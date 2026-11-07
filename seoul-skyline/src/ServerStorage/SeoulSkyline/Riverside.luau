--!strict
-- SeoulSkyline / Riverside
-- 양쪽 강변(공원 내부·다리 제외): 도시 지면 슬래브 · 올림픽대로/강변북로 · 계단식 호안 · 산책로/자전거도로
-- · 둔치 가로등/가로수 줄 · 수변 난간/벤치 · 가로등 수면 반사 · 도시로 들어가는 간선도로(차량 불빛 차선).
--
--   * 높이 층(겹치는 면 없음): 도시 지면 윗면 14.0 / 도로 포장 14.4 / 노면표시 14.75 / 보도 15.0
--                                호안 계단 0.9 · 2.15 / 산책로·자전거도로 3.4 / 노면표시 3.75
--   * 다리(Config.Bridge) 접속부: 다리가 제방 도로 가장자리(SlopeTo)에 평면 교차로로 내려옴 → 분리대·방음벽·
--     가로등·나무·난간을 비우고, 다리 축 간선도로는 다리 토막(ZFrom) 끝에서 같은 폭으로 이어짐.
--   * 간선도로는 앞서 빌드된 랜드마크/고층 발자국을 Kit.isFree 로 피해 꺾어 들어감(직각 jog).
--   * 원거리일수록 단순화(나무 3→2파트→덤불 매스, 가로등 간격 확대)로 파트 예산 유지.

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)

local Riverside = {}

type Span = { number }

local rgb = Color3.fromRGB
local P = Config.Palette
local L = Config.Level
local F, N = Config.FarBank, Config.NearBank
local B = Config.Bridge
local MAT = Enum.Material

------------------------------------------------------------------------------------------------------
-- 상수
------------------------------------------------------------------------------------------------------
local MAXP = 2000 -- 긴 띠 파트 조각 길이(<= 2048)
local GROUND_T = 22 -- 도시 지면 슬래브 두께(윗면 14, 바닥 -8: 제방 사면 끝 수직면을 가림)
local ROAD_TOP = L.City + 0.4 -- 도로 포장 윗면 (다리 토막·랜드마크 광장과 같은 높이)
local PAINT_UP = 0.35 -- 노면표시가 포장보다 높은 양
local CAR_Y = ROAD_TOP + 1.6 -- 차량 불빛 높이
local PATH_TOP = L.Promenade + 0.4 -- 둔치 산책로 윗면 (지형 잔디 3.0 보다 0.4 위)

local ROAD_X0, ROAD_X1 = -6500, 6500 -- 제방 도로 포장 범위
local LANE_X0, LANE_X1 = -5000, 5000 -- 차선(차량 불빛) 범위
local STEP_X0, STEP_X1 = -7000, 7000 -- 호안 계단 = 강 길이
local PATH_X0, PATH_X1 = -6500, 6500

-- 다리 접속부(세로 요소 비움)
local BRIDGE_HALF = B.Width / 2
local GAP_ROAD: Span = { B.X - BRIDGE_HALF - 4, B.X + BRIDGE_HALF + 4 }
local GAP_PARK: Span = { B.X - BRIDGE_HALF - 16, B.X + BRIDGE_HALF + 16 }

-- 제방 도로 단면 (중심선 기준 |오프셋|)
local MEDIAN_W = 1.4
local LANE_IN = 2.2 -- 1차로 안쪽 경계(노란 실선)
local LANE_W = 5.5
local CAR_LANES = { 5.0, 16.0 } -- 차량 불빛 차선 오프셋 (2/4차로 느낌)

-- 간선도로
local AVE_Z0 = F.RoadTo -- 올림픽대로 도시 쪽 가장자리
local AVE_Z1 = -3500
local AVE_HW = 20 -- 일반 간선 반폭(6차로)
local AVE_LAMP = 110 -- 한쪽 가로등 간격(양쪽 엇갈림)

