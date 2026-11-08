--!strict
-- SeoulSkyline / Bridge
-- 잠실대교 모티브 다경간 도로교 (실측 스케일, 1 stud = 0.3 m): 강을 Z 방향으로 가로질러 양쪽 둔치·제방을 넘어
-- 제방 도로(올림픽대로/강변북로, L.Levee)와 평면 교차로로 만나고, 그 바깥 도시 도로(ZFrom/ZTo)까지 이어짐.
--
--   * 종단 선형: 양끝(제방 도로 가장자리 F.SlopeTo / N.SlopeTo)은 도시 도로 높이(L.City + 0.4), 강 중앙 ±FLAT_HALF
--     (75 m)는 DeckTop(17 m). 사이는 smoothstep 완경사(최대 ≈ 7 %). 상판은 지점(교각/교대) 사이 직선 세그먼트
--     (기울어진 파트)로 이어지고, 같은 기울기의 연속 세그먼트는 하나로 합침.
--   * 단면(폭 36 m, 중심선 기준 반폭 18 m): 중앙분리대 2 m(콘크리트 방호벽 0.6 x 0.85 m) + 방향별 4차로 x 3.5 m
--     + 보도 2.5 m(연석 0.25 m) + 난간 기초 0.5 m. 난간 높이 1.1 m(보도 기준). 박스거더 높이 3.5 m(사다리꼴 웹).
--     가로등 10 m(난간 위) · 암 2 m · 간격 32 m, 따뜻한 나트륨 등기구.
--   * 교각: 수중 기초(둥근 코, 폭 18 m) + 쌍기둥(지름 3.5 m, 중심 간격 12 m) + 해머헤드 캡(19 x 3.5 x 2.2 m)
--     + 받침. 기둥은 반투명 Neon 외피로 따뜻한 업라이트 세척광, 캡 앞면 빛막, 기초의 등기구 + SpotLight(위로).
--     낮은 교각(둔치 끝)은 벽식. 교대: 사면 발치에 콘크리트 블록.
--   * 수면 반사: 수중 교각마다 긴 주황 스트릭, 수면 위 가로등 쌍마다 짧은 스트릭(Kit.reflection).
--   * 차선: 방향별 4차로 Kit.lane, 전조등 높이(노면 + 0.75 m), 60~70 km/h(55~65 stud/s).
--     우측통행: +Z 로 오는 차 = -X 쪽 "head", -Z 로 가는 차 = +X 쪽 "tail".
--   * 예약: 양끝 도시 도로 토막 + 둔치/수면 구간 (제방 도로 띠는 Riverside 가 깔도록 비워 둠 → 입구에 가로막는 것 없음).

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)

local Bridge = {}

type PartOpts = Kit.PartOpts

local P = Config.Palette
local B = Config.Bridge
local L = Config.Level
local F, N = Config.FarBank, Config.NearBank
local R = Config.Real
local m = Config.m
local rgb = Color3.fromRGB

