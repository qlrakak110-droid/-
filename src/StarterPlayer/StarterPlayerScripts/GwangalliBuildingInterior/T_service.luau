--!strict
-- GwangalliBuildingInterior/T_service: 유형 (lobby residence realty laundry office bank clinic academy) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (프런트 · 우편함 · 택배함 · 매물판 · 컨베이어 · 간판 · 소품 · 상호작용)
--
-- 세부 유형:
--   lobby     hotel (맵 프런트 Ledge/FrontPanel/WorkDesk 가 있는 호텔 로비) · motel (프런트 없는 좁은 모텔 로비)
--   residence 아파트 · 오피스텔 공동현관 로비 (Mailboxes = 게임플레이 우편함, 엘리베이터는 그대로)
--   realty    공인중개사 (상담 책상 · 매물판 · 수영구 지도 · 등록증 · 정수기 · 손님 소파)
--   laundry   세탁소 (회전 컨베이어 행거 · 다림질대 · 스팀다리미 · 수선 미싱 · 요금표)
--   office / bank / clinic / academy : 같은 '사무 공간' 뼈대 + 유형별 간판 · 게시물 · 소품 (맵에 아직 없음, 기본만 탄탄히)
-- 맵 게임플레이 파트(Ledge · WorkDesk · DeskBell · Mailboxes · Seat · TableTop ...)는 같은 자세 · 같은 범위로만 덮어씌우고
-- 숨김. 엘리베이터 (ElevatorDoor/Jamb/Head/FloorIndicator/CallButton) 는 손대지 않고 주변 벽 마감만.
-- 새 바닥 소품은 canPlace (K:spot 과 같은 검사 + 맵 파트) 로 자리를 확인하고 예약, 벽 소품은 K.wallUsed 로 서로 피함.
-- Common.fixtures (스위치 · 콘센트 · 시계 · 등록증) 는 큰 벽 소품을 놓은 뒤에 부름 (S.skip.fixtures).

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))

local Lighting = game:GetService("Lighting")

