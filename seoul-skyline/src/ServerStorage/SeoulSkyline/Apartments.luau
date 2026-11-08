--!strict
-- SeoulSkyline / Apartments
-- 한국형 아파트 단지 — 먼 쪽 잠실 강변 띠(ApartmentsFar) + 관람자 뒤 강북 띠(ApartmentsNear). 실제 스케일(1 stud = 0.3 m).
--   * 판상 동: 길이 40~70 m(137~227 stud) × 깊이 12~15 m(40~50 stud), 15~35층, 층고 2.9 m(Config.Real.HomeFloor)
--     + 필로티 3.5 m → 높이 = 필로티 + 층수 × 2.9 m + 옥상 파라펫 1.2 m (15층 ≈ 48 m, 35층 ≈ 106 m).
--   * 신축 타워형 단지: 35~49층(층고 3.0 m, 높이 110~153 m), 평면 26~36 m, 원형/커튼월 + 왕관 프레임.
--   * 단지 = 같은 벽색 + 측벽 슈퍼그래픽 강조색 + 동 번호("101동", 대단지 "1201동" — 글자 높이 3 m)를 공유하는 4~10동.
--     동 간격: 앞뒤 30~50 m(인동 거리, 높이에 비례), 좌우 10~22 m. 단지(로트) 사이 도로 = 4차로(3.5 m) + 보도 3 m × 2.
--   * 모든 동/잔디/상가/나무는 Kit.isFreeRect 검사 후 Kit.reserveRect (앞서 빌드된 랜드마크·고층·도로를 피함).
--   * LOD: 히어로 카메라/전망대에서 가까운 단지부터 "full"(Facade apartment: 층 슬래브·세대 벽·동 번호) →
--     "lite"(벽색 몸체 + 층 묶음 불빛 + 발코니 띠) → "min"(몸체 + 불빛 면 하나 + 꺼진 세대 몇 개). 파트 예산 안에서 계획.
--   * 강변 앞줄은 밀도를 낮추고(몇 개 대단지만), 히어로 구도에서 롯데타워·몰 앞을 가리는 동은 배치하지 않음.
--   * 실제 광원 0개 — 불빛은 모두 Neon(glow 태그로 낮/밤 전환).

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)
local Facade = require(script.Parent.Facade)

local Apartments = {}

local rgb = Color3.fromRGB
local P = Config.Palette
local ZN = Config.Zones
local R = Config.Real
local M = Config.m
local CITY_Y = Config.Level.City
local BLACK = Color3.new(0, 0, 0)
local MAT = Enum.Material

------------------------------------------------------------------------------------------------------
-- 상수 (실측 m → stud)
------------------------------------------------------------------------------------------------------
local BUDGET_TOTAL = 9000 -- 모듈 전체 파트 상한(하드 캡)
local BUDGET_FAR = 7050 -- 먼 쪽 띠 계획 예산(추정치는 실제보다 ~10% 큼)
local BUDGET_NEAR = 2700 -- 가까운 쪽 띠
local FULL_FAR = 3300 -- 먼 쪽 정밀 모델 예산
local FULL_NEAR = 1250
local FULL_RANGE_FAR = 4700 -- 히어로 카메라 가중 거리 이내 단지만 정밀
local FULL_RANGE_NEAR = 1900 -- 전망대 거리
local LITE_RANGE_FAR = 7800 -- 이보다 멀면 min LOD
local LITE_RANGE_NEAR = 3200

local FLOOR_H = R.HomeFloor -- 아파트 층고 2.9 m (Facade apartment 기본값과 동일)
local PILOTIS = FLOOR_H * 1.2 -- 필로티 3.5 m (Facade 와 동일)
local PARAPET = FLOOR_H * 0.4 -- 옥상 파라펫 슬래브 1.2 m
local TOWER_FLOOR_H = M(3.0) -- 신축 타워형 층고 3.0 m
local TOWER_LOBBY = 20 -- Facade curtain/round 로비 높이(6 m) — 타워 높이 계산용
local UNIT = 15 -- Facade apartment 세대 벽 간격(4.5 m) 기본값
local PAD = M(3) -- 동 둘레 보도 여유(예약)
local STREET = R.Lane * 4 + M(3) * 2 -- 로트 사이 도로: 4차로 + 양쪽 보도 = 20 m
local LAWN_T = 0.5 -- 단지 잔디 두께(도시 지면 위)
local LAWN_MX, LAWN_MZ = M(10), M(12) -- 동 배열 둘레 잔디/산책로 여유
local SHOP_ROOM = M(18) -- 단지 상가 자리(로트 안에서 비워 둠)
local SHOP_GAP = M(4)
local END_W = M(0.6) -- 경량 모델 측벽 두께
local LABEL_H = M(3) -- 동 번호 글자 높이 3 m

local HERO = Config.Viewpoint.HeroCamPos
local HERO_LOOK = Config.Viewpoint.HeroCamLook
local DECK = Config.Viewpoint.DeckCenter

