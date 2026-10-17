--!strict
-- GwangalliBuildingInterior/T_cafe: 유형 (cafe bakery dessert) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드) + S.brand (아래 B)
--   build(K, V, S) 유형별 디테일 (메뉴판 · 진열 · 장비 · 간판 · 소품 · 상호작용)
--
-- 브랜드 B (이름 · 메뉴 · 맵 내용물로 고름): 메가 · 컴포즈 · 투썸 · 파스쿠찌 · 스타벅스 · 로스터리 · 오뜨 · 051 · 라운지 ·
--   인디 5종 (scandi / terracotta / concrete / ocean / green, 매장 이름 해시로) · 베이커리 · 와플/젤라또 · 탕후루 ·
--   빙수 · 인형뽑기(BINGBING) · 츄러스 · 호떡. 가격은 2026 부산 기준.
-- 짓는 순서 (각 단계 pcall):
--   1) 맵 간판 · 표시물 자리 등록 (V:spans 는 Sign_* 쉘을 안 보므로 K.wallUsed 에 넣음)
--   2) 큰 바닥 소품 (로스터 · 오븐 · 셀프바 · 냉장 쇼케이스 · MD 선반 · 아일랜드 진열대 · 화분) — K:spot + 벽 사용 기록
--   3) 카운터 위 / 뒤 장비 (카드단말기 · 진동벨 · 메뉴 스탠드 · 블렌더 · 시럽 · 컵 디스펜서 · 제빙기 패널 ...)
--   4) 맵의 엉성한 장식 다시 만들기 (Jar · Pastry · Bread · Cup · Plush 숨기고 같은 자리에) + 게임플레이 장비는
--      같은 자세 오버레이 (GelatoTub · WaffleIron) 또는 0.02 바깥 스킨 (EspressoBody · Grinder · CaseBase)
--   5) 뒷벽 메뉴판 (라이트박스 / 칠판 / 펠트 레터보드 / 브라스) + 로고 + 프로모 띠
--   6) 옆벽: 액자 · 네온(켜기/끄기) · 안내문 (와이파이 · 영업시간 · 카드결제 · 원산지 · 위생등급) · 선반 · 스피커(BGM 바꾸기) · TV
--   7) 천장: 덕트 · 레일 조명 · 픽업 전광판 · 행잉 화분 · LED 띠
-- 상호작용 (클라이언트 전용, 서버 행동과 안 겹침): 네온사인 켜기/끄기 · 매장 BGM 바꾸기 (이퀄라이저 LED) ·
--   음료 냉장고 / 케이크 쇼케이스 문 여닫기 · 커피 로스터 가동 (드럼 창 · 냉각 날개 회전) · 인형뽑기방 LED 모드 ·
--   아이스크림 냉동고 뚜껑. 애니메이션: 픽업 전광판 번호 · TV 프로모 · 오븐 불빛 · 벽시계.
-- 예산: room(K, n) 으로 복합 소품을 통째로 짓거나 건너뜀 (저사양 1300 파트에서도 반쪽 소품 없음).
-- 스타벅스 광안리점: 바리스타 잡 시스템 → 카운터 위 · 카운터 리스킨 · 커피 머신 스킨 · 바닥 소품은 하지 않음.

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local T = {}
T.types = { "cafe", "bakery", "dessert" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local F = Enum.Font
local rgb = Color3.fromRGB
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

-- 작은 도구 ------------------------------------------------------------------------------------------
local function hashStr(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 1000003
	end
	return h
end

-- 0..1 의사난수
local function rnd(seed: number, i: number): number
	local s = math.sin((seed % 9973) * 0.731 + i * 12.9898) * 43758.5453
	return s - math.floor(s)
end

local function dk(c: Color3, f: number): Color3
	return c:Lerp(BLACK, f)
end
local function lt(c: Color3, f: number): Color3
	return c:Lerp(WHITE, f)
end
local function lk(c: Color3, m: Enum.Material?, extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
-- 바탕색 위에서 잘 읽히는 글자색
local function onColor(c: Color3): Color3
	local lum = c.R * 0.3 + c.G * 0.59 + c.B * 0.11
	return if lum > 0.7 then dk(c, 0.78) else rgb(255, 255, 255)
end

local function glassL(c: Color3?, t: number?): { [string]: any }
	return { c = c or rgb(226, 236, 238), m = M.Glass, t = t or 0.55, r = 0.12 }
end

-- 표시면 프레임 (점 p, 바깥 법선 n)
local function faceCF(p: Vector3, n: Vector3): CFrame
	local x = Vector3.yAxis:Cross(n).Unit
	return CFrame.fromMatrix(p, x, Vector3.yAxis, n)
end
-- 소품 프레임: 원점 p, +Z = n
local function facing(p: Vector3, n: Vector3): CFrame
	return CFrame.lookAt(p, p - n)
end
-- 벽(표시면)에 붙는 원판: 축 = dcf Z
local function wdisc(K: any, name: string, dia: number, t: number, dcf: CFrame, look: any): BasePart
	return K:disc(name, dia, t, dcf * CF(0, 0, t / 2) * ANG(PI / 2, 0, 0), look)
end
-- 위를 보는 글자판 (카운터 위 스티커 · 바닥 표시): p 중심, 글자 위쪽 = up (수평 벡터)
local function topCF(p: Vector3, up: Vector3): CFrame
	local x = up:Cross(Vector3.yAxis).Unit
	return CFrame.fromMatrix(p, x, up, Vector3.yAxis)
end

-- 긴 자리 찾기 루프 안에서 프레임 양보 (Kit:tick 과 같은 시간 분할, 파트 수는 안 셈)
local function breathe(K: any)
	if K.sliceT and os.clock() - K.sliceT > (K.slice or 0.0025) then
		task.wait()
		K.sliceT = os.clock()
	end
end

-- 남은 파트 예산 (복합 소품은 통째로 짓거나 통째로 건너뜀)
local function room(K: any, n: number): boolean
	return #K.parts + n <= (K.maxParts or 2600) - 24
end

local function hi(K: any): boolean
	return K.detail == "high"
end
local function lowD(K: any): boolean
	return K.detail == "low"
end

-- 자리 관리 ---------------------------------------------------------------------------------------------
local function useWall(K: any, wn: string, a: number, b: number, y0: number, y1: number)
	K.wallUsed = K.wallUsed or {}
	table.insert(K.wallUsed, { w = wn, a = a, b = b, y0 = y0, y1 = y1 })
end

local function wallBlocked(K: any, wn: string, a: number, b: number, y0: number, y1: number): boolean
	for _, u in K.wallUsed or {} do
		if u.w == wn and u.y1 > y0 and u.y0 < y1 and u.b > a and u.a < b then
			return true
		end
	end
	return false
end

-- 벽면 빈 구간 (V:spans 에서 K.wallUsed 빼기)
local function freeSpans(K: any, wn: string, y0: number, y1: number, depth: number?): { { number } }
	local V = K.V
	local out = {}
	for _, s in V:spans(wn, y0, y1, depth or 1.0) do
		local segs = { { s[1], s[2] } }
		for _, u in K.wallUsed or {} do
			if u.w == wn and u.y1 > y0 and u.y0 < y1 then
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
			if g[2] - g[1] > 0.3 then
				table.insert(out, g)
			end
		end
	end
	return out
end

-- 벽에 w 폭, y0..y1 높이 자리 찾기. pred(dcf, wn, u) 로 추가 조건 (프롬프트 거리 등). 반환 wn, dcf(가운데), u
local function wallFind(K: any, walls: { string }, w: number, y0: number, y1: number, prefer: any?, pred: any?, depth: number?): (string?, CFrame?, number?)
	local V = K.V
	for _, wn in walls do
		local pu = 0
		if type(prefer) == "number" then
			pu = prefer
		elseif type(prefer) == "table" and prefer[wn] then
			pu = prefer[wn]
		end
		local cands = {}
		for _, s in freeSpans(K, wn, y0, y1, depth) do
			if s[2] - s[1] >= w then
				local lo, hi2 = s[1] + w / 2, s[2] - w / 2
				table.insert(cands, math.clamp(pu, lo, hi2))
				if pred then
					local u = lo
					while u <= hi2 do
						table.insert(cands, u)
						u += 0.5
					end
				end
			end
		end
		table.sort(cands, function(a, b)
			return math.abs(a - pu) < math.abs(b - pu)
		end)
		for _, cu in cands do
			breathe(K)
			local dcf = V:wall(wn, cu, (y0 + y1) / 2, 0)
			if not pred or pred(dcf, wn, cu) then
				useWall(K, wn, cu - w / 2 - 0.15, cu + w / 2 + 0.15, y0, y1)
				return wn, dcf, cu
			end
		end
	end
	return nil, nil, nil
end

local function boxHits(list: { any }, mn: Vector3, mx: Vector3): boolean
	for _, r in list do
		if Kit.overlap(mn, mx, r.min, r.max, 0.04) then
			return true
		end
	end
	return false
end

-- K:spot + 벽 부착물 · 천장 매달린 것 · 문짝까지 확인
local function spotX(K: any, pcf: CFrame, size: Vector3, pad: number?, kind: string?): boolean
	local V = K.V
	local p = pad or 0
	local mn, mx = Kit.laabb(pcf * CF(0, size.Y / 2, 0), size + V3(2 * p, 0, 2 * p))
	if boxHits(V.wallItems, mn, mx) or boxHits(V.hang, mn, mx) then
		return false
	end
	for _, r in V.parts do
		if r.door and Kit.overlap(mn, mx, r.min, r.max, 0.04) then
			return false
		end
	end
	return K:spot(pcf, size, pad, kind)
end

-- 계산대 · 진열장 뒤 (뒷벽 쪽 직원 동선)에 걸치나? (뒤 = -Z 쪽, 길이 방향이 X 인 것만)
local function behindService(K: any, pcf: CFrame, size: Vector3): boolean
	local V = K.V
	local mn, mx = Kit.laabb(pcf * CF(0, size.Y / 2, 0), size)
	local boxes = K.behindBoxes
	if not boxes then
		boxes = {}
		for _, g in V.counters do
			if (g.max.X - g.min.X) >= (g.max.Z - g.min.Z) then
				table.insert(boxes, { min = V3(g.min.X - 0.4, 0, V.z0 - 1), max = V3(g.max.X + 0.4, 8, g.min.Z + 0.2) })
			end
		end
		for _, r in V.byName.CaseBase or {} do
			table.insert(boxes, { min = V3(r.min.X - 0.4, 0, V.z0 - 1), max = V3(r.max.X + 0.4, 8, r.min.Z + 0.2) })
		end
		K.behindBoxes = boxes
	end
	return boxHits(boxes, mn, mx)
end

-- 벽에 붙여 세우는 바닥 소품 자리: 폭 w (벽 방향) · 깊이 d · 높이 h. 반환 wn, pcf (+Z = 방 안쪽), u
local function floorFind(K: any, walls: { string }, w: number, d: number, h: number, prefer: any?, opts: any?): (string?, CFrame?, number?)
	local V = K.V
	local o: any = opts or {}
	for _, wn in walls do
		local wall = V.walls[wn]
		if wall then
			local pu = 0
			if type(prefer) == "number" then
				pu = prefer
			elseif type(prefer) == "table" and prefer[wn] then
				pu = prefer[wn]
			end
			local cands = {}
			local u = wall.a + w / 2 + 0.15
			while u <= wall.b - w / 2 - 0.15 do
				table.insert(cands, u)
				u += 0.5
			end
			table.sort(cands, function(a, b)
				return math.abs(a - pu) < math.abs(b - pu)
			end)
			for _, cu in cands do
				breathe(K)
				if not wallBlocked(K, wn, cu - w / 2, cu + w / 2, 0, o.wallH or h) then
					local pcf = V:wall(wn, cu, 0, d / 2 + 0.06)
					if (not o.pred or o.pred(pcf, wn, cu)) and (o.behindOK or not behindService(K, pcf, V3(w, h, d))) and spotX(K, pcf, V3(w, h, d), o.pad or 0.08, o.kind) then
						useWall(K, wn, cu - w / 2 - 0.1, cu + w / 2 + 0.1, 0, (o.wallH or h) + 0.25)
						return wn, pcf, cu
					end
				end
			end
		end
	end
	return nil, nil, nil
end

-- 카운터 손님 쪽 방향 (Props.counterOver 와 같은 규칙)
local function custDir(V: any, g: any): Vector3
	local alongX = (g.max.X - g.min.X) >= (g.max.Z - g.min.Z)
	if alongX then
		local cz = (g.min.Z + g.max.Z) / 2
		return if (V.door and V.door.z or V.z1) > cz then V3(0, 0, 1) else V3(0, 0, -1)
	else
		local cx = (g.min.X + g.max.X) / 2
		return if cx > 0 then V3(-1, 0, 0) else V3(1, 0, 0)
	end
end

-- 카운터 윗면 자리: side = "front" (손님 쪽 끝) | "back" (안쪽 끝) | "mid". 반환 pcf (+Z = 손님 쪽) 또는 nil
local function counterSpot(K: any, g: any, w: number, d: number, h: number, side: string, prefer: number?, pad: number?, inset: number?): CFrame?
	local V = K.V
	local n = custDir(V, g)
	local t = g.top or g
	-- 상판이 벽 속으로 들어간 경우 방 안쪽으로 자름
	local mn = V3(math.max(t.min.X, V.x0 + 0.06), t.min.Y, math.max(t.min.Z, V.z0 + 0.06))
	local mx = V3(math.min(t.max.X, V.x1 - 0.06), t.max.Y, math.min(t.max.Z, V.z1 - 0.06))
	local y = g.y
	local alongX = math.abs(n.Z) > 0.5
	local ins = inset or 0.14
	local lo, hi2, fixed
	if alongX then
		lo, hi2 = mn.X + w / 2 + 0.12, mx.X - w / 2 - 0.12
		local zf = if n.Z > 0 then mx.Z - d / 2 - ins else mn.Z + d / 2 + ins
		local zb = if n.Z > 0 then mn.Z + d / 2 + ins else mx.Z - d / 2 - ins
		fixed = if side == "back" then zb elseif side == "mid" then (mn.Z + mx.Z) / 2 else zf
	else
		lo, hi2 = mn.Z + w / 2 + 0.12, mx.Z - w / 2 - 0.12
		local xf = if n.X > 0 then mx.X - d / 2 - ins else mn.X + d / 2 + ins
		local xb = if n.X > 0 then mn.X + d / 2 + ins else mx.X - d / 2 - ins
		fixed = if side == "back" then xb elseif side == "mid" then (mn.X + mx.X) / 2 else xf
	end
	if hi2 < lo then
		return nil
	end
	local cands = {}
	local s = lo
	while s <= hi2 + 1e-6 do
		table.insert(cands, s)
		s += 0.2
	end
	local pu = prefer or (lo + hi2) / 2
	table.sort(cands, function(a, b)
		return math.abs(a - pu) < math.abs(b - pu)
	end)
	for _, c in cands do
		breathe(K)
		local p = if alongX then V3(c, y, fixed) else V3(fixed, y, c)
		local pcf = facing(p, n)
		if spotX(K, pcf, V3(w, h, d), pad or 0.04) then
			return pcf
		end
	end
	return nil
end

-- 프롬프트를 둘 수 있는 벽 자리인가 (서버 앵커 6.5 밖)
local function promptOK(K: any, half: number?): (CFrame, string, number) -> boolean
	local hw = half or 0.8
	return function(dcf: CFrame)
		for _, dx in { -hw, 0, hw } do
			for _, dy in { -0.5, 0.5 } do
				if not Interact.canPrompt(K, dcf.Position + dcf.XVector * dx + dcf.YVector * dy + dcf.ZVector * 0.25) then
					return false
				end
			end
		end
		return true
	end
end

-- 프롬프트 붙일 벽 자리: 여러 높이 띠를 차례로
local function promptSpot(K: any, walls: { string }, w: number, bands: { { number } }, prefer: any?): (string?, CFrame?, number?)
	local pred = promptOK(K, w / 2)
	for _, wl in walls do
		for _, b in bands do
			local wn, dcf, u = wallFind(K, { wl }, w, b[1], b[2], prefer, pred)
			if wn then
				return wn, dcf, u
			end
		end
	end
	return nil, nil, nil
end

-- 브랜드 카탈로그 -----------------------------------------------------------------------------------------
-- 메뉴 항목 { 이름, 가격, 아이콘? }
local MENUS: { [string]: any } = {}
MENUS.mega = {
	{ "COFFEE", { { "아메리카노", "2,000", "americano" }, { "카페라떼", "3,200", "latte" }, { "바닐라라떼", "3,700", "vanilla" }, { "메가리카노", "3,300", "americano" }, { "헛개리카노", "2,700" }, { "콜드브루", "3,800" } } },
	{ "NON-COFFEE", { { "딸기라떼", "4,000", "strawberry" }, { "녹차라떼", "3,700", "matcha" }, { "고구마라떼", "3,700" }, { "초코라떼", "3,700", "choco" }, { "퐁크러쉬", "4,400" }, { "곡물라떼", "3,500" } } },
	{ "ADE · TEA", { { "레몬에이드", "3,800", "ade" }, { "자몽에이드", "3,800", "grapefruit" }, { "블루레몬에이드", "3,800", "blue" }, { "복숭아아이스티", "3,000", "tea" }, { "유자차", "3,500" }, { "캐모마일", "2,800" } } },
}
MENUS.compose = {
	{ "COFFEE", { { "아메리카노", "1,800", "americano" }, { "카페라떼", "2,900", "latte" }, { "바닐라라떼", "3,300", "vanilla" }, { "돌체라떼", "3,800", "latte" }, { "헤이즐넛라떼", "3,300" }, { "콜드브루", "3,300" } } },
	{ "BEVERAGE", { { "딸기라떼", "3,800", "strawberry" }, { "리얼초코", "3,500", "choco" }, { "녹차라떼", "3,500", "matcha" }, { "요거트스무디", "3,900" }, { "자몽에이드", "3,800", "grapefruit" }, { "복숭아아이스티", "2,800", "tea" } } },
}
MENUS.twosome = {
	{ "COFFEE", { { "아메리카노", "4,700", "americano" }, { "카페라떼", "5,200", "latte" }, { "스페니쉬 연유라떼", "6,200", "vanilla" }, { "바닐라라떼", "5,700" }, { "로얄 밀크티", "5,900", "tea" } } },
	{ "CAKE", { { "아이스박스", "7,500" }, { "스트로베리 레어치즈", "7,500" }, { "떠먹는 티라미수", "6,900" }, { "생크림 카스텔라", "6,500" }, { "마카롱", "3,000" } } },
}
MENUS.pascucci = {
	{ "CAFFÈ", { { "아메리카노", "4,800", "americano" }, { "카페라떼", "5,300", "latte" }, { "카푸치노", "5,300", "latte" }, { "아포가토", "6,500" }, { "카페모카", "5,800", "choco" } } },
	{ "DOLCE", { { "티라미수", "7,000" }, { "젤라또 컵", "5,500" }, { "파니니", "7,500" }, { "크로플", "5,000" }, { "레몬에이드", "6,000", "ade" } } },
}
MENUS.starbucks = {
	{ "ESPRESSO", { { "아메리카노", "4,700" }, { "카페라떼", "5,200" }, { "카라멜 마키아또", "6,100" }, { "돌체라떼", "6,100" }, { "콜드브루", "5,100" } } },
	{ "FRAPPUCCINO · TEA", { { "자바칩 프라푸치노", "6,600" }, { "자몽허니블랙티", "6,100" }, { "유자민트티", "6,100" }, { "딸기 딜라이트 요거트", "6,700" } } },
}
MENUS.roastery = {
	{ "ESPRESSO BAR", { { "에스프레소", "4,000", "americano" }, { "아메리카노", "5,000", "americano" }, { "카페라떼", "5,500", "latte" }, { "플랫화이트", "5,800", "latte" }, { "아인슈페너", "6,500", "vanilla" }, { "콜드브루", "6,000" } } },
	{ "FILTER COFFEE", { { "에티오피아 예가체프 G1", "7,000" }, { "케냐 AA 키리냐가", "7,500" }, { "콜롬비아 게이샤", "12,000" }, { "과테말라 안티구아", "6,500" }, { "디카페인 콜롬비아", "6,500" }, { "오늘의 핸드드립", "6,000" } } },
	{ "BEANS 200g", { { "하우스 블렌드", "16,000" }, { "싱글 오리진", "19,000" }, { "게이샤 100g", "28,000" }, { "드립백 10입", "15,000" }, { "디카페인", "18,000" } } },
}
MENUS.haute = {
	{ "SIGNATURE", { { "오뜨 크림라떼", "7,500", "vanilla" }, { "피스타치오 라떼", "7,500", "matcha" }, { "얼그레이 밀크티", "7,000", "tea" }, { "아메리카노", "5,500", "americano" }, { "로즈 에이드", "7,500", "strawberry" } } },
	{ "PÂTISSERIE", { { "딸기 생크림 케이크", "8,500" }, { "바닐라 밀푀유", "9,000" }, { "마카롱 (1개)", "3,200" }, { "까눌레", "3,800" }, { "바스크 치즈케이크", "7,500" } } },
}
MENUS.busan = {
	{ "051 COFFEE", { { "아메리카노", "4,500", "americano" }, { "카페라떼", "5,000", "latte" }, { "광안 씨솔트라떼", "6,500", "vanilla" }, { "영도 흑임자라떼", "6,500", "choco" }, { "아인슈페너", "6,000" }, { "콜드브루", "5,500" } } },
	{ "NON-COFFEE", { { "해운대 블루에이드", "6,800", "blue" }, { "기장 유자에이드", "6,500", "ade" }, { "흑당 밀크티", "6,000", "tea" }, { "말차라떼", "6,000", "matcha" }, { "바다 소금빵", "3,800" }, { "부산 앙버터", "4,500" } } },
}
MENUS.lounge = {
	{ "COFFEE", { { "아메리카노", "7,000", "americano" }, { "카페라떼", "7,500", "latte" }, { "플랫화이트", "7,500", "latte" }, { "아인슈페너", "8,000" }, { "콜드브루", "7,500" } } },
	{ "TEA · DESSERT", { { "TWG 얼그레이", "8,000", "tea" }, { "캐모마일", "8,000" }, { "애프터눈 티 세트 (2인)", "39,000" }, { "치즈케이크", "9,000" }, { "와인 (글라스)", "12,000" } } },
}
MENUS.indie = {
	{ "COFFEE", { { "아메리카노", "4,500", "americano" }, { "카페라떼", "5,000", "latte" }, { "바닐라빈라떼", "5,500", "vanilla" }, { "플랫화이트", "5,500", "latte" }, { "아인슈페너", "6,000" }, { "핸드드립", "6,500" } } },
	{ "NON-COFFEE", { { "말차라떼", "6,000", "matcha" }, { "딸기라떼", "6,500", "strawberry" }, { "자몽에이드", "6,000", "grapefruit" }, { "얼그레이 밀크티", "6,000", "tea" }, { "레몬 진저티", "5,500" } } },
	{ "BAKE", { { "소금빵", "3,800" }, { "바스크 치즈케이크", "7,000" }, { "휘낭시에", "3,000" }, { "스콘", "3,500" }, { "크로플", "5,500" } } },
}
MENUS.indie2 = {
	{ "COFFEE", { { "아메리카노", "4,800", "americano" }, { "카페라떼", "5,300", "latte" }, { "크림라떼", "6,000", "vanilla" }, { "흑당라떼", "6,000", "choco" }, { "콜드브루", "5,500" }, { "디카페인 +500", "" } } },
	{ "TEA · ADE", { { "청귤에이드", "6,500", "ade" }, { "자몽허니블랙티", "6,000", "grapefruit" }, { "유자민트티", "5,800", "tea" }, { "말차라떼", "6,300", "matcha" }, { "딸기우유", "6,500", "strawberry" } } },
	{ "DESSERT", { { "크로플", "5,800" }, { "티라미수", "7,000" }, { "레몬 파운드", "4,500" }, { "버터바", "4,000" }, { "스모어 쿠키", "4,200" } } },
}
MENUS.indie3 = {
	{ "COFFEE", { { "에스프레소", "4,000", "americano" }, { "아메리카노", "4,500", "americano" }, { "라떼", "5,000", "latte" }, { "오트라떼", "5,800", "latte" }, { "아포가토", "6,500" }, { "핸드드립", "7,000" } } },
	{ "SIGNATURE", { { "바다 크림커피", "6,500", "vanilla" }, { "피스타치오 라떼", "6,800", "matcha" }, { "선셋 에이드", "6,800", "grapefruit" }, { "밀크티", "6,000", "tea" }, { "바닐라빈 쉐이크", "7,000", "vanilla" } } },
}
MENUS.bakery = {
	{ "오늘의 빵", { { "소금빵", "3,500" }, { "크루아상", "4,200" }, { "단팥빵", "2,800" }, { "소보로", "2,800" }, { "우유식빵", "5,500" }, { "바게트", "4,500" }, { "고로케", "3,000" }, { "마늘바게트", "5,000" } } },
	{ "CAKE · DRINK", { { "생크림 케이크 1호", "32,000" }, { "에그타르트", "3,200" }, { "크림치즈 베이글", "4,500" }, { "아메리카노", "3,500", "americano" }, { "카페라떼", "4,000", "latte" }, { "우유 (200ml)", "1,500" } } },
}
MENUS.waffle = {
	{ "WAFFLE", { { "플레인 와플", "3,500" }, { "생크림 와플", "4,500" }, { "누텔라 바나나", "5,500" }, { "젤라또 와플", "6,500" }, { "크로플", "4,500" }, { "애플 시나몬", "5,000" } } },
	{ "GELATO", { { "싱글 컵 · 콘", "4,800" }, { "더블", "6,800" }, { "트리플", "8,800" }, { "파인트 (포장)", "16,000" }, { "아포가토", "6,500", "americano" } } },
}
MENUS.tanghulu = {
	{ "탕후루", { { "딸기 탕후루", "3,500" }, { "샤인머스캣", "4,500" }, { "블루베리", "4,000" }, { "귤 탕후루", "3,000" }, { "키위", "3,500" }, { "방울토마토", "3,000" }, { "파인애플", "3,500" }, { "모둠 (3꼬치)", "9,900" } } },
	{ "GELATO", { { "싱글", "4,800" }, { "더블", "6,800" }, { "트리플", "8,800" }, { "탕후루 젤라또", "6,500" }, { "아이스티", "3,000", "tea" } } },
}
MENUS.bingsu = {
	{ "빙수", { { "우유 눈꽃빙수", "9,900" }, { "애플망고 빙수", "13,900" }, { "인절미 빙수", "10,900" }, { "옛날 팥빙수", "9,500" }, { "생딸기 빙수", "12,900" }, { "초코 브라우니 빙수", "11,500" } } },
	{ "DRINK", { { "아메리카노", "3,500", "americano" }, { "딸기라떼", "5,000", "strawberry" }, { "망고 스무디", "5,500", "ade" }, { "아이스티", "3,000", "tea" } } },
}
MENUS.claw = {
	{ "PLAY", { { "1회", "1,000원" }, { "5회 (+1 보너스)", "5,000원" }, { "10회 (+3 보너스)", "10,000원" } } },
	{ "빙수 · 아이스크림", { { "컵빙수", "4,500" }, { "아이스크림 (낱개)", "1,000~" }, { "음료", "1,500~" } } },
}
MENUS.churros = {
	{ "CHURROS", { { "오리지널 츄러스", "3,000" }, { "시나몬 슈가", "3,000" }, { "초코 딥", "4,000" }, { "츄러스 + 젤라또", "6,500" }, { "미니 츄러스 (6개)", "5,000" } } },
	{ "GELATO", { { "싱글", "4,800" }, { "더블", "6,800" }, { "아이스 초코", "4,500", "choco" } } },
}
MENUS.hotteok = {
	{ "호떡", { { "씨앗호떡", "2,000" }, { "꿀호떡", "1,500" }, { "치즈호떡", "2,500" }, { "녹차씨앗호떡", "2,500" }, { "호떡 아이스크림", "4,000" } } },
	{ "DRINK", { { "식혜", "2,500" }, { "아메리카노", "2,500", "americano" }, { "유자차", "3,000" } } },
}

-- B 필드: title (간판), logo (짧은 로고), slogan, c1 (주색), c2 (짙은색), c3 (강조), paper, ink,
--   menuKind ("lightbox" | "chalk" | "felt" | "brass" | "tv"), menuBg / menuFg / menuAcc, menus,
--   neon = { 글자, 색, 폰트 }, art (벽 그림 종류), wifi, promo, wall = { 벽 이름 = look } (벽 전체 스킨),
--   feat = { selfbar, fridge, md, roaster, ducts, track, pickup, cake, oven, island, hangPlants, claw, tanghulu ... }
local function brandKey(V: any): string
	local n = string.upper(V.name or "")
	local menu = V.menu or ""
	local function has(s: string): boolean
		return string.find(n, s, 1, true) ~= nil
	end
	-- 프랜차이즈 이름이 먼저 (분류가 dessert 로 와도 카페 브랜드)
	if has("STARBUCKS") or has("스타벅스") then
		return "starbucks"
	end
	if has("PASCUCCI") then
		return "pascucci"
	end
	if has("TWOSOME") then
		return "twosome"
	end
	-- 윗층 카페의 1층 엘리베이터 로비 (계산대 없음)
	if V.type == "cafe" and V:has("ElevatorDoor") > 0 and #V.counters == 0 then
		return "lobby"
	end
	if V.type == "dessert" then
		if V:has("ClawBase") > 0 then
			return "claw"
		end
		if has("탕후루") or menu == "tanghulu" then
			return "tanghulu"
		end
		if has("와플") or menu == "waffle" or V:has("WaffleIron") > 0 then
			return "waffle"
		end
		if has("츄러스") or menu == "churros" then
			return "churros"
		end
		if has("호떡") or menu == "hotteok" then
			return "hotteok"
		end
		if V:has("GelatoTub") > 0 then
			return "waffle"
		end
		return "bingsu"
	end
	if V.type == "bakery" then
		return "bakery"
	end
	if has("STARBUCKS") or has("스타벅스") then
		return "starbucks"
	end
	if has("MEGA") then
		return "mega"
	end
	if has("COMPOSE") then
		return "compose"
	end
	if has("TWOSOME") then
		return "twosome"
	end
	if has("PASCUCCI") then
		return "pascucci"
	end
	if has("로스터리") or has("LAB") or has("ROAST") or menu == "roastery" then
		return "roastery"
	end
	if has("HAUTE") then
		return "haute"
	end
	if has("051") then
		return "busan"
	end
	if has("라운지") or has("LOUNGE") or has("HOTEL") or has("15F") or has("씨엘로") then
		return "lounge"
	end
	if menu == "dessertcafe" then
		return "haute"
	end
	local list = { "scandi", "terracotta", "concrete", "ocean", "green" }
	return list[hashStr(V.name or "cafe") % #list + 1]
end

local function brandOf(V: any): any
	local key = brandKey(V)
	local nm = V.name or "CAFE"
	local seed = hashStr((V.key or nm) .. "#")
	local B: any = {
		key = key,
		seed = seed,
		title = nm,
		logo = nm,
		slogan = "SPECIALTY COFFEE",
		c1 = rgb(60, 44, 34),
		c2 = rgb(28, 26, 24),
		c3 = rgb(214, 172, 110),
		paper = rgb(246, 242, 234),
		ink = rgb(30, 28, 26),
		menuKind = "chalk",
		menus = MENUS.indie,
		neon = { "coffee & moments", rgb(255, 196, 120), F.IndieFlower },
		art = "abstract",
		wifi = "CAFE_5G",
		pw = "coffee2026",
		hours = "매일 10:00 - 23:00",
		promo = { "NEW", "딸기 라떼 시즌 한정", "6,500" },
		feat = { selfbar = true, md = true, pickup = true, plants = 2 },
		cup = rgb(250, 250, 248),
	}
	local feat = B.feat
	if key == "mega" then
		B.title, B.logo, B.slogan = "MEGA COFFEE", "MGC", "MEGA SIZE · MEGA VALUE"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(255, 208, 0), rgb(24, 24, 26), rgb(255, 255, 255), rgb(255, 255, 255), rgb(22, 22, 22)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(255, 208, 0), rgb(24, 24, 24), rgb(24, 24, 24)
		B.menus = MENUS.mega
		B.neon = { "MEGA COFFEE", rgb(255, 214, 40), F.GothamBlack }
		B.art, B.wifi, B.pw, B.hours = "pop", "MEGACOFFEE_FREE", "mega2026!", "매일 07:00 - 24:00"
		B.promo = { "NEW", "딸기 퐁크러쉬", "4,400" }
		B.cup = rgb(255, 208, 0)
		B.wall = { left = lk(rgb(246, 246, 242), M.Plaster), right = lk(rgb(246, 246, 242), M.Plaster) }
		B.logoPlate, B.logoFg = Look.black, rgb(255, 208, 0)
		feat.fridge, feat.md, feat.tv = true, false, true
	elseif key == "compose" then
		B.title, B.logo, B.slogan = "COMPOSE COFFEE", "COMPOSE", "BEST QUALITY · BEST PRICE"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(255, 196, 0), rgb(30, 30, 30), rgb(255, 255, 255), rgb(255, 255, 255), rgb(22, 22, 22)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(28, 28, 30), rgb(250, 250, 248), rgb(255, 196, 0)
		B.menus = MENUS.compose
		B.neon = { "COMPOSE COFFEE", rgb(255, 200, 40), F.GothamBlack }
		B.art, B.wifi, B.pw, B.hours = "pop", "COMPOSE_5G", "compose1234", "매일 07:00 - 24:00"
		B.cup = rgb(255, 196, 0)
		B.wall = { left = lk(rgb(40, 40, 42), M.Plaster), right = lk(rgb(40, 40, 42), M.Plaster) }
		B.logoPlate, B.logoFg = Look.black, rgb(255, 196, 0)
		feat.fridge, feat.md, feat.tv = true, false, true
	elseif key == "twosome" then
		B.title, B.logo, B.slogan = "A TWOSOME PLACE", "TWOSOME", "DESSERT CAFE"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(30, 28, 28), rgb(16, 16, 16), rgb(176, 30, 50), rgb(246, 242, 236), rgb(20, 20, 20)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "tv", rgb(18, 18, 18), rgb(244, 240, 232), rgb(220, 60, 80)
		B.menus = MENUS.twosome
		B.neon = { "A TWOSOME PLACE", rgb(255, 240, 230), F.Gotham }
		B.art = "botanical"
		feat.cake, feat.md, feat.fridge = true, false, false
	elseif key == "pascucci" then
		B.title, B.logo, B.slogan = "PASCUCCI", "PASCUCCI", "CAFFÈ ITALIANO DAL 1883"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(150, 32, 40), rgb(48, 30, 24), rgb(214, 180, 120), rgb(244, 236, 222), rgb(40, 28, 22)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "brass", rgb(48, 30, 24), rgb(246, 238, 222), rgb(214, 180, 120)
		B.menus = MENUS.pascucci
		B.neon = { "Pascucci", rgb(255, 220, 170), F.Garamond }
		B.art = "coffee"
		-- 이탈리안 카페: 따뜻한 베이지 회벽 (맵의 흰 벽이 넓은 매장에서 회색으로 죽어 보임)
		B.wall = { back = lk(rgb(236, 224, 206), M.Plaster), left = lk(rgb(236, 224, 206), M.Plaster), right = lk(rgb(236, 224, 206), M.Plaster) }
		feat.fridge = true
	elseif key == "starbucks" then
		B.title, B.logo, B.slogan = "STARBUCKS", "STARBUCKS", "광안리점"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(0, 112, 74), rgb(30, 57, 50), rgb(212, 180, 120), rgb(242, 240, 235), rgb(30, 57, 50)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "chalk", rgb(30, 40, 36), rgb(240, 238, 228), rgb(200, 220, 190)
		B.menus = MENUS.starbucks
		B.neon = { "STARBUCKS COFFEE", rgb(220, 250, 230), F.GothamBold }
		B.art = "coffee"
		B.noCounter = true
		-- 벽: 계산대 뒤 짙은 월넛 패널 대신 따뜻한 원목 · 옆벽 크림 플라스터 (맵의 검은 벽이 너무 어두움)
		B.wall = { back = lk(rgb(112, 80, 54), M.Wood), left = lk(rgb(232, 222, 204), M.Plaster), right = lk(rgb(232, 222, 204), M.Plaster) }
		B.wifi, B.pw, B.hours = "Starbucks_WiFi", "앱에서 연결", "매일 07:00 - 23:00"
		feat.pickup, feat.selfbar, feat.md, feat.plants = false, false, false, 0
	elseif key == "roastery" then
		-- 로고: COFFEE LAB 149 -> LAB, 남천 로스터리 -> 남천 (첫 낱말)
		local first = string.match(nm, "^(%S+)") or nm
		B.title, B.slogan = nm, "SPECIALTY COFFEE ROASTERS"
		local isLab = string.find(string.upper(nm), "LAB", 1, true) ~= nil
		B.logo = if isLab then (string.match(string.upper(nm), "LAB%s*%d+") or "LAB") else first
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(28, 28, 30), rgb(18, 18, 18), rgb(214, 120, 52), rgb(236, 232, 224), rgb(24, 24, 24)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "felt", rgb(26, 26, 28), rgb(240, 240, 236), rgb(240, 160, 90)
		B.menus = MENUS.roastery
		B.neon = { "ROASTING IN PROGRESS", rgb(255, 140, 60), F.Oswald }
		B.art, B.wifi, B.pw, B.hours = "coffee", if isLab then "LAB149_GUEST" else "ROASTERY_GUEST", if isLab then "roast149" else "beans0612", "매일 09:00 - 22:00 · 로스팅 화 · 금"
		B.wall = { left = lk(rgb(168, 98, 76), M.Brick), right = lk(rgb(160, 158, 154), M.Concrete), back = lk(rgb(176, 174, 170), M.Concrete) }
		B.promo = { "THIS WEEK", "에티오피아 게뎁 내추럴", "7,500" }
		feat.roaster, feat.ducts, feat.track, feat.sacks, feat.drip = true, true, true, true, true
	elseif key == "haute" then
		B.title, B.logo, B.slogan = nm, "Haute", "PÂTISSERIE & CAFÉ"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(236, 196, 196), rgb(60, 44, 40), rgb(196, 160, 96), rgb(250, 246, 240), rgb(52, 40, 36)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "brass", rgb(250, 246, 238), rgb(52, 40, 36), rgb(176, 136, 70)
		B.menus = MENUS.haute
		B.neon = { "la vie en rose", rgb(255, 150, 180), F.IndieFlower }
		B.art, B.wifi, B.pw, B.hours = "gallery", "HAUTE_GUEST", "haute0510", "매일 11:00 - 22:00"
		B.promo = { "SEASON", "딸기 밀푀유 출시", "9,800" }
		B.cup = rgb(248, 236, 236)
		B.sofa = rgb(196, 150, 150)
		B.logoFg = rgb(190, 150, 86)
		B.casePanel = lk(rgb(240, 230, 218))
		-- 블러시 핑크 (너무 짙으면 중성광에서 회보라로 죽음): 뒷벽은 조금 진하게, 옆벽은 크림에 가깝게
		B.wall = { back = lk(rgb(250, 230, 224), M.Plaster), left = lk(rgb(250, 242, 236), M.Plaster), right = lk(rgb(250, 242, 236), M.Plaster) }
		feat.cake, feat.md, feat.mirror, feat.flowers = true, false, true, true
	elseif key == "busan" then
		B.title, B.logo, B.slogan = nm, "051", "GWANGALLI · BUSAN"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(30, 74, 140), rgb(18, 34, 64), rgb(250, 196, 60), rgb(246, 246, 242), rgb(22, 36, 60)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(246, 246, 242), rgb(22, 36, 60), rgb(30, 74, 140)
		B.menus = MENUS.busan
		B.neon = { "SEA YOU IN 051", rgb(120, 200, 255), F.FredokaOne }
		B.art, B.wifi, B.pw = "busan", "CAFE051_FREE", "gwangalli051"
		B.promo = { "BUSAN ONLY", "광안 씨솔트라떼", "6,500" }
		B.cup = rgb(240, 246, 252)
		B.wall = { left = lk(rgb(246, 247, 246), M.Plaster), right = lk(rgb(246, 247, 246), M.Plaster), back = lk(rgb(214, 228, 240), M.Plaster) }
		feat.fridge = true
	elseif key == "lounge" then
		B.title, B.logo, B.slogan = nm, "LOUNGE", "COFFEE · TEA · WINE"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(40, 34, 30), rgb(22, 20, 18), rgb(196, 160, 96), rgb(240, 234, 222), rgb(30, 26, 22)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "brass", rgb(30, 28, 26), rgb(240, 232, 216), rgb(206, 170, 106)
		B.menus = MENUS.lounge
		B.neon = { "good evening", rgb(255, 210, 160), F.IndieFlower }
		B.art = "gallery"
		feat.md = false
	elseif key == "lobby" then
		local floorTag = string.match(nm, "(%d+F)") or "15F"
		local cafeName = string.gsub(string.gsub(nm, "%s*·%s*%d+F", ""), "%s+$", "")
		B.title, B.logo, B.slogan = nm, cafeName, floorTag .. " · OCEAN VIEW CAFE & LOUNGE"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(196, 160, 96), rgb(28, 26, 24), rgb(150, 120, 70), rgb(244, 240, 232), rgb(30, 28, 26)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "brass", rgb(30, 28, 26), rgb(240, 232, 216), rgb(206, 170, 106)
		B.menus = {}
		B.neon = { cafeName .. " · " .. floorTag .. " ↑", rgb(255, 214, 160), F.GothamMedium }
		B.art, B.wifi, B.pw, B.hours = "bridge", "LOBBY_FREE", "lobby2026", "매일 10:00 - 23:00 (" .. floorTag .. ")"
		B.info = { "관리사무소\n평일 09:00 - 18:00\n☎ 051-752-0181", "택배 보관 안내\n관리사무소 앞\n무인 택배함 이용", "엘리베이터 정기 점검\n매월 둘째 주 화요일 10:00 - 11:00\n점검 중 계단을 이용해 주세요" }
		feat = { plants = 2, lobby = true }
		B.feat = feat
	elseif key == "bakery" then
		B.title, B.logo, B.slogan = nm, "BAKERY", "매일 아침 직접 굽는 빵"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(150, 96, 52), rgb(60, 40, 28), rgb(232, 176, 60), rgb(250, 244, 230), rgb(52, 36, 24)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "chalk", rgb(36, 40, 36), rgb(244, 240, 228), rgb(246, 210, 120)
		B.menus = MENUS.bakery
		B.neon = { "FRESH BREAD DAILY", rgb(255, 196, 110), F.FredokaOne }
		B.art, B.wifi, B.pw, B.hours = "bread", "BAKERY_GUEST", "bread0707", "매일 07:00 - 22:00"
		-- 맵 벽 (따뜻한 살구색) 이 노란 조명에서 주황으로 타 보여서: 크림 회벽
		B.wall = { left = lk(rgb(248, 242, 230), M.Plaster), right = lk(rgb(248, 242, 230), M.Plaster), back = lk(rgb(242, 234, 220), M.Plaster) }
		B.promo = { "OVEN FRESH", "오늘의 소금빵 나왔어요", "3,500" }
		feat = { oven = true, cake = true, island = true, plants = 1, tongs = true, pickup = false }
		B.feat = feat
		B.casePanel = Look.oak
	elseif key == "waffle" or key == "churros" or key == "hotteok" then
		B.title, B.logo = nm, if key == "waffle" then "WAFFLE" elseif key == "churros" then "CHURROS" else "호떡"
		B.slogan = if key == "waffle" then "WAFFLE & GELATO" elseif key == "churros" then "CHURROS & GELATO" else "부산 명물 씨앗호떡"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(150, 210, 196), rgb(60, 50, 46), rgb(246, 150, 160), rgb(255, 250, 244), rgb(60, 46, 40)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(255, 250, 244), rgb(60, 46, 40), rgb(230, 110, 130)
		B.menus = MENUS[key]
		B.neon = { if key == "waffle" then "sweet waffle" else "sweet & warm", rgb(255, 150, 190), F.FredokaOne }
		B.art, B.wifi, B.pw, B.hours = "pastel", "SWEET_FREE", "gelato777", "매일 11:00 - 23:00"
		B.promo = { "BEST", "젤라또 와플", "6,500" }
		B.cup = rgb(255, 236, 240)
		feat = { freezer = true, plants = 1, gelato = true, fridge = true, cart = if key ~= "waffle" then key else nil }
		B.feat = feat
		B.wall = { back = lk(rgb(252, 234, 238), M.Plaster), left = lk(rgb(250, 248, 243), M.Plaster), right = lk(rgb(250, 248, 243), M.Plaster) }
	elseif key == "tanghulu" then
		B.title, B.logo, B.slogan = nm, "탕후루", "바삭 달콤 과일 탕후루"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(222, 40, 60), rgb(60, 20, 24), rgb(255, 210, 60), rgb(255, 248, 244), rgb(70, 20, 26)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(222, 40, 60), rgb(255, 255, 255), rgb(255, 222, 90)
		B.menus = MENUS.tanghulu
		B.neon = { "탕후루 & 젤라또", rgb(255, 90, 120), F.FredokaOne }
		B.art, B.wifi, B.pw, B.hours = "fruit", "TANGHULU_5G", "sweet2026", "매일 12:00 - 23:00"
		B.promo = { "BEST", "샤인머스캣 탕후루", "4,500" }
		B.cup = rgb(255, 240, 240)
		feat = { tanghulu = true, freezer = true, plants = 2, gelato = true, fruit = true, fridge = true }
		B.feat = feat
	elseif key == "claw" then
		B.title, B.logo, B.slogan = nm, "BINGBING", "인형뽑기 · 빙수"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(255, 80, 170), rgb(30, 22, 48), rgb(80, 230, 255), rgb(255, 240, 250), rgb(30, 22, 48)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "tv", rgb(24, 16, 40), rgb(255, 255, 255), rgb(255, 90, 180)
		B.menus = MENUS.claw
		B.neon = { "BINGBING", rgb(255, 80, 200), F.FredokaOne }
		B.art, B.wifi, B.pw, B.hours = "neon", "BINGBING_FREE", "pickme2026", "24시간 무인 운영"
		feat = { claw = true, plants = 0, freezer = true, leds = true }
		B.feat = feat
	elseif key == "bingsu" then
		B.title, B.logo, B.slogan = nm, "빙수", "눈꽃빙수 전문점"
		B.c1, B.c2, B.c3, B.paper, B.ink = rgb(140, 196, 236), rgb(30, 50, 80), rgb(255, 190, 200), rgb(250, 252, 255), rgb(30, 46, 70)
		B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(250, 252, 255), rgb(30, 46, 70), rgb(70, 140, 210)
		B.menus = MENUS.bingsu
		B.neon = { "snow flake", rgb(150, 220, 255), F.FredokaOne }
		B.art = "pastel"
		feat = { freezer = true, plants = 1 }
		B.feat = feat
	else
		-- 인디 카페 팔레트
		if string.sub(nm, 1, 8) == "SideShop" then
			local names = { "BEACH COFFEE", "바다 커피", "COFFEE STAND", "SURF COFFEE", "카페 파도", "GWANGAN BREW" }
			nm = names[seed % #names + 1]
		end
		B.title, B.logo = nm, nm
		local mv = { MENUS.indie, MENUS.indie2, MENUS.indie3 }
		B.menus = mv[seed % #mv + 1]
		if key == "scandi" then
			B.c1, B.c2, B.c3, B.paper, B.ink = rgb(156, 176, 150), rgb(48, 52, 46), rgb(214, 186, 140), rgb(248, 246, 240), rgb(40, 42, 38)
			B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "felt", rgb(36, 38, 36), rgb(244, 244, 238), rgb(214, 220, 190)
			B.neon = { "slow coffee", rgb(255, 214, 160), F.IndieFlower }
			B.art = "abstract"
			B.wall = { left = lk(rgb(244, 242, 236), M.Plaster), right = lk(rgb(244, 242, 236), M.Plaster), back = lk(rgb(244, 242, 236), M.Plaster) }
			feat.hangPlants = true
		elseif key == "terracotta" then
			B.c1, B.c2, B.c3, B.paper, B.ink = rgb(196, 112, 76), rgb(72, 44, 32), rgb(232, 196, 140), rgb(246, 238, 226), rgb(64, 40, 28)
			B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "chalk", rgb(52, 44, 40), rgb(244, 236, 222), rgb(240, 190, 140)
			B.neon = { "sunny day coffee", rgb(255, 170, 110), F.IndieFlower }
			B.art = "abstract"
			feat.hangPlants = true
		elseif key == "concrete" then
			B.c1, B.c2, B.c3, B.paper, B.ink = rgb(60, 60, 62), rgb(24, 24, 26), rgb(220, 120, 60), rgb(236, 234, 230), rgb(26, 26, 28)
			B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "felt", rgb(26, 26, 28), rgb(240, 240, 236), rgb(240, 150, 90)
			B.neon = { "COFFEE ON THE BEACH", rgb(255, 255, 255), F.Oswald }
			B.art = "coffee"
			B.wall = { left = lk(rgb(150, 148, 144), M.Concrete) }
			feat.ducts, feat.track = true, true
		elseif key == "ocean" then
			B.c1, B.c2, B.c3, B.paper, B.ink = rgb(40, 110, 170), rgb(20, 40, 64), rgb(250, 210, 120), rgb(248, 248, 244), rgb(24, 40, 64)
			B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "lightbox", rgb(248, 248, 244), rgb(24, 40, 64), rgb(40, 110, 170)
			B.neon = { "ocean breeze", rgb(110, 210, 255), F.FredokaOne }
			B.art = "busan"
			B.wall = { left = lk(rgb(246, 247, 246), M.Plaster), right = lk(rgb(246, 247, 246), M.Plaster) }
		else
			B.c1, B.c2, B.c3, B.paper, B.ink = rgb(44, 80, 62), rgb(24, 40, 32), rgb(200, 164, 96), rgb(244, 240, 228), rgb(28, 40, 32)
			B.menuKind, B.menuBg, B.menuFg, B.menuAcc = "brass", rgb(30, 50, 40), rgb(240, 236, 220), rgb(214, 180, 110)
			B.neon = { "green & bean", rgb(170, 255, 190), F.IndieFlower }
			B.art = "botanical"
			feat.hangPlants = true
		end
	end
	B.menuBg = B.menuBg or rgb(34, 36, 34)
	B.menuFg = B.menuFg or rgb(244, 240, 230)
	B.menuAcc = B.menuAcc or B.c3
	return B
end
T.brandOf = brandOf

-- 스타일 (Common 용) -----------------------------------------------------------------------------------
function T.style(V: any): any
	local B = brandOf(V)
	local k = B.key
	local S: any = {
		brand = B,
		chair = { style = "bentwood", frame = Look.walnut, seat = Look.walnut },
		stool = { style = "bar", frame = Look.blackMetal, seat = Look.leatherBrown },
		table = { top = Look.oak, base = Look.blackMetal, barStyle = "steel" },
		counter = { front = "fluted", frontL = Look.oak, topL = Look.marbleWhite, kickL = Look.black, led = rgb(255, 214, 160) },
		ceiling = { skin = Look.white },
		lights = { kind = "downlight", color = Look.warmLight },
		pendant = { shade = "dome", look = Look.blackMetal },
		base = lk(rgb(70, 60, 52)),
		mat = { text = string.upper(B.logo or "WELCOME") },
		plants = { "monstera", "olive", "snake" },
	}
	if k == "mega" or k == "compose" then
		S.chair = { style = "shell", frame = Look.blackMetal, seat = lk(B.c1, M.Plastic) }
		S.stool = { style = "bar", frame = Look.chrome, seat = lk(rgb(30, 30, 30), M.Leather) }
		S.table = { top = Look.white, base = Look.blackMetal, barStyle = "steel", style = "pedestal" }
		S.counter = { front = "panel", frontL = lk(B.c1), topL = Look.white, kickL = Look.black, led = rgb(255, 240, 200) }
		S.floor = { look = lk(rgb(200, 200, 198), M.CeramicTiles), tile = 2.0, grout = lk(rgb(162, 162, 160)) }
		S.lower = { kind = "tile", h = 3.2, look = Look.tileWhite, grout = lk(rgb(206, 204, 200)), walls = { "left", "right" } }
		S.pendant = { shade = "drum", look = lk(B.c1, M.Metal), dia = 1.15 }
		S.lights = { kind = "downlight", color = Look.neutralLight }
		S.base = Look.black
	elseif k == "twosome" then
		S.chair = { style = "padded", frame = Look.blackMetal, seat = Look.leatherBlack }
		S.table = { top = Look.marbleBlack, base = Look.blackMetal, style = "pedestal", barStyle = "steel" }
		S.counter = { front = "fluted", frontL = lk(rgb(32, 30, 30)), topL = Look.marbleWhite, kickL = Look.black, led = rgb(255, 220, 190) }
		S.floor = { look = lk(rgb(120, 96, 76), M.WoodPlanks), tile = 0 }
		S.lower = { kind = "wainscot", h = 3.4, look = lk(rgb(40, 36, 36)), panel = 1.8, walls = { "left", "right" } }
		S.pendant = { shade = "dome", look = Look.blackMetal }
	elseif k == "pascucci" then
		S.chair = { style = "bentwood", frame = Look.darkWood, seat = Look.leatherBrown }
		S.counter = { front = "panel", frontL = lk(rgb(120, 30, 34)), topL = Look.marbleWhite, kickL = Look.darkWood, led = rgb(255, 210, 160) }
		S.lower = { kind = "wainscot", h = 3.4, look = Look.walnut, panel = 1.8, walls = { "left", "right" } }
		S.pendant = { shade = "cone", look = Look.brass }
	elseif k == "starbucks" then
		S.chair = { style = "padded", frame = Look.darkWood, seat = Look.leatherBrown }
		S.table = { top = Look.walnut, base = Look.blackMetal, barStyle = "steel" }
		S.counter = false
		S.floor = { look = lk(rgb(168, 128, 92), M.WoodPlanks), tile = 0 }
		S.lower = { kind = "louver", h = 3.4, look = lk(rgb(136, 98, 66), M.Wood), back = Look.darkWood, walls = { "left", "right" } }
		S.pendant = { shade = "dome", look = lk(rgb(30, 57, 50), M.Metal) }
	elseif k == "roastery" or k == "concrete" then
		S.chair = { style = "shell", frame = Look.blackMetal, seat = Look.plywood }
		S.stool = { style = "cushion", frame = Look.blackMetal, seat = Look.leatherBrown }
		S.table = { top = Look.walnut, base = Look.blackMetal, barStyle = "steel" }
		S.counter = { front = "fluted", frontL = Look.walnut, topL = lk(rgb(64, 64, 66), M.Slate), kickL = Look.black, led = rgb(255, 196, 140) }
		S.floor = { look = Look.polishedConcrete, tile = 4.0, grout = lk(rgb(128, 126, 122)) }
		-- 노출 천장: 낮은 천장(8 미만)은 짙은 색이 답답해서 중간 회색 콘크리트
		S.ceiling = { skin = if V.H < 9 then lk(rgb(164, 162, 158), M.Concrete) else lk(rgb(146, 144, 140), M.Concrete) }
		S.pendant = { shade = "cone", look = Look.blackMetal }
		S.lights = { kind = "downlight", color = Look.warmLight }
		S.base = Look.black
		S.plants = { "snake", "olive" }
	elseif k == "haute" then
		S.chair = { style = "bentwood", frame = Look.walnut, seat = Look.leatherCream }
		S.table = { top = Look.marbleWhite, base = Look.brass, edge = Look.goldMetal, style = "pedestal", barStyle = "steel" }
		S.counter = { front = "fluted", frontL = lk(rgb(240, 232, 220)), topL = Look.marbleWhite, kickL = Look.brass, led = rgb(255, 220, 186) }
		S.floor = { look = lk(rgb(234, 228, 220), M.Marble), tile = 2.5, grout = lk(rgb(204, 196, 184)) }
		S.ceiling = { skin = Look.white, crown = lk(rgb(242, 238, 230)) }
		S.lower = { kind = "wainscot", h = 3.4, look = lk(rgb(242, 236, 226)), cap = lk(rgb(200, 168, 108), M.Metal), panel = 2.2, walls = { "left", "right" } }
		S.pendant = { shade = "globe" }
		S.base = lk(rgb(232, 224, 212))
		S.plants = { "olive", "ficus" }
	elseif k == "busan" or k == "ocean" then
		S.stool = { style = "wood", frame = Look.oak, seat = Look.oak }
		S.chair = { style = "shell", frame = Look.blackMetal, seat = Look.lightOak }
		S.table = { top = Look.lightOak, base = Look.blackMetal, barStyle = "steel" }
		S.counter = { front = "tile", frontL = lk(rgb(36, 80, 146), M.CeramicTiles), topL = Look.terrazzo, kickL = Look.black, led = rgb(220, 236, 255) }
		S.floor = { look = Look.terrazzo, tile = 0 }
		S.lower = { kind = "tile", h = 3.0, look = Look.tileWhite, grout = lk(rgb(96, 136, 186)), walls = { "left", "right" } }
		S.pendant = { shade = "dome", look = lk(rgb(30, 60, 110), M.Metal) }
		S.lights = { kind = "downlight", color = Look.neutralLight }
	elseif k == "lounge" then
		S.chair = { style = "padded", frame = Look.darkWood, seat = Look.fabricNavy }
		S.table = { top = Look.marbleBlack, base = Look.brass, style = "pedestal", barStyle = "steel" }
		S.counter = { front = "marble", frontL = Look.marbleBlack, topL = Look.marbleWhite, kickL = Look.brass, led = rgb(255, 210, 160) }
		S.floor = { look = lk(rgb(92, 66, 48), M.WoodPlanks), tile = 0 }
		S.lower = { kind = "wainscot", h = 3.4, look = Look.walnut, cap = Look.brass, panel = 2.0, walls = { "left", "right" } }
		S.pendant = { shade = "drum", look = Look.fabricBeige }
	elseif k == "scandi" then
		S.chair = { style = "shell", frame = Look.birch, seat = Look.birch }
		S.stool = { style = "wood", frame = Look.birch, seat = Look.birch }
		S.table = { top = Look.birch, base = Look.birch, barStyle = "steel" }
		S.counter = { front = "fluted", frontL = Look.birch, topL = Look.white, kickL = lk(rgb(120, 136, 116)), led = rgb(255, 224, 180) }
		S.floor = { look = lk(rgb(208, 180, 140), M.WoodPlanks), tile = 0 }
		S.lower = { kind = "paint", h = 3.4, look = lk(B.c1), cap = Look.birch, walls = { "left", "right" } }
		S.pendant = { shade = "cone", look = Look.white }
	elseif k == "terracotta" then
		S.chair = { style = "bentwood", frame = Look.oak, seat = Look.rattan }
		S.counter = { front = "tile", frontL = lk(rgb(196, 112, 76), M.CeramicTiles), topL = Look.lightOak, kickL = lk(rgb(90, 56, 40)), led = rgb(255, 200, 150) }
		S.floor = { look = lk(rgb(190, 116, 84), M.CeramicTiles), tile = 1.5, grout = lk(rgb(214, 196, 176)) }
		S.lower = { kind = "paint", h = 3.0, look = lk(rgb(230, 186, 156)), cap = Look.oak, walls = { "left", "right" } }
		S.pendant = { shade = "rattan" }
	elseif k == "green" then
		S.chair = { style = "padded", frame = Look.brass, seat = Look.fabricGreen }
		S.counter = { front = "fluted", frontL = lk(rgb(40, 72, 56)), topL = Look.marbleWhite, kickL = Look.brass, led = rgb(255, 216, 170) }
		S.floor = { look = lk(rgb(150, 112, 80), M.WoodPlanks), tile = 0 }
		S.lower = { kind = "louver", h = 3.4, look = lk(rgb(46, 82, 62), M.Wood), back = lk(rgb(30, 50, 40)), walls = { "left", "right" } }
		S.pendant = { shade = "dome", look = Look.brass }
	elseif k == "bakery" then
		S.chair = { style = "bentwood", frame = Look.oak, seat = Look.oak }
		S.table = { top = Look.marbleWhite, base = Look.blackMetal, style = "pedestal", barStyle = "steel" }
		S.counter = { front = "panel", frontL = Look.oak, topL = Look.marbleWhite, kickL = Look.walnut, led = rgb(255, 214, 160) }
		S.floor = { look = lk(rgb(214, 200, 182), M.CeramicTiles), tile = 2.0, grout = lk(rgb(182, 168, 150)) }
		S.lower = { kind = "tile", h = 3.2, look = Look.tileWhite, grout = lk(rgb(200, 196, 190)), walls = { "left", "right" } }
		S.pendant = { shade = "dome", look = lk(rgb(60, 52, 46), M.Metal) }
		S.base = Look.walnut
		S.plants = { "olive" }
	elseif k == "waffle" or k == "churros" or k == "hotteok" or k == "bingsu" then
		S.chair = { style = "shell", frame = Look.white, seat = lk(B.c3, M.Plastic) }
		S.table = { top = Look.white, base = Look.white, style = "pedestal", barStyle = "steel" }
		S.counter = { front = "fluted", frontL = lk(B.c1), topL = Look.white, kickL = lk(dk(B.c1, 0.4)), led = rgb(255, 230, 220) }
		S.floor = { look = lk(rgb(240, 232, 228), M.Granite), tile = 0 }
		S.lower = { kind = "tile", h = 3.0, look = lk(lt(B.c1, 0.55), M.CeramicTiles), grout = lk(rgb(255, 255, 255)), walls = { "left", "right" } }
		S.pendant = { shade = "globe" }
		S.lights = { kind = "downlight", color = Look.neutralLight }
		S.base = Look.white
		S.plants = { "olive" }
	elseif k == "tanghulu" then
		S.chair = { style = "shell", frame = Look.white, seat = lk(B.c1, M.Plastic) }
		S.table = { top = Look.white, base = Look.white, style = "pedestal", barStyle = "steel" }
		S.counter = { front = "panel", frontL = lk(B.c1), topL = Look.white, kickL = lk(dk(B.c1, 0.5)), led = rgb(255, 230, 220) }
		S.floor = { look = lk(rgb(244, 242, 238), M.CeramicTiles), tile = 2.0, grout = lk(rgb(224, 210, 210)) }
		S.lower = { kind = "tile", h = 3.0, look = Look.tileWhite, grout = lk(rgb(240, 160, 170)), walls = { "left", "right" } }
		S.pendant = { shade = "dome", look = lk(B.c1, M.Metal) }
		S.lights = { kind = "downlight", color = Look.neutralLight }
		S.base = lk(B.c1)
		S.plants = { "olive" }
	elseif k == "lobby" then
		S.chair = { style = "padded", frame = Look.darkWood, seat = Look.leatherBrown }
		S.floor = { look = lk(rgb(226, 222, 214), M.Marble), tile = 3.0, grout = lk(rgb(190, 184, 174)) }
		S.lower = { kind = "wainscot", h = 3.4, look = Look.walnut, cap = Look.brass, panel = 2.4, walls = { "left", "right" } }
		S.pendant = { shade = "globe" }
		S.base = Look.darkWood
		S.plants = { "ficus", "snake", "olive" }
	elseif k == "claw" then
		S.floor = { look = lk(rgb(34, 28, 50), M.Rubber), tile = 2.0, grout = lk(rgb(60, 40, 90)) }
		S.ceiling = { skin = lk(rgb(26, 22, 34)) }
		S.lower = false
		S.lights = { kind = "downlight", color = rgb(240, 230, 255) }
		S.base = lk(rgb(40, 30, 60))
		S.mat = { text = "PICK ME UP!" }
		S.plants = {}
	end
	-- 아랫벽 마감은 뒷벽(손님 쪽 빈 벽 · 계산대 뒤 백스플래시)까지
	if S.lower and S.lower.walls and not table.find(S.lower.walls, "back") then
		S.lower.walls = table.clone(S.lower.walls)
		table.insert(S.lower.walls, "back")
	end
	-- 의자는 이 모듈이 직접 (소파 구분). 벽시계도 직접 (뒷벽은 메뉴판 자리라 옆벽에)
	S.myChair = S.chair
	S.chair = false
	S.clock = false
	return S
end

-- 소품 라이브러리 ----------------------------------------------------------------------------------------

-- 음료 그림 (메뉴판 사진 자리): dcf 표면, s = 높이
local DRINK: { [string]: { Color3 } } = {
	americano = { rgb(52, 30, 18), rgb(86, 52, 30), rgb(30, 30, 30) },
	latte = { rgb(190, 142, 96), rgb(242, 228, 206), rgb(30, 30, 30) },
	vanilla = { rgb(214, 172, 116), rgb(248, 238, 216), rgb(30, 30, 30) },
	strawberry = { rgb(226, 70, 96), rgb(252, 214, 222), rgb(240, 240, 240) },
	matcha = { rgb(112, 156, 72), rgb(228, 238, 206), rgb(30, 30, 30) },
	ade = { rgb(250, 204, 54), rgb(255, 244, 180), rgb(240, 240, 240) },
	grapefruit = { rgb(238, 100, 80), rgb(255, 200, 176), rgb(240, 240, 240) },
	choco = { rgb(86, 52, 34), rgb(200, 164, 132), rgb(30, 30, 30) },
	blue = { rgb(50, 130, 220), rgb(196, 232, 252), rgb(240, 240, 240) },
	tea = { rgb(196, 112, 36), rgb(236, 176, 96), rgb(30, 30, 30) },
}
local function glyph(K: any, dcf: CFrame, s: number, kind: string)
	local c = DRINK[kind] or DRINK.latte
	K:plate("CupGlyph", 0.48 * s, 0.66 * s, 0.01, dcf * CF(0, -0.08 * s, 0), lk(rgb(238, 242, 244)))
	K:plate("CupDrink", 0.42 * s, 0.36 * s, 0.014, dcf * CF(0, -0.22 * s, 0), lk(c[1]))
	K:plate("CupTop", 0.44 * s, 0.2 * s, 0.014, dcf * CF(0, 0.06 * s, 0), lk(c[2]))
	K:plate("CupLid", 0.56 * s, 0.07 * s, 0.018, dcf * CF(0, 0.28 * s, 0), lk(rgb(252, 252, 252)))
	K:plate("CupStraw", 0.045 * s, 0.34 * s, 0.02, dcf * CF(0.07 * s, 0.44 * s, 0) * ANG(0, 0, -0.2), lk(c[3]))
end

-- 메뉴판. st = { kind, bg, fg, acc, frame, font, tfont, icons, sub }. 반환 얼굴 파트
local function menuPanel(K: any, dcf: CFrame, w: number, h: number, title: string?, items: { any }, st: any): BasePart?
	if not room(K, 30) then
		return nil
	end
	local kind = st.kind or "lightbox"
	local bg: Color3, fg: Color3, acc: Color3 = st.bg, st.fg, st.acc
	local lit = kind == "lightbox" or kind == "tv"
	local glow = if lit then (st.glow or 1.0) else nil
	local dep = if kind == "lightbox" then 0.24 elseif kind == "tv" then 0.14 else 0.08
	local frameL = st.frame or (if kind == "chalk" then Look.walnut elseif kind == "brass" then Look.brass elseif kind == "felt" then Look.oak elseif kind == "tv" then Look.black else Look.alu)
	local bw = if kind == "tv" then 0.05 elseif kind == "lightbox" then 0.07 else 0.11
	K:plate("MenuBack", w + 2 * bw, h + 2 * bw, dep, dcf, lk(dk(frameL.c, 0.2), frameL.m))
	local face: BasePart
	if lit then
		face = K:text("MenuFace", w, h, dcf * CF(0, 0, dep), " ", { bg = bg, glow = 0.8, d = 0.02 })
	else
		local fm = if kind == "chalk" then M.Slate elseif kind == "felt" then M.Fabric else M.SmoothPlastic
		face = K:plate("MenuFace", w, h, 0.02, dcf * CF(0, 0, dep), lk(bg, fm))
	end
	local fz = dep + 0.025
	-- 테두리 (프레임 립)
	local lipD = if lit then 0.035 else 0.06
	K:plate("MenuLip", w + 2 * bw, bw, fz - dep + lipD, dcf * CF(0, h / 2 + bw / 2, dep), frameL)
	K:plate("MenuLip", w + 2 * bw, bw, fz - dep + lipD, dcf * CF(0, -h / 2 - bw / 2, dep), frameL)
	K:plate("MenuLip", bw, h, fz - dep + lipD, dcf * CF(-w / 2 - bw / 2, 0, dep), frameL)
	K:plate("MenuLip", bw, h, fz - dep + lipD, dcf * CF(w / 2 + bw / 2, 0, dep), frameL)
	local y = h / 2 - 0.12
	if title then
		local th = math.clamp(h * 0.13, 0.3, 0.62)
		K:text("MenuTitle", w * 0.86, th, dcf * CF(0, y - th / 2, fz), title, { fg = acc, glow = glow, font = st.tfont or F.GothamBlack })
		y -= th + 0.07
		K:plate("MenuRule", w * 0.86, 0.03, 0.006, dcf * CF(0, y, fz + (if lit then 0.05 else -0.003)), lk(acc))
		y -= 0.08
	end
	local icons = {}
	for _, it in items do
		if it[3] and #icons < 4 then
			table.insert(icons, it[3])
		end
	end
	local iconH = if st.icons ~= false and #icons > 0 and h >= 2.4 and w >= 2.0 then math.min(0.95, h * 0.24) else 0
	local bottom = -h / 2 + 0.1 + iconH
	local n = #items
	local rh = math.min(0.46, (y - bottom) / math.max(1, n))
	-- 이름 열 · 가격 열을 각각 한 글자판으로 (줄 높이 고정 = 행 맞춤, SurfaceGui 수 절약)
	local names, prices = {}, {}
	for _, it in items do
		table.insert(names, it[1])
		table.insert(prices, if it[2] and it[2] ~= "" then it[2] else " ")
	end
	local colH = rh * n
	local colY = y - colH / 2
	-- 글자 높이 (스터드): 행 높이의 56%, 가장 긴 이름이 열 폭에 들어가게
	local maxLen = 1
	for _, nm in names do
		maxLen = math.max(maxLen, utf8.len(nm) or #nm)
	end
	local nameW = w * 0.62
	local tsStud = math.min(rh * 0.56, nameW / (maxLen * 0.95))
	local function column(name: string, cw: number, cx: number, text: string, color: Color3, align: string, font: any)
		local p, lab = K:text(name, cw, colH, dcf * CF(cx, colY, fz), text, { fg = color, glow = glow, align = align, font = font })
		local g = p:FindFirstChildWhichIsA("SurfaceGui")
		local ppx = if g then g.PixelsPerStud else 40
		lab.TextScaled = false
		lab.TextSize = math.max(8, math.floor(tsStud * ppx))
		lab.LineHeight = rh / tsStud
		return lab
	end
	column("MenuItems", nameW, -w * 0.43 + w * 0.31, table.concat(names, "\n"), fg, "Left", st.font or F.GothamMedium)
	column("MenuPrices", w * 0.26, w * 0.43 - w * 0.13, table.concat(prices, "\n"), acc, "Right", F.GothamBold)
	if not lit and hi(K) and kind ~= "felt" then
		for i = 1, n - 1 do
			local ry = y - rh * i
			K:plate("MenuDots", w * 0.86, 0.012, 0.004, dcf * CF(0, ry, fz - 0.004), lk(dk(bg:Lerp(fg, 0.35), 0.1)))
		end
	end
	if iconH > 0 then
		for i, ik in icons do
			local x = -w / 2 + w * (i - 0.5) / #icons
			glyph(K, dcf * CF(x, -h / 2 + 0.08 + iconH / 2, fz + (if lit then 0.05 else -0.004)), iconH * 0.92, ik)
		end
	end
	if st.sub then
		K:text("MenuSub", w * 0.8, 0.16, dcf * CF(0, -h / 2 + 0.1, fz), st.sub, { fg = dk(fg, 0.15), glow = glow, font = F.Gotham })
	end
	return face
end

-- 네온 사인 (아크릴 판 + 빛나는 글자 + 스탠드오프). 반환 sign 표 (켜기/끄기용)
local function neonSign(K: any, dcf: CFrame, w: number, h: number, text: string, c: Color3, font: any?, backer: boolean?): any
	if backer ~= false then
		K:plate("NeonBacker", w + 0.36, h + 0.26, 0.05, dcf * CF(0, 0, 0.1), glassL(rgb(36, 36, 42), 0.5))
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				K:cyl("NeonStandoff", 0.12, 0.08, dcf * CF(sx * (w / 2 + 0.06), sy * (h / 2 + 0.02), 0.06) * ANG(0, PI / 2, 0), Look.chrome)
			end
		end
	end
	local p, lab = K:text("NeonText", w, h, dcf * CF(0, 0, 0.16), text, { fg = c, glow = 2.1, font = font or F.FredokaOne })
	local light = K:light(p, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 8, Brightness = 0.7, Angle = 120, Color = c })
	return { part = p, label = lab, light = light, color = c }
end

local function neonToggle(K: any, sign: any, object: string, at: BasePart?)
	local p: BasePart? = at or sign.part
	if not p or p.Parent == nil then
		return
	end
	local gui = sign.part and sign.part:FindFirstChildWhichIsA("SurfaceGui")
	Interact.toggle(K, p :: BasePart, {
		object = object,
		onText = "끄기",
		offText = "켜기",
		state = true,
		on = function(state: boolean)
			if sign.label then
				sign.label.TextColor3 = if state then sign.color else dk(sign.color, 0.6)
			end
			if gui then
				gui.Brightness = if state then 2.1 else 1
				gui.LightInfluence = if state then 0 else 1
			end
			if sign.light then
				sign.light.Enabled = state
			end
			for _, t in sign.tubes or {} do
				if t.Parent then
					t.Material = if state then M.Neon else M.SmoothPlastic
				end
			end
		end,
	})
end

-- 스피커 한 쌍 + 앰프 (BGM 바꾸기 + 이퀄라이저 깜빡임)
local PLAYLIST = { "Lo-fi Beach Jazz", "City Pop 1984", "Bossa Nova Café", "K-Indie Acoustic", "Rainy Day Piano", "광안리 Sunset Mix", "OFF" }
local function speaker(K: any, dcf: CFrame)
	if not room(K, 5) then
		return
	end
	K:plate("SpeakerMount", 0.3, 0.3, 0.12, dcf * CF(0, 0.2, 0), Look.blackMetal)
	K:plate("SpeakerBox", 0.62, 0.98, 0.5, dcf * CF(0, 0, 0.12), Look.of(28, 28, 30, Enum.Material.SmoothPlastic))
	wdisc(K, "SpeakerWoofer", 0.42, 0.03, dcf * CF(0, -0.15, 0.62), Look.of(50, 50, 54, Enum.Material.Fabric))
	wdisc(K, "SpeakerTweeter", 0.16, 0.03, dcf * CF(0, 0.28, 0.62), Look.of(60, 60, 64, Enum.Material.Metal))
end

local function musicPanel(K: any, dcf: CFrame, B: any, compact: boolean?)
	local sc = if compact then 0.72 else 1.0
	K:plate("AmpBody", 1.4 * sc, 0.8, 0.22, dcf, Look.of(34, 34, 36, Enum.Material.Metal))
	K:plate("AmpFace", 1.3 * sc, 0.68, 0.02, dcf * CF(0, 0, 0.22), Look.black)
	local scr, lab = K:text("AmpScreen", 0.84 * sc, 0.24, dcf * CF(-0.14 * sc, 0.13, 0.245), "♪ " .. PLAYLIST[1], { fg = rgb(140, 230, 255), bg = rgb(10, 16, 24), glow = 1.2, font = F.Code, d = 0.01 })
	K:cyl("AmpKnob", 0.08, 0.24 * sc, dcf * CF(0.46 * sc, 0.06, 0.28) * ANG(0, PI / 2, 0), Look.chrome)
	K:text("AmpBrand", 0.5 * sc, 0.08, dcf * CF(-0.3 * sc, -0.27, 0.245), "STREAMER · AMP", { fg = rgb(160, 160, 160), font = F.Gotham, d = 0.005 })
	local bars = {}
	local base = {}
	for i = 1, 7 do
		local x = (-0.42 + i * 0.085) * sc
		local b = K:plate("AmpLED", 0.06, 0.1, 0.012, dcf * CF(x, -0.12, 0.245), Look.neon(if i > 5 then rgb(255, 90, 60) else rgb(80, 230, 140)))
		bars[i] = b
		base[i] = K.cf * dcf * CF(x, -0.17, 0.251)
	end
	local playing = true
	Interact.cycle(K, scr, PLAYLIST, {
		action = "BGM 바꾸기",
		object = "매장 음악",
		on = function(_i: number, item: string)
			playing = item ~= "OFF"
			lab.Text = if playing then "♪ " .. item else "■ BGM OFF"
		end,
	})
	Interact.anim(K, function(t: number)
		for i, b in bars do
			if b.Parent then
				local hgt = if playing then 0.03 + 0.17 * math.abs(math.sin(t * (2.1 + i * 0.37) + i * 1.3)) else 0.02
				b.Size = V3(0.06, hgt, 0.012)
				b.CFrame = base[i] * CF(0, hgt / 2, 0)
			end
		end
	end)
	return scr
end

-- 안내판 (아크릴 + 글자)
local function notice(K: any, dcf: CFrame, w: number, h: number, text: string, fg: Color3, bg: Color3, font: any?)
	K:plate("NoticeBack", w + 0.08, h + 0.08, 0.02, dcf, lk(dk(bg, 0.25)))
	K:text("Notice", w, h, dcf * CF(0, 0, 0.02), text, { fg = fg, bg = bg, d = 0.02, font = font or F.GothamMedium })
	if hi(K) then
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				wdisc(K, "NoticeScrew", 0.06, 0.02, dcf * CF(sx * (w / 2 - 0.06), sy * (h / 2 - 0.06), 0.04), Look.chrome)
			end
		end
	end
end

-- 안내 보드 (코르크 + 꽂힌 종이 3장: 와이파이 · 영업시간 · 결제 안내)
local function infoBoard(K: any, dcf: CFrame, B: any)
	if not room(K, 14) then
		return
	end
	local w, h = 1.9, 2.3
	K:plate("InfoBoardFrame", w + 0.14, h + 0.14, 0.06, dcf, Look.oak)
	K:plate("InfoBoardCork", w, h, 0.07, dcf, lk(rgb(178, 136, 92), M.Sand))
	local z = 0.075
	K:text("InfoWifi", 0.86, 0.95, dcf * CF(-0.44, 0.56, z) * ANG(0, 0, 0.03), (B.info and B.info[1]) or ("Wi-Fi\n" .. B.wifi .. "\nPW " .. B.pw), { fg = rgb(30, 30, 34), bg = rgb(252, 252, 250), d = 0.01, font = F.GothamMedium })
	K:text("InfoHours", 0.86, 0.95, dcf * CF(0.47, 0.6, z) * ANG(0, 0, -0.04), (B.info and B.info[2]) or ("영업시간\n" .. B.hours .. "\n라스트오더 30분 전"), { fg = rgb(40, 34, 30), bg = rgb(255, 244, 196), d = 0.01, font = F.GothamMedium })
	K:text("InfoPay", 1.6, 0.8, dcf * CF(0, -0.55, z) * ANG(0, 0, 0.015), (B.info and B.info[3]) or "카드 · 삼성페이 · 카카오페이 · 제로페이\n현금영수증 발행 가능\n1인 1음료 부탁드려요 :)", { fg = rgb(30, 30, 30), bg = rgb(240, 244, 248), d = 0.01, font = F.GothamMedium })
	for _, p in { V3(-0.44, 0.98, 0), V3(0.47, 1.02, 0), V3(-0.6, -0.2, 0), V3(0.6, -0.2, 0) } do
		K:ball("InfoPin", 0.08, dcf * CF(p.X, p.Y, z + 0.03), lk(if p.Y > 0 then rgb(220, 40, 40) else rgb(40, 110, 220)))
	end
end

-- 벽 그림 --------------------------------------------------------------------------------------------
local function artPiece(K: any, dcf: CFrame, w: number, h: number, kind: string, B: any, idx: number)
	if not room(K, 34) then
		return
	end
	local seed = B.seed + idx * 17
	local frameL = if B.key == "haute" or B.key == "lounge" or B.key == "pascucci" then Look.goldMetal elseif B.key == "scandi" or B.key == "terracotta" or B.key == "bakery" then Look.oak else Look.blackMetal
	local mat = Look.paper
	if kind == "bridge" or kind == "neon" then
		mat = lk(rgb(20, 24, 48))
	elseif kind == "pop" then
		mat = lk(B.c1)
	elseif kind == "botanical" then
		mat = lk(rgb(236, 230, 214))
	end
	Props.frame(K, dcf, w, h, { frame = frameL, mat = mat, border = 0.08, depth = 0.08 })
	local iw, ih = w - 0.32, h - 0.32
	local z = 0.049
	local function blk(nm: string, x: number, y: number, bw: number, bh: number, c: Color3, rot: number?)
		K:plate(nm, iw * bw, ih * bh, 0.005, dcf * CF(iw * (x - 0.5), ih * (y - 0.5), z) * ANG(0, 0, rot or 0), lk(c))
	end
	if kind == "bridge" then
		-- 광안대교 야경: 하늘 띠 · 바다 · 상판 · 주탑 2 · 케이블 · 불빛
		blk("ArtSky", 0.5, 0.82, 1, 0.36, rgb(56, 46, 104))
		blk("ArtSky", 0.5, 0.6, 1, 0.12, rgb(150, 80, 120))
		blk("ArtSea", 0.5, 0.2, 1, 0.4, rgb(14, 30, 64))
		blk("ArtDeck", 0.5, 0.42, 1, 0.025, rgb(220, 226, 236))
		for _, tx in { 0.3, 0.7 } do
			blk("ArtTower", tx, 0.6, 0.018, 0.4, rgb(230, 236, 246))
			for k = 1, 4 do
				local dx = 0.05 * k
				for _, sgn in { -1, 1 } do
					local x0, y0 = tx, 0.8
					local x1, y1 = tx + sgn * dx * 1.6, 0.43
					local len = math.sqrt(((x1 - x0) * iw) ^ 2 + ((y1 - y0) * ih) ^ 2)
					local ang = math.atan2((y1 - y0) * ih, (x1 - x0) * iw)
					K:plate("ArtCable", len, 0.012, 0.004, dcf * CF(iw * ((x0 + x1) / 2 - 0.5), ih * ((y0 + y1) / 2 - 0.5), z) * ANG(0, 0, ang), lk(rgb(200, 210, 230)))
				end
			end
		end
		local cols = { rgb(255, 90, 160), rgb(90, 200, 255), rgb(255, 220, 90), rgb(160, 120, 255) }
		for k = 0, 7 do
			blk("ArtLight", 0.06 + k * 0.125, 0.405, 0.05, 0.012, cols[k % 4 + 1])
		end
		blk("ArtReflect", 0.5, 0.3, 0.9, 0.01, rgb(90, 120, 190))
		K:disc("ArtMoon", ih * 0.12, 0.005, dcf * CF(iw * 0.32, ih * 0.38, z) * ANG(PI / 2, 0, 0), lk(rgb(250, 240, 210)))
	elseif kind == "pop" then
		K:text("ArtPopTitle", iw * 0.9, ih * 0.22, dcf * CF(0, ih * 0.34, z + 0.002), if rnd(seed, 1) > 0.5 then "ICE\nAMERICANO" else "BIG SIZE\nLATTE", { fg = B.c2 or BLACK, font = F.GothamBlack })
		glyph(K, dcf * CF(0, -ih * 0.08, z + 0.002), ih * 0.42, if rnd(seed, 2) > 0.5 then "americano" else "latte")
		K:text("ArtPopPrice", iw * 0.7, ih * 0.14, dcf * CF(0, -ih * 0.38, z + 0.002), B.promo[3] .. "원~", { fg = B.c2 or BLACK, font = F.GothamBlack })
	elseif kind == "botanical" then
		local stems = 2 + math.floor(rnd(seed, 3) * 2)
		for sI = 1, stems do
			local x = 0.25 + (sI - 1) * 0.5 / math.max(1, stems - 1)
			blk("ArtStem", x, 0.45, 0.008, 0.7, rgb(80, 104, 70), (sI - 2) * 0.12)
			for lI = 1, 4 do
				local ly = 0.25 + lI * 0.14
				local side = if lI % 2 == 0 then 1 else -1
				K:ell("ArtLeaf", V3(iw * 0.16, ih * 0.06, 0.01), dcf * CF(iw * (x - 0.5) + side * iw * 0.07, ih * (ly - 0.5), z + 0.004) * ANG(0, 0, side * 0.5), lk(if lI % 2 == 0 then rgb(96, 130, 84) else rgb(130, 160, 100)))
			end
		end
	elseif kind == "coffee" then
		K:text("ArtTitle", iw * 0.86, ih * 0.14, dcf * CF(0, ih * 0.38, z + 0.002), if rnd(seed, 4) > 0.5 then "SINGLE ORIGIN" else "FROM SEED TO CUP", { fg = rgb(40, 32, 26), font = F.Oswald })
		for k = 0, 5 do
			local bx, by = 0.22 + (k % 3) * 0.28, 0.48 - math.floor(k / 3) * 0.24
			K:ell("ArtBean", V3(iw * 0.16, ih * 0.13, 0.02), dcf * CF(iw * (bx - 0.5), ih * (by - 0.5), z + 0.006) * ANG(0, 0, 0.5 + k * 0.4), lk(rgb(92 + k * 6, 58, 36)))
			blk("ArtBeanLine", bx, by, 0.012, 0.11, rgb(50, 30, 20), 0.5 + k * 0.4)
		end
		K:text("ArtOrigin", iw * 0.86, ih * 0.12, dcf * CF(0, -ih * 0.4, z + 0.002), "ETHIOPIA · KENYA · COLOMBIA · GUATEMALA", { fg = rgb(90, 70, 56), font = F.Gotham })
	elseif kind == "bread" then
		K:text("ArtTitle", iw * 0.86, ih * 0.15, dcf * CF(0, ih * 0.37, z + 0.002), "BOULANGERIE", { fg = rgb(90, 56, 30), font = F.Garamond })
		for k = 0, 2 do
			K:ell("ArtBaguette", V3(iw * 0.7, ih * 0.08, 0.02), dcf * CF(0, ih * (0.12 - k * 0.15), z + 0.006) * ANG(0, 0, 0.12 - k * 0.12), lk(rgb(200, 140, 64)))
		end
		K:text("ArtSub", iw * 0.8, ih * 0.1, dcf * CF(0, -ih * 0.4, z + 0.002), "PAIN · CROISSANT · BRIOCHE", { fg = rgb(120, 90, 60), font = F.Gotham })
	elseif kind == "pastel" or kind == "fruit" then
		-- 아이스크림 콘 / 딸기 일러스트
		if kind == "fruit" then
			K:ell("ArtBerry", V3(iw * 0.5, ih * 0.5, 0.02), dcf * CF(0, -ih * 0.05, z + 0.006), lk(rgb(226, 40, 60)))
			for k = 0, 2 do
				K:ell("ArtBerryLeaf", V3(iw * 0.16, ih * 0.07, 0.02), dcf * CF((k - 1) * iw * 0.11, ih * 0.22, z + 0.01) * ANG(0, 0, (k - 1) * 0.5), lk(rgb(60, 150, 60)))
			end
			for k = 0, 8 do
				blk("ArtSeed", 0.36 + (k % 3) * 0.14, 0.32 + math.floor(k / 3) * 0.13, 0.025, 0.04, rgb(255, 230, 120))
			end
		else
			K:wedge("ArtCone", V3(0.004, ih * 0.42, iw * 0.3), dcf * CF(0, -ih * 0.2, z + 0.004) * ANG(0, PI / 2, PI), lk(rgb(214, 160, 90)))
			local sc = { rgb(250, 200, 210), rgb(190, 230, 210), rgb(250, 236, 180) }
			for k = 1, 3 do
				K:disc("ArtScoop", iw * 0.34, 0.005, dcf * CF((k - 2) * iw * 0.08, ih * (0.02 + k * 0.1), z + 0.004 + k * 0.001) * ANG(PI / 2, 0, 0), lk(sc[k]))
			end
		end
		K:text("ArtTitle", iw * 0.86, ih * 0.13, dcf * CF(0, ih * 0.4, z + 0.012), if kind == "fruit" then "SWEET & CRUNCHY" else "HAPPY SCOOPS", { fg = dk(B.c1, 0.3), font = F.FredokaOne })
	elseif kind == "busan" then
		K:text("ArtTitle", iw * 0.8, ih * 0.22, dcf * CF(0, ih * 0.3, z + 0.002), "BUSAN\n051", { fg = rgb(24, 50, 100), font = F.GothamBlack })
		for k = 0, 2 do
			K:ring("ArtWave", dcf * CF(iw * (k * 0.3 - 0.3), -ih * 0.32, z + 0.006), iw * 0.13, 0.025, 6, lk(rgb(50, 120, 200)), 0, PI)
		end
		blk("ArtSea", 0.5, 0.08, 1, 0.16, rgb(60, 140, 210))
		for k = 0, 1 do
			blk("ArtGull", 0.65 + k * 0.12, 0.52 + k * 0.06, 0.07, 0.012, rgb(40, 40, 50), 0.4)
			blk("ArtGull", 0.7 + k * 0.12, 0.52 + k * 0.06, 0.07, 0.012, rgb(40, 40, 50), -0.4)
		end
	elseif kind == "gallery" then
		-- 흑백 사진 느낌 (바다 · 수평선 · 인물 실루엣)
		blk("ArtPhoto", 0.5, 0.65, 1, 0.7, rgb(190, 190, 186))
		blk("ArtPhoto", 0.5, 0.18, 1, 0.36, rgb(110, 112, 114))
		blk("ArtHorizon", 0.5, 0.36, 1, 0.01, rgb(240, 240, 238))
		blk("ArtFigure", 0.62 + rnd(seed, 6) * 0.15, 0.32, 0.03, 0.14, rgb(40, 40, 42))
		K:disc("ArtSun", ih * 0.16, 0.005, dcf * CF(-iw * 0.2, ih * 0.15, z + 0.004) * ANG(PI / 2, 0, 0), lk(rgb(236, 236, 232)))
	else
		-- abstract: 원 · 사각 · 아치 (미드센추리)
		local pal = { B.c1, B.c3, lt(B.c2, 0.3), rgb(226, 160, 96), rgb(150, 170, 140) }
		for k = 1, 3 do
			local d = ih * (0.22 + rnd(seed, k) * 0.25)
			K:disc("ArtCircle", d, 0.006, dcf * CF(iw * (rnd(seed, k + 10) - 0.5) * 0.6, ih * (rnd(seed, k + 20) - 0.5) * 0.5, z + 0.002 + k * 0.001) * ANG(PI / 2, 0, 0), lk(pal[(k + idx) % #pal + 1]))
		end
		blk("ArtBlock", 0.3 + rnd(seed, 30) * 0.4, 0.2, 0.3, 0.3, pal[(idx + 3) % #pal + 1])
		K:ring("ArtArc", dcf * CF(0, -ih * 0.2, z + 0.008), iw * 0.25, 0.03, 8, lk(B.c2), 0, PI)
	end
end

-- 바닥 소품 ------------------------------------------------------------------------------------------------

-- 셀프바 (빨대 · 냅킨 · 시럽 · 뚜껑 · 퇴식구). pcf 바닥, +Z = 손님 쪽. w 폭 (깊이 1.5)
local function selfBar(K: any, pcf: CFrame, w: number, B: any)
	local d, h = 1.5, 3.1
	local body = if B.key == "mega" or B.key == "compose" then Look.white elseif B.key == "roastery" or B.key == "concrete" then Look.of(40, 40, 42, Enum.Material.Metal) else Look.offWhite
	local topL = if B.key == "haute" or B.key == "lounge" then Look.marbleWhite elseif B.key == "mega" or B.key == "compose" then Look.of(60, 60, 62, Enum.Material.Slate) else Look.oak
	K:box("SelfBarKick", V3(w - 0.12, 0.3, d - 0.2), pcf * CF(0, 0.15, -0.06), Look.black)
	K:box("SelfBarBody", V3(w, h - 0.42, d), pcf * CF(0, 0.3 + (h - 0.42) / 2, 0), body)
	K:box("SelfBarTop", V3(w + 0.1, 0.12, d + 0.08), pcf * CF(0, h - 0.06, 0.03), topL)
	-- 문짝 + 손잡이
	local nd = math.max(2, math.floor(w / 1.1))
	local dw = (w - 0.1) / nd
	for i = 1, nd do
		local x = -w / 2 + 0.05 + dw * (i - 0.5)
		K:box("SelfBarDoor", V3(dw - 0.06, h - 0.62, 0.04), pcf * CF(x, 0.32 + (h - 0.62) / 2, d / 2 + 0.02), lk(dk((body :: any).c, 0.05), (body :: any).m))
		if i < nd then
			K:box("SelfBarHandle", V3(0.05, 0.6, 0.06), pcf * CF(x + dw / 2 - 0.16, h - 0.75, d / 2 + 0.07), Look.brushed)
		end
	end
	-- 퇴식구 (오른쪽 문: 동그란 투입구 + 글자)
	local rx = w / 2 - 0.05 - dw / 2
	K:cyl("SelfBarSlot", 0.06, 0.6, pcf * CF(rx, h - 0.85, d / 2 + 0.05) * ANG(0, PI / 2, 0), Look.black)
	K:text("SelfBarSlotLabel", dw * 0.8, 0.22, pcf * CF(rx, h - 1.38, d / 2 + 0.045), "일반쓰레기 · 컵 투입구", { fg = rgb(60, 60, 60), font = F.GothamMedium, d = 0.01 })
	local y = h
	-- 음료 버리는 곳 (스테인리스 싱크 + 그레이트)
	local sx = w / 2 - 0.65
	K:box("SelfBarSink", V3(0.95, 0.04, 0.95), pcf * CF(sx, y + 0.02, -0.05), Look.steel)
	for k = -2, 2 do
		K:box("SelfBarGrate", V3(0.85, 0.03, 0.04), pcf * CF(sx, y + 0.045, -0.05 + k * 0.17), Look.chrome)
	end
	-- 빨대 디스펜서
	local px = -w / 2 + 0.4
	K:box("StrawBox", V3(0.44, 0.8, 0.34), pcf * CF(px, y + 0.4, -0.25), glassL(rgb(236, 240, 242), 0.55))
	K:box("StrawBoxBase", V3(0.48, 0.1, 0.38), pcf * CF(px, y + 0.05, -0.25), Look.black)
	for k = 0, 4 do
		K:vcyl("Straw", 0.75, 0.04, pcf * CF(px - 0.14 + k * 0.07, y + 0.45, -0.25 + (k % 2) * 0.06) * ANG(0.1 * (k - 2), 0, 0.06 * (k - 2)), lk(if k % 2 == 0 then rgb(250, 250, 250) else rgb(30, 30, 30)))
	end
	-- 냅킨 꽂이 · 물티슈
	px += 0.62
	K:box("NapkinHolder", V3(0.52, 0.4, 0.34), pcf * CF(px, y + 0.2, -0.2), Look.brushed)
	K:box("NapkinStack", V3(0.44, 0.08, 0.28), pcf * CF(px, y + 0.43, -0.2), Look.paper)
	-- 시럽 펌프 2
	for k = 0, 1 do
		local bx = px + 0.55 + k * 0.4
		K:vcyl("SyrupBottle", 0.75, 0.3, pcf * CF(bx, y + 0.375, -0.3), lk(if k == 0 then rgb(170, 110, 50) else rgb(230, 220, 200), M.Glass, { t = 0.2 }))
		K:vcyl("SyrupPump", 0.24, 0.12, pcf * CF(bx, y + 0.87, -0.3), Look.black)
		K:box("SyrupNozzle", V3(0.05, 0.05, 0.22), pcf * CF(bx, y + 0.98, -0.2), Look.black)
		K:text("SyrupLabel", 0.26, 0.16, pcf * CF(bx, y + 0.35, -0.149), if k == 0 then "시럽" else "헤이즐넛", { fg = rgb(40, 40, 40), bg = rgb(250, 250, 246), d = 0.01, font = F.GothamBold })
	end
	-- 뚜껑 · 컵 슬리브
	local lx = px + 1.42
	if lx < sx - 0.7 then
		K:vcyl("LidStack", 0.32, 0.38, pcf * CF(lx, y + 0.16, 0.1), lk(rgb(250, 250, 250), M.Glass, { t = 0.25 }))
		K:vcyl("SleeveStack", 0.42, 0.34, pcf * CF(lx, y + 0.21, -0.35), Look.kraft)
	end
	-- 뒤판 + 안내
	K:plate("SelfBarSplash", w, 1.45, 0.04, pcf * CF(0, y + 0.725, -d / 2 + 0.0) * CF(0, 0, -0.06), lk(dk(topL.c, 0.06), topL.m))
	K:text("SelfBarSign", w * 0.8, 0.32, pcf * CF(0, y + 1.22, -d / 2 + 0.0), "SELF BAR  빨대 · 냅킨 · 시럽", { fg = B.ink, bg = B.paper, d = 0.02, font = F.GothamBold })
	K:text("SelfBarSink", 0.9, 0.18, pcf * CF(sx, y + 0.28, -d / 2 + 0.01), "남은 음료 · 얼음 버리는 곳", { fg = rgb(255, 255, 255), bg = rgb(50, 120, 200), d = 0.01, font = F.GothamBold })
end

-- MD 선반 (원두 · 드립백 · 텀블러 · 머그). pcf 바닥, w 폭, h 높이
local function mdShelf(K: any, pcf: CFrame, w: number, h: number, B: any)
	local d = 1.1
	local wood = if B.key == "roastery" or B.key == "concrete" then Look.of(40, 40, 42, Enum.Material.Metal) else Look.oak
	local shelfL = if B.key == "roastery" or B.key == "concrete" then Look.walnut else wood
	for _, sx in { -1, 1 } do
		K:box("MDSide", V3(0.1, h, d), pcf * CF(sx * (w / 2 - 0.05), h / 2, 0), wood)
	end
	K:box("MDBack", V3(w - 0.2, h - 0.1, 0.04), pcf * CF(0, h / 2, -d / 2 + 0.03), lk(dk((shelfL :: any).c, 0.2), (shelfL :: any).m))
	local ns = 4
	local seed = B.seed
	local bag = lk(rgb(196, 160, 112), M.Cardboard)
	local cols = { B.c1, rgb(250, 250, 248), rgb(30, 30, 32), rgb(150, 170, 150), B.c3 }
	for i = 0, ns do
		local y = 0.18 + (h - 0.4) * i / ns
		K:box("MDShelfBoard", V3(w - 0.2, 0.08, d - 0.06), pcf * CF(0, y, 0.02), shelfL)
		if i < ns then
			local yy = y + 0.04
			local inner = w - 0.4
			if i == 0 then
				local n = math.max(2, math.floor(inner / 0.75))
				for k = 1, n do
					local x = -inner / 2 + inner * (k - 0.5) / n
					local bh = 0.5 + rnd(seed, k) * 0.1
					K:box("DripBox", V3(0.6, bh, 0.42), pcf * CF(x, yy + bh / 2, 0.05), lk(cols[(k % #cols) + 1]))
					K:text("DripBoxLabel", 0.5, 0.2, pcf * CF(x, yy + bh * 0.6, 0.265), "DRIP BAG\n10입", { fg = if k % #cols == 1 then rgb(255, 255, 255) else rgb(30, 30, 30), d = 0.005, font = F.GothamBold })
				end
			elseif i == 1 then
				local n = math.max(2, math.floor(inner / 0.62))
				for k = 1, n do
					local x = -inner / 2 + inner * (k - 0.5) / n
					K:box("BeanBag", V3(0.48, 0.72, 0.3), pcf * CF(x, yy + 0.36, 0.08), bag)
					K:box("BeanBagFold", V3(0.5, 0.1, 0.32), pcf * CF(x, yy + 0.75, 0.08), lk(rgb(170, 134, 90), M.Cardboard))
					K:plate("BeanBagLabel", 0.36, 0.3, 0.01, pcf * CF(x, yy + 0.4, 0.23), lk(cols[(k + 1) % #cols + 1]))
					if hi(K) then
						K:cyl("BeanBagValve", 0.02, 0.08, pcf * CF(x, yy + 0.6, 0.235) * ANG(0, PI / 2, 0), Look.black)
					end
				end
			elseif i == 2 then
				local n = math.max(2, math.floor(inner / 0.5))
				for k = 1, n do
					local x = -inner / 2 + inner * (k - 0.5) / n
					if k % 3 == 0 then
						K:vcyl("Mug", 0.4, 0.38, pcf * CF(x, yy + 0.2, 0.05), lk(cols[k % #cols + 1]))
						K:box("MugHandle", V3(0.06, 0.24, 0.08), pcf * CF(x + 0.22, yy + 0.2, 0.05), lk(cols[k % #cols + 1]))
					else
						K:vcyl("Tumbler", 0.82, 0.32, pcf * CF(x, yy + 0.41, 0.05), lk(cols[k % #cols + 1], M.Metal))
						K:vcyl("TumblerLid", 0.14, 0.34, pcf * CF(x, yy + 0.89, 0.05), if k % 2 == 0 then Look.black else Look.chrome)
					end
				end
			else
				Props.potPlant(K, pcf * CF(-inner / 2 + 0.35, yy, 0.05), 0.42, 0.6)
				K:box("GiftSet", V3(1.0, 0.45, 0.6), pcf * CF(0.2, yy + 0.225, 0.05), lk(B.c2))
				K:plate("GiftRibbon", 0.08, 0.46, 0.01, pcf * CF(0.2, yy + 0.225, 0.35), lk(B.c3))
				K:text("GiftLabel", 0.9, 0.16, pcf * CF(0.2, yy + 0.32, 0.36), "GIFT SET 29,000", { fg = rgb(255, 255, 255), d = 0.005, font = F.GothamBold })
			end
			if hi(K) then
				K:text("MDPriceStrip", w - 0.3, 0.07, pcf * CF(0, y - 0.005, d / 2 - 0.02), if i == 1 then "원두 200g  16,000~19,000" elseif i == 2 then "텀블러 25,000 · 머그 15,000" elseif i == 0 then "드립백 10입 15,000" else "" , { fg = rgb(30, 30, 30), bg = rgb(250, 250, 246), d = 0.005, font = F.GothamMedium })
			end
		end
	end
	K:text("MDHeader", w - 0.3, 0.32, pcf * CF(0, h + 0.18, 0), if B.key == "roastery" then "BEANS & GOODS" else "MD · 원두 · 텀블러", { fg = B.ink, bg = B.paper, d = 0.04, font = F.GothamBold })
end

-- 냉장 쇼케이스 (케이크 · 디저트, 세로형 유리문). 반환 문 Model, 경첩(월드)
local function cakeFridge(K: any, pcf: CFrame, w: number, B: any, title: string): (Model?, Vector3?)
	if not room(K, 130) then
		return nil, nil
	end
	local d, h = 2.0, 6.2
	local body = lk(B.c2 or rgb(40, 36, 34), M.Metal)
	K:box("CakeFridgeBase", V3(w, 1.5, d), pcf * CF(0, 0.75, 0), body)
	K:box("CakeFridgeKick", V3(w - 0.1, 0.3, 0.06), pcf * CF(0, 0.15, d / 2 + 0.02), Look.black)
	K:plate("CakeFridgeVent", w * 0.6, 0.3, 0.02, faceCF((pcf * CF(0, 0.6, d / 2 + 0.01)).Position, pcf.ZVector), lk(rgb(70, 70, 74), M.DiamondPlate))
	-- 유리 몸체 (옆 · 뒤 판 + 위 헤더)
	K:box("CakeFridgeBack", V3(w, h - 2.1, 0.1), pcf * CF(0, 1.5 + (h - 2.1) / 2, -d / 2 + 0.05), Look.mirror)
	for _, sx in { -1, 1 } do
		K:box("CakeFridgePost", V3(0.1, h - 2.1, d), pcf * CF(sx * (w / 2 - 0.05), 1.5 + (h - 2.1) / 2, 0), glassL(rgb(220, 232, 236), 0.6))
		K:box("CakeFridgeEdge", V3(0.06, h - 2.1, 0.08), pcf * CF(sx * (w / 2 - 0.03), 1.5 + (h - 2.1) / 2, d / 2 - 0.04), body)
	end
	K:box("CakeFridgeHead", V3(w, 0.6, d), pcf * CF(0, h - 0.3, 0), body)
	K:text("CakeFridgeTitle", w - 0.3, 0.38, pcf * CF(0, h - 0.3, d / 2 + 0.005), title, { fg = rgb(255, 255, 255), glow = 1.2, font = F.GothamBold, d = 0.01 })
	local lamp = K:box("CakeFridgeLamp", V3(w - 0.3, 0.05, 0.12), pcf * CF(0, h - 0.65, d / 2 - 0.3), Look.lampNeutral)
	K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.6, Angle = 120, Color = Look.neutralLight })
	-- 선반 3 + 케이크
	local cakeCols = { { rgb(250, 246, 240), rgb(220, 30, 50) }, { rgb(84, 50, 34), rgb(240, 220, 200) }, { rgb(250, 230, 150), rgb(250, 250, 240) }, { rgb(240, 200, 210), rgb(250, 250, 250) }, { rgb(140, 180, 100), rgb(250, 250, 240) } }
	for i = 0, 2 do
		local y = 1.5 + 0.1 + i * 1.32
		K:box("CakeShelf", V3(w - 0.2, 0.04, d - 0.3), pcf * CF(0, y, -0.05), glassL(rgb(230, 240, 240), 0.5))
		local n = math.max(1, math.floor((w - 0.3) / 0.95))
		for k = 1, n do
			local x = -(w - 0.3) / 2 + (w - 0.3) * (k - 0.5) / n
			local cc = cakeCols[(i * 2 + k) % #cakeCols + 1]
			local c = pcf * CF(x, y + 0.02, 0.0)
			K:disc("CakeBoard", 0.82, 0.03, c * CF(0, 0.015, 0), Look.goldMetal)
			if (i + k) % 3 == 0 then
				-- 조각 케이크 3개
				for j = 0, 2 do
					K:wedge("CakeSlice", V3(0.22, 0.4, 0.34), c * CF((j - 1) * 0.26, 0.23, 0) * ANG(0, PI / 2, 0), lk(cc[1]))
					K:ball("CakeTopping", 0.1, c * CF((j - 1) * 0.26, 0.45, 0.06), lk(cc[2]))
				end
			else
				K:vcyl("Cake", 0.48, 0.74, c * CF(0, 0.27, 0), lk(cc[1]))
				K:vcyl("CakeCream", 0.06, 0.76, c * CF(0, 0.5, 0), lk(lt(cc[1], 0.4)))
				if hi(K) then
					for j = 0, 5 do
						local a = j * PI / 3
						K:ball("CakeTopping", 0.12, c * CF(math.cos(a) * 0.26, 0.56, math.sin(a) * 0.26), lk(cc[2]))
					end
				else
					K:ball("CakeTopping", 0.16, c * CF(0, 0.56, 0), lk(cc[2]))
				end
			end
			K:text("CakeTag", 0.42, 0.14, pcf * CF(x, y + 0.1, d / 2 - 0.22), if i == 0 then "8,500" elseif i == 1 then "7,500" else "32,000", { fg = rgb(40, 40, 40), bg = rgb(252, 250, 244), d = 0.01, font = F.GothamBold })
		end
	end
	-- 앞 유리문
	local hingeL = pcf * CF(-w / 2 + 0.06, 0, d / 2 + 0.04)
	local door = K:group("CakeFridgeDoor", function()
		K:box("CakeDoorGlass", V3(w - 0.14, h - 2.15, 0.05), pcf * CF(0, 1.5 + (h - 2.1) / 2, d / 2 + 0.04), glassL(rgb(220, 236, 240), 0.72))
		K:box("CakeDoorFrame", V3(w - 0.12, 0.08, 0.07), pcf * CF(0, 1.53, d / 2 + 0.04), body)
		K:box("CakeDoorFrame", V3(w - 0.12, 0.08, 0.07), pcf * CF(0, h - 0.64, d / 2 + 0.04), body)
		K:box("CakeDoorHandle", V3(0.07, 1.6, 0.1), pcf * CF(w / 2 - 0.25, 3.6, d / 2 + 0.12), Look.chrome)
	end)
	return door, (K.cf * hingeL).Position
end

-- 음료 병 (몸통 · 어깨 · 뚜껑 · 라벨)
local function bottle(K: any, base: CFrame, h: number, d: number, liquid: Color3, cap: Color3, label: Color3?)
	K:vcyl("Bottle", h * 0.7, d, base * CF(0, h * 0.35, 0), lk(liquid, M.Glass, { t = 0.2 }))
	K:vcyl("BottleShoulder", h * 0.14, d * 0.62, base * CF(0, h * 0.77, 0), lk(liquid, M.Glass, { t = 0.2 }))
	K:vcyl("BottleCap", h * 0.09, d * 0.4, base * CF(0, h * 0.885, 0), lk(cap))
	if label then
		K:vcyl("BottleLabel", h * 0.24, d + 0.012, base * CF(0, h * 0.4, 0), lk(label))
	end
end

-- 음료 냉장고 (유리문 1칸: 생수 · 주스 · 우유 · 콜드브루 · 샌드위치). 반환 문 Model, 경첩(월드)
local function drinkFridge(K: any, pcf: CFrame, w: number, B: any, header: string): (Model?, Vector3?)
	if not room(K, 120) then
		return nil, nil
	end
	local d, h = 2.0, 6.4
	local body = lk(rgb(38, 38, 42), M.Metal)
	K:box("FridgeBack", V3(w, h, 0.1), pcf * CF(0, h / 2, -d / 2 + 0.05), body)
	for _, sx in { -1, 1 } do
		K:box("FridgeSide", V3(0.1, h, d), pcf * CF(sx * (w / 2 - 0.05), h / 2, 0), body)
	end
	K:box("FridgeTop", V3(w, 0.75, d), pcf * CF(0, h - 0.375, 0), body)
	K:box("FridgeBottom", V3(w, 0.62, d), pcf * CF(0, 0.31, 0), body)
	K:text("FridgeHeader", w - 0.24, 0.5, faceCF((pcf * CF(0, h - 0.375, d / 2 + 0.01)).Position, pcf.ZVector), header, { fg = onColor(B.c1), bg = B.c1, glow = 1.1, font = F.GothamBlack, d = 0.01 })
	K:plate("FridgeGrille", w - 0.5, 0.3, 0.02, faceCF((pcf * CF(0, 0.3, d / 2 + 0.01)).Position, pcf.ZVector), lk(rgb(64, 64, 68), M.DiamondPlate))
	local ih = h - 1.37
	local iy = 0.62 + ih / 2
	K:box("FridgeLiner", V3(w - 0.2, ih, 0.04), pcf * CF(0, iy, -d / 2 + 0.12), Look.white)
	for _, sx in { -1, 1 } do
		K:box("FridgeLinerSide", V3(0.04, ih, d - 0.3), pcf * CF(sx * (w / 2 - 0.12), iy, -0.05), Look.white)
	end
	local lamp = K:box("FridgeLamp", V3(w - 0.3, 0.05, 0.08), pcf * CF(0, h - 0.8, d / 2 - 0.25), Look.lampCool)
	K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.7, Angle = 130, Color = Look.coolLight })
	local ns = 5
	local inner = w - 0.45
	for i = 0, ns - 1 do
		local y = 0.62 + 0.06 + i * ih / ns
		K:box("FridgeShelf", V3(w - 0.3, 0.04, d - 0.4), pcf * CF(0, y, -0.1), Look.chrome)
		K:box("FridgeShelfStrip", V3(w - 0.3, 0.1, 0.02), pcf * CF(0, y - 0.03, d / 2 - 0.31), lk(B.c1))
		local function slot(k: number, n: number): CFrame
			return pcf * CF(-inner / 2 + inner * (k - 0.5) / n, y + 0.02, 0.2)
		end
		if i == 0 then
			for k = 1, 4 do
				bottle(K, slot(k, 4), 0.95, 0.36, rgb(214, 232, 240), rgb(40, 110, 220), rgb(230, 240, 250))
			end
		elseif i == ns - 1 then
			for k = 1, 3 do
				local c = slot(k, 3)
				K:box("SandwichPack", V3(0.5, 0.42, 0.2), c * CF(0, 0.21, 0), glassL(rgb(240, 244, 246), 0.55))
				K:wedge("SandwichBread", V3(0.16, 0.36, 0.44), c * CF(0, 0.19, 0) * ANG(0, PI / 2, 0), lk(rgb(236, 210, 160)))
				K:box("SandwichFill", V3(0.44, 0.06, 0.17), c * CF(0, 0.12, 0), lk(if k == 2 then rgb(240, 160, 160) else rgb(130, 180, 90)))
			end
		else
			local kinds = { { rgb(250, 150, 40), rgb(250, 250, 250), rgb(250, 200, 60) }, { rgb(60, 36, 24), rgb(20, 20, 20), rgb(230, 220, 200) }, { rgb(248, 248, 244), rgb(60, 140, 220), rgb(90, 160, 230) }, { rgb(200, 30, 40), rgb(220, 220, 220), rgb(200, 30, 40) } }
			local kd = kinds[(i - 1) % #kinds + 1]
			local n = if hi(K) then 5 else 3
			for k = 1, n do
				bottle(K, slot(k, n), 0.85, 0.28, kd[1], kd[2], kd[3])
			end
		end
	end
	local hinge = pcf * CF(-w / 2 + 0.06, 0, d / 2 + 0.05)
	local door = K:group("FridgeGlassDoor", function()
		local c = pcf * CF(0, iy, d / 2 + 0.05)
		K:box("FridgeDoorGlass", V3(w - 0.2, ih, 0.04), c, glassL(rgb(214, 232, 238), 0.78))
		K:box("FridgeDoorBar", V3(w - 0.12, 0.12, 0.08), c * CF(0, ih / 2, 0), body)
		K:box("FridgeDoorBar", V3(w - 0.12, 0.12, 0.08), c * CF(0, -ih / 2, 0), body)
		K:box("FridgeDoorBar", V3(0.12, ih, 0.08), c * CF(-w / 2 + 0.12, 0, 0), body)
		K:box("FridgeDoorBar", V3(0.12, ih, 0.08), c * CF(w / 2 - 0.12, 0, 0), body)
		K:box("FridgeDoorHandle", V3(0.08, ih * 0.55, 0.12), c * CF(w / 2 - 0.3, 0, 0.1), Look.chrome)
	end)
	return door, (K.cf * hinge).Position
end

-- 계산대 앞 로고 (판 + 글자 또는 금속 글자)
local function counterLogo(K: any, V: any, g: any, B: any)
	local n = custDir(V, g)
	local body = g.body or g.top
	if not body then
		return
	end
	local alongX = math.abs(n.Z) > 0.5
	local len = if alongX then body.size.X else body.size.Z
	if len < 3 then
		return
	end
	local c = (body.min + body.max) / 2
	local fp = if alongX then V3(c.X, 0, if n.Z > 0 then body.max.Z else body.min.Z) else V3(if n.X > 0 then body.max.X else body.min.X, 0, c.Z)
	local top = if g.top then g.top.min.Y else g.y
	local dcf = faceCF(fp + n * 0.2 + V3(0, top * 0.56, 0), n)
	local font = if B.key == "haute" or B.key == "bakery" or B.key == "pascucci" then F.Garamond elseif B.key == "roastery" or B.key == "concrete" then F.Oswald elseif B.type == "dessert" then F.FredokaOne else F.GothamBlack
	K:free(function()
		if B.logoPlate then
			K:panel("CounterLogoPlate", 2.7, 0.92, 0.05, 0.22, dcf, B.logoPlate)
			K:text("CounterLogo", 2.4, 0.62, dcf * CF(0, 0, 0.06), B.logo, { fg = B.logoFg, font = font, d = 0.01 })
		else
			local lw = math.min(4.0, len * 0.32)
			K:text("CounterLogo", lw, 0.55, dcf, B.logo, { fg = B.logoFg or B.c3, font = font, d = 0.03 })
		end
	end)
end

-- 조리 카트 (씨앗호떡 철판 · 츄러스 튀김기): 스테인리스 하부장 + 상판 장비 + 위 간판
local function cookCart(K: any, pcf: CFrame, w: number, kind: string, B: any)
	local d, h = 1.9, 3.0
	K:box("CartKick", V3(w - 0.1, 0.3, d - 0.2), pcf * CF(0, 0.15, -0.05), Look.black)
	K:box("CartBody", V3(w, h - 0.42, d), pcf * CF(0, 0.3 + (h - 0.42) / 2, 0), Look.steel)
	K:box("CartTop", V3(w + 0.06, 0.12, d + 0.06), pcf * CF(0, h - 0.06, 0), Look.brushed)
	for k = -1, 1, 2 do
		K:box("CartDoor", V3(w / 2 - 0.15, h - 0.8, 0.03), pcf * CF(k * w / 4, 0.4 + (h - 0.8) / 2, d / 2 + 0.015), lk(rgb(190, 192, 196), M.Metal))
		K:box("CartHandle", V3(0.5, 0.06, 0.06), pcf * CF(k * w / 4, h - 0.6, d / 2 + 0.06), Look.chrome)
	end
	K:text("CartLabel", w * 0.7, 0.36, faceCF((pcf * CF(0, 1.0, d / 2 + 0.035)).Position, pcf.ZVector), if kind == "hotteok" then "부산 명물 씨앗호떡" else "갓 튀긴 츄러스", { fg = onColor(B.c1), bg = B.c1, d = 0.02, font = F.GothamBlack })
	local y = h
	if kind == "hotteok" then
		-- 철판 + 굽는 호떡 6 + 누르개 + 기름병 + 씨앗 통
		K:box("Griddle", V3(w * 0.62, 0.08, d - 0.3), pcf * CF(-w * 0.15, y + 0.04, 0), lk(rgb(36, 36, 38), M.Metal))
		K:box("GriddleRim", V3(w * 0.62 + 0.08, 0.14, 0.06), pcf * CF(-w * 0.15, y + 0.07, -(d - 0.3) / 2), Look.steel)
		for k = 0, 5 do
			local x = -w * 0.15 - w * 0.22 + (k % 3) * w * 0.22
			local z = if k < 3 then -0.3 else 0.3
			K:disc("Hotteok", 0.5, 0.07, pcf * CF(x, y + 0.115, z), lk(rgb(206, 140, 60)))
			K:disc("HotteokCrisp", 0.36, 0.072, pcf * CF(x, y + 0.117, z), lk(rgb(176, 104, 40)))
		end
		K:box("HotteokPress", V3(0.5, 0.04, 0.5), pcf * CF(w * 0.12, y + 0.26, 0.4) * ANG(0, 0.3, 0), Look.steel)
		K:seg("HotteokPressHandle", (pcf * CF(w * 0.12, y + 0.28, 0.4)).Position, (pcf * CF(w * 0.12 + 0.2, y + 0.75, 0.4)).Position, 0.06, Look.walnut)
		for k = 0, 2 do
			K:box("SeedBin", V3(0.4, 0.22, 0.4), pcf * CF(w * 0.3, y + 0.11, -0.55 + k * 0.48), Look.steel)
			K:box("SeedFill", V3(0.34, 0.03, 0.34), pcf * CF(w * 0.3, y + 0.2, -0.55 + k * 0.48), lk(if k == 0 then rgb(120, 86, 50) elseif k == 1 then rgb(60, 50, 40) else rgb(200, 170, 110), M.Pebble))
		end
		K:vcyl("OilBottle", 0.7, 0.24, pcf * CF(w * 0.42, y + 0.35, 0.5), lk(rgb(230, 200, 90), M.Glass, { t = 0.2 }))
		-- 종이컵에 꽂힌 완성 호떡
		for k = 0, 3 do
			local c = pcf * CF(w * 0.45 - 0.05, y, -0.65 + k * 0.32)
			K:vcyl("PaperCup", 0.32, 0.26, c * CF(0, 0.16, 0), Look.paper)
			K:disc("CupHotteok", 0.34, 0.06, c * CF(0, 0.38, 0) * ANG(0.9, 0, 0), lk(rgb(200, 132, 56)))
		end
	else
		-- 튀김기 (기름통 2) + 츄러스 거치대 + 설탕 통
		for k = 0, 1 do
			local c = pcf * CF(-w * 0.25 + k * 0.95, y, -0.1)
			K:box("FryerWell", V3(0.85, 0.3, 1.1), c * CF(0, 0.15, 0), Look.steel)
			K:box("FryerOil", V3(0.75, 0.02, 1.0), c * CF(0, 0.29, 0), lk(rgb(196, 150, 50), M.Glass, { t = 0.15 }))
			K:box("FryerBasket", V3(0.6, 0.06, 0.8), c * CF(0, 0.36, 0), Look.chrome)
			K:bar("FryerBasketHandle", (c * CF(0, 0.38, 0.4)).Position, (c * CF(0, 0.75, 0.75)).Position, 0.05, 0.05, Look.black)
		end
		local hc = pcf * CF(w * 0.32, y, 0.0)
		K:box("ChurrosHolder", V3(0.9, 0.4, 0.5), hc * CF(0, 0.2, 0), Look.walnut)
		for k = 0, 5 do
			local x = -0.32 + (k % 3) * 0.32
			local z = if k < 3 then -0.1 else 0.1
			K:seg("Churro", (hc * CF(x, 0.3, z)).Position, (hc * CF(x + (k - 2.5) * 0.04, 1.35, z)).Position, 0.12, lk(rgb(200, 140, 70), M.Sand))
		end
		K:vcyl("SugarTub", 0.3, 0.6, pcf * CF(w * 0.32, y + 0.15, -0.6), lk(rgb(240, 236, 226), M.Sand))
	end
	K:text("CartPrice", w * 0.6, 0.3, faceCF((pcf * CF(0, y + 1.3, -d / 2 + 0.05)).Position, pcf.ZVector), if kind == "hotteok" then "씨앗호떡 2,000 · 꿀호떡 1,500" else "츄러스 3,000 · 초코딥 4,000", { fg = rgb(40, 30, 20), bg = rgb(255, 248, 230), d = 0.03, font = F.GothamBold })
	K:bar("CartSignPost", (pcf * CF(-w / 2 + 0.1, y, -d / 2 + 0.05)).Position, (pcf * CF(-w / 2 + 0.1, y + 1.5, -d / 2 + 0.05)).Position, 0.06, 0.06, Look.blackMetal)
	K:bar("CartSignPost", (pcf * CF(w / 2 - 0.1, y, -d / 2 + 0.05)).Position, (pcf * CF(w / 2 - 0.1, y + 1.5, -d / 2 + 0.05)).Position, 0.06, 0.06, Look.blackMetal)
end

-- 커피 로스터 (드럼 · 호퍼 · 냉각 트레이 · 연통 · 사이클론 · 제어반). 반환 { glass, arms, armBase, panel, screen }
local function roaster(K: any, pcf: CFrame, B: any): any
	local V = K.V
	local body = lk(rgb(32, 32, 34), M.Metal)
	local acc = lk(B.c3 or rgb(200, 110, 50), M.Metal, { r = 0.1 })
	local out: any = {}
	K:box("RoasterPlinth", V3(2.3, 0.14, 2.0), pcf * CF(-0.55, 0.07, -0.3), Look.black)
	K:box("RoasterBase", V3(2.1, 2.3, 1.8), pcf * CF(-0.55, 1.29, -0.3), body)
	K:plate("RoasterBasePanel", 1.5, 1.4, 0.03, faceCF((pcf * CF(-0.55, 1.25, 0.6)).Position, pcf.ZVector), acc)
	K:cyl("RoasterDrum", 1.9, 1.7, pcf * CF(-0.55, 3.3, -0.35) * ANG(0, PI / 2, 0), body)
	K:cyl("RoasterBand", 0.12, 1.78, pcf * CF(-0.55, 3.3, 0.35) * ANG(0, PI / 2, 0), acc)
	K:cyl("RoasterFace", 0.08, 1.6, pcf * CF(-0.55, 3.3, 0.62) * ANG(0, PI / 2, 0), Look.brushed)
	K:cyl("RoasterDoor", 0.1, 1.05, pcf * CF(-0.55, 3.2, 0.7) * ANG(0, PI / 2, 0), Look.chrome)
	out.glass = K:cyl("RoasterSightGlass", 0.04, 0.34, pcf * CF(-0.2, 3.62, 0.72) * ANG(0, PI / 2, 0), lk(rgb(120, 70, 40), M.Glass, { t = 0.2 }))
	K:bar("RoasterDoorHandle", (pcf * CF(-0.55, 3.2, 0.78)).Position, (pcf * CF(0.1, 3.0, 0.82)).Position, 0.08, 0.08, Look.black)
	K:cyl("RoasterTrier", 0.36, 0.1, pcf * CF(-0.95, 3.55, 0.8) * ANG(0, PI / 2, 0), Look.walnut)
	-- 배출 슈트
	K:wedge("RoasterChute", V3(0.6, 0.35, 0.6), pcf * CF(0.0, 2.55, 0.62) * ANG(0, PI / 2, 0), Look.brushed)
	-- 호퍼 (깔때기)
	K:vcyl("RoasterHopperNeck", 0.5, 0.34, pcf * CF(-0.55, 4.4, -0.35), Look.chrome)
	K:vcyl("RoasterHopperLow", 0.35, 0.7, pcf * CF(-0.55, 4.8, -0.35), Look.chrome)
	K:vcyl("RoasterHopper", 0.6, 1.1, pcf * CF(-0.55, 5.25, -0.35), Look.chrome)
	K:disc("RoasterHopperBeans", 1.0, 0.04, pcf * CF(-0.55, 5.54, -0.35), lk(rgb(150, 170, 96), M.Pebble))
	-- 연통 (천장까지)
	K:free(function()
		K:seg("RoasterFlue", pcf * V3(-0.55, 3.9, -1.05), pcf * V3(-0.55, V.H - 0.05, -1.05), 0.42, Look.brushed)
		K:seg("RoasterFlueJoint", pcf * V3(-0.55, 3.3, -1.05), pcf * V3(-0.55, 3.95, -1.05), 0.5, Look.brushed)
		K:disc("RoasterFlueCollar", 0.7, 0.08, CF(pcf * V3(-0.55, V.H - 0.05, -1.05)), Look.brushed)
	end)
	-- 냉각 트레이 (교반 날개 회전)
	local trayC = pcf * CF(0.95, 2.05, 0.35)
	K:vcyl("CoolingStand", 1.8, 0.5, pcf * CF(0.95, 0.9, 0.35), body)
	K:disc("CoolingTray", 1.85, 0.32, trayC, Look.steel)
	K:disc("CoolingBeans", 1.7, 0.04, trayC * CF(0, 0.15, 0), lk(rgb(86, 52, 32), M.Pebble))
	K:vcyl("CoolingHub", 0.28, 0.16, trayC * CF(0, 0.3, 0), Look.chrome)
	local a1 = K:box("CoolingArm", V3(1.6, 0.06, 0.07), trayC * CF(0, 0.22, 0), Look.chrome)
	local a2 = K:box("CoolingArm", V3(1.6, 0.06, 0.07), trayC * CF(0, 0.22, 0) * ANG(0, PI / 2, 0), Look.chrome)
	out.arms = { a1, a2 }
	out.armBase = { a1.CFrame, a2.CFrame }
	out.center = (K.cf * trayC).Position
	-- 사이클론 (채프 수집기)
	K:vcyl("ChaffCyclone", 1.4, 0.8, pcf * CF(1.25, 4.1, -0.95), body)
	K:vcyl("ChaffCone", 0.5, 0.45, pcf * CF(1.25, 3.15, -0.95), body)
	K:vcyl("ChaffBin", 0.6, 0.6, pcf * CF(1.25, 0.3, -0.95), Look.brushed)
	K:seg("ChaffPipe", pcf * V3(-0.2, 3.9, -0.9), pcf * V3(0.9, 4.5, -0.95), 0.2, Look.brushed)
	-- 제어반 (화면 + 계기)
	local pc = pcf * CF(0.95, 3.65, 0.2)
	out.panel = K:box("RoasterPanel", V3(0.95, 0.95, 0.2), pc, body)
	local dcfP = faceCF((pc * CF(0, 0, 0.1)).Position, pcf.ZVector)
	local scr, lab = K:text("RoasterScreen", 0.7, 0.36, dcfP * CF(0, 0.18, 0.01), "STANDBY\nBT 25℃", { fg = rgb(120, 255, 160), bg = rgb(8, 14, 10), glow = 1.3, font = F.Code, d = 0.01 })
	out.screen, out.label = scr, lab
	for k = -1, 1 do
		wdisc(K, "RoasterGauge", 0.2, 0.03, dcfP * CF(k * 0.26, -0.22, 0.0), Look.white)
	end
	K:text("RoasterBadge", 1.2, 0.22, faceCF((pcf * CF(-0.55, 1.95, 0.64)).Position, pcf.ZVector), "DRUM ROASTER 12kg", { fg = rgb(240, 240, 236), font = F.GothamBold, d = 0.01 })
	return out
end

-- 생두 자루 (팔레트 위 마대)
local function beanSacks(K: any, pcf: CFrame, w: number)
	if not room(K, 20) then
		return
	end
	K:box("PalletTop", V3(w, 0.12, 1.7), pcf * CF(0, 0.42, 0), Look.pine)
	for k = -1, 1 do
		K:box("PalletBlock", V3(w, 0.3, 0.22), pcf * CF(0, 0.18, k * 0.7), Look.pine)
	end
	local origin = { "ETHIOPIA\nYIRGACHEFFE", "COLOMBIA\nHUILA", "KENYA AA", "GUATEMALA\nANTIGUA", "BRAZIL\nCERRADO" }
	local n = math.max(2, math.floor(w / 1.05))
	for k = 1, n do
		local x = -w / 2 + w * (k - 0.5) / n
		local c = pcf * CF(x, 0.48, 0.05 + (k % 2) * 0.15)
		K:ell("JuteSack", V3(0.95, 0.75, 1.3), c * CF(0, 0.36, 0) * ANG(0, (k % 3) * 0.15 - 0.15, 0), lk(rgb(176, 146, 100), M.Fabric))
		K:ell("JuteSackTop", V3(0.5, 0.25, 0.6), c * CF(0, 0.74, -0.1), lk(rgb(160, 130, 88), M.Fabric))
		K:text("JuteSackPrint", 0.62, 0.36, faceCF((c * CF(0, 0.38, 0.62)).Position, pcf.ZVector) * ANG(-0.25, 0, 0), origin[(k - 1) % #origin + 1], { fg = rgb(70, 50, 34), font = F.SpecialElite, d = 0.005 })
	end
	if w > 2.2 then
		local c = pcf * CF(0.2, 1.25, 0.1)
		K:ell("JuteSack", V3(0.9, 0.6, 1.2), c * CF(0, 0.2, 0) * ANG(0, 0.4, 0), lk(rgb(186, 156, 108), M.Fabric))
	end
end

-- 데크 오븐 3단 (스테인리스 + 창 안쪽 빵 + 온도 표시)
local function deckOven(K: any, pcf: CFrame, w: number): any
	local d = 2.5
	local steel = lk(rgb(196, 198, 200), M.SmoothPlastic, { r = 0.05 })
	local out: any = { glows = {} }
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:box("OvenLeg", V3(0.14, 1.1, 0.14), pcf * CF(sx * (w / 2 - 0.15), 0.55, sz * (d / 2 - 0.15)), steel)
		end
	end
	K:box("OvenRackShelf", V3(w - 0.2, 0.06, d - 0.2), pcf * CF(0, 0.35, 0), steel)
	for k = 0, 2 do
		K:box("OvenSheetPan", V3(w - 0.5, 0.04, d - 0.6), pcf * CF(0, 0.45 + k * 0.18, 0), Look.alu)
	end
	K:box("OvenBody", V3(w, 4.0, d), pcf * CF(0, 1.1 + 2.0, 0), steel)
	K:box("OvenHood", V3(w + 0.1, 0.7, d + 0.2), pcf * CF(0, 5.45, 0.08), lk(rgb(176, 178, 182), M.SmoothPlastic, { r = 0.05 }))
	K:box("OvenHoodLip", V3(w + 0.12, 0.1, 0.1), pcf * CF(0, 5.1, d / 2 + 0.16), Look.brushed)
	local dw = w - 1.1
	for k = 0, 2 do
		local y = 1.1 + 0.2 + k * 1.3 + 0.55
		local dc = faceCF((pcf * CF(-0.45, y, d / 2 + 0.01)).Position, pcf.ZVector)
		K:plate("OvenDoor", dw, 1.05, 0.06, dc, Look.chrome)
		local g = K:plate("OvenGlow", dw - 0.5, 0.48, 0.065, dc * CF(0, 0.08, 0), Look.neon(rgb(255, 150, 70), 0.25))
		table.insert(out.glows, g)
		for j = 0, 2 do
			K:ell("OvenLoaf", V3(0.55, 0.2, 0.05), dc * CF(-0.6 + j * 0.6, -0.04, 0.09), lk(rgb(150, 86, 34)))
		end
		K:plate("OvenWindow", dw - 0.4, 0.56, 0.12, dc * CF(0, 0.08, 0), glassL(rgb(60, 40, 30), 0.6))
		K:bar("OvenHandle", (dc * CF(-dw / 2 + 0.3, -0.38, 0.14)).Position, (dc * CF(dw / 2 - 0.3, -0.38, 0.14)).Position, 0.08, 0.08, Look.black)
		local pc = faceCF((pcf * CF(w / 2 - 0.5, y, d / 2 + 0.01)).Position, pcf.ZVector)
		K:plate("OvenPanel", 0.8, 1.0, 0.04, pc, Look.charcoal)
		K:text("OvenTemp", 0.6, 0.24, pc * CF(0, 0.22, 0.045), if k == 0 then "220℃" elseif k == 1 then "200℃" else "180℃", { fg = rgb(255, 60, 40), bg = rgb(10, 6, 6), glow = 1.5, font = F.Code, d = 0.01 })
		for j = -1, 1 do
			wdisc(K, "OvenKnob", 0.14, 0.05, pc * CF(j * 0.22, -0.2, 0.04), Look.chrome)
		end
	end
	K:text("OvenBadge", 1.6, 0.26, faceCF((pcf * CF(0, 5.45, d / 2 + 0.19)).Position, pcf.ZVector), "DECK OVEN 3단", { fg = rgb(60, 60, 64), font = F.GothamBold, d = 0.01 })
	return out
end

-- 빵 ------------------------------------------------------------------------------------------------------
local BREADS = {
	{ "소금빵", "3,500", "salt" }, { "크루아상", "4,200", "croissant" }, { "단팥빵", "2,800", "bun" }, { "소보로", "2,800", "soboro" },
	{ "우유식빵", "5,500", "loaf" }, { "바게트", "4,500", "baguette" }, { "고로케", "3,000", "goroke" }, { "마늘바게트", "5,000", "garlic" },
	{ "에그타르트", "3,200", "tart" }, { "크림치즈 베이글", "4,500", "bagel" }, { "앙버터", "4,500", "salt" }, { "옥수수빵", "3,200", "bun" },
	{ "치아바타", "4,000", "ciabatta" }, { "명란 바게트", "5,500", "baguette" },
}
local function bread(K: any, pcf: CFrame, kind: string, s: number)
	if kind == "hotteok" or kind == "hotteokg" then
		-- 두 장 겹친 호떡: 살짝 볼록한 반죽 + 가운데 캐러멜 자국 + 위 장 갈라진 틈의 씨앗
		local dough = if kind == "hotteokg" then rgb(150, 160, 84) else rgb(214, 150, 70)
		for k = 0, 1 do
			local c = pcf * CF(k * 0.07 * s, 0.045 * s + k * 0.085 * s, -k * 0.03 * s)
			K:ell("Hotteok", V3(0.46, 0.09, 0.46) * s, c, lk(dough))
			K:ell("HotteokCrisp", V3(0.3, 0.05, 0.28) * s, c * CF(0.02 * s, 0.026 * s, 0), lk(dk(dough, 0.18)))
		end
		K:ell("HotteokSeeds", V3(0.16, 0.03, 0.08) * s, pcf * CF(0.09 * s, 0.18 * s, -0.03 * s) * ANG(0, 0.4, 0), lk(rgb(126, 88, 52), M.Pebble))
	elseif kind == "salt" then
		K:ell("Bread", V3(0.6, 0.28, 0.36) * s, pcf * CF(0, 0.13 * s, 0), lk(rgb(216, 154, 72)))
		K:ell("BreadGloss", V3(0.46, 0.1, 0.26) * s, pcf * CF(0, 0.24 * s, 0), lk(rgb(186, 112, 44), M.SmoothPlastic, { r = 0.06 }))
	elseif kind == "croissant" then
		local c = lk(rgb(202, 132, 56))
		K:ell("Croissant", V3(0.46, 0.28, 0.32) * s, pcf * CF(0, 0.13 * s, 0), c)
		for _, sx in { -1, 1 } do
			K:ell("CroissantHorn", V3(0.32, 0.16, 0.18) * s, pcf * CF(sx * 0.28 * s, 0.08 * s, 0.08 * s) * ANG(0, sx * 0.7, 0), c)
		end
		K:ell("CroissantRidge", V3(0.1, 0.27, 0.33) * s, pcf * CF(0.1 * s, 0.14 * s, 0), lk(rgb(176, 104, 40)))
	elseif kind == "baguette" or kind == "garlic" then
		K:ell("Baguette", V3(1.2, 0.22, 0.24) * s, pcf * CF(0, 0.11 * s, 0) * ANG(0, 0.1, 0), lk(if kind == "garlic" then rgb(214, 170, 90) else rgb(204, 144, 64)))
		for i = -1, 1 do
			K:box("BaguetteScore", V3(0.18, 0.02, 0.05) * s, pcf * CF(i * 0.3 * s, 0.215 * s, 0) * ANG(0, 0.1 + 0.6, 0), lk(if kind == "garlic" then rgb(120, 150, 60) else rgb(238, 210, 156)))
		end
	elseif kind == "loaf" then
		K:box("Loaf", V3(0.7, 0.38, 0.44) * s, pcf * CF(0, 0.19 * s, 0), lk(rgb(234, 204, 156)))
		for i = -1, 1 do
			K:ell("LoafTop", V3(0.25, 0.22, 0.44) * s, pcf * CF(i * 0.22 * s, 0.38 * s, 0), lk(rgb(178, 106, 44)))
		end
	elseif kind == "ciabatta" then
		K:ell("Ciabatta", V3(0.8, 0.2, 0.46) * s, pcf * CF(0, 0.09 * s, 0), lk(rgb(206, 164, 104), M.Sand))
		K:ell("CiabattaFlour", V3(0.5, 0.06, 0.28) * s, pcf * CF(0.04 * s, 0.17 * s, 0), lk(rgb(240, 232, 216), M.Sand))
	elseif kind == "soboro" then
		K:ell("Soboro", V3(0.52, 0.26, 0.52) * s, pcf * CF(0, 0.12 * s, 0), lk(rgb(214, 164, 92), M.Sand))
	elseif kind == "goroke" then
		K:ell("Goroke", V3(0.56, 0.26, 0.36) * s, pcf * CF(0, 0.12 * s, 0), lk(rgb(190, 120, 50), M.Sand))
	elseif kind == "tart" then
		K:disc("TartCrust", 0.42 * s, 0.14 * s, pcf * CF(0, 0.07 * s, 0), lk(rgb(220, 170, 96)))
		K:disc("TartCustard", 0.34 * s, 0.03 * s, pcf * CF(0, 0.14 * s, 0), lk(rgb(250, 206, 80)))
		K:disc("TartBurn", 0.12 * s, 0.032 * s, pcf * CF(0.05 * s, 0.142 * s, 0.03 * s), lk(rgb(150, 86, 30)))
	elseif kind == "bagel" then
		K:disc("Bagel", 0.5 * s, 0.18 * s, pcf * CF(0, 0.09 * s, 0), lk(rgb(200, 140, 70)))
		K:disc("BagelHole", 0.14 * s, 0.185 * s, pcf * CF(0, 0.09 * s, 0), lk(rgb(90, 60, 36)))
	else
		K:ell("Bun", V3(0.48, 0.26, 0.48) * s, pcf * CF(0, 0.12 * s, 0), lk(rgb(178, 104, 40), M.SmoothPlastic, { r = 0.05 }))
		K:ball("BunSesame", 0.06 * s, pcf * CF(0, 0.25 * s, 0), lk(rgb(30, 24, 20)))
	end
end

-- 바구니 (등나무 테 + 유산지)
local function basket(K: any, pcf: CFrame, w: number, d: number, look: any)
	K:box("BasketBase", V3(w, 0.06, d), pcf * CF(0, 0.03, 0), look)
	K:box("BasketRim", V3(w, 0.16, 0.06), pcf * CF(0, 0.1, d / 2 - 0.03), look)
	K:box("BasketRim", V3(w, 0.16, 0.06), pcf * CF(0, 0.1, -d / 2 + 0.03), look)
	K:box("BasketRim", V3(0.06, 0.16, d - 0.12), pcf * CF(w / 2 - 0.03, 0.1, 0), look)
	K:box("BasketRim", V3(0.06, 0.16, d - 0.12), pcf * CF(-w / 2 + 0.03, 0.1, 0), look)
	K:box("BasketPaper", V3(w - 0.14, 0.02, d - 0.14), pcf * CF(0, 0.07, 0), Look.paper)
end

-- 가격표 (작은 판)
local function tag(K: any, dcf: CFrame, w: number, h: number, text: string, bg: Color3?, fg: Color3?)
	K:text("PriceTag", w, h, dcf, text, { fg = fg or rgb(30, 30, 30), bg = bg or rgb(252, 250, 244), d = 0.012, font = F.GothamBold })
end

-- 페이스트리 (진열장 안): kind 로 모양
local function pastry(K: any, pcf: CFrame, kind: string, s: number)
	if kind == "croissant" or kind == "salt" or kind == "tart" or kind == "bagel" then
		bread(K, pcf, kind, s)
	elseif kind == "muffin" then
		K:vcyl("MuffinCup", 0.22 * s, 0.34 * s, pcf * CF(0, 0.11 * s, 0), lk(rgb(240, 236, 226)))
		K:ell("MuffinTop", V3(0.42, 0.26, 0.42) * s, pcf * CF(0, 0.24 * s, 0), lk(rgb(120, 72, 40)))
	elseif kind == "macaron" then
		local cols = { rgb(250, 190, 206), rgb(190, 230, 200), rgb(250, 230, 150), rgb(200, 180, 240) }
		for k = 0, 2 do
			local c = pcf * CF((k - 1) * 0.2 * s, 0, 0)
			local col = cols[(k + math.floor(s * 10)) % #cols + 1]
			K:disc("MacaronShell", 0.18 * s, 0.05 * s, c * CF(0, 0.025 * s, 0), lk(col))
			K:disc("MacaronFill", 0.16 * s, 0.03 * s, c * CF(0, 0.065 * s, 0), lk(rgb(250, 246, 236)))
			K:disc("MacaronShell", 0.18 * s, 0.05 * s, c * CF(0, 0.105 * s, 0), lk(col))
		end
	elseif kind == "cake" then
		K:box("CakeSlice", V3(0.34, 0.3, 0.42) * s, pcf * CF(0, 0.15 * s, 0), lk(rgb(250, 240, 220)))
		K:box("CakeLayer", V3(0.345, 0.04, 0.425) * s, pcf * CF(0, 0.15 * s, 0), lk(rgb(220, 60, 80)))
		K:ball("CakeBerry", 0.12 * s, pcf * CF(0, 0.33 * s, 0), lk(rgb(220, 30, 50)))
	elseif kind == "cookie" then
		for k = 0, 2 do
			K:disc("Cookie", 0.3 * s, 0.05 * s, pcf * CF((k - 1) * 0.12 * s, 0.03 * s + k * 0.045 * s, 0) * ANG(0.12 * (k - 1), 0, 0.08), lk(rgb(196, 140, 76)))
		end
	elseif kind == "financier" then
		for k = 0, 1 do
			K:box("Financier", V3(0.32, 0.12, 0.16) * s, pcf * CF(0, 0.06 * s, (k - 0.5) * 0.2 * s), lk(rgb(206, 150, 76)))
		end
	else
		K:ell("Scone", V3(0.4, 0.24, 0.4) * s, pcf * CF(0, 0.11 * s, 0), lk(rgb(220, 176, 110), M.Sand))
	end
end
local HOTTEOK_CASE = {
	{ "씨앗호떡", "2,000", "hotteok" }, { "꿀호떡", "1,500", "hotteok" }, { "녹차씨앗호떡", "2,500", "hotteokg" }, { "치즈호떡", "2,500", "hotteok" },
	{ "찹쌀호떡 6입 포장", "9,000", "hotteok" },
}
local PASTRIES = {
	{ "크루아상", "4,200", "croissant" }, { "블루베리 머핀", "3,800", "muffin" }, { "마카롱", "3,000", "macaron" }, { "딸기 케이크", "7,500", "cake" },
	{ "초코칩 쿠키", "2,800", "cookie" }, { "휘낭시에", "3,000", "financier" }, { "소금빵", "3,800", "salt" }, { "스콘", "3,500", "scone" },
	{ "에그타르트", "3,200", "tart" }, { "베이글", "3,500", "bagel" },
}

-- 카운터 위 소품 ----------------------------------------------------------------------------------------
local function pagerTower(K: any, pcf: CFrame, n: number, c: Color3)
	K:box("PagerBase", V3(0.66, 0.14, 0.66), pcf * CF(0, 0.07, 0), Look.black)
	K:box("PagerBaseLED", V3(0.3, 0.03, 0.02), pcf * CF(0, 0.08, 0.335), Look.ledGreen)
	for i = 1, n do
		local y = 0.14 + 0.1 * (i - 0.5)
		K:box("Pager", V3(0.56, 0.08, 0.56), pcf * CF(0, y, 0) * ANG(0, (i % 2) * 0.05, 0), lk(if i % 2 == 0 then rgb(250, 250, 248) else c))
		K:box("PagerLED", V3(0.12, 0.03, 0.02), pcf * CF(0.12, y, 0.29), Look.ledRed)
	end
	K:text("PagerNo", 0.36, 0.16, topCF((pcf * CF(0, 0.15 + 0.1 * n, 0)).Position, pcf.ZVector * -1), tostring(10 + n), { fg = rgb(40, 40, 40), d = 0.005, font = F.GothamBold })
end

local function cookieJar(K: any, pcf: CFrame, c: Color3, label: string)
	K:vcyl("CookieJar", 0.7, 0.5, pcf * CF(0, 0.35, 0), glassL(rgb(236, 242, 244), 0.6))
	K:vcyl("CookieJarLid", 0.1, 0.52, pcf * CF(0, 0.75, 0), Look.walnut)
	K:ball("CookieJarKnob", 0.12, pcf * CF(0, 0.82, 0), Look.walnut)
	for k = 0, 3 do
		K:disc("JarCookie", 0.36, 0.06, pcf * CF((k % 2) * 0.04 - 0.02, 0.08 + k * 0.1, 0) * ANG(0.2 * (k % 2), 0, 0.15), lk(c))
	end
	tag(K, facing((pcf * CF(0, 0.3, 0.26)).Position, pcf.ZVector), 0.4, 0.16, label)
end

local function cakeDome(K: any, pcf: CFrame, c: Color3)
	K:disc("DomeStand", 0.8, 0.04, pcf * CF(0, 0.02, 0), Look.white)
	K:vcyl("DomeStem", 0.25, 0.12, pcf * CF(0, 0.15, 0), Look.white)
	K:disc("DomePlate", 0.86, 0.04, pcf * CF(0, 0.29, 0), Look.white)
	K:vcyl("DomeCake", 0.32, 0.56, pcf * CF(0, 0.47, 0), lk(c))
	K:vcyl("DomeCakeCream", 0.05, 0.58, pcf * CF(0, 0.62, 0), Look.white)
	K:ell("DomeGlass", V3(0.8, 0.8, 0.8), pcf * CF(0, 0.55, 0), glassL(rgb(236, 242, 244), 0.75))
	K:ball("DomeKnob", 0.08, pcf * CF(0, 0.97, 0), Look.chrome)
end

local function flowerVase(K: any, pcf: CFrame, B: any)
	K:vcyl("Vase", 0.5, 0.28, pcf * CF(0, 0.25, 0), glassL(rgb(220, 236, 236), 0.4))
	local cols = { B.c1, rgb(250, 250, 246), rgb(250, 200, 120), lt(B.c1, 0.4) }
	for k = 0, 6 do
		local a = k * 2 * PI / 7
		local tip = pcf * V3(math.cos(a) * 0.22, 0.95 + (k % 3) * 0.1, math.sin(a) * 0.22)
		K:seg("FlowerStem", pcf * V3(0, 0.45, 0), tip, 0.025, Look.leafDark)
		K:ball("FlowerHead", 0.17 + (k % 2) * 0.05, CF(tip), lk(cols[k % #cols + 1], M.Fabric))
	end
end

local function standSign(K: any, pcf: CFrame, w: number, h: number, text: string, fg: Color3, bg: Color3)
	K:box("StandSignFoot", V3(w * 0.7, 0.05, 0.3), pcf * CF(0, 0.025, 0), Look.acrylicWhite)
	K:text("StandSign", w, h, pcf * CF(0, 0.05 + h / 2, 0) * ANG(math.rad(-6), 0, 0), text, { fg = fg, bg = bg, d = 0.03, font = F.GothamBold })
end

-- 뒷바 장비
local function blender(K: any, pcf: CFrame, enclosure: boolean)
	K:box("BlenderBase", V3(0.55, 0.45, 0.6), pcf * CF(0, 0.225, 0), Look.of(30, 30, 32))
	K:plate("BlenderPanel", 0.42, 0.16, 0.02, faceCF((pcf * CF(0, 0.25, 0.3)).Position, pcf.ZVector), Look.of(60, 60, 64, Enum.Material.Glass))
	K:box("BlenderLED", V3(0.1, 0.03, 0.02), pcf * CF(-0.12, 0.3, 0.31), Look.ledBlue)
	K:vcyl("BlenderJar", 0.8, 0.46, pcf * CF(0, 0.45 + 0.4, 0), glassL(rgb(230, 236, 240), 0.5))
	K:vcyl("BlenderLid", 0.1, 0.48, pcf * CF(0, 1.3, 0), Look.black)
	K:box("BlenderHandle", V3(0.07, 0.56, 0.1), pcf * CF(0.29, 0.88, 0), Look.black)
	if enclosure then
		K:box("BlenderHood", V3(0.82, 1.15, 0.78), pcf * CF(0, 0.45 + 0.6, 0), glassL(rgb(220, 230, 236), 0.75))
	end
end

local function syrupRack(K: any, pcf: CFrame, n: number)
	local w = n * 0.34 + 0.1
	K:box("SyrupRack", V3(w, 0.12, 0.42), pcf * CF(0, 0.06, 0), Look.steel)
	K:box("SyrupRackBack", V3(w, 0.4, 0.04), pcf * CF(0, 0.2, -0.2), Look.steel)
	local cols = { rgb(150, 92, 40), rgb(220, 200, 160), rgb(120, 40, 30), rgb(90, 140, 70), rgb(230, 230, 220), rgb(60, 30, 20) }
	local names = { "바닐라", "헤이즐넛", "카라멜", "모카", "슈가", "돌체" }
	for k = 1, n do
		local x = -w / 2 + 0.05 + 0.34 * (k - 0.5)
		K:vcyl("SyrupBottle", 0.82, 0.26, pcf * CF(x, 0.12 + 0.41, 0), lk(cols[(k - 1) % #cols + 1], M.Glass, { t = 0.15 }))
		K:vcyl("SyrupPump", 0.22, 0.1, pcf * CF(x, 1.05, 0), Look.black)
		K:box("SyrupNozzle", V3(0.04, 0.04, 0.18), pcf * CF(x, 1.15, 0.08), Look.black)
		if hi(K) then
			K:text("SyrupLabel", 0.22, 0.2, pcf * CF(x, 0.5, 0.131), names[(k - 1) % #names + 1], { fg = rgb(40, 40, 40), bg = rgb(250, 248, 240), d = 0.005, font = F.GothamBold })
		end
	end
end

local function cupTower(K: any, pcf: CFrame, cupC: Color3)
	K:box("CupTowerBase", V3(1.2, 0.1, 0.45), pcf * CF(0, 0.05, 0), Look.steel)
	local sizes = { 0.34, 0.4, 0.46 }
	for k = 1, 3 do
		local x = -0.4 + (k - 1) * 0.4
		K:vcyl("CupTube", 1.2, sizes[k] + 0.06, pcf * CF(x, 0.7, 0), glassL(rgb(230, 236, 240), 0.7))
		K:vcyl("CupStack", 1.05, sizes[k], pcf * CF(x, 0.65, 0), lk(cupC, M.SmoothPlastic))
	end
end

local function hotWater(K: any, pcf: CFrame)
	K:box("HotWaterBody", V3(0.7, 1.25, 0.8), pcf * CF(0, 0.625, 0), Look.steel)
	K:text("HotWaterLCD", 0.4, 0.16, faceCF((pcf * CF(0, 1.05, 0.405)).Position, pcf.ZVector), "95℃", { fg = rgb(255, 80, 60), bg = rgb(10, 10, 12), glow = 1.3, font = F.Code, d = 0.01 })
	K:box("HotWaterTap", V3(0.12, 0.2, 0.18), pcf * CF(0, 0.62, 0.48), Look.black)
	K:box("HotWaterTray", V3(0.5, 0.05, 0.3), pcf * CF(0, 0.08, 0.5), Look.chrome)
end

local function pitchers(K: any, pcf: CFrame)
	for k = 0, 2 do
		local c = pcf * CF((k - 1) * 0.3, 0, (k % 2) * 0.08)
		K:vcyl("MilkPitcher", 0.34, 0.24, c * CF(0, 0.17, 0), Look.steel)
		K:box("MilkPitcherSpout", V3(0.06, 0.06, 0.08), c * CF(0, 0.32, 0.13), Look.steel)
	end
end

local function knockBox(K: any, pcf: CFrame)
	K:box("KnockBox", V3(0.55, 0.36, 0.5), pcf * CF(0, 0.18, 0), Look.black)
	K:cyl("KnockBar", 0.5, 0.07, pcf * CF(0, 0.33, 0), Look.rubber)
	K:box("KnockGrounds", V3(0.45, 0.02, 0.4), pcf * CF(0, 0.3, 0), lk(rgb(56, 36, 24), M.Ground))
end

local function canisters(K: any, pcf: CFrame, n: number, B: any)
	local cols = { B.c1, rgb(240, 240, 236), B.c2 or rgb(30, 30, 30) }
	for k = 1, n do
		local x = (k - (n + 1) / 2) * 0.42
		K:vcyl("TeaTin", 0.55, 0.34, pcf * CF(x, 0.275, 0), lk(cols[k % #cols + 1], M.Metal))
		K:vcyl("TeaTinLid", 0.08, 0.36, pcf * CF(x, 0.59, 0), Look.chrome)
	end
end

-- 드립 스테이션 (핸드드립 3구 + 주전자 + 저울)
local function dripStation(K: any, pcf: CFrame)
	K:box("DripStand", V3(1.5, 0.08, 0.5), pcf * CF(0, 0.75, 0), Look.walnut)
	for _, sx in { -1, 1 } do
		K:box("DripStandLeg", V3(0.08, 0.75, 0.45), pcf * CF(sx * 0.7, 0.375, 0), Look.walnut)
	end
	for k = -1, 1 do
		local c = pcf * CF(k * 0.48, 0, 0)
		K:vcyl("DripServer", 0.42, 0.3, c * CF(0, 0.21, 0), glassL(rgb(230, 236, 240), 0.5))
		K:vcyl("DripCoffee", 0.12, 0.26, c * CF(0, 0.07, 0), lk(rgb(70, 40, 22)))
		K:vcyl("Dripper", 0.3, 0.34, c * CF(0, 0.94, 0), lk(rgb(250, 250, 248)))
		K:vcyl("DripperCone", 0.15, 0.2, c * CF(0, 0.82, 0), lk(rgb(250, 250, 248)))
	end
	local kc = pcf * CF(0.95, 0, 0.05)
	K:box("DripScale", V3(0.4, 0.06, 0.4), kc * CF(0, 0.03, 0), Look.black)
	K:vcyl("Kettle", 0.42, 0.34, kc * CF(0, 0.27, 0), Look.blackMetal)
	K:seg("KettleSpout", (kc * CF(0, 0.2, 0.15)).Position, (kc * CF(0, 0.55, 0.45)).Position, 0.04, Look.blackMetal)
	K:bar("KettleHandle", (kc * CF(0, 0.45, -0.16)).Position, (kc * CF(0, 0.22, -0.26)).Position, 0.05, 0.08, Look.walnut)
end

-- 진열장 / 장비 스킨 ----------------------------------------------------------------------------------------
local function machineSkin(K: any, r: any, look: any)
	K:free(function()
		K:box("Skin" .. r.name, r.size + V3(0.03, 0.03, 0.03), CF(r.c), look)
	end)
end

-- 상업용 2그룹 에스프레소 머신 (EspressoBody 같은 자리 스킨): 스테인리스 몸통 (세로 모서리 둥글게) + 브랜드 색
--   옆판 · 손님 쪽 뒷판 (크롬 테 · 배지) + 윗면 컵 워머 그릴 + 직원 쪽 그룹별 버튼 패드 · 온수 꼭지 · 작업등.
--   C = faceCF(몸통 중심, n): +X = 폭, +Z = 손님 쪽. 원본 몸통은 스킨이 0.01 바깥으로 덮음 (그룹헤드 · 포터필터는 맵 그대로)
local ESP_MAKERS = { "ARDENTE", "SOLENNE", "VELARO" }
local STAINLESS = { c = rgb(206, 209, 213), m = M.Metal, r = 0.12 }
local function espressoSkin(K: any, V: any, B: any, e: any, n: Vector3, espL: any)
	local ax = if math.abs(n.Z) > 0.5 then V3(1, 0, 0) else V3(0, 0, 1)
	local W = math.abs(n.Z) * e.size.X + math.abs(n.X) * e.size.Z
	local Dd = math.abs(n.X) * e.size.X + math.abs(n.Z) * e.size.Z
	local H = e.size.Y
	local C = faceCF(e.c, n)
	local steel = STAINLESS
	local badge = if B.key == "mega" then "MGC" elseif B.key == "compose" then "COMPOSE" elseif B.key == "busan" then "051" else ESP_MAKERS[B.seed % #ESP_MAKERS + 1]
	local bz = Dd / 2 + 0.01
	-- 몸통 · 옆판 · 뒷판
	K:rbox("SkinEspressoBody", V3(H + 0.02, W + 0.02, Dd + 0.02), 0.11, C * ANG(0, 0, PI / 2), steel)
	for _, s in { -1, 1 } do
		K:box("EspressoSidePanel", V3(0.05, H - 0.22, Dd - 0.3), C * CF(s * (W / 2 + 0.03), -0.02, 0), espL)
		K:box("EspressoSideTrim", V3(0.06, 0.05, Dd - 0.26), C * CF(s * (W / 2 + 0.03), H / 2 - 0.13, 0), Look.chrome)
	end
	K:box("EspressoBackPanel", V3(W - 0.34, H - 0.44, 0.04), C * CF(0, -0.04, bz + 0.02), espL)
	for _, sy in { -1, 1 } do
		K:box("EspressoBackTrim", V3(W - 0.3, 0.05, 0.05), C * CF(0, -0.04 + sy * (H - 0.44) / 2, bz + 0.025), Look.chrome)
	end
	local bw = math.min(1.1, W * 0.42)
	K:panel("EspressoBadge", bw, 0.26, 0.03, 0.09, C * CF(0, 0.16, bz + 0.04), Look.chrome)
	K:text("EspressoBadgeText", bw * 0.84, 0.17, C * CF(0, 0.16, bz + 0.071), badge, { fg = if B.key == "mega" then rgb(30, 30, 30) else rgb(40, 40, 44), font = F.GothamBlack, d = 0.004 })
	if not lowD(K) then
		-- 아래 통풍 슬릿
		local ventL = lk(dk(espL.c, 0.35))
		for k = 0, 3 do
			K:box("EspressoVent", V3(W * 0.5, 0.03, 0.02), C * CF(0, -H / 2 + 0.36 + k * 0.08, bz + 0.045), ventL)
		end
	end
	-- 윗면: 컵 워머 트레이 + 그릴 홈 + 난간 + 데운 잔
	local tY = H / 2 + 0.01
	K:box("EspressoCupTray", V3(W - 0.18, 0.035, Dd - 0.2), C * CF(0, tY + 0.0175, 0), Look.chrome)
	if hi(K) then
		for k = 1, 5 do
			K:box("EspressoTrayGrille", V3(W - 0.42, 0.01, 0.03), C * CF(0, tY + 0.04, -Dd / 2 + 0.1 + k * (Dd - 0.2) / 6), Look.black)
		end
	end
	for _, s in { -1, 1 } do
		K:box("CupRail", V3(W - 0.2, 0.04, 0.04), C * CF(0, tY + 0.14, s * (Dd / 2 - 0.12)), Look.chrome)
		for _, sx in { -1, 1 } do
			K:vcyl("CupRailPost", 0.12, 0.04, C * CF(sx * (W / 2 - 0.12), tY + 0.08, s * (Dd / 2 - 0.12)), Look.chrome)
		end
	end
	for k = 0, 4 do
		local x = -W / 2 + 0.36 + k * (W - 0.72) / 4
		local zz = ((k % 2) - 0.5) * 0.36
		K:vcyl("WarmerCup", 0.2, 0.24, C * CF(x, tY + 0.135, zz), Look.white)
		if k % 2 == 0 then
			K:vcyl("WarmerCup", 0.2, 0.24, C * CF(x, tY + 0.335, zz) * ANG(PI, 0, 0), Look.white)
		end
	end
	-- 직원 쪽 (-Z): 그룹별 버튼 패드 · 압력계 · 온수 꼭지 · 스팀 완드 · 작업등
	local sz = -Dd / 2 - 0.01
	local groups = {}
	for _, g in V.byName.GroupHead or {} do
		if (g.c - e.c).Magnitude < 2.6 then
			table.insert(groups, (g.c - e.c):Dot(ax))
		end
	end
	if #groups == 0 then
		groups = { -W * 0.28, W * 0.28 }
	end
	local Cs = C * ANG(0, PI, 0)
	for _, gx in groups do
		K:box("EspressoKeypad", V3(0.44, 0.2, 0.03), C * CF(gx, 0.45, sz - 0.015), Look.black)
		for b = 0, 3 do
			K:box("EspressoKey", V3(0.07, 0.07, 0.02), C * CF(gx - 0.15 + b * 0.1, 0.45, sz - 0.035), if b == 0 then Look.ledBlue else Look.lampNeutral)
		end
		K:box("EspressoGroupCollar", V3(0.5, 0.06, 0.06), C * CF(gx, 0.3, sz - 0.03), Look.chrome)
	end
	for _, s in { -1, 1 } do
		local g = Cs * CF(s * 0.3, H / 2 - 0.3, Dd / 2 + 0.01)
		wdisc(K, "EspressoGauge", 0.24, 0.035, g, Look.chrome)
		wdisc(K, "EspressoGaugeFace", 0.19, 0.04, g, Look.white)
		K:box("EspressoGaugeNeedle", V3(0.015, 0.08, 0.01), g * CF(0.01, 0.025, 0.045) * ANG(0, 0, -0.6), Look.ledRed)
	end
	K:seg("EspressoHotWater", C * V3(0, 0.12, sz), C * V3(0, -0.12, sz - 0.18), 0.06, Look.chrome)
	for _, s in { -1, 1 } do
		local a = C * V3(s * (W / 2 - 0.12), H / 2 - 0.34, sz - 0.02)
		local b2 = a + Vector3.yAxis * -0.8 + ax * s * 0.08 + n * -0.2
		K:seg("SteamWand", a, b2, 0.05, Look.chrome)
		K:seg("SteamKnob", a + Vector3.yAxis * 0.16, a + Vector3.yAxis * 0.16 - n * 0.14, 0.11, Look.black)
		K:ball("SteamKnobCap", 0.12, CF(a + Vector3.yAxis * 0.16 - n * 0.15), Look.chrome)
	end
	K:box("EspressoWorkLED", V3(W - 0.5, 0.03, 0.03), C * CF(0, H / 2 - 0.16, sz - 0.02), Look.lampNeutral)
end

-- 그라인더 (Grinder + GrinderHopper): 몸통 둥근 상자 · 직원 쪽 배출구 · 포터필터 거치 포크 · LCD · 손님 쪽 배지,
--   호퍼는 같은 자세 스모크 아크릴 + 원두 + 검은 뚜껑으로 다시 입히고 원본 숨김
local function grinderSkin(K: any, V: any, B: any, r: any, n: Vector3, bodyL: any)
	local w = math.abs(n.Z) * r.size.X + math.abs(n.X) * r.size.Z
	local d = math.abs(n.X) * r.size.X + math.abs(n.Z) * r.size.Z
	local h = r.size.Y
	local C = faceCF(r.c, n)
	K:rbox("SkinGrinder", V3(h + 0.02, w + 0.02, d + 0.02), 0.09, C * ANG(0, 0, PI / 2), bodyL)
	local sz = -d / 2 - 0.01
	K:box("GrinderChute", V3(0.2, 0.16, 0.14), C * CF(0, h * 0.12, sz - 0.07), Look.chrome)
	for _, s in { -1, 1 } do
		K:box("GrinderFork", V3(0.04, 0.04, 0.3), C * CF(s * 0.12, -h * 0.05, sz - 0.15), Look.chrome)
	end
	K:box("GrinderTray", V3(0.46, 0.03, 0.26), C * CF(0, -h / 2 + 0.2, sz - 0.12), Look.chrome)
	K:text("GrinderLCD", 0.32, 0.14, C * ANG(0, PI, 0) * CF(0, h * 0.32, d / 2 + 0.012), "18.5g", { fg = rgb(120, 210, 255), bg = rgb(10, 14, 20), glow = 1.2, font = F.Code, d = 0.006 })
	K:box("GrinderButton", V3(0.1, 0.06, 0.02), C * CF(0, h * 0.22, sz - 0.01), Look.ledGreen)
	K:panel("GrinderBadge", 0.42, 0.13, 0.02, 0.05, C * CF(0, h * 0.25, d / 2 + 0.01), Look.chrome)
	K:text("GrinderBadgeText", 0.36, 0.09, C * CF(0, h * 0.25, d / 2 + 0.032), "MILL·64", { fg = rgb(40, 40, 44), font = F.GothamBlack, d = 0.003 })
	local hop = nil
	for _, q in V.byName.GrinderHopper or {} do
		if math.abs(q.c.X - r.c.X) < 0.5 and math.abs(q.c.Z - r.c.Z) < 0.5 then
			hop = q
		end
	end
	if hop then
		K:box("GrinderHopperSkin", hop.size, CF(hop.c), glassL(rgb(70, 56, 48), 0.42))
		K:box("GrinderBeans", V3(hop.size.X - 0.08, hop.size.Y * 0.56, hop.size.Z - 0.08), CF(hop.c - V3(0, hop.size.Y * 0.2, 0)), lk(rgb(74, 44, 26), M.Pebble))
		K:box("GrinderLid", V3(hop.size.X + 0.02, 0.07, hop.size.Z + 0.02), CF(hop.c.X, hop.max.Y - 0.035, hop.c.Z), Look.blackMetal)
		K:vcyl("GrinderLidKnob", 0.05, 0.16, CF(hop.c.X, hop.max.Y - 0.01, hop.c.Z), Look.chrome)
		Scan.hide(K.hidden, hop.part)
	end
end

-- 와플 기계 (같은 자세): 스테인리스 받침 (둥근 모서리) + 직원 쪽 검은 조작판 (온도 다이얼 · 램프 2) +
--   주물 아래판 + 둥근 주물 뚜껑 (격자) + 경첩 + 베이클라이트 손잡이. face = 손잡이 쪽 (직원)
local function waffleMaker(K: any, cf: CFrame, w: number, h: number, d: number, lidD: number, lidH: number, decor: boolean)
	-- cf: 받침 바닥 가운데, +Z = 손잡이 쪽
	K:rbox(if decor then "WaffleDecorBase" else "WaffleBase", V3(h, w, d), 0.07, cf * CF(0, h / 2, 0) * ANG(0, 0, PI / 2), STAINLESS)
	K:plate("WaffleControl", w * 0.7, h * 0.62, 0.02, cf * CF(0, h * 0.5, d / 2), Look.black)
	wdisc(K, "WaffleDial", 0.16, 0.04, cf * CF(-w * 0.18, h * 0.5, d / 2 + 0.02), Look.chrome)
	K:plate("WaffleLamp", 0.07, 0.05, 0.02, cf * CF(w * 0.12, h * 0.55, d / 2 + 0.02), Look.ledRed)
	K:plate("WaffleLamp", 0.07, 0.05, 0.02, cf * CF(w * 0.24, h * 0.55, d / 2 + 0.02), Look.ledGreen)
	K:box("WafflePlate", V3(w - 0.14, 0.04, d - 0.14), cf * CF(0, h - 0.015, 0), Look.of(52, 52, 56, Enum.Material.DiamondPlate))
	local lc = cf * CF(0, h + lidH / 2, 0)
	K:disc("WaffleLid", lidD, lidH, lc, Look.of(40, 40, 44, Enum.Material.Metal))
	K:disc("WaffleLidTop", lidD * 0.82, 0.02, lc * CF(0, lidH / 2 + 0.01, 0), Look.of(28, 28, 30, Enum.Material.Metal))
	for k = -1, 1 do
		K:box("WaffleGrid", V3(lidD * 0.6, 0.012, 0.03), lc * CF(0, lidH / 2 + 0.025, k * lidD * 0.16), Look.of(60, 60, 64))
		K:box("WaffleGrid", V3(0.03, 0.012, lidD * 0.6), lc * CF(k * lidD * 0.16, lidH / 2 + 0.025, 0), Look.of(60, 60, 64))
	end
	K:box("WaffleHinge", V3(0.3, 0.1, 0.08), cf * CF(0, h + 0.03, -d / 2 + 0.06), Look.chrome)
	K:box("WaffleHandleArm", V3(0.06, 0.05, 0.16), cf * CF(0, h + lidH / 2, d / 2 - 0.12), Look.chrome)
	K:box("WaffleHandle", V3(0.42, 0.08, 0.09), cf * CF(0, h + lidH / 2, d / 2 - 0.05), Look.black)
end

-- 뒷선반 작업 스테이션 소품 (와플 · 탕후루 가게: 맵 Cup 자리를 맛집 작업대로) — pcf: 선반 윗면, +Z = 손님 쪽
local function batterJug(K: any, pcf: CFrame)
	K:vcyl("BatterJug", 0.62, 0.4, pcf * CF(0, 0.31, 0), glassL(rgb(244, 240, 230), 0.35))
	K:vcyl("BatterFill", 0.42, 0.36, pcf * CF(0, 0.22, 0), lk(rgb(236, 206, 150)))
	K:vcyl("BatterLid", 0.06, 0.42, pcf * CF(0, 0.65, 0), Look.white)
	K:seg("BatterSpout", pcf * V3(0.18, 0.5, 0), pcf * V3(0.3, 0.58, 0), 0.07, Look.white)
	K:seg("BatterLadle", pcf * V3(-0.05, 0.4, 0), pcf * V3(-0.12, 0.95, 0.05), 0.04, Look.chrome)
end
local function creamMachine(K: any, pcf: CFrame)
	K:box("CreamBase", V3(0.5, 0.12, 0.5), pcf * CF(0, 0.06, 0), STAINLESS)
	K:vcyl("CreamTank", 0.62, 0.42, pcf * CF(0, 0.43, 0), STAINLESS)
	K:vcyl("CreamCap", 0.08, 0.44, pcf * CF(0, 0.78, 0), Look.white)
	K:seg("CreamNozzle", pcf * V3(0, 0.32, 0.2), pcf * V3(0, 0.22, 0.36), 0.08, Look.chrome)
	K:text("CreamLabel", 0.32, 0.12, pcf * CF(0, 0.5, 0.215), "WHIP 4℃", { fg = rgb(120, 210, 255), bg = rgb(16, 20, 26), glow = 1.1, font = F.Code, d = 0.005 })
end
local function insertPans(K: any, pcf: CFrame, cols: { Color3 }, ball: boolean)
	local n = #cols
	local pw = 0.34
	K:box("PanFrame", V3(n * (pw + 0.04) + 0.06, 0.08, 0.6), pcf * CF(0, 0.04, 0), Look.steel)
	for k = 1, n do
		local x = (k - (n + 1) / 2) * (pw + 0.04)
		K:box("InsertPan", V3(pw, 0.12, 0.52), pcf * CF(x, 0.14, 0), Look.chrome)
		K:box("PanFill", V3(pw - 0.05, 0.03, 0.46), pcf * CF(x, 0.2, 0), lk(cols[k], M.Pebble))
		if ball and hi(K) then
			for j = 0, 2 do
				K:ball("PanFruit", 0.13, pcf * CF(x + ((j % 2) - 0.5) * 0.12, 0.25, -0.14 + j * 0.14), lk(cols[k]))
			end
		end
	end
end
local function sugarStation(K: any, pcf: CFrame)
	K:box("Induction", V3(1.0, 0.1, 0.9), pcf * CF(0, 0.05, 0), Look.black)
	K:plate("InductionRing", 0.5, 0.5, 0.005, topCF((pcf * CF(0, 0.101, 0)).Position, -pcf.ZVector), Look.of(70, 70, 76))
	K:plate("InductionLED", 0.2, 0.05, 0.01, pcf * CF(0.32, 0.05, 0.45), Look.ledRed)
	K:vcyl("SugarPot", 0.42, 0.62, pcf * CF(0, 0.31, 0), STAINLESS)
	K:vcyl("SugarSyrup", 0.03, 0.56, pcf * CF(0, 0.5, 0), lk(rgb(236, 170, 60), M.Glass, { t = 0.15 }))
	K:seg("SugarPotHandle", pcf * V3(0.31, 0.42, 0), pcf * V3(0.7, 0.44, 0.05), 0.06, Look.black)
	K:seg("DipSkewer", pcf * V3(-0.1, 0.45, 0), pcf * V3(-0.22, 1.15, 0.08), 0.03, lk(rgb(224, 202, 160), M.Wood))
end
local function skewerCup(K: any, pcf: CFrame)
	K:vcyl("SkewerCup", 0.4, 0.3, pcf * CF(0, 0.2, 0), Look.white)
	for k = 0, 8 do
		local a = k * 0.7
		K:seg("Skewer", pcf * V3(math.cos(a) * 0.06, 0.1, math.sin(a) * 0.06), pcf * V3(math.cos(a) * 0.12, 1.05, math.sin(a) * 0.12), 0.025, lk(rgb(224, 202, 160), M.Wood))
	end
end
local function fruitCrate(K: any, pcf: CFrame, c: Color3, label: string)
	K:box("FruitCrate", V3(1.0, 0.32, 0.7), pcf * CF(0, 0.16, 0), lk(rgb(246, 244, 238), M.Cardboard))
	K:box("FruitCrateBand", V3(1.02, 0.1, 0.72), pcf * CF(0, 0.26, 0), lk(c))
	for k = 0, 5 do
		K:ball("CrateFruit", 0.2, pcf * CF(-0.33 + (k % 3) * 0.33, 0.34, -0.14 + math.floor(k / 3) * 0.28), lk(c))
	end
	K:text("FruitCrateLabel", 0.8, 0.13, pcf * CF(0, 0.12, 0.355), label, { fg = dk(c, 0.3), font = F.GothamBold, d = 0.004 })
end
local function sugarSack(K: any, pcf: CFrame)
	K:box("SugarSack", V3(0.9, 0.5, 0.42), pcf * CF(0, 0.25, 0), lk(rgb(246, 244, 240), M.Fabric))
	K:box("SugarSackFold", V3(0.92, 0.08, 0.3), pcf * CF(0, 0.52, -0.04), lk(rgb(232, 230, 224), M.Fabric))
	K:text("SugarSackLabel", 0.74, 0.26, pcf * CF(0, 0.26, 0.215), "백설탕\n15kg", { fg = rgb(30, 90, 170), font = F.GothamBlack, d = 0.004 })
end

-- 젤라또 맛
local FLAVORS = {
	{ "피스타치오", rgb(156, 186, 104) }, { "바닐라빈", rgb(248, 238, 206) }, { "다크초코", rgb(88, 54, 36) }, { "생딸기", rgb(240, 130, 150) },
	{ "애플망고", rgb(250, 184, 60) }, { "그릭요거트", rgb(250, 250, 244) }, { "흑임자", rgb(92, 88, 86) }, { "레몬셔벗", rgb(250, 236, 120) },
	{ "쑥 인절미", rgb(150, 168, 104) }, { "솔티드카라멜", rgb(212, 150, 80) }, { "민트초코", rgb(170, 230, 210) }, { "블루베리", rgb(120, 96, 168) },
}

-- 탕후루 꼬치: base = 막대 아래 끝 (축 +Y)
local FRUIT: { [string]: any } = {
	strawberry = { c = rgb(214, 28, 48), d = 0.24, n = 4, ell = true },
	grape = { c = rgb(160, 206, 80), d = 0.2, n = 5 },
	blueberry = { c = rgb(60, 60, 120), d = 0.13, n = 7 },
	mandarin = { c = rgb(250, 146, 28), d = 0.25, n = 3 },
	kiwi = { c = rgb(130, 180, 50), d = 0.22, n = 4, ell = true },
	tomato = { c = rgb(232, 44, 36), d = 0.17, n = 5 },
	pineapple = { c = rgb(250, 206, 60), d = 0.21, n = 4, cube = true },
}
local FRUIT_ORDER = { "strawberry", "grape", "blueberry", "mandarin", "kiwi", "tomato", "pineapple" }
local function skewer(K: any, base: CFrame, kind: string, len: number)
	local f = FRUIT[kind] or FRUIT.strawberry
	K:vcyl("TangStick", len, 0.04, base * CF(0, len / 2, 0), lk(rgb(224, 202, 160), M.Wood))
	local y = len - 0.06
	local candy = lk(f.c, M.Glass, { t = 0.04, r = 0.22 })
	for _ = 1, f.n do
		local p = base * CF(0, y - f.d / 2, 0)
		if f.cube then
			K:box("TangFruit", V3(f.d, f.d, f.d) * 0.9, p * ANG(0, 0.6, 0), candy)
		elseif f.ell then
			K:ell("TangFruit", V3(f.d, f.d * 1.15, f.d), p, candy)
		else
			K:ball("TangFruit", f.d, p, candy)
		end
		y -= f.d * 0.98
	end
end

-- 생과일 진열대 (3단 나무 상자 + 과일 + 가격 카드): 탕후루 · 디저트 가게 가운데
local function fruitStand(K: any, pcf: CFrame, w: number, B: any)
	local d = 2.2
	local wood = Look.pine
	local tiers = { { 0.55, 0.55 }, { 1.35, 0.0 }, { 2.15, -0.55 } }
	-- 계단형 옆판 (앞이 낮고 뒤가 높음)
	for _, sx in { -1, 1 } do
		for _, t in tiers do
			K:box("FruitStandSide", V3(0.12, t[1] + 0.08, 0.6), pcf * CF(sx * (w / 2 - 0.06), (t[1] + 0.08) / 2, t[2]), Look.walnut)
		end
	end
	local kinds = { { "strawberry", "생딸기 500g", "9,900" }, { "grape", "샤인머스캣 1송이", "12,000" }, { "mandarin", "제주 귤 1kg", "6,900" }, { "blueberry", "블루베리 200g", "7,900" }, { "kiwi", "골드키위 5입", "6,500" }, { "tomato", "대추방울토마토", "5,900" } }
	local idx = 0
	for _, t in tiers do
		local y, z = t[1], t[2]
		K:box("FruitStandShelf", V3(w - 0.24, 0.08, 1.0), pcf * CF(0, y, z), wood)
		local n = 2
		for k = 1, n do
			idx += 1
			local info = kinds[(idx + B.seed) % #kinds + 1]
			local f = FRUIT[info[1]]
			local x = -(w - 0.4) / 2 + (w - 0.4) * (k - 0.5) / n
			local c = pcf * CF(x, y + 0.04, z)
			local cw = (w - 0.6) / n
			K:box("FruitCrate", V3(cw, 0.06, 0.85), c * CF(0, 0.03, 0), wood)
			for _, sz in { -1, 1 } do
				K:box("FruitCrateSide", V3(cw, 0.28, 0.06), c * CF(0, 0.14, sz * 0.4), wood)
			end
			for _, sx in { -1, 1 } do
				K:box("FruitCrateSide", V3(0.06, 0.28, 0.8), c * CF(sx * (cw / 2 - 0.03), 0.14, 0), wood)
			end
			local look = lk(f.c, M.SmoothPlastic, { r = 0.04 })
			local fd = math.max(f.d, 0.18)
			local nx = math.max(2, math.floor((cw - 0.15) / fd))
			for j = 0, nx - 1 do
				for q = 0, 2 do
					local p = c * CF(-cw / 2 + 0.1 + fd * (j + 0.5), 0.12 + fd * 0.45 + (q % 2) * 0.04, -0.28 + q * 0.28)
					if f.ell then
						K:ell("CrateFruit", V3(fd, fd * 1.1, fd), p, look)
					else
						K:ball("CrateFruit", fd, p, look)
					end
				end
			end
			local cardP = faceCF((c * CF(0, 0.22, 0.44)).Position, pcf.ZVector)
			K:text("FruitCard", cw * 0.8, 0.26, cardP, info[2] .. "  " .. info[3], { fg = rgb(40, 30, 20), bg = rgb(255, 250, 236), d = 0.01, font = F.GothamBold })
		end
	end
	K:text("FruitStandHead", w - 0.3, 0.36, faceCF((pcf * CF(0, 2.75, -0.45)).Position, pcf.ZVector), "오늘 들어온 생과일", { fg = onColor(B.c1), bg = B.c1, d = 0.04, font = F.GothamBlack })
end

-- 인형 (곰 · 토끼 · 병아리): c 중심, s 크기, face = 앞 방향
local function plush(K: any, c: Vector3, s: number, kind: number, col: Color3, face: Vector3)
	local pcf = facing(c - V3(0, s * 0.45, 0), face)
	local fur = lk(col, M.Fabric)
	K:ell("PlushBody", V3(0.8, 0.7, 0.7) * s, pcf * CF(0, s * 0.32, 0), fur)
	K:ball("PlushHead", 0.62 * s, pcf * CF(0, s * 0.8, 0.03 * s), fur)
	if kind == 1 then
		for _, sx in { -1, 1 } do
			K:ell("PlushEar", V3(0.14, 0.42, 0.1) * s, pcf * CF(sx * 0.14 * s, s * 1.2, 0), fur)
		end
	elseif kind == 2 then
		K:wedge("PlushBeak", V3(0.12, 0.08, 0.14) * s, pcf * CF(0, s * 0.78, 0.33 * s), lk(rgb(250, 150, 40)))
	else
		for _, sx in { -1, 1 } do
			K:ball("PlushEar", 0.2 * s, pcf * CF(sx * 0.22 * s, s * 1.06, 0), fur)
		end
		if hi(K) then
			K:ell("PlushMuzzle", V3(0.24, 0.16, 0.12) * s, pcf * CF(0, s * 0.74, 0.3 * s), lk(lt(col, 0.5), M.Fabric))
		end
	end
	if not lowD(K) then
		for _, sx in { -1, 1 } do
			K:ball("PlushEye", 0.07 * s, pcf * CF(sx * 0.11 * s, s * 0.86, 0.3 * s), Look.black)
		end
	end
end

-- 아이스크림 냉동고 (유리 뚜껑 + 속 상자들 + 할인 띠). 반환 뚜껑 파트
local function freezerChest(K: any, pcf: CFrame, w: number, B: any, title: string): BasePart
	if not room(K, 60) then
		return nil :: any
	end
	local d, h = 1.7, 2.7
	K:box("FreezerBody", V3(w, h - 0.3, d), pcf * CF(0, 0.3 + (h - 0.3) / 2, 0), Look.white)
	K:box("FreezerKick", V3(w - 0.1, 0.3, d - 0.1), pcf * CF(0, 0.15, 0), Look.grey)
	K:box("FreezerStripe", V3(w + 0.01, 0.45, d + 0.01), pcf * CF(0, h - 0.6, 0), lk(B.c1))
	K:text("FreezerTitle", w * 0.8, 0.36, faceCF((pcf * CF(0, h - 0.6, d / 2 + 0.01)).Position, pcf.ZVector), title, { fg = onColor(B.c1), font = F.GothamBlack, d = 0.01 })
	K:text("FreezerPrice", w * 0.7, 0.5, faceCF((pcf * CF(0, 1.2, d / 2 + 0.01)).Position, pcf.ZVector), "아이스크림 전 품목 50%\n파인트 16,000", { fg = rgb(220, 30, 40), bg = rgb(255, 250, 236), font = F.GothamBold, d = 0.02 })
	K:box("FreezerInner", V3(w - 0.2, 0.05, d - 0.2), pcf * CF(0, h - 0.4, 0), lk(rgb(220, 236, 244)))
	local cols = { rgb(250, 200, 210), rgb(160, 210, 250), rgb(250, 230, 150), rgb(200, 240, 200), rgb(110, 70, 50), rgb(250, 250, 244) }
	local n = math.max(3, math.floor((w - 0.3) / 0.45))
	for k = 1, n do
		for j = 0, 1 do
			local x = -(w - 0.3) / 2 + (w - 0.3) * (k - 0.5) / n
			local c = cols[(k + j * 3) % #cols + 1]
			if (k + j) % 3 == 0 then
				K:vcyl("FreezerPint", 0.36, 0.34, pcf * CF(x, h - 0.2, (j - 0.5) * 0.7), lk(c))
			else
				K:box("FreezerBar", V3(0.36, 0.14, 0.5), pcf * CF(x, h - 0.3, (j - 0.5) * 0.7) * ANG(0, 0.15 * (k % 3 - 1), 0), lk(c))
			end
		end
	end
	K:box("FreezerRim", V3(w, 0.06, 0.08), pcf * CF(0, h + 0.03, d / 2 - 0.04), Look.grey)
	K:box("FreezerRim", V3(w, 0.06, 0.08), pcf * CF(0, h + 0.03, -d / 2 + 0.04), Look.grey)
	local lid = K:box("FreezerLid", V3(w / 2, 0.04, d - 0.1), pcf * CF(-w / 4, h + 0.05, 0), glassL(rgb(220, 236, 244), 0.6))
	K:box("FreezerLid", V3(w / 2, 0.04, d - 0.1), pcf * CF(w / 4, h + 0.09, 0), glassL(rgb(220, 236, 244), 0.6))
	return lid
end

-- 픽업 전광판 (천장에 매닮). x, z 로컬, n = 손님 쪽 방향
local function pickupBoard(K: any, x: number, z: number, n: Vector3, B: any)
	local V = K.V
	local y = V.H - 1.05
	local c = facing(V3(x, y, z), n)
	K:free(function()
		for _, sx in { -1, 1 } do
			K:seg("PickupRod", (c * CF(sx * 0.9, 0.45, 0)).Position, V3(x, V.H, z) + (c.XVector * sx * 0.9), 0.05, Look.blackMetal)
		end
	end)
	K:box("PickupBox", V3(2.4, 0.9, 0.18), c, Look.black)
	K:text("PickupHead", 0.9, 0.3, c * CF(-0.62, 0.18, 0.095), "PICK UP", { fg = B.c1, glow = 1.4, font = F.GothamBlack, d = 0.005 })
	local scr, lab = K:text("PickupNo", 1.1, 0.5, c * CF(0.55, 0, 0.095), "0127", { fg = rgb(255, 60, 40), bg = rgb(8, 8, 8), glow = 1.6, font = F.Code, d = 0.005 })
	K:text("PickupSub", 0.9, 0.18, c * CF(-0.62, -0.2, 0.095), "음료가 준비되었습니다", { fg = rgb(230, 230, 230), glow = 1.1, font = F.Gotham, d = 0.005 })
	local frames = {}
	for k = 0, 7 do
		table.insert(frames, { text = string.format("%04d", 127 + k * 3 + (k % 2)) })
	end
	Interact.screenLoop(K, nil, lab, frames, 6)
	return scr
end

-- 화면 (TV 메뉴 · 프로모): 프레임 순환
local function promoScreen(K: any, dcf: CFrame, w: number, frames: { any })
	if not room(K, 4) then
		return
	end
	local h = w * 9 / 16
	K:plate("ScreenMount", w * 0.3, h * 0.3, 0.1, dcf, Look.blackMetal)
	K:plate("ScreenBody", w + 0.1, h + 0.1, 0.12, dcf * CF(0, 0, 0.1), Look.black)
	local scr, lab = K:text("PromoScreen", w, h, dcf * CF(0, 0, 0.22), frames[1].text, { fg = frames[1].fg or rgb(255, 255, 255), bg = frames[1].c or rgb(30, 30, 30), glow = 1.15, font = F.GothamBlack, d = 0.02 })
	Interact.anim(K, function(t: number)
		local i = math.floor(t / 5) % #frames + 1
		local f = frames[i]
		if lab.Parent then
			lab.Text = f.text
			lab.BackgroundColor3 = f.c or rgb(30, 30, 30)
			lab.TextColor3 = f.fg or rgb(255, 255, 255)
		end
	end)
	return scr
end

-- 덕트 (스파이럴 원형 덕트 + 행거 + 디퓨저): 천장 아래 z 줄을 따라 빈 구간만
local function ducts(K: any, V: any)
	if not room(K, 80) then
		return
	end
	local dia = 1.1
	local y = V.H - 0.95
	local best, bz = -1, nil
	local function blocked(x: number, z: number): boolean
		for _, r in V.hang do
			if x > r.min.X - 0.8 and x < r.max.X + 0.8 and z > r.min.Z - 0.8 and z < r.max.Z + 0.8 and r.max.Y > y - 0.7 then
				return true
			end
		end
		return false
	end
	local z = V.z0 + 2.0
	while z < V.z1 - 3.0 do
		local free, run = 0, 0
		for x = V.x0 + 1, V.x1 - 1, 0.5 do
			if blocked(x, z) then
				run = 0
			else
				run += 0.5
				free = math.max(free, run)
			end
		end
		if free > best + 0.6 then
			best, bz = free, z
		end
		z += 0.5
	end
	if not bz or best < 6 then
		return
	end
	-- 가장 긴 빈 구간
	local runs, cur = {}, nil
	for x = V.x0 + 1, V.x1 - 1, 0.5 do
		if blocked(x, bz) then
			cur = nil
		else
			if not cur then
				cur = { x, x }
				table.insert(runs, cur)
			end
			cur[2] = x
		end
	end
	local look = lk(rgb(196, 198, 200), M.Metal, { r = 0.1 })
	K:free(function()
		for _, rr in runs do
			if rr[2] - rr[1] >= 5 then
				local a, b = V3(rr[1], y, bz), V3(rr[2], y, bz)
				K:seg("Duct", a, b, dia, look)
				local n = math.floor((rr[2] - rr[1]) / 2.0)
				for k = 0, n do
					local x = rr[1] + (rr[2] - rr[1]) * k / math.max(1, n)
					K:cyl("DuctSeam", 0.06, dia + 0.04, CF(x, y, bz), look)
					if k % 2 == 0 then
						K:seg("DuctHanger", V3(x, y + dia / 2, bz), V3(x, V.H, bz), 0.04, Look.blackMetal)
						K:bar("DuctStrap", V3(x - 0.04, y + dia / 2 + 0.02, bz - dia / 2), V3(x - 0.04, y + dia / 2 + 0.02, bz + dia / 2), 0.05, 0.03, Look.blackMetal)
					end
					if k % 3 == 1 then
						K:vcyl("DuctDiffuserNeck", 0.3, 0.5, CF(x, y - dia / 2 - 0.1, bz), look)
						K:disc("DuctDiffuser", 0.8, 0.08, CF(x, y - dia / 2 - 0.28, bz), look)
					end
				end
				K:disc("DuctCap", dia + 0.06, 0.08, CF(a) * ANG(0, 0, PI / 2), look)
				K:disc("DuctCap", dia + 0.06, 0.08, CF(b) * ANG(0, 0, PI / 2), look)
			end
		end
		-- 케이블 트레이 (덕트 옆)
		local tz = bz + dia / 2 + 0.6
		for _, rr in runs do
			if rr[2] - rr[1] >= 5 then
				K:box("CableTray", V3(rr[2] - rr[1], 0.08, 0.5), CF((rr[1] + rr[2]) / 2, V.H - 0.4, tz), Look.blackMetal)
				K:seg("CableBundle", V3(rr[1], V.H - 0.33, tz), V3(rr[2], V.H - 0.33, tz), 0.12, Look.black)
			end
		end
	end)
end

-- 행잉 화분 (천장 줄 + 화분 + 늘어진 잎)
local function hangingPlant(K: any, x: number, z: number, drop: number)
	if not room(K, 28) then
		return
	end
	local V = K.V
	local y = V.H - drop
	K:free(function()
		for k = 0, 2 do
			local a = k * 2 * PI / 3
			K:seg("HangCord", V3(x, V.H, z), V3(x + math.cos(a) * 0.3, y + 0.5, z + math.sin(a) * 0.3), 0.03, Look.of(200, 190, 170, Enum.Material.Fabric))
		end
		K:vcyl("HangPot", 0.5, 0.65, CF(x, y + 0.25, z), Look.terracotta)
		K:disc("HangSoil", 0.58, 0.02, CF(x, y + 0.5, z), Look.soil)
		for k = 0, 6 do
			local a = k * 2 * PI / 7
			local len = 0.8 + (k % 3) * 0.45
			local p0 = V3(x + math.cos(a) * 0.3, y + 0.5, z + math.sin(a) * 0.3)
			local p1 = V3(x + math.cos(a) * 0.55, y + 0.4 - len, z + math.sin(a) * 0.55)
			K:seg("HangVine", p0, p1, 0.03, Look.leafDark)
			K:ell("HangLeaf", V3(0.3, 0.12, 0.22), CF(p1) * ANG(0, a, 0.4), if k % 2 == 0 then Look.leaf else Look.leafLight)
			K:ell("HangLeaf", V3(0.26, 0.1, 0.2), CF(p0:Lerp(p1, 0.5)) * ANG(0, a + 1, -0.3), Look.leaf)
		end
		K:ell("HangTuft", V3(0.8, 0.35, 0.8), CF(x, y + 0.62, z), Look.leaf)
	end)
end

-- 벽 스킨 (문 · 개구부 피함): wn 벽, look
local function wallSkin(K: any, V: any, wn: string, look: any)
	local wall = V.walls[wn]
	if not wall then
		return
	end
	local cuts = {}
	for _, nm in { "DoorCasing", "DoorLeaf", "Door", "GlassDoor" } do
		for _, r in V.byName[nm] or {} do
			local u0, d0 = V:wallCoord(wn, r.min)
			local u1, d1 = V:wallCoord(wn, r.max)
			if math.min(d0, d1) < 0.6 then
				table.insert(cuts, { math.min(u0, u1) - 0.12, math.max(u0, u1) + 0.12, r.max.Y + 0.1 })
			end
		end
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local H = V.H - 0.04
	K:free(function()
		local cur = wall.a
		for _, c in cuts do
			if c[1] > cur + 0.05 then
				K:plate("WallSkin", c[1] - cur, H, 0.012, V:wall(wn, (cur + c[1]) / 2, H / 2, 0.004), look)
			end
			if H > c[3] + 0.05 then
				K:plate("WallSkin", c[2] - math.max(cur, c[1]), H - c[3], 0.012, V:wall(wn, (math.max(cur, c[1]) + c[2]) / 2, c[3] + (H - c[3]) / 2, 0.004), look)
			end
			cur = math.max(cur, c[2])
		end
		if wall.b > cur + 0.05 then
			K:plate("WallSkin", wall.b - cur, H, 0.012, V:wall(wn, (cur + wall.b) / 2, H / 2, 0.004), look)
		end
	end)
end


-- 단계 ------------------------------------------------------------------------------------------------------

local function context(K: any, V: any, B: any): any
	local ctx: any = { boards = {} }
	local pos = V:first("PosBase") or V:first("OrderKiosk") or V:first("CashierPanel")
	ctx.pos = pos
	local main = nil
	if pos then
		for _, g in V.counters do
			if pos.c.X >= g.min.X - 0.6 and pos.c.X <= g.max.X + 0.6 and pos.c.Z >= g.min.Z - 0.9 and pos.c.Z <= g.max.Z + 0.9 then
				main = g
			end
		end
	end
	if not main then
		local best = 0
		for _, g in V.counters do
			local a = (g.max.X - g.min.X) * (g.max.Z - g.min.Z)
			if a > best then
				best, main = a, g
			end
		end
	end
	ctx.main = main
	ctx.esp = V.byName.EspressoBody or {}
	ctx.cx, ctx.cz = (V.x0 + V.x1) / 2, (V.z0 + V.z1) / 2
	if main then
		ctx.n = custDir(V, main)
		for _, g in V.counters do
			if g ~= main then
				local behind = if ctx.n.Z > 0.5 then g.max.Z <= main.min.Z + 0.3 elseif ctx.n.Z < -0.5 then g.min.Z >= main.max.Z - 0.3 else false
				if behind then
					ctx.back = g
				end
			end
		end
		local alongX = math.abs(ctx.n.Z) > 0.5
		local lo = if alongX then main.min.X else main.min.Z
		local hi2 = if alongX then main.max.X else main.max.Z
		local pu = if pos then (if alongX then pos.c.X else pos.c.Z) else lo
		ctx.alongX = alongX
		ctx.posU = pu
		ctx.pickU = if math.abs(pu - lo) < math.abs(pu - hi2) then hi2 - 1.0 else lo + 1.0
	end
	-- 뒷벽에 맵 간판이 있나 (브랜드 로고 중복 피함)
	for _, r in V.parts do
		if r.shell and string.sub(r.name, 1, 5) == "Sign_" and r.c.Z < V.z0 + 0.8 and not string.find(r.name, "화장실", 1, true) then
			ctx.backSign = r
		end
	end
	return ctx
end

-- 1) 맵 간판 자리 등록
local function stepShell(K: any, V: any, B: any, _ctx: any)
	for _, r in V.parts do
		if r.shell and string.sub(r.name, 1, 5) == "Sign_" then
			for _, wn in { "back", "left", "right" } do
				local u0, d0 = V:wallCoord(wn, r.min)
				local u1, d1 = V:wallCoord(wn, r.max)
				local dmin = math.min(d0, d1)
				if dmin < 0.9 and dmin > -0.8 then
					useWall(K, wn, math.min(u0, u1) - 0.25, math.max(u0, u1) + 0.25, r.min.Y - 0.2, r.max.Y + 0.2)
				end
			end
		end
	end
	-- 벽 전체 스킨 (브랜드)
	if B.wall then
		for wn, look in B.wall do
			wallSkin(K, V, wn, look)
		end
	end
end

local function uOf(V: any, wn: string, x: number, z: number): number
	local u = V:wallCoord(wn, V3(x, 0, z))
	return u
end

-- 2) 바닥 소품
local function stepFloor(K: any, V: any, B: any, ctx: any)
	local feat = B.feat or {}
	ctx.placed = ctx.placed or {}
	local function mark(name: string, cf: CFrame?)
		if cf then
			table.insert(ctx.placed, name .. ctx.where(cf))
		end
	end
	local main = ctx.main
	local small = V.W * V.D < 180
	-- 셀프바 · 냉장고는 픽업 쪽 옆벽, MD 는 반대쪽
	local pickSide = "right"
	if main and ctx.alongX then
		pickSide = if ctx.pickU > ctx.cx then "right" else "left"
	elseif main then
		pickSide = if (main.min.X + main.max.X) / 2 > 0 then "right" else "left"
	end
	local other = if pickSide == "right" then "left" else "right"
	local zT = if main then math.min(V.z1 - 4, main.max.Z + 2.4) else V.z0 + V.D * 0.45
	local pref = { [pickSide] = uOf(V, pickSide, 0, zT), [other] = uOf(V, other, 0, zT + 1.5), back = 0 }

	if feat.roaster then
		local wn, pcf = floorFind(K, { "back", "left", "right" }, 3.9, 2.9, 5.7, { back = V.x0 + 4.0 - ctx.cx, left = uOf(V, "left", 0, V.z0 + 3), right = uOf(V, "right", 0, V.z0 + 3) }, { pad = 0.1 })
		if wn and pcf then
			mark("roaster", pcf)
			if room(K, 70) then
				ctx.roaster = roaster(K, pcf, B)
			end
			if feat.sacks then
				local wn2, pcf2 = floorFind(K, { wn, "left", "right" }, 2.3, 1.8, 2.0, uOf(V, wn, (pcf.Position.X), pcf.Position.Z) + 3.3, { pad = 0.03, behindOK = true })
				if wn2 and pcf2 then
					mark("sacks", pcf2)
					beanSacks(K, pcf2, 2.2)
				end
			end
		end
	end
	if feat.oven then
		local wn, pcf = floorFind(K, { pickSide, other }, 4.2, 2.6, 6.0, pref, { pad = 0.1 })
		if wn and pcf then
			mark("oven", pcf)
			if room(K, 90) then
				ctx.oven = deckOven(K, pcf, 4.2)
			end
		end
	end
	if feat.cart then
		local wn, pcf = floorFind(K, { pickSide, other, "back" }, 3.4, 1.9, 4.6, pref, { pad = 0.1 })
		if wn and pcf then
			mark("cart", pcf)
			if room(K, 60) then
				cookCart(K, pcf, 3.4, feat.cart, B)
			end
		end
	end
	if feat.selfbar then
		local w = if small then 2.6 else 3.4
		local wn, pcf = floorFind(K, { pickSide, other }, w, 1.5, 4.6, pref, { pad = 0.08 })
		if wn and pcf then
			mark("selfbar", pcf)
			if room(K, 50) then
				selfBar(K, pcf, w, B)
			end
		end
	end
	if feat.fridge and not small then
		local wn, pcf = floorFind(K, { pickSide, other }, 2.5, 2.1, 6.6, pref, { pad = 0.06 })
		if wn and pcf then
			mark("fridge", pcf)
			local door, hinge = drinkFridge(K, pcf, 2.5, B, if B.type == "dessert" then "과일컵 · 음료" else "GRAB & GO")
			if door and hinge then
				Interact.swing(K, door, hinge, (K.cf * pcf).UpVector, -1.75, { object = "음료 냉장고", openText = "문 열기", closeText = "문 닫기" })
			end
		end
	end
	if feat.cake then
		local wn, pcf = floorFind(K, { pickSide, other, "back" }, 2.8, 2.0, 6.2, pref, { pad = 0.06 })
		if wn and pcf then
			mark("cake", pcf)
			local door, hinge = cakeFridge(K, pcf, 2.8, B, if B.key == "bakery" then "CAKE · 생크림 케이크" else "CAKE & DESSERT")
			if door and hinge then
				Interact.swing(K, door, hinge, (K.cf * pcf).UpVector, -1.6, { object = "케이크 쇼케이스", openText = "문 열기", closeText = "문 닫기" })
			end
		end
	end
	if feat.md and not small then
		local wn, pcf = floorFind(K, { other, pickSide }, 3.2, 1.1, 5.8, pref, { pad = 0.06 })
		if wn and pcf then
			mark("md", pcf)
			if room(K, 90) then
				mdShelf(K, pcf, 3.2, 5.4, B)
			end
		end
	end
	if feat.freezer then
		local w = if small then 2.6 else 3.2
		local placed = false
		if B.key == "claw" then
			-- 가운데 (인형뽑기 기계 앞 2.6 비움)
			local zs = { ctx.cz + 0.3, ctx.cz - 0.4, ctx.cz + 1.0 }
			for _, z in zs do
				local pcf = facing(V3(ctx.cx, 0, z), V3(0, 0, 1))
				if spotX(K, pcf, V3(w, 2.9, 1.7), 0.9) then
					ctx.freezer = freezerChest(K, pcf, w, B, "무인 아이스크림")
					ctx.freezerCF = pcf
					placed = true
					break
				end
			end
		end
		if not placed then
			local wn, pcf = floorFind(K, { other, pickSide, "back" }, w, 1.7, 2.9, pref, { pad = 0.08 })
			if wn and pcf then
				mark("freezer", pcf)
				ctx.freezer = freezerChest(K, pcf, w, B, if B.key == "tanghulu" then "젤라또 파인트" else "HOME PINT")
				ctx.freezerCF = pcf
			end
		end
	end
	-- 탕후루 냉장 쇼케이스: 젤라또 진열장 옆 같은 줄
	if feat.tanghulu then
		local case = V:first("CaseBase")
		local zc = if case then (case.min.Z + case.max.Z) / 2 else V.z0 + 5
		local w, d, h = 3.6, 2.2, 4.4
		local x = if case then case.min.X - 0.25 - w / 2 else ctx.cx
		for _ = 1, 16 do
			local pcf = facing(V3(x, 0, zc), V3(0, 0, 1))
			if spotX(K, pcf, V3(w, h, d), 0.05) then
				ctx.tangCase = pcf
				mark("tang", pcf)
				break
			end
			x -= 0.5
		end
	end
	-- 생과일 진열대 (가운데, 탕후루)
	if feat.fruit then
		local done = false
		for dx = 0, 14 do
			for _, sx in { -1, 1 } do
				local x = ctx.cx - V.W * 0.22 + sx * dx * 0.7
				for _, z in { V.z0 + V.D * 0.42, V.z0 + V.D * 0.36, V.z0 + V.D * 0.5 } do
					local pcf = facing(V3(x, 0, z), V3(0, 0, 1))
					if not done and spotX(K, pcf, V3(3.6, 2.9, 2.3), 0.8) then
						done = true
						mark("fruit", pcf)
						if room(K, 170) then
							fruitStand(K, pcf, 3.6, B)
						end
					end
				end
			end
			if done then
				break
			end
		end
	end
	-- 베이커리 아일랜드 진열대 (가운데)
	if feat.island then
		local done = false
		for dz = 0, 6 do
			for dx = 0, 10 do
				for _, sx in { -1, 1 } do
					local x = ctx.cx - V.W * 0.12 + sx * dx * 0.8
					local z = V.z0 + V.D * 0.42 + (if dz % 2 == 0 then 1 else -1) * math.floor((dz + 1) / 2) * 0.5
					local pcf = facing(V3(x, 0, z), V3(0, 0, 1))
					if not done and spotX(K, pcf, V3(4.2, 3.4, 2.4), 0.7) then
						ctx.island = pcf
						mark("island", pcf)
						done = true
					end
				end
				if done then
					break
				end
			end
			if done then
				break
			end
		end
	end
end

-- 2b) 바닥 화분 (벽 장식 다음: 화분 · 아래 잎 높이만 벽 자리 차지)
local function stepPlants(K: any, V: any, B: any, ctx: any)
	local feat = B.feat or {}
	local main = ctx.main
	local pickSide = "right"
	if main and ctx.alongX then
		pickSide = if ctx.pickU > ctx.cx then "right" else "left"
	end
	local other = if pickSide == "right" then "left" else "right"
	ctx.placed = ctx.placed or {}
	local function mark(name: string, cf: CFrame?)
		if cf then
			table.insert(ctx.placed, name .. ctx.where(cf))
		end
	end
	local np = feat.plants or 2
	local kinds = (K.style and K.style.plants) or { "monstera", "olive" }
	for i = 1, np do
		local z = if i == 1 then V.z1 - 4.5 else V.z0 + V.D * 0.5
		local wn, pcf = floorFind(K, if i % 2 == 1 then { other, pickSide } else { pickSide, other }, 1.9, 1.9, 5.5, { [other] = uOf(V, other, 0, z), [pickSide] = uOf(V, pickSide, 0, z) }, { pad = 0.05, wallH = 3.0 })
		if wn and pcf and #kinds > 0 then
			mark("plant", pcf)
			local kind = kinds[(i + B.seed) % #kinds + 1]
			local ph = math.clamp(V.H * 0.5, 4.2, 5.4)
			-- 잎이 넓게 퍼지는 몬스테라 · 올리브는 좌석 · 통로 keep 에 닿으면 산세베리아로
			if kind ~= "snake" then
				local mn, mx = Kit.laabb(pcf * CF(0, ph / 2, 0), V3(3.2, ph, 3.2))
				if K:hitsKeep(mn, mx) then
					kind = "snake"
				end
			end
			Props.floorPlant(K, pcf, { kind = kind, h = ph, dia = 1.5, pot = if B.key == "roastery" or B.key == "concrete" then Look.of(60, 60, 62, Enum.Material.Concrete) else nil })
		end
	end
end

-- 3) 카운터 위 / 뒤
local function stepCounters(K: any, V: any, B: any, ctx: any)
	if B.noCounter then
		return
	end
	local g = ctx.main
	if g then
		counterLogo(K, V, g, B)
		local pu = ctx.posU or 0
		local pcf = counterSpot(K, g, 0.5, 0.8, 0.4, "front", pu + 1.05)
		if pcf then
			Props.cardTerminal(K, pcf)
		end
		pcf = if B.key ~= "bakery" then counterSpot(K, g, 0.7, 0.7, 1.5, "front", pu - 1.15) else nil
		if pcf then
			pagerTower(K, pcf, if lowD(K) then 4 else 8, B.c1)
		end
		pcf = counterSpot(K, g, 0.65, 0.35, 1.0, "front", pu + 1.9)
		if pcf then
			Props.menuStand(K, pcf, B.promo[1] .. "\n" .. B.promo[2] .. "\n" .. B.promo[3] .. "원")
		end
		if B.feat.pickup ~= false then
			pcf = counterSpot(K, g, 1.3, 0.35, 0.8, "front", ctx.pickU)
			if pcf then
				standSign(K, pcf, 1.2, 0.62, "PICK UP\n픽업대", B.ink, B.paper)
				ctx.pickCF = pcf
			end
		end
		-- 디저트 진열 (쿠키 병 · 케이크 돔) / 꽃
		local mid = if ctx.esp[1] then (if ctx.alongX then ctx.esp[1].c.X else ctx.esp[1].c.Z) else pu + 3
		local dpos = (pu + mid) / 2
		if B.key == "haute" or B.key == "lounge" or B.key == "twosome" then
			pcf = counterSpot(K, g, 1.0, 1.0, 1.1, "front", dpos)
			if pcf then
				cakeDome(K, pcf, if B.key == "twosome" then rgb(90, 56, 40) else rgb(250, 232, 236))
			end
			pcf = counterSpot(K, g, 0.6, 0.6, 1.3, "front", ctx.pickU - 1.6)
			if pcf then
				flowerVase(K, pcf, B)
			end
		elseif B.type ~= "bakery" and B.key ~= "claw" then
			for k = 0, 1 do
				pcf = counterSpot(K, g, 0.6, 0.6, 0.9, "front", dpos + (k - 0.5) * 0.8)
				if pcf then
					cookieJar(K, pcf, if k == 0 then rgb(196, 140, 76) else rgb(110, 70, 44), if k == 0 then "쿠키 2,800" else "휘낭시에 3,000")
				end
			end
		end
		if B.feat.drip then
			pcf = counterSpot(K, g, 2.4, 0.6, 1.3, "front", ctx.pickU - 2.6)
			if pcf then
				dripStation(K, pcf)
			end
		end
		-- 픽업 쪽 안쪽: 포장 봉투 · 컵 캐리어
		if not lowD(K) then
			local pk = counterSpot(K, g, 1.3, 0.5, 0.95, "back", ctx.pickU)
			if pk then
				for k = 0, 1 do
					local c = pk * CF(-0.32 + k * 0.62, 0, 0)
					K:box("TakeoutBag", V3(0.5, 0.72, 0.3), c * CF(0, 0.36, 0), Look.kraft)
					K:box("TakeoutBagFold", V3(0.52, 0.08, 0.32), c * CF(0, 0.74, 0), lk(rgb(170, 134, 90), M.Cardboard))
					K:plate("TakeoutBagLogo", 0.3, 0.2, 0.01, c * CF(0, 0.4, 0.15), lk(B.c1))
				end
			end
		end
		-- 직원 쪽: 컵 · 피처 · 넉박스
		if ctx.esp[1] then
			local eu = if ctx.alongX then ctx.esp[1].c.X else ctx.esp[1].c.Z
			pcf = counterSpot(K, g, 0.6, 0.55, 0.45, "back", eu - 2.0)
			if pcf then
				knockBox(K, pcf)
			end
			pcf = counterSpot(K, g, 1.0, 0.4, 0.5, "back", eu + 2.1)
			if pcf then
				pitchers(K, pcf)
			end
		end
		-- 베이커리 / 디저트 계산대: 포장 봉투 · 영수증
		if B.key == "bakery" or B.type == "dessert" then
			pcf = counterSpot(K, g, 0.7, 0.8, 0.6, "mid", pu + 1.4)
			if pcf then
				Props.receiptPrinter(K, pcf)
			end
			pcf = counterSpot(K, g, 0.9, 0.6, 0.5, "front", pu - 1.3)
			if pcf then
				for k = 0, 3 do
					K:box("PaperBag", V3(0.8, 0.06, 0.55), pcf * CF(0, 0.03 + k * 0.065, 0) * ANG(0, k * 0.06, 0), Look.kraft)
				end
				K:text("PaperBagLogo", 0.5, 0.2, topCF((pcf * CF(0, 0.3, 0)).Position, -pcf.ZVector), B.logo, { fg = dk(B.c1, 0.3), d = 0.005, font = F.GothamBold })
			end
		end
	end
	-- 뒷바 (벽쪽 카운터)
	local bk = ctx.back
	if bk then
		local function bspot(w: number, d: number, h: number, pu: number): CFrame?
			return counterSpot(K, bk, w, d, h, "back", pu, 0.04, 0.08)
		end
		local lo = if ctx.alongX then bk.min.X else bk.min.Z
		local span = if ctx.alongX then bk.max.X - bk.min.X else bk.max.Z - bk.min.Z
		local chain = B.key == "mega" or B.key == "compose" or B.key == "twosome" or B.key == "pascucci"
		local items = {
			{ 0.9, 0.85, 1.5, 0.62, function(p) blender(K, p, chain) end },
			{ 0.9, 0.85, 1.5, 0.7, function(p) blender(K, p, chain) end },
			{ 1.9, 0.45, 1.25, 0.45, function(p) syrupRack(K, p, 5) end },
			{ 1.3, 0.5, 1.35, 0.25, function(p) cupTower(K, p, B.cup) end },
			{ 0.8, 0.85, 1.3, 0.85, function(p) hotWater(K, p) end },
			{ 1.3, 0.4, 0.7, 0.15, function(p) canisters(K, p, 3, B) end },
			{ 0.8, 0.85, 1.3, 0.92, function(p) blender(K, p, false) end },
		}
		for _, it in items do
			local p = bspot(it[1], it[2], it[3], lo + span * it[4])
			if p then
				it[5](p)
			end
		end
		-- 뒷바 앞면: 테이블 냉장고 문 + 제빙기 패널 (평평한 마감)
		local body = bk.body or bk
		local n = custDir(V, bk)
		if math.abs(n.Z) > 0.5 then
			local fz = if n.Z > 0 then body.max.Z else body.min.Z
			local top = (if bk.top then bk.top.min.Y else bk.y) - 0.1
			local h = top - 0.5
			local x = body.min.X + 0.3
			local k = 0
			K:free(function()
				while x + 2.0 <= body.max.X - 0.2 do
					local dcf = faceCF(V3(x + 1.0, 0.45 + h / 2, fz + n.Z * 0.085), n)
					local ice = k == 1
					K:plate("UnderFridgeDoor", 1.9, h - 0.1, 0.05, dcf, Look.steel)
					K:plate("UnderFridgeHandle", 1.5, 0.08, 0.06, dcf * CF(0, h / 2 - 0.3, 0.05), Look.chrome)
					if ice then
						for j = 0, 3 do
							K:plate("IceMachineVent", 1.4, 0.05, 0.02, dcf * CF(0, -h / 2 + 0.3 + j * 0.14, 0.05), Look.black)
						end
						K:text("IceMachineLabel", 0.8, 0.18, dcf * CF(0, 0.15, 0.06), "ICE MAKER", { fg = rgb(60, 60, 64), font = F.GothamBold, d = 0.005 })
					else
						K:text("UnderFridgeLCD", 0.36, 0.14, dcf * CF(0.6, h / 2 - 0.55, 0.06), "3℃", { fg = rgb(90, 200, 255), bg = rgb(10, 14, 20), glow = 1.2, font = F.Code, d = 0.005 })
					end
					x += 2.1
					k += 1
				end
			end)
		end
	end
end

-- 계산대 몸통 (Common 리스킨은 원래 몸통을 숨기고 앞면 · 상판만 다시 만들어 옆 · 뒤가 비어 보임): 같은 자리 · 크기 몸통
local function counterCarcass(K: any, V: any, B: any)
	local S = K.style or {}
	if S.counter == false then
		return
	end
	-- Props.counterOver 가 몸통을 직접 만들게 되면 (공유 모듈 수정) 중복 생략
	for _, p in K.parts do
		if p.Name == "CounterCarcass" then
			return
		end
	end
	local side = if B.key == "mega" or B.key == "compose" or B.type == "dessert" then Look.white elseif B.key == "roastery" or B.key == "concrete" or B.key == "twosome" or B.key == "lounge" then Look.charcoal else lk(rgb(226, 220, 210))
	K:free(function()
		for _, g in V.counters do
			local body = g.body
			if body then
				local top = if g.top then g.top.min.Y else body.max.Y
				local h = top - 0.02
				K:box("CounterCarcass", V3(body.size.X - 0.02, h, body.size.Z - 0.02), CF(body.c.X, h / 2, body.c.Z), side)
				-- 직원 쪽 선반 (뒷면에 열린 칸 2단)
				local n = custDir(V, g)
				if math.abs(n.Z) > 0.5 and body.size.X > 2.5 then
					local bz = if n.Z > 0 then body.min.Z - 0.005 else body.max.Z + 0.005
					local back = faceCF(V3(body.c.X, 0, bz), -n)
					for _, yy in { 0.9, 1.8 } do
						if yy < h - 0.3 then
							K:plate("CounterBackShelf", body.size.X - 0.3, 0.05, 0.02, back * CF(0, yy, 0), lk(dk(side.c, 0.25)))
						end
					end
				end
			end
		end
	end)
end

-- 4) 장비 스킨 · 진열장 · 맵 소품 다시 만들기
local function stepMachines(K: any, V: any, B: any, ctx: any)
	counterCarcass(K, V, B)
	if B.noCounter then
		return
	end
	local n: Vector3 = ctx.n or V3(0, 0, 1)
	local espL = if B.key == "mega" or B.key == "compose" then lk(rgb(30, 30, 32), M.Metal) elseif B.key == "haute" then lk(rgb(240, 236, 228), M.Metal) elseif B.key == "busan" or B.key == "ocean" then lk(rgb(30, 64, 120), M.Metal) elseif B.key == "roastery" or B.key == "concrete" then lk(rgb(40, 40, 42), M.Metal) else lk(rgb(170, 40, 36), M.Metal, { r = 0.06 })
	for _, e in V.byName.EspressoBody or {} do
		if room(K, 70) then
			K:free(function()
				espressoSkin(K, V, B, e, n, espL)
			end)
		else
			machineSkin(K, e, espL)
		end
	end
	-- 드립 트레이 (게임플레이: 같은 자세 스테인리스 + 직원 쪽 그릴 후 원본 숨김)
	for _, r in V.byName.DripTray or {} do
		K:free(function()
			K:box("DripTraySkin", r.size, CF(r.c), STAINLESS)
			if not lowD(K) then
				for k = 0, 5 do
					local t = -0.42 + k * 0.17
					K:box("DripGrate", V3(math.abs(n.Z) * (r.size.X - 0.2) + math.abs(n.X) * 0.05, 0.012, math.abs(n.X) * (r.size.Z - 0.2) + math.abs(n.Z) * 0.05), CF(r.c + V3(0, r.size.Y / 2 + 0.006, 0) + (if math.abs(n.Z) > 0.5 then V3(0, 0, -n.Z * (r.size.Z / 2 - 0.3 + t * 0.4)) else V3(-n.X * (r.size.X / 2 - 0.3 + t * 0.4), 0, 0))), Look.black)
				end
			end
		end)
		Scan.hide(K.hidden, r.part)
	end
	local grL = if B.key == "haute" then lk(rgb(232, 226, 216), M.Metal) elseif B.key == "busan" or B.key == "ocean" then lk(rgb(30, 64, 120), M.Metal) else lk(rgb(32, 32, 34), M.Metal)
	for _, r in V.byName.Grinder or {} do
		K:free(function()
			grinderSkin(K, V, B, r, n, grL)
			K:vcyl("GrinderCollar", 0.12, math.min(r.size.X, r.size.Z) * 0.9, CF(r.c.X, r.max.Y + 0.06, r.c.Z), Look.chrome)
		end)
	end
	-- 진열장 (CaseBase · CaseGlass): 앞면 패널 + 크롬 모서리 + 가격 레일
	for _, cb in V.byName.CaseBase or {} do
		local cg = nil
		for _, q in V.byName.CaseGlass or {} do
			if math.abs(q.c.X - cb.c.X) < 1 and math.abs(q.c.Z - cb.c.Z) < 1 then
				cg = q
			end
		end
		local cn = n
		if math.abs(cn.Z) < 0.5 then
			cn = V3(0, 0, 1)
		end
		local fz = if cn.Z > 0 then cb.max.Z else cb.min.Z
		local w = cb.size.X
		local front = faceCF(V3(cb.c.X, 0, fz + cn.Z * 0.012), cn)
		local panelL = lk(if B.type == "dessert" then B.c1 else dk(B.c2 or rgb(40, 34, 30), 0.0), if B.type == "dessert" then M.SmoothPlastic else M.Wood)
		if B.key == "mega" or B.key == "compose" then
			panelL = Look.white
		elseif B.casePanel then
			panelL = B.casePanel
		end
		K:free(function()
			K:plate("CaseKick", w - 0.1, 0.35, 0.04, front * CF(0, 0.175, -0.02), Look.black)
			K:plate("CasePanel", w, cb.size.Y - 0.4, 0.03, front * CF(0, 0.35 + (cb.size.Y - 0.4) / 2, 0), panelL)
			K:plate("CaseRail", w, 0.2, 0.06, front * CF(0, cb.max.Y - 0.12, 0), Look.chrome)
			local nf = math.max(2, math.floor(w / 1.2))
			for k = 1, nf - 1 do
				K:plate("CasePanelGroove", 0.03, cb.size.Y - 0.6, 0.035, front * CF(-w / 2 + w * k / nf, 0.35 + (cb.size.Y - 0.4) / 2, 0), lk(dk(panelL.c, 0.2)))
			end
			K:text("CaseLabel", math.min(w * 0.6, 3.4), 0.36, front * CF(0, 1.35, 0.035), if B.key == "hotteok" then "씨앗호떡 · 주문 즉시 구워 드립니다" elseif B.key == "churros" then "GELATO · CHURROS 매일 직접 만듭니다" elseif B.key == "bingsu" then "국산 팥 · 우유 눈꽃빙수" elseif B.type == "dessert" then "GELATO · 매일 아침 직접 만듭니다" elseif B.type == "bakery" then "오늘 구운 디저트" else "BAKERY & DESSERT", { fg = if (panelL.c.R * 0.3 + panelL.c.G * 0.59 + panelL.c.B * 0.11) > 0.8 then dk(panelL.c, 0.7) else rgb(250, 246, 236), font = F.GothamBold, d = 0.01 })
			if cg and cg.size.Y < 1.6 then
				-- 낮은 젤라또 진열장: 맵의 빛 판(CaseLight) 대신 유리 상판 + 뒤쪽 LED 바
				for _, cl in V.byName.CaseLight or {} do
					if cl.c.X >= cg.min.X - 0.2 and cl.c.X <= cg.max.X + 0.2 and math.abs(cl.c.Z - cg.c.Z) < 1.5 then
						Scan.hide(K.hidden, cl.part)
					end
				end
				K:box("CaseGlassTop", V3(cg.size.X - 0.08, 0.04, cg.size.Z * 0.62), CF(cg.c.X, cg.max.Y - 0.02, cg.c.Z - cn.Z * cg.size.Z * 0.18), glassL(rgb(226, 238, 240), 0.72))
				K:box("CaseLEDBar", V3(cg.size.X - 0.1, 0.08, 0.1), CF(cg.c.X, cg.max.Y - 0.06, if cn.Z > 0 then cg.min.Z + 0.08 else cg.max.Z - 0.08), Look.lampNeutral)
			end
			if cg then
				local gfz = if cn.Z > 0 then cg.max.Z else cg.min.Z
				local gbz = if cn.Z > 0 then cg.min.Z else cg.max.Z
				for _, zz in { gfz, gbz } do
					K:box("CaseTrim", V3(cg.size.X + 0.04, 0.06, 0.06), CF(cg.c.X, cg.max.Y, zz), Look.chrome)
				end
				for _, sx in { -1, 1 } do
					for _, zz in { gfz, gbz } do
						K:box("CasePost", V3(0.05, cg.size.Y, 0.05), CF(cg.c.X + sx * cg.size.X / 2, cg.c.Y, zz), Look.chrome)
					end
				end
			end
		end)
		-- 페이스트리 (Pastry 상자 → 모양 + 가격표)
		local k = 0
		for _, pr in V.byName.Pastry or {} do
			if pr.c.X >= cb.min.X - 0.1 and pr.c.X <= cb.max.X + 0.1 and pr.c.Z >= cb.min.Z - 0.4 and pr.c.Z <= cb.max.Z + 0.4 and room(K, 10) then
				k += 1
				local info = if B.key == "hotteok" then HOTTEOK_CASE[(k + B.seed) % #HOTTEOK_CASE + 1] else PASTRIES[(k + B.seed) % #PASTRIES + 1]
				local pcf = facing(V3(pr.c.X, pr.min.Y, pr.c.Z), cn)
				Scan.hide(K.hidden, pr.part)
				K:free(function()
					pastry(K, pcf, info[3], 1.2)
					if not lowD(K) and pr.c.Z * cn.Z > (cb.c.Z * cn.Z) - 0.05 then
						tag(K, facing(V3(pr.c.X, pr.min.Y + 0.12, (if cn.Z > 0 then pr.max.Z + 0.12 else pr.min.Z - 0.12)), cn) * ANG(math.rad(-20), 0, 0), 0.5, 0.2, info[1] .. "\n" .. info[2])
					end
				end)
			end
		end
	end
end

local function stepRebuild(K: any, V: any, B: any, ctx: any)
	local n: Vector3 = ctx.n or V3(0, 0, 1)
	local seed = B.seed
	-- 벽 선반 병 (Jar): 원두 캐니스터 · 원두 봉투 · 시럽병 · 틴 · 화분
	local i = 0
	for _, r in V.byName.Jar or {} do
		i += 1
		if not room(K, 6) then
			break
		end
		Scan.hide(K.hidden, r.part)
		local pcf = facing(V3(r.c.X, r.min.Y, r.c.Z), V3(0, 0, 1))
		local kind = (i + seed) % 5
		local h = math.clamp(r.size.Y, 0.5, 1.1)
		if kind == 0 then
			K:vcyl("BeanCanister", h, 0.5, pcf * CF(0, h / 2, 0), glassL(rgb(236, 240, 242), 0.55))
			K:vcyl("BeanFill", h * 0.72, 0.44, pcf * CF(0, h * 0.37, 0), lk(rgb(78, 46, 28), M.Pebble))
			K:vcyl("BeanCanisterLid", 0.1, 0.52, pcf * CF(0, h + 0.05, 0), Look.walnut)
		elseif kind == 1 then
			K:box("BeanBag", V3(0.46, h * 0.85, 0.3), pcf * CF(0, h * 0.425, 0), Look.kraft)
			K:box("BeanBagFold", V3(0.48, 0.1, 0.32), pcf * CF(0, h * 0.85 + 0.03, 0), lk(rgb(170, 134, 90), M.Cardboard))
			K:plate("BeanBagLabel", 0.34, 0.26, 0.01, pcf * CF(0, h * 0.45, 0.15), lk(B.c1))
		elseif kind == 2 then
			K:vcyl("SyrupBottle", h * 0.7, 0.26, pcf * CF(0, h * 0.35, 0), lk(if i % 2 == 0 then rgb(150, 90, 40) else rgb(110, 30, 30), M.Glass, { t = 0.12 }))
			K:vcyl("SyrupNeck", h * 0.25, 0.1, pcf * CF(0, h * 0.82, 0), lk(rgb(150, 90, 40), M.Glass, { t = 0.12 }))
			K:vcyl("SyrupCap", 0.06, 0.12, pcf * CF(0, h * 0.97, 0), Look.black)
			K:plate("SyrupBottleLabel", 0.2, 0.22, 0.01, pcf * CF(0, h * 0.35, 0.13), Look.paper)
		elseif kind == 3 then
			K:vcyl("TeaTin", h * 0.7, 0.38, pcf * CF(0, h * 0.35, 0), lk(if i % 2 == 0 then B.c1 else rgb(40, 40, 42), M.Metal))
			K:vcyl("TeaTinLid", 0.08, 0.4, pcf * CF(0, h * 0.7 + 0.04, 0), Look.chrome)
		else
			Props.potPlant(K, pcf, 0.4, math.max(0.4, h - 0.3))
		end
	end
	-- 디저트 선반 컵 (Cup): 파인트 · 콘 타워 · 토핑 병 · 소스 · 컵 스택 (와플 · 탕후루는 아래 선반을 작업 스테이션으로)
	i = 0
	local lowI: number?, upI: number? = nil, nil
	for _, r in V.byName.Cup or {} do
		i += 1
		if not room(K, if B.key == "waffle" or B.key == "tanghulu" then 44 else 16) then
			break
		end
		Scan.hide(K.hidden, r.part)
		local pcf = facing(V3(r.c.X, r.min.Y, r.c.Z), V3(0, 0, 1))
		local kind = (i + seed) % 5
		-- 와플 · 탕후루: 아래 선반 (작업대 높이 ~2.6) = 직원 작업 스테이션, 위 선반 = 재료 · 포장 재고
		local lower = r.min.Y < 3.6
		if B.key == "waffle" and lower then
			lowI = (lowI or 0) + 1
			local k5 = (lowI + seed) % 4
			if k5 == 0 or k5 == 2 then
				for _, sx in { -0.6, 0.6 } do
					waffleMaker(K, pcf * CF(sx, 0, 0), 1.0, 0.36, 0.95, 0.84, 0.14, true)
				end
			elseif k5 == 1 then
				batterJug(K, pcf * CF(-0.5, 0, 0))
				creamMachine(K, pcf * CF(0.45, 0, 0))
			else
				insertPans(K, pcf, { rgb(222, 40, 60), rgb(250, 222, 120), rgb(92, 56, 36), rgb(50, 44, 44) }, false)
				K:text("PanLabel", 1.5, 0.14, pcf * CF(0, 0.05, 0.31), "딸기 · 바나나 · 누텔라 · 오레오", { fg = rgb(60, 46, 40), bg = rgb(255, 250, 244), font = F.GothamBold, d = 0.006 })
			end
			continue
		elseif B.key == "tanghulu" then
			if lower then
				lowI = (lowI or 0) + 1
				local k5 = (lowI + seed) % 4
				if k5 == 0 then
					sugarStation(K, pcf * CF(-0.3, 0, 0))
					skewerCup(K, pcf * CF(0.65, 0, 0.1))
				elseif k5 == 1 then
					insertPans(K, pcf, { rgb(214, 28, 48), rgb(160, 206, 80), rgb(250, 146, 28), rgb(60, 60, 120) }, true)
				elseif k5 == 2 then
					K:box("SkewerFoam", V3(1.1, 0.24, 0.36), pcf * CF(-0.2, 0.12, 0), lk(rgb(250, 250, 248)))
					for k = 0, 4 do
						skewer(K, pcf * CF(-0.6 + k * 0.2, 0.24, 0), FRUIT_ORDER[(k + lowI) % #FRUIT_ORDER + 1], 0.8)
					end
					skewerCup(K, pcf * CF(0.7, 0, 0))
				else
					sugarStation(K, pcf * CF(0.1, 0, 0))
				end
				continue
			else
				upI = (upI or 0) + 1
				local k5 = (upI + seed) % 4
				if k5 == 0 then
					fruitCrate(K, pcf * CF(-0.55, 0, 0), rgb(214, 28, 48), "논산 설향 딸기")
					sugarSack(K, pcf * CF(0.55, 0, 0))
				elseif k5 == 1 then
					fruitCrate(K, pcf * CF(-0.55, 0, 0), rgb(150, 200, 70), "샤인머스캣 2kg")
					fruitCrate(K, pcf * CF(0.55, 0, 0) * ANG(0, 0.05, 0), rgb(250, 146, 28), "제주 감귤")
				elseif k5 == 2 then
					for k = 0, 2 do
						K:vcyl("TangCupStack", 0.8, 0.34, pcf * CF(-0.5 + k * 0.42, 0.4, 0), lk(if k == 1 then B.c1 else rgb(250, 250, 248)))
						K:vcyl("TangCupRim", 0.04, 0.37, pcf * CF(-0.5 + k * 0.42, 0.78, 0), lk(dk(if k == 1 then B.c1 else rgb(250, 250, 248), 0.15)))
					end
					K:text("TangCupLabel", 1.2, 0.13, pcf * CF(0, 0.05, 0.3), "탕후루 컵 · 꼬치 홀더", { fg = B.c1, bg = rgb(255, 255, 255), font = F.GothamBold, d = 0.005 })
				else
					sugarSack(K, pcf * CF(-0.5, 0, 0))
					fruitCrate(K, pcf * CF(0.55, 0, 0), rgb(60, 60, 120), "블루베리")
				end
				continue
			end
		end
		if kind == 0 then
			for k = 0, 2 do
				local fl = FLAVORS[(i + k) % #FLAVORS + 1]
				K:vcyl("PintCup", 0.42, 0.36, pcf * CF((k - 1) * 0.4, 0.21, 0), Look.white)
				K:vcyl("PintLid", 0.06, 0.38, pcf * CF((k - 1) * 0.4, 0.45, 0), lk(fl[2]))
			end
		elseif kind == 1 then
			K:box("ConeHolder", V3(0.95, 0.32, 0.45), pcf * CF(0, 0.16, 0), Look.walnut)
			local cone = lk(rgb(214, 160, 90), M.Sand)
			for k = 0, 2 do
				local c = pcf * CF((k - 1) * 0.3, 0.32, 0)
				K:vcyl("ConeTip", 0.14, 0.08, c * CF(0, 0.07, 0), cone)
				K:vcyl("ConeBody", 0.16, 0.16, c * CF(0, 0.2, 0), cone)
				K:vcyl("ConeBody", 0.16, 0.23, c * CF(0, 0.34, 0), cone)
				K:vcyl("ConeRim", 0.1, 0.28, c * CF(0, 0.46, 0), lk(rgb(200, 146, 80), M.Sand))
				K:vcyl("ConeStackTop", 0.14, 0.27, c * CF(0, 0.57, 0), lk(rgb(220, 170, 100), M.Sand))
			end
		elseif kind == 2 then
			for k = 0, 1 do
				K:vcyl("ToppingJar", 0.5, 0.34, pcf * CF((k - 0.5) * 0.42, 0.25, 0), glassL(rgb(240, 240, 240), 0.5))
				K:vcyl("ToppingFill", 0.34, 0.3, pcf * CF((k - 0.5) * 0.42, 0.19, 0), lk(if k == 0 then rgb(250, 120, 170) else rgb(110, 70, 40), M.Pebble))
				K:vcyl("ToppingLid", 0.06, 0.36, pcf * CF((k - 0.5) * 0.42, 0.53, 0), Look.chrome)
			end
		elseif kind == 3 then
			for k = 0, 2 do
				K:vcyl("SauceBottle", 0.6, 0.22, pcf * CF((k - 1) * 0.28, 0.3, 0), lk(if k == 0 then rgb(80, 50, 30) elseif k == 1 then rgb(220, 40, 60) else rgb(230, 170, 70)))
				K:vcyl("SauceTip", 0.16, 0.08, pcf * CF((k - 1) * 0.28, 0.68, 0), Look.white)
			end
		else
			for k = 0, 1 do
				local c = pcf * CF((k - 0.5) * 0.42, 0, 0)
				K:vcyl("PaperCupStack", 0.7, 0.3, c * CF(0, 0.35, 0), lk(if k == 0 then B.cup else rgb(250, 250, 248)))
				for j = 1, 3 do
					K:vcyl("PaperCupRim", 0.03, 0.34, c * CF(0, 0.2 * j + 0.08, 0), lk(dk(if k == 0 then B.cup else rgb(250, 250, 248), 0.12)))
				end
			end
		end
	end
	-- 빵 (Bread): 바구니 + 빵 2~3 + 선반 앞 가격표
	i = 0
	local breadList = BREADS
	if B.key == "hotteok" then
		breadList = { { "씨앗호떡", "2,000", "hotteok" }, { "꿀호떡", "1,500", "hotteok" }, { "녹차씨앗호떡", "2,500", "hotteokg" }, { "치즈호떡", "2,500", "hotteok" } }
	end
	local shelves = V.byName.BreadShelf or {}
	for _, r in V.byName.Bread or {} do
		i += 1
		if not room(K, 16) then
			break
		end
		Scan.hide(K.hidden, r.part)
		local sh = nil
		for _, s in shelves do
			if r.c.X >= s.min.X and r.c.X <= s.max.X and math.abs(r.min.Y - s.max.Y) < 0.35 then
				sh = s
			end
		end
		local y = if sh then sh.max.Y else r.min.Y
		local info = breadList[(i + seed) % #breadList + 1]
		local pcf = facing(V3(r.c.X, y, if sh then (sh.min.Z + sh.max.Z) / 2 + 0.1 else r.c.Z), V3(0, 0, 1))
		local bw = 1.55
		if B.key == "hotteok" and sh and sh.c.Y > 3.5 then
			-- 호떡집 윗선반: 씨앗호떡 믹스 선물세트 · 꿀 단지 (포장 상품)
			local red = if i % 2 == 0 then rgb(196, 52, 46) else rgb(232, 168, 48)
			K:box("GiftBox", V3(1.1, 0.42, 0.72), pcf * CF(-0.15, 0.21, -0.05), lk(red))
			K:box("GiftBand", V3(1.12, 0.1, 0.74), pcf * CF(-0.15, 0.3, -0.05), lk(rgb(240, 214, 140), M.Metal))
			K:box("GiftBox", V3(1.0, 0.38, 0.66), pcf * CF(-0.12, 0.61, -0.08) * ANG(0, 0.08, 0), lk(dk(red, 0.1)))
			K:text("GiftLabel", 0.9, 0.24, pcf * CF(-0.15, 0.15, 0.315), "부산 씨앗호떡 믹스", { fg = rgb(255, 250, 236), d = 0.005, font = F.GothamBold })
			K:vcyl("HoneyJar", 0.42, 0.32, pcf * CF(0.55, 0.21, 0.05), lk(rgb(220, 150, 40), M.Glass, { t = 0.2 }))
			K:vcyl("HoneyJarLid", 0.08, 0.34, pcf * CF(0.55, 0.46, 0.05), lk(rgb(240, 214, 140), M.Metal))
			if sh then
				tag(K, faceCF(V3(r.c.X, sh.c.Y, sh.max.Z + 0.012), V3(0, 0, 1)), 0.95, math.min(0.22, sh.size.Y + 0.02), "선물세트 12,000")
			end
			continue
		end
		basket(K, pcf, bw, 1.1, if i % 2 == 0 then Look.rattan else Look.of(150, 110, 70, Enum.Material.Wood))
		local kind = info[3]
		local cnt = if kind == "baguette" or kind == "garlic" then 2 elseif kind == "loaf" then 1 else 3
		for k = 1, cnt do
			local ox = (k - (cnt + 1) / 2) * (if cnt == 2 then 0.0 else 0.45)
			local oz = if cnt == 2 then (k - 1.5) * 0.32 else (k % 2) * 0.12 - 0.06
			bread(K, pcf * CF(ox, 0.08, oz) * ANG(0, (k - 2) * 0.2, 0), kind, if kind == "baguette" or kind == "garlic" then 1.05 elseif kind == "loaf" or kind == "ciabatta" then 1.25 else 1.05)
		end
		if sh then
			local dcf = faceCF(V3(r.c.X, sh.c.Y, sh.max.Z + 0.012), V3(0, 0, 1))
			tag(K, dcf, 0.95, math.min(0.22, sh.size.Y + 0.02), info[1] .. "  " .. info[2])
		end
	end
	-- 빵 선반 보강: 앞 레일 · 까치발 · 선반 아래 LED
	K:free(function()
		for _, s in shelves do
			local fz = s.max.Z
			K:box("BreadShelfLip", V3(s.size.X, 0.06, 0.05), CF(s.c.X, s.max.Y + 0.03, fz - 0.02), Look.walnut)
			local nb = math.max(2, math.floor(s.size.X / 4))
			for k = 0, nb do
				local x = s.min.X + 0.2 + (s.size.X - 0.4) * k / nb
				K:box("BreadShelfBracket", V3(0.06, 0.5, 0.04), CF(x, s.min.Y - 0.25, s.min.Z + 0.03), Look.blackMetal)
				K:box("BreadShelfBracket", V3(0.06, 0.06, s.size.Z - 0.35), CF(x, s.min.Y - 0.03, s.min.Z + (s.size.Z - 0.35) / 2 + 0.05), Look.blackMetal)
			end
			if s.c.Y > 3.5 then
				local led = K:box("BreadShelfLED", V3(s.size.X - 0.4, 0.04, 0.06), CF(s.c.X, s.min.Y - 0.03, fz - 0.25), Look.lampWarm)
				if not ctx.shelfLit then
					ctx.shelfLit = K:light(led, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.5, Angle = 120, Color = Look.warmLight })
				end
			end
		end
	end)
	-- 커피 뒷벽 선반 (맵 WallShelf: 떠 있는 판 하나) 보강: 앞 립 · 까치발 · 선반 아래 LED 띠 (선반 자체는 그대로)
	K:free(function()
		for _, s in V.byName.WallShelf or {} do
			local nz = if s.c.Z < (V.z0 + V.z1) / 2 then 1 else -1
			if B.noCounter or math.abs(s.size.X) < 1.5 or not room(K, 20) then
				continue
			end
			local fz = if nz > 0 then s.max.Z else s.min.Z
			local bz = if nz > 0 then s.min.Z else s.max.Z
			local lipL = if B.key == "mega" or B.key == "compose" then lk(B.c1) elseif B.key == "busan" then lk(B.c1) else Look.walnut
			K:box("ShelfLip", V3(s.size.X, s.size.Y + 0.04, 0.04), CF(s.c.X, s.c.Y + 0.01, fz + nz * 0.02), lipL)
			local nb = math.max(2, math.floor(s.size.X / 3))
			for k = 0, nb do
				local x = s.min.X + 0.3 + (s.size.X - 0.6) * k / nb
				K:box("ShelfBracket", V3(0.05, 0.42, 0.05), CF(x, s.min.Y - 0.21, bz + nz * 0.03), Look.blackMetal)
				K:box("ShelfBracket", V3(0.05, 0.05, s.size.Z - 0.2), CF(x, s.min.Y - 0.025, (s.min.Z + s.max.Z) / 2 - nz * 0.05), Look.blackMetal)
			end
			K:box("ShelfLED", V3(s.size.X - 0.3, 0.03, 0.05), CF(s.c.X, s.min.Y - 0.02, fz - nz * 0.12), Look.lampWarm)
		end
	end)
	-- 젤라또 통 (GelatoTub, 게임플레이: 같은 자세 오버레이 후 숨김) + 맛 이름표
	i = 0
	for _, r in V.byName.GelatoTub or {} do
		i += 1
		local fl = FLAVORS[(i + seed) % #FLAVORS + 1]
		local top = r.max.Y
		K:free(function()
			K:box("GelatoPan", r.size, CF(r.c), Look.steel)
			K:box("GelatoSurface", V3(r.size.X - 0.08, 0.03, r.size.Z - 0.08), CF(r.c.X, top - 0.005, r.c.Z), lk(fl[2]))
			K:ell("GelatoMound", V3(r.size.X * 0.82, 0.24, r.size.Z * 0.7), CF(r.c.X, top - 0.03, r.c.Z - 0.05), lk(fl[2]))
			K:ell("GelatoWave", V3(r.size.X * 0.5, 0.14, r.size.Z * 0.3), CF(r.c.X + 0.1, top + 0.01, r.c.Z + 0.25) * ANG(0, 0.3, 0), lk(dk(fl[2], 0.08)))
			if i % 2 == 1 then
				K:box("GelatoSpade", V3(0.16, 0.02, 0.32), CF(r.c.X - 0.15, top + 0.06, r.c.Z - 0.3) * ANG(0.5, 0, 0), Look.chrome)
				K:bar("GelatoSpadeHandle", V3(r.c.X - 0.15, top + 0.12, r.c.Z - 0.45), V3(r.c.X - 0.15, top + 0.45, r.c.Z - 0.75), 0.05, 0.05, Look.black)
			end
		end)
		Scan.hide(K.hidden, r.part)
		local glass = nil
		for _, q in V.byName.CaseGlass or {} do
			if r.c.X >= q.min.X and r.c.X <= q.max.X then
				glass = q
			end
		end
		if glass then
			local dcf = faceCF(V3(r.c.X, glass.min.Y + 0.25, glass.max.Z + 0.012), V3(0, 0, 1))
			tag(K, dcf, 0.85, 0.2, fl[1], rgb(255, 255, 255), dk(fl[2], 0.55))
		end
	end
	-- 와플 기계 (WaffleIron + WaffleLid, 게임플레이: 같은 자세 오버레이 후 숨김)
	for _, r in V.byName.WaffleIron or {} do
		local lid = nil
		for _, q in V.byName.WaffleLid or {} do
			if (q.c - r.c).Magnitude < 1 then
				lid = q
			end
		end
		local wn = ctx.n or V3(0, 0, 1)
		local ww = math.abs(wn.Z) * r.size.X + math.abs(wn.X) * r.size.Z
		local wd = math.abs(wn.X) * r.size.X + math.abs(wn.Z) * r.size.Z
		K:free(function()
			waffleMaker(K, facing(V3(r.c.X, r.min.Y, r.c.Z), -wn), ww, r.size.Y, wd, if lid then math.min(lid.size.X, lid.size.Z) else ww * 0.82, if lid then lid.size.Y else 0.15, false)
		end)
		Scan.hide(K.hidden, r.part)
		if lid then
			Scan.hide(K.hidden, lid.part)
		end
	end
	-- 인형 (Plush): 곰 · 토끼 · 병아리
	i = 0
	local pal = { rgb(250, 190, 210), rgb(250, 230, 160), rgb(180, 220, 250), rgb(210, 180, 140), rgb(250, 250, 246), rgb(200, 240, 200), rgb(230, 200, 250) }
	for _, r in V.byName.Plush or {} do
		i += 1
		if not room(K, 8) then
			break
		end
		Scan.hide(K.hidden, r.part)
		local face = V3(0, 0, 1)
		local best = math.huge
		for _, j in V.byName.Joystick or {} do
			local d = (j.c - r.c) * V3(1, 0, 1)
			if d.Magnitude < best then
				best = d.Magnitude
				face = if math.abs(d.X) > math.abs(d.Z) then V3(math.sign(d.X), 0, 0) else V3(0, 0, math.sign(d.Z))
			end
		end
		local kind = (i + seed) % 3
		local col = if kind == 2 then rgb(250, 220, 90) else pal[(i * 3 + seed) % #pal + 1]
		plush(K, V3(r.c.X, r.min.Y + r.size.Y * 0.45, r.c.Z), r.size.Y * 0.95, kind, col, face)
	end
end

-- 인형뽑기 기계 꾸미기
local function stepClaw(K: any, V: any, B: any, ctx: any)
	local pal = { rgb(255, 90, 170), rgb(80, 200, 255), rgb(255, 210, 60), rgb(120, 230, 170), rgb(190, 130, 255) }
	local i = 0
	ctx.clawLeds = {}
	for _, b in V.byName.ClawBase or {} do
		i += 1
		if not room(K, 46) then
			break
		end
		local face = V3(0, 0, 1)
		local best = math.huge
		for _, j in V.byName.Joystick or {} do
			local d = (j.c - b.c) * V3(1, 0, 1)
			if d.Magnitude < best then
				best = d.Magnitude
				face = if math.abs(d.X) > math.abs(d.Z) then V3(math.sign(d.X), 0, 0) else V3(0, 0, math.sign(d.Z))
			end
		end
		local half = math.abs(face.X) * b.size.X / 2 + math.abs(face.Z) * b.size.Z / 2
		local w = math.abs(face.Z) * b.size.X + math.abs(face.X) * b.size.Z
		local fp = b.c + face * (half + 0.012)
		local front = faceCF(V3(fp.X, 0, fp.Z), face)
		local c = pal[(i + B.seed) % #pal + 1]
		local top = nil
		for _, q in V.byName.ClawTop or {} do
			if (q.c * V3(1, 0, 1) - b.c * V3(1, 0, 1)).Magnitude < 0.6 then
				top = q
			end
		end
		K:free(function()
			K:plate("ClawPanel", w, b.size.Y - 0.3, 0.03, front * CF(0, 0.3 + (b.size.Y - 0.3) / 2, 0), lk(c))
			K:plate("ClawKick", w - 0.1, 0.3, 0.04, front * CF(0, 0.15, -0.01), Look.black)
			K:plate("ClawPrizeDoor", 1.1, 0.8, 0.05, front * CF(-w * 0.18, 0.95, 0), Look.black)
			K:plate("ClawPrizeFlap", 1.0, 0.7, 0.06, front * CF(-w * 0.18, 0.95, 0), glassL(rgb(200, 200, 210), 0.5))
			K:text("ClawPrizeLabel", 1.0, 0.18, front * CF(-w * 0.18, 1.5, 0.04), "PRIZE ▼", { fg = rgb(255, 255, 255), font = F.GothamBlack, d = 0.005 })
			K:plate("ClawCoin", 0.42, 0.7, 0.06, front * CF(w * 0.28, 1.6, 0), Look.chrome)
			K:plate("ClawCoinSlot", 0.06, 0.24, 0.07, front * CF(w * 0.28, 1.7, 0), Look.black)
			K:text("ClawCoinLabel", 0.4, 0.14, front * CF(w * 0.28, 1.36, 0.065), "1,000", { fg = rgb(30, 30, 30), bg = rgb(255, 230, 80), d = 0.005, font = F.GothamBold })
			K:text("ClawBrand", w * 0.7, 0.3, front * CF(0, 2.45, 0.035), if i % 2 == 0 then "PICK ME!" else "LUCKY CATCH", { fg = rgb(255, 255, 255), font = F.FredokaOne, d = 0.005 })
			-- 버튼 (조작대 위)
			local bp = b.c + face * (half - 0.35) + V3(0, b.max.Y - b.c.Y + 0.03, 0)
			K:disc("ClawButton", 0.3, 0.06, CF(bp) + face:Cross(Vector3.yAxis) * 0.6, Look.ledRed)
			-- 모서리 LED 기둥
			if not lowD(K) then
				local side = face:Cross(Vector3.yAxis)
				local hTop = if top then top.max.Y else 7.9
				for _, s in { -1, 1 } do
					local p = b.c + face * (half + 0.03) + side * s * (w / 2 - 0.04)
					local led = K:box("ClawLED", V3(0.07, hTop - 0.1, 0.07), CF(p.X, hTop / 2, p.Z), Look.neon(c))
					table.insert(ctx.clawLeds, led)
				end
			end
			if top then
				local tf = top.c + face * (half + 0.015)
				K:text("ClawMarquee", w * 0.9, top.size.Y * 0.7, faceCF(V3(tf.X, top.c.Y, tf.Z), face), if i % 3 == 0 then "인형뽑기" elseif i % 3 == 1 then "BINGBING" else "♥ CATCH ♥", { fg = rgb(255, 255, 255), glow = 1.6, font = F.FredokaOne, d = 0.01 })
			end
			-- 집게 · 와이어 · 갠트리 · 조이스틱 · 배출구 (맵의 상자 집게 · 굵은 막대 · 각진 조이스틱 대신, 같은 자리)
			local function near(list: { any }?, maxD: number): any
				for _, q in list or {} do
					if (q.c * V3(1, 0, 1) - b.c * V3(1, 0, 1)).Magnitude < maxD then
						return q
					end
				end
				return nil
			end
			local claw = near(V.byName.Claw, 1.6)
			local cable = near(V.byName.ClawCable, 1.6)
			local glass = near(V.byName.ClawGlass, 0.6)
			local stick = nil
			for _, j in V.byName.Joystick or {} do
				if (j.c * V3(1, 0, 1) - (b.c + face * half) * V3(1, 0, 1)).Magnitude < 1.6 then
					stick = j
				end
			end
			if claw then
				local hubY = claw.max.Y - 0.1
				K:vcyl("ClawHub", 0.2, 0.32, CF(claw.c.X, hubY, claw.c.Z), Look.chrome)
				K:vcyl("ClawMotor", 0.12, 0.22, CF(claw.c.X, claw.max.Y - 0.02, claw.c.Z), Look.darkAlu)
				local rr = math.min(claw.size.X, claw.size.Z) / 2 - 0.04
				for k = 0, 2 do
					local a = k * 2 * PI / 3 + 0.4
					local dir = V3(math.cos(a), 0, math.sin(a))
					local p0 = V3(claw.c.X, hubY - 0.08, claw.c.Z) + dir * 0.13
					local p1 = V3(claw.c.X, claw.c.Y - 0.02, claw.c.Z) + dir * rr
					local p2 = V3(claw.c.X, claw.min.Y + 0.04, claw.c.Z) + dir * (rr * 0.55)
					K:seg("ClawProng", p0, p1, 0.05, Look.chrome, 0.03)
					K:seg("ClawProng", p1, p2, 0.05, Look.chrome, 0.03)
					K:ball("ClawTip", 0.07, CF(p2), Look.chrome)
				end
				Scan.hide(K.hidden, claw.part)
			end
			if cable then
				K:vcyl("ClawWire", cable.size.Y, 0.035, CF(cable.c), Look.steel)
				Scan.hide(K.hidden, cable.part)
			end
			if glass and not lowD(K) then
				local gy = glass.max.Y - 0.06
				local side = face:Cross(Vector3.yAxis)
				local gw = math.abs(face.Z) * glass.size.X + math.abs(face.X) * glass.size.Z
				local gd = math.abs(face.X) * glass.size.X + math.abs(face.Z) * glass.size.Z
				for _, sz in { -1, 1 } do
					local c0 = glass.c * V3(1, 0, 1) + V3(0, gy, 0) + face * (sz * (gd / 2 - 0.1))
					K:box("ClawGantryRail", V3(0.07, 0.06, 0.07) + (V3(math.abs(side.X), 0, math.abs(side.Z)) * (gw - 0.24)), CF(c0), Look.darkAlu)
				end
				local cx = if cable then cable.c else glass.c
				local c1 = V3(cx.X, gy - 0.02, cx.Z)
				local along = V3(math.abs(face.X), 0, math.abs(face.Z))
				K:box("ClawGantryBeam", V3(0.06, 0.05, 0.06) + along * (gd - 0.24), CF(V3(c1.X, gy - 0.02, c1.Z) * (V3(1, 1, 1) - along) + glass.c * along), Look.darkAlu)
				K:box("ClawTrolley", V3(0.32, 0.14, 0.32), CF(c1.X, gy - 0.08, c1.Z), Look.blackMetal)
				-- 배출구 (앞 왼쪽 모서리의 투명 아크릴 통)
				local cc = glass.c * V3(1, 0, 1) + face * (gd / 2 - 0.5) - side * (gw / 2 - 0.5) + V3(0, glass.min.Y + 0.3, 0)
				K:box("ClawChute", V3(0.82, 0.6, 0.82), CF(cc), glassL(rgb(230, 240, 250), 0.55))
				K:box("ClawChuteRim", V3(0.86, 0.04, 0.86), CF(cc + V3(0, 0.31, 0)), Look.chrome)
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local pp = glass.c * V3(1, 0, 1) + side * (sx * (gw / 2 - 0.03)) + face * (sz * (gd / 2 - 0.03))
						K:box("ClawGlassEdge", V3(0.05, glass.size.Y, 0.05), CF(pp.X, glass.c.Y, pp.Z), Look.chrome)
					end
				end
			end
			if stick then
				K:disc("JoyBase", 0.34, 0.05, CF(stick.c.X, stick.min.Y + 0.025, stick.c.Z), Look.black)
				K:vcyl("JoyBoot", 0.12, 0.16, CF(stick.c.X, stick.min.Y + 0.1, stick.c.Z), Look.rubber)
				K:vcyl("JoyStick", stick.size.Y - 0.25, 0.06, CF(stick.c.X, stick.min.Y + (stick.size.Y - 0.25) / 2 + 0.05, stick.c.Z), Look.chrome)
				K:ball("JoyBall", 0.22, CF(stick.c.X, stick.max.Y - 0.11, stick.c.Z), lk(c))
				Scan.hide(K.hidden, stick.part)
			end
		end)
	end
	-- 지폐교환기
	for _, r in V.byName.ChangeMachine or {} do
		local fp = r.max.Z + 0.012
		local f = faceCF(V3(r.c.X, 0, fp), V3(0, 0, 1))
		K:free(function()
			K:plate("ChangePanel", r.size.X, 2.2, 0.03, f * CF(0, 2.0, 0), lk(rgb(30, 30, 34), M.Metal))
			K:plate("ChangeBillSlot", 0.8, 0.16, 0.06, f * CF(0, 2.6, 0), Look.black)
			K:plate("ChangeBillLight", 0.7, 0.04, 0.065, f * CF(0, 2.6, 0), Look.ledGreen)
			K:plate("ChangeCoinCup", 0.8, 0.5, 0.2, f * CF(0, 1.0, 0), Look.chrome)
			K:text("ChangeLabel", r.size.X * 0.9, 0.6, f * CF(0, 3.4, 0.035), "지폐교환기\n1,000 · 5,000 · 10,000원", { fg = rgb(255, 255, 255), font = F.GothamBold, d = 0.005 })
			K:text("ChangeNotice", r.size.X * 0.9, 0.4, f * CF(0, 1.6, 0.035), "고장 · 분실 문의 010-5150-0511", { fg = rgb(255, 230, 90), font = F.GothamMedium, d = 0.005 })
		end)
	end
end

-- 5) 뒷벽 메뉴판 · 로고 · 빵 시간표
local function stepBackWall(K: any, V: any, B: any, ctx: any)
	local st = { kind = B.menuKind, bg = B.menuBg, fg = B.menuFg, acc = B.menuAcc, tfont = (if B.menuKind == "chalk" then F.PermanentMarker elseif B.menuKind == "brass" then F.Garamond else F.GothamBlack) }
	local menus = B.menus or {}
	-- 판 자리: 뒷벽 빈 구간 (넓으면 2~3 장으로 나눔). 계산대 뒤 직원 자리(6.5 까지) · 사업자등록증 위
	local function backSlots(y0: number, y1: number): { any }
		local slots = {}
		local spans = freeSpans(K, "back", y0, y1, 1.0)
		table.sort(spans, function(a, b)
			return a[1] < b[1]
		end)
		for _, sp in spans do
			local len = sp[2] - sp[1] - 0.3
			if len >= 2.0 then
				local nb = math.clamp(math.floor((len + 0.5) / 3.4), 1, 3)
				local bw = math.min(4.6, (len - (nb - 1) * 0.5) / nb)
				local total = nb * bw + (nb - 1) * 0.5
				local start = (sp[1] + sp[2]) / 2 - total / 2
				for k = 1, nb do
					table.insert(slots, { u = start + (k - 0.5) * bw + (k - 1) * 0.5, w = bw, y0 = y0, y1 = y1, wall = "back" })
				end
			end
		end
		return slots
	end
	local y1 = math.min(V.H - 0.35, 9.9)
	local slots = backSlots(math.max(6.8, y1 - 3.0), y1)
	if #slots == 0 then
		slots = backSlots(math.max(5.9, y1 - 3.2), y1)
	end
	local mi = 0
	local litDone = false
	local function place(sl: any, sec: any)
		local h = sl.y1 - sl.y0
		local dcf = V:wall(sl.wall, sl.u, sl.y0 + h / 2, 0)
		useWall(K, sl.wall, sl.u - sl.w / 2 - 0.15, sl.u + sl.w / 2 + 0.15, sl.y0, sl.y1)
		if sec then
			local face = menuPanel(K, dcf, sl.w, h - 0.2, sec[1], sec[2], st)
			if sl.wall == "back" then
				table.insert(ctx.boards, { u = sl.u, w = sl.w, y = sl.y0 + h / 2 })
			end
			if face and not litDone and (B.menuKind == "lightbox" or B.menuKind == "tv") then
				litDone = true
				K:light(face, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 7, Brightness = 0.35, Angle = 110, Color = lt(B.menuBg, 0.5) })
			end
		else
			-- 남는 칸: 프로모 포스터 (사진 메뉴)
			local pw, ph = sl.w, h - 0.2
			K:plate("PromoBack", pw + 0.1, ph + 0.1, 0.06, dcf, Look.blackMetal)
			K:plate("PromoFace", pw, ph, 0.02, dcf * CF(0, 0, 0.06), lk(B.c1))
			K:text("PromoTag", pw * 0.5, 0.36, dcf * CF(0, ph / 2 - 0.35, 0.085), B.promo[1], { fg = B.paper, bg = B.c2 or BLACK, font = F.GothamBlack, d = 0.01 })
			glyph(K, dcf * CF(0, 0.05, 0.085), math.min(ph * 0.5, pw * 0.9), if B.type == "dessert" then "strawberry" else "latte")
			K:text("PromoName", pw * 0.9, 0.42, dcf * CF(0, -ph / 2 + 0.75, 0.085), B.promo[2], { fg = B.ink, font = F.GothamBlack, d = 0.01 })
			K:text("PromoPrice", pw * 0.6, 0.34, dcf * CF(0, -ph / 2 + 0.32, 0.085), B.promo[3] .. "원", { fg = B.ink, font = F.GothamBold, d = 0.01 })
		end
	end
	for idx, sl in slots do
		if mi >= #menus and idx > 3 then
			break
		end
		if mi < #menus then
			mi += 1
			place(sl, menus[mi])
		else
			place(sl, nil)
		end
	end
	-- 남은 메뉴: 계산대 가까운 옆벽 (뒤쪽 끝)
	if mi < #menus then
		local order = { "left", "right" }
		if ctx.main and (ctx.main.min.X + ctx.main.max.X) / 2 > ctx.cx then
			order = { "right", "left" }
		end
		for _, s in order do
			if mi < #menus then
				local zt = if ctx.main then math.max(V.z0 + 1.8, ctx.main.min.Z + 0.6) else V.z0 + 2
				local wn, dcf, u = wallFind(K, { s }, 3.3, 5.6, 8.6, uOf(V, s, 0, zt))
				if wn and dcf and u then
					mi += 1
					K.wallUsed[#K.wallUsed] = nil
					place({ wall = s, u = u, w = 3.0, y0 = 5.6, y1 = 8.6 }, menus[mi])
				end
			end
		end
	end
	ctx.menuPlaced = mi
	-- 메뉴판 아래 띠 (프랜차이즈: BEST 음료 사진 4)
	if (B.key == "mega" or B.key == "compose" or B.key == "busan" or B.type == "dessert") and V.H > 9 then
		local wn, dcf = wallFind(K, { "back" }, 5.6, 5.95, 6.5 + (if ctx.backSign then 1.2 else 0.0), ctx.backSign and (ctx.backSign.c.X - ctx.cx) or 0)
		if wn and dcf then
			local bh = if ctx.backSign then 1.6 else 0.5
			local bw = 5.4
			K:plate("BestStripBack", bw + 0.1, bh + 0.08, 0.05, dcf, Look.blackMetal)
			K:plate("BestStrip", bw, bh, 0.02, dcf * CF(0, 0, 0.05), lk(if B.key == "mega" then rgb(28, 28, 28) else B.paper))
			if bh > 1 then
				local kinds = { "americano", "latte", "strawberry", "ade" }
				for k = 1, 4 do
					local x = -bw / 2 + bw * (k - 0.5) / 4
					glyph(K, dcf * CF(x - 0.35, 0.0, 0.075), 1.1, kinds[k])
					local it = (B.menus[1] and B.menus[1][2][k]) or { "", "" }
					K:text("BestName", 0.75, 0.28, dcf * CF(x + 0.3, 0.18, 0.075), it[1], { fg = if B.key == "mega" then rgb(255, 255, 255) else B.ink, glow = 0.9, font = F.GothamBold, d = 0.005 })
					K:text("BestPrice", 0.6, 0.24, dcf * CF(x + 0.3, -0.18, 0.075), it[2] or "", { fg = B.c1, glow = 0.9, font = F.GothamBlack, d = 0.005 })
				end
			else
				K:text("BestLine", bw * 0.9, 0.34, dcf * CF(0, 0, 0.075), B.slogan, { fg = if B.key == "mega" then B.c1 else B.ink, glow = 0.9, font = F.GothamBlack, d = 0.005 })
			end
		end
	end
	-- 베이커리: 빵 나오는 시간 + 원산지 표시판
	if B.key == "bakery" then
		local wn, dcf = wallFind(K, { "back", "left", "right" }, 2.4, 5.8, 8.6, -V.W * 0.25)
		if wn and dcf then
			K:plate("BakeTimeFrame", 2.5, 2.9, 0.08, dcf, Look.walnut)
			K:plate("BakeTimeBoard", 2.3, 2.7, 0.1, dcf, lk(rgb(36, 40, 36), M.Slate))
			K:text("BakeTimeTitle", 2.0, 0.36, dcf * CF(0, 1.05, 0.11), "빵 나오는 시간", { fg = rgb(246, 210, 120), font = F.PermanentMarker })
			K:text("BakeTimeList", 2.1, 1.9, dcf * CF(0, -0.2, 0.11), "07:00  소금빵 · 크루아상\n09:30  우유식빵 · 바게트\n12:00  고로케 · 단팥빵\n15:00  마늘바게트 · 에그타르트\n18:00  앙버터 · 치아바타", { fg = rgb(244, 240, 228), font = F.GothamMedium, align = "Left" })
		end
	end
	-- 브랜드 로고 (뒷벽에 맵 간판이 없을 때)
	if not ctx.backSign then
		local wn, dcf = wallFind(K, { "back" }, math.min(7, V.W * 0.4), y1 + 0.05, math.min(V.H - 0.15, y1 + 0.9), 0)
		if wn and dcf then
			local chain = B.key == "mega" or B.key == "compose" or B.key == "tanghulu" or B.key == "claw"
			K:text("BackLogo", math.min(6.8, V.W * 0.38), 0.7, dcf * CF(0, 0, 0.06), B.title, { fg = if chain then B.c1 else B.ink, glow = if chain then 1.0 else nil, font = if B.key == "bakery" or B.key == "haute" then F.Garamond else F.GothamBlack, d = 0.06 })
		end
	end
end

-- 계산대 뒤 벽 (뒷선반 위 ~ 천장 간판 아래, 6.6 ~ 8.9) 빈 구간: 브랜드별로
--   프랜차이즈 · 디저트 = 사진 메뉴 포스터 (태그 · 음료 그림 · 이름 · 가격), 오뜨 · 라운지 · 투썸 · 파스쿠찌 = 황동 아치 거울 +
--   사이 벽등, 베이커리 = 빵 그림 액자. 벽에 붙는 판뿐 (깊이 < 0.2) 이라 직원 자리 · 선반과 안 부딪힘
local MIRROR_KEYS = { haute = true, lounge = true, twosome = true, pascucci = true, green = true }
local POSTER_TAGS = { "BEST", "NEW", "SIGNATURE", "시즌 한정", "추천" }
local function backBarWall(K: any, V: any, B: any, ctx: any)
	if B.key == "starbucks" or B.key == "lobby" or B.key == "claw" or not V.walls.back or not ctx.main then
		return
	end
	local y0, y1 = 6.6, math.min(V.H - 1.0, 8.9)
	if ctx.backSign then
		-- 맵 간판 (Sign_) 밑까지만 (간판 자리는 위아래 0.2 여유로 등록돼 있음)
		y1 = math.min(y1, ctx.backSign.min.Y - 0.3)
	end
	if y1 - y0 < 1.7 then
		return
	end
	local items = {}
	for _, sec in B.menus or {} do
		for _, it in sec[2] do
			table.insert(items, it)
		end
	end
	if #items == 0 then
		return
	end
	local cx0, cx1 = ctx.main.min.X - 0.5, ctx.main.max.X + 0.5
	if ctx.back then
		cx0, cx1 = math.min(cx0, ctx.back.min.X - 0.5), math.max(cx1, ctx.back.max.X + 0.5)
	end
	local mirror = MIRROR_KEYS[B.key] == true
	local k = 0
	local placed = 0
	for _, s in freeSpans(K, "back", y0, y1, 1.0) do
		-- 계산대 폭 안쪽만 (손님 쪽 벽은 stepFill 이 채움)
		local a, b = math.max(s[1], cx0 - ctx.cx), math.min(s[2], cx1 - ctx.cx)
		local len = b - a
		if len >= 2.4 and placed < 6 and room(K, 40) then
			-- 구간을 같은 칸으로 나눠 칸 가운데에 (긴 벽은 리듬 있게 6 장까지)
			local n = math.clamp(math.floor((len + 0.4) / (if mirror then 3.2 else 3.0)), 1, 6)
			local cell = len / n
			local pw = math.min(if mirror then math.min(2.0, (y1 - y0) * 0.82) else 2.3, cell - 0.6)
			local ph = math.min(y1 - y0 - 0.2, if mirror then 2.3 else pw * 1.2)
			local yc = y0 + (y1 - y0) / 2
			for j = 1, n do
				if not room(K, 26) or placed >= 6 then
					break
				end
				k += 1
				placed += 1
				local u = a + (j - 0.5) * cell
				if mirror then
					local r = pw / 2
					local rectH = ph - r
					local yb = yc - ph / 2
					local frameL = if B.key == "twosome" then Look.blackMetal else Look.goldMetal
					K:plate("ArchMirrorFrame", pw + 0.14, rectH, 0.04, V:wall("back", u, yb + rectH / 2, 0.01), frameL)
					wdisc(K, "ArchMirrorFrameTop", pw + 0.14, 0.04, V:wall("back", u, yb + rectH, 0.01), frameL)
					K:plate("ArchMirror", pw, rectH - 0.07, 0.02, V:wall("back", u, yb + rectH / 2 + 0.035, 0.05), Look.mirror)
					wdisc(K, "ArchMirrorTop", pw, 0.02, V:wall("back", u, yb + rectH, 0.05), Look.mirror)
					if j < n then
						-- 사이 벽등 (황동 팔 + 우윳빛 글로브)
						local sx = u + cell / 2
						local sd = V:wall("back", sx, yc + 0.2, 0.01)
						K:plate("SconcePlate", 0.2, 0.34, 0.04, sd, frameL)
						K:box("SconceArm", V3(0.05, 0.05, 0.36), sd * CF(0, 0.05, 0.2), frameL)
						K:ball("SconceGlobe", 0.32, sd * CF(0, 0.22, 0.36), lk(rgb(255, 244, 226), M.Neon))
					end
				else
					local it = items[(k * 3 + B.seed) % #items + 1]
					local dcf = V:wall("back", u, yc, 0)
					if B.key == "bakery" then
						artPiece(K, dcf, pw, ph, "bread", B, 40 + k)
					else
						local face = if B.key == "mega" or B.key == "compose" then B.c1 elseif B.type == "dessert" then lt(B.c1, 0.55) else B.paper
						local ink = onColor(face)
						K:plate("PosterFrame", pw + 0.1, ph + 0.1, 0.05, dcf, Look.blackMetal)
						K:text("PosterFace", pw, ph, dcf * CF(0, 0, 0.05), " ", { bg = face, glow = 0.7, d = 0.02 })
						K:text("PosterTag", pw * 0.5, 0.3, dcf * CF(-pw * 0.2, ph / 2 - 0.28, 0.072), POSTER_TAGS[(k + B.seed) % #POSTER_TAGS + 1], { fg = face, bg = B.c2 or BLACK, font = F.GothamBlack, d = 0.006 })
						glyph(K, dcf * CF(0, 0.08, 0.075), math.min(ph * 0.48, pw * 0.8), it[3] or (if B.type == "dessert" then "strawberry" else "latte"))
						K:text("PosterName", pw * 0.9, 0.34, dcf * CF(0, -ph / 2 + 0.62, 0.072), it[1], { fg = ink, glow = 0.7, font = F.GothamBlack, d = 0.006 })
						K:text("PosterPrice", pw * 0.6, 0.28, dcf * CF(0, -ph / 2 + 0.27, 0.072), (it[2] or "") .. "원", { fg = if B.key == "mega" then rgb(24, 24, 24) else dk(B.c1, 0.1), glow = 0.7, font = F.GothamBold, d = 0.006 })
					end
				end
				useWall(K, "back", u - pw / 2 - 0.2, u + pw / 2 + 0.2, y0, y1)
			end
		end
	end
	ctx.backBar = placed
end

-- 벽시계 (옆벽 뒤쪽, 실제 게임 시각)
local function wallClock(K: any, V: any, B: any)
	local h = math.min(V.H - 1.4, 7.6)
	local prefer = { left = uOf(V, "left", 0, V.z0 + 3.5), right = uOf(V, "right", 0, V.z0 + 3.5), back = 0 }
	local wn, dcf = wallFind(K, { "left", "right", "back" }, 1.6, h - 0.8, h + 0.8, prefer)
	if wn and dcf then
		local look = if B.key == "haute" or B.key == "lounge" or B.key == "pascucci" then { frame = Look.goldMetal } elseif B.key == "scandi" or B.key == "bakery" or B.key == "terracotta" then { frame = Look.oak } else nil
		local hr, mn = Props.clock(K, dcf, 1.4, look)
		Interact.clock(K, hr, mn, dcf, 1.4)
	end
end

-- 6) 옆벽
local function stepSideWalls(K: any, V: any, B: any, ctx: any)
	wallClock(K, V, B)
	local sides = { "left", "right" }
	local frontU = { left = uOf(V, "left", 0, V.z1 - 5), right = uOf(V, "right", 0, V.z1 - 5) }
	local midU = { left = uOf(V, "left", 0, ctx.cz), right = uOf(V, "right", 0, ctx.cz) }
	local promptPred = promptOK(K)
	-- 네온 (켜기/끄기)
	local nt = B.neon
	if nt and B.key ~= "claw" then
		local nw = math.clamp(utf8.len(nt[1]) or #nt[1], 6, 18) * 0.26 + 0.5
		local wn, dcf = promptSpot(K, { "left", "right", "back" }, nw + 0.5, { { 5.3, 6.7 }, { 5.7, 6.9 }, { 4.9, 6.3 } }, midU)
		local withPrompt = wn ~= nil
		if not wn then
			wn, dcf = wallFind(K, sides, nw + 0.5, 5.3, 6.7, midU)
		end
		if wn and dcf then
			local sign = neonSign(K, dcf, nw, 0.9, nt[1], nt[2], nt[3])
			if withPrompt then
				neonToggle(K, sign, "네온사인")
			end
		end
	end
	-- BGM 앰프 + 스피커
	local wn, dcf = promptSpot(K, { "left", "right", "back" }, 1.6, { { 3.85, 4.75 }, { 4.9, 5.8 }, { 5.45, 6.35 } }, frontU)
	if not wn then
		wn, dcf = promptSpot(K, { "left", "right", "back" }, 1.15, { { 3.85, 4.75 }, { 4.9, 5.8 }, { 5.45, 6.35 } }, frontU)
	end
	if wn and dcf then
		musicPanel(K, dcf, B, false)
	end
	local _ = promptPred
	for _, s in sides do
		local w2, d2 = wallFind(K, { s }, 0.8, V.H - 1.75, V.H - 0.55, if s == "left" then uOf(V, s, 0, V.z1 - 3.5) else uOf(V, s, 0, V.z1 - 3.5))
		if w2 and d2 then
			speaker(K, d2 * CF(0, 0.05, 0))
		end
	end
	-- 안내 보드 (와이파이 · 영업시간 · 결제)
	local wi, di = wallFind(K, sides, 2.2, 3.6, 6.1, frontU)
	if wi and di then
		infoBoard(K, di, B)
	end
	-- TV 프로모 (프랜차이즈)
	if B.feat.tv then
		local wt, dt = wallFind(K, sides, 3.2, 5.7, 7.6, midU)
		if wt and dt then
			promoScreen(K, dt, 3.0, {
				{ text = B.promo[1] .. "\n" .. B.promo[2] .. "\n" .. B.promo[3] .. "원", c = B.c1, fg = B.c2 or BLACK },
				{ text = "ICE AMERICANO\n" .. (B.menus[1][2][1][2]) .. "원", c = rgb(24, 24, 26), fg = B.c1 },
				{ text = "앱 주문하고\n스탬프 2배 적립", c = rgb(250, 250, 248), fg = rgb(24, 24, 26) },
			})
		end
	end
	-- 거울 (오뜨)
	if B.feat.mirror then
		local wm, dm = wallFind(K, sides, 2.6, 3.3, 8.0, midU)
		if wm and dm then
			K:panel("MirrorFrame", 2.5, 4.6, 0.1, 0.5, dm, Look.goldMetal)
			K:panel("Mirror", 2.25, 4.35, 0.12, 0.42, dm, Look.mirror)
		end
	end
	-- 액자
	local artKinds = { B.art, if B.key == "busan" or B.key == "ocean" or B.key == "mega" then "bridge" else "abstract", "bridge", B.art }
	local nArt = if V.W * V.D > 500 then 4 elseif V.W * V.D > 250 then 3 else 2
	for k = 1, nArt do
		local aw = if k % 2 == 1 then 2.6 else 2.0
		local ah = if k % 2 == 1 then 2.0 else 2.6
		local s = if k % 2 == 1 then { "left", "right" } else { "right", "left" }
		local wa, da = wallFind(K, s, aw + 0.3, 6.6 - ah - 0.1, 6.7, midU)
		if not wa then
			wa, da = wallFind(K, s, aw + 0.3, 7.0 - ah, 7.2, frontU)
		end
		if wa and da then
			artPiece(K, da * CF(0, 0, 0.01), aw, ah, artKinds[(k - 1) % #artKinds + 1], B, k)
		end
	end
	-- 높은 천장: 윗벽 큰 그림 (7 ~ 9.4)
	if V.H >= 10.4 then
		for k, sd in { "right", "left" } do
			local wa, da = wallFind(K, { sd }, 3.9, 7.0, 9.4, midU)
			if wa and da then
				artPiece(K, da * CF(0, 0, 0.01), 3.6, 2.2, if k == 1 then (if B.art == "gallery" then "abstract" else "gallery") else B.art, B, 10 + k)
			end
		end
	end
	-- 벽 선반 (식물 · 책 · 원두)
	local ws, dsh = wallFind(K, sides, 3.2, 6.9, 8.1, midU)
	if ws and dsh then
		local at = Props.shelf(K, dsh * CF(0, -0.45, 0), 3.0, { depth = 0.75, look = if B.key == "roastery" then Look.walnut else Look.oak })
		Props.row(K, at, 2.9, if B.type == "bakery" then "jars" elseif B.key == "roastery" then "books" else "plants", { seed = B.seed % 97, n = if B.key == "roastery" then 10 else 4 })
	end
	-- 위생 · 원산지 · 콘센트 안내
	local wn2, dn = nil, nil
	if B.key ~= "lobby" then
		wn2, dn = wallFind(K, sides, 1.0, 4.2, 5.2, frontU)
	end
	if wn2 and dn then
		K:panel("HygieneBadge", 0.85, 0.85, 0.03, 0.42, dn, lk(rgb(30, 110, 200)))
		K:text("HygieneText", 0.7, 0.5, dn * CF(0, 0, 0.035), "위생등급\n매우 우수", { fg = rgb(255, 255, 255), font = F.GothamBold, d = 0.005 })
	end
	if B.type == "bakery" or B.type == "dessert" or B.key == "haute" then
		local wo, dor = wallFind(K, { "left", "right", "back" }, 1.9, 3.5, 5.3, frontU)
		if wo and dor then
			notice(K, dor, 1.8, 1.6, "원산지 표시\n밀가루: 미국산 · 캐나다산\n버터: 뉴질랜드산\n우유 · 계란: 국내산\n딸기: 국내산 (논산)\n팥: 국내산", rgb(30, 30, 30), rgb(250, 250, 246))
		end
	elseif B.key ~= "lobby" then
		local wo, dor = wallFind(K, sides, 1.5, 3.2, 3.9, midU)
		if wo and dor then
			notice(K, dor, 1.4, 0.55, "콘센트 사용 가능\n노트북 이용 2시간", rgb(40, 40, 40), rgb(250, 248, 240))
		end
	end
	-- 벽등 (고급 카페: 브라스 팔 + 유리구)
	if B.key == "haute" or B.key == "lounge" or B.key == "pascucci" or B.key == "twosome" or B.key == "green" or B.key == "lobby" then
		local n = 0
		for _, s in sides do
			for k = 1, 3 do
				local target = (V.walls[s].a + V.walls[s].b) / 2 + (k - 2) * V.D * 0.3
				local wl, dl = wallFind(K, { s }, 0.8, 6.9, 7.9, target)
				if wl and dl and n < 6 then
					n += 1
					wdisc(K, "SconcePlate", 0.34, 0.05, dl * CF(0, -0.2, 0), Look.brass)
					K:bar("SconceArm", (dl * CF(0, -0.2, 0.05)).Position, (dl * CF(0, 0.05, 0.42)).Position, 0.06, 0.06, Look.brass)
					K:vcyl("SconceCup", 0.12, 0.2, dl * CF(0, 0.08, 0.45), Look.brass)
					K:ball("SconceGlobe", 0.4, dl * CF(0, 0.32, 0.45), glassL(rgb(255, 244, 226), 0.35))
					K:ball("SconceBulb", 0.16, dl * CF(0, 0.3, 0.45), Look.lampWarm)
				end
			end
		end
	end
	-- 윗벽 띠 문구
	if V.H >= 9.5 and B.key ~= "claw" then
		for _, s in sides do
			local wl, dl = wallFind(K, { s }, math.min(9, V.D * 0.5), 8.35, 9.05, midU)
			if wl and dl then
				K:text("WallSlogan", math.min(8.6, V.D * 0.48), 0.5, dl * CF(0, 0, 0.02), B.slogan, { fg = if B.key == "mega" then rgb(30, 30, 30) elseif B.key == "compose" then B.c1 elseif B.type == "dessert" then dk(B.c1, 0.15) else B.ink, font = F.GothamBlack, d = 0.02 })
			end
		end
	end
end

-- 인형뽑기방 벽 (기계 위 높은 띠 + 조작 패널)
local function stepClawWalls(K: any, V: any, B: any, ctx: any)
	wallClock(K, V, B)
	local promptPred = promptOK(K)
	local midU = { left = uOf(V, "left", 0, ctx.cz), right = uOf(V, "right", 0, ctx.cz) }
	local wn, dcf = wallFind(K, { "back" }, 7.0, 8.3, 10.2, 0)
	if wn and dcf then
		ctx.clawSign = neonSign(K, dcf, 6.4, 1.5, B.neon[1], B.neon[2], B.neon[3])
	end
	local words = { "PICK ME UP!", "오늘은 꼭 뽑자!" }
	ctx.wallNeons = {}
	for k, s in { "left", "right" } do
		local w2, d2 = wallFind(K, { s }, 6.0, 8.4, 9.8, midU[s])
		if w2 and d2 then
			table.insert(ctx.wallNeons, neonSign(K, d2, 5.4, 1.0, words[k], if k == 1 then rgb(80, 220, 255) else rgb(255, 210, 60), F.FredokaOne, false))
		end
	end
	-- 조작 패널 (LED 모드) + BGM
	local _ = promptPred
	local wp, dp = promptSpot(K, { "left", "right", "back" }, 0.95, { { 3.9, 4.9 }, { 5.5, 6.5 }, { 4.9, 5.9 } }, midU)
	if wp and dp then
		K:plate("LEDPanel", 0.85, 0.9, 0.08, dp, Look.of(30, 30, 34, Enum.Material.Metal))
		local scr, lab = K:text("LEDPanelScreen", 0.7, 0.3, dp * CF(0, 0.16, 0.09), "LED: PARTY", { fg = rgb(255, 120, 220), bg = rgb(10, 8, 16), glow = 1.3, font = F.Code, d = 0.01 })
		for k = -1, 1 do
			wdisc(K, "LEDPanelButton", 0.16, 0.04, dp * CF(k * 0.24, -0.22, 0.08), Look.neon(if k == -1 then rgb(255, 60, 160) elseif k == 0 then rgb(60, 200, 255) else rgb(255, 220, 60)))
		end
		local signs = {}
		if ctx.clawSign then
			table.insert(signs, ctx.clawSign)
		end
		for _, sg in ctx.wallNeons or {} do
			table.insert(signs, sg)
		end
		local modes = { { "PARTY", nil }, { "PINK", rgb(255, 80, 180) }, { "OCEAN", rgb(60, 190, 255) }, { "GOLD", rgb(255, 200, 60) }, { "OFF", rgb(60, 60, 70) } }
		local leds = {}
		for _, p in ctx.clawLeds or {} do
			table.insert(leds, { p = p, c = p.Color })
		end
		local mode = 1
		Interact.cycle(K, scr, modes, {
			action = "LED 모드",
			object = "매장 조명",
			on = function(i: number, m: any)
				mode = i
				lab.Text = "LED: " .. m[1]
				for _, l in leds do
					if l.p.Parent then
						l.p.Color = m[2] or l.c
						l.p.Material = if m[1] == "OFF" then M.SmoothPlastic else M.Neon
					end
				end
				local off = m[1] == "OFF"
				for _, sg in signs do
					local gui = sg.part and sg.part:FindFirstChildWhichIsA("SurfaceGui")
					if sg.label then
						sg.label.TextColor3 = if off then dk(sg.color, 0.6) else sg.color
					end
					if gui then
						gui.Brightness = if off then 1 else 2.1
						gui.LightInfluence = if off then 1 else 0
					end
					if sg.light then
						sg.light.Enabled = not off
					end
				end
			end,
		})
		Interact.anim(K, function(t: number)
			if mode ~= 1 then
				return
			end
			for k, l in leds do
				if l.p.Parent then
					local f = 0.5 + 0.5 * math.sin(t * 3 + k * 0.7)
					l.p.Color = l.c:Lerp(WHITE, f * 0.35)
				end
			end
		end)
	end
	local wm, dm = promptSpot(K, { "right", "left", "back" }, 1.05, { { 3.85, 4.75 }, { 5.5, 6.4 }, { 4.9, 5.8 } }, midU)
	if wm and dm then
		musicPanel(K, dm, B, true)
	end
	-- 안내 (가격 · CCTV · 무인)
	local wi, di = wallFind(K, { "left", "right", "back" }, 1.8, 5.2, 7.0, midU)
	if wi and di then
		notice(K, di, 1.7, 1.6, "1PLAY 1,000원\n5,000원 = 6PLAY\n\nCCTV 24시간 녹화중\n무인 운영 매장입니다", rgb(255, 255, 255), rgb(40, 20, 60))
	end

	-- 아이스크림 냉동고 뚜껑 (밀어 열기)
	if ctx.freezer and ctx.freezer.Parent then
		local lid: BasePart = ctx.freezer
		local base = lid.CFrame
		local w = lid.Size.X
		Interact.toggle(K, lid, {
			object = "아이스크림 냉동고",
			onText = "뚜껑 열기",
			offText = "뚜껑 닫기",
			state = true,
			on = function(state: boolean)
				lid.CFrame = if state then base else base * CF(w * 0.9, 0.04, 0)
			end,
		})
	end
end

-- 7) 천장
local function stepCeiling(K: any, V: any, B: any, ctx: any)
	local feat = B.feat or {}
	if feat.ducts then
		ducts(K, V)
	end
	-- 메뉴판 레일 조명 (칠판 · 펠트 · 브라스)
	if (feat.track or B.menuKind == "chalk" or B.menuKind == "felt" or B.menuKind == "brass") and #ctx.boards > 0 then
		local z = V.z0 + 2.2
		for _, b in ctx.boards do
			local x = b.u + ctx.cx
			if Common.ceilFree(K, x, z, 0.6) then
				Props.trackLight(K, V3(x - b.w / 2 + 0.3, 0, z), V3(x + b.w / 2 - 0.3, 0, z), math.max(2, math.floor(b.w / 1.5)), { aim = V3(0, -1, -1.1), look = Look.blackMetal })
				Common.useCeil(K, x, z)
			end
		end
	end
	-- 픽업 전광판
	if ctx.main and B.feat.pickup ~= false and not B.noCounter then
		local g = ctx.main
		local n = ctx.n
		local x, z
		if ctx.alongX then
			x = ctx.pickU
			z = if n.Z > 0 then g.max.Z + 0.6 else g.min.Z - 0.6
		else
			z = ctx.pickU
			x = if n.X > 0 then g.max.X + 0.6 else g.min.X - 0.6
		end
		local fx, fz = nil, nil
		for _, dz in { 0, 0.6, 1.2, 1.8, 2.4 } do
			for k = 0, 8 do
				local off = (if k % 2 == 0 then 1 else -1) * math.floor((k + 1) / 2) * 0.6
				local xx = if ctx.alongX then x + off else x + n.X * dz
				local zz = if ctx.alongX then z + n.Z * dz else z + off
				if not fx and Common.ceilFree(K, xx, zz, 1.25) then
					fx, fz = xx, zz
				end
			end
		end
		if fx and fz then
			pickupBoard(K, fx, fz, n, B)
			Common.useCeil(K, fx, fz)
		end
	end
	-- 행잉 화분
	if feat.hangPlants then
		local n = 0
		for _, f in { { 0.25, 0.55 }, { 0.75, 0.55 }, { 0.5, 0.7 }, { 0.15, 0.75 } } do
			local x, z = V.x0 + V.W * f[1], V.z0 + V.D * f[2]
			if n < 3 and Common.ceilFree(K, x, z, 0.8) then
				hangingPlant(K, x, z, 2.2 + (n % 2) * 0.5)
				Common.useCeil(K, x, z)
				n += 1
			end
		end
	end
	-- 인형뽑기방: 천장 LED 띠
	if feat.leds then
		local cols = { rgb(255, 70, 190), rgb(70, 210, 255) }
		local y = V.H - 0.06
		K:free(function()
			for k = 0, 3 do
				local z = V.z0 + V.D * (0.15 + k * 0.23)
				local p = K:box("CeilingLED", V3(V.W - 1.0, 0.05, 0.1), CF(ctx.cx, y, z), Look.neon(cols[k % 2 + 1]))
				table.insert(ctx.clawLeds, p)
			end
			for _, s in { -1, 1 } do
				local p = K:box("CeilingLED", V3(0.1, 0.05, V.D - 1.0), CF(ctx.cx + s * (V.W / 2 - 0.6), y, ctx.cz), Look.neon(cols[1]))
				table.insert(ctx.clawLeds, p)
			end
		end)
	end
end

-- 8) 유형 특수: 로스터 · 오븐 · 탕후루 · 아일랜드 · 집게 (바닥 단계에서 정한 자리)
-- 쟁반 스테이션 (맵 TrayStation = 호스트 앵커): 같은 자세 · 같은 윗면의 원목 캐비닛 리스킨 후 원본 숨김.
--   앞면: 쟁반이 꽂힌 칸 (쟁반 모서리 줄) + 문짝 2 + 손잡이 + 걸레받이, 위: 대리석 상판, 앞 띠에 "쟁반 · 집게"
local function trayStationSkin(K: any, V: any, B: any, r: any)
	if not room(K, 30) then
		return
	end
	local d = V3((V.x0 + V.x1) / 2, 0, (V.z0 + V.z1) / 2) - r.c
	local fwd = if math.abs(d.X) > math.abs(d.Z) then V3(math.sign(d.X), 0, 0) else V3(0, 0, math.sign(d.Z))
	local depth = math.abs(fwd.X) * r.size.X + math.abs(fwd.Z) * r.size.Z
	local width = math.abs(fwd.Z) * r.size.X + math.abs(fwd.X) * r.size.Z
	local h = r.size.Y
	local y0 = r.min.Y
	local front = faceCF(V3(r.c.X, y0, r.c.Z) + fwd * (depth / 2), fwd)
	local wood = if B.type == "bakery" then Look.oak elseif B.key == "tanghulu" then lk(rgb(240, 236, 232)) else lk(lt(B.c1, 0.35))
	local edge = lk(dk((wood :: any).c, 0.2), (wood :: any).m)
	K:free(function()
		K:box("TrayBody", V3(width, h - 0.1, depth - 0.04), front * CF(0, (h - 0.1) / 2, -(depth - 0.04) / 2 - 0.04), wood)
		K:box("TrayTop", V3(width, 0.1, depth), front * CF(0, h - 0.05, -depth / 2), Look.marbleWhite)
		K:plate("TrayKick", width - 0.1, 0.3, 0.02, front * CF(0, 0.15, -0.04), Look.black)
		-- 쟁반 칸 (위쪽 40%)
		local cubH = h * 0.38
		local cy = h - 0.1 - 0.1 - cubH / 2
		K:plate("TrayCubby", width - 0.3, cubH, 0.01, front * CF(0, cy, -0.04), lk(dk((wood :: any).c, 0.55)))
		local n = math.max(4, math.floor(cubH / 0.13))
		for k = 1, n do
			local col = if k % 2 == 0 then rgb(120, 80, 50) else rgb(140, 96, 60)
			K:plate("TrayEdge", width - 0.42, 0.05, 0.03, front * CF(0, cy - cubH / 2 + k * cubH / (n + 1), -0.04), lk(col))
		end
		-- 문짝 2 + 손잡이
		local doorH = h - 0.3 - cubH - 0.35
		for _, sx in { -1, 1 } do
			local dc = front * CF(sx * width / 4, 0.3 + 0.05 + doorH / 2, -0.04)
			K:plate("TrayDoor", width / 2 - 0.12, doorH, 0.03, dc, edge)
			K:plate("TrayDoorInset", width / 2 - 0.4, doorH - 0.3, 0.035, dc, wood)
			K:plate("TrayDoorHandle", 0.06, 0.5, 0.06, dc * CF(-sx * (width / 4 - 0.22), 0.1, 0), Look.brass)
		end
		K:text("TraySign", math.min(width - 0.3, 2.2), 0.22, front * CF(0, h - 0.1 - 0.06, -0.035), if B.type == "bakery" then "쟁반 · 집게 TRAY & TONGS" else "쟁반 · 스푼 · 냅킨", { fg = rgb(60, 40, 30), d = 0.005, font = F.GothamBold })
	end)
	Scan.hide(K.hidden, r.part)
end

local function stepSpecial(K: any, V: any, B: any, ctx: any)
	local R = ctx.roaster
	if R and R.panel and R.panel.Parent then
		local on = false
		local ang = 0
		Interact.toggle(K, R.panel, {
			object = "커피 로스터",
			onText = "로스팅 시작",
			offText = "로스팅 멈춤",
			state = true,
			on = function(_s: boolean)
				on = not on
				if R.glass and R.glass.Parent then
					R.glass.Material = if on then M.Neon else M.Glass
					R.glass.Color = if on then rgb(255, 120, 40) else rgb(120, 70, 40)
				end
				if R.label then
					R.label.Text = if on then "ROASTING\nBT 198℃  ▲" else "STANDBY\nBT 25℃"
				end
			end,
		})
		Interact.anim(K, function(_t: number, dt: number)
			if not on then
				return
			end
			ang += (dt or 0.1) * PI
			local c = CF(R.center)
			for k, a in R.arms do
				if a.Parent then
					a.CFrame = c * ANG(0, ang, 0) * c:Inverse() * R.armBase[k]
				end
			end
		end)
	end
	-- 오븐 창 깜빡임 (불꽃 느낌)
	if ctx.oven and ctx.oven.glows then
		local gl = ctx.oven.glows
		Interact.anim(K, function(t: number)
			for k, g in gl do
				if g.Parent then
					g.Transparency = 0.2 + 0.15 * math.abs(math.sin(t * 1.3 + k))
				end
			end
		end)
	end
	-- 탕후루 쇼케이스 (냉장, 앞 유리) + 꼬치
	if ctx.tangCase and room(K, 170) then
		local pcf: CFrame = ctx.tangCase
		local w, d, h = 3.6, 2.2, 4.4
		K:box("TangCaseBase", V3(w, 2.2, d), pcf * CF(0, 1.1, 0), lk(B.c1))
		K:box("TangCaseKick", V3(w - 0.1, 0.3, 0.05), pcf * CF(0, 0.15, d / 2 + 0.02), Look.black)
		K:text("TangCaseLabel", w * 0.8, 0.5, faceCF((pcf * CF(0, 1.3, d / 2 + 0.01)).Position, pcf.ZVector), "탕후루 · 당일 생과일", { fg = rgb(255, 255, 255), font = F.GothamBlack, d = 0.01 })
		K:box("TangCaseFloor", V3(w - 0.2, 0.06, d - 0.2), pcf * CF(0, 2.23, 0), Look.white)
		K:box("TangCaseGlass", V3(w, 1.7, 0.05), pcf * CF(0, 2.2 + 0.85, d / 2 - 0.03) * ANG(-0.25, 0, 0), glassL(rgb(230, 240, 244), 0.75))
		K:box("TangCaseTop", V3(w, 0.06, d * 0.5), pcf * CF(0, 4.0, -d * 0.25), glassL(rgb(230, 240, 244), 0.7))
		for _, sx in { -1, 1 } do
			K:box("TangCaseSide", V3(0.05, 1.8, d), pcf * CF(sx * (w / 2 - 0.03), 3.1, 0), glassL(rgb(230, 240, 244), 0.75))
		end
		local lamp = K:box("TangCaseLamp", V3(w - 0.3, 0.04, 0.1), pcf * CF(0, 3.95, -0.2), Look.lampNeutral)
		local _ = lamp
		-- 꼬치 (누운 줄 3 x 7 종)
		local rows = 3
		for rr = 0, rows - 1 do
			local zz = -d / 2 + 0.45 + rr * 0.55
			K:box("TangTray", V3(w - 0.4, 0.04, 0.48), pcf * CF(0, 2.28, zz), Look.white)
			for k = 0, 6 do
				local kind = FRUIT_ORDER[(k + rr) % #FRUIT_ORDER + 1]
				local x = -(w - 0.6) / 2 + (w - 0.6) * k / 6
				skewer(K, pcf * CF(x, 2.43, zz + 0.2) * ANG(-PI / 2 + 0.05, 0, 0), kind, 0.9)
			end
			tag(K, faceCF((pcf * CF(0, 2.32, zz + 0.25)).Position, pcf.ZVector), 1.0, 0.12, if rr == 0 then "딸기 3,500 · 샤인 4,500" elseif rr == 1 then "블루베리 4,000 · 귤 3,000" else "키위 3,500 · 토마토 3,000")
		end
		-- 위: 꼬치 스탠드 (세워 꽂은 꼬치)
		local sb = pcf * CF(0.9, 4.03, -d * 0.25)
		K:box("TangStand", V3(1.2, 0.22, 0.4), sb * CF(0, 0.11, 0), Look.walnut)
		for k = 0, 5 do
			skewer(K, sb * CF(-0.5 + k * 0.2, 0.2, 0) * ANG(0, 0, (k - 2.5) * 0.08), FRUIT_ORDER[k % #FRUIT_ORDER + 1], 1.0)
		end
		-- 과일 상자
		local fb = pcf * CF(-0.9, 4.03, -d * 0.25)
		K:box("FruitCrate", V3(1.2, 0.3, 0.8), fb * CF(0, 0.15, 0), Look.pine)
		for k = 0, 9 do
			K:ell("CrateStrawberry", V3(0.2, 0.22, 0.2), fb * CF(-0.45 + (k % 5) * 0.22, 0.36, -0.15 + math.floor(k / 5) * 0.3), lk(rgb(214, 28, 48)))
		end
	end
	-- 베이커리 아일랜드 진열대
	if ctx.island and room(K, 130) then
		local pcf: CFrame = ctx.island
		local w, d, h = 4.2, 2.4, 2.9
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				K:box("IslandLeg", V3(0.2, h - 0.12, 0.2), pcf * CF(sx * (w / 2 - 0.2), (h - 0.12) / 2, sz * (d / 2 - 0.2)), Look.walnut)
			end
		end
		K:box("IslandShelf", V3(w - 0.3, 0.1, d - 0.3), pcf * CF(0, 0.6, 0), Look.walnut)
		K:box("IslandApron", V3(w - 0.2, 0.3, d - 0.2), pcf * CF(0, h - 0.27, 0), Look.walnut)
		K:box("IslandTop", V3(w, 0.12, d), pcf * CF(0, h - 0.06, 0), Look.oak)
		for k = 0, 2 do
			K:box("IslandBagBox", V3(1.0, 0.5, 0.8), pcf * CF(-1.3 + k * 1.3, 0.9, 0), Look.kraft)
		end
		local idx = 0
		for bx = -1, 1 do
			for bz = 0, 1 do
				idx += 1
				local info = BREADS[(idx * 3 + B.seed) % #BREADS + 1]
				local bc = pcf * CF(bx * 1.35, h, (bz - 0.5) * 1.05)
				basket(K, bc, 1.2, 0.9, if idx % 2 == 0 then Look.rattan else Look.of(150, 110, 70, Enum.Material.Wood))
				local kind = info[3]
				local cnt = if kind == "baguette" or kind == "garlic" then 2 elseif kind == "loaf" then 1 else 3
				for j = 1, cnt do
					bread(K, bc * CF((j - (cnt + 1) / 2) * (if cnt == 2 then 0 else 0.36), 0.08, if cnt == 2 then (j - 1.5) * 0.3 else 0) * ANG(0, j * 0.3, 0), kind, if kind == "baguette" or kind == "garlic" then 0.9 else 1.1)
				end
				local zf = if bz == 1 then d / 2 + 0.012 else -d / 2 - 0.012
				local nrm = if bz == 1 then pcf.ZVector else -pcf.ZVector
				tag(K, faceCF((pcf * CF(bx * 1.35, h - 0.27, zf)).Position, nrm), 0.95, 0.22, info[1] .. "  " .. info[2])
			end
		end
	end
	-- 집게 · 쟁반 안내 (TrayStation 옆벽)
	for _, ts in V.byName.TrayStation or {} do
		local best, bw = nil, math.huge
		for _, wn in { "left", "right", "back" } do
			local u, d = V:wallCoord(wn, ts.c)
			if d < bw then
				best, bw = { wn, u }, d
			end
		end
		if best and bw < 2.5 then
			local wn, dcf = wallFind(K, { best[1] }, 2.0, 3.6, 4.6, best[2])
			if wn and dcf then
				K:plate("TongRail", 1.8, 0.08, 0.1, dcf * CF(0, 0.25, 0), Look.chrome)
				for k = 0, 3 do
					local x = -0.6 + k * 0.4
					K:bar("Tong", (dcf * CF(x, 0.22, 0.1)).Position, (dcf * CF(x + 0.04, -0.4, 0.12)).Position, 0.05, 0.03, Look.steel)
					K:bar("Tong", (dcf * CF(x + 0.06, 0.22, 0.1)).Position, (dcf * CF(x + 0.12, -0.4, 0.12)).Position, 0.05, 0.03, Look.steel)
				end
				K:text("TongSign", 1.8, 0.3, dcf * CF(0, 0.52, 0.04), if B.type == "bakery" then "쟁반과 집게를 이용해 주세요" else "쟁반 · 스푼은 이곳에", { fg = rgb(60, 40, 30), bg = rgb(252, 246, 232), d = 0.02, font = F.GothamBold })
			end
		end
		trayStationSkin(K, V, B, ts)
	end
end

-- keep 에 닿되 통로(aisle)뿐인가? (기존 가구 발자국 안에 붙이는 작은 부착물은 통로 keep 을 허용)
local function onlyAisle(K: any, mn: Vector3, mx: Vector3): boolean
	for _, k in K.V.keep do
		if Kit.overlap(mn, mx, k.min, k.max, 0.04) and k.kind ~= "aisle" then
			return false
		end
	end
	return true
end

-- 창가 바: 발받침 레일 + 바 아래 콘센트 박스 (USB)
local function stepBars(K: any, V: any, B: any, ctx: any)
	for _, t in V.tables do
		if t.kind == "bar" and (t.max.X - t.min.X) >= (t.max.Z - t.min.Z) and (t.max.X - t.min.X) > 3 then
			local cz = (t.min.Z + t.max.Z) / 2
			local side = 1
			for _, st in V.stools do
				if st.seat.c.X >= t.min.X - 0.5 and st.seat.c.X <= t.max.X + 0.5 and math.abs(st.seat.c.Z - cz) < 3 then
					side = if st.seat.c.Z < cz then -1 else 1
				end
			end
			local zf = if side < 0 then t.min.Z else t.max.Z
			local n = V3(0, 0, side)
			-- 발받침 레일
			local zr = zf + side * 0.18
			-- 문 · 좌석 keep 을 피한 가장 긴 구간
			local bestA, bestB, curA = 0, 0, nil
			local xs = t.min.X + 0.35
			while xs <= t.max.X - 0.35 + 1e-6 do
				local ok = onlyAisle(K, V3(xs - 0.15, 0.0, zr - 0.1), V3(xs + 0.15, 0.86, zr + 0.1))
				if ok then
					curA = curA or xs
					if xs - curA > bestB - bestA then
						bestA, bestB = curA, xs
					end
				else
					curA = nil
				end
				xs += 0.25
			end
			local x0, x1 = bestA, bestB
			if x1 - x0 >= 2.0 then
				K:free(function()
					K:seg("FootRail", V3(x0, 0.78, zr), V3(x1, 0.78, zr), 0.12, Look.chrome)
					local nb = math.max(2, math.floor((x1 - x0) / 3.5) + 1)
					for k = 0, nb - 1 do
						local x = x0 + 0.3 + (x1 - x0 - 0.6) * k / math.max(1, nb - 1)
						K:seg("FootRailPost", V3(x, 0.02, zr), V3(x, 0.78, zr), 0.08, Look.chrome)
						K:disc("FootRailFoot", 0.24, 0.03, CF(x, 0.015, zr), Look.chrome)
					end
				end)
			end
			-- 콘센트 (2.6 간격)
			local y = t.y - 0.34
			local nb = math.max(1, math.floor((t.max.X - t.min.X) / 2.6))
			for k = 1, nb do
				local x = t.min.X + (t.max.X - t.min.X) * (k - 0.5) / nb
				local c = V3(x, y, zf - side * 0.1)
				local bmn, bmx = c - V3(0.3, 0.13, 0.1), c + V3(0.3, 0.13, 0.1)
				if onlyAisle(K, bmn, bmx) then
					K.freeDepth += 1
					K:box("OutletBox", V3(0.56, 0.24, 0.16), CF(c), Look.white)
					local dcf = faceCF(c + n * 0.081, n)
					for j = -1, 1 do
						if j == 1 then
							K:plate("OutletUSB", 0.1, 0.05, 0.01, dcf * CF(0.18, 0.03, 0), Look.black)
							K:plate("OutletUSB", 0.1, 0.05, 0.01, dcf * CF(0.18, -0.05, 0), Look.black)
						else
							wdisc(K, "OutletSocket", 0.14, 0.01, dcf * CF(if j == -1 then -0.15 else -0.01, 0, 0), Look.offWhite)
						end
					end
					K.freeDepth -= 1
				end
			end
		end
	end
end

-- 주문하는 곳 표시 (POS 위, 천장에 매닮)
local function orderSign(K: any, V: any, B: any, ctx: any)
	local g, pos = ctx.main, ctx.pos
	if not g or not pos or B.noCounter then
		return
	end
	local n = ctx.n
	for _, dz in { 0.6, 1.2, 1.8 } do
		for k = 0, 6 do
			local off = (if k % 2 == 0 then 1 else -1) * math.floor((k + 1) / 2) * 0.5
			local x = if ctx.alongX then pos.c.X + off else (if n.X > 0 then g.max.X else g.min.X) + n.X * dz
			local z = if ctx.alongX then (if n.Z > 0 then g.max.Z else g.min.Z) + n.Z * dz else pos.c.Z + off
			if Common.ceilFree(K, x, z, 1.0) then
				Common.useCeil(K, x, z)
				local y = V.H - 1.0
				local c = facing(V3(x, y, z), n)
				K:free(function()
					for _, sx in { -1, 1 } do
						K:seg("OrderRod", (c * CF(sx * 0.7, 0.3, 0)).Position, V3(x, V.H, z) + c.XVector * sx * 0.7, 0.04, Look.blackMetal)
					end
					K:box("OrderBox", V3(1.8, 0.6, 0.1), c, lk(B.c2 or BLACK))
					K:text("OrderText", 1.6, 0.46, c * CF(0, 0, 0.051), "ORDER · 주문하는 곳", { fg = B.c1, glow = 1.2, font = F.GothamBold, d = 0.005 })
				end)
				return
			end
		end
	end
end

-- 의자 · 소파 리스킨 (Common.chairs 대신 여기서: 소파 Seat 는 소파 모양 오버레이, 원래 자세 · 윗면 그대로)
local function roundOver(K: any, name: string, r: any, rad: number, look: any)
	if r.size.X >= r.size.Z then
		K:rbox(name, r.size, rad, CF(r.c), look)
	else
		K:rbox(name, V3(r.size.Z, r.size.Y, r.size.X), rad, CF(r.c) * ANG(0, PI / 2, 0), look)
	end
end

local function sofaOverlay(K: any, ch: any, done: { [any]: boolean }, B: any)
	local fab = lk(B.sofa or rgb(176, 156, 136), M.Fabric)
	local dark = lk(dk(fab.c, 0.16), M.Fabric)
	local s = ch.seat
	-- 소파 몸통 부품 (Scan 묶음 반경 밖에 걸친 팔걸이 · 등받이까지)
	local list = table.clone(ch.parts)
	local SOFA = { Backrest = true, Arm = true, Base = true, Plinth = true, SofaBack = true, SofaArm = true, SofaBase = true }
	for _, r in K.V.parts do
		if SOFA[r.name] and not done[r] and r.min.Y < ch.top + 3 then
			local d = (r.c - s.c) * V3(1, 0, 1)
			if d.Magnitude < 4.6 then
				table.insert(list, r)
			end
		end
	end
	K:free(function()
		for _, r in list do
			if not done[r] then
				done[r] = true
				local nm = r.name
				if r == s then
					K:slab("SofaCushion", r.size.X, r.size.Z, r.size.Y, 0.22, CF(r.c), fab)
					K:slab("SofaCushionPiping", r.size.X + 0.02, r.size.Z + 0.02, 0.04, 0.23, CF(r.c.X, r.min.Y + 0.08, r.c.Z), dark)
				elseif nm == "Plinth" then
					K:box("SofaPlinth", r.size, CF(r.c), Look.brass)
				elseif nm == "Base" then
					K:box("SofaBase", r.size, CF(r.c), dark)
				elseif nm == "Backrest" or nm == "ChairBack" then
					roundOver(K, "SofaBack", r, 0.35, fab)
					-- 단추 터프팅 (앞면)
					local d = (s.c - r.c) * V3(1, 0, 1)
					if d.Magnitude > 0.05 and hi(K) then
						local nrm = if math.abs(d.X) > math.abs(d.Z) then V3(math.sign(d.X), 0, 0) else V3(0, 0, math.sign(d.Z))
						local along = nrm:Cross(Vector3.yAxis)
						local half = math.abs(nrm.X) * r.size.X / 2 + math.abs(nrm.Z) * r.size.Z / 2
						local len = math.abs(along.X) * r.size.X + math.abs(along.Z) * r.size.Z
						local nb = math.max(3, math.floor(len / 1.1))
						for row = 0, 1 do
							for k = 1, nb do
								local p = r.c + nrm * (half + 0.01) + along * (-len / 2 + len * (k - 0.5 + row * 0.5) / (nb + 0.5)) + V3(0, (row - 0.2) * 0.8 + 0.4, 0)
								K:ball("SofaButton", 0.1, CF(p), dark)
							end
						end
					end
				elseif nm == "Arm" then
					roundOver(K, "SofaArm", r, 0.3, fab)
				else
					K:box("Sofa" .. nm, r.size, CF(r.c), fab)
				end
				Scan.hide(K.hidden, r.part)
			end
		end
	end)
	K:reserve(V3(s.min.X - 0.3, 0, s.min.Z - 0.3), V3(s.max.X + 0.3, ch.top + 2, s.max.Z + 0.3), "chair")
end

local function stepChairs(K: any, V: any, B: any, S: any)
	local cs = S.myChair
	if not cs then
		return
	end
	local done: { [any]: boolean } = {}
	local n = #V.chairs
	local detail = K.detail
	if n * 30 > K.maxParts * 0.4 then
		detail = if n * 22 > K.maxParts * 0.4 then "low" else "mid"
	end
	for _, ch in V.chairs do
		local s = ch.seat
		if s.part:IsA("Seat") and s.part.Transparency >= 0.99 then
			continue
		end
		local isSofa = s.name == "Seat" or s.name == "SofaSeat" or s.size.X * s.size.Z > 4.5
		if isSofa then
			sofaOverlay(K, ch, done, B)
		else
			local w = math.max(1.1, math.min(2.2, math.min(s.size.X, s.size.Z) + 0.05))
			local backH = 1.8
			if ch.back then
				backH = math.clamp(ch.back.max.Y - ch.top, 1.0, 3.2)
			end
			local o = table.clone(cs)
			o.seatTop, o.w, o.d = ch.top, w, w
			o.backH = o.backH or backH
			o.detail = if detail == "high" then o.detail else detail
			local p = V3(s.c.X, 0, s.c.Z)
			local pcf = CFrame.lookAt(p, p - ch.face)
			K:free(function()
				Props.chair(K, pcf, o)
			end)
			for _, r in ch.parts do
				Scan.hide(K.hidden, r.part)
			end
			K:reserve(V3(s.min.X - 0.3, 0, s.min.Z - 0.3), V3(s.max.X + 0.3, ch.top + backH, s.max.Z + 0.3), "chair")
		end
	end
end

-- 엘리베이터 로비 (윗층 카페 · 1층 로비: CAFE 181 · 15F) --------------------------------------------------
--   우편함 (맵 Mailboxes 같은 자세 스테인리스 리스킨: 호수 문 · 투입구 · 번호) · 층별 안내판 · 엘리베이터 안내판 ·
--   15F 카페 입간판 · 콘솔 테이블 (화병 · 메뉴 카드) · 관리사무소 게시판
local function mailboxSkin(K: any, V: any, r: any)
	if not room(K, 120) then
		return
	end
	local lines = {}
	for _, q in V.byName.MailboxLine or {} do
		table.insert(lines, q)
	end
	-- 앞면 방향: 방 가운데 쪽 (맵의 줄 무늬는 벽 쪽 1 스터드 틈을 보고 있어 손님이 못 봄)
	local lc = r.lcf
	local sz = r.part.Size
	local dd = V3((V.x0 + V.x1) / 2, 0, (V.z0 + V.z1) / 2) - r.c
	local fwd: Vector3 = if math.abs(dd.X) * r.size.Z > math.abs(dd.Z) * r.size.X then V3(math.sign(dd.X), 0, 0) else V3(0, 0, math.sign(dd.Z))
	local _ = lc
	local _2 = sz
	-- 앞면 기준 크기: 폭(앞에서 본 가로) · 깊이
	local depth = math.abs(fwd.X) * r.size.X + math.abs(fwd.Z) * r.size.Z
	local width = math.abs(fwd.Z) * r.size.X + math.abs(fwd.X) * r.size.Z
	local hgt = r.size.Y
	local front = faceCF(V3(r.c.X, r.min.Y, r.c.Z) + fwd * (depth / 2), fwd)
	K:free(function()
		-- 몸통 (앞면 0.05 안쪽, 문짝이 원래 앞면까지)
		K:box("MailBody", V3(width, hgt, depth - 0.05), front * CF(0, hgt / 2, -(depth - 0.05) / 2 - 0.05), lk(rgb(178, 182, 188), M.SmoothPlastic, { r = 0.12 }))
		K:plate("MailTop", width, 0.08, 0.05, front * CF(0, hgt - 0.04, -0.05), Look.chrome)
		K:plate("MailKick", width - 0.04, 0.4, 0.05, front * CF(0, 0.2, -0.05), Look.charcoal)
		local cols = math.clamp(math.floor(width / 0.95), 3, 9)
		local rows = math.clamp(math.floor((hgt - 1.0) / 0.92), 3, 6)
		local cw = (width - 0.2) / cols
		local rh = (hgt - 0.9) / rows
		local floors = { 15, 14, 12, 10, 8, 6, 5, 3, 2 }
		for ry = 1, rows do
			for cx = 1, cols do
				local x = -width / 2 + 0.1 + cw * (cx - 0.5)
				local y = 0.55 + rh * (ry - 0.5)
				local door = front * CF(x, y, -0.05)
				K:plate("MailDoor", cw - 0.06, rh - 0.06, 0.04, door, lk(rgb(214, 216, 220), M.SmoothPlastic, { r = 0.1 }))
				if hi(K) or (cx + ry) % 2 == 0 then
					K:plate("MailSlot", (cw - 0.06) * 0.62, 0.05, 0.045, door * CF(0, rh * 0.28, 0), Look.charcoal)
				end
				local fl = floors[(rows - ry) % #floors + 1]
				K:text("MailNo", (cw - 0.06) * 0.55, 0.16, door * CF(0, -rh * 0.12, 0.045), string.format("%d%02d", fl, cx), { fg = rgb(30, 30, 34), bg = rgb(244, 244, 240), d = 0.004, font = F.GothamBold })
			end
		end
		K:text("MailHeader", math.min(width - 0.4, 3.2), 0.3, front * CF(0, hgt - 0.24, 0.0), "우편함 MAIL BOX · 택배는 관리사무소에 맡겨 주세요", { fg = rgb(40, 40, 44), d = 0.004, font = F.GothamMedium })
	end)
	Scan.hide(K.hidden, r.part)
	for _, q in lines do
		Scan.hide(K.hidden, q.part)
	end
end

local function stepLobby(K: any, V: any, B: any, ctx: any)
	for _, r in V.byName.Mailboxes or {} do
		mailboxSkin(K, V, r)
		-- 우편함 뒤 벽 (1 스터드 틈) 은 안 보이니 벽 부착물 자리에서 뺌
		for _, wn in { "left", "right", "back" } do
			if V.walls[wn] then
				local ua, da = V:wallCoord(wn, r.min)
				local ub, db = V:wallCoord(wn, r.max)
				if math.min(da, db) < 2.5 then
					useWall(K, wn, math.min(ua, ub) - 0.3, math.max(ua, ub) + 0.3, 0, r.max.Y + 0.2)
				end
			end
		end
	end
	-- 맵 매입등(Downlight, 빛 없음) 위에 빛나는 원판 + 불빛 몇 개 (로비가 너무 어둡지 않게)
	local nl = 0
	for _, r in V.byName.Downlight or {} do
		if nl < 3 and #K.lights < (V.maxLights or 8) - 1 then
			local disc
			K:free(function()
				disc = K:disc("DownlightGlow", math.max(r.size.X, r.size.Z) * 0.8, 0.04, CF(r.c.X, r.min.Y - 0.01, r.c.Z), Look.lampWarm)
			end)
			if disc then
				K:light(disc, "PointLight", { Range = 13, Brightness = 0.7, Color = rgb(255, 228, 190) })
				nl += 1
			end
		end
	end
	-- 엘리베이터 벽 (ElevatorHead 가 붙은 벽)
	local heads = V.byName.ElevatorHead or {}
	local ewall = "back"
	if heads[1] then
		local bd = math.huge
		for _, wn in { "back", "left", "right" } do
			if V.walls[wn] then
				local _, d = V:wallCoord(wn, heads[1].c)
				if math.abs(d) < bd then
					ewall, bd = wn, math.abs(d)
				end
			end
		end
	end
	local eu: { number } = {}
	for _, h in heads do
		local u = V:wallCoord(ewall, h.c)
		table.insert(eu, u)
	end
	table.sort(eu)
	-- 엘리베이터 옆 안내판 (정원 · 점검)
	for _, u in eu do
		for _, sx in { -1, 1 } do
			local wn, dcf = wallFind(K, { ewall }, 0.9, 4.6, 5.8, u + sx * 3.0)
			if wn and dcf and room(K, 4) then
				K:plate("ElevPlateBack", 0.8, 1.05, 0.02, dcf, Look.chrome)
				K:text("ElevPlate", 0.72, 0.95, dcf * CF(0, 0, 0.02), "승강기 안전\n정원 15인\n1,000kg\n검사 2026.03", { fg = rgb(30, 40, 60), bg = rgb(236, 240, 246), d = 0.005, font = F.GothamMedium })
				break
			end
		end
	end
	-- 층별 안내판
	local mid = if #eu > 0 then (eu[1] + eu[#eu]) / 2 else 0
	-- (로비 벽 앞 1 스터드 틈에 선 우편함 뒤로 숨지 않게 depth 3)
	local wd, dd = wallFind(K, { ewall, "left", "right" }, 2.4, 3.5, 6.6, { [ewall] = mid + (if mid > 0 then -4.5 else 4.5) }, nil, 3.0)
	if not wd then
		wd, dd = wallFind(K, { "left", "right", "back" }, 2.4, 3.5, 6.6, 0, nil, 3.0)
	end
	if wd and dd and room(K, 8) then
		K:plate("DirFrame", 2.3, 3.0, 0.06, dd, Look.brass)
		K:plate("DirFace", 2.14, 2.84, 0.08, dd, lk(rgb(24, 26, 30), M.Glass, { r = 0.15 }))
		K:text("DirTitle", 1.9, 0.34, dd * CF(0, 1.12, 0.09), "층별 안내  DIRECTORY", { fg = rgb(214, 186, 126), font = F.GothamBold, d = 0.005 })
		K:text("DirList", 1.95, 2.1, dd * CF(0, -0.18, 0.09), "15F   CAFE 181 · 오션뷰 라운지\n14F - 5F   오피스텔\n4F - 2F   게스트하우스 게스후\n1F   로비 · 우편함 · 관리사무소\nB1   주차장 (방문 1시간 무료)", { fg = rgb(236, 236, 232), font = F.GothamMedium, align = "Left", d = 0.005 })
		K:plate("DirRule", 1.9, 0.02, 0.09, dd * CF(0, 0.9, 0), lk(rgb(214, 186, 126)))
	end
	-- 15F 카페 액자 포스터 (메뉴 + 뷰)
	local wp, dp = wallFind(K, { "left", "right", ewall }, 2.3, 3.6, 6.7, 0, nil, 3.0)
	if wp and dp and room(K, 12) then
		K:plate("CafePosterFrame", 2.2, 3.0, 0.06, dp, Look.blackMetal)
		K:plate("CafePosterFace", 2.04, 2.84, 0.07, dp, lk(rgb(246, 242, 234)))
		K:plate("CafePosterSky", 2.04, 1.1, 0.075, dp * CF(0, 0.82, 0), lk(rgb(226, 150, 120)))
		K:plate("CafePosterSea", 2.04, 0.42, 0.078, dp * CF(0, 0.12, 0), lk(rgb(40, 70, 120)))
		K:plate("CafePosterBridge", 2.04, 0.04, 0.082, dp * CF(0, 0.36, 0), lk(rgb(240, 240, 236)))
		for _, tx in { -0.45, 0.45 } do
			K:plate("CafePosterTower", 0.04, 0.5, 0.082, dp * CF(tx, 0.6, 0), lk(rgb(240, 240, 236)))
		end
		K:text("CafePosterTitle", 1.9, 0.3, dp * CF(0, -0.32, 0.085), "15F  CAFE 181", { fg = rgb(30, 28, 26), font = F.GothamBlack, d = 0.004 })
		K:text("CafePosterMenu", 1.8, 0.8, dp * CF(0, -0.95, 0.085), "아메리카노 6,500 · 카페라떼 7,000\n181 시그니처 라떼 8,000\n광안대교 야경 창가석 · 매일 10:00 - 23:00", { fg = rgb(60, 54, 48), font = F.GothamMedium, d = 0.004 })
	end
	-- 바닥: 15F 카페 입간판 · 콘솔 테이블
	-- 엘리베이터 문 앞은 비움: 옆벽 (엘리베이터 벽 쪽 끝) 에 세움
	local sideCands = {}
	for _, wn in { "left", "right" } do
		if V.walls[wn] and wn ~= ewall then
			for _, du in { 2.2, 3.2, 4.2, 5.2 } do
				table.insert(sideCands, { wn, uOf(V, wn, 0, V.z0 + du) })
			end
		end
	end
	for _, cand in sideCands do
		local wn = cand[1]
		if V.walls[wn] then
			local pcf = V:wall(wn, cand[2], 0, 0.9)
			if spotX(K, pcf, V3(1.9, 3.6, 1.0), 0.3, "sign") then
				local cf = pcf * CF(0, 0, 0)
				K:box("StandBase", V3(1.6, 0.12, 0.9), cf * CF(0, 0.06, 0), Look.blackMetal)
				K:seg("StandPole", (cf * CF(0, 0.12, 0)).Position, (cf * CF(0, 1.2, 0)).Position, 0.08, Look.blackMetal)
				K:box("StandBoard", V3(1.6, 2.3, 0.08), cf * CF(0, 2.3, 0) * ANG(-0.06, 0, 0), lk(rgb(30, 28, 26)))
				K:text("StandText", 1.45, 2.1, (cf * CF(0, 2.3, 0.05) * ANG(-0.06, 0, 0)), "CAFE 181\n15F\n▲\n엘리베이터를\n이용해 주세요\n10:00 - 23:00", { fg = rgb(236, 214, 170), font = F.GothamBold, d = 0.005 })
				useWall(K, wn, cand[2] - 1.0, cand[2] + 1.0, 0, 3.8)
				break
			end
		end
	end
	for _, wn in { "left", "right", ewall } do
		local wf, pcf = floorFind(K, { wn }, 2.6, 0.9, 2.7, 0, { pad = 0.6, wallH = 2.8 })
		if wf and pcf and room(K, 16) then
			K:box("ConsoleTop", V3(2.6, 0.1, 0.9), pcf * CF(0, 2.55, 0), Look.walnut)
			K:box("ConsoleApron", V3(2.5, 0.25, 0.8), pcf * CF(0, 2.37, 0), Look.walnut)
			for _, sx in { -1, 1 } do
				K:seg("ConsoleLeg", (pcf * CF(sx * 1.15, 0, 0)).Position, (pcf * CF(sx * 1.15, 2.25, 0)).Position, 0.1, Look.brass)
			end
			K:box("ConsoleShelf", V3(2.3, 0.06, 0.7), pcf * CF(0, 0.5, 0), Look.walnut)
			K:vcyl("ConsoleVase", 0.9, 0.42, pcf * CF(-0.75, 3.05, 0), lk(rgb(240, 238, 232), M.SmoothPlastic))
			for k = 0, 4 do
				K:seg("ConsoleBranch", (pcf * CF(-0.75, 3.4, 0)).Position, (pcf * CF(-0.75 + (k - 2) * 0.22, 4.4 + (k % 2) * 0.3, (k - 2) * 0.05)).Position, 0.04, lk(rgb(110, 90, 60)))
				K:ball("ConsoleBloom", 0.2, pcf * CF(-0.75 + (k - 2) * 0.22, 4.4 + (k % 2) * 0.3, (k - 2) * 0.05), lk(if k % 2 == 0 then rgb(246, 242, 236) else rgb(228, 196, 196)))
			end
			K:box("ConsoleBook", V3(0.7, 0.1, 0.5), pcf * CF(0.55, 2.65, 0), lk(rgb(40, 60, 70)))
			K:box("ConsoleBook", V3(0.62, 0.08, 0.46), pcf * CF(0.55, 2.74, 0) * ANG(0, 0.12, 0), lk(rgb(220, 210, 190)))
			K:box("MenuCardBase", V3(0.5, 0.06, 0.2), pcf * CF(0.1, 2.63, 0.15), Look.brass)
			K:text("MenuCard", 0.46, 0.62, pcf * CF(0.1, 2.97, 0.17) * ANG(-0.15, 0, 0), "15F\nCAFE 181\n오늘의 원두\n에티오피아", { fg = rgb(40, 34, 30), bg = rgb(250, 246, 238), d = 0.02, font = F.GothamMedium })
			break
		end
	end
end

-- 9) 빈 벽 채우기 ------------------------------------------------------------------------------------------
-- 다른 단계가 끝난 뒤 옆벽 · 뒷벽(손님 쪽) 눈높이 띠에 남은 긴 빈 구간을 브랜드 구성으로 채움:
--   갤러리 월 (크기가 다른 액자 줄 + 픽처 라이트) · MD 벽선반 (원두 · 드립백 · 텀블러) · 아치 니치 (오뜨 · 인디) ·
--   브랜드 벽화 (긴 벽) · 윗벽 브랜드 문구. 넓은 매장(파스쿠찌 · 스타벅스 · 오뜨)의 텅 빈 벽을 없앰.
local ART_KINDS: { [string]: { string } } = {
	mega = { "pop", "bridge", "pop" },
	compose = { "pop", "bridge", "pop" },
	twosome = { "botanical", "gallery", "abstract" },
	pascucci = { "coffee", "gallery", "bridge" },
	starbucks = { "coffee", "bridge", "botanical" },
	roastery = { "coffee", "gallery", "abstract" },
	concrete = { "coffee", "abstract", "gallery" },
	haute = { "gallery", "botanical", "abstract" },
	busan = { "busan", "bridge", "gallery" },
	ocean = { "busan", "bridge", "abstract" },
	lounge = { "gallery", "bridge", "abstract" },
	scandi = { "abstract", "botanical", "gallery" },
	terracotta = { "abstract", "botanical", "pastel" },
	green = { "botanical", "abstract", "gallery" },
	bakery = { "bread", "botanical", "gallery" },
	tanghulu = { "fruit", "pastel", "abstract" },
	waffle = { "pastel", "abstract", "fruit" },
	churros = { "pastel", "abstract", "bridge" },
	hotteok = { "bridge", "pastel", "abstract" },
	bingsu = { "pastel", "fruit", "abstract" },
	lobby = { "bridge", "gallery", "busan" },
}

-- 벽 wn 의 y0..y1 띠에서 쓸 수 있는 구간: freeSpans 에서 새로 세운 바닥 소품(K.reserved) · 카운터 뒤를 뺌
local function fillSpans(K: any, V: any, wn: string, y0: number, y1: number, skipCounters: boolean): { { number } }
	local spans = freeSpans(K, wn, y0, y1, 1.2)
	local cuts = {}
	local function cutBox(mn: Vector3, mx: Vector3, depth: number, pad: number)
		if mx.Y < y0 or mn.Y > y1 then
			return
		end
		local umin, umax, dmin = math.huge, -math.huge, math.huge
		for _, x in { mn.X, mx.X } do
			for _, z in { mn.Z, mx.Z } do
				local u, d = V:wallCoord(wn, V3(x, 0, z))
				umin, umax, dmin = math.min(umin, u), math.max(umax, u), math.min(dmin, d)
			end
		end
		if dmin <= depth then
			table.insert(cuts, { umin - pad, umax + pad })
		end
	end
	for _, r in K.reserved or {} do
		cutBox(r.min, r.max, 1.4, 0.3)
	end
	if skipCounters then
		for _, g in V.counters do
			cutBox(V3(g.min.X, 0, g.min.Z), V3(g.max.X, 10, g.max.Z), 4.5, 0.4)
		end
	end
	local out = {}
	for _, s in spans do
		local segs = { { s[1], s[2] } }
		for _, c in cuts do
			local nxt = {}
			for _, g in segs do
				if c[2] <= g[1] or c[1] >= g[2] then
					table.insert(nxt, g)
				else
					if c[1] > g[1] then
						table.insert(nxt, { g[1], c[1] })
					end
					if c[2] < g[2] then
						table.insert(nxt, { c[2], g[2] })
					end
				end
			end
			segs = nxt
		end
		for _, g in segs do
			if g[2] - g[1] > 1.5 then
				table.insert(out, g)
			end
		end
	end
	table.sort(out, function(a, b)
		return (a[2] - a[1]) > (b[2] - b[1])
	end)
	return out
end

-- 픽처 라이트 (액자 위 황동 바 + 아래로 비추는 빛줄)
local function pictureLight(K: any, dcf: CFrame, w: number, h: number)
	local top = dcf * CF(0, h / 2 + 0.32, 0)
	K:box("PicLightMount", V3(0.18, 0.12, 0.06), top * CF(0, 0, 0.03), Look.brass)
	K:bar("PicLightArm", (top * CF(0, 0, 0.05)).Position, (top * CF(0, 0.06, 0.32)).Position, 0.05, 0.05, Look.brass)
	K:cyl("PicLightBar", w * 0.55, 0.13, top * CF(0, 0.06, 0.36), Look.brass)
	K:box("PicLightGlow", V3(w * 0.5, 0.03, 0.06), top * CF(0, 0.0, 0.36), Look.lampWarm)
end

-- 갤러리 월: 구간 a..b 가운데에 크기가 다른 액자 줄 (가운데 높이 yc)
local function galleryWall(K: any, V: any, B: any, wn: string, a: number, b: number, yc: number, idx: number): number
	local kinds = ART_KINDS[B.key] or { "abstract", "gallery", "botanical" }
	local cycles = {
		{ { 1.5, 2.0 }, { 2.7, 2.0 }, { 1.5, 2.0 } },
		{ { 1.8, 1.8 }, { 1.3, 1.7 }, { 2.5, 1.9 } },
		{ { 2.4, 1.8 }, { 1.4, 1.9 } },
	}
	local cyc = cycles[(B.seed + idx) % #cycles + 1]
	local gap = 0.55
	local len = b - a - 0.6
	local row = {}
	local total = -gap
	local k = 0
	while k < 7 do
		local sz = cyc[k % #cyc + 1]
		if total + gap + sz[1] > len then
			break
		end
		table.insert(row, sz)
		total += gap + sz[1]
		k += 1
	end
	if #row == 0 then
		return 0
	end
	local u = (a + b) / 2 - total / 2
	for i, sz in row do
		if not room(K, 40) then
			break
		end
		local cu = u + sz[1] / 2
		-- 액자 위 · 아래 가장자리 맞춤 대신 가운데 맞춤 + 작은 높이 흔들림 (손으로 건 느낌 없이 정돈)
		local dcf = V:wall(wn, cu, yc + (if sz[2] < 1.8 then 0.1 else 0), 0.01)
		artPiece(K, dcf, sz[1], sz[2], kinds[(i + idx + B.seed) % #kinds + 1], B, 40 + idx * 7 + i)
		if sz[1] >= 2.2 and hi(K) then
			pictureLight(K, dcf, sz[1], sz[2])
		end
		u += sz[1] + gap
	end
	useWall(K, wn, (a + b) / 2 - total / 2 - 0.2, (a + b) / 2 + total / 2 + 0.2, yc - 1.2, yc + 1.5)
	return #row
end

-- MD 벽선반: 떠 있는 선반 2단 + 원두 봉투 · 드립백 · 텀블러 · 머그 + 가격표 + 머리판
local function merchWall(K: any, V: any, B: any, wn: string, u: number, w: number)
	if not room(K, 70) then
		return
	end
	local shelfL = if B.key == "roastery" or B.key == "concrete" or B.key == "pascucci" or B.key == "lounge" then Look.walnut elseif B.key == "scandi" then Look.birch else Look.oak
	local cols = { B.c1, rgb(250, 250, 248), rgb(30, 30, 32), B.c3, rgb(150, 170, 150) }
	local bag = lk(rgb(196, 160, 112), M.Cardboard)
	for tier = 0, 1 do
		local y = 4.1 + tier * 1.35
		local at = Props.shelf(K, V:wall(wn, u, y, 0), w, { depth = 0.72, look = shelfL, bracket = Look.blackMetal, thick = 0.12 })
		local inner = w - 0.5
		if tier == 0 then
			local n = math.max(2, math.floor(inner / 0.62))
			for k = 1, n do
				local x = -inner / 2 + inner * (k - 0.5) / n
				local c = at * CF(x, 0, -0.06)
				if k % 3 == 0 then
					K:box("DripBox", V3(0.56, 0.5, 0.36), c * CF(0, 0.25, 0), lk(cols[(k % #cols) + 1]))
					K:text("DripBoxLabel", 0.46, 0.18, c * CF(0, 0.3, 0.185), "DRIP BAG\n10입", { fg = onColor(cols[(k % #cols) + 1]), d = 0.005, font = F.GothamBold })
				else
					K:box("BeanBag", V3(0.44, 0.68, 0.28), c * CF(0, 0.34, 0), bag)
					K:box("BeanBagFold", V3(0.46, 0.09, 0.3), c * CF(0, 0.7, 0), lk(rgb(170, 134, 90), M.Cardboard))
					K:plate("BeanBagLabel", 0.34, 0.28, 0.01, c * CF(0, 0.36, 0.14), lk(cols[(k + 1) % #cols + 1]))
				end
			end
			K:text("MerchPrice", math.min(inner, 2.6), 0.13, at * CF(0, -0.07, 0.37), "원두 200g 16,000 ~ 19,000원 · 드립백 10입 15,000원", { fg = rgb(30, 30, 30), bg = rgb(250, 250, 246), d = 0.005, font = F.GothamMedium })
		else
			local n = math.max(2, math.floor(inner / 0.48))
			for k = 1, n do
				local x = -inner / 2 + inner * (k - 0.5) / n
				local c = at * CF(x, 0, -0.06)
				local col = cols[k % #cols + 1]
				if k % 3 == 0 then
					K:vcyl("Mug", 0.38, 0.36, c * CF(0, 0.19, 0), lk(col))
					K:box("MugHandle", V3(0.06, 0.22, 0.07), c * CF(0.21, 0.19, 0), lk(col))
				else
					K:vcyl("Tumbler", 0.78, 0.3, c * CF(0, 0.39, 0), lk(col, M.Metal, { r = 0.08 }))
					K:vcyl("TumblerLid", 0.13, 0.32, c * CF(0, 0.84, 0), if k % 2 == 0 then Look.black else Look.chrome)
					K:plate("TumblerLogo", 0.16, 0.16, 0.005, c * CF(0, 0.45, 0.15), lk(onColor(col)))
				end
			end
			K:text("MerchPrice", math.min(inner, 2.4), 0.13, at * CF(0, -0.07, 0.37), "텀블러 25,000 ~ 39,000원 · 머그 15,000원", { fg = rgb(30, 30, 30), bg = rgb(250, 250, 246), d = 0.005, font = F.GothamMedium })
		end
	end
	K:text("MerchHeader", math.min(w - 0.2, 3.0), 0.34, V:wall(wn, u, 6.85, 0.02), if B.key == "roastery" or B.key == "concrete" then "BEANS & GOODS" else (B.logo or "CAFE") .. "  MD · 원두 · 텀블러", { fg = B.ink, bg = B.paper, d = 0.03, font = F.GothamBold })
	useWall(K, wn, u - w / 2 - 0.2, u + w / 2 + 0.2, 3.4, 7.1)
end

-- 아치 니치: 페인트 아치 + 작은 선반 (화병 · 책 · 캔들) — 오뜨 · 스칸디 · 테라코타 · 라운지
local function archNiche(K: any, V: any, B: any, wn: string, u: number, w: number, y0: number, y1: number, idx: number)
	if not room(K, 22) then
		return
	end
	local base = if B.key == "haute" then rgb(234, 200, 196) elseif B.key == "terracotta" then rgb(214, 150, 112) elseif B.key == "lounge" then rgb(70, 58, 48) else lt(B.c1, 0.35)
	if idx % 2 == 1 then
		base = dk(base, 0.08)
	end
	local look = lk(base, M.Plaster)
	local r = w / 2
	local rectH = (y1 - y0) - r
	K:plate("ArchPanel", w, rectH, 0.03, V:wall(wn, u, y0 + rectH / 2, 0.01), look)
	wdisc(K, "ArchTop", w, 0.03, V:wall(wn, u, y0 + rectH, 0.01), look)
	-- 니치 선반 + 소품
	local at = Props.shelf(K, V:wall(wn, u, y0 + rectH * 0.55, 0.04), w * 0.7, { depth = 0.5, look = if B.key == "lounge" then Look.brass else Look.oak, bracket = lk(base), thick = 0.08 })
	K:vcyl("NicheVase", 0.62, 0.3, at * CF(-w * 0.16, 0.31, -0.05), lk(rgb(246, 244, 238), M.Plaster))
	for k = 0, 2 do
		K:seg("NicheStem", (at * CF(-w * 0.16 + (k - 1) * 0.05, 0.55, -0.05)).Position, (at * CF(-w * 0.16 + (k - 1) * 0.16, 1.05 + k * 0.08, -0.05)).Position, 0.03, lk(rgb(110, 120, 80)))
		K:ball("NicheBloom", 0.16, at * CF(-w * 0.16 + (k - 1) * 0.16, 1.07 + k * 0.08, -0.05), lk(if k == 1 then rgb(250, 246, 236) else rgb(232, 170, 170)))
	end
	K:box("NicheBook", V3(0.5, 0.08, 0.36), at * CF(w * 0.14, 0.04, -0.06), lk(rgb(226, 214, 196)))
	K:box("NicheBook", V3(0.46, 0.07, 0.34), at * CF(w * 0.15, 0.115, -0.06) * ANG(0, 0.1, 0), lk(rgb(120, 140, 130)))
	K:vcyl("NicheCandle", 0.22, 0.18, at * CF(w * 0.15, 0.26, -0.06), lk(rgb(250, 246, 238)))
	useWall(K, wn, u - w / 2 - 0.15, u + w / 2 + 0.15, y0, y1)
end

-- 브랜드 벽화 (긴 빈 벽): 바탕 판 + 큰 제목 + 부제 + 음료 그림 3 (또는 사이렌 원형 엠블럼)
local MURAL: { [string]: { string } } = {
	mega = { "MEGA SIZE", "24oz 대용량 · 아메리카노 2,000원", "pop" },
	compose = { "COMPOSE YOUR DAY", "BEST QUALITY · BEST PRICE", "pop" },
	pascucci = { "Caffè Pascucci", "dal 1883 · Montecerignone, Italia", "coffee" },
	starbucks = { "STARBUCKS COFFEE", "광안리점 · Since 1971 Seattle", "siren" },
	twosome = { "A TWOSOME PLACE", "Dessert & Coffee · Strawberry Choux Cake", "cake" },
	haute = { "Pâtisserie Haute", "fraisier · mille-feuille · madeleine", "cake" },
	roastery = { "ROASTED HERE", "Ethiopia · Kenya · Colombia · Guatemala", "coffee" },
	lounge = { "Lounge by the Sea", "coffee · tea · wine · 광안대교 view", "bridge" },
	busan = { "SEA YOU IN 051", "Gwangalli Beach · Busan", "bridge" },
	bakery = { "Boulangerie", "매일 아침 7시 첫 빵이 나옵니다", "bread" },
	tanghulu = { "탕후루", "제철 과일 · 바삭한 설탕 코팅", "fruit" },
}
local function brandMural(K: any, V: any, B: any, wn: string, u: number, w: number, y0: number, y1: number)
	if not room(K, 40) then
		return
	end
	local m = MURAL[B.key] or { B.title, B.slogan, "cups" }
	local h = y1 - y0
	local dcf = V:wall(wn, u, y0 + h / 2, 0.01)
	local bg = if B.key == "mega" or B.key == "compose" then B.c1 elseif B.key == "haute" then rgb(244, 222, 218) elseif B.key == "starbucks" then rgb(0, 98, 65) elseif B.key == "bakery" then rgb(236, 220, 196) else (B.c2 or rgb(40, 40, 40))
	local fg = onColor(bg)
	if B.key == "haute" then
		fg = rgb(150, 110, 60)
	end
	K:plate("MuralTrim", w + 0.16, h + 0.16, 0.03, dcf, if B.key == "haute" or B.key == "pascucci" or B.key == "lounge" then Look.goldMetal else Look.blackMetal)
	K:plate("Mural", w, h, 0.02, dcf * CF(0, 0, 0.03), lk(bg, M.SmoothPlastic))
	local z = 0.052
	local font = if B.key == "pascucci" or B.key == "haute" or B.key == "lounge" or B.key == "bakery" then F.Garamond else F.GothamBlack
	if m[3] == "siren" then
		local d = math.min(h * 0.72, w * 0.32)
		local c = dcf * CF(-w * 0.26, 0, z)
		wdisc(K, "SirenRing", d, 0.01, c, lk(rgb(255, 255, 255)))
		wdisc(K, "SirenField", d * 0.86, 0.012, c, lk(rgb(0, 112, 74)))
		wdisc(K, "SirenInner", d * 0.56, 0.014, c, lk(rgb(255, 255, 255)))
		wdisc(K, "SirenFace", d * 0.4, 0.016, c * CF(0, d * 0.02, 0), lk(rgb(0, 112, 74)))
		K:plate("SirenCrown", d * 0.22, d * 0.07, 0.018, c * CF(0, d * 0.22, 0), lk(rgb(255, 255, 255)))
		for sx = -1, 1, 2 do
			K:plate("SirenTail", d * 0.06, d * 0.3, 0.018, c * CF(sx * d * 0.24, -d * 0.02, 0) * ANG(0, 0, sx * 0.35), lk(rgb(0, 112, 74)))
		end
		K:text("MuralTitle", w * 0.5, h * 0.22, dcf * CF(w * 0.18, h * 0.12, z), m[1], { fg = rgb(255, 255, 255), font = F.GothamBold, d = 0.005 })
		K:text("MuralSub", w * 0.5, h * 0.12, dcf * CF(w * 0.18, -h * 0.12, z), m[2], { fg = rgb(212, 233, 226), font = F.Gotham, d = 0.005 })
	else
		K:text("MuralTitle", w * 0.86, h * 0.3, dcf * CF(0, h * 0.24, z), m[1], { fg = fg, font = font, d = 0.005 })
		K:text("MuralSub", w * 0.8, h * 0.11, dcf * CF(0, h * 0.02, z), m[2], { fg = if B.key == "mega" or B.key == "compose" then rgb(30, 30, 30) else lt(fg, 0.15), font = F.GothamMedium, d = 0.005 })
		local kinds = if m[3] == "pop" then { "americano", "latte", "strawberry", "ade" } elseif m[3] == "fruit" then { "strawberry", "ade", "strawberry" } else { "latte", "americano", "latte" }
		local n = #kinds
		for k = 1, n do
			local x = -w * 0.33 + (k - 1) * (w * 0.66 / math.max(1, n - 1))
			if m[3] == "coffee" or m[3] == "bread" or m[3] == "cake" or m[3] == "bridge" then
				-- 선 그림 대신 원형 배지 + 아이콘 글자
				wdisc(K, "MuralBadge", h * 0.28, 0.01, dcf * CF(x, -h * 0.28, z), lk(lt(bg, 0.2)))
				K:text("MuralBadgeText", h * 0.26, h * 0.1, dcf * CF(x, -h * 0.28, z + 0.012), (if m[3] == "coffee" then { "ESPRESSO", "ROAST", "BREW" } elseif m[3] == "bread" then { "PAIN", "CROISSANT", "BRIOCHE" } elseif m[3] == "cake" then { "GÂTEAU", "TARTE", "CHOUX" } else { "COFFEE", "TEA", "WINE" })[k], { fg = fg, font = F.GothamBold, d = 0.003 })
			else
				glyph(K, dcf * CF(x, -h * 0.26, z), h * 0.4, kinds[k])
			end
		end
	end
	useWall(K, wn, u - w / 2 - 0.2, u + w / 2 + 0.2, y0 - 0.1, y1 + 0.1)
end

-- 넓은 매장 가운데 빈 바닥: 원두 · MD 아일랜드 진열대 + 플랜터 박스 (K:spot 으로 통로 · 좌석 · 줄 서는 자리 피함)
local SWEET_KEYS = { tanghulu = true, waffle = true, churros = true, hotteok = true, bingsu = true, claw = true, bakery = true, lobby = true }
local function coffeeBrand(B: any): boolean
	return not SWEET_KEYS[B.key]
end

local function beanIsland(K: any, B: any, pcf: CFrame)
	local w, d, h = 3.4, 1.6, 2.7
	local wood = if B.key == "pascucci" or B.key == "lounge" or B.key == "roastery" or B.key == "starbucks" then Look.walnut else Look.oak
	local topL = if B.key == "pascucci" or B.key == "haute" or B.key == "twosome" then Look.marbleWhite else Look.with(wood, { c = lt((wood :: any).c, 0.1) })
	K:box("IslandKick", V3(w - 0.24, 0.3, d - 0.24), pcf * CF(0, 0.15, 0), Look.black)
	K:box("IslandBody", V3(w, h - 0.42, d), pcf * CF(0, 0.3 + (h - 0.42) / 2, 0), wood)
	K:box("IslandTop", V3(w + 0.12, 0.12, d + 0.12), pcf * CF(0, h - 0.06, 0), topL)
	if not lowD(K) then
		for _, sz in { 1, -1 } do
			for k = 1, 7 do
				K:box("IslandFlute", V3(0.05, h - 0.62, 0.03), pcf * CF(-w / 2 + k * w / 8, 0.3 + (h - 0.42) / 2, sz * (d / 2 + 0.015)), lk(dk((wood :: any).c, 0.25), (wood :: any).m))
			end
		end
	end
	local top = pcf * CF(0, h, 0)
	-- 원두 상자 2 (나무 크레이트 + 원두 + 스쿱)
	for i, sx in { -1, 1 } do
		local c = top * CF(sx * 1.05, 0, -0.25)
		K:box("CrateBase", V3(1.0, 0.06, 0.7), c * CF(0, 0.03, 0), Look.pine)
		for _, e in { { 0, 0.33, 1.0, 0.06 }, { 0, -0.33, 1.0, 0.06 } } do
			K:box("CrateSide", V3(e[3], 0.3, e[4]), c * CF(e[1], 0.18, e[2]), Look.pine)
		end
		for _, ex in { -0.47, 0.47 } do
			K:box("CrateSide", V3(0.06, 0.3, 0.6), c * CF(ex, 0.18, 0), Look.pine)
		end
		K:box("CrateBeans", V3(0.88, 0.2, 0.6), c * CF(0, 0.16, 0), lk(if i == 1 then rgb(74, 46, 30) else rgb(104, 66, 40), M.Pebble))
		if i == 1 then
			K:vcyl("BeanScoop", 0.16, 0.26, c * CF(0.18, 0.3, 0.05) * ANG(0.5, 0, 0), Look.steel)
			K:seg("BeanScoopHandle", (c * CF(0.18, 0.34, 0.15)).Position, (c * CF(0.18, 0.5, 0.42)).Position, 0.06, Look.steel)
		end
		K:text("CrateTag", 0.6, 0.18, top * CF(sx * 1.05, 0.24, 0.12) * ANG(-0.5, 0, 0), if i == 1 then "HOUSE BLEND\n200g 16,000" else "ETHIOPIA G1\n200g 19,000", { fg = rgb(30, 30, 30), bg = rgb(250, 248, 240), d = 0.01, font = F.GothamBold })
	end
	-- 가운데: 원두 봉투 줄 + 선물 세트 + 아크릴 사인
	for k = -1, 1 do
		local c = top * CF(k * 0.32, 0, 0.35)
		K:box("BeanBag", V3(0.28, 0.48, 0.2), c * CF(0, 0.24, 0), lk(rgb(196, 160, 112), M.Cardboard))
		K:plate("BeanBagLabel", 0.22, 0.2, 0.01, c * CF(0, 0.26, 0.1), lk(if k == 0 then B.c1 else rgb(250, 250, 246)))
	end
	K:box("GiftSet", V3(0.8, 0.32, 0.5), top * CF(0, 0.16, -0.35), lk(B.c2 or rgb(40, 40, 40)))
	K:plate("GiftRibbon", 0.07, 0.33, 0.01, top * CF(0, 0.16, -0.1), lk(B.c3 or rgb(200, 160, 90)))
	K:box("SignFoot", V3(0.9, 0.05, 0.2), top * CF(0, 0.025, 0.72), Look.acrylicWhite)
	K:text("IslandSign", 1.0, 0.42, top * CF(0, 0.3, 0.73) * ANG(-0.12, 0, 0), "이달의 원두\n에티오피아 예가체프 · 자스민 · 레몬", { fg = rgb(30, 30, 30), bg = rgb(252, 252, 250), d = 0.02, font = F.GothamMedium })
end

local function planterBox(K: any, pcf: CFrame, len: number, B: any)
	local body = if B.key == "roastery" or B.key == "concrete" then Look.of(80, 80, 82, Enum.Material.Concrete) else Look.walnut
	K:box("PlanterBox", V3(len, 1.3, 0.9), pcf * CF(0, 0.65, 0), body)
	K:box("PlanterBoxLip", V3(len + 0.08, 0.08, 0.98), pcf * CF(0, 1.32, 0), Look.blackMetal)
	K:box("PlanterBoxSoil", V3(len - 0.12, 0.05, 0.78), pcf * CF(0, 1.3, 0), Look.soil)
	local n = math.floor(len / 0.32)
	for k = 1, n do
		local x = -len / 2 + (k - 0.5) * len / n
		local hgt = 1.4 + rnd(B.seed, k) * 1.2
		local lean = (rnd(B.seed, k + 30) - 0.5) * 0.35
		K:wedge("PlanterLeaf", V3(0.05, hgt, 0.22), pcf * CF(x, 1.3 + hgt / 2, (rnd(B.seed, k + 60) - 0.5) * 0.4) * ANG(lean, rnd(B.seed, k + 90) * 3, 0), lk(if k % 3 == 0 then rgb(96, 128, 64) else rgb(46, 92, 54), M.Grass))
	end
end

local function floorIslands(K: any, V: any, B: any, ctx: any)
	if V.W * V.D < 650 or B.key == "lobby" or B.key == "starbucks" then
		return
	end
	local placed = {}
	local function farFromCounters(x: number, z: number): boolean
		for _, g in V.counters do
			if x > g.min.X - 3.5 and x < g.max.X + 3.5 and z > g.min.Z - 3.5 and z < g.max.Z + 5.0 then
				return false
			end
		end
		return true
	end
	local cands = {}
	local x = V.x0 + 5
	while x <= V.x1 - 5 do
		local z = V.z0 + 5
		while z <= V.z1 - 5.5 do
			table.insert(cands, V3(x, 0, z))
			z += 1.0
		end
		x += 1.0
	end
	table.sort(cands, function(a, b)
		return (a - V3(ctx.cx, 0, ctx.cz)).Magnitude < (b - V3(ctx.cx, 0, ctx.cz)).Magnitude
	end)
	local want = if V.W * V.D > 1400 then 3 else 2
	for _, p in cands do
		if #placed >= want or not room(K, 70) then
			break
		end
		breathe(K)
		local ok = farFromCounters(p.X, p.Z)
		for _, q in placed do
			if (q - p).Magnitude < 11 then
				ok = false
			end
		end
		if ok then
			local kind = if #placed % 2 == 0 and coffeeBrand(B) then "island" else "planter"
			local pcf = facing(p, V3(0, 0, 1))
			local size = if kind == "island" then V3(3.6, 3.4, 1.8) else V3(3.6, 3.0, 1.0)
			if spotX(K, pcf, size, 1.4, kind) then
				if kind == "island" then
					beanIsland(K, B, pcf)
				else
					planterBox(K, pcf, 3.4, B)
				end
				table.insert(placed, p)
				table.insert(ctx.placed, kind .. ctx.where(pcf))
			end
		end
	end
end

-- X배너 (입구 쪽 옆벽 앞): 엑스자 받침 + 세로 현수막 (로고 · 음료/디저트 그림 · 신메뉴 · 가격)
local function xBanner(K: any, pcf: CFrame, B: any)
	if not room(K, 16) then
		return
	end
	local h = 5.0
	for _, sx in { -1, 1 } do
		K:seg("XBannerLeg", (pcf * CF(sx * 0.55, 0.02, 0.35)).Position, (pcf * CF(-sx * 0.55, 0.02, -0.35)).Position, 0.06, Look.alu)
	end
	K:box("XBannerHub", V3(0.14, 0.1, 0.14), pcf * CF(0, 0.06, 0), Look.darkAlu)
	K:seg("XBannerPole", (pcf * CF(0, 0.1, -0.05)).Position, (pcf * CF(0, h + 0.15, -0.05)).Position, 0.05, Look.alu)
	for _, sx in { -1, 1 } do
		K:seg("XBannerArm", (pcf * CF(0, 0.5, -0.05)).Position, (pcf * CF(sx * 0.82, 0.32, -0.03)).Position, 0.035, Look.alu)
		K:seg("XBannerArm", (pcf * CF(0, h - 0.4, -0.05)).Position, (pcf * CF(sx * 0.82, h + 0.12, -0.03)).Position, 0.035, Look.alu)
	end
	local face = pcf * CF(0, 0.3 + (h - 0.2) / 2, 0)
	K:box("XBanner", V3(1.7, h - 0.2, 0.02), face, lk(B.paper or rgb(255, 255, 255)))
	K:plate("XBannerTop", 1.7, 1.0, 0.012, face * CF(0, (h - 0.2) / 2 - 0.5, 0.01), lk(B.c1))
	K:text("XBannerLogo", 1.5, 0.5, face * CF(0, (h - 0.2) / 2 - 0.5, 0.025), B.logo or B.title, { fg = onColor(B.c1), font = F.FredokaOne, d = 0.003 })
	local kinds = { tanghulu = "strawberry", waffle = "strawberry", churros = "choco", hotteok = "latte", bingsu = "strawberry" }
	glyph(K, face * CF(0, 0.25, 0.022), 1.4, kinds[B.key] or "latte")
	K:text("XBannerNew", 1.0, 0.32, face * CF(0, -0.75, 0.022), B.promo[1], { fg = rgb(255, 255, 255), bg = rgb(230, 60, 80), font = F.GothamBlack, d = 0.003 })
	K:text("XBannerName", 1.55, 0.42, face * CF(0, -1.2, 0.022), B.promo[2], { fg = B.ink, font = F.GothamBlack, d = 0.003 })
	K:text("XBannerPrice", 1.3, 0.36, face * CF(0, -1.65, 0.022), B.promo[3] .. "원", { fg = dk(B.c1, 0.3), font = F.GothamBlack, d = 0.003 })
end

-- 큰 아이스크림 콘 조형물 (젤라또 가게 입구 옆)
local function coneStatue(K: any, pcf: CFrame, B: any)
	if not room(K, 14) then
		return
	end
	K:disc("ConeBase", 1.3, 0.16, pcf * CF(0, 0.08, 0), Look.white)
	K:vcyl("ConePost", 0.5, 0.25, pcf * CF(0, 0.4, 0), Look.chrome)
	-- 콘: 아래로 갈수록 좁은 원통 6단 + 와플 무늬 띠
	for k = 0, 5 do
		local dia = 0.22 + k * 0.17
		K:vcyl("ConeWafer", 0.36, dia, pcf * CF(0, 0.82 + k * 0.34, 0), lk(rgb(214, 160, 90), M.Sand))
	end
	K:ring("ConeBand", pcf * CF(0, 2.0, 0) * ANG(PI / 2, 0, 0), 0.5, 0.06, 10, lk(rgb(176, 120, 60)))
	local cols = { lt(B.c3 or rgb(250, 180, 190), 0.2), rgb(250, 246, 236), rgb(120, 76, 50) }
	K:ball("ConeScoop", 1.25, pcf * CF(0, 3.1, 0), lk(cols[1]))
	K:ball("ConeScoop", 1.05, pcf * CF(0.05, 3.85, 0.05), lk(cols[2]))
	K:ball("ConeCherry", 0.3, pcf * CF(0.1, 4.45, 0.1), lk(rgb(220, 30, 50)))
	K:seg("ConeStem", (pcf * CF(0.1, 4.55, 0.1)).Position, (pcf * CF(0.2, 4.8, 0.05)).Position, 0.04, lk(rgb(60, 100, 40)))
end

local function dessertFloor(K: any, V: any, B: any, ctx: any)
	if not (B.key == "waffle" or B.key == "churros" or B.key == "tanghulu" or B.key == "bingsu" or B.key == "hotteok") then
		return
	end
	-- 입구 안쪽 양옆 (창가 keep 띠 z1 - 1.8 보다 안쪽), 입구 쪽(+Z)으로 30도 돌려 들어오는 손님이 보게
	local function find(size: Vector3, first: number): CFrame?
		for _, sx in { first, -first } do
			for _, dz in { 2.9, 3.6, 4.4, 5.2 } do
				for _, dx in { 1.3, 2.0, 2.8, 3.6 } do
					local x = if sx > 0 then V.x1 - dx else V.x0 + dx
					local p = V3(x, 0, V.z1 - dz)
					local dir = (V3(0, 0, 1) + V3(-sx * 0.6, 0, 0)).Unit
					local pcf = CFrame.lookAt(p, p - dir)
					if spotX(K, pcf, size, 0.15, "sign") then
						return pcf
					end
				end
			end
		end
		return nil
	end
	local first = if (B.seed % 2) == 0 then 1 else -1
	local pb = find(V3(1.9, 5.3, 1.3), first)
	if pb then
		xBanner(K, pb, B)
		table.insert(ctx.placed, "xbanner" .. ctx.where(pb))
	end
	if B.key ~= "hotteok" then
		local pc = find(V3(1.4, 4.9, 1.4), -first)
		if pc then
			coneStatue(K, pc, B)
			table.insert(ctx.placed, "cone" .. ctx.where(pc))
		end
	end
end

-- 스타벅스: 계산대 뒤 맵 GreenTileWall (거의 검은 초록) -> 같은 자리 광택 그린 서브웨이 타일 + 줄눈 + 황동 몰딩
local function starbucksTiles(K: any, V: any)
	for _, r in V.byName.GreenTileWall or {} do
		local u0, d0 = V:wallCoord("back", r.min)
		local u1, d1 = V:wallCoord("back", r.max)
		if math.max(d0, d1) < 1.0 and room(K, 70) then
			local a, b = math.min(u0, u1), math.max(u0, u1)
			local face = math.max(d0, d1)
			local y0, y1 = r.min.Y, r.max.Y
			K:free(function()
				local c = V:wall("back", (a + b) / 2, (y0 + y1) / 2, face - 0.02)
				K:plate("GreenTile", b - a, y1 - y0, 0.03, c, lk(rgb(30, 96, 76), M.SmoothPlastic, { r = 0.12 }))
				local rows = math.floor((y1 - y0) / 0.55)
				for i = 1, rows do
					K:plate("GreenTileGrout", b - a, 0.03, 0.035, c * CF(0, -(y1 - y0) / 2 + i * 0.55, 0), lk(rgb(150, 170, 160)))
				end
				local cols = math.floor((b - a) / 1.1)
				for i = 1, cols do
					K:plate("GreenTileGrout", 0.03, y1 - y0, 0.035, c * CF(-(b - a) / 2 + i * 1.1, 0, 0), lk(rgb(150, 170, 160)))
				end
				K:plate("GreenTileCap", b - a + 0.1, 0.12, 0.08, c * CF(0, (y1 - y0) / 2 - 0.06, 0), Look.brass)
			end)
			Scan.hide(K.hidden, r.part)
		end
	end
end

local function stepFill(K: any, V: any, B: any, ctx: any)
	if B.key == "claw" then
		return
	end
	if B.key == "starbucks" then
		starbucksTiles(K, V)
	end
	local maxN = if V.W * V.D > 900 then 9 elseif V.W * V.D > 450 then 6 else 4
	if K.detail == "low" then
		maxN = math.min(maxN, 2)
	end
	local n = 0
	local idx = 0
	local archy = B.key == "haute" or B.key == "scandi" or B.key == "terracotta" or B.key == "lounge"
	local merchOK = coffeeBrand(B) and B.key ~= "mega" and B.key ~= "compose"
	local muralDone = false
	for pass = 1, 2 do
		for _, wn in { "back", "left", "right" } do
			if not V.walls[wn] then
				continue
			end
			local y0, y1 = 3.55, math.min(6.75, V.H - 1.2)
			for _, s in fillSpans(K, V, wn, y0, y1, wn == "back") do
				if n >= maxN or not room(K, 60) then
					break
				end
				local a, b = s[1], s[2]
				local len = b - a
				idx += 1
				-- 긴 벽 (8+): 브랜드 벽화 1 회, 그 외 갤러리
				if not muralDone and len >= 8.5 and MURAL[B.key] and V.H >= 9.4 then
					local top = math.min(V.H - 1.0, 8.4)
					local mh = math.min(3.6, top - 3.7)
					local placedM = false
					if mh >= 2.6 then
						-- 벽화 높이 띠 전체가 비어 있는 부분 (메뉴판 · 간판 아래로 들어가지 않게)
						for _, t in fillSpans(K, V, wn, top - mh - 0.15, top + 0.15, wn == "back") do
							local lo, hi2 = math.max(a, t[1]), math.min(b, t[2])
							if hi2 - lo >= 7.6 then
								brandMural(K, V, B, wn, (lo + hi2) / 2, math.min(hi2 - lo - 0.9, 9.5), top - mh, top)
								placedM = true
								break
							end
						end
					end
					if placedM then
						muralDone = true
						n += 1
						continue
					end
				end
				if len >= 6.2 then
					if galleryWall(K, V, B, wn, a, b, 5.05, idx) > 0 then
						n += 1
					end
				elseif len >= 4.0 then
					local w = math.min(3.6, len - 0.6)
					if merchOK and (idx + B.seed) % 2 == 0 then
						merchWall(K, V, B, wn, (a + b) / 2, w)
					elseif archy and V.H >= 9 then
						local aw = math.min(2.4, len - 0.8)
						archNiche(K, V, B, wn, (a + b) / 2, aw, 0.45, math.min(V.H - 1.4, 7.4), idx)
					else
						galleryWall(K, V, B, wn, a, b, 5.05, idx)
					end
					n += 1
				elseif len >= 2.6 and pass == 2 then
					local kinds = ART_KINDS[B.key] or { "abstract" }
					local aw = math.min(2.2, len - 0.5)
					local ah = if aw > 1.8 then 1.7 else 2.0
					artPiece(K, V:wall(wn, (a + b) / 2, 5.05, 0.01), aw, ah, kinds[(idx + B.seed) % #kinds + 1], B, 80 + idx)
					useWall(K, wn, (a + b) / 2 - aw / 2 - 0.2, (a + b) / 2 + aw / 2 + 0.2, 3.9, 6.2)
					n += 1
				end
			end
		end
	end
	-- 윗벽 브랜드 문구 (뒷벽 손님 쪽 · 높은 천장)
	if V.H >= 9.6 then
		for _, s in fillSpans(K, V, "back", 7.3, math.min(V.H - 0.6, 9.4), false) do
			local len = s[2] - s[1]
			if len >= 6 and room(K, 4) then
				local w = math.min(len - 1, 9)
				local txt = if B.key == "pascucci" then "Caffè Pascucci · dal 1883" elseif B.key == "haute" then "Pâtisserie & Café Haute" elseif B.key == "twosome" then "A TWOSOME PLACE · DESSERT CAFE" else (B.slogan or B.title)
				K:text("BackScript", w, 0.8, V:wall("back", (s[1] + s[2]) / 2, 8.3, 0.03), txt, { fg = if B.key == "mega" or B.key == "compose" then B.c1 elseif B.type == "dessert" then dk(B.c1, 0.15) elseif B.key == "haute" then rgb(150, 108, 56) else B.ink, font = if B.key == "pascucci" or B.key == "haute" or B.key == "lounge" then F.Garamond else F.GothamBlack, d = 0.03 })
				useWall(K, "back", (s[1] + s[2]) / 2 - w / 2, (s[1] + s[2]) / 2 + w / 2, 7.8, 8.8)
				break
			end
		end
	end
	-- 메가 · 컴포즈: 옆벽 윗단 브랜드 컬러 띠 (매장 전체가 흰 벽 + 회색으로 죽어 보여서). 벽면 마감이라 깊이 0.03
	if (B.key == "mega" or B.key == "compose") and V.H >= 9 then
		local by0, by1 = 7.25, math.min(V.H - 0.9, 8.55)
		for _, wn in { "left", "right" } do
			if V.walls[wn] and room(K, 12) then
				-- 칠한 띠라서 액자 · 포스터 뒤로 지나가도 됨: 구조 (창 · 문 · keep) 만 피함
				for _, sp in V:spans(wn, by0, by1, 0.4) do
					local len = sp[2] - sp[1] - 0.3
					if len >= 3.0 then
						local mid = (sp[1] + sp[2]) / 2
						local bh = by1 - by0
						local dcf = V:wall(wn, mid, by0 + bh / 2, 0.01)
						K:plate("BrandBand", len, bh, 0.014, dcf, lk(B.c1))
						K:plate("BrandBandLine", len, 0.06, 0.025, dcf * CF(0, bh / 2 - 0.03, 0), Look.black)
						K:plate("BrandBandLine", len, 0.06, 0.025, dcf * CF(0, -bh / 2 + 0.03, 0), Look.black)
						local tw = math.min(len - 0.4, 9.0)
						K:text("BrandBandText", tw, bh * 0.56, dcf * CF(0, 0, 0.03), if B.key == "mega" then "MEGA MGC COFFEE · 메가MGC커피" else "COMPOSE COFFEE · 컴포즈커피", { fg = rgb(24, 24, 24), font = F.GothamBlack, d = 0.004 })
						useWall(K, wn, sp[1], sp[2], by0, by1)
					end
				end
			end
		end
	end
	ctx.fillN = n
	floorIslands(K, V, B, ctx)
	dessertFloor(K, V, B, ctx)
end

-- 짓기 ------------------------------------------------------------------------------------------------------
function T.build(K: any, V: any, S: any)
	local B = (S and S.brand) or brandOf(V)
	B.type = V.type
	local ctx = context(K, V, B)
	local okC, errC = pcall(stepChairs, K, V, B, S or {})
	if not okC then
		K:note("cafe.chairs error: " .. tostring(errC))
	end
	local steps: { any } = {
		{ "shell", stepShell },
		{ "floor", stepFloor },
		{ "counters", stepCounters },
		{ "bars", stepBars },
		{ "order", orderSign },
		{ "machines", stepMachines },
		{ "rebuild", stepRebuild },
	}
	if B.key == "lobby" then
		steps = { { "shell", stepShell }, { "floor", stepFloor }, { "rebuild", stepRebuild }, { "lobby", stepLobby }, { "sides", stepSideWalls }, { "plants", stepPlants }, { "fill", stepFill }, { "ceiling", stepCeiling } }
	elseif B.key == "claw" then
		table.insert(steps, { "claw", stepClaw })
		table.insert(steps, { "ceiling", stepCeiling })
		table.insert(steps, { "clawWalls", stepClawWalls })
	else
		table.insert(steps, { "back", stepBackWall })
		table.insert(steps, { "special", stepSpecial })
		table.insert(steps, { "backbar", backBarWall })
		table.insert(steps, { "sides", stepSideWalls })
		table.insert(steps, { "plants", stepPlants })
		table.insert(steps, { "fill", stepFill })
		table.insert(steps, { "ceiling", stepCeiling })
	end
	local function where(cf: CFrame?): string
		if not cf then
			return "-"
		end
		local p = cf.Position
		return string.format("(%.1f,%.1f)", p.X, p.Z)
	end
	ctx.where = where
	for _, st in steps do
		local fn = st[2]
		local ok, err = pcall(function()
			if st[1] == "rebuild" or st[1] == "claw" then
				K:free(function()
					fn(K, V, B, ctx)
				end)
			else
				fn(K, V, B, ctx)
			end
		end)
		if not ok then
			K:note("cafe." .. st[1] .. " error: " .. tostring(err))
		end
	end
	K:note(string.format("cafe[%s] menus=%d boards=%d backbar=%d fill=%d placed=%s", B.key, ctx.menuPlaced or 0, #ctx.boards, ctx.backBar or 0, ctx.fillN or 0, table.concat(ctx.placed or {}, " ")))
end

return T
