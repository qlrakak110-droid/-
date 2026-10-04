-- Elevators: real, working elevators (호출 -> 탑승 -> 층 선택 -> 이동 -> 도착).
--   Collective control (집합 선택 방식): the car keeps its direction while calls remain ahead, stops at
--   car calls and at hall calls in its direction, then reverses. Hall calls (▲ / ▼ prompts at every
--   stop, or the 월패드 "엘리베이터 호출" in a home), car calls (the panel inside the car / the floor
--   sheet on screen), door open / close / alarm buttons, door reopening when someone stands in the
--   doorway, a chime and the hall lantern on arrival, idle return to the lobby.
--   Motion: trapezoidal profile segments (Shared.Util.planSeg). The server publishes each segment as
--   attributes on the elevator Model; every client moves its car smoothly from the same server clock
--   and carries its own avatar with it, so riding works on any device without physics jitter. The
--   server writes the car CFrame only when the car stops. A call ahead of a moving car that it can
--   still stop for re-targets the running segment.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Util = Shared.Util
local Kit = Shared.Kit

local Elevators = {}

local Registry: any
local services: any

type Car = {
	model: Model,
	id: string,
	labels: { string },
	ys: { number },
	n: number,
	home: number,
	pos: number, -- stop index the car is at (or last passed)
	seg: any?,
	target: number?,
	dir: string,
	door: string,
	doorT: number,
	dwellUntil: number,
	carCalls: { [number]: boolean },
	up: { [number]: boolean },
	down: { [number]: boolean },
	idleSince: number,
	restricted: { [number]: string },
	carCF0: CFrame,
	carY0: number,
	base: CFrame,
	doorW: number,
}

local cars: { [Model]: Car } = {}
local byId: { [string]: Car } = {}

local function now(): number
	return Registry.now()
end

local function setList(m: Model, attr: string, set: { [number]: boolean })
	local list = {}
	for k in set do
		table.insert(list, k)
	end
	table.sort(list)
	m:SetAttribute(attr, table.concat(list, ","))
end

local function publish(c: Car)
	local m = c.model
	setList(m, "Calls", c.carCalls)
	setList(m, "HallUp", c.up)
	setList(m, "HallDown", c.down)
	m:SetAttribute("Dir", c.dir)
	m:SetAttribute("Pos", c.pos)
end

local function curY(c: Car): (number, number)
	if c.seg then
		local y, v = Util.evalSeg(c.seg, now())
		return y, v
	end
	return c.ys[c.pos], 0
end

-- the car's model pivot for a car-floor height
local function placeCar(c: Car, y: number)
	local car = c.model:FindFirstChild("Car")
	if car and car:IsA("Model") then
		car:PivotTo(c.carCF0 + Vector3.new(0, y - c.carY0, 0))
	end
end

local function setDoor(c: Car, phase: string)
	c.door = phase
	c.doorT = now()
	c.model:SetAttribute("Door", phase)
	c.model:SetAttribute("DoorT0", c.doorT)
	-- door collisions: the hall leaves of the stop + the car leaves are passable while not closed
	local passable = phase ~= "closed"
	local stopM = c.model:FindFirstChild("Stop_" .. c.pos)
	if stopM then
		for _, d in stopM:GetDescendants() do
			if d:IsA("BasePart") and d.Parent and string.sub(d.Parent.Name, 1, 8) == "HallLeaf" then
				d.CanCollide = not passable
			end
		end
	end
	local car = c.model:FindFirstChild("Car")
	if car then
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") and d.Parent and string.sub(d.Parent.Name, 1, 7) == "CarLeaf" then
				d.CanCollide = not passable
			end
		end
	end
	if phase == "closed" then
		-- every other stop's hall doors are closed
		for _, s in c.model:GetChildren() do
			if string.sub(s.Name, 1, 5) == "Stop_" then
				for _, d in s:GetDescendants() do
					if d:IsA("BasePart") and d.Parent and string.sub(d.Parent.Name, 1, 8) == "HallLeaf" then
						d.CanCollide = true
					end
				end
			end
		end
	end
end

