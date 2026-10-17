--!strict
-- GwangalliBuildingInterior/T_grill: 유형 (grill · pocha) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (테마별 바닥 · 징두리 · 걸레받이 · 카운터 · 펜던트)
--   build(K, V, S) 유형별 디테일. 테마 = 가게 이름 · 메뉴 · 맵 내용물로 고름:
--     clam (부산 조개구이) · gopchang (한우 곱창 · 막창) · bbq (숯불 돼지갈비)
--     pochaTent (실내포차: 주황 · 파랑 · 빨강 천막 천장 + 전구 줄) · pochaBar (다찌 카운터 포차: 오뎅 바)
--     pocha24 (24시 포차 · 해장: 벽 둘레 천막 처마 + 형광등 + 평상)
--   공통 구성 (맵 가구는 같은 자세 · 같은 윗면으로 덮고 원본은 숨김, R3/R4):
--     불판 테이블 (스테인리스 상판 · 드럼통 / 캐비닛 / 기둥 받침) + 숯 화로 (재 · 숯 · 불씨 · 석쇠) + 원형 후드 · 신축 덕트
--     천장 메인 덕트 (스파이럴 이음 · 행거 · 벽 플랜지) · 플라스틱 원형 스툴 (색 섞임) · 레드 비닐 의자 · 방석 · 평상
--     소주 냉장고 (유리문 · 초록 소주병 · 갈색 맥주병 · 캔) · 아이스 진열대 (가리비 · 키조개 · 전복 · 새우 / 고무 다라이 해삼 ·
--     멍게 · 개불 · 산낙지 / 곱창 · 대창 · 막창 / 갈비 · 삼겹) + 가격표
--     메뉴판 (파란 라이트박스 · 나무 간판 · 손글씨 색지 메뉴 줄, 2026 부산 가격) · 원산지 표시판 · 영업시간 · 결제 (동백전) ·
--     와이파이 · 청소년 주류 판매 금지 · 사인지 벽 · 소주 포스터 · 앞치마 걸이 · 셀프 코너 · 소주 박스 · 스탠드 에어컨 ·
--     주방 문 (STAFF ONLY) · 벽걸이 TV (롯데 야구) · 벽걸이 선풍기 · 환풍기 · 벽시계
--   상호작용 (이 클라이언트만, 주문 · 계산 · 앉기와 겹치지 않음): 선풍기 켜기 · 환풍기 켜기 · TV 채널 · 냉장고 문 ·
--     전구 줄 켜기 — 프롬프트는 서버 앵커 · 테이블에서 6.5 넘게 떨어진 벽에만.

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))

local T = {}
T.types = { "grill", "pocha" }

local L = Look
local M = Enum.Material
local F = Enum.Font
local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local rgb = Color3.fromRGB
local WHITE = rgb(255, 255, 255)
local INK = rgb(24, 24, 28)

-- 공용 도우미 ------------------------------------------------------------------------------------------
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

local function lift(look: any, f: number): any
	return L.with(look, { c = (look.c :: Color3):Lerp(Color3.new(1, 1, 1), f) })
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

-- 표시면(dcf) 앞을 보는 원판: dcf 의 +Z 쪽 z..z+t
local function wdisc(K: any, name: string, dia: number, t: number, dcf: CFrame, z: number, look: any): BasePart
	return K:make("Part", name, V3(t, dia, dia), dcf * CF(0, 0, z + t / 2) * ANG(0, PI / 2, 0), look, Enum.PartType.Cylinder)
end

local function txt(K: any, name: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3, bg: Color3?, font: Enum.Font?, o: any?): (BasePart, TextLabel)
	local opts: any = { fg = fg, bg = bg, font = font or F.GothamBold }
	if o then
		for k, v in o do
			opts[k] = v
		end
	end
	return K:text(name, w, h, dcf, s, opts)
end

-- 이름 가진 맵 파트 중 xz 상자 안 (pad 여유)
local function within(V: any, name: string, mn: Vector3, mx: Vector3, pad: number): { any }
	local out = {}
	for _, r in V.byName[name] or {} do
		if r.c.X > mn.X - pad and r.c.X < mx.X + pad and r.c.Z > mn.Z - pad and r.c.Z < mx.Z + pad then
			table.insert(out, r)
		end
	end
	return out
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
			if mapClear(V, mn, mx) and not usedHit(K, wn, cu - size.X / 2, cu + size.X / 2, 0, size.Y) and (not test or test(pcf, wn, cu)) and K:spot(pcf, size, pad or 0.1, "grill") then
				claim(K, wn, cu - size.X / 2 - 0.15, cu + size.X / 2 + 0.15, 0, size.Y + 0.2)
				return pcf, wn, cu
			end
		end
	end
	return nil, nil, nil
end

-- 프롬프트 자리: 서버 앵커 6.5 + 테이블 (ShopLife Table_n 앵커) · 카운터 6.6 밖
local function promptOK(c: any, lp: Vector3): boolean
	local K, V = c.K, c.V
	if not Interact.canPrompt(K, lp) then
		return false
	end
	for _, t in V.tables do
		local tc = (t.min + t.max) / 2
		if V3(tc.X - lp.X, 0, tc.Z - lp.Z).Magnitude < 6.6 then
			return false
		end
	end
	return true
end

local function promptWallOK(c: any, wn: string, u: number, y: number): boolean
	local V = c.V
	for _, du in { -0.5, 0, 0.5 } do
		if not promptOK(c, V:wall(wn, u + du, y, 0.4).Position) then
			return false
		end
	end
	return true
end

local function at(K: any, what: string, wn: string?, u: number?)
	K:note(string.format("%s @ %s u=%.1f", what, tostring(wn), u or 0))
end

-- 지도 간판 (StreetSigns 의 Sign_메뉴 · Sign_화장실 ...) 자리를 벽에서 비움 (V:spans 는 Sign_* 쉘을 안 봄)
local function signClaims(c: any)
	local K, V = c.K, c.V
	local function add(mn: Vector3, mx: Vector3)
		if mx.X > V.x0 - 0.6 and mn.X < V.x1 + 0.6 and mx.Z > V.z0 - 0.6 and mn.Z < V.z1 + 0.6 and mx.Y > 0.5 and mn.Y < V.H then
			for _, wn in { "back", "left", "right" } do
				local u0, d0 = V:wallCoord(wn, mn)
				local u1, d1 = V:wallCoord(wn, mx)
				if math.min(d0, d1) < 0.8 then
					claim(K, wn, math.min(u0, u1) - 0.3, math.max(u0, u1) + 0.3, mn.Y - 0.25, mx.Y + 0.25)
				end
			end
		end
	end
	for _, r in V.parts do
		if string.sub(r.name, 1, 5) == "Sign_" or r.name == "ExitSign" then
			add(r.min, r.max)
		end
	end
	local scope: Instance? = V.model and V.model.Parent
	if scope and scope ~= workspace and scope:IsA("Model") then
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
	if V.kind == "street" then
		-- 스트리밍 순서와 상관없이 표준 메뉴판 자리 (뒷벽 가운데 14 x 1.8, 높이 H-1.6) · 화장실 표지 자리는 항상 비움
		claim(K, "back", -7.4, 7.4, V.H - 2.7, V.H - 0.3)
		for _, r in V.byName.DoorCasing or {} do
			if r.c.Z - V.z0 < 0.5 then
				claim(K, "back", r.c.X - 1.3, r.c.X + 1.3, 5.1, 6.1)
			end
		end
	end
end

-- 테마 --------------------------------------------------------------------------------------------------
local RED_PL = rgb(206, 38, 36)
local BLUE_PL = rgb(30, 92, 196)
local GREEN_PL = rgb(40, 150, 80)
local ORANGE_PL = rgb(236, 120, 30)

local POCHA_SHEETS = {
	{ "해물탕", "38,000" }, { "오뎅탕", "18,000" }, { "닭발", "19,000" }, { "꼼장어 구이", "25,000" },
	{ "조개탕", "18,000" }, { "계란말이", "13,000" }, { "해물파전", "17,000" }, { "골뱅이 무침", "20,000" },
	{ "오징어 숙회", "20,000" }, { "똥집 튀김", "16,000" }, { "김치전", "13,000" }, { "알탕", "18,000" },
	{ "라면", "5,000" }, { "우동", "7,000" }, { "소주", "5,000" }, { "맥주", "5,000" }, { "막걸리", "5,000" },
}

local THEMES: { [string]: any } = {
	clam = {
		key = "clam",
		grill = true,
		title = "조개구이",
		shop = "조개구이",
		accent = rgb(22, 88, 168),
		accent2 = rgb(255, 206, 40),
		floor = { look = L.of(124, 128, 130, M.Slate), tile = 2.0, grout = L.of(92, 94, 98) },
		lower = { kind = "tile", h = 3.6, look = L.of(236, 240, 242, M.CeramicTiles), grout = L.of(178, 190, 200), tw = 1.0, th = 1.0, walls = { "back", "left", "right" } },
		band = rgb(26, 96, 178),
		base = L.of(28, 60, 110),
		top = L.of(210, 214, 218, M.SmoothPlastic, { r = 0.16 }),
		edge = L.of(36, 36, 40, M.Rubber),
		tableBase = "cabinet",
		stools = { RED_PL, RED_PL, RED_PL, RED_PL, RED_PL, BLUE_PL },
		light = rgb(236, 244, 255),
		lamp = L.lampCool,
		menuStyle = "blue",
		menu = {
			{ "조개구이 모듬 (소)", "45,000" }, { "조개구이 모듬 (중)", "55,000" }, { "조개구이 모듬 (대)", "65,000" },
			{ "가리비 치즈구이", "35,000" }, { "키조개 관자구이", "30,000" }, { "전복 버터구이", "35,000" },
			{ "왕새우 소금구이", "30,000" }, { "민물장어 (1마리)", "28,000" },
		},
		side = { { "조개탕", "15,000" }, { "해물라면", "6,000" }, { "치즈 추가", "3,000" }, { "김치볶음밥", "4,000" }, { "소주", "5,000" }, { "맥주", "5,000" }, { "음료", "2,000" } },
		sideTitle = "식사 · 주류",
		origin = "원산지 표시\n가리비 · 키조개 : 국내산 (통영 · 보령)\n전복 : 국내산 (완도) · 새우 : 국내산\n장어 : 국내산 (고창)\n쌀 · 배추김치 · 고춧가루 : 국내산",
		hours = "영업시간\n12:00 - 02:00\n연중무휴",
		fridgeHeader = "시원한 소주 · 맥주",
		fridgeBg = rgb(22, 96, 60),
		display = "ice",
		displaySign = "산지직송 활 조개 · 매일 아침 입고",
		catch = {
			{ "scallop", "가리비\n1kg 25,000" }, { "pen", "키조개\n1개 8,000" }, { "abalone", "전복\n1kg 70,000" },
			{ "clam", "백합\n1kg 20,000" }, { "shrimp", "왕새우\n1kg 38,000" }, { "ark", "피조개\n1kg 18,000" },
		},
		aprons = { rgb(196, 30, 36), rgb(30, 60, 120), rgb(196, 30, 36), rgb(36, 36, 40), rgb(196, 30, 36) },
		posters = { { "치즈 가리비\n출시!", rgb(255, 206, 40), rgb(22, 88, 168) }, { "부산 바다\n한 상 가득", WHITE, rgb(20, 120, 150) } },
		tv = true,
		exhaust = true,
		kitchenDoor = true,
		selfBar = true,
		crates = true,
		station = true,
	},
	gopchang = {
		key = "gopchang",
		grill = true,
		title = "곱창 · 막창",
		shop = "곱창",
		accent = rgb(196, 40, 30),
		accent2 = rgb(250, 230, 190),
		floor = { look = L.of(84, 80, 78, M.Concrete), tile = 0, grout = L.of(70, 66, 64) },
		lower = { kind = "paint", h = 3.6, look = L.of(150, 70, 52, M.Brick), cap = L.of(70, 46, 32, M.Wood), walls = { "back", "left", "right" } },
		base = L.of(54, 36, 26, M.Wood),
		top = L.of(210, 214, 218, M.SmoothPlastic, { r = 0.16 }),
		edge = L.of(40, 40, 44, M.Metal),
		tableBase = "drum",
		drums = { rgb(168, 40, 32), rgb(168, 40, 32), rgb(40, 84, 140) },
		stools = { RED_PL, RED_PL, RED_PL, RED_PL, ORANGE_PL },
		light = rgb(255, 222, 186),
		lamp = L.lampWarm,
		menuStyle = "wood",
		menu = {
			{ "한우 소곱창 (200g)", "22,000" }, { "한우 대창 (200g)", "23,000" }, { "돼지 막창 (300g)", "16,000" },
			{ "한우 염통 (200g)", "16,000" }, { "모듬 구이 (2인)", "45,000" }, { "곱창 전골 (2인)", "32,000" },
		},
		side = { { "볶음밥", "3,000" }, { "부추 추가", "2,000" }, { "된장찌개", "5,000" }, { "공기밥", "1,000" }, { "소주", "5,000" }, { "맥주", "5,000" }, { "음료", "2,000" } },
		sideTitle = "식사 · 주류",
		origin = "원산지 표시\n소곱창 · 대창 · 염통 : 국내산 (한우)\n돼지막창 : 국내산\n쌀 · 배추김치 · 고춧가루 : 국내산\n부추 · 양파 : 국내산",
		hours = "영업시간\n16:00 - 02:00\n매주 월요일 휴무",
		fridgeHeader = "소주 · 맥주 · 음료",
		fridgeBg = rgb(160, 30, 30),
		display = "meat",
		displaySign = "당일 손질 한우 곱창",
		catch = { { "gopchang", "소곱창\n200g 22,000" }, { "daechang", "대창\n200g 23,000" }, { "makchang", "막창\n300g 16,000" }, { "heart", "염통\n200g 16,000" } },
		aprons = { rgb(36, 36, 40), rgb(160, 30, 30), rgb(36, 36, 40), rgb(160, 30, 30) },
		posters = { { "곱창엔\n소주 한잔", WHITE, rgb(160, 30, 30) }, { "1983\n그 시절 그 맛", rgb(250, 230, 190), rgb(70, 46, 32) } },
		tv = true,
		exhaust = true,
		kitchenDoor = true,
		selfBar = true,
		crates = true,
		station = false,
	},
	bbq = {
		key = "bbq",
		grill = true,
		title = "숯불구이",
		shop = "숯불구이",
		accent = rgb(214, 120, 40),
		accent2 = rgb(246, 238, 220),
		floor = { look = L.of(70, 70, 74, M.Slate), tile = 2.0, grout = L.of(50, 50, 54) },
		lower = { kind = "louver", h = 3.8, look = L.of(96, 66, 44, M.Wood), back = L.of(30, 26, 24), pitch = 0.5, walls = { "back", "left", "right" } },
		base = L.of(26, 24, 22),
		top = L.of(44, 44, 48, M.Metal),
		edge = L.of(150, 154, 158, M.Metal),
		tableBase = "pedestal",
		stools = { rgb(46, 46, 50), rgb(46, 46, 50), rgb(120, 70, 40) },
		light = rgb(255, 214, 170),
		lamp = L.lampWarm,
		menuStyle = "wood",
		menu = {
			{ "숯불 돼지갈비 (250g)", "17,000" }, { "생삼겹살 (180g)", "17,000" }, { "목살 (180g)", "17,000" },
			{ "항정살 (150g)", "19,000" }, { "양념 소갈비 (250g)", "33,000" }, { "가브리살 (150g)", "18,000" },
		},
		side = { { "물냉면 · 비빔냉면", "8,000" }, { "된장찌개", "5,000" }, { "계란찜", "5,000" }, { "공기밥", "1,000" }, { "소주", "5,000" }, { "맥주", "5,000" } },
		sideTitle = "식사 · 주류",
		origin = "원산지 표시\n돼지고기 : 국내산\n소갈비 : 미국산\n쌀 · 배추김치 : 국내산\n숯 : 국내산 참숯",
		hours = "영업시간\n11:30 - 24:00\n연중무휴",
		fridgeHeader = "소주 · 맥주",
		fridgeBg = rgb(30, 30, 34),
		display = "meat",
		displaySign = "숙성실 · 오늘의 고기",
		catch = { { "galbi", "돼지갈비\n250g 17,000" }, { "pork", "삼겹살\n180g 17,000" }, { "neck", "목살\n180g 17,000" }, { "jowl", "항정살\n150g 19,000" } },
		aprons = { rgb(36, 36, 40), rgb(110, 70, 44), rgb(36, 36, 40) },
		posters = { { "참숯 직화\n돼지갈비", rgb(246, 238, 220), rgb(30, 26, 24) }, { "점심 특선\n갈비탕 11,000", WHITE, rgb(214, 120, 40) } },
		tv = true,
		exhaust = true,
		kitchenDoor = true,
		selfBar = true,
		crates = true,
		station = true,
	},
}

-- 포차 (실내포차): 천막 색은 가게 이름으로
local TARPS = {
	{ name = "orange", a = rgb(244, 124, 38), b = rgb(244, 124, 38), trim = rgb(252, 238, 212) },
	{ name = "blue", a = rgb(40, 96, 180), b = rgb(40, 96, 180), trim = rgb(244, 244, 240) },
	{ name = "red", a = rgb(214, 44, 38), b = rgb(214, 44, 38), trim = rgb(250, 238, 214) },
}

