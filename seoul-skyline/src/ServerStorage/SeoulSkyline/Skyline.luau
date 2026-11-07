--!strict
-- SeoulSkyline / Skyline
-- 먼 쪽(잠실) 강변의 히어로 고층 클러스터 — 사진의 오른쪽 초고층 군, 왼쪽 오피스+주거 고층 군, 타워 뒤/오른쪽 중층.
--   * 주요 실루엣은 손으로 배치(HERO_*), 빈 곳은 Kit.isFreeRect 로 절차적 필(fill)
--   * 모든 발자국 Kit.reserveRect 예약(가로 여유 STREET_PAD 포함 → 이후 모듈과 겹치지 않음)
--   * 히어로 카메라/전망대 시점에서 롯데타워 실루엣과 화면상 겹치는 배치는 거부(타워 시야 보호)
--   * 창 조명은 Facade 의 Neon 코어 — 블룸을 고려해 Config 창 색보다 한 톤 어두운 팔레트 사용

local Config = require(script.Parent.Config)

local Skyline = {}

local rgb = Color3.fromRGB
local P = Config.Palette
local Z = Config.Zones
local CITY_Y = Config.Level.City

------------------------------------------------------------------------------------------------------
-- 상수
------------------------------------------------------------------------------------------------------
local STREET_PAD = 7 -- 예약 시 발자국 바깥 여백(보도/골목)
local FILL_GAP = 12 -- 절차적 필 건물 사이 최소 간격
local GUARD_PAD = 0.012 -- 타워 화면 구간 여유(ndc tan 단위, 약 7px)
local BRIDGE_X = Config.Bridge.X
local BRIDGE_CLEAR = Config.Bridge.Width / 2 + 34 -- 다리 진입 도로 연장선(앞줄)은 비워 둠
local GLINT_Z = -900 -- 이보다 강 쪽(+Z) 건물만 수면 반사
local MAX_LIGHTS = 6

-- 창 조명 팔레트 (Neon = 발광 세기. 블룸 대비 한 톤 낮춤)
local LIT_GOLD = { rgb(222, 166, 94), rgb(198, 146, 82), rgb(172, 126, 74), rgb(236, 188, 118), rgb(118, 124, 146) }
local LIT_COOL = { rgb(158, 178, 212), rgb(132, 152, 188), rgb(184, 194, 212), rgb(196, 158, 110), rgb(106, 118, 148) }
local LIT_HOME = { rgb(226, 162, 96), rgb(202, 144, 84), rgb(176, 126, 78), rgb(234, 194, 132), rgb(138, 144, 168) }

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

local LANTERN_GOLD = rgb(176, 124, 58)
local PODIUM = rgb(64, 66, 74)

------------------------------------------------------------------------------------------------------
-- 손으로 배치한 실루엣. x,z = 발자국 중심, w = 로컬 X 폭(카메라를 향하는 면), d = 깊이
--   crown: led/spire/helipad/slant/frame/box,  lantern: frame 크라운 안의 금빛 발광 볼륨
------------------------------------------------------------------------------------------------------
type Entry = {
	name: string,
	x: number,
	z: number,
	w: number,
	d: number,
	h: number,
	yaw: number?,
	style: string?,
	crown: string?,
	tiers: number?,
	glass: Color3?,
	frame: Color3?,
	lit: { Color3 }?,
	litChance: number?,
	led: Color3?,
	floorH: number?,
	podium: boolean?,
	lantern: boolean?,
	light: boolean?,
	glint: boolean?,
}

