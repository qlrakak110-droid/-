--!strict
-- SeoulSkyline / Landmark
-- 롯데월드타워 모티브 초고층 + 저층 몰(파란 곡면 지붕 홀) + 타워 광장 + 수면 반사.
-- 실제 스케일(1 stud = 0.3 m): 모든 치수는 Config.m(미터) / Config.Real 로 계산하고, 위치는 Config 에서 유도.
--
-- 타워 (Config.Landmark.Tower: 지상부 87 m → 크라운 32 m, 본체 450 m + 크라운 78 m + 첨탑 27 m = 555 m):
--   * 로비 13.5 m(유리 상자 + 3 m 간격 멀리언 + 메자닌 띠) → 그 위 오피스/호텔 층 ≈ 105개(층고 ≈ 4.2 m).
--   * 3개 층 = 1 세그먼트: 안쪽 Neon 조명 코어 1개 + 층마다 바깥 반사 유리 슬래브 링(층 줄무늬).
--     단면은 "십자 블록 2 + 모서리 원기둥 4" 로 만든 정확한 둥근 정사각형(보이는 면끼리 겹침 없음).
--     코어는 바로 위 슬래브보다 CORE_INSET 만큼 들어가 있어 금빛 실내 + 은청색 유리의 가는 층 줄무늬가 됨.
--     9 세그먼트마다 어두운 피난/기계층 띠.
--   * 면 중앙 금빛 솔기: 건물을 관통하는 얇은 Neon 핀 1개가 마주 보는 두 면에 동시에 세로선을 그림.
--   * 랜턴 크라운: 계속 가늘어지는 4면 위 다이아몬드 격자 리브(Neon) + 안쪽 등불 + 첨탑 + 항공장애등.
--   폭 곡선 w(t) = Top + (Base - Top)(1 - t^p): 중간이 살짝 불룩하고 꼭대기로 갈수록 빠르게 가늘어짐.
-- 몰 (Config.Landmark.Mall): 8~12층(35~50 m) Facade 커튼월 블록들 + 높이 27 m 의 파란 곡면 지붕 홀.
-- 광장: 도시 지면 포장 + 타워 둘레 돌띠/빛띠 + 7 m 가로등 + 화단 + 8~12 m 나무 + 5.5 m 캐노피.
-- 모든 발자국은 Kit.reserve 로 예약.

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)
local Facade = require(script.Parent.Facade)

local Landmark = {}

local P = Config.Palette
local T = Config.Landmark.Tower
local M = Config.Landmark.Mall
local CITY_Y = Config.Level.City
local m2s = Config.m -- 미터 → stud
local rgb = Color3.fromRGB

------------------------------------------------------------------------------------------------------
-- 상수 (실측 m → stud)
------------------------------------------------------------------------------------------------------
-- 타워 본체
local FLOOR_TARGET = m2s(4.2) -- 초고층 오피스/호텔 층고
local FLOORS_PER_SEG = 3 -- 조명 코어 하나가 묶는 층 수 (파트 예산)
local LOBBY_H = m2s(13.5) -- 지면 → 첫 오피스 층 슬래브 (로비 2개 층 높이)
local PLINTH_H = m2s(0.36) -- 화강석 기단 (포장보다 0.8 stud 높은 낮은 단)
local TAPER_POW = 1.4 -- >1 : 중간이 불룩, 꼭대기 쪽에서 빠르게 가늘어짐
local CORNER_R = 0.12 -- 모서리 반경 / 폭
local SLAB_RATIO = 0.46 -- 층 높이 중 유리 슬래브(스팬드럴) 비율 → 1.9 m 띠 + 2.3 m 창
local CORE_INSET = m2s(0.3) -- 코어가 바로 위 슬래브보다 들어간 깊이
local SEAM_W = m2s(2.0) -- 면 중앙 솔기 폭
local SEAM_FROM = 0.1 -- 솔기가 시작하는 높이(비율)
local REFUGE_EVERY = 9 -- 이 세그먼트마다 어두운 피난/기계층
-- 크라운
local CROWN_BASE_RATIO = 0.92 -- 크라운 시작 폭 / TopWidth (둥근 모서리 안쪽에 리브가 앉도록)
local CROWN_TOP_RATIO = 0.32 -- 크라운 꼭대기 폭 / TopWidth (뾰족한 실루엣)
local CROWN_TIERS = 5
local RIB_W, RIB_D = m2s(0.8), m2s(0.6)
-- 사람 스케일
local PAVE_UP = 0.4 -- 포장 윗면 = 도시 지면 + 0.4 (겹치는 면 없음)
local CANOPY_CLEAR = m2s(5.5) -- 출입구 캐노피 하부 높이
local CANOPY_T = m2s(0.5)
local LAMP_H = m2s(7) -- 광장 가로등
local PLANTER_H = m2s(0.55) -- 앉을 수 있는 화단 턱
-- 색
local GLASS = P.GlassBlue:Lerp(P.GlassSilver, 0.25) -- 은청색 반사 유리(하늘을 비춰 밝아 보이므로 조금 어둡게)
local SEAM_C = rgb(236, 188, 114)
local RIB_C = rgb(178, 160, 128) -- 블룸이 켜져 있으므로 격자는 중간 밝기
local RIB_CORNER_C = rgb(214, 196, 158)
local LANTERN_C = rgb(92, 78, 60)
local LOBBY_C = rgb(214, 160, 92)
local CORE_PAL = { P.WindowWarm, P.WindowWarm, P.WindowGold, P.WindowGold, P.WindowWarmDim, P.WindowWarmDim, rgb(255, 178, 92), P.WindowCoolDim, P.WindowCool }
local MALL_LIT = { rgb(156, 112, 66), rgb(140, 100, 60), rgb(168, 128, 80), rgb(120, 96, 70), rgb(104, 118, 142) }
local DOME_C = rgb(52, 98, 178)
local DOME_RIB_C = rgb(120, 182, 255)
local PAVE_C = rgb(118, 116, 112)

-- 실내 연결부 (LandmarkInterior 가 Landmark.layout 으로 받아 실내를 채움)
--   로비 홀: 정면(+Z 로컬 면 = 강/히어로 쪽) 가운데 32 × 25 m, 천장 13.5 m. 뒷벽 가운데 엘리베이터 알코브 8.4 × 10 m, 천장 4.2 m.
local LOBBY_HALL_W = m2s(32)
local LOBBY_HALL_D = m2s(25)
local LOBBY_ALCOVE_W = m2s(8.4)
local LOBBY_ALCOVE_D = m2s(10)
local LOBBY_FLOOR = PLINTH_H + 0.3 -- 로비 바닥 마감 윗면 (기단 + 0.3)
local LOBBY_ALCOVE_TOP = LOBBY_FLOOR + m2s(4.2) + 2.2 -- 알코브 천장고 4.2 m + 천장 마감 공간
local DOOR_W, DOOR_H = m2s(2.4), m2s(2.7) -- 자동 미닫이문 유효 폭 2.4 m, 높이 2.7 m
--   서울스카이 전망대: 본체 꼭대기 2 세그먼트(≈ 25 m)를 유리 커튼월 2개 층(118F 전망대 / 123F 라운지)으로
local OBS_SEGS = 2
local OBS_SLAB_MID = m2s(2.4) -- 두 층 사이 슬래브(라운지 바닥)
local OBS_SLAB_TOP = m2s(3.3) -- 라운지 위 슬래브(크라운 데크 아래)
local OBS_GLASS_IN = 0.6 -- 유리면이 바로 위 슬래브보다 들어간 깊이
local OBS_GLASS_T = 0.4
local OBS_GLASS_C = rgb(196, 208, 218)
local OBS_PIT_W, OBS_PIT_D, OBS_PIT_GAP = m2s(7.2), m2s(3.6), m2s(1.0) -- 스카이데크 유리 바닥 7.2 × 3.6 m, 창에서 1 m
--   몰 홀(파란 곡면 지붕): 가운데 2개 층 갤러리아(아트리움) 66 × 21.6 m + 양쪽 상점 + 정면 입구 통로
local HALL_GX = m2s(33) -- 갤러리아 반길이(X)
local HALL_GZ = m2s(10.8) -- 갤러리아 반폭(상점 전면선)
local HALL_VZ = m2s(6.6) -- 보이드 반폭(메자닌 난간선)
local HALL_SD = m2s(18.6) -- 상점 뒷벽
local HALL_SHOPS = 7 -- 한 줄 상점 수 (가운데 칸 = 정면 입구 통로)
local HALL_FY1 = PAVE_UP + 0.3 -- 1층 바닥 마감 윗면
local HALL_FY2 = HALL_FY1 + m2s(6) -- 2층(메자닌) 바닥 윗면, 층고 6 m
local HALL_ET = HALL_FY2 - 3 -- 입구 통로 천장 구조 하단
local HALL_ST = HALL_FY2 + m2s(4.5) + 0.8 -- 2층 상점 천장 위

