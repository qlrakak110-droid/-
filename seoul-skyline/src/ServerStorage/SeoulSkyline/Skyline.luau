--!strict
-- SeoulSkyline / Skyline
-- 먼 쪽(잠실) 강변의 히어로 고층 클러스터 — 사진의 오른쪽 초고층 군, 왼쪽 오피스+주거 고층 군, 타워 뒤/오른쪽 중층.
--   * 실제 스케일(1 stud = 0.3 m): 발자국은 m, 높이는 "층수 × 실측 층고"(오피스 4.0 m / 주거 2.9 m)로 지정.
--       오른쪽 초고층 55~64층(220~256 m, 크라운 포함 최고층 ≈ 280 m ≈ 롯데타워의 절반), 왼쪽 오피스 45~58층(180~232 m),
--       가운데 34~50층, 앞줄·필(fill) 25~45층. 발자국 31~53 m.
--   * 주요 실루엣은 손으로 배치(HERO_*: 좌표는 Config.Zones 기준 실측 레이아웃), 빈 곳은 Kit.isFreeRect 로 절차적 필
--   * 모든 발자국 Kit.reserveRect 예약(보도 STREET_PAD 포함 → 이후 모듈과 겹치지 않음)
--   * 히어로 카메라/전망대 시점에서 롯데타워 실루엣과 화면상 겹치는 배치는 거부(타워 시야 보호)
--   * 로비는 숨기지 않고 은은한 발광(spec.lobbyColor), 포디움(상가 저층부)은 타워 뒤·양옆을 감싸는 별동
--   * 창 조명은 Facade 의 Neon 코어 — 블룸을 고려해 Config 창 색보다 한 톤 어두운 팔레트 사용
--   * 원거리 매스(Mass): Facade 코어보다 0.4 stud 안쪽에 숨은 큰 발광 볼륨. 가까이서는 완전히 가려지고,
--     렌더러가 작은 파트(슬래브/코어/크라운)를 거리 컬링하는 먼 거리에서는 건물의 불빛·실루엣을 대신함.

local Config = require(script.Parent.Config)

local Skyline = {}

local rgb = Color3.fromRGB
local BLACK = Color3.new(0, 0, 0)
local P = Config.Palette
local Z = Config.Zones
local R = Config.Real
local M = Config.m
local CITY_Y = Config.Level.City

------------------------------------------------------------------------------------------------------
-- 상수 (실측 m → stud)
------------------------------------------------------------------------------------------------------
local OFFICE_FLOOR = R.OfficeFloor -- 4.0 m
local HOME_FLOOR = R.HomeFloor -- 2.9 m
local STREET_PAD = M(4) -- 예약 시 발자국 바깥 여백(보도 4 m)
local FILL_GAP = M(6) -- 절차적 필 건물 사이 최소 간격(골목 6 m)
local PODIUM_OUT = M(6) -- 포디움이 타워 옆/뒤로 나오는 폭 6 m
local PODIUM_H = 44 -- 상가 3층 13.2 m (Facade 슬래브 면 40.3 / 48.3 과 겹치지 않는 높이)
local GUARD_PAD = 0.012 -- 타워 화면 구간 여유(ndc tan 단위, 약 7px)
local BRIDGE_X = Config.Bridge.X
local BRIDGE_CLEAR = Config.Bridge.Width / 2 + M(17) -- 다리 진입 간선도로 연장선(앞줄)은 비워 둠
local GLINT_Z = Config.FarBank.CityFrom - M(140) -- 이보다 강 쪽(+Z) 건물만 수면 반사
local MAX_LIGHTS = 6
local MASS_INSET = 1.8 -- Facade 커튼월 코어 inset 1.4 + 0.4 → 코어 뒤에 완전히 숨음
local MASS_INSET_ROUND = 2.0 -- 원형 코어 inset 1.6 + 0.4
local MASS_MIN_H = M(60) -- 이보다 낮은 건물은 원거리 매스 생략

-- Facade.curtain 의 로비/캐노피 높이(같은 식) — 매스/랜턴 위치 계산용
local function lobbyHeight(h: number): number
	return math.min(20, h * 0.06)
end