-- 단지 벽색(크림·베이지·연회색·아이보리) / 슈퍼그래픽 강조색
local WALLS = {
	rgb(224, 218, 206),
	rgb(208, 198, 182),
	rgb(214, 212, 206),
	rgb(228, 216, 196),
	rgb(198, 192, 186),
	rgb(212, 200, 190),
	rgb(190, 196, 200),
	rgb(220, 206, 186),
}
local ACCENTS = {
	rgb(58, 104, 158),
	rgb(36, 58, 96),
	rgb(166, 90, 62),
	rgb(82, 122, 80),
	rgb(210, 136, 56),
	rgb(112, 82, 136),
	rgb(64, 142, 152),
	rgb(146, 48, 54),
}
-- 신축 타워 유리/프레임
local TOWER_GLASS = { P.GlassSilver, P.GlassBlue, P.GlassTeal, rgb(118, 112, 104), P.GlassDeep }
local TOWER_FRAME = { P.MullionLight, rgb(204, 198, 186), P.Mullion, rgb(150, 132, 104) }
-- 옥상 LED 는 블룸 대비 어둡게(멀리서 지붕 전체가 번쩍이지 않게)
local CROWN_LED = { rgb(150, 110, 52), rgb(52, 120, 140), rgb(44, 86, 150), rgb(160, 120, 70), rgb(120, 130, 150) }
-- 단지 상가 간판
local SIGNS = { rgb(90, 200, 230), rgb(220, 96, 180), rgb(236, 236, 224), rgb(240, 190, 90), rgb(110, 220, 140), rgb(250, 120, 90) }
local LEAVES = { P.Leaf1, P.Leaf2, rgb(40, 70, 46), rgb(52, 80, 46) }

-- 창 조명: Facade.LIT_HOME 을 블룸 대비 한 톤 낮춤(넓은 Neon 면 → 은은하게) + 일부 단지는 LED 흰빛 섞음
local function dim(c: Color3, k: number): Color3
	return c:Lerp(BLACK, k)
end
local function dimList(t: { Color3 }, k: number): { Color3 }
	local out = {}
	for i, c in t do
		out[i] = dim(c, k)
	end
	return out
end
local LIT_WARM = dimList(Facade.LIT_HOME, 0.36)
local LIT_MIXED = dimList({ P.WindowWarm, P.WindowGold, P.WindowCoolDim, P.WindowCool, P.WindowWarmDim }, 0.38)
local LIT_LITE = dimList(Facade.LIT_HOME, 0.3) -- 경량 모델 세대 줄(면적이 작아 조금 밝게)

------------------------------------------------------------------------------------------------------
-- 타입
------------------------------------------------------------------------------------------------------
type Zone = { XMin: number, XMax: number, ZMin: number, ZMax: number }

type Slab = {
	x: number,
	z: number,
	w: number,
	d: number,
	h: number,
	floors: number,
	yaw: number,
	style: string, -- "apartment" | "curtain" | "round"
	label: string,
}

type Extra = { kind: string, x: number, z: number, w: number, d: number, h: number, yaw: number, color: Color3 }

type Complex = {
	name: string,
	kind: string, -- "slab" | "tower"
	lod: string, -- "full" | "lite" | "min"
	wall: Color3,
	accent: Color3,
	dark: Color3,
	glass: Color3,
	frame: Color3,
	led: Color3,
	crown: string?,
	lit: { Color3 },
	litChance: number,
	slabs: { Slab },
	extras: { Extra },
	lawn: { number }?, -- cx, cz, w, d, yaw
	cost: number,
}

type Lot = { x0: number, z0: number, x1: number, z1: number, prio: number, idx: number }

type ZoneOpts = {
	key: string,
	zone: Zone,
	pitchX: number,
	pitchZ: number,
	viewer: Vector3, -- 우선순위 기준점(히어로 카메라 / 전망대)
	frustum: boolean, -- true: 히어로 화면 밖 로트는 우선순위 낮춤
	budget: number,
	fullBudget: number,
	fullRange: number,
	liteRange: number,
	towerChance: number,
	waterZ: number, -- 강변 앞줄 경계(이보다 강 쪽 = 앞줄)
	waterSign: number, -- 강 방향(+1 = +Z)
	labelFace: number, -- 동 번호 면이 향할 Z 방향(+1 = +Z)
	guard: boolean,
}

