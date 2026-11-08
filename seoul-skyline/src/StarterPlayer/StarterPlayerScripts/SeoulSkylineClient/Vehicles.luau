--!strict
-- SeoulSkylineClient / Vehicles — 실측 절차적 차량 빌더 (클라이언트 전용, 실제 브랜드 로고·이름 없음)
--
--   한국 도로 차종 구성: 중형 세단 · 소형 해치백 · 소형 SUV · 대형 SUV · 미니밴 · 택시(꽃담황토/흰색, 지붕 표시등·빈차등)
--   · 시내버스(간선 파랑/지선 초록/광역 빨강, LED 노선 표시) · 1톤 화물(포터형 캡 + 적재함) · 1톤 탑차.
--   치수는 실측(m) → stud(1 stud = 0.3 m). 모델 원점 = 앞뒤 차축 중간의 노면, 진행 방향 = −Z(LookVector), 오른쪽 = +X.
--
--   * 차종마다 템플릿 Model 을 한 번만 만들고(:Clone) 인스턴스를 찍어냄. 인스턴스는 parts/offs(원점 기준 CFrame)를
--     가지고 있어 호출자가 carCF * offs[j] 로 BulkMoveTo 할 수 있음.
--   * LOD: full(≈30~45 파트: 차체·보닛/트렁크 쐐기·유리·필러·바퀴·휠하우스·그릴·등화·번호판·미러·도어 이음선)
--          lite(≈8~12 파트: 실루엣·바퀴·전조등/후미등 띠) — 중거리용.
--   * 이음선·몰딩은 "관통 슬래브"(차체를 가로지르는 얇은 판, 양쪽 옆면에서 ≥ 0.05 stud 돌출) → 파트 하나로 양쪽 표현,
--     z-fighting 없음. 바퀴도 차축 하나에 타이어 원기둥 1 + 림 원기둥 1(타이어보다 양쪽 0.02 m 돌출).
--   * 모든 파트: Anchored, CanCollide/CanQuery/CanTouch false, CastShadow 는 차체 큰 면만.

local Vehicles = {}

local MPS = 0.3 -- m / stud
local function S(m: number): number
	return m / MPS
end

local rgb = Color3.fromRGB
local MAT = Enum.Material

------------------------------------------------------------------------------------------------------
-- 색 · 재질
------------------------------------------------------------------------------------------------------
local C = {
	glass = rgb(16, 20, 26),
	glassLite = rgb(26, 30, 38),
	trim = rgb(22, 23, 26),
	seam = rgb(12, 12, 14),
	tyre = rgb(26, 26, 28),
	rim = rgb(132, 135, 140),
	rimDark = rgb(58, 60, 64),
	well = rgb(10, 10, 11),
	under = rgb(6, 6, 7),
	grille = rgb(30, 31, 34),
	headOn = rgb(255, 246, 228),
	headOff = rgb(196, 202, 210),
	drl = rgb(232, 242, 255),
	tailRun = rgb(196, 20, 16),
	tailBrake = rgb(255, 44, 32),
	tailOff = rgb(104, 14, 16),
	plateWhite = rgb(240, 240, 236),
	plateYellow = rgb(244, 196, 40),
	plateBlue = rgb(70, 140, 214),
	chrome = rgb(150, 154, 160),
	taxiSign = rgb(255, 236, 170),
	vacancy = rgb(255, 40, 30),
	busRoof = rgb(232, 234, 236),
	busSkirt = rgb(60, 62, 66),
	bed = rgb(150, 154, 158),
	bedDark = rgb(48, 50, 54),
	ledAmber = rgb(255, 170, 40),
	ledGreen = rgb(120, 255, 120),
}
Vehicles.Colors = C

-- 한국 차량 색 분포: 흰/펄 35 %, 회색/은색 25 %, 검정 20 %, 나머지 파랑/빨강/갈색/초록/베이지
local PAINTS: { { w: number, c: Color3 } } = {
	{ w = 22, c = rgb(236, 236, 234) }, -- 퓨어 화이트
	{ w = 13, c = rgb(226, 223, 214) }, -- 펄 화이트
	{ w = 12, c = rgb(178, 182, 186) }, -- 실버
	{ w = 8, c = rgb(112, 116, 120) }, -- 그레이
	{ w = 5, c = rgb(80, 84, 88) }, -- 다크 그레이
	{ w = 20, c = rgb(20, 21, 24) }, -- 블랙
	{ w = 6, c = rgb(26, 44, 86) }, -- 딥 블루
	{ w = 4, c = rgb(126, 20, 24) }, -- 레드
	{ w = 4, c = rgb(86, 62, 48) }, -- 브라운
	{ w = 3, c = rgb(42, 66, 56) }, -- 다크 그린
	{ w = 3, c = rgb(176, 160, 132) }, -- 베이지 골드
}
local PAINT_TOTAL = 0
for _, p in PAINTS do
	PAINT_TOTAL += p.w
end

local TAXI_ORANGE = rgb(226, 120, 54) -- 서울 택시 꽃담황토색
local BUS = {
	{ kind = "blue", body = rgb(30, 92, 190), routes = { "301", "302", "303", "340", "341", "360", "362", "370" }, dest = "잠실역" },
	{ kind = "green", body = rgb(62, 168, 64), routes = { "3313", "3314", "3216", "3412", "3214", "3411" }, dest = "잠실새내역" },
	{ kind = "red", body = rgb(210, 36, 40), routes = { "1100", "1700", "2000", "9403", "1009", "1650" }, dest = "서울역" },
}
local TRUCK_CABS = { rgb(236, 236, 234), rgb(236, 236, 234), rgb(236, 236, 234), rgb(38, 78, 160), rgb(38, 78, 160), rgb(178, 182, 186) }
local TARPS = { rgb(40, 82, 150), rgb(46, 92, 64), rgb(120, 122, 126), rgb(180, 150, 90) }

local HANGUL_PRIVATE = { "가", "나", "다", "라", "마", "거", "너", "더", "러", "머", "버", "서", "어", "저", "고", "노", "도", "로", "모", "보", "소", "오", "조", "구", "누", "두", "루", "무", "부", "수", "우", "주", "하", "허", "호" }
local HANGUL_BIZ = { "바", "사", "아", "자" }

------------------------------------------------------------------------------------------------------
-- 차종 사양 (m). 승용차는 공통 빌더(buildCar) 매개변수.
------------------------------------------------------------------------------------------------------
export type CarSpec = {
	L: number, W: number, H: number, wb: number, fo: number,
	r: number, rimR: number, tw: number, track: number,
	sill: number, archGap: number, hoodF: number, cowl: number, belt: number, nx: number, nz: number,
	hoodZ1: number, roofZ0: number, roofZ1: number, rearZ: number,
	ghW: number, roofW: number, roofT: number, rails: boolean,
	fbb: number, rbb: number,
	head: { number }, drl: { number }?, tail: { number }, tailBar: { number }?,
	grille: { number }, plateFY: number, plateRY: number,
	zB: number, cSlab: number?, seams: { { number } }, handles: { number },
	spoiler: boolean?, rocker: boolean?, slider: { number }?, darkRims: boolean?,
}

