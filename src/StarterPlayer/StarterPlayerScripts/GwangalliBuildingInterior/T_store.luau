--!strict
-- GwangalliBuildingInterior/T_store: 유형 (cvs retail pharmacy) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (진열 상품 · 냉장고 · 담배장 · 계산대 · 간판 · POP · 소품 · 상호작용)
--
-- 세부 유형 (V.name / V.menu / 내용물로 판단):
--   cvs      : gs25 · cu · seven (7-ELEVEn) · emart24 · indie (동네 슈퍼 · 스낵 편의점) — 브랜드 색 · PB · 커피 · 택배 문구
--   retail   : cosmetics (올리브영 · 화장품) · souvenir (기념품 · I AM BUSAN) · beach (비치용품 · 튜브대여 · 돗자리)
--              · flower (꽃집) · book (서점) · generic
--   pharmacy : street (거리 약국) · gw (GwShop 바다약국: 바닥 소품은 거의 안 늘리고 진열 · 벽 · 천장만)
-- 맵 진열대(Gondola · WallBay · 약장 · Fridge)는 게임플레이 파트라 그대로 두고, 그 위의 엉성한 Product/Bottle/Goods/Shirt/Float
-- 상자만 숨긴 뒤 같은 선반 위에 실제 크기 상품(봉지과자 · 컵라면 · 페트 · 캔 · 우유 · 화장품 · 약 상자 ...)을 다시 진열합니다.
-- 새 바닥 소품은 전부 canPlace (= K:spot 과 같은 검사, 예약은 성공 후) 로 자리 확인, 벽 소품은 K.wallUsed 로 서로 피함.
-- Common.fixtures (스위치 · 콘센트 · 시계 · 사업자등록증) 는 S.skip 으로 미뤘다가 큰 진열장을 놓은 뒤 · 포스터 전에 불러 서로 피하게 함.
-- 프롬프트가 있는 소품(사이니지 · 택배 접수기 · 혈압계 · 거울 조명 · 회전 진열대 · 광안대교 모형 · 선풍기)은 서버 앵커 6.5 밖
-- (ShopLife 의 진열대 '고르기' 앵커 추정치 포함) 에서만 자리를 잡고, 그 자리를 다른 것보다 먼저 차지함.

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))

local TweenService = game:GetService("TweenService")

