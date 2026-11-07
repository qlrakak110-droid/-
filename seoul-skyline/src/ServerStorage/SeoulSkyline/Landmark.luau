--!strict
-- SeoulSkyline / Landmark
-- 롯데월드타워 모티브 초고층 + 저층 몰(파란 곡면 지붕 홀) + 타워 광장 + 수면 반사.
--
-- 타워 (Config.Landmark.Tower): 둥근 모서리 정사각 평면을 Yaw 만큼 돌려, 곡선으로 가늘어지게 쌓음.
--   * 세그먼트 = 안쪽 Neon 조명 코어 1개 + 바깥 반사 유리 층 슬래브 링 2개.
--     단면은 "십자 블록 2 + 모서리 원기둥 4" 로 만든 정확한 둥근 정사각형(보이는 면끼리 겹침 없음).
--     코어는 바로 위 슬래브보다 CORE_INSET 만큼 들어가 있어 금빛 실내 + 은청색 유리의 가는 층 줄무늬가 됨.
--   * 면 중앙 금빛 솔기: 건물을 관통하는 얇은 Neon 핀 1개가 마주 보는 두 면에 동시에 세로선을 그림.
--   * 랜턴 크라운: 계속 가늘어지는 4면 위 다이아몬드 격자 리브(Neon) + 안쪽 등불 + 첨탑 + 항공장애등.
--   폭 곡선 w(t) = Top + (Base - Top)(1 - t^p): 중간이 살짝 불룩하고 꼭대기로 갈수록 빠르게 가늘어짐.
-- 몰 (Config.Landmark.Mall): Facade 커튼월 블록들 + 타원체 곡면 지붕(파란 Neon + 아치 리브) 홀.
-- 광장: 포장 판 + 타워 둘레 돌띠/빛띠 + 가로등 + 화단 + 나무.  모든 발자국은 Kit.reserve 로 예약.

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)
local Facade = require(script.Parent.Facade)

local Landmark = {}

local P = Config.Palette
local T = Config.Landmark.Tower
local M = Config.Landmark.Mall
local CITY_Y = Config.Level.City
local rgb = Color3.fromRGB

------------------------------------------------------------------------------------------------------
-- 상수
------------------------------------------------------------------------------------------------------
-- 타워 본체
local N_SEG = 46 -- 조명 코어 세그먼트 수 (세그먼트당 슬래브 2개 → 가로 띠 92개)
local SLABS_PER_SEG = 2
local LOBBY_H = 26 -- 지면 → 첫 슬래브(로비 층고)
local PLINTH_H = 1.2
local TAPER_POW = 1.4 -- >1 : 중간이 불룩, 꼭대기 쪽에서 빠르게 가늘어짐
local CORNER_R = 0.12 -- 모서리 반경 / 폭
local SLAB_RATIO = 0.42 -- 층 높이 중 유리 슬래브 비율
local CORE_INSET = 0.9 -- 코어가 바로 위 슬래브보다 들어간 깊이
local SEAM_W = 4 -- 면 중앙 솔기 폭
local SEAM_FROM = 0.1 -- 솔기가 시작하는 높이(비율)
-- 크라운
local CROWN_BASE_RATIO = 0.92 -- 크라운 시작 폭 / TopWidth (둥근 모서리 안쪽에 리브가 앉도록)
local CROWN_TOP_RATIO = 0.32 -- 크라운 꼭대기 폭 / TopWidth (뾰족한 실루엣)
local CROWN_TIERS = 5
local RIB_W, RIB_D = 1.6, 1.2
-- 색
local GLASS = P.GlassSilver:Lerp(P.GlassDeep, 0.42) -- 은청색 반사 유리
local SEAM_C = rgb(255, 206, 128)
local RIB_C = rgb(178, 160, 128) -- 블룸이 켜져 있으므로 격자는 중간 밝기
local RIB_CORNER_C = rgb(214, 196, 158)
local LANTERN_C = rgb(92, 78, 60)
local LOBBY_C = rgb(214, 160, 92)
local CORE_PAL = { P.WindowWarm, P.WindowWarm, P.WindowWarm, P.WindowGold, P.WindowGold, P.WindowWarmDim, rgb(255, 178, 92), P.WindowCoolDim }
local MALL_LIT = { rgb(196, 148, 92), rgb(184, 136, 84), P.WindowWarmDim, rgb(180, 150, 104), P.WindowCoolDim }
local DOME_C = rgb(52, 98, 178)
local DOME_RIB_C = rgb(120, 182, 255)

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
			reflectance = 0.24,
			collide = collide,
			query = collide,
		}
	end
