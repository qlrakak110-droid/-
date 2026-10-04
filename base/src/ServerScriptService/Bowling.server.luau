-- Bowling (server) — 광안 락볼링클럽 gameplay.
--
-- Lanes are Models tagged "BowlingLane" (built by build/venues/bowling_lanes.luau) with:
--   LaneFrame (foul-line centre, LookVector down the lane, attributes LaneLength/LaneWidth/...),
--   PromptAnchor, FoulBarrier, BallRest, Sweep, BumperL / BumperR (retracted rails, attribute
--   UpOffset), Pins/Pin_1..10 (PrimaryPart "Collider"), Ball (PrimaryPart "BallCore"), a SurfaceGui
--   "LaneMonitor_XX". Ball racks: parts named "BallRackPrompt" (one per pair). The hall high-score
--   board: part "HallLeaderboard" with SurfaceGui "LeaderboardGui" (rows Row1..Row5).
--
-- Flow
--   * ProximityPrompt "볼링 치기" claims a free lane; on a lane in use it becomes "합류하기": a Roblox
--     friend of a lane member (or an invited player) joins at once, anyone else sends a join request
--     the lane owner accepts or declines. Up to 4 players per lane; turns rotate per frame (a player
--     bowls the whole frame, then the next player gets a fresh rack). Late joiners start at frame 1
--     and keep bowling after the others are done.
--   * Each player has a house ball (8-16 lb, BowlingShared.Balls) picked at the ball rack ("공 고르기")
--     or from the lane menu: the lane ball takes its colour and mass; lighter balls leave the hand
--     faster, heavier balls carry the pins (physics mass) and hook more (back-end hook multiplier).
--   * Per-player bumpers: rails rise out of the gutters for that player's turns.
--   * The client sends Approach (relayed so everyone nearby sees the 4-step approach + backswing) and
--     Throw {offset, angle, spin, power}. The server validates, applies the release grade's small
--     random error, and rolls a server-owned physics ball (the only physics in the hall: idle lanes
--     keep their pins anchored and the ball parked; the hook Heartbeat runs only while a ball rolls).
--   * After the roll it counts fallen pins (tilted > 35 deg, dropped, or off the pin deck), scores the
--     roll, detects strikes / spares / splits (USBC rule) / streaks, broadcasts a Result (callouts,
--     cheers, sounds on every nearby client), renders the lane monitor sheet for all players, runs the
--     pinsetter and passes the turn.
--   * Game end: per-player summary (best frame, strikes, ...), the server high-score board, one-time
--     milestone rewards (첫 스트라이크 / 첫 터키 / 첫 200점 ...) and LastBowlingScore (Life: happiness).
--     Milestones persist in DataStore "GwangalliBowling_v1" (session memory when DataStores are off).
--   * Money: house prizes (cash) are paid through ServerStorage.GwangalliProgressAPI ("reward":
--     bank, counted as earnings with a money pop) or ServerStorage.GwangalliGameplayAPI
--     ("addMoney"); 인기 / 행복 through GwangalliGameplayAPI ("addStats"); the 4,500원 game fee through
--     GwangalliGameplayAPI ("spend"). Every API is optional: without a money API a prize stays
--     "pending" in the player's bowling record and is paid at a later game end; without "spend" the
--     game is free. Goals / achievements: GwangalliProgressAPI "track" (bowl_strike, bowl_spare,
--     bowl_turkey); bowl_game / bowl_200 come from the LastBowlingScore attribute.
--   * Server hook for other systems: ServerStorage.GwangalliBowlingEvent (BindableEvent, created
--     here) fires ("roll", player, info), ("game", player, summary), ("milestone", player, info).
--   * Lanes are released when empty; members are removed on leave / death / respawn / walking away /
--     idle. Spectators (players standing behind a lane in use) get the lane sheet.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local sharedModule = ReplicatedStorage:WaitForChild("BowlingShared", 30)
if not sharedModule then
	warn("[Bowling] ReplicatedStorage.BowlingShared missing; bowling disabled")
	return
end
local Shared = require(sharedModule)

local LANE_TAG = "BowlingLane"
local GROUP_OBJ = "BowlingObjects" -- balls + pins
local GROUP_LANE = "BowlingLane" -- static lane surfaces the ball/pins must hit
local GROUP_BARRIER = "BowlingBarrier" -- foul-line barrier: blocks players only

local CFG = {
	PinDensity = 0.6,
	PinBellyDensity = 1.3, -- lowers the centre of mass like a real pin
	PinFriction = 0.3,
	PinElasticity = 0.55,
	BallDensity = 4.5, -- 14 lb: ~4.7x a pin's mass (6.4 kg ball vs 1.5 kg pin); scaled per ball
	BallFriction = 0.04,
	BallFrictionWeight = 4,
	BallElasticity = 0.15,
	LaneFriction = 0.08, -- oiled lane
	DeckFriction = 0.3,
	HookStart = Shared.HookStart or 36, -- studs past the foul line where the oil pattern ends
	HookAccel = Shared.HookAccel or 3.5, -- lateral studs/s^2 at full spin in the back end
	HookRamp = Shared.HookRamp or 10,
	GutterMinSpeed = 8,
	RollTimeout = 7,
	SettleTime = 2.2,
	StopSpeed = 0.6,
	FallAngle = 35,
	ThrowCooldown = 1.0,
	RequestsPerSecond = 12,
	ClaimDistance = 16,
	MemberDistance = 80,
	SpectateDistance = 30, -- from the settee point behind the approach
	NearbyDistance = 150, -- swing / roll / cheer broadcasts (the whole hall)
	RackDrop = 3.2, -- pins are lowered from behind the masking unit
	ParkHeight = 4.6, -- deadwood parked inside the pinsetter
	BowlerIdle = 90, -- a bowler who does nothing on their turn for this long is removed
	InviteTTL = 25,
	ApiTimeout = 8,
	SaveInterval = 7, -- DataStore: at most one write per key per this many seconds
}

--------------------------------------------------------------------------------------------------
-- remotes (created at runtime) + server hook event
--------------------------------------------------------------------------------------------------
local folder = ReplicatedStorage:FindFirstChild(Shared.FolderName)
if not folder then
	folder = Instance.new("Folder")
	folder.Name = Shared.FolderName
	folder.Parent = ReplicatedStorage
end
local function getRemote(name: string): RemoteEvent
	local r = folder:FindFirstChild(name)
	if r and r:IsA("RemoteEvent") then
		return r
	end
	if r then
		r:Destroy()
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = folder
	return ev
end
local requestRemote = getRemote(Shared.RequestName)
local updateRemote = getRemote(Shared.UpdateName)

local hookEvent: BindableEvent
do
	local e = ServerStorage:FindFirstChild(Shared.EventName)
	if e and e:IsA("BindableEvent") then
		hookEvent = e
	else
		local ne = Instance.new("BindableEvent")
		ne.Name = Shared.EventName
		ne.Parent = ServerStorage
		hookEvent = ne
	end
end
local function fireHook(kind: string, player: Player, info: any)
	task.spawn(function()
		pcall(function()
			hookEvent:Fire(kind, player, info)
		end)
	end)
end

--------------------------------------------------------------------------------------------------
-- collision groups
--------------------------------------------------------------------------------------------------
local function ensureGroup(name: string): boolean
	local okCheck, registered = pcall(function()
		return PhysicsService:IsCollisionGroupRegistered(name)
	end)
	if okCheck and registered then
		return true
	end
	local ok, err = pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
	if not ok then
		warn("[Bowling] cannot register collision group", name, err)
	end
	return ok
end
local groupsOk = ensureGroup(GROUP_OBJ) and ensureGroup(GROUP_LANE) and ensureGroup(GROUP_BARRIER)

local function configureGroups()
	if not groupsOk then
		return
	end
	local ok, err = pcall(function()
		-- balls/pins ignore every other group (players, vehicles, props) ...
		for _, info in PhysicsService:GetRegisteredCollisionGroups() do
			local name = info.name
			if name ~= GROUP_OBJ and name ~= GROUP_LANE then
				PhysicsService:CollisionGroupSetCollidable(GROUP_OBJ, name, false)
			end
		end
		-- ... but hit the lane and each other; the barrier still blocks players (Default)
		PhysicsService:CollisionGroupSetCollidable(GROUP_OBJ, GROUP_LANE, true)
		PhysicsService:CollisionGroupSetCollidable(GROUP_OBJ, GROUP_OBJ, true)
		PhysicsService:CollisionGroupSetCollidable(GROUP_BARRIER, "Default", true)
		PhysicsService:CollisionGroupSetCollidable(GROUP_LANE, "Default", true)
	end)
	if not ok then
		warn("[Bowling] collision group setup failed:", err)
	end
end
configureGroups()

local function setGroup(part: BasePart, group: string)
	if groupsOk then
		part.CollisionGroup = group
	end
end

local function setServerOwner(part: BasePart)
	if part.Anchored then
		return
	end
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
end

--------------------------------------------------------------------------------------------------
-- records
--------------------------------------------------------------------------------------------------
type Pin = {
	n: number,
	model: Model,
	collider: BasePart,
	spot: CFrame, -- collider CFrame standing on its spot
	rest: CFrame, -- collider CFrame where it stood before the current roll
	upLocal: Vector3, -- collider-local axis that points up when standing
	template: Model?,
}

type PGame = {
	player: Player,
	rolls: { number },
	splits: { [number]: boolean }, -- roll index -> that ball left a split
	gutters: number,
	streak: number,
	lb: number,
	bumpers: boolean,
	offset: number, -- last release offset (where the bowler is set up)
	over: boolean,
	summarized: boolean,
	liveMs: { [string]: boolean },
	lastAction: number,
}

type Lane = {
	index: number,
	model: Model,
	frameCF: CFrame,
	laneLength: number,
	laneWidth: number,
	gutterWidth: number,
	ballR: number,
	deckEnd: number,
	pitDepth: number,
	pinsFolder: Instance,
	pins: { Pin },
	standing: { boolean },
	ballModel: Model,
	ballCore: BasePart,
	ballTemplate: Model?,
	restCF: CFrame,
	sweep: BasePart?,
	sweepCF: CFrame?,
	sweepTween: Tween?,
	bumpers: { BasePart },
	bumperDown: { CFrame },
	bumperUpOffset: number,
	bumpersUp: boolean,
	gui: SurfaceGui?,
	prompt: ProximityPrompt,
	prepared: boolean,
	members: { Player },
	games: { [Player]: PGame },
	turn: number,
	bowler: Player?,
	spectators: { [Player]: boolean },
	conns: { [Player]: { RBXScriptConnection } },
	state: string, -- Idle | Resetting | Ready | Rolling | Settling | GameOver
	rackRoll: number,
	standingBefore: number,
	token: number, -- bumps on new game / release / turn change (cancels pending flows)
	rollId: number,
	lastThrow: number,
	lastActivity: number,
	throwTime: number,
	spin: number,
	hookMul: number,
	inGutter: boolean,
	ballInPit: boolean,
	flashId: number,
	monCache: { [Instance]: any },
	gameNo: number,
}

local lanes: { [number]: Lane } = {}
local laneByModel: { [Instance]: Lane } = {}
local laneOf: { [Player]: Lane } = {}
local spectating: { [Player]: Lane } = {}
local activeRolls: { [Lane]: boolean } = {}
local preparedHalls: { [Instance]: boolean } = {}
local chosenLb: { [Player]: number } = {}
local hall: Instance? = nil