-- 창 조명 팔레트 (Neon = 발광 세기. 블룸 대비 한 톤 낮춤)
local LIT_GOLD = { rgb(160, 110, 56), rgb(138, 96, 50), rgb(118, 82, 46), rgb(178, 128, 68), rgb(72, 80, 100) }
local LIT_COOL = { rgb(78, 94, 124), rgb(66, 80, 108), rgb(96, 106, 128), rgb(140, 106, 66), rgb(56, 66, 88) }
local LIT_HOME = { rgb(166, 112, 60), rgb(146, 100, 54), rgb(124, 86, 50), rgb(180, 134, 80), rgb(82, 88, 108) }

-- 은은한 로비 (기본 WindowWarmDim 보다 어둡게: 원경에서 바닥 띠가 튀지 않게)
local LOBBY_WARM = rgb(104, 78, 50)
local LOBBY_COOL = rgb(66, 76, 96)

-- 유리 / 프레임
local NAVY = rgb(28, 42, 66)
local INK = rgb(34, 50, 76)
local G_DEEP = P.GlassDeep
local G_BLUE = P.GlassBlue
local G_TEAL = P.GlassTeal
local G_SILVER = rgb(112, 130, 152)
local G_BRONZE = P.GlassBronze
local F_DARK = P.Mullion
local F_GOLD = rgb(128, 106, 72)
local F_LIGHT = rgb(132, 140, 152)

local LANTERN_GOLD = rgb(168, 116, 52)
local CROWN_GOLD = rgb(206, 150, 78) -- 원거리 금빛 상층부
local PODIUM = rgb(64, 66, 74)
local SHOPS = rgb(150, 112, 70)

------------------------------------------------------------------------------------------------------
-- 손으로 배치한 실루엣. x,z = 발자국 중심(stud, 실측 레이아웃), wm/dm = 발자국 m (wm = 로컬 X 폭),
--   floors = 층수, home = 주거 층고(2.9 m; 기본은 오피스 4.0 m)
--   crown: led/spire/helipad/slant/frame/box,  lantern: frame 크라운 안의 금빛 발광 볼륨
--   gold: 원거리에서 어두운 유리 몸체 + 금빛 상층부(사진 오른쪽 군의 금빛 크라운)
------------------------------------------------------------------------------------------------------
type Entry = {
	name: string,
	x: number,
	z: number,
	wm: number?,
	dm: number?,
	floors: number?,
	home: boolean?,
	-- 해석 결과(stud)
	w: number?,
	d: number?,
	h: number?,
	floorH: number?,
	yaw: number?,
	style: string?,
	crown: string?,
	tiers: number?,
	glass: Color3?,
	frame: Color3?,
	lit: { Color3 }?,
	litChance: number?,
	led: Color3?,
	podium: boolean?,
	lantern: boolean?,
	light: boolean?,
	glint: boolean?,
	gold: boolean?,
	terrace: boolean?,
}