end

local function neonOpts(name: string, dayMat: Enum.Material, dayColor: Color3): OptFn
	return function(c: Color3, cyl: boolean): PartOpts
		return {
			name = name,
			shape = if cyl then "Cylinder" else "Block",
			material = Enum.Material.Neon,
			color = c,
			collide = false,
			query = false,
			shadow = false,
			glow = true,
			dayMaterial = dayMat,
			dayColor = dayColor,
		}
	end
end

local function solidOpts(name: string, mat: Enum.Material, c: Color3, collide: boolean?): PartOpts
	local col = if collide == nil then false else collide
	return { name = name, material = mat, color = c, collide = col, query = col }
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

------------------------------------------------------------------------------------------------------
-- 타워 본체
------------------------------------------------------------------------------------------------------
local function coreColor(rng: Random, t: number, faceK: number): Color3
	local c = CORE_PAL[rng:NextInteger(1, #CORE_PAL)]
	local k = faceK * rng:NextNumber(0.6, 0.88)
	if rng:NextNumber() < 0.12 then
		k *= 0.5 -- 드문드문 불 꺼진 층 묶음
	end
	if t > 0.86 then
		k *= 0.72 -- 꼭대기 근처: 기계층 / 어두운 유리
	end
	return scale(c, k)
end

local function buildShaft(m: Model, TF: CFrame, rng: Random)
	local H = T.Height
	local hs = (H - LOBBY_H) / N_SEG
	local floorH = hs / SLABS_PER_SEG
	local slabH = floorH * SLAB_RATIO
	local coreMk = neonOpts("Core", Enum.Material.Glass, P.GlassBlue)
	local seamMk = neonOpts("Seam", Enum.Material.Metal, P.MullionLight)
	for k = 0, N_SEG - 1 do
		local y0 = LOBBY_H + k * hs
		local y1 = y0 + hs
		local t = (y0 + hs / 2) / H
		-- 1) 층 슬래브(반사 유리 링)
		local wsMax = 0
		for j = 0, SLABS_PER_SEG - 1 do
			local yc = y0 + j * floorH + slabH / 2
			local ws = widthAt(yc)
			wsMax = math.max(wsMax, ws)
			rsquare(m, TF * CFrame.new(0, yc, 0), ws, slabH, ws * CORNER_R, GLASS, GLASS, GLASS, slabOpts(true))
		end
		-- 2) 조명 코어: 이 세그먼트 위의(더 좁은) 슬래브 기준으로 inset → 모든 슬래브보다 안쪽
		local wTop = widthAt(y1 + slabH / 2)
		local cA, cB = coreColor(rng, t, 1.0), coreColor(rng, t, 0.84)
		rsquare(m, TF * CFrame.new(0, (y0 + y1) / 2, 0), wTop - 2 * CORE_INSET, hs, wTop * CORNER_R - CORE_INSET, cA, cB, cA:Lerp(cB, 0.5), coreMk)
		-- 3) 면 중앙 솔기 (관통 핀 2개 → 4면)
		if y0 >= H * SEAM_FROM then
			local L = wsMax + 0.8
			local cf = TF * CFrame.new(0, (y0 + y1) / 2, 0)
			Kit.part(m, cf, Vector3.new(SEAM_W, hs, L), seamMk(SEAM_C, false))
			Kit.part(m, cf, Vector3.new(L, hs, SEAM_W), seamMk(SEAM_C, false))
		end
	end
	-- 항공장애등: 중간 높이 모서리 4개
	local yb = H * 0.56
	local ws = widthAt(yb)
	local r = ws * CORNER_R
	local diag = (ws / 2 - r) * math.sqrt(2) + r + 1.2
	for i = 0, 3 do
		local a = i * math.pi / 2
		Kit.beacon(m, (TF * CFrame.Angles(0, a + math.pi / 4, 0) * CFrame.new(0, yb, diag)).Position, 3)
	end
