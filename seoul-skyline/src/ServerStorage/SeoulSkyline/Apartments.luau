--!strict
-- SeoulSkyline / Apartments
-- 한국형 아파트 단지(아파트 단지) — 먼 쪽 잠실 강변 띠(ApartmentsFar) + 관람자 뒤 강북 띠(ApartmentsNear).
--   * 단지 = 같은 벽색 + 측벽 슈퍼그래픽 강조색 + 동 번호(101, 102 … / 대단지는 1201 …)를 공유하는
--     판상 4~10동(평행/엇갈림) 또는 신축 35~49층 타워 3~6동(커튼월/원형 + 왕관 프레임).
--   * 배치: 도로 격자 블록(로트) → 로트 안에 단지 배치. 방향은 대부분 0/90도, 일부 단지 15~30도.
--     모든 동/상가/나무/잔디는 Kit.isFreeRect 검사 후 Kit.reserveRect (앞서 빌드된 랜드마크·고층·도로를 피함).
--   * LOD: 히어로 카메라/전망대에서 가까운 단지부터 Facade "apartment" 정밀 모델(층 슬래브·세대 벽·동 번호),
--     예산이 차면 경량 모델(벽색 몸체 + 어두운 창 면 + 겹치지 않는 켜진 세대 줄 Neon). 파트 예산을 넘지 않게 계획.
--   * 강변 앞줄은 밀도를 낮추고(몇 개 대단지만), 히어로 구도에서 롯데타워·몰 앞을 가리는 동은 배치하지 않음.
--   * 실제 광원 0개 — 불빛은 모두 Neon(glow 태그로 낮/밤 전환).

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)
local Facade = require(script.Parent.Facade)

local Apartments = {}

local rgb = Color3.fromRGB
local P = Config.Palette
local ZN = Config.Zones
local CITY_Y = Config.Level.City
local BLACK = Color3.new(0, 0, 0)
local MAT = Enum.Material

------------------------------------------------------------------------------------------------------
-- 상수
------------------------------------------------------------------------------------------------------
local BUDGET_TOTAL = 9000 -- 모듈 전체 파트 상한(하드 캡)
local BUDGET_FAR = 6300 -- 먼 쪽 띠 계획 예산(추정치)
local BUDGET_NEAR = 2500 -- 가까운 쪽 띠
local FULL_FAR = 3900 -- 먼 쪽 정밀 모델 예산
local FULL_NEAR = 1700
local FULL_RANGE_FAR = 2700 -- 히어로 카메라 가중 거리 이내 단지만 정밀
local FULL_RANGE_NEAR = 1100 -- 전망대 거리

local FLOOR_H = 4.4 -- 판상 아파트 층고(압축 스케일: 15~32층 → 높이 70~146)
local PILOTIS = FLOOR_H * 1.2 -- Facade 필로티 높이와 동일
local TOWER_FLOOR_H = 4.6 -- 신축 타워 층고(35~49층 → 160~225)
local UNIT = 10 -- 세대 폭(세대 벽 간격)
local PAD = 6 -- 동 둘레 보도 여유(예약)
local STREET = 44 -- 로트(블록) 사이 도로 폭
local LAWN_T = 0.4 -- 단지 잔디 두께(도시 지면 14.0 위)
local END_W = 1.6 -- 경량 모델 측벽 두께

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
local CROWN_LED = { P.LedGold, P.LedCyan, P.LedBlue, P.LedGold, P.WindowWarm }
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
	full: boolean,
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
	local T, M = Config.Landmark.Tower, Config.Landmark.Mall
	local r = T.BaseWidth * 0.75
	for _, c in { { T.Center.X - r, T.Center.Z - r }, { T.Center.X + r, T.Center.Z - r }, { T.Center.X - r, T.Center.Z + r }, { T.Center.X + r, T.Center.Z + r }, { M.Min.X, M.Min.Y }, { M.Max.X, M.Min.Y }, { M.Min.X, M.Max.Y }, { M.Max.X, M.Max.Y } } do
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