-- 근경 디테일 구간(히어로/산책로 구도에 보이는 X)
local NEAR_VIEW0, NEAR_VIEW1 = -1400, 1200
local NEAR_LIGHT0, NEAR_LIGHT1 = -540, 500 -- 실제 PointLight 를 다는 가까운 쪽 가로등 X 범위
local MAX_LIGHTS = 36

-- 색
local GROUND_C = rgb(80, 81, 86)
local ASPHALT = P.Asphalt
local PAINT_W = rgb(160, 160, 152)
local PAINT_Y = rgb(190, 150, 62)
local BARRIER_C = rgb(134, 134, 136)
local WALL_GLASS = rgb(74, 98, 112)
local POLE_C = rgb(56, 60, 68)
local STEP1_C, STEP2_C = rgb(98, 98, 96), rgb(116, 114, 110)
local WALK_C = rgb(132, 126, 116)
local BIKE_C = rgb(94, 60, 56)
local SIDEWALK_C = rgb(118, 110, 102)
local WOOD_C = rgb(110, 82, 58)
local LEAVES = { rgb(36, 60, 40), rgb(42, 70, 44), rgb(50, 78, 46), rgb(32, 54, 38), rgb(56, 82, 50), rgb(40, 64, 46) }
local LAMP_PROM = rgb(255, 194, 124) -- 둔치 가로등(작은 머리 → 밝게)
local LAMP_ROAD = rgb(232, 150, 76) -- 제방 도로 나트륨 빛(T 바 → 약간 어둡게)
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

local function inGaps(x: number, gaps: { Span }): boolean
	for _, g in gaps do
		if x > g[1] and x < g[2] then
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
local function tryLight(p: BasePart, brightness: number, range: number)
	if lightsUsed >= MAX_LIGHTS then
		return
	end
	if Kit.light(p, "PointLight", { color = P.LampWarm, brightness = brightness, range = range }) then
		lightsUsed += 1
	end
end

------------------------------------------------------------------------------------------------------
-- 1) 도시 지면
------------------------------------------------------------------------------------------------------
local function tiles(parent: Instance, x0: number, x1: number, z0: number, z1: number)
	local za, zb = math.min(z0, z1), math.max(z0, z1)
	local nx = math.ceil((x1 - x0) / MAXP)
	local nz = math.ceil((zb - za) / MAXP)
	local dx, dz = (x1 - x0) / nx, (zb - za) / nz
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			Kit.box(parent, CFrame.new(x0 + dx * (i + 0.5), L.City - GROUND_T / 2, za + dz * (j + 0.5)), Vector3.new(dx, GROUND_T, dz), GROUND_C, MAT.Concrete, { name = "CityGround" })
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 2) 제방 고속화도로 (X 방향)
--   riverSign: 강이 있는 쪽(+1 = +Z).  우측통행: +X 로 가는 차는 +Z 쪽 차로.
------------------------------------------------------------------------------------------------------
local function lampMedian(parent: Instance, x: number, zc: number)
	local base = ROAD_TOP + 2.2
	local top = ROAD_TOP + 13.5
	Kit.vcyl(parent, Vector3.new(x, (base + top) / 2, zc), top - base + 0.4, 0.8, POLE_C, MAT.Metal, deco("LampPole"))
	-- 양쪽 차로 위로 뻗은 LED T 바 (멀리서는 한 점의 불빛)
	Kit.box(parent, CFrame.new(x, top + 0.25, zc), Vector3.new(1.1, 0.5, 12), LAMP_ROAD, MAT.Neon, glowOpts("LampBar"))
end