end

------------------------------------------------------------------------------------------------------
-- 로비 / 기단 / 캐노피
------------------------------------------------------------------------------------------------------
local function buildBase(m: Model, TF: CFrame)
	-- 화강석 기단
	local pw = T.BaseWidth + 16
	rsquare(m, TF * CFrame.new(0, PLINTH_H / 2, 0), pw, PLINTH_H, pw * CORNER_R, P.ConcreteGrey, P.ConcreteGrey, P.ConcreteGrey, function(c: Color3, cyl: boolean): PartOpts
		return { name = "Plinth", shape = if cyl then "Cylinder" else "Block", material = Enum.Material.Slate, color = c, collide = true }
	end)
	-- 로비 유리 상자(금빛 발광): 첫 슬래브보다 3 stud 안쪽
	local w0 = widthAt(LOBBY_H)
	local wl = w0 - 6
	local rl = w0 * CORNER_R - 3
	local lh = LOBBY_H - PLINTH_H
	rsquare(m, TF * CFrame.new(0, PLINTH_H + lh / 2, 0), wl, lh, rl, LOBBY_C, LOBBY_C, LOBBY_C, neonOpts("Lobby", Enum.Material.Glass, P.GlassSilver))
	-- 로비 멀리언(관통 핀)
	local span = wl / 2 - rl - 2
	local n = math.floor(span * 2 / 10)
	for i = 0, n do
		local x = -span + i * (span * 2 / n)
		local cf = TF * CFrame.new(x, PLINTH_H + lh / 2, 0)
		Kit.box(m, cf, Vector3.new(0.8, lh, wl + 1.0), P.Mullion, Enum.Material.Metal, { name = "LobbyFin", collide = false, query = false, shadow = false })
		Kit.box(m, TF * CFrame.new(0, PLINTH_H + lh / 2, x), Vector3.new(wl + 1.0, lh, 0.8), P.Mullion, Enum.Material.Metal, { name = "LobbyFin", collide = false, query = false, shadow = false })
	end
	-- 각 면 중앙 출입구 캐노피 + 아래 조명 띠 + 기둥 + 실제 광원
	local cy = 16
	for f = 0, 3 do
		local FR = TF * CFrame.Angles(0, f * math.pi / 2, 0)
		local z0 = wl / 2 - 1
		Kit.box(m, FR * CFrame.new(0, cy, z0 + 10), Vector3.new(46, 1.6, 20), P.ConcreteDark, Enum.Material.Metal, { name = "Canopy", collide = true })
		local strip = Kit.box(m, FR * CFrame.new(0, cy - 0.8 - 0.5, z0 + 10.5), Vector3.new(40, 0.3, 15), P.WindowWarm, Enum.Material.Neon, {
			name = "CanopyLight",
			collide = false,
			query = false,
			glow = true,
			dayMaterial = Enum.Material.SmoothPlastic,
			dayColor = P.ConcreteLight,
		})
		Kit.light(strip, "PointLight", { color = P.LampWarm, brightness = 1.6, range = 30 })
		for _, sx in { -20, 20 } do
			Kit.part(m, FR * CFrame.new(sx, (cy - 0.8) / 2, z0 + 18) * CYL_UP, Vector3.new(cy - 0.8, 1.4, 1.4), {
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
-- 랜턴 크라운 + 첨탑
------------------------------------------------------------------------------------------------------
local function buildCrown(m: Model, TF: CFrame)
	local H = T.Height
	-- 본체 마감 데크
	local wd = widthAt(H) + 0.6
	rsquare(m, TF * CFrame.new(0, H + 1, 0), wd, 2, wd * CORNER_R, GLASS, GLASS, GLASS, slabOpts(true))
	local yc0 = H + 2
	local CHc = T.CrownHeight - 2
	local function cw(u: number): number
		local a = u / CHc
		return T.TopWidth * (CROWN_BASE_RATIO + (CROWN_TOP_RATIO - CROWN_BASE_RATIO) * a)
	end
	-- 안쪽 등불(아래 3단): 격자 사이로 은은하게
	for i = 0, 1 do
		local u0, u1 = i * CHc / CROWN_TIERS, (i + 1) * CHc / CROWN_TIERS
		local dia = cw(u1) * 0.55
		local c = scale(LANTERN_C, 1 + i * 0.15)
		local p = Kit.part(m, TF * CFrame.new(0, yc0 + (u0 + u1) / 2, 0) * CYL_UP, Vector3.new(u1 - u0, dia, dia), neonOpts("Lantern", Enum.Material.Glass, P.GlassSilver)(c, true))
		Kit.light(p, "PointLight", { color = P.LampWarm, brightness = 1.8, range = 50 })
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
		rib(m, pt(0, 0), pt(0, CHc), 2.6, 1.8, nrm, SEAM_C, "CrownSeam")
		local cn = (nrm + FR:VectorToWorldSpace(Vector3.xAxis)).Unit
		rib(m, pt(1, 0), pt(1, CHc), 2.4, 2.4, cn, RIB_CORNER_C, "CrownCorner")
		-- 데크 모서리 항공장애등
		Kit.beacon(m, (FR * CFrame.new(cw(0) / 2 + 1, yc0 + 2, cw(0) / 2 + 1)).Position, 2.6)
	end
	-- 첨탑: 꼭대기 네 모서리에서 모이는 버팀대 + 마스트
	local yTop = yc0 + CHc
	local hwT = cw(CHc) / 2
	local apex = TF * Vector3.new(0, yTop + 16, 0)
	for _, s in CORNERS do
		local a = TF * Vector3.new(s[1] * hwT, yTop, s[2] * hwT)
		rib(m, a, apex, 1.8, 1.8, Vector3.yAxis, RIB_CORNER_C, "SpireStrut")
		Kit.beacon(m, a + Vector3.new(0, 2.2, 0), 2.4)
	end
	local S = T.SpireHeight
	local lo, hi = S * 0.55, S * 0.45
	Kit.part(m, TF * CFrame.new(0, yTop + lo / 2, 0) * CYL_UP, Vector3.new(lo, 3.4, 3.4), { name = "Spire", shape = "Cylinder", material = Enum.Material.Metal, color = P.MullionLight, collide = false })
	Kit.part(m, TF * CFrame.new(0, yTop + lo + hi / 2, 0) * CYL_UP, Vector3.new(hi, 1.8, 1.8), { name = "Spire", shape = "Cylinder", material = Enum.Material.Metal, color = P.MullionLight, collide = false })
	Kit.beacon(m, TF * Vector3.new(0, yTop + S + 1.6, 0), 4)
	Kit.beacon(m, TF * Vector3.new(0, yTop + lo + 0.4, 0), 3)
end

------------------------------------------------------------------------------------------------------
-- 몰
------------------------------------------------------------------------------------------------------
type Block = { name: string, x0: number, x1: number, z0: number, z1: number, h: number, glass: Color3, crown: string, led: Color3? }

local function buildMall(m: Model, rng: Random)
	local mx0, mz0, mx1, mz1 = M.Min.X, M.Min.Y, M.Max.X, M.Max.Y
	local blocks: { Block } = {
		{ name = "MallWest", x0 = mx0 + 15, x1 = mx0 + 145, z0 = mz0 + 8, z1 = mz0 + 92, h = 62, glass = P.GlassBlue, crown = "led", led = scale(P.LedGold, 0.8) },
		{ name = "MallMid", x0 = mx0 + 160, x1 = mx0 + 290, z0 = mz0 + 8, z1 = mz0 + 80, h = 46, glass = P.GlassDeep, crown = "flat" },
		{ name = "MallEast", x0 = mx1 - 110, x1 = mx1 - 8, z0 = mz0 + 8, z1 = mz0 + 160, h = 88, glass = P.GlassTeal, crown = "led", led = scale(P.LedCyan, 0.7) },
		{ name = "Pavilion", x0 = mx1 - 110, x1 = mx1 - 20, z0 = mz1 - 62, z1 = mz1 - 8, h = 30, glass = P.GlassSilver, crown = "flat" },
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
			floorH = 9,
			bay = 12,
			glass = b.glass,
			lit = MALL_LIT,
			litChance = 0.8,
			crown = b.crown,
			ledColor = b.led,
			beacon = false,
		})
	end
	-- 곡면 지붕 홀 (사진: 타워 오른쪽 발치의 파랗게 빛나는 둥근 지붕)
	local hx0, hx1, hz0, hz1, hh = mx0 + 25, mx0 + 280, mz1 - 135, mz1 - 25, 32
	local hcx, hcz = (hx0 + hx1) / 2, (hz0 + hz1) / 2
	local hw, hd = hx1 - hx0, hz1 - hz0
	Facade.tower(m, {
		name = "Hall",
		style = "curtain",
		cf = CFrame.new(hcx, CITY_Y, hcz),
		w = hw,
		d = hd,
		h = hh,
		rng = rng,
		floorH = 10,
		bay = 14,
		glass = P.GlassBlue,
		lit = MALL_LIT,
		litChance = 0.85,
		crown = "none",
		beacon = false,
	})
	-- 타원체 돔(아랫반은 건물 속): 적도면이 지붕 슬래브(두께 1.2) 안에 있어 틈/겹침 없음
	local ey = CITY_Y + hh + 0.8
	local a, bR, c = (hw - 10) / 2, 28, (hd - 14) / 2
	Kit.ellipsoid(m, CFrame.new(hcx, ey, hcz), Vector3.new(a * 2, bR * 2, c * 2), DOME_C, Enum.Material.Neon, {
		name = "Dome",
		shadow = false,
		glow = true,
		dayMaterial = Enum.Material.Glass,
		dayColor = P.GlassBlue,
	})
	-- 아치 리브: 각 x 단면의 돔 타원보다 0.6 큰 얇은 렌즈 → 표면 위 빛나는 아치선
	local nR = 13
	for i = 1, nR do
		local x = -a + (2 * a) * i / (nR + 1)
		local s = math.sqrt(math.max(0, 1 - (x / a) ^ 2))
		Kit.ellipsoid(m, CFrame.new(hcx + x, ey, hcz), Vector3.new(1.4, 2 * bR * s + 1.2, 2 * c * s + 1.2), DOME_RIB_C, Enum.Material.Neon, {
			name = "DomeRib",
			shadow = false,
			query = false,
			glow = true,
			dayMaterial = Enum.Material.Metal,
			dayColor = P.MullionLight,
		})
	end
	-- 용마루 선
	Kit.ellipsoid(m, CFrame.new(hcx, ey, hcz), Vector3.new(a * 2 + 1.2, bR * 2 + 1.2, 1.4), DOME_RIB_C, Enum.Material.Neon, {
		name = "DomeRidge",
		shadow = false,
		query = false,
		glow = true,
		dayMaterial = Enum.Material.Metal,
		dayColor = P.MullionLight,
	})
	-- 홀 정면 출입구: 캐노피 + 빛 띠 + 광원
	local fz = hz1
	Kit.box(m, CFrame.new(hcx, CITY_Y + 13, fz + 8), Vector3.new(70, 1.4, 17), P.ConcreteDark, Enum.Material.Metal, { name = "HallCanopy", collide = true })
	local hs = Kit.box(m, CFrame.new(hcx, CITY_Y + 13 - 0.7 - 0.5, fz + 8.5), Vector3.new(64, 0.3, 13), P.WindowWarm, Enum.Material.Neon, {
		name = "HallCanopyLight",
		collide = false,
		query = false,
		glow = true,
		dayMaterial = Enum.Material.SmoothPlastic,
		dayColor = P.ConcreteLight,
	})
	Kit.light(hs, "PointLight", { color = P.LampWarm, brightness = 1.5, range = 36 })
	-- 동쪽 블록 출입구
	local eb = blocks[3]
	local ex, ez = (eb.x0 + eb.x1) / 2, eb.z1
	local es = Kit.box(m, CFrame.new(ex, CITY_Y + 9, ez + 6), Vector3.new(40, 0.8, 11), P.WindowWarm, Enum.Material.Neon, {
		name = "EntranceLight",
		collide = false,
		query = false,
		glow = true,
		dayMaterial = Enum.Material.SmoothPlastic,
		dayColor = P.ConcreteLight,
	})
	Kit.light(es, "PointLight", { color = P.LampWarm, brightness = 1.4, range = 30 })
	return hcx, hcz, ex, (eb.z0 + eb.z1) / 2
end

------------------------------------------------------------------------------------------------------
-- 광장
------------------------------------------------------------------------------------------------------
local function tree(m: Model, rng: Random, pos: Vector3, size: number)
	local th = size * 0.45
	Kit.part(m, CFrame.new(pos + Vector3.new(0, th / 2, 0)) * CYL_UP, Vector3.new(th, 1.4, 1.4), { name = "Trunk", shape = "Cylinder", material = Enum.Material.Wood, color = P.Bark, collide = false, query = false, shadow = false })
	local leaf = ({ P.Leaf1, P.Leaf2, P.Leaf3 })[rng:NextInteger(1, 3)]
	local c0 = pos + Vector3.new(0, th + size * 0.32, 0)
	Kit.ellipsoid(m, CFrame.new(c0), Vector3.new(size, size * 0.82, size), leaf, Enum.Material.Grass, { name = "Crown", query = false })
	Kit.ellipsoid(m, CFrame.new(c0 + Vector3.new(rng:NextNumber(-0.2, 0.2) * size, size * 0.3, rng:NextNumber(-0.2, 0.2) * size)), Vector3.new(size * 0.66, size * 0.6, size * 0.66), scale(leaf, 1.12), Enum.Material.Grass, { name = "Crown", query = false })
end

local function lamp(m: Model, pos: Vector3, real: boolean)
	local h = 13
	Kit.part(m, CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CYL_UP, Vector3.new(h, 0.7, 0.7), { name = "LampPole", shape = "Cylinder", material = Enum.Material.Metal, color = P.Mullion, collide = true })
	local head = Kit.ball(m, pos + Vector3.new(0, h + 0.6, 0), 1.9, P.LampWarm, Enum.Material.Neon, { name = "LampHead", collide = false, query = false, glow = true, dayMaterial = Enum.Material.Glass, dayColor = P.LampWhite })
	if real then
		Kit.light(head, "PointLight", { color = P.LampWarm, brightness = 1.3, range = 34 })
	end
end

local function buildPlaza(m: Model, rng: Random, TF: CFrame, px0: number, pz0: number, px1: number, pz1: number)
	local TC = T.Center
	local mx0, mz0, mx1, mz1 = M.Min.X, M.Min.Y, M.Max.X, M.Max.Y
	local top = CITY_Y + 0.4 -- 포장 윗면 (도시 지면보다 0.4 높음 → 겹치는 면 없음)
	local bot = CITY_Y - 10
	local function pave(x0: number, z0: number, x1: number, z1: number, c: Color3, mat: Enum.Material)
		Kit.box(m, CFrame.new((x0 + x1) / 2, (top + bot) / 2, (z0 + z1) / 2), Vector3.new(x1 - x0, top - bot, z1 - z0), c, mat, { name = "Paving", collide = true })
	end
	-- 서로 겹치지 않는 3장: 타워 광장(뒤) / 타워 광장(앞) / 몰 포디움
	pave(px0, pz0, px1, mz0, rgb(118, 116, 112), Enum.Material.Slate)
	pave(px0, mz0, mx0, pz1, rgb(118, 116, 112), Enum.Material.Slate)
	pave(mx0, mz0, mx1, mz1, rgb(108, 108, 110), Enum.Material.Concrete)
	-- 타워 둘레: 밝은 돌띠(바깥) + 바닥 조명 띠(안쪽)  — 포장보다 0.3 위
	local function ring(side: number, wdt: number, c: Color3, neon: boolean)
		for f = 0, 3 do
			local FR = TF * CFrame.Angles(0, f * math.pi / 2, 0)
			local o: PartOpts = if neon
				then { name = "GroundLight", material = Enum.Material.Neon, color = c, collide = false, query = false, glow = true, dayMaterial = Enum.Material.Slate, dayColor = P.ConcreteLight }
				else { name = "StoneBand", material = Enum.Material.Slate, color = c, collide = false, query = false, shadow = false }
			Kit.part(m, FR * CFrame.new(0, top - CITY_Y + 0.0, side / 2), Vector3.new(side + wdt, 0.6, wdt), o)
		end
	end
	ring(T.BaseWidth + 50, 4, P.ConcreteLight, false)
	ring(T.BaseWidth + 30, 1.2, scale(P.WindowWarm, 0.7), true)
	-- 가로등: 돌띠 위 모서리 4 + 면 중앙 바깥 4 (+ 몰 앞 3)
	local diag = (T.BaseWidth + 50) / 2 * math.sqrt(2)
	for i = 0, 3 do
		local a = i * math.pi / 2
		local pc = (TF * CFrame.Angles(0, a + math.pi / 4, 0) * CFrame.new(0, top - CITY_Y, diag - 4)).Position
		lamp(m, pc, i == 1 or i == 2)
		local pf = (TF * CFrame.Angles(0, a, 0) * CFrame.new(32, top - CITY_Y, (T.BaseWidth + 50) / 2 + 9)).Position
		lamp(m, pf, false)
	end
	-- 몰 앞(홀 캐노피 구간은 비움)
	for i, x in { mx0 + 30, mx0 + 100, mx0 + 210, mx0 + 270 } do
		lamp(m, Vector3.new(x, top, mz1 - 12), i == 1 or i == 4)
	end
	-- 화단(앞 광장)
	local fx0, fx1 = px0 + 30, mx0 - 20
	for i = 0, 3 do
		local x = fx0 + (fx1 - fx0) * (i + 0.5) / 4
		local z = pz1 - 26
		Kit.box(m, CFrame.new(x, top + 1.2, z), Vector3.new(30, 2.4, 9), P.ConcreteGrey, Enum.Material.Concrete, { name = "Planter", collide = true })
		Kit.ellipsoid(m, CFrame.new(x, top + 2.6, z), Vector3.new(28, 4.4, 7.6), P.GrassDark, Enum.Material.Grass, { name = "Shrub", query = false })
	end
	-- 나무: 앞 광장 2열 + 몰 앞 가로수 + 타워 오른쪽 뒤
	for i = 0, 5 do
		local x = px0 + 24 + i * ((mx0 - px0 - 48) / 5) + rng:NextNumber(-5, 5)
		tree(m, rng, Vector3.new(x, top, pz1 - 8 + rng:NextNumber(-2, 2)), rng:NextNumber(14, 19))
	end
	for i = 0, 2 do
		local x = px0 + 40 + i * 70 + rng:NextNumber(-6, 6)
		tree(m, rng, Vector3.new(x, top, pz1 - 52 + rng:NextNumber(-3, 3)), rng:NextNumber(13, 17))
	end
	for _, x in { mx0 + 48, mx0 + 82, mx0 + 230, mx0 + 252 } do
		tree(m, rng, Vector3.new(x + rng:NextNumber(-3, 3), top, mz1 - 7), rng:NextNumber(12, 15))
	end
	for i = 0, 3 do
		tree(m, rng, Vector3.new(px1 - 14, top, TC.Z - 40 - i * 60 + rng:NextNumber(-6, 6)), rng:NextNumber(14, 18))
	end
end

------------------------------------------------------------------------------------------------------
-- 수면 반사: 카메라(히어로)–광원 시선을 따라 기울인 스트릭 → 화면에서 수직으로 보임
------------------------------------------------------------------------------------------------------
local function streak(m: Model, objX: number, objZ: number, z0: number, z1: number, width: number, c: Color3, tr: number, yOff: number)
	local cam = Config.Viewpoint.HeroCamPos
	local k = (objX - cam.X) / (objZ - cam.Z)
	local zc = (z0 + z1) / 2
	local xc = cam.X + (zc - cam.Z) * k
	local len = math.abs(z1 - z0) * math.sqrt(1 + k * k)
	local p = Kit.reflection(m, xc, zc, width, len, c, tr)
	p.CFrame = CFrame.new(xc, Config.Level.Water + 0.25 + yOff, zc) * CFrame.Angles(0, math.atan(k), 0)
end

local function buildReflections(m: Model, rng: Random, hallX: number, hallZ: number, eastX: number, eastZ: number)
	local TC = T.Center
	local zStart = Config.FarBank.WaterEdge + 6
	-- 타워: 끊어진 금빛 대시(물결) + 가운데 가는 밝은 줄(솔기) — 서로 0.35 높이차, 대시끼리는 간격
	local z = zStart
	local zEnd = 150 -- 먼 쪽 절반은 진하게, 가까운 쪽으로 갈수록 옅어지는 꼬리
	while z < zEnd do
		local f = (z - zStart) / (zEnd - zStart)
		local len = rng:NextNumber(24, 44)
		local z1 = math.min(z + len, zEnd)
		local w = (48 - 18 * f) * rng:NextNumber(0.7, 1.15)
		local c = if rng:NextNumber() < 0.5 then P.WindowGold else P.WindowWarm
		streak(m, TC.X, TC.Z, z, z1, w, scale(c, rng:NextNumber(0.8, 1)), 0.6 + 0.24 * f + rng:NextNumber(0, 0.06), 0)
		z = z1 + rng:NextNumber(4, 9)
	end
	streak(m, TC.X, TC.Z, zStart + 4, -120, 6, P.WindowGold, 0.55, 0.35)
	-- 몰: 파란 돔 + 동쪽 블록(따뜻한 빛)
	streak(m, hallX, hallZ, zStart, zStart + 120, 30, P.LedBlue, 0.7, 0)
	streak(m, hallX, hallZ, zStart + 130, zStart + 210, 22, P.LedBlue, 0.78, 0)
	streak(m, eastX, eastZ, zStart, zStart + 150, 18, P.WindowWarm, 0.72, 0)
end

------------------------------------------------------------------------------------------------------
-- 진입점
------------------------------------------------------------------------------------------------------
function Landmark.build(ctx: any)
	local rng: Random = ctx.rng
	local root: Model = ctx.model
	local TC = T.Center
	local TF = CFrame.new(TC.X, CITY_Y, TC.Z) * CFrame.Angles(0, math.rad(T.Yaw), 0)

	-- 발자국 예약: 타워(+기단/캐노피 여유) / 광장 / 몰
	local px0, px1 = TC.X - 220, Config.Zones.SkylineMid.XMin
	local pz0, pz1 = TC.Z - 220, M.Min.Y + 120
	Kit.reserveRect(TC.X, TC.Z, T.BaseWidth + 60, T.BaseWidth + 60, T.Yaw, "LandmarkTower")
	Kit.reserve(px0, pz0, px1, pz1, "LandmarkPlaza")
	Kit.reserve(M.Min.X, M.Min.Y, M.Max.X, M.Max.Y, "LandmarkMall")

	local tower = Kit.group(root, "Tower")
	buildBase(tower, TF)
	buildShaft(tower, TF, rng)
	local crown = Kit.group(tower, "Crown")
	buildCrown(crown, TF)

	local mall = Kit.group(root, "Mall")
	local hallX, hallZ, eastX, eastZ = buildMall(mall, rng)

	local plaza = Kit.group(root, "Plaza")
	buildPlaza(plaza, rng, TF, px0, pz0, px1, pz1)

	local refl = Kit.group(root, "Reflections")
	buildReflections(refl, rng, hallX, hallZ, eastX, eastZ)

	tower:SetAttribute("Height", T.Height + T.CrownHeight + T.SpireHeight)
end

return Landmark