-- 정밀 모델 파트 수 추정(계획 단계 예산용; 실제 수는 빌드 때 측정)
local function estFull(s: Slab, lc: number, crown: string?): number
	if s.style == "apartment" then
		local nu = math.max(2, math.floor(s.w / UNIT))
		local n = s.floors
		return 14 + n + math.ceil(n / 4.5) + (nu - 1) + math.min(30, math.floor(n * nu * (1 - lc) / 3)) + (if crown then 7 else 0)
	end
	local n = math.floor((s.h - 13) / TOWER_FLOOR_H)
	if s.style == "round" then
		return 12 + n + math.ceil(n / 4.5)
	end
	local nx = math.max(1, math.floor(s.w / 6))
	local nz = math.max(1, math.floor(s.d / 6))
	return 18 + n + math.ceil(n / 4.5) + nx + nz + math.min(26, math.floor(n * (nx + nz) * (1 - lc) / 9))
end

local function nSegs(s: Slab, lc: number): number
	local nu = math.max(2, math.floor((s.w - 2 * END_W) / UNIT))
	return math.clamp(math.floor(s.floors * nu * lc / 7), 4, 13)
end

local function estLite(s: Slab, lc: number, crown: string?): number
	if s.style ~= "apartment" then
		return 3 + math.clamp(math.floor(s.h / 22), 1, 6)
	end
	return 4 + nSegs(s, lc) + (if crown then 1 else 0)
end

