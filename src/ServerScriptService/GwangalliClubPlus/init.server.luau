-- GwangalliClubPlus (server): CLUB OCEAN 광안 AAA show add-on. Drop-in: this Script +
-- ReplicatedStorage.GwangalliClubPlusShared + StarterPlayerScripts.GwangalliClubPlus. No existing script
-- is edited: orders / 합석 come from the club's public attributes (GwangalliClubShow Show / Tables /
-- Booking), money goes through ServerStorage.GwangalliGameplayAPI, the house parade is held through
-- ServerStorage.ClubShowHook.
--
--   Bridge    existing-system adapter (club attributes, hook, wallet, gates, ClubRanking)
--   Stage     the centre LED wall's timeline (paid / DJ cues around the club's own order intros)
--   Ranking   오늘의 큰손 / 후원 랭킹 / 최고가 주문 / 이번 주 랭킹 (OrderedDataStore + memory fallback)
--   Donate    전광판 후원 with in-game money (+ optional Robux developer products)
--   Receipts  ProcessReceipt router (installed only when products exist and nobody else claimed it)
--   Dj        guest DJ queue / turns / pad cues
--
-- Boot: shared contract -> folder + remotes -> context C -> modules -> loops -> folder parented.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")
local CollectionService = game:GetService("CollectionService")

local sharedModule = ReplicatedStorage:WaitForChild("GwangalliClubPlusShared", 60)
if not (sharedModule and sharedModule:IsA("ModuleScript")) then
	warn("[GwangalliClubPlus] ReplicatedStorage.GwangalliClubPlusShared is missing; the add-on is off")
	return
end
local okS, S = pcall(require, sharedModule)
if not okS or type(S) ~= "table" then
	warn("[GwangalliClubPlus] shared module failed:", S)
	return
end
local Cfg = S.Config
if not Cfg.Enabled then
	return
end
if ReplicatedStorage:FindFirstChild(S.Names.Folder) then
	warn("[GwangalliClubPlus] a second copy of the server script is running; this one stops")
	return
end

-- optional live kill switch (GwangalliLiveConfig: enabled("clubplus") == false turns the add-on off)
do
	local live = ReplicatedStorage:FindFirstChild("GwangalliLiveConfig")
	if live and live:IsA("ModuleScript") then
		local ok, Live = pcall(require, live)
		if ok and type(Live) == "table" and type(Live.enabled) == "function" then
			local okE, on = pcall(Live.enabled, "clubplus")
			if okE and on == false then
				return
			end
		end
	end
end

local Lines = S.Lines

-------------------------------------------------------------------------------------------------
-- folder + remotes (parented last, so clients see a complete contract)
-------------------------------------------------------------------------------------------------
local folder = Instance.new("Folder")
folder.Name = S.Names.Folder
local request = Instance.new("RemoteEvent")
request.Name = S.Names.Request
request.Parent = folder
local event = Instance.new("RemoteEvent")
event.Name = S.Names.Event
event.Parent = folder

-------------------------------------------------------------------------------------------------
-- context
-------------------------------------------------------------------------------------------------
local C: any = { S = S, Cfg = Cfg, folder = folder }

function C.now(): number
	return workspace:GetServerTimeNow()
end

function C.isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

local published: { [string]: string } = {}
function C.publish(attr: string, value: any)
	local s = S.encode(value)
	if not s then
		warn("[GwangalliClubPlus] publish", attr, "failed to encode")
		return
	end
	if published[attr] == s then
		return
	end
	published[attr] = s
	folder:SetAttribute(attr, s)
end

function C.send(p: Player, kind: string, payload: any)
	if C.isPlayer(p) then
		event:FireClient(p, kind, payload)
	end
end
function C.broadcast(kind: string, payload: any)
	event:FireAllClients(kind, payload)
end

