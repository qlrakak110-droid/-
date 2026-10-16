--!strict
-- GwangalliBuildingInterior/T_pub: 유형 (pub) 실내 — 크래프트 비어 펍 · 탭하우스 · 스포츠 펍 · 칵테일 바 · 파티 펍.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (테마별 바닥 · 징두리 · 카운터 · 스툴 · 펜던트)
--   build(K, V, S) 유형별 디테일:
--     백바 (스모크 거울 · 조명 유리 선반 · 술병 · 하부장 + 유리문 맥주 쿨러 · 상호 크라운)
--     탭 타워 (맵 TapPost/TapBar/TapHandle/DripTray 와 같은 자리 · 같은 높이로 덮어씌움) · 황동 발판 레일 · 코스터
--     탭 리스트 보드 (스타일 · ABV · 가격) · 안주 보드 · 네온사인 · 스포츠 TV · 다트 머신 · 브라이트 탱크 · 케그
--     노출 천장 (스파이럴 덕트 · 에디슨 전구 · 페스툰 전구줄) · 벤치 소파 (같은 자리) · 포스터 · 안내판
--     (영업시간 · 19세 미만 출입금지 · 와이파이 · 원산지 · 간편결제 · 음주운전 · STAFF ONLY)
--   상호작용 (이 클라이언트만): TV 채널 · 네온 켜기/끄기 · 다트 게임 · 주크박스 — 주문 · 계산 · 앉기와 겹치지 않음

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))

local T = {}
T.types = { "pub" }

local L = Look
local M = Enum.Material
local F = Enum.Font
local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local rgb = Color3.fromRGB

-- 공용 도우미 ------------------------------------------------------------------------------------------
local function wood(r: number, g: number, b: number): any
	return L.of(r, g, b, M.Wood)
end

local function dim(look: any, f: number): any
	return L.with(look, { c = (look.c :: Color3):Lerp(Color3.new(0, 0, 0), f) })
end

