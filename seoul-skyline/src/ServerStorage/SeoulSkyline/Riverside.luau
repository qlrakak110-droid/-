--!strict
-- SeoulSkyline / Riverside
-- 양쪽 강변(공원 내부·다리 제외): 도시 지면 슬래브 · 올림픽대로/강변북로 · 계단식 호안 · 산책로/자전거도로
-- · 둔치 보안등/가로수 줄 · 수변 난간/벤치/휴지통 · 보안등 수면 반사 · 도시로 들어가는 간선도로(차량 불빛 차선).
--
--   * 실제 스케일(1 stud = 0.3 m). 모든 치수는 Config.m(미터) / Config.Real 로 씀:
--       제방 고속화도로: 왕복 8차로(차로 3.5 m) + 길어깨 + 중앙분리대(폭 0.8 m, 높이 0.9 m) + 강 쪽 방호벽(1.0 m)
--                        + 도시 쪽 방음벽 3.5 m(콘크리트 기단 1 m + 투명 패널) = 단면 32.8 m.
--                        중앙 쌍가로등 11 m, 38 m 간격.  차량 불빛 높이 0.7 m, 전조등 간격 1.45 m.
--       계단식 호안: 단 높이 0.4 m · 디딤 1.1 m × 3단 → 산책로(4 m) → 녹지(보안등 4.5 m·벤치·휴지통) → 자전거도로 3 m.
--       난간 1.1 m(기둥 3 m 간격), 벤치 좌면 0.45 m × 길이 1.8 m, 휴지통 0.9 m, 가로수 8~14 m(수관 5~9 m).
--       간선도로: 다리 축은 다리 폭(36 m: 4+4 차로 3.5 m + 보도 3.5 m), 일반 간선은 6차로(3.25 m) + 보도 3 m.
--         가로등 10 m, 한쪽 40 m 간격(양쪽 엇갈림).
--   * 높이 층(겹치는 면 없음): 도시 지면 윗면 = Config.Level.City / 도로 포장 +0.4 / 노면표시 +0.3 / 보도 +0.5
--                                호안 계단 1.35 · 2.7 · 4.05 / 산책로·자전거도로 = Promenade + 0.4 / 노면표시 +0.3
--   * 8차로는 Config 의 제방 도로 띠(RoadFrom..RoadTo, 27 m)보다 넓어서 도시 쪽(RoadTo..CityFrom 녹지)으로 넘침.
--     다리 입구(Bridge.X ± Width/2)에서는 그 넘친 부분을 비워 다리 토막(Bridge 소유)이 덮게 하고,
--     분리대·방호벽·방음벽·노면표시·차선(차량 불빛)도 끊음.
--   * 간선도로는 앞서 빌드된 랜드마크/고층 발자국을 Kit.isFree 로 피해 꺾어 들어감(직각 jog).
--   * 원거리일수록 단순화(나무 3→2파트→수림 매스, 가로등 간격 확대)로 파트 예산 유지.
--   * 가까운 쪽 소유 범위(Z): 호안~자전거도로 [N.WaterEdge - 7.3, N.WaterEdge + NEAR_OWN] — 그 너머는 Park.

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)

local Riverside = {}

type Span = { number }

local rgb = Color3.fromRGB
local m = Config.m
local P = Config.Palette
local L = Config.Level
local F, N = Config.FarBank, Config.NearBank
local B = Config.Bridge
local R = Config.River
local Z = Config.Zones
local MAT = Enum.Material

------------------------------------------------------------------------------------------------------
-- 상수 (studs; 실측은 m())
------------------------------------------------------------------------------------------------------
local MAXP = 2000 -- 긴 띠 파트 조각 길이(<= 2048)
local GROUND_BOT = L.Promenade - m(6) -- 도시 지면 슬래브 바닥(제방 사면 끝 지형 아래까지 내려 틈을 가림)
local ROAD_TOP = L.City + 0.4 -- 도로 포장 윗면 (다리 토막·랜드마크 광장과 같은 높이)
local PAINT_UP = 0.3 -- 노면표시가 포장보다 높은 양
local CURB_UP = m(0.15) -- 보도 연석 높이
local CAR_Y = ROAD_TOP + m(0.7) -- 차량 불빛 높이
local CAR_SPACING = m(1.45) -- 전조등 두 개 간격
local PATH_TOP = L.Promenade + 0.4 -- 둔치 산책로 윗면 (지형 잔디 Promenade 보다 0.4 위)

local ROAD_X0, ROAD_X1 = R.XMin, R.XMax -- 먼 쪽 제방 도로 포장 범위(강 길이)
local NEAR_X0, NEAR_X1 = Z.CarpetNear.XMin, Z.CarpetNear.XMax -- 가까운 쪽 도로·도시 지면
local LANE_X = 8500 -- 차선(차량 불빛) 범위 ±
local MARK_X, DIV_X = 6000, 4000 -- 가장자리선 / 차선 구분선 범위 ± (먼 곳은 생략)
local BANK_X0, BANK_X1 = R.XMin, R.XMax -- 호안·산책로 = 강 길이

-- 다리 입구(교차로): 분리대·방호벽·방음벽·차선이 끊기는 X 범위
local BRIDGE_HALF = B.Width / 2
local GAP_MOUTH: Span = { B.X - BRIDGE_HALF, B.X + BRIDGE_HALF }
local GAP_PARK: Span = { B.X - BRIDGE_HALF - m(4), B.X + BRIDGE_HALF + m(4) } -- 둔치: 다리 밑 나무/보안등/난간 비움

-- 제방 고속화도로 단면: 강 쪽 가장자리(RoadFrom)에서 도시 쪽으로 u (m)
local XS = {
	parapet = { 0.0, 0.5 }, -- 강 쪽 콘크리트 방호벽 (높이 1.0 m)
	carA = { 1.5, 15.5 }, -- 강 쪽 차로 4 × 3.5 m (바깥 길어깨 1.0 m)
	median = { 16.0, 16.8 }, -- 중앙분리대 (안쪽 길어깨 0.5 m 씩)
	carB = { 17.3, 31.3 }, -- 도시 쪽 차로 4 × 3.5 m
	wall = { 32.3, 32.8 }, -- 방음벽 (바깥 길어깨 1.0 m)
}
local W_ROAD = m(XS.wall[2]) -- 32.8 m
local LANE_M = 3.5
local PARAPET_H, MEDIAN_H = m(1.0), m(0.9)
local WALL_BASE_H, WALL_H = m(1.0), m(3.5)
local XLAMP_H, XLAMP_ARM = m(11), m(5.0) -- 중앙 쌍가로등 높이 / 양팔 등기구 폭
local XLAMP_PITCH = m(38)
local LAMP_X_FAR, LAMP_X_NEAR = 8500, 5000