local function numAttr(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	if type(v) == "number" and v == v then
		return v
	end
	return default
end

local function alive(player: Player): (Humanoid?, BasePart?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hrp:IsA("BasePart") and hum.Health > 0 then
		return hum, hrp
	end
	return nil, nil
end

local function send(player: Player?, msg: { [string]: any })
	if player and player.Parent == Players then
		updateRemote:FireClient(player, msg)
	end
end

local function notify(player: Player, text: string, kind: string?)
	send(player, { type = "Notice", text = text, kind = kind })
end

-- members + spectators of a lane
local function audience(lane: Lane): { Player }
	local out = {}
	for _, p in lane.members do
		table.insert(out, p)
	end
	for p in lane.spectators do
		if p.Parent == Players and not table.find(out, p) then
			table.insert(out, p)
		end
	end
	return out
end

local function sendLane(lane: Lane, msg: { [string]: any })
	for _, p in audience(lane) do
		send(p, msg)
	end
end

-- everyone in the hall around this lane (animations / sounds / cheers)
local function sendNearby(lane: Lane, msg: { [string]: any }, except: Player?)
	local origin = lane.frameCF.Position
	for _, p in Players:GetPlayers() do
		if p ~= except then
			local _, hrp = alive(p)
			if hrp and (hrp.Position - origin).Magnitude <= CFG.NearbyDistance then
				send(p, msg)
			elseif lane.games[p] or lane.spectators[p] then
				send(p, msg)
			end
		end
	end
end

--------------------------------------------------------------------------------------------------
-- life-game API (optional) + persistence
--------------------------------------------------------------------------------------------------
local function bindable(name: string): BindableFunction?
	local f = ServerStorage:FindFirstChild(name)
	if f and f:IsA("BindableFunction") then
		return f
	end
	return nil
end

-- Invokes a server BindableFunction with a timeout (yields; callers run in their own threads).
-- Returns ("noapi" | "ok" | "error" | "timeout", result).
local function invokeTimed(apiName: string, op: string, ...: any): (string, any)
	local api = bindable(apiName)
	if not api then
		return "noapi", nil
	end
	local args = table.pack(...)
	local box = { done = false, status = "timeout", value = nil :: any }
	task.spawn(function()
		local ok, res = pcall(function()
			return (api :: BindableFunction):Invoke(op, table.unpack(args, 1, args.n))
		end)
		if box.done then
			return
		end
		box.done = true
		box.status = if ok then "ok" else "error"
		box.value = res
		if not ok then
			warn("[Bowling]", apiName, op, "failed:", res)
		end
	end)
	local t0 = os.clock()
	while not box.done and os.clock() - t0 < CFG.ApiTimeout do
		task.wait(0.05)
	end
	if not box.done then
		box.done = true
		return "timeout", nil
	end
	return box.status, box.value
end

local GAMEPLAY_API = "GwangalliGameplayAPI" -- spend / addMoney / addStats (life-game core, optional)
local PROGRESS_API = "GwangalliProgressAPI" -- reward / track (progression module, optional)

local function apiCall(op: string, ...: any): (string, any)
	return invokeTimed(GAMEPLAY_API, op, ...)
end

-- Goal / achievement counter in the progression module (fire and forget).
local function track(player: Player, key: string, n: number?)
	if not bindable(PROGRESS_API) then
		return
	end
	task.spawn(invokeTimed, PROGRESS_API, "track", player, key, n or 1)
end

-- Cash prize: the progression module's reward (bank, counted as earnings, money pop) or the life-game
-- API's addMoney. Returns true when paid.
local function payCash(player: Player, cash: number, label: string): boolean
	if cash <= 0 then
		return true
	end
	local st, res = invokeTimed(PROGRESS_API, "reward", player, cash, label)
	if st == "ok" and res == true then
		return true
	end
	st, res = apiCall("addMoney", player, cash, label)
	return st == "ok" and res ~= false and res ~= nil
end

-- Stats (인기 / 행복): the life-game API's addStats when it exists. Returns true when applied.
local function payStats(player: Player, stats: { [string]: number }?, label: string): boolean
	if not stats or next(stats) == nil then
		return true
	end
	local st = apiCall("addStats", player, stats, label)
	return st == "ok"
end

type Record = {
	loaded: boolean,
	volatile: boolean,
	best: number,
	games: number,
	strikes: number,
	ms: { [string]: boolean },
	pending: { { cash: number, stats: { [string]: number }, label: string } },
	goodDay: string,
	goodCount: number,
	dirty: boolean,
	lastSave: number,
	saveQueued: boolean,
}
local records: { [number]: Record } = {}
local store: DataStore? = nil
do
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore("GwangalliBowling_v1")
	end)
	if ok then
		store = ds
	end
end

local function dayKey(): string
	return os.date("!%Y-%m-%d", os.time() + 9 * 3600) :: string -- KST day
end

local function recordFor(player: Player): Record
	local uid = player.UserId
	local rec = records[uid]
	if rec then
		return rec
	end
	local r: Record = {
		loaded = false,
		volatile = store == nil,
		best = 0,
		games = 0,
		strikes = 0,
		ms = {},
		pending = {},
		goodDay = "",
		goodCount = 0,
		dirty = false,
		lastSave = 0,
		saveQueued = false,
	}
	records[uid] = r
	if not store then
		r.loaded = true
		return r
	end
	task.spawn(function()
		local ok, data = pcall(function()
			return (store :: DataStore):GetAsync("u" .. uid)
		end)
		if ok and type(data) == "table" then
			r.best = math.max(r.best, tonumber(data.best) or 0)
			r.games += tonumber(data.games) or 0
			r.strikes += tonumber(data.strikes) or 0
			if type(data.ms) == "table" then
				for k, v in data.ms do
					if v then
						r.ms[tostring(k)] = true
					end
				end
			end
			if type(data.pending) == "table" then
				for _, pd in data.pending do
					if type(pd) == "table" and type(pd.cash) == "number" then
						table.insert(r.pending, { cash = pd.cash, stats = if type(pd.stats) == "table" then pd.stats else {}, label = tostring(pd.label or "볼링 보상") })
					end
				end
			end
			if type(data.goodDay) == "string" then
				r.goodDay = data.goodDay
				r.goodCount = tonumber(data.goodCount) or 0
			end
		elseif not ok then
			r.volatile = true
		end
		r.loaded = true
	end)
	return r
end

local function saveRecord(uid: number)
	local r = records[uid]
	if not (r and store and not r.volatile and r.loaded and r.dirty) then
		return
	end
	local now = os.clock()
	if now - r.lastSave < CFG.SaveInterval then
		if not r.saveQueued then
			r.saveQueued = true
			task.delay(CFG.SaveInterval - (now - r.lastSave) + 0.1, function()
				r.saveQueued = false
				saveRecord(uid)
			end)
		end
		return
	end
	r.lastSave = now
	r.dirty = false
	local snapshot = {
		v = 1,
		best = r.best,
		games = r.games,
		strikes = r.strikes,
		ms = table.clone(r.ms),
		pending = table.clone(r.pending),
		goodDay = r.goodDay,
		goodCount = r.goodCount,
	}
	task.spawn(function()
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync("u" .. uid, function(old: any)
				local out = snapshot
				if type(old) == "table" then
					out.best = math.max(snapshot.best, tonumber(old.best) or 0)
					if type(old.ms) == "table" then
						for k, v in old.ms do
							if v then
								out.ms[k] = true
							end
						end
					end
				end
				return out
			end)
		end)
		if not ok then
			r.dirty = true
			warn("[Bowling] save failed:", err)
		end
	end)
end

-- Pays a prize (or keeps the cash pending until a money API exists). Returns
-- "paid" | "pending" and whether the stats were applied.
local function payReward(player: Player, cash: number, stats: { [string]: number }?, label: string): (string, boolean)
	local rec = recordFor(player)
	local statsOk = payStats(player, stats, label)
	if payCash(player, cash, label) then
		return "paid", statsOk
	end
	table.insert(rec.pending, { cash = cash, stats = {}, label = label })
	rec.dirty = true
	return "pending", statsOk
end

