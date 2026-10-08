-- GwangalliGameplay/Profiles: player profiles (cash + bank ledger, stats, job / careers, home, message threads, offers, inventory,
-- outfit/hair) persisted in DataStore "GwangalliProfile_v1", key "u_<UserId>".
--   * load: UpdateAsync that claims a session lock ({job, t}); a lock held by another live server
--     (refreshed within LOCK_TTL) is waited on a few times, then taken over
--   * save: UpdateAsync (never blind SetAsync); a save is skipped when another server took the lock
--   * retries with backoff; autosave every 120 s (dirty only); save + release on leave; BindToClose
--   * no DataStore (unpublished place, Studio without API access, repeated errors): profiles live in
--     memory only; this is printed once
--   * a player whose data could not be read gets a fresh in-memory profile that is NEVER saved
--     (so a temporary outage cannot wipe real progress), and is told so once

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Profiles = {}

local LOCK_TTL = 330 -- seconds a session lock stays valid without refresh (autosave refreshes it)
local AUTOSAVE = 120
local RETRIES = 3
local MAX_THREAD = 30 -- messages kept per contact thread

local G: any
local Util: any
local ctx: any

local store: DataStore? = nil
local enabled = false
local disabledReason: string? = nil
local announced = false
local JOB = ""

type Meta = { loaded: boolean, dirty: boolean, noSave: boolean, saving: boolean, lastSave: number, released: boolean }
local data: { [Player]: any } = {}
local meta: { [Player]: Meta } = {}
local loading: { [Player]: boolean } = {}

local function announceDisabled(reason: string)
	enabled = false
	disabledReason = reason
	if not announced then
		announced = true
		print("[GwangalliGameplay] DataStore unavailable (" .. reason .. "): player profiles are kept in memory only this session.")
	end
end

local function isAccessError(err: string): boolean
	local e = string.lower(err)
	return string.find(e, "studio", 1, true) ~= nil
		or string.find(e, "api", 1, true) ~= nil and string.find(e, "access", 1, true) ~= nil
		or string.find(e, "publish", 1, true) ~= nil
		or string.find(e, "403", 1, true) ~= nil
		or string.find(e, "not allowed", 1, true) ~= nil
end

-------------------------------------------------------------------------------------------------
-- Schema (v2: life game). Old v1 saves: money -> cash, a fresh bank account, quests dropped,
-- message threads kept as plain history.
-------------------------------------------------------------------------------------------------
local function defaultData(): any
	local stats = {}
	for _, k in G.STAT_ORDER do
		stats[k] = G.STATS[k].start
	end
	local d = {
		v = G.VERSION,
		cash = G.START_CASH,
		bank = G.START_BANK,
		transactions = {},
		stats = stats,
		job = nil, -- { id, onShift is session-only }
		careers = {}, -- [jobId] = level
		careerXp = {}, -- [jobId] = xp
		shifts = 0, -- completed shifts (all jobs)
		earnedDay = { day = 0, amount = 0 },
		home = nil, -- { listingId, tier, owned, dueIn, missed, arrears, deposit }
		housing = G.defaultHousing(), -- furniture / storage / bills / loan / 집들이 (see G.sanitizeHousing)
		lifeDay = 1, -- the player's own in-game day counter
		messages = { threads = {} },
		offers = {}, -- [offerId] = { contact, t }
		offersSent = {}, -- [offerId] = unix time last sent
		waypoint = nil,
		inventory = {},
		owned = { outfits = {}, hair = {} },
		outfit = "default",
		hair = "default",
		buffs = {},
		gym = { sets = 0, day = 0, today = 0 },
		daily = { day = 0, counts = {}, clubDay = 0 },
		milestones = {},
		banking = if G.sanitizeBanking then G.sanitizeBanking(nil) else nil, -- 송금 한도 / 최근 보낸 사람 (Bank.luau)
		created = os.time(),
		lastLogin = os.time(),
		playSeconds = 0,
	}
	table.insert(d.transactions, { t = os.time(), amount = G.START_BANK, label = "BNK부산은행 통장 개설 (정착 지원금)", balance = G.START_BANK, account = "bank" })
	return d
end

local function num(v: any, default: number): number
	if G.isFiniteNumber(v) then
		return v
	end
	return default
end