-- 강변 단면: 수면 경계에서 육지 쪽으로 u (studs)
local STEP_RISE = m(0.405)
local STEP_TREAD = m(1.1)
local STEP_U0 = -m(2.2) -- 맨 아래 단은 물속에서 시작
local PROM_IN = 3 * STEP_TREAD -- 산책로 시작 (3단 계단 뒤)
local PROM_OUT = PROM_IN + m(4.0) -- 산책로 4 m
local BIKE_IN = PROM_OUT + m(2.8) -- 보안등·벤치 녹지 2.8 m
local BIKE_OUT = BIKE_IN + m(3.0) -- 자전거도로 3 m
local VERGE_U = (PROM_OUT + BIKE_IN) / 2 -- 보안등 줄
local NEAR_OWN = BIKE_OUT + m(1.8) -- 가까운 쪽 소유 끝(그 너머 Park)
local PLAMP_H = Config.Real.ParkLamp -- 보안등 4.5 m
local PLAMP_PITCH_NEAR, PLAMP_PITCH_FAR = m(25), m(30)

-- 근경 디테일 구간(히어로/산책로 구도에 보이는 X)
local NEAR_VIEW0, NEAR_VIEW1 = -2300, 2000
local NEAR_LIGHT0, NEAR_LIGHT1 = -1050, 700 -- 실제 PointLight 를 다는 가까운 쪽 보안등 X 범위
local FAR_VIEW0, FAR_VIEW1 = -2700, 2700 -- 먼 쪽 가로수 줄 본편 구간(히어로 화면 폭)
local MAX_LIGHTS = 28

-- 간선도로
local AVE_Z1 = Z.ApartmentsFar.ZMin -- 도시 카펫(LOD) 시작까지
local AVE_LAMP = m(40) -- 한쪽 가로등 간격(양쪽 엇갈림)
local AVE_LAMP_H = m(10)

-- 색
local GROUND_C = rgb(80, 81, 86)
local ASPHALT = P.Asphalt
local PAINT_W = rgb(160, 160, 152)
local PAINT_Y = rgb(190, 150, 62)
local BARRIER_C = rgb(134, 134, 136)
local WALL_GLASS = rgb(74, 98, 112)
local POLE_C = rgb(56, 60, 68)
local STEP_C = { rgb(92, 92, 90), rgb(106, 105, 101), rgb(118, 116, 111) }
local WALK_C = rgb(124, 116, 106)
local BIKE_C = rgb(122, 58, 50)
local SIDEWALK_C = rgb(118, 110, 102)
local WOOD_C = rgb(116, 84, 58)
local BIN_C = rgb(62, 74, 66)
local LEAVES = { rgb(36, 60, 40), rgb(42, 70, 44), rgb(50, 78, 46), rgb(32, 54, 38), rgb(56, 82, 50), rgb(40, 64, 46) }
local LAMP_PROM = rgb(255, 194, 124) -- 둔치 보안등
local LAMP_ROAD = rgb(255, 168, 86) -- 제방 도로 나트륨 빛
local LAMP_AVE = rgb(226, 178, 120) -- 도시 간선
local LAMP_DAY = rgb(214, 214, 206)
local GLINT_C = rgb(236, 164, 92)

------------------------------------------------------------------------------------------------------
-- 유틸
------------------------------------------------------------------------------------------------------
local function deco(name: string, extra: { [string]: any }?): any
	local o: { [string]: any } = { name = name, collide = false, query = false }
	if extra then
		for k, v in extra do
			o[k] = v
		end
	end
	return o
end

local function glowOpts(name: string): any
	return { name = name, collide = false, query = false, shadow = false, glow = true, dayMaterial = MAT.SmoothPlastic, dayColor = LAMP_DAY }
end

-- [a,b] 에서 gaps 를 빼고 maxLen 이하 조각으로 나눔
local function spans(a: number, b: number, maxLen: number, gaps: { Span }?): { Span }
	local pieces: { Span } = { { a, b } }
	if gaps then
		for _, g in gaps do
			local nextP: { Span } = {}
			for _, p in pieces do
				if g[2] <= p[1] or g[1] >= p[2] then
					table.insert(nextP, p)
				else
					if g[1] > p[1] then
						table.insert(nextP, { p[1], g[1] })
					end
					if g[2] < p[2] then
						table.insert(nextP, { g[2], p[2] })
					end
				end
			end
			pieces = nextP
		end
	end
	local out: { Span } = {}
	for _, p in pieces do
		local len = p[2] - p[1]
		if len > 0.5 then
			local n = math.ceil(len / maxLen)
			for i = 0, n - 1 do
				table.insert(out, { p[1] + len * i / n, p[1] + len * (i + 1) / n })
			end
		end
	end
	return out
end

local function inGaps(x: number, gaps: { Span }, pad: number?): boolean
	local d = pad or 0
	for _, g in gaps do
		if x > g[1] - d and x < g[2] + d then
			return true
		end
	end
	return false
end

-- X 방향 띠: z = 중심, w = Z 폭, yTop = 윗면, h = 높이
local function stripX(parent: Instance, x0: number, x1: number, z: number, w: number, yTop: number, h: number, color: Color3, mat: Enum.Material, opts: any, gaps: { Span }?)
	for _, s in spans(x0, x1, MAXP, gaps) do
		Kit.box(parent, CFrame.new((s[1] + s[2]) / 2, yTop - h / 2, z), Vector3.new(s[2] - s[1], h, w), color, mat, table.clone(opts))
	end
end

-- Z 방향 띠: x = 중심, w = X 폭
local function stripZ(parent: Instance, z0: number, z1: number, x: number, w: number, yTop: number, h: number, color: Color3, mat: Enum.Material, opts: any)
	local a, b = math.min(z0, z1), math.max(z0, z1)
	for _, s in spans(a, b, MAXP, nil) do
		Kit.box(parent, CFrame.new(x, yTop - h / 2, (s[1] + s[2]) / 2), Vector3.new(w, h, s[2] - s[1]), color, mat, table.clone(opts))
	end
end

