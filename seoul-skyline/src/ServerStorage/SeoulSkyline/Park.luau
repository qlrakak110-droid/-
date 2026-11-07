--!strict
-- SeoulSkyline / Park
-- 가까운 쪽(+Z) 한강공원 + 관람 전망대(플레이어 스폰).
--
--   * 범위: Z [N.ParkFrom+70, N.SlopeTo] (= 490 ~ 790), X [-1600, 1600]. 히어로 구도 하단(X -460 ~ 660, Z 500 ~ 560)
--     은 둥근 수관이 촘촘한 "숲 카펫" 띠, 그 강 쪽 가장자리에 가로등 줄(수관을 아래에서 비춤).
--   * 높이 층(겹치는 면 없음): 잔디(지형) 3.0 / 연결 산책로 3.4 (이음 원판 3.1) / 메인 산책로·강변 산책로 3.7
--     (이음 3.4) / 광장·매점 테라스·주차장 4.0 / 주차선 4.3.  교차부는 위층이 아래층을 덮음.
--   * 전망대: DeckCenter 위 48x36 데크(바닥 120) + 뒤쪽 원형 유리 엘리베이터 + 그 둘레 나선 램프(걸어서 오르내림).
--     나선은 위로 갈수록 각도가 줄어 +X 쪽에서 -Z 로 진행하며 끝남 → 착지판 A 를 거쳐 데크로.
--   * 나무: 줄기 1 + 수관 타원체 1~2 개(근경 3 개). 길·구조물·다리·가로등과 겹치지 않게 격자/예약으로 검사.
--   * 실제 광원은 MAX_LIGHTS 이내: 전망대 → 광장 → 히어로 띠 가로등 순서(전역 상한에 걸리면 앞쪽이 우선).

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)

local Park = {}

local rgb = Color3.fromRGB
local P = Config.Palette
local L = Config.Level
local N = Config.NearBank
local B = Config.Bridge
local V = Config.Viewpoint
local MAT = Enum.Material

------------------------------------------------------------------------------------------------------
-- 상수
------------------------------------------------------------------------------------------------------
local PART_BUDGET = 3180
local MAX_LIGHTS = 40

local Z0 = N.ParkFrom + 70 -- 490
local Z1 = N.SlopeTo -- 790
local X0, X1 = -1600, 1600
local GROUND = L.Promenade -- 3
local CONN_TOP = GROUND + 0.4 -- 3.4
local MAIN_TOP = GROUND + 0.7 -- 3.7
local PLAZA_TOP = GROUND + 1.0 -- 4.0

local BRIDGE_HALF = B.Width / 2
local VIEW_X = 60 -- 히어로 화면 하단 중앙 X 근처
local BELT_X0, BELT_X1, BELT_Z1 = -460, 660, 562 -- 히어로 하단 숲 띠

-- 산책로
local MAIN_W = 8
local CONN_W = 5
local EDGE_W = 5
local EDGE_Z = Z0 + 3.5 -- 강변 쪽 산책로 중심선 (491 ~ 496)

-- 전망대
local DC = V.DeckCenter
local DY = V.DeckHeight -- 바닥 윗면
local DECK_W, DECK_D = 40, 30
local SHAFT = Vector2.new(DC.X, DC.Z + 38) -- 엘리베이터/나선 중심 (X, Z)
local SHAFT_R = 4.5
local RAMP_RIN, RAMP_ROUT = 6.5, 13.5
local RAMP_TURNS = 5.75
local RAMP_PER_TURN = 12
local PLAZA = Vector2.new(DC.X, DC.Z + 16)
local PLAZA_R = 38

-- 매점 / 피크닉 / 주차장
local KIOSK_X = -300
local PICNIC = { -380, 500, -220, 578 } -- x0, z0, x1, z1 (나무 없는 잔디밭)
local LOT = { -600, 676, -470, 752 }

-- 색
local WOOD = rgb(104, 78, 56)
local STEEL = rgb(58, 62, 70)
local STEEL_LIGHT = rgb(150, 156, 164)
local RAMP_C = rgb(168, 164, 156)
local GLASS_C = rgb(176, 206, 226)
local RAIL_GLOW = rgb(128, 98, 66)
local UNDER_GLOW = rgb(214, 176, 126)
local FASCIA_GLOW = rgb(150, 116, 76)
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
	rgb(52, 90, 50),
	rgb(64, 104, 54),
	rgb(46, 80, 48),
	rgb(74, 112, 58),
	rgb(56, 96, 64),
	rgb(82, 118, 60),
	rgb(42, 74, 48),
	rgb(90, 124, 64),
	rgb(66, 106, 68),
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
-- 점유 격자 (4 stud 셀): 1 = 길/벤치, 2 = 구조물(광장·매점·주차장)
------------------------------------------------------------------------------------------------------
local CELL = 4
local grid: { [number]: number } = {}

local function gkey(ix: number, iz: number): number
	return ix * 8192 + iz
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

local lamps = newHash(32)

------------------------------------------------------------------------------------------------------
-- 지면 높이 (레이아웃 + 잔디 둔덕)
------------------------------------------------------------------------------------------------------
local mounds: { { number } } = {} -- { x, z, r, centerY }

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
	return math.abs(x - B.X) < BRIDGE_HALF + pad
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
		if skip and skip(mid.X) then
			continue
		end
		local d = b - a
		local len = d.Magnitude
		if len < 0.2 then
			continue
		end
		local cf = CFrame.lookAt(Vector3.new(mid.X, top - th / 2, mid.Y), Vector3.new(b.X, top - th / 2, b.Y))
		Kit.box(parent, cf, Vector3.new(width, th, len), color, mat, { name = name, shadow = false })
		markSeg(a.X, a.Y, b.X, b.Y, width / 2 + 1, 1)
		-- 꺾인 이음부 바깥쪽 틈을 아래층 원판으로 메움(윗면이 0.3 낮아 겹친 곳은 가려짐)
		if i > 1 and not (skip and skip(a.X)) then
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
-- 가로등 / 벤치
------------------------------------------------------------------------------------------------------
-- 공원 가로등: 기둥 + 둥근 등(Neon). 반환: 등 머리 파트
local function lamp(parent: Instance, x: number, z: number, h: number, head: number): BasePart
	local gy = groundAt(x, z)
	Kit.vcyl(parent, Vector3.new(x, gy + h / 2 - 0.5, z), h + 1, 0.42, POLE_C, MAT.Metal, opts("LampPole", { shadow = false }))
	local hp = Kit.ball(parent, Vector3.new(x, gy + h + head * 0.42, z), head, LAMP_HEAD, MAT.Neon, glowOpts("LampHead"))
	hashAdd(lamps, x, z, 0)
	return hp