local CYL_UP = CFrame.Angles(0, 0, math.rad(90))
local CORNERS = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

type PartOpts = Kit.PartOpts
type OptFn = (c: Color3, cyl: boolean) -> PartOpts

local function scale(c: Color3, k: number): Color3
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

local function widthAt(y: number): number
	local t = math.clamp(y / T.Height, 0, 1.05)
	return T.TopWidth + (T.BaseWidth - T.TopWidth) * (1 - t ^ TAPER_POW)
end

------------------------------------------------------------------------------------------------------
-- 파트 옵션
------------------------------------------------------------------------------------------------------
local function slabOpts(collide: boolean): OptFn
	return function(c: Color3, cyl: boolean): PartOpts
		return {
			name = "Slab",
			shape = if cyl then "Cylinder" else "Block",
			material = Enum.Material.Glass,
			color = c,
			-- 둥근 모서리(원기둥)는 어떤 태양 각도에서도 정반사 점이 생겨 블룸이 번지므로 반사율을 낮춤
			reflectance = if cyl then 0.06 else 0.2,
			collide = collide,
			query = collide,
			shadow = false,
		}
	end
end

local function neonOpts(name: string, dayMat: Enum.Material, dayColor: Color3, collide: boolean?): OptFn
	local col = collide == true
	return function(c: Color3, cyl: boolean): PartOpts
		return {
			name = name,
			shape = if cyl then "Cylinder" else "Block",
			material = Enum.Material.Neon,
			color = c,
			collide = col,
			query = col,
			shadow = false,
			glow = true,
			dayMaterial = dayMat,
			dayColor = dayColor,
		}
	end
end

-- 둥근 모서리 정사각 단면 프리즘: 십자 블록 2 + 모서리 원기둥 4 (cf = 중심, 로컬 Y = 높이)
-- cA: ±X 면, cB: ±Z 면, cC: 모서리
local function rsquare(parent: Instance, cf: CFrame, w: number, h: number, r: number, cA: Color3, cB: Color3, cC: Color3, mk: OptFn)
	local rr = math.clamp(r, 0.4, w * 0.45)
	Kit.part(parent, cf, Vector3.new(w, h, w - 2 * rr), mk(cA, false))
	Kit.part(parent, cf, Vector3.new(w - 2 * rr, h, w), mk(cB, false))
	local o = w / 2 - rr
	for _, s in CORNERS do
		Kit.part(parent, cf * CFrame.new(s[1] * o, 0, s[2] * o) * CYL_UP, Vector3.new(h, 2 * rr, 2 * rr), mk(cC, true))
	end
end

-- 둥근 정사각 프리즘에서 축 정렬 직사각형 구멍(로컬 x0..x1, z0..z1; |x| <= w/2 - r 안쪽, z 는 면까지 가능)을 뺀 조각들.
-- 조각끼리는 맞닿기만 하고(같은 색) 보이는 면이 겹치지 않음.
local function rsquareCut(parent: Instance, cf: CFrame, w: number, h: number, r: number, hole: { number }, c: Color3, mk: OptFn)
	local rr = math.clamp(r, 0.4, w * 0.45)
	local W = w / 2
	local o = W - rr
	local hx0, hx1, hz0, hz1 = hole[1], hole[2], hole[3], hole[4]
	local function blk(x0: number, x1: number, z0: number, z1: number)
		if x1 - x0 > 0.05 and z1 - z0 > 0.05 then
			Kit.part(parent, cf * CFrame.new((x0 + x1) / 2, 0, (z0 + z1) / 2), Vector3.new(x1 - x0, h, z1 - z0), mk(c, false))
		end
	end
	blk(-W, -o, -o, o)
	blk(o, W, -o, o)
	blk(-o, hx0, -W, W)
	blk(hx1, o, -W, W)
	blk(hx0, hx1, -W, hz0)
	blk(hx0, hx1, hz1, W)
	for _, s in CORNERS do
		Kit.part(parent, cf * CFrame.new(s[1] * o, 0, s[2] * o) * CYL_UP, Vector3.new(h, 2 * rr, 2 * rr), mk(c, true))
	end
end
Landmark.rsquareCut = rsquareCut
Landmark.rsquare = rsquare

-- a → b 를 잇는 얇은 Neon 리브. up = 리브 두께 방향 힌트(면 법선)
local function rib(parent: Instance, a: Vector3, b: Vector3, w: number, d: number, up: Vector3, c: Color3, name: string): BasePart
	local len = (b - a).Magnitude + w * 0.5
	return Kit.part(parent, CFrame.lookAt((a + b) / 2, b, up), Vector3.new(w, d, len), {
		name = name,
		material = Enum.Material.Neon,
		color = c,
		collide = false,
		query = false,
		shadow = false,
		glow = true,
		dayMaterial = Enum.Material.Metal,
		dayColor = P.MullionLight,
	})
end