local function sanitizeThread(t: any): any?
	if type(t) ~= "table" then
		return nil
	end
	local list = {}
	if type(t.list) == "table" then
		for _, m in t.list do
			if type(m) == "table" and type(m.text) == "string" then
				local from = if m.from == "me" or m.from == "system" then m.from else "them"
				table.insert(list, { from = from, text = G.clipText(m.text, 400), t = num(m.t, 0), clock = num(m.clock, 12) })
			end
		end
	end
	while #list > MAX_THREAD do
		table.remove(list, 1)
	end
	local offer = if type(t.offer) == "string" and G.OFFERS[t.offer] then t.offer else nil
	local special = if t.special == "rent" then "rent" else nil
	return { list = list, unread = math.clamp(math.floor(num(t.unread, 0)), 0, 99), offer = offer, special = special }
end

local function sanitizeHome(h: any): any?
	if type(h) ~= "table" or type(h.listingId) ~= "string" then
		return nil
	end
	local l = G.LISTINGS[h.listingId]
	if not l then
		return nil
	end
	return {
		listingId = h.listingId,
		tier = l.tier,
		owned = l.kind == "buy",
		dueIn = math.clamp(num(h.dueIn, G.DAY_SECONDS), 0, G.DAY_SECONDS),
		missed = math.clamp(math.floor(num(h.missed, 0)), 0, G.EVICT_AFTER),
		arrears = math.max(0, math.floor(num(h.arrears, 0))),
		deposit = if l.kind == "rent" then math.max(0, math.floor(num(h.deposit, l.deposit or 0))) else 0,
	}
end

