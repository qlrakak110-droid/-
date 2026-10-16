--!strict
-- GwangalliBuildingInterior/T_clinic: 광안 메디컬 의원 방 유형 실내 (Venues.luau 의 방, Scan.fitRoom).
--   clinic_lobby (접수 · 수납) clinic_waiting (대기실) clinic_consult (진료실 1 · 내과) clinic_pharmacy (약국 코너)
--   clinic_treat (주사실 · 처치실) clinic_hall (후면 홀) clinic_ward (입원실 201 · 202) clinic_nurse (간호사실)
--   clinic_lounge (휴게실) clinic_checkup (건강검진센터)
--   style(V) -> S  (Common 단계는 전부 건너뜀: 아래 build 에서 방 틀을 다시 맞춘 뒤 직접 부름)
--   build(K, V, S) 유형별 디테일
-- 방 틀 다시 맞추기 (refit): 병원 건물은 월드 축에서 약 1.9도 돌아가 있고 rooms.json 상자는 월드 축 · 벽 안쪽 면과
-- 0.4~2 스터드 어긋나 있어, 건물 벽에 맞춘 회전 틀 + 실제 벽 안쪽 면 상자로 Scan.fitRoom 을 다시 합니다 (K.V / K.cf 교체).
-- 지켜야 할 것 (서버 계약): HospitalPrompt 앵커 · 프롬프트, HospitalBed BedSeat (자리 · 높이 그대로, 보이게),
-- HospitalStaff 리그, GwProp 주사기, AutoDoor_Hospital, Door_* 모델, LEDScreen, Seat 파트 (숨겨도 앉기는 그대로),
-- Law/Hospital NPC 지점 사이 통로 (아래 SPOTS/LANES 로 keep 추가).

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local T = {}
T.types = { "clinic_lobby", "clinic_waiting", "clinic_consult", "clinic_pharmacy", "clinic_treat", "clinic_hall", "clinic_ward", "clinic_nurse", "clinic_lounge", "clinic_checkup" }

local M = Enum.Material
local CF, V3, ANG = CFrame.new, Vector3.new, CFrame.Angles
local PI = math.pi
local C3 = Color3.fromRGB
local FONT_B, FONT_M, FONT_K = Enum.Font.GothamBold, Enum.Font.GothamMedium, Enum.Font.GothamBlack

-- 색 · 재질 ----------------------------------------------------------------------------------------------
local TEAL = C3(0, 128, 118) -- 맵 병원 브랜드 청록
local TEAL_D = C3(0, 92, 86)
local MINT = C3(196, 232, 226)
local MINT_L = C3(228, 245, 241)
local WHITE = C3(250, 250, 248)
local INK = C3(30, 34, 38)
local GREY_T = C3(96, 102, 108)
local RED = C3(206, 36, 40)
local NAVY = C3(28, 50, 92)
local GREEN_EXIT = C3(0, 150, 80)

local function lk(r: number, g: number, b: number, m: Enum.Material?, extra: { [string]: any }?): any
	return Look.of(r, g, b, m, extra)
end
local function col(c: Color3, m: Enum.Material?, extra: { [string]: any }?): any
	local t: any = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
local function darker(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), t)
end

local LK = {
	white = lk(246, 246, 243),
	paint = lk(240, 240, 236),
	abs = lk(236, 238, 236, M.Plastic),
	absGrey = lk(178, 184, 188, M.Plastic),
	absDark = lk(86, 92, 98, M.Plastic),
	steel = Look.steel,
	chrome = Look.chrome,
	alu = Look.alu,
	darkAlu = Look.darkAlu,
	black = Look.black,
	rubber = Look.rubber,
	teal = col(TEAL),
	tealD = col(TEAL_D),
	mint = col(MINT),
	vinylTeal = lk(46, 120, 124, M.Leather),
	vinylNavy = lk(40, 56, 88, M.Leather),
	vinylGrey = lk(118, 124, 130, M.Leather),
	vinylMint = lk(150, 200, 196, M.Leather),
	vinylCream = lk(226, 218, 200, M.Leather),
	mattress = lk(170, 196, 214, M.Leather),
	sheet = lk(244, 246, 246, M.Fabric),
	curtain = lk(150, 198, 200, M.Fabric),
	curtainMesh = lk(228, 240, 238, M.Fabric, { t = 0.35 }),
	glass = Look.glass(C3(214, 232, 236), 0.62),
	glassFrost = { c = C3(232, 240, 240), m = M.Glass, t = 0.25, r = 0.05 },
	screenOff = Look.screen(),
	wood = Look.oak,
	lightWood = Look.lightOak,
	paper = Look.paper,
	cardboard = Look.cardboard,
}

