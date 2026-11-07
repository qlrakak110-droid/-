--!strict
-- SeoulSkyline / Park
-- 가까운 쪽(+Z) 한강공원 + 관람 전망대(플레이어 스폰).  실측 스케일: 1 stud = 0.3 m (Config.m(미터) → stud).
--
--   * 범위: Z [N.WaterEdge + 24 m, N.SlopeTo] (≈ 780 ~ 1317), X ±800 m. 수변 띠(700 ~ 777)는 Riverside 소유, 다리 축
--     (Bridge.X ± (반폭 + 6 m)) 은 비움. 히어로 구도 하단(Z 790 ~ 965)은 둥근 수관이 촘촘한 "숲 카펫" 띠이고,
--     그 강 쪽 가장자리 산책로의 공원등(4.5 m) 줄이 수관을 아래에서 비춤.
--   * 높이 층(겹치는 면 없음): 잔디(지형) 5.0 / 연결 산책로 +0.4 (이음 원판 +0.1) / 메인·강변 산책로 +0.8
--     (이음 +0.5) / 광장·매점 테라스·주차장 +1.2 / 주차선 +1.5.  교차부는 위층이 아래층을 덮음.
--   * 전망대(60 m): DeckCenter 위 16 x 12 m 데크(유리 난간 1.15 m, 망원경 1.3 m, 벤치 0.45 m), 콘크리트 코어 Ø 3.2 m
--     + 경사 버팀대 4.
--     뒤쪽 원통 유리 계단탑: 가운데 유리 엘리베이터 샤프트(Ø 2.7 m) + 둘레 나선 계단(유효폭 1.6 m,
--     챌판 0.17 m / 디딤판 0.30 m, 한 바퀴 48 단 = 8.2 m) → 꼭대기 착지판 → 데크. 지붕 없음(히어로 좌하단 가림 방지).
--   * 나무: 줄기 1 + 수관 타원체 1~3 개. 높이 8 ~ 14 m, 줄기 Ø 0.3 ~ 0.6 m, 수관 Ø 5 ~ 9 m.
--   * 실제 광원은 MAX_LIGHTS 이내: 전망대 → 광장 → 매점·주차장 → 히어로 띠 공원등 순서(전역 상한에 걸리면 앞쪽 우선).

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)

local Park = {}

local rgb = Color3.fromRGB
local P = Config.Palette
local L = Config.Level
local N = Config.NearBank
local B = Config.Bridge
local V = Config.Viewpoint
local R = Config.Real
local M = Config.m
local MAT = Enum.Material

------------------------------------------------------------------------------------------------------
-- 상수 (레이아웃 = Config 기준 / 사물 = 실측 m)
------------------------------------------------------------------------------------------------------
local PART_BUDGET = 3260
local MAX_LIGHTS = 40

local Z0 = N.WaterEdge + M(24) -- 780: Riverside 수변 띠(~777) 안쪽부터
local Z1 = N.SlopeTo -- 1317: 제방 사면 끝
local X0, X1 = -M(800), M(800) -- 공원 길이 1.6 km
local GROUND = L.Promenade -- 5 (둔치 잔디 윗면)
local CONN_TOP = GROUND + 0.4
local MAIN_TOP = GROUND + 0.8
local PLAZA_TOP = GROUND + 1.2

local BRIDGE_CORR = B.Width / 2 + M(6) -- 다리 축 비움 반폭 (= 80)

-- 히어로 카메라 시선이 Z 에서 지나는 X (화면 하단 중앙)
local function heroX(z: number): number
	local a, b = V.HeroCamPos, V.HeroCamLook
	return a.X + (b.X - a.X) * (a.Z - z) / (a.Z - b.Z)
end
local VIEW_X = heroX(Z0 + M(30)) -- ≈ 76
local BELT_X0, BELT_X1, BELT_Z1 = VIEW_X - M(255), VIEW_X + M(255), Z0 + M(56) -- 히어로 하단 숲 띠 (큰 수관, 촘촘)

-- 산책로 (폭 3 ~ 4 m)
local MAIN_W = M(4)
local CONN_W = M(3)
local EDGE_W = M(3)
local EDGE_Z = Z0 + M(4) -- 숲 앞 강변 쪽 산책로 중심선 (788 ~ 798)
local TREE_Z0 = EDGE_Z + EDGE_W / 2 + M(1)

-- 전망대
local DC = V.DeckCenter
local DY = V.DeckHeight -- 데크 바닥 윗면 (60 m)
local DECK_W, DECK_D = M(16), M(12)
local DECK_DZ = M(1) -- 데크 중심을 DeckCenter 보다 1 m 뒤(+Z)로: 앞 난간 5 m 앞, 히어로 좌하단에서 작게
local RAIL_H = M(1.15) -- 유리 난간 높이 (바닥 기준)
local STAIR_RIN, STAIR_ROUT = M(1.45), M(3.05) -- 나선 계단 (유효폭 1.6 m)
local SHAFT_R = M(1.35) -- 엘리베이터 샤프트 Ø 2.7 m
local RISER, TREAD = M(0.17), M(0.30)
local LAND_W = M(1.6) -- 꼭대기 착지판 폭
local TOWER = Vector2.new(DC.X, DC.Z + DECK_DZ + DECK_D / 2 + M(2.4) + STAIR_ROUT) -- 계단탑 중심 (X, Z)
local PLAZA = Vector2.new(DC.X, DC.Z + M(8))
local PLAZA_R = M(19)

-- 매점 / 피크닉 / 주차장 (옛 레이아웃 × 5/3)
local KIOSK_X = -500
local PICNIC = { -577, 830, -423, 893 } -- x0, z0, x1, z1 (나무 없는 잔디밭)
local LOT_X0, LOT_X1 = -1000, -783
local LOT_Z1 = N.ParkTo - M(10)
local LOT_Z0 = LOT_Z1 - (M(5) * 2 + M(6) + M(2)) -- 2.5 x 5 m 주차칸 2 열 + 통로 6 m

-- 색
local WOOD = rgb(104, 78, 56)
local STEEL = rgb(58, 62, 70)
local STEEL_LIGHT = rgb(150, 156, 164)
local STAIR_C = rgb(168, 164, 156)
local GLASS_C = rgb(124, 154, 176)
local RAIL_GLOW = rgb(104, 80, 54)
local UNDER_GLOW = rgb(214, 176, 126)
local FASCIA_GLOW = rgb(124, 96, 62)
local HELIX_GLOW = rgb(176, 132, 84)
local CAB_GLOW = rgb(226, 196, 150)
local LAMP_HEAD = P.LampWarm
local LAMP_DAY = rgb(214, 214, 206)
local POLE_C = rgb(52, 56, 62)
local BRICK_C = rgb(122, 90, 76)
local PAVE_C = rgb(124, 118, 108)
local EDGE_C = rgb(112, 108, 100)
local PLAZA_C = rgb(108, 104, 98)
local BENCH_WOOD = rgb(110, 82, 58)
local BENCH_BASE = rgb(116, 114, 110)
local BARK = P.Bark
local LEAF_LIGHT = rgb(124, 146, 70)
local LEAF_DARK = rgb(30, 54, 38)
local LEAVES = {
	rgb(60, 102, 56),
	rgb(74, 118, 62),
	rgb(54, 92, 54),
	rgb(84, 126, 66),
	rgb(64, 108, 72),
	rgb(94, 132, 68),
	rgb(50, 86, 54),
	rgb(102, 138, 72),
	rgb(76, 120, 76),
}
local CAR_COLORS = { rgb(222, 222, 224), rgb(150, 154, 160), rgb(28, 30, 34), rgb(36, 44, 70), rgb(132, 30, 30), rgb(92, 94, 98), rgb(210, 206, 196) }

------------------------------------------------------------------------------------------------------
-- 유틸
------------------------------------------------------------------------------------------------------
local function opts(name: string, extra: { [string]: any }?): any
	local o: { [string]: any } = { name = name, collide = false, query = false }
	if extra then
		for k, v in extra do
			o[k] = v
		end
	end
	if o.collide then
		o.query = true -- CanCollide 파트는 CanQuery 를 끌 수 없음
	end
	return o
end

local function glowOpts(name: string, dayColor: Color3?): any
	return { name = name, collide = false, query = false, shadow = false, glow = true, dayMaterial = MAT.SmoothPlastic, dayColor = dayColor or LAMP_DAY }
end

local lightsUsed = 0
local function tryLight(p: BasePart, className: string, props: Kit.LightProps): boolean
	if lightsUsed >= MAX_LIGHTS then
		return false
	end
	if Kit.light(p, className, props) then
		lightsUsed += 1
		return true
	end
	return false
end