------------------------------------------------------------------------------------------------------
-- 계획: 로트 하나에 단지 하나
------------------------------------------------------------------------------------------------------
local function planComplex(o: ZoneOpts, lot: Lot, rng: Random, serial: number, full: boolean, big: boolean): Complex?
	local lx, lz = (lot.x0 + lot.x1) / 2, (lot.z0 + lot.z1) / 2
	local LW, LD = lot.x1 - lot.x0, lot.z1 - lot.z0
	local isTower = (not big) and rng:NextNumber() < o.towerChance
	-- 단지 방향: 0(긴 면이 강/카메라 쪽) / 90(측벽 동 번호가 카메라 쪽) / 15~30 비스듬
	local r = rng:NextNumber()
	local orient = if r < 0.6 then 0 elseif r < 0.82 then 90 else 1
	local frameYaw = 0
	local ext = { LW, LD } -- 단지 로컬 X(동 긴 축) / Z 범위
	if orient == 90 then
		frameYaw = 90
		ext = { LD, LW }
	elseif orient == 1 then
		frameYaw = rng:NextNumber(15, 30) * (if rng:NextNumber() < 0.5 then -1 else 1)
		ext = { LW * 0.8, LD * 0.8 }
	end

	local cx: Complex = {
		name = string.format("Danji_%s%02d", o.key, serial),
		kind = if isTower then "tower" else "slab",
		full = full,
		wall = pick(rng, WALLS),
		accent = pick(rng, ACCENTS),
		dark = rgb(40, 42, 50),
		glass = pick(rng, TOWER_GLASS),
		frame = pick(rng, TOWER_FRAME),
		led = pick(rng, CROWN_LED),
		crown = nil,
		lit = if rng:NextNumber() < 0.7 then LIT_WARM else LIT_MIXED,
		litChance = rng:NextNumber(0.45, 0.7),
		slabs = {},
		extras = {},
		lawn = nil,
		cost = 0,
	}
	cx.dark = cx.wall:Lerp(rgb(30, 32, 40), 0.72)

	-- 동 치수 / 간격
	local w, d, floors, colGap, rowGap
	local stagger = false
	if isTower then
		w = rng:NextNumber(36, 48)
		d = w * rng:NextNumber(0.82, 1.0)
		floors = rng:NextInteger(35, 49)
		colGap = rng:NextNumber(40, 70)
		rowGap = rng:NextNumber(50, 80)
		stagger = true
		cx.crown = "frame"
	else
		w = UNIT * rng:NextInteger(6, 9) + 2
		d = rng:NextNumber(16, 22)
		if big then
			floors = rng:NextInteger(24, 32)
		elseif rng:NextNumber() < 0.15 then
			floors = rng:NextInteger(9, 12) -- 오래된 저층 단지
		else
			floors = rng:NextInteger(15, 30)
		end
		colGap = rng:NextNumber(16, 34)
		rowGap = math.clamp(floors * FLOOR_H * 0.42, 34, 64)
		stagger = rng:NextNumber() < 0.4
		if floors >= 20 and rng:NextNumber() < 0.28 then
			cx.crown = if rng:NextNumber() < 0.6 then "frame" else "led" -- 신축 브랜드 아파트 옥상 왕관/LED
		end
	end
	local hNominal = if isTower then floors * TOWER_FLOOR_H + 13 else PILOTIS + floors * FLOOR_H + 1

	local maxCols = math.clamp(math.floor((ext[1] + colGap) / (w + colGap)), 0, if isTower then 3 else 4)
	local maxRows = math.clamp(math.floor((ext[2] + rowGap) / (d + rowGap)), 0, 4)
	if maxCols < 1 or maxRows < 1 then
		return nil
	end
	local cols = math.clamp(rng:NextInteger(2, 4), 1, maxCols)
	local rows = math.clamp(rng:NextInteger(2, 3), 1, maxRows)
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
	if blockW > ext[1] then
		stagger = false
		blockW = cols * w + (cols - 1) * colGap
	end
	local ox = rng:NextNumber(-0.5, 0.5) * math.max(0, ext[1] - blockW)
	local oz = rng:NextNumber(-0.5, 0.5) * math.max(0, ext[2] - blockD)
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
	local lawnW, lawnD = blockW + 36, blockD + 40
	local lawnPos = frame.Position
	local useLawn = placeable(o, lawnPos.X, lawnPos.Z, lawnW, lawnD, frameYaw)
	if useLawn then
		cx.lawn = { lawnPos.X, lawnPos.Z, lawnW, lawnD, frameYaw }
	end

	-- 동 번호: 101.. (대단지 = 1201..)
	local labelBase = if big or rng:NextNumber() < 0.15 then rng:NextInteger(10, 13) * 100 else 100
	local n = 0
	local frontSign = o.waterSign
	for ri = 0, rows - 1 do
		-- 강(카메라) 쪽 줄일수록 낮게 (뒤 동이 앞 동 위로 보이도록)
		local frontness = if rows > 1 then ri / (rows - 1) else 0.5
		local shift = if stagger and ri % 2 == 1 then (w + colGap) * 0.5 else 0
		local ncols = cols
		for ci = 0, ncols - 1 do
			local lxp = -blockW / 2 + w / 2 + ci * (w + colGap) + shift
			local lzp = -blockD / 2 + d / 2 + ri * (d + rowGap)
			local wp = frame * CFrame.new(lxp, 0, lzp)
			local x, z = wp.Position.X, wp.Position.Z
			local fl = floors + rng:NextInteger(-2, 2)
			-- 앞줄(강 쪽) 동은 조금 낮게
			local zFront = (if frontSign > 0 then lzp else -lzp) / math.max(1, blockD)
			if not isTower and orient ~= 90 then
				fl -= math.floor(math.max(0, zFront) * 4)
			end
			local _ = frontness
			fl = math.max(if isTower then 33 else 8, fl)
			local h = if isTower then fl * TOWER_FLOOR_H + 13 else PILOTIS + fl * FLOOR_H + 1
			local yaw = slabYaw(x)
			local fw, fd = w + 2 * PAD, d + 2 * PAD
			local ok = if useLawn then insideZone(o.zone, x, z, fw, fd, yaw) else placeable(o, x, z, fw, fd, yaw)
			if ok then
				n += 1
				local s: Slab = {
					x = x,
					z = z,
					w = w,
					d = d,
					h = h,
					floors = fl,
					yaw = yaw,
					style = if isTower then (if rng:NextNumber() < 0.5 then "round" else "curtain") else "apartment",
					label = tostring(labelBase + n),
				}
				table.insert(cx.slabs, s)
				if not useLawn then
					Kit.reserveRect(x, z, fw, fd, yaw, cx.name)
				end
			end
		end
	end
	local _ = hNominal
	if #cx.slabs < 3 then
		-- 실패: 잔디 예약 전이므로 개별 예약만 남음(작은 빈 터 → 이후 도시 카펫이 채우지 않음, 무해)
		if #cx.slabs == 0 then
			return nil
		end
	end
	if useLawn then
		Kit.reserveRect(lawnPos.X, lawnPos.Z, lawnW, lawnD, frameYaw, cx.name)
	end

	-- 상가(단지 입구, 강 쪽 모서리) + 나무
	local shopW, shopD = rng:NextNumber(36, 60), rng:NextNumber(16, 24)
	local shopCF = frame * CFrame.new(rng:NextNumber(-0.35, 0.35) * blockW, 0, frontSign * (blockD / 2 + 14 + shopD / 2) * (if frameYaw == 90 or frameYaw == -90 then 0 else 1))
	if frameYaw == 90 then
		shopCF = frame * CFrame.new(-(blockW / 2 + 14 + shopW / 2) * frontSign, 0, rng:NextNumber(-0.3, 0.3) * blockD)
	end
	local sp = shopCF.Position
	local shopFits = if useLawn
		then insideZone(o.zone, sp.X, sp.Z, shopW, shopD, frameYaw) and math.abs((frame:PointToObjectSpace(sp)).Z) + shopD / 2 <= lawnD / 2 and math.abs((frame:PointToObjectSpace(sp)).X) + shopW / 2 <= lawnW / 2
		else placeable(o, sp.X, sp.Z, shopW + 8, shopD + 8, frameYaw)
	if shopFits then
		table.insert(cx.extras, { kind = "shop", x = sp.X, z = sp.Z, w = shopW, d = shopD, h = rng:NextNumber(8, 12), yaw = frameYaw, color = pick(rng, SIGNS) })
		if not useLawn then
			Kit.reserveRect(sp.X, sp.Z, shopW + 8, shopD + 8, frameYaw, cx.name)
		end
	end
	if useLawn then
		-- 나무 덩어리: 동 사이 줄(row gap)에 배치
		local nt = if full then rng:NextInteger(4, 7) else rng:NextInteger(2, 4)
		for _ = 1, nt do
			local ts = rng:NextNumber(18, 34)
			local gi = rng:NextInteger(0, math.max(0, rows - 1))
			local lzp = -blockD / 2 + d + gi * (d + rowGap) + rowGap * 0.5
			if rows <= 1 or gi >= rows - 1 then
				lzp = (if rng:NextNumber() < 0.5 then -1 else 1) * (blockD / 2 + 10)
			end
			local lxp = rng:NextNumber(-0.5, 0.5) * blockW
			local tp = (frame * CFrame.new(lxp, 0, lzp)).Position
			table.insert(cx.extras, { kind = "tree", x = tp.X, z = tp.Z, w = ts, d = ts * rng:NextNumber(0.75, 1.1), h = ts * rng:NextNumber(0.55, 0.75), yaw = 0, color = pick(rng, LEAVES) })
		end
	end

	-- 비용 추정
	local cost = (if cx.lawn then 1 else 0)
	for _, s in cx.slabs do
		cost += if full then estFull(s, cx.litChance, cx.crown) else estLite(s, cx.litChance, cx.crown)
	end
	for _, e in cx.extras do
		cost += if e.kind == "shop" then 3 else 1
	end
	cx.cost = cost
	return cx