local function hash(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end

local function rnd(seed: number, i: number): number
	local s = math.sin(seed * 0.7311 + i * 12.9898) * 43758.5453
	return s - math.floor(s)
end

local function extend(base: any, over: any): any
	local t = table.clone(base)
	for k, v in over do
		t[k] = v
	end
	return t
end

local function laabb(lcf: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size / 2
	local ex = math.abs(lcf.XVector.X) * h.X + math.abs(lcf.YVector.X) * h.Y + math.abs(lcf.ZVector.X) * h.Z
	local ey = math.abs(lcf.XVector.Y) * h.X + math.abs(lcf.YVector.Y) * h.Y + math.abs(lcf.ZVector.Y) * h.Z
	local ez = math.abs(lcf.XVector.Z) * h.X + math.abs(lcf.YVector.Z) * h.Y + math.abs(lcf.ZVector.Z) * h.Z
	local p = lcf.Position
	return V3(p.X - ex, p.Y - ey, p.Z - ez), V3(p.X + ex, p.Y + ey, p.Z + ez)
end

local function overlap(amin: Vector3, amax: Vector3, bmin: Vector3, bmax: Vector3): boolean
	return amin.X < bmax.X - 0.02 and amax.X > bmin.X + 0.02 and amin.Y < bmax.Y - 0.02 and amax.Y > bmin.Y + 0.02 and amin.Z < bmax.Z - 0.02 and amax.Z > bmin.Z + 0.02
end

local function hideRec(K: any, r: any)
	Scan.hide(K.hidden, r.part)
end

local function budget(K: any, n: number): boolean
	return #K.parts + n < K.maxParts * 0.94
end

-- 벽 위 표시면에서 앞을 보는 원판 (다트판 · 맨홀 · 계기판): dcf 의 +Z 쪽으로 z..z+t
local function wdisc(K: any, name: string, dia: number, t: number, dcf: CFrame, z: number, look: any): BasePart
	return K:make("Part", name, V3(t, dia, dia), dcf * CF(0, 0, z + t / 2) * ANG(0, PI / 2, 0), look, Enum.PartType.Cylinder)
end

-- 수평 글자판 (카운터 위 코스터 글자 등): +Z(보는 사람) = 위, 글자 윗변 = -Z
local function flatCF(p: Vector3): CFrame
	return CFrame.fromMatrix(p, V3(1, 0, 0), V3(0, 0, -1), V3(0, 1, 0))
end

-- 벽 자리 관리 -------------------------------------------------------------------------------------------
-- Common.wallSpot 와 같은 K.wallUsed 를 씀 (Common 이 먼저 붙인 스위치 · 비상벨 · 콘센트를 피함)
local function claim(K: any, wn: string, a: number, b: number, y0: number, y1: number)
	K.wallUsed = K.wallUsed or {}
	table.insert(K.wallUsed, { w = wn, a = a, b = b, y0 = y0, y1 = y1 })
end

local function usedHit(K: any, wn: string, a: number, b: number, y0: number, y1: number): boolean
	for _, u in K.wallUsed or {} do
		if u.w == wn and u.a < b and u.b > a and u.y0 < y1 and u.y1 > y0 then
			return true
		end
	end
	return false
end

local function freeSpans(K: any, wn: string, y0: number, y1: number, depth: number?): { { number } }
	local V = K.V
	local out = {}
	for _, s in V:spans(wn, y0, y1, depth or 0.8) do
		local segs = { { s[1], s[2] } }
		for _, u in K.wallUsed or {} do
			if u.w == wn and u.y0 < y1 and u.y1 > y0 then
				local nxt = {}
				for _, g in segs do
					if u.b <= g[1] or u.a >= g[2] then
						table.insert(nxt, g)
					else
						if u.a > g[1] then
							table.insert(nxt, { g[1], u.a })
						end
						if u.b < g[2] then
							table.insert(nxt, { u.b, g[2] })
						end
					end
				end
				segs = nxt
			end
		end
		for _, g in segs do
			if g[2] - g[1] > 0.4 then
				table.insert(out, g)
			end
		end
	end
	return out
end

-- walls 순서대로: 폭 minW..maxW 가 들어가는 빈 구간 중 near 에 가까운 자리. test(wn, u, w) 로 추가 조건.
-- 반환 wn, u (벽 좌표), w (실제 폭). 찾은 자리는 claim.
local function findWall(K: any, walls: { string }, minW: number, maxW: number, y0: number, y1: number, near: Vector3?, depth: number?, test: any?): (string?, number?, number?)
	local V = K.V
	for _, wn in walls do
		if not V.walls[wn] then
			continue
		end
		local target = if near then (V:wallCoord(wn, near)) else 0
		local best, bu, bw = math.huge, nil, nil
		for _, s in freeSpans(K, wn, y0, y1, depth) do
			local span = s[2] - s[1] - 0.2
			if span >= minW then
				local w = math.min(maxW, span)
				local lo, hi = s[1] + 0.1 + w / 2, s[2] - 0.1 - w / 2
				local cands = { math.clamp(target, lo, hi) }
				if test then
					local k = lo
					while k <= hi + 1e-3 do
						table.insert(cands, k)
						k += 0.5
					end
					table.sort(cands, function(a, b)
						return math.abs(a - target) < math.abs(b - target)
					end)
				end
				for _, cu in cands do
					local d = math.abs(cu - target)
					if d >= best then
						break
					end
					if not test or test(wn, cu, w) then
						best, bu, bw = d, cu, w
						break
					end
				end
			end
		end
		if bu and bw then
			claim(K, wn, bu - bw / 2 - 0.15, bu + bw / 2 + 0.15, y0, y1)
			return wn, bu, bw
		end
	end
	return nil, nil, nil
end

-- 맵 파트(쉘 제외)와 안 겹치나
local function mapClear(V: any, mn: Vector3, mx: Vector3): boolean
	for _, r in V.parts do
		if not r.shell and not r.point and overlap(mn, mx, r.min, r.max) then
			return false
		end
	end
	return true
end

-- 벽에 붙여 세우는 바닥 소품 자리 (K:spot 으로 예약). 반환 pcf (+Z = 방 안쪽), wn, u
local function floorOnWall(K: any, walls: { string }, size: Vector3, near: Vector3?, pad: number?, test: any?): (CFrame?, string?, number?)
	local V = K.V
	for _, wn in walls do
		local w = V.walls[wn]
		if not w then
			continue
		end
		local target = if near then (V:wallCoord(wn, near)) else (w.a + w.b) / 2
		local cands = {}
		local u = w.a + size.X / 2 + 0.3
		while u <= w.b - size.X / 2 - 0.3 do
			table.insert(cands, u)
			u += 0.5
		end
		table.sort(cands, function(a, b)
			return math.abs(a - target) < math.abs(b - target)
		end)
		for _, cu in cands do
			local pcf = V:wall(wn, cu, 0, size.Z / 2 + 0.14)
			local mn, mx = laabb(pcf * CF(0, size.Y / 2, 0), size + V3(0.2, 0, 0.2))
			if mapClear(V, mn, mx) and not usedHit(K, wn, cu - size.X / 2, cu + size.X / 2, 0, size.Y) and (not test or test(pcf, wn, cu)) and K:spot(pcf, size, pad or 0.1, "pub") then
				claim(K, wn, cu - size.X / 2 - 0.15, cu + size.X / 2 + 0.15, 0, size.Y + 0.2)
				return pcf, wn, cu
			end
		end
	end
	return nil, nil, nil
end

-- 벽에 붙은 프롬프트 자리가 서버 앵커에서 충분히 먼가
local function promptOK(K: any, lp: Vector3): boolean
	return Interact.canPrompt(K, lp)
end

-- 카운터 안쪽 (직원 쪽) 인가
local function behindCounter(V: any, p: Vector3): boolean
	for _, g in V.counters do
		local alongX = (g.max.X - g.min.X) >= (g.max.Z - g.min.Z)
		if alongX then
			local custPlus = (if V.door then V.door.z else V.z1) > (g.min.Z + g.max.Z) / 2
			if p.X > g.min.X - 1.6 and p.X < g.max.X + 1.6 then
				if custPlus and p.Z < g.min.Z + 0.2 then
					return true
				elseif not custPlus and p.Z > g.max.Z - 0.2 then
					return true
				end
			end
		else
			local cx = (g.min.X + g.max.X) / 2
			if p.Z > g.min.Z - 1.6 and p.Z < g.max.Z + 1.6 then
				if cx < 0 and p.X < g.min.X + 0.2 then
					return true
				elseif cx >= 0 and p.X > g.max.X - 0.2 then
					return true
				end
			end
		end
	end
	for _, k in V.keep do
		if k.kind == "staff" and p.X > k.min.X - 0.6 and p.X < k.max.X + 0.6 and p.Z > k.min.Z - 0.6 and p.Z < k.max.Z + 0.6 then
			return true
		end
	end
	return false
end

-- 손님이 벽 앞 (1.3 ~ 3.4 스터드) 에 설 자리가 있나 (가구 · 카운터 안쪽 · 문 앞 제외)
local function reachable(K: any, wn: string, u: number): boolean
	local V = K.V
	for _, off in { 1.3, 2.3, 3.4, 4.0 } do
		local p = V:wall(wn, u, 0, off).Position
		if p.X > V.x0 + 0.4 and p.X < V.x1 - 0.4 and p.Z > V.z0 + 0.4 and p.Z < V.z1 - 0.4 and not behindCounter(V, p) then
			local mn, mx = p + V3(-0.35, 0.2, -0.35), p + V3(0.35, 3.0, 0.35)
			local ok = true
			for _, s in V.solid do
				if overlap(mn, mx, s.min, s.max) then
					ok = false
					break
				end
			end
			if ok then
				for _, r in K.reserved do
					if overlap(mn, mx, r.min, r.max) then
						ok = false
						break
					end
				end
			end
			if ok then
				return true
			end
		end
	end
	return false
end

-- 작은 소품: keep 에 걸리면 아예 안 만듦 (blocked 수를 늘리지 않게)
local function clearAt(K: any, cf: CFrame, size: Vector3): boolean
	local mn, mx = laabb(cf, size)
	return K:hitsKeep(mn, mx) == nil
end

-- 테마 --------------------------------------------------------------------------------------------------
-- 탭 리스트 행: { 이름, 스타일, ABV, 가격, 맥주색, 탭 핸들 약자, 핸들색 }
local THEMES: { [string]: any } = {}

THEMES.monk = {
	key = "monk",
	brand = "HAPPY MONK",
	crown = "HAPPY MONK  ·  CRAFT BREWERY  ·  광안리",
	font = F.Oswald,
	dark = wood(66, 42, 28),
	mid = wood(104, 70, 44),
	trim = L.brass,
	cabTop = L.of(44, 42, 42, M.Marble),
	mirror = L.of(78, 72, 64, M.Glass, { r = 0.32 }),
	seat = L.of(48, 74, 56, M.Leather),
	seatStyle = "tuft",
	stool = { style = "bar", frame = L.blackMetal, seat = L.of(48, 74, 56, M.Leather) },
	tableTop = wood(122, 84, 52),
	counterFront = "panel",
	counterFrontL = wood(82, 54, 34),
	counterTop = wood(58, 36, 22),
	led = rgb(255, 176, 96),
	floor = { look = L.of(98, 66, 44, M.WoodPlanks), tile = 0 },
	lower = { kind = "wainscot", h = 3.6, look = wood(72, 47, 30), cap = wood(54, 35, 22), panel = 1.9, walls = { "left", "right", "back" } },
	feature = { wall = "left", look = L.of(120, 66, 50, M.Brick) },
	paint = L.of(42, 58, 48),
	ceil = L.of(30, 28, 27),
	pendant = { shade = "dome", look = L.of(40, 62, 48, M.Metal) },
	tablePendant = "bulb",
	neonC = rgb(255, 172, 60),
	neon2 = rgb(255, 92, 70),
	neonText = "CHEERS!",
	neonIcon = "mug",
	neonFont = F.FredokaOne,
	shelfLED = rgb(255, 190, 120),
	board = "chalk",
	boardTitle = "ON TAP  ·  오늘의 생맥주",
	boardSub = "473ml PINT  ·  모든 맥주 하프(330ml) 가능",
	boardFoot = "샘플러 4종 15,000원  ·  매일 17-19시 해피아워 1,000원 할인",
	taps = {
		{ "몽크 윗비어", "Belgian Witbier", "4.9%", "8,500", rgb(240, 214, 140), "WIT", rgb(232, 220, 180) },
		{ "광안 블론드", "Belgian Blonde", "6.2%", "9,000", rgb(232, 184, 72), "BLONDE", rgb(212, 164, 56) },
		{ "갈매기 IPA", "West Coast IPA", "6.8%", "9,500", rgb(214, 140, 48), "IPA", rgb(56, 112, 66) },
		{ "수도원 두벨", "Abbey Dubbel", "7.0%", "10,000", rgb(124, 62, 30), "DUBBEL", rgb(116, 40, 32) },
		{ "트리펠 몽크", "Tripel", "8.5%", "11,000", rgb(226, 170, 60), "TRIPEL", rgb(36, 36, 38) },
		{ "해변 세종", "Farmhouse Saison", "6.0%", "9,500", rgb(224, 176, 84) },
		{ "민락 스타우트", "Oatmeal Stout", "5.8%", "9,000", rgb(36, 24, 18) },
		{ "쿼드 리저브", "Quadrupel", "10.2%", "13,000", rgb(96, 38, 24) },
	},
	foodTitle = "FOOD  ·  안주",
	food = {
		{ "트러플 감자튀김", nil, nil, "9,000" },
		{ "피쉬 앤 칩스", nil, nil, "18,000" },
		{ "벨기에식 홍합찜", nil, nil, "24,000" },
		{ "수제 소시지 플래터", nil, nil, "19,000" },
		{ "버팔로 윙 8pc", nil, nil, "16,000" },
		{ "치즈 플래터", nil, nil, "22,000" },
		{ "노가리 & 땅콩", nil, nil, "9,000" },
	},
	posters = { "monk", "bridge", "prost", "stout", "rules" },
	plants = { "olive", "ficus" },
	tanks = true,
	kegs = true,
	dart = true,
	festoon = false,
	wifi = "HAPPYMONK_5G\nPW  monk2026!",
	hours = "영업시간\nOPEN 17:00 – 02:00\n금 · 토 03:00까지\nLAST ORDER 01:30",
	mat = "HAPPY MONK",
	bottleMix = { "square", "round", "wine", "squat", "tall" },
}

THEMES.wave = {
	key = "wave",
	tapWall = true,
	brand = "WILD WAVE",
	crown = "WILD WAVE  ·  SURF BREWING  ·  BUSAN",
	font = F.Bangers,
	dark = wood(150, 112, 74),
	mid = wood(190, 152, 106),
	trim = L.blackMetal,
	cabTop = L.of(210, 206, 196, M.Concrete),
	mirror = L.of(110, 120, 122, M.Glass, { r = 0.3 }),
	seat = L.of(38, 110, 118, M.Leather),
	seatStyle = "channel",
	stool = { style = "wood", frame = wood(172, 132, 88), seat = wood(172, 132, 88) },
	tableTop = wood(178, 138, 94),
	counterFront = "fluted",
	counterFrontL = wood(164, 124, 82),
	counterTop = L.of(206, 202, 192, M.Concrete),
	led = rgb(255, 204, 150),
	floor = { look = L.of(160, 158, 152, M.Concrete), tile = 4, grout = L.of(120, 118, 114) },
	lower = { kind = "louver", h = 3.6, look = wood(178, 138, 94), back = L.of(36, 66, 72), walls = { "left", "right" } },
	feature = { wall = "left", look = L.of(232, 228, 218, M.Brick) },
	paint = L.of(34, 74, 84),
	ceil = L.of(34, 36, 38),
	pendant = { shade = "cone", look = L.of(30, 92, 102, M.Metal) },
	tablePendant = "bulb",
	neonC = rgb(80, 220, 255),
	neon2 = rgb(255, 120, 180),
	neonText = "RIDE THE WAVE",
	neonIcon = "wave",
	neonFont = F.Bangers,
	shelfLED = rgb(200, 236, 255),
	board = "digital",
	boardTitle = "ON TAP  ·  WILD WAVE BREWING",
	boardSub = "500ml  ·  광안리 해변에서 만든 서핑 맥주",
	boardFoot = "그라울러 포장 1L 18,000원~  ·  해피아워 17-19시",
	taps = {
		{ "와일드 필스너", "Pilsner", "4.8%", "7,500", rgb(240, 206, 110), "PILS", rgb(250, 250, 246) },
		{ "서프 페일에일", "American Pale Ale", "5.3%", "8,500", rgb(226, 164, 64), "PALE", rgb(40, 150, 170) },
		{ "광안 헤이지 IPA", "Hazy IPA", "6.5%", "9,500", rgb(236, 190, 90), "HAZY", rgb(250, 190, 60) },
		{ "타이드 고제", "Sea Salt Gose", "4.2%", "9,000", rgb(236, 210, 150), "GOSE", rgb(80, 200, 220) },
		{ "빅 스웰 DIPA", "Double IPA", "8.2%", "11,000", rgb(214, 130, 40) },
		{ "블랙 타이드", "Porter", "5.6%", "9,000", rgb(44, 28, 20) },
		{ "선셋 앰버", "Amber Ale", "5.2%", "8,500", rgb(170, 84, 36) },
		{ "유자 위트", "Yuzu Wheat", "4.6%", "8,500", rgb(244, 216, 120) },
	},
	foodTitle = "BEACH FOOD",
	food = {
		{ "감바스 알 아히요", nil, nil, "19,000" },
		{ "피쉬 타코 3pc", nil, nil, "15,000" },
		{ "새우튀김 & 칩스", nil, nil, "17,000" },
		{ "클램 차우더", nil, nil, "12,000" },
		{ "할라피뇨 나초", nil, nil, "13,000" },
		{ "감자튀김", nil, nil, "8,000" },
	},
	posters = { "surf", "bridge", "ipa", "map" },
	plants = { "bamboo", "monstera" },
	tanks = true,
	kegs = true,
	dart = false,
	festoon = true,
	surf = true,
	wifi = "WILDWAVE_FREE\nPW  surf2026",
	hours = "영업시간\nOPEN 15:00 – 01:00\n연중무휴\nLAST ORDER 24:30",
	mat = "WILD WAVE",
	bottleMix = { "round", "tall", "square", "wine" },
}

THEMES.tap = {
	key = "tap",
	tapWall = true,
	brand = "광안 탭하우스",
	crown = "GWANGAN TAP HOUSE  ·  20 TAPS",
	font = F.Oswald,
	dark = L.of(38, 38, 40, M.Metal),
	mid = wood(150, 110, 72),
	trim = L.of(176, 180, 184, M.Metal, { r = 0.06 }),
	cabTop = wood(150, 110, 72),
	mirror = L.of(70, 72, 74, M.Glass, { r = 0.3 }),
	seat = L.of(120, 74, 44, M.Leather),
	seatStyle = "channel",
	stool = { style = "bar", frame = L.blackMetal, seat = L.of(120, 74, 44, M.Leather) },
	tableTop = wood(150, 110, 72),
	counterFront = "tile",
	counterFrontL = L.of(236, 236, 230, M.CeramicTiles),
	counterTop = wood(140, 100, 64),
	led = rgb(255, 200, 130),
	floor = { look = L.of(150, 148, 144, M.Concrete), tile = 4, grout = L.of(108, 106, 102) },
	lower = { kind = "tile", h = 4.2, look = L.tileWhite, grout = L.of(70, 70, 72), tw = 0.6, th = 0.3, walls = { "left", "right" } },
	feature = { wall = "right", look = L.of(116, 66, 52, M.Brick) },
	paint = L.of(42, 44, 46),
	ceil = L.of(30, 30, 32),
	pendant = { shade = "bulb" },
	tablePendant = "cone",
	neonC = rgb(255, 214, 150),
	neon2 = rgb(255, 120, 60),
	neonText = "TAP HOUSE",
	neonIcon = "mug",
	neonFont = F.Oswald,
	shelfLED = rgb(255, 214, 170),
	board = "chalk",
	boardTitle = "TODAY'S TAP LIST",
	boardSub = "부산 · 국내 크래프트 생맥주  ·  473ml",
	boardFoot = "탭은 매주 바뀝니다  ·  시음은 직원에게 말씀해 주세요",
	taps = {
		{ "광안 라거", "Helles Lager", "4.6%", "7,000", rgb(240, 206, 110), "LAGER", rgb(220, 180, 60) },
		{ "해운대 필스너", "Czech Pils", "5.0%", "7,500", rgb(236, 196, 92), "PILS", rgb(40, 90, 160) },
		{ "다이아몬드 IPA", "IPA", "6.4%", "9,000", rgb(214, 140, 48), "IPA", rgb(190, 40, 40) },
		{ "수영강 헤페", "Hefeweizen", "5.2%", "8,000", rgb(236, 190, 96), "WEIZEN", rgb(240, 236, 220) },
		{ "민락 레드", "Irish Red Ale", "5.0%", "8,000", rgb(150, 56, 30) },
		{ "부산항 포터", "Robust Porter", "6.0%", "8,500", rgb(40, 26, 18) },
		{ "감귤 사워", "Fruit Sour", "4.5%", "9,000", rgb(240, 150, 70) },
		{ "오륙도 DIPA", "Double IPA", "8.0%", "10,500", rgb(220, 140, 40) },
	},
	foodTitle = "SNACKS",
	food = {
		{ "수제 피클 & 올리브", nil, nil, "6,000" },
		{ "트러플 감자튀김", nil, nil, "10,000" },
		{ "수제 소시지 2종", nil, nil, "15,000" },
		{ "바베큐 폭립", nil, nil, "26,000" },
		{ "맥앤치즈", nil, nil, "12,000" },
		{ "프레첼 & 머스터드", nil, nil, "8,000" },
	},
	posters = { "map", "ipa", "rules", "bridge" },
	plants = { "snake" },
	tanks = true,
	kegs = true,
	dart = true,
	festoon = false,
	wifi = "GWANGAN_TAP\nPW  20taps!",
	hours = "영업시간\nOPEN 16:00 – 01:00\n월요일 휴무\nLAST ORDER 24:30",
	mat = "TAP HOUSE",
	bottleMix = { "round", "square", "tall" },
}

THEMES.sunset = {
	key = "sunset",
	brand = "SUNSET PUB",
	crown = "SUNSET PUB  ·  SPORTS & BEER",
	font = F.GothamBlack,
	dark = wood(84, 56, 38),
	mid = wood(130, 90, 58),
	trim = L.brass,
	cabTop = L.of(38, 38, 40, M.Granite),
	mirror = L.of(86, 80, 74, M.Glass, { r = 0.3 }),
	seat = L.of(168, 92, 52, M.Leather),
	seatStyle = "channel",
	stool = { style = "cushion", frame = L.blackMetal, seat = L.of(168, 92, 52, M.Leather) },
	tableTop = wood(140, 96, 60),
	counterFront = "panel",
	counterFrontL = L.of(34, 44, 70),
	counterTop = wood(90, 58, 36),
	led = rgb(255, 150, 80),
	floor = { look = L.of(112, 76, 50, M.WoodPlanks), tile = 0 },
	lower = { kind = "wainscot", h = 3.4, look = L.of(32, 42, 68), cap = wood(92, 62, 40), panel = 1.7, walls = { "left", "right", "back" } },
	feature = { wall = "left", look = L.of(118, 70, 54, M.Brick) },
	paint = L.of(70, 50, 44),
	ceil = L.of(30, 30, 34),
	pendant = { shade = "dome", look = L.of(196, 92, 52, M.Metal) },
	tablePendant = "bulb",
	neonC = rgb(255, 128, 60),
	neon2 = rgb(255, 60, 140),
	neonText = "SUNSET",
	neonIcon = "sun",
	neonFont = F.FredokaOne,
	shelfLED = rgb(255, 170, 110),
	board = "digital",
	boardTitle = "BEER & DRINKS",
	boardSub = "생맥주 · 수입맥주 · 하이볼",
	boardFoot = "스포츠 중계 있는 날 피처 2,000원 할인",
	taps = {
		{ "생맥주 (라거) 500cc", "Draft Lager", "4.8%", "5,500", rgb(240, 200, 100), "LAGER", rgb(250, 120, 40) },
		{ "생맥주 1,000cc", "Draft Lager", "4.8%", "9,900", rgb(240, 200, 100), "DARK", rgb(30, 30, 34) },
		{ "피처 3,000cc", "Pitcher", "4.8%", "22,000", rgb(240, 200, 100), "IPA", rgb(40, 120, 200) },
		{ "흑맥주 500cc", "Dark Lager", "5.0%", "6,500", rgb(50, 30, 20), "WHEAT", rgb(250, 230, 160) },
		{ "부산 IPA 473ml", "IPA", "6.5%", "8,900", rgb(214, 140, 48) },
		{ "하이볼", "Whisky Highball", "7%", "9,000", rgb(230, 190, 110) },
		{ "소맥 세트 (소주 1 + 500cc 2)", "Somaek", "", "15,000", rgb(250, 250, 240) },
		{ "칵테일 (모히또 · 선라이즈)", "Cocktail", "", "9,900", rgb(250, 120, 80) },
	},
	foodTitle = "PUB FOOD",
	food = {
		{ "감자튀김", nil, nil, "8,000" },
		{ "치킨 텐더 & 칩스", nil, nil, "14,000" },
		{ "버팔로 윙", nil, nil, "15,000" },
		{ "나초 플래터", nil, nil, "12,000" },
		{ "소시지 야채볶음", nil, nil, "17,000" },
		{ "먹태 & 청양마요", nil, nil, "13,000" },
	},
	posters = { "lotte", "sunsetp", "prost", "rules" },
	plants = { "monstera", "snake" },
	tanks = false,
	kegs = true,
	dart = true,
	festoon = true,
	wifi = "SUNSET_PUB_5G\nPW  sunset0909",
	hours = "영업시간\nOPEN 11:00 – 02:00\n스포츠 중계 시 연장\nLAST ORDER 01:30",
	mat = "SUNSET",
	bottleMix = { "square", "round", "tall", "squat" },
}

THEMES.fuzzy = {
	key = "fuzzy",
	brand = "FUZZY NAVEL",
	crown = "FUZZY NAVEL  ·  COCKTAIL BAR",
	font = F.Bangers,
	dark = L.of(28, 24, 28, M.Wood),
	mid = L.of(64, 40, 58, M.Wood),
	trim = L.goldMetal,
	cabTop = L.of(236, 232, 226, M.Marble),
	mirror = L.of(110, 90, 72, M.Glass, { r = 0.36 }),
	seat = L.of(122, 44, 94, M.Fabric),
	seatStyle = "channel",
	stool = { style = "cushion", frame = L.goldMetal, seat = L.of(122, 44, 94, M.Fabric) },
	tableTop = L.of(236, 232, 226, M.Marble),
	counterFront = "fluted",
	counterFrontL = L.of(36, 30, 38, M.Wood),
	counterTop = L.of(236, 232, 226, M.Marble),
	led = rgb(255, 90, 180),
	floor = { look = L.of(40, 38, 42, M.Marble), tile = 2.5, grout = L.of(150, 120, 70) },
	lower = { kind = "paint", h = 3.6, look = L.of(30, 52, 50), cap = L.goldMetal, walls = { "left", "right", "back" } },
	feature = { wall = "left", look = L.of(70, 40, 74, M.Fabric) },
	paint = L.of(58, 36, 64),
	ceil = L.of(20, 18, 22),
	pendant = { shade = "globe", look = L.of(240, 206, 226, M.Glass, { t = 0.3 }) },
	tablePendant = "globe",
	neonC = rgb(255, 80, 180),
	neon2 = rgb(150, 100, 255),
	neonText = "Fuzzy Navel",
	neonIcon = "cocktail",
	neonFont = F.FredokaOne,
	shelfLED = rgb(255, 150, 220),
	board = "brass",
	boardTitle = "SIGNATURE COCKTAILS",
	boardSub = "바텐더 추천  ·  모든 칵테일 논알콜 가능",
	boardFoot = "칵테일 2잔 이상 주문 시 나쵸 서비스",
	taps = {
		{ "퍼지 네이블", "피치 · 오렌지", "8%", "12,000", rgb(255, 160, 80), "PEACH", rgb(255, 150, 90) },
		{ "모히또", "럼 · 라임 · 민트", "10%", "13,000", rgb(170, 230, 140), "MOJITO", rgb(90, 200, 120) },
		{ "광안 선셋", "보드카 · 패션후르츠", "12%", "14,000", rgb(255, 110, 90), "SUNSET", rgb(255, 90, 140) },
		{ "롱아일랜드 아이스티", "5 Spirits · 콜라", "22%", "15,000", rgb(150, 80, 40), "LIIT", rgb(60, 60, 64) },
		{ "마가리타", "데킬라 · 라임", "15%", "13,000", rgb(220, 240, 170) },
		{ "에스프레소 마티니", "보드카 · 커피", "18%", "14,000", rgb(60, 36, 26) },
		{ "진토닉", "진 · 토닉 · 라임", "10%", "11,000", rgb(230, 244, 240) },
		{ "하이볼", "위스키 · 소다", "9%", "10,000", rgb(230, 186, 100) },
	},
	foodTitle = "BAR BITES",
	food = {
		{ "치즈 & 크래커", nil, nil, "15,000" },
		{ "제철 과일 플래터", nil, nil, "25,000" },
		{ "트러플 감자튀김", nil, nil, "11,000" },
		{ "나쵸 & 과카몰리", nil, nil, "13,000" },
		{ "초콜릿 퐁듀", nil, nil, "16,000" },
	},
	posters = { "cocktail", "deco", "bridge" },
	plants = { "snake", "monstera" },
	tanks = false,
	kegs = false,
	dart = false,
	festoon = false,
	glassRack = true,
	wifi = "FUZZYNAVEL_BAR\nPW  peach1212",
	hours = "영업시간\nOPEN 24 HOURS\n연중무휴\n해피아워 17:00 – 20:00",
	mat = "FUZZY NAVEL",
	bottleMix = { "square", "round", "wine", "squat", "tall", "round" },
}

THEMES.party = extend(THEMES.sunset, {
	key = "party",
	brand = "THURSDAY PARTY",
	crown = "THURSDAY PARTY  ·  광안리점",
	dark = L.of(26, 26, 30, M.SmoothPlastic),
	mid = L.of(52, 52, 58, M.SmoothPlastic),
	trim = L.chrome,
	cabTop = L.of(30, 30, 34, M.Granite),
	mirror = L.of(60, 60, 70, M.Glass, { r = 0.34 }),
	seat = L.of(30, 30, 34, M.Leather),
	stool = { style = "bar", frame = L.chrome, seat = L.of(200, 40, 60, M.Leather) },
	tableTop = L.of(30, 30, 34, M.Granite),
	counterFront = "panel",
	counterFrontL = L.of(26, 26, 30),
	counterTop = L.of(28, 28, 32, M.Granite),
	led = rgb(130, 90, 255),
	floor = { look = L.of(32, 32, 36, M.Slate), tile = 3, grout = L.of(64, 64, 72) },
	lower = { kind = "paint", h = 3.4, look = L.of(26, 26, 30), cap = L.chrome, walls = { "left", "right", "back" } },
	feature = nil,
	paint = L.of(22, 22, 26),
	ceil = L.of(18, 18, 20),
	pendant = { shade = "cone", look = L.chrome },
	neonC = rgb(255, 60, 200),
	neon2 = rgb(60, 220, 255),
	neonText = "PARTY ALL NIGHT",
	neonIcon = "star",
	board = "digital",
	boardTitle = "PARTY DRINKS",
	boardSub = "목요일은 파티 데이!",
	boardFoot = "생일 · 단체 예약 시 샴페인 서비스",
	taps = {
		{ "생맥주 500cc", "Draft", "4.8%", "4,500", rgb(240, 200, 100), "BEER", rgb(255, 60, 200) },
		{ "생맥주 피처 2,000cc", "Pitcher", "4.8%", "15,000", rgb(240, 200, 100), "PITCH", rgb(60, 220, 255) },
		{ "예거밤", "Jäger Bomb", "", "9,000", rgb(60, 30, 20), "BOMB", rgb(250, 200, 40) },
		{ "데킬라 샷", "Tequila Shot", "40%", "5,000", rgb(250, 230, 160), "SHOT", rgb(240, 240, 240) },
		{ "칵테일 타워 3L", "Cocktail Tower", "", "39,000", rgb(255, 90, 140) },
		{ "보드카 1병 세트", "Vodka + Mixer", "", "89,000", rgb(240, 244, 250) },
		{ "하이볼", "Highball", "7%", "8,000", rgb(230, 190, 110) },
		{ "소맥 타워", "Somaek Tower", "", "29,000", rgb(250, 240, 200) },
	},
	posters = { "party", "prost", "deco" },
	plants = { "snake" },
	festoon = false,
	disco = true,
	dart = true,
	wifi = "THURSDAY_PARTY\nPW  party2026",
	hours = "영업시간\nOPEN 19:00 – 05:00\n목 · 금 · 토 파티 나이트",
	mat = "THURSDAY PARTY",
})

THEMES.dogs = extend(THEMES.monk, {
	key = "dogs",
	brand = "MAD DOGS",
	crown = "MAD DOGS  ·  IRISH PUB",
	seat = L.of(120, 72, 44, M.Leather),
	seatStyle = "channel",
	paint = L.of(30, 58, 44),
	neonC = rgb(90, 255, 120),
	neonText = "MAD DOGS",
	neonIcon = "mug",
	tanks = false,
	boardTitle = "ON TAP  ·  IRISH PUB",
	taps = {
		{ "아이리시 스타우트", "Dry Stout", "4.2%", "9,000", rgb(30, 20, 16), "STOUT", rgb(30, 30, 30) },
		{ "레드 에일", "Irish Red", "4.8%", "8,500", rgb(150, 56, 30), "RED", rgb(170, 40, 40) },
		{ "골든 라거", "Lager", "4.6%", "7,000", rgb(240, 200, 100), "LAGER", rgb(230, 190, 60) },
		{ "사이더", "Apple Cider", "4.5%", "8,500", rgb(230, 190, 90), "CIDER", rgb(90, 160, 60) },
		{ "아이리시 위스키 샷", "Whiskey", "40%", "9,000", rgb(180, 110, 40) },
		{ "아이리시 커피", "Hot", "", "11,000", rgb(80, 50, 30) },
	},
	posters = { "stout", "prost", "rules" },
	wifi = "MADDOGS_PUB\nPW  slainte!",
	hours = "영업시간\nOPEN 11:00 – 02:00\n연중무휴",
	mat = "MAD DOGS",
})

THEMES.holiday = extend(THEMES.wave, {
	key = "holiday",
	brand = "WORKING HOLIDAY",
	crown = "WORKING HOLIDAY  ·  AUSSIE PUB",
	neonText = "G'DAY MATE",
	neonIcon = "sun",
	neonC = rgb(255, 190, 60),
	tanks = false,
	boardTitle = "AUSSIE BEERS",
	taps = {
		{ "오지 라거", "Australian Lager", "4.6%", "7,000", rgb(240, 206, 110), "AUSSIE", rgb(250, 190, 40) },
		{ "쿠퍼스 스타일 페일", "Pale Ale", "4.5%", "8,500", rgb(230, 180, 90), "PALE", rgb(40, 120, 60) },
		{ "골드코스트 IPA", "IPA", "6.0%", "9,000", rgb(214, 140, 48), "IPA", rgb(40, 90, 170) },
		{ "시드니 다크", "Dark Ale", "5.5%", "8,500", rgb(70, 40, 24), "DARK", rgb(30, 30, 34) },
		{ "미트 파이", "Meat Pie", "", "9,000", rgb(190, 130, 70) },
		{ "칩스 & 그레이비", "Chips", "", "8,000", rgb(230, 190, 110) },
	},
	posters = { "surf", "map", "prost" },
	wifi = "WORKING_HOLIDAY\nPW  gday2026",
	hours = "영업시간\nOPEN 12:00 – 01:00\n화요일 휴무",
	mat = "G'DAY",
})

THEMES.bat = extend(THEMES.sunset, {
	key = "bat",
	brand = "BEER BAT",
	crown = "BEER BAT  ·  BASEBALL PUB",
	neonText = "BEER BAT",
	neonIcon = "ball",
	neonC = rgb(255, 70, 60),
	neon2 = rgb(80, 160, 255),
	counterFrontL = L.of(20, 36, 80),
	lower = { kind = "wainscot", h = 3.4, look = L.of(20, 34, 76), cap = L.of(200, 40, 40), panel = 1.7, walls = { "left", "right", "back" } },
	posters = { "lotte", "lotte2", "prost", "rules" },
	bats = true,
	boardTitle = "직관보다 맛있는 생맥",
	boardFoot = "롯데 승리한 날 생맥 500cc 1잔 무료!",
	wifi = "BEERBAT_GIANTS\nPW  lotte1982",
	mat = "BEER BAT",
})

-- 간판 이름 (모델 이름이 SideShop 같은 일반 이름일 때: 가장 큰 Sign_ 글자)
local GENERIC_SIGN = { "화장실", "OPEN", "BREAK", "TODAY", "영업", "메  뉴", "MENU", "EXIT", "비상구", "CLOSE" }
local function shopName(V: any): string
	local best, area = nil, 0
	for _, r in V.parts or {} do
		if string.sub(r.name, 1, 5) == "Sign_" then
			local t = string.sub(r.name, 6)
			local generic = false
			for _, g in GENERIC_SIGN do
				if string.find(string.upper(t), g, 1, true) then
					generic = true
				end
			end
			local a = math.max(r.size.X, r.size.Z) * r.size.Y
			if not generic and #t > 1 and a > area then
				best, area = t, a
			end
		end
	end
	local nm = tostring(V.name or "")
	if best and (nm == "" or nm == "SideShop" or string.find(nm, "Shop", 1, true) or string.find(nm, "Annex", 1, true)) then
		return best
	end
	return if nm ~= "" then nm else (best or "PUB")
end
T.shopName = shopName

local function pickTheme(V: any): any
	local nameStr = shopName(V)
	local n = string.upper(nameStr)
	local function has(s: string): boolean
		return string.find(n, s, 1, true) ~= nil
	end
	if has("MONK") then
		return THEMES.monk
	elseif has("WILD WAVE") or has("와일드") then
		return THEMES.wave
	elseif has("탭하우스") or has("TAP HOUSE") or has("TAPHOUSE") then
		return THEMES.tap
	elseif has("FUZZY") or V.menu == "cocktail" then
		return THEMES.fuzzy
	elseif has("THURSDAY") or V.menu == "party" then
		return THEMES.party
	elseif has("MAD DOG") then
		return THEMES.dogs
	elseif has("WORKING HOLIDAY") then
		return THEMES.holiday
	elseif has("BEER BAT") then
		return THEMES.bat
	elseif has("SUNSET") then
		local t = extend(THEMES.sunset, { brand = nameStr })
		if has("ROOFTOP") then
			t.crown = "SUNSET ROOFTOP  ·  BAR & LOUNGE"
		end
		return t
	elseif V.menu == "craft" then
		return extend(THEMES.tap, { brand = nameStr, crown = nameStr .. "  ·  CRAFT BEER" })
	end
	return extend(THEMES.sunset, { brand = nameStr, crown = nameStr .. "  ·  PUB" })
end
T.pickTheme = pickTheme

-- 술병 · 맥주병 · 캔 --------------------------------------------------------------------------------------
local GLASS = {
	rgb(150, 86, 30), -- 앰버 (위스키 · 럼)
	rgb(96, 56, 24), -- 갈색
	rgb(226, 234, 236), -- 투명 (보드카 · 진 · 데킬라)
	rgb(40, 96, 56), -- 녹색 (와인 · 압생트 · 리큐르)
	rgb(40, 84, 160), -- 파랑 (진)
	rgb(70, 66, 62), -- 스모크
	rgb(150, 30, 34), -- 빨강 (비터)
	rgb(214, 168, 70), -- 골드 리큐르
	rgb(30, 28, 26), -- 검정 (허브 리큐르)
}
local LABELS = { rgb(244, 236, 214), rgb(30, 30, 32), rgb(196, 40, 40), rgb(236, 200, 90), rgb(240, 240, 240), rgb(40, 70, 120) }

local function bottle(K: any, base: CFrame, h: number, kind: string, gc: Color3, lab: Color3, cap: any, detail: string)
	local clear = gc.R > 0.8 and gc.G > 0.8
	local gl = { c = gc, m = M.Glass, t = if clear then 0.42 else 0.16, r = 0.12 }
	local labL = { c = lab, m = M.SmoothPlastic }
	if kind == "square" then
		local bh = h * 0.64
		K:box("Bottle", V3(0.34, bh, 0.3), base * CF(0, bh / 2, 0), gl)
		K:vcyl("BottleNeck", h * 0.26, 0.13, base * CF(0, bh + h * 0.13, 0), gl)
		K:vcyl("BottleCap", h * 0.1, 0.17, base * CF(0, h * 0.95, 0), cap)
		if detail ~= "low" then
			K:box("BottleLabel", V3(0.28, bh * 0.42, 0.012), base * CF(0, bh * 0.46, 0.156), labL)
		end
	elseif kind == "wine" then
		local bh = h * 0.56
		K:vcyl("Bottle", bh, 0.28, base * CF(0, bh / 2, 0), gl)
		K:ell("BottleShoulder", V3(0.28, 0.24, 0.28), base * CF(0, bh, 0), gl)
		K:vcyl("BottleNeck", h * 0.32, 0.1, base * CF(0, bh + h * 0.16 + 0.03, 0), gl)
		K:vcyl("BottleFoil", h * 0.12, 0.115, base * CF(0, h * 0.94, 0), cap)
		if detail ~= "low" then
			K:box("BottleLabel", V3(0.2, bh * 0.4, 0.012), base * CF(0, bh * 0.5, 0.142), labL)
		end
	elseif kind == "squat" then
		local bh = h * 0.55
		K:ell("Bottle", V3(0.44, bh, 0.44), base * CF(0, bh / 2, 0), gl)
		K:vcyl("BottleNeck", h * 0.4, 0.12, base * CF(0, h * 0.7, 0), gl)
		K:vcyl("BottleCap", h * 0.12, 0.17, base * CF(0, h * 0.94, 0), cap)
		if detail ~= "low" then
			K:box("BottleLabel", V3(0.22, bh * 0.36, 0.012), base * CF(0, bh * 0.48, 0.21), labL)
		end
	else
		local d = if kind == "tall" then 0.25 else 0.31
		local bh = h * (if kind == "tall" then 0.7 else 0.6)
		K:vcyl("Bottle", bh, d, base * CF(0, bh / 2, 0), gl)
		K:ell("BottleShoulder", V3(d, 0.18, d), base * CF(0, bh, 0), gl)
		K:vcyl("BottleNeck", h * 0.92 - bh, 0.11, base * CF(0, (bh + h * 0.92) / 2, 0), gl)
		K:vcyl("BottleCap", h * 0.09, 0.14, base * CF(0, h * 0.955, 0), cap)
		if detail ~= "low" then
			K:box("BottleLabel", V3(d * 0.72, bh * 0.4, 0.012), base * CF(0, bh * 0.45, d / 2 + 0.004), labL)
		end
	end
	if clear and detail == "high" then
		-- 투명한 병 속 술 (조금 남은 높이)
		local fh = h * 0.42
		local fd = if kind == "square" then 0.26 elseif kind == "squat" then 0.3 elseif kind == "wine" then 0.22 elseif kind == "tall" then 0.2 else 0.25
		K:vcyl("BottleSpirit", fh, fd, base * CF(0, fh / 2 + 0.02, 0), { c = rgb(246, 236, 210), m = M.Glass, t = 0.55 })
	end
end

-- 작은 맥주병 (쿨러 · 진열 선반)
local function beerBottle(K: any, base: CFrame, gc: Color3, lab: Color3, detail: string)
	local gl = { c = gc, m = M.Glass, t = 0.12, r = 0.1 }
	K:vcyl("BeerBottle", 0.36, 0.18, base * CF(0, 0.18, 0), gl)
	K:vcyl("BeerBottleNeck", 0.22, 0.08, base * CF(0, 0.46, 0), gl)
	K:vcyl("BeerBottleCap", 0.04, 0.095, base * CF(0, 0.585, 0), L.goldMetal)
	if detail == "high" then
		K:box("BeerLabel", V3(0.14, 0.15, 0.012), base * CF(0, 0.19, 0.092), { c = lab })
	end
end

-- 473ml 크래프트 캔
local function beerCan(K: any, base: CFrame, c: Color3, band: Color3, detail: string)
	K:vcyl("BeerCan", 0.46, 0.21, base * CF(0, 0.23, 0), { c = c, m = M.SmoothPlastic })
	K:vcyl("BeerCanTop", 0.03, 0.18, base * CF(0, 0.475, 0), L.alu)
	if detail == "high" then
		K:vcyl("BeerCanBand", 0.12, 0.214, base * CF(0, 0.27, 0), { c = band })
	end
end

-- 네온 관 (dcf 평면 위 폴리라인, 단위 s) --------------------------------------------------------------------
local function nline(K: any, dcf: CFrame, pts: { { number } }, s: number, z: number, d: number, look: any, out: { BasePart })
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local p = K:seg("NeonTube", (dcf * CF(a[1] * s, a[2] * s, z)).Position, (dcf * CF(b[1] * s, b[2] * s, z)).Position, d, look, d * 0.7)
		if p then
			table.insert(out, p)
		end
	end
end

local function narc(K: any, dcf: CFrame, cx: number, cy: number, r: number, a0: number, a1: number, n: number, s: number, z: number, d: number, look: any, out: { BasePart })
	local pts = {}
	for i = 0, n do
		local a = a0 + (a1 - a0) * i / n
		table.insert(pts, { cx + math.cos(a) * r, cy + math.sin(a) * r })
	end
	nline(K, dcf, pts, s, z, d, look, out)
end

-- 아이콘 (단위 상자 -0.5..0.5)
local function neonIcon(K: any, dcf: CFrame, kind: string, s: number, c: Color3, c2: Color3, out: { BasePart })
	local d = math.clamp(s * 0.045, 0.05, 0.09)
	local lk, lk2 = L.neon(c), L.neon(c2)
	local z = 0.12
	if kind == "mug" then
		nline(K, dcf, { { -0.3, -0.45 }, { 0.18, -0.45 }, { 0.22, 0.26 }, { -0.34, 0.26 }, { -0.3, -0.45 } }, s, z, d, lk, out)
		narc(K, dcf, 0.24, -0.08, 0.16, -1.35, 1.35, 6, s, z, d, lk, out)
		narc(K, dcf, -0.22, 0.3, 0.11, 0, PI, 5, s, z, d, lk2, out)
		narc(K, dcf, -0.02, 0.33, 0.12, 0, PI, 5, s, z, d, lk2, out)
		narc(K, dcf, 0.16, 0.3, 0.08, 0, PI, 4, s, z, d, lk2, out)
		nline(K, dcf, { { -0.16, -0.32 }, { -0.15, 0.12 } }, s, z, d * 0.8, lk, out)
		nline(K, dcf, { { 0.03, -0.32 }, { 0.05, 0.12 } }, s, z, d * 0.8, lk, out)
	elseif kind == "wave" then
		local p1, p2 = {}, {}
		for i = 0, 14 do
			local t = i / 14
			table.insert(p1, { -0.5 + t, 0.08 + 0.14 * math.sin(t * PI * 3) })
			table.insert(p2, { -0.45 + t * 0.9, -0.2 + 0.09 * math.sin(t * PI * 3 + 1) })
		end
		nline(K, dcf, p1, s, z, d, lk, out)
		nline(K, dcf, p2, s, z, d, lk, out)
		narc(K, dcf, 0.28, 0.36, 0.1, 0, 2 * PI, 8, s, z, d, lk2, out)
	elseif kind == "sun" then
		narc(K, dcf, 0, -0.12, 0.3, 0, PI, 10, s, z, d, lk, out)
		for k = 0, 6 do
			local a = PI * k / 6
			nline(K, dcf, { { math.cos(a) * 0.38, -0.12 + math.sin(a) * 0.38 }, { math.cos(a) * 0.5, -0.12 + math.sin(a) * 0.5 } }, s, z, d, lk, out)
		end
		nline(K, dcf, { { -0.5, -0.14 }, { 0.5, -0.14 } }, s, z, d, lk2, out)
		nline(K, dcf, { { -0.34, -0.3 }, { 0.34, -0.3 } }, s, z, d, lk2, out)
		nline(K, dcf, { { -0.18, -0.44 }, { 0.18, -0.44 } }, s, z, d, lk2, out)
	elseif kind == "cocktail" then
		nline(K, dcf, { { -0.38, 0.38 }, { 0.38, 0.38 }, { 0, -0.06 }, { -0.38, 0.38 } }, s, z, d, lk, out)
		nline(K, dcf, { { 0, -0.06 }, { 0, -0.42 } }, s, z, d, lk, out)
		nline(K, dcf, { { -0.2, -0.45 }, { 0.2, -0.45 } }, s, z, d, lk, out)
		narc(K, dcf, 0.1, 0.2, 0.07, 0, 2 * PI, 6, s, z, d, lk2, out)
		nline(K, dcf, { { 0.1, 0.2 }, { 0.3, 0.5 } }, s, z, d * 0.8, lk2, out)
	elseif kind == "star" then
		local pts = {}
		for k = 0, 10 do
			local a = PI / 2 + k * PI / 5
			local r = if k % 2 == 0 then 0.48 else 0.2
			table.insert(pts, { math.cos(a) * r, math.sin(a) * r })
		end
		nline(K, dcf, pts, s, z, d, lk, out)
		narc(K, dcf, 0, 0, 0.08, 0, 2 * PI, 6, s, z, d, lk2, out)
	elseif kind == "ball" then
		narc(K, dcf, 0, 0, 0.42, 0, 2 * PI, 16, s, z, d, lk2, out)
		narc(K, dcf, -0.66, 0, 0.44, -0.75, 0.75, 5, s, z, d, lk, out)
		narc(K, dcf, 0.66, 0, 0.44, PI - 0.75, PI + 0.75, 5, s, z, d, lk, out)
	end
end

-- 네온사인 묶음: 아크릴 뒤판 + 스탠드오프 + 아이콘 + 글자. store = { parts, labels, lights }
local function neonSign(K: any, dcf: CFrame, w: number, h: number, th: any, icon: string?, text: string, c: Color3, c2: Color3, store: any)
	K:panel("NeonBacker", w, h, 0.05, math.min(0.3, h * 0.2), dcf, { c = rgb(14, 14, 18), m = M.SmoothPlastic, r = 0.06 })
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			K:cyl("NeonStandoff", 0.17, 0.08, dcf * CF(sx * (w / 2 - 0.22), sy * (h / 2 - 0.18), 0.0) * ANG(0, PI / 2, 0), L.chrome)
		end
	end
	local iconW = if icon then math.min(h * 0.92, w * 0.4) else 0
	if icon then
		neonIcon(K, dcf * CF(-w / 2 + iconW / 2 + 0.2, 0, 0), icon, iconW, c, c2, store.parts)
	end
	local tw = w - iconW - 0.5
	local p, lab = K:text("NeonText", tw, h * 0.66, dcf * CF(iconW / 2 + 0.05, 0, 0.1), text, { fg = c, glow = 2.4, font = th.neonFont or F.FredokaOne, d = 0.02 })
	table.insert(store.labels, lab)
	local lp = store.parts[1] or p
	local li = K:light(lp, "PointLight", { Range = 11, Brightness = 1.15, Color = c })
	if li then
		table.insert(store.lights, li)
	end
	return p
end

-- 보드 (탭 리스트 · 안주 · 칵테일) -------------------------------------------------------------------------
local BOARD = {
	chalk = { face = L.of(36, 42, 40, M.Slate), frame = wood(86, 58, 38), fg = rgb(236, 234, 222), acc = rgb(250, 214, 110), dim = rgb(176, 186, 180), font = F.PermanentMarker, titleFont = F.PermanentMarker, glow = 1.0 },
	digital = { face = L.of(14, 16, 20, M.SmoothPlastic, { r = 0.02 }), frame = L.of(24, 24, 26, M.Metal), fg = rgb(246, 246, 246), acc = rgb(255, 196, 60), dim = rgb(150, 170, 190), font = F.GothamMedium, titleFont = F.GothamBlack, glow = 1.3 },
	brass = { face = L.of(18, 16, 20), frame = L.goldMetal, fg = rgb(246, 236, 214), acc = rgb(222, 184, 104), dim = rgb(190, 170, 150), font = F.GothamMedium, titleFont = F.Oswald, glow = 1.15 },
}

-- rows = { { 이름, 스타일?, ABV?, 가격, 색? } }
local function listBoard(K: any, dcf: CFrame, w: number, h: number, style: string, title: string, sub: string?, rows: { any }, foot: string?, accent: Color3?)
	local st = BOARD[style] or BOARD.chalk
	local acc = accent or st.acc
	local fr = 0.16
	K:plate("BoardFace", w, h, 0.06, dcf, st.face)
	K:plate("BoardFrame", w + 2 * fr, fr, 0.12, dcf * CF(0, h / 2 + fr / 2, 0), st.frame)
	K:plate("BoardFrame", w + 2 * fr, fr, 0.12, dcf * CF(0, -h / 2 - fr / 2, 0), st.frame)
	K:plate("BoardFrame", fr, h, 0.12, dcf * CF(-w / 2 - fr / 2, 0, 0), st.frame)
	K:plate("BoardFrame", fr, h, 0.12, dcf * CF(w / 2 + fr / 2, 0, 0), st.frame)
	if style == "chalk" then
		-- 분필 받침 + 분필 두 개
		K:plate("BoardLedge", w * 0.5, 0.06, 0.2, dcf * CF(-w * 0.2, -h / 2 - fr - 0.03, 0), st.frame)
		K:box("Chalk", V3(0.3, 0.06, 0.06), dcf * CF(-w * 0.32, -h / 2 - fr + 0.03, 0.12), L.paper)
		K:box("Chalk", V3(0.24, 0.06, 0.06), dcf * CF(-w * 0.18, -h / 2 - fr + 0.03, 0.1) * ANG(0, 0.3, 0), L.of(250, 210, 120))
	end
	local z = 0.065
	local y = h / 2 - 0.12
	local tH = math.min(0.78, h * 0.15)
	K:text("BoardTitle", w * 0.9, tH, dcf * CF(0, y - tH / 2, z), title, { fg = acc, glow = st.glow, font = st.titleFont, d = 0.01 })
	y -= tH + 0.04
	if sub then
		local sH = math.min(0.3, tH * 0.42)
		K:text("BoardSub", w * 0.84, sH, dcf * CF(0, y - sH / 2, z), sub, { fg = st.dim, glow = st.glow, font = st.font, d = 0.01 })
		y -= sH + 0.06
	end
	K:plate("BoardRule", w * 0.9, 0.035, 0.075, dcf * CF(0, y, 0), { c = acc, m = M.SmoothPlastic })
	y -= 0.08
	local footH = if foot then math.min(0.3, h * 0.07) else 0
	local avail = y - (-h / 2 + 0.12 + footH + 0.06)
	local n = #rows
	local rh = math.min(0.62, avail / math.max(1, n))
	local hasMid = false
	for _, r in rows do
		if r[2] or r[3] then
			hasMid = true
		end
	end
	for i, r in rows do
		local yc = y - rh * (i - 0.5)
		local x0 = -w / 2 + 0.22
		local dotW = 0
		if r[5] then
			wdisc(K, "BoardDot", rh * 0.46, 0.02, dcf * CF(x0 + rh * 0.23, yc, 0), 0.06, { c = r[5], m = M.SmoothPlastic })
			dotW = rh * 0.62
		end
		x0 += dotW
		-- 열: 이름 | 스타일 | ABV | 가격 (가격은 오른쪽 끝 정렬)
		local priceW = w * 0.15
		local abvW = w * 0.09
		local priceR = w / 2 - 0.22
		local abvR = priceR - priceW - 0.1
		local nameW = if hasMid then w * 0.38 else (priceR - priceW - 0.15) - x0
		K:text("BoardItem", nameW, rh * 0.6, dcf * CF(x0 + nameW / 2, yc, z), r[1], { fg = st.fg, glow = st.glow, align = "Left", font = st.font, d = 0.01 })
		if r[2] then
			local sx0 = x0 + nameW + 0.08
			local sw = math.max(0.4, (abvR - abvW - 0.08) - sx0)
			K:text("BoardStyle", sw, rh * 0.42, dcf * CF(sx0 + sw / 2, yc, z), r[2], { fg = st.dim, glow = st.glow, align = "Left", font = st.font, d = 0.01 })
		end
		if r[3] and r[3] ~= "" then
			K:text("BoardABV", abvW, rh * 0.46, dcf * CF(abvR - abvW / 2, yc, z), r[3], { fg = st.dim, glow = st.glow, align = "Right", font = st.font, d = 0.01 })
		end
		K:text("BoardPrice", priceW, rh * 0.58, dcf * CF(priceR - priceW / 2, yc, z), r[4], { fg = acc, glow = st.glow, align = "Right", font = F.GothamBold, d = 0.01 })
	end
	if foot then
		K:text("BoardFoot", w * 0.9, footH, dcf * CF(0, -h / 2 + 0.12 + footH / 2, z), foot, { fg = st.dim, glow = st.glow, font = st.font, d = 0.01 })
	end
end

-- 안내판 ---------------------------------------------------------------------------------------------------
local function signPlate(K: any, dcf: CFrame, w: number, h: number, text: string, fg: Color3, bg: Color3, border: Color3?, font: Enum.Font?)
	if border then
		K:plate("SignBorder", w + 0.1, h + 0.1, 0.03, dcf, { c = border, m = M.SmoothPlastic })
	end
	K:text("SignPlate", w, h, dcf * CF(0, 0, 0.03), text, { fg = fg, bg = bg, d = 0.02, font = font or F.GothamBold })
end

-- 포스터 ---------------------------------------------------------------------------------------------------
local function poster(K: any, dcf: CFrame, w: number, h: number, kind: string, th: any)
	local b = 0.09
	local dep = 0.12
	local iw, ih = w - 2 * b - 0.12, h - 2 * b - 0.12
	local zA = dep * 0.7 + 0.004 -- 그림 앞면
	local function blk(c: Color3, x: number, y: number, bw: number, bh: number, z: number?)
		K:plate("PosterArt", iw * bw, ih * bh, 0.004, dcf * CF(-iw / 2 + iw * (x + bw / 2), -ih / 2 + ih * (y + bh / 2), zA + (z or 0)), { c = c, m = M.SmoothPlastic })
	end
	local function txt(t: string, x: number, y: number, tw: number, thh: number, fg: Color3, font: Enum.Font?)
		K:text("PosterText", iw * tw, ih * thh, dcf * CF(-iw / 2 + iw * x, -ih / 2 + ih * y, zA + 0.006), t, { fg = fg, font = font or F.GothamBlack, d = 0.004 })
	end
	local frameL = if kind == "cocktail" or kind == "deco" then L.goldMetal elseif kind == "rules" or kind == "map" then wood(90, 60, 40) else L.blackMetal
	local bg = rgb(30, 30, 34)
	if kind == "bridge" then
		bg = rgb(30, 28, 64)
	elseif kind == "ipa" then
		bg = rgb(58, 108, 62)
	elseif kind == "prost" then
		bg = rgb(238, 226, 196)
	elseif kind == "stout" then
		bg = rgb(20, 18, 18)
	elseif kind == "surf" then
		bg = rgb(40, 150, 160)
	elseif kind == "lotte" or kind == "lotte2" then
		bg = rgb(16, 30, 72)
	elseif kind == "cocktail" or kind == "deco" then
		bg = rgb(16, 16, 20)
	elseif kind == "map" then
		bg = rgb(214, 190, 150)
	elseif kind == "rules" then
		bg = rgb(34, 40, 38)
	elseif kind == "monk" then
		bg = rgb(70, 40, 26)
	elseif kind == "party" then
		bg = rgb(40, 10, 50)
	elseif kind == "sunsetp" then
		bg = rgb(250, 140, 70)
	end
	Props.frame(K, dcf, w, h, { frame = frameL, depth = dep, border = b, mat = { c = bg, m = M.SmoothPlastic } })
	-- 액자 유리: 비스듬히 볼 때 하늘 반사로 그림이 회색으로 덮이지 않게 반사를 낮춤
	for k = #K.parts, math.max(1, #K.parts - 2), -1 do
		local gp = K.parts[k]
		if gp and gp.Name == "FrameGlass" then
			gp.Reflectance = 0.03
			gp.Transparency = 0.93
			break
		end
	end
	local cream = rgb(255, 238, 206)
	if kind == "bridge" then
		blk(rgb(250, 150, 70), 0, 0.42, 1, 0.2)
		blk(rgb(236, 96, 112), 0, 0.3, 1, 0.12)
		blk(rgb(26, 40, 82), 0, 0, 1, 0.3)
		wdisc(K, "PosterSun", iw * 0.26, 0.004, dcf * CF(iw * 0.18, -ih / 2 + ih * 0.5, 0), zA + 0.002, { c = rgb(255, 214, 120) })
		-- 광안대교 (상판 · 주탑 2 · 케이블)
		local deckY = -ih / 2 + ih * 0.33
		K:plate("PosterBridge", iw, ih * 0.02, 0.004, dcf * CF(0, deckY, zA + 0.008), { c = rgb(30, 30, 40) })
		for _, tx in { -0.22, 0.22 } do
			local x = iw * tx
			K:plate("PosterBridge", iw * 0.025, ih * 0.22, 0.004, dcf * CF(x, deckY + ih * 0.11, zA + 0.008), { c = rgb(30, 30, 40) })
			for k = 1, 3 do
				for _, sd in { -1, 1 } do
					local a = (dcf * CF(x, deckY + ih * 0.21, zA + 0.01)).Position
					local bb = (dcf * CF(x + sd * iw * 0.075 * k, deckY, zA + 0.01)).Position
					K:seg("PosterCable", a, bb, 0.012, { c = rgb(40, 40, 54) })
				end
			end
		end
		txt("GWANGALLI\nBEER FEST 2026", 0.5, 0.82, 0.86, 0.26, cream)
		txt("10.23 – 10.25  ·  광안리 해변", 0.5, 0.12, 0.8, 0.06, cream, F.GothamMedium)
	elseif kind == "ipa" then
		blk(rgb(236, 210, 120), 0, 0.88, 1, 0.04)
		for k = 0, 2 do
			K:ell("PosterHop", V3(iw * (0.22 - k * 0.04), ih * 0.1, 0.02), dcf * CF(0, -ih * 0.02 - k * ih * 0.07, zA + 0.01), { c = rgb(150, 196, 90), m = M.SmoothPlastic })
		end
		K:ell("PosterHop", V3(iw * 0.12, ih * 0.05, 0.02), dcf * CF(iw * 0.1, ih * 0.06, zA + 0.012) * ANG(0, 0, 0.6), { c = rgb(90, 150, 70), m = M.SmoothPlastic })
		txt("IPA", 0.5, 0.72, 0.8, 0.2, rgb(250, 236, 180))
		txt("INDIA PALE ALE\n6.5% · 60 IBU · 광안리", 0.5, 0.14, 0.86, 0.12, rgb(250, 236, 180), F.GothamBold)
	elseif kind == "prost" then
		blk(rgb(180, 40, 36), 0, 0.9, 1, 0.1)
		blk(rgb(180, 40, 36), 0, 0, 1, 0.08)
		for _, sd in { -1, 1 } do
			local cx = iw * 0.13 * sd
			local rot = ANG(0, 0, -sd * 0.22)
			K:plate("PosterMug", iw * 0.2, ih * 0.22, 0.004, dcf * CF(cx, ih * 0.02, zA + 0.008) * rot, { c = rgb(236, 164, 50) })
			K:plate("PosterFoam", iw * 0.22, ih * 0.05, 0.004, dcf * CF(cx, ih * 0.02, zA + 0.012) * rot * CF(0, ih * 0.12, 0), { c = rgb(252, 250, 240) })
		end
		txt("PROST!", 0.5, 0.74, 0.8, 0.14, rgb(160, 34, 30))
		txt("건배 · CHEERS · 乾杯 · SALUD", 0.5, 0.18, 0.86, 0.07, rgb(60, 40, 30), F.GothamBold)
	elseif kind == "stout" then
		K:plate("PosterPint", iw * 0.3, ih * 0.4, 0.004, dcf * CF(0, -ih * 0.06, zA + 0.008), { c = rgb(44, 24, 16) })
		K:plate("PosterHead", iw * 0.32, ih * 0.07, 0.004, dcf * CF(0, ih * 0.17, zA + 0.01), { c = rgb(240, 224, 190) })
		txt("STOUT", 0.5, 0.84, 0.7, 0.13, rgb(240, 224, 190))
		txt("SMOOTH · ROASTY · DARK", 0.5, 0.13, 0.8, 0.06, rgb(200, 180, 150), F.GothamBold)
	elseif kind == "surf" then
		blk(rgb(244, 220, 170), 0, 0, 1, 0.16)
		local cols = { rgb(250, 120, 80), rgb(250, 230, 120), rgb(250, 250, 246) }
		for k = 1, 3 do
			K:ell("PosterBoard", V3(iw * 0.16, ih * 0.62, 0.02), dcf * CF(iw * (k - 2) * 0.24, -ih * 0.02, zA + 0.01) * ANG(0, 0, (k - 2) * 0.12), { c = cols[k], m = M.SmoothPlastic })
			K:plate("PosterStringer", iw * 0.01, ih * 0.55, 0.004, dcf * CF(iw * (k - 2) * 0.24, -ih * 0.02, zA + 0.024) * ANG(0, 0, (k - 2) * 0.12), { c = rgb(60, 60, 60) })
		end
		txt("SURF & BEER", 0.5, 0.86, 0.86, 0.12, rgb(255, 250, 236))
		txt("광안리 해변 · SINCE 2015", 0.5, 0.08, 0.8, 0.06, rgb(30, 80, 90), F.GothamBold)
	elseif kind == "lotte" or kind == "lotte2" then
		blk(rgb(200, 30, 40), 0, 0.82, 1, 0.05)
		blk(rgb(200, 30, 40), 0, 0.12, 1, 0.05)
		wdisc(K, "PosterBall", iw * 0.36, 0.004, dcf * CF(0, -ih * 0.04, 0), zA + 0.004, { c = rgb(246, 244, 236) })
		for _, sd in { -1, 1 } do
			K:plate("PosterStitch", iw * 0.012, ih * 0.16, 0.004, dcf * CF(sd * iw * 0.09, -ih * 0.04, zA + 0.01) * ANG(0, 0, sd * 0.25), { c = rgb(200, 30, 40) })
		end
		if kind == "lotte" then
			txt("최강 롯데", 0.5, 0.9, 0.8, 0.1, rgb(255, 255, 255))
			txt("부산 갈매기 · 사직 직관 중계", 0.5, 0.06, 0.86, 0.06, rgb(255, 255, 255), F.GothamBold)
		else
			txt("GAME DAY", 0.5, 0.9, 0.8, 0.1, rgb(255, 255, 255))
			txt("야구 보면서 생맥 한 잔", 0.5, 0.06, 0.86, 0.06, rgb(255, 255, 255), F.GothamBold)
		end
	elseif kind == "cocktail" or kind == "deco" then
		local gold = rgb(214, 176, 96)
		for k = -3, 3 do
			local a = (dcf * CF(0, -ih * 0.42, zA + 0.008)).Position
			local bb = (dcf * CF(iw * 0.13 * k, ih * 0.3, zA + 0.008)).Position
			K:seg("PosterDeco", a, bb, 0.014, { c = gold, m = M.Metal })
		end
		if kind == "cocktail" then
			local glassCF = dcf * CF(0, ih * 0.02, 0)
			local pts = { { -0.16, 0.12 }, { 0.16, 0.12 }, { 0, -0.06 }, { -0.16, 0.12 } }
			for i = 1, #pts - 1 do
				K:seg("PosterGlass", (glassCF * CF(pts[i][1] * iw * 1.6, pts[i][2] * ih, zA + 0.012)).Position, (glassCF * CF(pts[i + 1][1] * iw * 1.6, pts[i + 1][2] * ih, zA + 0.012)).Position, 0.02, { c = gold, m = M.Metal })
			end
			txt("COCKTAIL HOUR", 0.5, 0.86, 0.86, 0.1, gold, F.Oswald)
			txt("17:00 – 20:00  ·  2잔째 반값", 0.5, 0.1, 0.84, 0.06, rgb(236, 220, 190), F.GothamMedium)
		else
			txt("THE ART\nOF MIXING", 0.5, 0.78, 0.8, 0.2, gold, F.Oswald)
			txt("SHAKEN · STIRRED · SERVED", 0.5, 0.1, 0.84, 0.06, rgb(236, 220, 190), F.GothamMedium)
		end
	elseif kind == "map" then
		local coast = { { 0.05, 0.62 }, { 0.22, 0.55 }, { 0.36, 0.5 }, { 0.5, 0.4 }, { 0.62, 0.42 }, { 0.78, 0.3 }, { 0.95, 0.26 } }
		for i = 1, #coast - 1 do
			local a = dcf * CF(-iw / 2 + iw * coast[i][1], -ih / 2 + ih * coast[i][2], zA + 0.008)
			local bb = dcf * CF(-iw / 2 + iw * coast[i + 1][1], -ih / 2 + ih * coast[i + 1][2], zA + 0.008)
			K:seg("PosterCoast", a.Position, bb.Position, 0.03, { c = rgb(40, 90, 140) })
		end
		blk(rgb(120, 170, 200), 0, 0, 1, 0.24)
		for i, p in { { 0.3, 0.56, "서면" }, { 0.52, 0.47, "광안리" }, { 0.76, 0.38, "해운대" } } do
			wdisc(K, "PosterPin", iw * 0.05, 0.004, dcf * CF(-iw / 2 + iw * p[1], -ih / 2 + ih * p[2], 0), zA + 0.01, { c = if i == 2 then rgb(200, 40, 40) else rgb(60, 60, 60) })
			txt(p[3], p[1], p[2] + 0.06, 0.24, 0.05, rgb(50, 40, 30), F.GothamBold)
		end
		txt("BUSAN CRAFT\nBEER MAP", 0.5, 0.84, 0.86, 0.2, rgb(70, 46, 30))
	elseif kind == "rules" then
		txt("HOUSE RULES", 0.5, 0.88, 0.8, 0.09, rgb(250, 214, 110), F.PermanentMarker)
		txt("1. 건배는 크게!\n2. 과음은 금물\n3. 음주운전 NO\n4. 대리운전은 필수\n5. 다트는 선 뒤에서", 0.5, 0.42, 0.84, 0.66, rgb(236, 234, 222), F.PermanentMarker)
	elseif kind == "monk" then
		local gold = rgb(220, 180, 90)
		K:plate("PosterChalice", iw * 0.34, ih * 0.14, 0.004, dcf * CF(0, ih * 0.06, zA + 0.008), { c = gold })
		K:plate("PosterChalice", iw * 0.05, ih * 0.14, 0.004, dcf * CF(0, -ih * 0.07, zA + 0.008), { c = gold })
		K:plate("PosterChalice", iw * 0.22, ih * 0.03, 0.004, dcf * CF(0, -ih * 0.15, zA + 0.008), { c = gold })
		K:plate("PosterBeer", iw * 0.3, ih * 0.03, 0.004, dcf * CF(0, ih * 0.14, zA + 0.012), { c = rgb(250, 240, 210) })
		txt("ABBEY ALE", 0.5, 0.86, 0.8, 0.1, gold, F.Oswald)
		txt("BREWED IN GWANGALLI\nSINCE 2015", 0.5, 0.14, 0.86, 0.1, rgb(230, 210, 170), F.GothamBold)
	elseif kind == "party" then
		for k = 1, 12 do
			local cx, cy = rnd(k, 1), 0.2 + rnd(k, 2) * 0.55
			wdisc(K, "PosterDot", iw * (0.03 + rnd(k, 3) * 0.05), 0.004, dcf * CF(-iw / 2 + iw * cx, -ih / 2 + ih * cy, 0), zA + 0.004, { c = if k % 3 == 0 then rgb(255, 60, 200) elseif k % 3 == 1 then rgb(60, 220, 255) else rgb(255, 220, 60) })
		end
		txt("THURSDAY\nPARTY NIGHT", 0.5, 0.82, 0.86, 0.22, rgb(255, 240, 255))
		txt("EVERY THU · FRI · SAT  21:00", 0.5, 0.08, 0.86, 0.06, rgb(255, 200, 250), F.GothamBold)
	elseif kind == "sunsetp" then
		blk(rgb(236, 90, 110), 0, 0.3, 1, 0.22)
		blk(rgb(60, 40, 90), 0, 0, 1, 0.3)
		wdisc(K, "PosterSun", iw * 0.42, 0.004, dcf * CF(0, -ih / 2 + ih * 0.32, 0), zA + 0.002, { c = rgb(255, 214, 110) })
		blk(rgb(60, 40, 90), 0, 0, 1, 0.3, 0.004)
		K:seg("PosterPalm", (dcf * CF(iw * 0.3, -ih * 0.3, zA + 0.012)).Position, (dcf * CF(iw * 0.22, ih * 0.15, zA + 0.012)).Position, 0.03, { c = rgb(30, 20, 30) })
		for k = 0, 4 do
			K:ell("PosterFrond", V3(iw * 0.22, ih * 0.03, 0.01), dcf * CF(iw * 0.22, ih * 0.15, zA + 0.014) * ANG(0, 0, k * 0.8 - 1.6) * CF(iw * 0.1, 0, 0), { c = rgb(30, 20, 30) })
		end
		txt("SUNSET\nHAPPY HOUR", 0.5, 0.82, 0.86, 0.22, rgb(255, 250, 236))
		txt("매일 17 – 19시 생맥주 1+1", 0.5, 0.08, 0.86, 0.06, rgb(255, 230, 210), F.GothamBold)
	end
end

-- 1) 벽 마감 (윗벽 페인트 · 벽돌 포인트 벽) ---------------------------------------------------------------
-- 문틀 · 백바 같은 제외 구간만 빼고 넓은 판 몇 장으로 (작은 벽 물건은 판 앞에 그대로 보임)
local function wallRuns(V: any, wn: string, y0: number, y1: number, excl: { { number } }?): { { number } }
	local w = V.walls[wn]
	local cuts = {}
	for _, r in V.parts do
		local isDoor = r.door or r.name == "DoorCasing" or r.name == "DoorLeaf" or r.name == "DoorFrame" or r.name == "ShopWindow"
		if isDoor and r.max.Y > y0 + 0.05 and r.min.Y < y1 - 0.05 then
			local umin, umax, dmin = math.huge, -math.huge, math.huge
			for _, x in { r.min.X, r.max.X } do
				for _, z in { r.min.Z, r.max.Z } do
					local u, d = V:wallCoord(wn, V3(x, 0, z))
					umin = math.min(umin, u)
					umax = math.max(umax, u)
					dmin = math.min(dmin, d)
				end
			end
			if dmin < 0.6 then
				table.insert(cuts, { umin - 0.05, umax + 0.05 })
			end
		end
	end
	for _, e in excl or {} do
		table.insert(cuts, e)
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local out = {}
	local cur = w.a
	for _, c in cuts do
		if c[1] > cur + 0.3 then
			table.insert(out, { cur, math.min(c[1], w.b) })
		end
		cur = math.max(cur, c[2])
	end
	if cur < w.b - 0.3 then
		table.insert(out, { cur, w.b })
	end
	return out
end

local function upperWalls(c: any)
	local K, V, th, S = c.K, c.V, c.th, c.S
	local y0 = (if S.lower then (S.lower.h or 3.0) else 0.45) + 0.05
	local y1 = V.H - 0.03
	if y1 - y0 < 1 then
		return
	end
	-- 문 위아래로 나눔 (문 위 띠도 칠함)
	local breaks = { y0, y1 }
	for _, r in V.parts do
		if (r.name == "DoorCasing" or r.name == "DoorLeaf") and r.max.Y > y0 + 0.3 and r.max.Y < y1 - 0.3 then
			table.insert(breaks, r.max.Y + 0.02)
		end
	end
	table.sort(breaks)
	for _, wn in { "left", "right", "back" } do
		local look = if th.feature and th.feature.wall == wn then th.feature.look else th.paint
		if not look then
			continue
		end
		local excl = if wn == "back" then c.backExcl else nil
		K:free(function()
			for i = 1, #breaks - 1 do
				local ya, yb = breaks[i], breaks[i + 1]
				if yb - ya > 0.2 then
					for _, s in wallRuns(V, wn, ya, yb, excl) do
						K:plate("WallUpper", s[2] - s[1], yb - ya, 0.03, V:wall(wn, (s[1] + s[2]) / 2, (ya + yb) / 2, 0.012), look)
					end
				end
			end
		end)
	end
end

-- 2) 벤치 소파 (맵 Backrest + Seat + Base + Arm + Plinth 를 같은 자리 · 같은 좌판 높이로) -----------------------
local function banquettes(c: any)
	local K, V, th = c.K, c.V, c.th
	c.usedChairs = c.usedChairs or {}
	c.banq = {}
	for _, br in V.byName.Backrest or {} do
		if br.size.Y < 2.2 then
			continue
		end
		local alongZ = br.size.Z >= br.size.X
		local len = if alongZ then br.size.Z else br.size.X
		if len < 3 then
			continue
		end
		local seats = {}
		for _, ch in V.chairs do
			local sc = ch.seat.c
			local along = if alongZ then sc.Z else sc.X
			local lo = if alongZ then br.min.Z else br.min.X
			local hi = if alongZ then br.max.Z else br.max.X
			local perp = if alongZ then math.abs(sc.X - br.c.X) else math.abs(sc.Z - br.c.Z)
			if along > lo - 0.1 and along < hi + 0.1 and perp < 3.5 and ch.top < 2.4 then
				table.insert(seats, ch)
			end
		end
		if #seats == 0 then
			continue
		end
		local sc = seats[1].seat.c
		local face = if alongZ then V3(if sc.X > br.c.X then 1 else -1, 0, 0) else V3(0, 0, if sc.Z > br.c.Z then 1 else -1)
		local thick = if alongZ then br.size.X else br.size.Z
		local fpos = V3(br.c.X, 0, br.c.Z) + face * (thick / 2)
		local bcf = CFrame.lookAt(fpos, fpos - face)
		local top = seats[1].top
		local depth = 0
		for _, ch in seats do
			local lp = bcf:PointToObjectSpace(ch.seat.c)
			local half = (if alongZ then ch.seat.size.X else ch.seat.size.Z) / 2
			depth = math.max(depth, lp.Z + half)
		end
		local extras = {}
		local arms = {}
		for _, nm in { "Base", "Arm", "Plinth", "SeatBase", "SofaBase" } do
			for _, r in V.byName[nm] or {} do
				local lp = bcf:PointToObjectSpace(r.c)
				if math.abs(lp.X) < len / 2 + 0.8 and lp.Z > -0.3 and lp.Z < depth + 0.8 then
					table.insert(extras, r)
					if nm == "Arm" then
						table.insert(arms, r)
					end
				end
			end
		end
		local up = th.seat
		local dk = dim(up, 0.3)
		local frameL = th.dark
		local baseTop = top - 0.42
		K:free(function()
			-- 받침 (안쪽으로 들어간 걸레받이)
			K:box("BanqPlinth", V3(len - 0.3, 0.3, depth - 0.35), bcf * CF(0, 0.15, (depth - 0.35) / 2), L.black)
			-- 몸통 (가죽 스커트) + 앞 모서리 웰트
			K:box("BanqBase", V3(len - 0.06, baseTop - 0.3, depth - 0.04), bcf * CF(0, 0.3 + (baseTop - 0.3) / 2, (depth - 0.04) / 2), dk)
			K:cyl("BanqWelt", len - 0.12, 0.07, bcf * CF(0, baseTop - 0.03, depth - 0.05), dim(up, 0.5))
			-- 좌판 쿠션 (좌석마다, 윗면 = 원래 좌판 높이)
			for _, ch in seats do
				local lp = bcf:PointToObjectSpace(ch.seat.c)
				local sl = if alongZ then ch.seat.size.Z else ch.seat.size.X
				local cz = (depth - 0.08) / 2 + 0.02
				K:slab("BanqCushion", sl - 0.08, depth - 0.1, 0.42, 0.13, bcf * CF(lp.X, top - 0.21, cz), up)
				K:slab("BanqPiping", sl - 0.05, depth - 0.07, 0.035, 0.14, bcf * CF(lp.X, top - 0.07, cz), dim(up, 0.45))
			end
			-- 등받이: 뒤 셸 (원목) + 채널/버튼 터프팅 + 윗 롤 + 캡
			local bmin, bmax = br.min.Y, br.max.Y
			K:box("BanqBackShell", V3(len, bmax - bmin, thick - 0.32), bcf * CF(0, (bmin + bmax) / 2, -(thick - 0.32) / 2 - 0.32), frameL)
			K:box("BanqCap", V3(len, 0.08, thick), bcf * CF(0, bmax - 0.04, -thick / 2), frameL)
			local bh = bmax - top
			if th.seatStyle == "tuft" then
				K:box("BanqBackPad", V3(len - 0.1, bh - 0.32, 0.3), bcf * CF(0, top + 0.04 + (bh - 0.32) / 2, -0.15), up)
				local cols = math.max(2, math.floor(len / 0.85))
				for row = 1, 2 do
					for k = 1, cols do
						local x = -len / 2 + len * (k - 0.5) / cols + (if row == 2 then len / cols / 2 else 0)
						if x < len / 2 - 0.2 then
							K:ball("BanqButton", 0.08, bcf * CF(x, top + 0.04 + (bh - 0.32) * (if row == 1 then 0.36 else 0.72), 0.0), dk)
						end
					end
				end
			else
				local n = math.max(3, math.floor(len / 0.55))
				local cw = len / n
				for k = 1, n do
					K:vcyl("BanqChannel", bh - 0.36, cw * 1.04, bcf * CF(-len / 2 + cw * (k - 0.5), top + 0.04 + (bh - 0.36) / 2, -cw * 0.52), up)
				end
			end
			K:cyl("BanqTopRoll", len - 0.04, 0.34, bcf * CF(0, bmax - 0.08 - 0.17, -0.22), up)
			-- 팔걸이 (맵 Arm 자리 그대로)
			for _, a in arms do
				local lp = bcf:PointToObjectSpace(a.c)
				local aw = if alongZ then a.size.Z else a.size.X
				local ad = if alongZ then a.size.X else a.size.Z
				local ah = a.size.Y
				K:rbox("BanqArm", V3(ad, ah - 0.04, aw), math.min(0.16, aw / 2 - 0.02), bcf * CF(lp.X, a.c.Y - 0.02, lp.Z) * ANG(0, PI / 2, 0), up)
				K:box("BanqArmCap", V3(aw + 0.02, 0.06, ad + 0.02), bcf * CF(lp.X, a.max.Y - 0.03, lp.Z), frameL)
			end
		end)
		-- 숨김 + 예약
		hideRec(K, br)
		local mn, mx = br.min, br.max
		for _, ch in seats do
			c.usedChairs[ch] = true
			for _, r in ch.parts do
				hideRec(K, r)
				mn, mx = mn:Min(r.min), mx:Max(r.max)
			end
		end
		for _, r in extras do
			hideRec(K, r)
			mn, mx = mn:Min(r.min), mx:Max(r.max)
		end
		K:reserve(V3(mn.X - 0.2, 0, mn.Z - 0.2), V3(mx.X + 0.2, mx.Y, mx.Z + 0.2), "banquette")
		local wn = if alongZ then (if face.X < 0 then "right" else "left") else (if face.Z > 0 then "back" else "front")
		table.insert(c.banq, { wall = wn, center = (mn + mx) / 2, len = len, top = br.max.Y, alongZ = alongZ, min = mn, max = mx })
	end