-- 일정 간격 위치 목록: 근경 구간 [v0,v1] 은 dNear, 바깥(lim 까지)은 dFar
local function stations(lim0: number, lim1: number, v0: number, v1: number, dNear: number, dFar: number): { number }
	local out: { number } = {}
	local x = v0
	while x <= v1 do
		table.insert(out, x)
		x += dNear
	end
	x = v1 + dFar
	while x <= lim1 do
		table.insert(out, x)
		x += dFar
	end
	x = v0 - dFar
	while x >= lim0 do
		table.insert(out, x)
		x -= dFar
	end
	return out
end

local lightsUsed = 0
local function tryLight(p: BasePart, brightness: number, range: number, color: Color3?)
	if lightsUsed >= MAX_LIGHTS then
		return
	end
	if Kit.light(p, "PointLight", { color = color or P.LampWarm, brightness = brightness, range = range }) then
		lightsUsed += 1
	end
end

------------------------------------------------------------------------------------------------------
-- 1) 도시 지면 (윗면 = L.City, 타일 <= 2048)
------------------------------------------------------------------------------------------------------
local function tiles(parent: Instance, x0: number, x1: number, z0: number, z1: number)
	local za, zb = math.min(z0, z1), math.max(z0, z1)
	local nx = math.ceil((x1 - x0) / MAXP)
	local nz = math.ceil((zb - za) / MAXP)
	local dx, dz = (x1 - x0) / nx, (zb - za) / nz
	local h = L.City - GROUND_BOT
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			Kit.box(parent, CFrame.new(x0 + dx * (i + 0.5), L.City - h / 2, za + dz * (j + 0.5)), Vector3.new(dx, h, dz), GROUND_C, MAT.Concrete, { name = "CityGround", shadow = false })
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 2) 제방 고속화도로 (X 방향, 왕복 8차로)
--   edge = 강 쪽 가장자리 Z (RoadFrom), inland = 도시 방향 부호(먼 쪽 -1 / 가까운 쪽 +1).
--   우측통행: +X 로 가는 차는 +Z 쪽 차로.
------------------------------------------------------------------------------------------------------
type RoadSpec = {
	name: string,
	edge: number,
	inland: number,
	bandEnd: number, -- Config 의 도로 띠 끝(RoadTo): 그 너머(도시 쪽 넘침)는 다리 입구에서 비움
	x0: number,
	x1: number,
	slabBottom: number,
	cityGaps: { Span }, -- 방음벽을 끊는 곳(간선도로 접속)
	lampX: number,
	lampLights: number, -- 다리 입구 근처 가로등에 다는 PointLight 수
}

local function expressway(parent: Instance, spec: RoadSpec)
	local e, s = spec.edge, spec.inland
	local function zAt(um: number): number -- u(미터) → Z
		return e + s * m(um)
	end
	local function zMid(r: { number }): (number, number)
		return (zAt(r[1]) + zAt(r[2])) / 2, m(r[2] - r[1])
	end
	local mouth = { GAP_MOUTH }
	local x0, x1 = spec.x0, spec.x1
	-- 포장: Config 띠 안쪽은 연속, 도시 쪽 넘친 부분은 다리 입구에서 비움
	local uBand = math.abs(spec.bandEnd - e)
	local zb0, zb1 = e, e + s * uBand
	stripX(parent, x0, x1, (zb0 + zb1) / 2, uBand, ROAD_TOP, ROAD_TOP - spec.slabBottom, ASPHALT, MAT.Asphalt, { name = "Road", shadow = false })
	if W_ROAD > uBand + 0.5 then
		-- 도시 쪽 끝은 방음벽 기단 바깥면보다 0.05 안쪽(기단 속) → 두 면이 같은 평면에 겹치지 않음
		local ze = e + s * (W_ROAD - 0.05)
		stripX(parent, x0, x1, (zb1 + ze) / 2, W_ROAD - 0.05 - uBand, ROAD_TOP, ROAD_TOP - spec.slabBottom, ASPHALT, MAT.Asphalt, { name = "Road", shadow = false }, mouth)
	end
	-- 노면표시: 안쪽 노란 실선 + 바깥 흰 실선 + 차로 구분선(흰색, 원거리는 생략)
	local function line(um: number, wm: number, c: Color3, lim: number)
		stripX(parent, math.max(x0, -lim), math.min(x1, lim), zAt(um), m(wm), ROAD_TOP + PAINT_UP, 0.6, c, MAT.SmoothPlastic, deco("Paint", { shadow = false }), mouth)
	end
	for _, cw in { XS.carA, XS.carB } do
		local innerIsHigh = cw == XS.carA -- carA 의 안쪽(분리대 쪽)은 u 가 큰 쪽
		local uIn = if innerIsHigh then cw[2] - 0.15 else cw[1] + 0.15
		local uOut = if innerIsHigh then cw[1] + 0.15 else cw[2] - 0.15
		line(uIn, 0.15, PAINT_Y, MARK_X)
		line(uOut, 0.2, PAINT_W, MARK_X)
		for k = 1, 3 do
			line(cw[1] + LANE_M * k, 0.15, PAINT_W, DIV_X)
		end
	end
	-- 중앙분리대 / 강 쪽 방호벽 (다리 입구에서 끊김). 도로 양끝(맵 끝)에서는 0.1 안쪽에서 끝남(도로 끝면과 같은 평면 회피).
	-- 방호벽은 도로 강 쪽 면보다 0.1 강 쪽으로 나와 그 면을 덮음(같은 평면 회피).
	local zc, w = zMid(XS.median)
	stripX(parent, x0 + 0.1, x1 - 0.1, zc, w, ROAD_TOP + MEDIAN_H, MEDIAN_H + 0.3, BARRIER_C, MAT.Concrete, { name = "Median" }, mouth)
	zc, w = zMid(XS.parapet)
	zc, w = zc - s * 0.05, w + 0.1
	stripX(parent, x0 + 0.1, x1 - 0.1, zc, w, ROAD_TOP + PARAPET_H, PARAPET_H + 0.3, BARRIER_C, MAT.Concrete, { name = "Parapet" }, mouth)
	-- 도시 쪽 방음벽 (콘크리트 기단 1 m + 반투명 패널) — 간선도로 접속부·다리 입구에서 끊김
	local cg = table.clone(spec.cityGaps)
	table.insert(cg, GAP_MOUTH)
	-- 투명 패널은 기단보다 끊기는 곳마다 0.1 짧게(끝면이 기단 끝면과 같은 평면에 겹치지 않음)
	local cgPanel: { Span } = {}
	for _, g in cg do
		table.insert(cgPanel, { g[1] - 0.1, g[2] + 0.1 })
	end
	zc, w = zMid(XS.wall)
	stripX(parent, x0 + 0.1, x1 - 0.1, zc, w, ROAD_TOP + WALL_BASE_H, WALL_BASE_H + 0.3, BARRIER_C, MAT.Concrete, { name = "SoundWallBase" }, cg)
	stripX(parent, x0 + 0.2, x1 - 0.2, zc, m(0.15), ROAD_TOP + WALL_H, WALL_H - WALL_BASE_H + 0.3, WALL_GLASS, MAT.Glass, { name = "SoundWall", transparency = 0.55, shadow = false }, cgPanel)
	-- 중앙 쌍가로등 (11 m, 38 m 간격): 기둥 + 양팔 LED 등기구(멀리서는 한 점의 불빛)
	local zMed = zMid(XS.median)
	local lit = 0
	local xs = stations(-spec.lampX, spec.lampX, -spec.lampX, spec.lampX, XLAMP_PITCH, XLAMP_PITCH)
	table.sort(xs, function(a: number, b: number)
		return math.abs(a - B.X) < math.abs(b - B.X)
	end)
	for _, x in xs do
		if not inGaps(x, mouth, m(3)) then
			local base = ROAD_TOP + MEDIAN_H - 0.3
			Kit.vcyl(parent, Vector3.new(x, (base + XLAMP_H + ROAD_TOP) / 2, zMed), XLAMP_H + ROAD_TOP - base, m(0.25), POLE_C, MAT.Metal, deco("LampPole"))
			local head = Kit.box(parent, CFrame.new(x, ROAD_TOP + XLAMP_H + m(0.1), zMed), Vector3.new(m(0.5), m(0.3), XLAMP_ARM), LAMP_ROAD, MAT.Neon, glowOpts("LampArm"))
			if lit < spec.lampLights then
				lit += 1
				tryLight(head, 1.6, m(24), P.LampSodium)
			end
		end
	end
	-- 차량 불빛 차선: +X 방향 = 후미등(tail), -X 방향 = 전조등(head). 다리 입구에서 끊김.
	local plusZ = if s > 0 then XS.carB else XS.carA -- +Z 쪽 차로(= +X 로 가는 차)
	local minusZ = if s > 0 then XS.carA else XS.carB
	local segs = { { -LANE_X, GAP_MOUTH[1] }, { GAP_MOUTH[2], LANE_X } }
	for k = 1, 4 do
		-- k = 1 은 안쪽(분리대 쪽, 빠름)
		local function laneU(cw: { number }): number
			local inner = if cw == XS.carA then cw[2] else cw[1]
			local dir = if cw == XS.carA then -1 else 1
			return inner + dir * LANE_M * (k - 0.5)
		end
		local zP, zM = zAt(laneU(plusZ)), zAt(laneU(minusZ))
		local spd = m((90 - (k - 1) * 7) / 3.6) -- 90 → 69 km/h
		for j, sg in segs do
			Kit.lane(string.format("%s_E%d_%d", spec.name, k, j), { Vector3.new(sg[1], CAR_Y, zP), Vector3.new(sg[2], CAR_Y, zP) }, { kind = "tail", speed = spd, density = 0.75, spacing = CAR_SPACING })
			Kit.lane(string.format("%s_W%d_%d", spec.name, k, j), { Vector3.new(sg[2], CAR_Y, zM), Vector3.new(sg[1], CAR_Y, zM) }, { kind = "head", speed = spd * 1.02, density = 0.75, spacing = CAR_SPACING })
		end
	end
	Kit.reserve(x0, e, x1, e + s * W_ROAD, spec.name)