-- Pays prizes kept while no money API was reachable.
local function flushPending(player: Player)
	local rec = records[player.UserId]
	if not (rec and #rec.pending > 0 and (bindable(PROGRESS_API) or bindable(GAMEPLAY_API))) then
		return
	end
	local list = rec.pending
	rec.pending = {}
	for _, pd in list do
		if not payCash(player, pd.cash, pd.label) then
			table.insert(rec.pending, pd)
		end
	end
	rec.dirty = true
	saveRecord(player.UserId)
end

-- Server high scores (this server, since it started).
type HighScore = { userId: number, name: string, score: number, lane: number, t: number, strikes: number }
local highScores: { HighScore } = {}
local leaderboardGui: SurfaceGui? = nil

local function renderLeaderboard()
	local g = leaderboardGui
	if not (g and g.Parent) then
		return
	end
	local face = g:FindFirstChild("Face")
	if not face then
		return
	end
	for i = 1, 5 do
		local row = face:FindFirstChild("Row" .. i)
		if row and row:IsA("TextLabel") then
			local h = highScores[i]
			row.Text = if h then string.format("%d. %s   %d점   (%d번 레인)", i, h.name, h.score, h.lane) else string.format("%d.  ─", i)
		end
	end
end

local function addHighScore(player: Player, score: number, laneIndex: number, strikes: number): number
	table.insert(highScores, { userId = player.UserId, name = player.DisplayName, score = score, lane = laneIndex, t = os.time(), strikes = strikes })
	table.sort(highScores, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.t < b.t
	end)
	local rank = 0
	for i, h in highScores do
		if h.userId == player.UserId and h.score == score and rank == 0 then
			rank = i
		end
	end
	while #highScores > 10 do
		table.remove(highScores)
	end
	renderLeaderboard()
	return if rank <= 10 then rank else 0
end

--------------------------------------------------------------------------------------------------
-- pins / ball preparation (lazy: a lane is prepared the first time somebody claims it)
--------------------------------------------------------------------------------------------------
local function preparePinModel(pm: Model): (BasePart?)
	local collider = pm.PrimaryPart or pm:FindFirstChild("Collider")
	if not (collider and collider:IsA("BasePart")) then
		return nil
	end
	collider.Anchored = true
	local visuals = {}
	for _, d in pm:GetDescendants() do
		if d:IsA("BasePart") and d ~= collider then
			d.Anchored = true
			if not d:FindFirstChild("BowlingWeld") then
				local w = Instance.new("WeldConstraint")
				w.Name = "BowlingWeld"
				w.Part0 = collider
				w.Part1 = d
				w.Parent = d
			end
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = d.Name ~= "Belly"
			if d.Name == "Belly" then
				d.CustomPhysicalProperties = PhysicalProperties.new(CFG.PinBellyDensity, CFG.PinFriction, CFG.PinElasticity)
			end
			setGroup(d, GROUP_OBJ)
			table.insert(visuals, d)
		end
	end
	for _, d in visuals do
		d.Anchored = false
	end
	collider.CanCollide = true
	collider.CanTouch = false
	collider.CustomPhysicalProperties = PhysicalProperties.new(CFG.PinDensity, CFG.PinFriction, CFG.PinElasticity, 1, 1)
	setGroup(collider, GROUP_OBJ)
	pm.PrimaryPart = collider
	return collider
end

local function ballProps(lb: number): PhysicalProperties
	local b = Shared.ball(lb)
	return PhysicalProperties.new(CFG.BallDensity * b.mass, CFG.BallFriction, CFG.BallElasticity, CFG.BallFrictionWeight, 1)
end

local function prepareBallModel(bm: Model): (BasePart?)
	local core = bm.PrimaryPart or bm:FindFirstChild("BallCore")
	if not (core and core:IsA("BasePart")) then
		return nil
	end
	core.Anchored = true
	local visuals = {}
	for _, d in bm:GetDescendants() do
		if d:IsA("BasePart") and d ~= core then
			d.Anchored = true
			if not d:FindFirstChild("BowlingWeld") then
				local w = Instance.new("WeldConstraint")
				w.Name = "BowlingWeld"
				w.Part0 = core
				w.Part1 = d
				w.Parent = d
			end
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			setGroup(d, GROUP_OBJ)
			table.insert(visuals, d)
		end
	end
	for _, d in visuals do
		d.Anchored = false
	end
	core.CanCollide = true
	core.CanTouch = false
	core.CustomPhysicalProperties = ballProps(Shared.DefaultLb)
	setGroup(core, GROUP_OBJ)
	bm.PrimaryPart = core
	return core
end

-- Re-creates a pin / the ball if something destroyed it (e.g. FallenPartsDestroyHeight).
local function ensurePin(lane: Lane, pin: Pin)
	if pin.model.Parent and pin.collider.Parent and pin.collider:IsDescendantOf(pin.model) then
		return
	end
	if not pin.template then
		return
	end
	if pin.model.Parent then
		pin.model:Destroy() -- half-destroyed leftovers
	end
	local clone = (pin.template :: Model):Clone()
	clone.Parent = lane.pinsFolder
	local collider = preparePinModel(clone)
	if collider then
		pin.model = clone
		pin.collider = collider
	end
end

local function ensureBall(lane: Lane)
	if lane.ballModel.Parent and lane.ballCore.Parent and lane.ballCore:IsDescendantOf(lane.ballModel) then
		return
	end
	if not lane.ballTemplate then
		return
	end
	if lane.ballModel.Parent then
		lane.ballModel:Destroy()
	end
	local clone = (lane.ballTemplate :: Model):Clone()
	clone.Parent = lane.model
	local core = prepareBallModel(clone)
	if core then
		lane.ballModel = clone
		lane.ballCore = core
	end
end

local function pinSet(pin: Pin, cf: CFrame)
	local c = pin.collider
	c.Anchored = true
	pin.model:PivotTo(cf)
	c.AssemblyLinearVelocity = Vector3.zero
	c.AssemblyAngularVelocity = Vector3.zero
end

local function parkCF(pin: Pin): CFrame
	return pin.spot + Vector3.new(0, CFG.ParkHeight, 0)
end

local function freezePins(lane: Lane)
	for _, pin in lane.pins do
		ensurePin(lane, pin)
		pin.collider.Anchored = true
		pin.collider.AssemblyLinearVelocity = Vector3.zero
		pin.collider.AssemblyAngularVelocity = Vector3.zero
	end
end

local function parkBall(lane: Lane)
	ensureBall(lane)
	local core = lane.ballCore
	core.Anchored = true
	lane.ballModel:PivotTo(lane.restCF)
	core.AssemblyLinearVelocity = Vector3.zero
	core.AssemblyAngularVelocity = Vector3.zero
end

local function countStanding(lane: Lane): number
	local n = 0
	for i = 1, 10 do
		if lane.standing[i] then
			n += 1
		end
	end
	return n
end

-- Official rule: a pin counts as down when it is knocked over or knocked off the pin deck. A pin
-- that slides off its spot but stays standing on the deck is a standing pin (the pinsetter
-- respots it where it stands, see sweepCycle).
local function pinFallen(lane: Lane, pin: Pin): boolean
	local c = pin.collider
	if not c.Parent then
		return true
	end
	local up = c.CFrame:VectorToWorldSpace(pin.upLocal)
	if up.Y < math.cos(math.rad(CFG.FallAngle)) then
		return true
	end
	if c.Position.Y < pin.spot.Position.Y - 0.35 then
		return true -- dropped into the pit or the gutter
	end
	-- the pin deck starts ~0.55 studs in front of the head pin (bowling_config W_DECK)
	local rel = lane.frameCF:PointToObjectSpace(c.Position)
	local dist = -rel.Z
	if math.abs(rel.X) > lane.laneWidth / 2 or dist > lane.deckEnd or dist < lane.laneLength - 0.8 then
		return true -- standing, but off the pin deck (in a gutter, the pit or out on the lane)
	end
	return false
end

-- Sets a fresh rack of 10 (optionally lowered from the pinsetter).
local function rackAll(lane: Lane, animate: boolean, token: number)
	for n, pin in lane.pins do
		ensurePin(lane, pin)
		lane.standing[n] = true
		pin.rest = pin.spot
	end
	if animate then
		local steps = 10
		for s = steps, 0, -1 do
			if lane.token ~= token then
				return
			end
			local h = CFG.RackDrop * (s / steps)
			for _, pin in lane.pins do
				pinSet(pin, pin.spot + Vector3.new(0, h, 0))
			end
			task.wait(0.04)
		end
	else
		for _, pin in lane.pins do
			pinSet(pin, pin.spot)
		end
	end
end

-- Tweens the sweep bar and waits; the tween is kept on the lane so release() can cancel it.
local function tweenSweep(lane: Lane, cf: CFrame, t: number)
	local sw = lane.sweep
	if not sw then
		task.wait(t)
		return
	end
	if lane.sweepTween then
		lane.sweepTween:Cancel()
	end
	local tw = TweenService:Create(sw, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = cf })
	lane.sweepTween = tw
	tw:Play()
	task.wait(t)
end

local function resetSweep(lane: Lane)
	if lane.sweepTween then
		lane.sweepTween:Cancel()
		lane.sweepTween = nil
	end
	if lane.sweep and lane.sweepCF then
		lane.sweep.CFrame = lane.sweepCF
	end
end

-- Pinsetter cycle: sweep drops, (standing pins are lifted), sweep clears the deck into the pit
-- (deadwood parked), sweep returns, standing pins are set back down upright.
local function sweepCycle(lane: Lane, token: number, keepStanding: boolean)
	local sw, base = lane.sweep, lane.sweepCF
	local lifted: { Pin } = {}
	if keepStanding then
		for n, pin in lane.pins do
			if lane.standing[n] then
				local p = pin.collider.Position
				pin.rest = CFrame.new(p.X, pin.spot.Position.Y, p.Z) * pin.spot.Rotation
				table.insert(lifted, pin)
			end
		end
	end
	local down, back
	if sw and base then
		down = base - Vector3.new(0, numAttr(sw, "DropHeight", 3.45), 0)
		back = down + lane.frameCF.LookVector * numAttr(sw, "Travel", 4)
		tweenSweep(lane, down, 0.3)
	else
		task.wait(0.3)
	end
	if lane.token ~= token then
		return
	end
	-- the table picks the standing pins up
	for s = 1, 5 do
		for _, pin in lifted do
			pinSet(pin, pin.rest + Vector3.new(0, CFG.RackDrop * s / 5, 0))
		end
		task.wait(0.04)
	end
	if sw and back then
		tweenSweep(lane, back, 0.45)
	end
	if lane.token ~= token then
		return
	end
	for n, pin in lane.pins do
		if not (keepStanding and lane.standing[n]) then
			pinSet(pin, parkCF(pin))
		end
	end
	if sw and down and base then
		tweenSweep(lane, down, 0.35)
		tweenSweep(lane, base, 0.3)
	end
	if lane.token ~= token then
		return
	end
	for s = 4, 0, -1 do
		for _, pin in lifted do
			pinSet(pin, pin.rest + Vector3.new(0, CFG.RackDrop * s / 5, 0))
		end
		task.wait(0.04)
	end
end

--------------------------------------------------------------------------------------------------
-- bumpers (retracted rails in the gutters; raised for players who turned them on)
--------------------------------------------------------------------------------------------------
local function setBumpers(lane: Lane, on: boolean)
	if lane.bumpersUp == on or #lane.bumpers == 0 then
		return
	end
	lane.bumpersUp = on
	for i, part in lane.bumpers do
		local down = lane.bumperDown[i]
		local goal = if on then down + Vector3.new(0, lane.bumperUpOffset, 0) else down
		if on then
			part.CanCollide = true
		end
		local tw = TweenService:Create(part, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal })
		tw:Play()
		if not on then
			tw.Completed:Connect(function()
				if not lane.bumpersUp then
					part.CanCollide = false
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------------------------
-- lane monitor (scoreboard SurfaceGui, 510 x 295 px): up to 4 players
--------------------------------------------------------------------------------------------------
local MON_ROWS = 4
local FRAME_X = {}
do
	local x = 0.17
	for f = 1, 10 do
		local w = f < 10 and 0.064 or 0.088
		FRAME_X[f] = { x, w }
		x += w
	end
	FRAME_X[11] = { x + 0.006, 0.985 - x - 0.006 }
end

local COL = {
	bg1 = Color3.fromRGB(40, 12, 90),
	bg2 = Color3.fromRGB(8, 26, 76),
	gold = Color3.fromRGB(255, 205, 70),
	cyan = Color3.fromRGB(80, 235, 255),
	magenta = Color3.fromRGB(255, 80, 190),
	white = Color3.fromRGB(255, 255, 255),
	sub = Color3.fromRGB(180, 172, 230),
	dim = Color3.fromRGB(120, 116, 160),
	cell = Color3.fromRGB(250, 250, 255),
	red = Color3.fromRGB(255, 96, 96),
}

local function label(parent: Instance, name: string, pos: UDim2, size: UDim2, text: string, color: Color3, font: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = color
	t.Font = font or Enum.Font.GothamBold
	t.ZIndex = 6
	t.Parent = parent
	return t
end

local function idleFace(lane: Lane, visible: boolean)
	local gui = lane.gui
	if not gui then
		return
	end
	local face = gui:FindFirstChild("Face")
	if face then
		for _, c in face:GetChildren() do
			if c:IsA("GuiObject") then
				c.Visible = visible
			end
		end
	end
end

local function buildBoard(lane: Lane)
	local gui = lane.gui
	if not gui then
		return
	end
	local old = gui:FindFirstChild("Board")
	if old then
		old:Destroy()
	end
	lane.monCache = {}
	idleFace(lane, false)
	local board = Instance.new("Frame")
	board.Name = "Board"
	board.Size = UDim2.fromScale(1, 1)
	board.BackgroundColor3 = Color3.fromRGB(12, 10, 36)
	board.BorderSizePixel = 0
	board.ZIndex = 5
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(COL.bg1, COL.bg2)
	grad.Rotation = 90
	grad.Parent = board
	label(board, "Lane", UDim2.fromScale(0.02, 0.02), UDim2.fromScale(0.16, 0.12), string.format("LANE %02d", lane.index), COL.gold, Enum.Font.GothamBlack)
	label(board, "Bowler", UDim2.fromScale(0.2, 0.02), UDim2.fromScale(0.56, 0.12), "", COL.white)
	-- pin diagram (top-right): back row on top, head pin at the bottom
	local pinsF = Instance.new("Frame")
	pinsF.Name = "PinDiagram"
	pinsF.BackgroundTransparency = 1
	pinsF.Position = UDim2.fromScale(0.82, 0.015)
	pinsF.Size = UDim2.fromScale(0.16, 0.145)
	pinsF.ZIndex = 6
	pinsF.Parent = board
	for n = 1, 10 do
		local dot = Instance.new("Frame")
		dot.Name = "P" .. n
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale((Shared.PinX[n] + 1.524) / 3.048 * 0.84 + 0.08, (4 - Shared.PinRow[n]) / 3 * 0.8 + 0.1)
		dot.Size = UDim2.fromScale(0.13, 0.22)
		dot.BackgroundColor3 = COL.white
		dot.BorderSizePixel = 0
		dot.ZIndex = 7
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = dot
		dot.Parent = pinsF
	end
	for r = 1, MON_ROWS do
		local row = Instance.new("Frame")
		row.Name = "Row" .. r
		row.BackgroundColor3 = COL.white
		row.BackgroundTransparency = 0.94
		row.BorderSizePixel = 0
		row.ZIndex = 5
		row.Visible = false
		local st = Instance.new("UIStroke")
		st.Name = "Stroke"
		st.Color = COL.gold
		st.Thickness = 0
		st.Parent = row
		row.Parent = board
		label(row, "Name", UDim2.fromScale(0.01, 0.05), UDim2.fromScale(0.155, 0.9), "", COL.white)
		for f = 1, 11 do
			local fx = FRAME_X[f]
			local box = Instance.new("Frame")
			box.Name = f <= 10 and ("F" .. f) or "FT"
			box.Position = UDim2.fromScale(fx[1], 0.06)
			box.Size = UDim2.fromScale(fx[2] - 0.004, 0.88)
			box.BackgroundColor3 = COL.cell
			box.BackgroundTransparency = 0.9
			box.BorderSizePixel = 0
			box.ZIndex = 5
			local stroke = Instance.new("UIStroke")
			stroke.Name = "Stroke"
			stroke.Color = Color3.fromRGB(150, 140, 220)
			stroke.Thickness = 1
			stroke.Parent = box
			box.Parent = row
			if f <= 10 then
				local n = f < 10 and 2 or 3
				for k = 1, n do
					label(box, "M" .. k, UDim2.fromScale((k - 1) / n, 0.02), UDim2.fromScale(1 / n, 0.46), "", COL.white, Enum.Font.GothamBlack)
				end
				label(box, "Score", UDim2.fromScale(0, 0.5), UDim2.fromScale(1, 0.48), "", Color3.fromRGB(255, 240, 150))
			else
				label(box, "Score", UDim2.fromScale(0, 0.1), UDim2.fromScale(1, 0.8), "0", COL.cyan, Enum.Font.GothamBlack)
			end
		end
	end
	label(board, "Status", UDim2.fromScale(0.03, 0.87), UDim2.fromScale(0.94, 0.11), "", Color3.fromRGB(230, 230, 255), Enum.Font.GothamMedium)
	-- callout overlay (the UIScale "Pop" is animated locally by nearby clients)
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.fromRGB(220, 20, 140)
	flash.BackgroundTransparency = 0.06
	flash.BorderSizePixel = 0
	flash.ZIndex = 10
	flash.Visible = false
	local fg = Instance.new("UIGradient")
	fg.Rotation = 90
	fg.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 170))
	fg.Parent = flash
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = flash
	local ft = label(flash, "Title", UDim2.fromScale(0.04, 0.12), UDim2.fromScale(0.92, 0.5), "", COL.white, Enum.Font.GothamBlack)
	ft.ZIndex = 11
	ft.TextStrokeTransparency = 0.4
	local fs = label(flash, "Sub", UDim2.fromScale(0.06, 0.64), UDim2.fromScale(0.88, 0.2), "", COL.white, Enum.Font.GothamBold)
	fs.ZIndex = 11
	flash.Parent = board
	board.Parent = gui