local T = {}
T.types = { "lobby", "residence", "realty", "laundry", "office", "bank", "clinic", "academy" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local C = Color3.fromRGB
local F = Enum.Font
local WHITE = C(255, 255, 255)
local INK = C(28, 28, 32)

---------------------------------------------------------------------------------------------------
-- 0. 기본 도구
---------------------------------------------------------------------------------------------------

local function hashStr(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	return h
end

local function mkRng(seed: any): () -> number
	local s = (if type(seed) == "number" then math.floor(seed) else hashStr(tostring(seed))) % 2147483646 + 1
	return function(): number
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

local function pickR(rng: () -> number, list: { any }): any
	return list[math.floor(rng() * #list) + 1]
end

local function lk(c: Color3, m: Enum.Material?, extra: { [string]: any }?): any
	local t: any = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end

local function darker(c: Color3, t: number): Color3
	return c:Lerp(C(0, 0, 0), t)
end
local function lighter(c: Color3, t: number): Color3
	return c:Lerp(WHITE, t)
end

-- 표시면 프레임: p 에서 n 쪽(보는 사람 쪽)을 향함
local function dcfAt(p: Vector3, n: Vector3): CFrame
	local x = Vector3.yAxis:Cross(n)
	if x.Magnitude < 1e-3 then
		x = Vector3.xAxis
	end
	x = x.Unit
	local y = n:Cross(x).Unit
	return CFrame.fromMatrix(p, x, y, n)
end

-- 소품 프레임: 바닥 점 p, 정면 face
local function pcfAt(p: Vector3, face: Vector3): CFrame
	return CFrame.lookAt(p, p - face)
end

-- 윗면 프레임 (pcf 를 위로 올린 것): 책상 위 물건
local function topAt(x: number, y: number, z: number, face: Vector3): CFrame
	return CFrame.lookAt(V3(x, y, z), V3(x, y, z) - face)
end

local function snap(v: Vector3): Vector3
	if math.abs(v.X) >= math.abs(v.Z) then
		return V3(if v.X >= 0 then 1 else -1, 0, 0)
	end
	return V3(0, 0, if v.Z >= 0 then 1 else -1)
end

local function note(K: any, s: string)
	K:note("service: " .. s)
end

local function yieldy(K: any)
	if K.sliceT and os.clock() - K.sliceT > (K.slice or 0.0025) then
		task.wait()
		K.sliceT = os.clock()
	end
end

local function step(K: any, name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		note(K, name .. " error: " .. tostring(err))
	end
end

local function hi(K: any): boolean
	return K.detail == "high"
end
local function lo(K: any): boolean
	return K.detail == "low"
end

local function txt(K: any, name: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3?, bg: Color3?, o: any?): (BasePart, TextLabel)
	local opts: any = o and table.clone(o) or {}
	opts.fg = fg or INK
	opts.bg = bg
	return K:text(name, w, h, dcf, s, opts)
end

local function hideRec(K: any, r: any)
	if r and r.part then
		Scan.hide(K.hidden, r.part)
	end
end

---------------------------------------------------------------------------------------------------
-- 1. 자리 확인 · 벽 사용 기록 (T_store 와 같은 규칙)
---------------------------------------------------------------------------------------------------

local STRUCT: { [string]: boolean } = {}
for k in Scan.SHELL do
	STRUCT[k] = true
end
for _, k in { "TBar", "Troffer", "LightPanel", "LightFrame", "Downlight", "TrackRail", "TrackHead", "TrackLens", "CassetteAC", "ACVanes", "ACGrille", "Rug" } do
	STRUCT[k] = true
end

local function mapBlocked(K: any, mn: Vector3, mx: Vector3): boolean
	for _, r in K.V.parts do
		local nm = r.name
		local isSign = string.sub(nm, 1, 5) == "Sign_"
		if (isSign or not STRUCT[nm]) and r.part.Transparency < 0.99 and not K.hidden[r.part] then
			if K.overlap(mn, mx, r.min, r.max, 0.02) then
				return true
			end
		end
	end
	return false
end

local function wallBusy(K: any, wn: string, a: number, b: number, y0: number, y1: number): boolean
	for _, u in K.wallUsed or {} do
		if u.w == wn and u.a < b and u.b > a and u.y0 < y1 and u.y1 > y0 then
			return true
		end
	end
	return false
end

local function addWallUsed(K: any, wn: string, a: number, b: number, y0: number, y1: number)
	K.wallUsed = K.wallUsed or {}
	table.insert(K.wallUsed, { w = wn, a = a, b = b, y0 = y0, y1 = y1 })
end

-- K:spot 과 같은 검사 (keep · 기존 가구 · 예약 · 보이는 맵 파트), 예약은 안 함. 성공하면 AABB
local function canPlace(K: any, lcf: CFrame, size: Vector3, pad: number?): (Vector3?, Vector3?)
	local V = K.V
	local p = pad or 0
	local c = lcf * CF(0, size.Y / 2, 0)
	local mn, mx = K.laabb(c, size + V3(2 * p, 0, 2 * p))
	if mn.X < V.x0 - 0.05 or mx.X > V.x1 + 0.05 or mn.Z < V.z0 - 0.05 or mx.Z > V.z1 + 0.05 then
		return nil, nil
	end
	if K:hitsKeep(mn, mx) then
		return nil, nil
	end
	for _, s in V.solid do
		if not K.hidden[s.part] and K.overlap(mn, mx, s.min, s.max, 0.04) then
			return nil, nil
		end
	end
	for _, r in K.reserved do
		if K.overlap(mn, mx, r.min, r.max, 0.02) then
			return nil, nil
		end
	end
	local smn, smx = K.laabb(c, size)
	if mapBlocked(K, smn, smx) then
		return nil, nil
	end
	return mn, mx
end

-- 바닥 자리 예약: canPlace 성공하면 reserve
local function claim(K: any, pcf: CFrame, size: Vector3, pad: number?, kind: string?): boolean
	local mn, mx = canPlace(K, pcf, size, pad)
	if mn and mx then
		K:reserve(mn, mx, kind or "service")
		return true
	end
	return false
end

-- 벽에 붙여 세우는 바닥 소품 자리 찾기 (폭 w, 깊이 d, 높이 h). prefer = 가까울수록 좋은 로컬 점
local function wallFloorSpot(K: any, walls: { string }, w: number, d: number, h: number, prefer: Vector3?, pad: number?, kind: string?, accept: ((CFrame, string, number) -> boolean)?): (string?, CFrame?, number?)
	local V = K.V
	local cands = {}
	for _, wn in walls do
		local wall = V.walls[wn]
		if wall and wall.b - wall.a > w + 0.2 then
			local u = wall.a + w / 2 + 0.1
			while u <= wall.b - w / 2 - 0.1 + 1e-6 do
				local pcf = V:wall(wn, u, 0, 0.06) * CF(0, 0, d / 2)
				local sc = if prefer then (pcf.Position - prefer).Magnitude else math.abs(u)
				table.insert(cands, { wn = wn, u = u, pcf = pcf, sc = sc })
				u += 0.3
			end
		end
	end
	table.sort(cands, function(a, b)
		return a.sc < b.sc
	end)
	for _, c in cands do
		yieldy(K)
		if not wallBusy(K, c.wn, c.u - w / 2 - 0.1, c.u + w / 2 + 0.1, 0, h) and (not accept or accept(c.pcf, c.wn, c.u)) then
			local mn, mx = canPlace(K, c.pcf, V3(w, h, d), pad)
			if mn and mx then
				K:reserve(mn, mx, kind or "service")
				addWallUsed(K, c.wn, c.u - w / 2 - 0.15, c.u + w / 2 + 0.15, 0, h + 0.3)
				return c.wn, c.pcf, c.u
			end
		end
	end
	return nil, nil, nil
end

local function sortWallUsed(K: any)
	if K.wallUsed then
		table.sort(K.wallUsed, function(x, y)
			return x.a < y.a
		end)
	end
end

-- 벽 부착물 자리 (Common.wallSpot + 맵 파트 · keep 검사). accept(dcf, wn) 가 false 면 다른 자리
local function wallItemSpot(K: any, walls: { string }, w: number, y0: number, y1: number, prefer: number?, accept: ((CFrame, string) -> boolean)?, depth: number?): (string?, CFrame?)
	local temp = {}
	local rw, rd = nil, nil
	for _ = 1, 14 do
		sortWallUsed(K)
		local wn, dcf = Common.wallSpot(K, walls, w, y0, y1, prefer)
		if not wn or not dcf then
			break
		end
		local mn, mx = K.laabb(dcf * CF(0, 0, (depth or 0.4) / 2), V3(w, y1 - y0, depth or 0.4))
		if mapBlocked(K, mn, mx) or K:hitsKeep(mn, mx) or (accept and not accept(dcf, wn)) then
			table.insert(temp, K.wallUsed[#K.wallUsed])
			continue
		end
		-- 바닥 소품 (예약) 뒤에 숨는 자리는 피함
		local hidden = false
		for _, r in K.reserved do
			if r.kind ~= "front" and r.kind ~= "staff" and r.kind ~= "chair" and K.overlap(mn, mx, r.min, r.max, 0.02) then
				hidden = true
				break
			end
		end
		if hidden then
			table.insert(temp, K.wallUsed[#K.wallUsed])
			continue
		end
		rw, rd = wn, dcf
		break
	end
	for _, t in temp do
		local i = table.find(K.wallUsed, t)
		if i then
			table.remove(K.wallUsed, i)
		end
	end
	return rw, rd
end

-- 정해진 벽 자리 (u, y) 가 비었는지 + 기록
local function wallFree(K: any, wn: string, u: number, w: number, y0: number, y1: number, depth: number?): boolean
	local V = K.V
	if wallBusy(K, wn, u - w / 2, u + w / 2, y0, y1) then
		return false
	end
	local ok = false
	for _, s in V:spans(wn, y0, y1, depth or 0.6) do
		if u - w / 2 >= s[1] - 0.01 and u + w / 2 <= s[2] + 0.01 then
			ok = true
		end
	end
	if not ok then
		return false
	end
	local dcf = V:wall(wn, u, (y0 + y1) / 2, 0)
	local mn, mx = K.laabb(dcf * CF(0, 0, (depth or 0.4) / 2), V3(w, y1 - y0, depth or 0.4))
	if mapBlocked(K, mn, mx) or K:hitsKeep(mn, mx) then
		return false
	end
	addWallUsed(K, wn, u - w / 2 - 0.15, u + w / 2 + 0.15, y0, y1)
	return true
end

-- 점 p 에 가까운 벽부터 (각 벽마다 p 의 u 를 선호 위치로) 벽 부착물 자리
local function spotNear(K: any, walls: { string }, w: number, y0: number, y1: number, p: Vector3, accept: ((CFrame, string) -> boolean)?, depth: number?): (string?, CFrame?)
	local V = K.V
	local order = {}
	for _, wn in walls do
		local _, dist = V:wallCoord(wn, p)
		table.insert(order, { wn = wn, d = math.abs(dist) })
	end
	table.sort(order, function(a, b)
		return a.d < b.d
	end)
	for _, o in order do
		local u = V:wallCoord(o.wn, p)
		local wn, d = wallItemSpot(K, { o.wn }, w, y0, y1, u, accept, depth)
		if wn and d then
			return wn, d
		end
	end
	return nil, nil
end

-- 벽지 · 벽 마감 (y0..y1, 빈 구간마다 얇은 판). rail = 위아래 몰딩 look
local function wallSkin(K: any, walls: { string }, y0: number, y1: number, look: any, rail: any?, off: number?)
	local V = K.V
	K:free(function()
		for _, wn in walls do
			for _, s in V:spans(wn, y0, y1, 0.12) do
				local len = s[2] - s[1]
				K:plate("WallSkin", len, y1 - y0, 0.015, V:wall(wn, (s[1] + s[2]) / 2, (y0 + y1) / 2, off or 0.006), look)
				if rail then
					K:plate("WallRail", len, 0.1, 0.06, V:wall(wn, (s[1] + s[2]) / 2, y0 + 0.05, 0.006), rail)
				end
			end
		end
	end)
end

-- 천장 둘레 간접조명 (몰딩 아래 LED 줄)
local function coveLED(K: any, walls: { string }, c: Color3, withLight: boolean?)
	local V = K.V
	local first = true
	K:free(function()
		for _, wn in walls do
			local wall = V.walls[wn]
			local y = V.H - 0.32
			K:plate("CoveSoffit", wall.b - wall.a - 0.1, 0.1, 0.42, V:wall(wn, (wall.a + wall.b) / 2, y - 0.08, 0.0), lk(C(240, 238, 232)))
			local s = K:bar("CoveLED", V:wall(wn, wall.a + 0.2, y + 0.02, 0.36).Position, V:wall(wn, wall.b - 0.2, y + 0.02, 0.36).Position, 0.06, 0.05, Look.neon(c))
			if s and withLight and first then
				K:light(s, "SurfaceLight", { Face = Enum.NormalId.Top, Range = 8, Brightness = 0.5, Angle = 150, Color = c })
				first = false
			end
		end
	end)
end

-- 프롬프트를 둘 수 있는 첫 파트에
local function promptOn(K: any, parts: { BasePart? }, spec: any): ProximityPrompt?
	for _, p in parts do
		if p and p.Parent then
			local lp = K.V.cf:PointToObjectSpace(p.Position)
			if Interact.canPrompt(K, lp) then
				return Interact.prompt(K, p, spec)
			end
		end
	end
	note(K, "no prompt spot: " .. tostring(spec.object))
	return nil
end

local function promptOkAt(K: any, lp: Vector3): boolean
	return Interact.canPrompt(K, lp)
end

-- 후보 점들 중 첫 성공 (pcf 정면 face)
local function floorSpot(K: any, cands: { Vector3 }, size: Vector3, face: Vector3, pad: number?, kind: string?): CFrame?
	for _, p in cands do
		yieldy(K)
		local pcf = pcfAt(V3(p.X, 0, p.Z), face)
		if claim(K, pcf, size, pad, kind) then
			return pcf
		end
	end
	return nil
end

-- 한 점의 가장 가까운 벽 (방 안쪽 법선)
local function nearestWall(V: any, p: Vector3): (string, number)
	local d = { left = p.X - V.x0, right = V.x1 - p.X, back = p.Z - V.z0 }
	local best, bd = "back", math.huge
	for k, v in d do
		if v < bd then
			best, bd = k, v
		end
	end
	return best, bd
end

-- 맵 AABB 를 그대로 덮는 상자 (같은 범위)
local function overBox(K: any, name: string, r: any, look: any, shrink: number?)
	local s = shrink or 0
	K:free(function()
		K:box(name, r.size + V3(0.02 - s, 0.01 - s, 0.02 - s), CF(r.c), look)
	end)
end

-- AABB 의 한 면 (face 쪽) 표시면 프레임: 원점 = 그 면 가운데 바닥 높이 (y = 0), 폭 = 그 면 너비
local function faceOf(r: any, face: Vector3): (CFrame, number)
	if face.Z > 0.5 then
		return CFrame.fromMatrix(V3(r.c.X, 0, r.max.Z), V3(1, 0, 0), Vector3.yAxis, face), r.size.X
	elseif face.Z < -0.5 then
		return CFrame.fromMatrix(V3(r.c.X, 0, r.min.Z), V3(-1, 0, 0), Vector3.yAxis, face), r.size.X
	elseif face.X > 0.5 then
		return CFrame.fromMatrix(V3(r.max.X, 0, r.c.Z), V3(0, 0, -1), Vector3.yAxis, face), r.size.Z
	end
	return CFrame.fromMatrix(V3(r.min.X, 0, r.c.Z), V3(0, 0, 1), Vector3.yAxis, face), r.size.Z
end

---------------------------------------------------------------------------------------------------
-- 2. 공용 소품 (벽 게시물 · 액자 · 사인 · 바닥 소품)
---------------------------------------------------------------------------------------------------

-- 금속 글자 (판 없이 글자 + 아래 그림자 글자로 두께감)
local function metalText(K: any, name: string, dcf: CFrame, w: number, h: number, s: string, col: Color3, font: Enum.Font?, glow: number?)
	txt(K, name .. "Shade", w, h, dcf * CF(0.03, -0.03, 0.01), s, darker(col, 0.65), nil, { font = font or F.GothamBold, d = 0.02 })
	return txt(K, name, w, h, dcf * CF(0, 0, 0.05), s, col, nil, { font = font or F.GothamBold, d = 0.02, glow = glow })
end

-- A4 종이 (제목 + 본문). dcf = 벽(판) 표면, w x h. 테이프 · 핀
local function paper(K: any, dcf: CFrame, w: number, h: number, title: string, body: string?, o: any?)
	local oo: any = o or {}
	local bg: Color3 = oo.bg or C(250, 249, 244)
	local th = if body then h * (oo.titleH or 0.24) else h
	local sheet = K:plate("Paper", w, h, 0.012, dcf * ANG(0, 0, oo.tilt or 0), lk(bg))
	local d = dcf * ANG(0, 0, oo.tilt or 0) * CF(0, 0, 0.013)
	if oo.band then
		K:plate("PaperBand", w, th * 0.98, 0.004, d * CF(0, h / 2 - th / 2, 0), lk(oo.band))
	end
	txt(K, "PaperTitle", w * 0.9, th * 0.78, d * CF(0, h / 2 - th / 2, 0.005), title, oo.titleFg or (if oo.band then WHITE else INK), nil, { font = oo.titleFont or F.GothamBlack, d = 0.004 })
	if body then
		txt(K, "PaperBody", w * 0.88, (h - th) * 0.9, d * CF(0, -th / 2, 0.005), body, oo.fg or C(52, 52, 56), nil, { font = oo.font or F.GothamMedium, d = 0.004, align = oo.align })
	end
	if oo.pin ~= false then
		if oo.tape then
			K:plate("PaperTape", w * 0.28, 0.16, 0.006, d * CF(0, h / 2 - 0.02, 0.004) * ANG(0, 0, 0.06), lk(C(236, 230, 200), M.SmoothPlastic, { t = 0.25 }))
		else
			K:ball("PaperPin", 0.11, d * CF(0, h / 2 - 0.12, 0.04), lk(oo.pinC or C(210, 40, 40)))
		end
	end
	return sheet
end

-- 게시판: 알루미늄 테 + 펠트/코르크 + 머리띠 제목 + 종이 격자. sheets = { {title, body, opts?} ... }
local function noticeBoard(K: any, dcf: CFrame, w: number, h: number, title: string, sheets: { any }, o: any?)
	local oo: any = o or {}
	local felt = oo.felt or lk(C(196, 160, 112), M.Fabric)
	K:plate("BoardBack", w, h, 0.08, dcf, felt)
	local fr = oo.frame or Look.alu
	K:plate("BoardFrame", w + 0.12, 0.08, 0.12, dcf * CF(0, h / 2, 0), fr)
	K:plate("BoardFrame", w + 0.12, 0.08, 0.12, dcf * CF(0, -h / 2, 0), fr)
	K:plate("BoardFrame", 0.08, h, 0.12, dcf * CF(-w / 2, 0, 0), fr)
	K:plate("BoardFrame", 0.08, h, 0.12, dcf * CF(w / 2, 0, 0), fr)
	local hh = math.min(0.62, h * 0.16)
	K:plate("BoardHeader", w - 0.1, hh, 0.09, dcf * CF(0, h / 2 - hh / 2 - 0.05, 0), lk(oo.head or C(30, 70, 140)))
	txt(K, "BoardTitle", w * 0.86, hh * 0.72, dcf * CF(0, h / 2 - hh / 2 - 0.05, 0.095), title, WHITE, nil, { font = F.GothamBlack })
	local n = #sheets
	if n == 0 then
		return
	end
	local cols = oo.cols or math.max(1, math.min(n, math.floor((w - 0.2) / 1.25)))
	local rows = math.ceil(n / cols)
	local cw = (w - 0.3) / cols
	local rh = (h - hh - 0.3) / rows
	local pw, ph = math.min(cw * 0.86, 1.25), math.min(rh * 0.88, 1.6)
	for i, s in sheets do
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		local x = -w / 2 + 0.15 + cw * (col + 0.5)
		local y = h / 2 - hh - 0.15 - rh * (row + 0.5)
		local so: any = s[3] or {}
		so.tilt = so.tilt or ((i % 3) - 1) * 0.025
		paper(K, dcf * CF(x, y, 0.085), pw, ph, s[1], s[2], so)
	end
end

-- 금테 액자 증서 (등록증 · 자격증 · 요율표)
local function cert(K: any, dcf: CFrame, w: number, h: number, title: string, body: string, o: any?)
	local oo: any = o or {}
	Props.frame(K, dcf, w, h, { frame = oo.frame or Look.goldMetal, border = 0.07, depth = 0.06, mat = Look.paper })
	local d = dcf * CF(0, 0, 0.05)
	txt(K, "CertTitle", w * 0.72, h * 0.13, d * CF(0, h * 0.32, 0), title, C(40, 40, 44), nil, { font = F.GothamBlack, d = 0.004 })
	txt(K, "CertBody", w * 0.7, h * 0.48, d * CF(0, -h * 0.06, 0), body, C(70, 70, 74), nil, { font = F.SourceSans, d = 0.004 })
	K:disc("CertSeal", math.min(w, h) * 0.16, 0.01, d * CF(w * 0.24, -h * 0.34, 0.004) * ANG(PI / 2, 0, 0), lk(C(200, 40, 40)))
end

-- 비상구 유도등 (녹색 바탕 + 흰 글자, 빛남)
local function exitSign(K: any, dcf: CFrame)
	K:plate("ExitSignBox", 1.6, 0.62, 0.16, dcf, Look.white)
	local face = K:plate("ExitSignLED", 1.46, 0.5, 0.02, dcf * CF(0, 0, 0.16), Look.neon(C(30, 190, 90)))
	txt(K, "ExitSignText", 1.3, 0.38, dcf * CF(0.08, 0, 0.185), "비상구  EXIT ▶", WHITE, nil, { font = F.GothamBlack, glow = 1.4 })
	return face
end

-- 옥내소화전함 (빨간 함 + 표시등 + 유리창 안 호스)
local function hydrant(K: any, dcf: CFrame)
	local w, h = 1.9, 3.4
	local base = dcf * CF(0, h / 2 + 1.0, 0)
	K:plate("HydrantBox", w, h, 0.36, base, lk(C(196, 32, 34), M.Metal))
	K:plate("HydrantDoorEdge", w - 0.12, h - 0.12, 0.02, base * CF(0, 0, 0.36), lk(C(170, 26, 28), M.Metal))
	K:plate("HydrantWindow", w * 0.62, h * 0.36, 0.01, base * CF(0, 0.32, 0.385), lk(C(200, 214, 220), M.Glass, { t = 0.45 }))
	if not lo(K) then
		for i = 0, 2 do
			K:cyl("HydrantHose", 0.12, 0.9 - i * 0.18, base * CF(-0.1 + i * 0.02, 0.32, 0.3) * ANG(0, PI / 2, 0), lk(C(236, 232, 220), M.Fabric))
		end
		K:cyl("HydrantNozzle", 0.5, 0.1, base * CF(0.45, 0.2, 0.3) * ANG(0, 0, 0.6), Look.brass)
	end
	txt(K, "HydrantText", w * 0.7, 0.42, base * CF(0, -0.55, 0.39), "소 화 전", WHITE, nil, { font = F.GothamBlack })
	txt(K, "HydrantSub", w * 0.75, 0.22, base * CF(0, -0.95, 0.39), "FIRE HOSE · 사용법: 문을 열고 호스를 펼친 뒤 밸브를 여세요", lighter(C(196, 32, 34), 0.75), nil, { font = F.GothamMedium })
	K:plate("HydrantHandle", 0.08, 0.5, 0.06, base * CF(w / 2 - 0.2, -0.2, 0.39), Look.chrome)
	-- 위 표시등 · 비상벨 함
	local top = dcf * CF(0, h + 1.35, 0)
	K:plate("HydrantLampBox", w, 0.55, 0.22, top, lk(C(196, 32, 34), M.Metal))
	K:disc("HydrantLamp", 0.34, 0.06, top * CF(-0.45, 0, 0.25) * ANG(PI / 2, 0, 0), Look.ledRed)
	K:disc("HydrantBellBtn", 0.26, 0.05, top * CF(0.45, 0, 0.25) * ANG(PI / 2, 0, 0), Look.white)
	txt(K, "HydrantBellText", 0.5, 0.2, top * CF(0.05, 0, 0.23), "발신기", WHITE, nil, { font = F.GothamBold })
end

-- 우산 비닐 포장기 (비 오는 날 한국 건물 입구 필수품)
local function umbrellaBagger(K: any, pcf: CFrame, side: number?)
	local sd = side or 1
	K:box("UmbBase", V3(1.2, 0.12, 0.8), pcf * CF(0, 0.06, 0), Look.steel)
	K:box("UmbBody", V3(1.1, 2.6, 0.7), pcf * CF(0, 1.42, 0), Look.steel)
	K:box("UmbTop", V3(1.16, 0.12, 0.76), pcf * CF(0, 2.78, 0), Look.darkAlu)
	K:box("UmbSlot", V3(0.5, 0.06, 0.18), pcf * CF(0, 2.85, 0.05), Look.black)
	K:plate("UmbBagRoll", 0.8, 0.9, 0.02, pcf * CF(0, 1.9, 0.35), lk(C(230, 238, 240), M.Glass, { t = 0.4 }))
	txt(K, "UmbLabel", 0.9, 0.5, pcf * CF(0, 1.1, 0.352), "우산 비닐 커버\n위에서 꽂고 빼세요", C(30, 60, 120), C(240, 244, 248), { font = F.GothamBold, d = 0.01 })
	if not lo(K) then
		for i, c in { C(40, 60, 120), C(140, 40, 40) } do
			K:seg("UmbStick", (pcf * CF(sd * 0.75, 0.0, 0.1 * i)).Position, (pcf * CF(sd * 0.82, 2.7, 0.1 * i)).Position, 0.06, Look.chrome)
			K:ell("UmbCanopy", V3(0.3, 2.0, 0.3), pcf * CF(sd * 0.8, 1.5, 0.1 * i), lk(c, M.Fabric))
		end
	end
end

-- 정수기 (냉온수 · 컵 디스펜서)
local function purifier(K: any, pcf: CFrame, col: Color3?)
	local body = lk(col or C(244, 244, 242))
	K:rbox("PurifierBody", V3(1.1, 3.4, 1.1), 0.12, pcf * CF(0, 1.7, 0), body)
	K:box("PurifierTop", V3(1.12, 0.06, 1.12), pcf * CF(0, 3.42, 0), Look.darkAlu)
	K:plate("PurifierPanel", 0.9, 0.5, 0.02, pcf * CF(0, 2.9, 0.55), Look.black)
	K:ball("PurifierLEDb", 0.07, pcf * CF(-0.2, 2.95, 0.58), Look.ledBlue)
	K:ball("PurifierLEDr", 0.07, pcf * CF(0.2, 2.95, 0.58), Look.ledRed)
	K:box("PurifierRecess", V3(0.8, 0.9, 0.2), pcf * CF(0, 2.0, 0.47), Look.charcoal)
	K:vcyl("PurifierTap", 0.14, 0.12, pcf * CF(-0.15, 2.35, 0.48), Look.chrome)
	K:vcyl("PurifierTapH", 0.14, 0.12, pcf * CF(0.15, 2.35, 0.48), lk(C(200, 50, 40)))
	K:box("PurifierTray", V3(0.7, 0.05, 0.3), pcf * CF(0, 1.58, 0.52), Look.grey)
	-- 옆 종이컵 디스펜서
	K:vcyl("CupTube", 0.9, 0.3, pcf * CF(0.68, 2.3, 0.2), lk(C(220, 230, 236), M.Glass, { t = 0.35 }))
	K:vcyl("CupStack", 0.8, 0.24, pcf * CF(0.68, 2.3, 0.2), Look.paper)
end

-- 벤치 (원목 좌판 + 철제 다리). pcf = 바닥 가운데, len 길이
local function bench(K: any, pcf: CFrame, len: number, seat: any?, leg: any?)
	local s = seat or Look.oak
	local l = leg or Look.blackMetal
	K:box("BenchSeat", V3(len, 0.18, 1.3), pcf * CF(0, 1.62, 0), s)
	if not lo(K) then
		for i = 1, 4 do
			K:box("BenchSlatGap", V3(len - 0.04, 0.02, 0.03), pcf * CF(0, 1.715, -0.65 + i * 0.26), darker(s.c, 0.25) and lk(darker(s.c, 0.3), s.m))
		end
	end
	for _, sx in { -1, 1 } do
		local x = sx * (len / 2 - 0.35)
		K:box("BenchLeg", V3(0.12, 1.53, 0.12), pcf * CF(x, 0.765, -0.5), l)
		K:box("BenchLeg", V3(0.12, 1.53, 0.12), pcf * CF(x, 0.765, 0.5), l)
		K:box("BenchFoot", V3(0.14, 0.1, 1.2), pcf * CF(x, 0.05, 0), l)
		K:box("BenchRail", V3(0.1, 0.1, 1.1), pcf * CF(x, 1.47, 0), l)
	end
end

-- 바닥 포스터 스탠드 (크롬 받침 + 액자). pcf 정면 +Z
local function posterStand(K: any, pcf: CFrame, w: number, h: number, title: string, body: string, bg: Color3, fg: Color3, band: Color3?)
	K:disc("StandBase", 1.1, 0.08, pcf * CF(0, 0.04, 0), Look.chrome)
	K:vcyl("StandPole", 4.2 - h / 2, 0.08, pcf * CF(0, (4.2 - h / 2) / 2, 0), Look.chrome)
	local d = pcf * CF(0, 4.2, 0.06)
	K:plate("StandFrame", w + 0.1, h + 0.1, 0.06, d * CF(0, 0, -0.06), Look.chrome)
	K:plate("StandFace", w, h, 0.02, d, lk(bg))
	local bh = h * 0.22
	if band then
		K:plate("StandBand", w, bh, 0.01, d * CF(0, h / 2 - bh / 2, 0.02), lk(band))
	end
	txt(K, "StandTitle", w * 0.9, bh * 0.7, d * CF(0, h / 2 - bh / 2, 0.035), title, if band then WHITE else fg, nil, { font = F.GothamBlack })
	txt(K, "StandBody", w * 0.86, (h - bh) * 0.86, d * CF(0, -bh / 2, 0.035), body, fg, nil, { font = F.GothamMedium })
end

-- 디지털 사이니지 스탠드 (세로 화면, 화면 순환). 반환: 화면 파트, 글자
local function signageStand(K: any, pcf: CFrame, w: number, h: number, frames: { any }, period: number?)
	K:box("SignageFoot", V3(w + 0.3, 0.12, 1.0), pcf * CF(0, 0.06, 0), Look.darkAlu)
	K:box("SignageBody", V3(w + 0.16, h + 0.16, 0.26), pcf * CF(0, 0.5 + h / 2, 0), Look.black)
	local scr = K:plate("SignageScreen", w, h, 0.02, pcf * CF(0, 0.5 + h / 2, 0.13), { c = frames[1].c or C(20, 40, 80), m = M.Neon, t = 0.1 })
	local _, lab = txt(K, "SignageText", w * 0.9, h * 0.9, pcf * CF(0, 0.5 + h / 2, 0.155), frames[1].text, WHITE, nil, { font = F.GothamBold, glow = 1.2 })
	Interact.screenLoop(K, scr, lab, frames, period or 5)
	return scr, lab
end

-- 액자 그림: 단색 블록 구성 (추상화). palette 색 목록
local function artBlocks(K: any, dcf: CFrame, w: number, h: number, rng: () -> number, palette: { Color3 }, frame: any?)
	local art = {}
	local n = if lo(K) then 3 else 6
	for i = 1, n do
		local aw, ah = 0.2 + rng() * 0.5, 0.15 + rng() * 0.5
		table.insert(art, { palette[(i - 1) % #palette + 1], rng() * (1 - aw), rng() * (1 - ah), aw, ah })
	end
	Props.frame(K, dcf, w, h, { frame = frame or Look.blackMetal, art = art, mat = lk(C(244, 240, 232)), border = 0.08, depth = 0.08 })
end

-- 세운 화분 (자리 확인 포함)
local function plantAt(K: any, pcf: CFrame, kind: string, h: number, dia: number, pot: any?): boolean
	if not claim(K, pcf, V3(dia + 0.6, h, dia + 0.6), 0.05, "plant") then
		return false
	end
	Props.floorPlant(K, pcf, { kind = kind, h = h, dia = dia, pot = pot })
	return true
end

-- 세계 시계 (도시 이름 + 시차). dcf 중심
local function worldClock(K: any, dcf: CFrame, dia: number, city: string, off: number, frame: any?, fg: Color3?)
	local hr, mn = Props.clock(K, dcf, dia, { frame = frame or Look.brass })
	txt(K, "WorldClockCity", dia * 1.3, dia * 0.24, dcf * CF(0, -dia * 0.72, 0.01), city, fg or C(220, 196, 140), nil, { font = F.GothamBold, d = 0.01 })
	if hr.Parent == nil then
		return
	end
	local wc = K.cf * dcf
	Interact.anim(K, function()
		local h = (Lighting.ClockTime + off) % 24
		local m = (h % 1) * 60
		local ah = -((h % 12) / 12) * PI * 2
		local am = -(m / 60) * PI * 2
		hr.CFrame = wc * ANG(0, 0, ah) * CF(0, dia * 0.1, 0.155)
		mn.CFrame = wc * ANG(0, 0, am) * CF(0, dia * 0.16, 0.175)
	end)
end

-- 사무용 모니터 (책상 위). top = 책상 윗면 위 pcf (+Z = 화면이 보는 쪽)
local function monitor(K: any, top: CFrame, w: number, screenText: string?, screenBg: Color3?)
	local h = w * 0.58
	K:box("MonBase", V3(w * 0.36, 0.04, 0.5), top * CF(0, 0.02, -0.05), Look.darkAlu)
	K:box("MonNeck", V3(0.16, h * 0.55, 0.08), top * CF(0, 0.04 + h * 0.27, -0.2) * ANG(-0.08, 0, 0), Look.darkAlu)
	local cy = 0.32 + h / 2
	K:box("MonBody", V3(w, h, 0.08), top * CF(0, cy, -0.1), Look.black)
	K:box("MonBack", V3(w * 0.7, h * 0.6, 0.08), top * CF(0, cy, -0.18), Look.charcoal)
	local scr = K:plate("MonScreen", w - 0.08, h - 0.1, 0.01, top * CF(0, cy + 0.02, -0.06), { c = screenBg or C(232, 238, 246), m = M.Neon, t = 0.35 })
	if screenText then
		txt(K, "MonText", w - 0.2, h - 0.2, top * CF(0, cy + 0.02, -0.045), screenText, C(40, 60, 90), nil, { font = F.GothamMedium, glow = 0.9 })
	end
	return scr
end

local function keyboard(K: any, top: CFrame, w: number?)
	local kw = w or 1.3
	K:box("Keyboard", V3(kw, 0.06, 0.42), top * CF(0, 0.03, 0) * ANG(0.05, 0, 0), Look.charcoal)
	if hi(K) then
		K:box("KeyboardKeys", V3(kw - 0.1, 0.02, 0.34), top * CF(0, 0.07, 0) * ANG(0.05, 0, 0), Look.grey)
	end
	K:ell("Mouse", V3(0.2, 0.08, 0.3), top * CF(kw / 2 + 0.35, 0.04, 0.05), Look.charcoal)
end

local function deskPhone(K: any, top: CFrame)
	K:box("PhoneBase", V3(0.6, 0.12, 0.66), top * CF(0, 0.06, 0) * ANG(0.15, 0, 0), Look.black)
	K:box("PhoneHandset", V3(0.18, 0.12, 0.62), top * CF(-0.2, 0.17, 0) * ANG(0.15, 0, 0), Look.black)
	K:plate("PhoneLCD", 0.24, 0.12, 0.01, CFrame.fromMatrix((top * CF(0.1, 0.13, -0.1)).Position, top.XVector, top.ZVector, -top.YVector) * ANG(PI, 0, 0), lk(C(150, 190, 160), M.Neon, { t = 0.3 }))
end

local function penCup(K: any, top: CFrame)
	K:vcyl("PenCup", 0.34, 0.26, top * CF(0, 0.17, 0), Look.blackMetal)
	if not lo(K) then
		for i, c in { C(30, 60, 160), C(200, 40, 40), C(20, 20, 20) } do
			K:seg("Pen", (top * CF(-0.05 + i * 0.03, 0.1, 0)).Position, (top * CF(-0.1 + i * 0.06, 0.62, 0.02 * i)).Position, 0.04, lk(c))
		end
	end
end

local function paperStack(K: any, top: CFrame, w: number, d: number, n: number)
	for i = 1, n do
		K:box("PaperStack", V3(w, 0.03, d), top * CF((i % 2) * 0.03, 0.015 + (i - 1) * 0.035, 0) * ANG(0, (i % 3 - 1) * 0.06, 0), Look.paper)
	end
end

-- 사무용 의자 (메쉬 + 5발). pcf 정면 = 앉은 사람이 보는 쪽
local function officeChair(K: any, pcf: CFrame, col: Color3?)
	local mesh = lk(col or C(40, 42, 46), M.Fabric)
	for i = 0, 4 do
		local a = i * PI * 2 / 5
		K:seg("ChairStar", (pcf * CF(0, 0.22, 0)).Position, (pcf * CF(math.cos(a) * 0.95, 0.12, math.sin(a) * 0.95)).Position, 0.12, Look.black)
		if not lo(K) then
			K:ball("ChairCaster", 0.18, pcf * CF(math.cos(a) * 0.95, 0.09, math.sin(a) * 0.95), Look.black)
		end
	end
	K:vcyl("ChairGas", 1.0, 0.16, pcf * CF(0, 0.7, 0), Look.chrome)
	K:box("ChairMech", V3(0.7, 0.16, 0.7), pcf * CF(0, 1.2, 0), Look.black)
	K:rbox("ChairSeatPad", V3(1.55, 0.32, 1.5), 0.1, pcf * CF(0, 1.44, 0.05), mesh)
	K:box("ChairSpine", V3(0.22, 1.1, 0.12), pcf * CF(0, 1.8, -0.72) * ANG(-0.12, 0, 0), Look.black)
	K:rbox("ChairBackPad", V3(1.45, 1.7, 0.18), 0.12, pcf * CF(0, 2.75, -0.8) * ANG(-0.12, 0, 0), mesh)
	for _, sx in { -1, 1 } do
		K:box("ChairArmPost", V3(0.1, 0.55, 0.12), pcf * CF(sx * 0.72, 1.75, -0.1), Look.black)
		K:box("ChairArmPad", V3(0.22, 0.08, 0.75), pcf * CF(sx * 0.72, 2.05, 0), Look.black)
	end
end

-- 손님 의자 (사무실 대기 · 상담: 크롬 캔틸레버 + 가죽)
local function guestChair(K: any, pcf: CFrame, seatL: any?)
	local s = seatL or Look.leatherBlack
	K:box("GChairSeat", V3(1.45, 0.24, 1.4), pcf * CF(0, 1.55, 0), s)
	K:box("GChairBack", V3(1.45, 1.35, 0.18), pcf * CF(0, 2.45, -0.68) * ANG(-0.1, 0, 0), s)
	for _, sx in { -1, 1 } do
		K:seg("GChairRail", (pcf * CF(sx * 0.66, 0.05, 0.75)).Position, (pcf * CF(sx * 0.66, 0.05, -0.65)).Position, 0.08, Look.chrome)
		K:seg("GChairRail", (pcf * CF(sx * 0.66, 0.05, 0.75)).Position, (pcf * CF(sx * 0.66, 1.42, 0.55)).Position, 0.08, Look.chrome)
		K:seg("GChairRail", (pcf * CF(sx * 0.66, 0.05, -0.65)).Position, (pcf * CF(sx * 0.66, 1.42, -0.6)).Position, 0.08, Look.chrome)
	end
end

-- 2인 소파 (장식). pcf 정면 +Z, len 길이
local function sofa(K: any, pcf: CFrame, len: number, fab: any, legL: any?)
	local d = 2.3
	K:rbox("SofaBase", V3(len, 0.9, d), 0.15, pcf * CF(0, 0.75, 0), fab)
	local n = if len > 4.6 then 3 else 2
	local cw = (len - 0.9) / n
	for i = 1, n do
		local x = -len / 2 + 0.45 + cw * (i - 0.5)
		K:rbox("SofaCushion", V3(cw - 0.06, 0.38, d - 0.75), 0.14, pcf * CF(x, 1.38, 0.28), fab)
		K:rbox("SofaBackCushion", V3(cw - 0.08, 1.25, 0.5), 0.2, pcf * CF(x, 2.05, -0.62) * ANG(-0.12, 0, 0), fab)
	end
	K:rbox("SofaBack", V3(len, 1.9, 0.42), 0.15, pcf * CF(0, 1.6, -d / 2 + 0.21), fab)
	for _, sx in { -1, 1 } do
		K:rbox("SofaArm", V3(0.44, 1.55, d), 0.18, pcf * CF(sx * (len / 2 - 0.22), 1.08, 0), fab)
		for _, sz in { -1, 1 } do
			K:box("SofaLeg", V3(0.14, 0.3, 0.14), pcf * CF(sx * (len / 2 - 0.3), 0.15, sz * (d / 2 - 0.3)), legL or Look.walnut)
		end
	end
	K:ell("SofaPillow", V3(0.9, 0.85, 0.3), pcf * CF(-len / 2 + 0.85, 1.9, -0.25) * ANG(-0.3, 0.3, 0.1), lk(lighter(fab.c, 0.35), M.Fabric))
end

---------------------------------------------------------------------------------------------------
-- 3. 스타일 (Common S)
---------------------------------------------------------------------------------------------------

local function hotelTheme(V: any): any
	local h = hashStr(V.name or "hotel")
	local themes = {
		{ -- 화이트 마블 + 브라스 + 월넛 루버
			key = "marble",
			front = lk(C(238, 236, 230), M.Marble), vein = lk(C(160, 156, 150), M.Marble), top = lk(C(244, 242, 236), M.Marble),
			trim = Look.brass, wall = lk(C(120, 82, 56), M.Wood), wallBack = lk(C(56, 40, 30)), fab = lk(C(226, 216, 196), M.Fabric),
			rug = lk(C(176, 160, 136), M.Fabric), rugEdge = lk(C(92, 74, 56), M.Fabric), accent = C(196, 160, 96), floor = lk(C(226, 222, 212), M.Marble),
			stone = lk(C(222, 214, 198), M.Limestone),
		},
		{ -- 플루티드 오크 + 테라조 + 올리브 벨벳
			key = "oak",
			front = lk(C(198, 160, 118), M.Wood), vein = lk(C(150, 116, 80), M.Wood), top = lk(C(214, 208, 198), M.Granite),
			trim = Look.goldMetal, wall = lk(C(212, 196, 172), M.Limestone), wallBack = lk(C(150, 136, 116)), fab = lk(C(92, 108, 74), M.Fabric),
			rug = lk(C(200, 190, 170), M.Fabric), rugEdge = lk(C(120, 110, 86), M.Fabric), accent = C(214, 176, 110), floor = lk(C(214, 208, 198), M.Granite),
			stone = lk(C(206, 196, 178), M.Limestone),
		},
		{ -- 차콜 스톤 + 골드 + 코냑 가죽 (오션 나이트)
			key = "dark",
			front = lk(C(58, 60, 64), M.Slate), vein = lk(C(110, 112, 116), M.Slate), top = lk(C(30, 30, 32), M.Marble),
			trim = Look.goldMetal, wall = lk(C(72, 52, 38), M.Wood), wallBack = lk(C(24, 24, 26)), fab = lk(C(140, 84, 48), M.Leather),
			rug = lk(C(60, 72, 92), M.Fabric), rugEdge = lk(C(176, 150, 100), M.Fabric), accent = C(222, 186, 110), floor = lk(C(196, 192, 186), M.Marble),
			stone = lk(C(84, 84, 86), M.Slate),
		},
	}
	return themes[h % #themes + 1]
end

local function isMotel(V: any): boolean
	local n = string.upper(V.name or "")
	if string.find(n, "MOTEL", 1, true) or string.find(n, "모텔", 1, true) then
		return true
	end
	return V:has("Ledge") == 0 and V:has("WorkDesk") == 0 and V:has("FrontDesk") == 0
end

function T.style(V: any): any
	local t = V.type
	local skip = { fixtures = true }
	if t == "lobby" then
		if isMotel(V) then
			return {
				chair = false, stool = {}, table = false, counter = { front = "panel", frontL = lk(C(40, 34, 40)), topL = Look.marbleBlack },
				floor = { look = lk(C(54, 50, 52), M.Slate), tile = 2.0, grout = lk(C(30, 30, 32)) },
				ceiling = { skin = lk(C(40, 36, 42)) }, base = Look.black,
				lower = { kind = "paint", h = 3.4, look = lk(C(70, 52, 62), M.Fabric), cap = Look.goldMetal, walls = { "left", "right", "back" } },
				lights = { kind = "downlight", n = 3, color = C(255, 196, 150), glow = Look.lampWarm },
				mat = { look = lk(C(60, 20, 30), M.Fabric), text = "L MOTEL" }, cctv = true, clock = false, license = true, skip = skip,
			}
		end
		local th = hotelTheme(V)
		return {
			chair = false, stool = {}, table = false, counter = { front = "marble", frontL = th.front, topL = th.top },
			floor = { look = th.floor, tile = 3.0, grout = lk(darker(th.floor.c, 0.18)) },
			ceiling = { skin = lk(C(244, 242, 236), M.Plaster), crown = lk(C(236, 232, 224)) }, base = lk(darker(th.stone.c, 0.35), M.Slate),
			lower = { kind = "tile", h = 3.6, look = th.stone, grout = lk(darker(th.stone.c, 0.15)), tw = 2.4, th = 1.2, walls = { "left", "right", "back" } },
			lights = { kind = "downlight", n = 4, color = Look.warmLight, glow = Look.lampWarm },
			pendant = { shade = "globe" }, plants = { "olive", "ficus", "monstera" },
			mat = { look = lk(C(48, 46, 44), M.Fabric), text = string.upper(V.name or "WELCOME") }, cctv = true, clock = false, license = true, skip = skip,
		}
	elseif t == "residence" then
		local h = hashStr(V.name or "res")
		local warm = h % 2 == 0
		return {
			chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey }, stool = {}, table = { top = Look.oak, base = Look.blackMetal },
			counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
			floor = { look = if warm then lk(C(196, 188, 176), M.Granite) else lk(C(150, 152, 154), M.Granite), tile = 2.0, grout = lk(C(120, 118, 114)) },
			ceiling = { skin = lk(C(242, 242, 238), M.Plaster) }, base = lk(C(60, 60, 62), M.Slate),
			lower = { kind = "tile", h = 4.0, look = if warm then lk(C(214, 204, 186), M.Limestone) else lk(C(190, 192, 194), M.Marble), grout = lk(C(160, 156, 150)), tw = 2.0, th = 1.0, walls = { "left", "right" } },
			lights = { kind = "downlight", n = 3, color = Look.neutralLight },
			plants = { "snake", "ficus", "bamboo" }, mat = { look = lk(C(60, 60, 62), M.Fabric) }, cctv = true, clock = false, license = false, skip = skip,
		}
	elseif t == "realty" then
		return {
			chair = { style = "office", frame = Look.blackMetal, seat = lk(C(44, 46, 52), M.Fabric) }, stool = {},
			table = { top = lk(C(236, 234, 228)), base = Look.blackMetal, style = "four", edge = lk(C(60, 60, 62)) },
			counter = { front = "panel", frontL = lk(C(232, 230, 224)), topL = lk(C(120, 92, 66), M.Wood), led = false },
			floor = { look = lk(C(170, 140, 108), M.WoodPlanks), tile = 0 }, ceiling = { grid = true },
			base = lk(C(90, 70, 52), M.Wood), lower = false, lights = { kind = "panel", n = 4 },
			plants = { "snake", "ficus" }, mat = { look = lk(C(40, 60, 90), M.Fabric) }, cctv = true, clock = false, license = false, skip = skip,
		}
	elseif t == "laundry" then
		return {
			chair = { style = "plastic", seat = lk(C(60, 130, 190)) }, stool = { style = "plastic" },
			table = { top = lk(C(214, 220, 226)), base = Look.alu, style = "four", edge = Look.alu },
			counter = { front = "panel", frontL = lk(C(64, 120, 180)), topL = Look.marbleWhite, led = false },
			floor = { look = lk(C(206, 208, 206), M.CeramicTiles), tile = 1.5, grout = lk(C(170, 172, 172)) }, ceiling = { grid = true },
			base = lk(C(70, 110, 160)), lower = { kind = "tile", h = 3.0, look = lk(C(226, 236, 242), M.CeramicTiles), grout = lk(C(190, 196, 200)), tw = 1.0, th = 1.0, walls = { "left", "right", "back" } },
			lights = { kind = "panel", n = 4 }, mat = { look = lk(C(40, 70, 120), M.Fabric) }, cctv = true, clock = false, license = false, skip = skip,
		}
	end
	-- office / bank / clinic / academy
	return {
		chair = { style = "office", frame = Look.blackMetal, seat = lk(C(44, 46, 52), M.Fabric) }, stool = {},
		table = { top = lk(C(236, 234, 228)), base = Look.blackMetal, style = "four" },
		counter = { front = "panel", frontL = if t == "bank" then lk(C(30, 60, 120)) else Look.white, topL = Look.marbleWhite, led = false },
		floor = { look = if t == "clinic" then lk(C(226, 228, 226), M.SmoothPlastic) else lk(C(150, 152, 156), M.Fabric), tile = if t == "clinic" then 2.0 else 2.0, grout = lk(C(190, 192, 190)) },
		ceiling = { grid = true }, base = Look.white, lower = false, lights = { kind = "panel", n = 5 },
		plants = { "snake", "ficus" }, mat = {}, cctv = true, clock = false, license = false, skip = skip,
	}
end

---------------------------------------------------------------------------------------------------
-- 4. 호텔 로비
---------------------------------------------------------------------------------------------------

-- 프런트 데스크 덮어씌우기 (Ledge/FrontPanel/WorkDesk/WorkTop/ToeKick/DeskGlow/Monitor). 반환: 데스크 정보
local function hotelDesk(K: any, V: any, th: any, rng: () -> number): any?
	local ld, fp, wd, wt, tk, gl = V:first("Ledge"), V:first("FrontPanel"), V:first("WorkDesk"), V:first("WorkTop"), V:first("ToeKick"), V:first("DeskGlow")
	if not ld then
		return nil
	end
	local back = wd or wt or ld
	local face = snap((if fp then fp.c else ld.c) - back.c)
	if (if fp then fp.c else ld.c) == back.c then
		face = V3(0, 0, 1)
	end
	local mn, mx = ld.min, ld.max
	for _, r in { fp, wd, wt, tk } do
		if r then
			mn, mx = mn:Min(r.min), mx:Max(r.max)
		end
	end
	local info = { face = face, min = mn, max = mx, ledge = ld, c = (mn + mx) / 2 }
	K:free(function()
		-- 상판 (Ledge = 게임플레이 표면: 같은 높이 · 같은 범위)
		local lw, ll = ld.size.X, ld.size.Z
		local alongX = math.abs(face.Z) > 0.5
		local edgeW = 0.06
		local fcf, flen = faceOf(ld, face)
		local topY = ld.max.Y
		local tth = ld.size.Y
		if alongX then
			K:box("DeskLedge", V3(lw, tth, ll - edgeW), CF(ld.c.X, topY - tth / 2, ld.c.Z - face.Z * edgeW / 2), th.top)
			K:box("DeskLedgeEdge", V3(lw, tth, edgeW), CF(ld.c.X, topY - tth / 2, ld.c.Z + face.Z * (ll / 2 - edgeW / 2)), th.trim)
		else
			K:box("DeskLedge", V3(lw - edgeW, tth, ll), CF(ld.c.X - face.X * edgeW / 2, topY - tth / 2, ld.c.Z), th.top)
			K:box("DeskLedgeEdge", V3(edgeW, tth, ll), CF(ld.c.X + face.X * (lw / 2 - edgeW / 2), topY - tth / 2, ld.c.Z), th.trim)
		end
		_ = fcf
		_ = flen
		hideRec(K, ld)
		-- 앞판 (FrontPanel: 장식 파트, 같은 부피로 다시 짓고 숨김)
		if fp then
			local d, len = faceOf(fp, face)
			local y0, y1 = fp.min.Y, fp.max.Y
			K:box("DeskBody", fp.size + V3(-0.02, 0, -0.02), CF(fp.c), lk(darker(th.front.c, 0.06), th.front.m))
			local fh = y1 - y0
			local dd = d * CF(0, y0, 0)
			local ph = fh - 0.3
			-- 가운데: 백라이트 오닉스 판 (호텔 프런트 대표 마감) / 양옆: 테마 마감
			local ow = math.min(len * 0.34, 2.6)
			local sideW = (len - ow) / 2 - 0.08
			for _, sgn in { -1, 1 } do
				local cu = sgn * (ow / 2 + 0.08 + sideW / 2)
				if th.key == "oak" then
					local n = math.max(3, math.floor(sideW / (if lo(K) then 0.6 else 0.3)))
					local pw = sideW / n
					for i = 1, n do
						K:cyl("DeskFlute", ph, pw * 0.92, dd * CF(cu - sideW / 2 + pw * (i - 0.5), 0.15 + ph / 2, 0.0) * ANG(0, 0, PI / 2), th.front)
					end
				else
					K:plate("DeskFace", sideW, ph, 0.03, dd * CF(cu, 0.15 + ph / 2, 0), th.front)
					if th.key == "marble" then
						-- 북매치 대리석 결 (좌우 대칭 사선)
						for k = 1, (if lo(K) then 1 else 3) do
							local vy = 0.5 + k * ph / 4
							K:plate("DeskVein", sideW * 1.02, 0.025, 0.035, dd * CF(cu, vy, 0) * ANG(0, 0, -sgn * (0.22 + k * 0.05)), th.vein)
						end
					else
						for k = 1, 2 do
							K:plate("DeskInlay", 0.04, ph, 0.04, dd * CF(cu - sideW / 2 + sideW * k / 3, 0.15 + ph / 2, 0), th.trim)
						end
					end
				end
				-- 판 사이 금속 세로 띠
				K:plate("DeskJoint", 0.07, ph, 0.05, dd * CF(sgn * (ow / 2 + 0.04), 0.15 + ph / 2, 0), th.trim)
			end
			K:plate("DeskOnyx", ow, ph, 0.03, dd * CF(0, 0.15 + ph / 2, 0), lk(C(232, 206, 168), M.Neon, { t = 0.62 }))
			K:plate("DeskOnyxBack", ow, ph, 0.02, dd * CF(0, 0.15 + ph / 2, -0.01), lk(C(150, 110, 70)))
			if not lo(K) then
				for k = 1, 3 do
					K:plate("DeskOnyxVein", ow * 0.98, 0.025, 0.034, dd * CF(0, 0.4 + k * ph / 4, 0.002) * ANG(0, 0, (k % 2 - 0.5) * 0.18), lk(C(190, 150, 100), M.Glass, { t = 0.45 }))
				end
			end
			-- 위아래 금속 띠
			K:plate("DeskTrimTop", len, 0.08, 0.05, dd * CF(0, fh - 0.12, 0), th.trim)
			K:plate("DeskTrimBot", len, 0.12, 0.05, dd * CF(0, 0.08, 0), th.trim)
			-- 'RECEPTION' 금속 글자 (오닉스 위)
			metalText(K, "DeskSign", dd * CF(0, fh * 0.62, 0.02), ow * 0.86, 0.34, "RECEPTION", darker(th.trim.c, 0.45), F.GothamMedium)
			txt(K, "DeskSignKo", ow * 0.5, 0.24, dd * CF(0, fh * 0.62 - 0.36, 0.07), "프런트", darker(th.trim.c, 0.45), nil, { font = F.GothamBold })
			hideRec(K, fp)
		end
		if tk then
			K:box("DeskKick", tk.size + V3(0.02, 0, 0.02), CF(tk.c), Look.black)
			hideRec(K, tk)
		end
		-- 상판 아래 간접 조명 (DeskGlow 자리)
		if gl then
			local strip = K:box("DeskLEDStrip", gl.size + V3(0, -0.12, 0), CF(gl.c + V3(0, 0.04, 0)), Look.neon(C(255, 210, 160)))
			K:light(strip, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.7, Angle = 120, Color = C(255, 210, 160) })
			hideRec(K, gl)
		end
		-- 직원 쪽 작업대 (WorkTop · WorkDesk: 게임플레이 파트, 같은 범위)
		if wt then
			K:box("DeskWorkTop", wt.size + V3(0.01, 0.01, 0.01), CF(wt.c), lk(C(92, 66, 48), M.Wood))
			hideRec(K, wt)
		end
		if wd then
			K:box("DeskWorkBody", wd.size + V3(0.01, 0, 0.01), CF(wd.c), lk(C(236, 234, 228)))
			local bd, blen = faceOf(wd, -face)
			local n = math.max(2, math.floor(blen / 2.2))
			local cw = blen / n
			for i = 1, n do
				local u = -blen / 2 + cw * (i - 0.5)
				if i % 2 == 1 then
					-- 서랍 3단
					for j = 0, 2 do
						local y = wd.min.Y + 0.35 + j * 0.62
						K:plate("DeskDrawer", cw * 0.86, 0.54, 0.03, bd * CF(u, y, 0), lk(C(226, 224, 218)))
						K:plate("DeskPull", 0.5, 0.05, 0.05, bd * CF(u, y + 0.18, 0.03), Look.brushed)
					end
				else
					K:plate("DeskKnee", cw * 0.9, wd.size.Y - 0.3, 0.02, bd * CF(u, wd.min.Y + (wd.size.Y - 0.3) / 2 + 0.05, 0), lk(C(60, 58, 56)))
				end
			end
			hideRec(K, wd)
		end
	end)
	-- 모니터 (장식 파트: 같은 자리에 슬림 모니터로)
	local topY = if wt then wt.max.Y else ld.min.Y
	local mons = {}
	for _, r in V.byName.Monitor or {} do
		if r.c.X >= mn.X - 0.5 and r.c.X <= mx.X + 0.5 and r.c.Z >= mn.Z - 0.5 and r.c.Z <= mx.Z + 0.5 then
			table.insert(mons, r)
		end
	end
	local screens = {
		"PMS  객실 현황\n체크인 예정 14   체크아웃 9\n1203 디럭스 오션뷰  ● 청소 완료",
		"예약 조회\n홍길동 님 · 2박 · 오션뷰 더블\n조식 2인 포함",
		"키 카드 발급\n객실 1507 · 2매\n카드를 엔코더에 올려 주세요",
	}
	for i, r in mons do
		local sd = -face
		for _, s in V.byName.MonitorScreen or {} do
			if (s.c - r.c).Magnitude < 0.6 then
				local d = s.c - r.c
				if d:Dot(face) > 0.01 then
					sd = face
				end
				hideRec(K, s)
			end
		end
		for _, s in V.byName.MonitorStand or {} do
			if math.abs(s.c.X - r.c.X) < 0.6 and math.abs(s.c.Z - r.c.Z) < 0.6 then
				hideRec(K, s)
			end
		end
		hideRec(K, r)
		local base = topAt(r.c.X, topY, r.c.Z, sd)
		K:free(function()
			monitor(K, base, math.max(1.5, math.max(r.size.X, r.size.Z)), screens[(i - 1) % #screens + 1])
			keyboard(K, base * CF(-0.15, 0, 0.62), 1.2)
		end)
	end
	-- 작업대 위 소품 (직원 쪽, Ledge 아래 높이)
	if wt then
		local sd = -face
		local along = V3(math.abs(face.Z), 0, math.abs(face.X))
		local w = if math.abs(face.Z) > 0.5 then wt.size.X else wt.size.Z
		local function at(u: number, off: number): CFrame
			local p = wt.c + along * u + sd * off
			return topAt(p.X, topY, p.Z, sd)
		end
		local depth = if math.abs(face.Z) > 0.5 then wt.size.Z else wt.size.X
		local back = depth / 2 - 0.35
		-- 전화 · 카드 엔코더 · 영수증 프린터 · 펜꽂이 · 서류
		deskPhone(K, at(w / 2 - 0.5, back))
		K:box("KeyEncoder", V3(0.7, 0.18, 0.55), at(-w / 2 + 0.6, back) * CF(0, 0.09, 0), Look.charcoal)
		K:plate("KeyEncoderLED", 0.08, 0.08, 0.01, at(-w / 2 + 0.6, back) * CF(0.22, 0.12, 0.28), Look.ledGreen)
		for j = 1, 3 do
			K:box("KeyCard", V3(0.42, 0.012, 0.27), at(-w / 2 + 0.6, back) * CF(0, 0.19 + j * 0.013, 0) * ANG(0, j * 0.05, 0), lk(if j == 3 then th.accent else C(30, 40, 60)))
		end
		Props.receiptPrinter(K, at(-w / 2 + 1.5, back + 0.05))
		penCup(K, at(w / 2 - 1.3, back + 0.1))
		if not lo(K) then
			paperStack(K, at(0.1, back + 0.05), 0.7, 0.95, 4)
			K:box("PassportScanner", V3(0.8, 0.12, 0.6), at(w / 2 - 2.0, back) * CF(0, 0.06, 0), Look.black)
			K:box("PassportGlass", V3(0.6, 0.01, 0.4), at(w / 2 - 2.0, back) * CF(0, 0.125, 0), lk(C(120, 200, 140), M.Neon, { t = 0.5 }))
		end
	end
	-- 데스크 뒤 직원 공간 예약 (ShopStaff 가 직원을 세움: 새 바닥 소품 금지)
	local bz = if face.Z > 0.5 then V.z0 elseif face.Z < -0.5 then V.z1 else 0
	if math.abs(face.Z) > 0.5 then
		K:reserve(V3(mn.X - 0.4, 0, math.min(bz, mn.Z)), V3(mx.X + 0.4, 6.5, math.max(bz, mn.Z)), "staff")
	else
		local bx = if face.X > 0 then V.x0 else V.x1
		K:reserve(V3(math.min(bx, mn.X), 0, mn.Z - 0.4), V3(math.max(bx, mx.X), 6.5, mx.Z + 0.4), "staff")
	end
	-- 데스크 앞 손님 줄 자리 (새 바닥 소품 금지)
	local f0 = if math.abs(face.Z) > 0.5 then (if face.Z > 0 then mx.Z else mn.Z) else (if face.X > 0 then mx.X else mn.X)
	if math.abs(face.Z) > 0.5 then
		K:reserve(V3(mn.X - 0.3, 0, math.min(f0, f0 + face.Z * 3.2)), V3(mx.X + 0.3, 6.5, math.max(f0, f0 + face.Z * 3.2)), "front")
	else
		K:reserve(V3(math.min(f0, f0 + face.X * 3.2), 0, mn.Z - 0.3), V3(math.max(f0, f0 + face.X * 3.2), 6.5, mx.Z + 0.3), "front")
	end
	K:reserve(mn - V3(0.1, 0, 0.1), mx + V3(0.1, 0, 0.1), "counter")
	return info
end

-- 데스크 뒤 벽: 로고 피처월 + 세계 시계 + 높은 선반
local function hotelFeatureWall(K: any, V: any, th: any, desk: any, rng: () -> number)
	local face = desk.face
	if math.abs(face.Z) < 0.5 or face.Z < 0 then
		return -- 데스크가 입구를 보지 않으면 생략
	end
	local wn = "back"
	local cx = desk.c.X - (V.x0 + V.x1) / 2
	local yTop = math.min(V.H - 0.7, 11)
	local best, bw = nil, 0
	for _, s in V:spans(wn, 0.45, yTop, 1.2) do
		local a, b = math.max(s[1], cx - (desk.max.X - desk.min.X) / 2 - 1.5), math.min(s[2], cx + (desk.max.X - desk.min.X) / 2 + 1.5)
		if b - a > bw then
			best, bw = { a, b }, b - a
		end
	end
	if not best or bw < 3 then
		note(K, "feature wall: no span")
		return
	end
	local a, b = best[1], best[2]
	local w = b - a
	local u = (a + b) / 2
	addWallUsed(K, wn, a - 0.1, b + 0.1, 0, yTop)
	K:free(function()
		local hh = yTop - 0.45
		if th.key == "oak" then
			-- 트래버틴 판 (큰 판 + 줄눈)
			K:plate("FeatureStone", w, hh, 0.06, V:wall(wn, u, 0.45 + hh / 2, 0.01), th.wall)
			local rows = math.floor(hh / 2.4)
			for i = 1, rows do
				K:plate("FeatureJoint", w, 0.03, 0.07, V:wall(wn, u, 0.45 + i * 2.4, 0.01), lk(darker(th.wall.c, 0.2), M.Limestone))
			end
			for i = 1, math.floor(w / 3.6) do
				K:plate("FeatureJoint", 0.03, hh, 0.07, V:wall(wn, a + i * 3.6, 0.45 + hh / 2, 0.01), lk(darker(th.wall.c, 0.2), M.Limestone))
			end
		else
			Props.louverWall(K, wn, a, b, 0.45, yTop, { look = th.wall, back = th.wallBack, pitch = if lo(K) then 0.7 else 0.42 })
		end
		-- 위 · 아래 간접조명 (벽 와셔)
		local wash = K:bar("FeatureLED", V:wall(wn, a + 0.1, yTop - 0.05, 0.25).Position, V:wall(wn, b - 0.1, yTop - 0.05, 0.25).Position, 0.08, 0.06, Look.neon(C(255, 214, 170)))
		K:plate("FeatureCove", w, 0.12, 0.45, V:wall(wn, u, yTop + 0.02, 0.0), lk(C(240, 238, 232)))
		if wash then
			K:light(wash, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 10, Brightness = 0.8, Angle = 100, Color = C(255, 214, 170) })
		end
	end)
	-- 로고 (높은 곳: 직원 머리 위), 부제
	local logoY = math.min(yTop - 1.4, 8.4)
	local logoW = math.min(w * 0.8, 9)
	K:free(function()
		K:plate("LogoBacker", logoW + 0.6, 1.5, 0.08, V:wall(wn, u, logoY, 0.17), lk(darker(th.wallBack.c, 0.2)))
		metalText(K, "HotelLogo", V:wall(wn, u, logoY + 0.18, 0.26), logoW, 0.85, string.upper(V.name or "HOTEL"), th.accent, F.GothamMedium, 0.6)
		txt(K, "HotelLogoSub", logoW * 0.6, 0.3, V:wall(wn, u, logoY - 0.48, 0.3), "GWANGALLI  ·  BUSAN  ·  SINCE 2026", lighter(th.accent, 0.2), nil, { font = F.Gotham })
	end)
	-- 세계 시계 (로고 아래, 직원 머리 위 6.6+)
	local cy = logoY - 1.75
	if cy > 6.3 and w > 5 then
		local cities = { { "SEOUL", 0 }, { "TOKYO", 0 }, { "LONDON", -8 }, { "NEW YORK", -13 } }
		local n = if w > 7.5 then 4 else 3
		local gap = math.min(1.9, (w - 1) / n)
		for i = 1, n do
			local cu = u + (i - (n + 1) / 2) * gap
			K:free(function()
				worldClock(K, V:wall(wn, cu, cy, 0.17), 1.0, cities[i][1], cities[i][2], th.trim, lighter(th.accent, 0.3))
			end)
		end
	else
		-- 시계 대신 작은 안내판
		K:free(function()
			txt(K, "FeatureInfo", math.min(4, w * 0.6), 0.5, V:wall(wn, u, logoY - 1.4, 0.2), "CHECK-IN 15:00   ·   CHECK-OUT 11:00", lighter(th.accent, 0.3), nil, { font = F.GothamMedium })
		end)
	end
end

-- 1인 라운지 체어 (맵 Seat 덮어씌우기: 좌판 윗면 · 범위 같게). ch = V.chairs 항목
local function loungeChair(K: any, V: any, ch: any, th: any): (Vector3?, any?)
	local s = ch.seat
	local backR = nil
	local parts = table.clone(ch.parts)
	for _, r in ch.parts do
		if r.name == "Back" or r.name == "ChairBack" or r.name == "Backrest" then
			backR = r
		end
	end
	-- Scan 의 의자 묶음에 'Back' 이름은 없음: 좌판 옆 1.6 안의 Back 을 직접 찾음
	if not backR then
		for _, r in V.byName.Back or {} do
			local d = r.c - s.c
			if math.abs(d.X) < 1.8 and math.abs(d.Z) < 1.8 and r.min.Y < s.max.Y + 0.5 then
				backR = r
				table.insert(parts, r)
				break
			end
		end
	end
	local face = ch.face
	if backR then
		face = snap(s.c - backR.c)
	end
	-- 전체 범위
	local mn, mx = s.min, s.max
	for _, r in parts do
		mn, mx = mn:Min(r.min), mx:Max(r.max)
	end
	local c = (mn + mx) / 2
	local pcf = pcfAt(V3(c.X, 0, c.Z), face)
	local w = if math.abs(face.X) > 0.5 then mx.Z - mn.Z else mx.X - mn.X -- 가로 (팔걸이 포함)
	local d = if math.abs(face.X) > 0.5 then mx.X - mn.X else mx.Z - mn.Z -- 깊이
	local topY = s.max.Y
	-- 좌판 앞뒤 위치 (pcf 기준)
	local sl = pcf:PointToObjectSpace(s.c)
	local sw = if math.abs(face.X) > 0.5 then s.size.Z else s.size.X
	local sd = if math.abs(face.X) > 0.5 then s.size.X else s.size.Z
	local fab = th.fab
	local frame = lk(darker(fab.c, 0.18), fab.m)
	K:free(function()
		-- 다리 (월넛) + 받침
		K:box("LoungePlinth", V3(w - 0.3, 0.12, d - 0.3), pcf * CF(0, 0.26, 0), Look.walnut)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				K:box("LoungeLeg", V3(0.16, 0.26, 0.16), pcf * CF(sx * (w / 2 - 0.3), 0.13, sz * (d / 2 - 0.3)) * ANG(sz * 0.12, 0, -sx * 0.12), Look.walnut)
			end
		end
		-- 몸통
		K:rbox("LoungeBody", V3(w, topY - 0.45 - 0.3, d), 0.12, pcf * CF(0, 0.32 + (topY - 0.45 - 0.3) / 2, 0), frame)
		-- 좌판 쿠션 (윗면 = 맵 좌판 윗면, 범위 = 맵 좌판)
		K:rbox("LoungeCushion", V3(sw, 0.45, sd), 0.16, pcf * CF(sl.X, topY - 0.225, sl.Z), fab)
		-- 팔걸이
		local armH = 2.2
		for _, sx in { -1, 1 } do
			local ax = sx * (w / 2 - 0.25)
			K:rbox("LoungeArm", V3(0.5, armH - 0.32, d), 0.2, pcf * CF(ax, 0.32 + (armH - 0.32) / 2, 0), fab)
			if not lo(K) then
				K:box("LoungeArmSeam", V3(0.52, 0.02, d - 0.2), pcf * CF(ax, armH - 0.25, 0), frame)
			end
		end
		-- 등받이 + 등쿠션
		K:rbox("LoungeBack", V3(w - 0.3, 2.65, 0.5), 0.2, pcf * CF(0, 0.32 + 2.65 / 2, -d / 2 + 0.25) * ANG(-0.08, 0, 0), fab)
		K:rbox("LoungeBackCushion", V3(sw - 0.1, 1.15, 0.36), 0.16, pcf * CF(sl.X, topY + 0.62, -d / 2 + 0.66) * ANG(-0.16, 0, 0), lk(lighter(fab.c, 0.06), fab.m))
		if not lo(K) then
			K:rbox("LoungePillow", V3(0.22, 0.72, 0.82), 0.1, pcf * CF(sl.X + sw * 0.22, topY + 0.42, -d / 2 + 0.95) * ANG(-0.3, 0.3, 0.1) * ANG(0, PI / 2, 0), lk(lighter(th.rug.c, 0.25), M.Fabric))
		end
	end)
	for _, r in parts do
		hideRec(K, r)
	end
	K:reserve(mn - V3(0.2, 0, 0.2), mx + V3(0.2, 0, 0.2), "chair")
	-- 앉는 사람 앞 (발 공간)
	return face, { min = mn, max = mx, c = c, w = w, d = d }
end

-- 광안대교 야경 아트 (액자 + 하늘 · 바다 · 주탑 · 케이블 · LED). 반환: LED 파트 목록
local function bridgeArt(K: any, dcf: CFrame, w: number, h: number, frameL: any): { BasePart }
	local leds = {}
	local d = 0.1
	K:plate("ArtFrame", w + 0.24, h + 0.24, d, dcf, frameL)
	local inner = dcf * CF(0, 0, d)
	local iw, ih = w - 0.1, h - 0.1
	-- 하늘 (그라데이션 4단)
	local sky = { C(16, 20, 44), C(28, 30, 70), C(56, 44, 96), C(120, 70, 110) }
	for i, c in sky do
		local bh = ih * 0.6 / #sky
		K:plate("ArtSky", iw, bh + 0.01, 0.01, inner * CF(0, ih / 2 - bh * (i - 0.5), 0), lk(c))
	end
	-- 바다
	K:plate("ArtSea", iw, ih * 0.4, 0.01, inner * CF(0, -ih / 2 + ih * 0.2, 0), lk(C(14, 22, 40)))
	-- 마린시티 실루엣 (오른쪽)
	local bx = iw * 0.12
	for i = 1, (if lo(K) then 3 else 7) do
		local bwid = iw * (0.03 + (i % 3) * 0.012)
		local bht = ih * (0.12 + ((i * 37) % 11) / 30)
		K:plate("ArtTower", bwid, bht, 0.015, inner * CF(bx + i * iw * 0.05, -ih / 2 + ih * 0.4 + bht / 2, 0.002), lk(C(26, 26, 40)))
		if hi(K) then
			for k = 1, 3 do
				K:plate("ArtWindow", bwid * 0.6, 0.022, 0.016, inner * CF(bx + i * iw * 0.05, -ih / 2 + ih * 0.4 + bht * (0.25 * k), 0.003), lk(C(255, 206, 140), M.Neon, { t = 0.6 }))
			end
		end
	end
	-- 다리: 상판 (약간 아치)
	local deckY = -ih / 2 + ih * 0.42
	local x0, x1 = -iw / 2 + 0.05, iw / 2 - 0.05
	K:plate("ArtDeck", iw - 0.1, 0.08, 0.02, inner * CF(0, deckY, 0.004), lk(C(200, 200, 210)))
	K:plate("ArtDeckLow", iw - 0.1, 0.04, 0.02, inner * CF(0, deckY - 0.14, 0.004), lk(C(150, 150, 170)))
	-- 주탑 2개
	local tx = { -iw * 0.22, iw * 0.22 }
	local towH = ih * 0.36
	for _, x in tx do
		for _, o in { -0.07, 0.07 } do
			K:plate("ArtPylon", 0.06, towH, 0.025, inner * CF(x + o, deckY + towH / 2 - 0.12, 0.005), lk(C(220, 220, 230)))
		end
		K:plate("ArtPylonBeam", 0.2, 0.05, 0.025, inner * CF(x, deckY + towH * 0.7, 0.005), lk(C(220, 220, 230)))
	end
	-- 주 케이블 (포물선: 바깥 → 주탑 → 가운데 → 주탑 → 바깥)
	local function cableY(x: number): number
		local top = deckY + towH - 0.14
		if x < tx[1] then
			local t = (x - x0) / (tx[1] - x0)
			return deckY + 0.05 + (top - deckY - 0.05) * t * t
		elseif x > tx[2] then
			local t = (x1 - x) / (x1 - tx[2])
			return deckY + 0.05 + (top - deckY - 0.05) * t * t
		end
		local t = (x - (tx[1] + tx[2]) / 2) / ((tx[2] - tx[1]) / 2)
		return deckY + 0.12 + (top - deckY - 0.12) * t * t
	end
	local segs = if lo(K) then 10 else 22
	local prev = nil
	for i = 0, segs do
		local x = x0 + (x1 - x0) * i / segs
		local p = (inner * CF(x, cableY(x), 0.03)).Position
		if prev then
			local s = K:seg("ArtCableLED", prev, p, 0.035, Look.neon(C(120, 170, 255)))
			if s then
				table.insert(leds, s)
			end
		end
		prev = p
	end
	-- 행어 (세로 줄) + 상판 LED 점
	if not lo(K) then
		for i = 1, 15 do
			local x = x0 + (x1 - x0) * i / 16
			local cy = cableY(x)
			if cy - deckY > 0.12 then
				K:plate("ArtHanger", 0.012, cy - deckY, 0.02, inner * CF(x, (cy + deckY) / 2, 0.006), lk(C(180, 190, 210)))
			end
			local led = K:plate("ArtDeckLED", 0.06, 0.04, 0.02, inner * CF(x, deckY + 0.06, 0.012), Look.neon(C(120, 170, 255)))
			table.insert(leds, led)
		end
	end
	-- 바다 반사 (빛 띠)
	for i = 1, (if lo(K) then 2 else 5) do
		local rw = iw * (0.08 + (i % 3) * 0.05)
		local r = K:plate("ArtReflectLED", rw, 0.025, 0.012, inner * CF(-iw * 0.3 + i * iw * 0.13, deckY - 0.35 - i * 0.12, 0.004), Look.neon(C(120, 170, 255), 0.45))
		table.insert(leds, r)
	end
	-- 달
	K:disc("ArtMoon", ih * 0.09, 0.01, inner * CF(-iw * 0.36, ih * 0.32, 0.004) * ANG(PI / 2, 0, 0), lk(C(250, 240, 210), M.Neon, { t = 0.2 }))
	-- 유리
	K:plate("ArtGlass", w, h, 0.01, dcf * CF(0, 0, d + 0.05), { c = C(230, 236, 240), m = M.Glass, t = 0.9, r = 0.18 })
	-- 작품 라벨
	txt(K, "ArtLabel", 1.6, 0.36, dcf * CF(w / 2 - 0.8, -h / 2 - 0.4, 0.02), "광안대교의 밤 · 2026", C(200, 196, 186), C(40, 40, 42), { font = F.GothamMedium, d = 0.02 })
	return leds
end

-- 라운지: 라운지 체어 덮기 + 사이드 테이블 + 스탠드 + 커피 테이블 + 러그 + 아트
local function hotelLounge(K: any, V: any, th: any, rng: () -> number): any
	local out = { lamp = nil, art = nil }
	local groups = {}
	for _, ch in V.chairs do
		local face, box = loungeChair(K, V, ch, th)
		if face and box then
			table.insert(groups, { face = face, box = box })
		end
	end
	-- 러그 (맵 Rug: 장식, 같은 자리에 테두리 러그로)
	for _, r in V.byName.Rug or {} do
		K:free(function()
			K:box("RugField", V3(r.size.X - 0.02, 0.05, r.size.Z - 0.02), CF(r.c.X, 0.025, r.c.Z), th.rug)
			local bw = 0.35
			for _, s in { -1, 1 } do
				K:box("RugBorder", V3(r.size.X - 0.3, 0.056, bw), CF(r.c.X, 0.028, r.c.Z + s * (r.size.Z / 2 - 0.4)), th.rugEdge)
				K:box("RugBorder", V3(bw, 0.056, r.size.Z - 0.3), CF(r.c.X + s * (r.size.X / 2 - 0.4), 0.028, r.c.Z), th.rugEdge)
			end
		end)
		hideRec(K, r)
	end
	if #groups == 0 then
		return out
	end
	-- 의자 묶음 중심 · 방향 (같은 방향 의자들)
	local face = groups[1].face
	out.face = face
	local mn, mx = groups[1].box.min, groups[1].box.max
	for _, g in groups do
		mn, mx = mn:Min(g.box.min), mx:Max(g.box.max)
	end
	local c = (mn + mx) / 2
	local side = V3(-face.Z, 0, face.X) -- 의자 줄 방향
	-- 사이드 테이블 + 테이블 램프: 의자 사이
	if #groups >= 2 then
		local a, b = groups[1].box, groups[2].box
		local mid = (a.c + b.c) / 2
		local pcf = pcfAt(V3(mid.X, 0, mid.Z), face) * CF(0, 0, -0.35)
		if claim(K, pcf, V3(1.05, 3.6, 1.05), 0, "lounge") then
			K:vcyl("SideTableTop", 0.08, 1.05, pcf * CF(0, 1.95, 0), th.top)
			K:vcyl("SideTableStem", 1.85, 0.12, pcf * CF(0, 0.98, 0), th.trim)
			K:vcyl("SideTableFoot", 0.06, 0.7, pcf * CF(0, 0.03, 0), th.trim)
			-- 램프
			K:ell("LampBase", V3(0.42, 0.55, 0.42), pcf * CF(0, 2.25, 0), lk(C(236, 230, 220), M.Glass, { t = 0.1 }))
			K:vcyl("LampStem", 0.4, 0.05, pcf * CF(0, 2.7, 0), th.trim)
			K:vcyl("LampShade", 0.55, 0.8, pcf * CF(0, 3.15, 0), lk(C(244, 236, 220), M.Fabric, { t = 0.12 }))
			local bulb = K:ball("LampBulb", 0.26, pcf * CF(0, 3.0, 0), Look.lampWarm)
			K:light(bulb, "PointLight", { Range = 9, Brightness = 0.7, Color = Look.warmLight })
			out.lamp = { bulb = bulb, shade = nil }
		end
	end
	-- 커피 테이블: 의자 앞 (face 쪽)
	local front = if math.abs(face.X) > 0.5 then (if face.X > 0 then mx.X else mn.X) else (if face.Z > 0 then mx.Z else mn.Z)
	local cp = if math.abs(face.X) > 0.5 then V3(front + face.X * 1.55, 0, c.Z) else V3(c.X, 0, front + face.Z * 1.55)
	local tcf = pcfAt(cp, -face)
	local tw, tl = 2.0, math.min(3.4, (if math.abs(face.X) > 0.5 then mx.Z - mn.Z else mx.X - mn.X) - 1.2)
	if claim(K, tcf, V3(tl, 1.4, tw), 0.05, "lounge") then
		K:slab("CoffeeTop", tl, tw, 0.12, 0.5, tcf * CF(0, 1.32, 0) * ANG(0, PI / 2, 0), th.top)
		K:slab("CoffeeShelf", tl - 0.4, tw - 0.4, 0.06, 0.4, tcf * CF(0, 0.45, 0) * ANG(0, PI / 2, 0), Look.walnut)
		for _, sx in { -1, 1 } do
			K:box("CoffeeLeg", V3(0.1, 1.25, tw - 0.4), tcf * CF(sx * (tl / 2 - 0.35), 0.64, 0), th.trim)
		end
		-- 위: 쟁반 + 디퓨저 + 책 + 작은 화분
		local top = tcf * CF(0, 1.38, 0)
		K:slab("CoffeeTray", 0.9, 1.3, 0.04, 0.12, top * CF(-tl * 0.22, 0.02, 0) * ANG(0, PI / 2, 0), th.trim)
		K:vcyl("DiffuserBottle", 0.42, 0.3, top * CF(-tl * 0.22 - 0.2, 0.25, 0.1), lk(C(60, 40, 30), M.Glass, { t = 0.3 }))
		if not lo(K) then
			for i = 0, 5 do
				local a = i * PI / 3
				K:seg("DiffuserReed", (top * CF(-tl * 0.22 - 0.2, 0.4, 0.1)).Position, (top * CF(-tl * 0.22 - 0.2 + math.cos(a) * 0.3, 1.2, 0.1 + math.sin(a) * 0.3)).Position, 0.025, lk(C(60, 44, 30), M.Wood))
			end
		end
		K:box("CoffeeBook", V3(1.1, 0.12, 0.85), top * CF(tl * 0.18, 0.06, 0.15) * ANG(0, 0.15, 0), lk(C(30, 50, 80)))
		K:box("CoffeeBook", V3(0.95, 0.1, 0.75), top * CF(tl * 0.18, 0.17, 0.15) * ANG(0, -0.1, 0), lk(C(236, 228, 210)))
		txt(K, "CoffeeBookTitle", 0.7, 0.25, CFrame.fromMatrix((top * CF(tl * 0.18, 0.225, 0.15)).Position, (top * ANG(0, -0.1, 0)).XVector, -(top * ANG(0, -0.1, 0)).ZVector, Vector3.yAxis) * ANG(-PI / 2, 0, 0) * ANG(PI / 2, 0, 0), "BUSAN", C(40, 40, 44), nil, { d = 0.005, font = F.GothamBlack })
		Props.potPlant(K, top * CF(tl * 0.36, 0, -0.35), 0.34, 0.5, { pot = lk(C(236, 232, 224), M.Concrete) })
	end
	-- 아트: 의자 등 뒤 벽
	local wn = if math.abs(face.X) > 0.5 then (if face.X > 0 then "left" else "right") else (if face.Z > 0 then "back" else "front")
	if wn ~= "front" then
		local wu = V:wallCoord(wn, c)
		local aw = math.clamp((if math.abs(face.X) > 0.5 then mx.Z - mn.Z else mx.X - mn.X) + 1.2, 4, 8.5)
		local ah = math.min(aw * 0.5, V.H * 0.38)
		local ay = math.max(3.2 + ah / 2 + 0.6, math.min(V.H * 0.52, 3.4 + ah / 2 + 1.4))
		if wallFree(K, wn, wu, aw + 0.4, ay - ah / 2 - 0.3, ay + ah / 2 + 0.6, 0.5) then
			local dcf = V:wall(wn, wu, ay, 0.02)
			K:free(function()
				out.art = bridgeArt(K, dcf, aw, ah, th.trim)
				out.artFrame = K:plate("ArtHit", 0.4, 0.4, 0.02, dcf * CF(-aw / 2 + 0.4, -ah / 2 + 0.3, 0.18), { c = C(0, 0, 0), t = 1 })
				-- 아트 조명 (위 픽처 라이트)
				K:box("PictureLightArm", V3(0.1, 0.1, 0.5), dcf * CF(0, ah / 2 + 0.25, 0.25), th.trim)
				local pl = K:cyl("PictureLightLED", aw * 0.4, 0.16, dcf * CF(0, ah / 2 + 0.25, 0.5), Look.lampWarm)
				K:cyl("PictureLightHood", aw * 0.42, 0.24, dcf * CF(0, ah / 2 + 0.3, 0.5), th.trim)
				K:light(pl, "SpotLight", { Face = Enum.NormalId.Bottom, Range = 6, Brightness = 0.6, Angle = 70, Color = Look.warmLight })
			end)
		end
	end
	-- 플로어 램프: 라운지 모서리
	local half = (if math.abs(side.X) > 0.5 then mx.X - mn.X else mx.Z - mn.Z) / 2 + 0.95
	local pcfL = nil
	for _, sg in { -1, 1 } do
		for _, k in { 0, 0.5, -0.5 } do
			local p = c + side * (sg * half) - face * k
			local pc = pcfAt(V3(p.X, 0, p.Z), face)
			if not pcfL and Interact.canPrompt(K, V3(p.X, 4.75, p.Z)) and claim(K, pc, V3(1.4, 5.6, 1.4), 0, "lounge") then
				pcfL = pc
			end
		end
	end
	if pcfL then
		K:disc("FloorLampBase", 1.0, 0.1, pcfL * CF(0, 0.05, 0), th.trim)
		K:vcyl("FloorLampPole", 4.4, 0.08, pcfL * CF(0, 2.3, 0), th.trim)
		K:vcyl("FloorLampShade", 1.0, 1.15, pcfL * CF(0, 4.9, 0), lk(C(244, 236, 220), M.Fabric, { t = 0.15 }))
		local b = K:ball("FloorLampBulb", 0.3, pcfL * CF(0, 4.75, 0), Look.lampWarm)
		out.floorLamp = b
	end
	return out
end

-- 천장 링 샹들리에 (라운지 위)
local function ringChandelier(K: any, V: any, p: Vector3, dia: number, th: any): { BasePart }
	local y = math.max(7.6, V.H - 3.2)
	local parts = {}
	K:free(function()
		K:disc("ChandCanopy", 0.8, 0.08, CF(p.X, V.H - 0.04, p.Z), th.trim)
		for i = 0, 2 do
			local a = i * PI * 2 / 3
			K:seg("ChandWire", V3(p.X, V.H - 0.05, p.Z), V3(p.X + math.cos(a) * dia / 2, y, p.Z + math.sin(a) * dia / 2), 0.02, Look.black)
		end
		local f = CF(p.X, y, p.Z) * ANG(PI / 2, 0, 0)
		for _, s in K:ring("ChandRingLED", f, dia / 2, 0.16, if lo(K) then 12 else 22, Look.neon(C(255, 222, 180))) do
			table.insert(parts, s)
		end
		for _, s in K:ring("ChandRing", f * CF(0, 0, -0.1), dia / 2, 0.2, if lo(K) then 8 else 16, th.trim) do
			_ = s
		end
		local f2 = CF(p.X, y - 0.9, p.Z) * ANG(PI / 2, 0, 0)
		for _, s in K:ring("ChandRingLED", f2, dia * 0.32, 0.12, if lo(K) then 10 else 16, Look.neon(C(255, 222, 180))) do
			table.insert(parts, s)
		end
		for i = 0, 2 do
			local a = i * PI * 2 / 3 + 0.5
			K:seg("ChandWire", V3(p.X + math.cos(a) * dia / 2 * 0.9, y, p.Z + math.sin(a) * dia / 2 * 0.9), V3(p.X + math.cos(a) * dia * 0.32, y - 0.9, p.Z + math.sin(a) * dia * 0.32), 0.02, Look.black)
		end
		if parts[1] then
			K:light(parts[1], "PointLight", { Range = 14, Brightness = 0.7, Color = C(255, 222, 180) })
		end
	end)
	Common.useCeil(K, p.X, p.Z)
	return parts
end

-- 짐 카트 (브라스 버드케이지)
local function luggageCart(K: any, pcf: CFrame, th: any)
	local L, W = 3.0, 1.6
	K:box("CartDeck", V3(W, 0.2, L), pcf * CF(0, 0.45, 0), lk(C(120, 30, 40), M.Fabric))
	K:box("CartDeckFrame", V3(W + 0.08, 0.12, L + 0.08), pcf * CF(0, 0.32, 0), th.trim)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:vcyl("CartCaster", 0.25, 0.1, pcf * CF(sx * (W / 2 - 0.15), 0.18, sz * (L / 2 - 0.2)), Look.black)
			K:cyl("CartWheel", 0.1, 0.3, pcf * CF(sx * (W / 2 - 0.15), 0.15, sz * (L / 2 - 0.2)), Look.rubber)
		end
	end
	-- 양 끝 세움대 + 아치 + 가운데 걸이봉
	for _, sz in { -1, 1 } do
		for _, sx in { -1, 1 } do
			K:seg("CartPost", (pcf * CF(sx * 0.55, 0.5, sz * (L / 2 - 0.12))).Position, (pcf * CF(sx * 0.55, 4.3, sz * (L / 2 - 0.12))).Position, 0.1, th.trim)
		end
		K:ring("CartArch", pcf * CF(0, 4.3, sz * (L / 2 - 0.12)), 0.55, 0.1, if lo(K) then 4 else 8, th.trim, 0, PI)
	end
	K:seg("CartRail", (pcf * CF(0, 4.85, -L / 2 + 0.12)).Position, (pcf * CF(0, 4.85, L / 2 - 0.12)).Position, 0.09, th.trim)
	-- 짐: 캐리어 2 + 가방
	if not lo(K) then
		K:rbox("CartSuitcase", V3(0.9, 2.0, 1.3), 0.12, pcf * CF(0, 1.55, -0.6), lk(C(40, 60, 90)))
		K:seg("SuitcaseHandle", (pcf * CF(0, 2.55, -0.6)).Position, (pcf * CF(0, 3.0, -0.6)).Position, 0.06, Look.darkAlu)
		K:rbox("CartSuitcase", V3(0.8, 1.6, 1.1), 0.12, pcf * CF(0.1, 1.35, 0.7), lk(C(196, 180, 150)))
		K:ell("CartDuffel", V3(1.3, 0.7, 0.8), pcf * CF(0, 2.75, 0.6), lk(C(60, 50, 44), M.Leather))
	end
end

-- 관광 안내 브로슈어 랙
local function brochureRack(K: any, pcf: CFrame, w: number)
	K:box("RackBack", V3(w, 4.3, 0.12), pcf * CF(0, 2.35, -0.38), Look.darkAlu)
	K:box("RackBase", V3(w + 0.1, 0.2, 0.9), pcf * CF(0, 0.1, 0), Look.darkAlu)
	local titles = {
		{ "광안대교\n드론쇼", C(30, 60, 140) }, { "해운대\n블루라인", C(20, 130, 160) }, { "감천\n문화마을", C(230, 120, 60) },
		{ "부산\n시티투어", C(200, 40, 50) }, { "민락 수변\n회센터", C(60, 140, 90) }, { "자갈치\n시장", C(140, 80, 160) },
		{ "BUSAN\nMAP", C(240, 200, 60) }, { "요트\n투어", C(30, 100, 200) }, { "송정\n서핑", C(20, 160, 140) },
	}
	local cols = math.max(2, math.floor(w / 0.72))
	local cw = (w - 0.1) / cols
	local i = 0
	for row = 0, 3 do
		local y = 0.9 + row * 1.0
		K:box("RackPocket", V3(w - 0.06, 0.36, 0.08), pcf * CF(0, y, 0.12) * ANG(-0.25, 0, 0), lk(C(220, 230, 236), M.Glass, { t = 0.45 }))
		for col = 0, cols - 1 do
			i += 1
			local t = titles[(i - 1) % #titles + 1]
			local x = -w / 2 + 0.05 + cw * (col + 0.5)
			local d = pcf * CF(x, y + 0.3, 0.02) * ANG(-0.18, 0, 0)
			K:plate("Brochure", cw * 0.86, 0.8, 0.03, d, lk(t[2]))
			if not lo(K) then
				txt(K, "BrochureText", cw * 0.78, 0.4, d * CF(0, 0.14, 0.035), t[1], WHITE, nil, { font = F.GothamBlack, d = 0.004 })
			end
		end
	end
	txt(K, "RackHeader", w, 0.4, pcf * CF(0, 4.75, -0.32), "BUSAN TOUR INFO  관광 안내", WHITE, C(30, 40, 60), { font = F.GothamBold, d = 0.04 })
end

-- 엘리베이터 홀: 위 안내 띠 + 층별 안내판 (엘리베이터 파트는 그대로)
local function elevatorHall(K: any, V: any, th: any?, kind: string)
	local els = V.byName.ElevatorDoor
	if not els or #els == 0 then
		return nil
	end
	local mn, mx = els[1].min, els[1].max
	for _, nm in { "ElevatorDoor", "ElevatorJamb", "ElevatorHead" } do
		for _, r in V.byName[nm] or {} do
			mn, mx = mn:Min(r.min), mx:Max(r.max)
		end
	end
	local wn = nearestWall(V, (mn + mx) / 2)
	local cu = V:wallCoord(wn, (mn + mx) / 2)
	local w = if wn == "back" then mx.X - mn.X else mx.Z - mn.Z
	local headTop = mx.Y
	local info: any = { wall = wn, u = cu, w = w, top = headTop }
	-- 엘리베이터 위 안내 띠
	if V.H - headTop > 1.0 then
		local bh = math.min(1.1, V.H - headTop - 0.35)
		local y = headTop + 0.2 + bh / 2
		if wallFree(K, wn, cu, w, y - bh / 2, y + bh / 2, 0.3) then
			K:free(function()
				K:plate("ElevBand", w + 0.6, bh, 0.1, V:wall(wn, cu, y, 0.01), if th then lk(darker(th.wallBack.c, 0.1)) else lk(C(52, 54, 58), M.Metal))
				local fg = if th then th.accent else C(230, 230, 232)
				metalText(K, "ElevSign", V:wall(wn, cu, y, 0.12), math.min(w * 0.7, 6), bh * 0.5, if kind == "hotel" then "ELEVATOR  ·  객실 3F - 15F" else "ELEVATOR  ·  승강기", fg, F.GothamMedium)
			end)
		end
	end
	-- 엘리베이터 문 옆: 점검 안내 종이 (콜버튼 위)
	for _, cb in V.byName.CallButton or {} do
		local u = V:wallCoord(wn, cb.c)
		if wallFree(K, wn, u, 0.9, cb.max.Y + 0.4, cb.max.Y + 1.7, 0.2) then
			K:free(function()
				paper(K, V:wall(wn, u, cb.max.Y + 1.05, 0.01), 0.82, 1.15, if kind == "hotel" then "객실 안내" else "정기점검 안내", if kind == "hotel" then "객실층은 키 카드를\n대야 운행합니다\nRoom key required" else "10월 21일(화)\n10:00~12:00\n1호기 운행 중지\n- 관리사무소 -", { tape = true, titleFg = C(200, 40, 40) })
			end)
		end
		break
	end
	return info
end

local function hotelInteract(K: any, V: any, lounge: any)
	-- 1) 광안대교 아트 조명 모드
	if lounge.art and #lounge.art > 0 then
		local modes = {
			{ "블루 라이트", C(120, 170, 255) }, { "레인보우 쇼", C(255, 120, 200) }, { "골드 나이트", C(255, 200, 110) }, { "드론쇼 화이트", C(240, 246, 255) }, { "끄기", nil },
		}
		local hit = lounge.artFrame or lounge.art[1]
		local base = {}
		for _, p in lounge.art do
			table.insert(base, { p = p, t = p.Transparency })
		end
		promptOn(K, { hit, lounge.art[#lounge.art] }, {
			action = "조명 모드 바꾸기",
			object = "광안대교 야경 아트",
			fn = function(n)
				local m = modes[n % #modes + 1]
				for i, b in base do
					if b.p.Parent then
						if m[2] then
							local col: Color3 = m[2]
							if m[1] == "레인보우 쇼" then
								col = Color3.fromHSV((i * 0.07) % 1, 0.6, 1)
							end
							b.p.Material = M.Neon
							b.p.Color = col
						else
							b.p.Material = M.SmoothPlastic
							b.p.Color = C(60, 64, 80)
						end
					end
				end
			end,
		})
	end
	-- 2) 스탠드 켜기/끄기
	local lamps = {}
	for _, p in { lounge.lamp and lounge.lamp.bulb, lounge.floorLamp } do
		if p then
			table.insert(lamps, p)
		end
	end
	if #lamps > 0 then
		local target = lounge.floorLamp or lamps[1]
		local function set(on: boolean)
			for _, p in lamps do
				if p.Parent then
					p.Material = if on then M.Neon else M.SmoothPlastic
					p.Color = if on then C(255, 214, 160) else C(200, 196, 188)
					for _, l in p:GetChildren() do
						if l:IsA("Light") then
							l.Enabled = on
						end
					end
				end
			end
		end
		local pr = nil
		for _, p in { target, lamps[1] } do
			if p and not pr then
				pr = Interact.toggle(K, p, { object = "라운지 스탠드", onText = "스탠드 끄기", offText = "스탠드 켜기", state = true, on = set })
			end
		end
	end
end

local function buildHotel(K: any, V: any, S: any)
	local th = hotelTheme(V)
	local rng = mkRng(V.key or V.name)
	local desk = nil
	step(K, "skin", function()
		local wp = if th.key == "dark" then lk(C(196, 186, 172), M.Fabric) elseif th.key == "oak" then lk(C(228, 222, 208), M.Fabric) else lk(C(216, 208, 194), M.Fabric)
		wallSkin(K, { "left", "right", "back" }, 3.6, V.H - 0.02, wp, th.trim)
		coveLED(K, { "left", "right" }, C(255, 214, 170), true)
	end)
	step(K, "desk", function()
		desk = hotelDesk(K, V, th, rng)
	end)
	local lounge: any = {}
	step(K, "lounge", function()
		lounge = hotelLounge(K, V, th, rng)
	end)
	step(K, "feature", function()
		if desk then
			hotelFeatureWall(K, V, th, desk, rng)
		end
	end)
	step(K, "elevator", function()
		elevatorHall(K, V, th, "hotel")
	end)
	-- 데스크 위 펜던트 (Ledge keep 위 7.2 보다 높게)
	step(K, "pendants", function()
		if not desk then
			return
		end
		local ld = desk.ledge
		local alongX = math.abs(desk.face.Z) > 0.5
		local len = if alongX then ld.size.X else ld.size.Z
		local n = if len > 5.5 then 3 else 2
		for i = 1, n do
			local u = -len / 2 + len * (i - 0.5) / n
			local p = if alongX then V3(ld.c.X + u, V.H, ld.c.Z - desk.face.Z * 0.3) else V3(ld.c.X - desk.face.X * 0.3, V.H, ld.c.Z + u)
			if Common.ceilFree(K, p.X, p.Z, 0.5) then
				local drop = math.max(1.2, V.H - math.max(8.2, ld.max.Y + 4.2))
				K:free(function()
					Props.pendant(K, p, drop, { shade = "globe", dia = 0.95, look = lk(C(240, 236, 226), M.Glass, { t = 0.25 }), light = (i == 2 or n == 2 and i == 1), range = 10, bright = 0.6 })
				end)
				Common.useCeil(K, p.X, p.Z)
			end
		end
	end)
	-- 라운지 위 샹들리에
	step(K, "chandelier", function()
		local mn, mx = nil, nil
		for _, ch in V.chairs do
			mn = if mn then mn:Min(ch.seat.min) else ch.seat.min
			mx = if mx then mx:Max(ch.seat.max) else ch.seat.max
		end
		local cands = {}
		if mn and mx then
			local c = (mn + mx) / 2
			local f = if V.chairs[1] then V.chairs[1].face else V3(1, 0, 0)
			if lounge and lounge.face then
				f = lounge.face
			end
			for _, k in { 3.2, 2.6, 3.8, 2.0 } do
				table.insert(cands, c + f * k)
			end
		end
		table.insert(cands, V3((V.x0 + V.x1) / 2 - V.W * 0.25, 0, (V.z0 + V.z1) / 2 + 0.5))
		if V.H >= 9.5 then
			for _, p in cands do
				if Common.ceilFree(K, p.X, p.Z, 0.7) then
					ringChandelier(K, V, p, math.min(4.2, V.W * 0.2), th)
					break
				end
			end
		end
	end)
	-- 객실 요금 사이니지 (데스크 옆, 입구 쪽)
	step(K, "signage", function()
		if not desk then
			return
		end
		local f = desk.face
		local ends = if math.abs(f.Z) > 0.5 then { V3(desk.min.X - 1.0, 0, desk.max.Z + 0.4), V3(desk.max.X + 1.0, 0, desk.max.Z + 0.4), V3(desk.min.X - 1.0, 0, desk.c.Z) } else { V3(desk.c.X, 0, desk.min.Z - 1.0), V3(desk.c.X, 0, desk.max.Z + 1.0) }
		local pcf = floorSpot(K, ends, V3(1.7, 5.6, 1.1), V3(0, 0, 1), 0.1, "sign")
		if pcf then
			signageStand(K, pcf, 1.45, 2.6, {
				{ c = C(18, 30, 60), text = "객실 요금 안내\n\n스탠다드 더블  99,000\n디럭스 오션뷰  149,000\n패밀리 트윈  169,000\n스위트  320,000\n\n※ 주말·성수기 별도" },
				{ c = C(40, 26, 20), text = "조식 뷔페\nBREAKFAST\n\n2F 레스토랑\n06:30 - 10:00\n성인 25,000원\n어린이 15,000원" },
				{ c = C(14, 50, 70), text = "오늘의 광안리\n\n맑음  21°C\n\n광안리 M 드론쇼\n매주 토 20:00 / 22:00" },
				{ c = C(30, 30, 34), text = "Wi-Fi\n\nHOTEL_GUEST\nPW  gwangalli2026\n\n짐 보관 서비스\n프런트에 문의하세요" },
			}, 5)
		end
	end)
	-- 짐 카트 · 브로슈어 랙 · 우산 비닐 · 화분
	step(K, "cart", function()
		local d = V.door
		local pref = if d then V3(d.x, 0, V.z1 - 3) else V3(0, 0, V.z1 - 3)
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 3.3, 1.9, 5.1, pref, 0.05, "cart")
		if not (wn and pcf) then
			-- 벽에 못 붙이면 입구 옆 빈 바닥
			local cands = {}
			for _, x in { -1, 1 } do
				for _, z in { 3.4, 2.6, 1.6 } do
					table.insert(cands, V3((if d then d.x else 0) + x * ((if d then d.w / 2 else 2.4) + 4.2), 0, math.min(z, V.z1 - 3.6)))
				end
			end
			pcf = floorSpot(K, cands, V3(3.3, 5.1, 1.9), V3(0, 0, 1), 0.05, "cart")
		end
		if pcf then
			luggageCart(K, pcf * ANG(0, PI / 2, 0), th)
		end
	end)
	step(K, "brochure", function()
		local wn, pcf = wallFloorSpot(K, { "left", "right" }, 2.2, 1.0, 5.0, V3(0, 0, V.z1 - 3), 0.05, "rack")
		if wn and pcf then
			brochureRack(K, pcf, 2.2)
		end
	end)
	step(K, "umbrella", function()
		local d = V.door
		if not d then
			return
		end
		local cands = { V3(d.x - d.w / 2 - 2.9, 0, V.z1 - 1.0), V3(d.x + d.w / 2 + 2.9, 0, V.z1 - 1.0), V3(d.x - d.w / 2 - 2.9, 0, V.z1 - 2.6), V3(d.x + d.w / 2 + 2.9, 0, V.z1 - 2.6) }
		local pcf = floorSpot(K, cands, V3(2.4, 3.0, 1.0), V3(0, 0, 1), 0.05, "umbrella")
		if pcf then
			umbrellaBagger(K, pcf, if pcf.Position.X < d.x then -1 else 1)
		end
	end)
	step(K, "plants", function()
		for _, p in { V3(V.x0 + 1.1, 0, V.z0 + 1.1), V3(V.x1 - 1.1, 0, V.z0 + 1.1) } do
			plantAt(K, pcfAt(p, V3(0, 0, 1)), pickR(rng, { "olive", "ficus", "monstera" }), math.min(6.5, V.H * 0.5), 1.4, lk(C(60, 58, 56), M.Concrete))
		end
	end)
	-- 큰 벽 소품 뒤 작은 벽 부착물 (스위치 · 콘센트 · 등록증 ...)
	step(K, "fixtures", function()
		Common.fixtures(K, V, S)
	end)
	-- 벽: 층별 안내 · 와이파이 · 관광 포스터 · 비상구
	step(K, "walls", function()
		local els = V.byName.ElevatorDoor
		local ep = if els and els[1] then els[1].c else V3(0, 0, V.z0)
		local wn, d = spotNear(K, { "back", "left", "right" }, 2.2, 3.6, 6.8, ep + V3(-4, 0, 0))
		if wn and d then
			K:plate("DirBoard", 2.2, 3.2, 0.08, d, lk(darker(th.wallBack.c, 0.1)))
			txt(K, "DirTitle", 1.9, 0.4, d * CF(0, 1.3, 0.09), "FLOOR GUIDE  층별 안내", th.accent, nil, { font = F.GothamBold })
			txt(K, "DirBody", 1.9, 2.3, d * CF(0, -0.2, 0.09), "R   루프탑 바 · 인피니티 풀\n16F  스카이 라운지\n3-15F  객실 ROOMS\n2F  조식 레스토랑 · 피트니스\n1F  로비 · 프런트 · 편의점\nB1  주차장 PARKING", lighter(th.accent, 0.5), nil, { font = F.GothamMedium, align = "Left" })
		end
		local wn2, d2 = spotNear(K, { "right", "left", "back" }, 1.6, 4.0, 6.2, V3(V.x1, 0, 1))
		if wn2 and d2 then
			Props.frame(K, d2, 1.5, 2.0, { frame = th.trim, text = "광안리 해변\n도보 1분\n\nBEACH 1 MIN\n\n체크아웃 후\n짐 보관 무료", fg = C(30, 50, 80), bg = C(238, 242, 244), border = 0.06 })
		end
		local wn3, d3 = spotNear(K, { "left", "right" }, 1.7, math.min(7.2, V.H - 1.4), math.min(7.9, V.H - 0.7), V3(V.x0, 0, V.z1 - 2))
		if wn3 and d3 then
			exitSign(K, d3)
		end
	end)
	step(K, "interact", function()
		hotelInteract(K, V, lounge)
	end)
end

---------------------------------------------------------------------------------------------------
-- 5. 모텔 로비 (프런트 창구 + 객실 현황판 + 무인 키오스크)
---------------------------------------------------------------------------------------------------

local function buildMotel(K: any, V: any, S: any)
	local rng = mkRng(V.key or V.name)
	local accent = C(220, 60, 120)
	local gold = Look.goldMetal
	local name = V.name or "MOTEL"
	local leds = {}
	-- 프런트 창구 (벽 매립, 깊이 0.8): 옆벽 우선
	step(K, "window", function()
		local w = 3.4
		local wn, d = wallItemSpot(K, { "right", "left" }, w + 0.6, 0.4, 7.0, 0, nil, 0.9)
		if not wn or not d then
			note(K, "motel window: no wall")
			return
		end
		local base = d * CF(0, -3.7, 0)
		K:free(function()
			-- 아랫벽 (판넬) + 창 테 + 선반
			K:plate("FrontLowWall", w, 3.0, 0.3, base * CF(0, 1.9, 0), lk(C(40, 30, 36), M.Wood))
			for i = 1, 3 do
				K:plate("FrontLowLine", w, 0.03, 0.31, base * CF(0, 0.6 + i * 0.75, 0), gold)
			end
			K:plate("FrontLedge", w + 0.3, 0.14, 0.8, base * CF(0, 3.45, 0), Look.marbleBlack)
			K:plate("FrontLedgeEdge", w + 0.3, 0.14, 0.05, base * CF(0, 3.45, 0.8), gold)
			K:plate("FrontFrame", w, 2.5, 0.1, base * CF(0, 4.8, 0), lk(C(30, 24, 28), M.Wood))
			K:plate("FrontGlass", w - 0.4, 2.0, 0.05, base * CF(0, 4.85, 0.1), lk(C(60, 46, 50), M.Glass, { t = 0.25, r = 0.2 }))
			K:plate("FrontGlassFrost", w - 0.4, 1.1, 0.06, base * CF(0, 5.3, 0.11), lk(C(200, 190, 190), M.Glass, { t = 0.35 }))
			K:plate("FrontSlot", 1.3, 0.35, 0.12, base * CF(0, 3.7, 0.1), Look.black)
			txt(K, "FrontGlassText", w - 0.8, 0.5, base * CF(0, 5.4, 0.18), "FRONT  ·  안내", WHITE, nil, { font = F.GothamMedium })
			local glow = K:plate("FrontWindowLED", w - 0.4, 0.06, 0.05, base * CF(0, 3.62, 0.62), Look.neon(C(255, 170, 200)))
			table.insert(leds, glow)
			K:plate("FrontHeader", w + 0.3, 0.8, 0.25, base * CF(0, 6.45, 0), lk(C(24, 20, 24)))
			local sign = txt(K, "FrontHeaderText", w - 0.2, 0.55, base * CF(0, 6.45, 0.26), name, accent, nil, { font = F.GothamBlack, glow = 1.6 })
			_ = sign
			-- 선반 위 (작은 벨 대신 안내 아크릴 + 어메니티 바구니)
			local top = base * CF(0, 3.52, 0.45)
			local tcf = CFrame.fromMatrix(top.Position, top.XVector, Vector3.yAxis, top.ZVector)
			Props.menuStand(K, tcf * CF(-1.1, 0, 0), "대실 4시간\n30,000원\n숙박 60,000원\n(주말 80,000원)")
			K:box("AmenityBasket", V3(1.0, 0.35, 0.5), tcf * CF(1.0, 0.18, -0.05), Look.rattan)
			if not lo(K) then
				for i = 0, 3 do
					K:box("AmenityPack", V3(0.18, 0.4, 0.12), tcf * CF(0.65 + i * 0.22, 0.45, -0.05) * ANG(0, 0, (i - 1.5) * 0.08), lk(pickR(rng, { C(240, 240, 240), C(120, 200, 230), C(240, 180, 200) })))
				end
			end
		end)
	end)
	-- 객실 현황판 (다른 벽)
	local statusDots = {}
	step(K, "status", function()
		local w = 3.2
		local wn, d = wallItemSpot(K, { "left", "right", "back" }, w, 3.6, 7.0, 0)
		if not wn or not d then
			return
		end
		K:free(function()
			K:plate("StatusBoard", w, 3.0, 0.1, d, Look.black)
			K:plate("StatusFrame", w + 0.1, 3.1, 0.06, d * CF(0, 0, -0.04), gold)
			txt(K, "StatusTitle", w * 0.9, 0.36, d * CF(0, 1.25, 0.11), "객실 현황  ROOM STATUS", C(255, 220, 160), nil, { font = F.GothamBold, glow = 1.2 })
			local rooms = { 201, 202, 203, 205, 206, 301, 302, 303, 305, 306, 401, 402, 403, 405, 406 }
			for i, rm in rooms do
				local col = (i - 1) % 5
				local row = (i - 1) // 5
				local x = -w / 2 + 0.35 + col * ((w - 0.5) / 5) + 0.15
				local y = 0.75 - row * 0.62
				local busy = rng() < 0.55
				txt(K, "StatusRoom", 0.5, 0.26, d * CF(x - 0.06, y, 0.11), tostring(rm), WHITE, nil, { font = F.GothamBold, glow = 0.8 })
				local dot = K:ball("StatusLED", 0.14, d * CF(x + 0.28, y, 0.14), if busy then Look.ledRed else Look.ledGreen)
				table.insert(statusDots, dot)
			end
			txt(K, "StatusLegend", w * 0.9, 0.28, d * CF(0, -1.25, 0.11), "● 입실 가능    ● 사용 중  ·  대실 최대 4시간", C(200, 200, 204), nil, { font = F.GothamMedium })
		end)
	end)
	-- 무인 키오스크 (바닥)
	local kioskScreen, kioskLab = nil, nil
	step(K, "kiosk", function()
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.8, 1.3, 5.6, V3(0, 0, V.z0 + 3), 0.05, "kiosk")
		if not wn or not pcf then
			return
		end
		K:box("KioskBase", V3(1.8, 0.3, 1.2), pcf * CF(0, 0.15, 0), Look.black)
		K:rbox("KioskBody", V3(1.6, 4.4, 0.9), 0.12, pcf * CF(0, 2.5, -0.1), lk(C(32, 30, 34)))
		K:plate("KioskBezel", 1.36, 2.2, 0.03, pcf * CF(0, 3.5, 0.35) * ANG(-0.12, 0, 0), Look.black)
		kioskScreen = K:plate("KioskScreen", 1.2, 2.0, 0.02, pcf * CF(0, 3.5, 0.38) * ANG(-0.12, 0, 0), { c = C(30, 20, 40), m = M.Neon, t = 0.1 })
		local _, lab = txt(K, "KioskText", 1.1, 1.8, pcf * CF(0, 3.5, 0.405) * ANG(-0.12, 0, 0), "무인 체크인\n\n대실  30,000\n숙박  60,000\n\n화면을 눌러 주세요", WHITE, nil, { font = F.GothamBold, glow = 1.1 })
		kioskLab = lab
		K:plate("KioskCardSlot", 0.5, 0.12, 0.05, pcf * CF(0.3, 2.05, 0.35), Look.chrome)
		K:plate("KioskPrinter", 0.6, 0.08, 0.05, pcf * CF(-0.3, 1.75, 0.35), Look.chrome)
		K:plate("KioskKeySlot", 0.5, 0.5, 0.04, pcf * CF(0, 1.2, 0.35), lk(C(60, 56, 60)))
		txt(K, "KioskKeyText", 0.5, 0.18, pcf * CF(0, 0.85, 0.36), "KEY OUT", C(200, 196, 200), nil, { font = F.GothamBold })
		txt(K, "KioskTop", 1.5, 0.3, pcf * CF(0, 4.95, 0.36), "SELF CHECK-IN", accent, nil, { font = F.GothamBlack, glow = 1.3 })
	end)
	-- 무드 LED 띠 (천장 둘레)
	step(K, "mood", function()
		for _, wn in { "left", "right" } do
			local wall = V.walls[wn]
			local a = V:wall(wn, wall.a + 0.4, V.H - 0.35, 0.12).Position
			local b = V:wall(wn, wall.b - 0.4, V.H - 0.35, 0.12).Position
			K:free(function()
				K:plate("MoodCove", wall.b - wall.a - 0.6, 0.12, 0.35, V:wall(wn, (wall.a + wall.b) / 2, V.H - 0.22, 0.0), lk(C(36, 30, 38)))
				local s = K:bar("MoodLED", a, b, 0.07, 0.05, Look.neon(accent))
				if s then
					table.insert(leds, s)
					if wn == "left" then
						K:light(s, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 9, Brightness = 0.5, Angle = 130, Color = accent })
					end
				end
			end)
		end
	end)
	-- 거울 · 조화 · 우산 비닐 · 그림
	step(K, "decor", function()
		local wn, d = wallItemSpot(K, { "left", "right", "back" }, 1.6, 1.0, 6.4, -V.D / 2 + 2)
		if wn and d then
			K:plate("MirrorFrame", 1.6, 5.2, 0.08, d * CF(0, 0.5, 0), gold)
			K:plate("Mirror", 1.44, 5.04, 0.03, d * CF(0, 0.5, 0.08), Look.mirror)
		end
		plantAt(K, pcfAt(V3(V.x1 - 1.0, 0, V.z0 + 1.0), V3(0, 0, 1)), "snake", 3.4, 1.0, lk(C(30, 28, 30), M.Concrete))
		plantAt(K, pcfAt(V3(V.x0 + 1.0, 0, V.z0 + 1.0), V3(0, 0, 1)), "bamboo", 4.6, 1.0, lk(C(30, 28, 30), M.Concrete))
		local d0 = V.door
		if d0 then
			local pcf = floorSpot(K, { V3(V.x0 + 0.8, 0, V.z1 - 4.0), V3(V.x1 - 0.8, 0, V.z1 - 4.0), V3(V.x0 + 0.8, 0, V.z1 - 5.5) }, V3(1.4, 3.0, 1.0), V3(1, 0, 0), 0.0, "umbrella")
			if pcf then
				umbrellaBagger(K, pcf)
			end
		end
		local wn2, d2 = wallItemSpot(K, { "back", "left", "right" }, 1.8, 4.4, 6.8, 2)
		if wn2 and d2 then
			artBlocks(K, d2, 1.8, 2.2, rng, { C(220, 60, 120), C(40, 30, 60), C(240, 200, 160), C(90, 40, 80) }, gold)
		end
		local wn3, d3 = wallItemSpot(K, { "left", "right" }, 1.4, 4.0, 5.8, V.D / 2 - 3)
		if wn3 and d3 then
			paper(K, d3, 1.2, 1.6, "안내", "· 미성년자 출입 금지\n  (청소년보호법)\n· 객실 내 금연\n· 퇴실 시 키 반납\n· 주차: 건물 뒤편", { band = C(60, 20, 40), pin = false })
		end
	end)
	step(K, "elevator", function()
		elevatorHall(K, V, nil, "motel")
	end)
	step(K, "fixtures", function()
		Common.fixtures(K, V, S)
	end)
	step(K, "interact", function()
		if kioskScreen and kioskLab then
			local screens = {
				"무인 체크인\n\n대실  30,000\n숙박  60,000\n\n화면을 눌러 주세요",
				"객실 선택\n\n스탠다드  203 · 305\n스파 객실  402\n파티룸  406",
				"결제 수단\n\n신용카드 · 삼성페이\n카카오페이\n\n※ 현금은 프런트",
				"KOREAN · ENGLISH\n中文 · 日本語\n\n언어를 선택하세요",
			}
			Interact.cycle(K, kioskScreen, screens, { action = "화면 넘기기", object = "무인 키오스크", on = function(_i, s)
				if kioskLab and kioskLab.Parent then
					kioskLab.Text = s
				end
			end })
		end
		if #leds > 0 then
			local cols = { C(220, 60, 120), C(140, 80, 255), C(60, 160, 255), C(255, 170, 90) }
			local target = leds[#leds]
			Interact.cycle(K, target, cols, { action = "무드 조명 바꾸기", object = "로비 무드등", on = function(_i, c)
				for _, p in leds do
					if p.Parent then
						p.Color = c
					end
				end
				for _, l in K.lights do
					if l.Parent and l.Parent.Name == "MoodLED" then
						l.Color = c
					end
				end
			end })
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- 9. 진입
---------------------------------------------------------------------------------------------------

function T.build(K: any, V: any, S: any)
	local t = V.type
	if t == "lobby" then
		if isMotel(V) then
			buildMotel(K, V, S)
		else
			buildHotel(K, V, S)
		end
	else
		Common.fixtures(K, V, S)
	end
end

return T
