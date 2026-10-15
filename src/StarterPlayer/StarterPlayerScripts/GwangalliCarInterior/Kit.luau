--!strict
-- GwangalliCarInterior/Kit: 파트 조립 도구. 모든 좌표는 차체 프레임(Underbody) 기준 스터드:
-- +X = 오른쪽, +Y = 위, -Z = 앞 (Roblox 차량 규약). 파트는 전부 클라이언트 로컬, 질량 없음, 충돌·쿼리·터치 없음.
-- 두 가지 방식: anchored = true (주차된 차: 파트를 고정만 하고 용접 없음 -> 가장 가벼움) / false (움직이는 차:
-- 차체에 Weld). 회전하는 핸들은 피벗 파트에 붙고, 피벗만 움직이면 됩니다.
--   box / wedge / cyl / ball / ell(타원체: SpecialMesh Sphere) / seg(두 점 사이 원통) / ring(원환: 원통 n개)
--   rbox(모서리가 둥근 상자) / pivot(회전 피벗: 핸들) / slats(송풍구 날개)

local Kit = {}
Kit.__index = Kit

-- look = { c: Color3?, m: Enum.Material?, t: number? (Transparency), r: number? (Reflectance), shadow: boolean? }

local DEFAULT_COLOR = Color3.fromRGB(30, 30, 32)

function Kit.new(base: BasePart, parent: Instance, anchored: boolean?)
	local self = setmetatable({}, Kit)
	self.base = base
	self.anchored = anchored == true
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
	if self.anchored and self.attach == self.base then
		p.Anchored = true
	else
		local w = Instance.new("Weld")
		w.Name = "CabinWeld"
		w.Part0 = self.attach
		w.Part1 = p
		w.C0 = self.attachCF:Inverse() * lcf
		w.C1 = CFrame.new()
		w.Parent = p
	end
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

-- 앞에서 보면 네 모서리가 둥근 판 (보는 방향 = cf 의 +Z): 폭 w, 높이 h, 두께 d, 모서리 반지름 r
-- (화면 베젤 · 송풍구 테두리 · 센터 스택 · 공조 패널 · 페달)
function Kit:panel(name: string, w: number, h: number, d: number, r: number, cf: CFrame, look: any?)
	return self:rbox(name, Vector3.new(d, h, w), math.min(r, w / 2 - 0.002, h / 2 - 0.002), cf * CFrame.Angles(0, -math.pi / 2, 0), look)
end

-- 위에서 보면 네 모서리가 둥근 판 (수평 판: 콘솔 상판 · 충전 패드 · 트레이): 폭 w(X), 길이 len(Z), 두께 t
function Kit:slab(name: string, w: number, len: number, t: number, r: number, cf: CFrame, look: any?)
	return self:rbox(name, Vector3.new(t, w, len), math.min(r, w / 2 - 0.002, len / 2 - 0.002), cf * CFrame.Angles(0, 0, math.pi / 2), look)
end

-- 길이 방향(Z)으로 긴 상자의 긴 모서리 4개를 둥글게 (콘솔 몸체 · 도어 패널 · 팔걸이)
function Kit:zbox(name: string, size: Vector3, r: number, cf: CFrame, look: any?)
	return self:rbox(name, Vector3.new(size.Z, size.Y, size.X), r, cf * CFrame.Angles(0, math.pi / 2, 0), look)
end

-- 캡슐 (두 점 사이 원통 + 양끝 공): 손잡이 · 레버 · 크롬 라인 끝
function Kit:capsule(name: string, a: Vector3, b: Vector3, d: number, look: any?)
	self:seg(name, a, b, d, look)
	self:ball(name, d, CFrame.new(a), look)
	self:ball(name, d, CFrame.new(b), look)
end

-- 회전 피벗: 이후 fn 안에서 만든 파트는 피벗에 붙습니다 (핸들처럼 통째로 돌릴 부품).
-- 반환: 피벗, 차체와의 Weld (고정 방식이면 nil: 피벗 CFrame 을 직접 바꿉니다)
function Kit:pivot(name: string, lcf: CFrame, fn: () -> ()): (BasePart, Weld?)
	local p = Instance.new("Part")
	p.Name = name
	apply(p, { t = 1 })
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	p.CFrame = self.base.CFrame * lcf
	local w: Weld? = nil
	if self.anchored then
		p.Anchored = true
	else
		local wl = Instance.new("Weld")
		wl.Name = "PivotWeld"
		wl.Part0 = self.base
		wl.Part1 = p
		wl.C0 = lcf
		wl.Parent = p
		w = wl
	end
	p.Parent = self.parent
	local prevA, prevCF = self.attach, self.attachCF
	self.attach, self.attachCF = p, lcf
	fn()
	self.attach, self.attachCF = prevA, prevCF
	return p, w
end

-- 송풍구: frame 중심, 폭 w, 높이 h; 모서리가 둥근 테두리(크롬) + 둥근 안쪽 덕트 + 가로 날개 n 개 + 조절 노브
function Kit:vent(name: string, frame: CFrame, w: number, h: number, look: any, n: number?)
	local th = 0.035
	local r = math.min(w, h) * 0.38
	self:panel(name .. "Rim", w + 2 * th, h + 2 * th, 0.05, r + th, frame * CFrame.new(0, 0, -0.01), look.frame)
	self:panel(name .. "Duct", w, h, 0.05, r, frame * CFrame.new(0, 0, 0.0), look.duct)
	local k = n or 4
	for i = 1, k do
		local y = -h / 2 + h * (i - 0.5) / k
		-- 둥근 덕트 안에 들어가도록 위아래 날개는 짧게
		local edge = math.abs(y) / (h / 2)
		local sw = (w - 0.03) * (if edge > 0.6 then 1 - (edge - 0.6) * 0.6 else 1)
		self:cyl(name .. "Slat", sw, 0.024, frame * CFrame.new(0, y, 0.03), look.slat)
	end
	self:cyl(name .. "Knob", 0.07, 0.045, frame * CFrame.new(0, 0, 0.05), look.knob)
end

return Kit
