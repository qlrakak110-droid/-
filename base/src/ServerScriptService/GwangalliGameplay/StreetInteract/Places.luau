-- Interact/Places (server): the facility adapters the city NPCs use. It never builds or moves a
-- facility; it only reads the existing interfaces and keeps reservations so two users never share one.
--   * SEATS: plaza benches (Nav POIs 122 / 123, spots along the slab's long axis), GS25 광안리점 terrace
--     ChairSeats, any part tagged GwFacility Kind=seat (the building session's contract). take / release,
--     a player sitting there counts as taken; held POIs are published on the NPC folder ("PoiHeld")
--     so the clients' street pedestrians do not sit on the same spot.
--   * DOORS: AutoDoor models (GwangalliDoors). NPCs are anchored + attribute-driven, so a door is opened
--     with an invisible AutoDoorOpener-tagged proxy part placed at the door while a walking NPC's
--     computed path is about to cross it (ref-counted, removed after).
--   * STORE: GS25 광안리점 — the GwJobStation anchors JobWorld already uses (door_out, door_in, front,
--     browseN (+Path), queue1..3, counter, boss, backroom). While a player works the 알바 shift
--     (Jobs.shifts, index >= 1) JobWorld owns the queue: our shoppers hand off to JobWorld.spawnCustomer.
--     Otherwise our clerk + shoppers use the same graph with our own queue slots.
--   * ELEVATORS: ElevatorButton (Floor, Target = "ElevatorStop_<n>") — press, wait, ride (PivotTo).
--   * GwFacility (proposed contract, see docs): Kind = seat | queue | pickup | staff | lift ..., Held.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Places = {}

local I: any
local Cast: any
local Actors: any
local Jobs: any = nil
local JobWorld: any = nil
local Nav: any = nil

local spots: { [string]: Vector3 } = {}
Places.spots = spots

---------------------------------------------------------------------------------------------------
-- ground-checked named spots
---------------------------------------------------------------------------------------------------
function Places.spot(name: string?): Vector3?
	if not name then
		return nil
	end
	return spots[name]
end

-- the walkable point `dist` away from `to`, on the side of `from` (for watching / approaching)
function Places.nearPoint(from: Vector3, to: Vector3, dist: number): Vector3
	local d = Vector3.new(from.X - to.X, 0, from.Z - to.Z)
	if d.Magnitude < 0.1 then
		d = Vector3.new(1, 0, 0)
	end
	local p = to + d.Unit * dist
	return Vector3.new(p.X, Actors.groundAt(p, to.Y), p.Z)
end

---------------------------------------------------------------------------------------------------
-- seats
---------------------------------------------------------------------------------------------------
type Seat = { id: string, pos: Vector3, yaw: number, sitLift: number, held: string?, poi: number?, k: number?, group: string }
local seats: { Seat } = {}
Places.seats = seats

local function addSeat(id: string, pos: Vector3, yaw: number, group: string, poi: number?, k: number?)
	table.insert(seats, { id = id, pos = pos, yaw = yaw, sitLift = 0, held = nil, poi = poi, k = k, group = group })
end

local function publishHeld()
	local parts = {}
	for _, s in seats do
		if s.held and s.poi then
			table.insert(parts, s.poi .. ":" .. (s.k or 1))
		end
	end
	local f = workspace:FindFirstChild(I.C.NpcFolder)
	if f then
		f:SetAttribute("PoiHeld", table.concat(parts, ";"))
	end
end

local function playerOn(pos: Vector3): boolean
	for _, p in Players:GetPlayers() do
		local f = I.feetOf(p)
		if f and (Vector3.new(f.X - pos.X, 0, f.Z - pos.Z)).Magnitude < 1.6 then
			return true
		end
	end
	return false
end

-- reserve the closest free seat within r of `near` for NPC n (nil = none free)
function Places.takeSeat(n: any, near: Vector3, r: number): Seat?
	local best, bd = nil, r
	for _, s in seats do
		if not s.held then
			local d = (s.pos - near).Magnitude
			if d < bd and not playerOn(s.pos) then
				best, bd = s, d
			end
		end
	end
	if best then
		best.held = n.id
		n.holds = n.holds or {}
		n.holds["seat:" .. best.id] = best
		publishHeld()
	end
	return best
end

-- where somebody stands before sitting down (ground in front of the seat, along its facing)
function Places.seatApproach(s: Seat): Vector3
	local y = math.rad(s.yaw)
	local p = s.pos + Vector3.new(-math.sin(y), 0, -math.cos(y)) * 1.7
	return Vector3.new(p.X, Actors.groundAt(p + Vector3.new(0, 1, 0), s.pos.Y), p.Z)
end

function Places.releaseSeat(n: any, s: Seat?)
	if s and s.held == n.id then
		s.held = nil
		if n.holds then
			n.holds["seat:" .. s.id] = nil
		end
		publishHeld()
	end
end

---------------------------------------------------------------------------------------------------
-- doors (opener proxies)
---------------------------------------------------------------------------------------------------
type Door = { model: Instance, center: Vector3, radius: number, proxy: BasePart?, until_: number }
local doors: { Door } = {}

local doorSeen: { [Instance]: boolean } = {}
local function scanDoors(center: Vector3, r: number)
	for _, d in CollectionService:GetTagged("AutoDoor") do
		if doorSeen[d] then
			continue
		end
		local ok, cf = pcall(function()
			return (d :: any):GetPivot()
		end)
		if ok and cf and (cf.Position - center).Magnitude < r then
			-- centre = mean of the closed leaves (as GwangalliDoors), else the pivot
			local sum, n = Vector3.zero, 0
			for _, leaf in d:GetDescendants() do
				if leaf:IsA("BasePart") and leaf:GetAttribute("OpenOffset") ~= nil then
					sum += leaf.Position
					n += 1
				end
			end
			local c = if n > 0 then sum / n else cf.Position
			doorSeen[d] = true
			table.insert(doors, { model = d, center = c, radius = tonumber(d:GetAttribute("OpenRadius")) or 10, proxy = nil, until_ = 0 })
		end
	end
end

-- called by Mind for walking NPCs near players: open the doors their path is about to cross
function Places.doorTick()
	local now = os.clock()
	local st = workspace:GetServerTimeNow()
	for _, door in doors do
		local need = false
		for _, n in I.Mind.list do
			local a = n.a
			if n.present and a and not a.gone and a.path and n.lod ~= "far" then
				for _, dt in { 0, 0.5, 0.9 } do
					local p = Actors.pos(a, st + dt)
					if Vector3.new(p.X - door.center.X, 0, p.Z - door.center.Z).Magnitude < door.radius - 2 then
						need = true
						break
					end
				end
			end
			if need then
				break
			end
		end
		if need then
			door.until_ = now + 1.5
			if not door.proxy or not door.proxy.Parent then
				local p = Instance.new("Part")
				p.Name = "GiDoorOpener"
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.Transparency = 1
				p.Size = Vector3.new(0.2, 0.2, 0.2)
				p.Position = door.center
				CollectionService:AddTag(p, "AutoDoorOpener")
				p.Parent = workspace:FindFirstChild(I.C.NpcFolder) or workspace
				door.proxy = p
			end
		elseif door.proxy and now > door.until_ then
			door.proxy:Destroy()
			door.proxy = nil
		end
	end
end

---------------------------------------------------------------------------------------------------
-- the store (GS25 광안리점 station graph)
---------------------------------------------------------------------------------------------------
local STORE = "gs25"
local store = { ok = false, st = {} :: { [string]: any }, queue = {} :: { [number]: string? }, clerk = nil :: any, browse = {} :: { any } }
Places.store = store

local function stationFeet(part: BasePart): Vector3
	return part.Position - Vector3.new(0, 0.5, 0)
end

local function loadStore()
	local list = nil
	if JobWorld and JobWorld.stations then
		local ok, res = pcall(JobWorld.stations, STORE)
		if ok and type(res) == "table" then
			list = res
		end
	end
	if not list then
		list = {}
		for _, p in CollectionService:GetTagged("GwJobStation") do
			if p:IsA("BasePart") and p:GetAttribute("Job") == STORE then
				list[p:GetAttribute("Station")] = p
			end
		end
	end
	for id, part in list do
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			local look = part.CFrame.LookVector
			store.st[id] = { part = part, feet = stationFeet(part), yaw = math.deg(math.atan2(-look.X, -look.Z)), path = part:GetAttribute("Path") }
			if string.match(id, "^browse%d+$") then
				table.insert(store.browse, id)
			end
		end
	end
	store.ok = store.st.door_out ~= nil and store.st.queue1 ~= nil and store.st.counter ~= nil
	-- terrace chairs of the store as seats
	local map = workspace:FindFirstChild("Gwangalli")
	local gs = store.st.door_out and store.st.door_out.part
	local root = gs and gs:FindFirstAncestorWhichIsA("Model")
	while root and root.Parent and root.Parent ~= map and root.Parent:IsA("Model") do
		root = root.Parent:FindFirstAncestorWhichIsA("Model") or root.Parent
	end
	local scanRoot = (map and map:FindFirstChild("convenience")) or root
	if scanRoot then
		local i = 0
		for _, d in scanRoot:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "ChairSeat" and (d.Position - store.st.door_out.feet).Magnitude < 60 then
				i += 1
				-- seat.pos = the top of the seat (what the hips rest on); the renderer bends the legs over the edge
				local look = d.CFrame.LookVector
				local top = Vector3.new(d.Position.X, d.Position.Y + d.Size.Y / 2, d.Position.Z)
				addSeat("gs25_chair" .. i, top, math.deg(math.atan2(-look.X, -look.Z)), "gs25", nil, nil)
			end
		end
	end
end

function Places.storeStation(id: string): any?
	return store.st[id]
end

-- a player is clocked in at the store: JobWorld owns the counter and its queue
function Places.storeWorking(): boolean
	if not Jobs or type(Jobs.shifts) ~= "table" then
		return false
	end
	for p, s in Jobs.shifts do
		if typeof(p) == "Instance" and p.Parent == Players and type(s) == "table" and s.jobId == STORE and (s.index or 0) >= 1 then
			return true
		end
	end
	return false
end

-- room for one more JobWorld customer (its own cap is 3)
function Places.jobCustomerRoom(): boolean
	local st = JobWorld and JobWorld.stores and JobWorld.stores[STORE]
	return st ~= nil and #(st.customers or {}) < 3
end

function Places.spawnJobCustomer(): any?
	if not JobWorld or not JobWorld.spawnCustomer or not Places.jobCustomerRoom() then
		return nil
	end
	local ok, c = pcall(JobWorld.spawnCustomer, STORE, false)
	return if ok then c else nil
end

function Places.jobCustomerDone(c: any): boolean
	local pool = ServerStorage:FindFirstChild("GwangalliShopNPCPool")
	return not c or not c.model or c.model.Parent == nil or c.model.Parent == pool
end

-- our own queue (only while nobody works the shift)
function Places.queueJoin(n: any): number?
	for i = 1, 3 do
		if store.queue[i] == n.id then
			return i
		end
	end
	for i = 1, 3 do
		if not store.queue[i] then
			store.queue[i] = n.id
			n.holds = n.holds or {}
			n.holds.queue = true
			return i
		end
	end
	return nil
end

function Places.queueSlot(n: any): number?
	for i = 1, 3 do
		if store.queue[i] == n.id then
			return i
		end
	end
	return nil
end

-- everybody steps forward into a free slot ahead
function Places.queueAdvance()
	for i = 1, 2 do
		if not store.queue[i] and store.queue[i + 1] then
			store.queue[i] = store.queue[i + 1]
			store.queue[i + 1] = nil
		end
	end
end

function Places.queueLeave(n: any)
	for i = 1, 3 do
		if store.queue[i] == n.id then
			store.queue[i] = nil
		end
	end
	if n.holds then
		n.holds.queue = nil
	end
	Places.queueAdvance()
end

function Places.queueFeet(i: number): Vector3?
	local s = store.st["queue" .. i]
	return s and s.feet
end

-- the stations of a browse path ("front,aisle1" -> feet list) up to the browse spot
function Places.browsePath(id: string): { Vector3 }
	local out = {}
	local s = store.st[id]
	if not s then
		return out
	end
	if type(s.path) == "string" then
		for _, w in string.split(s.path, ",") do
			local ws = store.st[w]
			if ws then
				table.insert(out, ws.feet)
			end
		end
	end
	table.insert(out, s.feet)
	return out
end

function Places.chime()
	local d = store.st.door_in
	if d and d.part then
		d.part:SetAttribute("ChimeSeq", (d.part:GetAttribute("ChimeSeq") or 0) + 1)
	end
end

---------------------------------------------------------------------------------------------------
-- elevators (ElevatorButton: Floor, Target "ElevatorStop_<n>")
---------------------------------------------------------------------------------------------------
function Places.elevatorButtons(center: Vector3, r: number): { any }
	local out = {}
	for _, b in CollectionService:GetTagged("ElevatorButton") do
		local part = if b:IsA("BasePart") then b else b:FindFirstChildWhichIsA("BasePart", true)
		if part and (part.Position - center).Magnitude < r then
			table.insert(out, { button = b, part = part, floor = tonumber(b:GetAttribute("Floor")) or 1, target = b:GetAttribute("Target"), from = b:GetAttribute("FromFloor") })
		end
	end
	return out
end

function Places.elevatorStop(button: Instance, target: string?): BasePart?
	if type(target) ~= "string" then
		return nil
	end
	local node: Instance? = button
	for _ = 1, 10 do
		if not node then
			break
		end
		local s = node:FindFirstChild(target, true)
		if s and s:IsA("BasePart") then
			return s
		end
		node = node.Parent
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- holds cleanup (an NPC that stops an activity / despawns frees everything it had)
---------------------------------------------------------------------------------------------------
function Places.releaseAll(n: any)
	if not n.holds then
		return
	end
	for k, v in n.holds do
		if type(k) == "string" and string.sub(k, 1, 5) == "seat:" then
			Places.releaseSeat(n, v)
		end
	end
	if n.holds.queue then
		Places.queueLeave(n)
	end
	n.holds = {}
	-- a sim / Roblox body that was hidden for a JobWorld hand-off comes back on its own (Routine)
end

function Places.init(interact: any)
	I = interact
	Cast = I.Cast
	Actors = I.Actors
	local gg = script.Parent.Parent
	local function req(name: string): any
		local m = gg and gg:FindFirstChild(name)
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok and type(res) == "table" then
				return res
			end
		end
		return nil
	end
	Jobs = req("Jobs")
	JobWorld = req("JobWorld")
	local navM = game:GetService("ReplicatedStorage"):FindFirstChild("GwangalliNav")
	if navM then
		local ok, res = pcall(require, navM)
		if ok then
			Nav = res
		end
	end
	-- named spots: snapped to the pedestrian graph when a node is close, else to the ground
	local cache = nil
	if Nav and Nav.decode then
		local ok, c = pcall(Nav.decode)
		if ok then
			cache = c
		end
	end
	for name, p in Cast.PLACES do
		local snapped = nil
		if cache and Nav.nearest then
			local ok, node = pcall(Nav.nearest, p, 12)
			if ok and node and cache.pos[node] then
				snapped = cache.pos[node]
			end
		end
		spots[name] = snapped or Vector3.new(p.X, Actors.groundAt(Vector3.new(p.X, p.Y + 1.5, p.Z), p.Y), p.Z)
	end
	-- plaza benches: two sitters per slab along its long axis (X), facing the sea (-Z)
	for i, b in { Vector3.new(-278.3, 6.5, 15.5), Vector3.new(-246.3, 6.5, 16.0) } do
		local y = Actors.groundAt(b + Vector3.new(0, 1.5, 0), 6.5)
		for k, dx in { -1.6, 1.6 } do
			addSeat("plaza" .. i .. "_" .. k, Vector3.new(b.X + dx, y, b.Z - 0.3), 0, "plaza", if i == 1 then 123 else 122, k)
		end
	end
	-- the building session's seats (GwFacility Kind=seat), if any
	for _, p in CollectionService:GetTagged("GwFacility") do
		if p:IsA("BasePart") and p:GetAttribute("Kind") == "seat" then
			local look = p.CFrame.LookVector
			addSeat("fac_" .. p:GetFullName(), p.Position + Vector3.new(0, p.Size.Y / 2, 0), math.deg(math.atan2(-look.X, -look.Z)), tostring(p:GetAttribute("Site") or "fac"), nil, nil)
		end
	end
	loadStore()
	-- doors of the block: around the plaza and the store
	scanDoors(spots.plaza or Vector3.new(-262, 6.5, 22), 140)
	if store.st.door_out then
		scanDoors(store.st.door_out.feet, 40)
	end
	Places.Jobs = Jobs
	Places.JobWorld = JobWorld
	Places.Nav = Nav
end

return Places
