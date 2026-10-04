-- Club (server): housekeeping, bottle service and the life-game hooks for CLUB OCEAN 광안.
--  * Publishes ShowEpoch (server time the show clock starts from) on every ClubRuntime model so
--    all clients run the same 64-bar show in sync (the clients fall back to epoch 0).
--  * Mirrors the club model's MusicAssetId attribute onto the Persistent ClubRuntime model (the
--    music system, ClubMusic.server, reads it as its override playlist).
--  * NPC hygiene: anchored HumanoidRootPart (PrimaryPart), unanchored limbs, and an Animator under
--    the rig's AnimationController (the builder makes AnimationController rigs, not Humanoids). A rig
--    that still has a Humanoid (older place) gets the old cheap settings. Animations are played
--    locally by ClubLights.client.luau.
--  * PAID DOOR (ProximityPrompts tagged ClubIDCheck: the head bouncer's "입장하기" at the closed
--    street door + the ID podium; docs/CLUB_SHOW.md). Wristband = player attributes
--    ClubOceanWristband (server time it was put on) + ClubOceanWristbandUntil (valid until). A valid
--    wristband: the door opens again for free (re-entry the same night). Free entry: ClubVIP (VIP
--    pass, Appearance >= G.CLUB.vipAppearance), the MD's guest list / pass (Life.hasClubPass), a
--    reserved table (GwangalliClubAPI "hasTable"), a 친구 perk of the club staff (GwangalliSocialAPI
--    perk "clubEntry"). Everyone else gets the entry sheet through ClubRemote ("door", payload):
--    walk-in fee (GwangalliClubShowShared.doorFee: weekday 30,000 / Fri-Sat night 50,000) or
--    "테이블 예약 입장" (the basic set, entry included). The client answers ("doorPay", option); the
--    server re-checks distance / state, charges through GwangalliGameplayAPI "spend" (bank first,
--    cash fallback) and grants the pass + wristband ("clubGrant"). The door itself is client-side
--    (GwangalliClubShow.client: local slide + local barrier), so every EjectEvery seconds the server
--    walks anyone inside a club zone without a valid wristband back out to ClubDoorOutside.
--    Players with ClubVIP = true get a WELCOME VIP banner.
--  * ServerStorage.ClubShowHook (BindableFunction) for the GwangalliClub show layer: hold the house
--    parade, table info / seats, reach checks, ClubLights' sparkler bottles ("stamp"), the route.
--    The "보틀 서비스" table prompt opens GwangalliClubAPI's menu when that server is running.
--  * Tables (Models tagged ClubTable: TableId, TableType, part ServePoint): "보틀 서비스" prompt on
--    every ServePoint (opens the bottle menu on the player's screen through ReplicatedStorage.ClubRemote)
--    and "테이블 앉기" when the table has Seats. Menu = ClubShared.Menu (champagne / VIP parade /
--    birthday parade). The client answers ("order", TableId, itemId); the server re-checks reach,
--    rate limits (per player, per table, remote token bucket) and charges the life-game money through
--    ServerStorage.GwangalliGameplayAPI (BindableFunction, Invoke("spend", player, amount, label) ->
--    boolean) when that API exists; without it the service is free (the menu says so). Parade items
--    walk the staff line to the table (path published as ParadePath) and put "VIP <NAME>" /
--    "HAPPY BIRTHDAY <NAME>" on the LED wall (WallMsg* attributes on ClubRuntime) while they walk.
--    The player gets status replies in the player attribute ClubOrder
--    ("<status>|<TableId>|<server time x10>").
--  * Bottle-service parade schedule: ParadeAt / ParadeTable / ParadePath on the ClubRuntime model,
--    every Parade.Period seconds to ParadeRoute.TargetTable (house bottles) and for every parade
--    order (at once, or queued behind the parade under way). Clients walk the staff; the table's
--    bottles are stamped for the moment the staff line arrives.
--  * Life-game hooks (no edits to GwangalliGameplay): the player attribute ClubVIPTable turning true
--    (the MD's VIP table, 300,000원) sends a welcome VIP parade to a free G table; the BindableEvent
--    ServerStorage.ClubGameplayEvent (created here) takes :Fire("vipTable" | "birthday" | "entry",
--    player); a player dancing in the club (client "dance") earns a little Happiness through the
--    API's Invoke("addStats", player, { happiness = 3 }, label) at most every 10 minutes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = nil
do
	local mod = ReplicatedStorage:WaitForChild("ClubShared", 30)
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			Shared = res
		else
			warn("[Club] ClubShared failed to load:", res)
		end
	else
		warn("[Club] ReplicatedStorage.ClubShared missing; using defaults")
	end
end

-- show layer data (door prices, wristband length); optional: the door falls back to fixed values
local ShowShared: any = nil
do
	local mod = ReplicatedStorage:WaitForChild("GwangalliClubShowShared", 10)
	if mod and mod:IsA("ModuleScript") then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			ShowShared = res
		else
			warn("[Club] GwangalliClubShowShared failed to load:", res)
		end
	end
end
local DOOR = (ShowShared and ShowShared.Door)
	or { Enabled = true, Weekday = 30000, Weekend = 50000, WristbandSeconds = 1440, EjectEvery = 2, PayDistance = 26 }

local Tags = Shared and Shared.Tags or {}
local Attr = Shared and Shared.Attr or {}
local Names = Shared and Shared.Names or {}
local TAG_RUNTIME = Tags.Runtime or "ClubRuntime"
local TAG_NPC = Tags.NPC or "ClubNPC"
local TAG_TABLE = Tags.Table or "ClubTable"
local TAG_IDCHECK = Tags.IDCheck or "ClubIDCheck"
local TAG_ZONE = Tags.Zone or "ClubZone"
local ATTR_MUSIC = Attr.MusicAssetId or "MusicAssetId"
local ATTR_EPOCH = Attr.ShowEpoch or "ShowEpoch"
local ATTR_WRISTBAND = Attr.Wristband or "ClubOceanWristband"
local ATTR_PARADE_AT = Attr.ParadeAt or "ParadeAt"
local ATTR_PARADE_TABLE = Attr.ParadeTable or "ParadeTable"
local ATTR_PARADE_PATH = Attr.ParadePath or "ParadePath"
local ATTR_TARGET = Attr.TargetTable or "TargetTable"
local ATTR_BOTTLE_AT = Attr.BottleAt or "BottleAt"
local ATTR_BOTTLE_BY = Attr.BottleBy or "BottleBy"
local ATTR_ORDER = Attr.Order or "ClubOrder"
local ATTR_WALL = Attr.WallMsg or "WallMsg"
local ATTR_WALL_AT = Attr.WallMsgAt or "WallMsgAt"
local ATTR_WALL_FOR = Attr.WallMsgFor or "WallMsgFor"
local ATTR_WALL_KIND = Attr.WallMsgKind or "WallMsgKind"
local ATTR_WALL_SERIAL = Attr.WallMsgSerial or "WallMsgSerial"
local ATTR_VIPTABLE = Attr.VIPTable or "ClubVIPTable"
local ATTR_GUESTLIST = Attr.GuestList or "ClubGuestList"
local ATTR_CLUBVIP = Attr.ClubVIP or "ClubVIP"
local NAME_ROUTE = Names.ParadeRoute or "ParadeRoute"
local NAME_SERVE = Names.ServePoint or "ServePoint"
local NAME_ORDER = Names.OrderPrompt or "ClubOrderPrompt"
local NAME_SIT = Names.SitPrompt or "ClubSitPrompt"
local NAME_REMOTE = Names.Remote or "ClubRemote"
local NAME_GP_EVENT = Names.GameplayEvent or "ClubGameplayEvent"
local NAME_API = Names.GameplayAPI or "GwangalliGameplayAPI"

local PARADE = (Shared and Shared.Parade) or { Period = 150, FirstDelay = 25, Busy = 85, Speed = 4.2, Hold = 22 }
local TCFG = (Shared and Shared.TableCfg)
	or { PromptCooldown = 1.2, OrderCooldownPlayer = 20, OrderCooldownTable = 25, MaxDistance = 16, BottleSeconds = 26 }
local TYPE_LABEL = (Shared and Shared.TableTypeLabel) or {}
local MENU = (Shared and Shared.Menu) or {}
local MAX_LEG = (Shared and Shared.PARADE_MAX_LEG) or 60
local EXTEND = (Shared and Shared.PARADE_EXTEND) or 48

local bootAdds = 0
local function watch(tag: string, fn: (Instance) -> (), onRemoved: ((Instance) -> ())?)
	local seen: { [Instance]: boolean } = {}
	local function add(inst: Instance)
		if seen[inst] then
			return
		end
		seen[inst] = true
		local ok, err = pcall(fn, inst)
		if not ok then
			warn("[Club]", tag, err)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		seen[inst] = nil
		if onRemoved then
			local ok, err = pcall(onRemoved, inst)
			if not ok then
				warn("[Club]", tag, "remove:", err)
			end
		end
	end)
	-- initial pass spread over frames (130 NPC rigs + 31 tables with their prompts at server start)
	for _, inst in CollectionService:GetTagged(tag) do
		add(inst)
		bootAdds += 1
		if bootAdds % 25 == 0 then
			task.wait()
		end
	end
end

local function isPlayer(plr: any): boolean
	return typeof(plr) == "Instance" and plr:IsA("Player") and plr.Parent == Players
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- LED-safe player name (the wall font is ASCII): DisplayName when it is drawable, else the user name
local function ledName(plr: Player): string
	local name = ""
	if Shared and Shared.ledText then
		name = Shared.ledText(plr.DisplayName, 16)
		if #name < 2 then
			name = Shared.ledText(plr.Name, 16)
		end
	else
		name = string.upper(string.sub(plr.Name, 1, 16))
	end
	return if name ~= "" then name else "GUEST"
end

---------------------------------------------------------------------------------------------------
-- Remote + life-game plumbing
---------------------------------------------------------------------------------------------------
local remote: RemoteEvent
do
	local r = ReplicatedStorage:FindFirstChild(NAME_REMOTE)
	if r and r:IsA("RemoteEvent") then
		remote = r
	else
		local e = Instance.new("RemoteEvent")
		e.Name = NAME_REMOTE
		e.Parent = ReplicatedStorage
		remote = e
	end
end

local gameplayEvent: BindableEvent
do
	local b = ServerStorage:FindFirstChild(NAME_GP_EVENT)
	if b and b:IsA("BindableEvent") then
		gameplayEvent = b
	else
		local e = Instance.new("BindableEvent")
		e.Name = NAME_GP_EVENT
		e.Parent = ServerStorage
		gameplayEvent = e
	end
end

local function gameplayAPI(): BindableFunction?
	local f = ServerStorage:FindFirstChild(NAME_API)
	if f and f:IsA("BindableFunction") then
		return f
	end
	return nil
end

-- Charges `amount` won through the life-game API. onDone(status) runs once with "free" (nothing
-- to pay), "noapi" (no API: the service is free), "paid", "declined" (not enough money), "error"
-- or "timeout"; a payment that succeeds after its timeout still calls onDone("paid-late") so the
-- player gets what they paid for.
local function pay(plr: Player, amount: number, label: string, onDone: (string) -> ())
	if amount <= 0 then
		onDone("free")
		return
	end
	local api = gameplayAPI()
	if not api then
		onDone("noapi")
		return
	end
	local settled = false
	local timedOut = false
	task.spawn(function()
		local ok, res = pcall(function()
			return api:Invoke("spend", plr, amount, label, "bank") -- bank first, cash fallback
		end)
		if timedOut then
			if ok and res == true then
				warn("[Club] payment for", plr.Name, "arrived after its timeout; serving it")
				onDone("paid-late")
			end
			return
		end
		settled = true
		if not ok then
			warn("[Club] GwangalliGameplayAPI spend failed:", res)
		end
		onDone(if ok and res == true then "paid" elseif ok then "declined" else "error")
	end)
	task.delay(8, function()
		if not settled then
			timedOut = true
			onDone("timeout")
		end
	end)
end

local function addStats(plr: Player, delta: { [string]: number }, label: string)
	local api = gameplayAPI()
	if not api then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			return api:Invoke("addStats", plr, delta, label)
		end)
		if not ok then
			warn("[Club] GwangalliGameplayAPI addStats failed:", err)
		end
	end)
