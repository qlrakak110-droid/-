-- GwangalliLiveOps (server): LIVE UPDATES for every running server, no restart (docs/LIVE_UPDATES.md).
--
--   * boot: loads the config document from DataStore "GwangalliLiveConfig_v1" key "current",
--     validates it (ReplicatedStorage.GwangalliLiveConfig) and writes it into the game's data tables
--     (prices, pay, fares, rent, club menu, drone show...), so gameplay code needs no changes.
--   * MessagingService topic "GwangalliLiveConfig": "version N exists" -> every server re-reads the
--     DataStore (the source of truth) within ~1 s; a 60 s poll catches missed messages.
--   * versioning: every commit bumps `version` with a compare-and-swap UpdateAsync (two admins at once
--     never overwrite each other: the loser re-applies its change on top); the last 20 versions are
--     kept under key "history" -> rollback to any of them.
--   * clients: ReplicatedStorage.GwangalliLive (Folder) = snapshot attributes (L_<key>, Version,
--     HappyHourActive, Mode) + Doc (StringValue, public JSON) + Changed (RemoteEvent) + Admin
--     (RemoteFunction, admins only, re-checked on every call).
--   * server scripts: ServerStorage.GwangalliLiveOpsAPI (BindableFunction) :Invoke(op, ...):
--       "get", key -> value | "doc" -> public doc | "version" | "mode" | "happy" -> bool
--       "commit", opName, args, note -> {ok, v?, err?}  (trusted: server code)
--       "history" -> {{v, at, by, note}} | "reload"
--     ServerStorage.GwangalliLiveOpsChanged (BindableEvent): (version, changedKeys).
--   * admins: the game owner (user game) / owning group's rank >= 254, GwangalliLiveConfig.ADMINS,
--     the live `admins` list (owner-only). Unpublished places (Studio play test, PlaceId 0 in the web
--     player / simulator) treat the local tester as the owner.
--   * chat commands (admins): /live help | show <key> | set <key> <value> | reset <key> |
--     ann <text> | unann <id> | rollback <version> | drone | fireworks | clock <hour>
--   * text typed in-game (announcements, NPC lines, item names) goes through TextService filtering
--     before it is shown to other players (Roblox rule); Open Cloud text is developer content.

local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local TAG = "[GwangalliLiveOps] "

local function service(name: string): any
	local ok, s = pcall(function()
		return game:GetService(name)
	end)
	return if ok then s else nil
end
local DataStoreService = service("DataStoreService")
local MessagingService = service("MessagingService")
local TextService = service("TextService")
local GroupService = service("GroupService")

local function requireOptional(parent: Instance, name: string, wait: number?): any
	local m = if wait then parent:WaitForChild(name, wait) else parent:FindFirstChild(name)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn(TAG .. name .. " failed to load: " .. tostring(res))
	return nil
end

local LC = requireOptional(ReplicatedStorage, "GwangalliLiveConfig", 30)
if not LC then
	warn(TAG .. "ReplicatedStorage.GwangalliLiveConfig missing; live updates disabled")
	return
end
local G = requireOptional(ReplicatedStorage, "GwangalliGameplayShared", 30)
local Club = requireOptional(ReplicatedStorage, "ClubShared", 10)
local Config = requireOptional(ReplicatedStorage, "GwangalliConfig", 10)
local Shared = requireOptional(ReplicatedStorage, "GwangalliShared", 10)

-------------------------------------------------------------------------------------------------
-- Instances
-------------------------------------------------------------------------------------------------
local function child(parent: Instance, name: string, className: string): any
	local c = parent:FindFirstChild(name)
	if c and c.ClassName ~= className then
		c:Destroy()
		c = nil
	end
	if not c then
		c = Instance.new(className)
		c.Name = name
		c.Parent = parent
	end
	return c
end

local folder = ReplicatedStorage:FindFirstChild(LC.FOLDER)
if folder and not folder:IsA("Folder") then
	folder:Destroy()
	folder = nil
end
if not folder then
	folder = Instance.new("Folder")
	folder.Name = LC.FOLDER
end
local docValue = child(folder, LC.DOC_VALUE, "StringValue")
local changedRemote = child(folder, LC.REMOTE_CHANGED, "RemoteEvent")
local adminRemote = child(folder, LC.REMOTE_ADMIN, "RemoteFunction")
folder:SetAttribute("Version", 0)
folder:SetAttribute("Mode", "starting")
folder:SetAttribute("HappyHourActive", false)
folder.Parent = ReplicatedStorage

local api = child(ServerStorage, LC.API_NAME, "BindableFunction")
local changedEvent = child(ServerStorage, LC.CHANGED_NAME, "BindableEvent")