local function expressway(parent: Instance, name: string, z0: number, z1: number, riverSign: number, slabBottom: number, cityGaps: { Span }, lampNear: number, lampFar: number)
	local zc = (z0 + z1) / 2
	local half = math.abs(z1 - z0) / 2
	local gaps = { GAP_ROAD }
	-- 포장
	stripX(parent, ROAD_X0, ROAD_X1, zc, half * 2, ROAD_TOP, ROAD_TOP - slabBottom, ASPHALT, MAT.Asphalt, { name = "Road" })
	-- 노면표시: 방향별 노란 안쪽선 + 가운데 차로선 + 바깥 실선
	for _, side in { -1, 1 } do
		local function line(off: number, w: number, c: Color3)
			stripX(parent, ROAD_X0, ROAD_X1, zc + side * off, w, ROAD_TOP + PAINT_UP, 0.6, c, MAT.SmoothPlastic, deco("Paint", { shadow = false }))
		end
		line(LANE_IN, 0.45, PAINT_Y)
		line(LANE_IN + LANE_W * 2, 0.35, PAINT_W)
		line(half - 3.0, 0.45, PAINT_W)
	end
	-- 중앙분리대 (다리 교차로에서 끊김)
	stripX(parent, ROAD_X0, ROAD_X1, zc, MEDIAN_W, ROAD_TOP + 2.2, 2.6, BARRIER_C, MAT.Concrete, { name = "Median" }, gaps)
	-- 강 쪽: 콘크리트 방호벽
	stripX(parent, ROAD_X0, ROAD_X1, zc + riverSign * (half - 0.6), 1.2, ROAD_TOP + 2.4, 2.8, BARRIER_C, MAT.Concrete, { name = "Parapet" }, gaps)
	-- 도시 쪽: 방음벽 (콘크리트 기단 + 반투명 패널)
	local wz = zc - riverSign * (half - 0.6)
	local cg = table.clone(cityGaps)
	table.insert(cg, GAP_ROAD)
	stripX(parent, ROAD_X0, ROAD_X1, wz, 1.2, ROAD_TOP + 1.8, 2.2, BARRIER_C, MAT.Concrete, { name = "SoundWallBase" }, cg)
	stripX(parent, ROAD_X0, ROAD_X1, wz, 0.5, ROAD_TOP + 6.6, 5.1, WALL_GLASS, MAT.Glass, deco("SoundWall", { transparency = 0.55, collide = true }), cg)
	-- 중앙 가로등
	for _, x in stations(LANE_X0, LANE_X1, -2400, 2400, lampNear, lampFar) do
		if not inGaps(x, { { GAP_ROAD[1] - 4, GAP_ROAD[2] + 4 } }) then
			lampMedian(parent, x, zc)
		end
	end
	-- 차량 불빛 차선: +X 방향 = 후미등(tail), -X 방향 = 전조등(head)
	for i, off in CAR_LANES do
		local zPlus = zc + off -- +X 로 가는 차는 +Z 쪽
		local zMinus = zc - off
		Kit.lane(string.format("%s_E%d", name, i), { Vector3.new(LANE_X0, CAR_Y, zPlus), Vector3.new(LANE_X1, CAR_Y, zPlus) }, { kind = "tail", speed = 72 - i * 8, density = 0.9 })
		Kit.lane(string.format("%s_W%d", name, i), { Vector3.new(LANE_X1, CAR_Y, zMinus), Vector3.new(LANE_X0, CAR_Y, zMinus) }, { kind = "head", speed = 74 - i * 8, density = 0.9 })
	end
	Kit.reserve(-9000, math.min(z0, z1), 9000, math.max(z0, z1), name)
end

