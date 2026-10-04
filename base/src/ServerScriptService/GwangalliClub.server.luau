-- GwangalliClub (server): the CLUB OCEAN 광안 show layer on top of Club.server (docs/CLUB_SHOW.md).
--   * BottleService: the bottle menu (server prices from GwangalliClubShowShared.Menu), orders paid
--     through the life-game ledger (ServerStorage.GwangalliGameplayAPI "spend", bank first, cash
--     fallback), table ownership for the night (Tables), the door's "테이블 예약 입장".
--   * Show: one bottle-service show at a time (others queue): ONE folder attribute write per show
--     (Show = JSON); every client plays the choreography locally (staff line with sparkler fountains,
--     LED wall thanks with the filtered player name, spotlight, DJ shout-out, crowd cheer, confetti).
--     The house parade (Club.server) is held while a show runs; ClubLights' sparkler bottles land
--     on the table when the staff arrive (ClubShowHook "stamp").
--   * Booking: the 합석 이벤트 (friends hanging out, all-ages framing): the MD walks 2-4 roster
--     guests (GwangalliCitizens, adults, mixed) to the table; 짠 / 같이 춤 / 번호 교환 / 잘 가요
--     actions; affinity through ServerStorage.GwangalliSocialAPI (table / club / drink / dance /
--     number sources, capped by the social system itself).
-- Remotes (ReplicatedStorage.GwangalliClubShow): ShowEvent (server -> client), ShowRequest (client
-- -> server, token bucket per player). ServerStorage.GwangalliClubAPI: openMenu / reserve /
-- hasTable / ownsTable (Club.server's table prompt and door use it).
-- Cost: no per-frame work; a 0.5 s housekeeping loop; JSON attributes change only on events.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")

local function requireShared(name: string, timeout: number): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, timeout)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliClub] " .. name .. " failed to load:", res)
	return nil
end

local ShowShared = requireShared("GwangalliClubShowShared", 30)
local ClubShared = requireShared("ClubShared", 30)
if not ShowShared or not ClubShared then
	warn("[GwangalliClub] shared modules missing; club show layer disabled")
	return
end
local Citizens = requireShared("GwangalliCitizens", 20)

-- the module folder shares this script's name: find it by class
local folder: Instance? = nil
for _, c in script.Parent:GetChildren() do
	if c:IsA("Folder") and c.Name == "GwangalliClub" then
		folder = c
		break
	end
end
if not folder then
	warn("[GwangalliClub] module folder ServerScriptService.GwangalliClub missing; club show layer disabled")
	return
end

---------------------------------------------------------------------------------------------------
-- Remotes (folder parented last: a client that finds it finds both remotes)
---------------------------------------------------------------------------------------------------
local rfolder = ReplicatedStorage:FindFirstChild(ShowShared.Folder)
if rfolder and not rfolder:IsA("Folder") then
	rfolder:Destroy()
	rfolder = nil
end
local fresh = rfolder == nil
if not rfolder then
	local f = Instance.new("Folder")
	f.Name = ShowShared.Folder
	rfolder = f
end
local function remote(name: string): RemoteEvent
	local r = (rfolder :: Instance):FindFirstChild(name)
	if r and not r:IsA("RemoteEvent") then
		r:Destroy()
		r = nil
	end
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = rfolder
	end
	return r :: RemoteEvent
end
local event = remote(ShowShared.Remote.Event)
local request = remote(ShowShared.Remote.Request)
if fresh then
	(rfolder :: Instance).Parent = ReplicatedStorage
end

---------------------------------------------------------------------------------------------------
-- Context shared by the modules
---------------------------------------------------------------------------------------------------
local C: any = {
	Shared = ShowShared,
	Club = ClubShared,
	Citizens = Citizens,
	folder = rfolder,
	event = event,
}

function C.now(): number
	return workspace:GetServerTimeNow()
end

function C.isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

local function bindable(name: string): BindableFunction?
	local f = ServerStorage:FindFirstChild(name)
	return if f and f:IsA("BindableFunction") then f else nil
end

local function invoke(f: BindableFunction?, ...: any): ...any
	if not f then
		return nil
	end
	local res = table.pack(pcall(f.Invoke, f, ...))
	if not res[1] then
		warn("[GwangalliClub]", f.Name, "failed:", res[2])
		return nil
	end
	return table.unpack(res, 2, res.n)
end

function C.hook(method: string, ...: any): ...any
	return invoke(bindable(ShowShared.HOOK_NAME), method, ...)