-- 출입구 캐노피(하부 CANOPY_CLEAR) + 아래 조명 띠 (+ 선택: 기둥, 광원). cf = 캐노피 앞 중심의 바닥(포장 윗면), 로컬 +Z = 바깥.
local function canopy(m: Model, cf: CFrame, w: number, d: number, posts: boolean, light: boolean)
	local cy = CANOPY_CLEAR + CANOPY_T / 2
	Kit.box(m, cf * CFrame.new(0, cy, d / 2), Vector3.new(w, CANOPY_T, d), P.ConcreteDark, Enum.Material.Metal, { name = "Canopy", collide = true })
	-- 조명 띠: 캐노피 아랫면에서 0.35 stud 떨어져 겹침 없음
	local strip = Kit.box(m, cf * CFrame.new(0, CANOPY_CLEAR - 0.35 - 0.15, d / 2 + 0.3), Vector3.new(w - m2s(1.5), 0.3, d - m2s(1.6)), P.WindowWarm, Enum.Material.Neon, {
		name = "CanopyLight",
		collide = false,
		query = false,
		glow = true,
		dayMaterial = Enum.Material.SmoothPlastic,
		dayColor = P.ConcreteLight,
	})
	if light then
		Kit.light(strip, "PointLight", { color = P.LampWarm, brightness = 1.6, range = 50 })
	end
	if posts then
		for _, sx in { -1, 1 } do
			Kit.part(m, cf * CFrame.new(sx * (w / 2 - m2s(1.2)), CANOPY_CLEAR / 2, d - m2s(1.0)) * CYL_UP, Vector3.new(CANOPY_CLEAR, m2s(0.45), m2s(0.45)), {
				name = "CanopyPost",
				shape = "Cylinder",
				material = Enum.Material.Metal,
				color = P.Mullion,
				collide = true,
			})
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 타워 본체
------------------------------------------------------------------------------------------------------
local function coreColor(rng: Random, t: number, faceK: number, refuge: boolean): Color3
	local c = CORE_PAL[rng:NextInteger(1, #CORE_PAL)]
	local k = faceK * rng:NextNumber(0.5, 0.82)
	if rng:NextNumber() < 0.12 then
		k *= 0.5 -- 드문드문 불 꺼진 층 묶음
	end
	if refuge then
		k *= 0.42 -- 피난/기계층 띠
	end
	if t > 0.86 then
		k *= 0.72 -- 꼭대기 근처: 호텔/전망대 아래 어두운 유리
	end
	return scale(c, k)
end

------------------------------------------------------------------------------------------------------
-- 서울스카이 전망대 띠 (꼭대기 2 세그먼트): 슬래브 A(바닥, 스카이데크 구멍) / 118F 유리 / 슬래브 B / 123F 유리 / 슬래브 C
-- 층 사이 조명 코어 대신 바닥부터 천장까지 투명 유리 커튼월 + 1.8 m 간격 슬림 멀리언 → 밤에는 밝은 유리 띠로 읽힘.
------------------------------------------------------------------------------------------------------
local function glassBand(m: Model, TF: CFrame, yb: number, yt: number, w: number, seamMk: OptFn)
	local h = yt - yb + 0.6 -- 위아래 슬래브 속으로 0.3 씩
	local yc = (yb + yt) / 2
	local r = w * CORNER_R
	local W = w / 2
	local o = W - r
	local t = OBS_GLASS_T
	local gO: PartOpts = { name = "ObsGlass", material = Enum.Material.Glass, color = OBS_GLASS_C, transparency = 0.66, reflectance = 0.05, collide = true, shadow = false }
	local mO: PartOpts = { name = "ObsMullion", material = Enum.Material.Metal, color = P.Mullion, collide = false, query = false, shadow = false }
	local n = math.max(2, math.floor(2 * o / m2s(1.8) + 0.5))
	if n % 2 == 1 then
		n += 1 -- 면 가운데 = 솔기 자리
	end
	local da = math.pi / 6
	local fw = 2 * r * math.sin(da / 2)
	for f = 0, 3 do
		local FR = TF * CFrame.Angles(0, f * math.pi / 2, 0)
		Kit.part(m, FR * CFrame.new(0, yc, W - t / 2), Vector3.new(2 * o + 0.1, h, t), gO)
		for i = 0, n do
			if i ~= n / 2 then
				Kit.part(m, FR * CFrame.new(-o + i * 2 * o / n, yc, W - 0.15), Vector3.new(0.35, h, 1.2), mO)
			end
		end
		local CC = FR * CFrame.new(o, yc, o)
		for k = 0, 2 do
			Kit.part(m, CC * CFrame.Angles(0, (k + 0.5) * da, 0) * CFrame.new(0, 0, r * math.cos(da / 2) - t / 2), Vector3.new(fw + 0.15, h, t), gO)
		end
		for k = 1, 2 do
			Kit.part(m, CC * CFrame.Angles(0, k * da, 0) * CFrame.new(0, 0, r - 0.15), Vector3.new(0.35, h, 1.2), mO)
		end
		-- 솔기: 유리 밖 가는 금빛 선(0.3 m) + 안쪽 어두운 덮개(실내에서는 멀리언처럼 보임)
		Kit.part(m, FR * CFrame.new(0, yc, W + 0.08), Vector3.new(1.2, h - 0.6, 0.12), mO)
		Kit.part(m, FR * CFrame.new(0, yc, W + 0.65), Vector3.new(1.0, h - 0.6, 1.0), seamMk(SEAM_C, false))
	end
end

local function buildObservatory(m: Model, TF: CFrame, y0: number, slabH: number, seamMk: OptFn): { [string]: any }
	local H = T.Height
	local yA = y0 + slabH -- 118F 바닥(슬래브 A 윗면)
	local rest = H - yA - OBS_SLAB_MID - OBS_SLAB_TOP
	local yA1 = yA + rest * 0.52 -- 118F 천장(슬래브 B 아랫면): 약 9 m 2개 층 높이 전망 홀
	local yB = yA1 + OBS_SLAB_MID -- 123F 라운지 바닥
	local yB1 = H - OBS_SLAB_TOP -- 라운지 천장
	local wB = widthAt(yA1 + OBS_SLAB_MID / 2)
	local wC = widthAt(yB1 + OBS_SLAB_TOP / 2)
	local gw1 = wB - 2 * OBS_GLASS_IN
	local gw2 = wC - 2 * OBS_GLASS_IN
	-- 슬래브 A (스카이데크 유리 바닥 구멍)
	local wA = widthAt(y0 + slabH / 2)
	local pz1 = gw1 / 2 - OBS_PIT_GAP
	local pit = { -OBS_PIT_W / 2, OBS_PIT_W / 2, pz1 - OBS_PIT_D, pz1 }
	rsquareCut(m, TF * CFrame.new(0, y0 + slabH / 2, 0), wA, slabH, wA * CORNER_R, pit, GLASS, slabOpts(true))
	rsquare(m, TF * CFrame.new(0, yA1 + OBS_SLAB_MID / 2, 0), wB, OBS_SLAB_MID, wB * CORNER_R, GLASS, GLASS, GLASS, slabOpts(true))
	rsquare(m, TF * CFrame.new(0, yB1 + OBS_SLAB_TOP / 2, 0), wC, OBS_SLAB_TOP, wC * CORNER_R, GLASS, GLASS, GLASS, slabOpts(true))
	-- 슬래브 솔기: A 는 면마다(구멍을 지나지 않게), B·C 는 관통 핀(슬래브 속에 숨음)
	for f = 0, 3 do
		local FR = TF * CFrame.Angles(0, f * math.pi / 2, 0)
		Kit.part(m, FR * CFrame.new(0, y0 + slabH / 2, wA / 2 + 0.05), Vector3.new(SEAM_W, slabH - 0.4, 1.3), seamMk(SEAM_C, false))
	end
	for _, s in { { yA1 + OBS_SLAB_MID / 2, OBS_SLAB_MID, wB }, { yB1 + OBS_SLAB_TOP / 2, OBS_SLAB_TOP, wC } } do
		local cf = TF * CFrame.new(0, s[1], 0)
		Kit.part(m, cf, Vector3.new(SEAM_W, s[2] - 0.4, s[3] + 1.4), seamMk(SEAM_C, false))
		Kit.part(m, cf, Vector3.new(s[3] + 1.4, s[2] - 0.4, SEAM_W), seamMk(SEAM_C, false))
	end
	glassBand(m, TF, yA, yA1, gw1, seamMk)
	glassBand(m, TF, yB, yB1, gw2, seamMk)
	return { y0 = y0, yA = yA, yA1 = yA1, yB = yB, yB1 = yB1, gw1 = gw1, gw2 = gw2, glassT = OBS_GLASS_T, pit = pit, cornerR = CORNER_R }
end

local function buildShaft(m: Model, TF: CFrame, rng: Random): (number, { [string]: any })
	local H = T.Height
	local shaftH = H - LOBBY_H
	local nSeg = math.max(1, math.floor(shaftH / (FLOOR_TARGET * FLOORS_PER_SEG) + 0.5))
	local hs = shaftH / nSeg
	local floorH = hs / FLOORS_PER_SEG -- ≈ 4.16 m
	local slabH = floorH * SLAB_RATIO
	local coreMk = neonOpts("Core", Enum.Material.Glass, P.GlassBlue)
	local seamMk = neonOpts("Seam", Enum.Material.Metal, P.MullionLight)
	local obsFrom = nSeg - OBS_SEGS
	for k = 0, nSeg - 1 do
		local y0 = LOBBY_H + k * hs
		local y1 = y0 + hs
		local t = (y0 + hs / 2) / H
		if k >= obsFrom then
			-- 전망대 띠(buildObservatory)가 대신함. rng 소비만 맞춰 아래 몰/광장 배치를 그대로 유지.
			local refuge = (k % REFUGE_EVERY) == REFUGE_EVERY - 1
			coreColor(rng, t, 1.0, refuge)
			coreColor(rng, t, 0.7, refuge)
			continue
		end
		-- 1) 층 슬래브(반사 유리 링) — 층마다 하나
		local wsMax = 0
		for j = 0, FLOORS_PER_SEG - 1 do
			local yc = y0 + j * floorH + slabH / 2
			local ws = widthAt(yc)
			wsMax = math.max(wsMax, ws)
			rsquare(m, TF * CFrame.new(0, yc, 0), ws, slabH, ws * CORNER_R, GLASS, GLASS, GLASS, slabOpts(j == 0))
		end
		-- 2) 조명 코어: 이 세그먼트 위의(더 좁은) 슬래브 기준으로 inset → 모든 슬래브보다 안쪽
		local wTop = widthAt(y1 + slabH / 2)
		local refuge = (k % REFUGE_EVERY) == REFUGE_EVERY - 1
		local cA, cB = coreColor(rng, t, 1.0, refuge), coreColor(rng, t, 0.7, refuge) -- ±Z 면은 어둡게(면 대비)
		rsquare(m, TF * CFrame.new(0, (y0 + y1) / 2, 0), wTop - 2 * CORE_INSET, hs, wTop * CORNER_R - CORE_INSET, cA, cB, cA:Lerp(cB, 0.5), coreMk)
		-- 3) 면 중앙 솔기 (관통 핀 2개 → 4면)
		if y0 >= H * SEAM_FROM then
			local L = wsMax + 1.4
			local cf = TF * CFrame.new(0, (y0 + y1) / 2, 0)
			Kit.part(m, cf, Vector3.new(SEAM_W, hs, L), seamMk(SEAM_C, false))
			Kit.part(m, cf, Vector3.new(L, hs, SEAM_W), seamMk(SEAM_C, false))
		end
	end
	-- 항공장애등: 중간 높이 모서리 4개
	local yb = H * 0.56
	local ws = widthAt(yb)
	local r = ws * CORNER_R
	local diag = (ws / 2 - r) * math.sqrt(2) + r + 2
	for i = 0, 3 do
		local a = i * math.pi / 2
		Kit.beacon(m, (TF * CFrame.Angles(0, a + math.pi / 4, 0) * CFrame.new(0, yb, diag)).Position, 5)
	end
	local obs = buildObservatory(Kit.group(m, "SeoulSkyShell"), TF, LOBBY_H + obsFrom * hs, slabH, seamMk)
	return nSeg * FLOORS_PER_SEG, obs
end