local function playersInDoorway(c: Car): boolean
	local f = c.base * CFrame.new(0, c.ys[c.pos] - c.base.Y, 0)
	for _, p in Players:GetPlayers() do
		local pos = Registry.pos(p)
		if pos then
			local l = f:PointToObjectSpace(pos)
			if math.abs(l.X) < c.doorW / 2 + 0.3 and l.Z > -1.4 and l.Z < 1.6 and l.Y > -1 and l.Y < 8 then
				return true
			end
		end
	end
	return false
end

function Elevators.inCar(c: Car, p: Player): boolean
	local pos = Registry.pos(p)
	if not pos then
		return false
	end
	local y = curY(c)
	local f = c.base * CFrame.new(0, y - c.base.Y, 0)
	local l = f:PointToObjectSpace(pos)
	return math.abs(l.X) < Config.ELEV_CAR_W / 2 + 0.4 and l.Z > 0.2 and l.Z < 0.6 + Config.ELEV_CAR_D + 0.4 and l.Y > -1 and l.Y < 9
end

local function anyRider(c: Car): boolean
	for _, p in Players:GetPlayers() do
		if Elevators.inCar(c, p) then
			return true
		end
	end
	return false
end

local function anyCalls(c: Car): boolean
	return next(c.carCalls) ~= nil or next(c.up) ~= nil or next(c.down) ~= nil
end

local function callsAbove(c: Car, from: number): boolean
	for i = from + 1, c.n do
		if c.carCalls[i] or c.up[i] or c.down[i] then
			return true
		end
	end
	return false
end

local function callsBelow(c: Car, from: number): boolean
	for i = from - 1, 1, -1 do
		if c.carCalls[i] or c.up[i] or c.down[i] then
			return true
		end
	end
	return false
end

-- next stop in the current direction (collective control)
local function nextStop(c: Car): (number?, string)
	local p = c.pos
	local dir = c.dir
	if dir == "" then
		-- nearest call decides
		local best, bd = nil, math.huge
		for i = 1, c.n do
			if c.carCalls[i] or c.up[i] or c.down[i] then
				local d = math.abs(i - p)
				if d < bd then
					best, bd = i, d
				end
			end
		end
		if not best then
			return nil, ""
		end
		if best == p then
			return p, (if c.up[p] then "up" elseif c.down[p] then "down" else "")
		end
		dir = if best > p then "up" else "down"
	end
	if dir == "up" then
		for i = p + 1, c.n do
			if c.carCalls[i] or c.up[i] then
				return i, "up"
			end
		end
		-- the highest down call above turns the car around there
		for i = c.n, p + 1, -1 do
			if c.down[i] then
				return i, "up"
			end
		end
		if callsBelow(c, p + 1) then
			c.dir = "down"
			return nextStop(c)
		end
	else
		for i = p - 1, 1, -1 do
			if c.carCalls[i] or c.down[i] then
				return i, "down"
			end
		end
		for i = 1, p - 1 do
			if c.up[i] then
				return i, "down"
			end
		end
		if callsAbove(c, p - 1) then
			c.dir = "up"
			return nextStop(c)
		end
	end
	return nil, ""
end

local function startMove(c: Car, target: number)
	local y0, v0 = curY(c)
	local seg = { y0 = y0, y1 = c.ys[target], t0 = now(), v0 = math.abs(v0), vmax = Config.ELEV_SPEED, a = Config.ELEV_ACCEL }
	c.seg = seg
	c.target = target
	c.dir = if c.ys[target] > y0 then "up" else "down"
	local m = c.model
	m:SetAttribute("SegY0", seg.y0)
	m:SetAttribute("SegY1", seg.y1)
	m:SetAttribute("SegT0", seg.t0)
	m:SetAttribute("SegV0", seg.v0)
	m:SetAttribute("Moving", true)
	m:SetAttribute("Target", target)
	publish(c)
	-- the destination storey is built while the car travels
	local St = services and services.Streaming
	local rec = Registry.get(m:GetAttribute("BuildingId") :: string)
	local fl = rec and rec.floorByLabel and rec.floorByLabel[c.labels[target]]
	if St and fl and anyRider(c) then
		task.spawn(St.ensureFloor, rec, fl)
	end