local SPECS: { [string]: CarSpec } = {
	-- 중형 세단 4.90 x 1.86 x 1.47 (휠베이스 2.85, 타이어 Ø0.67)
	sedan = {
		L = 4.90, W = 1.86, H = 1.47, wb = 2.85, fo = 0.96,
		r = 0.335, rimR = 0.23, tw = 0.225, track = 1.60,
		sill = 0.17, archGap = 0.06, hoodF = 0.78, cowl = 0.955, belt = 0.99, nx = 0.15, nz = 0.13,
		hoodZ1 = 1.50, roofZ0 = 2.38, roofZ1 = 3.42, rearZ = 4.16,
		ghW = 0.77, roofW = 0.725, roofT = 0.06, rails = false,
		fbb = 0.22, rbb = 0.28,
		head = { 0.50, 0.835, 0.645, 0.745 }, drl = { 0.80, 0.752, 0.772 }, tail = { 0.56, 0.885, 0.86, 0.965 }, tailBar = { 0.58, 0.905, 0.935 },
		grille = { 0.42, 0.30, 0.66 }, plateFY = 0.42, plateRY = 0.64,
		zB = 2.84, seams = { { 1.53, 0 }, { 2.84, 0 } }, handles = {},
	},
	-- 소형 해치백 4.00 x 1.75 x 1.48
	compact = {
		L = 4.00, W = 1.75, H = 1.48, wb = 2.58, fo = 0.80,
		r = 0.315, rimR = 0.205, tw = 0.205, track = 1.53,
		sill = 0.16, archGap = 0.06, hoodF = 0.77, cowl = 0.945, belt = 0.98, nx = 0.14, nz = 0.12,
		hoodZ1 = 1.24, roofZ0 = 2.06, roofZ1 = 3.30, rearZ = 3.83,
		ghW = 0.72, roofW = 0.675, roofT = 0.06, rails = false,
		fbb = 0.22, rbb = 0.30,
		head = { 0.44, 0.79, 0.655, 0.755 }, drl = nil, tail = { 0.56, 0.84, 0.82, 0.965 }, tailBar = nil,
		grille = { 0.38, 0.28, 0.62 }, plateFY = 0.42, plateRY = 0.62,
		zB = 2.62, seams = { { 1.27, 0 }, { 2.62, 0 } }, handles = {},
		spoiler = true,
	},
	-- 소형 SUV 4.40 x 1.85 x 1.65 (루프레일 포함)
	suv = {
		L = 4.40, W = 1.85, H = 1.65, wb = 2.70, fo = 0.88,
		r = 0.36, rimR = 0.235, tw = 0.235, track = 1.61,
		sill = 0.26, archGap = 0.07, hoodF = 0.88, cowl = 1.035, belt = 1.07, nx = 0.15, nz = 0.13,
		hoodZ1 = 1.42, roofZ0 = 2.20, roofZ1 = 3.80, rearZ = 4.20,
		ghW = 0.76, roofW = 0.72, roofT = 0.06, rails = true,
		fbb = 0.30, rbb = 0.36,
		head = { 0.50, 0.835, 0.745, 0.815 }, drl = { 0.82, 0.83, 0.855 }, tail = { 0.56, 0.885, 0.92, 1.045 }, tailBar = { 0.60, 0.965, 0.995 },
		grille = { 0.48, 0.36, 0.80 }, plateFY = 0.48, plateRY = 0.70,
		zB = 2.96, cSlab = 3.56, seams = { { 1.45, 0 }, { 2.96, 0 } }, handles = {},
	},
	-- 대형 SUV 4.90 x 1.95 x 1.75
	suvL = {
		L = 4.90, W = 1.95, H = 1.75, wb = 2.90, fo = 0.92,
		r = 0.375, rimR = 0.25, tw = 0.245, track = 1.69,
		sill = 0.27, archGap = 0.07, hoodF = 0.96, cowl = 1.115, belt = 1.15, nx = 0.15, nz = 0.13,
		hoodZ1 = 1.48, roofZ0 = 2.28, roofZ1 = 4.38, rearZ = 4.70,
		ghW = 0.81, roofW = 0.77, roofT = 0.06, rails = true,
		fbb = 0.32, rbb = 0.38,
		head = { 0.55, 0.88, 0.80, 0.885 }, drl = { 0.86, 0.905, 0.93 }, tail = { 0.62, 0.935, 0.98, 1.125 }, tailBar = { 0.66, 1.04, 1.07 },
		grille = { 0.56, 0.38, 0.88 }, plateFY = 0.50, plateRY = 0.76,
		zB = 3.10, cSlab = 3.98, seams = { { 1.51, 0 }, { 3.10, 0 } }, handles = {},
		rocker = true, darkRims = true,
	},
	-- 미니밴 5.15 x 2.00 x 1.74 (슬라이딩 도어 레일)
	minivan = {
		L = 5.15, W = 2.00, H = 1.74, wb = 3.09, fo = 0.98,
		r = 0.37, rimR = 0.24, tw = 0.235, track = 1.74,
		sill = 0.20, archGap = 0.06, hoodF = 0.90, cowl = 1.035, belt = 1.06, nx = 0.16, nz = 0.13,
		hoodZ1 = 1.30, roofZ0 = 2.18, roofZ1 = 4.72, rearZ = 5.00,
		ghW = 0.84, roofW = 0.80, roofT = 0.06, rails = false,
		fbb = 0.24, rbb = 0.32,
		head = { 0.52, 0.90, 0.745, 0.845 }, drl = { 0.90, 0.855, 0.88 }, tail = { 0.64, 0.965, 0.87, 1.04 }, tailBar = { 0.66, 0.965, 0.995 },
		grille = { 0.56, 0.30, 0.74 }, plateFY = 0.44, plateRY = 0.72,
		zB = 2.62, cSlab = 3.72, seams = { { 1.34, 0 }, { 2.62, 0 } }, handles = {},
		slider = { 3.72, 4.80 },
	},
}
SPECS.taxi = SPECS.sedan

------------------------------------------------------------------------------------------------------
-- 차종 정보 (Traffic/ParkedCars 용, stud): 길이·폭·원점→앞/뒤 범퍼·휠베이스·등화 위치·혼합 비율·속도 계수
------------------------------------------------------------------------------------------------------
export type Info = {
	name: string,
	length: number,
	width: number,
	height: number,
	wheelbase: number,
	front: number, -- 원점 → 앞 범퍼 (stud)
	rear: number, -- 원점 → 뒤 범퍼 (stud)
	headY: number,
	tailY: number,
	lampHalf: number, -- 좌우 등 간격 / 2
	weight: number, -- 일반 차로 혼합 비율
	weightOuter: number, -- 바깥(끝) 차로 혼합 비율
	speed: number, -- 희망 속도 계수
	heavy: boolean,
}

Vehicles.TYPES = { "sedan", "compact", "suv", "suvL", "minivan", "taxi", "bus", "truck", "truckBox" }
Vehicles.Info = {} :: { [string]: Info }

local function info(name: string, L: number, W: number, H: number, wb: number, fo: number, headY: number, tailY: number, lampHalf: number, weight: number, weightOuter: number, speed: number, heavy: boolean)
	Vehicles.Info[name] = {
		name = name,
		length = S(L),
		width = S(W),
		height = S(H),
		wheelbase = S(wb),
		front = S(fo + wb / 2),
		rear = S(L - fo - wb / 2),
		headY = S(headY),
		tailY = S(tailY),
		lampHalf = S(lampHalf),
		weight = weight,
		weightOuter = weightOuter,
		speed = speed,
		heavy = heavy,
	}