end

-- 3) 나머지 의자 (Common.chairs 와 같은 방식, 테마 스타일)
local function chairsOver(c: any)
	local K, V, th = c.K, c.V, c.th
	local used = c.usedChairs or {}
	local cs = th.chair or { style = "padded", frame = L.blackMetal, seat = th.seat }
	local n = #V.chairs
	local detail = K.detail
	if n > 4 then
		detail = "mid"
	end
	if n * 30 > K.maxParts * 0.4 then
		detail = if n * 22 > K.maxParts * 0.4 then "low" else "mid"
	end
	for _, ch in V.chairs do
		if used[ch] then
			continue
		end
		local s = ch.seat
		if s.part:IsA("Seat") and s.part.Transparency >= 0.99 then
			continue
		end
		local w = math.max(1.1, math.min(2.2, math.min(s.size.X, s.size.Z) + 0.05))
		local backH = 1.8
		if ch.back then
			backH = math.clamp(ch.back.max.Y - ch.top, 1.0, 3.2)
		end
		local o = table.clone(cs)
		o.seatTop = ch.top
		o.w = w
		o.d = w
		o.backH = o.backH or backH
		o.detail = if detail == "high" then o.detail else detail
		local p = V3(s.c.X, 0, s.c.Z)
		local f: Vector3 = ch.face
		K:free(function()
			Props.chair(K, CFrame.lookAt(p, p - f), o)
		end)
		for _, r in ch.parts do
			hideRec(K, r)
		end
		K:reserve(V3(s.min.X - 0.3, 0, s.min.Z - 0.3), V3(s.max.X + 0.3, ch.top + backH, s.max.Z + 0.3), "chair")
	end
