--!strict
-- GwangalliCarInterior/Kit: 파트 조립 도구. 모든 좌표는 차체 프레임(Underbody) 기준 스터드:
-- +X = 오른쪽, +Y = 위, -Z = 앞 (Roblox 차량 규약). 파트는 전부 클라이언트 로컬, 질량 없음, 충돌·쿼리·터치 없음,
-- Weld 로 차체(또는 회전 피벗)에 붙습니다. 차가 주차 중(Anchored)이면 그대로 서 있고 운전 중이면 같이 움직입니다.
--   box / wedge / cyl / ball / ell(타원체: SpecialMesh Sphere) / seg(두 점 사이 원통) / ring(원환: 원통 n개)
--   rbox(모서리가 둥근 상자) / pivot(회전 피벗: 핸들) / slats(송풍구 날개)

local Kit = {}
Kit.__index = Kit

-- look = { c: Color3?, m: Enum.Material?, t: number? (Transparency), r: number? (Reflectance), shadow: boolean? }

local DEFAULT_COLOR = Color3.fromRGB(30, 30, 32)

function Kit.new(base: BasePart, parent: Instance)
	local self = setmetatable({}, Kit)
	self.base = base
	self.parent = parent
	self.count = 0
	self.budget = 70 -- 프레임당 생성 수 (그 이상이면 다음 프레임으로 양보)
	self.attach = base -- 지금 붙일 대상 (pivot 안에서 만들 때 바뀜)
	self.attachCF = CFrame.new() -- attach 의 차체 기준 CFrame
	self.parts = {} :: { BasePart }
	return self
end

-- 프레임 양보 (빌드 코루틴 안에서만)
function Kit:tick()
	self.count += 1
	if self.count % self.budget == 0 then
		task.wait()
	end
end

local function apply(p: BasePart, look: any?)
	local l: any = look or {}
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = l.shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = l.c or DEFAULT_COLOR
	p.Material = l.m or Enum.Material.SmoothPlastic
	p.Transparency = l.t or 0
	p.Reflectance = l.r or 0
end

-- lcf: 차체 기준 CFrame. 파트를 만들고 현재 attach 에 용접.
function Kit:make(class: string, name: string, size: Vector3, lcf: CFrame, look: any?, shape: Enum.PartType?): BasePart
	local p = Instance.new(class) :: BasePart
	if shape then
		(p :: Part).Shape = shape
	end
	p.Name = name
	apply(p, look)
	p.Size = size
	p.CFrame = self.base.CFrame * lcf
	local w = Instance.new("Weld")
	w.Name = "CabinWeld"
	w.Part0 = self.attach
	w.Part1 = p
	w.C0 = self.attachCF:Inverse() * lcf
	w.C1 = CFrame.new()
	w.Parent = p
	p.Parent = self.parent
	table.insert(self.parts, p)
	self:tick()
	return p
end

function Kit:box(name: string, size: Vector3, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, size, lcf, look)
end

function Kit:wedge(name: string, size: Vector3, lcf: CFrame, look: any?): BasePart
	return self:make("WedgePart", name, size, lcf, look)
end

-- 원통: 축 = lcf 의 X 축 (Roblox Cylinder 규약). len = 길이, d = 지름
function Kit:cyl(name: string, len: number, d: number, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, Vector3.new(len, d, d), lcf, look, Enum.PartType.Cylinder)
end

function Kit:ball(name: string, d: number, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, Vector3.new(d, d, d), lcf, look, Enum.PartType.Ball)
end

-- 타원체 (쿠션·볼스터·헤드레스트·에어백 커버): SpecialMesh Sphere 는 파트 크기에 맞춰 늘어납니다
function Kit:ell(name: string, size: Vector3, lcf: CFrame, look: any?): BasePart
	local p = self:make("Part", name, size, lcf, look)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- 두 점 a, b (차체 기준) 사이 원통