end
-- 서울 저녁 도로: 택시 많음, 버스·화물은 바깥 차로 위주
info("sedan", 4.90, 1.86, 1.47, 2.85, 0.96, 0.70, 0.91, 0.67, 31, 25, 1.0, false)
info("compact", 4.00, 1.75, 1.48, 2.58, 0.80, 0.70, 0.89, 0.62, 9, 8, 0.98, false)
info("suv", 4.40, 1.85, 1.65, 2.70, 0.88, 0.78, 0.98, 0.67, 19, 16, 1.0, false)
info("suvL", 4.90, 1.95, 1.75, 2.90, 0.92, 0.84, 1.05, 0.72, 11, 9, 1.0, false)
info("minivan", 4.90 + 0.25, 2.00, 1.74, 3.09, 0.98, 0.79, 0.95, 0.71, 8, 7, 0.99, false)
info("taxi", 4.90, 1.86, 1.47, 2.85, 0.96, 0.70, 0.91, 0.67, 16, 13, 1.04, false)
info("bus", 11.0, 2.49, 3.20, 5.85, 2.55, 0.65, 1.10, 0.93, 0, 11, 0.9, true)
info("truck", 5.10, 1.74, 1.97, 2.64, 1.06, 0.86, 0.62, 0.70, 3, 7, 0.93, true)
info("truckBox", 5.10, 1.74, 2.55, 2.64, 1.06, 0.86, 0.62, 0.70, 2, 4, 0.93, true)

------------------------------------------------------------------------------------------------------
-- 파트 팩토리 (미터 공간 → stud)
------------------------------------------------------------------------------------------------------
type Ctx = { model: Model, zc: number, n: number }

local function newPart(ctx: Ctx, kind: string, role: string, size: Vector3, pos: Vector3, rot: CFrame?, color: Color3, mat: Enum.Material?, shadow: boolean?): BasePart
	local p: BasePart
	if kind == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local q = Instance.new("Part")
		if kind == "Cyl" then
			q.Shape = Enum.PartType.Cylinder
		end
		p = q
	end
	p.Name = role
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = mat or MAT.SmoothPlastic
	p.Color = color
	p.Size = Vector3.new(math.max(S(size.X), 0.02), math.max(S(size.Y), 0.02), math.max(S(size.Z), 0.02))
	local cf = CFrame.new(pos.X / MPS, pos.Y / MPS, pos.Z / MPS)
	if rot then
		cf *= rot
	end
	p.CFrame = cf
	ctx.n += 1
	p.Parent = ctx.model
	return p
end

-- 축 정렬 상자: x0..x1, y0..y1, z0..z1 (z = 앞 범퍼에서 뒤로 m)
local function box(ctx: Ctx, role: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, mat: Enum.Material?, shadow: boolean?): BasePart
	return newPart(ctx, "Block", role, Vector3.new(x1 - x0, y1 - y0, z1 - z0), Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2 - ctx.zc), nil, color, mat, shadow)
end
local function sbox(ctx: Ctx, role: string, hw: number, y0: number, y1: number, z0: number, z1: number, color: Color3, mat: Enum.Material?, shadow: boolean?): BasePart
	return box(ctx, role, -hw, hw, y0, y1, z0, z1, color, mat, shadow)
end
-- 좌우 대칭 한 쌍 (xi..xo 는 양수, 안쪽 → 바깥)
local function pair(ctx: Ctx, role: string, xi: number, xo: number, y0: number, y1: number, z0: number, z1: number, color: Color3, mat: Enum.Material?)
	box(ctx, role, xi, xo, y0, y1, z0, z1, color, mat)
	box(ctx, role, -xo, -xi, y0, y1, z0, z1, color, mat)
end
-- 쐐기: 경사면이 앞·위를 봄(높은 쪽 = 뒤 z1)
local function wedgeF(ctx: Ctx, role: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, mat: Enum.Material?, shadow: boolean?): BasePart
	return newPart(ctx, "Wedge", role, Vector3.new(x1 - x0, y1 - y0, z1 - z0), Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2 - ctx.zc), nil, color, mat, shadow)
end
-- 쐐기: 경사면이 뒤·위를 봄(높은 쪽 = 앞 z0)
local FLIP = CFrame.Angles(0, math.pi, 0)
local function wedgeB(ctx: Ctx, role: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, mat: Enum.Material?, shadow: boolean?): BasePart
	return newPart(ctx, "Wedge", role, Vector3.new(x1 - x0, y1 - y0, z1 - z0), Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2 - ctx.zc), FLIP, color, mat, shadow)
end
-- 평면 모서리 깎기(수직 쐐기): ox = ±1 (좌/우), oz = −1 앞 / +1 뒤. 직각 꼭짓점은 차체 안쪽.
local function chamfer(ctx: Ctx, role: string, ox: number, oz: number, xi: number, xo: number, y0: number, y1: number, z0: number, z1: number, color: Color3, mat: Enum.Material?)
	local ly = Vector3.new(ox, 0, 0)
	local lz = Vector3.new(0, 0, -oz)
	local lx = ly:Cross(lz)
	local rot = CFrame.fromMatrix(Vector3.zero, lx, ly, lz)
	newPart(ctx, "Wedge", role, Vector3.new(y1 - y0, xo - xi, z1 - z0), Vector3.new(ox * (xi + xo) / 2, (y0 + y1) / 2, (z0 + z1) / 2 - ctx.zc), rot, color, mat)
end
-- 경사 띠(필러): (ya, za) → (yb, zb) 를 따라 x = xc, 두께 tx(x) · tn(경사면 법선, 바깥쪽으로)
local function strip(ctx: Ctx, role: string, xc: number, ya: number, za: number, yb: number, zb: number, tx: number, tn: number, color: Color3, mat: Enum.Material?)
	local a = Vector3.new(xc, ya, za - ctx.zc)
	local b = Vector3.new(xc, yb, zb - ctx.zc)
	local d = b - a
	local fwd = d.Unit
	local up = Vector3.xAxis:Cross(fwd)
	if up.Y < 0 then
		up = -up
	end
	local c = (a + b) / 2 + up * (tn / 2)
	local rot = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, up, Vector3.xAxis:Cross(up))
	newPart(ctx, "Block", role, Vector3.new(tx, tn, d.Magnitude), c, rot, color, mat)
end
-- X 축 원기둥(차축 관통: 타이어/림)
local function axle(ctx: Ctx, role: string, length: number, radius: number, y: number, z: number, color: Color3, mat: Enum.Material?): BasePart
	return newPart(ctx, "Cyl", role, Vector3.new(length, radius * 2, radius * 2), Vector3.new(0, y, z - ctx.zc), nil, color, mat)
end

-- 번호판 (흰 판 + SurfaceGui 글자). face: Front(-Z) | Back(+Z)
local function plate(ctx: Ctx, role: string, y: number, z0: number, z1: number, face: Enum.NormalId, w: number?, h: number?)
	local pw, ph = w or 0.52, h or 0.11
	local p = box(ctx, role, -pw / 2, pw / 2, y - ph / 2, y + ph / 2, z0, z1, C.plateWhite)
	local g = Instance.new("SurfaceGui")
	g.Name = "PlateGui"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 64
	g.LightInfluence = 1
	g.MaxDistance = 110
	g.ZOffset = 0
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 1, 0)
	t.Position = UDim2.new(0, 0, 0, 0)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = rgb(16, 16, 18)
	t.Text = "12가 3456"
	t.Parent = g
	g.Parent = p
end

-- 발광 표시판(LED 노선 표시·택시 표시등): 검정/색 판 + SurfaceGui (LightInfluence 0 = 자체 발광)
local function sign(part: BasePart, face: Enum.NormalId, text: string, fg: Color3, bg: Color3, name: string, maxDist: number)
	local g = Instance.new("SurfaceGui")
	g.Name = name
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.Brightness = 1.6
	g.MaxDistance = maxDist
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundColor3 = bg
	t.BackgroundTransparency = 0
	t.BorderSizePixel = 0
	t.Size = UDim2.new(1, 0, 1, 0)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = fg
	t.Text = text
	t.Parent = g
	g.Parent = part