------------------------------------------------------------------------------------------------------
-- 3) 강변: 계단식 호안 + 산책로 + 자전거도로 (sign: 육지 방향, 먼 쪽 -1 / 가까운 쪽 +1)
------------------------------------------------------------------------------------------------------
local PROM_IN, PROM_OUT = 9, 26 -- 산책로: 수면 경계에서 +9 ~ +26
local BIKE_IN, BIKE_OUT = 32, 42 -- 자전거도로
local function bankEdge(parent: Instance, edge: number, sign: number)
	local function zr(a: number, b: number): (number, number)
		local p, q = edge + sign * a, edge + sign * b
		return (p + q) / 2, math.abs(q - p)
	end
	-- 계단 2단 (물속에서 시작) + 산책로
	local z, w = zr(-4, 3)
	stripX(parent, STEP_X0, STEP_X1, z, w, L.Water + 0.9, 7.0, STEP1_C, MAT.Concrete, { name = "RevetStep" })
	z, w = zr(3, PROM_IN)
	stripX(parent, STEP_X0, STEP_X1, z, w, L.Water + 2.15, 8.2, STEP2_C, MAT.Concrete, { name = "RevetStep" })
	z, w = zr(PROM_IN, PROM_OUT)
	stripX(parent, PATH_X0, PATH_X1, z, w, PATH_TOP, 5.5, WALK_C, MAT.Pavement, { name = "Promenade" })
	z, w = zr(BIKE_IN, BIKE_OUT)
	stripX(parent, PATH_X0, PATH_X1, z, w, PATH_TOP, 3.0, BIKE_C, MAT.Asphalt, { name = "BikePath" })
	stripX(parent, PATH_X0, PATH_X1, z, 0.3, PATH_TOP + PAINT_UP, 0.6, PAINT_Y, MAT.SmoothPlastic, deco("BikeLine", { shadow = false }))
end

