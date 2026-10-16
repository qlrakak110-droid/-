--!strict
-- GwangalliBuildingInterior/Kit: 파트 조립 도구. 모든 좌표는 매장 프레임(V.cf) 기준 스터드입니다.
--   매장 프레임: 원점 = 바닥 윗면 가운데, +X = 안쪽(뒷벽)을 보고 섰을 때 오른쪽, +Y = 위,
--   -Z = 뒷벽 쪽, +Z = 입구(거리) 쪽.
-- 파트는 전부 이 클라이언트에만 생기고 Anchored, 충돌·쿼리·터치 없음, 질량 없음 (맵 서버 판정에 영향 없음).
--
-- 두 가지 프레임 규약 (Props · 타입 빌더 공통):
--   * 소품 프레임 pcf: 원점 = 소품 바닥 가운데, +X = 소품의 오른쪽(정면에서 볼 때), +Y = 위,
--     +Z = 소품 정면이 향하는 쪽 (사용자가 서는 쪽). 의자: 앉은 사람이 +Z 를 봄.
--   * 표시면 프레임 dcf: 원점 = 벽·판 표면 위의 점, +X = 보는 사람의 오른쪽, +Y = 위,
--     +Z = 보는 사람 쪽 (표면 바깥). 벽에 붙이는 것 · 글자판 · 액자 · 화면은 전부 dcf 로.
--   V:wall(name, u, y, off) 가 벽의 dcf 를 줍니다 (Scan).
--
-- 막힘 규칙: Kit 는 V.keep (게임플레이용으로 비워 둘 공간: 자동문 앞, 계산대 뒤 직원 자리, 테이블 위,
-- 통로 ...) 과 겹치는 파트를 만들지 않습니다 (ghost 로 남겼다가 끝에 지움). 기존 가구를 정확히 덮어 씌우는
-- 리스킨 · 벽면 마감처럼 의도적으로 그 공간에 들어가야 하면 look.free = true 또는 K:free(fn).
-- 바닥에 세우는 새 소품은 K:spot(lcf, size) 로 자리가 비었는지 먼저 확인하고(기존 가구 · 다른 새 소품 ·
-- keep 전부) 자리를 예약합니다.

local Kit = {}
Kit.__index = Kit

export type Look = {
	c: Color3?,
	m: Enum.Material?,
	t: number?, -- Transparency
	r: number?, -- Reflectance
	shadow: boolean?,
	collide: boolean?, -- 이 클라이언트에서만 충돌 (큰 바닥 가구 · 벽 쪽 진열장에만)
	free: boolean?, -- keep 공간 검사 생략 (리스킨 · 마감 오버레이)
}

local DEFAULT_COLOR = Color3.fromRGB(200, 200, 200)
local PI = math.pi

function Kit.new(V: any, parent: Instance)
	local self = setmetatable({}, Kit)
	self.V = V
	self.cf = V.cf :: CFrame
	self.parent = parent
	self.root = parent
	self.count = 0
	self.blocked = 0
	self.sliceT = os.clock()
	self.slice = 0.0025 -- 프레임당 최대 빌드 시간 (초)
	self.parts = {} :: { BasePart }
	self.ghosts = {} :: { Instance }
	self.lights = {} :: { Light }
	self.prompts = {} :: { ProximityPrompt }
	self.reserved = {} :: { any }
	self.freeDepth = 0
	self.maxParts = V.maxParts or 2600
	-- 디테일 단계: "high" | "mid" | "low" (작은 장식 생략). 의자가 아주 많은 매장은 Common 이 의자만 낮춤
	self.detail = V.detail or (if self.maxParts < 1500 then "low" elseif self.maxParts < 2300 then "mid" else "high")
	self.log = {} :: { string }
	return self
end

-- 시간 분할 양보 (빌드 코루틴 안에서만 호출됨)
function Kit:tick()
	self.count += 1
	if os.clock() - self.sliceT > self.slice then
		task.wait()
		self.sliceT = os.clock()
	end
end

function Kit:note(s: string)
	if #self.log < 60 then
		table.insert(self.log, s)
	end
end

local function apply(p: BasePart, look: any?)
	local l: any = look or {}
	p.Anchored = true
	p.CanCollide = l.collide == true
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
Kit.apply = apply