------------------------------------------------------------------------------------------------------
-- 로비 / 기단 / 캐노피
------------------------------------------------------------------------------------------------------
local function buildBase(m: Model, TF: CFrame): { [string]: any }
	-- 화강석 기단 (포장 위로 0.8 stud 낮은 단: 아바타가 걸어 오를 수 있음)
	local pw = T.BaseWidth + m2s(8)
	rsquare(m, TF * CFrame.new(0, PLINTH_H / 2, 0), pw, PLINTH_H, pw * CORNER_R, P.ConcreteGrey, P.ConcreteGrey, P.ConcreteGrey, function(c: Color3, cyl: boolean): PartOpts
		return { name = "Plinth", shape = if cyl then "Cylinder" else "Block", material = Enum.Material.Slate, color = c, collide = true, shadow = false }
	end)
	-- 로비 유리 상자(금빛 발광, 13.5 m): 첫 슬래브보다 1.5 m 안쪽.
	-- 정면(+Z) 가운데는 걸어 들어갈 수 있는 로비 홀(32 × 25 m, 천장 13.5 m) + 뒷벽 엘리베이터 알코브로 비워 둠.
	-- 나머지는 이전처럼 금빛 발광 덩어리(코어/후방 공간) — 조각끼리 맞닿기만 함.
	local w0 = widthAt(LOBBY_H)
	local inset = m2s(1.5)
	local wl = w0 - 2 * inset
	local rl = w0 * CORNER_R - inset
	local lh = LOBBY_H - PLINTH_H
	local ly = PLINTH_H + lh / 2
	local W = wl / 2
	local rr = math.clamp(rl, 0.4, wl * 0.45)
	local o = W - rr
	local HX = LOBBY_HALL_W / 2
	local ZB = W - LOBBY_HALL_D
	local AX = LOBBY_ALCOVE_W / 2
	local AZ0 = ZB - LOBBY_ALCOVE_D
	local lobbyMk = neonOpts("Lobby", Enum.Material.Glass, P.GlassSilver, true)
	local function vol(x0: number, x1: number, z0: number, z1: number, y0: number, y1: number)
		Kit.part(m, TF * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), Vector3.new(x1 - x0, y1 - y0, z1 - z0), lobbyMk(LOBBY_C, false))
	end
	vol(-W, -o, -o, o, PLINTH_H, LOBBY_H)
	vol(o, W, -o, o, PLINTH_H, LOBBY_H)
	vol(-o, -HX, -W, W, PLINTH_H, LOBBY_H)
	vol(HX, o, -W, W, PLINTH_H, LOBBY_H)
	vol(-HX, -AX, -W, ZB, PLINTH_H, LOBBY_H)
	vol(AX, HX, -W, ZB, PLINTH_H, LOBBY_H)
	vol(-AX, AX, -W, AZ0, PLINTH_H, LOBBY_H)
	vol(-AX, AX, AZ0, ZB, LOBBY_ALCOVE_TOP, LOBBY_H)
	for _, s in CORNERS do
		Kit.part(m, TF * CFrame.new(s[1] * o, ly, s[2] * o) * CYL_UP, Vector3.new(lh, 2 * rr, 2 * rr), lobbyMk(LOBBY_C, true))
	end
	-- 메자닌 띠 (6.5 m): 로비가 2개 층 높이로 읽히게. 홀을 가로지르지 않도록 외곽 링(면 4 + 모서리 원기둥 4)으로.
	local my = PLINTH_H + m2s(6.5)
	local bandMk = slabOpts(false)
	for f = 0, 3 do
		local FR = TF * CFrame.Angles(0, f * math.pi / 2, 0)
		Kit.part(m, FR * CFrame.new(0, my, W + 0.2), Vector3.new(2 * o, m2s(0.7), 1.6), bandMk(GLASS, false))
	end
	for _, s in CORNERS do
		Kit.part(m, TF * CFrame.new(s[1] * o, my, s[2] * o) * CYL_UP, Vector3.new(m2s(0.7), 2 * (rr + 1), 2 * (rr + 1)), bandMk(GLASS, true))
	end
	-- 로비 멀리언(3 m 간격): 면마다 짧은 핀(유리 안팎 0.4 m) — 홀 안을 가로지르지 않음
	local span = wl / 2 - rl - m2s(0.6)
	local n = math.max(1, math.floor(span * 2 / m2s(3)))
	if n % 2 == 0 then
		n += 1 -- 정면 가운데가 유리 칸(양옆 칸에 문)
	end
	local step = span * 2 / n
	local finO: PartOpts = { name = "LobbyFin", material = Enum.Material.Metal, color = P.Mullion, collide = false, query = false, shadow = false }
	for f = 0, 3 do
		local FR = TF * CFrame.Angles(0, f * math.pi / 2, 0)
		for i = 0, n do
			Kit.part(m, FR * CFrame.new(-span + i * step, ly, W - 0.3), Vector3.new(m2s(0.25), lh, 2.0), finO)
		end
	end
	-- 홀 정면 유리(두께 0.4, 투명) + 자동문 2곳(멀리언 사이 칸, 유효 폭 2.4 m × 2.7 m) 위 트랜섬/문틀 헤더
	local gz = W - 0.3
	local doorXs = { -step, step }
	local glassO: PartOpts = { name = "LobbyGlass", material = Enum.Material.Glass, color = rgb(176, 194, 208), transparency = 0.62, reflectance = 0.06, collide = true, shadow = false }
	local gy0, gy1 = PLINTH_H - 0.3, LOBBY_H + 0.3
	local function pane(x0: number, x1: number, y0: number, y1: number)
		Kit.part(m, TF * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, gz), Vector3.new(x1 - x0, y1 - y0, OBS_GLASS_T), glassO)
	end
	local dTop = LOBBY_FLOOR + DOOR_H
	pane(-HX, doorXs[1] - DOOR_W / 2, gy0, gy1)
	pane(doorXs[1] + DOOR_W / 2, doorXs[2] - DOOR_W / 2, gy0, gy1)
	pane(doorXs[2] + DOOR_W / 2, HX, gy0, gy1)
	for _, dx in doorXs do
		pane(dx - DOOR_W / 2, dx + DOOR_W / 2, dTop + 0.8, gy1)
		Kit.box(m, TF * CFrame.new(dx, dTop + 0.45, gz - 0.25), Vector3.new(DOOR_W + 0.6, 0.9, 1.3), P.Mullion, Enum.Material.Metal, { name = "DoorHeader", collide = true, shadow = false })
	end
	-- 각 면 중앙 출입구 캐노피(16 m × 8 m, 하부 5.5 m) + 조명 띠 + 기둥 + 실제 광원
	for f = 0, 3 do
		local FR = TF * CFrame.Angles(0, f * math.pi / 2, 0)
		canopy(m, FR * CFrame.new(0, PAVE_UP, wl / 2 - 1), m2s(16), m2s(8), true, true)
	end
	return {
		W = W, -- 로비 외곽 반폭(정면 유리 바깥면)
		HX = HX, -- 홀 반폭
		ZB = ZB, -- 홀 뒷벽
		AX = AX, -- 알코브 반폭
		AZ0 = AZ0, -- 알코브 안쪽 끝벽
		alcoveTop = LOBBY_ALCOVE_TOP,
		plinthY = PLINTH_H,
		floorY = LOBBY_FLOOR,
		ceilY = LOBBY_H,
		glassZ = gz,
		doorXs = doorXs,
		doorW = DOOR_W,
		doorH = DOOR_H,
		mezzY = my,
		finStep = step,
		finSpan = span,
	}
end