-- 오른쪽: 초고층 5~7동이 빽빽하게 (금빛 크라운, 짙은 청색 유리) + 앞줄 중층
local HERO_RIGHT: { Entry } = {
	{ name = "R1_GoldCrown", x = 470, z = -1080, w = 72, d = 56, h = 420, crown = "frame", tiers = 2, glass = NAVY, frame = F_GOLD, lit = LIT_GOLD, litChance = 0.5, led = P.LedGold, podium = true, lantern = true, light = true, glint = true },
	{ name = "R2_Twin", x = 588, z = -1205, w = 60, d = 58, h = 350, crown = "led", glass = G_DEEP, lit = LIT_COOL, litChance = 0.55, led = P.LedGold },
	{ name = "R3_Slant", x = 702, z = -1062, w = 78, d = 54, h = 462, crown = "slant", tiers = 2, glass = INK, frame = F_DARK, lit = LIT_GOLD, litChance = 0.5, led = P.LedGold, podium = true, light = true, glint = true },
	{ name = "R4_Apex", x = 832, z = -1172, w = 72, d = 62, h = 482, crown = "frame", tiers = 3, glass = NAVY, frame = F_GOLD, lit = LIT_GOLD, litChance = 0.45, led = P.LedGold, podium = true, lantern = true, light = true },
	{ name = "R5_Cyan", x = 958, z = -1060, w = 64, d = 52, h = 398, crown = "led", glass = G_DEEP, lit = LIT_COOL, litChance = 0.55, led = P.LedCyan, podium = true, glint = true },
	{ name = "R6_Round", x = 762, z = -1302, w = 56, d = 56, h = 372, style = "round", crown = "led", glass = G_BLUE, lit = LIT_COOL, litChance = 0.5, led = P.LedBlue },
	{ name = "R7_Spire", x = 642, z = -942, w = 58, d = 46, h = 338, yaw = 18, crown = "spire", glass = G_SILVER, frame = F_LIGHT, lit = LIT_COOL, litChance = 0.6, led = P.LedCyan },
	-- 앞줄/사이 중층 (150~300)
	{ name = "RM1", x = 300, z = -800, w = 46, d = 40, h = 200, crown = "box", glass = G_DEEP, lit = LIT_COOL, litChance = 0.6 },
	{ name = "RM2_Round", x = 420, z = -872, w = 40, d = 40, h = 162, style = "round", crown = "led", glass = G_TEAL, lit = LIT_HOME, litChance = 0.6, led = P.LedCyan },
	{ name = "RM3", x = 704, z = -800, w = 54, d = 38, h = 238, crown = "led", tiers = 2, glass = INK, lit = LIT_GOLD, litChance = 0.55, led = P.LedGold },
	{ name = "RM4_Officetel", x = 846, z = -862, w = 46, d = 42, h = 268, crown = "frame", glass = G_BRONZE, frame = F_GOLD, lit = LIT_HOME, litChance = 0.6, led = P.LedGold, floorH = 6.5 },
	{ name = "RM5_Heli", x = 985, z = -800, w = 42, d = 38, h = 212, crown = "helipad", glass = G_BLUE, lit = LIT_COOL, litChance = 0.55 },
	{ name = "RM6_Slant", x = 262, z = -1040, w = 48, d = 44, h = 282, crown = "slant", glass = G_TEAL, lit = LIT_COOL, litChance = 0.5, led = P.LedCyan },
	{ name = "RM7", x = 362, z = -1252, w = 50, d = 46, h = 300, yaw = 90, crown = "led", glass = G_DEEP, lit = LIT_GOLD, litChance = 0.5, led = P.LedBlue },
	{ name = "RM8_Round", x = 1002, z = -1252, w = 46, d = 46, h = 262, style = "round", crown = "led", glass = G_BLUE, lit = LIT_HOME, litChance = 0.55, led = P.LedGold },
}