-------------------------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------------------------
local current: any = LC.emptyDoc()
local mode = "local" -- "datastore" once the store answered
local store: any = nil
local subscribed = false
local messagingOk = MessagingService ~= nil -- false once the service says it does not exist here
local happyActive = false
local localHistory: { any } = {} -- {v, at, by, note, doc}, newest last (mirror of the store's)
local applier = LC.newApplier({ G = G, Club = Club, Config = Config, WS = workspace }, "server")

local function unpublished(): boolean
	local ok, studio = pcall(function()
		return RunService:IsStudio()
	end)
	return game.PlaceId == 0 or (ok and studio == true)
end

local function log(msg: string)
	print(TAG .. msg)
end

-------------------------------------------------------------------------------------------------
-- Snapshot for clients
-------------------------------------------------------------------------------------------------
local function publishSnapshot(doc: any)
	local json = LC.jsonEncode(LC.publicDoc(doc)) or "{}"
	docValue.Value = json -- first: readers cache by this string
	for _, f in LC.FIELDS do
		if f.type ~= "clocklist" then
			folder:SetAttribute(LC.attrName(f.key), LC.valueIn(doc, f.key))
		end
	end
	folder:SetAttribute("UpdatedAt", doc.updatedAt or 0)
	folder:SetAttribute("UpdatedBy", doc.updatedBy or 0)
	folder:SetAttribute("Mode", mode)
	folder:SetAttribute("Version", doc.version or 0) -- last
end

local function rememberHistory(doc: any)
	for _, h in localHistory do
		if h.v == doc.version then
			return
		end
	end
	table.insert(localHistory, { v = doc.version, at = doc.updatedAt, by = doc.updatedBy, note = doc.note, doc = LC.deepCopy(doc) })
	table.sort(localHistory, function(a, b)
		return a.v < b.v
	end)
	while #localHistory > LC.HISTORY_MAX do
		table.remove(localHistory, 1)
	end
end

local function annIds(doc: any): { [string]: boolean }
	local s = {}
	for _, a in (doc and doc.announcements) or {} do
		s[a.id] = true
	end
	return s
end

local refreshAdminFlags: () -> () -- defined with the admin checks below

-- Makes `doc` (validated) the live config on this server.
local function applyDoc(doc: any, reason: string)
	local prev = current
	current = doc
	rememberHistory(doc)
	local ok, changed = pcall(function()
		return applier:apply(doc, happyActive)
	end)
	if not ok then
		warn(TAG .. "apply failed: " .. tostring(changed))
		changed = {}
	end
	publishSnapshot(doc)
	local keys = LC.diffKeys(prev, doc)
	local seen = annIds(prev)
	local fresh = {}
	for _, a in LC.activeAnnouncements(doc, os.time()) do
		if not seen[a.id] then
			table.insert(fresh, a)
		end
	end
	if table.find(keys, "admins") and refreshAdminFlags then
		refreshAdminFlags()
	end
	if #keys > 0 or #fresh > 0 or prev.version ~= doc.version then
		changedRemote:FireAllClients({ v = doc.version, keys = keys, announce = fresh, by = doc.updatedBy, note = doc.note })
		changedEvent:Fire(doc.version, keys)
		log(string.format("v%d applied (%s): %d settings changed, %d data writes%s", doc.version, reason, #keys, #changed, if doc.note ~= "" then " - " .. doc.note else ""))
	end
end

-------------------------------------------------------------------------------------------------
-- DataStore
-------------------------------------------------------------------------------------------------
local function readStore(key: string): (boolean, any)
	if not store then
		return false, "no store"
	end
	local opts: any = nil
	pcall(function()
		local o = Instance.new("DataStoreGetOptions")
		o.UseCache = false -- a fresh read: GetAsync caches for 4 s per server
		opts = o
	end)
	return pcall(function()
		if opts then
			return store:GetAsync(key, opts)
		end
		return store:GetAsync(key)
	end)
end

local function appendHistory(doc: any)
	if mode ~= "datastore" then
		return
	end
	task.spawn(function()
		local entry = { v = doc.version, at = doc.updatedAt, by = doc.updatedBy, note = doc.note, doc = doc }
		for attempt = 1, 3 do
			local ok, err = pcall(function()
				store:UpdateAsync(LC.KEY_HISTORY, function(old: any)
					local list = if type(old) == "table" and type(old.list) == "table" then old.list else {}
					for _, h in list do
						if type(h) == "table" and h.v == entry.v then
							return nil -- already there
						end
					end
					table.insert(list, entry)
					while #list > LC.HISTORY_MAX do
						table.remove(list, 1)
					end
					return { list = list }
				end)
			end)
			if ok then
				return
			end
			warn(TAG .. "history write failed: " .. tostring(err))
			task.wait(attempt * 2)
		end
	end)
end

local function readHistory(): { any }
	if mode == "datastore" then
		local ok, v = readStore(LC.KEY_HISTORY)
		if ok and type(v) == "table" and type(v.list) == "table" then
			local out = {}
			for _, h in v.list do
				if type(h) == "table" and type(h.v) == "number" and type(h.doc) == "table" then
					table.insert(out, h)
				end
			end
			-- merge what this server saw (e.g. Open Cloud versions written without history)
			for _, h in localHistory do
				local have = false
				for _, o in out do
					if o.v == h.v then
						have = true
					end
				end
				if not have then
					table.insert(out, h)
				end
			end
			table.sort(out, function(a, b)
				return a.v < b.v
			end)
			return out
		end
	end
	return localHistory
end

-------------------------------------------------------------------------------------------------
-- Admins
-------------------------------------------------------------------------------------------------
local ownerCache: { [Player]: { at: number, v: boolean } } = {}
local groupOwnerId: number? = nil

local function creatorType(): string
	local ok, t = pcall(function()
		return game.CreatorType
	end)
	if ok and t == Enum.CreatorType.Group then
		return "group"
	end
	return "user"
end

local function isOwner(player: Player): boolean
	if unpublished() then
		return true
	end
	if creatorType() == "user" then
		return player.UserId == game.CreatorId
	end
	local c = ownerCache[player]
	if c and os.clock() - c.at < 60 then
		return c.v
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(game.CreatorId)
	end)
	local v = ok and type(rank) == "number" and rank >= 254
	ownerCache[player] = { at = os.clock(), v = v }
	return v
end

-- Admin by id alone (message publishers): owner id, baked list, live list.
local function isAdminId(userId: number): boolean
	if table.find(LC.ADMINS, userId) or table.find(current.admins or {}, userId) then
		return true
	end
	if creatorType() == "user" then
		return userId == game.CreatorId and userId ~= 0
	end
	if groupOwnerId == nil and GroupService then
		local ok, info = pcall(function()
			return GroupService:GetGroupInfoAsync(game.CreatorId)
		end)
		groupOwnerId = if ok and type(info) == "table" and type(info.Owner) == "table" then tonumber(info.Owner.Id) or 0 else 0
	end
	return groupOwnerId ~= nil and groupOwnerId ~= 0 and userId == groupOwnerId
end

local function isAdmin(player: Player): boolean
	return isOwner(player) or isAdminId(player.UserId)
end

function refreshAdminFlags()
	for _, p in Players:GetPlayers() do
		task.spawn(function()
			p:SetAttribute(LC.ADMIN_ATTR, isAdmin(p))
		end)
	end
end

-- MessagingService publishers: our own servers and the Open Cloud tool. Players cannot publish,
-- but a message naming a random non-admin as its author is still refused (defense in depth).
local function publisherAllowed(by: number, src: string): boolean
	if unpublished() then
		return true
	end
	if by == 0 then
		return src == "opencloud" or src == "server-api"
	end
	return isAdminId(by)
end

-------------------------------------------------------------------------------------------------
-- Publishing
-------------------------------------------------------------------------------------------------
local function publish(doc: any, by: number, src: string)
	if not MessagingService or not messagingOk then
		return
	end
	local msg: string
	if mode == "datastore" then
		msg = LC.jsonEncode({ t = "cfg", v = doc.version, by = by, src = src }) :: string
	else
		msg = LC.buildMessage(doc, by, src) -- no store: inline the doc when it fits (1 kB)
	end
	task.spawn(function()
		for attempt = 1, 3 do
			local ok, err = pcall(function()
				MessagingService:PublishAsync(LC.TOPIC, msg)
			end)
			if ok then
				return
			end
			if string.find(tostring(err), "not a valid member", 1, true) then
				messagingOk = false -- Studio / test harness without MessagingService
				return
			end
			if attempt == 3 then
				warn(TAG .. "publish failed (other servers will pick it up within " .. LC.POLL_SECONDS .. " s): " .. tostring(err))
			end
			task.wait(attempt)
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Reload (messages, poll)
-------------------------------------------------------------------------------------------------
local reloadWanted = 0
local reloading = false

local function loadFromStore(reason: string): boolean
	local ok, v = readStore(LC.KEY_CURRENT)
	if not ok then
		return false
	end
	if v == nil then
		return true
	end
	local clean, errs, notes = LC.validate(v)
	if not clean then
		warn(TAG .. "stored config rejected (kept v" .. current.version .. "): " .. table.concat(errs, " | "))
		return true
	end
	if #notes > 0 then
		warn(TAG .. "stored config: " .. table.concat(notes, " | "))
	end
	if clean.version > current.version then
		applyDoc(clean, reason)
	end
	return true
end

local function requestReload(target: number)
	reloadWanted = math.max(reloadWanted, target)
	if reloading then
		return
	end
	reloading = true
	task.spawn(function()
		-- the write may not be visible yet: retry with backoff until the announced version shows up
		for _, delay in { 0, 1, 2, 4, 8 } do
			if delay > 0 then
				task.wait(delay)
			end
			loadFromStore("message")
			if current.version >= reloadWanted then
				break
			end
		end
		reloading = false
	end)
end

local lastMessageAt = 0
local function onMessage(message: any)
	local data = if type(message) == "table" then message.Data else nil
	local msg, why = LC.parseMessage(data)
	if not msg then
		warn(TAG .. "message ignored: " .. tostring(why))
		return
	end
	if msg.v <= current.version then
		return -- old or our own
	end
	if not publisherAllowed(msg.by, msg.src) then
		warn(string.format("%smessage v%d refused: publisher %d (%s) is not an admin", TAG, msg.v, msg.by, msg.src))
		return
	end
	-- a flood of messages costs at most one DataStore read per second
	local now = os.clock()
	if now - lastMessageAt < 1 and reloading then
		reloadWanted = math.max(reloadWanted, msg.v)
		return
	end
	lastMessageAt = now
	if mode == "datastore" then
		requestReload(msg.v)
	elseif msg.d then
		local clean, errs = LC.validate(msg.d)
		if not clean then
			warn(TAG .. "message v" .. msg.v .. " rejected: " .. table.concat(errs, " | "))
		elseif clean.version ~= msg.v then
			warn(TAG .. "message version mismatch")
		elseif clean.version > current.version then
			applyDoc(clean, "message")
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Commit (serialized on this server; compare-and-swap across servers)
-------------------------------------------------------------------------------------------------
local lockBusy = false
local function withLock(fn: () -> any): any
	local t0 = os.clock()
	while lockBusy do
		if os.clock() - t0 > 30 then
			return { ok = false, err = "다른 변경을 처리 중이에요" }
		end
		task.wait(0.05)
	end
	lockBusy = true
	local ok, res = pcall(fn)
	lockBusy = false
	if not ok then
		warn(TAG .. "commit error: " .. tostring(res))
		return { ok = false, err = "서버 오류: " .. tostring(res) }
	end
	return res
end

-- mutate(baseDoc) -> newDoc | nil, err. opts {owner = bool, src = string}
local function commit(mutate: (any) -> (any, string?), actor: number, note: string?, opts: any?): any
	local o = opts or {}
	return withLock(function()
		for attempt = 1, 5 do
			local base = current
			local token = current.version -- stored version the compare-and-swap expects
			if mode == "datastore" then
				local ok, v = readStore(LC.KEY_CURRENT)
				if not ok then
					if attempt == 5 then
						return { ok = false, err = "저장소를 읽지 못했어요 (잠시 후 다시)" }
					end
					task.wait(attempt)
					continue
				end
				token = if type(v) == "table" and type(v.version) == "number" then v.version else 0
				if type(v) == "table" then
					local clean = LC.validate(v)
					if clean then
						if clean.version > current.version then
							applyDoc(clean, "refresh")
						end
						base = clean
					end
					-- an invalid stored doc is overwritten on top of what this server runs
				end
			end
			local nd, err = mutate(LC.deepCopy(base))
			if not nd then
				return { ok = false, err = err or "변경 실패" }
			end
			if not LC.same(nd.admins or {}, base.admins or {}) and not o.owner then
				return { ok = false, err = "관리자 목록은 게임 주인만 바꿀 수 있어요" }
			end
			if #LC.diffKeys(base, nd) == 0 then
				return { ok = true, v = base.version, unchanged = true } -- nothing to save: no empty versions
			end
			nd.schema = LC.SCHEMA
			nd.version = math.max(token, base.version) + 1
			nd.updatedAt = os.time()
			nd.updatedBy = actor
			nd.note = if type(note) == "string" then LC.clip(note, 120) else ""
			local clean, errs = LC.validate(nd, { strict = true })
			if not clean then
				return { ok = false, err = errs[1], errors = errs }
			end
			if mode == "datastore" then
				local conflict = false
				local okW, errW = pcall(function()
					store:UpdateAsync(LC.KEY_CURRENT, function(old: any)
						conflict = false
						local oldV = if type(old) == "table" and type(old.version) == "number" then old.version else 0
						if oldV ~= token then
							conflict = true
							return nil -- someone else wrote first: abort, re-read, re-apply
						end
						return clean
					end)
				end)
				if not okW then
					warn(TAG .. "store write failed: " .. tostring(errW))
					if attempt == 5 then
						return { ok = false, err = "저장 실패 (잠시 후 다시)" }
					end
					task.wait(attempt)
					continue
				end
				if conflict then
					continue
				end
				appendHistory(clean)
			end
			applyDoc(clean, "commit by " .. tostring(actor))
			publish(clean, actor, o.src or "server")
			return { ok = true, v = clean.version }
		end
		return { ok = false, err = "동시에 수정하는 사람이 많아요. 다시 시도해 주세요" }
	end)
end

local function commitOp(actor: number, op: string, a: any, b: any, note: string?, opts: any?): any
	return commit(function(base: any)
		return LC.applyOp(base, op, a, b, os.time())
	end, actor, note, opts)
end

local function rollbackTo(actor: number, version: number, opts: any?): any
	local target = nil
	if version == 0 then
		target = { v = 0, doc = LC.emptyDoc() } -- v0 = the game's built-in defaults, always available
	end
	for _, h in readHistory() do
		if h.v == version then
			target = h
		end
	end
	if not target then
		return { ok = false, err = "그 버전은 기록에 없어요 (최근 " .. LC.HISTORY_MAX .. "개만 보관)" }
	end
	-- an old version may carry keys a newer place no longer knows: keep what is still valid
	local old, errs = LC.validate(target.doc)
	if not old then
		return { ok = false, err = "그 버전은 지금 규칙에 맞지 않아요: " .. tostring(errs[1]) }
	end
	return commit(function(base: any)
		local d = LC.deepCopy(old)
		d.admins = base.admins -- rollbacks never change who is admin
		return d
	end, actor, "되돌리기 → v" .. version, opts)
end

-------------------------------------------------------------------------------------------------
-- Text filtering (Roblox: player-typed text shown to others must be filtered)
-------------------------------------------------------------------------------------------------
local function filterText(text: any, userId: number): (string?, string?)
	if type(text) ~= "string" then
		return nil, "글자가 아니에요"
	end
	if unpublished() or not TextService then
		return text, nil
	end
	local ok, res = pcall(function()
		local r = TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(res) == "string" then
		return res, nil
	end
	return nil, "글자 필터를 통과하지 못했어요 (잠시 후 다시)"
end

-------------------------------------------------------------------------------------------------
-- Admin operations (panel, chat, API)
-------------------------------------------------------------------------------------------------
local function historySummary(): { any }
	local out = {}
	for _, h in readHistory() do
		table.insert(out, { v = h.v, at = h.at, by = h.by, note = h.note })
	end
	return out
end

local function state(owner: boolean): any
	return {
		ok = true,
		doc = LC.deepCopy(current),
		mode = mode,
		subscribed = subscribed,
		happy = happyActive,
		owner = owner,
		history = historySummary(),
		serverTime = os.time(),
		jobId = game.JobId,
		unpublished = unpublished(),
	}
end

local function str(v: any, max: number): string?
	if type(v) ~= "string" then
		return nil
	end
	return LC.clip(v, max)
end

-- actor = UserId (0 = server code); owner = may change the admin list.
local function handleOp(actor: number, op: string, args: any, owner: boolean, src: string?): any
	local a = if type(args) == "table" then args else {}
	local cOpts = { owner = owner, src = src or "server" }
	if op == "state" then
		return state(owner)
	elseif op == "history" then
		return { ok = true, history = historySummary() }
	elseif op == "set" then
		local key = str(a.key, 64)
		if not key or not LC.BY_KEY[key] then
			return { ok = false, err = "모르는 설정이에요" }
		end
		local v, why = LC.parseInput(key, a.value)
		if v == nil then
			return { ok = false, err = LC.BY_KEY[key].label .. ": " .. tostring(why) }
		end
		if LC.BY_KEY[key].type == "string" then
			local ft, fwhy = filterText(v, actor)
			if not ft then
				return { ok = false, err = fwhy }
			end
			v = ft
		end
		return commitOp(actor, "set", key, v, LC.BY_KEY[key].label .. " → " .. LC.describe(key, v), cOpts)
	elseif op == "reset" then
		local key = str(a.key, 64)
		if not key or not LC.BY_KEY[key] then
			return { ok = false, err = "모르는 설정이에요" }
		end
		return commitOp(actor, "reset", key, nil, LC.BY_KEY[key].label .. " 기본값", cOpts)
	elseif op == "resetAll" then
		return commitOp(actor, "resetAll", nil, nil, "모든 설정 기본값", cOpts)
	elseif op == "announce" then
		local text, why = filterText(str(a.text, 400), actor)
		if not text then
			return { ok = false, err = why }
		end
		local minutes = tonumber(a.minutes) or 60
		return commitOp(actor, "announce", { text = text, style = str(a.style, 12), minutes = minutes, banner = a.banner == true }, nil, "공지: " .. LC.clip((string.gsub(text, "%s+", " ")), 40), cOpts)
	elseif op == "unannounce" then
		return commitOp(actor, "unannounce", str(a.id, 24), nil, "공지 내림", cOpts)
	elseif op == "npcLine" then
		local id = str(a.id, 40)
		local text = str(a.text, 400)
		if text and text ~= "" then
			local ft, why = filterText(text, actor)
			if not ft then
				return { ok = false, err = why }
			end
			text = ft
		end
		return commitOp(actor, "npcLine", id, text, "NPC 대사 · " .. tostring(id), cOpts)
	elseif op == "itemPrice" then
		local price = if a.price == nil or a.price == false then nil else tonumber(a.price)
		return commitOp(actor, "itemPrice", str(a.id, 40), price, "상품 가격 · " .. tostring(a.id), cOpts)
	elseif op == "catalogAdd" then
		local it = if type(a.item) == "table" then LC.deepCopy(a.item) else nil
		if not it then
			return { ok = false, err = "상품 정보가 없어요" }
		end
		for _, k in { "name", "desc" } do
			if it[k] ~= nil then
				local ft, why = filterText(it[k], actor)
				if not ft then
					return { ok = false, err = why }
				end
				it[k] = ft
			end
		end
		return commitOp(actor, "catalogAdd", it, nil, "상품 추가 · " .. tostring(it.name), cOpts)
	elseif op == "catalogRemove" then
		return commitOp(actor, "catalogRemove", str(a.id, 40), nil, "상품 내림 · " .. tostring(a.id), cOpts)
	elseif op == "rollback" then
		local v = tonumber(a.version)
		if not v then
			return { ok = false, err = "버전 번호가 필요해요" }
		end
		return rollbackTo(actor, math.floor(v), cOpts)
	elseif op == "admins" then
		if not owner then
			return { ok = false, err = "관리자 목록은 게임 주인만 바꿀 수 있어요" }
		end
		local list = {}
		if type(a.list) == "table" then
			for _, id in a.list do
				local n = tonumber(id)
				if n then
					table.insert(list, math.floor(n))
				end
			end
		end
		local res = commitOp(actor, "admins", list, nil, "관리자 목록 변경", cOpts)
		refreshAdminFlags()
		return res
	elseif op == "droneNow" then
		return commitOp(actor, "set", "events.droneShow.startAt", os.time() + 3, "드론쇼 지금 시작", cOpts)
	elseif op == "fireworksNow" then
		return commitOp(actor, "set", "events.fireworks.startAt", os.time() + 3, "불꽃축제 지금 시작", cOpts)
	elseif op == "setClock" then
		local h = tonumber(a.hour)
		if not h or h < 0 or h >= 24 then
			return { ok = false, err = "0 ~ 24 사이 시각" }
		end
		workspace:SetAttribute("GwangalliSetClock", h) -- this server's clock (each server has its own)
		return { ok = true, v = current.version }
	end
	return { ok = false, err = "모르는 명령: " .. tostring(op) }
end

-- Remote: admins only, re-checked every call; rate limited.
local calls: { [Player]: { number } } = {}
local deniedLogAt: { [Player]: number } = {}
local function rateOk(player: Player, limit: number, window: number): boolean
	local now = os.clock()
	local list = calls[player] or {}
	calls[player] = list
	while #list > 0 and now - list[1] > window do
		table.remove(list, 1)
	end
	if #list >= limit then
		return false
	end
	table.insert(list, now)
	return true
end

adminRemote.OnServerInvoke = function(player: Player, op: any, args: any)
	if type(op) ~= "string" or #op > 24 then
		return { ok = false, err = "잘못된 요청" }
	end
	if not rateOk(player, 12, 10) then
		return { ok = false, err = "너무 빨라요. 잠시 후 다시 해 주세요" }
	end
	if not isAdmin(player) then
		local last = deniedLogAt[player]
		if not last or os.clock() - last > 60 then -- one log line per player per minute
			deniedLogAt[player] = os.clock()
			warn(string.format("%sdenied: %s (%d) tried %s", TAG, player.Name, player.UserId, op))
		end
		return { ok = false, err = "권한이 없어요" }
	end
	local ok, res = pcall(handleOp, player.UserId, op, args, isOwner(player), "server")
	if not ok then
		warn(TAG .. "admin op " .. op .. " failed: " .. tostring(res))
		return { ok = false, err = "서버 오류" }
	end
	return res
end

-- Clients never send on Changed; ignore anything that arrives.
changedRemote.OnServerEvent:Connect(function() end)

api.OnInvoke = function(op: any, a: any, b: any, c: any)
	if op == "get" then
		return LC.valueIn(current, a)
	elseif op == "doc" then
		return LC.publicDoc(current)
	elseif op == "version" then
		return current.version
	elseif op == "mode" then
		return mode
	elseif op == "happy" then
		return happyActive
	elseif op == "history" then
		return historySummary()
	elseif op == "reload" then
		task.spawn(loadFromStore, "api")
		return true
	elseif op == "commit" then
		if type(a) ~= "string" then
			return { ok = false, err = "명령 이름이 필요해요" }
		end
		local res = handleOp(0, a, b, false, "server-api")
		if type(c) == "string" and type(res) == "table" then
			res.note = c
		end
		return res
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- Chat commands
-------------------------------------------------------------------------------------------------
local function reply(player: Player, text: string, kind: string?)
	changedRemote:FireClient(player, { reply = text, kind = kind or "info" })
end

local HELP = "/live show <키> · set <키> <값> · reset <키> · ann <공지> · unann <id> · rollback <버전> · drone · fireworks · clock <시> · keys"

local function onChat(player: Player, text: string)
	if type(text) ~= "string" then
		return
	end
	local cmd, rest = string.match(text, "^/live%s*(%S*)%s*(.-)%s*$")
	if cmd == nil then
		return
	end
	if not isAdmin(player) then
		return
	end
	if not rateOk(player, 12, 10) then
		return
	end
	local owner = isOwner(player)
	local res: any = nil
	if cmd == "" or cmd == "help" then
		reply(player, HELP)
		return
	elseif cmd == "keys" then
		local keys = {}
		for _, f in LC.FIELDS do
			if not f.hidden then
				table.insert(keys, f.key)
			end
		end
		reply(player, table.concat(keys, ", "))
		return
	elseif cmd == "show" then
		local f = LC.BY_KEY[rest]
		if not f then
			reply(player, "모르는 키: " .. rest .. " (/live keys)", "warn")
			return
		end
		reply(player, string.format("%s = %s (v%d)", f.label, LC.describe(rest, LC.valueIn(current, rest)), current.version))
		return
	elseif cmd == "set" then
		local key, value = string.match(rest, "^(%S+)%s+(.+)$")
		res = handleOp(player.UserId, "set", { key = key, value = value }, owner)
	elseif cmd == "reset" then
		res = handleOp(player.UserId, "reset", { key = rest }, owner)
	elseif cmd == "ann" then
		res = handleOp(player.UserId, "announce", { text = rest, minutes = 60 }, owner)
	elseif cmd == "unann" then
		res = handleOp(player.UserId, "unannounce", { id = rest }, owner)
	elseif cmd == "rollback" then
		res = handleOp(player.UserId, "rollback", { version = tonumber(rest) }, owner)
	elseif cmd == "drone" then
		res = handleOp(player.UserId, "droneNow", {}, owner)
	elseif cmd == "fireworks" then
		res = handleOp(player.UserId, "fireworksNow", {}, owner)
	elseif cmd == "clock" then
		res = handleOp(player.UserId, "setClock", { hour = tonumber(rest) }, owner)
	else
		reply(player, "모르는 명령. " .. HELP, "warn")
		return
	end
	if type(res) == "table" and res.ok then
		reply(player, "적용됨 ✅ v" .. tostring(res.v or current.version), "success")
	else
		reply(player, "실패: " .. tostring(res and res.err), "error")
	end
end

-------------------------------------------------------------------------------------------------
-- Players
-------------------------------------------------------------------------------------------------
local function onPlayer(player: Player)
	task.spawn(function()
		player:SetAttribute(LC.ADMIN_ATTR, isAdmin(player))
	end)
	pcall(function()
		player.Chatted:Connect(function(msg: string)
			onChat(player, msg)
		end)
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(p: Player)
	calls[p] = nil
	ownerCache[p] = nil
	deniedLogAt[p] = nil
end)

-------------------------------------------------------------------------------------------------
-- Boot
-------------------------------------------------------------------------------------------------
do
	-- capture the game's own values before anything is overridden
	local ok, err = pcall(function()
		applier:apply(current, false)
	end)
	if not ok then
		warn(TAG .. "baseline capture failed: " .. tostring(err))
	end
	publishSnapshot(current)
end

if DataStoreService then
	local okGet, s = pcall(function()
		return DataStoreService:GetDataStore(LC.DATASTORE)
	end)
	if okGet and s then
		store = s
		local okRead = false
		for attempt = 1, 3 do
			local ok, v = readStore(LC.KEY_CURRENT)
			if ok then
				okRead = true
				mode = "datastore"
				if v ~= nil then
					local clean, errs, notes = LC.validate(v)
					if clean then
						if #notes > 0 then
							warn(TAG .. "stored config: " .. table.concat(notes, " | "))
						end
						applyDoc(clean, "boot")
					else
						warn(TAG .. "stored config rejected, using defaults: " .. table.concat(errs, " | "))
					end
				end
				break
			end
			-- "publish this place to the web" / "Studio access to APIs is not allowed": no retry needed
			local msg = tostring(v)
			if string.find(msg, "publish", 1, true) or string.find(msg, "Studio", 1, true) or string.find(msg, "not allowed", 1, true) then
				break
			end
			task.wait(attempt * 2)
		end
		if not okRead then
			store = nil
		end
	end
end
if mode ~= "datastore" then
	log("DataStore unavailable (Studio / test): live config works on this server only; changes are not saved")
end
publishSnapshot(current)

if MessagingService then
	task.spawn(function()
		for attempt = 1, 5 do
			local ok, err = pcall(function()
				MessagingService:SubscribeAsync(LC.TOPIC, onMessage)
			end)
			if ok then
				subscribed = true
				return
			end
			if attempt == 5 or string.find(tostring(err), "not a valid member", 1, true) then
				log("MessagingService unavailable: " .. tostring(err))
				if string.find(tostring(err), "not a valid member", 1, true) then
					messagingOk = false
				end
				return
			end
			task.wait(2 ^ attempt)
		end
	end)
end

-- poll: missed messages / Open Cloud writes without a message still arrive within a minute
task.spawn(function()
	while true do
		task.wait(LC.POLL_SECONDS)
		if mode == "datastore" and not reloading then
			pcall(loadFromStore, "poll")
		end
	end
end)

-------------------------------------------------------------------------------------------------
-- Time-based events: happy hour window, 불꽃축제 schedule, manual "start now" actions
-------------------------------------------------------------------------------------------------
local function clockNow(): number
	if Shared and Shared.clockNow then
		local ok, c = pcall(Shared.clockNow)
		if ok and type(c) == "number" then
			return c
		end
	end
	return Lighting.ClockTime
end

local function crossed(a: number, b: number, t: number): boolean
	if a == b then
		return false
	end
	if a < b then
		return t > a and t <= b
	end
	return t > a or t <= b -- wrapped past midnight
end

local function startDroneShow()
	workspace:SetAttribute("GwangalliStartDroneShow", true)
end

local function startFireworks(why: string)
	startDroneShow() -- the drone show sequence ends with the fireworks formation
	local title = LC.valueIn(current, "events.fireworks.title")
	changedRemote:FireAllClients({ v = current.version, keys = {}, announce = { { id = "fw_" .. os.time(), text = title .. " 시작! 바다 쪽을 보세요 🎆", style = "event" } } })
	log("fireworks started (" .. why .. ")")
end

local handledStart = {
	drone = LC.valueIn(current, "events.droneShow.startAt"),
	fireworks = LC.valueIn(current, "events.fireworks.startAt"),
}
-- a server that boots inside the 2-minute window of a manual start still joins in
if os.time() < handledStart.drone + 120 then
	handledStart.drone = 0
end
if os.time() < handledStart.fireworks + 120 then
	handledStart.fireworks = 0
end

local lastClock = clockNow()
while true do
	task.wait(2)
	local ok, err = pcall(function()
		local clock = clockNow()
		local h = LC.happyActiveAt(current, clock)
		if h ~= happyActive then
			happyActive = h
			applier:apply(current, h)
			folder:SetAttribute("HappyHourActive", h)
			changedRemote:FireAllClients({ v = current.version, keys = { "happyHour" }, happy = h })
			changedEvent:Fire(current.version, { "happyHour" })
			log("happy hour " .. (if h then "started" else "ended"))
		end
		if LC.valueIn(current, "events.fireworks.enabled") then
			for _, t in LC.valueIn(current, "events.fireworks.times") do
				-- a normal tick moves the clock forward a little; a jump (GwangalliSetClock) never fires
				local forward = (clock - lastClock) % 24
				if forward > 0 and forward < 1 and crossed(lastClock, clock, t) then
					startFireworks("schedule " .. LC.clockText(t))
					break
				end
			end
		end
		lastClock = clock
		local now = os.time()
		local ds = LC.valueIn(current, "events.droneShow.startAt")
		if ds > handledStart.drone and now >= ds and now < ds + 120 then
			handledStart.drone = ds
			startDroneShow()
			log("drone show started (admin)")
		end
		local fs = LC.valueIn(current, "events.fireworks.startAt")
		if fs > handledStart.fireworks and now >= fs and now < fs + 120 then
			handledStart.fireworks = fs
			startFireworks("admin")
		end
	end)
	if not ok then
		warn(TAG .. "event tick failed: " .. tostring(err))
	end
end
