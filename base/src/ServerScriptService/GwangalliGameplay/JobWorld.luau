--!nocheck
-- GwangalliGameplay/JobWorld: the 알바 happening IN THE WORLD (docs/JOBS.md "월드 알바").
-- Required and driven by Jobs.luau (not a FEATURE_MODULE): Jobs.init -> JobWorld.init(ctx, Jobs, JS),
-- Jobs' 0.5 s tick -> JobWorld.tick(). No loop of its own.
--   * STATIONS: build-time anchors tagged GwJobStation (attrs Job, Station, Place, ...) from the store /
--     cafe / delivery builders. Work points snap to them; customer paths and prop rows read them.
--   * CUSTOMERS: pooled NPC rigs (GwangalliNPCLooks, max 3 per store, built once, parked in
--     ServerStorage when idle) that walk in, browse a shelf, queue at the counter with an order
--     bubble, get served by the worker's round and leave. They live in workspace.GwangalliNPCs with
--     the NPC.luau attribute contract (NpcId / NpcLeg polyline / NpcYaw / NpcAct / NpcEmote, NpcKind =
--     "shop") so GwangalliNPCClient animates them; the server writes attributes only on transitions.
--     Bubbles: model attributes ShopSay (text) + ShopSaySeq (number) -> GwangalliJobs client shows them
--     with the shared bubble pool to everyone nearby.
--   * BOSS: the store's employer NPC (G.NPCS[job.npc], placed by NPC.luau behind the counter) greets
--     the worker at clock-in, briefs, reacts to results (bubble via the JobGame remote {op = "say"} to
--     players within 60 studs + an NPC.react emote everyone sees).
--   * CARRIED PROPS: the restock box (both hands) and the quick-delivery parcel, welded to the
--     character so other players see them.
-- Official APIs only; StreamingEnabled-safe (server sees every anchor; clients get CFrames in payloads).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JobWorld = {}

local ctx: any
local G: any
local JS: any
local Jobs: any
local Util: any

local Looks: any = nil
local NPCmod: any = nil
local npcTried = false

local stations: { [string]: { [string]: BasePart } } = {} -- [job][station] = anchor
local SAY_RANGE = 60
local WALK = 5.4 -- studs / s
local MAX_CUSTOMERS = 3
local PATIENCE = 80 -- s a customer waits at the counter before leaving