-- 오른쪽: 초고층 7동(55~64층)이 빽빽하게 (금빛 크라운, 짙은 청색 유리) + 앞줄/사이 중층(30~42층)
local HERO_RIGHT: { Entry } = {
	{ name = "R1_GoldCrown", x = 783, z = -1800, wm = 50, dm = 38, floors = 60, crown = "frame", tiers = 2, glass = NAVY, frame = F_GOLD, lit = LIT_GOLD, litChance = 0.42, led = P.LedGold, podium = true, lantern = true, light = true, glint = true, gold = true },
	{ name = "R2_Twin", x = 980, z = -2008, wm = 43, dm = 39, floors = 57, crown = "led", glass = G_DEEP, lit = LIT_GOLD, litChance = 0.46, led = P.LedGold, podium = true },
	{ name = "R3_Slant", x = 1170, z = -1770, wm = 52, dm = 38, floors = 62, crown = "slant", glass = INK, frame = F_DARK, lit = LIT_GOLD, litChance = 0.46, led = P.LedGold, podium = true, light = true, glint = true },
	{ name = "R4_Apex", x = 1397, z = -1875, wm = 51, dm = 42, floors = 64, crown = "frame", tiers = 2, glass = NAVY, frame = F_GOLD, lit = LIT_GOLD, litChance = 0.4, led = P.LedGold, podium = true, lantern = true, light = true, gold = true },
	{ name = "R5_Cyan", x = 1613, z = -1770, wm = 46, dm = 35, floors = 58, crown = "led", glass = G_DEEP, lit = LIT_COOL, litChance = 0.46, led = P.LedCyan, podium = true, glint = true },
	{ name = "R6_Round", x = 1270, z = -2170, wm = 41, floors = 56, style = "round", crown = "led", glass = G_BLUE, lit = LIT_GOLD, litChance = 0.42, led = P.LedBlue, podium = true },
	{ name = "R7_Spire", x = 1070, z = -1570, wm = 40, dm = 32, floors = 55, yaw = 18, crown = "spire", glass = G_SILVER, frame = F_LIGHT, lit = LIT_COOL, litChance = 0.5, led = P.LedCyan, podium = true },
	-- 앞줄/사이 중층 (30~42층). 다리 축 간선도로(X = Bridge.X ± 폭/2) 는 비워 둠
	{ name = "RM1", x = 560, z = -1333, wm = 36, dm = 27, floors = 32, crown = "box", glass = G_DEEP, lit = LIT_COOL, litChance = 0.6 },
	{ name = "RM2_Round", x = 700, z = -1453, wm = 33, floors = 34, style = "round", crown = "led", glass = G_TEAL, lit = LIT_HOME, litChance = 0.5, led = P.LedCyan },
	{ name = "RM3", x = 1173, z = -1333, wm = 38, dm = 27, floors = 36, crown = "led", tiers = 2, glass = INK, lit = LIT_GOLD, litChance = 0.46, led = P.LedGold, terrace = true },
	{ name = "RM4_Officetel", x = 1410, z = -1437, wm = 35, dm = 29, floors = 48, home = true, crown = "frame", glass = G_BRONZE, frame = F_GOLD, lit = LIT_HOME, litChance = 0.5, led = P.LedGold },
	{ name = "RM5_Heli", x = 1642, z = -1333, wm = 35, dm = 27, floors = 33, crown = "helipad", glass = G_BLUE, lit = LIT_GOLD, litChance = 0.46 },
	{ name = "RM6_Slant", x = 600, z = -1733, wm = 33, dm = 31, floors = 40, crown = "slant", glass = G_TEAL, lit = LIT_GOLD, litChance = 0.42, led = P.LedCyan },
	{ name = "RM7", x = 603, z = -2087, wm = 35, dm = 32, floors = 42, yaw = 90, crown = "led", glass = G_DEEP, lit = LIT_GOLD, litChance = 0.42, led = P.LedBlue },
	{ name = "RM8_Round", x = 1670, z = -2087, wm = 34, floors = 40, style = "round", crown = "led", glass = G_BLUE, lit = LIT_HOME, litChance = 0.46, led = P.LedGold },
}