-- Fills missing keys, clamps numbers, drops unknown ids. Never errors on garbage input.
local function sanitize(raw: any): any
	local d = defaultData()
	if type(raw) ~= "table" then
		return d
	end
	local v = num(raw.v, 1)
	if v < 2 then
		-- v1 migration: the old wallet becomes cash, and the player also gets the new bank account
		d.cash = G.clampMoney(num(raw.money, G.START_CASH))
	else
		d.cash = G.clampMoney(num(raw.cash, G.START_CASH))
		d.bank = G.clampMoney(num(raw.bank, G.START_BANK))
		d.transactions = {}
		if type(raw.transactions) == "table" then
			for _, tx in raw.transactions do
				if type(tx) == "table" and G.isFiniteNumber(tx.amount) and type(tx.label) == "string" then
					local entry: { [string]: any } = {
						t = num(tx.t, 0),
						amount = math.floor(tx.amount),
						label = G.clipText(tx.label, 120),
						balance = G.clampMoney(num(tx.balance, 0)),
						account = if tx.account == "cash" then "cash" else "bank",
					}
					-- bank meta (송금 / ATM / 현금 주기: kind, peer, peerId, memo, fee, ref, place)
					if G.ledgerMeta then
						for k, v in G.ledgerMeta(tx) do
							entry[k] = v
						end
					end
					table.insert(d.transactions, entry)
				end
			end
		end
		while #d.transactions > G.LEDGER_MAX do
			table.remove(d.transactions, 1)
		end
		if G.sanitizeBanking then
			d.banking = G.sanitizeBanking(raw.banking)
		end
	end
	if type(raw.stats) == "table" then
		for _, k in G.STAT_ORDER do
			d.stats[k] = G.clampStat(num(raw.stats[k], G.STATS[k].start))
		end
		if v < 2 then
			-- v1 stamina was a gym stat that started at 10; the life game uses it as energy
			d.stats.stamina = math.max(d.stats.stamina, G.STATS.stamina.start)
		end
	end
	if type(raw.job) == "table" and type(raw.job.id) == "string" and G.JOBS[raw.job.id] then
		d.job = { id = raw.job.id }
	end
	if type(raw.careerXp) == "table" then
		for id, x in raw.careerXp do
			if G.JOBS[id] and G.isFiniteNumber(x) and x >= 0 then
				d.careerXp[id] = math.floor(x)
				d.careers[id] = G.jobLevel(id, x)
			end
		end
	end
	if d.job and not d.careerXp[d.job.id] then
		d.careerXp[d.job.id] = 0
		d.careers[d.job.id] = 1
	end
	d.shifts = math.max(0, math.floor(num(raw.shifts, 0)))
	if type(raw.earnedDay) == "table" then
		d.earnedDay = { day = num(raw.earnedDay.day, 0), amount = math.max(0, math.floor(num(raw.earnedDay.amount, 0))) }
	end
	d.home = sanitizeHome(raw.home)
	d.housing = G.sanitizeHousing(raw.housing)
	G.reconcileHousing(d)
	d.lifeDay = math.max(1, math.floor(num(raw.lifeDay, 1)))
	local m = raw.messages
	if type(m) == "table" and type(m.threads) == "table" then
		for cid, t in m.threads do
			local id = G.resolveContact(cid)
			if id then
				d.messages.threads[id] = sanitizeThread(t)
			end
		end
	end
	if type(raw.offers) == "table" then
		for id, o in raw.offers do
			if G.OFFERS[id] and type(o) == "table" then
				d.offers[id] = { contact = G.OFFERS[id].contact, t = num(o.t, os.time()) }
			end
		end
	end
	if type(raw.offersSent) == "table" then
		for id, t in raw.offersSent do
			if G.OFFERS[id] and G.isFiniteNumber(t) then
				d.offersSent[id] = t
			end
		end
	end
	if type(raw.waypoint) == "string" and #raw.waypoint <= 80 then
		d.waypoint = raw.waypoint
	end
	if type(raw.inventory) == "table" then
		for id, c in raw.inventory do
			if G.ITEMS[id] and G.isFiniteNumber(c) and c > 0 then
				d.inventory[id] = math.min(math.floor(c), 9999)
			end
		end
	end
	if type(raw.owned) == "table" then
		if type(raw.owned.outfits) == "table" then
			for id, x in raw.owned.outfits do
				if G.CLOTHES[id] and x then
					d.owned.outfits[id] = true
				end
			end
		end
		if type(raw.owned.hair) == "table" then
			for id, x in raw.owned.hair do
				if G.SALON[id] and x then
					d.owned.hair[id] = true
				end
			end
		end
	end
	if type(raw.outfit) == "string" and G.CLOTHES[raw.outfit] and (raw.outfit == "default" or d.owned.outfits[raw.outfit]) then
		d.outfit = raw.outfit
	end
	if type(raw.hair) == "string" and G.SALON[raw.hair] and (raw.hair == "default" or d.owned.hair[raw.hair]) then
		d.hair = raw.hair
	end
	if type(raw.buffs) == "table" then
		for id, b in raw.buffs do
			if G.BUFFS[id] and type(b) == "table" then
				d.buffs[id] = { untilT = num(b.untilT, 0), sets = math.max(0, math.floor(num(b.sets, 0))) }
			end
		end
	end
	if type(raw.gym) == "table" then
		d.gym = { sets = math.max(0, math.floor(num(raw.gym.sets, 0))), day = num(raw.gym.day, 0), today = math.max(0, math.floor(num(raw.gym.today, 0))) }
	end
	if type(raw.daily) == "table" then
		d.daily.day = num(raw.daily.day, 0)
		d.daily.clubDay = num(raw.daily.clubDay, 0)
		if type(raw.daily.counts) == "table" then
			for id, c in raw.daily.counts do
				if G.ITEMS[id] and G.isFiniteNumber(c) then
					d.daily.counts[id] = math.max(0, math.floor(c))
				end
			end
		end
	end
	if type(raw.milestones) == "table" then
		for k, x in raw.milestones do
			if type(k) == "string" and x then
				d.milestones[k] = true
			end
		end
	end
	if type(raw.work) == "table" then d.work = raw.work end
	-- 치안 (GwangalliGameplay.Law sanitises its own record: 전과, jail time left, police job, crime career)
	if type(raw.law) == "table" then d.law = raw.law end
	-- 연료 per owned car id (GwangalliGameplay.Fuel)
	if type(raw.fuel) == "table" then d.fuel = raw.fuel end
	-- 총기상 relations per dealer id (GwangalliGameplay.WeaponDealer sanitises its own slice)
	if type(raw.dealer) == "table" then d.dealer = raw.dealer end
	-- 전투·범죄·경찰 (GwangalliGameplay.Crime): 전과 / unpaid fines / last arrests only (the live wanted level never persists)
	if type(raw.crime) == "table" then
		local arrests = {}
		if type(raw.crime.arrests) == "table" then
			for _, a in raw.crime.arrests do
				if type(a) == "table" and #arrests < 8 then
					table.insert(arrests, {
						t = num(a.t, 0),
						fine = math.max(0, math.floor(num(a.fine, 0))),
						paid = math.max(0, math.floor(num(a.paid, 0))),
						crimes = if type(a.crimes) == "string" then G.clipText(a.crimes, 80) else "",
					})
				end
			end
		end
		d.crime = {
			record = math.clamp(math.floor(num(raw.crime.record, 0)), 0, 100000),
			debt = math.clamp(math.floor(num(raw.crime.debt, 0)), 0, 100000000),
			arrests = arrests,
		}
	end
	d.created = num(raw.created, os.time())
	d.playSeconds = math.max(0, num(raw.playSeconds, 0))
	d.lastLogin = os.time()
	d.v = G.VERSION
	return d