------------------------------------------------------------------------------------------------------
-- 랜턴 크라운 + 첨탑
------------------------------------------------------------------------------------------------------
local function buildCrown(m: Model, TF: CFrame)
	local H = T.Height
	-- 본체 마감 데크
	local wd = widthAt(H) + 1
	rsquare(m, TF * CFrame.new(0, H + 1, 0), wd, 2, wd * CORNER_R, GLASS, GLASS, GLASS, slabOpts(true))
	local yc0 = H + 2
	local CHc = T.CrownHeight - 2
	local function cw(u: number): number
		local a = u / CHc
		return T.TopWidth * (CROWN_BASE_RATIO + (CROWN_TOP_RATIO - CROWN_BASE_RATIO) * a)
	end
	-- 안쪽 등불(아래 2단): 격자 사이로 은은하게
	for i = 0, 1 do
		local u0, u1 = i * CHc / CROWN_TIERS, (i + 1) * CHc / CROWN_TIERS
		local dia = cw(u1) * 0.55
		local c = scale(LANTERN_C, 1 + i * 0.15)
		local p = Kit.part(m, TF * CFrame.new(0, yc0 + (u0 + u1) / 2, 0) * CYL_UP, Vector3.new(u1 - u0, dia, dia), neonOpts("Lantern", Enum.Material.Glass, P.GlassSilver)(c, true))
		Kit.light(p, "PointLight", { color = P.LampWarm, brightness = 1.8, range = 60 })
	end
	-- 4면 격자 리브
	for f = 0, 3 do
		local FR = TF * CFrame.Angles(0, f * math.pi / 2, 0)
		local nrm = FR:VectorToWorldSpace(Vector3.zAxis)
		local function pt(x: number, u: number): Vector3
			local hw = cw(u) / 2
			return FR * Vector3.new(x * hw, yc0 + u, hw)
		end
		for i = 0, CROWN_TIERS do
			local u = i * CHc / CROWN_TIERS
			rib(m, pt(-1, u), pt(1, u), RIB_W, RIB_D, nrm, RIB_C, "CrownRing")
		end
		for i = 0, CROWN_TIERS - 1 do
			local u0, u1 = i * CHc / CROWN_TIERS, (i + 1) * CHc / CROWN_TIERS
			rib(m, pt(-1, u0), pt(0, u1), RIB_W, RIB_D, nrm, RIB_C, "CrownRib")
			rib(m, pt(0, u0), pt(-1, u1), RIB_W, RIB_D, nrm, RIB_C, "CrownRib")
			rib(m, pt(0, u0), pt(1, u1), RIB_W, RIB_D, nrm, RIB_C, "CrownRib")
			rib(m, pt(1, u0), pt(0, u1), RIB_W, RIB_D, nrm, RIB_C, "CrownRib")
		end
		-- 솔기의 연장(중앙 세로 리브) + 모서리 리브
		rib(m, pt(0, 0), pt(0, CHc), m2s(1.3), m2s(0.9), nrm, SEAM_C, "CrownSeam")
		local cn = (nrm + FR:VectorToWorldSpace(Vector3.xAxis)).Unit
		rib(m, pt(1, 0), pt(1, CHc), m2s(1.2), m2s(1.2), cn, RIB_CORNER_C, "CrownCorner")
		-- 데크 모서리 항공장애등
		Kit.beacon(m, (FR * CFrame.new(cw(0) / 2 + 1.6, yc0 + 3.4, cw(0) / 2 + 1.6)).Position, 4.3)
	end
	-- 첨탑: 꼭대기 네 모서리에서 모이는 버팀대 + 마스트 (27 m)
	local yTop = yc0 + CHc
	local hwT = cw(CHc) / 2
	local apex = TF * Vector3.new(0, yTop + m2s(8), 0)
	for _, s in CORNERS do
		local a = TF * Vector3.new(s[1] * hwT, yTop, s[2] * hwT)
		rib(m, a, apex, m2s(0.9), m2s(0.9), Vector3.yAxis, RIB_CORNER_C, "SpireStrut")
		Kit.beacon(m, a + Vector3.new(0, 3.6, 0), 4)
	end
	local S = T.SpireHeight
	local lo, hi = S * 0.55, S * 0.45
	Kit.part(m, TF * CFrame.new(0, yTop + lo / 2, 0) * CYL_UP, Vector3.new(lo, m2s(1.7), m2s(1.7)), { name = "Spire", shape = "Cylinder", material = Enum.Material.Metal, color = P.MullionLight, collide = false })
	Kit.part(m, TF * CFrame.new(0, yTop + lo + hi / 2, 0) * CYL_UP, Vector3.new(hi, m2s(0.9), m2s(0.9)), { name = "Spire", shape = "Cylinder", material = Enum.Material.Metal, color = P.MullionLight, collide = false })
	Kit.beacon(m, TF * Vector3.new(0, yTop + S + 2.6, 0), 6.5)
	Kit.beacon(m, TF * Vector3.new(0, yTop + lo + 0.7, 0), 5)
end

------------------------------------------------------------------------------------------------------
-- 몰 (롯데월드몰 모티브: 8~12층 블록 + 곡면 지붕 홀)
------------------------------------------------------------------------------------------------------
-- 몰 홀 외피: Facade "curtain" 과 같은 야경 언어(층 슬래브 띠 + 1.4 안쪽 조명 코어 + 6 m 멀리언 + 꺼진 창)를 쓰되,
-- 조명 코어를 실내 공간(갤러리아/상점/입구 통로)을 비운 8 덩어리로 나누고, 슬래브·멀리언은 외곽 링/면별 핀으로 만듦.
local function buildHall(m: Model, rng: Random, HF: CFrame, hw: number, hd: number, hh: number): { [string]: any }
	local HXo, HZo = hw / 2, hd / 2
	local inset = 1.4
	local HXi, HZi = HXo - inset, HZo - inset
	local GX, GZ, SD = HALL_GX, HALL_GZ, HALL_SD
	local EX = GX / HALL_SHOPS -- 가운데 상점 칸 반폭 = 입구 통로 반폭
	local floorH = m2s(5.5)
	local slabH = floorH * 0.4
	local lobbyH = math.min(20, hh * 0.06)
	local fy0 = lobbyH + 1.6
	-- 1) 조명 코어 (실내를 비운 8 덩어리, 같은 색 → 바깥에서는 이전과 같은 따뜻한 층 불빛)
	local cF = MALL_LIT[rng:NextInteger(1, #MALL_LIT)]
	local coreO: PartOpts = { name = "Core", material = Enum.Material.Neon, color = cF, collide = true, shadow = false, glow = true, dayMaterial = Enum.Material.Glass, dayColor = P.GlassDeep }
	local function core(x0: number, x1: number, z0: number, z1: number, y0: number, y1: number)
		Kit.part(m, HF * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), Vector3.new(x1 - x0, y1 - y0, z1 - z0), coreO)
	end
	core(-HXi, -GX, -HZi, HZi, 0, hh)
	core(GX, HXi, -HZi, HZi, 0, hh)
	core(-GX, GX, -HZi, -SD, 0, hh)
	core(-GX, -EX, SD, HZi, 0, hh)
	core(EX, GX, SD, HZi, 0, hh)
	core(-EX, EX, SD, HZi, HALL_ET, hh)
	core(-GX, GX, GZ, SD, HALL_ST, hh)
	core(-GX, GX, -SD, -GZ, HALL_ST, hh)
	-- 2) 외곽 링(캐노피 띠 / 층 슬래브 / 상단 마감): out = 외벽 밖 돌출, depth = 안쪽 깊이, gap = 정면 입구 통로
	local function ring(y0: number, y1: number, out: number, depth: number, gap: number?, opts: PartOpts)
		local yc, yh = (y0 + y1) / 2, y1 - y0
		local xo, zo, xi, zi = HXo + out, HZo + out, HXo - depth, HZo - depth
		local function b(x0: number, x1: number, z0: number, z1: number)
			Kit.part(m, HF * CFrame.new((x0 + x1) / 2, yc, (z0 + z1) / 2), Vector3.new(x1 - x0, yh, z1 - z0), opts)
		end
		b(-xo, -xi, -zo, zo)
		b(xi, xo, -zo, zo)
		b(-xi, xi, -zo, -zi)
		if gap then
			b(-xi, -gap, zi, zo)
			b(gap, xi, zi, zo)
		else
			b(-xi, xi, zi, zo)
		end
	end
	ring(lobbyH, lobbyH + 1.6, 3, 2, EX, { name = "Canopy", material = Enum.Material.Concrete, color = P.ConcreteDark, collide = true, shadow = false })
	local slabO: PartOpts = { name = "Slab", material = Enum.Material.Glass, color = P.GlassBlue, reflectance = 0.18, collide = true, shadow = false }
	local nFloors = math.floor((hh - fy0) / floorH)
	for i = 0, nFloors - 1 do
		local yb = fy0 + i * floorH
		ring(yb, yb + slabH, 0, 2, if yb < HALL_ET then EX else nil, slabO)
	end
	ring(hh - slabH, hh, 0.2, 2, nil, slabO)
	-- 3) 멀리언(6 m): 면마다 짧은 핀(외벽 -1.1 ~ +0.5). 입구 칸은 통로 천장 위부터.
	local bay = m2s(6)
	local nx = math.max(1, math.floor(hw / bay))
	local nz = math.max(1, math.floor(hd / bay))
	local finO: PartOpts = { name = "Fin", material = Enum.Material.Metal, color = P.Mullion, collide = false, query = false, shadow = false }
	for i = 1, nx - 1 do
		local x = -HXo + i * (hw / nx)
		for _, sz in { -1, 1 } do
			local yb = if sz == 1 and math.abs(x) < EX + 0.6 then HALL_ET else fy0
			Kit.part(m, HF * CFrame.new(x, (yb + hh) / 2, sz * (HZo - 0.3)), Vector3.new(1.1, hh - yb, 1.6), finO)
		end
	end
	for i = 1, nz - 1 do
		local z = -HZo + i * (hd / nz)
		for _, sx in { -1, 1 } do
			Kit.part(m, HF * CFrame.new(sx * (HXo - 0.3), (fy0 + hh) / 2, z), Vector3.new(1.6, hh - fy0, 1.1), finO)
		end
	end
	for _, s in CORNERS do
		Kit.part(m, HF * CFrame.new(s[1] * HXo, (fy0 + hh) / 2, s[2] * HZo), Vector3.new(2.2, hh - fy0, 2.2), { name = "Corner", material = Enum.Material.Metal, color = P.Mullion, collide = false, shadow = false })
	end
	-- 4) 꺼진 창 패치(위 불빛 띠, 코어 앞 0.1)
	local s1 = fy0 + floorH + slabH
	local s2 = math.min(hh - slabH, s1 + floorH - slabH)
	local offO: PartOpts = { name = "Off", material = Enum.Material.Glass, color = P.WindowOff, reflectance = 0.1, collide = false, query = false, shadow = false }
	for _ = 1, 8 do
		local face = rng:NextInteger(1, 3)
		local nb = rng:NextInteger(1, 3)
		if face <= 2 then
			local i0 = rng:NextInteger(0, nx - nb)
			local x = -HXo + (i0 + nb / 2) * (hw / nx)
			local sz = if face == 1 then 1 else -1
			Kit.part(m, HF * CFrame.new(x, (s1 + s2) / 2, sz * (HZo - 0.95)), Vector3.new(nb * (hw / nx) - 1.1, s2 - s1, 0.7), offO)
		else
			local i0 = rng:NextInteger(0, nz - nb)
			local z = -HZo + (i0 + nb / 2) * (hd / nz)
			local sx = if rng:NextNumber() < 0.5 then 1 else -1
			Kit.part(m, HF * CFrame.new(sx * (HXo - 0.95), (s1 + s2) / 2, z), Vector3.new(0.7, s2 - s1, nb * (hd / nz) - 1.1), offO)
		end
	end
	-- 5) 지붕 슬래브(갤러리아 위는 열림 → 돔 볼트가 실내에서 보임)
	local roofO: PartOpts = { name = "Roof", material = Enum.Material.Concrete, color = P.ConcreteDark, collide = true }
	local function roof(x0: number, x1: number, z0: number, z1: number)
		Kit.part(m, HF * CFrame.new((x0 + x1) / 2, hh + 1, (z0 + z1) / 2), Vector3.new(x1 - x0, 2, z1 - z0), roofO)
	end
	roof(-HXo, HXo, GZ, HZo)
	roof(-HXo, HXo, -HZo, -GZ)
	roof(-HXo, -GX, -GZ, GZ)
	roof(GX, HXo, -GZ, GZ)
	-- 6) 정면 입구: 통로 폭 전체 유리(두께 0.4) + 자동문 2곳 + 문틀 헤더 + 양끝 문설주
	local ez = HZo - 0.3
	local dx = EX * 0.45
	local glassO: PartOpts = { name = "EntranceGlass", material = Enum.Material.Glass, color = rgb(176, 194, 208), transparency = 0.62, reflectance = 0.06, collide = true, shadow = false }
	local gy0, gy1 = 0, HALL_ET + 0.3
	local function pane(x0: number, x1: number, y0: number, y1: number)
		Kit.part(m, HF * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, ez), Vector3.new(x1 - x0, y1 - y0, OBS_GLASS_T), glassO)
	end
	local dTop = HALL_FY1 + DOOR_H
	pane(-EX, -dx - DOOR_W / 2, gy0, gy1)
	pane(-dx + DOOR_W / 2, dx - DOOR_W / 2, gy0, gy1)
	pane(dx + DOOR_W / 2, EX, gy0, gy1)
	for _, sx in { -1, 1 } do
		pane(sx * dx - DOOR_W / 2, sx * dx + DOOR_W / 2, dTop + 0.8, gy1)
		Kit.box(m, HF * CFrame.new(sx * dx, dTop + 0.45, ez - 0.25), Vector3.new(DOOR_W + 0.6, 0.9, 1.3), P.Mullion, Enum.Material.Metal, { name = "DoorHeader", collide = true, shadow = false })
		Kit.box(m, HF * CFrame.new(sx * EX, HALL_ET / 2, (HZi + HZo) / 2 - 0.1), Vector3.new(1.2, HALL_ET, inset + 0.4), P.Mullion, Enum.Material.Metal, { name = "Jamb", collide = true, shadow = false })
	end
	return {
		cf = HF,
		HX = HXo,
		HZ = HZo,
		H = hh,
		GX = GX,
		GZ = GZ,
		VZ = HALL_VZ,
		SD = SD,
		EX = EX,
		ET = HALL_ET,
		ST = HALL_ST,
		FY1 = HALL_FY1,
		FY2 = HALL_FY2,
		shops = HALL_SHOPS,
		doorXs = { -dx, dx },
		doorW = DOOR_W,
		doorH = DOOR_H,
		glassZ = ez,
	}
