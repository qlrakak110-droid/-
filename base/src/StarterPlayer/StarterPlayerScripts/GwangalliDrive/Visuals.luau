-- GwangalliDrive/Visuals: local-only animation of every rigged car near the camera.
--   * wheels of cars driven by OTHER players (or rolling driverless): spin from the forward speed,
--     front-wheel steer estimated from the yaw rate (no network traffic); the local driver's own
--     car is animated by Drive from the controller state (exact suspension travel)
--   * turn indicators / hazards from the replicated DriveState bits (2 Hz blink)
-- Motor6D.Transform is written locally only; sleeping (anchored) cars are skipped.
-- Cost (docs/perf_findings.md R4): the 30 Hz wheel step visits only the "awake" list (unanchored
-- cars within RADIUS), rebuilt at 2 Hz from all registered cars (parked ones included); the
-- DriveState attribute is read only on blink ticks (every 0.4 s) and only for cars within
-- BLINK_RADIUS or still blinking. The indicator parts of a car are found once per car model
-- (attribute CarModel): later cars of the same model look them up by path instead of walking all
-- their descendants, and a car whose Detail model streams in later is resolved again then.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Visuals = {}

local VS: any = nil
local cars: { [Model]: any } = {}
local awake: { any } = {}
local skip: Model? = nil
local RADIUS = 240
local BLINK_RADIUS = 320
local AMBER = Color3.fromRGB(255, 150, 30)

function Visuals.setSkip(m: Model?)
	skip = m
end

local function isIndicator(name: string): boolean
	local lower = string.lower(name)
	return string.find(lower, "repeater", 1, true) ~= nil
		or string.find(lower, "turnlamp", 1, true) ~= nil
		or string.find(lower, "indicator", 1, true) ~= nil
		or string.find(lower, "blinker", 1, true) ~= nil
end

-- CarModel -> containers (name paths from the car model; {} = the model itself) holding indicator
-- parts. Filled from the first car of that model whose Detail child had streamed in.
local indicatorPaths: { [string]: { { string } } } = {}

local function resolve(model: Instance, path: { string }): Instance?
	local node: Instance? = model
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function addTurnPart(turn: any, base: BasePart, d: BasePart)
	local l = base.CFrame:PointToObjectSpace(d.Position)
	table.insert(if l.X < 0 then turn.left else turn.right, { part = d, material = d.Material, color = d.Color })
end

-- Finds the indicator parts of rec.model (rec.turn is replaced; lamps that were blinking are reset
-- first). Returns false when a cached container is missing (a sub-model not streamed in yet).
local function collectTurn(rec: any): boolean
	local model, base = rec.model, rec.base
	if rec.turn then
		for _, list in { rec.turn.left, rec.turn.right } do
			for _, l in list do
				if l.part.Parent then
					l.part.Material = l.material
					l.part.Color = l.color
				end
			end
		end
	end
	local turn = { left = {}, right = {} }
	rec.turn = turn
	rec.blinkOn = false
	local key = model:GetAttribute("CarModel")
	local paths = if type(key) == "string" then indicatorPaths[key] else nil
	if paths then
		local complete = true
		for _, path in paths do
			local parent = resolve(model, path)
			if parent then
				for _, c in parent:GetChildren() do
					if c:IsA("BasePart") and isIndicator(c.Name) then
						addTurnPart(turn, base, c)
					end
				end
			else
				complete = false
			end
		end
		return complete
	end
	-- first car of this model (or no CarModel): one walk, remembered per model once complete
	local found: { [Instance]: boolean } = {}
	local containers: { Instance } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and isIndicator(d.Name) then
			addTurnPart(turn, base, d)
			local parent = d.Parent
			if parent and not found[parent] then
				found[parent] = true
				table.insert(containers, parent)
			end
		end
	end
	if type(key) == "string" and model:FindFirstChild("Detail") then
		local list = {}
		for _, c in containers do
			local path = {}
			local node: Instance? = c
			while node and node ~= model do
				table.insert(path, 1, node.Name)
				node = node.Parent
			end
			if node == model then
				table.insert(list, path)
			end
		end
		indicatorPaths[key] = list
		return true
	end
	return model:FindFirstChild("Detail") ~= nil
end