------------------------------------------------------------------------------------------------------
-- 보조
------------------------------------------------------------------------------------------------------
local function pick<T>(rng: Random, t: { T }): T
	return t[rng:NextInteger(1, #t)]
end

local function jitter(rng: Random, c: Color3, amt: number): Color3
	local k = 1 + (rng:NextNumber() * 2 - 1) * amt
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

-- 히어로 카메라 기준 수평 방위각(도): 오른쪽(+X) = +
local function bearing(x: number, z: number): number
	return math.deg(math.atan2(x - HERO.X, HERO.Z - z))
end
local LOOK_BEARING = bearing(HERO_LOOK.X, HERO_LOOK.Z)

-- 타워 시야 보호: 히어로 카메라에서 롯데타워 + 몰을 덮는 방위각 구간 (타워보다 카메라 쪽에 있는 동만 거부)
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
local GUARD_Z = Config.Landmark.Tower.Center.Z

local function blocksLandmark(x0: number, z0: number, x1: number, z1: number): boolean
	if math.max(z0, z1) < GUARD_Z then
		return false
	end
	local bmin, bmax = math.huge, -math.huge
	for _, c in { { x0, z0 }, { x1, z0 }, { x0, z1 }, { x1, z1 } } do
		local b = bearing(c[1], c[2])
		bmin = math.min(bmin, b)
		bmax = math.max(bmax, b)
	end
	return bmax > GUARD_B0 and bmin < GUARD_B1
end

-- 회전된 사각형이 구역 안에 완전히 들어가는가
local function insideZone(zone: Zone, x: number, z: number, w: number, d: number, yaw: number): boolean
	local x0, z0, x1, z1 = Kit.rotatedAABB(x, z, w, d, yaw)
	return x0 >= zone.XMin and x1 <= zone.XMax and z0 >= zone.ZMin and z1 <= zone.ZMax
end

local function placeable(o: ZoneOpts, x: number, z: number, w: number, d: number, yaw: number): boolean
	if not insideZone(o.zone, x, z, w, d, yaw) then
		return false
	end
	if not Kit.isFreeRect(x, z, w, d, yaw) then
		return false
	end
	if o.guard then
		local x0, z0, x1, z1 = Kit.rotatedAABB(x, z, w, d, yaw)
		if blocksLandmark(x0, z0, x1, z1) then
			return false
		end
	end
	return true
end

-- 판상 동 높이: 필로티 + 층수 × 층고 + 옥상 파라펫(Facade 의 마지막 슬래브가 딱 맞게)
local function slabHeight(floors: number): number
	return PILOTIS + floors * FLOOR_H + PARAPET
end
local function towerHeight(floors: number): number
	return TOWER_LOBBY + 1.6 + floors * TOWER_FLOOR_H
end

-- 정밀 모델 파트 수 추정(계획 단계 예산용; 실제 수는 빌드 때 측정)
local function estFull(s: Slab, lc: number, crown: string?): number
	if s.style == "apartment" then
		local nu = math.max(2, math.floor(s.w / UNIT))
		local n = s.floors
		return 14 + n + math.ceil(n / 4.5) + nu + math.min(30, math.floor(n * nu * (1 - lc) / 3)) + (if crown then 7 else 0)
	end
	local n = s.floors
	if s.style == "round" then
		return 12 + n + math.ceil(n / 4.5)
	end
	local bay = if s.w > 90 then 12 else 10
	local nx = math.max(1, math.floor(s.w / bay))
	local nz = math.max(1, math.floor(s.d / bay))
	return 18 + n + math.ceil(n / 4.5) + nx + nz + math.min(26, math.floor(n * (nx + nz) * (1 - lc) / 9))
end

-- 경량 동 구성: 발코니 띠 간격(층) / 꺼진 세대 패치 수
local function bandStep(floors: number): number
	return if floors <= 18 then 2 else 3
end
local function nOff(s: Slab, lc: number): number
	local nu = math.max(2, math.floor((s.w - 2 * END_W) / UNIT))
	return math.clamp(math.floor(s.floors * nu * (1 - lc) / 16), 2, 7)
end

local function estLite(s: Slab, lc: number, crown: string?): number
	if s.style ~= "apartment" then
		return 3 + math.clamp(math.floor(s.h / 36), 1, 6)
	end
	return 6 + math.floor(s.floors / bandStep(s.floors)) + nOff(s, lc) + (if crown then 1 else 0)
end

local function estMin(s: Slab): number
	if s.style ~= "apartment" then
		return 3
	end
	return 6
end

------------------------------------------------------------------------------------------------------
-- 계획: 로트 하나에 단지 하나
------------------------------------------------------------------------------------------------------
local function planComplex(o: ZoneOpts, lot: Lot, rng: Random, serial: number, lod: string, big: boolean, waterfront: boolean): Complex?
	local lx, lz = (lot.x0 + lot.x1) / 2, (lot.z0 + lot.z1) / 2
	local LW, LD = lot.x1 - lot.x0, lot.z1 - lot.z0
	local isTower = (not big) and rng:NextNumber() < o.towerChance
	-- 단지 방향: 0(긴 면이 강/카메라 쪽) / 90(측벽 동 번호가 카메라 쪽) / 15~30 비스듬
	local r = rng:NextNumber()
	local orient = if r < 0.6 then 0 elseif r < 0.82 then 90 else 1
	local frameYaw = 0
	local ex, ez = LW, LD -- 단지 로컬 X(동 긴 축) / Z 범위
	if orient == 90 then
		frameYaw = 90
		ex, ez = LD, LW
	elseif orient == 1 then
		frameYaw = rng:NextNumber(15, 30) * (if rng:NextNumber() < 0.5 then -1 else 1)
		ex, ez = LW * 0.8, LD * 0.8
	end
	-- 잔디 둘레 + 상가 자리
	ex -= 2 * LAWN_MX + SHOP_ROOM * 0.5
	ez -= 2 * LAWN_MZ + SHOP_ROOM * 0.5

	local cx: Complex = {
		name = string.format("Danji_%s%02d", o.key, serial),
		kind = if isTower then "tower" else "slab",
		lod = lod,
		wall = pick(rng, WALLS),
		accent = pick(rng, ACCENTS),
		dark = rgb(40, 42, 50),
		glass = pick(rng, TOWER_GLASS),
		frame = pick(rng, TOWER_FRAME),
		led = pick(rng, CROWN_LED),
		crown = nil,
		lit = if rng:NextNumber() < 0.7 then LIT_WARM else LIT_MIXED,
		litChance = rng:NextNumber(0.5, 0.7),
		slabs = {},
		extras = {},
		lawn = nil,
		cost = 0,
	}
	cx.dark = cx.wall:Lerp(rgb(30, 32, 40), 0.72)

	-- 동 치수 / 간격 (실측)
	local w, d, floors, colGap, rowGap
	local stagger = false
	if isTower then
		w = M(rng:NextNumber(26, 36)) -- 평면 26~36 m
		d = w * rng:NextNumber(0.82, 1.0)
		floors = rng:NextInteger(36, 49)
		colGap = M(rng:NextNumber(20, 34))
		rowGap = M(rng:NextNumber(32, 50))
		stagger = true
		cx.crown = "frame"
	else
		w = UNIT * rng:NextInteger(9, 15) + 2 -- 137~227 stud = 41~68 m
		d = M(rng:NextNumber(12, 15)) -- 깊이 12~15 m
		if big then
			floors = rng:NextInteger(27, 35)
		elseif waterfront or rng:NextNumber() < 0.15 then
			floors = rng:NextInteger(15, 21) -- 강변 앞줄 / 오래된 단지
		else
			floors = rng:NextInteger(18, 32)
		end
		colGap = M(rng:NextNumber(10, 22))
		rowGap = math.clamp(slabHeight(floors) * 0.48, M(30), M(50)) -- 인동 거리 30~50 m
		stagger = rng:NextNumber() < 0.4
		if floors >= 22 and rng:NextNumber() < 0.24 then
			cx.crown = if rng:NextNumber() < 0.5 then "frame" else "led" -- 신축 브랜드 아파트 옥상 왕관/LED
		end
	end

	local maxCols = math.clamp(math.floor((ex + colGap) / (w + colGap)), 0, if isTower then 3 else 4)
	local maxRows = math.clamp(math.floor((ez + rowGap) / (d + rowGap)), 0, 4)
	if maxCols < 1 or maxRows < 1 then
		return nil
	end
	local cols = math.clamp(rng:NextInteger(2, 4), 1, maxCols)
	local rows = math.clamp(rng:NextInteger(2, 4), 1, maxRows)
	if big then
		cols, rows = maxCols, maxRows
	end
	while cols * rows > 10 do
		rows -= 1
	end
	if isTower then
		while cols * rows > 6 do
			rows -= 1
		end
	end
	if cols * rows < (if isTower then 3 else 4) then
		-- 로트가 작으면 가능한 만큼 채움
		cols, rows = maxCols, math.min(maxRows, if isTower then 2 else 3)
		while cols * rows > 10 do
			rows -= 1
		end
		if cols * rows < 3 then
			return nil
		end
	end

	-- 블록(동 배열) 로컬 크기 → 로트 안에서 무작위 위치
	local blockW = cols * w + (cols - 1) * colGap + (if stagger then (w + colGap) * 0.5 else 0)
	local blockD = rows * d + (rows - 1) * rowGap
	if blockW > ex then
		stagger = false
		blockW = cols * w + (cols - 1) * colGap
	end
	local ox = rng:NextNumber(-0.5, 0.5) * math.max(0, ex - blockW)
	local oz = rng:NextNumber(-0.5, 0.5) * math.max(0, ez - blockD)
	local frame = CFrame.new(lx, 0, lz) * CFrame.Angles(0, math.rad(frameYaw), 0) * CFrame.new(ox, 0, oz)

	-- 동 번호면(+X 측벽)이 관람자 쪽을 향하도록 개별 yaw (판상: 0/180 또는 ±90)
	local function slabYaw(x: number): number
		if orient == 90 then
			return if o.labelFace > 0 then -90 else 90
		elseif orient == 0 then
			return if x > o.viewer.X then 180 else 0
		end
		return frameYaw
	end

	-- 잔디(단지 전체): 블록 + 여유 → 비어 있으면 통째로 예약
	local lawnW, lawnD = blockW + 2 * LAWN_MX, blockD + 2 * LAWN_MZ
	local lawnPos = frame.Position
	local useLawn = placeable(o, lawnPos.X, lawnPos.Z, lawnW, lawnD, frameYaw)
	if useLawn then
		cx.lawn = { lawnPos.X, lawnPos.Z, lawnW, lawnD, frameYaw }
	end

	-- 동 번호: 101.. (대단지 = 1201..)
	local labelBase = if big or rng:NextNumber() < 0.15 then rng:NextInteger(10, 13) * 100 else 100
	local n = 0
	for ri = 0, rows - 1 do
		local shift = if stagger and ri % 2 == 1 then (w + colGap) * 0.5 else 0
		for ci = 0, cols - 1 do
			local lxp = -blockW / 2 + w / 2 + ci * (w + colGap) + shift
			local lzp = -blockD / 2 + d / 2 + ri * (d + rowGap)
			local wp = frame * CFrame.new(lxp, 0, lzp)
			local x, z = wp.Position.X, wp.Position.Z
			local fl = floors + rng:NextInteger(-2, 2)
			-- 앞줄(강 쪽) 동은 조금 낮게 (뒤 동이 앞 동 위로 보이도록)
			local zFront = (if o.waterSign > 0 then lzp else -lzp) / math.max(1, blockD)
			if not isTower and orient ~= 90 then
				fl -= math.floor(math.max(0, zFront) * 5)
			end
			fl = math.max(if isTower then 35 else 15, fl)
			local h = if isTower then towerHeight(fl) else slabHeight(fl)
			local yaw = slabYaw(x)
			local fw, fd = w + 2 * PAD, d + 2 * PAD
			local ok = if useLawn then insideZone(o.zone, x, z, fw, fd, yaw) else placeable(o, x, z, fw, fd, yaw)
			if ok then
				n += 1
				table.insert(cx.slabs, {
					x = x,
					z = z,
					w = w,
					d = d,
					h = h,
					floors = fl,
					yaw = yaw,
					style = if isTower then (if rng:NextNumber() < 0.5 then "round" else "curtain") else "apartment",
					label = tostring(labelBase + n),
				})
				if not useLawn then
					Kit.reserveRect(x, z, fw, fd, yaw, cx.name)
				end
			end
		end
	end
	if #cx.slabs == 0 then
		return nil
	end
	if useLawn then
		Kit.reserveRect(lawnPos.X, lawnPos.Z, lawnW, lawnD, frameYaw, cx.name)
	end

	-- 단지 상가(2층 근린생활시설, 관람자/강 쪽 잔디 가장자리 밖)
	local shopW, shopD = M(rng:NextNumber(25, 40)), M(rng:NextNumber(12, 16))
	local toward = frame:VectorToObjectSpace(Vector3.new(0, 0, o.waterSign))
	local shopLocal: Vector3
	local shopYaw = frameYaw
	local edgeW: number = (if useLawn then lawnW else blockW)
	local edgeD: number = (if useLawn then lawnD else blockD)
	if math.abs(toward.Z) >= math.abs(toward.X) then
		local sgn = if toward.Z > 0 then 1 else -1
		shopLocal = Vector3.new(rng:NextNumber(-0.3, 0.3) * blockW, 0, sgn * (edgeD / 2 + SHOP_GAP + shopD / 2))
	else
		local sgn = if toward.X > 0 then 1 else -1
		shopLocal = Vector3.new(sgn * (edgeW / 2 + SHOP_GAP + shopD / 2), 0, rng:NextNumber(-0.3, 0.3) * blockD)
		shopYaw = frameYaw + 90
	end
	local sp = (frame * CFrame.new(shopLocal)).Position
	if placeable(o, sp.X, sp.Z, shopW + 8, shopD + 8, shopYaw) then
		table.insert(cx.extras, { kind = "shop", x = sp.X, z = sp.Z, w = shopW, d = shopD, h = M(rng:NextNumber(7.5, 9)), yaw = shopYaw, color = pick(rng, SIGNS) })
		Kit.reserveRect(sp.X, sp.Z, shopW + 8, shopD + 8, shopYaw, cx.name)
	end

	-- 나무(동 사이 줄 = 인동 공간의 조경): full = 키 8~13 m 가로수(수관 6~9 m), lite/min = 나무 덩어리
	if useLawn then
		local nt = if lod == "full" then rng:NextInteger(7, 11) elseif lod == "lite" then rng:NextInteger(3, 5) else rng:NextInteger(1, 2)
		for _ = 1, nt do
			local gi = rng:NextInteger(0, math.max(0, rows - 1))
			local lzp = -blockD / 2 + d + gi * (d + rowGap) + rowGap * 0.5 + rng:NextNumber(-0.18, 0.18) * rowGap
			if rows <= 1 or gi >= rows - 1 then
				lzp = (if rng:NextNumber() < 0.5 then -1 else 1) * (blockD / 2 + LAWN_MZ * 0.5)
			end
			local lxp = rng:NextNumber(-0.5, 0.5) * blockW
			local tp = (frame * CFrame.new(lxp, 0, lzp)).Position
			if lod == "full" then
				local cw = M(rng:NextNumber(6, 9))
				table.insert(cx.extras, { kind = "tree", x = tp.X, z = tp.Z, w = cw, d = cw * rng:NextNumber(0.85, 1.1), h = M(rng:NextNumber(8, 13)), yaw = 0, color = pick(rng, LEAVES) })
			else
				local cw = M(rng:NextNumber(10, 18))
				table.insert(cx.extras, { kind = "clump", x = tp.X, z = tp.Z, w = cw, d = cw * rng:NextNumber(0.6, 0.9), h = M(rng:NextNumber(8, 11)), yaw = 0, color = pick(rng, LEAVES) })
			end
		end
	end

	-- 비용 추정
	local cost = (if cx.lawn then 1 else 0)
	for _, s in cx.slabs do
		cost += if lod == "full" then estFull(s, cx.litChance, cx.crown) elseif lod == "lite" then estLite(s, cx.litChance, cx.crown) else estMin(s)
	end
	for _, e in cx.extras do
		cost += if e.kind == "shop" then (if lod == "min" then 2 else 3) elseif e.kind == "tree" then 2 else 1
	end
	cx.cost = cost
	return cx
end

------------------------------------------------------------------------------------------------------
-- 빌드: 정밀 / 경량 / 최소 동, 상가, 나무, 잔디
------------------------------------------------------------------------------------------------------
local function deco(name: string): Kit.PartOpts
	return { name = name, collide = false, query = false, shadow = false }
end

local function glowOpts(name: string, dayColor: Color3): Kit.PartOpts
	return { name = name, material = MAT.Neon, collide = false, query = false, shadow = false, glow = true, dayMaterial = MAT.Glass, dayColor = dayColor }
end

local function slabCF(s: Slab): CFrame
	return CFrame.new(s.x, CITY_Y, s.z) * CFrame.Angles(0, math.rad(s.yaw), 0)
end

-- 측벽(+X) 동 번호 "101동": 글자 높이 3 m, 꼭대기 두 층 아래. 투명 판 + SurfaceGui(자체 발광).
local function dongLabel(m: Model, s: Slab, cf: CFrame)
	local pw = math.min(s.d * 0.72, LABEL_H * 3.6)
	local plate = Kit.box(m, cf * CFrame.new(s.w / 2 + 1.6, s.h - FLOOR_H * 2, -s.d * 0.06), Vector3.new(0.2, LABEL_H, pw), P.ConcreteLight, MAT.SmoothPlastic, {
		name = "NumberPlate",
		collide = false,
		query = false,
		shadow = false,
		transparency = 1,
	})
	Kit.label(plate, Enum.NormalId.Right, s.label .. "동", { color = rgb(250, 244, 230), glow = true, pixelsPerStud = 8, maxDistance = 3000 })
end

-- 경량 판상 동(Facade "apartment" 의 저해상도판, 약 1/4 파트):
--   벽색 몸체(측벽·지붕·필로티) → 조명 코어 2~3 덩어리(Neon, 창 면 0.3 돌출) → 꺼진 세대 패치(0.6) → 발코니 띠(0.9, 2~3층마다)
local function liteSlab(parent: Instance, s: Slab, cx: Complex, rng: Random)
	local cf = slabCF(s)
	local m = Instance.new("Model")
	m.Name = "Dong" .. s.label
	local w, d, h = s.w, s.d, s.h
	local fl = s.floors
	Kit.box(m, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), cx.wall, MAT.Concrete, { name = "Body" })
	local fw = w - 2 * END_W
	-- 조명 코어: 층 묶음 2~3 덩어리(켜짐 = 따뜻한 Neon / 꺼짐 = 어두운 면)
	local f = 0
	while f < fl do
		local nf = math.min(fl - f, rng:NextInteger(math.max(3, math.floor(fl / 3)), math.max(4, math.ceil(fl / 2))))
		local y0 = PILOTIS + f * FLOOR_H
		local hh = nf * FLOOR_H
		local on = rng:NextNumber() < cx.litChance + 0.2
		local c = if on then jitter(rng, pick(rng, cx.lit), 0.08) else cx.dark
		-- 덩어리끼리 맞닿는 층 경계: 위 덩어리 바닥을 0.02 올려 같은 평면(창 면·측면)이 겹치지 않게(틈 6 mm, 뒤는 몸체 벽)
		local yb = if f > 0 then y0 + 0.02 else y0
		Kit.box(m, cf * CFrame.new(0, (yb + y0 + hh) / 2, 0), Vector3.new(fw, y0 + hh - yb, d + 0.6), c, if on then MAT.Neon else MAT.SmoothPlastic, if on then glowOpts("Core", cx.dark) else deco("CoreOff"))
		f += nf
	end
	-- 꺼진 세대(1~3세대 x 1~3층)
	local nu = math.max(2, math.floor(fw / UNIT))
	local uw = fw / nu
	for _ = 1, nOff(s, cx.litChance) do
		local len = rng:NextInteger(1, math.min(3, nu))
		local u0 = rng:NextInteger(0, nu - len)
		local nf = rng:NextInteger(1, 3)
		local f0 = rng:NextInteger(0, math.max(0, fl - nf))
		local y0 = PILOTIS + f0 * FLOOR_H
		Kit.box(m, cf * CFrame.new(-fw / 2 + (u0 + len / 2) * uw, y0 + nf * FLOOR_H / 2, 0), Vector3.new(len * uw - 0.8, nf * FLOOR_H, d + 1.2), cx.dark, MAT.SmoothPlastic, deco("Off"))
	end
	-- 발코니 띠(벽색, 1.2 m): 2~3층마다 → 멀리서 층 리듬
	local step = bandStep(fl)
	local bandH = FLOOR_H * 0.42
	for k = step, fl, step do
		local y = PILOTIS + k * FLOOR_H - bandH / 2
		Kit.box(m, cf * CFrame.new(0, y, 0), Vector3.new(fw, bandH, d + 1.8), cx.wall, MAT.Concrete, deco("Band"))
	end
	-- 1층(필로티) 로비 불빛
	Kit.box(m, cf * CFrame.new(rng:NextNumber(-0.25, 0.25) * w, PILOTIS * 0.45, 0), Vector3.new(w * 0.22, PILOTIS * 0.7, d + 0.6), dim(P.WindowWarm, 0.25), MAT.Neon, glowOpts("Lobby", cx.dark))
	-- 측벽 슈퍼그래픽(+X 측벽 = 관람자 쪽)
	Kit.box(m, cf * CFrame.new(w / 2 + 0.3, h * 0.55, d * 0.18), Vector3.new(0.6, h * 0.55, d * 0.26), cx.accent, MAT.SmoothPlastic, deco("Accent"))
	-- 옥상: 엘리베이터 기계실(4 x 3.5 m) / LED 띠(지붕 면보다 아래 → 위에서 보면 가는 테두리만 빛남)
	Kit.box(m, cf * CFrame.new(rng:NextNumber(-0.25, 0.25) * w, h + M(1.75), 0), Vector3.new(M(4), M(3.5), d * 0.6), cx.wall, MAT.Concrete, { name = "ElevatorHouse" })
	if cx.crown then
		Kit.box(m, cf * CFrame.new(0, h - 0.7, 0), Vector3.new(w + 0.6, 1, d + 0.6), cx.led, MAT.Neon, glowOpts("Led", cx.wall))
	end
	m.Parent = parent
end

-- 최소 판상 동(원경): 몸체 + 불빛 면 하나(어둡게) + 꺼진 세대 3개 + 기계실
local function minSlab(parent: Instance, s: Slab, cx: Complex, rng: Random)
	local cf = slabCF(s)
	local m = Instance.new("Model")
	m.Name = "Dong" .. s.label
	local w, d, h = s.w, s.d, s.h
	local fl = s.floors
	Kit.box(m, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), cx.wall, MAT.Concrete, { name = "Body", shadow = false })
	local fw = w - 2 * END_W
	local y0, y1 = PILOTIS, h - PARAPET
	Kit.box(m, cf * CFrame.new(0, (y0 + y1) / 2, 0), Vector3.new(fw, y1 - y0, d + 0.6), dim(jitter(rng, pick(rng, cx.lit), 0.08), 0.32), MAT.Neon, glowOpts("Core", cx.dark))
	local nu = math.max(2, math.floor(fw / UNIT))
	local uw = fw / nu
	for _ = 1, 3 do
		local len = rng:NextInteger(1, math.min(4, nu))
		local u0 = rng:NextInteger(0, nu - len)
		local nf = rng:NextInteger(2, math.max(2, math.floor(fl / 3)))
		local f0 = rng:NextInteger(0, math.max(0, fl - nf))
		Kit.box(m, cf * CFrame.new(-fw / 2 + (u0 + len / 2) * uw, PILOTIS + (f0 + nf / 2) * FLOOR_H, 0), Vector3.new(len * uw - 0.8, nf * FLOOR_H, d + 1.2), cx.dark, MAT.SmoothPlastic, deco("Off"))
	end
	Kit.box(m, cf * CFrame.new(rng:NextNumber(-0.25, 0.25) * w, h + M(1.75), 0), Vector3.new(M(4), M(3.5), d * 0.6), cx.wall, MAT.Concrete, deco("ElevatorHouse"))
	m.Parent = parent