end

local function hideBoard(lane: Lane)
	local gui = lane.gui
	if gui then
		local b = gui:FindFirstChild("Board")
		if b then
			b:Destroy()
		end
	end
	lane.monCache = {}
	idleFace(lane, true)
end

local function setProp(lane: Lane, inst: Instance?, prop: string, value: any)
	if not inst then
		return
	end
	local cache = lane.monCache[inst]
	if not cache then
		cache = {}
		lane.monCache[inst] = cache
	end
	if cache[prop] ~= value then
		cache[prop] = value;
		(inst :: any)[prop] = value
	end
end

local function boardOf(g: PGame): any
	return Shared.board(g.rolls, g.splits)
end

local function renderBoard(lane: Lane, callout: any?)
	local gui = lane.gui
	local board = gui and gui:FindFirstChild("Board")
	if not board then
		return
	end
	local n = #lane.members
	local bowler = lane.bowler
	local bg = bowler and lane.games[bowler]
	local prog = bg and Shared.progress(bg.rolls)
	setProp(lane, board:FindFirstChild("Bowler"), "Text", if bowler then (bowler.DisplayName .. " 차례") else "")
	-- pin diagram
	local pd = board:FindFirstChild("PinDiagram")
	if pd then
		for p = 1, 10 do
			local dot = pd:FindFirstChild("P" .. p)
			setProp(lane, dot, "BackgroundTransparency", if lane.standing[p] then 0 else 0.8)
		end
	end
	local rows = math.max(n, 1)
	local top, bottom = 0.17, 0.85
	local rowH = math.min((bottom - top) / math.max(rows, 2), 0.24)
	for r = 1, MON_ROWS do
		local row = board:FindFirstChild("Row" .. r)
		if not row then
			continue
		end
		local p = lane.members[r]
		local g = p and lane.games[p]
		setProp(lane, row, "Visible", g ~= nil)
		if not g then
			continue
		end
		local b = boardOf(g)
		local gp = Shared.progress(g.rolls)
		setProp(lane, row, "Position", UDim2.fromScale(0.01, top + (r - 1) * rowH))
		setProp(lane, row, "Size", UDim2.fromScale(0.98, rowH - 0.01))
		local isBowler = p == bowler and lane.state ~= "GameOver"
		setProp(lane, row:FindFirstChild("Stroke"), "Thickness", if isBowler then 3 else 0)
		setProp(lane, row, "BackgroundTransparency", if isBowler then 0.82 else 0.94)
		setProp(lane, row:FindFirstChild("Name"), "Text", (p :: Player).DisplayName)
		setProp(lane, row:FindFirstChild("Name"), "TextColor3", if g.over then COL.dim else COL.white)
		for f = 1, 10 do
			local box = row:FindFirstChild("F" .. f)
			local fi = b.frames[f]
			if box and fi then
				for k = 1, 3 do
					local m = box:FindFirstChild("M" .. k)
					if m then
						local s = fi.marks[k] or ""
						local sp = fi.splits and fi.splits[k]
						setProp(lane, m, "Text", if sp and s ~= "" then ("(" .. s .. ")") else s)
						setProp(lane, m, "TextColor3", if (s == "X" or s == "/") then COL.magenta elseif sp then COL.red else COL.white)
					end
				end
				setProp(lane, box:FindFirstChild("Score"), "Text", fi.score and tostring(fi.score) or "")
				local current = isBowler and not gp.over and f == gp.frame
				setProp(lane, box:FindFirstChild("Stroke"), "Color", if current then COL.gold else Color3.fromRGB(150, 140, 220))
				setProp(lane, box:FindFirstChild("Stroke"), "Thickness", if current then 3 else 1)
			end
		end
		local ft = row:FindFirstChild("FT")
		setProp(lane, ft and ft:FindFirstChild("Score"), "Text", tostring(b.total))
	end
	local status = board:FindFirstChild("Status")
	if lane.state == "GameOver" then
		local best, bestName = -1, ""
		for _, p in lane.members do
			local g = lane.games[p]
			if g then
				local t = boardOf(g).total
				if t > best then
					best, bestName = t, p.DisplayName
				end
			end
		end
		setProp(lane, status, "Text", if n > 1 then string.format("GAME OVER · 1위 %s %d점", bestName, best) else string.format("GAME OVER · %d점", math.max(best, 0)))
	elseif prog then
		setProp(lane, status, "Text", string.format("%d프레임 %d구 · 남은 핀 %d%s", prog.frame, prog.roll, countStanding(lane), if bg and bg.bumpers then " · 범퍼 ON" else ""))
	else
		setProp(lane, status, "Text", "")
	end
	local flash = board:FindFirstChild("Flash")
	if callout and flash and flash:IsA("Frame") then
		lane.flashId += 1
		local id = lane.flashId
		local c = callout.color or { 255, 80, 190 }
		flash.BackgroundColor3 = Color3.fromRGB(c[1], c[2], c[3])
		local t = flash:FindFirstChild("Title")
		local s = flash:FindFirstChild("Sub")
		if t and t:IsA("TextLabel") then
			t.Text = callout.text or ""
		end
		if s and s:IsA("TextLabel") then
			s.Text = callout.sub or ""
		end
		flash.Visible = true
		task.delay(if callout.big then 2.2 else 1.4, function()
			if lane.flashId == id and flash.Parent then
				flash.Visible = false
			end
		end)
	end
end

--------------------------------------------------------------------------------------------------
-- state messages
--------------------------------------------------------------------------------------------------
local function standingList(lane: Lane): { number }
	local out = {}
	for i = 1, 10 do
		out[i] = if lane.standing[i] then 1 else 0
	end
	return out
end

local function playersInfo(lane: Lane): { any }
	local out = {}
	for _, p in lane.members do
		local g = lane.games[p]
		if g then
			local b = boardOf(g)
			table.insert(out, {
				userId = p.UserId,
				name = p.DisplayName,
				board = b,
				total = b.total,
				lb = g.lb,
				bumpers = g.bumpers,
				over = g.over,
				owner = p == lane.members[1],
			})
		end
	end
	return out
end

local function stateMessage(lane: Lane): { [string]: any }
	local bowler = lane.bowler
	local g = bowler and lane.games[bowler]
	local prog = g and Shared.progress(g.rolls) or { frame = 1, roll = 1 }
	return {
		type = "State",
		lane = lane.index,
		state = lane.state,
		bowler = bowler and bowler.UserId or 0,
		bowlerName = bowler and bowler.DisplayName or "",
		owner = lane.members[1] and lane.members[1].UserId or 0,
		players = playersInfo(lane),
		frame = prog.frame,
		roll = prog.roll,
		pinsLeft = countStanding(lane),
		standing = standingList(lane),
		count = #lane.members,
	}
end

local function sendState(lane: Lane)
	local msg = stateMessage(lane)
	for _, p in lane.members do
		send(p, msg)
	end
	if next(lane.spectators) then
		local sm = table.clone(msg)
		sm.spectating = true
		for p in lane.spectators do
			send(p, sm)
		end
	end
end

--------------------------------------------------------------------------------------------------
-- character placement
--------------------------------------------------------------------------------------------------
local function rootHeight(hum: Humanoid, hrp: BasePart): number
	if hum.RigType == Enum.HumanoidRigType.R15 then
		return hum.HipHeight + hrp.Size.Y / 2
	end
	return 3
end

local function placeCharacter(player: Player, lane: Lane, x: number, back: number)
	local hum, hrp = alive(player)
	local char = player.Character
	if not (hum and hrp and char) then
		return
	end
	-- Stand up first: the client blocks the jump while a lane is open (it would cover the throw
	-- button on phones), so a player left in a bench seat could not get up by themselves.
	local seat = hum.SeatPart
	if seat then
		hum.Sit = false
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	local half = lane.laneWidth / 2 + lane.gutterWidth - 0.4
	local cf = lane.frameCF * CFrame.new(math.clamp(x, -half, half), rootHeight(hum, hrp) + 0.1, back)
	char:PivotTo(cf)
end

local function stanceX(g: PGame): number
	return g.offset - Shared.HandOffset
end