-- 왼쪽: 오피스 7동(42~58층) + 강변 주거 고층(주상복합 40~52층 × 2.9 m, 원형/커튼월 혼합, 따뜻한 조명)
local HERO_LEFT: { Entry } = {
	{ name = "L1", x = -2103, z = -1870, wm = 47, dm = 35, floors = 50, crown = "led", tiers = 2, glass = G_DEEP, lit = LIT_COOL, litChance = 0.46, led = P.LedGold, podium = true, terrace = true },
	{ name = "L2_Spire", x = -1887, z = -2087, wm = 42, dm = 39, floors = 58, crown = "spire", glass = G_BLUE, frame = F_LIGHT, lit = LIT_COOL, litChance = 0.42, led = P.LedCyan, light = true, podium = true },
	{ name = "L3_GoldCrown", x = -1670, z = -1870, wm = 48, dm = 35, floors = 55, crown = "frame", tiers = 2, glass = NAVY, frame = F_GOLD, lit = LIT_GOLD, litChance = 0.42, led = P.LedGold, podium = true, lantern = true, light = true, gold = true },
	{ name = "L4_Slant", x = -1453, z = -2170, wm = 40, dm = 35, floors = 48, yaw = 90, crown = "slant", glass = G_TEAL, lit = LIT_COOL, litChance = 0.42, led = P.LedCyan, podium = true },
	{ name = "L5_Heli", x = -2337, z = -2137, wm = 39, dm = 32, floors = 45, crown = "helipad", glass = G_DEEP, lit = LIT_COOL, litChance = 0.46, podium = true },
	{ name = "L6", x = -2520, z = -1803, wm = 37, dm = 31, floors = 42, crown = "box", glass = G_SILVER, frame = F_LIGHT, lit = LIT_HOME, litChance = 0.46 },
	{ name = "L7_WarmFront", x = -1803, z = -1603, wm = 36, dm = 30, floors = 56, home = true, crown = "led", glass = G_BRONZE, lit = LIT_HOME, litChance = 0.58, led = P.LedGold },
	-- 강변 주거 고층
	{ name = "LR1_Round", x = -2503, z = -1370, wm = 33, floors = 46, home = true, style = "round", crown = "led", glass = G_DEEP, lit = LIT_HOME, litChance = 0.5, led = P.LedGold },
	{ name = "LR2", x = -2367, z = -1473, wm = 35, dm = 25, floors = 42, home = true, crown = "frame", glass = G_SILVER, frame = F_LIGHT, lit = LIT_HOME, litChance = 0.5, led = P.LedGold },
	{ name = "LR3_Round", x = -2217, z = -1340, wm = 35, floors = 52, home = true, style = "round", crown = "led", glass = G_BLUE, lit = LIT_HOME, litChance = 0.5, led = P.LedCyan },
	{ name = "LR4", x = -2067, z = -1503, wm = 36, dm = 27, floors = 48, home = true, crown = "led", glass = G_DEEP, lit = LIT_HOME, litChance = 0.5, led = P.LedGold },
	{ name = "LR5_Round", x = -1917, z = -1370, wm = 32, floors = 44, home = true, style = "round", crown = "box", glass = G_TEAL, lit = LIT_HOME, litChance = 0.5 },
	{ name = "LR6", x = -1603, z = -1370, wm = 37, dm = 28, floors = 50, home = true, crown = "frame", glass = G_BRONZE, frame = F_GOLD, lit = LIT_HOME, litChance = 0.5, led = P.LedGold },
	{ name = "LR7_Round", x = -1437, z = -1503, wm = 33, floors = 46, home = true, style = "round", crown = "led", glass = G_DEEP, lit = LIT_HOME, litChance = 0.5, led = P.LedMagenta },
	{ name = "LR8", x = -2670, z = -1603, wm = 32, dm = 28, floors = 40, home = true, crown = "box", glass = G_DEEP, lit = LIT_HOME, litChance = 0.46 },
	{ name = "LR9", x = -2253, z = -1670, wm = 36, dm = 28, floors = 52, home = true, crown = "frame", glass = G_DEEP, frame = F_DARK, lit = LIT_HOME, litChance = 0.5, led = P.LedGold },
	{ name = "LR10", x = -1993, z = -1670, wm = 31, dm = 27, floors = 44, home = true, yaw = 22, crown = "led", glass = G_BLUE, lit = LIT_HOME, litChance = 0.5, led = P.LedCyan },
	{ name = "LR11_Round", x = -1370, z = -1737, wm = 32, floors = 40, style = "round", crown = "led", glass = G_DEEP, lit = LIT_COOL, litChance = 0.46, led = P.LedGold },
}

-- 가운데(타워 뒤/오른쪽): 34~50층 몇 동
local HERO_MID: { Entry } = {
	{ name = "M1", x = -250, z = -2103, wm = 37, dm = 32, floors = 42, crown = "led", glass = G_DEEP, lit = LIT_COOL, litChance = 0.46, led = P.LedCyan, podium = true },
	{ name = "M2_Lantern", x = -20, z = -2220, wm = 36, dm = 29, floors = 46, crown = "frame", glass = NAVY, frame = F_GOLD, lit = LIT_GOLD, litChance = 0.46, led = P.LedGold, lantern = true, light = true, gold = true },
	{ name = "M3_Round", x = 170, z = -2070, wm = 35, floors = 40, style = "round", crown = "led", glass = G_BLUE, lit = LIT_HOME, litChance = 0.5, led = P.LedGold },
	{ name = "M4_Slant", x = -137, z = -2537, wm = 41, dm = 35, floors = 50, crown = "slant", glass = INK, lit = LIT_COOL, litChance = 0.42, led = P.LedBlue, podium = true },
	{ name = "M5", x = 120, z = -2703, wm = 33, dm = 31, floors = 34, yaw = 90, crown = "box", glass = G_TEAL, lit = LIT_HOME, litChance = 0.46 },
}

-- m/층수 → stud 해석 (w, d, h, floorH 채움)
local function resolve(e: Entry): Entry
	local fh = if e.home then HOME_FLOOR else OFFICE_FLOOR
	e.floorH = fh
	if e.wm then
		e.w = M(e.wm :: number)
	end
	if e.dm then
		e.d = M(e.dm :: number)
	end
	if e.floors then
		e.h = (e.floors :: number) * fh
	end
	if (e.style or "curtain") == "round" or e.d == nil then
		e.d = e.w
	end
	return e