local function segDist(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local l2 = dx * dx + dz * dz
	local t = if l2 > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / l2, 0, 1) else 0
	local qx, qz = ax + dx * t - px, az + dz * t - pz
	return math.sqrt(qx * qx + qz * qz)
end

------------------------------------------------------------------------------------------------------
-- 점유 격자 (6 stud 셀): 1 = 길/벤치, 2 = 구조물(광장·매점·주차장), 3 = 히어로 띠의 빛길
------------------------------------------------------------------------------------------------------
local CELL = 6
local grid: { [number]: number } = {}

local function gkey(ix: number, iz: number): number
	return ix * 16384 + iz
end

local function mark(ix: number, iz: number, v: number)
	local k = gkey(ix, iz)
	local cur = grid[k]
	if cur == nil or cur < v then
		grid[k] = v
	end
end

local function markSeg(ax: number, az: number, bx: number, bz: number, r: number, v: number)
	local ix0, ix1 = math.floor((math.min(ax, bx) - r) / CELL), math.floor((math.max(ax, bx) + r) / CELL)
	local iz0, iz1 = math.floor((math.min(az, bz) - r) / CELL), math.floor((math.max(az, bz) + r) / CELL)
	for ix = ix0, ix1 do
		for iz = iz0, iz1 do
			if segDist((ix + 0.5) * CELL, (iz + 0.5) * CELL, ax, az, bx, bz) <= r then
				mark(ix, iz, v)
			end
		end
	end
end

local function markRect(x0: number, z0: number, x1: number, z1: number, v: number)
	for ix = math.floor(x0 / CELL), math.floor(x1 / CELL) do
		for iz = math.floor(z0 / CELL), math.floor(z1 / CELL) do
			mark(ix, iz, v)
		end
	end
end

-- (x,z) 반경 r 안에 v 이상 값의 셀이 있는가
local function occupied(x: number, z: number, r: number, v: number): boolean
	local ix0, ix1 = math.floor((x - r) / CELL), math.floor((x + r) / CELL)
	local iz0, iz1 = math.floor((z - r) / CELL), math.floor((z + r) / CELL)
	for ix = ix0, ix1 do
		for iz = iz0, iz1 do
			local g = grid[gkey(ix, iz)]
			if g and g >= v then
				local cx, cz = (ix + 0.5) * CELL - x, (iz + 0.5) * CELL - z
				if cx * cx + cz * cz <= (r + CELL * 0.71) ^ 2 then
					return true
				end
			end
		end
	end
	return false
end

------------------------------------------------------------------------------------------------------
-- 점 해시 (가로등 / 나무 간격)
------------------------------------------------------------------------------------------------------
type PointHash = { cell: number, map: { [number]: { { number } } } }

local function newHash(cell: number): PointHash
	return { cell = cell, map = {} }
end

local function hashAdd(h: PointHash, x: number, z: number, r: number)
	local k = gkey(math.floor(x / h.cell), math.floor(z / h.cell))
	local b = h.map[k]
	if not b then
		b = {}
		h.map[k] = b
	end
	table.insert(b, { x, z, r })
end

-- 가장 가까운 점과의 거리 조건: dist < k * (r + p.r) + pad 인 점이 있으면 true
local function hashHit(h: PointHash, x: number, z: number, r: number, k: number, pad: number): boolean
	local ix, iz = math.floor(x / h.cell), math.floor(z / h.cell)
	for dx = -1, 1 do
		for dz = -1, 1 do
			local b = h.map[gkey(ix + dx, iz + dz)]
			if b then
				for _, p in b do
					local ex, ez = p[1] - x, p[2] - z
					local md = k * (r + p[3]) + pad
					if ex * ex + ez * ez < md * md then
						return true
					end
				end
			end
		end
	end
	return false
end

local HASH_CELL = 40
local lamps = newHash(HASH_CELL)

------------------------------------------------------------------------------------------------------
-- 지면 높이 (레이아웃 + 잔디 둔덕)
------------------------------------------------------------------------------------------------------
local mounds: { { number } } = {} -- { x, z, r, centerY, footR }

local function groundAt(x: number, z: number): number
	local y = Kit.groundY(x, z)
	for _, m in mounds do
		local dx, dz = x - m[1], z - m[2]
		local d2 = dx * dx + dz * dz
		if d2 < m[3] * m[3] then
			y = math.max(y, m[4] + math.sqrt(m[3] * m[3] - d2))
		end
	end
	return y
end

local function inBridge(x: number, pad: number): boolean
	return math.abs(x - B.X) < BRIDGE_CORR + pad
end

local function inPicnic(x: number, z: number, pad: number): boolean
	return x > PICNIC[1] - pad and x < PICNIC[3] + pad and z > PICNIC[2] - pad and z < PICNIC[4] + pad
end

