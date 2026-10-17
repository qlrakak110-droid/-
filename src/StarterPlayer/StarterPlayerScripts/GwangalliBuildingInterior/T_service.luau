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

-- Common.fixtures 와 같은 배치 (스위치 · 콘센트 · 온도조절기 · 비상벨 · 등록증 · 시계) 이지만, 매번 Common.wallSpot 전에
-- K.wallUsed 를 a 순으로 정렬 (정렬 안 된 목록이면 Common.wallSpot 의 구간 빼기가 틀려 큰 게시물과 겹침).
local function fixturesSorted(K: any, V: any, S: any)
	local function spot(walls: { string }, w: number, y0: number, y1: number, prefer: number?): (string?, CFrame?)
		sortWallUsed(K)
		return Common.wallSpot(K, walls, w, y0, y1, prefer)
	end
	local side = if V.door and V.door.x > 0 then "left" else "right"
	-- 조명 스위치는 ensureSwitch 가 이미 (프롬프트 자리에) 달았으면 생략 (스위치 둘 방지)
	local wn, dcf = nil, nil
	if not K._svSwitch then
		wn, dcf = spot({ side, if side == "left" then "right" else "left" }, 1.0, 3.8, 4.6, if side == "left" then -V.D / 2 + 3 else V.D / 2 - 3)
	end
	if wn and dcf then
		local plate = Props.switchPlate(K, dcf, 2)
		Interact.lightSwitch(K, plate, "실내 조명 스위치")
	end
	local wn2, d2 = spot({ "left", "right", "back" }, 0.5, 1.0, 1.7, 0)
	if wn2 and d2 then
		Props.outlet(K, d2)
	end
	local wn3, d3 = spot({ side, "back" }, 0.7, 4.5, 5.3, 0)
	if wn3 and d3 then
		Props.thermostat(K, d3)
	end
	local wn4, d4 = spot({ "right", "left" }, 1.0, 4.4, 5.4, 0)
	if wn4 and d4 then
		Props.fireBell(K, d4)
	end
	if S.license ~= false and #V.counters > 0 then
		local g = V.counters[1]
		local wn5, d5 = spot({ "back", "left", "right" }, 1.3, 5.0, 6.7, (g.min.X + g.max.X) / 2 - (V.x0 + V.x1) / 2 + 3)
		if wn5 and d5 then
			Props.license(K, d5, V.name)
		end
	end
	if S.clock ~= false then
		local h = math.min(V.H - 1.4, 7.6)
		local wn6, d6 = spot({ "back", "left", "right" }, 1.6, h - 0.8, h + 0.8, 0)
		if wn6 and d6 then
			local hr, mn = Props.clock(K, d6, 1.4, S.clockLook)
			Interact.clock(K, hr, mn, d6, 1.4)
		end
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
		-- 앞 1.9 스터드 안에 키 큰 가구가 서 있으면 (가려짐) 다른 자리
		if not hidden then
			local fmn, fmx = K.laabb(dcf * CF(0, 0, 1.0), V3(math.max(0.2, w - 0.3), y1 - y0, 1.9))
			for _, sd in K.V.solid do
				if not K.hidden[sd.part] and sd.max.Y > y0 + 0.4 and K.overlap(fmn, fmx, sd.min, sd.max, 0.02) then
					hidden = true
					break
				end
			end
			if not hidden then
				for _, r in K.reserved do
					if r.kind ~= "front" and r.kind ~= "staff" and r.max.Y > y0 + 0.4 and K.overlap(fmn, fmx, r.min, r.max, 0.02) then
						hidden = true
						break
					end
				end
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

-- 벽을 0.15 간격으로 훑어 w 폭 자리 찾기 (wallItemSpot 이 남는 짧은 구간을 건너뛸 때 쓰는 촘촘한 버전).
-- 검사: 벽 구간 · 쓰인 벽 · 맵 파트 · keep · 앞 1.9 안 키 큰 가구/예약 소품. 찾으면 기록하고 (wn, dcf) 반환
local function wallScan(K: any, walls: { string }, w: number, y0: number, y1: number, prefer: Vector3?, depth: number?, accept: ((CFrame) -> boolean)?): (string?, CFrame?)
	local V = K.V
	local best, bs = nil, math.huge
	for _, wn in walls do
		for _, sp in V:spans(wn, y0, y1, depth or 0.4) do
			local u = sp[1] + w / 2
			while u <= sp[2] - w / 2 + 1e-6 do
				if not wallBusy(K, wn, u - w / 2 - 0.1, u + w / 2 + 0.1, y0, y1) then
					local dcf = V:wall(wn, u, (y0 + y1) / 2, 0)
					local mn, mx = K.laabb(dcf * CF(0, 0, (depth or 0.4) / 2), V3(w, y1 - y0, depth or 0.4))
					local ok = not mapBlocked(K, mn, mx) and not K:hitsKeep(mn, mx) and (not accept or accept(dcf))
					if ok then
						local fmn, fmx = K.laabb(dcf * CF(0, 0, 1.0), V3(math.max(0.2, w - 0.3), y1 - y0, 1.9))
						for _, sd in V.solid do
							if not K.hidden[sd.part] and sd.max.Y > y0 + 0.4 and K.overlap(fmn, fmx, sd.min, sd.max, 0.02) then
								ok = false
								break
							end
						end
						if ok then
							for _, r in K.reserved do
								if r.kind ~= "front" and r.kind ~= "staff" and r.max.Y > y0 + 0.4 and K.overlap(fmn, fmx, r.min, r.max, 0.02) then
									ok = false
									break
								end
							end
						end
					end
					if ok then
						local sc = if prefer then (dcf.Position - prefer).Magnitude else math.abs(u)
						if sc < bs then
							best, bs = { wn = wn, u = u, dcf = dcf }, sc
						end
					end
				end
				u += 0.15
			end
		end
	end
	if best then
		addWallUsed(K, best.wn, best.u - w / 2 - 0.15, best.u + w / 2 + 0.15, y0, y1)
		return best.wn, best.dcf
	end
	return nil, nil
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

-- 천장 라인 조명 (매입 LED 줄 2~3 개, 맵 조명 · 설비 피해서). 불빛 2개
local function ceilingLines(K: any, V: any, col: Color3)
	local n = if V.W > 11 then 2 else 1
	local lit = 0
	K:free(function()
		for i = 1, n do
			local x = V.x0 + V.W * i / (n + 1)
			local z0, z1 = V.z0 + 1.6, V.z1 - 2.4
			-- 맵 천장 물건과 겹치면 옆으로
			for _, dx in { 0, 0.8, -0.8, 1.4, -1.4 } do
				local ok = true
				for _, r in V.parts do
					if r.max.Y > V.H - 0.6 and not r.shell and r.min.X < x + dx + 0.3 and r.max.X > x + dx - 0.3 and r.max.Z > z0 and r.min.Z < z1 then
						ok = false
						break
					end
				end
				if ok then
					local cx = x + dx
					K:box("LineLightTrim", V3(0.32, 0.03, z1 - z0 + 0.12), CF(cx, V.H - 0.02, (z0 + z1) / 2), Look.white)
					local l = K:box("LineLightLED", V3(0.2, 0.03, z1 - z0), CF(cx, V.H - 0.04, (z0 + z1) / 2), Look.neon(col))
					if lit < 2 then
						K:light(l, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 14, Brightness = 0.9, Angle = 120, Color = col })
						lit += 1
					end
					break
				end
			end
		end
	end)
end

-- 천장 평판 조명 + 불빛 (맵 · Common 천장 물건 피해서). n 개, 그중 lit 개에 불빛
local function addCeilLights(K: any, V: any, n: number, lit: number, kind: string?)
	local placed, lights = 0, 0
	local cols = math.max(1, math.min(n, math.floor(V.W / 4)))
	local cands = {}
	for i = 1, cols do
		for _, fz in { 0.45, 0.3, 0.6 } do
			table.insert(cands, V3(V.x0 + V.W * (i - 0.5) / cols, 0, V.z0 + V.D * fz))
		end
	end
	for _, p in cands do
		if placed >= n then
			break
		end
		for _, dx in { 0, 1.0, -1.0 } do
			if Common.ceilFree(K, p.X + dx, p.Z, 1.0) then
				local withLight = lights < lit and #K.lights < (V.maxLights or 8) - 1
				if kind == "line" then
					K:free(function()
						K:box("LineLightTrim", V3(3.2, 0.03, 0.32), CF(p.X + dx, V.H - 0.02, p.Z), Look.white)
						local l = K:box("LineLightLED", V3(3.0, 0.03, 0.2), CF(p.X + dx, V.H - 0.04, p.Z), Look.lampNeutral)
						if withLight then
							K:light(l, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 14, Brightness = 0.9, Angle = 120, Color = Look.neutralLight })
						end
					end)
				else
					Props.panelLight(K, p.X + dx, p.Z, { light = withLight, range = 15, bright = 0.85, color = Look.neutralLight, glow = Look.lampNeutral })
				end
				if withLight then
					lights += 1
				end
				Common.useCeil(K, p.X + dx, p.Z)
				placed += 1
				break
			end
		end
	end
end

-- 프롬프트용 작은 벽 조작판 (프롬프트를 둘 수 있는 벽 자리). 반환: 판 파트
local function promptPanel(K: any, walls: { string }, label: string, prefer: Vector3?, look: any?): BasePart?
	local accept = function(d: CFrame): boolean
		return Interact.canPrompt(K, (d * CF(0, 0, 0.15)).Position)
	end
	local wn, d
	if prefer then
		wn, d = spotNear(K, walls, 0.8, 3.9, 4.9, prefer, accept, 0.2)
	else
		wn, d = wallItemSpot(K, walls, 0.8, 3.9, 4.9, nil, accept, 0.2)
	end
	if not (wn and d) then
		return nil
	end
	local base = d * CF(0, 0.05, 0)
	local p = K:plate("CtrlPanel", 0.62, 0.86, 0.07, base, look or Look.white)
	K:disc("CtrlPanelKnob", 0.3, 0.08, base * CF(0, 0.12, 0.1) * ANG(PI / 2, 0, 0), Look.grey)
	K:plate("CtrlPanelLED", 0.06, 0.06, 0.08, base * CF(0.2, 0.32, 0.03), Look.ledGreen)
	txt(K, "CtrlPanelText", 0.56, 0.16, base * CF(0, -0.27, 0.075), label, INK, nil, { font = F.GothamBold })
	return p
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
	if oo.pin == false and not oo.noFrame then
		-- 벽걸이 아크릴 꽂이 (검은 테)
		K:plate("PaperHolder", w + 0.12, h + 0.12, 0.02, dcf, lk(C(36, 36, 40)))
		dcf = dcf * CF(0, 0, 0.02)
	end
	local sheet = K:plate("Paper", w, h, 0.012, dcf * ANG(0, 0, oo.tilt or 0), lk(bg))
	local d = dcf * ANG(0, 0, oo.tilt or 0) * CF(0, 0, 0.013)
	if oo.band then
		K:plate("PaperBand", w, th * 0.98, 0.004, d * CF(0, h / 2 - th / 2, 0), lk(oo.band))
	end
	txt(K, "PaperTitle", w * 0.9, th * 0.78, d * CF(0, h / 2 - th / 2, 0.005), title, oo.titleFg or (if oo.band then WHITE else INK), oo.band or bg, { font = oo.titleFont or F.GothamBlack, d = 0.004 })
	if body then
		txt(K, "PaperBody", w * 0.88, (h - th) * 0.9, d * CF(0, -th / 2, 0.005), body, oo.fg or C(44, 44, 50), bg, { font = oo.font or F.GothamMedium, d = 0.004, align = oo.align })
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
	txt(K, "CertBody", w * 0.72, h * 0.66, d * CF(0, h * 0.06, 0), title .. "\n\n" .. body, C(40, 40, 46), Look.paper.c, { font = F.GothamMedium, d = 0.004 })
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

-- 벽걸이 에어컨 (작은 가게 · 사무실 필수품). dcf = 벽 (가운데)
local function wallAC(K: any, dcf: CFrame, w: number?)
	local aw = w or 2.9
	K:rbox("ACBody", V3(aw, 0.95, 0.75), 0.25, dcf * CF(0, 0, 0.38) * ANG(0, PI / 2, 0) * ANG(0, -PI / 2, 0), lk(C(246, 246, 244)))
	K:plate("ACFace", aw - 0.2, 0.55, 0.02, dcf * CF(0, 0.12, 0.76), lk(C(236, 236, 234)))
	K:plate("ACVent", aw - 0.4, 0.1, 0.03, dcf * CF(0, -0.36, 0.72), Look.charcoal)
	K:plate("ACFlap", aw - 0.4, 0.06, 0.06, dcf * CF(0, -0.42, 0.72) * ANG(-0.5, 0, 0), lk(C(220, 220, 218)))
	K:plate("ACLED", 0.3, 0.12, 0.01, dcf * CF(aw / 2 - 0.45, -0.12, 0.775), lk(C(80, 160, 255), M.Neon, { t = 0.2 }))
	txt(K, "ACBrand", 0.6, 0.12, dcf * CF(-aw / 2 + 0.55, -0.15, 0.775), "WHISEN", C(150, 150, 150), nil, { font = F.GothamBold })
	K:seg("ACPipe", (dcf * CF(aw / 2 - 0.2, -0.3, 0.1)).Position, (dcf * CF(aw / 2 + 0.2, -0.6, 0.1)).Position, 0.1, Look.white)
end

-- 매물 사진 액자 (아파트 · 오피스텔 그림). dcf, w x h
local function buildingPhoto(K: any, dcf: CFrame, w: number, h: number, rng: () -> number, caption: string)
	Props.frame(K, dcf, w, h, { frame = Look.blackMetal, mat = lk(C(170, 206, 236)), border = 0.06, depth = 0.06 })
	local d = dcf * CF(0, 0, 0.045)
	local iw, ih = w - 0.3, h - 0.3
	K:plate("PhotoGround", iw, ih * 0.18, 0.006, d * CF(0, -ih / 2 + ih * 0.09, 0), lk(C(120, 150, 110)))
	local n = 2 + math.floor(rng() * 2)
	for i = 1, n do
		local bw = iw * (0.18 + rng() * 0.1)
		local bh = ih * (0.45 + rng() * 0.35)
		local x = -iw / 2 + iw * (i - 0.5) / n
		K:plate("PhotoTower", bw, bh, 0.008, d * CF(x, -ih / 2 + ih * 0.18 + bh / 2, 0.001), lk(pickR(rng, { C(236, 232, 226), C(210, 214, 220), C(200, 186, 170) })))
		if not lo(K) then
			for k = 1, 5 do
				K:plate("PhotoWindows", bw * 0.8, 0.02, 0.009, d * CF(x, -ih / 2 + ih * 0.18 + bh * k / 6, 0.002), lk(C(90, 120, 150)))
			end
		end
	end
	txt(K, "PhotoCaption", w * 0.9, 0.22, dcf * CF(0, -h / 2 - 0.2, 0.01), caption, C(60, 60, 64), nil, { font = F.GothamBold, d = 0.01 })
end

-- 액자 포스터 (머리띠 제목 + 본문). dcf 벽, w x h
local function posterFrame(K: any, dcf: CFrame, w: number, h: number, title: string, body: string, band: Color3, o: any?)
	local oo: any = o or {}
	Props.frame(K, dcf, w, h, { frame = oo.frame or Look.alu, mat = lk(oo.bg or C(250, 250, 248)), border = 0.06, depth = 0.06 })
	local d = dcf * CF(0, 0, 0.045)
	local iw, ih = w - 0.24, h - 0.24
	local bh = ih * 0.3
	K:plate("PosterBand", iw, bh, 0.006, d * CF(0, ih / 2 - bh / 2, 0), lk(band))
	txt(K, "PosterTitle", iw * 0.9, bh * 0.66, d * CF(0, ih / 2 - bh / 2, 0.008), title, WHITE, nil, { font = F.GothamBlack, d = 0.004 })
	txt(K, "PosterBody", iw * 0.88, (ih - bh) * 0.82, d * CF(0, -bh / 2, 0.008), body, oo.fg or C(40, 44, 52), nil, { font = F.GothamBold, d = 0.004 })
end

-- 남은 벽 채우기: 포스터 목록을 빈 벽 자리에 (최대 n 장, 가려지지 않는 자리만)
local function fillPosters(K: any, list: { any }, n: number, walls: { string }?)
	local placed = 0
	for i, pst in list do
		if placed >= n then
			break
		end
		local w, h = pst.w or 1.5, pst.h or 2.0
		local y0 = pst.y or 3.9
		local wn, d = wallItemSpot(K, walls or { "left", "right", "back" }, w + 0.2, y0, y0 + h + 0.1, (i % 2 == 0) and 3 or -3)
		if wn and d then
			posterFrame(K, d * CF(0, 0.05, 0), w, h, pst[1], pst[2], pst[3] or C(30, 60, 120), pst)
			placed += 1
		end
	end
	return placed
end

local POSTERS = {
	hotel = { { "광안리 M 드론쇼", "매주 토요일\n20:00 · 22:00\n객실 오션뷰에서 관람", C(30, 40, 90) }, { "ROOFTOP BAR", "OPEN 18:00 - 01:00\n시그니처 칵테일\n15,000원~", C(60, 30, 50) }, { "조식 뷔페", "2F 레스토랑\n06:30 - 10:00\n성인 25,000원", C(120, 70, 30) } },
	residence = { { "층간소음 줄이기", "뛰지 않기 · 매트 깔기\n밤 10시 이후\n가전 사용 자제", C(150, 60, 140) }, { "재활용 분리배출", "종이 · 캔 · 플라스틱\n비닐 · 스티로폼\n월 · 목 18시 이후", C(40, 140, 90) }, { "엘리베이터 안전수칙", "문에 기대지 마세요\n어린이는 보호자와\n고장 시 비상벨", C(200, 120, 30) } },
	realty = { { "전세사기 예방", "등기부등본 확인\n선순위 채권 확인\n전입신고 · 확정일자", C(200, 40, 50) }, { "거래 신고 안내", "부동산 거래 계약 후\n30일 이내 신고\n(부동산거래신고법)", C(24, 50, 100) }, { "임대차 계약 체크", "보증보험 가입 여부\n관리비 · 수리 범위\n특약 사항 확인", C(30, 120, 90) } },
	laundry = { { "운동화 세탁", "1켤레 6,000원\n키즈 4,000원\n2일 소요", C(30, 110, 200) }, { "이불 · 커튼", "극세사 이불 15,000원~\n커튼 m 당 5,000원\n3일 소요", C(210, 120, 30) }, { "명품 가방 클리닝", "가죽 · 스웨이드\n염색 · 수선 상담\n7일 소요", C(60, 40, 30) } },
	office = { { "2026 목표", "고객 만족 100%\n안전 사고 ZERO\n매출 120%", C(30, 60, 110) }, { "회의실 예약", "사내 그룹웨어에서\n예약 후 사용\n사용 후 정리", C(60, 60, 70) }, { "보안 수칙", "자리 비울 때 PC 잠금\n출입증 패용\n서류 파쇄", C(200, 40, 50) } },
	bank = { { "정기적금 특판", "12개월 연 4.5%\n월 최대 50만원\n선착순 1만 좌", C(0, 90, 160) }, { "보이스피싱 주의", "은행은 전화로\n비밀번호를 묻지 않습니다\n☎ 112 · 1332", C(200, 40, 50) }, { "외화 환전", "인터넷 환전 시\n환율 우대 90%\n영업점 수령", C(30, 130, 90) }, { "주택청약종합저축", "매월 2만~50만원\n소득공제 혜택\n청년 우대형", C(120, 80, 160) } },
	clinic = { { "독감 예방접종", "2026-27 시즌\n만 65세 이상 무료\n4가 백신", C(20, 140, 130) }, { "손 씻기 6단계", "손바닥 · 손등 · 손가락\n엄지 · 손톱 밑\n30초 이상", C(30, 110, 200) }, { "혈압 관리", "목표 120/80 미만\n싱겁게 먹기\n하루 30분 걷기", C(200, 60, 60) } },
	academy = { { "겨울방학 특강", "수학 · 영어 집중반\n12월 22일 개강\n선착순 15명", C(230, 120, 30) }, { "무료 레벨 테스트", "예약제 운영\n결과 상담 30분\n☎ 051-000-0000", C(30, 90, 180) }, { "셔틀버스 안내", "광안 · 민락 · 남천\n18:00 · 21:30\n2대 운행", C(40, 140, 90) } },
}