end
Profiles.sanitize = function(raw: any)
	return sanitize(raw)
end
Profiles.defaultData = function()
	return defaultData()
end

-------------------------------------------------------------------------------------------------
-- DataStore IO
-------------------------------------------------------------------------------------------------
local function keyOf(player: Player): string
	return G.KEY_PREFIX .. tostring(player.UserId)
end

local function waitBudget(kind: Enum.DataStoreRequestType)
	for _ = 1, 20 do
		local ok, budget = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, kind)
		if not ok or budget > 0 then
			return
		end
		task.wait(0.5)
	end
end

-- Returns (ok, data | nil, lockedByOtherServer)
local function claim(player: Player, force: boolean): (boolean, any, boolean)
	local s = store
	if not s then
		return false, nil, false
	end
	local result: any = nil
	local lockedOther = false
	waitBudget(Enum.DataStoreRequestType.UpdateAsync)
	local ok, err = pcall(function()
		s:UpdateAsync(keyOf(player), function(old: any)
			lockedOther = false
			if type(old) == "table" and type(old._lock) == "table" and old._lock.job ~= JOB and not force then
				local t = old._lock.t
				if G.isFiniteNumber(t) and os.time() - t < LOCK_TTL then
					lockedOther = true
					result = nil
					return nil -- keep the other server's lock; retry later
				end
			end
			local d = sanitize(old)
			result = { data = d, existed = type(old) == "table" }
			local out = Util.deepCopy(d)
			out._lock = { job = JOB, t = os.time() }
			return out
		end)
	end)
	if not ok then
		return false, tostring(err), false
	end
	return true, result, lockedOther
end

local function writeProfile(player: Player, d: any, release: boolean): boolean
	local s = store
	if not s then
		return false
	end
	local snapshot = Util.deepCopy(d)
	for attempt = 1, RETRIES do
		waitBudget(Enum.DataStoreRequestType.UpdateAsync)
		local stolen = false
		local ok, err = pcall(function()
			s:UpdateAsync(keyOf(player), function(old: any)
				stolen = false
				if type(old) == "table" and type(old._lock) == "table" and old._lock.job ~= JOB then
					local t = old._lock.t
					if G.isFiniteNumber(t) and os.time() - t < LOCK_TTL then
						stolen = true
						return nil
					end
				end
				local out = Util.deepCopy(snapshot)
				out._lock = if release then nil else { job = JOB, t = os.time() }
				out.savedAt = os.time()
				return out
			end)
		end)
		if ok then
			if stolen then
				warn(string.format("[GwangalliGameplay] %s: another server holds the session; save skipped", player.Name))
				return false
			end
			return true
		end
		warn(string.format("[GwangalliGameplay] save %s failed (try %d): %s", player.Name, attempt, tostring(err)))
		if attempt < RETRIES then
			task.wait(2 ^ attempt)
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------------------------
function Profiles.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	JOB = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
	if game.PlaceId == 0 then
		announceDisabled("place not published")
	else
		local ok, res = pcall(DataStoreService.GetDataStore, DataStoreService, G.DATASTORE)
		if ok and res then
			store = res
			enabled = true
		else
			announceDisabled(tostring(res))
		end
	end
end

function Profiles.enabled(): boolean
	return enabled
end

function Profiles.get(player: Player): any?
	local m = meta[player]
	if m and m.loaded then
		return data[player]
	end
	return nil
end

function Profiles.isLoaded(player: Player): boolean
	local m = meta[player]
	return m ~= nil and m.loaded
end

