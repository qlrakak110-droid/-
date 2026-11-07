--!strict
-- SeoulSkyline / CityCarpet
-- 지평선까지 이어지는 LOD 도시 카펫 + 원경 산 능선.
--   * CarpetFarMid  : Facade "mid"(몸체 + 층 불빛 띠) h 40~180, 다운타운 클러스터에서 200~260 고층(항공등)
--   * CarpetFarFar  : Facade "far"(몸체 + 불빛 띠 1) h 30~160, 클러스터에서 가끔 높은 원경 타워(항공등)
--   * CarpetNear    : 관람자 뒤쪽 도시 — 가까운 줄은 "mid", 먼 줄은 "far"
--   * Infill        : 아파트 띠의 빈 블록 + 아파트 띠 바깥 옆 구간을 저층 상가/빌라(h 14~46)로 메움
--   * 높이는 몇 개의 "다운타운" 클러스터(가우시안)에서 솟아 원경 스카이라인이 평평한 벽이 되지 않게 함
--   * 배치: 지터 격자 후보 → 우선순위(관람자 거리 × 화면 밖 가중 × 잡음) 순으로 예산까지 → 멀수록 자연스럽게 성기게
--   * 모든 발자국 Kit.isFreeRect 검사 + Kit.reserveRect. 실제 광원 0개.
--   * 산: Kit.ellipsoid 타원체를 겹쳐 3겹(먼 쪽) / 2겹(가까운 쪽) 능선 — 땅 아래로 30% 묻고, 먼 겹일수록 밝은 청회색.

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)
local Facade = require(script.Parent.Facade)

local CityCarpet = {}

local rgb = Color3.fromRGB
local P = Config.Palette
local ZN = Config.Zones
local CITY_Y = Config.Level.City
local BLACK = Color3.new(0, 0, 0)
local MAT = Enum.Material

------------------------------------------------------------------------------------------------------
-- 상수
------------------------------------------------------------------------------------------------------
local BUDGET_TOTAL = 5500 -- 모듈 하드 캡
local BUDGET = { FarMid = 2150, FarFar = 1550, Near = 1150, Infill = 420 } -- 구역별(밀도 배율 적용 전)
local GAP = 8 -- 건물 사이 최소 간격(예약 여유)

local HERO = Config.Viewpoint.HeroCamPos
local HERO_LOOK = Config.Viewpoint.HeroCamLook
local DECK = Config.Viewpoint.DeckCenter

type Cluster = { x: number, z: number, r: number, k: number }

-- 다운타운 클러스터(히어로 화면에서 고층 군 사이 빈틈 뒤쪽에 오도록)
local CLUSTERS_FAR: { Cluster } = {
	{ x = -1500, z = -3250, r = 620, k = 1.15 }, -- 왼쪽 군과 타워 사이 뒤
	{ x = 2900, z = -3150, r = 720, k = 1.3 }, -- 오른쪽 군 오른편 뒤
	{ x = -4500, z = -3000, r = 700, k = 1.2 }, -- 화면 왼쪽 끝
	{ x = 5600, z = -2900, r = 520, k = 0.9 },
	{ x = -2700, z = -5400, r = 900, k = 1.1 },
	{ x = 4700, z = -5900, r = 900, k = 1.0 },
	{ x = 1300, z = -5000, r = 700, k = 0.8 },
	{ x = -6800, z = -5600, r = 760, k = 0.9 },
	{ x = 8000, z = -5000, r = 640, k = 0.8 },
}
local CLUSTERS_NEAR: { Cluster } = {
	{ x = -2700, z = 3300, r = 700, k = 1.2 },
	{ x = 2900, z = 3000, r = 650, k = 1.0 },
	{ x = 200, z = 4600, r = 900, k = 0.9 },
	{ x = -5000, z = 4200, r = 600, k = 0.7 },
}