------------------------------------------------------------------------------------------------------
-- 상수 (모두 실측 m → stud)
------------------------------------------------------------------------------------------------------
local BX = B.X
local HALF_W = B.Width / 2 -- 18 m
-- 종단
local Y_END = L.City + 0.4 -- 양끝 노면 = 제방/도시 도로 포장 윗면(Riverside 와 동일)
local FLAT_HALF = m(75) -- 강 중앙 수평 구간 반폭
local Z_A, Z_B = F.SlopeTo, N.SlopeTo -- 교량 본체 시작/끝(제방 도로 가장자리)
-- 단면 (상판 윗면 = 로컬 y 0)
local FASCIA_W = m(0.5) -- 난간 기초(가장자리보) 폭
local EDGE_X = HALF_W - FASCIA_W / 2 -- 가장자리보 중심(난간·가로등 기초)
local SLAB_HALF = HALF_W - FASCIA_W + 0.3 -- 슬래브는 가장자리보 속으로 0.3 들어감
local SLAB_T = m(0.45) -- 캔틸레버 슬래브(포장 포함)
local GIRDER_D = m(3.5) -- 노면 → 박스거더 바닥
local GIRDER_HALF = m(8.5) -- 거더 하부 플랜지 반폭
local WEB_TOP_HALF = m(10.5) -- 경사 웹 상단 반폭
local MEDIAN_HALF = m(1.0) -- 중앙분리대 구역 반폭(2 m)
local BARRIER_HALF, BARRIER_H = m(0.3), m(0.85) -- 콘크리트 방호벽
local LANE_W = R.Lane -- 3.5 m
local LANE_X0 = MEDIAN_HALF -- 1차로 안쪽 경계
local CURB_X = LANE_X0 + 4 * LANE_W -- 4차로 바깥 경계 = 연석
local WALK_TOP = m(0.25) -- 보도 연석 높이
local FASCIA_TOP = WALK_TOP + m(0.4) -- 난간 콘크리트 기초 윗면
local FASCIA_BOT = -m(1.3) -- 가장자리보 아래 끝
local MARK_T = 0.3 -- 노면표시 윗면이 아스팔트보다 높은 양(동일 평면 회피)
local LINE_W = m(0.15)
local DASH_LEN, DASH_PITCH, DASH_OFF = m(6), m(18), m(2)
local RAIL_TOP = WALK_TOP + R.Railing -- 보도 기준 1.1 m
local RAIL_MID = WALK_TOP + m(0.75)
local POST_PITCH = m(6)
local CAR_UP = m(0.75) -- 전조등 높이
-- 가로등
local LAMP_PITCH = m(32)
local LAMP_H = R.StreetLamp -- 10 m (난간 기초 위)
local LAMP_ARM = m(2.0)
local LAMP_LIGHTS = 14 -- 가로등 SpotLight 수(가까운 쪽 위주)
-- 교각
local COL_X, COL_D = m(6), m(3.5)
local CAP_W, CAP_D, CAP_H = m(19), m(3.5), m(2.2)
local FOOT_D = m(6)
local FOOT_TOP_W = L.Water + m(0.6)
local BEARING_GAP = m(0.15)
local PIER_LIGHTS = 9
-- 색
local CONC = rgb(176, 172, 166)
local ASPHALT = P.Asphalt:Lerp(P.AsphaltLight, 0.35)
local PAINT_W = P.LaneWhite:Lerp(ASPHALT, 0.22) -- 야간 노면 도색(원경에서 점선이 너무 튀지 않게)
local PAINT_Y = P.LaneYellow:Lerp(ASPHALT, 0.15)
local CONC_FASCIA = rgb(198, 192, 182)
local CONC_GIRDER = rgb(118, 118, 122)
local CONC_PIER = rgb(160, 154, 146)
local WALK_C = rgb(132, 122, 112)
local METAL = rgb(78, 84, 92)
local POLE_C = rgb(64, 68, 74)
local EDGE_LED = rgb(226, 164, 100) -- 가장자리 빛띠(길어서 중간 밝기)
local LAMP_LENS = P.LampWarm
local LAMP_GLARE = rgb(255, 190, 118)
local UPLIGHT = rgb(255, 172, 92)
local SHEATH_C = rgb(178, 110, 54) -- 기둥 세척광 외피(반투명, 아래쪽)
local SHEATH_TOP = rgb(150, 100, 64) -- 위쪽(빛이 옅어짐)
local WASH_C = rgb(150, 96, 52)
local PIER_REF = rgb(255, 156, 78)
local LAMP_REF = rgb(255, 168, 96)

------------------------------------------------------------------------------------------------------
-- 종단 선형
------------------------------------------------------------------------------------------------------
local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function deckY(z: number): number
	local rise = B.DeckTop - Y_END
	if z < -FLAT_HALF then
		return Y_END + rise * smooth((z - Z_A) / (-FLAT_HALF - Z_A))
	elseif z > FLAT_HALF then
		return Y_END + rise * smooth((Z_B - z) / (Z_B - FLAT_HALF))
	end
	return B.DeckTop
end

-- 지점: 교대(양끝) + PierSpacing 격자 교각(둔치 사면에는 두지 않음)
local function supports(): ({ number }, { number })
	local zs = { Z_A }
	local piers = {}
	local sp = B.PierSpacing
	local pad = m(4)
	for k = math.ceil((F.ParkTo + pad) / sp), math.floor((N.ParkTo - pad) / sp) do
		local z = k * sp
		table.insert(zs, z)
		table.insert(piers, z)
	end
	table.insert(zs, Z_B)
	return zs, piers
end

type Seg = { z0: number, y0: number, z1: number, y1: number, len: number, s0: number, cf: CFrame }