end

local function arrive(c: Car)
	local t = c.target :: number
	c.pos = t
	c.seg = nil
	c.target = nil
	placeCar(c, c.ys[t])
	c.model:SetAttribute("Moving", false)
	c.model:SetAttribute("SegY0", c.ys[t])
	c.model:SetAttribute("SegY1", c.ys[t])
	c.carCalls[t] = nil
	-- answer the hall call in the travel direction; at the ends / when nothing remains ahead, both
	local ahead = if c.dir == "up" then callsAbove(c, t) else callsBelow(c, t)
	if c.dir == "up" then
		if c.up[t] or not ahead then
			c.up[t] = nil
			if not ahead and c.down[t] then
				c.down[t] = nil
				c.dir = "down"
			end
		end
	elseif c.dir == "down" then
		if c.down[t] or not ahead then
			c.down[t] = nil
			if not ahead and c.up[t] then
				c.up[t] = nil
				c.dir = "up"
			end
		end
	end
	if not anyCalls(c) then
		c.dir = ""
	end
	c.model:SetAttribute("Arrive", now())
	setDoor(c, "opening")
	publish(c)
end

local function tick(c: Car)
	local t = now()
	local m = c.model
	if not m:IsDescendantOf(workspace) then
		return
	end
	if c.seg then
		-- re-target to a closer stop in the direction of travel when a new call allows it
		local y, v = Util.evalSeg(c.seg, t)
		local done = t - c.seg.t0 >= Util.segDuration(c.seg)
		if done then
			arrive(c)
			return
		end
		local dirUp = c.seg.y1 > c.seg.y0
		local brake = Util.brakeDistance(math.abs(v), Config.ELEV_ACCEL) + 0.3
		local tgt = c.target :: number
		if dirUp then
			for i = 1, tgt - 1 do
				if c.ys[i] > y + brake and (c.carCalls[i] or c.up[i]) then
					startMove(c, i)
					break
				end
			end
		else
			for i = c.n, tgt + 1, -1 do
				if c.ys[i] < y - brake and (c.carCalls[i] or c.down[i]) then
					startMove(c, i)
					break
				end
			end
		end
		-- track the stop we last passed (for the hall lanterns / server queries)
		local passed = c.pos
		for i = 1, c.n do
			if (dirUp and c.ys[i] <= y + 0.1) or (not dirUp and c.ys[i] >= y - 0.1) then
				passed = i
				if not dirUp then
					break
				end
			end
		end
		if passed ~= c.pos then
			c.pos = passed
			m:SetAttribute("Pos", passed)
		end
		return
	end
	-- stopped
	local dt = t - c.doorT
	if c.door == "opening" then
		if dt >= Config.ELEV_DOOR_TIME then
			setDoor(c, "open")
			c.dwellUntil = t + Config.ELEV_DWELL
		end
	elseif c.door == "open" then
		if t >= c.dwellUntil then
			if playersInDoorway(c) then
				c.dwellUntil = t + 1.0
			else
				setDoor(c, "closing")
			end
		end
	elseif c.door == "closing" then
		if playersInDoorway(c) then
			setDoor(c, "opening")
		elseif dt >= Config.ELEV_DOOR_TIME then
			setDoor(c, "closed")
			c.idleSince = t
		end
	elseif c.door == "closed" then
		local nxt = nextStop(c)
		if nxt then
			if nxt == c.pos then
				c.carCalls[nxt] = nil
				c.up[nxt] = nil
				c.down[nxt] = nil
				setDoor(c, "opening")
				m:SetAttribute("Arrive", t)
				publish(c)
			else
				startMove(c, nxt)
			end
		elseif Config.ELEV_IDLE_HOME > 0 and c.pos ~= c.home and t - c.idleSince > Config.ELEV_IDLE_HOME then
			c.dir = ""
			startMove(c, c.home)
			c.carCalls[c.home] = nil
		end
	end
end