local function pochaTheme(V: any, layout: string): any
	local h = hash(V.name or "pocha")
	local tarp = TARPS[(h % #TARPS) + 1]
	if string.find(V.name or "", "해물", 1, true) then
		tarp = TARPS[1]
	end
	local th: any = {
		key = layout,
		grill = layout == "pochaTent",
		pocha = true,
		title = "포장마차",
		shop = "포차",
		tarp = tarp,
		accent = rgb(220, 40, 30),
		accent2 = rgb(255, 220, 60),
		floor = { look = L.of(118, 116, 112, M.Concrete), tile = 0, grout = L.of(90, 88, 86) },
		lower = { kind = "louver", h = 3.4, look = L.of(176, 132, 84, M.WoodPlanks), back = L.of(60, 44, 30), pitch = 0.62, walls = { "back", "left", "right" } },
		base = L.of(54, 40, 28, M.Wood),
		top = L.of(212, 214, 216, M.SmoothPlastic, { r = 0.16 }),
		edge = L.of(150, 40, 34, M.Plastic),
		tableBase = "drum",
		drums = { rgb(40, 84, 150), rgb(168, 40, 32), rgb(40, 120, 70) },
		stools = { RED_PL, BLUE_PL, RED_PL, GREEN_PL, RED_PL, BLUE_PL },
		light = rgb(255, 206, 150),
		lamp = L.lampWarm,
		menuStyle = "sheets",
		sheets = POCHA_SHEETS,
		origin = "원산지 표시\n꼼장어 : 국내산 (기장) · 닭발 : 국내산\n오징어 : 원양산 · 홍합 · 조개 : 국내산\n쌀 · 배추김치 · 고춧가루 : 국내산",
		hours = "영업시간\n18:00 - 05:00\n연중무휴",
		fridgeHeader = "소주 · 맥주 · 막걸리",
		fridgeBg = rgb(200, 36, 30),
		display = "basin",
		displaySign = "오늘 들어온 해산물",
		catch = {
			{ "seacucumber", "해삼\n한접시 20,000" }, { "squirt", "멍게\n한접시 15,000" }, { "spoonworm", "개불\n한접시 20,000" },
			{ "octopus", "산낙지\n1마리 15,000" }, { "abalone", "전복\n3미 25,000" }, { "conch", "소라\n한접시 18,000" },
		},
		aprons = { rgb(200, 36, 30), rgb(36, 84, 160), rgb(200, 36, 30) },
		posters = { { "홍합탕\n서비스!", rgb(255, 230, 60), rgb(200, 36, 30) }, { "롯데 이기면\n소주 한병 서비스", WHITE, rgb(20, 40, 90) } },
		tv = true,
		fan = true,
		exhaust = layout == "pochaTent",
		kitchenDoor = layout == "pochaTent",
		selfBar = false,
		crates = true,
		standAC = layout ~= "pocha24",
		tent = if layout == "pocha24" then "eaves" else "full",
	}
	if layout == "pochaBar" then
		th.counter = { front = "tile", frontL = L.of(196, 64, 44, M.CeramicTiles), topL = L.of(200, 204, 208, M.Metal, { r = 0.1 }), kickL = L.black, led = rgb(255, 196, 130) }
		th.hours = "영업시간\n17:00 - 03:00\n연중무휴"
		th.fridgeHeader = "소주 · 맥주"
	elseif layout == "pocha24" then
		th.hours = "24시간 영업\n연중무휴\n해장 · 안주 · 술"
		th.lower = { kind = "tile", h = 3.4, look = L.of(238, 240, 236, M.CeramicTiles), grout = L.of(190, 196, 190), tw = 0.6, th = 0.6, walls = { "back", "left", "right" } }
		th.band = rgb(30, 120, 80)
		th.chair = { style = "diner", frame = L.chrome, seat = L.of(176, 30, 30, M.Leather) }
		th.table = { style = "four", top = L.of(200, 204, 206, M.Metal, { r = 0.08 }), base = L.of(170, 174, 178, M.Metal) }
		th.cushion = { rgb(170, 40, 40), rgb(40, 70, 130), rgb(200, 150, 40) }
		th.maru = L.of(200, 150, 96, M.WoodPlanks)
		th.maruFrame = L.of(120, 78, 46, M.Wood)
		th.sheets = {
			{ "선지해장국", "9,000" }, { "돼지국밥", "10,000" }, { "순대국밥", "10,000" }, { "오뎅탕", "17,000" },
			{ "닭발", "18,000" }, { "계란말이", "12,000" }, { "두부김치", "15,000" }, { "해물파전", "16,000" },
			{ "제육볶음", "15,000" }, { "라면", "5,000" }, { "소주", "5,000" }, { "맥주", "5,000" }, { "막걸리", "5,000" },
		}
		th.origin = "원산지 표시\n돼지고기 : 국내산 · 소선지 : 국내산\n닭발 : 국내산 · 오징어 : 원양산\n쌀 · 배추김치 · 고춧가루 : 국내산"
	end
	return th
end

local function themeFor(V: any): any
	local n = V.name or ""
	local m = V.menu
	local function has(s: string): boolean
		return string.find(n, s, 1, true) ~= nil
	end
	if V.type == "pocha" or m == "pocha" then
		if #V.counters > 0 or V:has("BackBarCabinet") > 0 then
			return pochaTheme(V, "pochaBar")
		end
		if V:has("KitchenPass") > 0 or V:has("CharcoalPot") == 0 then
			return pochaTheme(V, "pocha24")
		end
		return pochaTheme(V, "pochaTent")
	end
	if has("곱창") or has("막창") or m == "gopchang" then
		return THEMES.gopchang
	end
	if has("조개") or m == "clam" then
		-- 조개구이집마다 간판색 · 타일 띠 · 스툴 색을 다르게 (광안 = 파랑, 바다마을 = 청록, 갯마을 = 남색 + 주황)
		local th = table.clone(THEMES.clam)
		local v = hash(n) % 3
		if has("바다") then
			v = 1
		elseif has("갯") then
			v = 2
		elseif has("광안") then
			v = 0
		end
		if v == 1 then
			th.accent = rgb(0, 118, 126)
			th.band = rgb(0, 136, 142)
			th.base = L.of(0, 70, 76)
			th.stools = { rgb(236, 120, 30), rgb(236, 120, 30), BLUE_PL, rgb(236, 120, 30) }
			th.posters = { { "가리비 듬뿍\n바다마을 정식", rgb(255, 226, 90), rgb(0, 118, 126) }, { "부산 바다\n한 상 가득", WHITE, rgb(20, 120, 150) } }
		elseif v == 2 then
			th.accent = rgb(28, 42, 92)
			th.accent2 = rgb(255, 160, 50)
			th.band = rgb(226, 110, 34)
			th.base = L.of(28, 42, 92)
			th.stools = { RED_PL, rgb(28, 60, 140), RED_PL, RED_PL }
			th.posters = { { "갯벌에서 바로\n싱싱한 조개", rgb(255, 170, 60), rgb(28, 42, 92) }, { "치즈 가리비\n출시!", rgb(255, 206, 40), rgb(196, 60, 30) } }
		end
		th.variant = v
		return th
	end
	if m == "bbq" or has("갈비") or has("고기") or has("테이스티") or has("숯불") then
		return THEMES.bbq
	end
	return THEMES.clam
end
T.themeFor = themeFor

-- 좌석 ------------------------------------------------------------------------------------------------
-- 포차 원형 플라스틱 스툴: 위 원판 + 테 + 몸통 + 넓은 치마 + 손잡이 구멍 + (고급) 다리 사이 구멍
local function plasticStool(c: any, x: number, z: number, top: number, dia: number, cc: Color3)
	local K = c.K
	local pl = col(cc, M.Plastic)
	local dk = col(cc:Lerp(Color3.new(0, 0, 0), 0.45), M.Plastic)
	local base = CF(x, 0, z)
	K:disc("StoolSeat", dia * 0.94, 0.1, base * CF(0, top - 0.05, 0), pl)
	K:disc("StoolRim", dia * 0.98, 0.06, base * CF(0, top - 0.12, 0), dk)
	local hb = top - 0.15
	K:disc("StoolBody", dia * 0.9, hb * 0.36, base * CF(0, hb - hb * 0.18, 0), pl)
	K:disc("StoolBody", dia * 0.97, hb * 0.34, base * CF(0, hb * 0.47, 0), pl)
	K:disc("StoolSkirt", dia * 1.04, hb * 0.32, base * CF(0, hb * 0.16, 0), pl)
	K:disc("StoolGrip", dia * 0.3, 0.02, base * CF(0, top + 0.004, 0), dk)
end

local function stoolsOver(c: any)
	local K, V, th = c.K, c.V, c.th
	for i, ch in V.stools do
		local s = ch.seat
		if s.part:IsA("Seat") and s.part.Transparency >= 0.99 then
			continue
		end
		local dia = math.max(0.9, math.min(1.8, math.max(s.size.X, s.size.Z)))
		K:free(function()
			if ch.top < 2.3 then
				local list = th.stools
				local k = (math.floor(s.c.X * 3.7 + s.c.Z * 1.3) + c.seed + i) % #list + 1
				plasticStool(c, s.c.X, s.c.Z, ch.top, dia, list[k])
			else
				-- 바 스툴 (다찌 카운터): 크롬 기둥 + 빨간 비닐 쿠션
				Props.stool(K, CF(s.c.X, 0, s.c.Z), { style = "bar", seatTop = ch.top, dia = dia, seat = L.of(176, 30, 30, M.Leather), frame = L.chrome })
			end
		end)
		for _, r in ch.parts do
			hideRec(K, r)
		end
		for _, r in V.byName.FootRing or {} do
			if math.abs(r.c.X - s.c.X) < 0.9 and math.abs(r.c.Z - s.c.Z) < 0.9 then
				hideRec(K, r)
			end
		end
		K:reserve(V3(s.min.X - 0.2, 0, s.min.Z - 0.2), V3(s.max.X + 0.2, ch.top + 0.5, s.max.Z + 0.2), "stool")
	end
end

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
	local list = th.cushion or { rgb(170, 40, 40), rgb(40, 70, 130) }
	local cc: Color3 = list[((i + c.seed) % #list) + 1]
	local fab = col(cc, M.Fabric)
	local pipe = col(cc:Lerp(rgb(255, 220, 140), 0.45), M.Fabric)
	K:free(function()
		K:slab("Bangseok", w - 0.06, d - 0.06, h * 0.7, 0.24, CF(s.c.X, base + h * 0.35, s.c.Z), fab)
		K:ell("BangseokPuff", V3(w - 0.3, h * 0.6, d - 0.3), CF(s.c.X, top - h * 0.3, s.c.Z), fab)
		K:slab("BangseokPipe", w - 0.02, d - 0.02, 0.04, 0.26, CF(s.c.X, base + h * 0.7, s.c.Z), pipe)
		if c.hi then
			K:disc("BangseokTuft", 0.16, 0.03, CF(s.c.X, top - 0.01, s.c.Z), col(cc:Lerp(Color3.new(0, 0, 0), 0.35), M.Fabric))
		end
	end)
end

-- 벽 붙박이 장의자 (Base + Plinth + Backrest + Arm + Seat n): 레드 비닐 쿠션 · 세로 누빔 등받이 · 원목 몸통
local function banquetteOver(c: any): { [any]: boolean }
	local K, V = c.K, c.V
	local done: { [any]: boolean } = {}
	local backs = V.byName.Backrest or {}
	if #backs == 0 then
		return done
	end
	for _, br in backs do
		local seats = {}
		for _, ch in V.chairs do
			local s = ch.seat
			if s.name == "Seat" and s.c.Z > br.min.Z - 0.5 and s.c.Z < br.max.Z + 0.5 and math.abs(s.c.X - br.c.X) < 3.5 then
				table.insert(seats, ch)
			end
		end
		if #seats == 0 then
			continue
		end
		local alongZ = br.size.Z >= br.size.X
		-- 손님이 보는 방향 (등받이 -> 좌석)
		local s0 = seats[1].seat
		local face = if alongZ then V3(math.sign(s0.c.X - br.c.X), 0, 0) else V3(0, 0, math.sign(s0.c.Z - br.c.Z))
		local vinyl = L.of(160, 32, 30, M.Leather)
		local vinylD = dim(vinyl, 0.25)
		local woodL = L.of(110, 70, 42, M.Wood)
		local bases = {}
		for _, nm in { "Base", "Plinth", "Arm" } do
			for _, r in within(V, nm, br.min - V3(3.5, 0, 0.6), br.max + V3(3.5, 0, 0.6), 0) do
				table.insert(bases, r)
			end
		end
		K:free(function()
			-- 몸통 · 걸레받이 (같은 범위)
			for _, r in bases do
				if r.name == "Base" then
					K:box("BenchBody", r.size - V3(0.02, 0.02, 0.02), CF(r.c), woodL)
					-- 앞면 세로 판 이음
					if c.hi then
						local n = math.floor((if alongZ then r.size.Z else r.size.X) / 1.4)
						for i = 1, n - 1 do
							local t = -0.5 + i / n
							local p = if alongZ then V3(r.c.X + face.X * (r.size.X / 2), r.c.Y, r.c.Z + t * r.size.Z) else V3(r.c.X + t * r.size.X, r.c.Y, r.c.Z + face.Z * (r.size.Z / 2))
							K:box("BenchSeam", if alongZ then V3(0.03, r.size.Y - 0.1, 0.05) else V3(0.05, r.size.Y - 0.1, 0.03), CF(p), dim(woodL, 0.35))
						end
					end
				elseif r.name == "Plinth" then
					K:box("BenchKick", r.size - V3(0.02, 0.02, 0.02), CF(r.c), L.of(30, 26, 22))
				else
					K:box("BenchArm", r.size - V3(0.02, 0.06, 0.02), CF(r.c - V3(0, 0.03, 0)), woodL)
					K:box("BenchArmCap", V3(r.size.X + 0.04, 0.08, r.size.Z + 0.04), CF(r.c.X, r.max.Y - 0.04, r.c.Z), dim(woodL, 0.2))
				end
			end
			-- 좌석 쿠션 (Seat 마다, 같은 윗면)
			for _, ch in seats do
				local s = ch.seat
				K:rbox("BenchCushion", V3(s.size.X - 0.06, s.size.Y, s.size.Z - 0.08), 0.12, CF(s.c) * (if alongZ then ANG(0, PI / 2, 0) else CFrame.new()), vinyl)
				K:box("BenchPiping", V3(s.size.X - 0.02, 0.04, s.size.Z - 0.04), CF(s.c.X, s.max.Y - 0.1, s.c.Z), vinylD)
			end
			-- 등받이: 세로 누빔 쿠션
			local len = if alongZ then br.size.Z else br.size.X
			local n = math.max(3, math.floor(len / 0.9))
			local step = len / n
			local y0 = s0.max.Y
			local hgt = br.max.Y - y0 - 0.1
			K:box("BenchBackBoard", V3(br.size.X - 0.02, br.size.Y - 0.02, br.size.Z - 0.02) - (if alongZ then V3(0.3, 0, 0) else V3(0, 0, 0.3)), CF(br.c - face * 0.15), woodL)
			for i = 1, n do
				local t = -len / 2 + step * (i - 0.5)
				local p = if alongZ then V3(br.c.X + face.X * (br.size.X / 2 - 0.25), y0 + hgt / 2, br.c.Z + t) else V3(br.c.X + t, y0 + hgt / 2, br.c.Z + face.Z * (br.size.Z / 2 - 0.25))
				local sz = if alongZ then V3(0.4, hgt, step - 0.06) else V3(step - 0.06, hgt, 0.4)
				K:rbox("BenchTuft", if alongZ then V3(sz.Z, sz.Y, sz.X) else sz, 0.16, CF(p) * (if alongZ then ANG(0, PI / 2, 0) else CFrame.new()), vinyl)
			end
			K:box("BenchCap", if alongZ then V3(br.size.X + 0.04, 0.1, br.size.Z) else V3(br.size.X, 0.1, br.size.Z + 0.04), CF(br.c.X, br.max.Y - 0.05, br.c.Z), dim(woodL, 0.2))
		end)
		hideRec(K, br)
		for _, r in bases do
			hideRec(K, r)
		end
		for _, ch in seats do
			for _, r in ch.parts do
				hideRec(K, r)
			end
			done[ch] = true
		end
		K:reserve(br.min:Min(s0.min) - V3(0.2, 0, 0.2), br.max + V3(0.2, 0.2, 0.2), "bench")
	end
	return done
end

local function chairsOver(c: any)
	local K, V, th = c.K, c.V, c.th
	local done = banquetteOver(c)
	local n = #V.chairs
	local detail = K.detail
	if n * 30 > K.maxParts * 0.4 or n > 16 then
		detail = if n * 22 > K.maxParts * 0.4 then "low" else "mid"
	end
	for i, ch in V.chairs do
		if done[ch] then
			continue
		end
		local s = ch.seat
		if s.part:IsA("Seat") and s.part.Transparency >= 0.99 then
			continue
		end
		if s.name == "Cushion" or s.name == "SeatCushion" then
			cushionOver(c, ch, i)
			K:reserve(V3(s.min.X - 0.1, s.min.Y, s.min.Z - 0.1), V3(s.max.X + 0.1, ch.top + 0.4, s.max.Z + 0.1), "cushion")
		else
			local w = math.max(1.1, math.min(2.2, math.min(s.size.X, s.size.Z) + 0.05))
			local backH = 1.8
			if ch.back then
				backH = math.clamp(ch.back.max.Y - ch.top, 1.0, 3.2)
			end
			local o = table.clone(th.chair or { style = "plastic", seat = L.of(206, 38, 36, M.Plastic) })
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

-- 테이블 ----------------------------------------------------------------------------------------------
-- 불판 테이블 하나: 상판 (같은 윗면 · 같은 범위) + 화로 우물 + 받침 (드럼통 / 캐비닛 / 기둥)
local function grillTableOver(c: any, g: any, idx: number)
	local K, th = c.K, c.th
	local t = g.t
	local mn, mx, y = t.min, t.max, t.y
	local w, l = mx.X - mn.X, mx.Z - mn.Z
	local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
	local pot = g.pot
	local pc = if pot then pot.c else V3(cx, y, cz)
	local potD = if pot then math.max(pot.size.X, pot.size.Z) else 1.4
	local topL = th.top
	local edgeL = th.edge
	K:free(function()
		K:slab("GrillTop", w, l, 0.1, 0.24, CF(cx, y - 0.05, cz), topL)
		K:box("GrillTopEdge", V3(w - 0.3, 0.1, l - 0.3), CF(cx, y - 0.15, cz), edgeL)
		-- 화로 우물 테 (상판 위 아주 얇게)
		K:disc("GrillWell", potD + 0.24, 0.02, CF(pc.X, y + 0.008, pc.Z), dim(topL, 0.45))
		local by = y - 0.2 -- 받침 윗면
		if th.tableBase == "drum" then
			-- 드럼통 (200L): 도장 몸통 + 테 2줄 + 위 · 아래 말린 테 + 작은 마개
			local list = th.drums or { rgb(168, 40, 32) }
			local dc: Color3 = list[(idx + c.seed) % #list + 1]
			local drumL = col(dc, M.Metal)
			local rimL = col(dc:Lerp(Color3.new(0, 0, 0), 0.25), M.Metal)
			local dd = math.min(2.3, math.min(w, l) - 1.0)
			K:vcyl("DrumBody", by, dd, CF(cx, by / 2, cz), drumL)
			for _, f in { 0.34, 0.67 } do
				K:vcyl("DrumRib", 0.08, dd + 0.06, CF(cx, by * f, cz), rimL)
			end
			K:vcyl("DrumChime", 0.1, dd + 0.05, CF(cx, by - 0.05, cz), rimL)
			K:vcyl("DrumChime", 0.1, dd + 0.05, CF(cx, 0.05, cz), rimL)
			if c.hi then
				K:vcyl("DrumBung", 0.04, 0.22, CF(cx + dd * 0.28, by + 0.0, cz + dd * 0.12), rimL)
				-- 재 받이 문 (앞쪽)
				local fz = cz + dd / 2
				K:box("DrumDoor", V3(0.7, 0.5, 0.04), CF(cx, by * 0.5, fz + 0.01), dim(drumL, 0.35))
				K:box("DrumDoorKnob", V3(0.2, 0.06, 0.06), CF(cx, by * 0.5 + 0.12, fz + 0.05), L.blackMetal)
			end
		elseif th.tableBase == "cabinet" then
			-- 스테인리스 캐비닛 받침 (재 서랍 · 통풍구 · 걸레받이)
			local bw = math.min(1.9, math.min(w, l) - 1.2)
			local bh = by - 0.32
			K:box("GrillCabinet", V3(bw, bh, bw), CF(cx, 0.32 + bh / 2, cz), L.brushed)
			K:box("GrillCabinetKick", V3(bw - 0.2, 0.32, bw - 0.2), CF(cx, 0.16, cz), L.of(30, 30, 32))
			local fz = cz + bw / 2
			K:box("AshDrawer", V3(bw - 0.4, 0.42, 0.04), CF(cx, by - 0.45, fz + 0.01), L.steel)
			K:box("AshDrawerHandle", V3(0.5, 0.06, 0.07), CF(cx, by - 0.45, fz + 0.06), L.blackMetal)
		else
			-- 블랙 기둥 + 사각 발판 + 재 통
			K:vcyl("GrillColumn", by - 0.1, 0.42, CF(cx, (by - 0.1) / 2 + 0.06, cz), L.blackMetal)
			K:box("GrillFoot", V3(1.7, 0.1, 1.7), CF(cx, 0.05, cz), L.blackMetal)
			K:vcyl("AshCan", 0.5, 1.0, CF(cx, by - 0.3, cz), L.of(60, 60, 64, M.Metal))
			K:box("GrillFootGlide", V3(1.5, 0.03, 1.5), CF(cx, 0.115, cz), L.of(80, 80, 84, M.Metal))
		end
		-- 화로 (CharcoalPot 같은 범위 · 같은 윗면) + 재 · 숯 · 불씨 + 석쇠
		if pot then
			local y0, y1 = pot.min.Y, pot.max.Y
			local iron = L.of(50, 48, 46, M.Metal)
			K:disc("PotBody", potD - 0.02, y1 - y0 - 0.04, CF(pc.X, (y0 + y1) / 2 - 0.02, pc.Z), iron)
			K:disc("PotRim", potD, 0.05, CF(pc.X, y1 - 0.025, pc.Z), L.of(86, 86, 90, M.Metal))
			K:disc("PotAsh", potD - 0.22, 0.012, CF(pc.X, y1 + 0.006, pc.Z), L.of(92, 88, 84, M.Slate))
			local cd = if g.coals then math.max(g.coals.size.X, g.coals.size.Z) else potD * 0.66
			local glow = K:disc("CoalGlow", cd, 0.02, CF(pc.X, y1 + 0.018, pc.Z), L.neon(rgb(255, 104, 34)))
			c.coalGlows = c.coalGlows or {}
			table.insert(c.coalGlows, glow)
			-- 숯 덩이 (검은 덩이 + 끝이 빨간 덩이)
			local nl = if c.hi then 5 else 3
			for i = 1, nl do
				local a = i * 2 * PI / nl + rnd(c.seed + idx, i) * 0.6
				local r = cd * 0.28 * (0.4 + rnd(c.seed + idx, i + 9) * 0.6)
				local look = if i % 3 == 0 then L.neon(rgb(255, 80, 28)) else L.of(34, 32, 32, M.Slate)
				K:ell("Charcoal", V3(0.3, 0.09, 0.2), CF(pc.X + math.cos(a) * r, y1 + 0.05, pc.Z + math.sin(a) * r) * ANG(0, a, 0.2), look)
			end
			if c.hi then
				-- 석쇠: 둥근 테 + 가로살 5
				local gy = y1 + 0.11
				local R = potD / 2 - 0.06
				K:seg("GrateFrame", V3(pc.X, gy - 0.01, pc.Z - R), V3(pc.X, gy - 0.01, pc.Z + R), 0.05, L.of(120, 116, 112, M.Metal))
				for i = -2, 2 do
					local zz = i * R * 0.38
					local hx = math.sqrt(math.max(0, R * R - zz * zz))
					K:seg("GrateBar", V3(pc.X - hx, gy, pc.Z + zz), V3(pc.X + hx, gy, pc.Z + zz), 0.03, L.of(120, 116, 112, M.Metal))
				end
			end
			-- 손잡이 귀 2개 (상판 위)
			for _, sx in { -1, 1 } do
				K:box("PotEar", V3(0.18, 0.05, 0.3), CF(pc.X + sx * (potD / 2 + 0.06), y + 0.03, pc.Z), iron)
			end
		end
		-- 테이블 위 조개 (맵 Shell 자리 그대로): 가리비 한 개
		if g.shell then
			local s = g.shell
			K:ell("ShellCup", V3(s.size.X, s.size.Y * 0.6, s.size.Z), CF(s.c.X, s.min.Y + s.size.Y * 0.3, s.c.Z), L.of(222, 150, 116))
			K:ell("ShellMeat", V3(s.size.X * 0.62, s.size.Y * 0.4, s.size.Z * 0.6), CF(s.c.X, s.min.Y + s.size.Y * 0.55, s.c.Z), L.of(250, 230, 200))
			K:box("ShellHinge", V3(0.12, 0.05, 0.08), CF(s.c.X, s.min.Y + s.size.Y * 0.3, s.min.Z + 0.02), L.of(190, 120, 90))
		end
	end)
end

-- 원형 후드 (Hood 같은 범위) + 신축 덕트 (HoodDuct 같은 범위)
local function hoodOver(c: any, h: any, duct: any?)
	local K, V = c.K, c.V
	local cx, cz = h.c.X, h.c.Z
	local hw = math.min(h.size.X, h.size.Z)
	local y0, y1 = h.min.Y, h.max.Y
	local hh = y1 - y0
	local st = L.of(214, 218, 222, M.SmoothPlastic, { r = 0.2 })
	local stD = L.of(182, 186, 190, M.SmoothPlastic, { r = 0.14 })
	K:free(function()
		-- 계단식 종 모양 (아래 테가 가장 넓음)
		local steps = { { 1.0, 0.2 }, { 0.92, 0.1 }, { 0.83, 0.1 }, { 0.74, 0.1 }, { 0.65, 0.1 }, { 0.56, 0.1 }, { 0.47, 0.1 }, { 0.38, 0.2 } }
		local y = y0
		for i, s in steps do
			local sh = hh * s[2]
			K:disc("HoodShell", hw * s[1], sh, CF(cx, y + sh / 2, cz), if i == 1 then stD else st)
			y += sh
		end
		K:disc("HoodFilter", hw * 0.9, 0.02, CF(cx, y0 + 0.012, cz), L.of(64, 66, 70, M.DiamondPlate))
		if duct then
			local d = math.min(duct.size.X, duct.size.Z)
			local dy0, dy1 = duct.min.Y, math.min(duct.max.Y, V.H)
			local mid = dy0 + (dy1 - dy0) * 0.5
			-- 아래 미닫이 관 (가는) + 위 고정 관 (굵은) + 이음 칼라 + 바닥 클램프 + 천장 플랜지
			K:vcyl("DuctLower", mid + 0.2 - dy0, d * 0.84, CF(cx, (dy0 + mid + 0.2) / 2, cz), st)
			K:vcyl("DuctUpper", dy1 - mid, d, CF(cx, (mid + dy1) / 2, cz), stD)
			K:vcyl("DuctCollar", 0.12, d + 0.08, CF(cx, mid + 0.06, cz), L.of(140, 144, 148, M.Metal))
			K:vcyl("DuctClamp", 0.08, d * 0.84 + 0.06, CF(cx, dy0 + 0.06, cz), L.of(140, 144, 148, M.Metal))
			K:disc("DuctFlange", d + 0.36, 0.04, CF(cx, V.H - 0.03, cz), stD)
			if c.hi then
				-- 높이 조절 손잡이 (작은 레버)
				K:box("DuctLever", V3(0.08, 0.08, 0.4), CF(cx, mid - 0.3, cz + d * 0.42 + 0.18), L.blackMetal)
				K:ball("DuctLeverKnob", 0.14, CF(cx, mid - 0.3, cz + d * 0.42 + 0.38), L.of(196, 30, 30, M.Plastic))
			end
		end
	end)
end

-- 천장 메인 덕트: 줄마다 후드 덕트를 이어 가까운 옆벽으로 (스파이럴 이음 · 행거 · 벽 플랜지)
local function trunkDucts(c: any, hoods: { any })
	local K, V = c.K, c.V
	local rows = {}
	for _, h in hoods do
		local row = nil
		for _, r in rows do
			if math.abs(r.z - h.z) < 1.0 then
				row = r
			end
		end
		if not row then
			row = { z = h.z, xs = {} }
			table.insert(rows, row)
		end
		table.insert(row.xs, h.x)
	end
	local st = L.of(226, 230, 234, M.SmoothPlastic, { r = 0.24 })
	local seam = L.of(176, 180, 186, M.SmoothPlastic, { r = 0.12 })
	local dia = 0.9
	c.trunkEnds = {}
	for _, row in rows do
		table.sort(row.xs)
		local xa, xb = row.xs[1], row.xs[#row.xs]
		local toLeft = (xa - V.x0) <= (V.x1 - xb)
		local x0 = if toLeft then V.x0 + 0.02 else xa - 0.45
		local x1 = if toLeft then xb + 0.45 else V.x1 - 0.02
		-- 높이: AC · 조명 아래 (후드 덕트 자신은 제외)
		local top = V.H - 0.12
		for _, r in V.parts do
			if not r.shell and r.min.Y > V.H - 2.2 and r.name ~= "HoodDuct" and r.name ~= "Hood" and r.max.X > x0 and r.min.X < x1 and r.max.Z > row.z - dia / 2 - 0.1 and r.min.Z < row.z + dia / 2 + 0.1 then
				top = math.min(top, r.min.Y - 0.06)
			end
		end
		if top - dia < 7.6 then
			continue
		end
		local y = top - dia / 2
		local z = row.z
		K:free(function()
			K:cyl("TrunkDuct", x1 - x0, dia, CF((x0 + x1) / 2, y, z), st)
			local n = math.floor((x1 - x0) / 1.6)
			for i = 1, n do
				local x = x0 + (x1 - x0) * i / (n + 1)
				K:cyl("TrunkSeam", 0.06, dia + 0.04, CF(x, y, z), seam)
				if i % 3 == 0 then
					-- 행거 (전산볼트 2 + 밴드)
					K:seg("TrunkHanger", V3(x, y + dia / 2, z - 0.3), V3(x, V.H, z - 0.3), 0.04, L.blackMetal)
					K:seg("TrunkHanger", V3(x, y + dia / 2, z + 0.3), V3(x, V.H, z + 0.3), 0.04, L.blackMetal)
					K:cyl("TrunkBand", 0.1, dia + 0.08, CF(x, y, z), L.blackMetal)
				end
			end
			-- 끝: 벽 플랜지 / 마개
			local wallX = if toLeft then V.x0 else V.x1
			local endX = if toLeft then x1 else x0
			K:make("Part", "TrunkFlange", V3(0.1, dia + 0.5, dia + 0.5), CF(wallX + (if toLeft then 0.06 else -0.06), y, z), seam, Enum.PartType.Cylinder)
			K:cyl("TrunkCap", 0.08, dia + 0.04, CF(endX, y, z), seam)
		end)
		table.insert(c.trunkEnds, { wall = if toLeft then "left" else "right", z = z, y = y })
	end
end

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
	local topL = L.of(150, 96, 58, M.Wood)
	local edgeL = dim(topL, 0.35)
	local alongX = w >= l
	K:free(function()
		K:slab("GyojaTop", w, l, 0.12, 0.1, CF(cx, y - 0.06, cz), topL)
		K:slab("GyojaEdge", w - 0.04, l - 0.04, 0.05, 0.1, CF(cx, y - 0.145, cz), edgeL)
		local legH = y - 0.17 - fy
		for _, s in { -1, 1 } do
			if alongX then
				local x = cx + s * (w / 2 - 0.45)
				for _, sz in { -1, 1 } do
					K:box("GyojaLeg", V3(0.14, legH, 0.14), CF(x, fy + legH / 2, cz + sz * (l / 2 - 0.35)), edgeL)
				end
				K:box("GyojaFoot", V3(0.12, 0.1, l - 0.6), CF(x, fy + 0.05, cz), edgeL)
			else
				local z = cz + s * (l / 2 - 0.45)
				for _, sx in { -1, 1 } do
					K:box("GyojaLeg", V3(0.14, legH, 0.14), CF(cx + sx * (w / 2 - 0.35), fy + legH / 2, z), edgeL)
				end
				K:box("GyojaFoot", V3(w - 0.6, 0.1, 0.12), CF(cx, fy + 0.05, z), edgeL)
			end
		end
	end)
end

-- 수저통 (SpoonBox 자리 · 크기 그대로)
local function spoonBoxOver(c: any, r: any)
	local K = c.K
	local sx, sy, sz = r.size.X, r.size.Y, r.size.Z
	local base = CF(r.c.X, r.min.Y, r.c.Z)
	local alongX = sx >= sz
	local long, short = math.max(sx, sz), math.min(sx, sz)
	local b = base * (if alongX then CFrame.new() else ANG(0, PI / 2, 0))
	K:free(function()
		K:box("SujeoBody", V3(long - 0.02, sy - 0.06, short - 0.02), b * CF(0, (sy - 0.06) / 2, 0), L.steel)
		K:box("SujeoLid", V3(long, 0.05, short), b * CF(0, sy - 0.035, 0), L.chrome)
		K:box("SujeoKnob", V3(0.18, 0.04, 0.06), b * CF(0, sy - 0.005 - 0.02, 0), L.black)
	end)
end

local function tablesOver(c: any)
	local K, V, th = c.K, c.V, c.th
	c.grills = {}
	local hoods = {}
	for i, t in V.tables do
		local pots = within(V, "CharcoalPot", t.min, t.max, 0.05)
		if #pots > 0 or t.kind == "grill" then
			local g: any = { t = t, pot = pots[1] }
			g.coals = within(V, "Coals", t.min, t.max, 0.05)[1]
			for _, s in within(V, "Shell", t.min, t.max, 0) do
				if s.min.Y >= t.y - 0.1 and s.max.Y < t.y + 1.0 then
					g.shell = s
				end
			end
			for _, h in within(V, "Hood", t.min, t.max, 0) do
				if h.min.Y > t.y + 2 then
					g.hood = h
				end
			end
			if g.hood then
				for _, d in within(V, "HoodDuct", g.hood.min, g.hood.max, 0) do
					if d.min.Y >= g.hood.max.Y - 0.2 then
						g.duct = d
					end
				end
			end
			grillTableOver(c, g, i)
			for _, r in t.parts do
				hideRec(K, r)
			end
			for _, r in { g.pot, g.coals, g.shell } do
				hideRec(K, r)
			end
			if g.hood then
				hoodOver(c, g.hood, g.duct)
				hideRec(K, g.hood)
				if g.duct then
					hideRec(K, g.duct)
				end
				table.insert(hoods, { x = g.hood.c.X, z = g.hood.c.Z })
			end
			table.insert(c.grills, g)
		elseif t.kind == "low" then
			lowTableOver(c, t)
			for _, r in t.parts do
				hideRec(K, r)
			end
		else
			local o = table.clone(th.table or { style = "pedestal", top = th.top, edge = th.edge, base = L.blackMetal })
			if t.kind == "bar" then
				o.style = "steel"
			end
			Props.tableOver(K, t, o)
			for _, r in t.parts do
				hideRec(K, r)
			end
		end
		K:reserve(V3(t.min.X, 0, t.min.Z), V3(t.max.X, t.y + 0.2, t.max.Z), "table")
	end
	for _, r in V.byName.SpoonBox or {} do
		spoonBoxOver(c, r)
		hideRec(K, r)
	end
	if #hoods > 0 then
		trunkDucts(c, hoods)
	end
	-- 숯불 빛 (두 테이블만: 밤에 불판이 은은하게)
	for i, gl in c.coalGlows or {} do
		if i == 1 or i == math.max(2, #c.coalGlows - 1) then
			K:light(gl, "PointLight", { Range = 5, Brightness = 0.6, Color = rgb(255, 120, 50) })
		end
	end
end

-- 병 · 캔 (실제 비율: 소주 360ml ≈ 0.68 스터드) -----------------------------------------------------------------
local SOJU_GLASS = { c = rgb(44, 146, 82), m = M.Glass, t = 0.12, r = 0.08 }
local BEER_GLASS = { c = rgb(112, 62, 22), m = M.Glass, t = 0.1, r = 0.08 }
local function bottle(K: any, base: CFrame, kind: string, hi: boolean, tint: Color3?)
	if kind == "soju" then
		K:vcyl("Soju", 0.44, 0.22, base * CF(0, 0.22, 0), SOJU_GLASS)
		K:vcyl("SojuNeck", 0.2, 0.11, base * CF(0, 0.54, 0), SOJU_GLASS)
		K:vcyl("SojuCap", 0.06, 0.12, base * CF(0, 0.67, 0), L.of(36, 110, 60, M.Metal))
		if hi then
			K:plate("SojuLabel", 0.17, 0.17, 0.01, base * CF(0, 0.22, 0.11), L.of(250, 250, 248))
		end
	elseif kind == "beer" then
		K:vcyl("BeerBottle", 0.5, 0.25, base * CF(0, 0.25, 0), BEER_GLASS)
		K:vcyl("BeerNeck", 0.24, 0.11, base * CF(0, 0.62, 0), BEER_GLASS)
		K:vcyl("BeerCap", 0.05, 0.12, base * CF(0, 0.765, 0), L.goldMetal)
		if hi then
			K:plate("BeerLabel", 0.2, 0.16, 0.01, base * CF(0, 0.26, 0.125), L.of(236, 206, 70))
		end
	elseif kind == "makgeolli" then
		K:vcyl("Makgeolli", 0.6, 0.26, base * CF(0, 0.3, 0), L.of(246, 244, 238, M.Plastic))
		K:vcyl("MakgeolliCap", 0.1, 0.13, base * CF(0, 0.65, 0), L.of(40, 140, 70, M.Plastic))
		if hi then
			K:plate("MakgeolliLabel", 0.22, 0.2, 0.01, base * CF(0, 0.32, 0.13), L.of(60, 130, 80))
		end
	elseif kind == "cider" then
		K:vcyl("Cider", 0.62, 0.24, base * CF(0, 0.31, 0), { c = rgb(150, 216, 160), m = M.Glass, t = 0.3 })
		K:vcyl("CiderCap", 0.06, 0.12, base * CF(0, 0.65, 0), L.of(40, 120, 60))
	else
		local cc = tint or rgb(200, 30, 36)
		K:vcyl("Can", 0.38, 0.2, base * CF(0, 0.19, 0), col(cc, M.Metal))
		if hi then
			K:vcyl("CanTop", 0.02, 0.17, base * CF(0, 0.39, 0), L.alu)
		end
	end
end

-- 소주 냉장고 (맵 냉장고 묶음과 같은 범위): 몸통 · 상단 광고판 · 안쪽 LED · 선반 · 병 · 유리문 (여닫기)
local FRIDGE_PARTS = { Body = true, Kick = true, SidePanel = true, FridgeGlow = true, FridgeDoor = true, WireShelf = true, Bottle = true, FridgeLamp = true }
local function fridgeBuild(c: any, pcf: CFrame, W: number, D: number, H: number, kickY: number, crownY: number, shelfYs: { number }, hingeLeft: boolean, n: number)
	local K, th = c.K, c.th
	local body = L.of(232, 234, 236, M.Metal)
	local dark = L.of(40, 42, 46, M.Metal)
	local sideT = 0.16
	local iw = W - 2 * sideT
	K:box("FridgeSide", V3(sideT, H, D), pcf * CF(-W / 2 + sideT / 2, H / 2, 0), body)
	K:box("FridgeSide", V3(sideT, H, D), pcf * CF(W / 2 - sideT / 2, H / 2, 0), body)
	K:box("FridgeBack", V3(W, H, 0.14), pcf * CF(0, H / 2, -D / 2 + 0.07), body)
	K:box("FridgeCrown", V3(W, H - crownY, D), pcf * CF(0, (crownY + H) / 2, 0), body)
	K:box("FridgeKick", V3(W, kickY, D - 0.1), pcf * CF(0, kickY / 2, -0.05), dark)
	K:plate("FridgeVent", W * 0.7, kickY * 0.55, 0.02, pcf * CF(0, kickY / 2, D / 2 - 0.1), L.of(80, 82, 86, M.DiamondPlate))
	K:box("FridgeLiner", V3(iw, crownY - kickY, 0.02), pcf * CF(0, (kickY + crownY) / 2, -D / 2 + 0.15), L.of(246, 248, 250))
	local hb = th.fridgeBg or rgb(22, 96, 60)
	txt(K, "FridgeHeader", W - 0.2, (H - crownY) * 0.72, pcf * CF(0, (crownY + H) / 2, D / 2), th.fridgeHeader or "소주 · 맥주", WHITE, hb, F.GothamBlack, { glow = 1.4 })
	local lamp = K:box("FridgeLamp", V3(iw - 0.1, 0.05, 0.12), pcf * CF(0, crownY - 0.08, D / 2 - 0.4), L.lampCool)
	K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 7, Brightness = 0.8, Angle = 140, Color = L.coolLight })
	for _, sx in { -1, 1 } do
		K:box("FridgeLED", V3(0.05, crownY - kickY - 0.3, 0.05), pcf * CF(sx * (iw / 2 - 0.04), (kickY + crownY) / 2, D / 2 - 0.3), L.lampCool)
	end
	-- 층: 바닥칸 (kick 위) + 선반들
	local levels = { kickY }
	for _, y in shelfYs do
		table.insert(levels, y)
	end
	table.sort(levels)
	local kinds = if th.pocha then { "can", "makgeolli", "beer", "soju", "soju" } else { "can", "beer", "soju", "soju", "soju" }
	local canC = { rgb(200, 30, 36), rgb(30, 90, 190), rgb(240, 190, 40), rgb(60, 160, 70), rgb(236, 236, 236) }
	for li, y in levels do
		if li > 1 then
			K:box("FridgeShelf", V3(iw - 0.04, 0.03, D - 0.55), pcf * CF(0, y - 0.015, -0.1), L.of(200, 204, 208, M.Metal, { t = 0.25 }))
			K:cyl("FridgeShelfRail", iw - 0.04, 0.04, pcf * CF(0, y + 0.06, D / 2 - 0.42), L.chrome)
			if c.hi then
				K:plate("FridgePriceStrip", iw - 0.2, 0.08, 0.01, pcf * CF(0, y - 0.04, D / 2 - 0.38), L.of(250, 250, 248))
			end
		end
		local kind = kinds[math.min(li, #kinds)]
		local step = if kind == "beer" or kind == "makgeolli" then 0.34 else 0.3
		local nb = math.max(1, math.floor((iw - 0.2) / step))
		local s = (iw - 0.2) / nb
		for j = 1, nb do
			local x = -iw / 2 + 0.1 + s * (j - 0.5)
			bottle(K, pcf * CF(x, y + 0.01, D / 2 - 0.68), kind, c.hi and (j % 2 == 1), canC[(j + li) % #canC + 1])
			if c.hi and j % 2 == 0 then
				-- 뒷줄 (몸통만)
				K:vcyl("BackRow", 0.5, 0.22, pcf * CF(x, y + 0.26, D / 2 - 1.1), if kind == "soju" then SOJU_GLASS elseif kind == "beer" then BEER_GLASS else L.of(120, 120, 124))
			end
		end
	end
	-- 유리문 (경첩 쪽 = hingeLeft)
	local doors = {}
	local dw = iw / n
	for i = 1, n do
		local x0 = -iw / 2 + (i - 1) * dw
		local m = K:group("FridgeDoor_" .. i, function()
			local cc = pcf * CF(x0 + dw / 2, (kickY + crownY) / 2, D / 2 + 0.05)
			local hgt = crownY - kickY
			local fr = L.of(46, 48, 52, M.Metal)
			K:box("FridgeDoorFrame", V3(dw, 0.12, 0.1), cc * CF(0, hgt / 2 - 0.06, 0), fr)
			K:box("FridgeDoorFrame", V3(dw, 0.16, 0.1), cc * CF(0, -hgt / 2 + 0.08, 0), fr)
			K:box("FridgeDoorFrame", V3(0.12, hgt, 0.1), cc * CF(-dw / 2 + 0.06, 0, 0), fr)
			K:box("FridgeDoorFrame", V3(0.12, hgt, 0.1), cc * CF(dw / 2 - 0.06, 0, 0), fr)
			K:box("FridgeDoorGlass", V3(dw - 0.22, hgt - 0.26, 0.03), cc, { c = rgb(214, 232, 238), m = M.SmoothPlastic, t = 0.8, r = 0.14 })
			local hx = if hingeLeft then dw / 2 - 0.2 else -dw / 2 + 0.2
			K:box("FridgeDoorHandle", V3(0.08, hgt * 0.5, 0.08), cc * CF(hx, 0, 0.16), L.chrome)
			K:box("FridgeHandleFoot", V3(0.06, 0.06, 0.12), cc * CF(hx, hgt * 0.24, 0.08), L.chrome)
			K:box("FridgeHandleFoot", V3(0.06, 0.06, 0.12), cc * CF(hx, -hgt * 0.24, 0.08), L.chrome)
		end)
		local hxL = if hingeLeft then x0 else x0 + dw
		table.insert(doors, { m = m, hinge = (K.cf * pcf * CF(hxL, 0, D / 2 + 0.05)).Position, sign = if hingeLeft then -1 else 1 })
	end
	return doors
end

local function fridgeSwing(c: any, doors: { any }, object: string)
	local K = c.K
	for _, d in doors do
		local handle = d.m:FindFirstChild("FridgeDoorHandle", true)
		if handle and handle:IsA("BasePart") and promptOK(c, c.V.cf:PointToObjectSpace(handle.Position)) then
			Interact.swing(K, d.m, d.hinge, K.cf:VectorToWorldSpace(Vector3.yAxis), d.sign * 1.75, { object = object, openText = "문 열기", closeText = "문 닫기" })
		end
	end
end

local function fridgeOver(c: any)
	local K, V = c.K, c.V
	local fds = V.byName.FridgeDoor
	if not fds or #fds == 0 then
		return false
	end
	local fd = fds[1]
	local grp = {}
	local mn, mx = fd.min, fd.max
	for _, r in V.parts do
		if FRIDGE_PARTS[r.name] and math.abs(r.c.X - fd.c.X) < 3.2 and math.abs(r.c.Z - fd.c.Z) < 4.2 then
			table.insert(grp, r)
			mn = mn:Min(r.min)
			mx = mx:Max(r.max)
		end
	end
	local handle = nil
	for _, r in V.byName.DoorHandle or {} do
		if r.c.X > fd.min.X - 0.4 and r.c.X < fd.max.X + 0.4 and r.c.Z > fd.min.Z - 0.5 and r.c.Z < fd.max.Z + 0.5 and r.c.Y > 1 then
			handle = r
			table.insert(grp, r)
		end
	end
	local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
	local dx, dz = fd.c.X - cx, fd.c.Z - cz
	local front = if math.abs(dz) >= math.abs(dx) then V3(0, 0, if dz >= 0 then 1 else -1) else V3(if dx >= 0 then 1 else -1, 0, 0)
	local W = if front.Z ~= 0 then mx.X - mn.X else mx.Z - mn.Z
	local D = if front.Z ~= 0 then mx.Z - mn.Z else mx.X - mn.X
	local p = V3(cx, 0, cz)
	local pcf = CFrame.lookAt(p, p - front)
	local kickY, crownY = fd.min.Y, fd.max.Y
	local shelfYs = {}
	for _, r in grp do
		if r.name == "WireShelf" then
			table.insert(shelfYs, r.max.Y)
		end
	end
	local hingeLeft = true
	if handle then
		hingeLeft = pcf:PointToObjectSpace(handle.c).X > 0
	end
	local doors
	K:free(function()
		doors = fridgeBuild(c, pcf, W, D, mx.Y, kickY, crownY, shelfYs, hingeLeft, 1)
	end)
	for _, r in grp do
		hideRec(K, r)
	end
	fridgeSwing(c, doors, "소주 냉장고")
	K:note(string.format("fridge overlay @ %.1f,%.1f", cx, cz))
	return true
end

-- 해산물 · 고기 진열대 (맵 ShellDisplay 와 같은 범위) ------------------------------------------------------
local function seafood(c: any, kind: string, base: CFrame, w: number, d: number, seed: number)
	local K = c.K
	local function pos(i: number, n: number): CFrame
		local cols = math.max(1, math.floor(math.sqrt(n * w / d) + 0.5))
		local rows = math.ceil(n / cols)
		local ci, ri = (i - 1) % cols, (i - 1) // cols
		local x = -w / 2 + w * (ci + 0.5) / cols + (rnd(seed, i) - 0.5) * 0.12
		local z = -d / 2 + d * (ri + 0.5) / rows + (rnd(seed, i + 7) - 0.5) * 0.1
		return base * CF(x, 0, z) * ANG(0, rnd(seed, i + 3) * PI * 2, 0)
	end
	if kind == "scallop" then
		for i = 1, 6 do
			local p = pos(i, 6)
			K:ell("Scallop", V3(0.42, 0.08, 0.4), p * CF(0, 0.04, 0), L.of(226, 128, 96))
			K:ell("ScallopRim", V3(0.36, 0.06, 0.32), p * CF(0, 0.08, 0.02), L.of(246, 196, 160))
		end
	elseif kind == "pen" then
		for i = 1, 4 do
			local p = pos(i, 4)
			K:wedge("PenShell", V3(0.32, 0.08, 0.78), p * CF(0, 0.04, 0), L.of(56, 46, 40))
			K:disc("PenMeat", 0.18, 0.04, p * CF(0, 0.09, 0.2), L.of(244, 236, 220))
		end
	elseif kind == "abalone" then
		for i = 1, 5 do
			local p = pos(i, 5)
			K:ell("Abalone", V3(0.38, 0.1, 0.28), p * CF(0, 0.05, 0), L.of(108, 98, 76))
			K:ell("AbaloneMantle", V3(0.3, 0.07, 0.2), p * CF(0, 0.1, 0), L.of(70, 82, 58))
		end
	elseif kind == "clam" or kind == "ark" then
		local cc = if kind == "clam" then L.of(222, 210, 186) else L.of(96, 74, 54)
		for i = 1, 8 do
			K:ell("Clam", V3(0.28, 0.14, 0.24), pos(i, 8) * CF(0, 0.07, 0), if i % 3 == 0 then dim(cc, 0.15) else cc)
		end
	elseif kind == "shrimp" then
		for i = 1, 5 do
			local p = pos(i, 5)
			K:ell("Shrimp", V3(0.16, 0.12, 0.42), p * CF(0, 0.06, 0), L.of(150, 140, 136))
			K:ell("ShrimpTail", V3(0.18, 0.06, 0.16), p * CF(0, 0.05, 0.26), L.of(200, 110, 80))
			K:ell("ShrimpHead", V3(0.18, 0.13, 0.18), p * CF(0, 0.07, -0.24), L.of(120, 110, 104))
		end
	elseif kind == "gopchang" then
		for i = 1, 3 do
			local p = pos(i, 3)
			for k = 0, 6 do
				local a = k * 0.9
				K:ell("Gopchang", V3(0.16, 0.12, 0.22), p * CF(math.cos(a) * 0.08 * k * 0.4, 0.07, math.sin(a) * 0.08 * k * 0.4) * ANG(0, a, 0), L.of(234, 196, 172))
			end
		end
	elseif kind == "daechang" then
		for i = 1, 4 do
			K:cyl("Daechang", 0.6, 0.17, pos(i, 4) * CF(0, 0.09, 0), L.of(244, 230, 206))
		end
	elseif kind == "makchang" then
		for i = 1, 6 do
			K:make("Part", "Makchang", V3(0.08, 0.26, 0.26), pos(i, 6) * CF(0, 0.07, 0) * ANG(0, 0, PI / 2 - 0.15), L.of(204, 140, 118), Enum.PartType.Cylinder)
		end
	elseif kind == "heart" then
		for i = 1, 6 do
			K:ell("Yeomtong", V3(0.3, 0.08, 0.2), pos(i, 6) * CF(0, 0.05, 0), L.of(150, 50, 52))
		end
	elseif kind == "galbi" then
		for i = 1, 4 do
			local p = pos(i, 4)
			K:box("Galbi", V3(0.5, 0.06, 0.3), p * CF(0, 0.04, 0), L.of(132, 64, 36))
			K:cyl("GalbiBone", 0.3, 0.06, p * CF(0, 0.08, -0.12), L.of(236, 226, 206))
		end
	elseif kind == "pork" or kind == "neck" or kind == "jowl" then
		local lean = if kind == "neck" then L.of(200, 96, 92) elseif kind == "jowl" then L.of(236, 180, 170) else L.of(214, 110, 104)
		for i = 1, 3 do
			local p = pos(i, 3)
			K:box("Meat", V3(0.62, 0.05, 0.3), p * CF(0, 0.03, 0), lean)
			K:box("MeatFat", V3(0.62, 0.03, 0.3), p * CF(0, 0.07, 0), L.of(246, 236, 224))
			K:box("Meat", V3(0.62, 0.04, 0.3), p * CF(0, 0.105, 0), lean)
		end
	elseif kind == "seacucumber" then
		for i = 1, 4 do
			K:ell("Haesam", V3(0.46, 0.13, 0.18), pos(i, 4) * CF(0, 0.07, 0), L.of(62, 52, 48))
		end
	elseif kind == "squirt" then
		for i = 1, 5 do
			K:ell("Meongge", V3(0.24, 0.3, 0.22), pos(i, 5) * CF(0, 0.12, 0), L.of(226, 82, 52))
		end
	elseif kind == "spoonworm" then
		for i = 1, 5 do
			K:ell("Gaebul", V3(0.14, 0.12, 0.46), pos(i, 5) * CF(0, 0.06, 0), L.of(238, 140, 150))
		end
	elseif kind == "octopus" then
		for i = 1, 2 do
			local p = pos(i, 2)
			K:ell("NakjiHead", V3(0.24, 0.18, 0.28), p * CF(0, 0.09, 0), L.of(150, 70, 70))
			for k = 0, 5 do
				local a = k * PI / 3
				K:seg("NakjiArm", (p * CF(0, 0.04, 0)).Position, (p * CF(math.cos(a) * 0.34, 0.03, math.sin(a) * 0.34)).Position, 0.05, L.of(170, 90, 90))
			end
		end
	elseif kind == "conch" then
		for i = 1, 5 do
			local p = pos(i, 5)
			K:ell("Sora", V3(0.26, 0.22, 0.26), p * CF(0, 0.1, 0), L.of(176, 146, 108))
			K:ell("SoraTip", V3(0.12, 0.14, 0.12), p * CF(0.04, 0.24, 0), L.of(150, 120, 86))
		end
	end
end

local function displayOver(c: any)
	local K, V, th = c.K, c.V, c.th
	local sd = V.byName.ShellDisplay and V.byName.ShellDisplay[1]
	if not sd then
		return
	end
	local mn, mx = sd.min, sd.max
	local extra = {}
	for _, nm in { "Ice", "Clam" } do
		for _, r in within(V, nm, sd.min, sd.max, 0.3) do
			table.insert(extra, r)
			mx = mx:Max(r.max)
		end
	end
	local alongX = (sd.max.X - sd.min.X) >= (sd.max.Z - sd.min.Z)
	local cx, cz = sd.c.X, sd.c.Z
	local front = if alongX then V3(0, 0, if cz > (V.z0 + V.z1) / 2 then -1 else 1) else V3(if cx > 0 then -1 else 1, 0, 0)
	local W = if alongX then sd.max.X - sd.min.X else sd.max.Z - sd.min.Z
	local D = if alongX then sd.max.Z - sd.min.Z else sd.max.X - sd.min.X
	local p = V3(cx, 0, cz)
	local pcf = CFrame.lookAt(p, p - front)
	local top = sd.max.Y
	local maxY = math.min(3.32, mx.Y + 0.2)
	local kind = th.display or "ice"
	local steel = L.brushed
	K:free(function()
		K:box("DisplayBody", V3(W - 0.04, top - 0.32, D - 0.04), pcf * CF(0, 0.32 + (top - 0.32) / 2, 0), steel)
		K:box("DisplayKick", V3(W - 0.3, 0.32, D - 0.3), pcf * CF(0, 0.16, 0), L.of(30, 30, 32))
		K:plate("DisplayKickPlate", W - 0.3, 0.3, 0.02, pcf * CF(0, 0.16, (D - 0.3) / 2), L.of(150, 152, 156, M.DiamondPlate))
		-- 앞면 띠 (손님 쪽)
		local bandBg = if kind == "meat" then th.accent else (th.band or th.accent)
		txt(K, "DisplaySign", W - 0.5, 0.62, pcf * CF(0, top * 0.55, D / 2 - 0.02), th.displaySign or "", WHITE, bandBg, F.GothamBlack)
		if c.hi then
			txt(K, "DisplaySub", W - 0.9, 0.3, pcf * CF(0, top * 0.55 - 0.55, D / 2 - 0.02), if kind == "meat" then "냉장 0 ~ 2℃ 보관 · 주문 즉시 손질" else "수조 · 얼음 진열 · 원산지 국내산", rgb(60, 64, 70), rgb(236, 238, 240), F.GothamMedium)
		end
		-- 위 쟁반 테 (스테인리스)
		local ry0 = top - 0.06
		local rh = 0.34
		K:box("DisplayRim", V3(W, rh, 0.08), pcf * CF(0, ry0 + rh / 2, D / 2 - 0.04), L.steel)
		K:box("DisplayRim", V3(W, rh, 0.08), pcf * CF(0, ry0 + rh / 2, -D / 2 + 0.04), L.steel)
		K:box("DisplayRim", V3(0.08, rh, D - 0.16), pcf * CF(-W / 2 + 0.04, ry0 + rh / 2, 0), L.steel)
		K:box("DisplayRim", V3(0.08, rh, D - 0.16), pcf * CF(W / 2 - 0.04, ry0 + rh / 2, 0), L.steel)
		local bedTop = ry0 + rh - 0.06
		local bedL = if kind == "meat" then L.of(236, 238, 240) else { c = rgb(232, 244, 250), m = M.Ice, r = 0.1 }
		K:box("DisplayBed", V3(W - 0.16, bedTop - top + 0.06, D - 0.16), pcf * CF(0, (top - 0.06 + bedTop) / 2, 0), bedL)
		if kind ~= "meat" and c.hi then
			for i = 1, 10 do
				local x = (rnd(c.seed, i) - 0.5) * (W - 0.5)
				local z = (rnd(c.seed, i + 20) - 0.5) * (D - 0.5)
				K:ball("IceChunk", 0.14 + rnd(c.seed, i + 40) * 0.12, pcf * CF(x, bedTop + 0.02, z), { c = rgb(236, 246, 252), m = M.Glass, t = 0.35, r = 0.2 })
			end
		end
		-- 칸 나누기 + 해산물 / 고기 + 가격표
		local catch = th.catch or {}
		local n = math.max(1, math.min(#catch, math.floor((W - 0.3) / 0.95)))
		local sw = (W - 0.3) / n
		for i = 1, n do
			local x = -W / 2 + 0.15 + sw * (i - 0.5)
			local base = pcf * CF(x, bedTop, -0.12)
			if kind == "basin" then
				-- 빨간 고무 다라이 + 물
				K:vcyl("Darai", 0.16, sw - 0.1, base * CF(0, 0.08, 0), L.of(204, 36, 30, M.Rubber))
				K:vcyl("DaraiRim", 0.05, sw - 0.04, base * CF(0, 0.165, 0), L.of(180, 30, 26, M.Rubber))
				K:vcyl("DaraiWater", 0.02, sw - 0.2, base * CF(0, 0.13, 0), { c = rgb(140, 186, 200), m = M.Glass, t = 0.4, r = 0.2 })
				seafood(c, catch[i][1], base * CF(0, 0.1, 0), sw - 0.36, sw - 0.36, c.seed + i)
			elseif kind == "meat" then
				K:box("MeatTray", V3(sw - 0.12, 0.05, D - 0.6), base * CF(0, 0.025, 0), L.of(250, 250, 248))
				seafood(c, catch[i][1], base * CF(0, 0.05, 0), sw - 0.3, D - 0.8, c.seed + i)
			else
				seafood(c, catch[i][1], base, sw - 0.2, D - 0.7, c.seed + i)
			end
			if i < n then
				K:box("DisplayDivider", V3(0.04, 0.1, D - 0.3), pcf * CF(x + sw / 2, bedTop + 0.04, 0), L.steel)
			end
			-- 가격표 (꽂이)
			-- 앞 테에 기대 꽂은 가격표 (뒤로 많이 눕혀 해산물을 가리지 않게)
			local ty = math.min(maxY - 0.1, bedTop + 0.1)
			local tw = math.min(0.9, sw - 0.08)
			K:seg("TagPick", (pcf * CF(x, bedTop, D / 2 - 0.3)).Position, (pcf * CF(x, ty - 0.02, D / 2 - 0.24)).Position, 0.025, L.white)
			txt(K, "PriceTag", tw, 0.36, pcf * CF(x, ty, D / 2 - 0.2) * ANG(-1.05, 0, 0), catch[i][2], rgb(196, 0, 0), rgb(255, 252, 236), F.GothamBlack, { d = 0.02 })
		end
		if kind == "meat" then
			-- 냉장 쇼케이스 유리 (경사 앞유리 + 옆유리) + 위 LED
			local g = { c = rgb(220, 236, 242), m = M.SmoothPlastic, t = 0.84, r = 0.15 }
			local gy0, gy1 = ry0 + rh, maxY
			K:bar("CaseGlass", pcf * V3(0, gy0, D / 2 - 0.06), pcf * V3(0, gy1, D / 2 - 0.5), W - 0.1, 0.03, g)
			for _, sx in { -1, 1 } do
				K:box("CaseGlassSide", V3(0.03, gy1 - gy0, D - 0.2), pcf * CF(sx * (W / 2 - 0.05), (gy0 + gy1) / 2, 0), g)
			end
			K:box("CaseTop", V3(W - 0.06, 0.06, D * 0.55), pcf * CF(0, gy1 - 0.03, -D * 0.2), L.steel)
			K:box("CaseLED", V3(W - 0.3, 0.03, 0.08), pcf * CF(0, gy1 - 0.075, D / 2 - 0.62), L.lampNeutral)
		else
			-- 앞 테 파란 LED · 낮은 유리 가드
			K:box("DisplayLED", V3(W - 0.3, 0.04, 0.03), pcf * CF(0, ry0 + rh - 0.06, D / 2 + 0.005), L.neon(rgb(120, 200, 255)))
			K:bar("SneezeGuard", pcf * V3(0, ry0 + rh, D / 2 - 0.05), pcf * V3(0, maxY - 0.02, D / 2 - 0.2), W - 0.1, 0.02, { c = rgb(220, 236, 242), m = M.SmoothPlastic, t = 0.84, r = 0.15 })
		end
	end)
	hideRec(K, sd)
	for _, r in extra do
		hideRec(K, r)
	end
	K:note(string.format("display @ %.1f,%.1f", cx, cz))
end

-- 천장 -------------------------------------------------------------------------------------------------
-- 전구 줄 한 가닥: a -> b, span 마다 처짐, 전구 간격 step
local function bulbLine(c: any, a: Vector3, b: Vector3, span: number, step: number, sag: number)
	local K = c.K
	c.bulbs = c.bulbs or {}
	local len = (b - a).Magnitude
	local ns = math.max(1, math.floor(len / span + 0.5))
	local per = math.max(1, math.floor((len / ns) / step + 0.5))
	local cable = L.of(26, 26, 28)
	local warm = rgb(255, 196, 120)
	local prev = a
	local k = 0
	for s = 1, ns do
		for j = 1, per do
			local t = j / per
			local u = ((s - 1) + t) / ns
			local p = a:Lerp(b, u) - V3(0, sag * 4 * t * (1 - t), 0)
			local q = prev
			prev = p
			local bmn, bmx = (q:Min(p)) - V3(0.16, 0.5, 0.16), (q:Max(p)) + V3(0.16, 0.05, 0.16)
			if K:hitsKeep(bmn, bmx) then
				continue
			end
			K:seg("BulbCable", q, p, 0.03, cable)
			k += 1
			if c.hi then
				K:vcyl("BulbSocket", 0.14, 0.12, CF(p - V3(0, 0.08, 0)), L.of(30, 30, 32))
			end
			local bc = if (k + c.seed) % 7 == 0 then rgb(255, 150, 80) else warm
			local bulb = K:ball("StringBulb", 0.3, CF(p - V3(0, 0.3, 0)), L.neon(bc))
			table.insert(c.bulbs, { p = bulb, c = bc })
		end
	end
end

-- 천막 천장 (실내포차): 파이프 골조 + 늘어진 천막 + 옆 처마 + 앞 가림막 (가게 이름) + 전구 줄
local function tentCeiling(c: any)
	local K, V, th = c.K, c.V, c.th
	local tarp = th.tarp
	local x0, x1 = V.x0 + 0.04, V.x1 - 0.04
	local z0, zf = V.z0 + 0.04, V.z1 - 2.0
	local yp = V.H - 0.55
	local sag = 0.36
	local rowsZ = {}
	for _, g in c.grills or {} do
		if g.hood then
			table.insert(rowsZ, g.hood.c.Z)
		end
	end
	local nb = math.max(3, math.floor((zf - z0) / 4.0 + 0.5))
	local zs = {}
	for k = 0, nb do
		zs[k + 1] = z0 + (zf - z0) * k / nb
	end
	for k = 2, nb do
		for _, rz in rowsZ do
			if math.abs(zs[k] - rz) < 0.9 then
				zs[k] = rz + (if zs[k] < rz then -0.9 else 0.9)
			end
		end
	end
	local tl = col(tarp.a, M.SmoothPlastic)
	local tl2 = col(tarp.b, M.SmoothPlastic)
	local trim = col(tarp.trim, M.SmoothPlastic)
	local pipe = L.of(178, 182, 186, M.Metal)
	local cx = (x0 + x1) / 2
	K:free(function()
		for k = 1, nb do
			local za, zb = zs[k], zs[k + 1]
			local zm = (za + zb) / 2
			local look = if k % 2 == 0 then tl2 else tl
			K:bar("Tarp", V3(cx, yp + 0.04, za), V3(cx, yp + 0.04 - sag, zm), x1 - x0, 0.04, look)
			K:bar("Tarp", V3(cx, yp + 0.04 - sag, zm), V3(cx, yp + 0.04, zb), x1 - x0, 0.04, look)
		end
		for k = 1, nb + 1 do
			K:seg("TentPipe", V3(x0, yp - 0.03, zs[k]), V3(x1, yp - 0.03, zs[k]), 0.12, pipe)
		end
		-- 옆 처마 (좌 · 우 · 뒤): 벽에서 안쪽으로 내려오는 경사 천막 + 끝단 띠
		local ew, ed = 1.3, 0.85
		for _, sx in { -1, 1 } do
			local xw = if sx < 0 then V.x0 + 0.03 else V.x1 - 0.03
			local xi = xw - sx * ew
			K:bar("TarpEave", V3(xw, yp + 0.05, (z0 + zf) / 2), V3(xi, yp - ed, (z0 + zf) / 2), zf - z0, 0.04, tl)
			K:seg("TarpEaveHem", V3(xi, yp - ed - 0.02, z0 + 0.1), V3(xi, yp - ed - 0.02, zf), 0.07, trim)
		end
		K:bar("TarpEave", V3(cx, yp + 0.05, V.z0 + 0.03), V3(cx, yp - ed, V.z0 + 0.03 + ew), x1 - x0 - 2 * ew, 0.04, tl)
		K:seg("TarpEaveHem", V3(x0 + ew, yp - ed - 0.02, V.z0 + 0.03 + ew), V3(x1 - ew, yp - ed - 0.02, V.z0 + 0.03 + ew), 0.07, trim)
		-- 앞 가림막: 천막 띠 + 흰 테 + 가게 이름 (안쪽에서 보이게)
		local vh = 0.95
		local vy = yp + 0.04 - vh / 2
		K:box("TarpValance", V3(x1 - x0, vh, 0.05), CF(cx, vy, zf), tl)
		K:box("TarpValanceTrim", V3(x1 - x0, 0.1, 0.07), CF(cx, yp + 0.04 - vh + 0.05, zf), trim)
		local name = V.name or "포장마차"
		local nameDcf = CFrame.fromMatrix(V3(cx, vy + 0.06, zf - 0.03), V3(1, 0, 0), Vector3.yAxis, V3(0, 0, 1)) * ANG(0, PI, 0)
		txt(K, "TarpName", math.min(14, (x1 - x0) * 0.45), vh * 0.66, nameDcf, name .. "  ·  실내포장마차", tarp.trim, nil, F.GothamBlack, { d = 0.01 })
	end)
	-- 전구 줄 (파이프 아래, 안쪽 줄마다)
	local step = if c.hi then 1.5 elseif K.detail == "mid" then 2.2 else 3.2
	for k = 2, nb do
		bulbLine(c, V3(x0 + 0.6, yp - 0.12, zs[k]), V3(x1 - 0.6, yp - 0.12, zs[k]), 3.6, step, 0.42)
	end
	-- 처마 끝 줄 (앞 가림막 안쪽)
	bulbLine(c, V3(x0 + 1.4, yp - 0.95, zf - 0.25), V3(x1 - 1.4, yp - 0.95, zf - 0.25), 3.6, step * 1.4, 0.3)
	c.tentZs = zs
end

-- 벽 둘레 천막 처마 (24시 포차: 가운데 천장은 형광등 그대로)
local function tentEaves(c: any)
	local K, V, th = c.K, c.V, c.th
	local tarp = th.tarp
	local tl = col(tarp.a, M.SmoothPlastic)
	local trim = col(tarp.trim, M.SmoothPlastic)
	local ew, drop = 2.0, 1.25
	local yt = V.H - 0.25
	local zf = V.z1 - 2.0
	K:free(function()
		for _, sx in { -1, 1 } do
			local xw = if sx < 0 then V.x0 + 0.03 else V.x1 - 0.03
			local xi = xw - sx * ew
			K:bar("TarpEave", V3(xw, yt, (V.z0 + zf) / 2), V3(xi, yt - drop, (V.z0 + zf) / 2), zf - V.z0 - 0.1, 0.04, tl)
			K:box("TarpEaveFlap", V3(0.04, 0.6, zf - V.z0 - 0.1), CF(xi, yt - drop - 0.28, (V.z0 + zf) / 2), tl)
			K:box("TarpEaveHem", V3(0.06, 0.09, zf - V.z0 - 0.1), CF(xi, yt - drop - 0.6, (V.z0 + zf) / 2), trim)
		end
		local cx = (V.x0 + V.x1) / 2
		local bl = V.W - 2 * ew - 0.1
		K:bar("TarpEave", V3(cx, yt, V.z0 + 0.03), V3(cx, yt - drop, V.z0 + 0.03 + ew), bl, 0.04, tl)
		K:box("TarpEaveFlap", V3(bl, 0.6, 0.04), CF(cx, yt - drop - 0.28, V.z0 + 0.03 + ew), tl)
		K:box("TarpEaveHem", V3(bl, 0.09, 0.06), CF(cx, yt - drop - 0.6, V.z0 + 0.03 + ew), trim)
	end)
	local step = if c.hi then 1.6 else 2.6
	local y = yt - drop - 0.65
	bulbLine(c, V3(V.x0 + ew + 0.1, y, V.z0 + 2.3), V3(V.x0 + ew + 0.1, y, zf - 0.4), 3.6, step, 0.3)
	bulbLine(c, V3(V.x1 - ew - 0.1, y, V.z0 + 2.3), V3(V.x1 - ew - 0.1, y, zf - 0.4), 3.6, step, 0.3)
	bulbLine(c, V3(V.x0 + ew + 0.6, y, V.z0 + ew + 0.15), V3(V.x1 - ew - 0.6, y, V.z0 + ew + 0.15), 3.6, step, 0.3)
end

-- 전구 빛 (몇 개만 PointLight) + 켜기/끄기 스위치 상태
local function bulbLights(c: any, n: number)
	local K = c.K
	local list = c.bulbs or {}
	c.bulbLights = {}
	if #list == 0 then
		return
	end
	for i = 1, n do
		local b = list[math.clamp(math.floor(#list * (i - 0.5) / n) + 1, 1, #list)]
		local l = K:light(b.p, "PointLight", { Range = 15, Brightness = 0.75, Color = rgb(255, 190, 130) })
		if l then
			table.insert(c.bulbLights, l)
		end
	end
end

-- 불판집 천장: 선형 LED 등기구 (덕트 줄 사이)
local function grillLights(c: any)
	local K, V, th = c.K, c.V, c.th
	local zs = {}
	local rows = {}
	for _, g in c.grills or {} do
		if g.hood then
			local found = false
			for _, r in rows do
				if math.abs(r - g.hood.c.Z) < 1 then
					found = true
				end
			end
			if not found then
				table.insert(rows, g.hood.c.Z)
			end
		end
	end
	table.sort(rows)
	if #rows >= 2 then
		for i = 1, #rows - 1 do
			table.insert(zs, (rows[i] + rows[i + 1]) / 2)
		end
		table.insert(zs, math.max(V.z0 + 1.6, rows[1] - 3.4))
		table.insert(zs, math.min(V.z1 - 2.6, rows[#rows] + 3.4))
	else
		zs = { V.z0 + V.D * 0.25, V.z0 + V.D * 0.62 }
	end
	local housing = L.white
	local lamp = th.lamp or L.lampCool
	local nl = 0
	for zi, z in zs do
		local x = V.x0 + 2.0
		while x < V.x1 - 2.0 do
			local len = math.min(5.5, V.x1 - 2.0 - x)
			if len < 2.4 then
				break
			end
			local mn, mx = V3(x, V.H - 1.2, z - 0.5), V3(x + len, V.H, z + 0.5)
			local clear = true
			for _, r in V.parts do
				if not r.shell and r.max.Y > V.H - 1.2 and overlap(mn, mx, r.min, r.max) then
					clear = false
					break
				end
			end
			if clear then
				K:free(function()
					local cxl = x + len / 2
					K:box("LedHousing", V3(len, 0.14, 0.44), CF(cxl, V.H - 0.07, z), housing)
					local d = K:box("LedDiffuser", V3(len - 0.12, 0.03, 0.3), CF(cxl, V.H - 0.155, z), lamp)
					nl += 1
					if nl % 3 == 1 and zi <= 3 then
						K:light(d, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 16, Brightness = if th.key == "gopchang" then 0.95 else 0.8, Angle = 140, Color = th.light or L.coolLight })
					end
				end)
				x += len + 1.6
			else
				x += 1.0
			end
		end
	end
end

-- 벽 장식 ---------------------------------------------------------------------------------------------
local function plateSign(K: any, dcf: CFrame, w: number, h: number, s: string, fg: Color3, bg: Color3, frameL: any?, font: Enum.Font?, o: any?): (BasePart, TextLabel)
	K:plate("SignBack", w + 0.1, h + 0.1, 0.04, dcf, frameL or L.of(44, 44, 48, M.Metal))
	return txt(K, "SignText", w, h, dcf * CF(0, 0, 0.04), s, fg, bg, font, o)
end

-- 두 단어 메뉴는 두 줄로 ("꼼장어 구이" -> "꼼장어\n구이")
local function twoLines(s: string): string
	local n = 0
	for _ in utf8.codes(s) do
		n += 1
	end
	if n > 4 then
		local i = string.find(s, " ", 1, true)
		if i then
			return string.sub(s, 1, i - 1) .. "\n" .. string.sub(s, i + 1)
		end
	end
	return s
end

-- 큰 메뉴판 (파란 라이트박스 / 나무 간판) + 식사 · 주류 판
local function mainMenus(c: any)
	local K, V, th = c.K, c.V, c.th
	local opts: any
	if th.menuStyle == "blue" then
		opts = { bg = th.accent, fg = WHITE, accent = th.accent2, glow = 1.15, frame = L.of(232, 234, 238, M.Metal) }
	else
		opts = { bg = rgb(58, 38, 24), fg = rgb(250, 236, 210), accent = rgb(250, 196, 110), glow = 1.0, frame = L.of(36, 24, 16, M.Wood) }
	end
	local near = V3(V.x0 * 0.5, 0, V.z0)
	local wn, u, w = findWall(K, { "back", "left", "right" }, 6.0, 8.2, 5.4, 8.9, near, 0.8)
	if not wn or not u or not w then
		return
	end
	local dcf = V:wall(wn, u, 7.15, 0)
	Props.menuBoard(K, dcf, w, 3.0, th.title .. " 메뉴", th.menu, opts)
	if c.hi then
		-- 메뉴판 위 작은 조명 2개 (갓 + 팔)
		for _, sx in { -1, 1 } do
			local a = dcf * CF(sx * w * 0.3, 1.75, 0)
			K:plate("MenuLampMount", 0.2, 0.2, 0.06, a, L.blackMetal)
			K:bar("MenuLampArm", (a * CF(0, 0, 0.06)).Position, (a * CF(0, 0.15, 0.6)).Position, 0.05, 0.05, L.blackMetal)
			local hd = a * CF(0, 0.12, 0.66) * ANG(-0.9, 0, 0)
			K:vcyl("MenuLampHead", 0.24, 0.22, hd, L.blackMetal)
			K:disc("MenuLampLens", 0.18, 0.02, hd * CF(0, -0.13, 0), L.lampWarm)
		end
	end
	at(K, "menu", wn, u)
	local wn2, u2, w2 = findWall(K, { wn, "left", "right", "back" }, 3.0, 3.8, 5.4, 8.9, V:wall(wn, u, 0, 0).Position, 0.8)
	if wn2 and u2 and w2 then
		local o2 = table.clone(opts)
		o2.cols = 1
		Props.menuBoard(K, V:wall(wn2, u2, 7.15, 0), w2, 3.0, th.sideTitle or "식사 · 주류", th.side, o2)
	end
end

-- 손글씨 색지 메뉴 줄 (포차): 벽마다 빈 구간에 한 장씩
local function menuSheets(c: any)
	local K, V, th = c.K, c.V, c.th
	local items = th.sheets or POCHA_SHEETS
	local papers = { rgb(255, 250, 236), rgb(255, 234, 96), rgb(255, 204, 212), rgb(214, 242, 222), rgb(255, 214, 150) }
	local inks = { INK, rgb(24, 52, 150), INK, rgb(30, 110, 50) }
	local sw, sh, gap = 1.12, 1.5, 0.14
	local y0, y1 = 6.3, 8.1
	local idx = 1
	for pass = 1, 2 do
		for _, wn in { "left", "back", "right" } do
			for _, s in freeSpans(K, wn, y0, y1, 0.6) do
				local span = s[2] - s[1] - 0.3
				local n = math.min(math.floor((span + gap) / (sw + gap)), if pass == 1 then 9 else 6)
				if n >= 2 and idx <= #items then
					n = math.min(n, #items - idx + 1)
					local tot = n * sw + (n - 1) * gap
					local start = (s[1] + s[2]) / 2 - tot / 2
					for i = 1, n do
						local it = items[idx]
						idx += 1
						local u = start + (sw + gap) * (i - 1) + sw / 2
						local rot = (rnd(c.seed, idx * 3) - 0.5) * 0.09
						local yy = (y0 + y1) / 2 + (rnd(c.seed, idx * 5) - 0.5) * 0.12
						local d = V:wall(wn, u, yy, 0) * ANG(0, 0, rot)
						K:plate("MenuSheet", sw, sh, 0.02, d, col(papers[(idx + c.seed) % #papers + 1]))
						txt(K, "SheetItem", sw - 0.14, sh * 0.5, d * CF(0, sh * 0.15, 0.021), twoLines(it[1]), inks[(idx + c.seed) % #inks + 1], nil, F.GothamBlack, { d = 0.005, glow = 0.9 })
						txt(K, "SheetPrice", sw - 0.24, sh * 0.24, d * CF(0, -sh * 0.29, 0.021), it[2], rgb(214, 24, 24), nil, F.GothamBold, { d = 0.005, glow = 0.9 })
						if c.hi then
							K:plate("SheetTape", 0.3, 0.12, 0.005, d * CF(-sw / 2 + 0.12, sh / 2 - 0.02, 0.02) * ANG(0, 0, 0.6), { c = rgb(240, 236, 220), m = M.SmoothPlastic, t = 0.35 })
							K:plate("SheetTape", 0.3, 0.12, 0.005, d * CF(sw / 2 - 0.12, sh / 2 - 0.02, 0.02) * ANG(0, 0, -0.6), { c = rgb(240, 236, 220), m = M.SmoothPlastic, t = 0.35 })
						end
					end
					claim(K, wn, start - 0.15, start + tot + 0.15, y0, y1)
				end
			end
		end
		if idx > #items then
			break
		end
	end
	at(K, "sheets", "n", idx - 1)
end

-- 오늘의 추천 칠판 (포차)
local function chalkboard(c: any)
	local K, V, th = c.K, c.V, c.th
	local wn, u = findWall(K, { "left", "right", "back" }, 2.4, 2.4, 3.9, 6.2, V3(0, 0, V.z0 + 3), 0.5)
	if not wn or not u then
		return
	end
	local d = V:wall(wn, u, 5.05, 0)
	K:plate("ChalkFrame", 2.4, 2.2, 0.06, d, L.of(120, 80, 48, M.Wood))
	K:plate("ChalkBoard", 2.2, 2.0, 0.07, d, L.of(34, 52, 44, M.Slate))
	txt(K, "ChalkTitle", 1.9, 0.42, d * CF(0, 0.66, 0.075), "오늘의 추천", rgb(255, 226, 90), nil, F.GothamBlack, { d = 0.005 })
	txt(K, "ChalkBody", 2.0, 1.1, d * CF(0, -0.18, 0.075), if th.key == "pocha24" then "새벽 해장 세트\n국밥 + 소주 1병\n14,000" else "산낙지 · 해삼 · 멍게\n싯가 (문의)\n홍합탕 무한리필!", rgb(244, 244, 236), nil, F.GothamBold, { d = 0.005 })
	K:box("ChalkTray", V3(2.0, 0.06, 0.16), d * CF(0, -1.04, 0.1), L.of(120, 80, 48, M.Wood))
	K:box("Chalk", V3(0.3, 0.05, 0.05), d * CF(0.5, -1.0, 0.12), L.white)
end

-- 원산지 표시판 (흰 아크릴 + 색 머리띠)
local function originBoard(c: any, near: Vector3?)
	local K, V, th = c.K, c.V, c.th
	local wn, u = findWall(K, { "back", "left", "right" }, 2.7, 2.7, 4.2, 6.7, near, 0.6)
	if not wn or not u then
		return
	end
	local d = V:wall(wn, u, 5.45, 0)
	local body = string.gsub(th.origin or "", "^원산지 표시\n", "")
	K:plate("OriginBack", 2.7, 2.3, 0.04, d, L.of(250, 250, 248))
	K:plate("OriginHead", 2.7, 0.44, 0.05, d * CF(0, 0.93, 0), col(th.accent))
	txt(K, "OriginTitle", 2.3, 0.32, d * CF(0, 0.93, 0.05), "원산지 표시", WHITE, nil, F.GothamBlack, { d = 0.005 })
	txt(K, "OriginText", 2.5, 1.66, d * CF(0, -0.22, 0.045), body, INK, nil, F.GothamMedium, { d = 0.005, align = "Left", glow = 0.9 })
	at(K, "origin", wn, u)
end

-- 작은 안내판들: 영업시간 · 결제 · 와이파이 · 청소년 주류 금지 · 금연
local function infoSigns(c: any)
	local K, V, th = c.K, c.V, c.th
	local nearFront = V3(V.x0 + 1, 0, V.z1 - 4)
	local wn, u = findWall(K, { "left", "right", "back" }, 1.7, 1.7, 4.4, 5.9, nearFront, 0.5)
	if wn and u then
		local d = V:wall(wn, u, 5.15, 0)
		plateSign(K, d, 1.6, 1.3, th.hours or "영업시간", WHITE, rgb(30, 30, 34), L.of(200, 170, 90, M.Metal), F.GothamBold)
	end
	local wn2, u2 = findWall(K, { "left", "right", "back" }, 1.8, 1.8, 4.4, 5.6, nearFront, 0.5)
	if wn2 and u2 then
		local d = V:wall(wn2, u2, 5.0, 0)
		plateSign(K, d, 1.7, 0.9, "카드 · 동백전\n제로페이 결제 OK", rgb(20, 60, 140), rgb(248, 248, 244), nil, F.GothamBold)
	end
	local wn3, u3 = findWall(K, { "right", "left", "back" }, 1.6, 1.6, 4.4, 5.5, V3(V.x1 - 1, 0, 0), 0.5)
	if wn3 and u3 then
		local d = V:wall(wn3, u3, 4.95, 0)
		local wifi = "WiFi  " .. (if th.pocha then "POCHA_5G" else "GRILL_5G") .. "\nPW  0517" .. string.format("%04d", c.seed % 10000)
		plateSign(K, d, 1.5, 0.8, wifi, WHITE, rgb(40, 120, 200), nil, F.GothamBold)
	end
	local wn4, u4 = findWall(K, { "left", "right", "back" }, 1.3, 1.3, 4.3, 5.7, nearFront, 0.5)
	if wn4 and u4 then
		local d = V:wall(wn4, u4, 5.0, 0)
		wdisc(K, "Age19Ring", 1.2, 0.03, d, 0, L.of(210, 30, 30))
		wdisc(K, "Age19Face", 1.0, 0.03, d, 0.01, L.white)
		txt(K, "Age19", 0.7, 0.42, d * CF(0, 0.12, 0.045), "19", rgb(210, 30, 30), nil, F.GothamBlack, { d = 0.005 })
		txt(K, "Age19Sub", 0.8, 0.22, d * CF(0, -0.22, 0.045), "청소년 주류 판매 금지", INK, nil, F.GothamBold, { d = 0.005 })
	end
	local wn5, u5 = findWall(K, { "right", "left", "back" }, 1.0, 1.0, 4.3, 5.5, V3(V.x1, 0, V.z1 - 5), 0.5)
	if wn5 and u5 then
		local d = V:wall(wn5, u5, 4.9, 0)
		wdisc(K, "NoSmokeRing", 0.9, 0.03, d, 0, L.of(210, 30, 30))
		wdisc(K, "NoSmokeFace", 0.74, 0.03, d, 0.01, L.white)
		K:plate("NoSmokeCig", 0.5, 0.1, 0.01, d * CF(0, 0, 0.045), L.of(60, 60, 60))
		K:plate("NoSmokeBar", 0.8, 0.09, 0.012, d * CF(0, 0, 0.05) * ANG(0, 0, -0.78), L.of(210, 30, 30))
		txt(K, "NoSmoke", 0.9, 0.22, d * CF(0, -0.62, 0.02), "금연 구역", INK, nil, F.GothamBold, { d = 0.005 })
	end
end

-- 사인지 벽 (손님 · 유명인 다녀감)
local AUTOS = {
	"대박나세요!\n♡ 2025.07", "또 올게요~\n광안리 최고", "조개 최고!!\n부산 사나이", "번창하세요\n2024.08.15",
	"맛있게 먹고\n갑니다 ♥", "사장님 짱\n2026.05.03", "부산 오면\n무조건 여기", "소주가 술술\n♡♡♡",
	"불맛 인정!\n- 서울에서 -", "다음엔\n친구들이랑!",
}
local function autographs(c: any)
	local K, V, th = c.K, c.V, c.th
	local wn, u, w = findWall(K, { "left", "right", "back" }, 3.4, 4.6, 4.7, 8.5, V3(0, 0, 0), 0.5)
	if not wn or not u or not w then
		return
	end
	local cols = math.floor((w + 0.12) / 1.12)
	local inks = { rgb(30, 30, 120), rgb(180, 20, 20), INK, rgb(20, 90, 40) }
	txt(K, "AutoTitle", math.min(w, 3.6), 0.42, V:wall(wn, u, 8.2, 0), "다녀가신 분들 ♥", th.accent, nil, F.GothamBlack, { d = 0.01 })
	local k = 0
	for row = 0, 1 do
		for i = 1, cols do
			k += 1
			local x = u - (cols * 1.12) / 2 + 1.12 * (i - 0.5)
			local y = 7.2 - row * 1.42
			local rot = (rnd(c.seed, k * 7) - 0.5) * 0.12
			local d = V:wall(wn, x, y, 0) * ANG(0, 0, rot)
			if (k + c.seed) % 3 == 0 then
				K:plate("AutoFrame", 1.04, 1.28, 0.04, d, L.of(30, 30, 32))
				K:plate("AutoPaper", 0.92, 1.14, 0.05, d, L.of(252, 250, 244))
			else
				K:plate("AutoPaper", 0.92, 1.14, 0.02, d, L.of(252, 250, 244))
			end
			txt(K, "AutoText", 0.84, 0.9, d * CF(0, 0, 0.055), AUTOS[(k + c.seed) % #AUTOS + 1], inks[(k + c.seed) % #inks + 1], nil, F.GothamBold, { d = 0.004, glow = 0.9 })
		end
	end
	at(K, "autographs", wn, u)
end

-- 포스터 (액자 + 색 블록 + 글자)
local function posters(c: any)
	local K, V, th = c.K, c.V, c.th
	for i, ps in th.posters or {} do
		local wn, u = findWall(K, { if i == 1 then "right" else "left", "back", if i == 1 then "left" else "right" }, 1.9, 1.9, 4.5, 7.6, V3(0, 0, V.z0 + 4), 0.5)
		if wn and u then
			local d = V:wall(wn, u, 6.05, 0)
			Props.frame(K, d, 1.8, 2.6, {
				frame = L.of(30, 30, 32, M.Metal),
				mat = col(ps[3]),
				art = {
					{ ps[3]:Lerp(Color3.new(1, 1, 1), 0.18), 0.0, 0.0, 1.0, 0.36 },
					{ rgb(44, 146, 82), 0.62, 0.06, 0.16, 0.42 },
					{ rgb(44, 146, 82), 0.665, 0.46, 0.07, 0.14 },
					{ rgb(250, 250, 248), 0.63, 0.16, 0.14, 0.12 },
				},
				text = ps[1],
				fg = ps[2],
				textH = 0.42,
				textY = 0.5,
			})
		end
	end
end

-- 앞치마 걸이 (원목 레일 + 고리 + 앞치마)
local function apronRack(c: any)
	local K, V, th = c.K, c.V, c.th
	local list = th.aprons or {}
	if #list == 0 then
		return
	end
	local wn, u, w = findWall(K, { "left", "right", "back" }, 2.6, 0.82 * #list + 0.3, 3.7, 7.1, V3(0, 0, V.z1 - 5), 0.6)
	if not wn or not u or not w then
		return
	end
	local n = math.min(#list, math.floor((w - 0.2) / 0.8))
	local d = V:wall(wn, u, 6.25, 0)
	K:plate("ApronRail", w, 0.14, 0.1, d, L.of(120, 80, 50, M.Wood))
	for i = 1, n do
		local x = -w / 2 + w * (i - 0.5) / n
		local cc: Color3 = list[i]
		local fab = col(cc, M.Fabric)
		K:box("ApronHook", V3(0.06, 0.06, 0.24), d * CF(x, 0.02, 0.2), L.chrome)
		local a = d * CF(x, -0.98, 0.13) * ANG(0.03, 0, (rnd(c.seed, i) - 0.5) * 0.06)
		K:plate("Apron", 0.76, 1.5, 0.04, a, fab)
		K:plate("ApronPocket", 0.5, 0.3, 0.012, a * CF(0, -0.38, 0.04), dim(fab, 0.18))
		for _, sx in { -1, 1 } do
			K:bar("ApronStrap", (a * CF(sx * 0.26, 0.74, 0.02)).Position, (d * CF(x, 0.04, 0.3)).Position, 0.05, 0.02, fab)
		end
		if c.hi then
			txt(K, "ApronLogo", 0.6, 0.2, a * CF(0, 0.2, 0.042), th.shop or "", WHITE, nil, F.GothamBold, { d = 0.004 })
		end
	end
	txt(K, "ApronSign", math.min(w, 3.8), 0.4, V:wall(wn, u, 6.8, 0), "앞치마 · 비닐장갑은 셀프입니다", INK, rgb(255, 226, 90), F.GothamBold, { d = 0.03 })
	at(K, "aprons", wn, u)
end

-- 주방 문 (스테인리스 스윙 도어 · 둥근 창 · 노렌 · STAFF ONLY), 뒷벽에 납작하게
local function kitchenDoor(c: any)
	local K, V, th = c.K, c.V, c.th
	local wn, u = findWall(K, { "back" }, 3.4, 3.4, 0.05, 7.9, V3(V.x0 * 0.55, 0, V.z0), 0.9)
	if not wn or not u then
		return
	end
	local d = V:wall(wn, u, 0, 0)
	K:plate("KDoorCasing", 3.3, 7.4, 0.08, d * CF(0, 3.7, 0), L.of(150, 154, 158, M.Metal))
	K:plate("KDoorShadow", 3.0, 7.15, 0.09, d * CF(0, 3.575, 0), L.of(40, 40, 42))
	K:plate("KDoorLeaf", 1.44, 7.05, 0.13, d * CF(-0.74, 3.55, 0), L.brushed)
	K:plate("KDoorLeaf", 1.44, 7.05, 0.13, d * CF(0.74, 3.55, 0), L.brushed)
	for _, sx in { -0.74, 0.74 } do
		K:plate("KDoorKick", 1.36, 0.9, 0.14, d * CF(sx, 0.5, 0), L.of(130, 134, 138, M.DiamondPlate))
		wdisc(K, "KDoorPortRim", 0.78, 0.03, d * CF(sx, 5.3, 0), 0.13, L.of(70, 70, 74, M.Metal))
		wdisc(K, "KDoorPort", 0.64, 0.02, d * CF(sx, 5.3, 0), 0.15, { c = rgb(255, 214, 160), m = M.Glass, t = 0.25, r = 0.2 })
		K:plate("KDoorPush", 0.3, 0.9, 0.15, d * CF(sx + (if sx < 0 then 0.5 else -0.5), 3.6, 0), L.chrome)
	end
	plateSign(K, d * CF(0, 3.0, 0.15), 1.7, 0.42, "STAFF ONLY · 관계자 외 출입금지", INK, rgb(255, 214, 40), L.black, F.GothamBold)
	-- 노렌 (문 위 짧은 천 2장)
	local nc = th.accent
	K:seg("NorenRod", (d * CF(-1.6, 7.25, 0.32)).Position, (d * CF(1.6, 7.25, 0.32)).Position, 0.06, L.of(120, 80, 50, M.Wood))
	for i, ch in { "주", "방" } do
		local x = if i == 1 then -0.76 else 0.76
		local nd = d * CF(x, 6.55, 0.3)
		K:plate("Noren", 1.46, 1.3, 0.03, nd, col(nc, M.Fabric))
		txt(K, "NorenText", 0.9, 0.9, nd * CF(0, 0.05, 0.031), ch, WHITE, nil, F.GothamBlack, { d = 0.004 })
	end
	at(K, "kitchen door", wn, u)
end

-- 벽걸이 선풍기 (날개 회전 · 줄 스위치)
local function wallFan(c: any)
	local K, V = c.K, c.V
	local wn, u = findWall(K, { "left", "right", "back" }, 1.9, 1.9, 7.0, 8.95, V3(0, 0, V.z0 + 3), 0.6, function(wn2: string, cu: number)
		return promptWallOK(c, wn2, cu, 4.7) and not usedHit(K, wn2, cu - 0.4, cu + 0.4, 4.2, 5.2) and #freeSpans(K, wn2, 4.2, 7.0, 0.6) > 0
	end)
	if not wn or not u then
		return
	end
	claim(K, wn, u - 0.4, u + 0.4, 4.2, 7.0)
	local dcf = V:wall(wn, u, 8.05, 0)
	local body = L.of(240, 240, 236, M.Plastic)
	K:plate("FanMount", 0.5, 0.7, 0.08, dcf, body)
	local hub = dcf * CF(0, -0.2, 0.95) * ANG(-0.45, 0, 0)
	K:bar("FanArm", (dcf * CF(0, 0, 0.08)).Position, (hub * CF(0, 0, -0.45)).Position, 0.14, 0.14, body)
	K:ell("FanMotor", V3(0.44, 0.44, 0.62), hub * CF(0, 0, -0.42), body)
	local guard = { c = rgb(228, 230, 234), m = M.Metal, t = 0.72 }
	K:make("Part", "FanGuard", V3(0.04, 1.5, 1.5), hub * CF(0, 0, -0.12) * ANG(0, PI / 2, 0), guard, Enum.PartType.Cylinder)
	K:make("Part", "FanGuard", V3(0.04, 1.5, 1.5), hub * CF(0, 0, 0.2) * ANG(0, PI / 2, 0), guard, Enum.PartType.Cylinder)
	K:ring("FanRim", hub * CF(0, 0, 0.04), 0.76, 0.05, 12, L.of(232, 234, 238, M.Metal))
	K:make("Part", "FanBadge", V3(0.05, 0.34, 0.34), hub * CF(0, 0, 0.22) * ANG(0, PI / 2, 0), L.of(40, 110, 200), Enum.PartType.Cylinder)
	local blades = {}
	for i = 0, 2 do
		local a = i * 2 * PI / 3
		local b = K:ell("FanBlade", V3(0.38, 0.64, 0.04), hub * CF(0, 0, 0.04) * ANG(0, 0, a) * CF(0, 0.34, 0) * ANG(0, 0.25, 0), { c = rgb(140, 196, 240), m = M.Glass, t = 0.3 })
		table.insert(blades, b)
	end
	-- 줄 스위치 (손이 닿는 높이)
	local sd = V:wall(wn, u, 4.7, 0)
	K:seg("FanCord", (dcf * CF(0.18, -0.35, 0.06)).Position, (sd * CF(0.18, 0.3, 0.06)).Position, 0.02, L.white)
	local sw = K:plate("FanSwitch", 0.42, 0.6, 0.1, sd, L.of(246, 246, 242, M.Plastic))
	K:plate("FanSwitchKnob", 0.16, 0.16, 0.14, sd * CF(0, 0.1, 0), L.of(40, 110, 200))
	txt(K, "FanSwitchLabel", 0.5, 0.16, sd * CF(0, -0.42, 0.01), "선풍기", rgb(60, 60, 64), nil, F.GothamBold, { d = 0.004 })
	local hubW = K.cf * hub * CF(0, 0, 0.04)
	local rel = {}
	for _, b in blades do
		if b.Parent then
			table.insert(rel, { p = b, r = hubW:ToObjectSpace(b.CFrame) })
		end
	end
	local on, ang, spd = false, 0, 0
	Interact.toggle(K, sw, {
		object = "벽걸이 선풍기",
		onText = "끄기",
		offText = "켜기",
		state = false,
		on = function(s: boolean)
			on = s
		end,
	})
	Interact.anim(K, function(_t: number, dt: number)
		spd = spd + ((if on then 14 else 0) - spd) * math.min(1, dt * 1.5)
		if spd < 0.05 then
			return
		end
		ang += spd * dt
		local rot = hubW * ANG(0, 0, ang)
		for _, r in rel do
			if r.p.Parent then
				r.p.CFrame = rot * r.r
			end
		end
	end)
	at(K, "fan", wn, u)
end

-- 환풍기 (벽 높이 · 날개 4장) + 아래 스위치
local function exhaustFan(c: any)
	local K, V = c.K, c.V
	local walls = { "right", "left", "back" }
	if c.trunkEnds and #c.trunkEnds > 0 then
		walls = { c.trunkEnds[1].wall, if c.trunkEnds[1].wall == "left" then "right" else "left", "back" }
	end
	local wn, u = findWall(K, walls, 1.8, 1.8, 7.55, 9.25, V3(0, 0, V.z0 + 2), 0.6, function(wn2: string, cu: number)
		return promptWallOK(c, wn2, cu, 4.6) and not usedHit(K, wn2, cu - 0.4, cu + 0.4, 4.1, 5.1)
	end)
	if not wn or not u then
		return
	end
	claim(K, wn, u - 0.4, u + 0.4, 4.1, 5.1)
	local d = V:wall(wn, u, 8.4, 0)
	K:plate("ExhaustFrame", 1.6, 1.6, 0.12, d, L.of(214, 216, 218, M.Metal))
	K:plate("ExhaustHole", 1.3, 1.3, 0.125, d, L.of(28, 28, 30))
	local hub = d * CF(0, 0, 0.1)
	K:make("Part", "ExhaustHub", V3(0.06, 0.26, 0.26), hub * CF(0, 0, 0.02) * ANG(0, PI / 2, 0), L.of(60, 60, 64, M.Metal), Enum.PartType.Cylinder)
	local blades = {}
	for i = 0, 3 do
		local a = i * PI / 2
		table.insert(blades, K:ell("ExhaustBlade", V3(0.3, 0.56, 0.03), hub * ANG(0, 0, a) * CF(0, 0.3, 0) * ANG(0, 0.35, 0), L.of(170, 172, 176, M.Metal)))
	end
	for i = -2, 2 do
		K:plate("ExhaustLouver", 1.36, 0.04, 0.17, d * CF(0, i * 0.26, 0), L.of(200, 202, 206, M.Metal))
	end
	local sd = V:wall(wn, u, 4.6, 0)
	local sw = Props.switchPlate(K, sd, 1)
	txt(K, "ExhaustLabel", 0.7, 0.18, sd * CF(0, 0.42, 0.01), "환풍기", rgb(60, 60, 64), nil, F.GothamBold, { d = 0.004 })
	local hubW = K.cf * hub
	local rel = {}
	for _, b in blades do
		if b.Parent then
			table.insert(rel, { p = b, r = hubW:ToObjectSpace(b.CFrame) })
		end
	end
	local on, ang, spd = false, 0, 0
	Interact.toggle(K, sw, {
		object = "환풍기",
		onText = "끄기",
		offText = "켜기",
		state = false,
		on = function(s: boolean)
			on = s
		end,
	})
	Interact.anim(K, function(_t: number, dt: number)
		spd = spd + ((if on then 11 else 0) - spd) * math.min(1, dt * 1.2)
		if spd < 0.05 then
			return
		end
		ang += spd * dt
		local rot = hubW * ANG(0, 0, ang)
		for _, r in rel do
			if r.p.Parent then
				r.p.CFrame = rot * r.r
			end
		end
	end)
	at(K, "exhaust", wn, u)
end

-- 벽걸이 TV (채널: 롯데 야구 · 부산 뉴스 · 맛집 예능 · 끄기) + 리모컨 꽂이 (프롬프트)
local TV_FRAMES = {
	{ text = "LOTTE  4 : 3  DOOSAN\n8회말 · 2사 1, 2루\n사직 야구장 생중계", c = rgb(34, 110, 60) },
	{ text = "부산 뉴스\n광안리 드론쇼 오늘 밤 8시\n광안대교 야경 명소", c = rgb(24, 46, 110) },
	{ text = "맛있는 녀석들\n부산 조개구이 · 꼼장어 편", c = rgb(196, 90, 30) },
	{ text = "", c = rgb(14, 14, 16) },
}
local function tvScreen(c: any, dcf: CFrame, w: number, h: number, depth: number): (BasePart, TextLabel)
	local K = c.K
	K:plate("TVBody", w + 0.1, h + 0.1, depth, dcf, L.of(18, 18, 20))
	local scr = K:plate("TVScreen", w, h, 0.02, dcf * CF(0, 0, depth), { c = TV_FRAMES[1].c, m = M.SmoothPlastic })
	local _, lab = txt(K, "TVText", w * 0.92, h * 0.8, dcf * CF(0, 0, depth + 0.025), TV_FRAMES[1].text, WHITE, nil, F.GothamBlack, { glow = 1.3, d = 0.01 })
	K:plate("TVLogo", 0.26, 0.04, 0.01, dcf * CF(0, -h / 2 - 0.025, depth + 0.002), L.chrome)
	K:plate("TVStandby", 0.05, 0.05, 0.01, dcf * CF(w / 2 - 0.1, -h / 2 - 0.025, depth + 0.002), L.ledRed)
	return scr, lab
end

local function tvRemote(c: any, wn: string, u: number, scr: BasePart, lab: TextLabel)
	local K, V = c.K, c.V
	local sd = V:wall(wn, u, 4.7, 0)
	local holder = K:plate("RemoteHolder", 0.42, 0.62, 0.12, sd, L.of(250, 250, 246, M.Plastic))
	K:plate("Remote", 0.16, 0.5, 0.06, sd * CF(0, 0.1, 0.12), L.of(30, 30, 34))
	K:plate("RemoteBtn", 0.06, 0.06, 0.01, sd * CF(0, 0.28, 0.18), L.ledRed)
	txt(K, "RemoteLabel", 0.5, 0.15, sd * CF(0, -0.42, 0.01), "TV 리모컨", rgb(60, 60, 64), nil, F.GothamBold, { d = 0.004 })
	Interact.cycle(K, holder, TV_FRAMES, {
		action = "채널 바꾸기",
		object = "벽걸이 TV",
		on = function(_i: number, f: any)
			if scr.Parent then
				scr.Color = f.c
			end
			lab.Text = f.text
		end,
	})
end

local function wallTV(c: any)
	local K, V = c.K, c.V
	if V:has("TVScreen") > 0 then
		return
	end
	local w = 4.0
	local h = w * 9 / 16
	local wn, u = findWall(K, { "left", "right", "back" }, w + 0.3, w + 0.3, 4.3, 8.6, V3(0, 0, V.z0 + 4), 0.6, function(wn2: string, cu: number)
		return promptWallOK(c, wn2, cu, 4.7)
	end)
	local remote = wn ~= nil
	if not wn or not u then
		-- 프롬프트 자리가 없으면 TV 만 (리모컨 없이) 높이 걸기
		wn, u = findWall(K, { "left", "right", "back" }, w + 0.3, w + 0.3, 5.6, 8.6, V3(0, 0, V.z0 + 4), 0.6)
	end
	if not wn or not u then
		return
	end
	local dcf = V:wall(wn, u, 7.1, 0)
	K:plate("TVMount", w * 0.3, h * 0.4, 0.1, dcf, L.blackMetal)
	local scr, lab = tvScreen(c, dcf * CF(0, 0, 0.1), w, h, 0.12)
	if remote then
		tvRemote(c, wn, u, scr, lab)
	else
		-- 스스로 바뀌는 화면 (야구 중계 · 뉴스)
		Interact.screenLoop(K, scr, lab, { TV_FRAMES[1], TV_FRAMES[2], TV_FRAMES[3] }, 9)
	end
	at(K, "tv", wn, u)
end

-- 맵 TV (TV + TVScreen) 같은 범위로 다시
local function tvOver(c: any)
	local K, V = c.K, c.V
	local tv = V.byName.TV and V.byName.TV[1]
	local ts = V.byName.TVScreen and V.byName.TVScreen[1]
	if not tv then
		return
	end
	local wn, best = "back", math.huge
	for _, w in { "back", "left", "right" } do
		local _, dd = V:wallCoord(w, tv.c)
		if math.abs(dd) < best then
			wn, best = w, math.abs(dd)
		end
	end
	local u, dist = V:wallCoord(wn, tv.c)
	local alongX = wn == "back"
	local w = if alongX then tv.size.X else tv.size.Z
	local h = tv.size.Y
	local depth = math.max(0.1, (if alongX then tv.size.Z else tv.size.X))
	local dcf = V:wall(wn, u, tv.c.Y, dist - depth / 2)
	local scr, lab
	K:free(function()
		scr, lab = tvScreen(c, dcf, w - 0.24, h - 0.24, depth)
	end)
	hideRec(K, tv)
	if ts then
		hideRec(K, ts)
	end
	claim(K, wn, u - w / 2 - 0.2, u + w / 2 + 0.2, tv.min.Y - 0.2, tv.max.Y + 0.2)
	if promptWallOK(c, wn, u, 4.7) then
		claim(K, wn, u - 0.4, u + 0.4, 4.2, 5.2)
		tvRemote(c, wn, u, scr, lab)
	end
end

-- 벽시계
local function wallClock(c: any)
	local K, V = c.K, c.V
	local wn, u = findWall(K, { "back", "left", "right" }, 1.6, 1.6, 7.0, 8.7, V3(V.x1 * 0.4, 0, V.z0), 0.5)
	if wn and u then
		local d = V:wall(wn, u, 7.85, 0)
		local hr, mn = Props.clock(K, d, 1.4)
		Interact.clock(K, hr, mn, d, 1.4)
	end
end

-- 타일 위 색 띠 (조개구이 · 24시 포차)
local function tileBand(c: any)
	local K, V, th = c.K, c.V, c.th
	local lw = th.lower
	if not th.band or not lw or lw.kind ~= "tile" then
		return
	end
	local h = lw.h or 3.4
	K:free(function()
		for _, w in lw.walls or { "left", "right" } do
			for _, s in V:spans(w, 0.45, h, 0.25) do
				K:plate("TileBand", s[2] - s[1], 0.3, 0.045, V:wall(w, (s[1] + s[2]) / 2, h - 0.15, 0.0), col(th.band, M.CeramicTiles))
			end
		end
	end)
end

-- 바닥 소품 ---------------------------------------------------------------------------------------------
-- 셀프 코너 (스테인리스 2단 카트 + 쌈채소 · 마늘 · 고추 · 쌈장 · 앞접시 · 집게 · 물티슈) + 위 안내판
local function selfCart(c: any)
	local K, V, th = c.K, c.V, c.th
	local size = V3(2.6, 3.2, 1.3)
	local pcf, wn, u = floorOnWall(K, { "left", "right", "back" }, size, V3(0, 0, 0), 0.15)
	if not pcf or not wn or not u then
		return
	end
	local w, d, h = 2.5, 1.2, 3.05
	local st = L.steel
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:vcyl("CartLeg", h - 0.2, 0.1, pcf * CF(sx * (w / 2 - 0.08), 0.2 + (h - 0.2) / 2, sz * (d / 2 - 0.08)), st)
			K:ball("CartCaster", 0.2, pcf * CF(sx * (w / 2 - 0.08), 0.1, sz * (d / 2 - 0.08)), L.of(40, 40, 42, M.Rubber))
		end
	end
	K:box("CartTop", V3(w, 0.06, d), pcf * CF(0, h - 0.03, 0), st)
	K:box("CartShelf", V3(w - 0.1, 0.05, d - 0.1), pcf * CF(0, 1.0, 0), st)
	K:box("CartLip", V3(w, 0.16, 0.04), pcf * CF(0, h + 0.05, d / 2 - 0.02), st)
	K:box("CartLip", V3(w, 0.3, 0.04), pcf * CF(0, h + 0.12, -d / 2 + 0.02), st)
	-- 통 4개 (상추 · 깻잎 · 파채 · 마늘 고추)
	local fills = { L.of(96, 160, 70, M.Grass), L.of(56, 110, 54, M.Grass), L.of(196, 220, 150, M.Grass), L.of(240, 236, 222) }
	for i = 1, 4 do
		local x = -w / 2 + 0.33 + (i - 1) * 0.6
		local b = pcf * CF(x, h, 0.05)
		K:box("CartBin", V3(0.56, 0.2, 0.8), b * CF(0, 0.06, 0), L.of(210, 214, 218, M.Metal))
		K:box("CartFill", V3(0.5, 0.06, 0.74), b * CF(0, 0.15, 0), fills[i])
		if c.hi then
			for k = 1, 3 do
				local ox, oz = (rnd(c.seed, i * 10 + k) - 0.5) * 0.3, (rnd(c.seed, i * 20 + k) - 0.5) * 0.5
				if i <= 2 then
					K:ell("Lettuce", V3(0.3, 0.08, 0.26), b * CF(ox, 0.2, oz) * ANG(0.2, k, 0), lift(fills[i], 0.12))
				elseif i == 3 then
					K:seg("Pacha", (b * CF(ox - 0.1, 0.19, oz)).Position, (b * CF(ox + 0.12, 0.2, oz + 0.05)).Position, 0.03, L.of(220, 236, 190))
				else
					K:ball("Garlic", 0.1, b * CF(ox, 0.2, oz), L.of(246, 242, 230))
					K:cyl("Gochu", 0.26, 0.06, b * CF(ox, 0.2, oz + 0.12) * ANG(0, k, 0), L.of(60, 140, 50))
				end
			end
		end
	end
	-- 쌈장 · 앞접시 · 집게 컵 · 물티슈 (아래 칸)
	K:vcyl("Ssamjang", 0.2, 0.42, pcf * CF(0.8, 1.13, 0.1), L.of(150, 90, 50))
	for k = 0, 5 do
		K:disc("Plate", 0.56, 0.035, pcf * CF(-0.75, 1.05 + 0.02 + k * 0.04, 0.05), L.white)
	end
	K:vcyl("TongCup", 0.42, 0.24, pcf * CF(0.05, 1.24, 0.1), L.steel)
	for k = 0, 2 do
		K:bar("Tong", (pcf * CF(0.05 + (k - 1) * 0.05, 1.3, 0.1)).Position, (pcf * CF(0.05 + (k - 1) * 0.09, 1.75, 0.12)).Position, 0.04, 0.02, L.chrome)
	end
	K:box("WetTissue", V3(0.5, 0.22, 0.3), pcf * CF(0.25, 0.1 + 0.11 + 0.0, 0.2) * CF(0, 0.0, 0), L.of(250, 250, 250))
	K:box("GloveBox", V3(0.5, 0.25, 0.32), pcf * CF(-0.4, 0.33, 0.2), L.of(230, 236, 246))
	-- 위 안내판 (벽)
	local sd = V:wall(wn, u, 4.25, 0)
	claim(K, wn, u - 1.4, u + 1.4, 3.6, 5.0)
	plateSign(K, sd, 2.5, 0.8, "셀프 코너\n쌈채소 · 마늘 · 고추 · 쌈장 · 앞접시", WHITE, th.accent, nil, F.GothamBold)
	at(K, "self cart", wn, u)
end

-- 소주 박스 더미 (초록 플라스틱 박스 3단 + 맥주 박스)
local function crateStack(c: any)
	local K, V = c.K, c.V
	local size = V3(3.2, 2.6, 1.3)
	local pcf, wn, u = floorOnWall(K, { "back", "left", "right" }, size, V3(V.x0 + 2, 0, V.z0), 0.1)
	if not pcf or not wn or not u then
		return
	end
	local cw, ch, cd = 1.5, 0.8, 1.15
	local green = L.of(40, 138, 70, M.Plastic)
	local brown = L.of(196, 150, 40, M.Plastic)
	local function crate(base: CFrame, look: any, full: boolean, kind: string)
		K:box("Crate", V3(cw, ch, cd), base * CF(0, ch / 2, 0), look)
		for _, sx in { -1, 1 } do
			K:plate("CrateGrip", 0.5, 0.16, 0.01, CFrame.fromMatrix((base * CF(sx * (cw / 2 + 0.002), ch - 0.2, 0)).Position, base.ZVector * -sx, base.YVector, base.XVector * sx), dim(look, 0.5))
		end
		K:plate("CrateLabel", 0.7, 0.24, 0.01, base * CF(0, ch * 0.5, cd / 2), L.of(250, 250, 246))
		if full and c.hi then
			for i = 0, 4 do
				for j = 0, 2 do
					local p = base * CF(-cw / 2 + 0.17 + i * 0.29, ch, -cd / 2 + 0.2 + j * 0.37)
					K:vcyl("CrateNeck", 0.18, 0.11, p * CF(0, 0.05, 0), if kind == "soju" then SOJU_GLASS else BEER_GLASS)
				end
			end
		end
	end
	local b0 = pcf * CF(-0.8, 0, 0)
	for i = 0, 2 do
		crate(b0 * CF(0, ch * i, 0) * ANG(0, (i - 1) * 0.04, 0), green, i == 2, "soju")
	end
	local b1 = pcf * CF(0.85, 0, 0.02) * ANG(0, 0.08, 0)
	crate(b1, brown, false, "beer")
	crate(b1 * CF(0, ch, 0) * ANG(0, -0.05, 0), brown, true, "beer")
	at(K, "crates", wn, u)
end

-- 스탠드 에어컨 (천장 카세트 대신, 포차)
local function standAC(c: any)
	local K, V = c.K, c.V
	local size = V3(1.6, 5.8, 1.1)
	local pcf, wn, u = floorOnWall(K, { "left", "right" }, size, V3(V.x0, 0, V.z1 - 3), 0.1)
	if not pcf or not wn or not u then
		return
	end
	local w, h, d = 1.5, 5.7, 1.0
	local white = L.of(244, 244, 240, M.SmoothPlastic)
	K:box("ACBase", V3(w - 0.1, 0.14, d - 0.1), pcf * CF(0, 0.07, 0), L.of(70, 70, 74))
	K:rbox("ACBody", V3(h - 0.16, w, d), 0.22, pcf * CF(0, 0.14 + (h - 0.16) / 2, 0) * ANG(0, 0, PI / 2), white)
	K:plate("ACFront", w - 0.26, h - 1.9, 0.02, pcf * CF(0, 0.6 + (h - 1.9) / 2, d / 2), L.of(250, 250, 248, M.SmoothPlastic, { r = 0.08 }))
	K:plate("ACVent", w - 0.3, 1.1, 0.03, pcf * CF(0, h - 0.75, d / 2), L.of(70, 72, 76))
	for i = 0, 4 do
		K:plate("ACVane", w - 0.36, 0.05, 0.06, pcf * CF(0, h - 1.22 + i * 0.22, d / 2), L.of(200, 202, 206))
	end
	K:plate("ACDisplay", 0.5, 0.26, 0.03, pcf * CF(0, h - 1.75, d / 2), L.of(20, 20, 24))
	txt(K, "ACTemp", 0.44, 0.2, pcf * CF(0, h - 1.75, d / 2 + 0.032), "냉방 24℃", rgb(120, 200, 255), nil, F.GothamBold, { glow = 1.2, d = 0.005 })
	K:plate("ACStrip", 0.06, h - 2.4, 0.025, pcf * CF(0, 1.4 + (h - 2.4) / 2 - 0.4, d / 2), L.neon(rgb(150, 210, 255)))
	at(K, "stand AC", wn, u)
end

-- 숯불 화로대 (뒷벽 · 주방 문 옆): 스테인리스 작업대 + 불붙은 화로 2 + 아래 예비 화로 + 집게 + 안내
local function charcoalStation(c: any)
	local K, V, th = c.K, c.V, c.th
	local size = V3(2.8, 3.4, 1.4)
	local pcf, wn, u = floorOnWall(K, { "back", "left", "right" }, size, V3(V.x0 * 0.55, 0, V.z0), 0.15)
	if not pcf or not wn or not u then
		return
	end
	local w, d, h = 2.7, 1.3, 2.4
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:box("StationLeg", V3(0.12, h, 0.12), pcf * CF(sx * (w / 2 - 0.08), h / 2, sz * (d / 2 - 0.08)), L.steel)
		end
	end
	K:box("StationTop", V3(w, 0.08, d), pcf * CF(0, h - 0.04, 0), L.steel)
	K:box("StationShelf", V3(w - 0.1, 0.05, d - 0.1), pcf * CF(0, 0.5, 0), L.steel)
	K:box("StationSplash", V3(w, 0.5, 0.05), pcf * CF(0, h + 0.25, -d / 2 + 0.03), L.steel)
	for i, x in { -0.62, 0.62 } do
		local b = pcf * CF(x, h, 0.05)
		K:disc("SparePot", 1.0, 0.32, b * CF(0, 0.16, 0), L.of(50, 48, 46, M.Metal))
		K:disc("SpareAsh", 0.84, 0.02, b * CF(0, 0.32, 0), L.of(92, 88, 84, M.Slate))
		local gl = K:disc("SpareCoal", 0.64, 0.03, b * CF(0, 0.335, 0), L.neon(rgb(255, 96, 30)))
		if i == 1 then
			K:light(gl, "PointLight", { Range = 5, Brightness = 0.5, Color = rgb(255, 110, 40) })
		end
		for k = 1, 4 do
			local a = k * PI / 2 + i
			K:ell("Charcoal", V3(0.26, 0.09, 0.18), b * CF(math.cos(a) * 0.18, 0.37, math.sin(a) * 0.18) * ANG(0, a, 0.2), if k == 2 then L.neon(rgb(255, 80, 28)) else L.of(34, 32, 32, M.Slate))
		end
	end
	for k = 0, 2 do
		K:disc("PotStack", 1.0, 0.3, pcf * CF(-0.6, 0.55 + 0.15 + k * 0.3, 0), L.of(56, 54, 52, M.Metal))
	end
	K:box("CharcoalBag", V3(1.0, 0.9, 0.6), pcf * CF(0.65, 0.53 + 0.45, 0.1), L.of(176, 150, 110, M.Fabric))
	txt(K, "CharcoalBagLabel", 0.8, 0.4, pcf * CF(0.65, 1.05, 0.405), "참숯\n10kg", INK, nil, F.GothamBlack, { d = 0.004 })
	K:bar("FireTong", (pcf * CF(0.05, h + 0.02, 0.45)).Position, (pcf * CF(0.6, h + 0.05, 0.55)).Position, 0.05, 0.03, L.chrome)
	local sd = V:wall(wn, u, h + 1.05, 0)
	claim(K, wn, u - 1.4, u + 1.4, h, h + 1.6)
	plateSign(K, sd, 2.2, 0.5, "숯불 작업 중 · 뜨거워요!", INK, rgb(255, 214, 40), L.black, F.GothamBold)
	at(K, "charcoal station", wn, u)
end

-- 냉장고가 없는 포차: 2문 (자리가 없으면 1문) 소주 냉장고를 벽에 세움
local function standFridge(c: any)
	local K, V = c.K, c.V
	for _, nd in { 2, 1 } do
		local fw = if nd == 2 then 4.2 else 2.3
		local size = V3(fw + 0.1, 6.6, 2.5)
		local near = V3(V.x1, 0, V.z0 + 3)
		local pcf, wn, u = floorOnWall(K, { "left", "right", "back" }, size, near, 0.15, function(p: CFrame)
			return promptOK(c, (p * CF(0, 0, 1.2)).Position)
		end)
		if not pcf then
			pcf, wn, u = floorOnWall(K, { "left", "right", "back" }, size, near, 0.15)
		end
		if pcf then
			local doors = fridgeBuild(c, pcf * CF(0, 0, -0.24), fw, 2.0, 6.5, 0.6, 5.7, { 1.9, 3.2, 4.5 }, true, nd)
			fridgeSwing(c, doors, "소주 냉장고")
			at(K, "stand fridge " .. nd, wn, u)
			return
		end
	end
end

-- 다찌 카운터 위 오뎅 바 (스테인리스 통 · 국물 · 꼬치 · 국자 · 종이컵)
local function odengBath(c: any)
	local K, V = c.K, c.V
	local g = V.counters[1]
	if not g then
		return
	end
	local y = g.y
	if (g.max.X - g.min.X) < (g.max.Z - g.min.Z) then
		return
	end
	local W, D, Hh = 2.3, 0.95, 0.42
	local tz0, tz1 = g.min.Z, g.max.Z
	if g.top then
		tz0, tz1 = g.top.min.Z, g.top.max.Z
	end
	local zc = (tz0 + tz1) / 2
	local spotX = nil
	for _, xc in { g.min.X + W / 2 + 0.3, g.max.X - W / 2 - 0.3 } do
		local mn, mx = V3(xc - W / 2 - 0.4, y + 0.01, zc - D / 2), V3(xc + W / 2 + 0.4, y + 1.2, zc + D / 2)
		if not K:hitsKeep(mn, mx) and mapClear(V, mn, mx) then
			spotX = xc
			break
		end
	end
	if not spotX then
		return
	end
	local b = CF(spotX, y, zc)
	K:box("OdengBath", V3(W, Hh, D), b * CF(0, Hh / 2, 0), L.steel)
	K:box("OdengBroth", V3(W - 0.12, 0.02, D - 0.12), b * CF(0, Hh - 0.06, 0), L.of(176, 122, 64, M.Glass, { t = 0.1 }))
	K:box("OdengDivider", V3(0.03, 0.08, D - 0.12), b * CF(-W * 0.18, Hh - 0.04, 0), L.steel)
	K:box("OdengDivider", V3(0.03, 0.08, D - 0.12), b * CF(W * 0.2, Hh - 0.04, 0), L.steel)
	local cake = L.of(214, 158, 94)
	local n = if c.hi then 12 else 7
	for i = 1, n do
		local x = -W / 2 + 0.2 + (W - 0.4) * ((i - 1) % 6) / 5
		local zz = if i <= 6 then -0.18 else 0.16
		local base = b * CF(x, Hh - 0.08, zz) * ANG(if zz < 0 then -0.5 else 0.45, 0, (rnd(c.seed, i) - 0.5) * 0.3)
		K:seg("OdengStick", (base * CF(0, 0, 0)).Position, (base * CF(0, 0.75, 0)).Position, 0.03, L.of(222, 196, 150, M.Wood))
		for k = 0, 2 do
			K:box("OdengCake", V3(0.26, 0.16, 0.04), base * CF(0, 0.12 + k * 0.13, 0) * ANG(if k % 2 == 0 then 0.5 else -0.5, 0, 0), cake)
		end
	end
	K:seg("Ladle", (b * CF(W / 2 - 0.25, Hh - 0.05, 0.2)).Position, (b * CF(W / 2 + 0.1, Hh + 0.55, 0.36)).Position, 0.04, L.chrome)
	K:ell("LadleCup", V3(0.24, 0.1, 0.24), b * CF(W / 2 - 0.28, Hh - 0.05, 0.18), L.chrome)
	K:vcyl("PaperCups", 0.62, 0.24, b * CF(W / 2 + 0.35, 0.31, -0.15), L.white)
	K:disc("SauceDish", 0.34, 0.06, b * CF(-W / 2 - 0.35, 0.03, 0.05), L.white)
	K:disc("Sauce", 0.28, 0.02, b * CF(-W / 2 - 0.35, 0.065, 0.05), L.of(70, 40, 20))
	K:bar("SauceBrush", (b * CF(-W / 2 - 0.45, 0.07, 0.0)).Position, (b * CF(-W / 2 - 0.2, 0.3, -0.16)).Position, 0.04, 0.03, L.of(200, 170, 120, M.Wood))
	local cd = b * CF(-W / 2 - 0.35, 0.0, -0.3)
	txt(K, "OdengCard", 0.6, 0.36, CFrame.fromMatrix((cd * CF(0, 0.22, 0)).Position, Vector3.xAxis, Vector3.yAxis, Vector3.zAxis) * ANG(-0.2, 0, 0), "오뎅 1개\n1,000원", rgb(200, 20, 20), rgb(255, 250, 236), F.GothamBlack, { d = 0.02 })
	-- 김 (천천히 오르는 반투명 덩이)
	local steamL = { c = rgb(250, 250, 250), m = M.SmoothPlastic, t = 0.86 }
	local puffs = {}
	for i = 1, 3 do
		local p = K:ell("OdengSteam", V3(0.5, 0.36, 0.4), b * CF((i - 2) * 0.6, Hh + 0.3 + i * 0.25, 0), steamL)
		if p.Parent then
			table.insert(puffs, { p = p, base = p.CFrame, ph = i * 1.3 })
		end
	end
	Interact.anim(K, function(t: number)
		for _, s in puffs do
			local k = (t * 0.25 + s.ph) % 1
			if s.p.Parent then
				s.p.CFrame = s.base * CF(math.sin(t + s.ph) * 0.06, k * 0.6 - 0.3, 0)
				s.p.Transparency = 0.8 + k * 0.18
			end
		end
	end)
	at(K, "odeng bath", "counter", spotX)
end

-- 백바 (BackBarCabinet · MirrorBack · BarShelf · ShelfGlow · Bottle): 같은 범위로 원목 · 소주병 · 양은 주전자
local function backBarOver(c: any)
	local K, V = c.K, c.V
	local cab = V.byName.BackBarCabinet and V.byName.BackBarCabinet[1]
	local woodL = L.of(120, 80, 48, M.Wood)
	K:free(function()
		if cab then
			K:box("BackCab", cab.size - V3(0.02, 0.02, 0.02), CF(cab.c), dim(woodL, 0.1))
			K:box("BackCabTop", V3(cab.size.X + 0.04, 0.08, cab.size.Z + 0.04), CF(cab.c.X, cab.max.Y - 0.04, cab.c.Z), L.steel)
			local n = math.max(2, math.floor(cab.size.X / 1.8))
			local dw = (cab.size.X - 0.2) / n
			for i = 1, n do
				local x = cab.min.X + 0.1 + dw * (i - 0.5)
				K:box("BackCabDoor", V3(dw - 0.08, cab.size.Y - 0.5, 0.04), CF(x, cab.min.Y + 0.3 + (cab.size.Y - 0.5) / 2, cab.max.Z + 0.01), woodL)
				K:box("BackCabKnob", V3(0.06, 0.4, 0.06), CF(x + (if i % 2 == 0 then -1 else 1) * (dw / 2 - 0.2), cab.min.Y + 1.9, cab.max.Z + 0.06), L.blackMetal)
			end
			hideRec(K, cab)
		end
		for _, r in V.byName.MirrorBack or {} do
			K:box("BackBoard", V3(r.size.X - 0.02, r.size.Y - 0.02, r.size.Z), CF(r.c), L.of(60, 40, 26, M.WoodPlanks))
			hideRec(K, r)
		end
		local shelves = V.byName.BarShelf or {}
		for si, r in shelves do
			K:box("BarShelfPlank", r.size - V3(0.02, 0, 0.02), CF(r.c), woodL)
			hideRec(K, r)
			local y = r.max.Y
			local n = math.floor((r.size.X - 0.3) / 0.32)
			for j = 1, n do
				local x = r.min.X + 0.15 + (r.size.X - 0.3) * (j - 0.5) / n
				local kind = if si == #shelves and j % 5 == 0 then "kettle" elseif (j + si) % 7 == 0 then "makgeolli" elseif (j + si) % 4 == 0 then "beer" else "soju"
				local base = CF(x, y, r.c.Z + 0.05)
				if kind == "kettle" then
					-- 양은 주전자
					K:vcyl("Kettle", 0.42, 0.5, base * CF(0, 0.21, 0), L.of(214, 196, 150, M.Metal))
					K:vcyl("KettleLid", 0.06, 0.3, base * CF(0, 0.45, 0), L.of(214, 196, 150, M.Metal))
					K:seg("KettleSpout", (base * CF(0.2, 0.15, 0)).Position, (base * CF(0.42, 0.4, 0)).Position, 0.07, L.of(214, 196, 150, M.Metal))
				else
					bottle(K, base, kind, c.hi and j % 2 == 0)
				end
			end
		end
		for _, r in V.byName.ShelfGlow or {} do
			K:box("ShelfLED", r.size - V3(0.02, 0.02, 0.02), CF(r.c), L.neon(rgb(255, 190, 120)))
			hideRec(K, r)
		end
	end)
	-- 맵 병 (선반 위) 숨김
	if cab then
		for _, r in V.byName.Bottle or {} do
			if r.c.Z < cab.max.Z + 0.6 then
				hideRec(K, r)
			end
		end
	end
end

-- 24시 포차: 주방 패스 둘레 (스테인리스 테 · 타일 · 주문표 레일 · 노렌 같은 자세 · PassLedge 같은 범위)
local function passDecor(c: any)
	local K, V, th = c.K, c.V, c.th
	local kp = V.byName.KitchenPass and V.byName.KitchenPass[1]
	if not kp then
		return
	end
	local u = V:wallCoord("back", kp.c)
	local w, y0, y1 = kp.size.X, kp.min.Y, kp.max.Y
	claim(K, "back", u - w / 2 - 0.8, u + w / 2 + 0.8, 0, 8.4)
	K:free(function()
		local d = V:wall("back", u, (y0 + y1) / 2, 0)
		K:plate("PassSurround", w + 1.2, (y1 - y0) + 1.4, 0.03, d * CF(0, 0.3, 0), L.of(240, 240, 236, M.CeramicTiles))
		for i = -2, 3 do
			K:plate("PassGrout", w + 1.2, 0.02, 0.035, d * CF(0, i * 0.6, 0), L.of(190, 194, 190))
		end
		K:plate("PassTrim", w + 0.2, 0.12, 0.14, d * CF(0, (y1 - y0) / 2 + 0.06, 0), L.steel)
		K:plate("PassTrim", 0.12, y1 - y0, 0.14, d * CF(-w / 2 - 0.06, 0, 0), L.steel)
		K:plate("PassTrim", 0.12, y1 - y0, 0.14, d * CF(w / 2 + 0.06, 0, 0), L.steel)
		K:box("PassInner", kp.size - V3(0.02, 0.02, 0), CF(kp.c), L.of(56, 50, 44))
		K:box("PassGlow", V3(w - 0.3, 0.04, 0.02), CF(kp.c.X, y1 - 0.12, kp.max.Z), L.lampNeutral)
		-- 패스 안 주방 (벽에 붙은 얕은 그림): 흰 타일 · 선반 위 뚝배기 · 육수 솥 김 · 국자 걸이
		local _, fdist = V:wallCoord("back", V3(kp.c.X, 0, kp.max.Z))
		local kd = V:wall("back", u, (y0 + y1) / 2, fdist)
		local kh = y1 - y0
		K:plate("PassKitchenTile", w - 0.14, kh - 0.2, 0.01, kd, L.of(232, 234, 230, M.CeramicTiles))
		for i = 1, 3 do
			K:plate("PassKitchenGrout", w - 0.14, 0.015, 0.012, kd * CF(0, -kh / 2 + kh * i / 4, 0), L.of(186, 190, 186))
		end
		local sy = kh * 0.12
		K:plate("PassShelf", w - 0.3, 0.07, 0.08, kd * CF(0, sy, 0.01), L.steel)
		for i = 0, 5 do
			local bx = -w / 2 + 0.55 + i * 0.5
			if bx < w / 2 - 1.7 then
				K:plate("PassTtukbaegi", 0.42, 0.24, 0.03, kd * CF(bx, sy + 0.16, 0.012), L.of(54, 40, 34))
				K:plate("PassTtukRim", 0.46, 0.05, 0.035, kd * CF(bx, sy + 0.28, 0.012), L.of(84, 64, 54))
				if i % 2 == 0 then
					K:plate("PassTtukbaegi", 0.42, 0.24, 0.03, kd * CF(bx, sy + 0.46, 0.012), L.of(54, 40, 34))
					K:plate("PassTtukRim", 0.46, 0.05, 0.035, kd * CF(bx, sy + 0.58, 0.012), L.of(84, 64, 54))
				end
			end
		end
		-- 육수 솥 (오른쪽 아래) + 김
		local px = w / 2 - 0.95
		K:plate("PassStockPot", 1.2, 0.95, 0.04, kd * CF(px, -kh / 2 + 0.6, 0.012), L.of(196, 200, 204, M.Metal))
		K:plate("PassStockRim", 1.28, 0.08, 0.05, kd * CF(px, -kh / 2 + 1.07, 0.012), L.steel)
		K:plate("PassStockBand", 1.2, 0.05, 0.045, kd * CF(px, -kh / 2 + 0.5, 0.012), L.of(150, 154, 160, M.Metal))
		if c.hi then
			for k = 1, 3 do
				K:ell("PassSteam", V3(0.5 + k * 0.12, 0.42, 0.02), kd * CF(px + (k - 2) * 0.22, -kh / 2 + 1.2 + k * 0.32, 0.03), { c = rgb(250, 250, 250), m = M.SmoothPlastic, t = 0.55 + k * 0.1 })
			end
		end
		-- 국자 · 뜰채 걸이 (위)
		K:plate("PassUtensilRail", w - 1.0, 0.05, 0.06, kd * CF(-0.3, kh / 2 - 0.42, 0.012), L.chrome)
		for k = 0, 3 do
			local lx = -w / 2 + 0.9 + k * 0.42
			K:plate("PassLadle", 0.04, 0.6, 0.02, kd * CF(lx, kh / 2 - 0.74, 0.04), L.chrome)
			wdisc(K, "PassLadleCup", 0.2, 0.03, kd * CF(lx, kh / 2 - 1.08, 0.03), 0, L.chrome)
		end
		-- 주문표 레일
		local rd = V:wall("back", u, y1 + 0.95, 0)
		K:plate("TicketRail", w, 0.12, 0.1, rd, L.steel)
		for i = 1, 4 do
			K:plate("Ticket", 0.42, 0.62, 0.012, rd * CF(-w / 2 + 0.6 + (i - 1) * 0.6, -0.3, 0.1) * ANG(0, 0, (rnd(c.seed, i) - 0.5) * 0.1), L.of(252, 252, 246))
		end
	end)
	hideRec(K, kp)
	for _, r in V.byName.PassLedge or {} do
		K:free(function()
			K:box("PassLedgeTop", r.size, CF(r.c), L.steel)
			K:box("PassLedgeLip", V3(r.size.X, 0.06, 0.04), CF(r.c.X, r.max.Y + 0.03, r.max.Z - 0.02), L.chrome)
		end)
		hideRec(K, r)
	end
	local nm = V.name or "주방"
	local chars = {}
	for _, cp in utf8.codes(nm) do
		table.insert(chars, utf8.char(cp))
	end
	for i, r in V.byName.Noren or {} do
		K:free(function()
			local u2, dist = V:wallCoord("back", r.c)
			local nd = V:wall("back", u2, r.c.Y, dist - r.size.Z / 2)
			K:plate("NorenCloth", r.size.X - 0.04, r.size.Y, r.size.Z, nd, col(rgb(30, 40, 70), M.Fabric))
			K:plate("NorenHem", r.size.X - 0.04, 0.08, r.size.Z + 0.01, nd * CF(0, -r.size.Y / 2 + 0.06, 0), col(rgb(200, 40, 34), M.Fabric))
			local s = if i == 1 then (chars[1] or "주") .. (chars[2] or "") else table.concat(chars, "", math.min(3, #chars), #chars)
			txt(K, "NorenText", r.size.X * 0.8, r.size.Y * 0.6, nd * CF(0, 0.06, r.size.Z + 0.002), s, WHITE, nil, F.GothamBlack, { d = 0.004 })
		end)
		hideRec(K, r)
	end
end

-- 좌식 평상 (같은 범위 · 같은 윗면): 마루 + 테두리목 + 몸통 + 걸레받이 + 신발
local function platformOver(c: any)
	local K, V, th = c.K, c.V, c.th
	for _, r in V.byName["좌식평상"] or {} do
		local mn, mx = r.min, r.max
		local top = mx.Y
		local W, D = mx.X - mn.X, mx.Z - mn.Z
		local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
		local fr = th.maruFrame or L.of(120, 78, 46, M.Wood)
		local maru = th.maru or L.of(200, 150, 96, M.WoodPlanks)
		K:free(function()
			local bw = 0.34
			K:box("MaruTop", V3(W - 2 * bw, 0.12, D - 2 * bw), CF(cx, top - 0.06, cz), maru)
			K:box("MaruRim", V3(W, 0.12, bw), CF(cx, top - 0.06, mn.Z + bw / 2), fr)
			K:box("MaruRim", V3(W, 0.12, bw), CF(cx, top - 0.06, mx.Z - bw / 2), fr)
			K:box("MaruRim", V3(bw, 0.12, D - 2 * bw), CF(mn.X + bw / 2, top - 0.06, cz), fr)
			K:box("MaruRim", V3(bw, 0.12, D - 2 * bw), CF(mx.X - bw / 2, top - 0.06, cz), fr)
			local kick = 0.28
			K:box("MaruBody", V3(W - 0.06, top - 0.12 - kick, D - 0.06), CF(cx, kick + (top - 0.12 - kick) / 2, cz), dim(fr, 0.15))
			K:box("MaruKick", V3(W - 0.3, kick, D - 0.3), CF(cx, kick / 2, cz), L.of(36, 28, 22))
			local n = math.max(2, math.floor(D / 1.8))
			for i = 1, n - 1 do
				local z = mn.Z + D * i / n
				K:box("MaruStile", V3(0.04, top - 0.16 - kick, 0.12), CF(mn.X - 0.02, kick + (top - 0.12 - kick) / 2, z), dim(fr, 0.35))
			end
			K:cyl("MaruNosing", D, 0.14, CF(mn.X + 0.07, top - 0.07, cz) * ANG(0, PI / 2, 0), fr)
		end)
		hideRec(K, r)
		-- 신발 (평상 앞 바닥)
		local shoeC = { rgb(40, 40, 44), rgb(200, 200, 196), rgb(120, 70, 40) }
		for i, z in { cz - D * 0.25, cz + D * 0.2 } do
			local x = mn.X - 0.45
			if K:spot(CF(x, 0, z), V3(0.8, 0.25, 0.8), 0, "shoe") then
				local base = CF(x, 0.03, z) * ANG(0, PI / 2 + (i - 1.5) * 0.3, 0)
				for _, sx in { -0.17, 0.17 } do
					K:box("Shoe", V3(0.28, 0.18, 0.62), base * CF(sx, 0.09, 0), col(shoeC[(i + c.seed) % 3 + 1], M.Fabric))
					K:box("ShoeSole", V3(0.3, 0.05, 0.66), base * CF(sx, 0.025, 0), L.of(236, 236, 230, M.Rubber))
				end
			end
		end
	end
end

-- 카세트 에어컨 숨김 (천막 천장 위로 가려지는 것) + 맵 다운라이트
local function hideCeilingKit(c: any)
	local K, V = c.K, c.V
	for _, nm in { "CassetteAC", "ACVanes", "ACGrille", "Downlight" } do
		for _, r in V.byName[nm] or {} do
			if r.min.Y > V.H - 1.0 and r.c.Z < V.z1 - 2.0 then
				hideRec(K, r)
			end
		end
	end
end

-- 전구 줄 스위치 (벽, 프롬프트)
local function bulbSwitch(c: any)
	local K, V = c.K, c.V
	if not c.bulbs or #c.bulbs == 0 then
		return
	end
	local wn, u = findWall(K, { "left", "right", "back" }, 0.9, 0.9, 3.9, 5.0, V3(0, 0, V.z0 + 4), 0.5, function(wn2: string, cu: number)
		return promptWallOK(c, wn2, cu, 4.4)
	end)
	if not wn or not u then
		return
	end
	local sd = V:wall(wn, u, 4.4, 0)
	local sw = Props.switchPlate(K, sd, 2)
	txt(K, "BulbSwitchLabel", 0.8, 0.18, sd * CF(0, 0.42, 0.01), "전구 조명", rgb(60, 60, 64), nil, F.GothamBold, { d = 0.004 })
	Interact.toggle(K, sw, {
		object = "천막 전구 줄",
		onText = "끄기",
		offText = "켜기",
		state = true,
		on = function(s: boolean)
			for _, b in c.bulbs do
				if b.p.Parent then
					b.p.Material = if s then M.Neon else M.SmoothPlastic
					b.p.Color = if s then b.c else b.c:Lerp(rgb(120, 110, 100), 0.6)
				end
			end
			for _, l in c.bulbLights or {} do
				l.Enabled = s
			end
		end,
	})
	at(K, "bulb switch", wn, u)
end

-- 사진 메뉴 라이트박스 (한식 · 포차 벽 위쪽: 메뉴마다 음식 사진 + 이름 + 가격) ----------------------------------
-- 사진은 얇은 타원 판을 겹쳐 그린 일러스트 (그릇 · 국물 · 건더기 · 고명). DISH[kind] = { v = 그릇, fill = 국물색,
--   bits = { { 모양, 색, 개수, 크기(그릇 지름 비), 종횡비 } }, side = 곁들이 반찬 }
local DISH: { [string]: any } = {
	gukbap = { v = "ttuk", fill = rgb(238, 228, 208), bits = { { "ell", rgb(214, 176, 156), 4, 0.24, 0.5 }, { "disc", rgb(96, 168, 70), 8, 0.07 }, { "ell", rgb(196, 46, 30), 1, 0.18, 0.75 } }, side = "kkakdugi" },
	seonji = { v = "ttuk", fill = rgb(176, 64, 34), bits = { { "sq", rgb(84, 22, 24), 4, 0.15 }, { "ell", rgb(110, 116, 52), 4, 0.22, 0.45 }, { "disc", rgb(110, 180, 70), 7, 0.06 } }, side = "kimchi" },
	sundae = { v = "ttuk", fill = rgb(232, 220, 196), bits = { { "disc", rgb(74, 52, 62), 5, 0.17 }, { "ell", rgb(214, 180, 160), 3, 0.2, 0.5 }, { "disc", rgb(96, 168, 70), 7, 0.06 } }, side = "kkakdugi" },
	doenjang = { v = "ttuk", fill = rgb(150, 100, 52), bits = { { "sq", rgb(246, 242, 228), 5, 0.14 }, { "disc", rgb(176, 200, 96), 4, 0.15 }, { "ell", rgb(200, 40, 30), 3, 0.1, 0.35 } } },
	eggs = { v = "ttuk", fill = rgb(250, 206, 92), bits = { { "ell", rgb(255, 226, 140), 3, 0.3, 0.8 }, { "disc", rgb(96, 168, 70), 6, 0.06 } } },
	dakbal = { v = "plate", bits = { { "ell", rgb(176, 40, 22), 9, 0.26, 0.28 }, { "disc", rgb(250, 246, 230), 8, 0.03 }, { "disc", rgb(110, 180, 70), 4, 0.06 } }, side = "egg" },
	kkom = { v = "plate", bits = { { "ell", rgb(206, 86, 40), 7, 0.3, 0.32 }, { "ell", rgb(250, 240, 220), 3, 0.2, 0.3 }, { "disc", rgb(110, 180, 70), 6, 0.06 } } },
	pajeon = { v = "plate", bits = { { "ell", rgb(222, 170, 80), 1, 0.86, 0.9 }, { "bar", rgb(70, 150, 60), 7, 0.5, 0.05 }, { "ell", rgb(244, 236, 226), 4, 0.14, 0.7 }, { "disc", rgb(200, 40, 30), 5, 0.05 } }, side = "sauce" },
	haemultang = { v = "pot", fill = rgb(190, 54, 30), bits = { { "ell", rgb(226, 90, 44), 1, 0.42, 0.7 }, { "ell", rgb(236, 120, 80), 3, 0.24, 0.4 }, { "ell", rgb(220, 206, 176), 4, 0.14, 0.75 }, { "ell", rgb(90, 150, 60), 3, 0.2, 0.5 } } },
	odeng = { v = "pot", fill = rgb(206, 172, 110), bits = { { "bar", rgb(150, 110, 70), 5, 0.62, 0.025 }, { "ell", rgb(214, 160, 96), 6, 0.24, 0.5 }, { "disc", rgb(246, 244, 236), 2, 0.16 }, { "disc", rgb(110, 180, 70), 6, 0.05 } } },
	clamset = { v = "grill", bits = { { "ell", rgb(230, 136, 104), 4, 0.24, 0.85 }, { "ell", rgb(226, 212, 186), 5, 0.18, 0.8 }, { "ell", rgb(64, 52, 44), 2, 0.3, 0.4 }, { "ell", rgb(250, 214, 80), 2, 0.12, 0.8 } } },
	scallopcheese = { v = "grill", bits = { { "ell", rgb(232, 140, 104), 6, 0.26, 0.85 }, { "ell", rgb(252, 216, 90), 6, 0.15, 0.8 }, { "disc", rgb(250, 230, 120), 6, 0.04 } } },
	pen = { v = "grill", bits = { { "ell", rgb(200, 200, 204), 1, 0.6, 0.8 }, { "disc", rgb(246, 238, 220), 5, 0.17 }, { "ell", rgb(250, 220, 120), 3, 0.1, 0.8 }, { "disc", rgb(110, 180, 70), 4, 0.05 } } },
	clamsoup = { v = "steel", fill = rgb(230, 226, 200), bits = { { "ell", rgb(214, 200, 170), 6, 0.2, 0.8 }, { "disc", rgb(110, 180, 70), 6, 0.06 }, { "ell", rgb(200, 40, 30), 2, 0.1, 0.35 } } },
	ramyeon = { v = "yangeun", fill = rgb(204, 70, 30), bits = { { "bar", rgb(240, 214, 140), 9, 0.5, 0.035 }, { "ell", rgb(250, 250, 244), 1, 0.3, 0.8 }, { "disc", rgb(250, 190, 40), 1, 0.14 }, { "disc", rgb(110, 180, 70), 6, 0.06 } }, side = "kimchi" },
	gopchang = { v = "pan", fill = rgb(70, 56, 46), bits = { { "ell", rgb(236, 196, 160), 9, 0.2, 0.62 }, { "bar", rgb(90, 160, 60), 6, 0.36, 0.04 }, { "ell", rgb(244, 236, 220), 3, 0.16, 0.5 } }, side = "ssam" },
	daechang = { v = "pan", fill = rgb(70, 56, 46), bits = { { "ell", rgb(236, 186, 110), 6, 0.3, 0.42 }, { "ell", rgb(250, 230, 190), 4, 0.16, 0.6 }, { "bar", rgb(90, 160, 60), 4, 0.36, 0.04 } }, side = "ssam" },
	jeongol = { v = "pot", fill = rgb(196, 62, 34), bits = { { "ell", rgb(236, 196, 160), 6, 0.2, 0.6 }, { "ell", rgb(232, 222, 200), 4, 0.15, 0.6 }, { "ell", rgb(80, 150, 60), 4, 0.22, 0.45 }, { "bar", rgb(250, 246, 230), 4, 0.3, 0.05 } } },
	friedrice = { v = "pan", fill = rgb(222, 180, 120), bits = { { "disc", rgb(200, 90, 50), 10, 0.05 }, { "disc", rgb(40, 40, 36), 8, 0.05 }, { "disc", rgb(110, 180, 70), 8, 0.05 }, { "ell", rgb(250, 220, 110), 1, 0.3, 0.6 } } },
	galbi = { v = "grill", bits = { { "ell", rgb(128, 56, 28), 5, 0.36, 0.42 }, { "ell", rgb(236, 226, 206), 3, 0.12, 0.6 }, { "disc", rgb(240, 236, 220), 6, 0.04 } }, side = "ssam" },
	samgyeop = { v = "grill", bits = { { "ell", rgb(214, 120, 106), 5, 0.4, 0.3 }, { "ell", rgb(248, 236, 222), 5, 0.36, 0.1 }, { "ell", rgb(250, 240, 220), 3, 0.12, 0.8 } }, side = "ssam" },
	naengmyeon = { v = "steel", fill = rgb(206, 186, 140), bits = { { "ell", rgb(120, 98, 84), 1, 0.55, 0.6 }, { "ell", rgb(250, 248, 240), 1, 0.2, 0.7 }, { "disc", rgb(250, 196, 40), 1, 0.09 }, { "bar", rgb(120, 180, 80), 4, 0.24, 0.04 }, { "disc", rgb(236, 240, 244), 3, 0.12 } } },
	eggroll = { v = "plate", bits = { { "sq", rgb(250, 206, 90), 6, 0.2 }, { "disc", rgb(110, 180, 70), 8, 0.04 }, { "bar", rgb(200, 40, 30), 2, 0.6, 0.04 } } },
	golbaengi = { v = "plate", bits = { { "ell", rgb(250, 246, 236), 1, 0.5, 0.6 }, { "ell", rgb(214, 74, 40), 4, 0.3, 0.55 }, { "ell", rgb(110, 84, 54), 4, 0.15, 0.8 }, { "bar", rgb(120, 180, 80), 5, 0.3, 0.04 } } },
	dubu = { v = "plate", bits = { { "sq", rgb(248, 246, 236), 5, 0.2 }, { "ell", rgb(206, 64, 36), 1, 0.45, 0.7 }, { "ell", rgb(220, 120, 110), 3, 0.15, 0.6 }, { "disc", rgb(250, 246, 230), 6, 0.03 } } },
	jeyuk = { v = "plate", bits = { { "ell", rgb(190, 60, 30), 8, 0.28, 0.45 }, { "ell", rgb(246, 238, 220), 4, 0.2, 0.25 }, { "bar", rgb(90, 160, 60), 4, 0.3, 0.04 }, { "disc", rgb(250, 246, 230), 6, 0.03 } }, side = "ssam" },
}

local PHOTOS: { [string]: any } = {
	clam = { title = "대표 메뉴", items = { { "조개구이 모듬", "55,000", "clamset" }, { "가리비 치즈구이", "35,000", "scallopcheese" }, { "키조개 관자구이", "30,000", "pen" }, { "시원한 조개탕", "15,000", "clamsoup" }, { "해물라면", "6,000", "ramyeon" }, { "김치볶음밥", "4,000", "friedrice" } } },
	gopchang = { title = "대표 메뉴", items = { { "한우 소곱창", "22,000", "gopchang" }, { "한우 대창", "23,000", "daechang" }, { "곱창 전골", "32,000", "jeongol" }, { "볶음밥", "3,000", "friedrice" }, { "된장찌개", "5,000", "doenjang" } } },
	bbq = { title = "대표 메뉴", items = { { "숯불 돼지갈비", "17,000", "galbi" }, { "생삼겹살", "17,000", "samgyeop" }, { "물냉면", "8,000", "naengmyeon" }, { "된장찌개", "5,000", "doenjang" }, { "계란찜", "5,000", "eggs" } } },
	pochaTent = { title = "포차 인기 안주", items = { { "얼큰 해물탕", "38,000", "haemultang" }, { "매운 닭발", "19,000", "dakbal" }, { "꼼장어 구이", "25,000", "kkom" }, { "해물파전", "17,000", "pajeon" }, { "오뎅탕", "18,000", "odeng" } } },
	pochaBar = { title = "오늘의 안주", items = { { "오뎅탕", "18,000", "odeng" }, { "매운 닭발", "19,000", "dakbal" }, { "계란말이", "13,000", "eggroll" }, { "골뱅이 무침", "20,000", "golbaengi" } } },
	pocha24 = { title = "24시 해장 · 식사", items = { { "선지해장국", "9,000", "seonji" }, { "돼지국밥", "10,000", "gukbap" }, { "순대국밥", "10,000", "sundae" }, { "두부김치", "15,000", "dubu" }, { "제육볶음", "15,000", "jeyuk" }, { "매운 닭발", "18,000", "dakbal" } } },
}

local function foodPhoto(c: any, d: CFrame, w: number, h: number, kind: string, seed: number)
	local K = c.K
	local ds = DISH[kind] or DISH.gukbap
	local bgs = { rgb(118, 80, 50), rgb(86, 62, 46), rgb(150, 112, 76), rgb(62, 60, 58), rgb(178, 150, 116) }
	K:plate("PhotoBg", w, h, 0.012, d, col(bgs[seed % #bgs + 1]))
	local z = 0.012
	local function E(name: string, sw: number, sh: number, x: number, y: number, look: any, rot: number?)
		z += 0.006
		K:ell(name, V3(sw, sh, 0.012), d * CF(x, y, z) * ANG(0, 0, rot or 0), look)
	end
	local function P(name: string, sw: number, sh: number, x: number, y: number, look: any, rot: number?)
		z += 0.006
		K:plate(name, sw, sh, 0.008, d * CF(x, y, z - 0.004) * ANG(0, 0, rot or 0), look)
	end
	local side = ds.side and h > 0.9
	local dia = math.min(if side then w * 0.66 else w * 0.84, h * 0.86)
	local cx, cy = if side then -w * 0.13 else 0, -h * 0.01
	local rx, ry = dia * 0.5, dia * 0.44
	-- 그림자 + 그릇
	E("PhotoShadow", dia * 1.06, dia * 0.92, cx + dia * 0.04, cy - dia * 0.05, L.of(30, 24, 20))
	local v = ds.v
	if v == "ttuk" then
		E("PhotoBowl", dia, dia * 0.9, cx, cy, L.of(46, 36, 32))
		E("PhotoSoup", dia * 0.82, dia * 0.72, cx, cy, col(ds.fill))
		rx, ry = dia * 0.36, dia * 0.3
	elseif v == "steel" then
		E("PhotoBowl", dia, dia * 0.9, cx, cy, L.of(206, 210, 214, M.Metal))
		E("PhotoSoup", dia * 0.84, dia * 0.74, cx, cy, col(ds.fill))
		rx, ry = dia * 0.36, dia * 0.3
	elseif v == "plate" then
		E("PhotoPlate", dia * 1.04, dia * 0.86, cx, cy, L.of(250, 250, 246))
		E("PhotoPlateWell", dia * 0.84, dia * 0.68, cx, cy, L.of(238, 238, 232))
		rx, ry = dia * 0.34, dia * 0.27
	elseif v == "pan" then
		P("PhotoPanHandle", dia * 0.5, dia * 0.1, cx + dia * 0.62, cy - dia * 0.08, L.of(30, 28, 28), -0.15)
		E("PhotoPan", dia, dia * 0.9, cx, cy, L.of(34, 32, 32))
		E("PhotoPanIn", dia * 0.86, dia * 0.76, cx, cy, col(ds.fill or rgb(60, 56, 52)))
		rx, ry = dia * 0.36, dia * 0.31
	elseif v == "pot" then
		for _, sx in { -1, 1 } do
			E("PhotoPotEar", dia * 0.2, dia * 0.12, cx + sx * dia * 0.52, cy, L.of(40, 40, 42))
		end
		E("PhotoPot", dia, dia * 0.9, cx, cy, L.of(52, 52, 56, M.Metal))
		E("PhotoBroth", dia * 0.88, dia * 0.78, cx, cy, col(ds.fill))
		rx, ry = dia * 0.38, dia * 0.32
	elseif v == "yangeun" then
		E("PhotoPot", dia, dia * 0.9, cx, cy, L.of(214, 178, 92, M.Metal))
		E("PhotoBroth", dia * 0.86, dia * 0.76, cx, cy, col(ds.fill))
		rx, ry = dia * 0.36, dia * 0.31
	else -- grill: 둥근 석쇠
		E("PhotoGrill", dia, dia * 0.92, cx, cy, L.of(40, 38, 36))
		E("PhotoCoal", dia * 0.8, dia * 0.72, cx, cy, L.of(120, 46, 26))
		for i = -2, 2 do
			local yy = i * dia * 0.14
			local hw = math.sqrt(math.max(0, 1 - (yy / (dia * 0.4)) ^ 2)) * dia * 0.8
			P("PhotoGrate", hw, 0.02, cx, cy + yy, L.of(150, 146, 140, M.Metal))
		end
		rx, ry = dia * 0.34, dia * 0.3
	end
	-- 건더기 · 고명
	local k = 0
	for _, b in ds.bits or {} do
		local shape, cc, n, s = b[1], b[2], b[3], b[4]
		if not c.hi then
			n = math.max(1, math.ceil(n * 0.5))
		end
		for i = 1, n do
			k += 1
			local a = rnd(seed, k) * PI * 2
			local rr = if n == 1 then 0.1 else 0.35 + rnd(seed, k + 50) * 0.6
			local x, y = cx + math.cos(a) * rx * rr, cy + math.sin(a) * ry * rr
			local rot = rnd(seed, k + 90) * PI
			local sz = s * dia
			if shape == "ell" then
				E("PhotoBit", sz, sz * (b[5] or 0.7), x, y, col(cc), rot)
			elseif shape == "disc" then
				E("PhotoDot", sz, sz, x, y, col(cc))
			elseif shape == "sq" then
				P("PhotoCube", sz, sz * 0.85, x, y, col(cc), rot * 0.3)
			else
				P("PhotoStrip", sz, math.max(0.02, sz * (b[5] or 0.06)), x, y, col(cc), rot)
			end
		end
	end
	-- 김 · 윤기 하이라이트
	E("PhotoGloss", dia * 0.28, dia * 0.07, cx - dia * 0.2, cy + dia * 0.3, { c = WHITE, m = M.SmoothPlastic, t = 0.45 }, 0.25)
	-- 곁들이 반찬 (오른쪽 작은 접시)
	if side then
		local sx, sy, sd = w * 0.33, -h * 0.18, math.min(w * 0.3, h * 0.42)
		E("PhotoSidePlate", sd, sd * 0.84, sx, sy, L.of(250, 250, 246))
		local sc = if ds.side == "kkakdugi" then rgb(214, 70, 40) elseif ds.side == "kimchi" then rgb(206, 80, 46) elseif ds.side == "ssam" then rgb(86, 160, 64) elseif ds.side == "egg" then rgb(250, 214, 110) else rgb(80, 56, 40)
		for i = 1, (if c.hi then 4 else 2) do
			local a = i * 1.7 + seed
			if ds.side == "kkakdugi" then
				P("PhotoSideBit", sd * 0.22, sd * 0.2, sx + math.cos(a) * sd * 0.18, sy + math.sin(a) * sd * 0.14, col(sc), a)
			else
				E("PhotoSideBit", sd * 0.42, sd * 0.24, sx + math.cos(a) * sd * 0.14, sy + math.sin(a) * sd * 0.1, col(sc), a)
			end
		end
		-- 수저 (위 오른쪽)
		P("PhotoSpoon", w * 0.36, 0.035, w * 0.3, h * 0.3, L.of(214, 216, 220, M.Metal), 0.2)
		E("PhotoSpoonHead", 0.12, 0.08, w * 0.12, h * 0.26, L.of(214, 216, 220, M.Metal), 0.2)
	end
end

-- 라이트박스 한 판: 알루미늄 테 + 흰 아크릴 면 + 머리띠 + 칸마다 사진 · 이름 · 가격, 위 · 아래 LED 테
local function photoMenu(c: any, walls: { string }, near: Vector3?, y0: number, y1: number, maxN: number?): boolean
	local K, V, th = c.K, c.V, c.th
	local set = PHOTOS[th.key]
	if not set then
		return false
	end
	local items = set.items
	local cw = 1.9
	local nMax = math.min(#items, maxN or #items)
	local nMin = math.min(nMax, 2)
	local wn, u, w = findWall(K, walls, nMin * cw + 0.4, nMax * cw + 0.4, y0, y1, near, 0.6)
	if not wn or not u or not w then
		return false
	end
	local n = math.max(1, math.min(nMax, math.floor((w - 0.4) / cw)))
	local bw = n * cw + 0.4
	local bh = y1 - y0 - 0.2
	local d = V:wall(wn, u, (y0 + y1) / 2, 0)
	local depth = 0.26
	K:plate("LightboxBack", bw, bh, depth - 0.02, d, L.of(60, 62, 66, M.Metal))
	-- 알루미늄 테 (4변, 살짝 둥근 단면)
	for _, sy in { -1, 1 } do
		K:plate("LightboxRail", bw + 0.08, 0.12, depth + 0.02, d * CF(0, sy * (bh / 2 + 0.02), 0), L.alu)
	end
	for _, sx in { -1, 1 } do
		K:plate("LightboxRail", 0.12, bh + 0.16, depth + 0.02, d * CF(sx * (bw / 2 + 0.02), 0, 0), L.alu)
	end
	local f = d * CF(0, 0, depth - 0.02)
	K:plate("LightboxFace", bw - 0.08, bh - 0.06, 0.012, f, L.of(252, 252, 248))
	-- 머리띠 (색) + 제목
	local hh = 0.5
	local hy = bh / 2 - 0.05 - hh / 2
	K:plate("LightboxHead", bw - 0.08, hh, 0.014, f * CF(0, hy, 0.012), col(th.accent))
	txt(K, "LightboxTitle", math.min(bw - 0.6, 5.2), hh * 0.72, f * CF(0, hy, 0.028), set.title, WHITE, nil, F.GothamBlack, { glow = 1.15, d = 0.004 })
	if c.hi then
		txt(K, "LightboxSub", 1.6, hh * 0.42, f * CF(bw / 2 - 1.0, hy, 0.028), "사진은 실제와 다를 수 있습니다", lift(col(th.accent), 0.6).c, nil, F.GothamMedium, { glow = 1.0, d = 0.004 })
	end
	-- 위 · 아래 LED 띠 (불 켜진 라이트박스 느낌)
	K:plate("LightboxLED", bw - 0.2, 0.05, 0.015, f * CF(0, hy - hh / 2 - 0.04, 0.012), L.lampNeutral)
	K:plate("LightboxLED", bw - 0.2, 0.05, 0.015, f * CF(0, -bh / 2 + 0.08, 0.012), L.lampNeutral)
	-- 칸
	local top = hy - hh / 2 - 0.1
	local bot = -bh / 2 + 0.14
	local nameH, priceH = 0.34, 0.3
	local ph = (top - bot) - nameH - priceH - 0.12
	for i = 1, n do
		local it = items[i]
		local x = -bw / 2 + 0.2 + cw * (i - 0.5)
		local pw = cw - 0.18
		local py = top - ph / 2
		K:plate("PhotoMat", pw + 0.06, ph + 0.06, 0.012, f * CF(x, py, 0.012), L.of(214, 214, 210))
		foodPhoto(c, f * CF(x, py, 0.024), pw, ph, it[3], c.seed + i * 13)
		txt(K, "PhotoName", pw, nameH, f * CF(x, top - ph - 0.06 - nameH / 2, 0.016), it[1], INK, nil, F.GothamBlack, { glow = 1.05, d = 0.004 })
		txt(K, "PhotoPrice", pw * 0.8, priceH, f * CF(x, top - ph - 0.08 - nameH - priceH / 2, 0.016), it[2] .. "원", rgb(206, 24, 24), nil, F.GothamBold, { glow = 1.05, d = 0.004 })
		if i < n then
			K:plate("PhotoDivider", 0.02, top - bot, 0.01, f * CF(x + cw / 2, (top + bot) / 2, 0.012), L.of(220, 220, 216))
		end
	end
	-- 전선 (라이트박스 아래로 콘센트까지)
	if c.hi then
		local a = (d * CF(bw / 2 - 0.3, -bh / 2, 0.05)).Position
		local oy = math.max((th.lower and th.lower.h or 3.4) + 0.5, y0 - 1.0)
		K:seg("LightboxCord", a, (V:wall(wn, u + bw / 2 - 0.3, oy + 0.2, 0.05)).Position, 0.04, L.of(240, 240, 236))
		Props.outlet(K, V:wall(wn, u + bw / 2 - 0.3, oy, 0))
	end
	at(K, "photo menu", wn, u)
	return true
end

-- 셀프 물 코너: 흰 하부장 + 정수기 (온 · 냉 버튼 · 물받이) + UV 컵 소독기 (스테인리스 컵) + 종이컵 디스펜서 + 안내
local function waterStation(c: any)
	local K, V, th = c.K, c.V, c.th
	if V:has("WaterPurifier") > 0 or V:has("WaterDispenser") > 0 or V:has("WaterBottle") > 0 then
		return
	end
	local size = V3(2.1, 4.7, 1.3)
	local pcf, wn, u = floorOnWall(K, { "left", "right", "back" }, size, V3(V.x0 * 0.6, 0, V.z0 + 2), 0.15)
	if not pcf or not wn or not u then
		return
	end
	local w, d, h = 2.0, 1.2, 2.7
	K:box("WaterCabKick", V3(w - 0.12, 0.22, d - 0.12), pcf * CF(0, 0.11, -0.03), L.black)
	K:box("WaterCab", V3(w, h - 0.22, d), pcf * CF(0, 0.22 + (h - 0.22) / 2, 0), L.white)
	K:plate("WaterCabSeam", 0.02, h - 0.4, 0.01, pcf * CF(0, 0.32 + (h - 0.4) / 2, d / 2), L.of(200, 200, 196))
	for _, sx in { -1, 1 } do
		K:box("WaterCabPull", V3(0.05, 0.5, 0.06), pcf * CF(sx * 0.12, h - 0.55, d / 2 + 0.03), L.chrome)
	end
	K:box("WaterCabTop", V3(w + 0.04, 0.06, d + 0.04), pcf * CF(0, h + 0.03, 0), L.steel)
	-- 정수기 (왼쪽)
	local pb = pcf * CF(-0.48, h + 0.06, -0.05)
	K:rbox("PurifierBody", V3(0.8, 1.55, 0.95), 0.12, pb * CF(0, 0.775, 0), L.of(246, 246, 244))
	K:plate("PurifierPanel", 0.56, 0.4, 0.02, pb * CF(0, 1.22, 0.475), L.of(26, 28, 32, M.Glass, { r = 0.1 }))
	for i, cc in { rgb(80, 160, 255), WHITE, rgb(255, 90, 70) } do
		K:plate("PurifierBtn", 0.1, 0.1, 0.01, pb * CF(-0.18 + (i - 1) * 0.18, 1.18, 0.497), L.neon(cc))
	end
	txt(K, "PurifierLabel", 0.5, 0.1, pb * CF(0, 1.34, 0.497), "냉수   정수   온수", rgb(220, 224, 230), nil, F.GothamBold, { glow = 1.0, d = 0.003 })
	K:box("PurifierNozzle", V3(0.14, 0.1, 0.2), pb * CF(0, 0.92, 0.52), L.chrome)
	K:plate("PurifierRecess", 0.5, 0.62, 0.01, pb * CF(0, 0.66, 0.475), L.of(220, 222, 224))
	K:box("PurifierTray", V3(0.5, 0.06, 0.3), pb * CF(0, 0.38, 0.52), L.of(60, 62, 66))
	K:plate("PurifierLED", 0.4, 0.03, 0.01, pb * CF(0, 1.5, 0.477), L.ledBlue)
	-- UV 컵 소독기 (오른쪽): 스테인리스 상자 + 유리문 + 보라 빛 + 컵 줄
	local ub = pcf * CF(0.5, h + 0.06, -0.12)
	local uw, uh, ud = 0.92, 1.25, 0.8
	K:box("UVBody", V3(uw, uh, ud), ub * CF(0, uh / 2, 0), L.steel)
	K:box("UVInner", V3(uw - 0.12, uh - 0.3, 0.02), ub * CF(0, uh / 2 - 0.02, -ud / 2 + 0.08), L.neon(rgb(150, 110, 255)))
	K:box("UVShelf", V3(uw - 0.12, 0.03, ud - 0.16), ub * CF(0, uh * 0.5, 0), L.chrome)
	for row = 0, 1 do
		for i = 0, 3 do
			K:vcyl("SteelCup", 0.24, 0.17, ub * CF(-0.3 + i * 0.2, 0.2 + row * uh * 0.44 + 0.12, 0.08), L.chrome)
		end
	end
	K:box("UVDoor", V3(uw - 0.06, uh - 0.14, 0.03), ub * CF(0, uh / 2, ud / 2 + 0.015), { c = rgb(200, 190, 240), m = M.Glass, t = 0.55, r = 0.15 })
	K:box("UVHandle", V3(0.4, 0.05, 0.05), ub * CF(0, uh - 0.18, ud / 2 + 0.06), L.black)
	txt(K, "UVLabel", 0.7, 0.12, ub * CF(0, 0.08, ud / 2 + 0.035), "자외선 컵 소독기", INK, nil, F.GothamBold, { d = 0.003 })
	-- 종이컵 디스펜서 (벽) + 쟁반 위 컵 몇 개
	local cd = V:wall(wn, u + 0.5, h + 1.85, 0)
	K:vcyl("CupTube", 1.0, 0.3, cd * CF(0, 0, 0.2), { c = rgb(230, 236, 240), m = M.Glass, t = 0.5 })
	K:vcyl("CupStack", 0.9, 0.24, cd * CF(0, 0.02, 0.2), L.paper)
	K:plate("CupBracket", 0.36, 0.2, 0.06, cd * CF(0, 0.38, 0), L.steel)
	K:box("TowelRoll", V3(0.5, 0.42, 0.36), pcf * CF(0.55, 0.22 + 1.1, d / 2 - 0.25), L.paper)
	-- 안내판
	local sd = V:wall(wn, u - 0.45, h + 2.2, 0)
	claim(K, wn, u - 1.2, u + 1.2, h, h + 2.8)
	plateSign(K, sd, 1.15, 0.6, "물은\n셀프입니다", WHITE, rgb(40, 120, 200), nil, F.GothamBlack)
	at(K, "water station", wn, u)
end

-- 활어 · 조개 수조 (2단 유리 수조 + 스테인리스 받침 · 냉각기 + 파란 LED + 기포 + 가격 스티커)
local function liveTank(c: any)
	local K, V, th = c.K, c.V, c.th
	local W = math.clamp(V.W * 0.13, 3.6, 4.8)
	local size = V3(W + 0.1, 6.5, 2.0)
	local pcf, wn, u = floorOnWall(K, { "left", "right", "back" }, size, V3(V.x0, 0, V.z1 - 3), 0.2)
	if not pcf or not wn or not u then
		return
	end
	local D = 1.85
	local frame = L.of(150, 154, 160, M.Metal)
	local water = { c = rgb(70, 160, 210), m = M.SmoothPlastic, t = 0.7, r = 0.05 }
	local standH = 1.5
	K:box("TankKick", V3(W - 0.2, 0.2, D - 0.2), pcf * CF(0, 0.1, 0), L.black)
	K:box("TankStand", V3(W, standH - 0.2, D), pcf * CF(0, 0.2 + (standH - 0.2) / 2, 0), L.brushed)
	-- 냉각기 통풍 그릴 (받침 앞)
	for i = 0, 5 do
		K:plate("ChillerVent", W * 0.4, 0.05, 0.02, pcf * CF(-W * 0.22, 0.45 + i * 0.16, D / 2), L.of(44, 46, 50))
	end
	K:plate("ChillerPanel", 0.7, 0.36, 0.02, pcf * CF(W * 0.26, 1.0, D / 2), L.of(28, 30, 34))
	txt(K, "ChillerTemp", 0.6, 0.24, pcf * CF(W * 0.26, 1.0, D / 2 + 0.022), "수온 12.5℃", rgb(120, 230, 140), nil, F.Arcade, { glow = 1.3, d = 0.003 })
	local tiers = { { standH, 1.85 }, { standH + 2.05, 1.5 } }
	local catch = th.catch or {}
	for ti, tr in tiers do
		local y0, hh = tr[1], tr[2]
		local base = pcf * CF(0, y0, 0)
		K:box("TankFloor", V3(W, 0.08, D), base * CF(0, 0.04, 0), frame)
		K:box("TankBed", V3(W - 0.16, 0.06, D - 0.16), base * CF(0, 0.11, 0), L.of(214, 204, 180, M.Sand))
		K:box("LiveTankWater", V3(W - 0.14, hh - 0.32, D - 0.14), base * CF(0, 0.14 + (hh - 0.32) / 2, 0), water)
		-- 유리 앞판 + 모서리 프레임
		K:box("TankGlass", V3(W - 0.08, hh - 0.1, 0.03), base * CF(0, 0.08 + (hh - 0.1) / 2, D / 2 - 0.02), { c = rgb(220, 236, 240), m = M.SmoothPlastic, t = 0.88, r = 0.2 })
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				K:box("TankPost", V3(0.08, hh, 0.08), base * CF(sx * (W / 2 - 0.04), hh / 2, sz * (D / 2 - 0.04)), frame)
			end
		end
		K:box("TankRim", V3(W, 0.1, 0.1), base * CF(0, hh - 0.05, D / 2 - 0.05), frame)
		K:box("TankRim", V3(W, 0.1, 0.1), base * CF(0, hh - 0.05, -D / 2 + 0.05), frame)
		K:box("TankLED", V3(W - 0.3, 0.05, 0.1), base * CF(0, hh - 0.14, 0.2), L.neon(rgb(110, 190, 255)))
		-- 해산물 (칸 2개) + 가격 스티커
		local nsec = 2
		for si = 1, nsec do
			local item = catch[((ti - 1) * nsec + si - 1) % math.max(1, #catch) + 1]
			if item then
				local sx = -W / 2 + W * (si - 0.5) / nsec
				seafood(c, item[1], base * CF(sx, 0.14, 0), W / nsec - 0.5, D - 0.6, c.seed + ti * 10 + si)
				local tag = string.gsub(item[2], "\n", "  ")
				txt(K, "TankTag", math.min(1.5, W / nsec - 0.3), 0.28, base * CF(sx, hh - 0.38, D / 2 + 0.005), tag, rgb(200, 16, 16), rgb(255, 250, 228), F.GothamBlack, { d = 0.01 })
			end
			if si < nsec then
				K:box("TankDivider", V3(0.02, hh - 0.3, D - 0.2), base * CF(-W / 2 + W * si / nsec, 0.1 + (hh - 0.3) / 2, 0), { c = rgb(220, 236, 240), m = M.Glass, t = 0.7 })
			end
		end
		-- 기포 (에어스톤 + 올라가는 방울)
		if c.hi then
			for bi = 1, 2 do
				local bx = (if bi == 1 then -1 else 1) * W * 0.36
				K:vcyl("AirStone", 0.08, 0.16, base * CF(bx, 0.18, -D / 2 + 0.3), L.of(150, 140, 130, M.Slate))
				for k = 1, 5 do
					local yy = 0.3 + (hh - 0.75) * k / 5
					K:ball("Bubble", 0.05 + rnd(c.seed, ti * 30 + bi * 7 + k) * 0.06, base * CF(bx + (rnd(c.seed, k + bi) - 0.5) * 0.12, yy, -D / 2 + 0.3), { c = rgb(240, 250, 255), m = M.Glass, t = 0.35 })
				end
			end
		end
	end
	-- 위: 여과기 · 냉각 배관 상자 + 호스
	local ty = standH + 2.05 + 1.5
	K:box("FilterBox", V3(W, 0.8, D - 0.3), pcf * CF(0, ty + 0.42, -0.15), L.of(60, 64, 70, M.Metal))
	K:plate("FilterLabel", 1.6, 0.36, 0.01, pcf * CF(0, ty + 0.42, (D - 0.3) / 2 - 0.15), L.of(240, 240, 236))
	txt(K, "FilterText", 1.5, 0.3, pcf * CF(0, ty + 0.42, (D - 0.3) / 2 - 0.135), "해수 순환 여과", INK, nil, F.GothamBold, { d = 0.004 })
	K:seg("TankHose", (pcf * CF(W / 2 - 0.2, ty + 0.2, -D / 2 + 0.2)).Position, (pcf * CF(W / 2 - 0.2, standH + 0.2, -D / 2 + 0.2)).Position, 0.1, L.of(30, 30, 34, M.Rubber))
	K:seg("TankHose", (pcf * CF(-W / 2 + 0.2, ty + 0.2, -D / 2 + 0.2)).Position, (pcf * CF(-W / 2 + 0.2, standH + 2.1, -D / 2 + 0.2)).Position, 0.08, L.of(210, 220, 230, M.Plastic))
	-- 뜰채 (옆에 걸림)
	local nx = W / 2 + 0.05
	K:seg("NetPole", (pcf * CF(nx, 1.6, 0.4)).Position, (pcf * CF(nx, 4.6, 0.3)).Position, 0.05, L.of(220, 200, 60, M.Plastic))
	K:make("Part", "NetRing", V3(0.04, 0.5, 0.5), pcf * CF(nx + 0.02, 4.85, 0.3), L.of(40, 120, 200, M.Plastic), Enum.PartType.Cylinder)
	-- 위 간판 (벽)
	local sd = V:wall(wn, u, math.min(V.H - 0.9, ty + 1.5), 0)
	claim(K, wn, u - W / 2 - 0.3, u + W / 2 + 0.3, 0, V.H)
	plateSign(K, sd, math.min(W, 4.2), 0.6, if th.pocha then "오늘 들어온 활어 · 해산물" else "산지직송 활 조개 수조", WHITE, rgb(20, 100, 170), nil, F.GothamBlack)
	at(K, "live tank", wn, u)
end


-- 네온 문구 간판 (아크릴 판 + 빛나는 글자 + 같은 색 네온관 테 + 벽 고정 볼트). 불빛(Light)은 안 씀 (예산)
local NEON_SLOGANS: { [string]: any } = {
	clam = { { "조개 굽는 밤", rgb(90, 230, 255) }, { "오늘도 조개각", rgb(255, 120, 200) } },
	gopchang = { { "오늘은 곱창에 소주", rgb(255, 90, 150) }, { "곱창은 사랑입니다", rgb(255, 120, 80) } },
	bbq = { { "고기는 사랑입니다", rgb(255, 170, 70) } },
	pochaTent = { { "오늘 밤은 포차에서", rgb(255, 100, 170) }, { "소주 한잔 할래?", rgb(110, 230, 255) } },
	pochaBar = { { "술술 넘어간다", rgb(255, 210, 80) }, { "오늘 밤은 포차에서", rgb(255, 100, 170) } },
	pocha24 = { { "새벽까지 영업중", rgb(120, 230, 255) }, { "해장은 여기서", rgb(255, 150, 60) } },
}
local function neonSlogan(c: any)
	local K, V, th = c.K, c.V, c.th
	local list = NEON_SLOGANS[th.key]
	if not list then
		return
	end
	local pick = list[c.seed % #list + 1]
	local text, cc = pick[1], pick[2]
	local n = utf8.len(text) or 6
	local w0 = math.clamp(n * 0.62, 3.2, 5.6)
	local wn, u, fw = findWall(K, { "back", "left", "right" }, 3.4, w0 + 0.4, 5.5, 8.1, V3(V.x1 * 0.5, 0, V.z0), 0.6)
	if not wn or not u or not fw then
		return
	end
	local w = fw - 0.4
	local h = math.clamp(w * 0.24, 0.9, 1.25)
	local d = V:wall(wn, u, 6.8, 0)
	-- 아크릴 판 (반투명 검정) + 볼트 4
	K:plate("NeonAcrylic", w + 0.3, h + 0.4, 0.05, d * CF(0, 0, 0.12), { c = rgb(24, 24, 28), m = M.SmoothPlastic, t = 0.35, r = 0.2 })
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			K:vcyl("NeonStandoff", 0.12, 0.1, d * CF(sx * (w / 2 + 0.02), sy * (h / 2 + 0.07), 0.06) * ANG(PI / 2, 0, 0), L.chrome)
		end
	end
	txt(K, "NeonText", w, h * 0.78, d * CF(0, 0.02, 0.18), text, cc, nil, F.GothamBlack, { glow = 2.4, d = 0.01 })
	-- 네온관 테 (둥근 모서리 사각): 위 · 아래 · 옆 막대
	local tube = L.neon(cc)
	local tw, th2 = w + 0.1, h + 0.2
	K:seg("NeonTube", (d * CF(-tw / 2 + 0.2, th2 / 2, 0.2)).Position, (d * CF(tw / 2 - 0.2, th2 / 2, 0.2)).Position, 0.06, tube)
	K:seg("NeonTube", (d * CF(-tw / 2 + 0.2, -th2 / 2, 0.2)).Position, (d * CF(tw / 2 - 0.2, -th2 / 2, 0.2)).Position, 0.06, tube)
	K:seg("NeonTube", (d * CF(-tw / 2, -th2 / 2 + 0.2, 0.2)).Position, (d * CF(-tw / 2, th2 / 2 - 0.2, 0.2)).Position, 0.06, tube)
	K:seg("NeonTube", (d * CF(tw / 2, -th2 / 2 + 0.2, 0.2)).Position, (d * CF(tw / 2, th2 / 2 - 0.2, 0.2)).Position, 0.06, tube)
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			local a0 = if sx > 0 then (if sy > 0 then 0 else -PI / 2) else (if sy > 0 then PI / 2 else PI)
			K:ring("NeonTube", d * CF(sx * (tw / 2 - 0.2), sy * (th2 / 2 - 0.2), 0.2), 0.2, 0.06, 3, tube, a0, a0 + PI / 2)
		end
	end
	-- 하트 장식 (작은 네온 원 두 개 + 쐐기 대신 원)
	if c.hi then
		local hx = tw / 2 - 0.45
		K:ring("NeonHeart", d * CF(hx - 0.1, th2 / 2 - 0.42, 0.21), 0.1, 0.04, 6, L.neon(rgb(255, 80, 110)))
		K:ring("NeonHeart", d * CF(hx + 0.1, th2 / 2 - 0.42, 0.21), 0.1, 0.04, 6, L.neon(rgb(255, 80, 110)))
	end
	-- 전원선 (아래로)
	K:seg("NeonCord", (d * CF(tw / 2 - 0.3, -th2 / 2 - 0.05, 0.08)).Position, (d * CF(tw / 2 - 0.3, -th2 / 2 - 1.1, 0.03)).Position, 0.035, L.of(30, 30, 32))
	at(K, "neon", wn, u)
end

-- 스타일 · 빌드 --------------------------------------------------------------------------------------------
function T.style(V: any): any
	local th = themeFor(V)
	local S: any = {
		theme = th,
		chair = false,
		stool = false,
		table = false,
		counter = th.counter or { front = "tile", frontL = L.of(196, 64, 44, M.CeramicTiles), topL = L.steel, kickL = L.black, led = rgb(255, 196, 130) },
		ceiling = if th.tent == "full" then false elseif th.key == "pocha24" then { grid = true, tile = 2.0 } else { grid = false },
		floor = th.floor,
		lower = th.lower,
		base = th.base,
		pendant = { shade = if th.pocha then "bulb" else "dome", look = L.of(200, 202, 206, M.Metal) },
		clock = false,
		license = #V.counters > 0,
		cctv = th.tent ~= "full",
		mat = { look = L.of(56, 58, 62, M.Fabric) },
		lights = { kind = "none" },
	}
	return S
end

function T.build(K: any, V: any, S: any)
	local th = S.theme or themeFor(V)
	local c: any = { K = K, V = V, S = S, th = th, hi = K.detail == "high", seed = hash(V.key or V.name or "grill") % 997 }
	local function step(name: string, fn: (any) -> ())
		local ok, err = pcall(fn, c)
		if not ok then
			K:note("grill." .. name .. " error: " .. tostring(err))
		end
	end
	step("signs", signClaims)
	step("stools", stoolsOver)
	step("chairs", chairsOver)
	step("tables", tablesOver)
	step("fridge", function()
		c.hasFridge = fridgeOver(c)
	end)
	step("display", displayOver)
	if th.key == "pochaBar" then
		step("oden", odengBath)
		step("backbar", backBarOver)
	end
	step("tvmap", tvOver)
	if th.key == "pocha24" then
		step("pass", passDecor)
		step("platform", platformOver)
	end
	-- 천장
	if th.tent == "full" then
		step("hideCeil", hideCeilingKit)
		step("tent", tentCeiling)
	elseif th.tent == "eaves" then
		step("eaves", tentEaves)
	else
		step("leds", grillLights)
	end
	step("band", tileBand)
	-- 벽 (큰 것부터)
	if th.kitchenDoor then
		step("kdoor", kitchenDoor)
	end
	if th.menuStyle ~= "sheets" then
		step("menus", mainMenus)
	end
	-- 상호작용 벽 · 바닥 소품 먼저 (프롬프트 자리는 테이블에서 먼 벽에만 있어서 드묾)
	if not c.hasFridge and th.pocha then
		step("standFridge", standFridge)
	end
	if th.tv then
		step("tv", wallTV)
	end
	step("fan", wallFan)
	if th.exhaust then
		step("exhaust", exhaustFan)
	end
	if c.bulbs and #c.bulbs > 0 then
		step("bulbSwitch", bulbSwitch)
	end
	-- 사진 메뉴 라이트박스 + 손글씨 메뉴 줄
	if th.menuStyle == "sheets" then
		step("photo", function()
			photoMenu(c, { "left", "right", "back" }, V3(V.x0, 0, -1), 5.2, 8.1, if th.key == "pochaBar" then 4 elseif th.key == "pochaTent" then 5 else 6)
		end)
		step("neon", neonSlogan)
		step("sheets", menuSheets)
	else
		step("photo", function()
			photoMenu(c, { "right", "left", "back" }, V3(V.x1, 0, 0), 5.3, 8.2, 6)
		end)
	end
	if th.menuStyle ~= "sheets" then
		step("neon", neonSlogan)
	end
	-- 바닥 소품: 수조 (조개구이 · 해물 포차, 앞쪽 옆벽) · 에어컨 · 화로대 · 셀프 카트 · 셀프 물 · 소주 박스
	if th.key == "clam" or (th.pocha and th.key ~= "pocha24") then
		step("tank", liveTank)
	end
	if th.standAC then
		step("standAC", standAC)
	end
	if th.station then
		step("station", charcoalStation)
	end
	if th.selfBar then
		step("selfCart", selfCart)
	end
	step("water", waterStation)
	if th.crates then
		step("crates", crateStack)
	end
	-- 안내 · 장식
	step("origin", function()
		originBoard(c, V3(V.x0 * 0.3, 0, V.z0))
	end)
	if th.pocha then
		step("chalk", chalkboard)
	end
	step("info", infoSigns)
	if not th.pocha or th.key == "pochaTent" then
		step("aprons", apronRack)
	end
	step("autos", autographs)
	step("posters", posters)
	step("clock", wallClock)
	-- 전구 빛 (남은 불빛 예산으로)
	if c.bulbs and #c.bulbs > 0 then
		step("bulbLights", function()
			bulbLights(c, math.max(1, math.min(4, (V.maxLights or 8) - #K.lights - 1)))
		end)
	end
end

return T
