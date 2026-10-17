--!strict
-- GwangalliBuildingInterior/T_korean: 유형 (soup noodle katsu chinese) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (테마별 바닥 · 징두리 · 천장 · 스툴 · 카운터)
--   build(K, V, S) 유형별 디테일. 테마 = 가게 이름 · 메뉴로 고름:
--     gukbap (부산 돼지국밥) · haejang (해장국) · bok (복국) · milmyeon (밀면) · kalguksu (칼국수) · ramen (하카타 라멘)
--     katsu (돈카츠) · chinese (중식 반점) · bistro (파스타 · 와인: 지도에서 soup 로 분류된 가게)
--   공통 구성:
--     좌석 리스킨 (의자 · 둥근 스툴 · 평상 방석: 같은 자리 · 같은 높이), 테이블 · 교자상 (같은 윗면), 수저통 (SpoonBox 자리)
--     좌식 평상 (마루 · 테두리목 · 걸레받이 · 신발) · 주방 패스 (타일 · 선반 뚝배기 · 국자 · 김 · 스테인리스 테 · 노렌 글자)
--     메뉴판 (나무 간판 / 라이트박스 / 칠판, 2026 부산 가격) · 원산지 표시판 · 영업시간 · 결제 (동백전) · 와이파이 · 금연
--     셀프 반찬바 (반찬 냉장 · 앞접시 · 집게 · 컵 소독기) · 소주 · 맥주 냉장고 (유리문) · 육수 솥 (가스 화구 · 김)
--     계산대 (카운터 없는 가게) · 벽걸이 TV (롯데 야구) · 벽걸이 선풍기 · 달력 · 음식 포스터 · 방송 출연 액자
--     라멘: 원목 카운터 · 위 선반 양념 · 후드 · 나무 메뉴패 · 붉은 등 · 식권 발매기 / 밀면: 제면기 / 칼국수: 반죽대
--     복국: 복어 수족관 / 중식: 홍등 · 복(福) · 금색 고양이
--   상호작용 (이 클라이언트만): TV 채널 · 선풍기 켜기 · 냉장고 문 · 육수 불 · 등 켜기 — 주문 · 계산 · 앉기와 겹치지 않음

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))

local T = {}
T.types = { "soup", "noodle", "katsu", "chinese" }

local L = Look
local M = Enum.Material
local F = Enum.Font
local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local rgb = Color3.fromRGB
local WHITE = rgb(255, 255, 255)

-- 공용 도우미 ------------------------------------------------------------------------------------------
local function wood(r: number, g: number, b: number): any
	return L.of(r, g, b, M.Wood)
end

local function col(c: Color3, m: Enum.Material?, extra: any?): any
	local t: any = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
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

-- GwShop 의 Table_n 모델 안 파트인가 (국밥 알바: 테이블 · 좌석 · TrayPoint 는 절대 숨기지 않음)
local function inTableModel(p: Instance): boolean
	local a = p.Parent
	while a and a ~= workspace do
		if a:IsA("Model") and string.match(a.Name, "^Table_%d+") then
			return true
		end
		a = a.Parent
	end
	return false
end

local function budget(K: any, n: number): boolean
	return #K.parts + n < K.maxParts * 0.94
end

-- 표시면(dcf) 앞을 보는 원판: dcf 의 +Z 쪽 z..z+t
local function wdisc(K: any, name: string, dia: number, t: number, dcf: CFrame, z: number, look: any): BasePart
	return K:make("Part", name, V3(t, dia, dia), dcf * CF(0, 0, z + t / 2) * ANG(0, PI / 2, 0), look, Enum.PartType.Cylinder)
end

-- 글자판: 배경색은 글자 라벨 배경 대신 판 파트 색으로 (조명 아래에서도 색이 정확), 글자만 라벨
local function ktext(K: any, name: string, w: number, h: number, dcf: CFrame, text: string, o: any?): (BasePart, TextLabel)
	local op: any = table.clone(o or {})
	if op.bg and not op.look then
		op.look = { c = op.bg, m = M.SmoothPlastic, free = op.free }
		op.bg = nil
	end
	return K:text(name, w, h, dcf, text, op)
end

-- 글자 세로 쓰기 ("돼지국밥" -> "돼\n지\n국\n밥")
local function vertical(s: string): string
	local out = {}
	for _, cp in utf8.codes(s) do
		local ch = utf8.char(cp)
		if ch ~= " " then
			table.insert(out, ch)
		end
	end
	return table.concat(out, "\n")
end

local function charCount(s: string): number
	local n = 0
	for _ in utf8.codes(s) do
		n += 1
	end
	return n
end

-- 벽 자리 관리 (Common.wallSpot 와 같은 K.wallUsed) ---------------------------------------------------------
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

-- walls 순서대로 폭 minW..maxW 가 들어가는 빈 구간 중 near 에 가까운 자리. 반환 wn, u, w (claim 함)
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
				local lo = s[1] + 0.1 + w / 2
				local hi = math.max(lo, s[2] - 0.1 - w / 2)
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

-- 맵 파트(쉘 · 포인트 제외)와 안 겹치나
local function mapClear(V: any, mn: Vector3, mx: Vector3): boolean
	for _, r in V.parts do
		if not r.shell and not r.point and overlap(mn, mx, r.min, r.max) then
			return false
		end
	end
	return true
end

-- 벽에 붙여 세우는 바닥 소품 자리 (K:spot 예약). 반환 pcf (+Z = 방 안쪽), wn, u
local function floorOnWall(K: any, walls: { string }, size: Vector3, near: Vector3?, pad: number?, test: any?, gap: number?): (CFrame?, string?, number?)
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
			local pcf = V:wall(wn, cu, 0, size.Z / 2 + (gap or 0.14))
			local mn, mx = laabb(pcf * CF(0, size.Y / 2, 0), size + V3(0.2, 0, 0.2))
			if mapClear(V, mn, mx) and not usedHit(K, wn, cu - size.X / 2, cu + size.X / 2, 0, size.Y) and (not test or test(pcf, wn, cu)) and K:spot(pcf, size, pad or 0.1, "korean") then
				claim(K, wn, cu - size.X / 2 - 0.15, cu + size.X / 2 + 0.15, 0, size.Y + 0.2)
				return pcf, wn, cu
			end
		end
	end
	return nil, nil, nil
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
		end
	end
	for _, k in V.keep do
		if k.kind == "staff" and p.X > k.min.X - 0.6 and p.X < k.max.X + 0.6 and p.Z > k.min.Z - 0.6 and p.Z < k.max.Z + 0.6 then
			return true
		end
	end
	return false
end

-- 작은 소품: keep 에 걸리면 아예 안 만듦 (blocked 수를 늘리지 않게)
local function clearAt(K: any, cf: CFrame, size: Vector3): boolean
	local mn, mx = laabb(cf, size)
	return K:hitsKeep(mn, mx) == nil
end

local function promptOK(K: any, lp: Vector3): boolean
	return Interact.canPrompt(K, lp)
end

-- 벽 위 프롬프트 자리 (u 좌우 m 까지 모두 서버 앵커에서 충분히 먼가)
local function promptWallOK(K: any, wn: string, u: number, y: number, m: number?): boolean
	local V = K.V
	local mm = m or 0.6
	for _, du in { -mm, 0, mm } do
		if not Interact.canPrompt(K, V:wall(wn, u + du, y, 0.4).Position) then
			return false
		end
	end
	return true
end

-- 배치 기록 (로그)
local function at(K: any, what: string, wn: string?, u: number?, p: Vector3?)
	if p then
		K:note(string.format("%s @ %.1f,%.1f,%.1f", what, p.X, p.Y, p.Z))
	else
		K:note(string.format("%s @ %s u=%.1f", what, tostring(wn), u or 0))
	end
end

-- 테마 --------------------------------------------------------------------------------------------------
local SOUP_FEAT = { pot = true, selfbar = true, fridge = true, tv = true, fan = true, cash = true, calendar = true }

local BASE_THEME: any = {
	kind = "soup",
	title = "돼지국밥",
	sub = "부산 정통",
	noren = { "돼지", "국밥" },
	norenC = rgb(30, 40, 70),
	norenFg = rgb(246, 242, 232),
	menuStyle = "wood",
	menuTitle = "메    뉴",
	menu = {},
	origin = {},
	hours = { "영업시간", "매일 06:00 - 22:00", "연중무휴" },
	broth = rgb(232, 224, 204),
	bowl = rgb(58, 38, 30), -- 뚝배기
	toppings = { "meat", "onion" },
	feat = SOUP_FEAT,
	chairs = { { style = "diner", frame = L.chrome, seat = L.leatherBlack } },
	stool = { style = "bar", frame = L.chrome, seat = L.leatherRed },
	table = { top = wood(180, 132, 88), edge = wood(120, 84, 54), base = L.blackMetal, style = "pedestal" },
	lowTop = wood(150, 96, 58),
	cushion = { rgb(150, 36, 40), rgb(46, 70, 120), rgb(170, 120, 40) },
	maru = L.of(196, 150, 102, M.WoodPlanks),
	maruFrame = wood(120, 80, 50),
	counter = { front = "wood", frontL = wood(150, 104, 66), topL = wood(190, 150, 104), led = false },
	floor = { look = L.of(150, 146, 140, M.Slate), tile = 2.0, grout = L.of(120, 116, 112) },
	lower = { kind = "wainscot", h = 3.4, look = wood(168, 120, 78), cap = wood(112, 78, 50), panel = 1.9, walls = { "left", "right", "back" } },
	base = wood(96, 66, 44),
	ceiling = { grid = true },
	lights = { kind = "none" },
	passTile = L.of(232, 232, 226, M.CeramicTiles),
	fridgeHeader = "시원한 소주 · 맥주",
	posters = {},
	tagsOn = false,
	tags = {},
	wifi = "GUKBAP_5G",
	pay = "카드 · 제로페이 · 동백전 결제 가능",
	selfSign = "셀프코너",
	selfSub = "반찬 · 물은 셀프입니다\n먹을 만큼만 담아주세요",
	mat = "어서오세요",
}

local THEMES: { [string]: any } = {}

THEMES.gukbap = extend(BASE_THEME, {
	title = "돼지국밥",
	sub = "24시간 고아낸 사골 육수",
	noren = { "돼지", "국밥" },
	menu = {
		{ "돼지국밥", "10,000" }, { "순대국밥", "10,000" }, { "섞어국밥", "10,500" }, { "내장국밥", "10,000" },
		{ "따로국밥", "11,000" }, { "수육백반", "13,000" }, { "수육 (소)", "22,000" }, { "수육 (대)", "30,000" },
		{ "모둠순대", "12,000" }, { "공기밥", "1,000" }, { "소주 · 맥주", "5,000" }, { "음료수", "2,000" },
	},
	origin = { "돼지고기 (국밥 · 수육) : 국내산", "쌀 : 국내산", "배추김치 (배추 · 고춧가루) : 국내산", "깍두기 (무) : 국내산", "순대 (돼지 창자) : 국내산", "새우젓 : 국내산", "부추 : 국내산" },
	hours = { "영업시간", "24시간 영업", "연중무휴" },
	broth = rgb(236, 228, 210),
	posters = {
		{ title = "부산 정통 돼지국밥", sub = "24시간 끓여낸 진한 사골 육수", bg = rgb(46, 30, 22), fg = rgb(255, 236, 200), acc = rgb(230, 70, 40) },
		{ title = "수육백반", sub = "부드러운 앞다리 수육 + 국밥 한 그릇", bg = rgb(120, 30, 26), fg = rgb(255, 244, 220), acc = rgb(255, 210, 90), kind = "suyuk" },
	},
	wifi = "DWAEJI_GUKBAP_5G",
	chairs = {
		{ style = "diner", frame = L.chrome, seat = L.leatherBlack },
		{ style = "bentwood", frame = L.walnut, seat = wood(150, 100, 62) },
	},
})

THEMES.haejang = extend(THEMES.gukbap, {
	title = "해장국",
	sub = "새벽을 여는 뜨끈한 한 그릇",
	noren = { "해장", "국" },
	norenC = rgb(120, 26, 24),
	menuStyle = "light",
	menu = {
		{ "선지해장국", "10,000" }, { "뼈해장국", "11,000" }, { "우거지해장국", "10,000" }, { "콩나물국밥", "9,000" },
		{ "소고기국밥", "11,000" }, { "내장탕", "12,000" }, { "수육 (중)", "25,000" }, { "계란말이", "9,000" },
		{ "공기밥", "1,000" }, { "소주 · 맥주", "5,000" },
	},
	origin = { "소 선지 · 양 : 국내산 (한우)", "돼지 등뼈 : 덴마크산", "쌀 : 국내산", "배추김치 : 국내산", "콩나물 · 우거지 : 국내산", "고춧가루 : 국내산" },
	hours = { "영업시간", "새벽 05:00 - 밤 10:00", "매주 월요일 휴무" },
	broth = rgb(150, 58, 30),
	toppings = { "seonji", "onion" },
	photoKinds = { "seonji", "bone", "seonji", "haejang", "gukbap" },
	posters = {
		{ title = "선지해장국", sub = "한우 선지 · 우거지 듬뿍", bg = rgb(110, 24, 20), fg = rgb(255, 240, 220), acc = rgb(255, 200, 80), kind = "seonji" },
		{ title = "속풀이 뼈해장국", sub = "푹 고아 살이 쏙쏙", bg = rgb(40, 28, 22), fg = rgb(255, 236, 200), acc = rgb(230, 80, 40), kind = "bone" },
	},
	chairs = { { style = "diner", frame = L.chrome, seat = L.leatherRed }, { style = "diner", frame = L.chrome, seat = L.leatherBlack } },
	lower = { kind = "tile", h = 3.4, look = L.of(236, 236, 230, M.CeramicTiles), grout = L.of(196, 196, 190), tw = 1.0, th = 0.5, walls = { "left", "right", "back" } },
	base = L.of(70, 72, 74, M.SmoothPlastic),
	wifi = "HAEJANG_FREE",
})

THEMES.bok = extend(THEMES.gukbap, {
	title = "복국",
	sub = "민락동 시원한 맑은 복국",
	noren = { "복", "국" },
	norenC = rgb(24, 52, 86),
	menuStyle = "wood",
	menu = {
		{ "밀복국", "14,000" }, { "은복국", "17,000" }, { "까치복국", "22,000" }, { "참복국", "33,000" },
		{ "복 매운탕", "+1,000" }, { "복불고기 (2인)", "40,000" }, { "복튀김", "25,000" }, { "복껍질무침", "15,000" },
		{ "공기밥", "1,000" }, { "소주 · 맥주", "5,000" },
	},
	origin = { "밀복 · 은복 · 까치복 : 국내산", "참복 : 국내산 (양식)", "콩나물 · 미나리 : 국내산", "쌀 : 국내산", "배추김치 : 국내산", "고춧가루 : 국내산" },
	hours = { "영업시간", "07:00 - 21:30", "브레이크타임 15:30 - 16:30" },
	broth = rgb(226, 220, 196),
	toppings = { "bok", "minari" },
	feat = extend(SOUP_FEAT, { tank = true }),
	posters = {
		{ title = "맑은 복국", sub = "콩나물 · 미나리 듬뿍, 시원한 해장", bg = rgb(26, 52, 80), fg = rgb(240, 248, 255), acc = rgb(120, 210, 240), kind = "bok" },
		{ title = "복불고기", sub = "매콤달콤 2인 이상 주문", bg = rgb(130, 32, 26), fg = rgb(255, 244, 220), acc = rgb(255, 210, 90), kind = "bulgogi" },
	},
	chairs = { { style = "bentwood", frame = wood(170, 130, 90), seat = wood(196, 160, 118) } },
	table = { top = wood(206, 174, 132), edge = wood(150, 112, 76), base = L.blackMetal, style = "pedestal" },
	lower = { kind = "wainscot", h = 3.4, look = wood(206, 176, 136), cap = wood(150, 112, 76), panel = 2.2, walls = { "left", "right", "back" } },
	base = wood(150, 112, 76),
	wifi = "MINRAK_BOK",
})

THEMES.milmyeon = extend(THEMES.gukbap, {
	kind = "noodle",
	title = "밀면",
	sub = "1952 피란 시절부터 부산의 맛",
	noren = { "밀", "면" },
	norenC = rgb(22, 70, 120),
	menuStyle = "light",
	menu = {
		{ "물밀면", "9,500" }, { "비빔밀면", "10,000" }, { "곱빼기", "+1,500" }, { "온면 (겨울)", "9,500" },
		{ "왕만두 (6개)", "7,000" }, { "고기만두", "6,000" }, { "수육 (소)", "18,000" }, { "음료수", "2,000" },
	},
	origin = { "밀가루 : 미국산 · 호주산", "소고기 (육수) : 호주산", "돼지고기 (수육) : 국내산", "배추김치 : 국내산", "무 : 국내산", "고춧가루 : 국내산" },
	hours = { "영업시간", "10:30 - 21:00", "재료 소진 시 조기 마감" },
	broth = rgb(170, 120, 70),
	bowl = rgb(200, 204, 210), -- 스테인리스 대접
	toppings = { "milmyeon" },
	photoKinds = { "milmyeon", "bibim", "milmyeon", "milmyeon", "milmyeon" },
	feat = { selfbar = true, fridge = true, tv = true, fan = true, cash = true, press = true, calendar = true },
	posters = {
		{ title = "살얼음 물밀면", sub = "한약재 사골 육수 + 쫄깃한 면", bg = rgb(20, 70, 120), fg = rgb(240, 250, 255), acc = rgb(140, 220, 255), kind = "milmyeon" },
		{ title = "비빔밀면", sub = "새콤달콤 매콤 비법 양념", bg = rgb(170, 36, 30), fg = rgb(255, 246, 230), acc = rgb(255, 214, 90), kind = "bibim" },
	},
	chairs = {
		{ style = "diner", frame = L.chrome, seat = L.of(40, 90, 160, M.Leather) },
		{ style = "diner", frame = L.chrome, seat = L.of(236, 238, 240, M.Leather) },
		{ style = "padded", frame = L.chrome, seat = L.of(24, 60, 110, M.Leather) },
	},
	table = { top = L.of(236, 236, 230, M.SmoothPlastic), edge = L.steel, base = L.chrome, style = "pedestal" },
	upper = L.of(246, 247, 245, M.Plaster), -- 밀면집: 하얗고 시원한 벽
	onyuksu = true,
	lower = { kind = "tile", h = 3.4, look = L.of(226, 236, 244, M.CeramicTiles), grout = L.of(190, 200, 208), tw = 1.0, th = 0.5, walls = { "left", "right", "back" } },
	base = L.of(60, 90, 130),
	fridgeHeader = "시원한 음료 · 소주 · 맥주",
	wifi = "MILMYEON_5G",
})

THEMES.kalguksu = extend(THEMES.gukbap, {
	kind = "noodle",
	title = "해물칼국수",
	sub = "매일 직접 밀어 써는 손칼국수",
	noren = { "칼국", "수" },
	norenC = rgb(80, 52, 30),
	menuStyle = "wood",
	menu = {
		{ "해물칼국수", "11,000" }, { "바지락칼국수", "10,000" }, { "들깨칼국수", "11,000" }, { "손수제비", "10,000" },
		{ "칼제비", "10,500" }, { "해물파전", "16,000" }, { "미니 보리밥", "3,000" }, { "공기밥", "1,000" },
		{ "소주 · 맥주", "5,000" }, { "막걸리", "5,000" },
	},
	origin = { "바지락 : 국내산", "오징어 : 국내산", "새우 : 베트남산", "밀가루 : 미국산 · 호주산", "배추김치 (겉절이) : 국내산", "쌀 · 보리 : 국내산" },
	hours = { "영업시간", "10:00 - 21:00", "매주 화요일 휴무" },
	broth = rgb(214, 200, 168),
	toppings = { "clam", "zucchini" },
	photoKinds = { "kal", "kal", "kal", "kal", "kal" },
	feat = { selfbar = true, fridge = true, tv = true, fan = true, cash = true, dough = true, calendar = true },
	posters = {
		{ title = "해물칼국수", sub = "바지락 · 새우 · 오징어 듬뿍", bg = rgb(36, 60, 70), fg = rgb(240, 248, 250), acc = rgb(255, 200, 90), kind = "kal" },
		{ title = "해물파전", sub = "비 오는 날엔 막걸리 한 잔", bg = rgb(120, 70, 30), fg = rgb(255, 246, 226), acc = rgb(255, 220, 120), kind = "pajeon" },
	},
	chairs = { { style = "bentwood", frame = L.walnut, seat = wood(150, 100, 62) } },
	wifi = "KALGUKSU_5G",
})

THEMES.ramen = extend(BASE_THEME, {
	kind = "noodle",
	title = "하카타 라멘",
	sub = "18시간 우린 돈코츠 육수",
	noren = { "하카타", "라멘" },
	norenC = rgb(22, 22, 24),
	norenFg = rgb(246, 242, 232),
	menuStyle = "black",
	menuTitle = "MENU  메뉴",
	menu = {
		{ "돈코츠 라멘", "11,000" }, { "카라이 (매운) 라멘", "12,000" }, { "쇼유 라멘", "11,500" }, { "츠케멘", "13,000" },
		{ "차슈동", "8,000" }, { "교자 (5pc)", "6,000" }, { "아지타마고", "2,000" }, { "차슈 추가", "3,500" },
		{ "카에다마 (면 추가)", "2,000" }, { "생맥주 500", "6,000" },
	},
	origin = { "돼지고기 (차슈 · 육수) : 국내산", "밀가루 (면) : 미국산 · 호주산", "계란 : 국내산", "쌀 : 국내산", "김 : 국내산", "대파 : 국내산" },
	hours = { "영업시간", "11:30 - 21:30", "브레이크타임 15:00 - 17:00" },
	broth = rgb(238, 226, 200),
	bowl = rgb(24, 22, 22),
	toppings = { "ramen" },
	feat = { fridge = true, lanterns = true, ticket = true, tags = true, cat = true, bgm = true },
	posters = {
		{ title = "돈코츠 라멘", sub = "진하고 부드러운 하카타식 백탕", bg = rgb(24, 22, 22), fg = rgb(250, 244, 230), acc = rgb(220, 40, 30), kind = "ramen" },
		{ title = "차슈 듬뿍", sub = "토치로 그을린 수제 차슈", bg = rgb(150, 26, 22), fg = rgb(255, 246, 230), acc = rgb(255, 214, 120), kind = "chashu" },
	},
	chairs = { { style = "bentwood", frame = wood(60, 40, 28), seat = wood(170, 130, 88) } },
	stool = { style = "wood", frame = wood(70, 46, 30), seat = wood(196, 156, 108) },
	table = { top = wood(196, 156, 108), edge = wood(90, 60, 40), base = L.blackMetal, style = "pedestal" },
	counter = { front = "wood", frontL = wood(84, 56, 36), topL = L.of(226, 196, 150, M.Wood), kickL = L.black, led = rgb(255, 200, 140) },
	floor = { look = L.of(112, 106, 98, M.Slate), tile = 2.0, grout = L.of(78, 74, 70) },
	lower = { kind = "louver", h = 3.8, look = wood(176, 134, 90), back = L.of(60, 44, 32), pitch = 0.5, walls = { "left", "right", "back" } },
	base = L.of(30, 26, 22),
	ceiling = { skin = L.of(226, 216, 198, M.WoodPlanks) },
	lights = { kind = "downlight", n = 6, color = rgb(255, 214, 170), glow = L.lampWarm },
	passTile = L.of(214, 210, 200, M.CeramicTiles),
	upper = L.of(222, 206, 176, M.Plaster), -- 토벽 느낌 모래색 회벽 (나무 루버 · 검은 테와 대비)
	fridgeHeader = "BEER · SAKE · 음료",
	tagsOn = true,
	tags = { { "돈코츠", "11,000" }, { "카라이", "12,000" }, { "쇼유", "11,500" }, { "츠케멘", "13,000" }, { "차슈동", "8,000" }, { "교자", "6,000" }, { "아지타마", "2,000" }, { "카에다마", "2,000" }, { "생맥주", "6,000" }, { "하이볼", "7,000" } },
	wifi = "HAKATA_RAMEN",
	mat = "いらっしゃいませ",
})

THEMES.katsu = extend(BASE_THEME, {
	kind = "katsu",
	title = "돈카츠",
	sub = "두툼한 숙성 등심 · 바삭한 생빵가루",
	noren = { "돈카", "츠" },
	norenC = rgb(26, 40, 64),
	menuStyle = "wood",
	menu = {
		{ "로스카츠 (등심)", "13,000" }, { "히레카츠 (안심)", "14,000" }, { "치즈카츠", "14,500" }, { "왕돈까스", "12,000" },
		{ "카츠동", "11,000" }, { "카레 돈카츠", "13,500" }, { "냉모밀", "9,000" }, { "모밀 세트", "16,000" },
		{ "생맥주 500", "6,000" }, { "음료수", "2,000" },
	},
	origin = { "돼지고기 (등심 · 안심) : 국내산", "쌀 : 국내산", "양배추 : 국내산", "치즈 : 미국산", "메밀 : 중국산", "배추김치 : 국내산" },
	hours = { "영업시간", "11:00 - 21:00", "브레이크타임 15:00 - 16:30" },
	broth = rgb(196, 140, 70),
	bowl = rgb(240, 238, 232),
	toppings = { "katsu" },
	feat = { fridge = true, selfbar = true, cash = true, lanterns = false, tags = true, calendar = true, bgm = true },
	posters = {
		{ title = "로스카츠", sub = "저온 숙성 국내산 등심 180g", bg = rgb(36, 30, 26), fg = rgb(255, 244, 222), acc = rgb(240, 170, 60), kind = "katsu" },
		{ title = "치즈카츠", sub = "모짜렐라가 주욱", bg = rgb(170, 110, 30), fg = rgb(255, 250, 236), acc = rgb(255, 240, 160), kind = "katsu" },
	},
	chairs = { { style = "bentwood", frame = L.oak, seat = L.oak } },
	table = { top = wood(214, 186, 148), edge = wood(160, 124, 86), base = L.blackMetal, style = "pedestal" },
	lower = { kind = "louver", h = 3.6, look = wood(200, 166, 120), back = L.of(230, 224, 212), pitch = 0.5, walls = { "left", "right", "back" } },
	base = wood(150, 116, 80),
	selfSign = "셀프바",
	selfSub = "양배추 · 장국 · 단무지는 셀프입니다",
	upper = L.of(238, 232, 220, M.Plaster),
	banchan = { { "buchu", rgb(196, 226, 160) }, { "onion", rgb(246, 214, 60) }, { "ssamjang", rgb(110, 60, 30) }, { "kimchi", rgb(200, 70, 40) }, { "buchu", rgb(220, 236, 196) }, { "garlic", rgb(250, 248, 240) } },
	fridgeHeader = "생맥주 · 음료",
	tagsOn = true,
	tags = { { "로스카츠", "13,000" }, { "히레카츠", "14,000" }, { "치즈카츠", "14,500" }, { "카츠동", "11,000" }, { "냉모밀", "9,000" }, { "생맥주", "6,000" } },
	wifi = "TONKATSU_5G",
})