end

------------------------------------------------------------------------------------------------------
-- 빌드: 정밀 / 경량 동, 상가, 나무, 잔디
------------------------------------------------------------------------------------------------------
local function deco(name: string, extra: { [string]: any }?): Kit.PartOpts
	local o: Kit.PartOpts = { name = name, collide = false, query = false, shadow = false }
	if extra then
		for k, v in extra do
			(o :: any)[k] = v
		end
	end
	return o
end

local function glowOpts(name: string, dayColor: Color3): Kit.PartOpts
	return { name = name, material = MAT.Neon, collide = false, query = false, shadow = false, glow = true, dayMaterial = MAT.Glass, dayColor = dayColor }
end

-- 경량 판상 동: 벽색 몸체 + 어두운 창 면(긴 면 두 쪽 0.3 돌출) + 켜진 세대 줄(창 면보다 0.3 더 돌출, 서로 겹치지 않음)
local function liteSlab(parent: Instance, s: Slab, cx: Complex, rng: Random)
	local cf = CFrame.new(s.x, CITY_Y, s.z) * CFrame.Angles(0, math.rad(s.yaw), 0)
	local m = Instance.new("Model")
	m.Name = "Dong" .. s.label
	local w, d, h = s.w, s.d, s.h
	Kit.box(m, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), cx.wall, MAT.Concrete, { name = "Body" })
	local fw = w - 2 * END_W
	local fy0, fy1 = PILOTIS, PILOTIS + s.floors * FLOOR_H
	Kit.box(m, cf * CFrame.new(0, (fy0 + fy1) / 2, 0), Vector3.new(fw, fy1 - fy0, d + 0.6), cx.dark, MAT.SmoothPlastic, deco("Windows"))
	-- 1층 로비 불빛
	Kit.box(m, cf * CFrame.new(rng:NextNumber(-0.25, 0.25) * w, PILOTIS * 0.45, 0), Vector3.new(w * 0.22, PILOTIS * 0.7, d + 0.6), dim(P.WindowWarm, 0.25), MAT.Neon, glowOpts("Lobby", cx.dark))
	local nu = math.max(2, math.floor(fw / UNIT))
	local uw = fw / nu
	local occ: { [number]: boolean } = {}
	local segs = nSegs(s, cx.litChance)
	for _ = 1, segs do
		for _try = 1, 5 do
			local tall = if rng:NextNumber() < 0.22 then 2 else 1
			local f = rng:NextInteger(0, math.max(0, s.floors - tall))
			local len = rng:NextInteger(1, math.min(4, nu))
			local u0 = rng:NextInteger(0, nu - len)
			local free = true
			for ff = f, f + tall - 1 do
				for uu = u0, u0 + len - 1 do
					if occ[ff * 64 + uu] then
						free = false
					end
				end
			end
			if free then
				for ff = f - 1, f + tall do -- 위아래 한 층 여유(세로로 붙은 띠가 하나로 뭉치지 않게)
					for uu = u0, u0 + len - 1 do
						occ[ff * 64 + uu] = true
					end
				end
				local y0 = PILOTIS + f * FLOOR_H + FLOOR_H * 0.34
				local hh = tall * FLOOR_H - FLOOR_H * 0.42
				local x = -fw / 2 + (u0 + len / 2) * uw
				local c = jitter(rng, pick(rng, cx.lit), 0.1):Lerp(BLACK, rng:NextNumber(0, 0.25))
				Kit.box(m, cf * CFrame.new(x, y0 + hh / 2, 0), Vector3.new(len * uw - 1.2, hh, d + 1.2), c, MAT.Neon, glowOpts("Lit", cx.dark))
				break
			end
		end
	end
	-- 측벽 슈퍼그래픽(+X 측벽 = 관람자 쪽)
	Kit.box(m, cf * CFrame.new(w / 2 + 0.3, h * 0.55, d * 0.18), Vector3.new(0.6, h * 0.55, d * 0.26), cx.accent, MAT.SmoothPlastic, deco("Accent"))
	-- 옥상: 엘리베이터 탑 / LED 왕관
	Kit.box(m, cf * CFrame.new(rng:NextNumber(-0.25, 0.25) * w, h + 3, 0), Vector3.new(8, 6, d * 0.6), cx.wall, MAT.Concrete, { name = "ElevatorHouse" })
	if cx.crown then
		Kit.box(m, cf * CFrame.new(0, h + 0.5, 0), Vector3.new(w + 0.6, 1, d + 0.6), cx.led, MAT.Neon, glowOpts("Led", cx.wall))
	end
	m.Parent = parent