end

-- 4) 백바 (맵 MirrorBack · BarShelf · ShelfGlow · Bottle · BackBarCabinet 자리) ---------------------------------
local function backCabinet(K: any, cab: any, th: any, c: any)
	local mn, mx = cab.min, cab.max
	local w, h, d = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
	local base = CF((mn.X + mx.X) / 2, 0, (mn.Z + mx.Z) / 2)
	local detail = K.detail
	K:free(function()
		K:box("BackCabTop", V3(w, 0.12, d), base * CF(0, h - 0.06, 0), th.cabTop)
		K:box("BackCabKick", V3(w - 0.06, 0.34, d - 0.12), base * CF(0, 0.17, -0.08), L.black)
		local n = math.max(2, math.floor(w / 1.9 + 0.5))
		local dw = w / n
		local bh = h - 0.12 - 0.34
		local coolers: { [number]: boolean } = {}
		if th.key ~= "fuzzy" and n >= 3 then
			local mid = math.floor((n + 1) / 2)
			coolers[mid] = true
			if n >= 5 then
				coolers[mid + 1] = true
			end
		end
		for i = 1, n do
			local x = -w / 2 + dw * (i - 0.5)
			local yc = 0.34 + bh / 2
			local fz = d / 2
			if coolers[i] then
				-- 유리문 맥주 쿨러: 뒤 몸통 + 밝은 안쪽 + 선반 2 + 병 · 캔 + 검은 문틀 + 유리
				K:box("BackCoolerBody", V3(dw, bh, d - 0.62), base * CF(x, yc, -0.31), th.dark)
				K:box("BackCoolerInner", V3(dw - 0.2, bh - 0.2, 0.04), base * CF(x, yc, fz - 0.6), L.of(232, 238, 242))
				local lamp = K:box("BackCoolerLED", V3(dw - 0.3, 0.04, 0.05), base * CF(x, 0.34 + bh - 0.16, fz - 0.2), L.lampCool)
				for k = 0, 1 do
					local sy = 0.34 + 0.12 + k * (bh - 0.25) / 2
					K:box("BackCoolerShelf", V3(dw - 0.2, 0.03, 0.5), base * CF(x, sy, fz - 0.33), L.of(200, 204, 208, M.Metal))
					local m = math.max(2, math.floor((dw - 0.3) / 0.3))
					for j = 1, m do
						local bx = x - (dw - 0.3) / 2 + (dw - 0.3) * (j - 0.5) / m
						local pc = base * CF(bx, sy + 0.015, fz - 0.33)
						if (j + k) % 2 == 0 then
							beerBottle(K, pc, if j % 3 == 0 then rgb(40, 96, 56) else rgb(110, 60, 24), LABELS[(j + k) % #LABELS + 1], detail)
						else
							beerCan(K, pc, (th.taps[(j % #th.taps) + 1] :: any)[7] or rgb(200, 60, 40), rgb(250, 250, 246), detail)
						end
					end
				end
				K:plate("BackCoolerFrame", dw - 0.06, bh - 0.04, 0.06, CF(base * V3(x, yc, fz)), L.of(26, 26, 28, M.Metal))
				K:box("BackCoolerGlass", V3(dw - 0.3, bh - 0.3, 0.03), base * CF(x, yc, fz + 0.075), { c = rgb(210, 230, 236), m = M.Glass, t = 0.72, r = 0.15 })
				K:box("BackCoolerHandle", V3(0.06, bh * 0.5, 0.08), base * CF(x + dw / 2 - 0.2, yc, fz + 0.12), L.chrome)
				if c then
					table.insert(c.coolLamps, lamp)
				end
			else
				K:box("BackCabBay", V3(dw, bh, d - 0.02), base * CF(x, yc, -0.01), th.dark)
				local dc = CF(base * V3(x, yc, fz))
				K:plate("BackCabDoor", dw - 0.08, bh - 0.08, 0.04, dc, th.mid)
				if detail ~= "low" then
					K:plate("BackCabPanel", dw - 0.46, bh - 0.5, 0.03, dc * CF(0, 0, 0.04), dim(th.mid, 0.18))
				end
				K:ball("BackCabKnob", 0.12, dc * CF(if i % 2 == 0 then -dw / 2 + 0.24 else dw / 2 - 0.24, bh * 0.28, 0.1), th.trim)
			end
		end
	end)
end

local function backBar(c: any)
	local K, V, th = c.K, c.V, c.th
	local mir = V:first("MirrorBack")
	local shelves = {}
	for _, r in V.byName.BarShelf or {} do
		table.insert(shelves, r)
	end
	local cab = V:first("BackBarCabinet")
	c.coolLamps = {}
	if not mir and #shelves == 0 then
		if cab then
			hideRec(K, cab)
			backCabinet(K, cab, th, c)
		end
		return
	end
	local ref = mir or shelves[1]
	if ref.min.Z - V.z0 > 0.7 then
		return -- 뒷벽 백바만
	end
	local x0, x1 = ref.min.X, ref.max.X
	for _, r in shelves do
		x0 = math.min(x0, r.min.X)
		x1 = math.max(x1, r.max.X)
	end
	table.sort(shelves, function(a, b)
		return a.max.Y < b.max.Y
	end)
	local yb = if cab then cab.max.Y else (if shelves[1] then shelves[1].min.Y - 0.4 else 3.0)
	local yTop = if mir then mir.max.Y else shelves[#shelves].max.Y + 1.6
	yTop = math.min(yTop, V.H - 0.6)
	local zw = V.z0
	local W = x1 - x0
	local cx = (x0 + x1) / 2
	local seed = c.seed
	local detail = K.detail
	-- 맵 장식 숨김
	for _, r in V.byName.Bottle or {} do
		if r.c.X >= x0 - 0.6 and r.c.X <= x1 + 0.6 and r.c.Z < zw + 1.8 then
			hideRec(K, r)
		end
	end
	for _, nm in { "MirrorBack", "BarShelf", "ShelfGlow" } do
		for _, r in V.byName[nm] or {} do
			hideRec(K, r)
		end
	end
	local backCx = (V.x0 + V.x1) / 2
	c.backExcl = { { x0 - backCx - 0.05, x1 - backCx + 0.05 } }
	claim(K, "back", x0 - backCx - 0.3, x1 - backCx + 0.3, 0, V.H)
	if cab then
		hideRec(K, cab)
		backCabinet(K, cab, th, c)
		claim(K, "back", cab.min.X - backCx - 0.3, cab.max.X - backCx + 0.3, 0, cab.max.Y + 0.4)
	end
	local nb = math.max(1, math.floor(W / 3.0 + 0.5))
	local bw = W / nb
	local crownH = math.min(0.62, V.H - yTop - 0.04)
	K:free(function()
		-- 스모크 거울
		K:box("BackBarMirror", V3(W - 0.06, yTop - yb, 0.04), CF(cx, (yb + yTop) / 2, zw + 0.03), th.mirror)
		-- 기둥 (원목 + 황동 띠)
		for i = 0, nb do
			local x = math.clamp(x0 + bw * i, x0 + 0.16, x1 - 0.16)
			K:box("BackBarPost", V3(0.32, yTop - yb, 0.96), CF(x, (yb + yTop) / 2, zw + 0.48), th.dark)
			K:box("BackBarPostTrim", V3(0.06, yTop - yb - 0.3, 0.02), CF(x, (yb + yTop) / 2, zw + 0.97), th.trim)
		end
		-- 크라운 + 상호 (뒤에서 빛나는 글자)
		if crownH > 0.3 then
			K:box("BackBarCrown", V3(W + 0.36, crownH, 1.08), CF(cx, yTop + crownH / 2, zw + 0.54), th.dark)
			K:box("BackBarCrownTrim", V3(W + 0.4, 0.05, 0.04), CF(cx, yTop + 0.03, zw + 1.1), th.trim)
			K:text("BackBarCrownSign", math.min(W * 0.8, 12), crownH * 0.62, CF(cx, yTop + crownH / 2 + 0.02, zw + 1.08), th.crown or th.brand, { fg = rgb(255, 222, 160), glow = 1.4, font = th.font or F.Oswald, d = 0.02 })
		end
		local lamp = K:box("BackBarLamp", V3(W - 0.5, 0.04, 0.08), CF(cx, yTop - 0.03, zw + 0.86), L.neon(th.shelfLED))
		K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 10, Brightness = 1.4, Angle = 120, Color = th.shelfLED })
		-- 선반 + 앞 레일 + LED + 술병
		local cap = { L.goldMetal, L.black, L.of(160, 30, 30), L.chrome, wood(120, 80, 50) }
		local mix = th.bottleMix or { "square", "round", "wine" }
		local idx = 0
		for si, r in shelves do
			local y = r.max.Y
			local clear = (if shelves[si + 1] then shelves[si + 1].min.Y else yTop) - y - 0.12
			for bi = 1, nb do
				local bx0 = x0 + bw * (bi - 1) + 0.2
				local bx1 = x0 + bw * bi - 0.2
				local bcx = (bx0 + bx1) / 2
				local sw = bx1 - bx0
				if th.tapWall and si == 1 and clear > 1.45 then
					-- 탭 월 (맨 아래 칸): 스테인리스 판 + 파우셋 줄 + 핸들 + 물받이 (20 TAPS 탭하우스)
					local steel = L.of(168, 172, 178, M.Metal, { r = 0.18 })
					local yF = y + math.min(0.85, clear - 0.95)
					K:box("TapWallPanel", V3(sw + 0.04, clear + 0.08, 0.06), CF(bcx, y + clear / 2, zw + 0.3), steel)
					K:box("TapWallManifold", V3(sw - 0.1, 0.16, 0.12), CF(bcx, yF, zw + 0.39), L.chrome)
					K:box("TapWallTrough", V3(sw + 0.04, 0.12, 0.62), CF(bcx, y - 0.0, zw + 0.64), steel)
					K:box("TapWallGrate", V3(sw - 0.08, 0.014, 0.5), CF(bcx, y + 0.066, zw + 0.64), L.of(40, 40, 42, M.Metal))
					if K.detail ~= "low" then
						for k = 1, 4 do
							K:box("TapWallGrateBar", V3(sw - 0.1, 0.016, 0.03), CF(bcx, y + 0.07, zw + 0.44 + k * 0.08), L.chrome)
						end
					end
					K:box("BackBarLED", V3(sw - 0.1, 0.03, 0.04), CF(bcx, y - 0.09, zw + 0.92), L.neon(th.shelfLED))
					local nt = math.max(3, math.floor(sw / 0.37))
					for j = 1, nt do
						idx += 1
						local x = bx0 + sw * (j - 0.5) / nt
						local tap = th.taps[(idx + seed) % #th.taps + 1]
						local hc = tap[7] or tap[5]
						K:cyl("TapWallShank", 0.4, 0.09, CF(x, yF, zw + 0.62) * ANG(0, PI / 2, 0), L.chrome)
						K:cyl("TapWallFaucet", 0.22, 0.14, CF(x, yF, zw + 0.86) * ANG(0, PI / 2, 0), L.chrome)
						K:vcyl("TapWallSpout", 0.2, 0.07, CF(x, yF - 0.15, zw + 0.92), L.chrome)
						K:vcyl("TapWallFerrule", 0.1, 0.1, CF(x, yF + 0.12, zw + 0.88), L.chrome)
						local hh = math.min(0.62, clear - (yF - y) - 0.36)
						K:box("TapWallHandle", V3(0.18, hh, 0.11), CF(x, yF + 0.17 + hh / 2, zw + 0.88), { c = hc, m = M.SmoothPlastic })
						K:box("TapWallHandleCap", V3(0.2, 0.03, 0.13), CF(x, yF + 0.17 + hh + 0.015, zw + 0.88), L.black)
						if detail == "high" then
							K:text("TapWallHandleLabel", 0.15, hh * 0.6, CF(x, yF + 0.17 + hh * 0.52, zw + 0.94), tap[6] or "ALE", { fg = if hc.R + hc.G + hc.B > 1.8 then rgb(30, 30, 30) else rgb(250, 250, 246), font = F.GothamBlack, d = 0.004 })
						end
					end
					-- 칸 번호 띠 (01-07 ...)
					local first = (bi - 1) * nt + 1
					K:text("TapWallNumbers", sw - 0.1, 0.14, CF(bcx, yF - 0.34, zw + 0.335), string.format("TAP %02d – %02d", first, first + nt - 1), { fg = rgb(40, 40, 44), font = F.GothamBold, d = 0.004 })
					continue
				end
				K:box("BackBarShelf", V3(sw + 0.04, 0.07, 0.86), CF(bcx, y - 0.035, zw + 0.06 + 0.43), { c = rgb(200, 226, 230), m = M.Glass, t = 0.35, r = 0.1 })
				K:cyl("BackBarRail", sw + 0.04, 0.05, CF(bcx, y + 0.24, zw + 0.86), th.trim)
				K:box("BackBarLED", V3(sw - 0.1, 0.03, 0.04), CF(bcx, y - 0.09, zw + 0.82), L.neon(th.shelfLED))
				local m = math.max(1, math.floor(sw / (if K.detail == "high" then 0.56 else 0.7)))
				for j = 1, m do
					idx += 1
					local bx = bx0 + sw * (j - 0.5) / m + (rnd(seed, idx) - 0.5) * 0.06
					local h = math.clamp(0.9 + rnd(seed, idx + 50) * 0.45, 0.6, clear)
					local kind = mix[(idx + seed) % #mix + 1]
					local gc = GLASS[(math.floor(rnd(seed, idx + 99) * 97)) % #GLASS + 1]
					bottle(K, CF(bx, y, zw + 0.42 + (j % 2) * 0.12), h, kind, gc, LABELS[(idx * 7 + seed) % #LABELS + 1], cap[(idx + si) % #cap + 1], detail)
				end
			end
		end
		-- 맨 아래 단 (하부장 위 · 첫 선반 아래) 위로 비추는 LED
		if shelves[1] and shelves[1].min.Y - yb > 0.2 then
			K:box("BackBarUplight", V3(W - 0.5, 0.03, 0.05), CF(cx, yb + 0.03, zw + 0.2), L.neon(th.shelfLED))
		end
	end)
	c.backBar = { x0 = x0, x1 = x1, yTop = yTop }
end

-- 4a) 백바 하부장 윗면 앞쪽 (선반 앞 0.6 띠): 칵테일 바는 바텐더 도구 (비터스 · 셰이커 · 지거 · 시트러스),
--     맥주 펍은 얼음 버킷 병맥주. 깊이는 하부장 안 (직원 통로에 안 나옴)
local function backTop(c: any)
	local K, V, th = c.K, c.V, c.th
	local cab = V:first("BackBarCabinet")
	if not cab or not c.backBar or not budget(K, 60) then
		return
	end
	local y = cab.max.Y
	local zc = cab.max.Z - 0.4
	local detail = K.detail
	local cocktail = th.key == "fuzzy" or th.key == "party"
	local function ok(x: number, w: number, h: number): boolean
		return clearAt(K, CF(x, y + h / 2 + 0.01, zc), V3(w, h, 0.5))
	end
	if cocktail then
		local x0 = cab.min.X + 1.5
		if ok(x0 + 0.7, 1.7, 0.5) then
			K:box("BarToolMat", V3(1.6, 0.03, 0.46), CF(x0 + 0.7, y + 0.015, zc), L.rubber)
			-- 비터스 4 (작은 갈색병 + 큰 흰 라벨 + 대셔 뚜껑)
			for k = 0, 3 do
				local bp = CF(x0 + k * 0.17, y + 0.03, zc - 0.1)
				K:vcyl("Bitters", 0.26, 0.12, bp * CF(0, 0.13, 0), { c = rgb(84, 46, 20), m = M.Glass, t = 0.1 })
				K:vcyl("BittersLabel", 0.16, 0.128, bp * CF(0, 0.13, 0), { c = if k % 2 == 0 then rgb(240, 236, 220) else rgb(220, 196, 120) })
				K:vcyl("BittersDasher", 0.08, 0.06, bp * CF(0, 0.3, 0), L.chrome)
			end
			-- 셰이커 (보스턴 틴 2: 하나는 엎어 둠) · 지거 2 · 바 스푼
			K:vcyl("ShakerTin", 0.4, 0.22, CF(x0 + 0.8, y + 0.23, zc - 0.06), L.chrome)
			K:vcyl("ShakerTinSmall", 0.3, 0.18, CF(x0 + 1.06, y + 0.18, zc - 0.04), L.chrome)
			for k = 0, 1 do
				local jp = CF(x0 + 1.3 + k * 0.16, y + 0.03, zc + 0.08)
				K:vcyl("JiggerBase", 0.1, 0.1, jp * CF(0, 0.05, 0), L.goldMetal)
				K:vcyl("JiggerCup", 0.1, 0.13, jp * CF(0, 0.15, 0), L.goldMetal)
			end
			K:seg("BarSpoon", V3(x0 + 0.3, y + 0.04, zc + 0.12), V3(x0 + 1.05, y + 0.04, zc + 0.16), 0.025, L.chrome)
			-- 시트러스 트레이 (레몬 · 라임 반쪽)
			K:box("CitrusTray", V3(0.62, 0.05, 0.3), CF(x0 + 1.75, y + 0.025, zc - 0.02), L.of(240, 240, 238))
			if detail ~= "low" then
				for k = 0, 5 do
					K:ell("Citrus", V3(0.16, 0.1, 0.16), CF(x0 + 1.52 + (k % 3) * 0.17, y + 0.09, zc - 0.09 + (k // 3) * 0.14), { c = if k < 3 then rgb(246, 214, 60) else rgb(120, 180, 60), m = M.SmoothPlastic })
				end
			end
		end
	end
	-- 얼음 버킷 병맥주 (스테인리스 버킷 + 얼음 + 병 목 3)
	local bx = cab.max.X - 1.4
	if ok(bx, 0.6, 0.6) then
		local bp = CF(bx, y, zc)
		K:vcyl("IceBucket", 0.42, 0.5, bp * CF(0, 0.21, 0), L.of(186, 190, 196, M.Metal, { r = 0.2 }))
		K:vcyl("IceBucketRim", 0.05, 0.54, bp * CF(0, 0.41, 0), L.chrome)
		K:ell("IceBucketIce", V3(0.44, 0.12, 0.44), bp * CF(0, 0.4, 0), { c = rgb(228, 240, 246), m = M.Ice })
		local gcs = if cocktail then { rgb(40, 96, 56), rgb(226, 234, 236), rgb(40, 96, 56) } else { rgb(110, 60, 24), rgb(40, 96, 56), rgb(110, 60, 24) }
		for k = 1, 3 do
			local a = k * 2.1
			local np = bp * CF(math.cos(a) * 0.11, 0.48, math.sin(a) * 0.11) * ANG(math.sin(a) * 0.15, 0, math.cos(a) * 0.15)
			K:vcyl("IceBucketNeck", 0.26, 0.09, np, { c = gcs[k], m = M.Glass, t = 0.1 })
			K:vcyl("IceBucketCap", 0.03, 0.1, np * CF(0, 0.14, 0), L.goldMetal)
		end
		if detail ~= "low" then
			for _, sx in { -1, 1 } do
				K:ring("IceBucketHandle", bp * CF(sx * 0.27, 0.3, 0) * ANG(0, PI / 2, 0), 0.06, 0.03, 3, L.chrome, -PI / 2, PI / 2)
			end
		end
	end
end

-- 4b) 카페형 매장 (WallShelf + Jar): 병 판매 선반으로
local function shelfBar(c: any)
	local K, V, th = c.K, c.V, c.th
	if c.backBar or V:has("TapPost") > 0 then
		return
	end
	local sh = V:first("WallShelf")
	if not sh then
		return
	end
	for _, r in V.byName.Jar or {} do
		if r.min.Y >= sh.max.Y - 0.2 and r.min.Y < sh.max.Y + 1.5 then
			hideRec(K, r)
		end
	end
	local y = sh.max.Y
	local zf = (sh.min.Z + sh.max.Z) / 2
	local cap = { L.goldMetal, L.black, L.chrome }
	local mix = th.bottleMix or { "square", "round" }
	local n = math.min(26, math.floor((sh.size.X - 0.4) / 0.62))
	for i = 1, n do
		local x = sh.min.X + 0.2 + (sh.size.X - 0.4) * (i - 0.5) / n
		local h = 0.85 + rnd(c.seed, i) * 0.35
		if clearAt(K, CF(x, y + h / 2, zf), V3(0.45, h, 0.45)) then
			bottle(K, CF(x, y, zf), h, mix[(i + c.seed) % #mix + 1], GLASS[(i * 5 + c.seed) % #GLASS + 1], LABELS[i % #LABELS + 1], cap[i % #cap + 1], K.detail)
		end
	end
	K:free(function()
		Props.ledStrip(K, V3(sh.min.X + 0.2, sh.min.Y - 0.03, sh.max.Z - 0.1), V3(sh.max.X - 0.2, sh.min.Y - 0.03, sh.max.Z - 0.1), th.shelfLED)
	end)
end

-- 5) 탭 타워 (맵 TapPost · TapBar · TapHandle · DripTray 와 같은 자리 · 같은 윗면) --------------------------------
local function tapTower(c: any)
	local K, V, th = c.K, c.V, c.th
	local bar = V:first("TapBar")
	local post = V:first("TapPost")
	if not bar or not post then
		return
	end
	local tray = nil
	for _, r in V.byName.DripTray or {} do
		if (r.c - bar.c).Magnitude < 2.5 then
			tray = r
		end
	end
	local handles = {}
	for _, r in V.byName.TapHandle or {} do
		if (r.c - bar.c).Magnitude < 3 then
			table.insert(handles, r)
		end
	end
	local alongX = bar.size.X >= bar.size.Z
	local perp = if alongX then V3(0, 0, 1) else V3(1, 0, 0)
	local zA = perp
	if tray then
		zA = if (tray.c - bar.c):Dot(perp) >= 0 then perp else -perp
	end
	local xA = Vector3.yAxis:Cross(zA)
	local y0 = post.min.Y
	local tc = CFrame.fromMatrix(V3(bar.c.X, y0, bar.c.Z), xA, Vector3.yAxis, zA)
	local len = if alongX then bar.size.X else bar.size.Z
	local fy = bar.c.Y - y0
	local pp = tc:PointToObjectSpace(post.c)
	hideRec(K, bar)
	hideRec(K, post)
	for _, h in handles do
		hideRec(K, h)
	end
	if tray then
		hideRec(K, tray)
	end
	local chrome = L.chrome
	local labels = {}
	K:free(function()
		K:disc("TapFlange", 0.58, 0.05, tc * CF(pp.X, 0.025, pp.Z), chrome)
		K:vcyl("TapColumn", fy - 0.06, 0.27, tc * CF(pp.X, (fy - 0.06) / 2 + 0.04, pp.Z), chrome)
		K:ball("TapElbow", 0.31, tc * CF(pp.X, fy, 0), chrome)
		K:cyl("TapCrossbar", len - 0.3, 0.27, tc * CF(0, fy, 0), chrome)
		K:cyl("TapFrost", len - 0.6, 0.3, tc * CF(0, fy, 0), { c = rgb(238, 244, 248), m = M.Glass, t = 0.5, r = 0.05 })
		for _, sd in { -1, 1 } do
			K:ball("TapEnd", 0.29, tc * CF(sd * (len / 2 - 0.15), fy, 0), chrome)
		end
		-- 탭 브랜드 띠 (크로스바 앞 중앙)
		local _, lab = K:text("TapBadge", math.min(1.2, len * 0.5), 0.2, tc * CF(0, fy + 0.02, 0.16), th.brand, { fg = rgb(30, 30, 30), bg = rgb(240, 232, 214), d = 0.01, font = F.GothamBlack })
		local _ = lab
		for i, h in handles do
			local hp = tc:PointToObjectSpace(h.c)
			local tap = th.taps[(i - 1) % #th.taps + 1]
			local hc = tap[7] or tap[5]
			-- 파우셋 (앞으로 나온 몸통 + 아래 주둥이)
			K:cyl("TapShank", 0.22, 0.09, tc * CF(hp.X, fy - 0.02, 0.16) * ANG(0, PI / 2, 0), chrome)
			K:cyl("TapFaucet", 0.26, 0.15, tc * CF(hp.X, fy - 0.02, 0.36) * ANG(0, PI / 2, 0), chrome)
			K:vcyl("TapSpout", 0.2, 0.07, tc * CF(hp.X, fy - 0.17, 0.44), chrome)
			-- 핸들 (맵 핸들과 같은 높이 · 자리)
			local hb, ht = h.min.Y - y0, h.max.Y - y0
			local hz = hp.Z
			K:vcyl("TapFerrule", 0.12, 0.12, tc * CF(hp.X, hb + 0.06, hz), chrome)
			K:vcyl("TapShaft", 0.2, 0.13, tc * CF(hp.X, hb + 0.22, hz), L.black)
			local bodyH = ht - hb - 0.34
			K:box("TapHandleBody", V3(0.2, bodyH, 0.12), tc * CF(hp.X, hb + 0.32 + bodyH / 2, hz), { c = hc, m = M.SmoothPlastic })
			K:box("TapHandleCap", V3(0.22, 0.03, 0.14), tc * CF(hp.X, ht - 0.015, hz), L.black)
			local _, tl = K:text("TapHandleLabel", 0.17, bodyH * 0.62, tc * CF(hp.X, hb + 0.32 + bodyH * 0.55, hz + 0.06), tap[6] or "ALE", { fg = if hc.R + hc.G + hc.B > 1.8 then rgb(30, 30, 30) else rgb(250, 250, 246), font = F.GothamBlack, d = 0.005 })
			table.insert(labels, tl)
		end
		if tray then
			local tp = tc:PointToObjectSpace(tray.c)
			local tw = if alongX then tray.size.X else tray.size.Z
			local td = if alongX then tray.size.Z else tray.size.X
			local tH = tray.size.Y
			K:box("TapTray", V3(tw, tH, td), tc * CF(tp.X, tray.c.Y - y0, tp.Z), L.steel)
			K:box("TapTrayWell", V3(tw - 0.12, 0.012, td - 0.12), tc * CF(tp.X, tray.max.Y - y0 - 0.008, tp.Z), L.of(40, 40, 42, M.Metal))
			local nbar = math.max(3, math.floor(td / 0.12))
			for k = 1, nbar do
				K:box("TapTrayGrate", V3(tw - 0.14, 0.012, 0.035), tc * CF(tp.X, tray.max.Y - y0 - 0.004, tp.Z - td / 2 + 0.06 + (td - 0.12) * (k - 0.5) / nbar), L.chrome)
			end
		end
	end)
	c.tap = { cf = tc, y = y0, len = len }
end

-- 6) 발판 레일 (FootRail 자리) ------------------------------------------------------------------------------
local function footRail(c: any)
	local K, V, th = c.K, c.V, c.th
	for _, r in V.byName.FootRail or {} do
		local alongX = r.size.X >= r.size.Z
		local len = if alongX then r.size.X else r.size.Z
		-- 레일이 붙은 카운터 앞면
		local g = nil
		for _, cg in V.counters do
			if r.c.X > cg.min.X - 1 and r.c.X < cg.max.X + 1 and r.c.Z > cg.min.Z - 2.5 and r.c.Z < cg.max.Z + 2.5 then
				g = cg
			end
		end
		local face: number? = nil
		local dir = 1
		if g then
			local body = g.body or g
			if alongX then
				if r.c.Z > body.max.Z then
					face, dir = body.max.Z, -1
				else
					face, dir = body.min.Z, 1
				end
			else
				if r.c.X > body.max.X then
					face, dir = body.max.X, -1
				else
					face, dir = body.min.X, 1
				end
			end
		end
		hideRec(K, r)
		K:free(function()
			local rot = if alongX then CFrame.new() else ANG(0, PI / 2, 0)
			local cc = CF(r.c) * rot
			K:cyl("FootRail", len, 0.17, cc, th.trim)
			for _, sd in { -1, 1 } do
				K:ball("FootRailEnd", 0.2, cc * CF(sd * len / 2, 0, 0), th.trim)
			end
			if face then
				local n = math.max(2, math.floor(len / 2.6) + 1)
				for i = 0, n - 1 do
					local u = -len / 2 + 0.35 + (len - 0.7) * i / (n - 1)
					local p = cc * V3(u, 0, 0)
					local q = if alongX then V3(p.X, p.Y, (face :: number) - dir * 0.04) else V3((face :: number) - dir * 0.04, p.Y, p.Z)
					K:seg("FootRailBracket", p, q, 0.07, th.trim)
					local fcf = if alongX then CF(q) else CF(q) * ANG(0, PI / 2, 0)
					K:box("FootRailFlange", V3(0.22, 0.22, 0.04), fcf, th.trim)
				end
			end
		end)
	end
end

-- 7) 스포츠 TV (맵 TV 자리) + 채널 상호작용 ---------------------------------------------------------------
local function tvSet(c: any)
	local K, V, th = c.K, c.V, c.th
	local tv = V:first("TV")
	local wn: string? = nil
	local u, w, h, yc = 0, 4.4, 2.48, 6.9
	if tv then
		if tv.min.Z - V.z0 < 0.6 then
			wn = "back"
		elseif V.x1 - tv.max.X < 0.6 then
			wn = "right"
		elseif tv.min.X - V.x0 < 0.6 then
			wn = "left"
		end
	end
	if tv and wn then
		u = (V:wallCoord(wn, tv.c))
		w = if wn == "back" then tv.size.X else tv.size.Z
		h = tv.size.Y
		yc = tv.c.Y
		hideRec(K, tv)
		for _, r in V.byName.TVScreen or {} do
			hideRec(K, r)
		end
		claim(K, wn, u - w / 2 - 0.3, u + w / 2 + 0.3, tv.min.Y - 1.0, tv.max.Y + 0.2)
	else
		-- 맵에 TV 가 없는 펍: 손님 쪽 벽에 새로 (사운드바 프롬프트가 설 자리)
		if V.H < 8.4 then
			return
		end
		local function okTV(wn2: string, uu: number, _w: number): boolean
			return promptOK(K, (V:wall(wn2, uu, 5.25, 0.3)).Position) and reachable(K, wn2, uu)
		end
		local w2, u2 = findWall(K, { "back", "right", "left" }, 4.8, 4.8, 5.0, math.min(V.H - 0.4, 8.6), V3(0, 0, V.z0), 0.8, okTV)
		if not w2 or not u2 then
			return
		end
		wn, u = w2, u2
		yc = math.min(V.H - 0.6, 8.6) - h / 2 - 0.1
	end
	local dcf = V:wall(wn :: string, u, yc, 0)
	local sw, sh = w - 0.14, h - 0.14
	local z = 0.24
	-- 맵 TV 와 같은 자리 덮어씌우기 (free)
	K:plate("TVMount", w * 0.3, h * 0.3, 0.1, dcf, L.with(L.blackMetal, { free = true }))
	K:plate("TVBody", w, h, 0.14, dcf * CF(0, 0, 0.1), L.of(18, 18, 20, nil, { free = true }))
	local scr, scrLab = K:text("TVScreen", sw, sh, dcf * CF(0, 0, z), "", { bg = rgb(36, 118, 54), glow = 1.0, d = 0.01, free = true })
	local dirt = K:text("TVField", sh * 0.42, sh * 0.42, dcf * CF(0, -sh * 0.2, z + 0.01) * ANG(0, 0, PI / 4), "", { bg = rgb(170, 110, 64), glow = 1.0, d = 0.005, free = true })
	-- 내야 (흙 다이아몬드 안 잔디 + 베이스 3 + 마운드): 야구 중계 화면처럼
	local field = {}
	do
		local fc = dcf * CF(0, -sh * 0.2, z + 0.02)
		local g = K:text("TVInfield", sh * 0.27, sh * 0.27, fc * ANG(0, 0, PI / 4), "", { bg = rgb(40, 128, 58), glow = 1.0, d = 0.004, free = true })
		table.insert(field, g)
		local bs = sh * 0.035
		for _, bp in { { -0.255, 0 }, { 0.255, 0 }, { 0, 0.255 } } do
			local b0 = K:text("TVBase", bs, bs, dcf * CF(bp[1] * sh, -sh * 0.2 + bp[2] * sh, z + 0.028) * ANG(0, 0, PI / 4), "", { bg = rgb(246, 246, 240), glow = 1.1, d = 0.003, free = true })
			table.insert(field, b0)
		end
		local mound = K:text("TVMound", sh * 0.06, sh * 0.06, fc * CF(0, 0, 0.008), "", { bg = rgb(176, 116, 70), glow = 1.0, d = 0.003, free = true })
		table.insert(field, mound)
	end
	local stripes = {}
	for k = 1, 3 do
		local p = K:text("TVStripe", sw / 7, sh, dcf * CF(-sw / 2 + sw * (2 * k - 0.5) / 7, 0, z + 0.008), "", { bg = rgb(44, 136, 60), glow = 1.0, d = 0.004, free = true })
		table.insert(stripes, p)
	end
	local _, bug = K:text("TVBug", sw * 0.4, sh * 0.17, dcf * CF(-sw * 0.27, sh * 0.37, z + 0.014), "", { fg = rgb(255, 255, 255), bg = rgb(16, 28, 70), glow = 1.1, d = 0.005, font = F.GothamBold, free = true })
	local live, liveLab = K:text("TVLive", sw * 0.1, sh * 0.08, dcf * CF(sw * 0.4, sh * 0.41, z + 0.014), "● LIVE", { fg = rgb(255, 255, 255), bg = rgb(210, 30, 40), glow = 1.2, d = 0.005, font = F.GothamBlack, free = true })
	local _, tick = K:text("TVTicker", sw - 0.1, sh * 0.09, dcf * CF(0, -sh / 2 + sh * 0.06, z + 0.014), "", { fg = rgb(255, 230, 90), bg = rgb(10, 10, 14), glow = 1.1, d = 0.005, font = F.GothamMedium, free = true })
	local _, logo = K:text("TVLogo", sw * 0.12, sh * 0.08, dcf * CF(sw * 0.4, -sh * 0.3, z + 0.014), "SPORTS", { fg = rgb(255, 255, 255), glow = 1.1, d = 0.004, font = F.GothamBlack, free = true })
	local tvBody = K:plate("TVLogoBadge", 0.36, 0.05, 0.01, dcf * CF(0, -h / 2 + 0.05, 0.24), L.with(L.chrome, { free = true }))
	-- 사운드바 (상호작용 손잡이; 문 앞 keep 에 걸리면 생략하고 TV 에 붙임)
	local bar = tvBody
	if clearAt(K, dcf * CF(0, -h / 2 - 0.36, 0.2), V3(w * 0.66, 0.42, 0.34)) then
		bar = K:box("TVSoundbar", V3(w * 0.66, 0.26, 0.34), dcf * CF(0, -h / 2 - 0.42, 0.19), L.of(26, 26, 28))
		K:box("TVSoundbarGrille", V3(w * 0.62, 0.18, 0.02), dcf * CF(0, -h / 2 - 0.42, 0.36), L.of(50, 50, 54, M.Fabric))
		K:box("TVSoundbarLED", V3(0.08, 0.04, 0.02), dcf * CF(w * 0.28, -h / 2 - 0.5, 0.37), L.ledGreen)
		K:seg("TVCable", (dcf * CF(w * 0.2, -h / 2, 0.08)).Position, (dcf * CF(w * 0.2, -h / 2 - 0.3, 0.08)).Position, 0.04, L.black)
	end
	local channels = {
		{ bg = rgb(36, 118, 54), dirt = true, stripes = false, live = true, logo = "SPORTS 1", bug = "롯데  3 : 2  두산\n▲ 7회  2사 1 · 2루", ticker = "KBO 리그 생중계 · 사직야구장 22,990석 매진" },
		{ bg = rgb(34, 124, 52), dirt = false, stripes = true, live = true, logo = "SPORTS 2", bug = "토트넘  1 - 0  첼시\n후반  72:14", ticker = "프리미어리그 9라운드 · 하이라이트는 경기 후 바로" },
		{ bg = rgb(16, 22, 60), dirt = false, stripes = false, live = false, logo = "BUSAN TV", bug = "광안리 M 드론 라이트쇼\n매주 토요일 20:00", ticker = "광안리해수욕장 · 드론 1,500대 · 오늘 밤 날씨 맑음" },
		{ bg = rgb(60, 24, 70), dirt = false, stripes = false, live = false, logo = "MUSIC", bug = "NOW PLAYING\n광안리 여름밤 플레이리스트", ticker = "♪ City Pop · Indie · K-Ballad  ·  신청곡은 바텐더에게" },
		{ bg = rgb(6, 6, 8), dirt = false, stripes = false, live = false, logo = "", bug = "", ticker = "", off = true },
	}
	local cur = 1
	local function apply(i: number)
		cur = i
		local ch = channels[i]
		scrLab.BackgroundColor3 = ch.bg
		dirt.Transparency = if ch.dirt then 0 else 1
		for _, p in dirt:GetChildren() do
			if p:IsA("SurfaceGui") then
				p.Enabled = ch.dirt
			end
		end
		for _, f in field do
			f.Transparency = if ch.dirt then 0 else 1
			for _, p in f:GetChildren() do
				if p:IsA("SurfaceGui") then
					p.Enabled = ch.dirt
				end
			end
		end
		for _, s in stripes do
			for _, p in s:GetChildren() do
				if p:IsA("SurfaceGui") then
					p.Enabled = ch.stripes
				end
			end
		end
		bug.Text = ch.bug
		bug.BackgroundTransparency = if ch.off then 1 else 0
		tick.Text = ch.ticker
		tick.BackgroundTransparency = if ch.off then 1 else 0
		logo.Text = ch.logo
		for _, p in live:GetChildren() do
			if p:IsA("SurfaceGui") then
				p.Enabled = ch.live
			end
		end
	end
	apply(1)
	Interact.cycle(K, bar, channels, {
		action = "채널 바꾸기",
		object = "스포츠 TV",
		on = function(i: number)
			apply(i)
		end,
	})
	-- 경기 진행 (볼카운트 · 시간) + LIVE 깜빡임
	local counts = { "B 1  S 0  O 2", "B 2  S 1  O 2", "B 3  S 2  O 2", "B 0  S 0  O 0" }
	local mins = { "72:14", "73:40", "75:02", "77:31" }
	local last = -1
	Interact.anim(K, function(t: number)
		local ch = channels[cur]
		if ch.live then
			liveLab.TextTransparency = if math.floor(t * 1.2) % 2 == 0 then 0 else 0.6
		end
		local k = math.floor(t / 6) % 4 + 1
		if k ~= last then
			last = k
			if cur == 1 then
				bug.Text = "롯데  3 : 2  두산\n▲ 7회  " .. counts[k]
			elseif cur == 2 then
				bug.Text = "토트넘  1 - 0  첼시\n후반  " .. mins[k]
			end
		end
	end)
	c.tv = { wall = wn :: string, u = u, w = w }
end

-- 8) 탭 리스트 보드 + (뒷벽이면) 아래 맥주 쿨러 · 잔 선반 ---------------------------------------------------
local function tapBoard(c: any)
	local K, V, th = c.K, c.V, c.th
	local g = V.counters[1]
	local near = if g then (g.min + g.max) / 2 else V3(0, 0, V.z0)
	local y0, y1 = 4.5, math.min(V.H - 0.8, 9.0)
	local side = if near.X < 0 then "left" else "right"
	local other = if side == "left" then "right" else "left"
	local wn, u, w = findWall(K, { "back", side, other }, 4.4, 7.6, y0, y1, near, 0.8)
	if not wn or not u or not w then
		return
	end
	local h = y1 - y0 - 0.4
	local dcf = V:wall(wn, u, (y0 + y1) / 2, 0.06)
	local rows = {}
	for _, t in th.taps do
		table.insert(rows, { t[1], t[2], t[3], t[4], t[5] })
	end
	listBoard(K, dcf, w - 0.4, h, th.board, th.boardTitle, th.boardSub, rows, th.boardFoot, nil)
	-- 보드 조명 (위에서 비추는 갤러리 램프 2)
	for _, sx in { -0.3, 0.3 } do
		local base = dcf * CF((w - 0.4) * sx, h / 2 + 0.3, -0.06)
		K:box("BoardLampMount", V3(0.18, 0.18, 0.06), base * CF(0, 0, 0.03), L.blackMetal)
		K:box("BoardLampArm", V3(0.06, 0.06, 0.62), base * CF(0, 0, 0.33), L.blackMetal)
		K:cyl("BoardLampHead", 0.5, 0.18, base * CF(0, -0.06, 0.66), L.blackMetal)
		K:box("BoardLampLens", V3(0.44, 0.02, 0.08), base * CF(0, -0.16, 0.66), L.lampWarm)
	end
	c.board = { wall = wn, u = u, w = w }
	-- 뒷벽 카운터 뒤면: 아래 언더카운터 쿨러 + 잔 선반 (깊이 1.0)
	if wn == "back" and g then
		local bw = math.min(w - 0.6, 6.4)
		local size = V3(bw, 3.0, 1.0)
		local pcf = V:wall("back", u, 0, 0.5 + 0.06)
		local mn, mx = laabb(pcf * CF(0, 1.5, 0), size)
		if behindCounter(V, (pcf * CF(0, 0, 1.2)).Position) and mapClear(V, mn, mx) and K:spot(pcf, size, 0.02, "cooler") then
			claim(K, "back", u - bw / 2 - 0.1, u + bw / 2 + 0.1, 0, 3.1)
			local nd = math.max(2, math.floor(bw / 2.0 + 0.5))
			local dw = bw / nd
			K:box("UnderCoolerBody", V3(bw, 2.6, 1.0), pcf * CF(0, 0.3 + 1.3, 0), L.steel)
			K:box("UnderCoolerKick", V3(bw - 0.1, 0.3, 0.9), pcf * CF(0, 0.15, -0.04), L.black)
			K:box("UnderCoolerTop", V3(bw + 0.04, 0.08, 1.04), pcf * CF(0, 2.94, 0), L.steel)
			for i = 1, nd do
				local x = -bw / 2 + dw * (i - 0.5)
				local fc = pcf * CF(x, 1.6, 0.5)
				K:plate("UnderCoolerDoor", dw - 0.08, 2.4, 0.05, fc, L.of(30, 30, 32, M.Metal))
				K:plate("UnderCoolerInner", dw - 0.34, 2.1, 0.02, fc * CF(0, 0, 0.05), L.of(226, 236, 242))
				local m = math.max(2, math.floor((dw - 0.4) / 0.28))
				for row = 0, 1 do
					for j = 1, m do
						local bx = -(dw - 0.5) / 2 + (dw - 0.5) * (j - 0.5) / m
						local col = (th.taps[((i + j + row) % #th.taps) + 1] :: any)[7] or rgb(200, 60, 40)
						K:box("UnderCoolerCan", V3(0.18, 0.42, 0.02), fc * CF(bx, -0.55 + row * 1.0, 0.075), { c = col })
					end
				end
				K:box("UnderCoolerGlass", V3(dw - 0.3, 2.1, 0.02), fc * CF(0, 0, 0.1), { c = rgb(210, 230, 236), m = M.Glass, t = 0.7, r = 0.15 })
				K:box("UnderCoolerHandle", V3(dw - 0.5, 0.06, 0.08), fc * CF(0, 1.06, 0.14), L.chrome)
			end
			-- 위: 바 매트 + 엎어 둔 파인트 잔
			K:box("BarMat", V3(bw - 0.4, 0.03, 0.7), pcf * CF(0, 3.0, 0), L.rubber)
			local ng = math.max(3, math.floor((bw - 0.6) / 0.42))
			for j = 1, ng do
				local gx = -(bw - 0.6) / 2 + (bw - 0.6) * (j - 0.5) / ng
				for row = 0, 1 do
					-- 엎어 둔 노닉 파인트 잔 (입구가 아래, 두꺼운 바닥이 위)
					local gp = pcf * CF(gx + row * 0.1, 3.015, -0.17 + row * 0.34)
					K:vcyl("PintGlass", 0.44, 0.26, gp * CF(0, 0.22, 0), { c = rgb(232, 240, 242), m = M.Glass, t = 0.62, r = 0.04 })
					if K.detail ~= "low" then
						K:vcyl("PintBulge", 0.06, 0.285, gp * CF(0, 0.12, 0), { c = rgb(232, 240, 242), m = M.Glass, t = 0.55, r = 0.04 })
						K:vcyl("PintBase", 0.05, 0.22, gp * CF(0, 0.465, 0), { c = rgb(214, 228, 230), m = M.Glass, t = 0.3, r = 0.04 })
					end
				end
			end
		end
	end
end

-- 9) 안주 보드 ---------------------------------------------------------------------------------------------
local function foodBoard(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.food then
		return
	end
	local walls = { "left", "right", "back" }
	if th.feature and th.feature.wall then
		walls = { th.feature.wall, "left", "right", "back" }
	end
	local near = V3((V.x0 + V.x1) / 2, 0, (V.z0 + V.z1) / 2)
	local wn, u, w = findWall(K, walls, 3.2, 4.4, 4.4, 7.8, near, 0.8)
	if not wn or not u or not w then
		return
	end
	local dcf = V:wall(wn, u, 6.1, 0.06)
	local style = if th.board == "digital" then "chalk" else th.board
	listBoard(K, dcf, w - 0.4, 3.0, style, th.foodTitle or "FOOD", nil, th.food, nil, nil)
end

-- 10) 네온사인 (소파 위 > 포인트 벽 > 아무 벽) + 켜기/끄기 ---------------------------------------------------
local function neonFeature(c: any)
	local K, V, th = c.K, c.V, c.th
	local store = c.neon
	local placed = nil
	local function tryWall(walls: { string }, near: Vector3?, minW: number, maxW: number, y0: number, y1: number): boolean
		local wn, u, w = findWall(K, walls, minW, maxW, y0, y1, near, 0.6)
		if wn and u and w then
			local hh = math.min(2.2, y1 - y0 - 0.2)
			local dcf = V:wall(wn, u, (y0 + y1) / 2, 0.08)
			neonSign(K, dcf, w - 0.3, hh, th, th.neonIcon, th.neonText, th.neonC, th.neon2, store)
			placed = { wall = wn, u = u, w = w, y = (y0 + y1) / 2, dcf = dcf }
			return true
		end
		return false
	end
	local done = false
	for _, b in c.banq or {} do
		if not done and (b.wall == "left" or b.wall == "right" or b.wall == "back") then
			local y0 = b.top + 0.7
			done = tryWall({ b.wall }, b.center, 4.0, math.min(7.0, b.len * 0.65), y0, math.min(y0 + 2.6, V.H - 0.6))
		end
	end
	if not done and th.feature then
		done = tryWall({ th.feature.wall }, nil, 4.0, 6.6, 5.0, 7.6)
	end
	if not done then
		done = tryWall({ "left", "right", "back" }, nil, 3.6, 6.0, 5.0, 7.6)
	end
	if not placed then
		return
	end
	-- 스위치 (손 닿는 높이, 서버 앵커에서 떨어진 자리)
	local pl = placed
	local function okAt(wn: string, uu: number, _w: number): boolean
		local lp = (V:wall(wn, uu, 4.8, 0.3)).Position
		return promptOK(K, lp) and reachable(K, wn, uu)
	end
	local swn, su = findWall(K, { pl.wall, "back", "left", "right" }, 0.5, 0.5, 4.45, 5.15, (pl.dcf * CF(pl.w / 2 + 0.6, -2, 0)).Position, 0.6, okAt)
	if not swn or not su then
		K:note("neon: no switch spot")
		return
	end
	local sd = V:wall(swn, su, 4.8, 0.07)
	local plate = K:plate("NeonSwitch", 0.42, 0.6, 0.05, sd, L.of(30, 30, 32))
	K:plate("NeonSwitchRocker", 0.16, 0.3, 0.04, sd * CF(0, 0.04, 0.05), L.of(220, 60, 60))
	K:text("NeonSwitchLabel", 0.4, 0.12, sd * CF(0, -0.38, 0.0), "NEON", { fg = rgb(220, 220, 220), d = 0.01, font = F.GothamBold })
	local base = {}
	for _, p in store.parts do
		table.insert(base, { p = p, c = p.Color })
	end
	Interact.toggle(K, plate, {
		object = "네온사인",
		onText = "네온 끄기",
		offText = "네온 켜기",
		state = true,
		on = function(s: boolean)
			for _, b in base do
				if b.p.Parent then
					b.p.Material = if s then M.Neon else M.SmoothPlastic
					b.p.Color = if s then b.c else b.c:Lerp(rgb(70, 70, 74), 0.7)
				end
			end
			for _, lab in store.labels do
				lab.TextTransparency = if s then 0 else 0.75
			end
			for _, l in store.lights do
				l.Enabled = s
			end
		end,
	})
end

-- 키 큰 소품이 TV · 보드 앞을 가리나 (벽 앞 3 스터드 상자)
local function blocksView(c: any, pcf: CFrame, size: Vector3): boolean
	local V = c.V
	local mn, mx = laabb(pcf * CF(0, size.Y / 2, 0), size)
	for _, it in { c.tv, c.board } do
		if it and it.wall and V.walls[it.wall] then
			local vmn, vmx = laabb(V:wall(it.wall, it.u, 5.5, 1.6), V3(it.w + 0.8, 5.0, 3.2))
			if overlap(mn, mx, vmn, vmx) then
				return true
			end
		end
	end
	return false
end

-- 11) 다트 머신 (벽에 세움, 앞 2.4m 던지는 선) + 게임 애니메이션 -----------------------------------------------------
local function dartMachine(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.dart then
		return
	end
	local size = V3(2.3, 7.7, 1.05)
	if V.H < 8.4 then
		return
	end
	local function test(pcf: CFrame, _wn: string, _u: number): boolean
		if blocksView(c, pcf, size) then
			return false
		end
		-- 프롬프트 자리 + 던지는 길 (앞 7.6) 에 가구 없음
		local lp = (pcf * CF(0.5, 2.3, size.Z / 2 + 0.2)).Position
		if not promptOK(K, lp) then
			return false
		end
		-- 던지는 사람 자리가 카운터 안쪽이면 안 됨
		for _, f in { 2.0, 4.5, 7.4 } do
			if behindCounter(V, (pcf * CF(0, 0, size.Z / 2 + f)).Position) then
				return false
			end
		end
		local mn, mx = laabb(pcf * CF(0, 2.6, size.Z / 2 + 3.9), V3(2.0, 5.0, 7.4))
		if mn.X < V.x0 - 0.1 or mx.X > V.x1 + 0.1 or mn.Z < V.z0 - 0.1 or mx.Z > V.z1 - 1.0 then
			return false
		end
		for _, s in V.solid do
			if overlap(mn, mx, s.min, s.max) then
				return false
			end
		end
		for _, r in K.reserved do
			if overlap(mn, mx, r.min, r.max) then
				return false
			end
		end
		for _, k in V.keep do
			if (k.kind == "door" or k.kind == "restroom" or k.kind == "staff") and overlap(mn, mx, k.min, k.max) then
				return false
			end
		end
		return true
	end
	local pcf = floorOnWall(K, { "left", "right", "back" }, size, V3(V.x0, 0, 0), 0.1, test)
	if not pcf then
		K:note("dart: no spot")
		return
	end
	local _ = reachable
	do
		local lmn, lmx = laabb(pcf * CF(0, 1.5, size.Z / 2 + 4.6), V3(2.4, 3.0, 9.0))
		K:reserve(lmn, lmx, "dartlane")
	end
	local accent = th.neon2 or rgb(60, 160, 255)
	local body = L.of(20, 20, 24)
	local D = size.Z
	local W = size.X
	-- 아래 캐비닛
	K:box("DartCabinet", V3(W, 2.9, D), pcf * CF(0, 1.45, 0), body)
	K:box("DartCabinetFront", V3(W - 0.2, 2.3, 0.04), pcf * CF(0, 1.5, D / 2 + 0.02), L.of(36, 40, 70))
	K:box("DartSpeaker", V3(0.7, 0.55, 0.03), pcf * CF(-0.5, 2.15, D / 2 + 0.05), L.of(44, 44, 48, M.DiamondPlate))
	local panel = K:box("DartPanel", V3(0.86, 0.66, 0.08), pcf * CF(0.5, 2.25, D / 2 + 0.06), L.of(28, 28, 32))
	local _, credit = K:text("DartCredit", 0.7, 0.16, pcf * CF(0.5, 2.44, D / 2 + 0.1), "CREDIT 00", { fg = rgb(255, 60, 50), bg = rgb(8, 8, 8), glow = 1.4, d = 0.01, font = F.Arcade })
	K:box("DartCardSlot", V3(0.4, 0.04, 0.03), pcf * CF(0.5, 2.2, D / 2 + 0.11), L.black)
	K:box("DartCoinSlot", V3(0.06, 0.22, 0.03), pcf * CF(0.75, 2.06, D / 2 + 0.11), L.chrome)
	K:text("DartInsert", 0.6, 0.1, pcf * CF(0.5, 2.0, D / 2 + 0.105), "INSERT CARD", { fg = rgb(220, 220, 220), d = 0.005, font = F.GothamBold })
	K:box("DartKick", V3(W - 0.1, 0.3, 0.05), pcf * CF(0, 0.15, D / 2 + 0.02), L.black)
	-- 위 하우징 (뒤판 + 양 날개 LED)
	K:box("DartBack", V3(W, 4.6, 0.5), pcf * CF(0, 2.9 + 2.3, -D / 2 + 0.25), body)
	local leds = {}
	for _, sx in { -1, 1 } do
		K:box("DartWing", V3(0.2, 4.6, 0.6), pcf * CF(sx * (W / 2 - 0.1), 5.2, -D / 2 + 0.6), body)
		local led = K:box("DartLED", V3(0.05, 4.3, 0.05), pcf * CF(sx * (W / 2 - 0.1), 5.2, -D / 2 + 0.92), L.neon(accent))
		table.insert(leds, led)
	end
	-- 다트판 (소프트팁: 캐치링 · 더블/트리플 링 · 세그먼트 · 불)
	local bc = pcf * CF(0, 5.0, -D / 2 + 0.5)
	wdisc(K, "DartCatch", 2.0, 0.06, bc, 0, L.of(26, 30, 60))
	wdisc(K, "DartNumberRing", 1.72, 0.04, bc, 0.06, L.black)
	wdisc(K, "DartDouble", 1.44, 0.03, bc, 0.1, L.of(210, 30, 40))
	wdisc(K, "DartSingle", 1.32, 0.03, bc, 0.13, L.of(236, 232, 220))
	wdisc(K, "DartTriple", 0.88, 0.03, bc, 0.16, L.of(40, 90, 200))
	wdisc(K, "DartInner", 0.78, 0.03, bc, 0.19, L.of(236, 232, 220))
	if K.detail ~= "low" then
		for k = 0, 9 do
			local a = k * PI / 5 + PI / 20
			K:box("DartSegment", V3(0.12, 0.64, 0.01), bc * CF(0, 0, 0.225) * ANG(0, 0, a) * CF(0, 0.33, 0), L.of(30, 30, 34))
		end
	end
	wdisc(K, "DartBullOuter", 0.18, 0.03, bc, 0.23, L.of(40, 90, 200))
	wdisc(K, "DartBull", 0.08, 0.03, bc, 0.26, L.of(210, 30, 40))
	-- 꽂힌 다트 3개
	for k, off in { { 0.12, 0.3 }, { -0.28, -0.1 }, { 0.05, -0.04 } } do
		local tip = (bc * CF(off[1], off[2], 0.25)).Position
		local tail = (bc * CF(off[1] + 0.05, off[2] + 0.08, 0.85)).Position
		K:seg("DartBarrel", tip, tail, 0.04, L.chrome)
		local fcol = if k == 1 then rgb(250, 60, 60) elseif k == 2 then rgb(60, 200, 255) else rgb(250, 220, 60)
		K:box("DartFlight", V3(0.16, 0.16, 0.01), CF(tail) * ANG(0, 0, PI / 4), { c = fcol })
	end
	-- 화면 + 헤더 간판
	local scr, scrLab = K:text("DartScreen", 1.7, 0.72, pcf * CF(0, 6.55, -D / 2 + 0.51), "DART  ·  501  ·  CRICKET\nINSERT CARD", { fg = rgb(255, 255, 255), bg = rgb(18, 30, 80), glow = 1.3, d = 0.02, font = F.GothamBold })
	local _ = scr
	K:box("DartHeader", V3(W, 0.6, 0.62), pcf * CF(0, 7.4, -D / 2 + 0.31), body)
	K:text("DartHeaderSign", W - 0.3, 0.42, pcf * CF(0, 7.4, -D / 2 + 0.62), "DARTS", { fg = accent, glow = 2.0, font = F.Bangers, d = 0.02 })
	-- 던지는 선 (바닥, 2.44m ≈ 7.2 스터드)
	local lineCF = pcf * CF(0, 0.012, D / 2 + 7.2)
	K:box("DartThrowLine", V3(2.0, 0.024, 0.18), lineCF, L.of(240, 240, 236))
	K:text("DartThrowText", 1.4, 0.3, CFrame.fromMatrix((pcf * CF(0, 0.03, D / 2 + 7.55)).Position, pcf.XVector, -pcf.ZVector, pcf.YVector), "THROW LINE", { fg = rgb(220, 220, 214), d = 0.005, font = F.GothamBlack, free = true })
	-- 게임 상태
	local playing = false
	local score = 501
	local hits = { "T20  ▶  60", "S5  ▶  5", "T19  ▶  57", "BULL  ▶  50", "S20  ▶  20", "D16  ▶  32", "T20  ▶  60", "S1  ▶  1" }
	local vals = { 60, 5, 57, 50, 20, 32, 60, 1 }
	local step = 0
	local lastT = 0
	local base: { [BasePart]: Color3 } = {}
	for _, l in leds do
		base[l] = l.Color
	end
	Interact.toggle(K, panel, {
		object = "다트 머신",
		onText = "게임 끝내기",
		offText = "다트 게임 시작",
		state = false,
		on = function(s: boolean)
			playing = s
			score = 501
			step = 0
			credit.Text = if s then "CREDIT 01" else "CREDIT 00"
			scrLab.Text = if s then "PLAYER 1   501\nGAME ON!" else "DART  ·  501  ·  CRICKET\nINSERT CARD"
		end,
	})
	Interact.anim(K, function(t: number)
		-- 대기: 천천히 색 순환 / 게임 중: 빠르게 깜빡임 + 점수
		for i, l in leds do
			if l.Parent then
				if playing then
					l.Color = if math.floor(t * 4 + i) % 2 == 0 then accent else rgb(255, 255, 255)
				else
					l.Color = Color3.fromHSV((t * 0.08 + i * 0.3) % 1, 0.8, 1)
				end
			end
		end
		if playing and t - lastT > 1.6 then
			lastT = t
			step += 1
			local k = (step - 1) % #hits + 1
			score -= vals[k]
			if score <= 0 then
				scrLab.Text = "PLAYER 1  WIN!\n☆ GAME SHOT ☆"
				score = 501
			else
				scrLab.Text = "PLAYER 1   " .. tostring(score) .. "\n" .. hits[k]
			end
		end
	end)
	c.dart = pcf
end

-- 12) 브라이트 탱크 · 케그 (크래프트 테마) ----------------------------------------------------------------------
local function briteTank(K: any, pcf: CFrame, dia: number, H: number, label: string, detail: string)
	local steel = L.of(150, 156, 162, M.Metal, { r = 0.28 })
	local legH = 1.4
	local r = dia / 2
	for i = 0, 3 do
		local a = i * PI / 2 + PI / 4
		local p0 = pcf * V3(math.cos(a) * r * 0.86, 0.05, math.sin(a) * r * 0.86)
		local p1 = pcf * V3(math.cos(a) * r * 0.72, legH + 0.55, math.sin(a) * r * 0.72)
		K:seg("TankLeg", p0, p1, 0.16, steel)
		K:disc("TankFoot", 0.34, 0.06, CF(p0 - V3(0, 0.02, 0)), steel)
	end
	K:ell("TankBottom", V3(dia, 1.1, dia), pcf * CF(0, legH + 0.55, 0), steel)
	local bodyH = H - legH - 0.55 - 0.45
	K:vcyl("TankBody", bodyH, dia, pcf * CF(0, legH + 0.55 + bodyH / 2, 0), steel)
	local topY = legH + 0.55 + bodyH
	K:ell("TankTop", V3(dia, 0.9, dia), pcf * CF(0, topY, 0), steel)
	-- 글리콜 냉각 재킷 (살짝 다른 결의 띠 + 위아래 용접선)
	for _, f in { 0.22, 0.68 } do
		local jy = legH + 0.55 + bodyH * f
		K:vcyl("TankJacket", bodyH * 0.24, dia + 0.03, pcf * CF(0, jy, 0), L.of(176, 180, 186, M.Metal, { r = 0.16 }))
		if detail ~= "low" then
			for _, sy in { -1, 1 } do
				K:vcyl("TankJacketSeam", 0.04, dia + 0.06, pcf * CF(0, jy + sy * bodyH * 0.12, 0), L.of(118, 122, 128, M.Metal))
			end
		end
	end
	-- 맨홀 (앞 아래)
	local mh = pcf * CF(0, legH + 0.55 + 0.75, r - 0.03)
	K:cyl("TankManway", 0.1, 0.78, mh * ANG(0, PI / 2, 0), steel)
	K:bar("TankManwayHandle", (mh * CF(-0.22, 0, 0.08)).Position, (mh * CF(0.22, 0, 0.08)).Position, 0.06, 0.06, L.blackMetal)
	-- 아래 배출 밸브 + 빨간 손잡이
	local vp = pcf * CF(0.34, legH + 0.62, r * 0.7)
	K:seg("TankPipe", vp.Position, (vp * CF(0, 0, 0.55)).Position, 0.12, steel)
	K:cyl("TankValve", 0.1, 0.28, vp * CF(0, 0, 0.42) * ANG(0, PI / 2, 0), steel)
	K:box("TankValveHandle", V3(0.36, 0.05, 0.06), vp * CF(0.12, 0.12, 0.42), L.of(200, 40, 40))
	-- 사이트 글라스 (맥주 높이)
	local sa = PI / 3
	local sx, sz = math.cos(sa) * (r + 0.08), math.sin(sa) * (r + 0.08)
	K:vcyl("TankSightGlass", bodyH * 0.78, 0.09, pcf * CF(sx, legH + 0.55 + bodyH * 0.5, sz), { c = rgb(220, 236, 240), m = M.Glass, t = 0.45 })
	K:vcyl("TankSightBeer", bodyH * 0.5, 0.06, pcf * CF(sx, legH + 0.55 + bodyH * 0.11 + bodyH * 0.25, sz), { c = rgb(214, 150, 50), m = M.Glass, t = 0.15 })
	-- 위: 압력계 · 안전밸브 · CIP 팔
	K:vcyl("TankTopPipe", 0.5, 0.1, pcf * CF(0.3, topY + 0.3, 0), steel)
	K:cyl("TankGauge", 0.06, 0.26, pcf * CF(0.3, topY + 0.6, 0.06) * ANG(0, PI / 2, 0), L.white)
	K:seg("TankCIP", (pcf * CF(-0.25, topY + 0.35, 0)).Position, (pcf * CF(-0.25, topY + 0.75, 0)).Position, 0.12, steel)
	K:seg("TankCIP", (pcf * CF(-0.25, topY + 0.75, 0)).Position, (pcf * CF(-0.25, topY + 0.75, -r - 0.1)).Position, 0.12, steel)
	-- 라벨 (분필 태그 + 금속판)
	K:text("TankLabel", 0.95, 0.52, pcf * CF(0, legH + 0.55 + bodyH * 0.46, r + 0.015), label, { fg = rgb(30, 30, 30), bg = rgb(240, 240, 236), d = 0.01, font = F.GothamBold })
	if detail == "high" then
		K:box("TankWeld", V3(0.02, bodyH, 0.02), pcf * CF(-r * 0.7, legH + 0.55 + bodyH / 2, r * 0.71), L.of(160, 164, 168, M.Metal))
	end
	-- 온도 · 압력 컨트롤러 (글리콜 냉각)
	local cx = -0.55
	local cz = math.sqrt(math.max(0.01, r * r - cx * cx))
	local ctl = K:box("TankController", V3(0.52, 0.7, 0.16), pcf * CF(cx, 4.35, cz + 0.07), L.of(232, 232, 228))
	local _, lcd = K:text("TankControllerLCD", 0.42, 0.3, pcf * CF(cx, 4.45, cz + 0.152), "", { fg = rgb(120, 255, 160), bg = rgb(10, 20, 14), glow = 1.3, d = 0.005, font = F.Arcade })
	K:box("TankControllerLED", V3(0.06, 0.06, 0.02), pcf * CF(cx + 0.15, 4.12, cz + 0.155), L.ledGreen)
	K:seg("TankControllerCable", (pcf * CF(cx, 4.0, cz + 0.05)).Position, (pcf * CF(cx, 3.2, cz + 0.02)).Position, 0.03, L.black)
	return ctl, lcd
end

local function keg(K: any, base: CFrame, cap: Color3)
	local steel = L.of(150, 154, 160, M.Metal, { r = 0.22 })
	local kd, kh = 1.3, 1.95
	K:vcyl("KegChime", 0.28, kd - 0.08, base * CF(0, 0.14, 0), steel)
	K:vcyl("KegBody", kh - 0.56, kd, base * CF(0, 0.28 + (kh - 0.56) / 2, 0), steel)
	K:vcyl("KegChime", 0.28, kd - 0.08, base * CF(0, kh - 0.14, 0), steel)
	for _, f in { 0.36, 0.64 } do
		K:vcyl("KegRib", 0.06, kd + 0.05, base * CF(0, kh * f, 0), steel)
	end
	K:vcyl("KegSpear", 0.12, 0.34, base * CF(0, kh - 0.2, 0), L.of(40, 40, 44))
	K:vcyl("KegCap", 0.04, 0.4, base * CF(0, kh - 0.12, 0), { c = cap })
end

local function okFront(V: any, c: any?, size: Vector3?): any
	return function(pcf: CFrame, _wn: string, _u: number): boolean
		if c and size and blocksView(c, pcf, size) then
			return false
		end
		return not behindCounter(V, pcf.Position)
	end
end

local function tanks(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.tanks or V.H < 8.6 or not budget(K, 80) then
		return
	end
	local H = math.min(V.H - 0.7, 8.8)
	local dia = 2.3
	local walls = { "back", "left", "right" }
	local near = V3((V.x0 + V.x1) / 2 + V.W * 0.25, 0, V.z0)
	local size = V3(2 * dia + 0.5, H + 0.6, dia + 0.3)
	local spots = {}
	local pcf = floorOnWall(K, walls, size, near, 0.15, okFront(V, c, size))
	if pcf then
		table.insert(spots, { pcf, 2 })
	else
		size = V3(dia + 0.4, H + 0.6, dia + 0.3)
		for _ = 1, 2 do
			local p1 = floorOnWall(K, walls, size, near, 0.15, okFront(V, c, size))
			if p1 then
				table.insert(spots, { p1, 1 })
			end
		end
	end
	if #spots == 0 then
		K:note("tanks: no spot")
		return
	end
	local k = 0
	local ctls = {}
	for _, sp in spots do
		local scf, n = sp[1], sp[2]
		for i = 1, n do
			k += 1
			local x = if n == 2 then (i - 1.5) * (dia + 0.35) else 0
			local b = th.taps[(k % #th.taps) + 1]
			local ctl, lcd = briteTank(K, scf * CF(x, 0, 0), dia, H, string.format("BRITE TANK 0%d\n%s · 1,000L", k, b[1]), K.detail)
			table.insert(ctls, { ctl, lcd, k, b })
		end
		K:box("TankDrain", V3(n * (dia + 0.35) - 0.3, 0.03, 0.4), scf * CF(0, 0.015, dia / 2 + 0.25), L.of(120, 124, 128, M.DiamondPlate))
	end
	c.tankAt = spots[1][1].Position
	-- 컨트롤러 화면: 첫 탱크는 손님이 눌러 볼 수 있음 (온도 · 압력 · 탄산 · 출고)
	local prompted = false
	for _, t in ctls do
		local ctl, lcd, num, b = t[1], t[2], t[3], t[4]
		local pages = {
			string.format("T%02d %s\n 2.0°C  1.1bar", num, b[6] or "ALE"),
			string.format("CO2 %.1f vol\nSET 2.6 vol", 2.4 + num * 0.1),
			"STATUS\nSERVING TODAY",
			string.format("BATCH #%d\nABV %s", 210 + num * 7, b[3] or "5.0%"),
		}
		lcd.Text = pages[1]
		if not prompted and ctl.Parent and promptOK(K, (K.cf:ToObjectSpace(ctl.CFrame)).Position) then
			prompted = true
			Interact.cycle(K, ctl, pages, {
				action = "탱크 상태 보기",
				object = "브라이트 탱크 " .. tostring(num),
				on = function(_i: number, txt: string)
					lcd.Text = txt
				end,
			})
		else
			local cur = 0
			Interact.anim(K, function(tt: number)
				local pg = math.floor(tt / 5 + num) % #pages + 1
				if pg ~= cur then
					cur = pg
					lcd.Text = pages[pg]
				end
			end)
		end
	end
end

local function kegs(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.kegs or not budget(K, 30) then
		return
	end
	local size = V3(2.9, 2.0, 1.45)
	local pcf = floorOnWall(K, { "back", "left", "right" }, size, c.tankAt or V3(V.x1, 0, V.z0), 0.1, okFront(V))
	if pcf then
		local caps = { rgb(200, 40, 40), rgb(40, 120, 200), rgb(240, 190, 40) }
		keg(K, pcf * CF(-0.72, 0, 0), caps[1])
		keg(K, pcf * CF(0.72, 0, 0), caps[2])
		K:text("KegTag", 0.6, 0.34, pcf * CF(-0.72, 1.05, 0.66), "IPA\n20L", { fg = rgb(30, 30, 30), bg = rgb(250, 236, 200), d = 0.01, font = F.GothamBlack })
	end
end

-- 13) 천장: 에디슨 펜던트 (테이블 위) · 스파이럴 덕트 · 페스툰 · 매달린 와인잔 랙 · 미러볼 ---------------------------
local function tablePendants(c: any)
	local K, V, th = c.K, c.V, c.th
	local lit = 0
	for ti, t in V.tables do
		if t.kind == "grill" then
			continue
		end
		local cx, cz = (t.min.X + t.max.X) / 2, (t.min.Z + t.max.Z) / 2
		local maxDrop = V.H - (t.y + 3.5) - 0.15
		if maxDrop < 0.8 then
			continue
		end
		local offs = if (t.max.X - t.min.X) * (t.max.Z - t.min.Z) > 7 then { { -0.55, 0.2, 0 }, { 0.5, -0.25, 0.35 } } else { { -0.32, 0.12, 0 }, { 0.3, -0.18, 0.4 }, { 0.02, 0.36, 0.2 } }
		for k, o in offs do
			local x, z = cx + o[1], cz + o[2]
			local drop = math.min(2.1 + o[3], maxDrop)
			if Common.ceilFree(K, x, z, 0.3) and clearAt(K, CF(x, V.H - drop / 2, z), V3(1.0, drop + 0.1, 1.0)) then
				local light = k == 1 and lit < 2 and #K.lights < (V.maxLights or 8) - 1
				Props.pendant(K, V3(x, V.H, z), drop, { shade = th.tablePendant or "bulb", dia = if th.tablePendant == "bulb" then 0.9 else 0.8, look = th.pendant and th.pendant.look, light = light, range = 14, bright = 0.95 })
				Common.useCeil(K, x, z)
				if light then
					lit += 1
				end
			end
		end
		local _ = ti
	end
end

local function ducts(c: any)
	local K, V, th = c.K, c.V, c.th
	if V.H < 8.6 or not budget(K, 60) then
		return
	end
	local dia = 0.95
	local y = V.H - 0.32 - dia / 2
	local bestZ, bestRuns, bestLen = nil, nil, 0
	for _, f in { 0.52, 0.44, 0.6, 0.36, 0.68 } do
		local z = V.z0 + V.D * f
		local runs, cur = {}, nil
		local x = V.x0 + 0.5
		while x <= V.x1 - 0.5 do
			local ok = Common.ceilFree(K, x, z, 0.62) and not K:hitsKeep(V3(x - 0.3, y - dia / 2, z - dia / 2), V3(x + 0.3, y + dia / 2, z + dia / 2))
			if ok then
				if not cur then
					cur = { x, x }
					table.insert(runs, cur)
				end
				cur[2] = x
			else
				cur = nil
			end
			x += 0.5
		end
		local total = 0
		for _, r in runs do
			if r[2] - r[1] >= 3 then
				total += r[2] - r[1]
			end
		end
		if total > bestLen then
			bestZ, bestRuns, bestLen = z, runs, total
		end
	end
	if not bestZ or not bestRuns then
		return
	end
	local z = bestZ :: number
	c.duct = { z = z, y = y, dia = dia }
	local galv = L.of(178, 182, 186, M.Metal, { r = 0.08 })
	local joint = L.of(150, 154, 158, M.Metal)
	K:free(function()
		for _, r in bestRuns :: { any } do
			local a, b = r[1], r[2]
			local len = b - a
			if len < 3 then
				continue
			end
			local ns = math.max(1, math.ceil(len / 4))
			local sl = len / ns
			for i = 0, ns - 1 do
				local xm = a + sl * (i + 0.5)
				K:cyl("Duct", sl, dia, CF(xm, y, z), galv)
			end
			for i = 0, ns do
				local xj = a + sl * i
				K:cyl("DuctJoint", 0.14, dia + 0.05, CF(xj, y, z), joint)
				K:box("DuctHanger", V3(0.05, V.H - y - dia / 2 + 0.02, 0.1), CF(xj, (V.H + y + dia / 2) / 2, z + dia / 2 - 0.02), L.blackMetal)
				K:box("DuctHanger", V3(0.05, V.H - y - dia / 2 + 0.02, 0.1), CF(xj, (V.H + y + dia / 2) / 2, z - dia / 2 + 0.02), L.blackMetal)
			end
			for _, xe in { a, b } do
				K:cyl("DuctCap", 0.05, dia - 0.04, CF(xe + (if xe == a then -0.02 else 0.02), y, z), joint)
			end
			-- 아래 슬롯 디퓨저
			local ng = math.max(1, math.floor(len / 7))
			for i = 1, ng do
				local xg = a + len * (i - 0.5) / ng
				K:box("DuctGrille", V3(1.4, 0.06, 0.34), CF(xg, y - dia / 2 + 0.02, z), L.of(60, 62, 66))
				for k = -2, 2 do
					K:box("DuctSlot", V3(1.3, 0.065, 0.03), CF(xg, y - dia / 2 + 0.02, z + k * 0.06), L.black)
				end
			end
			local xx = a
			while xx <= b do
				Common.useCeil(K, xx, z)
				xx += 1.2
			end
		end
	end)
	-- 전선관 (뒷벽 위)
	local cy = V.H - 0.25
	K:free(function()
		K:seg("Conduit", V3(V.x0 + 0.4, cy, V.z0 + 0.25), V3(V.x1 - 0.4, cy, V.z0 + 0.25), 0.08, L.blackMetal)
		for _, f in { 0.25, 0.75 } do
			K:box("JunctionBox", V3(0.36, 0.36, 0.2), CF(V.x0 + V.W * f, cy, V.z0 + 0.25), L.blackMetal)
		end
	end)
	local _ = th
end

local function festoon(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.festoon or V.H < 8.4 or not budget(K, 80) then
		return
	end
	local function line(a: Vector3, b: Vector3, sag: number)
		local len = (b - a).Magnitude
		local n = math.max(3, math.floor(len / (if len > 30 then 2.8 else 2.2)))
		local pts = {}
		for i = 0, n do
			local t = i / n
			table.insert(pts, a:Lerp(b, t) - V3(0, sag * 4 * t * (1 - t), 0))
		end
		for i = 1, n do
			K:seg("FestoonCable", pts[i], pts[i + 1], 0.035, L.black)
		end
		for i = 2, n do
			local p = pts[i]
			K:vcyl("FestoonSocket", 0.14, 0.1, CF(p - V3(0, 0.07, 0)), L.black)
			K:ell("FestoonBulb", V3(0.2, 0.28, 0.2), CF(p - V3(0, 0.27, 0)), L.lampWarm)
		end
		for _, e in { a, b } do
			K:ball("FestoonHook", 0.1, CF(e), L.blackMetal)
		end
	end
	-- 앞쪽 자리 위로 두 줄 (출입문 위 keep 은 피함: 문 keep 은 z >= 문 - 4.4)
	local doorZ = if V.door then V.door.z - 4.6 else V.z1 - 4.6
	local z1 = math.min(doorZ - 0.3, V.z1 - 3)
	local z0 = V.z0 + V.D * 0.38
	local yTop = V.H - 0.15
	K:free(function()
		line(V3(V.x0 + 0.05, yTop, z1), V3(V.x1 - 0.05, yTop, z0), 1.0)
		line(V3(V.x0 + 0.05, yTop, z0), V3(V.x1 - 0.05, yTop, z1), 1.0)
	end)
end

local function glassRack(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.glassRack then
		return
	end
	local g = V.counters[1]
	if not g or not budget(K, 80) then
		return
	end
	-- 카운터 뒤쪽 위 (7.1 ~ 7.6), 바 펜던트 피함
	local z = g.min.Z + 0.55
	local y = math.min(7.6, V.H - 1.4)
	local x0, x1 = nil, nil
	local best = 0
	local runs, cur = {}, nil
	local x = g.min.X + 0.8
	while x <= g.max.X - 0.8 do
		if Common.ceilFree(K, x, z, 0.75) then
			if not cur then
				cur = { x, x }
				table.insert(runs, cur)
			end
			cur[2] = x
		else
			cur = nil
		end
		x += 0.25
	end
	for _, r in runs do
		if r[2] - r[1] > best then
			best = r[2] - r[1]
			x0, x1 = r[1], r[2]
		end
	end
	if not x0 or not x1 or best < 3 then
		return
	end
	local a, b = x0 :: number, math.min(x1 :: number, (x0 :: number) + 7)
	local metal = th.trim
	K:free(function()
		K:box("GlassRackFrame", V3(b - a, 0.06, 0.08), CF((a + b) / 2, y, z - 0.45), metal)
		K:box("GlassRackFrame", V3(b - a, 0.06, 0.08), CF((a + b) / 2, y, z + 0.45), metal)
		for _, xe in { a, b } do
			K:box("GlassRackFrame", V3(0.08, 0.06, 0.98), CF(xe, y, z), metal)
			K:seg("GlassRackRod", V3(xe, y, z), V3(xe, V.H, z), 0.05, metal)
		end
		local n = math.floor((b - a - 0.3) / 0.42)
		for row = -1, 1, 2 do
			K:box("GlassRackSlide", V3(b - a - 0.1, 0.04, 0.05), CF((a + b) / 2, y - 0.04, z + row * 0.2), metal)
			for i = 1, n do
				local gx = a + 0.15 + (b - a - 0.3) * (i - 0.5) / n
				local gz = z + row * 0.2
				K:disc("WineGlassFoot", 0.26, 0.02, CF(gx, y - 0.08, gz), L.glassClear)
				K:vcyl("WineGlassStem", 0.36, 0.04, CF(gx, y - 0.27, gz), L.glassClear)
				K:ell("WineGlassBowl", V3(0.32, 0.42, 0.32), CF(gx, y - 0.62, gz), { c = rgb(226, 236, 240), m = M.Glass, t = 0.6, r = 0.2 })
			end
		end
	end)
end

local function disco(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.disco then
		return
	end
	local x, z = (V.x0 + V.x1) / 2 + V.W * 0.18, (V.z0 + V.z1) / 2 + 1.0
	if not Common.ceilFree(K, x, z, 0.9) then
		return
	end
	Common.useCeil(K, x, z)
	local parts = {}
	K:free(function()
		K:seg("DiscoRod", V3(x, V.H, z), V3(x, V.H - 1.1, z), 0.05, L.chrome)
		local ball = K:ball("DiscoBall", 1.3, CF(x, V.H - 1.75, z), { c = rgb(220, 224, 230), m = M.Glass, r = 0.6 })
		table.insert(parts, ball)
		for k = 0, 7 do
			local a = k * PI / 4
			local p = K:box("DiscoMirror", V3(0.22, 0.22, 0.02), CF(x, V.H - 1.75, z) * ANG(0, a, 0) * ANG(0.25 * (k % 3 - 1), 0, 0) * CF(0, 0, 0.66), L.with(L.chrome, { r = 0.6 }))
			table.insert(parts, p)
		end
	end)
	Interact.spin(K, parts, (K.cf * CF(x, 0, z)).Position, 0.08)
end

-- 14) 카운터 위 소품 (코스터 · 바 캐디 · 해피아워 텐트 · 결제 안내) ------------------------------------------------
local function counterProps(c: any)
	local K, V, th = c.K, c.V, c.th
	for gi, g in V.counters do
		local alongX = (g.max.X - g.min.X) >= (g.max.Z - g.min.Z)
		if not alongX then
			continue
		end
		local top = g.y + 0.006
		local custZ = if (V.door and V.door.z or V.z1) > (g.min.Z + g.max.Z) / 2 then 1 else -1
		local edgeZ = if custZ > 0 then g.max.Z else g.min.Z
		local stoolX = {}
		for _, st in V.stools do
			local sc = st.seat.c
			if sc.X > g.min.X and sc.X < g.max.X and (sc.Z - edgeZ) * custZ > 0 and (sc.Z - edgeZ) * custZ < 2.6 then
				table.insert(stoolX, sc.X)
				-- 코스터 (원형 펄프 + 로고 원)
				local p = V3(sc.X + 0.12, top + 0.01, edgeZ - custZ * 0.42)
				if clearAt(K, CF(p), V3(0.5, 0.03, 0.5)) then
					K:disc("Coaster", 0.48, 0.02, CF(p), L.of(236, 226, 204, M.Cardboard))
					K:disc("CoasterPrint", 0.3, 0.022, CF(p + V3(0, 0.002, 0)), { c = th.neonC:Lerp(rgb(0, 0, 0), 0.25) })
				end
			end
		end
		-- 상판 앞 모서리 황동 띠 + 스툴 사이 가방 고리 (카운터 면에 붙임)
		local body = g.body or g.top
		if g.top and body then
			local tz = if custZ > 0 then g.top.max.Z else g.top.min.Z
			local bz = if custZ > 0 then body.max.Z else body.min.Z
			local tw = g.top.max.X - g.top.min.X
			K:free(function()
				K:box("CounterBrassEdge", V3(tw + 0.02, 0.05, 0.03), CF((g.top.min.X + g.top.max.X) / 2, g.y - 0.075, tz + custZ * 0.035), th.trim)
				local xs = {}
				for i = 1, #stoolX - 1 do
					table.insert(xs, (stoolX[i] + stoolX[i + 1]) / 2)
				end
				if K.detail ~= "low" then
					for _, hx in xs do
						local fz = bz + custZ * 0.06
						K:box("BagHookPlate", V3(0.16, 0.22, 0.03), CF(hx, g.y - 0.55, fz), th.trim)
						K:bar("BagHook", V3(hx, g.y - 0.6, fz), V3(hx, g.y - 0.72, fz + custZ * 0.18), 0.05, 0.05, th.trim)
					end
				end
			end)
		end
		if gi > 1 then
			continue
		end
		table.sort(stoolX)
		-- 의자 사이 빈 자리 (탭 타워에서 떨어진 곳)
		local gaps = {}
		for i = 1, #stoolX - 1 do
			table.insert(gaps, (stoolX[i] + stoolX[i + 1]) / 2)
		end
		table.insert(gaps, g.max.X - 0.9)
		table.insert(gaps, g.min.X + 0.9)
		local tapX = if c.tap then c.tap.cf.X else math.huge
		local used = 0
		local zMid = (g.min.Z + g.max.Z) / 2
		for _, gx in gaps do
			if math.abs(gx - tapX) < 2.2 or not clearAt(K, CF(gx, top + 0.4, zMid + custZ * 0.1), V3(1.1, 0.8, 0.7)) then
				continue
			end
			used += 1
			local pc = CF(gx, top, zMid + custZ * 0.1)
			if used == 1 then
				-- 바 캐디 (냅킨 · 빨대 · 코스터 더미)
				K:box("BarCaddy", V3(0.9, 0.3, 0.42), pc * CF(0, 0.15, 0), L.blackMetal)
				K:box("BarCaddyNapkin", V3(0.36, 0.22, 0.36), pc * CF(-0.2, 0.36, 0), L.paper)
				for k = 0, 5 do
					K:seg("Straw", (pc * CF(0.22 + (k % 3) * 0.06 - 0.06, 0.28, (k // 3) * 0.1 - 0.05)).Position, (pc * CF(0.24 + (k % 3) * 0.07 - 0.06, 0.66, (k // 3) * 0.12 - 0.06)).Position, 0.025, { c = if k % 2 == 0 then rgb(30, 30, 30) else th.neonC })
				end
				K:vcyl("CoasterStack", 0.18, 0.46, pc * CF(0.55, 0.09, 0.3), L.of(236, 226, 204, M.Cardboard))
			elseif used == 2 then
				-- 해피아워 텐트 카드
				for _, sd in { -1, 1 } do
					local n = V3(0, 0.31, sd * 0.95)
					local upv = V3(0, 0.95, -sd * 0.31)
					local pos = (pc * CF(0, 0.24, sd * 0.09)).Position
					K:text("TentCard", 0.6, 0.5, CFrame.fromMatrix(pos, upv:Cross(n).Unit, upv, n), "HAPPY HOUR\n17:00 – 19:00\n생맥주 1,000원 ↓", { fg = rgb(30, 30, 30), bg = rgb(250, 240, 214), d = 0.01, font = F.GothamBlack })
				end
			elseif used == 3 then
				-- 간편결제 안내 스탠드
				Props.menuStand(K, pc * CF(0, 0, 0) * ANG(0, 0, 0), "카드 · 삼성페이\n애플페이 · 카카오페이\n제로페이 결제 가능")
			elseif used == 4 then
				-- 기본 안주 (뻥튀기 바구니)
				K:vcyl("SnackBasket", 0.18, 0.62, pc * CF(0, 0.09, 0), L.rattan)
				K:ell("SnackPopcorn", V3(0.56, 0.2, 0.56), pc * CF(0, 0.2, 0), L.of(244, 226, 170))
			end
			if used >= 4 then
				break
			end
		end
		-- 카운터 열린 끝: STAFF ONLY (끝면에 붙임)
		local eb = g.body or g
		local endX = eb.max.X
		K:free(function()
			K:text("StaffOnly", 1.1, 0.34, CFrame.fromMatrix(V3(endX + 0.015, 2.4, (eb.min.Z + eb.max.Z) / 2), V3(0, 0, -1), Vector3.yAxis, V3(1, 0, 0)), "STAFF ONLY", { fg = rgb(255, 255, 255), bg = rgb(170, 30, 30), d = 0.01, font = F.GothamBlack })
		end)
	end
end

-- 15) 벽 장식: 포스터 · 맥주병 진열 선반 · 서핑보드 · 야구배트 · 스피커 · 시계 · 사업자등록증 · 안내판 ----------------------
local function wallDecor(c: any)
	local K, V, th = c.K, c.V, c.th
	local seed = c.seed
	local center = V3((V.x0 + V.x1) / 2, 0, (V.z0 + V.z1) / 2)
	-- 맥주병 · 캔 진열 선반 (포인트 벽 높은 곳)
	do
		local walls = { (th.feature and th.feature.wall) or "left", "left", "right" }
		local wn, u, w = findWall(K, walls, 3.0, 7.0, 6.9, 7.9, center, 0.8)
		if wn and u and w then
			local top = Props.shelf(K, V:wall(wn, u, 7.0, 0.06), w - 0.3, { depth = 0.7, look = th.mid, bracket = L.blackMetal })
			local n = math.max(3, math.floor((w - 0.6) / 0.42))
			for i = 1, n do
				local x = -(w - 0.6) / 2 + (w - 0.6) * (i - 0.5) / n
				local tp = th.taps[(i + seed) % #th.taps + 1]
				local pc = top * CF(x, 0, -0.05)
				if th.key == "fuzzy" or th.key == "party" then
					bottle(K, pc, 0.75 + rnd(seed, i) * 0.25, (th.bottleMix or { "round" })[(i % #(th.bottleMix or { 1 })) + 1], GLASS[(i * 3 + seed) % #GLASS + 1], LABELS[i % #LABELS + 1], L.goldMetal, K.detail)
				elseif i % 2 == 0 then
					beerCan(K, pc, tp[7] or tp[5], rgb(250, 250, 246), K.detail)
				else
					beerBottle(K, pc, if i % 3 == 0 then rgb(40, 96, 56) else rgb(110, 60, 24), LABELS[(i + seed) % #LABELS + 1], K.detail)
				end
			end
		end
	end
	-- 서핑보드 (서핑 테마) / 야구배트 (야구 테마)
	if th.surf then
		local wn, u, w = findWall(K, { "right", "left", "back" }, 3.2, 3.6, 4.4, 8.9, center, 0.8)
		if wn and u and w then
			local cols = { rgb(250, 120, 80), rgb(80, 200, 220), rgb(250, 230, 120) }
			for k = 1, 3 do
				local d = V:wall(wn, u + (k - 2) * 1.05, 6.6, 0.1) * ANG(0, 0, (k - 2) * -0.08)
				K:ell("Surfboard", V3(0.82, 4.0, 0.14), d, { c = cols[k], m = M.SmoothPlastic })
				K:box("SurfStringer", V3(0.03, 3.8, 0.15), d, wood(150, 110, 70))
				K:box("SurfFin", V3(0.06, 0.4, 0.3), d * CF(0, -1.6, 0.18), L.black)
				K:box("SurfRack", V3(0.9, 0.08, 0.3), d * CF(0, -0.9, 0.0), L.blackMetal)
			end
		end
	end
	if th.bats then
		local wn, u, w = findWall(K, { "left", "right", "back" }, 3.0, 3.4, 4.6, 8.4, center, 0.8)
		if wn and u and w then
			for k = 1, 3 do
				local d = V:wall(wn, u + (k - 2) * 0.9, 6.5, 0.12)
				K:seg("BaseballBat", (d * CF(0, -1.5, 0.05)).Position, (d * CF(0, 1.4, 0.05)).Position, 0.18, wood(196, 150, 96))
				K:seg("BaseballBatHandle", (d * CF(0, -1.9, 0.05)).Position, (d * CF(0, -1.45, 0.05)).Position, 0.1, L.black)
				K:box("BatPeg", V3(0.5, 0.06, 0.2), d * CF(0, 0.4, 0.0), L.blackMetal)
			end
			K:text("BatPlate", 2.2, 0.36, V:wall(wn, u, 4.75, 0.08), "사직 직관 기념 배트", { fg = rgb(255, 255, 255), bg = rgb(20, 34, 76), d = 0.02 })
		end
	end
	-- 포스터 (남는 벽)
	local targets = { V3(V.x0, 0, 0), V3(V.x1, 0, V.z0 + 3), V3(0, 0, V.z0), V3(V.x0, 0, V.z1 - 4), V3(V.x1, 0, V.z1 - 4) }
	local np = 0
	-- 같은 테마 매장끼리 다르게: 포스터 순서를 매장 키로 돌림
	local plist = {}
	local src = th.posters or {}
	for i = 1, #src do
		plist[i] = src[(i + seed) % #src + 1]
	end
	for i, kind in plist do
		if not budget(K, 30) then
			break
		end
		local near = targets[(i - 1) % #targets + 1]
		local wn, u = findWall(K, { "left", "right", "back" }, 2.0, 2.0, 4.3, 7.5, near, 0.8)
		if wn and u then
			poster(K, V:wall(wn, u, 5.9, 0.06), 2.0, 2.8, kind, th)
			np += 1
		end
	end
	-- 스피커 2 (천장 가까운 벽 모서리)
	for k, near in { V3(V.x0, 0, V.z0 + 1), V3(V.x1, 0, V.z0 + 1) } do
		local wn, u = findWall(K, { if k == 1 then "left" else "right", "back" }, 1.0, 1.0, V.H - 2.0, V.H - 0.5, near, 0.8)
		if wn and u then
			local d = V:wall(wn, u, V.H - 1.25, 0.06)
			K:plate("SpeakerBracket", 0.3, 0.3, 0.3, d * CF(0, 0.5, 0), L.blackMetal)
			K:box("Speaker", V3(0.8, 1.2, 0.7), d * CF(0, 0, 0.45) * ANG(-0.25, 0, 0), L.of(24, 24, 26))
			K:box("SpeakerGrille", V3(0.7, 1.0, 0.02), d * CF(0, 0, 0.45) * ANG(-0.25, 0, 0) * CF(0, 0, 0.36), L.of(40, 40, 44, M.Fabric))
		end
	end
	-- 시계 (빈티지 황동)
	do
		local wn, u = findWall(K, { "back", "right", "left" }, 1.6, 1.6, 7.0, 8.7, V3(0, 0, V.z0), 0.8)
		if wn and u then
			local d = V:wall(wn, u, 7.85, 0.06)
			local hr, mn = Props.clock(K, d, 1.4, { frame = th.trim })
			Interact.clock(K, hr, mn, d, 1.4)
		end
	end
	-- 사업자등록증 · 영업신고증 (카운터 가까이)
	local g = V.counters[1]
	local nearC = if g then (g.min + g.max) / 2 else center
	do
		local wn, u = findWall(K, { "back", "left", "right" }, 1.3, 1.3, 4.6, 6.4, nearC, 0.8)
		if wn and u then
			Props.license(K, V:wall(wn, u, 5.5, 0.06), shopName(V))
		end
	end
	-- 입구 안내판 (영업시간 · 19세 · 와이파이 · 음주운전)
	local front = V3(0, 0, V.z1 - 2.5)
	local signs = {
		{ 1.5, 1.1, th.hours or "영업시간\n17:00 – 02:00", rgb(250, 246, 236), rgb(24, 24, 26), th.trim and (th.trim.c :: Color3) },
		{ 1.5, 0.95, "청소년 유해업소\n19세 미만 출입 · 고용 금지\n신분증 확인 후 입장", rgb(30, 30, 30), rgb(252, 252, 250), rgb(200, 30, 30) },
		{ 1.1, 0.8, "FREE Wi-Fi\nID  " .. (th.wifi or "PUB_5G"), rgb(255, 255, 255), rgb(30, 30, 34), nil },
		{ 1.5, 0.7, "음주운전은 범죄입니다\n대리운전은 직원에게 문의하세요", rgb(255, 255, 255), rgb(30, 60, 140), nil },
	}
	for i, s in signs do
		local wn, u = findWall(K, { if i % 2 == 1 then "left" else "right", if i % 2 == 1 then "right" else "left" }, s[1] + 0.1, s[1] + 0.1, 4.6, 4.6 + s[2] + 0.2, V3(if i % 2 == 1 then V.x0 else V.x1, 0, V.z1 - 3), 0.8)
		if wn and u then
			signPlate(K, V:wall(wn, u, 4.6 + s[2] / 2 + 0.1, 0.06), s[1], s[2], s[3], s[4], s[5], s[6])
		end
	end
	-- 금연구역 표지 (국민건강증진법: 모든 음식점 · 주점 실내 전체 금연)
	do
		local wn, u, yc = nil, nil, 5.4
		for _, band in { { 4.5, 6.3 }, { 6.1, 7.9 }, { 2.4, 4.2 } } do
			wn, u = findWall(K, { "left", "right", "back" }, 1.3, 1.3, band[1], band[2], V3(0, 0, V.z1 - 4), 0.8)
			if wn and u then
				yc = (band[1] + band[2]) / 2
				break
			end
		end
		if wn and u then
			local d = V:wall(wn, u, yc, 0.06)
			K:plate("NoSmokeBoard", 1.2, 1.6, 0.03, d, L.of(250, 250, 248))
			K:plate("NoSmokeBand", 1.2, 0.36, 0.035, d * CF(0, -0.62, 0), L.of(200, 30, 36))
			local ic = d * CF(0, 0.22, 0.035)
			K:ring("NoSmokeRing", ic, 0.36, 0.08, if K.detail == "low" then 8 else 12, L.of(210, 30, 36))
			K:box("NoSmokeCig", V3(0.5, 0.1, 0.02), ic * CF(-0.04, 0, 0.0), L.of(240, 240, 236))
			K:box("NoSmokeTip", V3(0.12, 0.1, 0.022), ic * CF(0.25, 0, 0.0), L.of(230, 150, 60))
			K:box("NoSmokeSlash", V3(0.78, 0.08, 0.025), ic * CF(0, 0, 0.012) * ANG(0, 0, -PI / 4), L.of(210, 30, 36))
			K:text("NoSmokeText", 1.1, 0.3, d * CF(0, -0.28, 0.035), "금연구역", { fg = rgb(200, 30, 36), font = F.GothamBlack, d = 0.004 })
			K:text("NoSmokeFine", 1.1, 0.28, d * CF(0, -0.62, 0.037), "전 구역 금연 · 위반 시\n과태료 10만원", { fg = rgb(255, 255, 255), font = F.GothamBold, d = 0.004 })
		end
	end
	-- 원산지 표시판 (안주 파는 펍: 카운터 근처, 법정 표시)
	do
		local wn, u = findWall(K, { "back", "left", "right" }, 1.6, 1.6, 3.9, 5.5, nearC, 0.8)
		if wn and u then
			signPlate(K, V:wall(wn, u, 4.7, 0.06), 1.5, 1.4, "원산지 표시\n닭고기(윙) 국내산\n돼지고기(소시지) 국내산\n감자 미국산 · 오징어 국내산\n쌀 · 김치 국내산", rgb(30, 30, 30), rgb(250, 250, 246), rgb(40, 110, 60), F.GothamMedium)
		end
	end
	local _ = np
end

-- 15b) 벽 조명 (황동 브래킷 + 유리 갓 + 에디슨 전구; 불빛 예산 대신 빛나는 전구로)
local function sconces(c: any)
	local K, V, th = c.K, c.V, c.th
	if not budget(K, 30) then
		return
	end
	for _, wn in { "left", "right" } do
		local w = V.walls[wn]
		local n = 0
		local u = w.a + 3.0
		while u < w.b - 2.0 and n < 3 do
			local ok = false
			for _, sp in freeSpans(K, wn, 6.3, 7.5, 0.8) do
				if u - 0.4 > sp[1] and u + 0.4 < sp[2] then
					ok = true
				end
			end
			local p = V:wall(wn, u, 0, 1.0).Position
			if ok and p.Z < V.z1 - 2.2 then
				claim(K, wn, u - 0.6, u + 0.6, 6.3, 7.5)
				local d = V:wall(wn, u, 6.9, 0.05)
				K:plate("SconcePlate", 0.22, 0.36, 0.05, d, th.trim)
				K:bar("SconceArm", (d * CF(0, 0, 0.04)).Position, (d * CF(0, 0.12, 0.42)).Position, 0.05, 0.05, th.trim)
				K:vcyl("SconceCup", 0.12, 0.16, d * CF(0, 0.16, 0.44), th.trim)
				K:ell("SconceBulb", V3(0.2, 0.28, 0.2), d * CF(0, 0.34, 0.44), L.lampWarm)
				K:vcyl("SconceShade", 0.36, 0.42, d * CF(0, 0.42, 0.44), { c = rgb(240, 214, 170), m = M.Glass, t = 0.45 })
				n += 1
				u += 6.0
			else
				u += 1.0
			end
		end
	end
end

-- 15c) 높은 선반 (천장 아래 빈 벽 띠): 크래프트 펍은 캔 · 그라울러 · 탭 핸들 · 식스팩 컬렉션,
--      칵테일 바는 빈 술병 · 셰이커, 스포츠 펍은 캔 · 트로피. 선반 앞 아래 은은한 LED (네온 파트, 불빛 예산 안 씀)
local function growler(K: any, base: CFrame, gc: Color3, lab: Color3, capL: any, detail: string)
	local gl = { c = gc, m = M.Glass, t = 0.08, r = 0.12 }
	K:vcyl("Growler", 0.44, 0.46, base * CF(0, 0.22, 0), gl)
	K:ell("GrowlerShoulder", V3(0.46, 0.36, 0.46), base * CF(0, 0.44, 0), gl)
	K:vcyl("GrowlerNeck", 0.16, 0.15, base * CF(0, 0.66, 0), gl)
	K:vcyl("GrowlerCap", 0.08, 0.18, base * CF(0, 0.77, 0), capL)
	K:box("GrowlerLabel", V3(0.27, 0.2, 0.02), base * CF(0, 0.24, 0.226), { c = lab, m = M.SmoothPlastic })
	if detail ~= "low" then
		K:ring("GrowlerHandle", base * CF(0.2, 0.5, 0), 0.09, 0.05, 3, gl, -PI / 2, PI / 2)
	end
end

local function standHandle(K: any, base: CFrame, col: Color3, txt: string?, detail: string)
	K:vcyl("HandleStand", 0.05, 0.24, base * CF(0, 0.025, 0), L.blackMetal)
	K:vcyl("HandleFerrule", 0.14, 0.11, base * CF(0, 0.12, 0), L.chrome)
	K:box("HandleBody", V3(0.2, 0.7, 0.13), base * CF(0, 0.54, 0), { c = col, m = M.SmoothPlastic })
	K:box("HandleCap", V3(0.22, 0.04, 0.15), base * CF(0, 0.91, 0), L.black)
	if txt and detail == "high" then
		K:text("HandleLabel", 0.16, 0.4, base * CF(0, 0.56, 0.066), txt, { fg = if col.R + col.G + col.B > 1.8 then rgb(30, 30, 30) else rgb(250, 250, 246), font = F.GothamBlack, d = 0.004 })
	end
end

local function sixPack(K: any, base: CFrame, col: Color3, gc: Color3, detail: string)
	K:box("SixPack", V3(0.64, 0.34, 0.42), base * CF(0, 0.17, 0), { c = col, m = M.SmoothPlastic })
	K:box("SixPackHandle", V3(0.07, 0.26, 0.4), base * CF(0, 0.47, 0), { c = col, m = M.SmoothPlastic })
	K:box("SixPackBand", V3(0.645, 0.1, 0.425), base * CF(0, 0.22, 0), L.of(30, 30, 32))
	for _, x in { -0.2, 0.2 } do
		for _, z in { -0.1, 0.1 } do
			if detail ~= "low" or z > 0 then
				K:vcyl("SixPackNeck", 0.28, 0.09, base * CF(x, 0.48, z), { c = gc, m = M.Glass, t = 0.08 })
				K:vcyl("SixPackCap", 0.03, 0.1, base * CF(x, 0.635, z), L.goldMetal)
			end
		end
	end
end

local function trophy(K: any, base: CFrame, detail: string)
	K:box("TrophyBase", V3(0.32, 0.14, 0.3), base * CF(0, 0.07, 0), L.of(28, 26, 26))
	K:box("TrophyPlate", V3(0.22, 0.07, 0.01), base * CF(0, 0.07, 0.152), L.goldMetal)
	K:vcyl("TrophyStem", 0.2, 0.07, base * CF(0, 0.24, 0), L.goldMetal)
	K:ell("TrophyCup", V3(0.34, 0.32, 0.34), base * CF(0, 0.46, 0), L.goldMetal)
	K:vcyl("TrophyRim", 0.04, 0.35, base * CF(0, 0.58, 0), L.goldMetal)
	if detail ~= "low" then
		for _, sx in { -1, 1 } do
			K:ring("TrophyHandle", base * CF(sx * 0.19, 0.48, 0) * ANG(0, 0, 0), 0.07, 0.035, 3, L.goldMetal, if sx > 0 then -PI / 2 else PI / 2, if sx > 0 then PI / 2 else PI * 1.5)
		end
	end
end

local function shaker(K: any, base: CFrame)
	K:vcyl("Shaker", 0.42, 0.2, base * CF(0, 0.21, 0), L.chrome)
	K:vcyl("ShakerTop", 0.14, 0.16, base * CF(0, 0.49, 0), L.chrome)
	K:vcyl("ShakerCap", 0.06, 0.09, base * CF(0, 0.59, 0), L.chrome)
end

local CAN_COLS = {
	rgb(232, 120, 30), rgb(40, 150, 170), rgb(222, 196, 60), rgb(196, 40, 52), rgb(60, 120, 70), rgb(240, 236, 226),
	rgb(36, 50, 110), rgb(150, 70, 160), rgb(250, 160, 170), rgb(28, 28, 30), rgb(120, 190, 90), rgb(250, 210, 120),
}
local HANDLE_TXT = { "IPA", "LAGER", "STOUT", "SOUR", "PILS", "APA", "PORTER", "WEISS", "DIPA", "GOSE", "RED", "SAISON" }

local function highLedge(c: any)
	local K, V, th = c.K, c.V, c.th
	if V.H < 9.3 or not budget(K, 140) then
		return
	end
	local mode = if th.key == "fuzzy" or th.key == "party" then "cocktail" elseif th.key == "sunset" or th.key == "bat" then "sports" else "craft"
	local PAT = {
		craft = { "growler", "can", "can", "can", "handle", "handle", "handle", "can", "can", "sixpack", "can", "can", "handle", "handle", "can", "can", "can" },
		cocktail = { "bottle", "bottle", "bottle", "shaker", "bottle", "bottle", "bottle", "bottle", "shaker", "bottle", "bottle" },
		sports = { "can", "can", "can", "trophy", "can", "can", "growler", "can", "can", "trophy", "can", "can", "can", "sixpack" },
	}
	local WID = { can = 0.31, growler = 0.62, handle = 0.33, sixpack = 0.76, bottle = 0.4, shaker = 0.32, trophy = 0.44 }
	local pat = PAT[mode]
	local dep = 0.56
	local maxN = if V.W > 30 then 4 else 2
	local placed = 0
	local seed = c.seed
	local detail = K.detail
	local ledC = th.shelfLED or rgb(255, 190, 120)
	local idx = seed % #pat
	-- 첫 단: 선반 8.05 (포스터 위) · 둘째 단: 그 아래에 다른 벽 물건이 있으면 8.5 (천장 바로 아래)
	for _, lv in { { 8.05, 7.56 }, { 8.5, 7.98 } } do
		local yS, yBand = lv[1], lv[2]
		if yS + 1.3 > V.H then
			continue
		end
		for _, wn in { "left", "right", "back" } do
			if placed >= maxN then
				break
			end
			-- 덕트 끝이 닿는 자리는 비움
			local excl = nil
			if c.duct and wn ~= "back" then
				local du = V:wallCoord(wn, V3(if wn == "left" then V.x0 else V.x1, 0, c.duct.z))
				excl = { du - 0.9, du + 0.9 }
			end
			local spans = {}
			for _, sp in freeSpans(K, wn, yBand, math.min(V.H - 0.3, yS + 1.15), 0.8) do
				if excl and sp[1] < excl[2] and sp[2] > excl[1] then
					table.insert(spans, { sp[1], excl[1] })
					table.insert(spans, { excl[2], sp[2] })
				else
					table.insert(spans, sp)
				end
			end
			table.sort(spans, function(a, b)
				return (a[2] - a[1]) > (b[2] - b[1])
			end)
			for _, sp in spans do
				if placed >= maxN or not budget(K, 90) then
					break
				end
				local len = math.min(sp[2] - sp[1] - 0.5, if V.W > 30 then 9.5 else 7.0)
				if len < 2.6 then
					continue
				end
				local u = (sp[1] + sp[2]) / 2
				local dcf = V:wall(wn, u, yS, 0.02)
				local mn, mx = laabb(dcf * CF(0, 0.35, dep / 2), V3(len, 1.8, dep))
				if K:hitsKeep(mn, mx) then
					continue
				end
				claim(K, wn, u - len / 2 - 0.2, u + len / 2 + 0.2, yBand - 0.2, V.H)
				placed += 1
				local top = Props.shelf(K, dcf, len, { depth = dep, look = th.mid, bracket = L.blackMetal, thick = 0.12 })
				if detail ~= "low" then
					K:box("LedgeLip", V3(len, 0.05, 0.04), dcf * CF(0, 0.08, dep - 0.02), th.trim)
					K:box("LedgeLED", V3(len - 0.4, 0.025, 0.04), dcf * CF(0, -0.075, dep - 0.08), L.neon(ledC))
				end
				-- 물건 채우기 (가운데 정렬)
				local items = {}
				local used = 0
				local guard = 0
				while guard < 80 do
					guard += 1
					idx += 1
					local kind = pat[(idx % #pat) + 1]
					local w = WID[kind]
					if used + w > len - 0.3 then
						break
					end
					table.insert(items, { kind, used + w / 2 })
					used += w
				end
				local x0 = -used / 2
				for i, it in items do
					local kind, xm = it[1], it[2]
					local r1 = rnd(seed, idx * 7 + i)
					local pc = top * CF(x0 + xm, 0, -0.02 + (r1 - 0.5) * 0.06)
					local col = CAN_COLS[(math.floor(r1 * 97) + i) % #CAN_COLS + 1]
					if kind == "can" then
						beerCan(K, pc * ANG(0, (r1 - 0.5) * 0.8, 0), col, if r1 > 0.5 then rgb(250, 250, 246) else rgb(24, 24, 26), detail)
					elseif kind == "growler" then
						growler(K, pc * ANG(0, -0.3, 0), if r1 > 0.6 then rgb(40, 34, 30) else rgb(110, 60, 24), LABELS[(i + seed) % #LABELS + 1], if r1 > 0.5 then L.black else L.goldMetal, detail)
					elseif kind == "handle" then
						standHandle(K, pc, col, HANDLE_TXT[(math.floor(r1 * 53) + i) % #HANDLE_TXT + 1], detail)
					elseif kind == "sixpack" then
						sixPack(K, pc, if r1 > 0.5 then rgb(170, 128, 84) else col, rgb(110, 60, 24), detail)
					elseif kind == "trophy" then
						trophy(K, pc, detail)
					elseif kind == "shaker" then
						shaker(K, pc)
					else
						local mix = th.bottleMix or { "round", "square", "wine" }
						bottle(K, pc, 0.78 + r1 * 0.22, mix[(i + seed) % #mix + 1], GLASS[(i * 3 + seed) % #GLASS + 1], LABELS[i % #LABELS + 1], L.goldMetal, detail)
					end
				end
			end
		end
	end
end

-- 16) 주크박스 (벽걸이 디지털 주크박스, 곡 바꾸기) --------------------------------------------------------------
local function jukebox(c: any)
	local K, V, th = c.K, c.V, c.th
	if c.dart and c.neonOK then
		-- 다트 + 네온이 있으면 충분
	end
	local function okAt(wn: string, uu: number, _w: number): boolean
		return promptOK(K, (V:wall(wn, uu, 4.6, 0.4)).Position) and reachable(K, wn, uu)
	end
	local wn, u = findWall(K, { "right", "left", "back" }, 1.9, 1.9, 3.6, 6.4, V3(V.x1, 0, 0), 0.8, okAt)
	if not wn or not u then
		K:note("jukebox: no spot")
		return
	end
	local d = V:wall(wn, u, 5.0, 0.06)
	local body = L.of(24, 24, 28)
	K:panel("JukeBody", 1.5, 2.6, 0.36, 0.26, d, body)
	K:panel("JukeTrim", 1.6, 2.7, 0.3, 0.3, d, L.with(th.trim, {}))
	local glow = K:plate("JukeArch", 1.24, 0.1, 0.38, d * CF(0, 1.14, 0), L.neon(th.neonC))
	local _, lab = K:text("JukeScreen", 1.2, 0.95, d * CF(0, 0.44, 0.38), "", { fg = rgb(255, 255, 255), bg = rgb(16, 20, 40), glow = 1.3, d = 0.02, font = F.GothamBold })
	K:box("JukeSpeaker", V3(1.1, 0.5, 0.02), d * CF(0, -0.68, 0.37), L.of(44, 44, 48, M.Fabric))
	local btn = K:plate("JukeButton", 0.8, 0.26, 0.06, d * CF(0, -0.2, 0.36), L.of(200, 40, 60))
	K:text("JukeButtonText", 0.72, 0.18, d * CF(0, -0.2, 0.42), "SELECT ▶", { fg = rgb(255, 255, 255), d = 0.005, font = F.GothamBlack })
	K:text("JukeBrand", 1.1, 0.16, d * CF(0, 1.0, 0.37), "DIGITAL JUKEBOX", { fg = th.neonC, glow = 1.4, d = 0.005, font = F.GothamBlack })
	local songs = {
		{ "♪ NOW PLAYING", "광안리 밤바다", "City Pop · 3:52" },
		{ "♪ NOW PLAYING", "Summer Wave", "Indie Rock · 4:10" },
		{ "♪ NOW PLAYING", "해운대 연가", "K-Ballad · 4:31" },
		{ "♪ NOW PLAYING", "Friday Night Lights", "Disco · 3:28" },
		{ "♪ NOW PLAYING", "Busan Blues", "Jazz · 5:02" },
	}
	local function show(s: any)
		lab.Text = s[1] .. "\n" .. s[2] .. "\n" .. s[3]
	end
	show(songs[1])
	Interact.cycle(K, btn, songs, {
		action = "다음 곡",
		object = "주크박스",
		on = function(_i: number, s: any)
			show(s)
		end,
	})
	local gc = glow.Color
	Interact.anim(K, function(t: number)
		if glow.Parent then
			glow.Color = gc:Lerp(rgb(255, 255, 255), 0.25 + 0.25 * math.sin(t * 2))
		end
	end)
end

-- 16b) 위스키 배럴 스탠딩 테이블 (넓게 빈 바닥에만, 통로 · 문 · 다트 길 피함) ------------------------------------------
local function barrelTable(K: any, pcf: CFrame, th: any)
	local oak = wood(118, 76, 44)
	local hoop = L.of(36, 36, 38, M.Metal)
	K:vcyl("BarrelBody", 2.9, 1.86, pcf * CF(0, 1.45, 0), oak)
	K:vcyl("BarrelBelly", 1.5, 1.98, pcf * CF(0, 1.45, 0), oak)
	for _, y in { 0.3, 0.95, 1.95, 2.6 } do
		K:vcyl("BarrelHoop", 0.12, (if y == 0.95 or y == 1.95 then 2.02 else 1.9), pcf * CF(0, y, 0), hoop)
	end
	if K.detail == "high" then
		for k = 0, 7 do
			local a = k * PI / 4
			K:box("BarrelStave", V3(0.03, 2.84, 0.04), pcf * CF(math.cos(a) * 0.94, 1.45, math.sin(a) * 0.94) * ANG(0, -a, 0), dim(oak, 0.35))
		end
	end
	K:disc("BarrelTop", 2.5, 0.12, pcf * CF(0, 2.96, 0), wood(140, 94, 56))
	K:disc("BarrelTopEdge", 2.54, 0.05, pcf * CF(0, 2.89, 0), dim(wood(140, 94, 56), 0.3))
	K:text("BarrelBrand", 0.9, 0.36, pcf * CF(0, 1.5, 0.995), th.brand, { fg = rgb(40, 24, 14), d = 0.005, font = F.Oswald })
end

local function barrels(c: any)
	local K, V, th = c.K, c.V, c.th
	if not budget(K, 40) or th.key == "fuzzy" or th.key == "party" then
		return
	end
	local cands = {}
	local x = V.x0 + 2.5
	while x <= V.x1 - 2.5 do
		local z = V.z0 + 2.5
		while z <= V.z1 - 3.0 do
			table.insert(cands, V3(x, 0, z))
			z += 1.0
		end
		x += 1.0
	end
	-- 뒤쪽 (TV · 탭 보드 가까이) 부터
	local tvp = if c.tv then V:wall(c.tv.wall, c.tv.u, 0, 3.5).Position else V3(0, 0, V.z0)
	table.sort(cands, function(a, b)
		return (a - tvp).Magnitude < (b - tvp).Magnitude
	end)
	local n = 0
	local maxN = if V.W * V.D > 600 then 2 else 1
	for _, p in cands do
		if n >= maxN then
			break
		end
		local nearSeat = false
		for _, list in { V.stools, V.chairs } do
			for _, st in list do
				local d = st.seat.c - p
				if V3(d.X, 0, d.Z).Magnitude < 3.0 then
					nearSeat = true
				end
			end
		end
		if not behindCounter(V, p) and not nearSeat then
			local pcf = CF(p)
			local mn, mx = laabb(pcf * CF(0, 1.6, 0), V3(4.6, 3.2, 4.6))
			if mapClear(V, mn, mx) and K:spot(pcf, V3(2.6, 3.1, 2.6), 1.3, "barrel") then
				barrelTable(K, pcf, th)
				n += 1
			end
		end
	end
end

-- 17) 화분 (앞 모서리) ------------------------------------------------------------------------------------
local function plants(c: any)
	local K, V, th = c.K, c.V, c.th
	local kinds = th.plants or { "monstera" }
	local spots = { V3(V.x0 + 1.1, 0, V.z1 - 1.3), V3(V.x1 - 1.1, 0, V.z1 - 1.3), V3(V.x0 + 1.1, 0, V.z1 - 3.6), V3(V.x1 - 1.1, 0, V.z1 - 3.6) }
	local n = 0
	for i, p in spots do
		if n >= 2 then
			break
		end
		local h = math.clamp(V.H * 0.5, 4, 5.4)
		local pcf = CF(p)
		local kind = kinds[(i + c.seed) % #kinds + 1]
		local spread = if kind == "monstera" then 6.2 elseif kind == "snake" then 1.4 else 2.6
		local mn, mx = laabb(pcf * CF(0, h / 2, 0), V3(1.8, h, 1.8))
		if mapClear(V, mn, mx) and clearAt(K, pcf * CF(0, h * 0.62, 0), V3(spread, h * 0.7, spread)) and K:spot(pcf, V3(1.8, h, 1.8), 0.1, "plant") then
			Props.floorPlant(K, pcf, { kind = kind, h = h, dia = 1.4, pot = L.of(52, 50, 48, M.Concrete) })
			n += 1
		end
	end
end

-- 스타일 ------------------------------------------------------------------------------------------------
function T.style(V: any): any
	local th = pickTheme(V)
	return {
		chair = false, -- 벤치 소파 · 의자는 T.build 가 직접 (소파를 의자 3개로 바꾸지 않게)
		stool = th.stool,
		table = { top = th.tableTop, base = L.blackMetal, thick = 0.2, r = 0.08 },
		counter = { front = th.counterFront, frontL = th.counterFrontL, topL = th.counterTop, kickL = L.black, led = th.led },
		ceiling = { skin = th.ceil },
		floor = th.floor,
		lower = th.lower,
		base = dim(th.dark, 0.2),
		pendant = th.pendant,
		clock = false,
		license = false,
		cctv = true,
		mat = { look = L.of(44, 36, 30, M.Fabric), text = th.mat },
		lights = { kind = "none" },
		plants = th.plants,
		pubTheme = th,
	}
end

function T.build(K: any, V: any, S: any)
	local th = S.pubTheme or pickTheme(V)
	local c = {
		K = K,
		V = V,
		S = S,
		th = th,
		seed = hash(tostring(V.key or V.name or "pub")),
		neon = { parts = {}, labels = {}, lights = {} },
		usedChairs = {},
	}
	local steps = {
		{ "banquette", banquettes },
		{ "chairs", chairsOver },
		{ "backbar", backBar },
		{ "backtop", backTop },
		{ "shelfbar", shelfBar },
		{ "tap", tapTower },
		{ "rail", footRail },
		{ "upper", upperWalls },
		{ "tv", tvSet },
		{ "board", tapBoard },
		{ "dart", dartMachine },
		{ "tanks", tanks },
		{ "neon", neonFeature },
		{ "jukebox", jukebox },
		{ "kegs", kegs },
		{ "food", foodBoard },
		{ "pendants", tablePendants },
		{ "ducts", ducts },
		{ "festoon", festoon },
		{ "glassrack", glassRack },
		{ "disco", disco },
		{ "counter", counterProps },
		{ "decor", wallDecor },
		{ "sconces", sconces },
		{ "ledge", highLedge },
		{ "plants", plants },
		{ "barrels", barrels },
	}
	local counts = {}
	local n0 = #K.parts
	for _, st in steps do
		local before = #K.parts
		local ok, err = pcall(st[2], c)
		if not ok then
			K:note("pub." .. st[1] .. " error: " .. tostring(err))
		end
		if #K.parts - before > 0 then
			table.insert(counts, st[1] .. "=" .. tostring(#K.parts - before))
		end
	end
	K:note("pub parts +" .. tostring(#K.parts - n0) .. " (" .. table.concat(counts, " ") .. ")")
end

return T