-- 흰 아크릴 요금표 (빛나지 않는 글자: 밝은 판에서 또렷하게). items = { {이름, 가격} ... }
local function priceBoard(K: any, dcf: CFrame, w: number, h: number, title: string, items: { { string } }, o: any?)
	local oo: any = o or {}
	local head: Color3 = oo.head or C(24, 50, 110)
	local acc: Color3 = oo.accent or C(210, 40, 50)
	K:plate("PriceBoardFrame", w + 0.14, h + 0.14, 0.08, dcf, lk(head))
	K:plate("PriceBoard", w, h, 0.1, dcf, lk(oo.bg or C(252, 252, 250)))
	local th = math.min(0.8, h * 0.2)
	K:plate("PriceBoardHead", w, th, 0.11, dcf * CF(0, h / 2 - th / 2, 0), lk(head))
	txt(K, "PriceBoardTitle", w * 0.9, th * 0.7, dcf * CF(0, h / 2 - th / 2, 0.115), title, WHITE, nil, { font = F.GothamBlack })
	local cols = oo.cols or 2
	local rows = math.ceil(#items / cols)
	local cw = (w - 0.3) / cols
	local rh = (h - th - 0.3) / rows
	for i, it in items do
		local c = (i - 1) // rows
		local r = (i - 1) % rows
		local x0 = -w / 2 + 0.15 + c * cw
		local y = h / 2 - th - 0.15 - rh * (r + 0.5)
		-- 인쇄 글자: 판과 같은 바탕색을 깔아 (불투명 글자판) 작은 글자도 또렷하게
		local paperC: Color3 = oo.bg or C(252, 252, 250)
		txt(K, "PriceItem", cw * 0.6, rh * 0.62, dcf * CF(x0 + cw * 0.32, y, 0.105), it[1], oo.ink or C(30, 34, 46), paperC, { font = F.GothamBold, align = "Left", d = 0.01 })
		txt(K, "PriceValue", cw * 0.34, rh * 0.62, dcf * CF(x0 + cw * 0.8, y, 0.105), it[2], acc, paperC, { font = F.GothamBlack, align = "Right", d = 0.01 })
		if r < rows - 1 and not lo(K) then
			K:plate("PriceRule", cw * 0.94, 0.02, 0.102, dcf * CF(x0 + cw * 0.5, y - rh / 2, 0), lk(C(220, 222, 226)))
		end
	end
	if cols > 1 then
		K:plate("PriceDivider", 0.03, h - th - 0.3, 0.102, dcf * CF(-w / 2 + 0.15 + cw, -th / 2, 0), lk(C(210, 212, 216)))
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

-- 아레카야자 (로비 대형 화분): 원통 화분 + 줄기 3~4 + 끝에 늘어진 잎 (얇은 판 · 아래로 휨). pcf 바닥 가운데
local function palmTree(K: any, pcf: CFrame, h: number, dia: number, potL: any?, seed: number?): boolean
	if not claim(K, pcf, V3(dia + 0.6, h, dia + 0.6), 0.05, "plant") then
		return false
	end
	local rng = mkRng(seed or 7)
	-- 줄기는 방 가운데 쪽으로만 기울임 (벽 쪽 잎이 벽을 뚫지 않게)
	local toC = pcf:VectorToObjectSpace(V3(-pcf.Position.X, 0, -pcf.Position.Z))
	local baseA = if toC.Magnitude > 0.1 then math.atan2(toC.Z, toC.X) else 0
	local ph = dia * 0.85
	potL = potL or lk(C(236, 232, 224), M.Concrete)
	K:vcyl("PalmPot", ph, dia, pcf * CF(0, ph / 2, 0), potL)
	K:vcyl("PalmPotRim", 0.1, dia + 0.08, pcf * CF(0, ph - 0.05, 0), lk(darker(potL.c, 0.12), potL.m))
	K:vcyl("PalmSoil", 0.06, dia - 0.15, pcf * CF(0, ph - 0.08, 0), Look.soil)
	local stems = if lo(K) then 3 else 4
	local leafA = lk(C(70, 120, 60), M.Grass)
	local leafB = lk(C(96, 146, 70), M.Grass)
	for i = 1, stems do
		local a = baseA + ((i - 0.5) / stems - 0.5) * PI * 1.1 + (rng() - 0.5) * 0.3
		local lean = 0.06 + rng() * 0.08
		local top = (h - ph) * (0.62 + rng() * 0.3)
		local base = pcf * CF(math.cos(a) * dia * 0.12, ph - 0.05, math.sin(a) * dia * 0.12)
		local tipP = (pcf * CF(math.cos(a) * (dia * 0.12 + top * lean), ph + top, math.sin(a) * (dia * 0.12 + top * lean))).Position
		K:seg("PalmStem", base.Position, tipP, 0.07, lk(C(150, 160, 90), M.Wood))
		local nf = if lo(K) then 3 else 5
		for f = 1, nf do
			local fa = a + (f - (nf + 1) / 2) * 0.75 + rng() * 0.2
			local dir = V3(math.cos(fa), 0, math.sin(fa))
			local len = 1.15 + rng() * 0.4
			local droop = 0.45 + rng() * 0.35
			-- 잎줄기 방향: 바깥 + 아래로 처짐. 판 (폭 0.55 · 두께 0.03 · 길이 len)
			local mid = tipP + dir * (len * 0.45) + V3(0, -len * 0.18 * droop, 0)
			local look = CFrame.lookAt(mid, mid + dir + V3(0, -droop * 0.6, 0))
			K:box("PalmFrond", V3(0.55, 0.03, len), look * ANG(0, 0, (rng() - 0.5) * 0.6), if (i + f) % 2 == 0 then leafA else leafB)
			if hi(K) then
				K:box("PalmFrondTip", V3(0.36, 0.03, len * 0.45), look * CF(0, -len * 0.12 * droop, -len * 0.62) * ANG(-droop * 0.7, 0, 0), leafA)
			end
		end
	end
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

-- 오래된 맨션 · 빌라 · 아파트 공동현관 (테라조 바닥 · 페인트 벽 · 경비실 창 · 알루미늄 우편함)
-- 아니면 신축 오피스텔 · 브랜드 아파트 (대형 타일 · 우드 루버 · 라인 조명 · 디지털 게시판)
local function resOld(V: any): boolean
	local n = V.name or ""
	local u = string.upper(n)
	for _, k in { "맨션", "빌라", "연립", "주택", "아파트", "MANSION", "VILLA" } do
		if string.find(n, k, 1, true) or string.find(u, k, 1, true) then
			return true
		end
	end
	return false
end

function T.style(V: any): any
	local t = V.type
	local skip = { fixtures = true }
	if t == "lobby" then
		if isMotel(V) then
			local nm = V.name or ""
			if string.find(nm, "야자", 1, true) or string.find(string.upper(nm), "PALM", 1, true) then
				-- 열대 휴양지 콘셉트 (야자수): 밝은 석재 바닥 · 라탄 · 원목 천장
				return {
					chair = false, stool = {}, table = false, counter = { front = "panel", frontL = lk(C(120, 90, 60), M.Wood), topL = Look.marbleWhite },
					floor = { look = lk(C(206, 196, 178), M.Limestone), tile = 2.4, grout = lk(C(160, 150, 134)) },
					ceiling = { skin = lk(C(168, 134, 98), M.Wood) }, base = lk(C(70, 52, 40), M.Wood),
					lower = { kind = "paint", h = 3.4, look = lk(C(150, 116, 80), M.Wood), cap = Look.goldMetal, walls = { "left", "right", "back" } },
					lights = { kind = "downlight", n = math.clamp(math.floor(V.W / 6), 3, 6), color = C(255, 210, 160), glow = Look.lampWarm },
					mat = { look = lk(C(40, 60, 44), M.Fabric), text = string.upper(nm) }, cctv = true, clock = false, license = true, skip = skip,
				}
			end
			return {
				chair = false, stool = {}, table = false, counter = { front = "panel", frontL = lk(C(40, 34, 40)), topL = Look.marbleBlack },
				floor = { look = lk(C(54, 50, 52), M.Slate), tile = 2.0, grout = lk(C(30, 30, 32)) },
				ceiling = { skin = lk(C(40, 36, 42)) }, base = Look.black,
				lower = { kind = "paint", h = 3.4, look = lk(C(64, 48, 58), M.Wood), cap = Look.goldMetal, walls = { "left", "right", "back" } },
				lights = { kind = "downlight", n = math.clamp(math.floor(V.W / 6), 3, 6), color = C(255, 196, 150), glow = Look.lampWarm },
				mat = { look = lk(C(60, 20, 30), M.Fabric), text = string.upper(V.name or "MOTEL") }, cctv = true, clock = false, license = true, skip = skip,
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
		if resOld(V) then
			-- 90~2000년대 맨션: 테라조 바닥 · 연녹색 페인트 아랫벽 + 원목 몰딩 · 사각 형광 등기구
			return {
				chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey }, stool = {}, table = { top = Look.oak, base = Look.blackMetal },
				counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
				floor = { look = lk(C(200, 192, 178), M.Granite), tile = 1.6, grout = lk(C(150, 140, 126)) },
				ceiling = { skin = lk(C(240, 238, 230), M.Plaster) }, base = lk(C(104, 80, 60), M.Wood),
				lower = { kind = "paint", h = 3.4, look = lk(C(170, 192, 176), M.SmoothPlastic), cap = lk(C(124, 94, 68), M.Wood), walls = { "left", "right" } },
				lights = { kind = "none" },
				plants = { "snake", "ficus", "monstera" }, mat = { look = lk(C(120, 40, 40), M.Fabric) }, cctv = true, clock = false, license = false, skip = skip,
			}
		end
		return {
			chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey }, stool = {}, table = { top = Look.oak, base = Look.blackMetal },
			counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
			floor = { look = if warm then lk(C(218, 210, 196), M.Marble) else lk(C(204, 206, 208), M.Marble), tile = 2.0, grout = lk(C(170, 166, 160)) },
			ceiling = { skin = lk(C(242, 242, 238), M.Plaster) }, base = lk(C(60, 60, 62), M.Slate),
			lower = { kind = "tile", h = 4.0, look = if warm then lk(C(214, 204, 186), M.Limestone) else lk(C(190, 192, 194), M.Marble), grout = lk(C(160, 156, 150)), tw = 2.0, th = 1.0, walls = { "left", "right" } },
			lights = { kind = "downlight", n = 3, color = Look.neutralLight },
			plants = { "snake", "ficus", "monstera" }, mat = { look = lk(C(60, 60, 62), M.Fabric) }, cctv = true, clock = false, license = false, skip = skip,
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
			lights = { kind = "panel", n = 4 }, mat = { look = lk(C(40, 70, 120), M.Fabric) }, cctv = true, clock = true, license = true, skip = skip,
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
-- 6. 공통: 조명 스위치 보장 · 사무 책상
---------------------------------------------------------------------------------------------------

-- Common 의 스위치 프롬프트가 서버 앵커 근처라 빠졌으면, 프롬프트를 둘 수 있는 벽에 하나 더
local function ensureSwitch(K: any, V: any)
	for _, p in K.prompts do
		if p.ObjectText == "실내 조명 스위치" then
			return
		end
	end
	local wn, dcf = wallItemSpot(K, { "left", "right", "back" }, 0.9, 3.9, 4.5, nil, function(d: CFrame)
		return Interact.canPrompt(K, d.Position)
	end, 0.2)
	if wn and dcf then
		local plate = Props.switchPlate(K, dcf, 3)
		Interact.lightSwitch(K, plate, "실내 조명 스위치")
		K._svSwitch = true
	end
end

-- 사무 책상 (상판 + 옆판 + 앞 가림판 + 서랍). pcf = 책상 바닥 가운데, +Z = 손님 쪽 (직원은 -Z 에서 +Z 를 봄)
-- 반환: 상판 윗면 프레임 (같은 방향)
local function officeDesk(K: any, pcf: CFrame, w: number, d: number, topL: any, bodyL: any?): CFrame
	local h = 2.5
	local body = bodyL or lk(C(236, 234, 228))
	K:box("DeskTop", V3(w, 0.12, d), pcf * CF(0, h - 0.06, 0), topL)
	K:box("DeskEdge", V3(w + 0.02, 0.04, d + 0.02), pcf * CF(0, h - 0.13, 0), lk(darker(topL.c, 0.3), topL.m))
	for _, sx in { -1, 1 } do
		K:box("DeskSide", V3(0.1, h - 0.12, d - 0.1), pcf * CF(sx * (w / 2 - 0.08), (h - 0.12) / 2, 0), body)
	end
	K:box("DeskModesty", V3(w - 0.3, 1.3, 0.06), pcf * CF(0, h - 0.85, d / 2 - 0.25), body)
	-- 서랍 (직원 오른쪽 = -X 쪽 아래)
	local px = -(w / 2 - 0.7)
	K:box("DeskPedestal", V3(1.1, h - 0.4, d - 0.5), pcf * CF(px, (h - 0.4) / 2 + 0.06, 0.05), body)
	for j = 0, 2 do
		local y = 0.45 + j * 0.62
		K:plate("DeskDrawer", 1.0, 0.54, 0.02, CFrame.fromMatrix((pcf * CF(px, y, -d / 2 + 0.3)).Position, -pcf.XVector, Vector3.yAxis, -pcf.ZVector), lk(darker(body.c, 0.04)))
		K:plate("DeskPull", 0.4, 0.05, 0.04, CFrame.fromMatrix((pcf * CF(px, y + 0.17, -d / 2 + 0.32)).Position, -pcf.XVector, Vector3.yAxis, -pcf.ZVector), Look.brushed)
	end
	return pcf * CF(0, h, 0)
end

-- 책상 위 업무 소품 (top = officeDesk 반환, +Z 손님 쪽): 모니터 · 키보드 · 전화 · 명패 · 서류함
local function deskKit(K: any, top: CFrame, w: number, d: number, nameplate: string?, screen: string?, rng: () -> number)
	monitor(K, top * CF(0.3, 0, d * 0.22) * ANG(0, PI, 0), 1.7, screen or "매물 관리 시스템\n광안동 아파트 128건\n신규 등록 3건", C(236, 242, 248))
	keyboard(K, top * CF(0.4, 0, -d * 0.18) * ANG(0, PI, 0), 1.2)
	deskPhone(K, top * CF(-w / 2 + 0.6, 0, d * 0.1) * ANG(0, PI, 0))
	if nameplate then
		local np = top * CF(w * 0.15, 0, d / 2 - 0.2)
		K:wedge("NamePlate", V3(1.5, 0.32, 0.3), np * CF(0, 0.16, 0) * ANG(0, PI, 0), Look.walnut)
		txt(K, "NamePlateText", 1.36, 0.2, CFrame.fromMatrix((np * CF(0, 0.165, 0)).Position, np.XVector, (np.YVector - np.ZVector).Unit, (np.ZVector + np.YVector).Unit), nameplate, Look.goldMetal.c, Look.black.c, { font = F.GothamBold, d = 0.01 })
	end
	if not lo(K) then
		-- 서류 트레이 2단 + 서류
		local tr = top * CF(w / 2 - 0.6, 0, d * 0.05)
		for j = 0, 1 do
			K:box("FileTray", V3(0.8, 0.04, 1.05), tr * CF(0, 0.05 + j * 0.3, 0), Look.blackMetal)
			paperStack(K, tr * CF(0, 0.07 + j * 0.3, 0), 0.7, 0.95, 2 + j)
		end
		K:box("FileTrayPost", V3(0.05, 0.36, 0.05), tr * CF(0.37, 0.2, 0.45), Look.blackMetal)
		K:box("FileTrayPost", V3(0.05, 0.36, 0.05), tr * CF(-0.37, 0.2, 0.45), Look.blackMetal)
		penCup(K, top * CF(-w / 2 + 1.35, 0, d * 0.2))
		K:vcyl("Mug", 0.32, 0.26, top * CF(-w / 2 + 1.1, 0.16, -d * 0.25), lk(pickR(rng, { C(240, 240, 236), C(40, 70, 120), C(200, 70, 60) })))
		paperStack(K, top * CF(-0.9, 0, -d * 0.12) * ANG(0, 0.2, 0), 0.7, 0.95, 3)
	end
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
			txt(K, "DeskCheckIn", ow * 0.86, 0.22, dd * CF(0, fh * 0.62 - 0.85, 0.07), "CHECK-IN 15:00  ·  CHECK-OUT 11:00", darker(th.trim.c, 0.5), nil, { font = F.GothamMedium })
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
	if not best or bw < 2.4 then
		-- 뒷벽이 엘리베이터로 막힌 로비: 데스크 가까운 옆벽 높은 곳에 로고 + 시계
		local side = if desk.c.X > (V.x0 + V.x1) / 2 then "right" else "left"
		local p = V3(desk.c.X, 0, desk.c.Z)
		local w = 4.2
		local y0 = math.max(6.3, math.min(V.H - 3.3, 7.0))
		local wn2, d = spotNear(K, { side, if side == "right" then "left" else "right" }, w + 0.4, y0, y0 + 2.6, p)
		if wn2 and d then
			K:free(function()
				local c = d * CF(0, 0, 0)
				K:plate("LogoPanel", w + 0.3, 2.5, 0.08, c, lk(darker(th.wallBack.c, 0.1)))
				K:plate("LogoPanelTrim", w + 0.4, 0.06, 0.1, c * CF(0, -1.26, 0), th.trim)
				metalText(K, "HotelLogo", c * CF(0, 0.6, 0.09), w * 0.9, 0.7, string.upper(V.name or "HOTEL"), th.accent, F.GothamMedium, 0.6)
				worldClock(K, c * CF(-1.0, -0.35, 0.08), 0.8, "SEOUL", 0, th.trim, lighter(th.accent, 0.3))
				worldClock(K, c * CF(1.0, -0.35, 0.08), 0.8, "LONDON", -8, th.trim, lighter(th.accent, 0.3))
			end)
		else
			note(K, "feature wall: no span")
		end
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
		local cities = { { "SEOUL", 0 }, { "LONDON", -8 }, { "NEW YORK", -13 }, { "SYDNEY", 2 } }
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
local function hotelLounge(K: any, V: any, th: any, rng: () -> number, opt: any?): any
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
		-- 맵 의자가 없는 로비: 러그 옆 벽에 2~3인 소파
		local rug = V:first("Rug")
		local pref = (opt and opt.pref) or (if rug then rug.c else V3(V.x0, 0, 0))
		for _, len in { 4.6, 3.8 } do
			local wn, pcf = wallFloorSpot(K, (opt and opt.walls) or { "left", "right" }, len + 0.2, 2.5, 3.4, pref, 0.1, "sofa")
			if wn and pcf then
				sofa(K, pcf * CF(0, 0, 0.05), len, th.fab, Look.walnut)
				local mn0, mx0 = K.laabb(pcf * CF(0, 1.7, 0), V3(len + 0.2, 3.4, 2.5))
				table.insert(groups, { face = snap(pcf.ZVector), box = { min = mn0, max = mx0, c = (mn0 + mx0) / 2, w = len, d = 2.5 } })
				break
			end
		end
		if #groups == 0 then
			return out
		end
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
				out.artHits = {}
				for _, fx in { 0, -0.3, 0.3, -0.45, 0.45 } do
					table.insert(out.artHits, K:plate("ArtHit", 0.4, 0.4, 0.02, dcf * CF(aw * fx, -ah / 2 + 0.3, 0.18), { c = C(0, 0, 0), t = 1 }))
				end
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
-- 음료 자판기 (모텔 · 호텔 로비). pcf 바닥 가운데, +Z 앞. 폭 2.4 · 깊이 1.9 · 높이 6.1
local function vendingMachine(K: any, pcf: CFrame, rng: () -> number)
	local w, d, h = 2.4, 1.9, 6.1
	local body = lk(C(28, 64, 140), M.SmoothPlastic, { r = 0.1 })
	K:box("VendPlinth", V3(w - 0.1, 0.3, d - 0.1), pcf * CF(0, 0.15, -0.05), Look.charcoal)
	local f = CFrame.fromMatrix((pcf * CF(0, 0, d / 2 - 0.05)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector)
	-- 몸통: 뒤 덩어리 + 진열창 둘레 테 (진열창 안은 비어 있어야 캔이 보임)
	local rec = 0.62
	local ww0 = w * 0.66
	local wx0 = -w / 2 + 0.12 + ww0 / 2
	local wy0b, wy1b = 2.35, h - 0.95
	local bh = h - 0.3
	K:rbox("VendBody", V3(w, bh, d - rec), 0.08, f * CF(0, 0.3 + bh / 2, -rec - (d - rec) / 2), body)
	K:box("VendBody", V3(w - ww0 - 0.12, bh, rec), f * CF(wx0 + ww0 / 2 + (w - ww0 - 0.12) / 2, 0.3 + bh / 2, -rec / 2), body)
	K:box("VendBody", V3(0.12, bh, rec), f * CF(-w / 2 + 0.06, 0.3 + bh / 2, -rec / 2), body)
	K:box("VendBody", V3(ww0, h - wy1b, rec), f * CF(wx0, wy1b + (h - wy1b) / 2, -rec / 2), body)
	K:box("VendBody", V3(ww0, wy0b - 0.25 - 0.3, rec), f * CF(wx0, 0.3 + (wy0b - 0.55) / 2, -rec / 2), body)
	-- 위 간판 (발광)
	K:plate("VendHeader", w - 0.2, 0.62, 0.04, f * CF(0, h - 0.5, 0.01), Look.neon(C(240, 246, 255), 0.05))
	txt(K, "VendHeaderText", w - 0.4, 0.46, f * CF(0, h - 0.5, 0.04), "시원한 음료  COLD DRINK", C(20, 46, 120), nil, { font = F.GothamBlack, glow = 1 })
	-- 진열창: 뒤 발광판 + 선반 4 줄 + 캔 · 병 + 가격 띠 + 유리
	local ww = w * 0.66
	local wx = -w / 2 + 0.12 + ww / 2
	local wy0, wy1 = 2.35, h - 0.95
	K:plate("VendBacklight", ww, wy1 - wy0 + 0.25, 0.02, f * CF(wx, (wy0 + wy1) / 2 - 0.1, -rec + 0.01), Look.neon(C(236, 244, 255), 0.15))
	local rows = 4
	local rh = (wy1 - wy0) / rows
	local per = if lo(K) then 3 else 5
	local cols = { C(220, 40, 40), C(240, 200, 40), C(40, 160, 90), C(30, 30, 34), C(250, 140, 40), C(60, 120, 220), C(240, 240, 240), C(140, 60, 160) }
	local prices = { "1,500   1,500   1,800   2,000   1,200", "2,000   1,800   1,500   2,500   2,000", "1,200   1,200   1,500   1,800   1,500", "2,500   2,000   2,000   1,800   3,000" }
	for r = 1, rows do
		local y = wy0 + rh * (r - 1)
		K:plate("VendShelf", ww, 0.06, 0.6, f * CF(wx, y + 0.08, -0.3), Look.chrome)
		for c = 1, per do
			local x = wx - ww / 2 + (c - 0.5) * (ww / per)
			local col = cols[math.floor(rng() * #cols) + 1]
			if (r + c) % 3 == 0 then
				-- 페트병
				K:vcyl("VendBottle", rh * 0.62, 0.26, f * CF(x, y + 0.12 + rh * 0.31, -0.25), lk(col, M.Glass, { t = 0.25 }))
				K:vcyl("VendBottleCap", 0.08, 0.14, f * CF(x, y + 0.16 + rh * 0.62, -0.25), lk(C(240, 240, 240)))
			else
				K:vcyl("VendCan", rh * 0.46, 0.3, f * CF(x, y + 0.12 + rh * 0.23, -0.25), lk(col, M.Metal, { r = 0.2 }))
			end
		end
		txt(K, "VendPrice", ww - 0.05, 0.16, f * CF(wx, y + 0.02, 0.03), prices[r], WHITE, C(20, 20, 24), { font = F.GothamBold, d = 0.02 })
		K:plate("VendButtons", ww - 0.05, 0.07, 0.04, f * CF(wx, y - 0.1, 0.03), Look.ledRed)
	end
	K:plate("VendGlass", ww, wy1 - wy0 + 0.1, 0.03, f * CF(wx, (wy0 + wy1) / 2, 0.02), lk(C(220, 230, 240), M.Glass, { t = 0.75, r = 0.3 }))
	K:plate("VendGlassFrame", ww + 0.12, 0.08, 0.05, f * CF(wx, wy1 + 0.06, 0.03), Look.chrome)
	K:plate("VendGlassFrame", ww + 0.12, 0.08, 0.05, f * CF(wx, wy0 - 0.25, 0.03), Look.chrome)
	-- 오른쪽 결제부
	local px = w / 2 - 0.12 - (w - ww - 0.36) / 2
	local pw = w - ww - 0.36
	K:plate("VendPayPanel", pw, 2.6, 0.03, f * CF(px, 3.6, 0.01), lk(C(220, 224, 230), M.Metal))
	K:plate("VendLCD", pw * 0.7, 0.32, 0.04, f * CF(px, 4.6, 0.02), Look.neon(C(120, 220, 140), 0.1))
	txt(K, "VendLCDText", pw * 0.65, 0.24, f * CF(px, 4.6, 0.05), "0", C(20, 60, 30), nil, { font = F.Arcade })
	K:plate("VendCoin", 0.1, 0.32, 0.05, f * CF(px - pw * 0.2, 4.05, 0.02), Look.black)
	K:plate("VendBill", pw * 0.7, 0.1, 0.05, f * CF(px, 3.65, 0.02), Look.black)
	K:plate("VendCard", pw * 0.6, 0.45, 0.05, f * CF(px, 3.1, 0.02), Look.charcoal)
	txt(K, "VendCardText", pw * 0.55, 0.16, f * CF(px, 3.1, 0.06), "카드 · 페이", WHITE, nil, { font = F.GothamBold })
	K:plate("VendReturn", 0.34, 0.26, 0.06, f * CF(px, 2.5, 0.02), Look.chrome)
	-- 꺼내는 곳
	K:plate("VendOutlet", ww, 0.7, 0.06, f * CF(wx, 1.15, 0.02), lk(C(16, 16, 18)))
	K:plate("VendFlap", ww - 0.15, 0.55, 0.03, f * CF(wx, 1.15, 0.06) * ANG(-0.15, 0, 0), lk(C(60, 64, 72), M.Glass, { t = 0.3 }))
	txt(K, "VendOutletText", ww * 0.6, 0.16, f * CF(wx, 1.62, 0.06), "꺼내는 곳  PUSH", WHITE, nil, { font = F.GothamBold })
end

-- 택배 상자 더미 (택배함 옆 바닥: 크기 다른 상자 3~4 + 테이프 + 송장). pcf 바닥 가운데
local function parcelPile(K: any, pcf: CFrame, rng: () -> number)
	local boxes = { { 1.3, 0.9, 1.0 }, { 0.9, 0.7, 0.8 }, { 1.0, 0.55, 0.7 }, { 0.7, 0.5, 0.6 } }
	local y = 0
	local n = if lo(K) then 2 else 4
	for i = 1, n do
		local b = boxes[i]
		local stackOn = i == 2 or i == 4
		local x = if stackOn then (rng() - 0.5) * 0.2 else (if i == 1 then -0.3 else 0.75)
		local yy = if stackOn then y else 0
		local cf = pcf * CF(x, yy + b[2] / 2, (rng() - 0.5) * 0.2) * ANG(0, (rng() - 0.5) * 0.5, 0)
		K:box("ParcelBox", V3(b[1], b[2], b[3]), cf, Look.cardboard)
		K:box("ParcelTape", V3(b[1] + 0.01, 0.02, 0.18), cf * CF(0, b[2] / 2, 0), lk(C(196, 170, 120), M.SmoothPlastic))
		K:box("ParcelLabel", V3(0.36, 0.02, 0.26), cf * CF(b[1] * 0.18, b[2] / 2 + 0.012, b[3] * 0.22), Look.paper)
		y = if stackOn then 0 else yy + b[2]
		if i == 1 then
			y = b[2]
		end
	end
end

-- 모텔 셀프 바 (어메니티 · 커피 · 생수). pcf 바닥 가운데, +Z 앞, 폭 w
local function selfBar(K: any, pcf: CFrame, w: number, rng: () -> number, accent: Color3)
	local h, d = 3.1, 1.2
	K:box("SelfBarBody", V3(w, h - 0.15, d - 0.05), pcf * CF(0, (h - 0.15) / 2, -0.025), lk(C(36, 30, 34), M.Wood))
	for i = 1, 2 do
		K:plate("SelfBarDoor", w / 2 - 0.08, h - 0.6, 0.03, CFrame.fromMatrix((pcf * CF(-w / 4 + (i - 1) * w / 2, (h - 0.15) / 2, d / 2 - 0.04)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector), lk(C(48, 40, 46), M.Wood))
	end
	K:box("SelfBarTop", V3(w + 0.1, 0.15, d + 0.05), pcf * CF(0, h - 0.075, 0), Look.marbleBlack)
	local top = pcf * CF(0, h, 0)
	-- 캡슐 커피 머신 + 컵 탑
	K:rbox("CoffeeMachine", V3(0.6, 0.95, 0.8), 0.06, top * CF(-w / 2 + 0.5, 0.475, -0.1), lk(C(30, 30, 32)))
	K:box("CoffeeMachineTray", V3(0.4, 0.05, 0.3), top * CF(-w / 2 + 0.5, 0.15, 0.25), Look.chrome)
	K:plate("CoffeeMachineLED", 0.1, 0.1, 0.02, CFrame.fromMatrix((top * CF(-w / 2 + 0.5, 0.8, 0.31)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector), Look.ledBlue)
	for i = 0, 4 do
		K:vcyl("PaperCupStack", 0.12, 0.26 - i * 0.004, top * CF(-w / 2 + 1.1, 0.06 + i * 0.12, 0.05), Look.paper)
	end
	-- 어메니티 바구니 3 (칫솔 · 면도기 · 헤어끈)
	for i = 0, 2 do
		local bcf = top * CF(-0.2 + i * 0.62, 0, -0.05)
		K:box("AmenityTray", V3(0.55, 0.22, 0.6), bcf * CF(0, 0.11, 0), Look.rattan)
		if not lo(K) then
			for k = 0, 2 do
				K:box("AmenityItem", V3(0.12, 0.3, 0.06), bcf * CF(-0.15 + k * 0.15, 0.3, (k % 2) * 0.1 - 0.05) * ANG(0.25, 0, 0), lk(pickR(rng, { C(240, 240, 240), C(120, 200, 230), C(240, 180, 200), C(250, 220, 120) })))
			end
		end
	end
	-- 생수 묶음
	for i = 0, 2 do
		K:vcyl("WaterBottle", 0.7, 0.22, top * CF(w / 2 - 0.35, 0.35, -0.25 + i * 0.25), lk(C(200, 226, 240), M.Glass, { t = 0.3 }))
		K:vcyl("WaterBottleCap", 0.08, 0.12, top * CF(w / 2 - 0.35, 0.74, -0.25 + i * 0.25), lk(C(40, 110, 200)))
	end
	-- 위 안내판
	local sd = CFrame.fromMatrix((pcf * CF(0, h + 1.7, -d / 2 + 0.03)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector)
	K:plate("SelfBarSign", math.min(2.6, w - 0.2), 0.7, 0.05, sd, lk(C(24, 20, 24)))
	txt(K, "SelfBarSignText", math.min(2.4, w - 0.4), 0.5, sd * CF(0, 0, 0.05), "SELF BAR  무료 어메니티 · 커피", accent, nil, { font = F.GothamBold, glow = 1.2 })
end

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
				K:plate("ElevBand", w + 0.6, bh, 0.1, V:wall(wn, cu, y, 0.01), if th then lk(darker(th.wallBack.c, 0.1)) else lk(C(44, 46, 50)))
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
		local hits = table.clone(lounge.artHits or {})
		table.insert(hits, lounge.art[1])
		local base = {}
		for _, p in lounge.art do
			table.insert(base, { p = p, t = p.Transparency })
		end
		promptOn(K, hits, {
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

-- 벽걸이 향기 디퓨저 (호텔 로비 시그니처 향). dcf = 벽, 반환: 본체 · 안개 파트들 · LED
local function scentDiffuser(K: any, dcf: CFrame, accent: Color3): (BasePart, { BasePart }, BasePart)
	local body = K:plate("DiffuserBody", 0.62, 1.05, 0.34, dcf, lk(C(236, 232, 224), M.SmoothPlastic, { r = 0.05 }))
	K:plate("DiffuserFace", 0.5, 0.62, 0.02, dcf * CF(0, -0.1, 0.34), lk(C(60, 54, 50), M.Wood))
	local led = K:plate("DiffuserLED", 0.24, 0.05, 0.02, dcf * CF(0, -0.32, 0.36), Look.neon(accent))
	K:disc("DiffuserNozzle", 0.12, 0.05, dcf * CF(0, 0.53, 0.17), Look.chrome)
	txt(K, "DiffuserText", 0.46, 0.2, dcf * CF(0, 0.08, 0.36), "SIGNATURE\nSCENT", C(230, 220, 200), nil, { font = F.GothamMedium, d = 0.01 })
	local mist = {}
	for i = 1, 3 do
		table.insert(mist, K:ell("DiffuserMist", V3(0.18 + i * 0.12, 0.22 + i * 0.1, 0.18 + i * 0.12), dcf * CF(0.03 * i, 0.6 + i * 0.2, 0.17 + 0.04 * i), lk(C(240, 244, 248), M.SmoothPlastic, { t = 0.78 + i * 0.05 })))
	end
	return body, mist, led
end

local function buildHotel(K: any, V: any, S: any)
	local th = hotelTheme(V)
	local rng = mkRng(V.key or V.name)
	local desk = nil
	step(K, "skin", function()
		local wp = if th.key == "dark" then lk(C(214, 208, 200), M.Fabric) elseif th.key == "oak" then lk(C(234, 230, 220), M.Fabric) else lk(C(226, 220, 210), M.Fabric)
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
			local drop = math.max(1.2, V.H - math.max(8.2, ld.max.Y + 4.2))
			if Common.ceilFree(K, p.X, p.Z, 0.5) and not K:hitsKeep(V3(p.X - 0.5, V.H - drop - 0.1, p.Z - 0.5), V3(p.X + 0.5, V.H, p.Z + 0.5)) then
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
			local dia = math.min(4.2, V.W * 0.2)
			local y = math.max(7.6, V.H - 3.2)
			for _, p in cands do
				local r = dia / 2 + 0.2
				if Common.ceilFree(K, p.X, p.Z, 0.7) and not K:hitsKeep(V3(p.X - r, y - 1.1, p.Z - r), V3(p.X + r, V.H, p.Z + r)) then
					ringChandelier(K, V, p, dia, th)
					break
				end
			end
		end
	end)
	-- 로비 가운데 꽃 장식 테이블 (넓은 로비)
	step(K, "flowers", function()
		if V.W < 18 then
			return
		end
		local cands = {}
		for _, fx in { -0.22, 0.22, -0.28, 0.28, -0.16, 0.16 } do
			for _, z in { 1.2, 0.4, 2.0 } do
				table.insert(cands, V3((V.x0 + V.x1) / 2 + V.W * fx, 0, z))
			end
		end
		local pcf = floorSpot(K, cands, V3(2.6, 5.2, 2.6), V3(0, 0, 1), 0.4, "flowers")
		if pcf then
			K:vcyl("FlowerTableTop", 0.14, 2.5, pcf * CF(0, 2.6, 0), th.top)
			K:vcyl("FlowerTableBase", 2.4, 1.0, pcf * CF(0, 1.27, 0), lk(darker(th.top.c, 0.08), th.top.m))
			K:vcyl("FlowerTablePlinth", 0.12, 1.6, pcf * CF(0, 0.06, 0), th.trim)
			-- 꽃꽂이: 낮은 도자기 볼 + 수국 송이 (작은 꽃잎 뭉치) + 높이 뻗은 목련 가지 + 큰 잎. 꽃 = 작은 공 여러 개
			local vaseL = lk(C(236, 232, 224), M.SmoothPlastic, { r = 0.05 })
			K:vcyl("FlowerVase", 0.55, 1.15, pcf * CF(0, 2.6 + 0.07 + 0.275, 0), vaseL)
			K:vcyl("FlowerVaseFoot", 0.12, 0.7, pcf * CF(0, 2.6 + 0.07 + 0.06, 0), th.trim)
			K:vcyl("FlowerVaseLip", 0.06, 1.2, pcf * CF(0, 2.6 + 0.07 + 0.55, 0), th.trim)
			local base = 2.6 + 0.07 + 0.55
			local hyd = { C(206, 218, 240), C(236, 238, 246), C(240, 206, 220), C(222, 210, 236) }
			local nCl = if lo(K) then 4 else 7
			for i = 1, nCl do
				local a = i * 2 * PI / nCl + 0.4
				local r = if i == nCl then 0 else 0.42
				local cc = pcf * CF(math.cos(a) * r, base + 0.22 + (if r == 0 then 0.18 else 0), math.sin(a) * r)
				local col = hyd[i % #hyd + 1]
				K:ball("FlowerHydrangea", 0.46, cc, lk(col, M.Fabric))
				if not lo(K) then
					for k = 0, 2 do
						local b = k * 2.1 + i
						K:ball("FlowerHydrangea", 0.3, cc * CF(math.cos(b) * 0.17, 0.08, math.sin(b) * 0.17), lk(lighter(col, 0.12), M.Fabric))
					end
				end
			end
			-- 큰 잎 (볼 가장자리로 늘어짐)
			for i = 0, (if lo(K) then 2 else 4) do
				local a = i * 2 * PI / 5 + 0.15
				K:ell("FlowerLeaf", V3(0.95, 0.06, 0.42), pcf * CF(math.cos(a) * 0.62, base - 0.02, math.sin(a) * 0.62) * ANG(0, -a, -0.35), Look.leafDark)
			end
			-- 목련 가지 (가늘고 높게, 끝에 흰 꽃 몇 송이)
			local nBr = if lo(K) then 3 else 5
			for i = 1, nBr do
				local a = i * 2 * PI / nBr + 0.9
				local lean = 0.18 + (i % 3) * 0.08
				local len = 1.7 + (i % 2) * 0.5
				local p0 = pcf * V3(math.cos(a) * 0.12, base + 0.1, math.sin(a) * 0.12)
				local dir = V3(math.cos(a) * math.sin(lean), math.cos(lean), math.sin(a) * math.sin(lean))
				local p1 = p0 + (pcf.Rotation * dir) * len
				K:seg("FlowerBranch", p0, p1, 0.045, lk(C(92, 70, 54), M.Wood))
				for k = 1, (if lo(K) then 2 else 4) do
					local t = 0.45 + k * 0.13
					local q = p0:Lerp(p1, math.min(1, t)) + V3(math.cos(a + k * 1.7) * 0.09, 0, math.sin(a + k * 1.7) * 0.09)
					K:ell("FlowerBlossom", V3(0.2, 0.16, 0.2), CF(q) * ANG(0.3 * k, a, 0), lk(if (i + k) % 3 == 0 then C(246, 214, 224) else C(250, 248, 244), M.Fabric))
				end
			end
		end
	end)
	-- 객실 요금 사이니지 (데스크 옆, 입구 쪽). 세울 자리가 없으면 벽 액자 (층별 안내 다음 순서)
	local needRateWall = false
	step(K, "signage", function()
		if not desk then
			return
		end
		local f = desk.face
		local ends = {}
		-- 엘리베이터 ↔ 입구 동선 (엘리베이터 폭 ±0.4) 위에는 세우지 않음
		local els = V.byName.ElevatorDoor
		local ex0, ex1 = math.huge, -math.huge
		for _, r in els or {} do
			ex0, ex1 = math.min(ex0, r.min.X - 0.4), math.max(ex1, r.max.X + 0.4)
		end
		local function offPath(p: Vector3): boolean
			return p.X + 0.95 < ex0 or p.X - 0.95 > ex1
		end
		if math.abs(f.Z) > 0.5 then
			-- 데스크 양 끝 바깥 (손님 줄 자리 ±0.3 밖) → 손님 줄 뒤 (입구 쪽)
			local raw = {}
			for _, dz in { 0.6, 0, 1.6, -0.8 } do
				for _, dx in { 1.4, 2.0, 2.7 } do
					table.insert(raw, V3(desk.min.X - dx, 0, desk.max.Z + dz))
					table.insert(raw, V3(desk.max.X + dx, 0, desk.max.Z + dz))
				end
			end
			for k = 0, 6 do
				for _, sgn in { 1, -1 } do
					table.insert(raw, V3(desk.c.X + sgn * k * 0.9, 0, desk.max.Z + 4.0))
				end
			end
			for _, p in raw do
				if offPath(p) then
					table.insert(ends, p)
				end
			end
		else
			for _, dz in { 1.4, 2.0, 2.7 } do
				table.insert(ends, V3(desk.c.X, 0, desk.min.Z - dz))
				table.insert(ends, V3(desk.c.X, 0, desk.max.Z + dz))
			end
		end
		local pcf = floorSpot(K, ends, V3(1.7, 5.6, 1.1), V3(0, 0, 1), 0.1, "sign")
		if pcf then
			signageStand(K, pcf, 1.45, 2.6, {
				{ c = C(18, 30, 60), text = "객실 요금 안내\n\n스탠다드 더블  99,000\n디럭스 오션뷰  149,000\n패밀리 트윈  169,000\n스위트  320,000\n\n※ 주말·성수기 별도" },
				{ c = C(40, 26, 20), text = "조식 뷔페\nBREAKFAST\n\n2F 레스토랑\n06:30 - 10:00\n성인 25,000원\n어린이 15,000원" },
				{ c = C(14, 50, 70), text = "오늘의 광안리\n\n맑음  21°C\n\n광안리 M 드론쇼\n매주 토 20:00 / 22:00" },
				{ c = C(30, 30, 34), text = "Wi-Fi\n\nHOTEL_GUEST\nPW  gwangalli2026\n\n짐 보관 서비스\n프런트에 문의하세요" },
			}, 5)
		else
			needRateWall = true
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
	step(K, "interact", function()
		hotelInteract(K, V, lounge)
	end)
	step(K, "fixtures", function()
		fixturesSorted(K, V, S)
	end)
	-- 조명 스위치 (프롬프트) 를 큰 벽 소품보다 먼저: 작은 로비에서 프롬프트 자리를 잃지 않게
	step(K, "switch", function()
		ensureSwitch(K, V)
	end)
	-- 벽걸이 향기 디퓨저 (호텔 시그니처 향): 상호작용이 적은 로비면 켜기/끄기 프롬프트, 자리가 없으면 장식만
	step(K, "diffuser", function()
		local n = 0
		for _, p in K.prompts do
			if p.ObjectText ~= "실내 조명 스위치" then
				n += 1
			end
		end
		local wn, d = nil, nil
		if n < 2 then
			wn, d = wallScan(K, { "left", "right", "back" }, 0.9, 3.4, 5.2, V3(0, 4, V.z1), 0.4, function(dc: CFrame)
				return Interact.canPrompt(K, (dc * CF(0, 0, 0.4)).Position)
			end)
		end
		local decoOnly = false
		if not (wn and d) then
			wn, d = wallItemSpot(K, { "left", "right", "back" }, 0.9, 3.4, 5.2, 0, nil, 0.4)
			decoOnly = true
		end
		if wn and d then
			local body, mist, led = scentDiffuser(K, d * CF(0, -0.15, 0), th.accent)
			if not decoOnly then
				Interact.toggle(K, body, { object = "향기 디퓨저", onText = "디퓨저 끄기", offText = "디퓨저 켜기", state = true, on = function(on: boolean)
					for i, m in mist do
						if m.Parent then
							m.Transparency = if on then 0.78 + i * 0.05 else 1
						end
					end
					if led.Parent then
						led.Material = if on then M.Neon else M.SmoothPlastic
					end
				end })
			end
		end
	end)
	-- 벽: 층별 안내 · 와이파이 · 관광 포스터 · 비상구
	step(K, "walls", function()
		local els = V.byName.ElevatorDoor
		local ep = if els and els[1] then els[1].c else V3(0, 0, V.z0)
		local wn, d = spotNear(K, { "back", "left", "right" }, 2.2, 3.6, 6.8, ep + V3(-4, 0, 0))
		if not wn then
			wn, d = wallScan(K, { "back", "left", "right" }, 2.2, 3.6, 6.8, ep, 0.3)
		end
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
		if needRateWall and desk then
			-- 데스크 가까운 벽에 객실 요금 액자
			-- 프롬프트를 둘 수 없는 자리 (서버 앵커 근처) 를 먼저: 조명 스위치 · 상호작용 자리를 빼앗지 않게
			local wn, d = spotNear(K, { "left", "right", "back" }, 1.9, 3.7, 6.4, desk.c, function(dc: CFrame)
				return not Interact.canPrompt(K, (dc * CF(0, -1.0, 0.2)).Position)
			end)
			if not wn then
				wn, d = spotNear(K, { "left", "right", "back" }, 1.9, 3.7, 6.4, desk.c)
			end
			if not wn then
				wn, d = wallScan(K, { "left", "right", "back" }, 1.9, 3.7, 6.4, desk.c, 0.3)
			end
			if wn and d then
				Props.frame(K, d, 1.75, 2.55, { frame = th.trim, border = 0.07, depth = 0.06, mat = lk(C(24, 30, 52)) })
				txt(K, "RateTitle", 1.45, 0.34, d * CF(0, 0.92, 0.06), "ROOM RATE  객실 요금", th.accent, C(24, 30, 52), { font = F.GothamBold, d = 0.005 })
				txt(K, "RateBody", 1.45, 1.75, d * CF(0, -0.22, 0.06), "스탠다드 더블   99,000\n디럭스 오션뷰  149,000\n패밀리 트윈    169,000\n스위트          320,000\n\n조식 1인 25,000\n※ 주말 · 성수기 별도", C(236, 232, 222), C(24, 30, 52), { font = F.GothamMedium, d = 0.005 })
			end
		end
	end)
	-- 큰 벽 소품 뒤 작은 벽 부착물 (스위치 · 콘센트 · 등록증 ...)
	step(K, "posters", function()
		fillPosters(K, POSTERS.hotel, 2)
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
	local tropical = string.find(name, "야자", 1, true) ~= nil or string.find(string.upper(name), "PALM", 1, true) ~= nil
	if tropical then
		accent = C(250, 176, 80)
	end
	local leds = {}
	step(K, "skin", function()
		wallSkin(K, { "left", "right", "back" }, 3.4, V.H - 0.02, if tropical then lk(C(226, 210, 184), M.Plaster) else lk(C(118, 96, 106), M.Fabric), Look.goldMetal)
		-- 벽 브래킷 조명 (따뜻한 빛 2)
		local n = 0
		for _, wn in { "left", "right" } do
			local wn2, d = wallItemSpot(K, { wn }, 0.8, 5.6, 6.8, 0)
			if wn2 and d then
				K:free(function()
					K:plate("SconceBack", 0.4, 0.9, 0.06, d, Look.goldMetal)
					K:vcyl("SconceShade", 0.7, 0.55, d * CF(0, 0.1, 0.38), lk(C(250, 226, 196), M.Fabric, { t = 0.15 }))
					local b = K:ball("SconceBulb", 0.22, d * CF(0, 0.05, 0.38), Look.lampWarm)
					K:seg("SconceArm", (d * CF(0, -0.2, 0.05)).Position, (d * CF(0, -0.2, 0.38)).Position, 0.06, Look.goldMetal)
					if n == 0 then
						K:light(b, "PointLight", { Range = 10, Brightness = 0.8, Color = Look.warmLight })
					end
				end)
				n += 1
			end
		end
	end)
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
			local frL = lk(C(30, 24, 28), M.Wood)
			K:plate("FrontFrame", w, 0.25, 0.14, base * CF(0, 5.925, 0), frL)
			K:plate("FrontFrame", w, 0.25, 0.14, base * CF(0, 3.725, 0), frL)
			K:plate("FrontFrame", 0.2, 2.0, 0.14, base * CF(-w / 2 + 0.1, 4.85, 0), frL)
			K:plate("FrontFrame", 0.2, 2.0, 0.14, base * CF(w / 2 - 0.1, 4.85, 0), frL)
			-- 창 안쪽 (작은 사무실: 따뜻한 조명 · 모니터 · 키 걸이)
			K:plate("FrontInside", w - 0.4, 2.0, 0.02, base * CF(0, 4.85, 0.0), lk(C(120, 84, 60), M.Neon, { t = 0.55 }))
			K:plate("FrontInsideDesk", w - 0.4, 0.3, 0.05, base * CF(0, 3.95, 0.02), lk(C(70, 50, 40), M.Wood))
			K:plate("FrontInsideMon", 0.8, 0.5, 0.03, base * CF(0.7, 4.35, 0.03), Look.black)
			K:plate("FrontInsideMonLit", 0.7, 0.4, 0.035, base * CF(0.7, 4.35, 0.035), lk(C(120, 170, 220), M.Neon, { t = 0.4 }))
			for i = 0, 5 do
				K:plate("FrontKeyTag", 0.1, 0.22, 0.03, base * CF(-1.1 + i * 0.18, 5.3 - (i % 2) * 0.05, 0.03), lk(pickR(rng, { C(200, 40, 60), C(240, 200, 60), C(60, 120, 200) })))
			end
			K:plate("FrontKeyBoard", 1.2, 0.08, 0.03, base * CF(-0.65, 5.48, 0.03), gold)
			K:plate("FrontGlass", w - 0.4, 2.0, 0.03, base * CF(0, 4.85, 0.1), lk(C(90, 70, 76), M.Glass, { t = 0.65, r = 0.2 }))
			K:plate("FrontGlassFrost", w - 0.4, 0.5, 0.06, base * CF(0, 5.6, 0.11), lk(C(200, 190, 190), M.Glass, { t = 0.35 }))
			K:plate("FrontSlot", 1.3, 0.35, 0.12, base * CF(0, 3.7, 0.1), Look.black)
			txt(K, "FrontGlassText", w - 0.8, 0.36, base * CF(0, 5.6, 0.18), "FRONT  ·  안내", WHITE, nil, { font = F.GothamMedium })
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
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.8, 1.3, 5.6, V3(0, 0, V.z0 + 3), 0.05, "kiosk", function(pc: CFrame)
			return Interact.canPrompt(K, (pc * CF(0, 3.5, 0.4)).Position)
		end)
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
	end)
	-- 넓은 모텔형 호텔 로비 (W >= 14): 대기 라운지 (소파 · 커피 테이블 · 아트 · 플로어 램프) + 음료 자판기
	local motelTh = if tropical
		then { fab = lk(C(214, 198, 168), M.Fabric), top = lk(C(126, 92, 60), M.Wood), trim = Look.goldMetal, rug = lk(C(190, 172, 140), M.Fabric), rugEdge = lk(C(112, 88, 56), M.Fabric) }
		else { fab = lk(C(96, 30, 52), M.Fabric), top = Look.marbleBlack, trim = Look.goldMetal, rug = lk(C(52, 38, 46), M.Fabric), rugEdge = lk(C(176, 140, 80), M.Fabric) }
	step(K, "lounge", function()
		if V.W < 14 then
			return
		end
		local lg = hotelLounge(K, V, motelTh, rng, { walls = { "back", "left", "right" }, pref = V3(V.x0 + V.W * 0.3, 0, V.z0) })
		if lg and lg.floorLamp then
			local b = lg.floorLamp
			Interact.toggle(K, b, { object = "플로어 램프", onText = "램프 끄기", offText = "램프 켜기", state = true, on = function(on: boolean)
				if b.Parent then
					b.Material = if on then M.Neon else M.SmoothPlastic
					b.Color = if on then C(255, 214, 160) else C(110, 104, 96)
				end
			end })
		end
	end)
	step(K, "vending", function()
		if V.W < 14 then
			return
		end
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 2.6, 2.2, 6.4, V3(V.x1, 0, 0), 0.05, "vending")
		if wn and pcf then
			vendingMachine(K, pcf, rng)
		end
	end)
	step(K, "selfbar", function()
		for _, w in { 3.6, 2.8 } do
			-- 앞 1.8 스터드는 비어 있어야 (사람이 서서 쓰는 자리)
			local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, w, 1.35, 5.2, V3(V.x0, 0, V.z0 + 2), 0.05, "selfbar", function(pc: CFrame)
				local mn = canPlace(K, pc * CF(0, 0, 1.35 / 2 + 1.0), V3(w, 2.0, 1.8), 0)
				return mn ~= nil
			end)
			if wn and pcf then
				selfBar(K, pcf * CF(0, 0, 0.05), w, rng, accent)
				break
			end
		end
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
		local target = if #leds > 0 then promptPanel(K, { "left", "right", "back" }, "MOOD", V3(0, 0, V.z0 + 2), lk(C(40, 34, 40))) else nil
		if target then
			local cols = { C(220, 60, 120), C(140, 80, 255), C(60, 160, 255), C(255, 170, 90) }
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
	-- 거울 · 조화 · 우산 비닐 · 그림
	step(K, "decor", function()
		local wn, d = wallItemSpot(K, { "left", "right", "back" }, 1.6, 1.0, 6.4, -V.D / 2 + 2)
		if wn and d then
			K:plate("MirrorFrame", 1.6, 5.2, 0.08, d * CF(0, 0.5, 0), gold)
			K:plate("Mirror", 1.44, 5.04, 0.03, d * CF(0, 0.5, 0.08), Look.mirror)
		end
		if tropical or V.W >= 14 then
			-- 아레카야자: 뒤 모서리 + 넓으면 창가 양끝
			local potL = if tropical then lk(C(196, 170, 130), M.Fabric) else lk(C(30, 28, 30), M.Concrete)
			local spots = { V3(V.x1 - 1.6, 0, V.z0 + 1.6), V3(V.x0 + 1.6, 0, V.z0 + 1.6) }
			if V.W >= 14 then
				for _, p in { V3(V.x0 + 1.6, 0, V.z1 - 3.3), V3(V.x1 - 1.6, 0, V.z1 - 3.3), V3(V.x0 + 1.6, 0, 0), V3(V.x1 - 1.6, 0, 0) } do
					table.insert(spots, p)
				end
				local els = V.byName.ElevatorDoor
				if els and #els > 0 then
					local mn, mx = els[1].min, els[1].max
					for _, r in els do
						mn, mx = mn:Min(r.min), mx:Max(r.max)
					end
					table.insert(spots, V3(mn.X - 1.9, 0, V.z0 + 1.6))
					table.insert(spots, V3(mx.X + 1.9, 0, V.z0 + 1.6))
				end
			end
			local placed = 0
			for i, p in spots do
				if placed < 4 and palmTree(K, pcfAt(p, V3(0, 0, 1)), math.min(6.4, V.H - 1.6), 1.3, potL, i * 13 + #name) then
					placed += 1
				end
			end
			-- 넓은 열대 콘셉트 로비: 가운데 비켜 둥근 원목 화단 벤치 + 큰 야자 (입구 → 엘리베이터 동선은 비움)
			if tropical and V.W >= 20 then
				for _, p in { V3(-6.2, 0, 0.8), V3(6.2, 0, 0.8), V3(-7.0, 0, -0.8), V3(7.0, 0, -0.8) } do
					local pc = pcfAt(p, V3(0, 0, 1))
					if canPlace(K, pc, V3(3.2, 7.5, 3.2), 0.1) then
						K:vcyl("PalmIslandBase", 1.2, 3.0, pc * CF(0, 0.6, 0), lk(C(120, 88, 58), M.Wood))
						K:vcyl("PalmIslandSeat", 0.14, 3.2, pc * CF(0, 1.27, 0), lk(C(150, 112, 74), M.Wood))
						for k = 0, 11 do
							local a = k * PI / 6
							K:box("PalmIslandSlat", V3(0.06, 1.0, 0.3), pc * CF(math.cos(a) * 1.52, 0.62, math.sin(a) * 1.52) * ANG(0, -a, 0), lk(C(96, 70, 46), M.Wood))
						end
						K:vcyl("PalmIslandSoil", 0.08, 2.0, pc * CF(0, 1.36, 0), Look.soil)
						K:vcyl("PalmIslandPebbles", 0.06, 2.6, pc * CF(0, 1.33, 0), lk(C(226, 220, 206), M.Pebble))
						-- 큰 야자 (화분 없이 화단에 심음): 화분 없는 palmTree 를 쓰기 위해 아주 작은 화분 + 높이
						local tcf = pc * CF(0, 1.3, 0)
						palmTree(K, tcf, math.min(7.2, V.H - 2.4), 0.6, lk(C(120, 88, 58), M.Wood), 99)
						local imn, imx = K.laabb(pc * CF(0, 3.75, 0), V3(3.3, 7.5, 3.3))
						K:reserve(imn, imx, "island")
						break
					end
				end
			end
			if placed == 0 then
				plantAt(K, pcfAt(spots[1], V3(0, 0, 1)), "snake", 3.4, 1.0, potL)
			end
		else
			plantAt(K, pcfAt(V3(V.x1 - 1.0, 0, V.z0 + 1.0), V3(0, 0, 1)), "snake", 3.4, 1.0, lk(C(30, 28, 30), M.Concrete))
			plantAt(K, pcfAt(V3(V.x0 + 1.0, 0, V.z0 + 1.0), V3(0, 0, 1)), "bamboo", 4.6, 1.0, lk(C(30, 28, 30), M.Concrete))
		end
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
	step(K, "extras", function()
		-- 입구 → 엘리베이터 러너 카펫 (바닥 마감, 0.03)
		local els = V.byName.ElevatorDoor
		local ex = if els and els[1] then (els[1].c.X + (els[#els] and els[#els].c.X or els[1].c.X)) / 2 else (V.x0 + V.x1) / 2
		K:free(function()
			local z0, z1 = V.z0 + 0.4, V.z1 - 2.8
			K:box("RunnerCarpet", V3(2.6, 0.03, z1 - z0), CF(ex, 0.035, (z0 + z1) / 2), lk(C(110, 24, 40), M.Fabric))
			for _, sx in { -1, 1 } do
				K:box("RunnerBorder", V3(0.18, 0.032, z1 - z0), CF(ex + sx * 1.15, 0.036, (z0 + z1) / 2), lk(C(196, 160, 90), M.Fabric))
			end
		end)
		-- 크리스털 샹들리에
		if V.H > 8.5 then
			local p = V3(ex, 0, (V.z0 + V.z1) / 2 - 1)
			for _, dz in { 0, -1.5, -3 } do
				local q = V3(ex, 0, (V.z0 + V.z1) / 2 - 1 + dz)
				if Common.ceilFree(K, q.X, q.Z, 0.8) and not K:hitsKeep(V3(q.X - 1, V.H - 2.0, q.Z - 1), V3(q.X + 1, V.H, q.Z + 1)) then
					p = q
					break
				end
			end
			if Common.ceilFree(K, p.X, p.Z, 0.8) and not K:hitsKeep(V3(p.X - 1, V.H - 2.0, p.Z - 1), V3(p.X + 1, V.H, p.Z + 1)) then
				K:free(function()
					local y = V.H - 1.6
					K:disc("CrystalCanopy", 0.6, 0.08, CF(p.X, V.H - 0.04, p.Z), Look.goldMetal)
					K:seg("CrystalChain", V3(p.X, V.H - 0.05, p.Z), V3(p.X, y + 0.5, p.Z), 0.04, Look.goldMetal)
					K:ring("CrystalRing", CF(p.X, y + 0.2, p.Z) * ANG(PI / 2, 0, 0), 0.8, 0.06, 12, Look.goldMetal)
					for k = 0, (if lo(K) then 5 else 11) do
						local a = k * PI / 6
						K:ell("CrystalDrop", V3(0.14, 0.4, 0.14), CF(p.X + math.cos(a) * 0.8, y - 0.1, p.Z + math.sin(a) * 0.8), lk(C(240, 240, 250), M.Glass, { t = 0.2, r = 0.3 }))
					end
					local b = K:ball("CrystalBulb", 0.45, CF(p.X, y + 0.1, p.Z), Look.lampWarm)
					K:light(b, "PointLight", { Range = 10, Brightness = 0.6, Color = Look.warmLight })
				end)
				Common.useCeil(K, p.X, p.Z)
			end
		end
		-- 객실 사진 (스파 · 파티룸 · 스탠다드)
		fillPosters(K, {
			{ "SPA ROOM", "월풀 욕조 · 안마의자\n대실 40,000 / 숙박 80,000", C(120, 40, 90), w = 1.4, h = 1.6, y = 4.2 },
			{ "PARTY ROOM", "75인치 TV · 노래방\n최대 6인 · 숙박 120,000", C(60, 40, 120), w = 1.4, h = 1.6, y = 4.2 },
			{ "주차 안내", "건물 뒤편 전용 주차장\n가림막 설치 · 무료", C(40, 40, 46), w = 1.2, h = 1.4, y = 4.2 },
		}, 3)
	end)
	step(K, "fixtures", function()
		fixturesSorted(K, V, S)
	end)
	step(K, "switch", function()
		ensureSwitch(K, V)
	end)
end

---------------------------------------------------------------------------------------------------
-- 7. 아파트 · 오피스텔 공동현관 로비
---------------------------------------------------------------------------------------------------

-- 우편함 (맵 Mailboxes 덮어씌우기: 같은 범위). 문 격자는 방 쪽 면
local function mailboxOver(K: any, V: any, r: any, old: boolean?)
	local face: Vector3
	local dl, dr = r.min.X - V.x0, V.x1 - r.max.X
	local db = r.min.Z - V.z0
	if math.abs(r.size.X) < math.abs(r.size.Z) then
		face = if dl < dr then V3(1, 0, 0) else V3(-1, 0, 0)
	else
		face = if db < V.z1 - r.max.Z then V3(0, 0, 1) else V3(0, 0, -1)
	end
	local warm = hashStr(V.name or "") % 2 == 0
	local steel = if old then lk(C(208, 210, 212), M.Metal, { r = 0.02 }) elseif warm then lk(C(214, 196, 160), M.SmoothPlastic, { r = 0.08 }) else lk(C(226, 228, 230), M.SmoothPlastic, { r = 0.1 })
	K:free(function()
		K:box("MailBody", r.size + V3(0.02, -0.08, 0.02), CF(r.c - V3(0, 0.04, 0)), lk(C(212, 214, 216), M.SmoothPlastic))
		-- 윗면 마감 판 (윗면 높이 = 맵 Mailboxes 윗면, 둘레 루버까지 덮음)
		K:box("MailTopCap", V3(r.size.X + 0.2, 0.08, r.size.Z + 0.2), CF(r.c.X, r.max.Y - 0.04, r.c.Z), if old then Look.alu else (if warm then lk(C(190, 154, 112), M.Wood) else lk(C(120, 94, 72), M.Wood)))
		-- 뒤 · 옆면: 템바보드 (세로 루버) 마감. 몸통 면에서 0.04 이상 띄움 (z-fighting 방지)
		-- 신축: 가는 템바보드 (홈과 살의 명암 차를 줄여 '울타리'처럼 보이지 않게) / 맨션: 헤어라인 알루미늄 판 + 가로 리브
		local slatL = if warm then lk(C(178, 140, 100), M.Wood) else lk(C(104, 80, 62), M.Wood)
		local grooveL = if warm then lk(C(128, 96, 66), M.Wood) else lk(C(70, 54, 44), M.Wood)
		local function louver(fd: CFrame, flen: number, y0: number, y1: number)
			if old then
				K:plate("MailSidePanel", flen - 0.04, y1 - y0, 0.04, fd * CF(0, (y0 + y1) / 2, 0.03), Look.brushed)
				for k = 1, 3 do
					K:plate("MailSideRib", flen - 0.06, 0.05, 0.06, fd * CF(0, y0 + (y1 - y0) * k / 4, 0.05), Look.alu)
				end
				return
			end
			K:plate("MailLouverBack", flen - 0.04, y1 - y0, 0.03, fd * CF(0, (y0 + y1) / 2, 0.025), grooveL)
			local pitch = if lo(K) then 0.6 elseif hi(K) then 0.3 else 0.4
			local n = math.max(2, math.floor((flen - 0.1) / pitch))
			local pw = (flen - 0.1) / n
			for i = 1, n do
				K:plate("MailLouver", pw * 0.74, y1 - y0 - 0.04, 0.06, fd * CF(-flen / 2 + 0.05 + pw * (i - 0.5), (y0 + y1) / 2, 0.055), slatL)
			end
		end
		local _, flen0 = faceOf(r, face)
		local mrows = math.max(2, math.floor((r.size.Y - 1.2) / 0.9))
		local mcols = math.max(2, math.floor(flen0 / 0.95))
		local bd, blen = faceOf(r, -face)
		louver(bd, blen, 0.5, r.size.Y - 0.55)
		K:plate("MailBackBand", blen, 0.5, 0.04, bd * CF(0, r.size.Y - 0.3, 0.04), lk(C(40, 44, 48)))
		K:plate("MailBackPlinth", blen, 0.5, 0.04, bd * CF(0, 0.25, 0.04), Look.charcoal)
		-- 양 끝면: 루버 + 위 띠 + 안내 판 (입구 쪽 끝은 동 · 호수 안내)
		for _, ef in { V3(-face.Z, 0, face.X), V3(face.Z, 0, -face.X) } do
			local ed, elen = faceOf(r, ef)
			local towardDoor = (ed.Position.Z > r.c.Z + 0.1) or (math.abs(ef.X) > 0.5 and V.door ~= nil and math.sign(V.door.x - r.c.X) == math.sign(ef.X))
			louver(ed, elen, 0.5, r.size.Y - 0.55)
			K:plate("MailEndBand", elen, 0.5, 0.04, ed * CF(0, r.size.Y - 0.3, 0.04), lk(C(40, 44, 48)))
			K:plate("MailEndPlinth", elen, 0.5, 0.04, ed * CF(0, 0.25, 0.04), Look.charcoal)
			if towardDoor and elen > 1.6 then
				local pw = math.min(1.9, elen - 0.5)
				K:plate("MailDirPlate", pw, 2.1, 0.04, ed * CF(0, 4.15, 0.13), Look.brushed)
				K:plate("MailDirHead", pw, 0.42, 0.045, ed * CF(0, 5.0, 0.13), lk(C(40, 44, 48)))
				txt(K, "MailDirHeadText", pw - 0.2, 0.3, ed * CF(0, 5.0, 0.16), "세대 안내", WHITE, nil, { font = F.GothamBold })
				txt(K, "MailDirText", pw - 0.25, 1.5, ed * CF(0, 3.95, 0.16), string.format("%dF ~ 1F  세대 우편함\n101 ~ %d%02d 호\n\n등기 · 대형 택배는\n경비실 · 무인택배함", mrows, mrows, mcols), C(40, 42, 46), nil, { font = F.GothamMedium })
			end
			if not lo(K) then
				txt(K, "MailEndSticker", math.min(1.5, elen - 0.5), 0.8, ed * CF(0, if towardDoor then 2.3 else 3.4, 0.16), "광고 전단\n부착 금지\n- 관리사무소 -", C(200, 40, 40), C(250, 250, 246), { font = F.GothamBold, d = 0.01 })
			end
		end
		local d, len = faceOf(r, face)
		local hgt = r.size.Y
		local base = d * CF(0, r.min.Y, 0.01)
		-- 받침 · 머리띠
		K:plate("MailPlinth", len, 0.5, 0.03, base * CF(0, 0.25, 0), Look.charcoal)
		K:plate("MailHeader", len, 0.55, 0.04, base * CF(0, hgt - 0.3, 0), lk(C(40, 44, 48)))
		txt(K, "MailHeaderText", len * 0.8, 0.36, base * CF(0, hgt - 0.3, 0.05), "우 편 함   MAIL BOX", WHITE, nil, { font = F.GothamBold })
		local cols = math.max(2, math.floor(len / 0.95))
		local rows = math.max(2, math.floor((hgt - 1.2) / 0.9))
		local cw = (len - 0.2) / cols
		local rh = (hgt - 1.15) / rows
		local floors = rows
		for ci = 1, cols do
			local u = -len / 2 + 0.1 + cw * (ci - 0.5)
			for ri = 1, rows do
				local y = 0.55 + rh * (ri - 0.5)
				local door = base * CF(u, y, 0)
				K:plate("MailDoor", cw - 0.07, rh - 0.07, 0.03, door, steel)
				K:plate("MailSlot", cw * 0.62, 0.05, 0.035, door * CF(0, rh * 0.28, 0.0), Look.black)
				if hi(K) or ci % 2 == 1 then
					K:plate("MailLock", 0.07, 0.07, 0.05, door * CF(cw * 0.32, -rh * 0.1, 0), Look.chrome)
				end
				if not lo(K) then
					K:plate("MailName", cw * 0.42, 0.12, 0.036, door * CF(-cw * 0.12, -rh * 0.22, 0), Look.paper)
				end
			end
			-- 세대 번호 (열마다 한 글자판: 위층부터)
			local lines = {}
			for ri = rows, 1, -1 do
				table.insert(lines, string.format("%d%02d", ri + (floors > 5 and 0 or 0), ci))
			end
			txt(K, "MailNums", cw * 0.32, rh * rows * 0.96, base * CF(u + cw * 0.18, 0.55 + rh * rows / 2 + rh * 0.08, 0.04), table.concat(lines, "\n"), C(30, 30, 34), nil, { font = F.GothamBold })
		end
		-- 위: 전단지 수거함
		K:plate("FlyerBin", len * 0.3, 0.35, 0.3, base * CF(len * 0.3, 0.35, 0.03), lk(C(60, 110, 70)))
		txt(K, "FlyerBinText", len * 0.28, 0.2, base * CF(len * 0.3, 0.38, 0.34), "광고물 수거함", WHITE, nil, { font = F.GothamBold })
	end)
	hideRec(K, r)
	for _, q in V.byName.MailboxLine or {} do
		hideRec(K, q)
	end
	return face
end

-- 무인택배함 (기둥 여러 칸 + 가운데 조작부). pcf 정면 +Z, w 폭. 반환: 화면 파트 · 글자 · 큰 문 모델
local function parcelLocker(K: any, pcf: CFrame, w: number, h: number, rng: () -> number): (BasePart?, TextLabel?, Model?, Vector3?)
	local body = lk(C(226, 228, 230))
	local doorL = lk(C(232, 234, 236), M.SmoothPlastic, { r = 0.06 })
	local accent = C(0, 120, 200)
	K:box("LockerBody", V3(w, h, 1.3), pcf * CF(0, h / 2, -0.05), body)
	K:box("LockerPlinth", V3(w - 0.1, 0.35, 1.2), pcf * CF(0, 0.175, 0), Look.charcoal)
	K:plate("LockerTop", w, 0.5, 0.02, CFrame.fromMatrix((pcf * CF(0, h - 0.3, 0.61)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector), lk(accent))
	txt(K, "LockerTopText", w * 0.7, 0.32, CFrame.fromMatrix((pcf * CF(0, h - 0.3, 0.64)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector), "무인택배함  24H  SMART PARCEL", WHITE, nil, { font = F.GothamBold })
	local colW = 1.25
	local ncol = math.max(3, math.floor(w / colW))
	colW = w / ncol
	local mid = math.ceil(ncol / 2)
	local screen, lab, bigDoor, hinge = nil, nil, nil, nil
	local sizes = { 0.55, 0.55, 0.85, 0.55, 1.2, 0.85, 0.55 }
	local no = 1
	for ci = 1, ncol do
		local x = -w / 2 + colW * (ci - 0.5)
		local face = CFrame.fromMatrix((pcf * CF(x, 0, 0.61)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector)
		if ci == mid then
			-- 조작부: 터치스크린 · 키패드 · 스캐너 · 영수증
			K:plate("LockerPanel", colW - 0.08, h - 1.0, 0.02, face * CF(0, 0.35 + (h - 1.0) / 2, 0), lk(C(60, 64, 70)))
			screen = K:plate("LockerScreen", colW - 0.3, 1.25, 0.02, face * CF(0, 4.0, 0.02), { c = C(20, 60, 110), m = M.Neon, t = 0.1 })
			local _, l = txt(K, "LockerScreenText", colW - 0.4, 1.1, face * CF(0, 4.0, 0.045), "택배 찾기\n\n동·호수를\n입력하세요", WHITE, nil, { font = F.GothamBold, glow = 1.1 })
			lab = l
			for kx = 0, 2 do
				for ky = 0, 3 do
					K:plate("LockerKey", 0.2, 0.14, 0.03, face * CF(-0.25 + kx * 0.25, 2.95 - ky * 0.2, 0.02), Look.grey)
				end
			end
			K:plate("LockerScanner", 0.5, 0.3, 0.06, face * CF(0, 2.0, 0.02), Look.black)
			K:plate("LockerScanLED", 0.3, 0.04, 0.07, face * CF(0, 2.0, 0.03), Look.ledRed)
			K:plate("LockerReceipt", 0.4, 0.06, 0.04, face * CF(0, 1.6, 0.02), Look.chrome)
			K:plate("LockerCam", 0.12, 0.12, 0.05, face * CF(0, 4.85, 0.02), Look.black)
		else
			local y = 0.4
			local k = (ci * 3 + math.floor(rng() * 4)) % #sizes + 1
			while y < h - 0.75 do
				local dh = math.min(sizes[k], h - 0.7 - y)
				if dh < 0.3 then
					break
				end
				local dcf = face * CF(0, y + dh / 2, 0)
				local isBig = (not bigDoor) and dh >= 1.1 and (ci == 1 or ci == ncol)
				local function mk()
					K:plate("LockerDoor", colW - 0.06, dh - 0.05, 0.03, dcf, doorL)
					K:plate("LockerDoorHandle", 0.06, math.min(0.4, dh * 0.5), 0.05, dcf * CF(colW / 2 - 0.2, 0, 0.03), Look.chrome)
					if not lo(K) then
						txt(K, "LockerNo", 0.28, 0.16, dcf * CF(-colW / 2 + 0.25, dh / 2 - 0.15, 0.035), tostring(no), C(60, 64, 70), nil, { font = F.GothamBold })
						K:plate("LockerLED", 0.06, 0.06, 0.04, dcf * CF(-colW / 2 + 0.2, -dh / 2 + 0.14, 0.03), if rng() < 0.35 then Look.ledRed else Look.ledGreen)
					end
				end
				if isBig then
					bigDoor = K:group("LockerBigDoor", mk)
					hinge = (K.cf * (dcf * CF(-colW / 2 + 0.03, 0, 0.03))).Position
				else
					mk()
				end
				no += 1
				y += dh
				k = k % #sizes + 1
			end
		end
	end
	return screen, lab, bigDoor, hinge
end

-- 경비실 호출 인터폰 (벽). 반환: 화면 · 글자 · 버튼
local function intercom(K: any, dcf: CFrame): (BasePart, TextLabel, BasePart)
	K:plate("IntercomBox", 1.1, 1.9, 0.12, dcf, lk(C(70, 74, 80), M.Metal))
	K:plate("IntercomBezel", 0.9, 0.62, 0.02, dcf * CF(0, 0.5, 0.12), Look.black)
	local scr = K:plate("IntercomScreen", 0.8, 0.52, 0.02, dcf * CF(0, 0.5, 0.13), { c = C(30, 80, 120), m = M.Neon, t = 0.15 })
	local _, lab = txt(K, "IntercomText", 0.74, 0.46, dcf * CF(0, 0.5, 0.155), "세대 호출\n동 · 호수 입력", WHITE, nil, { font = F.GothamBold, glow = 1.0 })
	for kx = 0, 2 do
		for ky = 0, 3 do
			K:plate("IntercomKey", 0.2, 0.14, 0.03, dcf * CF(-0.25 + kx * 0.25, -0.05 - ky * 0.19, 0.12), lk(C(210, 212, 214), M.Metal))
		end
	end
	local btn = K:plate("IntercomGuard", 0.7, 0.18, 0.04, dcf * CF(0, -0.84, 0.12), lk(C(40, 120, 200)))
	txt(K, "IntercomGuardText", 0.6, 0.13, dcf * CF(0, -0.84, 0.165), "경비실 호출", WHITE, nil, { font = F.GothamBold })
	K:disc("IntercomCam", 0.12, 0.04, dcf * CF(0, 0.9, 0.13) * ANG(PI / 2, 0, 0), Look.black)
	return scr, lab, btn
end

-- 경비실 창 (오래된 맨션 로비): 벽에 붙은 알루미늄 미닫이 유리창 + 안쪽 어두운 방 (CCTV 모니터 · 스탠드 · 열쇠함) + 창턱.
-- dcf = 창 가운데 (벽 면), w x h. 창턱은 앞으로 0.5 나옴
local function guardWindow(K: any, dcf: CFrame, w: number, h: number)
	local alu = Look.alu
	dcf = dcf * CF(0, 0, 0.05) -- 벽 마감 (페인트 · 타일) 위로 띄움: z-fighting 방지
	-- 안쪽 방 (벽 면에 붙은 어두운 판 + 천장 형광등 빛 띠)
	K:plate("GuardRoom", w, h, 0.02, dcf, lk(C(58, 60, 58)))
	K:plate("GuardRoomWall", w, h * 0.45, 0.025, dcf * CF(0, h * 0.27, 0), lk(C(150, 160, 150)))
	K:plate("GuardRoomTube", w * 0.6, 0.06, 0.03, dcf * CF(0, h / 2 - 0.12, 0.01), Look.neon(C(236, 246, 255)))
	-- CCTV 4분할 모니터 · 스탠드 · 열쇠함 · 달력 (유리 너머 실루엣)
	local mon = dcf * CF(-w * 0.22, -h * 0.05, 0.04)
	K:plate("GuardMonitor", 1.1, 0.8, 0.05, mon, Look.black)
	for i = 0, 3 do
		K:plate("GuardCCTV", 0.48, 0.33, 0.01, mon * CF(-0.25 + (i % 2) * 0.5, 0.18 - (i // 2) * 0.36, 0.03), Look.neon(if i == 1 then C(120, 140, 120) else C(110, 124, 140)))
	end
	K:plate("GuardKeyBox", 0.7, 0.9, 0.06, dcf * CF(w * 0.3, h * 0.12, 0.03), lk(C(196, 190, 170)))
	if not lo(K) then
		for i = 0, 5 do
			K:plate("GuardKey", 0.04, 0.16, 0.02, dcf * CF(w * 0.3 - 0.22 + (i % 3) * 0.22, h * 0.12 + 0.2 - (i // 3) * 0.35, 0.07), Look.brass)
		end
		K:plate("GuardCalendar", 0.55, 0.75, 0.01, dcf * CF(w * 0.08, h * 0.2, 0.03), Look.paper)
		K:plate("GuardCalendarTop", 0.55, 0.18, 0.012, dcf * CF(w * 0.08, h * 0.2 + 0.3, 0.035), lk(C(200, 40, 40)))
		K:plate("GuardLamp", 0.3, 0.16, 0.12, dcf * CF(w * 0.05, -h / 2 + 0.55, 0.06), Look.neon(C(255, 220, 160)))
	end
	-- 바깥 틀 + 가운데 세로살 + 미닫이 유리 2장 (앞뒤로 엇갈림)
	K:plate("GuardFrameTop", w + 0.24, 0.14, 0.32, dcf * CF(0, h / 2 + 0.05, 0), alu)
	K:plate("GuardFrameSide", 0.14, h + 0.2, 0.32, dcf * CF(-w / 2 - 0.05, 0, 0), alu)
	K:plate("GuardFrameSide", 0.14, h + 0.2, 0.32, dcf * CF(w / 2 + 0.05, 0, 0), alu)
	for i, sx in { -1, 1 } do
		local pz = 0.2 + (i - 1) * 0.06
		local pane = dcf * CF(sx * w / 4 + (if i == 1 then 0.08 else -0.08), 0, pz)
		K:plate("GuardGlass", w / 2 + 0.08, h - 0.04, 0.02, pane, lk(C(200, 222, 226), M.Glass, { t = 0.62, r = 0.15 }))
		K:plate("GuardSash", 0.07, h - 0.04, 0.05, pane * CF(sx * -(w / 4 + 0.02), 0, 0.0), alu)
		K:plate("GuardSash", w / 2 + 0.08, 0.06, 0.05, pane * CF(0, h / 2 - 0.05, 0), alu)
		K:plate("GuardSash", w / 2 + 0.08, 0.06, 0.05, pane * CF(0, -h / 2 + 0.05, 0), alu)
	end
	-- 창턱 (서류 받는 곳) + 안내
	K:box("GuardSill", V3(w + 0.3, 0.1, 0.55), dcf * CF(0, -h / 2 - 0.08, 0.27), lk(C(150, 116, 84), M.Wood))
	K:box("GuardSillLip", V3(w + 0.3, 0.06, 0.04), dcf * CF(0, -h / 2 - 0.04, 0.53), lk(C(110, 82, 58), M.Wood))
	local sw = math.min(2.2, w + 0.2)
	K:plate("GuardSign", sw, 0.5, 0.06, dcf * CF(0, h / 2 + 0.48, 0.02), lk(C(32, 56, 100)))
	txt(K, "GuardSignText", sw - 0.2, 0.36, dcf * CF(0, h / 2 + 0.48, 0.06), if w >= 2.2 then "경비실 · 관리실" else "경 비 실", WHITE, nil, { font = F.GothamBold })
	txt(K, "GuardNote", math.min(0.9, w / 2 - 0.1), 0.62, dcf * CF(w / 4 + 0.04, -h * 0.18, 0.22), "순찰 중에는\n인터폰으로\n호출해 주세요", C(40, 40, 44), C(250, 248, 236), { font = F.GothamBold, d = 0.005 })
end

-- 디지털 게시판 (신축 로비): 세로형 화면, 공지가 자동으로 넘어감 (Interact.screenLoop)
local function digitalBoard(K: any, dcf: CFrame, w: number, h: number, frames: { any })
	K:plate("DBoardBody", w + 0.16, h + 0.16, 0.12, dcf, lk(C(30, 32, 36), M.Metal))
	local scr = K:plate("DBoardScreen", w, h, 0.02, dcf * CF(0, 0, 0.12), { c = frames[1].c or C(16, 40, 80), m = M.Neon, t = 0.12 })
	K:plate("DBoardHead", w, 0.42, 0.01, dcf * CF(0, h / 2 - 0.21, 0.135), lk(C(250, 250, 250)))
	txt(K, "DBoardHeadText", w * 0.9, 0.3, dcf * CF(0, h / 2 - 0.21, 0.15), "SMART NOTICE  관리사무소", C(30, 40, 60), nil, { font = F.GothamBold })
	local _, lab = txt(K, "DBoardText", w * 0.86, h - 0.9, dcf * CF(0, -0.15, 0.15), frames[1].text, WHITE, nil, { font = F.GothamBold, glow = 1.0 })
	K:plate("DBoardCam", 0.1, 0.1, 0.02, dcf * CF(0, -h / 2 - 0.02, 0.13), Look.black)
	Interact.screenLoop(K, scr, lab, frames, 6)
	return scr
end

local function buildResidence(K: any, V: any, S: any)
	local rng = mkRng(V.key or V.name)
	local name = V.name or "RESIDENCE"
	local warm = hashStr(name) % 2 == 0
	local old = resOld(V)
	local metal = lk(C(196, 198, 202), M.Metal)
	-- 벽 위쪽 페인트 + 뒷벽 아랫부분 석재 (맨션: 크림색 페인트 + 원목 몰딩, 천장은 Common 의 사각 등기구)
	step(K, "skin", function()
		if old then
			wallSkin(K, { "left", "right", "back" }, 3.4, V.H - 0.02, lk(C(244, 238, 222), M.Plaster), lk(C(124, 94, 68), M.Wood))
			addCeilLights(K, V, 4, 3)
		else
			wallSkin(K, { "left", "right", "back" }, 4.0, V.H - 0.02, if warm then lk(C(246, 242, 234), M.Plaster) else lk(C(242, 244, 246), M.Plaster), Look.brushed)
			ceilingLines(K, V, if warm then C(255, 226, 190) else C(240, 246, 255))
		end
	end)
	-- 우편함 (게임플레이 파트: 같은 범위로 덮기)
	local mailFace = nil
	step(K, "mailbox", function()
		for _, r in V.byName.Mailboxes or {} do
			mailFace = mailboxOver(K, V, r, resOld(V))
			K:reserve(r.min - V3(0.2, 0, 0.2), r.max + V3(0.2, 0, 0.2), "mail")
			-- 우편함 앞 (편지 꺼내는 자리) 비움
			local c = r.c
			local f = mailFace :: Vector3
			local fx = if math.abs(f.X) > 0.5 then (if f.X > 0 then r.max.X else r.min.X) else 0
			if math.abs(f.X) > 0.5 then
				K:reserve(V3(math.min(fx, fx + f.X * 2.6), 0, r.min.Z), V3(math.max(fx, fx + f.X * 2.6), 6, r.max.Z), "front")
			else
				local fz = if f.Z > 0 then r.max.Z else r.min.Z
				K:reserve(V3(r.min.X, 0, math.min(fz, fz + f.Z * 2.6)), V3(r.max.X, 6, math.max(fz, fz + f.Z * 2.6)), "front")
			end
			_ = c
		end
	end)
	-- 엘리베이터 홀
	local eh = nil
	step(K, "elevator", function()
		eh = elevatorHall(K, V, nil, "res")
	end)
	-- 엘리베이터 앞 비움 (타고 내리는 자리)
	step(K, "elevfront", function()
		local els = V.byName.ElevatorDoor
		if els and #els > 0 then
			local mn, mx = els[1].min, els[1].max
			for _, r in els do
				mn, mx = mn:Min(r.min), mx:Max(r.max)
			end
			K:reserve(V3(mn.X - 0.5, 0, mx.Z), V3(mx.X + 0.5, 6, mx.Z + 3.4), "front")
		end
	end)
	-- 무인택배함
	local lockerScreen, lockerLab, lockerDoor, lockerHinge = nil, nil, nil, nil
	step(K, "locker", function()
		local h = math.min(6.0, V.H - 0.8)
		for _, w in (if V.W < 13 then { 5.0, 3.8 } else { 6.2, 5.0, 3.8 }) do
			local wn, pcf = wallFloorSpot(K, { "right", "left", "back" }, w, 1.4, h, V3(V.x1, 0, V.z0 + 3), 0.05, "locker", function(pc: CFrame)
				return Interact.canPrompt(K, (pc * CF(0, 4.0, 0.65)).Position)
			end)
			if not wn then
				wn, pcf = wallFloorSpot(K, { "right", "left", "back" }, w, 1.4, h, V3(V.x1, 0, V.z0 + 3), 0.05, "locker")
			end
			if wn and pcf then
				lockerScreen, lockerLab, lockerDoor, lockerHinge = parcelLocker(K, pcf, w, h, rng)
				if lockerScreen and lockerLab then
					local screens = {
						"택배 찾기\n\n동·호수를\n입력하세요", "101동 1203호\n\n보관 중 2건\n12번 · 27번", "비밀번호\n\n● ● ● ●\n\n확인", "택배 맡기기\n\n기사님 전용\n바코드 스캔",
					}
					Interact.cycle(K, lockerScreen, screens, { action = "화면 누르기", object = "무인택배함", on = function(_i, s2)
						if lockerLab and lockerLab.Parent then
							lockerLab.Text = s2
						end
					end })
				end
				if lockerDoor and lockerHinge then
					Interact.swing(K, lockerDoor, lockerHinge, K.cf.UpVector, -1.6, { object = "택배함 큰 칸", openText = "칸 열어 보기", closeText = "닫기" })
				end
				-- 택배함 옆에 쌓인 택배 상자 (기사님이 못 넣은 큰 상자)
				for _, sx in { 1, -1 } do
					local pp = pcf * CF(sx * (w / 2 + 1.12), 0, 0.1)
					if claim(K, pp, V3(1.9, 1.7, 1.4), 0.02, "parcels") then
						parcelPile(K, pp, rng)
						break
					end
				end
				break
			end
		end
	end)
	-- 인터폰 (경비실 호출)
	local icScreen, icLab, icBtn = nil, nil, nil
	step(K, "intercom", function()
		local wn, d = spotNear(K, { "left", "right", "back" }, 1.3, 3.6, 5.6, V3(0, 0, V.z1 - 4), function(dc: CFrame)
			return Interact.canPrompt(K, (dc * CF(0, -0.8, 0.15)).Position)
		end, 0.2)
		if not wn then
			wn, d = spotNear(K, { "left", "right", "back" }, 1.3, 3.6, 5.6, V3(0, 0, V.z1 - 4), nil, 0.2)
		end
		if wn and d then
			icScreen, icLab, icBtn = intercom(K, d * CF(0, 0.05, 0))
			txt(K, "IntercomSticker", 1.1, 0.3, d * CF(0, -1.25, 0.01), "CCTV 24시간 녹화 중", C(200, 40, 40), C(250, 230, 60), { font = F.GothamBold, d = 0.01 })
		end
		-- 프롬프트는 바로 등록 (뒤에 오는 스위치 프롬프트가 2.5 안쪽 자리를 차지하지 않게)
		if icBtn and icLab then
			local busy = false
			Interact.prompt(K, icBtn, { action = "경비실 호출", object = "공동현관 인터폰", fn = function()
				if busy then
					return
				end
				busy = true
				if icLab.Parent then
					icLab.Text = "경비실 호출 중…\n♪ ♪ ♪"
				end
				task.delay(2.2, function()
					if icLab.Parent then
						icLab.Text = "경비실입니다\n무엇을 도와드릴까요?"
					end
					task.delay(3.0, function()
						busy = false
						if icLab.Parent then
							icLab.Text = "세대 호출\n동 · 호수 입력"
						end
					end)
				end)
			end })
		end
	end)
	-- 조명 스위치 (프롬프트) 먼저: 큰 벽 소품이 프롬프트 자리를 차지하지 않게 (맨션은 경비실 창 다음)
	step(K, "switch", function()
		if not old then
			ensureSwitch(K, V)
		end
	end)
	-- 벤치 + 위 게시판
	local benchU = nil
	step(K, "bench", function()
		local wn, pcf, u = wallFloorSpot(K, { "right", "left" }, 3.8, 1.5, 2.0, V3(V.x1, 0, 0.5), 0.1, "bench")
		if wn and pcf then
			bench(K, pcf, 3.6, if warm then Look.oak else Look.walnut, Look.blackMetal)
			benchU = { wn = wn, u = u }
			-- 신축: 벤치 뒤 우드 루버 포인트 벽 (타일 위로 살짝 띄움) + 벤치 아래 간접등
			if not old and u then
				local top = if wallFree(K, wn, u, 4.6, 2.3, 3.95, 0.1) then 3.95 else 2.3
				local slat = if warm then lk(C(184, 146, 104), M.Wood) else lk(C(110, 84, 64), M.Wood)
				local groove = if warm then lk(C(126, 94, 64), M.Wood) else lk(C(66, 50, 40), M.Wood)
				K:free(function()
					local c = V:wall(wn, u, (0.45 + top) / 2, 0.06)
					local len, hh = 4.6, top - 0.45
					K:plate("BenchLouverBack", len, hh, 0.02, c, groove)
					local pitch = if lo(K) then 0.5 else 0.3
					local n = math.floor(len / pitch)
					for i = 0, n - 1 do
						K:plate("BenchLouver", pitch * 0.72, hh, 0.06, c * CF(-len / 2 + pitch * (i + 0.5), 0, 0.02), slat)
					end
					K:plate("BenchLouverCap", len + 0.06, 0.06, 0.1, c * CF(0, hh / 2 + 0.03, 0), Look.brushed)
					K:box("BenchGlow", V3(3.2, 0.04, 0.06), pcf * CF(0, 1.5, 0.45), Look.neon(C(255, 222, 180)))
				end)
			end
		end
	end)
	step(K, "notice", function()
		local sheets = {
			{ "관리비 납부 안내", "10월분 관리비\n고지서 배부 완료\n납부기한 10.31(금)\n자동이체 신청 가능", { band = C(30, 70, 140) } },
			{ "소독 실시 안내", "10월 22일(수)\n10:00 ~ 17:00\n세대 방문 소독\n부재 시 관리실 연락", { band = C(40, 140, 90) } },
			{ "분리수거 요일", "월 · 목 18시 이후\n음식물: 매일\n대형폐기물은\n스티커 부착 후 배출", { band = C(210, 120, 30) } },
			{ "층간소음 예방", "밤 10시 이후\n세탁기 · 청소기\n사용을 자제해 주세요", { band = C(150, 60, 140) } },
			{ "주차 안내", "방문 차량은\n사전 등록 후 이용\n관리실 051-752-0100", { band = C(60, 60, 70) } },
			{ "택배 분실 주의", "택배는 무인택배함\n이용을 권장합니다\n공용부 방치 금지", { band = C(200, 50, 50) } },
		}
		local wn, d
		local w = 4.4
		if benchU and wallFree(K, benchU.wn, benchU.u, w + 0.2, 3.6, 6.9, 0.3) then
			wn, d = benchU.wn, V:wall(benchU.wn, benchU.u, 5.25, 0.0)
		end
		if not wn then
			for _, ww in { 4.4, 3.0, 2.2 } do
				wn, d = wallItemSpot(K, { "right", "left", "back" }, ww, 3.6, 6.9, 0)
				if wn then
					w = ww
					break
				end
			end
		end
		if not wn then
			-- 벽이 거의 다 찬 작은 로비: 좁은 세로 게시판 (종이 2장)
			wn, d = wallScan(K, { "right", "left", "back" }, 1.6, 3.6, 6.9, V3(0, 0, V.z1), 0.3)
			if wn then
				w = 1.5
			end
		end
		if wn and d then
			local cols = if w > 4 then 3 elseif w > 2.8 then 2 elseif w > 2 then 2 else 1
			local list = {}
			for i = 1, (if w > 4 then 6 elseif w > 2.8 then 4 else 2) do
				list[i] = sheets[i]
			end
			if old then
				noticeBoard(K, d, w, 3.1, if w > 2.8 then "관리사무소 알림  NOTICE" else "관리사무소 알림", list, { cols = cols, head = C(110, 40, 40) })
			else
				-- 신축: 유리 덮개 알루미늄 게시판 (회색 펠트 · 검은 틀)
				noticeBoard(K, d, w, 3.1, if w > 2.8 then "입주민 알림  NOTICE" else "입주민 알림", list, { cols = cols, head = C(30, 60, 110), felt = lk(C(206, 208, 210), M.Fabric), frame = Look.blackMetal })
				K:free(function()
					K:plate("NoticeGlass", w - 0.04, 3.06, 0.01, d * CF(0, 0, 0.14), lk(C(220, 236, 240), M.Glass, { t = 0.82, r = 0.2 }))
				end)
			end
		end
	end)
	-- 맨션: 경비실 창 / 신축: 디지털 게시판
	step(K, "guard", function()
		if old then
			local gh = 2.3
			for _, gw in { 3.2, 2.4, 1.6 } do
				local wn, d = wallItemSpot(K, { "left", "right", "back" }, gw + 0.5, 2.9, 3.2 + gh + 0.9, 0, nil, 0.7)
				if not wn then
					wn, d = wallScan(K, { "left", "right", "back" }, gw + 0.5, 2.9, 3.2 + gh + 0.9, V3(0, 0, V.z1), 0.7)
				end
				if wn and d then
					guardWindow(K, d * CF(0, -(gh + 0.9 + 0.3) / 2 + 0.3 + gh / 2, 0), gw, gh)
					break
				end
			end
			ensureSwitch(K, V)
		else
			local wn, d = wallItemSpot(K, { "left", "right", "back" }, 2.4, 2.3, 6.1, 0, nil, 0.3)
			if wn and d then
				digitalBoard(K, d, 2.0, 3.5, {
					{ c = C(16, 40, 80), text = "관리비 고지\n\n10월분 관리비\n자동이체 25일\n\n입주민 앱에서\n확인하세요" },
					{ c = C(16, 70, 60), text = "택배 보관 안내\n\n무인택배함 이용\n48시간 지나면\n관리실로 옮깁니다" },
					{ c = C(80, 28, 30), text = "승강기 정기점검\n\n10월 21일(화)\n10:00 ~ 12:00\n1호기 운행 중지" },
					{ c = C(24, 30, 64), text = "오늘의 광안리\n\n맑음  21°C\n미세먼지 좋음\n\n드론쇼 토 20:00" },
				})
			end
		end
	end)
	-- 건물 이름 (스테인리스 글자)
	step(K, "nameplate", function()
		local w = math.min(6.5, math.max(3.5, #name * 0.32))
		local wn, d = wallItemSpot(K, { "left", "right", "back" }, w + 0.6, 6.4, 7.6, 0)
		if not wn then
			wn, d = wallItemSpot(K, { "left", "right", "back" }, w + 0.6, math.min(6.0, V.H - 2.2), math.min(7.2, V.H - 1.0), 0)
		end
		if wn and d then
			K:free(function()
				K:plate("NameBacker", w + 0.5, 1.15, 0.05, d, if warm then lk(C(70, 58, 48), M.Wood) else lk(C(44, 46, 50), M.Slate))
				metalText(K, "BuildingName", d * CF(0, 0.15, 0.06), w, 0.62, string.upper(name), C(222, 224, 228), F.GothamMedium)
				txt(K, "BuildingNameSub", w * 0.7, 0.24, d * CF(0, -0.36, 0.1), "부산광역시 수영구 광안해변로", C(200, 202, 206), nil, { font = F.Gotham })
			end)
		end
	end)
	-- 소화전 · 비상구 · CCTV 안내 · 우산 비닐 · 화분
	step(K, "safety", function()
		local wn, d = spotNear(K, { "left", "right", "back" }, 1.95, 1.0, 5.4, V3(V.x0, 0, V.z0), nil, 0.4)
		if wn and d then
			hydrant(K, d * CF(0, -3.2, 0))
		end
		local wn3, d3 = spotNear(K, { "left", "right" }, 1.7, math.min(7.0, V.H - 1.5), math.min(7.7, V.H - 0.8), V3(V.x0, 0, V.z1 - 2))
		if wn3 and d3 then
			exitSign(K, d3)
		end
		local dd = V.door
		if dd then
			local cands = { V3(dd.x - dd.w / 2 - 2.9, 0, V.z1 - 1.0), V3(dd.x + dd.w / 2 + 2.9, 0, V.z1 - 1.0), V3(V.x0 + 0.9, 0, V.z1 - 3.5), V3(V.x1 - 0.9, 0, V.z1 - 3.5) }
			local pcf = floorSpot(K, cands, V3(2.4, 3.0, 1.0), V3(0, 0, 1), 0.05, "umbrella")
			if pcf then
				umbrellaBagger(K, pcf, if pcf.Position.X < dd.x then -1 else 1)
			end
		end
		for _, p in { V3(V.x0 + 1.0, 0, V.z0 + 1.0), V3(V.x1 - 1.0, 0, V.z0 + 1.0) } do
			plantAt(K, pcfAt(p, V3(0, 0, 1)), pickR(rng, { "snake", "ficus", "bamboo" }), math.min(5.5, V.H * 0.55), 1.3, lk(C(70, 70, 72), M.Concrete))
		end
	end)
	step(K, "fixtures", function()
		fixturesSorted(K, V, S)
	end)
	_ = metal
	_ = eh
	step(K, "posters", function()
		fillPosters(K, POSTERS.residence, 2)
	end)
end

---------------------------------------------------------------------------------------------------
-- 8. 공인중개사
---------------------------------------------------------------------------------------------------

-- 상담 책상 덮어씌우기 (맵 TableTop: 같은 윗면 · 범위, 위는 비움)
local function consultDeskOver(K: any, V: any, t: any, topL: any)
	local mn, mx = t.min, t.max
	local y = t.y
	local w, l = mx.X - mn.X, mx.Z - mn.Z
	local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
	local body = lk(C(236, 234, 228))
	local _ = topL
	K:free(function()
		-- 상판: 원목 + 유리 덮개 아래 동네 지도 · 매물 전단 (부동산 상담 책상의 상징). 윗면 높이 = 맵 TableTop
		local wood = lk(C(150, 112, 78), M.Wood)
		K:box("ConsultTop", V3(w, 0.1, l), CF(cx, y - 0.075, cz), wood)
		K:box("ConsultEdge", V3(w + 0.01, 0.05, l + 0.01), CF(cx, y - 0.145, cz), lk(C(60, 44, 32), M.Wood))
		K:box("ConsultUnderMap", V3(w - 0.3, 0.012, l - 0.3), CF(cx, y - 0.019, cz), lk(C(196, 220, 186)))
		if not lo(K) then
			-- 지도 위 도로 · 해안선 · 끼워 둔 전단
			K:box("ConsultUnderSea", V3((w - 0.3) * 0.32, 0.013, l - 0.3), CF(cx + (w - 0.3) * 0.34, y - 0.018, cz), lk(C(110, 168, 214)))
			K:box("ConsultUnderRoad", V3(w - 0.3, 0.014, 0.06), CF(cx, y - 0.017, cz - l * 0.12), lk(C(250, 250, 246)))
			K:box("ConsultUnderRoad", V3(0.06, 0.014, l - 0.3), CF(cx - w * 0.12, y - 0.017, cz), lk(C(250, 250, 246)))
			for i, off in { { -0.28, 0.2 }, { 0.05, -0.22 } } do
				K:box("ConsultUnderSheet", V3(0.75, 0.015, 1.0), CF(cx + w * off[1], y - 0.016, cz + l * off[2]) * ANG(0, (i - 1.5) * 0.3, 0), Look.paper)
			end
		end
		K:box("ConsultGlass", V3(w - 0.04, 0.012, l - 0.04), CF(cx, y - 0.006, cz), lk(C(200, 230, 226), M.Glass, { t = 0.72, r = 0.15 }))
		-- 다리: 검은 철제 썰매형 프레임 + 원목 가림판
		local alongX = w >= l
		for _, sx in { -1, 1 } do
			if alongX then
				local x = cx + sx * (w / 2 - 0.25)
				K:box("ConsultLeg", V3(0.1, y - 0.2, 0.1), CF(x, (y - 0.2) / 2, cz - l / 2 + 0.25), Look.blackMetal)
				K:box("ConsultLeg", V3(0.1, y - 0.2, 0.1), CF(x, (y - 0.2) / 2, cz + l / 2 - 0.25), Look.blackMetal)
				K:box("ConsultFoot", V3(0.12, 0.08, l - 0.4), CF(x, 0.04, cz), Look.blackMetal)
				K:box("ConsultRail", V3(0.1, 0.1, l - 0.4), CF(x, y - 0.25, cz), Look.blackMetal)
			else
				local z = cz + sx * (l / 2 - 0.25)
				K:box("ConsultLeg", V3(0.1, y - 0.2, 0.1), CF(cx - w / 2 + 0.25, (y - 0.2) / 2, z), Look.blackMetal)
				K:box("ConsultLeg", V3(0.1, y - 0.2, 0.1), CF(cx + w / 2 - 0.25, (y - 0.2) / 2, z), Look.blackMetal)
				K:box("ConsultFoot", V3(w - 0.4, 0.08, 0.12), CF(cx, 0.04, z), Look.blackMetal)
				K:box("ConsultRail", V3(w - 0.4, 0.1, 0.1), CF(cx, y - 0.25, z), Look.blackMetal)
			end
		end
		if alongX then
			K:box("ConsultModesty", V3(w - 0.5, 1.1, 0.06), CF(cx, y - 0.8, cz), wood)
		else
			K:box("ConsultModesty", V3(0.06, 1.1, l - 0.5), CF(cx, y - 0.8, cz), wood)
		end
		_ = body
	end)
	for _, r in t.parts do
		hideRec(K, r)
	end
	K:reserve(V3(mn.X, 0, mn.Z), V3(mx.X, y + 0.2, mx.Z), "table")
end

-- 매물 카드 게시판
local LISTINGS = {
	{ "매매", "광안 자이 84㎡\n12층 · 오션뷰", "9억 2,000" }, { "전세", "삼익비치 전용 84\n리모델링", "4억 5,000" }, { "월세", "광안동 원룸 6평\n풀옵션", "500 / 45" },
	{ "매매", "민락 더샵 102㎡\n바다 정면", "13억 8,000" }, { "월세", "오피스텔 25㎡\n해변 1분", "1,000 / 70" }, { "전세", "남천 코오롱 59㎡\n역세권", "3억 2,000" },
	{ "매매", "광안 롯데캐슬\n84㎡ 고층", "10억 5,000" }, { "임대", "1층 상가 15평\n광안리 먹자골목", "3,000 / 250" }, { "월세", "투룸 빌라\n수영역 5분", "1,000 / 60" },
	{ "매매", "수영 SK뷰 84㎡\n남향 · 정원", "8억 3,000" }, { "전세", "망미 주공 59㎡\n학군 우수", "2억 6,000" }, { "월세", "복층 오피스텔\n민락동", "500 / 85" },
	{ "매매", "광안 경동리인\n113㎡ 펜트", "18억" }, { "임대", "사무실 30평\n수영로", "2,000 / 180" }, { "전세", "광안 비치 오피\n신축 2026", "2억 1,000" },
}
local DEAL_COL = { ["매매"] = C(200, 40, 50), ["전세"] = C(30, 90, 180), ["월세"] = C(30, 140, 80), ["임대"] = C(220, 130, 30) }

local function listingBoard(K: any, dcf: CFrame, w: number, h: number, rng: () -> number): (BasePart?, TextLabel?)
	local feat, featLab = nil, nil
	if w >= 5.0 then
		-- 오른쪽 1/3: 오늘의 추천 매물 (큰 카드, 넘기기 상호작용)
		local fw = math.min(2.4, w * 0.34)
		local fd = dcf * CF(w / 2 - fw / 2, 0, 0)
		K:plate("ListFeatBack", fw, h, 0.08, fd, lk(C(24, 50, 100)))
		txt(K, "ListFeatTitle", fw * 0.86, 0.36, fd * CF(0, h / 2 - 0.35, 0.09), "오늘의 추천", C(255, 214, 90), nil, { font = F.GothamBlack })
		feat = K:plate("ListFeatCard", fw - 0.24, h - 0.9, 0.02, fd * CF(0, -0.25, 0.08), Look.paper)
		local L = LISTINGS[1]
		local _, lab = txt(K, "ListFeatText", fw - 0.4, h - 1.1, fd * CF(0, -0.25, 0.105), L[1] .. "\n\n" .. L[2] .. "\n\n" .. L[3], C(24, 50, 100), nil, { font = F.GothamBold })
		featLab = lab
		K:plate("ListFeatRule", fw - 0.5, 0.05, 0.03, fd * CF(0, h / 2 - 0.62, 0.09), lk(C(255, 214, 90)))
		w = w - fw - 0.1
		dcf = dcf * CF(-(fw + 0.1) / 2, 0, 0)
	end
	K:plate("ListBoard", w, h, 0.08, dcf, lk(C(244, 244, 240)))
	K:plate("ListFrame", w + 0.12, h + 0.12, 0.06, dcf * CF(0, 0, -0.03), Look.alu)
	local hh = 0.62
	K:plate("ListHeader", w, hh, 0.09, dcf * CF(0, h / 2 - hh / 2, 0), lk(C(24, 50, 100)))
	txt(K, "ListHeaderText", w * 0.9, hh * 0.7, dcf * CF(0, h / 2 - hh / 2, 0.095), "추천 매물  ·  광안 · 민락 · 남천 · 수영", WHITE, nil, { font = F.GothamBlack })
	local cols = math.max(3, math.floor(w / 1.35))
	local rows = math.max(2, math.floor((h - hh - 0.2) / 1.25))
	local cw = (w - 0.2) / cols
	local rh = (h - hh - 0.2) / rows
	local order = {}
	for i = 1, #LISTINGS do
		order[i] = i
	end
	for i = #order, 2, -1 do
		local j = math.floor(rng() * i) + 1
		order[i], order[j] = order[j], order[i]
	end
	local n = 0
	for ri = 1, rows do
		for ci = 1, cols do
			n += 1
			local L = LISTINGS[order[(n - 1) % #order + 1]]
			local x = -w / 2 + 0.1 + cw * (ci - 0.5)
			local y = h / 2 - hh - 0.1 - rh * (ri - 0.5)
			local card = dcf * CF(x, y, 0.085)
			local cwid, chgt = cw - 0.12, rh - 0.12
			K:plate("ListCard", cwid, chgt, 0.01, card, Look.paper)
			K:plate("ListCardBand", cwid, chgt * 0.24, 0.012, card * CF(0, chgt * 0.38, 0), lk(DEAL_COL[L[1]] or C(60, 60, 60)))
			txt(K, "ListCardDeal", cwid * 0.8, chgt * 0.2, card * CF(0, chgt * 0.38, 0.015), L[1], WHITE, nil, { font = F.GothamBlack })
			-- 내용 + 가격을 글자판 하나로 (글자판 수 절약)
			txt(K, "ListCardBody", cwid * 0.9, chgt * 0.62, card * CF(0, -chgt * 0.12, 0.012), L[2] .. "\n" .. L[3], C(30, 30, 40), Look.paper.c, { font = F.GothamBold, d = 0.01 })
			K:ball("ListPin", 0.08, card * CF(0, chgt / 2 - 0.05, 0.03), lk(pickR(rng, { C(220, 40, 40), C(40, 120, 220), C(240, 200, 40) })))
		end
	end
	return feat, featLab
end

-- 수영구 지도 (해안선 · 광안대교 · 동 이름 · 매물 핀)
local function suyeongMap(K: any, dcf: CFrame, w: number, h: number)
	K:plate("MapFrame", w + 0.2, h + 0.2, 0.08, dcf, Look.walnut)
	local d = dcf * CF(0, 0, 0.08)
	K:plate("MapLand", w, h, 0.01, d, lk(C(236, 232, 218)))
	-- 바다 (아래 · 오른쪽)
	K:plate("MapSea", w, h * 0.32, 0.012, d * CF(0, -h * 0.34, 0.001), lk(C(150, 196, 226)))
	K:plate("MapBay", w * 0.36, h * 0.2, 0.012, d * CF(w * 0.08, -h * 0.12, 0.001), lk(C(150, 196, 226)))
	K:plate("MapBeach", w * 0.36, 0.08, 0.013, d * CF(w * 0.08, -h * 0.01, 0.002), lk(C(240, 214, 150)))
	-- 금련산 (녹지)
	K:plate("MapPark", w * 0.3, h * 0.28, 0.012, d * CF(-w * 0.3, h * 0.2, 0.001), lk(C(176, 210, 160)))
	-- 도로
	K:plate("MapRoad", w, 0.08, 0.013, d * CF(0, h * 0.12, 0.002), lk(C(255, 255, 255)))
	K:plate("MapRoad", 0.08, h * 0.7, 0.013, d * CF(w * 0.22, h * 0.15, 0.002), lk(C(255, 255, 255)))
	K:plate("MapRoad", w * 0.8, 0.06, 0.013, d * CF(-w * 0.05, h * 0.33, 0.002) * ANG(0, 0, 0.08), lk(C(250, 220, 120)))
	K:plate("MapRoad", 0.06, h * 0.6, 0.013, d * CF(-w * 0.08, h * 0.15, 0.002) * ANG(0, 0, -0.2), lk(C(255, 255, 255)))
	-- 광안대교
	K:plate("MapBridge", w * 0.62, 0.07, 0.014, d * CF(w * 0.12, -h * 0.26, 0.003) * ANG(0, 0, 0.12), lk(C(90, 90, 110)))
	-- 지하철 2호선
	K:plate("MapSubway", w * 0.9, 0.05, 0.014, d * CF(0, h * 0.04, 0.003) * ANG(0, 0, -0.05), lk(C(60, 170, 70)))
	for i, s in { "수영역", "광안역", "금련산역", "남천역" } do
		local x = w * 0.4 - (i - 1) * w * 0.26
		K:ball("MapStation", 0.14, d * CF(x, h * 0.04 + (i - 1) * 0.04, 0.02), Look.white)
		txt(K, "MapStationText", 0.9, 0.2, d * CF(x, h * 0.04 - 0.2, 0.016), s, C(40, 120, 50), nil, { font = F.GothamBold, d = 0.004 })
	end
	local labels = {
		{ "수영구 광안동", -0.05, 0.22, 0.32 }, { "민락동", 0.36, 0.22, 0.24 }, { "남천동", -0.38, -0.06, 0.24 }, { "망미동", 0.08, 0.42, 0.22 },
		{ "금련산", -0.3, 0.3, 0.2 }, { "광안리해수욕장", 0.08, -0.06, 0.2 }, { "광안대교", 0.14, -0.33, 0.2 }, { "수영강", 0.42, 0.42, 0.18 },
	}
	for _, l in labels do
		txt(K, "MapLabel", w * 0.3, h * 0.06 * (l[4] / 0.22), d * CF(w * l[2], h * l[3], 0.016), l[1], C(50, 50, 60), nil, { font = F.GothamBold, d = 0.004 })
	end
	-- 매물 핀
	for i = 1, 7 do
		local x = ((i * 37) % 17) / 17 - 0.5
		local y = ((i * 23) % 13) / 13 * 0.5 - 0.05
		K:ball("MapPin", 0.13, d * CF(w * x * 0.8, h * y, 0.05), lk(if i % 3 == 0 then C(30, 90, 180) else C(220, 40, 40)))
	end
	txt(K, "MapTitle", w * 0.5, 0.36, d * CF(-w * 0.22, h / 2 - 0.3, 0.016), "수영구 생활권 지도", C(30, 40, 70), C(250, 248, 240), { font = F.GothamBlack, d = 0.01 })
	K:plate("MapGlass", w, h, 0.01, d * CF(0, 0, 0.07), { c = C(230, 236, 240), m = M.Glass, t = 0.9, r = 0.18 })
end

-- 서류 · 매물장부 책장
local function binderCabinet(K: any, pcf: CFrame, w: number, h: number, rng: () -> number)
	local body = lk(C(232, 230, 224))
	K:box("CabBody", V3(w, h, 1.0), pcf * CF(0, h / 2, 0), body)
	K:box("CabInner", V3(w - 0.16, h - 1.9, 0.1), pcf * CF(0, 1.6 + (h - 1.9) / 2, -0.4), lk(C(200, 198, 192)))
	-- 아래 여닫이 2문
	for _, sx in { -1, 1 } do
		K:plate("CabDoor", w / 2 - 0.06, 1.35, 0.03, CFrame.fromMatrix((pcf * CF(sx * w / 4, 0.8, 0.5)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector), body)
		K:plate("CabKnob", 0.05, 0.3, 0.04, CFrame.fromMatrix((pcf * CF(sx * 0.12, 0.9, 0.53)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector), Look.brushed)
	end
	local labels = { "매물장부 2026", "계약서 보관", "등기부등본", "임대차 신고", "중개대상물 확인", "세무 · 영수증", "건축물대장" }
	local shelves = math.max(2, math.floor((h - 1.9) / 1.15))
	for si = 1, shelves do
		local y = 1.6 + (si - 1) * 1.15
		K:box("CabShelf", V3(w - 0.16, 0.06, 0.9), pcf * CF(0, y, 0), body)
		local x = -w / 2 + 0.2
		local k = 0
		while x < w / 2 - 0.35 do
			k += 1
			local bw = 0.28
			local col = pickR(rng, { C(30, 60, 140), C(30, 60, 140), C(200, 40, 40), C(40, 40, 44), C(230, 180, 40) })
			K:box("Binder", V3(bw - 0.02, 0.95, 0.8), pcf * CF(x + bw / 2, y + 0.03 + 0.475, 0.0), lk(col))
			if not lo(K) and k % 2 == 1 then
				K:plate("BinderLabel", 0.18, 0.5, 0.01, CFrame.fromMatrix((pcf * CF(x + bw / 2, y + 0.55, 0.41)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector), Look.paper)
			end
			x += bw
			if k == 9 then
				break
			end
		end
		if hi(K) then
			txt(K, "CabShelfLabel", 1.4, 0.16, CFrame.fromMatrix((pcf * CF(0, y + 0.02, 0.47)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector), labels[(si - 1) % #labels + 1], C(60, 60, 60), Look.paper.c, { font = F.GothamBold, d = 0.01 })
		end
	end
end

-- 복합기 (프린터 · 팩스 · 스캐너)
local function mfp(K: any, pcf: CFrame): BasePart
	K:box("MfpCabinet", V3(1.8, 1.2, 1.5), pcf * CF(0, 0.6, 0), lk(C(70, 72, 76)))
	K:box("MfpBody", V3(1.8, 1.4, 1.5), pcf * CF(0, 1.9, 0), lk(C(234, 234, 230)))
	K:box("MfpScanner", V3(1.75, 0.3, 1.45), pcf * CF(0, 2.75, -0.02), lk(C(220, 220, 216)))
	K:box("MfpPanel", V3(0.7, 0.08, 0.4), pcf * CF(0.45, 2.9, 0.55) * ANG(0.35, 0, 0), Look.charcoal)
	K:plate("MfpScreen", 0.5, 0.26, 0.01, CFrame.fromMatrix((pcf * CF(0.45, 2.945, 0.55)).Position, pcf.XVector, (Vector3.yAxis * 0.35 - pcf.ZVector).Unit, (Vector3.yAxis + pcf.ZVector * 0.35).Unit), lk(C(110, 170, 220), M.Neon, { t = 0.3 }))
	K:box("MfpTray", V3(1.2, 0.04, 0.9), pcf * CF(-0.1, 2.35, 0.3), lk(C(200, 200, 196)))
	local paperOut = K:box("MfpPaperOut", V3(0.85, 0.03, 0.95), pcf * CF(-0.1, 2.39, 0.3), Look.paper)
	for i = 0, 2 do
		K:plate("MfpDrawer", 1.7, 0.36, 0.02, CFrame.fromMatrix((pcf * CF(0, 0.25 + i * 0.4, 0.76)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector), lk(C(60, 62, 66)))
	end
	return paperOut
end

local function buildRealty(K: any, V: any, S: any)
	local rng = mkRng(V.key or V.name)
	local name = V.name or "공인중개사"
	if not string.find(name, "중개", 1, true) and not string.find(name, "부동산", 1, true) then
		name = pickR(rng, { "광안 해변 공인중개사", "민락 바다 공인중개사", "수영 제일 공인중개사" })
	end
	local wood = lk(C(132, 98, 70), M.Wood)
	local white = lk(C(240, 240, 236))
	step(K, "skin", function()
		wallSkin(K, { "left", "right", "back" }, 0.45, V.H - 0.02, lk(C(240, 238, 232), M.Plaster))
		Props.wainscot(K, "back", 3.0, { look = lk(C(226, 222, 212)), cap = wood, panel = 0 })
		addCeilLights(K, V, 4, 2)
	end)
	-- 맵 상담 책상 → 깔끔한 사무 책상 (위는 비움) + 맞은편 직원 의자
	step(K, "consult", function()
		for _, t in V.tables do
			if t.kind ~= "grill" then
				consultDeskOver(K, V, t, white)
				-- 손님 의자 반대편에 직원 의자
				local c = (t.min + t.max) / 2
				local guest = nil
				for _, ch in V.chairs do
					if ch.table == t then
						guest = ch
					end
				end
				local dir = if guest then snap(V3(c.X, 0, c.Z) - V3(guest.seat.c.X, 0, guest.seat.c.Z)) else V3(0, 0, -1)
				local half = if math.abs(dir.X) > 0.5 then (t.max.X - t.min.X) / 2 else (t.max.Z - t.min.Z) / 2
				local p = V3(c.X, 0, c.Z) + dir * (half + 0.55)
				local pcf = pcfAt(p, -dir)
				if claim(K, pcf, V3(1.6, 3.4, 1.4), 0, "chair") then
					officeChair(K, pcf)
				end
			end
		end
	end)
	-- 맵 카운터 위 모니터 교체 + 업무 소품
	step(K, "counter", function()
		for _, r in V.byName.Monitor or {} do
			local g = nil
			for _, cg in V.counters do
				if r.c.X >= cg.min.X - 0.3 and r.c.X <= cg.max.X + 0.3 and r.c.Z >= cg.min.Z - 0.6 and r.c.Z <= cg.max.Z + 0.6 then
					g = cg
				end
			end
			if g then
				hideRec(K, r)
				local top = g.y
				K:free(function()
					local base = topAt(r.c.X, top, r.c.Z, V3(0, 0, -1))
					monitor(K, base, 1.7, "매물 관리 시스템\n신규 문의 4건\n오늘 계약 1건")
					keyboard(K, base * CF(0, 0, 0.75), 1.2)
					deskPhone(K, topAt(r.c.X + 1.8, top, r.c.Z + 0.1, V3(0, 0, -1)))
					paperStack(K, topAt(r.c.X - 1.6, top, r.c.Z + 0.2, V3(0, 0, -1)), 0.7, 0.95, 4)
					Props.cardTerminal(K, topAt(r.c.X + 3.0, top, (g.min.Z + g.max.Z) / 2, V3(0, 0, 1)))
				end)
			end
		end
	end)
	-- 직원 책상 (뒷벽, 의자는 벽 쪽)
	local desks = 0
	step(K, "desks", function()
		local want = if V.W > 26 then 2 else 1
		for i = 1, want do
			local wn, pcf = wallFloorSpot(K, { "back" }, 3.8, 3.2, 3.4, V3(if i == 1 then V.x1 - 4 else V.x0 + 6, 0, V.z0), 0.05, "desk")
			if wn and pcf then
				desks += 1
				local dcf = pcf * CF(0, 0, 3.2 / 2 - 0.9)
				local top = officeDesk(K, dcf, 3.6, 1.7, if i == 1 then wood else white)
				deskKit(K, top, 3.6, 1.7, if i == 1 then "대표 공인중개사" else "소속 공인중개사", nil, rng)
				officeChair(K, pcf * CF(0, 0, -3.2 / 2 + 0.75))
				-- 손님 의자 (앞)
				for _, gx in { 0.6, -0.6, 1.1, -1.1 } do
					local gp = dcf * CF(gx, 0, 1.72)
					local gpcf = pcfAt(gp.Position, -dcf.ZVector)
					if claim(K, gpcf, V3(1.5, 3.0, 1.5), 0, "chair") then
						guestChair(K, gpcf)
						break
					end
				end
			end
		end
	end)
	-- 손님 소파 + 작은 테이블
	step(K, "sofa", function()
		local fab = pickR(rng, { lk(C(92, 100, 112), M.Fabric), lk(C(150, 120, 92), M.Leather), lk(C(70, 84, 76), M.Fabric) })
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 4.2, 2.4, 3.2, V3(V.x0, 0, 0), 0.05, "sofa")
		if not (wn and pcf) then
			-- 좁은 매장: 2인용 (벽 쪽) → 없으면 앞 유리창에 등을 댄 2인용 (창 keep 3.4 아래, 문 keep 밖)
			local lw
			for _, l2 in { 3.4, 3.0 } do
				wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, l2 + 0.1, 2.4, 3.2, V3(V.x0, 0, 0), 0.05, "sofa")
				if wn and pcf then
					lw = l2
					break
				end
			end
			if not (wn and pcf) then
				local d = V.door
				for _, l2 in { 3.4, 3.0 } do
					local cands = {}
					for _, side in { -1, 1 } do
						local dx = if d then d.x + side * ((d.w or 4.8) / 2 + 2.2 + l2 / 2) else side * (l2 / 2 + 3)
						for k = 0, 3 do
							table.insert(cands, V3(dx + side * k * 0.8, 0, V.z1 - 1.25))
						end
					end
					for _, p in cands do
						-- 소파 앞 1.4 는 지나다닐 자리로 함께 비워 둠
						local pc = pcfAt(p, V3(0, 0, -1))
						if claim(K, pc * CF(0, 0, 0.7), V3(l2 + 0.1, 3.2, 3.8), 0.03, "sofa") then
							pcf, lw = pc, l2
							break
						end
					end
					if pcf then
						break
					end
				end
			end
			if pcf and lw then
				sofa(K, pcf * CF(0, 0, -0.02), lw, fab)
				K:box("SofaThrow", V3(0.9, 0.05, 1.5), pcf * CF(lw / 2 - 0.9, 1.6, 0.25) * ANG(0, 0.1, 0), lk(C(214, 200, 176), M.Fabric))
			end
			return
		end
		if wn and pcf then
			sofa(K, pcf * CF(0, 0, -0.02), 4.0, fab)
			local tp = pcf * CF(0, 0, 2.2)
			if claim(K, tp, V3(2.0, 1.4, 1.2), 0, "table") then
				K:box("SofaTableTop", V3(2.0, 0.1, 1.1), tp * CF(0, 1.3, 0), lk(C(240, 240, 236)))
				for _, sx in { -1, 1 } do
					K:box("SofaTableLeg", V3(0.08, 1.25, 1.0), tp * CF(sx * 0.9, 0.62, 0), Look.blackMetal)
				end
				K:box("SofaTableFolder", V3(0.9, 0.04, 1.0), tp * CF(-0.3, 1.37, 0) * ANG(0, 0.2, 0), lk(C(30, 60, 140)))
				K:vcyl("SofaTableCup", 0.25, 0.22, tp * CF(0.55, 1.47, 0.1), Look.paper)
			end
		end
	end)
	-- 매물판 (가장 넓은 벽 자리, 입구에서 보이게)
	step(K, "listing", function()
		local w = math.min(8.0, V.W * 0.36)
		local top = math.min(V.H - 0.6, 7.3)
		local wn, d = wallItemSpot(K, { "back" }, w, 3.4, top, 0)
		if not wn then
			wn, d = wallItemSpot(K, { "back", "left", "right" }, w * 0.7, 3.4, top, 0)
			w = w * 0.7
		end
		if wn and d then
			-- 매물판 위 조명 (픽처 라이트 2) + 켜고 끄기
			local bh = top - 3.6
			local lamps = {}
			K:free(function()
				for _, fx in { -0.27, 0.27 } do
					local ld = d * CF(w * fx - (if w >= 5 then 0.6 else 0), bh / 2 + 0.22, 0)
					K:box("BoardLightArm", V3(0.08, 0.08, 0.5), ld * CF(0, 0, 0.25), Look.blackMetal)
					K:cyl("BoardLightHood", w * 0.3, 0.22, ld * CF(0, 0.04, 0.52), Look.blackMetal)
					local led = K:cyl("BoardLightLED", w * 0.28, 0.12, ld * CF(0, -0.03, 0.52), Look.lampNeutral)
					table.insert(lamps, led)
				end
				if lamps[1] then
					K:light(lamps[1], "SpotLight", { Face = Enum.NormalId.Bottom, Range = 7, Brightness = 0.7, Angle = 80, Color = Look.neutralLight })
				end
			end)
			if #lamps > 0 then
				promptOn(K, { lamps[1], lamps[2] }, { action = "매물판 조명 끄기", object = "매물 게시판 조명", fn = function(n, pr)
					local on = n % 2 == 0
					for _, l in lamps do
						if l.Parent then
							l.Material = if on then M.Neon else M.SmoothPlastic
							l.Color = if on then C(255, 240, 220) else C(90, 90, 92)
							for _, c in l:GetChildren() do
								if c:IsA("Light") then
									c.Enabled = on
								end
							end
						end
					end
					pr.ActionText = if on then "매물판 조명 끄기" else "매물판 조명 켜기"
				end })
			end
			local feat, featLab = listingBoard(K, d, w, top - 3.6, rng)
			if feat and featLab then
				local slides = {}
				for i = 1, #LISTINGS do
					local L = LISTINGS[(i * 7) % #LISTINGS + 1]
					table.insert(slides, L[1] .. "\n\n" .. L[2] .. "\n\n" .. L[3])
				end
				Interact.cycle(K, feat, slides, { action = "매물 넘기기", object = "오늘의 추천 매물", on = function(_i, s2)
					if featLab and featLab.Parent then
						featLab.Text = s2
					end
				end })
			end
		end
	end)
	-- 매물판 아래 낮은 수납장 (뒷벽 아랫부분이 비지 않게): 미닫이 문 · 위에 파일 · 달력 · 작은 화분
	step(K, "credenza", function()
		for _, cw in { 6.0, 4.6, 3.4, 2.4 } do
			local wn, pcf = wallFloorSpot(K, { "back" }, cw, 1.1, 2.75, V3((V.x0 + V.x1) / 2, 0, V.z0), 0.03, "credenza")
			if wn and pcf then
				local wood2 = lk(C(150, 112, 78), M.Wood)
				local bodyL = lk(C(236, 234, 228))
				K:box("CredBody", V3(cw, 2.3, 1.0), pcf * CF(0, 0.25 + 1.15, -0.05), bodyL)
				K:box("CredPlinth", V3(cw - 0.1, 0.25, 0.9), pcf * CF(0, 0.125, -0.08), Look.charcoal)
				K:box("CredTop", V3(cw + 0.06, 0.1, 1.1), pcf * CF(0, 2.6, 0), wood2)
				local nd = math.max(2, math.floor(cw / 1.2))
				local dw = cw / nd
				for i = 1, nd do
					local x = -cw / 2 + dw * (i - 0.5)
					local f = CFrame.fromMatrix((pcf * CF(x, 1.4, 0.46 + (i % 2) * 0.03)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector)
					K:plate("CredDoor", dw - 0.05, 2.1, 0.03, f, bodyL)
					K:plate("CredPull", 0.06, 0.6, 0.03, f * CF((if i % 2 == 0 then -1 else 1) * (dw / 2 - 0.18), 0.1, 0.02), Look.brushed)
				end
				-- 위 소품 (우리 수납장 위)
				local top = pcf * CF(0, 2.65, 0)
				local tx = -cw / 2 + 0.45
				for b = 0, 4 do
					K:box("CredBinder", V3(0.22, 0.95, 0.8), top * CF(tx + b * 0.24, 0.475, -0.05), lk(pickR(rng, { C(30, 60, 140), C(200, 40, 40), C(40, 40, 44), C(230, 180, 40) })))
				end
				K:box("CredBookend", V3(0.06, 0.6, 0.5), top * CF(tx + 5 * 0.24 - 0.08, 0.3, -0.05), Look.blackMetal)
				if cw >= 3.4 then
					-- 탁상 달력 + 명함꽂이 + 작은 화분
					-- 쐐기를 돌려 경사면이 손님 쪽(+Z)을 보게: 경사 중심 = 상자 중심
					local cal = top * CF(0.2, 0.3, 0.1)
					K:wedge("CredCalendar", V3(0.9, 0.6, 0.35), cal * ANG(0, PI, 0), lk(C(250, 250, 248)))
					txt(K, "CredCalText", 0.78, 0.5, cal * ANG(-math.atan(0.35 / 0.6), 0, 0) * CF(0, 0, 0.012), "10 OCT\n2026", C(200, 40, 40), C(250, 250, 248), { font = F.GothamBlack, d = 0.004 })
					K:box("CredCardHolder", V3(0.5, 0.3, 0.3), top * CF(0.95, 0.15, 0.15), Look.blackMetal)
					K:box("CredCards", V3(0.42, 0.04, 0.25), top * CF(0.95, 0.32, 0.15), Look.paper)
					Props.potPlant(K, top * CF(cw / 2 - 0.45, 0, 0), 0.55, 1.1, { kind = "succulent" })
				end
				break
			end
		end
	end)
	-- 수영구 지도
	step(K, "map", function()
		local w = math.min(5.2, V.W * 0.22)
		local wn, d = wallItemSpot(K, { "back", "left", "right" }, w + 0.3, 3.6, math.min(V.H - 0.6, 7.2), -V.W / 4)
		if wn and d then
			suyeongMap(K, d, w, math.min(V.H - 0.6, 7.2) - 3.9)
		end
	end)
	-- 법정 게시 증서 (등록증 · 자격증 · 사업자등록증 · 중개보수 요율표)
	step(K, "certs", function()
		local certs = {
			{ "중개사무소 등록증", "등록번호 26500-2019-00123\n상호 " .. name .. "\n대표 김O O\n수영구청장" },
			{ "공인중개사 자격증", "제 28회 공인중개사\n자격시험 합격\n한국산업인력공단" },
			{ "사업자등록증", "상호 " .. name .. "\n소재지 부산 수영구\n광안해변로\n수영세무서장" },
			{ "중개보수 요율표", "매매 5천만 미만 0.6%\n2억 미만 0.5% · 9억 미만 0.4%\n임대차 5천만 미만 0.5%\n1억 미만 0.4% · 3억 미만 0.3%" },
		}
		local cw, chh = 1.2, 1.6
		local total = #certs * (cw + 0.25)
		local wn, d = wallItemSpot(K, { "back", "left", "right" }, total, 4.3, 6.1, V.W / 4)
		if wn and d then
			for i, c in certs do
				cert(K, d * CF(-total / 2 + (i - 0.5) * (cw + 0.25), 0, 0), cw, chh, c[1], c[2])
			end
		else
			for _, c in certs do
				local wn2, d2 = wallItemSpot(K, { "back", "left", "right" }, cw + 0.2, 4.3, 6.1, 0)
				if wn2 and d2 then
					cert(K, d2, cw, chh, c[1], c[2])
				end
			end
		end
	end)
	-- 벽 TV (매물 슬라이드)
	local tvScr, tvLab = nil, nil
	step(K, "tv", function()
		local wn, d = wallItemSpot(K, { "left", "right", "back" }, 3.4, 4.0, 6.4, 0, function(dc: CFrame)
			return Interact.canPrompt(K, (dc * CF(0, 0, 0.3)).Position)
		end)
		if not wn then
			wn, d = wallItemSpot(K, { "left", "right", "back" }, 3.4, 4.0, 6.4, 0)
		end
		if wn and d then
			tvScr = Props.tv(K, d * CF(0, 0, 0), 3.2, { on = true, screen = C(16, 40, 80) })
			local _, lab = txt(K, "TvListing", 2.9, 1.6, d * CF(0, 0, 0.27), "오늘의 추천 매물\n민락 더샵 102㎡\n매매 13억 8,000", WHITE, nil, { font = F.GothamBold, glow = 1.2 })
			tvLab = lab
		end
	end)
	-- 바닥 소품: 정수기 · 복합기 · 책장 · 화분
	local paperOut = nil
	step(K, "floorprops", function()
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.9, 1.7, 3.2, V3(V.x1, 0, V.z0), 0.05, "mfp")
		if wn and pcf then
			paperOut = mfp(K, pcf)
		end
		local wn2, pcf2 = wallFloorSpot(K, { "left", "right", "back" }, 1.6, 1.3, 3.6, V3(V.x0, 0, V.z0), 0.05, "water")
		if wn2 and pcf2 then
			purifier(K, pcf2)
		end
		local wn3, pcf3 = wallFloorSpot(K, { "back", "left", "right" }, 2.6, 1.1, math.min(6.4, V.H - 1), V3(V.x0 + 3, 0, V.z0), 0.05, "cab")
		if wn3 and pcf3 then
			binderCabinet(K, pcf3, 2.6, math.min(6.4, V.H - 1), rng)
		end
		for _, p in { V3(V.x0 + 0.9, 0, V.z0 + 0.9), V3(V.x1 - 0.9, 0, V.z0 + 0.9), V3(V.x0 + 0.9, 0, V.z1 - 1.0) } do
			plantAt(K, pcfAt(p, V3(0, 0, 1)), pickR(rng, { "snake", "ficus", "monstera" }), math.min(5.0, V.H * 0.6), 1.2, lk(C(236, 234, 228), M.Concrete))
		end
	end)
	-- 영업시간 · 달력 · 상호 간판(안쪽)
	step(K, "signs", function()
		local wn, d = wallItemSpot(K, { "left", "right", "back" }, 1.6, 3.8, 5.8, 0)
		if wn and d then
			paper(K, d, 1.4, 1.9, "영업시간", "평일 09:00 - 19:00\n토요일 10:00 - 17:00\n일요일 · 공휴일 예약 상담\n\n☎ 051-753-0000", { band = C(24, 50, 100), pin = false })
		end
		local wn2, d2 = wallItemSpot(K, { "left", "right", "back" }, 1.4, 3.6, 5.6, 2)
		if wn2 and d2 then
			K:plate("Calendar", 1.3, 1.8, 0.02, d2, Look.paper)
			K:plate("CalendarTop", 1.3, 0.5, 0.025, d2 * CF(0, 0.65, 0), lk(C(200, 40, 40)))
			txt(K, "CalendarText", 1.2, 0.4, d2 * CF(0, 0.65, 0.03), "2026  10월", WHITE, nil, { font = F.GothamBlack })
			txt(K, "CalendarDays", 1.2, 1.15, d2 * CF(0, -0.22, 0.025), "일 월 화 수 목 금 토\n         1  2  3\n4  5  6  7  8  9 10\n11 12 13 14 15 16 17\n18 19 20 21 22 23 24\n25 26 27 28 29 30 31", C(50, 50, 54), nil, { font = F.Gotham })
		end
		local w = math.min(6, V.W * 0.25)
		local wn3, d3 = wallItemSpot(K, { "back" }, w, math.min(V.H - 1.4, 7.4), math.min(V.H - 0.3, 8.6), 0)
		if wn3 and d3 then
			K:plate("RealtyNameBack", w + 0.4, 0.95, 0.06, d3, lk(C(24, 50, 100)))
			txt(K, "RealtyName", w, 0.62, d3 * CF(0, 0.03, 0.07), name, WHITE, nil, { font = F.GothamBlack })
		end
	end)
	-- 유리창 매물 전단 (밖에서 읽히게 바깥쪽을 향함, 창 keep 3.4 아래 · 문 keep 밖 · 멀리언 피함)
	step(K, "windowsheets", function()
		local d = V.door
		local wins = V.byName.ShopWindow or {}
		local mulls = V.byName.Mullion or {}
		local sw, sh = 1.12, 1.42
		local zf = V.z1 - 0.07
		local idx = math.floor(rng() * #LISTINGS)
		local topN = 0
		local function onGlass(x: number): boolean
			if #wins == 0 then
				return true
			end
			for _, r in wins do
				if x - sw / 2 >= r.min.X + 0.05 and x + sw / 2 <= r.max.X - 0.05 and r.max.Z > V.z1 - 0.3 then
					return true
				end
			end
			return false
		end
		local function nearMullion(x: number): boolean
			for _, r in mulls do
				if r.max.Z > V.z1 - 0.4 and x + sw / 2 > r.min.X - 0.06 and x - sw / 2 < r.max.X + 0.06 then
					return true
				end
			end
			return false
		end
		K:free(function()
			for _, side in { -1, 1 } do
				local inner = if d then (if side > 0 then d.x + (d.w or 4.8) / 2 + 2.1 else d.x - (d.w or 4.8) / 2 - 2.1) else 0
				local outer = if side > 0 then V.x1 - 0.4 else V.x0 + 0.4
				local a, b = math.min(inner, outer), math.max(inner, outer)
				local n = math.floor((b - a) / (sw + 0.1))
				for i = 1, n do
					local x = a + (i - 0.5) * ((b - a) / n)
					if onGlass(x) and not nearMullion(x) then
						for row, y in { 1.08, 2.6 } do
							idx += 1
							local L = LISTINGS[idx % #LISTINGS + 1]
							local out = CFrame.fromMatrix(V3(x, y, zf), V3(1, 0, 0), Vector3.yAxis, V3(0, 0, 1))
							K:plate("WinSheet", sw, sh, 0.02, out * CF(0, 0, -0.012), Look.paper)
							K:plate("WinSheetBand", sw, 0.3, 0.012, out * CF(0, sh / 2 - 0.15, 0.002), lk(DEAL_COL[L[1]] or C(60, 60, 64)))
							if row == 2 then
								topN += 1
							end
							if row == 2 and topN % 2 == 1 and topN <= 7 then
								-- 위 줄: 매물 글자 (글자판은 한 장에 하나 — 글자판 수를 아낌)
								txt(K, "WinSheetText", sw - 0.1, sh - 0.4, out * CF(0, -0.17, 0), L[1] .. "\n" .. L[2] .. "\n" .. L[3], C(24, 30, 48), nil, { font = F.GothamBold, d = 0.012 })
							else
								-- 아래 줄: 평면도 (선 판)
								local ink = lk(C(90, 96, 110))
								K:plate("WinPlan", sw * 0.7, 0.03, 0.01, out * CF(0, 0.25, 0.004), ink)
								K:plate("WinPlan", sw * 0.7, 0.03, 0.01, out * CF(0, -0.55, 0.004), ink)
								K:plate("WinPlan", 0.03, 0.8, 0.01, out * CF(-sw * 0.35, -0.15, 0.004), ink)
								K:plate("WinPlan", 0.03, 0.8, 0.01, out * CF(sw * 0.35, -0.15, 0.004), ink)
								K:plate("WinPlan", 0.03, 0.45, 0.01, out * CF(0.05, 0.03, 0.004), ink)
								K:plate("WinPlan", sw * 0.36, 0.03, 0.01, out * CF(-0.12, -0.2, 0.004), ink)
							end
						end
					end
				end
			end
		end)
	end)
	step(K, "extras", function()
		-- 매물 사진 (3장)
		local caps = { "광안 자이 84㎡", "민락 더샵 오션뷰", "남천 코오롱 59㎡" }
		for n2 = 3, 1, -1 do
			local wn, d = wallItemSpot(K, { "back", "left", "right" }, n2 * 1.45, 3.9, 5.7, -V.W / 3)
			if wn and d then
				for i2 = 1, n2 do
					buildingPhoto(K, d * CF((i2 - (n2 + 1) / 2) * 1.45, 0.15, 0), 1.25, 1.3, rng, caps[i2])
				end
				break
			end
		end
		-- 벽걸이 에어컨
		local wn2, d2 = wallItemSpot(K, { "left", "right", "back" }, 3.1, math.min(V.H - 1.6, 6.4), math.min(V.H - 0.4, 7.6), 0)
		if wn2 and d2 then
			wallAC(K, d2 * CF(0, 0.05, 0))
		end
		-- 큰 지역 사진 (천장이 높은 매장)
		if V.H > 9.5 then
			local wn3, d3 = wallItemSpot(K, { "left", "right", "back" }, 6.4, 7.6, math.min(V.H - 0.5, 10.2), 0)
			if wn3 and d3 then
				bridgeArt(K, d3, 6.0, math.min(2.6, V.H - 8.3), Look.walnut)
			end
		end
		-- 화분 (모서리 · 입구 옆)
		local planted = 0
		for _, p in { V3(V.x0 + 0.9, 0, V.z0 + 0.9), V3(V.x1 - 0.9, 0, V.z0 + 0.9), V3(V.x0 + 0.9, 0, V.z1 - 1.0), V3(V.x1 - 0.9, 0, V.z1 - 1.0), V3(V.x0 + 2.0, 0, V.z0 + 0.9), V3(V.x1 - 2.0, 0, V.z0 + 0.9) } do
			if planted < 2 and plantAt(K, pcfAt(p, V3(0, 0, 1)), pickR(rng, { "snake", "ficus", "bamboo" }), math.min(4.6, V.H * 0.55), 1.0, lk(C(236, 234, 228), M.Concrete)) then
				planted += 1
			end
		end
		-- 좁은 매장: 뒷벽 앞 얕은 자리에 작은 산세베리아
		local cxx = (V.x0 + V.x1) / 2
		for _, dx in { 3.4, -3.4, 4.2, -4.2 } do
			if planted < 2 and plantAt(K, pcfAt(V3(cxx + dx, 0, V.z0 + 0.6), V3(0, 0, 1)), "snake", 2.8, 0.7, lk(C(236, 234, 228), M.Concrete)) then
				planted += 1
			end
		end
		-- 분양 브로슈어 꽂이 (벽)
		local wn4, d4 = wallItemSpot(K, { "left", "right", "back" }, 1.4, 2.0, 4.0, 0)
		if wn4 and d4 then
			K:plate("BrochureWallBack", 1.3, 1.9, 0.05, d4, lk(C(220, 224, 228), M.Glass, { t = 0.2 }))
			local cols = { C(30, 60, 140), C(200, 40, 50), C(30, 140, 100), C(240, 180, 40) }
			for r2 = 0, 1 do
				for c2 = 0, 1 do
					local bdc = d4 * CF(-0.32 + c2 * 0.64, 0.45 - r2 * 0.9, 0.06) * ANG(-0.12, 0, 0)
					K:plate("Brochure", 0.56, 0.75, 0.04, bdc, lk(cols[r2 * 2 + c2 + 1]))
					if not lo(K) then
						txt(K, "BrochureText", 0.5, 0.3, bdc * CF(0, 0.15, 0.045), pickR(rng, { "분양\n안내", "신축\n오피스텔", "재건축\n소식", "청약\n가이드" }), WHITE, nil, { font = F.GothamBlack, d = 0.004 })
					end
				end
			end
		end
	end)
	step(K, "interact", function()
		if tvScr and tvLab then
			local slides = {}
			for i = 1, 6 do
				local L = LISTINGS[(i * 4) % #LISTINGS + 1]
				table.insert(slides, "오늘의 추천 매물  " .. i .. "/6\n" .. string.gsub(L[2], "\n", " · ") .. "\n" .. L[1] .. "  " .. L[3])
			end
			local pr = Interact.cycle(K, tvScr, slides, { action = "화면 넘기기", object = "매물 안내 TV", on = function(_i, s)
				if tvLab and tvLab.Parent then
					tvLab.Text = s
				end
			end })
			if not pr then
				local frames = {}
				for _, sl in slides do
					table.insert(frames, { text = sl })
				end
				Interact.screenLoop(K, nil, tvLab, frames, 6)
			end
		end
		if paperOut then
			local base = paperOut.CFrame
			local busy = false
			Interact.prompt(K, paperOut, { action = "출력하기", object = "복합기 (매물 안내문)", fn = function()
				if busy then
					return
				end
				busy = true
				local t0 = os.clock()
				task.spawn(function()
					while os.clock() - t0 < 1.6 do
						local k = math.clamp((os.clock() - t0) / 1.4, 0, 1)
						if paperOut.Parent then
							paperOut.CFrame = base * CF(0, 0.02 * k, 0.55 * k)
						end
						task.wait()
					end
					task.wait(1.5)
					if paperOut.Parent then
						paperOut.CFrame = base
					end
					busy = false
				end)
			end })
		end
	end)
	step(K, "fixtures", function()
		fixturesSorted(K, V, S)
	end)
	step(K, "switch", function()
		ensureSwitch(K, V)
	end)
	_ = desks
	step(K, "posters", function()
		fillPosters(K, POSTERS.realty, 2)
	end)
end

---------------------------------------------------------------------------------------------------
-- 9. 세탁소
---------------------------------------------------------------------------------------------------

local GARMENTS = {
	{ kind = "shirt", len = 2.4, w = 1.2, t = 0.2, cols = { C(250, 250, 250), C(214, 230, 246), C(246, 246, 240) } },
	{ kind = "shirt", len = 2.4, w = 1.2, t = 0.2, cols = { C(246, 246, 244), C(200, 220, 240), C(236, 230, 214), C(220, 200, 214) } },
	{ kind = "suit", len = 2.6, w = 1.3, t = 0.26, cols = { C(36, 40, 56), C(60, 62, 66), C(30, 30, 32), C(80, 70, 60) } },
	{ kind = "coat", len = 3.3, w = 1.35, t = 0.3, cols = { C(190, 160, 120), C(120, 90, 70), C(70, 74, 80), C(150, 40, 40) } },
	{ kind = "padding", len = 2.6, w = 1.4, t = 0.42, cols = { C(24, 24, 26), C(40, 50, 80), C(220, 220, 214) } },
	{ kind = "dress", len = 3.0, w = 1.1, t = 0.2, cols = { C(160, 40, 60), C(40, 40, 44), C(230, 210, 200), C(60, 90, 70) } },
}

-- 비닐 씌운 옷 한 벌 (frame: 원점 = 레일 걸이 점, X = 어깨 방향, Y 위, Z = 얇은 쪽). 반환: 파트 목록
local function garment(K: any, frame: CFrame, g: any, col: Color3, tag: boolean): { BasePart }
	local out = {}
	local function add(p: BasePart?)
		if p then
			table.insert(out, p)
		end
	end
	local w, t, len = g.w, g.t, g.len
	local fab = lk(col, if g.kind == "shirt" then M.SmoothPlastic elseif g.kind == "padding" then M.Fabric else M.Fabric)
	-- 철사 옷걸이 고리 + 종이 어깨 커버 (세탁소 옷걸이)
	add(K:seg("GarmentHook", (frame * CF(0, 0.02, 0)).Position, (frame * CF(0, -0.3, 0)).Position, 0.035, Look.chrome))
	for _, sx in { -1, 1 } do
		add(K:box("GarmentShoulder", V3(w / 2 + 0.06, 0.09, t + 0.05), frame * CF(sx * w / 4, -0.44, 0) * ANG(0, 0, sx * -0.3), Look.paper))
	end
	-- 몸판: 위 (어깨 폭) + 아래 (코트 · 원피스는 살짝 넓게)
	local upper = len * 0.45
	add(K:box("GarmentBody", V3(w, upper, t), frame * CF(0, -0.52 - upper / 2, 0), fab))
	local flare = if g.kind == "dress" or g.kind == "coat" then 1.1 elseif g.kind == "padding" then 0.96 else 0.98
	add(K:box("GarmentBody", V3(w * flare, len - upper, t * 0.92), frame * CF(0, -0.52 - upper - (len - upper) / 2, 0), fab))
	-- 소매 (몸판 옆으로 늘어진 팔) · 깃
	if not lo(K) and g.kind ~= "dress" then
		for _, sx in { -1, 1 } do
			add(K:box("GarmentSleeve", V3(0.2, len * 0.62, t * 0.8), frame * CF(sx * (w / 2 + 0.07), -0.6 - len * 0.31, 0) * ANG(0, 0, sx * 0.05), lk(darker(col, 0.06), fab.m)))
		end
	end
	if g.kind == "shirt" or g.kind == "suit" then
		add(K:box("GarmentCollar", V3(w * 0.34, 0.16, t + 0.03), frame * CF(0, -0.56, 0), lk(if g.kind == "suit" then C(240, 240, 244) else lighter(col, 0.1))))
	end
	-- 비닐 커버: 몸통 + 어깨 지붕 (쐐기 둘) — 고리 쪽으로 좁아짐
	local pl = { c = C(232, 240, 246), m = M.Glass, t = 0.84, r = 0.25 }
	add(K:box("GarmentPlastic", V3(w + 0.16, len + 0.25, t + 0.1), frame * CF(0, -0.58 - len / 2, 0), pl))
	if not lo(K) then
		for _, sx in { -1, 1 } do
			add(K:wedge("GarmentPlasticTop", V3(t + 0.1, 0.32, w / 2 + 0.08), frame * CF(sx * (w / 4 + 0.04), -0.3, 0) * ANG(0, sx * -PI / 2, 0), pl))
		end
	end
	if tag then
		-- 세탁 번호표: 고리 목에 스테이플
		local tc = pickR(mkRng(col.R * 1000 + len), { C(250, 220, 60), C(250, 150, 170), C(140, 220, 160), C(250, 250, 250) })
		add(K:box("GarmentTag", V3(0.03, 0.3, 0.2), frame * CF(0, -0.42, t / 2 + 0.1) * ANG(0, 0, 0.12), lk(tc)))
	end
	return out
end

-- 회전 컨베이어 행거 (천장 레일 타원). xa..xb, zc 중심, R 반지름, railY. 반환: 상태 (garments, frameAt, run)
local function conveyor(K: any, V: any, xa: number, xb: number, zc: number, R: number, railY: number, rng: () -> number): any
	local L = xb - xa
	local P = 2 * L + 2 * PI * R
	local function at(s: number): (Vector3, Vector3)
		s = s % P
		if s < L then
			return V3(xa + s, railY, zc - R), V3(1, 0, 0)
		end
		s -= L
		if s < PI * R then
			local a = -PI / 2 + s / R
			return V3(xb + math.cos(a) * R, railY, zc + math.sin(a) * R), V3(-math.sin(a), 0, math.cos(a))
		end
		s -= PI * R
		if s < L then
			return V3(xb - s, railY, zc + R), V3(-1, 0, 0)
		end
		s -= L
		local a = PI / 2 + s / R
		return V3(xa + math.cos(a) * R, railY, zc + math.sin(a) * R), V3(-math.sin(a), 0, math.cos(a))
	end
	local function frameAt(s: number): CFrame
		local p, t = at(s)
		local n = Vector3.yAxis:Cross(t)
		return CFrame.fromMatrix(p, n, Vector3.yAxis, t)
	end
	local rail = lk(C(70, 74, 80), M.Metal)
	K:free(function()
		-- 레일 (곧은 2 + 반원 2)
		K:bar("ConveyorRail", V3(xa, railY + 0.08, zc - R), V3(xb, railY + 0.08, zc - R), 0.14, 0.16, rail)
		K:bar("ConveyorRail", V3(xa, railY + 0.08, zc + R), V3(xb, railY + 0.08, zc + R), 0.14, 0.16, rail)
		K:ring("ConveyorRail", CF(xb, railY + 0.08, zc) * ANG(PI / 2, 0, 0), R, 0.15, 8, rail, -PI / 2, PI / 2)
		K:ring("ConveyorRail", CF(xa, railY + 0.08, zc) * ANG(PI / 2, 0, 0), R, 0.15, 8, rail, PI / 2, PI * 1.5)
		-- 천장 매달기 봉
		for _, x in { xa, (xa + xb) / 2, xb } do
			K:seg("ConveyorHanger", V3(x, V.H - 0.02, zc), V3(x, railY + 0.16, zc), 0.08, rail)
			K:bar("ConveyorCross", V3(x, railY + 0.18, zc - R), V3(x, railY + 0.18, zc + R), 0.1, 0.1, rail)
		end
		-- 구동 모터
		K:box("ConveyorMotor", V3(0.9, 0.7, 0.9), CF(xb + R * 0.2, railY + 0.55, zc), lk(C(40, 90, 150), M.Metal))
		K:vcyl("ConveyorSprocket", 0.12, 1.2, CF(xb, railY + 0.22, zc), rail)
	end)
	local gl = {}
	local step0 = if lo(K) then 0.62 else 0.42
	local n = math.floor(P / step0)
	for i = 0, n - 1 do
		local s0 = i * P / n + (rng() - 0.5) * 0.05
		local g = GARMENTS[math.floor(rng() * #GARMENTS) + 1]
		local col = g.cols[math.floor(rng() * #g.cols) + 1]
		local f = frameAt(s0)
		local parts = {}
		K:free(function()
			parts = garment(K, f, g, col, not lo(K) and (i % 2 == 0))
		end)
		local wf = K.cf * f
		local rel = {}
		for _, p in parts do
			table.insert(rel, { p = p, rel = wf:ToObjectSpace(p.CFrame) })
		end
		table.insert(gl, { s0 = s0, parts = rel })
	end
	local st = { garments = gl, frameAt = frameAt, offset = 0, until_ = 0, P = P }
	Interact.anim(K, function(t, dt)
		if t > st.until_ then
			return
		end
		st.offset += (dt or 0.1) * 0.9
		for _, g in st.garments do
			local wf = K.cf * frameAt(g.s0 + st.offset)
			for _, r in g.parts do
				if r.p.Parent then
					r.p.CFrame = wf * r.rel
				end
			end
		end
	end)
	st.clock = 0
	Interact.anim(K, function(t)
		st.clock = t
	end)
	return st
end

-- 다림질대 + 스팀다리미 + 보일러. pcf 바닥 가운데, +Z = 일하는 사람 쪽, w 길이, dep 깊이. 반환: 스팀 파트들 · 다리미
local function pressStation(K: any, V: any, pcf: CFrame, w: number, dep: number): ({ BasePart }, BasePart?)
	local steel = Look.steel
	local h = 2.95
	local lz = dep / 2 - 0.15
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:box("PressLeg", V3(0.12, h - 0.3, 0.12), pcf * CF(sx * (w / 2 - 0.2), (h - 0.3) / 2, sz * lz), steel)
		end
	end
	K:box("PressShelf", V3(w - 0.3, 0.06, dep - 0.2), pcf * CF(0, 0.6, 0), steel)
	K:box("PressVacuum", V3(1.2, 1.0, dep - 0.3), pcf * CF(w / 2 - 0.9, 1.15, 0), lk(C(70, 110, 160), M.Metal))
	txt(K, "PressVacuumLabel", 0.8, 0.22, CFrame.fromMatrix((pcf * CF(w / 2 - 0.9, 1.3, dep / 2 - 0.14)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector), "VACUUM", WHITE, nil, { font = F.GothamBold })
	K:box("PressFrame", V3(w, 0.16, dep), pcf * CF(0, h - 0.38, 0), steel)
	K:rbox("PressBoard", V3(w - 0.1, 0.24, dep - 0.04), 0.1, pcf * CF(0, h - 0.18, 0), lk(C(196, 200, 204), M.Fabric))
	K:box("PressCover", V3(w - 0.4, 0.02, dep - 0.2), pcf * CF(0, h - 0.05, 0), lk(C(170, 180, 196), M.Fabric))
	-- 소매 다림판 (끝)
	K:ell("PressBuck", V3(1.3, 0.3, 0.5), pcf * CF(w / 2 - 0.75, h + 0.15, -dep / 2 + 0.3), lk(C(196, 200, 204), M.Fabric))
	-- 다리미 받침 + 다리미 (앞쪽)
	local ix, iz = -w / 2 + 1.1, dep / 2 - 0.42
	K:box("IronRest", V3(0.7, 0.04, 0.45), pcf * CF(ix, h - 0.03, iz), lk(C(40, 40, 44), M.Rubber))
	local iron = K:box("SteamIron", V3(0.42, 0.24, 0.6), pcf * CF(ix, h + 0.1, iz - 0.05), lk(C(220, 222, 226), M.Metal))
	K:wedge("SteamIronNose", V3(0.42, 0.24, 0.24), pcf * CF(ix, h + 0.1, iz - 0.47), lk(C(220, 222, 226), M.Metal))
	K:box("SteamIronHandle", V3(0.14, 0.12, 0.5), pcf * CF(ix, h + 0.38, iz - 0.02), Look.black)
	K:box("SteamIronPost", V3(0.1, 0.18, 0.08), pcf * CF(ix, h + 0.27, iz + 0.2), Look.black)
	-- 천장 스프링 밸런서 + 코드
	local topY = V.H - 0.05
	K:box("PressBalancer", V3(0.4, 0.4, 0.4), pcf * CF(ix, topY - 0.25, iz), lk(C(70, 74, 80), M.Metal))
	K:seg("PressBalancerRod", (pcf * CF(ix, topY, iz)).Position, (pcf * CF(ix, topY - 0.1, iz)).Position, 0.06, steel)
	local springTop = topY - 0.5
	if not lo(K) then
		for i = 0, 4 do
			K:ring("PressSpring", pcf * CF(ix, springTop - i * 0.14, iz) * ANG(PI / 2, 0, 0), 0.09, 0.03, 6, Look.chrome)
		end
	end
	-- 스프링에서 내려오는 코드 + 흰 스팀 호스 (가운데서 살짝 휨)
	local hoseL = lk(C(232, 232, 228), M.Rubber)
	local hA = (pcf * CF(ix, springTop - 0.7, iz)).Position
	local hM = (pcf * CF(ix + 0.12, (springTop - 0.7 + h + 0.45) / 2, iz + 0.22)).Position
	local hB = (pcf * CF(ix, h + 0.42, iz + 0.2)).Position
	-- 스팀 호스: 보일러 쪽으로 크게 늘어진 곡선 (2차 베지어 6마디)
	local hC = (pcf * CF(ix + 0.75, (springTop + h) / 2 - 0.2, iz + 0.45)).Position
	local prev = hA
	local nSeg = if lo(K) then 3 else 6
	for i = 1, nSeg do
		local t = i / nSeg
		local q = hA * (1 - t) * (1 - t) + hC * 2 * t * (1 - t) + hB * t * t
		K:seg("PressHose", prev, q, 0.065, hoseL)
		prev = q
	end
	K:seg("PressCord", hA + V3(0.05, 0, 0), hM + V3(0.05, 0, -0.04), 0.035, Look.charcoal)
	K:seg("PressCord", hM + V3(0.05, 0, -0.04), (pcf * CF(ix + 0.04, h + 0.45, iz + 0.1)).Position, 0.035, Look.charcoal)
	-- 옆 보일러
	local bx = pcf * CF(w / 2 + 0.6, 0, 0)
	local bd = math.min(1.0, dep - 0.05)
	K:vcyl("BoilerTank", 2.2, bd, bx * CF(0, 1.25, 0), lk(C(214, 216, 218), M.Metal))
	K:ell("BoilerDome", V3(bd, 0.4, bd), bx * CF(0, 2.35, 0), lk(C(214, 216, 218), M.Metal))
	K:box("BoilerBase", V3(bd + 0.1, 0.14, bd + 0.1), bx * CF(0, 0.07, 0), Look.charcoal)
	K:disc("BoilerGauge", 0.36, 0.06, bx * CF(0, 1.9, bd / 2 + 0.02) * ANG(PI / 2, 0, 0), Look.white)
	K:disc("BoilerGaugeRim", 0.4, 0.05, bx * CF(0, 1.9, bd / 2) * ANG(PI / 2, 0, 0), Look.chrome)
	K:plate("BoilerNeedle", 0.02, 0.14, 0.01, CFrame.fromMatrix((bx * CF(0, 1.93, bd / 2 + 0.06)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector) * ANG(0, 0, -0.6), Look.ledRed)
	K:seg("BoilerPipe", (bx * CF(-0.3, 2.3, 0)).Position, (pcf * CF(w / 2 - 0.3, h - 0.4, -dep / 2 + 0.2)).Position, 0.08, Look.brass)
	txt(K, "BoilerLabel", 0.7, 0.3, CFrame.fromMatrix((bx * CF(0, 1.2, bd / 2 + 0.005)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector), "스팀 보일러", C(40, 40, 44), C(250, 220, 60), { font = F.GothamBold, d = 0.01 })
	-- 다림질 중인 셔츠
	K:box("PressShirt", V3(1.6, 0.04, dep - 0.4), pcf * CF(0.4, h - 0.02, 0) * ANG(0, 0.08, 0), lk(C(236, 240, 248)))
	K:box("PressShirtSleeve", V3(0.9, 0.035, 0.3), pcf * CF(-0.45, h - 0.02, dep / 2 - 0.3) * ANG(0, 0.3, 0), lk(C(236, 240, 248)))
	-- 스팀 (숨김 상태로 만들고 상호작용 때 보임)
	local steam = {}
	for i = 1, 3 do
		local p = K:ell("SteamPuff", V3(0.4 + i * 0.12, 0.35 + i * 0.1, 0.4 + i * 0.1), pcf * CF(ix + (i - 2) * 0.12, h + 0.25 + i * 0.3, iz - 0.35), { c = C(250, 250, 252), m = M.SmoothPlastic, t = 1 })
		table.insert(steam, p)
	end
	return steam, iron
end

-- 바퀴 달린 옷 행거 (양쪽 기둥 + 위 봉, 옷은 봉과 직각). pcf 정면 +Z, len 길이 (X)
local function garmentRack(K: any, pcf: CFrame, len: number, railY: number, rng: () -> number, tagged: boolean)
	for _, sx in { -1, 1 } do
		local x = sx * (len / 2 - 0.1)
		K:box("RackFoot", V3(0.12, 0.12, 1.3), pcf * CF(x, 0.2, 0), Look.chrome)
		for _, sz in { -1, 1 } do
			K:ball("RackCaster", 0.22, pcf * CF(x, 0.11, sz * 0.55), Look.black)
		end
		K:seg("RackPost", (pcf * CF(x, 0.25, 0)).Position, (pcf * CF(x, railY + 0.1, 0)).Position, 0.1, Look.chrome)
	end
	K:seg("RackRail", (pcf * CF(-len / 2 + 0.1, railY, 0)).Position, (pcf * CF(len / 2 - 0.1, railY, 0)).Position, 0.09, Look.chrome)
	local n = math.floor((len - 0.4) / (if lo(K) then 0.55 else 0.36))
	for i = 1, n do
		local g = GARMENTS[math.floor(rng() * #GARMENTS) + 1]
		local col = g.cols[math.floor(rng() * #g.cols) + 1]
		local x = -len / 2 + 0.2 + (i - 0.5) * ((len - 0.4) / n)
		local gg = { kind = g.kind, len = math.min(g.len, railY - 2.4), w = 1.2, t = g.t }
		garment(K, pcf * CF(x, railY, 0) * ANG(0, PI / 2, 0), gg, col, tagged and i % 2 == 0)
	end
end

-- 수선 코너: 미싱 테이블 + 실 걸이 + 스탠드
local function sewingCorner(K: any, pcf: CFrame, rng: () -> number)
	local w = 2.8
	local top = 2.55
	K:box("SewTop", V3(w, 0.12, 1.4), pcf * CF(0, top - 0.06, 0), lk(C(220, 196, 150), M.Wood))
	for _, sx in { -1, 1 } do
		K:box("SewLeg", V3(0.12, top - 0.12, 1.2), pcf * CF(sx * (w / 2 - 0.12), (top - 0.12) / 2, 0), Look.blackMetal)
	end
	K:box("SewTreadle", V3(1.0, 0.08, 0.5), pcf * CF(0, 0.2, 0.25), Look.blackMetal)
	K:box("SewMotor", V3(0.5, 0.5, 0.5), pcf * CF(0.6, top - 0.45, -0.2), Look.charcoal)
	-- 미싱 (공업용)
	local m = pcf * CF(-0.2, top, -0.05)
	local body = lk(C(236, 234, 226))
	K:box("SewBed", V3(1.6, 0.18, 0.7), m * CF(0, 0.09, 0), body)
	K:box("SewColumn", V3(0.35, 0.95, 0.5), m * CF(0.6, 0.65, -0.05), body)
	K:box("SewArm", V3(1.5, 0.32, 0.45), m * CF(0.05, 1.1, -0.05), body)
	K:box("SewHead", V3(0.32, 0.55, 0.45), m * CF(-0.65, 0.85, -0.05), body)
	K:seg("SewNeedle", (m * CF(-0.68, 0.58, 0.05)).Position, (m * CF(-0.68, 0.22, 0.05)).Position, 0.02, Look.chrome)
	K:cyl("SewWheel", 0.12, 0.55, m * CF(0.85, 1.05, -0.05), Look.charcoal)
	K:vcyl("SewSpool", 0.3, 0.16, m * CF(0.3, 1.42, -0.1), lk(pickR(rng, { C(200, 40, 40), C(30, 60, 140), C(250, 250, 250) })))
	txt(K, "SewBrand", 0.6, 0.14, CFrame.fromMatrix((m * CF(0.05, 1.1, 0.18)).Position, pcf.XVector, Vector3.yAxis, pcf.ZVector), "JUKI", C(200, 40, 40), nil, { font = F.GothamBlack })
	-- 스탠드 (구즈넥)
	K:disc("SewLampBase", 0.4, 0.06, pcf * CF(w / 2 - 0.35, top + 0.03, -0.4), Look.black)
	K:seg("SewLampNeck", (pcf * CF(w / 2 - 0.35, top + 0.05, -0.4)).Position, (pcf * CF(w / 2 - 0.55, top + 1.2, -0.1)).Position, 0.05, Look.black)
	K:seg("SewLampNeck", (pcf * CF(w / 2 - 0.55, top + 1.2, -0.1)).Position, (pcf * CF(-0.2, top + 1.3, 0.1)).Position, 0.05, Look.black)
	local lamp = K:vcyl("SewLampHead", 0.2, 0.35, pcf * CF(-0.25, top + 1.2, 0.1), Look.black)
	local bulb = K:disc("SewLampLED", 0.28, 0.02, pcf * CF(-0.25, top + 1.09, 0.1), Look.lampNeutral)
	-- 소품: 바늘꽂이 · 가위 · 줄자 · 천
	K:ball("PinCushion", 0.3, pcf * CF(-w / 2 + 0.35, top + 0.12, 0.3), lk(C(200, 40, 50), M.Fabric))
	K:box("Scissors", V3(0.5, 0.03, 0.08), pcf * CF(-w / 2 + 0.6, top + 0.02, 0.5) * ANG(0, 0.4, 0), Look.chrome)
	K:box("Scissors", V3(0.5, 0.03, 0.08), pcf * CF(-w / 2 + 0.6, top + 0.035, 0.5) * ANG(0, 0.1, 0), Look.chrome)
	K:ring("TapeMeasure", pcf * CF(0.9, top + 0.02, 0.45) * ANG(PI / 2, 0, 0), 0.18, 0.05, 8, lk(C(240, 200, 40)))
	K:box("FabricPiece", V3(1.0, 0.03, 0.6), pcf * CF(-0.9, top + 0.02, 0.35) * ANG(0, -0.2, 0), lk(C(40, 50, 80), M.Fabric))
	return lamp, bulb
end

-- 수선용 마네킹 (드레스 폼: 삼발이 받침 + 봉 + 몸통 + 줄자). pcf 바닥 가운데, +Z 앞
local function dressForm(K: any, pcf: CFrame, col: Color3)
	for i = 0, 2 do
		local a = i * 2 * PI / 3
		K:box("FormFoot", V3(0.12, 0.1, 0.62), pcf * ANG(0, a, 0) * CF(0, 0.1, 0.3), Look.walnut)
		K:ball("FormCaster", 0.14, pcf * ANG(0, a, 0) * CF(0, 0.07, 0.56), Look.black)
	end
	K:vcyl("FormPole", 2.45, 0.1, pcf * CF(0, 1.3, 0), Look.chrome)
	K:vcyl("FormCollar", 0.16, 0.18, pcf * CF(0, 1.9, 0), Look.chrome)
	local fab = lk(col, M.Fabric)
	K:ell("FormHips", V3(1.12, 0.85, 0.72), pcf * CF(0, 2.85, 0), fab)
	K:ell("FormWaist", V3(0.88, 1.0, 0.6), pcf * CF(0, 3.4, 0), fab)
	K:ell("FormChest", V3(1.22, 1.35, 0.74), pcf * CF(0, 4.1, 0.02), fab)
	K:ell("FormShoulders", V3(1.32, 0.5, 0.62), pcf * CF(0, 4.62, -0.02), fab)
	K:vcyl("FormNeck", 0.36, 0.34, pcf * CF(0, 4.98, -0.02), fab)
	K:vcyl("FormNeckCap", 0.06, 0.38, pcf * CF(0, 5.18, -0.02), Look.walnut)
	K:ball("FormKnob", 0.14, pcf * CF(0, 5.26, -0.02), Look.walnut)
	-- 목에 건 줄자 (양쪽으로 늘어짐)
	local tape = lk(C(240, 200, 40))
	for _, sx in { -1, 1 } do
		K:seg("FormTape", (pcf * CF(sx * 0.2, 4.9, 0.2)).Position, (pcf * CF(sx * 0.32, 3.75, 0.42)).Position, 0.05, tape)
	end
end

-- 실 걸이 (벽 판 + 실패). dcf 벽
local function threadRack(K: any, dcf: CFrame, w: number, h: number, rng: () -> number)
	K:plate("ThreadBoard", w, h, 0.06, dcf, lk(C(220, 196, 150), M.Wood))
	local cols = math.floor(w / 0.32)
	local rows = math.floor(h / 0.45)
	for r = 1, rows do
		for c = 1, cols do
			if hi(K) or (r + c) % 2 == 0 then
				local x = -w / 2 + (c - 0.5) * (w / cols)
				local y = -h / 2 + (r - 0.5) * (h / rows)
				local col = Color3.fromHSV(rng(), 0.55 + rng() * 0.4, 0.5 + rng() * 0.5)
				K:vcyl("ThreadSpool", 0.32, 0.2, dcf * CF(x, y, 0.2), lk(col, M.Fabric))
			end
		end
	end
end

-- 찾아가실 옷 (벽 레일, 벽과 나란히). dcf = 벽 (레일 높이), w 폭
local function pickupRail(K: any, dcf: CFrame, w: number, rng: () -> number)
	K:bar("PickupRail", (dcf * CF(-w / 2, 0, 0.35)).Position, (dcf * CF(w / 2, 0, 0.35)).Position, 0.08, 0.08, Look.chrome)
	for _, sx in { -1, 1 } do
		K:plate("PickupBracket", 0.1, 0.3, 0.38, dcf * CF(sx * (w / 2 - 0.1), 0.05, 0), Look.chrome)
	end
	local n = math.floor(w / 0.42)
	for i = 1, n do
		local g = GARMENTS[math.floor(rng() * #GARMENTS) + 1]
		local col = g.cols[math.floor(rng() * #g.cols) + 1]
		local x = -w / 2 + (i - 0.5) * (w / n)
		-- 벽과 나란히 (어깨 = 벽 방향 X) 대신 겹쳐 보이게 약간 비스듬히
		local f = dcf * CF(x, 0, 0.35) * ANG(0, PI / 2 - 0.25, 0)
		local gg = { kind = g.kind, len = math.min(g.len, 2.6), w = 0.9, t = g.t }
		garment(K, f * ANG(0, -PI / 2, 0), gg, col, i % 2 == 1)
	end
end

local function buildLaundry(K: any, V: any, S: any)
	local rng = mkRng(V.key or V.name)
	local name = V.name or "세탁소"
	local navy = C(24, 50, 110)
	local cx = (V.x0 + V.x1) / 2
	step(K, "skin", function()
		wallSkin(K, { "left", "right", "back" }, 3.0, V.H - 0.02, lk(C(240, 244, 246), M.Plaster), lk(C(70, 110, 160)))
		addCeilLights(K, V, 4, 2)
	end)
	-- 1) 다림질대: 뒷벽 가운데 (문 앞 현관 keep 뒤 얕은 자리) — 들어오면 바로 보이는 작업대
	local steam, iron = nil, nil
	local pressU, ironU = nil, nil
	step(K, "press", function()
		local dep = 1.12
		for _, w in { 4.2, 3.4, 2.8 } do
			local cands = {}
			for _, dx in { 0, 0.6, -0.6, 1.2, -1.2, 2.0, -2.0 } do
				table.insert(cands, V3(cx + dx, 0, V.z0 + dep / 2 + 0.04))
			end
			local pcf = floorSpot(K, cands, V3(w + 1.3, 3.4, dep), V3(0, 0, 1), 0.0, "press")
			if pcf then
				steam, iron = pressStation(K, V, pcf * CF(-0.6, 0, 0), w, dep)
				pressU = pcf.Position.X - cx
				ironU = pressU - 0.6 - w / 2 + 1.1
				-- 일하는 자리 (앞) 비움
				K:reserve((pcf * CF(-(w + 1.3) / 2, 0, dep / 2)).Position, (pcf * CF((w + 1.3) / 2, 6, dep / 2 + 1.6)).Position:Max((pcf * CF(-(w + 1.3) / 2, 0, dep / 2)).Position), "front")
				break
			end
		end
		if steam and iron then
			promptOn(K, { iron, steam[3] }, { action = "스팀 분사", object = "스팀다리미", fn = function()
				for i, p in steam do
					task.delay(i * 0.12, function()
						if p.Parent then
							p.Transparency = 0.45
						end
						task.delay(1.4, function()
							if p.Parent then
								p.Transparency = 1
							end
						end)
					end)
				end
			end })
		end
		if not iron then
			note(K, "press: no room")
		end
	end)
	-- 3) 회전 컨베이어: 문 keep 바깥 ~ 옆벽, 맵 테이블이 없는 쪽
	local conv, convBox = nil, nil
	step(K, "conveyor", function()
		local depth = math.min(3.5, V.D - 2.0)
		local R = math.clamp((depth - 1.45) / 2, 0.7, 1.0)
		local railY = math.min(V.H - 1.2, 6.7)
		local best = nil
		local d = V.door
		for _, side in { 1, -1 } do
			local inner = if d then (if side > 0 then d.x + d.w / 2 + 2.15 else d.x - d.w / 2 - 2.15) else cx
			local outer = if side > 0 then V.x1 - 0.25 else V.x0 + 0.25
			local a, b = math.min(inner, outer), math.max(inner, outer)
			local function cut(mn: Vector3, mx: Vector3)
				if mn.Z < V.z0 + depth + 0.2 and mx.X > a and mn.X < b then
					if side > 0 then
						b = math.min(b, mn.X - 0.3)
					else
						a = math.max(a, mx.X + 0.3)
					end
				end
			end
			for _, sd in V.solid do
				if not K.hidden[sd.part] and sd.max.Y > 0.2 then
					cut(sd.min, sd.max)
				end
			end
			for _, t in V.tables do
				cut(t.min, t.max)
			end
			for _, r in K.reserved do
				if r.kind ~= "front" then
					cut(r.min, r.max)
				end
			end
			b = math.min(b, a + 7.5)
			if b - a >= 2 * R + 1.8 and (not best or b - a > best[2] - best[1]) then
				best = { a, b }
			end
		end
		if not best then
			note(K, "conveyor: no room")
			return
		end
		local a, b = best[1], best[2]
		local zc = V.z0 + 0.72 + R
		-- 레일 · 옷이 도는 부피 전체가 keep 밖이어야 함 (안 되면 반지름 · 길이를 줄임)
		local okBox = false
		for _ = 1, 8 do
			if not K:hitsKeep(V3(a, 2.4, V.z0), V3(b, V.H, zc + R + 0.75)) then
				okBox = true
				break
			end
			if R > 0.75 then
				R = 0.75
				zc = V.z0 + 0.72 + R
			elseif b - a > 2 * R + 2.2 then
				if d and d.x < (a + b) / 2 then
					a += 0.6
				else
					b -= 0.6
				end
			else
				break
			end
		end
		if not okBox then
			note(K, "conveyor: keep blocks")
			return
		end
		K:reserve(V3(a, 0, V.z0), V3(b, V.H, zc + R + 0.75), "conveyor")
		convBox = { a = a, b = b, zc = zc, R = R }
		conv = conveyor(K, V, a + R + 0.1, b - R - 0.1, zc, R, railY, rng)
	end)
	-- 컨베이어 조작함: 요금표보다 먼저 프롬프트 자리를 잡음 (서버 앵커 6.5 밖, 뒷벽)
	local convPanel = nil
	step(K, "convpanel", function()
		if not (conv and convBox) then
			return
		end
		local xs = {}
		for x = convBox.a - 0.6, V.x0 + 0.6, -0.3 do
			if math.abs(x - cx) > 2.75 then
				table.insert(xs, x)
			end
		end
		for x = convBox.a - 0.6, V.x0 + 0.6, -0.3 do
			if math.abs(x - cx) <= 2.75 then
				table.insert(xs, x)
			end
		end
		for _, x in xs do
			local u = x - cx
			local p = V:wall("back", u, 4.4, 0.15).Position
			if Interact.canPrompt(K, p) and wallFree(K, "back", u, 0.8, 3.7, 5.1, 0.3) then
				local d = V:wall("back", u, 4.4, 0.0)
				K:free(function()
					convPanel = K:plate("ConveyorPanel", 0.7, 1.0, 0.25, d, lk(C(220, 222, 224), M.Metal))
					K:disc("ConveyorBtnGo", 0.18, 0.05, d * CF(0, 0.2, 0.27) * ANG(PI / 2, 0, 0), Look.ledGreen)
					K:disc("ConveyorBtnStop", 0.18, 0.05, d * CF(0, -0.1, 0.27) * ANG(PI / 2, 0, 0), Look.ledRed)
					txt(K, "ConveyorPanelText", 0.6, 0.2, d * CF(0, -0.36, 0.26), "컨베이어", INK, nil, { font = F.GothamBold })
				end)
				break
			end
		end
		if convPanel then
			Interact.prompt(K, convPanel, { action = "컨베이어 돌리기", object = "옷 컨베이어", fn = function()
				conv.until_ = conv.clock + 6
			end, sound = "rbxasset://sounds/clickfast.wav" })
		else
			note(K, "conveyor panel: no prompt spot")
		end
	end)
	local sewBulb: BasePart? = nil
	step(K, "sewing", function()
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 3.0, 1.45, 4.0, V3(V.x0, 0, V.z0), 0.05, "sew")
		local sdep = 1.45
		if not wn then
			wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 2.9, 1.3, 4.0, V3(V.x0, 0, V.z0), 0.02, "sew")
			sdep = 1.3
		end
		if wn and pcf then
			local tp = pcf * CF(0, 0, -sdep / 2 + 0.7)
			local _, b = sewingCorner(K, tp, rng)
			sewBulb = b
			local stp = pcf * CF(0.2, 0, 1.3)
			if claim(K, stp, V3(1.1, 2.2, 1.1), 0, "stool") then
				Props.stool(K, stp, { style = "wood", seatTop = 2.0, dia = 1.0 })
			end
			local u = V:wallCoord(wn, pcf.Position)
			if wallFree(K, wn, u, 2.4, 4.0, 5.8, 0.3) then
				threadRack(K, V:wall(wn, u, 4.9, 0.01), 2.2, 1.6, rng)
			end
			if wallFree(K, wn, u, 1.6, 6.0, 7.0, 0.3) then
				txt(K, "SewSign", 1.5, 0.6, V:wall(wn, u, 6.5, 0.02), "수 선", WHITE, C(200, 40, 50), { font = F.GothamBlack, d = 0.06 })
			end
			if sewBulb then
				Interact.toggle(K, sewBulb, { object = "미싱 스탠드", onText = "스탠드 끄기", offText = "스탠드 켜기", state = true, on = function(on: boolean)
					if sewBulb and sewBulb.Parent then
						sewBulb.Material = if on then M.Neon else M.SmoothPlastic
						sewBulb.Color = if on then C(255, 240, 220) else C(120, 120, 120)
					end
				end })
			end
		end
	end)
	-- 4) 완성품 행거 (맵 테이블 뒤 = 직원 쪽, 남는 뒷벽)
	step(K, "rack", function()
		local railY = math.min(V.H - 1.4, 6.3)
		for _, len in { 4.6, 3.6, 2.6 } do
			local cands = {}
			for _, t in V.tables do
				local c = (t.min + t.max) / 2
				for _, dx in { 0, 0.8, -0.8, 1.6, -1.6 } do
					table.insert(cands, V3(c.X + dx, 0, V.z0 + 0.72))
				end
			end
			for _, f in { -0.36, 0.36, -0.28, 0.28 } do
				table.insert(cands, V3(cx + V.W * f, 0, V.z0 + 0.72))
			end
			local pcf = floorSpot(K, cands, V3(len, railY + 0.3, 1.42), V3(0, 0, 1), 0.0, "rack")
			if pcf then
				garmentRack(K, pcf, len, railY, rng, not lo(K))
				break
			end
		end
	end)
	-- 2) 요금표: 다림질대 위 뒷벽 (없으면 다른 벽)
	step(K, "prices", function()
		local w = math.min(4.0, V.W * 0.26)
		local y0, y1 = 4.1, math.min(V.H - 0.5, 7.4)
		local wn, d = wallItemSpot(K, { "back" }, w, y0, y1, if ironU then ironU + 0.4 + w / 2 else 0)
		if not wn then
			wn, d = wallItemSpot(K, { "back", "left", "right" }, w, y0, y1, 0)
		end
		if wn and d then
			-- 요금표 위 조명 (벽면이 어두워도 또렷하게)
			K:free(function()
				local bh = y1 - y0 - 0.2
				for _, fx in { -0.25, 0.25 } do
					local ld = d * CF(w * fx, bh / 2 + 0.25, 0)
					K:box("BoardLightArm", V3(0.08, 0.08, 0.55), ld * CF(0, 0, 0.27), Look.blackMetal)
					K:cyl("BoardLightHood", w * 0.36, 0.22, ld * CF(0, 0.04, 0.56), Look.blackMetal)
					local led = K:cyl("BoardLightLED", w * 0.34, 0.12, ld * CF(0, -0.03, 0.56), lk(C(250, 246, 236), M.SmoothPlastic))
					_ = led -- 스폿라이트는 글자를 하얗게 날려 버려서 빼고 (조명 예산도 아낌), 등기구 모양만
				end
			end)
			priceBoard(K, d, w, y1 - y0 - 0.2, name .. "  세탁 요금표", {
				{ "와이셔츠", "2,000" }, { "바지 · 스커트", "4,000" }, { "블라우스", "4,000" }, { "니트 · 스웨터", "5,000" }, { "원피스", "7,000" }, { "정장 상하", "9,000" },
				{ "코트", "12,000" }, { "패딩 점퍼", "15,000~" }, { "운동화", "6,000" }, { "이불 (극세사)", "15,000~" }, { "바지 기장 수선", "7,000" }, { "지퍼 교체", "10,000" },
			}, { cols = 2, head = navy, bg = C(238, 236, 230), ink = C(16, 20, 32), accent = C(196, 24, 36) })
		end
	end)
	-- 6) 상호작용: 컨베이어 조작함 · 스팀
	step(K, "interact", function()
	end)
	-- 7) 선반 (세제 · 옷걸이 묶음 · 비닐 롤)
	step(K, "shelf", function()
		local wn, d = wallItemSpot(K, { "left", "right", "back" }, 3.0, 5.9, 7.0, 0)
		if wn and d then
			local at = Props.shelf(K, d * CF(0, -0.4, 0), 3.0, { depth = 0.9, look = Look.white })
			-- 세제 말통 · 섬유유연제 · 얼룩 제거 스프레이
			local jugs = { C(40, 110, 200), C(240, 240, 240), C(250, 140, 170) }
			for i, jc in jugs do
				local jcf = at * CF(-1.25 + (i - 1) * 0.55, 0, -0.05)
				K:rbox("DetergentJug", V3(0.46, 0.72, 0.36), 0.06, jcf * CF(0, 0.36, 0), lk(jc, M.SmoothPlastic, { r = 0.15 }))
				K:box("DetergentHandle", V3(0.08, 0.2, 0.22), jcf * CF(0.14, 0.78, 0), lk(jc, M.SmoothPlastic))
				K:vcyl("DetergentCap", 0.1, 0.16, jcf * CF(-0.1, 0.77, 0), lk(if i == 2 then C(40, 110, 200) else C(250, 250, 250)))
				K:plate("DetergentLabel", 0.36, 0.3, 0.01, CFrame.fromMatrix((jcf * CF(0, 0.34, 0.185)).Position, jcf.XVector, Vector3.yAxis, jcf.ZVector), lk(if i == 2 then C(250, 200, 60) else C(250, 250, 250)))
			end
			for i = 0, 1 do
				local scf = at * CF(0.35 + i * 0.3, 0, 0.05)
				K:vcyl("SprayBottle", 0.5, 0.2, scf * CF(0, 0.25, 0), lk(if i == 0 then C(120, 200, 230) else C(250, 220, 90), M.SmoothPlastic, { t = 0.15 }))
				K:box("SprayHead", V3(0.12, 0.16, 0.2), scf * CF(0, 0.58, 0.03), lk(C(250, 250, 250)))
			end
			for i = 0, 3 do
				K:box("HangerBundle", V3(0.8, 0.45, 0.05), at * CF(0.95, 0.24, -0.25 + i * 0.12), lk(C(200, 202, 206), M.Metal))
			end
			K:cyl("PlasticRoll", 1.1, 0.4, at * CF(0.9, 0.2, 0.15) * ANG(0, 0, 0), lk(C(230, 236, 240), M.Glass, { t = 0.3 }))
		end
	end)
	-- 8) 안내문 (보관 기간 · 영업시간 · 운동화)
	step(K, "notices", function()
		local wn, d = wallItemSpot(K, { "left", "right", "back" }, 1.3, 3.6, 5.4, 0)
		if wn and d then
			paper(K, d, 1.2, 1.7, "알려드립니다", "세탁물 보관 기간은\n완성 후 3개월입니다\n기간 경과 시\n처분될 수 있습니다", { band = navy, pin = false })
		end
		local wn2, d2 = wallItemSpot(K, { "left", "right", "back" }, 1.3, 3.6, 5.4, 3)
		if wn2 and d2 then
			paper(K, d2, 1.2, 1.5, "영업시간", "평일 08:00-21:00\n토 09:00-18:00\n일요일 휴무\n\n카드 · 페이 결제 OK", { band = C(210, 40, 50), pin = false })
		end
		local wn3, d3 = wallItemSpot(K, { "left", "right", "back" }, 2.4, 5.6, 6.6, -3)
		if wn3 and d3 then
			txt(K, "SneakerSign", 2.3, 0.7, d3 * CF(0, 0, 0.02), "운동화 · 이불 · 명품 세탁\n오늘 맡기면 모레 완성", navy, C(250, 236, 120), { font = F.GothamBold, d = 0.05 })
		end
	end)
	-- 9) 바닥: 세탁물 바구니 · 화분
	step(K, "floor", function()
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.4, 1.2, 1.8, V3(V.x0, 0, V.z1 - 3), 0.05, "basket")
		if wn and pcf then
			K:vcyl("LaundryBasket", 1.4, 1.2, pcf * CF(0, 0.7, 0), lk(C(70, 140, 210)))
			K:vcyl("LaundryBasketRim", 0.1, 1.26, pcf * CF(0, 1.38, 0), lk(C(50, 110, 180)))
			for i = 0, 2 do
				K:ell("LaundryCloth", V3(0.9, 0.4, 0.7), pcf * CF((i - 1) * 0.25, 1.45 + i * 0.1, (i % 2) * 0.15), lk(pickR(rng, { C(240, 240, 240), C(200, 60, 60), C(60, 80, 140), C(220, 200, 150) }), M.Fabric))
			end
		end
		plantAt(K, pcfAt(V3(V.x1 - 0.9, 0, V.z1 - 1.0), V3(0, 0, 1)), "snake", 3.4, 1.0, lk(C(236, 234, 228), M.Concrete))
		-- 수선 마네킹: 수선 코너 가까이 (벽 앞, 문 · 창 keep 밖)
		local wf, fpcf = wallFloorSpot(K, { "left", "right", "back" }, 1.4, 1.4, 5.4, V3(V.x0 + 3, 0, V.z0), 0.02, "form")
		if wf and fpcf then
			dressForm(K, fpcf, pickR(rng, { C(40, 40, 44), C(226, 210, 184), C(240, 236, 230) }))
		end
		-- 맡긴 세탁물 망 (바구니 옆 바닥)
		local wb, bpcf = wallFloorSpot(K, { "left", "right", "back" }, 1.6, 1.2, 1.4, V3(V.x1, 0, V.z1 - 3), 0.05, "bags")
		if wb and bpcf then
			for i = 0, 2 do
				K:ell("LaundryBag", V3(0.95, 0.75 - i * 0.1, 0.8), bpcf * CF(-0.35 + i * 0.4, 0.34 + (i % 2) * 0.35, (i % 2) * 0.1 - 0.05) * ANG(0, i * 0.7, 0.1), lk(pickR(rng, { C(240, 240, 240), C(200, 210, 230), C(230, 220, 200) }), M.Fabric))
			end
			K:box("LaundryBagTag", V3(0.25, 0.32, 0.02), bpcf * CF(0.05, 0.9, 0.42) * ANG(0, 0, 0.15), lk(C(250, 220, 60)))
		end
	end)
	step(K, "fixtures", function()
		fixturesSorted(K, V, S)
	end)
	step(K, "switch", function()
		ensureSwitch(K, V)
	end)
	step(K, "posters", function()
		fillPosters(K, POSTERS.laundry, 2)
	end)
end

---------------------------------------------------------------------------------------------------
-- 10. 사무 공간 (office · bank · clinic · academy)
---------------------------------------------------------------------------------------------------

local OFFICE = {
	office = { color = C(30, 60, 110), title = "OFFICE", sub = "사무실", board = "업무 공지",
		sheets = { { "주간 회의", "매주 월 09:30\n3층 회의실" }, { "보안 수칙", "퇴근 시 PC 잠금\n서류 파쇄 필수" }, { "분리수거", "종이 · 캔 · 플라스틱\n분리 배출" } } },
	bank = { color = C(0, 90, 160), title = "BANK", sub = "은행 · 금융센터", board = "금리 안내",
		sheets = { { "정기예금", "12개월 연 3.2%\n우대 최고 3.6%" }, { "주택담보대출", "변동 연 3.9% ~\n상담 창구 2번" }, { "환율 안내", "USD 1,382\nJPY 9.21 · CNY 191" } } },
	clinic = { color = C(20, 140, 130), title = "CLINIC", sub = "의원 · 접수", board = "진료 안내",
		sheets = { { "진료시간", "평일 09:00-18:30\n토 09:00-13:00\n점심 13:00-14:00" }, { "독감 예방접종", "2026-27 시즌\n4가 백신 접종 중" }, { "건강검진", "국가 건강검진\n예약 접수 중" } } },
	academy = { color = C(230, 120, 30), title = "ACADEMY", sub = "학원 · 상담실", board = "수업 시간표",
		sheets = { { "초등반", "월수금 15:00\n화목 16:00" }, { "중등반", "월~금 17:30\n내신 대비" }, { "고등반", "월~금 19:30\n수능 특강" } } },
}

local OFFICE_NAMES = {
	bank = { "광안 해변은행 광안리지점", "수영 바다은행 민락지점" },
	clinic = { "광안 바다의원", "민락 가정의학과의원" },
	academy = { "광안 수학 · 영어학원", "해변 입시학원" },
	office = { "광안 오션 오피스", "수영 마린 컴퍼니" },
}

local function hasHangul(str: string): boolean
	return string.find(str, "[\234-\237]") ~= nil
end

-- 높은 접수 카운터 (책상 + 앞 가림판 3.4 + 위 선반). pcf 정면 +Z = 손님 쪽. 반환: 위 선반 pcf
local function receptionCounter(K: any, pcf: CFrame, w: number, col: Color3): CFrame
	local top = officeDesk(K, pcf * CF(0, 0, -0.35), w, 1.6, lk(C(236, 234, 228)))
	K:box("RecFront", V3(w, 3.3, 0.16), pcf * CF(0, 1.65, 0.53), lk(col))
	K:box("RecFrontBand", V3(w + 0.02, 0.12, 0.18), pcf * CF(0, 2.6, 0.53), lk(lighter(col, 0.4)))
	K:box("RecLedge", V3(w + 0.1, 0.1, 0.62), pcf * CF(0, 3.4, 0.42), Look.marbleWhite)
	K:box("RecKick", V3(w, 0.3, 0.1), pcf * CF(0, 0.15, 0.6), Look.black)
	_ = top
	return pcf * CF(0, 3.45, 0.42)
end

local function buildOffice(K: any, V: any, S: any)
	local t = V.type
	local cfg = OFFICE[t] or OFFICE.office
	local rng = mkRng(V.key or V.name)
	local name = V.name or cfg.title
	if not hasHangul(name) and OFFICE_NAMES[t] then
		name = pickR(rng, OFFICE_NAMES[t])
	end
	step(K, "skin", function()
		wallSkin(K, { "left", "right", "back" }, 0.45, V.H - 0.02, if t == "clinic" then lk(C(244, 248, 248), M.Plaster) else lk(C(240, 240, 236), M.Plaster))
		if t == "bank" or t == "office" then
			Props.wainscot(K, "back", 3.2, { look = lk(darker(cfg.color, 0.1)), cap = Look.brushed, panel = 2.0 })
		else
			Props.wainscot(K, "back", 3.0, { look = lk(lighter(cfg.color, 0.75)), cap = lk(cfg.color), panel = 0 })
		end
		addCeilLights(K, V, 4, 2)
	end)
	-- 상호 사인 (뒷벽 높은 곳)
	step(K, "sign", function()
		local w = math.min(7.5, V.W * 0.36)
		local y0 = math.min(V.H - 1.8, 6.4)
		local wn, d = wallItemSpot(K, { "back" }, w + 0.4, y0, y0 + 1.4, 0)
		if wn and d then
			K:plate("OfficeSignBack", w + 0.3, 1.3, 0.06, d * CF(0, 0.7, 0), lk(cfg.color))
			txt(K, "OfficeSign", w, 0.66, d * CF(0, 0.86, 0.08), name, WHITE, nil, { font = F.GothamBlack })
			txt(K, "OfficeSignSub", w * 0.6, 0.26, d * CF(0, 0.33, 0.08), cfg.sub, lighter(cfg.color, 0.7), nil, { font = F.GothamMedium })
		end
	end)
	-- 맵 테이블 → 사무 책상 덮개 (위는 비움)
	step(K, "tables", function()
		for _, tb in V.tables do
			if tb.kind ~= "grill" then
				consultDeskOver(K, V, tb, lk(C(240, 240, 236)))
			end
		end
	end)
	-- 서비스 줄: 은행 창구 · 접수 · 업무 책상
	local nDesk = if V.W > 26 then 3 elseif V.W > 16 then 2 else 1
	step(K, "service", function()
		for i = 1, nDesk do
			local pref = V3(V.x0 + V.W * (i - 0.5) / nDesk, 0, V.z0)
			if t == "bank" or t == "clinic" or (t == "academy" and i == 1) then
				local wn, pcf = wallFloorSpot(K, { "back" }, 3.8, 3.4, 4.6, pref, 0.05, "desk")
				if wn and pcf then
					local fc = pcf * CF(0, 0, 3.4 / 2 - 0.65)
					local ledge = receptionCounter(K, fc, 3.6, cfg.color)
					officeChair(K, pcf * CF(0, 0, -3.4 / 2 + 0.75))
					-- 카운터 안 모니터 (직원 쪽)
					monitor(K, fc * CF(0.4, 2.5, -0.55), 1.6, if t == "bank" then "고객 조회\n대기 3명" else "접수 대기 4명", C(236, 242, 248))
					keyboard(K, fc * CF(0.4, 2.5, -1.0) * ANG(0, PI, 0), 1.1)
					-- 선반 위: 펜 · 카드 단말기
					Props.cardTerminal(K, ledge * CF(1.2, 0, 0))
					penCup(K, ledge * CF(-1.3, 0, 0))
					if t == "bank" then
						-- 창구 칸막이 유리 + 번호
						K:box("TellerGlass", V3(3.6, 2.4, 0.06), fc * CF(0, 4.65, 0.2), lk(C(220, 236, 240), M.Glass, { t = 0.6 }))
						K:box("TellerGlassTop", V3(3.7, 0.12, 0.12), fc * CF(0, 5.9, 0.2), Look.brushed)
						local numY = math.min(V.H - 0.8, 7.0)
						K:box("TellerNumBox", V3(1.4, 0.7, 0.3), fc * CF(0, numY, 0.2), Look.black)
						txt(K, "TellerNum", 1.3, 0.6, CFrame.fromMatrix((fc * CF(0, numY, 0.36)).Position, fc.XVector, Vector3.yAxis, fc.ZVector), string.format("%d번  %04d", i, 120 + i * 3), C(255, 80, 60), nil, { font = F.GothamBold, glow = 1.6 })
					elseif t == "clinic" then
						txt(K, "RecSign", 2.6, 0.42, CFrame.fromMatrix((fc * CF(0, 2.0, 0.62)).Position, fc.XVector, Vector3.yAxis, fc.ZVector), "접수 · 수납", WHITE, nil, { font = F.GothamBold })
					else
						txt(K, "RecSign", 2.6, 0.42, CFrame.fromMatrix((fc * CF(0, 2.0, 0.62)).Position, fc.XVector, Vector3.yAxis, fc.ZVector), "입학 상담 · 안내", WHITE, nil, { font = F.GothamBold })
					end
				end
			else
				local wn, pcf = wallFloorSpot(K, { "back", "left", "right" }, 3.8, 3.2, 3.4, pref, 0.05, "desk")
				if wn and pcf then
					local dcf = pcf * CF(0, 0, 3.2 / 2 - 0.9)
					local top = officeDesk(K, dcf, 3.6, 1.7, lk(C(150, 116, 84), M.Wood))
					deskKit(K, top, 3.6, 1.7, if t == "academy" then "원장 상담" else pickR(rng, { "TEAM LEAD", "기획팀", "영업팀" }), if t == "academy" then "출결 관리\n오늘 출석 42명" else "업무 시스템\n결재 대기 2건", rng)
					officeChair(K, pcf * CF(0, 0, -3.2 / 2 + 0.75))
				end
			end
		end
	end)
	-- 대기 의자 줄 (옆벽 · 뒷벽)
	step(K, "waiting", function()
		for _, n in { 4, 3, 2 } do
			local len = n * 1.6
			local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, len + 0.2, 1.6, 3.2, V3(V.x0, 0, 0), 0.05, "wait")
			if wn and pcf then
				K:box("WaitBeam", V3(len, 0.12, 0.2), pcf * CF(0, 0.9, 0), Look.blackMetal)
				for _, sx in { -1, 1 } do
					K:box("WaitLeg", V3(0.12, 0.9, 1.2), pcf * CF(sx * (len / 2 - 0.3), 0.45, 0), Look.blackMetal)
				end
				for k = 1, n do
					local x = -len / 2 + 1.6 * (k - 0.5)
					K:box("WaitSeat", V3(1.45, 0.18, 1.3), pcf * CF(x, 1.55, 0.05), lk(cfg.color, M.Plastic))
					K:box("WaitBack", V3(1.45, 1.3, 0.14), pcf * CF(x, 2.3, -0.6) * ANG(-0.12, 0, 0), lk(cfg.color, M.Plastic))
					K:box("WaitPost", V3(0.12, 0.7, 0.12), pcf * CF(x, 1.2, 0), Look.blackMetal)
				end
				break
			end
		end
	end)
	-- 유형 소품 (바닥) + 상호작용
	step(K, "special", function()
		if t == "bank" then
			local wn2, pcf2 = wallFloorSpot(K, { "left", "right", "back" }, 1.4, 1.1, 4.6, V3(0, 0, V.z1 - 3), 0.05, "ticket", function(pc: CFrame)
				return Interact.canPrompt(K, (pc * CF(0, 3.2, 0.5)).Position)
			end)
			if wn2 and pcf2 then
				K:rbox("TicketBody", V3(1.2, 4.0, 0.9), 0.12, pcf2 * CF(0, 2.0, 0), lk(C(240, 240, 238)))
				local fr = CFrame.fromMatrix((pcf2 * CF(0, 3.2, 0.46)).Position, pcf2.XVector, Vector3.yAxis, pcf2.ZVector)
				local scr = K:plate("TicketScreen", 0.9, 0.7, 0.02, fr, lk(C(40, 120, 200), M.Neon, { t = 0.2 }))
				local _, lab = txt(K, "TicketText", 0.85, 0.6, fr * CF(0, 0, 0.03), "번호표\n입출금 · 상담", WHITE, nil, { font = F.GothamBold, glow = 1 })
				K:plate("TicketSlot", 0.5, 0.08, 0.03, CFrame.fromMatrix((pcf2 * CF(0, 2.5, 0.46)).Position, pcf2.XVector, Vector3.yAxis, pcf2.ZVector), Look.black)
				local slip = K:plate("TicketSlip", 0.3, 0.4, 0.01, CFrame.fromMatrix((pcf2 * CF(0, 2.32, 0.48)).Position, pcf2.XVector, Vector3.yAxis, pcf2.ZVector), { c = C(250, 250, 246), t = 1 })
				local no = 130
				Interact.prompt(K, scr, { action = "번호표 뽑기", object = "번호표 발행기", fn = function()
					no += 1
					if lab.Parent then
						lab.Text = string.format("%04d 번\n대기 %d명", no, 2 + no % 4)
					end
					if slip.Parent then
						slip.Transparency = 0
						task.delay(3, function()
							if slip.Parent then
								slip.Transparency = 1
							end
						end)
					end
				end })
			end
		elseif t == "clinic" then
			local wn2, pcf2 = wallFloorSpot(K, { "left", "right" }, 1.0, 1.0, 5.2, V3(0, 0, V.z1 - 3), 0.05, "sanitizer", function(pc: CFrame)
				return Interact.canPrompt(K, (pc * CF(0, 4.6, 0)).Position)
			end)
			if wn2 and pcf2 then
				K:disc("SanitizerBase", 0.9, 0.08, pcf2 * CF(0, 0.04, 0), Look.steel)
				K:vcyl("SanitizerPole", 3.0, 0.12, pcf2 * CF(0, 1.55, 0), Look.steel)
				K:box("SanitizerBox", V3(0.5, 0.8, 0.4), pcf2 * CF(0, 3.4, 0.1), Look.white)
				K:box("SanitizerTray", V3(0.4, 0.05, 0.3), pcf2 * CF(0, 2.9, 0.15), Look.grey)
				txt(K, "SanitizerText", 0.45, 0.3, CFrame.fromMatrix((pcf2 * CF(0, 3.45, 0.31)).Position, pcf2.XVector, Vector3.yAxis, pcf2.ZVector), "손소독제", C(20, 140, 130), nil, { font = F.GothamBold })
				-- 체온 측정 태블릿
				K:box("ThermoArm", V3(0.08, 0.6, 0.08), pcf2 * CF(0, 4.15, 0.05), Look.steel)
				K:box("ThermoBody", V3(0.6, 0.9, 0.1), pcf2 * CF(0, 4.6, 0.08), Look.black)
				local tf = CFrame.fromMatrix((pcf2 * CF(0, 4.6, 0.135)).Position, pcf2.XVector, Vector3.yAxis, pcf2.ZVector)
				local tscr = K:plate("ThermoScreen", 0.5, 0.75, 0.01, tf, lk(C(20, 60, 60), M.Neon, { t = 0.2 }))
				local _, tlab = txt(K, "ThermoText", 0.46, 0.6, tf * CF(0, 0, 0.012), "체온 측정\n얼굴을\n맞춰 주세요", WHITE, nil, { font = F.GothamBold, glow = 1 })
				Interact.prompt(K, tscr, { action = "체온 재기", object = "발열 체크 태블릿", fn = function()
					if tlab.Parent then
						tlab.Text = string.format("%.1f°C\n정상", 36.3 + (os.clock() * 10 % 5) / 10)
					end
					task.delay(3, function()
						if tlab.Parent then
							tlab.Text = "체온 측정\n얼굴을\n맞춰 주세요"
						end
					end)
				end })
			end
			-- 진료실 문 (벽 부착, 닫힘)
			local wn3, d3 = wallItemSpot(K, { "back", "left", "right" }, 3.0, 0.45, 7.2, V.W / 3)
			if wn3 and d3 then
				local dd = d3 * CF(0, -3.375, 0)
				K:plate("ClinicDoorFrame", 2.9, 6.9, 0.08, dd * CF(0, 3.45, 0), Look.white)
				K:plate("ClinicDoor", 2.6, 6.6, 0.06, dd * CF(0, 3.3, 0.08), lk(C(214, 226, 226)))
				K:plate("ClinicDoorGlass", 0.5, 2.4, 0.02, dd * CF(0.7, 4.4, 0.14), lk(C(200, 220, 224), M.Glass, { t = 0.3 }))
				K:plate("ClinicDoorHandle", 0.1, 0.8, 0.08, dd * CF(-1.0, 3.3, 0.14), Look.chrome)
				txt(K, "ClinicDoorSign", 1.6, 0.4, dd * CF(0, 5.7, 0.16), "진료실 1", WHITE, C(20, 140, 130), { font = F.GothamBold, d = 0.02 })
				local lamp = K:plate("ClinicDoorLamp", 1.0, 0.3, 0.05, dd * CF(0, 6.25, 0.1), Look.ledGreen)
				txt(K, "ClinicDoorLampText", 0.9, 0.24, dd * CF(0, 6.25, 0.16), "진료 중", WHITE, nil, { font = F.GothamBold, glow = 1.2 })
				_ = lamp
			end
		elseif t == "academy" then
			local wn2, d2 = wallItemSpot(K, { "back", "left", "right" }, 5.0, 3.0, 6.4, -V.W / 4)
			if wn2 and d2 then
				K:plate("WhiteBoard", 4.8, 3.0, 0.06, d2, lk(C(250, 250, 250), M.SmoothPlastic, { r = 0.05 }))
				K:plate("WhiteBoardFrame", 4.9, 0.08, 0.1, d2 * CF(0, -1.5, 0), Look.alu)
				txt(K, "WhiteBoardText", 4.2, 2.4, d2 * CF(0, 0.1, 0.07), "2026 수능 D-28\n\n이번 주 단어 시험 : 금요일\n개념 · 유형 · 실전 3단계", C(30, 60, 160), nil, { font = F.PermanentMarker })
				K:box("Marker", V3(0.5, 0.08, 0.08), d2 * CF(1.6, -1.45, 0.16), lk(C(200, 40, 40)))
			end
			local wn3, d3 = wallItemSpot(K, { "left", "right", "back" }, 4.4, 6.2, 7.4, 0)
			if wn3 and d3 then
				txt(K, "AcademyBanner", 4.3, 1.0, d3 * CF(0, 0, 0.02), "축  2026학년도 대입 합격\n부산대 · 경북대 · 해양대 외 32명", C(255, 240, 200), C(180, 30, 40), { font = F.GothamBlack, d = 0.03 })
			end
			local wn4, pcf4 = wallFloorSpot(K, { "back", "left", "right" }, 2.6, 1.1, math.min(6.4, V.H - 1), V3(V.x0 + 3, 0, V.z0), 0.05, "cab")
			if wn4 and pcf4 then
				binderCabinet(K, pcf4, 2.6, math.min(6.4, V.H - 1), rng)
			end
		else
			local wn4, pcf4 = wallFloorSpot(K, { "back", "left", "right" }, 2.6, 1.1, math.min(6.4, V.H - 1), V3(V.x0 + 3, 0, V.z0), 0.05, "cab")
			if wn4 and pcf4 then
				binderCabinet(K, pcf4, 2.6, math.min(6.4, V.H - 1), rng)
			end
			local wn5, pcf5 = wallFloorSpot(K, { "left", "right", "back" }, 1.9, 1.7, 3.2, V3(V.x1, 0, V.z0), 0.05, "mfp")
			if wn5 and pcf5 then
				mfp(K, pcf5)
			end
		end
	end)
	-- 게시판 · 화면
	step(K, "boards", function()
		local wn, d = wallItemSpot(K, { "left", "right", "back" }, 4.0, 3.6, 6.6, 0)
		if wn and d then
			noticeBoard(K, d, 3.8, 2.8, cfg.board, cfg.sheets, { cols = 3, head = cfg.color })
		end
		if t == "bank" then
			local wn2, d2 = wallItemSpot(K, { "left", "right", "back" }, 2.6, 4.2, 6.2, 0)
			if wn2 and d2 then
				K:plate("QueueDisplay", 2.4, 1.4, 0.15, d2, Look.black)
				local scr = K:plate("QueueScreen", 2.2, 1.2, 0.02, d2 * CF(0, 0, 0.15), { c = C(20, 20, 24), m = M.Neon, t = 0.1 })
				local _, lab = txt(K, "QueueText", 2.0, 1.1, d2 * CF(0, 0, 0.175), "0123 번 고객님\n2번 창구로 오세요", C(255, 80, 60), nil, { font = F.GothamBold, glow = 1.5 })
				Interact.screenLoop(K, scr, lab, { { text = "0123 번 고객님\n2번 창구로 오세요" }, { text = "0124 번 고객님\n1번 창구로 오세요" }, { text = "0125 번 고객님\n3번 창구로 오세요" } }, 6)
			end
			local wn3, d3 = wallItemSpot(K, { "left", "right", "back" }, 2.4, 3.8, 6.4, 3)
			if wn3 and d3 then
				priceBoard(K, d3, 2.2, 2.4, "오늘의 환율 (원)", { { "USD 미국", "1,382" }, { "JPY 100엔", "921" }, { "EUR 유럽", "1,498" }, { "CNY 중국", "191" } }, { cols = 1, head = cfg.color, accent = C(30, 30, 34) })
			end
		elseif t == "clinic" then
			local wn2, d2 = wallItemSpot(K, { "left", "right", "back" }, 1.4, 4.2, 6.2, 0)
			if wn2 and d2 then
				cert(K, d2, 1.3, 1.7, "의료기관 개설신고증", "부산광역시 수영구\n보건소장")
			end
			local wn3, d3 = wallItemSpot(K, { "left", "right", "back" }, 2.4, 3.8, 6.4, 3)
			if wn3 and d3 then
				priceBoard(K, d3, 2.2, 2.4, "비급여 진료비 안내", { { "독감 접종", "35,000" }, { "대상포진", "160,000" }, { "수액 (비타민)", "50,000" }, { "진단서", "20,000" } }, { cols = 1, head = cfg.color })
			end
		elseif t == "academy" then
			-- 교습비 등 게시표 (학원법상 게시 의무) · 등록증 · 셔틀 시간표 · 교재 책장
			local wn2, d2 = wallItemSpot(K, { "left", "right", "back" }, 2.8, 3.8, 6.6, 3)
			if wn2 and d2 then
				priceBoard(K, d2, 2.6, 2.7, "교습비 등 게시표 (월)", { { "초등 수학 주3회", "250,000" }, { "중등 수학 주3회", "320,000" }, { "고등 수학 주3회", "420,000" }, { "중등 영어 주3회", "300,000" }, { "교재비 · 모의고사", "별도" } }, { cols = 1, head = cfg.color, accent = C(40, 40, 46) })
			end
			local wn3, d3 = wallItemSpot(K, { "left", "right", "back" }, 1.4, 4.2, 6.2, 0)
			if wn3 and d3 then
				cert(K, d3, 1.3, 1.7, "학원 설립 · 운영 등록증", "부산광역시남부\n교육지원청 교육장")
			end
			local wn4, d4 = wallItemSpot(K, { "left", "right", "back" }, 1.4, 3.8, 5.8, -3)
			if wn4 and d4 then
				paper(K, d4, 1.3, 1.8, "셔틀버스 운행", "1차 15:00 광안초\n2차 17:10 수영중\n3차 19:20 광안역\n\n하원 22:00 출발", { band = cfg.color, pin = false })
			end
			local wn5, d5 = wallItemSpot(K, { "left", "right", "back" }, 3.0, 2.0, 5.4, V.W / 4)
			if wn5 and d5 then
				for i = 0, 2 do
					local at = Props.shelf(K, d5 * CF(0, -1.5 + i * 1.15, 0), 2.8, { depth = 0.8, look = Look.white })
					Props.row(K, at, 2.5, "books", { seed = i + 3, colors = { C(230, 120, 30), C(30, 60, 140), C(200, 40, 50), C(40, 140, 90), C(240, 200, 60) } })
				end
				txt(K, "BookShelfSign", 1.6, 0.3, d5 * CF(0, 2.0, 0.04), "교재 · 문제집", WHITE, cfg.color, { font = F.GothamBold, d = 0.03 })
			end
		end
	end)
	-- 바닥 소품: 정수기 · 화분
	step(K, "floor", function()
		local wn, pcf = wallFloorSpot(K, { "left", "right", "back" }, 1.6, 1.3, 3.6, V3(V.x0, 0, V.z0), 0.05, "water")
		if wn and pcf then
			purifier(K, pcf)
		end
		local planted = 0
		for _, p in { V3(V.x0 + 0.9, 0, V.z0 + 0.9), V3(V.x1 - 0.9, 0, V.z0 + 0.9), V3(V.x0 + 0.9, 0, V.z1 - 1.0), V3(V.x1 - 0.9, 0, V.z1 - 1.0) } do
			if planted < 2 and plantAt(K, pcfAt(p, V3(0, 0, 1)), pickR(rng, { "snake", "ficus", "monstera" }), math.min(5.0, V.H * 0.6), 1.2, lk(C(236, 234, 228), M.Concrete)) then
				planted += 1
			end
		end
	end)
	-- 벽 TV (안내 순환 + 넘기기)
	step(K, "tv", function()
		local wn, d = wallItemSpot(K, { "left", "right", "back" }, 3.4, 4.2, 6.6, 0, function(dc: CFrame)
			return Interact.canPrompt(K, (dc * CF(0, 0, 0.3)).Position)
		end)
		if not wn then
			wn, d = wallItemSpot(K, { "left", "right", "back" }, 3.4, 4.2, 6.6, 0)
		end
		if wn and d then
			local tvScr = Props.tv(K, d, 3.2, { on = true, screen = darker(cfg.color, 0.5) })
			local _, tvLab = txt(K, "OfficeTvText", 2.9, 1.6, d * CF(0, 0, 0.27), cfg.board .. "\n" .. cfg.sheets[1][1] .. "\n" .. string.gsub(cfg.sheets[1][2], "\n", " · "), WHITE, nil, { font = F.GothamBold, glow = 1.2 })
			local slides = {}
			for _, sh in cfg.sheets do
				table.insert(slides, cfg.board .. "\n" .. sh[1] .. "\n" .. string.gsub(sh[2], "\n", " · "))
			end
			local pr = Interact.cycle(K, tvScr, slides, { action = "안내 넘기기", object = cfg.sub .. " 안내 TV", on = function(_i, s2)
				if tvLab.Parent then
					tvLab.Text = s2
				end
			end })
			if not pr then
				local frames = {}
				for _, sl in slides do
					table.insert(frames, { text = sl })
				end
				Interact.screenLoop(K, nil, tvLab, frames, 6)
			end
		end
	end)
	step(K, "fixtures", function()
		S.clock = true
		fixturesSorted(K, V, S)
	end)
	step(K, "switch", function()
		ensureSwitch(K, V)
	end)
	-- 남은 벽: 포스터 · 에어컨
	step(K, "posters", function()
		fillPosters(K, POSTERS[t] or POSTERS.office, 3)
		local wn2, d2 = wallItemSpot(K, { "left", "right", "back" }, 3.1, math.min(V.H - 1.6, 6.4), math.min(V.H - 0.4, 7.6), 0)
		if wn2 and d2 then
			wallAC(K, d2 * CF(0, 0.05, 0))
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- 11. 진입
---------------------------------------------------------------------------------------------------

function T.build(K: any, V: any, S: any)
	local t = V.type
	if t == "lobby" then
		-- 로비에도 맵 우편함 (게임플레이) 이 있으면 같은 범위로 덮고 앞을 비움
		step(K, "lobbymail", function()
			for _, r in V.byName.Mailboxes or {} do
				local f = mailboxOver(K, V, r)
				K:reserve(r.min - V3(0.2, 0, 0.2), r.max + V3(0.2, 0, 0.2), "mail")
				if math.abs(f.X) > 0.5 then
					local fx = if f.X > 0 then r.max.X else r.min.X
					K:reserve(V3(math.min(fx, fx + f.X * 2.6), 0, r.min.Z), V3(math.max(fx, fx + f.X * 2.6), 6, r.max.Z), "front")
				else
					local fz = if f.Z > 0 then r.max.Z else r.min.Z
					K:reserve(V3(r.min.X, 0, math.min(fz, fz + f.Z * 2.6)), V3(r.max.X, 6, math.max(fz, fz + f.Z * 2.6)), "front")
				end
			end
		end)
		if isMotel(V) then
			buildMotel(K, V, S)
		else
			buildHotel(K, V, S)
		end
	elseif t == "residence" then
		buildResidence(K, V, S)
	elseif t == "realty" then
		buildRealty(K, V, S)
	elseif t == "laundry" then
		buildLaundry(K, V, S)
	else
		buildOffice(K, V, S)
	end
end

return T