local function collect(model: Model): any?
	local base = model:FindFirstChild(VS.Parts.Base)
	if not (base and base:IsA("BasePart")) then
		return nil
	end
	local rig = VS.decodeRig(model:GetAttribute(VS.Attr.Rig))
	if not rig then
		return nil
	end
	local wheels = {}
	local zf, zr, nf, nr = 0, 0, 0, 0
	for i, w in rig.wheels do
		local m1 = base:FindFirstChild(VS.Parts.Wheel .. i)
		local hub = m1 and (m1 :: any).Part1
		local m2 = hub and hub:FindFirstChild("DriveSpin" .. i)
		if m1 and m2 then
			table.insert(wheels, { steer = m1, spin = m2, r = w.r, front = w.front, angle = 0 })
		end
		if w.front then
			zf += w.z
			nf += 1
		else
			zr += w.z
			nr += 1
		end
	end
	local wb = if nf > 0 and nr > 0 then math.abs(zr / nr - zf / nf) else 9
	local rec = { model = model, base = base, wheels = wheels, wb = wb, steer = 0, turn = nil, blinkOn = false, conn = nil, awake = false }
	if not collectTurn(rec) then
		-- a sub-model (Detail) is still streaming in: look again when a child model arrives
		rec.conn = model.ChildAdded:Connect(function(ch)
			if ch:IsA("Model") and cars[model] == rec then
				if collectTurn(rec) and rec.conn then
					rec.conn:Disconnect()
					rec.conn = nil
				end
			end
		end)
	end
	return rec
end

local function drop(model: Model)
	local rec = cars[model]
	if rec then
		cars[model] = nil
		if rec.conn then
			rec.conn:Disconnect()
			rec.conn = nil
		end
	end
end

local function add(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local model = inst :: Model
	if cars[model] then
		return
	end
	local rec = collect(model)
	if rec then
		cars[model] = rec
	else
		-- rig attribute / parts may arrive a moment later
		task.delay(1, function()
			if model.Parent and not cars[model] and CollectionService:HasTag(model, VS.Tag) then
				local r = collect(model)
				if r then
					cars[model] = r
				end
			end
		end)
	end
end

local function remove(inst: Instance)
	drop(inst :: Model)
end

local function setTurn(list: { any }, on: boolean)
	for _, l in list do
		if l.part.Parent then
			if on then
				l.part.Material = Enum.Material.Neon
				l.part.Color = AMBER
			else
				l.part.Material = l.material
				l.part.Color = l.color
			end
		end
	end
end

function Visuals.start(shared: any)
	VS = shared
	for _, m in CollectionService:GetTagged(VS.Tag) do
		add(m)
	end
	CollectionService:GetInstanceAddedSignal(VS.Tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(VS.Tag):Connect(remove)

	local acc = 0
	local blinkT = 0
	local scanT = 1
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		blinkT += dt
		scanT += dt
		if acc < 1 / 30 then
			return
		end
		local step = acc
		acc = 0
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		-- 2 Hz: prune streamed-out cars, rebuild the awake list (unanchored, within RADIUS)
		if scanT >= 0.5 then
			scanT = 0
			table.clear(awake)
			for model, rec in cars do
				local base = rec.base
				if not base.Parent or not model.Parent then
					drop(model)
					continue
				end
				local near = (base.Position - camPos).Magnitude
				rec.dist = near
				if model ~= skip and not base.Anchored and near <= RADIUS + 40 then
					table.insert(awake, rec)
				end
			end
		end
		-- indicators (every 0.4 s): the state attribute only for cars in view range or still lit
		if blinkT >= 0.4 then
			blinkT = 0
			local B = VS.Bits
			for model, rec in cars do
				if rec.blinkOn or (rec.dist or math.huge) <= BLINK_RADIUS then
					if not model.Parent then
						continue
					end
					local bits = model:GetAttribute(VS.Attr.State) or 0
					local l = bit32.btest(bits, B.LEFT) or bit32.btest(bits, B.HAZARD)
					local r = bit32.btest(bits, B.RIGHT) or bit32.btest(bits, B.HAZARD)
					if l or r or rec.blinkOn then
						rec.blinkOn = not rec.blinkOn and (l or r)
						setTurn(rec.turn.left, rec.blinkOn and l)
						setTurn(rec.turn.right, rec.blinkOn and r)
					end
				end
			end
		end
		-- wheels (30 Hz): awake cars only
		for _, rec in awake do
			local base = rec.base
			if rec.model == skip or not base.Parent or base.Anchored then
				continue
			end
			if (base.Position - camPos).Magnitude > RADIUS then
				continue
			end
			local cf = base.CFrame
			local vel = base.AssemblyLinearVelocity
			local vLong = vel:Dot(cf.LookVector)
			local yaw = base.AssemblyAngularVelocity:Dot(cf.UpVector)
			local target = 0
			if math.abs(vLong) > 1.5 then
				target = -math.atan(yaw * rec.wb / vLong)
			end
			target = math.clamp(target, -0.6, 0.6)
			rec.steer += (target - rec.steer) * math.min(1, step * 8)
			for _, w in rec.wheels do
				w.angle = (w.angle + vLong / math.max(0.3, w.r) * step) % (2 * math.pi)
				w.spin.Transform = CFrame.Angles(-w.angle, 0, 0)
				w.steer.Transform = if w.front then CFrame.Angles(0, -rec.steer, 0) else CFrame.new()
			end
		end
	end)
end

return Visuals