THEMES.chinese = extend(BASE_THEME, {
	kind = "chinese",
	title = "중화요리",
	sub = "수타면 · 불맛 가득 웍 요리",
	noren = { "中華", "料理" },
	norenC = rgb(160, 24, 24),
	norenFg = rgb(255, 214, 110),
	menuStyle = "red",
	menuTitle = "차림표",
	menu = {
		{ "짜장면", "7,500" }, { "간짜장", "9,000" }, { "짬뽕", "9,500" }, { "차돌짬뽕", "12,000" },
		{ "볶음밥", "9,000" }, { "잡채밥", "10,000" }, { "탕수육 (소)", "19,000" }, { "탕수육 (중)", "26,000" },
		{ "군만두", "7,000" }, { "깐풍기", "30,000" }, { "유린기", "28,000" }, { "고량주 (소)", "9,000" },
	},
	origin = { "돼지고기 : 국내산", "오징어 : 원양산", "홍합 : 국내산", "밀가루 : 미국산", "배추김치 : 중국산", "쌀 : 국내산" },
	hours = { "영업시간", "11:00 - 21:00", "배달 · 포장 가능" },
	broth = rgb(170, 40, 24),
	bowl = rgb(236, 232, 224),
	toppings = { "jjamppong" },
	photoKinds = { "jjamppong", "jjamppong", "jjamppong", "jjamppong", "tangsuyuk" },
	feat = { fridge = true, tv = true, cash = true, lanterns = true, cat = true, calendar = true, fan = true, fu = true },
	posters = {
		{ title = "불맛 짬뽕", sub = "해물 듬뿍 · 직접 볶은 고추기름", bg = rgb(150, 20, 20), fg = rgb(255, 236, 190), acc = rgb(255, 200, 60), kind = "jjamppong" },
		{ title = "찹쌀 탕수육", sub = "부먹 · 찍먹 선택하세요", bg = rgb(40, 24, 18), fg = rgb(255, 236, 200), acc = rgb(255, 170, 60), kind = "tangsuyuk" },
	},
	chairs = { { style = "bentwood", frame = wood(70, 30, 24), seat = L.leatherRed } },
	table = { top = wood(120, 50, 36), edge = wood(80, 30, 24), base = L.blackMetal, style = "pedestal" },
	lower = { kind = "wainscot", h = 3.4, look = L.of(140, 26, 26), cap = L.of(196, 160, 80, M.Metal), panel = 1.8, walls = { "left", "right", "back" } },
	base = L.of(60, 20, 20),
	floor = { look = L.of(196, 190, 180, M.Granite), tile = 2.0, grout = L.of(150, 146, 140) },
	wifi = "CHINA_5G",
})

THEMES.bistro = extend(BASE_THEME, {
	kind = "bistro",
	title = "PASTA & WINE",
	sub = "바다 곁 작은 이탈리안 비스트로",
	noren = { "CUCINA", "VINO" },
	norenC = rgb(40, 56, 44),
	menuStyle = "chalk",
	menuTitle = "TODAY'S MENU",
	menu = {
		{ "알리오 올리오", "16,000" }, { "봉골레", "19,000" }, { "까르보나라", "18,000" }, { "로제 쉬림프", "19,000" },
		{ "라구 볼로네제", "19,000" }, { "마르게리타 피자", "18,000" }, { "리코타 샐러드", "15,000" }, { "트러플 감자튀김", "12,000" },
		{ "하우스 와인 (글라스)", "9,000" }, { "하우스 와인 (보틀)", "39,000" }, { "하이볼", "9,000" }, { "에이드", "6,500" },
	},
	origin = { "바지락 : 국내산", "새우 : 베트남산", "쇠고기 (라구) : 호주산", "돼지고기 (베이컨) : 스페인산", "쌀 : 국내산", "밀 (파스타) : 이탈리아산" },
	hours = { "OPEN", "11:30 - 22:00", "LAST ORDER 21:00" },
	broth = rgb(236, 210, 150),
	bowl = rgb(244, 242, 236),
	toppings = { "pasta" },
	feat = { bistro = true, calendar = false, bgm = true },
	posters = {
		{ title = "VONGOLE", sub = "광안리 바지락 듬뿍 봉골레", bg = rgb(32, 44, 38), fg = rgb(246, 240, 226), acc = rgb(230, 190, 110), kind = "pasta" },
		{ title = "VINO", sub = "오늘의 하우스 와인 글라스 9,000원", bg = rgb(90, 20, 34), fg = rgb(255, 240, 230), acc = rgb(240, 200, 140), kind = "wine" },
	},
	chairs = { { style = "bentwood", frame = L.walnut, seat = L.leatherBrown } },
	table = { top = wood(120, 84, 56), edge = wood(80, 56, 38), base = L.blackMetal, style = "pedestal" },
	counter = { front = "wood", frontL = wood(90, 62, 42), topL = L.marbleWhite, led = rgb(255, 196, 130) },
	floor = { look = L.of(150, 108, 76, M.WoodPlanks), tile = 0 },
	lower = { kind = "paint", h = 3.6, look = L.of(46, 64, 52), cap = L.brass, walls = { "left", "right" } },
	base = wood(70, 48, 32),
	ceiling = { skin = L.of(112, 84, 60, M.WoodPlanks) },
	pendant = { shade = "dome", look = L.of(40, 56, 44, M.Metal) },
	lights = { kind = "none" },
	wifi = "BADAGYEOT_GUEST",
	mat = "WELCOME",
})

local function themeKey(V: any): string
	local n = tostring(V.name or "")
	local m = tostring(V.menu or "")
	local function has(list: { string }): boolean
		for _, w in list do
			if string.find(n, w, 1, true) then
				return true
			end
		end
		return false
	end
	if has({ "파스타", "와인", "PASTA", "WINE", "비스트로", "BISTRO", "트라토리아" }) then
		return "bistro"
	end
	if m == "haejang" or has({ "해장" }) then
		return "haejang"
	end
	if m == "bok" or has({ "복국", "복어" }) then
		return "bok"
	end
	if m == "milmyeon" or has({ "밀면", "냉면" }) then
		return "milmyeon"
	end
	if m == "kalguksu" or has({ "칼국수", "수제비" }) then
		return "kalguksu"
	end
	if m == "ramen" or has({ "라멘", "RAMEN", "ラーメン" }) then
		return "ramen"
	end
	if V.type == "katsu" or m == "katsu" or has({ "카츠", "돈까스", "돈가스", "KATSU" }) then
		return "katsu"
	end
	if V.type == "chinese" or m == "chinese" or has({ "반점", "짜장", "짬뽕", "중화", "중식", "홍콩", "차이나", "마라", "각" }) and V.type == "chinese" then
		return "chinese"
	end
	if has({ "반점", "짜장", "짬뽕", "중화요리" }) then
		return "chinese"
	end
	if m == "gukbap" or has({ "국밥", "순대", "곰탕", "설렁탕" }) then
		return "gukbap"
	end
	if V.type == "noodle" then
		return "kalguksu"
	end
	return "gukbap"
end