end

local function lampLight(head: BasePart, range: number?)
	tryLight(head, "PointLight", { color = LAMP_HEAD, brightness = 1.25, range = range or 24 })
end

-- 벤치: 경로를 바라봄 (dirToPath: 벤치 → 경로 단위 벡터)
local function bench(parent: Instance, x: number, z: number, dirToPath: Vector2)
	local gy = groundAt(x, z)
	local cf = CFrame.lookAt(Vector3.new(x, gy, z), Vector3.new(x + dirToPath.X, gy, z + dirToPath.Y))
	Kit.box(parent, cf * CFrame.new(0, 0.6, 0), Vector3.new(4.2, 1.2, 1.2), BENCH_BASE, MAT.Concrete, opts("BenchBase"))
	Kit.box(parent, cf * CFrame.new(0, 1.4, 0.05), Vector3.new(5.2, 0.4, 1.9), BENCH_WOOD, MAT.WoodPlanks, opts("BenchSeat", { collide = true }))
	Kit.box(parent, cf * CFrame.new(0, 2.5, 0.85), Vector3.new(5.2, 1.6, 0.3), BENCH_WOOD, MAT.WoodPlanks, opts("BenchBack"))
	markSeg(x, z, x, z, 3.2, 1)
end

------------------------------------------------------------------------------------------------------
-- 1) 전망대 (스폰) — 데크 + 원형 유리 엘리베이터 + 나선 램프 + 하부 광장
------------------------------------------------------------------------------------------------------
local function buildDeck(parent: Instance)
	local cx, cz = DC.X, DC.Z
	local hw, hd = DECK_W / 2, DECK_D / 2
	local x0, x1, z0, z1 = cx - hw, cx + hw, cz - hd, cz + hd
	local slabTop, slabBot = DY - 1, DY - 3.4
	local sx, sz = SHAFT.X, SHAFT.Y

	-- 하부 광장 (원형 포장, 윗면 4.0)
	Kit.vcyl(parent, Vector3.new(PLAZA.X, PLAZA_TOP - 0.6, PLAZA.Y), 1.2, PLAZA_R * 2, PLAZA_C, MAT.Slate, { name = "DeckPlaza", shadow = false })
	Kit.vcyl(parent, Vector3.new(PLAZA.X, PLAZA_TOP - 0.55, PLAZA.Y), 1.0, PLAZA_R * 2 + 1.4, BENCH_BASE, MAT.Concrete, opts("PlazaCurb", { shadow = false }))

	-- 데크: 구조 슬래브 + 목재 바닥(가장자리 0.6 안쪽)
	Kit.box(parent, CFrame.new(cx, (slabTop + slabBot) / 2, cz), Vector3.new(DECK_W, slabTop - slabBot, DECK_D), STEEL, MAT.Metal, { name = "DeckSlab" })
	Kit.box(parent, CFrame.new(cx, DY - 0.5, cz), Vector3.new(DECK_W - 1.2, 1, DECK_D - 1.2), WOOD, MAT.WoodPlanks, { name = "DeckFloor" })

	-- 슬래브 옆면 LED 띠 (뒤쪽은 착지판 구간 비움)
	local fy = slabBot + 1.2
	local landX0, landX1 = sx - 4, sx + RAMP_ROUT - 0.1 -- 착지판 B(-44) ~ A(-26.6)
	Kit.box(parent, CFrame.new(cx, fy, z0 - 0.2), Vector3.new(DECK_W, 0.7, 0.4), FASCIA_GLOW, MAT.Neon, glowOpts("DeckFascia", STEEL_LIGHT))
	Kit.box(parent, CFrame.new(x0 - 0.2, fy, cz), Vector3.new(0.4, 0.7, DECK_D + 0.8), FASCIA_GLOW, MAT.Neon, glowOpts("DeckFascia", STEEL_LIGHT))
	Kit.box(parent, CFrame.new(x1 + 0.2, fy, cz), Vector3.new(0.4, 0.7, DECK_D + 0.8), FASCIA_GLOW, MAT.Neon, glowOpts("DeckFascia", STEEL_LIGHT))
	Kit.box(parent, CFrame.new((x0 + landX0) / 2, fy, z1 + 0.2), Vector3.new(landX0 - x0, 0.7, 0.4), FASCIA_GLOW, MAT.Neon, glowOpts("DeckFascia", STEEL_LIGHT))
	Kit.box(parent, CFrame.new((landX1 + x1) / 2, fy, z1 + 0.2), Vector3.new(x1 - landX1, 0.7, 0.4), FASCIA_GLOW, MAT.Neon, glowOpts("DeckFascia", STEEL_LIGHT))

	-- 하부 다운라이트 6 + SpotLight 2
	for _, dx in { -(hw - 8), hw - 8 } do
		for j, dz in { -8, 0, 8 } do
			local dl = Kit.box(parent, CFrame.new(cx + dx, slabBot - 0.35, cz + dz), Vector3.new(2.4, 0.3, 2.4), UNDER_GLOW, MAT.Neon, glowOpts("DeckDownlight", STEEL_LIGHT))
			if j == 2 then
				tryLight(dl, "SpotLight", { face = Enum.NormalId.Bottom, angle = 80, range = 60, brightness = 2.4, color = P.LampWarm })
			end
		end
	end

	-- 받침: 앞쪽 기둥 2(+ 중간 연결보) + 엘리베이터까지 이어지는 중앙 보
	local colX = hw - 6
	for _, dx in { -colX, colX } do
		local h = slabBot - PLAZA_TOP
		Kit.vcyl(parent, Vector3.new(cx + dx, PLAZA_TOP + h / 2, cz - 6), h, 3.6, STEEL_LIGHT, MAT.Metal, { name = "DeckColumn" })
	end
	Kit.box(parent, CFrame.new(cx, 58, cz - 6), Vector3.new(colX * 2, 2.4, 2.2), STEEL_LIGHT, MAT.Metal, { name = "DeckTie" })
	Kit.box(parent, CFrame.new(cx, slabBot - 1.5, (cz - 6 + sz - SHAFT_R) / 2), Vector3.new(8, 3, sz - SHAFT_R - (cz - 6)), STEEL, MAT.Metal, { name = "DeckBeam" })

	-- 착지판: A = 나선 끝(+X 쪽) → 데크, B = 엘리베이터 문 → 데크
	local aX0, aX1 = sx + RAMP_RIN - 0.1, sx + RAMP_ROUT + 0.1
	Kit.box(parent, CFrame.new((aX0 + aX1) / 2, (DY + slabBot) / 2, (z1 + sz + 0.3) / 2), Vector3.new(aX1 - aX0, DY - slabBot, sz + 0.3 - z1), WOOD, MAT.WoodPlanks, { name = "LandingA" })
	local bX0 = sx - 4
	local bZ1 = sz - SHAFT_R - 0.1
	Kit.box(parent, CFrame.new((bX0 + aX0) / 2, (DY + slabBot) / 2, (z1 + bZ1) / 2), Vector3.new(aX0 - bX0, DY - slabBot, bZ1 - z1), WOOD, MAT.WoodPlanks, { name = "LandingB" })

	-- 유리 난간 + 발광 손잡이
	local gTop = slabTop + 4.6
	local function rail(cfr: CFrame, len: number)
		Kit.box(parent, cfr * CFrame.new(0, (slabTop + gTop) / 2 - cfr.Position.Y, 0), Vector3.new(len, gTop - slabTop, 0.3), GLASS_C, MAT.Glass, { name = "GlassRail", transparency = 0.6 })
		Kit.box(parent, cfr * CFrame.new(0, gTop + 0.2 - cfr.Position.Y, 0), Vector3.new(len + 0.4, 0.4, 0.5), RAIL_GLOW, MAT.Neon, glowOpts("Handrail", STEEL_LIGHT))
	end
	local ry = slabTop
	local turn = CFrame.Angles(0, math.rad(90), 0)
	rail(CFrame.new(cx, ry, z0 + 0.4), DECK_W - 0.8)
	rail(CFrame.new(x0 + 0.4, ry, cz) * turn, DECK_D - 0.8)
	rail(CFrame.new(x1 - 0.4, ry, cz) * turn, DECK_D - 0.8)
	rail(CFrame.new((x0 + 0.4 + bX0) / 2, ry, z1 - 0.4), bX0 - x0 - 0.4)
	rail(CFrame.new((aX1 + x1 - 0.4) / 2, ry, z1 - 0.4), x1 - 0.4 - aX1)
	rail(CFrame.new(aX1 - 0.4, ry, (z1 + sz - 2) / 2) * turn, sz - 2 - z1)
	rail(CFrame.new(bX0 + 0.4, ry, (z1 + bZ1) / 2) * turn, bZ1 - z1)

	-- 원형 유리 엘리베이터 (+ 세로 LED 4, 발광 캐빈, 상부 캡, 하부 링)
	local shaftTop = DY + 8
	Kit.vcyl(parent, Vector3.new(sx, (PLAZA_TOP + shaftTop) / 2, sz), shaftTop - PLAZA_TOP, SHAFT_R * 2, GLASS_C, MAT.Glass, { name = "ElevatorShaft", transparency = 0.5, shadow = false })
	for k = 0, 3 do
		local a = math.rad(45 + 90 * k)
		Kit.box(parent, CFrame.new(sx + math.cos(a) * (SHAFT_R + 0.3), (PLAZA_TOP + shaftTop) / 2, sz + math.sin(a) * (SHAFT_R + 0.3)) * CFrame.Angles(0, -a, 0), Vector3.new(0.3, shaftTop - PLAZA_TOP, 0.3), FASCIA_GLOW, MAT.Neon, glowOpts("ShaftLed", STEEL_LIGHT))
	end
	local cab = Kit.box(parent, CFrame.new(sx, 64, sz), Vector3.new(5, 7, 5), CAB_GLOW, MAT.Neon, glowOpts("ElevatorCab", rgb(200, 200, 196)))
	tryLight(cab, "PointLight", { color = CAB_GLOW, brightness = 1.4, range = 22 })
	Kit.vcyl(parent, Vector3.new(sx, shaftTop + 0.6, sz), 1.2, SHAFT_R * 2 + 1.4, STEEL, MAT.Metal, { name = "ShaftCap" })
	local ring = Kit.vcyl(parent, Vector3.new(sx, PLAZA_TOP + 0.5, sz), 1.0, SHAFT_R * 2 + 1.2, STEEL, MAT.Metal, { name = "ShaftBase" })
	tryLight(ring, "PointLight", { color = P.LampWarm, brightness = 1.2, range = 24 })

	-- 나선 램프: 위로 갈수록 θ 감소, 끝 θ = 0(+X 쪽, -Z 로 진행) → 착지판 A
	local nSeg = math.floor(RAMP_TURNS * RAMP_PER_TURN + 0.5)
	local dTheta = math.rad(360 / RAMP_PER_TURN)
	local rise = (DY - PLAZA_TOP) / nSeg
	local rc = (RAMP_RIN + RAMP_ROUT) / 2
	local width = RAMP_ROUT - RAMP_RIN
	local arc = rc * dTheta
	local slope = math.atan(rise / arc)
	local len = (2 * RAMP_ROUT * math.tan(dTheta / 2) + 0.4) / math.cos(slope)
	local th = 0.8
	for k = 0, nSeg - 1 do
		local thMid = (nSeg - k - 0.5) * dTheta -- θ_end = 0
		local yMid = PLAZA_TOP + (k + 0.5) * rise
		local c = Vector3.new(sx + rc * math.cos(thMid), yMid, sz + rc * math.sin(thMid))
		local dir = Vector3.new(math.sin(thMid) * arc, rise, -math.cos(thMid) * arc)
		local cf = CFrame.lookAt(c, c + dir) * CFrame.new(0, -th / 2 / math.cos(slope), 0)
		Kit.box(parent, cf, Vector3.new(width, th, len), RAMP_C, MAT.Concrete, { name = "Ramp", shadow = true })
		Kit.box(parent, cf * CFrame.new(width / 2 - 0.25, th / 2 + 1.7, 0), Vector3.new(0.25, 3.4, len), GLASS_C, MAT.Glass, opts("RampGlass", { transparency = 0.62, collide = true }))
		Kit.box(parent, cf * CFrame.new(width / 2 + 0.25, -0.1, 0), Vector3.new(0.25, 0.35, len), HELIX_GLOW, MAT.Neon, glowOpts("RampLed", STEEL_LIGHT))
	end

	-- 데크 소품: 쌍안경 2, 벤치 2
	for _, dx in { -16, 16 } do
		Kit.vcyl(parent, Vector3.new(cx + dx, DY + 1.6, z0 + 3), 3.2, 0.7, STEEL_LIGHT, MAT.Metal, opts("ScopePost", { collide = true }))
		Kit.box(parent, CFrame.new(cx + dx, DY + 3.6, z0 + 3) * CFrame.Angles(math.rad(8), 0, 0), Vector3.new(1.4, 1.1, 2.0), rgb(40, 96, 110), MAT.Metal, opts("Binocular"))
	end
	for _, dx in { -13, 13 } do
		local bx, bz = cx + dx, cz + 8
		local cf = CFrame.new(bx, DY, bz)
		Kit.box(parent, cf * CFrame.new(0, 0.6, 0), Vector3.new(6, 1.2, 1.2), BENCH_BASE, MAT.Concrete, opts("DeckBenchBase"))
		Kit.box(parent, cf * CFrame.new(0, 1.4, 0), Vector3.new(7, 0.4, 2), BENCH_WOOD, MAT.WoodPlanks, opts("DeckBenchSeat", { collide = true }))
		Kit.box(parent, cf * CFrame.new(0, 2.5, 0.85), Vector3.new(7, 1.6, 0.3), BENCH_WOOD, MAT.WoodPlanks, opts("DeckBenchBack"))
	end

	-- 포토 스팟: 바닥 표지판 + 삼각대 + 카메라(PhotoSpot, ProximityPrompt)
	local px, pz = cx - 9, z0 + 5
	local plate = Kit.box(parent, CFrame.new(px, DY + 0.15, pz + 2.6), Vector3.new(5, 0.3, 2.2), rgb(34, 36, 42), MAT.SmoothPlastic, opts("PhotoSpotSign"))
	Kit.label(plate, Enum.NormalId.Top, "포토 스팟", { glow = true, color = rgb(255, 214, 150), pixelsPerStud = 24 })
	tryLight(plate, "PointLight", { color = P.LampWarm, brightness = 0.9, range = 12 })
	Kit.vcyl(parent, Vector3.new(px, DY + 2.1, pz), 4.2, 0.45, STEEL, MAT.Metal, opts("Tripod"))
	local spot = Kit.box(parent, CFrame.new(px, DY + 4.75, pz), Vector3.new(1.8, 1.1, 1.0), rgb(24, 24, 28), MAT.SmoothPlastic, { name = "PhotoSpot", collide = false, query = true })
	Kit.hcyl(parent, CFrame.new(px, DY + 4.75, pz - 0.8) * CFrame.Angles(0, math.rad(90), 0), 0.7, 0.7, rgb(60, 62, 70), MAT.Glass, opts("Lens"))
	spot:SetAttribute("HeroCamPos", V.HeroCamPos)
	spot:SetAttribute("HeroCamLook", V.HeroCamLook)
	spot:SetAttribute("HeroFov", V.HeroFov)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "PhotoPrompt"
	pp.ActionText = "사진 구도"
	pp.ObjectText = "포토 스팟"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Parent = spot

	-- 스폰 (반투명 패드, 정면 = -Z)
	local sp = Instance.new("SpawnLocation")
	sp.Name = "DeckSpawn"
	sp.Anchored = true
	sp.Size = Vector3.new(8, 0.4, 8)
	sp.CFrame = CFrame.new(cx, DY + 0.2, cz + 3)
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

	-- 광장 가로등 4 (광원)
	for k = 0, 3 do
		local a = math.rad(200 + k * 45)
		local lx, lz = PLAZA.X + math.cos(a) * (PLAZA_R - 3), PLAZA.Y + math.sin(a) * (PLAZA_R - 3)
		local gy = PLAZA_TOP
		Kit.vcyl(parent, Vector3.new(lx, gy + 5.5, lz), 11, 0.42, POLE_C, MAT.Metal, opts("LampPole", { shadow = false }))
		local hd2 = Kit.ball(parent, Vector3.new(lx, gy + 11.6, lz), 1.5, LAMP_HEAD, MAT.Neon, glowOpts("LampHead"))
		hashAdd(lamps, lx, lz, 0)
		lampLight(hd2, 26)
	end

	-- 예약 / 격자 (광장 원판 + 데크 전체)
	Kit.reserve(PLAZA.X - PLAZA_R, PLAZA.Y - PLAZA_R, PLAZA.X + PLAZA_R, PLAZA.Y + PLAZA_R, "ParkDeck")
	Kit.reserve(x0, z0, x1, z1, "ParkDeckSlab")
	for ix = math.floor((PLAZA.X - PLAZA_R) / CELL), math.floor((PLAZA.X + PLAZA_R) / CELL) do
		for iz = math.floor((PLAZA.Y - PLAZA_R) / CELL), math.floor((PLAZA.Y + PLAZA_R) / CELL) do
			local ex, ez = (ix + 0.5) * CELL - PLAZA.X, (iz + 0.5) * CELL - PLAZA.Y
			if ex * ex + ez * ez <= (PLAZA_R + 3) ^ 2 then
				mark(ix, iz, 2)
			end
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 2) 편의점 매점 + 테라스 + 피크닉장 + "한강공원" 표지석
------------------------------------------------------------------------------------------------------
local function parasol(parent: Instance, x: number, y: number, z: number, color: Color3)
	Kit.vcyl(parent, Vector3.new(x, y + 3.6, z), 7.2, 0.3, rgb(220, 220, 214), MAT.Metal, opts("ParasolPole"))
	Kit.ellipsoid(parent, CFrame.new(x, y + 7.0, z), Vector3.new(7.5, 1.6, 7.5), color, MAT.Fabric, opts("Parasol"))
