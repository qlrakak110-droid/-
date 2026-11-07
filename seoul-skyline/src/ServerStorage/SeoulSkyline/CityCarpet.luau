--!strict
-- SeoulSkyline / CityCarpet
-- 지평선까지 이어지는 LOD 도시 카펫 + 원경 산 능선. 실제 스케일(1 stud = 0.3 m).
--   * CarpetFarMid  : Facade "mid"(몸체 + 층 불빛 띠) 8~30층(25~90 m), 다운타운 클러스터에서 40~60층(160~240 m) 고층 몇 개
--   * CarpetFarFar  : Facade "far"(몸체 + 불빛 띠 1) 5~25층(16~80 m), 클러스터에서 가끔 높은 원경 타워(항공등)
--   * CarpetNear    : 관람자 뒤쪽 도시 — 가까운 줄은 "mid", 먼 줄은 "far"
--   * Infill        : 아파트 띠의 빈 블록 + 아파트 띠 바깥 옆 구간을 저층 상가/빌라(2~10층, 8~30 m)로 메움
--   * 높이는 몇 개의 "다운타운" 클러스터(가우시안)에서 솟아 원경 스카이라인이 평평한 벽이 되지 않게 함
--   * 배치: 지터 격자 후보 → 우선순위(관람자 거리 × 화면 밖 가중 × 잡음) 순으로 예산까지 → 멀수록 자연스럽게 성기게
--   * 모든 발자국 Kit.isFreeRect 검사 + Kit.reserveRect (Skyline/Landmark/Bridge/Riverside/Apartments 예약을 피함). 광원 0개.
--   * 산: 서울 외곽 산(높이 300~600 m = 1000~2000 stud, 산괴 폭 3~8 km)을 Kit.ellipsoid 로 — 넓고 낮은 산자락 1개 +
--     봉우리 2~4개를 땅에 묻어 겹침. 먼 겹일수록 밝은 청회색(대기 원근), 무광(Fabric) 재질. 먼 쪽 3겹 / 가까운 쪽 2겹.
--   * 도시 지면(Riverside CityGround) 바깥까지 이어지는 카펫 구간은 도시 지면보다 0.6 낮은 바닥 판으로 받침(겹쳐도 z-fighting 없음).

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)
local Facade = require(script.Parent.Facade)

local CityCarpet = {}

local rgb = Color3.fromRGB
local P = Config.Palette
local ZN = Config.Zones
local R = Config.Real
local M = Config.m
local CITY_Y = Config.Level.City
local MAT = Enum.Material

------------------------------------------------------------------------------------------------------
-- 상수
------------------------------------------------------------------------------------------------------
local BUDGET_TOTAL = 5500 -- 모듈 하드 캡
local BUDGET = { FarMid = 1900, FarFar = 1250, Near = 1000, InfillFar = 650, InfillNear = 380 } -- 구역별(밀도 배율 적용 전)
local RESERVE_TAIL = 260 -- 산 + 바닥 판 몫
local GAP = M(4) -- 건물 사이 최소 간격(예약 여유) 4 m

-- 층고(실측): 오피스 4.0 m, 주거/상가 혼합 3.3 m
local OFFICE_F = R.OfficeFloor
local MIXED_F = M(3.3)

local HERO = Config.Viewpoint.HeroCamPos
local HERO_LOOK = Config.Viewpoint.HeroCamLook
local DECK = Config.Viewpoint.DeckCenter

type Cluster = { x: number, z: number, r: number, k: number }