-- API ------------------------------------------------------------------------------------------------
function Elevators.hallCall(c: Car, stop: number, dir: string, p: Player?)
	if stop < 1 or stop > c.n then
		return
	end
	-- the car is here with doors opening / open: keep them open
	if not c.seg and c.pos == stop and c.door ~= "closed" then
		if c.door == "closing" then
			setDoor(c, "opening")
		end
		c.dwellUntil = math.max(c.dwellUntil, now() + Config.ELEV_DWELL_EXTEND)
		return
	end
	if dir == "up" then
		c.up[stop] = true
	else
		c.down[stop] = true
	end
	if c.dir == "" and not c.seg and c.door == "closed" then
		c.idleSince = now()
	end
	publish(c)
	c.model:SetAttribute("HallPress", now())
end

function Elevators.carCall(c: Car, stop: number, p: Player): (boolean, string?)
	if stop < 1 or stop > c.n then
		return false, nil
	end
	local unitId = c.restricted[stop]
	if unitId and services.Housing and not services.Housing.canEnter(p, unitId) then
		return false, "🔒 " .. c.labels[stop] .. "은(는) 입주민 전용 층이에요 (카드키 필요)"
	end
	if not c.seg and c.pos == stop then
		if c.door == "closed" or c.door == "closing" then
			setDoor(c, "opening")
		end
		return true, nil
	end
	c.carCalls[stop] = true
	publish(c)
	return true, nil
end

function Elevators.byId(id: string): Car?
	return byId[id]
end

-- call the elevator of a building to a storey (월패드). dir defaults to "down" (going out)
function Elevators.callFloor(rec: any, label: string, dir: string?): boolean
	for _, e in rec.elevators do
		local c = byId[e.id]
		if c then
			for i, l in c.labels do
				if l == label then
					local d = dir or (if i > 1 then "down" else "up")
					if i == c.n then
						d = "down"
					elseif i == 1 then
						d = "up"
					end
					Elevators.hallCall(c, i, d, nil)
					return true
				end
			end
		end
	end
	return false
end

local function register(m: Instance)
	if not m:IsA("Model") or cars[m] then
		return
	end
	local labels = Util.split(m:GetAttribute("Stops") :: string, "|")
	local ys = {}
	for _, s in Util.split(m:GetAttribute("StopY") :: string, "|") do
		table.insert(ys, tonumber(s) or 0)
	end
	if #labels == 0 or #labels ~= #ys then
		warn("[GwangalliBuildings] elevator without stops: " .. m:GetFullName())
		return
	end
	local car = m:FindFirstChild("Car") :: Model?
	if not car then
		return
	end
	local home = tonumber(m:GetAttribute("Home")) or 1
	local restricted = {}
	for _, pair in Util.split(m:GetAttribute("Restricted") :: string?, ",") do
		local i, u = string.match(pair, "^(%d+)=(.+)$")
		if i and u then
			restricted[tonumber(i) :: number] = u
		end
	end
	local base = m:GetAttribute("BaseCF")
	local c: Car = {
		model = m,
		id = m:GetAttribute("ElevatorId") :: string,
		labels = labels,
		ys = ys,
		n = #labels,
		home = home,
		pos = home,
		seg = nil,
		target = nil,
		dir = "",
		door = "closed",
		doorT = 0,
		dwellUntil = 0,
		carCalls = {},
		up = {},
		down = {},
		idleSince = 0,
		restricted = restricted,
		carCF0 = car:GetPivot(),
		carY0 = ys[home],
		base = if typeof(base) == "CFrame" then base else car:GetPivot(),
		doorW = tonumber(m:GetAttribute("DoorW")) or 4.4,
	}
	m:SetAttribute("CarY0", c.carY0)
	m:SetAttribute("CarCF0", c.carCF0)
	m:SetAttribute("SegY0", ys[home])
	m:SetAttribute("SegY1", ys[home])
	m:SetAttribute("SegT0", 0)
	m:SetAttribute("SegV0", 0)
	m:SetAttribute("VMax", Config.ELEV_SPEED)
	m:SetAttribute("Accel", Config.ELEV_ACCEL)
	cars[m] = c
	byId[c.id] = c
	-- hall buttons + car panel prompts
	for _, b in m:GetDescendants() do
		if b:IsA("BasePart") and CollectionService:HasTag(b, "GwB_ElevButton") then
			local where = b:GetAttribute("Where")
			local stop = tonumber(b:GetAttribute("Stop"))
			if where == "hall" and stop then
				local dir = b:GetAttribute("Dir") :: string
				local pr = Kit.prompt(b, if dir == "up" then "▲ 올라가기" else "▼ 내려가기", "엘리베이터 · " .. labels[stop], { dist = 6, name = "CallPrompt" })
				pr.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
				pr.Triggered:Connect(function(p)
					if Registry.near(p, b, 10) then
						Elevators.hallCall(c, stop, dir, p)
					end
				end)
			end
		elseif b:IsA("BasePart") and b.Name == "COP" then
			local pr = Kit.prompt(b, "층 선택", m:GetAttribute("Name") :: string? or "엘리베이터", { dist = 5, name = "PanelPrompt" })
			pr.Triggered:Connect(function(p)
				Registry.fire(p, "elev.panel", { elevator = m })
			end)
		end
	end
	setDoor(c, "closed")
	publish(c)