------------------------------------------------------------------------------------------------------
-- 경로 (Catmull-Rom → 직선 조각 + 꺾임 이음 원판)
------------------------------------------------------------------------------------------------------
local function catmull(pts: { Vector2 }, stepAt: (x: number) -> number): { Vector2 }
	local out: { Vector2 } = {}
	for i = 1, #pts - 1 do
		local p0 = pts[math.max(i - 1, 1)]
		local p1 = pts[i]
		local p2 = pts[i + 1]
		local p3 = pts[math.min(i + 2, #pts)]
		local n = math.max(1, math.ceil((p2 - p1).Magnitude / stepAt((p1.X + p2.X) / 2)))
		for k = 0, n - 1 do
			local t = k / n
			local t2, t3 = t * t, t * t * t
			local v = (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
			table.insert(out, v)
		end
	end
	table.insert(out, pts[#pts])
	return out
end

local function drawPath(parent: Instance, pts: { Vector2 }, width: number, top: number, color: Color3, mat: Enum.Material, name: string, skip: ((x: number) -> boolean)?)
	local th = 0.8
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local mid = (a + b) / 2
		if skip and (skip(a.X) or skip(b.X)) then
			continue
		end
		local d = b - a
		local len = d.Magnitude
		if len < 0.2 then
			continue
		end
		local cf = CFrame.lookAt(Vector3.new(mid.X, top - th / 2, mid.Y), Vector3.new(b.X, top - th / 2, b.Y))
		Kit.box(parent, cf, Vector3.new(width, th, len), color, mat, { name = name, shadow = false })
		markSeg(a.X, a.Y, b.X, b.Y, width / 2 + 1.5, 1)
		-- 꺾인 이음부 바깥쪽 틈을 아래층 원판으로 메움(윗면이 0.3 낮아 겹친 곳은 가려짐)
		if i > 1 then
			local pd = a - pts[i - 1]
			if pd.Magnitude > 0.2 then
				local c = math.clamp(pd.Unit:Dot(d.Unit), -1, 1)
				if math.acos(c) > math.rad(2.5) then
					Kit.vcyl(parent, Vector3.new(a.X, top - 0.3 - th / 2, a.Y), th, width, color, mat, opts(name .. "Joint", { shadow = false }))
				end
			end
		end
	end
end

-- 폴리라인을 따라 일정 간격(spacingAt) 위치 + 진행 방향
local function stations(pts: { Vector2 }, spacingAt: (x: number) -> number, start: number): { { Vector2 } }
	local out: { { Vector2 } } = {}
	local nextS = start
	local s = 0
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude
		if len > 0 then
			local dir = (b - a) / len
			while nextS <= s + len do
				local p = a + dir * (nextS - s)
				table.insert(out, { p, dir })
				nextS += spacingAt(p.X)
			end
		end
		s += len
	end
	return out
end

local function zOnPath(pts: { Vector2 }, x: number): number
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		if (x >= a.X and x <= b.X) or (x <= a.X and x >= b.X) then
			local t = if b.X ~= a.X then (x - a.X) / (b.X - a.X) else 0
			return a.Y + (b.Y - a.Y) * t
		end
	end
	return pts[#pts].Y
end

------------------------------------------------------------------------------------------------------
-- 공원등 / 벤치 / 휴지통 (실측)
------------------------------------------------------------------------------------------------------
local LAMP_H = R.ParkLamp -- 4.5 m
local LAMP_BALL = M(0.45)

-- 공원등: 기둥(Ø 0.12 m) + 둥근 등(Ø 0.45 m, Neon). 반환: 등 머리 파트
local function lamp(parent: Instance, x: number, z: number, base: number?): BasePart
	local hh = LAMP_H
	local gy = base or groundAt(x, z)
	Kit.vcyl(parent, Vector3.new(x, gy + (hh - 0.5) / 2, z), hh + 0.5, M(0.12), POLE_C, MAT.Metal, opts("LampPole", { shadow = false }))
	local hp = Kit.ball(parent, Vector3.new(x, gy + hh + LAMP_BALL * 0.4, z), LAMP_BALL, LAMP_HEAD, MAT.Neon, glowOpts("LampHead"))
	hashAdd(lamps, x, z, 0)
	return hp
end

local function lampLight(head: BasePart, range: number?)
	tryLight(head, "PointLight", { color = LAMP_HEAD, brightness = 1.3, range = range or M(12) })
end

-- 벤치: 좌판 높이 0.45 m, 길이 1.8 m, 깊이 0.45 m, 등받이 상단 0.85 m.  cf = 바닥 중심, 앞(-Z) = 앉는 사람이 보는 쪽
local function benchAt(parent: Instance, cf: CFrame, prefix: string)
	local len, seatY, seatD = M(1.8), M(0.45), M(0.45)
	Kit.box(parent, cf * CFrame.new(0, (seatY - 0.6) / 2, 0), Vector3.new(len * 0.7, seatY, seatD * 0.6), BENCH_BASE, MAT.Concrete, opts(prefix .. "BenchBase"))
	Kit.box(parent, cf * CFrame.new(0, seatY - 0.2, 0), Vector3.new(len, 0.4, seatD), BENCH_WOOD, MAT.WoodPlanks, opts(prefix .. "BenchSeat", { collide = true }))
	local backH = M(0.85) - seatY
	Kit.box(parent, cf * CFrame.new(0, seatY + backH / 2 - 0.1, seatD / 2 - 0.15), Vector3.new(len, backH + 0.2, 0.3), BENCH_WOOD, MAT.WoodPlanks, opts(prefix .. "BenchBack"))
end

-- 경로를 바라보는 벤치 (dirToPath: 벤치 → 경로 단위 벡터)
local function bench(parent: Instance, x: number, z: number, dirToPath: Vector2)
	local gy = groundAt(x, z)
	benchAt(parent, CFrame.lookAt(Vector3.new(x, gy, z), Vector3.new(x + dirToPath.X, gy, z + dirToPath.Y)), "")
	markSeg(x, z, x, z, M(1.2), 1)
end

-- 휴지통 Ø 0.55 m, 높이 0.9 m
local function bin(parent: Instance, x: number, z: number, gy: number)
	Kit.vcyl(parent, Vector3.new(x, gy + M(0.45) - 0.15, z), M(0.9) + 0.3, M(0.55), rgb(70, 82, 74), MAT.Metal, opts("TrashBin", { collide = true }))
end

------------------------------------------------------------------------------------------------------
-- 1) 전망대 (스폰) — 데크 + 유리 계단탑(엘리베이터 + 나선 계단) + 하부 광장
------------------------------------------------------------------------------------------------------
local function buildDeck(parent: Instance)
	local cx, cz = DC.X, DC.Z + DECK_DZ
	local hw, hd = DECK_W / 2, DECK_D / 2
	local x0, x1, z0, z1 = cx - hw, cx + hw, cz - hd, cz + hd
	local slabTop = DY - M(0.25) -- 목재 바닥 0.25 m
	local slabBot = slabTop - M(0.8) -- 강재 슬래브 0.8 m
	local sx, sz = TOWER.X, TOWER.Y
	local lh = LAND_W / 2

	-- 하부 광장 (원형 포장 Ø 38 m)
	Kit.vcyl(parent, Vector3.new(PLAZA.X, PLAZA_TOP - 0.6, PLAZA.Y), 1.2, PLAZA_R * 2, PLAZA_C, MAT.Slate, { name = "DeckPlaza", shadow = false })
	Kit.vcyl(parent, Vector3.new(PLAZA.X, PLAZA_TOP - 0.75, PLAZA.Y), 1.2, PLAZA_R * 2 + M(0.6), BENCH_BASE, MAT.Concrete, opts("PlazaCurb", { shadow = false }))

	-- 데크: 구조 슬래브 + 목재 바닥(가장자리 0.6 안쪽)
	Kit.box(parent, CFrame.new(cx, (slabTop + slabBot) / 2, cz), Vector3.new(DECK_W, slabTop - slabBot, DECK_D), STEEL, MAT.Metal, { name = "DeckSlab" })
	Kit.box(parent, CFrame.new(cx, (DY + slabTop - 0.3) / 2, cz), Vector3.new(DECK_W - 1.2, DY - slabTop + 0.3, DECK_D - 1.2), WOOD, MAT.WoodPlanks, { name = "DeckFloor" })

	-- 슬래브 옆면 LED 띠 (뒤쪽은 착지판 구간 비움)
	local fy = (slabTop + slabBot) / 2
	local fh = M(0.2)
	local gX0, gX1 = sx - lh, sx + lh
	Kit.box(parent, CFrame.new(cx, fy, z0 - 0.2), Vector3.new(DECK_W, fh, 0.4), FASCIA_GLOW, MAT.Neon, glowOpts("DeckFascia", STEEL_LIGHT))
	Kit.box(parent, CFrame.new(x0 - 0.2, fy, cz), Vector3.new(0.4, fh, DECK_D + 0.8), FASCIA_GLOW, MAT.Neon, glowOpts("DeckFascia", STEEL_LIGHT))
	Kit.box(parent, CFrame.new(x1 + 0.2, fy, cz), Vector3.new(0.4, fh, DECK_D + 0.8), FASCIA_GLOW, MAT.Neon, glowOpts("DeckFascia", STEEL_LIGHT))
	Kit.box(parent, CFrame.new((x0 + gX0) / 2, fy, z1 + 0.2), Vector3.new(gX0 - x0, fh, 0.4), FASCIA_GLOW, MAT.Neon, glowOpts("DeckFascia", STEEL_LIGHT))
	Kit.box(parent, CFrame.new((gX1 + x1) / 2, fy, z1 + 0.2), Vector3.new(x1 - gX1, fh, 0.4), FASCIA_GLOW, MAT.Neon, glowOpts("DeckFascia", STEEL_LIGHT))

	-- 하부 다운라이트 6 (+ SpotLight 2)
	for _, dx in { -(hw - M(3)), hw - M(3) } do
		for j, dz in { -M(3), 0, M(3) } do
			local dl = Kit.box(parent, CFrame.new(cx + dx, slabBot - 0.1, cz + dz), Vector3.new(M(0.7), 0.3, M(0.7)), UNDER_GLOW, MAT.Neon, glowOpts("DeckDownlight", STEEL_LIGHT))
			if j == 2 then
				tryLight(dl, "SpotLight", { face = Enum.NormalId.Bottom, angle = 70, range = 60, brightness = 2.6, color = P.LampWarm })
			end
		end
	end

	-- 받침: 가운데 콘크리트 코어(Ø 3.2 m) + 머리 확대부(Ø 5 m) + 경사 강관 버팀대 4 + 세로 LED 4
	local coreR = M(1.6)
	local capH = M(1.2)
	local coreTop = slabBot - capH + 0.3
	local coreBot = PLAZA_TOP - 0.5
	Kit.vcyl(parent, Vector3.new(cx, (coreTop + coreBot) / 2, cz), coreTop - coreBot, coreR * 2, rgb(200, 196, 188), MAT.Concrete, { name = "DeckCore" })
	Kit.vcyl(parent, Vector3.new(cx, slabBot - capH / 2 + 0.15, cz), capH + 0.3, M(5), rgb(186, 182, 174), MAT.Concrete, { name = "DeckCoreCap" })
	for q = 0, 3 do
		local a = math.rad(45 + 90 * q)
		Kit.box(parent, CFrame.new(cx + math.cos(a) * (coreR + 0.05), (PLAZA_TOP + coreTop) / 2, cz + math.sin(a) * (coreR + 0.05)) * CFrame.Angles(0, -a, 0), Vector3.new(0.3, coreTop - PLAZA_TOP, 0.4), FASCIA_GLOW, MAT.Neon, glowOpts("CoreLed", STEEL_LIGHT))
		local sxq, szq = if q == 0 or q == 3 then 1 else -1, if q <= 1 then 1 else -1
		local pa = Vector3.new(cx + sxq * coreR * 0.6, slabBot - M(10), cz + szq * coreR * 0.6)
		local pb = Vector3.new(cx + sxq * (hw - M(2)), slabBot + 0.3, cz + szq * (hd - M(1.8)))
		Kit.cylAlongY(parent, CFrame.lookAt((pa + pb) / 2, pb) * CFrame.Angles(math.rad(90), 0, 0), (pb - pa).Magnitude, M(0.45), STEEL_LIGHT, MAT.Metal, { name = "DeckStrut" })
	end

	-- 착지판: 계단 꼭대기(탑 -Z 쪽) → 데크 뒤 가장자리 (바닥 윗면 = DY)
	local landT = 1.0
	local lz0, lz1 = z1 - 0.6, sz - STAIR_RIN
	Kit.box(parent, CFrame.new(sx, DY - landT / 2, (lz0 + lz1) / 2), Vector3.new(LAND_W, landT, lz1 - lz0), WOOD, MAT.WoodPlanks, { name = "StairLanding" })
	Kit.box(parent, CFrame.new(sx, DY - landT - M(0.3), (z1 + sz - STAIR_ROUT) / 2), Vector3.new(LAND_W, M(0.6), sz - STAIR_ROUT - z1), STEEL, MAT.Metal, { name = "LandingBeam" })

	-- 유리 난간(1.15 m) + 발광 손잡이
	local gTop = DY + RAIL_H
	local function rail(cfr: CFrame, len: number)
		local y0 = slabTop - 0.3
		Kit.box(parent, cfr * CFrame.new(0, (y0 + gTop) / 2 - cfr.Position.Y, 0), Vector3.new(len, gTop - y0, 0.3), GLASS_C, MAT.Glass, { name = "GlassRail", transparency = 0.72 })
		Kit.box(parent, cfr * CFrame.new(0, gTop + 0.15 - cfr.Position.Y, 0), Vector3.new(len + 0.3, 0.3, 0.4), RAIL_GLOW, MAT.Neon, glowOpts("Handrail", STEEL_LIGHT))
	end
	local turn = CFrame.Angles(0, math.rad(90), 0)
	rail(CFrame.new(cx, DY, z0 + 0.4), DECK_W - 0.8)
	rail(CFrame.new(x0 + 0.4, DY, cz) * turn, DECK_D - 0.8)
	rail(CFrame.new(x1 - 0.4, DY, cz) * turn, DECK_D - 0.8)
	rail(CFrame.new((x0 + 0.4 + gX0) / 2, DY, z1 - 0.4), gX0 - x0 - 0.4)
	rail(CFrame.new((gX1 + x1 - 0.4) / 2, DY, z1 - 0.4), x1 - 0.4 - gX1)
	-- 착지판 양옆: -X 쪽은 탑 밖 구간만(계단에서 들어오는 입구), +X 쪽은 계단 우물 위까지
	rail(CFrame.new(gX0 + 0.2, DY, (z1 + sz - STAIR_ROUT - 0.6) / 2) * turn, sz - STAIR_ROUT - 0.6 - z1)
	rail(CFrame.new(gX1 - 0.2, DY, (z1 + sz - STAIR_RIN) / 2) * turn, sz - STAIR_RIN - z1)

	-- 엘리베이터: 유리 원통 샤프트 + 세로 LED 4 + 발광 캐빈 + 상부 기계실 캡 + 하부 링
	local shaftTop = DY + M(3.0)
	local shaftH = shaftTop - PLAZA_TOP
	Kit.vcyl(parent, Vector3.new(sx, PLAZA_TOP + shaftH / 2, sz), shaftH, SHAFT_R * 2, GLASS_C, MAT.Glass, { name = "ElevatorShaft", transparency = 0.5, shadow = false })
	for k = 0, 3 do
		local a = math.rad(45 + 90 * k)
		Kit.box(parent, CFrame.new(sx + math.cos(a) * (SHAFT_R + 0.15), PLAZA_TOP + shaftH / 2, sz + math.sin(a) * (SHAFT_R + 0.15)) * CFrame.Angles(0, -a, 0), Vector3.new(0.3, shaftH, 0.3), FASCIA_GLOW, MAT.Neon, glowOpts("ShaftLed", STEEL_LIGHT))
	end
	local cab = Kit.box(parent, CFrame.new(sx, PLAZA_TOP + shaftH * 0.42, sz), Vector3.new(M(1.5), M(2.3), M(1.5)), CAB_GLOW, MAT.Neon, glowOpts("ElevatorCab", rgb(200, 200, 196)))
	tryLight(cab, "PointLight", { color = CAB_GLOW, brightness = 1.4, range = M(10) })
	Kit.vcyl(parent, Vector3.new(sx, shaftTop + M(0.2), sz), M(0.4), SHAFT_R * 2 + M(0.4), STEEL_LIGHT, MAT.Metal, { name = "ShaftCap" })
	local ring = Kit.vcyl(parent, Vector3.new(sx, PLAZA_TOP, sz), 0.6, (STAIR_ROUT + 0.6) * 2, STEEL, MAT.Metal, { name = "TowerBase" })
	tryLight(ring, "PointLight", { color = P.LampWarm, brightness = 1.2, range = M(12) })

	-- 나선 계단: 챌판 0.17 m, 보행선(중심 반경) 디딤판 0.30 m → 한 바퀴 48 단.
	-- 마지막 단 다음이 착지판(θ = -90°, 데크 쪽). 진행 방향 = θ 증가.
	local rise = DY - PLAZA_TOP
	local n = math.ceil(rise / RISER)
	local riser = rise / n
	local rc = (STAIR_RIN + STAIR_ROUT) / 2
	local perTurn = math.floor(2 * math.pi * rc / TREAD + 0.5)
	local dTheta = 2 * math.pi / perTurn
	local thLand = -math.pi / 2
	local thLast = thLand - math.asin(lh / rc) - dTheta * 0.5
	local stepW = STAIR_ROUT - STAIR_RIN
	local depth = 2 * STAIR_ROUT * math.tan(dTheta / 2) + 0.1
	local stepT = 0.9
	local stairs = Kit.group(parent, "SpiralStair")
	for k = 1, n - 1 do
		local th = thLast - (n - 1 - k) * dTheta
		local top = PLAZA_TOP + k * riser
		local rm = (STAIR_RIN + STAIR_ROUT) / 2
		local c = Vector3.new(sx + rm * math.cos(th), top - stepT / 2, sz + rm * math.sin(th))
		local tangent = Vector3.new(-math.sin(th), 0, math.cos(th))
		Kit.box(stairs, CFrame.lookAt(c, c + tangent), Vector3.new(stepW, stepT, depth), STAIR_C, MAT.Concrete, { name = "Step", shadow = false })
	end
	-- 계단 바깥 가장자리 LED 나선 (6 단마다 한 조각)
	local ledR = STAIR_ROUT - 0.3
	local k = 1
	while k < n - 1 do
		local k2 = math.min(k + 6, n - 1)
		local ta, tb = thLast - (n - 1 - k) * dTheta, thLast - (n - 1 - k2) * dTheta
		local pa = Vector3.new(sx + ledR * math.cos(ta), PLAZA_TOP + k * riser - stepT - 0.15, sz + ledR * math.sin(ta))
		local pb = Vector3.new(sx + ledR * math.cos(tb), PLAZA_TOP + k2 * riser - stepT - 0.15, sz + ledR * math.sin(tb))
		Kit.box(stairs, CFrame.lookAt((pa + pb) / 2, pb), Vector3.new(0.3, 0.3, (pb - pa).Magnitude + 0.2), HELIX_GLOW, MAT.Neon, glowOpts("StairLed", STEEL_LIGHT))
		k = k2
	end

	-- 원통 유리 외피(24 면, 아래 2.3 m 는 출입 개방) + LED 멀리언 12. 착지판 앞 2 면은 착지판 아래에서 끝남.
	local NP = 24
	local pr = STAIR_ROUT + 0.4
	local pw = 2 * pr * math.tan(math.pi / NP) + 0.1
	local yB = PLAZA_TOP + M(2.3)
	local yT = DY + RAIL_H
	local skin = Kit.group(parent, "TowerSkin")
	for p = 0, NP - 1 do
		local a = thLand + (p + 0.5) * 2 * math.pi / NP
		local top = if p == 0 or p == NP - 1 then DY - landT - M(0.6) else yT
		local c = Vector3.new(sx + pr * math.cos(a), (yB + top) / 2, sz + pr * math.sin(a))
		Kit.box(skin, CFrame.lookAt(c, Vector3.new(sx, c.Y, sz)), Vector3.new(pw, top - yB, 0.3), GLASS_C, MAT.Glass, { name = "TowerGlass", transparency = 0.66 })
		if p % 2 == 1 then
			local am = thLand + (p + 1) * 2 * math.pi / NP
			local mr = pr + 0.25
			Kit.box(skin, CFrame.new(sx + mr * math.cos(am), (PLAZA_TOP + yT) / 2, sz + mr * math.sin(am)) * CFrame.Angles(0, -am, 0), Vector3.new(0.35, yT - PLAZA_TOP, 0.35), FASCIA_GLOW, MAT.Neon, glowOpts("TowerLed", STEEL_LIGHT))
		end
	end

	-- 데크 소품: 유료 망원경 3 (높이 1.3 m), 벤치 2
	for _, dx in { -M(6.2), M(1.2), M(5.4) } do
		local tx, tz = cx + dx, z0 + M(0.9)
		Kit.vcyl(parent, Vector3.new(tx, DY + M(0.525) - 0.15, tz), M(1.05) + 0.3, M(0.16), STEEL_LIGHT, MAT.Metal, opts("ScopePost", { collide = true }))
		Kit.box(parent, CFrame.new(tx, DY + M(1.15), tz) * CFrame.Angles(math.rad(10), 0, 0), Vector3.new(M(0.32), M(0.28), M(0.5)), rgb(40, 96, 110), MAT.Metal, opts("Binocular"))
	end
	for _, dx in { -M(4.5), M(4.5) } do
		benchAt(parent, CFrame.new(cx + dx, DY, cz + M(3.4)), "Deck")
	end

	-- 포토 스팟: 바닥 표지판 + 삼각대(1.5 m) + 카메라(PhotoSpot, ProximityPrompt)
	local px, pz = cx - M(2.6), z0 + M(1.6)
	local plate = Kit.box(parent, CFrame.new(px, DY + 0.1, pz + M(0.9)), Vector3.new(M(1.5), 0.4, M(0.7)), rgb(34, 36, 42), MAT.SmoothPlastic, opts("PhotoSpotSign"))
	Kit.label(plate, Enum.NormalId.Top, "포토 스팟", { glow = true, color = rgb(255, 214, 150), pixelsPerStud = 40 })
	tryLight(plate, "PointLight", { color = P.LampWarm, brightness = 0.9, range = M(4) })
	Kit.vcyl(parent, Vector3.new(px, DY + M(0.72), pz), M(1.44), M(0.05), STEEL, MAT.Metal, opts("Tripod"))
	local spot = Kit.box(parent, CFrame.new(px, DY + M(1.52), pz), Vector3.new(M(0.36), M(0.26), M(0.22)), rgb(24, 24, 28), MAT.SmoothPlastic, { name = "PhotoSpot", collide = false, query = true })
	Kit.hcyl(parent, CFrame.new(px, DY + M(1.52), pz - M(0.16)) * CFrame.Angles(0, math.rad(90), 0), M(0.12), M(0.18), rgb(60, 62, 70), MAT.Glass, opts("Lens"))
	spot:SetAttribute("HeroCamPos", V.HeroCamPos)
	spot:SetAttribute("HeroCamLook", V.HeroCamLook)
	spot:SetAttribute("HeroFov", V.HeroFov)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "PhotoPrompt"
	pp.ActionText = "사진 구도"
	pp.ObjectText = "포토 스팟"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = M(3.6)
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Parent = spot

	-- 스폰 (반투명 패드 2 x 2 m, 정면 = -Z). 바닥과 면이 겹치지 않게 0.3 띄움
	local sp = Instance.new("SpawnLocation")
	sp.Name = "DeckSpawn"
	sp.Anchored = true
	sp.Size = Vector3.new(M(2), 0.4, M(2))
	sp.CFrame = CFrame.new(cx + M(2), DY + 0.15, DC.Z + M(0.8))
	sp.Material = MAT.SmoothPlastic
	sp.Color = rgb(232, 204, 160)
	sp.Transparency = 0.8
	sp.TopSurface = Enum.SurfaceType.Smooth
	sp.BottomSurface = Enum.SurfaceType.Smooth
	sp.CastShadow = false
	sp.CanCollide = true
	sp.Neutral = true
	sp.Duration = 0
	sp.AllowTeamChangeOnTouch = false
	sp.Enabled = true
	sp.Parent = parent
	Kit.stats.parts += 1

	-- 광장 공원등 4 (광원) + 벤치 2
	for q = 0, 3 do
		local a = math.rad(200 + q * 45)
		local lx, lz = PLAZA.X + math.cos(a) * (PLAZA_R - M(1.5)), PLAZA.Y + math.sin(a) * (PLAZA_R - M(1.5))
		local hp = lamp(parent, lx, lz, PLAZA_TOP)
		lampLight(hp)
	end
	for _, a in { 160, 20 } do
		local r = PLAZA_R - M(2.5)
		local bx, bz = PLAZA.X + math.cos(math.rad(a)) * r, PLAZA.Y + math.sin(math.rad(a)) * r
		benchAt(parent, CFrame.lookAt(Vector3.new(bx, PLAZA_TOP, bz), Vector3.new(PLAZA.X, PLAZA_TOP, PLAZA.Y)), "Plaza")
	end

	-- 예약 / 격자 (광장 원판 + 데크 전체)
	Kit.reserve(PLAZA.X - PLAZA_R, PLAZA.Y - PLAZA_R, PLAZA.X + PLAZA_R, PLAZA.Y + PLAZA_R, "ParkDeck")
	Kit.reserve(x0, z0, x1, z1, "ParkDeckSlab")
	for ix = math.floor((PLAZA.X - PLAZA_R) / CELL) - 1, math.floor((PLAZA.X + PLAZA_R) / CELL) + 1 do
		for iz = math.floor((PLAZA.Y - PLAZA_R) / CELL) - 1, math.floor((PLAZA.Y + PLAZA_R) / CELL) + 1 do
			local ex, ez = (ix + 0.5) * CELL - PLAZA.X, (iz + 0.5) * CELL - PLAZA.Y
			if ex * ex + ez * ez <= (PLAZA_R + M(1)) ^ 2 then
				mark(ix, iz, 2)
			end
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 2) 편의점 매점(높이 3 m) + 테라스 + 피크닉장 + "한강공원" 표지석
------------------------------------------------------------------------------------------------------
-- 파라솔: 높이 2.3 m, 지름 2.4 m
local function parasol(parent: Instance, x: number, y: number, z: number, color: Color3)
	Kit.vcyl(parent, Vector3.new(x, y + M(1.15), z), M(2.3), M(0.05), rgb(220, 220, 214), MAT.Metal, opts("ParasolPole"))
	Kit.ellipsoid(parent, CFrame.new(x, y + M(2.15), z), Vector3.new(M(2.4), M(0.45), M(2.4)), color, MAT.Fabric, opts("Parasol"))
end

-- 표지석: 폭 4 m, 높이 1.1 m
local function signStone(parent: Instance, x: number, z: number, text: string)
	local gy = groundAt(x, z)
	Kit.box(parent, CFrame.new(x, gy + M(0.15) - 0.2, z), Vector3.new(M(4.4), M(0.3) + 0.4, M(1.0)), BENCH_BASE, MAT.Concrete, { name = "SignBase" })
	local board = Kit.box(parent, CFrame.new(x, gy + M(0.3) + M(0.55), z), Vector3.new(M(4), M(1.1), M(0.4)), rgb(48, 50, 56), MAT.Granite, { name = "SignStone" })
	Kit.label(board, Enum.NormalId.Back, text, { glow = true, color = rgb(250, 232, 200), pixelsPerStud = 24 })
	Kit.box(parent, CFrame.new(x, gy + M(0.3) + 0.15, z + M(0.4)), Vector3.new(M(3.6), 0.3, 0.6), LAMP_HEAD, MAT.Neon, glowOpts("SignUplight"))
	markSeg(x - M(2.2), z, x + M(2.2), z, M(1.2), 1)
end

-- 피크닉 테이블 세트: 상판 0.75 m (1.8 x 0.8 m), 의자 0.45 m
local function picnicSet(parent: Instance, cf: CFrame)
	local len = M(1.8)
	Kit.box(parent, cf * CFrame.new(0, M(0.75) - 0.15, 0), Vector3.new(len, 0.3, M(0.8)), BENCH_WOOD, MAT.WoodPlanks, opts("PicnicTable", { collide = true }))
	Kit.box(parent, cf * CFrame.new(0, (M(0.75) - 0.2) / 2, 0), Vector3.new(len * 0.7, M(0.75) - 0.2, 0.6), BENCH_BASE, MAT.Concrete, opts("PicnicLeg"))
	for _, s in { 1, -1 } do
		Kit.box(parent, cf * CFrame.new(0, M(0.45) - 0.15, s * M(0.75)), Vector3.new(len, 0.3, M(0.32)), BENCH_WOOD, MAT.WoodPlanks, opts("PicnicSeat", { collide = true }))
	end
end

local function buildKiosk(parent: Instance, rng: Random, mainPts: { Vector2 })
	local kx = KIOSK_X
	local pz = zOnPath(mainPts, kx)
	local W, D, H = M(8), M(5), M(2.75) -- 8 x 5 m, 벽체 2.75 m + 지붕 0.25 m = 3 m
	local kz1 = pz - MAIN_W / 2 - M(4.5) -- 매장 앞면(+Z, 테라스 4.5 m 너머 메인 산책로)
	local kz = kz1 - D / 2
	local base = PLAZA_TOP
	-- 테라스 (매장 뒤 0.5 m ~ 메인 산책로 가장자리 0.6 안쪽까지)
	local tz0, tz1 = kz - D / 2 - M(0.5), pz - MAIN_W / 2 + 0.6
	local tx0, tx1 = kx - W / 2 - M(3), kx + W / 2 + M(6)
	Kit.box(parent, CFrame.new((tx0 + tx1) / 2, base - 0.6, (tz0 + tz1) / 2), Vector3.new(tx1 - tx0, 1.2, tz1 - tz0), PAVE_C, MAT.Pavement, { name = "KioskTerrace", shadow = false })
	-- 건물
	Kit.box(parent, CFrame.new(kx, base + H / 2 - 0.15, kz), Vector3.new(W, H + 0.3, D), rgb(214, 208, 198), MAT.Concrete, { name = "Kiosk" })
	Kit.box(parent, CFrame.new(kx, base + H + M(0.125), kz + M(0.4)), Vector3.new(W + M(0.6), M(0.25), D + M(1.4)), rgb(54, 58, 66), MAT.Metal, { name = "KioskRoof" })
	local front = Kit.box(parent, CFrame.new(kx - M(0.65), base + M(1.45), kz1 + 0.2), Vector3.new(W - M(2.3), M(1.7), 0.4), rgb(214, 190, 150), MAT.Neon, glowOpts("KioskWindow", rgb(60, 78, 96)))
	tryLight(front, "PointLight", { color = rgb(255, 222, 176), brightness = 1.3, range = M(9) })
	Kit.box(parent, CFrame.new(kx + W / 2 - M(0.9), base + M(1.1), kz1 + 0.25), Vector3.new(M(1.0), M(2.2), 0.5), rgb(66, 70, 78), MAT.Metal, opts("KioskDoor"))
	local sign = Kit.box(parent, CFrame.new(kx, base + H - M(0.2), kz1 + 0.3), Vector3.new(W - 0.6, M(0.4), 0.6), rgb(30, 104, 168), MAT.SmoothPlastic, opts("KioskSign"))
	Kit.label(sign, Enum.NormalId.Back, "편의점", { glow = true, color = rgb(255, 255, 255), pixelsPerStud = 24 })
	-- 강 쪽 벽에도 간판
	local sign2 = Kit.box(parent, CFrame.new(kx, base + H - M(0.2), kz - D / 2 - 0.3), Vector3.new(W - M(1.6), M(0.4), 0.6), rgb(30, 104, 168), MAT.SmoothPlastic, opts("KioskSign"))
	Kit.label(sign2, Enum.NormalId.Front, "편의점", { glow = true, color = rgb(255, 255, 255), pixelsPerStud = 24 })
	-- 자판기 2 (1.83 x 1.0 x 0.8 m)
	for i, c in { rgb(170, 34, 40), rgb(36, 90, 160) } do
		local vx = kx - W / 2 - M(0.7) - (i - 1) * M(1.1)
		Kit.box(parent, CFrame.new(vx, base + M(0.915), kz1 - M(0.4)), Vector3.new(M(1.0), M(1.83), M(0.8)), c, MAT.SmoothPlastic, { name = "Vending" })
		Kit.box(parent, CFrame.new(vx, base + M(1.15), kz1 + 0.05), Vector3.new(M(0.75), M(1.0), 0.3), rgb(220, 226, 236), MAT.Neon, glowOpts("VendingGlow", rgb(180, 190, 200)))
	end
	-- 테라스 파라솔 테이블 3 (상판 Ø 0.8 m, 0.72 m)
	local cols = { rgb(196, 54, 46), rgb(236, 230, 214), rgb(44, 112, 168) }
	for i = 1, 3 do
		local tx, tz = kx - M(2.6) + (i - 1) * M(3.2), (kz1 + pz - MAIN_W / 2) / 2
		Kit.vcyl(parent, Vector3.new(tx, base + M(0.72) - 0.15, tz), 0.3, M(0.8), rgb(230, 230, 226), MAT.SmoothPlastic, opts("CafeTable", { collide = true }))
		parasol(parent, tx, base, tz, cols[i])
	end
	bin(parent, kx + W / 2 + M(1.2), kz1 + M(0.8), base)
	bin(parent, kx + W / 2 + M(2.0), kz1 + M(0.8), base)
	Kit.reserve(tx0, tz0, tx1, tz1, "ParkKiosk")
	markRect(tx0 - M(1), tz0 - M(1), tx1 + M(1), tz1, 2)

	-- 피크닉장 (매점 강 쪽 잔디밭): 테이블 세트 + 파라솔 + 돗자리
	local sets = { { -550, 852 }, { -533, 880 }, { -467, 883 }, { -447, 852 } }
	for i, s in sets do
		local x, z = s[1], s[2]
		local gy = groundAt(x, z)
		local cf = CFrame.new(x, gy, z) * CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0)
		picnicSet(parent, cf)
		if z > PICNIC[2] + 40 then
			parasol(parent, x, gy, z, cols[i % 3 + 1])
		end
	end
	local mats = { { -543, 840, rgb(214, 120, 60) }, { -563, 877, rgb(70, 140, 190) }, { -497, 887, rgb(220, 196, 90) } }
	for _, m in mats do
		Kit.box(parent, CFrame.new(m[1] :: number, GROUND + 0.3, m[2] :: number) * CFrame.Angles(0, math.rad(rng:NextNumber(-30, 30)), 0), Vector3.new(M(1.8), 0.3, M(2.4)), m[3] :: Color3, MAT.Fabric, opts("PicnicMat"))
	end
	local pl = lamp(parent, -430, 887)
	lampLight(pl)
	for _, s in sets do
		markSeg(s[1], s[2], s[1], s[2], M(2), 1)
	end
	signStone(parent, tx1 + M(6), pz - MAIN_W / 2 - M(2.5), "한강공원")
end

------------------------------------------------------------------------------------------------------
-- 3) 주차장 (제방 아래): 2.5 x 5 m 주차칸 2 열 + 통로 6 m, 승용차 4.6 x 1.85 x 1.5 m
------------------------------------------------------------------------------------------------------
local function buildParking(parent: Instance, rng: Random)
	local x0, z0, x1, z1 = LOT_X0, LOT_Z0, LOT_X1, LOT_Z1
	local top = PLAZA_TOP
	Kit.box(parent, CFrame.new((x0 + x1) / 2, top - 0.6, (z0 + z1) / 2), Vector3.new(x1 - x0, 1.2, z1 - z0), P.Asphalt, MAT.Asphalt, { name = "ParkingLot", shadow = false })
	Kit.box(parent, CFrame.new((x0 + x1) / 2, top - 0.45, z0 - 0.6), Vector3.new(x1 - x0 + 2.4, 1.5, 1.2), BENCH_BASE, MAT.Concrete, { name = "LotCurb", shadow = false })
	local stallW, depth = M(2.5), M(5)
	local rows = { { z0 + M(1), z0 + M(1) + depth, 1 }, { z1 - M(1) - depth, z1 - M(1), -1 } }
	local paint = rgb(200, 200, 192)
	local xs: { number } = {}
	local x = x0 + M(1.5)
	while x <= x1 - M(1.5) do
		table.insert(xs, x)
		x += stallW
	end
	for _, row in rows do
		for _, lx in xs do
			Kit.box(parent, CFrame.new(lx, top + 0.15, (row[1] + row[2]) / 2), Vector3.new(M(0.12), 0.3, depth), paint, MAT.SmoothPlastic, opts("StallLine", { shadow = false }))
		end
		-- 주차된 차 (빈칸 섞임): 차체 + 캐빈(유리)
		for i = 1, #xs - 1 do
			if rng:NextNumber() < 0.55 then
				local cx = (xs[i] + xs[i + 1]) / 2
				local cz = (row[1] + row[2]) / 2 + row[3] * M(0.15)
				local col = CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)]
				local cf = CFrame.new(cx, top, cz) * CFrame.Angles(0, math.rad(rng:NextNumber(-2, 2)), 0)
				local bodyH = M(0.8)
				Kit.box(parent, cf * CFrame.new(0, M(0.15) + bodyH / 2, 0), Vector3.new(M(1.85), bodyH, M(4.6)), col, MAT.SmoothPlastic, { name = "CarBody" })
				Kit.box(parent, cf * CFrame.new(0, M(0.95) + M(0.275) - 0.15, row[3] * M(0.25)), Vector3.new(M(1.6), M(0.55) + 0.3, M(2.4)), rgb(36, 42, 52), MAT.Glass, opts("CarCabin"))
			end
		end
	end
	-- 주차장 조명 2 (8 m 기둥, 연석 위)
	for i, lx in { x0 + M(12), x1 - M(12) } do
		local lz = z0 - 0.6
		Kit.vcyl(parent, Vector3.new(lx, top + M(4), lz), M(8), M(0.2), POLE_C, MAT.Metal, opts("LotPole"))
		local hd = Kit.box(parent, CFrame.new(lx, top + M(8) + 0.3, lz + M(0.6)), Vector3.new(M(0.8), 0.5, M(1.6)), rgb(236, 226, 206), MAT.Neon, glowOpts("LotLight"))
		hashAdd(lamps, lx, lz, 0)
		if i == 1 then
			tryLight(hd, "SpotLight", { face = Enum.NormalId.Bottom, angle = 110, range = 50, brightness = 1.6, color = rgb(255, 232, 196) })
		end
	end
	Kit.reserve(x0, z0 - 1.2, x1, z1, "ParkParking")
	markRect(x0 - M(1), z0 - M(1.5), x1 + M(1), z1 + M(1), 2)
	signStone(parent, x1 + M(8), z0 - M(3), "한강공원 주차장")
