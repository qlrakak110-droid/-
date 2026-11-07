--!strict
-- SeoulSkyline / Bridge
-- 잠실대교 모티브 다경간 도로교: 강을 Z 방향으로 가로질러 양쪽 둔치·제방을 넘어 도시 도로(Y=14)와 만남.
--
--   * 종단 선형: 양끝(제방 도로 가장자리 F.SlopeTo / N.SlopeTo)은 도시 도로 높이, 강 중앙 ±FLAT_HALF 는 DeckTop.
--     사이는 smoothstep 완경사. 상판은 지점(교각/교대) 사이 직선 세그먼트(기울어진 파트)로 이어지고,
--     같은 기울기의 연속 세그먼트는 하나로 합침.
--   * 단면(중심선 기준): 아스팔트 슬래브 + 박스거더 + 가장자리보(fascia) + 빛띠(Neon) + 보도/연석 + 중앙분리대
--     + 노면표시(실선·점선, 아스팔트 위 MARK_T) + 난간(지주·상/중간 레일) + 양측 가로등(일정 간격, 도로 쪽 암).
--   * 교각: 수중 기초(둥근 코) + 쌍기둥 + 해머헤드 캡(아래 테이퍼 웨지) + 받침.
--     기둥은 반투명 Neon 외피로 따뜻한 업라이트 세척광, 캡 앞면 빛막, 기초의 등기구 + SpotLight(위로).
--     낮은 교각(둔치 끝)은 벽식. 교대: 사면 발치에 콘크리트 블록.
--   * 수면 반사: 수중 교각마다 긴 주황 스트릭, 가로등 쌍마다 짧은 스트릭(Kit.reflection).
--   * 차선: 방향별 4차로 Kit.lane (우측통행: +Z 로 오는 차 = -X 쪽 "head", -Z 로 가는 차 = +X 쪽 "tail").
--   * 예약: 양끝 도시 도로 토막 + 둔치/수면 구간 (제방 도로 띠는 Riverside 가 깔도록 비워 둠).

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)

local Bridge = {}

type PartOpts = Kit.PartOpts

local P = Config.Palette
local B = Config.Bridge
local L = Config.Level
local F, N = Config.FarBank, Config.NearBank
local rgb = Color3.fromRGB