end

------------------------------------------------------------------------------------------------------
-- 3) 강변: 계단식 호안 + 산책로 + 자전거도로 (sign: 육지 방향, 먼 쪽 -1 / 가까운 쪽 +1)
------------------------------------------------------------------------------------------------------
local function bankEdge(parent: Instance, edge: number, sign: number)
	local function zr(a: number, b: number): (number, number)
		local p, q = edge + sign * a, edge + sign * b
		return (p + q) / 2, math.abs(q - p)
	end
	-- 계단 3단 (단 높이 0.4 m, 디딤 1.1 m; 맨 아래 단은 물속에서 시작) — 바닥은 지형 호안 사면 속까지
	local stepBot = L.Water - m(2.4)
	for i = 1, 3 do
		local a = if i == 1 then STEP_U0 else STEP_TREAD * (i - 1)
		local z, w = zr(a, STEP_TREAD * i)
		local top = L.Water + STEP_RISE * i
		stripX(parent, BANK_X0, BANK_X1, z, w, top, top - stepBot, STEP_C[i], MAT.Concrete, { name = "RevetStep", shadow = false })
	end
	-- 산책로 4 m (보도블록) — 아래는 호안 사면(지형) 속까지
	local z, w = zr(PROM_IN, PROM_OUT)
	stripX(parent, BANK_X0, BANK_X1, z, w, PATH_TOP, PATH_TOP - (L.Water - m(1.5)), WALK_C, MAT.Pavement, { name = "Promenade", shadow = false })
	-- 자전거도로 3 m (붉은 포장) + 가운데 노란 실선
	z, w = zr(BIKE_IN, BIKE_OUT)
	stripX(parent, BANK_X0, BANK_X1, z, w, PATH_TOP, m(0.6), BIKE_C, MAT.Asphalt, { name = "BikePath", shadow = false })
	stripX(parent, math.max(BANK_X0, -MARK_X), math.min(BANK_X1, MARK_X), z, m(0.12), PATH_TOP + PAINT_UP, 0.6, PAINT_Y, MAT.SmoothPlastic, deco("BikeLine", { shadow = false }))
end