end
function C.gameplay(op: string, plr: Player, ...: any): ...any
	return invoke(bindable((ClubShared.Names and ClubShared.Names.GameplayAPI) or "GwangalliGameplayAPI"), op, plr, ...)
end
function C.hasGameplay(): boolean
	return bindable((ClubShared.Names and ClubShared.Names.GameplayAPI) or "GwangalliGameplayAPI") ~= nil
end
function C.social(method: string, plr: Player, ...: any): ...any
	return invoke(bindable("GwangalliSocialAPI"), method, plr, ...)
end

function C.send(plr: Player, kind: string, payload: any)
	if plr.Parent == Players then
		event:FireClient(plr, kind, payload)
	end
end

function C.toast(plr: Player, title: string, body: string?, icon: string?, kind: string?)
	C.send(plr, "toast", { title = title, body = body or "", icon = icon or "🎶", kind = kind or "club" })
end

function C.aa(): boolean
	return ShowShared.allAges()
end

function C.clock(): number
	local ok, v = pcall(function()
		return Lighting.ClockTime
	end)
	return if ok and type(v) == "number" then v else 22
end

-- JSON folder attributes (only the server writes them)
function C.publish(attr: string, value: any)
	local ok, s = pcall(HttpService.JSONEncode, HttpService, value)
	if ok and type(s) == "string" then
		(rfolder :: Instance):SetAttribute(attr, s)
	else
		warn("[GwangalliClub] publish", attr, "failed:", s)
	end
end