end

local function signStone(parent: Instance, x: number, z: number, text: string)
	local gy = groundAt(x, z)
	Kit.box(parent, CFrame.new(x, gy + 0.5, z), Vector3.new(15, 1, 3.4), BENCH_BASE, MAT.Concrete, { name = "SignBase" })
	local board = Kit.box(parent, CFrame.new(x, gy + 1 + 1.9, z), Vector3.new(13, 3.8, 1.4), rgb(48, 50, 56), MAT.Granite, { name = "SignStone" })
	Kit.label(board, Enum.NormalId.Back, text, { glow = true, color = rgb(250, 232, 200), pixelsPerStud = 16 })
	Kit.box(parent, CFrame.new(x, gy + 1.25, z + 1.4), Vector3.new(12, 0.3, 0.6), LAMP_HEAD, MAT.Neon, glowOpts("SignUplight"))
	markSeg(x - 7.5, z, x + 7.5, z, 3, 1)
end

local function buildKiosk(parent: Instance, rng: Random, mainPts: { Vector2 })
	local kx = KIOSK_X
	local pz = zOnPath(mainPts, kx)
	local W, D, H = 22, 12, 9
	local kz1 = pz - MAIN_W / 2 - 9 -- 매장 앞면(+Z)
	local kz = kz1 - D / 2
	local base = PLAZA_TOP
	-- 테라스 (매장 뒤 1 ~ 메인 산책로 가장자리 0.6 안쪽까지)
	local tz0, tz1 = kz - D / 2 - 1, pz - MAIN_W / 2 + 0.6
	Kit.box(parent, CFrame.new(kx + 3, base - 0.6, (tz0 + tz1) / 2), Vector3.new(W + 18, 1.2, tz1 - tz0), PAVE_C, MAT.Pavement, { name = "KioskTerrace", shadow = false })
	-- 건물
	Kit.box(parent, CFrame.new(kx, base + H / 2, kz), Vector3.new(W, H, D), rgb(214, 208, 198), MAT.Concrete, { name = "Kiosk" })
	Kit.box(parent, CFrame.new(kx, base + H + 0.6, kz + 0.6), Vector3.new(W + 2.4, 1.2, D + 3.2), rgb(54, 58, 66), MAT.Metal, { name = "KioskRoof" })
	local front = Kit.box(parent, CFrame.new(kx - 2, base + 3.3, kz1 + 0.2), Vector3.new(W - 7, 5.4, 0.4), rgb(214, 190, 150), MAT.Neon, glowOpts("KioskWindow", rgb(60, 78, 96)))
	tryLight(front, "PointLight", { color = rgb(255, 222, 176), brightness = 1.3, range = 26 })
	Kit.box(parent, CFrame.new(kx + W / 2 - 2.6, base + 3.4, kz1 + 0.3), Vector3.new(3.2, 6.6, 0.6), rgb(66, 70, 78), MAT.Metal, opts("KioskDoor"))
	local sign = Kit.box(parent, CFrame.new(kx, base + H - 1.0, kz1 + 0.3), Vector3.new(W - 1, 1.7, 0.6), rgb(30, 104, 168), MAT.SmoothPlastic, opts("KioskSign"))
	Kit.label(sign, Enum.NormalId.Back, "편의점", { glow = true, color = rgb(255, 255, 255), pixelsPerStud = 16 })
	-- 강 쪽 벽에도 간판(히어로 반대편)
	local sign2 = Kit.box(parent, CFrame.new(kx, base + H - 1.0, kz - D / 2 - 0.3), Vector3.new(W - 6, 1.7, 0.6), rgb(30, 104, 168), MAT.SmoothPlastic, opts("KioskSign"))
	Kit.label(sign2, Enum.NormalId.Front, "편의점", { glow = true, color = rgb(255, 255, 255), pixelsPerStud = 16 })
	-- 자판기 2
	for i, c in { rgb(170, 34, 40), rgb(36, 90, 160) } do
		local vx = kx - W / 2 - 1.6 - (i - 1) * 2.8
		Kit.box(parent, CFrame.new(vx, base + 2.9, kz1 - 1.2), Vector3.new(2.4, 5.8, 2.0), c, MAT.SmoothPlastic, { name = "Vending" })
		Kit.box(parent, CFrame.new(vx, base + 3.6, kz1 - 0.05), Vector3.new(1.8, 3.2, 0.3), rgb(220, 226, 236), MAT.Neon, glowOpts("VendingGlow", rgb(180, 190, 200)))
	end
	-- 테라스 파라솔 테이블 3
	local cols = { rgb(196, 54, 46), rgb(236, 230, 214), rgb(44, 112, 168) }
	for i = 1, 3 do
		local tx, tz = kx - 8 + (i - 1) * 9, (kz1 + pz - MAIN_W / 2) / 2
		Kit.vcyl(parent, Vector3.new(tx, base + 2.5, tz), 0.25, 3.4, rgb(230, 230, 226), MAT.SmoothPlastic, opts("CafeTable", { collide = true }))
		parasol(parent, tx, base, tz, cols[i])
	end
	Kit.reserve(kx - W / 2 - 8, tz0, kx + W / 2 + 12, tz1, "ParkKiosk")
	markRect(kx - W / 2 - 8, tz0 - 2, kx + W / 2 + 14, tz1, 2)

	-- 피크닉장 (매점 강 쪽 잔디밭): 테이블 세트 + 파라솔 + 돗자리
	local sets = { { -350, 548 }, { -322, 562 }, { -292, 546 }, { -262, 560 }, { -238, 540 } }
	for i, s in sets do
		local x, z = s[1], s[2]
		local gy = groundAt(x, z)
		local yaw = CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0)
		local cf = CFrame.new(x, gy, z) * yaw
		Kit.box(parent, cf * CFrame.new(0, 2.6, 0), Vector3.new(6, 0.4, 2.8), BENCH_WOOD, MAT.WoodPlanks, opts("PicnicTable", { collide = true }))
		Kit.box(parent, cf * CFrame.new(0, 1.2, 0), Vector3.new(4.4, 2.4, 0.6), BENCH_BASE, MAT.Concrete, opts("PicnicLeg"))
		Kit.box(parent, cf * CFrame.new(0, 1.5, 2.6), Vector3.new(6, 0.4, 1.1), BENCH_WOOD, MAT.WoodPlanks, opts("PicnicSeat", { collide = true }))
		Kit.box(parent, cf * CFrame.new(0, 1.5, -2.6), Vector3.new(6, 0.4, 1.1), BENCH_WOOD, MAT.WoodPlanks, opts("PicnicSeat", { collide = true }))
		if i % 2 == 1 then
			parasol(parent, x, gy, z, cols[(i // 2) % 3 + 1])
		end
	end
	local mats = { { -330, 522, rgb(214, 120, 60) }, { -276, 528, rgb(70, 140, 190) }, { -246, 514, rgb(220, 196, 90) } }
	for _, m in mats do
		Kit.box(parent, CFrame.new(m[1] :: number, GROUND + 0.15, m[2] :: number) * CFrame.Angles(0, math.rad(rng:NextNumber(-30, 30)), 0), Vector3.new(6, 0.3, 5), m[3] :: Color3, MAT.Fabric, opts("PicnicMat"))
	end
	local pl = lamp(parent, -300, 572, 10.5, 1.5)
	lampLight(pl, 26)
	for _, s in sets do
		markSeg(s[1], s[2], s[1], s[2], 5, 1)
	end
	signStone(parent, kx + W / 2 + 26, pz - MAIN_W / 2 - 6, "한강공원")
end

------------------------------------------------------------------------------------------------------
-- 3) 주차장 (제방 아래)
------------------------------------------------------------------------------------------------------
local function buildParking(parent: Instance, rng: Random)
	local x0, z0, x1, z1 = LOT[1], LOT[2], LOT[3], LOT[4]
	local top = PLAZA_TOP
	Kit.box(parent, CFrame.new((x0 + x1) / 2, top - 0.6, (z0 + z1) / 2), Vector3.new(x1 - x0, 1.2, z1 - z0), P.Asphalt, MAT.Asphalt, { name = "ParkingLot", shadow = false })
	Kit.box(parent, CFrame.new((x0 + x1) / 2, top - 0.45, z0 - 0.6), Vector3.new(x1 - x0 + 2.4, 1.5, 1.2), BENCH_BASE, MAT.Concrete, { name = "LotCurb", shadow = false })
	local stallW, depth = 7.5, 17
	local rows = { { z0 + 1, z0 + 1 + depth, 1 }, { z1 - 1 - depth, z1 - 1, -1 } }
	local paint = rgb(200, 200, 192)
	local xs: { number } = {}
	local x = x0 + 5
	while x <= x1 - 5 do
		table.insert(xs, x)
		x += stallW
	end
	for _, row in rows do
		for _, lx in xs do
			Kit.box(parent, CFrame.new(lx, top + 0.15, (row[1] + row[2]) / 2), Vector3.new(0.35, 0.3, depth), paint, MAT.SmoothPlastic, opts("StallLine", { shadow = false }))
		end
		-- 주차된 차 (빈칸 섞임)
		for i = 1, #xs - 1 do
			if rng:NextNumber() < 0.55 then
				local cx = (xs[i] + xs[i + 1]) / 2
				local cz = (row[1] + row[2]) / 2 + row[3] * 0.6
				local col = CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)]
				local cf = CFrame.new(cx, top, cz) * CFrame.Angles(0, math.rad(rng:NextNumber(-2, 2)), 0)
				Kit.box(parent, cf * CFrame.new(0, 1.1, 0), Vector3.new(3.8, 1.6, 8.6), col, MAT.SmoothPlastic, { name = "CarBody" })
				Kit.box(parent, cf * CFrame.new(0, 2.5, row[3] * 0.6), Vector3.new(3.4, 1.2, 4.6), rgb(36, 42, 52), MAT.Glass, opts("CarCabin"))
			end
		end
	end
	-- 주차장 조명 2
	for i, lx in { x0 + 32, x1 - 32 } do
		local lz = (z0 + z1) / 2
		Kit.vcyl(parent, Vector3.new(lx, top + 8, lz), 16, 0.6, POLE_C, MAT.Metal, opts("LotPole"))
		local hd = Kit.box(parent, CFrame.new(lx, top + 16.2, lz), Vector3.new(2.6, 0.5, 1.2), rgb(236, 226, 206), MAT.Neon, glowOpts("LotLight"))
		hashAdd(lamps, lx, lz, 0)
		if i == 1 then
			tryLight(hd, "SpotLight", { face = Enum.NormalId.Bottom, angle = 110, range = 40, brightness = 1.6, color = rgb(255, 232, 196) })
		end
	end
	Kit.reserve(x0, z0 - 1.2, x1, z1, "ParkParking")
	markRect(x0 - 2, z0 - 3, x1 + 2, z1 + 2, 2)
	signStone(parent, x1 + 16, z0 - 8, "한강공원 주차장")