end

type FillOpts = {
	zone: { XMin: number, XMax: number, ZMin: number, ZMax: number },
	group: Instance,
	count: number,
	cx: number,
	cz: number,
	floorsMin: number,
	floorsMax: number,
	homeBias: number, -- 주거(따뜻한 조명, 2.9 m 층고) 비율
	midChance: number, -- 뒷줄 건물을 저파트 "mid" 매스로 만들 확률
}

------------------------------------------------------------------------------------------------------
-- 타워 시야 보호: 카메라 기준 화면 가로 구간(ndc = tan 각도) 비교
------------------------------------------------------------------------------------------------------
type Cam = { pos: Vector3, f: Vector3, r: Vector3, lo: number, hi: number }

local function ndcX(cam: Cam, p: Vector3): number
	local d = p - cam.pos
	local zc = d:Dot(cam.f)
	if zc < 1 then
		return if d:Dot(cam.r) < 0 then -1e6 else 1e6
	end
	return d:Dot(cam.r) / zc
end

local function rectCorners(cx: number, cz: number, w: number, d: number, yawDeg: number): { Vector3 }
	local cf = CFrame.new(cx, 0, cz) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local out = {}
	for _, s in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		table.insert(out, cf * Vector3.new(s[1] * w / 2, 0, s[2] * d / 2))
	end
	return out
end

local function spanOf(cam: Cam, corners: { Vector3 }, y0: number, y1: number): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, c in corners do
		for _, y in { y0, y1 } do
			local v = ndcX(cam, Vector3.new(c.X, y, c.Z))
			lo = math.min(lo, v)
			hi = math.max(hi, v)
		end
	end
	return lo, hi
end

local function makeCams(): { Cam }
	local VP, T = Config.Viewpoint, Config.Landmark.Tower
	local views = {
		{ VP.HeroCamPos, VP.HeroCamLook },
		{ Vector3.new(VP.DeckCenter.X, VP.DeckHeight + R.Railing * 1.5, VP.DeckCenter.Z), VP.HeroCamLook }, -- 전망대 눈높이
	}
	local cams: { Cam } = {}
	local tc = rectCorners(T.Center.X, T.Center.Z, T.BaseWidth, T.BaseWidth, T.Yaw)
	local top = T.Center.Y + T.Height + T.CrownHeight + T.SpireHeight
	for _, v in views do
		local f = (v[2] - v[1]).Unit
		local r = f:Cross(Vector3.yAxis).Unit
		local cam: Cam = { pos = v[1], f = f, r = r, lo = 0, hi = 0 }
		local lo, hi = spanOf(cam, tc, T.Center.Y, top)
		cam.lo, cam.hi = lo - GUARD_PAD, hi + GUARD_PAD
		table.insert(cams, cam)
	end
	return cams
end

local function blocksTower(cams: { Cam }, x: number, z: number, w: number, d: number, yaw: number, h: number): boolean
	local corners = rectCorners(x, z, w, d, yaw)
	for _, cam in cams do
		local lo, hi = spanOf(cam, corners, CITY_Y, CITY_Y + h + M(20))
		if lo < cam.hi and hi > cam.lo then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------------------------------