end

local function buildSlab(parent: Instance, s: Slab, cx: Complex, rng: Random)
	local cf = slabCF(s)
	if s.style == "apartment" then
		if cx.lod == "full" then
			-- Facade 기본 층고 2.9 m / 세대 벽 4.5 m / 필로티 3.5 m
			local mdl = Facade.tower(parent, {
				name = "Dong" .. s.label,
				cf = cf,
				w = s.w,
				d = s.d,
				h = s.h,
				style = "apartment",
				rng = rng,
				glass = cx.wall,
				lit = cx.lit,
				litChance = cx.litChance,
				accent = cx.accent,
				crown = cx.crown,
				ledColor = cx.led,
				lobbyColor = dim(P.WindowWarm, 0.3),
			})
			dongLabel(mdl, s, cf)
		elseif cx.lod == "lite" then
			liteSlab(parent, s, cx, rng)
		else
			minSlab(parent, s, cx, rng)
		end
		return
	end
	-- 신축 타워형
	if cx.lod == "full" then
		Facade.tower(parent, {
			name = "Dong" .. s.label,
			cf = cf,
			w = s.w,
			d = s.d,
			h = s.h,
			style = s.style,
			rng = rng,
			floorH = TOWER_FLOOR_H,
			glass = cx.glass,
			frame = cx.frame,
			lit = cx.lit,
			litChance = cx.litChance,
			crown = "frame",
			ledColor = cx.led,
			lobbyColor = dim(P.WindowWarm, 0.3),
		})
	else
		Facade.tower(parent, {
			name = "Dong" .. s.label,
			cf = cf,
			w = s.w,
			d = s.d,
			h = s.h,
			style = if cx.lod == "lite" then "mid" else "far",
			rng = rng,
			glass = cx.glass,
			lit = LIT_LITE,
			litChance = 0.8,
			crown = "led",
			ledColor = cx.led,
			beacon = true, -- 35층 이상(> 100 m) 항공장애등
		})
	end