-- 몸체 색(콘크리트·유리 톤)과 창 불빛(따뜻/차가운 혼합; Facade 가 무작위로 어둡게 함)
local BODY = { P.ConcreteDark, P.GlassDeep, P.ConcreteGrey, P.GlassTeal, P.GlassBronze, rgb(70, 74, 84), rgb(104, 100, 96), rgb(58, 66, 80) }
local LOW_BODY = { rgb(118, 110, 102), rgb(96, 92, 90), rgb(132, 124, 112), rgb(84, 86, 92), rgb(110, 100, 92) }
local LIT_CITY = { P.WindowWarm, P.WindowWarm, P.WindowWarmDim, P.WindowGold, P.WindowCool, P.WindowCoolDim }
local LIT_LOW = { P.WindowWarm, P.WindowCool, P.WindowGold, P.LedCyan, P.WindowWarmDim, rgb(240, 120, 160) }

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
	local T, M = Config.Landmark.Tower, Config.Landmark.Mall
	local r = T.BaseWidth * 0.75
	for _, c in { { T.Center.X - r, T.Center.Z - r }, { T.Center.X + r, T.Center.Z - r }, { T.Center.X - r, T.Center.Z + r }, { T.Center.X + r, T.Center.Z + r }, { M.Min.X, M.Min.Y }, { M.Max.X, M.Min.Y }, { M.Min.X, M.Max.Y }, { M.Max.X, M.Max.Y } } do
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
	clusters: { Cluster }?,
	towerChance: number, -- 클러스터 중심부의 고층 확률
	towerH: { number }, -- {min, max}
	beaconFar: boolean, -- far 스타일 고층에 항공등
	guard: boolean,
	low: boolean, -- 저층 채움(상가/빌라 색)
}

type Cand = { x: number, z: number, w: number, d: number, h: number, yaw: number, prio: number, idx: number, tall: boolean }