-- Waits (up to `timeout`) for the profile.
function Profiles.wait(player: Player, timeout: number): any?
	local t0 = os.clock()
	while player.Parent == Players and os.clock() - t0 < timeout do
		local d = Profiles.get(player)
		if d then
			return d
		end
		task.wait(0.25)
	end
	return Profiles.get(player)
end

function Profiles.markDirty(player: Player)
	local m = meta[player]
	if m then
		m.dirty = true
	end
end

-- Loads (yields). Calls onLoaded(player, data, info) when done; info = { fresh, noSave, message? }.
function Profiles.load(player: Player, onLoaded: (Player, any, any) -> ())
	if loading[player] or meta[player] then
		return
	end
	loading[player] = true
	local d: any = nil
	local noSave = false
	local fresh = false
	local message: string? = nil
	if enabled and store then
		local tries = 0
		local lockedTries = 0
		while player.Parent == Players do
			tries += 1
			local ok, res, locked = claim(player, lockedTries >= 3)
			if ok and not locked and type(res) == "table" then
				d = res.data
				fresh = not res.existed
				break
			elseif ok and locked then
				lockedTries += 1
				task.wait(3)
			else
				local err = tostring(res)
				if isAccessError(err) then
					announceDisabled(err)
					break
				end
				warn(string.format("[GwangalliGameplay] load %s failed (try %d): %s", player.Name, tries, err))
				if tries >= RETRIES then
					noSave = true
					message = "저장 서버에 연결하지 못했어요. 이번 접속의 진행 상황은 저장되지 않아요."
					break
				end
				task.wait(2 ^ tries)
			end
		end
	end
	loading[player] = nil
	if player.Parent ~= Players then
		-- left while loading: release the lock we may have claimed
		if d and enabled and not noSave then
			task.spawn(writeProfile, player, d, true)
		end
		return
	end
	if not d then
		d = defaultData()
		fresh = true
	end
	if not enabled then
		noSave = true
	end
	data[player] = d
	meta[player] = { loaded = true, dirty = false, noSave = noSave, saving = false, lastSave = os.clock(), released = false }
	player:SetAttribute(G.Attr.ProfileReady, true)
	onLoaded(player, d, { fresh = fresh, noSave = noSave, message = message })
end

function Profiles.save(player: Player, release: boolean): boolean
	local m = meta[player]
	local d = data[player]
	if not m or not d or not m.loaded then
		return false
	end
	if m.noSave or not enabled then
		m.dirty = false
		return true
	end
	while m.saving do
		task.wait(0.2)
	end
	if m.released then
		return true
	end
	m.saving = true
	local wasDirty = m.dirty
	m.dirty = false
	local ok = writeProfile(player, d, release)
	m.saving = false
	m.lastSave = os.clock()
	if not ok then
		m.dirty = m.dirty or wasDirty
	end
	if release then
		m.released = true
	end
	return ok
end

-- True when this player's profile is written to the DataStore (false: memory only -- Studio /
-- unpublished place, or a fresh fallback profile after a failed load). The bank refuses to move
-- money between a saved and a memory-only profile (a memory-only one could be re-created at will).
function Profiles.persistent(player: Player): boolean
	local m = meta[player]
	return m ~= nil and m.loaded and enabled and not m.noSave
end

-- Profiles are saved in memory-only mode too? (false = the whole server runs without a DataStore)
function Profiles.storeEnabled(): boolean
	return enabled
end

-- Money moved between players: save soon (coalesced; at least SOON_GAP s apart per key so the
-- DataStore per-key write limit is respected). The bank calls it for the payer first.
local SOON_GAP = 7
local soonPending: { [Player]: boolean } = {}
function Profiles.saveSoon(player: Player, delay: number?)
	local m = meta[player]
	if not m or not m.loaded or m.released then
		return
	end
	m.dirty = true
	if soonPending[player] or m.noSave or not enabled then
		return
	end
	soonPending[player] = true
	task.spawn(function()
		local wait = math.max(delay or 0.5, SOON_GAP - (os.clock() - m.lastSave))
		task.wait(wait)
		soonPending[player] = nil
		local mm = meta[player]
		if mm and mm.loaded and not mm.released and player.Parent == Players then
			pcall(Profiles.save, player, false)
		end
	end)
end