end

local function buildSlab(parent: Instance, s: Slab, cx: Complex, rng: Random)
	local cf = CFrame.new(s.x, CITY_Y, s.z) * CFrame.Angles(0, math.rad(s.yaw), 0)
	if s.style == "apartment" then
		if cx.full then
			Facade.tower(parent, {
				name = "Dong" .. s.label,
				cf = cf,
				w = s.w,
				d = s.d,
				h = s.h,
				style = "apartment",
				rng = rng,
				floorH = FLOOR_H,
				bay = UNIT,
				glass = cx.wall,
				lit = cx.lit,
				litChance = cx.litChance,
				accent = cx.accent,
				label = s.label,
				crown = cx.crown,
				ledColor = cx.led,
			})
		else
			liteSlab(parent, s, cx, rng)
		end
		return
	end
	-- 신축 타워
	if cx.full then
		Facade.tower(parent, {
			name = "Dong" .. s.label,
			cf = cf,
			w = s.w,
			d = s.d,
			h = s.h,
			style = s.style,
			rng = rng,
			floorH = TOWER_FLOOR_H,
			bay = 6,
			glass = cx.glass,
			frame = cx.frame,
			lit = cx.lit,
			litChance = cx.litChance,
			crown = "frame",
			ledColor = cx.led,
		})
	else
		Facade.tower(parent, {
			name = "Dong" .. s.label,
			cf = cf,
			w = s.w,
			d = s.d,
			h = s.h,
			style = "mid",
			rng = rng,
			glass = cx.glass,
			lit = LIT_LITE,
			litChance = 0.8,
			crown = "led",
			ledColor = cx.led,
		})
	end