-- 나무(실측 8~14 m, 수관 5~9 m): lod 3 = 줄기 + 수관 2, lod 2 = 줄기 + 수관 1
local function tree(parent: Instance, rng: Random, x: number, z: number, y0: number, lod: number, scale: number?)
	local t = rng:NextNumber() * (scale or 1)
	local H = m(8 + 6 * t) -- 전체 높이
	local D = m(5 + 4 * t + rng:NextNumber(-0.5, 0.5)) -- 수관 지름
	local clear = m(rng:NextNumber(2.2, 3.2)) -- 수관 아래 줄기 높이
	local ch = H - clear
	local trunkH = clear + ch * 0.35
	Kit.vcyl(parent, Vector3.new(x, y0 + trunkH / 2 - 0.25, z), trunkH + 0.5, m(0.28 + 0.14 * t), P.Bark, MAT.Wood, deco("Trunk"))
	Kit.ellipsoid(parent, CFrame.new(x, y0 + clear + ch / 2, z), Vector3.new(D, ch, D * rng:NextNumber(0.88, 1.04)), LEAVES[rng:NextInteger(1, #LEAVES)], MAT.Grass, deco("Canopy"))
	if lod >= 3 then
		local d2 = D * rng:NextNumber(0.58, 0.7)
		local a = rng:NextNumber(0, math.pi * 2)
		Kit.ellipsoid(parent, CFrame.new(x + math.cos(a) * D * 0.24, y0 + clear + ch * 0.66, z + math.sin(a) * D * 0.24), Vector3.new(d2, d2 * 0.9, d2), LEAVES[rng:NextInteger(1, #LEAVES)], MAT.Grass, deco("Canopy"))
	end
end

-- 둔치 보안등 4.5 m: 기둥 + 등 머리(0.5 m) (+ 갓)
local function parkLamp(parent: Instance, x: number, z: number, cap: boolean): BasePart
	local head = m(0.5)
	local ground = L.Promenade - 0.5
	local poleTop = L.Promenade + PLAMP_H - head - m(0.1)
	Kit.vcyl(parent, Vector3.new(x, (ground + poleTop) / 2, z), poleTop - ground, m(0.12), POLE_C, MAT.Metal, deco("LampPole"))
	local hp = Kit.box(parent, CFrame.new(x, poleTop + head / 2, z), Vector3.new(head, head, head), LAMP_PROM, MAT.Neon, glowOpts("LampHead"))
	if cap then
		Kit.box(parent, CFrame.new(x, poleTop + head + m(0.05), z), Vector3.new(head + m(0.15), m(0.1), head + m(0.15)), POLE_C, MAT.Metal, deco("LampCap"))
	end
	return hp
end

local function farBank(parent: Instance, glints: Instance, rng: Random)
	local e, s = F.WaterEdge, -1
	bankEdge(parent, e, s)
	local gaps = { GAP_PARK }
	-- 난간 1.1 m (원경: 손잡이 + 중간 레일만)
	local rz = e + s * (PROM_IN + m(0.12))
	stripX(parent, -6000, 6000, rz, m(0.1), PATH_TOP + Config.Real.Railing, m(0.08), POLE_C, MAT.Metal, { name = "RailTop", shadow = false }, gaps)
	stripX(parent, -6000, 6000, rz, m(0.05), PATH_TOP + m(0.5), m(0.05), POLE_C, MAT.Metal, deco("RailMid", { shadow = false }), gaps)
	-- 보안등 줄 (산책로-자전거도로 사이 녹지) + 수면 반사(2개에 1개, 히어로 화면 안)
	local lampZ = e + s * VERGE_U
	local n = 0
	for _, x in stations(-6000, 6000, FAR_VIEW0, FAR_VIEW1, PLAMP_PITCH_FAR, PLAMP_PITCH_FAR * 2) do
		if not inGaps(x, gaps) then
			parkLamp(parent, x, lampZ, false)
			n += 1
			if math.abs(x) <= 2200 and n % 3 == 0 then
				Kit.reflection(glints, x + rng:NextNumber(-2, 2), e + 8, m(2.0), m(rng:NextNumber(52, 64)), GLINT_C, 0.5)
			end
		end
	end
	-- 가로수 줄(8~14 m): 근경 3파트 → 2파트 → 원거리 수림 매스 (수관이 서로 닿아 짙은 녹색 띠)
	local function treeZ(): number
		return e + s * rng:NextNumber(BIKE_OUT + m(6), BIKE_OUT + m(16))
	end
	local x = FAR_VIEW0
	while x <= FAR_VIEW1 do
		local lod3 = x >= -900 and x <= 1300
		if not inGaps(x, gaps) then
			tree(parent, rng, x + rng:NextNumber(-3, 3), treeZ(), L.Promenade, if lod3 then 3 else 2)
		end
		x += rng:NextNumber(m(8), m(10.5))
	end
	-- 둘째 줄(뒤쪽, 듬성듬성): 틈 사이로 보이는 깊이감
	x = -1300
	while x <= 1600 do
		if not inGaps(x, gaps) then
			tree(parent, rng, x, e + s * rng:NextNumber(m(36), m(44)), L.Promenade, 2)
		end
		x += rng:NextNumber(m(22), m(28))
	end
	-- 화면 밖: 수림 매스(나무 여러 그루 덩어리, 높이 10~12 m)
	for _, dir in { -1, 1 } do
		local xx = if dir < 0 then FAR_VIEW0 - 40 else FAR_VIEW1 + 40
		while math.abs(xx) <= 6200 do
			local hgt = m(rng:NextNumber(10, 12.5))
			Kit.ellipsoid(parent, CFrame.new(xx, L.Promenade + hgt * 0.47, e + s * rng:NextNumber(m(22), m(30))), Vector3.new(m(rng:NextNumber(22, 30)), hgt, m(rng:NextNumber(9, 13))), LEAVES[rng:NextInteger(1, #LEAVES)], MAT.Grass, deco("TreeMass"))
			xx += dir * m(rng:NextNumber(26, 32))
		end
	end
	-- 사면 발치 관목 띠 (높이 2~3 m): 나무 줄기 사이 틈을 메움
	local hx = -2400
	while hx <= 2600 do
		if not inGaps(hx, gaps) then
			local hh = m(rng:NextNumber(2.2, 3.2))
			Kit.ellipsoid(parent, CFrame.new(hx, L.Promenade + hh * 0.3, e + s * rng:NextNumber(m(45), m(48))), Vector3.new(m(rng:NextNumber(14, 20)), hh, m(rng:NextNumber(4, 5.5))), LEAVES[rng:NextInteger(1, #LEAVES)], MAT.Grass, deco("Shrub"))
		end
		hx += m(rng:NextNumber(24, 30))
	end
	Kit.reserve(BANK_X0, F.ParkTo, BANK_X1, e + m(2.2), "FarRiverbank")
end

local function nearBank(parent: Instance, rng: Random)
	local e, s = N.WaterEdge, 1
	bankEdge(parent, e, s)
	local gaps = { GAP_PARK }
	-- 난간 1.1 m: 산책로 강 쪽 가장자리 (손잡이 + 중간 레일 2 + 기둥 3 m 간격, 원거리는 기둥 생략)
	local rz = e + s * (PROM_IN + m(0.12))
	local rx0, rx1 = math.max(BANK_X0, -6000), math.min(BANK_X1, 6000)
	stripX(parent, rx0, rx1, rz, m(0.1), PATH_TOP + Config.Real.Railing, m(0.08), POLE_C, MAT.Metal, { name = "RailTop", shadow = false }, gaps)
	stripX(parent, rx0, rx1, rz, m(0.05), PATH_TOP + m(0.7), m(0.05), POLE_C, MAT.Metal, deco("RailMid", { shadow = false }), gaps)
	stripX(parent, rx0, rx1, rz, m(0.05), PATH_TOP + m(0.3), m(0.05), POLE_C, MAT.Metal, deco("RailMid", { shadow = false }), gaps)
	local postH = Config.Real.Railing - m(0.08)
	for _, px in stations(NEAR_VIEW0, NEAR_VIEW1, -1000, 200, m(3), m(15)) do
		if not inGaps(px, gaps, 1) then
			Kit.box(parent, CFrame.new(px, PATH_TOP + postH / 2 - 0.15, rz), Vector3.new(m(0.07), postH + 0.3, m(0.07)), POLE_C, MAT.Metal, deco("RailPost"))
		end
	end
	-- 보안등 (산책로-자전거도로 사이 녹지) + 벤치(산책로 안쪽 가장자리, 물을 향함) + 휴지통
	local lampZ = e + s * VERGE_U
	local lampXs = stations(-5000, 5000, NEAR_VIEW0, NEAR_VIEW1, PLAMP_PITCH_NEAR, PLAMP_PITCH_NEAR * 4)
	table.sort(lampXs, function(a: number, b: number) -- 히어로/산책로 구도 중앙부터 광원 배정
		return math.abs(a + 200) < math.abs(b + 200)
	end)
	local seatTop = PATH_TOP + m(0.45)
	local benchU = PROM_OUT - m(0.32) -- 좌면 중심(산책로 안쪽 가장자리)
	for _, x in lampXs do
		if not inGaps(x, gaps) then
			local near = x >= NEAR_VIEW0 and x <= NEAR_VIEW1
			local head = parkLamp(parent, x, lampZ, near)
			if x >= NEAR_LIGHT0 and x <= NEAR_LIGHT1 then
				tryLight(head, 1.2, m(11))
			end
			local slot = math.floor((x - NEAR_VIEW0) / PLAMP_PITCH_NEAR + 0.5)
			if near and x > -1500 and x < 1000 and slot % 2 == 0 then
				-- 벤치 1.8 m: 좌면(0.45 m 높이) + 등받이(땅 쪽) + 받침
				local bx = x + PLAMP_PITCH_NEAR / 2
				if not inGaps(bx, gaps, m(2)) then
					local bz = e + s * benchU
					Kit.box(parent, CFrame.new(bx, PATH_TOP + (m(0.39) + 0.1) / 2, bz), Vector3.new(m(1.2), m(0.39) + 0.1, m(0.3)), BARRIER_C, MAT.Concrete, deco("BenchBase"))
					Kit.box(parent, CFrame.new(bx, seatTop - m(0.03), bz), Vector3.new(m(1.8), m(0.06), m(0.45)), WOOD_C, MAT.WoodPlanks, { name = "BenchSeat", shadow = false })
					Kit.box(parent, CFrame.new(bx, seatTop + m(0.22), bz + s * (m(0.225) + 0.15)), Vector3.new(m(1.8), m(0.4), m(0.05)), WOOD_C, MAT.WoodPlanks, deco("BenchBack"))
				end
			elseif near and x > -1500 and x < 1000 and slot % 4 == 1 then
				-- 휴지통 0.9 m (보안등 옆)
				Kit.vcyl(parent, Vector3.new(x + m(1.2), L.Promenade + m(0.45) - 0.2, lampZ), m(0.9) + 0.4, m(0.5), BIN_C, MAT.Metal, deco("TrashBin"))
			end
		end
	end
	local _ = rng
	Kit.reserve(BANK_X0, e - m(2.2), BANK_X1, e + s * NEAR_OWN, "NearRiverbank")
end

------------------------------------------------------------------------------------------------------
-- 5) 간선도로 (먼 쪽 도시): 막히면 옆으로 꺾어 빈 열을 찾음
------------------------------------------------------------------------------------------------------
local ROUTE_STEP = m(10)
local function routeAvenue(x0: number, zA: number, zB: number, checkFrom: number, hw: number): { Vector2 }
	local pts: { Vector2 } = { Vector2.new(x0, zA) }
	local function reach(cx: number, from: number): number
		local zb = from
		while zb > zB do
			local zn = math.max(zb - ROUTE_STEP, zB)
			if not Kit.isFree(cx - hw, zn, cx + hw, zb) then
				break
			end
			zb = zn
		end
		return zb
	end
	local x, z = x0, checkFrom
	for _ = 1, 6 do
		local zb = reach(x, z)
		if zb <= zB then
			table.insert(pts, Vector2.new(x, zB))
			return pts
		end
		local lastZ = pts[#pts].Y
		local bestX: number? = nil
		local bestZ = zb
		if lastZ - zb >= 2 * hw + m(6) then
			for k = 0, 30 do
				for _, sg in { -1, 1 } do
					local nx = x + sg * (2 * hw + m(4) + k * ROUTE_STEP)
					if Kit.isFree(math.min(x, nx) - hw, zb, math.max(x, nx) + hw, zb + 2 * hw) then
						local r = reach(nx, zb)
						if r < bestZ - 1 then
							bestX, bestZ = nx, r
						end
					end
				end
			end
		end
		if bestX == nil then
			table.insert(pts, Vector2.new(x, zb))
			return pts
		end
		local zc = zb + hw
		table.insert(pts, Vector2.new(x, zc))
		table.insert(pts, Vector2.new(bestX, zc))
		x, z = bestX, zb
	end
	table.insert(pts, Vector2.new(x, z))
	return pts
end

-- 진행 방향 오른쪽으로 d 만큼 평행 이동 (직각 꺾임은 모서리 교점)
local function offsetPolyline(pts: { Vector2 }, d: number): { Vector2 }
	local out: { Vector2 } = {}
	local n = #pts
	for i = 1, n do
		local nIn, nOut = Vector2.zero, Vector2.zero
		if i > 1 then
			local t = (pts[i] - pts[i - 1]).Unit
			nIn = Vector2.new(-t.Y, t.X)
		end
		if i < n then
			local t = (pts[i + 1] - pts[i]).Unit
			nOut = Vector2.new(-t.Y, t.X)
		end
		local off: Vector2
		if i == 1 then
			off = nOut * d
		elseif i == n then
			off = nIn * d
		elseif nIn:Dot(nOut) > 0.99 then
			off = nIn * d
		else
			off = (nIn + nOut) * d
		end
		table.insert(out, pts[i] + off)
	end
	return out
end

-- 간선 단면 (studs): carHalf = 중심 → 연석, walk = 보도 폭, medHalf = 중앙분리 반폭, lines = 차로 구분선 오프셋
type Section = { carHalf: number, walk: number, medHalf: number, lines: { number } }

local function section(medM: number, laneM: number, lanes: number, walkM: number): Section
	local lines: { number } = {}
	for k = 1, lanes - 1 do
		table.insert(lines, m(medM + laneM * k))
	end
	return { carHalf = m(medM + laneM * lanes), walk = m(walkM), medHalf = m(medM), lines = lines }
end

type AveSpec = {
	name: string,
	x: number,
	sec: Section, -- 일반 단면
	wide: Section?, -- 첫 직선 구간(다리 토막과 같은 폭)
	z0: number,
	checkFrom: number,
	lanes: { number }, -- 차량 불빛 차선 오프셋(중심선 기준)
}

-- 세로(Z) 도로 한 토막: 포장 [zTop, zBot], 분리대/노면표시/가로등은 [inTop, inBot]
local function avenuePiece(mdl: Instance, name: string, x: number, zTop: number, zBot: number, inTop: number, inBot: number, sec: Section, lampPhase: number)
	local half = sec.carHalf + sec.walk
	stripZ(mdl, zTop, zBot, x, sec.carHalf * 2, ROAD_TOP, 1.0, ASPHALT, MAT.Asphalt, { name = "Avenue", shadow = false })
	for _, sd in { -1, 1 } do
		stripZ(mdl, zTop, zBot, x + sd * (sec.carHalf + sec.walk / 2), sec.walk, ROAD_TOP + CURB_UP, CURB_UP + 1.0, SIDEWALK_C, MAT.Pavement, { name = "Sidewalk", shadow = false })
	end
	if inTop - inBot > m(8) then
		stripZ(mdl, inTop - m(3), inBot + m(3), x, sec.medHalf * 2, ROAD_TOP + m(0.25), m(0.25) + 0.3, BARRIER_C, MAT.Concrete, { name = "AveMedian" })
		for _, off in sec.lines do
			for _, sd in { -1, 1 } do
				stripZ(mdl, inTop, inBot, x + sd * off, m(0.15), ROAD_TOP + PAINT_UP, 0.6, PAINT_W, MAT.SmoothPlastic, deco("Paint", { shadow = false }))
			end
		end
	end
	-- 가로등 10 m (보도 연석 쪽, 팔 1.6 m 가 차도 쪽으로) — 양쪽 엇갈림
	local baseY = ROAD_TOP + CURB_UP
	for _, sd in { -1, 1 } do
		local zz = inTop - m(8) - (if sd > 0 then AVE_LAMP / 2 else 0) - lampPhase
		while zz > inBot + m(3) do
			local lx = x + sd * (sec.carHalf + m(0.6))
			Kit.vcyl(mdl, Vector3.new(lx, baseY + AVE_LAMP_H / 2 - 0.25, zz), AVE_LAMP_H + 0.5, m(0.2), POLE_C, MAT.Metal, deco("LampPole"))
			Kit.box(mdl, CFrame.new(lx - sd * m(0.9), baseY + AVE_LAMP_H + m(0.08), zz), Vector3.new(m(1.9), m(0.16), m(0.4)), LAMP_AVE, MAT.Neon, glowOpts("LampHead"))
			zz -= AVE_LAMP
		end
	end
	Kit.reserve(x - half - m(2), math.min(zTop, zBot), x + half + m(2), math.max(zTop, zBot), name)
end

local function avenue(parent: Instance, spec: AveSpec)
	local sec = spec.sec
	local hw = sec.carHalf + sec.walk
	local hc = hw + m(1.5) -- 경로/모서리 기준 반폭
	local pts = routeAvenue(spec.x, spec.z0, AVE_Z1, spec.checkFrom, hc)
	local np = #pts
	if np < 2 or math.abs(pts[1].Y - pts[np].Y) < m(20) then
		return
	end
	local mdl = Kit.group(parent, spec.name)
	-- 넓은 단면이 들어가는 첫 직선 구간 끝 (첫 꺾임 모서리 전까지, 비어 있는 만큼)
	local zWide: number? = nil
	local wide = spec.wide
	if wide then
		local wHw = wide.carHalf + wide.walk
		local limit = if np > 2 then pts[2].Y + hc else pts[2].Y
		local zb = spec.checkFrom
		while zb - ROUTE_STEP >= limit and Kit.isFree(spec.x - wHw - m(1), zb - ROUTE_STEP, spec.x + wHw + m(1), zb) do
			zb -= ROUTE_STEP
		end
		if zb < spec.z0 - m(12) then
			zWide = zb
		end
	end
	local phase = 0
	for i = 1, np - 1 do
		local a, b = pts[i], pts[i + 1]
		if math.abs(a.X - b.X) < 0.5 then
			-- 세로(Z) 구간: 꺾임 모서리 정사각형은 세로 구간이 포함
			local x = a.X
			local zTop = if i > 1 then a.Y + hc else a.Y
			local zBot = if i + 1 < np then b.Y - hc else b.Y
			local inTop = if i > 1 then zTop - 2 * hc else zTop - m(1)
			local inBot = if i + 1 < np then zBot + 2 * hc else zBot + m(1)
			local zw = zWide
			if i == 1 and zw and wide then
				avenuePiece(mdl, spec.name, x, zTop, zw, inTop, zw, wide, phase)
				if zw - zBot > 1 then
					avenuePiece(mdl, spec.name, x, zw, zBot, zw, inBot, sec, phase)
				end
			else
				avenuePiece(mdl, spec.name, x, zTop, zBot, inTop, inBot, sec, phase)
			end
			phase = (phase + AVE_LAMP / 3) % AVE_LAMP
		else
			-- 가로(X) 구간: 모서리 정사각형 제외
			local zc = a.Y
			local xa, xb = math.min(a.X, b.X) + hw, math.max(a.X, b.X) - hw
			if xb - xa > 1 then
				Kit.box(mdl, CFrame.new((xa + xb) / 2, ROAD_TOP - 0.5, zc), Vector3.new(xb - xa, 1.0, sec.carHalf * 2), ASPHALT, MAT.Asphalt, { name = "AveJog", shadow = false })
				Kit.box(mdl, CFrame.new((xa + xb) / 2, ROAD_TOP + PAINT_UP - 0.3, zc), Vector3.new(xb - xa, 0.6, m(0.15)), PAINT_Y, MAT.SmoothPlastic, deco("Paint", { shadow = false }))
			end
			Kit.reserve(math.min(a.X, b.X), zc - hw - m(2), math.max(a.X, b.X), zc + hw + m(2), spec.name)
		end
	end
	local route: { string } = {}
	for _, p in pts do
		table.insert(route, string.format("%d,%d", p.X, p.Y))
	end
	mdl:SetAttribute("Route", table.concat(route, " "))
	-- 차량 불빛: 도시로 들어가는 차(-Z) = 후미등, 강 쪽으로 나오는 차(+Z) = 전조등
	local rev: { Vector2 } = {}
	for i = np, 1, -1 do
		table.insert(rev, pts[i])
	end
	for i, off in spec.lanes do
		local outP, inP = offsetPolyline(pts, off), offsetPolyline(rev, off)
		local o3: { Vector3 } = {}
		local i3: { Vector3 } = {}
		for _, p in outP do
			table.insert(o3, Vector3.new(p.X, CAR_Y, p.Y))
		end
		for _, p in inP do
			table.insert(i3, Vector3.new(p.X, CAR_Y, p.Y))
		end
		local spd = m((60 - (i - 1) * 6) / 3.6) -- 60 → 54 km/h
		Kit.lane(string.format("%s_S%d", spec.name, i), o3, { kind = "tail", speed = spd, density = 0.7, spacing = CAR_SPACING })
		Kit.lane(string.format("%s_N%d", spec.name, i), i3, { kind = "head", speed = spd * 1.04, density = 0.7, spacing = CAR_SPACING })
	end
end

------------------------------------------------------------------------------------------------------
function Riverside.build(ctx: any)
	local model: Model = ctx.model
	local rng: Random = ctx.rng
	lightsUsed = 0

	-- 1) 도시 지면 (먼 쪽: 올림픽대로 아래부터 / 가까운 쪽: 강변북로 뒤부터)
	local ground = Kit.group(model, "CityGround")
	-- 강 쪽 끝은 제방 도로 강 쪽 면보다 0.05 안쪽(도로 슬래브 속) → 두 면이 같은 평면에 겹치지 않음
	tiles(ground, Z.CarpetFarFar.XMin, Z.CarpetFarFar.XMax, F.RoadFrom - 0.05, F.CityTo)
	tiles(ground, NEAR_X0, NEAR_X1, N.RoadTo, N.CityTo)

	-- 간선도로 단면: 다리 축은 다리 폭(4+4 차로 3.5 m, 분리 1 m, 보도 3.5 m = 36 m), 일반 간선 6차로(3.25 m) + 보도 3 m
	local wideSec = section(0.5, 3.5, 4, B.Width / 2 * Config.METERS_PER_STUD - 14.5)
	local aveSec = section(0.75, 3.25, 3, 3.0)
	local aveXs = { Z.SkylineLeft.XMin - m(140), Z.SkylineRight.XMax + m(295) } -- 서쪽/동쪽 간선 (고층 클러스터 바깥)
	local aveGaps: { Span } = {}
	local aveHalf = aveSec.carHalf + aveSec.walk
	for _, ax in aveXs do
		table.insert(aveGaps, { ax - aveHalf - m(1), ax + aveHalf + m(1) })
	end

	-- 2) 제방 도로 (올림픽대로: 먼 쪽 / 강변북로: 가까운 쪽 — 다리 입구 가로등부터 광원)
	expressway(Kit.group(model, "OlympicDaero"), {
		name = "OlympicDaero",
		edge = F.RoadFrom,
		inland = -1,
		bandEnd = F.RoadTo,
		x0 = ROAD_X0,
		x1 = ROAD_X1,
		slabBottom = L.City - 1.0,
		cityGaps = aveGaps,
		lampX = LAMP_X_FAR,
		lampLights = 4,
	})
	-- 가까운 쪽은 도시 지면이 RoadTo 부터라 도로 슬래브가 제방 사면 끝(지형) 아래까지 깊게 내려감
	expressway(Kit.group(model, "GangbyeonBukro"), {
		name = "GangbyeonBukro",
		edge = N.RoadFrom,
		inland = 1,
		bandEnd = N.RoadTo,
		x0 = NEAR_X0,
		x1 = NEAR_X1,
		slabBottom = GROUND_BOT + 0.5,
		cityGaps = {},
		lampX = LAMP_X_NEAR,
		lampLights = 0,
	})
	Kit.reserve(NEAR_X0, N.RoadFrom + W_ROAD, NEAR_X1, N.CityFrom, "NearRoadVerge")

	-- 3) 강변 (+ 4) 수면 반사)
	local glints = Kit.group(model, "Glints")
	nearBank(Kit.group(model, "NearBank"), rng)
	farBank(Kit.group(model, "FarBank"), glints, rng)

	-- 5) 간선도로: 다리 축(다리 토막 끝 ZFrom 에서 같은 폭으로) + 좌우 2개 (올림픽대로 도시 쪽 가장자리에서 시작)
	local avenues = Kit.group(model, "Avenues")
	local roadCity = F.RoadFrom - W_ROAD
	local aLanes = { m(0.75 + 3.25 * 0.5), m(0.75 + 3.25 * 1.5) }
	local wLanes = { m(0.5 + 3.5 * 0.5), m(0.5 + 3.5 * 1.5), m(0.5 + 3.5 * 2.5) }
	avenue(avenues, { name = "JamsilAve", x = B.X, sec = aveSec, wide = wideSec, z0 = B.ZFrom, checkFrom = B.ZFrom, lanes = wLanes })
	avenue(avenues, { name = "WestAve", x = aveXs[1], sec = aveSec, z0 = roadCity, checkFrom = math.min(roadCity, F.CityFrom), lanes = aLanes })
	avenue(avenues, { name = "EastAve", x = aveXs[2], sec = aveSec, z0 = roadCity, checkFrom = math.min(roadCity, F.CityFrom), lanes = aLanes })

	model:SetAttribute("Lights", lightsUsed)
	model:SetAttribute("NearOwnZ", Vector2.new(N.WaterEdge + STEP_U0, N.WaterEdge + NEAR_OWN))
end

return Riverside