end

local function buildExtra(parent: Instance, e: Extra, cx: Complex)
	local cf = CFrame.new(e.x, CITY_Y, e.z) * CFrame.Angles(0, math.rad(e.yaw), 0)
	if e.kind == "shop" then
		-- 단지 상가: 2층 몸체 + 1층 쇼윈도 불빛(3 m) + 간판 띠(1.2 m)
		local body = cx.wall:Lerp(rgb(70, 70, 76), 0.45)
		Kit.box(parent, cf * CFrame.new(0, e.h / 2, 0), Vector3.new(e.w, e.h, e.d), body, MAT.Concrete, { name = "Shop" })
		Kit.box(parent, cf * CFrame.new(0, M(1.6), 0), Vector3.new(e.w - 2, M(3), e.d + 0.6), dim(P.WindowCool, 0.3), MAT.Neon, glowOpts("ShopFront", body))
		if cx.lod ~= "min" then
			Kit.box(parent, cf * CFrame.new(0, e.h - M(0.9), 0), Vector3.new(e.w - 3, M(1.2), e.d + 0.6), dim(e.color, 0.2), MAT.Neon, glowOpts("ShopSign", body))
		end
	elseif e.kind == "tree" then
		-- 조경수: 줄기(지름 0.4 m) + 수관(지면 2.5 m 위부터)
		local trunkH = M(3.2)
		local base = CITY_Y + LAWN_T
		Kit.vcyl(parent, Vector3.new(e.x, base + trunkH / 2, e.z), trunkH, M(0.4), P.Bark, MAT.Wood, deco("Trunk"))
		local ch = e.h - M(2.5)
		Kit.ellipsoid(parent, CFrame.new(e.x, base + M(2.5) + ch / 2, e.z), Vector3.new(e.w, ch, e.d), e.color, MAT.Grass, { name = "Tree", shadow = false, query = false })
	else
		-- 나무 덩어리(원경): 지면에서 1 m 띄운 수관 묶음
		Kit.ellipsoid(parent, CFrame.new(e.x, CITY_Y + LAWN_T + M(1) + e.h / 2, e.z), Vector3.new(e.w, e.h, e.d), e.color, MAT.Grass, { name = "Trees", shadow = false, query = false })
	end