end

-- 다면 타원 돔(위 반쪽만): 경도(u) 14 × 위도(θ) 8 패널 + 아치 리브 15 + 용마루. 패널은 Neon(밤) → 밖에서는 이전 타원체 돔과 같고,
-- 안(갤러리아)에서는 파랗게 빛나는 볼트와 밝은 리브가 보임. 같은 색 패널끼리는 가장자리만 살짝 겹침.
local function buildDome(m: Model, HF: CFrame, a: number, bR: number, c: number, ey: number)
	local NU, NT = 14, 8
	local UMAX = 0.995
	local function pt(u: number, th: number): Vector3
		local s = math.sqrt(math.max(0, 1 - u * u))
		return Vector3.new(a * u, ey + bR * s * math.sin(th), c * s * math.cos(th))
	end
	local function nrmAt(p: Vector3): Vector3
		return Vector3.new(p.X / (a * a), (p.Y - ey) / (bR * bR), p.Z / (c * c)).Unit
	end
	local us = {}
	for i = 0, NU do
		us[i + 1] = UMAX * math.sin(-math.pi / 2 + math.pi * i / NU)
	end
	local panelO: PartOpts = { name = "Dome", material = Enum.Material.Neon, color = DOME_C, collide = true, shadow = false, glow = true, dayMaterial = Enum.Material.Glass, dayColor = P.GlassBlue }
	local center = Vector3.new(0, ey, 0)
	for i = 1, NU do
		for j = 0, NT - 1 do
			local t0, t1 = math.pi * j / NT, math.pi * (j + 1) / NT
			local p00, p10, p01, p11 = pt(us[i], t0), pt(us[i + 1], t0), pt(us[i], t1), pt(us[i + 1], t1)
			local ctr = (p00 + p10 + p01 + p11) / 4
			local eu = (p10 + p11 - p00 - p01) / 2
			local et = (p01 + p11 - p00 - p10) / 2
			local nrm = eu:Cross(et)
			if nrm.Magnitude > 1e-3 and eu.Magnitude > 1e-3 then
				nrm = nrm.Unit
				if nrm:Dot(ctr - center) < 0 then
					nrm = -nrm
				end
				local ex = eu.Unit
				local ez = ex:Cross(nrm).Unit
				local wU = math.max((p10 - p00).Magnitude, (p11 - p01).Magnitude) + 0.6
				local wT = math.max(math.abs((p01 - p00):Dot(ez)), math.abs((p11 - p10):Dot(ez))) + 0.6
				Kit.part(m, HF * CFrame.fromMatrix(ctr, ex, nrm, ez), Vector3.new(wU, 0.8, wT), panelO)
			end
		end
	end
	-- 양 끝 마개(얇은 타원판, 아랫반은 지붕/코어 속)
	local sEnd = math.sqrt(1 - UMAX * UMAX)
	for _, sx in { -1, 1 } do
		Kit.ellipsoid(m, HF * CFrame.new(sx * a * UMAX, ey, 0), Vector3.new(1.2, 2 * bR * sEnd + 1, 2 * c * sEnd + 1), DOME_C, Enum.Material.Neon, { name = "DomeCap", shadow = false, glow = true, dayMaterial = Enum.Material.Glass, dayColor = P.GlassBlue })
	end
	-- 아치 리브(약 8 m 간격) + 용마루: 패널을 안팎으로 1 stud 씩 관통하는 띠 → 밖과 안 모두에서 빛나는 선
	local ribO: PartOpts = { name = "DomeRib", material = Enum.Material.Neon, color = DOME_RIB_C, collide = false, query = false, shadow = false, glow = true, dayMaterial = Enum.Material.Metal, dayColor = P.MullionLight }
	local function seg(q0: Vector3, q1: Vector3)
		local mid = (q0 + q1) / 2
		Kit.part(m, HF * CFrame.lookAt(mid, q1, nrmAt(mid)), Vector3.new(m2s(0.7), 2.0, (q1 - q0).Magnitude + 0.8), ribO)
	end
	local nR = 15
	for i = 1, nR do
		local u = -1 + 2 * i / (nR + 1)
		for j = 0, NT - 1 do
			seg(pt(u, math.pi * j / NT), pt(u, math.pi * (j + 1) / NT))
		end
	end
	for i = 1, NU do
		seg(pt(us[i], math.pi / 2), pt(us[i + 1], math.pi / 2))
	end
end

type Block = { name: string, x0: number, x1: number, z0: number, z1: number, h: number, glass: Color3, crown: string, led: Color3? }