function Kit:seg(name: string, a: Vector3, b: Vector3, d: number, look: any?, extra: number?): BasePart?
	local v = b - a
	local len = v.Magnitude
	if len < 1e-3 then
		return nil
	end
	local mid = (a + b) / 2
	local x = v / len
	local up = if math.abs(x.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	return self:cyl(name, len + (extra or 0), d, CFrame.fromMatrix(mid, x, y, z), look)
end

-- 원환 (핸들 림·송풍구 테두리·스피커 링): frame 의 XY 평면, 반지름 R, 단면 지름 d, n 조각, a0..a1 (라디안)
function Kit:ring(name: string, frame: CFrame, R: number, d: number, n: number, look: any?, a0: number?, a1: number?, fat: ((number) -> number)?)
	local s0, s1 = a0 or 0, a1 or math.pi * 2
	local full = math.abs((s1 - s0) - math.pi * 2) < 1e-3
	local out = {}
	for i = 0, n - 1 do
		local t0 = s0 + (s1 - s0) * i / n
		local t1 = s0 + (s1 - s0) * (i + 1) / n
		local pa = frame * Vector3.new(math.cos(t0) * R, math.sin(t0) * R, 0)
		local pb = frame * Vector3.new(math.cos(t1) * R, math.sin(t1) * R, 0)
		local dd = if fat then d * fat((t0 + t1) / 2) else d
		local p = self:seg(name, pa, pb, dd, look, dd * 0.42)
		if p then
			table.insert(out, p)
		end
	end
	if not full then
		-- 열린 호의 끝은 둥글게
		self:ball(name, d, CFrame.new(frame * Vector3.new(math.cos(s0) * R, math.sin(s0) * R, 0)), look)
		self:ball(name, d, CFrame.new(frame * Vector3.new(math.cos(s1) * R, math.sin(s1) * R, 0)), look)
	end
	return out
end

-- 모서리가 둥근 상자 (lcf 의 X 축 방향 4개 모서리를 반지름 r 로): 상자 2개 + 원통 4개
function Kit:rbox(name: string, size: Vector3, r: number, lcf: CFrame, look: any?)
	r = math.min(r, size.Y / 2 - 1e-3, size.Z / 2 - 1e-3)
	if r <= 0.01 then
		return { self:box(name, size, lcf, look) }
	end
	local out = {}
	table.insert(out, self:box(name, Vector3.new(size.X, size.Y - 2 * r, size.Z), lcf, look))
	table.insert(out, self:box(name, Vector3.new(size.X, size.Y, size.Z - 2 * r), lcf, look))
	for _, sy in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(out, self:cyl(name, size.X, 2 * r, lcf * CFrame.new(0, sy * (size.Y / 2 - r), sz * (size.Z / 2 - r)), look))
		end
	end
	return out
end

-- 회전 피벗: 이후 fn 안에서 만든 파트는 피벗에 붙습니다 (핸들처럼 통째로 돌릴 부품)
function Kit:pivot(name: string, lcf: CFrame, fn: () -> ()): (BasePart, Weld)
	local p = Instance.new("Part")
	p.Name = name
	apply(p, { t = 1 })
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	p.CFrame = self.base.CFrame * lcf
	local w = Instance.new("Weld")
	w.Name = "PivotWeld"
	w.Part0 = self.base
	w.Part1 = p
	w.C0 = lcf
	w.Parent = p
	p.Parent = self.parent
	local prevA, prevCF = self.attach, self.attachCF
	self.attach, self.attachCF = p, lcf
	fn()
	self.attach, self.attachCF = prevA, prevCF
	return p, w
end

-- 송풍구: frame 중심, 폭 w, 높이 h; 테두리(크롬) + 안쪽 어두운 덕트 + 가로 날개 n 개 + 조절 노브
function Kit:vent(name: string, frame: CFrame, w: number, h: number, look: any, n: number?)
	local th = 0.035
	self:box(name .. "Duct", Vector3.new(w, h, 0.08), frame * CFrame.new(0, 0, -0.03), look.duct)
	self:box(name .. "Rim", Vector3.new(w + 2 * th, th, 0.06), frame * CFrame.new(0, h / 2 + th / 2, 0), look.frame)
	self:box(name .. "Rim", Vector3.new(w + 2 * th, th, 0.06), frame * CFrame.new(0, -h / 2 - th / 2, 0), look.frame)
	self:box(name .. "Rim", Vector3.new(th, h, 0.06), frame * CFrame.new(w / 2 + th / 2, 0, 0), look.frame)
	self:box(name .. "Rim", Vector3.new(th, h, 0.06), frame * CFrame.new(-w / 2 - th / 2, 0, 0), look.frame)
	local k = n or 4
	for i = 1, k do
		local y = -h / 2 + h * (i - 0.5) / k
		self:box(name .. "Slat", Vector3.new(w - 0.02, 0.022, 0.07), frame * CFrame.new(0, y, 0.005) * CFrame.Angles(math.rad(-12), 0, 0), look.slat)
	end
	self:box(name .. "Knob", Vector3.new(0.07, 0.05, 0.05), frame * CFrame.new(0, 0, 0.04), look.knob)
end

return Kit