-- pair = { title, body } from Lines; extra args format the body
function C.toast(p: Player, pair: { string }, kind: string?, icon: string?, ...: any)
	local body = pair[2] or ""
	if select("#", ...) > 0 then
		local ok, s = pcall(string.format, body, ...)
		if ok then
			body = s
		end
	end
	C.send(p, "toast", { title = pair[1], body = body, kind = kind or "club", icon = icon })
end

-- filtered display name (TextService broadcast filter; "손님" when it fails: never unfiltered)
local nameCache: { [number]: string } = {}
function C.filteredName(p: Player): string
	local cached = nameCache[p.UserId]
	if cached then
		return cached
	end
	local raw = p.DisplayName
	if type(raw) ~= "string" or raw == "" then
		raw = p.Name
	end
	raw = string.sub(raw, 1, 20)
	local out = "손님"
	local ok, res = pcall(function()
		local r = TextService:FilterStringAsync(raw, p.UserId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(res) == "string" and res ~= "" and not S.mostlyHashed(res) then
		out = res
	end
	nameCache[p.UserId] = out
	return out
end
function C.cachedName(uid: number): string?
	return nameCache[uid]
end

-- free text for the LED wall: nil = rejected (filter failed or came back mostly ####)
function C.filterText(p: Player, text: string): string?
	local ok, res = pcall(function()
		local r = TextService:FilterStringAsync(text, p.UserId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(res) ~= "string" or res == "" then
		return nil
	end
	if S.mostlyHashed(res) then
		return nil
	end
	return res
end

-- Roblox usernames for other servers' players on the boards (cached; usernames are moderated by Roblox)
local userCache: { [number]: string } = {}
function C.userName(uid: number): string?
	if userCache[uid] then
		return userCache[uid]
	end
	local p = Players:GetPlayerByUserId(uid)
	if p then
		userCache[uid] = p.Name
		return p.Name
	end
	if uid <= 0 then
		return nil
	end
	local ok, n = pcall(Players.GetNameFromUserIdAsync, Players, uid)
	if ok and type(n) == "string" then
		userCache[uid] = n
		return n
	end
	return nil
end

-- bindables of the existing systems (ServerStorage, looked up each time: they may load later)
local function bindable(name: string): BindableFunction?
	local b = ServerStorage:FindFirstChild(name)
	return if b and b:IsA("BindableFunction") then b else nil
end
local function invoke(b: BindableFunction?, ...: any): ...any
	if not b then
		return nil
	end
	local res = table.pack(pcall(b.Invoke, b, ...))
	if not res[1] then
		return nil
	end
	return table.unpack(res, 2, res.n)
end
function C.hook(method: string, ...: any): ...any
	return invoke(bindable(S.Names.ClubHook), method, ...)
end
function C.hasHook(): boolean
	return bindable(S.Names.ClubHook) ~= nil
end
function C.gameplay(op: string, p: Player, ...: any): ...any
	return invoke(bindable(S.Names.GameplayAPI), op, p, ...)
end
function C.hasWallet(): boolean
	return bindable(S.Names.GameplayAPI) ~= nil
end

function C.balance(p: Player): (number?, number?)
	if not C.hasWallet() then
		return nil, nil
	end
	local cash, bank = C.gameplay("balance", p)
	return if type(cash) == "number" then cash else nil, if type(bank) == "number" then bank else nil
end

-- money: onDone(status) exactly once, except a late success after a timeout which calls
-- onDone("paid-late") a second time. status: paid | paid-late | noapi | free | declined | error | timeout
function C.charge(p: Player, amount: number, label: string, onDone: (string) -> ())
	if amount <= 0 then
		onDone("free")
		return
	end
	if not C.hasWallet() then
		onDone("noapi")
		return
	end
	local settled, timedOut = false, false
	task.spawn(function()
		local res = C.gameplay("spend", p, math.floor(amount), label, "bank")
		if timedOut then
			if res == true then
				onDone("paid-late")
			end
			return
		end
		settled = true
		onDone(if res == true then "paid" elseif res == false then "declined" else "error")
	end)
	task.delay(8, function()
		if not settled then
			timedOut = true
			onDone("timeout")
		end
	end)
end

-- bank credits: labels carry 환불 / 정산 so pass perks never multiply them
function C.refund(p: Player, amount: number, label: string): boolean
	if amount <= 0 or not C.isPlayer(p) then
		return false
	end
	if not string.find(label, "환불", 1, true) then
		label ..= " 환불"
	end
	return C.gameplay("earn", p, math.floor(amount), label) == true
end
function C.payout(p: Player, amount: number, label: string): boolean
	if amount <= 0 or not C.isPlayer(p) then
		return false
	end
	if not string.find(label, "정산", 1, true) then
		label ..= " 정산"
	end
	return C.gameplay("earn", p, math.floor(amount), label) == true
end

function C.addStats(p: Player, delta: { [string]: number }, label: string)
	local d = {}
	for k, v in delta do
		if type(v) == "number" then
			d[k] = math.clamp(math.floor(v), -20, 20)
		end
	end
	task.spawn(C.gameplay, "addStats", p, d, label)
end

function C.root(p: Player): BasePart?
	local ch = p.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if r and r:IsA("BasePart") and hum and hum.Health > 0 then
		return r
	end
	return nil
end

function C.anchor(name: string): BasePart?
	for _, part in CollectionService:GetTagged("ClubShowAnchor") do
		if part.Name == name and part:IsA("BasePart") and part:IsDescendantOf(workspace) then
			return part
		end
	end
	return nil
end

-- admins: the place owner (user-owned places), Config.DJ.Admins, a group rank (cached per player)
local adminCache: { [number]: boolean } = {}
function C.isAdmin(p: Player): boolean
	local uid = p.UserId
	if adminCache[uid] ~= nil then
		return adminCache[uid]
	end
	local yes = false
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId == uid then
		yes = true
	end
	for _, id in Cfg.DJ.Admins do
		if id == uid then
			yes = true
		end
	end
	if not yes and game.CreatorType == Enum.CreatorType.Group and game.CreatorId > 0 then
		local ok, rank = pcall(p.GetRankInGroup, p, game.CreatorId)
		if ok and type(rank) == "number" and rank >= 255 then
			yes = true
		end
	end
	if not yes and Cfg.DJ.AdminGroupId > 0 then
		local ok, rank = pcall(p.GetRankInGroup, p, Cfg.DJ.AdminGroupId)
		if ok and type(rank) == "number" and rank >= Cfg.DJ.AdminMinRank then
			yes = true
		end
	end
	adminCache[uid] = yes
	return yes
end

-------------------------------------------------------------------------------------------------
-- modules
-------------------------------------------------------------------------------------------------
C.Bridge = require(script:WaitForChild("Bridge"))
C.Stage = require(script:WaitForChild("Stage"))
C.Ranking = require(script:WaitForChild("Ranking"))
C.Donate = require(script:WaitForChild("Donate"))
C.Receipts = require(script:WaitForChild("Receipts"))
C.Dj = require(script:WaitForChild("Dj"))

-- who may use the paid / DJ features right now: in a club room (not the street "Near" zone), with a
-- valid wristband (when the door system exists) and the club unlocked in the journey
function C.gate(p: Player): (boolean, string?)
	if not C.isPlayer(p) then
		return false, "gate"
	end
	if p:GetAttribute("GwJourneyClub") == "locked" then
		return false, "gate"
	end
	if not C.Bridge.inClub(p) then
		return false, "gate"
	end
	if Cfg.RequireWristband and not C.Bridge.wristband(p) then
		return false, "gate"
	end
	return true, nil
end

-------------------------------------------------------------------------------------------------
-- remote dispatch (token bucket per player; handlers validate their own payloads)
-------------------------------------------------------------------------------------------------
local buckets: { [Player]: { tokens: number, at: number } } = {}
local function take(p: Player): boolean
	local b = buckets[p]
	local t = os.clock()
	if not b then
		b = { tokens = Cfg.Rate.Burst, at = t }
		buckets[p] = b
	end
	b.tokens = math.min(Cfg.Rate.Burst, b.tokens + (t - b.at) * Cfg.Rate.PerSecond)
	b.at = t
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function menuFor(p: Player): any
	local m = C.Donate.menu(p)
	m.dj = C.Dj.stateFor(p)
	return m
end

local handlers: { [string]: (Player, { [string]: any }) -> () } = {
	menu = function(p)
		C.send(p, "menu", menuFor(p))
	end,
	donate = function(p, payload)
		C.Donate.request(p, payload)
	end,
	robux = function(p, payload)
		C.Donate.robuxIntent(p, payload)
	end,
	dj = function(p, payload)
		C.Dj.request(p, payload)
	end,
}

request.OnServerEvent:Connect(function(p: Player, op: any, payload: any)
	if type(op) ~= "string" or #op > 16 then
		return
	end
	if payload ~= nil and type(payload) ~= "table" then
		return
	end
	local h = handlers[op]
	if not h or not take(p) then
		return
	end
	local ok, err = pcall(h, p, payload or {})
	if not ok then
		warn("[GwangalliClubPlus] request", op, "failed:", err)
	end
end)

Players.PlayerRemoving:Connect(function(p: Player)
	buckets[p] = nil
	adminCache[p.UserId] = nil
	C.Donate.playerLeft(p)
	C.Dj.playerLeft(p)
	-- (nameCache stays: queued cues and boards keep showing the name)
end)

-------------------------------------------------------------------------------------------------
-- boot
-------------------------------------------------------------------------------------------------
C.Bridge.init(C)
C.Stage.init(C)
C.Ranking.init(C)
C.Donate.init(C)
C.Receipts.init(C)
C.Dj.init(C)

-- every club order: LED intro window on the stage timeline, rankings, ticker, rank badge
C.Bridge.onOrder(function(evt: any)
	local ledTier = S.orderTier(evt.price)
	if ledTier >= 2 then
		C.Stage.block(evt.at, evt.at + S.orderIntro(ledTier), "order")
	end
	C.Ranking.addOrder(evt)
	C.Stage.ticker("order", evt.n, string.format(Lines.Ticker.order, evt.table, evt.n, evt.label), evt.price)
	-- rank badge for the LED intro (ClubRanking publishes its own Top a moment after the same write)
	task.delay(0.8, function()
		local rank, total, gap = C.Ranking.spendRank(evt.u)
		local owner = Players:GetPlayerByUserId(evt.u)
		C.broadcast("order", {
			key = evt.key,
			source = evt.source,
			table = evt.table,
			u = evt.u,
			n = evt.n,
			un = owner and owner.Name or nil,
			label = evt.label,
			icon = evt.icon,
			price = evt.price,
			at = evt.at,
			arriveAt = evt.arriveAt,
			rank = rank,
			total = total,
			gap = gap,
			king = rank == 1,
			tier = ledTier,
		})
		if rank == 1 then
			C.Stage.ticker("king", evt.n, string.format(Lines.Ticker.king, evt.n), nil)
		end
	end)
end)

-- the 합석 이벤트's LED card owns the main screen for its intro
C.Bridge.onBooking(function(rec: any)
	if type(rec.at) == "number" and rec.at > 0 then
		C.Stage.block(rec.at, rec.at + S.Durations.booking, "booking")
	end
end)

folder:SetAttribute(S.Attr.Active, true)
folder.Parent = ReplicatedStorage

task.spawn(function()
	while true do
		task.wait(0.5)
		local now = C.now()
		for _, m in { C.Stage, C.Dj, C.Ranking, C.Donate } do
			local ok, err = pcall(m.tick, now)
			if not ok then
				warn("[GwangalliClubPlus] tick failed:", err)
			end
		end
	end
end)

game:BindToClose(function()
	pcall(C.Ranking.flush, true)
end)