local function fill(parent: Instance, o: FillOpts, rng: Random, hardLeft: number): number
	local density = Config.Quality.Density
	local budget = math.min(o.budget * density, hardLeft)
	local cands: { Cand } = {}
	local pitch = o.pitch / math.sqrt(math.max(0.3, density))
	for _, r in o.rects do
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
				local b = if o.clusters then boost(o.clusters, x, z) else 0
				local w = rng:NextNumber(o.wMin, o.wMax)
				local d = math.clamp(w * rng:NextNumber(0.6, 1.25), o.wMin * 0.7, o.wMax)
				local h = o.hMin + (o.hMax - o.hMin) * (rng:NextNumber() ^ o.hPow)
				h *= 1 + b * rng:NextNumber(0.5, 1.0)
				local tall = false
				if b > 0.45 and rng:NextNumber() < o.towerChance * b then
					h = rng:NextNumber(o.towerH[1], o.towerH[2])
					w = math.min(w, rng:NextNumber(40, 66))
					d = math.min(d, w * rng:NextNumber(0.8, 1.0))
					tall = true
				end
				h = math.min(h, o.towerH[2])
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
				table.insert(cands, { x = x, z = z, w = w, d = d, h = h, yaw = yaw, prio = prio, idx = #cands + 1, tall = tall })
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
	local n = 0
	for _, c in cands do
		if Kit.stats.parts - start >= budget then
			break
		end
		if not Kit.isFreeRect(c.x, c.z, c.w, c.d, c.yaw, GAP) then
			continue
		end
		if o.guard and blocksLandmark(c.x, c.z, math.max(c.w, c.d) * 0.7) then
			continue
		end
		local style = o.style(c.z, c.h, rng)
		local body = if o.low then pick(rng, LOW_BODY) else pick(rng, BODY)
		local lit = if o.low then LIT_LOW else LIT_CITY
		local beacon: boolean? = nil
		if style == "far" then
			beacon = c.tall and o.beaconFar
		end
		local crown: string? = nil
		if c.tall and rng:NextNumber() < 0.6 then
			crown = "led"
		end
		Facade.tower(g, {
			name = if c.tall then "Tower" else "Block",
			cf = CFrame.new(c.x, CITY_Y, c.z) * CFrame.Angles(0, math.rad(c.yaw), 0),
			w = c.w,
			d = c.d,
			h = c.h,
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
	end
	g:SetAttribute("Buildings", n)
	g:SetAttribute("Parts", Kit.stats.parts - start)
	return Kit.stats.parts - start
end

------------------------------------------------------------------------------------------------------
-- 산 능선
------------------------------------------------------------------------------------------------------
type RidgeOpts = {
	xMin: number,
	xMax: number,
	z: number,
	zJit: number,
	hMin: number,
	hMax: number,
	wMin: number,
	wMax: number,
	color: Color3,
	material: Enum.Material,
	phase: number,
	freq: number,
	sink: number, -- 타원체 반높이 중 땅 아래로 묻는 비율
}

local function ridge(parent: Instance, o: RidgeOpts, rng: Random): number
	local n = 0
	local x = o.xMin - rng:NextNumber(0.2, 0.5) * o.wMax
	while x < o.xMax + o.wMax * 0.3 do
		local w = rng:NextNumber(o.wMin, o.wMax)
		-- 저주파 높이(산괴) × 잡음
		local wave = 0.5 + 0.5 * math.sin(x * o.freq + o.phase) * math.cos(x * o.freq * 0.37 + o.phase * 1.7)
		local H = (o.hMin + (o.hMax - o.hMin) * wave) * rng:NextNumber(0.82, 1.12)
		local halfY = H / (1 - o.sink)
		local cy = CITY_Y + H - halfY
		local dz = w * rng:NextNumber(0.45, 0.75)
		local c = o.color:Lerp(rgb(30, 38, 48), rng:NextNumber(0, 0.12))
		Kit.ellipsoid(parent, CFrame.new(x + w * 0.5, cy, o.z + rng:NextNumber(-o.zJit, o.zJit)), Vector3.new(w, halfY * 2, dz), c, o.material, { name = "Ridge", shadow = false, query = false, collide = false })
		n += 1
		x += w * rng:NextNumber(0.36, 0.55)
	end
	return n
end

local function mountains(parent: Instance, rng: Random)
	local MF, MN = ZN.MountainsFar, ZN.MountainsNear
	local far = Kit.group(parent, "MountainsFar")
	-- 먼 겹 → 가까운 겹 (먼 겹일수록 높고 밝은 청회색)
	ridge(far, { xMin = MF.XMin, xMax = MF.XMax, z = MF.Z - 900, zJit = 200, hMin = 480, hMax = 900, wMin = 1800, wMax = 3000, color = P.MountainFar:Lerp(rgb(120, 128, 150), 0.25), material = MAT.Rock, phase = 1.3, freq = 1 / 2100, sink = 0.3 }, rng)
	ridge(far, { xMin = MF.XMin, xMax = MF.XMax, z = MF.Z, zJit = 220, hMin = 340, hMax = 680, wMin = 1300, wMax = 2600, color = P.MountainFar, material = MAT.Grass, phase = 4.1, freq = 1 / 1700, sink = 0.3 }, rng)
	ridge(far, { xMin = MF.XMin, xMax = MF.XMax, z = MF.Z + 700, zJit = 180, hMin = 220, hMax = 430, wMin = 900, wMax = 1900, color = P.Mountain, material = MAT.Grass, phase = 2.6, freq = 1 / 1300, sink = 0.3 }, rng)
	local near = Kit.group(parent, "MountainsNear")
	ridge(near, { xMin = MN.XMin, xMax = MN.XMax, z = MN.Z + 700, zJit = 200, hMin = 420, hMax = 820, wMin = 1600, wMax = 2800, color = P.MountainFar, material = MAT.Rock, phase = 0.4, freq = 1 / 1900, sink = 0.3 }, rng)
	ridge(near, { xMin = MN.XMin, xMax = MN.XMax, z = MN.Z, zJit = 200, hMin = 260, hMax = 520, wMin = 1000, wMax = 2200, color = P.Mountain, material = MAT.Grass, phase = 3.3, freq = 1 / 1500, sink = 0.3 }, rng)
end

------------------------------------------------------------------------------------------------------
-- 진입점
------------------------------------------------------------------------------------------------------
function CityCarpet.build(ctx: any)
	local model: Model = ctx.model
	local rng: Random = ctx.rng
	local start = Kit.stats.parts
	local function left(): number
		return BUDGET_TOTAL - 130 - (Kit.stats.parts - start) -- 산 몫 남겨 둠
	end
	local deckView = Vector3.new(DECK.X, Config.Viewpoint.DeckHeight, DECK.Z)
	local AF, AN = ZN.ApartmentsFar, ZN.ApartmentsNear
	local F, N = Config.FarBank, Config.NearBank

	-- 1) 중경(먼 쪽): mid
	fill(model, {
		name = "FarMid",
		rects = { ZN.CarpetFarMid },
		pitch = 150,
		keep = 0.92,
		viewer = HERO,
		frustum = true,
		budget = BUDGET.FarMid,
		style = function(_z: number, _h: number, _r: Random): string
			return "mid"
		end,
		wMin = 34,
		wMax = 92,
		hMin = 40,
		hMax = 180,
		hPow = 1.7,
		clusters = CLUSTERS_FAR,
		towerChance = 0.5,
		towerH = { 200, 260 },
		beaconFar = true,
		guard = false,
		low = false,
	}, rng, left())

	-- 2) 원경(먼 쪽): far — 블록 단위로 크게
	fill(model, {
		name = "FarFar",
		rects = { ZN.CarpetFarFar },
		pitch = 175,
		keep = 0.9,
		viewer = HERO,
		frustum = true,
		budget = BUDGET.FarFar,
		style = function(_z: number, _h: number, _r: Random): string
			return "far"
		end,
		wMin = 50,
		wMax = 140,
		hMin = 30,
		hMax = 160,
		hPow = 1.5,
		clusters = CLUSTERS_FAR,
		towerChance = 0.35,
		towerH = { 170, 240 },
		beaconFar = true,
		guard = false,
		low = false,
	}, rng, left())

	-- 3) 관람자 뒤쪽 도시: 가까운 줄 mid, 먼 줄 far
	local NZ = ZN.CarpetNear
	fill(model, {
		name = "Near",
		rects = { NZ },
		pitch = 175,
		keep = 0.88,
		viewer = deckView,
		frustum = false,
		budget = BUDGET.Near,
		style = function(z: number, h: number, r: Random): string
			if z < 3000 or (h > 150 and r:NextNumber() < 0.5) then
				return "mid"
			end
			return "far"
		end,
		wMin = 36,
		wMax = 110,
		hMin = 30,
		hMax = 150,
		hPow = 1.6,
		clusters = CLUSTERS_NEAR,
		towerChance = 0.4,
		towerH = { 180, 240 },
		beaconFar = true,
		guard = false,
		low = false,
	}, rng, left())

	-- 4) 저층 채움: 아파트 띠의 빈 블록 + 아파트 띠 바깥 옆 구간
	fill(model, {
		name = "Infill",
		rects = {
			AF,
			{ XMin = -6500, XMax = AF.XMin, ZMin = AF.ZMin, ZMax = F.CityFrom },
			{ XMin = AF.XMax, XMax = 6500, ZMin = AF.ZMin, ZMax = F.CityFrom },
			AN,
			{ XMin = -6000, XMax = AN.XMin, ZMin = N.CityFrom, ZMax = ZN.CarpetNear.ZMin },
			{ XMin = AN.XMax, XMax = 6000, ZMin = N.CityFrom, ZMax = ZN.CarpetNear.ZMin },
		},
		pitch = 120,
		keep = 0.8,
		viewer = HERO,
		frustum = true,
		budget = BUDGET.Infill,
		style = function(_z: number, _h: number, _r: Random): string
			return "mid"
		end,
		wMin = 26,
		wMax = 64,
		hMin = 14,
		hMax = 46,
		hPow = 1.3,
		clusters = nil,
		towerChance = 0,
		towerH = { 46, 46 },
		beaconFar = false,
		guard = true,
		low = true,
	}, rng, left())

	-- 5) 원경 산 능선
	mountains(Kit.group(model, "Mountains"), rng)

	model:SetAttribute("Parts", Kit.stats.parts - start)
	print(string.format("[CityCarpet] 파트 %d", Kit.stats.parts - start))
end

return CityCarpet