local T = {}
T.types = { "cvs", "retail", "pharmacy" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local C = Color3.fromRGB
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

-- 결정적 난수 (매장 · 선반마다 같은 결과)
local function mkRng(seed: any): () -> number
	local s = (if type(seed) == "number" then math.floor(seed) else hashStr(tostring(seed))) % 2147483646 + 1
	return function(): number
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

local function pick(rng: () -> number, list: { any }): any
	return list[math.floor(rng() * #list) + 1]
end

-- 목록 섞기 (매장마다 다른 순서 · 다른 조합)
local function shuffled(rng: () -> number, list: { any }): { any }
	local t = table.clone(list)
	for i = #t, 2, -1 do
		local j = math.floor(rng() * i) + 1
		t[i], t[j] = t[j], t[i]
	end
	return t
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

-- keep 검사 생략 표시 (기존 표면에 붙는 마감 · 같은 범위 덧씌우기)
local function L_FREE(l: any): any
	local t = table.clone(l)
	t.free = true
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

local function note(K: any, s: string)
	K:note("store: " .. s)
end

-- 긴 자리 찾기 반복 중 프레임 양보 (Kit 의 시간 분할과 같은 기준)
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

local function txt(K: any, name: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3?, bg: Color3?, o: any?): (BasePart, TextLabel)
	local opts: any = o and table.clone(o) or {}
	opts.fg = fg or INK
	opts.bg = bg
	return K:text(name, w, h, dcf, s, opts)
end

-- 물놀이 튜브 (원환): 원통 조각 + 이음 공 (각진 다각형 대신 둥근 도넛) + 공기 마개
local function tubeRing(K: any, name: string, frame: CFrame, R: number, d: number, n: number, look: any, hi: boolean)
	K:ring(name, frame, R, d, n, look)
	if hi then
		for i = 0, n - 1 do
			local t = 2 * PI * i / n
			K:ball(name .. "Joint", d * 0.98, frame * CF(math.cos(t) * R, math.sin(t) * R, 0), look)
		end
		K:vcyl(name .. "Valve", 0.08, 0.1, frame * CF(R * 0.7, R * 0.7, d * 0.46) * ANG(PI / 2, 0, 0), lk(C(250, 250, 250), M.Plastic))
	end
end

---------------------------------------------------------------------------------------------------
-- 1. 자리 확인 · 벽 사용 기록
---------------------------------------------------------------------------------------------------

local STRUCT: { [string]: boolean } = {}
for k in Scan.SHELL do
	STRUCT[k] = true
end
for _, k in { "TBar", "Troffer", "BrandStripe", "GreenBand", "LightPanel", "LightFrame", "Downlight", "TrackRail", "TrackHead", "TrackLens", "CassetteAC", "ACVanes", "ACGrille" } do
	STRUCT[k] = true
end

-- 맵 파트(간판 Sign_ 포함, 벽 · 바닥 · 천장 같은 구조체 제외)와 겹치나?
local function mapBlocked(K: any, mn: Vector3, mx: Vector3): boolean
	for _, r in K.V.parts do
		local nm = r.name
		local isSign = string.sub(nm, 1, 5) == "Sign_"
		if (isSign or not STRUCT[nm]) and r.part.Transparency < 0.99 then
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

-- K:spot 과 같은 검사 (keep · 기존 가구 · 예약), 예약은 안 함. 성공하면 AABB
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
		if K.overlap(mn, mx, s.min, s.max, 0.04) then
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

-- 벽에 붙여 세우는 바닥 소품 자리 찾기 (폭 w, 깊이 d, 높이 h). prefer = 가까울수록 좋은 로컬 점
local function wallFloorSpot(K: any, walls: { string }, w: number, d: number, h: number, prefer: Vector3?, pad: number?, kind: string?, accept: ((CFrame) -> boolean)?): (string?, CFrame?, number?)
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
				u += 0.4
			end
		end
	end
	table.sort(cands, function(a, b)
		return a.sc < b.sc
	end)
	for _, c in cands do
		yieldy(K)
		if not wallBusy(K, c.wn, c.u - w / 2 - 0.1, c.u + w / 2 + 0.1, 0, h) and (not accept or accept(c.pcf)) then
			local mn, mx = canPlace(K, c.pcf, V3(w, h, d), pad)
			if mn and mx then
				K:reserve(mn, mx, kind or "store")
				addWallUsed(K, c.wn, c.u - w / 2 - 0.15, c.u + w / 2 + 0.15, 0, h + 0.3)
				return c.wn, c.pcf, c.u
			end
		end
	end
	return nil, nil, nil
end

-- 벽 부착물 자리 (Common.wallSpot + 맵 간판 · 액자와 안 겹치게 다시 찾기). accept(dcf, wn) 가 false 면 다른 자리 (그 자리는 비워 둠)
-- Common.wallSpot 은 사용 구간을 앞에서부터 빼므로 a 순으로 정렬해 두어야 겹침이 안 생김
local function sortWallUsed(K: any)
	if K.wallUsed then
		table.sort(K.wallUsed, function(x, y)
			return x.a < y.a
		end)
	end
end

local function wallItemSpot(K: any, walls: { string }, w: number, y0: number, y1: number, prefer: number?, accept: ((CFrame, string) -> boolean)?): (string?, CFrame?)
	local temp = {}
	local rw, rd = nil, nil
	for _ = 1, 12 do
		sortWallUsed(K)
		local wn, dcf = Common.wallSpot(K, walls, w, y0, y1, prefer)
		if not wn or not dcf then
			break
		end
		local mn, mx = K.laabb(dcf * CF(0, 0, 0.2), V3(w, y1 - y0, 0.4))
		if mapBlocked(K, mn, mx) or K:hitsKeep(mn, mx) then
			continue
		end
		if accept and not accept(dcf, wn) then
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

-- ShopLife 가 실제 게임에서 더 만드는 '고르기' 앵커 자리 (진열대 모델 중심 · 냉동고 · 스티머 · 소매 진열 파트)를
-- Interact 의 호스트 점 목록에 미리 더해 둠 → 오프라인 미리보기에서도 게임과 같은 자리에서만 프롬프트가 생김
local function addHostEstimates(K: any, V: any, kind: string)
	if not K.hostPts then
		K.hostPts = Interact.hostPoints(V)
	end
	local pts = K.hostPts
	local function add(p: Vector3)
		table.insert(pts, V.cf:PointToObjectSpace(p))
	end
	local ok = pcall(function()
		if kind == "cvs" then
			for _, m in V.model:GetDescendants() do
				if m:IsA("Model") and (m.Name == "Gondola" or string.match(m.Name, "^Gondola_%d+$") or m.Name == "Fridge" or m.Name == "OpenChiller") then
					local cf = m:GetBoundingBox()
					add(cf.Position)
				end
			end
		end
	end)
	if not ok then
		note(K, "host estimate failed")
	end
	for _, nm in { "IceCreamChest", "SteamerCase", "HotBar" } do
		local r = V:first(nm)
		if r then
			table.insert(pts, r.c)
		end
	end
	if kind == "retail" then
		local n = 0
		for _, nm in { "WallRack", "DisplayTable", "Rack", "WallBay", "Hanger", "Gondola", "WallShelf", "Shelf", "Product" } do
			for i, r in V.byName[nm] or {} do
				if i <= 3 and n < 5 then
					table.insert(pts, r.c)
					n += 1
				end
			end
		end
	end
end

-- 벽 부착물 앞 (depth 만큼) 에 우리 바닥 소품이 서 있지 않은가 (모형 · 화면이 가려지지 않게)
local function frontClear(K: any, dcf: CFrame, w: number, h: number, depth: number): boolean
	local mn, mx = K.laabb(dcf * CF(0, 0, depth / 2 + 0.1), V3(w, h, depth))
	for _, r in K.reserved do
		if r.kind ~= "front" and K.overlap(mn, mx, r.min, r.max, 0.02) then
			return false
		end
	end
	return true
end

-- 프롬프트를 둘 수 있는 자리인가 (맵 서버 앵커 6.5 밖, 다른 프롬프트 2.5 밖)
local function promptOk(K: any, lp: Vector3): boolean
	return Interact.canPrompt(K, lp)
end

local function firstOk(K: any, parts: { BasePart }): BasePart?
	for _, p in parts do
		if p and p.Parent and promptOk(K, K.V.cf:PointToObjectSpace(p.Position)) then
			return p
		end
	end
	return nil
end

-- 후보 파트 중 프롬프트를 둘 수 있는 첫 파트에
local function promptOn(K: any, parts: { BasePart }, spec: any): ProximityPrompt?
	for _, p in parts do
		if p and p.Parent then
			local lp = K.V.cf:PointToObjectSpace(p.Position)
			if promptOk(K, lp) then
				return Interact.prompt(K, p, spec)
			end
		end
	end
	note(K, "no prompt spot: " .. tostring(spec.object))
	return nil
end

-- 바닥 아무 데나 (격자 탐색): 중심 후보 cands 중 첫 성공
local function floorSpot(K: any, cands: { Vector3 }, size: Vector3, face: Vector3, pad: number?, kind: string?, accept: ((Vector3) -> boolean)?): CFrame?
	for _, p in cands do
		yieldy(K)
		if accept and not accept(p) then
			continue
		end
		local pcf = pcfAt(V3(p.X, 0, p.Z), face)
		local mn, mx = canPlace(K, pcf, size, pad)
		if mn and mx then
			K:reserve(mn, mx, kind or "store")
			return pcf
		end
	end
	return nil
end

-- 손님이 서는 앞 공간 예약 (새 소품이 막지 않게): 계산대 · 전자레인지 · ATM · 냉장고 문 · 진열대 통로
local function reserveFront(K: any, mn: Vector3, mx: Vector3, dir: Vector3, depth: number, side: number?)
	local s = side or 0.3
	local a, b
	if math.abs(dir.X) > math.abs(dir.Z) then
		local x = if dir.X > 0 then mx.X else mn.X
		a = V3(math.min(x, x + dir.X * depth), 0.1, mn.Z - s)
		b = V3(math.max(x, x + dir.X * depth), 6.5, mx.Z + s)
	else
		local z = if dir.Z > 0 then mx.Z else mn.Z
		a = V3(mn.X - s, 0.1, math.min(z, z + dir.Z * depth))
		b = V3(mx.X + s, 6.5, math.max(z, z + dir.Z * depth))
	end
	K:reserve(a, b, "front")
end

-- 계산대 손님 쪽 (Props.counterOver 와 같은 계산)
local function counterFace(V: any, g: any): Vector3
	local mn, mx = g.min, g.max
	local alongX = (mx.X - mn.X) >= (mx.Z - mn.Z)
	if alongX then
		local cz = (mn.Z + mx.Z) / 2
		return if (V.door and V.door.z or V.z1) > cz then V3(0, 0, 1) else V3(0, 0, -1)
	else
		local cx = (mn.X + mx.X) / 2
		return if cx > 0 then V3(-1, 0, 0) else V3(1, 0, 0)
	end
end

-- 가장 가까운 벽 쪽의 반대 (방 안쪽)
local function awayFromWall(V: any, r: any): Vector3
	local dl, dr, db = r.min.X - V.x0, V.x1 - r.max.X, r.min.Z - V.z0
	if dl <= dr and dl <= db then
		return V3(1, 0, 0)
	elseif dr <= db then
		return V3(-1, 0, 0)
	end
	return V3(0, 0, 1)
end

---------------------------------------------------------------------------------------------------
-- 2. 상품 (실제 크기: 1 스터드 ≈ 33cm, 사람 키 5.2)
---------------------------------------------------------------------------------------------------

-- k = 모양, w/h/d 크기, cols = 색 후보, lab = 라벨 색 후보
local SKU: { [string]: any } = {
	-- 편의점 과자 · 라면 · 생활
	chips = { k = "bag", w = 0.62, h = 0.86, d = 0.28, cols = { C(222, 38, 38), C(250, 160, 30), C(250, 206, 48), C(36, 96, 190), C(62, 150, 72), C(120, 64, 160), C(112, 64, 40), C(236, 232, 226) } },
	snackBox = { k = "box", w = 0.5, h = 0.6, d = 0.3, stack = 2, cols = { C(196, 28, 40), C(240, 180, 30), C(48, 40, 38), C(130, 70, 40), C(236, 110, 150), C(250, 120, 40) } },
	pringles = { k = "can", w = 0.26, h = 0.82, cols = { C(200, 30, 40), C(40, 140, 60), C(30, 60, 160), C(240, 170, 30) } },
	candy = { k = "pouch", w = 0.38, h = 0.5, d = 0.14, cols = { C(240, 90, 140), C(255, 180, 40), C(120, 200, 80), C(90, 160, 240), C(255, 120, 60) } },
	choco = { k = "box", w = 0.56, h = 0.2, d = 0.34, stack = 3, cols = { C(90, 50, 30), C(196, 30, 40), C(240, 230, 210), C(40, 40, 120) } },
	cupRamen = { k = "cup", w = 0.4, h = 0.38, cols = { C(210, 30, 30), C(232, 96, 30), C(30, 30, 30), C(240, 196, 40), C(120, 70, 40), C(196, 40, 60) } },
	bowlRamen = { k = "bowl", w = 0.56, h = 0.3, cols = { C(210, 30, 30), C(30, 30, 30), C(250, 140, 30), C(60, 120, 60) } },
	ramenPack = { k = "pack", w = 1.0, h = 0.44, d = 0.62, cols = { C(200, 24, 28), C(236, 120, 30), C(30, 30, 30), C(250, 200, 40), C(40, 110, 60) } },
	rice = { k = "box", w = 0.48, h = 0.3, d = 0.42, stack = 3, cols = { C(240, 240, 236), C(250, 236, 200) }, lab = { C(200, 30, 40), C(30, 90, 170) } },
	tissue = { k = "box", w = 0.74, h = 0.34, d = 0.5, stack = 3, cols = { C(246, 246, 244), C(200, 226, 246), C(250, 220, 230) }, lab = { C(60, 140, 220), C(240, 120, 160) } },
	wetwipe = { k = "pouch", w = 0.66, h = 0.24, d = 0.42, cols = { C(250, 250, 250), C(170, 220, 250), C(190, 240, 200) } },
	shampoo = { k = "pump", w = 0.32, h = 0.88, cols = { C(250, 250, 250), C(40, 90, 160), C(240, 160, 190), C(60, 60, 64) } },
	toothbrush = { k = "card", w = 0.24, h = 0.76, d = 0.06, cols = { C(60, 150, 230), C(230, 60, 80), C(80, 190, 120), C(250, 200, 60) } },
	battery = { k = "card", w = 0.32, h = 0.48, d = 0.06, cols = { C(30, 30, 30), C(240, 160, 30), C(196, 30, 40) } },
	cable = { k = "card", w = 0.36, h = 0.62, d = 0.08, cols = { C(250, 250, 250), C(40, 40, 44) } },
	detergent = { k = "jug", w = 0.5, h = 0.9, d = 0.32, cols = { C(40, 120, 210), C(250, 120, 40), C(120, 60, 180) } },
	-- 음료 (냉장)
	pet = { k = "pet", w = 0.25, h = 0.7, cols = { C(200, 16, 30), C(30, 90, 190), C(250, 140, 20), C(60, 160, 70), C(110, 60, 30), C(240, 220, 60) } },
	water = { k = "pet", w = 0.25, h = 0.72, cols = { C(70, 160, 230), C(40, 120, 200) }, clear = true },
	water2l = { k = "pet", w = 0.38, h = 1.02, cols = { C(70, 160, 230), C(40, 120, 200) }, clear = true },
	can = { k = "can", w = 0.24, h = 0.42, cols = { C(200, 16, 30), C(30, 30, 30), C(30, 120, 200), C(240, 200, 30), C(240, 240, 240), C(60, 160, 70) } },
	tallcan = { k = "can", w = 0.26, h = 0.58, cols = { C(200, 16, 30), C(30, 60, 140), C(60, 60, 64) } },
	beer = { k = "can", w = 0.26, h = 0.58, cols = { C(26, 60, 150), C(30, 110, 60), C(200, 160, 50), C(220, 220, 220), C(150, 30, 40) } },
	soju = { k = "soju", w = 0.24, h = 0.76, cols = { C(40, 150, 70) } },
	milk = { k = "carton", w = 0.32, h = 0.66, d = 0.32, cols = { C(246, 246, 244) }, lab = { C(30, 90, 200), C(40, 150, 70), C(240, 120, 160), C(130, 80, 50) } },
	banana = { k = "banana", w = 0.3, h = 0.42, cols = { C(250, 220, 90) } },
	cupCoffee = { k = "cupc", w = 0.3, h = 0.46, cols = { C(110, 70, 40), C(240, 230, 210), C(30, 30, 30), C(200, 40, 40) } },
	yogurt = { k = "cup", w = 0.3, h = 0.28, cols = { C(246, 246, 244), C(250, 200, 220), C(250, 230, 160) } },
	-- 화장품
	toner = { k = "bottle", w = 0.26, h = 0.74, cols = { C(246, 246, 244), C(236, 226, 214), C(200, 226, 240), C(250, 220, 230), C(220, 240, 220) } },
	serum = { k = "dropper", w = 0.22, h = 0.52, cols = { C(180, 120, 60), C(240, 240, 240), C(120, 160, 200) } },
	cream = { k = "jar", w = 0.36, h = 0.26, cols = { C(246, 246, 244), C(30, 30, 30), C(240, 200, 210), C(200, 220, 250), C(196, 164, 98) } },
	sunscreen = { k = "tube", w = 0.22, h = 0.6, cols = { C(250, 250, 250), C(250, 210, 60), C(250, 140, 40), C(90, 180, 230) } },
	lotion = { k = "pump", w = 0.3, h = 0.82, cols = { C(246, 246, 244), C(220, 236, 250), C(250, 236, 220), C(200, 230, 210) } },
	lip = { k = "lip", w = 0.13, h = 0.38, cols = { C(200, 20, 50), C(230, 90, 110), C(180, 70, 60), C(240, 140, 150), C(150, 30, 60), C(220, 120, 100) } },
	cushionC = { k = "compact", w = 0.36, h = 0.12, cols = { C(250, 250, 250), C(30, 30, 30), C(240, 200, 210), C(200, 180, 150) } },
	palette = { k = "box", w = 0.5, h = 0.08, d = 0.36, stack = 3, cols = { C(30, 30, 30), C(240, 220, 210), C(250, 200, 210) } },
	mask = { k = "card", w = 0.42, h = 0.62, d = 0.05, cols = { C(90, 180, 230), C(250, 140, 170), C(120, 200, 120), C(250, 210, 80), C(180, 140, 220), C(246, 246, 244) } },
	hairBig = { k = "pump", w = 0.42, h = 1.02, cols = { C(250, 250, 250), C(30, 30, 30), C(150, 90, 50), C(60, 120, 80), C(230, 200, 150) } },
	perfume = { k = "perfume", w = 0.3, h = 0.5, cols = { C(250, 220, 230), C(220, 240, 250), C(250, 240, 210) } },
	healthB = { k = "box", w = 0.42, h = 0.56, d = 0.3, stack = 2, cols = { C(246, 246, 244), C(250, 240, 220) }, lab = { C(240, 140, 30), C(40, 150, 70), C(200, 30, 40), C(30, 90, 170) } },
	-- 약국
	med = { k = "medbox", w = 0.46, h = 0.32, d = 0.32, stack = 2, cols = { C(250, 250, 250), C(250, 250, 250), C(40, 100, 200), C(250, 210, 40), C(210, 40, 50), C(40, 150, 80), C(250, 140, 30), C(80, 170, 230) }, lab = { C(30, 90, 190), C(200, 30, 40), C(40, 150, 70), C(250, 170, 30), C(250, 250, 250), C(30, 160, 170) } },
	medTall = { k = "medbox", w = 0.34, h = 0.52, d = 0.28, stack = 1, cols = { C(250, 250, 250), C(40, 100, 200), C(250, 210, 40), C(210, 40, 50), C(120, 70, 40) }, lab = { C(30, 90, 190), C(200, 30, 40), C(40, 150, 70), C(250, 250, 250) } },
	ointment = { k = "medbox", w = 0.56, h = 0.18, d = 0.26, stack = 3, cols = { C(250, 250, 250), C(40, 150, 80), C(210, 40, 50) }, lab = { C(200, 30, 40), C(30, 120, 200), C(250, 250, 250) } },
	drinkA = { k = "amber", w = 0.17, h = 0.42, cols = { C(120, 60, 20) } },
	vitamin = { k = "jar", w = 0.36, h = 0.56, cols = { C(250, 250, 250), C(250, 200, 60), C(240, 140, 30), C(200, 40, 40) } },
	ginseng = { k = "box", w = 0.72, h = 0.46, d = 0.4, cols = { C(150, 20, 30), C(40, 30, 30) }, lab = { C(214, 180, 100) } },
	rxBox = { k = "medbox", w = 0.42, h = 0.36, d = 0.34, stack = 3, cols = { C(250, 250, 250), C(236, 240, 244) }, lab = { C(30, 90, 190), C(40, 150, 70), C(200, 30, 40) } },
	rxBottle = { k = "jar", w = 0.3, h = 0.44, cols = { C(160, 90, 30), C(250, 250, 250) } },
	-- 기념품 · 비치
	giftBox = { k = "box", gift = true, w = 0.96, h = 0.36, d = 0.66, stack = 3, cols = { C(30, 80, 160), C(200, 40, 40), C(240, 200, 60), C(250, 250, 250), C(40, 130, 120) }, lab = { C(250, 250, 250), C(214, 180, 100) } },
	mug = { k = "mug", w = 0.32, h = 0.36, cols = { C(250, 250, 250), C(30, 80, 160), C(240, 200, 60), C(200, 40, 40) } },
	globe = { k = "globe", w = 0.42, h = 0.52, cols = { C(30, 80, 160), C(250, 250, 250), C(40, 40, 44) } },
	plush = { k = "plush", w = 0.46, h = 0.56, cols = { C(250, 250, 250) } },
	towel = { k = "towel", w = 0.9, h = 0.3, d = 0.62, stack = 3, cols = { C(30, 120, 200), C(250, 120, 40), C(240, 200, 60), C(60, 180, 160), C(240, 90, 120) } },
	sunB = { k = "bottle", w = 0.28, h = 0.62, cols = { C(250, 210, 60), C(250, 140, 40), C(250, 250, 250), C(90, 180, 230) } },
	goggle = { k = "card", w = 0.46, h = 0.6, d = 0.08, cols = { C(30, 120, 200), C(250, 120, 40), C(240, 60, 120), C(60, 60, 64) } },
	flip = { k = "flip", w = 0.56, h = 0.12, d = 0.9, cols = { C(30, 120, 200), C(250, 120, 40), C(240, 60, 120), C(250, 210, 60), C(60, 180, 160) } },
	loaf = { k = "loaf", w = 0.62, h = 0.36, d = 0.42, cols = { C(196, 140, 80), C(170, 110, 60), C(214, 170, 110), C(150, 90, 50) } },
	hotteok = { k = "box", gift = true, ribbon = C(200, 40, 40), w = 0.8, h = 0.3, d = 0.52, stack = 3, cols = { C(250, 200, 60), C(200, 120, 50), C(240, 240, 236) }, lab = { C(200, 40, 40), C(120, 70, 40) } },
	tshirtFold = { k = "box", fold = true, print = true, w = 0.86, h = 0.56, d = 0.7, cols = { C(20, 40, 90), C(250, 250, 250), C(150, 154, 160), C(240, 200, 60), C(200, 40, 40), C(90, 170, 220) } },
	book = { k = "book", w = 0.16, h = 0.86, d = 0.6, cols = { C(30, 80, 160), C(200, 40, 40), C(240, 200, 60), C(40, 130, 90), C(240, 236, 226), C(60, 60, 64) } },
}

-- 범주 = 진열 칸에 쓸 상품 목록 (아래 칸 -> 위 칸 순으로 큰 것 · 무거운 것)
local CATS: { [string]: any } = {
	snack = { low = { "ramenPack", "snackBox", "chips" }, mid = { "chips", "chips", "snackBox", "pringles" }, top = { "chips", "candy", "choco" } },
	ramen = { low = { "ramenPack", "ramenPack", "rice" }, mid = { "cupRamen", "cupRamen", "bowlRamen" }, top = { "cupRamen", "bowlRamen", "rice" } },
	daily = { low = { "tissue", "detergent", "wetwipe" }, mid = { "shampoo", "toothbrush", "wetwipe", "battery" }, top = { "cable", "battery", "toothbrush" } },
	sweets = { low = { "snackBox", "choco" }, mid = { "candy", "choco", "snackBox" }, top = { "candy", "pringles" } },
	drinkRoom = { low = { "water2l", "pet" }, mid = { "pet", "can", "water" }, top = { "can", "cupCoffee" } },
	-- 냉장고 문 칸 (세로 한 칸 = 한 범주)
	dairy = { low = { "milk" }, mid = { "milk", "milk", "yogurt", "banana" }, top = { "yogurt", "banana", "cupCoffee", "milk" } },
	coffee = { low = { "pet", "cupCoffee" }, mid = { "cupCoffee", "can" }, top = { "cupCoffee", "can" } },
	soda = { low = { "pet" }, mid = { "pet", "can" }, top = { "can", "tallcan" } },
	waterF = { low = { "water2l" }, mid = { "water", "pet" }, top = { "water", "can" } },
	beer = { low = { "beer", "soju" }, mid = { "beer", "tallcan" }, top = { "soju", "beer" } },
	-- 화장품
	skincare = { low = { "lotion", "toner" }, mid = { "toner", "serum", "cream", "lotion" }, top = { "cream", "serum", "sunscreen" } },
	makeup = { low = { "cushionC", "palette", "cream" }, mid = { "lip", "cushionC", "sunscreen", "lip" }, top = { "lip", "palette", "perfume" } },
	hairbody = { low = { "hairBig" }, mid = { "hairBig", "lotion", "shampoo" }, top = { "lotion", "toner" } },
	maskcare = { low = { "healthB", "lotion" }, mid = { "mask", "mask", "sunscreen" }, top = { "mask", "cream" } },
	health = { low = { "healthB", "ginseng" }, mid = { "healthB", "vitamin" }, top = { "vitamin", "healthB" } },
	-- 약국
	otc = { low = { "medTall", "med" }, mid = { "med", "medTall", "ointment", "drinkA" }, top = { "med", "ointment" } },
	supplement = { low = { "ginseng", "healthB" }, mid = { "vitamin", "healthB" }, top = { "vitamin", "med" } },
	rx = { low = { "rxBox", "rxBottle" }, mid = { "rxBox", "rxBottle", "med" }, top = { "rxBox" } },
	dermo = { low = { "lotion" }, mid = { "cream", "toner", "sunscreen" }, top = { "cream", "serum" } },
	-- 기념품 · 비치
	gift = { low = { "giftBox" }, mid = { "mug", "globe", "plush" }, top = { "plush", "mug", "globe" } },
	beachgoods = { low = { "towel", "flip" }, mid = { "sunB", "goggle", "sunscreen" }, top = { "goggle", "sunB" } },
	books = { low = { "book" }, mid = { "book" }, top = { "book" } },
	tableGift = { low = { "tshirtFold", "giftBox", "tshirtFold", "hotteok" }, mid = { "giftBox", "mug", "globe", "plush", "hotteok" }, top = { "plush", "mug" } },
	busan = { low = { "giftBox", "hotteok" }, mid = { "loaf", "hotteok", "giftBox", "mug" }, top = { "loaf", "plush", "globe" } },
}

-- 상품 하나: base = 상품 바닥 가운데, +Z = 정면. lv = 3 (라벨 · 뚜껑까지) | 2 (모양을 결정하는 두 번째 부품까지) | 1 (한 덩어리)
-- 반환 = 만든 파트 수
local function item(K: any, base: CFrame, sku: any, col: Color3, lab: Color3?, h: number, lv: number): number
	local k, w, d = sku.k, sku.w, sku.d or sku.w
	local L = lk(col)
	local n = 1
	local two = lv >= 2
	local three = lv >= 3
	if k == "bag" then
		-- 과자 봉지: 납작한 몸통 + 위 접착 띠 (앞에서 보면 봉지, 옆은 얇게)
		K:box("StSnackBag", V3(w, h * 0.9, d * 0.62), base * CF(0, h * 0.45, 0), L)
		if two then
			K:box("StSnackSeal", V3(w * 1.03, h * 0.09, d * 0.26), base * CF(0, h * 0.93, 0), lk(darker(col, 0.12)))
			n += 1
		end
		if three then
			K:plate("StSnackLogo", w * 0.56, h * 0.28, 0.015, base * CF(0, h * 0.52, d * 0.31), lk(lab or lighter(col, 0.75)))
			n += 1
		end
	elseif k == "box" or k == "medbox" or k == "pack" then
		K:box("StGoodsBox", V3(w, h, d), base * CF(0, h / 2, 0), L)
		local sn = sku.stackN or 1
		if sku.gift and two then
			-- 선물세트: 앞 · 위를 지나는 리본 띠 + 위 가로 리본 + 앞 옆면 금박 띠 (상자 더미 전체)
			local rib = lk(sku.ribbon or C(214, 180, 100), M.SmoothPlastic)
			K:plate("StGiftRibbonV", 0.07, h, 0.012, base * CF(w * 0.3, h / 2, d / 2), rib)
			K:box("StGiftRibbonTop", V3(0.07, 0.014, d), base * CF(w * 0.3, h + 0.007, 0), rib)
			n += 2
			if three then
				K:box("StGiftRibbonTop2", V3(w, 0.014, 0.07), base * CF(0, h + 0.009, d * 0.18), rib)
				K:ell("StGiftBow", V3(0.22, 0.08, 0.16), base * CF(w * 0.3, h + 0.04, d * 0.18), rib)
				n += 2
			end
		end
		if sku.fold and two then
			-- 접어 쌓은 티셔츠 · 수건: 층마다 어두운 접힘 줄 (앞) + 맨 위 프린트
			local layers = math.max(2, math.floor(h / 0.14))
			for li = 1, math.min(layers - 1, 6) do
				K:plate("StFoldLine", w * 0.98, 0.025, 0.01, base * CF(0, h * li / layers, d / 2), lk(darker(col, 0.35)))
				n += 1
			end
			if three and sku.print then
				K:box("StFoldPrint", V3(w * 0.5, 0.012, d * 0.4), base * CF(0, h + 0.006, 0), lk(if (col.R + col.G + col.B) > 1.6 then C(20, 40, 90) else C(250, 250, 250)))
				n += 1
			end
		end
		if sn > 1 and two then
			-- 쌓인 상자 이음매 (상자 사이 어두운 줄)
			for si = 1, sn - 1 do
				local lum = col.R * 0.3 + col.G * 0.55 + col.B * 0.15
				K:plate("StStackSeam", w * 1.01, 0.04, 0.014, base * CF(0, h * si / sn, d / 2), lk(if lum < 0.35 then lighter(col, 0.45) else darker(col, 0.4)))
				n += 1
			end
			h = h / sn
			base = base * CF(0, h * (sn - 1), 0)
		end
		if k == "medbox" then
			if two then
				K:plate("StMedBand", w * 0.98, h * 0.34, 0.012, base * CF(0, h * 0.36, d / 2), lk(lab or C(30, 90, 190)))
				n += 1
			end
			if three then
				K:plate("StMedLogo", w * 0.36, h * 0.16, 0.014, base * CF(-w * 0.22, h * 0.76, d / 2), lk(darker(lab or C(30, 90, 190), 0.2)))
				n += 1
			end
		elseif k == "pack" then
			if two then
				K:plate("StPackWindow", w * 0.42, h * 0.5, 0.012, base * CF(w * 0.18, h * 0.46, d / 2), lk(C(250, 236, 200)))
				n += 1
			end
			if three then
				K:plate("StPackLogo", w * 0.3, h * 0.3, 0.014, base * CF(-w * 0.26, h * 0.56, d / 2), lk(C(250, 250, 250)))
				n += 1
			end
		elseif two then
			K:plate("StBoxLabel", w * 0.8, h * 0.36, 0.012, base * CF(0, h * 0.56, d / 2), lk(lab or lighter(col, 0.7)))
			n += 1
		end
	elseif k == "can" then
		K:vcyl("StCan", h, w, base * CF(0, h / 2, 0), lk(col, M.Metal))
		if three then
			K:vcyl("StCanTop", 0.03, w * 0.86, base * CF(0, h + 0.012, 0), Look.alu)
			n += 1
		end
	elseif k == "pet" then
		local body = if sku.clear then { c = lighter(col, 0.55), m = M.Glass, t = 0.35, r = 0.1 } else lk(col)
		K:vcyl("StPet", h * 0.8, w, base * CF(0, h * 0.4, 0), body)
		if two then
			K:vcyl("StPetCap", h * 0.14, w * 0.44, base * CF(0, h * 0.87, 0), lk(if sku.clear then C(40, 110, 200) else lighter(col, 0.6)))
			n += 1
		end
		if three then
			K:vcyl("StPetLabel", h * 0.26, w * 1.02, base * CF(0, h * 0.42, 0), lk(if sku.clear then C(40, 130, 220) else lab or lighter(col, 0.8)))
			n += 1
		end
	elseif k == "cup" or k == "bowl" or k == "cupc" then
		K:vcyl("StCup", h, w, base * CF(0, h / 2, 0), L)
		if two then
			K:vcyl("StCupLid", 0.03, w * 1.04, base * CF(0, h + 0.012, 0), lk(if k == "cupc" then C(250, 250, 250) else C(214, 216, 220), M.Metal))
			n += 1
		end
	elseif k == "pouch" then
		-- 스탠드 파우치 (젤리 · 물티슈): 납작한 몸통 + 윗 접착 띠 + 앞 창 (풍선처럼 둥근 공 대신)
		K:box("StPouch", V3(w, h * 0.88, d), base * CF(0, h * 0.44, 0), L)
		if two then
			K:box("StPouchSeal", V3(w * 0.96, h * 0.1, d * 0.4), base * CF(0, h * 0.93, 0), lk(darker(col, 0.15)))
			n += 1
		end
		if three then
			K:plate("StPouchWindow", w * 0.5, h * 0.3, 0.012, base * CF(0, h * 0.42, d / 2), lk(lighter(col, 0.6)))
			n += 1
		end
	elseif k == "pump" or k == "bottle" or k == "jug" then
		local bh = h * 0.76
		if k == "jug" then
			K:box("StJug", V3(w, bh, d), base * CF(0, bh / 2, 0), L)
		else
			K:vcyl("StBottle", bh, w, base * CF(0, bh / 2, 0), L)
		end
		if two then
			K:vcyl("StBottleCap", h * 0.14, w * 0.42, base * CF(0, bh + h * 0.07, 0), lk(if k == "bottle" then darker(col, 0.35) else C(240, 240, 240)))
			n += 1
		end
		if three and k == "pump" then
			K:box("StPumpHead", V3(w * 0.26, h * 0.06, w * 0.5), base * CF(0, h * 0.94, w * 0.18), lk(C(240, 240, 240)))
			n += 1
		end
		if three and lab then
			K:plate("StBottleLabel", w * 0.7, bh * 0.4, 0.01, base * CF(0, bh * 0.5, (if k == "jug" then d else w) / 2), lk(lab))
			n += 1
		end
	elseif k == "tube" then
		K:box("StTube", V3(w, h * 0.84, w * 0.56), base * CF(0, h * 0.16 + h * 0.42, 0), L)
		if two then
			K:vcyl("StTubeCap", h * 0.16, w * 0.8, base * CF(0, h * 0.08, 0), lk(darker(col, 0.25)))
			n += 1
		end
	elseif k == "jar" then
		K:vcyl("StJar", h * 0.72, w, base * CF(0, h * 0.36, 0), L)
		if two then
			K:vcyl("StJarLid", h * 0.28, w * 1.02, base * CF(0, h * 0.86, 0), lk(if lab then lab else darker(col, 0.3), if lab then M.SmoothPlastic else M.Metal))
			n += 1
		end
	elseif k == "dropper" then
		K:vcyl("StDropper", h * 0.62, w, base * CF(0, h * 0.31, 0), { c = col, m = M.Glass, t = 0.2, r = 0.1 })
		if two then
			K:vcyl("StDropperCap", h * 0.38, w * 0.42, base * CF(0, h * 0.81, 0), lk(C(30, 30, 30)))
			n += 1
		end
	elseif k == "lip" then
		K:vcyl("StLip", h * 0.62, w, base * CF(0, h * 0.31, 0), lk(C(30, 30, 32), M.Metal))
		if two then
			K:vcyl("StLipColor", h * 0.36, w * 0.7, base * CF(0, h * 0.8, 0), L)
			n += 1
		end
	elseif k == "compact" then
		K:vcyl("StCompact", h, w, base * CF(0, h / 2, 0), L)
	elseif k == "perfume" then
		K:box("StPerfume", V3(w, h * 0.64, w * 0.6), base * CF(0, h * 0.32, 0), { c = col, m = M.Glass, t = 0.25, r = 0.15 })
		if two then
			K:vcyl("StPerfumeCap", h * 0.3, w * 0.5, base * CF(0, h * 0.8, 0), Look.goldMetal)
			n += 1
		end
	elseif k == "card" then
		K:box("StCard", V3(w, h, d), base * CF(0, h / 2, 0), L)
		if three then
			K:plate("StCardBlister", w * 0.7, h * 0.5, 0.03, base * CF(0, h * 0.42, d / 2), { c = C(230, 236, 240), m = M.Glass, t = 0.4 })
			n += 1
		end
	elseif k == "amber" then
		K:vcyl("StAmber", h * 0.78, w, base * CF(0, h * 0.39, 0), { c = col, m = M.Glass, t = 0.15 })
		if two then
			K:vcyl("StAmberCap", h * 0.14, w * 0.62, base * CF(0, h * 0.85, 0), Look.goldMetal)
			n += 1
		end
		if three then
			K:vcyl("StAmberLabel", h * 0.3, w * 1.02, base * CF(0, h * 0.4, 0), lk(C(250, 210, 40)))
			n += 1
		end
	elseif k == "soju" then
		K:vcyl("StSoju", h * 0.66, w, base * CF(0, h * 0.33, 0), { c = col, m = M.Glass, t = 0.2 })
		if two then
			K:vcyl("StSojuNeck", h * 0.3, w * 0.42, base * CF(0, h * 0.8, 0), { c = col, m = M.Glass, t = 0.2 })
			n += 1
		end
		if three then
			K:vcyl("StSojuLabel", h * 0.22, w * 1.02, base * CF(0, h * 0.34, 0), lk(C(250, 250, 250)))
			n += 1
		end
	elseif k == "carton" then
		K:box("StCarton", V3(w, h * 0.84, d), base * CF(0, h * 0.42, 0), L)
		if two then
			K:box("StCartonFin", V3(w, h * 0.14, 0.06), base * CF(0, h * 0.91, 0), L)
			n += 1
		end
		if three or two then
			K:plate("StCartonLabel", w * 0.9, h * 0.34, 0.012, base * CF(0, h * 0.4, d / 2), lk(lab or C(30, 90, 200)))
			n += 1
		end
	elseif k == "banana" then
		K:ell("StBanana", V3(w, h * 0.86, w), base * CF(0, h * 0.43, 0), lk(col))
		if two then
			K:vcyl("StBananaLid", 0.05, w * 0.5, base * CF(0, h * 0.86, 0), lk(C(250, 240, 220)))
			n += 1
		end
	elseif k == "mug" then
		K:vcyl("StMug", h, w, base * CF(0, h / 2, 0), L)
		if two then
			K:box("StMugHandle", V3(0.06, h * 0.6, 0.12), base * CF(w / 2 + 0.03, h * 0.5, 0), L)
			n += 1
		end
		if three then
			K:plate("StMugPrint", w * 0.5, h * 0.4, 0.01, base * CF(0, h * 0.5, w / 2 - 0.005), lk(C(30, 80, 160)))
			n += 1
		end
	elseif k == "globe" then
		K:vcyl("StGlobeBase", h * 0.3, w * 0.86, base * CF(0, h * 0.15, 0), lk(col))
		K:ball("StGlobeGlass", w * 0.82, base * CF(0, h * 0.3 + w * 0.4, 0), { c = C(220, 236, 246), m = M.Glass, t = 0.55, r = 0.2 })
		n += 1
		if three then
			K:box("StGlobeBridge", V3(w * 0.6, 0.06, 0.06), base * CF(0, h * 0.3 + w * 0.36, 0), lk(C(220, 60, 60)))
			n += 1
		end
	elseif k == "plush" then
		-- 부산 갈매기 인형 (흰 몸통 + 머리 + 노란 부리 + 회색 날개)
		K:ell("StGullBody", V3(w, h * 0.62, w * 0.8), base * CF(0, h * 0.31, 0), lk(C(250, 250, 250), M.Fabric))
		K:ball("StGullHead", w * 0.56, base * CF(0, h * 0.72, w * 0.05), lk(C(250, 250, 250), M.Fabric))
		K:ell("StGullBeak", V3(w * 0.18, w * 0.12, w * 0.3), base * CF(0, h * 0.7, w * 0.34), lk(C(250, 190, 40)))
		n += 2
		if three then
			K:ell("StGullWing", V3(w * 1.12, h * 0.24, w * 0.5), base * CF(0, h * 0.4, -w * 0.1), lk(C(170, 180, 190), M.Fabric))
			n += 1
		end
	elseif k == "towel" then
		K:box("StTowel", V3(w, h, d), base * CF(0, h / 2, 0), lk(col, M.Fabric))
		if two then
			K:plate("StTowelStripe", w, h * 0.3, 0.01, base * CF(0, h * 0.5, d / 2), lk(C(250, 250, 250), M.Fabric))
			n += 1
		end
	elseif k == "flip" then
		for _, sx in { -1, 1 } do
			K:ell("StFlipFlop", V3(w * 0.44, h * 0.6, d), base * CF(sx * w * 0.24, h * 0.3, 0), lk(col, M.Rubber))
		end
		n += 1
	elseif k == "loaf" then
		K:ell("StLoaf", V3(w, h, d), base * CF(0, h * 0.5, 0), lk(col, M.SmoothPlastic))
		if two then
			K:box("StLoafBag", V3(w * 1.05, h * 0.6, d * 1.05), base * CF(0, h * 0.3, 0), { c = C(240, 236, 226), m = M.Glass, t = 0.6 })
			n += 1
		end
	elseif k == "book" then
		K:box("StBook", V3(w, h, d), base * CF(0, h / 2, 0), L)
	else
		K:box("StGoods", V3(w, h, d), base * CF(0, h / 2, 0), L)
	end
	return n
end

---------------------------------------------------------------------------------------------------
-- 3. 진열 칸 (맵 선반 찾기 + 상품 채우기 + 가격표)
---------------------------------------------------------------------------------------------------

local FAMILY: { [string]: boolean } = {
	Board = true, Upright = true, PriceRail = true, BackPanel = true, Product = true, Bottle = true, EndPanel = true, EndHeader = true,
	Header = true, WireShelf = true, Body = true, Kick = true, SidePanel = true, FridgeGlow = true, FridgeDoor = true, FridgeLamp = true,
	DoorMullion = true, DoorHandle = true, Goods = true, PosterFrame = true,
}

-- 진열 칸 s: { cf (앞 모서리 가운데, 윗면, +Z = 손님 쪽, +X = 칸 방향), len, depth, clear (위로 빈 높이), rail (가격 레일 있음),
--   key (진열대 면 이름: 같은 면의 칸끼리 같은 범주), level (아래부터 1..), along (면 위 칸 가운데 좌표) }
local function surfFrom(r: any, front: number, alongX: boolean, clear: number, rail: any?): any
	local top = r.max.Y
	if alongX then
		local z = if front > 0 then r.max.Z else r.min.Z
		return { cf = CFrame.fromMatrix(V3(r.c.X, top, z), V3(front, 0, 0), Vector3.yAxis, V3(0, 0, front)), len = r.size.X, depth = r.size.Z, clear = clear, rail = rail, rec = r, key = string.format("x%d:%d", front, math.floor(z * 2 + 0.5)), along = r.c.X }
	end
	local x = if front > 0 then r.max.X else r.min.X
	return { cf = CFrame.fromMatrix(V3(x, top, r.c.Z), V3(0, 0, -front), Vector3.yAxis, V3(front, 0, 0)), len = r.size.Z, depth = r.size.X, clear = clear, rail = rail, rec = r, key = string.format("z%d:%d", front, math.floor(x * 2 + 0.5)), along = r.c.Z }
end

local function overlapXZ(a: any, b: any, pad: number): boolean
	return a.min.X < b.max.X + pad and a.max.X > b.min.X - pad and a.min.Z < b.max.Z + pad and a.max.Z > b.min.Z - pad
end

-- 맵의 선반 판(Board) · 냉장고 와이어 선반(WireShelf) -> 진열 칸 목록
local function mapSurfaces(V: any): { any }
	local out = {}
	local boards: { any } = {}
	for _, nm in { "Board", "WireShelf", "BreadShelf" } do
		for _, r in V.byName[nm] or {} do
			if math.min(r.size.X, r.size.Z) >= 0.5 and math.max(r.size.X, r.size.Z) >= 1.0 and r.size.Y < 0.4 then
				table.insert(boards, r)
			end
		end
	end
	-- 냉장고 바닥 (Kick 윗면 = 와이어 선반 아래 첫 칸)
	local fridgeFloors = {}
	for _, ws in V.byName.WireShelf or {} do
		for _, kk in V.byName.Kick or {} do
			if overlapXZ(ws, kk, 0.1) and kk.max.Y < ws.min.Y then
				local key = string.format("%d:%d", math.floor(kk.c.X), math.floor(kk.c.Z))
				if not fridgeFloors[key] then
					fridgeFloors[key] = true
					-- 와이어 선반과 같은 XZ, 높이만 Kick 윗면
					table.insert(boards, { name = "FridgeFloor", min = V3(ws.min.X, kk.max.Y - 0.05, ws.min.Z), max = V3(ws.max.X, kk.max.Y, ws.max.Z), c = V3(ws.c.X, kk.max.Y - 0.025, ws.c.Z), size = V3(ws.size.X, 0.05, ws.size.Z), fridge = true })
				end
			end
		end
	end
	for _, r in boards do
		local alongX = r.size.X >= r.size.Z
		local depth = if alongX then r.size.Z else r.size.X
		-- 앞쪽: 가격 레일 > 냉장고 문 > 방 안쪽
		local front: number? = nil
		local rail: any = nil
		for _, pr in V.byName.PriceRail or {} do
			if pr.max.Y > r.min.Y - 0.4 and pr.min.Y < r.max.Y + 0.4 then
				if alongX then
					local ov = math.min(pr.max.X, r.max.X) - math.max(pr.min.X, r.min.X)
					local dz = pr.c.Z - r.c.Z
					if ov > 0.5 and math.abs(dz) > depth * 0.3 and math.abs(dz) < depth / 2 + 0.3 then
						front, rail = (if dz > 0 then 1 else -1), pr
					end
				else
					local ov = math.min(pr.max.Z, r.max.Z) - math.max(pr.min.Z, r.min.Z)
					local dx = pr.c.X - r.c.X
					if ov > 0.5 and math.abs(dx) > depth * 0.3 and math.abs(dx) < depth / 2 + 0.3 then
						front, rail = (if dx > 0 then 1 else -1), pr
					end
				end
			end
		end
		local isFridge = r.name == "WireShelf" or r.fridge == true
		if not front and isFridge then
			for _, fd in V.byName.FridgeDoor or {} do
				if overlapXZ(fd, r, 0.6) then
					front = if alongX then (if fd.c.Z > r.c.Z then 1 else -1) else (if fd.c.X > r.c.X then 1 else -1)
				end
			end
		end
		if not front then
			if alongX then
				front = if r.c.Z < (V.z0 + V.z1) / 2 then 1 else -1
			else
				front = if r.c.X < (V.x0 + V.x1) / 2 then 1 else -1
			end
		end
		-- 위로 빈 높이: 바로 위 판 / 천장 쪽 구조물 / 기둥 꼭대기
		local top = r.max.Y
		local clear = math.huge
		for _, q in boards do
			if q ~= r and q.min.Y > top + 0.2 and overlapXZ(q, r, -0.1) then
				clear = math.min(clear, q.min.Y - top)
			end
		end
		if clear == math.huge then
			local cap = math.huge
			local post = 0
			for _, nm in { "Header", "FridgeLamp", "Body", "EndHeader", "Upright", "SidePanel", "BackPanel" } do
				for _, q in V.byName[nm] or {} do
					if overlapXZ(q, r, 0.15) and q.max.Y > top + 0.3 then
						if (nm == "Header" or nm == "FridgeLamp" or nm == "Body") and q.min.Y > top + 0.3 then
							cap = math.min(cap, q.min.Y - top)
						else
							post = math.max(post, q.max.Y - top)
						end
					end
				end
			end
			clear = if cap < math.huge then cap else (if post > 0.3 then math.min(post, 1.5) else 1.3)
		end
		local s = surfFrom(r, front :: number, alongX, math.min(clear, 2.2), rail)
		s.fridge = isFridge
		table.insert(out, s)
	end
	-- 같은 면(key)끼리 높이 순 level
	local byKey: { [string]: { any } } = {}
	for _, s in out do
		local k = s.key .. ":" .. math.floor(s.along + 0.5)
		s.face = k
		byKey[k] = byKey[k] or {}
		table.insert(byKey[k], s)
	end
	for _, l in byKey do
		table.sort(l, function(a, b)
			return a.cf.Position.Y < b.cf.Position.Y
		end)
		for i, s in l do
			s.level = i
			s.levels = #l
		end
	end
	return out
end

-- 선반 위 상품이 피할 장애물 (계산대 등 선반 가족이 아닌 바닥 가구)
local function obstacles(V: any): { any }
	local o = {}
	for _, s in V.solid do
		if not FAMILY[s.name] then
			table.insert(o, s)
		end
	end
	for _, g in V.counters do
		table.insert(o, { min = g.min, max = g.max })
	end
	return o
end

-- 진열 칸들을 진열대(곤돌라 · 벽 베이) 단위로 묶음 -> { min, max, surfs }
local function clusters(surfs: { any }, fridge: boolean?): { any }
	local out = {}
	for _, s in surfs do
		if (s.fridge == true) == (fridge == true) and s.rec then
			local hit = nil
			for _, c in out do
				if overlapXZ(c, s.rec, 0.45) then
					hit = c
					break
				end
			end
			if hit then
				hit.min = hit.min:Min(s.rec.min)
				hit.max = hit.max:Max(s.rec.max)
				table.insert(hit.surfs, s)
			else
				table.insert(out, { min = s.rec.min, max = s.rec.max, surfs = { s } })
			end
		end
	end
	return out
end

local function hitsAny(K: any, list: { any }, mn: Vector3, mx: Vector3): boolean
	for _, b in list do
		if K.overlap(mn, mx, b.min, b.max, 0.02) then
			return true
		end
	end
	return false
end

-- 가격표 · 행사 태그 (레일 앞면). x = 칸 좌표
local function priceTag(K: any, s: any, x: number, promo: string?, theme: any, price: string?, dl: number?)
	local y = if s.railY then s.railY else -0.12
	local z = s.railOff or 0.075
	local at = s.cf * CF(x, y, z)
	K.stTagTexts = K.stTagTexts or 0
	if promo and K.stTagTexts < (theme.maxTagText or 28) then
		K.stTagTexts += 1
		local bg = if promo == "1+1" then theme.promo1 or C(230, 30, 50) elseif promo == "2+1" then theme.promo2 or C(250, 190, 0) else theme.promo3 or C(230, 30, 50)
		local fg = if promo == "2+1" then INK else WHITE
		txt(K, "StPromoTag", 0.42, 0.22, at, promo, fg, bg, { d = 0.02, font = Enum.Font.GothamBlack })
	elseif price and K.stTagTexts < (theme.maxTagText or 28) and K.detail == "high" then
		K.stTagTexts += 1
		txt(K, "StPriceTag", 0.4, 0.2, at, price, INK, C(252, 252, 248), { d = 0.02, font = Enum.Font.GothamBold })
	else
		K:plate("StPriceTag", 0.36, 0.18, 0.015, at, lk(C(252, 252, 248)))
		if K.detail ~= "low" and (dl or 3) >= 2 then
			K:plate("StPriceInk", 0.22, 0.06, 0.017, at * CF(0.03, -0.03, 0), lk(INK))
		end
	end
end

local PRICES = { "1,200", "1,500", "1,700", "1,800", "2,000", "2,200", "2,500", "2,800", "3,000", "3,500", "4,500" }

-- 칸 하나 채우기. cat = CATS 이름, rng, theme (태그 색 · 행사 비율),
-- opt { lvl (상품 디테일 3/2/1), obst, gap, back (뒤쪽 재고 덩어리), noTags, facing, scale, spread (묶음 사이 여유 배수) }
local function fillSurf(K: any, s: any, catName: string, rng: () -> number, theme: any, opt: any?): number
	local o: any = opt or {}
	local cat = CATS[catName] or CATS.snack
	local lv = s.level or 1
	local list = if lv <= 1 then cat.low elseif s.levels and lv >= s.levels then cat.top else cat.mid
	local dl = o.lvl or (if K.detail == "high" then 3 elseif K.detail == "mid" then 2 else 1)
	local a, b = -s.len / 2 + 0.1, s.len / 2 - 0.1
	local x = a
	local used = 0
	local gap = o.gap or 0.04
	local scale = o.scale or 1
	local groups = 0
	while x < b - 0.15 do
		local sku = SKU[pick(rng, list)]
		local w = sku.w * scale
		local d = math.min((sku.d or sku.w) * scale, s.depth - 0.12)
		-- 상자류는 칸 깊이만큼 (한 줄 재고가 통째로 보임) → 뒤 재고 덩어리 대신 라벨에 파트를 씀
		-- (단계 2 이상은 앞줄 실제 깊이 + 묶음 뒤 재고 덩어리: 옆에서 봐도 긴 막대 한 개가 아니라 줄지어 선 상자)
		local deep = (sku.k == "box" or sku.k == "medbox" or sku.k == "pack" or sku.k == "towel") and o.back ~= false and w <= 0.7 and (dl < 2 or s.depth - 0.16 < ((sku.d or sku.w) * scale) * 1.7)
		if deep then
			d = math.max(d, s.depth - 0.16)
		end
		local h = math.min(sku.h * scale * (0.92 + rng() * 0.12), s.clear - 0.12)
		if h < 0.12 or d < 0.04 then
			break
		end
		local col: Color3 = pick(rng, sku.cols)
		local lab: Color3? = if sku.lab then pick(rng, sku.lab) else nil
		local n = math.max(1, math.floor((o.facing or 2) + rng() * 3))
		if sku.k == "pack" or (sku.k == "box" and w > 0.8) then
			n = math.max(1, n - 1)
		end
		-- 상자류는 칸 높이만큼 2~3단 쌓기 (한 덩어리 + 이음매)
		local stackN = 1
		if sku.stack then
			stackN = math.clamp(math.floor((s.clear - 0.14) / (h + 0.015)), 1, sku.stack)
			h = h * stackN
		end
		local gx0 = x
		local placed = 0
		local sk = setmetatable({ w = w, d = d, stackN = stackN }, { __index = sku })
		for _ = 1, n do
			if x + w > b then
				break
			end
			local cx = x + w / 2
			local base = s.cf * CF(cx, 0.005, -d / 2 - 0.05)
			local mn, mx = K.laabb(base * CF(0, h / 2, 0), V3(w, h, d))
			if o.obst and hitsAny(K, o.obst, mn, mx) then
				x += w + gap
				continue
			end
			used += item(K, base, sk, col, lab, h, dl)
			placed += 1
			x += w + gap
		end
		if placed > 0 then
			groups += 1
			local gw = x - gx0 - gap
			-- 뒤쪽 재고 (같은 상품 줄이 안쪽으로 이어진 느낌)
			if dl >= 2 and o.back ~= false and not deep and s.depth - d > 0.35 then
				local bd = s.depth - d - 0.2
				local bh = h * 0.9
				local mnb, mxb = K.laabb(s.cf * CF(gx0 + gw / 2, bh / 2, -d - 0.1 - bd / 2), V3(gw, bh, bd))
				if not (o.obst and hitsAny(K, o.obst, mnb, mxb)) then
					local bl = if sku.k == "can" or sku.k == "pet" or sku.k == "soju" or sku.k == "amber" then lk(darker(col, 0.25), if sku.k == "can" then M.Metal else M.SmoothPlastic) else lk(darker(col, 0.18))
					if sku.clear then
						bl = { c = lighter(col, 0.4), m = M.Glass, t = 0.45 }
					end
					K:box("StBackStock", V3(gw, bh, bd), s.cf * CF(gx0 + gw / 2, 0.005 + bh / 2, -d - 0.1 - bd / 2), bl)
					used += 1
				end
			end
			if s.rail and not o.noTags and (dl >= 2 or groups % 2 == 1) then
				local r = rng()
				local p11, p21, ps = theme.p11 or 0.12, theme.p21 or 0.12, theme.pSale or 0
				local promo = if r < p11 then "1+1" elseif r < p11 + p21 then "2+1" elseif r < p11 + p21 + ps then (theme.saleText or "SALE") else nil
				priceTag(K, s, gx0 + gw / 2, promo, theme, if theme.prices then pick(rng, theme.prices) else pick(rng, PRICES), dl)
				used += if promo or dl >= 3 or dl < 2 then 1 else 2
			end
		end
		x += (o.groupGap or 0.08) * (o.spread or 1) + (if (o.spread or 1) > 1 then w * ((o.spread or 1) - 1) else 0)
	end
	return used
end

-- 진열 예약: 구조물(진열장 · 아일랜드)을 다 만든 뒤 runFill 이 매장 상품 예산에 맞춰 디테일 단계를 정해 채움
local function queueFill(K: any, s: any, cat: string, seed: string, theme: any, opt: any?)
	K.stQueue = K.stQueue or {}
	table.insert(K.stQueue, { s = s, cat = cat, seed = seed, theme = theme or {}, opt = opt or {} })
end

-- 스터드당 대략 파트 수 (단계 3 / 2 / 1)
local PPS = { 6.6, 4.2, 2.4 }

-- 진열 칸 하나의 예상 파트 밀도 (스터드당, 단계 lv): 상품 폭 · 라벨 단계 · 가격표 · 뒤 재고
local function estDensity(e: any, lv: number): number
	local cat = CATS[e.cat] or CATS.snack
	local s = e.s
	local l = s.level or 1
	local list = if l <= 1 then cat.low elseif s.levels and l >= s.levels then cat.top else cat.mid
	local gap = e.opt.gap or 0.04
	local scale = e.opt.scale or 1
	local items = 0
	for _, nm in list do
		items += 1 / ((SKU[nm] or SKU.chips).w * scale + gap)
	end
	items = items / math.max(1, #list) * 0.94
	local per = if lv >= 3 then 2.5 elseif lv == 2 then 1.8 else 1
	local groups = items / 3
	local tags = if not s.rail or e.opt.noTags then 0 elseif lv >= 3 then groups elseif lv == 2 then groups * 2 else groups * 0.5
	local back = if lv >= 2 and e.opt.back ~= false and s.depth > 0.8 then groups else 0
	-- 실측 보정 (빈 칸 · 장애물 · 큰 상자 깊이 채움 때문에 실제가 조금 적음)
	return (items * per + tags + back) * (if lv >= 3 then 0.82 elseif lv == 2 then 0.86 else 0.92)
end

-- 예약된 진열 칸을 예산 안에서 고르게 채움: 남은 칸을 모두 단계 1 로 채울 예산을 남겨 둔 채로, 칸마다 가능한 가장 높은 단계.
-- 단계 1 로도 모자라면 묶음 간격을 띄움 (앞 칸이 빽빽하고 뒤 칸이 텅 비는 일 없이)
local function runFill(K: any, budget: number): number
	local q = K.stQueue or {}
	K.stQueue = {}
	local maxLv = if K.detail == "high" then 3 elseif K.detail == "mid" then 2 else 1
	local remain1 = 0
	local need = { 0, 0, 0 }
	for _, e in q do
		for lv = 1, 3 do
			need[lv] += estDensity(e, math.min(lv, e.opt.maxLvl or 3)) * e.s.len
		end
	end
	remain1 = need[1]
	local used = 0
	for _, e in q do
		local cap = math.min(maxLv, e.opt.maxLvl or 3)
		local c1 = estDensity(e, 1) * e.s.len
		local rest = remain1 - c1
		local left = budget - used - rest
		local lv = 1
		for l = cap, 2, -1 do
			if estDensity(e, l) * e.s.len <= left then
				lv = l
				break
			end
		end
		local o = table.clone(e.opt)
		o.lvl = lv
		local ratio = (budget - used) / math.max(remain1, 1)
		if lv == 1 and ratio < 0.95 then
			-- 묶음(약 3개)마다 상품 하나 폭만큼 더 띄움: 밀도 = 3 / (2 + spread)
			o.spread = math.clamp(3 / math.max(ratio, 0.3) - 2, 1, 2.6)
		end
		local n = 0
		K:free(function()
			n = fillSurf(K, e.s, e.cat, mkRng(e.seed), e.theme, o)
		end)
		used += n
		remain1 = math.max(0, rest)
	end
	note(K, string.format("fill budget=%d need=%d/%d/%d used=%d", budget, need[1], need[2], need[3], used))
	K.stGoodsParts = (K.stGoodsParts or 0) + used
	return used
end

-- GwShop: 원래 Product 상자 안쪽만 (같은 범위) 작은 실제 상품 여러 개로 다시 만들기
local function fillInside(K: any, r: any, front: Vector3, catName: string, rng: () -> number, lv: number, clear: number?): number
	local alongX = math.abs(front.Z) > math.abs(front.X)
	local len = if alongX then r.size.X else r.size.Z
	local dep = if alongX then r.size.Z else r.size.X
	local h = r.size.Y
	local p = V3(r.c.X, r.min.Y, r.c.Z) + front * (dep / 2)
	local xv = Vector3.yAxis:Cross(front).Unit
	local cf = CFrame.fromMatrix(p, xv, Vector3.yAxis, front)
	local cat = CATS[catName]
	local sku = SKU[pick(rng, cat.mid)]
	local n = math.max(1, math.floor(len / math.max(0.18, sku.w) + 0.2))
	local w = len / n
	local col: Color3 = pick(rng, sku.cols)
	local lab: Color3? = if sku.lab then pick(rng, sku.lab) else nil
	local used = 0
	local hh = math.min(h, sku.h * 1.15)
	-- 상자류는 위 선반까지 여유가 있으면 2~3단으로 쌓아 (실제 약국 진열처럼) 칸이 비어 보이지 않게
	local sn = 1
	if clear and sku.stack and (sku.k == "box" or sku.k == "medbox") then
		sn = math.clamp(math.floor((clear - 0.25) / (hh + 0.02)), 1, sku.stack + 1)
	end
	-- 깊은 칸: 앞줄은 실제 상자 깊이, 뒤로는 같은 상품 재고 줄 (한 덩어리 긴 막대처럼 보이지 않게 틈 0.04)
	local fd = dep * 0.95
	local backD = 0
	if sku.d and dep > sku.d * 1.7 and lv >= 2 then
		fd = math.min(dep * 0.95, sku.d * 1.05)
		backD = dep * 0.95 - fd - 0.04
	end
	for i = 1, n do
		local base = cf * CF(-len / 2 + w * (i - 0.5), 0.005, -fd / 2 - 0.02)
		used += item(K, base, setmetatable({ w = w * 0.92, d = fd, stackN = sn }, { __index = sku }), col, lab, hh * sn, lv)
	end
	if backD > 0.08 then
		K:box("StBackStock", V3(len * 0.96, hh * sn * 0.96, backD), cf * CF(0, 0.005 + hh * sn * 0.48, -fd - 0.06 - backD / 2), lk(darker(col, 0.12)))
		used += 1
	end
	return used
end

---------------------------------------------------------------------------------------------------
-- 4. 공용 진열 · 사인 소품
---------------------------------------------------------------------------------------------------

-- 포스터 / POP (dcf 표면, 벽에서 0.06 띄움): 바탕 + 윗띠 + 제목 + 본문
local function poster(K: any, dcf: CFrame, w: number, h: number, title: string, body: string?, bg: Color3, fg: Color3, band: Color3?, bandFg: Color3?, o: any?)
	local oo: any = o or {}
	local d0 = dcf * CF(0, 0, oo.off or 0.06)
	if oo.frame ~= false then
		K:plate("StPosterFrame", w + 0.08, h + 0.08, 0.03, d0, oo.frameL or lk(C(240, 240, 238)))
	end
	K:plate("StPoster", w, h, 0.035, d0, lk(bg))
	local th = if body then h * (oo.titleH or 0.3) else h
	if band then
		K:plate("StPosterBand", w, th, 0.04, d0 * CF(0, h / 2 - th / 2, 0), lk(band))
	end
	txt(K, "StPosterTitle", w * 0.92, th * 0.82, d0 * CF(0, h / 2 - th / 2, 0.041), title, bandFg or fg, nil, { font = oo.font or Enum.Font.GothamBlack })
	if body then
		txt(K, "StPosterBody", w * 0.88, (h - th) * 0.86, d0 * CF(0, -th / 2, 0.036), body, fg, nil, { font = oo.bodyFont or Enum.Font.GothamBold })
	end
end

-- 천장에 매다는 양면 POP (와이어 2개 + 판 + 양면 글자)
local function hangSign(K: any, x: number, z: number, w: number, h: number, yBot: number, rotY: number, front: string, back: string?, bg: Color3, fg: Color3, edge: Color3?): boolean
	local V = K.V
	local cf = CF(x, yBot + h / 2, z) * ANG(0, rotY, 0)
	local mn, mx = K.laabb(cf, V3(w + 0.1, h, 0.2))
	local mnW, mxW = mn, V3(mx.X, V.H, mx.Z)
	if K:hitsKeep(mnW, mxW) then
		return false
	end
	-- 다른 매단 POP 와 1.5 이상 떨어지게
	for _, sb in K.stSignBoxes or {} do
		if K.overlap(mn - V3(1.5, 0, 1.5), mx + V3(1.5, 0, 1.5), sb.min, sb.max, 0) then
			return false
		end
	end
	-- 와이어 윗점이 에어컨 · 조명 · CCTV 위에 걸리지 않게 (T-bar 사이는 괜찮음)
	for _, sx in { -1, 1 } do
		local a = (cf * CF(sx * w * 0.38, h / 2, 0)).Position
		for _, r in V.parts do
			local nm = r.name
			if (nm == "CassetteAC" or nm == "ACVanes" or nm == "Troffer" or nm == "Downlight" or nm == "CCTV" or nm == "CCTVMount" or nm == "LightPanel" or nm == "LightFrame" or nm == "TrackRail" or nm == "ShopLight") and a.X > r.min.X - 0.25 and a.X < r.max.X + 0.25 and a.Z > r.min.Z - 0.25 and a.Z < r.max.Z + 0.25 then
				return false
			end
		end
		for _, q in K.ceilUsed or {} do
			if math.abs(q.X - a.X) < 0.5 and math.abs(q.Z - a.Z) < 0.5 then
				return false
			end
		end
	end
	for _, r in V.hang do
		if K.overlap(mn - V3(0, 0.2, 0), mx + V3(0, 0.3, 0), r.min, r.max, 0.05) then
			return false
		end
	end
	if mapBlocked(K, mn, mx) then
		return false
	end
	for _, sx in { -1, 1 } do
		local a = (cf * CF(sx * w * 0.38, h / 2, 0)).Position
		K:seg("StHangWire", a, V3(a.X, V.H - 0.02, a.Z), 0.03, Look.chrome)
	end
	K:box("StHangBoard", V3(w, h, 0.06), cf, lk(bg))
	if edge then
		K:box("StHangEdge", V3(w + 0.04, 0.1, 0.08), cf * CF(0, h / 2 - 0.05, 0), lk(edge))
		K:box("StHangEdge", V3(w + 0.04, 0.1, 0.08), cf * CF(0, -h / 2 + 0.05, 0), lk(edge))
	end
	txt(K, "StHangText", w * 0.92, h * 0.74, cf * CF(0, -0.02, 0.031), front, fg, nil, { font = Enum.Font.GothamBlack, d = 0.01, glow = 1.05 })
	txt(K, "StHangText", w * 0.92, h * 0.74, cf * CF(0, -0.02, -0.031) * ANG(0, PI, 0), back or front, fg, nil, { font = Enum.Font.GothamBlack, d = 0.01, glow = 1.05 })
	Common.useCeil(K, x, z)
	K.stSignBoxes = K.stSignBoxes or {}
	table.insert(K.stSignBoxes, { min = mn, max = V3(mx.X, V.H, mx.Z) })
	return true
end

-- 매다는 POP: 자리가 막히면 조금씩 옮겨 봄
local function hangSignNear(K: any, x: number, z: number, w: number, h: number, yBot: number, rotY: number, front: string, back: string?, bg: Color3, fg: Color3, edge: Color3?): boolean
	for _, o in { V3(0, 0, 0), V3(0.8, 0, 0), V3(-0.8, 0, 0), V3(0, 0, 0.9), V3(0, 0, -0.9), V3(1.6, 0, 0), V3(-1.6, 0, 0), V3(0, 0, 1.8), V3(0, 0, -1.8), V3(1.2, 0, 1.2), V3(-1.2, 0, -1.2), V3(0, 0, 2.8), V3(0, 0, -2.8), V3(2.4, 0, 0), V3(-2.4, 0, 0), V3(0, 0, 3.6), V3(0, 0, -3.6) } do
		if hangSign(K, x + o.X, z + o.Z, w, h, yBot, rotY, front, back, bg, fg, edge) then
			return true
		end
	end
	return false
end

-- 디지털 사이니지 (벽걸이 화면): 자동으로 넘어가고, 프롬프트로 직접 넘김. frames = { { text, c } }
local function didScreen(K: any, dcf: CFrame, w: number, frames: { any }, object: string, frameL: any?)
	local h = w * 9 / 16
	K:plate("StDIDMount", w * 0.3, h * 0.3, 0.1, dcf, Look.blackMetal)
	K:plate("StDIDBezel", w + 0.14, h + 0.14, 0.12, dcf * CF(0, 0, 0.1), frameL or Look.black)
	-- 화면 = 불투명 배경 글자판 (밝기 1.3): 화면 색 · 글자를 같이 바꿈
	local scr, label = txt(K, "StDIDScreen", w, h, dcf * CF(0, 0, 0.22), frames[1].text, WHITE, frames[1].c, { glow = 1.1, font = Enum.Font.GothamBlack, d = 0.02 })
	K:plate("StDIDLed", 0.06, 0.06, 0.01, dcf * CF(w / 2 - 0.05, -h / 2 - 0.04, 0.225), Look.ledGreen)
	local idx = 0
	local last = -1
	local function show(i: number)
		local f = frames[i]
		if label.Parent then
			label.Text = f.text
			label.BackgroundColor3 = f.c
		end
	end
	Interact.anim(K, function(t)
		local i = (math.floor(t / 6) + idx) % #frames + 1
		if i ~= last then
			last = i
			show(i)
		end
	end)
	promptOn(K, { scr }, {
		action = "화면 넘기기",
		object = object,
		fn = function()
			idx += 1
			last = -1
		end,
	})
	return scr
end

-- 벽에 붙은 진열장 (새 바닥 소품): 벽 wn 의 u 중심, 폭 len. 반환 = 진열 칸 목록
local function wallUnit(K: any, pcf: CFrame, len: number, d: number, h: number, o: any)
	local body = o.body or Look.white
	local backL = o.back or lk(C(236, 236, 232))
	local shelfL = o.shelf or lk(C(246, 246, 244))
	local railL = o.rail or lk(C(250, 250, 248))
	local n = o.levels or 5
	-- 바닥 받침 · 뒤판 · 옆판
	K:box("StUnitKick", V3(len - 0.1, 0.42, d - 0.12), pcf * CF(0, 0.21, 0.0), o.kick or Look.charcoal)
	K:box("StUnitBack", V3(len, h, 0.12), pcf * CF(0, h / 2, -d / 2 + 0.06), backL)
	if o.peg then
		-- 유공보드 느낌 (얇은 가로 줄)
		for yy = 1.2, h - 0.4, 0.9 do
			K:box("StUnitPegLine", V3(len - 0.3, 0.025, 0.02), pcf * CF(0, yy, -d / 2 + 0.13), lk(darker(backL.c, 0.08)))
		end
	end
	for _, sx in { -1, 1 } do
		K:box("StUnitSide", V3(0.12, h, d), pcf * CF(sx * (len / 2 - 0.06), h / 2, 0), body)
	end
	-- 머리 간판 (라이트 박스)
	local hd = K:box("StUnitHeader", V3(len, 0.62, 0.36), pcf * CF(0, h + 0.31, -d / 2 + 0.18), o.headL or lk(C(250, 250, 250)))
	K:plate("StUnitHeaderLine", len, 0.06, 0.37, pcf * CF(0, h + 0.03, -d / 2) * ANG(0, 0, 0), o.lineL or lk(C(30, 30, 30)))
	if o.title then
		txt(K, "StUnitTitle", len * 0.9, 0.46, pcf * CF(0, h + 0.31, -d / 2 + 0.365), o.title, o.titleFg or INK, nil, { font = Enum.Font.GothamBlack, glow = o.glow })
	end
	local surfs = {}
	local y0 = 0.42
	local top = h - 0.25
	local stepY = (top - y0) / n
	for i = 1, n do
		local y = y0 + (i - 1) * stepY
		local sd = if i == 1 then d - 0.14 else d - 0.2 - (i - 1) * 0.06
		if i > 1 then
			K:box("StUnitShelf", V3(len - 0.24, 0.07, sd), pcf * CF(0, y - 0.035, -d / 2 + 0.12 + sd / 2), shelfL)
		end
		local zf = -d / 2 + 0.12 + sd
		K:box("StUnitRail", V3(len - 0.24, 0.2, 0.04), pcf * CF(0, y - 0.07, zf + 0.02), railL)
		local cf = pcf * CF(0, y, zf)
		table.insert(surfs, { cf = CFrame.fromMatrix(cf.Position, cf.XVector, cf.YVector, cf.ZVector), len = len - 0.3, depth = sd - 0.05, clear = stepY - 0.12, rail = true, railY = -0.07, railOff = 0.045, level = i, levels = n })
	end
	if o.led ~= false then
		local strip = K:box("StUnitLED", V3(len - 0.3, 0.04, 0.06), pcf * CF(0, h - 0.06, -d / 2 + 0.4), Look.lampCool)
		if o.light then
			K:light(strip, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 7, Brightness = 0.5, Angle = 120, Color = Look.coolLight })
		end
	end
	return surfs, hd
end

-- 양면 진열대 (새 아일랜드): pcf 바닥 가운데, +X = 긴 방향. 반환 = 진열 칸
local function island(K: any, pcf: CFrame, len: number, w: number, h: number, o: any): { any }
	local body = o.body or Look.white
	local n = o.levels or 3
	K:box("StIslandKick", V3(len - 0.1, 0.4, w - 0.1), pcf * CF(0, 0.2, 0), o.kick or Look.charcoal)
	K:box("StIslandSpine", V3(len, h, 0.14), pcf * CF(0, h / 2, 0), o.spine or body)
	for _, sx in { -1, 1 } do
		K:box("StIslandEnd", V3(0.14, h, w), pcf * CF(sx * (len / 2 - 0.07), h / 2, 0), body)
	end
	if o.topL then
		K:box("StIslandTop", V3(len + 0.1, 0.08, w + 0.1), pcf * CF(0, h + 0.04, 0), o.topL)
	end
	local surfs = {}
	local y0 = 0.4
	local stepY = (h - 0.2 - y0) / n
	local sd = w / 2 - 0.12
	for _, side in { 1, -1 } do
		local face = pcf * ANG(0, if side > 0 then 0 else PI, 0)
		for i = 1, n do
			local y = y0 + (i - 1) * stepY
			if i > 1 then
				K:box("StIslandShelf", V3(len - 0.3, 0.07, sd), face * CF(0, y - 0.035, 0.07 + sd / 2), o.shelf or lk(C(246, 246, 244)))
			end
			K:box("StIslandRail", V3(len - 0.3, 0.2, 0.04), face * CF(0, y - 0.07, 0.07 + sd + 0.02), o.rail or lk(C(250, 250, 248)))
			local cf = face * CF(0, y, 0.07 + sd)
			table.insert(surfs, { cf = cf, len = len - 0.4, depth = sd - 0.04, clear = stepY - 0.1, rail = true, railY = -0.07, railOff = 0.045, level = i, levels = n, side = side })
		end
	end
	return surfs
end

-- 낮은 행사 테이블 (창가 · 입구 쪽, 높이 3.3 아래): 상판 + 계단식 아크릴 단 2개 + POP. 반환 = 진열 칸
local function promoTable(K: any, pcf: CFrame, w: number, d: number, topL: any, popTitle: string, popBody: string, popBg: Color3)
	local th = 2.3
	K:box("StPromoTop", V3(w, 0.12, d), pcf * CF(0, th - 0.06, 0), topL)
	K:box("StPromoBody", V3(w - 0.3, th - 0.4, d - 0.3), pcf * CF(0, (th - 0.4) / 2 + 0.28, 0), lk(C(236, 236, 232)))
	K:box("StPromoKick", V3(w - 0.4, 0.28, d - 0.4), pcf * CF(0, 0.14, 0), Look.charcoal)
	local surfs = {}
	-- 앞 · 뒤 (양쪽 손님) 단
	for _, side in { 1, -1 } do
		local f = pcf * ANG(0, if side > 0 then 0 else PI, 0)
		K:box("StPromoRiser", V3(w - 0.4, 0.34, d / 2 - 0.5), f * CF(0, th + 0.17, -(d / 2 - 0.5) / 2 - 0.05), { c = C(240, 244, 246), m = M.Glass, t = 0.25 })
		table.insert(surfs, { cf = f * CF(0, th, d / 2 - 0.05), len = w - 0.4, depth = 0.45, clear = 0.75, rail = false, level = 2, levels = 3 })
		table.insert(surfs, { cf = f * CF(0, th + 0.34, -0.05), len = w - 0.6, depth = d / 2 - 0.55, clear = 0.62, rail = false, level = 3, levels = 3 })
	end
	-- POP 꽂이 (가운데, 높이 3.3 아래)
	K:box("StPromoPopFoot", V3(0.5, 0.06, 0.3), pcf * CF(0, th, 0), Look.chrome)
	K:box("StPromoPopPole", V3(0.04, 0.4, 0.04), pcf * CF(0, th + 0.2, 0), Look.chrome)
	local pd = pcf * CF(0, th + 0.62, 0)
	txt(K, "StPromoPop", 1.4, 0.5, pd, popTitle, WHITE, popBg, { d = 0.02, font = Enum.Font.GothamBlack })
	txt(K, "StPromoPop", 1.4, 0.5, pd * ANG(0, PI, 0), popBody, WHITE, popBg, { d = 0.02, font = Enum.Font.GothamBold })
	return surfs
end

-- 장바구니 더미 (입구 옆)
local function basketStack(K: any, pcf: CFrame, col: Color3, n: number, label: string?)
	local bw, bd, bh = 1.3, 0.9, 0.62
	for i = 0, n - 1 do
		local y = i * 0.2
		if i == 0 then
			K:box("StBasket", V3(bw, bh, bd), pcf * CF(0, y + bh / 2, 0), lk(col, M.Plastic))
		else
			K:box("StBasketRim", V3(bw + 0.04, 0.08, bd + 0.04), pcf * CF(0, y + bh - 0.04, 0), lk(darker(col, 0.15), M.Plastic))
		end
	end
	local topY = (n - 1) * 0.2 + bh
	K:box("StBasketBody", V3(bw - 0.02, topY - bh + 0.02, bd - 0.02), pcf * CF(0, bh + (topY - bh) / 2 - 0.01, 0), lk(col, M.Plastic))
	K:box("StBasketInside", V3(bw - 0.16, 0.04, bd - 0.16), pcf * CF(0, topY - 0.06, 0), lk(darker(col, 0.45), M.Plastic))
	for _, sx in { -1, 1 } do
		K:bar("StBasketHandle", (pcf * CF(sx * 0.42, topY, 0)).Position, (pcf * CF(sx * 0.12, topY + 0.32, 0)).Position, 0.06, 0.06, lk(C(30, 30, 30), M.Plastic))
	end
	K:box("StBasketHandleTop", V3(0.3, 0.06, 0.06), pcf * CF(0, topY + 0.32, 0), lk(C(30, 30, 30), M.Plastic))
	if label then
		txt(K, "StBasketLabel", bw * 0.7, 0.24, pcf * CF(0, bh * 0.5, bd / 2 + 0.005), label, WHITE, nil, { font = Enum.Font.GothamBlack, d = 0.01 })
	end
end

-- 바닥 스탠드형 POP (A4 꽂이 기둥)
local function popStand(K: any, pcf: CFrame, title: string, body: string, bg: Color3, fg: Color3)
	K:disc("StPopBase", 1.0, 0.06, pcf * CF(0, 0.03, 0), Look.chrome)
	K:vcyl("StPopPole", 3.4, 0.08, pcf * CF(0, 1.75, 0), Look.chrome)
	local d = pcf * CF(0, 4.1, 0.06)
	K:plate("StPopFrame", 1.5, 1.9, 0.04, d, Look.chrome)
	K:plate("StPopCard", 1.4, 1.8, 0.05, d, lk(bg))
	txt(K, "StPopTitle", 1.3, 0.5, d * CF(0, 0.55, 0.051), title, fg, nil, { font = Enum.Font.GothamBlack })
	txt(K, "StPopBody", 1.3, 1.1, d * CF(0, -0.3, 0.051), body, fg, nil, { font = Enum.Font.GothamBold })
end

-- 선반 날개 POP (선반 레일에서 튀어나온 작은 깃발)
local function wobbler(K: any, s: any, x: number, text: string, bg: Color3, fg: Color3)
	local at = s.cf * CF(x, (s.railY or -0.12) - 0.02, (s.railOff or 0.075) + 0.25) * ANG(0, PI / 2, 0)
	K:box("StWobblerArm", V3(0.5, 0.03, 0.03), s.cf * CF(x, (s.railY or -0.12), (s.railOff or 0.075) + 0.25 * 0.5) * ANG(0, PI / 2, 0), Look.chrome)
	K:box("StWobbler", V3(0.04, 0.5, 0.5), at * CF(0, 0, 0), lk(bg))
	txt(K, "StWobblerText", 0.44, 0.44, at * CF(0.025, 0, 0) * ANG(0, PI / 2, 0), text, fg, nil, { font = Enum.Font.GothamBlack, d = 0.01 })
	txt(K, "StWobblerText", 0.44, 0.44, at * CF(-0.025, 0, 0) * ANG(0, -PI / 2, 0), text, fg, nil, { font = Enum.Font.GothamBlack, d = 0.01 })
end

---------------------------------------------------------------------------------------------------
-- 5. 브랜드 · 세부 유형
---------------------------------------------------------------------------------------------------

local BRANDS: { [string]: any } = {
	gs25 = { ssid = "GS25_FREE_WiFi", name = "GS25", main = C(0, 118, 206), sub = C(0, 178, 226), accent = C(122, 190, 64), dark = C(10, 40, 80), basket = C(0, 118, 206), coffee = "카페25", pb = "유어스", parcel = "GS25 반값택배 · 택배 접수", app = "우리동네GS 앱 픽업", promo1 = C(232, 30, 60), promo2 = C(250, 196, 0), slogan = "LIFESTYLE PLATFORM" },
	cu = { ssid = "CU_Free_WiFi", name = "CU", main = C(108, 44, 150), sub = C(160, 206, 60), accent = C(160, 206, 60), dark = C(48, 18, 70), basket = C(108, 44, 150), coffee = "GET 커피", pb = "PB 헤이루", parcel = "CU 알뜰택배 · 택배 접수", app = "포켓CU 앱 픽업", promo1 = C(232, 30, 60), promo2 = C(160, 206, 60), slogan = "가까운 행복 CU" },
	seven = { ssid = "7-ELEVEn_Free", name = "7-ELEVEn", main = C(0, 130, 96), sub = C(246, 132, 32), accent = C(232, 36, 52), dark = C(0, 60, 44), basket = C(0, 130, 96), coffee = "세븐카페", pb = "세븐셀렉트", parcel = "세븐일레븐 택배 접수", app = "세븐앱 픽업", promo1 = C(232, 36, 52), promo2 = C(246, 132, 32), slogan = "Always Open 24" },
	emart24 = { ssid = "emart24_WiFi", name = "emart24", main = C(255, 184, 28), sub = C(60, 60, 62), accent = C(232, 40, 50), dark = C(40, 40, 42), basket = C(255, 184, 28), coffee = "이프레소", pb = "아임e", parcel = "emart24 택배 접수", app = "emart24 앱 픽업", promo1 = C(232, 40, 50), promo2 = C(255, 184, 28), slogan = "Everyday emart24" },
	indie = { ssid = "STORE_WiFi_5G", name = "마트", main = C(214, 40, 44), sub = C(30, 70, 150), accent = C(250, 196, 0), dark = C(60, 20, 20), basket = C(214, 40, 44), coffee = "원두커피", pb = "알뜰상품", parcel = "택배 접수", app = "전화 주문 배달", promo1 = C(214, 40, 44), promo2 = C(250, 196, 0), slogan = "동네 마트" },
}

local OY = { main = C(154, 194, 27), dark = C(28, 34, 30), sub = C(230, 40, 120), white = C(250, 250, 248) }
local PH = { main = C(10, 138, 58), dark = C(10, 70, 40), sub = C(0, 150, 200), white = C(250, 252, 250) }

-- 매장 상품 파트 예산 (넓이 비례, 남은 파트 여유 안에서)
local function goodsBudget(K: any, V: any, mul: number?): number
	local cap = if V.W * V.D > 900 then 1650 else 950 -- 대형 매장 (올리브영 본점급) 은 진열이 비어 보이지 않게 조금 더
	local b = math.clamp(V.W * V.D * 1.5 * (mul or 1), 300, cap)
	local room = (K.maxParts or 2600) - #K.parts - 520
	return math.max(160, math.min(b, room))
end

local function subtype(V: any): (string, string)
	local raw = tostring(V.name or "")
	local n = string.upper(raw)
	local m = tostring(V.menu or "")
	local function has(s: string): boolean
		return string.find(n, s, 1, true) ~= nil
	end
	if V.type == "pharmacy" then
		return "pharmacy", if V.kind == "gwshop" then "gw" else "street"
	end
	if V.type == "cvs" then
		if has("GS25") or has("GS 25") then
			return "cvs", "gs25"
		elseif n == "CU" or string.sub(n, 1, 3) == "CU " or has(" CU") or has("씨유") then
			return "cvs", "cu"
		elseif has("7-ELEVEN") or has("세븐일레븐") or has("7ELEVEN") then
			return "cvs", "seven"
		elseif has("EMART24") or has("이마트24") then
			return "cvs", "emart24"
		end
		return "cvs", "indie"
	end
	if m == "cosmetics" or has("OLIVE") or has("올리브") or has("LALAVLA") or has("화장품") or V:has("Tester") > 0 then
		return "retail", "cosmetics"
	elseif m == "beach" or has("비치") or has("튜브") or has("돗자리") or has("폭죽") or has("BEACH") then
		return "retail", "beach"
	elseif m == "souvenir" or has("기념품") or has("BUSAN") or has("ORANGE") or has("SOUVENIR") then
		return "retail", "souvenir"
	elseif m == "flower" or has("꽃") or has("FLOWER") then
		return "retail", "flower"
	elseif m == "book" or has("서점") or has("책") or has("BOOK") then
		return "retail", "book"
	end
	if V:has("Float") > 0 then
		return "retail", "beach"
	elseif V:has("Shirt") > 0 or V:has("Goods") > 0 then
		return "retail", "souvenir"
	end
	return "retail", "generic"
end
T.subtype = subtype

---------------------------------------------------------------------------------------------------
-- 6. 편의점
---------------------------------------------------------------------------------------------------

-- 담배 진열장: 맵 CigCabinet/PackFace/CigHeader 와 같은 범위에 다시 (직원 자리 keep 안이라 free)
local CIG_COLS = { C(250, 250, 250), C(30, 60, 140), C(200, 30, 40), C(30, 30, 34), C(120, 170, 220), C(214, 180, 100), C(90, 60, 140), C(40, 120, 90), C(236, 236, 230), C(160, 30, 50), C(60, 140, 200), C(246, 200, 60) }

local function cigCabinet(K: any, V: any, B: any, rng: () -> number)
	local cab = V:first("CigCabinet")
	if not cab then
		return
	end
	local pf = V:first("PackFace")
	local hd = V:first("CigHeader")
	local alongX = cab.size.X >= cab.size.Z
	local face: Vector3
	if pf then
		face = if alongX then V3(0, 0, if pf.c.Z > cab.c.Z then 1 else -1) else V3(if pf.c.X > cab.c.X then 1 else -1, 0, 0)
	else
		face = if alongX then V3(0, 0, if cab.c.Z < (V.door and V.door.z or V.z1) then 1 else -1) else V3(if cab.c.X < 0 then 1 else -1, 0, 0)
	end
	local len = if alongX then cab.size.X else cab.size.Z
	local dep = if alongX then cab.size.Z else cab.size.X
	local fz = (if alongX then (if face.Z > 0 then cab.max.Z else cab.min.Z) else (if face.X > 0 then cab.max.X else cab.min.X))
	local fp = if alongX then V3(cab.c.X, cab.min.Y, fz) else V3(fz, cab.min.Y, cab.c.Z)
	local fcf = dcfAt(fp, face) -- 앞면 바닥 가운데 (dcf)
	local hgt = cab.size.Y
	K:free(function()
		local frameL = lk(C(30, 30, 34), M.Metal)
		-- 속이 빈 장: 뒤판 · 옆판 · 위아래 (앞은 칸마다 아크릴 턱)
		K:box("StCigBack", V3(len, hgt, 0.08), fcf * CF(0, hgt / 2, -dep + 0.05), frameL)
		K:plate("StCigBackLight", len - 0.24, hgt - 0.3, 0.02, fcf * CF(0, hgt / 2, -dep + 0.09), lk(C(236, 238, 242)))
		for _, sx in { -1, 1 } do
			K:box("StCigSide", V3(0.1, hgt, dep - 0.02), fcf * CF(sx * (len / 2 - 0.05), hgt / 2, -dep / 2), frameL)
		end
		K:box("StCigBottom", V3(len, 0.14, dep - 0.02), fcf * CF(0, 0.07, -dep / 2), frameL)
		K:box("StCigTop", V3(len, 0.1, dep - 0.02), fcf * CF(0, hgt - 0.05, -dep / 2), frameL)
		-- 위 1/4 = 광고 라이트박스, 아래 = 담배 칸
		local adH = math.clamp(hgt * 0.22, 0.9, 1.5)
		local ad = K:plate("StCigAd", len - 0.24, adH - 0.1, 0.04, fcf * CF(0, hgt - adH / 2 - 0.05, -0.1), lk(lighter(B.main, 0.15)))
		txt(K, "StCigAdText", len * 0.8, adH * 0.42, fcf * CF(0, hgt - adH * 0.32 - 0.05, -0.05), "궐련형 전자담배 · 일반 담배 · 라이터", WHITE, nil, { glow = 1.2, font = Enum.Font.GothamBold, d = 0.01 })
		txt(K, "StCigNotice", len - 0.4, adH * 0.32, fcf * CF(0, hgt - adH * 0.78 - 0.05, -0.04), "19세 미만 청소년에게 술 · 담배를 판매하지 않습니다 · 신분증 제시", WHITE, C(200, 30, 40), { d = 0.01, font = Enum.Font.GothamBold })
		local _ = ad
		local rowsH = hgt - adH - 0.25
		local rows = math.max(3, math.floor(rowsH / 0.62))
		local pitch = if K.detail == "high" then 0.34 else (if K.detail == "mid" then 0.44 else 0.66)
		local nCol = math.floor((len - 0.4) / pitch)
		for r = 1, rows do
			local y = 0.18 + (r - 1) * rowsH / rows
			K:box("StCigShelf", V3(len - 0.2, 0.04, dep - 0.2), fcf * CF(0, y, -dep / 2), lk(C(200, 204, 210), M.Metal))
			K:box("StCigLip", V3(len - 0.2, 0.12, 0.02), fcf * CF(0, y + 0.06, -0.05), { c = C(230, 236, 240), m = M.Glass, t = 0.3 })
			for i = 1, nCol do
				local x = -len / 2 + 0.2 + pitch * (i - 0.5)
				local col: Color3 = pick(rng, CIG_COLS)
				K:box("StCigPack", V3(pitch * 0.8, 0.44, 0.1), fcf * CF(x, y + 0.26, -0.22), lk(col))
			end
			if K.detail ~= "low" and r % 2 == 1 then
				txt(K, "StCigPrice", len - 0.4, 0.1, fcf * CF(0, y + 0.06, -0.035), "4,500      4,500      4,800      4,500      5,000      4,500      4,800      5,500", INK, C(250, 250, 248), { d = 0.01, font = Enum.Font.GothamBold })
			end
		end
		-- 장 아래 수납장 (바닥 ~ 장 밑, 같은 깊이: 계산대 뒤 직원 쪽, 서랍 + 문)
		if cab.min.Y > 1.2 then
			local bh = cab.min.Y - 0.02
			local bcf = fcf * CF(0, -cab.min.Y, 0)
			K:box("StCigBase", V3(len, bh, dep - 0.06), bcf * CF(0, bh / 2, -dep / 2), lk(C(236, 236, 232)))
			K:box("StCigBaseKick", V3(len - 0.1, 0.3, 0.04), bcf * CF(0, 0.15, -0.02), Look.charcoal)
			local nd = math.max(2, math.floor(len / 1.6))
			for i = 1, nd do
				local x = -len / 2 + (i - 0.5) * len / nd
				K:plate("StCigBaseDoor", len / nd - 0.08, bh - 0.5, 0.02, bcf * CF(x, 0.3 + (bh - 0.5) / 2 + 0.05, -0.03), lk(C(244, 244, 240)))
				K:box("StCigBaseHandle", V3(0.5, 0.05, 0.05), bcf * CF(x, bh - 0.35, 0.0), Look.chrome)
			end
		end
		-- 머리 라이트 박스
		if hd then
			local hlen = if alongX then hd.size.X else hd.size.Z
			local hfz = if alongX then (if face.Z > 0 then hd.max.Z else hd.min.Z) else (if face.X > 0 then hd.max.X else hd.min.X)
			local hp = if alongX then V3(hd.c.X, hd.c.Y, hfz) else V3(hfz, hd.c.Y, hd.c.Z)
			local hcf = dcfAt(hp, face)
			K:box("StCigHeader", V3(hlen, hd.size.Y, dep - 0.02), hcf * CF(0, 0, -dep / 2), lk(B.dark))
			txt(K, "StCigHeaderText", hlen * 0.9, hd.size.Y * 0.7, hcf * CF(0, 0, 0.002), "TOBACCO · 담배 · 전자담배", WHITE, nil, { glow = 1.3, font = Enum.Font.GothamBlack, d = 0.01 })
			Scan.hide(K.hidden, hd.part)
		end
	end)
	Scan.hide(K.hidden, cab.part)
	if pf then
		Scan.hide(K.hidden, pf.part)
	end
end

-- 냉장 워크인: 맵 와이어 선반 칸에 문(멀리언)별 범주로 음료 진열 + 문 위 범주 띠 + 문틀 LED
local function walkIn(K: any, V: any, surfs: { any }, B: any, rng: () -> number, theme: any, cats: { string })
	local fridge = {}
	for _, s in surfs do
		if s.fridge then
			table.insert(fridge, s)
		end
	end
	if #fridge == 0 then
		return 0
	end
	-- 냉장고 범위
	local mn, mx = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	for _, s in fridge do
		mn = mn:Min(s.rec.min)
		mx = mx:Max(s.rec.max)
	end
	local alongX = (mx.X - mn.X) >= (mx.Z - mn.Z)
	local s0 = fridge[1]
	-- 문 칸 경계 (DoorMullion)
	local cuts = {}
	for _, dm in V.byName.DoorMullion or {} do
		if dm.c.X > mn.X - 0.6 and dm.c.X < mx.X + 0.6 and dm.c.Z > mn.Z - 0.8 and dm.c.Z < mx.Z + 0.8 then
			local lp = s0.cf:PointToObjectSpace(dm.c)
			table.insert(cuts, lp.X)
		end
	end
	table.sort(cuts)
	local half = s0.len / 2
	local cols = {}
	local prev = -half
	for _, cx in cuts do
		if cx > prev + 0.6 and cx < half - 0.4 then
			table.insert(cols, { prev, cx })
			prev = cx
		end
	end
	table.insert(cols, { prev, half })
	-- 범주 (마지막 칸은 주류)
	local colCat = {}
	for i = 1, #cols do
		colCat[i] = cats[math.min(i, #cats)]
		if i == #cols and #cols >= 3 then
			colCat[i] = cats[#cats]
		end
	end
	local used = 0
	for _, s in fridge do
		for i, c in cols do
			local w = c[2] - c[1] - 0.16
			if w > 0.4 then
				local sub = { cf = s.cf * CF((c[1] + c[2]) / 2, 0, 0), len = w, depth = s.depth, clear = s.clear, rail = s.rail, level = s.level, levels = s.levels }
				queueFill(K, sub, colCat[i], V.key .. "f" .. i .. ":" .. (s.level or 0), theme, { facing = 3, noTags = true, gap = 0.03 })
			end
		end
	end
	-- 범주 띠 (냉장고 머리 Body 앞면) + 문틀 LED
	local body = nil
	for _, b in V.byName.Body or {} do
		if b.min.Y > mx.Y and overlapXZ(b, { min = mn, max = mx }, 0.6) then
			body = b
		end
	end
	local LABEL = { dairy = "우유 · 유제품", coffee = "커피 · 차음료", soda = "탄산 · 이온음료", waterF = "생수 · 주스", beer = "맥주 · 소주 · 하이볼", drinkRoom = "음료" }
	if body then
		local face = s0.cf.ZVector
		local fpos = if alongX then (if face.Z > 0 then body.max.Z else body.min.Z) else (if face.X > 0 then body.max.X else body.min.X)
		for i, c in cols do
			local mid = s0.cf * V3((c[1] + c[2]) / 2, 0, 0)
			local p = if alongX then V3(mid.X, (body.min.Y + body.max.Y) / 2, fpos) else V3(fpos, (body.min.Y + body.max.Y) / 2, mid.Z)
			local d = dcfAt(p, face)
			local w = c[2] - c[1] - 0.2
			local bg = if colCat[i] == "beer" then B.dark else (if i % 2 == 0 then B.main else lighter(B.main, 0.1))
			txt(K, "StFridgeCat", w, math.min(0.62, body.size.Y * 0.7), d, LABEL[colCat[i]] or "음료", WHITE, bg, { d = 0.02, font = Enum.Font.GothamBlack, glow = 1.15, free = true })
		end
		if K.detail ~= "low" then
			txt(K, "StFridgeSale", math.min(3.4, s0.len * 0.3), 0.3, dcfAt((if alongX then V3(mx.X - 1.9, body.min.Y - 0.25, fpos + face.Z * 0.02) else V3(fpos + face.X * 0.02, body.min.Y - 0.25, mx.Z - 1.9)), face), "맥주 4캔 12,000원 · 2+1 음료", INK, B.promo2, { d = 0.015, font = Enum.Font.GothamBlack, free = true })
		end
	end
	-- 문틀 안쪽 세로 LED (멀리언 바로 뒤)
	local face = s0.cf.ZVector
	for _, dm in V.byName.DoorMullion or {} do
		if dm.c.X > mn.X - 0.6 and dm.c.X < mx.X + 0.6 and dm.c.Z > mn.Z - 0.8 and dm.c.Z < mx.Z + 0.8 then
			local halfT = if math.abs(face.Z) > 0.5 then dm.size.Z / 2 else dm.size.X / 2
			local q = dm.c - face * (halfT + 0.05)
			K:box("StFridgeLED", V3(0.05, dm.size.Y - 0.3, 0.05), CF(q.X, dm.c.Y, q.Z), L_FREE(Look.lampCool))
		end
	end
	-- 맵 FridgeGlow (냉장고 뒤 전체가 눈부신 네온 판 -> 상품이 실루엣으로만 보임) 를 숨기고 같은 자리에 무광 흰 뒤판,
	-- 와이어 선반마다 앞 모서리 아래 LED 띠 + 흰 가격 레일 (행사 태그 몇 개) — 실제 워크인 쿨러처럼 상품 앞면이 밝게
	local fr = { min = mn, max = mx }
	K:free(function()
		for _, g in V.byName.FridgeGlow or {} do
			if overlapXZ(g, fr, 0.9) and g.part.Transparency < 0.99 then
				Scan.hide(K.hidden, g.part)
				-- 은은하게 빛나는 뒤판 (원래 네온 판의 1/2 밝기: 냉장고 안이 밝아 보이되 상품이 실루엣이 되지 않게)
				K:box("StFridgeBack", g.part.Size, g.lcf, Look.neon(C(128, 136, 144)))
				-- 뒤판 세로 이음 (판넬 칸)
				if K.detail ~= "low" then
					local alongG = g.size.X >= g.size.Z
					local glen = if alongG then g.size.X else g.size.Z
					local nseg = math.max(1, math.floor(glen / 2.6))
					local inward = if alongG then V3(0, 0, if g.c.Z < (mn.Z + mx.Z) / 2 + 0.01 then 1 else -1) else V3(if g.c.X < (mn.X + mx.X) / 2 + 0.01 then 1 else -1, 0, 0)
					local th = if alongG then g.size.Z else g.size.X
					for i = 1, nseg - 1 do
						local a = -glen / 2 + glen * i / nseg
						local p = g.c + inward * (th / 2 + 0.005) + (if alongG then V3(a, 0, 0) else V3(0, 0, a))
						K:box("StFridgeBackSeam", if alongG then V3(0.05, g.size.Y - 0.2, 0.01) else V3(0.01, g.size.Y - 0.2, 0.05), CF(p), lk(C(190, 196, 202)))
					end
				end
			end
		end
		local tr = mkRng(V.key .. "frail")
		local tags = 0
		for _, s in fridge do
			if s.rec and s.rec.name == "WireShelf" then
				K:box("StFridgeShelfLED", V3(s.len - 0.12, 0.035, 0.05), s.cf * CF(0, -0.075, -0.06), L_FREE(Look.lampCool))
				K:box("StFridgeRail", V3(s.len - 0.04, 0.17, 0.03), s.cf * CF(0, -0.05, 0.016), lk(C(250, 250, 248)))
				if K.detail ~= "low" then
					-- 레일 위 행사 태그 (빨강 1+1 · 노랑 2+1) + 가격 표 자국
					local n = math.floor(s.len / 0.9)
					for i = 1, n do
						local x = -s.len / 2 + (i - 0.5) * s.len / n
						local r = tr()
						if r < 0.22 and tags < 14 then
							tags += 1
							local promo = if r < 0.11 then "1+1" else "2+1"
							txt(K, "StFridgeTag", 0.36, 0.15, s.cf * CF(x, -0.05, 0.032), promo, if promo == "2+1" then INK else WHITE, if promo == "1+1" then theme.promo1 or C(230, 30, 50) else theme.promo2 or C(250, 190, 0), { d = 0.012, font = Enum.Font.GothamBlack, free = true })
						elseif K.detail == "high" and r < 0.62 then
							K:box("StFridgeTagInk", V3(0.2, 0.05, 0.01), s.cf * CF(x, -0.06, 0.036), lk(INK))
						end
					end
				end
			end
		end
		-- 냉장고 머리 안쪽 조명 (앞 위 FridgeLamp 바로 아래, 아래로 비춤) — 진열 상품 앞면을 밝힘
		local lit = 0
		for _, fl in V.byName.FridgeLamp or {} do
			if lit < 2 and overlapXZ(fl, fr, 0.9) then
				local bsz = if fl.size.Z > fl.size.X then V3(math.max(0.08, fl.size.X - 0.1), 0.04, math.max(0.4, fl.size.Z - 0.2)) else V3(math.max(0.4, fl.size.X - 0.2), 0.04, math.max(0.08, fl.size.Z - 0.1))
				local bar = K:box("StFridgeLightBar", bsz, CF(fl.c.X, fl.min.Y - 0.03, fl.c.Z), L_FREE(Look.lampCool))
				if K:light(bar, "SurfaceLight", { Face = Enum.NormalId.Bottom, Angle = 70, Range = 8, Brightness = 1.6, Color = Color3.fromRGB(236, 244, 255) }) then
					lit += 1
				end
			end
		end
	end)
	return used
end

-- 계산대 꾸밈 (카드 단말기 · 껌 진열 · 일회용 컵 · 봉투 안내 · 택배 스티커)
local function cashierDress(K: any, V: any, g: any, B: any, kind: string)
	local face = counterFace(V, g)
	local alongX = math.abs(face.Z) > 0.5
	local len = if alongX then g.max.X - g.min.X else g.max.Z - g.min.Z
	local fpos = if alongX then (if face.Z > 0 then g.max.Z else g.min.Z) else (if face.X > 0 then g.max.X else g.min.X)
	local mid = (g.min + g.max) / 2
	local fp = if alongX then V3(mid.X, 0, fpos) else V3(fpos, 0, mid.Z)
	local fc = dcfAt(fp, face) -- 계산대 앞면 바닥 (손님 쪽)
	local top = g.y
	local pos = nil
	for _, nm in { "PosBase", "CashierPanel" } do
		for _, r in V.byName[nm] or {} do
			if r.c.X > g.min.X - 0.3 and r.c.X < g.max.X + 0.3 and r.c.Z > g.min.Z - 0.6 and r.c.Z < g.max.Z + 0.6 then
				pos = pos or r
			end
		end
	end
	local posU = if pos then fc:PointToObjectSpace(pos.c).X else 0
	-- 앞면 스티커 (교통카드 · 택배 · 공과금)
	local stickers: { any } = {}
	if kind == "cvs" then
		stickers = { { "교통카드 충전\n티머니 · 캐시비", B.main }, { B.parcel, B.sub }, { "공과금 수납\n휴대폰 요금", C(80, 80, 86) } }
	elseif kind == "cosmetics" then
		stickers = { { "CJ ONE 포인트 적립\n올리브영 앱 쿠폰", C(154, 194, 27) }, { "오늘드림\n3시간 빠른 배송", C(30, 30, 30) } }
	elseif kind == "pharmacy" then
		stickers = { { "처방전 접수\n복약 상담", C(10, 138, 58) }, { "카드 · 간편결제\n현금영수증", C(60, 60, 66) } }
	else
		stickers = { { "카드 · 간편결제 OK\nTAX FREE", C(30, 80, 160) }, { "포장 · 선물 포장 가능", C(200, 40, 40) } }
	end
	local nSt = #stickers
	local sw = math.min(1.9, (len - 1.0) / math.max(1, nSt))
	for i, st in stickers do
		local u = -len / 2 + 0.5 + sw * (i - 0.5)
		if math.abs(u - posU) > 0.3 or true then
			K:free(function()
				txt(K, "StCounterSticker", sw - 0.2, 0.62, fc * CF(u, top * 0.62, 0.1), st[1], WHITE, st[2], { d = 0.01, font = Enum.Font.GothamBold })
			end)
		end
	end
	-- 상판 위 소품: 이미 놓인 것 (POS · 스티머 · 화면) 을 피해 손님 쪽 반에
	local onTop = {}
	for _, r in V.parts do
		if r.min.Y >= top - 0.15 and r.max.Y > top + 0.05 and r.c.X > g.min.X - 0.1 and r.c.X < g.max.X + 0.1 and r.c.Z > g.min.Z - 0.1 and r.c.Z < g.max.Z + 0.1 and r.part.Transparency < 0.99 then
			table.insert(onTop, r)
		end
	end
	local taken = {}
	local function topCf(u: number, depthIn: number): CFrame
		local p = fc * V3(u, top, -depthIn)
		return pcfAt(p, face)
	end
	local function slot(w: number, d: number, depthIn: number, us: { number }): CFrame?
		for _, u in us do
			if math.abs(u) + w / 2 < len / 2 - 0.12 then
				local cf = topCf(u, depthIn)
				local mn, mx = K.laabb(cf * CF(0, 0.3, 0), V3(w, 0.6, d))
				local ok = true
				for _, r in onTop do
					if K.overlap(mn, mx, r.min - V3(0.08, 0, 0.08), r.max + V3(0.08, 0, 0.08), 0) then
						ok = false
						break
					end
				end
				if ok then
					for _, t in taken do
						if K.overlap(mn, mx, t[1], t[2], 0) then
							ok = false
							break
						end
					end
				end
				if ok then
					table.insert(taken, { mn, mx })
					return cf
				end
			end
		end
		return nil
	end
	-- POS 에서 먼 끝 -> POS 쪽으로 훑는 후보
	local farSign = if posU > 0 then -1 else 1
	local function sweepFar(): { number }
		local out = {}
		local u = farSign * (len / 2 - 0.6)
		for _ = 1, 40 do
			table.insert(out, u)
			u -= farSign * 0.25
		end
		return out
	end
	local function nearPos(): { number }
		local out = {}
		for i = 0, 10 do
			table.insert(out, posU + farSign * (1.05 + i * 0.25))
			table.insert(out, posU - farSign * (1.05 + i * 0.25))
		end
		return out
	end
	K:free(function()
		-- 카드 단말기 (POS 옆, 손님 쪽)
		local tc = if V:has("CardReader") > 0 or V:has("CardTerminal") > 0 then nil else slot(0.5, 0.8, 0.5, nearPos())
		if tc then
			Props.cardTerminal(K, tc)
		end
		if kind == "cvs" then
			-- 껌 · 캔디 진열대 (계단식 3단)
			local gp = slot(1.0, 0.8, 0.55, sweepFar())
			if gp then
				for i = 0, 2 do
					K:box("StGumTier", V3(0.9, 0.12 + i * 0.16, 0.24), gp * CF(0, (0.12 + i * 0.16) / 2, 0.2 - i * 0.22), lk(C(240, 240, 240)))
					for j = 0, 3 do
						local col = ({ C(60, 160, 230), C(40, 170, 90), C(240, 80, 120), C(250, 190, 40) })[j + 1]
						K:box("StGumPack", V3(0.18, 0.16, 0.1), gp * CF(-0.33 + j * 0.22, 0.12 + i * 0.16 + 0.08, 0.2 - i * 0.22), lk(col))
					end
				end
				txt(K, "StBagSign", 0.9, 0.5, gp * CF(0, 1.05, -0.32), "봉투 필요하세요?\n종량제 · 종이봉투", INK, C(250, 250, 248), { d = 0.02, font = Enum.Font.GothamBold })
				K:seg("StBagSignStick", (gp * CF(0, 0.5, -0.34)).Position, (gp * CF(0, 0.8, -0.34)).Position, 0.03, Look.chrome)
			end
			-- 일회용 아이스컵 탑
			local cp = slot(0.4, 0.4, 0.4, sweepFar())
			if cp then
				K:vcyl("StCupStack", 0.7, 0.32, cp * CF(0, 0.35, 0), { c = C(236, 244, 250), m = M.Glass, t = 0.35 })
				K:vcyl("StCupStackTop", 0.04, 0.34, cp * CF(0, 0.71, 0), lk(C(250, 250, 250)))
			end
		elseif kind == "cosmetics" then
			local tp = slot(1.1, 0.7, 0.55, sweepFar())
			if tp then
				K:box("StLipTray", V3(1.0, 0.1, 0.6), tp * CF(0, 0.05, 0), lk(C(250, 250, 250)))
				for j = 0, 5 do
					local col = ({ C(230, 90, 110), C(200, 20, 50), C(240, 140, 150), C(180, 70, 60), C(250, 200, 210), C(150, 30, 60) })[j + 1]
					K:vcyl("StLipBalm", 0.28, 0.12, tp * CF(-0.38 + j * 0.15, 0.24, 0.1), lk(col))
				end
				txt(K, "StLipTrayTag", 0.8, 0.2, tp * CF(0, 0.13, 0.302), "계산대 특가 립밤 3,900", INK, C(250, 250, 248), { d = 0.01 })
			end
			local bp = slot(0.9, 0.5, 0.4, sweepFar())
			if bp then
				for i = 0, 2 do
					K:box("StShopBag", V3(0.8, 0.9, 0.08), bp * CF(0, 0.45, -0.1 + i * 0.1), lk(if i == 1 then OY.main else C(250, 250, 248)))
				end
			end
		elseif kind == "pharmacy" then
			-- 처방전 접수 아크릴 + 약봉투 + 손소독제
			local tp = slot(0.9, 0.4, 0.4, sweepFar())
			if tp then
				K:box("StRxStandBase", V3(0.8, 0.05, 0.3), tp * CF(0, 0.025, 0), Look.acrylicWhite)
				txt(K, "StRxStand", 0.76, 0.56, tp * CF(0, 0.34, 0), "처방전\n접수", C(10, 120, 50), C(250, 252, 250), { d = 0.03, font = Enum.Font.GothamBlack })
			end
			local bp = slot(0.8, 0.8, 0.6, sweepFar())
			if bp then
				for i = 0, 3 do
					K:box("StPillBag", V3(0.5, 0.02, 0.7), bp * CF(0, 0.012 + i * 0.022, 0) * ANG(0, 0.08 * i, 0), lk(C(250, 250, 246)))
				end
				K:box("StPillBagPrint", V3(0.3, 0.004, 0.2), bp * CF(0, 0.1, 0.1), lk(C(40, 150, 70)))
			end
			local sp = slot(0.4, 0.4, 0.35, sweepFar())
			if sp then
				K:vcyl("StSanitizer", 0.5, 0.26, sp * CF(0, 0.25, 0), { c = C(220, 240, 250), m = M.Glass, t = 0.3 })
				K:vcyl("StSanitizerPump", 0.14, 0.12, sp * CF(0, 0.57, 0), lk(C(250, 250, 250)))
			end
		else
			local tp = slot(1.1, 0.7, 0.5, sweepFar())
			if tp then
				K:box("StGiftWrapBase", V3(1.0, 0.06, 0.6), tp * CF(0, 0.03, 0), Look.walnut)
				K:cyl("StGiftWrapRoll", 0.9, 0.22, tp * CF(0, 0.2, 0.12), lk(C(200, 40, 40)))
				K:cyl("StGiftWrapRoll", 0.9, 0.22, tp * CF(0, 0.2, -0.12), lk(C(30, 80, 160)))
			end
		end
	end)
end

-- CCTV 모니터 (4분할 화면 · 벽 브래킷): 계산대 가까운 벽, 손님이 보도록 높이 6.6 이상
local function cctvMonitor(K: any, dcf: CFrame)
	K:plate("StCCTVArm", 0.3, 0.3, 0.5, dcf, Look.blackMetal)
	local m = dcf * CF(0, -0.1, 0.5)
	K:plate("StCCTVBezel", 1.7, 1.05, 0.12, m, Look.black)
	local cols = { C(60, 74, 80), C(52, 66, 74), C(70, 80, 84), C(56, 70, 66) }
	for i = 0, 3 do
		local x = -0.39 + (i % 2) * 0.78
		local y = 0.23 - math.floor(i / 2) * 0.46
		K:plate("StCCTVView", 0.74, 0.42, 0.01, m * CF(x, y, 0.12), { c = cols[i + 1], m = M.Neon, t = 0.35 })
	end
	txt(K, "StCCTVRec", 0.5, 0.12, m * CF(-0.52, 0.4, 0.135), "● REC  CAM1-4", C(255, 70, 60), nil, { glow = 1.4, d = 0.005 })
end

-- ATM 앞면 디테일 (같은 면에 얇은 덧붙임)
local function atmDress(K: any, V: any)
	local atm = V:first("ATM")
	if not atm then
		return
	end
	local scr = V:first("ATMScreen")
	local face = if scr then (if math.abs(scr.c.X - atm.c.X) > math.abs(scr.c.Z - atm.c.Z) then V3(math.sign(scr.c.X - atm.c.X), 0, 0) else V3(0, 0, math.sign(scr.c.Z - atm.c.Z))) else awayFromWall(V, atm)
	local fpos = if math.abs(face.X) > 0.5 then (if face.X > 0 then atm.max.X else atm.min.X) else (if face.Z > 0 then atm.max.Z else atm.min.Z)
	local p = if math.abs(face.X) > 0.5 then V3(fpos, 0, atm.c.Z) else V3(atm.c.X, 0, fpos)
	local d = dcfAt(p, face)
	local w = if math.abs(face.X) > 0.5 then atm.size.Z else atm.size.X
	K:free(function()
		K:plate("StATMFascia", w - 0.2, 1.3, 0.03, d * CF(0, 2.4, 0), lk(C(214, 218, 224), M.Metal))
		K:plate("StATMCardSlot", 0.5, 0.08, 0.05, d * CF(-w * 0.22, 2.75, 0.03), lk(C(40, 200, 120), M.Neon))
		K:plate("StATMCashSlot", 1.1, 0.12, 0.05, d * CF(0, 2.2, 0.03), lk(C(30, 30, 32)))
		K:plate("StATMReceipt", 0.4, 0.06, 0.05, d * CF(w * 0.25, 2.75, 0.03), lk(C(30, 30, 32)))
		txt(K, "StATMLabel", w - 0.4, 0.42, d * CF(0, 1.4, 0.035), "현금인출기 ATM\n입금 · 출금 · 이체 24시간", C(20, 60, 120), C(240, 244, 250), { d = 0.01, font = Enum.Font.GothamBold })
		local hd = V:first("ATMHeader")
		if hd then
			local hp = if math.abs(face.X) > 0.5 then V3((if face.X > 0 then hd.max.X else hd.min.X), hd.c.Y, hd.c.Z) else V3(hd.c.X, hd.c.Y, (if face.Z > 0 then hd.max.Z else hd.min.Z))
			txt(K, "StATMHead", w - 0.2, hd.size.Y * 0.7, dcfAt(hp, face), "ATM  24H", WHITE, C(20, 80, 170), { d = 0.02, font = Enum.Font.GothamBlack, glow = 1.2 })
		end
	end)
end

-- 셀프 원두커피 스테이션 (하부장 + 머신 + 컵 · 뚜껑 + 안내)
local function coffeeStation(K: any, pcf: CFrame, B: any)
	local w, d, h = 2.2, 1.5, 2.9
	K:box("StCoffeeCab", V3(w, h - 0.1, d), pcf * CF(0, (h - 0.1) / 2, 0), lk(B.dark))
	K:box("StCoffeeTop", V3(w + 0.06, 0.1, d + 0.06), pcf * CF(0, h - 0.05, 0), lk(C(236, 236, 232)))
	K:plate("StCoffeeDoorLine", 0.03, h - 0.6, 0.01, pcf * CF(0, (h - 0.1) / 2, d / 2), lk(darker(B.dark, 0.3)))
	txt(K, "StCoffeeCabText", w * 0.86, 0.5, pcf * CF(0, h * 0.55, d / 2 + 0.005), B.coffee, WHITE, nil, { font = Enum.Font.GothamBlack, d = 0.01 })
	-- 머신
	local m = pcf * CF(-0.3, h, -0.1)
	K:rbox("StCoffeeMachine", V3(1.1, 1.7, 1.0), 0.08, m * CF(0, 0.85, 0), lk(C(30, 30, 32), M.Metal))
	K:plate("StCoffeePanel", 0.8, 0.5, 0.02, m * CF(0, 1.3, 0.5), lk(C(60, 60, 64), M.Metal))
	K:plate("StCoffeeScreen", 0.46, 0.26, 0.02, m * CF(0, 1.32, 0.52), lk(C(60, 160, 240), M.Neon))
	K:box("StCoffeeNozzle", V3(0.3, 0.16, 0.2), m * CF(0, 0.82, 0.5), Look.chrome)
	K:box("StCoffeeDrip", V3(0.7, 0.06, 0.4), m * CF(0, 0.12, 0.42), Look.chrome)
	K:vcyl("StCoffeeCup", 0.32, 0.22, m * CF(0, 0.32, 0.42), lk(C(250, 250, 250)))
	-- 컵 · 뚜껑 · 빨대
	local c = pcf * CF(0.65, h, 0.1)
	for i = 0, 1 do
		K:vcyl("StCoffeeCups", 0.8, 0.28, c * CF(-0.15 + i * 0.32, 0.4, 0), lk(if i == 0 then C(250, 250, 250) else C(214, 196, 170)))
	end
	K:vcyl("StStrawCup", 0.4, 0.22, c * CF(0.2, 0.2, -0.36), lk(C(240, 240, 240)))
	for i = 0, 3 do
		K:seg("StStraw", (c * CF(0.16 + i * 0.03, 0.35, -0.36)).Position, (c * CF(0.12 + i * 0.06, 0.75, -0.38)).Position, 0.025, lk(({ C(230, 40, 50), C(40, 120, 220), C(250, 250, 250), C(40, 170, 90) })[i + 1]))
	end
	-- 안내판 (뒤 벽쪽 세움)
	txt(K, "StCoffeeMenu", w * 0.9, 1.2, pcf * CF(0, h + 2.4, -d / 2 + 0.1), "셀프 원두커피 " .. B.coffee .. "\n아메리카노 HOT 1,300 · ICE 1,800\n카페라떼 2,500 · 계산 후 컵 받아 가세요", WHITE, B.main, { d = 0.04, font = Enum.Font.GothamBold })
end

-- 무인 택배 접수기 (키오스크 + 저울 선반): 화면 안내를 넘겨 보는 상호작용
local function parcelKiosk(K: any, pcf: CFrame, B: any)
	local body = lk(C(242, 242, 240))
	K:box("StKioskPlinth", V3(1.4, 0.3, 1.0), pcf * CF(0, 0.15, 0), Look.charcoal)
	K:rbox("StKioskBody", V3(1.3, 4.0, 0.86), 0.12, pcf * CF(0, 2.3, -0.02), body)
	K:box("StKioskHead", V3(1.34, 0.62, 0.9), pcf * CF(0, 4.6, -0.02), lk(B.main))
	txt(K, "StKioskHeadText", 1.2, 0.46, pcf * CF(0, 4.6, 0.432), "무인 택배 접수", WHITE, nil, { font = Enum.Font.GothamBlack, d = 0.01, glow = 1.1 })
	K:box("StKioskBezel", V3(1.0, 1.3, 0.08), pcf * CF(0, 3.35, 0.42) * ANG(-0.1, 0, 0), Look.black)
	local scr, label = txt(K, "StKioskScreen", 0.86, 1.14, pcf * CF(0, 3.35, 0.46) * ANG(-0.1, 0, 0), "택배 접수\n화면을 눌러\n시작하세요", WHITE, C(30, 90, 170), { glow = 1.25, font = Enum.Font.GothamBold, d = 0.02 })
	K:box("StKioskPrinter", V3(0.6, 0.12, 0.1), pcf * CF(0, 2.4, 0.44), lk(C(40, 40, 44)))
	K:box("StKioskCard", V3(0.36, 0.2, 0.12), pcf * CF(0.3, 2.75, 0.45), lk(C(60, 60, 64)))
	K:plate("StKioskCardLED", 0.08, 0.04, 0.01, pcf * CF(0.3, 2.82, 0.51), Look.ledGreen)
	K:box("StKioskScanner", V3(0.24, 0.3, 0.2), pcf * CF(-0.36, 2.72, 0.47) * ANG(0.3, 0, 0), Look.black)
	-- 옆 저울 선반
	K:box("StScaleShelf", V3(1.0, 0.1, 0.8), pcf * CF(1.2, 2.0, 0), lk(C(220, 222, 226), M.Metal))
	K:box("StScaleLeg", V3(0.1, 2.0, 0.1), pcf * CF(1.6, 1.0, 0.3), Look.chrome)
	K:box("StScaleLeg", V3(0.1, 2.0, 0.1), pcf * CF(1.6, 1.0, -0.3), Look.chrome)
	K:box("StScale", V3(0.8, 0.12, 0.6), pcf * CF(1.2, 2.11, 0), Look.steel)
	K:plate("StScaleLCD", 0.3, 0.1, 0.01, pcf * CF(1.2, 2.11, 0.305), Look.ledRed)
	K:box("StParcelBox", V3(0.6, 0.45, 0.5), pcf * CF(1.2, 2.4, 0), Look.kraft)
	K:box("StParcelTape", V3(0.62, 0.04, 0.1), pcf * CF(1.2, 2.63, 0), lk(C(220, 200, 150), M.Plastic))
	txt(K, "StKioskGuide", 1.1, 0.7, pcf * CF(0, 1.4, 0.44), B.parcel .. "\n접수 마감 22:00", INK, C(250, 250, 248), { d = 0.01, font = Enum.Font.GothamBold })
	local frames = { "택배 접수\n화면을 눌러\n시작하세요", "1. 받는 분 주소\n입력", "2. 저울에 올려\n무게 측정", "3. 운송장 출력 후\n상자에 부착", "결제는 계산대에서\n" .. B.parcel }
	local i = 1
	promptOn(K, { scr }, {
		action = "화면 넘기기",
		object = "무인 택배 접수기",
		fn = function()
			i = i % #frames + 1
			if label.Parent then
				label.Text = frames[i]
			end
		end,
	})
end

-- 2L 생수 묶음 더미 (팔레트 위, 창가 낮은 진열)
local function waterStack(K: any, pcf: CFrame, B: any)
	K:box("StPallet", V3(2.4, 0.22, 1.6), pcf * CF(0, 0.11, 0), Look.pine)
	local pw, ph, pd = 1.15, 1.02, 0.76
	for layer = 0, 1 do
		for i = 0, 1 do
			for j = 0, 1 do
				local p = pcf * CF(-0.58 + i * 1.17, 0.22 + layer * ph + ph / 2, -0.39 + j * 0.78)
				K:box("StWaterPack", V3(pw, ph, pd), p, { c = C(196, 226, 246), m = M.Glass, t = 0.25, r = 0.1 })
				if K.detail ~= "low" and j == 1 then
					K:box("StWaterPackLabel", V3(pw + 0.01, 0.26, pd + 0.01), p * CF(0, 0.05, 0), lk(C(30, 110, 200)))
				end
			end
		end
	end
	K:bar("StWaterHandle", (pcf * CF(-0.9, 2.3, 0.39)).Position, (pcf * CF(-0.3, 2.3, 0.39)).Position, 0.05, 0.1, lk(C(250, 250, 250)))
	txt(K, "StWaterPOP", 1.8, 0.6, pcf * CF(0, 2.4, 0.8), "생수 2L × 6 행사 5,980원", WHITE, B.promo1, { d = 0.03, font = Enum.Font.GothamBlack })
	K:seg("StWaterPOPStick", (pcf * CF(0.9, 2.1, 0.76)).Position, (pcf * CF(0.9, 2.7, 0.76)).Position, 0.04, Look.chrome)
end

-- 라면 · 전자레인지 코너 (맵 전자레인지 · 온수기 위 벽에 안내, 끝에 국물 버리는 통)
local function ramenCorner(K: any, V: any, B: any)
	local mw = V.byName.Microwave or {}
	local hw = V:first("HotWater")
	if #mw == 0 and not hw then
		return
	end
	local ref = hw or mw[1]
	-- 벽 (가장 가까운 벽)
	local dl, dr, db = ref.min.X - V.x0, V.x1 - ref.max.X, ref.min.Z - V.z0
	local wn = if db <= dl and db <= dr then "back" elseif dl < dr then "left" else "right"
	local u = V:wallCoord(wn, ref.c)
	local dcf = V:wall(wn, u, 4.75, 0.06)
	if not wallBusy(K, wn, u - 1.6, u + 1.6, 4.2, 5.3) then
		local mn, mx = K.laabb(dcf * CF(0, 0, 0.05), V3(3.0, 0.7, 0.1))
		if not mapBlocked(K, mn, mx) then
			txt(K, "StRamenGuide", 3.0, 0.6, dcf, "컵라면 물 붓는 선까지 · 전자레인지 용기 확인 · 국물은 통에", INK, C(250, 236, 120), { d = 0.02, font = Enum.Font.GothamBold })
			addWallUsed(K, wn, u - 1.6, u + 1.6, 4.3, 5.2)
		end
	end
	-- 벽에 붙인 양념 · 냅킨 꽂이 (전자레인지 사이 빈 벽, 상판 바로 위 얕게)
	local cnt0 = nil
	for _, g in V.counters do
		if ref.c.X >= g.min.X - 0.5 and ref.c.X <= g.max.X + 0.5 and ref.c.Z >= g.min.Z - 0.8 and ref.c.Z <= g.max.Z + 0.8 then
			cnt0 = g
		end
	end
	local sinkX: number? = nil
	if cnt0 and wn == "back" then
		local busy = {}
		for _, r in V.parts do
			if r.min.Y >= cnt0.y - 0.15 and r.min.Y < cnt0.y + 0.6 and r.max.Y > cnt0.y + 0.05 and r.c.X > cnt0.min.X and r.c.X < cnt0.max.X and r.c.Z > cnt0.min.Z - 0.1 and r.c.Z < cnt0.max.Z + 0.1 then
				table.insert(busy, { r.min.X - 0.15, r.max.X + 0.15 })
			end
		end
		table.sort(busy, function(a, b)
			return a[1] < b[1]
		end)
		local cur, best, bw = cnt0.min.X + 0.2, nil, 0
		for _, b in busy do
			if b[1] - cur > bw then
				best, bw = (cur + b[1]) / 2, b[1] - cur
			end
			cur = math.max(cur, b[2])
		end
		if cnt0.max.X - 0.2 - cur > bw then
			best, bw = (cur + cnt0.max.X - 0.2) / 2, cnt0.max.X - 0.2 - cur
		end
		-- 가장 넓은 빈 구간: 온수기 쪽 끝 1.1 = 국물 개수대 (편의점 라면 코너의 상징), 남으면 양념 · 젓가락 꽂이
		if best and bw >= 1.15 then
			local ga, gb = best - bw / 2, best + bw / 2
			local hx = if hw then hw.c.X else ref.c.X
			local nearA = math.abs(ga - hx) <= math.abs(gb - hx)
			sinkX = if bw < 2.4 then best elseif nearA then ga + 0.55 else gb - 0.55
			if bw >= 2.4 then
				local ra, rb = if nearA then ga + 1.25 else ga, if nearA then gb else gb - 1.25
				best, bw = (ra + rb) / 2, rb - ra
			else
				best, bw = nil, 0
			end
		end
		if best and bw >= 1.2 then
			local rw = math.min(1.8, bw - 0.2)
			local u2 = best - (V.x0 + V.x1) / 2
			local rc = V:wall("back", u2, cnt0.y, 0.02)
			K:free(function()
				K:box("StCondRack", V3(rw, 0.06, 0.36), rc * CF(0, 0.5, 0.18), Look.steel)
				K:box("StCondRackBack", V3(rw, 0.8, 0.04), rc * CF(0, 0.45, 0.02), Look.steel)
				K:box("StNapkinBox", V3(0.5, 0.36, 0.3), rc * CF(-rw / 2 + 0.35, 0.71, 0.18), lk(C(250, 250, 250)))
				K:box("StNapkinTissue", V3(0.2, 0.08, 0.12), rc * CF(-rw / 2 + 0.35, 0.93, 0.18), Look.paper)
				K:vcyl("StChopCup", 0.4, 0.24, rc * CF(-rw / 2 + 0.85, 0.73, 0.18), Look.steel)
				for i = 0, 4 do
					K:seg("StChopstick", (rc * CF(-rw / 2 + 0.8 + i * 0.025, 0.6, 0.18)).Position, (rc * CF(-rw / 2 + 0.78 + i * 0.03, 1.12, 0.16)).Position, 0.03, Look.birch)
				end
				K:vcyl("StForkCup", 0.36, 0.22, rc * CF(-rw / 2 + 1.2, 0.71, 0.18), lk(C(240, 240, 240)))
				if rw > 1.5 then
					K:box("StWetWipe", V3(0.36, 0.14, 0.26), rc * CF(rw / 2 - 0.25, 0.6, 0.18), lk(C(170, 220, 250)))
				end
			end)
		end
	end
	-- 국물 버리는 통 (카운터 옆 바닥)
	local cnt = nil
	for _, g in V.counters do
		if ref.c.X >= g.min.X - 0.5 and ref.c.X <= g.max.X + 0.5 and ref.c.Z >= g.min.Z - 0.8 and ref.c.Z <= g.max.Z + 0.8 then
			cnt = g
		end
	end
	if cnt then
		local cands = {}
		local alongX = (cnt.max.X - cnt.min.X) >= (cnt.max.Z - cnt.min.Z)
		local face = V3(0, 0, 1)
		if alongX then
			table.insert(cands, V3(cnt.max.X + 0.65, 0, cnt.min.Z + 0.6))
			table.insert(cands, V3(cnt.min.X - 0.65, 0, cnt.min.Z + 0.6))
			-- 옆 자리가 없으면 카운터 앞 끝 (전자레인지 · 온수기 앞 예약 칸 밖)
			local fz = if (cnt.min.Z + cnt.max.Z) / 2 < (V.z0 + V.z1) / 2 then cnt.max.Z + 0.6 else cnt.min.Z - 0.6
			for fx = cnt.min.X + 0.55, cnt.max.X - 0.55, 0.25 do
				table.insert(cands, V3(fx, 0, fz))
			end
		else
			table.insert(cands, V3((cnt.min.X + cnt.max.X) / 2, 0, cnt.max.Z + 0.65))
			table.insert(cands, V3((cnt.min.X + cnt.max.X) / 2, 0, cnt.min.Z - 0.65))
			local fx = if (cnt.min.X + cnt.max.X) / 2 < (V.x0 + V.x1) / 2 then cnt.max.X + 0.6 else cnt.min.X - 0.6
			for fz = cnt.min.Z + 0.55, cnt.max.Z - 0.55, 0.25 do
				table.insert(cands, V3(fx, 0, fz))
			end
		end
		local pcf = floorSpot(K, cands, V3(1.0, 2.6, 1.0), face, 0, "soupbin")
		if pcf then
			K:vcyl("StSoupBin", 2.0, 0.9, pcf * CF(0, 1.0, 0), lk(C(70, 74, 80), M.Plastic))
			K:vcyl("StSoupBinLid", 0.1, 0.96, pcf * CF(0, 2.05, 0), lk(C(220, 222, 224), M.Metal))
			K:disc("StSoupBinMesh", 0.6, 0.02, pcf * CF(0, 2.11, 0), lk(C(150, 150, 150), M.DiamondPlate))
			txt(K, "StSoupBinLabel", 0.7, 0.4, pcf * CF(0, 1.4, 0.452), "국물\n버리는 곳", WHITE, C(200, 40, 40), { d = 0.01 })
		elseif sinkX and cnt0 then
			-- 바닥 자리가 없으면 (카운터 앞 = 손님 자리) 상판에 얹힌 스테인리스 국물 개수대 + 거름망 + 안내판
			local y = cnt0.y
			local zc = cnt0.max.Z - 0.62
			local sc = CF(sinkX, y, zc)
			K:free(function()
				K:box("StSoupSinkRim", V3(1.0, 0.05, 0.9), sc * CF(0, 0.025, 0), Look.steel)
				K:box("StSoupSinkBasin", V3(0.78, 0.012, 0.68), sc * CF(0, 0.056, 0), lk(C(60, 64, 70), M.Metal))
				K:box("StSoupSinkGrate", V3(0.5, 0.012, 0.42), sc * CF(0, 0.066, 0), lk(C(170, 172, 176), M.DiamondPlate))
				K:vcyl("StSoupSinkDrain", 0.014, 0.16, sc * CF(0, 0.072, 0), lk(C(30, 30, 32), M.Metal))
				K:box("StSoupSinkBack", V3(1.0, 0.55, 0.05), sc * CF(0, 0.3, -0.43), Look.steel)
				txt(K, "StSoupSinkLabel", 0.9, 0.42, sc * CF(0, 0.32, -0.402), "국물 버리는 곳\n건더기는 거름망에", WHITE, C(200, 40, 40), { d = 0.01, font = Enum.Font.GothamBold })
			end)
		end
	end
end

-- 미뤄 둔 공통 벽 부착물 (스위치 · 콘센트 · 온도조절기 · 비상벨 · 사업자등록증 · 시계) — 큰 진열장 다음, 포스터 전에 한 번
local function fixturesNow(K: any, V: any, S: any)
	if K.stFixturesDone then
		return
	end
	K.stFixturesDone = true
	step(K, "fixtures", function()
		sortWallUsed(K)
		Common.fixtures(K, V, S)
	end)
end

local function buildCvs(K: any, V: any, S: any, brand: string)
	local B = table.clone(BRANDS[brand] or BRANDS.indie)
	if brand == "indie" then
		B.name = tostring(V.name or "마트")
	end
	local rng = mkRng(V.key .. "cvs")
	local theme = { promo1 = B.promo1, promo2 = B.promo2, p11 = 0.14, p21 = 0.16, maxTagText = 34 }
	local surfs = mapSurfaces(V)
	local obst = obstacles(V)
	-- 손님 앞 공간 예약
	for _, g in V.counters do
		reserveFront(K, g.min, g.max, counterFace(V, g), 2.6, 0.4)
	end
	for _, nm in { "Microwave", "HotWater" } do
		for _, r in V.byName[nm] or {} do
			reserveFront(K, r.min, r.max, awayFromWall(V, r), 2.6, 0.4)
		end
	end
	for _, nm in { "ATM", "IceCreamChest", "FridgeDoor" } do
		for _, r in V.byName[nm] or {} do
			local dir = awayFromWall(V, r)
			if nm == "FridgeDoor" then
				dir = if r.size.X > r.size.Z then V3(0, 0, if r.c.Z < (V.z0 + V.z1) / 2 then 1 else -1) else V3(if r.c.X < 0 then 1 else -1, 0, 0)
			end
			reserveFront(K, r.min, r.max, dir, if nm == "IceCreamChest" then 1.6 else 2.8, 0.3)
		end
	end
	for _, s in surfs do
		if not s.fridge then
			local r = s.rec
			local fwd = s.cf.ZVector
			reserveFront(K, r.min, r.max, V3(math.round(fwd.X), 0, math.round(fwd.Z)), 2.2, 0.2)
		end
	end
	-- 맵 상품 숨김
	for _, nm in { "Product", "Bottle" } do
		for _, r in V.byName[nm] or {} do
			Scan.hide(K.hidden, r.part)
		end
	end
	local used = 0
	step(K, "fridge", function()
		used += walkIn(K, V, surfs, B, rng, theme, { "dairy", "coffee", "soda", "waterF", "beer" })
	end)
	-- 곤돌라: 면마다 범주
	local faceCats = { "snack", "ramen", "sweets", "daily" }
	local faceOf: { [string]: string } = {}
	local nf = 0
	step(K, "gondola", function()
		K:free(function()
			for _, s in surfs do
				if not s.fridge then
					local cat = faceOf[s.face]
					if not cat then
						nf += 1
						cat = faceCats[(nf - 1 + math.floor(rng() * 2)) % #faceCats + 1]
						faceOf[s.face] = cat
					end
					queueFill(K, s, cat, V.key .. s.face .. (s.level or 0), theme, { obst = obst })
				end
			end
		end)
	end)
	-- 곤돌라 끝판 POP + 머리 띠
	step(K, "endcaps", function()
		local CATN = { snack = "과자 · 스낵", ramen = "라면 · 즉석식품", sweets = "초콜릿 · 캔디 · 젤리", daily = "생활용품 · 위생" }
		local promos = { { "2+1", "음료 · 과자 행사" }, { "1+1", B.pb .. " 신상품" }, { "이달의 행사", "카드 결제 시 10% 할인" } }
		for i, ep in V.byName.EndPanel or {} do
			local thinX = ep.size.X < ep.size.Z
			-- 바깥쪽 = 진열대 중심 반대
			local cen = nil
			for _, s in surfs do
				if not s.fridge and overlapXZ(s.rec, ep, 0.6) then
					cen = s.rec.c
				end
			end
			local face = if thinX then V3(if cen and cen.X > ep.c.X then -1 else 1, 0, 0) else V3(0, 0, if cen and cen.Z > ep.c.Z then -1 else 1)
			local fpos = if thinX then (if face.X > 0 then ep.max.X else ep.min.X) else (if face.Z > 0 then ep.max.Z else ep.min.Z)
			local w = if thinX then ep.size.Z else ep.size.X
			local p = if thinX then V3(fpos, ep.size.Y * 0.5, ep.c.Z) else V3(ep.c.X, ep.size.Y * 0.5, fpos)
			local d = dcfAt(p, face)
			local pr = promos[(i - 1) % #promos + 1]
			K:free(function()
				poster(K, d * CF(0, 0, -0.05), w - 0.4, ep.size.Y - 1.2, pr[1], pr[2] .. "\n" .. B.name, C(252, 252, 250), INK, if i % 2 == 0 then B.promo1 else B.main, WHITE, { titleH = 0.42, frame = false })
			end)
			for _, eh in V.byName.EndHeader or {} do
				if overlapXZ(eh, ep, 0.05) then
					local hp = if thinX then V3((if face.X > 0 then eh.max.X else eh.min.X), eh.c.Y, eh.c.Z) else V3(eh.c.X, eh.c.Y, (if face.Z > 0 then eh.max.Z else eh.min.Z))
					local catName = "행사상품"
					for _, s in surfs do
						if not s.fridge and overlapXZ(s.rec, ep, 0.6) and faceOf[s.face] then
							catName = CATN[faceOf[s.face]] or catName
						end
					end
					K:free(function()
						txt(K, "StEndHeaderText", w - 0.2, eh.size.Y * 0.72, dcfAt(hp, face), catName, WHITE, B.main, { d = 0.015, font = Enum.Font.GothamBlack })
					end)
				end
			end
		end
	end)
	-- 담배장 · 계산대 · 라면 코너 · ATM
	step(K, "cig", function()
		cigCabinet(K, V, B, mkRng(V.key .. "cig"))
	end)
	step(K, "cashier", function()
		for _, g in V.counters do
			local hasPos = false
			for _, r in V.byName.PosBase or {} do
				if r.c.X > g.min.X - 0.3 and r.c.X < g.max.X + 0.3 and r.c.Z > g.min.Z - 0.6 and r.c.Z < g.max.Z + 0.6 then
					hasPos = true
				end
			end
			if hasPos then
				cashierDress(K, V, g, B, "cvs")
			end
		end
	end)
	step(K, "ramen", function()
		ramenCorner(K, V, B)
	end)
	step(K, "cctvmon", function()
		local cash = nil
		for _, g in V.counters do
			for _, r in V.byName.PosBase or {} do
				if r.c.X > g.min.X - 0.3 and r.c.X < g.max.X + 0.3 and r.c.Z > g.min.Z - 0.6 and r.c.Z < g.max.Z + 0.6 then
					cash = g
				end
			end
		end
		if cash then
			local c = (cash.min + cash.max) / 2
			local wn = if math.abs(c.X - V.x0) < math.abs(V.x1 - c.X) then "left" else "right"
			local wn2, dcf = wallItemSpot(K, { wn, "back" }, 1.8, 6.7, 8.0, (V:wallCoord(wn, c)))
			if wn2 and dcf then
				cctvMonitor(K, dcf * CF(0, 0, 0.02))
			end
		end
	end)
	step(K, "atm", function()
		atmDress(K, V)
	end)
	-- 아이스크림 냉동고 뒤 모서리 POP (높이 3.4 아래)
	step(K, "icecream", function()
		local ic = V:first("IceCreamChest")
		if ic then
			local alongX = ic.size.X >= ic.size.Z
			-- 뒤쪽 = 가까운 벽 쪽 (손님은 반대편)
			local face = if alongX then V3(0, 0, if ic.c.Z > (V.z0 + V.z1) / 2 then -1 else 1) else V3(if ic.c.X > 0 then -1 else 1, 0, 0)
			local back = if alongX then V3(ic.c.X, ic.max.Y, if face.Z < 0 then ic.max.Z - 0.08 else ic.min.Z + 0.08) else V3(if face.X < 0 then ic.max.X - 0.08 else ic.min.X + 0.08, ic.max.Y, ic.c.Z)
			local d = dcfAt(back + V3(0, 0.36, 0), face)
			local w = math.min(2.2, (if alongX then ic.size.X else ic.size.Z) - 0.6)
			K:free(function()
				K:box("StIceClip", V3(0.3, 0.12, 0.12), dcfAt(back + V3(0, 0.04, 0), face) * CF(0, 0, -0.02), Look.chrome)
				txt(K, "StIcePOP", w, 0.6, d, "아이스크림 상시 할인\n콘 · 바 · 튜브 2+1", WHITE, B.promo1, { d = 0.03, font = Enum.Font.GothamBlack })
			end)
		end
	end)
	-- 핫바 · 호빵 (SteamerCase 안)
	step(K, "steamer", function()
		local sc = V:first("SteamerCase")
		if sc then
			K:free(function()
				local y = sc.min.Y + 0.08
				K:box("StSteamerTray", V3(sc.size.X - 0.2, 0.04, sc.size.Z - 0.2), CF(sc.c.X, y, sc.c.Z), Look.steel)
				for i = 0, 4 do
					local x = sc.min.X + 0.3 + i * (sc.size.X - 0.6) / 4
					K:box("StHotBar", V3(0.16, 0.12, 0.8), CF(x, y + 0.1, sc.c.Z + 0.1), lk(C(214, 150, 90)))
					K:seg("StHotBarStick", V3(x, y + 0.1, sc.c.Z - 0.3), V3(x, y + 0.12, sc.c.Z - 0.55), 0.03, lk(C(230, 210, 170)))
				end
				for i = 0, 2 do
					K:ell("StHoppang", V3(0.42, 0.3, 0.42), CF(sc.min.X + 0.4 + i * 0.6, y + 0.62, sc.c.Z), lk(C(250, 246, 236)))
				end
				K:box("StSteamerShelf", V3(sc.size.X - 0.2, 0.03, sc.size.Z - 0.3), CF(sc.c.X, y + 0.45, sc.c.Z), Look.steel)
				txt(K, "StSteamerTag", math.min(1.8, sc.size.X - 0.2), 0.26, dcfAt(V3(sc.c.X, sc.max.Y + 0.15, sc.c.Z + sc.size.Z / 2), V3(0, 0, 1)), "핫바 2,800 · 호빵 1,800 · 군고구마 3,000", WHITE, C(200, 40, 40), { d = 0.02, font = Enum.Font.GothamBold })
			end)
		end
	end)
	-- 디지털 사이니지 (손 닿는 높이, 서버 앵커에서 먼 벽) — 벽 진열장보다 먼저 자리 잡음
	step(K, "did", function()
		local wn, dcf = wallItemSpot(K, { "right", "left", "back" }, 3.4, 4.6, 6.6, -2, function(d: CFrame): boolean
			return promptOk(K, d.Position)
		end)
		if wn and dcf then
			didScreen(K, dcf * CF(0, 0.1, 0.04), 3.0, {
				{ text = B.name .. "\n이달의 행사 1+1 · 2+1", c = B.main },
				{ text = "도시락 · 삼각김밥\n" .. B.pb .. " 신상", c = darker(B.sub, 0.2) },
				{ text = B.coffee .. "\n아이스 아메리카노 1,800", c = C(70, 44, 30) },
				{ text = B.parcel .. "\n" .. B.app, c = B.dark },
			}, B.name .. " 광고 화면")
		end
	end)
	-- 무인 택배 접수기: 벽 쪽 우선, 없으면 바닥 (화면이 서버 앵커에서 먼 곳)
	step(K, "parcel", function()
		local function okAt(c: CFrame): boolean
			return promptOk(K, (c * CF(0, 3, 0.5)).Position)
		end
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 2.5, 1.1, 5.2, nil, 0.1, "kiosk", function(c: CFrame): boolean
			return okAt(c * CF(-0.55, 0, 0))
		end)
		if wn and pcf then
			parcelKiosk(K, pcf * CF(-0.55, 0, 0), B)
			return
		end
		local cands = {}
		for gx = V.x0 + 2, V.x1 - 2, 0.5 do
			for gz = V.z0 + 2, V.z1 - 4, 0.5 do
				table.insert(cands, V3(gx, 0, gz))
			end
		end
		for _, face in { V3(0, 0, 1), V3(1, 0, 0), V3(-1, 0, 0) } do
			local pc = floorSpot(K, cands, V3(2.6, 5.2, 1.2), face, 0.9, "kiosk", function(p: Vector3): boolean
				return okAt(pcfAt(p, face) * CF(-0.55, 0, 0))
			end)
			if pc then
				parcelKiosk(K, pc * CF(-0.55, 0, 0), B)
				return
			end
		end
	end)
	-- 새 바닥 소품: 벽 진열장 · 커피 · 생수 · 장바구니
	step(K, "wallunits", function()
		local hU = math.min(5.6, V.H - 2.4)
		local cats = { { "daily", "생활용품 · 위생 · 충전기" }, { "sweets", "초콜릿 · 젤리 · 디저트" }, { "drinkRoom", "음료 · 상온 생수" } }
		local placed = 0
		for _, cc in cats do
			if placed >= 2 then
				break
			end
			for _, len in { 7.2, 5.6, 4.2 } do
				local wn, pcf = wallFloorSpot(K, { "right", "left", "back" }, len, 1.35, hU + 0.7, nil, 0.0, "wallunit")
				if wn and pcf then
					local us = wallUnit(K, pcf, len, 1.35, hU, { title = cc[2], headL = lk(B.main), titleFg = WHITE, lineL = lk(B.sub), levels = 5, glow = 1.1 })
					K:free(function()
						for _, s in us do
							queueFill(K, s, cc[1], V.key .. cc[1] .. s.level, theme, {})
						end
					end)
					placed += 1
					break
				end
			end
		end
	end)
	step(K, "coffee", function()
		local cash = nil
		for _, g in V.counters do
			if V:first("PosBase") and (V:first("PosBase").c - (g.min + g.max) / 2).Magnitude < 5 then
				cash = g
			end
		end
		local prefer = if cash then (cash.min + cash.max) / 2 else nil
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 2.3, 1.55, 5.6, prefer, 0.0, "coffee")
		if wn and pcf then
			coffeeStation(K, pcf, B)
		end
	end)
	step(K, "water", function()
		local cands = {}
		for _, fx in { -0.38, 0.38, -0.25, 0.25, -0.12, 0.12 } do
			table.insert(cands, V3((V.x0 + V.x1) / 2 + V.W * fx, 0, V.z1 - 1.3))
		end
		local pcf = floorSpot(K, cands, V3(2.5, 3.0, 1.7), V3(0, 0, -1), 0.1, "water")
		if pcf then
			waterStack(K, pcf, B)
		end
	end)
	step(K, "baskets", function()
		local d = V.door
		local cands = {}
		if d then
			for _, dx in { 5.2, -5.2, 6.2, -6.2 } do
				table.insert(cands, V3(d.x + dx, 0, V.z1 - 3.2))
				table.insert(cands, V3(d.x + dx, 0, V.z1 - 4.6))
			end
		end
		local pcf = floorSpot(K, cands, V3(1.5, 2.2, 1.1), V3(0, 0, 1), 0.05, "basket")
		if pcf then
			basketStack(K, pcf, B.basket, 6, B.name)
		end
	end)
	-- 입구 옆 우산 통 (비 오는 날 장우산 · 3단 우산 판매) + 가격 POP
	step(K, "umbrella", function()
		local d = V.door
		if not d then
			return
		end
		local cands = {}
		for _, dx in { 3.4, -3.4, 4.2, -4.2, 5.0, -5.0, 6.4, -6.4 } do
			table.insert(cands, V3(d.x + dx, 0, V.z1 - 0.75))
			table.insert(cands, V3(d.x + dx, 0, V.z1 - 1.4))
		end
		local pcf = floorSpot(K, cands, V3(1.0, 3.2, 1.0), V3(0, 0, -1), 0.05, "umbrella")
		if not pcf then
			return
		end
		local ur = mkRng(V.key .. "umb")
		K:vcyl("StUmbBin", 1.4, 0.86, pcf * CF(0, 0.7, 0), lk(C(70, 74, 80), M.Metal))
		K:vcyl("StUmbBinRim", 0.08, 0.92, pcf * CF(0, 1.4, 0), Look.chrome)
		local cols = { C(20, 24, 30), C(30, 60, 120), C(150, 30, 40), C(230, 230, 226), C(40, 90, 70), B.main }
		for i = 0, 5 do
			local a = i / 6 * PI * 2 + ur()
			local top = (pcf * CF(math.cos(a) * 0.34, 2.55 + ur() * 0.4, math.sin(a) * 0.34)).Position
			local bot = (pcf * CF(math.cos(a) * 0.14, 0.2, math.sin(a) * 0.14)).Position
			local col = cols[(i % #cols) + 1]
			-- 접힌 우산: 천 부분(아래 넓게) + 손잡이 막대 + J 손잡이
			K:seg("StUmbCanopy", bot + (top - bot) * 0.05, bot + (top - bot) * 0.72, 0.2, lk(col, M.Fabric))
			K:seg("StUmbShaft", bot + (top - bot) * 0.72, top, 0.05, Look.chrome)
			if K.detail ~= "low" then
				K:ball("StUmbHandle", 0.13, CF(top), lk(C(40, 30, 24), M.Wood))
			end
		end
		txt(K, "StUmbPOP", 0.66, 0.46, pcf * CF(0, 0.9, 0.45), "장우산 9,900\n3단 12,000", INK, C(250, 250, 248), { d = 0.02, font = Enum.Font.GothamBold })
	end)
	fixturesNow(K, V, S)
	-- 천장 POP (진열대 위 · 입구 쪽을 봄)
	step(K, "hang", function()
		local done = 0
		local texts = { { "1+1 · 2+1 행사상품", "이달의 행사 " .. B.name }, { B.pb .. " 신상품", "도시락 · 김밥 · 샌드위치" }, { "카드 · 간편결제 OK", B.app } }
		local yb = math.max(6.0, V.H - 2.6)
		for _, c in clusters(surfs) do
			if done < 2 then
				local cx, cz = (c.min.X + c.max.X) / 2, (c.min.Z + c.max.Z) / 2
				local t = texts[done + 1]
				if hangSignNear(K, cx, cz, 3.6, 1.0, yb, 0, t[1], t[2], B.main, WHITE, B.sub) then
					done += 1
				end
			end
		end
		for _, p in { V3(0, 0, -1), V3(-V.W * 0.25, 0, 0), V3(V.W * 0.25, 0, 0) } do
			if done < 2 then
				local t = texts[done + 1]
				if hangSignNear(K, (V.x0 + V.x1) / 2 + p.X, (V.z0 + V.z1) / 2 + p.Z, 3.6, 1.0, yb, 0, t[1], t[2], B.main, WHITE, B.sub) then
					done += 1
				end
			end
		end
	end)
	-- 벽 안내 · 포스터 · 사이니지
	step(K, "posters", function()
		local W0 = C(250, 250, 250)
		local P = {
			{ "Free Wi-Fi", (B.ssid or "STORE_WiFi_5G") .. "\n비밀번호 없음", W0, INK, B.main },
			{ "24시간 영업", "연중무휴 · 심야 결제는 카드 권장", W0, INK, B.dark },
			{ "택배 접수", B.parcel .. "\n접수 마감 매일 22:00", W0, INK, B.sub },
			{ B.pb, "가성비 PB 신상품 출시\n도시락 4,900원부터", B.main, WHITE, B.promo1 },
		}
		for _, p in shuffled(mkRng(V.key .. "pp"), {
			{ "CCTV 녹화중", "24시간 녹화 · 도난 방지", W0, INK, C(60, 60, 64) },
			{ "안전상비의약품", "해열진통제 · 소화제 · 파스\n24시간 판매 (1회 1통)", W0, INK, C(10, 138, 58) },
			{ "아이스크림 할인", "전 품목 상시 할인\n콘 · 바 · 튜브 2+1", W0, INK, B.promo1 },
			{ "분리배출 안내", "컵라면 국물은 국물통에\n용기 · 캔 · 페트 분리", W0, INK, C(40, 120, 90) },
			{ "카드 · 간편결제", "통신사 멤버십 할인\n제로페이 · 페이코 · 카카오페이", W0, INK, B.main },
		}) do
			if #P < 6 then
				table.insert(P, p)
			end
		end
		for i, p in P do
			local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 1.9, 4.4, 6.6, (i - 3) * 3)
			if wn and dcf then
				poster(K, dcf, 1.7, 2.0, p[1], p[2], p[3], p[4], p[5], WHITE, {})
			end
		end
	end)
	step(K, "goods", function()
		used += runFill(K, goodsBudget(K, V))
	end)
	-- 선반 날개 POP (NEW · 1+1 · 할인) 몇 개
	step(K, "wobblers", function()
		local wr = mkRng(V.key .. "wob")
		local n = 0
		local texts = { { "NEW", B.main }, { "1+1", B.promo1 }, { "할인", B.promo1 }, { B.pb, B.main } }
		K:free(function()
			for _, su in surfs do
				if n < 4 and not su.fridge and su.rail and su.level == 2 and wr() < 0.6 then
					n += 1
					local t = texts[(n - 1) % #texts + 1]
					wobbler(K, su, (wr() - 0.5) * (su.len - 1.2), t[1], t[2], WHITE)
				end
			end
		end)
	end)
	note(K, string.format("cvs %s goods parts=%d surfaces=%d", brand, used, #surfs))
end

---------------------------------------------------------------------------------------------------
-- 7. 소매 (올리브영 · 기념품 · 비치용품 · 꽃 · 서점)
---------------------------------------------------------------------------------------------------

-- 화장대 거울 (전구 둘레) + 조명 토글
local function vanityMirror(K: any, dcf: CFrame, w: number, h: number)
	K:plate("StVanityFrame", w + 0.4, h + 0.4, 0.08, dcf, lk(C(250, 250, 250)))
	K:plate("StVanityGlass", w, h, 0.02, dcf * CF(0, 0, 0.08), Look.mirror)
	local bulbs = {}
	local n = math.floor(w / 0.55)
	for i = 0, n do
		for _, sy in { -1, 1 } do
			table.insert(bulbs, K:ball("StVanityBulb", 0.2, dcf * CF(-w / 2 + i * w / n, sy * (h / 2 + 0.1), 0.14), Look.lampWarm))
		end
	end
	for j = 1, math.floor(h / 0.6) do
		for _, sx in { -1, 1 } do
			table.insert(bulbs, K:ball("StVanityBulb", 0.2, dcf * CF(sx * (w / 2 + 0.1), -h / 2 + j * h / (math.floor(h / 0.6) + 1), 0.14), Look.lampWarm))
		end
	end
	local glow = K:plate("StVanityGlow", 0.1, 0.1, 0.01, dcf * CF(0, h / 2 + 0.1, 0.2), Look.lampWarm)
	local l = K:light(glow, "PointLight", { Range = 7, Brightness = 0.6, Color = Look.warmLight })
	local pp = firstOk(K, bulbs)
	if not pp then
		note(K, "no prompt spot: vanity")
		return
	end
	Interact.toggle(K, pp, {
		object = "화장대 거울 조명",
		state = true,
		on = function(on: boolean)
			for _, b in bulbs do
				if b.Parent then
					b.Material = if on then M.Neon else M.SmoothPlastic
					b.Color = if on then C(255, 214, 160) else C(220, 220, 214)
				end
			end
			if glow.Parent then
				glow.Material = if on then M.Neon else M.SmoothPlastic
			end
			if l then
				l.Enabled = on
			end
		end,
	})
end

-- 회전 진열대 (엽서 · 립스틱 타워): 프롬프트로 돌림
local function spinRack(K: any, pcf: CFrame, kind: string, object: string)
	local parts: { BasePart } = {}
	local function keep(p: BasePart?)
		if p then
			table.insert(parts, p)
		end
	end
	K:disc("StSpinBase", 1.4, 0.08, pcf * CF(0, 0.04, 0), Look.chrome)
	local h = if kind == "postcard" then 5.2 else 4.6
	K:vcyl("StSpinPole", h, 0.12, pcf * CF(0, h / 2, 0), Look.chrome)
	local tiers = 5
	for t = 1, tiers do
		local y = 0.7 + (t - 1) * (h - 1.0) / tiers
		for f = 0, 3 do
			local a = f * PI / 2
			local fc = pcf * ANG(0, a, 0) * CF(0, y, 0.3)
			if kind == "postcard" then
				-- 철사 주머니 + 흰 테 엽서 (사진 = 하늘 · 바다 두 띠, 일부는 광안대교 실루엣 · 야경)
				keep(K:box("StSpinPocket", V3(0.62, 0.5, 0.05), fc * CF(0, 0.25, 0.14), { c = C(230, 236, 240), m = M.Glass, t = 0.55 }))
				local card = fc * CF(0, 0.4, 0.09) * ANG(-0.06, 0, 0)
				keep(K:box("StPostcard", V3(0.54, 0.7, 0.02), card, lk(C(250, 250, 246))))
				local ph = ({ { C(120, 190, 240), C(30, 90, 170) }, { C(250, 170, 90), C(60, 70, 120) }, { C(20, 26, 60), C(30, 40, 90) }, { C(150, 210, 240), C(230, 210, 160) }, { C(240, 120, 150), C(250, 220, 230) }, { C(90, 170, 120), C(40, 110, 170) } })[(t * 3 + f) % 6 + 1]
				keep(K:plate("StPostcardSky", 0.46, 0.34, 0.006, card * CF(0, 0.1, 0.01), lk(ph[1])))
				keep(K:plate("StPostcardSea", 0.46, 0.22, 0.006, card * CF(0, -0.18, 0.01), lk(ph[2])))
				if K.detail == "high" and (t + f) % 2 == 0 then
					keep(K:plate("StPostcardBridge", 0.44, 0.03, 0.008, card * CF(0, -0.06, 0.012), lk(if (t * 3 + f) % 6 == 2 then C(120, 220, 255) else C(40, 44, 52), if (t * 3 + f) % 6 == 2 then M.Neon else M.SmoothPlastic)))
				end
			else
				keep(K:box("StLipShelf", V3(0.7, 0.04, 0.3), fc * CF(0, 0, 0.1), lk(C(250, 250, 250))))
				for j = 0, 3 do
					local col = SKU.lip.cols[(t + j + f) % #SKU.lip.cols + 1]
					keep(K:vcyl("StLipTester", 0.3, 0.1, fc * CF(-0.24 + j * 0.16, 0.17, 0.12), lk(col)))
				end
			end
		end
	end
	if kind == "postcard" then
		keep(K:box("StSpinTop", V3(0.9, 0.5, 0.9), pcf * CF(0, h + 0.25, 0), lk(C(30, 80, 160))))
		for f = 0, 3 do
			local tp = txt(K, "StSpinTopText", 0.84, 0.36, pcf * ANG(0, f * PI / 2, 0) * CF(0, h + 0.25, 0.451), if f % 2 == 0 then "엽서 POSTCARD\n1장 1,500 · 3장 4,000" else "광안리 · 해운대\n부산 풍경 엽서", WHITE, C(30, 80, 160), { d = 0.01 })
			keep(tp)
		end
	end
	local center = (K.cf * pcf).Position
	local base = {}
	for _, p in parts do
		table.insert(base, { p = p, cf = p.CFrame })
	end
	local angle = 0
	local nv: NumberValue? = nil
	local pr = promptOn(K, parts, {
		action = "돌려 보기",
		object = object,
		sound = "rbxasset://sounds/clickfast.wav",
		fn = function()
			if not nv then
				local v = Instance.new("NumberValue")
				v.Name = "GwSpinAngle"
				v.Value = 0
				v.Parent = parts[1]
				v.Changed:Connect(function(a: number)
					local rot = CFrame.new(center) * CFrame.Angles(0, a, 0) * CFrame.new(-center)
					for _, b in base do
						if b.p.Parent then
							b.p.CFrame = rot * b.cf
						end
					end
				end)
				nv = v
			end
			angle += PI / 2
			TweenService:Create(nv :: NumberValue, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = angle }):Play()
		end,
	})
	return pr
end

-- 광안대교 LED 모형 (벽): 조명 쇼 순환
local function bridgeModel(K: any, dcf: CFrame, w: number)
	local h = w * 0.36
	K:plate("StBridgeBack", w + 0.3, h + 0.3, 0.06, dcf, lk(C(12, 20, 40)))
	-- 바다 · 하늘 · 마린시티 야경 실루엣
	K:plate("StBridgeSea", w, h * 0.28, 0.07, dcf * CF(0, -h * 0.36, 0), lk(C(20, 40, 80)))
	for i = 0, 6 do
		local tw = 0.32 + (i % 3) * 0.08
		local thh = h * (0.32 + ((i * 37) % 5) * 0.07)
		local tx = w * 0.18 + i * 0.36
		if tx + tw / 2 < w / 2 - 0.1 then
			K:plate("StSkyline", tw, thh, 0.065, dcf * CF(tx, -h * 0.22 + thh / 2, 0), lk(C(24, 30, 56)))
			if K.detail ~= "low" then
				K:plate("StSkylineLit", tw * 0.4, thh * 0.7, 0.068, dcf * CF(tx, -h * 0.22 + thh * 0.45, 0), Look.neon(C(255, 214, 140), 0.3))
			end
		end
	end
	local leds: { BasePart } = {}
	-- 상판 (2층 교량)
	local deckY = -h * 0.12
	K:plate("StBridgeDeck", w * 0.96, 0.1, 0.12, dcf * CF(0, deckY, 0), lk(C(200, 204, 210), M.Metal))
	K:plate("StBridgeDeck2", w * 0.96, 0.08, 0.12, dcf * CF(0, deckY - 0.2, 0), lk(C(180, 184, 190), M.Metal))
	table.insert(leds, K:plate("StBridgeDeckLED", w * 0.96, 0.04, 0.14, dcf * CF(0, deckY - 0.08, 0), Look.neon(C(70, 170, 255))))
	-- 주탑 2개 + 케이블 (현수교)
	local towers = { -w * 0.22, w * 0.22 }
	for _, tx in towers do
		K:plate("StBridgeTower", 0.12, h * 0.62, 0.14, dcf * CF(tx - 0.12, deckY + h * 0.2, 0), lk(C(220, 224, 228), M.Metal))
		K:plate("StBridgeTower", 0.12, h * 0.62, 0.14, dcf * CF(tx + 0.12, deckY + h * 0.2, 0), lk(C(220, 224, 228), M.Metal))
		table.insert(leds, K:plate("StBridgeTowerLED", 0.06, h * 0.58, 0.16, dcf * CF(tx, deckY + h * 0.2, 0), Look.neon(C(70, 170, 255))))
	end
	local topY = deckY + h * 0.5
	local pts = {}
	local N = if K.detail == "high" then 12 else 7
	for i = 0, N do
		local t = i / N
		local x = -w * 0.48 + t * w * 0.96
		local y: number
		if x < towers[1] then
			local k = (x - (-w * 0.48)) / (towers[1] + w * 0.48)
			y = deckY + 0.05 + (topY - deckY - 0.05) * k * k
		elseif x > towers[2] then
			local k = (w * 0.48 - x) / (w * 0.48 - towers[2])
			y = deckY + 0.05 + (topY - deckY - 0.05) * k * k
		else
			local k = (x - towers[1]) / (towers[2] - towers[1]) * 2 - 1
			y = deckY + 0.15 + (topY - deckY - 0.15) * k * k
		end
		table.insert(pts, (dcf * CF(x, y, 0.12)).Position)
	end
	for i = 1, #pts - 1 do
		local p = K:seg("StBridgeCableLED", pts[i], pts[i + 1], 0.06, Look.neon(C(70, 170, 255)))
		if p then
			table.insert(leds, p)
		end
	end
	txt(K, "StBridgeTitle", w * 0.5, 0.3, dcf * CF(0, h / 2 - 0.12, 0.07), "광안대교 GWANGAN BRIDGE", C(220, 230, 250), nil, { d = 0.005, glow = 1.2 })
	local schemes = {
		{ "기본 블루", function(_i: number, _n: number): Color3
			return C(70, 170, 255)
		end },
		{ "레인보우", function(i: number, n: number): Color3
			return Color3.fromHSV((i / n) % 1, 0.8, 1)
		end },
		{ "불꽃축제", function(i: number, _n: number): Color3
			return if i % 3 == 0 then C(255, 80, 60) elseif i % 3 == 1 then C(255, 200, 60) else C(255, 255, 255)
		end },
		{ "바다 웨이브", function(i: number, n: number): Color3
			return Color3.fromHSV(0.5 + 0.12 * math.sin(i / n * PI * 2), 0.7, 1)
		end },
	}
	local function apply(k: number)
		local f = schemes[k][2]
		for i, p in leds do
			if p.Parent then
				p.Color = f(i, #leds)
			end
		end
	end
	local pp = firstOk(K, leds)
	if not pp then
		note(K, "no prompt spot: bridge")
		return
	end
	Interact.cycle(K, pp, schemes, {
		action = "조명 쇼 바꾸기",
		object = "광안대교 LED 모형",
		on = function(i: number)
			apply(i)
		end,
	})
end

-- 티셔츠 (옷걸이에 걸린 것): pcf = 어깨선 가운데, +Z = 앞면. w 폭, h 길이
local function tshirt(K: any, cf: CFrame, w: number, h: number, col: Color3, print: string?, hi: boolean)
	local L = lk(col, M.Fabric)
	K:box("StShirtBody", V3(w, h, 0.07), cf * CF(0, -h / 2, 0), L)
	if hi then
		for _, sx in { -1, 1 } do
			K:box("StShirtSleeve", V3(w * 0.34, h * 0.3, 0.07), cf * CF(sx * (w / 2 + w * 0.1), -h * 0.14, 0) * ANG(0, 0, sx * 0.5), L)
		end
		K:box("StShirtCollar", V3(w * 0.3, 0.06, 0.08), cf * CF(0, -0.03, 0.005), lk(darker(col, 0.2), M.Fabric))
	end
	if print and hi then
		txt(K, "StShirtPrint", w * 0.7, h * 0.3, cf * CF(0, -h * 0.4, 0.036), print, if col.R + col.G + col.B > 2 then C(30, 60, 140) else WHITE, nil, { d = 0.005, font = Enum.Font.GothamBlack })
	end
end

-- 옷걸이 + 셔츠 (봉에 수직으로 걸림): rail 위 점 p, 셔츠 면 방향 n (봉 방향)
local function hangerShirt(K: any, p: Vector3, n: Vector3, col: Color3, hi: boolean, h: number)
	local cf = dcfAt(p - V3(0, 0.25, 0), n)
	K:seg("StHangerHook", p + V3(0, 0.08, 0), p - V3(0, 0.22, 0), 0.03, Look.chrome)
	K:box("StHanger", V3(1.3, 0.06, 0.05), cf * CF(0, 0, 0), lk(C(214, 186, 148), M.Wood))
	tshirt(K, cf * CF(0, -0.02, 0), 1.4, h, col, nil, hi)
end

-- 맵 옷걸이 봉 (Rail + RailPost) 의 Shirt 를 숨기고 다시 걸기
local function railShirts(K: any, V: any, cols: { Color3 }, rng: () -> number)
	local rail = V:first("Rail")
	if not rail then
		return
	end
	local shirts = V.byName.Shirt or {}
	local alongX = rail.size.X >= rail.size.Z
	local n = alongX and V3(1, 0, 0) or V3(0, 0, 1)
	local hi = K.detail ~= "low"
	K:free(function()
		for i, s in shirts do
			local p = if alongX then V3(s.c.X, rail.max.Y + 0.02, rail.c.Z) else V3(rail.c.X, rail.max.Y + 0.02, s.c.Z)
			local h = math.min(2.3, rail.max.Y - 1.2)
			-- 옷걸이마다 살짝 다른 각도 (자로 잰 듯한 판 줄 대신 걸린 옷처럼)
			local nj = CFrame.Angles(0, (rng() - 0.5) * 0.18, 0):VectorToWorldSpace(n)
			hangerShirt(K, p, nj, pick(rng, cols), hi and (i % 2 == 0 or K.detail == "high"), h * (0.94 + rng() * 0.08))
			Scan.hide(K.hidden, s.part)
		end
		-- 봉 끝 사이즈 표 · 가격
		local endp = if alongX then V3(rail.max.X + 0.02, rail.max.Y - 0.6, rail.c.Z) else V3(rail.c.X, rail.max.Y - 0.6, rail.max.Z + 0.02)
		txt(K, "StRailPrice", 0.9, 0.6, dcfAt(endp, n), "티셔츠\n15,000\n2장 25,000", INK, C(250, 250, 248), { d = 0.02, font = Enum.Font.GothamBold })
	end)
end

-- 진열 테이블 (맵 DisplayTable) 원목 리스킨 + 위 상품
local function displayTable(K: any, V: any, kind: string, rng: () -> number)
	for _, dt in V.byName.DisplayTable or {} do
		local mn, mx = dt.min, dt.max
		local top = mx.Y
		local cx, cz = dt.c.X, dt.c.Z
		local w, d = dt.size.X, dt.size.Z
		K:free(function()
			K:box("StDTTop", V3(w, 0.16, d), CF(cx, top - 0.08, cz), Look.oak)
			K:box("StDTApron", V3(w - 0.2, 0.36, d - 0.2), CF(cx, top - 0.34, cz), Look.walnut)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					K:box("StDTLeg", V3(0.18, top - 0.16, 0.18), CF(cx + sx * (w / 2 - 0.2), (top - 0.16) / 2, cz + sz * (d / 2 - 0.2)), Look.walnut)
				end
			end
			K:box("StDTShelf", V3(w - 0.3, 0.1, d - 0.3), CF(cx, 0.55, cz), Look.oak)
			-- 아래 칸: 박스 재고
			for i = 0, 2 do
				K:box("StDTStock", V3(1.4, 0.7, d - 0.6), CF(cx - w / 2 + 1.0 + i * (w - 2) / 2, 0.95, cz), Look.kraft)
			end
			-- 위 상품
			local alongX = w >= d
			if kind == "beach" then
				-- 튜브 (도넛) 쌓기 + 비치볼
				local tubeCols = { C(250, 120, 40), C(40, 160, 230), C(250, 210, 60), C(240, 80, 140), C(60, 200, 150) }
				for i = 0, 2 do
					local px = cx - w / 2 + 1.1 + i * 1.6
					for j = 0, 1 do
						local ring = CF(px, top + 0.14 + j * 0.27, cz - 0.3) * ANG(PI / 2, 0, 0)
						tubeRing(K, "StTube", ring, 0.48, 0.28, if K.detail == "high" then 12 else 7, lk(tubeCols[(i + j) % #tubeCols + 1], M.Plastic), K.detail == "high")
					end
				end
				for i = 0, 1 do
					K:ball("StBeachBall", 0.7, CF(cx + w / 2 - 1.0 - i * 0.8, top + 0.35, cz + 0.4), lk(({ C(250, 250, 250), C(250, 210, 60) })[i + 1], M.Plastic))
					K:ell("StBeachBallStripe", V3(0.72, 0.72, 0.2), CF(cx + w / 2 - 1.0 - i * 0.8, top + 0.35, cz + 0.4), lk(({ C(230, 40, 50), C(40, 120, 220) })[i + 1], M.Plastic))
				end
				txt(K, "StDTSign", 1.4, 0.5, dcfAt(V3(cx, top + 0.5, mx.Z + 0.01), V3(0, 0, 1)) * CF(0, -0.25 - 0.4, 0), "튜브 판매 12,000~", WHITE, C(30, 120, 200), { d = 0.02 })
			else
				-- 기념품: 어묵 선물세트 · 머그 · 스노우볼 · 갈매기 인형
				local surf = { cf = CFrame.fromMatrix(V3(cx, top, if alongX then mx.Z - 0.05 else cz), V3(1, 0, 0), Vector3.yAxis, V3(0, 0, 1)), len = w - 0.4, depth = d * 0.45, clear = 0.95, rail = false, level = 2, levels = 3 }
				fillSurf(K, surf, "tableGift", rng, {}, { back = false, facing = 1 })
				local surf2 = { cf = CFrame.fromMatrix(V3(cx, top, mn.Z + 0.05), V3(-1, 0, 0), Vector3.yAxis, V3(0, 0, -1)), len = w - 0.4, depth = d * 0.45, clear = 1.4, rail = false, level = 1, levels = 3 }
				fillSurf(K, surf2, "tableGift", rng, {}, { back = false, facing = 1 })
				txt(K, "StDTSign", 1.6, 0.6, dcfAt(V3(cx, top - 0.34, mx.Z + 0.01), V3(0, 0, 1)), "부산 기념 선물세트\n어묵 · 씨앗호떡 · 머그", WHITE, C(30, 80, 160), { d = 0.02 })
			end
		end)
		Scan.hide(K.hidden, dt.part)
		for _, f in V.byName.Float or {} do
			if f.c.X > mn.X - 0.3 and f.c.X < mx.X + 0.3 and f.c.Z > mn.Z - 0.3 and f.c.Z < mx.Z + 0.3 then
				Scan.hide(K.hidden, f.part)
			end
		end
		K:reserve(mn - V3(1.2, 0, 1.2), mx + V3(1.2, 0, 1.2), "front")
	end
end

-- 맵에 진열 테이블이 없는 기념품 가게 (빵 · 과자 선물 위주): 빈 바닥 가운데에 2단 원목 선물세트 테이블 하나
local function giftTable(K: any, V: any, rng: () -> number): boolean
	if V:has("DisplayTable") > 0 or V.W < 18 then
		return false
	end
	local w, d, h = 4.8, 2.4, 2.9
	local cands = {}
	local cz = (V.z0 + V.z1) / 2
	for gx = V.x0 + 4, V.x1 - 4, 1.0 do
		for _, dz in { -1.2, -0.8, -1.6, 0.8, 1.6, 2.4 } do
			table.insert(cands, V3(gx, 0, cz + dz))
		end
	end
	local px = V.x0 + V.W * 0.3
	table.sort(cands, function(a, b)
		return math.abs(a.X - px) + math.abs(a.Z - cz) < math.abs(b.X - px) + math.abs(b.Z - cz)
	end)
	local pcf = floorSpot(K, cands, V3(w, h, d), V3(0, 0, 1), 1.1, "gifttable")
	if not pcf then
		return false
	end
	local top = 2.75
	K:box("StGTTop", V3(w, 0.14, d), pcf * CF(0, top - 0.07, 0), Look.oak)
	K:box("StGTApron", V3(w - 0.2, 0.3, d - 0.2), pcf * CF(0, top - 0.29, 0), Look.walnut)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:box("StGTLeg", V3(0.18, top - 0.14, 0.18), pcf * CF(sx * (w / 2 - 0.2), (top - 0.14) / 2, sz * (d / 2 - 0.2)), Look.walnut)
		end
	end
	K:box("StGTShelf", V3(w - 0.3, 0.1, d - 0.3), pcf * CF(0, 0.5, 0), Look.oak)
	for i = 0, 2 do
		K:box("StGTStock", V3(1.3, 0.62, d - 0.6), pcf * CF(-w / 2 + 0.95 + i * (w - 1.9) / 2, 0.86, 0), Look.kraft)
		K:plate("StGTStockLabel", 0.7, 0.24, 0.01, pcf * CF(-w / 2 + 0.95 + i * (w - 1.9) / 2, 0.9, (d - 0.6) / 2), lk(C(250, 250, 248)))
	end
	-- 가운데 단 (계단식 진열): 뒤쪽이 높게
	K:box("StGTRiser", V3(w - 0.8, 0.5, 0.8), pcf * CF(0, top + 0.25, 0), Look.lightOak)
	K:free(function()
		local f1 = { cf = pcf * CF(0, top, d / 2 - 0.05), len = w - 0.4, depth = d / 2 - 0.5, clear = 1.4, rail = false, level = 2, levels = 3 }
		fillSurf(K, f1, "busan", rng, {}, { back = false, facing = 1 })
		local f2 = { cf = pcf * ANG(0, PI, 0) * CF(0, top, d / 2 - 0.05), len = w - 0.4, depth = d / 2 - 0.5, clear = 1.4, rail = false, level = 1, levels = 3 }
		fillSurf(K, f2, "busan", rng, {}, { back = false, facing = 1 })
		local f3 = { cf = pcf * CF(0, top + 0.5, 0.4), len = w - 1.0, depth = 0.7, clear = 1.0, rail = false, level = 3, levels = 3 }
		fillSurf(K, f3, "gift", rng, {}, { back = false, facing = 1 })
	end)
	txt(K, "StGTSign", 1.9, 0.62, pcf * CF(0, top - 0.3, d / 2 + 0.01), "부산 기념 선물세트\n12,000 ~ 35,000원", WHITE, C(30, 60, 120), { d = 0.02, font = Enum.Font.GothamBold })
	txt(K, "StGTPop", 1.0, 0.7, pcf * CF(w / 2 - 0.7, top + 1.15, 0.2), "BEST\n선물 1위", C(30, 60, 120), C(255, 214, 90), { d = 0.04, font = Enum.Font.GothamBlack })
	K:box("StGTPopStem", V3(0.06, 0.6, 0.06), pcf * CF(w / 2 - 0.7, top + 0.5, 0.18), Look.chrome)
	return true
end

-- 기념품 · 비치 벽 (맵 WallRack 앞면의 Goods 자리): 유공보드 + 걸이 상품 + 선반
local function goodsWall(K: any, V: any, kind: string, rng: () -> number)
	local wr = V:first("WallRack")
	local goods = V.byName.Goods or {}
	if not wr then
		return
	end
	local face = V3(0, 0, 1)
	if wr.size.X < wr.size.Z then
		face = V3(if wr.c.X < 0 then 1 else -1, 0, 0)
	end
	local fz = if math.abs(face.Z) > 0.5 then wr.max.Z else (if face.X > 0 then wr.max.X else wr.min.X)
	local hi = K.detail == "high"
	local sections = {}
	for _, g in goods do
		table.insert(sections, g)
		Scan.hide(K.hidden, g.part)
	end
	if #sections == 0 then
		table.insert(sections, { min = V3(wr.min.X + 0.5, 2.0, wr.min.Z), max = V3(wr.max.X - 0.5, wr.max.Y - 1.0, wr.max.Z), c = wr.c, size = wr.size })
	end
	table.sort(sections, function(a, b)
		return a.c.X < b.c.X
	end)
	K:free(function()
		for si, g in sections do
			local w = (if math.abs(face.Z) > 0.5 then g.size.X else g.size.Z) - 0.2
			local y0, y1 = math.max(1.4, g.min.Y - 0.6), math.min(wr.max.Y - 0.4, g.max.Y + 0.2)
			local p = if math.abs(face.Z) > 0.5 then V3(g.c.X, (y0 + y1) / 2, fz) else V3(fz, (y0 + y1) / 2, g.c.Z)
			local d = dcfAt(p, face)
			local h = y1 - y0
			local role = if kind == "beach" then ({ "rings", "wear", "shelves" })[(si - 1) % 3 + 1] else ({ "magnets", "shirts", "shelves" })[(si - 1) % 3 + 1]
			-- 바탕 보드
			K:plate("StPegBoard", w, h, 0.05, d, lk(if role == "magnets" then C(30, 60, 120) else C(236, 230, 218)))
			K:plate("StPegBoardTrim", w + 0.12, 0.1, 0.07, d * CF(0, h / 2, 0), Look.walnut)
			K:plate("StPegBoardTrim", w + 0.12, 0.1, 0.07, d * CF(0, -h / 2, 0), Look.walnut)
			local title = ({ magnets = "광안리 마그넷 · 키링", shirts = "BUSAN T-SHIRTS", shelves = if kind == "beach" then "선크림 · 물놀이 용품" else "부산 기념 선물", rings = "튜브 · 비치볼", wear = "래쉬가드 · 수영복" })[role]
			txt(K, "StGoodsTitle", w * 0.8, 0.5, d * CF(0, h / 2 + 0.42, 0.04), title, WHITE, if kind == "beach" then C(30, 120, 200) else C(30, 60, 120), { d = 0.04, font = Enum.Font.GothamBlack })
			if role == "magnets" then
				local cols = math.floor((w - 0.4) / (if hi then 0.42 else 0.6))
				local rows = math.floor((h - 0.6) / (if hi then 0.46 else 0.66))
				for i = 1, cols do
					for j = 1, rows do
						local x = -w / 2 + 0.2 + (i - 0.5) * (w - 0.4) / cols
						local y = -h / 2 + 0.3 + (j - 0.5) * (h - 0.6) / rows
						local r = rng()
						if j % 3 == 0 then
							-- 키링 (고리 + 작은 모형)
							K:seg("StKeyHook", (d * CF(x, y + 0.18, 0.05)).Position, (d * CF(x, y + 0.18, 0.3)).Position, 0.03, Look.chrome)
							K:box("StKeyring", V3(0.2, 0.26, 0.06), d * CF(x, y - 0.02, 0.26), lk(pick(rng, { C(250, 210, 60), C(240, 80, 120), C(60, 170, 220), C(250, 250, 250) })))
						else
							local col = pick(rng, { C(250, 250, 250), C(250, 210, 60), C(60, 170, 220), C(240, 120, 80), C(120, 200, 140), C(240, 160, 200) })
							K:plate("StMagnet", 0.34 + r * 0.06, 0.3, 0.05, d * CF(x, y, 0.05), lk(col))
							if hi and r < 0.4 then
								K:plate("StMagnetArt", 0.24, 0.08, 0.055, d * CF(x, y - 0.04, 0.05), lk(C(30, 80, 160)))
							end
						end
					end
				end
			elseif role == "shirts" or role == "wear" then
				local n = math.max(1, math.floor(w / 2.0))
				for i = 1, n do
					local x = -w / 2 + (i - 0.5) * w / n
					local col = pick(rng, if role == "wear" then { C(30, 60, 140), C(240, 80, 120), C(30, 30, 34), C(60, 180, 170) } else { C(250, 250, 250), C(30, 60, 140), C(240, 200, 60), C(240, 240, 236), C(200, 40, 50) })
					K:seg("StWallHook", (d * CF(x, h / 2 - 0.35, 0.05)).Position, (d * CF(x, h / 2 - 0.35, 0.3)).Position, 0.04, Look.chrome)
					K:box("StHanger", V3(1.3, 0.06, 0.05), d * CF(x, h / 2 - 0.55, 0.25), lk(C(214, 186, 148), M.Wood))
					tshirt(K, d * CF(x, h / 2 - 0.58, 0.27), 1.5, math.min(1.9, h - 2.8), col, if role == "shirts" then (if i % 2 == 0 then "I ♥ BUSAN" else "광안리\nGWANGALLI") else nil, K.detail ~= "low")
				end
				-- 아래 선반: 개어 놓은 티셔츠 · 래쉬가드 더미 + 가격
				if h > 3.6 then
					local y = -h / 2 + 0.75
					K:box("StGoodsShelf", V3(w - 0.1, 0.08, 0.8), d * CF(0, y, 0.4), Look.oak)
					for _, sx in { -1, 1 } do
						K:bar("StGoodsBracket", (d * CF(sx * (w / 2 - 0.4), y - 0.35, 0.03)).Position, (d * CF(sx * (w / 2 - 0.4), y - 0.04, 0.6)).Position, 0.05, 0.05, Look.blackMetal)
					end
					local ns = math.max(1, math.floor((w - 0.2) / 0.95))
					local fcols = if role == "wear" then { C(30, 60, 140), C(240, 80, 120), C(30, 30, 34), C(60, 180, 170), C(250, 160, 40) } else { C(250, 250, 250), C(30, 60, 140), C(240, 200, 60), C(200, 40, 50), C(120, 180, 220), C(40, 40, 44) }
					for k = 1, ns do
						local x = -w / 2 + 0.1 + (k - 0.5) * (w - 0.2) / ns
						local col = fcols[(k + si) % #fcols + 1]
						local sh = 0.5 + (k % 3) * 0.12
						K:box("StFoldedShirts", V3(0.82, sh, 0.66), d * CF(x, y + 0.04 + sh / 2, 0.42), lk(col, M.Fabric))
						if K.detail ~= "low" then
							for f = 1, 2 do
								K:plate("StFoldLine", 0.82, 0.03, 0.01, d * CF(x, y + 0.04 + sh * f / 3, 0.75), lk(darker(col, 0.25), M.Fabric))
							end
						end
					end
					txt(K, "StShirtPrice", 1.6, 0.3, d * CF(0, y - 0.25, 0.81), if role == "wear" then "래쉬가드 29,000 · 아동 19,000" else "티셔츠 15,000 · 2장 25,000", INK, C(250, 250, 248), { d = 0.01 })
				end
			elseif role == "rings" then
				local n = math.max(1, math.floor(w / 1.5))
				for i = 1, n do
					local x = -w / 2 + (i - 0.5) * w / n
					for j = 0, 1 do
						local y = h / 2 - 0.9 - j * 1.6
						if y > -h / 2 + 0.6 then
							K:seg("StWallHook", (d * CF(x, y + 0.6, 0.05)).Position, (d * CF(x, y + 0.6, 0.3)).Position, 0.04, Look.chrome)
							tubeRing(K, "StWallTube", d * CF(x, y, 0.3), 0.5, 0.3, if hi then 12 else 7, lk(pick(rng, { C(250, 120, 40), C(40, 160, 230), C(250, 210, 60), C(240, 80, 140), C(60, 200, 150) }), M.Plastic), hi)
						end
					end
				end
			else
				-- 선반 3단 + 상품
				local lv = 3
				for j = 1, lv do
					local y = -h / 2 + 0.2 + (j - 1) * (h - 0.4) / lv
					K:box("StGoodsShelf", V3(w - 0.1, 0.08, 0.8), d * CF(0, y, 0.4), Look.oak)
					for _, sx in { -1, 1 } do
						K:bar("StGoodsBracket", (d * CF(sx * (w / 2 - 0.4), y - 0.35, 0.03)).Position, (d * CF(sx * (w / 2 - 0.4), y - 0.04, 0.6)).Position, 0.05, 0.05, Look.blackMetal)
					end
					local scf = d * CF(0, y + 0.04, 0.8)
					local surf = { cf = CFrame.fromMatrix(scf.Position, scf.XVector, scf.YVector, scf.ZVector), len = w - 0.3, depth = 0.75, clear = (h - 0.4) / lv - 0.15, rail = false, level = j, levels = lv }
					queueFill(K, surf, if kind == "beach" then "beachgoods" else "gift", V.key .. "gw" .. si .. j, {}, { back = false })
				end
			end
		end
	end)
end

local function buildRetail(K: any, V: any, S: any, sub: string)
	local rng = mkRng(V.key .. sub)
	local surfs = mapSurfaces(V)
	local obst = obstacles(V)
	local used = 0
	for _, g in V.counters do
		reserveFront(K, g.min, g.max, counterFace(V, g), 2.6, 0.4)
	end
	for _, s in surfs do
		local r = s.rec
		local fwd = s.cf.ZVector
		reserveFront(K, r.min, r.max, V3(math.round(fwd.X), 0, math.round(fwd.Z)), 2.4, 0.2)
	end
	for _, nm in { "TesterTable", "Mirror", "WallRack", "Rail" } do
		for _, r in V.byName[nm] or {} do
			reserveFront(K, r.min, r.max, awayFromWall(V, r), 2.4, 0.4)
			if nm == "Rail" then
				K:reserve(r.min - V3(1.4, 0, 1.4), r.max + V3(1.4, 0, 1.4), "front")
			end
		end
	end
	for _, nm in { "Product" } do
		for _, r in V.byName[nm] or {} do
			Scan.hide(K.hidden, r.part)
		end
	end
	if sub == "cosmetics" then
		local theme = { promo1 = OY.sub, promo2 = OY.main, p11 = 0.12, p21 = 0.05, pSale = 0.12, saleText = "올영세일", promo3 = C(230, 40, 50), maxTagText = 34, prices = { "9,900", "12,900", "15,800", "18,000", "22,400", "24,900", "8,500", "31,000" } }
		-- 벽 칸: 구역(긴 판을 3~4 칸 세로 블록)마다 범주
		local wallCats = { "skincare", "makeup", "maskcare", "hairbody", "health" }
		local gondCats = { "makeup", "skincare", "maskcare", "hairbody" }
		local faceIdx = 0
		local faceCat: { [string]: any } = {}
		step(K, "shelves", function()
			K:free(function()
				for _, s in surfs do
					if s.len > 6 then
						-- 긴 벽 칸: 블록 단위로 쪼갬
						local nb = math.max(1, math.floor(s.len / 3.7 + 0.5))
						local bw = s.len / nb
						for bi = 1, nb do
							local key = s.face .. "#" .. bi
							if not faceCat[key] then
								faceIdx += 1
								faceCat[key] = wallCats[(faceIdx - 1) % #wallCats + 1]
							end
							local sub2 = { cf = s.cf * CF(-s.len / 2 + bw * (bi - 0.5), 0, 0), len = bw - 0.16, depth = s.depth, clear = s.clear, rail = s.rail, level = s.level, levels = s.levels }
							queueFill(K, sub2, faceCat[key], V.key .. key .. (s.level or 0), theme, { obst = obst, scale = 1.15, facing = 2 })
						end
					else
						if not faceCat[s.face] then
							faceIdx += 1
							faceCat[s.face] = gondCats[(faceIdx - 1) % #gondCats + 1]
						end
						queueFill(K, s, faceCat[s.face], V.key .. s.face .. (s.level or 0), theme, { obst = obst, scale = 1.15 })
					end
				end
			end)
		end)
		-- 벽 칸 머리 (맵 Header) 범주 글자
		step(K, "headers", function()
			local names = { "스킨케어 SKINCARE", "메이크업 MAKEUP", "마스크팩 · 선케어", "헤어 · 바디 HAIR & BODY", "건강식품 HEALTH" }
			for i, hd in V.byName.Header or {} do
				local face = if hd.size.X >= hd.size.Z then V3(0, 0, if hd.c.Z < 0 then 1 else -1) else V3(if hd.c.X < 0 then 1 else -1, 0, 0)
				local fpos = if math.abs(face.Z) > 0.5 then (if face.Z > 0 then hd.max.Z else hd.min.Z) else (if face.X > 0 then hd.max.X else hd.min.X)
				local p = if math.abs(face.Z) > 0.5 then V3(hd.c.X, hd.c.Y, fpos) else V3(fpos, hd.c.Y, hd.c.Z)
				local w = math.max(hd.size.X, hd.size.Z)
				K:free(function()
					K:plate("StHeaderSkin", w, hd.size.Y, 0.02, dcfAt(p, face), lk(OY.white))
					K:plate("StHeaderLine", w, 0.08, 0.03, dcfAt(p - V3(0, hd.size.Y / 2 - 0.04, 0), face), lk(OY.main))
					-- 뒤에서 불이 들어오는 흰 머리판 (검은 글자)
					txt(K, "StHeaderText", w - 0.1, hd.size.Y - 0.14, dcfAt(p + V3(0, 0.03, 0), face) * CF(0, 0, 0.02), names[(i - 1) % #names + 1], OY.dark, OY.white, { d = 0.006, glow = 1.0, font = Enum.Font.GothamBlack })
				end)
			end
			local promos = { { "올영세일", "최대 70% · 10.24 ~ 10.30" }, { "오늘의 특가", "오특 단 하루 특가" }, { "1+1", "선크림 · 마스크팩" }, { "NEW", "올리브영 단독 런칭" } }
			for i, ep in V.byName.EndPanel or {} do
				local thinX = ep.size.X < ep.size.Z
				local cen = nil
				for _, s in surfs do
					if overlapXZ(s.rec, ep, 0.6) then
						cen = s.rec.c
					end
				end
				local face = if thinX then V3(if cen and cen.X > ep.c.X then -1 else 1, 0, 0) else V3(0, 0, if cen and cen.Z > ep.c.Z then -1 else 1)
				local fpos = if thinX then (if face.X > 0 then ep.max.X else ep.min.X) else (if face.Z > 0 then ep.max.Z else ep.min.Z)
				local w = if thinX then ep.size.Z else ep.size.X
				local p = if thinX then V3(fpos, ep.size.Y * 0.52, ep.c.Z) else V3(ep.c.X, ep.size.Y * 0.52, fpos)
				local pr = promos[(i - 1) % #promos + 1]
				K:free(function()
					poster(K, dcfAt(p, face) * CF(0, 0, -0.05), w - 0.4, ep.size.Y - 1.0, pr[1], pr[2], OY.white, OY.dark, if i % 2 == 0 then OY.sub else OY.main, WHITE, { titleH = 0.4, frame = false })
				end)
				for _, eh in V.byName.EndHeader or {} do
					if overlapXZ(eh, ep, 0.05) then
						local hp = if thinX then V3((if face.X > 0 then eh.max.X else eh.min.X), eh.c.Y, eh.c.Z) else V3(eh.c.X, eh.c.Y, (if face.Z > 0 then eh.max.Z else eh.min.Z))
						K:free(function()
							txt(K, "StEndHeaderText", w - 0.2, eh.size.Y * 0.7, dcfAt(hp, face), "OLIVE YOUNG", WHITE, nil, { d = 0.015, font = Enum.Font.GothamBlack })
						end)
					end
				end
			end
		end)
		-- 테스터 테이블: 거울 위 조명 바 + 안내
		step(K, "tester", function()
			local mr = V:first("Mirror")
			if mr then
				Scan.hide(K.hidden, mr.part)
				local face = V3(0, 0, 1)
				local tt = V:first("TesterTable")
				if tt then
					face = if math.abs(mr.c.Z - tt.c.Z) > math.abs(mr.c.X - tt.c.X) then V3(0, 0, math.sign(tt.c.Z - mr.c.Z)) else V3(math.sign(tt.c.X - mr.c.X), 0, 0)
				end
				local fpos = if math.abs(face.Z) > 0.5 then (if face.Z > 0 then mr.max.Z else mr.min.Z) else (if face.X > 0 then mr.max.X else mr.min.X)
				local w = math.max(mr.size.X, mr.size.Z)
				local p = if math.abs(face.Z) > 0.5 then V3(mr.c.X, mr.max.Y + 0.2, fpos) else V3(fpos, mr.max.Y + 0.2, mr.c.Z)
				K:free(function()
					local mc = dcfAt(if math.abs(face.Z) > 0.5 then V3(mr.c.X, mr.c.Y, if face.Z > 0 then mr.min.Z else mr.max.Z) else V3(if face.X > 0 then mr.min.X else mr.max.X, mr.c.Y, mr.c.Z), face)
					local th = if math.abs(face.Z) > 0.5 then mr.size.Z else mr.size.X
					K:plate("StMirrorFrame", w, mr.size.Y, th * 0.6, mc, lk(C(250, 250, 250)))
					K:plate("StMirrorGlass", w - 0.16, mr.size.Y - 0.16, th + 0.01, mc, Look.mirror)
					K:plate("StMirrorLightBar", w, 0.24, 0.12, dcfAt(p, face), lk(C(250, 250, 250)))
					K:plate("StMirrorLight", w - 0.2, 0.08, 0.13, dcfAt(p - V3(0, 0.06, 0), face), Look.lampNeutral)
					txt(K, "StTesterSign", w * 0.7, 0.4, dcfAt(p + V3(0, 0.45, 0), face), "TESTER · 테스터는 자유롭게 사용해 보세요", OY.dark, OY.white, { d = 0.02 })
				end)
			end
		end)
		-- 계산대
		step(K, "cashier", function()
			for _, g in V.counters do
				cashierDress(K, V, g, OY, "cosmetics")
			end
		end)
		-- 빈 바닥: 아일랜드 진열대 (큰 매장)
		step(K, "did", function()
			local wn, dcf = wallItemSpot(K, { "right", "left", "back" }, 4.0, 4.8, 7.0, 0, function(d: CFrame): boolean
				return promptOk(K, d.Position)
			end)
			if wn and dcf then
				didScreen(K, dcf, 3.6, {
					{ text = "올영세일\n최대 70% OFF", c = OY.main },
					{ text = "NEW 선크림\n1+1 기획", c = C(250, 160, 40) },
					{ text = "오늘드림\n3시간 빠른 배송", c = OY.sub },
					{ text = "OLIVE YOUNG\n건강한 아름다움", c = C(40, 40, 40) },
				}, "뷰티 광고 화면")
			end
		end)
		step(K, "vanity", function()
			local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 3.4, 3.0, 6.6, 0, function(d: CFrame): boolean
				return promptOk(K, (d * CF(-1.3, 1.6, 0)).Position) or promptOk(K, (d * CF(1.3, 1.6, 0)).Position)
			end)
			if wn and dcf then
				vanityMirror(K, dcf * CF(0, 0, 0.04), 2.6, 3.0)
				-- 아래 선반 (화장대 상판)
				K:box("StVanityShelf", V3(3.0, 0.1, 0.8), dcf * CF(0, -1.85, 0.4), lk(C(250, 250, 250)))
				local scf = dcf * CF(0, -1.8, 0.8)
				fillSurf(K, { cf = scf, len = 2.8, depth = 0.7, clear = 0.8, rail = false, level = 2, levels = 3 }, "makeup", mkRng(V.key .. "van"), theme, { back = false })
			end
		end)
		step(K, "islands", function()
			local cands = {}
			local cx0 = (V.x0 + V.x1) / 2
			for gx = V.x0 + 4, V.x1 - 4, 2.0 do
				for gz = V.z0 + 5, V.z1 - 5, 2.0 do
					table.insert(cands, V3(gx, 0, gz))
				end
			end
			table.sort(cands, function(a, b)
				return math.abs(a.X - cx0) > math.abs(b.X - cx0)
			end)
			local cats = { "makeup", "maskcare", "skincare", "health" }
			local n = 0
			local maxN = math.clamp(math.floor(V.W * V.D / 220), 0, 4)
			for _, p in cands do
				if n >= maxN then
					break
				end
				yieldy(K)
				local len, w, h = 6.4, 2.6, 4.2
				local pcf = pcfAt(V3(p.X, 0, p.Z), V3(1, 0, 0)) -- 긴 방향 = Z 축 (앞쪽 = +X)
				local cf2 = CFrame.fromMatrix(pcf.Position, V3(0, 0, 1), Vector3.yAxis, V3(-1, 0, 0))
				local mn, mx = canPlace(K, cf2, V3(len, h + 0.6, w), 2.4)
				if mn and mx then
					local mn2, mx2 = K.laabb(cf2 * CF(0, (h + 0.6) / 2, 0), V3(len, h + 0.6, w))
					K:reserve(mn2, mx2, "island")
					n += 1
					local us = island(K, cf2, len, w, h, { levels = 3, topL = lk(OY.white), kick = lk(C(60, 64, 60)) })
					K:free(function()
						for _, s in us do
							queueFill(K, s, cats[(n - 1) % #cats + 1], V.key .. "is" .. n .. s.level .. s.side, theme, { scale = 1.15 })
						end
						-- 끝판 POP
						for _, sx in { -1, 1 } do
							local d = cf2 * CF(sx * (len / 2), h * 0.55, 0) * ANG(0, sx * PI / 2, 0)
							poster(K, d, w - 0.4, h - 1.6, if n % 2 == 0 then "1+1" else "올영픽", if n % 2 == 0 then "마스크팩 · 선케어" else "이번 주 추천 아이템", OY.white, OY.dark, if sx > 0 then OY.main else OY.sub, WHITE, { titleH = 0.4, frame = false, off = 0.02 })
						end
					end)
				end
			end
		end)
		step(K, "baskets", function()
			local d = V.door
			local cands = {}
			if d then
				for _, dx in { 5.4, -5.4, 6.6, -6.6 } do
					table.insert(cands, V3(d.x + dx, 0, V.z1 - 3.0))
				end
			end
			local pcf = floorSpot(K, cands, V3(1.5, 2.2, 1.1), V3(0, 0, 1), 0.05, "basket")
			if pcf then
				basketStack(K, pcf, OY.dark, 6, "OLIVE YOUNG")
			end
		end)
		-- 창가 낮은 행사 테이블 (올영세일 · 오특)
		step(K, "promoTables", function()
			local cands = {}
			for gx = V.x0 + 3, V.x1 - 3, 1.0 do
				table.insert(cands, V3(gx, 0, V.z1 - 3.2))
				table.insert(cands, V3(gx, 0, V.z1 - 4.4))
			end
			table.sort(cands, function(a, b)
				return math.abs(a.X) > math.abs(b.X)
			end)
			local n = 0
			local maxN = if V.W > 36 then 3 elseif V.W > 24 then 2 else 1
			local pops = { { "오특", "오늘의 특가 단 하루", OY.sub }, { "1+1", "선크림 · 립밤 기획", OY.main }, { "NEW", "이달의 신상 뷰티", OY.dark } }
			for _, p in cands do
				if n >= maxN then
					break
				end
				yieldy(K)
				local pcf = pcfAt(V3(p.X, 0, p.Z), V3(0, 0, 1))
				local mn, mx = canPlace(K, pcf, V3(3.4, 3.3, 2.0), 1.2)
				if mn and mx then
					local mn2, mx2 = K.laabb(pcf * CF(0, 1.65, 0), V3(3.4 + 1.2, 3.3, 2.0 + 1.2))
					K:reserve(mn2, mx2, "promo")
					n += 1
					local pp = pops[(n - 1) % #pops + 1]
					local us = promoTable(K, pcf, 3.4, 2.0, lk(OY.white), pp[1], pp[2], pp[3])
					for _, su in us do
						queueFill(K, su, if n % 2 == 0 then "skincare" else "makeup", V.key .. "pt" .. n .. su.level, theme, { back = false, scale = 1.1, noTags = true })
					end
				end
			end
		end)
		-- 옆벽 진열장 (더마 · 헤어바디 · 건강식품 · 마스크팩)
		step(K, "sidewalls", function()
			local cats = { { "dermo", "더마 · 선케어 DERMA" }, { "hairbody", "헤어 · 바디 · 향수" }, { "health", "건강식품 · 이너뷰티" }, { "maskcare", "마스크팩 MASK" } }
			local placed = 0
			local hU = math.min(5.4, V.H - 2.4)
			for _, cc in cats do
				for _, len in { 7.2, 5.6, 4.4 } do
					local wn, pcf = wallFloorSpot(K, { "left", "right" }, len, 1.3, hU + 0.7, nil, 0, "wallunit")
					if wn and pcf then
						local us = wallUnit(K, pcf, len, 1.3, hU, { title = cc[2], body = lk(OY.white), back = lk(C(244, 244, 240)), headL = lk(OY.white), titleFg = OY.dark, lineL = lk(OY.main), levels = 5, kick = lk(C(60, 64, 60)) })
						for _, su in us do
							queueFill(K, su, cc[1], V.key .. cc[1] .. su.level, theme, { scale = 1.15 })
						end
						placed += 1
						break
					end
				end
			end
			note(K, "olive side units " .. placed)
		end)
		-- 벽 칸 브랜드 띠 (구역마다 실제 브랜드 이름)
		step(K, "brands", function()
			local BR = { "라운드랩", "토리든", "아누아", "닥터지", "메디힐", "라로슈포제", "에스트라", "롬앤", "클리오", "페리페라", "웨이크메이크", "어뮤즈", "마녀공장", "스킨1004", "구달", "닥터포헤어", "일리윤", "바이오더마" }
			local bi0 = 0
			for _, s in surfs do
				if s.len > 6 and s.level and s.levels and s.level == s.levels then
					local nb = math.max(1, math.floor(s.len / 3.7 + 0.5))
					local bw = s.len / nb
					for bi = 1, nb do
						bi0 += 1
						local cf = s.cf * CF(-s.len / 2 + bw * (bi - 0.5), math.min(s.clear - 0.22, 1.1), -s.depth + 0.12)
						K:free(function()
							txt(K, "StBrandStrip", bw - 0.5, 0.32, cf, BR[(hashStr(V.key) + bi0) % #BR + 1], WHITE, if bi0 % 3 == 0 then OY.main else OY.dark, { d = 0.03, font = Enum.Font.GothamBlack })
						end)
					end
				end
			end
		end)
		fixturesNow(K, V, S)
		step(K, "hang", function()
			local done = 0
			for _, x in { -0.3, 0.3, 0, -0.15, 0.15 } do
				if done >= 3 then
					break
				end
				if hangSignNear(K, V.W * x, (V.z0 + V.z1) / 2 - 1.5, 4.4, 1.1, math.max(6.4, V.H - 2.8), 0, if done == 1 then "오늘의 특가 오특" else "올영세일 최대 70%", "OLIVE YOUNG · 건강한 아름다움", if done == 1 then OY.sub else OY.main, WHITE, OY.white) then
					done += 1
				end
			end
		end)
		step(K, "posters", function()
			local P = {
				{ "올영세일", "10.24 - 10.30\n최대 70% 할인", OY.white, OY.dark, OY.main },
				{ "CJ ONE", "결제 시 포인트 적립\n앱 쿠폰 사용 가능", OY.white, OY.dark, OY.dark },
				{ "오늘드림", "주문 후 3시간 내 배송\n광안리점 픽업 가능", OY.white, OY.dark, OY.sub },
				{ "TAX FREE", "외국인 즉시 환급\nInstant Tax Refund", OY.white, OY.dark, C(30, 80, 160) },
			}
			for i, p in P do
				local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 2.0, 4.6, 7.0, (i - 2) * 4)
				if wn and dcf then
					poster(K, dcf, 1.8, 2.2, p[1], p[2], p[3], p[4], p[5], WHITE, {})
				end
			end
		end)
	elseif sub == "souvenir" or sub == "beach" then
		local beach = sub == "beach"
		local accent = if beach then C(30, 120, 200) else C(30, 60, 120)
		local warm = if beach then C(250, 160, 40) else C(200, 40, 40)
		step(K, "goodswall", function()
			goodsWall(K, V, sub, rng)
		end)
		-- 빵 선반 (I AM BUSAN 같은 부산 먹거리 기념품 가게): 맵 Bread 숨기고 선물세트 · 빵 · 호떡 믹스로
		step(K, "breadshelf", function()
			if V:has("BreadShelf") > 0 then
				for _, r in V.byName.Bread or {} do
					Scan.hide(K.hidden, r.part)
				end
				for _, su in surfs do
					if su.rec.name == "BreadShelf" then
						local nb = math.max(1, math.floor(su.len / 4 + 0.5))
						local bw = su.len / nb
						for bi = 1, nb do
							local sub2 = { cf = su.cf * CF(-su.len / 2 + bw * (bi - 0.5), 0, 0), len = bw - 0.2, depth = su.depth, clear = su.clear, rail = false, level = su.level, levels = su.levels }
							queueFill(K, sub2, if bi % 3 == 0 then "gift" else "busan", V.key .. "bs" .. bi .. (su.level or 0), {}, { obst = obst })
						end
					end
				end
			end
		end)
		step(K, "rail", function()
			railShirts(K, V, if beach then { C(30, 60, 140), C(240, 80, 120), C(30, 30, 34), C(60, 180, 170), C(250, 160, 40) } else { C(250, 250, 250), C(30, 60, 140), C(240, 200, 60), C(240, 240, 236), C(200, 40, 50), C(120, 180, 220) }, rng)
			-- 봉 리스킨 (크롬)
			for _, nm in { "Rail", "RailPost" } do
				for _, r in V.byName[nm] or {} do
					K:free(function()
						if r.size.Y > r.size.X and r.size.Y > r.size.Z then
							K:vcyl("StRailPost", r.size.Y, math.max(r.size.X, r.size.Z) * 0.9, CF(r.c), Look.chrome)
							K:disc("StRailFoot", 0.9, 0.06, CF(r.c.X, 0.03, r.c.Z), Look.chrome)
						else
							K:cyl("StRailBar", math.max(r.size.X, r.size.Z), math.min(r.size.Y, 0.16), CF(r.c) * (if r.size.X >= r.size.Z then CFrame.new() else ANG(0, PI / 2, 0)), Look.chrome)
						end
					end)
					Scan.hide(K.hidden, r.part)
				end
			end
		end)
		step(K, "table", function()
			displayTable(K, V, sub, rng)
			if not beach and giftTable(K, V, rng) then
				note(K, "gift table")
			end
		end)
		step(K, "cashier", function()
			for _, g in V.counters do
				cashierDress(K, V, g, { main = accent }, "retail")
			end
		end)
		step(K, "hang", function()
			local t1 = if beach then "BEACH SHOP · 튜브 대여" else "BUSAN SOUVENIR · 부산 기념품"
			local t2 = if beach then "선크림 · 돗자리 · 비치타월" else "I ♥ BUSAN · 광안리"
			hangSignNear(K, (V.x0 + V.x1) / 2 - V.W * 0.2, (V.z0 + V.z1) / 2, 4.6, 1.1, math.max(6.2, V.H - 2.8), 0, t1, t2, accent, WHITE, warm)
		end)
		if beach then
			-- 대여 요금판 · 파라솔 통 · 선풍기
			step(K, "fan", function()
				local wn, pcf = wallFloorSpot(K, { "back", "left", "right" }, 1.4, 1.4, 4.6, V3((V.x0 + V.x1) / 2, 0, V.z0), 0.1, "fan", function(c: CFrame): boolean
					return promptOk(K, c.Position)
				end)
				if wn and pcf then
					local fcf = pcf * ANG(0, 0, 0)
					K:disc("StFanBase", 1.2, 0.12, fcf * CF(0, 0.06, 0), lk(C(240, 240, 240), M.Plastic))
					K:vcyl("StFanPole", 3.0, 0.14, fcf * CF(0, 1.6, 0), lk(C(240, 240, 240), M.Plastic))
					local head = fcf * CF(0, 3.5, 0.1)
					K:ell("StFanMotor", V3(0.5, 0.5, 0.6), head * CF(0, 0, -0.25), lk(C(240, 240, 240), M.Plastic))
					K:ring("StFanGuard", head * CF(0, 0, 0.12), 0.85, 0.05, 12, lk(C(220, 220, 224), M.Metal))
					local blades = {}
					for i = 0, 2 do
						local a = i * 2 * PI / 3
						table.insert(blades, K:ell("StFanBlade", V3(0.36, 0.7, 0.04), head * CF(0, 0, 0.1) * ANG(0, 0, a) * CF(0, 0.38, 0), { c = C(120, 190, 240), m = M.Plastic, t = 0.2 }))
					end
					local blur = K:disc("StFanBlur", 1.6, 0.02, head * CF(0, 0, 0.1) * ANG(PI / 2, 0, 0), { c = C(140, 200, 240), m = M.Glass, t = 1 })
					local hub = K:ball("StFanHub", 0.22, head * CF(0, 0, 0.14), lk(C(240, 240, 240), M.Plastic))
					local on = false
					local fp = firstOk(K, { hub, blur })
					if fp then Interact.toggle(K, fp, {
						object = "선풍기",
						state = false,
						onText = "끄기",
						offText = "켜기",
						on = function(st: boolean)
							on = st
							for _, b in blades do
								if b.Parent then
									b.Transparency = if st then 1 else 0.2
								end
							end
							if blur.Parent then
								blur.Transparency = if st then 0.55 else 1
							end
						end,
					}) end
					local _ = on
				end
			end)
			step(K, "rental", function()
				local wn, dcf = wallItemSpot(K, { "left", "right" }, 3.4, 3.6, 7.6, 0)
				if wn and dcf then
					local d0 = dcf * CF(0, 0, 0.06)
					K:plate("StRentFrame", 3.4, 4.0, 0.06, d0, Look.walnut)
					K:plate("StRentBoard", 3.2, 3.8, 0.07, d0, lk(C(250, 250, 246)))
					K:plate("StRentBand", 3.2, 0.7, 0.08, d0 * CF(0, 1.55, 0), lk(accent))
					txt(K, "StRentTitle", 3.0, 0.56, d0 * CF(0, 1.55, 0.081), "대여 요금 RENTAL", WHITE, nil, { font = Enum.Font.GothamBlack })
					local rows = { { "튜브 (1일)", "10,000" }, { "파라솔 (1일)", "15,000" }, { "비치베드", "20,000" }, { "구명조끼", "5,000" }, { "돗자리", "5,000" }, { "보증금 · 신분증 필수", "10,000" } }
					for i, r in rows do
						local y = 1.0 - i * 0.48
						txt(K, "StRentItem", 1.9, 0.36, d0 * CF(-0.55, y, 0.072), r[1], INK, nil, { align = "Left", font = Enum.Font.GothamBold })
						txt(K, "StRentPrice", 1.0, 0.36, d0 * CF(1.0, y, 0.072), r[2], warm, nil, { align = "Right", font = Enum.Font.GothamBlack })
						K:plate("StRentRule", 2.9, 0.02, 0.071, d0 * CF(0, y - 0.24, 0), lk(C(214, 214, 210)))
					end
				end
			end)
			-- 천장에 매단 튜브 (해변 가게 상징): 옷걸이 봉 · 진열 테이블 위
			step(K, "ceilTubes", function()
				local cols = { C(250, 120, 40), C(40, 160, 230), C(250, 210, 60), C(240, 80, 140), C(60, 200, 150), C(250, 250, 250) }
				local lines = {}
				local rl = V:first("Rail")
				if rl then
					table.insert(lines, { rl.min.X + 0.6, rl.max.X - 0.6, rl.c.Z })
				end
				local dt = V:first("DisplayTable")
				if dt then
					table.insert(lines, { dt.min.X + 0.6, dt.max.X - 0.6, dt.c.Z })
				end
				local n = 0
				for _, ln in lines do
					local cnt = math.max(1, math.floor((ln[2] - ln[1]) / 1.6))
					for i = 0, cnt do
						local x = ln[1] + (ln[2] - ln[1]) * i / math.max(1, cnt)
						local y = V.H - 2.0 - (i % 2) * 0.35
						local ring = CF(x, y, ln[3]) * ANG(0, (i % 3) * 0.5, 0)
						local mn, mx = K.laabb(ring, V3(1.8, 1.8, 1.8))
						local nearSign = false
						for _, sb in K.stSignBoxes or {} do
							if K.overlap(mn - V3(0.6, 0, 0.6), mx + V3(0.6, 0, 0.6), sb.min, sb.max, 0) then
								nearSign = true
							end
						end
						if not nearSign and not K:hitsKeep(mn, V3(mx.X, V.H, mx.Z)) and not mapBlocked(K, mn, mx) then
							tubeRing(K, "StCeilTube", ring, 0.68, 0.4, if K.detail == "high" then 12 else 8, lk(cols[(n % #cols) + 1], M.Plastic), K.detail ~= "low")
							K:seg("StCeilTubeString", V3(x, y + 0.88, ln[3]), V3(x, V.H - 0.02, ln[3]), 0.025, lk(C(240, 240, 240)))
							n += 1
						end
					end
				end
			end)
			step(K, "mats", function()
				local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.5, 1.2, 4.4, nil, 0.1, "mats")
				if wn and pcf then
					K:box("StMatBin", V3(1.4, 1.4, 1.1), pcf * CF(0, 0.7, 0), lk(C(196, 156, 100), M.Fabric))
					K:box("StMatBinRim", V3(1.46, 0.1, 1.16), pcf * CF(0, 1.42, 0), lk(C(150, 110, 70), M.Fabric))
					local cols = { C(40, 120, 200), C(250, 120, 40), C(60, 180, 160), C(240, 80, 120), C(250, 210, 60), C(120, 80, 200) }
					for i = 0, 5 do
						local x = -0.42 + (i % 3) * 0.42
						local z = -0.2 + math.floor(i / 3) * 0.4
						local h = 3.2 + (i % 2) * 0.3
						K:vcyl("StMatRoll", h, 0.36, pcf * CF(x, 0.3 + h / 2, z) * ANG(0.04 * (i - 2), 0, 0.03 * (i - 3)), lk(cols[i + 1], M.Fabric))
						K:vcyl("StMatStrap", 0.08, 0.38, pcf * CF(x, 0.3 + h * 0.7, z), lk(C(30, 30, 30), M.Fabric))
					end
					txt(K, "StMatTag", 1.2, 0.4, pcf * CF(0, 0.9, 0.555), "돗자리 5,000 · 2개 9,000", WHITE, C(40, 120, 200), { d = 0.01 })
				end
			end)
			step(K, "parasols", function()
				local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.6, 1.6, 6.0, nil, 0.1, "parasol")
				if wn and pcf then
					K:vcyl("StParasolBin", 1.6, 1.3, pcf * CF(0, 0.8, 0), lk(C(40, 120, 200), M.Plastic))
					K:vcyl("StParasolBinRim", 0.1, 1.36, pcf * CF(0, 1.62, 0), lk(C(250, 250, 250), M.Plastic))
					local cols = { C(250, 120, 40), C(40, 160, 230), C(250, 210, 60), C(240, 80, 140), C(250, 250, 250) }
					for i = 0, 4 do
						local a = i * 2 * PI / 5
						local base = pcf * CF(math.cos(a) * 0.3, 0.3, math.sin(a) * 0.3)
						local top = base * CF(math.cos(a) * 0.25, 5.2, math.sin(a) * 0.25)
						K:seg("StParasolPole", base.Position, top.Position, 0.06, lk(C(250, 250, 250)))
						-- 접힌 천 (길쭉한 타원체)
						local mid = (base.Position + top.Position) / 2 + V3(0, 1.0, 0)
						K:ell("StParasolCloth", V3(0.34, 3.0, 0.34), CF(mid) * ANG(math.sin(a) * 0.05, 0, -math.cos(a) * 0.05), lk(cols[i + 1], M.Fabric))
					end
					txt(K, "StParasolTag", 1.0, 0.4, pcf * CF(0, 1.0, 0.66), "파라솔 대여", WHITE, nil, { d = 0.01 })
				end
			end)
		else
			step(K, "bridge", function()
				local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 5.6, 5.0, 7.6, 0, function(d: CFrame): boolean
					return frontClear(K, d, 5.6, 2.6, 2.0) and (promptOk(K, (d * CF(-2.0, 0, 0)).Position) or promptOk(K, (d * CF(2.0, 0, 0)).Position) or promptOk(K, d.Position))
				end)
				if wn and dcf then
					bridgeModel(K, dcf * CF(0, 0, 0.04), 5.2)
					-- 모형 앞은 비워 둠 (회전 진열대 등이 가리지 않게)
					local fmn, fmx = K.laabb(dcf * CF(0, 0, 0.9), V3(5.6, 0.1, 1.8))
					K:reserve(V3(fmn.X, 0, fmn.Z), V3(fmx.X, 7.6, fmx.Z), "wallfront")
				end
			end)
			step(K, "spinner", function()
				local cands = {}
				for gx = V.x0 + 1.6, V.x1 - 1.6, 0.5 do
					for gz = V.z0 + 2, V.z1 - 2.5, 0.5 do
						table.insert(cands, V3(gx, 0, gz))
					end
				end
				table.sort(cands, function(a, b)
					return math.abs(a.X) > math.abs(b.X)
				end)
				local pcf = floorSpot(K, cands, V3(1.6, 5.8, 1.6), V3(0, 0, 1), 0.4, "spinner", function(p: Vector3): boolean
					return promptOk(K, V3(p.X, 3, p.Z + 0.6))
				end)
				if pcf then
					spinRack(K, pcf, "postcard", "엽서 회전 진열대")
				end
			end)
		end
		-- 여행 · 바다 정보 화면 (서버 앵커에서 먼 벽)
		step(K, "infoScreen", function()
			local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 3.2, 5.0, 7.0, -3, function(d: CFrame): boolean
				return promptOk(K, d.Position)
			end)
			if wn and dcf then
				if beach then
					didScreen(K, dcf * CF(0, 0, 0.04), 2.8, {
						{ text = "오늘의 광안리 바다\n수온 22°C · 파고 0.5m", c = C(30, 120, 200) },
						{ text = "자외선 지수 높음\n선크림 2시간마다", c = C(240, 140, 30) },
						{ text = "해파리 주의보\n쏘이면 바닷물로 씻기", c = C(200, 60, 80) },
						{ text = "튜브 대여 1일 10,000\n18:00 까지 반납", c = C(40, 150, 120) },
					}, "바다 정보 화면")
				else
					didScreen(K, dcf * CF(0, 0, 0.04), 2.8, {
						{ text = "광안리 M 드론 라이트쇼\n매주 토요일 20:00", c = C(40, 50, 120) },
						{ text = "부산 시티투어\n광안대교 야경 코스", c = C(30, 110, 170) },
						{ text = "해운대 블루라인파크\n해변열차 · 스카이캡슐", c = C(20, 130, 140) },
						{ text = "TAX FREE · 외국인 환급\nInstant Refund", c = C(170, 40, 50) },
					}, "부산 여행 정보 화면")
				end
			end
		end)
		fixturesNow(K, V, S)
		step(K, "posters", function()
			local P = if beach
				then { { "주의 안내", "수영 가능 시간 09:00 - 18:00\n음주 수영 금지 · 안전요원 지시", C(250, 250, 246), INK, warm }, { "TAX FREE", "카드 · 간편결제 OK", C(250, 250, 246), INK, accent }, { "광안리 해수욕장", "개장 7.1 - 8.31\n튜브는 안전구역 안에서", C(250, 250, 246), INK, C(60, 170, 150) }, { "폭죽 사용 금지", "광안리 백사장 · 해변로 전역\n적발 시 과태료 부과", C(250, 250, 246), INK, C(200, 40, 40) } }
				else { { "부산 여행 기념", "광안대교 · 해운대 · 감천마을\n엽서 1,500 · 마그넷 5,000", C(250, 250, 246), INK, accent }, { "TAX FREE", "외국인 즉시 환급\n카드 · 간편결제 OK", C(250, 250, 246), INK, warm }, { "포장 서비스", "선물 포장 무료\n쇼핑백 100원", C(250, 250, 246), INK, C(60, 140, 90) } }
			for i, p in P do
				local wn, dcf = wallItemSpot(K, { "left", "right" }, 2.0, 4.2, 6.6, (i - 2) * 3)
				if wn and dcf then
					poster(K, dcf, 1.8, 2.2, p[1], p[2], p[3], p[4], p[5], WHITE, {})
				end
			end
		end)
	else
		-- 꽃집 · 서점 · 일반 소매: 맵 선반만 채우고 벽 진열 + 포스터
		local cat = if sub == "book" then "books" elseif sub == "flower" then "gift" else "gift"
		step(K, "shelves", function()
			K:free(function()
				for _, s in surfs do
					queueFill(K, s, cat, V.key .. s.face .. (s.level or 0), {}, { obst = obst })
				end
			end)
		end)
		step(K, "wallunits", function()
			for i = 1, 2 do
				local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 5.0, 1.3, math.min(6.2, V.H - 1.6), nil, 0, "wallunit")
				if wn and pcf then
					local us = wallUnit(K, pcf, 5.0, 1.3, math.min(5.6, V.H - 2.2), { title = if sub == "book" then "베스트셀러 · 신간" else "추천 상품", body = Look.oak, back = Look.lightOak, shelf = Look.oak, headL = lk(C(40, 40, 44)), titleFg = WHITE, levels = 5 })
					K:free(function()
						for _, s in us do
							queueFill(K, s, cat, V.key .. "wu" .. i .. s.level, {}, {})
						end
					end)
				end
			end
		end)
		step(K, "cashier", function()
			for _, g in V.counters do
				cashierDress(K, V, g, { main = C(40, 40, 44) }, "retail")
			end
		end)
	end
	step(K, "goods", function()
		used += runFill(K, goodsBudget(K, V, if sub == "cosmetics" then 1.1 else 1))
	end)
	note(K, string.format("retail %s goods parts=%d surfaces=%d", sub, used, #surfs))
end

---------------------------------------------------------------------------------------------------
-- 8. 약국
---------------------------------------------------------------------------------------------------

-- 자동 혈압계 코너 (본체 + 팔걸이 커프 + 화면 + 스툴) : 측정 상호작용
local function bpCorner(K: any, pcf: CFrame)
	K:box("StBPBase", V3(1.4, 0.3, 1.5), pcf * CF(0, 0.15, 0), lk(C(240, 240, 240)))
	K:rbox("StBPBody", V3(1.3, 3.0, 1.1), 0.1, pcf * CF(0, 1.8, -0.15), lk(C(246, 246, 244)))
	K:box("StBPArm", V3(0.8, 0.5, 1.1), pcf * CF(0, 3.05, 0.25), lk(C(70, 120, 180)))
	K:cyl("StBPCuff", 0.9, 0.5, pcf * CF(0, 3.25, 0.3) * ANG(0, PI / 2, 0), lk(C(40, 60, 100), M.Fabric))
	K:plate("StBPBezel", 0.9, 0.6, 0.02, pcf * CF(0, 3.9, 0.4) * ANG(-0.25, 0, 0), Look.black)
	local scr, label = txt(K, "StBPReading", 0.8, 0.5, pcf * CF(0, 3.9, 0.42) * ANG(-0.25, 0, 0), "혈압 측정\n팔을 넣고 시작", C(120, 240, 170), C(16, 30, 36), { glow = 1.3, d = 0.02, font = Enum.Font.GothamBold })
	K:plate("StBPButton", 0.2, 0.2, 0.03, pcf * CF(0.45, 3.4, 0.41), Look.ledGreen)
	txt(K, "StBPLabel", 1.0, 0.36, pcf * CF(0, 2.2, 0.41), "자동 혈압계\n무료 측정", PH.dark, PH.white, { d = 0.01 })
	-- 스툴 (Seat 아님)
	K:vcyl("StBPStoolLeg", 1.7, 0.14, pcf * CF(0, 0.85, 1.6), Look.chrome)
	K:disc("StBPStoolFoot", 0.9, 0.06, pcf * CF(0, 0.03, 1.6), Look.chrome)
	K:disc("StBPStoolSeat", 1.0, 0.18, pcf * CF(0, 1.78, 1.6), lk(C(40, 60, 100), M.Leather))
	local busy = false
	promptOn(K, { scr }, {
		action = "혈압 재기",
		object = "자동 혈압계",
		fn = function()
			if busy then
				return
			end
			busy = true
			label.Text = "측정 중...\n움직이지 마세요"
			task.delay(2.6, function()
				local sys = 108 + math.random(0, 22)
				local dia = 68 + math.random(0, 14)
				local pulse = 64 + math.random(0, 20)
				if label.Parent then
					label.Text = string.format("%d / %d mmHg\n맥박 %d · %s", sys, dia, pulse, if sys < 120 then "정상" else "주의")
				end
				busy = false
			end)
		end,
	})
end

-- 약사 가운 걸이 (벽)
-- 조제실 약 서랍장 (처방약장 맨 아래 칸 밑, 약장 앞면에 맞춤): 몸통 + 서랍 칸 + 흰 이름표 + 손잡이 + 위 약포지 · 약봉투
local function drawerCab(K: any, pcf: CFrame, w: number, h: number, d: number, top: boolean)
	K:box("StDrawerBody", V3(w, h, d), pcf * CF(0, h / 2, 0), lk(C(236, 238, 236)))
	K:box("StDrawerKick", V3(w - 0.06, 0.3, 0.04), pcf * CF(0, 0.15, d / 2 + 0.005), Look.charcoal)
	local cols = math.max(3, math.floor(w / 1.25))
	local rows = math.max(2, math.floor((h - 0.4) / 0.72))
	local cw, rh = (w - 0.12) / cols, (h - 0.42) / rows
	for r = 1, rows do
		for c = 1, cols do
			local x = -w / 2 + 0.06 + cw * (c - 0.5)
			local y = 0.36 + rh * (r - 0.5)
			local f = pcf * CF(x, y, d / 2)
			K:plate("StDrawerFront", cw - 0.05, rh - 0.05, 0.03, f, lk(C(246, 248, 246)))
			if K.detail ~= "low" then
				K:plate("StDrawerPull", cw * 0.34, 0.05, 0.04, f * CF(0, -rh * 0.12, 0.03), Look.chrome)
			end
			if K.detail == "high" then
				K:plate("StDrawerLabel", cw * 0.5, 0.1, 0.01, f * CF(0, rh * 0.22, 0.03), lk(if (r + c) % 4 == 0 then C(220, 236, 226) else C(252, 252, 250)))
			end
		end
	end
	if not top then
		return
	end
	-- 위: 약포지 롤 · 약봉투 묶음 (뒤쪽에 얕게)
	K:cyl("StDrawerPaperRoll", 0.5, 0.36, pcf * CF(-w / 2 + 0.6, h + 0.18, -d / 2 + 0.3) * ANG(0, PI / 2, 0), lk(C(250, 250, 248)))
	K:box("StDrawerBags", V3(0.6, 0.12, 0.45), pcf * CF(w / 2 - 0.6, h + 0.06, -d / 2 + 0.3), lk(C(250, 250, 246)))
	K:box("StDrawerBagPrint", V3(0.3, 0.004, 0.2), pcf * CF(w / 2 - 0.6, h + 0.122, -d / 2 + 0.3), lk(PH.main))
end

local function coatHook(K: any, dcf: CFrame)
	K:plate("StCoatRail", 1.2, 0.12, 0.06, dcf * CF(0, 0.6, 0), Look.walnut)
	K:seg("StCoatPeg", (dcf * CF(0, 0.6, 0.05)).Position, (dcf * CF(0, 0.66, 0.3)).Position, 0.06, Look.chrome)
	local d = dcf * CF(0, 0.45, 0.14)
	K:box("StCoatHanger", V3(1.4, 0.05, 0.05), d, lk(C(214, 186, 148), M.Wood))
	K:box("StCoatBody", V3(1.5, 2.8, 0.12), d * CF(0, -1.45, 0), lk(C(250, 250, 250), M.Fabric))
	for _, sx in { -1, 1 } do
		K:box("StCoatSleeve", V3(0.36, 2.2, 0.12), d * CF(sx * 0.82, -1.2, 0.02) * ANG(0, 0, sx * 0.08), lk(C(244, 244, 242), M.Fabric))
		K:box("StCoatLapel", V3(0.26, 1.0, 0.02), d * CF(sx * 0.2, -0.55, 0.07) * ANG(0, 0, -sx * 0.25), lk(C(236, 236, 234), M.Fabric))
	end
	K:plate("StCoatPocket", 0.36, 0.3, 0.01, d * CF(-0.38, -0.9, 0.06), lk(C(236, 236, 234), M.Fabric))
	K:plate("StCoatBadge", 0.36, 0.12, 0.01, d * CF(0.4, -0.85, 0.065), lk(PH.main))
	K:box("StCoatPen", V3(0.04, 0.3, 0.04), d * CF(-0.3, -0.8, 0.09), lk(C(30, 60, 140)))
end

-- 폐의약품 수거함 (흰 철제 함 · 초록 머리 · 투입구 덮개는 여닫기): pcf = 바닥 가운데, +Z = 정면
local function medBin(K: any, pcf: CFrame)
	local w, d, h = 1.3, 0.9, 2.8
	local hb = h - 0.1
	K:box("StMedBinKick", V3(w - 0.08, 0.12, d - 0.08), pcf * CF(0, 0.06, 0), Look.charcoal)
	K:box("StMedBinBody", V3(w, hb - 0.12, d), pcf * CF(0, 0.12 + (hb - 0.12) / 2, 0), lk(C(246, 248, 246), M.Metal))
	K:box("StMedBinCap", V3(w + 0.04, 0.1, d + 0.04), pcf * CF(0, hb + 0.05, 0), lk(PH.main))
	local fr = pcf * CF(0, 0, d / 2)
	txt(K, "StMedBinTitle", w - 0.12, 0.62, fr * CF(0, hb - 0.42, 0), "폐의약품\n수거함", WHITE, PH.main, { d = 0.02, font = Enum.Font.GothamBlack })
	-- 투입구 (어두운 틈 + 둘레) 와 덮개
	local sy = hb - 1.05
	K:plate("StMedBinSlotRim", w * 0.72, 0.26, 0.015, fr * CF(0, sy, 0), Look.steel)
	K:plate("StMedBinSlot", w * 0.62, 0.12, 0.02, fr * CF(0, sy, 0), lk(C(24, 26, 28)))
	local flap = K:group("StMedBinFlapG", function()
		K:plate("StMedBinFlap", w * 0.66, 0.34, 0.03, fr * CF(0, sy - 0.04, 0.015) * CF(0, 0, 0), lk(C(220, 226, 222), M.Metal))
		K:plate("StMedBinFlapHandle", 0.4, 0.05, 0.03, fr * CF(0, sy - 0.17, 0.045), Look.chrome)
	end)
	txt(K, "StMedBinGuide", w - 0.16, 0.86, fr * CF(0, 0.95, 0), "유통기한 지난 약 · 먹다 남은 약\n알약은 포장째 · 물약은 한 병에\n※ 주사바늘 · 체온계 넣지 마세요", INK, C(250, 252, 250), { d = 0.012, font = Enum.Font.GothamBold })
	K:plate("StMedBinStripe", w, 0.08, 0.012, fr * CF(0, 0.42, 0), lk(PH.main))
	-- 덮개 윗변 경첩 기준으로 위로 젖힘
	local hinge = (K.cf * (fr * CF(0, sy + 0.13, 0.03))).Position
	local axis = (K.cf * pcf).XVector
	return Interact.swing(K, flap, hinge, -axis, 1.1, { object = "폐의약품 수거함 투입구", openText = "투입구 열기", closeText = "닫기" })
end

-- 벽걸이 건강 정보 리플릿 꽂이 (아크릴 주머니 3단 x 2열)
local function leafletRack(K: any, dcf: CFrame)
	local cols = { C(60, 150, 90), C(40, 120, 200), C(240, 150, 40), C(220, 70, 90), C(130, 90, 180), C(30, 160, 170) }
	local titles = { "당뇨 관리", "고혈압 수칙", "올바른 약 복용", "감기 · 독감", "피부 건강", "어린이 해열제" }
	K:plate("StLeafBack", 1.6, 1.9, 0.04, dcf, lk(C(236, 238, 236)))
	txt(K, "StLeafHead", 1.5, 0.26, dcf * CF(0, 0.8, 0.045), "건강 정보 · 무료로 가져가세요", WHITE, PH.main, { d = 0.01, font = Enum.Font.GothamBold })
	local i = 0
	for row = 0, 2 do
		for col = 0, 1 do
			i += 1
			local c = dcf * CF(-0.38 + col * 0.76, 0.32 - row * 0.52, 0.04)
			K:box("StLeafPaper", V3(0.6, 0.46, 0.04), c * CF(0, 0.02, 0.05), lk(cols[i]))
			if K.detail ~= "low" then
				txt(K, "StLeafTitle", 0.56, 0.14, c * CF(0, 0.14, 0.071), titles[i], WHITE, nil, { d = 0.004, font = Enum.Font.GothamBold })
			end
			K:box("StLeafPocket", V3(0.68, 0.28, 0.12), c * CF(0, -0.1, 0.07), { c = C(230, 240, 244), m = M.Glass, t = 0.55 })
		end
	end
end

local function buildPharmacy(K: any, V: any, S: any, sub: string)
	local gw = sub == "gw"
	local surfs = mapSurfaces(V)
	local obst = obstacles(V)
	local theme = { promo1 = PH.main, promo2 = C(250, 196, 0), p11 = 0.04, p21 = 0.0, pSale = 0.06, saleText = "추천", promo3 = PH.main, maxTagText = 26, prices = { "3,000", "3,500", "4,500", "5,000", "6,500", "8,000", "12,000", "22,000" } }
	local used = 0
	-- GwShop 점원 인형 (Humanoid 없는 것) 주변 2.5 비움
	if not V._stNpcKeep then
		V._stNpcKeep = true
		for _, hr in V.byName.HumanoidRootPart or {} do
			local par = hr.part.Parent
			local mn, mx = hr.min, hr.max
			for _, r in V.parts do
				if r.part.Parent == par then
					mn = mn:Min(r.min)
					mx = mx:Max(r.max)
				end
			end
			V:addKeep(mn - V3(2.5, 0, 2.5), mx + V3(2.5, 0.5, 2.5), "npc")
		end
	end
	for _, g in V.counters do
		reserveFront(K, g.min, g.max, counterFace(V, g), 2.6, 0.4)
	end
	for _, s in surfs do
		local r = s.rec
		local fwd = s.cf.ZVector
		reserveFront(K, r.min, r.max, V3(math.round(fwd.X), 0, math.round(fwd.Z)), 2.4, 0.2)
	end
	-- 진열: 거리 약국은 Product 숨기고 다시, GwShop 은 Product 상자 범위 안에서만 다시
	local rxBoard = {}
	for _, s in surfs do
		local par = s.rec.part and s.rec.part.Parent
		if par and (par.Name == "처방약장" or string.find(par.Name, "처방", 1, true)) then
			rxBoard[s] = true
		end
	end
	step(K, "shelves", function()
		if gw then
			-- 각 Product 의 선반 앞쪽 방향 = 가장 가까운 칸의 앞
			local hidden = 0
			K:free(function()
				for i, r in V.byName.Product or {} do
					local best, bd = nil, math.huge
					for _, s in surfs do
						if overlapXZ(s.rec, r, 0.05) and r.min.Y >= s.rec.max.Y - 0.2 then
							local dy = r.min.Y - s.rec.max.Y
							if dy < bd then
								best, bd = s, dy
							end
						end
					end
					local front = if best then best.cf.ZVector else awayFromWall(V, r)
					front = V3(math.round(front.X), 0, math.round(front.Z))
					local cats = { "otc", "otc", "supplement", "otc" }
					used += fillInside(K, r, front, cats[(math.floor(r.c.Z / 5) % #cats) + 1], mkRng(V.key .. "p" .. i), if K.detail == "low" then 1 else 2, if best then best.clear else nil)
					Scan.hide(K.hidden, r.part)
					hidden += 1
				end
				for i, r in V.byName.Bottle or {} do
					local front = V3(0, 0, 1)
					for _, fd in V.byName.FridgeDoor or {} do
						if (fd.c - r.c).Magnitude < 5 then
							front = if fd.size.X < fd.size.Z then V3(math.sign(fd.c.X - r.c.X), 0, 0) else V3(0, 0, math.sign(fd.c.Z - r.c.Z))
						end
					end
					local sku = if i % 3 == 0 then SKU.drinkA else SKU.pet
					local base = pcfAt(V3(r.c.X, r.min.Y, r.c.Z), front)
					used += item(K, base, sku, if i % 3 == 0 then C(120, 60, 20) else pick(mkRng(i), { C(250, 200, 40), C(40, 120, 200), C(240, 120, 30) }), nil, math.min(r.size.Y, sku.h), if K.detail == "low" then 1 else 2)
					Scan.hide(K.hidden, r.part)
				end
			end)
			note(K, "gw products restyled " .. hidden)
			-- 원래 상품이 없는 선반 빈 구간만 채움 (선반 안쪽 · 앞 모서리 안)
			local gaps = 0
			for _, su in surfs do
				if not su.fridge and su.rec.part then
					local occ = {}
					for _, r in V.byName.Product or {} do
						if overlapXZ(su.rec, r, 0.02) and r.min.Y >= su.rec.max.Y - 0.25 and r.min.Y < su.rec.max.Y + 0.4 then
							local a = su.cf:PointToObjectSpace(r.min).X
							local b = su.cf:PointToObjectSpace(r.max).X
							table.insert(occ, { math.min(a, b) - 0.05, math.max(a, b) + 0.05 })
						end
					end
					table.sort(occ, function(x, y)
						return x[1] < y[1]
					end)
					local cur = -su.len / 2 + 0.1
					local ivs = {}
					for _, o in occ do
						if o[1] - cur > 0.5 then
							table.insert(ivs, { cur, o[1] })
						end
						cur = math.max(cur, o[2])
					end
					if su.len / 2 - 0.1 - cur > 0.5 then
						table.insert(ivs, { cur, su.len / 2 - 0.1 })
					end
					for gi, iv in ivs do
						local sub2 = { cf = su.cf * CF((iv[1] + iv[2]) / 2, 0, 0), len = iv[2] - iv[1] - 0.05, depth = su.depth, clear = su.clear, rail = false, level = su.level, levels = su.levels }
						queueFill(K, sub2, if (gi + (su.level or 0)) % 3 == 0 then "supplement" else "otc", V.key .. "gg" .. su.face .. gi .. (su.level or 0), theme, { facing = 1, noTags = true, obst = obst })
						gaps += 1
					end
				end
			end
			note(K, "gw shelf gaps filled " .. gaps)
		else
			for _, nm in { "Product", "Bottle" } do
				for _, r in V.byName[nm] or {} do
					Scan.hide(K.hidden, r.part)
				end
			end
			-- 벽 약장: 긴 판을 세로 블록으로 (감기 · 소화 · 진통 · 파스 · 비타민)
			K:free(function()
				for _, s in surfs do
					if rxBoard[s] then
						queueFill(K, s, "rx", V.key .. "rx" .. (s.level or 0), theme, { noTags = true, obst = obst })
					elseif s.len > 6 then
						local nb = math.max(1, math.floor(s.len / 3.2 + 0.5))
						local bw = s.len / nb
						for bi = 1, nb do
							local cat = if bi == nb then "supplement" else "otc"
							local sub2 = { cf = s.cf * CF(-s.len / 2 + bw * (bi - 0.5), 0, 0), len = bw - 0.16, depth = s.depth, clear = s.clear, rail = s.rail, level = s.level, levels = s.levels }
							queueFill(K, sub2, cat, V.key .. s.face .. bi .. (s.level or 0), theme, { obst = obst, facing = 1 })
						end
					else
						local cat = if s.cf.ZVector.X > 0 then "supplement" else "otc"
						queueFill(K, s, cat, V.key .. s.face .. (s.level or 0), theme, { obst = obst, facing = 1 })
					end
				end
			end)
		end
	end)
	-- 머리 띠 · 끝판
	step(K, "headers", function()
		for i, hd in V.byName.Header or {} do
			if not gw then
				local face = if hd.size.X >= hd.size.Z then V3(0, 0, if hd.c.Z < 0 then 1 else -1) else V3(if hd.c.X < 0 then 1 else -1, 0, 0)
				local fpos = if math.abs(face.Z) > 0.5 then (if face.Z > 0 then hd.max.Z else hd.min.Z) else (if face.X > 0 then hd.max.X else hd.min.X)
				local p = if math.abs(face.Z) > 0.5 then V3(hd.c.X, hd.c.Y, fpos) else V3(fpos, hd.c.Y, hd.c.Z)
				local w = math.max(hd.size.X, hd.size.Z)
				K:free(function()
					txt(K, "StHeaderText", w * 0.9, hd.size.Y * 0.72, dcfAt(p, face), "감기 · 해열     소화 · 위장     진통 · 파스     눈 · 피부     비타민 · 영양제", WHITE, nil, { font = Enum.Font.GothamBold, d = 0.01 })
				end)
			end
		end
		local promos = { { "건강기능식품", "비타민 · 유산균 · 오메가3" }, { "약사 추천", "피로회복 · 간 건강" } }
		for i, ep in V.byName.EndPanel or {} do
			local thinX = ep.size.X < ep.size.Z
			local cen = nil
			for _, s in surfs do
				if overlapXZ(s.rec, ep, 0.6) then
					cen = s.rec.c
				end
			end
			local face = if thinX then V3(if cen and cen.X > ep.c.X then -1 else 1, 0, 0) else V3(0, 0, if cen and cen.Z > ep.c.Z then -1 else 1)
			local fpos = if thinX then (if face.X > 0 then ep.max.X else ep.min.X) else (if face.Z > 0 then ep.max.Z else ep.min.Z)
			local w = if thinX then ep.size.Z else ep.size.X
			local p = if thinX then V3(fpos, ep.size.Y * 0.5, ep.c.Z) else V3(ep.c.X, ep.size.Y * 0.5, fpos)
			local pr = promos[(i - 1) % #promos + 1]
			K:free(function()
				poster(K, dcfAt(p, face) * CF(0, 0, -0.05), w - 0.4, ep.size.Y - 1.2, pr[1], pr[2], PH.white, PH.dark, PH.main, WHITE, { titleH = 0.36, frame = false })
			end)
			for _, eh in V.byName.EndHeader or {} do
				if overlapXZ(eh, ep, 0.05) then
					local hp = if thinX then V3((if face.X > 0 then eh.max.X else eh.min.X), eh.c.Y, eh.c.Z) else V3(eh.c.X, eh.c.Y, (if face.Z > 0 then eh.max.Z else eh.min.Z))
					K:free(function()
						txt(K, "StEndHeaderText", w - 0.2, eh.size.Y * 0.7, dcfAt(hp, face), if i % 2 == 0 then "생활건강 · 위생" else "건강기능식품", WHITE, nil, { d = 0.015, font = Enum.Font.GothamBlack })
					end)
				end
			end
		end
	end)
	step(K, "cashier", function()
		for _, g in V.counters do
			cashierDress(K, V, g, PH, "pharmacy")
		end
	end)
	-- 처방약장 맨 아래 판 밑이 비어 있으면 조제실 약 서랍장 (약장 앞면에 맞춘 얕은 장)
	step(K, "drawers", function()
		local low = nil
		for sf in rxBoard do
			if sf.rec and sf.rec.name == "Board" and sf.rec.min.Y > 2.6 and (not low or sf.rec.min.Y < low.rec.min.Y) then
				low = sf
			end
		end
		if not low then
			return
		end
		local face = low.cf.ZVector
		local d = math.min(1.0, low.depth - 0.05)
		local h = low.rec.min.Y - 0.06
		local w = low.len - 0.1
		local p = low.cf.Position - face * (d / 2 + 0.02)
		local pcf = pcfAt(V3(p.X, 0, p.Z), V3(math.round(face.X), 0, math.round(face.Z)))
		local mn, mx = canPlace(K, pcf, V3(w, h, d), 0)
		if mn and mx then
			K:reserve(mn, mx, "drawers")
			drawerCab(K, pcf, w, h, d, true)
		else
			-- 직원 자리 keep 안: 약장 뒤판에 붙은 붙박이 서랍 (뒤판 면에서 0.1 이내 = 벽 마감)
			local bp = low.cf.Position - face * (low.depth - 0.05)
			local fcf = pcfAt(V3(bp.X, 0, bp.Z), V3(math.round(face.X), 0, math.round(face.Z)))
			K:free(function()
				drawerCab(K, fcf, w, h, 0.1, false)
			end)
		end

	end)
	step(K, "did", function()
		local wn, dcf = wallItemSpot(K, { "right", "left", "back" }, 3.2, math.min(4.6, V.H - 3.3), math.min(6.6, V.H - 1.3), -3, function(d: CFrame): boolean
			return promptOk(K, d.Position)
		end)
		if wn and dcf then
			didScreen(K, dcf, 2.8, {
				{ text = "건강 정보\n물은 하루 8잔", c = PH.main },
				{ text = "감기약 복용 중\n음주는 피하세요", c = PH.sub },
				{ text = "약 보관은\n서늘하고 건조하게", c = C(60, 120, 90) },
				{ text = "유통기한 지난 약은\n약국 수거함에", c = PH.dark },
			}, "건강 정보 화면")
		end
	end)
	if not gw then
		step(K, "bp", function()
			local door = V.door
			local prefer = if door then V3(door.x, 0, door.z - 6) else nil
			local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.6, 3.4, 4.4, prefer, 0.1, "bp", function(c: CFrame): boolean
				return promptOk(K, (c * CF(0, 0, -0.4)).Position)
			end)
			if wn and pcf then
				-- 벽에서 0.2 띄우고 화면은 방 쪽
				bpCorner(K, pcf * CF(0, 0, -0.8))
				local wn2, dcf2 = wallItemSpot(K, { wn }, 1.8, 4.6, 5.8, (V:wallCoord(wn, pcf.Position)))
				if wn2 and dcf2 then
					txt(K, "StBPWallSign", 1.7, 0.7, dcf2 * CF(0, 0, 0.04), "자동 혈압계\n누구나 무료", WHITE, PH.main, { d = 0.03, font = Enum.Font.GothamBlack })
				end
			end
		end)
		step(K, "wallunits", function()
			local hU = math.min(5.4, V.H - 2.0)
			local cats = { { "supplement", "건강기능식품 · 비타민" }, { "dermo", "더마 화장품 · 피부 연고" }, { "otc", "마스크 · 밴드 · 파스" } }
			local placed = 0
			for _, cc in cats do
				if placed >= 2 then
					break
				end
				for _, len in { 6.4, 4.8, 3.6 } do
					local wn, pcf = wallFloorSpot(K, { "right", "left" }, len, 1.3, hU + 0.7, nil, 0, "wallunit")
					if wn and pcf then
						local us = wallUnit(K, pcf, len, 1.3, hU, { title = cc[2], headL = lk(PH.main), titleFg = WHITE, lineL = lk(PH.dark), levels = 5, glow = 1.1 })
						K:free(function()
							for _, s in us do
								queueFill(K, s, cc[1], V.key .. cc[1] .. s.level, theme, {})
							end
						end)
						placed += 1
						break
					end
				end
			end
		end)
		step(K, "popstand", function()
			local d = V.door
			if d then
				local cands = {}
				for _, dx in { 5.2, -5.2, 6.0, -6.0 } do
					table.insert(cands, V3(d.x + dx, 0, V.z1 - 3.0))
					table.insert(cands, V3(d.x + dx, 0, V.z1 - 4.2))
				end
				local pcf = floorSpot(K, cands, V3(1.6, 5.2, 1.1), V3(0, 0, 1), 0.2, "pop")
				if pcf then
					popStand(K, pcf, "환절기 건강", "감기약 · 비타민\n약사 상담 무료", PH.main, WHITE)
				end
			end
		end)
		step(K, "cross", function()
			-- 약국 LED 십자 간판 (진녹색 알루미늄 테 + 초록 LED 면 + 가운데 흰 '약') + 옆 'PHARMACY' 글자판
			local wn, dcf = wallItemSpot(K, { "back", "left", "right" }, 4.4, math.max(5.4, V.H - 2.4), V.H - 0.3, 0)
			local cw = 1.9
			if wn and dcf then
				local d = dcf * CF(-1.2, 0, 0.04)
				K:plate("StCrossMount", 0.5, 0.5, 0.08, d, Look.alu)
				for _, hv in { V3(cw, cw * 0.34, 0), V3(cw * 0.34, cw, 0) } do
					K:plate("StCrossFrame", hv.X, hv.Y, 0.16, d * CF(0, 0, 0.08), lk(PH.dark, M.Metal))
					K:plate("StCrossFace", hv.X - 0.1, hv.Y - 0.1, 0.03, d * CF(0, 0, 0.24), Look.neon(C(20, 210, 90)))
				end
				txt(K, "StCrossYak", cw * 0.3, cw * 0.3, d * CF(0, 0, 0.275), "약", PH.dark, WHITE, { d = 0.01, font = Enum.Font.GothamBlack, glow = 1.1 })
				txt(K, "StCrossWord", 2.1, 0.9, dcf * CF(1.05, 0, 0.04), "약국\nPHARMACY", PH.dark, nil, { d = 0.02, font = Enum.Font.GothamBlack })
			else
				wn, dcf = wallItemSpot(K, { "back", "left", "right" }, 2.0, math.max(5.4, V.H - 2.4), V.H - 0.3, 0)
				if wn and dcf then
					local d = dcf * CF(0, 0, 0.04)
					for _, hv in { V3(cw, cw * 0.34, 0), V3(cw * 0.34, cw, 0) } do
						K:plate("StCrossFrame", hv.X, hv.Y, 0.16, d, lk(PH.dark, M.Metal))
						K:plate("StCrossFace", hv.X - 0.1, hv.Y - 0.1, 0.03, d * CF(0, 0, 0.16), Look.neon(C(20, 210, 90)))
					end
					txt(K, "StCrossYak", cw * 0.3, cw * 0.3, d * CF(0, 0, 0.195), "약", PH.dark, WHITE, { d = 0.01, font = Enum.Font.GothamBlack, glow = 1.1 })
				end
			end
		end)
		step(K, "leaflets", function()
			local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 1.8, 3.4, 5.5, 2)
			if wn and dcf then
				leafletRack(K, dcf * CF(0, 0, 0.02))
			end
		end)
		step(K, "coat", function()
			local cnt = V.counters[1]
			local prefer = if cnt then V:wallCoord("right", (cnt.min + cnt.max) / 2) else 0
			local wn, dcf = wallItemSpot(K, { "right", "left" }, 1.6, 2.4, 6.2, prefer - 4)
			if wn and dcf then
				coatHook(K, dcf * CF(0, 0, 0.02))
			end
		end)
	end
	-- 폐의약품 수거함: 벽 앞 빈 자리 (프롬프트 둘 수 있는 곳 우선), 없으면 생략
	step(K, "medbin", function()
		local door = V.door
		local prefer = if door then V3(door.x, 0, door.z - 7) else nil
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.5, 1.0, 3.0, prefer, 0.15, "medbin", function(c: CFrame): boolean
			return promptOk(K, (c * CF(0, 1.8, 0.5)).Position)
		end)
		if not (wn and pcf) and not gw then
			wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.5, 1.0, 3.0, prefer, 0.15, "medbin")
		end
		if wn and pcf then
			medBin(K, pcf * CF(0, 0, -0.05))
			local mn, mx = K.laabb(pcf * CF(0, 1.2, 1.3), V3(1.5, 2.4, 1.6))
			K:reserve(mn, mx, "front")
		else
			note(K, "no medbin spot")
		end
	end)
	step(K, "hang", function()
		local n = 0
		for _, s in surfs do
			if n < (if gw then 2 else 1) and not rxBoard[s] and s.len < 7 then
				local r = s.rec
				if hangSignNear(K, r.c.X, r.c.Z, 3.4, 0.9, math.max(5.5, V.H - 2.2), 0, "일반의약품 · 건강기능식품", "약은 약사와 상담하세요", PH.main, WHITE, PH.dark) then
					n += 1
				end
			end
		end
	end)
	fixturesNow(K, V, S)
	step(K, "posters", function()
		local P = {
			{ "영업시간", "평일 09:00 - 21:00\n토 09:00 - 18:00 · 일 휴무", PH.white, INK, PH.main },
			{ "의약품 부작용 피해구제", "한국의약품안전관리원\n1644-6223", PH.white, INK, PH.sub },
			{ "약은 약사에게", "복약 지도 · 상비약 상담\n처방전 접수", PH.white, INK, PH.dark },
			{ "금연 상담", "니코틴 패치 · 껌 상담\n보건소 금연클리닉 연계", PH.white, INK, C(200, 90, 40) },
			{ "휴일지킴이약국", "일 · 공휴일 운영 약국 안내\n129 · 응급의료포털", PH.white, INK, PH.main },
		}
		local nP = if gw then 2 else #P
		for i = 1, nP do
			local p = P[if gw then i + 1 else i]
			local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 1.9, math.min(4.2, V.H - 3.6), math.min(6.4, V.H - 1.4), (i - 3) * 3)
			if wn and dcf then
				poster(K, dcf, 1.7, math.min(2.0, V.H - 5.8), p[1], p[2], p[3], p[4], p[5], WHITE, {})
			end
		end
	end)
	step(K, "goods", function()
		used += runFill(K, goodsBudget(K, V, 1.45))
	end)
	note(K, string.format("pharmacy %s goods parts=%d surfaces=%d", sub, used, #surfs))
end

---------------------------------------------------------------------------------------------------
-- 8b. 장비 리스킨 (POS · 전자레인지 · 온수기) + 윗벽 라이트박스
--   맵의 PosBase · Microwave · HotWater 는 게임플레이 앵커라 크기 · 자리를 그대로 덮어씌운 뒤에만 숨김 (R3).
--   본체는 원래 AABB 와 정확히 같은 범위, 앞면 디테일은 그 범위 안 마지막 0.02 에 들어감.
---------------------------------------------------------------------------------------------------

-- 기록 r 의 AABB 를 정면 face 기준 소품 프레임으로: pcf (바닥 가운데, +Z = 정면), 폭 w, 깊이 d, 높이 h
local function recFrame(r: any, face: Vector3): (CFrame, number, number, number)
	local sx, sz = r.max.X - r.min.X, r.max.Z - r.min.Z
	local fz = math.abs(face.Z) > 0.5
	local w = if fz then sx else sz
	local d = if fz then sz else sx
	local p = V3((r.min.X + r.max.X) / 2, r.min.Y, (r.min.Z + r.max.Z) / 2)
	return pcfAt(p, face), w, d, r.max.Y - r.min.Y
end

local function axisDir(v: Vector3): Vector3
	if math.abs(v.X) > math.abs(v.Z) then
		return V3(if v.X >= 0 then 1 else -1, 0, 0)
	end
	return V3(0, 0, if v.Z >= 0 then 1 else -1)
end

-- 업소용 전자레인지 (스테인리스 몸체 · 검은 유리창 문 · 오른쪽 조작부)
local function microwaveSkin(K: any, V: any, r: any, door: any?, i: number)
	local face = awayFromWall(V, r)
	if door then
		face = axisDir(door.c - r.c)
	end
	local pcf, w, d, h = recFrame(r, face)
	local body = if i % 2 == 1 then Look.steel else lk(C(236, 236, 232))
	local fr = pcf * CF(0, 0, d / 2 - 0.02)
	local hi = K.detail == "high"
	K:free(function()
		K:box("StMwBody", V3(w, h, d - 0.02), pcf * CF(0, h / 2, -0.01), body)
		-- 문 (창 + 테두리) · 손잡이 홈
		local dw = w * 0.7
		local dx = -w / 2 + dw / 2 + 0.03
		K:plate("StMwDoor", dw, h - 0.08, 0.012, fr * CF(dx, h / 2, 0), lk(C(44, 46, 50), M.SmoothPlastic, { r = 0.1 }))
		K:plate("StMwWindow", dw - 0.22, h - 0.3, 0.018, fr * CF(dx - 0.03, h / 2, 0), lk(C(18, 20, 24), M.Glass, { r = 0.3 }))
		K:plate("StMwHandle", 0.06, h * 0.56, 0.02, fr * CF(dx + dw / 2 - 0.08, h / 2, 0), Look.chrome)
		-- 조작부: 표시창 + 버튼
		local px = w / 2 - (w - dw - 0.06) / 2 - 0.02
		local pw = w - dw - 0.1
		K:plate("StMwPanel", pw, h - 0.08, 0.012, fr * CF(px, h / 2, 0), lk(C(26, 26, 28)))
		K:plate("StMwDisplay", pw * 0.78, 0.12, 0.018, fr * CF(px, h - 0.2, 0), Look.neon(C(110, 230, 255)))
		if hi then
			for row = 0, 2 do
				for col = 0, 1 do
					K:plate("StMwKey", pw * 0.3, 0.07, 0.016, fr * CF(px - pw * 0.2 + col * pw * 0.4, h - 0.38 - row * 0.12, 0), lk(if row == 2 and col == 1 then C(60, 170, 90) else C(150, 152, 156)))
				end
			end
			K:plate("StMwStart", pw * 0.7, 0.1, 0.016, fr * CF(px, 0.16, 0), lk(C(220, 50, 50)))
		end
		-- 안내 스티커 (문 위 가장자리)
		txt(K, "StMwSticker", dw * 0.62, 0.12, fr * CF(dx, h - 0.06, 0.019), "업소용 1000W · 금속 용기 금지", INK, C(250, 220, 60), { d = 0.002, font = Enum.Font.GothamBold })
	end)
end

-- 온수기 (흰 몸체 · 위 표시창 · 빨간 버튼 · 실제로 파인 물 받는 칸 + 노즐 + 물받이)
local function hotWaterSkin(K: any, V: any, r: any)
	local face = awayFromWall(V, r)
	local pcf, w, d, h = recFrame(r, face)
	local bodyL = lk(C(240, 240, 238))
	local edgeL = Look.steel
	local a0, a1 = h * 0.2, h * 0.56 -- 칸 아래 · 위
	local fz = d / 2 - 0.02 -- 앞면 (디테일 0.02 는 이 앞)
	local rd = 0.32 -- 칸 깊이
	local fr = pcf * CF(0, 0, fz)
	K:free(function()
		-- 뒤 몸통 + 앞 블록들 (가운데 칸이 비게)
		K:box("StHwBack", V3(w, h - 0.05, d - 0.02 - rd), pcf * CF(0, (h - 0.05) / 2, -d / 2 + (d - 0.02 - rd) / 2), bodyL)
		K:box("StHwBase", V3(w, a0, rd), pcf * CF(0, a0 / 2, fz - rd / 2), bodyL)
		K:box("StHwTop", V3(w, h - 0.05 - a1, rd), pcf * CF(0, a1 + (h - 0.05 - a1) / 2, fz - rd / 2), bodyL)
		for sx = -1, 1, 2 do
			K:box("StHwSide", V3(0.14, a1 - a0, rd), pcf * CF(sx * (w / 2 - 0.07), (a0 + a1) / 2, fz - rd / 2), bodyL)
		end
		K:box("StHwLid", V3(w - 0.04, 0.05, d - 0.06), pcf * CF(0, h - 0.025, -0.01), edgeL)
		-- 칸 안: 어두운 뒷면 · 노즐 · 물받이 격자
		K:plate("StHwNiche", w - 0.28, a1 - a0, 0.01, pcf * CF(0, (a0 + a1) / 2, fz - rd), lk(C(60, 62, 66)))
		K:vcyl("StHwNozzle", 0.14, 0.09, pcf * CF(0, a1 - 0.07, fz - rd / 2), Look.chrome)
		K:box("StHwTray", V3(w - 0.3, 0.04, rd - 0.04), pcf * CF(0, a0 + 0.02, fz - rd / 2 + 0.01), lk(C(150, 152, 156), M.DiamondPlate))
		-- 앞면: 표시창 · 버튼 · 경고
		txt(K, "StHwDisplay", w * 0.66, 0.2, fr * CF(0, h * 0.86, 0), "온수 98℃", C(255, 90, 70), C(20, 20, 22), { d = 0.016, glow = 1.2, font = Enum.Font.GothamBlack })
		K:cyl("StHwButton", 0.018, 0.24, fr * CF(0, h * 0.7, 0.009) * ANG(0, PI / 2, 0), lk(C(220, 36, 40)))
		txt(K, "StHwWarn", w * 0.8, 0.22, fr * CF(0, a0 * 0.55, 0), "뜨거운 물 주의\n컵라면 · 차 전용", INK, C(250, 210, 40), { d = 0.012, font = Enum.Font.GothamBold })
	end)
end

-- POS (맵 PosBase 는 같은 범위로 덮고, 엉성한 화면 뒤판 · 손님 표시창은 숨긴 뒤 기울어진 터치 모니터 + 손님 화면으로)
local function posSkin(K: any, V: any, kind: string, sub: string)
	local B = BRANDS[sub] or nil
	local brandName = if B then B.name elseif kind == "pharmacy" then "약국" elseif sub == "cosmetics" then "OLIVE YOUNG" else tostring(V.name or "")
	local accent = if B then B.main elseif kind == "pharmacy" then PH.main elseif sub == "cosmetics" then OY.main else C(30, 80, 160)
	for _, pb in V.byName.PosBase or {} do
		local sb, cd = nil, nil
		for _, r in V.byName.PosScreenBack or {} do
			local dv = r.c - pb.c
			if V3(dv.X, 0, dv.Z).Magnitude < 1.0 then
				sb = r
			end
		end
		if not sb then
			continue
		end
		for _, r in V.byName.CustomerDisplay or {} do
			local dv = r.c - sb.c
			if V3(dv.X, 0, dv.Z).Magnitude < 0.8 then
				cd = r
			end
		end
		local g = nil
		for _, c in V.counters do
			if pb.c.X >= c.min.X - 0.3 and pb.c.X <= c.max.X + 0.3 and pb.c.Z >= c.min.Z - 0.6 and pb.c.Z <= c.max.Z + 0.6 then
				g = c
			end
		end
		local cust = if g then counterFace(V, g) else V3(0, 0, 1)
		if cd then
			local dv = cd.c - sb.c
			if math.abs(dv.X) + math.abs(dv.Z) > 0.03 then
				cust = axisDir(dv)
			end
		end
		local pcf, w, d, h = recFrame(pb, cust)
		local dark = lk(C(38, 40, 44))
		local sbz = pcf:PointToObjectSpace(sb.c).Z
		local my = sb.c.Y - pb.min.Y
		local tilt = 0.22
		K:free(function()
			-- 본체 (PosBase 와 같은 범위): 아래 금전함 + 위 덮개
			K:box("StPosBody", V3(w, h, d - 0.02), pcf * CF(0, h / 2, 0.01), dark)
			local sf = pcf * CF(0, 0, -d / 2 + 0.02) * ANG(0, PI, 0) -- 직원 쪽 면
			K:plate("StPosDrawer", w - 0.12, h * 0.56, 0.016, sf * CF(0, h * 0.34, 0), lk(C(54, 56, 60)))
			K:plate("StPosDrawerLip", w * 0.4, 0.04, 0.02, sf * CF(0, h * 0.6, 0), Look.chrome)
			K:plate("StPosKey", 0.08, 0.08, 0.02, sf * CF(w / 2 - 0.2, h * 0.36, 0), Look.chrome)
			-- 모니터 받침
			K:box("StPosFoot", V3(0.6, 0.04, 0.46), pcf * CF(0, h + 0.02, sbz), lk(C(30, 30, 32)))
			K:box("StPosNeck", V3(0.18, math.max(0.1, my - h - 0.3), 0.1), pcf * CF(0, h + math.max(0.1, my - h - 0.3) / 2, sbz - 0.02), Look.darkAlu)
			-- 직원용 터치 모니터 (직원 쪽을 보고 뒤로 기움)
			local mc = pcf * CF(0, my, sbz) * ANG(0, PI, 0) * ANG(-tilt, 0, 0)
			K:box("StPosBezel", V3(1.42, 0.98, 0.1), mc * CF(0, 0, -0.05), lk(C(22, 22, 24)))
			txt(K, "StPosScreen", 1.3, 0.86, mc, brandName .. "  POS\n상품 0개 · 합계 0원\n[ 카드 ]  [ 현금 ]  [ 간편결제 ]", C(30, 40, 60), C(232, 240, 250), { d = 0.008, glow = 1.1, font = Enum.Font.GothamBold })
			-- 손님 쪽 표시창 (모니터 뒤판)
			local bc = mc * CF(0, 0, -0.1) * ANG(0, PI, 0)
			txt(K, "StPosCustomer", 0.96, 0.56, bc * CF(0, 0.08, 0), "결제 금액\n0원", WHITE, accent, { d = 0.008, glow = 1.1, font = Enum.Font.GothamBlack })
			K:plate("StPosLogoBar", 0.96, 0.12, 0.008, bc * CF(0, -0.32, 0), lk(C(240, 240, 240)))
		end)
		Scan.hide(K.hidden, pb.part)
		Scan.hide(K.hidden, sb.part)
		if cd then
			Scan.hide(K.hidden, cd.part)
		end
	end
end

local function equipSkins(K: any, V: any, kind: string, sub: string)
	step(K, "pos", function()
		posSkin(K, V, kind, sub)
	end)
	step(K, "microwave", function()
		for i, r in V.byName.Microwave or {} do
			local door = nil
			for _, dr in V.byName.MicrowaveDoor or {} do
				local dv = dr.c - r.c
				if V3(dv.X, 0, dv.Z).Magnitude < 1.0 and math.abs(dv.Y) < 0.4 then
					door = dr
				end
			end
			microwaveSkin(K, V, r, door, i)
			Scan.hide(K.hidden, r.part)
			if door then
				Scan.hide(K.hidden, door.part)
			end
		end
		for _, r in V.byName.HotWater or {} do
			hotWaterSkin(K, V, r)
			Scan.hide(K.hidden, r.part)
		end
	end)
end

-- 벽 wn 의 y0..y1 에서 정말 빈 u 구간: V:spans (가구 · 문 · keep) 에서 맵 간판 · 머리판 (shell 이라 spans 가 안 보는 것)과
-- 우리 벽 부착물 (K.wallUsed) 을 더 뺌
local function freeIntervals(K: any, V: any, wn: string, y0: number, y1: number): { { number } }
	local cuts = {}
	for _, r in V.parts do
		local nm = r.name
		if (string.sub(nm, 1, 5) == "Sign_" or not STRUCT[nm]) and r.part.Transparency < 0.99 and r.max.Y > y0 and r.min.Y < y1 then
			local umin, umax, dmin = math.huge, -math.huge, math.huge
			for _, x in { r.min.X, r.max.X } do
				for _, z in { r.min.Z, r.max.Z } do
					local u, dd = V:wallCoord(wn, V3(x, 0, z))
					umin, umax, dmin = math.min(umin, u), math.max(umax, u), math.min(dmin, dd)
				end
			end
			if dmin < 1.2 and dmin > -0.6 then
				table.insert(cuts, { umin - 0.3, umax + 0.3 })
			end
		end
	end
	for _, u in K.wallUsed or {} do
		if u.w == wn and u.y0 < y1 and u.y1 > y0 then
			table.insert(cuts, { u.a - 0.2, u.b + 0.2 })
		end
	end
	table.sort(cuts, function(p, q)
		return p[1] < q[1]
	end)
	local out = {}
	for _, sp in V:spans(wn, y0, y1, 1.0) do
		local cur = sp[1]
		for _, c in cuts do
			if c[2] > cur and c[1] < sp[2] then
				if c[1] > cur then
					table.insert(out, { cur, c[1] })
				end
				cur = math.max(cur, c[2])
			end
		end
		if sp[2] > cur then
			table.insert(out, { cur, sp[2] })
		end
	end
	return out
end

-- 윗벽 라이트박스 (진열장 위 빈 벽): walls 의 y0..y1 빈 구간마다 (긴 구간은 여러 개), list 를 차례로
local function lightboxes(K: any, V: any, walls: { string }, y0: number, y1: number, list: { any }, maxN: number?, maxW: number?): number
	local n = 0
	local idx = (hashStr(V.key) % #list)
	local h = math.min(2.6, y1 - y0)
	if h < 1.2 then
		return 0
	end
	local yc = y0 + h / 2
	local MW = maxW or 14
	for _, wn in walls do
		if K.stDebugLb then
			local ss = {}
			for _, sp in freeIntervals(K, V, wn, y0, y0 + h) do
				table.insert(ss, string.format("%.1f..%.1f", sp[1], sp[2]))
			end
			note(K, "lb " .. wn .. " y" .. y0 .. ": " .. table.concat(ss, " "))
		end
		for _, sp in freeIntervals(K, V, wn, y0, y0 + h) do
			local len = sp[2] - sp[1]
			if len < 4.5 then
				continue
			end
			local k = math.max(1, math.ceil((len - 0.6) / (MW + 0.8)))
			local seg = len / k
			for j = 1, k do
				if n >= (maxN or 6) then
					return n
				end
				local w = math.min(seg - 0.8, MW)
				local u = sp[1] + seg * (j - 0.5)
				local dcf = V:wall(wn, u, yc, 0.02)
				local mn, mx = K.laabb(dcf * CF(0, 0, 0.12), V3(w, h, 0.24))
				if w >= 3.6 and not mapBlocked(K, mn, mx) and not K:hitsKeep(mn, mx) then
					idx += 1
					local it = list[(idx - 1) % #list + 1]
					K:free(function()
						K:plate("StLbFrame", w, h, 0.16, dcf, lk(C(214, 216, 218), M.Metal))
						txt(K, "StLbFace", w - 0.16, h - 0.16, dcf * CF(0, 0, 0.16), " ", it.fg, it.bg, { d = 0.01, glow = 1.05 })
						local side = it.side and w >= 7
						local tw = if side then w * 0.62 else w * 0.9
						local tx = if side then -w * 0.17 else 0
						txt(K, "StLbTitle", tw, h * 0.42, dcf * CF(tx, h * 0.14, 0.17), it.title, it.fg, it.bg, { d = 0.006, glow = 1.05, font = Enum.Font.GothamBlack })
						txt(K, "StLbSub", tw * 0.9, h * 0.2, dcf * CF(tx, -h * 0.22, 0.17), it.sub, it.fg2 or it.fg, it.bg, { d = 0.006, glow = 1.05, font = Enum.Font.GothamBold })
						if it.band then
							K:plate("StLbBand", w - 0.16, 0.12, 0.012, dcf * CF(0, -h / 2 + 0.2, 0.17), lk(it.band))
						end
						if side then
							-- 오른쪽: 큰 상품 실루엣 (튜브 · 앰플 병) = 사진 대신 입체 판
							local sx = w / 2 - w * 0.17
							local sc = it.sideC or C(250, 250, 248)
							K:plate("StLbHero", 0.7, h * 0.62, 0.03, dcf * CF(sx - 0.55, -h * 0.04, 0.17), lk(sc))
							K:plate("StLbHeroCap", 0.46, h * 0.16, 0.035, dcf * CF(sx - 0.55, h * 0.35, 0.17), lk(darker(sc, 0.5)))
							K:plate("StLbHero2", 0.5, h * 0.48, 0.03, dcf * CF(sx + 0.45, -h * 0.11, 0.17), lk(it.sideC2 or lighter(it.bg, 0.5)))
							K:plate("StLbHero2Cap", 0.24, h * 0.14, 0.035, dcf * CF(sx + 0.45, h * 0.2, 0.17), lk(C(40, 40, 40)))
						end
					end)
					addWallUsed(K, wn, u - w / 2, u + w / 2, y0, y0 + h)
					n += 1
				end
			end
		end
	end
	return n
end

---------------------------------------------------------------------------------------------------
-- 9. 스타일 · 빌드 입구
---------------------------------------------------------------------------------------------------

function T.style(V: any): any
	local kind, sub = subtype(V)
	local S: any = {
		chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey },
		stool = { style = "cushion" },
		table = { top = Look.white, base = Look.blackMetal },
		lights = { kind = "none" },
		ceiling = {},
		skip = { fixtures = true },
		clock = true,
		license = true,
	}
	if kind == "cvs" then
		local B = BRANDS[sub] or BRANDS.indie
		S.counter = { front = "panel", frontL = lk(B.main), topL = lk(C(232, 232, 228)), kickL = Look.charcoal, led = Color3.fromRGB(236, 244, 255) }
		S.floor = { look = lk(C(226, 226, 222), M.CeramicTiles), tile = 2.0, grout = lk(C(186, 186, 182)) }
		S.base = lk(C(90, 92, 96))
		S.mat = { look = lk(C(48, 50, 54), M.Fabric), text = B.name }
		S.lower = false
		S.plants = { "snake" }
	elseif kind == "pharmacy" then
		S.counter = if sub == "gw" then false else { front = "panel", frontL = lk(C(248, 250, 248)), topL = lk(C(240, 242, 240)), kickL = lk(C(10, 110, 50)), led = Color3.fromRGB(240, 255, 245) }
		S.floor = if sub == "gw" then false else { look = lk(C(236, 238, 236), M.CeramicTiles), tile = 2.0, grout = lk(C(200, 204, 200)) }
		S.base = lk(C(10, 110, 50))
		S.mat = { look = lk(C(40, 60, 48), M.Fabric), text = "WELCOME" }
		S.lights = if sub == "gw" then { kind = "none" } else { kind = "downlight", n = 4, color = Look.coolLight, glow = Look.lampCool }
		S.lower = false
		S.plants = { "snake", "olive" }
	else
		if sub == "cosmetics" then
			S.counter = { front = "panel", frontL = lk(C(250, 250, 248)), topL = lk(C(244, 244, 240), M.Marble), kickL = lk(OY.main), led = Color3.fromRGB(240, 255, 220) }
			S.floor = { look = lk(C(242, 242, 238), M.Marble, { r = 0.04 }), tile = 3.0, grout = lk(C(214, 214, 210)) }
			S.base = lk(C(250, 250, 248))
			S.mat = { look = lk(C(40, 44, 40), M.Fabric), text = "OLIVE YOUNG" }
			S.lower = false
		elseif sub == "beach" then
			S.counter = { front = "wood", frontL = lk(C(196, 160, 118), M.WoodPlanks), topL = lk(C(240, 236, 226)), kickL = Look.charcoal, led = Color3.fromRGB(255, 220, 170) }
			S.floor = { look = lk(C(206, 176, 136), M.WoodPlanks), tile = 0 }
			S.base = lk(C(30, 120, 200))
			S.lower = { kind = "paint", h = 3.2, look = lk(C(200, 230, 246)), cap = lk(C(250, 250, 250)), walls = { "left", "right" } }
			S.mat = { look = lk(C(40, 90, 140), M.Fabric), text = "BEACH" }
		elseif sub == "souvenir" then
			S.counter = { front = "wood", frontL = Look.oak, topL = lk(C(240, 236, 226)), kickL = Look.charcoal, led = Color3.fromRGB(255, 214, 160) }
			S.floor = { look = Look.floorOak, tile = 0 }
			S.base = Look.walnut
			S.lower = { kind = "wainscot", h = 3.0, look = lk(C(236, 228, 212)), walls = { "left", "right" } }
			S.mat = { look = lk(C(40, 50, 80), M.Fabric), text = "BUSAN" }
		else
			S.counter = { front = "wood", frontL = Look.oak, topL = Look.marbleWhite, kickL = Look.charcoal }
			S.floor = { look = Look.floorOak, tile = 0 }
			S.base = Look.walnut
			S.lower = false
		end
	end
	S._kind, S._sub = kind, sub
	return S
end

function T.build(K: any, V: any, S: any)
	local kind, sub = S._kind, S._sub
	if not kind then
		kind, sub = subtype(V)
	end
	note(K, "type " .. tostring(kind) .. "/" .. tostring(sub))
	addHostEstimates(K, V, kind)
	if kind == "cvs" then
		buildCvs(K, V, S, sub)
	elseif kind == "pharmacy" then
		buildPharmacy(K, V, S, sub)
	else
		buildRetail(K, V, S, sub)
	end
	-- 미뤄 둔 공통 벽 부착물 (스위치 · 콘센트 · 온도조절기 · 비상벨 · 사업자등록증 · 시계): 우리 진열대를 피함
	fixturesNow(K, V, S)
	-- 장비 리스킨 (계산대 소품 자리 계산이 끝난 뒤: 맵 POS 화면 뒤판을 숨기기 전에 피해 놓았음)
	equipSkins(K, V, kind, sub)
	step(K, "lightbox", function()
		local n = 0
		if kind == "cvs" then
			-- 편의점: 냉장고 · 진열장 위 남는 윗벽에 브랜드 행사 라이트박스 (최대 2)
			local B = BRANDS[sub] or BRANDS.indie
			local nm = if sub == "indie" then tostring(V.name or B.name) else B.name
			local LB: { [string]: any } = {
				seven = { { title = "세븐일레븐 이달의 행사", sub = "1+1 · 2+1 · 덤 증정 · 세븐앱 쿠폰 할인", bg = B.main, fg = WHITE, fg2 = C(255, 214, 160), band = B.sub }, { title = "세븐카페 원두커피", sub = "아메리카노 1,300 · 택배 접수 · 세븐앱 픽업", bg = C(250, 250, 248), fg = B.main, fg2 = B.accent, band = B.sub } },
				gs25 = { { title = "GS25 갓생기획", sub = "이달의 1+1 · 2+1 · 우리동네GS 앱 픽업", bg = B.main, fg = WHITE, fg2 = C(200, 236, 255), band = B.accent }, { title = "카페25 원두커피", sub = "아이스 아메리카노 1,800 · 반값택배 접수", bg = C(250, 250, 248), fg = B.main, fg2 = B.dark, band = B.sub } },
				cu = { { title = "CU 득템 행사", sub = "1+1 · 2+1 · 포켓CU 앱 쿠폰", bg = B.main, fg = WHITE, fg2 = B.sub, band = B.sub }, { title = "GET 커피", sub = "연세우유 크림빵과 함께 · 알뜰택배 접수", bg = C(250, 250, 248), fg = B.main, fg2 = C(90, 130, 30), band = B.sub } },
				emart24 = { { title = "emart24 이달의 행사", sub = "1+1 · 2+1 · 노브랜드 상품 · 와인 할인", bg = B.main, fg = B.dark, fg2 = C(120, 20, 20), band = B.dark }, { title = "이프레소 원두커피", sub = "아메리카노 1,500 · 택배 접수 · 앱 픽업", bg = C(52, 52, 54), fg = B.main, fg2 = WHITE, band = B.main } },
				indie = { { title = nm, sub = "신선식품 · 생활용품 · 음료 · 주류 매일 할인", bg = B.main, fg = WHITE, fg2 = C(255, 230, 140), band = B.accent } },
			}
			n = lightboxes(K, V, { "left", "right", "back" }, math.max(6.9, V.H - 2.9), V.H - 0.45, LB[sub] or LB.indie, 2, 8)
		elseif kind == "pharmacy" then
			local nm = tostring(V.name or "약국")
			n = lightboxes(K, V, { "left", "right", "back" }, math.max(5.5, V.H - 2.4), V.H - 0.3, {
				{ title = nm, sub = "일반의약품 · 건강기능식품 · 처방전 조제 · 약사 상담", bg = PH.main, fg = WHITE, fg2 = C(220, 250, 230), band = WHITE },
				{ title = "환절기 건강 지키기", sub = "종합감기약 · 비타민 · 유산균 · 마스크", bg = PH.white, fg = PH.dark, fg2 = PH.main, band = PH.main },
			}, if sub == "gw" then 1 else 2, 7)
		elseif kind == "retail" and sub == "cosmetics" then
			n = lightboxes(K, V, { "back", "left", "right" }, 7.3, V.H - 0.45, {
				{ title = "올영세일", sub = "10.24 - 10.30 · 최대 70% · 올리브영 단독 기획", bg = OY.main, fg = OY.dark, side = true, sideC = C(250, 250, 248), sideC2 = C(255, 214, 90) },
				{ title = "OLIVE YOUNG 광안리점", sub = "K-BEAUTY · TAX FREE 외국인 즉시 환급", bg = OY.white, fg = OY.dark, fg2 = C(90, 120, 20), band = OY.main },
				{ title = "올리브영 어워즈 2026", sub = "스킨케어 · 메이크업 · 헤어 부문 1위 모음", bg = C(32, 36, 32), fg = WHITE, fg2 = OY.main, side = true, sideC = C(240, 190, 200), sideC2 = C(200, 230, 250) },
				{ title = "오늘드림", sub = "주문 후 3시간 내 도착 · 광안리점 픽업", bg = C(238, 70, 146), fg = WHITE, band = WHITE },
			}, 6)
		elseif kind == "retail" and (sub == "souvenir" or sub == "beach") then
			local top = 0
			for _, r in V.byName.WallRack or {} do
				top = math.max(top, r.max.Y)
			end
			if top == 0 and sub == "souvenir" then
				-- 벽 진열장이 없는 기념품 가게 (빵 · 과자 선물 위주): 낮은 벽 선반 위 넓은 벽에 라이트박스 여러 개
				local nm = tostring(V.name or "BUSAN")
				n = lightboxes(K, V, { "back", "left", "right" }, math.min(6.2, V.H - 3.2), V.H - 0.6, {
					{ title = nm, sub = "부산 여행 기념 빵 · 어묵 · 씨앗호떡 선물세트", bg = C(16, 30, 70), fg = WHITE, fg2 = C(255, 200, 80), band = C(220, 50, 60) },
					{ title = "광안대교 · 해운대 · 감천마을", sub = "부산 풍경 굿즈 · 엽서 · 마그넷 · 키링", bg = C(244, 238, 226), fg = C(16, 30, 70), fg2 = C(200, 40, 50), band = C(16, 30, 70) },
					{ title = "TAX FREE · 선물 포장", sub = "외국인 즉시 환급 · 쇼핑백 · 보냉 포장 무료", bg = C(200, 40, 50), fg = WHITE, band = WHITE },
				}, 3, 11)
			elseif top > 0 then
				n = lightboxes(K, V, { "back" }, top + 0.25, V.H - 0.35, if sub == "beach" then {
					{ title = "광안리 BEACH SHOP", sub = "튜브 · 파라솔 · 돗자리 대여 · 선케어 · 물놀이 용품", bg = C(20, 70, 140), fg = WHITE, fg2 = C(255, 214, 90), band = C(255, 214, 90) },
				} else {
					{ title = "BUSAN · 광안리 GWANGALLI", sub = "부산 여행 기념품 · 광안대교 굿즈 · 엽서 · 티셔츠", bg = C(16, 30, 70), fg = WHITE, fg2 = C(255, 200, 80), band = C(220, 50, 60) },
				}, 1)
			end
		end
		if n > 0 then
			note(K, "lightboxes " .. n)
		end
	end)
end

return T