end

------------------------------------------------------------------------------------------------------
-- 승용차 공통 빌더
------------------------------------------------------------------------------------------------------
local function buildCar(ctx: Ctx, P: CarSpec, lite: boolean, taxi: boolean)
	local hw = P.W / 2
	local L = P.L
	local zf, zr = P.fo, P.fo + P.wb
	local aT = 2 * P.r + P.archGap -- 휠아치 윗면
	local aH = P.r + 0.075 -- 휠아치 반길이
	local paint = rgb(236, 236, 234)
	local roofTop = if P.rails then P.H - 0.05 else P.H
	local roofBot = roofTop - P.roofT
	local glassMat = if lite then MAT.SmoothPlastic else MAT.Glass
	local glassC = if lite then C.glassLite else C.glass

	if lite then
		-- 실루엣: 하부 차체(코 포함) + 보닛 쐐기 + 벨트 + 유리 3 + 지붕 + 타이어 2(옆면 돌출) + 전조등/후미등 띠
		sbox(ctx, "Paint", hw, P.sill, P.hoodF, 0.02, L - 0.02, paint, nil, true)
		wedgeF(ctx, "Paint", -hw + 0.02, hw - 0.02, P.hoodF, P.cowl, 0.05, P.hoodZ1, paint, nil, true)
		sbox(ctx, "Paint", hw, P.hoodF, P.belt, P.hoodZ1, L - 0.04, paint, nil, true)
		wedgeF(ctx, "Glass", -P.ghW, P.ghW, P.belt, roofBot, P.hoodZ1, P.roofZ0, glassC, glassMat)
		sbox(ctx, "Glass", P.ghW, P.belt, roofBot, P.roofZ0, P.roofZ1, glassC, glassMat)
		wedgeB(ctx, "Glass", -P.ghW, P.ghW, P.belt, roofBot, P.roofZ1, P.rearZ, glassC, glassMat)
		sbox(ctx, "Paint", P.roofW, roofBot, roofTop, P.roofZ0 - 0.04, P.roofZ1 + 0.04, paint, nil, true)
		axle(ctx, "Tyre", P.W + 0.04, P.r, P.r, zf, C.tyre)
		axle(ctx, "Tyre", P.W + 0.04, P.r, P.r, zr, C.tyre)
		local h = P.head
		sbox(ctx, "Head", h[2], h[3], h[4], -0.02, 0.03, C.headOn, MAT.Neon)
		local t = P.tail
		sbox(ctx, "Tail", t[2], t[3], t[4], L - 0.03, L + 0.02, C.tailRun, MAT.Neon)
		if taxi then
			sbox(ctx, "TaxiSign", 0.30, roofTop, roofTop + 0.20, (P.roofZ0 + P.roofZ1) / 2 - 0.14, (P.roofZ0 + P.roofZ1) / 2 + 0.14, C.taxiSign, MAT.Neon)
		end
		return
	end

	-- 바닥 그림자(접지감): 노면 위 0.02 m
	sbox(ctx, "Under", hw - 0.10, 0.02, 0.035, 0.30, L - 0.30, C.under)
	-- 하부 차체: 휠아치 사이 3 토막
	sbox(ctx, "Paint", hw, P.fbb, aT, P.nz, zf - aH, paint, nil, true)
	if P.rocker then
		sbox(ctx, "Trim", hw, P.sill, P.sill + 0.13, zf + aH, zr - aH, C.trim)
		sbox(ctx, "Paint", hw, P.sill + 0.13, aT, zf + aH, zr - aH, paint, nil, true)
	else
		sbox(ctx, "Paint", hw, P.sill, aT, zf + aH, zr - aH, paint, nil, true)
	end
	sbox(ctx, "Paint", hw, P.rbb, aT, zr + aH, L - P.nz, paint, nil, true)
	-- 어깨 띠(아치 위 ~ 보닛 앞선 높이), 앞/뒤 페시아 + 평면 모서리 깎기
	sbox(ctx, "Paint", hw, aT, P.hoodF, P.nz, L - P.nz, paint, nil, true)
	local noseTop = P.hoodF - 0.07
	sbox(ctx, "Paint", hw - P.nx, P.fbb, noseTop, 0, P.nz, paint, nil, true)
	wedgeF(ctx, "Paint", -(hw - P.nx), hw - P.nx, noseTop, P.hoodF, 0, P.nz, paint) -- 보닛 앞선 둥글림
	chamfer(ctx, "Paint", 1, -1, hw - P.nx, hw, P.fbb, noseTop, 0, P.nz, paint)
	chamfer(ctx, "Paint", -1, -1, hw - P.nx, hw, P.fbb, noseTop, 0, P.nz, paint)
	sbox(ctx, "Paint", hw - P.nx, P.rbb, P.belt, L - P.nz, L, paint, nil, true)
	chamfer(ctx, "Paint", 1, 1, hw - P.nx, hw, P.rbb, P.belt, L - P.nz, L, paint)
	chamfer(ctx, "Paint", -1, 1, hw - P.nx, hw, P.rbb, P.belt, L - P.nz, L, paint)
	-- 보닛(앞으로 낮아지는 쐐기) + 벨트 블록(캐빈 옆면·트렁크)
	wedgeF(ctx, "Paint", -hw + 0.025, hw - 0.025, P.hoodF, P.cowl, P.nz, P.hoodZ1, paint, nil, true)
	sbox(ctx, "Paint", hw, P.hoodF, P.belt, P.hoodZ1, L - P.nz, paint, nil, true)
	-- 그린하우스: 앞유리 쐐기 · 옆유리 상자 · 뒷유리 쐐기 · 지붕
	wedgeF(ctx, "Glass", -P.ghW, P.ghW, P.belt, roofBot, P.hoodZ1, P.roofZ0, C.glass, glassMat)
	sbox(ctx, "Glass", P.ghW, P.belt, roofBot, P.roofZ0, P.roofZ1, C.glass, glassMat)
	wedgeB(ctx, "Glass", -P.ghW, P.ghW, P.belt, roofBot, P.roofZ1, P.rearZ, C.glass, glassMat)
	sbox(ctx, "Paint", P.roofW, roofBot, roofTop, P.roofZ0 - 0.05, P.roofZ1 + 0.05, paint, nil, true)
	-- A 필러(차체색, 앞유리 옆선을 따라 유리 밖으로 0.02 m), B 필러(검정 관통 슬래브), C/D 필러(뒷유리 옆 삼각 판)
	for _, sx in { 1, -1 } do
		strip(ctx, "Paint", sx * (P.ghW - 0.02), P.belt, P.hoodZ1, roofBot, P.roofZ0, 0.08, 0.035, paint)
		local x0 = if sx > 0 then P.ghW + 0.004 else -P.ghW - 0.024
		wedgeB(ctx, "Paint", x0, x0 + 0.02, P.belt, roofBot, P.roofZ1, P.rearZ, paint)
	end
	sbox(ctx, "Trim", P.ghW + 0.02, P.belt, roofBot, P.zB - 0.045, P.zB + 0.045, C.trim)
	if P.cSlab then
		sbox(ctx, "Trim", P.ghW + 0.02, P.belt, roofBot, P.cSlab - 0.05, P.cSlab + 0.05, C.trim)
	end
	if P.rails then
		pair(ctx, "Trim", P.roofW - 0.10, P.roofW - 0.05, roofTop, P.H, P.roofZ0 + 0.20, P.roofZ1 - 0.06, C.trim)
	end
	if P.spoiler then
		sbox(ctx, "Paint", P.roofW - 0.02, roofTop - 0.03, roofTop + 0.02, P.roofZ1 - 0.02, P.roofZ1 + 0.16, paint)
	end
	-- 휠하우스(검정, 차체 폭보다 안쪽) · 타이어 · 림
	sbox(ctx, "Well", hw - 0.06, 0.12, aT - 0.005, zf - aH, zf + aH, C.well)
	sbox(ctx, "Well", hw - 0.06, 0.12, aT - 0.005, zr - aH, zr + aH, C.well)
	-- 휠아치 위 두 모서리를 차체색 관통 쐐기로 채워 둥근 아치처럼(타이어와 ≥ 8 cm 간격)
	local cw, ch = 0.21, 0.19
	for _, za in { zf, zr } do
		newPart(ctx, "Wedge", "Paint", Vector3.new(P.W, ch, cw), Vector3.new(0, aT - ch / 2, za - aH + cw / 2 - ctx.zc), CFrame.Angles(math.pi, 0, 0), paint)
		newPart(ctx, "Wedge", "Paint", Vector3.new(P.W, ch, cw), Vector3.new(0, aT - ch / 2, za + aH - cw / 2 - ctx.zc), CFrame.Angles(0, 0, math.pi), paint)
	end
	local tl = P.track + P.tw
	local rimC = if P.darkRims then C.rimDark else C.rim
	axle(ctx, "Tyre", tl, P.r, P.r, zf, C.tyre)
	axle(ctx, "Tyre", tl, P.r, P.r, zr, C.tyre)
	axle(ctx, "Rim", tl + 0.04, P.rimR, P.r, zf, rimC)
	axle(ctx, "Rim", tl + 0.04, P.rimR, P.r, zr, rimC)
	-- 앞: 그릴(0.03 m 돌출), 전조등 한 쌍, 주간주행등 띠
	local g = P.grille
	sbox(ctx, "Trim", g[1], g[2], g[3], -0.03, 0.02, C.grille)
	local h = P.head
	pair(ctx, "Head", h[1], h[2], h[3], h[4], -0.025, 0.02, C.headOn, MAT.Neon)
	if P.drl then
		local d = P.drl
		sbox(ctx, "DRL", d[1], d[2], d[3], -0.022, 0.02, C.drl, MAT.Neon)
	end
	-- 뒤: 후미등 한 쌍 + (연결형) 후미등 띠
	local t = P.tail
	pair(ctx, "Tail", t[1], t[2], t[3], t[4], L - 0.02, L + 0.025, C.tailRun, MAT.Neon)
	if P.tailBar and not taxi then
		local b = P.tailBar
		sbox(ctx, "Tail", b[1], b[2], b[3], L - 0.02, L + 0.02, C.tailRun, MAT.Neon)
	end
	-- 번호판 (앞: 그릴 앞 0.03 m, 뒤: 페시아 밖 0.03~0.05 m)
	plate(ctx, "PlateF", P.plateFY, -0.06, -0.04, Enum.NormalId.Front)
	plate(ctx, "PlateR", P.plateRY, L + 0.03, L + 0.05, Enum.NormalId.Back)
	-- 사이드미러
	-- 좌우 미러(관통 막대: 앞유리 경사면 아래에 숨도록 앞유리 밑변에서 충분히 뒤)
	local mz = P.hoodZ1 + math.max(0.16, 0.125 * (P.roofZ0 - P.hoodZ1) / (roofBot - P.belt))
	sbox(ctx, "Paint", hw + 0.10, P.belt + 0.005, P.belt + 0.115, mz, mz + 0.15, paint)
	-- 도어 이음선(관통 슬래브, 옆면 밖으로 0.016 m) · 손잡이
	for si, sm in P.seams do
		if taxi and si > 1 then
			break
		end
		local y0 = if sm[2] == 1 then aT + 0.01 else P.sill + 0.05
		sbox(ctx, "Seam", hw + 0.016, y0, P.belt - 0.012, sm[1] - 0.006, sm[1] + 0.006, C.seam)
	end
	for _, z in P.handles do
		sbox(ctx, "Trim", hw + 0.018, P.belt - 0.125, P.belt - 0.095, z - 0.09, z + 0.09, C.chrome)
	end
	if P.slider then
		local s = P.slider
		sbox(ctx, "Seam", hw + 0.016, P.belt - 0.035, P.belt - 0.02, s[1], s[2], C.seam)
	end
	if taxi then
		-- 지붕 표시등(TAXI) + 빈차등(앞유리 오른쪽 아래, 붉은 LED)
		local zm = (P.roofZ0 + P.roofZ1) / 2
		local sp = box(ctx, "TaxiSign", -0.31, 0.31, roofTop, roofTop + 0.21, zm - 0.13, zm + 0.13, C.taxiSign, MAT.SmoothPlastic)
		sign(sp, Enum.NormalId.Front, "TAXI", rgb(30, 30, 34), C.taxiSign, "SignF", 600)
		sign(sp, Enum.NormalId.Back, "TAXI", rgb(30, 30, 34), C.taxiSign, "SignB", 600)
		local run = P.roofZ0 - P.hoodZ1
		local rise = roofBot - P.belt
		local f0, f1 = 0.05, 0.16
		strip(ctx, "Vacancy", 0.40, P.belt + rise * f0, P.hoodZ1 + run * f0, P.belt + rise * f1, P.hoodZ1 + run * f1, 0.22, 0.02, C.vacancy, MAT.Neon)
	end