end

------------------------------------------------------------------------------------------------------
-- 4) 둔덕 (지형 Ball, 잔디)
------------------------------------------------------------------------------------------------------
local function buildMounds(rng: Random)
	local made = 0
	for _ = 1, 80 do
		if made >= 12 then
			break
		end
		local x = rng:NextNumber(-1300, 1300)
		local z = rng:NextNumber(570, 735)
		local r = rng:NextNumber(30, 46)
		local h = rng:NextNumber(3.5, 6.5)
		local fr = math.sqrt(2 * r * h - h * h)
		if inBridge(x, fr + 10) or inPicnic(x, z, fr + 4) then
			continue
		end
		if occupied(x, z, fr + 3, 1) then
			continue
		end
		if not Kit.isFree(x - fr, z - fr, x + fr, z + fr) then
			continue
		end
		local clash = false
		for _, m in mounds do
			local mfr = m[5]
			if (Vector2.new(m[1], m[2]) - Vector2.new(x, z)).Magnitude < fr + mfr + 6 then
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
-- 5) 나무 (둥근 활엽수: 줄기 + 수관 타원체)
------------------------------------------------------------------------------------------------------
local function tree(parent: Instance, rng: Random, x: number, z: number, gy: number, D: number, lod: number): number
	local th = rng:NextNumber(3.2, 5.6) * math.clamp(D / 18, 0.8, 1.3)
	local hc = D * rng:NextNumber(0.8, 0.94)
	local trunkD = math.clamp(D * 0.075, 0.9, 2.0)
	local n = 0
	Kit.vcyl(parent, Vector3.new(x, gy + (th + 2.5) / 2 - 1, z), th + 2.5, trunkD, BARK, MAT.Wood, { name = "Trunk", shadow = false })
	n += 1
	local c = LEAVES[rng:NextInteger(1, #LEAVES)]
	local mat = if rng:NextNumber() < 0.6 then MAT.Grass else MAT.LeafyGrass
	local cy = gy + th + hc * 0.45
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
	if d < 700 then
		return 1
	end
	return math.clamp(1 - (d - 700) / 1100, 0.42, 1)
end

local function buildTrees(parent: Instance, rng: Random, budget: number): number
	-- 숲(그로브) 중심: 그 밖은 듬성듬성(잔디 공터)
	local groves: { { number } } = {}
	for _ = 1, 70 do
		local x = math.clamp(VIEW_X + rng:NextNumber(-1, 1) * rng:NextNumber(0.25, 1) * 1700, X0, X1)
		table.insert(groves, { x, rng:NextNumber(Z0 + 20, Z1 - 20), rng:NextNumber(40, 90) })
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

	local trees = newHash(32)
	local used, count = 0, 0
	-- pass 1: 히어로 띠 + 근경, pass 2: 원경
	local passes = {
		{ x0 = -1000, x1 = 1150, tries = 9000 },
		{ x0 = X0 + 8, x1 = X1 - 8, tries = 9000 },
	}
	for pi, pass in passes do
		for _ = 1, pass.tries do
			if used >= budget - 4 then
				break
			end
			local x = rng:NextNumber(pass.x0, pass.x1)
			if pi == 2 and x > -1000 and x < 1150 then
				continue
			end
			local z = rng:NextNumber(Z0 + 8, Z1 - 6)
			local belt = x > BELT_X0 and x < BELT_X1 and z < BELT_Z1
			local p = if belt then 0.95 else densX(x) * (0.2 + 0.8 * groveField(x, z))
			if rng:NextNumber() > p then
				continue
			end
			local D = if belt then rng:NextNumber(22, 30) else rng:NextNumber(14, 24)
			local r = D / 2
			if z + r * 0.9 > Z1 - 2 then
				continue
			end
			if inBridge(x, 5 + r) or inPicnic(x, z, r * 0.5) then
				continue
			end
			if occupied(x, z, 2.5, 1) or occupied(x, z, r * 0.7, 2) then
				continue
			end
			if hashHit(lamps, x, z, r * 0.85, 1, 1.2) then
				continue
			end
			if hashHit(trees, x, z, r, if belt then 0.58 else 0.64, 0) then
				continue
			end
			if not Kit.isFree(x - r * 0.7, z - r * 0.7, x + r * 0.7, z + r * 0.7) then
				continue
			end
			local gy = groundAt(x, z)
			local near = math.abs(x - VIEW_X) < 950
			local lod = if near and D >= 15 then 3 else 2
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
	lamps = newHash(32)

	-- 메인 산책로 선형 (구조물 배치 기준)
	local ctrl = {
		Vector2.new(-1600, 645),
		Vector2.new(-1380, 615),
		Vector2.new(-1150, 650),
		Vector2.new(-930, 605),
		Vector2.new(-720, 632),
		Vector2.new(-560, 610),
		Vector2.new(-400, 612),
		Vector2.new(-250, 618),
		Vector2.new(-130, 648),
		Vector2.new(-40, 662),
		Vector2.new(60, 650),
		Vector2.new(170, 626),
		Vector2.new(B.X, 624),
		Vector2.new(340, 622),
		Vector2.new(450, 600),
		Vector2.new(600, 628),
		Vector2.new(780, 606),
		Vector2.new(980, 645),
		Vector2.new(1200, 612),
		Vector2.new(1420, 640),
		Vector2.new(1600, 620),
	}
	local function stepAt(x: number): number
		return if math.abs(x - VIEW_X) < 950 then 22 else 60
	end
	local mainPts = catmull(ctrl, stepAt)

	-- 1) 전망대
	buildDeck(Kit.group(model, "Deck"))

	-- 2) 산책로: 강변 산책로(직선) → 메인(곡선) → 연결로 → 광장 진입로
	local paths = Kit.group(model, "Paths")
	local edgeSpans = { { -1000, B.X - BRIDGE_HALF - 4 }, { B.X + BRIDGE_HALF + 4, 1100 } }
	for _, s in edgeSpans do
		local a, b = s[1], s[2]
		Kit.box(paths, CFrame.new((a + b) / 2, MAIN_TOP - 0.4, EDGE_Z), Vector3.new(b - a, 0.8, EDGE_W), EDGE_C, MAT.Pavement, { name = "EdgeWalk", shadow = false })
		markSeg(a, EDGE_Z, b, EDGE_Z, EDGE_W / 2 + 1, 1)
	end
	drawPath(paths, mainPts, MAIN_W, MAIN_TOP, BRICK_C, MAT.Brick, "MainPath")

	local connectors: { { Vector2 } } = {}
	local connX = { -1240, -760, -180, 380, 760, 1180 }
	for _, cx in connX do
		local xe = cx + rng:NextNumber(-30, 30)
		local ze = zOnPath(mainPts, xe)
		local c = {
			Vector2.new(cx, EDGE_Z),
			Vector2.new(cx + rng:NextNumber(-14, 14), EDGE_Z + (ze - EDGE_Z) * 0.35),
			Vector2.new((cx + xe) / 2 + rng:NextNumber(-16, 16), EDGE_Z + (ze - EDGE_Z) * 0.7),
			Vector2.new(xe, ze),
		}
		local pts = catmull(c, function(_x: number): number
			return 18
		end)
		drawPath(paths, pts, CONN_W, CONN_TOP, PAVE_C, MAT.Pavement, "ConnPath")
		table.insert(connectors, pts)
	end
	-- 광장 진입로 (메인 → 광장 안쪽)
	local spur = catmull({ Vector2.new(DC.X + 22, zOnPath(mainPts, DC.X + 22)), Vector2.new(DC.X + 12, PLAZA.Y - PLAZA_R + 8) }, function(_x: number): number
		return 30
	end)
	drawPath(paths, spur, 6, CONN_TOP, PAVE_C, MAT.Pavement, "PlazaSpur")

	-- 3) 매점·피크닉 / 주차장
	buildKiosk(Kit.group(model, "Kiosk"), rng, mainPts)
	buildParking(Kit.group(model, "Parking"), rng)

	-- 4) 가로등 + 벤치
	local fx = Kit.group(model, "Lamps")
	local function lampOK(x: number, z: number): boolean
		return not inBridge(x, 6) and not occupied(x, z, 1.5, 2) and not hashHit(lamps, x, z, 0, 1, 10)
	end
	-- 강변 산책로 줄 (숲 앞 가장자리): 히어로 띠는 촘촘 + 광원
	do
		local x = -1000
		local n = 0
		while x <= 1100 do
			local lz = EDGE_Z + EDGE_W / 2 + 1.6
			local nearConn = false
			for _, cx in connX do
				if math.abs(x - cx) < 6 then
					nearConn = true
				end
			end
			if not nearConn and lampOK(x, lz) then
				local hp = lamp(fx, x, lz, 10.5, 1.5)
				n += 1
				if x > -340 and x < 480 and n % 2 == 0 then
					lampLight(hp, 26)
				end
			end
			x += if x > BELT_X0 and x < BELT_X1 then 32 else 72
		end
	end
	-- 메인 산책로: 양쪽 엇갈림
	local side = 1
	for _, st in stations(mainPts, function(x: number): number
		return if math.abs(x - VIEW_X) < 950 then 38 else 96
	end, 10) do
		local p, dir = st[1], st[2]
		local nrm = Vector2.new(-dir.Y, dir.X) * side
		local q = p + nrm * (MAIN_W / 2 + 1.6)
		if lampOK(q.X, q.Y) then
			local hp = lamp(fx, q.X, q.Y, 11, 1.5)
			if q.X > -260 and q.X < 200 then
				lampLight(hp)
			end
		end
		side = -side
	end
	-- 연결로
	for ci, pts in connectors do
		local sd = if ci % 2 == 0 then 1 else -1
		for _, st in stations(pts, function(_x: number): number
			return 34
		end, 24) do
			local p, dir = st[1], st[2]
			local q = p + Vector2.new(-dir.Y, dir.X) * sd * (CONN_W / 2 + 1.5)
			if q.Y < zOnPath(mainPts, q.X) - MAIN_W and lampOK(q.X, q.Y) then
				local hp = lamp(fx, q.X, q.Y, 10, 1.4)
				if q.X > -340 and q.X < 480 and q.Y < 580 then
					lampLight(hp)
				end
			end
			sd = -sd
		end
	end
	-- 벤치: 메인 산책로 근경
	local bside = 1
	for _, st in stations(mainPts, function(_x: number): number
		return 46
	end, 30) do
		local p, dir = st[1], st[2]
		if math.abs(p.X - VIEW_X) < 900 then
			local nrm = Vector2.new(-dir.Y, dir.X) * bside
			local q = p + nrm * (MAIN_W / 2 + 2.4)
			if not inBridge(q.X, 8) and not occupied(q.X, q.Y, 2, 2) and not hashHit(lamps, q.X, q.Y, 0, 1, 4) then
				bench(fx, q.X, q.Y, -nrm)
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