------------------------------------------------------------------------------------------------------
-- 상수
------------------------------------------------------------------------------------------------------
local BX = B.X
local HALF_W = B.Width / 2 -- 36
-- 종단
local Y_END = L.City + 0.4 -- 양끝 노면(도시 도로 윗면보다 0.4 위: z-fighting 방지)
local FLAT_HALF = 150 -- 강 중앙 수평 구간 반폭
local Z_A, Z_B = F.SlopeTo, N.SlopeTo -- 교량 본체 시작/끝(제방 도로 가장자리)
-- 단면 (상판 윗면 = 로컬 y 0)
local SLAB_HALF = HALF_W - 1.0 -- 슬래브는 가장자리보 안쪽에서 끝남
local SLAB_T = 1.8
local GIRDER_HALF = 22
local GIRDER_D = 6 -- 노면 → 박스거더 바닥
local FASCIA_W = 1.2
local FASCIA_TOP, FASCIA_BOT = 1.4, -2.6
local EDGE_X = HALF_W - FASCIA_W / 2 -- 가장자리보 중심(난간·가로등 기초)
local MEDIAN_HALF, MEDIAN_H = 0.8, 2.2
local CURB_X = 28
local WALK_TOP = 0.6
local LANE_W = 6.4
local LANE_X0 = 1.8 -- 1차로 안쪽 경계
local MARK_T = 0.3 -- 노면표시 윗면이 아스팔트보다 높은 양
local DASH_LEN, DASH_PITCH, DASH_OFF = 16, 40, 6
local RAIL_TOP, RAIL_MID = 3.8, 2.6
local POST_PITCH = 24
-- 가로등
local LAMP_PITCH = 36
local LAMP_H = 13
local LAMP_ARM = 5.5
local LAMP_LIGHTS = 16 -- 가로등 SpotLight 수(가까운 쪽 위주)
-- 교각
local COL_X, COL_D = 14, 7
local CAP_W, CAP_D, CAP_H = 52, 9, 3.2
local FOOT_D = 13
local FOOT_TOP_W = L.Water + 1.2
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
local UPLIGHT = rgb(255, 172, 92)
local SHEATH_C = rgb(170, 104, 50) -- 기둥 세척광 외피(반투명)
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
	for k = math.ceil((F.ParkTo + 8) / sp), math.floor((N.ParkTo - 8) / sp) do
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
	for _, seg in segs do
		local len = seg.len
		-- 슬래브(아스팔트 노면) + 박스거더
		along(parent, seg, 0, -SLAB_T, 0, SLAB_HALF * 2, 0, len, solid("DeckSlab", ASPHALT, Enum.Material.Asphalt))
		along(parent, seg, 0, -GIRDER_D, -SLAB_T + 0.2, GIRDER_HALF * 2, 0, len, solid("BoxGirder", CONC_GIRDER, Enum.Material.Concrete))
		-- 중앙분리대
		along(parent, seg, 0, -0.2, MEDIAN_H, MEDIAN_HALF * 2, 0, len, solid("Median", CONC, Enum.Material.Concrete))
		for _, side in { -1, 1 } do
			-- 가장자리보(낮은 방호벽 겸) + 빛띠
			along(parent, seg, side * EDGE_X, FASCIA_BOT, FASCIA_TOP, FASCIA_W, 0, len, solid("Fascia", CONC_FASCIA, Enum.Material.Concrete))
			along(parent, seg, side * (HALF_W + 0.15), -1.5, -0.85, 0.3, 0, len, neon("EdgeLight", EDGE_LED, Enum.Material.Concrete, CONC_FASCIA))
			-- 보도(연석 높이 WALK_TOP, 가장자리보 속으로 0.4 겹침)
			local w0, w1 = CURB_X, SLAB_HALF + 0.2
			along(parent, seg, side * (w0 + w1) / 2, -0.4, WALK_TOP, w1 - w0, 0, len, solid("Sidewalk", WALK_C, Enum.Material.Pavement))
			-- 노면표시: 바깥 실선(흰색), 안쪽 실선(노랑)
			along(parent, seg, side * (CURB_X - 0.6), MARK_T - 0.5, MARK_T, 0.35, 0, len, decor("EdgeLine", PAINT_W, Enum.Material.SmoothPlastic))
			along(parent, seg, side * (LANE_X0 - 0.4), MARK_T - 0.5, MARK_T, 0.35, 0, len, decor("CenterLine", PAINT_Y, Enum.Material.SmoothPlastic))
			-- 난간 레일(상/중간)
			along(parent, seg, side * EDGE_X, RAIL_TOP - 0.15, RAIL_TOP + 0.15, 0.35, 0, len, solid("RailTop", METAL, Enum.Material.Metal))
			along(parent, seg, side * EDGE_X, RAIL_MID - 0.1, RAIL_MID + 0.1, 0.25, 0, len, decor("RailMid", METAL, Enum.Material.Metal))
			-- 차선 점선(전역 위상으로 세그먼트를 넘어 이어짐)
			for k = 1, 3 do
				local x = side * (LANE_X0 + k * LANE_W)
				local m = math.floor((seg.s0 - DASH_OFF) / DASH_PITCH)
				while m * DASH_PITCH + DASH_OFF < seg.s0 + len do
					local a = math.max(m * DASH_PITCH + DASH_OFF, seg.s0)
					local b = math.min(m * DASH_PITCH + DASH_OFF + DASH_LEN, seg.s0 + len)
					if b - a > 1 then
						along(parent, seg, x, MARK_T - 0.5, MARK_T, 0.3, a - seg.s0, b - seg.s0, decor("LaneDash", PAINT_W, Enum.Material.SmoothPlastic))
					end
					m += 1
				end
			end
		end
	end
end