local function themeFor(V: any): any
	local key = themeKey(V)
	local th = table.clone(THEMES[key] or THEMES.gukbap)
	th.key = key
	-- 가게 이름이 테마 제목과 다르면 메뉴판 · 노렌 부제에 씀
	th.shop = tostring(V.name or th.title)
	local seed = hash(tostring(V.key or V.name or key))
	th.seed = seed
	th.chair = th.chairs[(seed % #th.chairs) + 1]
	-- 가게마다 다르게 (같은 맵 틀을 쓰는 가게가 많음): 바닥 · 징두리 · 메뉴판 · 쿠션 색 순서
	local v1, v2, v3 = (seed // 7) % 3, (seed // 31) % 3, (seed // 101) % 2
	if th.kind == "soup" or th.kind == "noodle" and key ~= "ramen" then
		local ALL = { "left", "right", "back" }
		local floors = {
			th.floor,
			{ look = L.of(204, 196, 182, M.CeramicTiles), tile = 2.0, grout = L.of(170, 162, 150) },
			{ look = L.of(196, 192, 184, M.Granite), tile = 0 },
		}
		th.floor = floors[v1 + 1]
		-- 아랫벽 변형은 가게 종류 정체성 안에서만 (밀면 = 하늘 · 흰 · 민트 타일, 해장국 = 흰 타일 · 짙은 나무, 국밥 = 나무 · 흰 타일)
		local lowers: { any }
		if key == "milmyeon" then
			lowers = {
				th.lower,
				{ kind = "tile", h = 3.4, look = L.of(240, 242, 240, M.CeramicTiles), grout = L.of(150, 176, 200), tw = 1.0, th = 0.5, walls = ALL },
				{ kind = "tile", h = 3.4, look = L.of(206, 234, 226, M.CeramicTiles), grout = L.of(170, 200, 192), tw = 0.5, th = 0.5, walls = ALL },
			}
		elseif key == "kalguksu" or key == "bok" then
			lowers = {
				th.lower,
				{ kind = "wainscot", h = 3.4, look = wood(190, 156, 112), cap = wood(130, 96, 62), panel = 2.0, walls = ALL },
				{ kind = "tile", h = 3.4, look = L.of(232, 228, 214, M.CeramicTiles), grout = L.of(190, 184, 170), tw = 1.0, th = 0.5, walls = ALL },
			}
		else
			lowers = {
				th.lower,
				{ kind = "tile", h = 3.4, look = L.of(236, 236, 230, M.CeramicTiles), grout = L.of(196, 196, 190), tw = 1.0, th = 0.5, walls = ALL },
				{ kind = "wainscot", h = 3.4, look = wood(150, 104, 66), cap = wood(100, 68, 44), panel = 1.9, walls = ALL },
			}
		end
		th.lower = lowers[v2 + 1]
		if v3 == 1 and key ~= "milmyeon" and (th.menuStyle == "wood" or th.menuStyle == "light") then
			th.menuStyle = if th.menuStyle == "wood" then "light" else "wood"
		end
	end
	if v3 == 1 then
		local cs = table.clone(th.cushion)
		table.insert(cs, table.remove(cs, 1))
		th.cushion = cs
	end
	th.fridgeLeft = (seed // 13) % 2 == 0
	return th
end

-- GwShop 의 맵 메뉴 글자 (서버 · 알바 일과 같은 값) 를 읽어 사진 메뉴 가격을 맞춤: "돼지국밥\n9,500원" 꼴
local GW_MENU_FALLBACK = { { "돼지국밥", "9,500" }, { "순대국밥", "10,000" }, { "섞어국밥", "10,500" }, { "수육백반", "14,000" } }
local function gwMenu(V: any): { any }
	local out, seen = {}, {}
	local model: Instance? = V.model
	if model then
		local n = 0
		for _, d in model:GetDescendants() do
			n += 1
			if n > 8000 or #out >= 6 then
				break
			end
			if d:IsA("TextLabel") then
				local txt = tostring(d.Text)
				local name, price = string.match(txt, "^%s*([^\n%d]-)%s*\n%s*([%d,]+)%s*원")
				if name and price and #name >= 6 and not seen[name] then
					seen[name] = true
					table.insert(out, { name, price })
				end
			end
		end
	end
	if #out >= 3 then
		return out
	end
	return GW_MENU_FALLBACK
end

function T.style(V: any): any
	local th = themeFor(V)
	if V.kind == "gwshop" then
		th.menu = gwMenu(V)
	end
	local S: any = {
		chair = false, -- 좌석은 build 에서 (방석 · 둥근 스툴 구분)
		table = false, -- 테이블 · 교자상도 build 에서
		stool = th.stool,
		counter = th.counter,
		ceiling = th.ceiling,
		floor = th.floor,
		lower = th.lower,
		base = th.base,
		pendant = th.pendant,
		clock = false, -- 시계는 build 에서 (메뉴판 자리를 먼저 잡음)
		mat = { text = th.mat },
		lights = th.lights,
		plants = { "snake", "ficus", "olive" },
	}
	if V.kind == "gwshop" then
		S.lights = { kind = "none" }
		-- GwShop: 바닥 · 징두리는 이미 있음 (마감 · 장식만, R14)
		S.floor = nil
		S.lower = false
		S.ceiling = { grid = true } -- 텍스 그리드 마감 (얇은 오버레이, R5 · R14)
		S.mat = false
	end
	S.__theme = th
	return S
end

-- 좌석 -------------------------------------------------------------------------------------------------
local function chairFrame(ch: any): CFrame
	local s = ch.seat
	local f: Vector3 = ch.face
	local p = V3(s.c.X, 0, s.c.Z)
	return CFrame.lookAt(p, p - f)
end

-- 방석 (평상 위 Cushion): 같은 자리 · 같은 윗면
local function cushionOver(c: any, ch: any, i: number)
	local K, th = c.K, c.th
	local s = ch.seat
	local w, d = s.size.X, s.size.Z
	local top, base = s.max.Y, s.min.Y
	local h = math.max(0.12, top - base)
	local cc: Color3 = th.cushion[((i + c.seed) % #th.cushion) + 1]
	local fab = col(cc, M.Fabric)
	local pipe = col(cc:Lerp(Color3.fromRGB(255, 220, 140), 0.45), M.Fabric)
	K:free(function()
		K:slab("Bangseok", w - 0.06, d - 0.06, h * 0.7, 0.24, CF(s.c.X, base + h * 0.35, s.c.Z), fab)
		K:ell("BangseokPuff", V3(w - 0.3, h * 0.6, d - 0.3), CF(s.c.X, top - h * 0.3, s.c.Z), fab)
		K:slab("BangseokPipe", w - 0.02, d - 0.02, 0.04, 0.26, CF(s.c.X, base + h * 0.7, s.c.Z), pipe)
		if c.hi then
			K:disc("BangseokTuft", 0.16, 0.03, CF(s.c.X, top - 0.01, s.c.Z), col(cc:Lerp(Color3.new(0, 0, 0), 0.35), M.Fabric))
			for _, a in { 0, PI / 2, PI, PI * 1.5 } do
				K:disc("BangseokTassel", 0.1, 0.03, CF(s.c.X + math.cos(a) * (w / 2 - 0.08), base + h * 0.7, s.c.Z + math.sin(a) * (d / 2 - 0.08)), pipe)
			end
		end
	end)
end

local function seatsOver(c: any)
	local K, V, th = c.K, c.V, c.th
	local n = #V.chairs
	local detail = K.detail
	if n * 30 > K.maxParts * 0.4 then
		detail = if n * 22 > K.maxParts * 0.4 then "low" else "mid"
	end
	for i, ch in V.chairs do
		local s = ch.seat
		if s.part:IsA("Seat") and s.part.Transparency >= 0.99 then
			continue
		end
		local isCushion = s.name == "Cushion" or s.name == "SeatCushion"
		local stoolish = false
		for _, r in ch.parts do
			if r.name == "StoolLeg" or r.name == "StoolPost" or r.name == "StoolBase" then
				stoolish = true
			end
		end
		if isCushion then
			cushionOver(c, ch, i)
			K:reserve(V3(s.min.X - 0.1, s.min.Y, s.min.Z - 0.1), V3(s.max.X + 0.1, ch.top + 0.4, s.max.Z + 0.1), "cushion")
		elseif stoolish and not ch.back then
			local o = table.clone(th.stool or {})
			o.seatTop = ch.top
			o.dia = math.clamp(math.max(s.size.X, s.size.Z), 0.9, 1.6)
			if ch.top < 2.3 and o.style ~= "wood" then
				o.style = "bar"
			end
			K:free(function()
				Props.stool(K, CF(s.c.X, 0, s.c.Z), o)
			end)
			for _, q in V.byName.StoolRing or {} do
				if math.abs(q.c.X - s.c.X) < 0.8 and math.abs(q.c.Z - s.c.Z) < 0.8 then
					hideRec(K, q)
				end
			end
			K:reserve(V3(s.min.X - 0.2, 0, s.min.Z - 0.2), V3(s.max.X + 0.2, ch.top + 0.5, s.max.Z + 0.2), "stool")
		else
			local w = math.max(1.1, math.min(2.2, math.min(s.size.X, s.size.Z) + 0.05))
			local backH = 1.8
			if ch.back then
				backH = math.clamp(ch.back.max.Y - ch.top, 1.0, 3.2)
			end
			local o = table.clone(th.chair or {})
			o.seatTop = ch.top
			o.w = w
			o.d = w
			o.backH = backH
			o.detail = if detail == "high" then o.detail else detail
			K:free(function()
				Props.chair(K, chairFrame(ch), o)
			end)
			K:reserve(V3(s.min.X - 0.3, 0, s.min.Z - 0.3), V3(s.max.X + 0.3, ch.top + backH, s.max.Z + 0.3), "chair")
		end
		for _, r in ch.parts do
			hideRec(K, r)
		end
	end
end

-- 테이블 -----------------------------------------------------------------------------------------------
-- 교자상 (평상 위 낮은 상): 같은 윗면 · 같은 범위, 접이식 다리
local function lowTableOver(c: any, t: any)
	local K, th = c.K, c.th
	local mn, mx = t.min, t.max
	local y = t.y
	local w, l = mx.X - mn.X, mx.Z - mn.Z
	local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
	local fy = y - 1.05
	for _, r in t.parts do
		if r.name == "LowTableLeg" then
			fy = math.min(fy, r.min.Y)
		end
	end
	fy = math.max(0, fy)
	local topL = th.lowTop or wood(150, 96, 58)
	local edgeL = dim(topL, 0.35)
	local legL = dim(topL, 0.45)
	local alongX = w >= l
	K:free(function()
		K:slab("GyojaTop", w, l, 0.12, 0.1, CF(cx, y - 0.06, cz), topL)
		K:slab("GyojaEdge", w - 0.04, l - 0.04, 0.05, 0.1, CF(cx, y - 0.145, cz), edgeL)
		local ay = y - 0.27
		K:box("GyojaApron", V3(w - 0.5, 0.2, 0.06), CF(cx, ay, mn.Z + 0.25), edgeL)
		K:box("GyojaApron", V3(w - 0.5, 0.2, 0.06), CF(cx, ay, mx.Z - 0.25), edgeL)
		K:box("GyojaApron", V3(0.06, 0.2, l - 0.5), CF(mn.X + 0.25, ay, cz), edgeL)
		K:box("GyojaApron", V3(0.06, 0.2, l - 0.5), CF(mx.X - 0.25, ay, cz), edgeL)
		local legH = y - 0.17 - fy
		-- 접이식 다리 프레임 (짧은 변 쪽 2벌)
		for _, s in { -1, 1 } do
			if alongX then
				local x = cx + s * (w / 2 - 0.45)
				for _, sz in { -1, 1 } do
					K:box("GyojaLeg", V3(0.14, legH, 0.14), CF(x, fy + legH / 2, cz + sz * (l / 2 - 0.35)), legL)
				end
				K:box("GyojaFoot", V3(0.12, 0.1, l - 0.6), CF(x, fy + 0.05, cz), legL)
			else
				local z = cz + s * (l / 2 - 0.45)
				for _, sx in { -1, 1 } do
					K:box("GyojaLeg", V3(0.14, legH, 0.14), CF(cx + sx * (w / 2 - 0.35), fy + legH / 2, z), legL)
				end
				K:box("GyojaFoot", V3(w - 0.6, 0.1, 0.12), CF(cx, fy + 0.05, z), legL)
			end
		end
	end)
end

-- 수저통 (SpoonBox 자리 · 크기 그대로): 스테인리스 통 + 뚜껑 + 손잡이
local function spoonBoxOver(c: any, r: any)
	local K = c.K
	local sx, sy, sz = r.size.X, r.size.Y, r.size.Z
	local base = CF(r.c.X, r.min.Y, r.c.Z)
	local alongX = sx >= sz
	local long, short = math.max(sx, sz), math.min(sx, sz)
	local rot = if alongX then CFrame.new() else ANG(0, PI / 2, 0)
	local b = base * rot
	K:free(function()
		K:box("SujeoBody", V3(long - 0.02, sy - 0.06, short - 0.02), b * CF(0, (sy - 0.06) / 2, 0), L.steel)
		K:box("SujeoLid", V3(long, 0.05, short), b * CF(0, sy - 0.035, 0), L.chrome)
		K:box("SujeoKnob", V3(0.18, 0.04, 0.06), b * CF(0, sy - 0.005 - 0.02, 0), L.black)
		if c.hi then
			K:box("SujeoSeam", V3(0.02, sy - 0.1, short), b * CF(0, (sy - 0.06) / 2, 0), L.brushed)
		end
	end)
end

local function tablesOver(c: any)
	local K, V, th = c.K, c.V, c.th
	for _, t in V.tables do
		if t.kind == "grill" then
			continue
		end
		if t.kind == "low" then
			lowTableOver(c, t)
		else
			local o = table.clone(th.table or {})
			if t.kind == "bar" then
				o.style = "steel"
			end
			Props.tableOver(K, t, o)
		end
		for _, r in t.parts do
			hideRec(K, r)
		end
		-- 상판 바로 아래 TableEdge (GwShop) 도 같이
		for _, r in V.byName.TableEdge or {} do
			if r.c.X > t.min.X - 0.3 and r.c.X < t.max.X + 0.3 and r.c.Z > t.min.Z - 0.3 and r.c.Z < t.max.Z + 0.3 then
				hideRec(K, r)
			end
		end
		K:reserve(V3(t.min.X, 0, t.min.Z), V3(t.max.X, t.y + 0.2, t.max.Z), "table")
	end
	for _, r in V.byName.SpoonBox or {} do
		spoonBoxOver(c, r)
		hideRec(K, r)
	end
end

-- 좌식 평상 ----------------------------------------------------------------------------------------------
local function platformOver(c: any)
	local K, V, th = c.K, c.V, c.th
	local list = {}
	for _, nm in { "좌식평상", "Pyeongsang" } do
		for _, r in V.byName[nm] or {} do
			table.insert(list, r)
		end
	end
	for _, r in list do
		if inTableModel(r.part) then
			continue
		end
		local mn, mx = r.min, r.max
		-- 앞 모서리 (PyeongsangEdge) 를 같이 덮음
		for _, e in V.byName.PyeongsangEdge or {} do
			if e.max.Y <= mx.Y + 0.05 and math.abs(e.c.Z - r.c.Z) < 2 then
				mn = mn:Min(e.min)
				mx = mx:Max(e.max)
				hideRec(K, e)
			end
		end
		local top = mx.Y
		local W, D = mx.X - mn.X, mx.Z - mn.Z
		local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
		local fr = th.maruFrame
		local exp = {
			left = mn.X - V.x0 > 0.35,
			right = V.x1 - mx.X > 0.35,
			back = mn.Z - V.z0 > 0.35,
			front = V.z1 - mx.Z > 0.35,
		}
		K:free(function()
			-- 마루 판 (안쪽) + 테두리목 (같은 높이)
			local bw = 0.34
			K:box("MaruTop", V3(W - 2 * bw, 0.12, D - 2 * bw), CF(cx, top - 0.06, cz), th.maru)
			K:box("MaruRim", V3(W, 0.12, bw), CF(cx, top - 0.06, mn.Z + bw / 2), fr)
			K:box("MaruRim", V3(W, 0.12, bw), CF(cx, top - 0.06, mx.Z - bw / 2), fr)
			K:box("MaruRim", V3(bw, 0.12, D - 2 * bw), CF(mn.X + bw / 2, top - 0.06, cz), fr)
			K:box("MaruRim", V3(bw, 0.12, D - 2 * bw), CF(mx.X - bw / 2, top - 0.06, cz), fr)
			-- 몸통 (어두운 원목 판) + 들어간 걸레받이
			local kick = 0.28
			K:box("MaruBody", V3(W - 0.06, top - 0.12 - kick, D - 0.06), CF(cx, kick + (top - 0.12 - kick) / 2, cz), dim(fr, 0.15))
			K:box("MaruKick", V3(W - 0.3, kick, D - 0.3), CF(cx, kick / 2, cz), L.of(36, 28, 22))
			-- 노출된 면: 세로 띠 (판 이음) + 둥근 모서리
			local function face(axis: string, sgn: number)
				local len = if axis == "x" then D else W
				local n = math.max(2, math.floor(len / 1.8))
				for i = 1, n - 1 do
					local t = -len / 2 + len * i / n
					if axis == "x" then
						local x = if sgn < 0 then mn.X else mx.X
						K:box("MaruStile", V3(0.04, top - 0.12 - kick - 0.04, 0.12), CF(x + sgn * 0.02, kick + (top - 0.12 - kick) / 2, cz + t), dim(fr, 0.35))
					else
						local z = if sgn < 0 then mn.Z else mx.Z
						K:box("MaruStile", V3(0.12, top - 0.12 - kick - 0.04, 0.04), CF(cx + t, kick + (top - 0.12 - kick) / 2, z + sgn * 0.02), dim(fr, 0.35))
					end
				end
				if axis == "x" then
					local x = if sgn < 0 then mn.X + 0.07 else mx.X - 0.07
					K:cyl("MaruNosing", D, 0.14, CF(x, top - 0.07, cz) * ANG(0, PI / 2, 0), fr)
				else
					local z = if sgn < 0 then mn.Z + 0.07 else mx.Z - 0.07
					K:cyl("MaruNosing", W, 0.14, CF(cx, top - 0.07, z), fr)
				end
			end
			if exp.left then
				face("x", -1)
			end
			if exp.right then
				face("x", 1)
			end
			if exp.front then
				face("z", 1)
			end
			if exp.back then
				face("z", -1)
			end
		end)
		hideRec(K, r)
		-- 디딤판 (StepBoard): 화강석 댓돌 + 신발 몇 켤레
		for _, sb in V.byName.StepBoard or {} do
			K:free(function()
				K:box("StepStone", sb.size - V3(0.02, 0.02, 0.02), CF(sb.c), L.of(150, 146, 140, M.Granite))
				K:box("StepStoneTop", V3(sb.size.X - 0.06, 0.03, sb.size.Z - 0.06), CF(sb.c.X, sb.max.Y - 0.005, sb.c.Z), L.of(170, 166, 160, M.Granite))
			end)
			hideRec(K, sb)
		end
		-- 신발 (평상 앞 바닥, 통로 · keep 피해서)
		local function shoePair(p: Vector3, yaw: number, cl: Color3)
			local base = CF(p) * ANG(0, yaw, 0)
			for _, sx in { -0.17, 0.17 } do
				K:box("Shoe", V3(0.28, 0.18, 0.62), base * CF(sx, 0.09, 0), col(cl, M.Fabric))
				K:box("ShoeSole", V3(0.3, 0.05, 0.66), base * CF(sx, 0.025, 0), L.of(236, 236, 230, M.Rubber))
			end
		end
		local exSide = if exp.left then -1 elseif exp.right then 1 else 0
		if exSide ~= 0 then
			local x = if exSide < 0 then mn.X - 0.45 else mx.X + 0.45
			local zs = { cz - D * 0.25, cz + D * 0.2 }
			local shoeC = { rgb(40, 40, 44), rgb(200, 200, 196), rgb(120, 70, 40) }
			for i, z in zs do
				local sp = CF(x, 0, z)
				if K:spot(sp, V3(0.8, 0.25, 0.8), 0, "shoe") then
					shoePair(V3(x, 0.03, z), (if exSide < 0 then PI / 2 else -PI / 2) + (i - 1.5) * 0.3, shoeC[(i + c.seed) % 3 + 1])
				end
			end
		end
		-- 안내 (평상 옆면 앞쪽)
		c.platform = { mn = mn, mx = mx, top = top, exp = exp }
	end
end

-- 표지 · 글자판 도우미 ------------------------------------------------------------------------------------
local function signPlate(c: any, dcf: CFrame, w: number, h: number, text: string, fg: Color3, bg: Color3, o: any?)
	local K = c.K
	local opt: any = o or {}
	local z = 0
	if opt.border then
		K:plate("SignBorder", w + 0.1, h + 0.1, 0.03, dcf, col(opt.border))
		z = 0.03
	end
	local p, t = ktext(K, opt.name or "Sign", w, h, dcf * CF(0, 0, z), text, { fg = fg, bg = bg, font = opt.font or F.GothamBold, d = 0.03, glow = opt.glow or 0.85 })
	return p, t
end

-- 메뉴판 스타일
local MENU_STYLES: { [string]: any } = {
	wood = { frame = wood(66, 44, 30), face = L.of(212, 176, 128, M.WoodPlanks), title = rgb(110, 26, 22), fg = rgb(44, 28, 18), price = rgb(150, 30, 24), font = F.GothamBlack, rule = rgb(110, 76, 48) },
	light = { frame = L.of(200, 202, 206, M.Metal), face = L.of(250, 250, 246), title = WHITE, titleBg = rgb(196, 30, 36), fg = rgb(30, 30, 32), price = rgb(200, 28, 32), glow = 1.0, font = F.GothamBlack, rule = rgb(220, 220, 214) },
	black = { frame = wood(40, 28, 20), face = L.of(26, 24, 22), title = rgb(255, 206, 80), fg = rgb(246, 242, 232), price = rgb(255, 206, 80), glow = 1.1, font = F.GothamBlack, rule = rgb(90, 80, 60) },
	red = { frame = L.of(196, 160, 80, M.Metal, { r = 0.1 }), face = L.of(150, 22, 24), title = rgb(255, 220, 120), fg = rgb(255, 240, 214), price = rgb(255, 214, 90), glow = 1.0, font = F.GothamBlack, rule = rgb(200, 150, 70) },
	chalk = { frame = wood(96, 66, 42), face = L.of(42, 48, 44, M.Slate), title = rgb(250, 248, 240), fg = rgb(236, 234, 226), price = rgb(255, 214, 140), font = F.PermanentMarker, rule = rgb(150, 150, 140) },
}

local function menuBoard(c: any, dcf: CFrame, w: number, h: number, title: string, items: { any }, style: string, sub: string?)
	local K = c.K
	local st = MENU_STYLES[style] or MENU_STYLES.wood
	K:plate("MenuFrame", w + 0.26, h + 0.26, 0.14, dcf, st.frame)
	K:plate("MenuFace", w, h, 0.18, dcf, st.face)
	local z = 0.185
	local th = math.clamp(h * 0.2, 0.5, 0.95)
	if st.titleBg then
		K:plate("MenuTitleBand", w, th, 0.02, dcf * CF(0, h / 2 - th / 2, 0.18), col(st.titleBg))
		z = 0.205
	end
	ktext(K, "MenuTitle", w * 0.6, th * 0.8, dcf * CF(if sub then -w * 0.12 else 0, h / 2 - th / 2, z), title, { fg = st.title, glow = st.glow, font = st.font })
	if sub then
		ktext(K, "MenuSub", w * 0.3, th * 0.42, dcf * CF(w / 2 - w * 0.17, h / 2 - th / 2, z), sub, { fg = if st.titleBg then WHITE else st.fg, glow = st.glow, font = F.GothamMedium })
	end
	K:plate("MenuRule", w - 0.3, 0.035, 0.012, dcf * CF(0, h / 2 - th - 0.04, 0.18), col(st.rule))
	local n = #items
	local cols = if n > 12 and w > 9 then 3 elseif n > 5 and w > 3.4 then 2 else 1
	local rows = math.ceil(n / cols)
	local top = h / 2 - th - 0.12
	local avail = h - th - 0.24
	local rh = math.min(0.62, avail / rows)
	local cw = (w - 0.4) / cols
	local f = if style == "chalk" then F.PermanentMarker else F.GothamBold
	for i, it in items do
		local cI = (i - 1) // rows
		local row = (i - 1) % rows
		local x0 = -w / 2 + 0.2 + cI * cw
		local y = top - rh * (row + 0.5)
		ktext(K, "MenuItem", cw * 0.62, rh * 0.68, dcf * CF(x0 + cw * 0.32, y, z), it[1], { fg = st.fg, glow = st.glow, align = "Left", font = f })
		ktext(K, "MenuPrice", cw * 0.32, rh * 0.6, dcf * CF(x0 + cw * 0.81, y, z), it[2], { fg = st.price, glow = st.glow, align = "Right", font = f })
	end
	for i = 1, cols - 1 do
		K:plate("MenuColRule", 0.03, avail - 0.1, 0.012, dcf * CF(-w / 2 + 0.2 + cw * i, top - avail / 2 + 0.05, 0.18), col(st.rule))
	end
	if style == "wood" and c.hi then
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				wdisc(K, "MenuScrew", 0.1, 0.02, dcf * CF(sx * (w / 2 + 0.06), sy * (h / 2 + 0.06), 0), 0.14, L.brass)
			end
		end
	end
end

-- 원산지 표시판 (흰 아크릴 + 남색 머리띠 + 은색 테)
local function originBoard(c: any, dcf: CFrame, w: number, h: number)
	local K, th = c.K, c.th
	K:plate("OriginFrame", w + 0.12, h + 0.12, 0.05, dcf, L.alu)
	K:plate("OriginFace", w, h, 0.06, dcf, L.of(252, 252, 248))
	local hh = math.min(0.6, h * 0.18)
	ktext(K, "OriginTitle", w, hh, dcf * CF(0, h / 2 - hh / 2, 0.06), "원산지 표시", { fg = WHITE, bg = rgb(26, 50, 110), font = F.GothamBlack, d = 0.01, glow = 0.85 })
	ktext(K, "OriginBody", w - 0.2, h - hh - 0.25, dcf * CF(0, -hh / 2 - 0.05, 0.065), table.concat(th.origin, "\n"), { fg = rgb(30, 30, 34), bg = rgb(252, 252, 248), font = F.GothamMedium, align = "Left", glow = 0.85, d = 0.01 })
end

-- 음식 그림 (위에서 본 그릇) — 포스터 · 패스 · 메뉴 사진용
local function bowlArt(c: any, dcf: CFrame, dia: number, kind: string?, broth: Color3?, bowlC: Color3?, z0: number?)
	local K, th = c.K, c.th
	local z = z0 or 0
	local k = kind or th.key
	local alias: { [string]: string } = { kalguksu = "kal", chinese = "jjamppong", bistro = "pasta" }
	k = alias[k] or k
	local bc = bowlC or th.bowl
	local br = broth or th.broth
	wdisc(K, "ArtShadow", dia * 1.04, 0.01, dcf * CF(dia * 0.05, -dia * 0.05, 0), z, col(rgb(14, 10, 8)))
	wdisc(K, "ArtBowl", dia, 0.012, dcf, z + 0.01, col(bc))
	wdisc(K, "ArtBroth", dia * 0.8, 0.012, dcf, z + 0.022, col(br))
	local zt = z + 0.034
	local function bit(name: string, sx: number, sy: number, x: number, y: number, a: number, cl: Color3)
		K:ell(name, V3(dia * sx, dia * sy, 0.012), dcf * CF(dia * x, dia * y, zt + 0.006) * ANG(0, 0, a), col(cl))
	end
	local green = rgb(84, 150, 60)
	if k == "ramen" or k == "chashu" then
		bit("ArtChashu", 0.3, 0.26, -0.12, 0.08, 0.2, rgb(196, 140, 110))
		bit("ArtChashu", 0.28, 0.24, 0.02, 0.14, -0.3, rgb(186, 128, 100))
		bit("ArtEgg", 0.16, 0.12, 0.16, -0.08, 0.5, rgb(250, 200, 80))
		bit("ArtNori", 0.08, 0.3, 0.27, 0.12, 0.1, rgb(20, 30, 24))
		for i = 1, 6 do
			bit("ArtNegi", 0.05, 0.04, -0.2 + rnd(i, 3) * 0.3, -0.18 + rnd(i, 7) * 0.12, i, green)
		end
		bit("ArtBeni", 0.08, 0.06, -0.06, -0.2, 0, rgb(220, 50, 60))
	elseif k == "milmyeon" or k == "bibim" then
		bit("ArtNoodle", 0.5, 0.42, 0, 0, 0, rgb(200, 170, 120))
		if k == "bibim" then
			bit("ArtSauce", 0.3, 0.26, 0.02, 0.02, 0.4, rgb(196, 40, 26))
		end
		bit("ArtEgg", 0.14, 0.14, 0.06, 0.12, 0, rgb(250, 248, 240))
		bit("ArtYolk", 0.07, 0.07, 0.06, 0.12, 0, rgb(250, 190, 40))
		bit("ArtMeat", 0.16, 0.08, -0.12, 0.06, 0.5, rgb(170, 110, 90))
		bit("ArtCuke", 0.2, 0.05, -0.04, -0.12, -0.2, rgb(110, 170, 80))
		bit("ArtRadish", 0.14, 0.05, 0.14, -0.06, 0.6, rgb(250, 240, 210))
	elseif k == "kal" or k == "clam" then
		bit("ArtNoodle", 0.5, 0.4, 0, 0, 0.3, rgb(236, 226, 196))
		for i = 1, 5 do
			bit("ArtClam", 0.12, 0.09, -0.24 + i * 0.09, ((i % 2) - 0.5) * 0.24, i, rgb(150, 120, 96))
		end
		bit("ArtZucchini", 0.1, 0.03, 0.1, 0.18, 0.4, green)
		bit("ArtShrimp", 0.14, 0.07, -0.16, -0.06, -0.4, rgb(240, 120, 80))
	elseif k == "pajeon" then
		bit("ArtJeon", 0.7, 0.66, 0, 0, 0, rgb(210, 160, 80))
		for i = 1, 8 do
			bit("ArtPa", 0.4, 0.035, -0.1 + rnd(i, 2) * 0.2, -0.24 + i * 0.06, 0.2, green)
		end
	elseif k == "katsu" then
		for i = 1, 5 do
			K:box("ArtKatsu", V3(dia * 0.15, dia * 0.52, 0.02), dcf * CF(-dia * 0.3 + i * dia * 0.11, 0, zt + 0.01) * ANG(0, 0, 0.12), col(rgb(206, 140, 60)))
			K:box("ArtKatsuIn", V3(dia * 0.1, dia * 0.46, 0.022), dcf * CF(-dia * 0.3 + i * dia * 0.11, 0, zt + 0.012) * ANG(0, 0, 0.12), col(rgb(236, 210, 190)))
		end
		bit("ArtCabbage", 0.3, 0.26, 0.24, 0.12, 0, rgb(200, 230, 170))
	elseif k == "jjamppong" then
		bit("ArtNoodle", 0.4, 0.36, 0, 0, 0, rgb(226, 190, 120))
		bit("ArtMussel", 0.14, 0.08, -0.16, 0.12, 0.5, rgb(30, 26, 30))
		bit("ArtMussel", 0.14, 0.08, 0.14, -0.12, -0.4, rgb(30, 26, 30))
		bit("ArtSquid", 0.18, 0.06, 0.1, 0.14, 0.3, rgb(250, 240, 230))
		bit("ArtCabbage", 0.12, 0.08, -0.14, -0.14, 0, rgb(200, 220, 160))
	elseif k == "tangsuyuk" then
		for i = 1, 7 do
			bit("ArtPiece", 0.16, 0.12, -0.24 + rnd(i, 4) * 0.48, -0.2 + rnd(i, 9) * 0.4, i, rgb(214, 150, 60))
		end
		bit("ArtSauce", 0.18, 0.18, 0.02, 0, 0, rgb(230, 120, 50))
	elseif k == "pasta" then
		bit("ArtPasta", 0.5, 0.46, 0, 0, 0, rgb(236, 210, 140))
		for i = 1, 5 do
			bit("ArtClam", 0.11, 0.08, -0.22 + i * 0.08, ((i % 2) - 0.5) * 0.3, i, rgb(160, 130, 100))
		end
		for i = 1, 5 do
			bit("ArtParsley", 0.04, 0.03, -0.1 + rnd(i, 5) * 0.2, -0.1 + rnd(i, 6) * 0.2, i, green)
		end
	elseif k == "wine" then
		bit("ArtWine", 0.5, 0.5, 0, 0, 0, rgb(110, 16, 34))
	elseif k == "bok" or k == "bulgogi" then
		for i = 1, 4 do
			bit("ArtBok", 0.18, 0.12, -0.18 + i * 0.08, ((i % 2) - 0.5) * 0.2, i * 0.7, rgb(240, 236, 226))
		end
		for i = 1, 8 do
			bit("ArtMinari", 0.22, 0.03, -0.1 + rnd(i, 3) * 0.2, -0.24 + i * 0.06, 0.4, green)
		end
		if k == "bulgogi" then
			bit("ArtSauce", 0.4, 0.34, 0, 0, 0, rgb(180, 40, 24))
		end
	elseif k == "seonji" or k == "bone" or k == "haejang" then
		if k == "bone" then
			bit("ArtBone", 0.3, 0.2, -0.08, 0.06, 0.4, rgb(150, 100, 70))
			bit("ArtBone", 0.26, 0.18, 0.12, -0.06, -0.5, rgb(140, 92, 64))
		else
			bit("ArtSeonji", 0.16, 0.14, -0.12, 0.06, 0, rgb(70, 24, 20))
			bit("ArtSeonji", 0.14, 0.12, 0.1, 0.12, 0, rgb(80, 28, 22))
			bit("ArtSeonji", 0.15, 0.13, 0.02, -0.12, 0, rgb(66, 22, 18))
		end
		for i = 1, 5 do
			bit("ArtUgeoji", 0.24, 0.06, -0.12 + rnd(i, 2) * 0.24, -0.2 + i * 0.08, i, rgb(90, 110, 50))
		end
	else
		-- 돼지국밥 · 수육: 고기 편 + 송송 파 + 다대기
		for i = 1, 4 do
			bit("ArtMeat", 0.24, 0.12, -0.18 + i * 0.08, ((i % 2) - 0.5) * 0.12, 0.3 * i, rgb(230, 206, 186))
			bit("ArtMeatRind", 0.24, 0.035, -0.18 + i * 0.08, ((i % 2) - 0.5) * 0.12 + 0.05, 0.3 * i, rgb(246, 236, 220))
		end
		for i = 1, 9 do
			wdisc(K, "ArtPa", dia * 0.05, 0.008, dcf * CF(dia * (-0.25 + rnd(i, 1) * 0.5), dia * (-0.25 + rnd(i, 8) * 0.5), 0), zt + 0.012, col(green))
		end
		bit("ArtDadegi", 0.1, 0.09, 0.18, 0.16, 0, rgb(190, 40, 26))
	end
end

-- 음식 포스터: 프레임 + 배경 + 그릇 그림 + 제목 · 부제
local function foodPoster(c: any, dcf: CFrame, w: number, h: number, ps: any)
	local K = c.K
	K:plate("PosterFrame", w + 0.12, h + 0.12, 0.05, dcf, L.blackMetal)
	K:plate("PosterBg", w, h, 0.06, dcf, col(ps.bg))
	local wide = w >= h
	local dia = math.min(if wide then h * 0.82 else w * 0.8, if wide then w * 0.48 else h * 0.55)
	local art = if wide then dcf * CF(-w / 2 + dia / 2 + 0.2, 0, 0) else dcf * CF(0, h / 2 - dia / 2 - 0.2, 0)
	bowlArt(c, art, dia, ps.kind, nil, nil, 0.06)
	if wide then
		local tw = w - dia - 0.5
		local tx = w / 2 - tw / 2 - 0.15
		ktext(K, "PosterTitle", tw, h * 0.34, dcf * CF(tx, h * 0.16, 0.065), ps.title, { fg = ps.fg, font = F.GothamBlack })
		K:plate("PosterRule", tw * 0.7, 0.04, 0.01, dcf * CF(tx, -h * 0.04, 0.065), col(ps.acc))
		ktext(K, "PosterSub", tw, h * 0.22, dcf * CF(tx, -h * 0.22, 0.065), ps.sub, { fg = ps.acc, font = F.GothamMedium, wrap = true })
	else
		local ty = -h / 2 + (h - dia - 0.3) / 2
		ktext(K, "PosterTitle", w * 0.86, (h - dia) * 0.36, dcf * CF(0, ty + (h - dia) * 0.14, 0.065), ps.title, { fg = ps.fg, font = F.GothamBlack })
		ktext(K, "PosterSub", w * 0.86, (h - dia) * 0.2, dcf * CF(0, ty - (h - dia) * 0.16, 0.065), ps.sub, { fg = ps.acc, font = F.GothamMedium, wrap = true })
	end
	K:plate("PosterGlass", w, h, 0.01, dcf * CF(0, 0, 0.1), { c = rgb(230, 236, 240), m = M.Glass, t = 0.9, r = 0.18 })
end

-- 달력 (2026년 10월)
local function calendar(c: any, dcf: CFrame)
	local K = c.K
	local w, h = 1.5, 2.3
	K:plate("CalHook", 0.06, 0.06, 0.08, dcf * CF(0, h / 2 + 0.08, 0), L.chrome)
	K:plate("CalBack", w, h, 0.03, dcf, L.paper)
	K:plate("CalPhoto", w - 0.12, h * 0.38, 0.01, dcf * CF(0, h / 2 - h * 0.21, 0.03), col(rgb(80, 150, 200)))
	K:plate("CalPhotoSea", w - 0.12, h * 0.14, 0.012, dcf * CF(0, h / 2 - h * 0.33, 0.03), col(rgb(40, 90, 150)))
	K:plate("CalPhotoBridge", w * 0.7, 0.05, 0.014, dcf * CF(0.05, h / 2 - h * 0.25, 0.03), col(rgb(230, 230, 236)))
	ktext(K, "CalMonth", w - 0.2, 0.32, dcf * CF(0, h * 0.02, 0.035), "2026  10월  OCTOBER", { fg = rgb(200, 30, 30), font = F.GothamBlack })
	local grid = "일  월  화  수  목  금  토\n            1   2   3\n4   5   6   7   8   9  10\n11 12 13 14 15 16 17\n18 19 20 21 22 23 24\n25 26 27 28 29 30 31"
	ktext(K, "CalGrid", w - 0.16, h * 0.42, dcf * CF(0, -h * 0.27, 0.035), grid, { fg = rgb(40, 40, 44), font = F.GothamMedium })
	ktext(K, "CalShop", w - 0.2, 0.12, dcf * CF(0, -h / 2 + 0.1, 0.035), "광안 수산 · 축산 납품", { fg = rgb(90, 90, 96), font = F.Gotham })
end

-- 방송 출연 액자 (TV 화면 캡처 느낌)
local function tvFrame(c: any, dcf: CFrame, w: number, h: number)
	local K, th = c.K, c.th
	K:plate("TVFrameRim", w + 0.14, h + 0.14, 0.06, dcf, L.goldMetal)
	K:plate("TVFrameBg", w, h, 0.07, dcf, col(rgb(20, 24, 40)))
	local sw = w * 0.6
	K:plate("TVFrameShot", sw, h * 0.62, 0.01, dcf * CF(-w / 2 + sw / 2 + 0.1, h * 0.1, 0.07), col(rgb(90, 70, 50)))
	bowlArt(c, dcf * CF(-w / 2 + sw / 2 + 0.1, h * 0.1, 0), h * 0.5, th.key, nil, nil, 0.08)
	ktext(K, "TVFrameCap", sw, h * 0.18, dcf * CF(-w / 2 + sw / 2 + 0.1, -h * 0.32, 0.075), "부산 " .. th.title .. " 맛집", { fg = rgb(255, 230, 60), bg = rgb(30, 30, 30), font = F.GothamBlack, d = 0.01 })
	ktext(K, "TVFrameSide", w - sw - 0.3, h * 0.7, dcf * CF(w / 2 - (w - sw - 0.3) / 2 - 0.1, 0.05, 0.075), "방송 출연\n\n생생정보\n2025. 08", { fg = WHITE, font = F.GothamBold })
end

-- 패스 (KitchenPass · PassLedge · Noren) --------------------------------------------------------------------
-- 김 (반투명 타원체가 올라가며 옅어짐). srcs = { { p = 로컬 점, r = 폭 } }
local function steam(c: any, srcs: { any }, n: number?)
	local K = c.K
	local puffs = {}
	local per = n or 3
	for si, s in srcs do
		for j = 1, per do
			local p = K:ell("Steam", V3(s.r, s.r * 0.6, s.r), CF(s.p + V3(0, j * 0.5, 0)), { c = rgb(250, 250, 250), m = M.SmoothPlastic, t = 0.9, free = true })
			table.insert(puffs, { part = p, base = s.p, ph = (j - 1) / per + si * 0.37, r = s.r, rise = s.rise or 2.0, src = s })
		end
	end
	Interact.anim(K, function(t)
		for _, q in puffs do
			if q.part.Parent then
				local f = (t * 0.32 + q.ph) % 1
				local sc = 0.55 + f * 0.9
				q.part.Size = V3(q.r * sc, q.r * (0.45 + f * 0.5), q.r * sc)
				q.part.CFrame = K.cf * CF(q.base + V3(math.sin(t * 0.9 + q.ph * 6) * 0.12, f * q.rise, math.cos(t * 0.7 + q.ph * 5) * 0.08))
				-- 솥 입구에선 거의 투명 → 중간에서 가장 짙고 → 위에서 사라짐 (공처럼 보이지 않게)
				q.part.Transparency = if q.src.off then 1 else 0.84 + 0.15 * math.abs(f * 2 - 0.7) / 1.3
			end
		end
	end)
	return puffs
end

local norenAt: (any, CFrame, number, number, string) -> ()

local function norenOver(c: any, r: any, txt: string)
	local K, th = c.K, c.th
	local w, h = math.max(r.size.X, r.size.Z), r.size.Y
	local alongX = r.size.X >= r.size.Z
	-- 앞면 dcf (방 안쪽을 봄)
	local n = if alongX then V3(0, 0, if r.c.Z < 0 then 1 else -1) else V3(if r.c.X < 0 then 1 else -1, 0, 0)
	local ux = if alongX then V3(n.Z, 0, 0) else V3(0, 0, -n.X)
	local front = r.c + n * (math.min(r.size.X, r.size.Z) / 2)
	local d = CFrame.fromMatrix(front, ux, Vector3.yAxis, n)
	norenAt(c, d, w, h, txt)
	hideRec(K, r)
end

-- 노렌 한 벌 (d = 천 앞면 가운데 dcf, 폭 w, 높이 h): 봉 + 갈라진 천 두 장 + 단 + 글자
norenAt = function(c: any, d: CFrame, w: number, h: number, txt: string)
	local K, th = c.K, c.th
	local fab = col(th.norenC, M.Fabric)
	local gap = 0.06
	local pw = (w - gap) / 2
	K:free(function()
		K:cyl("NorenRod", w + 0.2, 0.1, d * CF(0, h / 2 - 0.05, -0.04), L.of(150, 110, 70, M.Wood))
		for _, s in { -1, 1 } do
			K:box("NorenCloth", V3(pw, h - 0.12, 0.04), d * CF(s * (pw / 2 + gap / 2), -0.06, -0.03), fab)
			K:box("NorenHem", V3(pw, 0.08, 0.05), d * CF(s * (pw / 2 + gap / 2), -h / 2 + 0.04, -0.03), dim(fab, 0.25))
		end
		local sz = math.min(h * 0.62, pw * 0.8)
		ktext(K, "NorenText", w * 0.86, sz, d * CF(0, -0.04, 0.0), txt, { fg = th.norenFg, font = F.GothamBlack, free = true })
		if c.hi then
			-- 고리 (천을 봉에 다는 고리)
			for i = 0, 5 do
				local x = -w / 2 + 0.15 + (w - 0.3) * i / 5
				K:box("NorenLoop", V3(0.08, 0.16, 0.06), d * CF(x, h / 2 - 0.1, -0.03), fab)
			end
		end
	end)
end

-- 주방 패스 안쪽 그림 (타일 · 조리대 · 솥 윗부분 · 그릇 선반 · 국자 · 김 · 테). kp = 덮어씌울 맵 KitchenPass (없으면 벽에 판)
local function passView(c: any, a: number, b: number, y0: number, y1: number, zf: number, norenBottom: number, kp: any?)
	local K, V, th = c.K, c.V, c.th
	local w, h = b - a, y1 - y0
	local u = (a + b) / 2
	local face = CFrame.fromMatrix(V3(u, (y0 + y1) / 2, zf), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
	c.pass = { a = a, b = b, y0 = y0, y1 = y1, z = zf, face = face }
	do
		K:free(function()
			-- 주방 안쪽 벽 (같은 자리 · 크기) : 흰 타일 + 줄눈
			if kp then
				K:box("PassBack", kp.size, CF(kp.c), th.passTile)
			else
				K:plate("PassBack", w, h, 0.06, face * CF(0, 0, -0.06), th.passTile)
			end
			local tile = 0.5
			for yy = y0 + tile, y1 - 0.05, tile do
				K:plate("PassGrout", w, 0.025, 0.006, face * CF(0, yy - (y0 + y1) / 2, 0), L.of(180, 178, 172))
			end
			for xx = a + 1.0, b - 0.1, 1.0 do
				K:plate("PassGrout", 0.025, h, 0.006, face * CF(xx - u, 0, 0), L.of(180, 178, 172))
			end
			-- 안쪽 조리대 (스테인리스 띠) + 솥 / 육수통 윗부분
			local ctY = y0 + 0.36
			K:plate("PassCounterBand", w, 0.5, 0.06, face * CF(0, ctY - (y0 + y1) / 2, 0), L.steel)
			local nPot = math.clamp(math.floor(w / 2.6), 1, 5)
			local srcs = {}
			for i = 1, nPot do
				local px = a + w * (i - 0.5) / nPot
				local pw = math.min(1.5, w / nPot - 0.5)
				local pc = face * CF(px - u, ctY + 0.5 - (y0 + y1) / 2, 0)
				if th.key == "ramen" and i % 2 == 0 then
					-- 면 삶는 기계 (테보 바구니 손잡이가 위로) : 벽에 붙은 스테인리스 통
					local bw = math.min(1.7, w / nPot - 0.3)
					local boil = pc * CF(0, -0.1, 0.2)
					K:box("NoodleBoiler", V3(bw, 0.55, 0.42), boil, L.brushed)
					K:box("NoodleBoilerRim", V3(bw + 0.06, 0.05, 0.46), boil * CF(0, 0.29, 0), L.chrome)
					K:box("NoodleBoilerWater", V3(bw - 0.12, 0.02, 0.32), boil * CF(0, 0.26, 0), col(rgb(220, 214, 196), M.SmoothPlastic))
					local nb2 = math.max(2, math.floor(bw / 0.3))
					for k = 1, nb2 do
						local bx = -bw / 2 + (k - 0.5) * bw / nb2
						K:vcyl("Tebo", 0.16, 0.22, boil * CF(bx, 0.33, 0), L.chrome)
						K:seg("TeboHandle", (boil * CF(bx, 0.4, 0.05)).Position, (boil * CF(bx, 0.95, 0.16)).Position, 0.035, L.of(40, 30, 24))
					end
					table.insert(srcs, { p = V3(px, ctY + 0.85, zf + 0.25), r = 0.9, rise = math.max(0.8, norenBottom - ctY - 0.9) })
					continue
				end
				-- 반쯤 벽에 묻힌 원통 솥 (앞으로 최대 0.42 나옴: 패스 받침 위 그릇 자리와 안 겹침)
				local pd = math.min(pw, 0.84)
				local potC = pc * CF(0, 0, -0.02)
				K:vcyl("PassPot", 0.75, pd, potC, L.brushed)
				K:vcyl("PassPotRim", 0.07, pd + 0.06, potC * CF(0, 0.38, 0), L.chrome)
				K:vcyl("PassPotBand", 0.05, pd + 0.02, potC * CF(0, 0.04, 0), dim(L.steel, 0.2))
				K:vcyl("PassBroth", 0.02, pd - 0.08, potC * CF(0, 0.33, 0), col(th.broth, M.SmoothPlastic))
				for _, sx in { -1, 1 } do
					K:box("PassPotHandle", V3(0.12, 0.08, 0.1), potC * CF(sx * (pd / 2 + 0.04), 0.26, 0.12), L.blackMetal)
				end
				if i % 2 == 0 then
					-- 국자 꽂힌 솥
					K:seg("PassPotLadle", (potC * CF(0.12, 0.3, 0.16)).Position, (potC * CF(0.3, 1.0, 0.1)).Position, 0.035, L.chrome)
				end
				table.insert(srcs, { p = V3(px, ctY + 0.95, zf + 0.25), r = 0.7, rise = math.max(0.8, norenBottom - ctY - 0.9) })
			end
			-- 선반 (노렌 바로 아래): 그릇 쌓음 + 국자 걸이
			local sy = math.min(norenBottom - 0.18, y0 + h * 0.72)
			local shelfDcf = face * CF(0, sy - (y0 + y1) / 2, 0)
			K:box("PassShelf", V3(w - 0.3, 0.06, 0.42), shelfDcf * CF(0, 0, 0.21), L.steel)
			local nb = math.floor((w - 0.6) / 0.62)
			local bowlL = col(th.bowl, if th.key == "milmyeon" then M.Metal else M.SmoothPlastic)
			for i = 1, nb do
				local x = -w / 2 + 0.3 + (i - 0.5) * (w - 0.6) / nb
				local stack = 1 + (i + c.seed) % 3
				for j = 1, stack do
					local by = 0.03 + (j - 1) * 0.13
					K:vcyl("PassBowlFoot", 0.04, 0.26, shelfDcf * CF(x, by + 0.02, 0.22), bowlL)
					K:vcyl("PassBowl", 0.1, 0.5, shelfDcf * CF(x, by + 0.09, 0.22), bowlL)
				end
			end
			-- 국자 · 뜰채 (선반 아래에 걸림)
			for i = 1, math.min(4, math.floor(w / 1.4)) do
				local x = -w / 2 + 0.6 + (i - 1) * 1.1
				local top = shelfDcf * CF(x, -0.03, 0.36)
				K:seg("PassLadle", top.Position, (top * CF(0, -0.6, 0)).Position, 0.035, L.chrome)
				K:ell("PassLadleCup", V3(0.24, 0.16, 0.24), top * CF(0, -0.66, 0), L.chrome)
			end
			-- 스테인리스 테 + 주방 조명 띠
			K:plate("PassTrim", w + 0.3, 0.14, 0.12, face * CF(0, h / 2 + 0.07, 0), L.chrome)
			K:plate("PassTrim", 0.14, h, 0.12, face * CF(-w / 2 - 0.08, 0, 0), L.chrome)
			K:plate("PassTrim", 0.14, h, 0.12, face * CF(w / 2 + 0.08, 0, 0), L.chrome)
			local lamp = K:plate("PassLampLED", w - 0.4, 0.05, 0.05, face * CF(0, sy + 0.12 - (y0 + y1) / 2, 0.05), L.lampNeutral)
			K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.7, Angle = 120, Color = L.neutralLight })
			c.passSteam = steam(c, srcs, 2)
			-- 주문표 레일 (테 위) + 주방 표지
			K:plate("TicketRail", math.min(w - 0.6, 3.2), 0.08, 0.1, face * CF(0, h / 2 + 0.22, 0), L.chrome)
			for i = 1, 4 do
				K:plate("OrderSlip", 0.32, 0.42, 0.012, face * CF(-1.2 + i * 0.48, h / 2 + 0.0, 0.11) * ANG(0, 0, (i % 2 - 0.5) * 0.08), L.paper)
			end
		end)
	end
end

local function passOver(c: any)
	local K, V, th = c.K, c.V, c.th
	local kp = V:first("KitchenPass")
	if kp then
		local norenBottom = kp.max.Y
		for _, r in V.byName.Noren or {} do
			if r.c.X > kp.min.X - 1 and r.c.X < kp.max.X + 1 then
				norenBottom = math.min(norenBottom, r.min.Y)
			end
		end
		passView(c, kp.min.X, kp.max.X, kp.min.Y, kp.max.Y, kp.max.Z, norenBottom, kp)
		hideRec(K, kp)
	end
	local pl = V:first("PassLedge")
	if pl then
		K:free(function()
			K:box("PassLedgeTop", pl.size, CF(pl.c), L.steel)
			K:box("PassLedgeLip", V3(pl.size.X, pl.size.Y + 0.06, 0.06), CF(pl.c.X, pl.c.Y - 0.03, pl.max.Z - 0.03), L.chrome)
			for _, sx in { -1, 1 } do
				local x = pl.c.X + sx * (pl.size.X / 2 - 0.5)
				K:bar("PassBracket", V3(x, pl.min.Y - 0.6, pl.min.Z + 0.03), V3(x, pl.min.Y, pl.max.Z - 0.15), 0.07, 0.07, L.chrome)
			end
		end)
		hideRec(K, pl)
	end
	local nlist = {}
	for _, r in V.byName.Noren or {} do
		table.insert(nlist, r)
	end
	table.sort(nlist, function(p, q)
		return p.c.X < q.c.X
	end)
	for i, r in nlist do
		norenOver(c, r, th.noren[((i - 1) % #th.noren) + 1])
	end
end

-- 패스가 없는 가게 (주방 창이 없는 맵): 뒷벽에 주방 창 (타일 안쪽 그림 + 스테인리스 받침 + 노렌)
local function fakePass(c: any)
	local K, V, th = c.K, c.V, c.th
	if c.pass or #V.counters > 0 or V:has("KitchenPass") > 0 or V:has("PassCounter") > 0 then
		return
	end
	local y0 = 3.5
	local y1 = math.min(V.H - 2.75, 5.6)
	if y1 - y0 < 1.5 then
		return
	end
	local wn, u, w = findWall(K, { "back" }, 4.6, 6.0, y0 - 0.5, y1 + 0.08, V3(-3, 0, V.z0), 0.6, function(_wn: string, uu: number, ww: number)
		local mn, mx = V3(uu - ww / 2, y0 - 0.45, V.z0), V3(uu + ww / 2, y0 - 0.05, V.z0 + 1.0)
		return K:hitsKeep(mn, mx) == nil
	end)
	if not wn or not u or not w then
		return
	end
	local ww = w - 0.5
	local a, b = u - ww / 2, u + ww / 2
	local zf = V.z0 + 0.06
	local nh = math.min(0.75, (y1 - y0) * 0.38)
	passView(c, a, b, y0, y1, zf, y1 - nh)
	-- 받침 (스테인리스 선반) + 노렌
	K:box("FakePassLedge", V3(ww + 0.4, 0.16, 0.95), CF(u, y0 - 0.08, V.z0 + 0.475), L.steel)
	K:box("FakePassLip", V3(ww + 0.4, 0.22, 0.05), CF(u, y0 - 0.1, V.z0 + 0.95), L.chrome)
	for _, sx in { -1, 1 } do
		K:bar("FakePassBracket", V3(u + sx * (ww / 2 - 0.3), y0 - 0.7, V.z0 + 0.03), V3(u + sx * (ww / 2 - 0.3), y0 - 0.16, V.z0 + 0.8), 0.07, 0.07, L.chrome)
	end
	local d = CFrame.fromMatrix(V3(u, y1 - nh / 2, zf + 0.06), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
	norenAt(c, d, ww, nh, th.noren[1] .. " " .. (th.noren[2] or ""))
	at(K, "fakepass", wn, u)
end

-- 라멘 카운터 (BarUpstand · 양념 · 뒷벽 하부장 · 후드 · 등) ------------------------------------------------------
local function condimentSet(c: any, base: CFrame, i: number)
	local K, th = c.K, c.th
	K:box("CondTray", V3(1.1, 0.05, 0.34), base * CF(0, 0.025, 0), wood(70, 46, 30))
	if th.key == "ramen" then
		K:vcyl("CondBeni", 0.32, 0.24, base * CF(-0.38, 0.21, 0), { c = rgb(220, 50, 60), m = M.Glass, t = 0.2 })
		K:vcyl("CondBeniLid", 0.06, 0.26, base * CF(-0.38, 0.4, 0), L.black)
		K:vcyl("CondSesame", 0.34, 0.2, base * CF(-0.1, 0.22, 0), { c = rgb(230, 200, 140), m = M.Glass, t = 0.25 })
		K:vcyl("CondSesameTop", 0.1, 0.16, base * CF(-0.1, 0.44, 0), L.black)
		K:vcyl("CondGarlic", 0.28, 0.22, base * CF(0.15, 0.19, 0), { c = rgb(240, 236, 220), m = M.Glass, t = 0.2 })
		K:vcyl("CondTogarashi", 0.3, 0.14, base * CF(0.36, 0.2, 0), L.of(180, 30, 26))
		K:vcyl("CondTogarashiCap", 0.06, 0.15, base * CF(0.36, 0.38, 0), L.black)
	else
		K:vcyl("CondVinegar", 0.5, 0.18, base * CF(-0.3, 0.3, 0), { c = rgb(240, 200, 120), m = M.Glass, t = 0.3 })
		K:vcyl("CondMustard", 0.46, 0.18, base * CF(0, 0.28, 0), L.of(240, 200, 40))
		K:vcyl("CondSauce", 0.4, 0.2, base * CF(0.3, 0.25, 0), L.of(120, 60, 30))
	end
	-- 젓가락통 · 티슈 / 물병 (번갈아)
	K:vcyl("ChopstickHolder", 0.42, 0.22, base * CF(-0.85, 0.21, 0), wood(150, 106, 66))
	for k = 0, 4 do
		K:vcyl("Chopstick", 0.5, 0.035, base * CF(-0.85 + (k - 2) * 0.035, 0.42, (k % 2 - 0.5) * 0.04), L.of(236, 220, 180, M.Wood))
	end
	if i % 2 == 0 then
		K:box("CondTissue", V3(0.42, 0.26, 0.28), base * CF(0.88, 0.13, 0), L.of(246, 246, 240))
		K:box("CondTissuePop", V3(0.14, 0.08, 0.1), base * CF(0.88, 0.3, 0), L.paper)
	else
		K:vcyl("WaterPitcher", 0.55, 0.26, base * CF(0.88, 0.275, 0), L.steel)
		K:box("WaterPitcherHandle", V3(0.05, 0.36, 0.06), base * CF(1.03, 0.3, 0), L.steel)
		K:wedge("WaterPitcherSpout", V3(0.1, 0.08, 0.12), base * CF(0.73, 0.52, 0) * ANG(0, -PI / 2, 0), L.steel)
	end
end

-- 후드 (f = 후드 바닥 가운데 높이 0 의 프레임, +Z = 방 쪽): 폭 w, 깊이 d, y0..y1
local function hoodFrame(c: any, f: CFrame, w: number, d: number, y0: number, y1: number)
	local K = c.K
	K:free(function()
		local hs = L.of(204, 207, 210, M.SmoothPlastic, { r = 0.22 })
		K:box("HoodBody", V3(w, y1 - y0 - 0.5, d), f * CF(0, y0 + 0.5 + (y1 - y0 - 0.5) / 2, 0), hs)
		K:box("HoodSkirt", V3(w, 0.5, 0.08), f * CF(0, y0 + 0.25, d / 2 - 0.04), hs)
		K:box("HoodSkirt", V3(0.08, 0.5, d), f * CF(-w / 2 + 0.04, y0 + 0.25, 0), hs)
		K:box("HoodSkirt", V3(0.08, 0.5, d), f * CF(w / 2 - 0.04, y0 + 0.25, 0), hs)
		local n = math.max(2, math.floor(w / 1.6))
		for i = 1, n do
			local x = -w / 2 + w * (i - 0.5) / n
			K:box("HoodFilter", V3(w / n - 0.12, 0.04, d - 0.4), f * CF(x, y0 + 0.5, -0.05), L.of(110, 112, 116, M.DiamondPlate))
		end
		local led = K:box("HoodLED", V3(w - 0.6, 0.04, 0.12), f * CF(0, y0 + 0.47, d / 2 - 0.3), L.lampWarm)
		K:light(led, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 8, Brightness = 0.6, Angle = 130, Color = L.warmLight })
		K:box("HoodSeam", V3(0.03, y1 - y0 - 0.6, 0.02), f * CF(0, y0 + 0.5 + (y1 - y0 - 0.5) / 2, d / 2 + 0.005), L.brushed)
		K:box("HoodDuct", V3(math.min(1.6, w * 0.3), 0.3, 0.8), f * CF(0, y1 - 0.15, -d / 2 + 0.5), hs)
	end)
end

local function hoodOver(c: any, x0: number, x1: number, z0: number, z1: number, y0: number, y1: number)
	hoodFrame(c, CF((x0 + x1) / 2, 0, (z0 + z1) / 2), x1 - x0, z1 - z0, y0, y1)
end

-- 나무 메뉴패 줄 (dcf 표면 위, 폭 w, 높이 h 영역)
local function menuTags(c: any, dcf: CFrame, w: number, h: number, items: { any })
	local K = c.K
	local n = math.min(#items, math.floor(w / 0.95))
	if n < 1 then
		return
	end
	local tw = math.min(0.78, w / n - 0.16)
	K:plate("TagRail", w, 0.12, 0.08, dcf * CF(0, h / 2 - 0.06, 0), wood(50, 34, 24))
	for i = 1, n do
		local x = -w / 2 + (i - 0.5) * w / n
		local it = items[i]
		local th2 = h - 0.24
		local d = dcf * CF(x, -0.08, 0)
		K:plate("TagWood", tw, th2, 0.06, d, L.of(226, 198, 150, M.Wood))
		local nc = charCount(it[1])
		ktext(K, "TagName", tw * 0.8, th2 * 0.7, d * CF(0, th2 * 0.12, 0.06), vertical(it[1]), { fg = rgb(30, 22, 18), font = F.GothamBlack })
		ktext(K, "TagPrice", tw * 0.9, math.min(0.26, th2 * 0.14), d * CF(0, -th2 / 2 + 0.17, 0.06), it[2], { fg = rgb(170, 30, 24), font = F.GothamBold })
		if nc == 0 then
			break
		end
	end
end

local function lantern(c: any, top: Vector3, dia: number, h: number, txt: string?, colr: Color3?)
	local K = c.K
	local cl = colr or rgb(206, 40, 28)
	local cy = top.Y - 0.35 - h / 2
	local p = V3(top.X, cy, top.Z)
	K:seg("LanternCord", top, p + V3(0, h / 2 + 0.1, 0), 0.04, L.black)
	K:disc("LanternCap", dia * 0.45, 0.12, CF(p + V3(0, h / 2, 0)), L.black)
	K:disc("LanternCap", dia * 0.45, 0.12, CF(p - V3(0, h / 2, 0)), L.black)
	local body = K:ell("LanternLamp", V3(dia, h, dia), CF(p), { c = cl, m = M.SmoothPlastic })
	if c.hi then
		for _, fy in { -0.28, 0, 0.28 } do
			local r = dia / 2 * math.sqrt(1 - (fy * 2) ^ 2 * 0.9)
			K:ring("LanternRib", CF(p + V3(0, h * fy, 0)) * ANG(PI / 2, 0, 0), r, 0.03, 10, L.of(120, 20, 16))
		end
	end
	if txt then
		-- 글자는 손님 쪽(+Z, 입구 쪽) 한 면만 (SurfaceGui 수 절약)
		for _, s in { 1 } do
			local d = CFrame.fromMatrix(p + V3(0, 0, s * (dia / 2 + 0.005)), V3(s, 0, 0), Vector3.yAxis, V3(0, 0, s))
			ktext(K, "LanternText", dia * 0.5, h * 0.6, d, vertical(txt), { fg = rgb(20, 14, 12), font = F.GothamBlack, free = true })
		end
	end
	K:seg("LanternTassel", p - V3(0, h / 2 + 0.06, 0), p - V3(0, h / 2 + 0.55, 0), 0.08, if colr then L.goldMetal else L.of(150, 20, 16, M.Fabric))
	return body
end

local function barOver(c: any)
	local K, V, th = c.K, c.V, c.th
	if #V.counters == 0 then
		return
	end
	local g = V.counters[1]
	local up = V:first("BarUpstand")
	if up then
		K:free(function()
			K:box("UpstandBody", up.size - V3(0, 0.08, 0), CF(up.c - V3(0, 0.04, 0)), wood(84, 56, 36))
			K:box("UpstandCap", V3(up.size.X + 0.06, 0.08, up.size.Z + 0.1), CF(up.c.X, up.max.Y - 0.04, up.c.Z), L.of(226, 196, 150, M.Wood))
		end)
		hideRec(K, up)
		-- 위 선반 양념 (스툴 2개마다)
		local n = math.max(1, math.floor(up.size.X / 2.8))
		for i = 1, n do
			local x = up.min.X + up.size.X * (i - 0.5) / n
			local base = CF(x, up.max.Y, up.c.Z)
			if clearAt(K, base * CF(0, 0.3, 0), V3(2.3, 0.62, 0.4)) then
				condimentSet(c, base, i)
			else
				-- Scan 의 통로 keep 은 주방 패스(카운터 안쪽)에서 테이블로 곧게 그어져 카운터 · 윗선반을 뚫고 지나감.
				-- 윗선반(맵 BarUpstand) 위는 사람이 다닐 수 없는 자리라 통로 keep 만 걸리면 놓음 (좌석 · 테이블 · 직원 keep 은 그대로 피함)
				local mn, mx = laabb(base * CF(0, 0.3, 0), V3(2.3, 0.62, 0.4))
				local other = false
				for _, kk in V.keep do
					if kk.kind ~= "aisle" and overlap(mn, mx, kk.min, kk.max) then
						other = true
						break
					end
				end
				if not other and mn.Z >= up.min.Z - 0.05 and mx.Z <= up.max.Z + 0.05 then
					K:free(function()
						condimentSet(c, base, i)
					end)
				end
			end
		end
		c.upstand = up
	end
	-- 뒷벽 하부장 (깊이 < 1.2, 직원 자리 피함) — 카운터가 뒷벽과 나란할 때
	local alongX = (g.max.X - g.min.X) >= (g.max.Z - g.min.Z)
	if alongX and g.min.Z - V.z0 < 4.5 then
		local pl = V:first("PassLedge")
		local cabH = if pl then pl.min.Y - 0.12 else 3.2
		local x = g.min.X + 0.2
		while x < g.max.X - 1.2 do
			local w = 1.8
			local cx = x + w / 2
			local pcf = CF(cx, 0, V.z0 + 0.48)
			if clearAt(K, pcf * CF(0, cabH / 2, 0), V3(w, cabH, 0.9)) and K:spot(pcf, V3(w, cabH, 0.9), 0, "backcab") then
				K:box("BackCabinet", V3(w - 0.04, cabH - 0.3, 0.9), pcf * CF(0, 0.3 + (cabH - 0.3) / 2, 0), L.steel)
				K:box("BackCabinetKick", V3(w - 0.2, 0.3, 0.8), pcf * CF(0, 0.15, -0.05), L.black)
				K:box("BackCabinetSeam", V3(0.03, cabH - 0.5, 0.02), pcf * CF(0, 0.3 + (cabH - 0.3) / 2, 0.455), L.brushed)
				for _, sx in { -1, 1 } do
					K:box("BackCabinetHandle", V3(0.06, 0.5, 0.06), pcf * CF(sx * 0.12, cabH - 0.6, 0.48), L.chrome)
				end
				K:box("BackCabinetLCD", V3(0.3, 0.14, 0.02), pcf * CF(w / 2 - 0.3, cabH - 0.3, 0.46), L.ledBlue)
			end
			x += w + 0.05
		end
		-- 후드 (6.5 위): 패스 위 뒷벽에서 카운터 뒤쪽까지
		local hy0 = math.max(7.2, (if c.pass then c.pass.y1 else 6.6) + 0.6)
		local hy1 = V.H - 0.15
		if hy1 - hy0 > 1.4 then
			local z1 = math.min(g.min.Z - 0.1, V.z0 + 2.4)
			hoodOver(c, g.min.X, g.max.X, V.z0 + 0.02, z1, hy0, hy1)
			claim(K, "back", g.min.X - 0.2, g.max.X + 0.2, hy0 - 0.2, V.H)
			c.hood = { x0 = g.min.X, x1 = g.max.X, z1 = z1, y0 = hy0, y1 = hy1 }
		end
	end
end

-- 셀프 반찬바 ------------------------------------------------------------------------------------------------
local BANCHAN = {
	{ "kkakdugi", rgb(214, 96, 52) }, { "kimchi", rgb(196, 62, 36) }, { "buchu", rgb(80, 132, 52) }, { "onion", rgb(236, 226, 186) },
	{ "pepper", rgb(70, 130, 50) }, { "ssamjang", rgb(130, 76, 40) }, { "saeujeot", rgb(236, 200, 182) }, { "garlic", rgb(246, 242, 228) },
}

local function banchanFill(c: any, base: CFrame, kind: string, cl: Color3, pw: number, pd: number)
	local K = c.K
	local fl = col(cl, M.SmoothPlastic)
	K:box("BanchanFill", V3(pw - 0.12, 0.08, pd - 0.12), base * CF(0, 0.04, 0), fl)
	if not c.hi then
		return
	end
	if kind == "kkakdugi" then
		for i = 1, 4 do
			K:box("Kkakdugi", V3(0.14, 0.14, 0.14), base * CF(-pw / 2 + 0.16 + (i - 1) * (pw - 0.3) / 3, 0.12, (rnd(i, 4) - 0.5) * 0.3) * ANG(0, i, 0.2), fl)
		end
	elseif kind == "kimchi" or kind == "buchu" or kind == "ssamjang" then
		K:ell("BanchanHeap", V3(pw * 0.7, 0.18, pd * 0.6), base * CF(0, 0.1, 0), fl)
	elseif kind == "pepper" then
		for i = 1, 3 do
			K:cyl("Gochu", 0.34, 0.08, base * CF(0, 0.1, -0.2 + i * 0.12) * ANG(0, 0.3 * i, 0), fl)
		end
	elseif kind == "garlic" then
		for i = 1, 4 do
			K:ball("Maneul", 0.12, base * CF(-0.15 + (i % 2) * 0.3, 0.1, -0.15 + (i // 3) * 0.3), fl)
		end
	end
end

local function selfBar(c: any, pcf: CFrame, w: number, d: number)
	local K, th = c.K, c.th
	local H = 3.0
	K:box("SelfBarBody", V3(w, H - 0.45, d - 0.1), pcf * CF(0, 0.35 + (H - 0.45) / 2, -0.05), L.brushed)
	K:box("SelfBarKick", V3(w - 0.2, 0.35, d - 0.3), pcf * CF(0, 0.175, -0.15), L.black)
	local nd = math.max(2, math.floor(w / 1.4))
	local dw = w / nd
	for i = 1, nd do
		local x = -w / 2 + dw * (i - 0.5)
		K:box("SelfBarDoorSeam", V3(0.03, H - 0.7, 0.02), pcf * CF(x + dw / 2, 0.35 + (H - 0.7) / 2 + 0.05, d / 2 - 0.09), dim(L.steel, 0.3))
		K:box("SelfBarHandle", V3(dw * 0.5, 0.06, 0.06), pcf * CF(x, H - 0.45, d / 2 - 0.05), L.chrome)
	end
	K:box("SelfBarTop", V3(w + 0.1, 0.1, d + 0.05), pcf * CF(0, H - 0.05, 0), L.steel)
	-- 반찬 통 (냉장 칸)
	local panW = w - 1.5
	local np = math.clamp(math.floor(panW / 0.72), 3, 8)
	local pw = panW / np
	local pd = 0.95
	local x0 = -w / 2 + 0.15
	K:box("SelfBarWell", V3(panW + 0.08, 0.1, pd + 0.12), pcf * CF(x0 + panW / 2, H + 0.05, 0.12), L.of(60, 62, 66, M.Metal))
	for i = 1, np do
		local x = x0 + pw * (i - 0.5)
		local list = th.banchan or BANCHAN
		local bc = list[((i - 1 + c.seed) % #list) + 1]
		local base = pcf * CF(x, H + 0.1, 0.12)
		K:box("BanchanPan", V3(pw - 0.04, 0.14, pd), base * CF(0, 0.07, 0), L.chrome)
		banchanFill(c, base * CF(0, 0.08, 0), bc[1], bc[2], pw - 0.04, pd)
	end
	-- 재채기 가림막 (크롬 기둥 + 유리)
	local gy = H + 1.25
	for _, sx in { -1, 1 } do
		local x = x0 + (if sx < 0 then 0.05 else panW - 0.05)
		K:vcyl("GuardPost", 1.25, 0.08, pcf * CF(x, H + 0.625, -0.36), L.chrome)
	end
	K:box("GuardGlass", V3(panW, 0.04, 0.9), pcf * CF(x0 + panW / 2, gy, 0.05), { c = rgb(220, 236, 240), m = M.Glass, t = 0.65, r = 0.15 })
	K:box("GuardFront", V3(panW, 0.6, 0.03), pcf * CF(x0 + panW / 2, gy - 0.28, 0.52) * ANG(math.rad(18), 0, 0), { c = rgb(220, 236, 240), m = M.Glass, t = 0.7, r = 0.15 })
	local led = K:box("GuardLED", V3(panW - 0.2, 0.03, 0.06), pcf * CF(x0 + panW / 2, gy - 0.035, -0.2), L.lampNeutral)
	-- 끝: 앞접시 · 집게 · 컵 소독기
	local ex = w / 2 - 0.7
	for j = 1, 6 do
		K:disc("SidePlate", 0.62, 0.05, pcf * CF(ex - 0.15, H + 0.03 + j * 0.05, 0.3), L.of(246, 246, 240))
	end
	K:box("TongTray", V3(0.5, 0.05, 0.8), pcf * CF(ex + 0.38, H + 0.03, 0.4), L.steel)
	for k = 1, 2 do
		K:box("Tong", V3(0.06, 0.04, 0.7), pcf * CF(ex + 0.3 + k * 0.08, H + 0.08, 0.4) * ANG(0, 0.05 * k, 0), L.chrome)
	end
	-- 컵 소독기 (UV 파란 불빛)
	local cb = pcf * CF(ex, H, -0.35)
	K:box("CupSterilizer", V3(1.1, 1.3, 0.8), cb * CF(0, 0.65, 0), L.plasticWhite)
	K:box("CupSterilizerGlass", V3(0.9, 1.0, 0.02), cb * CF(0, 0.7, 0.41), { c = rgb(150, 160, 230), m = M.Glass, t = 0.45 })
	K:box("CupSterilizerUV", V3(0.86, 0.04, 0.5), cb * CF(0, 1.16, 0.05), L.neon(rgb(110, 90, 255)))
	for k = 0, 3 do
		K:vcyl("SteelCup", 0.32, 0.22, cb * CF(-0.3 + k * 0.2, 0.42 + 0.16, 0.12), L.steel)
		K:vcyl("SteelCup", 0.32, 0.22, cb * CF(-0.3 + k * 0.2, 0.82 + 0.16, 0.12), L.steel)
	end
	K:box("CupSterilizerShelf", V3(0.96, 0.03, 0.6), cb * CF(0, 0.78, 0.05), L.chrome)
	return led
end

-- 소주 · 맥주 냉장고 (유리문, 문은 상호작용으로 엶) ------------------------------------------------------------------
local function bottle(K: any, base: CFrame, kind: string, hi: boolean)
	if kind == "soju" then
		K:vcyl("Soju", 0.5, 0.24, base * CF(0, 0.25, 0), { c = rgb(40, 140, 80), m = M.Glass, t = 0.15 })
		if hi then
			K:vcyl("SojuNeck", 0.2, 0.12, base * CF(0, 0.6, 0), { c = rgb(40, 140, 80), m = M.Glass, t = 0.15 })
			K:plate("SojuLabel", 0.2, 0.18, 0.01, base * CF(0, 0.26, 0.12), L.of(250, 250, 250))
		end
	elseif kind == "beer" then
		K:vcyl("BeerBottle", 0.56, 0.26, base * CF(0, 0.28, 0), { c = rgb(110, 60, 20), m = M.Glass, t = 0.12 })
		if hi then
			K:vcyl("BeerNeck", 0.22, 0.12, base * CF(0, 0.67, 0), { c = rgb(110, 60, 20), m = M.Glass, t = 0.12 })
			K:plate("BeerLabel", 0.22, 0.16, 0.01, base * CF(0, 0.3, 0.13), L.of(230, 200, 60))
		end
	elseif kind == "cider" then
		K:vcyl("Cider", 0.62, 0.26, base * CF(0, 0.31, 0), { c = rgb(140, 210, 150), m = M.Glass, t = 0.3 })
		if hi then
			K:vcyl("CiderCap", 0.06, 0.12, base * CF(0, 0.65, 0), L.of(40, 120, 60))
		end
	else
		K:vcyl("Can", 0.42, 0.24, base * CF(0, 0.21, 0), L.of(200, 30, 36, M.Metal))
		if hi then
			K:vcyl("CanTop", 0.02, 0.2, base * CF(0, 0.43, 0), L.alu)
		end
	end
end

local function drinkFridge(c: any, pcf: CFrame, nd: number)
	local K, th = c.K, c.th
	local dw = 2.0
	local w = nd * dw + 0.3
	local h = 6.3
	local d = 2.0
	local body = L.of(232, 234, 236, M.Metal)
	-- 껍데기 (안이 보이게 상자 여러 장)
	K:box("FridgeBack", V3(w, h, 0.12), pcf * CF(0, h / 2, -d / 2 + 0.06), body)
	K:box("FridgeSide", V3(0.12, h, d), pcf * CF(-w / 2 + 0.06, h / 2, 0), body)
	K:box("FridgeSide", V3(0.12, h, d), pcf * CF(w / 2 - 0.06, h / 2, 0), body)
	K:box("FridgeTop", V3(w, 0.75, d), pcf * CF(0, h - 0.375, 0), body)
	K:box("FridgeBase", V3(w, 0.6, d), pcf * CF(0, 0.3, 0), body)
	K:plate("FridgeVent", w * 0.6, 0.3, 0.02, pcf * CF(0, 0.3, d / 2), L.of(80, 82, 86, M.DiamondPlate))
	K:box("FridgeInner", V3(w - 0.26, h - 1.35, 0.02), pcf * CF(0, 0.6 + (h - 1.35) / 2, -d / 2 + 0.13), L.of(244, 246, 248))
	ktext(K, "FridgeHeader", w - 0.14, 0.55, pcf * CF(0, h - 0.375, d / 2), th.fridgeHeader, { fg = WHITE, bg = rgb(16, 110, 64), glow = 1.2, font = F.GothamBlack })
	local lamp = K:box("FridgeLamp", V3(w - 0.4, 0.05, 0.1), pcf * CF(0, h - 0.8, d / 2 - 0.3), L.lampCool)
	K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.7, Angle = 140, Color = L.coolLight })
	local shelves = 4
	local innerH = h - 1.35
	local kinds = { "soju", "soju", "beer", "cider" }
	if th.key == "ramen" or th.key == "katsu" or th.key == "bistro" then
		kinds = { "beer", "beer", "can", "cider" }
	end
	for i = 1, shelves do
		local y = 0.6 + (i - 1) * innerH / shelves + 0.02
		K:box("FridgeShelf", V3(w - 0.3, 0.04, d - 0.5), pcf * CF(0, y, -0.1), L.of(190, 194, 198, M.Metal))
		local kind = kinds[i]
		local n = math.floor((w - 0.5) / 0.33)
		local step = (w - 0.5) / n
		for j = 1, n do
			local x = -w / 2 + 0.25 + step * (j - 0.5)
			bottle(K, pcf * CF(x, y + 0.02, 0.35), kind, c.hi and (j % 2 == 1))
			if c.hi and j % 3 == 0 then
				bottle(K, pcf * CF(x, y + 0.02, -0.15), kind, false)
			end
		end
	end
	-- 문 (경첩 = 왼쪽 끝)
	local doors = {}
	for i = 1, nd do
		local x0 = -w / 2 + 0.15 + (i - 1) * dw
		local m = K:group("FridgeDoor_" .. i, function()
			local cc = pcf * CF(x0 + dw / 2, 0.6 + innerH / 2, d / 2 + 0.05)
			local fr = L.of(40, 42, 46, M.Metal)
			K:box("FridgeDoorFrame", V3(dw, 0.12, 0.1), cc * CF(0, innerH / 2 - 0.06, 0), fr)
			K:box("FridgeDoorFrame", V3(dw, 0.12, 0.1), cc * CF(0, -innerH / 2 + 0.06, 0), fr)
			K:box("FridgeDoorFrame", V3(0.12, innerH, 0.1), cc * CF(-dw / 2 + 0.06, 0, 0), fr)
			K:box("FridgeDoorFrame", V3(0.12, innerH, 0.1), cc * CF(dw / 2 - 0.06, 0, 0), fr)
			K:box("FridgeDoorGlass", V3(dw - 0.22, innerH - 0.22, 0.03), cc, { c = rgb(210, 230, 236), m = M.Glass, t = 0.75, r = 0.12 })
			K:box("FridgeDoorHandle", V3(0.08, innerH * 0.55, 0.12), cc * CF(dw / 2 - 0.22, 0, 0.1), L.chrome)
		end)
		local hinge = (K.cf * pcf * CF(x0, 0, d / 2 + 0.05)).Position
		table.insert(doors, { m = m, hinge = hinge })
	end
	return doors
end

-- 육수 솥 (가스 낮은 화구 + 스테인리스 곰솥 + 김) ----------------------------------------------------------------
local function potStation(c: any, pcf: CFrame, w: number)
	local K, th = c.K, c.th
	local nPots = if w >= 3.8 then 2 else 1
	local potD = 1.6
	local burnerH = 0.95
	local cast = L.of(30, 30, 32, M.Metal)
	local flames = {}
	local srcs = {}
	for i = 1, nPots do
		local x = if nPots == 1 then 0 else (i - 1.5) * 2.0
		local b = pcf * CF(x, 0, 0)
		local s = 1.75
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				K:box("BurnerLeg", V3(0.14, burnerH, 0.14), b * CF(sx * (s / 2 - 0.07), burnerH / 2, sz * (s / 2 - 0.07)), cast)
			end
		end
		K:box("BurnerRail", V3(s, 0.12, 0.14), b * CF(0, burnerH - 0.06, s / 2 - 0.07), cast)
		K:box("BurnerRail", V3(s, 0.12, 0.14), b * CF(0, burnerH - 0.06, -s / 2 + 0.07), cast)
		K:box("BurnerRail", V3(0.14, 0.12, s - 0.28), b * CF(s / 2 - 0.07, burnerH - 0.06, 0), cast)
		K:box("BurnerRail", V3(0.14, 0.12, s - 0.28), b * CF(-s / 2 + 0.07, burnerH - 0.06, 0), cast)
		K:box("BurnerShelf", V3(s - 0.2, 0.05, s - 0.2), b * CF(0, 0.22, 0), cast)
		K:disc("BurnerHead", 0.7, 0.16, b * CF(0, burnerH - 0.28, 0), L.of(50, 50, 52, M.Metal))
		local fl = {}
		for _, p in K:ring("BurnerFlame", b * CF(0, burnerH - 0.17, 0) * ANG(PI / 2, 0, 0), 0.3, 0.08, 10, L.neon(rgb(90, 150, 255))) do
			table.insert(fl, p)
		end
		table.insert(flames, fl)
		-- 냄비 받침 (삼발이)
		for k = 0, 2 do
			local a = k * 2 * PI / 3
			K:box("BurnerGrate", V3(0.08, 0.08, 0.8), b * CF(math.cos(a) * 0.3, burnerH + 0.0, math.sin(a) * 0.3) * ANG(0, -a + PI / 2, 0), cast)
		end
		-- 곰솥
		local py = burnerH + 0.04
		local potH = 1.65
		K:vcyl("StockPotBody", potH - 0.14, potD, b * CF(0, py + (potH - 0.14) / 2, 0), L.steel)
		K:disc("StockPotBroth", potD - 0.08, 0.02, b * CF(0, py + potH - 0.13, 0), col(th.broth))
		K:ring("StockPotRim", b * CF(0, py + potH - 0.08, 0) * ANG(PI / 2, 0, 0), potD / 2 - 0.02, 0.09, 16, L.chrome)
		K:ring("StockPotLip", b * CF(0, py + potH - 0.02, 0) * ANG(PI / 2, 0, 0), potD / 2 - 0.02, 0.07, 16, L.chrome)
		K:disc("StockPotBand", potD + 0.02, 0.06, b * CF(0, py + 0.3, 0), L.brushed)
		for _, sx in { -1, 1 } do
			K:box("StockPotHandle", V3(0.3, 0.1, 0.4), b * CF(sx * (potD / 2 + 0.12), py + potH - 0.35, 0), L.chrome)
		end
		-- 국자 (솥 안에 기대어)
		local la = (b * CF(0.25, py + potH - 0.2, 0.1)).Position
		local lb = (b * CF(0.7, py + potH + 1.0, 0.35)).Position
		K:seg("LadleHandle", la, lb, 0.06, L.chrome)
		K:ell("LadleCup", V3(0.36, 0.2, 0.36), b * CF(0.2, py + potH - 0.2, 0.08), L.chrome)
		-- 육수 거품 · 고기 덩이
		if c.hi then
			for k = 1, 3 do
				K:ell("BrothChunk", V3(0.3, 0.06, 0.24), b * CF(-0.4 + k * 0.22, py + potH - 0.115, -0.2 + (k % 2) * 0.3) * ANG(0, k, 0), col(th.broth:Lerp(rgb(150, 110, 80), 0.5)))
			end
		end
		table.insert(srcs, { p = (b * CF(0, py + potH + 0.2, 0)).Position, r = 0.9, rise = 2.4 })
		-- 가스 호스 → 벽
		K:seg("GasHose", (b * CF(0, burnerH - 0.3, -0.3)).Position, (b * CF(0, 0.4, -s / 2 - 0.1)).Position, 0.08, L.of(200, 140, 40))
		K:seg("GasPipe", (b * CF(0, 0.4, -s / 2 - 0.1)).Position, (b * CF(0, 1.5, -s / 2 - 0.14)).Position, 0.1, L.of(220, 190, 40))
		K:box("GasValve", V3(0.36, 0.08, 0.1), b * CF(0, 1.3, -s / 2 - 0.05), L.of(230, 40, 30))
	end
	local puffs = steam(c, srcs, 3)
	return flames, puffs, srcs
end

-- 계산대 (카운터 없는 가게): pcf +Z = 손님 쪽 -------------------------------------------------------------------
local function cashDesk(c: any, pcf: CFrame, w: number, d: number)
	local K, th = c.K, c.th
	local H = 3.3
	local frontL = th.counter and th.counter.frontL or wood(150, 104, 66)
	local topL = th.counter and th.counter.topL or wood(190, 150, 104)
	K:box("CashBody", V3(w - 0.1, H - 0.4, d - 0.15), pcf * CF(0, 0.3 + (H - 0.4) / 2, -0.05), frontL)
	K:box("CashKick", V3(w - 0.3, 0.3, d - 0.4), pcf * CF(0, 0.15, -0.1), L.black)
	K:box("CashTop", V3(w, 0.12, d), pcf * CF(0, H - 0.06, 0), topL)
	for i = 1, 2 do
		K:box("CashMould", V3(w - 0.1, 0.06, 0.04), pcf * CF(0, 0.3 + (H - 0.4) * i / 3, d / 2 - 0.12), dim(frontL, 0.25))
	end
	ktext(K, "CashSign", w * 0.5, 0.5, pcf * CF(0, H * 0.55, d / 2 - 0.1), "계 산", { fg = rgb(250, 240, 220), bg = rgb(120, 30, 26), font = F.GothamBlack })
	local top = pcf * CF(0, H, 0)
	-- POS (직원 쪽을 봄) + 손님 화면
	local pos = top * CF(-w / 2 + 0.7, 0, -0.1)
	K:box("PosBaseNew", V3(0.7, 0.12, 0.6), pos * CF(0, 0.06, 0), L.charcoal)
	K:box("PosNeck", V3(0.12, 0.6, 0.12), pos * CF(0, 0.42, 0), L.charcoal)
	K:box("PosBody", V3(1.1, 0.75, 0.1), pos * CF(0, 0.95, 0) * ANG(math.rad(12), PI, 0), L.charcoal)
	K:text("PosScreenUI", 1.0, 0.62, pos * CF(0, 0.95, -0.07) * ANG(math.rad(-12), PI, 0), "테이블 1   2   3\n4   5   6   7\n결제 대기", { fg = WHITE, bg = rgb(30, 60, 110), glow = 1.0, font = F.GothamMedium })
	K:box("PosCustomer", V3(0.6, 0.4, 0.06), pos * CF(0, 0.7, 0.12) * ANG(math.rad(-10), 0, 0), L.charcoal)
	K:text("PosCustomerUI", 0.54, 0.32, pos * CF(0, 0.7, 0.16) * ANG(math.rad(-10), 0, 0), "감사합니다", { fg = WHITE, bg = rgb(20, 120, 90), glow = 1.0 })
	Props.cardTerminal(K, top * CF(0.1, 0, 0.25))
	Props.receiptPrinter(K, top * CF(0.75, 0, -0.25))
	-- 사탕 · 이쑤시개
	local cb = top * CF(w / 2 - 0.45, 0, 0.3)
	K:vcyl("CandyBowl", 0.22, 0.6, cb * CF(0, 0.11, 0), { c = rgb(230, 240, 240), m = M.Glass, t = 0.4 })
	local candy = { rgb(250, 250, 250), rgb(230, 60, 60), rgb(250, 200, 60) }
	for k = 1, 5 do
		K:ball("Candy", 0.13, cb * CF(-0.15 + (k % 3) * 0.15, 0.18, -0.08 + (k // 3) * 0.16), col(candy[(k % 3) + 1]))
	end
	K:vcyl("ToothpickHolder", 0.32, 0.16, top * CF(w / 2 - 0.95, 0.16, 0.35), L.of(196, 160, 110, M.Wood))
	K:vcyl("Toothpicks", 0.1, 0.12, top * CF(w / 2 - 0.95, 0.37, 0.35), L.of(236, 220, 180, M.Wood))
end

-- TV (벽 브래킷, 채널 순환) ------------------------------------------------------------------------------------
local function tvSet(c: any, dcf: CFrame, w: number)
	local K, th = c.K, c.th
	local h = w * 9 / 16
	K:plate("TVWallPlate", 0.7, 0.8, 0.06, dcf, L.blackMetal)
	for _, sx in { -0.18, 0.18 } do
		K:box("TVArm", V3(0.1, 0.1, 0.55), dcf * CF(sx, 0, 0.33), L.blackMetal)
	end
	local scr = dcf * CF(0, 0, 0.62) * ANG(math.rad(-10), 0, 0)
	K:box("TVBody", V3(w + 0.1, h + 0.1, 0.14), scr * CF(0, 0, 0.07), L.black)
	local chans = {
		{ bg = rgb(26, 92, 44), fg = WHITE, text = "KBO 리그  롯데 3 : 2 삼성\n7회말 2사 1루 · 사직야구장" },
		{ bg = rgb(20, 40, 96), fg = WHITE, text = "뉴스 9\n광안리 불꽃축제 11월 개최 확정" },
		{ bg = rgb(160, 70, 20), fg = rgb(255, 240, 200), text = "생생정보 맛집\n부산 " .. th.title .. " 한 그릇의 비밀" },
		{ bg = rgb(40, 110, 170), fg = WHITE, text = "오늘의 날씨  부산 맑음 22°C\n미세먼지 좋음 · 파고 0.5m" },
		{ bg = rgb(12, 12, 14), fg = rgb(60, 60, 60), text = "" },
	}
	local p, lab = K:text("TVScreen", w, h, scr * CF(0, 0, 0.145), chans[1].text, { fg = chans[1].fg, bg = chans[1].bg, glow = 1.0, font = F.GothamBold, d = 0.02 })
	K:plate("TVLogo", 0.24, 0.04, 0.01, scr * CF(0, -h / 2 - 0.02, 0.145), L.chrome)
	local led = K:plate("TVStandbyLED", 0.05, 0.03, 0.01, scr * CF(w / 2 - 0.1, -h / 2 - 0.02, 0.145), L.ledRed)
	return p, lab, chans
end

-- 벽걸이 선풍기 (날개 회전) ------------------------------------------------------------------------------------
local function wallFan(c: any, dcf: CFrame)
	local K = c.K
	local plastic = L.of(240, 240, 236, M.Plastic)
	K:plate("FanMount", 0.5, 0.7, 0.14, dcf, plastic)
	K:box("FanArm", V3(0.16, 0.16, 0.6), dcf * CF(0, -0.1, 0.44), plastic)
	local head = dcf * CF(0, -0.18, 0.95) * ANG(math.rad(-16), 0, 0)
	K:ell("FanMotor", V3(0.55, 0.55, 0.75), head * CF(0, 0, -0.18), plastic)
	local R = 0.8
	K:ring("FanGuard", head * CF(0, 0, 0.32), R, 0.04, 16, plastic)
	K:ring("FanGuard", head * CF(0, 0, 0.06), R, 0.04, 16, plastic)
	for i = 0, 7 do
		local a = i * PI / 4
		K:seg("FanSpoke", (head * CF(0, 0, 0.34)).Position, (head * CF(math.cos(a) * R, math.sin(a) * R, 0.32)).Position, 0.022, plastic)
	end
	wdisc(K, "FanBadge", 0.28, 0.04, head, 0.33, L.of(40, 110, 190))
	local blades = {}
	for i = 0, 2 do
		local a = i * 2 * PI / 3
		local p = K:ell("FanBlade", V3(0.38, 0.7, 0.04), head * CF(0, 0, 0.19) * ANG(0, 0, a) * CF(0, 0.4, 0) * ANG(0, 0.35, 0), { c = rgb(150, 196, 230), m = M.SmoothPlastic, t = 0.2 })
		table.insert(blades, { p = p, a0 = a })
	end
	wdisc(K, "FanHub", 0.22, 0.1, head, 0.14, plastic)
	local state = { on = true, ang = 0, last = nil :: number? }
	Interact.anim(K, function(t)
		local dt = if state.last then math.clamp(t - (state.last :: number), 0, 0.5) else 0
		state.last = t
		if state.on then
			state.ang += dt * 7
		end
		local wc = K.cf * head * CF(0, 0, 0.19)
		for _, b in blades do
			if b.p.Parent then
				b.p.CFrame = wc * ANG(0, 0, b.a0 + state.ang) * CF(0, 0.4, 0) * ANG(0, 0.35, 0)
			end
		end
	end)
	-- 줄 스위치 (아래로 늘어진 끈 + 손잡이) : 프롬프트 자리
	local drop = 1.3
	local pull = dcf * CF(0.22, -drop, 0.12)
	K:seg("FanCord", (dcf * CF(0.22, -0.3, 0.12)).Position, pull.Position, 0.025, L.of(200, 200, 196))
	local knob = K:ball("FanPullKnob", 0.14, pull, plastic)
	return state, knob
end

-- 식권 발매기 (라멘) ------------------------------------------------------------------------------------------
local function ticketMachine(c: any, pcf: CFrame)
	local K, th = c.K, c.th
	local w, d, h = 1.6, 1.2, 5.0
	K:box("TicketBody", V3(w, h - 0.2, d), pcf * CF(0, 0.2 + (h - 0.2) / 2, 0), L.of(236, 232, 222, M.Metal))
	K:box("TicketPlinth", V3(w - 0.1, 0.2, d - 0.1), pcf * CF(0, 0.1, 0), L.black)
	K:box("TicketTop", V3(w + 0.04, 0.12, d + 0.04), pcf * CF(0, h - 0.06, 0), L.of(180, 30, 26, M.Metal))
	local f = pcf * CF(0, 0, d / 2)
	ktext(K, "TicketHead", w - 0.2, 0.45, f * CF(0, h - 0.45, 0.01), "식권 발매기\n食券", { fg = WHITE, bg = rgb(180, 30, 26), font = F.GothamBlack, d = 0.02 })
	K:text("TicketScreen", w - 0.5, 0.5, f * CF(0, h - 1.1, 0.01), "메뉴를 누르세요\n카드 · 현금", { fg = rgb(20, 40, 30), bg = rgb(150, 220, 170), glow = 0.9, d = 0.02 })
	local names = { "돈코츠", "카라이", "쇼유", "츠케멘", "차슈동", "교자", "아지타마", "차슈", "카에다마", "맥주" }
	local cols, rows = 2, 5
	for i = 1, cols * rows do
		local cI = (i - 1) % cols
		local r = (i - 1) // cols
		local x = -w / 2 + 0.42 + cI * (w - 0.84)
		local y = h - 1.6 - r * 0.42
		local bc = if i <= 4 then rgb(240, 236, 220) else rgb(250, 230, 160)
		ktext(K, "TicketBtn", 0.62, 0.32, f * CF(x, y, 0.01), names[i] or "", { fg = rgb(30, 24, 20), bg = bc, font = F.GothamBold, d = 0.04 })
	end
	K:box("TicketBillSlot", V3(0.5, 0.06, 0.04), f * CF(-0.35, h - 3.85, 0.02), L.black)
	K:box("TicketCardSlot", V3(0.06, 0.4, 0.04), f * CF(0.45, h - 3.85, 0.02), L.black)
	K:box("TicketOut", V3(0.9, 0.3, 0.06), f * CF(0, 0.75, 0.02), L.of(40, 40, 42))
	K:box("TicketPaper", V3(0.4, 0.02, 0.2), f * CF(0, 0.66, 0.08), L.paper)
	K:box("TicketCoin", V3(0.36, 0.22, 0.06), f * CF(0.4, 1.3, 0.02), L.chrome)
end

-- 금색 손 흔드는 고양이 (중식 · 라멘): pcf = 놓는 면
local function luckyCat(c: any, pcf: CFrame, s: number)
	local K = c.K
	local gold = L.of(220, 180, 70, M.Metal, { r = 0.15 })
	local white = L.of(250, 248, 240)
	local body = if c.th.key == "chinese" then gold else white
	K:ell("CatBody", V3(0.5 * s, 0.6 * s, 0.42 * s), pcf * CF(0, 0.3 * s, 0), body)
	K:ball("CatHead", 0.46 * s, pcf * CF(0, 0.75 * s, 0.02 * s), body)
	for _, sx in { -1, 1 } do
		K:wedge("CatEar", V3(0.04 * s, 0.14 * s, 0.14 * s), pcf * CF(sx * 0.13 * s, 0.98 * s, 0) * ANG(0, PI / 2, 0), body)
	end
	K:disc("CatCoin", 0.3 * s, 0.04 * s, pcf * CF(0, 0.3 * s, 0.22 * s) * ANG(PI / 2, 0, 0), L.goldMetal)
	K:box("CatCollar", V3(0.4 * s, 0.05 * s, 0.36 * s), pcf * CF(0, 0.55 * s, 0), L.ledRed)
	local paw = K:ell("CatPaw", V3(0.14 * s, 0.32 * s, 0.14 * s), pcf * CF(0.22 * s, 0.82 * s, 0.05 * s), body)
	local pivot = pcf * CF(0.2 * s, 0.6 * s, 0.05 * s)
	Interact.anim(K, function(t)
		if paw.Parent then
			paw.CFrame = K.cf * pivot * ANG(math.sin(t * 3) * 0.5, 0, 0) * CF(0.02 * s, 0.22 * s, 0)
		end
	end)
end

-- 복어 수족관 (복국): pcf 바닥
local function fishTank(c: any, pcf: CFrame, w: number)
	local K = c.K
	local d, baseH, th = 1.5, 2.6, 1.9
	K:box("TankCabinet", V3(w, baseH, d), pcf * CF(0, baseH / 2, 0), L.of(30, 32, 36))
	K:plate("TankCabinetSeam", 0.03, baseH - 0.4, 0.01, pcf * CF(0, baseH / 2, d / 2), L.of(60, 62, 66))
	K:box("TankBackdrop", V3(w - 0.14, th - 0.22, 0.04), pcf * CF(0, baseH + (th - 0.2) / 2, -d / 2 + 0.1), L.of(70, 150, 200))
	K:box("TankWaterBody", V3(w - 0.12, th - 0.2, d - 0.12), pcf * CF(0, baseH + (th - 0.2) / 2, 0), { c = rgb(150, 210, 235), m = M.Glass, t = 0.7 })
	for k = 1, 3 do
		K:ell("TankRock", V3(0.6 - k * 0.1, 0.35, 0.4), pcf * CF(-w / 2 + 0.5 + k * 0.7, baseH + 0.28, -d / 2 + 0.4), L.of(110, 104, 96, M.Slate))
		K:box("TankWeed", V3(0.08, 0.7 + k * 0.15, 0.08), pcf * CF(w / 2 - 0.4 - k * 0.3, baseH + 0.55 + k * 0.07, -d / 2 + 0.35) * ANG(0, 0, (k - 2) * 0.15), L.of(60, 140, 70, M.Grass))
	end
	K:box("TankGravel", V3(w - 0.14, 0.2, d - 0.14), pcf * CF(0, baseH + 0.1, 0), L.of(190, 176, 150, M.Pebble))
	K:box("TankLid", V3(w, 0.16, d), pcf * CF(0, baseH + th - 0.08, 0), L.of(30, 32, 36))
	local glow = K:box("TankLight", V3(w - 0.3, 0.03, 0.3), pcf * CF(0, baseH + th - 0.17, 0), L.neon(rgb(180, 220, 255)))
	for _, sx in { -1, 1 } do
		K:box("TankCorner", V3(0.06, th, 0.06), pcf * CF(sx * (w / 2 - 0.03), baseH + th / 2, d / 2 - 0.03), L.of(30, 32, 36))
	end
	ktext(K, "TankSign", w * 0.6, 0.3, pcf * CF(0, baseH - 0.3, d / 2 + 0.01), "오늘 들어온 활복", { fg = rgb(255, 240, 200), bg = rgb(20, 50, 90), font = F.GothamBold })
	-- 복어 (노란 · 회색 타원 + 지느러미 + 점)
	local fish = {}
	for i = 1, 3 do
		local y = baseH + 0.6 + i * 0.32
		local f = K:ell("Pufferfish", V3(0.55, 0.4, 0.4), pcf * CF(0, y, (i - 2) * 0.35), L.of(196, 180, 120))
		local belly = K:ell("PufferBelly", V3(0.45, 0.2, 0.32), pcf * CF(0, y - 0.1, (i - 2) * 0.35), L.of(246, 244, 236))
		local tail = K:wedge("PufferTail", V3(0.04, 0.24, 0.2), pcf * CF(-0.32, y, (i - 2) * 0.35) * ANG(0, PI / 2, 0), L.of(170, 150, 100))
		table.insert(fish, { parts = { f, belly, tail }, y = y, z = (i - 2) * 0.35, ph = i * 1.7, spd = 0.3 + i * 0.07 })
	end
	local bub: { BasePart } = {}
	for i = 1, 5 do
		table.insert(bub, K:ball("TankBubble", 0.08, pcf * CF(w / 2 - 0.3, baseH + 0.3 + i * 0.3, -d / 2 + 0.3), { c = WHITE, m = M.Glass, t = 0.4 }))
	end
	local half = w / 2 - 0.5
	Interact.anim(K, function(t)
		for _, f in fish do
			local s = math.sin(t * f.spd + f.ph)
			local x = s * half
			local dir = if math.cos(t * f.spd + f.ph) >= 0 then 0 else PI
			local base = K.cf * pcf * CF(x, f.y + math.sin(t * 1.3 + f.ph) * 0.08, f.z) * ANG(0, dir, 0)
			if f.parts[1].Parent then
				f.parts[1].CFrame = base
				f.parts[2].CFrame = base * CF(0, -0.1, 0)
				f.parts[3].CFrame = base * CF(-0.32, 0, 0) * ANG(0, PI / 2, 0)
			end
		end
		for i, b in bub do
			if b.Parent then
				local f = (t * 0.5 + i / #bub) % 1
				b.CFrame = K.cf * pcf * CF(w / 2 - 0.3 + math.sin(t * 3 + i) * 0.03, baseH + 0.25 + f * (th - 0.5), -d / 2 + 0.3)
			end
		end
	end)
	return glow
end

-- 제면기 (밀면): pcf 바닥, +Z 정면
local function noodlePress(c: any, pcf: CFrame)
	local K = c.K
	local w, d, h = 1.8, 1.5, 3.4
	-- 몸통: 아래 · 위 덩어리 + 양 기둥, 가운데 앞쪽은 면 받는 칸 (h-2.1 .. h-1.2, 깊이 0.6)
	local a0, a1, ad = h - 2.1, h - 1.2, 0.6
	K:box("PressBody", V3(w, a0 - 0.3, d), pcf * CF(0, 0.3 + (a0 - 0.3) / 2, 0), L.steel)
	K:box("PressBody", V3(w, h - a1, d), pcf * CF(0, a1 + (h - a1) / 2, 0), L.steel)
	K:box("PressBody", V3(w - 0.24, a1 - a0, d - ad), pcf * CF(0, (a0 + a1) / 2, -ad / 2), L.brushed)
	for _, sx in { -1, 1 } do
		K:box("PressPillar", V3(0.12, a1 - a0, d), pcf * CF(sx * (w / 2 - 0.06), (a0 + a1) / 2, 0), L.steel)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:vcyl("PressFoot", 0.3, 0.16, pcf * CF(sx * (w / 2 - 0.15), 0.15, sz * (d / 2 - 0.15)), L.black)
		end
	end
	K:vcyl("PressCylinder", 1.4, 0.8, pcf * CF(0, h + 0.7, -0.1), L.chrome)
	K:disc("PressCap", 0.9, 0.12, pcf * CF(0, h + 1.46, -0.1), L.blackMetal)
	K:seg("PressLever", (pcf * CF(0, h + 1.5, -0.1)).Position, (pcf * CF(0.72, h + 1.95, 0.28)).Position, 0.1, L.chrome)
	K:ball("PressLeverKnob", 0.22, pcf * CF(0.74, h + 1.97, 0.3), L.black)

	K:box("PressPanel", V3(0.8, 0.5, 0.04), pcf * CF(0.3, h - 0.6, d / 2 + 0.02), L.charcoal)
	K:plate("PressBtnG", 0.14, 0.14, 0.03, pcf * CF(0.1, h - 0.6, d / 2 + 0.04), L.ledGreen)
	K:plate("PressBtnR", 0.14, 0.14, 0.03, pcf * CF(0.45, h - 0.6, d / 2 + 0.04), L.ledRed)
	-- 면 나오는 구멍 + 면 가닥 → 칸 바닥의 스테인리스 대야
	K:box("PressNozzle", V3(0.5, 0.16, 0.3), pcf * CF(0, a1 - 0.08, d / 2 - ad / 2), L.chrome)
	for i = 1, 5 do
		K:box("PressNoodle", V3(0.03, 0.62, 0.03), pcf * CF(-0.15 + i * 0.05, a1 - 0.47, d / 2 - ad / 2), L.of(220, 196, 150))
	end
	K:vcyl("PressBasin", 0.26, 0.56, pcf * CF(0, a0 + 0.13, d / 2 - ad / 2), L.brushed)
	K:vcyl("PressBasinNoodle", 0.04, 0.46, pcf * CF(0, a0 + 0.24, d / 2 - ad / 2), L.of(220, 196, 150))
	ktext(K, "PressSign", w * 0.9, 0.5, pcf * CF(0, 1.2, d / 2 + 0.01), "주문 즉시 뽑는 생면", { fg = WHITE, bg = rgb(20, 70, 120), font = F.GothamBold })
end

-- 반죽대 (칼국수): 나무 작업대 + 밀가루 · 반죽 · 밀대 · 칼 · 썬 면
local function doughTable(c: any, pcf: CFrame, w: number)
	local K = c.K
	local d, h = 1.8, 3.1
	local top = wood(200, 160, 110)
	K:box("DoughTop", V3(w, 0.2, d), pcf * CF(0, h - 0.1, 0), top)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:box("DoughLeg", V3(0.2, h - 0.2, 0.2), pcf * CF(sx * (w / 2 - 0.2), (h - 0.2) / 2, sz * (d / 2 - 0.2)), dim(top, 0.3))
		end
	end
	K:box("DoughShelf", V3(w - 0.3, 0.1, d - 0.3), pcf * CF(0, 0.5, 0), dim(top, 0.2))
	K:box("FlourSack", V3(1.0, 0.8, 0.7), pcf * CF(-w / 4, 0.95, 0), L.of(236, 230, 214, M.Fabric))
	ktext(K, "FlourLabel", 0.7, 0.3, pcf * CF(-w / 4, 1.0, 0.36), "밀가루 20kg", { fg = rgb(40, 60, 120), font = F.GothamBlack })
	local t = pcf * CF(0, h, 0)
	K:box("DoughSheet", V3(w * 0.5, 0.03, d * 0.6), t * CF(-w * 0.12, 0.015, 0), L.of(244, 236, 216))
	K:ell("DoughBall", V3(0.6, 0.35, 0.6), t * CF(w * 0.3, 0.17, -0.3), L.of(240, 230, 206))
	K:cyl("RollingPin", 1.6, 0.16, t * CF(-w * 0.1, 0.12, 0.3) * ANG(0, 0.2, 0), wood(214, 186, 140))
	K:box("NoodleKnife", V3(0.6, 0.03, 0.3), t * CF(w * 0.18, 0.02, 0.35), L.chrome)
	K:box("NoodleKnifeHandle", V3(0.3, 0.06, 0.08), t * CF(w * 0.18 + 0.45, 0.04, 0.35), wood(60, 40, 28))
	for i = 1, 6 do
		K:box("CutNoodle", V3(0.06, 0.03, 0.8), t * CF(w * 0.3 + i * 0.07, 0.03, 0.35), L.of(240, 230, 206))
	end
	K:ell("FlourDust", V3(0.8, 0.02, 0.5), t * CF(-w * 0.25, 0.02, -0.4), L.of(250, 248, 242))
end

-- 상호작용용 작은 스위치판 (벽) : 반환 = 판 파트
local function wallSwitch(c: any, dcf: CFrame, label: string): BasePart
	local K = c.K
	local p = Props.switchPlate(K, dcf, 1)
	ktext(K, "SwitchLabel", 0.7, 0.18, dcf * CF(0, 0.4, 0.01), label, { fg = rgb(60, 60, 64), font = F.GothamMedium })
	return p
end

-- 배치 ---------------------------------------------------------------------------------------------------
local function nearestWallDist(V: any, p: Vector3): number
	return math.min(p.X - V.x0, V.x1 - p.X, p.Z - V.z0, V.z1 - p.Z)
end

-- 바닥 소품 배치 (벽에 붙임), 조건: 테이블에서 프롬프트 거리 등
local function placeOnWall(c: any, walls: { string }, size: Vector3, near: Vector3?, test: any?, gap: number?): (CFrame?, string?, number?)
	return floorOnWall(c.K, walls, size, near, 0.1, test, gap)
end

-- 소주 · 맥주 냉장고
local function fridgeProp(c: any)
	local K, V = c.K, c.V
	local nd = if V.W > 30 then 2 elseif (c.seed % 2 == 0) then 2 else 1
	local function handlesOK(p: CFrame, n: number): boolean
		local w = n * 2.0 + 0.3
		for i = 1, n do
			local x0 = -w / 2 + 0.15 + (i - 1) * 2.0
			if not promptOK(K, (p * CF(x0 + 2.0 - 0.22, 3.0, 1.15)).Position) then
				return false
			end
		end
		return true
	end
	local pcf: CFrame? = nil
	local tries: { any } = { { n = nd, t = true }, { n = 1, t = true }, { n = nd, t = false } }
	for _, try in tries do
		local n: number = try.n
		local size = V3(n * 2.0 + 0.3, 6.3, 2.0)
		pcf = placeOnWall(c, if c.th.fridgeLeft then { "left", "back", "right" } else { "back", "left", "right" }, size, if c.th.fridgeLeft then V3(V.x0, 0, V.z0 + 3) else V3(V.x0 + V.W * 0.3, 0, V.z0), if try.t then function(p: CFrame)
			return handlesOK(p, n)
		end else nil)
		if pcf then
			nd = n
			break
		end
	end
	if not pcf then
		return
	end
	local doors = drinkFridge(c, pcf, nd)
	at(K, "fridge", nil, nil, pcf.Position)
	for _, dd in doors do
		Interact.swing(K, dd.m, dd.hinge, Vector3.yAxis, -1.7, { object = "음료 냉장고", openText = "문 열기", closeText = "문 닫기" })
	end
	c.fridge = pcf
end

local function selfBarProp(c: any)
	local K, V, th = c.K, c.V, c.th
	local w = if V.W > 30 then 5.6 else 4.8
	local size = V3(w, 4.4, 1.9)
	local near = if c.fridge then c.fridge.Position else V3(V.x0, 0, 0)
	local pcf, wn, u = placeOnWall(c, { "left", "back", "right" }, size, near)
	if not pcf then
		size = V3(4.0, 4.4, 1.9)
		pcf, wn, u = placeOnWall(c, { "left", "back", "right" }, size, near)
		w = 4.0
	end
	if not pcf or not wn or not u then
		return
	end
	selfBar(c, pcf, w, 1.9)
	at(K, "selfbar", nil, nil, pcf.Position)
	-- 위 벽: 셀프코너 간판 + 안내
	local sy = 5.0
	if not usedHit(K, wn, u - w / 2, u + w / 2, sy, sy + 1.4) then
		local d = V:wall(wn, u, sy + 0.45, 0)
		ktext(K, "SelfSign", math.min(3.2, w - 0.6), 0.7, d, th.selfSign, { fg = WHITE, bg = rgb(150, 26, 24), glow = 0.9, font = F.GothamBlack, d = 0.06 })
		ktext(K, "SelfSub", math.min(3.6, w - 0.4), 0.55, d * CF(0, -0.7, 0), th.selfSub, { fg = rgb(40, 40, 44), bg = rgb(252, 250, 244), font = F.GothamBold, d = 0.04, glow = 0.85 })
		claim(K, wn, u - w / 2, u + w / 2, sy - 0.4, sy + 1.4)
	end
	c.selfbar = pcf
end

local function potProp(c: any)
	local K, V, th = c.K, c.V, c.th
	local size = V3(4.0, 3.2, 2.0)
	-- 거리에서 김이 보이게 앞 유리 쪽 옆벽 우선 (창 keep 은 3.4 위만)
	local near = V3(V.x0 + 2, 0, V.z1 - 3)
	local knobSide = -1
	local pcf, wn, u = placeOnWall(c, { "left", "right", "back" }, size, near, function(p: CFrame)
		for _, sd in { -1, 1 } do
			if promptOK(K, (p * CF(sd * (size.X / 2 - 0.3), 0.75, 0.95)).Position) then
				knobSide = sd
				return true
			end
		end
		return false
	end)
	if not pcf then
		size = V3(2.0, 3.2, 2.0)
		pcf, wn, u = placeOnWall(c, { "left", "right", "back" }, size, near)
	end
	if not pcf or not wn or not u then
		return
	end
	local flames, puffs, srcs = potStation(c, pcf, size.X)
	at(K, "pot", nil, nil, pcf.Position)
	-- 불 조절 손잡이 (화구 앞) : 상호작용
	local knob = K:box("BurnerKnob", V3(0.22, 0.22, 0.12), pcf * CF(knobSide * (size.X / 2 - 0.3), 0.75, 0.95), L.of(200, 30, 26))
	local fireOn = true
	Interact.toggle(K, knob, {
		object = "육수 솥 화구",
		onText = "불 줄이기",
		offText = "불 키우기",
		state = true,
		on = function(s: boolean)
			fireOn = s
			for _, fl in flames do
				for _, p in fl do
					if p.Parent then
						p.Material = if s then M.Neon else M.SmoothPlastic
						p.Color = if s then rgb(90, 150, 255) else rgb(50, 50, 54)
					end
				end
			end
			for _, sv in srcs do
				sv.off = not s
			end
		end,
	})
	-- 솥 위 후드 (6.5 위, keep · 천장 설비 피함)
	local hy0 = math.max(6.6, math.min(V.H - 2.0, 7.4))
	local hy1 = V.H - 0.12
	local hd = math.min(2.4, size.Z + 0.4)
	local hc = pcf * CF(0, (hy0 + hy1) / 2, -size.Z / 2 - 0.14 + hd / 2)
	local hsize = V3(size.X + 0.5, hy1 - hy0, hd)
	if hy1 - hy0 > 0.9 and clearAt(K, hc, hsize) and Common.ceilFree(K, hc.Position.X, hc.Position.Z, 0.2) then
		hoodFrame(c, pcf * CF(0, 0, -size.Z / 2 - 0.14 + hd / 2), hsize.X, hd, hy0, hy1)
		claim(K, wn, u - hsize.X / 2 - 0.1, u + hsize.X / 2 + 0.1, hy0 - 0.1, V.H)
	end
	-- 솥 위 벽 글자
	local d = V:wall(wn, u, 4.4, 0)
	if not usedHit(K, wn, u - 1.6, u + 1.6, 3.9, 4.9) then
		ktext(K, "PotSign", 3.0, 0.6, d, if th.key == "haejang" then "새벽부터 끓이는 해장국" elseif th.key == "bok" then "매일 아침 우리는 복 육수" else "24시간 고아내는 사골 육수", { fg = rgb(255, 240, 210), bg = rgb(60, 36, 26), font = F.GothamBlack, d = 0.05, glow = 0.9 })
		claim(K, wn, u - 1.6, u + 1.6, 3.9, 4.9)
	end
	c.pot = pcf
	c.potWall = wn
end

-- 개업 축하 화분 (산세베리아 · 고무나무) + 붉은 리본
local function giftPlant(c: any)
	local K, V = c.K, c.V
	local kind = if c.seed % 2 == 0 then "snake" else "ficus"
	local h = math.clamp(V.H * 0.5, 4.0, 5.4)
	local pcf = placeOnWall(c, { "right", "left", "back" }, V3(1.8, h, 1.8), V3(V.x1, 0, V.z1 - 2.5))
	if not pcf then
		return
	end
	Props.floorPlant(K, pcf, { kind = kind, h = h, dia = 1.4, pot = L.of(250, 250, 246, M.SmoothPlastic) })
	local ph = 1.4 * 0.9
	for i, txt in { "祝 開業", "번창하세요" } do
		local x = (i - 1.5) * 0.42
		local d = pcf * CF(x, ph - 0.95, 0.72) * ANG(0, 0, (i - 1.5) * 0.06)
		ktext(K, "GiftRibbon", 0.32, 1.7, d, vertical(txt), { fg = rgb(255, 230, 150), bg = rgb(190, 20, 30), font = F.GothamBlack, d = 0.02 })
	end
	ktext(K, "GiftTag", 0.9, 0.24, pcf * CF(0, ph + 0.05, 0.71), "광안상가번영회", { fg = rgb(40, 30, 20), bg = rgb(250, 244, 230), font = F.GothamBold, d = 0.02 })
	at(K, "gift", nil, nil, pcf.Position)
end

local function cashProp(c: any)
	local K, V = c.K, c.V
	if #V.counters > 0 or V:has("PosBase") > 0 or V:has("CashDesk") > 0 then
		return
	end
	-- 입구 가까운 옆벽, 벽과 직원 자리 1.6 띄움 (계산대 + 뒤 공간을 한 번에 예약)
	local size = V3(2.6, 3.6, 2.7)
	local near = V3(if V.door and V.door.x > 0 then V.x0 else V.x1, 0, V.z1 - 3)
	local pcf = placeOnWall(c, { "right", "left" }, size, near, function(p: CFrame)
		return p.Position.Z > (V.z0 + V.z1) / 2 - 1
	end)
	if not pcf then
		pcf = placeOnWall(c, { "left", "right", "back" }, size, near)
	end
	if not pcf then
		return
	end
	cashDesk(c, pcf * CF(0, 0, 0.6), 2.6, 1.4)
	at(K, "cash", nil, nil, pcf.Position)
	-- 뒤 벽 : 사업자등록증 · 원산지 (Common 은 카운터 없으면 안 붙임)
	c.cash = pcf
end

local function pressProp(c: any)
	local K, V = c.K, c.V
	local near = if c.pass then V3((c.pass.a + c.pass.b) / 2, 0, V.z0) else V3(0, 0, V.z0)
	local pcf = placeOnWall(c, { "back", "left", "right" }, V3(1.9, 5.7, 1.6), near)
	if pcf then
		noodlePress(c, pcf)
		at(K, "press", nil, nil, pcf.Position)
	end
end

-- 밀면집 온육수 셀프대: 스테인리스 하부장 + 전기 육수 보온통 (꼭지) + 종이컵 디스펜서 + 식초 · 겨자 + 대접 더미
-- pcf +Z = 손님 쪽. 프롬프트: 온육수 따르기 (컵에 따라지는 줄기 + 김, 클라이언트 전용)
local function onyuksuStation(c: any, pcf: CFrame)
	local K, th = c.K, c.th
	local w, d, h = 1.8, 1.2, 2.9
	K:box("OnyukCab", V3(w, h - 0.3, d), pcf * CF(0, 0.3 + (h - 0.3) / 2, 0), L.steel)
	K:box("OnyukKick", V3(w - 0.16, 0.3, d - 0.16), pcf * CF(0, 0.15, -0.04), L.black)
	K:box("OnyukTop", V3(w + 0.06, 0.08, d + 0.04), pcf * CF(0, h + 0.04, 0), L.brushed)
	K:box("OnyukDoorSeam", V3(0.03, h - 0.6, 0.02), pcf * CF(0, 0.3 + (h - 0.3) / 2, d / 2 + 0.005), dim(L.steel, 0.3))
	for _, sx in { -1, 1 } do
		K:box("OnyukHandle", V3(0.05, 0.4, 0.06), pcf * CF(sx * 0.12, h - 0.45, d / 2 + 0.03), L.chrome)
	end
	local top = pcf * CF(0, h + 0.08, 0)
	-- 보온통 (뒤 왼쪽) + 꼭지 + 물받이
	local urn = top * CF(-0.42, 0, -0.12)
	K:vcyl("UrnBody", 1.3, 0.82, urn * CF(0, 0.65 + 0.12, 0), L.chrome)
	K:vcyl("UrnBase", 0.12, 0.9, urn * CF(0, 0.06, 0), L.black)
	K:vcyl("UrnLid", 0.1, 0.86, urn * CF(0, 1.47, 0), L.brushed)
	K:ball("UrnKnob", 0.16, urn * CF(0, 1.58, 0), L.black)
	K:box("UrnLabel", V3(0.5, 0.3, 0.02), urn * CF(0, 0.95, 0.41), L.of(250, 246, 236))
	K:box("UrnLamp", V3(0.08, 0.08, 0.03), urn * CF(0.24, 0.42, 0.4), L.neon(rgb(255, 80, 40)))
	K:box("UrnTap", V3(0.14, 0.12, 0.26), urn * CF(0, 0.34, 0.5), L.chrome)
	K:box("UrnTapLever", V3(0.08, 0.26, 0.06), urn * CF(0, 0.5, 0.6), L.black)
	K:box("UrnDripTray", V3(0.5, 0.06, 0.36), top * CF(-0.42, 0.03, 0.42), L.brushed)
	-- 따르는 줄기 + 컵 (평소엔 안 보임)
	local stream = K:box("UrnStream", V3(0.05, 0.22, 0.05), urn * CF(0, 0.17, 0.6), { c = th.broth, m = M.Glass, t = 1, free = true })
	local cupY = 0.06 + 0.13
	local cup = K:vcyl("PourCup", 0.26, 0.2, top * CF(-0.42, cupY, 0.48), { c = rgb(250, 250, 246), m = M.SmoothPlastic, t = 1, free = true })
	local steamP = K:ell("PourSteam", V3(0.22, 0.16, 0.22), top * CF(-0.42, 0.45, 0.48), { c = rgb(250, 250, 250), m = M.SmoothPlastic, t = 1, free = true })
	-- 종이컵 디스펜서 (오른쪽 뒤, 위로 긴 투명 통)
	local cd = top * CF(0.55, 0, -0.3)
	K:vcyl("CupTube", 1.1, 0.3, cd * CF(0, 0.6, 0), { c = rgb(220, 232, 240), m = M.Glass, t = 0.55 })
	K:vcyl("CupStack", 1.0, 0.24, cd * CF(0, 0.6, 0), L.of(250, 250, 246))
	K:vcyl("CupTubeCap", 0.06, 0.34, cd * CF(0, 1.18, 0), L.chrome)
	K:vcyl("CupTubeFoot", 0.08, 0.36, cd * CF(0, 0.04, 0), L.chrome)
	-- 식초 · 겨자 (짜는 통) + 스테인리스 대접 더미
	local bt = top * CF(0.2, 0, 0.3)
	K:vcyl("Vinegar", 0.5, 0.18, bt * CF(0, 0.25, 0), { c = rgb(236, 222, 170), m = M.Glass, t = 0.3 })
	K:vcyl("VinegarCap", 0.12, 0.12, bt * CF(0, 0.56, 0), L.of(200, 30, 30))
	K:vcyl("Mustard", 0.5, 0.18, bt * CF(0.24, 0.25, 0), L.of(236, 196, 40, M.SmoothPlastic))
	K:vcyl("MustardCap", 0.12, 0.12, bt * CF(0.24, 0.56, 0), L.of(40, 120, 60))
	if not c.lo then
		for j = 1, 4 do
			K:vcyl("BowlStack", 0.12, 0.62, top * CF(0.62, 0.06 + j * 0.11, 0.26), L.brushed)
		end
	end
	-- 앞 이름표
	ktext(K, "OnyukTag", w - 0.2, 0.5, pcf * CF(0, h - 0.95, d / 2 + 0.01), "온육수 · 식초 · 겨자 셀프", { fg = WHITE, bg = rgb(20, 70, 120), font = F.GothamBold, d = 0.02 })
	K:plate("OnyukWarn", 0.5, 0.18, 0.012, urn * CF(0, 0.95, 0.42), L.of(200, 30, 30))
	return { tap = K:box("UrnTapHit", V3(0.5, 0.5, 0.5), urn * CF(0, 0.45, 0.62), { c = WHITE, t = 1, free = true }), stream = stream, cup = cup, steam = steamP }
end

local function onyuksuProp(c: any)
	local K, V, th = c.K, c.V, c.th
	if not th.onyuksu then
		return
	end
	local size = V3(1.9, 4.6, 1.3)
	local near = if c.selfbar then c.selfbar.Position elseif c.fridge then c.fridge.Position else V3(V.x0, 0, 0)
	-- 꼭지 앞에서 프롬프트가 뜨는 자리를 먼저 찾고, 없으면 장식으로만
	local pcf, wn, u = placeOnWall(c, { "left", "back", "right" }, size, near, function(p: CFrame)
		return promptOK(K, (p * CF(-0.42, 3.43, 0.5)).Position)
	end)
	if not pcf then
		pcf, wn, u = placeOnWall(c, { "left", "back", "right" }, size, near)
	end
	if not pcf or not wn or not u then
		return
	end
	local o = onyuksuStation(c, pcf)
	at(K, "onyuksu", nil, nil, pcf.Position)
	-- 위 벽 안내
	if not usedHit(K, wn, u - 1.0, u + 1.0, 4.5, 5.4) then
		signPlate(c, V:wall(wn, u, 4.95, 0), 1.9, 0.75, "따뜻한 온육수\n뜨거우니 조심하세요", rgb(20, 50, 90), rgb(236, 244, 250), { border = rgb(20, 70, 120), font = F.GothamBold })
		claim(K, wn, u - 1.0, u + 1.0, 4.5, 5.4)
	end
	do
		local pouring = false
		Interact.prompt(K, o.tap, {
			action = "따르기",
			object = "온육수",
			fn = function()
				if pouring then
					return
				end
				pouring = true
				o.cup.Transparency = 0
				o.stream.Transparency = 0.25
				o.steam.Transparency = 0.8
				task.delay(1.6, function()
					if o.stream.Parent then
						o.stream.Transparency = 1
					end
				end)
				task.delay(4.5, function()
					if o.cup.Parent then
						o.cup.Transparency = 1
						o.steam.Transparency = 1
					end
					pouring = false
				end)
			end,
		})
	end
end

-- 스탠드형 정수기 (셀프바 옆): 흰 몸통 + 은색 앞판 + 냉 · 온 꼭지 + 물받이 + 종이컵 걸이
local function purifierProp(c: any)
	local K, V, th = c.K, c.V, c.th
	if th.key == "ramen" or th.key == "bistro" or th.onyuksu then
		return -- 밀면집은 온육수 셀프대가 컵 · 물 자리
	end
	local size = V3(1.25, 4.5, 1.25)
	local near = if c.selfbar then c.selfbar.Position elseif c.fridge then c.fridge.Position else V3(V.x0, 0, 0)
	local pcf = placeOnWall(c, { "left", "back", "right" }, size, near)
	if not pcf then
		return
	end
	local w, d, h = 1.1, 1.1, 4.3
	K:rbox("PurifierBody", V3(w, h - 0.15, d), 0.08, pcf * CF(0, 0.15 + (h - 0.15) / 2, 0), L.plasticWhite)
	K:box("PurifierFoot", V3(w - 0.1, 0.15, d - 0.1), pcf * CF(0, 0.075, 0), L.of(70, 72, 76))
	local f = pcf * CF(0, 0, d / 2)
	K:plate("PurifierPanel", w - 0.16, 2.0, 0.03, f * CF(0, h - 1.25, 0), L.brushed)
	-- 꼭지 칸 (움푹 들어간 검은 칸) + 꼭지 2개 + 물받이
	K:plate("PurifierNook", w - 0.3, 0.9, 0.02, f * CF(0, 2.15, 0.03), L.of(40, 42, 46))
	for i, cl in { rgb(40, 120, 220), rgb(220, 40, 30) } do
		local x = (i - 1.5) * 0.36
		K:box("PurifierTap", V3(0.12, 0.16, 0.16), f * CF(x, 2.45, 0.1), L.chrome)
		K:plate("PurifierBtn", 0.2, 0.12, 0.02, f * CF(x, 2.85, 0.05), L.neon(cl))
	end
	K:box("PurifierDrip", V3(w - 0.3, 0.06, 0.32), f * CF(0, 1.72, 0.16), L.chrome)
	K:box("PurifierGrate", V3(w - 0.4, 0.015, 0.24), f * CF(0, 1.76, 0.16), L.of(60, 62, 66, M.DiamondPlate))
	ktext(K, "PurifierLogo", 0.7, 0.18, f * CF(0, h - 0.5, 0.035), "PURE WATER", { fg = rgb(40, 90, 160), font = F.GothamBold, d = 0.01 })
	K:plate("PurifierLED", 0.4, 0.08, 0.02, f * CF(0, h - 0.8, 0.035), L.neon(rgb(80, 180, 255)))
	-- 옆면 종이컵 걸이
	local side = pcf * CF(w / 2, 0, 0)
	K:vcyl("CupHolder", 0.9, 0.24, side * CF(0.14, 2.9, 0.15), { c = rgb(220, 232, 240), m = M.Glass, t = 0.5 })
	K:vcyl("CupHolderCups", 0.8, 0.18, side * CF(0.14, 2.9, 0.15), L.of(250, 250, 246))
	at(K, "purifier", nil, nil, pcf.Position)
end

-- 뚝배기 선반 (육수 솥 옆): 크롬 기둥 3단 선반 + 뚝배기 · 토기 받침 더미
local function ttukRackProp(c: any)
	local K, V, th = c.K, c.V, c.th
	if th.kind ~= "soup" or not c.pot then
		return
	end
	local w, d, h = 1.9, 1.0, 3.3
	-- 솥과 같은 벽, 솥에서 4.5 안쪽만 (멀리 떨어진 선반은 이야기가 안 됨)
	local potP = c.pot.Position
	local pcf = placeOnWall(c, { c.potWall or "back" }, V3(w + 0.1, h + 0.1, d + 0.1), potP, function(p: CFrame)
		return (p.Position - potP).Magnitude < 4.5
	end)
	if not pcf then
		return
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:vcyl("RackPost", h, 0.07, pcf * CF(sx * (w / 2 - 0.04), h / 2, sz * (d / 2 - 0.04)), L.chrome)
		end
	end
	local earth = L.of(70, 44, 32, M.Slate)
	local glaze = L.of(44, 30, 24, M.SmoothPlastic)
	for si, y in { 0.35, 1.45, 2.55 } do
		K:box("RackShelf", V3(w, 0.04, d), pcf * CF(0, y, 0), L.of(150, 154, 160, M.DiamondPlate))
		K:box("RackLip", V3(w, 0.08, 0.03), pcf * CF(0, y + 0.03, d / 2 - 0.015), L.chrome)
		for k = 1, 3 do
			local x = (k - 2) * 0.6
			if si == 3 and k == 2 then
				-- 맨 위 가운데: 나무 받침 더미
				for j = 1, 4 do
					K:box("TtukTray", V3(0.56, 0.06, 0.56), pcf * CF(x, y + 0.02 + (j - 0.5) * 0.065, 0.05), wood(120, 84, 52))
				end
				continue
			end
			local n = math.min(1 + ((k + si + c.seed) % 3), if si == 3 then 2 else 3)
			for j = 1, n do
				local by = y + 0.02 + (j - 1) * 0.3
				K:vcyl("Ttukbaegi", 0.3, 0.5, pcf * CF(x, by + 0.15, 0.05), earth)
				if c.hi then
					K:vcyl("TtukbaegiLip", 0.05, 0.56, pcf * CF(x, by + 0.28, 0.05), glaze)
				end
			end
		end
	end
	at(K, "ttukrack", nil, nil, pcf.Position)
end

-- 사인 액자 벽 (연예인 · 손님 사인 색지): 이름은 지어낸 것, 손글씨 글꼴
local SIGN_TEXTS = {
	"광안리 최고!\n또 올게요\n2025.8", "사장님\n대박나세요 ♡", "JJANG!!\n국밥은 여기", "맛있게\n먹었습니다\n- 부산 야구단", "해장 완료 ^^\n2026.3",
	"부산 오면\n무조건 여기", "Delicious!\nfrom Seoul", "육수 진짜\n미쳤다", "단골 인증\n10년째", "♡ 행복하세요\n2025.12",
}
local function signWall(c: any)
	local K, V, th = c.K, c.V, c.th
	if V.H < 8 or th.key == "bistro" then
		return
	end
	local bw = 0.92
	local y0, y1 = 5.25, 7.55
	local cols, need = 0, 0
	local wn: string?, u: number? = nil, nil
	for _, n in { 4, 3, 2 } do
		need = n * (bw + 0.2) + 0.2
		wn, u = findWall(K, { "left", "right", "back" }, need, need, y0, y1, V3(0, 0, 0), 0.6)
		if wn and u then
			cols = n
			break
		end
	end
	if not wn or not u then
		return
	end
	local papers = { rgb(250, 248, 240), rgb(252, 240, 220), rgb(236, 244, 250) }
	local inks = { rgb(30, 30, 34), rgb(30, 50, 140), rgb(170, 30, 30), rgb(30, 110, 60) }
	local fonts = { F.PermanentMarker, F.IndieFlower, F.PermanentMarker }
	local k = 0
	for row = 1, 2 do
		for col_ = 1, cols do
			k += 1
			local x = (col_ - (cols + 1) / 2) * (bw + 0.2) + (if row == 2 then 0.06 else -0.04)
			local y = (y0 + y1) / 2 + (if row == 1 then 0.56 else -0.56)
			local d = V:wall(wn, u + x, y, 0) * ANG(0, 0, ((k + c.seed) % 3 - 1) * 0.04)
			local i = ((k + c.seed) % #SIGN_TEXTS) + 1
			K:plate("SignBoardEdge", bw + 0.06, bw * 1.12 + 0.06, 0.03, d, L.of(200, 166, 90, M.Metal))
			ktext(K, "SignBoard", bw, bw * 1.12, d * CF(0, 0, 0.03), SIGN_TEXTS[i], { fg = inks[((k + c.seed) % #inks) + 1], bg = papers[((k + c.seed) % #papers) + 1], font = fonts[(k % #fonts) + 1], d = 0.02, glow = 0.85 })
		end
	end
	claim(K, wn, u - need / 2, u + need / 2, y0, y1)
	at(K, "signwall", wn, u)
end

local function doughProp(c: any)
	local K, V = c.K, c.V
	local near = if c.pass then V3((c.pass.a + c.pass.b) / 2, 0, V.z0) else V3(0, 0, V.z0)
	local pcf = placeOnWall(c, { "back", "left", "right" }, V3(3.2, 3.6, 1.8), near)
	if pcf then
		doughTable(c, pcf, 3.2)
		at(K, "dough", nil, nil, pcf.Position)
		local wn, u = nil, nil
	end
end

local function tankProp(c: any)
	local K, V = c.K, c.V
	local pcf = placeOnWall(c, { "left", "right", "back" }, V3(3.4, 4.6, 1.5), V3(V.x0, 0, V.z1 - 4))
	if pcf then
		fishTank(c, pcf, 3.4)
		at(K, "tank", nil, nil, pcf.Position)
	end
end

local function ticketProp(c: any)
	local K, V = c.K, c.V
	local near = V3(if V.door then V.door.x + 6 else 4, 0, V.z1)
	local pcf = placeOnWall(c, { "back", "right", "left" }, V3(1.7, 5.1, 1.3), V3(V.x0 + V.W * 0.5, 0, V.z0))
	if not pcf then
		return
	end
	ticketMachine(c, pcf)
	at(K, "ticket", nil, nil, pcf.Position)
end

-- 벽 꾸미기 ------------------------------------------------------------------------------------------------
-- 지도 간판 (StreetSigns 의 Sign_메뉴 · Sign_화장실 ...) 자리를 벽에서 비움: 실제 게임에서는 주변 Sign_* 파트를 읽고,
-- 못 읽으면 StreetShops 표준 자리 (뒷벽 가운데 14 x 1.8, 높이 H-1.6 · 화장실 문 위 5.6) 를 씀
-- 윗벽 칠 (테마: 라멘 = 짙은 먹색 회벽, 돈카츠 = 크림 회벽): 징두리 위 ~ 천장, 맵 물건 · 문을 피해서
local function upperPaint(c: any)
	local K, V, th = c.K, c.V, c.th
	if V.kind == "gwshop" then
		-- GwShop: 맵 징두리 레일(3.5 - 3.7) 위 벽을 밝은 미색 회벽으로 (얇은 마감, 맵 액자 · 시계 · 선풍기 자리는 V:spans 가 비움)
		local rail = 3.4
		for _, r in V.byName.WainscotRail or {} do
			rail = math.max(rail, r.max.Y)
		end
		local y0, y1 = rail + 0.02, V.H - 0.05
		K:free(function()
			for _, wn in { "left", "right", "back" } do
				for _, sp in V:spans(wn, y0, y1, 0.3) do
					K:plate("UpperPaint", sp[2] - sp[1], y1 - y0, 0.02, V:wall(wn, (sp[1] + sp[2]) / 2, (y0 + y1) / 2, 0.005), L.of(240, 234, 220, M.Plaster))
				end
			end
		end)
		return
	end
	if not th.upper then
		return
	end
	local y0 = (th.lower and th.lower.h or 3.4) + 0.02
	local y1 = V.H - 0.05
	K:free(function()
		for _, wn in { "back", "left", "right" } do
			for _, sp in V:spans(wn, y0, y1, 0.3) do
				K:plate("UpperPaint", sp[2] - sp[1], y1 - y0, 0.02, V:wall(wn, (sp[1] + sp[2]) / 2, (y0 + y1) / 2, 0.005), th.upper)
			end
		end
	end)
end

local function mapSignClaims(c: any)
	local K, V = c.K, c.V
	local found = 0
	local function add(mn: Vector3, mx: Vector3)
		if mx.X > V.x0 - 0.6 and mn.X < V.x1 + 0.6 and mx.Z > V.z0 - 0.6 and mn.Z < V.z1 + 0.6 and mx.Y > 0.5 and mn.Y < V.H then
			for _, wn in { "back", "left", "right" } do
				local u0, d0 = V:wallCoord(wn, mn)
				local u1, d1 = V:wallCoord(wn, mx)
				if math.min(d0, d1) < 0.8 then
					claim(K, wn, math.min(u0, u1) - 0.25, math.max(u0, u1) + 0.25, mn.Y - 0.2, mx.Y + 0.2)
					found += 1
				end
			end
		end
	end
	for _, r in V.parts do
		if string.sub(r.name, 1, 5) == "Sign_" then
			add(r.min, r.max)
		end
	end
	local inside = found
	local scope: Instance? = V.model and V.model.Parent
	if V.kind == "street" and scope and scope ~= workspace and scope:IsA("Model") then
		local n = 0
		for _, d in scope:GetDescendants() do
			n += 1
			if n > 6000 then
				break
			end
			if d:IsA("BasePart") and string.sub(d.Name, 1, 5) == "Sign_" and not d:IsDescendantOf(V.model) then
				local lc = V.cf:ToObjectSpace(d.CFrame)
				local mn, mx = laabb(lc, d.Size)
				add(mn, mx)
			end
		end
	end
	found -= inside
	if V.kind == "street" then
		-- 스트리밍 순서와 상관없이 표준 자리는 항상 비움
		claim(K, "back", -7.3, 7.3, V.H - 2.65, V.H - 0.4)
		for _, r in V.byName.DoorCasing or {} do
			if r.c.Z - V.z0 < 0.5 then
				claim(K, "back", r.c.X - 1.2, r.c.X + 1.2, 5.15, 6.05)
			end
		end
	end
end

-- 사진 메뉴판 한 장 (그릇 사진 + 이름 + 가격)
local function photoMenu(c: any, dcf: CFrame, w: number, h: number, name: string, price: string, kind: string?)
	local K, th = c.K, c.th
	K:plate("PhotoMenuFrame", w + 0.1, h + 0.1, 0.06, dcf, L.of(30, 30, 32, M.Metal))
	K:plate("PhotoMenuBg", w, h, 0.07, dcf, col(rgb(44, 30, 24)))
	local dia = math.min(w * 0.72, h * 0.62)
	bowlArt(c, dcf * CF(0, h / 2 - dia / 2 - 0.12, 0), dia, kind, nil, nil, 0.07)
	ktext(K, "PhotoMenuName", w * 0.9, h * 0.17, dcf * CF(0, -h / 2 + h * 0.22, 0.075), name, { fg = WHITE, font = F.GothamBlack })
	ktext(K, "PhotoMenuPrice", w * 0.8, h * 0.13, dcf * CF(0, -h / 2 + h * 0.08, 0.075), price .. "원", { fg = rgb(255, 210, 80), font = F.GothamBold })
end

local function photoRow(c: any)
	local K, V, th = c.K, c.V, c.th
	if V.H >= 7.6 and th.key ~= "bistro" then
		local ph = math.clamp(V.H - 5.7, 1.9, 2.3)
		local py0 = V.H - 0.4 - ph
		local n = math.min(5, #th.menu)
		local kinds = th.photoKinds or {}
		for _, want in { 5, 4, 3 } do
			if want > n then
				continue
			end
			local need = want * 2.2
			local pwn, pu, pw = findWall(K, { "left", "right", "back" }, need, need, py0 - 0.1, V.H - 0.3, V3(0, 0, V.z0), 0.6)
			if pwn and pu and pw then
				local each = pw / want
				for i = 1, want do
					local it = th.menu[i]
					local d = V:wall(pwn, pu - pw / 2 + each * (i - 0.5), py0 + ph / 2, 0)
					photoMenu(c, d, each - 0.25, ph, it[1], it[2], kinds[i])
				end
				at(K, "photomenu", pwn, pu)
				break
			end
		end
		n = n
	end
end

local function menuWall(c: any)
	local K, V, th = c.K, c.V, c.th
	local y1 = V.H - 0.45
	local yy0 = math.max(5.45, V.H - 4.4)
	local maxW = math.min(7.2, V.W * 0.4)
	local near = if c.pass then V3((c.pass.a + c.pass.b) / 2, 0, V.z0) else V3(0, 0, V.z0)
	local wn, u, w = findWall(K, { "back", "left", "right" }, 4.6, maxW, yy0, y1, near, 0.6)
	if wn and u and w then
		local h = math.min(y1 - yy0, 3.8)
		menuBoard(c, V:wall(wn, u, y1 - h / 2 - 0.05, 0), w - 0.4, h - 0.25, th.menuTitle, th.menu, th.menuStyle, th.shop)
		at(K, "menu", wn, u)
	end
	-- 나무 메뉴패 (후드가 없으면 벽 위쪽)
	if th.tagsOn and not c.hood and V.H >= 8.5 then
		local n = math.min(#th.tags, 8)
		local need = n * 0.95 + 0.4
		local twn, tu, tw = findWall(K, { "left", "right", "back" }, need, need, V.H - 3.0, V.H - 0.35, V3(V.x0, 0, 0), 0.6)
		if twn and tu and tw then
			menuTags(c, V:wall(twn, tu, V.H - 1.65, 0), tw - 0.3, 2.4, th.tags)
			at(K, "tags", twn, tu)
		end
	end
	-- 라멘: 후드 앞면에 나무 메뉴패
	if c.hood and th.tagsOn then
		local hd = c.hood
		local dcf = CFrame.fromMatrix(V3((hd.x0 + hd.x1) / 2, (hd.y0 + hd.y1) / 2 - 0.05, hd.z1 + 0.01), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
		K:free(function()
			menuTags(c, dcf, hd.x1 - hd.x0 - 1.2, math.min(2.2, hd.y1 - hd.y0 - 0.2), th.tags)
		end)
	end
end

local function infoSigns(c: any)
	local K, V, th = c.K, c.V, c.th
	-- 원산지 표시판 (눈높이)
	local near = if c.cash then c.cash.Position elseif c.selfbar then c.selfbar.Position else V3(V.x0, 0, V.z0)
	local wn, u = findWall(K, { "back", "left", "right" }, 2.4, 2.4, 4.0, 7.3, near, 0.7)
	if wn and u then
		originBoard(c, V:wall(wn, u, 5.65, 0), 2.3, 3.1)
		at(K, "origin", wn, u)
	end
	-- 영업시간 · 결제 · 와이파이 묶음
	local wn2, u2 = findWall(K, { "left", "right", "back" }, 2.2, 2.2, 4.2, 6.8, near, 0.7)
	if wn2 and u2 then
		local d = V:wall(wn2, u2, 6.1, 0)
		signPlate(c, d, 2.0, 1.0, table.concat(th.hours, "\n"), rgb(30, 30, 34), rgb(250, 248, 240), { border = rgb(40, 40, 44) })
		signPlate(c, d * CF(0, -1.25, 0), 2.0, 0.7, th.pay, WHITE, rgb(20, 100, 170), { font = F.GothamBold })
	end
	local wn3, u3 = findWall(K, { "right", "left", "back" }, 1.6, 1.6, 4.4, 5.6, V3(V.x1, 0, 0), 0.7)
	if wn3 and u3 then
		local d = V:wall(wn3, u3, 5.0, 0)
		signPlate(c, d, 1.5, 0.95, "WiFi\nID  " .. th.wifi .. "\nPW  " .. tostring(10000000 + c.seed % 89999999), rgb(30, 30, 34), rgb(236, 244, 250), { border = rgb(60, 130, 200) })
	end
	-- 금연 (출입문 쪽 옆벽)
	local wn4, u4 = findWall(K, { "left", "right" }, 1.2, 1.2, 5.6, 7.0, V3(0, 0, V.z1), 0.7)
	if wn4 and u4 then
		local d = V:wall(wn4, u4, 6.3, 0)
		K:plate("NoSmokeBg", 1.1, 1.3, 0.03, d, L.of(250, 250, 248))
		wdisc(K, "NoSmokeRing", 0.66, 0.012, d * CF(0, 0.18, 0), 0.03, L.of(210, 30, 30))
		wdisc(K, "NoSmokeIn", 0.52, 0.014, d * CF(0, 0.18, 0), 0.032, L.of(250, 250, 248))
		K:plate("NoSmokeCig", 0.42, 0.08, 0.01, d * CF(0, 0.18, 0.046), L.of(60, 60, 60))
		K:plate("NoSmokeBar", 0.62, 0.07, 0.012, d * CF(0, 0.18, 0.05) * ANG(0, 0, -0.78), L.of(210, 30, 30))
		ktext(K, "NoSmokeText", 1.0, 0.36, d * CF(0, -0.38, 0.035), "금연구역\n위반 시 과태료 10만원", { fg = rgb(40, 40, 44), font = F.GothamBold })
	end
	-- 평상 안내
	if c.platform then
		local pf = c.platform
		local wn5, u5 = findWall(K, { "right", "left", "back" }, 2.0, 2.4, pf.top + 2.5, pf.top + 3.4, (pf.mn + pf.mx) / 2, 0.5)
		if wn5 and u5 then
			signPlate(c, V:wall(wn5, u5, pf.top + 2.95, 0), 2.2, 0.7, "신발은 벗고 올라가 주세요 ^^\n단체석 예약 환영", rgb(60, 40, 24), rgb(244, 232, 210), { border = rgb(120, 80, 50) })
		end
		-- 옷걸이 레일 (평상 위 벽, 놋쇠 고리 + 걸린 겉옷 하나)
		local wn6, u6, w6 = findWall(K, { "right", "left", "back" }, 2.8, 4.2, pf.top + 3.55, pf.top + 4.75, (pf.mn + pf.mx) / 2, 0.6)
		if wn6 and u6 and w6 then
			local rw = w6 - 0.3
			local d = V:wall(wn6, u6, pf.top + 4.35, 0)
			K:plate("CoatRail", rw, 0.3, 0.06, d, c.th.maruFrame or wood(120, 80, 50))
			local nh = math.max(3, math.floor(rw / 0.7))
			for i = 1, nh do
				local x = -rw / 2 + (i - 0.5) * rw / nh
				K:box("CoatHook", V3(0.06, 0.06, 0.22), d * CF(x, -0.02, 0.17), L.brass)
				K:box("CoatHookTip", V3(0.06, 0.12, 0.05), d * CF(x, 0.04, 0.27), L.brass)
				if i == 2 then
					-- 걸린 점퍼 (몸판 + 소매 + 후드)
					local jc = col(if c.seed % 2 == 0 then rgb(40, 52, 80) else rgb(70, 74, 62), M.Fabric)
					K:box("CoatBody", V3(0.95, 1.5, 0.16), d * CF(x, -0.86, 0.2), jc)
					K:box("CoatHood", V3(0.5, 0.26, 0.2), d * CF(x, -0.06, 0.24), jc)
					for _, sx in { -1, 1 } do
						K:box("CoatSleeve", V3(0.2, 1.2, 0.16), d * CF(x + sx * 0.56, -0.95, 0.19) * ANG(0, 0, sx * 0.08), jc)
					end
					K:box("CoatZip", V3(0.03, 1.4, 0.01), d * CF(x, -0.86, 0.285), L.chrome)
				end
			end
		end
	end
	-- 포장 안내 (계산대 옆)
	if c.cash then
		local wn7, u7 = findWall(K, { "left", "right", "back" }, 1.9, 1.9, 4.0, 5.1, c.cash.Position, 0.7)
		if wn7 and u7 then
			signPlate(c, V:wall(wn7, u7, 4.55, 0), 1.8, 0.8, "포장 됩니다\n" .. (if th.kind == "noodle" then "면 · 육수 따로 포장" else "수육 · 국밥 포장 환영"), WHITE, rgb(196, 40, 30), { border = rgb(250, 240, 220), font = F.GothamBlack })
		end
	end
end

local function clockProp(c: any)
	local K, V = c.K, c.V
	local h = math.min(V.H - 1.4, 7.8)
	local wn, u = findWall(K, { "left", "right", "back" }, 1.6, 1.6, h - 0.8, h + 0.8, V3(0, 0, 0), 0.6)
	if wn and u then
		local d = V:wall(wn, u, h, 0)
		local hr, mn = Props.clock(K, d, 1.4, { frame = wood(90, 60, 40) })
		Interact.clock(K, hr, mn, d, 1.4)
	end
end

local function tvProp(c: any)
	local K, V = c.K, c.V
	local w = if V.W > 30 then 3.6 else 3.0
	local h = w * 9 / 16
	local y = math.min(V.H - 0.6 - h / 2 - 0.3, 8.0)
	local ry = 4.7
	local wn, u = findWall(K, { "left", "right", "back" }, w + 0.4, w + 0.4, y - h / 2 - 0.3, y + h / 2 + 0.2, V3(V.x0, 0, V.z1 - 4), 1.2, function(wn: string, uu: number)
		return promptWallOK(K, wn, uu + w / 2 - 0.2, ry, 0.4) and not usedHit(K, wn, uu + w / 2 - 0.5, uu + w / 2 + 0.1, ry - 0.5, ry + 0.5)
	end)
	if not wn or not u then
		-- 리모컨 자리(프롬프트)가 없으면 TV 만 (방송 화면은 그대로)
		local wn2, u2 = findWall(K, { "left", "right", "back" }, w + 0.4, w + 0.4, y - h / 2 - 0.3, y + h / 2 + 0.2, V3(V.x0, 0, V.z1 - 4), 1.2)
		if wn2 and u2 then
			tvSet(c, V:wall(wn2, u2, y, 0), w)
			at(K, "tv(no remote)", wn2, u2)
		end
		return
	end
	local p, lab, chans = tvSet(c, V:wall(wn, u, y, 0), w)
	at(K, "tv", wn, u)
	-- 리모컨 거치대 (손 닿는 높이)
	local rd = V:wall(wn, u + w / 2 - 0.2, ry, 0)
	claim(K, wn, u + w / 2 - 0.55, u + w / 2 + 0.15, ry - 0.5, ry + 0.5)
	K:plate("RemoteHolder", 0.42, 0.62, 0.16, rd, L.plasticWhite)
	local remote = K:box("TVRemote", V3(0.2, 0.62, 0.08), rd * CF(0, 0.12, 0.13) * ANG(math.rad(-6), 0, 0), L.black)
	K:plate("TVRemoteBtn", 0.08, 0.06, 0.01, rd * CF(0, 0.36, 0.17), L.ledRed)
	ktext(K, "RemoteLabel", 0.42, 0.14, rd * CF(0, -0.22, 0.16), "TV", { fg = rgb(60, 60, 64), font = F.GothamBold })
	if p and lab then
		Interact.cycle(K, remote, chans, {
			action = "채널 돌리기",
			object = "TV 리모컨",
			on = function(_i: number, ch: any)
				lab.Text = ch.text
				lab.BackgroundColor3 = ch.bg
				lab.TextColor3 = ch.fg
				p.Color = ch.bg
			end,
		})
	end
end

local function fanProp(c: any)
	local K, V = c.K, c.V
	local y = math.min(V.H - 1.3, 7.8)
	local wn, u = findWall(K, { "right", "left", "back" }, 1.8, 1.8, y - 1.0, y + 0.8, V3(V.x1, 0, 0), 1.4, function(wn: string, uu: number)
		return promptWallOK(K, wn, uu + 0.22, y - 1.3, 0.4)
	end)
	if not wn or not u then
		return
	end
	local st, knob = wallFan(c, V:wall(wn, u, y, 0))
	at(K, "fan", wn, u)
	Interact.toggle(K, knob, {
		object = "벽걸이 선풍기",
		onText = "끄기",
		offText = "켜기",
		state = true,
		on = function(s: boolean)
			st.on = s
		end,
	})
end

-- 매장 음악 (벽 앰프 + LCD 곡명 + 이퀄라이저 막대 + 모서리 스피커): 곡 바꾸기
local TRACKS: { [string]: { any } } = {
	ramen = { { "♪ 시티팝 플레이리스트", "1984 · Plastic Love" }, { "♪ J-ROCK", "하카타 라이브 하우스" }, { "♪ 엔카 라디오", "후쿠오카 FM" }, { "■ 정지", "" } },
	katsu = { { "♪ 재즈 피아노", "Autumn Leaves" }, { "♪ 로파이 비트", "Rainy Gwangalli" }, { "♪ 보사노바", "Wave" }, { "■ 정지", "" } },
	bistro = { { "♪ 이탈리안 칸초네", "Volare" }, { "♪ 재즈 트리오", "Fly Me to the Moon" }, { "♪ 어쿠스틱", "바다곁 플레이리스트" }, { "■ 정지", "" } },
	default = { { "♪ 트로트 메들리", "부산갈매기" }, { "♪ 7080 가요", "해운대 연가" }, { "♪ 라디오", "부산 MBC FM4U" }, { "■ 정지", "" } },
}

local function bgmProp(c: any)
	local K, V, th = c.K, c.V, c.th
	local wn, u = findWall(K, { "left", "right", "back" }, 1.6, 1.6, 4.0, 5.4, V3(V.x0, 0, V.z1 - 3), 0.5, function(wn: string, uu: number)
		return promptWallOK(K, wn, uu, 4.7)
	end)
	if not wn or not u then
		return
	end
	local d = V:wall(wn, u, 4.7, 0)
	K:plate("AmpBody", 1.4, 0.8, 0.3, d, L.of(28, 28, 30, M.Metal))
	K:plate("AmpFace", 1.3, 0.7, 0.02, d * CF(0, 0, 0.3), L.of(46, 46, 50, M.Metal))
	local list = TRACKS[th.key] or TRACKS.default
	local p, lab = K:text("AmpLCD", 0.9, 0.3, d * CF(-0.12, 0.12, 0.32), list[1][1] .. "\n" .. list[1][2], { fg = rgb(140, 230, 255), bg = rgb(10, 24, 40), glow = 1.2, font = F.GothamMedium, d = 0.02 })
	for i, x in { 0.42, 0.56 } do
		wdisc(K, "AmpKnob", 0.16, 0.06, d * CF(x, 0.12, 0), 0.32, L.chrome)
		i = i
	end
	local bars = {}
	for i = 1, 7 do
		table.insert(bars, K:plate("AmpEQ", 0.08, 0.2, 0.02, d * CF(-0.48 + i * 0.12, -0.2, 0.32), L.ledGreen))
	end
	ktext(K, "AmpLabel", 1.2, 0.14, d * CF(0, -0.5, 0), "매장 음악", { fg = rgb(60, 60, 64), font = F.GothamBold })
	-- 모서리 스피커 2개 (천장 아래)
	for _, side in { -1, 1 } do
		local wn2 = if wn == "back" then "back" else wn
		local w = V.walls[wn2]
		local uu = if side < 0 then w.a + 0.9 else w.b - 0.9
		local sd = V:wall(wn2, uu, V.H - 1.0, 0)
		if not usedHit(K, wn2, uu - 0.5, uu + 0.5, V.H - 1.5, V.H - 0.4) and clearAt(K, sd * CF(0, 0, 0.3), V3(0.8, 1.1, 0.6)) then
			K:box("WallSpeaker", V3(0.7, 1.0, 0.55), sd * CF(0, 0, 0.32) * ANG(math.rad(-12), 0, 0), L.of(30, 30, 32))
			K:plate("WallSpeakerGrille", 0.56, 0.84, 0.02, sd * CF(0, 0, 0.6) * ANG(math.rad(-12), 0, 0), L.of(60, 60, 64, M.Fabric))
			claim(K, wn2, uu - 0.5, uu + 0.5, V.H - 1.5, V.H - 0.4)
		end
	end
	local playing = true
	Interact.anim(K, function(t)
		for i, b in bars do
			if b.Parent then
				local hgt = if playing then 0.06 + 0.22 * math.abs(math.sin(t * (2.2 + i * 0.7) + i)) else 0.03
				b.Size = V3(0.08, hgt, 0.02)
				b.CFrame = K.cf * d * CF(-0.48 + i * 0.12, -0.3 + hgt / 2, 0.33)
			end
		end
	end)
	if p and lab then
		Interact.cycle(K, p, list, {
			action = "곡 바꾸기",
			object = "매장 음악",
			on = function(_i: number, tr: any)
				lab.Text = tr[1] .. (if tr[2] ~= "" then "\n" .. tr[2] else "")
				playing = tr[2] ~= ""
			end,
		})
	end
	at(K, "bgm", wn, u)
end

local function calendarProp(c: any)
	local K, V = c.K, c.V
	local wn, u = findWall(K, { "back", "left", "right" }, 1.7, 1.7, 4.6, 7.2, V3(V.x0 + 2, 0, V.z0), 0.6)
	if wn and u then
		calendar(c, V:wall(wn, u, 5.9, 0))
		at(K, "calendar", wn, u)
	end
end

-- 이야기 액자 (한지 바탕 + 나무 테): 부산 돼지국밥 · 밀면의 유래
local STORIES: { [string]: { string } } = {
	gukbap = { "부산 돼지국밥 이야기", "6·25 피란 시절, 부산에 모인 사람들이\n돼지 뼈와 머리 고기를 푹 고아 나눠 먹던\n한 그릇이 오늘의 돼지국밥이 되었습니다.\n새우젓 · 부추 · 다대기는 입맛대로!" },
	milmyeon = { "밀면 이야기", "1950년대 피란 온 이북 사람들이\n메밀 대신 구호물자 밀가루로 냉면을 뽑은 것이\n부산 밀면의 시작입니다.\n식초 · 겨자는 두 바퀴, 기호에 맞게!" },
}
local function storyBoard(c: any, yc: number)
	local K, V, th = c.K, c.V, c.th
	local st = STORIES[th.key]
	if not st then
		return
	end
	local wn, u = findWall(K, { "left", "right", "back" }, 3.3, 3.3, yc - 1.25, yc + 1.25, V3(0, 0, 0), 0.7)
	if not wn or not u then
		return
	end
	local d = V:wall(wn, u, yc, 0)
	K:plate("StoryFrame", 3.2, 2.3, 0.08, d, wood(84, 56, 36))
	K:plate("StoryPaper", 2.96, 2.06, 0.1, d, L.of(236, 224, 196, M.Fabric))
	ktext(K, "StoryTitle", 2.6, 0.36, d * CF(0, 0.78, 0.1), st[1], { fg = rgb(120, 30, 24), font = F.GothamBlack })
	ktext(K, "StoryBody", 2.7, 1.3, d * CF(0, -0.2, 0.1), st[2], { fg = rgb(50, 36, 26), font = F.GothamMedium })
	-- 낙관 (빨간 도장)
	K:plate("StorySeal", 0.2, 0.2, 0.105, d * CF(1.25, -0.85, 0), L.of(190, 30, 26))
	at(K, "story", wn, u)
end

-- 남은 빈 벽을 포스터 · 액자로 채움
local function postersFill(c: any)
	local K, V, th = c.K, c.V, c.th
	local placed = 0
	local yc = math.min(6.0, V.H - 2.4)
	storyBoard(c, yc)
	for i, ps in th.posters do
		local wide = (i % 2 == 1)
		local w, h = if wide then 4.2 else 2.4, if wide then 2.4 else 3.2
		local wn, u = findWall(K, { "left", "right", "back" }, w + 0.3, w + 0.3, yc - h / 2 - 0.1, yc + h / 2 + 0.1, if i == 1 then V3(V.x0, 0, 0) else V3(V.x1, 0, 0), 0.7)
		if wn and u then
			foodPoster(c, V:wall(wn, u, yc, 0), w, h, ps)
			at(K, "poster", wn, u)
			placed += 1
		end
	end
	-- 방송 출연 액자
	local wn, u = findWall(K, { "back", "left", "right" }, 2.9, 2.9, yc - 1.0, yc + 1.0, V3(0, 0, V.z0), 0.7)
	if wn and u then
		tvFrame(c, V:wall(wn, u, yc, 0), 2.8, 1.8)
	end
	-- 넓은 벽에 남은 자리: 큰 포스터 하나 더 (순서 바꿔)
	if #th.posters > 0 then
		for k = 1, 2 do
			local ps = th.posters[((k + c.seed) % #th.posters) + 1]
			local wn2, u2 = findWall(K, { "left", "right", "back" }, 3.8, 3.8, yc - 1.3, yc + 1.3, V3(0, 0, 0), 0.7)
			if wn2 and u2 then
				foodPoster(c, V:wall(wn2, u2, yc, 0), 3.6, 2.4, ps)
			end
		end
	end
end

-- 라멘 · 중식 등 (천장 등 + 스위치)
local function lanternsProp(c: any)
	local K, V, th = c.K, c.V, c.th
	local spots = {}
	if c.upstand then
		local up = c.upstand
		local n = math.max(2, math.floor(up.size.X / 3.4))
		for i = 1, n do
			local x = up.min.X + up.size.X * (i - 0.5) / n
			for _, dz in { 1.0, 0.6, 1.5, 2.2 } do
				if Common.ceilFree(K, x, up.c.Z + dz, 0.6) then
					table.insert(spots, V3(x, V.H, up.c.Z + dz))
					break
				end
			end
		end
	else
		for _, t in V.tables do
			if #spots < 6 and t.kind ~= "low" then
				table.insert(spots, V3((t.min.X + t.max.X) / 2, V.H, (t.min.Z + t.max.Z) / 2))
			end
		end
	end
	local lamps = {}
	local txt = if th.key == "ramen" then "라멘" elseif th.key == "chinese" then "福" else nil
	for i, p in spots do
		if Common.ceilFree(K, p.X, p.Z, 0.6) then
			local dia, h = 1.1, 1.5
			local cy = V.H - 0.35 - h / 2
			local mn, mx = V3(p.X - dia / 2, cy - h / 2 - 0.6, p.Z - dia / 2), V3(p.X + dia / 2, V.H, p.Z + dia / 2)
			if K:hitsKeep(mn, mx) == nil then
				local b = lantern(c, p, dia, h, txt, if th.key == "chinese" then rgb(214, 30, 24) else nil)
				table.insert(lamps, b)
				Common.useCeil(K, p.X, p.Z)
				if i == 1 then
					K:light(b, "PointLight", { Range = 12, Brightness = 0.8, Color = rgb(255, 150, 110) })
				end
			end
		end
	end
	if #lamps == 0 then
		return
	end
	-- 벽 스위치 (테이블 · 카운터에서 먼 벽)
	local wn, u = findWall(K, { "left", "right", "back" }, 1.0, 1.0, 3.8, 4.8, V3(V.x0, 0, V.z1 - 3), 0.5, function(wn: string, uu: number)
		return promptWallOK(K, wn, uu, 4.3, 0.4)
	end)
	if wn and u then
		local sw = wallSwitch(c, V:wall(wn, u, 4.3, 0), "홍등")
		local base = {}
		for _, b in lamps do
			table.insert(base, b.Color)
		end
		local lightsOf = {}
		for _, b in lamps do
			for _, l in b:GetChildren() do
				if l:IsA("Light") then
					table.insert(lightsOf, l)
				end
			end
		end
		Interact.toggle(K, sw, {
			object = if th.key == "ramen" then "붉은 등 (초칭)" else "홍등",
			onText = "끄기",
			offText = "켜기",
			state = true,
			on = function(s: boolean)
				for i2, b in lamps do
					if b.Parent then
						b.Color = if s then base[i2] else (base[i2] :: Color3):Lerp(Color3.new(0, 0, 0), 0.55)
					end
				end
				for _, l in lightsOf do
					(l :: Light).Enabled = s
				end
			end,
		})
	end
end

local function catProp(c: any)
	local K, V = c.K, c.V
	-- 계산대 위 / 냉장고 위 / 벽 선반
	if c.cash then
		local top = c.cash * CF(0, 3.3, 0.75)
		luckyCat(c, top * CF(-1.0, 0, 0.2), 1.0)
		return
	end
	local wn, u = findWall(K, { "back", "left", "right" }, 1.4, 1.4, 5.6, 7.4, V3(0, 0, V.z0), 0.8)
	if wn and u then
		local at = Props.shelf(K, V:wall(wn, u, 5.8, 0), 1.3, { depth = 0.7, look = wood(90, 60, 40) })
		luckyCat(c, at * CF(0, 0, -0.05), 1.1)
	end
end

-- 라멘: 일본 술병 (1.8L 됫병 · 위스키 · 소주) — base = 선반 윗면 위 병 바닥 가운데
local function sakeBottle(K: any, base: CFrame, kind: number, hi: boolean)
	if kind == 0 or kind == 2 then
		-- 됫병 (짙은 갈색 / 초록 유리 + 흰 라벨)
		local gl = if kind == 0 then { c = rgb(70, 40, 20), m = M.Glass, t = 0.1 } else { c = rgb(30, 70, 40), m = M.Glass, t = 0.1 }
		K:vcyl("SakeBody", 0.95, 0.36, base * CF(0, 0.475, 0), gl)
		K:ell("SakeShoulder", V3(0.36, 0.24, 0.36), base * CF(0, 0.95, 0), gl)
		K:vcyl("SakeNeck", 0.26, 0.14, base * CF(0, 1.12, 0), gl)
		K:vcyl("SakeCap", 0.08, 0.16, base * CF(0, 1.27, 0), L.of(200, 170, 80, M.Metal))
		if hi then
			K:plate("SakeLabel", 0.24, 0.46, 0.01, base * CF(0, 0.52, 0.178), L.of(244, 236, 214))
			K:plate("SakeLabelMark", 0.1, 0.26, 0.012, base * CF(0, 0.55, 0.179), L.of(if kind == 0 then 30 else 170, if kind == 0 then 24 else 30, 20))
		end
	elseif kind == 1 then
		-- 하이볼 위스키 (각진 병)
		K:box("WhiskyBody", V3(0.34, 0.62, 0.22), base * CF(0, 0.31, 0), { c = rgb(190, 120, 40), m = M.Glass, t = 0.15 })
		K:vcyl("WhiskyNeck", 0.2, 0.1, base * CF(0, 0.72, 0), { c = rgb(190, 120, 40), m = M.Glass, t = 0.15 })
		K:vcyl("WhiskyCap", 0.08, 0.13, base * CF(0, 0.86, 0), L.black)
		if hi then
			K:plate("WhiskyLabel", 0.26, 0.2, 0.01, base * CF(0, 0.3, 0.11), L.of(240, 226, 190))
		end
	else
		-- 소주 (초록 병 · 짧음)
		K:vcyl("ShochuBody", 0.5, 0.24, base * CF(0, 0.25, 0), { c = rgb(40, 140, 80), m = M.Glass, t = 0.15 })
		K:vcyl("ShochuNeck", 0.2, 0.11, base * CF(0, 0.6, 0), { c = rgb(40, 140, 80), m = M.Glass, t = 0.15 })
	end
end

-- 라멘 식당 벽: 높은 술 선반 · '맛있게 먹는 법' 액자 · 노보리 현수막 · 오늘의 한정 칠판
local function ramenWall(c: any)
	local K, V, th = c.K, c.V, c.th
	if th.key ~= "ramen" then
		return
	end
	local dining = V3(if c.upstand then (if c.upstand.c.X < 0 then V.x1 - V.W * 0.25 else V.x0 + V.W * 0.25) else 0, 0, V.z0)
	-- 1) 높은 선반 (7.3 위: 원산지 · 냉장고 위) + 술병 · 됫병
	if V.H >= 9.2 then
		local wn, u, w = findWall(K, { "back", "right", "left" }, 3.2, 5.2, 7.35, 8.9, dining, 0.8)
		if wn and u and w then
			local sw = w - 0.2
			local top = Props.shelf(K, V:wall(wn, u, 7.55, 0), sw, { depth = 0.6, look = wood(96, 64, 42) })
			local n = math.floor((sw - 0.4) / 0.5)
			for i = 1, n do
				local x = -(sw - 0.4) / 2 + (i - 0.5) * (sw - 0.4) / n
				sakeBottle(K, top * CF(x, 0, -0.02), (i + c.seed) % 4, c.hi)
			end
		end
	end
	-- 2) 노보리 (세로 천 현수막) 두 장
	local wn3, u3 = findWall(K, { "back", "right", "left" }, 2.1, 2.1, 3.95, 7.45, dining, 0.6)
	if wn3 and u3 then
		for i, txt in { "豚骨 라멘", "차슈 듬뿍" } do
			local d = V:wall(wn3, u3 + (i - 1.5) * 1.02, 5.7, 0)
			K:plate("NoboriPole", 1.0, 0.08, 0.1, d * CF(0, 1.66, 0), L.of(150, 110, 70, M.Wood))
			K:plate("NoboriCloth", 0.88, 3.25, 0.04, d, col(if i == 1 then rgb(246, 240, 226) else rgb(170, 30, 26), M.Fabric))
			K:plate("NoboriBand", 0.88, 0.26, 0.05, d * CF(0, 1.5, 0), col(if i == 1 then rgb(170, 30, 26) else rgb(30, 24, 20), M.Fabric))
			ktext(K, "NoboriText", 0.66, 2.6, d * CF(0, -0.18, 0.05), vertical(txt), { fg = if i == 1 then rgb(30, 22, 18) else rgb(255, 240, 210), font = F.GothamBlack })
		end
	end
	-- 3) '맛있게 먹는 법' 나무 액자 (눈높이)
	local wn2, u2 = findWall(K, { "back", "right", "left" }, 2.8, 2.8, 4.0, 7.0, dining, 0.7)
	if wn2 and u2 then
		local d = V:wall(wn2, u2, 5.5, 0)
		K:plate("HowToFrame", 2.7, 3.0, 0.08, d, wood(70, 46, 30))
		K:plate("HowToPaper", 2.45, 2.75, 0.1, d, L.of(240, 230, 206))
		ktext(K, "HowToTitle", 2.2, 0.42, d * CF(0, 1.08, 0.1), "라멘 맛있게 먹는 법", { fg = rgb(170, 30, 24), font = F.GothamBlack })
		K:plate("HowToRule", 2.1, 0.03, 0.105, d * CF(0, 0.82, 0), L.of(150, 110, 70))
		ktext(K, "HowToBody", 2.15, 1.9, d * CF(0, -0.25, 0.1), "① 국물 먼저 한 숟갈\n② 면은 바로, 불기 전에\n③ 반쯤 먹고 마늘 · 생강 추가\n④ 면 추가 (카에다마) 2,000원\n   면 익힘: 카타 · 보통 · 야와", { fg = rgb(40, 30, 22), font = F.GothamBold, align = "Left" })
	end
	-- 4) 오늘의 한정 칠판
	local wn4, u4 = findWall(K, { "back", "right", "left" }, 2.1, 2.1, 4.4, 6.9, dining, 0.7)
	if wn4 and u4 then
		menuBoard(c, V:wall(wn4, u4, 5.65, 0), 1.8, 1.9, "오늘의 한정", { { "마제소바", "12,000" }, { "아부리 차슈동", "9,000" }, { "미소 라멘", "12,500" } }, "chalk")
	end
end

-- 비스트로 (파스타 · 와인): 칠판 · 와인 상자 · 허브 화분 · 올리브유 · 치즈
local function bistroProp(c: any)
	local K, V = c.K, c.V
	-- 와인 상자 쌓음 (바닥, 벽에 붙임)
	local pcf = placeOnWall(c, { "right", "left", "back" }, V3(2.2, 2.6, 1.4), V3(V.x1, 0, 0))
	if pcf then
		for i = 0, 2 do
			local y = i * 0.85
			local b = pcf * CF((i % 2) * 0.15 - 0.07, y, 0)
			K:box("WineCrate", V3(2.0, 0.8, 1.3), b * CF(0, 0.4, 0), wood(186, 146, 100))
			K:box("WineCrateSlat", V3(2.02, 0.08, 1.32), b * CF(0, 0.6, 0), wood(150, 112, 76))
			ktext(K, "WineCrateMark", 1.2, 0.3, b * CF(0, 0.38, 0.66), "VINO ROSSO · 2023", { fg = rgb(90, 30, 30), font = F.SpecialElite })
			for j = 1, 4 do
				K:cyl("CrateBottle", 0.6, 0.24, b * CF(-0.75 + j * 0.3, 0.88 + 0.12, 0.2) * ANG(0, PI / 2, 0), { c = rgb(40, 60, 30), m = M.Glass, t = 0.1 })
			end
		end
	end
	-- 허브 화분 선반 + 올리브유
	local wn, u = findWall(K, { "left", "right", "back" }, 3.0, 3.0, 5.2, 6.6, V3(V.x0, 0, 0), 0.7)
	if wn and u then
		local at = Props.shelf(K, V:wall(wn, u, 5.4, 0), 3.0, { depth = 0.8, look = wood(120, 84, 56) })
		Props.row(K, at * CF(-0.75, 0, 0), 1.5, "plants", { seed = c.seed })
		Props.row(K, at * CF(0.75, 0, 0), 1.5, "bottles", { colors = { rgb(120, 140, 40), rgb(80, 100, 30) }, seed = c.seed })
	end
	-- 이탈리아 국기 띠 액자
	local wn2, u2 = findWall(K, { "right", "left", "back" }, 2.6, 2.6, 5.0, 7.4, V3(V.x1, 0, 0), 0.7)
	if wn2 and u2 then
		Props.frame(K, V:wall(wn2, u2, 6.2, 0), 2.4, 2.2, { frame = wood(80, 56, 38), art = { { rgb(0, 140, 70), 0, 0, 0.333, 1 }, { rgb(244, 244, 240), 0.333, 0, 0.334, 1 }, { rgb(206, 40, 52), 0.667, 0, 0.333, 1 } }, text = "TRATTORIA\nGWANGALLI", fg = rgb(30, 30, 30) })
	end
end

-- 펜던트 조명 밝기 (비스트로): 우리 불빛 밝기 단계
local function dimmerProp(c: any)
	local K, V = c.K, c.V
	local wn, u = findWall(K, { "left", "right", "back" }, 1.0, 1.0, 3.8, 4.8, V3(V.x0, 0, V.z1 - 3), 0.5, function(wn: string, uu: number)
		return promptWallOK(K, wn, uu, 4.3, 0.4)
	end)
	if not wn or not u then
		return
	end
	local d = V:wall(wn, u, 4.3, 0)
	K:plate("DimmerPlate", 0.5, 0.7, 0.04, d, L.of(40, 40, 42))
	local knob = wdisc(K, "DimmerKnob", 0.28, 0.08, d, 0.04, L.brass)
	ktext(K, "DimmerLabel", 0.8, 0.16, d * CF(0, 0.5, 0.01), "조명 밝기", { fg = rgb(60, 60, 64), font = F.GothamMedium })
	local base = {}
	for _, l in K.lights do
		table.insert(base, { l = l, b = (l :: any).Brightness })
	end
	local levels = { { "100%", 1.0 }, { "70%", 0.7 }, { "40%", 0.4 }, { "촛불 모드", 0.18 } }
	Interact.cycle(K, knob, levels, {
		action = "밝기 바꾸기",
		object = "펜던트 조명",
		on = function(_i: number, lv: any)
			for _, r in base do
				if r.l.Parent then
					(r.l :: any).Brightness = r.b * lv[2]
				end
			end
		end,
	})
	at(K, "dimmer", wn, u)
end

-- 거꾸로 붙인 복(福) 마름모 (중식): 빨간 마름모 + 금색 글자 (복이 들어온다)
local function fuProp(c: any)
	local K, V = c.K, c.V
	for i = 1, 3 do
		local wn, u = findWall(K, { "left", "right", "back" }, 1.7, 1.7, 5.3, 7.1, V3(if i == 2 then V.x1 else V.x0, 0, (i - 2) * 4), 0.6)
		if not wn or not u then
			break
		end
		local d = V:wall(wn, u, 6.2, 0) * ANG(0, 0, PI / 4)
		K:plate("FuDiamondRim", 1.25, 1.25, 0.03, d, L.goldMetal)
		K:plate("FuDiamond", 1.1, 1.1, 0.05, d, L.of(190, 20, 20))
		ktext(K, "FuText", 0.8, 0.8, d * CF(0, 0, 0.05) * ANG(0, 0, PI * 3 / 4), "福", { fg = rgb(255, 214, 90), font = F.GothamBlack })
		K:seg("FuTassel", (V:wall(wn, u, 6.2 - 0.88, 0.04)).Position, (V:wall(wn, u, 6.2 - 1.5, 0.04)).Position, 0.08, L.of(200, 20, 20, M.Fabric))
		at(K, "fu", wn, u)
	end
end

-- 텍스 천장 LED 평판등 (국밥 · 해장국 · 밀면 · 칼국수): 맵 형광등 줄 사이, 벽에서 3.5 이상 (후드 · 솥 자리 비움)
local function ceilPanels(c: any)
	local K, V, th = c.K, c.V, c.th
	if not ((th.kind == "soup" or th.kind == "noodle") and th.key ~= "ramen" and th.key ~= "bistro") then
		return
	end
	-- GwShop (넓은 홀, 맵 형광등 3줄뿐이라 어두움): 천장 마감 위 평판등을 더 달고 불빛도 하나 더
	local gw = V.kind == "gwshop"
	local maxLit = if gw then 4 else 3
	local want = math.clamp(math.floor(V.W * V.D / 80), 3, if gw then 10 else 8)
	local nx = math.max(2, math.floor((V.W - 7.2) / 6.5 + 0.5))
	local zs = { V.z0 + V.D * 0.2, (V.z0 + V.z1) / 2, V.z1 - V.D * 0.2 }
	local placed, lit = 0, 0
	for j, z0 in zs do
		for i = 1, nx do
			if placed >= want then
				break
			end
			local x = V.x0 + 3.6 + (V.W - 7.2) * (i - 0.5) / nx
			local z: number? = nil
			for _, dz in { 0, 1.3, -1.3, 2.4, -2.4 } do
				local zz = z0 + dz
				if zz > V.z0 + 3.5 and zz < V.z1 - 1.5 and Common.ceilFree(K, x, zz, 1.15) then
					z = zz
					break
				end
			end
			if z then
				local withLight = (i + j) % 2 == 0 and lit < maxLit and #K.lights < (V.maxLights or 8) - 2
				Props.panelLight(K, x, z, { light = withLight, range = 18, bright = 0.85, color = L.coolLight, glow = L.lampCool })
				Common.useCeil(K, x, z)
				placed += 1
				if withLight then
					lit += 1
				end
			end
		end
	end
	K:note(string.format("panels %d lit %d", placed, lit))
end

-- GwShop 가구 감싸기: 원본(Table_n · Seat)은 숨기지도 옮기지도 않고, 조금 더 큰 덮개로 감쌈 (윗면 +0.006)
local function gwFurniture(c: any)
	local K, V, th = c.K, c.V, c.th
	local topL = th.table.top
	local edgeL = th.table.edge
	local metal = L.of(60, 62, 66, M.Metal)
	local function sleeve(r: any, look: any, pad: number)
		K:box("Sleeve", r.size + V3(pad, 0.004, pad), CF(r.c), look)
	end
	for _, t in V.tables do
		local mn, mx = t.min, t.max
		for _, r in V.byName.TableEdge or {} do
			if r.c.X > mn.X - 0.3 and r.c.X < mx.X + 0.3 and r.c.Z > mn.Z - 0.3 and r.c.Z < mx.Z + 0.3 then
				mn, mx = mn:Min(r.min), mx:Max(r.max)
			end
		end
		local low = t.kind == "low"
		local y = t.y + 0.006
		local thick = y - mn.Y + 0.02
		local w, l = mx.X - mn.X + 0.03, mx.Z - mn.Z + 0.03
		local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
		K:free(function()
			K:slab("GwTableTop", w, l, thick, 0.08, CF(cx, y - thick / 2, cz), if low then th.lowTop else topL)
			K:slab("GwTableBand", w + 0.02, l + 0.02, 0.05, 0.08, CF(cx, y - thick - 0.02, cz), if low then dim(th.lowTop, 0.35) else edgeL)
			for _, r in t.parts do
				if r.name == "TableLeg" or r.name == "LowTableLeg" or r.name == "TableFoot" then
					sleeve(r, if low then dim(th.lowTop, 0.4) else metal, 0.05)
				end
			end
		end)
	end
	for i, ch in V.chairs do
		local sr = ch.seat
		local isCushion = sr.name == "Cushion" or sr.name == "SeatCushion"
		if sr.part:IsA("Seat") and sr.part.Transparency >= 0.99 and not isCushion then
			continue
		end
		K:free(function()
			if isCushion then
				local cc: Color3 = th.cushion[((i + c.seed) % #th.cushion) + 1]
				K:slab("GwBangseok", sr.size.X + 0.06, sr.size.Z + 0.06, sr.size.Y + 0.01, 0.22, CF(sr.c.X, sr.c.Y + 0.003, sr.c.Z), col(cc, M.Fabric))
				K:slab("GwBangseokPipe", sr.size.X + 0.09, sr.size.Z + 0.09, 0.04, 0.24, CF(sr.c.X, sr.max.Y - 0.05, sr.c.Z), col(cc:Lerp(rgb(255, 220, 140), 0.45), M.Fabric))
			else
				local sh = sr.size.Y + 0.08
				K:box("GwStoolSeat", V3(sr.size.X + 0.08, sh, sr.size.Z + 0.08), CF(sr.c.X, sr.max.Y + 0.006 - sh / 2, sr.c.Z), th.stool.seat or L.leatherRed)
				K:box("GwStoolPipe", V3(sr.size.X + 0.12, 0.05, sr.size.Z + 0.12), CF(sr.c.X, sr.max.Y - sh * 0.55, sr.c.Z), dim(th.stool.seat or L.leatherRed, 0.45))
				for _, r in ch.parts do
					if r.name == "StoolLeg" or r.name == "StoolPost" then
						sleeve(r, L.chrome, 0.05)
					end
				end
				for _, q in V.byName.StoolRing or {} do
					if math.abs(q.c.X - sr.c.X) < 0.8 and math.abs(q.c.Z - sr.c.Z) < 0.8 then
						K:box("GwStoolRing", q.size + V3(0.05, 0.03, 0.05), CF(q.c), L.chrome)
					end
				end
			end
		end)
	end
end

-- GwShop (행복 돼지국밥): 마감 · 장식만 (R14) ------------------------------------------------------------------
local function gwshopDecor(c: any)
	local K, V, th = c.K, c.V, c.th
	-- 빈 벽 위쪽: 사진 메뉴 줄 (높이 6.5 위, 테이블 · 통로와 무관)
	photoRow(c)
	-- 눈높이 안내 (GwShop 에 이미 있는 원산지 · 셀프 안내는 빼고): 영업시간 · 결제 · 와이파이 · 금연
	local near = V3(V.x1, 0, V.z1 - 6)
	local wn2, u2 = findWall(K, { "right", "left" }, 2.2, 2.2, 4.2, 6.8, near, 0.7)
	if wn2 and u2 then
		local d = V:wall(wn2, u2, 6.1, 0)
		signPlate(c, d, 2.0, 1.0, table.concat(th.hours, "\n"), rgb(30, 30, 34), rgb(250, 248, 240), { border = rgb(40, 40, 44) })
		signPlate(c, d * CF(0, -1.25, 0), 2.0, 0.7, th.pay, WHITE, rgb(20, 100, 170), { font = F.GothamBold })
		at(K, "gwinfo", wn2, u2)
	end
	local wn3, u3 = findWall(K, { "left", "right" }, 1.6, 1.6, 4.4, 5.6, V3(V.x0, 0, V.z1 - 6), 0.7)
	if wn3 and u3 then
		signPlate(c, V:wall(wn3, u3, 5.0, 0), 1.5, 0.95, "WiFi\nID  HAENGBOK_GUKBAP\nPW  " .. tostring(20000000 + c.seed % 79999999), rgb(30, 30, 34), rgb(236, 244, 250), { border = rgb(60, 130, 200) })
	end
	calendarProp(c)
	-- 평상 안내 (평상 위 벽)
	if c.platform then
		local pf = c.platform
		local wn5, u5 = findWall(K, { "left", "right", "back" }, 2.4, 2.4, pf.top + 2.5, pf.top + 3.4, (pf.mn + pf.mx) / 2, 0.5)
		if wn5 and u5 then
			signPlate(c, V:wall(wn5, u5, pf.top + 2.95, 0), 2.2, 0.7, "신발은 벗고 올라가 주세요 ^^\n단체석 예약 환영", rgb(60, 40, 24), rgb(244, 232, 210), { border = rgb(120, 80, 50) })
		end
	end
	-- 빈 벽에 포스터 · 방송 액자 · 선풍기
	postersFill(c)
	fanProp(c)
end

-- 본체 --------------------------------------------------------------------------------------------------
function T.build(K: any, V: any, S: any)
	local th = S.__theme or themeFor(V)
	local c: any = { K = K, V = V, S = S, th = th, seed = th.seed or 1, hi = K.detail == "high", lo = K.detail == "low" }
	local function step(name: string, fn: (any) -> ())
		if not budget(K, 40) then
			K:note("korean." .. name .. ": skipped (part budget)")
			return
		end
		local ok, err = pcall(fn, c)
		if not ok then
			K:note("korean." .. name .. ": " .. tostring(err))
		end
	end
	K:note("theme " .. tostring(th.key))
	if V.kind == "gwshop" then
		-- GwShop (국밥 알바): Table_n · Seat · TrayPoint · PassTray · Point 는 그대로 둠. 평상 · 벽 · 천장 장식만
		step("panels", ceilPanels)
		step("upper", upperPaint)
		step("platform", platformOver)
		step("gwfurniture", gwFurniture)
		step("mapsigns", mapSignClaims)
		step("gwshop", gwshopDecor)
		return
	end
	step("panels", ceilPanels)
	step("seats", seatsOver)
	step("tables", tablesOver)
	step("platform", platformOver)
	step("mapsigns", mapSignClaims)
	step("upper", upperPaint)
	step("pass", passOver)
	step("fakepass", fakePass)
	step("bar", barOver)
	local f = th.feat or {}
	-- 바닥 소품 (벽 자리를 먼저 잡음)
	if f.fridge then
		step("fridge", fridgeProp)
	end
	if f.cash then
		step("cash", cashProp)
	end
	if f.selfbar then
		step("selfbar", selfBarProp)
		step("purifier", purifierProp)
	end
	if f.pot then
		step("pot", potProp)
		step("ttukrack", ttukRackProp)
	end
	if f.press then
		step("press", pressProp)
	end
	if th.onyuksu then
		step("onyuksu", onyuksuProp)
	end
	if th.key ~= "bistro" then
		step("gift", giftPlant)
	end
	if f.dough then
		step("dough", doughProp)
	end
	if f.tank then
		step("tank", tankProp)
	end
	if f.ticket then
		step("ticket", ticketProp)
	end
	if f.bistro then
		step("bistro", bistroProp)
		step("dimmer", dimmerProp)
	end
	-- 벽 (높은 것 먼저: 메뉴판 · TV · 선풍기 · 시계, 그다음 눈높이 안내판 · 포스터)
	step("menu", menuWall)
	if f.tv then
		step("tv", tvProp)
	end
	if f.fan then
		step("fan", fanProp)
	end
	step("clock", clockProp)
	if f.bgm then
		step("bgm", bgmProp)
	end
	step("photomenu", photoRow)
	step("signs", infoSigns)
	if f.calendar then
		step("calendar", calendarProp)
	end
	if f.cat then
		step("cat", catProp)
	end
	if f.fu then
		step("fu", fuProp)
	end
	if th.key == "ramen" then
		step("ramenwall", ramenWall)
	end
	if th.kind == "soup" or th.kind == "noodle" then
		step("signwall", signWall)
	end
	step("posters", postersFill)
	if f.lanterns then
		step("lanterns", lanternsProp)
	end
end

return T