local function updatePrompt(lane: Lane)
	local n = #lane.members
	if n == 0 then
		lane.prompt.ActionText = Shared.PromptText
		lane.prompt.ObjectText = string.format("%d번 레인 · %s", lane.index, Shared.PriceText)
		lane.prompt.Enabled = true
	elseif n < Shared.MaxPlayers then
		lane.prompt.ActionText = "합류하기"
		lane.prompt.ObjectText = string.format("%d번 레인 · %d/%d명 · %s", lane.index, n, Shared.MaxPlayers, lane.members[1].DisplayName)
		lane.prompt.Enabled = true
	else
		lane.prompt.ActionText = "관전 중"
		lane.prompt.ObjectText = string.format("%d번 레인 · 만석 (%d명)", lane.index, n)
		lane.prompt.Enabled = false
	end
end

--------------------------------------------------------------------------------------------------
-- lane preparation (first claim)
--------------------------------------------------------------------------------------------------
local function prepareHallParts(h: Instance)
	if preparedHalls[h] then
		return
	end
	preparedHalls[h] = true
	for _, name in { "Pit", "Cappings" } do
		local m = h:FindFirstChild(name)
		if m then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.CanCollide then
					setGroup(d, GROUP_LANE)
				end
			end
		end
	end
end

local function prepareLane(lane: Lane): boolean
	if lane.prepared then
		return true
	end
	local model = lane.model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not d:IsDescendantOf(lane.pinsFolder) and not d:IsDescendantOf(lane.ballModel) then
			if d.Name == "FoulBarrier" then
				d.CanCollide = true
				d.Transparency = 1
				setGroup(d, GROUP_BARRIER)
			elseif d.Name == "BumperL" or d.Name == "BumperR" then
				setGroup(d, GROUP_LANE)
				d.CustomPhysicalProperties = PhysicalProperties.new(1.5, 0.08, 0.55, 1, 1)
			elseif d.CanCollide then
				setGroup(d, GROUP_LANE)
				if d.Name == "LaneBed" then
					d.CustomPhysicalProperties = PhysicalProperties.new(0.7, CFG.LaneFriction, 0.2, 1, 1)
				elseif d.Name == "PinDeck" then
					d.CustomPhysicalProperties = PhysicalProperties.new(0.7, CFG.DeckFriction, 0.3, 1, 1)
				end
			end
		end
	end
	if model.Parent then
		prepareHallParts(model.Parent)
	end
	for n, pin in lane.pins do
		local collider = preparePinModel(pin.model)
		if not collider then
			warn("[Bowling] lane", lane.index, "pin without collider", n)
			return false
		end
		pin.collider = collider
		pin.template = pin.model:Clone()
	end
	local core = prepareBallModel(lane.ballModel)
	if not core then
		warn("[Bowling] lane", lane.index, "ball without BallCore")
		return false
	end
	lane.ballCore = core
	lane.ballTemplate = lane.ballModel:Clone()
	lane.prepared = true
	return true
end

--------------------------------------------------------------------------------------------------
-- game flow
--------------------------------------------------------------------------------------------------
local release: (Lane, string) -> ()
local removeMember: (Lane, Player, string) -> ()
local beginTurn: (Lane, boolean) -> ()

local function newPGame(player: Player, old: PGame?): PGame
	return {
		player = player,
		rolls = {},
		splits = {},
		gutters = 0,
		streak = 0,
		lb = chosenLb[player] or (old and old.lb) or Shared.DefaultLb,
		bumpers = if old then old.bumpers else false,
		offset = if old then old.offset else 0,
		over = false,
		summarized = false,
		liveMs = {},
		lastAction = os.clock(),
	}
end

-- Charges the game fee (when the life-game API exists). Returns true when the player may play.
local function chargeFee(player: Player): boolean
	if Shared.GameFee <= 0 then
		return true
	end
	local st, res = apiCall("spend", player, Shared.GameFee, "광안 락볼링클럽 1게임")
	if st == "noapi" then
		return true
	end
	if st == "ok" and res == true then
		return true
	end
	if st == "ok" then
		notify(player, string.format("잔액이 부족해요. 볼링 1게임은 %s원이에요.", "4,500"), "warn")
		return false
	end
	-- API error / timeout: let them play (never block the fun on a backend hiccup)
	return true
end

local function laneTokenFlow(lane: Lane, fn: (token: number) -> ())
	lane.token += 1
	local token = lane.token
	task.spawn(fn, token)
end

-- Full-rack reset, then the current bowler's turn.
local function freshRackThenTurn(lane: Lane, token: number)
	lane.state = "Resetting"
	freezePins(lane)
	parkBall(lane)
	sendState(lane)
	if lane.sweep then
		sweepCycle(lane, token, false)
	end
	if lane.token ~= token then
		return
	end
	rackAll(lane, true, token)
	if lane.token ~= token then
		return
	end
	lane.rackRoll = 1
	beginTurn(lane, true)
end

local function newGame(lane: Lane)
	lane.gameNo += 1
	activeRolls[lane] = nil
	for _, p in lane.members do
		lane.games[p] = newPGame(p, lane.games[p])
	end
	lane.turn = 1
	lane.bowler = lane.members[1]
	lane.rackRoll = 1
	buildBoard(lane)
	renderBoard(lane, nil)
	laneTokenFlow(lane, function(token)
		freshRackThenTurn(lane, token)
	end)
end

function beginTurn(lane: Lane, fresh: boolean)
	local bowler = lane.members[lane.turn]
	lane.bowler = bowler
	if not bowler then
		return
	end
	local g = lane.games[bowler]
	if not g then
		return
	end
	g.lastAction = os.clock()
	lane.lastActivity = os.clock()
	-- the lane ball becomes this bowler's house ball
	ensureBall(lane)
	local core = lane.ballCore
	core.Color = Shared.ballColor(g.lb)
	core.CustomPhysicalProperties = ballProps(g.lb)
	setBumpers(lane, g.bumpers)
	if fresh then
		-- step up to the approach: the client walks its character there; only a bowler far away
		-- (at the bar, in the lounge) is moved by the server
		local _, hrp = alive(bowler)
		local spot = (lane.frameCF * CFrame.new(stanceX(g), 0, Shared.StanceBack)).Position
		if not hrp or (hrp.Position - spot).Magnitude > 16 then
			placeCharacter(bowler, lane, stanceX(g), Shared.StanceBack)
		end
	end
	lane.state = "Ready"
	renderBoard(lane, nil)
	sendState(lane)
	sendNearby(lane, { type = "Turn", lane = lane.index, userId = bowler.UserId, name = bowler.DisplayName, lb = g.lb, fresh = fresh })
end

-- Next member (cyclic) whose game is not over; nil when everybody is done.
local function nextTurnIndex(lane: Lane): number?
	local n = #lane.members
	if n == 0 then
		return nil
	end
	for k = 1, n do
		local idx = ((lane.turn - 1 + k) % n) + 1
		local g = lane.games[lane.members[idx]]
		if g and not g.over then
			return idx
		end
	end
	return nil
end

local function gameOverLane(lane: Lane, token: number)
	lane.state = "GameOver"
	lane.bowler = nil
	renderBoard(lane, nil)
	sendState(lane)
	task.wait(2)
	if lane.token ~= token then
		return
	end
	sweepCycle(lane, token, false)
	if lane.token ~= token then
		return
	end
	rackAll(lane, true, token)
	setBumpers(lane, false)
end

