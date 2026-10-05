-- GwangalliLawCars (LocalScript, StarterPlayerScripts; owner: law): the NPC patrol cars of
-- Law/Police on this client.
--   * MOTION: every car in workspace.GwangalliLawCars carries its drive path (LawPath "x,y,z,t;..."
--     + LawT0 = server time of t = 0, LawSerial bumps on every re-plan). Each rendered frame the root
--     goes to the path sample at the server clock (the same sampler as the server's TaxiDispatch), so
--     the car advances and turns every frame — never stepped at a fixed rate — and corners show the
--     path's speed profile (slow down, steer, speed up). No path = parked where the server put it.
--   * LIGHT BAR: lamps tagged LawLamp ("r" / "b") flash in turns while LawSiren is on (and glow
--     through their PointLight), so the car is seen from far down the road; off = dark lamps.
--   * VISIBILITY GUARD: a car that arrives with LocalTransparencyModifier left on (an interrupted
--     fade elsewhere) is cleared; parts that stream in later are picked up.
--   * The seated crew is GwangalliNPCClient's (NpcSeat): it reads this car's root after this script
--     moved it (render priority just before the NPC client).

local RunService = game:GetService("RunService")

local UP = Vector3.new(0, 1, 0)

local function unitFlat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	local m = f.Magnitude
	if m < 1e-4 then
		return nil
	end
	return f / m
end

local function cframe(pos: Vector3, dir: Vector3): CFrame
	local look = unitFlat(dir) or Vector3.new(0, 0, -1)
	return CFrame.fromMatrix(pos, look:Cross(UP), UP, -look)
end

local function posAt(pts: { Vector3 }, times: { number }, t: number): (Vector3, number)
	local n = #pts
	if n == 0 then
		return Vector3.zero, 1
	end
	if t <= times[1] or n == 1 then
		return pts[1], 1
	end
	if t >= times[n] then
		return pts[n], n - 1
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if times[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local span = times[hi] - times[lo]
	local u = if span > 1e-6 then (t - times[lo]) / span else 1
	return pts[lo]:Lerp(pts[hi], u), lo
end

-- same maths as TaxiDispatch.sample (heading = the chord over +-0.3 s)
local function sample(pts: { Vector3 }, times: { number }, t: number): (Vector3, Vector3)
	local p, i = posAt(pts, times, t)
	local a = posAt(pts, times, t - 0.3)
	local b = posAt(pts, times, t + 0.3)
	local dir = unitFlat(b - a)
	if not dir or Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude < 0.4 then
		local n = #pts
		local j = math.clamp(i, 1, math.max(1, n - 1))
		dir = nil
		for k = j, 1, -1 do
			if k + 1 <= n then
				dir = unitFlat(pts[k + 1] - pts[k])
				if dir and Vector3.new(pts[k + 1].X - pts[k].X, 0, pts[k + 1].Z - pts[k].Z).Magnitude > 0.4 then
					break
				end
			end
		end
		if not dir then
			for k = j, n - 1 do
				dir = unitFlat(pts[k + 1] - pts[k])
				if dir then
					break
				end
			end
		end
	end
	return p, dir or Vector3.new(0, 0, -1)
end

local function decode(s: string): ({ Vector3 }, { number })
	local pts, times = {}, {}
	for x, y, z, t in string.gmatch(s, "([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)") do
		local nx, ny, nz, nt = tonumber(x), tonumber(y), tonumber(z), tonumber(t)
		if nx and ny and nz and nt then
			table.insert(pts, Vector3.new(nx, ny, nz))
			table.insert(times, nt)
		end
	end
	return pts, times
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

type Car = { model: Model, root: BasePart?, pts: { Vector3 }, times: { number }, t0: number, total: number, lamps: { BasePart }, siren: boolean, conns: { RBXScriptConnection } }

local cars: { [Model]: Car } = {}

local function loadPath(car: Car)
	local s = car.model:GetAttribute("LawPath")
	local t0 = car.model:GetAttribute("LawT0")
	if type(s) == "string" and s ~= "" and type(t0) == "number" then
		car.pts, car.times = decode(s)
		car.t0 = t0
		car.total = if #car.times > 0 then car.times[#car.times] else 0
	else
		car.pts, car.times, car.total = {}, {}, 0
	end
end

local function setLamps(car: Car, redOn: boolean?, blueOn: boolean?)
	for _, l in car.lamps do
		if l.Parent then
			local kind = l:GetAttribute("LawLamp")
			local on = if kind == "r" then redOn else blueOn
			l.Transparency = if on then 0 else 0.55
			local glow = l:FindFirstChild("LawGlow")
			if glow and glow:IsA("PointLight") then
				glow.Enabled = on == true
			end
		end
	end
end

local function untrack(model: Model)
	local car = cars[model]
	if car then
		for _, c in car.conns do
			c:Disconnect()
		end
		cars[model] = nil
	end
end

local function track(model: Instance)
	if not model:IsA("Model") or cars[model] or not model:GetAttribute("LawCar") then
		return
	end
	local car: Car = { model = model, root = model.PrimaryPart or model:FindFirstChild("CarRoot") :: BasePart?, pts = {}, times = {}, t0 = 0, total = 0, lamps = {}, siren = model:GetAttribute("LawSiren") == true, conns = {} }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("LawLamp") then
				table.insert(car.lamps, d)
			end
			if d.LocalTransparencyModifier ~= 0 then
				d.LocalTransparencyModifier = 0
			end
		end
	end
	cars[model] = car
	table.insert(car.conns, model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			if d:GetAttribute("LawLamp") then
				table.insert(car.lamps, d)
			end
			if d.Name == "CarRoot" then
				car.root = d
			end
		end
	end))
	loadPath(car)
	table.insert(car.conns, model.AttributeChanged:Connect(function(name: string)
		if name == "LawPath" or name == "LawT0" or name == "LawSerial" then
			loadPath(car)
		elseif name == "LawSiren" then
			car.siren = model:GetAttribute("LawSiren") == true
			if not car.siren then
				setLamps(car, false, false)
			end
		end
	end))
	table.insert(car.conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			untrack(model)
		end
	end))
	if not car.siren then
		setLamps(car, false, false)
	end