local function buildMall(m: Model, rng: Random)
	local mx0, mz0, mx1, mz1 = M.Min.X, M.Min.Y, M.Max.X, M.Max.Y
	local e = m2s(4) -- 블록 사이/가장자리 여유 4 m
	local blocks: { Block } = {
		-- 서쪽 백화점 블록 65 × 42 m, 9층 40 m
		{ name = "MallWest", x0 = mx0 + 2 * e, x1 = mx0 + m2s(72), z0 = mz0 + e, z1 = mz0 + m2s(46), h = m2s(40), glass = P.GlassBlue, crown = "led", led = scale(P.LedGold, 0.8) },
		-- 중앙 쇼핑몰 블록 65 × 36 m, 8층 35 m
		{ name = "MallMid", x0 = mx0 + m2s(80), x1 = mx0 + m2s(145), z0 = mz0 + e, z1 = mz0 + m2s(40), h = m2s(35), glass = P.GlassDeep, crown = "flat" },
		-- 동쪽 블록 51 × 76 m, 12층 50 m
		{ name = "MallEast", x0 = mx1 - m2s(55), x1 = mx1 - e, z0 = mz0 + e, z1 = mz0 + m2s(80), h = m2s(50), glass = P.GlassTeal, crown = "led", led = scale(P.LedCyan, 0.7) },
		-- 동쪽 앞 파빌리온 45 × 27 m, 4층 18 m
		{ name = "Pavilion", x0 = mx1 - m2s(55), x1 = mx1 - m2s(10), z0 = mz1 - m2s(31), z1 = mz1 - e, h = m2s(18), glass = P.GlassSilver, crown = "flat" },
	}
	for _, b in blocks do
		Facade.tower(m, {
			name = b.name,
			style = "curtain",
			cf = CFrame.new((b.x0 + b.x1) / 2, CITY_Y, (b.z0 + b.z1) / 2),
			w = b.x1 - b.x0,
			d = b.z1 - b.z0,
			h = b.h,
			rng = rng,
			floorH = m2s(4.6), -- 상업시설 층고
			bay = m2s(4.2),
			glass = b.glass,
			lit = MALL_LIT,
			litChance = 0.7,
			crown = b.crown,
			ledColor = b.led,
			beacon = false,
		})
	end
	-- 곡면 지붕 홀 (사진: 타워 오른쪽 발치의 파랗게 빛나는 둥근 지붕). 벽 17 m + 지붕 10 m = 27 m.
	local hx0, hx1, hz0, hz1 = mx0 + m2s(13), mx0 + m2s(140), mz1 - m2s(67), mz1 - m2s(13)
	local hh = m2s(17)
	local hcx, hcz = (hx0 + hx1) / 2, (hz0 + hz1) / 2
	local hw, hd = hx1 - hx0, hz1 - hz0
	-- 홀 외피(Facade 커튼월과 같은 층 띠/멀리언/불빛) + 속을 비운 갤러리아 + 정면 입구, 다면 타원 돔(안에서도 보이는 파란 볼트)
	local HF = CFrame.new(hcx, CITY_Y, hcz)
	local hall = buildHall(Kit.group(m, "Hall"), rng, HF, hw, hd, hh)
	buildDome(Kit.group(m, "HallRoof"), HF, (hw - m2s(5)) / 2, m2s(10), (hd - m2s(7)) / 2, hh + 0.8)
	-- 홀 정면 출입구: 30 m × 9 m 캐노피 + 빛 띠 + 광원
	canopy(m, CFrame.new(hcx, CITY_Y + PAVE_UP, hz1 - 1), m2s(30), m2s(9), true, true)
	-- 동쪽 블록 출입구 (MallEast 앞면, 파빌리온과의 사이 통로 쪽)
	local eb = blocks[3]
	local ex = (eb.x0 + eb.x1) / 2
	canopy(m, CFrame.new(ex, CITY_Y + PAVE_UP, eb.z1 - 1), m2s(20), m2s(7), false, true)
	return hcx, hcz, ex, (eb.z0 + eb.z1) / 2, hall
end

------------------------------------------------------------------------------------------------------
-- 광장
------------------------------------------------------------------------------------------------------
-- 나무: H = 전체 높이(stud). 줄기 지름 0.35 m, 수관 폭 ≈ 0.6 H (8~12 m 나무 → 5~7 m 수관)
local function tree(m: Model, rng: Random, pos: Vector3, H: number)
	local cw = H * rng:NextNumber(0.55, 0.65)
	local th = H * 0.36
	Kit.part(m, CFrame.new(pos + Vector3.new(0, th / 2, 0)) * CYL_UP, Vector3.new(th + cw * 0.2, m2s(0.35), m2s(0.35)), { name = "Trunk", shape = "Cylinder", material = Enum.Material.Wood, color = P.Bark, collide = true, shadow = false })
	local leaf = ({ P.Leaf1, P.Leaf2, P.Leaf3 })[rng:NextInteger(1, 3)]
	local c0 = pos + Vector3.new(0, th + cw * 0.4, 0)
	Kit.ellipsoid(m, CFrame.new(c0), Vector3.new(cw, cw * 0.82, cw), leaf, Enum.Material.Grass, { name = "Crown", query = false })
	Kit.ellipsoid(m, CFrame.new(c0 + Vector3.new(rng:NextNumber(-0.2, 0.2) * cw, cw * 0.3, rng:NextNumber(-0.2, 0.2) * cw)), Vector3.new(cw * 0.66, cw * 0.6, cw * 0.66), scale(leaf, 1.12), Enum.Material.Grass, { name = "Crown", query = false })
end

local function treeH(rng: Random): number
	return m2s(rng:NextNumber(8, 12))
end

-- 7 m 광장 가로등: 기둥 + 등기구
local function lamp(m: Model, pos: Vector3, real: boolean)
	Kit.part(m, CFrame.new(pos + Vector3.new(0, LAMP_H / 2, 0)) * CYL_UP, Vector3.new(LAMP_H, m2s(0.18), m2s(0.18)), { name = "LampPole", shape = "Cylinder", material = Enum.Material.Metal, color = P.Mullion, collide = true })
	local head = Kit.ball(m, pos + Vector3.new(0, LAMP_H + m2s(0.25), 0), m2s(0.6), P.LampWarm, Enum.Material.Neon, { name = "LampHead", collide = false, query = false, glow = true, dayMaterial = Enum.Material.Glass, dayColor = P.LampWhite })
	if real then
		Kit.light(head, "PointLight", { color = P.LampWarm, brightness = 1.3, range = 45 })
	end
end