-- Filtered display name for the LED wall / DJ / guests' lines (TextService broadcast filter;
-- "손님" when filtering fails: an unfiltered name is never shown).
local nameCache: { [Player]: string } = {}
function C.filteredName(plr: Player): string
	local cached = nameCache[plr]
	if cached then
		return cached
	end
	local raw = plr.DisplayName
	if type(raw) ~= "string" or raw == "" then
		raw = plr.Name
	end
	raw = string.sub(raw, 1, 20)
	local out = "손님"
	local ok, res = pcall(function()
		local r = TextService:FilterStringAsync(raw, plr.UserId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(res) == "string" and res ~= "" and not string.find(res, "^#+$") then
		out = res
	end
	nameCache[plr] = out
	return out
end

-- Show anchors (built by club_front.luau: tag ClubShowAnchor, looked up by name)
function C.anchor(name: string): BasePart?
	for _, p in CollectionService:GetTagged(ShowShared.Tags.Anchor) do
		if p.Name == name and p:IsA("BasePart") and p:IsDescendantOf(workspace) then
			return p
		end
	end
	return nil
end

-- Walking path from `lead` (points before the route) along the ParadeRoute points to the table
-- at `dest`: ClubShared.paradePath with a spherecast clear check against the furniture.
local clearParams = RaycastParams.new()
clearParams.FilterType = Enum.RaycastFilterType.Exclude
local function legClear(a: Vector3, b: Vector3): boolean
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = d.Magnitude
	if len < 2.5 then
		return true
	end
	local dir = d.Unit * (len - 2)
	local okS, hit = pcall(function()
		return (workspace :: any):Spherecast(a, 1.1, dir, clearParams)
	end)
	if okS then
		return hit == nil
	end
	local okR, h = pcall(function()
		return workspace:Raycast(a + Vector3.new(0, 0.6, 0), dir, clearParams)
	end)
	return not (okR and h)
end

function C.pathTo(lead: { Vector3 }, route: { Vector3 }, dest: Vector3, tableModel: Instance?): ({ Vector3 }, number)
	local list: { Vector3 } = {}
	for _, p in lead do
		table.insert(list, p)
	end
	for _, p in route do
		table.insert(list, p)
	end
	if #list < 2 then
		local start = list[1] or dest
		local pts = { start, Vector3.new(dest.X, start.Y, dest.Z) }
		return pts, ClubShared.pathLength(pts)
	end
	local ex: { Instance } = {}
	for _, npc in CollectionService:GetTagged((ClubShared.Tags and ClubShared.Tags.NPC) or "ClubNPC") do
		table.insert(ex, npc)
	end
	if tableModel then
		table.insert(ex, tableModel)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ex, p.Character)
		end
	end
	clearParams.FilterDescendantsInstances = ex
	local pts, len = ClubShared.paradePath(list, dest, ClubShared.PARADE_MAX_LEG or 60, ClubShared.PARADE_EXTEND or 48, legClear)
	if not pts then
		pts = table.clone(list)
		table.insert(pts, Vector3.new(dest.X, list[#list].Y, dest.Z))
		len = ClubShared.pathLength(pts)
	end
	return pts :: { Vector3 }, len
end

function C.tableModel(tableId: string): Instance?
	for _, m in CollectionService:GetTagged((ClubShared.Tags and ClubShared.Tags.Table) or "ClubTable") do
		local id = m:GetAttribute("TableId")
		if (id == tableId or m.Name == tableId) and m:IsDescendantOf(workspace) then
			return m
		end
	end
	return nil
end

-- money: onDone(status) once: "paid" | "paid-late" | "noapi" (no life-game: free) | "free" |
-- "declined" | "error" | "timeout"
function C.charge(plr: Player, amount: number, label: string, onDone: (string) -> ())
	if amount <= 0 then
		onDone("free")
		return
	end
	if not C.hasGameplay() then
		onDone("noapi")
		return
	end
	local settled, timedOut = false, false
	task.spawn(function()
		local res = C.gameplay("spend", plr, amount, label, "bank")
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

function C.won(n: number): string
	local s = tostring(math.floor(n))
	repeat
		local k
		s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s .. "원"
end

---------------------------------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------------------------------
local function load(name: string): any
	local m = (folder :: Instance):FindFirstChild(name)
	if not m or not m:IsA("ModuleScript") then
		warn("[GwangalliClub] module missing:", name)
		return nil
	end
	local ok, res = pcall(require, m)
	if not ok or type(res) ~= "table" then
		warn("[GwangalliClub] module failed:", name, res)
		return nil
	end
	return res
end

local Show = load("Show")
local BottleService = load("BottleService")
local Booking = load("Booking")
C.Show, C.BottleService, C.Booking = Show, BottleService, Booking
for _, m in { Show, BottleService, Booking } do
	if m and type(m.init) == "function" then
		local ok, err = pcall(m.init, C)
		if not ok then
			warn("[GwangalliClub] init failed:", err)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Server API for Club.server (table prompt, door)
---------------------------------------------------------------------------------------------------
do
	local f = ServerStorage:FindFirstChild(ShowShared.API_NAME)
	if f and not f:IsA("BindableFunction") then
		f:Destroy()
		f = nil
	end
	if not f then
		f = Instance.new("BindableFunction")
		f.Name = ShowShared.API_NAME
		f.Parent = ServerStorage
	end
	(f :: BindableFunction).OnInvoke = function(op: any, plr: any, a: any): any
		if not C.isPlayer(plr) or not BottleService then
			return nil
		end
		if op == "openMenu" then
			return BottleService.openMenu(plr, a, true)
		elseif op == "reserve" then
			return BottleService.reserve(plr, a)
		elseif op == "hasTable" then
			return BottleService.tableOf(plr)
		elseif op == "ownsTable" then
			return BottleService.owns(plr, a)
		end
		return nil
	end
end

---------------------------------------------------------------------------------------------------
-- Client requests (token bucket: 6 tokens, 1.5 / s)
---------------------------------------------------------------------------------------------------
local buckets: { [Player]: { tokens: number, t: number } } = {}
local function allowed(plr: Player): boolean
	local now = os.clock()
	local b = buckets[plr]
	if not b then
		b = { tokens = 6, t = now }
		buckets[plr] = b
	end
	b.tokens = math.min(6, b.tokens + (now - b.t) * 1.5)
	b.t = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

request.OnServerEvent:Connect(function(plr: Player, op: any, a: any, b: any)
	if not C.isPlayer(plr) or type(op) ~= "string" or not allowed(plr) then
		return
	end
	local ok, err = pcall(function()
		if op == "menu" and BottleService then
			BottleService.openMenu(plr, a, false)
		elseif op == "order" and BottleService then
			BottleService.order(plr, a, b)
		elseif op == "booking" and Booking then
			Booking.request(plr, a)
		elseif op == "act" and Booking then
			Booking.act(plr, a)
		end
	end)
	if not ok then
		warn("[GwangalliClub] request", op, "failed:", err)
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	buckets[plr] = nil
	nameCache[plr] = nil
	for _, m in { Show, BottleService, Booking } do
		if m and type(m.onLeave) == "function" then
			pcall(m.onLeave, plr)
		end
	end
end)

-- housekeeping (queued shows, table life expiry, the 합석 event's end)
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, m in { Show, BottleService, Booking } do
			if m and type(m.tick) == "function" then
				local ok, err = pcall(m.tick)
				if not ok then
					warn("[GwangalliClub] tick failed:", err)
				end
			end
		end
	end
end)