-- 나무: lod 3 = 줄기 + 수관 2, lod 2 = 줄기 + 수관 1
local function tree(parent: Instance, rng: Random, x: number, z: number, y0: number, s: number, lod: number)
	local th = 6.5 * s
	Kit.vcyl(parent, Vector3.new(x, y0 + th / 2 - 0.5, z), th + 1, 1.1 * s, P.Bark, MAT.Wood, deco("Trunk"))
	local w = rng:NextNumber(13, 17) * s
	local h = w * rng:NextNumber(0.78, 0.95)
	Kit.ellipsoid(parent, CFrame.new(x, y0 + th + h * 0.3, z), Vector3.new(w, h, w * rng:NextNumber(0.85, 1.05)), LEAVES[rng:NextInteger(1, #LEAVES)], MAT.Grass, deco("Canopy"))
	if lod >= 3 then
		local w2 = w * rng:NextNumber(0.6, 0.72)
		local a = rng:NextNumber(0, math.pi * 2)
		Kit.ellipsoid(parent, CFrame.new(x + math.cos(a) * w * 0.2, y0 + th + h * 0.62, z + math.sin(a) * w * 0.2), Vector3.new(w2, w2 * 0.85, w2), LEAVES[rng:NextInteger(1, #LEAVES)], MAT.Grass, deco("Canopy"))
	end
end

-- 둔치 가로등: 기둥 + 등 머리 (+ 갓)
local function promLamp(parent: Instance, x: number, z: number, h: number, head: number, cap: boolean): BasePart
	Kit.vcyl(parent, Vector3.new(x, PATH_TOP + h / 2 - 0.3, z), h + 0.6, 0.45, POLE_C, MAT.Metal, deco("LampPole"))
	local hp = Kit.box(parent, CFrame.new(x, PATH_TOP + h + head * 0.4, z), Vector3.new(head, head * 0.8, head), LAMP_PROM, MAT.Neon, glowOpts("LampHead"))
	if cap then
		Kit.box(parent, CFrame.new(x, PATH_TOP + h + head * 0.8 + 0.2, z), Vector3.new(head + 0.6, 0.4, head + 0.6), POLE_C, MAT.Metal, deco("LampCap"))
	end
	return hp
end

local function farBank(parent: Instance, glints: Instance, rng: Random)
	local e, s = F.WaterEdge, -1
	bankEdge(parent, e, s)
	-- 가로등 줄 (산책로 강 쪽 가장자리) + 수면 반사
	local lampZ = e + s * (PROM_IN + 1.2)
	local n = 0
	for _, x in stations(-5500, 5500, -2600, 2600, 40, 110) do
		if not inGaps(x, { GAP_PARK }) then
			promLamp(parent, x, lampZ, 9, 1.9, false)
			n += 1
			if math.abs(x) <= 2200 and n % 2 == 0 then
				Kit.reflection(glints, x + rng:NextNumber(-2, 2), e + 6, 3.4, 68, GLINT_C, 0.66)
			end
		end
	end
	-- 가로수 줄: 근경 3파트 → 2파트 → 원거리 덤불 매스
	local function treeZ(): number
		return e + s * rng:NextNumber(52, 84)
	end
	local x = -3000
	while x <= 3400 do
		if not inGaps(x, { GAP_PARK }) then
			local lod = if x >= -900 and x <= 1500 then 3 else 2
			tree(parent, rng, x + rng:NextNumber(-4, 4), treeZ(), L.Promenade, rng:NextNumber(0.9, 1.25), lod)
		end
		x += if x >= -900 and x <= 1500 then rng:NextNumber(24, 30) else rng:NextNumber(28, 36)
	end
	for _, dir in { -1, 1 } do
		local xx = if dir < 0 then -3000 - 60 else 3400 + 60
		while math.abs(xx) <= 5800 do
			Kit.ellipsoid(parent, CFrame.new(xx, L.Promenade + 7, e + s * rng:NextNumber(58, 80)), Vector3.new(rng:NextNumber(46, 70), rng:NextNumber(15, 21), rng:NextNumber(20, 30)), LEAVES[rng:NextInteger(1, #LEAVES)], MAT.Grass, deco("TreeMass"))
			xx += dir * rng:NextNumber(80, 105)
		end
	end
end

local function nearBank(parent: Instance)
	local e, s = N.WaterEdge, 1
	bankEdge(parent, e, s)
	local gaps = { GAP_PARK }
	-- 난간: 산책로 강 쪽 가장자리 (상단 레일 + 중간 레일 + 기둥)
	local rz = e + s * (PROM_IN + 0.5)
	stripX(parent, PATH_X0, PATH_X1, rz, 0.35, PATH_TOP + 3.4, 0.35, POLE_C, MAT.Metal, { name = "RailTop", shadow = false }, gaps)
	stripX(parent, PATH_X0, PATH_X1, rz, 0.25, PATH_TOP + 1.9, 0.25, POLE_C, MAT.Metal, deco("RailMid", { shadow = false }), gaps)
	local px = NEAR_VIEW0
	while px <= NEAR_VIEW1 do
		if not inGaps(px, gaps) then
			Kit.box(parent, CFrame.new(px, PATH_TOP + 1.6, rz), Vector3.new(0.3, 3.2, 0.3), POLE_C, MAT.Metal, deco("RailPost"))
		end
		px += if px > -800 and px < 600 then 16 else 32
	end
	-- 가로등 (산책로-자전거도로 사이 잔디 띠) + 벤치
	local lampZ = e + s * ((PROM_OUT + BIKE_IN) / 2)
	for _, x in stations(-4600, 4600, NEAR_VIEW0, NEAR_VIEW1, 32, 120) do
		if not inGaps(x, gaps) then
			local near = x >= NEAR_VIEW0 and x <= NEAR_VIEW1
			local head = promLamp(parent, x, lampZ, 10, 1.3, near)
			if x >= NEAR_LIGHT0 and x <= NEAR_LIGHT1 then
				tryLight(head, 1.3, 26)
			end
			-- 벤치: 가로등 사이, 산책로 안쪽 가장자리에서 물을 향함
			if near and x > -1000 and x < 900 and (math.floor((x - NEAR_VIEW0) / 32) % 2 == 0) then
				local bx, bz = x + 16, e + s * (PROM_OUT - 2.2)
				if not inGaps(bx, gaps) then
					Kit.box(parent, CFrame.new(bx, PATH_TOP + 0.6, bz), Vector3.new(4.4, 1.2, 1.2), STEP2_C, MAT.Concrete, deco("BenchBase"))
					Kit.box(parent, CFrame.new(bx, PATH_TOP + 1.2 + 0.2, bz), Vector3.new(5.2, 0.4, 1.9), WOOD_C, MAT.WoodPlanks, deco("BenchSeat"))
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 5) 간선도로 (먼 쪽 도시): 막히면 옆으로 꺾어 빈 열을 찾음
------------------------------------------------------------------------------------------------------
local function routeAvenue(x0: number, zA: number, zB: number, checkFrom: number, hw: number): { Vector2 }
	local STEP = 20
	local pts: { Vector2 } = { Vector2.new(x0, zA) }
	local function reach(cx: number, from: number): number
		local zb = from
		while zb > zB do
			local zn = math.max(zb - STEP, zB)
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
		if lastZ - zb >= 2 * hw + 20 then
			for k = 0, 16 do
				for _, sg in { -1, 1 } do
					local nx = x + sg * (2 * hw + 12 + k * 20)
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

type AveSpec = { name: string, x: number, hw: number, z0: number, checkFrom: number, walk: boolean, lines: { number }, lanes: { number } }

local function avenue(parent: Instance, spec: AveSpec)
	local hw = spec.hw
	local pts = routeAvenue(spec.x, spec.z0, AVE_Z1, spec.checkFrom, hw + 4)
	if #pts < 2 or math.abs(pts[1].Y - pts[#pts].Y) < 60 then
		return
	end
	local m = Kit.group(parent, spec.name)
	local np = #pts
	for i = 1, np - 1 do
		local a, b = pts[i], pts[i + 1]
		if math.abs(a.X - b.X) < 0.5 then
			-- 세로(Z) 구간: 꺾임 모서리는 세로 구간이 포함
			local x = a.X
			local zTop = if i > 1 then a.Y + hw + 4 else a.Y
			local zBot = if i + 1 < np then b.Y - (hw + 4) else b.Y
			local zTopIn = if i > 1 then zTop - 2 * (hw + 4) else zTop - 4
			local zBotIn = if i + 1 < np then zBot + 2 * (hw + 4) else zBot + 4
			stripZ(m, zTop, zBot, x, hw * 2, ROAD_TOP, 1.0, ASPHALT, MAT.Asphalt, { name = "Avenue" })
			if zTopIn - zBotIn > 20 then
				stripZ(m, zTopIn - 6, zBotIn + 6, x, 1.6, ROAD_TOP + 0.9, 1.3, BARRIER_C, MAT.Concrete, { name = "AveMedian" })
				for _, off in spec.lines do
					for _, sd in { -1, 1 } do
						stripZ(m, zTopIn, zBotIn, x + sd * off, 0.35, ROAD_TOP + PAINT_UP, 0.6, PAINT_W, MAT.SmoothPlastic, deco("Paint", { shadow = false }))
					end
				end
			end
			local edge = hw
			if spec.walk then
				-- 다리 축 대로: 다리 토막과 같은 보도(아스팔트 위 +0.6)
				for _, sd in { -1, 1 } do
					stripZ(m, zTop, zBot, x + sd * (hw - 4), 8, ROAD_TOP + 0.6, 1.4, SIDEWALK_C, MAT.Pavement, { name = "Sidewalk" })
				end
				edge = hw - 3
			end
			-- 가로등 (양쪽 엇갈림), 기둥은 도로/보도 가장자리 바깥 1.2
			for _, sd in { -1, 1 } do
				local zz = zTopIn - 30 - (if sd > 0 then AVE_LAMP / 2 else 0)
				while zz > zBotIn + 10 do
					local lx = x + sd * (edge + (if spec.walk then 0 else 1.2))
					local baseY = if spec.walk then ROAD_TOP + 0.6 else L.City
					Kit.vcyl(m, Vector3.new(lx, baseY + 6, zz), 12.4, 0.6, POLE_C, MAT.Metal, deco("LampPole"))
					Kit.box(m, CFrame.new(lx - sd * 1.6, baseY + 12.45, zz), Vector3.new(3.6, 0.5, 1.1), LAMP_AVE, MAT.Neon, glowOpts("LampHead"))
					zz -= AVE_LAMP
				end
			end
			Kit.reserve(x - hw - 8, zBot, x + hw + 8, zTop, spec.name)
		else
			-- 가로(X) 구간: 모서리 정사각형은 제외
			local zc = a.Y
			local xa, xb = math.min(a.X, b.X) + hw, math.max(a.X, b.X) - hw
			if xb - xa > 1 then
				Kit.box(m, CFrame.new((xa + xb) / 2, ROAD_TOP - 0.5, zc), Vector3.new(xb - xa, 1.0, (hw + 4) * 2 - 8), ASPHALT, MAT.Asphalt, { name = "AveJog" })
				Kit.box(m, CFrame.new((xa + xb) / 2, ROAD_TOP + PAINT_UP - 0.3, zc), Vector3.new(xb - xa, 0.6, 0.45), PAINT_Y, MAT.SmoothPlastic, deco("Paint", { shadow = false }))
			end
			Kit.reserve(math.min(a.X, b.X), zc - hw - 8, math.max(a.X, b.X), zc + hw + 8, spec.name)
		end
	end
	-- 차량 불빛: 도시로 들어가는 차(-Z) = 후미등(+X 쪽), 강 쪽으로 나오는 차(+Z) = 전조등
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
		Kit.lane(string.format("%s_S%d", spec.name, i), o3, { kind = "tail", speed = 46 - i * 4, density = 0.8 })
		Kit.lane(string.format("%s_N%d", spec.name, i), i3, { kind = "head", speed = 48 - i * 4, density = 0.8 })
	end
end

------------------------------------------------------------------------------------------------------
function Riverside.build(ctx: any)
	local model: Model = ctx.model
	local rng: Random = ctx.rng
	lightsUsed = 0

	-- 1) 도시 지면 (먼 쪽: 올림픽대로 아래부터 / 가까운 쪽: 강변북로 뒤부터)
	local ground = Kit.group(model, "CityGround")
	tiles(ground, -9000, 9000, F.RoadFrom, F.CityTo)
	tiles(ground, -6500, 6500, N.RoadTo, N.CityTo)

	-- 2) 제방 도로
	local aveXs = { -1980, 1640 }
	local aveGaps: { Span } = {}
	for _, ax in aveXs do
		table.insert(aveGaps, { ax - AVE_HW - 2, ax + AVE_HW + 2 })
	end
	local olympic = Kit.group(model, "OlympicDaero")
	expressway(olympic, "OlympicDaero", F.RoadFrom, F.RoadTo, 1, L.City - 1.0, aveGaps, 64, 150)
	local gangbyeon = Kit.group(model, "GangbyeonBukro")
	-- 가까운 쪽은 도시 지면이 RoadTo 부터라 도로 슬래브가 제방 사면 끝(지형)까지 깊게 내려감
	expressway(gangbyeon, "GangbyeonBukro", N.RoadFrom, N.RoadTo, -1, L.City - GROUND_T, {}, 96, 200)
	Kit.reserve(-6500, N.RoadTo, 6500, N.CityFrom, "NearRoadVerge")

	-- 3) 강변 (+ 4) 수면 반사)
	local glints = Kit.group(model, "Glints")
	farBank(Kit.group(model, "FarBank"), glints, rng)
	nearBank(Kit.group(model, "NearBank"))

	-- 5) 간선도로: 다리 축(다리 토막 끝 ZFrom 에서 같은 폭으로) + 좌우 2개
	local avenues = Kit.group(model, "Avenues")
	local bLines = { 8.2, 14.6, 21.0 }
	avenue(avenues, { name = "JamsilAve", x = B.X, hw = BRIDGE_HALF, z0 = B.ZFrom, checkFrom = B.ZFrom, walk = true, lines = bLines, lanes = { 11.4, 24.2 } })
	avenue(avenues, { name = "WestAve", x = aveXs[1], hw = AVE_HW, z0 = AVE_Z0, checkFrom = F.CityFrom, walk = false, lines = { 7.2, 13.6 }, lanes = { 4.4, 10.8 } })
	avenue(avenues, { name = "EastAve", x = aveXs[2], hw = AVE_HW, z0 = AVE_Z0, checkFrom = F.CityFrom, walk = false, lines = { 7.2, 13.6 }, lanes = { 4.4, 10.8 } })

	model:SetAttribute("Lights", lightsUsed)
end

return Riverside