-- 기본 도구 -----------------------------------------------------------------------------------------------
local function note(K: any, s: string)
	K:note("clinic: " .. s)
end

local function step(K: any, name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		note(K, name .. " error: " .. tostring(err))
	end
end

local function hashStr(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

local function rng(seed: any): () -> number
	local s = (if type(seed) == "number" then seed else hashStr(tostring(seed))) % 2147483646 + 1
	return function(): number
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

-- 글자판 (K:text) 줄임
local function tx(K: any, name: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3?, bg: Color3?, o: any?): (BasePart, TextLabel)
	local oo: any = o or {}
	return K:text(name, w, h, dcf, s, {
		fg = fg or INK,
		bg = bg,
		font = oo.font or FONT_B,
		d = oo.d or 0.03,
		glow = oo.glow,
		align = oo.align,
		free = oo.free,
		look = oo.look,
		maxDist = oo.maxDist,
		wrap = oo.wrap,
	})
end

-- dcf 를 pcf 처럼: 표면 위 점에서 수평으로 바라보는 방향 n (보는 사람 쪽)
local function faceCF(p: Vector3, n: Vector3): CFrame
	local z = Vector3.new(n.X, 0, n.Z).Unit
	local x = Vector3.yAxis:Cross(z).Unit
	return CFrame.fromMatrix(p, x, Vector3.yAxis, z)
end

-- 바닥 소품 pcf (x, z, 앞 방향 각도: 0 = +Z, PI/2 = +X ...)
local function at(x: number, z: number, yaw: number?): CFrame
	return CF(x, 0, z) * ANG(0, yaw or 0, 0)
end

-- 숨기기 ----------------------------------------------------------------------------------------------------
local function hideRec(K: any, r: any)
	if r and r.part then
		Scan.hide(K.hidden, r.part)
	end
end

local function hideList(K: any, list: { any }?)
	for _, r in list or {} do
		hideRec(K, r)
	end
end

-- 이름 목록의 파트 숨기기 (filter(rec) -> bool 선택)
local function hideNames(K: any, names: { string }, filter: ((any) -> boolean)?)
	local V = K.V
	for _, n in names do
		for _, r in V.byName[n] or {} do
			if not filter or filter(r) then
				hideRec(K, r)
			end
		end
	end
end

-- 부모 모델 이름으로 찾기
local function recsIn(V: any, modelName: string): { any }
	local out = {}
	for _, r in V.parts do
		local p = r.part.Parent
		if p and p.Name == modelName then
			table.insert(out, r)
		end
	end
	return out
end

local function sibling(V: any, r: any, name: string): any?
	local par = r.part.Parent
	for _, q in V.parts do
		if q.name == name and q.part.Parent == par then
			return q
		end
	end
	return nil
end

local function siblings(V: any, r: any): { any }
	local par = r.part.Parent
	local out = {}
	for _, q in V.parts do
		if q.part.Parent == par then
			table.insert(out, q)
		end
	end
	return out
end

local function nearest(V: any, name: string, p: Vector3, maxD: number?): any?
	local best, bd = nil, maxD or math.huge
	for _, r in V.byName[name] or {} do
		local d = (Vector3.new(r.c.X, 0, r.c.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude
		if d < bd then
			best, bd = r, d
		end
	end
	return best
end

-- 벽 자리 기록 (Common.wallSpot 이 피하게)
local function wallUse(K: any, wn: string, a: number, b: number, y0: number, y1: number)
	K.wallUsed = K.wallUsed or {}
	table.insert(K.wallUsed, { w = wn, a = a, b = b, y0 = y0, y1 = y1 })
end

-- 벽면 u 구간이 비었나 (맵 물건 · keep · 이미 쓴 자리)
local function wallFree(K: any, wn: string, u: number, w: number, y0: number, y1: number, depth: number?): boolean
	local V = K.V
	local a, b = u - w / 2, u + w / 2
	local okSpan = false
	for _, s in V:spans(wn, y0, y1, depth or 1.0) do
		if s[1] <= a + 0.01 and s[2] >= b - 0.01 then
			okSpan = true
			break
		end
	end
	if not okSpan then
		return false
	end
	for _, used in K.wallUsed or {} do
		if used.w == wn and used.a < b and used.b > a and used.y0 < y1 and used.y1 > y0 then
			return false
		end
	end
	return true
end

-- 벽 위 자리 찾기: prefer 에 가까운 빈 u (없으면 nil). 찾으면 기록하고 dcf 반환
local function wallSpot(K: any, wn: string, w: number, y0: number, y1: number, prefer: number, depth: number?): CFrame?
	local V = K.V
	local wall = V.walls[wn]
	if not wall then
		return nil
	end
	local best, bd = nil, math.huge
	local stepU = 0.25
	local u = wall.a + w / 2 + 0.3
	while u <= wall.b - w / 2 - 0.3 do
		local d = math.abs(u - prefer)
		if d < bd and wallFree(K, wn, u, w, y0, y1, depth) then
			best, bd = u, d
		end
		u += stepU
	end
	if best then
		wallUse(K, wn, best - w / 2 - 0.15, best + w / 2 + 0.15, y0, y1)
		return V:wall(wn, best, (y0 + y1) / 2, 0)
	end
	return nil
end

-- 벽에 등을 댄 바닥 소품 pcf (+Z = 방 안쪽). 자리가 비었으면 pcf, 아니면 nil
local function wallFloor(K: any, wn: string, u: number, w: number, d: number, h: number, pad: number?, gap: number?): CFrame?
	local V = K.V
	local pcf = V:wall(wn, u, 0, (gap or 0.02) + d / 2)
	pcf = CFrame.fromMatrix(pcf.Position, pcf.XVector, Vector3.yAxis, pcf.ZVector)
	if K:spot(pcf, V3(w, h, d), pad or 0) then
		return pcf
	end
	return nil
end

-- 벽에 등을 댄 바닥 소품: prefer 근처에서 자리 찾기
local function wallFloorNear(K: any, wn: string, prefer: number, w: number, d: number, h: number, range: number?, pad: number?): (CFrame?, number?)
	local r = range or 6
	local best = nil
	for i = 0, math.floor(r / 0.5) do
		for _, sgn in { 1, -1 } do
			local u = prefer + sgn * i * 0.5
			local pcf = wallFloor(K, wn, u, w, d, h, pad)
			if pcf then
				return pcf, u
			end
			if i == 0 then
				break
			end
		end
	end
	return best, nil
end

-- 자유 바닥 소품
local function floorAt(K: any, x: number, z: number, yaw: number, w: number, d: number, h: number, pad: number?): CFrame?
	local pcf = at(x, z, yaw)
	if K:spot(pcf, V3(w, h, d), pad or 0) then
		return pcf
	end
	return nil
end

-- 방 틀 다시 맞추기 ------------------------------------------------------------------------------------------
-- 건물에 맞춘 회전 틀(원점 = rooms.json 방 가운데)에서 잰 실제 벽 안쪽 면 { x0, x1, z0, z1 }
local ROOMFIX: { [string]: { number } } = {
	lobby = { -23.5, 23.87, -13.6, 12.9 },
	waiting = { -13.31, 12.5, -13.48, 13.04 },
	consult = { -22.28, 22.3, -13.87, 14.27 },
	pharmacy = { -29.31, 29.29, -11.88, 11.5 },
	treat = { -23.26, 23.33, -11.64, 11.75 },
	backhall = { -58.8, 59.6, -8.26, 8.32 },
	ward201 = { -22.25, 22.53, -12.66, 12.79 },
	nurse = { -13.94, 14.05, -13.17, 12.27 },
	ward202 = { -22.38, 22.38, -12.98, 12.47 },
	lounge = { -18.92, 19.83, -22.86, 19.9 },
	checkup = { -24.76, 26.01, -21.72, 21.02 },
}
-- 앞(+Z)이 거리 유리창인 방 (window keep 유지)
local FRONT_GLASS = { lobby = true, waiting = true }
-- 뒤(-Z)가 바깥 창인 방 (창 앞 비움)
local BACK_GLASS = { consult = true, ward201 = true, ward202 = true, nurse = true }

-- Law/Hospital NPC 지점 (월드 xz, 서버 SPOTS) 과 지점 사이 통로 (서버 걷기 격자가 고르는 길을 단순화한 꺾은선)
local SPOTS1 = {
	fore = { -496, 252 }, door = { -496, 270 }, lobby = { -505, 276 }, desk_front = { -515, 281 }, desk = { -503, 284 },
	wait1 = { -466, 275 }, wait2 = { -466, 281 }, wait3 = { -466, 287 }, hall = { -505, 300 }, hall2 = { -525, 294 },
	bench = { -520, 328 }, pharm = { -540, 294 }, cons_door = { -537, 297 }, cons = { -545, 285 }, treat_door = { -485, 296 },
	treat = { -478, 308 }, treat_bed = { -468, 309 }, lift1 = { -548, 332 },
}
local SPOTS2 = {
	lift2 = { -548, 332 }, landing = { -540, 294 }, corr2 = { -520, 290 }, station = { -515, 284 }, w201_door = { -497, 293 },
	w201 = { -480, 283 }, w201_bed = { -466, 282 }, w202_door = { -537, 292 }, w202 = { -550, 281 }, w202_bed = { -540, 281 },
	check_door = { -543, 298 }, check = { -552, 312 }, lounge = { -478, 311 },
}
local LANES1 = {
	{ { -496, 252 }, { -496, 270 }, { -505, 276 }, { -515, 281 } },
	{ { -505, 276 }, { -503, 284 } },
	{ { -505, 276 }, { -466, 275 } },
	{ { -505, 276 }, { -466, 281 } },
	{ { -505, 276 }, { -480, 284 }, { -466, 287 } },
	{ { -505, 276 }, { -497, 291 }, { -505, 300 } },
	{ { -505, 300 }, { -525, 294 }, { -540, 294 } },
	{ { -525, 294 }, { -537, 297 }, { -534.9, 292.5 }, { -545, 285 } },
	{ { -505, 300 }, { -485, 296 }, { -487, 298.8 }, { -478, 308 }, { -468, 309 } },
	{ { -505, 300 }, { -510, 323 }, { -520, 328 }, { -548, 332 } },
}
local LANES2 = {
	{ { -548, 332 }, { -552, 312 }, { -543, 298 }, { -538.9, 295 }, { -540, 294 }, { -520, 290 } },
	{ { -548, 332 }, { -543, 298 } },
	{ { -540, 294 }, { -537, 292 }, { -534.75, 289.2 }, { -550, 281 }, { -540, 281 } },
	{ { -520, 290 }, { -497, 293 }, { -494.8, 290.5 }, { -480, 283 }, { -466, 282 } },
	{ { -520, 290 }, { -525.5, 290 }, { -525.5, 284 }, { -515, 284 } },
	{ { -520, 290 }, { -503.5, 290 }, { -503.5, 284 }, { -515, 284 } },
	{ { -497, 293 }, { -478.6, 296 }, { -478, 311 } },
}

-- 건물 회전 (V.cf 기준 Y 각, -45..45 도)
local function buildingAngle(V: any): number
	local angs = {}
	for _, r in V.parts do
		local p: BasePart = r.part
		if p.Size.Magnitude > 8 and math.abs(p.CFrame.UpVector.Y) > 0.999 then
			local xv = V.cf:VectorToObjectSpace(p.CFrame.XVector)
			local a = math.atan2(-xv.Z, xv.X)
			while a > PI / 4 do
				a -= PI / 2
			end
			while a <= -PI / 4 do
				a += PI / 2
			end
			table.insert(angs, a)
		end
	end
	if #angs == 0 then
		return 0
	end
	table.sort(angs)
	return angs[math.floor(#angs / 2) + 1]
end

local function addLaneKeeps(V: any, floorY: number, lanes: { any }, spots: { [string]: { number } }, hw: number, sr: number)
	local function L(p: { number }): Vector3
		local l = V.cf:PointToObjectSpace(Vector3.new(p[1], floorY, p[2]))
		return Vector3.new(l.X, 0, l.Z)
	end
	local function inside(p: Vector3, m: number): boolean
		return p.X > V.x0 - m and p.X < V.x1 + m and p.Z > V.z0 - m and p.Z < V.z1 + m
	end
	for _, line in lanes do
		for i = 1, #line - 1 do
			local a, b = L(line[i]), L(line[i + 1])
			local len = (b - a).Magnitude
			local n = math.max(1, math.ceil(len / 1.0))
			for k = 0, n do
				local p = a:Lerp(b, k / n)
				if inside(p, hw) then
					V:addKeep(Vector3.new(p.X - hw, 0.1, p.Z - hw), Vector3.new(p.X + hw, 6.5, p.Z + hw), "lane")
				end
			end
		end
	end
	for _, s in spots do
		local p = L(s)
		if inside(p, sr) then
			V:keepAround(p, sr, 6.5, "point")
		end
	end
end

-- V 를 건물 틀로 다시 맞춤. 반환 V2 (실패하면 V)
local function refit(V: any): any
	local fix = ROOMFIX[V.room or ""]
	if not fix or not V.model then
		return V
	end
	local a = buildingAngle(V)
	local rf = V.cf * ANG(0, a, 0)
	local x0, x1, z0, z1 = fix[1], fix[2], fix[3], fix[4]
	local cf2 = rf * CF((x0 + x1) / 2, 0, (z0 + z1) / 2)
	local spec = {
		cf = cf2,
		size = V3(x1 - x0, V.H, z1 - z0),
		type = V.type,
		room = V.room,
		kind = "venue",
		name = V.name,
		key = V.key,
		noDoorGuess = true,
		margin = 0.6,
	}
	local ok, V2 = pcall(Scan.fitRoom, V.model, spec)
	if not ok or not V2 then
		return V
	end
	V2.maxParts, V2.maxLights, V2.detail = V.maxParts, V.maxLights, V.detail
	V2.bAngle = a
	V2.orig = V
	local upper = V2.cf.Y > 15 -- 2층
	V2.upper = upper
	-- keep 고치기 (Scan 이 시설 전체 'Staff' 폴더를 NPC 하나로 · 1층 자동문을 2층 방 문으로 · 벽을 유리창으로 봄)
	local keep = {}
	for _, k in V2.keep do
		local sz = k.max - k.min
		if k.kind == "npc" and (sz.X > 10 or sz.Z > 10) then
			continue
		end
		if k.kind == "door" and upper then
			continue
		end
		if k.kind == "window" and not FRONT_GLASS[V.room] then
			continue
		end
		table.insert(keep, k)
	end
	V2.keep = keep
	if upper then
		V2.door, V2.doors = nil, {}
	end
	-- 실제 리그 (HumanoidRootPart) 둘레
	for _, r in V2.byName.HumanoidRootPart or {} do
		V2:keepAround(r.c, 2.0, 6.5, "npc")
	end
	-- 서버 프롬프트 앵커 둘레
	for _, n in { "HospitalPrompt_desk", "HospitalPrompt_doctor" } do
		for _, r in V2.byName[n] or {} do
			V2:keepAround(r.c, 1.4, 6.5, "point")
		end
	end
	if BACK_GLASS[V.room] then
		V2:addKeep(Vector3.new(V2.x0 - 1, 0.1, V2.z0 - 0.5), Vector3.new(V2.x1 + 1, V2.H, V2.z0 + 1.1), "window")
	end
	-- NPC 통로
	local floorY = V2.cf.Y
	if upper then
		addLaneKeeps(V2, floorY, LANES2, SPOTS2, 1.25, 1.7)
	else
		addLaneKeeps(V2, floorY, LANES1, SPOTS1, 1.25, 1.7)
	end
	return V2
end
T._refit = refit

T._debug = {}

return T