-- Save + release on leave, then forget.
function Profiles.release(player: Player)
	local m = meta[player]
	if m and m.loaded then
		local d = data[player]
		if d then
			d.playSeconds = (d.playSeconds or 0) + math.max(0, os.clock() - (ctx.session(player).joinedAt or os.clock()))
		end
		Profiles.save(player, true)
	end
	data[player] = nil
	meta[player] = nil
end

function Profiles.startAutosave()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for _, player in Players:GetPlayers() do
				local m = meta[player]
				if m and m.loaded and not m.released and (m.dirty or os.clock() - m.lastSave > LOCK_TTL * 0.5) then
					task.spawn(Profiles.save, player, false)
					task.wait(0.5)
				end
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for _, player in Players:GetPlayers() do
			local m = meta[player]
			if m and m.loaded and not m.released then
				pending += 1
				task.spawn(function()
					pcall(Profiles.save, player, true)
					pending -= 1
				end)
			end
		end
		local t0 = os.clock()
		local limit = if RunService:IsStudio() then 5 else 25
		while pending > 0 and os.clock() - t0 < limit do
			task.wait(0.1)
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Views for the client (see the PROFILE VIEW contract in GwangalliGameplayShared)
-------------------------------------------------------------------------------------------------
local function round1(v: number): number
	return math.floor(v * 10 + 0.5) / 10
end

local function statsView(d: any): any
	local out = {}
	for _, k in G.STAT_ORDER do
		out[k] = round1(d.stats[k] or 0)
	end
	return out
end

local function threadView(cid: string, t: any): any
	local c = G.CONTACTS[cid]
	local list = {}
	for i, m in t.list do
		list[i] = { from = m.from, text = m.text, t = m.t, clock = m.clock }
	end
	local choices = nil
	if t.offer then
		choices = { { id = "accept", label = "수락할게요 👍" }, { id = "decline", label = "다음에요" } }
	elseif t.special == "rent" then
		choices = { { id = "pay", label = "지금 납부하기" }, { id = "later", label = "나중에" } }
	end
	return {
		contact = cid,
		name = c.name,
		role = c.role,
		icon = c.icon,
		color = c.color,
		list = list,
		msgs = list,
		unread = t.unread or 0,
		choices = choices,
		offerId = t.offer,
	}
end

local function lastT(t: any): number
	local l = t.list
	return if #l > 0 then l[#l].t else 0
end

local function threadOrder(d: any): { string }
	local order = {}
	for cid in d.messages.threads do
		table.insert(order, cid)
	end
	table.sort(order, function(a, b)
		local ta, tb = lastT(d.messages.threads[a]), lastT(d.messages.threads[b])
		if ta ~= tb then
			return ta > tb
		end
		return a < b
	end)
	return order
end

local function buffsView(d: any): any
	local now = os.time()
	local out = {}
	for id, b in d.buffs do
		local def = G.BUFFS[id]
		if b.sets and b.sets > 0 then
			out[id] = { sets = b.sets, name = def and def.name or id }
		elseif b.untilT and b.untilT > now then
			out[id] = { seconds = b.untilT - now, name = def and def.name or id }
		end
	end
	return out
end

local function jobView(d: any, player: Player?): any
	local j = d.job
	if not j or not G.JOBS[j.id] then
		return false -- false (not nil) so a partial ProfileChanged can clear it
	end
	local def = G.JOBS[j.id]
	local xp = d.careerXp[j.id] or 0
	local lv = G.jobLevel(j.id, xp)
	local onShift = false
	if player and ctx and ctx.onShift then
		local ok, res = pcall(ctx.onShift, player)
		onShift = ok and res == true
	end
	return {
		id = j.id,
		title = def.title,
		place = def.place,
		icon = def.icon,
		level = lv,
		levelTitle = def.levels[lv].title,
		xp = xp,
		nextXp = G.nextLevelXp(j.id, lv),
		wage = G.jobWage(j.id, lv),
		taskPay = G.taskPay(j.id, lv),
		onShift = onShift,
	}
end