local function makeSegs(zs: { number }): ({ Seg }, number)
	-- 같은 기울기의 연속 구간은 합침
	local pts: { Vector2 } = {}
	for _, z in zs do
		table.insert(pts, Vector2.new(z, deckY(z)))
	end
	local keep: { Vector2 } = { pts[1] }
	for i = 2, #pts - 1 do
		local a, b, c = keep[#keep], pts[i], pts[i + 1]
		local s1 = (b.Y - a.Y) / (b.X - a.X)
		local s2 = (c.Y - b.Y) / (c.X - b.X)
		if math.abs(s1 - s2) > 1e-5 then
			table.insert(keep, b)
		end
	end
	table.insert(keep, pts[#pts])
	local segs: { Seg } = {}
	local s = 0
	for i = 1, #keep - 1 do
		local a, b = keep[i], keep[i + 1]
		local p0 = Vector3.new(BX, a.Y, a.X)
		local p1 = Vector3.new(BX, b.Y, b.X)
		local d = p1 - p0
		local mid = (p0 + p1) / 2
		-- LookVector = -d → 로컬 +Z = 진행(+Z) 방향, 로컬 +X = 월드 +X
		local cf = CFrame.lookAt(mid, mid - d)
		table.insert(segs, { z0 = a.X, y0 = a.Y, z1 = b.X, y1 = b.Y, len = d.Magnitude, s0 = s, cf = cf })
		s += d.Magnitude
	end
	return segs, s
end

------------------------------------------------------------------------------------------------------
-- 파트 옵션
------------------------------------------------------------------------------------------------------
local function solid(name: string, color: Color3, mat: Enum.Material): PartOpts
	return { name = name, color = color, material = mat, collide = true }
end

local function decor(name: string, color: Color3, mat: Enum.Material): PartOpts
	return { name = name, color = color, material = mat, collide = false, query = false }
end

local function neon(name: string, color: Color3, dayMat: Enum.Material, dayColor: Color3, tr: number?): PartOpts
	return {
		name = name,
		color = color,
		material = Enum.Material.Neon,
		transparency = tr,
		collide = false,
		query = false,
		shadow = false,
		glow = true,
		dayMaterial = dayMat,
		dayColor = dayColor,
	}
end

-- 세그먼트 로컬 좌표(x, y0..y1, 진행 l0..l1)의 상자
local function along(parent: Instance, seg: Seg, x: number, y0: number, y1: number, w: number, l0: number, l1: number, o: PartOpts): BasePart
	local zc = (l0 + l1) / 2 - seg.len / 2
	return Kit.part(parent, seg.cf * CFrame.new(x, (y0 + y1) / 2, zc), Vector3.new(w, y1 - y0, l1 - l0), o)
end

local function worldAt(seg: Seg, x: number, y: number, l: number): Vector3
	return seg.cf:PointToWorldSpace(Vector3.new(x, y, l - seg.len / 2))
end

-- 전역 호길이 s → (세그먼트, 로컬 l)
local function locate(segs: { Seg }, s: number): (Seg, number)
	for _, seg in segs do
		if s <= seg.s0 + seg.len then
			return seg, math.max(0, s - seg.s0)
		end
	end
	local last = segs[#segs]
	return last, last.len
end

------------------------------------------------------------------------------------------------------
-- 상판 (세그먼트별 단면)
------------------------------------------------------------------------------------------------------
local function buildDeck(parent: Instance, segs: { Seg })
	local webY0, webY1 = -GIRDER_D, -SLAB_T + 0.2
	local webW = WEB_TOP_HALF - GIRDER_HALF + 0.3
	for _, seg in segs do
		local len = seg.len
		-- 슬래브(아스팔트 노면) + 박스거더(하부) + 경사 웹(웨지: 윗면 전체, 안쪽 수직면, 바깥으로 얇아짐)
		along(parent, seg, 0, -SLAB_T, 0, SLAB_HALF * 2, 0, len, solid("DeckSlab", ASPHALT, Enum.Material.Asphalt))
		along(parent, seg, 0, webY0, webY1, GIRDER_HALF * 2, 0, len, solid("BoxGirder", CONC_GIRDER, Enum.Material.Concrete))
		-- 중앙분리대 방호벽
		along(parent, seg, 0, -0.2, BARRIER_H, BARRIER_HALF * 2, 0, len, solid("MedianBarrier", CONC, Enum.Material.Concrete))
		for _, side in { -1, 1 } do
			local wx = side * (GIRDER_HALF - 0.3 + webW / 2)
			local cf = seg.cf * CFrame.new(wx, (webY0 + webY1) / 2, 0) * CFrame.Angles(0, -side * math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi)
			Kit.wedge(parent, cf, Vector3.new(len, webY1 - webY0, webW), CONC_GIRDER, Enum.Material.Concrete, { name = "GirderWeb" })
			-- 가장자리보(난간 기초) + 빛띠
			along(parent, seg, side * EDGE_X, FASCIA_BOT, FASCIA_TOP, FASCIA_W, 0, len, solid("Fascia", CONC_FASCIA, Enum.Material.Concrete))
			along(parent, seg, side * (HALF_W + 0.15), FASCIA_BOT + 0.6, FASCIA_BOT + 0.6 + m(0.3), 0.3, 0, len, neon("EdgeLight", EDGE_LED, Enum.Material.Concrete, CONC_FASCIA))
			-- 보도(연석 높이 WALK_TOP, 가장자리보 속으로 0.3 겹침)
			local w0, w1 = CURB_X, SLAB_HALF
			along(parent, seg, side * (w0 + w1) / 2, -0.4, WALK_TOP, w1 - w0, 0, len, solid("Sidewalk", WALK_C, Enum.Material.Pavement))
			-- 노면표시: 바깥 실선(흰색), 안쪽 실선(노랑)
			along(parent, seg, side * (CURB_X - 0.5 - LINE_W / 2), MARK_T - 0.5, MARK_T, LINE_W, 0, len, decor("EdgeLine", PAINT_W, Enum.Material.SmoothPlastic))
			along(parent, seg, side * (LANE_X0 + LINE_W / 2), MARK_T - 0.5, MARK_T, LINE_W, 0, len, decor("CenterLine", PAINT_Y, Enum.Material.SmoothPlastic))
			-- 난간 레일(상/중간) — 상단 레일은 충돌(추락 방지)
			along(parent, seg, side * EDGE_X, RAIL_TOP - m(0.05), RAIL_TOP + m(0.05), m(0.1), 0, len, solid("RailTop", METAL, Enum.Material.Metal))
			along(parent, seg, side * EDGE_X, RAIL_MID - m(0.03), RAIL_MID + m(0.03), m(0.06), 0, len, decor("RailMid", METAL, Enum.Material.Metal))
			-- 차선 점선(전역 위상으로 세그먼트를 넘어 이어짐)
			for k = 1, 3 do
				local x = side * (LANE_X0 + k * LANE_W)
				local mm = math.floor((seg.s0 - DASH_OFF) / DASH_PITCH)
				while mm * DASH_PITCH + DASH_OFF < seg.s0 + len do
					local a = math.max(mm * DASH_PITCH + DASH_OFF, seg.s0)
					local b = math.min(mm * DASH_PITCH + DASH_OFF + DASH_LEN, seg.s0 + len)
					if b - a > 2 then
						along(parent, seg, x, MARK_T - 0.5, MARK_T, LINE_W, a - seg.s0, b - seg.s0, decor("LaneDash", PAINT_W, Enum.Material.SmoothPlastic))
					end
					mm += 1
				end
			end
		end
	end
end

-- 난간 지주 + 가로등 (월드 수직)
local function buildLampsAndPosts(parent: Instance, segs: { Seg }, total: number, rng: Random, reflParent: Instance)
	local s = POST_PITCH / 2
	local postW = m(0.08)
	while s < total do
		local seg, l = locate(segs, s)
		for _, side in { -1, 1 } do
			local base = worldAt(seg, side * EDGE_X, FASCIA_TOP, l)
			local h = RAIL_TOP - FASCIA_TOP
			Kit.box(parent, CFrame.new(base + Vector3.new(0, h / 2, 0)), Vector3.new(postW, h, postW), METAL, Enum.Material.Metal, { name = "RailPost", collide = false, query = false })
		end
		s += POST_PITCH
	end

	local lights = 0
	local idx = 0
	local headL, headH, headD = m(0.75), m(0.18), m(0.32)
	s = LAMP_PITCH / 2
	while s < total do
		idx += 1
		local seg, l = locate(segs, s)
		local zLamp = 0
		for _, side in { -1, 1 } do
			local base = worldAt(seg, side * EDGE_X, FASCIA_TOP, l)
			zLamp = base.Z
			Kit.vcyl(parent, base + Vector3.new(0, (LAMP_H + 0.2) / 2 - 0.2, 0), LAMP_H + 0.2, m(0.2), POLE_C, Enum.Material.Metal, { name = "LampPole", collide = true })
			-- 암: 기둥 꼭대기에서 차도 쪽으로
			Kit.box(parent, CFrame.new(base + Vector3.new(-side * LAMP_ARM / 2, LAMP_H, 0)), Vector3.new(LAMP_ARM + m(0.1), m(0.1), m(0.12)), POLE_C, Enum.Material.Metal, { name = "LampArm", collide = false, query = false })
			-- 등기구 머리(암 끝) + 아래 발광 렌즈
			local hx = -side * (LAMP_ARM - headL / 2 + m(0.1))
			Kit.box(parent, CFrame.new(base + Vector3.new(hx, LAMP_H + headH / 2 - m(0.03), 0)), Vector3.new(headL, headH, headD), POLE_C, Enum.Material.Metal, { name = "LampHead", collide = false, query = false })
			local lensPos = base + Vector3.new(hx, LAMP_H - m(0.08), 0)
			local lens = Kit.box(
				parent,
				CFrame.new(lensPos),
				Vector3.new(headL - m(0.08), m(0.12), headD - m(0.05)),
				LAMP_LENS,
				Enum.Material.Neon,
				neon("LampLens", LAMP_LENS, Enum.Material.Glass, rgb(200, 200, 192))
			)
			-- 글레어(눈부심 번짐): 실물 아님. 원경에서 등 머리가 사진처럼 빛점으로 읽히도록 하는 반투명 Neon 구
			Kit.ball(parent, lensPos - Vector3.new(0, m(0.1), 0), m(1.1), LAMP_GLARE, Enum.Material.Neon, neon("LampGlare", LAMP_GLARE, Enum.Material.Glass, rgb(200, 200, 192), 0.62))
			-- 실제 광원: 가까운 쪽에서 쌍마다 한쪽씩(번갈아)
			if lights < LAMP_LIGHTS and zLamp > -m(120) and (idx % 2 == 0) == (side < 0) then
				if Kit.light(lens, "SpotLight", { color = P.LampSodium, brightness = 2.6, range = 50, angle = 115, face = Enum.NormalId.Bottom }) then
					lights += 1
				end
			end
		end
		-- 수면 위 가로등 쌍 → 짧은 반사 스트릭(카메라 쪽 서측 가장자리 앞)
		if zLamp > F.WaterEdge + m(4) and zLamp < N.WaterEdge - m(10) then
			Kit.reflection(reflParent, BX - EDGE_X + LAMP_ARM - m(1), zLamp + m(1), m(1.3), rng:NextNumber(m(35), m(58)), LAMP_REF, 0.8)
		end
		s += LAMP_PITCH
	end
end

------------------------------------------------------------------------------------------------------
-- 교각 / 교대
------------------------------------------------------------------------------------------------------
local pierLights = 0

local function uplightFixture(parent: Instance, pos: Vector3, withLight: boolean)
	local fix = Kit.box(parent, CFrame.new(pos), Vector3.new(m(0.5), m(0.18), m(0.3)), UPLIGHT, Enum.Material.Neon, neon("Uplight", UPLIGHT, Enum.Material.Metal, METAL))
	if withLight and pierLights < PIER_LIGHTS then
		if Kit.light(fix, "SpotLight", { color = UPLIGHT, brightness = 5, range = 50, angle = 45, face = Enum.NormalId.Top }) then
			pierLights += 1
		end
	end
end

local function buildPier(parent: Instance, reflParent: Instance, z: number, rng: Random)
	local isWater = z > F.WaterEdge and z < N.WaterEdge
	local gb = deckY(z) - GIRDER_D -- 거더 바닥
	local ground = if isWater then L.Water else Kit.groundY(BX, z)
	local footTop = if isWater then FOOT_TOP_W else ground + m(0.3)
	local capTop = gb - BEARING_GAP
	-- 기초
	if isWater then
		local yb = L.Water - m(4)
		Kit.box(parent, CFrame.new(BX, (yb + footTop) / 2, z), Vector3.new(COL_X * 2, footTop - yb, FOOT_D), CONC_PIER, Enum.Material.Concrete, { name = "Footing" })
		for _, side in { -1, 1 } do
			-- 둥근 코(흐름 방향 = X). 윗면은 상자보다 0.3 낮게(동일 평면 회피)
			local top = footTop - 0.3
			Kit.vcyl(parent, Vector3.new(BX + side * COL_X, (yb + top) / 2, z), top - yb, FOOT_D, CONC_PIER, Enum.Material.Concrete, { name = "FootingNose" })
		end
	else
		local yb = ground - m(1)
		Kit.box(parent, CFrame.new(BX, (yb + footTop) / 2, z), Vector3.new(COL_X * 2 + COL_D + m(2), footTop - yb, COL_D + m(1.5)), CONC_PIER, Enum.Material.Concrete, { name = "Footing" })
	end

	if capTop - CAP_H - footTop < m(2) then
		-- 낮은 지점: 벽식 교각
		local wallTop = capTop - m(0.1)
		local h = wallTop - (footTop - 0.2)
		Kit.box(parent, CFrame.new(BX, (footTop - 0.2 + wallTop) / 2, z), Vector3.new(GIRDER_HALF * 2 - m(1), h, m(1.5)), CONC_PIER, Enum.Material.Concrete, { name = "PierWall" })
		Kit.box(parent, CFrame.new(BX, (wallTop + gb) / 2 + 0.1, z), Vector3.new(GIRDER_HALF * 2 - m(2.5), gb - wallTop + 0.2, m(0.8)), CONC_GIRDER, Enum.Material.Concrete, { name = "Bearing", collide = false, query = false })
		uplightFixture(parent, Vector3.new(BX - COL_X, footTop + m(0.1), z + m(1.5)), false)
		return
	end

	local capBot = capTop - CAP_H
	-- 쌍기둥 + 세척광 외피 + 등기구
	for _, side in { -1, 1 } do
		local cx = BX + side * COL_X
		local y0, y1 = footTop - 0.2, capBot + 0.2
		Kit.vcyl(parent, Vector3.new(cx, (y0 + y1) / 2, z), y1 - y0, COL_D, CONC_PIER, Enum.Material.Concrete, { name = "Column" })
		-- 업라이트 감쇠: 아래(밝음) 55 % + 위(옅음) 45 %
		local s0, s1 = footTop + 0.3, capBot - 0.3
		local sm = s0 + (s1 - s0) * 0.55
		Kit.vcyl(parent, Vector3.new(cx, (s0 + sm) / 2, z), sm - s0, COL_D + 0.8, SHEATH_C, Enum.Material.Neon, neon("ColumnWash", SHEATH_C, Enum.Material.Glass, CONC_PIER, 0.56))
		Kit.vcyl(parent, Vector3.new(cx, (sm + 0.1 + s1) / 2, z), s1 - sm - 0.1, COL_D + 0.8, SHEATH_TOP, Enum.Material.Neon, neon("ColumnWashTop", SHEATH_TOP, Enum.Material.Glass, CONC_PIER, 0.74))
		uplightFixture(parent, Vector3.new(cx, footTop + m(0.09), z + COL_D / 2 + m(0.6)), isWater and side < 0)
	end
	-- 해머헤드 캡 + 아래쪽 테이퍼(웨지: 평면이 위, 두꺼운 쪽이 기둥)
	Kit.box(parent, CFrame.new(BX, capBot + CAP_H / 2, z), Vector3.new(CAP_W, CAP_H, CAP_D), CONC_PIER, Enum.Material.Concrete, { name = "PierCap" })
	local wl = CAP_W / 2 - COL_X - COL_D / 2 + 0.3
	local wh = m(1.2)
	for _, side in { -1, 1 } do
		local pos = Vector3.new(BX + side * (CAP_W / 2 - wl / 2), capBot - wh / 2, z)
		local cf = CFrame.lookAt(pos, pos + Vector3.new(side, 0, 0)) * CFrame.Angles(0, 0, math.pi)
		Kit.wedge(parent, cf, Vector3.new(CAP_D - 0.3, wh, wl), CONC_PIER, Enum.Material.Concrete, { name = "CapTaper" })
		-- 받침(캡 윗면 → 거더 바닥, 양끝 0.1 묻힘)
		Kit.box(parent, CFrame.new(BX + side * COL_X, (capTop + gb) / 2, z), Vector3.new(m(1.0), gb - capTop + 0.2, m(1.0)), CONC_GIRDER, Enum.Material.Concrete, { name = "Bearing", collide = false, query = false })
	end
	-- 캡 앞뒤면 세척광 막
	for _, dz in { 1, -1 } do
		Kit.box(parent, CFrame.new(BX, capBot + CAP_H / 2, z + dz * (CAP_D / 2 + 0.4)), Vector3.new(CAP_W - m(1), CAP_H - m(0.3), 0.2), WASH_C, Enum.Material.Neon, neon("CapWash", WASH_C, Enum.Material.Glass, CONC_PIER, 0.55))
	end

	if isWater then
		Kit.reflection(reflParent, BX - COL_X, z + FOOT_D / 2 + m(1), m(3.5), rng:NextNumber(m(65), m(100)), PIER_REF, 0.74)
	end
end

local function buildAbutment(parent: Instance, zToe: number, zCrest: number)
	-- 사면 발치(둔치 쪽)에서 제방 마루 안쪽까지 묻힌 콘크리트 블록. 윗면 = 거더 바닥 아래 0.3
	local dir = if zCrest > zToe then 1 else -1
	local zFront = zToe - dir * m(0.3)
	local zBack = zCrest + dir * m(0.6)
	local top = deckY(zToe) - GIRDER_D - 0.3
	local bot = L.Promenade - m(0.3)
	Kit.box(parent, CFrame.new(BX, (bot + top) / 2, (zFront + zBack) / 2), Vector3.new(B.Width, top - bot, math.abs(zBack - zFront)), CONC_PIER, Enum.Material.Concrete, { name = "Abutment" })
end

------------------------------------------------------------------------------------------------------
-- 양끝 도시 도로 토막 (ZFrom/ZTo ~ 제방 도로 띠, 평탄 Y_END)
--   제방 고속화도로(Riverside)는 실제 8차로 폭 W_ROAD_REAL(32.8 m)로 Config 의 RoadFrom..RoadTo(27 m)보다 도시 쪽으로 넘침.
--   다리 입구에서 Riverside 는 넘친 부분을 비워 두므로 토막의 포장은 RoadTo 까지 덮되, 분리대·보도·차선은 고속도로의
--   실제 가장자리(zEdge = RoadFrom ∓ 32.8 m)에서 끝내고, 고속도로로 들어가는 차로에 정지선(폭 0.45 m)을 그림.
------------------------------------------------------------------------------------------------------
local W_ROAD_REAL = m(32.8) -- Riverside XS.wall[2] (방음벽 바깥면) 과 같은 값

local function buildStub(parent: Instance, zCity: number, zRoad: number, zEdge: number)
	local function span(za: number, zb: number): (number, number)
		return (za + zb) / 2, math.abs(zb - za)
	end
	local function box(x: number, y0: number, y1: number, w: number, za: number, zb: number, o: PartOpts)
		local zc, len = span(za, zb)
		if len < 0.5 then
			return
		end
		Kit.part(parent, CFrame.new(BX + x, Y_END + (y0 + y1) / 2, zc), Vector3.new(w, y1 - y0, len), o)
	end
	local dir = if zRoad > zCity then 1 else -1 -- 도시 → 강(고속도로) 방향
	-- 포장: 도시 끝 ~ 제방 도로 띠(RoadTo). 도시 지면이 아직 없어도 떠 보이지 않도록 깊게(윗면만 지면 위 0.4)
	box(0, -m(3), 0, B.Width, zCity, zRoad, solid("RoadSlab", ASPHALT, Enum.Material.Asphalt))
	-- 분리대·보도·노면표시: 도시 끝 ~ 고속도로 실제 가장자리
	local zM = zEdge - dir * m(1.5) -- 분리대 끝은 가장자리에서 1.5 m 물림(정지선 앞)
	box(0, -0.2, BARRIER_H, BARRIER_HALF * 2, zCity + dir * m(1.5), zM, solid("MedianBarrier", CONC, Enum.Material.Concrete))
	for _, side in { -1, 1 } do
		box(side * (CURB_X + HALF_W) / 2, -0.4, WALK_TOP, HALF_W - CURB_X, zCity, zEdge, solid("Sidewalk", WALK_C, Enum.Material.Pavement))
		box(side * (CURB_X - 0.5 - LINE_W / 2), MARK_T - 0.5, MARK_T, LINE_W, zCity, zEdge - dir * m(0.6), decor("EdgeLine", PAINT_W, Enum.Material.SmoothPlastic))
		box(side * (LANE_X0 + LINE_W / 2), MARK_T - 0.5, MARK_T, LINE_W, zCity, zEdge - dir * m(0.6), decor("CenterLine", PAINT_Y, Enum.Material.SmoothPlastic))
		local len = math.abs(zEdge - zCity)
		for k = 1, 3 do
			local dl = math.min(DASH_LEN, len - m(4))
			local z0 = zCity + dir * m(1)
			box(side * (LANE_X0 + k * LANE_W), MARK_T - 0.5, MARK_T, LINE_W, z0, z0 + dir * dl, decor("LaneDash", PAINT_W, Enum.Material.SmoothPlastic))
		end
	end
	-- 정지선: 고속도로 쪽으로 진행하는 차로(+Z 진행 = -X 쪽, -Z 진행 = +X 쪽; 우측통행)
	local stopSide = if dir > 0 then -1 else 1
	local zs = zEdge - dir * m(0.6)
	box(stopSide * (LANE_X0 + 2 * LANE_W), MARK_T - 0.5, MARK_T, 4 * LANE_W - LINE_W, zs - dir * m(0.45), zs, decor("StopLine", PAINT_W, Enum.Material.SmoothPlastic))
end

------------------------------------------------------------------------------------------------------
-- 차선 (차량 불빛)
------------------------------------------------------------------------------------------------------
local LANE_SPEED = { 65, 62, 58, 55 } -- stud/s: 1차로(중앙, ≈ 70 km/h) → 4차로(바깥, ≈ 60 km/h)

local function registerLanes(zs: { number })
	local pts: { Vector2 } = { Vector2.new(B.ZFrom, Y_END) }
	for _, z in zs do
		table.insert(pts, Vector2.new(z, deckY(z)))
	end
	table.insert(pts, Vector2.new(B.ZTo, Y_END))
	for k = 1, 4 do
		local off = LANE_X0 + (k - 0.5) * LANE_W
		-- +Z(관람자 쪽)로 오는 차: 우측통행 → -X 쪽, 전조등
		local head: { Vector3 } = {}
		for _, p in pts do
			table.insert(head, Vector3.new(BX - off, p.Y + CAR_UP, p.X))
		end
		Kit.lane("Bridge_N" .. k, head, { speed = LANE_SPEED[k], kind = "head", density = 0.9, spacing = m(1.5) })
		-- -Z(잠실 쪽)로 가는 차: +X 쪽, 후미등
		local tail: { Vector3 } = {}
		for i = #pts, 1, -1 do
			local p = pts[i]
			table.insert(tail, Vector3.new(BX + off, p.Y + CAR_UP, p.X))
		end
		Kit.lane("Bridge_S" .. k, tail, { speed = LANE_SPEED[k] - 2, kind = "tail", density = 0.9, spacing = m(1.5) })
	end
end

------------------------------------------------------------------------------------------------------
function Bridge.build(ctx: any)
	local model: Instance = ctx.model
	local rng: Random = ctx.rng
	pierLights = 0

	local function folder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = model
		return f
	end
	local deckF, pierF, lampF, reflF, endF = folder("Deck"), folder("Piers"), folder("Lamps"), folder("Reflections"), folder("Ends")

	local zs, piers = supports()
	local segs, total = makeSegs(zs)

	buildDeck(deckF, segs)
	buildLampsAndPosts(lampF, segs, total, rng, reflF)
	-- 교각: 가까운(관람자) 쪽부터 → 업라이트 SpotLight 예산이 보이는 교각에 먼저 쓰이도록
	table.sort(piers, function(a: number, b: number)
		return a > b
	end)
	for _, z in piers do
		buildPier(pierF, reflF, z, rng)
	end
	buildAbutment(endF, F.ParkTo, Z_A)
	buildAbutment(endF, N.ParkTo, Z_B)
	buildStub(endF, B.ZFrom, F.RoadTo, F.RoadFrom - W_ROAD_REAL)
	buildStub(endF, B.ZTo, N.RoadTo, N.RoadFrom + W_ROAD_REAL)

	registerLanes(zs)

	-- 발자국 예약: 도시 도로 토막 + 둔치/사면/수면 구간(제방 도로 띠는 비워 둠)
	local hw = HALF_W + m(1.2)
	Kit.reserve(BX - hw, B.ZFrom, BX + hw, F.RoadTo, "BridgeRoadFar")
	Kit.reserve(BX - hw, Z_A, BX + hw, Z_B, "Bridge")
	Kit.reserve(BX - hw, N.RoadTo, BX + hw, B.ZTo, "BridgeRoadNear")
end

return Bridge
