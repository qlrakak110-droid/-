--!strict
-- GwangalliBuildingInterior/T_seafood: 유형 (rawfish seafood) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (메뉴판 · 진열 · 주방 · 간판 · 소품 · 상호작용)
--
-- 부산 광안리 · 민락동 횟집 · 초장집 · 수산 · 조개찜 · 대게 · 오징어 · 스시 바 기준:
--   * 수족관 (TankWater = 게임플레이: 물 상자는 그대로, 둘레만 덧씌움) — 스테인리스 받침장 · 모서리 앵글 ·
--     테두리 · 여과기 · 기포기 · UV 살균기 · PVC 배관 · 수조 LED · 가격표 · 뜰채, 안에는 헤엄치는 활어
--     (광어 · 도다리 · 우럭 · 참돔 · 농어) / 조개 바구니 / 대게 · 킹크랩 / 산오징어 + 기포 애니메이션
--   * 활어 손질 카운터 뒷벽: 타일 · 칼 자석 걸이 · 자외선 칼 소독기 · 스텐 선반 (회 접시 · 초장 · 간장) ·
--     카운터 위 저울 · 회 플레이팅 · 초장/와사비 · 포장 용기 · 랩
--   * 벽: 라이트 박스 메뉴판 (광어 · 우럭 · 도다리 · 모듬회 小中大), 오늘의 시가 칠판, 원산지 표시판,
--     낚시 인증 사진 · 어탁 액자, 제철 수산물 달력, 위생등급 · 와이파이 · 카드/동백전 안내, 그물 · 부표 ·
--     풍어기, 벽걸이 TV (사직 야구 · 낚시 채널 · 날씨 · 드론쇼 뉴스), 벽걸이 선풍기
--   * 바닥: 주류 냉장고, 스티로폼 활어 상자 · 고무 다라이, 개업 축하 화분, (조개찜) 조개 진열대,
--     (대게) 스팀 찜기, (오징어) 오징어 건조 줄
--   * 상호작용 (클라이언트 전용): 수족관 조명 · 기포기 스위치, TV 채널, 주류 냉장고 문, 선풍기 줄 스위치

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))

local T = {}
T.types = { "rawfish", "seafood" }

local L = Look
local M = Enum.Material
local F = Enum.Font
local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local rgb = Color3.fromRGB
local WHITE = rgb(255, 255, 255)
local WALL_OFF = 0.05 -- 벽 부착물은 타일 · 줄눈 · 색띠(최대 0.045) 앞에
-- 활어 손질대 상판: 헤어라인 스테인리스 (횟집 · 수산 · 조개찜 · 대게 공통)
local STEEL_TOP = Look.of(204, 208, 212, Enum.Material.Metal)

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