end

------------------------------------------------------------------------------------------------------
-- 4) 둔덕 (지형 Ball, 잔디): 반지름 15 ~ 23 m, 높이 1.8 ~ 3.3 m
------------------------------------------------------------------------------------------------------
local function buildMounds(rng: Random)
	local made = 0
	for _ = 1, 80 do
		if made >= 12 then
			break
		end
		local x = rng:NextNumber(-M(650), M(650))
		local z = rng:NextNumber(BELT_Z1 - M(5), N.ParkTo - M(12))
		local r = rng:NextNumber(M(15), M(23))
		local h = rng:NextNumber(M(1.8), M(3.3))
		local fr = math.sqrt(2 * r * h - h * h)
		if inBridge(x, fr + M(3)) or inPicnic(x, z, fr + M(1.2)) then
			continue
		end
		if occupied(x, z, fr + M(1), 1) then
			continue
		end
		if not Kit.isFree(x - fr, z - fr, x + fr, z + fr) then
			continue
		end
		local clash = false
		for _, m in mounds do
			if (Vector2.new(m[1], m[2]) - Vector2.new(x, z)).Magnitude < fr + m[5] + M(2) then
				clash = true
				break
			end
		end
		if clash then
			continue
		end
		local cy = GROUND - r + h
		table.insert(mounds, { x, z, r, cy, fr })
		Kit.terrain("Ball", CFrame.new(x, cy, z), Vector3.new(r * 2, r * 2, r * 2), MAT.Grass)
		made += 1
	end