end

------------------------------------------------------------------------------------------------------
-- 시내버스 11.0 x 2.49 x 3.20 m (저상, 휠베이스 5.85, 타이어 Ø1.0, 뒤 복륜)
------------------------------------------------------------------------------------------------------
local function buildBus(ctx: Ctx, lite: boolean)
	local L, hw = 11.0, 2.49 / 2
	local zf, zr = 2.55, 2.55 + 5.85
	local r = 0.50
	local body = BUS[1].body
	local winTop, roofTop = 2.78, 3.02
	if lite then
		sbox(ctx, "Paint", hw, 0.30, 1.18, 0.02, L, body, nil, true)
		sbox(ctx, "Glass", hw - 0.03, 1.18, winTop, 0.0, L - 0.05, C.glassLite)
		sbox(ctx, "Roof", hw, winTop, roofTop, 0.04, L - 0.04, C.busRoof, nil, true)
		sbox(ctx, "Roof", 0.85, roofTop, 3.20, 3.0, 9.4, C.busRoof)
		axle(ctx, "Tyre", 2.49 + 0.04, r, r, zf, C.tyre)
		axle(ctx, "Tyre", 2.49 + 0.04, r, r, zr, C.tyre)
		sbox(ctx, "Head", 1.08, 0.55, 0.72, -0.03, 0.03, C.headOn, MAT.Neon)
		sbox(ctx, "Tail", 1.12, 0.62, 1.55, L - 0.02, L + 0.03, C.tailRun, MAT.Neon)
		local ledF = sbox(ctx, "LED", 0.95, 2.42, 2.70, -0.05, 0.02, rgb(8, 8, 10))
		sign(ledF, Enum.NormalId.Front, "301", C.ledAmber, rgb(8, 8, 10), "Route", 900)
		return
	end
	sbox(ctx, "Under", hw - 0.12, 0.02, 0.035, 0.6, L - 0.6, C.under)
	-- 하부 차체(노선색): 앞/가운데/뒤 토막, 어깨 띠
	local aH = 0.62
	sbox(ctx, "Paint", hw, 0.30, 1.10, 0.05, zf - aH, body, nil, true)
	sbox(ctx, "Paint", hw, 0.30, 1.10, zf + aH, zr - 0.72, body, nil, true)
	sbox(ctx, "Paint", hw, 0.30, 1.10, zr + 0.72, L, body, nil, true)
	sbox(ctx, "Paint", hw, 1.10, 1.20, 0.05, L, body, nil, true)
	-- 창 띠(옆 유리, 0.03 m 안쪽) + 앞 유리(큰 평면 유리, 앞으로 0.05 m 돌출)
	sbox(ctx, "Glass", hw - 0.03, 1.20, winTop, 0.06, L - 0.05, C.glass, MAT.Glass)
	sbox(ctx, "Glass", hw - 0.08, 0.92, winTop - 0.04, 0.0, 0.10, C.glass, MAT.Glass)
	-- 지붕(흰색) + 앞 캡(노선색) + 에어컨/연료통 덮개
	sbox(ctx, "Roof", hw, winTop, roofTop, 0.62, L - 0.02, C.busRoof, nil, true)
	sbox(ctx, "Paint", hw, winTop, roofTop, 0.05, 0.62, body, nil, true)
	sbox(ctx, "Roof", 0.86, roofTop, 3.20, 2.9, 5.2, C.busRoof)
	sbox(ctx, "Roof", 0.92, roofTop, 3.17, 6.2, 9.6, rgb(200, 204, 208))
	-- 창 기둥(검정 관통 슬래브, 유리 밖 0.02 m)
	for _, z in { 1.62, 3.55, 5.0, 7.15, 8.9, 10.35 } do
		sbox(ctx, "Trim", hw - 0.01, 1.20, winTop, z - 0.05, z + 0.05, C.trim)
	end
	-- 출입문(오른쪽 = +X): 앞문(앞바퀴 앞), 뒷문(가운데)
	box(ctx, "Door", hw - 0.10, hw + 0.02, 0.32, winTop - 0.06, 0.22, 1.42, C.glass, MAT.Glass)
	box(ctx, "Door", hw - 0.10, hw + 0.02, 0.32, winTop - 0.06, 5.55, 6.85, C.glass, MAT.Glass)
	-- 휠하우스 · 타이어(앞 단륜 / 뒤 복륜) · 림
	sbox(ctx, "Well", hw - 0.08, 0.15, 1.095, zf - aH, zf + aH, C.well)
	sbox(ctx, "Well", hw - 0.08, 0.15, 1.095, zr - 0.72, zr + 0.72, C.well)
	axle(ctx, "Tyre", 2.05 + 0.28, r, r, zf, C.tyre)
	axle(ctx, "Tyre", 1.86 + 0.56, r, r, zr, C.tyre)
	axle(ctx, "Rim", 2.05 + 0.28 + 0.04, 0.29, r, zf, C.rim)
	axle(ctx, "Rim", 1.86 + 0.56 + 0.04, 0.29, r, zr, C.rim)
	-- 범퍼(검정) · 전조등 · 후미등(세로)
	sbox(ctx, "Trim", hw - 0.02, 0.30, 0.56, -0.05, 0.25, C.busSkirt)
	sbox(ctx, "Trim", hw - 0.02, 0.30, 0.50, L - 0.25, L + 0.05, C.busSkirt)
	pair(ctx, "Head", 0.70, 1.10, 0.60, 0.74, -0.08, 0.04, C.headOn, MAT.Neon)
	pair(ctx, "Tail", 0.92, 1.16, 0.62, 1.56, L - 0.02, L + 0.03, C.tailRun, MAT.Neon)
	-- LED 노선 표시(앞 · 오른쪽 옆 · 뒤)
	local ledF = sbox(ctx, "LED", 0.98, 2.42, 2.70, -0.05, 0.02, rgb(8, 8, 10))
	sign(ledF, Enum.NormalId.Front, "301  잠실역", C.ledAmber, rgb(8, 8, 10), "Route", 900)
	local ledS = box(ctx, "LED", hw - 0.05, hw + 0.02, 2.36, 2.64, 1.70, 2.85, rgb(8, 8, 10))
	sign(ledS, Enum.NormalId.Right, "301", C.ledAmber, rgb(8, 8, 10), "Route", 500)
	local ledR = sbox(ctx, "LED", 0.55, 2.30, 2.56, L - 0.06, L + 0.03, rgb(8, 8, 10))
	sign(ledR, Enum.NormalId.Back, "301", C.ledAmber, rgb(8, 8, 10), "Route", 500)
	-- 번호판 · 미러(지붕 모서리에서 앞으로 뻗은 팔 + 거울)
	plate(ctx, "PlateF", 0.43, -0.09, -0.065, Enum.NormalId.Front)
	plate(ctx, "PlateR", 0.62, L + 0.06, L + 0.08, Enum.NormalId.Back)
	for _, sx in { 1, -1 } do
		local xi, xo = hw - 0.10, hw + 0.08
		box(ctx, "Trim", if sx > 0 then xi else -xo, if sx > 0 then xo else -xi, 2.62, 2.68, -0.42, 0.10, C.trim)
		local mi, mo = hw - 0.02, hw + 0.10
		box(ctx, "Trim", if sx > 0 then mi else -mo, if sx > 0 then mo else -mi, 1.88, 2.62, -0.46, -0.36, C.trim)
	end