-- Milestones + summary for a player whose game just ended.
local function finishPlayerGame(lane: Lane, g: PGame)
	if g.summarized then
		return
	end
	g.summarized = true
	local player = g.player
	local sm = Shared.summary(g.rolls, g.splits, g.gutters)
	local rec = recordFor(player)
	local isBest = sm.total > rec.best
	rec.best = math.max(rec.best, sm.total)
	rec.games += 1
	rec.strikes += sm.strikes
	rec.dirty = true
	local rank = addHighScore(player, sm.total, lane.index, sm.strikes)
	player:SetAttribute("LastBowlingScore", sm.total)
	fireHook("game", player, { lane = lane.index, total = sm.total, strikes = sm.strikes, spares = sm.spares, maxStreak = sm.maxStreak, clean = sm.clean, perfect = sm.perfect, players = #lane.members })
	local laneIndex = lane.index
	task.spawn(function()
		-- wait (briefly) for the record so one-time milestones are not granted twice
		local t0 = os.clock()
		while not rec.loaded and os.clock() - t0 < 6 do
			task.wait(0.25)
		end
		local rewards = {}
		for _, id in Shared.milestonesReached(sm, true) do
			local m = Shared.milestone(id)
			if m and not rec.ms[id] and not g.liveMs[id] then
				rec.ms[id] = true
				rec.dirty = true
				local status, statsOk = payReward(player, m.cash, m.stats, "볼링장 경품 · " .. m.title)
				table.insert(rewards, { id = id, title = m.title, cash = m.cash, stats = if statsOk then m.stats else {}, status = status })
				fireHook("milestone", player, { id = id, title = m.title, cash = m.cash, stats = m.stats, status = status })
			end
		end
		-- repeatable: a good game gives a little popularity (twice a day)
		local GG = Shared.GoodGame
		if sm.total >= GG.score then
			local today = dayKey()
			if rec.goodDay ~= today then
				rec.goodDay = today
				rec.goodCount = 0
			end
			if rec.goodCount < GG.dailyCap then
				rec.goodCount += 1
				rec.dirty = true
				if payStats(player, GG.stats, "볼링 하이스코어 🎳") and bindable(GAMEPLAY_API) then
					table.insert(rewards, { id = "good_game", title = string.format("%d점 이상 게임", GG.score), cash = 0, stats = GG.stats, status = "paid" })
				end
			end
		end
		flushPending(player)
		saveRecord(player.UserId)
		send(player, {
			type = "Summary",
			lane = laneIndex,
			summary = sm,
			rewards = rewards,
			rank = rank,
			best = rec.best,
			isBest = isBest,
			games = rec.games,
			players = #lane.members,
		})
	end)
end

-- Live milestones (first strike / turkey / split conversion) granted the moment they happen.
local function liveMilestones(lane: Lane, g: PGame)
	local rec = recordFor(g.player)
	if not rec.loaded then
		return -- checked again at the game end
	end
	local sm = Shared.summary(g.rolls, g.splits, g.gutters)
	for _, id in Shared.milestonesReached(sm, false) do
		local m = Shared.milestone(id)
		if m and m.live and not rec.ms[id] and not g.liveMs[id] then
			rec.ms[id] = true
			g.liveMs[id] = true
			rec.dirty = true
			local player = g.player
			task.spawn(function()
				local status, statsOk = payReward(player, m.cash, m.stats, "볼링장 경품 · " .. m.title)
				send(player, { type = "Milestone", lane = lane.index, id = id, title = m.title, cash = m.cash, stats = if statsOk then m.stats else {}, status = status })
				fireHook("milestone", player, { id = id, title = m.title, cash = m.cash, stats = m.stats, status = status })
				saveRecord(player.UserId)
			end)
		end
	end
end

local function finishRoll(lane: Lane)
	if lane.state ~= "Rolling" then
		return
	end
	activeRolls[lane] = nil
	lane.state = "Settling"
	local token, rollId = lane.token, lane.rollId
	local bowler = lane.bowler
	local g = bowler and lane.games[bowler]
	task.spawn(function()
		task.wait(CFG.SettleTime)
		if lane.token ~= token or lane.rollId ~= rollId or not g or not bowler then
			return
		end
		local knocked = 0
		for n, pin in lane.pins do
			if lane.standing[n] and pinFallen(lane, pin) then
				lane.standing[n] = false
				knocked += 1
			end
		end
		local before = Shared.progress(g.rolls)
		-- derived from the rolls (not lane.rackRoll) so a lane reset racing a pinsetter cycle can
		-- never turn a strike into a "spare"
		local rackRoll = if before.fullRack then 1 else 2
		local prevIndex = #g.rolls
		local prevWasSplit = rackRoll == 2 and g.splits[prevIndex] == true
		table.insert(g.rolls, knocked)
		local idx = #g.rolls
		local prog = Shared.progress(g.rolls)
		local base = Shared.markFor(knocked, lane.standingBefore, rackRoll, lane.inGutter)
		local leave = Shared.leaveName(lane.standing)
		local kind = base
		local split = false
		if base == "STRIKE" then
			g.streak += 1
			if g.streak >= 12 then
				kind = "PERFECT"
			end
		elseif base == "SPARE" then
			kind = if prevWasSplit then "SPLITMADE" else "SPARE"
		else
			if rackRoll == 1 then
				g.streak = 0
				if knocked < 10 and Shared.isSplit(lane.standing) then
					split = true
					g.splits[idx] = true
					kind = "SPLIT"
				elseif base == "GUTTER" then
					kind = "GUTTER"
				elseif knocked == 9 then
					kind = "NINE"
				else
					kind = "PINS"
				end
			else
				kind = if base == "GUTTER" then "GUTTER" elseif knocked == 0 then "MISS" else "PINS"
			end
		end
		if lane.inGutter and knocked == 0 then
			g.gutters += 1
		end
		g.over = prog.over
		g.lastAction = os.clock()
		local callout = Shared.callout(kind, { streak = g.streak, leave = leave, knocked = knocked })
		freezePins(lane)
		parkBall(lane)
		lane.state = "Resetting"
		renderBoard(lane, callout)
		local msg = {
			type = "Result",
			lane = lane.index,
			userId = bowler.UserId,
			name = bowler.DisplayName,
			knocked = knocked,
			kind = kind,
			mark = base,
			streak = g.streak,
			leave = leave,
			split = split,
			standing = standingList(lane),
			callout = callout,
			board = boardOf(g),
			frame = prog.frame,
			roll = prog.roll,
			over = prog.over,
			members = {},
		}
		for _, p in lane.members do
			table.insert(msg.members, p.UserId)
		end
		sendNearby(lane, msg)
		fireHook("roll", bowler, { lane = lane.index, knocked = knocked, kind = kind, mark = base, streak = g.streak, split = split, frame = before.frame })
		if base == "STRIKE" then
			track(bowler, "bowl_strike", 1)
			if g.streak > 0 and g.streak % 3 == 0 then
				track(bowler, "bowl_turkey", 1)
			end
		elseif base == "SPARE" then
			track(bowler, "bowl_spare", 1)
		end
		if base == "STRIKE" or kind == "SPLITMADE" then
			liveMilestones(lane, g)
		end
		if g.over then
			finishPlayerGame(lane, g)
		end
		task.wait(0.6)
		if lane.token ~= token then
			return
		end
		local frameDone = prog.over or prog.frame ~= before.frame
		if frameDone then
			local nextIdx = nextTurnIndex(lane)
			if not nextIdx then
				gameOverLane(lane, token)
				return
			end
			lane.turn = nextIdx
			sweepCycle(lane, token, false)
			if lane.token ~= token then
				return
			end
			rackAll(lane, true, token)
			lane.rackRoll = 1
			if lane.token ~= token then
				return
			end
			beginTurn(lane, true)
			return
		end
		if prog.fullRack then
			sweepCycle(lane, token, false)
			if lane.token ~= token then
				return
			end
			rackAll(lane, true, token)
			lane.rackRoll = 1
		else
			sweepCycle(lane, token, true)
			if lane.token ~= token then
				return
			end
			lane.rackRoll = 2
		end
		if lane.token ~= token then
			return
		end
		beginTurn(lane, false)
	end)
end

local function finiteNumber(v: any, default: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end

--------------------------------------------------------------------------------------------------
-- rolling ball supervision (hook, gutter, end of roll): connected only while a ball rolls
--------------------------------------------------------------------------------------------------
local rollConn: RBXScriptConnection? = nil

local function rollStep(dt: number)
	for lane in activeRolls do
		local core = lane.ballCore
		if not core.Parent then
			finishRoll(lane)
			continue
		end
		local lf = lane.frameCF
		local rel = lf:PointToObjectSpace(core.Position)
		local dist = -rel.Z
		local lat = rel.X
		local vel = core.AssemblyLinearVelocity
		if not lane.inGutter and not lane.bumpersUp and dist > 0 and dist < lane.deckEnd and math.abs(lat) > lane.laneWidth / 2 + 0.05 then
			lane.inGutter = true
		end
		if lane.inGutter then
			if dist < lane.deckEnd - 0.3 then
				local side = lat >= 0 and 1 or -1
				local target = side * (lane.laneWidth / 2 + lane.gutterWidth / 2)
				local v = lf:VectorToObjectSpace(vel)
				local forward = math.min(v.Z, -CFG.GutterMinSpeed)
				core.AssemblyLinearVelocity = lf:VectorToWorldSpace(Vector3.new((target - lat) * 6, math.min(v.Y, 2), forward))
			end
		elseif dist > CFG.HookStart and dist < lane.laneLength - 1 and lane.spin ~= 0 then
			local ramp = math.clamp((dist - CFG.HookStart) / CFG.HookRamp, 0, 1)
			core.AssemblyLinearVelocity = vel + lf.RightVector * (lane.spin * CFG.HookAccel * lane.hookMul * ramp * dt)
		end
		-- in the pit: centre below lane level (a gutter ball sits at -0.09, a pit ball at ~-0.29)
		if dist > lane.deckEnd - 0.2 and rel.Y < -0.15 then
			lane.ballInPit = true
		end
		local elapsed = os.clock() - lane.throwTime
		if lane.ballInPit or elapsed > CFG.RollTimeout or (elapsed > 1.5 and vel.Magnitude < CFG.StopSpeed) or rel.Y < -8 or dist < -6 then
			finishRoll(lane)
		end
	end
	if next(activeRolls) == nil and rollConn then
		rollConn:Disconnect()
		rollConn = nil
	end
end

local function startRollLoop()
	if not rollConn then
		rollConn = RunService.Heartbeat:Connect(rollStep)
	end
end

local rng = Random.new()

local function handleThrow(lane: Lane, player: Player, payload: any)
	if lane.state ~= "Ready" or lane.bowler ~= player then
		return
	end
	local now = os.clock()
	if now - lane.lastThrow < CFG.ThrowCooldown then
		return
	end
	if type(payload) ~= "table" then
		return
	end
	local g = lane.games[player]
	if not g then
		return
	end
	local L = Shared.Limits
	local offset = math.clamp(finiteNumber(payload.offset, 0), -L.MaxOffset, L.MaxOffset)
	local angle = math.clamp(finiteNumber(payload.angle, 0), -L.MaxAngle, L.MaxAngle)
	local spin = math.clamp(finiteNumber(payload.spin, 0), -L.MaxSpin, L.MaxSpin)
	local power = math.clamp(finiteNumber(payload.power, 0.6), 0, 1)
	local hum, hrp = alive(player)
	if not (hum and hrp) then
		return
	end
	if (hrp.Position - lane.frameCF.Position).Magnitude > CFG.MemberDistance then
		return
	end
	-- release grade: a clean release keeps the line, a rushed / late one drifts a little
	local grade = Shared.grade(power)
	local err = Shared.gradeError(grade)
	angle = math.clamp(angle + rng:NextNumber(-err, err), -L.MaxAngle - 1, L.MaxAngle + 1)
	if grade == "PERFECT" then
		spin = math.clamp(spin * 1.06, -L.MaxSpin, L.MaxSpin) -- a clean release adds a few revs
	end
	g.offset = offset
	g.lastAction = now
	lane.lastThrow = now
	lane.lastActivity = now
	lane.rollId += 1
	lane.state = "Rolling"
	lane.inGutter = false
	lane.ballInPit = false
	lane.spin = spin
	lane.hookMul = Shared.ball(g.lb).hook
	lane.throwTime = now
	lane.standingBefore = countStanding(lane)
	-- the client walks its approach to the foul line; only snap a character that is far off
	local rel = lane.frameCF:PointToObjectSpace(hrp.Position)
	if rel.Z < -0.5 or rel.Z > Shared.StanceBack + 4 or math.abs(rel.X - (offset - Shared.HandOffset)) > 3 then
		placeCharacter(player, lane, offset - Shared.HandOffset, Shared.SlideBack + 0.4)
	end
	-- standing pins become physical (deadwood stays parked + anchored)
	for n, pin in lane.pins do
		ensurePin(lane, pin)
		if lane.standing[n] then
			pinSet(pin, pin.rest)
			pin.collider.Anchored = false
			setServerOwner(pin.collider)
		end
	end
	ensureBall(lane)
	local core = lane.ballCore
	local lf = lane.frameCF
	core.Anchored = true
	core.CustomPhysicalProperties = ballProps(g.lb)
	lane.ballModel:PivotTo(lf * CFrame.new(offset, lane.ballR + 0.04, 0.9))
	core.Anchored = false
	setServerOwner(core)
	local a = math.rad(angle)
	local dir = lf:VectorToWorldSpace(Vector3.new(math.sin(a), 0, -math.cos(a)))
	local speed = Shared.speedFor(power, g.lb)
	core.AssemblyLinearVelocity = dir * speed
	core.AssemblyAngularVelocity = Vector3.yAxis:Cross(dir) * (speed / lane.ballR) * 0.35 + dir * (spin * 12)
	activeRolls[lane] = true
	startRollLoop()
	sendNearby(lane, { type = "Thrown", lane = lane.index, ball = core, speed = speed, userId = player.UserId, lb = g.lb, grade = grade, spin = spin })
	sendState(lane)
end

--------------------------------------------------------------------------------------------------
-- membership
--------------------------------------------------------------------------------------------------
local function claimedMessage(lane: Lane): { [string]: any }
	return {
		type = "Claimed",
		lane = lane.index,
		laneFrame = lane.frameCF,
		laneModel = lane.model,
		laneLength = lane.laneLength,
		laneWidth = lane.laneWidth,
		ballDiameter = lane.ballR * 2,
	}
end

local function hookMember(lane: Lane, player: Player)
	local hum = alive(player)
	local list = {}
	if hum then
		table.insert(list, hum.Died:Connect(function()
			if laneOf[player] == lane then
				removeMember(lane, player, "died")
			end
		end))
	end
	table.insert(list, player.CharacterRemoving:Connect(function()
		if laneOf[player] == lane then
			removeMember(lane, player, "respawn")
		end
	end))
	lane.conns[player] = list
end

local function unhookMember(lane: Lane, player: Player)
	local list = lane.conns[player]
	if list then
		for _, c in list do
			c:Disconnect()
		end
	end
	lane.conns[player] = nil
end

local function stopSpectating(player: Player)
	local l = spectating[player]
	if l then
		l.spectators[player] = nil
		spectating[player] = nil
		send(player, { type = "Spectate", lane = 0 })
	end
end

-- Adds a player to a lane (fee charged by the caller). First member = owner, starts a new game.
local function addMember(lane: Lane, player: Player)
	local current = laneOf[player]
	if current and current ~= lane then
		removeMember(current, player, "switch")
	end
	stopSpectating(player)
	recordFor(player)
	table.insert(lane.members, player)
	laneOf[player] = lane
	lane.games[player] = newPGame(player, nil)
	hookMember(lane, player)
	lane.lastActivity = os.clock()
	lane.model:SetAttribute("OwnerUserId", lane.members[1].UserId)
	lane.model:SetAttribute("Players", #lane.members)
	updatePrompt(lane)
	send(player, claimedMessage(lane))
	if #lane.members == 1 then
		configureGroups() -- pick up collision groups other systems registered since startup
		lane.lastThrow = 0
		newGame(lane)
		placeCharacter(player, lane, -Shared.HandOffset, Shared.StanceBack)
	else
		renderBoard(lane, nil)
		sendState(lane)
		for _, p in lane.members do
			if p ~= player then
				notify(p, string.format("%s 님이 %d번 레인에 합류했어요! (%d/%d)", player.DisplayName, lane.index, #lane.members, Shared.MaxPlayers), "join")
			end
		end
		-- the lane was finished: a joiner restarts nobody's game; they bowl alone from frame 1
		if lane.state == "GameOver" then
			lane.turn = #lane.members
			laneTokenFlow(lane, function(token)
				freshRackThenTurn(lane, token)
			end)
		end
	end
end

function removeMember(lane: Lane, player: Player, reason: string)
	local idx = table.find(lane.members, player)
	if not idx then
		return
	end
	local wasBowler = lane.bowler == player
	local g = lane.games[player]
	if g and not g.over and #g.rolls >= 3 then
		-- an unfinished game still counts towards LastBowlingScore / the happiness hook? no: only
		-- finished games do. Save the record (best score etc.).
		saveRecord(player.UserId)
	end
	table.remove(lane.members, idx)
	lane.games[player] = nil
	unhookMember(lane, player)
	if laneOf[player] == lane then
		laneOf[player] = nil
	end
	send(player, { type = "Released", lane = lane.index, reason = reason })
	if #lane.members == 0 then
		release(lane, reason)
		return
	end
	lane.model:SetAttribute("OwnerUserId", lane.members[1].UserId)
	lane.model:SetAttribute("Players", #lane.members)
	updatePrompt(lane)
	for _, p in lane.members do
		notify(p, string.format("%s 님이 레인을 떠났어요.", player.DisplayName), "leave")
	end
	-- keep the rotation pointing at the same next player
	if idx < lane.turn then
		lane.turn -= 1
	end
	if lane.turn > #lane.members then
		lane.turn = 1
	end
	if wasBowler and lane.state ~= "GameOver" then
		activeRolls[lane] = nil
		-- the leaver's turn ends: next unfinished player gets a fresh rack
		lane.turn = math.max(lane.turn - 1, 0)
		if lane.turn == 0 then
			lane.turn = #lane.members
		end
		local nxt = nextTurnIndex(lane)
		if nxt then
			lane.turn = nxt
			laneTokenFlow(lane, function(token)
				freshRackThenTurn(lane, token)
			end)
		else
			laneTokenFlow(lane, function(token)
				gameOverLane(lane, token)
			end)
		end
	else
		renderBoard(lane, nil)
		sendState(lane)
	end
end

release = function(lane: Lane, reason: string)
	lane.token += 1
	activeRolls[lane] = nil
	for _, p in lane.members do
		unhookMember(lane, p)
		if laneOf[p] == lane then
			laneOf[p] = nil
		end
		send(p, { type = "Released", lane = lane.index, reason = reason })
	end
	for p in lane.spectators do
		if spectating[p] == lane then
			spectating[p] = nil
			send(p, { type = "Spectate", lane = 0 })
		end
	end
	lane.spectators = {}
	lane.members = {}
	lane.games = {}
	lane.bowler = nil
	lane.turn = 1
	lane.state = "Idle"
	lane.rackRoll = 1
	if lane.prepared then
		freezePins(lane)
		parkBall(lane)
		resetSweep(lane)
		rackAll(lane, false, lane.token)
		lane.ballCore.Color = Shared.ballColor(Shared.DefaultLb)
	end
	if lane.bumpersUp then
		setBumpers(lane, false)
	end
	hideBoard(lane)
	lane.model:SetAttribute("OwnerUserId", nil)
	lane.model:SetAttribute("Players", nil)
	updatePrompt(lane)
end

-- invites / join requests
type Pending = { id: number, kind: string, from: Player, to: Player, lane: Lane, expires: number }
local pendings: { [number]: Pending } = {}
local pendingSeq = 0
local friendCache: { [string]: boolean } = {}

local function isFriend(a: Player, b: Player): boolean
	local k = if a.UserId < b.UserId then (a.UserId .. ":" .. b.UserId) else (b.UserId .. ":" .. a.UserId)
	local c = friendCache[k]
	if c ~= nil then
		return c
	end
	local ok, res = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	local v = ok and res == true
	friendCache[k] = v
	return v
end

local function newPending(kind: string, from: Player, to: Player, lane: Lane): Pending
	pendingSeq += 1
	local p: Pending = { id = pendingSeq, kind = kind, from = from, to = to, lane = lane, expires = os.clock() + CFG.InviteTTL }
	-- one pending entry per (kind, from, to)
	for id, q in pendings do
		if q.kind == kind and q.from == from and q.to == to then
			pendings[id] = nil
		end
	end
	pendings[p.id] = p
	return p
end

-- Joins `player` to `lane` (fee first). Returns true when joined.
local function tryJoin(lane: Lane, player: Player): boolean
	if table.find(lane.members, player) then
		return true
	end
	if #lane.members >= Shared.MaxPlayers then
		notify(player, string.format("%d번 레인은 만석이에요 (최대 %d명).", lane.index, Shared.MaxPlayers), "warn")
		return false
	end
	if not chargeFee(player) then
		return false
	end
	if #lane.members >= Shared.MaxPlayers or table.find(lane.members, player) then
		return false
	end
	if #lane.members == 0 and not prepareLane(lane) then
		notify(player, "이 레인은 점검 중이에요. 다른 레인을 이용해 주세요.", "warn")
		return false
	end
	addMember(lane, player)
	return true
end

local function claim(lane: Lane, player: Player)
	local hum, hrp = alive(player)
	if not (hum and hrp) then
		return
	end
	local anchor = lane.prompt.Parent
	if anchor and anchor:IsA("BasePart") and (hrp.Position - anchor.Position).Magnitude > CFG.ClaimDistance then
		return
	end
	if table.find(lane.members, player) then
		lane.lastActivity = os.clock()
		send(player, claimedMessage(lane))
		sendState(lane)
		return
	end
	-- stale owners (left the game) are dropped first
	for i = #lane.members, 1, -1 do
		local p = lane.members[i]
		if p.Parent ~= Players then
			removeMember(lane, p, "left")
		end
	end
	if #lane.members == 0 then
		task.spawn(tryJoin, lane, player)
		return
	end
	if #lane.members >= Shared.MaxPlayers then
		notify(player, string.format("%d번 레인은 만석이에요. 다른 레인을 이용해 주세요.", lane.index), "warn")
		return
	end
	-- an invite to this lane, or a friend of somebody on it: join straight away
	for id, q in pendings do
		if q.kind == "invite" and q.to == player and q.lane == lane then
			pendings[id] = nil
			task.spawn(tryJoin, lane, player)
			return
		end
	end
	for _, m in lane.members do
		if isFriend(m, player) then
			task.spawn(tryJoin, lane, player)
			return
		end
	end
	local owner = lane.members[1]
	local pd = newPending("request", player, owner, lane)
	send(owner, { type = "JoinRequest", id = pd.id, from = player.UserId, fromName = player.DisplayName, lane = lane.index, ttl = CFG.InviteTTL })
	notify(player, string.format("%s 님에게 합류 요청을 보냈어요. 잠시만 기다려 주세요!", owner.DisplayName), "info")
end

local function invite(lane: Lane, from: Player, targetId: any)
	if type(targetId) ~= "number" then
		return
	end
	local target = Players:GetPlayerByUserId(targetId)
	if not target or target == from then
		return
	end
	if laneOf[target] then
		notify(from, string.format("%s 님은 이미 다른 레인에서 게임 중이에요.", target.DisplayName), "warn")
		return
	end
	if #lane.members >= Shared.MaxPlayers then
		notify(from, "레인이 꽉 찼어요 (최대 4명).", "warn")
		return
	end
	local _, hrp = alive(target)
	if not hrp or (hrp.Position - lane.frameCF.Position).Magnitude > CFG.NearbyDistance then
		notify(from, string.format("%s 님이 볼링장 안에 있어야 초대할 수 있어요.", target.DisplayName), "warn")
		return
	end
	local pd = newPending("invite", from, target, lane)
	send(target, { type = "Invite", id = pd.id, from = from.UserId, fromName = from.DisplayName, lane = lane.index, ttl = CFG.InviteTTL, count = #lane.members })
	notify(from, string.format("%s 님을 초대했어요!", target.DisplayName), "info")
end

local function answer(player: Player, payload: any)
	if type(payload) ~= "table" or type(payload.id) ~= "number" then
		return
	end
	local pd = pendings[payload.id]
	if not pd or pd.to ~= player or os.clock() > pd.expires then
		pendings[payload.id or 0] = nil
		return
	end
	pendings[pd.id] = nil
	local accept = payload.accept == true
	if pd.kind == "invite" then
		if accept then
			if pd.lane.state == "Idle" or #pd.lane.members == 0 then
				notify(player, "그 레인의 게임이 이미 끝났어요.", "warn")
				return
			end
			if tryJoin(pd.lane, player) then
				return
			end
		else
			notify(pd.from, string.format("%s 님이 초대를 거절했어요.", player.DisplayName), "info")
		end
	elseif pd.kind == "request" then
		if laneOf[player] ~= pd.lane then
			return
		end
		if accept then
			local _, hrp = alive(pd.from)
			if pd.from.Parent == Players and hrp then
				tryJoin(pd.lane, pd.from)
			end
		else
			notify(pd.from, string.format("%s 님이 합류 요청을 거절했어요.", player.DisplayName), "info")
		end
	end
end

--------------------------------------------------------------------------------------------------
-- lane setup (boot: references only; physics preparation happens on the first claim)
--------------------------------------------------------------------------------------------------
local function findMonitorGui(model: Instance, index: number): SurfaceGui?
	local name = string.format("LaneMonitor_%02d", index)
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceGui") and d.Name == name then
			return d
		end
	end
	return nil
end

local function setupRacks(h: Instance)
	for _, d in h:GetDescendants() do
		if d.Name == "BallRackPrompt" and d:IsA("BasePart") and not d:FindFirstChildOfClass("ProximityPrompt") then
			local p = Instance.new("ProximityPrompt")
			p.Name = "BallRackPrompt"
			p.ActionText = "공 고르기"
			p.ObjectText = "하우스볼 8~16 lb"
			p.HoldDuration = 0
			p.MaxActivationDistance = 8
			p.RequiresLineOfSight = false
			p.KeyboardKeyCode = Enum.KeyCode.F
			p.GamepadKeyCode = Enum.KeyCode.ButtonY
			p.ClickablePrompt = true
			p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
			p.Parent = d
			p.Triggered:Connect(function(player: Player)
				local _, hrp = alive(player)
				if hrp and (hrp.Position - d.Position).Magnitude <= 14 then
					local lane = laneOf[player]
					local g = lane and lane.games[player]
					send(player, { type = "Picker", lb = (g and g.lb) or chosenLb[player] or Shared.DefaultLb })
				end
			end)
		end
	end
	local lb = h:FindFirstChild("HallLeaderboard", true)
	if lb and lb:IsA("BasePart") then
		local g = lb:FindFirstChildOfClass("SurfaceGui")
		if g then
			leaderboardGui = g
			renderLeaderboard()
		end
	end
end

local function setupLane(model: Instance)
	if not model:IsA("Model") or laneByModel[model] then
		return
	end
	local index = model:GetAttribute("LaneIndex")
	local laneFrame = model:FindFirstChild("LaneFrame")
	local pinsFolder = model:FindFirstChild("Pins")
	local ballModel = model:FindFirstChild("Ball")
	local anchor = model:FindFirstChild("PromptAnchor")
	if type(index) ~= "number" or not (laneFrame and laneFrame:IsA("BasePart")) or not pinsFolder or not (ballModel and ballModel:IsA("Model")) or not (anchor and anchor:IsA("BasePart")) then
		warn("[Bowling] incomplete lane model", model:GetFullName())
		return
	end
	if lanes[index] then
		warn("[Bowling] duplicate lane index", index)
		return
	end
	local pins: { Pin } = {}
	for n = 1, 10 do
		local pm = pinsFolder:FindFirstChild("Pin_" .. n)
		local collider = pm and pm:IsA("Model") and (pm.PrimaryPart or pm:FindFirstChild("Collider"))
		if not (pm and pm:IsA("Model") and collider and collider:IsA("BasePart")) then
			warn("[Bowling] lane", index, "missing Pin_" .. n)
			return
		end
		local spot = collider.CFrame
		pins[n] = {
			n = n,
			model = pm,
			collider = collider,
			spot = spot,
			rest = spot,
			upLocal = spot:VectorToObjectSpace(Vector3.yAxis),
			template = nil,
		}
	end
	local core = ballModel.PrimaryPart or ballModel:FindFirstChild("BallCore")
	if not (core and core:IsA("BasePart")) then
		warn("[Bowling] lane", index, "ball without BallCore")
		return
	end
	local rest = model:FindFirstChild("BallRest")
	local restCF = (rest and rest:IsA("BasePart")) and rest.CFrame or core.CFrame
	local sweep = model:FindFirstChild("Sweep")
	local sweepPart = (sweep and sweep:IsA("BasePart")) and sweep or nil
	local bumpers, bumperDown = {}, {}
	local upOffset = 0
	for _, name in { "BumperL", "BumperR" } do
		local b = model:FindFirstChild(name)
		if b and b:IsA("BasePart") then
			table.insert(bumpers, b)
			table.insert(bumperDown, b.CFrame)
			upOffset = numAttr(b, "UpOffset", 0.97)
		end
	end
	-- prompt
	-- Touch: the default-style prompt is a tappable button (ClickablePrompt). Lanes sit ~5.7 studs
	-- apart, so several are in range at once: OnePerButton shows only the nearest one, which keeps a
	-- single big tap target on a phone screen instead of a row of overlapping prompts.
	local prompt = anchor:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.Name = "BowlingPrompt"
	prompt.ActionText = Shared.PromptText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.ClickablePrompt = true
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = anchor

	local lane: Lane = {
		index = index,
		model = model,
		frameCF = laneFrame.CFrame,
		laneLength = numAttr(laneFrame, "LaneLength", 60.96),
		laneWidth = numAttr(laneFrame, "LaneWidth", 3.5),
		gutterWidth = numAttr(laneFrame, "GutterWidth", 0.8),
		ballR = numAttr(laneFrame, "BallDiameter", 0.72) / 2,
		deckEnd = numAttr(laneFrame, "DeckEnd", 64.06),
		pitDepth = numAttr(laneFrame, "PitDepth", 0.65),
		pinsFolder = pinsFolder,
		pins = pins,
		standing = { true, true, true, true, true, true, true, true, true, true },
		ballModel = ballModel,
		ballCore = core,
		ballTemplate = nil,
		restCF = restCF,
		sweep = sweepPart,
		sweepCF = sweepPart and sweepPart.CFrame or nil,
		sweepTween = nil,
		bumpers = bumpers,
		bumperDown = bumperDown,
		bumperUpOffset = upOffset,
		bumpersUp = false,
		gui = findMonitorGui(model, index),
		prompt = prompt,
		prepared = false,
		members = {},
		games = {},
		turn = 1,
		bowler = nil,
		spectators = {},
		conns = {},
		state = "Idle",
		rackRoll = 1,
		standingBefore = 10,
		token = 0,
		rollId = 0,
		lastThrow = 0,
		lastActivity = 0,
		throwTime = 0,
		spin = 0,
		hookMul = 1,
		inGutter = false,
		ballInPit = false,
		flashId = 0,
		monCache = {},
		gameNo = 0,
	}
	lanes[index] = lane
	laneByModel[model] = lane
	updatePrompt(lane)
	prompt.Triggered:Connect(function(player: Player)
		claim(lane, player)
	end)
	if model.Parent and model.Parent ~= hall then
		hall = model.Parent
		setupRacks(model.Parent)
	end
end

for _, m in CollectionService:GetTagged(LANE_TAG) do
	task.spawn(setupLane, m)
end
CollectionService:GetInstanceAddedSignal(LANE_TAG):Connect(function(m)
	task.spawn(setupLane, m)
end)

--------------------------------------------------------------------------------------------------
-- requests from clients
--------------------------------------------------------------------------------------------------
local buckets: { [Player]: { tokens: number, t: number } } = {}
local function allow(player: Player): boolean
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = { tokens = CFG.RequestsPerSecond, t = now }
		buckets[player] = b
	end
	b.tokens = math.min(CFG.RequestsPerSecond, b.tokens + (now - b.t) * CFG.RequestsPerSecond)
	b.t = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function leaderboardMessage(): { [string]: any }
	local rows = {}
	for i, h in highScores do
		rows[i] = { rank = i, name = h.name, userId = h.userId, score = h.score, lane = h.lane, strikes = h.strikes }
	end
	return { type = "Leaderboard", rows = rows }
end

requestRemote.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
	if type(action) ~= "string" or not allow(player) then
		return
	end
	-- actions that work without a lane
	if action == "PickBall" then
		local lb = type(payload) == "table" and payload.lb or nil
		if Shared.validLb(lb) then
			chosenLb[player] = lb
			local lane = laneOf[player]
			local g = lane and lane.games[player]
			if lane and g then
				g.lb = lb
				if lane.bowler == player and lane.state == "Ready" then
					lane.ballCore.Color = Shared.ballColor(lb)
					lane.ballCore.CustomPhysicalProperties = ballProps(lb)
					sendNearby(lane, { type = "Turn", lane = lane.index, userId = player.UserId, name = player.DisplayName, lb = lb, fresh = false })
				end
				sendState(lane)
			end
			send(player, { type = "Ball", lb = lb })
		end
		return
	elseif action == "Leaderboard" then
		send(player, leaderboardMessage())
		return
	elseif action == "Answer" then
		answer(player, payload)
		return
	end
	local lane = laneOf[player]
	if not lane or not table.find(lane.members, player) then
		if action ~= "Ping" and action ~= "Approach" then
			send(player, { type = "Released", lane = 0, reason = "notowner" })
		end
		return
	end
	local g = lane.games[player]
	if g then
		g.lastAction = os.clock()
	end
	if action == "Throw" then
		handleThrow(lane, player, payload)
	elseif action == "Approach" then
		if lane.bowler == player and lane.state == "Ready" then
			lane.lastActivity = os.clock()
			sendNearby(lane, { type = "Swing", lane = lane.index, userId = player.UserId, phase = "approach", lb = g and g.lb or Shared.DefaultLb }, player)
		end
	elseif action == "Leave" then
		removeMember(lane, player, "leave")
	elseif action == "NewGame" then
		if player ~= lane.members[1] then
			notify(player, "새 게임은 레인 주인만 시작할 수 있어요.", "info")
		elseif lane.state == "GameOver" or lane.state == "Ready" then
			lane.lastActivity = os.clock()
			task.spawn(function()
				-- every member pays for the new game (when the life-game API exists)
				for _, p in table.clone(lane.members) do
					if p ~= player and not chargeFee(p) then
						removeMember(lane, p, "fee")
					end
				end
				if not chargeFee(player) then
					return
				end
				if laneOf[player] == lane then
					newGame(lane)
				end
			end)
		end
	elseif action == "Bumpers" then
		if g and type(payload) == "table" then
			g.bumpers = payload.on == true
			if lane.bowler == player and lane.state == "Ready" then
				setBumpers(lane, g.bumpers)
			end
			renderBoard(lane, nil)
			sendState(lane)
		end
	elseif action == "Invite" then
		if type(payload) == "table" then
			invite(lane, player, payload.userId)
		end
	elseif action == "Ping" then
		lane.lastActivity = os.clock()
	elseif action == "Sync" then
		send(player, claimedMessage(lane))
		sendState(lane)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local lane = laneOf[player]
	if lane then
		removeMember(lane, player, "left")
	end
	laneOf[player] = nil
	stopSpectating(player)
	buckets[player] = nil
	chosenLb[player] = nil
	for id, q in pendings do
		if q.from == player or q.to == player then
			pendings[id] = nil
		end
	end
	saveRecord(player.UserId)
	task.delay(CFG.SaveInterval + 2, function()
		if not Players:GetPlayerByUserId(player.UserId) then
			records[player.UserId] = nil
		end
	end)
end)

pcall(function()
	game:BindToClose(function()
		for uid, r in records do
			if r.dirty then
				r.lastSave = 0
				saveRecord(uid)
			end
		end
		task.wait(2)
	end)
end)

--------------------------------------------------------------------------------------------------
-- watchdog: idle / distance, spectators, expired invites (every 2 s, only while lanes are in use)
--------------------------------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(2)
		local now = os.clock()
		local anyActive = false
		for _, lane in lanes do
			if #lane.members > 0 then
				anyActive = true
				for i = #lane.members, 1, -1 do
					local p = lane.members[i]
					local _, hrp = alive(p)
					local g = lane.games[p]
					if p.Parent ~= Players then
						removeMember(lane, p, "left")
					elseif not hrp then
						removeMember(lane, p, "nocharacter")
					elseif (hrp.Position - lane.frameCF.Position).Magnitude > CFG.MemberDistance then
						removeMember(lane, p, "far")
					elseif g and lane.bowler == p and lane.state == "Ready" and now - g.lastAction > CFG.BowlerIdle then
						removeMember(lane, p, "idle")
					end
				end
				if #lane.members > 0 and lane.state ~= "Rolling" and lane.state ~= "Settling" and now - lane.lastActivity > Shared.IdleTimeout then
					local list = table.clone(lane.members)
					for _, p in list do
						removeMember(lane, p, "idle")
					end
				end
			end
		end
		for id, q in pendings do
			if now > q.expires then
				pendings[id] = nil
			end
		end
		-- spectators: players (not on a lane) standing behind an active lane's approach
		if anyActive or next(spectating) then
			for _, p in Players:GetPlayers() do
				if not laneOf[p] then
					local _, hrp = alive(p)
					local best: Lane? = nil
					local bestD = CFG.SpectateDistance
					if hrp then
						for _, lane in lanes do
							if #lane.members > 0 then
								local spot = (lane.frameCF * CFrame.new(0, 0, Shared.StanceBack + 8)).Position
								local d = (hrp.Position - spot).Magnitude
								if d < bestD then
									best, bestD = lane, d
								end
							end
						end
					end
					local cur = spectating[p]
					if cur ~= best then
						if cur then
							cur.spectators[p] = nil
							spectating[p] = nil
						end
						if best then
							best.spectators[p] = true
							spectating[p] = best
							send(p, { type = "Spectate", lane = best.index, laneFrame = best.frameCF, laneLength = best.laneLength, laneWidth = best.laneWidth })
							local sm = stateMessage(best)
							sm.spectating = true
							send(p, sm)
						else
							send(p, { type = "Spectate", lane = 0 })
						end
					end
				end
			end
		end
	end
end)