end

------------------------------------------------------------------------------------------------------
-- 5) 나무 (둥근 활엽수: 줄기 + 수관 타원체). 높이 8 ~ 14 m, 줄기 Ø 0.3 ~ 0.6 m, 수관 Ø 5 ~ 9 m
------------------------------------------------------------------------------------------------------
local function tree(parent: Instance, rng: Random, x: number, z: number, gy: number, D: number, lod: number): number
	local th = rng:NextNumber(M(3.0), M(4.6)) * math.clamp(D / M(7), 0.9, 1.15) -- 수관 아래 줄기 높이
	local hc = D * rng:NextNumber(0.8, 0.94) -- 수관 높이
	local trunkD = math.clamp(D * 0.06, M(0.3), M(0.6))
	local n = 0
	local trunkH = th + hc * 0.35 + 1
	Kit.vcyl(parent, Vector3.new(x, gy - 1 + trunkH / 2, z), trunkH, trunkD, BARK, MAT.Wood, { name = "Trunk", shadow = false, collide = true })
	n += 1
	local c = LEAVES[rng:NextInteger(1, #LEAVES)]
	local mat = if rng:NextNumber() < 0.6 then MAT.Grass else MAT.LeafyGrass
	local cy = gy + th + hc * 0.5
	local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	Kit.ellipsoid(parent, CFrame.new(x, cy, z) * yaw, Vector3.new(D, hc, D * rng:NextNumber(0.84, 1.0)), c, mat, opts("Canopy"))
	n += 1
	if lod >= 2 then
		local a = rng:NextNumber(0, math.pi * 2)
		local d2 = D * rng:NextNumber(0.56, 0.72)
		local off = D * rng:NextNumber(0.2, 0.3)
		Kit.ellipsoid(parent, CFrame.new(x + math.cos(a) * off, cy + hc * rng:NextNumber(0.08, 0.24), z + math.sin(a) * off), Vector3.new(d2, d2 * 0.84, d2), c:Lerp(LEAF_LIGHT, rng:NextNumber(0.08, 0.3)), mat, opts("Canopy"))
		n += 1
		if lod >= 3 then
			local a2 = a + math.pi + rng:NextNumber(-0.6, 0.6)
			local d3 = D * rng:NextNumber(0.52, 0.66)
			local off2 = D * rng:NextNumber(0.22, 0.3)
			Kit.ellipsoid(parent, CFrame.new(x + math.cos(a2) * off2, cy - hc * rng:NextNumber(0.0, 0.12), z + math.sin(a2) * off2), Vector3.new(d3, d3 * 0.82, d3), c:Lerp(LEAF_DARK, rng:NextNumber(0.1, 0.3)), mat, opts("Canopy"))
			n += 1
		end
	end
	return n
end

local function densX(x: number): number
	local d = math.abs(x - VIEW_X)
	if d < M(350) then
		return 1
	end
	return math.clamp(1 - (d - M(350)) / M(550), 0.42, 1)
end

local function buildTrees(parent: Instance, rng: Random, budget: number): number
	-- 숲(그로브) 중심: 그 밖은 듬성듬성(잔디 공터)
	local groves: { { number } } = {}
	for _ = 1, 70 do
		local x = math.clamp(VIEW_X + rng:NextNumber(-1, 1) * rng:NextNumber(0.25, 1) * M(850), X0, X1)
		table.insert(groves, { x, rng:NextNumber(Z0 + M(10), Z1 - M(10)), rng:NextNumber(M(20), M(45)) })
	end
	local function groveField(x: number, z: number): number
		local g = 0
		for _, gr in groves do
			local ex, ez = (x - gr[1]) / gr[3], (z - gr[2]) / gr[3]
			if math.abs(ex) < 1 and math.abs(ez) < 1 then
				local d2 = ex * ex + ez * ez
				if d2 < 1 then
					g = math.max(g, 1 - d2)
				end
			end
		end
		return g
	end

	local trees = newHash(HASH_CELL)
	local used, count = 0, 0
	-- pass 1: 히어로 하단 띠(큰 수관, 촘촘) → pass 2: 근경 나머지(그로브) → pass 3: 원경
	local NEAR0, NEAR1 = VIEW_X - M(530), VIEW_X + M(545)
	local passes = {
		{ x0 = BELT_X0, x1 = BELT_X1, z1 = BELT_Z1, tries = 7000, cap = budget * 0.52 },
		{ x0 = NEAR0, x1 = NEAR1, z1 = Z1 - M(3), tries = 9000, cap = budget * 0.83 },
		{ x0 = X0 + M(4), x1 = X1 - M(4), z1 = Z1 - M(3), tries = 10000, cap = budget },
	}
	for pi, pass in passes do
		for _ = 1, pass.tries do
			if used >= pass.cap - 4 then
				break
			end
			local x = rng:NextNumber(pass.x0, pass.x1)
			local z = rng:NextNumber(TREE_Z0, pass.z1)
			local belt = x > BELT_X0 and x < BELT_X1 and z < BELT_Z1
			if (pi == 2 and belt) or (pi == 3 and x > NEAR0 and x < NEAR1) then
				continue
			end
			local p = if belt then 1 else densX(x) * (0.32 + 0.68 * groveField(x, z))
			if rng:NextNumber() > p then
				continue
			end
			local D = if belt then rng:NextNumber(M(6.8), M(9)) else rng:NextNumber(M(5), M(8))
			local r = D / 2
			if z + r * 0.9 > Z1 - 1 then
				continue
			end
			if inBridge(x, r) or inPicnic(x, z, r * 0.5) then
				continue
			end
			if occupied(x, z, M(0.8), 1) or occupied(x, z, r * 0.7, 2) or (belt and occupied(x, z, r * 0.8, 3)) then
				continue
			end
			if hashHit(lamps, x, z, r * 0.85, 1, M(0.6)) then
				continue
			end
			if hashHit(trees, x, z, r, if belt then 0.6 else 0.64, 0) then
				continue
			end
			if not Kit.isFree(x - r * 0.7, z - r * 0.7, x + r * 0.7, z + r * 0.7) then
				continue
			end
			local gy = groundAt(x, z)
			local near = math.abs(x - VIEW_X) < M(475)
			local lod = if belt or (near and D >= M(6.5)) then 3 else 2
			used += tree(parent, rng, x, z, gy, D, lod)
			count += 1
			hashAdd(trees, x, z, r)
		end
	end
	return count
end

------------------------------------------------------------------------------------------------------
-- 빌드
------------------------------------------------------------------------------------------------------
function Park.build(ctx: any)
	local model: Model = ctx.model
	local rng: Random = ctx.rng
	local p0 = Kit.stats.parts
	lightsUsed = 0
	grid = {}
	mounds = {}
	lamps = newHash(HASH_CELL)

	-- 메인 산책로 선형 (구조물 배치 기준; 옛 레이아웃 × 5/3, 다리 아래는 비움)
	local ctrl = {
		Vector2.new(X0, 1075),
		Vector2.new(-2300, 1025),
		Vector2.new(-1917, 1083),
		Vector2.new(-1550, 1008),
		Vector2.new(-1200, 1053),
		Vector2.new(-933, 1017),
		Vector2.new(-667, 1020),
		Vector2.new(-417, 1030),
		Vector2.new(-217, 1080),
		Vector2.new(DC.X, PLAZA.Y - PLAZA_R - M(5)),
		Vector2.new(100, 1083),
		Vector2.new(283, 1043),
		Vector2.new(B.X, 1040),
		Vector2.new(567, 1037),
		Vector2.new(750, 1000),
		Vector2.new(1000, 1047),
		Vector2.new(1300, 1010),
		Vector2.new(1633, 1075),
		Vector2.new(2000, 1020),
		Vector2.new(2367, 1067),
		Vector2.new(X1, 1033),
	}
	local function stepAt(x: number): number
		return if math.abs(x - VIEW_X) < M(475) then M(11) else M(45)
	end
	local mainPts = catmull(ctrl, stepAt)
	local function skipBridge(x: number): boolean
		return inBridge(x, M(1))
	end

	-- 1) 전망대
	buildDeck(Kit.group(model, "Deck"))

	-- 2) 산책로: 강변 쪽 숲 앞 산책로(직선) → 메인(곡선) → 연결로 → 광장 진입로
	local paths = Kit.group(model, "Paths")
	local edgeSpans = { { -M(500), B.X - BRIDGE_CORR - M(1) }, { B.X + BRIDGE_CORR + M(1), M(550) } }
	for _, s in edgeSpans do
		local a, b = s[1], s[2]
		Kit.box(paths, CFrame.new((a + b) / 2, MAIN_TOP - 0.4, EDGE_Z), Vector3.new(b - a, 0.8, EDGE_W), EDGE_C, MAT.Pavement, { name = "EdgeWalk", shadow = false })
		markSeg(a, EDGE_Z, b, EDGE_Z, EDGE_W / 2 + 1.5, 1)
	end
	drawPath(paths, mainPts, MAIN_W, MAIN_TOP, BRICK_C, MAT.Brick, "MainPath", skipBridge)

	local connectors: { { Vector2 } } = {}
	-- 히어로 하단에 보이는 연결로(-167, 200)는 숲 띠 안에서 수관이 덮지 않는 "빛길"(공원등 줄)
	local connX = { -2067, -1267, -167, 200, 933, 1967 }
	for _, cx in connX do
		local xe = cx + rng:NextNumber(-M(15), M(15))
		local ze = zOnPath(mainPts, xe)
		local c = {
			Vector2.new(cx, EDGE_Z),
			Vector2.new(cx + rng:NextNumber(-M(7), M(7)), EDGE_Z + (ze - EDGE_Z) * 0.35),
			Vector2.new((cx + xe) / 2 + rng:NextNumber(-M(8), M(8)), EDGE_Z + (ze - EDGE_Z) * 0.7),
			Vector2.new(xe, ze),
		}
		local pts = catmull(c, function(_x: number): number
			return M(9)
		end)
		drawPath(paths, pts, CONN_W, CONN_TOP, PAVE_C, MAT.Pavement, "ConnPath")
		table.insert(connectors, pts)
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			if (a.Y + b.Y) / 2 < BELT_Z1 + M(5) and a.X > BELT_X0 and a.X < BELT_X1 then
				markSeg(a.X, a.Y, b.X, b.Y, CONN_W / 2 + 1.5, 3)
			end
		end
	end
	-- 광장 진입로 (메인 → 광장 안쪽)
	local spurX = DC.X + M(11)
	local spur = catmull({ Vector2.new(spurX, zOnPath(mainPts, spurX)), Vector2.new(DC.X + M(6), PLAZA.Y - PLAZA_R + M(4)) }, function(_x: number): number
		return M(15)
	end)
	drawPath(paths, spur, M(3), CONN_TOP, PAVE_C, MAT.Pavement, "PlazaSpur")

	-- 3) 매점·피크닉 / 주차장
	buildKiosk(Kit.group(model, "Kiosk"), rng, mainPts)
	buildParking(Kit.group(model, "Parking"), rng)

	-- 4) 공원등(4.5 m) + 벤치 + 휴지통
	local fx = Kit.group(model, "Lamps")
	local function lampOK(x: number, z: number): boolean
		return not inBridge(x, M(2)) and not occupied(x, z, 1.5, 2) and not hashHit(lamps, x, z, 0, 1, M(5))
	end
	-- 강변 쪽 산책로 줄 (숲 앞 가장자리): 히어로 띠는 촘촘 + 광원
	do
		local x = -M(500)
		local cnt = 0
		local lz = EDGE_Z + EDGE_W / 2 + M(0.6)
		while x <= M(550) do
			local nearConn = false
			for _, cx in connX do
				if math.abs(x - cx) < M(3) then
					nearConn = true
				end
			end
			if not nearConn and lampOK(x, lz) then
				local hp = lamp(fx, x, lz)
				cnt += 1
				if x > VIEW_X - M(195) and x < VIEW_X + M(215) and cnt % 2 == 0 then
					lampLight(hp)
				end
			end
			x += if x > BELT_X0 and x < BELT_X1 then M(15) else M(33)
		end
	end
	-- 메인 산책로: 양쪽 엇갈림
	local side = 1
	for _, st in
		stations(mainPts, function(x: number): number
			return if math.abs(x - VIEW_X) < M(475) then M(20) else M(45)
		end, M(3))
	do
		local p, dir = st[1], st[2]
		local nrm = Vector2.new(-dir.Y, dir.X) * side
		local q = p + nrm * (MAIN_W / 2 + M(0.6))
		if lampOK(q.X, q.Y) then
			local hp = lamp(fx, q.X, q.Y)
			if q.X > DC.X - M(60) and q.X < DC.X + M(80) then
				lampLight(hp)
			end
		end
		side = -side
	end
	-- 연결로
	for ci, pts in connectors do
		local sd = if ci % 2 == 0 then 1 else -1
		for _, st in
			stations(pts, function(x: number): number
				return if math.abs(x - VIEW_X) < M(250) then M(13) elseif math.abs(x - VIEW_X) < M(475) then M(17) else M(35)
			end, M(4))
		do
			local p, dir = st[1], st[2]
			local q = p + Vector2.new(-dir.Y, dir.X) * sd * (CONN_W / 2 + M(0.5))
			if q.Y < zOnPath(mainPts, q.X) - MAIN_W and lampOK(q.X, q.Y) then
				local hp = lamp(fx, q.X, q.Y)
				if q.X > VIEW_X - M(195) and q.X < VIEW_X + M(215) and q.Y < BELT_Z1 then
					lampLight(hp)
				end
			end
			sd = -sd
		end
	end
	-- 벤치: 메인 산책로 근경 (+ 3 개마다 휴지통)
	local bside = 1
	local bcount = 0
	for _, st in
		stations(mainPts, function(_x: number): number
			return M(30)
		end, M(9))
	do
		local p, dir = st[1], st[2]
		if math.abs(p.X - VIEW_X) < M(410) then
			local nrm = Vector2.new(-dir.Y, dir.X) * bside
			local q = p + nrm * (MAIN_W / 2 + M(0.9))
			if not inBridge(q.X, M(3)) and not occupied(q.X, q.Y, M(0.6), 2) and not hashHit(lamps, q.X, q.Y, 0, 1, M(1.2)) then
				bench(fx, q.X, q.Y, -nrm)
				bcount += 1
				if bcount % 3 == 0 then
					local bq = q + dir * M(1.5)
					bin(fx, bq.X, bq.Y, groundAt(bq.X, bq.Y))
				end
			end
		end
		bside = -bside
	end

	-- 5) 둔덕
	buildMounds(rng)

	-- 6) 나무 (남은 파트 예산 전부)
	local treeCount = buildTrees(Kit.group(model, "Trees"), rng, PART_BUDGET - (Kit.stats.parts - p0))

	-- 공원 띠 전체 예약 (도시 생성기가 둔치를 침범하지 않도록)
	Kit.reserve(X0, Z0, X1, Z1, "Park")
	model:SetAttribute("Lights", lightsUsed)
	model:SetAttribute("Trees", treeCount)
	model:SetAttribute("Parts", Kit.stats.parts - p0)
end

return Park