-- Facade 커튼월 단(tier) 구간 재현 (Facade.curtain 과 같은 식) → { y0, y1, w, d }
------------------------------------------------------------------------------------------------------
local function tierBlocks(w0: number, d0: number, h: number, tierCount: number?): { { number } }
	local y = lobbyHeight(h) + 1.6
	local remaining = h - y
	local w, d = w0, d0
	local tiers = math.clamp(tierCount or 1, 1, 3)
	local out = {}
	for t = 1, tiers do
		local frac = if t == tiers then 1 else (if tiers == 2 then 0.62 else (if t == 1 then 0.5 else 0.6))
		local th = if t == tiers then h - y else math.floor(remaining * frac)
		table.insert(out, { y, y + th, w, d })
		y += th
		remaining = h - y
		if t < tiers then
			w *= 0.78
			d *= 0.78
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------
-- 빌드
------------------------------------------------------------------------------------------------------
function Skyline.build(ctx: any)
	local Kit = ctx.Kit
	local Facade = ctx.Facade
	local rng: Random = ctx.rng
	local cams = makeCams()
	local lightsLeft = MAX_LIGHTS
	local placed = 0
	-- 수면 반사 띠 X 구간 (같은 높이 Y=Water+0.3 이라 겹치면 z-fighting). 다리 반사 구간은 미리 점유.
	local bridgeHalf = Config.Bridge.Width / 2 + M(15)
	local glints: { { number } } = { { BRIDGE_X - bridgeHalf, BRIDGE_X + bridgeHalf } }

	local function claimGlint(x: number, width: number): boolean
		local x0, x1 = x - width / 2 - 2, x + width / 2 + 2
		for _, g in glints do
			if x0 < g[2] and x1 > g[1] then
				return false
			end
		end
		table.insert(glints, { x0, x1 })
		return true
	end

	local function glowOpts(name: string, dayColor: Color3): any
		return { name = name, collide = false, query = false, shadow = false, glow = true, dayMaterial = Enum.Material.Glass, dayColor = dayColor }
	end

	-- 원거리 매스: 코어보다 0.4 안쪽, 각 단 위/아래 0.4~0.5 안쪽 → 어떤 면과도 겹치지 않음
	local function addMass(m: Model, e: Entry, w: number, d: number, h: number, cf: CFrame, style: string)
		if h < MASS_MIN_H or style == "mid" or style == "far" then
			return
		end
		local lit = e.lit or LIT_COOL
		local lc = e.litChance or 0.55
		local function litColor(): Color3
			local c = lit[rng:NextInteger(1, #lit)]
			return c:Lerp(BLACK, 0.18 + (1 - lc) * 0.5 + rng:NextNumber(0, 0.12))
		end
		local glass = e.glass or G_DEEP
		if style == "round" then
			local y0, y1 = lobbyHeight(h) + 0.5, h - 0.4
			local c = if e.gold then CROWN_GOLD:Lerp(BLACK, 0.12) else litColor()
			Kit.cylAlongY(m, cf * CFrame.new(0, (y0 + y1) / 2, 0), y1 - y0, w - MASS_INSET_ROUND * 2, c, Enum.Material.Neon, glowOpts("Mass", glass))
			return
		end
		local blocks = tierBlocks(w, d, h, e.tiers)
		local top = blocks[#blocks]
		local tw, td = top[3] - MASS_INSET * 2, top[4] - MASS_INSET * 2
		-- 척추(spine): 최상단 단의 평면으로 전체 높이 → 상층 실루엣이 원거리에서도 유지됨
		local y0, y1 = blocks[1][1] + 0.5, h - 0.4
		local spineC = if e.gold then CROWN_GOLD else litColor()
		Kit.box(m, cf * CFrame.new(0, (y0 + y1) / 2, 0), Vector3.new(tw, y1 - y0, td), spineC, Enum.Material.Neon, glowOpts("Mass", glass))
		-- 아래 단(더 넓은 평면): 금빛 크라운 건물은 어두운 유리 몸체, 나머지는 은은한 불빛
		for i = 1, #blocks - 1 do
			local b = blocks[i]
			local by0, by1 = b[1] + 0.4, b[2] - 0.4
			local size = Vector3.new(b[3] - MASS_INSET * 2, by1 - by0, b[4] - MASS_INSET * 2)
			local bcf = cf * CFrame.new(0, (by0 + by1) / 2, 0)
			if e.gold then
				Kit.box(m, bcf, size, glass:Lerp(BLACK, 0.25), Enum.Material.Glass, { name = "Mass", collide = false, query = false, shadow = false, reflectance = 0.12 })
			else
				Kit.box(m, bcf, size, litColor(), Enum.Material.Neon, glowOpts("Mass", glass))
			end
		end
	end

	local function addExtras(m: Model, e: Entry, w: number, d: number, h: number, cf: CFrame)
		-- 포디움(상가 3층): 타워 뒤·양옆을 감싸는 별동. 앞면은 타워 앞면보다 안쪽(로비가 그대로 보임)
		if e.podium then
			local front, back = d * 0.1, -d / 2 - PODIUM_OUT
			local pw = w + PODIUM_OUT * 2
			local zc = (front + back) / 2
			Kit.box(m, cf * CFrame.new(0, PODIUM_H / 2, zc), Vector3.new(pw, PODIUM_H, front - back), PODIUM, Enum.Material.Concrete, { name = "Podium" })
			-- 상가 간판 띠(높이 2.4~3.6 m): 앞면에서 0.5 튀어나오고 옆면보다 0.4 바깥
			Kit.box(m, cf * CFrame.new(0, M(3), front - 0.1), Vector3.new(pw + 0.8, M(1.2), 1.2), SHOPS, Enum.Material.Neon, glowOpts("PodiumShops", G_DEEP))
		end
		local lightPart: BasePart? = nil
		-- frame 크라운 안의 금빛 랜턴 — Facade.crown "frame" 치수(파라펫 ph, 프레임 fh, 기둥 3.2, LED 1.6, 상부 보 3.2)와 0.5 이상 이격
		if e.lantern and e.crown == "frame" and (e.style or "curtain") == "curtain" then
			local blocks = tierBlocks(w, d, h, e.tiers)
			local top = blocks[#blocks]
			local ph = math.clamp(h * 0.03, 7, 27)
			local fh = math.clamp(h * 0.07, 17, 56)
			local y0, y1 = h + ph + 1.6 + 0.5, h + ph + fh - 1.6 - 0.5
			lightPart = Kit.box(m, cf * CFrame.new(0, (y0 + y1) / 2, 0), Vector3.new(top[3] - 3.2 * 2 - 1.0, y1 - y0, top[4] * 0.6), LANTERN_GOLD, Enum.Material.Neon, glowOpts("Lantern", NAVY))
		end
		-- 실제 광원: 크라운을 금빛으로 적시는 PointLight (예산 MAX_LIGHTS)
		if e.light and lightsLeft > 0 then
			local part = lightPart or m:FindFirstChild("Roof") :: BasePart?
			if part then
				if Kit.light(part, "PointLight", { color = e.led or P.LedGold, brightness = 2.4, range = 60 }) then
					lightsLeft -= 1
				end
			end
		end
	end

	local function place(group: Instance, e: Entry, curated: boolean): Model?
		resolve(e)
		local w, d, h = e.w :: number, e.d :: number, e.h :: number
		local yaw = e.yaw or 0
		local style = e.style or "curtain"
		local pad = STREET_PAD + (if e.podium then PODIUM_OUT else 0)
		if blocksTower(cams, e.x, e.z, w + pad, d + pad, yaw, h) then
			if curated then
				warn("[Skyline] 타워 시야를 가려 생략: " .. e.name)
			end
			return nil
		end
		local ext = (pad - STREET_PAD) * 2 -- 포디움까지 포함한 실제 발자국
		if curated and not Kit.isFreeRect(e.x, e.z, w + ext, d + ext, yaw, 0) then
			warn("[Skyline] 예약과 겹침: " .. e.name)
		end
		Kit.reserveRect(e.x, e.z, w + pad * 2, d + pad * 2, yaw, "Skyline")
		local cf = CFrame.new(e.x, CITY_Y, e.z) * CFrame.Angles(0, math.rad(yaw), 0)
		local wantGlint = if e.glint ~= nil then e.glint else (e.z > GLINT_Z and math.abs(e.x - BRIDGE_X) > BRIDGE_CLEAR)
		local glint = wantGlint and style ~= "mid" and claimGlint(e.x, math.min(w, d) * 0.35) -- Facade 반사 폭과 동일
		local warm = (e.lit or LIT_COOL) ~= LIT_COOL
		local m = Facade.tower(group, {
			name = e.name,
			cf = cf,
			w = w,
			d = d,
			h = h,
			style = style,
			rng = rng,
			floorH = e.floorH,
			glass = e.glass,
			frame = e.frame,
			lit = e.lit,
			litChance = e.litChance,
			crown = e.crown,
			ledColor = e.led,
			tiers = e.tiers,
			glint = glint,
			lobbyColor = if warm then LOBBY_WARM else LOBBY_COOL,
			terraceLed = e.terrace or e.gold or false,
		})
		m:SetAttribute("Floors", e.floors or math.floor(h / (e.floorH :: number)))
		m:SetAttribute("HeightMeters", math.floor(h * Config.METERS_PER_STUD + 0.5))
		addMass(m, e, w, d, h, cf, style)
		addExtras(m, e, w, d, h, cf)
		placed += 1
		return m
	end

	-- 1) 손으로 배치한 주요 실루엣 (먼저 예약)
	local gRight = Kit.group(ctx.model, "SkylineRight")
	local gLeft = Kit.group(ctx.model, "SkylineLeft")
	local gMid = Kit.group(ctx.model, "SkylineMid")
	for _, e in HERO_RIGHT do
		place(gRight, e, true)
	end
	for _, e in HERO_LEFT do
		place(gLeft, e, true)
	end
	for _, e in HERO_MID do
		place(gMid, e, true)
	end

	-- 2) 절차적 필(25~45층): 클러스터 중심에 가까울수록 높게, 강 쪽 앞줄은 반사, 뒷줄 일부는 저파트 매스
	local GLASSES = { G_DEEP, G_BLUE, G_TEAL, INK, G_SILVER, G_BRONZE, NAVY }
	local CROWNS = { "box", "led", "led", "flat", "helipad", "frame", "slant", "box" }
	local LEDS = { P.LedGold, P.LedGold, P.LedCyan, P.LedBlue, P.LedGold }
	local MARGIN = M(9)

	local function fill(o: FillOpts)
		local zn = o.zone
		local n, tries = 0, 0
		local maxR = math.max(zn.XMax - zn.XMin, zn.ZMax - zn.ZMin) * 0.6
		while n < o.count and tries < o.count * 40 do
			tries += 1
			local w = M(rng:NextInteger(30, 45))
			local d = M(rng:NextInteger(28, 40))
			local r = rng:NextNumber()
			local yaw = if r < 0.6 then 0 elseif r < 0.86 then 90 else (rng:NextInteger(15, 30) * (if rng:NextNumber() < 0.5 then -1 else 1))
			local x = rng:NextNumber(zn.XMin + MARGIN, zn.XMax - MARGIN)
			local z = rng:NextNumber(zn.ZMin + MARGIN, zn.ZMax - MARGIN)
			local front = z > GLINT_Z
			if math.abs(x - BRIDGE_X) < BRIDGE_CLEAR + w / 2 then
				continue
			end
			if not Kit.isFreeRect(x, z, w + STREET_PAD * 2, d + STREET_PAD * 2, yaw, FILL_GAP) then
				continue
			end
			local t = math.clamp(math.sqrt((x - o.cx) ^ 2 + (z - o.cz) ^ 2) / maxR, 0, 1)
			local floors = math.floor((o.floorsMax + (o.floorsMin - o.floorsMax) * t) * rng:NextNumber(0.85, 1.06) + 0.5)
			floors = math.clamp(floors, 25, 45)
			local home = rng:NextNumber() < o.homeBias
			local styleR = rng:NextNumber()
			local style = if styleR < 0.2 then "round" elseif (not front and styleR > 1 - o.midChance) then "mid" else "curtain"
			local e: Entry = {
				name = string.format("Fill_%d", placed + 1),
				x = x,
				z = z,
				w = w,
				d = d,
				floors = floors,
				home = home,
				yaw = yaw,
				style = style,
				crown = CROWNS[rng:NextInteger(1, #CROWNS)],
				glass = GLASSES[rng:NextInteger(1, #GLASSES)],
				lit = if home then LIT_HOME else LIT_COOL,
				litChance = rng:NextNumber(0.36, 0.56),
				led = LEDS[rng:NextInteger(1, #LEDS)],
				tiers = if floors > 38 and rng:NextNumber() < 0.4 then 2 else 1,
			}
			if style == "round" then
				e.w = math.min(w, d) + M(2)
				e.d = e.w
				e.crown = if e.crown == "led" or e.crown == "box" then e.crown else "led"
			end
			if place(o.group, e, false) then
				n += 1
			end
		end
	end

	fill({ zone = Z.SkylineRight, group = gRight, count = 11, cx = 1167, cz = -1833, floorsMin = 28, floorsMax = 45, homeBias = 0.35, midChance = 0.5 })
	fill({ zone = Z.SkylineLeft, group = gLeft, count = 9, cx = -1833, cz = -1833, floorsMin = 25, floorsMax = 42, homeBias = 0.6, midChance = 0.5 })
	fill({ zone = Z.SkylineMid, group = gMid, count = 5, cx = -67, cz = -2417, floorsMin = 30, floorsMax = 42, homeBias = 0.4, midChance = 0.5 })

	ctx.model:SetAttribute("Buildings", placed)
	ctx.model:SetAttribute("Lights", MAX_LIGHTS - lightsLeft)
end

return Skyline