end

-- remote spam guard: token bucket per player (6 tokens, 2 / s)
local buckets: { [Player]: { tokens: number, t: number } } = {}
local function remoteAllowed(plr: Player): boolean
	local now = os.clock()
	local b = buckets[plr]
	if not b then
		b = { tokens = 6, t = now }
		buckets[plr] = b
	end
	b.tokens = math.min(6, b.tokens + (now - b.t) * 2)
	b.t = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

---------------------------------------------------------------------------------------------------
-- Show epoch + music attribute mirror + parade / wall attributes
---------------------------------------------------------------------------------------------------
local epoch = math.floor(serverNow())
local runtimes: { [Instance]: boolean } = {}
local paradeAt = 0 -- server time of the current parade (0 = none yet)
local paradeTable = ""
local paradePath = ""
local paradeLen = 0
local paradeClock = -math.huge -- os.clock() of the last start (rate limit)
local wall = { text = "", kind = "", at = 0, dur = 0, serial = 0 }

local function publishWall(rt: Instance)
	rt:SetAttribute(ATTR_WALL, wall.text)
	rt:SetAttribute(ATTR_WALL_KIND, wall.kind)
	rt:SetAttribute(ATTR_WALL_AT, wall.at)
	rt:SetAttribute(ATTR_WALL_FOR, wall.dur)
	rt:SetAttribute(ATTR_WALL_SERIAL, wall.serial)