local function homeView(d: any): any
	local h = d.home
	if not h then
		return false
	end
	local l = G.LISTINGS[h.listingId]
	if not l then
		return false
	end
	return {
		listingId = h.listingId,
		tier = h.tier,
		name = l.name,
		place = l.place,
		icon = l.icon,
		owned = h.owned,
		rentPerDay = G.homeDaily(h.listingId),
		dueIn = math.max(0, math.floor(h.dueIn or 0)),
		missed = h.missed or 0,
		arrears = h.arrears or 0,
		deposit = h.deposit or 0,
		value = if h.owned then G.homeValue(h, d) else nil,
		tierKey = l.tierKey,
	}
end

local function contactsView(_d: any): any
	local out = {}
	for _, id in G.CONTACT_ORDER do
		local c = G.CONTACTS[id]
		table.insert(out, { id = id, name = c.name, role = c.role, icon = c.icon, color = c.color, kind = c.kind })
	end
	return out
end

local function offersView(d: any): any
	local out = {}
	for id, o in d.offers do
		local def = G.OFFERS[id]
		if def then
			table.insert(out, { id = id, contact = def.contact, title = def.title, body = def.text, kind = if def.action then def.action.type else "info", t = o.t })
		end
	end
	table.sort(out, function(a, b)
		return (a.t or 0) > (b.t or 0)
	end)
	return out
end

local VIEWS: { [string]: (any, Player?) -> any } = {
	cash = function(d)
		return d.cash
	end,
	money = function(d)
		return d.cash
	end,
	bank = function(d)
		return d.bank
	end,
	netWorth = function(d)
		return G.netWorth(d)
	end,
	transactions = function(d)
		return Util.deepCopy(d.transactions)
	end,
	stats = statsView,
	job = jobView,
	careers = function(d)
		return Util.deepCopy(d.careers)
	end,
	home = homeView,
	threads = function(d)
		local out = {}
		for cid, t in d.messages.threads do
			out[cid] = threadView(cid, t)
		end
		return out
	end,
	threadOrder = threadOrder,
	unread = function(d)
		local n = 0
		for _, t in d.messages.threads do
			n += t.unread or 0
		end
		return n
	end,
	contacts = contactsView,
	offers = offersView,
	waypoint = function(d)
		return d.waypoint or false
	end,
	inventory = function(d)
		return Util.deepCopy(d.inventory)
	end,
	outfit = function(d)
		return d.outfit
	end,
	hair = function(d)
		return d.hair
	end,
	owned = function(d)
		return Util.deepCopy(d.owned)
	end,
	buffs = buffsView,
	housing = function(d)
		return G.housingView(d)
	end,
	clock = function(d)
		return { day = d.lifeDay or 1, shifts = d.shifts or 0 }
	end,
}
Profiles.VIEW_KEYS = {
	"cash", "money", "bank", "netWorth", "transactions", "stats", "job", "careers", "home",
	"threads", "threadOrder", "unread", "contacts", "offers", "waypoint", "inventory", "outfit",
	"hair", "owned", "buffs", "clock", "housing",
}
-- ctx.changed(player, key) with one of these keys also refreshes the listed view keys.
local EXPAND: { [string]: { string } } = {
	cash = { "cash", "money", "netWorth", "transactions" },
	money = { "cash", "money", "netWorth", "transactions" },
	bank = { "bank", "netWorth", "transactions" },
	home = { "home", "netWorth", "clock", "housing" },
	housing = { "housing", "netWorth" },
	messages = { "threads", "threadOrder", "unread", "offers" },
	threads = { "threads", "threadOrder", "unread", "offers" },
	offers = { "threads", "threadOrder", "unread", "offers" },
	job = { "job", "careers", "clock" },
}

-- Full view, or only `keys` ({ [key] = true }).
function Profiles.view(player: Player, keys: { [string]: boolean }?): any?
	local d = Profiles.get(player)
	if not d then
		return nil
	end
	local want: { [string]: boolean }? = nil
	if keys then
		local w: { [string]: boolean } = {}
		for k in keys do
			local ex = EXPAND[k]
			if ex then
				for _, e in ex do
					w[e] = true
				end
			else
				w[k] = true
			end
		end
		want = w
	end
	local out = {}
	for _, k in Profiles.VIEW_KEYS do
		if not want or want[k] then
			local ok, v = pcall(VIEWS[k], d, player)
			if ok then
				out[k] = v
			else
				warn("[GwangalliGameplay] view " .. k .. " failed: " .. tostring(v))
			end
		end
	end
	return out
end

Profiles.MAX_THREAD = MAX_THREAD

return Profiles
