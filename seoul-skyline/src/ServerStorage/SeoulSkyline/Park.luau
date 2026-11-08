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
--     디테일: 데크 앞 "잠실 야경" 경사 안내판(약도 + 이름표), 계단 입구 표지(조명) + 샤프트에 10 m 마다 높이 표시,
--     엘리베이터 호출 버튼(SeoulElevator) 받침 기둥 + 지상 안내 토템 / 데크 계단 안내판. 버튼 위치는 그대로.
--   * 한강 편의점(KIOSK_X, 메인 산책로 강 쪽): 12 x 8 m, 천장고 2.9 m, 지붕 3.45 m(+ 띠 간판 3.75 m).
--     강 쪽 전면 유리 커튼월 + 자동문(유효폭 1.8 m x 2.3 m, 열린 상태; 문짝 태그 SeoulAutoDoor + ClosedOffset).
--     실내: 60 cm 타일 바닥, 곤돌라 2 (1.8 m, 4 단 양면, 상품 반복 패턴), 음료 냉장고 벽(유리문 6, 네온 백라이트),
--     아이스크림 냉동고, 한강라면 조리기 4 대(LED 표시창) + 온수기 + 라면 진열대, 계산대 0.9 m(POS·핫바), 담배 진열장,
--     창가 바 테이블 1.0 m + 스툴 8, 커피·전자레인지 코너, 직원 출입문 0.9 x 2.1 m, 걸이 간판·포스터·가격표(한글).
--     강 쪽 테라스 6.9 m: 파라솔 테이블 5, 줄조명(기둥 3 ↔ 캐노피), 분리수거함 4. 뒤편 자판기 2.
--   * 공중화장실(편의점 서쪽 9 m): 10 x 6 m 노출콘크리트 파빌리온, 천장고 2.6 m, 입구 2(폭 1.0 m) + 눈가림벽,
--     세면대 0.86 m·거울, 대변기 칸(1.0 x 1.5 m), 소변기, 고창(발광 띠).
--   * 공공자전거 대여소(강변 자전거도로 옆 Z 751 ~ 769): 거치대 9 + 자전거 5 + 키오스크 + 안내판.
--     편의점 테라스 → 피크닉장 → 강변 산책로 → 자전거도로를 잇는 3 m 연결로 + 테라스 조망 축(나무 없음).
--   * 나무: 줄기 1 + 수관 타원체 1~3 개. 높이 8 ~ 14 m, 줄기 Ø 0.3 ~ 0.6 m, 수관 Ø 5 ~ 9 m.
--   * 실제 광원은 MAX_LIGHTS 이내: 전망대 → 광장 → 편의점·화장실·대여소 → 주차장 → 히어로 띠 공원등 순서.

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
local PART_BUDGET = 3260 -- 공원 본체(길·전망대·주차장·가로등·나무). 나무가 남은 예산을 채움
local INTERIOR_BUDGET = 1800 -- 편의점·화장실·자전거 대여소·전망대 디테일(실내/근접 디테일) — 본체 예산과 별도
local MAX_LIGHTS = 56 -- 본체 40 + 실내 16

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
	-- 작동하는 엘리베이터: 호출 버튼(ProximityPrompt) → SeoulSkylineBoot 이 플레이어를 반대편 층으로 이동
	local function callButton(pos: Vector3, target: Vector3, action: string)
		local b = Kit.box(parent, CFrame.new(pos), Vector3.new(M(0.45), M(0.6), M(0.45)), CAB_GLOW, MAT.Neon, glowOpts("ElevatorCall", STEEL_LIGHT))
		b.CanQuery = true
		b:SetAttribute("ElevatorTarget", target)
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = action
		pp.ObjectText = "전망대 엘리베이터"
		pp.HoldDuration = 0.3
		pp.MaxActivationDistance = 12
		pp.RequiresLineOfSight = false
		pp.Parent = b
		game:GetService("CollectionService"):AddTag(b, "SeoulElevator")
	end
	local downAt = Vector3.new(sx, PLAZA_TOP + M(1.1), sz + STAIR_ROUT + M(1.2))
	local upAt = Vector3.new(cx + hw - M(1.6), DY + M(1.1), z1 - M(1.4))
	callButton(downAt, Vector3.new(cx, DY + 3.5, cz), "전망대로 올라가기")
	callButton(upAt, Vector3.new(sx, PLAZA_TOP + 3.5, sz + STAIR_ROUT + M(3.5)), "공원으로 내려가기")
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
	-- 볼라드 조명 2 (0.9 m): 데크 바닥을 따뜻하게 (히어로 좌하단에서 불 켜진 전망대로 읽히도록)
	for i, dx in { -(hw - M(1)), hw - M(1) } do
		local bx, bz = cx + dx, z1 - M(1)
		Kit.vcyl(parent, Vector3.new(bx, DY + M(0.4) - 0.15, bz), M(0.8) + 0.3, M(0.2), STEEL, MAT.Metal, opts("Bollard", { collide = true }))
		local bh = Kit.vcyl(parent, Vector3.new(bx, DY + M(0.85), bz), M(0.1), M(0.2), LAMP_HEAD, MAT.Neon, glowOpts("BollardLight"))
		if i == 1 then
			tryLight(bh, "PointLight", { color = P.LampWarm, brightness = 1.6, range = M(11) })
		end
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
-- 실내 헬퍼: ORG 기준 로컬 미터 좌표 (축 정렬 건물, -Z = 강 쪽).  B = 두 모서리 상자, CY = 세로 원기둥(바닥~윗면),
-- CH = 가로 원기둥(로컬 X 축 / alongZ), BAR = 두 점 사이 각재(튜브·전선).  모두 미터 단위.
------------------------------------------------------------------------------------------------------
local ORG = CFrame.identity
local irng = Random.new(Config.SEED + 4242) -- 실내 소품 전용(공원 rng 순서를 건드리지 않음) — Park.build 에서 재시드

local function at(x: number, y: number, z: number): CFrame
	return ORG * CFrame.new(M(x), M(y), M(z))
end

local function solid(name: string, extra: { [string]: any }?): any
	local o = opts(name, extra)
	o.collide = true
	o.query = true
	return o
end