end

watch(TAG_RUNTIME, function(rt)
	runtimes[rt] = true
	rt:SetAttribute(ATTR_EPOCH, epoch)
	if paradeAt > 0 then
		rt:SetAttribute(ATTR_PARADE_AT, paradeAt)
		rt:SetAttribute(ATTR_PARADE_TABLE, paradeTable)
		rt:SetAttribute(ATTR_PARADE_PATH, paradePath)
	end
	if wall.serial > 0 then
		publishWall(rt)
	end
	local venue = rt.Parent
	if not venue or venue == workspace then
		return
	end
	local function copy()
		if not rt.Parent then
			return
		end
		local v = venue:GetAttribute(ATTR_MUSIC)
		if type(v) ~= "string" and type(v) ~= "number" then
			v = ""
		end
		rt:SetAttribute(ATTR_MUSIC, v)
	end
	copy()
	local conn
	conn = venue:GetAttributeChangedSignal(ATTR_MUSIC):Connect(function()
		if not rt.Parent then
			conn:Disconnect()
			return
		end
		copy()
	end)
end, function(rt)
	runtimes[rt] = nil
end)

-- LED wall banner: shown on every client inside from `at` for `dur` seconds (a newer one replaces it)
local function setWall(text: string, kind: string, at: number, dur: number)
	if text == "" then
		return
	end
	wall.text, wall.kind, wall.at, wall.dur = text, kind, at, dur
	wall.serial += 1
	for rt in runtimes do
		if rt.Parent then
			publishWall(rt)
		end
	end
end

-- banners that are not tied to a parade wait for the current one (at most 4 waiting)
local wallQueue: { { text: string, kind: string, dur: number } } = {}
local function queueWall(text: string, kind: string, dur: number)
	if text == "" then
		return
	end
	local now = serverNow()
	if now >= wall.at + wall.dur then
		setWall(text, kind, now, dur)
	elseif #wallQueue < 4 then
		table.insert(wallQueue, { text = text, kind = kind, dur = dur })
	end
end

local function defaultParadeTarget(): string
	for rt in runtimes do
		local route = rt.Parent and rt:FindFirstChild(NAME_ROUTE)
		if route then
			local t = route:GetAttribute(ATTR_TARGET)
			if type(t) == "string" then
				return t
			end
		end
	end
	return ""
end

-- ParadeRoute folder + waypoints (world positions, in order) of the first ClubRuntime with a route
local function routeInfo(): (Instance?, { Vector3 })
	for rt in runtimes do
		local route = rt.Parent and rt:FindFirstChild(NAME_ROUTE)
		if route then
			local pts: { Vector3 } = {}
			for i = 1, 64 do
				local wp = route:FindFirstChild("WP" .. i)
				if wp and wp:IsA("BasePart") then
					pts[i] = wp.Position
				elseif wp and wp:IsA("Attachment") then
					pts[i] = wp.WorldPosition
				else
					break
				end
			end
			return route, pts
		end
	end
	return nil, {}
end

---------------------------------------------------------------------------------------------------
-- Tables registry (declared early: the parade code needs it)
---------------------------------------------------------------------------------------------------
type TableRec = {
	model: Model,
	id: string,
	kind: string,
	serve: Instance, -- BasePart or Attachment named ServePoint
	seats: { Seat },
	busyUntil: number, -- server time until which the table takes no new order (bottles still out)
	pendingBy: number?, -- UserId of a parade order whose bottles come with the next parade
	pendingMsg: { text: string, kind: string }?, -- banner of that order
	reservedBy: Player?, -- an order is being paid for right now
	reservedUntil: number,
	conns: { RBXScriptConnection },
}
local tableRecs: { [Instance]: TableRec } = {}
local tableById: { [string]: TableRec } = {}

local function servePosition(rec: TableRec): Vector3?
	local sp = rec.serve
	if not sp.Parent then
		return nil
	end
	if sp:IsA("BasePart") then
		return sp.Position
	elseif sp:IsA("Attachment") then
		return sp.WorldPosition
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Parade path (route -> branch point -> the table, with a clear straight leg)
---------------------------------------------------------------------------------------------------
local clearParams = RaycastParams.new()
clearParams.FilterType = Enum.RaycastFilterType.Exclude

-- is the straight walk a -> b (HumanoidRootPart height) free of furniture? Spherecast (radius 1.1:
-- sofas, table tops, counters, the DJ booth) when the engine has it, else four rays.
local function legClear(a: Vector3, b: Vector3): boolean
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = d.Magnitude
	if len < 2.5 then
		return true
	end
	local unit = d.Unit
	local dir = unit * (len - 2) -- stop short of the ServePoint (it stands right at the table)
	local okS, hit = pcall(function()
		return (workspace :: any):Spherecast(a, 1.1, dir, clearParams)
	end)
	if okS then
		return hit == nil
	end
	local side = Vector3.new(-unit.Z, 0, unit.X)
	for _, off in { Vector3.new(0, -1, 0), Vector3.new(0, 0.6, 0), side + Vector3.new(0, 0.6, 0), -side + Vector3.new(0, 0.6, 0) } do
		local okR, h = pcall(function()
			return workspace:Raycast(a + off, dir, clearParams)
		end)
		if okR and h then
			return false
		end
	end
	return true
end