-- 난간 지주 + 가로등 (월드 수직)
local function buildLampsAndPosts(parent: Instance, segs: { Seg }, total: number, rng: Random, reflParent: Instance)
	local s = POST_PITCH / 2
	while s < total do
		local seg, l = locate(segs, s)
		for _, side in { -1, 1 } do
			local base = worldAt(seg, side * EDGE_X, FASCIA_TOP, l)
			local h = RAIL_TOP + 0.15 - FASCIA_TOP
			Kit.box(parent, CFrame.new(base + Vector3.new(0, h / 2, 0)), Vector3.new(0.3, h, 0.3), METAL, Enum.Material.Metal, { name = "RailPost", collide = false, query = false })
		end
		s += POST_PITCH
	end

	local lights = 0
	local idx = 0
	s = LAMP_PITCH / 2
	while s < total do
		idx += 1
		local seg, l = locate(segs, s)
		local zLamp = 0
		for _, side in { -1, 1 } do
			local base = worldAt(seg, side * EDGE_X, FASCIA_TOP, l)
			zLamp = base.Z
			Kit.vcyl(parent, base + Vector3.new(0, (LAMP_H + 0.2) / 2, 0), LAMP_H + 0.2, 0.55, POLE_C, Enum.Material.Metal, { name = "LampPole", collide = true })
			-- 암: 기둥 꼭대기에서 차도 쪽으로
			Kit.box(parent, CFrame.new(base + Vector3.new(-side * LAMP_ARM / 2, LAMP_H, 0)), Vector3.new(LAMP_ARM + 0.3, 0.35, 0.5), POLE_C, Enum.Material.Metal, { name = "LampArm", collide = false, query = false })
			-- 등기구 머리(암 끝) + 아래 발광 렌즈
			local hx = -side * (LAMP_ARM - 1.1)
			Kit.box(parent, CFrame.new(base + Vector3.new(hx, LAMP_H + 0.05, 0)), Vector3.new(2.8, 0.55, 1.2), POLE_C, Enum.Material.Metal, { name = "LampHead", collide = false, query = false })
			local lens = Kit.box(
				parent,
				CFrame.new(base + Vector3.new(hx, LAMP_H - 0.3, 0)),
				Vector3.new(2.4, 0.3, 0.9),
				LAMP_LENS,
				Enum.Material.Neon,
				neon("LampLens", LAMP_LENS, Enum.Material.Glass, rgb(200, 200, 192))
			)
			-- 실제 광원: 가까운 쪽에서 2쌍마다 한쪽씩(번갈아)
			if lights < LAMP_LIGHTS and zLamp > -250 and idx % 2 == 0 and ((idx // 2) % 2 == 0) == (side < 0) then
				if Kit.light(lens, "SpotLight", { color = P.LampSodium, brightness = 3, range = 34, angle = 120, face = Enum.NormalId.Bottom }) then
					lights += 1
				end
			end
		end
		-- 수면 위 가로등 쌍 → 짧은 반사 스트릭(카메라 쪽 서측 가장자리 앞)
		if zLamp > F.WaterEdge + 8 and zLamp < N.WaterEdge - 20 then
			Kit.reflection(reflParent, BX - HALF_W - 5, zLamp + 2, 2.6, rng:NextNumber(70, 115), LAMP_REF, 0.76)
		end
		s += LAMP_PITCH
	end
end

------------------------------------------------------------------------------------------------------
-- 교각 / 교대
------------------------------------------------------------------------------------------------------
local function uplightFixture(parent: Instance, pos: Vector3, withLight: boolean)
	local fix = Kit.box(parent, CFrame.new(pos), Vector3.new(1.6, 0.6, 1.0), UPLIGHT, Enum.Material.Neon, neon("Uplight", UPLIGHT, Enum.Material.Metal, METAL))
	if withLight then
		Kit.light(fix, "SpotLight", { color = UPLIGHT, brightness = 6, range = 40, angle = 50, face = Enum.NormalId.Top })
	end
end

local function buildPier(parent: Instance, reflParent: Instance, z: number, rng: Random)
	local isWater = z > F.WaterEdge and z < N.WaterEdge
	local gb = deckY(z) - GIRDER_D -- 거더 바닥
	local ground = if isWater then L.Water else Kit.groundY(BX, z)
	local footTop = if isWater then FOOT_TOP_W else ground + 0.8
	local capTop = gb - 0.5
	-- 기초
	if isWater then
		local yb = L.Water - 8
		Kit.box(parent, CFrame.new(BX, (yb + footTop) / 2, z), Vector3.new(COL_X * 2, footTop - yb, FOOT_D), CONC_PIER, Enum.Material.Concrete, { name = "Footing" })
		for _, side in { -1, 1 } do
			-- 둥근 코(흐름 방향 = X). 윗면은 상자보다 0.3 낮게(동일 평면 회피)
			local top = footTop - 0.3
			Kit.vcyl(parent, Vector3.new(BX + side * COL_X, (yb + top) / 2, z), top - yb, FOOT_D, CONC_PIER, Enum.Material.Concrete, { name = "FootingNose" })
		end
	else
		Kit.box(parent, CFrame.new(BX, (ground - 2 + footTop) / 2, z), Vector3.new(COL_X * 2 + 14, footTop - ground + 2, 12), CONC_PIER, Enum.Material.Concrete, { name = "Footing" })
	end

	if capTop - CAP_H - footTop < 6 then
		-- 낮은 지점: 벽식 교각
		local h = capTop - (footTop - 0.2)
		Kit.box(parent, CFrame.new(BX, (footTop - 0.2 + capTop) / 2, z), Vector3.new(GIRDER_HALF * 2 - 4, h, 5), CONC_PIER, Enum.Material.Concrete, { name = "PierWall" })
		Kit.box(parent, CFrame.new(BX, capTop + 0.25, z), Vector3.new(GIRDER_HALF * 2 - 8, 0.7, 3), CONC_GIRDER, Enum.Material.Concrete, { name = "Bearing", collide = false, query = false })
		uplightFixture(parent, Vector3.new(BX - 12, footTop + 0.3, z + 4), false)
		return
	end

	local capBot = capTop - CAP_H
	-- 쌍기둥 + 세척광 외피 + 등기구
	for _, side in { -1, 1 } do
		local cx = BX + side * COL_X
		local y0, y1 = footTop - 0.2, capBot + 0.2
		Kit.vcyl(parent, Vector3.new(cx, (y0 + y1) / 2, z), y1 - y0, COL_D, CONC_PIER, Enum.Material.Concrete, { name = "Column" })
		local s0, s1 = footTop + 0.3, capBot - 0.3
		Kit.vcyl(parent, Vector3.new(cx, (s0 + s1) / 2, z), s1 - s0, COL_D + 0.8, SHEATH_C, Enum.Material.Neon, neon("ColumnWash", SHEATH_C, Enum.Material.Glass, CONC_PIER, 0.62))
		uplightFixture(parent, Vector3.new(cx, footTop + 0.3, z + COL_D / 2 + 1.4), side < 0)
	end
	-- 해머헤드 캡 + 아래쪽 테이퍼(웨지: 평면이 위, 두꺼운 쪽이 기둥)
	Kit.box(parent, CFrame.new(BX, capBot + CAP_H / 2, z), Vector3.new(CAP_W, CAP_H, CAP_D), CONC_PIER, Enum.Material.Concrete, { name = "PierCap" })
	local wl = CAP_W / 2 - COL_X - COL_D / 2
	local wh = 2.4
	for _, side in { -1, 1 } do
		local pos = Vector3.new(BX + side * (COL_X + COL_D / 2 + wl / 2), capBot - wh / 2, z)
		local cf = CFrame.lookAt(pos, pos + Vector3.new(side, 0, 0)) * CFrame.Angles(0, 0, math.pi)
		Kit.wedge(parent, cf, Vector3.new(CAP_D, wh, wl), CONC_PIER, Enum.Material.Concrete, { name = "CapTaper" })
		-- 받침
		Kit.box(parent, CFrame.new(BX + side * COL_X, capTop + 0.25, z), Vector3.new(3.2, 0.7, 3.2), CONC_GIRDER, Enum.Material.Concrete, { name = "Bearing", collide = false, query = false })
	end
	-- 캡 앞면(관람자 쪽 +Z) 세척광 막
	Kit.box(parent, CFrame.new(BX, capBot + CAP_H / 2, z + CAP_D / 2 + 0.4), Vector3.new(CAP_W - 3, CAP_H - 0.8, 0.2), WASH_C, Enum.Material.Neon, neon("CapWash", WASH_C, Enum.Material.Glass, CONC_PIER, 0.55))

	if isWater then
		Kit.reflection(reflParent, BX - COL_X - 1, z + FOOT_D / 2 + 2, 7, rng:NextNumber(130, 200), PIER_REF, 0.66)
	end
end

local function buildAbutment(parent: Instance, zToe: number, zCrest: number)
	-- 사면 발치(둔치 쪽)에서 제방 마루 안쪽까지 묻힌 콘크리트 블록. 윗면 = 거더 바닥 아래 0.3
	local dir = if zCrest > zToe then 1 else -1
	local zFront = zToe - dir * 1
	local zBack = zCrest + dir * 2
	local top = deckY(zToe) - GIRDER_D - 0.3
	local bot = L.Promenade - 1
	Kit.box(parent, CFrame.new(BX, (bot + top) / 2, (zFront + zBack) / 2), Vector3.new(B.Width, top - bot, math.abs(zBack - zFront)), CONC_PIER, Enum.Material.Concrete, { name = "Abutment" })
end

------------------------------------------------------------------------------------------------------
-- 양끝 도시 도로 토막 (제방 도로 바깥 ~ ZFrom/ZTo, 평탄 Y_END)
------------------------------------------------------------------------------------------------------
local function buildStub(parent: Instance, z0: number, z1: number)
	local len = math.abs(z1 - z0)
	if len < 1 then
		return
	end
	local zc = (z0 + z1) / 2
	local cf = CFrame.new(BX, Y_END, zc)
	local function box(x: number, y0: number, y1: number, w: number, o: PartOpts, l: number?)
		local ll = l or len
		Kit.part(parent, cf * CFrame.new(x, (y0 + y1) / 2, 0), Vector3.new(w, y1 - y0, ll), o)
	end
	-- 도시 지면이 아직 없어도 떠 보이지 않도록 깊게(윗면만 지면 위 0.4)
	box(0, -10, 0, B.Width, solid("RoadSlab", ASPHALT, Enum.Material.Asphalt))
	box(0, -0.2, MEDIAN_H * 0.6, MEDIAN_HALF * 2, solid("Median", CONC, Enum.Material.Concrete))
	for _, side in { -1, 1 } do
		box(side * (CURB_X + HALF_W) / 2, -0.4, WALK_TOP, HALF_W - CURB_X, solid("Sidewalk", WALK_C, Enum.Material.Pavement))
		box(side * (CURB_X - 0.6), MARK_T - 0.5, MARK_T, 0.35, decor("EdgeLine", PAINT_W, Enum.Material.SmoothPlastic))
		box(side * (LANE_X0 - 0.4), MARK_T - 0.5, MARK_T, 0.35, decor("CenterLine", PAINT_Y, Enum.Material.SmoothPlastic))
		for k = 1, 3 do
			box(side * (LANE_X0 + k * LANE_W), MARK_T - 0.5, MARK_T, 0.3, decor("LaneDash", PAINT_W, Enum.Material.SmoothPlastic), math.min(DASH_LEN, len - 4))
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 차선 (차량 불빛)
------------------------------------------------------------------------------------------------------
local LANE_SPEED = { 75, 68, 62, 55 } -- 1차로(중앙) → 4차로(바깥)

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
			table.insert(head, Vector3.new(BX - off, p.Y + 1.6, p.X))
		end
		Kit.lane("Bridge_N" .. k, head, { speed = LANE_SPEED[k], kind = "head", density = 1.1 })
		-- -Z(잠실 쪽)로 가는 차: +X 쪽, 후미등
		local tail: { Vector3 } = {}
		for i = #pts, 1, -1 do
			local p = pts[i]
			table.insert(tail, Vector3.new(BX + off, p.Y + 1.6, p.X))
		end
		Kit.lane("Bridge_S" .. k, tail, { speed = LANE_SPEED[k] - 2, kind = "tail", density = 1.1 })
	end
end

------------------------------------------------------------------------------------------------------
function Bridge.build(ctx: any)
	local model: Instance = ctx.model
	local rng: Random = ctx.rng

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
	for _, z in piers do
		buildPier(pierF, reflF, z, rng)
	end
	buildAbutment(endF, F.ParkTo, Z_A)
	buildAbutment(endF, N.ParkTo, Z_B)
	buildStub(endF, B.ZFrom, F.RoadTo)
	buildStub(endF, N.RoadTo, B.ZTo)

	registerLanes(zs)

	-- 발자국 예약: 도시 도로 토막 + 둔치/사면/수면 구간(제방 도로 띠는 비워 둠)
	local hw = HALF_W + 4
	Kit.reserve(BX - hw, B.ZFrom, BX + hw, F.RoadTo, "BridgeRoadFar")
	Kit.reserve(BX - hw, Z_A, BX + hw, Z_B, "Bridge")
	Kit.reserve(BX - hw, N.RoadTo, BX + hw, B.ZTo, "BridgeRoadNear")
end

return Bridge