-- 매장 프레임 기준 축 정렬 상자(lcf, size)의 로컬 AABB
local function laabb(lcf: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size / 2
	local r = lcf
	local ex = math.abs(r.XVector.X) * h.X + math.abs(r.YVector.X) * h.Y + math.abs(r.ZVector.X) * h.Z
	local ey = math.abs(r.XVector.Y) * h.X + math.abs(r.YVector.Y) * h.Y + math.abs(r.ZVector.Y) * h.Z
	local ez = math.abs(r.XVector.Z) * h.X + math.abs(r.YVector.Z) * h.Y + math.abs(r.ZVector.Z) * h.Z
	local p = lcf.Position
	return Vector3.new(p.X - ex, p.Y - ey, p.Z - ez), Vector3.new(p.X + ex, p.Y + ey, p.Z + ez)
end
Kit.laabb = laabb

local function overlap(amin: Vector3, amax: Vector3, bmin: Vector3, bmax: Vector3, eps: number): boolean
	return amin.X < bmax.X - eps and amax.X > bmin.X + eps and amin.Y < bmax.Y - eps and amax.Y > bmin.Y + eps and amin.Z < bmax.Z - eps and amax.Z > bmin.Z + eps
end
Kit.overlap = overlap

-- keep 공간과 겹치나? (겹치는 keep 의 kind 를 돌려줌)
function Kit:hitsKeep(mn: Vector3, mx: Vector3): string?
	for _, k in self.V.keep do
		if overlap(mn, mx, k.min, k.max, 0.04) then
			return k.kind
		end
	end
	return nil
end

-- 바닥 소품 자리 확인 + 예약: lcf = 소품 바닥 가운데, size = 소품 전체 크기 (pad = 둘레 여유).
-- 기존 가구(V.solid) · keep · 이미 예약된 새 소품과 겹치면 false.
function Kit:spot(lcf: CFrame, size: Vector3, pad: number?, kind: string?): boolean
	local c = lcf * CFrame.new(0, size.Y / 2, 0)
	local mn, mx = laabb(c, size + Vector3.new(2 * (pad or 0), 0, 2 * (pad or 0)))
	local V = self.V
	if mn.X < V.x0 - 0.05 or mx.X > V.x1 + 0.05 or mn.Z < V.z0 - 0.05 or mx.Z > V.z1 + 0.05 then
		return false
	end
	if self:hitsKeep(mn, mx) then
		return false
	end
	for _, s in V.solid do
		if overlap(mn, mx, s.min, s.max, 0.04) then
			return false
		end
	end
	for _, r in self.reserved do
		if overlap(mn, mx, r.min, r.max, 0.02) then
			return false
		end
	end
	table.insert(self.reserved, { min = mn, max = mx, kind = kind or "prop" })
	return true
end

-- 이미 정해진 자리를 예약만 (리스킨한 가구 등: 이후 새 소품이 겹치지 않게)
function Kit:reserve(mn: Vector3, mx: Vector3, kind: string?)
	table.insert(self.reserved, { min = mn, max = mx, kind = kind or "prop" })
end

-- fn 안에서 만드는 파트는 keep 검사를 하지 않음 (리스킨 · 마감)
function Kit:free(fn: () -> ())
	self.freeDepth += 1
	local ok, err = pcall(fn)
	self.freeDepth -= 1
	if not ok then
		error(err, 0)
	end
end

-- 하위 모델(그룹) 안에서 만들기: 문짝처럼 통째로 움직일 부품, 상호작용 대상
function Kit:group(name: string, fn: () -> ()): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = self.parent
	local prev = self.parent
	self.parent = m
	local ok, err = pcall(fn)
	self.parent = prev
	if not ok then
		error(err, 0)
	end
	return m
end

-- lcf: 매장 프레임 기준 CFrame. 파트를 만들어 현재 parent 에 넣음 (keep 과 겹치면 ghost)
function Kit:make(class: string, name: string, size: Vector3, lcf: CFrame, look: any?, shape: Enum.PartType?): BasePart
	local p = Instance.new(class) :: BasePart
	if shape then
		(p :: Part).Shape = shape
	end
	p.Name = name
	apply(p, look)
	p.Size = size
	p.CFrame = self.cf * lcf
	local l: any = look or {}
	local ghost = false
	if #self.parts >= self.maxParts then
		ghost = true
	elseif self.freeDepth == 0 and not l.free then
		local mn, mx = laabb(lcf, size)
		local k = self:hitsKeep(mn, mx)
		if k then
			ghost = true
			self.blocked += 1
			if self.blocked <= 8 then
				self:note(string.format("blocked %s by keep %s", name, k))
			end
		end
	end
	if ghost then
		table.insert(self.ghosts, p)
		return p
	end
	p.Parent = self.parent
	table.insert(self.parts, p)
	self:tick()
	return p
end

function Kit:box(name: string, size: Vector3, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, size, lcf, look)
end

-- 쐐기: Roblox WedgePart (뒤 +Z 가 높은 면, 경사는 앞 -Z 아래로)
function Kit:wedge(name: string, size: Vector3, lcf: CFrame, look: any?): BasePart
	return self:make("WedgePart", name, size, lcf, look)
end

-- 원통: 축 = lcf 의 X 축 (Roblox Cylinder 규약). len = 길이, d = 지름
function Kit:cyl(name: string, len: number, d: number, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, Vector3.new(len, d, d), lcf, look, Enum.PartType.Cylinder)
end

-- 세운 원통 (축 = Y): 기둥 · 컵 · 병 · 화분 · 스툴 다리
function Kit:vcyl(name: string, h: number, d: number, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, Vector3.new(h, d, d), lcf * CFrame.Angles(0, 0, PI / 2), look, Enum.PartType.Cylinder)
end

function Kit:ball(name: string, d: number, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, Vector3.new(d, d, d), lcf, look, Enum.PartType.Ball)
end

-- 타원체 (쿠션 · 잎 · 전등갓 · 빵): SpecialMesh Sphere 는 파트 크기에 맞춰 늘어남
function Kit:ell(name: string, size: Vector3, lcf: CFrame, look: any?): BasePart
	local p = self:make("Part", name, size, lcf, look)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- 두 점 a, b (매장 프레임) 사이 원통 (파이프 · 다리 · 프레임 · 전선)
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

-- 두 점 사이 각진 막대 (단면 w x h): 프레임 · 레일 · 몰딩
function Kit:bar(name: string, a: Vector3, b: Vector3, w: number, h: number, look: any?): BasePart?
	local v = b - a
	local len = v.Magnitude
	if len < 1e-3 then
		return nil
	end
	local z = v / len
	local up = if math.abs(z.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local x = up:Cross(z).Unit
	local y = z:Cross(x).Unit
	return self:box(name, Vector3.new(w, h, len), CFrame.fromMatrix((a + b) / 2, x, y, -z), look)
end

-- 원환 (frame 의 XY 평면, 반지름 R, 단면 지름 d, n 조각, a0..a1 라디안)
function Kit:ring(name: string, frame: CFrame, R: number, d: number, n: number, look: any?, a0: number?, a1: number?)
	local s0, s1 = a0 or 0, a1 or PI * 2
	local out = {}
	for i = 0, n - 1 do
		local t0 = s0 + (s1 - s0) * i / n
		local t1 = s0 + (s1 - s0) * (i + 1) / n
		local pa = frame * Vector3.new(math.cos(t0) * R, math.sin(t0) * R, 0)
		local pb = frame * Vector3.new(math.cos(t1) * R, math.sin(t1) * R, 0)
		local p = self:seg(name, pa, pb, d, look, d * 0.42)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

-- 모서리가 둥근 상자 (lcf 의 X 축 방향 4개 모서리를 반지름 r 로): 상자 2개 + 원통 4개
function Kit:rbox(name: string, size: Vector3, r: number, lcf: CFrame, look: any?): { BasePart }
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

-- 위에서 보면 네 모서리가 둥근 수평 판 (상판 · 쟁반 · 매트): 폭 w(X), 길이 len(Z), 두께 t, 모서리 r. lcf = 판 중심
function Kit:slab(name: string, w: number, len: number, t: number, r: number, lcf: CFrame, look: any?): { BasePart }
	return self:rbox(name, Vector3.new(t, w, len), math.min(r, w / 2 - 0.002, len / 2 - 0.002), lcf * CFrame.Angles(0, 0, PI / 2), look)
end

-- 정면에서 보면 네 모서리가 둥근 판 (dcf: +Z = 보는 쪽): 폭 w, 높이 h, 두께 d, 모서리 r. 판은 표면에서 d 만큼 나옴
function Kit:panel(name: string, w: number, h: number, d: number, r: number, dcf: CFrame, look: any?): { BasePart }
	return self:rbox(name, Vector3.new(d, h, w), math.min(r, w / 2 - 0.002, h / 2 - 0.002), dcf * CFrame.new(0, 0, d / 2) * CFrame.Angles(0, -PI / 2, 0), look)
end

-- 세운 원기둥을 위에서 본 원판 (바닥 원판 · 테이블 상판 · 접시): 지름 dia, 두께 t, lcf = 원판 중심
function Kit:disc(name: string, dia: number, t: number, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, Vector3.new(t, dia, dia), lcf * CFrame.Angles(0, 0, PI / 2), look, Enum.PartType.Cylinder)
end

-- 표시면(dcf)에 붙는 얇은 판: 표면에서 d 만큼 나온 w x h 상자 (액자 · 포스터 · 화면 · 타일)
function Kit:plate(name: string, w: number, h: number, d: number, dcf: CFrame, look: any?): BasePart
	return self:box(name, Vector3.new(w, h, d), dcf * CFrame.new(0, 0, d / 2), look)
end

-- 글자판: dcf 표면에 w x h 판 + 글자 (SurfaceGui 하나 + TextLabel 하나 = 임시 스튜디오와 실제 게임이 똑같이 보임).
-- opts: fg (글자색), bg (판 색; nil 이면 판 투명 = 글자만), font (Enum.Font), d (두께), glow (SurfaceGui.Brightness,
--   불빛 간판), look (판 재질 look), align ("Left"|"Center"|"Right"), lines (줄 수 힌트), wrap
-- 여러 줄은 "\n" 으로. 반환: 판 파트, TextLabel
function Kit:text(name: string, w: number, h: number, dcf: CFrame, text: string, opts: any?): (BasePart, TextLabel)
	local o: any = opts or {}
	local d = o.d or 0.04
	local look = table.clone(o.look or {})
	if not o.look then
		look.c = o.bg or Color3.new(1, 1, 1)
		look.t = if o.bg then 0 else 1
	end
	look.free = look.free or o.free
	-- 판의 Front(-Z) 가 보는 사람 쪽 (+Z of dcf)
	local p = self:box(name, Vector3.new(w, h, d), dcf * CFrame.new(0, 0, d / 2) * CFrame.Angles(0, PI, 0), look)
	local g = Instance.new("SurfaceGui")
	g.Name = "Gw" .. name
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = o.ppx or math.clamp(math.floor(220 / math.max(w, h)), 24, 80)
	g.LightInfluence = if o.glow then 0 else 1
	g.Brightness = o.glow or 1
	g.MaxDistance = o.maxDist or 60
	g.ClipsDescendants = true
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = if o.bg and not o.look then 0 else 1
	t.BackgroundColor3 = o.bg or Color3.new(1, 1, 1)
	t.BorderSizePixel = 0
	t.Text = text
	t.TextColor3 = o.fg or Color3.fromRGB(20, 20, 22)
	t.TextScaled = true
	t.TextWrapped = o.wrap == true
	t.Font = o.font or Enum.Font.GothamBold
	t.TextXAlignment = if o.align == "Left" then Enum.TextXAlignment.Left elseif o.align == "Right" then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center
	t.RichText = false
	t.Parent = g
	g.Parent = p
	return p, t
end

-- 불빛: kind = "PointLight" | "SpotLight" | "SurfaceLight". props 는 그대로 대입 (Brightness, Range, Color, Face, Angle).
-- GwangalliIndoorLight 가 실내 조명을 x0.55 로 줄이지 않게 GwIndoorDim = 0 을 먼저 붙임 (R9).
function Kit:light(part: BasePart, kind: string, props: { [string]: any }): Light?
	if part.Parent == nil then
		return nil -- ghost
	end
	if #self.lights >= (self.V.maxLights or 8) then
		return nil
	end
	local l = Instance.new(kind) :: Light
	l:SetAttribute("GwIndoorDim", 0)
	l.Shadows = false
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = part
	table.insert(self.lights, l)
	return l
end

-- 끝: ghost 정리
function Kit:finish()
	for _, g in self.ghosts do
		g:Destroy()
	end
	self.ghosts = {}
end

return Kit
