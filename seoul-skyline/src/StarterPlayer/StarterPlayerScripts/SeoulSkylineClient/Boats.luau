--!strict
-- SeoulSkylineClient / Boats — 한강 유람선(태그 SeoulBoat 모델) 운항
--   속성 PathA / PathB (Vector3, 수선면), Speed (stud/s), TurnRadius (stud, 기본 30 m), Phase (0~1, A→B 구간 시작점).
--   경로 = 경기장형 루프: A→B 직선 → 강 중심 쪽으로 반원 U턴 → 평행한 복귀 직선 → 반원 U턴 → A.
--   U턴에서는 속도를 55 % 로 부드럽게 줄이고(전후 60 m 램프), 선회 방향 반대로 살짝 기울며, 잔물결에 따라
--   아주 작게 상하·좌우로 흔들립니다. 매 프레임 Model:PivotTo (카메라에서 9 km 밖이면 갱신 생략).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Util = require(script.Parent.Util)

local Boats = {}

local TAG = "SeoulBoat"
local STEP_NAME = "SeoulSkylineBoats"
local FAR = 9000

type Boat = {
	model: Model,
	original: CFrame,
	A: Vector3,
	dir: Vector3,
	n: Vector3,
	R: number,
	Ls: number,
	total: number,
	speed: number,
	s: number,
	ramp: number,
	bob: number,
	turnSign: number,
}

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- s → 위치, 진행 방향
local function sample(b: Boat, s: number): (Vector3, Vector3)
	local Ls, R, A, dir, n = b.Ls, b.R, b.A, b.dir, b.n
	local half = math.pi * R
	if s < Ls then
		return A + dir * s, dir
	end
	s -= Ls
	local B = A + dir * Ls
	if s < half then
		local th = s / R
		local c = B + n * R
		return c - n * (R * math.cos(th)) + dir * (R * math.sin(th)), dir * math.cos(th) + n * math.sin(th)
	end
	s -= half
	local B2 = B + n * (2 * R)
	if s < Ls then
		return B2 - dir * s, -dir
	end
	s -= Ls
	local th = math.min(s / R, math.pi)
	local c = A + n * R
	return c + n * (R * math.cos(th)) - dir * (R * math.sin(th)), -dir * math.cos(th) - n * math.sin(th)
end

-- 루프 위 s 에서 가장 가까운 U턴까지의 (순환) 거리 → 감속/기울기 가중(0~1)
local function turnWeight(b: Boat, s: number): number
	local T, Ls, half = b.total, b.Ls, math.pi * b.R
	local function circ(x: number): number
		local d = math.abs(s - x) % T
		return math.min(d, T - d)
	end
	local d = math.huge
	for _, seg in { { Ls, Ls + half }, { 2 * Ls + half, T } } do
		if s >= seg[1] and s <= seg[2] then
			return 1
		end
		d = math.min(d, circ(seg[1]), circ(seg[2]))
	end
	return 1 - smooth(d / b.ramp)
end

local function makeBoat(model: Model, root: Model): Boat?
	local A, B = model:GetAttribute("PathA"), model:GetAttribute("PathB")
	if typeof(A) ~= "Vector3" or typeof(B) ~= "Vector3" then
		return nil
	end
	local flat = Vector3.new(B.X - A.X, 0, B.Z - A.Z)
	if flat.Magnitude < 10 then
		return nil
	end
	local dir = flat.Unit
	local n = Vector3.new(-dir.Z, 0, dir.X)
	if n:Dot(Vector3.new(0, 0, -A.Z)) < 0 then -- 강 중심(Z = 0) 쪽으로 U턴
		n = -n
	end
	local R = model:GetAttribute("TurnRadius")
	local speed = model:GetAttribute("Speed")
	local phase = model:GetAttribute("Phase")
	local rr = if typeof(R) == "number" and R > 1 then R else Util.m(30, root)
	local Ls = flat.Magnitude
	local b: Boat = {
		model = model,
		original = model:GetPivot(),
		A = A,
		dir = dir,
		n = n,
		R = rr,
		Ls = Ls,
		total = 2 * Ls + 2 * math.pi * rr,
		speed = if typeof(speed) == "number" and speed > 0 then speed else Util.m(5, root),
		s = (if typeof(phase) == "number" then math.clamp(phase, 0, 1) else 0) * Ls,
		ramp = Util.m(60, root),
		bob = (Util.hash(model:GetFullName()) % 628) / 100,
		turnSign = if n:Dot(dir:Cross(Vector3.yAxis)) > 0 then 1 else -1, -- 선회 바깥쪽으로 기움
	}
	return b
end

function Boats.start(root: Model): () -> ()
	if root:GetAttribute("Boats") == false then
		return function() end
	end
	local boats: { [Model]: Boat } = {}
	local conns: { RBXScriptConnection } = {}

	local function add(inst: Instance)
		if not inst:IsA("Model") or boats[inst] or not inst:IsDescendantOf(root) then
			return
		end
		local b = makeBoat(inst, root)
		if b then
			boats[inst] = b
		end
	end
	table.insert(conns, CollectionService:GetInstanceAddedSignal(TAG):Connect(add))
	table.insert(conns, CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		boats[inst :: Model] = nil
	end))
	for _, inst in CollectionService:GetTagged(TAG) do
		add(inst)
	end

	local clock = 0
	local function step(dt: number)
		dt = math.min(dt, 0.1)
		clock += dt
		local cam = workspace.CurrentCamera
		local cp = if cam then cam.CFrame.Position else Vector3.zero
		for model, b in boats do
			if not model.Parent then
				boats[model] = nil
				continue
			end
			local w = turnWeight(b, b.s)
			b.s = (b.s + b.speed * (1 - 0.45 * w) * dt) % b.total
			local pos, fwd = sample(b, b.s)
			if (pos - cp).Magnitude > FAR then
				continue
			end
			local ph = b.bob + clock
			local heave = 0.12 * math.sin(ph * 0.9)
			local pitch = math.rad(0.25) * math.sin(ph * 0.7 + 1.3)
			local roll = math.rad(0.35) * math.sin(ph * 0.55) + math.rad(1.6) * w * b.turnSign
			local cf = CFrame.lookAt(pos, pos + fwd) * CFrame.new(0, heave, 0) * CFrame.Angles(pitch, 0, roll)
			model:PivotTo(cf)
		end
	end
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 3, step)

	return function()
		pcall(function()
			RunService:UnbindFromRenderStep(STEP_NAME)
		end)
		Util.disconnectAll(conns)
		for model, b in boats do
			if model.Parent then
				model:PivotTo(b.original)
			end
		end
		table.clear(boats)
	end
end

return Boats