-------------------------------------------------------------------------------------------------
-- Stations
-------------------------------------------------------------------------------------------------
local function addStation(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local job, id = inst:GetAttribute("Job"), inst:GetAttribute("Station")
	if type(job) ~= "string" or type(id) ~= "string" then
		return
	end
	stations[job] = stations[job] or {}
	stations[job][id] = inst
end

function JobWorld.station(jobId: string, id: string): BasePart?
	local list = stations[jobId]
	local p = list and list[id]
	if p and p.Parent then
		return p
	end
	-- delivery jobs share one office
	if jobId == "delivery_quick" or jobId == "delivery_parcel" or jobId == "rider" then
		list = stations.delivery
		p = list and list[id]
		if p and p.Parent then
			return p
		end
	end
	return nil
end

function JobWorld.stations(jobId: string): { [string]: BasePart }
	return stations[jobId] or {}
end

-- feet position + facing of a station (anchors are 1-stud cubes centred 0.5 above the floor)
function JobWorld.feet(part: BasePart): Vector3
	return part.Position - Vector3.new(0, 0.5, 0)
end

local function yawOf(v: Vector3): number
	return math.deg(math.atan2(-v.X, -v.Z))
end

-- CFrame list for a client payload (only the ids asked for)
function JobWorld.frames(jobId: string, ids: { string }): { [string]: CFrame }
	local out = {}
	for _, id in ids do
		local p = JobWorld.station(jobId, id)
		if p then
			out[id] = p.CFrame
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Optional modules
-------------------------------------------------------------------------------------------------
local function npc(): any
	if npcTried then
		return NPCmod
	end
	npcTried = true
	local m = script.Parent and script.Parent:FindFirstChild("NPC")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			NPCmod = res
		end
	end
	return NPCmod
end

local function looks(): any
	if Looks then
		return Looks
	end
	local m = ReplicatedStorage:FindFirstChild("GwangalliNPCLooks")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" and type(res.build) == "function" then
			Looks = res
		end
	end
	return Looks
end

-------------------------------------------------------------------------------------------------
-- Speech: boss (remote to nearby players) and customers (model attributes)
-------------------------------------------------------------------------------------------------
local sayRemote: RemoteEvent? = nil

local function playersNear(pos: Vector3, r: number): { Player }
	local out = {}
	for _, p in Players:GetPlayers() do
		local rp = Util.rootPosition(p)
		if rp and (rp - pos).Magnitude <= r then
			table.insert(out, p)
		end
	end
	return out
end

-- npcId: a G.NPCS id (boss); the text is shown over its head for the worker and players nearby
function JobWorld.bossSay(player: Player, jobId: string, text: string, emote: string?, dur: number?)
	if type(text) ~= "string" or text == "" then
		return
	end
	local job = G.JOBS[jobId]
	local npcId = job and job.npc
	local N = npc()
	local st = nil
	if N and npcId and type(N.state) == "function" then
		local ok, res = pcall(N.state, npcId)
		if ok then
			st = res
		end
	end
	local who = { player }
	if st and st.pos and not st.hidden then
		for _, p in playersNear(st.pos, SAY_RANGE) do
			if p ~= player then
				table.insert(who, p)
			end
		end
		if emote and type(N.react) == "function" then
			pcall(N.react, npcId, emote)
		end
		if type(N.engage) == "function" then
			pcall(N.engage, npcId, player, 6)
		end
	end
	local boss = JS.BOSS[if jobId == "delivery_quick" or jobId == "delivery_parcel" then "delivery" else jobId]
	local payload = { op = "say", who = "boss", npc = npcId, name = boss and boss.name or "사장님", text = text, dur = dur or 4, offline = st == nil or st.hidden == true, jobId = jobId }
	if sayRemote then
		for _, p in who do
			if p.Parent == Players then
				sayRemote:FireClient(p, payload)
			end
		end
	end
end

function JobWorld.bossLine(player: Player, jobId: string, key: string, emote: string?)
	local boss = JS.BOSS[if jobId == "delivery_quick" or jobId == "delivery_parcel" then "delivery" else jobId]
	if not boss then
		return
	end
	local v = boss[key]
	if type(v) == "table" then
		v = v[math.random(1, #v)]
	end
	if type(v) == "string" and v ~= "" then
		JobWorld.bossSay(player, jobId, v, emote)
	end
end

local function modelSay(model: Model, text: string)
	model:SetAttribute("ShopSay", text)
	model:SetAttribute("ShopSaySeq", (model:GetAttribute("ShopSaySeq") or 0) + 1)
end
JobWorld.modelSay = modelSay

local emoteSeq = 0
local function modelEmote(model: Model, name: string)
	emoteSeq += 1
	model:SetAttribute("NpcEmote", string.format("%s#%d#%.1f", name, emoteSeq, workspace:GetServerTimeNow()))
end

-------------------------------------------------------------------------------------------------
-- Customer rigs (pooled)
-------------------------------------------------------------------------------------------------
type Cust = {
	id: string,
	store: string,
	model: Model,
	root: BasePart,
	ground: number,
	state: string, -- walk | browse | queue | serving | leave
	nextState: string?,
	arriveAt: number,
	waitUntil: number,
	pos: Vector3, -- feet
	yaw: number,
	slot: number?,
	slotSince: number,
	browse: BasePart?,
	role: string?,
	served: boolean,
	worker: Player?,
	said: boolean,
}

local stores: { [string]: { customers: { Cust }, pool: { any }, nextSpawn: number, serial: number } } = {}
local parkFolder: Folder? = nil
local custSerial = 0

local function npcFolder(): Folder
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if not f or not f:IsA("Folder") then
		f = Instance.new("Folder")
		f.Name = "GwangalliNPCs"
		f.Parent = workspace
	end
	return f :: Folder
end

local function park(): Folder
	if parkFolder and parkFolder.Parent then
		return parkFolder
	end
	local f = ServerStorage:FindFirstChild("GwangalliShopNPCPool")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwangalliShopNPCPool"
		f.Parent = ServerStorage
	end
	parkFolder = f :: Folder
	return parkFolder :: Folder
end

local function storeOf(jobId: string): any
	local st = stores[jobId]
	if not st then
		st = { customers = {}, pool = {}, nextSpawn = 0, serial = 0 }
		stores[jobId] = st
	end
	return st
end

local function placeAt(c: Cust, feet: Vector3, yaw: number)
	c.pos = feet
	c.yaw = yaw
	c.root.CFrame = CFrame.new(feet + Vector3.new(0, c.ground, 0)) * CFrame.Angles(0, math.rad(yaw), 0)
	c.model:SetAttribute("NpcYaw", math.floor(yaw * 10 + 0.5) / 10)
end

local function setAct(c: Cust, act: string)
	if c.model:GetAttribute("NpcAct") ~= act then
		c.model:SetAttribute("NpcAct", act)
	end
end

-- walks a polyline of feet points; next = state after arrival
local function walk(c: Cust, pts: { Vector3 }, nextState: string, endYaw: number?)
	local clean = { c.pos }
	for _, p in pts do
		if (p - clean[#clean]).Magnitude > 0.3 then
			table.insert(clean, p)
		end
	end
	if #clean < 2 then
		c.state = nextState
		c.arriveAt = os.clock()
		if endYaw then
			placeAt(c, c.pos, endYaw)
		end
		return
	end
	local len = 0
	for i = 2, #clean do
		len += (clean[i] - clean[i - 1]).Magnitude
	end
	local buf = { "P", string.format("%.2f", workspace:GetServerTimeNow()), string.format("%.3f", WALK) }
	for _, p in clean do
		table.insert(buf, string.format("%.1f,%.2f,%.1f", p.X, p.Y, p.Z))
	end
	setAct(c, "walk")
	c.model:SetAttribute("NpcLeg", table.concat(buf, ";"))
	c.state = "walk"
	c.nextState = nextState
	c.arriveAt = os.clock() + len / WALK + 0.1
	local last = clean[#clean]
	local dir = last - clean[#clean - 1]
	c.pos = last
	c.yaw = endYaw or (if dir.Magnitude > 0.1 then yawOf(dir) else c.yaw)
end

local function arrive(c: Cust)
	c.model:SetAttribute("NpcLeg", "")
	placeAt(c, c.pos, c.yaw)
end

local function feetOf(jobId: string, id: string): Vector3?
	local p = JobWorld.station(jobId, id)
	return p and JobWorld.feet(p) or nil
end

local function pathPoints(jobId: string, ids: { string }): { Vector3 }
	local out = {}
	for _, id in ids do
		local f = feetOf(jobId, id)
		if f then
			table.insert(out, f)
		end
	end
	return out
end

local function splitPath(s: any): { string }
	local out = {}
	if type(s) == "string" then
		for id in string.gmatch(s, "[^,]+") do
			table.insert(out, id)
		end
	end
	return out
end

local function newRig(jobId: string): any
	local L = looks()
	if not L then
		return nil
	end
	custSerial += 1
	local seed = custSerial * 7919 + math.random(1, 100000)
	local okS, spec = pcall(L.random, seed, {})
	if not okS then
		return nil
	end
	local okB, rig = pcall(L.build, spec, { name = "Customer", anchored = true, humanoid = false })
	if not okB or type(rig) ~= "table" or not rig.model then
		return nil
	end
	local model: Model = rig.model
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("NpcKind", "shop")
	model:SetAttribute("ShopCustomer", true)
	model:SetAttribute("ShopStore", jobId)
	model:SetAttribute("NpcGround", rig.ground or 3)
	model:SetAttribute("NpcAct", "idle")
	model:SetAttribute("NpcYaw", 0)
	model:SetAttribute("NpcLook", 0)
	model:SetAttribute("NpcTalk", 0)
	model:SetAttribute("NpcLeg", "")
	model:SetAttribute("NpcEmote", "")
	return rig
end

local function despawn(st: any, c: Cust)
	local i = table.find(st.customers, c)
	if i then
		table.remove(st.customers, i)
	end
	c.model.Parent = park()
	table.insert(st.pool, { model = c.model, root = c.root, ground = c.ground })
end

local function spawnCustomer(jobId: string, quick: boolean?): Cust?
	local st = storeOf(jobId)
	local door = feetOf(jobId, "door_out")
	local inside = feetOf(jobId, "door_in")
	if not door or not inside then
		return nil
	end
	local rec = table.remove(st.pool)
	if not rec then
		local rig = newRig(jobId)
		if not rig then
			return nil
		end
		rec = { model = rig.model, root = rig.root, ground = rig.ground or 3 }
		-- re-dress pooled rigs now and then (outside the Workspace, as Looks.restyle wants)
	elseif Looks and type(Looks.restyle) == "function" and math.random() < 0.6 then
		custSerial += 1
		pcall(function()
			Looks.restyle({ model = rec.model }, Looks.random(custSerial * 104729 + math.random(1, 9999), {}), "Customer")
		end)
	end
	st.serial += 1
	local c: Cust = {
		id = string.format("shop_%s_%d", jobId, st.serial),
		store = jobId,
		model = rec.model,
		root = rec.root,
		ground = rec.ground,
		state = "walk",
		nextState = nil,
		arriveAt = 0,
		waitUntil = 0,
		pos = door,
		yaw = 0,
		slot = nil,
		slotSince = 0,
		browse = nil,
		role = nil,
		served = false,
		worker = nil,
		said = false,
	}
	c.model:SetAttribute("NpcId", c.id)
	c.model:SetAttribute("ShopSay", "")
	c.model:SetAttribute("ShopRole", "")
	c.model.Name = "ShopCustomer_" .. c.id
	placeAt(c, door, yawOf(inside - door))
	c.model.Parent = npcFolder()
	table.insert(st.customers, c)
	-- walk in: straight to the queue (quick) or via a browse spot
	local browseList = {}
	for id, p in JobWorld.stations(jobId) do
		if string.sub(id, 1, 6) == "browse" then
			table.insert(browseList, p)
		end
	end
	if quick or #browseList == 0 then
		local pts = pathPoints(jobId, { "door_in", "front" })
		walk(c, pts, "toqueue")
	else
		local b = browseList[math.random(1, #browseList)]
		c.browse = b
		local ids = { "door_in" }
		for _, id in splitPath(b:GetAttribute("Path")) do
			table.insert(ids, id)
		end
		local pts = pathPoints(jobId, ids)
		table.insert(pts, JobWorld.feet(b))
		walk(c, pts, "browse", yawOf(b.CFrame.LookVector))
	end
	pcall(function()
		-- the door chime: clients near the store ring it on this attribute
		local d = JobWorld.station(jobId, "door_in")
		if d then
			d:SetAttribute("ChimeSeq", (d:GetAttribute("ChimeSeq") or 0) + 1)
		end
	end)
	return c
end

local function queueSlots(jobId: string): { Vector3 }
	local out = {}
	for i = 1, 3 do
		local f = feetOf(jobId, "queue" .. i)
		if f then
			table.insert(out, f)
		end
	end
	return out
end

local function queueYaw(jobId: string): number
	local q = JobWorld.station(jobId, "queue1")
	return if q then yawOf(q.CFrame.LookVector) else 0
end

local function takenSlots(st: any): { [number]: Cust }
	local out = {}
	for _, c in st.customers do
		if c.slot then
			out[c.slot] = c
		end
	end
	return out
end

local function toQueue(c: Cust)
	local st = storeOf(c.store)
	local slots = queueSlots(c.store)
	local taken = takenSlots(st)
	local free = nil
	for i = 1, #slots do
		if not taken[i] then
			free = i
			break
		end
	end
	if not free then
		-- queue full: browse a bit longer near the front
		c.state = "browse"
		c.waitUntil = os.clock() + 4
		setAct(c, "shop")
		return
	end
	c.slot = free
	c.slotSince = os.clock()
	local pts = { slots[free] }
	-- coming from the aisles: pass the front node first
	local front = feetOf(c.store, "front")
	if front and (c.pos - front).Magnitude > 4 then
		table.insert(pts, 1, front)
	end
	walk(c, pts, "queue", queueYaw(c.store))
end

local function leave(c: Cust, text: string?)
	local st = storeOf(c.store)
	c.slot = nil
	c.state = "walk"
	if text then
		modelSay(c.model, text)
	end
	local pts = pathPoints(c.store, { "front", "door_in", "door_out" })
	walk(c, pts, "gone")
	local _ = st
end

-- the queue moves up when slot 1 frees
local function advanceQueue(jobId: string)
	local st = storeOf(jobId)
	local slots = queueSlots(jobId)
	local taken = takenSlots(st)
	for i = 2, #slots do
		local c = taken[i]
		if c and not taken[i - 1] and (c.state == "queue" or c.state == "walk") then
			c.slot = i - 1
			taken[i - 1], taken[i] = c, nil
			c.said = false
			if i - 1 == 1 then
				c.slotSince = os.clock()
			end
			walk(c, { slots[i - 1] }, "queue", queueYaw(jobId))
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Worker side
-------------------------------------------------------------------------------------------------
local function workersAt(jobId: string): { Player }
	local out = {}
	for player, s in Jobs.shifts do
		if s.jobId == jobId and s.index >= 1 and player.Parent == Players then
			table.insert(out, player)
		end
	end
	return out
end

-- the customer waiting at the counter (slot 1, arrived), if any
function JobWorld.counterCustomer(jobId: string): Cust?
	local st = stores[jobId]
	if not st then
		return nil
	end
	for _, c in st.customers do
		if c.slot == 1 and (c.state == "queue" or c.state == "serving") and os.clock() >= c.arriveAt then
			return c
		end
	end
	return nil
end

function JobWorld.customerReady(player: Player, s: any): boolean
	local c = JobWorld.counterCustomer(s.jobId)
	return c ~= nil and (c.state == "queue" or (c.state == "serving" and c.worker == player))
end

-- a customer task became current: make sure someone is (or will be) coming
function JobWorld.taskStarted(player: Player, s: any, t: any)
	if not t or t.world ~= "customer" then
		return
	end
	local st = storeOf(s.jobId)
	if #st.customers == 0 then
		spawnCustomer(s.jobId, true)
		st.nextSpawn = os.clock() + 6
	end
	local _ = player
end

-- extra generator input + payload fields for a round (customer / prop rows)
function JobWorld.roundInfo(player: Player, s: any, t: any, info: any): any
	local extra: any = { world = t.world, stations = {} }
	if t.world == "customer" then
		local c = JobWorld.counterCustomer(s.jobId)
		if c then
			c.state = "serving"
			c.worker = player
			c.role = t.customer or t.game
			c.model:SetAttribute("ShopRole", c.role)
			extra.customer = c.model
			setAct(c, if t.game == "sale" then "shop" else "talk")
			if t.game == "ask" and type(t.question) == "string" then
				local q = string.gsub(t.question, "^손님:%s*", "")
				modelSay(c.model, q)
			elseif t.game == "parcel" then
				modelSay(c.model, JS.CUSTOMER_LINES.parcel[math.random(1, #JS.CUSTOMER_LINES.parcel)])
			end
		end
		extra.stations = JobWorld.frames(s.jobId, { "counter_items", "counter_scanned", "counter", "bar", "bar_cup", "pos" })
		if t.game == "ask" then
			info.question, info.choices, info.answer = t.question, t.choices, t.answer
		end
	elseif t.world == "restock" then
		extra.stations = JobWorld.frames(s.jobId, { "slot_food", "slot_snack", "slot_drink", "slot_life", "backroom" })
		JobWorld.attachCarry(player, s, "box")
	elseif t.world == "expiry" then
		extra.stations = JobWorld.frames(s.jobId, { "chiller_items", "chiller" })
	elseif t.world == "cup" then
		extra.stations = JobWorld.frames(s.jobId, { "bar_cup", "bar" })
	end
	return extra
end

function JobWorld.roundResolved(player: Player, s: any, t: any, ok: boolean, score: number, view: any)
	if not t then
		return
	end
	if t.world == "restock" then
		JobWorld.removeCarry(s)
	end
	if t.world == "customer" then
		local c = JobWorld.counterCustomer(s.jobId)
		if c and c.worker == player then
			c.served = true
			local lines = JS.CUSTOMER_LINES
			if ok then
				modelEmote(c.model, if math.random() < 0.5 then "bow" else "wave")
				leave(c, lines.thanks[math.random(1, #lines.thanks)])
			else
				modelEmote(c.model, "shrug")
				leave(c, if t.game == "ask" then "음… 알겠어요" else "어… 계산이 이상한데…")
			end
			advanceQueue(s.jobId)
		end
	end
	-- the boss reacts now and then (always on a miss or a perfect round)
	if not ok then
		JobWorld.bossLine(player, s.jobId, "bad", "shrug")
	elseif score >= 0.999 and math.random() < 0.6 then
		JobWorld.bossLine(player, s.jobId, "good", "thumbs")
	end
	local _ = view
end

function JobWorld.clockIn(player: Player, s: any)
	local jobId = s.jobId
	JobWorld.bossLine(player, jobId, "greet", "wave")
	task.delay(3.6, function()
		if Jobs.shifts[player] == s then
			JobWorld.bossLine(player, jobId, "brief", "point")
		end
	end)
	-- first customer on the way right away
	if storeOf(jobId) and JobWorld.station(jobId, "door_out") then
		local st = storeOf(jobId)
		if #st.customers == 0 then
			spawnCustomer(jobId, true)
			st.nextSpawn = os.clock() + 8
		end
	end
end

function JobWorld.shiftEnded(player: Player, s: any, completed: boolean)
	JobWorld.removeCarry(s)
	if completed then
		JobWorld.bossLine(player, s.jobId, "bye", "wave")
	end
	-- release a customer this worker was serving
	local st = stores[s.jobId]
	if st then
		for _, c in st.customers do
			if c.worker == player and c.state == "serving" then
				c.state = "queue"
				c.worker = nil
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Carried props (restock box / parcel), welded to the character
-------------------------------------------------------------------------------------------------
function JobWorld.removeCarry(s: any)
	if s.carry then
		if s.carry.Parent then
			s.carry:Destroy()
		end
		s.carry = nil
	end
end

function JobWorld.attachCarry(player: Player, s: any, kind: string, label: string?)
	JobWorld.removeCarry(s)
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local box = Instance.new("Part")
	box.Name = if kind == "box" then "RestockBox" else "ParcelBox"
	box.Size = if kind == "box" then Vector3.new(2.2, 1.5, 1.6) else Vector3.new(1.6, 1.1, 1.2)
	box.Color = if kind == "box" then Color3.fromRGB(196, 160, 110) else Color3.fromRGB(180, 140, 92)
	box.Material = Enum.Material.Cardboard
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.Massless = true
	box.CastShadow = false
	box.CFrame = torso.CFrame * CFrame.new(0, -0.35, -1.25)
	local tape = Instance.new("Part")
	tape.Name = "Tape"
	tape.Size = Vector3.new(0.35, box.Size.Y + 0.02, box.Size.Z + 0.02)
	tape.Color = Color3.fromRGB(150, 110, 60)
	tape.Material = Enum.Material.SmoothPlastic
	tape.CanCollide = false
	tape.CanQuery = false
	tape.CanTouch = false
	tape.Massless = true
	tape.CastShadow = false
	tape.CFrame = box.CFrame
	local w1 = Instance.new("WeldConstraint")
	w1.Part0 = torso
	w1.Part1 = box
	w1.Parent = box
	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = box
	w2.Part1 = tape
	w2.Parent = tape
	tape.Parent = box
	if label then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.MaxDistance = 40
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.GothamBold
		t.TextColor3 = Color3.fromRGB(40, 30, 20)
		t.Text = label
		t.Parent = gui
		gui.Parent = box
	end
	box.Parent = char
	s.carry = box
	s.carryKind = kind
end

-------------------------------------------------------------------------------------------------
-- Tick (from Jobs' 0.5 s loop)
-------------------------------------------------------------------------------------------------
local function tickStore(jobId: string, st: any, now: number)
	local workers = workersAt(jobId)
	-- spawn while someone works here
	if #workers > 0 and #st.customers < MAX_CUSTOMERS and now >= st.nextSpawn then
		local queued = 0
		for _, c in st.customers do
			if c.slot then
				queued += 1
			end
		end
		if queued < 2 then
			spawnCustomer(jobId, false)
		end
		st.nextSpawn = now + 9 + math.random() * 7
	end
	for i = #st.customers, 1, -1 do
		local c = st.customers[i]
		if not c then
			continue
		end
		if c.state == "walk" and now >= c.arriveAt then
			arrive(c)
			local nxt = c.nextState
			c.nextState = nil
			if nxt == "gone" then
				despawn(st, c)
				continue
			elseif nxt == "browse" then
				c.state = "browse"
				c.waitUntil = now + 3 + math.random() * 4
				setAct(c, "shop")
				if math.random() < 0.4 then
					modelSay(c.model, JS.CUSTOMER_LINES.browse[math.random(1, #JS.CUSTOMER_LINES.browse)])
				end
			elseif nxt == "toqueue" then
				toQueue(c)
			elseif nxt == "queue" then
				c.state = "queue"
				setAct(c, if c.slot == 1 then "queue" else "phone")
				if c.slot == 1 then
					c.slotSince = now
				end
			else
				c.state = nxt or "browse"
			end
		elseif c.state == "browse" and now >= c.waitUntil then
			if #workers == 0 then
				leave(c, nil)
			else
				toQueue(c)
			end
		elseif c.state == "queue" then
			if c.slot == 1 and not c.said and now >= c.arriveAt then
				c.said = true
				modelSay(c.model, JS.SALE_LINES[math.random(1, #JS.SALE_LINES)])
				-- tell the worker(s) when they are not on a counter task right now
				for _, p in workers do
					local s = Jobs.shifts[p]
					if s and s.task and s.task.world == "customer" and not s.roundStarted and math.random() < 0.5 then
						JobWorld.bossLine(p, jobId, "wait", "point")
					end
				end
			end
			if #workers == 0 then
				leave(c, nil)
				advanceQueue(jobId)
			elseif c.slot == 1 and now - c.slotSince > PATIENCE then
				leave(c, JS.CUSTOMER_LINES.angry[math.random(1, #JS.CUSTOMER_LINES.angry)])
				advanceQueue(jobId)
				for _, p in workers do
					JobWorld.bossLine(p, jobId, "left", "facepalm")
					local s = Jobs.shifts[p]
					if s then
						s.combo = 0
					end
				end
			elseif c.slot == 1 and now - c.slotSince > PATIENCE * 0.6 and not c.served and (c.model:GetAttribute("ShopSay") or "") ~= JS.CUSTOMER_LINES.slow[1] then
				modelSay(c.model, JS.CUSTOMER_LINES.slow[1])
			end
		elseif c.state == "serving" then
			-- the worker left: back to waiting
			if not c.worker or not Jobs.shifts[c.worker] then
				c.state = "queue"
				c.worker = nil
			end
		end
	end
end

function JobWorld.tick()
	local now = os.clock()
	for jobId, st in stores do
		local ok, err = pcall(tickStore, jobId, st, now)
		if not ok then
			warn("[GwangalliGameplay] JobWorld store " .. jobId .. ": " .. tostring(err))
		end
	end
end

-- exported for the simulator / tests
JobWorld.stores = stores
JobWorld.stationTable = stations
JobWorld.spawnCustomer = spawnCustomer

function JobWorld.init(context: any, jobsModule: any, js: any, remote: RemoteEvent?)
	ctx = context
	G = context.G
	Util = context.Util
	Jobs = jobsModule
	JS = js
	sayRemote = remote
	for _, inst in CollectionService:GetTagged("GwJobStation") do
		addStation(inst)
	end
	CollectionService:GetInstanceAddedSignal("GwJobStation"):Connect(addStation)
end

return JobWorld