end

------------------------------------------------------------------------------------------------------
-- 1톤 화물(포터형 세미 캡오버) 5.10 x 1.74 x 1.97 / 탑차(적재함 높이 2.55)
------------------------------------------------------------------------------------------------------
local function buildTruck(ctx: Ctx, lite: boolean, boxBody: boolean)
	local L = 5.10
	local hw, chw = 1.74 / 2, 0.85
	local zf, zr = 1.06, 1.06 + 2.64
	local rf, rr = 0.33, 0.29
	local cab = rgb(236, 236, 234)
	local cabEnd = 1.72
	local boxTop = 2.55
	if lite then
		sbox(ctx, "Paint", chw, 0.38, 1.06, 0.0, cabEnd, cab, nil, true)
		wedgeF(ctx, "Glass", -chw + 0.04, chw - 0.04, 1.06, 1.88, 0.08, 0.50, C.glassLite)
		sbox(ctx, "Glass", chw - 0.04, 1.06, 1.88, 0.50, 1.45, C.glassLite)
		sbox(ctx, "Paint", chw - 0.02, 1.06, 1.97, 1.45, cabEnd, cab, nil, true)
		sbox(ctx, "Paint", chw - 0.03, 1.88, 1.97, 0.45, 1.45, cab, nil, true)
		if boxBody then
			sbox(ctx, "Cargo", hw, 0.72, boxTop, 1.80, L, rgb(236, 238, 240), nil, true)
		else
			sbox(ctx, "Bed", hw, 0.72, 1.20, 1.78, L, C.bed, nil, true)
			sbox(ctx, "Cargo", hw - 0.09, 1.20, 1.50, 2.0, 4.7, TARPS[1], nil, true)
		end
		axle(ctx, "Tyre", 1.74 + 0.04, rf, rf, zf, C.tyre)
		axle(ctx, "Tyre", 1.68, rr, rr, zr, C.tyre)
		sbox(ctx, "Head", 0.82, 0.78, 0.93, -0.03, 0.03, C.headOn, MAT.Neon)
		sbox(ctx, "Tail", 0.84, 0.54, 0.68, L - 0.02, L + 0.03, C.tailRun, MAT.Neon)
		return
	end
	sbox(ctx, "Under", hw - 0.12, 0.02, 0.035, 0.25, L - 0.30, C.under)
	-- 캡: 앞바퀴 아치 앞/뒤 하부, 어깨, 앞유리 쐐기, 옆유리, 뒤 기둥, 지붕
	local aT = 2 * rf + 0.07
	local aH = rf + 0.07
	sbox(ctx, "Paint", chw, 0.40, aT, 0.04, zf - aH, cab, nil, true)
	sbox(ctx, "Paint", chw, 0.46, aT, zf + aH, cabEnd, cab, nil, true)
	sbox(ctx, "Paint", chw, aT, 1.06, 0.04, cabEnd, cab, nil, true)
	wedgeF(ctx, "Glass", -chw + 0.04, chw - 0.04, 1.06, 1.88, 0.08, 0.50, C.glass, MAT.Glass)
	sbox(ctx, "Glass", chw - 0.04, 1.06, 1.88, 0.50, 1.45, C.glass, MAT.Glass)
	sbox(ctx, "Paint", chw - 0.02, 1.06, 1.88, 1.45, cabEnd, cab, nil, true)
	sbox(ctx, "Paint", chw - 0.03, 1.88, 1.97, 0.42, cabEnd, cab, nil, true)
	wedgeF(ctx, "Paint", -chw + 0.03, chw - 0.03, 1.88, 1.97, 0.30, 0.42, cab)
	for _, sx in { 1, -1 } do
		strip(ctx, "Paint", sx * (chw - 0.06), 1.06, 0.08, 1.88, 0.50, 0.08, 0.035, cab)
	end
	-- 앞: 검정 그릴 띠, 전조등, 범퍼(진회색)
	sbox(ctx, "Trim", 0.56, 0.74, 0.96, 0.0, 0.06, C.grille)
	pair(ctx, "Head", 0.57, 0.80, 0.77, 0.94, -0.02, 0.06, C.headOn, MAT.Neon)
	sbox(ctx, "Trim", chw - 0.01, 0.30, 0.50, -0.06, 0.12, C.bedDark)
	-- 미러(검정, 문 앞쪽 팔)
	pair(ctx, "Trim", chw - 0.04, chw + 0.17, 1.28, 1.55, 0.40, 0.48, C.trim)
	-- 문 이음선(관통 슬래브)
	sbox(ctx, "Seam", chw + 0.016, aT + 0.01, 1.84, 0.52 - 0.006, 0.52 + 0.006, C.seam)
	sbox(ctx, "Seam", chw + 0.016, 0.50, 1.84, 1.46 - 0.006, 1.46 + 0.006, C.seam)
	-- 앞 휠하우스 · 타이어 · 림 (뒤는 적재함 아래로 노출, 복륜)
	sbox(ctx, "Well", chw - 0.06, 0.12, aT - 0.005, zf - aH, zf + aH, C.well)
	axle(ctx, "Tyre", 1.485 + 0.195, rf, rf, zf, C.tyre)
	axle(ctx, "Tyre", 1.32 + 0.36, rr, rr, zr, C.tyre)
	axle(ctx, "Rim", 1.485 + 0.195 + 0.04, 0.19, rf, zf, C.rim)
	axle(ctx, "Rim", 1.32 + 0.36 + 0.04, 0.17, rr, zr, C.rim)
	-- 섀시 프레임 + 적재함
	sbox(ctx, "Trim", 0.46, 0.42, 0.72, cabEnd, L - 0.05, C.bedDark)
	if boxBody then
		-- 탑차: 알루미늄 박스 + 뒷문 이음선 + 아래 테두리
		sbox(ctx, "Cargo", hw, 0.74, boxTop, 1.80, L, rgb(236, 238, 240), MAT.SmoothPlastic, true)
		sbox(ctx, "Trim", hw + 0.016, 0.72, 0.80, 1.80, L + 0.016, rgb(150, 154, 160))
		box(ctx, "Seam", -0.006, 0.006, 0.82, boxTop - 0.05, L, L + 0.016, C.seam)
		sbox(ctx, "Trim", hw + 0.016, boxTop - 0.06, boxTop, 1.80, L + 0.016, rgb(150, 154, 160))
		sbox(ctx, "Stripe", hw + 0.016, 1.55, 1.75, 1.90, L - 0.10, rgb(40, 84, 170))
	else
		-- 일반 적재함: 바닥 + 좌우/뒤 문짝 + 보호 프레임 + 덮개 씌운 짐
		sbox(ctx, "Bed", hw, 0.72, 0.80, 1.78, L, C.bed, nil, true)
		pair(ctx, "Bed", hw - 0.035, hw, 0.80, 1.20, 1.78, L, C.bed)
		sbox(ctx, "Bed", hw, 0.80, 1.20, L - 0.035, L, C.bed)
		sbox(ctx, "Bed", hw, 0.80, 1.97, 1.74, 1.80, C.bedDark)
		sbox(ctx, "Cargo", hw - 0.09, 0.80, 1.48, 2.0, 4.7, TARPS[1], nil, true)
	end
	-- 뒤: 후미등 · 번호판 · 언더런 바
	pair(ctx, "Tail", 0.58, 0.84, 0.54, 0.68, L - 0.02, L + 0.03, C.tailRun, MAT.Neon)
	sbox(ctx, "Trim", 0.80, 0.34, 0.44, L - 0.10, L + 0.02, C.bedDark)
	plate(ctx, "PlateF", 0.40, -0.10, -0.08, Enum.NormalId.Front)
	plate(ctx, "PlateR", 0.56, L + 0.05, L + 0.07, Enum.NormalId.Back, 0.335, 0.17)