local function BX(parent: Instance, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, color: Color3, mat: Enum.Material, o: any?): BasePart
	return Kit.box(parent, at((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), Vector3.new(M(math.abs(x1 - x0)), M(math.abs(y1 - y0)), M(math.abs(z1 - z0))), color, mat, o or opts("Prop"))
end

local function CY(parent: Instance, x: number, z: number, y0: number, y1: number, dia: number, color: Color3, mat: Enum.Material, o: any?): BasePart
	return Kit.cylAlongY(parent, at(x, (y0 + y1) / 2, z), M(y1 - y0), M(dia), color, mat, o or opts("Prop"))
end

local function CH(parent: Instance, x: number, y: number, z: number, len: number, dia: number, alongZ: boolean, color: Color3, mat: Enum.Material, o: any?): BasePart
	local cf = at(x, y, z)
	if alongZ then
		cf *= CFrame.Angles(0, math.rad(90), 0)
	end
	return Kit.hcyl(parent, cf, M(len), M(dia), color, mat, o or opts("Prop"))
end

local function BAR(parent: Instance, a: Vector3, b: Vector3, t: number, color: Color3, mat: Enum.Material, o: any?): BasePart
	local pa, pb = at(a.X, a.Y, a.Z).Position, at(b.X, b.Y, b.Z).Position
	local d = pb - pa
	local up = if math.abs(d.Unit.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
	return Kit.box(parent, CFrame.lookAt((pa + pb) / 2, pb, up), Vector3.new(M(t), M(t), d.Magnitude + M(t) * 0.5), color, mat, o or opts("Prop"))
end

-- 야간 발광 + 충돌(벽 일부인 발광 띠)
local function glowSolid(name: string, dayColor: Color3?): any
	local o = glowOpts(name, dayColor)
	o.collide = true
	o.query = true
	return o
end

local function matOr(name: string, fallback: Enum.Material): Enum.Material
	local ok, m = pcall(function(): any
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(m) == "EnumItem" then
		return m :: Enum.Material
	end
	return fallback
end
local TILE_MAT = matOr("CeramicTiles", MAT.SmoothPlastic)

-- 색 (편의점 = 가상 브랜드: 청록 띠 + 라임 포인트)
local WHITE_WALL = rgb(236, 234, 228)
local BRAND = rgb(20, 112, 134)
local BRAND2 = rgb(150, 206, 64)
local SS = rgb(184, 188, 194) -- 스테인리스
local SS_DARK = rgb(116, 120, 126)
local FLOOR_TILE = rgb(212, 210, 204)
local GROUT = rgb(160, 158, 152)
local LED_COOL = rgb(232, 242, 255)
local LED_DAY = rgb(226, 228, 230)
local GLASS_STORE = rgb(176, 200, 214)
local FRAME_DARK = rgb(44, 48, 54)
local WHITE_LABEL = rgb(255, 255, 255)

-- 상품 팔레트 / 진열 패턴(폭·높이 m, 같은 상품 연속 수 run, 깊이 d, cyl = 원기둥)
local C_SNACK = { rgb(222, 50, 44), rgb(250, 198, 40), rgb(244, 130, 36), rgb(40, 108, 198), rgb(58, 158, 78), rgb(150, 68, 170), rgb(238, 236, 228), rgb(34, 34, 38) }
local C_RAMEN = { rgb(204, 30, 30), rgb(224, 52, 36), rgb(238, 122, 30), rgb(250, 202, 60), rgb(34, 30, 30), rgb(240, 236, 224), rgb(178, 28, 36) }
local C_DAILY = { rgb(238, 242, 246), rgb(118, 180, 222), rgb(98, 190, 160), rgb(242, 170, 192), rgb(250, 222, 120), rgb(168, 200, 92), rgb(70, 90, 160) }
local C_SWEET = { rgb(118, 68, 40), rgb(202, 30, 60), rgb(250, 200, 40), rgb(240, 120, 160), rgb(82, 50, 30), rgb(238, 230, 210), rgb(60, 120, 200) }
local C_BREAD = { rgb(230, 190, 120), rgb(200, 148, 88), rgb(242, 232, 212), rgb(250, 212, 80), rgb(212, 92, 60), rgb(120, 170, 222) }
local C_DRINK = { rgb(74, 30, 22), rgb(236, 120, 30), rgb(70, 150, 230), rgb(176, 120, 52), rgb(120, 196, 110), rgb(222, 52, 44), rgb(240, 214, 80) }
local C_CAN = { rgb(200, 204, 210), rgb(36, 80, 170), rgb(214, 170, 60), rgb(40, 120, 60), rgb(200, 40, 40), rgb(30, 30, 34), rgb(240, 240, 236) }
local C_CIG = { rgb(240, 240, 236), rgb(196, 200, 206), rgb(30, 46, 96), rgb(200, 36, 40), rgb(206, 168, 80), rgb(110, 170, 220), rgb(40, 110, 70), rgb(26, 26, 30), rgb(120, 70, 140) }

-- 진열 패턴 (실측 m): w = 한 개 폭, h = 높이, d = 앞뒤 줄 깊이, gap = 개별 상품 사이 틈(≥ 2 cm, 낱개로 읽힘),
-- run = 같은 상품 연속 수(페이싱), fill = 페이싱이 채워질 확률(빈 자리 = 팔린 칸), stack = 세로 적층, lid = 컵 뚜껑 색
local G_MULTI = { colors = C_SNACK, w = { 0.26, 0.34 }, h = { 0.22, 0.3 }, run = { 1, 2 }, gap = 0.03, d = 0.28, fill = 0.9 } -- 묶음 과자
local G_BOX = { colors = C_SWEET, w = { 0.12, 0.18 }, h = { 0.15, 0.22 }, run = { 2, 4 }, gap = 0.025, d = 0.24, fill = 0.85 } -- 쿠키·비스킷 상자
local G_BAG = { colors = C_SNACK, w = { 0.17, 0.19 }, h = { 0.24, 0.26 }, run = { 2, 4 }, gap = 0.025, d = 0.26, fill = 0.85 } -- 봉지 과자 18 x 25 cm
local G_BAG_S = { colors = C_SNACK, w = { 0.14, 0.16 }, h = { 0.2, 0.23 }, run = { 2, 3 }, gap = 0.025, d = 0.24, fill = 0.6 } -- 작은 봉지(반쯤 팔림)
local G_RAMEN5 = { colors = C_RAMEN, w = { 0.36, 0.4 }, h = { 0.16, 0.2 }, run = { 1, 2 }, gap = 0.03, d = 0.27, fill = 0.9 } -- 5 입 묶음
local G_BOWL = { colors = C_RAMEN, w = { 0.15, 0.16 }, h = { 0.085, 0.095 }, run = { 2, 4 }, gap = 0.02, d = 0.16, cyl = true, stack = 2, fill = 0.85 } -- 큰사발 2 단
local G_CUP = { colors = C_RAMEN, w = { 0.1, 0.1 }, h = { 0.11, 0.11 }, run = { 3, 5 }, gap = 0.018, d = 0.1, cyl = true, lid = rgb(236, 236, 232), fill = 0.85 } -- 컵라면 Ø 10 x 11 cm + 뚜껑
local G_PACK = { colors = C_RAMEN, w = { 0.15, 0.15 }, h = { 0.2, 0.2 }, run = { 2, 4 }, gap = 0.025, d = 0.24, fill = 0.85 } -- 봉지라면 15 x 20 cm 세워 진열
local G_DAILY = { colors = C_DAILY, w = { 0.2, 0.26 }, h = { 0.1, 0.13 }, run = { 1, 3 }, gap = 0.025, d = 0.22, fill = 0.85 } -- 티슈·물티슈
local G_SMALL = { colors = C_DAILY, w = { 0.06, 0.09 }, h = { 0.16, 0.21 }, run = { 3, 5 }, gap = 0.025, d = 0.06, cyl = true, fill = 0.8 } -- 샴푸·세제 병
local G_ROLL = { colors = C_DAILY, w = { 0.3, 0.36 }, h = { 0.26, 0.3 }, run = { 1, 2 }, gap = 0.03, d = 0.3, fill = 0.9 } -- 화장지 묶음
local G_SWEET = { colors = C_SWEET, w = { 0.09, 0.14 }, h = { 0.08, 0.14 }, run = { 3, 5 }, gap = 0.02, d = 0.2, fill = 0.7 } -- 초콜릿·사탕
local G_BREAD = { colors = C_BREAD, w = { 0.16, 0.2 }, h = { 0.1, 0.14 }, run = { 1, 3 }, gap = 0.025, d = 0.25, fill = 0.75 } -- 빵
-- 냉장고 (500 ml PET Ø 6.8 cm × 21 cm, 캔 Ø 6.6 × 12.3 cm, 소주병 Ø 6.5 × 22 cm, 1.5 L Ø 9 × 31 cm)
local F_PET = { colors = C_DRINK, w = { 0.068, 0.072 }, h = { 0.23, 0.25 }, run = { 3, 6 }, gap = 0.03, d = 0.07, cyl = true, fill = 0.9 }
local F_WATER = { colors = { rgb(196, 226, 250) }, w = { 0.07, 0.075 }, h = { 0.23, 0.25 }, run = { 8, 14 }, gap = 0.03, d = 0.07, cyl = true, tr = 0.35 }
local F_SOJU = { colors = { rgb(56, 132, 78), rgb(46, 116, 70) }, w = { 0.065, 0.066 }, h = { 0.22, 0.22 }, run = { 6, 10 }, gap = 0.035, d = 0.065, cyl = true, tr = 0.25, mat = MAT.Glass }
local F_CAN = { colors = C_CAN, w = { 0.066, 0.066 }, h = { 0.123, 0.123 }, run = { 3, 6 }, gap = 0.025, d = 0.066, cyl = true, mat = MAT.Metal, stack = 2, fill = 0.85 }
local F_BIG = { colors = { rgb(74, 30, 22), rgb(120, 196, 110), rgb(236, 120, 30), rgb(196, 226, 250) }, w = { 0.09, 0.095 }, h = { 0.3, 0.32 }, run = { 2, 4 }, gap = 0.035, d = 0.09, cyl = true }
local F_CASE = { colors = { rgb(214, 170, 60), rgb(36, 80, 170), rgb(200, 204, 210), rgb(40, 120, 60), rgb(200, 40, 40) }, w = { 0.2, 0.26 }, h = { 0.13, 0.25 }, run = { 1, 2 }, gap = 0.03, d = 0.3, fill = 0.85 }
local F_MILK = { colors = { rgb(240, 240, 236), rgb(250, 220, 120), rgb(240, 180, 200), rgb(180, 120, 70), rgb(150, 200, 240) }, w = { 0.07, 0.08 }, h = { 0.16, 0.2 }, run = { 3, 6 }, gap = 0.025, d = 0.07 }

-- 선반 한 칸 진열: 진열 축(alongZ 이면 Z) a0..a1, 바닥 y, 선반 앞 가장자리 front, 안쪽 방향 inward(±1).
-- 같은 상품을 run 개씩(페이싱) 낱개 파트로 놓되 이웃 낱개는 명도를 번갈아(14 %) 바꾸고 2 cm 이상 띄워 개별 상품으로 읽히게 함.
-- 페이싱 일부는 비움(fill). 반환: 파트 수
local DARKEN = Color3.new(0, 0, 0)
local function fillShelf(parent: Instance, a0: number, a1: number, y: number, front: number, inward: number, kind: any, alongZ: boolean?): number
	local n = 0
	local a = a0 + 0.02
	local left = 0
	local col: Color3 = kind.colors[1]
	local w, h = 0.2, 0.2
	local empty = false
	local idx = 0
	local mat = kind.mat or MAT.SmoothPlastic
	local o = if kind.tr then { transparency = kind.tr } else nil
	local stack = kind.stack or 1
	while true do
		if left <= 0 then
			col = kind.colors[irng:NextInteger(1, #kind.colors)]
			left = irng:NextInteger(kind.run[1], kind.run[2])
			w = irng:NextNumber(kind.w[1], kind.w[2])
			h = irng:NextNumber(kind.h[1], kind.h[2])
			empty = irng:NextNumber() > (kind.fill or 1)
		end
		if a + w > a1 - 0.02 then
			break
		end
		if not empty then
			idx += 1
			local c = if idx % 2 == 0 then col:Lerp(DARKEN, 0.14) else col
			local f0 = front + inward * 0.025
			for k = 0, stack - 1 do
				local yb = y + k * h
				local ck = if k % 2 == 1 then c:Lerp(DARKEN, 0.1) else c
				if kind.cyl then
					local cc = f0 + inward * w / 2
					local px, pz = if alongZ then cc else a + w / 2, if alongZ then a + w / 2 else cc
					CY(parent, px, pz, yb, yb + h, w * 0.94, ck, mat, opts("Goods", o))
					n += 1
					if kind.lid and k == stack - 1 then
						CY(parent, px, pz, yb + h, yb + h + 0.012, w * 0.98, kind.lid, MAT.SmoothPlastic, opts("GoodsLid"))
						n += 1
					end
				else
					local f1 = f0 + inward * kind.d
					if alongZ then
						BX(parent, f0, yb, a, f1, yb + h, a + w, ck, mat, opts("Goods", o))
					else
						BX(parent, a, yb, f0, a + w, yb + h, f1, ck, mat, opts("Goods", o))
					end
					n += 1
				end
			end
		end
		left -= 1
		a += w + kind.gap
	end
	return n
end

-- 가격표(노랑/빨강), 일부만 글자
local PRICES = { "1,500", "2,200", "990", "1+1", "2+1", "3,300", "1,200", "4,500" }
local function priceTag(parent: Instance, x: number, y: number, zFace: number, out: number, labelled: boolean)
	local red = irng:NextNumber() < 0.3
	local t = BX(parent, x, y - 0.04, zFace, x + 0.075, y, zFace + out * 0.02, if red then rgb(222, 40, 40) else rgb(252, 222, 60), MAT.SmoothPlastic, opts("PriceTag"))
	if labelled then
		Kit.label(t, if out < 0 then Enum.NormalId.Front else Enum.NormalId.Back, PRICES[irng:NextInteger(1, #PRICES)], { glow = true, color = if red then WHITE_LABEL else rgb(30, 30, 30), pixelsPerStud = 120, font = Enum.Font.GothamBold })
	end
end

-- 곤돌라 진열대 (높이 1.8 m, 양면 각 깊이 0.35 m, 선반 4 단). kinds[side][level]: side 1 = -Z 면, 2 = +Z 면
local LV = { 0.12, 0.55, 0.98, 1.41 }
local GH, GD = 1.8, 0.35
local function gondola(parent: Instance, xa: number, xb: number, zc: number, kinds: { { any } }): number
	local base = rgb(70, 74, 82)
	local body = rgb(226, 228, 230)
	BX(parent, xa, 0, zc - GD + 0.02, xb, LV[1], zc + GD - 0.02, base, MAT.SmoothPlastic, solid("GondolaBase"))
	BX(parent, xa, LV[1], zc - 0.025, xb, GH, zc + 0.025, rgb(104, 108, 116), MAT.SmoothPlastic, solid("GondolaSpine")) -- 어두운 타공판: 상품 사이 틈이 보임
	BX(parent, xa - 0.03, 0, zc - GD, xa, GH + 0.03, zc + GD, body, MAT.SmoothPlastic, solid("GondolaEnd"))
	BX(parent, xb, 0, zc - GD, xb + 0.03, GH + 0.03, zc + GD, body, MAT.SmoothPlastic, solid("GondolaEnd"))
	BX(parent, xa, GH, zc - 0.07, xb, GH + 0.03, zc + 0.07, body, MAT.SmoothPlastic, opts("GondolaTop"))
	local n = 5
	for si, s in { -1, 1 } do
		local zf = zc + s * GD
		for li, lv in LV do
			if li > 1 then
				BX(parent, xa, lv - 0.025, zc + s * 0.025, xb, lv, zf, rgb(200, 202, 206), MAT.Metal, opts("Shelf"))
				BX(parent, xa, lv - 0.055, zf - s * 0.01, xb, lv - 0.004, zf + s * 0.015, rgb(246, 246, 240), MAT.SmoothPlastic, opts("PriceRail"))
				n += 2
				local nt = if li >= 3 then 4 else 2
				for k = 1, nt do
					local tx = xa + (xb - xa) * (k - 0.5) / nt + irng:NextNumber(-0.3, 0.3)
					priceTag(parent, tx, lv - 0.008, zf + s * 0.015, s, li >= 3 and k % 2 == 1)
					n += 1
				end
			else
				local zp = zc + s * (GD - 0.02)
				BX(parent, xa, 0.02, zp - s * 0.01, xb, 0.1, zp + s * 0.015, rgb(246, 246, 240), MAT.SmoothPlastic, opts("PriceRail"))
				n += 1
			end
			local kd = kinds[si][li]
			if kd.split then -- 한 칸을 반씩 두 상품군으로
				local xm = (xa + xb) / 2
				n += fillShelf(parent, xa, xm, lv, zf, -s, kd.split[1])
				n += fillShelf(parent, xm, xb, lv, zf, -s, kd.split[2])
			else
				n += fillShelf(parent, xa, xb, lv, zf, -s, kd)
			end
		end
	end
	return n
end

------------------------------------------------------------------------------------------------------
-- 2) 한강 편의점 (12 x 8 m, 천장고 2.9 m) + 테라스 + 화장실 + 자전거 대여소 + 피크닉장 + "한강공원" 표지석
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

-- 매장 실내 (로컬 m, 바닥 윗면 y = 0, 외벽 x ±6 / z ±4, 실내 x ±5.8 / z ±3.8)
local function storeInterior(inner: Instance)
	-- 바닥 타일 줄눈 (60 cm 격자)
	for k = 1, 19 do
		local x = -5.8 + 0.6 * k
		BX(inner, x - 0.0075, -0.01, -3.8, x + 0.0075, 0.016, 3.8, GROUT, MAT.SmoothPlastic, opts("Grout", { shadow = false }))
	end
	for k = 1, 12 do
		local z = -3.8 + 0.6 * k
		BX(inner, -5.8, -0.01, z - 0.0075, 5.8, 0.016, z + 0.0075, GROUT, MAT.SmoothPlastic, opts("Grout", { shadow = false }))
	end
	-- 걸레받이(양 측벽)
	BX(inner, -5.8, 0, -3.8, -5.775, 0.1, 3.8, rgb(90, 92, 96), MAT.SmoothPlastic, opts("Skirting"))
	BX(inner, 5.775, 0, -3.8, 5.8, 0.1, 3.8, rgb(90, 92, 96), MAT.SmoothPlastic, opts("Skirting"))

	-- 천장(2.9 m) + LED 라인 조명 4 (실광원 3) + 천장형 에어컨 + CCTV
	BX(inner, -5.8, 2.9, -3.8, 5.8, 2.96, 3.8, rgb(244, 244, 240), MAT.SmoothPlastic, solid("StoreCeiling"))
	for i, zc in { -2.2, -0.1, 2.1 } do
		local strip = BX(inner, -5.0, 2.86, zc - 0.08, 3.4, 2.9, zc + 0.08, LED_COOL, MAT.Neon, glowOpts("CeilingLed", LED_DAY))
		tryLight(strip, "PointLight", { color = LED_COOL, brightness = if i == 2 then 1.2 else 1.0, range = M(6.5) })
	end
	BX(inner, 4.92, 2.86, -2.0, 5.08, 2.9, 1.4, LED_COOL, MAT.Neon, glowOpts("CeilingLed", LED_DAY))
	BX(inner, -2.3, 2.86, 0.6, -1.5, 2.9, 1.4, rgb(236, 236, 234), MAT.SmoothPlastic, opts("AirCon"))
	BX(inner, -2.2, 2.84, 0.7, -1.6, 2.86, 1.3, rgb(120, 122, 126), MAT.SmoothPlastic, opts("AirConGrille"))
	Kit.ball(inner, at(5.3, 2.84, -3.4).Position, M(0.12), rgb(30, 30, 34), MAT.Glass, opts("CCTV"))

	-- 통로 걸이 간판 3 (계산대 쪽에서 통로를 바라볼 때 보임)
	for _, a in { { -2.15, "과자 · 스낵" }, { -0.1, "라면 · 생활용품" }, { 2.05, "음료 · 아이스크림" } } do
		local zc = a[1] :: number
		local sg = BX(inner, 1.235, 2.3, zc - 0.45, 1.265, 2.55, zc + 0.45, BRAND, MAT.SmoothPlastic, opts("AisleSign"))
		Kit.label(sg, Enum.NormalId.Right, a[2] :: string, { glow = true, color = WHITE_LABEL, pixelsPerStud = 50 })
		Kit.label(sg, Enum.NormalId.Left, a[2] :: string, { glow = true, color = WHITE_LABEL, pixelsPerStud = 50 })
		BX(inner, 1.24, 2.55, zc - 0.01, 1.26, 2.9, zc + 0.01, SS, MAT.Metal, opts("SignRod"))
	end

	-- 곤돌라 2 (x -3.8 ~ 1.0, 높이 1.8 m): 창가 통로 1.55 m / 가운데 1.1 m / 냉장고 앞 1.85 m
	gondola(inner, -3.8, 1.0, -1.0, {
		{ G_MULTI, G_BOX, G_BAG, G_BAG_S },
		{ G_RAMEN5, G_BOWL, { split = { G_CUP, G_PACK } }, G_PACK },
	})
	gondola(inner, -3.8, 1.0, 0.8, {
		{ G_ROLL, G_DAILY, G_SMALL, G_SWEET },
		{ G_MULTI, G_BREAD, G_BAG, G_BOX },
	})
	-- 엔드캡 행사 매대 (+X 끝, 입구 쪽): 음료 박스 / 컵라면 박스 + "2+1" "1+1"
	for i, zc in { -1.0, 0.8 } do
		local ca, cb = if i == 1 then rgb(214, 170, 60) else rgb(204, 30, 30), if i == 1 then rgb(36, 80, 170) else rgb(238, 122, 30)
		BX(inner, 1.03, 0, zc - 0.3, 1.4, 0.1, zc + 0.3, rgb(70, 74, 82), MAT.SmoothPlastic, solid("Endcap"))
		BX(inner, 1.06, 0.1, zc - 0.28, 1.38, 0.38, zc - 0.01, ca, MAT.SmoothPlastic, opts("PromoCase"))
		BX(inner, 1.06, 0.1, zc + 0.01, 1.38, 0.38, zc + 0.28, cb, MAT.SmoothPlastic, opts("PromoCase"))
		BX(inner, 1.08, 0.38, zc - 0.2, 1.36, 0.64, zc + 0.2, ca:Lerp(cb, 0.5), MAT.SmoothPlastic, opts("PromoCase"))
		local pop = BX(inner, 1.38, 0.86, zc - 0.15, 1.395, 1.06, zc + 0.15, rgb(226, 36, 40), MAT.SmoothPlastic, opts("PromoPOP"))
		Kit.label(pop, Enum.NormalId.Right, if i == 1 then "2+1" else "1+1", { glow = true, color = rgb(255, 240, 120), pixelsPerStud = 60, font = Enum.Font.GothamBold })
		BX(inner, 1.36, 0.64, zc - 0.006, 1.372, 0.88, zc + 0.006, SS, MAT.Metal, opts("PromoStick"))
	end

	-- 음료 냉장고 벽 (뒷벽, 유리문 6 × 0.8 m, 높이 2.0 m + 상부 간판) — 네온 백라이트 + 상단 SurfaceLight
	local fx0, fx1 = -4.9, -0.1
	local doors = 6
	local dw = (fx1 - fx0) / doors
	BX(inner, fx0 - 0.05, 0, 3.0, fx0, 2.4, 3.8, rgb(232, 232, 230), MAT.SmoothPlastic, solid("FridgeSide"))
	BX(inner, fx1, 0, 3.0, fx1 + 0.05, 2.4, 3.8, rgb(232, 232, 230), MAT.SmoothPlastic, solid("FridgeSide"))
	BX(inner, fx0, 0, 3.03, fx1, 0.15, 3.8, rgb(54, 58, 64), MAT.SmoothPlastic, solid("FridgeKick"))
	local fhead = BX(inner, fx0, 2.0, 2.96, fx1, 2.4, 3.8, BRAND, MAT.SmoothPlastic, solid("FridgeHeader"))
	Kit.label(fhead, Enum.NormalId.Front, "음료 · 맥주 · 생수", { glow = true, color = WHITE_LABEL, pixelsPerStud = 30 })
	tryLight(fhead, "SurfaceLight", { face = Enum.NormalId.Bottom, angle = 110, range = M(3.2), brightness = 1.6, color = LED_COOL })
	BX(inner, fx0, 0.15, 3.72, fx1, 2.0, 3.78, rgb(150, 172, 196), MAT.Neon, glowOpts("FridgeBacklight", rgb(214, 218, 222)))
	local levels = { 0.15, 0.5, 0.86, 1.22, 1.58 }
	local kindsAt = {
		{ F_CASE, F_BIG, F_CASE },
		{ F_SOJU, F_PET, F_WATER },
		{ F_PET, F_PET, F_WATER },
		{ F_CAN, F_CAN, F_MILK },
		{ F_MILK, F_PET, F_PET },
	}
	for li, lv in levels do
		if li > 1 then
			BX(inner, fx0, lv - 0.02, 3.06, fx1, lv, 3.7, rgb(190, 194, 200), MAT.Metal, opts("FridgeShelf"))
			BX(inner, fx0, lv - 0.05, 3.045, fx1, lv - 0.004, 3.07, rgb(246, 246, 240), MAT.SmoothPlastic, opts("PriceRail"))
		end
		for seg = 1, 3 do
			local a0 = fx0 + (seg - 1) * dw * 2
			fillShelf(inner, a0, a0 + dw * 2, lv, 3.06, 1, kindsAt[li][seg])
		end
	end
	BX(inner, fx0, 0.15, 3.0, fx1, 2.0, 3.02, rgb(200, 220, 235), MAT.Glass, solid("FridgeGlass", { transparency = 0.74 }))
	for k = 0, doors do
		local x = fx0 + k * dw
		BX(inner, x - 0.025, 0.15, 2.97, x + 0.025, 2.0, 3.0, FRAME_DARK, MAT.Metal, opts("FridgeFrame"))
		if k < doors then
			local hx = x + dw - 0.09
			BX(inner, hx - 0.012, 0.85, 2.92, hx + 0.012, 1.55, 2.97, SS, MAT.Metal, opts("FridgeHandle"))
		end
	end
	BX(inner, fx0, 0.15, 2.97, fx1, 0.21, 3.0, FRAME_DARK, MAT.Metal, opts("FridgeRail"))
	BX(inner, fx0, 1.94, 2.97, fx1, 2.0, 3.0, FRAME_DARK, MAT.Metal, opts("FridgeRail"))
	for i, x in { -4.6, -1.4 } do
		local tg = BX(inner, x, 1.66, 2.95, x + 0.2, 1.78, 2.97, rgb(226, 36, 40), MAT.SmoothPlastic, opts("GlassPOP"))
		Kit.label(tg, Enum.NormalId.Front, if i == 1 then "4캔 1만원" else "2+1", { glow = true, color = WHITE_LABEL, pixelsPerStud = 80, font = Enum.Font.GothamBold })
	end

	-- 한강라면 조리기 스테이션 (-X 벽, 스테인리스 카운터 0.9 m, 조리기 4 대 + 온수기 + 라면 진열대)
	BX(inner, -5.75, 0, -2.38, -5.15, 0.1, 2.38, rgb(60, 62, 66), MAT.Metal, solid("RamenKick"))
	BX(inner, -5.8, 0.1, -2.4, -5.1, 0.86, 2.4, SS, MAT.Metal, solid("RamenCounter"))
	BX(inner, -5.8, 0.86, -2.43, -5.06, 0.9, 2.43, rgb(208, 212, 218), MAT.Metal, solid("RamenTop", { reflectance = 0.08 }))
	for i, c in { -1.75, -0.85, 0.05, 0.95 } do
		BX(inner, -5.66, 0.9, c - 0.19, -5.22, 0.93, c + 0.19, rgb(22, 22, 26), MAT.SmoothPlastic, opts("CookerPlate", { reflectance = 0.15 }))
		BX(inner, -5.79, 0.9, c - 0.2, -5.62, 1.34, c + 0.2, rgb(226, 228, 232), MAT.SmoothPlastic, solid("RamenCooker", { reflectance = 0.06 }))
		BX(inner, -5.79, 1.34, c - 0.2, -5.24, 1.54, c + 0.2, rgb(226, 228, 232), MAT.SmoothPlastic, solid("RamenCookerHead", { reflectance = 0.06 }))
		local led = BX(inner, -5.24, 1.38, c - 0.13, -5.225, 1.48, c + 0.13, rgb(14, 14, 16), MAT.SmoothPlastic, opts("CookerLED"))
		Kit.label(led, Enum.NormalId.Right, if i == 2 then "02:47" elseif i == 3 then "01:15" else "READY", { glow = true, color = if i == 2 or i == 3 then rgb(255, 64, 40) else rgb(90, 255, 120), font = Enum.Font.GothamBold, pixelsPerStud = 90 })
		BX(inner, -5.24, 1.495, c - 0.19, -5.225, 1.53, c + 0.19, rgb(206, 36, 36), MAT.SmoothPlastic, opts("CookerBand"))
		CY(inner, -5.44, c, 1.29, 1.34, 0.04, SS_DARK, MAT.Metal, opts("CookerNozzle"))
		BX(inner, -5.24, 1.345, c + 0.14, -5.225, 1.37, c + 0.18, rgb(255, 120, 60), MAT.Neon, glowOpts("CookerBtn", rgb(200, 60, 40)))
		if i == 2 or i == 3 then -- 조리 중인 라면 (은박 용기 + 빨간 국물)
			CY(inner, -5.44, c, 0.93, 1.02, 0.17, rgb(214, 214, 210), MAT.Metal, opts("RamenBowl"))
			CY(inner, -5.44, c, 1.02, 1.04, 0.14, rgb(196, 82, 36), MAT.SmoothPlastic, opts("RamenSoup"))
		end
	end
	-- 온수기 + 받침대
	BX(inner, -5.78, 0.9, 1.52, -5.4, 1.56, 1.98, rgb(236, 236, 232), MAT.SmoothPlastic, solid("HotWater"))
	BX(inner, -5.4, 1.18, 1.68, -5.32, 1.24, 1.82, rgb(200, 40, 36), MAT.SmoothPlastic, opts("HotWaterTap"))
	BX(inner, -5.42, 0.9, 1.6, -5.25, 0.94, 1.9, rgb(70, 72, 76), MAT.Metal, opts("DripTray"))
	local hwl = BX(inner, -5.4, 1.36, 1.6, -5.385, 1.5, 1.9, rgb(200, 40, 36), MAT.SmoothPlastic, opts("HotWaterLabel"))
	Kit.label(hwl, Enum.NormalId.Right, "뜨거운 물", { glow = true, color = WHITE_LABEL, pixelsPerStud = 80 })
	-- 용기 더미, 젓가락·냅킨, 국물 버리는 곳
	CY(inner, -5.55, 2.2, 0.9, 1.3, 0.17, rgb(238, 238, 232), MAT.SmoothPlastic, opts("BowlStack"))
	CY(inner, -5.3, 2.2, 0.9, 1.15, 0.17, rgb(206, 206, 202), MAT.Metal, opts("FoilBowlStack"))
	CY(inner, -5.3, 1.33, 0.9, 1.05, 0.08, rgb(84, 62, 42), MAT.Wood, opts("ChopstickCup"))
	BX(inner, -5.33, 1.05, 1.3, -5.27, 1.22, 1.36, rgb(222, 202, 160), MAT.Wood, opts("Chopsticks"))
	BX(inner, -5.64, 0.9, 1.22, -5.46, 1.08, 1.42, rgb(40, 40, 44), MAT.SmoothPlastic, opts("NapkinBox"))
	BX(inner, -5.75, 0.9, -2.38, -5.2, 0.96, -2.02, rgb(146, 150, 156), MAT.Metal, opts("SoupSink"))
	local ssl = BX(inner, -5.8, 1.06, -2.38, -5.785, 1.26, -2.0, rgb(250, 250, 246), MAT.SmoothPlastic, opts("SoupSinkSign"))
	Kit.label(ssl, Enum.NormalId.Right, "국물 버리는 곳", { glow = true, color = rgb(40, 40, 40), pixelsPerStud = 80 })
	-- 벽 라면 진열대 (스테인리스 3 단): 봉지라면 2 단 + 5 입 묶음 1 단
	for li, lv in { 1.62, 1.88, 2.14 } do
		BX(inner, -5.8, lv - 0.02, -2.4, -5.5, lv, 2.4, SS, MAT.Metal, opts("RamenRack"))
		BX(inner, -5.51, lv - 0.05, -2.4, -5.485, lv - 0.004, 2.4, rgb(252, 222, 60), MAT.SmoothPlastic, opts("PriceRail"))
		fillShelf(inner, -2.38, 2.38, lv, -5.5, -1, if li == 3 then G_RAMEN5 else G_PACK, true)
	end
	BX(inner, -5.8, 1.55, -2.43, -5.5, 2.16, -2.4, SS_DARK, MAT.Metal, opts("RackSide"))
	BX(inner, -5.8, 1.55, 2.4, -5.5, 2.16, 2.43, SS_DARK, MAT.Metal, opts("RackSide"))
	local rsign = BX(inner, -5.8, 2.42, -1.9, -5.72, 2.82, 1.9, rgb(198, 28, 30), MAT.SmoothPlastic, opts("RamenSign"))
	Kit.label(rsign, Enum.NormalId.Right, "한강라면 조리기", { glow = true, color = rgb(255, 242, 206), pixelsPerStud = 30 })
	tryLight(rsign, "PointLight", { color = rgb(255, 214, 170), brightness = 1.0, range = M(4.5) })
	local how = BX(inner, -5.8, 1.0, 2.55, -5.785, 2.1, 3.55, rgb(252, 238, 204), MAT.SmoothPlastic, opts("RamenHowTo"))
	Kit.label(how, Enum.NormalId.Right, "한강라면 끓이는 법\n① 라면 고르기\n② 계산 후 용기에 담기\n③ 조리기에 올리고 버튼\n④ 3분 30초 완성!", { glow = true, color = rgb(150, 24, 24), pixelsPerStud = 60, font = Enum.Font.GothamMedium })
	BX(inner, -5.7, 0, 2.85, -5.25, 0.75, 3.3, rgb(90, 96, 100), MAT.Metal, solid("CupBin"))
	BX(inner, -5.72, 0.75, 2.83, -5.23, 0.8, 3.32, rgb(60, 140, 90), MAT.SmoothPlastic, opts("CupBinLid"))

	-- 창가 바 테이블 (강을 향함, 상판 1.0 m) + 스툴 8 (좌면 0.74 m) + 먹다 남은 소품
	BX(inner, -5.75, 0.97, -3.84, 1.3, 1.02, -3.32, rgb(176, 140, 100), MAT.Wood, solid("WindowCounter"))
	BX(inner, -5.75, 0, -3.84, 1.3, 0.97, -3.8, rgb(226, 224, 218), MAT.SmoothPlastic, solid("WindowCounterApron"))
	CH(inner, -2.225, 0.25, -3.45, 6.95, 0.035, false, SS, MAT.Metal, opts("FootRail"))
	for i = 0, 7 do
		local sx = -5.2 + i * 0.85
		CY(inner, sx, -3.0, 0, 0.03, 0.4, rgb(50, 52, 56), MAT.Metal, opts("StoolBase"))
		CY(inner, sx, -3.0, 0.03, 0.68, 0.05, SS, MAT.Metal, opts("StoolPole"))
		CY(inner, sx, -3.0, 0.68, 0.74, 0.36, rgb(36, 36, 40), MAT.SmoothPlastic, solid("StoolSeat"))
	end
	CY(inner, -4.35, -3.6, 1.02, 1.11, 0.16, rgb(214, 214, 210), MAT.Metal, opts("RamenBowl"))
	CY(inner, -4.35, -3.6, 1.11, 1.13, 0.13, rgb(196, 82, 36), MAT.SmoothPlastic, opts("RamenSoup"))
	BX(inner, -4.33, 1.13, -3.72, -4.31, 1.145, -3.46, rgb(222, 202, 160), MAT.Wood, opts("Chopsticks"))
	CY(inner, -4.0, -3.55, 1.02, 1.143, 0.066, rgb(214, 170, 60), MAT.Metal, opts("BeerCan"))
	CY(inner, -3.9, -3.62, 1.02, 1.143, 0.066, rgb(36, 80, 170), MAT.Metal, opts("BeerCan"))
	BX(inner, -4.62, 1.02, -3.62, -4.47, 1.036, -3.47, rgb(246, 246, 242), MAT.SmoothPlastic, opts("Napkin"))
	CY(inner, -1.8, -3.6, 1.02, 1.12, 0.08, rgb(244, 244, 240), MAT.SmoothPlastic, opts("CoffeeCup"))
	CY(inner, -1.8, -3.6, 1.12, 1.135, 0.085, rgb(60, 40, 30), MAT.SmoothPlastic, opts("CupLid"))
	BX(inner, -2.12, 1.02, -3.7, -2.04, 1.036, -3.55, rgb(20, 20, 24), MAT.SmoothPlastic, opts("Phone"))
	CY(inner, -0.1, -3.58, 1.02, 1.14, 0.12, rgb(204, 30, 30), MAT.SmoothPlastic, opts("CupNoodle"))
	BX(inner, -0.02, 1.02, -3.72, 0.0, 1.036, -3.46, rgb(222, 202, 160), MAT.Wood, opts("Chopsticks"))
	-- 유리창 포스터 (밖을 향함)
	for _, p in { { 0.35, 1.15, "1+1 · 2+1\n행사 상품", rgb(222, 40, 44), WHITE_LABEL }, { 3.75, 4.6, "한강라면\n조리기 운영중", rgb(250, 196, 40), rgb(150, 20, 20) } } do
		local pst = BX(inner, p[1] :: number, 1.45, -3.875, p[2] :: number, 2.05, -3.86, p[4] :: Color3, MAT.SmoothPlastic, opts("WindowPoster"))
		Kit.label(pst, Enum.NormalId.Front, p[3] :: string, { glow = true, color = p[5] :: Color3, pixelsPerStud = 50, font = Enum.Font.GothamBold })
	end

	-- 계산대 (상판 0.9 m) + POS + 고객 화면 + 카드 단말 + 핫바 온장고 + 껌 매대
	BX(inner, 4.0, 0, -2.2, 4.6, 0.88, 1.6, rgb(240, 240, 236), MAT.SmoothPlastic, solid("Counter"))
	BX(inner, 3.97, 0.12, -2.1, 4.0, 0.8, 1.5, BRAND, MAT.SmoothPlastic, opts("CounterFront"))
	BX(inner, 3.955, 0.74, -2.1, 3.97, 0.77, 1.5, BRAND2, MAT.Neon, glowOpts("CounterStripe", BRAND2))
	BX(inner, 3.95, 0.88, -2.25, 4.65, 0.92, 1.65, rgb(70, 72, 78), MAT.Granite, solid("CounterTop"))
	local age = BX(inner, 3.955, 0.45, -0.95, 3.97, 0.62, -0.15, rgb(250, 250, 246), MAT.SmoothPlastic, opts("AgeNotice"))
	Kit.label(age, Enum.NormalId.Left, "19세 미만 술·담배 판매 금지", { glow = true, color = rgb(200, 20, 20), pixelsPerStud = 80 })
	CY(inner, 4.42, -0.4, 0.92, 1.05, 0.06, rgb(30, 30, 34), MAT.Metal, opts("POSStand"))
	BX(inner, 4.38, 1.04, -0.62, 4.45, 1.3, -0.18, rgb(24, 24, 28), MAT.SmoothPlastic, opts("POS"))
	BX(inner, 4.45, 1.06, -0.6, 4.465, 1.28, -0.2, rgb(140, 196, 255), MAT.Neon, glowOpts("POSScreen", rgb(40, 50, 60)))
	BX(inner, 4.05, 0.92, -0.75, 4.12, 1.12, -0.5, rgb(24, 24, 28), MAT.SmoothPlastic, opts("CustomerDisplay"))
	BX(inner, 4.035, 0.95, -0.72, 4.05, 1.1, -0.53, rgb(110, 214, 255), MAT.Neon, glowOpts("CustomerScreen", rgb(40, 50, 60)))
	BX(inner, 4.06, 0.92, -0.1, 4.2, 0.97, 0.06, rgb(30, 30, 34), MAT.SmoothPlastic, opts("CardTerminal"))
	BX(inner, 4.3, 0.92, 0.15, 4.5, 1.04, 0.35, rgb(40, 40, 44), MAT.SmoothPlastic, opts("ReceiptPrinter"))
	BX(inner, 4.15, 0.92, -1.1, 4.27, 0.98, -0.95, rgb(30, 30, 34), MAT.SmoothPlastic, opts("Scanner"))
	BX(inner, 4.08, 0.92, 1.05, 4.55, 0.96, 1.55, rgb(255, 170, 90), MAT.Neon, glowOpts("HotbarWarm", rgb(150, 150, 146)))
	BX(inner, 4.08, 0.96, 1.05, 4.55, 1.22, 1.55, rgb(230, 230, 220), MAT.Glass, opts("HotbarGlass", { transparency = 0.6 }))
	for j = 0, 2 do
		CH(inner, 4.31, 1.0, 1.17 + j * 0.13, 0.36, 0.04, false, rgb(176, 72, 50), MAT.SmoothPlastic, opts("Hotbar"))
	end
	BX(inner, 3.93, 0.5, 0.35, 3.95, 0.88, 1.25, rgb(214, 214, 210), MAT.Metal, opts("GumRack"))
	for r = 0, 1 do
		for k = 0, 2 do
			BX(inner, 3.82, 0.52 + r * 0.18, 0.38 + k * 0.29, 3.93, 0.64 + r * 0.18, 0.64 + k * 0.29, C_SWEET[irng:NextInteger(1, #C_SWEET)], MAT.SmoothPlastic, opts("Gum"))
		end
	end
	-- 담배 진열장 (계산대 뒤, 일반 포장) + 하부장 + 헤더
	BX(inner, 5.35, 0, -2.2, 5.8, 0.9, 1.6, rgb(240, 240, 236), MAT.SmoothPlastic, solid("CigCabinet"))
	BX(inner, 5.6, 0.9, -2.2, 5.8, 2.4, 1.6, rgb(36, 38, 44), MAT.SmoothPlastic, solid("CigWall"))
	local chd = BX(inner, 5.5, 2.4, -2.2, 5.8, 2.7, 1.6, rgb(36, 38, 44), MAT.SmoothPlastic, opts("CigHeader"))
	Kit.label(chd, Enum.NormalId.Left, "담배 · 전자담배", { glow = true, color = rgb(230, 230, 230), pixelsPerStud = 30 })
	-- 담뱃갑 낱개 5.5 x 8.8 cm, 11.5 cm 간격 3 단 (아크릴 칸막이 뒤 어두운 배경, 일부 품절)
	for r = 0, 2 do
		local y = 1.05 + r * 0.4
		BX(inner, 5.48, y - 0.03, -2.15, 5.6, y, 1.55, rgb(232, 238, 246), MAT.Neon, glowOpts("CigShelfLed", LED_DAY))
		local z = -2.1
		local col = C_CIG[1]
		while z + 0.055 <= 1.52 do
			if irng:NextNumber() < 0.35 then
				col = C_CIG[irng:NextInteger(1, #C_CIG)]
			end
			if irng:NextNumber() > 0.08 then
				BX(inner, 5.52, y, z, 5.58, y + 0.088, z + 0.055, col, MAT.SmoothPlastic, opts("CigPack"))
			end
			z += 0.115
		end
	end
	BX(inner, 4.62, 0, -2.0, 5.33, 0.016, 1.4, rgb(30, 30, 32), MAT.Fabric, opts("CashierMat"))
	-- 직원 출입문 (+Z 벽, 0.9 x 2.1 m)
	BX(inner, 4.54, 0, 3.72, 4.6, 2.16, 3.8, FRAME_DARK, MAT.Metal, solid("DoorJamb"))
	BX(inner, 5.5, 0, 3.72, 5.56, 2.16, 3.8, FRAME_DARK, MAT.Metal, solid("DoorJamb"))
	BX(inner, 4.6, 2.1, 3.72, 5.5, 2.16, 3.8, FRAME_DARK, MAT.Metal, solid("DoorHead"))
	BX(inner, 4.6, 0.01, 3.76, 5.5, 2.1, 3.8, rgb(150, 156, 164), MAT.Metal, solid("StaffDoor"))
	BX(inner, 4.66, 0.98, 3.7, 4.8, 1.01, 3.76, SS, MAT.Metal, opts("DoorLever"))
	local stf = BX(inner, 4.8, 1.45, 3.745, 5.3, 1.6, 3.76, rgb(240, 240, 236), MAT.SmoothPlastic, opts("StaffSign"))
	Kit.label(stf, Enum.NormalId.Front, "관계자 외 출입금지", { glow = true, color = rgb(200, 20, 20), pixelsPerStud = 80 })

	-- 커피 머신 · 전자레인지 코너 (+Z 벽)
	BX(inner, 0.12, 0, 3.22, 2.08, 0.86, 3.8, rgb(232, 232, 228), MAT.SmoothPlastic, solid("CoffeeCabinet"))
	BX(inner, 0.08, 0.86, 3.18, 2.12, 0.9, 3.8, rgb(70, 72, 78), MAT.Granite, solid("CoffeeTop"))
	BX(inner, 0.3, 0.9, 3.38, 0.78, 1.6, 3.78, rgb(28, 28, 32), MAT.SmoothPlastic, solid("CoffeeMachine"))
	BX(inner, 0.38, 1.36, 3.365, 0.7, 1.52, 3.38, rgb(140, 210, 255), MAT.Neon, glowOpts("CoffeeScreen", rgb(40, 50, 60)))
	BX(inner, 0.38, 0.9, 3.3, 0.7, 0.95, 3.38, rgb(60, 62, 66), MAT.Metal, opts("CoffeeTray"))
	CY(inner, 0.98, 3.55, 0.9, 1.3, 0.1, rgb(244, 244, 240), MAT.SmoothPlastic, opts("CupStack"))
	for _, mx in { 1.38, 1.84 } do
		BX(inner, mx - 0.22, 0.9, 3.4, mx + 0.22, 1.18, 3.78, rgb(214, 214, 210), MAT.SmoothPlastic, solid("Microwave"))
		BX(inner, mx - 0.2, 0.93, 3.385, mx + 0.08, 1.15, 3.4, rgb(30, 34, 40), MAT.Glass, opts("MicrowaveDoor"))
	end
	local cfs = BX(inner, 0.2, 1.75, 3.785, 2.0, 1.95, 3.8, BRAND, MAT.SmoothPlastic, opts("CoffeeSign"))
	Kit.label(cfs, Enum.NormalId.Front, "원두커피 1,500원  ·  전자레인지", { glow = true, color = WHITE_LABEL, pixelsPerStud = 60 })

	-- 아이스크림 냉동고 (뒷벽, 1.4 x 0.7 m, 높이 0.85 m, 유리 슬라이딩 뚜껑)
	local qz0, qz1 = 3.05, 3.75
	BX(inner, 2.3, 0, qz0, 3.7, 0.62, qz1, rgb(244, 244, 240), MAT.SmoothPlastic, solid("IceFreezer"))
	BX(inner, 2.3, 0.62, qz0, 3.7, 0.85, qz0 + 0.05, rgb(244, 244, 240), MAT.SmoothPlastic, solid("FreezerRim"))
	BX(inner, 2.3, 0.62, qz1 - 0.05, 3.7, 0.85, qz1, rgb(244, 244, 240), MAT.SmoothPlastic, solid("FreezerRim"))
	BX(inner, 2.3, 0.62, qz0 + 0.05, 2.35, 0.85, qz1 - 0.05, rgb(244, 244, 240), MAT.SmoothPlastic, solid("FreezerRim"))
	BX(inner, 3.65, 0.62, qz0 + 0.05, 3.7, 0.85, qz1 - 0.05, rgb(244, 244, 240), MAT.SmoothPlastic, solid("FreezerRim"))
	for row = 0, 1 do
		local x = 2.37
		while true do
			local w = irng:NextNumber(0.1, 0.16)
			if x + w > 3.63 then
				break
			end
			local zA = if row == 0 then qz0 + 0.07 else qz0 + 0.37
			BX(inner, x, 0.62, zA, x + w, 0.62 + irng:NextNumber(0.06, 0.15), zA + 0.26, C_SWEET[irng:NextInteger(1, #C_SWEET)]:Lerp(rgb(255, 255, 255), 0.15), MAT.SmoothPlastic, opts("IceCream"))
			x += w + 0.025
		end
	end
	BX(inner, 2.35, 0.81, qz0 + 0.05, 3.65, 0.83, qz1 - 0.05, rgb(210, 230, 245), MAT.Glass, opts("FreezerLid", { transparency = 0.65 }))
	local ice = BX(inner, 2.55, 0.28, qz0 - 0.015, 3.45, 0.56, qz0, BRAND, MAT.SmoothPlastic, opts("FreezerSign"))
	Kit.label(ice, Enum.NormalId.Front, "아이스크림 2+1", { glow = true, color = WHITE_LABEL, pixelsPerStud = 60, font = Enum.Font.GothamBold })

	-- 장바구니 더미 (입구 옆, 빨간 플라스틱 3 단 + 손잡이)
	for k = 0, 2 do
		BX(inner, 3.75, k * 0.09, -3.68, 4.2, 0.2 + k * 0.09, -3.38, rgb(206, 34, 40), MAT.SmoothPlastic, opts("Basket", { collide = k == 0 }))
	end
	BX(inner, 3.96, 0.38, -3.68, 3.99, 0.5, -3.38, rgb(40, 40, 44), MAT.SmoothPlastic, opts("BasketHandle"))
	-- 입구 매트 (180° 돌려 들어오는 손님 쪽으로 글자)
	local mat = Kit.box(inner, at(2.7, 0.008, -3.25) * CFrame.Angles(0, math.pi, 0), Vector3.new(M(1.6), M(0.016), M(1.0)), rgb(40, 52, 70), MAT.Fabric, opts("EntranceMat"))
	Kit.label(mat, Enum.NormalId.Top, "어서오세요", { glow = false, color = rgb(196, 206, 220), pixelsPerStud = 40 })
end

-- 매장 외피 (강 쪽 유리 커튼월 + 자동문, 지붕 캐노피, 간판, 자판기, 실외기)
local function storeShell(shell: Instance, TY: number)
	local CLAD = rgb(206, 208, 210)
	local STONE = rgb(70, 72, 76)
	-- 바닥 슬래브 (윗면 = 매장 바닥, 테라스보다 0.09 m 높음)
	BX(shell, -6, -0.63, -4, 6, 0, 4, FLOOR_TILE, MAT.SmoothPlastic, solid("StoreFloor"))
	-- 벽 (안쪽 흰색) + 바깥 알루미늄 복합패널 + 화강석 걸레받이
	BX(shell, -6, 0, 3.8, 6, 3.15, 4.0, WHITE_WALL, MAT.SmoothPlastic, solid("StoreWall"))
	BX(shell, -6, 0, -4, -5.8, 3.15, 3.8, WHITE_WALL, MAT.SmoothPlastic, solid("StoreWall"))
	BX(shell, 5.8, 0, -4, 6, 3.15, 3.8, WHITE_WALL, MAT.SmoothPlastic, solid("StoreWall"))
	BX(shell, -6, TY, 4.0, 6, 3.15, 4.09, CLAD, MAT.Metal, solid("StoreCladding"))
	BX(shell, -6.09, TY, -4.0, -6.0, 3.15, 4.09, CLAD, MAT.Metal, solid("StoreCladding"))
	BX(shell, 6.0, TY, -4.0, 6.09, 3.15, 4.09, CLAD, MAT.Metal, solid("StoreCladding"))
	BX(shell, -6.09, TY, 4.09, 6.09, 0.45, 4.19, STONE, MAT.Granite, solid("StoreBase"))
	BX(shell, -6.19, TY, -4.0, -6.09, 0.45, 4.19, STONE, MAT.Granite, solid("StoreBase"))
	BX(shell, 6.09, TY, -4.0, 6.19, 0.45, 4.19, STONE, MAT.Granite, solid("StoreBase"))
	-- 강 쪽 유리 커튼월: 문틀 x 1.8 ~ 3.6 (유효폭 1.8 m, 높이 2.3 m), 멀리언 1.5 m 간격
	BX(shell, -5.8, 0, -4.0, 1.74, 0.08, -3.8, FRAME_DARK, MAT.Metal, solid("StoreSill"))
	BX(shell, 3.66, 0, -4.0, 5.8, 0.08, -3.8, FRAME_DARK, MAT.Metal, solid("StoreSill"))
	BX(shell, 1.8, 0, -4.05, 3.6, 0.016, -3.75, SS, MAT.Metal, solid("DoorThreshold"))
	BX(shell, -5.8, 2.85, -4.0, 5.8, 3.15, -3.8, WHITE_WALL, MAT.SmoothPlastic, solid("StoreHeadBand"))
	BX(shell, -5.8, 0.08, -3.92, 1.77, 2.85, -3.88, GLASS_STORE, MAT.Glass, solid("StoreGlass", { transparency = 0.8 }))
	BX(shell, 3.63, 0.08, -3.92, 5.8, 2.85, -3.88, GLASS_STORE, MAT.Glass, solid("StoreGlass", { transparency = 0.8 }))
	BX(shell, 1.77, 2.35, -3.92, 3.63, 2.85, -3.88, GLASS_STORE, MAT.Glass, solid("StoreGlass", { transparency = 0.8 }))
	for _, x in { -4.28, -2.76, -1.24, 0.28, 4.7 } do
		BX(shell, x - 0.03, 0.08, -4.0, x + 0.03, 2.85, -3.8, FRAME_DARK, MAT.Metal, solid("Mullion"))
	end
	BX(shell, 1.74, 0, -4.0, 1.8, 2.85, -3.8, FRAME_DARK, MAT.Metal, solid("DoorJamb"))
	BX(shell, 3.6, 0, -4.0, 3.66, 2.85, -3.8, FRAME_DARK, MAT.Metal, solid("DoorJamb"))
	BX(shell, 1.8, 2.3, -4.0, 3.6, 2.35, -3.8, FRAME_DARK, MAT.Metal, solid("DoorHead"))
	-- 자동문: 문짝 2 (열린 상태 = 고정창 바깥으로 0.9 m 씩 밀려 있음). 태그 SeoulAutoDoor + ClosedOffset 속성(애니메이션용)
	BX(shell, 0.85, 2.3, -4.22, 4.55, 2.5, -4.0, FRAME_DARK, MAT.Metal, solid("AutoDoorHeader"))
	BX(shell, 2.6, 2.25, -4.18, 2.8, 2.3, -4.1, rgb(20, 20, 24), MAT.SmoothPlastic, opts("AutoDoorSensor"))
	local CS = game:GetService("CollectionService")
	for i, xs in { { 0.88, 1.8, 1 }, { 3.6, 4.52, -1 } } do
		local leaf = BX(shell, xs[1], 0.02, -4.13, xs[2], 2.3, -4.09, rgb(176, 200, 214), MAT.Glass, opts("AutoDoorLeaf", { transparency = 0.55 }))
		local stile = BX(shell, if i == 1 then xs[2] - 0.04 else xs[1], 0.02, -4.135, if i == 1 then xs[2] else xs[1] + 0.04, 2.3, -4.085, FRAME_DARK, MAT.Metal, opts("AutoDoorStile"))
		for _, p in { leaf, stile } do
			CS:AddTag(p, "SeoulAutoDoor")
			p:SetAttribute("ClosedOffset", Vector3.new(xs[3] * M(0.9), 0, 0)) -- 열린 위치 + 이 값 = 닫힌 위치 (월드)
		end
		if i == 1 then
			local st = BX(shell, 1.12, 1.12, -4.145, 1.56, 1.26, -4.13, rgb(230, 236, 240), MAT.SmoothPlastic, opts("AutoDoorSticker"))
			Kit.label(st, Enum.NormalId.Front, "자동문", { glow = true, color = rgb(30, 60, 120), pixelsPerStud = 80 })
		end
	end
	-- 지붕 슬래브 + 강 쪽 캐노피(1.6 m) + 띠 간판 + 라임 네온 라인 + 캐노피 다운라이트
	BX(shell, -6.3, 3.15, -5.6, 6.3, 3.45, 4.3, rgb(64, 68, 76), MAT.Metal, solid("StoreRoof"))
	BX(shell, -6.3, 3.05, -5.72, 6.3, 3.75, -5.6, rgb(238, 240, 242), MAT.SmoothPlastic, solid("StoreFascia"))
	BX(shell, -6.3, 3.05, 4.3, 6.3, 3.75, 4.42, rgb(238, 240, 242), MAT.SmoothPlastic, solid("StoreFascia"))
	BX(shell, -6.42, 3.05, -5.72, -6.3, 3.75, 4.42, rgb(238, 240, 242), MAT.SmoothPlastic, solid("StoreFascia"))
	BX(shell, 6.3, 3.05, -5.72, 6.42, 3.75, 4.42, rgb(238, 240, 242), MAT.SmoothPlastic, solid("StoreFascia"))
	BX(shell, -6.3, 3.0, -5.75, 6.3, 3.05, -5.63, BRAND2, MAT.Neon, glowOpts("StoreStripe", BRAND2))
	local s1 = BX(shell, -3.3, 3.12, -5.84, 3.3, 3.7, -5.72, BRAND, MAT.SmoothPlastic, opts("StoreSign"))
	Kit.label(s1, Enum.NormalId.Front, "편의점  ·  한강공원점  24", { glow = true, color = WHITE_LABEL, pixelsPerStud = 24 })
	local s2 = BX(shell, -2.6, 3.12, 4.42, 2.6, 3.7, 4.54, BRAND, MAT.SmoothPlastic, opts("StoreSign"))
	Kit.label(s2, Enum.NormalId.Back, "편의점  24시", { glow = true, color = WHITE_LABEL, pixelsPerStud = 24 })
	for i, x in { -3.6, 0.0, 2.7 } do
		local dl = CY(shell, x, -4.8, 3.11, 3.15, 0.18, LAMP_HEAD, MAT.Neon, glowOpts("CanopyLight"))
		if i == 3 then
			tryLight(dl, "SpotLight", { face = Enum.NormalId.Bottom, angle = 100, range = M(6), brightness = 1.5, color = P.LampWarm })
		end
	end
	-- 지붕 위 실외기 + 점검구 (전망대에서 내려다보임), 측벽 실외기
	BX(shell, 2.0, 3.45, 0.5, 3.2, 3.95, 1.6, rgb(200, 200, 196), MAT.Metal, opts("RoofAC"))
	BX(shell, -3.5, 3.45, 1.0, -2.7, 3.6, 1.8, rgb(150, 150, 146), MAT.Metal, opts("RoofHatch"))
	BX(shell, -6.75, TY, 0.6, -6.25, 0.72, 1.5, rgb(214, 214, 210), MAT.Metal, solid("ACUnit"))
	CH(shell, -6.76, 0.41, 1.05, 0.02, 0.46, false, rgb(60, 62, 66), MAT.Metal, opts("ACFan"))
	-- 자판기 2 (산책로 쪽 뒷벽, 1.83 x 1.0 x 0.8 m)
	for i, c in { rgb(170, 34, 40), rgb(36, 90, 160) } do
		local x0 = 1.4 + (i - 1) * 1.15
		BX(shell, x0, TY, 4.2, x0 + 1.0, 1.74, 4.99, c, MAT.SmoothPlastic, solid("Vending"))
		BX(shell, x0 + 0.12, 0.85, 4.99, x0 + 0.88, 1.6, 5.03, rgb(220, 226, 236), MAT.Neon, glowOpts("VendingGlow", rgb(180, 190, 200)))
		BX(shell, x0 + 0.2, 0.12, 4.99, x0 + 0.7, 0.32, 5.02, rgb(30, 30, 34), MAT.SmoothPlastic, opts("VendingSlot"))
	end
end

-- 테라스: 파라솔 테이블 5 세트, 줄조명(전선 + 전구), 분리수거함
local function storeTerrace(ter: Instance, TY: number)
	local cols = { rgb(196, 54, 46), rgb(236, 230, 214), rgb(44, 112, 168), rgb(70, 150, 90), rgb(236, 180, 50) }
	local sets = { { -6.2, -7.2 }, { -2.8, -7.2 }, { 6.6, -7.2 }, { -4.5, -9.7 }, { 5.0, -9.7 } }
	for i, s in sets do
		local cx, cz = s[1], s[2]
		CY(ter, cx, cz, TY, TY + 0.03, 0.45, rgb(60, 62, 66), MAT.Metal, opts("TableBase"))
		CY(ter, cx, cz, TY + 0.03, 0.72, 0.06, rgb(220, 220, 216), MAT.Metal, opts("TablePole"))
		CY(ter, cx, cz, 0.72, 0.75, 0.8, if i % 2 == 0 then rgb(236, 236, 230) else rgb(40, 110, 160), MAT.SmoothPlastic, solid("CafeTable"))
		CY(ter, cx, cz, 0.75, 2.35, 0.04, rgb(220, 220, 214), MAT.Metal, opts("ParasolPole"))
		Kit.ellipsoid(ter, at(cx, 2.2, cz), Vector3.new(M(2.4), M(0.45), M(2.4)), cols[i], MAT.Fabric, opts("Parasol"))
		local chairC = if i % 2 == 0 then rgb(238, 238, 232) else rgb(40, 110, 160)
		for k = 0, 2 do
			local a = math.rad(irng:NextNumber(-20, 20) + k * 120 + 30)
			local base = at(cx + math.cos(a) * 0.72, TY, cz + math.sin(a) * 0.72).Position
			local cf = CFrame.lookAt(base, Vector3.new(at(cx, TY, cz).Position.X, base.Y, at(cx, TY, cz).Position.Z))
			Kit.box(ter, cf * CFrame.new(0, M(0.43 - 0.02), 0), Vector3.new(M(0.42), M(0.04), M(0.42)), chairC, MAT.SmoothPlastic, solid("ChairSeat"))
			Kit.box(ter, cf * CFrame.new(0, M(0.41), M(0.195)), Vector3.new(M(0.42), M(0.82), M(0.03)), chairC, MAT.SmoothPlastic, opts("ChairBack"))
			Kit.box(ter, cf * CFrame.new(0, M(0.2), -M(0.18)), Vector3.new(M(0.38), M(0.4), M(0.03)), chairC, MAT.SmoothPlastic, opts("ChairLegs"))
		end
	end
	-- 줄조명: 강 쪽 기둥 3 (3.2 m) ↔ 캐노피 끝 2 점, W 자 + 앞줄. 처짐 0.35 m, 전구 1 m 간격
	local poles = { Vector3.new(-7.6, 3.1, -10.7), Vector3.new(0.6, 3.1, -10.7), Vector3.new(8.6, 3.1, -10.7) }
	for _, p in poles do
		CY(ter, p.X, p.Z, TY, 3.2, 0.08, rgb(52, 56, 62), MAT.Metal, solid("StringPole"))
		CY(ter, p.X, p.Z, TY, TY + 0.3, 0.26, rgb(110, 110, 108), MAT.Concrete, opts("PoleFoot"))
	end
	local A1, A2 = Vector3.new(-4.6, 3.0, -5.62), Vector3.new(4.4, 3.0, -5.62)
	local spans = { { poles[1], A1 }, { A1, poles[2] }, { poles[2], A2 }, { A2, poles[3] }, { poles[1], poles[2] }, { poles[2], poles[3] } }
	local lit = 0
	for si, sp in spans do
		local a, b = sp[1], sp[2]
		local sag = 0.35
		local function pt(t: number): Vector3
			return a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		end
		for k = 0, 2 do
			BAR(ter, pt(k / 3), pt((k + 1) / 3), 0.012, rgb(28, 28, 30), MAT.SmoothPlastic, opts("Wire"))
		end
		local nb = math.max(3, math.floor((b - a).Magnitude / 1.0 + 0.5))
		for k = 0, nb - 1 do
			local q = pt((k + 0.5) / nb) - Vector3.new(0, 0.05, 0)
			local bulb = Kit.ball(ter, at(q.X, q.Y, q.Z).Position, M(0.1), rgb(255, 202, 124), MAT.Neon, glowOpts("StringBulb", rgb(230, 222, 204)))
			if (si == 1 or si == 4) and k == math.floor(nb / 2) and lit < 2 then
				if tryLight(bulb, "PointLight", { color = rgb(255, 196, 130), brightness = 0.9, range = M(5) }) then
					lit += 1
				end
			end
		end
	end
	-- 분리수거함 4 (일반 / 캔·병 / 플라스틱 / 종이) + 안내판
	BX(ter, 6.9, TY, -4.15, 8.7, 1.25, -4.1, rgb(60, 66, 74), MAT.Metal, solid("RecycleBoard"))
	local rh = BX(ter, 6.9, 1.0, -4.17, 8.7, 1.25, -4.15, BRAND, MAT.SmoothPlastic, opts("RecycleHeader"))
	Kit.label(rh, Enum.NormalId.Front, "분리수거  RECYCLE", { glow = true, color = WHITE_LABEL, pixelsPerStud = 60 })
	local bins = { { "일반", rgb(120, 124, 130) }, { "캔·병", rgb(40, 100, 180) }, { "플라스틱", rgb(230, 140, 40) }, { "종이", rgb(60, 140, 80) } }
	for k, bn in bins do
		local x0 = 6.95 + (k - 1) * 0.44
		local body = BX(ter, x0, TY, -4.58, x0 + 0.4, 0.8, -4.18, rgb(228, 230, 232), MAT.SmoothPlastic, solid("RecycleBin"))
		Kit.label(body, Enum.NormalId.Front, bn[1] :: string, { glow = true, color = bn[2] :: Color3, pixelsPerStud = 60 })
		BX(ter, x0 - 0.01, 0.8, -4.59, x0 + 0.41, 0.85, -4.17, bn[2] :: Color3, MAT.SmoothPlastic, opts("RecycleLid"))
	end
end

-- 공중화장실 (10 x 6 m 노출콘크리트 파빌리온, 천장고 2.6 m). 입구 2 (+Z, 산책로 쪽, 폭 1.0 m) + 눈가림벽
local function buildRestroom(parent: Instance, rx: number, rz: number, FY: number)
	ORG = CFrame.new(rx, FY, rz)
	local sh = Kit.group(parent, "Restroom")
	local rin = Kit.group(parent, "RestroomInterior", Config.InteriorStreaming)
	local CONC = rgb(196, 194, 188)
	local TILE_W = rgb(236, 238, 236)
	local H = 2.9
	BX(sh, -5, -0.63, -3, 5, 0, 3, rgb(132, 136, 140), MAT.SmoothPlastic, solid("RestroomFloor"))
	BX(sh, -5, 0, -3, 5, 2.2, -2.8, CONC, MAT.Concrete, solid("RestroomWall"))
	BX(sh, -5, 2.2, -3, 5, 2.55, -2.8, rgb(236, 228, 204), MAT.Neon, glowSolid("RestroomClerestory", rgb(176, 184, 190)))
	BX(sh, -5, 2.55, -3, 5, H, -2.8, CONC, MAT.Concrete, solid("RestroomWall"))
	BX(sh, -5, 0, -2.8, -4.8, H, 2.8, CONC, MAT.Concrete, solid("RestroomWall"))
	BX(sh, 4.8, 0, -2.8, 5, H, 2.8, CONC, MAT.Concrete, solid("RestroomWall"))
	BX(sh, -5, 0, 2.8, -1.45, H, 3, CONC, MAT.Concrete, solid("RestroomWall"))
	BX(sh, -0.45, 0, 2.8, 0.45, H, 3, CONC, MAT.Concrete, solid("RestroomWall"))
	BX(sh, 1.45, 0, 2.8, 5, H, 3, CONC, MAT.Concrete, solid("RestroomWall"))
	BX(sh, -1.45, 2.1, 2.8, -0.45, H, 3, CONC, MAT.Concrete, solid("RestroomWall"))
	BX(sh, 0.45, 2.1, 2.8, 1.45, H, 3, CONC, MAT.Concrete, solid("RestroomWall"))
	-- 지붕(입구 쪽 1.3 m 캐노피) + 목재 처마 반자 + 다운라이트
	BX(sh, -5.5, H, -3.5, 5.5, H + 0.25, 4.3, rgb(170, 168, 162), MAT.Concrete, solid("RestroomRoof"))
	BX(sh, -5.5, H - 0.03, 3.0, 5.5, H, 4.3, rgb(150, 112, 76), MAT.Wood, opts("RestroomSoffit"))
	for i, x in { -0.95, 0.95 } do
		local dl = CY(sh, x, 3.65, H - 0.06, H - 0.03, 0.16, LAMP_HEAD, MAT.Neon, glowOpts("RestroomDownlight"))
		if i == 1 then
			tryLight(dl, "SpotLight", { face = Enum.NormalId.Bottom, angle = 110, range = M(5), brightness = 1.3, color = P.LampWarm })
		end
	end
	-- 입구 면 목재 루버 패널 + 간판 + 남/여 표지 + 문틀
	BX(sh, -4.7, 0.25, 3.0, -1.75, 2.5, 3.09, rgb(150, 110, 74), MAT.Wood, solid("WoodClad"))
	BX(sh, 1.75, 0.25, 3.0, 4.7, 2.5, 3.09, rgb(150, 110, 74), MAT.Wood, solid("WoodClad"))
	local rs = BX(sh, -0.42, 2.25, 3.0, 0.42, 2.72, 3.09, rgb(40, 44, 50), MAT.SmoothPlastic, opts("RestroomSign"))
	Kit.label(rs, Enum.NormalId.Back, "화장실", { glow = true, color = WHITE_LABEL, pixelsPerStud = 40 })
	local fs = BX(sh, -2.4, 1.45, 3.09, -1.8, 2.0, 3.13, rgb(206, 60, 72), MAT.SmoothPlastic, opts("WomenSign"))
	Kit.label(fs, Enum.NormalId.Back, "여자", { glow = true, color = WHITE_LABEL, pixelsPerStud = 60 })
	local ms = BX(sh, 1.8, 1.45, 3.09, 2.4, 2.0, 3.13, rgb(50, 110, 200), MAT.SmoothPlastic, opts("MenSign"))
	Kit.label(ms, Enum.NormalId.Back, "남자", { glow = true, color = WHITE_LABEL, pixelsPerStud = 60 })
	for _, d in { { -1.45, -0.45 }, { 0.45, 1.45 } } do
		BX(sh, d[1] - 0.06, 0, 2.76, d[1] + 0.02, 2.16, 3.05, SS, MAT.Metal, solid("DoorFrame"))
		BX(sh, d[2] - 0.02, 0, 2.76, d[2] + 0.06, 2.16, 3.05, SS, MAT.Metal, solid("DoorFrame"))
		BX(sh, d[1] - 0.06, 2.08, 2.76, d[2] + 0.06, 2.16, 3.05, SS, MAT.Metal, solid("DoorFrame"))
	end

	-- 실내: 천장 + 바닥 줄눈 + 가운데 칸막이벽
	BX(rin, -4.8, 2.6, -2.8, 4.8, 2.64, 2.8, rgb(242, 242, 238), MAT.SmoothPlastic, solid("RestroomCeiling"))
	for k = 1, 15 do
		local x = -4.8 + 0.6 * k
		BX(rin, x - 0.0075, -0.01, -2.8, x + 0.0075, 0.016, 2.8, rgb(176, 180, 184), MAT.SmoothPlastic, opts("Grout", { shadow = false }))
	end
	for k = 1, 9 do
		local z = -2.8 + 0.6 * k
		BX(rin, -4.8, -0.01, z - 0.0075, 4.8, 0.016, z + 0.0075, rgb(176, 180, 184), MAT.SmoothPlastic, opts("Grout", { shadow = false }))
	end
	BX(rin, -0.1, 0, -2.8, 0.1, H, 2.8, TILE_W, TILE_MAT, solid("RestroomPartition"))

	-- 방 하나 (sg = -1 여자 / +1 남자, u = |x| : 0.1 칸막이 ~ 4.8 외벽)
	local function room(sg: number)
		local function X(u: number): number
			return sg * u
		end
		local PANEL = if sg < 0 then rgb(214, 186, 178) else rgb(160, 182, 204)
		local DOOR = PANEL:Lerp(rgb(255, 255, 255), 0.25)
		-- 벽 타일(1.5 m)
		BX(rin, X(4.78), 0, -2.8, X(4.8), 1.5, 2.8, TILE_W, TILE_MAT, opts("Wainscot"))
		BX(rin, X(0.12), 0, -2.8, X(4.78), 1.5, -2.78, TILE_W, TILE_MAT, opts("Wainscot"))
		BX(rin, X(1.45), 0, 2.78, X(4.78), 1.5, 2.8, TILE_W, TILE_MAT, opts("Wainscot"))
		-- 눈가림벽 (입구에서 안이 보이지 않게)
		BX(rin, X(0.1), 0, 1.4, X(2.3), 2.1, 1.55, TILE_W, TILE_MAT, solid("PrivacyScreen"))
		-- 세면대 (상판 0.86 m, 볼 세면기 2) + 거울 + 손 건조기 + 휴지통
		BX(rin, X(2.55), 0.82, 2.25, X(4.65), 0.86, 2.78, rgb(64, 66, 70), MAT.Granite, solid("Vanity"))
		BX(rin, X(2.55), 0.62, 2.27, X(4.65), 0.82, 2.78, rgb(64, 66, 70), MAT.Granite, solid("VanityApron"))
		for _, u in { 3.1, 4.1 } do
			CY(rin, X(u), 2.5, 0.86, 0.98, 0.4, rgb(246, 246, 244), MAT.SmoothPlastic, opts("Basin"))
			CY(rin, X(u), 2.72, 0.86, 1.06, 0.03, SS, MAT.Metal, opts("Faucet"))
			BX(rin, X(u) - 0.015, 1.03, 2.58, X(u) + 0.015, 1.06, 2.72, SS, MAT.Metal, opts("Spout"))
		end
		BX(rin, X(2.6), 1.0, 2.755, X(4.6), 1.85, 2.775, rgb(196, 206, 214), MAT.Glass, opts("Mirror", { reflectance = 0.45 }))
		BX(rin, X(1.6), 1.05, 2.6, X(1.95), 1.35, 2.78, rgb(220, 222, 226), MAT.SmoothPlastic, solid("HandDryer"))
		CY(rin, X(2.35), 2.5, 0, 0.6, 0.32, rgb(200, 200, 196), MAT.Metal, solid("RestroomBin"))
		-- 대변기 칸 (폭 1.0 m, 깊이 1.5 m, 칸막이 높이 0.15 ~ 2.0 m). 가운데 칸은 문이 열려 있음
		local stalls = if sg < 0 then { { 3.8, 4.8 }, { 2.8, 3.8 }, { 1.8, 2.8 } } else { { 3.8, 4.8 }, { 2.8, 3.8 } }
		for si, st in stalls do
			local ua, ub = st[1], st[2]
			BX(rin, X(ua - 0.0125), 0.15, -2.78, X(ua + 0.0125), 2.0, -1.3, PANEL, MAT.SmoothPlastic, solid("StallPanel"))
			BX(rin, X(ub - 0.18), 0.15, -1.32, X(ub), 2.0, -1.28, PANEL, MAT.SmoothPlastic, solid("StallPilaster"))
			local w = (ub - 0.2) - (ua + 0.02)
			if si == 2 then
				local hinge = at(X(ua + 0.02), 1.075, -1.3) * CFrame.Angles(0, math.rad(sg * 80), 0)
				Kit.box(rin, hinge * CFrame.new(M(sg * w / 2), 0, 0), Vector3.new(M(w), M(1.85), M(0.03)), DOOR, MAT.SmoothPlastic, solid("StallDoor"))
			else
				BX(rin, X(ua + 0.02), 0.15, -1.315, X(ub - 0.2), 2.0, -1.285, DOOR, MAT.SmoothPlastic, solid("StallDoor"))
				BX(rin, X(ub - 0.32), 1.0, -1.285, X(ub - 0.26), 1.08, -1.265, rgb(220, 60, 50), MAT.SmoothPlastic, opts("StallIndicator"))
			end
			local uc = (ua + ub) / 2
			BX(rin, X(uc - 0.2), 0.42, -2.78, X(uc + 0.2), 0.78, -2.6, rgb(248, 248, 246), MAT.SmoothPlastic, solid("ToiletTank"))
			CY(rin, X(uc), -2.36, 0, 0.38, 0.32, rgb(248, 248, 246), MAT.SmoothPlastic, solid("ToiletBowl"))
			CY(rin, X(uc), -2.38, 0.38, 0.42, 0.4, rgb(240, 240, 238), MAT.SmoothPlastic, opts("ToiletSeat"))
			BX(rin, X(ua + 0.0125), 0.66, -2.05, X(ua + 0.1), 0.76, -1.88, SS, MAT.Metal, opts("PaperHolder"))
		end
		if sg < 0 then
			-- 청소도구함 (칸 줄 끝)
			BX(rin, X(0.1), 0.0, -1.32, X(0.3), 2.0, -1.28, PANEL, MAT.SmoothPlastic, solid("ClosetFront"))
			BX(rin, X(1.2), 0.0, -1.32, X(1.8), 2.0, -1.28, PANEL, MAT.SmoothPlastic, solid("ClosetFront"))
			local cd = BX(rin, X(0.3), 0.02, -1.315, X(1.2), 2.0, -1.285, DOOR, MAT.SmoothPlastic, solid("ClosetDoor"))
			Kit.label(cd, Enum.NormalId.Back, "청소도구함", { glow = false, color = rgb(90, 70, 70), pixelsPerStud = 40 })
		else
			-- 소변기 3 + 칸막이 2
			for _, uc in { 0.75, 1.45, 2.15 } do
				BX(rin, X(uc - 0.18), 0.4, -2.78, X(uc + 0.18), 1.05, -2.48, rgb(248, 248, 246), MAT.SmoothPlastic, solid("Urinal"))
				BX(rin, X(uc - 0.12), 0.5, -2.48, X(uc + 0.12), 0.94, -2.465, rgb(222, 226, 230), MAT.SmoothPlastic, opts("UrinalBowl"))
				CY(rin, X(uc), -2.74, 1.05, 1.3, 0.04, SS, MAT.Metal, opts("FlushValve"))
			end
			for _, u in { 1.1, 1.8 } do
				BX(rin, X(u - 0.01), 0.6, -2.78, X(u + 0.01), 1.5, -2.35, PANEL, MAT.SmoothPlastic, opts("UrinalDivider"))
			end
		end
		-- 천장 조명 패널 + 실광원
		local lp = BX(rin, X(1.2), 2.56, -0.5, X(3.8), 2.6, 0.5, LED_COOL, MAT.Neon, glowOpts("RestroomCeilingLight", LED_DAY))
		tryLight(lp, "PointLight", { color = LED_COOL, brightness = 1.0, range = M(5) })
	end
	room(-1)
	room(1)
end

-- 공공자전거 대여소 (자전거도로 옆 둔치): 거치대 9 + 자전거 5 + 키오스크 + 안내판. 로컬 원점 = 패드 중심, -Z = 강(자전거도로) 쪽
local function buildBikeStation(parent: Instance, bx: number, bz: number, top: number)
	ORG = CFrame.new(bx, top, bz)
	local bk = Kit.group(parent, "BikeStation")
	local GREEN = rgb(70, 170, 90)
	local FRAME_W = rgb(232, 236, 236)
	BX(bk, -5.4, -0.36, -2.7, 5.4, 0, 2.7, rgb(150, 150, 146), MAT.Pavement, { name = "BikePad", shadow = false })
	BX(bk, -4.4, 0, -1.55, 3.6, 0.08, -1.25, rgb(120, 124, 130), MAT.Concrete, solid("DockBase"))
	local bikesAt = { [0] = true, [1] = true, [3] = true, [4] = true, [6] = true }
	for i = 0, 8 do
		local x = -4.0 + i * 0.9
		BX(bk, x - 0.06, 0, -1.48, x + 0.06, 0.62, -1.32, FRAME_W, MAT.Metal, solid("DockPost"))
		BX(bk, x - 0.09, 0.45, -1.32, x + 0.09, 0.66, -1.12, rgb(54, 60, 66), MAT.SmoothPlastic, opts("DockLock"))
		BX(bk, x - 0.03, 0.6, -1.12, x + 0.03, 0.63, -1.105, if bikesAt[i] then rgb(80, 255, 120) else rgb(255, 170, 60), MAT.Neon, glowOpts("DockLed", rgb(60, 120, 70)))
		if bikesAt[i] then
			-- 자전거 (바퀴 Ø 0.6 m, 축거 1.05 m, 스텝스루 프레임, 앞 바구니): 앞바퀴가 거치대에 물림
			local zf, zr = -0.92, 0.13
			for _, zw in { zf, zr } do
				CH(bk, x, 0.3, zw, 0.045, 0.6, false, rgb(24, 24, 26), MAT.SmoothPlastic, opts("BikeTire"))
				CH(bk, x, 0.3, zw, 0.075, 0.44, false, rgb(196, 200, 206), MAT.Metal, opts("BikeRim", { transparency = 0.45 }))
			end
			local Hd, BB, S, Rr, Fr = Vector3.new(x, 0.86, zf + 0.15), Vector3.new(x, 0.3, zf + 0.55), Vector3.new(x, 0.84, zf + 0.73), Vector3.new(x, 0.3, zr), Vector3.new(x, 0.3, zf)
			BAR(bk, Hd, BB, 0.05, FRAME_W, MAT.Metal, opts("BikeFrame"))
			BAR(bk, BB, S, 0.045, FRAME_W, MAT.Metal, opts("BikeFrame"))
			BAR(bk, BB, Rr, 0.035, FRAME_W, MAT.Metal, opts("BikeFrame"))
			BAR(bk, Hd, Fr, 0.035, FRAME_W, MAT.Metal, opts("BikeFork"))
			BAR(bk, Hd, Vector3.new(x, 1.0, zf + 0.1), 0.03, rgb(40, 40, 44), MAT.Metal, opts("BikeStem"))
			CH(bk, x, 1.0, zf + 0.1, 0.56, 0.03, false, rgb(30, 30, 34), MAT.SmoothPlastic, opts("BikeBar"))
			BX(bk, x - 0.08, 0.86, zf + 0.65, x + 0.08, 0.92, zf + 0.89, rgb(30, 30, 34), MAT.SmoothPlastic, opts("BikeSaddle"))
			BX(bk, x - 0.17, 0.74, zf - 0.28, x + 0.17, 0.96, zf - 0.02, rgb(60, 64, 70), MAT.Metal, opts("BikeBasket", { transparency = 0.3 }))
			BX(bk, x + 0.04, 0.22, zf + 0.55, x + 0.07, 0.38, zr, GREEN, MAT.SmoothPlastic, opts("BikeChainGuard"))
		end
	end
	-- 키오스크 (QR / 카드) + 안내판
	BX(bk, 4.15, 0, -1.6, 4.65, 1.55, -1.25, FRAME_W, MAT.SmoothPlastic, solid("BikeKiosk"))
	local kt = BX(bk, 4.15, 1.55, -1.6, 4.65, 1.75, -1.25, GREEN, MAT.SmoothPlastic, opts("BikeKioskTop"))
	Kit.label(kt, Enum.NormalId.Back, "공공자전거", { glow = true, color = WHITE_LABEL, pixelsPerStud = 60 })
	local scr = BX(bk, 4.22, 0.95, -1.25, 4.58, 1.35, -1.235, rgb(150, 220, 255), MAT.Neon, glowOpts("BikeKioskScreen", rgb(40, 50, 60)))
	tryLight(scr, "PointLight", { color = rgb(190, 230, 255), brightness = 0.8, range = M(4) })
	BX(bk, 4.3, 0.75, -1.25, 4.5, 0.85, -1.22, rgb(24, 24, 28), MAT.SmoothPlastic, opts("CardReader"))
	CY(bk, -5.25, -1.4, 0, 1.9, 0.06, rgb(120, 124, 130), MAT.Metal, solid("MapPost"))
	CY(bk, -4.55, -1.4, 0, 1.9, 0.06, rgb(120, 124, 130), MAT.Metal, solid("MapPost"))
	local mp = BX(bk, -5.35, 0.95, -1.45, -4.45, 1.9, -1.38, GREEN, MAT.SmoothPlastic, opts("BikeMapBoard"))
	Kit.label(mp, Enum.NormalId.Back, "공공자전거 대여소\n한강공원 502번\nQR 대여 · 1시간 1,000원", { glow = true, color = WHITE_LABEL, pixelsPerStud = 60 })
end

local function buildKiosk(parent: Instance, rng: Random, mainPts: { Vector2 })
	local kx = KIOSK_X
	local pz = zOnPath(mainPts, kx)
	local kz = pz - MAIN_W / 2 - M(2.2) - M(4) -- 매장 중심 (뒷벽 바깥면이 메인 산책로 2.2 m 앞)
	local FY = PLAZA_TOP + 0.3 -- 매장 바닥 윗면 (테라스 윗면 = PLAZA_TOP)
	local TY = -0.3 * Config.METERS_PER_STUD -- 테라스 윗면 (로컬 m)
	local zEdge = (pz - MAIN_W / 2 + 0.6 - kz) * Config.METERS_PER_STUD -- 메인 산책로 가장자리까지 (로컬 m)
	ORG = CFrame.new(kx, FY, kz)
	local store = Kit.group(parent, "ConvenienceStore")
	local ter = Kit.group(store, "Terrace")
	BX(ter, -8, TY - 0.36, -11, 9, TY, zEdge, PAVE_C, MAT.Pavement, { name = "StoreTerrace", shadow = false })
	storeShell(Kit.group(store, "Shell"), TY)
	storeInterior(Kit.group(store, "Interior", Config.InteriorStreaming))
	ORG = CFrame.new(kx, FY, kz)
	storeTerrace(ter, TY)
	local tx0, tx1 = kx - M(8), kx + M(9)
	local tz0, tz1 = kz - M(11), pz - MAIN_W / 2 + 0.6
	Kit.reserve(tx0, tz0, tx1, tz1, "ParkStore")
	markRect(tx0 - M(1), tz0 - M(1), tx1 + M(1), tz1, 2)

	-- 화장실 (매장 서쪽 9 m): 입구 앞 포장 마당은 테라스와 이어짐
	local rx = kx - M(6) - M(9) - M(5)
	local rpz = zOnPath(mainPts, rx)
	local rz = rpz - MAIN_W / 2 - M(2.5) - M(3)
	local ax0 = rx - M(5.6)
	local az0, az1 = rz - M(3.6), rpz - MAIN_W / 2 + 0.6
	Kit.box(store, CFrame.new((ax0 + tx0) / 2, PLAZA_TOP - 0.6, (az0 + az1) / 2), Vector3.new(tx0 - ax0, 1.2, az1 - az0), PAVE_C, MAT.Pavement, { name = "RestroomApron", shadow = false })
	buildRestroom(Kit.group(store, "PublicRestroom"), rx, rz, FY)
	Kit.reserve(ax0, az0, tx0, az1, "ParkRestroom")
	markRect(ax0 - M(1), az0 - M(1), tx0, az1, 2)

	-- 강 쪽 연결로 (테라스 → 피크닉장 → 강변 산책로 → 자전거도로, 폭 3 m) + 테라스 조망 축(나무 없음)
	local z0p = N.WaterEdge + M(15.2) -- 750: Riverside 소유 끝 너머
	Kit.box(store, CFrame.new(kx, CONN_TOP - 0.4, (z0p + tz0) / 2), Vector3.new(CONN_W, 0.8, tz0 - z0p), PAVE_C, MAT.Pavement, { name = "StorePath", shadow = false })
	markSeg(kx, z0p, kx, tz0, CONN_W / 2 + 1.5, 2)
	markRect(kx - 40, EDGE_Z + EDGE_W / 2 + M(1.8), kx + 40, tz0, 2)
	Kit.reserve(kx - CONN_W / 2, z0p, kx + CONN_W / 2, tz0, "ParkStorePath")

	-- 공공자전거 대여소 (연결로 서쪽, 자전거도로와 강변 산책로 사이 둔치)
	local bpx = kx - CONN_W / 2 - M(5.4)
	local bpz = z0p + 0.5 + M(2.7)
	buildBikeStation(Kit.group(store, "BikeStation"), bpx, bpz, CONN_TOP)
	Kit.reserve(bpx - M(5.4), bpz - M(2.7), bpx + M(5.4), bpz + M(2.7), "ParkBikeStation")
	markRect(bpx - M(5.4), bpz - M(2.7), bpx + M(5.4), bpz + M(2.7), 2)

	-- 피크닉장 (매점 강 쪽 잔디밭): 테이블 세트 + 파라솔 + 돗자리
	local cols = { rgb(196, 54, 46), rgb(236, 230, 214), rgb(44, 112, 168) }
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
	local mats = { { -543, 840, rgb(214, 120, 60) }, { -563, 877, rgb(70, 140, 190) }, { -474, 842, rgb(220, 196, 90) } }
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
-- 1b) 전망대 디테일: "잠실 야경" 안내판(데크 앞 난간), 계단 입구 표지 + 10 m 마다 높이 표시(계단탑 안),
--     엘리베이터 호출 버튼 받침 기둥 + 안내 토템(지상) / 계단 안내판(데크)
------------------------------------------------------------------------------------------------------
local function buildDeckDetail(parent: Instance)
	local cx, cz = DC.X, DC.Z + DECK_DZ
	local hw, hd = DECK_W / 2, DECK_D / 2
	local z0, z1 = cz - hd, cz + hd
	local sx, sz = TOWER.X, TOWER.Y
	local NAVY = rgb(24, 30, 44)
	local GOLD = rgb(255, 214, 150)

	-- 1) 잠실 야경 안내판: 1.3 x 0.75 m 판을 35° 기울임(중심 높이 1.0 m). 강(-Z)을 향해 선 사람이 내려다보는 약도
	local bx, bz = cx + M(3.3), z0 + M(0.85)
	local TH = 0.05
	local bcf = CFrame.new(bx, DY + M(1.0), bz) * CFrame.Angles(math.rad(35), 0, 0)
	for _, dx in { -0.5, 0.5 } do
		Kit.vcyl(parent, Vector3.new(bx + M(dx), DY + M(0.47), bz + M(0.05)), M(0.94), M(0.06), STEEL, MAT.Metal, opts("InfoBoardLeg", { collide = true }))
	end
	Kit.box(parent, bcf, Vector3.new(M(1.3), M(TH), M(0.75)), NAVY, MAT.SmoothPlastic, { name = "InfoBoard" })
	-- 판 위 요소: u = 판 가로(m), v = 판 세로(m, + = 보는 사람 쪽 아래), 판 면에서 2 cm 돋움
	local function bp(u0: number, v0: number, u1: number, v1: number, color: Color3, name: string, glow: boolean, yaw: number?): BasePart
		local cf = bcf * CFrame.new(M((u0 + u1) / 2), M(TH / 2 + 0.01), M((v0 + v1) / 2))
		local size = Vector3.new(M(math.abs(u1 - u0)), M(0.02), M(math.abs(v1 - v0)))
		if yaw then -- 비스듬한 막대(다리): 강·글자판보다 1.5 cm 더 돋움
			local du, dv = u1 - u0, v1 - v0
			cf = bcf * CFrame.new(M((u0 + u1) / 2), M(TH / 2 + 0.0175), M((v0 + v1) / 2)) * CFrame.Angles(0, math.atan2(-dv, du), 0)
			size = Vector3.new(M(math.sqrt(du * du + dv * dv)), M(0.035), M(yaw))
		end
		return Kit.box(parent, cf, size, color, if glow then MAT.Neon else MAT.SmoothPlastic, if glow then glowOpts(name, color) else opts(name))
	end
	local function lbl(u0: number, v0: number, u1: number, v1: number, text: string, color: Color3?)
		local p = bp(u0, v0, u1, v1, rgb(18, 22, 32), "InfoLabel", false)
		Kit.label(p, Enum.NormalId.Top, text, { glow = true, color = color or rgb(236, 230, 214), pixelsPerStud = 90 })
	end
	lbl(-0.6, -0.365, 0.6, -0.285, "잠실 야경  ·  JAMSIL NIGHT VIEW", GOLD)
	local river = bp(-0.62, 0.1, 0.62, 0.17, rgb(36, 74, 122), "InfoRiver", false)
	Kit.label(river, Enum.NormalId.Top, "한  강", { glow = true, color = rgb(170, 210, 250), pixelsPerStud = 90 })
	bp(-0.62, 0.085, 0.62, 0.1, rgb(214, 160, 90), "InfoBank", true)
	for _, b in { { -0.58, -0.5, 0.0 }, { -0.48, -0.41, -0.06 }, { -0.39, -0.33, 0.02 }, { 0.06, 0.13, -0.08 }, { 0.15, 0.22, -0.04 }, { 0.25, 0.31, -0.1 }, { 0.34, 0.4, -0.02 } } do
		bp(b[1], b[3], b[2], 0.085, rgb(120, 140, 170), "InfoBuilding", true)
	end
	bp(-0.12, 0.05, -0.02, 0.085, rgb(70, 130, 220), "InfoMall", true)
	bp(-0.2, -0.2, -0.16, 0.085, GOLD, "InfoTower", true)
	bp(-0.187, -0.255, -0.173, -0.2, GOLD, "InfoSpire", true)
	bp(0.62, 0.3, 0.36, 0.1, rgb(214, 160, 90), "InfoBridge", true, 0.012)
	lbl(-0.14, -0.255, 0.16, -0.195, "롯데월드타워 555 m")
	lbl(0.05, -0.165, 0.45, -0.11, "잠실 고층 업무지구")
	lbl(-0.36, 0.2, -0.04, 0.26, "롯데월드몰")
	lbl(0.22, 0.215, 0.46, 0.275, "잠실대교")
	lbl(-0.6, 0.29, 0.6, 0.355, "현재 위치: 한강공원 전망대 (높이 60 m) · 앞쪽 강변 = 올림픽대로", rgb(200, 206, 216))
	local hood = Kit.box(parent, bcf * CFrame.new(0, M(TH / 2 + 0.07), -M(0.39)), Vector3.new(M(1.2), M(0.03), M(0.05)), LAMP_HEAD, MAT.Neon, glowOpts("InfoBoardLamp"))
	tryLight(hood, "PointLight", { color = P.LampWarm, brightness = 0.8, range = M(2.5) })

	-- 2) 계단탑: 첫 단 앞 입구 표지(조명) + 10 m 마다 높이 표시(엘리베이터 샤프트 유리 바깥면)
	local rise = DY - PLAZA_TOP
	local n = math.ceil(rise / RISER)
	local riser = rise / n
	local rc = (STAIR_RIN + STAIR_ROUT) / 2
	local perTurn = math.floor(2 * math.pi * rc / TREAD + 0.5)
	local dTheta = 2 * math.pi / perTurn
	local thLast = -math.pi / 2 - math.asin((LAND_W / 2) / rc) - dTheta * 0.5
	local function theta(k: number): number
		return thLast - (n - 1 - k) * dTheta
	end
	local t1 = theta(1) - math.rad(22)
	local out = Vector3.new(math.cos(t1), 0, math.sin(t1))
	local pp = Vector3.new(sx, PLAZA_TOP, sz) + out * (STAIR_ROUT + M(2.4))
	local pcf = CFrame.lookAt(pp + Vector3.new(0, M(1.1), 0), pp + Vector3.new(0, M(1.1), 0) + out)
	Kit.box(parent, pcf, Vector3.new(M(0.7), M(2.2), M(0.14)), rgb(40, 44, 52), MAT.Metal, { name = "StairPylon" })
	local face = Kit.box(parent, pcf * CFrame.new(0, M(0.2), -M(0.08)), Vector3.new(M(0.6), M(1.3), M(0.02)), rgb(26, 30, 38), MAT.SmoothPlastic, opts("StairPylonFace"))
	Kit.label(face, Enum.NormalId.Front, string.format("전망대 계단\n60 m\n%d계단 · 약 7분\n\n엘리베이터는\n탑 뒤편", n - 1), { glow = true, color = GOLD, pixelsPerStud = 50 })
	local strip = Kit.box(parent, pcf * CFrame.new(0, M(0.95), -M(0.08)), Vector3.new(M(0.6), M(0.06), M(0.02)), LAMP_HEAD, MAT.Neon, glowOpts("StairPylonLed"))
	tryLight(strip, "PointLight", { color = P.LampWarm, brightness = 1.0, range = M(5) })
	for _, hm in { 10, 20, 30, 40, 50 } do
		local k = math.floor(M(hm) / riser + 0.5)
		if k >= 1 and k <= n - 1 then
			local th = theta(k)
			local o2 = Vector3.new(math.cos(th), 0, math.sin(th))
			local p = Vector3.new(sx, PLAZA_TOP + k * riser + M(1.45), sz) + o2 * (SHAFT_R + 0.12)
			local plate = Kit.box(parent, CFrame.lookAt(p, p + o2), Vector3.new(M(0.5), M(0.24), 0.12), rgb(30, 34, 42), MAT.SmoothPlastic, opts("HeightMark"))
			Kit.label(plate, Enum.NormalId.Front, string.format("%d m", hm), { glow = true, color = GOLD, pixelsPerStud = 60 })
		end
	end

	-- 3) 엘리베이터 호출 버튼 받침 기둥(버튼 위치·크기는 buildDeck 그대로) + 지상 안내 토템 + 데크 계단 안내판
	local downAt = Vector3.new(sx, PLAZA_TOP + M(1.1), sz + STAIR_ROUT + M(1.2))
	local upAt = Vector3.new(cx + hw - M(1.6), DY + M(1.1), z1 - M(1.4))
	for _, b in { { downAt, PLAZA_TOP }, { upAt, DY } } do
		local p, base = b[1] :: Vector3, b[2] :: number
		local top = p.Y - M(0.3)
		Kit.box(parent, CFrame.new(p.X, (base + top) / 2, p.Z), Vector3.new(M(0.22), top - base, M(0.22)), SS, MAT.Metal, solid("ElevatorCallPost"))
	end
	local tx, tz = sx + M(1.1), downAt.Z
	Kit.box(parent, CFrame.new(tx, PLAZA_TOP + M(1.05), tz), Vector3.new(M(0.55), M(2.1), M(0.12)), rgb(40, 44, 52), MAT.Metal, { name = "ElevatorTotem" })
	local tf = Kit.box(parent, CFrame.new(tx, PLAZA_TOP + M(1.3), tz + M(0.07)), Vector3.new(M(0.46), M(1.2), M(0.02)), rgb(26, 30, 38), MAT.SmoothPlastic, opts("ElevatorTotemFace"))
	Kit.label(tf, Enum.NormalId.Back, "전망대\n엘리베이터\n\n60 m\n잠실 야경", { glow = true, color = GOLD, pixelsPerStud = 50 })
	local gx, gz = sx - M(1.9), z1 - M(0.7)
	Kit.box(parent, CFrame.new(gx, DY + M(0.55), gz), Vector3.new(M(0.06), M(1.1), M(0.06)), STEEL, MAT.Metal, opts("DeckSignPost", { collide = true }))
	local ds = Kit.box(parent, CFrame.new(gx, DY + M(1.25), gz), Vector3.new(M(0.9), M(0.32), M(0.04)), rgb(26, 30, 38), MAT.SmoothPlastic, opts("DeckSign"))
	Kit.label(ds, Enum.NormalId.Front, "계단으로 내려가기\n엘리베이터는 오른쪽 끝", { glow = true, color = GOLD, pixelsPerStud = 60 })
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
	if lod >= 3 then
		c = c:Lerp(LEAF_LIGHT, rng:NextNumber(0.12, 0.32)) -- 히어로 띠: 위에서 보이는 수관을 조금 밝게
	end
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
		{ x0 = BELT_X0, x1 = BELT_X1, z1 = BELT_Z1, tries = 7000, cap = budget * 0.47 },
		{ x0 = NEAR0, x1 = NEAR1, z1 = Z1 - M(3), tries = 9000, cap = budget * 0.85 },
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
			local lod = if belt then 3 elseif near then 2 else 1
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

	irng = Random.new(Config.SEED + 4242)
	ORG = CFrame.identity
	local interiorParts = 0

	-- 1) 전망대 (+ 안내판·계단 표지·호출 버튼 받침)
	buildDeck(Kit.group(model, "Deck"))
	local q0 = Kit.stats.parts
	buildDeckDetail(Kit.group(model, "DeckDetail", Config.InteriorStreaming))
	interiorParts += Kit.stats.parts - q0

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

	-- 3) 편의점·테라스·화장실·자전거 대여소·피크닉 / 주차장
	q0 = Kit.stats.parts
	buildKiosk(Kit.group(model, "Kiosk"), rng, mainPts)
	interiorParts += Kit.stats.parts - q0
	if interiorParts > INTERIOR_BUDGET then
		warn(string.format("[SeoulSkyline] Park 실내 디테일 파트 %d > 예산 %d", interiorParts, INTERIOR_BUDGET))
	end
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
				if x > VIEW_X - M(195) and x < VIEW_X + M(215) and (cnt % 2 == 0 or math.abs(x - VIEW_X) < M(60)) then
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
	local treeCount = buildTrees(Kit.group(model, "Trees"), rng, PART_BUDGET - (Kit.stats.parts - p0 - interiorParts))

	-- 공원 띠 전체 예약 (도시 생성기가 둔치를 침범하지 않도록)
	Kit.reserve(X0, Z0, X1, Z1, "Park")
	model:SetAttribute("Lights", lightsUsed)
	model:SetAttribute("Trees", treeCount)
	model:SetAttribute("Parts", Kit.stats.parts - p0)
	model:SetAttribute("InteriorParts", interiorParts)
end

return Park