-- 다운타운 클러스터(히어로 화면에서 고층 군 사이 빈틈 뒤쪽에 오도록) — 구역 좌표 기준(실제 스케일)
local CLUSTERS_FAR: { Cluster } = {
	{ x = -2500, z = -5400, r = 1030, k = 1.15 }, -- 왼쪽 군과 타워 사이 뒤
	{ x = 4830, z = -5250, r = 1200, k = 1.3 }, -- 오른쪽 군 오른편 뒤
	{ x = -7500, z = -5000, r = 1170, k = 1.2 }, -- 화면 왼쪽 끝
	{ x = 9330, z = -4830, r = 870, k = 0.9 },
	{ x = -4500, z = -9000, r = 1500, k = 1.1 },
	{ x = 7830, z = -9830, r = 1500, k = 1.0 },
	{ x = 2170, z = -8330, r = 1170, k = 0.8 },
	{ x = -11330, z = -9330, r = 1270, k = 0.9 },
	{ x = 13330, z = -8330, r = 1070, k = 0.8 },
}
local CLUSTERS_NEAR: { Cluster } = {
	{ x = -4500, z = 5500, r = 1170, k = 1.2 },
	{ x = 4830, z = 5000, r = 1080, k = 1.0 },
	{ x = 330, z = 7670, r = 1500, k = 0.9 },
	{ x = -8330, z = 7000, r = 1000, k = 0.7 },
}

-- 몸체 색(콘크리트·유리 톤)과 창 불빛(따뜻/차가운 혼합; Facade 가 무작위로 어둡게 함)
-- 해질녘 원경 건물은 어두운 실루엣 + 불빛: 몸체는 어둡게(대기 산란이 밝혀 줌)
local BODY = { rgb(52, 56, 66), P.GlassDeep, rgb(70, 72, 78), rgb(40, 62, 70), rgb(72, 62, 54), rgb(60, 64, 74), rgb(80, 78, 76), rgb(46, 54, 68) }
local LOW_BODY = { rgb(96, 90, 84), rgb(78, 76, 76), rgb(104, 98, 90), rgb(68, 70, 76), rgb(88, 80, 74) }
local LIT_CITY = { P.WindowWarm, P.WindowWarm, P.WindowWarmDim, P.WindowGold, P.WindowCool, P.WindowCoolDim }
local LIT_LOW = { P.WindowWarm, P.WindowWarmDim, P.WindowGold, P.WindowCoolDim, P.WindowWarm, rgb(200, 120, 150) }