end

------------------------------------------------------------------------------------------------------
-- 템플릿 / 인스턴스
------------------------------------------------------------------------------------------------------
local FRONT: { [string]: number } = {
	sedan = 0.96, compact = 0.80, suv = 0.88, suvL = 0.92, minivan = 0.98, taxi = 0.96, bus = 2.55, truck = 1.06, truckBox = 1.06,
}
local WB: { [string]: number } = {
	sedan = 2.85, compact = 2.58, suv = 2.70, suvL = 2.90, minivan = 3.09, taxi = 2.85, bus = 5.85, truck = 2.64, truckBox = 2.64,
}

local templates: { [string]: Model } = {}

function Vehicles.template(typ: string, lite: boolean): Model
	local key = typ .. (if lite then "/lite" else "/full")
	local t = templates[key]
	if t then
		return t
	end
	local model = Instance.new("Model")
	model.Name = "Vehicle_" .. typ .. (if lite then "_lite" else "")
	local ctx: Ctx = { model = model, zc = (FRONT[typ] or 1) + (WB[typ] or 2.8) / 2, n = 0 }
	if typ == "bus" then
		buildBus(ctx, lite)
	elseif typ == "truck" or typ == "truckBox" then
		buildTruck(ctx, lite, typ == "truckBox")
	else
		buildCar(ctx, SPECS[typ] or SPECS.sedan, lite, typ == "taxi")
	end
	model.WorldPivot = CFrame.new() -- 피벗 = 원점(차축 중간 노면) → PivotTo 로 노면에 정확히 놓임
	model:SetAttribute("Parts", ctx.n)
	model:SetAttribute("VehicleType", typ)
	templates[key] = model
	return model
end

export type Inst = {
	model: Model,
	typ: string,
	lite: boolean,
	parts: { BasePart },
	offs: { CFrame },
	paint: { BasePart },
	heads: { BasePart },
	tails: { BasePart },
	drls: { BasePart },
	lamps: { BasePart },
	plates: { BasePart },
	plateText: { TextLabel },
	route: { TextLabel },
	cargo: { BasePart },
	night: boolean?,
	brake: boolean?,
	lightsOn: boolean?,
	color: Color3?,
	ident: number?,
}