end

local function buildComplex(parent: Instance, cx: Complex, rng: Random)
	local g = Kit.group(parent, cx.name)
	g:SetAttribute("Lod", cx.lod)
	if cx.lawn then
		local l = cx.lawn
		Kit.box(g, CFrame.new(l[1], CITY_Y + LAWN_T / 2, l[2]) * CFrame.Angles(0, math.rad(l[5]), 0), Vector3.new(l[3], LAWN_T, l[4]), P.GrassDark, MAT.Grass, { name = "Lawn", shadow = false })
	end
	for _, s in cx.slabs do
		buildSlab(g, s, cx, rng)
	end
	for _, e in cx.extras do
		buildExtra(g, e, cx)
	end
end

------------------------------------------------------------------------------------------------------
-- 구역
------------------------------------------------------------------------------------------------------
local function lotsOf(o: ZoneOpts): { Lot }
	local zone = o.zone
	local nx = math.max(1, math.floor((zone.XMax - zone.XMin) / o.pitchX + 0.5))
	local nz = math.max(1, math.floor((zone.ZMax - zone.ZMin) / o.pitchZ + 0.5))
	local px, pz = (zone.XMax - zone.XMin) / nx, (zone.ZMax - zone.ZMin) / nz
	local out: { Lot } = {}
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local x0, z0 = zone.XMin + i * px + STREET / 2, zone.ZMin + j * pz + STREET / 2
			local x1, z1 = x0 + px - STREET, z0 + pz - STREET
			local cxp, czp = (x0 + x1) / 2, (z0 + z1) / 2
			local dist = (Vector2.new(cxp, czp) - Vector2.new(o.viewer.X, o.viewer.Z)).Magnitude
			if o.frustum and math.abs(bearing(cxp, czp) - LOOK_BEARING) > 48 then
				dist *= 1.7
			end
			table.insert(out, { x0 = x0, z0 = z0, x1 = x1, z1 = z1, prio = dist, idx = #out + 1 })
		end
	end
	table.sort(out, function(a: Lot, b: Lot): boolean
		if a.prio ~= b.prio then
			return a.prio < b.prio
		end
		return a.idx < b.idx
	end)
	return out
end

local function planZone(o: ZoneOpts, rng: Random): { Complex }
	local density = Config.Quality.Density
	local budget = o.budget * density
	local fullBudget = o.fullBudget * density
	local used, fullUsed = 0, 0
	local out: { Complex } = {}
	local serial = 0
	local bigLeft = 3
	for _, lot in lotsOf(o) do
		if used >= budget then
			break
		end
		local czp = (lot.z0 + lot.z1) / 2
		local waterfront = (czp - o.waterZ) * o.waterSign > 0
		local big = false
		if waterfront then
			-- 강변 앞줄: 밀도 낮춤(일부 비움) + 대부분 낮은 단지, 몇 개만 대단지
			if bigLeft > 0 and rng:NextNumber() < 0.3 then
				big = true
				bigLeft -= 1
			elseif rng:NextNumber() < 0.35 then
				continue
			end
		elseif rng:NextNumber() < 0.1 then
			continue -- 학교/공원/저층 블록 자리(도시 카펫이 채움)
		end
		local lod = "min"
		if lot.prio < o.fullRange and fullUsed < fullBudget then
			lod = "full"
		elseif lot.prio < o.liteRange then
			lod = "lite"
		end
		serial += 1
		local cx = planComplex(o, lot, rng, serial, lod, big, waterfront)
		if cx then
			table.insert(out, cx)
			used += cx.cost
			if lod == "full" then
				fullUsed += cx.cost
			end
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------
-- 진입점
------------------------------------------------------------------------------------------------------
function Apartments.build(ctx: any)
	local model: Model = ctx.model
	local rng: Random = ctx.rng
	local start = Kit.stats.parts
	local B = Config.Bridge
	local N, F = Config.NearBank, Config.FarBank

	-- 다리 축 연장(가까운 쪽 도시로 들어가는 길)은 비워 둠
	Kit.reserve(B.X - B.Width / 2 - M(6), N.CityFrom, B.X + B.Width / 2 + M(6), ZN.ApartmentsNear.ZMax, "BridgeAxisNear")

	local far: ZoneOpts = {
		key = "F",
		zone = ZN.ApartmentsFar,
		pitchX = M(270), -- 단지 블록 약 270 x 230 m (도로 중심 간격)
		pitchZ = M(230),
		viewer = HERO,
		frustum = true,
		budget = BUDGET_FAR,
		fullBudget = FULL_FAR,
		fullRange = FULL_RANGE_FAR,
		liteRange = LITE_RANGE_FAR,
		towerChance = 0.16,
		waterZ = F.CityFrom - M(140), -- 도시 앞 140 m 안쪽 = 강변 앞줄
		waterSign = 1,
		labelFace = 1,
		guard = true,
	}
	local near: ZoneOpts = {
		key = "N",
		zone = ZN.ApartmentsNear,
		pitchX = M(265),
		pitchZ = M(255),
		viewer = Vector3.new(DECK.X, Config.Viewpoint.DeckHeight, DECK.Z),
		frustum = false,
		budget = BUDGET_NEAR,
		fullBudget = FULL_NEAR,
		fullRange = FULL_RANGE_NEAR,
		liteRange = LITE_RANGE_NEAR,
		towerChance = 0.14,
		waterZ = N.CityFrom + M(150),
		waterSign = -1,
		labelFace = -1,
		guard = false,
	}

	local plans: { { any } } = {}
	for _, o in { far, near } do
		local list = planZone(o, rng)
		local g = Kit.group(model, if o.key == "F" then "Far" else "Near")
		table.insert(plans, { g, list })
	end
	local nSlabs, nFull = 0, 0
	for _, pr in plans do
		local g = pr[1] :: Model
		for _, cx in pr[2] :: { Complex } do
			if Kit.stats.parts - start + cx.cost > BUDGET_TOTAL - 40 then -- 추정 오차 여유
				continue
			end
			buildComplex(g, cx, rng)
			nSlabs += #cx.slabs
			if cx.lod == "full" then
				nFull += #cx.slabs
			end
		end
	end
	model:SetAttribute("Slabs", nSlabs)
	model:SetAttribute("FullSlabs", nFull)
	model:SetAttribute("Parts", Kit.stats.parts - start)
	print(string.format("[Apartments] 동 %d (정밀 %d) · 파트 %d", nSlabs, nFull, Kit.stats.parts - start))
end

return Apartments