-- 왼쪽: 오피스 4~6동(240~380) + 주거 고층 군(원형/커튼월 혼합, 따뜻한 조명)
local HERO_LEFT: { Entry } = {
	{ name = "L1", x = -1262, z = -1122, w = 66, d = 52, h = 330, crown = "led", tiers = 2, glass = G_DEEP, lit = LIT_COOL, litChance = 0.55, led = P.LedGold, podium = true },
	{ name = "L2_Spire", x = -1132, z = -1252, w = 58, d = 58, h = 378, crown = "spire", glass = G_BLUE, frame = F_LIGHT, lit = LIT_COOL, litChance = 0.5, led = P.LedCyan, light = true },
	{ name = "L3_GoldCrown", x = -1002, z = -1122, w = 70, d = 50, h = 362, crown = "frame", tiers = 2, glass = NAVY, frame = F_GOLD, lit = LIT_GOLD, litChance = 0.5, led = P.LedGold, podium = true, lantern = true, light = true },
	{ name = "L4_Slant", x = -872, z = -1302, w = 56, d = 50, h = 300, yaw = 90, crown = "slant", glass = G_TEAL, lit = LIT_COOL, litChance = 0.5, led = P.LedCyan },
	{ name = "L5_Heli", x = -1402, z = -1282, w = 52, d = 46, h = 270, crown = "helipad", glass = G_DEEP, lit = LIT_COOL, litChance = 0.55 },
	{ name = "L6", x = -1512, z = -1082, w = 50, d = 44, h = 246, crown = "box", glass = G_SILVER, frame = F_LIGHT, lit = LIT_HOME, litChance = 0.55 },
	{ name = "L7_WarmFront", x = -1082, z = -962, w = 48, d = 42, h = 288, crown = "led", glass = G_BRONZE, lit = LIT_HOME, litChance = 0.7, led = P.LedGold, floorH = 6.5 },
	-- 주거 고층 (150~260)
	{ name = "LR1_Round", x = -1502, z = -822, w = 40, d = 40, h = 208, style = "round", crown = "led", glass = G_DEEP, lit = LIT_HOME, litChance = 0.6, led = P.LedGold, floorH = 6.5, glint = true },
	{ name = "LR2", x = -1420, z = -884, w = 42, d = 36, h = 182, crown = "frame", glass = G_SILVER, frame = F_LIGHT, lit = LIT_HOME, litChance = 0.6, led = P.LedGold, floorH = 6.5, glint = true },
	{ name = "LR3_Round", x = -1330, z = -804, w = 44, d = 44, h = 242, style = "round", crown = "led", glass = G_BLUE, lit = LIT_HOME, litChance = 0.6, led = P.LedCyan, floorH = 6.5, glint = true },
	{ name = "LR4", x = -1240, z = -902, w = 46, d = 38, h = 226, crown = "led", tiers = 2, glass = G_DEEP, lit = LIT_HOME, litChance = 0.6, led = P.LedGold, floorH = 6.5 },
	{ name = "LR5_Round", x = -1150, z = -822, w = 38, d = 38, h = 190, style = "round", crown = "box", glass = G_TEAL, lit = LIT_HOME, litChance = 0.6, floorH = 6.5, glint = true },
	{ name = "LR6", x = -962, z = -822, w = 44, d = 40, h = 252, crown = "frame", glass = G_BRONZE, frame = F_GOLD, lit = LIT_HOME, litChance = 0.6, led = P.LedGold, floorH = 6.5, glint = true },
	{ name = "LR7_Round", x = -862, z = -902, w = 42, d = 42, h = 204, style = "round", crown = "led", glass = G_DEEP, lit = LIT_HOME, litChance = 0.6, led = P.LedMagenta, floorH = 6.5 },
	{ name = "LR8", x = -1602, z = -962, w = 40, d = 40, h = 172, crown = "box", glass = G_DEEP, lit = LIT_HOME, litChance = 0.55, floorH = 6.5 },
	{ name = "LR9", x = -1352, z = -1002, w = 44, d = 40, h = 262, crown = "frame", glass = G_DEEP, frame = F_DARK, lit = LIT_HOME, litChance = 0.6, led = P.LedGold, floorH = 6.5 },
	{ name = "LR10", x = -1196, z = -1002, w = 40, d = 38, h = 214, yaw = 22, crown = "led", glass = G_BLUE, lit = LIT_HOME, litChance = 0.6, led = P.LedCyan, floorH = 6.5 },
	{ name = "LR11_Round", x = -822, z = -1042, w = 40, d = 40, h = 232, style = "round", crown = "led", glass = G_DEEP, lit = LIT_COOL, litChance = 0.55, led = P.LedGold },
}