local function pickOf(list: { any }, seed: number, i: number): any
	return list[(math.floor(rnd(seed, i) * #list) % #list) + 1]
end

local function has(s: string, sub: string): boolean
	return string.find(s, sub, 1, true) ~= nil
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
	return #K.parts + n < K.maxParts * 0.95
end

-- 표시면(dcf) 앞을 보는 원판: dcf 의 +Z 쪽 z..z+t
local function wdisc(K: any, name: string, dia: number, t: number, dcf: CFrame, z: number, look: any): BasePart
	return K:make("Part", name, V3(t, dia, dia), dcf * CF(0, 0, z + t / 2) * ANG(0, PI / 2, 0), look, Enum.PartType.Cylinder)
end

-- 글자판: 배경색은 판 파트 색으로 (조명 아래에서도 판이 보임), 글자만 라벨
local function ktext(K: any, name: string, w: number, h: number, dcf: CFrame, text: string, o: any?): (BasePart, TextLabel)
	local op: any = table.clone(o or {})
	if op.bg and not op.look and not op.lit then
		op.look = { c = op.bg, m = M.SmoothPlastic, free = op.free }
		op.bg = nil
	end
	return K:text(name, w, h, dcf, text, op)
end

-- 스스로 빛나는 면 (라이트 박스 · 화면): 라벨 배경이 조명 영향 없이 그 색으로 보임
local function litFace(K: any, name: string, w: number, h: number, dcf: CFrame, bg: Color3, text: string?, fg: Color3?, glow: number?, d: number?): (BasePart, TextLabel)
	return K:text(name, w, h, dcf, text or "", { bg = bg, fg = fg or WHITE, glow = glow or 1, d = d or 0.03, font = F.GothamBold })
end

local function charCount(s: string): number
	local n = 0
	for _ in utf8.codes(s) do
		n += 1
	end
	return n
end

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

-- 글자 폭 (em): 한글 1.0, 영숫자 0.6, 공백 0.32
local function textEm(s: string): number
	local w = 0
	for _, cp in utf8.codes(s) do
		if cp >= 0x1100 then
			w += 1.0
		elseif cp == 32 then
			w += 0.32
		else
			w += 0.6
		end
	end
	return w
end

-- 같은 높이 · 같은 줄 수의 여러 줄 라벨 묶음 (메뉴 표 열): 글자 크기 하나 + 줄 간격 고정이라 행이 맞음.
-- cols = { { x, w, text, fg, font, align } } (x = dcf 기준 가운데), n = 줄 수, dcf = 판 앞면 위 가운데 (y 중심)
local function textColumns(K: any, name: string, dcf: CFrame, h: number, n: number, cols: { any }, glow: number?)
	local made = {}
	local size = math.huge
	for _, cd in cols do
		local _, lbl = K:text(name, cd.w, h, dcf * CF(cd.x, 0, 0), cd.text, { fg = cd.fg, glow = glow, font = cd.font, align = cd.align, d = 0.005 })
		local g: any = lbl.Parent
		local ppx = if g then g.PixelsPerStud else 40
		local lh = h * ppx / math.max(1, n)
		local fit = lh * 0.74
		local maxEm = 0
		for line in string.gmatch(cd.text .. "\n", "(.-)\n") do
			maxEm = math.max(maxEm, textEm(line))
		end
		if maxEm > 0 then
			fit = math.min(fit, cd.w * ppx * 0.94 / maxEm)
		end
		size = math.min(size, fit / ppx)
		table.insert(made, { lbl = lbl, ppx = ppx, lh = lh })
	end
	for _, m in made do
		local ts = math.clamp(math.floor(size * m.ppx), 6, 100)
		m.lbl.TextScaled = false
		m.lbl.TextSize = ts
		m.lbl.LineHeight = math.clamp(m.lh / ts, 1, 3)
	end
end

-- 벽 자리 관리 (Common.wallSpot 과 같은 K.wallUsed) ---------------------------------------------------------
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
	-- 옆벽: 앞 유리 2 스터드 안쪽은 창 띠 (3.4 위) 라 비움
	local clipLo, clipHi = -math.huge, math.huge
	if y1 > 3.4 and (wn == "left" or wn == "right") then
		if wn == "right" then
			clipHi = V.z1 - 2.1
		else
			clipLo = -(V.z1 - 2.1)
		end
	end
	for _, s in V:spans(wn, y0, y1, depth or 0.8) do
		local segs = { { math.max(s[1], clipLo), math.min(s[2], clipHi) } }
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
		-- 맵 간판 (Sign_*) 은 Scan 이 쉘로 분류해 빈 구간에서 빠지지 않으므로 여기서 뺌
		for _, r in V.parts do
			if string.sub(r.name, 1, 5) == "Sign_" and r.max.Y > y0 and r.min.Y < y1 then
				local umin, umax, dmin = math.huge, -math.huge, math.huge
				for _, x in { r.min.X, r.max.X } do
					for _, z in { r.min.Z, r.max.Z } do
						local uu, dd = V:wallCoord(wn, V3(x, 0, z))
						umin = math.min(umin, uu)
						umax = math.max(umax, uu)
						dmin = math.min(dmin, dd)
					end
				end
				if dmin <= 1.0 then
					local nxt = {}
					for _, g in segs do
						if umax + 0.3 <= g[1] or umin - 0.3 >= g[2] then
							table.insert(nxt, g)
						else
							if umin - 0.3 > g[1] then
								table.insert(nxt, { g[1], umin - 0.3 })
							end
							if umax + 0.3 < g[2] then
								table.insert(nxt, { umax + 0.3, g[2] })
							end
						end
					end
					segs = nxt
				end
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

-- walls 순서대로 폭 minW..maxW 가 들어가는 빈 구간 중 near(u) 에 가까운 자리. 반환 wn, u, w (claim 함)
local function findWall(K: any, walls: { string }, minW: number, maxW: number, y0: number, y1: number, near: any?, depth: number?, test: any?): (string?, number?, number?)
	local V = K.V
	for _, wn in walls do
		if not V.walls[wn] then
			continue
		end
		local target = 0
		if typeof(near) == "Vector3" then
			target = (V:wallCoord(wn, near))
		elseif type(near) == "table" and near[wn] then
			target = near[wn]
		elseif type(near) == "number" then
			target = near
		end
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

-- 벽면 빈 구간 (맵 파트만 피함, keep 무시): 타일 · 페인트 같은 납작한 벽 마감용
local function finishSpans(V: any, wn: string, y0: number, y1: number, depth: number?): { { number } }
	local w = V.walls[wn]
	if not w then
		return {}
	end
	local dep = depth or 0.3
	local cuts = {}
	for _, r in V.parts do
		if (not r.shell or r.door) and not r.point and r.max.Y > y0 and r.min.Y < y1 then
			local umin, umax, dmin = math.huge, -math.huge, math.huge
			for _, x in { r.min.X, r.max.X } do
				for _, z in { r.min.Z, r.max.Z } do
					local u, d = V:wallCoord(wn, V3(x, 0, z))
					umin = math.min(umin, u)
					umax = math.max(umax, u)
					dmin = math.min(dmin, d)
				end
			end
			if dmin <= dep then
				table.insert(cuts, { umin - 0.1, umax + 0.1 })
			end
		end
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local out = {}
	local cur = w.a + 0.05
	for _, cc in cuts do
		if cc[1] > cur + 0.3 then
			table.insert(out, { cur, math.min(cc[1], w.b - 0.05) })
		end
		cur = math.max(cur, cc[2])
	end
	if cur < w.b - 0.35 then
		table.insert(out, { cur, w.b - 0.05 })
	end
	return out
end

-- 작은 소품: keep 에 걸리면 아예 안 만듦 (blocked 수를 늘리지 않게)
local function clearAt(K: any, cf: CFrame, size: Vector3): boolean
	local mn, mx = laabb(cf, size)
	return K:hitsKeep(mn, mx) == nil
end

-- 벽에 붙여 세우는 바닥 소품 자리 (K:spot 예약). 반환 pcf (+Z = 방 안쪽), wn, u
local function floorOnWall(K: any, walls: { string }, size: Vector3, near: any?, pad: number?, test: any?, gap: number?): (CFrame?, string?, number?)
	local V = K.V
	for _, wn in walls do
		local w = V.walls[wn]
		if not w then
			continue
		end
		local target = (w.a + w.b) / 2
		if typeof(near) == "Vector3" then
			target = (V:wallCoord(wn, near))
		elseif type(near) == "table" and near[wn] then
			target = near[wn]
		end
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
			local pcf = V:wall(wn, cu, 0, size.Z / 2 + (gap or 0.12))
			local mn, mx = laabb(pcf * CF(0, size.Y / 2, 0), size + V3(0.2, 0, 0.2))
			if mapClear(V, mn, mx) and not usedHit(K, wn, cu - size.X / 2, cu + size.X / 2, 0, size.Y) and (not test or test(pcf, wn, cu)) and K:spot(pcf, size, pad or 0.1, "seafood") then
				claim(K, wn, cu - size.X / 2 - 0.15, cu + size.X / 2 + 0.15, 0, size.Y + 0.2)
				return pcf, wn, cu
			end
		end
	end
	return nil, nil, nil
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

local function at(K: any, what: string, wn: string?, u: number?, p: Vector3?)
	if p then
		K:note(string.format("%s @ %.1f,%.1f,%.1f", what, p.X, p.Y, p.Z))
	else
		K:note(string.format("%s @ %s u=%.1f", what, tostring(wn), u or 0))
	end
end

-- 유형 · 테마 -------------------------------------------------------------------------------------------
local function kindOf(V: any): string
	local n = tostring(V.name or "")
	local m = tostring(V.menu or "")
	if m == "sushi" or has(n, "스시") or has(n, "초밥") or has(string.upper(n), "SUSHI") then
		return "sushi"
	end
	if m == "crab" or has(n, "대게") or has(n, "킹크랩") or has(n, "게장") then
		return "crab"
	end
	if m == "ojingeo" or has(n, "오징어") then
		return "squid"
	end
	if m == "jjim" or has(n, "조개") then
		return "jjim"
	end
	if has(n, "초장") then
		return "chojang"
	end
	if has(n, "수산") then
		return "market"
	end
	if V.type == "seafood" then
		return "jjim"
	end
	return "hoe"
end

local function shortName(V: any, fallback: string): string
	local n = tostring(V.name or "")
	if n == "" or n == "SideShop" or #n > 40 then
		return fallback
	end
	return n
end

-- 메뉴 데이터 (부산 광안리 · 민락 2026 시세)
local MENUS: { [string]: any } = {
	hoe = {
		title = "활어회 메뉴",
		cols = { "소", "중", "대" },
		main = {
			{ "광어", "50,000", "70,000", "90,000" },
			{ "우럭", "55,000", "75,000", "95,000" },
			{ "광어 + 우럭", "60,000", "80,000", "100,000" },
			{ "모듬회 (스끼다시)", "50,000", "70,000", "90,000" },
			{ "도다리 (봄 한정)", "시가" },
			{ "자연산 모듬", "시가" },
		},
		side = {
			{ "물회", "15,000" },
			{ "회덮밥", "13,000" },
			{ "매운탕 (회 주문시)", "8,000" },
			{ "알밥", "9,000" },
			{ "멍게 · 해삼 · 개불", "20,000" },
			{ "산낙지", "25,000" },
		},
		sideTitle = "식사 · 별미",
		drinks = "소주 5,000  ·  맥주 5,000  ·  음료 2,000",
	},
	chojang = {
		title = "초장집 상차림",
		cols = { "가격" },
		main = {
			{ "상차림 (1인)", "5,000" },
			{ "매운탕 끓임", "10,000" },
			{ "지리 (맑은탕)", "12,000" },
			{ "공기밥", "1,000" },
			{ "라면 사리", "2,000" },
			{ "수제비 사리", "2,000" },
		},
		side = {
			{ "회는 1층 수산에서", "직접" },
			{ "손질 · 포장", "무료" },
			{ "초장 · 쌈채소", "무한" },
			{ "단체석 (2층)", "예약" },
		},
		sideTitle = "이용 안내",
		drinks = "소주 5,000  ·  맥주 5,000  ·  음료 2,000",
	},
	market = {
		title = "오늘의 활어 시세 (1kg)",
		cols = { "kg" },
		main = {
			{ "광어", "35,000" },
			{ "우럭", "40,000" },
			{ "도다리", "45,000" },
			{ "참돔", "50,000" },
			{ "농어", "38,000" },
			{ "전복 (10미)", "55,000" },
		},
		side = {
			{ "멍게", "15,000" },
			{ "해삼", "35,000" },
			{ "개불", "30,000" },
			{ "산낙지 (1미)", "8,000" },
			{ "가리비", "18,000" },
		},
		sideTitle = "해산물",
		drinks = "손질비 무료  ·  포장 · 택배 가능",
	},
	jjim = {
		title = "조개찜 · 해물 메뉴",
		cols = { "소", "중", "대" },
		main = {
			{ "모듬 조개찜", "50,000", "65,000", "80,000" },
			{ "가리비찜", "45,000", "60,000", "75,000" },
			{ "해물 조개탕", "40,000", "55,000", "70,000" },
			{ "조개구이 (2인)", "55,000" },
			{ "키조개 버터구이", "25,000" },
			{ "전복 버터구이", "30,000" },
		},
		side = {
			{ "해물 칼국수", "10,000" },
			{ "라면 사리", "2,000" },
			{ "볶음밥", "3,000" },
			{ "공기밥", "1,000" },
			{ "새우튀김", "12,000" },
		},
		sideTitle = "식사 · 추가",
		drinks = "소주 5,000  ·  맥주 5,000  ·  음료 2,000",
	},
	crab = {
		title = "대게 · 킹크랩 시세",
		cols = { "kg 당" },
		main = {
			{ "영덕 대게 (국내산)", "시가" },
			{ "대게 (러시아산)", "89,000" },
			{ "킹크랩 (러시아산)", "135,000" },
			{ "홍게", "45,000" },
			{ "랍스타 (캐나다산)", "95,000" },
			{ "대게 세트 (2인)", "160,000" },
		},
		side = {
			{ "상차림 (1인)", "5,000" },
			{ "게딱지 볶음밥", "3,000" },
			{ "대게 라면", "5,000" },
			{ "회 · 스끼다시", "포함" },
			{ "찜 (대게 · 킹크랩)", "무료" },
		},
		sideTitle = "식사 · 추가",
		drinks = "소주 5,000  ·  맥주 5,000  ·  음료 2,000",
	},
	squid = {
		title = "오징어 메뉴",
		cols = { "가격" },
		main = {
			{ "산오징어회", "시가" },
			{ "오징어 숙회", "20,000" },
			{ "오징어 물회", "15,000" },
			{ "오징어 통찜", "18,000" },
			{ "오징어 볶음", "18,000" },
			{ "모듬회 (소)", "50,000" },
		},
		side = {
			{ "회덮밥", "13,000" },
			{ "오징어 순대", "15,000" },
			{ "매운탕", "8,000" },
			{ "공기밥", "1,000" },
		},
		sideTitle = "식사",
		drinks = "소주 5,000  ·  맥주 5,000  ·  음료 2,000",
	},
	sushi = {
		title = "SUSHI MENU",
		cols = { "가격" },
		main = {
			{ "모둠초밥 (12p)", "18,000" },
			{ "연어초밥 (10p)", "16,000" },
			{ "특선초밥 (12p)", "28,000" },
			{ "참치뱃살초밥", "32,000" },
			{ "장어초밥 (8p)", "22,000" },
			{ "오마카세 (런치)", "45,000" },
		},
		side = {
			{ "냉우동", "8,000" },
			{ "새우튀김", "12,000" },
			{ "사케 (도쿠리)", "9,000" },
			{ "하이볼", "9,000" },
			{ "생맥주", "6,000" },
		},
		sideTitle = "사이드 · 주류",
		drinks = "사케 9,000  ·  준마이 1병 45,000",
	},
}

-- 원산지 (식당 원산지 표시제)
local ORIGIN: { [string]: string } = {
	hoe = "광어 : 국내산 (제주)\n우럭 : 국내산 (통영)\n도다리 : 국내산\n참돔 : 일본산\n연어 : 노르웨이산\n멍게 · 해삼 : 국내산\n쌀 · 고춧가루 : 국내산\n배추김치 : 국내산",
	chojang = "광어 · 우럭 : 국내산\n참돔 : 일본산\n쌀 : 국내산\n고춧가루 : 국내산\n배추김치 : 국내산\n된장 : 국내산 콩",
	market = "광어 : 국내산 (제주 · 완도)\n우럭 : 국내산 (통영)\n참돔 : 일본산\n농어 : 국내산\n전복 : 국내산 (완도)\n가리비 : 국내산 (고성)",
	jjim = "가리비 : 국내산 (고성)\n키조개 : 국내산 (보령)\n백합 · 동죽 : 국내산\n홍합 : 국내산\n전복 : 국내산 (완도)\n쌀 · 고춧가루 : 국내산",
	crab = "대게 : 국내산 (영덕) · 러시아산\n킹크랩 : 러시아산\n홍게 : 국내산 (울진)\n랍스타 : 캐나다산\n쌀 : 국내산\n배추김치 : 국내산",
	squid = "오징어 : 국내산 (동해)\n광어 · 우럭 : 국내산\n쌀 · 고춧가루 : 국내산\n배추김치 : 국내산",
	sushi = "광어 : 국내산\n연어 : 노르웨이산\n참치 : 원양산\n장어 : 국내산\n새우 : 베트남산\n쌀 : 국내산",
}

local function themeFor(V: any): any
	local kind = kindOf(V)
	local seed = hash(tostring(V.name or "") .. tostring(V.key or ""))
	local n = tostring(V.name or "")
	local th: any = { kind = kind, seed = seed }
	local variant = kind
	if kind == "hoe" then
		if has(n, "진미") then
			variant = "wood"
		elseif has(n, "신라") or has(n, "물회") then
			variant = "red"
		elseif has(n, "파도") then
			variant = "blue"
		else
			variant = pickOf({ "blue", "wood", "red" }, seed, 1)
		end
	end
	th.variant = variant
	-- 기본값 (blue 횟집)
	th.accent = rgb(22, 66, 132)
	th.accent2 = rgb(204, 36, 40)
	th.ink = rgb(24, 32, 48)
	th.tile = L.of(242, 244, 244, M.CeramicTiles)
	th.grout = L.of(204, 210, 212)
	th.band = L.of(36, 96, 170, M.CeramicTiles)
	th.upper = L.of(216, 232, 242, M.SmoothPlastic)
	th.lowerKind = "tile"
	th.lowerH = 4.2
	th.floor = { look = L.of(150, 154, 156, M.Slate), tile = 2.0, grout = L.of(118, 122, 124) }
	th.stool = { kind = "steel", frame = L.chrome, seat = L.of(40, 84, 168, M.Leather) }
	th.table = { style = "four", top = L.of(196, 198, 198, M.SmoothPlastic, { r = 0.1 }), edge = L.of(150, 152, 154, M.SmoothPlastic, { r = 0.1 }), base = L.chrome, thick = 0.12, r = 0 }
	th.counter = { front = "panel", frontL = L.of(188, 192, 196, M.Metal), topL = STEEL_TOP, kickL = L.black, led = rgb(200, 230, 255) }
	th.chair = { style = "padded", frame = L.blackMetal, seat = L.fabricGrey }
	th.splash = L.of(244, 246, 246, M.CeramicTiles)
	th.tank = "fish"
	th.flags = false
	th.net = true
	th.fridgeHeader = "시원한 소주 · 맥주"
	th.wifi = "PADO_GUEST"
	if variant == "wood" then
		th.accent = rgb(20, 44, 78)
		th.accent2 = rgb(190, 146, 60)
		th.lowerKind = "wainscot"
		th.lowerH = 3.6
		th.tile = L.of(112, 78, 54, M.Wood)
		th.band = L.of(70, 48, 34, M.Wood)
		th.upper = L.of(236, 228, 210, M.SmoothPlastic)
		th.floor = { look = L.of(118, 110, 100, M.Slate), tile = 2.0, grout = L.of(92, 86, 78) }
		th.stool = { kind = "wood", frame = L.darkWood, seat = L.of(176, 132, 88, M.Wood) }
		th.table = { style = "four", top = L.of(132, 92, 60, M.Wood), base = L.blackMetal, thick = 0.16, r = 0 }
		th.counter = { front = "wood", frontL = L.of(100, 70, 48, M.Wood), topL = STEEL_TOP, kickL = L.black, led = rgb(255, 214, 160) }
		th.wifi = "JINMI_5G"
	elseif variant == "red" then
		th.accent = rgb(196, 28, 38)
		th.accent2 = rgb(20, 44, 96)
		th.band = L.of(196, 36, 40, M.CeramicTiles)
		th.upper = L.of(242, 238, 230, M.SmoothPlastic)
		th.floor = { look = L.of(170, 172, 170, M.Slate), tile = 2.0, grout = L.of(136, 138, 136) }
		th.stool = { kind = "steel", frame = L.chrome, seat = L.of(190, 34, 36, M.Leather) }
		th.wifi = "SILLA_MULHOE"
	elseif variant == "chojang" or variant == "market" then
		th.accent = rgb(0, 112, 120)
		th.accent2 = rgb(214, 48, 40)
		th.tile = L.of(214, 226, 222, M.CeramicTiles)
		th.band = L.of(0, 120, 128, M.CeramicTiles)
		th.upper = L.of(232, 242, 240, M.SmoothPlastic)
		th.floor = { look = L.of(122, 128, 128, M.Slate), tile = 1.8, grout = L.of(98, 102, 102) }
		th.stool = { kind = "plastic", seat = L.of(206, 52, 46, M.Plastic) }
		th.table = { style = "four", top = L.of(196, 198, 198, M.SmoothPlastic, { r = 0.1 }), base = L.of(170, 174, 178, M.Metal), thick = 0.1, r = 0 }
		th.wifi = if variant == "market" then "MILLAK_SUSAN" else "CHOJANG_FREE"
		th.flags = true
		th.fridgeHeader = "소주 · 맥주 · 음료"
	elseif variant == "jjim" then
		th.accent = rgb(232, 106, 28)
		th.accent2 = rgb(20, 52, 104)
		th.tile = L.of(206, 228, 240, M.CeramicTiles)
		th.band = L.of(232, 112, 36, M.CeramicTiles)
		th.upper = L.of(246, 244, 238, M.SmoothPlastic)
		th.floor = { look = L.of(140, 142, 144, M.Slate), tile = 2.0, grout = L.of(110, 112, 114) }
		th.stool = { kind = "plastic", seat = L.of(38, 96, 196, M.Plastic) }
		th.table = { style = "four", top = L.of(196, 198, 198, M.SmoothPlastic, { r = 0.1 }), base = L.of(170, 174, 178, M.Metal), thick = 0.1, r = 0 }
		th.tank = "shell"
		th.flags = true
		th.wifi = "JOGAE_JJIM"
	elseif variant == "crab" then
		th.accent = rgb(196, 36, 28)
		th.accent2 = rgb(214, 168, 64)
		th.ink = rgb(60, 20, 16)
		th.lowerKind = "wainscot"
		th.lowerH = 3.6
		th.tile = L.of(124, 44, 36, M.Wood)
		th.band = L.of(82, 30, 26, M.Wood)
		th.upper = L.of(244, 236, 220, M.SmoothPlastic)
		th.floor = { look = L.of(176, 164, 150, M.Slate), tile = 2.0, grout = L.of(140, 130, 118) }
		th.stool = { kind = "wood", frame = L.darkWood, seat = L.of(170, 40, 32, M.Leather) }
		th.table = { style = "four", top = L.of(168, 122, 82, M.Wood), base = L.blackMetal, thick = 0.16, r = 0 }
		th.counter = { front = "wood", frontL = L.of(110, 40, 32, M.Wood), topL = STEEL_TOP, kickL = L.black, led = rgb(255, 214, 160) }
		th.tank = "crab"
		th.wifi = "DAEGE_MILLAK"
	elseif variant == "squid" then
		th.accent = rgb(0, 128, 150)
		th.accent2 = rgb(244, 176, 40)
		th.band = L.of(0, 136, 156, M.CeramicTiles)
		th.upper = L.of(228, 240, 238, M.SmoothPlastic)
		th.stool = { kind = "plastic", seat = L.of(40, 150, 90, M.Plastic) }
		th.tank = "squid"
		th.flags = true
		th.wifi = "SQUID_GWANGAN"
	elseif variant == "sushi" then
		th.accent = rgb(26, 32, 58)
		th.accent2 = rgb(196, 58, 38)
		th.ink = rgb(30, 26, 22)
		th.lowerKind = "louver"
		th.lowerH = 3.4
		th.tile = L.of(222, 198, 158, M.Wood)
		th.band = L.of(60, 44, 32, M.Wood)
		th.upper = L.of(232, 222, 202, M.Plaster)
		th.floor = { look = L.of(62, 62, 64, M.Slate), tile = 1.8, grout = L.of(44, 44, 46) }
		th.stool = { kind = "steel", frame = L.blackMetal, seat = L.of(40, 36, 34, M.Leather) }
		th.chair = { style = "bentwood", frame = L.of(96, 66, 44, M.Wood), seat = L.of(120, 84, 56, M.Wood) }
		th.table = { style = "four", top = L.of(226, 204, 166, M.Wood), base = L.blackMetal, thick = 0.18, r = 0 }
		th.counter = { front = "fluted", frontL = L.of(84, 60, 42, M.Wood), topL = L.of(232, 212, 172, M.Wood), kickL = L.black, led = rgb(255, 210, 150) }
		th.splash = L.of(232, 222, 202, M.Plaster)
		th.tank = "none"
		th.net = false
		th.fridgeHeader = "SAKE · 사케"
		th.wifi = "SUSHI_OCEAN"
	end
	-- 타일 벽 매장: 카운터 앞도 같은 타일 (스테인리스 상판), 시장형은 스테인리스 판
	if th.lowerKind == "tile" and variant ~= "chojang" and variant ~= "market" then
		th.counter = { front = "tile", frontL = th.tile, topL = STEEL_TOP, kickL = th.band, led = rgb(200, 230, 255) }
	elseif variant == "chojang" or variant == "market" then
		th.counter = { front = "panel", frontL = L.of(214, 218, 222, M.SmoothPlastic, { r = 0.15 }), topL = STEEL_TOP, kickL = L.black, led = false }
	end
	th.menu = MENUS[if kind == "hoe" then "hoe" else kind] or MENUS.hoe
	th.origin = ORIGIN[if kind == "hoe" then "hoe" else kind] or ORIGIN.hoe
	return th
end

function T.style(V: any): any
	local th = themeFor(V)
	local S: any = {
		chair = th.chair,
		stool = false,
		table = th.table,
		counter = th.counter,
		ceiling = if th.kind == "sushi" then { grid = false, skin = L.of(176, 140, 100, M.WoodPlanks) } else { grid = true },
		floor = th.floor,
		base = if th.lowerKind == "wainscot" or th.lowerKind == "louver" then dim(th.band, 0.1) else L.of(70, 74, 78),
		lights = { kind = "none" },
		mat = { look = L.of(44, 46, 50, M.Fabric), text = if th.kind == "sushi" then "いらっしゃいませ" else "어서오세요" },
		plants = { "snake", "ficus", "bamboo" },
		clock = false,
	}
	if th.lowerKind == "wainscot" then
		S.lower = { kind = "wainscot", h = th.lowerH, look = th.tile, cap = th.band, panel = 2.8, walls = { "left", "right", "back" } }
	elseif th.lowerKind == "louver" then
		S.lower = { kind = "louver", h = th.lowerH, look = th.tile, back = L.of(60, 46, 34, M.Wood), pitch = 0.5, walls = { "left", "right", "back" } }
	else
		S.lower = { kind = "tile", h = th.lowerH, look = th.tile, grout = th.grout, tw = 0.9, th = 0.9, walls = { "left", "right", "back" } }
	end
	S.th = th
	return S
end

-- 스툴 (맵 Stool 을 같은 자리 · 같은 높이로): steel = 크롬 4다리 + 사각 가로대 + 비닐 쿠션 (횟집 표준),
-- wood = 원목, plastic = 포차 원형 플라스틱. Common 스툴보다 파트가 적음 (8~10, 저사양 3)
local function stoolsOver(c: any)
	local K, V, th = c.K, c.V, c.th
	local spec = th.stool
	if not spec then
		return
	end
	for _, ch in V.stools do
		local s = ch.seat
		if s.part:IsA("Seat") and s.part.Transparency >= 0.99 then
			continue
		end
		local top = ch.top
		local dia = math.max(0.9, math.min(1.6, math.max(s.size.X, s.size.Z)))
		local base = CF(s.c.X, 0, s.c.Z)
		K:free(function()
			local seatL = spec.seat
			if spec.kind == "plastic" then
				K:disc("StoolSeat", dia, 0.12, base * CF(0, top - 0.06, 0), seatL)
				K:disc("StoolBody", dia * 0.9, top * 0.5, base * CF(0, top - 0.12 - top * 0.25, 0), seatL)
				K:disc("StoolSkirt", dia * 1.06, top * 0.4, base * CF(0, top * 0.2, 0), seatL)
				if c.hi then
					K:disc("StoolGrip", dia * 0.32, 0.02, base * CF(0, top + 0.005, 0), dim(seatL, 0.35))
				end
				return
			end
			local fr = spec.frame
			local ct = if spec.kind == "wood" then 0.14 else 0.2
			K:disc("StoolSeat", dia, ct, base * CF(0, top - ct / 2, 0), seatL)
			if spec.kind ~= "wood" then
				K:disc("StoolSeatPan", dia * 0.84, 0.06, base * CF(0, top - ct - 0.03, 0), fr)
			end
			if K.detail == "low" then
				K:vcyl("StoolPost", top - ct, 0.2, base * CF(0, (top - ct) / 2, 0), fr)
				return
			end
			local r0, r1 = dia * 0.28, dia * 0.4
			local feet = {}
			local legD = if spec.kind == "wood" then 0.12 else 0.09
			for i = 0, 3 do
				local a = i * PI / 2 + PI / 4
				local p0 = base * V3(math.cos(a) * r0, top - ct - 0.04, math.sin(a) * r0)
				local p1 = base * V3(math.cos(a) * r1, 0.02, math.sin(a) * r1)
				K:seg("StoolLeg", p0, p1, legD, fr)
				table.insert(feet, { p0, p1 })
			end
			local ry = top * 0.34
			local pts = {}
			for i, f in feet do
				local k = (ry - f[2].Y) / (f[1].Y - f[2].Y)
				pts[i] = f[2]:Lerp(f[1], k)
			end
			for i = 1, 4 do
				K:seg("StoolRung", pts[i], pts[i % 4 + 1], legD * 0.65, fr)
			end
		end)
		for _, r in ch.parts do
			hideRec(K, r)
		end
		K:reserve(V3(s.min.X - 0.2, 0, s.min.Z - 0.2), V3(s.max.X + 0.2, top + 0.5, s.max.Z + 0.2), "stool")
	end
end

-- 윗벽 마감 (페인트 + 띠) ----------------------------------------------------------------------------------
local function wallFinish(c: any)
	local K, V, th = c.K, c.V, c.th
	local y0 = th.lowerH
	K:free(function()
		for _, wn in { "left", "right", "back" } do
			local w = V.walls[wn]
			if not w then
				continue
			end
			local len = w.b - w.a
			-- 윗벽 페인트 (맵 벽 바로 앞 0.01, 두께 0.015: 맵 벽 부착물은 모두 이보다 앞에 있음)
			K:plate("UpperPaint", len - 0.04, V.H - y0 - 0.04, 0.015, V:wall(wn, (w.a + w.b) / 2, y0 + (V.H - y0) / 2, 0.008), th.upper)
			-- 천장 몰딩
			K:plate("CeilTrim", len - 0.04, 0.16, 0.06, V:wall(wn, (w.a + w.b) / 2, V.H - 0.1, 0.0), lift(th.upper, 0.4))
			-- 아랫벽 위 띠 (타일 벽: 색 타일 한 줄)
			if th.lowerKind == "tile" then
				for _, s in V:spans(wn, y0 - 0.05, y0 + 0.3, 0.25) do
					K:plate("TileBand", s[2] - s[1], 0.3, 0.03, V:wall(wn, (s[1] + s[2]) / 2, y0 + 0.15, 0.012), th.band)
				end
			end
		end
	end)
end

-- 수족관 ----------------------------------------------------------------------------------------------------
local function tankSets(V: any): { any }
	local out = {}
	for _, w in V.byName.TankWater or {} do
		local set = nil
		for _, t in out do
			if w.min.X < t.max.X - 0.2 and w.max.X > t.min.X + 0.2 and w.min.Z < t.max.Z - 0.2 and w.max.Z > t.min.Z + 0.2 then
				set = t
				break
			end
		end
		if not set then
			set = { waters = {}, min = w.min, max = w.max }
			table.insert(out, set)
		end
		table.insert(set.waters, w)
		set.min = V3(math.min(set.min.X, w.min.X), math.min(set.min.Y, w.min.Y), math.min(set.min.Z, w.min.Z))
		set.max = V3(math.max(set.max.X, w.max.X), math.max(set.max.Y, w.max.Y), math.max(set.max.Z, w.max.Z))
	end
	for _, t in out do
		table.sort(t.waters, function(a, b)
			return a.min.Y < b.min.Y
		end)
		t.stands, t.rims, t.lamps, t.gravel, t.fish = {}, {}, {}, {}, {}
		local map = { TankStand = t.stands, TankRim = t.rims, TankLamp = t.lamps, Gravel = t.gravel, Fish = t.fish }
		for nm, list in map do
			for _, r in V.byName[nm] or {} do
				if r.c.X > t.min.X - 0.6 and r.c.X < t.max.X + 0.6 and r.c.Z > t.min.Z - 0.6 and r.c.Z < t.max.Z + 0.6 then
					table.insert(list, r)
				end
			end
		end
	end
	return out
end

-- 물고기 · 해산물 (로컬 +X = 머리 쪽). 반환 { {p, off} } (애니메이션용 상대 위치)
local function addPart(list: { any }, p: BasePart?, off: CFrame)
	if p then
		table.insert(list, { p = p, off = off })
	end
end

local FISH: { [string]: any } = {
	rockfish = { body = rgb(70, 66, 60), belly = rgb(150, 140, 126), fin = rgb(52, 48, 44), len = 1.05, h = 0.42, w = 0.3 }, -- 우럭
	bream = { body = rgb(214, 112, 112), belly = rgb(240, 196, 186), fin = rgb(196, 90, 90), len = 1.1, h = 0.5, w = 0.24 }, -- 참돔
	bass = { body = rgb(176, 184, 190), belly = rgb(226, 230, 232), fin = rgb(120, 126, 132), len = 1.25, h = 0.32, w = 0.24 }, -- 농어
	blackbream = { body = rgb(60, 64, 72), belly = rgb(120, 126, 134), fin = rgb(40, 42, 48), len = 1.0, h = 0.48, w = 0.22 }, -- 감성돔
}

local function swimmer(K: any, base: CFrame, kind: string, s: number, hi: boolean): { any }
	local spec = FISH[kind] or FISH.rockfish
	local len, h, w = spec.len * s, spec.h * s, spec.w * s
	local out = {}
	local function put(p: BasePart?, off: CFrame)
		addPart(out, p, off)
	end
	local bodyL = col(spec.body, M.SmoothPlastic)
	local o0 = CF()
	put(K:ell("FishBody", V3(len, h, w), base * o0, bodyL), o0)
	local ob = CF(0.04 * s, -h * 0.18, 0)
	put(K:ell("FishBelly", V3(len * 0.8, h * 0.6, w * 0.92), base * ob, col(spec.belly)), ob)
	local ot = CF(-len * 0.55, 0, 0)
	put(K:ell("FishTail", V3(len * 0.28, h * 0.95, 0.03), base * ot, col(spec.fin)), ot)
	local od = CF(-len * 0.05, h * 0.46, 0)
	put(K:ell("FishFin", V3(len * 0.6, h * 0.36, 0.025), base * od, col(spec.fin)), od)
	if hi then
		for _, sz in { -1, 1 } do
			local oe = CF(len * 0.33, h * 0.12, sz * w * 0.4)
			put(K:ball("FishEye", 0.09 * s, base * oe, col(rgb(230, 220, 170))), oe)
			local op = CF(len * 0.36, h * 0.12, sz * w * 0.46)
			put(K:ball("FishPupil", 0.05 * s, base * op, L.black), op)
			local of = CF(len * 0.12, -h * 0.12, sz * w * 0.45) * ANG(0, sz * 0.5, 0.4)
			put(K:ell("FishPectoral", V3(len * 0.22, h * 0.28, 0.02), base * of, col(spec.fin)), of)
		end
		if kind == "bream" then
			for i = 1, 3 do
				local osp = CF(len * (0.2 - i * 0.12), h * 0.22, w * 0.47)
				put(K:ball("FishSpot", 0.04 * s, base * osp, L.neon(rgb(120, 200, 255))), osp)
			end
		elseif kind == "rockfish" then
			for i = 1, 2 do
				local osp = CF(len * (0.15 - i * 0.2), 0, 0)
				put(K:ell("FishBand", V3(0.08 * s, h * 0.9, w * 1.02), base * osp, col(rgb(46, 44, 40))), osp)
			end
		end
	end
	return out
end

-- 광어 · 도다리 (바닥에 납작): base 는 바닥 위
local function flatfish(K: any, base: CFrame, s: number, hi: boolean, light: boolean)
	local bodyC = if light then rgb(132, 118, 90) else rgb(104, 92, 70)
	K:ell("FlatfishBody", V3(1.3 * s, 0.16 * s, 0.74 * s), base * CF(0, 0.08 * s, 0), col(bodyC))
	K:ell("FlatfishFin", V3(1.36 * s, 0.05 * s, 0.86 * s), base * CF(-0.02 * s, 0.04 * s, 0), col(bodyC:Lerp(rgb(200, 190, 160), 0.25)))
	K:ell("FlatfishTail", V3(0.32 * s, 0.05 * s, 0.4 * s), base * CF(-0.74 * s, 0.04 * s, 0), col(bodyC:Lerp(rgb(0, 0, 0), 0.15)))
	if hi then
		for i = 1, 3 do
			K:ell("FlatfishSpot", V3(0.16 * s, 0.03 * s, 0.12 * s), base * CF((0.25 - i * 0.22) * s, 0.155 * s, ((i % 2) - 0.5) * 0.3 * s), col(bodyC:Lerp(rgb(0, 0, 0), 0.4)))
		end
		K:ball("FlatfishEye", 0.08 * s, base * CF(0.42 * s, 0.17 * s, -0.08 * s), col(rgb(40, 36, 30)))
		K:ball("FlatfishEye", 0.08 * s, base * CF(0.38 * s, 0.17 * s, 0.06 * s), col(rgb(40, 36, 30)))
	end
end

-- 대게 (몸통 + 다리 8 + 집게 2). base 는 바닥 위, +X = 앞
local function crab(K: any, base: CFrame, s: number, kind: string, hi: boolean)
	local shell = if kind == "king" then rgb(176, 48, 44) elseif kind == "red" then rgb(214, 82, 52) else rgb(186, 112, 66)
	local leg = shell:Lerp(rgb(240, 200, 160), if kind == "king" then 0.1 else 0.25)
	local bh = 0.28 * s
	local y = 0.42 * s
	K:ell("CrabShell", V3(0.86 * s, bh, 0.8 * s), base * CF(0, y, 0), col(shell))
	K:ell("CrabBelly", V3(0.74 * s, bh * 0.6, 0.7 * s), base * CF(0, y - bh * 0.3, 0), col(rgb(236, 220, 196)))
	if hi then
		K:ball("CrabEye", 0.07 * s, base * CF(0.42 * s, y + bh * 0.42, 0.08 * s), L.black)
		K:ball("CrabEye", 0.07 * s, base * CF(0.42 * s, y + bh * 0.42, -0.08 * s), L.black)
		if kind == "king" then
			for i = 1, 4 do
				K:ball("CrabSpike", 0.08 * s, base * CF((0.25 - i * 0.12) * s, y + bh * 0.48, ((i % 2) - 0.5) * 0.3 * s), col(shell:Lerp(rgb(255, 230, 200), 0.3)))
			end
		end
	end
	local legD = (if kind == "king" then 0.13 else 0.085) * s
	local reach = (if kind == "king" then 1.05 else 1.25) * s
	local nLegs = if hi then 4 else 3
	for _, sz in { -1, 1 } do
		for i = 1, nLegs do
			local ax = (0.22 - (i - 1) * 0.16) * s
			local a = base * V3(ax, y, sz * 0.32 * s)
			local spread = (i - 2.5) * 0.28
			local knee = base * V3(ax + math.sin(spread) * reach * 0.5, y + 0.22 * s, sz * (0.32 * s + math.cos(spread) * reach * 0.5))
			local foot = base * V3(ax + math.sin(spread) * reach * 0.9, 0.03, sz * (0.32 * s + math.cos(spread) * reach * 0.95))
			K:seg("CrabLeg", a, knee, legD, col(leg))
			K:seg("CrabLeg", knee, foot, legD * 0.8, col(leg))
		end
		-- 집게
		local ca = base * V3(0.38 * s, y, sz * 0.25 * s)
		local cb = base * V3(0.68 * s, y + 0.1 * s, sz * 0.42 * s)
		K:seg("CrabArm", ca, cb, legD * 1.3, col(leg))
		K:ell("CrabClaw", V3(0.34 * s, 0.14 * s, 0.12 * s), CFrame.lookAt(cb, cb + (base.XVector * 0.8 + base.ZVector * sz * 0.4)) * CF(0, 0, -0.14 * s) * ANG(0, PI / 2, 0), col(shell))
	end
end

-- 랍스타
local function lobster(K: any, base: CFrame, s: number, hi: boolean)
	local c0 = rgb(40, 60, 76)
	local y = 0.24 * s
	K:ell("LobsterBody", V3(0.8 * s, 0.32 * s, 0.34 * s), base * CF(0.2 * s, y, 0), col(c0))
	for i = 1, 4 do
		K:ell("LobsterTail", V3(0.24 * s, 0.24 * s, 0.3 * s), base * CF((-0.25 - i * 0.18) * s, y - i * 0.01, 0), col(c0:Lerp(rgb(80, 40, 30), 0.2)))
	end
	K:ell("LobsterFan", V3(0.2 * s, 0.06 * s, 0.4 * s), base * CF(-1.05 * s, y - 0.06, 0), col(c0))
	for _, sz in { -1, 1 } do
		local a = base * V3(0.5 * s, y, sz * 0.14 * s)
		local b = base * V3(0.85 * s, y + 0.04, sz * 0.4 * s)
		K:seg("LobsterArm", a, b, 0.08 * s, col(c0))
		K:ell("LobsterClaw", V3(0.6 * s, 0.2 * s, 0.26 * s), CF(b) * CFrame.fromMatrix(V3(), base.XVector, base.YVector, base.ZVector) * CF(0.32 * s, 0, sz * 0.06 * s), col(c0:Lerp(rgb(0, 0, 0), 0.15)))
		if hi then
			K:seg("LobsterAntenna", base * V3(0.58 * s, y + 0.08, sz * 0.06 * s), base * V3(1.6 * s, y + 0.5 * s, sz * 0.5 * s), 0.025, col(rgb(150, 80, 60)))
			for i = 1, 3 do
				K:seg("LobsterLeg", base * V3((0.25 - i * 0.12) * s, y, sz * 0.14 * s), base * V3((0.2 - i * 0.12) * s, 0.03, sz * 0.42 * s), 0.035 * s, col(c0))
			end
		end
	end
end

-- 산오징어 (몸통 + 지느러미 + 다리). 반환 애니메이션용 목록. +X = 다리 쪽
local function squid(K: any, base: CFrame, s: number, hi: boolean): { any }
	local out = {}
	local skin = { c = rgb(232, 206, 196), m = M.SmoothPlastic, t = 0.15 }
	local o1 = CF(-0.3 * s, 0, 0)
	addPart(out, K:ell("SquidMantle", V3(1.0 * s, 0.26 * s, 0.26 * s), base * o1, skin), o1)
	local o2 = CF(-0.72 * s, 0, 0)
	addPart(out, K:ell("SquidFin", V3(0.3 * s, 0.04 * s, 0.5 * s), base * o2, skin), o2)
	local o3 = CF(0.26 * s, 0, 0)
	addPart(out, K:ell("SquidHead", V3(0.22 * s, 0.2 * s, 0.22 * s), base * o3, skin), o3)
	if hi then
		for _, sz in { -1, 1 } do
			local oe = CF(0.27 * s, 0.03 * s, sz * 0.1 * s)
			addPart(out, K:ball("SquidEye", 0.07 * s, base * oe, L.black), oe)
		end
		for i = 1, 3 do
			local a = (i - 2) * 0.22
			local oa = CF(0.62 * s, -0.02 * s, a * 0.4 * s) * ANG(0, -a, 0)
			addPart(out, K:ell("SquidArm", V3(0.65 * s, 0.05 * s, 0.05 * s), base * oa, { c = rgb(236, 190, 180), m = M.SmoothPlastic, t = 0.2 }), oa)
		end
	else
		local oa = CF(0.62 * s, 0, 0)
		addPart(out, K:ell("SquidArm", V3(0.65 * s, 0.07 * s, 0.14 * s), base * oa, skin), oa)
	end
	return out
end

-- 조개 무더기 (바구니 안 · 얼음 위): pcf 바닥 가운데, w x d 범위
local function shellPile(K: any, pcf: CFrame, w: number, d: number, kind: string, seed: number, n: number)
	for i = 1, n do
		local x = (rnd(seed, i) - 0.5) * (w - 0.3)
		local z = (rnd(seed, i + 40) - 0.5) * (d - 0.3)
		local y = 0.06 + rnd(seed, i + 80) * 0.08
		local yaw = rnd(seed, i + 120) * PI * 2
		local base = pcf * CF(x, y, z) * ANG(0, yaw, 0)
		if kind == "scallop" then
			K:ell("Scallop", V3(0.42, 0.09, 0.4), base * ANG(0.15, 0, 0), col(if i % 3 == 0 then rgb(214, 120, 70) else rgb(196, 90, 60)))
		elseif kind == "pen" then
			K:ell("PenShell", V3(0.7, 0.1, 0.32), base, col(rgb(54, 46, 40)))
		elseif kind == "mussel" then
			K:ell("Mussel", V3(0.34, 0.12, 0.17), base, col(rgb(28, 28, 36)))
		elseif kind == "clam" then
			K:ell("Clam", V3(0.3, 0.14, 0.25), base, col(if i % 2 == 0 then rgb(218, 206, 180) else rgb(170, 150, 120)))
		elseif kind == "abalone" then
			K:ell("Abalone", V3(0.38, 0.12, 0.28), base, col(rgb(96, 84, 62)))
			K:ell("AbaloneFoot", V3(0.3, 0.06, 0.2), base * CF(0, -0.05, 0), col(rgb(210, 196, 160)))
		elseif kind == "conch" then
			K:ell("Conch", V3(0.3, 0.26, 0.3), base * CF(0, 0.08, 0), col(rgb(150, 120, 90), M.Slate))
		end
	end
end

-- 멍게 (주황 울퉁불퉁) · 해삼
local function seaSquirt(K: any, base: CFrame, s: number)
	K:ell("SeaSquirt", V3(0.36 * s, 0.46 * s, 0.34 * s), base * CF(0, 0.23 * s, 0), col(rgb(232, 96, 44)))
	K:ball("SeaSquirtKnob", 0.12 * s, base * CF(0.08 * s, 0.44 * s, 0), col(rgb(240, 120, 60)))
	K:ball("SeaSquirtKnob", 0.1 * s, base * CF(-0.1 * s, 0.4 * s, 0.06 * s), col(rgb(240, 120, 60)))
end

local function seaCucumber(K: any, base: CFrame, s: number)
	K:ell("SeaCucumber", V3(0.8 * s, 0.2 * s, 0.24 * s), base * CF(0, 0.1 * s, 0), col(rgb(52, 44, 40)))
	for i = 1, 3 do
		K:ball("SeaCucumberBump", 0.07 * s, base * CF((i - 2) * 0.2 * s, 0.2 * s, 0), col(rgb(70, 58, 50)))
	end
end

local function tankOverlay(c: any, t: any)
	local K, V, th = c.K, c.V, c.th
	local hi = c.hi
	local cx, cz = (t.min.X + t.max.X) / 2, (t.min.Z + t.max.Z) / 2
	local W, D = t.max.X - t.min.X, t.max.Z - t.min.Z
	-- 방 안쪽 면 (손님이 보는 면) = tcf +Z
	local dz1, dz0, dx0, dx1 = V.z1 - t.max.Z, t.min.Z - V.z0, t.min.X - V.x0, V.x1 - t.max.X
	local m = math.min(dz1, dz0, dx0, dx1)
	local f: Vector3
	if m == dz1 then
		f = V3(0, 0, -1)
	elseif m == dz0 then
		f = V3(0, 0, 1)
	elseif m == dx0 then
		f = V3(1, 0, 0)
	else
		f = V3(-1, 0, 0)
	end
	local tw, td = W, D
	if math.abs(f.X) > 0.5 then
		tw, td = D, W
	end
	local tcf = CFrame.fromMatrix(V3(cx, 0, cz), Vector3.yAxis:Cross(f), Vector3.yAxis, f)
	local hw, hd = tw / 2, td / 2
	local steel = L.of(200, 204, 208, M.Metal, { r = 0.1 })
	local frameL = L.of(150, 156, 162, M.Metal)
	local topY = t.max.Y
	for _, r in t.rims do
		topY = math.max(topY, r.max.Y)
	end
	t.tcf, t.hw, t.hd, t.topY = tcf, hw, hd, topY
	local standTop = t.waters[1].min.Y
	-- 받침장: 맵 TankStand 를 같은 크기 스테인리스 장으로
	K:free(function()
		for _, s in t.stands do
			hideRec(K, s)
		end
		if standTop > 0.5 then
			local sy = standTop
			local sw, sd = tw + 0.04, td + 0.04
			K:box("TankCabinet", V3(sw - 0.1, sy - 0.32, sd - 0.1), tcf * CF(0, 0.32 + (sy - 0.32) / 2, 0), L.brushed)
			K:box("TankCabinetKick", V3(sw - 0.3, 0.32, sd - 0.3), tcf * CF(0, 0.16, 0), L.black)
			K:box("TankCabinetTop", V3(sw + 0.04, 0.08, sd + 0.04), tcf * CF(0, sy - 0.04, 0), steel)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					K:box("TankCabinetPost", V3(0.12, sy - 0.08, 0.12), tcf * CF(sx * (sw / 2 - 0.06), (sy - 0.08) / 2, sz * (sd / 2 - 0.06)), steel)
				end
			end
			-- 방 쪽 문 (여과기 · 냉각기 수납)
			local nd = math.max(2, math.floor(tw / 2.3))
			local dw = (sw - 0.3) / nd
			local dh = sy - 0.52
			for i = 1, nd do
				local x = -sw / 2 + 0.15 + dw * (i - 0.5)
				local dc = tcf * CF(x, 0.32 + 0.1 + dh / 2, sd / 2 - 0.05)
				K:plate("TankCabDoor", dw - 0.08, dh, 0.04, dc, steel)
				K:plate("TankCabHandle", math.min(0.6, dw * 0.3), 0.06, 0.05, dc * CF(0, dh / 2 - 0.14, 0.04), L.chrome)
				if hi and i == nd then
					for k = 1, 5 do
						K:plate("TankCabVent", dw * 0.55, 0.035, 0.02, dc * CF(0, -dh / 2 + 0.12 + k * 0.1, 0.04), L.of(70, 74, 78, M.Metal))
					end
				end
			end
			-- 냉각기 온도 표시 (빨간 LED)
			local disp = tcf * CF(-sw / 2 + 0.15 + dw * 0.5, 0.32 + 0.1 + dh * 0.62, sd / 2 - 0.01)
			K:plate("ChillerPanel", 0.62, 0.3, 0.04, disp, L.black)
			K:text("ChillerLED", 0.5, 0.2, disp * CF(0, 0, 0.041), "14.5℃", { fg = rgb(255, 60, 40), glow = 1.6, font = F.Arcade, d = 0.01 })
			-- 거리 쪽 면: 수산 스티커
			local sc = tcf * CF(0, sy * 0.55, -sd / 2 + 0.05) * ANG(0, PI, 0)
			ktext(K, "TankStreetSticker", math.min(4.2, tw * 0.5), 0.5, sc, if th.tank == "crab" then "영덕 · 울진 대게 직송" elseif th.tank == "shell" then "싱싱한 조개 · 산지 직송" elseif th.tank == "squid" then "동해 산오징어" else "자연산 활어 · 매일 입고", { fg = WHITE, bg = th.accent, font = F.GothamBlack, d = 0.02 })
		end
		-- 수족관 앞 바닥 배수 트렌치 (스테인리스 그레이팅, 바닥과 같은 높이)
		if standTop > 0.5 then
			local gl = tw - 0.4
			local gcf = tcf * CF(0, 0.012, hd + 0.5)
			K:box("TrenchFrame", V3(gl + 0.12, 0.024, 0.5), gcf, L.of(170, 174, 178, M.Metal))
			K:box("TrenchSlot", V3(gl - 0.04, 0.026, 0.38), gcf, L.of(40, 42, 44, M.Metal))
			local nb = if hi then math.floor(gl / 0.36) else 0
			for k = 1, nb - 1 do
				K:box("TrenchBar", V3(0.05, 0.03, 0.4), gcf * CF(-gl / 2 + k * gl / nb, 0.003, 0), L.of(190, 194, 198, M.Metal, { r = 0.1 }))
			end
		end
		-- 물칸마다: 모서리 앵글 · 아래 실리콘 띠 · LED
		for i, wt in t.waters do
			local y0, y1 = wt.min.Y, wt.max.Y
			local h = y1 - y0
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					K:box("TankAngle", V3(0.12, h, 0.12), tcf * CF(sx * (hw + 0.035), y0 + h / 2, sz * (hd + 0.035)), frameL)
				end
			end
			for _, sz in { -1, 1 } do
				K:box("TankSeal", V3(tw + 0.1, 0.08, 0.05), tcf * CF(0, y0 + 0.04, sz * (hd + 0.03)), L.of(30, 34, 40))
			end
			for _, sx in { -1, 1 } do
				K:box("TankSeal", V3(0.05, 0.08, td + 0.1), tcf * CF(sx * (hw + 0.03), y0 + 0.04, 0), L.of(30, 34, 40))
			end
			-- 물 안 LED 바 (방 쪽 위) : 수조 조명
			local led = K:box("TankLED", V3(tw - 0.5, 0.05, 0.08), tcf * CF(0, y1 - 0.1, hd - 0.22), L.neon(rgb(150, 220, 255)))
			table.insert(c.tankLeds, { p = led, c = led.Color })
			if i == #t.waters then
				local l = K:light(led, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 9, Brightness = 1.4, Angle = 120, Color = rgb(140, 210, 255) })
				if l then
					table.insert(c.tankLights, l)
				end
			end
		end
		-- 테두리 (맵 TankRim 을 같은 범위 스테인리스로)
		for _, r in t.rims do
			hideRec(K, r)
			local sz = r.max - r.min
			K:box("TankRimSkin", sz, CF(r.c), steel)
			K:box("TankRimLip", V3(sz.X + 0.06, 0.05, sz.Z + 0.06), CF(r.c.X, r.max.Y - 0.025, r.c.Z), L.chrome)
		end
	end)
	-- 맵 물고기는 숨기고 새로 (같은 물칸 안)
	for _, r in t.fish do
		hideRec(K, r)
	end
	-- 가격표 (방 쪽 면 아래 칸 위) : 집게 달린 흰 카드
	local tags: { { string } } = { { "광어", "시가" }, { "우럭", "시가" }, { "도다리", "시가" } }
	if th.tank == "shell" then
		tags = { { "가리비", "kg 18,000" }, { "키조개", "1미 8,000" }, { "전복", "1미 5,000" } }
	elseif th.tank == "crab" then
		tags = { { "대게", "kg 89,000" }, { "킹크랩", "kg 135,000" }, { "홍게", "kg 45,000" } }
	elseif th.tank == "squid" then
		tags = { { "산오징어", "시가" }, { "광어", "시가" }, { "우럭", "시가" } }
	elseif th.variant == "market" then
		tags = { { "광어", "kg 35,000" }, { "우럭", "kg 40,000" }, { "참돔", "kg 50,000" } }
	end
	if #t.waters >= 1 then
		local wt = t.waters[1]
		local nT = math.min(#tags, math.max(1, math.floor(tw / 2.6)))
		for i = 1, nT do
			local x = -hw + tw * (i - 0.5) / nT
			local dc = tcf * CF(x, wt.max.Y - 0.32, hd + 0.075)
			K:free(function()
				K:plate("PriceTagBack", 0.95, 0.46, 0.02, dc, L.of(250, 214, 40))
				K:plate("PriceTagClip", 0.16, 0.12, 0.04, dc * CF(0, 0.27, 0), L.of(40, 120, 200))
				K:text("PriceTag", 0.86, 0.4, dc * CF(0, 0, 0.021), tags[i][1] .. "\n" .. tags[i][2], { fg = rgb(30, 24, 20), font = F.GothamBlack, d = 0.005, free = true, glow = 0.7 })
			end)
		end
	end
	-- 위 장비 (방 쪽 절반): 여과기 · 기포기 · UV 살균기 · 멀티탭 · 배관
	local top = topY
	local eq = tcf * CF(0, top, hd - 0.62)
	local filterW = math.min(3.6, tw * 0.42)
	local fcf = eq * CF(-hw + 0.3 + filterW / 2, 0, 0)
	if clearAt(K, fcf * CF(0, 0.4, 0), V3(filterW, 0.8, 1.0)) then
		K:box("TankFilterBox", V3(filterW, 0.7, 0.95), fcf * CF(0, 0.36, 0), L.of(60, 96, 140, M.Plastic))
		K:box("TankFilterLid", V3(filterW + 0.06, 0.06, 1.0), fcf * CF(0, 0.74, 0), L.of(40, 70, 110, M.Plastic))
		K:box("TankFilterMedia", V3(filterW - 0.3, 0.04, 0.7), fcf * CF(0, 0.78, 0), L.of(230, 230, 220, M.Fabric))
		ktext(K, "TankFilterLabel", math.min(1.6, filterW * 0.5), 0.26, fcf * CF(0, 0.36, 0.476), "여과조 · 매일 청소", { fg = WHITE, d = 0.01 })
		-- 하수 파이프 (여과조 -> 위 물칸)
		for k = 1, 2 do
			local px = -filterW / 2 + filterW * k / 3
			local a = (fcf * CF(px, 0.02, 0.2)).Position
			local b = (fcf * CF(px, -1.3, 0.2)).Position
			K:seg("TankPipe", a, b, 0.2, L.of(236, 236, 232, M.Plastic))
			K:ball("TankPipeElbow", 0.26, fcf * CF(px, 0.02, 0.2), L.of(236, 236, 232, M.Plastic))
		end
	end
	local pcf = eq * CF(hw - 1.0, 0, 0.05)
	if clearAt(K, pcf * CF(0, 0.25, 0), V3(0.8, 0.5, 0.6)) then
		K:box("AirPump", V3(0.72, 0.36, 0.46), pcf * CF(0, 0.18, 0), L.of(234, 236, 236, M.Plastic))
		K:box("AirPumpBand", V3(0.74, 0.08, 0.48), pcf * CF(0, 0.28, 0), L.of(40, 120, 200, M.Plastic))
		K:plate("AirPumpLED", 0.06, 0.06, 0.02, pcf * CF(0.25, 0.2, 0.23), L.ledGreen)
	end
	local ucf = eq * CF(0.2, 0, 0.12)
	if hi and clearAt(K, ucf * CF(0, 0.2, 0), V3(1.9, 0.36, 0.36)) then
		K:cyl("UVSterilizer", 1.7, 0.32, ucf * CF(0, 0.18, 0), L.of(180, 186, 192, M.Metal))
		K:cyl("UVCap", 0.12, 0.36, ucf * CF(-0.9, 0.18, 0), L.of(40, 110, 200, M.Plastic))
		K:cyl("UVCap", 0.12, 0.36, ucf * CF(0.9, 0.18, 0), L.of(40, 110, 200, M.Plastic))
		K:ball("UVLamp", 0.08, ucf * CF(0.97, 0.26, 0), L.neon(rgb(150, 120, 255)))
	end
	-- 반환 배관 (탱크 끝 바깥으로 내려가 받침장으로)
	if hi then
		local px = hw + 0.22
		local pz = hd - 0.45
		local a = tcf * V3(px - 0.4, top + 0.5, pz)
		local b = tcf * V3(px, top + 0.5, pz)
		local cbot = tcf * V3(px, standTop - 0.1, pz)
		local mn, mx = laabb(CF((b + cbot) / 2), V3(0.3, (b - cbot).Magnitude, 0.3))
		if K:hitsKeep(mn, mx) == nil and mapClear(V, mn, mx) then
			K:seg("TankReturnPipe", a, b, 0.2, L.of(236, 236, 232, M.Plastic))
			K:ball("TankPipeElbow", 0.26, CF(b), L.of(236, 236, 232, M.Plastic))
			K:seg("TankReturnPipe", b, cbot, 0.2, L.of(236, 236, 232, M.Plastic))
			K:cyl("TankValve", 0.16, 0.3, CF(tcf * V3(px, standTop + 1.0, pz)) * ANG(0, 0, PI / 2), L.of(40, 110, 200, M.Plastic))
			K:box("TankValveHandle", V3(0.36, 0.06, 0.1), CF(tcf * V3(px, standTop + 1.0, pz + 0.2)), L.of(200, 40, 40, M.Plastic))
		end
	end
	-- 뜰채 (탱크 끝에 기대 세움)
	do
		local nx = -hw - 0.32
		local base = tcf * CF(nx, 0, hd - 0.35)
		local mn, mx = laabb(base * CF(0, 3.3, 0), V3(0.4, 6.6, 0.4))
		if K:hitsKeep(mn, mx) == nil and mapClear(V, mn, mx) and K:spot(base, V3(0.4, 6.6, 0.4), 0, "net") then
			local topP = (base * CF(0.05, 6.4, 0.1)).Position
			K:seg("NetPole", (base * CF(0, 0.6, 0)).Position, topP, 0.07, L.of(60, 120, 200, M.Plastic))
			local rc = CF(topP + V3(0, 0.38, 0)) * CFrame.fromMatrix(V3(), tcf.XVector, tcf.YVector, tcf.ZVector)
			K:ring("NetRing", rc * ANG(0, PI / 2, 0), 0.36, 0.04, 10, L.of(60, 120, 200, M.Plastic))
			K:ell("NetMesh", V3(0.04, 0.68, 0.6), rc * CF(0, -0.12, 0), { c = rgb(30, 60, 50), m = M.Fabric, t = 0.4 })
		end
	end
	-- 물칸 안 내용물 + 기포
	local swim: { any } = {}
	local bubbles: { any } = {}
	for i, wt in t.waters do
		local y0, y1 = wt.min.Y, wt.max.Y
		local gTop = y0 + 0.25
		for _, g in t.gravel do
			if g.max.Y > y0 and g.max.Y < y1 then
				gTop = math.max(gTop, g.max.Y)
			end
		end
		local lower = (i == 1)
		local bottom = tcf * CF(0, gTop, 0)
		local seed = c.seed + i * 17
		K:free(function()
			-- 돌 몇 개
			for k = 1, (if hi then 3 else 2) do
				local x = -hw + tw * (k / 4) + (rnd(seed, k) - 0.5) * 0.6
				K:ell("TankRock", V3(0.55 + rnd(seed, k + 5) * 0.4, 0.3, 0.45), bottom * CF(x, 0.1, -hd + 0.5 + rnd(seed, k + 9) * 0.4), L.of(110, 106, 100, M.Slate))
			end
			-- 기포석 + 호스
			for k = 1, 2 do
				local x = -hw + tw * (if k == 1 then 0.18 else 0.78)
				local z = -hd + 0.45
				K:vcyl("AirStone", 0.16, 0.22, bottom * CF(x, 0.08, z), L.of(130, 130, 126, M.Slate))
				K:seg("AirHose", (bottom * CF(x, 0.15, z)).Position, (tcf * CF(x * 0.98, y1 + 0.35, z)).Position, 0.035, { c = rgb(220, 230, 230), m = M.Glass, t = 0.3 })
				for b = 1, (if hi then 6 else 3) do
					local p = K:ball("TankBubble", 0.08 + (b % 3) * 0.03, bottom * CF(x, 0.3 + b * 0.3, z), { c = rgb(236, 248, 255), m = M.SmoothPlastic, t = 0.4, r = 0.3 })
					table.insert(bubbles, { p = p, base = bottom * CF(x, 0, z), h = (y1 - 0.15) - gTop, k = b, n = (if hi then 6 else 3) })
				end
			end
			local content = th.tank
			if content == "fish" then
				if lower then
					local n = if hi then 4 else 2
					for k = 1, n do
						local x = -hw + 0.9 + (tw - 1.8) * (k - 0.5) / n
						flatfish(K, bottom * CF(x, 0, (rnd(seed, k) - 0.5) * (td - 1.0)) * ANG(0, (rnd(seed, k + 3) - 0.5) * 1.6, 0), 0.9 + rnd(seed, k + 7) * 0.3, hi, k % 2 == 0)
					end
					seaSquirt(K, bottom * CF(hw - 0.7, 0, hd - 0.5), 1.0)
					seaSquirt(K, bottom * CF(hw - 1.2, 0, hd - 0.7), 0.8)
					seaCucumber(K, bottom * CF(-hw + 1.0, 0, hd - 0.5) * ANG(0, 0.6, 0), 1.0)
					-- 유리에 붙은 전복
					if hi then
						for k = 1, 3 do
							local x = -hw * 0.4 + k * 0.9
							K:ell("AbaloneGlass", V3(0.4, 0.3, 0.12), tcf * CF(x, gTop + 0.35 + (k % 2) * 0.4, hd - 0.08), col(rgb(92, 80, 60)))
						end
					end
				else
					local kinds = { "rockfish", "bream", "rockfish", "bass", "blackbream", "rockfish" }
					local n = if hi then 5 else 3
					for k = 1, n do
						local kind = kinds[(k + c.seed) % #kinds + 1]
						local y = gTop + 0.55 + ((k * 0.37) % 1) * math.max(0.4, (y1 - gTop) - 1.2)
						local z = -hd + 0.45 + ((k * 0.61) % 1) * (td - 0.9)
						local base = tcf * CF(0, y, z)
						local parts = swimmer(K, base, kind, 0.85 + rnd(seed, k) * 0.35, hi)
						table.insert(swim, { parts = parts, tcf = tcf, y = y, z = z, A = hw - 0.9, spd = 0.25 + rnd(seed, k + 11) * 0.2, ph = rnd(seed, k + 13) * 6.28, bob = 0.06 })
					end
				end
			elseif content == "shell" then
				if lower then
					-- 망 바구니 3개 (가리비 · 키조개 · 백합)
					local kinds = { "scallop", "pen", "clam" }
					local nb = math.max(2, math.min(3, math.floor(tw / 2.8)))
					local bw = (tw - 0.6) / nb - 0.25
					for k = 1, nb do
						local x = -hw + 0.3 + (bw + 0.25) * (k - 0.5) + 0.12
						local bc = bottom * CF(x, 0, 0)
						local bd = td - 0.7
						local basket = L.of(40, 150, 90, M.Plastic, { t = 0.15 })
						K:box("ShellBasket", V3(bw, 0.06, bd), bc * CF(0, 0.03, 0), basket)
						for _, sz in { -1, 1 } do
							K:box("ShellBasketSide", V3(bw, 0.4, 0.05), bc * CF(0, 0.2, sz * bd / 2), basket)
						end
						for _, sx in { -1, 1 } do
							K:box("ShellBasketSide", V3(0.05, 0.4, bd), bc * CF(sx * bw / 2, 0.2, 0), basket)
						end
						shellPile(K, bc * CF(0, 0.04, 0), bw, bd, kinds[(k - 1) % #kinds + 1], seed + k, if hi then 14 else 7)
					end
				else
					shellPile(K, bottom, tw - 0.6, td - 0.6, "abalone", seed, if hi then 8 else 4)
					shellPile(K, bottom * CF(hw * 0.4, 0, 0), tw * 0.4, td - 0.6, "conch", seed + 3, if hi then 6 else 3)
					for k = 1, 2 do
						local y = gTop + 0.7 + k * 0.4
						local z = -hd + 0.6 + k * 0.5
						local parts = swimmer(K, tcf * CF(0, y, z), "rockfish", 0.85, hi)
						table.insert(swim, { parts = parts, tcf = tcf, y = y, z = z, A = hw - 0.9, spd = 0.22 + k * 0.05, ph = k * 2.1, bob = 0.05 })
					end
				end
			elseif content == "crab" then
				local n = if hi then 3 else 2
				for k = 1, n do
					local x = -hw + 1.2 + (tw - 2.4) * (k - 0.5) / n
					local yaw = (rnd(seed, k) - 0.5) * 1.2
					local base = bottom * CF(x, 0, (rnd(seed, k + 2) - 0.5) * 0.6) * ANG(0, yaw + PI / 2, 0)
					if lower then
						crab(K, base, 1.0 + rnd(seed, k + 4) * 0.2, if k == 2 then "red" else "snow", hi)
					else
						if k == n and hi then
							lobster(K, base, 0.9, hi)
						else
							crab(K, base, 1.25, "king", hi)
						end
					end
				end
			elseif content == "squid" then
				local n = if hi then 4 else 2
				if lower then
					flatfish(K, bottom * CF(-hw + 1.2, 0, 0) * ANG(0, 0.4, 0), 1.0, hi, false)
					flatfish(K, bottom * CF(hw - 1.4, 0, 0.2) * ANG(0, -0.3, 0), 0.9, hi, true)
				end
				for k = 1, n do
					local y = gTop + 0.6 + ((k * 0.41) % 1) * math.max(0.4, (y1 - gTop) - 1.1)
					local z = -hd + 0.5 + ((k * 0.57) % 1) * (td - 1.0)
					local parts = squid(K, tcf * CF(0, y, z), 1.0, hi)
					table.insert(swim, { parts = parts, tcf = tcf, y = y, z = z, A = hw - 1.1, spd = 0.3 + rnd(seed, k) * 0.2, ph = rnd(seed, k + 5) * 6.28, bob = 0.1, squid = true })
				end
			end
		end)
	end
	-- 애니메이션: 헤엄 + 기포
	local state = c.tankState
	Interact.anim(K, function(tt)
		for _, f in swim do
			local ph = tt * f.spd + f.ph
			local x = math.sin(ph) * f.A
			local v = math.cos(ph)
			local yaw = math.acos(math.clamp(v * 3, -1, 1))
			local y = f.y + math.sin(tt * 1.1 + f.ph) * f.bob
			local base = K.cf * f.tcf * CF(x, y, f.z) * ANG(0, yaw, 0)
			for _, pp in f.parts do
				if pp.p.Parent then
					pp.p.CFrame = base * pp.off
				end
			end
		end
		local on = state.air
		for _, b in bubbles do
			if b.p.Parent then
				if on then
					local fr = (tt * 0.45 + b.k / b.n) % 1
					b.p.Transparency = 0.4 + fr * 0.2
					b.p.CFrame = K.cf * b.base * CF(math.sin(tt * 3 + b.k) * 0.04, 0.2 + fr * b.h, 0)
				else
					b.p.Transparency = 1
				end
			end
		end
	end)
	at(K, "tank", nil, nil, V3(cx, topY, cz))
end

-- 활어 손질 카운터 (뒷벽 · 카운터 위) -------------------------------------------------------------------------
local function knifeSet(c: any, dcf: CFrame, w: number)
	local K = c.K
	K:plate("KnifeMagnet", w, 0.2, 0.08, dcf, L.black)
	local n = math.max(3, math.min(6, math.floor(w / 0.42)))
	for i = 1, n do
		local x = -w / 2 + w * (i - 0.5) / n
		local long = (i % 2 == 1)
		local bl = if long then 1.25 else 0.8
		local bw = if long then 0.13 else 0.24
		K:plate("KnifeBlade", bw, bl, 0.02, dcf * CF(x, -0.12 - bl / 2, 0.08), L.of(214, 218, 222, M.Metal, { r = 0.3 }))
		K:plate("KnifeSpine", 0.025, bl, 0.03, dcf * CF(x - bw / 2 + 0.012, -0.12 - bl / 2, 0.08), L.of(160, 164, 170, M.Metal))
		K:vcyl("KnifeHandle", 0.5, 0.1, dcf * CF(x, 0.15, 0.13), if long then L.of(196, 170, 120, M.Wood) else L.black)
	end
end

local function uvSterilizer(c: any, dcf: CFrame)
	-- 벽걸이 자외선 칼 · 도마 소독기: 스테인리스 함 + 유리문 (안에 칼 · 도마가 보임) + 위 보라 램프 띠 + 전원 표시
	local K = c.K
	local body = L.of(214, 218, 222, M.Metal, { r = 0.12 })
	K:plate("UVCabinet", 1.5, 1.7, 0.55, dcf, body)
	K:plate("UVInner", 1.3, 1.25, 0.02, dcf * CF(0, -0.08, 0.5), L.of(70, 64, 120, M.SmoothPlastic))
	K:plate("UVLampBar", 1.24, 0.07, 0.04, dcf * CF(0, 0.5, 0.46), L.neon(rgb(150, 110, 255)))
	for i = 1, 4 do
		local x = -0.48 + (i - 1) * 0.22
		K:plate("UVKnife", 0.1, 0.62, 0.02, dcf * CF(x, -0.12, 0.42), L.of(206, 210, 216, M.Metal, { r = 0.2 }))
		K:plate("UVKnifeHandle", 0.07, 0.28, 0.04, dcf * CF(x, 0.3, 0.42), if i % 2 == 0 then L.black else L.of(196, 170, 120, M.Wood))
	end
	K:plate("UVBoard", 0.42, 0.9, 0.06, dcf * CF(0.4, -0.12, 0.38), L.of(236, 232, 222))
	-- 유리문 + 알루 문틀 + 손잡이
	K:plate("UVDoorGlass", 1.36, 1.32, 0.02, dcf * CF(0, -0.06, 0.55), { c = rgb(190, 180, 255), m = M.Glass, t = 0.55 })
	for _, sy in { -1, 1 } do
		K:plate("UVDoorFrame", 1.42, 0.06, 0.04, dcf * CF(0, -0.06 + sy * 0.68, 0.55), L.alu)
	end
	for _, sx in { -1, 1 } do
		K:plate("UVDoorFrame", 0.06, 1.42, 0.04, dcf * CF(sx * 0.7, -0.06, 0.55), L.alu)
	end
	K:plate("UVHandle", 0.06, 0.4, 0.08, dcf * CF(0.6, -0.06, 0.59), L.chrome)
	-- 위 조작부: 이름 띠 + 전원 LED + 타이머 다이얼
	ktext(K, "UVLabel", 1.0, 0.18, dcf * CF(-0.15, 0.76, 0.551), "자외선 살균 소독기", { fg = rgb(30, 60, 120), d = 0.005 })
	K:plate("UVPower", 0.06, 0.06, 0.02, dcf * CF(0.52, 0.76, 0.55), L.neon(rgb(80, 255, 120)))
	K:cyl("UVDial", 0.04, 0.12, dcf * CF(0.64, 0.76, 0.57) * ANG(0, PI / 2, 0), L.black)
end

local function platesStack(K: any, base: CFrame, dia: number, n: number, look: any)
	for i = 1, n do
		K:disc("PlateStack", dia, 0.05, base * CF(0, 0.03 + (i - 1) * 0.06, 0), look)
	end
end

local function sauceBottle(K: any, base: CFrame, kind: string)
	if kind == "chojang" then
		K:vcyl("ChojangBottle", 0.5, 0.24, base * CF(0, 0.25, 0), L.of(200, 36, 30, M.Plastic))
		K:vcyl("ChojangCap", 0.12, 0.16, base * CF(0, 0.56, 0), L.of(240, 240, 236, M.Plastic))
		K:vcyl("ChojangTip", 0.1, 0.05, base * CF(0, 0.66, 0), L.of(240, 240, 236, M.Plastic))
	elseif kind == "soy" then
		K:vcyl("SoyBottle", 0.46, 0.2, base * CF(0, 0.23, 0), { c = rgb(40, 24, 18), m = M.Glass, t = 0.15 })
		K:vcyl("SoyCap", 0.08, 0.14, base * CF(0, 0.5, 0), L.of(200, 30, 30, M.Plastic))
	elseif kind == "wasabi" then
		K:cyl("WasabiTube", 0.42, 0.12, base * CF(0, 0.06, 0), L.of(90, 160, 70, M.Plastic))
		K:cyl("WasabiCap", 0.08, 0.1, base * CF(0.24, 0.06, 0), L.white)
	elseif kind == "sesame" then
		K:vcyl("OilBottle", 0.5, 0.2, base * CF(0, 0.25, 0), { c = rgb(180, 120, 40), m = M.Glass, t = 0.2 })
		K:vcyl("OilCap", 0.08, 0.12, base * CF(0, 0.54, 0), L.of(30, 120, 60, M.Plastic))
	end
end

local function scale(K: any, base: CFrame)
	K:box("ScaleBase", V3(1.0, 0.24, 0.8), base * CF(0, 0.12, 0), L.of(236, 236, 232, M.Plastic))
	K:box("ScalePan", V3(0.9, 0.04, 0.7), base * CF(0, 0.27, -0.02), L.of(206, 210, 214, M.Metal, { r = 0.2 }))
	K:box("ScalePanel", V3(0.9, 0.12, 0.06), base * CF(0, 0.16, 0.42), L.of(60, 64, 70, M.Plastic))
	K:text("ScaleLED", 0.5, 0.09, base * CF(-0.15, 0.16, 0.452), "1.250 kg", { fg = rgb(90, 255, 120), glow = 1.4, font = F.Arcade, d = 0.005 })
end

local function sashimiPlatter(c: any, base: CFrame)
	local K = c.K
	K:slab("PlatterBoard", 1.5, 1.0, 0.08, 0.3, base * CF(0, 0.04, 0), L.of(30, 30, 32, M.SmoothPlastic))
	K:ell("RadishMound", V3(0.6, 0.18, 0.4), base * CF(-0.35, 0.14, -0.15), L.of(248, 248, 244, M.Fabric))
	K:ell("Kelp", V3(0.32, 0.03, 0.46), base * CF(-0.35, 0.1, 0.2), L.of(40, 80, 50))
	local cols = { rgb(250, 244, 236), rgb(236, 120, 110), rgb(250, 244, 236), rgb(244, 160, 140), rgb(250, 244, 236) }
	for i = 1, (if c.hi then 7 else 4) do
		local a = -0.15 + i * 0.12
		K:ell("SashimiSlice", V3(0.34, 0.05, 0.16), base * CF(0.05 + i * 0.07, 0.12 + i * 0.004, -0.25 + i * 0.07) * ANG(0, a, 0.25), col(cols[(i - 1) % #cols + 1]))
	end
	K:ell("PerillaLeaf", V3(0.3, 0.02, 0.24), base * CF(0.45, 0.1, 0.25), L.of(56, 110, 50))
	K:disc("LemonSlice", 0.16, 0.03, base * CF(0.25, 0.16, 0.32) * ANG(0.3, 0, 0), L.of(240, 220, 80))
	K:ball("WasabiDab", 0.1, base * CF(0.55, 0.12, 0.05), L.of(130, 180, 80))
end

-- 위생 앞치마 걸이 (PVC 앞치마 2 + 고무장갑 + 토시) + 아래 바닥에 고무 장화
local function apronStation(c: any, dcf: CFrame, bootsCf: CFrame?)
	local K = c.K
	K:plate("ApronRail", 1.6, 0.12, 0.08, dcf * CF(0, 1.35, 0), L.of(196, 200, 204, M.Metal))
	local colors = { pickOf({ rgb(236, 120, 40), rgb(40, 110, 190), rgb(60, 140, 90) }, c.seed, 51), rgb(34, 36, 44) }
	for i, cc in colors do
		local x = -0.4 + (i - 1) * 0.8
		local z = 0.06 + i * 0.04
		local look = col(cc, M.Plastic)
		K:cyl("ApronHook", 0.2, 0.06, dcf * CF(x, 1.3, 0.14) * ANG(0, PI / 2, 0), L.chrome)
		-- 가슴판 (위가 좁음) + 치마 (넓고 길게) + 목끈 고리
		K:plate("ApronBib", 0.46, 0.6, 0.03, dcf * CF(x, 0.8, z), look)
		K:plate("Apron", 0.8, 2.0, 0.03, dcf * CF(x, -0.5, z), look)
		K:seg("ApronStrap", (dcf * CF(x - 0.2, 1.08, z + 0.02)).Position, (dcf * CF(x, 1.3, 0.14)).Position, 0.035, look)
		K:seg("ApronStrap", (dcf * CF(x + 0.2, 1.08, z + 0.02)).Position, (dcf * CF(x, 1.3, 0.14)).Position, 0.035, look)
	end
	-- 고무장갑 (노랑 · 빨강) 한 켤레를 고리에
	K:cyl("GloveHook", 0.24, 0.05, dcf * CF(0.72, 1.3, 0.2) * ANG(0, PI / 2, 0), L.chrome)
	K:ell("RubberGloveHang", V3(0.22, 0.7, 0.08), dcf * CF(0.68, 0.95, 0.26) * ANG(0, 0, 0.12), L.of(244, 196, 40, M.Rubber))
	K:ell("RubberGloveHang", V3(0.22, 0.66, 0.08), dcf * CF(0.76, 0.93, 0.32) * ANG(0, 0, -0.1), L.of(244, 196, 40, M.Rubber))
	if bootsCf then
		for _, sx in { -1, 1 } do
			local b = bootsCf * CF(sx * 0.24, 0, 0)
			local boot = L.of(28, 30, 34, M.Rubber)
			K:box("BootSole", V3(0.34, 0.12, 0.72), b * CF(0, 0.06, 0.08), L.of(240, 200, 40, M.Rubber))
			K:box("BootFoot", V3(0.32, 0.3, 0.6), b * CF(0, 0.26, 0.1), boot)
			K:vcyl("BootShaft", 0.95, 0.34, b * CF(0, 0.8, -0.08), boot)
			K:disc("BootTopBand", 0.36, 0.06, b * CF(0, 1.25, -0.08), L.of(240, 200, 40, M.Rubber))
		end
	end
end

local function kitchen(c: any)
	local K, V, th = c.K, c.V, c.th
	local g = V.counters[1]
	if not g then
		return
	end
	local alongX = (g.max.X - g.min.X) >= (g.max.Z - g.min.Z)
	local againstBack = alongX and (g.min.Z - V.z0) < 0.8
	local topY = g.y
	if againstBack then
		local u0, u1 = g.min.X + 0.15, g.max.X - 0.15
		-- 뒷벽 타일 (카운터 위 ~ 6.3)
		local yTop = math.min(6.4, V.H - 3)
		K:free(function()
			for _, s in finishSpans(V, "back", topY + 0.05, yTop, 0.3) do
				local a, b = math.max(s[1], u0 - 0.15), math.min(s[2], u1 + 0.15)
				if b - a > 0.8 then
					Props.wallTiles(K, "back", a, b, topY, yTop, { look = th.splash, grout = L.of(210, 212, 210), tw = 0.9, th = 0.45 })
					K:plate("SplashCap", b - a, 0.1, 0.06, V:wall("back", (a + b) / 2, yTop, 0.0), L.of(196, 200, 204, M.Metal))
				end
			end
		end)
		-- 칼 자석 걸이 (도마 위) · 자외선 소독기 · 선반
		local board = nil
		for _, r in V.byName.CuttingBoard or {} do
			if r.c.X > g.min.X - 0.5 and r.c.X < g.max.X + 0.5 then
				board = r
			end
		end
		local bx = if board then board.c.X else (u0 + u1) / 2
		if th.kind ~= "sushi" then
			local wn, u, w = findWall(K, { "back" }, 1.6, 2.4, topY + 1.2, topY + 2.6, bx, 0.6)
			if wn and u and w then
				knifeSet(c, V:wall("back", u, topY + 2.45, WALL_OFF), w)
			end
			local wn2, u2 = findWall(K, { "back" }, 1.5, 1.5, topY + 0.6, topY + 2.3, bx + 3.2, 0.6)
			if wn2 and u2 then
				uvSterilizer(c, V:wall("back", u2, topY + 1.45, WALL_OFF))
			end
		end
		-- 스텐 선반 (6.6) + 접시 · 소스병
		local shY = math.min(6.7, V.H - 2.4)
		local spans = freeSpans(K, "back", shY - 0.6, shY + 1.0, 1.2)
		for _, s in spans do
			local a, b = math.max(s[1], u0), math.min(s[2], u1)
			if b - a >= 2.4 then
				local w = math.min(b - a, 7)
				local u = (a + b) / 2
				claim(K, "back", u - w / 2, u + w / 2, shY - 0.6, shY + 1.0)
				local dcf = V:wall("back", u, shY, 0.0)
				local at2 = Props.shelf(K, dcf, w, { depth = 0.9, look = L.of(206, 210, 214, M.Metal, { r = 0.1 }), bracket = L.of(170, 174, 178, M.Metal), thick = 0.08 })
				local n = math.floor((w - 0.4) / 0.6)
				for i = 1, n do
					local x = -w / 2 + 0.3 + (w - 0.6) * (i - 0.5) / n
					local base = at2 * CF(x, 0, -0.05)
					local pickK = (i + c.seed) % 6
					if th.kind == "sushi" then
						if pickK % 2 == 0 then
							platesStack(K, base, 0.5, 4, L.of(30, 30, 32))
						else
							Props.row(K, base * CF(0, 0, 0), 0.5, "bottles", { n = 1, colors = { rgb(230, 230, 220), rgb(40, 60, 40) }, seed = i })
						end
					elseif pickK == 0 or pickK == 3 then
						platesStack(K, base, 0.55, 5, if pickK == 0 then L.white else L.of(30, 30, 32))
					elseif pickK == 1 then
						sauceBottle(K, base * CF(-0.13, 0, 0), "chojang")
						sauceBottle(K, base * CF(0.13, 0, 0), "chojang")
					elseif pickK == 2 then
						sauceBottle(K, base * CF(-0.12, 0, 0), "soy")
						sauceBottle(K, base * CF(0.14, 0, 0), "sesame")
					elseif pickK == 4 then
						K:box("PackBox", V3(0.5, 0.4, 0.5), base * CF(0, 0.2, 0), L.of(244, 244, 240, M.Plastic))
						K:box("PackBoxLid", V3(0.52, 0.06, 0.52), base * CF(0, 0.43, 0), L.of(220, 220, 214, M.Plastic))
					else
						K:vcyl("RiceJar", 0.5, 0.4, base * CF(0, 0.25, 0), { c = rgb(232, 236, 236), m = M.Glass, t = 0.4 })
						K:vcyl("RiceJarFill", 0.3, 0.34, base * CF(0, 0.16, 0), L.of(200, 50, 30))
					end
				end
				break
			end
		end
		-- 위생 앞치마 걸이 (카운터 끝 옆벽 가까이)
	end
	-- 카운터 위 소품 (도마 · 칼 · keep 피해서)
	local top = g.top or g.body
	if not top then
		return
	end
	local tmn, tmx = top.min, top.max
	-- 맵 칼은 새 사시미 칼로 (같은 자리)
	for _, r in V.byName.Knife or {} do
		if r.c.X > tmn.X - 0.3 and r.c.X < tmx.X + 0.3 and r.c.Z > tmn.Z - 0.3 and r.c.Z < tmx.Z + 0.3 then
			hideRec(K, r)
			local along = r.size.X >= r.size.Z
			local kcf = CF(r.c.X, r.min.Y + 0.015, r.c.Z) * (if along then CF() else ANG(0, PI / 2, 0))
			K:free(function()
				local len = math.max(r.size.X, r.size.Z)
				K:box("SashimiKnife", V3(len * 0.68, 0.02, 0.13), kcf * CF(len * 0.14, 0, 0), L.of(220, 224, 228, M.Metal, { r = 0.3 }))
				K:cyl("SashimiKnifeHandle", len * 0.3, 0.09, kcf * CF(-len * 0.34, 0.03, 0), L.of(196, 170, 120, M.Wood))
				K:cyl("SashimiKnifeFerrule", 0.06, 0.1, kcf * CF(-len * 0.19, 0.03, 0), L.black)
			end)
		end
	end
	-- 카운터 끝면 (방 가운데 쪽) 관계자 외 출입금지 스티커
	if alongX and g.body then
		local bmn, bmx = g.body.min, g.body.max
		local endX, dir = bmx.X, 1
		if math.abs(bmn.X) < math.abs(bmx.X) then
			endX, dir = bmn.X, -1
		end
		local pos = V3(endX + dir * 0.012, math.min(2.0, topY - 0.9), (bmn.Z + bmx.Z) / 2)
		local zAx = V3(dir, 0, 0)
		local dcfS = CFrame.fromMatrix(pos, Vector3.yAxis:Cross(zAx), Vector3.yAxis, zAx)
		local wS = math.min(1.3, (bmx.Z - bmn.Z) - 0.3)
		if wS > 0.6 then
			K:free(function()
				ktext(K, "StaffOnly", wS, 0.5, dcfS, "관계자 외\n출입금지", { fg = WHITE, bg = rgb(200, 30, 36), font = F.GothamBlack, d = 0.01 })
			end)
		end
	end
	if not alongX then
		return
	end
	local busy: { { number } } = {}
	for _, s in V.solid do
		if s.max.Y > topY - 0.1 and s.min.Y < topY + 1 and s.max.X > tmn.X and s.min.X < tmx.X and s.max.Z > tmn.Z and s.min.Z < tmx.Z then
			table.insert(busy, { s.min.X - 0.25, s.max.X + 0.25 })
		end
	end
	local zBack = if againstBack then tmn.Z + 0.6 else (tmn.Z + tmx.Z) / 2
	local items: { any } = {}
	if th.kind == "sushi" then
		items = {}
	elseif th.kind == "jjim" then
		items = { { w = 1.9, kind = "pot" }, { w = 1.9, kind = "pot" }, { w = 1.7, kind = "sink" }, { w = 1.2, kind = "sauce" }, { w = 1.1, kind = "scale" }, { w = 1.0, kind = "wrap" } }
	elseif th.kind == "crab" then
		items = { { w = 1.1, kind = "scale" }, { w = 1.7, kind = "sink" }, { w = 1.7, kind = "platter" }, { w = 1.2, kind = "sauce" }, { w = 1.9, kind = "pot" }, { w = 1.0, kind = "boxes" } }
	else
		items = { { w = 1.1, kind = "scale" }, { w = 1.7, kind = "sink" }, { w = 1.7, kind = "platter" }, { w = 1.2, kind = "sauce" }, { w = 1.3, kind = "bowl" }, { w = 1.0, kind = "boxes" }, { w = 1.0, kind = "wrap" }, { w = 1.0, kind = "gloves" }, { w = 1.1, kind = "plates" } }
	end
	if th.kind == "jjim" or th.kind == "crab" then
		table.insert(items, { w = 1.3, kind = "bowl" })
		table.insert(items, { w = 1.1, kind = "plates" })
	end
	local cursor = tmn.X + 0.3
	local steamSrc: { any } = {}
	for _, it in items do
		local placed = false
		while cursor + it.w <= tmx.X - 0.25 do
			local a, b = cursor, cursor + it.w
			local hit = false
			for _, bz in busy do
				if a < bz[2] and b > bz[1] then
					hit = true
					cursor = bz[2] + 0.05
					break
				end
			end
			if not hit then
				local cx = (a + b) / 2
				local isPot = it.kind == "pot"
				local base = CF(cx, topY, if isPot then zBack + 0.3 else zBack)
				local h = if isPot then 1.6 elseif it.kind == "sink" then 1.0 else 0.8
				if clearAt(K, base * CF(0, h / 2 + 0.02, 0), V3(it.w, h, if isPot then 1.6 elseif it.kind == "bowl" then 1.3 else 1.0)) then
					placed = true
					cursor = b + 0.2
					-- 놓은 자리는 다음 품목 (처음부터 다시 찾을 때 포함) 이 피함
					table.insert(busy, { a - 0.1, b + 0.1 })
					if it.kind == "scale" then
						scale(K, base)
					elseif it.kind == "platter" then
						sashimiPlatter(c, base)
					elseif it.kind == "sauce" then
						sauceBottle(K, base * CF(-0.4, 0, 0), "chojang")
						sauceBottle(K, base * CF(-0.1, 0, 0), "soy")
						sauceBottle(K, base * CF(0.2, 0, 0.1), "wasabi")
						sauceBottle(K, base * CF(0.42, 0, -0.1), "sesame")
					elseif it.kind == "boxes" then
						for k = 1, 3 do
							K:box("TakeoutTray", V3(0.9, 0.12, 0.62), base * CF(0, 0.07 + (k - 1) * 0.13, 0), L.of(246, 246, 242, M.Plastic))
						end
						K:box("TakeoutLid", V3(0.92, 0.04, 0.64), base * CF(0, 0.45, 0), { c = rgb(236, 240, 240), m = M.Glass, t = 0.4 })
					elseif it.kind == "wrap" then
						K:box("WrapBox", V3(0.9, 0.2, 0.24), base * CF(0, 0.1, 0), L.of(40, 120, 70))
						K:cyl("WrapRoll", 0.86, 0.12, base * CF(0, 0.24, 0.03), { c = rgb(236, 244, 246), m = M.Glass, t = 0.35 })
					elseif it.kind == "bowl" then
						-- 스텐 볼 (무채 · 깻잎) + 집게
						K:disc("PrepBowl", 1.1, 0.34, base * CF(0, 0.17, 0), L.of(210, 214, 218, M.Metal, { r = 0.2 }))
						K:disc("PrepBowlRim", 1.18, 0.04, base * CF(0, 0.35, 0), L.chrome)
						K:ell("RadishShred", V3(0.86, 0.22, 0.86), base * CF(0, 0.32, 0), L.of(248, 248, 242, M.Fabric))
						K:ell("PerillaPile", V3(0.36, 0.08, 0.3), base * CF(0.18, 0.43, 0.12), L.of(56, 112, 52))
						K:box("Tongs", V3(0.7, 0.03, 0.07), base * CF(0.2, 0.47, -0.1) * ANG(0, 0.5, 0.2), L.chrome)
					elseif it.kind == "plates" then
						-- 회 접시 (흰 타원 플라스틱) 더미 + 초장 종지
						for k = 1, 5 do
							K:slab("SashimiPlate", 0.95, 0.7, 0.05, 0.3, base * CF(0, 0.03 + (k - 1) * 0.055, 0) * ANG(0, (k % 2) * 0.05, 0), L.of(246, 246, 242, M.SmoothPlastic))
						end
						for k = 1, 3 do
							K:disc("SauceDish", 0.26, 0.08, base * CF(-0.3 + k * 0.17, 0.33 + (k - 1) * 0.08, 0.15), L.of(240, 240, 236))
						end
						K:disc("SauceDishFill", 0.2, 0.02, base * CF(0.21, 0.54, 0.15), L.of(196, 40, 30))
					elseif it.kind == "gloves" then
						K:box("GloveBox", V3(0.7, 0.3, 0.42), base * CF(0, 0.15, 0), L.of(240, 240, 236))
						K:box("GloveBoxBand", V3(0.72, 0.1, 0.44), base * CF(0, 0.2, 0), L.of(40, 110, 190))
						K:ell("RubberGlove", V3(0.5, 0.06, 0.22), base * CF(0.05, 0.33, 0.05) * ANG(0, 0.3, 0), L.of(240, 190, 40, M.Rubber))
					elseif it.kind == "sink" then
						-- 상판 매립 스테인리스 싱크 + 벽 쪽 구즈넥 수전 + 수세미
						K:box("SinkRim", V3(1.6, 0.03, 1.0), base * CF(0, 0.015, 0), L.of(214, 218, 222, M.Metal, { r = 0.2 }))
						K:box("SinkBowl", V3(1.36, 0.035, 0.78), base * CF(0, 0.02, 0), L.of(110, 114, 118, M.Metal))
						K:disc("SinkDrain", 0.16, 0.04, base * CF(0.3, 0.03, 0), L.of(60, 60, 62, M.Metal))
						local p0 = (base * CF(0, 0.03, -0.45)).Position
						local p1 = (base * CF(0, 0.95, -0.45)).Position
						local p2 = (base * CF(0, 0.95, -0.1)).Position
						K:seg("Faucet", p0, p1, 0.08, L.chrome)
						K:ball("FaucetBend", 0.09, CF(p1), L.chrome)
						K:seg("Faucet", p1, p2, 0.07, L.chrome)
						K:seg("FaucetSpout", p2, (base * CF(0, 0.78, -0.1)).Position, 0.06, L.chrome)
						K:box("FaucetLever", V3(0.3, 0.04, 0.06), base * CF(0.08, 0.55, -0.45), L.chrome)
						K:box("Scrubber", V3(0.26, 0.1, 0.18), base * CF(0.62, 0.05, -0.32), L.of(90, 170, 80, M.Fabric))
					elseif it.kind == "pot" then
						local burner = L.of(46, 48, 52, M.Metal)
						K:box("GasBurner", V3(1.5, 0.3, 1.0), base * CF(0, 0.15, 0), burner)
						K:disc("BurnerKnob", 0.16, 0.08, base * CF(0.5, 0.15, 0.52) * ANG(PI / 2, 0, 0), L.black)
						K:disc("Pot", 1.4, 0.9, base * CF(0, 0.3 + 0.45, 0), L.of(206, 200, 186, M.Metal, { r = 0.12 }))
						K:disc("PotRim", 1.46, 0.06, base * CF(0, 1.2, 0), L.of(220, 214, 200, M.Metal))
						K:disc("PotLid", 1.38, 0.08, base * CF(0, 1.27, 0), L.of(196, 190, 176, M.Metal))
						K:ball("PotLidKnob", 0.18, base * CF(0, 1.36, 0), L.black)
						for _, sx in { -1, 1 } do
							K:box("PotHandle", V3(0.2, 0.08, 0.3), base * CF(sx * 0.78, 1.1, 0), L.black)
						end
						table.insert(steamSrc, base * CF(0, 1.38, 0))
					end
					break
				else
					cursor += 0.3
				end
			end
		end
		if not placed then
			cursor = tmn.X + 0.3
		end
	end
	c.steamSrc = steamSrc
end

-- 김 (냄비 · 찜기): 반투명 구 3개가 오르며 흩어짐
local function steam(c: any, srcs: { CFrame })
	local K = c.K
	if #srcs == 0 then
		return
	end
	local puffs = {}
	for i, s in srcs do
		for k = 1, (if c.hi then 4 else 2) do
			local p = K:ball("SteamPuff", 0.5, s * CF(0, 0.3 * k, 0), { c = rgb(250, 250, 250), m = M.SmoothPlastic, t = 0.75 })
			table.insert(puffs, { p = p, s = s, k = k, ph = i * 0.37 })
		end
	end
	Interact.anim(K, function(t)
		for _, pf in puffs do
			if pf.p.Parent then
				local fr = (t * 0.35 + pf.k * 0.25 + pf.ph) % 1
				local sz = 0.35 + fr * 0.9
				pf.p.Size = V3(sz, sz, sz)
				pf.p.Transparency = 0.6 + fr * 0.38
				pf.p.CFrame = K.cf * pf.s * CF(math.sin(t + pf.k) * 0.12 * fr, 0.1 + fr * 1.6, 0)
			end
		end
	end)
end

-- 벽 부착물 --------------------------------------------------------------------------------------------------
-- 라이트 박스 메뉴판 (글자판 수를 아끼려고 열마다 여러 줄 라벨 하나: 줄 간격을 맞춰 행이 정렬됨)
local function menuLightbox(c: any, dcf: CFrame, w: number, h: number)
	local K, th, V = c.K, c.th, c.V
	local menu = th.menu
	local dark = (th.variant == "wood" or th.kind == "sushi" or th.variant == "crab")
	local bg = if dark then rgb(30, 26, 22) else rgb(252, 252, 248)
	local fg = if dark then rgb(246, 238, 220) else th.ink
	local priceC = if dark then rgb(240, 196, 90) else th.accent2
	K:plate("MenuCase", w + 0.24, h + 0.24, 0.22, dcf, L.alu)
	K:plate("MenuCaseEdge", w + 0.3, 0.06, 0.24, dcf * CF(0, -(h + 0.24) / 2, 0), L.darkAlu)
	litFace(K, "MenuFace", w, h, dcf * CF(0, 0, 0.22), bg, nil, nil, 0.95, 0.02)
	local z = 0.245
	local hh = math.min(0.8, h * 0.2)
	local title = shortName(V, "") .. "  " .. menu.title
	if charCount(title) > 18 then
		title = menu.title
	end
	litFace(K, "MenuHeader", w, hh, dcf * CF(0, h / 2 - hh / 2, z), th.accent, title, WHITE, 1.05, 0.012)
	local foot = 0.42
	litFace(K, "MenuFooter", w, foot, dcf * CF(0, -h / 2 + foot / 2, z), th.accent:Lerp(rgb(0, 0, 0), 0.25), menu.drinks, WHITE, 1.05, 0.012)
	-- 왼쪽: 주메뉴 표 (이름 + 小中大), 오른쪽: 식사 · 별미
	local leftW = w * 0.62
	local rightW = w - leftW - 0.3
	local x0 = -w / 2 + 0.2
	local cols = menu.cols
	local nameW = leftW * (if #cols >= 3 then 0.42 else 0.6)
	local colW = (leftW - nameW) / #cols
	local gapTop = 0.1
	local headH = 0.34
	local bodyTop = h / 2 - hh - gapTop
	local bodyH = h - hh - foot - gapTop * 2 - headH - 0.06
	local zc = dcf * CF(0, 0, z + 0.004)
	-- 열 제목 줄
	local heads = { { x = x0 + nameW / 2, w = nameW, text = if th.kind == "hoe" then "활어회" else "메뉴", fg = th.accent, font = F.GothamBlack } }
	for j, cn in cols do
		table.insert(heads, { x = x0 + nameW + colW * (j - 0.5), w = colW, text = cn, fg = th.accent, font = F.GothamBlack })
	end
	textColumns(K, "MenuColHead", zc * CF(0, bodyTop - headH / 2, 0), headH, 1, heads, 1.05)
	K:plate("MenuRule", leftW, 0.035, 0.01, dcf * CF(x0 + leftW / 2, bodyTop - headH - 0.02, z), { c = th.accent, m = M.SmoothPlastic })
	-- 본문 열
	local nameLines, priceLines = {}, {}
	for j = 1, #cols do
		priceLines[j] = {}
	end
	for _, it in menu.main do
		table.insert(nameLines, it[1])
		for j = 1, #cols do
			local v = it[j + 1]
			if #it == 2 then
				v = if j == math.ceil(#cols / 2) then it[2] else " "
			end
			table.insert(priceLines[j], v or " ")
		end
	end
	local yb = bodyTop - headH - 0.06 - bodyH / 2
	local body = { { x = x0 + nameW / 2, w = nameW, text = table.concat(nameLines, "\n"), fg = fg, font = F.GothamBold, align = "Left" } }
	for j = 1, #cols do
		table.insert(body, { x = x0 + nameW + colW * (j - 0.5), w = colW, text = table.concat(priceLines[j], "\n"), fg = priceC, font = F.GothamBold })
	end
	textColumns(K, "MenuRows", zc * CF(0, yb, 0), bodyH, #menu.main, body, 1.0)
	if c.hi then
		local rh = bodyH / #menu.main
		for i = 1, #menu.main - 1 do
			K:plate("MenuRowLine", leftW, 0.012, 0.006, dcf * CF(x0 + leftW / 2, yb + bodyH / 2 - rh * i, z), { c = fg:Lerp(bg, 0.8), m = M.SmoothPlastic })
		end
	end
	-- 오른쪽 칸
	local rx0 = x0 + leftW + 0.3
	K:plate("MenuDivider", 0.035, h - hh - foot - 0.2, 0.01, dcf * CF(rx0 - 0.15, (foot - hh) / 2, z), { c = th.accent, m = M.SmoothPlastic })
	textColumns(K, "MenuSideHead", zc * CF(0, bodyTop - headH / 2, 0), headH, 1, { { x = rx0 + rightW / 2, w = rightW, text = menu.sideTitle, fg = th.accent, font = F.GothamBlack } }, 1.05)
	local sN, sP = {}, {}
	for _, it in menu.side do
		table.insert(sN, it[1])
		table.insert(sP, it[2])
	end
	local n = math.max(#menu.side, #menu.main)
	while #sN < n do
		table.insert(sN, " ")
		table.insert(sP, " ")
	end
	textColumns(K, "MenuSide", zc * CF(0, yb, 0), bodyH, n, {
		{ x = rx0 + rightW * 0.33, w = rightW * 0.64, text = table.concat(sN, "\n"), fg = fg, font = F.GothamMedium, align = "Left" },
		{ x = rx0 + rightW * 0.83, w = rightW * 0.32, text = table.concat(sP, "\n"), fg = priceC, font = F.GothamBold, align = "Right" },
	}, 1.0)
	-- 라이트 박스 불빛 (예산 있을 때)
	if #K.lights < (V.maxLights or 8) - 2 then
		local glowBar = K:plate("MenuGlowBar", w, 0.05, 0.05, dcf * CF(0, h / 2 + 0.16, 0.3), L.neon(rgb(255, 250, 240)))
		K:light(glowBar, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 7, Brightness = 0.6, Angle = 110, Color = rgb(255, 246, 232) })
	end
end

-- 오늘의 시가 칠판
local function sigaBoard(c: any, dcf: CFrame, w: number, h: number)
	local K, th = c.K, c.th
	local wood = L.of(120, 84, 52, M.Wood)
	K:plate("ChalkBoard", w, h, 0.06, dcf, L.of(34, 46, 40, M.Slate))
	for _, sy in { -1, 1 } do
		K:plate("ChalkFrame", w + 0.24, 0.14, 0.12, dcf * CF(0, sy * (h / 2 + 0.05), 0), wood)
	end
	for _, sx in { -1, 1 } do
		K:plate("ChalkFrame", 0.14, h + 0.2, 0.12, dcf * CF(sx * (w / 2 + 0.05), 0, 0), wood)
	end
	K:plate("ChalkTray", w * 0.8, 0.06, 0.3, dcf * CF(0, -h / 2 - 0.12, 0), wood)
	K:cyl("Chalk", 0.3, 0.06, dcf * CF(-w * 0.2, -h / 2 - 0.06, 0.18), L.white)
	K:cyl("Chalk", 0.24, 0.06, dcf * CF(-w * 0.1, -h / 2 - 0.06, 0.2), L.of(250, 220, 90))
	local lines: { string }
	if th.tank == "crab" then
		lines = { "영덕 대게 (특大) · 시가", "러시아 대게 · kg 89,000", "킹크랩 (3kg 이상) · kg 135,000", "홍게 · kg 45,000", "※ 찜 · 손질 무료" }
	elseif th.tank == "shell" then
		lines = { "고성 가리비 · kg 18,000", "보령 키조개 · 1미 8,000", "완도 전복 · 1미 5,000", "백합 · 동죽 · 시가", "※ 오늘 조개 아주 좋아요" }
	elseif th.tank == "squid" then
		lines = { "동해 산오징어 · 시가", "광어 · 시가", "우럭 · 시가", "※ 오징어 입고 시간 오후 4시", "※ 조기 품절 될 수 있음" }
	else
		lines = { "자연산 참돔 · 시가", "감성돔 · 시가", "돌돔 · 시가", "줄돔 · 쥐치 · 시가", "※ kg 단위 · 손질 무료" }
	end
	K:text("ChalkTitle", w * 0.8, h * 0.18, dcf * CF(0, h / 2 - h * 0.13, 0.065), "오늘의 시가", { fg = rgb(250, 226, 110), font = F.GothamBlack, d = 0.005, glow = 0.9 })
	textColumns(K, "ChalkBody", dcf * CF(0, -h * 0.1, 0.065), h * 0.62, #lines, { { x = 0, w = w * 0.86, text = table.concat(lines, "\n"), fg = rgb(240, 240, 232), font = F.GothamMedium, align = "Left" } }, 0.8)
	K:text("ChalkDate", w * 0.34, h * 0.08, dcf * CF(w * 0.3, -h / 2 + h * 0.07, 0.065), "10월 17일 (토)", { fg = rgb(250, 170, 170), font = F.GothamBold, d = 0.005, glow = 0.8 })
end

-- 원산지 표시판
local function originBoard(c: any, dcf: CFrame, w: number, h: number)
	local K, th = c.K, c.th
	K:plate("OriginBack", w + 0.1, h + 0.1, 0.05, dcf, L.of(200, 204, 206, M.Metal))
	K:plate("OriginFace", w, h, 0.06, dcf, L.of(252, 252, 250))
	local hh = h * 0.16
	ktext(K, "OriginHead", w, hh, dcf * CF(0, h / 2 - hh / 2, 0.061), "원산지 표시판", { fg = WHITE, bg = rgb(28, 120, 70), font = F.GothamBlack, d = 0.01 })
	local nl = select(2, string.gsub(th.origin, "\n", "")) + 1
	textColumns(K, "OriginBody", dcf * CF(0, -hh / 2 + 0.02, 0.061), h * 0.76, nl, { { x = 0, w = w * 0.9, text = th.origin, fg = rgb(30, 30, 34), font = F.GothamMedium, align = "Left" } })
end

-- 사진 액자 (낚시 인증 · 배 · 바다)
local function fishPhoto(c: any, dcf: CFrame, w: number, h: number, i: number)
	local K = c.K
	local fr = if i % 2 == 0 then L.of(40, 40, 42) else L.of(150, 110, 70, M.Wood)
	K:plate("PhotoBack", w, h, 0.05, dcf, L.white)
	for _, sy in { -1, 1 } do
		K:plate("PhotoFrame", w, 0.08, 0.09, dcf * CF(0, sy * (h / 2 - 0.04), 0), fr)
	end
	for _, sx in { -1, 1 } do
		K:plate("PhotoFrame", 0.08, h - 0.16, 0.09, dcf * CF(sx * (w / 2 - 0.04), 0, 0), fr)
	end
	local iw, ih = w - 0.3, h - 0.42
	local pc = dcf * CF(0, 0.08, 0.05)
	K:plate("PhotoSky", iw, ih * 0.55, 0.01, pc * CF(0, ih * 0.225, 0), col(rgb(150, 196, 230)))
	K:plate("PhotoSea", iw, ih * 0.45, 0.01, pc * CF(0, -ih * 0.275, 0), col(rgb(40, 96, 150)))
	-- 사람 (실루엣) + 물고기
	local px = (if i % 2 == 0 then -0.15 else 0.15) * iw
	K:plate("PhotoBody", iw * 0.22, ih * 0.42, 0.012, pc * CF(px, -ih * 0.24, 0.002), col(if i % 3 == 0 then rgb(220, 120, 40) else rgb(40, 50, 70)))
	wdisc(K, "PhotoHead", ih * 0.17, 0.012, pc * CF(px, ih * 0.06, 0), 0.002, col(rgb(214, 170, 130)))
	K:plate("PhotoCap", ih * 0.2, ih * 0.05, 0.014, pc * CF(px, ih * 0.13, 0), col(rgb(230, 230, 230)))
	local fishC = if i % 2 == 0 then rgb(214, 110, 110) else rgb(190, 196, 200)
	K:ell("PhotoFish", V3(iw * 0.55, ih * 0.16, 0.02), pc * CF(-px * 0.6, -ih * 0.16, 0.012), col(fishC))
	K:ell("PhotoFishTail", V3(iw * 0.1, ih * 0.16, 0.02), pc * CF(-px * 0.6 + (if px > 0 then -1 else 1) * iw * 0.28, -ih * 0.16, 0.012), col(fishC:Lerp(rgb(0, 0, 0), 0.2)))
	local caps = { "참돔 68cm · 기장 앞바다", "감성돔 52cm · 2025.11", "광어 81cm 월척!", "방어 92cm · 대마도", "우럭 55cm · 오륙도" }
	K:text("PhotoCaption", iw, 0.22, dcf * CF(0, -h / 2 + 0.2, 0.051), caps[(i + c.seed) % #caps + 1], { fg = rgb(40, 40, 40), font = F.GothamBold, d = 0.005 })
	K:plate("PhotoGlass", w - 0.16, h - 0.16, 0.01, dcf * CF(0, 0, 0.08), { c = rgb(230, 236, 240), m = M.Glass, t = 0.88, r = 0.2 })
end

-- 어탁 (먹물 물고기 탁본 액자)
local function gyotaku(c: any, dcf: CFrame, w: number, h: number)
	local K = c.K
	local fr = L.of(46, 32, 24, M.Wood)
	K:plate("GyotakuPaper", w, h, 0.05, dcf, L.of(240, 232, 212, M.Fabric))
	for _, sy in { -1, 1 } do
		K:plate("GyotakuFrame", w + 0.16, 0.1, 0.1, dcf * CF(0, sy * (h / 2 + 0.03), 0), fr)
	end
	for _, sx in { -1, 1 } do
		K:plate("GyotakuFrame", 0.1, h + 0.12, 0.1, dcf * CF(sx * (w / 2 + 0.03), 0, 0), fr)
	end
	local fc = dcf * CF(-w * 0.08, -h * 0.04, 0.05)
	local ink = col(rgb(26, 26, 28))
	K:ell("GyotakuFish", V3(w * 0.62, h * 0.36, 0.015), fc, ink)
	K:ell("GyotakuTail", V3(w * 0.14, h * 0.4, 0.015), fc * CF(-w * 0.35, 0, 0), ink)
	K:ell("GyotakuFin", V3(w * 0.34, h * 0.14, 0.015), fc * CF(-w * 0.02, h * 0.2, 0), ink)
	K:ell("GyotakuFin", V3(w * 0.12, h * 0.1, 0.015), fc * CF(-w * 0.1, -h * 0.2, 0), ink)
	wdisc(K, "GyotakuEye", h * 0.07, 0.01, fc * CF(w * 0.22, h * 0.04, 0), 0.008, col(rgb(240, 232, 212)))
	K:plate("GyotakuSeal", w * 0.07, w * 0.07, 0.01, dcf * CF(w * 0.4, -h * 0.3, 0.05), col(rgb(200, 30, 30)))
	K:text("GyotakuText", w * 0.12, h * 0.8, dcf * CF(w * 0.4, h * 0.05, 0.052), "감\n성\n돔\n52\ncm", { fg = rgb(30, 30, 30), font = F.GothamBold, d = 0.005 })
end

-- 제철 수산물 달력
local function seasonChart(c: any, dcf: CFrame, w: number, h: number)
	local K, th = c.K, c.th
	K:plate("SeasonBack", w, h, 0.04, dcf, L.white)
	local hh = h * 0.14
	ktext(K, "SeasonHead", w, hh, dcf * CF(0, h / 2 - hh / 2, 0.041), "제철 수산물 달력", { fg = WHITE, bg = th.accent, font = F.GothamBlack, d = 0.01 })
	local left = "1월  방어\n2월  도미\n3월  도다리\n4월  주꾸미\n5월  멍게\n6월  농어"
	local right = "7월  민어\n8월  갯장어\n9월  전어\n10월  대하\n11월  방어\n12월  대방어"
	local bh = h - hh - 0.2
	local rowH = bh / 6
	-- 이달 (10월) 강조 띠
	K:plate("SeasonNow", w / 2 - 0.12, rowH * 0.9, 0.045, dcf * CF(w / 4, h / 2 - hh - 0.1 - rowH * 3.5, 0), col(th.accent2))
	for k = 0, 5 do
		if k % 2 == 1 then
			K:plate("SeasonStripe", w - 0.12, rowH, 0.042, dcf * CF(0, h / 2 - hh - 0.1 - rowH * (k + 0.5), 0), col(rgb(228, 238, 246)))
		end
	end
	textColumns(K, "SeasonCols", dcf * CF(0, h / 2 - hh - 0.1 - bh / 2, 0.047), bh, 6, {
		{ x = -w / 4, w = w / 2 - 0.2, text = left, fg = rgb(30, 40, 60), font = F.GothamBold },
		{ x = w / 4, w = w / 2 - 0.2, text = right, fg = rgb(30, 40, 60), font = F.GothamBold },
	})
end

-- 소주 포스터 (초록 병 + 문구)
local function sojuPoster(c: any, dcf: CFrame, w: number, h: number)
	local K = c.K
	K:plate("PosterBack", w, h, 0.03, dcf, col(rgb(220, 240, 230)))
	K:plate("PosterBand", w, h * 0.3, 0.035, dcf * CF(0, -h * 0.35, 0), col(rgb(20, 120, 70)))
	local bc = dcf * CF(w * 0.18, h * 0.02, 0.035)
	K:plate("PosterBottle", w * 0.22, h * 0.42, 0.01, bc, col(rgb(40, 150, 90)))
	K:plate("PosterNeck", w * 0.08, h * 0.16, 0.01, bc * CF(0, h * 0.28, 0), col(rgb(40, 150, 90)))
	K:plate("PosterCap", w * 0.09, h * 0.04, 0.012, bc * CF(0, h * 0.37, 0), col(rgb(230, 230, 230)))
	K:plate("PosterLabel", w * 0.2, h * 0.12, 0.012, bc * CF(0, -h * 0.02, 0), L.white)
	K:text("PosterCopy", w * 0.5, h * 0.36, dcf * CF(-w * 0.2, h * 0.18, 0.04), "부산 바다엔\n시원한\n한 잔", { fg = rgb(20, 90, 60), font = F.GothamBlack, d = 0.005 })
	K:text("PosterSub", w * 0.9, h * 0.12, dcf * CF(0, -h * 0.35, 0.04), "회 한 접시엔 역시 소주", { fg = WHITE, font = F.GothamBold, d = 0.005 })
end

-- 위생등급 패
local function hygieneBadge(c: any, dcf: CFrame)
	local K = c.K
	K:plate("HygieneBack", 1.2, 1.5, 0.04, dcf, L.white)
	ktext(K, "HygieneHead", 1.2, 0.36, dcf * CF(0, 0.57, 0.041), "위생등급", { fg = WHITE, bg = rgb(30, 90, 170), font = F.GothamBlack, d = 0.01 })
	K:text("HygieneBody", 1.0, 1.0, dcf * CF(0, -0.17, 0.045), "★★★\n매우 우수\n식품의약품안전처", { fg = rgb(30, 60, 140), font = F.GothamBlack, d = 0.005 })
end

-- 작은 안내판 (와이파이 · 결제 · 포장 · 영업시간)
local function infoPlate(c: any, dcf: CFrame, w: number, h: number, text: string, fg: Color3, bg: Color3)
	local K = c.K
	K:plate("InfoPlateEdge", w + 0.06, h + 0.06, 0.03, dcf, L.alu)
	ktext(K, "InfoPlate", w, h, dcf * CF(0, 0, 0.031), text, { fg = fg, bg = bg, font = F.GothamBold, d = 0.02 })
end

-- 그물 + 부표 + 불가사리 (벽 장식)
local function netDecor(c: any, dcf: CFrame, w: number, h: number)
	local K = c.K
	local rope = L.of(170, 150, 110, M.Fabric)
	local nx = math.max(4, math.floor(w / 0.5))
	local ny = math.max(3, math.floor(h / 0.5))
	local sag = 0.18
	for i = 0, nx do
		local x = -w / 2 + w * i / nx
		local a = (dcf * CF(x, h / 2 - math.abs(x) / w * sag * 2, 0.08)).Position
		local b = (dcf * CF(x * 0.9, -h / 2, 0.1)).Position
		K:seg("NetRope", a, b, 0.03, rope)
	end
	for j = 0, ny do
		local y = h / 2 - h * j / ny
		local wj = w * (1 - 0.1 * j / ny)
		K:seg("NetRope", (dcf * CF(-wj / 2, y, 0.09)).Position, (dcf * CF(wj / 2, y, 0.09)).Position, 0.03, rope)
	end
	K:seg("NetTopRope", (dcf * CF(-w / 2 - 0.2, h / 2 + 0.05, 0.06)).Position, (dcf * CF(w / 2 + 0.2, h / 2 + 0.05, 0.06)).Position, 0.07, L.of(120, 96, 64, M.Fabric))
	-- 부표 (주황 · 흰)
	local buoys = { { -0.32, 0.1, rgb(240, 110, 30) }, { 0.05, -0.2, rgb(240, 240, 236) }, { 0.36, 0.15, rgb(240, 110, 30) } }
	for _, b in buoys do
		local p = dcf * CF(w * b[1], h * b[2], 0.35)
		K:ball("Buoy", 0.55, p, col(b[3], M.Plastic))
		K:vcyl("BuoyNeck", 0.14, 0.14, p * CF(0, 0.3, 0), L.of(60, 60, 60))
	end
	-- 불가사리
	local sc = dcf * CF(-w * 0.12, -h * 0.28, 0.14)
	for k = 0, 4 do
		K:plate("StarfishArm", 0.12, 0.34, 0.05, sc * ANG(0, 0, k * 2 * PI / 5) * CF(0, 0.16, 0), col(rgb(230, 120, 60)))
	end
	K:ell("Shell", V3(0.36, 0.3, 0.1), dcf * CF(w * 0.2, -h * 0.32, 0.14), col(rgb(240, 220, 200)))
end

-- 풍어기 (줄무늬 큰 깃발 + 글자)
local function bigFlag(c: any, dcf: CFrame, w: number, h: number, text: string)
	local K = c.K
	local stripes = { rgb(214, 36, 36), rgb(248, 214, 40), rgb(40, 110, 200), rgb(250, 250, 248), rgb(40, 160, 80) }
	K:cyl("FlagPole", w + 0.1, 0.08, dcf * CF(0, h / 2 + 0.08, 0.1), L.of(150, 110, 70, M.Wood))
	local sh = h / #stripes
	for i, cc in stripes do
		K:plate("FlagStripe", w, sh, 0.02, dcf * CF(0, h / 2 - sh * (i - 0.5), 0.04) * ANG(0, 0, (i % 2 - 0.5) * 0.01), col(cc, M.Fabric))
	end
	K:text("FlagText", w * 0.8, h * 0.7, dcf * CF(0, 0, 0.065), text, { fg = rgb(30, 30, 30), font = F.GothamBlack, d = 0.005 })
end

-- 오징어 건조 줄 (벽 위)
local function squidLine(c: any, dcf: CFrame, w: number)
	local K = c.K
	K:seg("DryLine", (dcf * CF(-w / 2, 0, 0.3)).Position, (dcf * CF(w / 2, 0, 0.3)).Position, 0.03, L.of(80, 80, 80))
	for _, sx in { -1, 1 } do
		K:plate("DryHook", 0.1, 0.2, 0.32, dcf * CF(sx * w / 2, 0, 0), L.of(120, 120, 120, M.Metal))
	end
	local n = math.max(3, math.floor(w / 0.75))
	for i = 1, n do
		local x = -w / 2 + w * (i - 0.5) / n
		local cc = dcf * CF(x, -0.55, 0.3)
		K:plate("DriedSquid", 0.42, 0.75, 0.02, cc, col(rgb(214, 170, 120)))
		K:plate("DriedSquidFin", 0.56, 0.14, 0.02, cc * CF(0, 0.38, 0.002), col(rgb(200, 150, 100)))
		for k = 1, 4 do
			K:plate("DriedSquidLeg", 0.05, 0.45, 0.015, cc * CF(-0.16 + k * 0.064, -0.56, 0.002) * ANG(0, 0, (k - 2.5) * 0.1), col(rgb(190, 140, 96)))
		end
		K:plate("DryPeg", 0.06, 0.18, 0.04, cc * CF(0, 0.5, 0.01), L.of(230, 230, 230, M.Plastic))
	end
end

-- 큰 대게 간판 (벽, 빨간 대게 조형)
local function crabSign(c: any, dcf: CFrame, w: number)
	local K = c.K
	local s = w / 3.2
	local shell = col(rgb(214, 54, 36))
	local base = dcf * CF(0, 0, 0.2)
	K:ell("CrabSignShell", V3(1.4 * s, 1.0 * s, 0.3), base, shell)
	K:ell("CrabSignShellHi", V3(1.0 * s, 0.5 * s, 0.32), base * CF(0, 0.15 * s, 0.02), col(rgb(236, 96, 60)))
	for _, sx in { -1, 1 } do
		for i = 1, 4 do
			local a = base * V3(sx * 0.55 * s, (0.2 - i * 0.16) * s, 0)
			local b = base * V3(sx * (1.1 + i * 0.05) * s, (0.45 - i * 0.28) * s, 0)
			local d0 = base * V3(sx * (1.5 + i * 0.02) * s, (0.0 - i * 0.32) * s, 0)
			K:seg("CrabSignLeg", a, b, 0.12 * s, shell)
			K:seg("CrabSignLeg", b, d0, 0.1 * s, shell)
		end
		local ca = base * V3(sx * 0.45 * s, 0.4 * s, 0)
		local cb = base * V3(sx * 0.8 * s, 0.85 * s, 0)
		K:seg("CrabSignArm", ca, cb, 0.14 * s, shell)
		K:ell("CrabSignClaw", V3(0.5 * s, 0.3 * s, 0.2), CF(cb + V3(0, 0.1 * s, 0)) * CFrame.fromMatrix(V3(), dcf.XVector, dcf.YVector, dcf.ZVector) * ANG(0, 0, sx * 0.6), shell)
		K:ball("CrabSignEye", 0.16 * s, base * CF(sx * 0.16 * s, 0.5 * s, 0.1), L.white)
		K:ball("CrabSignPupil", 0.08 * s, base * CF(sx * 0.16 * s, 0.52 * s, 0.17), L.black)
	end
	ktext(K, "CrabSignText", 1.2 * s, 0.38 * s, base * CF(0, -0.15 * s, 0.17), "대게", { fg = WHITE, font = F.GothamBlack, d = 0.01 })
end

-- 광안대교 야경 파노라마 액자 (마린시티 스카이라인 + 복층 현수교 + 무지개 조명 + 드론쇼)
local function bridgeArt(c: any, dcf: CFrame, w: number, h: number)
	-- 광안대교 야경 사진 액자: 검은 알루 프레임 + 흰 매트 + 사진 (노을 하늘 · 마린시티 실루엣 · 주탑 2 · 현수 케이블 · 수면 반사)
	local K = c.K
	local fr = L.of(24, 24, 26, M.Metal)
	K:plate("BridgeMat", w, h, 0.05, dcf, L.of(246, 244, 238, M.SmoothPlastic))
	for _, sy in { -1, 1 } do
		K:plate("BridgeFrame", w + 0.12, 0.08, 0.1, dcf * CF(0, sy * (h / 2 + 0.02), 0), fr)
	end
	for _, sx in { -1, 1 } do
		K:plate("BridgeFrame", 0.08, h + 0.12, 0.1, dcf * CF(sx * (w / 2 + 0.02), 0, 0), fr)
	end
	local mat = 0.16
	local iw, ih = w - mat * 2, h - mat * 2 - 0.12
	local pc = dcf * CF(0, 0.06, 0.05)
	-- 하늘 (위 남색 -> 지평선 보라 · 분홍), 바다
	local sky = { rgb(14, 20, 52), rgb(36, 34, 88), rgb(92, 56, 120), rgb(170, 92, 120) }
	local skyH = ih * 0.58
	for k, cc in sky do
		local bh = skyH / #sky
		K:plate("BridgeSky", iw, bh, 0.004, pc * CF(0, ih / 2 - bh * (k - 0.5), 0), col(cc))
	end
	local seaH = ih - skyH
	K:plate("BridgeSea", iw, seaH, 0.004, pc * CF(0, -ih / 2 + seaH / 2, 0), col(rgb(8, 16, 36)))
	local hz = ih / 2 - skyH -- 지평선 y
	wdisc(K, "BridgeMoon", ih * 0.09, 0.004, pc * CF(-iw * 0.38, ih * 0.36, 0), 0.0, L.neon(rgb(250, 240, 210)))
	-- 마린시티 실루엣 (왼쪽 뒤) : 어두운 탑 + 꼭대기 경관등 몇 점
	local bxs = { 0.04, 0.085, 0.12, 0.16, 0.2, 0.235, 0.27 }
	for i, f in bxs do
		local bx = -iw / 2 + iw * f
		local bh = ih * (0.12 + ((i * 37) % 10) / 45)
		local bw = iw * (0.03 + (i % 3) * 0.008)
		K:plate("BridgeCity", bw, bh, 0.006, pc * CF(bx, hz + bh / 2, 0), col(rgb(20, 22, 40)))
		if c.hi and i % 2 == 1 then
			K:plate("BridgeCityLamp", bw * 0.5, 0.025, 0.008, pc * CF(bx, hz + bh - 0.03, 0), L.neon(rgb(255, 214, 150), 0.3))
		end
	end
	-- 다리: 복층 상판 (불빛 줄) + 주탑 2 (H형, 흰 조명) + 주케이블 + 행어
	local cableC = pickOf({ rgb(90, 170, 255), rgb(170, 110, 255), rgb(80, 230, 210) }, c.seed, 41)
	local dy = hz + ih * 0.05
	K:plate("BridgeDeck", iw, 0.06, 0.01, pc * CF(0, dy, 0), col(rgb(40, 44, 64)))
	K:plate("BridgeDeckLights", iw, 0.022, 0.014, pc * CF(0, dy + 0.035, 0), L.neon(rgb(255, 226, 170)))
	K:plate("BridgeDeckLights2", iw, 0.018, 0.014, pc * CF(0, dy - 0.04, 0), L.neon(cableC, 0.2))
	local tx = iw * 0.21
	local th0 = ih * 0.4
	for _, sx in { -1, 1 } do
		for _, dx in { -0.035, 0.035 } do
			K:plate("BridgePylon", 0.035, th0, 0.012, pc * CF(sx * tx + dx, dy + th0 / 2 - 0.08, 0), L.neon(rgb(226, 232, 250), 0.15))
		end
		K:plate("BridgePylonBeam", 0.1, 0.03, 0.014, pc * CF(sx * tx, dy + th0 - 0.2, 0), L.neon(rgb(226, 232, 250), 0.15))
		K:plate("BridgePylonBeam", 0.1, 0.03, 0.014, pc * CF(sx * tx, dy + th0 * 0.45, 0), L.neon(rgb(226, 232, 250), 0.15))
		-- 수면 반사 (세로로 흔들리는 빛 기둥)
		for k = 1, 3 do
			K:plate("BridgeReflect", 0.03, seaH * (0.5 - k * 0.1), 0.008, pc * CF(sx * tx + (k - 2) * 0.05, hz - seaH * (0.25 - k * 0.02), 0), L.neon(if k == 2 then rgb(226, 232, 250) else cableC, 0.5))
		end
	end
	local function cable(x0: number, y0: number, x1: number, y1: number, sag: number, hangers: boolean)
		local n = 6
		local prev = nil
		for k = 0, n do
			local t = k / n
			local x = x0 + (x1 - x0) * t
			local y = y0 + (y1 - y0) * t - sag * 4 * t * (1 - t)
			local p = (pc * CF(x, y, 0.014)).Position
			if prev then
				K:seg("BridgeCable", prev, p, 0.03, L.neon(cableC))
			end
			if hangers and c.hi and k > 0 and k < n then
				K:seg("BridgeHanger", p, (pc * CF(x, dy + 0.03, 0.012)).Position, 0.008, col(rgb(120, 130, 170)))
			end
			prev = p
		end
	end
	local topY = dy + th0 - 0.08
	cable(-tx, topY, tx, topY, th0 * 0.78, true)
	cable(-iw / 2 + 0.03, dy + 0.05, -tx, topY, -th0 * 0.1, false)
	cable(tx, topY, iw / 2 - 0.03, dy + 0.05, -th0 * 0.1, false)
	-- 드론쇼 (하트 점)
	if c.hi then
		for k = 0, 9 do
			local a = k / 10 * PI * 2
			local hx = 16 * math.sin(a) ^ 3
			local hy = 13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a)
			K:plate("DroneDot", 0.04, 0.04, 0.01, pc * CF(iw * 0.32 + hx * 0.011, ih * 0.3 + hy * 0.011, 0), L.neon(rgb(255, 150, 214)))
		end
	end
	K:plate("BridgeGlass", w - 0.04, h - 0.04, 0.01, dcf * CF(0, 0, 0.09), { c = rgb(230, 236, 240), m = M.Glass, t = 0.9, r = 0.2 })
	K:text("BridgeCaption", w * 0.7, 0.13, dcf * CF(0, -h / 2 + 0.1, 0.051), "광안대교 야경 · 민락수변공원에서", { fg = rgb(60, 60, 64), font = F.GothamMedium, d = 0.004 })
end

-- 천장 그물 (부표 · 불가사리를 담아 처지게 매단 장식 그물)
local function ceilingNet(c: any)
	local K, V = c.K, c.V
	local nw, nd = math.min(8, V.W * 0.28), 3.6
	local rope = L.of(176, 156, 112, M.Fabric)
	local nets = 0
	local want = if V.W > 30 then 2 else 1
	local zc = (V.z0 + V.z1) / 2
	local used = {}
	local x = V.x0 + nw / 2 + 1.5
	while x <= V.x1 - nw / 2 - 1.5 and nets < want do
		local ok = true
		for _, u in used do
			if math.abs(u - x) < nw + 2 then
				ok = false
			end
		end
		if ok then
			for i = 0, 2 do
				for j = 0, 2 do
					if not Common.ceilFree(K, x - nw / 2 + nw * i / 2, zc - nd / 2 + nd * j / 2, 0.35) then
						ok = false
					end
				end
			end
		end
		if ok and budget(K, 70) then
			table.insert(used, x)
			nets += 1
			local top = V.H - 0.06
			local sag = 0.85
			local function y(u: number, v: number): number
				return top - sag * (1 - (2 * u - 1) ^ 2) * (1 - (2 * v - 1) ^ 2) - 0.08
			end
			local function P(u: number, v: number): Vector3
				return V3(x - nw / 2 + nw * u, y(u, v), zc - nd / 2 + nd * v)
			end
			local nu, nv = 6, 3
			for j = 0, nv do
				local v = j / nv
				for i = 0, nu - 1, 2 do
					K:seg("CeilNetRope", P(i / nu, v), P((i + 2) / nu, v), 0.035, rope)
				end
			end
			for i = 0, nu do
				local u = i / nu
				K:seg("CeilNetRope", P(u, 0), P(u, 0.5), 0.035, rope)
				K:seg("CeilNetRope", P(u, 0.5), P(u, 1), 0.035, rope)
			end
			for _, cu in { 0, 1 } do
				for _, cv in { 0, 1 } do
					local p = P(cu, cv)
					K:vcyl("CeilNetHook", 0.12, 0.08, CF(p.X, V.H - 0.06, p.Z), L.of(120, 120, 120, M.Metal))
				end
			end
			-- 그물에 얹힌 부표 · 불가사리 · 소라
			local items = { { 0.3, 0.45, "buoy", rgb(240, 110, 30) }, { 0.55, 0.5, "buoy", rgb(246, 246, 240) }, { 0.72, 0.4, "star", rgb(230, 120, 60) }, { 0.18, 0.7, "glass", rgb(70, 150, 110) }, { 0.42, 0.62, "shell", rgb(240, 222, 200) }, { 0.8, 0.6, "buoy", rgb(240, 110, 30) }, { 0.64, 0.25, "glass", rgb(60, 120, 150) } }
			for k, it in items do
				if not c.hi and k > 3 then
					break
				end
				local p = P(it[1], it[2])
				if it[3] == "buoy" then
					K:ball("CeilBuoy", 0.6, CF(p - V3(0, 0.26, 0)), col(it[4], M.Plastic))
				elseif it[3] == "glass" then
					-- 유리 부표 (밧줄 망에 싸서 늘어뜨림)
					local q = p - V3(0, 0.55, 0)
					K:seg("CeilFloatRope", p, q + V3(0, 0.22, 0), 0.03, rope)
					K:ball("CeilGlassFloat", 0.48, CF(q), { c = it[4], m = M.SmoothPlastic, t = 0.25, r = 0.25 })
					K:ring("CeilFloatNet", CF(q) * ANG(PI / 2, 0, 0), 0.245, 0.025, 8, rope)
				elseif it[3] == "star" then
					for a = 0, 4 do
						K:box("CeilStarArm", V3(0.36, 0.06, 0.12), CF(p - V3(0, 0.05, 0)) * ANG(0, a * 2 * PI / 5, 0) * CF(0.16, 0, 0), col(it[4]))
					end
				else
					K:ell("CeilShell", V3(0.4, 0.3, 0.32), CF(p - V3(0, 0.14, 0)), col(it[4]))
				end
			end
			Common.useCeil(K, x, zc)
		end
		x += 1.0
	end
end

-- 집어등 (오징어 배 등) 장식 줄: 천장에 매단 검은 파이프 + 반사갓 + 큰 전구 (네온). 반환: 전구 수
local function fishingLamps(c: any): number
	local K, V = c.K, c.V
	if not budget(K, 40) then
		return 0
	end
	local yPipe = V.H - 0.95
	local step = 1.7
	local zc = (V.z0 + V.z1) / 2
	local best: { number }? = nil
	local bestZ = zc
	for _, dz in { -1.2, 1.2, -2.6, 2.6, 0 } do
		local z = zc + dz
		local run: { number } = {}
		local x = V.x0 + 3
		while x <= V.x1 - 3 do
			if Common.ceilFree(K, x, z, 0.55) then
				table.insert(run, x)
			else
				if #run > (if best then #(best :: { number }) else 0) then
					best, bestZ = run, z
				end
				run = {}
			end
			x += step
		end
		if #run > (if best then #(best :: { number }) else 0) then
			best, bestZ = run, z
		end
		if best and #(best :: { number }) >= 6 then
			break
		end
	end
	if not best or #(best :: { number }) < 4 then
		return 0
	end
	local xs: { number } = best :: { number }
	local n = math.min(#xs, if c.hi then 8 else 5)
	local i0 = math.floor((#xs - n) / 2) + 1
	local xa, xb = xs[i0], xs[i0 + n - 1]
	local pipe = L.of(36, 38, 40, M.Metal)
	K:seg("LampPipe", V3(xa - 0.5, yPipe, bestZ), V3(xb + 0.5, yPipe, bestZ), 0.12, pipe)
	for _, x in { xa, xb } do
		K:seg("LampRod", V3(x, yPipe, bestZ), V3(x, V.H - 0.02, bestZ), 0.06, pipe)
		K:vcyl("LampRodPlate", 0.04, 0.3, CF(x, V.H - 0.03, bestZ), pipe)
	end
	for k = i0, i0 + n - 1 do
		local x = xs[k]
		local top = CF(x, yPipe - 0.06, bestZ)
		K:vcyl("LampSocket", 0.32, 0.22, top * CF(0, -0.16, 0), L.black)
		K:disc("LampShade", 0.8, 0.05, top * CF(0, -0.28, 0), L.of(214, 218, 222, M.Metal, { r = 0.2 }))
		K:disc("LampShadeLip", 0.86, 0.03, top * CF(0, -0.31, 0), L.of(180, 184, 188, M.Metal))
		K:ell("LampBulb", V3(0.44, 0.62, 0.44), top * CF(0, -0.62, 0), L.neon(rgb(255, 236, 196), 0.05))
		Common.useCeil(K, x, bestZ)
	end
	return n
end

-- 벽걸이 TV (화면 = 스스로 빛나는 라벨)
local function tvSet(c: any, dcf: CFrame, w: number): (BasePart, TextLabel, BasePart)
	local K = c.K
	local h = w * 9 / 16
	K:plate("TVMount", w * 0.3, h * 0.3, 0.14, dcf, L.blackMetal)
	local body = K:plate("TVBody", w + 0.12, h + 0.12, 0.12, dcf * CF(0, 0, 0.14), L.black)
	local scr, lbl = K:text("TVScreen", w, h, dcf * CF(0, 0, 0.26), "", { bg = rgb(20, 90, 40), fg = WHITE, glow = 1.1, font = F.GothamBlack, d = 0.01 })
	K:plate("TVLogo", 0.24, 0.04, 0.01, dcf * CF(0, -h / 2 - 0.03, 0.26), L.chrome)
	K:plate("TVLed", 0.05, 0.03, 0.01, dcf * CF(w / 2 - 0.1, -h / 2 - 0.03, 0.26), L.ledRed)
	K:seg("TVCable", (dcf * CF(w * 0.2, -h / 2 + 0.1, 0.12)).Position, (dcf * CF(w * 0.2, -h / 2 - 1.4, 0.03)).Position, 0.05, L.black)
	return scr, lbl, body
end

local TV_CH = {
	{ c = rgb(20, 100, 50), text = "롯데 3 : 2 한화   7회말\n사직야구장 LIVE" },
	{ c = rgb(16, 52, 110), text = "낚시 채널 · 오늘의 조황\n기장 앞바다 감성돔 마릿수" },
	{ c = rgb(30, 34, 44), text = "부산 내일 날씨\n맑음 · 18℃ · 파고 0.5m" },
	{ c = rgb(120, 26, 30), text = "뉴스\n광안리 드론쇼 이번 주 토요일 20시" },
}

-- 벽걸이 선풍기 (줄 스위치)
local function wallFan(c: any, dcf: CFrame): (any, BasePart)
	local K = c.K
	local plastic = L.of(240, 240, 236, M.Plastic)
	K:plate("FanMount", 0.5, 0.7, 0.14, dcf, plastic)
	K:box("FanArm", V3(0.16, 0.16, 0.6), dcf * CF(0, -0.1, 0.44), plastic)
	local head = dcf * CF(0, -0.18, 0.95) * ANG(math.rad(-18), 0, 0)
	K:ell("FanMotor", V3(0.55, 0.55, 0.75), head * CF(0, 0, -0.18), plastic)
	local R = 0.8
	K:ring("FanGuard", head * CF(0, 0, 0.32), R, 0.04, 10, plastic)
	K:ring("FanGuard", head * CF(0, 0, 0.06), R, 0.04, 10, plastic)
	for i = 0, 5 do
		local a = i * PI / 3
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
	local drop = 1.4
	local pull = dcf * CF(0.24, -drop, 0.12)
	K:seg("FanCord", (dcf * CF(0.24, -0.3, 0.12)).Position, pull.Position, 0.025, L.of(200, 200, 196))
	local knob = K:ball("FanPullKnob", 0.16, pull, plastic)
	return state, knob
end

-- 수족관 조명 · 기포기 스위치 박스 (벽) + 위로 올라가는 전선관
local function tankSwitchBox(c: any, dcf: CFrame): BasePart
	local K, V = c.K, c.V
	K:plate("TankCtrlBox", 1.0, 1.3, 0.22, dcf, L.of(214, 216, 214, M.Plastic))
	K:plate("TankCtrlDoor", 0.9, 1.2, 0.03, dcf * CF(0, 0, 0.22), L.of(226, 228, 226, M.Plastic))
	K:plate("TankCtrlBand", 0.86, 0.22, 0.01, dcf * CF(0, 0.44, 0.25), col(rgb(30, 90, 170)))
	local sw = K:plate("TankCtrlSwitch", 0.3, 0.42, 0.06, dcf * CF(-0.2, 0.0, 0.25), L.of(60, 140, 220, M.Plastic))
	K:plate("TankCtrlSwitch2", 0.3, 0.42, 0.06, dcf * CF(0.2, 0.0, 0.25), L.of(60, 140, 220, M.Plastic))
	K:text("TankCtrlSub", 0.86, 0.3, dcf * CF(0, -0.36, 0.255), "수족관 조명 · 기포기", { fg = rgb(30, 60, 120), font = F.GothamBold, d = 0.005 })
	K:plate("TankCtrlLED", 0.06, 0.06, 0.02, dcf * CF(0.36, -0.5, 0.25), L.ledGreen)
	return sw
end

-- 바닥 소품 --------------------------------------------------------------------------------------------------
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
	elseif kind == "sake" then
		K:vcyl("SakeBottle", 0.7, 0.3, base * CF(0, 0.35, 0), { c = rgb(236, 236, 228), m = M.Glass, t = 0.25 })
		if hi then
			K:vcyl("SakeNeck", 0.26, 0.13, base * CF(0, 0.83, 0), { c = rgb(236, 236, 228), m = M.Glass, t = 0.25 })
			K:plate("SakeLabel", 0.24, 0.32, 0.01, base * CF(0, 0.36, 0.15), L.of(30, 30, 30))
		end
	elseif kind == "cider" then
		K:vcyl("Cider", 0.62, 0.26, base * CF(0, 0.31, 0), { c = rgb(140, 210, 150), m = M.Glass, t = 0.3 })
		if hi then
			K:vcyl("CiderCap", 0.06, 0.12, base * CF(0, 0.65, 0), L.of(40, 120, 60))
		end
	else
		K:vcyl("Can", 0.42, 0.24, base * CF(0, 0.21, 0), L.of(200, 30, 36, M.Metal))
	end
end

local function drinkFridge(c: any, pcf: CFrame, nd: number)
	local K, th = c.K, c.th
	local dw = 2.0
	local w = nd * dw + 0.3
	local h = 6.3
	local d = 2.0
	local body = if th.kind == "sushi" then L.of(40, 40, 42, M.Metal) else L.of(232, 234, 236, M.Metal)
	K:box("FridgeBack", V3(w, h, 0.12), pcf * CF(0, h / 2, -d / 2 + 0.06), body)
	K:box("FridgeSide", V3(0.12, h, d), pcf * CF(-w / 2 + 0.06, h / 2, 0), body)
	K:box("FridgeSide", V3(0.12, h, d), pcf * CF(w / 2 - 0.06, h / 2, 0), body)
	K:box("FridgeTop", V3(w, 0.75, d), pcf * CF(0, h - 0.375, 0), body)
	K:box("FridgeBase", V3(w, 0.6, d), pcf * CF(0, 0.3, 0), body)
	K:plate("FridgeVent", w * 0.6, 0.3, 0.02, pcf * CF(0, 0.3, d / 2), L.of(80, 82, 86, M.DiamondPlate))
	K:box("FridgeInner", V3(w - 0.26, h - 1.35, 0.02), pcf * CF(0, 0.6 + (h - 1.35) / 2, -d / 2 + 0.13), L.of(244, 246, 248))
	litFace(K, "FridgeHeader", w - 0.14, 0.55, pcf * CF(0, h - 0.375, d / 2), if th.kind == "sushi" then rgb(26, 26, 30) else rgb(16, 110, 64), th.fridgeHeader, WHITE, 1.2, 0.02)
	local lamp = K:box("FridgeLamp", V3(w - 0.4, 0.05, 0.1), pcf * CF(0, h - 0.8, d / 2 - 0.3), L.lampCool)
	K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.7, Angle = 140, Color = L.coolLight })
	local shelves = 4
	local innerH = h - 1.35
	local kinds = { "soju", "soju", "beer", "cider" }
	if th.kind == "sushi" then
		kinds = { "sake", "sake", "beer", "can" }
	end
	for i = 1, shelves do
		local y = 0.6 + (i - 1) * innerH / shelves + 0.02
		K:box("FridgeShelf", V3(w - 0.3, 0.04, d - 0.5), pcf * CF(0, y, -0.1), L.of(190, 194, 198, M.Metal))
		local kind = kinds[i]
		local step0 = if kind == "sake" then 0.44 else 0.4
		local n = math.floor((w - 0.5) / step0)
		local step = (w - 0.5) / n
		for j = 1, n do
			local x = -w / 2 + 0.25 + step * (j - 0.5)
			bottle(K, pcf * CF(x, y + 0.02, 0.35), kind, c.hi and (j % 2 == 1))
		end
	end
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
			K:box("FridgeDoorGlass", V3(dw - 0.22, innerH - 0.22, 0.03), cc, { c = rgb(220, 236, 240), m = M.Glass, t = 0.84, r = 0.02 })
			K:box("FridgeDoorHandle", V3(0.08, innerH * 0.55, 0.12), cc * CF(dw / 2 - 0.22, 0, 0.1), L.chrome)
		end)
		local hinge = (K.cf * pcf * CF(x0, 0, d / 2 + 0.05)).Position
		table.insert(doors, { m = m, hinge = hinge })
	end
	return doors
end

-- 스티로폼 활어 상자 더미
local function styroStack(c: any, pcf: CFrame, n: number)
	local K = c.K
	local foam = L.of(246, 246, 242, M.Plastic)
	local labels = { "활어 직송 · 통영", "제주 광어", "수협 공판장", "활어 · 냉장" }
	for i = 1, n do
		local y = (i - 1) * 0.92
		local rot = ANG(0, (rnd(c.seed, i) - 0.5) * 0.12, 0)
		local b = pcf * CF(0, y, 0) * rot
		K:box("StyroBox", V3(2.0, 0.84, 1.3), b * CF(0, 0.42, 0), foam)
		K:box("StyroLid", V3(2.04, 0.08, 1.34), b * CF(0, 0.88, 0), L.of(238, 238, 234, M.Plastic))
		K:box("StyroTape", V3(0.24, 0.05, 1.36), b * CF(0, 0.9, 0), L.of(40, 110, 200, M.Plastic))
		ktext(K, "StyroLabel", 1.2, 0.3, b * CF(0, 0.45, 0.651), labels[(i + c.seed) % #labels + 1], { fg = rgb(30, 70, 160), font = F.GothamBlack, d = 0.01 })
	end
end

-- 빨간 고무 다라이 (물 + 낙지 · 조개): 바닥이 좁고 위가 넓은 통 + 말린 테두리 + 물 + 기포 호스
local function basin(c: any, pcf: CFrame, kind: string)
	local K = c.K
	local red = L.of(190, 38, 32, M.Rubber)
	K:disc("BasinBottom", 1.5, 0.08, pcf * CF(0, 0.04, 0), dim(red, 0.15))
	K:disc("BasinLow", 1.7, 0.3, pcf * CF(0, 0.23, 0), red)
	K:disc("Basin", 1.9, 0.36, pcf * CF(0, 0.55, 0), red)
	K:disc("BasinRim", 2.08, 0.1, pcf * CF(0, 0.76, 0), dim(red, 0.08))
	K:disc("BasinInner", 1.72, 0.04, pcf * CF(0, 0.72, 0), dim(red, 0.35))
	K:disc("BasinWater", 1.74, 0.03, pcf * CF(0, 0.66, 0), { c = rgb(70, 130, 160), m = M.SmoothPlastic, t = 0.35, r = 0.25 })
	if kind == "octopus" then
		for i = 1, 3 do
			local a = i * 2.1
			local p = pcf * CF(math.cos(a) * 0.4, 0.66, math.sin(a) * 0.4)
			K:ell("OctopusHead", V3(0.34, 0.16, 0.3), p * CF(0, 0.03, 0), col(rgb(150, 104, 116)))
			for k = 1, 4 do
				local b = a + k * 1.4
				K:seg("OctopusArm", p.Position, (p * CF(math.cos(b) * 0.42, -0.02, math.sin(b) * 0.42)).Position, 0.06, col(rgb(176, 128, 136)))
			end
		end
	else
		shellPile(K, pcf * CF(0, 0.62, 0), 1.3, 1.3, "clam", c.seed + 9, if c.hi then 10 else 5)
	end
	K:seg("BasinAirHose", (pcf * CF(0.8, 0.8, 0.4)).Position, (pcf * CF(0.55, 0.45, 0.25)).Position, 0.045, { c = rgb(220, 230, 230), m = M.SmoothPlastic, t = 0.3 })
end

-- 개업 축하 화분 (금전수 + 리본)
local function giftPlant(c: any, pcf: CFrame)
	local K = c.K
	K:vcyl("GiftPot", 1.0, 1.1, pcf * CF(0, 0.5, 0), L.of(240, 240, 236, M.Plastic))
	K:vcyl("GiftPotRim", 0.08, 1.16, pcf * CF(0, 1.0, 0), L.of(220, 200, 120, M.Metal))
	K:disc("GiftSoil", 1.0, 0.04, pcf * CF(0, 0.98, 0), L.soil)
	for i = 1, 7 do
		local a = i * 0.9
		local lean = 0.1 + (i % 3) * 0.06
		local h = 1.3 + (i % 3) * 0.32
		local root = pcf * V3(math.cos(a) * 0.2, 1.0, math.sin(a) * 0.2)
		local tip = pcf * V3(math.cos(a) * (0.2 + lean * h), 1.0 + h, math.sin(a) * (0.2 + lean * h))
		K:seg("ZZStem", root, tip, 0.06, L.of(70, 110, 50))
		for k = 1, 3 do
			local p = root:Lerp(tip, 0.35 + k * 0.2)
			K:ell("ZZLeaf", V3(0.3, 0.06, 0.16), CF(p) * ANG(0, a + k, 0.3), L.of(46, 110, 50, M.SmoothPlastic, { r = 0.1 }))
		end
	end
	-- 리본 (축 개업 · 번창하세요)
	local rc = pcf * CF(0.0, 0.92, 0.56)
	K:plate("RibbonKnot", 0.36, 0.2, 0.04, rc, L.of(200, 30, 40, M.Fabric))
	ktext(K, "Ribbon", 0.26, 1.7, rc * CF(-0.22, -0.95, 0.02) * ANG(0, 0, 0.08), vertical("축 개업"), { fg = rgb(250, 230, 160), bg = rgb(200, 30, 40), font = F.GothamBold, d = 0.01 })
	ktext(K, "Ribbon", 0.26, 1.7, rc * CF(0.22, -0.95, 0.02) * ANG(0, 0, -0.08), vertical("번창하세요"), { fg = rgb(250, 230, 160), bg = rgb(200, 30, 40), font = F.GothamBold, d = 0.01 })
end

-- 조개 진열대 (2단 스텐, 앞으로 기울인 얼음 판 + 빨간 바구니 + 이름표, 위 간판)
local function clamRack(c: any, pcf: CFrame, w: number)
	local K = c.K
	local d, h = 1.6, 3.6
	local steel = L.of(200, 204, 208, M.Metal)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:box("RackLeg", V3(0.1, h, 0.1), pcf * CF(sx * (w / 2 - 0.05), h / 2, sz * (d / 2 - 0.05)), steel)
		end
	end
	local kinds = { { "scallop", "가리비" }, { "clam", "백합" }, { "mussel", "홍합" }, { "pen", "키조개" }, { "abalone", "전복" }, { "conch", "소라" } }
	local idx = 0
	for tier = 1, 2 do
		local y = if tier == 1 then 1.0 else 2.15
		-- 앞으로 15도 기울인 판 (손님 쪽 = +Z)
		local tc = pcf * CF(0, y, 0) * ANG(math.rad(15), 0, 0)
		K:box("RackTray", V3(w, 0.06, d - 0.1), tc, steel)
		K:box("RackIce", V3(w - 0.2, 0.06, d - 0.3), tc * CF(0, 0.06, 0), L.of(236, 244, 248, M.Ice))
		K:box("RackLip", V3(w, 0.16, 0.05), tc * CF(0, 0.08, (d - 0.1) / 2), steel)
		local nb = math.max(2, math.floor(w / 1.2))
		local bw = (w - 0.3) / nb - 0.1
		for k = 1, nb do
			idx += 1
			local x = -w / 2 + 0.15 + (bw + 0.1) * (k - 0.5) + 0.05
			local bc = tc * CF(x, 0.09, -0.05)
			local red = L.of(206, 36, 36, M.Plastic)
			local bd = 1.0
			K:box("RedBasket", V3(bw, 0.05, bd), bc * CF(0, 0.025, 0), red)
			for _, sz in { -1, 1 } do
				K:box("RedBasketSide", V3(bw, 0.24, 0.04), bc * CF(0, 0.12, sz * bd / 2), red)
			end
			for _, sx in { -1, 1 } do
				K:box("RedBasketSide", V3(0.04, 0.24, bd), bc * CF(sx * bw / 2, 0.12, 0), red)
			end
			local kd = kinds[(idx - 1) % #kinds + 1]
			shellPile(K, bc * CF(0, 0.04, 0), bw, bd, kd[1], c.seed + idx, if c.hi then 10 else 5)
			ktext(K, "RackTag", 0.7, 0.24, bc * CF(0, 0.14, bd / 2 + 0.03), kd[2], { fg = rgb(200, 30, 30), bg = WHITE, font = F.GothamBlack, d = 0.01 })
		end
	end
	K:box("RackTopBar", V3(w, 0.08, 0.08), pcf * CF(0, h - 0.04, d / 2 - 0.05), steel)
	ktext(K, "RackHeader", w, 0.46, pcf * CF(0, h + 0.2, d / 2 - 0.05), "오늘 들어온 조개", { fg = WHITE, bg = c.th.accent, font = F.GothamBlack, d = 0.05 })
end

-- 대게 찜통 (가스 레인지 + 3단 원형 찜통 2줄 + 벽 후드 + 김). 반환: 뚜껑 Model, 경첩(월드), 축(월드)
local function crabSteamer(c: any, pcf: CFrame): (Model?, Vector3?, Vector3?)
	local K, V = c.K, c.V
	local w, d = 2.6, 1.8
	local steel = L.of(206, 210, 214, M.Metal, { r = 0.1 })
	local rangeH = 1.4
	K:box("SteamRange", V3(w, rangeH - 0.3, d), pcf * CF(0, 0.3 + (rangeH - 0.3) / 2, 0), steel)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:box("SteamRangeLeg", V3(0.12, 0.3, 0.12), pcf * CF(sx * (w / 2 - 0.12), 0.15, sz * (d / 2 - 0.12)), L.of(60, 60, 64, M.Metal))
		end
		wdisc(K, "SteamRangeKnob", 0.22, 0.08, pcf * CF(sx * 0.62, 0.95, d / 2), 0, L.black)
	end
	K:box("SteamRangeTop", V3(w + 0.04, 0.06, d + 0.04), pcf * CF(0, rangeH + 0.03, 0), L.of(50, 52, 56, M.Metal))
	K:plate("SteamPilot", 0.1, 0.06, 0.02, pcf * CF(0, 0.95, d / 2), L.neon(rgb(80, 150, 255)))
	ktext(K, "SteamRangeLabel", 1.5, 0.3, pcf * CF(0, 0.55, d / 2 + 0.01), "대게 찜통 · 15분", { fg = WHITE, bg = rgb(196, 36, 28), font = F.GothamBold, d = 0.02 })
	local lid: Model? = nil
	local hinge: Vector3? = nil
	for k, sx in { -1, 1 } do
		local base = pcf * CF(sx * 0.64, rangeH + 0.06, 0)
		K:disc("SteamBurnerRing", 0.9, 0.06, base * CF(0, 0.03, 0), L.of(40, 40, 44, M.Metal))
		local y = 0.06
		for tier = 1, 3 do
			K:disc("SteamBasket", 1.16, 0.5, base * CF(0, y + 0.25, 0), steel)
			K:disc("SteamBasketRim", 1.22, 0.05, base * CF(0, y + 0.5, 0), L.of(186, 190, 194, M.Metal))
			if tier == 2 then
				for _, hx in { -1, 1 } do
					K:box("SteamBasketHandle", V3(0.16, 0.06, 0.3), base * CF(hx * 0.64, y + 0.4, 0), L.black)
				end
			end
			y += 0.52
		end
		local lidY = y
		if k == 1 then
			local hz = -0.58
			lid = K:group("SteamerLid", function()
				K:disc("SteamLid", 1.2, 0.08, base * CF(0, lidY + 0.04, 0), L.of(196, 200, 204, M.Metal))
				K:ell("SteamLidDome", V3(1.1, 0.24, 1.1), base * CF(0, lidY + 0.08, 0), L.of(196, 200, 204, M.Metal))
				K:ball("SteamLidHandle", 0.2, base * CF(0, lidY + 0.24, 0.2), L.black)
			end)
			hinge = (K.cf * base * CF(0, lidY + 0.04, hz)).Position
		else
			K:disc("SteamLid", 1.2, 0.08, base * CF(0, lidY + 0.04, 0), L.of(196, 200, 204, M.Metal))
			K:ell("SteamLidDome", V3(1.1, 0.24, 1.1), base * CF(0, lidY + 0.08, 0), L.of(196, 200, 204, M.Metal))
			K:ball("SteamLidKnob", 0.18, base * CF(0, lidY + 0.24, 0), L.black)
		end
		table.insert(c.steamSrc, base * CF(0, lidY + 0.3, 0))
	end
	-- 벽 후드 + 덕트
	local hoodY = math.min(V.H - 1.4, 5.9)
	local hc = pcf * CF(0, hoodY, -d / 2 + 0.75)
	K:box("SteamHood", V3(w + 0.3, 0.6, 1.5), hc, steel)
	K:box("SteamHoodLip", V3(w + 0.34, 0.08, 1.54), hc * CF(0, -0.3, 0), L.of(170, 174, 178, M.Metal))
	K:box("SteamHoodFilter", V3(w, 0.03, 1.2), hc * CF(0, -0.32, 0), L.of(90, 94, 98, M.DiamondPlate))
	local dp = (hc * CF(0, 0.3, -0.3)).Position
	K:seg("SteamDuct", dp, V3(dp.X, V.H - 0.03, dp.Z), 0.6, L.of(186, 190, 194, M.Metal))
	local axis = (K.cf * pcf).XVector
	return lid, hinge, axis
end

-- 천장: 만국기 줄 (포차 분위기)
local function buntings(c: any)
	local K, V = c.K, c.V
	local cols = { rgb(214, 40, 40), rgb(248, 206, 40), rgb(40, 110, 200), rgb(250, 250, 248), rgb(40, 160, 80), rgb(240, 120, 30) }
	local y = V.H - 0.45
	local lines = 0
	for _, fz in { 0.28, 0.66 } do
		local z = V.z0 + V.D * fz
		local ok = true
		for k = 0, 10 do
			local x = V.x0 + 0.5 + (V.W - 1) * k / 10
			if not Common.ceilFree(K, x, z, 0.3) then
				ok = false
			end
		end
		if not ok then
			z = z + 1.2
		end
		local n = math.max(6, math.floor(V.W / 1.5))
		local pts = {}
		for i = 0, n do
			local x = V.x0 + 0.2 + (V.W - 0.4) * i / n
			local sag = math.sin(PI * ((i % 4) / 4)) * 0.35
			table.insert(pts, V3(x, y - sag, z))
		end
		for i = 1, n do
			K:seg("BuntingCord", pts[i], pts[i + 1], 0.03, L.of(236, 236, 230))
			local mid = (pts[i] + pts[i + 1]) / 2
			local cc = cols[(i + lines * 2) % #cols + 1]
			local fc = CF(mid - V3(0, 0.36, 0))
			K:box("BuntingFlag", V3(0.82, 0.62, 0.02), fc, col(cc, M.Fabric))
			if c.hi then
				K:box("BuntingStripe", V3(0.82, 0.12, 0.025), fc * CF(0, 0.05, 0), col(cols[(i + lines * 2 + 2) % #cols + 1], M.Fabric))
			end
		end
		lines += 1
	end
end

-- 천장: 종이 등 (스시 · 대게)
local function lantern(c: any, top: Vector3, dia: number, h: number, txt: string?, colr: Color3?)
	local K = c.K
	local cc = colr or rgb(200, 40, 30)
	local drop = 1.2
	K:seg("LanternCord", top, top - V3(0, drop, 0), 0.04, L.black)
	local ctr = top - V3(0, drop + h / 2, 0)
	K:vcyl("LanternCapTop", 0.14, dia * 0.5, CF(ctr + V3(0, h / 2, 0)), L.black)
	K:vcyl("LanternCapBot", 0.14, dia * 0.5, CF(ctr - V3(0, h / 2, 0)), L.black)
	local body = K:ell("LanternBody", V3(dia, h, dia), CF(ctr), { c = cc, m = M.Neon, t = 0.1 })
	for k = 1, 3 do
		K:ell("LanternRib", V3(dia * 1.01, 0.03, dia * 1.01), CF(ctr + V3(0, (k - 2) * h * 0.28, 0)), L.of(60, 30, 20))
	end
	if txt then
		K:text("LanternText", dia * 0.5, h * 0.7, CFrame.fromMatrix(ctr + V3(0, 0, dia * 0.5 + 0.01), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis), txt, { fg = rgb(20, 20, 20), font = F.GothamBlack, d = 0.01 })
	end
	return body
end

-- 스시 바 전용 ---------------------------------------------------------------------------------------------
local function woodTags(c: any, dcf: CFrame, w: number, h: number, items: { { string } })
	local K = c.K
	local wood = L.of(226, 200, 150, M.Wood)
	K:plate("TagRail", w + 0.2, 0.12, 0.1, dcf * CF(0, h / 2 + 0.05, 0), L.of(60, 44, 32, M.Wood))
	local n = #items
	local tw = math.min(0.62, (w - 0.1) / n - 0.08)
	for i, it in items do
		local x = -w / 2 + (w / n) * (i - 0.5)
		local tc = dcf * CF(x, 0, 0.04)
		K:plate("MenuTag", tw, h, 0.05, tc, wood)
		K:text("MenuTagName", tw * 0.7, h * 0.66, tc * CF(0, h * 0.1, 0.051), vertical(it[1]), { fg = rgb(30, 22, 16), font = F.GothamBlack, d = 0.005 })
		K:text("MenuTagPrice", tw * 0.9, h * 0.14, tc * CF(0, -h * 0.4, 0.051), it[2], { fg = rgb(170, 40, 30), font = F.GothamBold, d = 0.005 })
	end
end

local function waveArt(c: any, dcf: CFrame, w: number, h: number)
	local K = c.K
	K:plate("WaveFrame", w + 0.2, h + 0.2, 0.08, dcf, L.of(30, 24, 20, M.Wood))
	K:plate("WaveSky", w, h, 0.09, dcf, col(rgb(232, 222, 196)))
	local blue = col(rgb(28, 56, 110))
	for i = 1, 4 do
		local x = -w / 2 + w * (i - 0.5) / 4
		local s = 0.7 + (i % 2) * 0.4
		K:ell("WaveCrest", V3(w * 0.32 * s, h * 0.42 * s, 0.02), dcf * CF(x, -h * 0.22 + (i % 2) * h * 0.08, 0.095), blue)
		K:ell("WaveFoam", V3(w * 0.18 * s, h * 0.14 * s, 0.022), dcf * CF(x + w * 0.04, -h * 0.05 + (i % 2) * h * 0.1, 0.1), col(rgb(246, 244, 236)))
	end
	K:plate("WaveSea", w, h * 0.22, 0.1, dcf * CF(0, -h * 0.39, 0), blue)
	wdisc(K, "WaveSun", h * 0.2, 0.01, dcf * CF(w * 0.32, h * 0.28, 0), 0.09, col(rgb(210, 70, 50)))
	K:text("WaveText", w * 0.08, h * 0.6, dcf * CF(-w * 0.42, h * 0.12, 0.1), "海\n光\n安", { fg = rgb(40, 30, 24), font = F.GothamBlack, d = 0.005 })
end

local function luckyCat(K: any, pcf: CFrame, s: number)
	local white = L.of(246, 244, 238, M.SmoothPlastic)
	K:ell("CatBody", V3(0.5 * s, 0.6 * s, 0.42 * s), pcf * CF(0, 0.3 * s, 0), white)
	K:ball("CatHead", 0.46 * s, pcf * CF(0, 0.72 * s, 0.02 * s), white)
	for _, sx in { -1, 1 } do
		K:wedge("CatEar", V3(0.04 * s, 0.14 * s, 0.12 * s), pcf * CF(sx * 0.14 * s, 0.96 * s, 0) * ANG(0, PI / 2, 0), white)
	end
	K:ell("CatBib", V3(0.32 * s, 0.1 * s, 0.1 * s), pcf * CF(0, 0.5 * s, 0.2 * s), L.of(200, 30, 30))
	K:ball("CatBell", 0.1 * s, pcf * CF(0, 0.46 * s, 0.24 * s), L.goldMetal)
	local arm = K:ell("CatArm", V3(0.14 * s, 0.32 * s, 0.14 * s), pcf * CF(0.22 * s, 0.85 * s, 0.1 * s), white)
	K:disc("CatCoin", 0.3 * s, 0.04 * s, pcf * CF(-0.1 * s, 0.32 * s, 0.22 * s) * ANG(PI / 2, 0, 0), L.goldMetal)
	return arm
end

-- 주방 패스 창 (KitchenPass 를 같은 크기로 덮고 숨김): 주방 타일 · 나무 틀 · 주문표 레일 · 보온등 · 그릇 선반
local function passOverlay(c: any)
	local K, V = c.K, c.V
	for _, r in V.byName.KitchenPass or {} do
		if r.size.Z < 0.5 and r.size.X > 2 and math.abs(r.min.Z - V.z0) < 0.6 then
			local w, h = r.size.X, r.size.Y
			local dcf = CFrame.fromMatrix(V3(r.c.X, r.c.Y, r.max.Z), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
			K:free(function()
				K:box("PassSkin", r.size, CF(r.c), L.of(236, 234, 226, M.CeramicTiles))
				for i = 1, math.floor(h / 0.6) do
					K:plate("PassGrout", w, 0.025, 0.01, dcf * CF(0, -h / 2 + i * 0.6, 0), L.of(196, 194, 186))
				end
				for i = 1, math.floor(w / 0.9) do
					K:plate("PassGrout", 0.025, h, 0.01, dcf * CF(-w / 2 + i * 0.9, 0, 0), L.of(196, 194, 186))
				end
				local wood = L.of(64, 46, 32, M.Wood)
				K:plate("PassFrame", w + 0.36, 0.2, 0.14, dcf * CF(0, h / 2 + 0.08, 0), wood)
				for _, sx in { -1, 1 } do
					K:plate("PassFrame", 0.2, h + 0.1, 0.14, dcf * CF(sx * (w / 2 + 0.08), 0, 0), wood)
				end
				-- 보온등 · 주문표 레일
				local lamp = K:plate("PassHeatLamp", w - 0.6, 0.08, 0.1, dcf * CF(0, h / 2 - 0.12, 0), L.neon(rgb(255, 196, 130)))
				K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.7, Angle = 120, Color = rgb(255, 200, 150) })
				K:plate("TicketRail", w - 0.8, 0.07, 0.08, dcf * CF(0, h / 2 - 0.32, 0.02), L.of(200, 204, 208, M.Metal))
				local nT = if c.hi then 7 else 4
				for i = 1, nT do
					local x = -w / 2 + 0.6 + (w - 1.2) * (i - 0.5) / nT
					K:plate("OrderTicket", 0.32, 0.46, 0.012, dcf * CF(x, h / 2 - 0.6, 0.1) * ANG(0, 0, (rnd(c.seed, i) - 0.5) * 0.12), L.of(250, 248, 240))
				end
				-- 안쪽 그릇 선반 (벽면에 납작)
				K:plate("PassShelf", w - 0.6, 0.07, 0.22, dcf * CF(0, -h / 2 + 1.2, 0), L.of(200, 204, 208, M.Metal))
				local nB = math.floor((w - 1) / 0.7)
				for i = 1, nB do
					local x = -w / 2 + 0.8 + (w - 1.6) * (i - 0.5) / nB
					K:ell("PassBowl", V3(0.42, 0.18, 0.16), dcf * CF(x, -h / 2 + 1.33, 0.1), if i % 3 == 0 then L.of(40, 36, 34) else L.of(238, 236, 228))
				end
			end)
			hideRec(K, r)
		end
	end
end

-- 노렌 (맵 Noren 을 같은 자리에서 갈라진 쪽빛 천 + 흰 글자로)
local function norenOver(c: any)
	local K, V = c.K, c.V
	local chars = { "寿", "司", "海", "光", "酒", "肴", "旬", "魚" }
	local ci = 0
	for _, r in V.byName.Noren or {} do
		if r.size.Z < 0.3 and r.size.X > 1.5 then
			hideRec(K, r)
			local w, h = r.size.X, r.size.Y
			local dcf = CFrame.fromMatrix(V3(r.c.X, r.c.Y, r.max.Z), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
			K:free(function()
				K:cyl("NorenRod", w + 0.3, 0.1, dcf * CF(0, h / 2 + 0.05, 0.04), L.of(70, 50, 34, M.Wood))
				local n = math.max(2, math.floor(w / 1.4))
				local pw = w / n
				for i = 1, n do
					local x = -w / 2 + pw * (i - 0.5)
					local pc = dcf * CF(x, 0, -0.02)
					K:plate("NorenPanel", pw - 0.07, h, 0.03, pc, L.of(28, 38, 78, M.Fabric))
					K:plate("NorenHem", pw - 0.07, 0.06, 0.035, pc * CF(0, -h / 2 + 0.03, 0), L.of(20, 28, 60, M.Fabric))
					ci += 1
					K:text("NorenChar", math.min(pw * 0.6, h * 0.7), h * 0.7, pc * CF(0, -0.02, 0.031), chars[(ci - 1) % #chars + 1], { fg = rgb(244, 240, 228), font = F.GothamBlack, d = 0.004 })
				end
			end)
		end
	end
end

-- 사케 통 (고모다루) 더미: 짚 감은 흰 통 + 줄 + 붉은 글자
local function sakeBarrels(c: any, pcf: CFrame)
	local K = c.K
	local straw = L.of(232, 222, 196, M.Fabric)
	local rope = L.of(150, 110, 70, M.Fabric)
	local pos = { { -0.62, 0 }, { 0.62, 0 }, { 0, 1.2 } }
	local names = { "大漁", "光安", "酒" }
	for i, p in pos do
		local base = pcf * CF(p[1], p[2], 0)
		K:vcyl("SakeBarrel", 1.15, 1.2, base * CF(0, 0.6, 0), straw)
		K:vcyl("SakeBarrelLid", 0.06, 1.1, base * CF(0, 1.18, 0), L.of(200, 170, 120, M.Wood))
		for _, y in { 0.15, 0.6, 1.05 } do
			K:vcyl("SakeBarrelRope", 0.07, 1.24, base * CF(0, y, 0), rope)
		end
		ktext(K, "SakeBarrelLabel", 0.5, 0.7, base * CF(0, 0.6, 0.61), vertical(names[i]), { fg = rgb(190, 30, 30), font = F.GothamBlack, d = 0.01 })
	end
end

-- 블루투스 스피커 (BGM 바꾸기): 나무 몸체 + 그릴 + LCD
local function bgmSpeaker(c: any, dcf: CFrame): (BasePart, TextLabel)
	local K = c.K
	K:plate("SpeakerShelf", 1.3, 0.08, 0.6, dcf * CF(0, -0.5, 0), L.of(84, 60, 42, M.Wood))
	K:plate("SpeakerBody", 1.1, 0.9, 0.45, dcf * CF(0, -0.02, 0.05), L.of(120, 86, 56, M.Wood))
	wdisc(K, "SpeakerGrille", 0.6, 0.02, dcf * CF(-0.18, -0.02, 0.05), 0.45, L.of(40, 38, 36, M.Fabric))
	local scr, lbl = K:text("SpeakerLCD", 0.36, 0.24, dcf * CF(0.32, 0.12, 0.5), "♪ 시티팝", { bg = rgb(20, 40, 60), fg = rgb(140, 220, 255), glow = 1.2, font = F.GothamBold, d = 0.01 })
	K:plate("SpeakerKnob", 0.12, 0.12, 0.04, dcf * CF(0.32, -0.2, 0.5), L.chrome)
	return scr, lbl
end

-- 생맥주 · 하이볼 포스터 (스시 바)
local function beerPoster(c: any, dcf: CFrame, w: number, h: number)
	local K = c.K
	K:plate("BeerPosterBack", w, h, 0.03, dcf, col(rgb(246, 238, 220)))
	wdisc(K, "BeerPosterSun", w * 0.5, 0.008, dcf * CF(0, h * 0.18, 0), 0.03, col(rgb(206, 50, 38)))
	local mc = dcf * CF(0, h * 0.12, 0.04)
	K:plate("BeerMug", w * 0.26, h * 0.28, 0.01, mc, col(rgb(236, 170, 40)))
	K:plate("BeerFoam", w * 0.3, h * 0.07, 0.012, mc * CF(0, h * 0.16, 0), L.white)
	K:plate("BeerHandle", w * 0.06, h * 0.16, 0.01, mc * CF(w * 0.17, 0, 0), col(rgb(220, 220, 214)))
	K:text("BeerPosterText", w * 0.9, h * 0.3, dcf * CF(0, -h * 0.28, 0.04), "생맥주 6,000\n하이볼 9,000", { fg = rgb(40, 30, 24), font = F.GothamBlack, d = 0.005 })
end

-- 도자기 선반 (도쿠리 · 오초코 · 젓가락 받침)
local function ceramicShelf(c: any, dcf: CFrame, w: number)
	local K = c.K
	local at2 = Props.shelf(K, dcf, w, { depth = 0.6, look = L.of(84, 60, 42, M.Wood), bracket = L.blackMetal, thick = 0.1 })
	local n = math.max(3, math.floor(w / 0.45))
	for i = 1, n do
		local x = -w / 2 + 0.25 + (w - 0.5) * (i - 0.5) / n
		local b = at2 * CF(x, 0, -0.05)
		local glaze = if i % 3 == 0 then L.of(40, 60, 110) elseif i % 3 == 1 then L.of(236, 232, 222) else L.of(150, 110, 80)
		if i % 2 == 1 then
			K:vcyl("Tokkuri", 0.42, 0.26, b * CF(0, 0.21, 0), glaze)
			K:vcyl("TokkuriNeck", 0.16, 0.1, b * CF(0, 0.5, 0), glaze)
		else
			K:vcyl("Ochoko", 0.14, 0.18, b * CF(-0.08, 0.07, 0), glaze)
			K:vcyl("Ochoko", 0.14, 0.18, b * CF(0.1, 0.07, 0.05), glaze)
		end
	end
end

local function sushiExtras(c: any)
	local K, V = c.K, c.V
	passOverlay(c)
	norenOver(c)
	-- 사케 통 (입구 쪽 옆벽 앞)
	local pcf = floorOnWall(K, { "left", "right" }, V3(2.6, 2.4, 1.3), { left = -(V.z1 - 3.2), right = V.z1 - 3.2 }, 0.1)
	if pcf then
		sakeBarrels(c, pcf)
	end
	-- 대나무 화분
	local pcf2 = floorOnWall(K, { "right", "left", "back" }, V3(1.4, 5.2, 1.4), { left = -(V.z1 - 3), right = V.z1 - 3, back = V.x1 * 0.6 }, 0.05)
	if pcf2 then
		Props.floorPlant(K, pcf2, { kind = "bamboo", h = 5.0, dia = 1.2 })
	end
	-- 옆벽: 생맥주 포스터 · 도자기 선반
	local wn, u = findWall(K, { "left", "right" }, 1.7, 1.7, 4.0, 6.7, V3(0, 0, V.z1 - 4), 0.6)
	if wn and u then
		beerPoster(c, V:wall(wn, u, 5.35, WALL_OFF), 1.7, 2.5)
	end
	local wn2, u2, w2 = findWall(K, { "right", "left" }, 2.4, 3.2, 3.6, 4.6, V3(0, 0, (V.z0 + V.z1) / 2), 0.8)
	if wn2 and u2 and w2 then
		ceramicShelf(c, V:wall(wn2, u2, 4.0, WALL_OFF), w2)
	end
	-- 냉장고 위 마네키네코
	if c.fridgeTop then
		luckyCat(K, c.fridgeTop * CF(-0.6, 0, 0.2), 1.0)
	end
end

local function sushiDecor(c: any)
	local K, V, th = c.K, c.V, c.th
	-- 뒷벽 위: 사케 병 선반 (패스 위 6.8 ~)
	local pass = V.byName.KitchenPass and V.byName.KitchenPass[1]
	local y0 = if pass then pass.max.Y + 0.7 else 6.9
	local spans = freeSpans(K, "back", y0, y0 + 1.6, 1.0)
	local placedShelf = false
	for _, s in spans do
		if s[2] - s[1] >= 3 and not placedShelf then
			local w = math.min(s[2] - s[1] - 0.3, 6.5)
			local u = (s[1] + s[2]) / 2
			claim(K, "back", u - w / 2, u + w / 2, y0, y0 + 1.6)
			for tier = 0, 1 do
				local at2 = Props.shelf(K, V:wall("back", u, y0 + 0.1 + tier * 0.85, 0), w, { depth = 0.7, look = L.of(84, 60, 42, M.Wood), bracket = L.blackMetal, thick = 0.1 })
				local n = math.floor((w - 0.4) / 0.42)
				for j = 1, n do
					local x = -w / 2 + 0.25 + (w - 0.5) * (j - 0.5) / n
					local kind = if (j + tier) % 4 == 0 then "beer" else "sake"
					if tier == 1 and j % 2 == 0 then
						bottle(K, at2 * CF(x, 0, -0.05), "sake", c.hi)
					elseif tier == 0 then
						bottle(K, at2 * CF(x, 0, -0.05), kind, c.hi)
					end
				end
			end
			placedShelf = true
		end
	end
	-- 나무 메뉴패 (옆벽)
	local tags = { { "광어", "2,500" }, { "연어", "2,500" }, { "참치", "4,000" }, { "장어", "3,500" }, { "새우", "2,500" }, { "한치", "3,000" }, { "성게", "6,000" }, { "연어알", "4,500" } }
	local wn, u, w = findWall(K, { "left", "right" }, 4.0, 6.0, 6.4, 8.4, nil, 0.6)
	if wn and u and w then
		local n = math.min(#tags, math.floor(w / 0.72))
		local sub = {}
		for i = 1, n do
			table.insert(sub, tags[i])
		end
		woodTags(c, V:wall(wn, u, 7.3, WALL_OFF), w, 1.8, sub)
	end
	-- 파도 그림
	local wn2, u2, w2 = findWall(K, { "right", "left" }, 3.6, 4.6, 4.4, 7.2, nil, 0.6)
	if wn2 and u2 and w2 then
		waveArt(c, V:wall(wn2, u2, 5.8, WALL_OFF), w2, 2.4)
	end
	-- 종이 등 (카운터 위): 형광등 · 에어컨 피해서 몇 줄 앞뒤로 시도
	local g = V.counters[1]
	local nL = 0
	c.lanterns = {}
	if g then
		local gz = (g.min.Z + g.max.Z) / 2
		for _, dz in { 1.4, -1.0, 2.2, -1.8, 0.4 } do
			if nL >= 3 then
				break
			end
			for k = 1, 3 do
				local p = V3(g.min.X + (g.max.X - g.min.X) * k / 4, V.H, gz + dz)
				if nL < 3 and Common.ceilFree(K, p.X, p.Z, 0.6) then
					local body = lantern(c, p, 0.9, 1.3, if nL == 1 then "寿司" elseif nL == 2 then "酒" else nil, rgb(214, 54, 36))
					table.insert(c.lanterns, { p = body, c = body.Color })
					if nL == 0 then
						local l = K:light(body, "PointLight", { Range = 10, Brightness = 0.8, Color = rgb(255, 170, 120) })
						if l then
							c.lanternLight = l
						end
					end
					Common.useCeil(K, p.X, p.Z)
					nL += 1
				end
			end
		end
	end
	-- BGM 스피커 (프롬프트 자리 먼저)
	local wn, u = findWall(K, { "left", "right" }, 1.4, 1.4, 4.2, 5.7, V3(0, 0, (V.z0 + V.z1) / 2 - 2.5), 0.9, function(wn0: string, u0: number)
		return promptWallOK(K, wn0, u0, 4.8, 0.5)
	end)
	if wn and u then
		local scr, lbl = bgmSpeaker(c, V:wall(wn, u, 5.1, WALL_OFF))
		local songs = { { t = "♪ 시티팝" }, { t = "♪ 재즈 피아노" }, { t = "♪ 엔카" }, { t = "♪ 로파이" } }
		Interact.cycle(K, scr, songs, {
			action = "음악 바꾸기",
			object = "BGM 스피커",
			on = function(_i: number, it: any)
				if lbl.Parent then
					lbl.Text = it.t
				end
			end,
		})
		at(K, "speaker", wn, u)
	end
	if c.lanterns and #c.lanterns > 0 then
		local wn2, u2 = findWall(K, { "right", "left" }, 0.9, 0.9, 3.8, 5.2, V3(0, 0, (V.z0 + V.z1) / 2), 0.6, function(wn0: string, u0: number)
			return promptWallOK(K, wn0, u0, 4.4, 0.4)
		end)
		if wn2 and u2 then
			local dcf = V:wall(wn2, u2, 4.4, WALL_OFF)
			local plate = Props.switchPlate(K, dcf, 1)
			ktext(K, "LanternSwitchLabel", 0.6, 0.18, dcf * CF(0, 0.42, 0), "등불", { fg = rgb(60, 40, 30), bg = rgb(236, 226, 206), d = 0.02 })
			Interact.toggle(K, plate, {
				object = "종이 등불",
				state = true,
				onText = "끄기",
				offText = "켜기",
				on = function(on: boolean)
					for _, ln in c.lanterns do
						if ln.p.Parent then
							ln.p.Material = if on then M.Neon else M.SmoothPlastic
							ln.p.Color = if on then ln.c else ln.c:Lerp(rgb(60, 30, 20), 0.5)
						end
					end
					if c.lanternLight then
						c.lanternLight.Enabled = on
					end
				end,
			})
		end
	end
	-- 원산지 · 와이파이
	local wn3, u3, w3 = findWall(K, { "left", "right", "back" }, 1.8, 1.8, 4.2, 6.6, nil, 0.6)
	if wn3 and u3 and w3 then
		originBoard(c, V:wall(wn3, u3, 5.4, WALL_OFF), 1.8, 2.4)
	end
	local _ = th
end

-- 짓기 --------------------------------------------------------------------------------------------------------
function T.build(K: any, V: any, S: any)
	local th = (S and S.th) or themeFor(V)
	local c: any = {
		K = K,
		V = V,
		S = S,
		th = th,
		seed = th.seed,
		hi = K.detail == "high",
		lo = K.detail == "low",
		tankLeds = {},
		tankLights = {},
		tankState = { air = true, light = true },
		steamSrc = {},
	}
	local function step(name: string, fn: () -> ())
		local ok, err = pcall(fn)
		if not ok then
			K:note("seafood." .. name .. " error: " .. tostring(err))
		end
	end
	step("stools", function()
		stoolsOver(c)
	end)
	step("walls", function()
		wallFinish(c)
	end)
	-- 1) 수족관
	local tks = {}
	step("tanks", function()
		tks = tankSets(V)
		for _, t in tks do
			tankOverlay(c, t)
		end
	end)
	-- 2) 주방 · 카운터
	step("kitchen", function()
		kitchen(c)
	end)
	step("apron", function()
		local g = V.counters[1]
		if th.kind == "sushi" or not g or not c.hi then
			return
		end
		-- 카운터의 방 가운데 쪽 끝 옆 (뒷벽 우선)
		local endX = if math.abs(g.min.X) < math.abs(g.max.X) then g.min.X - 1.0 else g.max.X + 1.0
		local wn, u = findWall(K, { "back" }, 1.7, 1.7, 2.2, 6.0, endX, 0.5)
		if wn and u then
			local bcf = V:wall(wn, u, 0, 0.55)
			local okBoots = K:spot(bcf * CF(0, 0, 0), V3(1.0, 1.3, 0.85), 0.05, "seafood")
			apronStation(c, V:wall(wn, u, 4.4, WALL_OFF), if okBoots then bcf else nil)
			at(K, "apron", wn, u)
		end
	end)
	local bigWalls = { "left", "right" }
	if rnd(c.seed, 3) > 0.5 then
		bigWalls = { "right", "left" }
	end
	local isSushi = th.kind == "sushi"
	-- 3) 바닥 소품 (벽 자리를 먼저 차지)
	local fridgeDoors = nil
	step("fridge", function()
		local nd = if V.W > 30 then 2 else 1
		local function handlesOK(p: CFrame, n: number): boolean
			local w = n * 2.0 + 0.3
			for i = 1, n do
				local x0 = -w / 2 + 0.15 + (i - 1) * 2.0
				if not Interact.canPrompt(K, (p * CF(x0 + 2.0 - 0.22, 3.0, 1.15)).Position) then
					return false
				end
			end
			return true
		end
		local tries: { any } = { { n = nd, t = true }, { n = 1, t = true } }
		for _, try in tries do
			local n: number = try.n
			local size = V3(n * 2.0 + 0.3, 6.3, 2.0)
			local pcf = floorOnWall(K, { "back", bigWalls[2], bigWalls[1] }, size, { back = V.x1 * 0.4, left = V.z0 + 3, right = V.z0 + 3 }, 0.1, if try.t then function(p: CFrame)
				return handlesOK(p, n)
			end else nil)
			if pcf then
				local doors = drinkFridge(c, pcf, n)
				c.fridgeTop = pcf * CF(0, 6.3, 0)
				fridgeDoors = doors
				at(K, "fridge", nil, nil, pcf.Position)
				break
			end
		end
	end)
	step("floorProps", function()
		if isSushi then
			return
		end
		-- 종류별 큰 소품
		if th.kind == "jjim" then
			local pcf = floorOnWall(K, { bigWalls[2], bigWalls[1], "back" }, V3(3.6, 3.9, 1.7), { left = 0, right = 0, back = V.x1 * 0.3 }, 0.15)
			if pcf then
				clamRack(c, pcf, 3.6)
				at(K, "clamRack", nil, nil, pcf.Position)
			end
		elseif th.kind == "crab" then
			local size = V3(2.9, 6.3, 1.9)
			local nearS = { left = V.z0 + 4, right = V.z0 + 4, back = V.x1 * 0.2 }
			local pcf = floorOnWall(K, { bigWalls[2], bigWalls[1], "back" }, size, nearS, 0.15, function(p: CFrame)
				return Interact.canPrompt(K, (p * CF(-0.64, 3.3, 0.2)).Position)
			end)
			if not pcf then
				pcf = floorOnWall(K, { bigWalls[2], bigWalls[1], "back" }, size, nearS, 0.15)
			end
			if pcf then
				local door, hinge, axis = crabSteamer(c, pcf)
				c.steamer = { door = door, hinge = hinge, axis = axis }
				at(K, "steamer", nil, nil, pcf.Position)
			end
		end
		-- 스티로폼 상자 (탱크 가까운 벽 앞 · 뒤 구석)
		local near = if tks[1] then (tks[1].min + tks[1].max) / 2 else V3(V.x1, 0, V.z1)
		local pcf = floorOnWall(K, { "right", "left", "back" }, V3(2.1, 2.7, 1.4), near, 0.1)
		if pcf then
			styroStack(c, pcf, if c.hi then 3 else 2)
		end
		local pcf2 = floorOnWall(K, { "back", "left", "right" }, V3(2.2, 0.9, 2.2), { back = (V.x0 + V.x1) / 2 + 2, left = V.z0 + 2, right = V.z0 + 2 }, 0.1)
		if pcf2 then
			basin(c, pcf2 * CF(0, 0, 0), if th.kind == "jjim" then "clam" else "octopus")
		end
		-- 개업 화분 (입구 쪽 구석, 창 띠 앞은 피함)
		local pcf3 = floorOnWall(K, { "left", "right" }, V3(1.4, 3.4, 1.4), { left = -(V.z1 - 3), right = V.z1 - 3 }, 0.05)
		if pcf3 then
			giftPlant(c, pcf3)
		end
	end)
	step("tankSwitch", function()
		-- (a) 수족관 조명 · 기포기 스위치
		if #tks > 0 then
			local near = (tks[1].min + tks[1].max) / 2
			local wn, u = findWall(K, { "right", "left", "back" }, 1.0, 1.0, 3.6, 5.2, near, 0.6, function(wn0: string, u0: number)
				return promptWallOK(K, wn0, u0, 4.4, 0.5)
			end)
			if wn and u then
				local sw = tankSwitchBox(c, V:wall(wn, u, 4.4, WALL_OFF))
				c.conduitAt = { wn = wn, u = u }
				local st = c.tankState
				Interact.toggle(K, sw, {
					object = "수족관 조명 · 기포기",
					state = true,
					onText = "끄기",
					offText = "켜기",
					on = function(on: boolean)
						st.air = on
						for _, l in c.tankLights do
							l.Enabled = on
						end
						for _, led in c.tankLeds do
							if led.p.Parent then
								led.p.Material = if on then M.Neon else M.SmoothPlastic
								led.p.Color = if on then led.c else rgb(70, 90, 100)
							end
						end
					end,
				})
				at(K, "tankSwitch", wn, u)
			end
		end
	end)
	-- 4) 벽 계획: A = 메뉴 벽, B = 맞은편 옆벽, back = 뒷벽 (카운터 · 냉장고 남은 자리)
	local A, B = bigWalls[1], bigWalls[2]
	local pFront = V3(0, 0, V.z1 - 3.5)
	local pBack = V3(V.x1 * 0.25, 0, V.z0 + 3)
	local pMid = V3(0, 0, (V.z0 + V.z1) / 2 + 0.5)
	step("menu", function()
		local w = math.min(9, math.max(6, V.D * 0.5))
		local wn, u, ww = findWall(K, { A, B }, 6.0, w, 3.95, 7.75, pMid, 0.6)
		if wn and u and ww then
			menuLightbox(c, V:wall(wn, u, 5.85, WALL_OFF), ww, 3.4)
			at(K, "menu", wn, u)
		end
	end)
	step("tv", function()
		if isSushi then
			return
		end
		local wn, u, w = findWall(K, { B, "back", A }, 3.0, 3.4, 5.95, 7.9, { left = -3, right = 3, back = V.x1 * 0.3 }, 0.8, function(wn0: string, u0: number)
			return promptWallOK(K, wn0, u0, 6.9, 0.6)
		end)
		if wn and u and w then
			local scr, lbl = tvSet(c, V:wall(wn, u, 6.9, WALL_OFF), w)
			lbl.Text = TV_CH[1].text
			lbl.BackgroundColor3 = TV_CH[1].c
			Interact.cycle(K, scr, TV_CH, {
				action = "채널 돌리기",
				object = "TV",
				on = function(_i: number, item: any)
					if lbl.Parent then
						lbl.Text = item.text
						lbl.BackgroundColor3 = item.c
					end
				end,
			})
			at(K, "tv", wn, u)
		end
	end)
	step("fan", function()
		if isSushi or not budget(K, 40) then
			return
		end
		local wn, u = findWall(K, { B, A, "back" }, 1.8, 1.8, 6.4, 8.9, pMid, 1.2, function(wn0: string, u0: number)
			return promptWallOK(K, wn0, u0 + 0.24, 6.6, 0.3)
		end)
		if wn and u then
			c.fanSpot = { wn = wn, u = u }
		end
	end)
	step("boards", function()
		if isSushi then
			sushiDecor(c)
			sushiExtras(c)
			return
		end
		local wn, u, w = findWall(K, { B, A, "back" }, 3.0, 3.8, 4.1, 7.1, pMid, 0.6)
		if wn and u and w then
			sigaBoard(c, V:wall(wn, u, 5.6, WALL_OFF), w, 2.5)
		end
		local wn3, u3 = findWall(K, { B, "back", A }, 2.4, 2.4, 4.1, 7.1, pBack, 0.6)
		if wn3 and u3 then
			seasonChart(c, V:wall(wn3, u3, 5.6, WALL_OFF), 2.4, 2.8)
		end
		local wn4, u4 = findWall(K, { B, A, "back" }, 1.7, 1.7, 4.0, 6.8, pFront, 0.6)
		if wn4 and u4 then
			sojuPoster(c, V:wall(wn4, u4, 5.4, WALL_OFF), 1.7, 2.5)
		end
		local wn2, u2 = findWall(K, { A, B, "back" }, 1.9, 1.9, 4.2, 6.9, pBack, 0.6)
		if wn2 and u2 then
			originBoard(c, V:wall(wn2, u2, 5.55, WALL_OFF), 1.9, 2.5)
		end
		local wn5, u5, w5 = findWall(K, { "back", B, A }, 3.6, 5.0, 4.5, 7.25, V3((V.x0 + V.x1) / 2 + 2, 0, V.z0), 0.6)
		if wn5 and u5 and w5 then
			bridgeArt(c, V:wall(wn5, u5, 5.85, WALL_OFF), w5, 2.4)
		end
	end)
	-- 5) 위쪽 벽 (7.5 ~ 9.6): TV · 선풍기 (프롬프트 자리) 먼저, 그다음 사진 · 어탁 · 그물 · 풍어기
	local yA, yB = 7.55, math.min(V.H - 0.3, 9.6)
	step("upper", function()
		if yB - yA < 1.4 then
			return
		end
		local mid = (yA + yB) / 2
		local hh = yB - yA
		if th.kind == "crab" then
			local wn, u, w = findWall(K, { A, B }, 3.4, 3.6, yA - 0.4, yB + 0.1, pMid, 0.8)
			if wn and u and w then
				crabSign(c, V:wall(wn, u, mid, WALL_OFF), w)
			end
		end
		if th.kind == "squid" then
			local wn, u, w = findWall(K, { B, A }, 3.0, 5.0, yA - 0.6, yB, pMid, 0.8)
			if wn and u and w then
				squidLine(c, V:wall(wn, u, yB - 0.2, WALL_OFF), w)
			end
		end
		if isSushi then
			return
		end
		if th.net then
			local wn, u, w = findWall(K, { B, A, "back" }, 3.6, 5.2, yA, yB, pMid, 0.8)
			if wn and u and w then
				netDecor(c, V:wall(wn, u, mid, WALL_OFF), w, hh - 0.2)
			end
		end
		local wn, u, w = findWall(K, { A, B, "back" }, 2.6, 3.2, yA, yB, pFront, 0.8)
		if wn and u and w then
			bigFlag(c, V:wall(wn, u, mid - 0.05, WALL_OFF), w, hh - 0.35, if th.kind == "crab" then "만선" else "풍어")
		end
		local nPh = if c.hi then 4 else 2
		for i = 1, nPh do
			local wn2, u2 = findWall(K, { A, B, "back" }, 1.6, 1.6, yA, yB, if i % 2 == 1 then pMid else pBack, 0.8)
			if wn2 and u2 then
				if i == 2 then
					gyotaku(c, V:wall(wn2, u2, mid, WALL_OFF), 1.6, hh - 0.35)
				else
					fishPhoto(c, V:wall(wn2, u2, mid, WALL_OFF), 1.6, math.min(1.5, hh - 0.25), i)
				end
			end
		end
	end)
	step("clock", function()
		local wn, u = findWall(K, { "back", A, B }, 1.6, 1.6, 6.9, 8.6, { back = V.x1 * 0.45, left = 0, right = 0 }, 0.8)
		if wn and u then
			local dcf = V:wall(wn, u, 7.75, WALL_OFF)
			local hr, mn = Props.clock(K, dcf, 1.4, if th.kind == "sushi" then { frame = L.of(84, 60, 42, M.Wood) } else nil)
			Interact.clock(K, hr, mn, dcf, 1.4)
		end
	end)
	-- 6) 작은 안내판
	step("info", function()
		local plates = {
			{ "Wi-Fi  " .. th.wifi .. "\nPW  0516" .. string.format("%04d", c.seed % 10000), rgb(255, 255, 255), rgb(36, 40, 48), 1.7, 0.7 },
			{ "카드 · 제로페이 · 동백전\n결제 가능합니다", rgb(30, 30, 40), rgb(250, 230, 120), 1.9, 0.7 },
			{ if isSushi then "런치 11:30 - 15:00\n디너 17:00 - 22:00" else "포장 · 택배 가능\n단체 예약 환영", WHITE, th.accent, 1.8, 0.7 },
		}
		for i, p in plates do
			local wn, u = findWall(K, { "back", A, B }, p[4], p[4], 3.9, 4.8, { back = -2 + i * 2.2, left = 4 - i * 2, right = -4 + i * 2 }, 0.6)
			if wn and u then
				infoPlate(c, V:wall(wn, u, 4.35, WALL_OFF), p[4], p[5], p[1], p[2], p[3])
			end
		end
		local wn, u = findWall(K, { "back", B, A }, 1.2, 1.2, 4.6, 6.4, { back = 2, left = 0, right = 0 }, 0.6)
		if wn and u then
			hygieneBadge(c, V:wall(wn, u, 5.5, WALL_OFF))
		end
	end)
	-- 7) 천장
	step("ceiling", function()
		-- 진미 (wood) · 오징어집: 집어등 줄, 조개찜 · 포차: 만국기, 그 밖 횟집 · 대게: 그물 + 부표
		local lamps = 0
		if th.variant == "wood" or th.kind == "squid" then
			lamps = fishingLamps(c)
		end
		if th.flags then
			buntings(c)
		elseif (th.kind == "hoe" or th.kind == "crab") and (lamps == 0 or V.W > 40) then
			ceilingNet(c)
		end
		if th.kind == "crab" and budget(K, 30) then
			local n = 0
			for _, fx in { 0.3, 0.7 } do
				local p = V3(V.x0 + V.W * fx, V.H, V.z0 + V.D * 0.42)
				if Common.ceilFree(K, p.X, p.Z, 0.7) then
					lantern(c, p, 1.0, 1.2, if n == 0 then "대게" else "킹크랩", rgb(220, 50, 30))
					Common.useCeil(K, p.X, p.Z)
					n += 1
				end
			end
		end
	end)
	-- 8) 김
	step("steam", function()
		steam(c, c.steamSrc)
	end)
	-- 8b) 스위치 박스 전선관: 위 벽이 비어 있을 때만 천장까지 (TV · 액자 뒤를 지나지 않게)
	step("conduit", function()
		local ca = c.conduitAt
		if ca and not usedHit(K, ca.wn, ca.u - 0.15, ca.u + 0.15, 5.25, V.H) then
			local top = V:wall(ca.wn, ca.u, 5.05, WALL_OFF + 0.1)
			local yTop = V.H - 0.15
			K:seg("TankConduit", top.Position, V3(top.Position.X, yTop, top.Position.Z), 0.12, L.of(226, 226, 222, M.Plastic))
			for _, yy in { 6.4, 8.2 } do
				if yy < yTop - 0.3 then
					K:plate("ConduitClip", 0.2, 0.1, 0.16, V:wall(ca.wn, ca.u, yy, WALL_OFF), L.of(200, 200, 196, M.Plastic))
				end
			end
		end
	end)
	-- 9) 상호작용
	step("interact", function()
		-- (c) 냉장고 문
		if fridgeDoors then
			for _, dd in fridgeDoors do
				Interact.swing(K, dd.m, dd.hinge, Vector3.yAxis, -1.7, { object = if isSushi then "사케 냉장고" else "주류 냉장고", openText = "문 열기", closeText = "문 닫기" })
			end
		end
		-- (d) 대게 찜기 문
		if c.steamer and c.steamer.door and c.steamer.hinge then
			Interact.swing(K, c.steamer.door, c.steamer.hinge, c.steamer.axis or Vector3.xAxis, -1.25, { object = "대게 찜통", openText = "뚜껑 열기", closeText = "뚜껑 닫기" })
		end
		-- (e) 선풍기 (상호작용이 4개 미만일 때만)
		if c.fanSpot and #K.prompts < 4 then
			local fs = c.fanSpot
			local st, knob = wallFan(c, V:wall(fs.wn, fs.u, 8.3, WALL_OFF))
			Interact.toggle(K, knob, {
				object = "벽걸이 선풍기",
				state = true,
				onText = "끄기",
				offText = "켜기",
				on = function(on: boolean)
					st.on = on
				end,
			})
			at(K, "fan", fs.wn, fs.u)
		end
	end)
end

return T