-- the walk for a parade to `rec` (nil = the route's own table): points + flat length
local function computeParadePath(rec: TableRec?): ({ Vector3 }, number)
	local folder, route = routeInfo()
	if #route < 2 then
		return route, 0
	end
	local own = defaultParadeTarget()
	local dest = rec and servePosition(rec)
	if rec and dest and rec.id ~= own and Shared and Shared.paradePath then
		local ex: { Instance } = {}
		for _, npc in CollectionService:GetTagged(TAG_NPC) do
			table.insert(ex, npc)
		end
		table.insert(ex, rec.model)
		if folder then
			table.insert(ex, folder)
		end
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(ex, p.Character)
			end
		end
		clearParams.FilterDescendantsInstances = ex
		local pts, len = Shared.paradePath(route, dest, MAX_LEG, EXTEND, legClear)
		if pts then
			return pts, len
		end
	end
	return route, (if Shared and Shared.pathLength then Shared.pathLength(route) else 0)
end

-- seconds from a parade start until the staff line stands at its table
local function paradeTravel(): number
	return paradeLen / math.max(0.1, PARADE.Speed or 4.2) + 1
end

local pendingParade: string? = nil -- TableId of an order waiting for the running parade to end
local onParadeStart: ((string, number) -> ())? = nil -- set by the tables section

local function startParade(tableId: string)
	local pts, len = computeParadePath(tableById[tableId])
	paradeClock = os.clock()
	paradeAt = serverNow()
	paradeTable = tableId
	paradeLen = len
	paradePath = if Shared and Shared.encodePath and #pts >= 2 then Shared.encodePath(pts) else ""
	for rt in runtimes do
		if rt.Parent then
			rt:SetAttribute(ATTR_PARADE_PATH, paradePath)
			rt:SetAttribute(ATTR_PARADE_TABLE, tableId)
			rt:SetAttribute(ATTR_PARADE_AT, paradeAt) -- last: clients rebuild the walk on this one
		end
	end
	if onParadeStart then
		onParadeStart(tableId, paradeAt)
	end
end

local function paradeBusy(): boolean
	return os.clock() - paradeClock < (PARADE.Busy or 85)
end

task.spawn(function()
	task.wait(PARADE.FirstDelay or 25)
	while true do
		if next(runtimes) ~= nil and not paradeBusy() then
			local target: string? = nil
			if pendingParade then
				target, pendingParade = pendingParade, nil -- an order queued behind the last parade
			elseif os.clock() - paradeClock >= (PARADE.Period or 150) then
				target = defaultParadeTarget()
			end
			if target then
				local ok, err = pcall(startParade, target)
				if not ok then
					warn("[Club] parade schedule:", err)
				end
			end
		end
		-- waiting banners
		if #wallQueue > 0 and serverNow() >= wall.at + wall.dur then
			local nxt = table.remove(wallQueue, 1)
			if nxt then
				setWall(nxt.text, nxt.kind, serverNow(), nxt.dur)
			end
		end
		task.wait(2)
	end
end)

---------------------------------------------------------------------------------------------------
-- NPC hygiene (AnimationController rigs; Humanoid rigs from older places still work)
---------------------------------------------------------------------------------------------------
watch(TAG_NPC, function(model)
	if not model:IsA("Model") then
		return
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.Anchored = true
		if model.PrimaryPart == nil then
			model.PrimaryPart = hrp
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= hrp and d.Anchored then
			d.Anchored = false -- limbs must be free for the Motor6D animation
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		-- transition: a Humanoid rig. Cheap settings (no name / health display, no state machine).
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.BreakJointsOnDeath = false
		pcall(function()
			(hum :: any).EvaluateStateMachine = false
		end)
		if not hum:FindFirstChildOfClass("Animator") then
			local animator = Instance.new("Animator")
			animator.Parent = hum
		end
		return
	end
	local ctrl = model:FindFirstChildOfClass("AnimationController")
	if not ctrl then
		local c = Instance.new("AnimationController")
		c.Name = "AnimationController"
		c.Parent = model
		ctrl = c
	end
	if ctrl and not ctrl:FindFirstChildOfClass("Animator") then
		local animator = Instance.new("Animator")
		animator.Parent = ctrl
	end
end)

---------------------------------------------------------------------------------------------------
-- Per-player state
---------------------------------------------------------------------------------------------------
local lastCheck: { [Player]: number } = {}
local lastPrompt: { [Player]: number } = {}
local lastOrder: { [Player]: number } = {}
local paying: { [Player]: boolean } = {}
local lastWelcome: { [Player]: number } = {}
local lastVipParade: { [Player]: number } = {}
local lastDance: { [Player]: number } = {}

local function reply(plr: Player, status: string, id: string)
	if plr.Parent ~= Players then
		return
	end
	plr:SetAttribute(ATTR_ORDER, string.format("%s|%s|%d", status, id, math.floor(serverNow() * 10)))
end

---------------------------------------------------------------------------------------------------
-- Club zone test on the server (the persistent ClubZone boxes)
---------------------------------------------------------------------------------------------------
local zoneParts: { [BasePart]: boolean } = {}
watch(TAG_ZONE, function(z)
	if z:IsA("BasePart") then
		zoneParts[z] = true
	end
end, function(z)
	zoneParts[z :: BasePart] = nil
end)

local function inClub(plr: Player): boolean
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local pos = root.Position
	for z in zoneParts do
		if z.Parent and z:GetAttribute("Zone") ~= "Near" then
			local lp = z.CFrame:PointToObjectSpace(pos)
			local h = z.Size * 0.5
			if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
				return true
			end
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------
-- ID check at the door (ProximityPrompt tagged ClubIDCheck)
---------------------------------------------------------------------------------------------------
local function welcome(plr: Player)
	local now = os.clock()
	if lastWelcome[plr] and now - lastWelcome[plr] < 600 then
		return
	end
	lastWelcome[plr] = now
	queueWall("WELCOME VIP " .. ledName(plr), "welcome", 12)
end

-- Paid door ---------------------------------------------------------------------------------------
local ATTR_WB_UNTIL = (ShowShared and ShowShared.Attr.WristbandUntil) or "ClubOceanWristbandUntil"
local entryPrompts: { [ProximityPrompt]: boolean } = {}
local doorPaying: { [Player]: boolean } = {}
local lastDoorPay: { [Player]: number } = {}
local lastValidOpen: { [Player]: number } = {} -- os.clock() of the last "door opens for you"
local lastEject: { [Player]: number } = {}

local function doorEnabled(): boolean
	if workspace:GetAttribute("GwangalliClubFreeEntry") == true then
		return false
	end
	return DOOR.Enabled ~= false
end

local function wristbandUntil(plr: Player): number
	local v = plr:GetAttribute(ATTR_WB_UNTIL)
	return if type(v) == "number" and v == v then v else 0
end

local function wristbandValid(plr: Player): boolean
	return wristbandUntil(plr) > serverNow()
end

-- the wristband without the life-game (no API): same attributes, same length
local function putWristband(plr: Player)
	local now = serverNow()
	plr:SetAttribute(ATTR_WB_UNTIL, math.floor(math.max(wristbandUntil(plr), now + (DOOR.WristbandSeconds or 1440))))
	plr:SetAttribute(ATTR_WRISTBAND, math.floor(now))
end

local function invokeApi(op: string, plr: Player, ...: any): ...any
	local api = gameplayAPI()
	if not api then
		return nil
	end
	local res = table.pack(pcall(api.Invoke, api, op, plr, ...))
	if not res[1] then
		warn("[Club] GwangalliGameplayAPI", op, "failed:", res[2])
		return nil
	end
	return table.unpack(res, 2, res.n)
end

local function clubApi(): BindableFunction?
	local f = ServerStorage:FindFirstChild((ShowShared and ShowShared.API_NAME) or "GwangalliClubAPI")
	return if f and f:IsA("BindableFunction") then f else nil
end

local function invokeClub(op: string, ...: any): any
	local f = clubApi()
	if not f then
		return nil
	end
	local ok, res = pcall(f.Invoke, f, op, ...)
	if not ok then
		warn("[Club] GwangalliClubAPI", op, "failed:", res)
		return nil
	end
	return res
end

-- grant entry (pass + wristband through the life-game, else the attributes directly)
local function grantEntry(plr: Player)
	local ok = invokeApi("clubGrant", plr, true)
	if ok ~= true then
		putWristband(plr)
	elseif not wristbandValid(plr) then
		putWristband(plr) -- an older life-game without the wristband in grantPass
	end
	if plr:GetAttribute(ATTR_CLUBVIP) == true then
		welcome(plr)
	end
end

-- why this player walks in for free (nil = pay)
local function freeReason(plr: Player): string?
	if not doorEnabled() then
		return "event"
	end
	if plr:GetAttribute(ATTR_CLUBVIP) == true then
		return "vip"
	end
	local st = invokeApi("clubState", plr)
	if type(st) == "table" and (st.pass == true or st.invited == true) then
		return "guest"
	end
	if invokeClub("hasTable", plr) then
		return "table"
	end
	local social = ServerStorage:FindFirstChild("GwangalliSocialAPI")
	if social and social:IsA("BindableFunction") then
		local ok, res = pcall(social.Invoke, social, "perk", plr, "clubEntry")
		if ok and res == true then
			return "friend"
		end
	end
	return nil
end

local function doorFeeNow(): (number, boolean)
	if ShowShared and ShowShared.doorFee then
		return ShowShared.doorFee(os.time())
	end
	return DOOR.Weekday or 30000, false
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s
	repeat
		local k
		out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return out
end

local function sendDoor(plr: Player, payload: { [string]: any })
	if plr.Parent == Players then
		remote:FireClient(plr, "door", payload)
	end
end

-- the nearest entry prompt's part (payment distance check)
local function nearEntry(plr: Player, radius: number): boolean
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	for p in entryPrompts do
		local host = p.Parent
		if host and host:IsA("BasePart") and (host.Position - root.Position).Magnitude <= radius then
			return true
		end
	end
	return false
end

local function doorModel(): Instance?
	for _, m in CollectionService:GetTagged((ShowShared and ShowShared.Tags.Door) or "ClubDoor") do
		if m:IsDescendantOf(workspace) then
			return m
		end
	end
	return nil
end

-- feet CFrame just outside the door (facing it) / just inside the vestibule
local function doorOutsideCF(): CFrame?
	local d = doorModel()
	local out = d and d:FindFirstChild("ClubDoorOutside")
	if out and out:IsA("BasePart") then
		return out.CFrame * CFrame.new(0, -out.Size.Y / 2, 0)
	end
	return nil
end

local function moveCharacter(plr: Player, feet: CFrame)
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or hum.Health <= 0 then
		return
	end
	if hum.SeatPart then
		local w = hum.SeatPart:FindFirstChild("SeatWeld")
		if w then
			w:Destroy()
		end
		hum.Sit = false
	end
	invokeApi("allowTeleport", plr, 5)
	local hip = (hum.HipHeight or 2) + 1
	char:PivotTo(feet * CFrame.new(0, hip, 0))
end

local function onEntryPrompt(plr: Player)
	local now = os.clock()
	if lastCheck[plr] and now - lastCheck[plr] < 1.2 then
		return
	end
	lastCheck[plr] = now
	local fee, weekend = doorFeeNow()
	if wristbandValid(plr) then
		-- re-entry is free; a second tap while still outside (the local door never opened) walks the
		-- player in through the vestibule
		if lastValidOpen[plr] and now - lastValidOpen[plr] > 6 and not inClub(plr) then
			local cf = doorOutsideCF()
			if cf then
				moveCharacter(plr, cf * CFrame.new(0, 0.44, -13))
			end
		end
		lastValidOpen[plr] = now
		sendDoor(plr, { state = "valid", untilT = wristbandUntil(plr), fee = fee })
		return
	end
	local reason = freeReason(plr)
	if reason then
		grantEntry(plr)
		lastValidOpen[plr] = now
		sendDoor(plr, { state = "granted", reason = reason, untilT = wristbandUntil(plr), fee = fee })
		return
	end
	local cash, bank = invokeApi("balance", plr)
	local st = invokeApi("clubState", plr)
	local options = { { id = "ticket", price = fee } }
	local tableSet = ShowShared and ShowShared.item(DOOR.TableOption or "basic")
	if tableSet and clubApi() then
		table.insert(options, { id = "table", price = tableSet.price, set = tableSet.id })
	end
	sendDoor(plr, {
		state = "quote",
		fee = fee,
		weekend = weekend,
		cash = if type(cash) == "number" then cash else nil,
		bank = if type(bank) == "number" then bank else nil,
		priced = gameplayAPI() ~= nil,
		options = options,
		mdCover = if type(st) == "table" and type(st.cover) == "number" then st.cover else nil,
		wristbandSeconds = DOOR.WristbandSeconds or 1440,
	})
end

local function onDoorPay(plr: Player, option: any)
	if option ~= "ticket" and option ~= "table" then
		return
	end
	local now = os.clock()
	if doorPaying[plr] or (lastDoorPay[plr] and now - lastDoorPay[plr] < 2) then
		return
	end
	if wristbandValid(plr) then
		sendDoor(plr, { state = "valid", untilT = wristbandUntil(plr) })
		return
	end
	if not nearEntry(plr, DOOR.PayDistance or 26) then
		sendDoor(plr, { state = "far" })
		return
	end
	local reason = freeReason(plr)
	if reason then
		grantEntry(plr)
		lastValidOpen[plr] = now
		sendDoor(plr, { state = "granted", reason = reason, untilT = wristbandUntil(plr) })
		return
	end
	local price, label = doorFeeNow(), "CLUB OCEAN 입장료"
	local setId: string? = nil
	if option == "table" then
		local item = ShowShared and ShowShared.item(DOOR.TableOption or "basic")
		if not item or not clubApi() then
			return
		end
		price, setId = item.price, item.id
		label = "CLUB OCEAN 테이블 예약 (" .. (ShowShared.label(item) or item.id) .. ", 입장 포함)"
	end
	lastDoorPay[plr] = now
	doorPaying[plr] = true
	pay(plr, price, label, function(status)
		doorPaying[plr] = nil
		if status == "declined" then
			sendDoor(plr, { state = "nofunds", price = price, option = option })
			return
		elseif status == "error" or status == "timeout" then
			sendDoor(plr, { state = "error" })
			return
		end
		if not isPlayer(plr) then
			return
		end
		grantEntry(plr)
		lastValidOpen[plr] = os.clock()
		local tableId = nil
		if setId then
			tableId = invokeClub("reserve", plr, setId)
		end
		sendDoor(plr, { state = "paid", option = option, price = price, table = tableId, untilT = wristbandUntil(plr), free = status == "noapi" })
	end)
end

watch(TAG_IDCHECK, function(prompt)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	entryPrompts[prompt] = true
	if prompt.Name == "IDCheckPrompt" then
		prompt.ActionText = "입장하기"
	end
	prompt.Triggered:Connect(function(plr)
		if not isPlayer(plr) then
			return
		end
		local ok, err = pcall(onEntryPrompt, plr)
		if not ok then
			warn("[Club] entry prompt:", err)
		end
	end)
end, function(prompt)
	entryPrompts[prompt :: ProximityPrompt] = nil
end)

-- today's fee on the prompts (ObjectText), refreshed every minute
task.spawn(function()
	while true do
		local fee, weekend = doorFeeNow()
		local text = string.format("CLUB OCEAN · %s원%s", commas(fee), if weekend then " (주말)" else "")
		for p in entryPrompts do
			if p.Parent and p.Name ~= "IDCheckPrompt" then
				p.ObjectText = if doorEnabled() then text else "CLUB OCEAN · 오늘 무료 입장"
			end
		end
		task.wait(60)
	end
end)

-- walk-out sweep: inside a club zone without a valid wristband -> back outside the door
task.spawn(function()
	while true do
		task.wait(DOOR.EjectEvery or 2)
		if doorEnabled() then
			for _, plr in Players:GetPlayers() do
				if not wristbandValid(plr) and inClub(plr) then
					local cf = doorOutsideCF()
					if cf then
						local ok, err = pcall(function()
							moveCharacter(plr, cf * CFrame.new(math.random(-15, 15) / 10, 0, 0))
						end)
						if not ok then
							warn("[Club] walk-out failed:", err)
						end
						local now = os.clock()
						if not lastEject[plr] or now - lastEject[plr] > 4 then
							lastEject[plr] = now
							sendDoor(plr, { state = "eject" })
						end
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- Tables: bottle menu / orders / sit
---------------------------------------------------------------------------------------------------
-- The player's living character within `radius` of the table (the prompt's own distance check runs
-- on the client, so the server checks again).
local function reach(plr: Player, rec: TableRec, radius: number?): (Humanoid?, BasePart?)
	local pos = servePosition(rec)
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not pos or not root or not root:IsA("BasePart") or not hum or hum.Health <= 0 then
		return nil, nil
	end
	if (root.Position - pos).Magnitude > (radius or TCFG.MaxDistance or 16) then
		return nil, nil
	end
	return hum, root
end

local function promptAllowed(plr: Player): boolean
	local now = os.clock()
	if lastPrompt[plr] and now - lastPrompt[plr] < (TCFG.PromptCooldown or 1.2) then
		return false
	end
	lastPrompt[plr] = now
	return true
end

-- Put the sparkler bottles on the table at server time `at` (may be in the future: a parade is
-- carrying them over). Every client near the table builds them from these attributes.
local function stampBottles(rec: TableRec, at: number, by: number)
	rec.model:SetAttribute(ATTR_BOTTLE_AT, at)
	rec.model:SetAttribute(ATTR_BOTTLE_BY, by)
	rec.busyUntil = math.max(rec.busyUntil, at + (TCFG.BottleSeconds or 26))
end

-- every parade brings bottles to its table: the ordering player's, or the house's (BottleBy 0) for
-- the scheduled ones; they land when the staff line arrives, and the order's banner shows meanwhile
onParadeStart = function(tableId: string, startedAt: number)
	local rec = tableById[tableId]
	if not rec or not rec.model.Parent then
		return
	end
	local by = rec.pendingBy or 0
	rec.pendingBy = nil
	local travel = paradeTravel()
	stampBottles(rec, startedAt + travel, by)
	local msg = rec.pendingMsg
	rec.pendingMsg = nil
	if msg then
		setWall(msg.text, msg.kind, startedAt, travel + (PARADE.Hold or 22))
	end
end

local function tableBusy(rec: TableRec, plr: Player?): boolean
	local nowS = serverNow()
	if rec.reservedBy and rec.reservedBy ~= plr and nowS < rec.reservedUntil and rec.reservedBy.Parent == Players then
		return true
	end
	return nowS < rec.busyUntil or rec.pendingBy ~= nil
end

-- Sends the parade for `rec` (at once, queued behind the running one, or - both slots taken - the
-- bottles straight away with the banner queued). Returns the reply status.
local function sendParade(rec: TableRec, byUserId: number, text: string?, kind: string): string
	if not paradeBusy() then
		rec.pendingBy = byUserId
		rec.pendingMsg = if text then { text = text, kind = kind } else nil
		startParade(rec.id)
		return "parade"
	elseif pendingParade == nil then
		pendingParade = rec.id
		rec.pendingBy = byUserId
		rec.pendingMsg = if text then { text = text, kind = kind } else nil
		if text then
			queueWall(text, kind, 14) -- on the wall right away; again when the staff set off
		end
		return "queued"
	end
	stampBottles(rec, serverNow(), byUserId)
	if text then
		queueWall(text, kind, 16)
	end
	return "ok"
end

local function fulfil(plr: Player, rec: TableRec, item: { [string]: any })
	rec.busyUntil = math.max(rec.busyUntil, serverNow() + (TCFG.OrderCooldownTable or 25))
	if item.parade then
		local text = if type(item.msg) == "string" then string.format(item.msg, ledName(plr)) else nil
		reply(plr, sendParade(rec, plr.UserId, text, item.kind or "vip"), rec.id)
		addStats(plr, { happiness = 10, popularity = 3 }, "CLUB OCEAN 보틀 퍼레이드 🍾")
		return
	end
	stampBottles(rec, serverNow(), plr.UserId)
	reply(plr, "ok", rec.id)
	addStats(plr, { happiness = 5, popularity = 1 }, "CLUB OCEAN 샴페인 🍾")
end

-- bottle menu payload for the ordering player's screen
local function openMenu(rec: TableRec, plr: any)
	if not isPlayer(plr) or not rec.model.Parent or not promptAllowed(plr) then
		return
	end
	if not reach(plr, rec) then
		return
	end
	-- the show layer (GwangalliClub.server) owns the bottle menu when it runs
	if invokeClub("openMenu", plr, rec.id) == true then
		return
	end
	local items = {}
	for _, it in MENU do
		table.insert(items, { id = it.id, label = it.label, desc = it.desc, icon = it.icon, price = it.price, parade = it.parade == true })
	end
	local cooldown = 0
	if lastOrder[plr] then
		cooldown = math.max(0, (TCFG.OrderCooldownPlayer or 20) - (os.clock() - lastOrder[plr]))
	end
	remote:FireClient(plr, "menu", {
		table = rec.id,
		kind = rec.kind,
		label = rec.id .. " · " .. (TYPE_LABEL[rec.kind] or rec.kind),
		items = items,
		priced = gameplayAPI() ~= nil,
		busy = tableBusy(rec, plr),
		cooldown = math.floor(cooldown + 0.5),
	})
end

local function onOrderRequest(plr: Player, tableId: any, itemId: any)
	if type(tableId) ~= "string" or #tableId > 12 or type(itemId) ~= "string" or #itemId > 24 then
		return
	end
	local rec = tableById[tableId]
	local item = Shared and Shared.menuItem and Shared.menuItem(itemId)
	if not rec or not item or not rec.model.Parent then
		return
	end
	if paying[plr] then
		reply(plr, "paying", rec.id)
		return
	end
	if not reach(plr, rec, (TCFG.MaxDistance or 16) + 10) then
		reply(plr, "far", rec.id)
		return
	end
	local now = os.clock()
	if lastOrder[plr] and now - lastOrder[plr] < (TCFG.OrderCooldownPlayer or 20) then
		reply(plr, "wait", rec.id)
		return
	end
	if tableBusy(rec, plr) then
		reply(plr, "busy", rec.id)
		return
	end
	-- hold the table while the payment runs (nobody else can order it meanwhile)
	rec.reservedBy = plr
	rec.reservedUntil = serverNow() + 12
	paying[plr] = true
	lastOrder[plr] = now -- the cooldown starts with the attempt (no payment spam)
	local price = if type(item.price) == "number" then math.max(0, math.floor(item.price)) else 0
	pay(plr, price, string.format("CLUB OCEAN %s (%s)", item.label, rec.id), function(status)
		paying[plr] = nil
		if rec.reservedBy == plr then
			rec.reservedBy = nil
		end
		if status == "declined" then
			lastOrder[plr] = nil
			reply(plr, "nofunds", rec.id)
			return
		elseif status == "error" or status == "timeout" then
			lastOrder[plr] = nil
			reply(plr, "error", rec.id)
			return
		end
		if not isPlayer(plr) or not rec.model.Parent then
			return
		end
		fulfil(plr, rec, item)
	end)
end

local function sitOn(seat: Seat, hum: Humanoid)
	local wasDisabled = seat.Disabled
	if wasDisabled then
		seat.Disabled = false -- the builder may save Seats disabled (no auto-sit on touch)
	end
	local ok, err = pcall(function()
		seat:Sit(hum)
	end)
	if not ok then
		warn("[Club] Seat:Sit failed:", err)
	end
	if not wasDisabled then
		return
	end
	local conn: RBXScriptConnection? = nil
	local function restore()
		if seat.Parent and seat.Occupant == nil then
			if conn then
				conn:Disconnect()
				conn = nil
			end
			seat.Disabled = true
		end
	end
	conn = seat:GetPropertyChangedSignal("Occupant"):Connect(restore)
	task.delay(2, restore) -- the sit did not take: disable it again
end

local function onSit(rec: TableRec, plr: any)
	if not isPlayer(plr) or not rec.model.Parent or not promptAllowed(plr) then
		return
	end
	local hum, root = reach(plr, rec)
	if not hum or not root then
		return
	end
	local current = hum.SeatPart
	if current and current:IsDescendantOf(rec.model) then
		return -- already sitting at this table
	end
	local best: Seat? = nil
	local bestD = math.huge
	for _, seat in rec.seats do
		local guestUntil = seat:GetAttribute((ShowShared and ShowShared.Attr.GuestSeat) or "ClubGuestSeat")
		local guest = type(guestUntil) == "number" and guestUntil > serverNow()
		if seat.Parent and seat:IsDescendantOf(workspace) and seat.Occupant == nil and not guest then
			local d = (seat.Position - root.Position).Magnitude
			if d < bestD then
				best, bestD = seat, d
			end
		end
	end
	if not best then
		reply(plr, "full", rec.id)
		return
	end
	local seat = best :: Seat
	if current then
		-- leave the other seat first (the SeatWeld is server-side; Sit = false alone can lag behind)
		local weld = current:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		hum.Sit = false
		task.delay(0.2, function()
			if seat.Parent and seat.Occupant == nil and hum.Parent and hum.Health > 0 then
				sitOn(seat, hum)
			end
		end)
	else
		sitOn(seat, hum)
	end
end

local function makePrompt(parent: Instance, name: string, props: { [string]: any }): ProximityPrompt
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("ProximityPrompt") then
		for k, v in props do
			pcall(function()
				(existing :: any)[k] = v
			end)
		end
		return existing
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.RequiresLineOfSight = false -- sofas and table tops sit between the player and the point
	p.MaxActivationDistance = 9
	p.ClickablePrompt = true -- tap on phones
	p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

watch(TAG_TABLE, function(model)
	if not model:IsA("Model") or tableRecs[model] then
		return
	end
	local id = model:GetAttribute(Attr.TableId or "TableId")
	local kind = model:GetAttribute(Attr.TableType or "TableType")
	if type(id) ~= "string" or id == "" then
		id = model.Name
	end
	kind = if type(kind) == "string" then kind else "Standing"
	local sp = model:FindFirstChild(NAME_SERVE, true)
	if not sp or not (sp:IsA("BasePart") or sp:IsA("Attachment")) then
		warn("[Club] table", id, "has no ServePoint part")
		return
	end
	local seats: { Seat } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Seat") then
			table.insert(seats, d)
		end
	end
	local rec: TableRec = {
		model = model,
		id = id,
		kind = kind,
		serve = sp,
		seats = seats,
		busyUntil = 0,
		pendingBy = nil,
		pendingMsg = nil,
		reservedBy = nil,
		reservedUntil = 0,
		conns = {},
	}
	tableRecs[model] = rec
	tableById[id] = rec
	local label = id .. " · " .. (TYPE_LABEL[kind] or kind)
	local order = makePrompt(sp, NAME_ORDER, {
		ActionText = "보틀 서비스",
		ObjectText = label,
		HoldDuration = 0.3,
		KeyboardKeyCode = Enum.KeyCode.E,
		GamepadKeyCode = Enum.KeyCode.ButtonX,
		UIOffset = if #seats > 0 then Vector2.new(0, -42) else Vector2.zero,
	})
	table.insert(rec.conns, order.Triggered:Connect(function(plr)
		openMenu(rec, plr)
	end))
	if #seats > 0 then
		local sit = makePrompt(sp, NAME_SIT, {
			ActionText = "테이블 앉기",
			ObjectText = label,
			HoldDuration = 0,
			KeyboardKeyCode = Enum.KeyCode.F,
			GamepadKeyCode = Enum.KeyCode.ButtonY,
			UIOffset = Vector2.new(0, 42),
		})
		table.insert(rec.conns, sit.Triggered:Connect(function(plr)
			onSit(rec, plr)
		end))
	end
end, function(model)
	local rec = tableRecs[model]
	if rec then
		for _, c in rec.conns do
			c:Disconnect()
		end
		tableRecs[model] = nil
		if tableById[rec.id] == rec then
			tableById[rec.id] = nil
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- Life-game hooks: VIP table bought from the MD, gameplay events, dancing
---------------------------------------------------------------------------------------------------
-- a free VIP table for a welcome parade (the route's own table first)
local function freeVipTable(): TableRec?
	local own = tableById[defaultParadeTarget()]
	if own and own.kind == "VIP" and own.model.Parent and not tableBusy(own) then
		return own
	end
	local ids = {}
	for id, rec in tableById do
		if rec.kind == "VIP" and rec.model.Parent and not tableBusy(rec) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return if #ids > 0 then tableById[ids[1]] else nil
end

local function vipParade(plr: Player, text: string, kind: string)
	if not isPlayer(plr) then
		return
	end
	local now = os.clock()
	if lastVipParade[plr] and now - lastVipParade[plr] < 20 then
		return -- the attribute and the gameplay event may both report the same purchase
	end
	lastVipParade[plr] = now
	local rec = freeVipTable()
	if rec then
		rec.busyUntil = math.max(rec.busyUntil, serverNow() + (TCFG.OrderCooldownTable or 25))
		reply(plr, sendParade(rec, plr.UserId, text, kind), rec.id)
	else
		queueWall(text, kind, 16)
	end
end

local function hookPlayer(plr: Player)
	plr:GetAttributeChangedSignal(ATTR_VIPTABLE):Connect(function()
		if plr:GetAttribute(ATTR_VIPTABLE) == true then
			vipParade(plr, "VIP " .. ledName(plr), "vip")
		end
	end)
end
Players.PlayerAdded:Connect(hookPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(hookPlayer, p)
end

gameplayEvent.Event:Connect(function(action: any, plr: any)
	if not isPlayer(plr) or type(action) ~= "string" then
		return
	end
	if action == "vipTable" then
		vipParade(plr, "VIP " .. ledName(plr), "vip")
	elseif action == "birthday" then
		vipParade(plr, "HAPPY BIRTHDAY " .. ledName(plr) .. " *", "birthday")
	elseif action == "entry" then
		if plr:GetAttribute(ATTR_CLUBVIP) == true then
			welcome(plr)
		end
	end
end)

local function onDance(plr: Player)
	local now = os.clock()
	if lastDance[plr] and now - lastDance[plr] < 600 then
		return
	end
	if not inClub(plr) then
		return
	end
	lastDance[plr] = now
	addStats(plr, { happiness = 3 }, "클럽에서 춤 💃")
end

---------------------------------------------------------------------------------------------------
-- ServerStorage.ClubShowHook: the show layer's window into this script (server only)
---------------------------------------------------------------------------------------------------
do
	local name = (ShowShared and ShowShared.HOOK_NAME) or "ClubShowHook"
	local hook = ServerStorage:FindFirstChild(name)
	if hook and not hook:IsA("BindableFunction") then
		hook:Destroy()
		hook = nil
	end
	if not hook then
		local f = Instance.new("BindableFunction")
		f.Name = name
		f.Parent = ServerStorage
		hook = f
	end
	local GUEST_ATTR = (ShowShared and ShowShared.Attr.GuestSeat) or "ClubGuestSeat"
	local function info(rec: TableRec): { [string]: any }?
		local pos = servePosition(rec)
		if not pos then
			return nil
		end
		local okB, cf, size = pcall(function()
			return rec.model:GetBoundingBox()
		end)
		local seats = {}
		local nowS = serverNow()
		for _, seat in rec.seats do
			if seat.Parent and seat:IsDescendantOf(workspace) then
				local g = seat:GetAttribute(GUEST_ATTR)
				table.insert(seats, { cf = seat.CFrame, size = seat.Size, free = seat.Occupant == nil and not (type(g) == "number" and g > nowS), seat = seat })
			end
		end
		return {
			id = rec.id,
			kind = rec.kind,
			label = rec.id .. " · " .. (TYPE_LABEL[rec.kind] or rec.kind),
			serve = pos,
			centre = if okB and typeof(cf) == "CFrame" then cf.Position else pos,
			size = if okB and typeof(size) == "Vector3" then size else Vector3.new(6, 4, 6),
			seats = seats,
			busy = tableBusy(rec),
		}
	end;
	(hook :: BindableFunction).OnInvoke = function(method: any, a: any, b: any, c: any): any
		if method == "hold" then
			local sec = if type(a) == "number" and a == a then math.clamp(a, 0, 600) else 0
			-- paradeBusy() = os.clock() - paradeClock < Busy: push the clock so it stays busy `sec` more
			paradeClock = math.max(paradeClock, os.clock() - (PARADE.Busy or 85) + sec)
			return true
		elseif method == "tableInfo" then
			local rec = type(a) == "string" and tableById[a]
			return if rec and rec.model.Parent then info(rec) else nil
		elseif method == "tables" then
			local ids = {}
			for id, rec in tableById do
				if rec.model.Parent then
					table.insert(ids, id)
				end
			end
			table.sort(ids)
			return ids
		elseif method == "reach" then
			local rec = type(b) == "string" and tableById[b]
			if not isPlayer(a) or not rec then
				return false
			end
			return reach(a, rec, if type(c) == "number" then c else nil) ~= nil
		elseif method == "stamp" then
			local rec = type(a) == "string" and tableById[a]
			if rec and rec.model.Parent and type(b) == "number" then
				stampBottles(rec, b, if type(c) == "number" then c else 0)
				return true
			end
			return false
		elseif method == "markBusy" then
			local rec = type(a) == "string" and tableById[a]
			if rec and type(b) == "number" then
				rec.busyUntil = math.max(rec.busyUntil, b)
				return true
			end
			return false
		elseif method == "route" then
			local _, pts = routeInfo()
			return pts
		elseif method == "inClub" then
			return isPlayer(a) and inClub(a)
		end
		return nil
	end
end

remote.OnServerEvent:Connect(function(plr: Player, action: any, a: any, b: any)
	if not isPlayer(plr) or type(action) ~= "string" or not remoteAllowed(plr) then
		return
	end
	local ok, err = pcall(function()
		if action == "order" then
			onOrderRequest(plr, a, b)
		elseif action == "doorPay" then
			onDoorPay(plr, a)
		elseif action == "doorAsk" then
			onEntryPrompt(plr) -- the entry sheet's "다시 보기" / the client's own entry button
		elseif action == "dance" then
			onDance(plr)
		end
	end)
	if not ok then
		warn("[Club] remote", action, err)
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	lastCheck[plr] = nil
	lastPrompt[plr] = nil
	lastOrder[plr] = nil
	paying[plr] = nil
	lastWelcome[plr] = nil
	lastVipParade[plr] = nil
	lastDance[plr] = nil
	buckets[plr] = nil
	doorPaying[plr] = nil
	lastDoorPay[plr] = nil
	lastValidOpen[plr] = nil
	lastEject[plr] = nil
	for _, rec in tableById do
		if rec.reservedBy == plr then
			rec.reservedBy = nil
		end
	end
end)