local function buildPlaza(m: Model, rng: Random, TF: CFrame, px0: number, pz0: number, px1: number, pz1: number)
	local TC = T.Center
	local mx0, mz0, mx1, mz1 = M.Min.X, M.Min.Y, M.Max.X, M.Max.Y
	local top = CITY_Y + PAVE_UP -- 포장 윗면 (도시 지면보다 0.4 높음 → 겹치는 면 없음)
	local bot = CITY_Y - 10
	local function pave(x0: number, z0: number, x1: number, z1: number, c: Color3, mat: Enum.Material)
		Kit.box(m, CFrame.new((x0 + x1) / 2, (top + bot) / 2, (z0 + z1) / 2), Vector3.new(x1 - x0, top - bot, z1 - z0), c, mat, { name = "Paving", collide = true })
	end
	-- 서로 겹치지 않는 3장: 타워 광장(뒤) / 타워 광장(앞) / 몰 포디움
	pave(px0, pz0, px1, mz0, PAVE_C, Enum.Material.Slate)
	pave(px0, mz0, mx0, pz1, PAVE_C, Enum.Material.Slate)
	pave(mx0, mz0, mx1, mz1, rgb(108, 108, 110), Enum.Material.Concrete)
	-- 타워 둘레: 밝은 돌띠(바깥, 2 m) + 바닥 조명 띠(안쪽, 0.6 m) — 포장보다 0.3 위. 모서리가 겹치지 않게 짝/홀 면 길이를 다르게.
	local function ring(side: number, wdt: number, c: Color3, neon: boolean)
		for f = 0, 3 do
			local FR = TF * CFrame.Angles(0, f * math.pi / 2, 0)
			local o: PartOpts = if neon
				then { name = "GroundLight", material = Enum.Material.Neon, color = c, collide = false, query = false, glow = true, dayMaterial = Enum.Material.Slate, dayColor = P.ConcreteLight }
				else { name = "StoneBand", material = Enum.Material.Slate, color = c, collide = false, query = false, shadow = false }
			local len = if f % 2 == 0 then side + wdt else side - wdt
			Kit.part(m, FR * CFrame.new(0, PAVE_UP, side / 2), Vector3.new(len, 0.6, wdt), o)
		end
	end
	local bandSide = T.BaseWidth + m2s(25)
	ring(bandSide, m2s(2), P.ConcreteLight, false)
	ring(T.BaseWidth + m2s(15), m2s(0.6), scale(P.WindowWarm, 0.7), true)
	-- 가로등: 돌띠 안쪽 모서리 4 + 면 중앙 바깥 4 (+ 몰 앞 4)
	local diag = bandSide / 2 * math.sqrt(2)
	for i = 0, 3 do
		local a = i * math.pi / 2
		local pc = (TF * CFrame.Angles(0, a + math.pi / 4, 0) * CFrame.new(0, PAVE_UP, diag - m2s(2.2))).Position
		lamp(m, pc, i == 1 or i == 2)
		local pf = (TF * CFrame.Angles(0, a, 0) * CFrame.new(m2s(16), PAVE_UP, bandSide / 2 + m2s(4.5))).Position
		lamp(m, pf, false)
	end
	-- 몰 앞(홀 캐노피 구간은 비움)
	for i, x in { mx0 + m2s(15), mx0 + m2s(50), mx0 + m2s(105), mx0 + m2s(135) } do
		lamp(m, Vector3.new(x, top, mz1 - m2s(6)), i == 1 or i == 4)
	end
	-- 화단(앞 광장): 10 m × 3 m, 높이 0.55 m 턱 + 관목
	local fx0, fx1 = px0 + m2s(15), mx0 - m2s(10)
	local nPl = 5
	for i = 0, nPl - 1 do
		local x = fx0 + (fx1 - fx0) * (i + 0.5) / nPl
		local z = pz1 - m2s(13)
		Kit.box(m, CFrame.new(x, top + PLANTER_H / 2, z), Vector3.new(m2s(10), PLANTER_H, m2s(3)), P.ConcreteGrey, Enum.Material.Concrete, { name = "Planter", collide = true })
		Kit.ellipsoid(m, CFrame.new(x, top + PLANTER_H, z), Vector3.new(m2s(9.4), m2s(1.6), m2s(2.5)), P.GrassDark, Enum.Material.Grass, { name = "Shrub", query = false })
	end
	-- 나무 (8~12 m): 앞 광장 가로수 1열(≈ 12 m 간격) + 2열 + 몰 앞 + 타워 오른쪽 뒤
	local nFront = math.max(2, math.floor((mx0 - px0 - m2s(24)) / m2s(12)))
	for i = 0, nFront do
		local x = px0 + m2s(12) + i * ((mx0 - px0 - m2s(24)) / nFront) + rng:NextNumber(-2, 2)
		tree(m, rng, Vector3.new(x, top, pz1 - m2s(4) + rng:NextNumber(-1, 1)), treeH(rng))
	end
	for i = 0, 3 do
		local x = px0 + m2s(20) + i * m2s(30) + rng:NextNumber(-4, 4)
		tree(m, rng, Vector3.new(x, top, pz1 - m2s(26) + rng:NextNumber(-3, 3)), treeH(rng))
	end
	for _, x in { mx0 + m2s(24), mx0 + m2s(36), mx0 + m2s(115), mx0 + m2s(126) } do
		tree(m, rng, Vector3.new(x + rng:NextNumber(-3, 3), top, mz1 - m2s(3.5)), treeH(rng))
	end
	for i = 0, 4 do
		tree(m, rng, Vector3.new(px1 - m2s(7), top, TC.Z - m2s(12) - i * m2s(24) + rng:NextNumber(-6, 6)), treeH(rng))
	end
end

------------------------------------------------------------------------------------------------------
-- 수면 반사: 카메라(히어로)–광원 시선을 따라 기울인 스트릭 → 화면에서 수직으로 보임
------------------------------------------------------------------------------------------------------
local REFL_Y = Config.Level.Water + 0.7 -- Kit.reflection(수면 +0.3) 위 0.4 → 겹치는 면 없음

local function streak(m: Model, objX: number, objZ: number, z0: number, z1: number, width: number, c: Color3, tr: number, yOff: number)
	local cam = Config.Viewpoint.ReflectionEye
	local k = (objX - cam.X) / (objZ - cam.Z)
	local zc = (z0 + z1) / 2
	local xc = cam.X + (zc - cam.Z) * k
	local len = math.abs(z1 - z0) * math.sqrt(1 + k * k)
	-- 단일 조각(대시 패턴은 buildReflections 가 직접 만듦) — Kit.reflection 과 같은 재질/야간 규약
	Kit.part(m, CFrame.new(xc, REFL_Y + yOff, zc) * CFrame.Angles(0, math.atan(k), 0), Vector3.new(width, 0.12, len), {
		name = "WaterGlint",
		material = Enum.Material.Neon,
		color = c,
		transparency = tr,
		collide = false,
		query = false,
		shadow = false,
		glow = true,
		dayMaterial = Enum.Material.Glass,
		dayColor = Color3.fromRGB(40, 60, 80),
	})
end

local function buildReflections(m: Model, rng: Random, hallX: number, hallZ: number, eastX: number, eastZ: number)
	local TC = T.Center
	local HW = Config.River.HalfWidth
	local zStart = Config.FarBank.WaterEdge + 10
	-- 타워: 끊어진 금빛 대시(물결) + 가운데 가는 밝은 줄(솔기) — 서로 0.35 높이차, 대시끼리는 간격
	local z = zStart
	local zEnd = HW * 0.36 -- 먼 쪽 절반은 진하게, 가까운 쪽으로 갈수록 옅어지는 꼬리
	while z < zEnd do
		local f = (z - zStart) / (zEnd - zStart)
		local len = rng:NextNumber(30, 57)
		local z1 = math.min(z + len, zEnd)
		local w = (80 - 30 * f) * rng:NextNumber(0.7, 1.15)
		local c = if rng:NextNumber() < 0.5 then P.WindowGold else P.WindowWarm
		streak(m, TC.X, TC.Z, z, z1, w, scale(c, rng:NextNumber(0.8, 1)), 0.6 + 0.24 * f + rng:NextNumber(0, 0.06), 0)
		z = z1 + rng:NextNumber(0.8, 4.2) -- 거의 이어진 기둥(물결 가장자리는 폭 변화로)
	end
	streak(m, TC.X, TC.Z, zStart + 7, -HW * 0.29, 10, P.WindowGold, 0.55, 0.35)
	-- 몰: 파란 돔 + 동쪽 블록(따뜻한 빛)
	streak(m, hallX, hallZ, zStart, zStart + 200, 50, P.LedBlue, 0.7, 0)
	streak(m, hallX, hallZ, zStart + 217, zStart + 350, 37, P.LedBlue, 0.78, 0)
	streak(m, eastX, eastZ, zStart, zStart + 250, 30, P.WindowWarm, 0.72, 0)
end

------------------------------------------------------------------------------------------------------
-- 진입점
------------------------------------------------------------------------------------------------------
function Landmark.build(ctx: any)
	local rng: Random = ctx.rng
	local root: Model = ctx.model
	local TC = T.Center
	local TF = CFrame.new(TC.X, CITY_Y, TC.Z) * CFrame.Angles(0, math.rad(T.Yaw), 0)

	-- 발자국 예약: 타워(+기단/캐노피 여유 15 m) / 광장(타워 중심 ±110 m, 몰 앞 60 m) / 몰
	local px0, px1 = TC.X - m2s(110), Config.Zones.SkylineMid.XMin
	local pz0, pz1 = TC.Z - m2s(110), M.Min.Y + m2s(60)
	Kit.reserveRect(TC.X, TC.Z, T.BaseWidth + m2s(30), T.BaseWidth + m2s(30), T.Yaw, "LandmarkTower")
	Kit.reserve(px0, pz0, px1, pz1, "LandmarkPlaza")
	Kit.reserve(M.Min.X, M.Min.Y, M.Max.X, M.Max.Y, "LandmarkMall")

	local tower = Kit.group(root, "Tower")
	local lobby = buildBase(tower, TF)
	local floors, obs = buildShaft(tower, TF, rng)
	local crown = Kit.group(tower, "Crown")
	buildCrown(crown, TF)

	local mall = Kit.group(root, "Mall")
	local hallX, hallZ, eastX, eastZ, hall = buildMall(mall, rng)
	-- 실내 모듈(LandmarkInterior)이 쓰는 배치 정보
	Landmark.layout = { TF = TF, lobby = lobby, obs = obs, hall = hall }

	local plaza = Kit.group(root, "Plaza")
	buildPlaza(plaza, rng, TF, px0, pz0, px1, pz1)

	local refl = Kit.group(root, "Reflections")
	buildReflections(refl, rng, hallX, hallZ, eastX, eastZ)

	local total = T.Height + T.CrownHeight + T.SpireHeight
	tower:SetAttribute("Height", total)
	tower:SetAttribute("HeightMeters", total * Config.METERS_PER_STUD)
	tower:SetAttribute("Floors", floors + 2 + CROWN_TIERS * 3) -- 로비 2 + 오피스/호텔 + 크라운 전망층
end

return Landmark