end

local lastFlash = 0
local phase = 0
local function step()
	local tNow = serverNow()
	local flash = false
	if os.clock() - lastFlash > 0.18 then
		lastFlash = os.clock()
		phase = (phase + 1) % 4
		flash = true
	end
	for _, car in cars do
		local root = car.root
		if not root or not root.Parent then
			car.root = car.model.PrimaryPart or car.model:FindFirstChild("CarRoot") :: BasePart?
			root = car.root
		end
		if root and #car.pts > 1 then
			local t = tNow - car.t0
			if t <= car.total + 0.5 then
				local p, dir = sample(car.pts, car.times, math.min(math.max(t, 0), car.total))
				if p == p then
					root.CFrame = cframe(p, dir)
				end
			end
		end
		if flash and car.siren then
			-- red, dark, blue, dark (each side in turn)
			setLamps(car, phase == 0, phase == 2)
		end
	end
end

RunService:BindToRenderStep("GwangalliLawCars", Enum.RenderPriority.Camera.Value - 1, function()
	local ok, err = pcall(step)
	if not ok then
		warn("[GwangalliLawCars] " .. tostring(err))
	end
end)

task.spawn(function()
	local f = workspace:WaitForChild("GwangalliLawCars", 120)
	while not f do
		f = workspace:WaitForChild("GwangalliLawCars", 120)
	end
	f.ChildAdded:Connect(function(ch)
		task.defer(track, ch)
	end)
	f.ChildRemoved:Connect(function(ch)
		if ch:IsA("Model") then
			untrack(ch)
		end
	end)
	for _, ch in f:GetChildren() do
		track(ch)
	end
end)