function Vehicles.new(typ: string, lite: boolean, parent: Instance?): Inst
	local model = Vehicles.template(typ, lite):Clone()
	local inst: Inst = {
		model = model,
		typ = typ,
		lite = lite,
		parts = {},
		offs = {},
		paint = {},
		heads = {},
		tails = {},
		drls = {},
		lamps = {},
		plates = {},
		plateText = {},
		route = {},
		cargo = {},
	}
	for _, c in model:GetChildren() do
		if c:IsA("BasePart") then
			table.insert(inst.parts, c)
			table.insert(inst.offs, c.CFrame)
			local n = c.Name
			if n == "Paint" then
				table.insert(inst.paint, c)
			elseif n == "Head" then
				table.insert(inst.heads, c)
			elseif n == "Tail" then
				table.insert(inst.tails, c)
			elseif n == "DRL" then
				table.insert(inst.drls, c)
			elseif n == "Vacancy" or n == "TaxiSign" then
				table.insert(inst.lamps, c)
			elseif n == "PlateF" or n == "PlateR" then
				table.insert(inst.plates, c)
				local g = c:FindFirstChildOfClass("SurfaceGui")
				local tl = g and g:FindFirstChild("Text")
				if tl and tl:IsA("TextLabel") then
					table.insert(inst.plateText, tl)
				end
			elseif n == "LED" then
				local g = c:FindFirstChildOfClass("SurfaceGui")
				local tl = g and g:FindFirstChild("Text")
				if tl and tl:IsA("TextLabel") then
					table.insert(inst.route, tl)
				end
			elseif n == "Cargo" then
				table.insert(inst.cargo, c)
			end
		end
	end
	model.Parent = parent
	return inst
end

------------------------------------------------------------------------------------------------------
-- 외형(색·번호판·노선) — 결정적 해시 h (32-bit 정수)로 고름
------------------------------------------------------------------------------------------------------
local function hbits(h: number, shift: number, mod: number): number
	return bit32.extract(h, shift % 32, 8) % mod
end

function Vehicles.paintFor(typ: string, h: number): Color3
	if typ == "taxi" then
		local k = h % 10
		return if k < 6 then TAXI_ORANGE elseif k < 9 then rgb(238, 238, 236) else rgb(180, 184, 188)
	elseif typ == "bus" then
		return BUS[h % 3 + 1].body
	elseif typ == "truck" or typ == "truckBox" then
		return TRUCK_CABS[h % #TRUCK_CABS + 1]
	end
	local x = (h % 1000) / 1000 * PAINT_TOTAL
	for _, p in PAINTS do
		x -= p.w
		if x < 0 then
			return p.c
		end
	end
	return PAINTS[1].c
end

function Vehicles.plateFor(typ: string, h: number): (string, Color3)
	local num = string.format("%04d", (h // 7) % 10000)
	if typ == "taxi" then
		return string.format("%d%d%s %s", 3, hbits(h, 3, 10), HANGUL_BIZ[hbits(h, 11, 4) + 1], num), C.plateYellow
	elseif typ == "bus" then
		return string.format("7%d%s %s", hbits(h, 3, 10), HANGUL_BIZ[hbits(h, 11, 4) + 1], num), C.plateYellow
	elseif typ == "truckBox" then
		return string.format("8%d배 %s", hbits(h, 3, 10), num), C.plateYellow
	end
	local letter = HANGUL_PRIVATE[hbits(h, 11, #HANGUL_PRIVATE) + 1]
	local ev = hbits(h, 19, 100) < 11 and typ ~= "truck"
	local head = if hbits(h, 5, 3) == 0 then string.format("%03d", 100 + hbits(h, 13, 200) * 4 % 899) else string.format("%02d", 11 + hbits(h, 13, 89))
	return head .. letter .. " " .. num, if ev then C.plateBlue else C.plateWhite
end

-- 인스턴스에 외형 적용(색이 바뀔 때만 속성 기록)
function Vehicles.dress(inst: Inst, h: number, colorOverride: Color3?)
	if inst.ident == h then
		return
	end
	inst.ident = h
	local col = colorOverride or Vehicles.paintFor(inst.typ, h)
	if inst.color ~= col then
		inst.color = col
		for _, p in inst.paint do
			p.Color = col
		end
	end
	if #inst.plateText > 0 or #inst.plates > 0 then
		local text, bg = Vehicles.plateFor(inst.typ, h)
		for _, p in inst.plates do
			if p.Color ~= bg then
				p.Color = bg
			end
		end
		for _, t in inst.plateText do
			t.Text = text
		end
	end
	if inst.typ == "bus" then
		local b = BUS[h % 3 + 1]
		local route = b.routes[hbits(h, 9, #b.routes) + 1]
		for i, t in inst.route do
			t.Text = if i == 1 and not inst.lite then route .. "  " .. b.dest else route
		end
	elseif inst.typ == "truck" then
		local tarp = TARPS[hbits(h, 7, #TARPS) + 1]
		for _, p in inst.cargo do
			p.Color = tarp
		end
	end
end

-- 등화: night = 전조등·후미등 점등, brake = 제동등, on = false 면 모두 소등(주차)
function Vehicles.setLights(inst: Inst, night: boolean, brake: boolean, on: boolean?)
	local lit = on ~= false
	if inst.night == night and inst.brake == brake and inst.lightsOn == lit then
		return
	end
	local headOn = lit and night
	if inst.night ~= night or inst.lightsOn ~= lit then
		for _, p in inst.heads do
			p.Material = if headOn then MAT.Neon else MAT.SmoothPlastic
			p.Color = if headOn then C.headOn else C.headOff
		end
		for _, p in inst.drls do
			p.Material = if lit then MAT.Neon else MAT.SmoothPlastic
			p.Color = if lit then C.drl else C.headOff
		end
		for _, p in inst.lamps do
			if p.Name == "Vacancy" then
				p.Material = if lit then MAT.Neon else MAT.SmoothPlastic
				p.Color = if lit then C.vacancy else rgb(90, 20, 20)
			end
		end
	end
	local tailLit = lit and (night or brake)
	local tailC = if not lit then C.tailOff elseif brake then C.tailBrake elseif night then C.tailRun else C.tailOff
	for _, p in inst.tails do
		p.Material = if tailLit then MAT.Neon else MAT.SmoothPlastic
		p.Color = tailC
	end
	inst.night = night
	inst.brake = brake
	inst.lightsOn = lit
end

-- 혼합 비율에 따른 차종 선택 (u ∈ [0,1), outer = 바깥 차로)
local cumNormal: { { t: string, c: number } } = {}
local cumOuter: { { t: string, c: number } } = {}
do
	local a, b = 0, 0
	for _, t in Vehicles.TYPES do
		a += Vehicles.Info[t].weight
		b += Vehicles.Info[t].weightOuter
	end
	local ca, cb = 0, 0
	for _, t in Vehicles.TYPES do
		ca += Vehicles.Info[t].weight / a
		cb += Vehicles.Info[t].weightOuter / b
		table.insert(cumNormal, { t = t, c = ca })
		table.insert(cumOuter, { t = t, c = cb })
	end
end
function Vehicles.pickType(u: number, outer: boolean): string
	local list = if outer then cumOuter else cumNormal
	for _, e in list do
		if u < e.c then
			return e.t
		end
	end
	return "sedan"
end

-- 주차장용(버스 제외)
function Vehicles.pickParked(u: number): string
	local list = { { "sedan", 0.34 }, { "compact", 0.44 }, { "suv", 0.64 }, { "suvL", 0.76 }, { "minivan", 0.86 }, { "taxi", 0.90 }, { "truck", 0.96 }, { "truckBox", 1.0 } }
	for _, e in list do
		if u < e[2] then
			return e[1]
		end
	end
	return "sedan"
end

return Vehicles