end

local function buildExtra(parent: Instance, e: Extra, cx: Complex, rng: Random)
	local cf = CFrame.new(e.x, CITY_Y, e.z) * CFrame.Angles(0, math.rad(e.yaw), 0)
	if e.kind == "shop" then
		-- 단지 상가: 2~3층 몸체 + 1층 쇼윈도 불빛 + 간판 띠
		local body = cx.wall:Lerp(rgb(70, 70, 76), 0.45)
		Kit.box(parent, cf * CFrame.new(0, e.h / 2, 0), Vector3.new(e.w, e.h, e.d), body, MAT.Concrete, { name = "Shop" })
		Kit.box(parent, cf * CFrame.new(0, 2.1, 0), Vector3.new(e.w - 2, 3, e.d + 0.6), dim(P.WindowCool, 0.3), MAT.Neon, glowOpts("ShopFront", body))
		Kit.box(parent, cf * CFrame.new(0, e.h - 1.6, 0), Vector3.new(e.w - 3, 1.8, e.d + 0.6), dim(e.color, 0.2), MAT.Neon, glowOpts("ShopSign", body))
	else
		local _ = rng
		Kit.ellipsoid(parent, CFrame.new(e.x, CITY_Y + LAWN_T + e.h / 2 - 1.2, e.z), Vector3.new(e.w, e.h, e.d), e.color, MAT.Grass, { name = "Trees", shadow = false, query = false })
	end
end

local function buildComplex(parent: Instance, cx: Complex, rng: Random)
	local g = Kit.group(parent, cx.name)
	g:SetAttribute("Lod", if cx.full then "full" else "lite")
	if cx.lawn then
		local l = cx.lawn
		Kit.box(g, CFrame.new(l[1], CITY_Y + LAWN_T / 2, l[2]) * CFrame.Angles(0, math.rad(l[5]), 0), Vector3.new(l[3], LAWN_T, l[4]), P.GrassDark, MAT.Grass, { name = "Lawn", shadow = false })
	end
	for _, s in cx.slabs do
		buildSlab(g, s, cx, rng)
	end
	for _, e in cx.extras do
		buildExtra(g, e, cx, rng)
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
			-- 강변 앞줄: 대부분 비우고 몇 개만 대단지
			if bigLeft > 0 and rng:NextNumber() < 0.35 then
				big = true
				bigLeft -= 1
			elseif rng:NextNumber() < 0.75 then
				continue
			end
		elseif rng:NextNumber() < 0.1 then
			continue -- 학교/공원/저층 블록 자리
		end
		local full = lot.prio < o.fullRange and fullUsed < fullBudget
		serial += 1
		local cx = planComplex(o, lot, rng, serial, full, big)
		if cx then
			table.insert(out, cx)
			used += cx.cost
			if full then
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
	local N = Config.NearBank

	-- 다리 축 연장(가까운 쪽 도시로 들어가는 길)은 비워 둠
	Kit.reserve(B.X - B.Width / 2 - 20, N.CityFrom, B.X + B.Width / 2 + 20, ZN.ApartmentsNear.ZMax, "BridgeAxisNear")

	local far: ZoneOpts = {
		key = "F",
		zone = ZN.ApartmentsFar,
		pitchX = 460,
		pitchZ = 400,
		viewer = HERO,
		frustum = true,
		budget = BUDGET_FAR,
		fullBudget = FULL_FAR,
		fullRange = FULL_RANGE_FAR,
		towerChance = 0.16,
		waterZ = -900,
		waterSign = 1,
		labelFace = 1,
		guard = true,
	}
	local near: ZoneOpts = {
		key = "N",
		zone = ZN.ApartmentsNear,
		pitchX = 440,
		pitchZ = 340,
		viewer = Vector3.new(DECK.X, Config.Viewpoint.DeckHeight, DECK.Z),
		frustum = false,
		budget = BUDGET_NEAR,
		fullBudget = FULL_NEAR,
		fullRange = FULL_RANGE_NEAR,
		towerChance = 0.14,
		waterZ = 1080,
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
			if Kit.stats.parts - start + cx.cost > BUDGET_TOTAL then
				continue
			end
			buildComplex(g, cx, rng)
			nSlabs += #cx.slabs
			if cx.full then
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