end

function Elevators.onHot(rec: any)
	for _, e in rec.elevators do
		local c = byId[e.id]
		if c and not c.seg then
			placeCar(c, c.ys[c.pos])
		end
	end
end

function Elevators.init(ctx: any)
	Registry = ctx.Registry
	services = ctx.services
	CollectionService:GetInstanceAddedSignal("GwB_Elevator"):Connect(register)
	for _, m in CollectionService:GetTagged("GwB_Elevator") do
		register(m)
	end
	Registry.on("elev.call", function(p: Player, d: any)
		local m = d.elevator
		local c = if typeof(m) == "Instance" then cars[m :: Model] else nil
		if not c or type(d.stop) ~= "number" then
			return { ok = false }
		end
		local stopM = c.model:FindFirstChild("Stop_" .. d.stop)
		if not stopM or not Registry.near(p, (stopM :: Model):GetPivot().Position, 40) then
			return { ok = false, msg = "버튼에서 너무 멀어요" }
		end
		Elevators.hallCall(c, d.stop, if d.dir == "up" then "up" else "down", p)
		return { ok = true }
	end)
	Registry.on("elev.car", function(p: Player, d: any)
		local m = d.elevator
		local c = if typeof(m) == "Instance" then cars[m :: Model] else nil
		if not c or type(d.stop) ~= "number" then
			return { ok = false }
		end
		if not Elevators.inCar(c, p) then
			return { ok = false, msg = "엘리베이터 안에서 눌러 주세요" }
		end
		local ok, msg = Elevators.carCall(c, math.floor(d.stop), p)
		return { ok = ok, msg = msg }
	end)
	Registry.on("elev.door", function(p: Player, d: any)
		local m = d.elevator
		local c = if typeof(m) == "Instance" then cars[m :: Model] else nil
		if not c or not Elevators.inCar(c, p) then
			return { ok = false }
		end
		if d.action == "open" then
			if not c.seg then
				if c.door == "closing" or c.door == "closed" then
					setDoor(c, "opening")
				else
					c.dwellUntil = math.max(c.dwellUntil, now() + Config.ELEV_DWELL_EXTEND)
				end
			end
		elseif d.action == "close" then
			if not c.seg and c.door == "open" then
				setDoor(c, "closing")
			end
		elseif d.action == "alarm" then
			c.model:SetAttribute("Alarm", now())
			Registry.toast(p, "🔔 비상벨: 관리실과 연결되었습니다. 잠시만 기다려 주세요", "warn")
		end
		return { ok = true }
	end)
end

function Elevators.start()
	while true do
		task.wait(0.1)
		for _, c in cars do
			local ok, err = pcall(tick, c)
			if not ok then
				warn("[GwangalliBuildings] elevator " .. c.id .. ": " .. tostring(err))
			end
		end
	end
end

return Elevators