------------------------------------------------------------------------------------------------------
-- 보조
------------------------------------------------------------------------------------------------------
local function pick<T>(rng: Random, t: { T }): T
	return t[rng:NextInteger(1, #t)]
end

local function bearing(x: number, z: number): number
	return math.deg(math.atan2(x - HERO.X, HERO.Z - z))
end
local LOOK_BEARING = bearing(HERO_LOOK.X, HERO_LOOK.Z)

-- 롯데타워 + 몰 시야 보호(타워보다 카메라 쪽 저층 채움만 해당)
local GUARD_B0, GUARD_B1 = math.huge, -math.huge
do
	local T, Mall = Config.Landmark.Tower, Config.Landmark.Mall
	local r = T.BaseWidth * 0.75
	for _, c in { { T.Center.X - r, T.Center.Z - r }, { T.Center.X + r, T.Center.Z - r }, { T.Center.X - r, T.Center.Z + r }, { T.Center.X + r, T.Center.Z + r }, { Mall.Min.X, Mall.Min.Y }, { Mall.Max.X, Mall.Min.Y }, { Mall.Min.X, Mall.Max.Y }, { Mall.Max.X, Mall.Max.Y } } do
		local b = bearing(c[1], c[2])
		GUARD_B0 = math.min(GUARD_B0, b - 1.2)
		GUARD_B1 = math.max(GUARD_B1, b + 1.2)
	end
end
local function blocksLandmark(x: number, z: number, r: number): boolean
	if z + r < Config.Landmark.Tower.Center.Z or z > 0 then
		return false
	end
	local b = bearing(x, z)
	local db = math.deg(math.atan2(r, math.max(1, HERO.Z - z)))
	return b + db > GUARD_B0 and b - db < GUARD_B1
end

local function boost(clusters: { Cluster }, x: number, z: number): number
	local b = 0
	for _, c in clusters do
		local dx, dz = (x - c.x) / c.r, (z - c.z) / c.r
		b = math.max(b, c.k * math.exp(-(dx * dx + dz * dz)))
	end
	return b
end

-- 층 단위로 스냅(실제 층수 × 층고 + 옥탑 1.2 m)
local function snapFloors(h: number, floorH: number): number
	return math.max(2, math.floor(h / floorH + 0.5)) * floorH + M(1.2)
end

------------------------------------------------------------------------------------------------------
-- 건물 후보 생성 + 예산 내 배치
------------------------------------------------------------------------------------------------------
type Rect = { XMin: number, XMax: number, ZMin: number, ZMax: number }

type FillOpts = {
	name: string,
	rects: { Rect },
	pitch: number,
	keep: number, -- 셀 사용 확률
	viewer: Vector3,
	frustum: boolean,
	budget: number,
	style: (z: number, h: number, rng: Random) -> string,
	wMin: number,
	wMax: number,
	hMin: number,
	hMax: number,
	hPow: number, -- 높이 분포 지수(클수록 낮은 건물 위주)
	floorH: number,
	clusters: { Cluster }?,
	towerChance: number, -- 클러스터 중심부의 고층 확률
	towerH: { number }, -- {min, max}
	maxTall: number, -- 고층 개수 상한("몇 개만")
	beaconFar: boolean, -- far 스타일 고층에 항공등
	guard: boolean,
	low: boolean, -- 저층 채움(상가/빌라 색)
	maxDist: number?, -- 관람자에서 이보다 먼 후보는 버림(산자락 안/뒤 = 보이지 않음)
}

type Cand = { x: number, z: number, w: number, d: number, h: number, yaw: number, prio: number, idx: number, tall: boolean }

local function fill(parent: Instance, o: FillOpts, rng: Random, hardLeft: number): number
	local density = Config.Quality.Density
	local budget = math.min(o.budget * density, hardLeft)
	local cands: { Cand } = {}
	local pitch = o.pitch / math.sqrt(math.max(0.3, density))
	local hCap = o.hMax * 1.35 -- 클러스터 가산 후 일반 건물 상한
	for _, r in o.rects do
		if r.XMax - r.XMin < pitch * 0.5 or r.ZMax - r.ZMin < pitch * 0.5 then
			continue
		end
		local nx = math.max(1, math.floor((r.XMax - r.XMin) / pitch))
		local nz = math.max(1, math.floor((r.ZMax - r.ZMin) / pitch))
		local px, pz = (r.XMax - r.XMin) / nx, (r.ZMax - r.ZMin) / nz
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				if rng:NextNumber() > o.keep then
					continue
				end
				local x = r.XMin + (i + 0.5) * px + rng:NextNumber(-0.22, 0.22) * px
				local z = r.ZMin + (j + 0.5) * pz + rng:NextNumber(-0.22, 0.22) * pz
				if o.maxDist and (Vector2.new(x, z) - Vector2.new(o.viewer.X, o.viewer.Z)).Magnitude > o.maxDist then
					continue
				end
				local b = if o.clusters then boost(o.clusters, x, z) else 0
				local w = rng:NextNumber(o.wMin, o.wMax)
				local d = math.clamp(w * rng:NextNumber(0.6, 1.25), o.wMin * 0.7, o.wMax)
				local h = o.hMin + (o.hMax - o.hMin) * (rng:NextNumber() ^ o.hPow)
				h = math.min(h * (1 + b * rng:NextNumber(0.4, 0.8)), hCap)
				local tall = false
				if b > 0.5 and rng:NextNumber() < o.towerChance * b then
					h = rng:NextNumber(o.towerH[1], o.towerH[2])
					w = math.min(w, M(rng:NextNumber(30, 45))) -- 고층 평면 30~45 m
					d = math.min(d, w * rng:NextNumber(0.8, 1.0))
					tall = true
				end
				-- 셀보다 크면 줄임
				w = math.min(w, px - GAP * 2)
				d = math.min(d, pz - GAP * 2)
				local yaw = 0
				local ry = rng:NextNumber()
				if ry < 0.12 then
					yaw = rng:NextNumber(-35, 35)
				elseif ry < 0.3 then
					yaw = 90 -- 정사각에 가까운 평면을 돌려 리듬 변화
				end
				local dist = (Vector2.new(x, z) - Vector2.new(o.viewer.X, o.viewer.Z)).Magnitude
				local prio = dist * rng:NextNumber(0.85, 1.2)
				if o.frustum and math.abs(bearing(x, z) - LOOK_BEARING) > 50 then
					prio *= 1.6
				end
				if tall then
					prio *= 0.7 -- 다운타운 고층 우선
				end
				table.insert(cands, { x = x, z = z, w = w, d = d, h = snapFloors(h, if tall then OFFICE_F else o.floorH), yaw = yaw, prio = prio, idx = #cands + 1, tall = tall })
			end
		end
	end
	table.sort(cands, function(a: Cand, b: Cand): boolean
		if a.prio ~= b.prio then
			return a.prio < b.prio
		end
		return a.idx < b.idx
	end)
	local g = Kit.group(parent, o.name)
	local start = Kit.stats.parts
	local n, nTall = 0, 0
	for _, c in cands do
		if Kit.stats.parts - start >= budget then
			break
		end
		local h = c.h
		local tall = c.tall
		if tall and nTall >= o.maxTall then
			tall = false
			h = snapFloors(math.min(h, hCap), o.floorH)
		end
		if not Kit.isFreeRect(c.x, c.z, c.w, c.d, c.yaw, GAP) then
			continue
		end
		if o.guard and blocksLandmark(c.x, c.z, math.max(c.w, c.d) * 0.7) then
			continue
		end
		local style = o.style(c.z, h, rng)
		local body = if o.low then pick(rng, LOW_BODY) else pick(rng, BODY)
		local lit = if o.low then LIT_LOW else LIT_CITY
		local beacon: boolean? = nil
		if style == "far" then
			beacon = tall and o.beaconFar
		end
		local crown: string? = nil
		if tall and rng:NextNumber() < 0.6 then
			crown = "led"
		end
		Facade.tower(g, {
			name = if tall then "Tower" else "Block",
			cf = CFrame.new(c.x, CITY_Y, c.z) * CFrame.Angles(0, math.rad(c.yaw), 0),
			w = c.w,
			d = c.d,
			h = h,
			style = style,
			rng = rng,
			glass = body,
			lit = lit,
			litChance = if style == "far" then 0.72 else 0.8,
			crown = crown,
			ledColor = pick(rng, { P.LedGold, P.LedCyan, P.LedBlue, P.WindowCool }),
			beacon = beacon,
			collide = style ~= "far",
		})
		Kit.reserveRect(c.x, c.z, c.w, c.d, c.yaw, o.name)
		n += 1
		if tall then
			nTall += 1
		end
	end
	g:SetAttribute("Buildings", n)
	g:SetAttribute("Towers", nTall)
	g:SetAttribute("Parts", Kit.stats.parts - start)
	return Kit.stats.parts - start
end

------------------------------------------------------------------------------------------------------
-- 카펫 바닥 판: 도시 지면(Riverside) 밖으로 이어지는 카펫 구간 받침. 도시 지면보다 0.6 낮게 → 겹쳐도 가려짐.
------------------------------------------------------------------------------------------------------
local GROUND_C = rgb(52, 54, 60)
local function groundPad(parent: Instance, x0: number, x1: number, z0: number, z1: number)
	local MAXP = 2000
	local za, zb = math.min(z0, z1), math.max(z0, z1)
	local nx = math.max(1, math.ceil((x1 - x0) / MAXP))
	local nz = math.max(1, math.ceil((zb - za) / MAXP))
	local dx, dz = (x1 - x0) / nx, (zb - za) / nz
	local T = 4
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			Kit.box(parent, CFrame.new(x0 + dx * (i + 0.5), CITY_Y - 0.6 - T / 2, za + dz * (j + 0.5)), Vector3.new(dx, T, dz), GROUND_C, MAT.Concrete, { name = "CarpetGround", shadow = false })
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 산 능선
------------------------------------------------------------------------------------------------------
type RangeOpts = {
	xMin: number,
	xMax: number,
	foot: number, -- 산자락이 땅에 닿는 앞쪽 Z (관람자 쪽 경계)
	away: number, -- 관람자에서 멀어지는 Z 부호(먼 쪽 -1 / 가까운 쪽 +1)
	hMin: number, -- 봉우리 높이(지면 위)
	hMax: number,
	wMin: number, -- 산괴 폭
	wMax: number,
	color: Color3,
	phase: number,
	freq: number,
}

local MOUNTAIN_MAT = MAT.Fabric -- 무광(스페큘러 없음): 노을빛에 모래 언덕처럼 번들거리지 않게

-- 땅에 묻힌 타원체: 지면 위 높이 H, sink = 반높이 중 땅 아래 비율. 앞쪽(관람자 쪽) 가장자리 = footZ.
local function dome(parent: Instance, x: number, footZ: number, away: number, w: number, H: number, d: number, sink: number, c: Color3)
	local halfY = H / (1 - sink)
	local cy = CITY_Y + H - halfY
	local zc = footZ + away * (d / 2) * math.sqrt(1 - sink * sink) -- 지면 단면 반지름만큼 뒤로
	Kit.ellipsoid(parent, CFrame.new(x, cy, zc), Vector3.new(w, halfY * 2, d), c, MOUNTAIN_MAT, { name = "Ridge", shadow = false, query = false, collide = false })
end

local function range(parent: Instance, o: RangeOpts, rng: Random): number
	local n = 0
	local x = o.xMin - rng:NextNumber(0.3, 0.5) * o.wMax
	while x < o.xMax do
		local W = rng:NextNumber(o.wMin, o.wMax)
		local cx = x + W / 2
		local wave = 0.5 + 0.5 * math.sin(cx * o.freq + o.phase) * math.cos(cx * o.freq * 0.41 + o.phase * 1.7)
		local Hp = (o.hMin + (o.hMax - o.hMin) * wave) * rng:NextNumber(0.88, 1.08)
		local foot = o.foot + o.away * rng:NextNumber(0, 0.12) * W
		local tone = o.color:Lerp(rgb(26, 32, 42), rng:NextNumber(0, 0.14))
		-- 산자락(넓고 낮게, 40~48%)
		dome(parent, cx, foot, o.away, W, Hp * rng:NextNumber(0.4, 0.48), W * rng:NextNumber(0.42, 0.55), 0.3, tone)
		n += 1
		-- 봉우리 2~4개 (주봉 1 + 보조봉): 폭/높이 2.2~3.4 → 둥근 모래 언덕이 아니라 솟은 능선
		local np = rng:NextInteger(2, 4)
		for i = 1, np do
			local ph = Hp * (if i == 1 then 1 else rng:NextNumber(0.58, 0.86))
			local pw = ph * rng:NextNumber(2.2, 3.4)
			local px = cx + rng:NextNumber(-0.34, 0.34) * W
			local pf = foot + o.away * rng:NextNumber(0.06, 0.22) * W
			dome(parent, px, pf, o.away, pw, ph, pw * rng:NextNumber(0.6, 0.85), 0.12, tone:Lerp(o.color, 0.5))
			n += 1
		end
		x += W * rng:NextNumber(0.5, 0.72)
	end
	return n
end

local function mountains(parent: Instance, rng: Random)
	local MF, MN = ZN.MountainsFar, ZN.MountainsNear
	local F, N = Config.FarBank, Config.NearBank
	-- 대기 원근: 먼 겹일수록 밝고 푸른 회색. 기준 팔레트 Mountain / MountainFar.
	local farBack = P.MountainFar:Lerp(rgb(104, 116, 140), 0.35)
	local farMid = P.MountainFar
	local farFront = P.Mountain
	local far = Kit.group(parent, "MountainsFar")
	local frontFoot = math.min(F.CityTo - M(150), MF.Z + M(600))
	-- 먼 겹 → 가까운 겹 (그리기 순서와 무관하지만 읽기 쉽게). 높이 300~600 m, 산괴 폭 3~8 km
	range(far, { xMin = MF.XMin, xMax = MF.XMax, foot = MF.Z - M(800), away = -1, hMin = M(430), hMax = M(600), wMin = M(5000), wMax = M(8000), color = farBack, phase = 1.3, freq = 1 / 4200 }, rng)
	range(far, { xMin = MF.XMin, xMax = MF.XMax, foot = MF.Z, away = -1, hMin = M(340), hMax = M(520), wMin = M(4000), wMax = M(6500), color = farMid, phase = 4.1, freq = 1 / 3300 }, rng)
	range(far, { xMin = MF.XMin * 0.8, xMax = MF.XMax * 0.8, foot = frontFoot, away = -1, hMin = M(220), hMax = M(380), wMin = M(3000), wMax = M(5000), color = farFront, phase = 2.6, freq = 1 / 2600 }, rng)
	local near = Kit.group(parent, "MountainsNear")
	local nearFoot = math.max(N.CityTo + M(150), MN.Z - M(500))
	range(near, { xMin = MN.XMin, xMax = MN.XMax, foot = MN.Z + M(600), away = 1, hMin = M(400), hMax = M(580), wMin = M(4500), wMax = M(7500), color = farMid, phase = 0.4, freq = 1 / 3800 }, rng)
	range(near, { xMin = MN.XMin * 0.85, xMax = MN.XMax * 0.85, foot = nearFoot, away = 1, hMin = M(250), hMax = M(400), wMin = M(3000), wMax = M(5000), color = farFront, phase = 3.3, freq = 1 / 2800 }, rng)
end

------------------------------------------------------------------------------------------------------
-- 진입점
------------------------------------------------------------------------------------------------------
function CityCarpet.build(ctx: any)
	local model: Model = ctx.model
	local rng: Random = ctx.rng
	local start = Kit.stats.parts
	local function left(): number
		return BUDGET_TOTAL - RESERVE_TAIL - (Kit.stats.parts - start)
	end
	local deckView = Vector3.new(DECK.X, Config.Viewpoint.DeckHeight, DECK.Z)
	local AF, AN = ZN.ApartmentsFar, ZN.ApartmentsNear
	local CFM, CFF, CN = ZN.CarpetFarMid, ZN.CarpetFarFar, ZN.CarpetNear
	local F, N = Config.FarBank, Config.NearBank

	-- 1) 중경(먼 쪽): mid — 8~30층(25~90 m), 클러스터 중심에 40~60층(160~240 m) 몇 개
	fill(model, {
		name = "FarMid",
		rects = { CFM },
		pitch = M(75),
		keep = 0.92,
		viewer = HERO,
		frustum = true,
		budget = BUDGET.FarMid,
		style = function(_z: number, _h: number, _r: Random): string
			return "mid"
		end,
		wMin = M(18),
		wMax = M(45),
		hMin = M(25),
		hMax = M(90),
		hPow = 1.7,
		floorH = MIXED_F,
		clusters = CLUSTERS_FAR,
		towerChance = 0.45,
		towerH = { M(160), M(240) },
		maxTall = 7,
		beaconFar = true,
		guard = false,
		low = false,
	}, rng, left())

	-- 2) 원경(먼 쪽): far — 5~25층(16~80 m), 블록 단위로 크게
	fill(model, {
		name = "FarFar",
		rects = { CFF },
		pitch = M(88),
		keep = 0.9,
		viewer = HERO,
		frustum = true,
		budget = BUDGET.FarFar,
		style = function(_z: number, _h: number, _r: Random): string
			return "far"
		end,
		wMin = M(22),
		wMax = M(60),
		hMin = M(16),
		hMax = M(80),
		hPow = 1.5,
		floorH = MIXED_F,
		clusters = CLUSTERS_FAR,
		towerChance = 0.35,
		towerH = { M(140), M(220) },
		maxTall = 6,
		beaconFar = true,
		guard = false,
		low = false,
	}, rng, left())

	-- 3) 관람자 뒤쪽 도시: 가까운 줄 mid, 먼 줄 far
	local midUntil = CN.ZMin + (CN.ZMax - CN.ZMin) * 0.33
	fill(model, {
		name = "Near",
		rects = { CN },
		pitch = M(88),
		keep = 0.88,
		viewer = deckView,
		frustum = false,
		budget = BUDGET.Near,
		style = function(z: number, h: number, r: Random): string
			if z < midUntil or (h > M(120) and r:NextNumber() < 0.5) then
				return "mid"
			end
			return "far"
		end,
		wMin = M(18),
		wMax = M(55),
		hMin = M(16),
		hMax = M(80),
		hPow = 1.6,
		floorH = MIXED_F,
		clusters = CLUSTERS_NEAR,
		towerChance = 0.4,
		towerH = { M(150), M(220) },
		maxTall = 4,
		beaconFar = true,
		guard = false,
		low = false,
	}, rng, left())

	-- 4) 저층 채움: 아파트 띠의 빈 블록 + 아파트 띠 바깥 옆 구간 (먼 쪽 / 가까운 쪽) — 2~10층 상가/빌라
	local function lowStyle(_z: number, _h: number, _r: Random): string
		return "mid"
	end
	local function infill(name: string, rects: { Rect }, viewer: Vector3, frustum: boolean, budget: number)
		fill(model, {
			name = name,
			rects = rects,
			pitch = M(60),
			keep = 0.8,
			viewer = viewer,
			frustum = frustum,
			budget = budget,
			style = lowStyle,
			wMin = M(13),
			wMax = M(32),
			hMin = M(8),
			hMax = M(30),
			hPow = 1.3,
			floorH = MIXED_F,
			clusters = nil,
			towerChance = 0,
			towerH = { M(30), M(30) },
			maxTall = 0,
			beaconFar = false,
			guard = frustum,
			low = true,
		}, rng, left())
	end
	infill("InfillFar", {
		AF,
		{ XMin = CFM.XMin, XMax = AF.XMin, ZMin = AF.ZMin, ZMax = F.CityFrom },
		{ XMin = AF.XMax, XMax = CFM.XMax, ZMin = AF.ZMin, ZMax = F.CityFrom },
	}, HERO, true, BUDGET.Infill * 0.72)
	infill("InfillNear", {
		AN,
		{ XMin = CN.XMin, XMax = AN.XMin, ZMin = N.CityFrom, ZMax = CN.ZMin },
		{ XMin = AN.XMax, XMax = CN.XMax, ZMin = N.CityFrom, ZMax = CN.ZMin },
	}, deckView, false, BUDGET.Infill * 0.28)

	-- 5) 카펫 바닥 판(도시 지면 바깥 좌우 구간): 먼 쪽 |X| 8800 ~ CarpetFarFar 끝, 가까운 쪽 |X| 6300 ~ CarpetNear 끝
	local pads = Kit.group(model, "CarpetGround")
	local farX = math.max(CFF.XMax, CFM.XMax)
	groundPad(pads, -farX, -8800, F.CityFrom, F.CityTo)
	groundPad(pads, 8800, farX, F.CityFrom, F.CityTo)
	groundPad(pads, CN.XMin, -6300, N.CityFrom, N.CityTo)
	groundPad(pads, 6300, CN.XMax, N.CityFrom, N.CityTo)

	-- 6) 원경 산 능선
	mountains(Kit.group(model, "Mountains"), rng)

	model:SetAttribute("Parts", Kit.stats.parts - start)
	print(string.format("[CityCarpet] 파트 %d", Kit.stats.parts - start))
end

return CityCarpet