-- 가운데(타워 뒤/오른쪽): 150~300 몇 동
local HERO_MID: { Entry } = {
	{ name = "M1", x = -150, z = -1262, w = 52, d = 46, h = 272, crown = "led", glass = G_DEEP, lit = LIT_COOL, litChance = 0.55, led = P.LedCyan },
	{ name = "M2_Lantern", x = -12, z = -1332, w = 48, d = 40, h = 232, crown = "frame", glass = NAVY, frame = F_GOLD, lit = LIT_GOLD, litChance = 0.55, led = P.LedGold, lantern = true },
	{ name = "M3_Round", x = 102, z = -1242, w = 40, d = 40, h = 182, style = "round", crown = "led", glass = G_BLUE, lit = LIT_HOME, litChance = 0.6, led = P.LedGold },
	{ name = "M4_Slant", x = -82, z = -1522, w = 58, d = 50, h = 302, crown = "slant", glass = INK, lit = LIT_COOL, litChance = 0.5, led = P.LedBlue },
	{ name = "M5", x = 72, z = -1622, w = 46, d = 44, h = 212, yaw = 90, crown = "box", glass = G_TEAL, lit = LIT_HOME, litChance = 0.55 },
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
		local p = cf * Vector3.new(s[1] * w / 2, 0, s[2] * d / 2)
		table.insert(out, p)
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
		{ Vector3.new(VP.DeckCenter.X, VP.DeckHeight + 8, VP.DeckCenter.Z), VP.HeroCamLook },
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
		local lo, hi = spanOf(cam, corners, CITY_Y, CITY_Y + h + 40)
		if lo < cam.hi and hi > cam.lo then
			return true
		end
	end
	return false
end

type FillOpts = {
	zone: { XMin: number, XMax: number, ZMin: number, ZMax: number },
	group: Instance,
	count: number,
	cx: number,
	cz: number,
	hMin: number,
	hMax: number,
	homeBias: number, -- 주거(따뜻한 조명) 비율
}

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

	-- 크라운 상단 높이(Facade.crown 과 같은 식) → 랜턴/조명 위치
	local function topWidth(e: Entry): (number, number)
		local k = 0.78 ^ (math.clamp(e.tiers or 1, 1, 3) - 1)
		return e.w * k, e.d * k
	end

	local function addExtras(m: Model, e: Entry, cf: CFrame)
		local h = e.h
		-- 포디움(저층부) : 로비/캐노피를 감싸는 어두운 기단 + 은은한 상가 불빛 띠
		if e.podium then
			local pw, pd, ph = e.w + 14, e.d + 14, 16
			Kit.box(m, cf * CFrame.new(0, ph / 2, 0), Vector3.new(pw, ph, pd), PODIUM, Enum.Material.Concrete, { name = "Podium" })
			Kit.box(m, cf * CFrame.new(0, 6.5, 0), Vector3.new(pw + 0.6, 3.2, pd + 0.6), rgb(150, 112, 70), Enum.Material.Neon, {
				name = "PodiumShops",
				collide = false,
				query = false,
				glow = true,
				dayMaterial = Enum.Material.Glass,
				dayColor = G_DEEP,
			})
		end
		local lightPart: BasePart? = nil
		-- frame 크라운 안의 금빛 랜턴 (프레임 안쪽 면에서 0.5 이상 떨어짐)
		if e.lantern and (e.crown == "frame") and (e.style or "curtain") == "curtain" then
			local tw, td = topWidth(e)
			local ph = math.clamp(h * 0.035, 4, 16)
			local fh = math.clamp(h * 0.08, 10, 34)
			local lh = fh - 3
			local lant = Kit.box(m, cf * CFrame.new(0, h + ph + 1.5 + lh / 2, 0), Vector3.new(tw - 5, lh, td * 0.6), LANTERN_GOLD, Enum.Material.Neon, {
				name = "Lantern",
				collide = false,
				query = false,
				glow = true,
				dayMaterial = Enum.Material.Glass,
				dayColor = NAVY,
			})
			lightPart = lant
		end
		-- 실제 광원: 크라운을 금빛으로 적시는 PointLight (예산 MAX_LIGHTS)
		if e.light and lightsLeft > 0 then
			local part = lightPart or m:FindFirstChild("Roof") :: BasePart?
			if part then
				local L = Kit.light(part, "PointLight", { color = e.led or P.LedGold, brightness = 2.2, range = 58 })
				if L then
					lightsLeft -= 1
				end
			end
		end
	end

	local function place(group: Instance, e: Entry, curated: boolean): Model?
		local yaw = e.yaw or 0
		local style = e.style or "curtain"
		if style == "round" then
			e.d = e.w
		end
		local pad = STREET_PAD + (if e.podium then 7 else 0)
		if blocksTower(cams, e.x, e.z, e.w + pad, e.d + pad, yaw, e.h) then
			if curated then
				warn("[Skyline] 타워 시야를 가려 생략: " .. e.name)
			end
			return nil
		end
		if curated and not Kit.isFreeRect(e.x, e.z, e.w, e.d, yaw, 0) then
			warn("[Skyline] 예약과 겹침: " .. e.name)
		end
		Kit.reserveRect(e.x, e.z, e.w + pad * 2, e.d + pad * 2, yaw, "Skyline")
		local cf = CFrame.new(e.x, CITY_Y, e.z) * CFrame.Angles(0, math.rad(yaw), 0)
		local m = Facade.tower(group, {
			name = e.name,
			cf = cf,
			w = e.w,
			d = e.d,
			h = e.h,
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
			glint = if e.glint ~= nil then e.glint else (e.z > GLINT_Z and math.abs(e.x - BRIDGE_X) > 70),
		})
		addExtras(m, e, cf)
		placed += 1
		return m
	end

	-- 1) 손으로 배치한 주요 실루엣 (높은 것부터 → 예약 우선)
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

	-- 2) 절차적 필: 클러스터 중심에 가까울수록 높게, 강 쪽 앞줄은 반사
	local GLASSES = { G_DEEP, G_BLUE, G_TEAL, INK, G_SILVER, G_BRONZE, NAVY }
	local CROWNS = { "box", "led", "led", "flat", "helipad", "frame", "slant", "box" }
	local LEDS = { P.LedGold, P.LedGold, P.LedCyan, P.LedBlue, P.LedGold }

	local function fill(o: FillOpts)
		local zn = o.zone
		local n, tries = 0, 0
		local maxR = math.max(zn.XMax - zn.XMin, zn.ZMax - zn.ZMin) * 0.6
		while n < o.count and tries < o.count * 40 do
			tries += 1
			local w = rng:NextInteger(30, 54)
			local d = rng:NextInteger(28, 50)
			local r = rng:NextNumber()
			local yaw = if r < 0.6 then 0 elseif r < 0.86 then 90 else (rng:NextInteger(15, 30) * (if rng:NextNumber() < 0.5 then -1 else 1))
			local x = rng:NextNumber(zn.XMin + 30, zn.XMax - 30)
			local z = rng:NextNumber(zn.ZMin + 30, zn.ZMax - 30)
			local front = z > GLINT_Z
			if front and math.abs(x - BRIDGE_X) < BRIDGE_CLEAR then
				continue
			end
			if not Kit.isFreeRect(x, z, w + STREET_PAD * 2, d + STREET_PAD * 2, yaw, FILL_GAP) then
				continue
			end
			local t = math.clamp(math.sqrt((x - o.cx) ^ 2 + (z - o.cz) ^ 2) / maxR, 0, 1)
			local h = math.floor((o.hMax + (o.hMin - o.hMax) * t) * rng:NextNumber(0.78, 1.08))
			local home = rng:NextNumber() < o.homeBias
			local styleR = rng:NextNumber()
			local style = if styleR < 0.22 then "round" elseif (not front and styleR > 0.8) then "mid" else "curtain"
			local e: Entry = {
				name = string.format("Fill_%d", placed + 1),
				x = x,
				z = z,
				w = w,
				d = d,
				h = h,
				yaw = yaw,
				style = style,
				crown = CROWNS[rng:NextInteger(1, #CROWNS)],
				glass = GLASSES[rng:NextInteger(1, #GLASSES)],
				lit = if home then LIT_HOME else LIT_COOL,
				litChance = rng:NextNumber(0.45, 0.65),
				led = LEDS[rng:NextInteger(1, #LEDS)],
				floorH = if home then 6.5 else 8,
				tiers = if h > 220 and rng:NextNumber() < 0.4 then 2 else 1,
			}
			if style == "round" then
				e.w = math.min(w, d) + 6
				e.crown = if e.crown == "led" or e.crown == "box" then e.crown else "led"
			end
			if place(o.group, e, false) then
				n += 1
			end
		end
	end

	fill({ zone = Z.SkylineRight, group = gRight, count = 16, cx = 700, cz = -1100, hMin = 110, hMax = 250, homeBias = 0.35 })
	fill({ zone = Z.SkylineLeft, group = gLeft, count = 18, cx = -1100, cz = -1100, hMin = 110, hMax = 230, homeBias = 0.6 })
	fill({ zone = Z.SkylineMid, group = gMid, count = 6, cx = -40, cz = -1450, hMin = 120, hMax = 200, homeBias = 0.4 })

	ctx.model:SetAttribute("Buildings", placed)
	ctx.model:SetAttribute("Lights", MAX_LIGHTS - lightsLeft)
end

return Skyline
