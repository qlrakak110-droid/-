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
-- 벽이 없는 쪽 (열린 방 경계): 통째로 없는 벽 / 일부 열린 구간 { wall, u0, u1 }
local OPEN_WALLS = { lobby = { left = true }, waiting = { right = true } }
local OPEN_SPANS = {
	lobby = { { "back", -24, -6.1 } },
	backhall = { { "front", -0.6, 12.2 } },
	nurse = { { "front", -15, 15 } },
	lounge = { { "front", -6.2, 0.2 } },
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
	-- 열린 경계: 벽 정보 지우기 + 열린 구간은 벽면 keep (벽 소품 · 바닥 소품이 안 들어가게)
	for wn in OPEN_WALLS[V.room] or {} do
		V2.walls[wn] = nil
	end
	for _, o in OPEN_SPANS[V.room] or {} do
		local a = V2:wall(o[1], o[2], 0, 0).Position
		local b = V2:wall(o[1], o[3], 0, 0.9).Position
		V2:addKeep(Vector3.new(math.min(a.X, b.X), 0.1, math.min(a.Z, b.Z)), Vector3.new(math.max(a.X, b.X), V2.H - 0.3, math.max(a.Z, b.Z)), "opening")
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

-- 천장: 맵 T-bar 격자(4.08) 를 반으로 나눠 600각 텍스 + 2x2 LED 평판등 ------------------------------------------
local function tbarGrid(V: any): ({ number }, { number })
	local gx, gz = {}, {}
	local seenX, seenZ = {}, {}
	local root = V.model
	for _, d in root:GetDescendants() do
		if d.Name == "TBar" and d:IsA("BasePart") then
			local l = V.cf:ToObjectSpace(d.CFrame)
			if math.abs(l.Y - V.H) < 0.8 then
				local s = d.Size
				local long = if s.X >= s.Z then l.XVector else l.ZVector
				if math.abs(long.Z) > 0.95 then
					local k = math.floor(l.X * 4 + 0.5)
					if l.X > V.x0 - 4.5 and l.X < V.x1 + 4.5 and not seenX[k] then
						seenX[k] = true
						table.insert(gx, l.X)
					end
				elseif math.abs(long.X) > 0.95 then
					local k = math.floor(l.Z * 4 + 0.5)
					if l.Z > V.z0 - 4.5 and l.Z < V.z1 + 4.5 and not seenZ[k] then
						seenZ[k] = true
						table.insert(gz, l.Z)
					end
				end
			end
		end
	end
	table.sort(gx)
	table.sort(gz)
	return gx, gz
end

-- 반 격자 선 (맵 선 + 가운데 선, 방 안쪽만)
local function halfLines(lines: { number }, a: number, b: number, pitch: number): ({ number }, { number })
	local all, mids = {}, {}
	if #lines < 2 then
		local n = math.floor((b - a) / pitch)
		for i = 0, n do
			table.insert(all, a + i * pitch)
		end
		return all, all
	end
	local step = lines[2] - lines[1]
	local first = lines[1]
	while first - step / 2 > a do
		first -= step
	end
	local x = first
	while x < b + step do
		for _, v in { x, x + step / 2 } do
			if v > a + 0.15 and v < b - 0.15 then
				table.insert(all, v)
				if v ~= x then
					table.insert(mids, v)
				end
			end
		end
		x += step
	end
	table.sort(all)
	return all, mids
end

-- 아랫벽 보호 패널 + 청록 몰딩 (벽 이름 목록, 높이 y1)
local function lowerWall(K: any, V: any, walls: { string }, y1: number?, look: any?, capC: Color3?)
	local yy = y1 or 3.0
	for _, wn in walls do
		if V.walls[wn] then
			K:free(function()
				for _, s in V:spans(wn, 0.45, yy, 0.25) do
					local len = s[2] - s[1]
					if len > 0.8 then
						local u = (s[1] + s[2]) / 2
						K:plate("WallGuardPanel", len, yy - 0.45, 0.04, V:wall(wn, u, 0.45 + (yy - 0.45) / 2, 0.005), look or lk(232, 230, 224, M.SmoothPlastic))
						K:plate("WallGuardCap", len, 0.12, 0.09, V:wall(wn, u, yy, 0.005), col(capC or TEAL))
					end
				end
			end)
		end
	end
end

-- 천장 아래 빈 자리? (맵 T-bar · 숨긴 LightPanel 은 무시: Common.ceilFree 는 T-bar 를 막힘으로 봄)
local CEIL_SKIP = { LightPanel = true, TBar = true, CeilingBoard = true, Ceiling = true }
local function ceilOK(K: any, x: number, z: number, r: number): boolean
	local V = K.V
	for _, h in V.hang do
		if not CEIL_SKIP[h.name] and h.max.Y > V.H - 1.2 and x > h.min.X - r and x < h.max.X + r and z > h.min.Z - r and z < h.max.Z + r then
			return false
		end
	end
	for _, q in K.ceilUsed or {} do
		if math.abs(q.X - x) < r * 2 and math.abs(q.Z - z) < r * 2 then
			return false
		end
	end
	return true
end

-- 천장 마감. o.skin (텍스 look), o.every (평판등 간격 칸 수, 기본 3), o.lights (붙일 불빛 수), o.bright, o.range,
-- o.avoid = { {x0,z0,x1,z1} } 평판등을 피할 xz 구간, o.hideMap (맵 LightPanel 숨김, 기본 true)
local function ceilingKit(K: any, V: any, o: any?)
	local oo: any = o or {}
	local H = V.H
	if oo.hideMap ~= false then
		hideNames(K, { "LightPanel" })
	end
	local gx, gz = tbarGrid(V)
	local xs, mx = halfLines(gx, V.x0, V.x1, 2.04)
	local zs, mz = halfLines(gz, V.z0, V.z1, 2.04)
	local barL = lk(206, 206, 202, M.Metal)
	local vd = oo.void -- { x0, z0, x1, z1 } 천장 구멍 (계단)
	-- 구간 a..b 에서 구멍 [c, d] 빼기
	local function cut(a: number, b: number, c: number?, d: number?): { { number } }
		if not c or not d or d <= a or c >= b then
			return { { a, b } }
		end
		local out = {}
		if c > a + 0.1 then
			table.insert(out, { a, c })
		end
		if d < b - 0.1 then
			table.insert(out, { d, b })
		end
		return out
	end
	K:free(function()
		local skinL = oo.skin or lk(238, 237, 232, M.Plaster)
		if vd then
			for _, sx in cut(V.x0, V.x1, vd[1], vd[3]) do
				K:box("CeilingSkin", V3(sx[2] - sx[1] - 0.02, 0.02, V.D - 0.04), CF((sx[1] + sx[2]) / 2, H - 0.018, 0), skinL)
			end
			for _, sz in cut(V.z0, V.z1, vd[2], vd[4]) do
				K:box("CeilingSkin", V3(vd[3] - vd[1], 0.02, sz[2] - sz[1] - 0.02), CF((vd[1] + vd[3]) / 2, H - 0.018, (sz[1] + sz[2]) / 2), skinL)
			end
		else
			K:box("CeilingSkin", V3(V.W - 0.04, 0.02, V.D - 0.04), CF(0, H - 0.018, 0), skinL)
		end
		for _, x in mx do
			local inV = vd and x > vd[1] and x < vd[3]
			for _, sz in cut(V.z0 + 0.04, V.z1 - 0.04, if inV then vd[2] else nil, if inV then vd[4] else nil) do
				K:box("CeilingTBar", V3(0.18, 0.08, sz[2] - sz[1]), CF(x, H - 0.05, (sz[1] + sz[2]) / 2), barL)
			end
		end
		for _, z in mz do
			local inV = vd and z > vd[2] and z < vd[4]
			for _, sx in cut(V.x0 + 0.04, V.x1 - 0.04, if inV then vd[1] else nil, if inV then vd[3] else nil) do
				K:box("CeilingTBar", V3(sx[2] - sx[1], 0.08, 0.18), CF((sx[1] + sx[2]) / 2, H - 0.05, z), barL)
			end
		end
	end)
	if vd then
		oo.avoid = oo.avoid or {}
		table.insert(oo.avoid, { vd[1] - 1, vd[2] - 1, vd[3] + 1, vd[4] + 1 })
	end
	-- 평판등 칸
	local every = oo.every or 3
	local cells = {}
	for i = 1, #xs - 1 do
		for j = 1, #zs - 1 do
			if (i % every == 2 % every) and (j % every == 2 % every) then
				local x0, x1, z0, z1 = xs[i], xs[i + 1], zs[j], zs[j + 1]
				if x1 - x0 > 1.6 and x1 - x0 < 2.6 and z1 - z0 > 1.6 and z1 - z0 < 2.6 then
					table.insert(cells, { (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0 })
				end
			end
		end
	end
	local placed = {}
	for _, c in cells do
		local x, z = c[1], c[2]
		local skip = false
		for _, a in oo.avoid or {} do
			if x > a[1] and x < a[3] and z > a[2] and z < a[4] then
				skip = true
			end
		end
		if not skip and x > V.x0 + 1 and x < V.x1 - 1 and z > V.z0 + 1 and z < V.z1 - 1 and ceilOK(K, x, z, 0.9) then
			table.insert(placed, c)
			Common.useCeil(K, x, z)
		end
	end
	-- 불빛 고르기: 고르게 퍼지게 (멀리 떨어진 순)
	local nL = math.min(oo.lights or 4, math.max(0, (V.maxLights or 8) - #K.lights - (oo.reserve or 2)))
	local lit = {}
	if nL > 0 and #placed > 0 then
		local chosen = {}
		local cx, cz = 0, 0
		table.insert(chosen, placed[math.max(1, math.floor(#placed / 2))])
		while #chosen < math.min(nL, #placed) do
			local best, bd = nil, -1
			for _, c in placed do
				local dmin = math.huge
				for _, q in chosen do
					dmin = math.min(dmin, (c[1] - q[1]) ^ 2 + (c[2] - q[2]) ^ 2)
				end
				if dmin > bd then
					best, bd = c, dmin
				end
			end
			if not best or bd <= 0 then
				break
			end
			table.insert(chosen, best)
		end
		for _, q in chosen do
			lit[q] = true
		end
		_ = cx + cz
	end
	local glow = col(C3(244, 248, 255), M.Neon)
	K:free(function()
		for _, c in placed do
			local x, z, w, d = c[1], c[2], c[3] - 0.1, c[4] - 0.1
			K:box("PanelLightFrame", V3(w, 0.06, d), CF(x, H - 0.06, z), lk(238, 238, 236))
			local p = K:box("PanelLight", V3(w - 0.22, 0.03, d - 0.22), CF(x, H - 0.1, z), glow)
			if lit[c] then
				K:light(p, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = oo.range or 18, Brightness = oo.bright or 0.85, Angle = 120, Color = C3(240, 246, 255) })
			end
		end
	end)
	note(K, string.format("ceiling panels=%d lit=%d grid=%dx%d", #placed, #K.lights, #gx, #gz))
	return placed
end

-- 바닥 오버레이: o.look, o.tile (줄눈 간격, 0 = 없음), o.grout, o.plank (마루형: 줄 방향 x, 이음 엇갈림)
local function floorKit(K: any, V: any, o: any?)
	local oo: any = o or {}
	local L = oo.look or lk(214, 210, 202, M.SmoothPlastic)
	local grout = oo.grout or lk(176, 172, 166)
	local t = oo.tile or 2.04
	K:free(function()
		K:box("FloorSkin", V3(V.W - 0.02, 0.02, V.D - 0.02), CF(0, 0.012, 0), L)
		if t > 0 then
			if oo.plank then
				-- 데코타일 마루: 폭 t 줄 (z 방향 줄눈) + 길이 이음 (x 방향, 줄마다 엇갈림 2개만)
				local z = V.z0 + t
				local row = 0
				while z < V.z1 - 0.1 do
					K:box("FloorGrout", V3(V.W - 0.04, 0.022, 0.03), CF(0, 0.014, z), grout)
					z += t
					row += 1
				end
			else
				local x = V.x0 + ((oo.ox or 0) % t)
				if x <= V.x0 + 0.05 then
					x += t
				end
				while x < V.x1 - 0.05 do
					K:box("FloorGrout", V3(0.035, 0.022, V.D - 0.04), CF(x, 0.014, 0), grout)
					x += t
				end
				local z = V.z0 + ((oo.oz or 0) % t)
				if z <= V.z0 + 0.05 then
					z += t
				end
				while z < V.z1 - 0.05 do
					K:box("FloorGrout", V3(V.W - 0.04, 0.022, 0.035), CF(0, 0.014, z), grout)
					z += t
				end
			end
		end
	end)
end

-- 걸레받이 (벽 이름 목록)
local function baseKit(K: any, V: any, walls: { string }, look: any?)
	for _, w in walls do
		K:free(function()
			Props.baseboard(K, w, look or lk(120, 128, 132, M.SmoothPlastic), 0.45)
		end)
	end
end

-- 안전 손잡이 (벽에 붙은 둥근 레일 + 까치발): wall, u0..u1, 높이 y
local function handrail(K: any, wn: string, u0: number, u1: number, y: number?, o: any?)
	local V = K.V
	local yy = y or 2.9
	local oo: any = o or {}
	local railL = oo.look or lk(214, 200, 168, M.Wood)
	local brL = oo.bracket or LK.alu
	local len = u1 - u0
	if len < 1.5 then
		return
	end
	K:free(function()
		local a = V:wall(wn, u0, yy, 0.42)
		local b = V:wall(wn, u1, yy, 0.42)
		K:seg("Handrail", a.Position, b.Position, 0.32, railL)
		-- 끝 (벽으로 꺾임)
		for _, e in { { u0, 1 }, { u1, -1 } } do
			local p = V:wall(wn, e[1], yy, 0.42).Position
			local q = V:wall(wn, e[1], yy, 0.05).Position
			K:seg("HandrailEnd", p, q, 0.3, railL)
			K:ball("HandrailEndCap", 0.32, CF(p), railL)
		end
		local n = math.max(1, math.floor(len / 4.2))
		for i = 0, n do
			local u = u0 + 0.6 + (len - 1.2) * i / n
			local w = V:wall(wn, u, yy - 0.28, 0)
			K:plate("HandrailBracketPlate", 0.32, 0.32, 0.04, w, brL)
			K:seg("HandrailBracket", (w * CF(0, 0, 0.04)).Position, (w * CF(0, 0.12, 0.3)).Position, 0.08, brL)
		end
	end)
end

-- 벽 구간마다 손잡이 (spans 사용)
local function handrailSpans(K: any, wn: string, y: number?, minLen: number?)
	local V = K.V
	local yy = y or 2.9
	for _, s in V:spans(wn, yy - 0.4, yy + 0.4, 0.8) do
		if s[2] - s[1] >= (minLen or 3) then
			handrail(K, wn, s[1] + 0.2, s[2] - 0.2, yy)
		end
	end
end

-- 글자 · 표지 ----------------------------------------------------------------------------------------------------

-- 포스터 (아크릴 액자: 판 + 위 띠 제목 + 본문). th = 띠 비율
local function poster(K: any, dcf: CFrame, w: number, h: number, title: string, body: string?, bg: Color3, fg: Color3, band: Color3, bandFg: Color3, th: number?)
	local frameL = lk(210, 212, 214, M.Metal)
	K:plate("PosterFrame", w + 0.12, h + 0.12, 0.04, dcf, frameL)
	K:plate("Poster", w, h, 0.05, dcf, col(bg))
	local bh = h * (th or 0.26)
	K:plate("PosterBand", w, bh, 0.055, dcf * CF(0, h / 2 - bh / 2, 0), col(band))
	tx(K, "PosterTitle", w * 0.9, bh * 0.78, dcf * CF(0, h / 2 - bh / 2, 0.056), title, bandFg, nil, { font = FONT_K })
	if body then
		tx(K, "PosterBody", w * 0.86, (h - bh) * 0.86, dcf * CF(0, -bh / 2, 0.052), body, fg, nil, { font = FONT_M })
	end
end

-- 방 / 구역 이름판 (청록 아크릴 + 흰 글자 + 작은 영문)
local function roomSign(K: any, dcf: CFrame, w: number, h: number, ko: string, en: string?, o: any?)
	local oo: any = o or {}
	local bg = oo.bg or TEAL
	K:plate("RoomSignBack", w, h, 0.08, dcf, col(bg))
	K:plate("RoomSignEdge", w, 0.06, 0.09, dcf * CF(0, -h / 2 + 0.03, 0), col(darker(bg, 0.25)))
	if en then
		tx(K, "RoomSignKo", w * 0.9, h * 0.56, dcf * CF(0, h * 0.14, 0.085), ko, oo.fg or WHITE, nil, { font = FONT_K, glow = oo.glow })
		tx(K, "RoomSignEn", w * 0.8, h * 0.24, dcf * CF(0, -h * 0.28, 0.085), en, oo.fg2 or MINT, nil, { font = FONT_M, glow = oo.glow })
	else
		tx(K, "RoomSignKo", w * 0.9, h * 0.72, dcf * CF(0, 0, 0.085), ko, oo.fg or WHITE, nil, { font = FONT_K, glow = oo.glow })
	end
end

-- 천장 매달린 양면 안내판 (x, z, 바닥 위 아래 끝 y, 방향 yaw)
local function hangSign(K: any, x: number, z: number, w: number, h: number, yBot: number, yaw: number, front: string, back: string?, o: any?)
	local oo: any = o or {}
	local V = K.V
	local c = CF(x, yBot + h / 2, z) * ANG(0, yaw, 0)
	K:free(function()
		for _, sx in { -1, 1 } do
			K:seg("HangSignWire", (c * CF(sx * (w / 2 - 0.3), h / 2, 0)).Position, Vector3.new((c * CF(sx * (w / 2 - 0.3), 0, 0)).X, V.H, (c * CF(sx * (w / 2 - 0.3), 0, 0)).Z), 0.04, LK.alu)
		end
		K:box("HangSign", V3(w, h, 0.14), c, col(oo.bg or WHITE))
		K:box("HangSignBand", V3(w, 0.1, 0.16), c * CF(0, h / 2 - 0.05, 0), col(oo.band or TEAL))
		tx(K, "HangSignFront", w * 0.92, h * 0.74, c * CF(0, -0.03, 0.07), front, oo.fg or TEAL_D, nil, { font = FONT_K, free = true })
		tx(K, "HangSignBack", w * 0.92, h * 0.74, c * ANG(0, PI, 0) * CF(0, -0.03, 0.07), back or front, oo.fg or TEAL_D, nil, { font = FONT_K, free = true })
	end)
end

-- 비상구 유도등 (녹색 + 흰 사람 + 화살표), dcf 벽 표면
local function exitSign(K: any, dcf: CFrame, w: number?, arrow: string?)
	local ww = w or 2.2
	K:plate("ExitSignBox", ww, ww * 0.42, 0.18, dcf, lk(236, 236, 232))
	local p = K:plate("ExitSignLamp", ww - 0.14, ww * 0.42 - 0.14, 0.03, dcf * CF(0, 0, 0.18), col(GREEN_EXIT, M.Neon))
	tx(K, "ExitSignText", ww - 0.3, ww * 0.3, dcf * CF(0, 0, 0.215), "비상구  " .. (arrow or "🏃→"), WHITE, nil, { glow = 1.4, font = FONT_K })
	return p
end

-- 옥내소화전함 (빨강 함 + 표시등 + 발신기)
local function hydrantBox(K: any, dcf: CFrame)
	K:plate("HydrantBox", 2.6, 4.2, 0.5, dcf, lk(196, 30, 34))
	K:plate("HydrantDoor", 2.4, 2.6, 0.04, dcf * CF(0, -0.6, 0.5), lk(210, 40, 42))
	K:plate("HydrantWindow", 1.4, 0.9, 0.02, dcf * CF(0, -0.2, 0.54), { c = C3(230, 236, 238), m = M.Glass, t = 0.4 })
	tx(K, "HydrantLabel", 1.9, 0.5, dcf * CF(0, -1.45, 0.545), "소화전", WHITE, nil, { font = FONT_K })
	K:plate("HydrantTop", 2.4, 1.2, 0.04, dcf * CF(0, 1.35, 0.5), lk(180, 26, 30))
	K:disc("HydrantLamp", 0.42, 0.1, dcf * CF(-0.6, 1.4, 0.58) * ANG(PI / 2, 0, 0), Look.ledRed)
	K:disc("HydrantBell", 0.5, 0.08, dcf * CF(0.55, 1.4, 0.56) * ANG(PI / 2, 0, 0), lk(220, 200, 40, M.Metal))
	tx(K, "HydrantSub", 2.2, 0.3, dcf * CF(0, 0.85, 0.545), "발신기 · 표시등", WHITE, nil, { font = FONT_M })
	K:seg("HydrantHandle", (dcf * CF(0.95, -0.9, 0.56)).Position, (dcf * CF(0.95, -0.3, 0.56)).Position, 0.08, LK.chrome)
end

-- AED 함 (흰 함 + 초록 띠 + 하트)
local function aedBox(K: any, dcf: CFrame)
	K:plate("AEDBox", 1.9, 2.4, 0.5, dcf, lk(244, 244, 240))
	K:plate("AEDBand", 1.9, 0.5, 0.52, dcf * CF(0, 0.85, 0), col(GREEN_EXIT))
	tx(K, "AEDTitle", 1.7, 0.4, dcf * CF(0, 0.85, 0.525), "AED 자동심장충격기", WHITE, nil, { font = FONT_K })
	K:plate("AEDWindow", 1.5, 1.2, 0.03, dcf * CF(0, -0.25, 0.5), { c = C3(220, 236, 236), m = M.Glass, t = 0.35 })
	K:box("AEDUnit", V3(1.1, 0.9, 0.35), dcf * CF(0, -0.3, 0.25), lk(230, 200, 30, M.Plastic))
	tx(K, "AEDHeart", 0.6, 0.5, dcf * CF(0, -0.25, 0.43), "♥⚡", C3(220, 30, 40), nil, {})
	tx(K, "AEDNote", 1.7, 0.3, dcf * CF(0, -1.05, 0.505), "응급 시 문을 열고 사용 · 119 신고", INK, nil, { font = FONT_M })
end

-- 손 소독제 벽걸이 디스펜서
local function sanitizerWall(K: any, dcf: CFrame): BasePart
	local b = K:plate("SanitizerUnit", 0.7, 1.1, 0.42, dcf, lk(246, 246, 244, M.Plastic))
	K:plate("SanitizerWindow", 0.36, 0.3, 0.02, dcf * CF(0, 0.12, 0.42), { c = C3(150, 210, 230), m = M.Glass, t = 0.3 })
	K:plate("SanitizerPush", 0.5, 0.26, 0.06, dcf * CF(0, -0.28, 0.42), lk(0, 128, 118, M.Plastic))
	K:plate("SanitizerDrip", 0.6, 0.06, 0.3, dcf * CF(0, -0.58, 0.05), lk(200, 204, 206, M.Plastic))
	tx(K, "SanitizerLabel", 0.62, 0.18, dcf * CF(0, 0.42, 0.425), "손 소독제", TEAL_D, nil, { font = FONT_B })
	return b
end

-- 종이 타월 디스펜서
local function towelDispenser(K: any, dcf: CFrame)
	K:plate("TowelDispenser", 1.2, 1.4, 0.45, dcf, lk(240, 240, 238, M.Plastic))
	K:plate("TowelWindow", 0.8, 0.2, 0.02, dcf * CF(0, 0.3, 0.45), { c = C3(180, 200, 210), m = M.Glass, t = 0.5 })
	K:plate("TowelSheet", 0.8, 0.35, 0.02, dcf * CF(0, -0.75, 0.25), Look.paper)
	tx(K, "TowelLabel", 0.9, 0.18, dcf * CF(0, 0.05, 0.455), "PAPER TOWEL", GREY_T, nil, { font = FONT_M })
end

-- 비누 (물비누) 디스펜서
local function soapDispenser(K: any, dcf: CFrame)
	K:plate("SoapDispenser", 0.55, 0.85, 0.35, dcf, lk(244, 244, 242, M.Plastic))
	K:plate("SoapWindow", 0.3, 0.3, 0.02, dcf * CF(0, 0.08, 0.35), { c = C3(240, 200, 120), m = M.Glass, t = 0.3 })
	K:plate("SoapPush", 0.4, 0.18, 0.05, dcf * CF(0, -0.28, 0.35), lk(120, 128, 132, M.Plastic))
end

-- 일회용 장갑 상자 (벽 홀더)
local function gloveHolder(K: any, dcf: CFrame, n: number?)
	local k = n or 3
	K:plate("GloveRack", 0.9 * k + 0.2, 0.7, 0.06, dcf, LK.alu)
	local cols = { C3(90, 140, 220), C3(140, 110, 200), C3(80, 180, 200) }
	for i = 1, k do
		local x = -(0.9 * k) / 2 + 0.45 + (i - 1) * 0.9
		K:plate("GloveBox", 0.82, 0.5, 0.48, dcf * CF(x, 0.02, 0.06), lk(246, 246, 244))
		K:plate("GloveBand", 0.82, 0.14, 0.49, dcf * CF(x, 0.2, 0.06), col(cols[(i - 1) % 3 + 1]))
		K:plate("GloveTuft", 0.3, 0.1, 0.06, dcf * CF(x, 0.0, 0.54), col(cols[(i - 1) % 3 + 1]:Lerp(WHITE, 0.4)))
	end
	tx(K, "GloveLabel", 0.9 * k, 0.12, dcf * CF(0, -0.29, 0.07), "S          M          L", INK, nil, { font = FONT_M })
end

-- 벽시계는 Common, 화면 ---------------------------------------------------------------------------------------

-- 벽걸이 모니터 / TV (dcf 중심). 반환 화면 파트, 글자
local function wallScreen(K: any, dcf: CFrame, w: number, h: number, text: string, bg: Color3, fg: Color3, o: any?): (BasePart, TextLabel)
	local oo: any = o or {}
	K:plate("ScreenMount", w * 0.3, h * 0.35, 0.12, dcf, LK.black)
	K:plate("ScreenBezel", w + 0.14, h + 0.14, 0.14, dcf * CF(0, 0, 0.12), lk(18, 18, 20))
	local p, t = tx(K, oo.name or "InfoScreen", w, h, dcf * CF(0, 0, 0.262), text, fg, bg, { glow = oo.glow or 1.15, font = oo.font or FONT_B, free = oo.free })
	K:plate("ScreenLogo", 0.3, 0.05, 0.01, dcf * CF(0, -h / 2 - 0.04, 0.262), lk(140, 140, 144, M.Metal))
	return p, t
end

-- 책상 모니터 (pcf = 책상 위, +Z = 보는 사람). 반환 화면 파트, 글자
local function deskMonitor(K: any, pcf: CFrame, w: number, text: string, bg: Color3?, fg: Color3?, o: any?): (BasePart, TextLabel)
	local oo: any = o or {}
	local h = w * 0.6
	local lift = oo.lift or 0.55
	K:box("MonitorFoot", V3(w * 0.42, 0.05, 0.62), pcf * CF(0, 0.025, -0.1), lk(36, 36, 40, M.Metal))
	K:box("MonitorNeck", V3(0.2, lift + h * 0.3, 0.12), pcf * CF(0, (lift + h * 0.3) / 2, -0.28), lk(40, 40, 44, M.Metal))
	local c = pcf * CF(0, lift + h / 2, -0.16) * ANG(math.rad(-4), 0, 0)
	K:box("MonitorPanel", V3(w, h, 0.09), c, lk(22, 22, 24))
	K:box("MonitorBack", V3(w * 0.6, h * 0.5, 0.12), c * CF(0, -h * 0.05, -0.09), lk(30, 30, 34))
	local p, t = tx(K, "MonitorScreen", w - 0.1, h - 0.1, c * CF(0, 0.02, 0.046), text, fg or C3(220, 236, 240), bg or C3(24, 52, 70), { glow = oo.glow or 1.0, font = oo.font or FONT_M, align = oo.align })
	K:box("MonitorChin", V3(w - 0.1, 0.05, 0.01), c * CF(0, -h / 2 + 0.04, 0.046), lk(40, 40, 44))
	return p, t
end

local function keyboard(K: any, pcf: CFrame, w: number?)
	local ww = w or 1.7
	K:box("Keyboard", V3(ww, 0.06, 0.6), pcf * CF(0, 0.03, 0), lk(30, 30, 32))
	K:box("KeyboardKeys", V3(ww - 0.12, 0.02, 0.48), pcf * CF(0, 0.07, 0), lk(54, 54, 58))
	K:box("KeyboardSpace", V3(ww * 0.36, 0.025, 0.08), pcf * CF(0, 0.08, 0.17), lk(70, 70, 74))
	K:ell("Mouse", V3(0.22, 0.1, 0.36), pcf * CF(ww / 2 + 0.35, 0.05, 0.05), lk(32, 32, 34))
	K:box("MousePad", V3(0.8, 0.01, 0.7), pcf * CF(ww / 2 + 0.35, 0.005, 0.05), lk(46, 60, 72, M.Fabric))
end

local function deskPhone(K: any, pcf: CFrame)
	K:wedge("PhoneBase", V3(0.9, 0.22, 0.75), pcf * CF(0, 0.11, 0) * ANG(0, PI, 0), lk(40, 40, 44))
	K:box("PhoneHandset", V3(0.22, 0.12, 0.75), pcf * CF(-0.28, 0.26, 0), lk(34, 34, 38))
	K:box("PhoneLCD", V3(0.36, 0.01, 0.16), pcf * CF(0.16, 0.2, -0.12) * ANG(math.rad(-16), 0, 0), col(C3(140, 190, 200), M.Neon))
	for i = 0, 2 do
		for j = 0, 2 do
			K:box("PhoneKey", V3(0.07, 0.02, 0.06), pcf * CF(0.07 + i * 0.1, 0.17 + j * 0.02, 0.05 + j * 0.09) * ANG(math.rad(-16), 0, 0), lk(90, 90, 96))
		end
	end
end

local function penCup(K: any, pcf: CFrame)
	K:vcyl("PenCup", 0.42, 0.3, pcf * CF(0, 0.21, 0), lk(60, 64, 70, M.Metal))
	local cs = { C3(30, 60, 160), C3(200, 30, 40), C3(20, 20, 20) }
	for i = 1, 3 do
		local a = i * 2.1
		K:seg("Pen", (pcf * CF(math.cos(a) * 0.06, 0.3, math.sin(a) * 0.06)).Position, (pcf * CF(math.cos(a) * 0.11, 0.66, math.sin(a) * 0.11)).Position, 0.045, col(cs[i]))
	end
end

-- 서류 트레이 / 바인더 줄
local function binderRow(K: any, pcf: CFrame, n: number, cols: { Color3 }, labels: { string }?)
	for i = 1, n do
		local x = -(n * 0.32) / 2 + 0.16 + (i - 1) * 0.32
		local c = cols[(i - 1) % #cols + 1]
		K:box("Binder", V3(0.28, 1.2, 1.0), pcf * CF(x, 0.6, 0), col(c, M.SmoothPlastic))
		if labels and labels[i] then
			tx(K, "BinderLabel", 0.2, 0.5, pcf * CF(x, 0.7, 0.505), labels[i], INK, WHITE, { font = FONT_M, d = 0.01 })
		end
	end
end

-- 가구 ---------------------------------------------------------------------------------------------------------

-- 사무용 하이백 의자 (pcf 바닥, +Z = 앉은 사람이 보는 쪽), top = 좌판 윗면
local function officeChair(K: any, pcf: CFrame, top: number?, o: any?)
	local oo: any = o or {}
	local tp = top or 1.9
	local seatL = oo.seat or lk(36, 40, 46, M.Fabric)
	local meshL = oo.mesh or lk(40, 44, 50, M.Fabric)
	local frameL = oo.frame or lk(40, 40, 44, M.Plastic)
	local base = pcf
	for i = 0, 4 do
		local a = i * 2 * PI / 5 + 0.3
		local e = base * CF(math.cos(a) * 1.0, 0.18, math.sin(a) * 1.0)
		K:seg("ChairStar", (base * CF(0, 0.26, 0)).Position, e.Position, 0.14, frameL)
		K:ball("ChairCaster", 0.24, base * CF(math.cos(a) * 1.0, 0.12, math.sin(a) * 1.0), LK.black)
	end
	K:vcyl("ChairHub", 0.18, 0.36, base * CF(0, 0.28, 0), frameL)
	K:vcyl("ChairGas", tp - 0.75, 0.16, base * CF(0, 0.3 + (tp - 0.75) / 2, 0), LK.chrome)
	K:vcyl("ChairGasCover", 0.4, 0.22, base * CF(0, 0.55, 0), frameL)
	K:box("ChairMech", V3(0.9, 0.16, 0.8), base * CF(0, tp - 0.4, 0), frameL)
	K:slab("ChairSeat", 1.75, 1.65, 0.3, 0.3, base * CF(0, tp - 0.15, 0.05), seatL)
	local bz = -0.78
	local back = base * CF(0, tp + 0.15, bz) * ANG(math.rad(-10), 0, 0)
	K:seg("ChairSpine", (base * CF(0, tp - 0.35, -0.3)).Position, (back * CF(0, 0.4, -0.08)).Position, 0.16, frameL)
	local bh = oo.backH or 2.3
	K:panel("ChairBackFrame", 1.7, bh, 0.12, 0.35, back * CF(0, bh / 2 + 0.25, -0.1), frameL)
	K:panel("ChairBackMesh", 1.5, bh - 0.2, 0.06, 0.3, back * CF(0, bh / 2 + 0.25, 0.02), meshL)
	K:box("ChairLumbar", V3(1.3, 0.28, 0.08), back * CF(0, 0.8, 0.08), frameL)
	if oo.arms ~= false then
		for _, sx in { -1, 1 } do
			K:seg("ChairArmPost", (base * CF(sx * 0.82, tp - 0.3, -0.1)).Position, (base * CF(sx * 0.82, tp + 0.6, -0.05)).Position, 0.12, frameL)
			K:box("ChairArmPad", V3(0.26, 0.1, 0.95), base * CF(sx * 0.82, tp + 0.65, 0.05), lk(30, 30, 32, M.Rubber))
		end
	end
end

-- 환자용 원형 회전 스툴 (등받이 없음, pcf 바닥)
local function rollStool(K: any, pcf: CFrame, top: number?, seatL: any?)
	local tp = top or 1.8
	for i = 0, 4 do
		local a = i * 2 * PI / 5
		K:seg("StoolStar", (pcf * CF(0, 0.24, 0)).Position, (pcf * CF(math.cos(a) * 0.8, 0.16, math.sin(a) * 0.8)).Position, 0.1, LK.chrome)
		K:ball("StoolCaster", 0.2, pcf * CF(math.cos(a) * 0.8, 0.1, math.sin(a) * 0.8), LK.black)
	end
	K:vcyl("StoolGas", tp - 0.5, 0.14, pcf * CF(0, 0.25 + (tp - 0.5) / 2, 0), LK.chrome)
	K:disc("StoolSeat", 1.3, 0.28, pcf * CF(0, tp - 0.14, 0), seatL or LK.vinylTeal)
	K:disc("StoolRim", 1.34, 0.06, pcf * CF(0, tp - 0.3, 0), LK.black)
end

-- 보호자 · 대기용 패드 의자 (팔걸이, pcf 바닥, top 좌판)
local function armChair(K: any, pcf: CFrame, top: number?, seatL: any?, frameL: any?)
	local tp = top or 1.9
	local fl = frameL or LK.alu
	local sl = seatL or LK.vinylTeal
	for _, sx in { -1, 1 } do
		K:bar("ChairSled", pcf * V3(sx * 0.85, 0.05, -0.7), pcf * V3(sx * 0.85, 0.05, 0.75), 0.1, 0.08, fl)
		K:seg("ChairFrontLeg", pcf * V3(sx * 0.85, 0.05, 0.72), pcf * V3(sx * 0.85, tp + 0.55, 0.62), 0.1, fl)
		K:seg("ChairRearLeg", pcf * V3(sx * 0.85, 0.05, -0.68), pcf * V3(sx * 0.85, tp + 1.9, -0.82), 0.1, fl)
		K:box("ChairArm", V3(0.24, 0.1, 1.3), pcf * CF(sx * 0.85, tp + 0.6, 0.0), lk(40, 40, 44, M.Plastic))
	end
	K:slab("ChairSeat", 1.6, 1.5, 0.3, 0.2, pcf * CF(0, tp - 0.15, 0.02), sl)
	K:panel("ChairBack", 1.55, 1.6, 0.26, 0.22, pcf * CF(0, tp + 1.05, -0.74) * ANG(math.rad(-8), 0, 0), sl)
end

-- 대기실 연결 의자 (빔 체어) 다시 입히기: bench = { seat recs } (같은 모델)
local function beamChairs(K: any, seats: { any }, o: any?)
	local oo: any = o or {}
	if #seats == 0 then
		return
	end
	local seatL = oo.seat or LK.vinylTeal
	local frameL = oo.frame or lk(150, 154, 158, M.Metal)
	-- 정렬 + 방향 (등받이 반대쪽)
	local s1 = seats[1]
	local back = sibling(K.V, s1.seat, "BenchBack") or sibling(K.V, s1.seat, "ChairBack")
	local face = s1.face
	if back then
		local d = Vector3.new(s1.seat.c.X - back.c.X, 0, s1.seat.c.Z - back.c.Z)
		if d.Magnitude > 0.05 then
			face = d.Unit
		end
	end
	if math.abs(face.X) > math.abs(face.Z) then
		face = Vector3.new(math.sign(face.X), 0, 0)
	else
		face = Vector3.new(0, 0, math.sign(face.Z))
	end
	local right = Vector3.yAxis:Cross(face) -- pcf +X (up x face)
	table.sort(seats, function(a, b)
		return a.seat.c:Dot(right) < b.seat.c:Dot(right)
	end)
	local top = s1.top
	local first, last = seats[1].seat.c, seats[#seats].seat.c
	local mid = (first + last) / 2
	local len = (last - first).Magnitude + 2.0
	local base = CFrame.fromMatrix(Vector3.new(mid.X, 0, mid.Z), right, Vector3.yAxis, face)
	K:free(function()
		-- 빔 + T 다리 2
		K:box("BeamRail", V3(len, 0.22, 0.4), base * CF(0, top - 0.62, -0.1), frameL)
		for _, f in { -0.36, 0.36 } do
			local x = f * len
			K:box("BeamLeg", V3(0.24, top - 0.7, 0.28), base * CF(x, (top - 0.7) / 2, -0.1), frameL)
			K:box("BeamFoot", V3(0.3, 0.08, 1.9), base * CF(x, 0.04, -0.05), frameL)
			for _, z in { -0.95, 0.85 } do
				K:disc("BeamGlide", 0.24, 0.05, base * CF(x, 0.025, z), LK.rubber)
			end
		end
		for i, s in seats do
			local c = s.seat.c
			local pc = CFrame.fromMatrix(Vector3.new(c.X, 0, c.Z), right, Vector3.yAxis, face)
			local w = math.min(1.85, math.max(s.seat.size.X, s.seat.size.Z))
			-- 좌판 (모서리 둥근 쿠션) + 셸
			K:box("BeamSeatShell", V3(w - 0.06, 0.12, 1.7), pc * CF(0, top - 0.33, 0.02), lk(60, 64, 70, M.Plastic))
			K:slab("BeamSeat", w - 0.08, 1.72, 0.26, 0.22, pc * CF(0, top - 0.13, 0.05), seatL)
			K:box("BeamSeatArm", V3(0.16, top - 0.55, 0.2), pc * CF(0, (top - 0.55) / 2 + 0.55, -0.6), frameL)
			-- 등받이 (살짝 젖힘)
			local bc = pc * CF(0, top + 0.95, -0.86) * ANG(math.rad(-9), 0, 0)
			K:box("BeamBackShell", V3(w - 0.1, 1.55, 0.12), bc * CF(0, 0, -0.08), lk(60, 64, 70, M.Plastic))
			K:panel("BeamBack", w - 0.12, 1.5, 0.2, 0.22, bc * CF(0, 0, -0.02), seatL)
			K:seg("BeamBackPost", (pc * CF(0, top - 0.5, -0.5)).Position, (bc * CF(0, -0.55, -0.16)).Position, 0.14, frameL)
			-- 팔걸이 (좌석 사이 + 양 끝)
			local sides = { 1 }
			if i == 1 then
				sides = { -1, 1 }
			end
			for _, sx in sides do
				local ax = sx * (w / 2 + 0.05)
				K:box("BeamArmPost", V3(0.12, 0.62, 0.12), pc * CF(ax, top + 0.18, -0.15), frameL)
				K:box("BeamArmPad", V3(0.2, 0.09, 1.05), pc * CF(ax, top + 0.52, -0.05), lk(34, 34, 36, M.Plastic))
			end
			for _, r in s.parts do
				hideRec(K, r)
			end
			local b = sibling(K.V, s.seat, "BenchBack")
			if b then
				-- 같은 자리의 등받이만
				for _, q in siblings(K.V, s.seat) do
					if q.name == "BenchBack" and (Vector3.new(q.c.X - c.X, 0, q.c.Z - c.Z)).Magnitude < 1.4 then
						hideRec(K, q)
					end
				end
			end
		end
		for _, q in siblings(K.V, s1.seat) do
			if q.name == "BenchBar" or q.name == "BenchLeg" then
				hideRec(K, q)
			end
		end
	end)
end

-- 의료 소품 -------------------------------------------------------------------------------------------------------

-- 링거 거치대 (5발 바퀴 + 기둥 + 4 고리 + 수액 백 + 점적통 + 줄). pcf 바닥. 반환: 점적통 위치 (애니메이션용)
local function ivPole(K: any, pcf: CFrame, o: any?): Vector3
	local oo: any = o or {}
	local h = oo.h or 6.4
	for i = 0, 4 do
		local a = i * 2 * PI / 5 + 0.2
		K:seg("IVLeg", (pcf * CF(0, 0.3, 0)).Position, (pcf * CF(math.cos(a) * 0.95, 0.2, math.sin(a) * 0.95)).Position, 0.1, LK.chrome)
		K:ball("IVCaster", 0.2, pcf * CF(math.cos(a) * 0.95, 0.1, math.sin(a) * 0.95), LK.black)
	end
	K:vcyl("IVHub", 0.2, 0.26, pcf * CF(0, 0.3, 0), LK.chrome)
	K:vcyl("IVPoleLow", h * 0.55, 0.12, pcf * CF(0, 0.3 + h * 0.275, 0), LK.chrome)
	K:vcyl("IVPoleHigh", h * 0.45, 0.09, pcf * CF(0, 0.3 + h * 0.55 + h * 0.225, 0), LK.chrome)
	K:vcyl("IVClamp", 0.18, 0.18, pcf * CF(0, 0.3 + h * 0.55, 0), lk(60, 60, 64, M.Plastic))
	local top = 0.3 + h
	for i = 0, 3 do
		local a = i * PI / 2 + PI / 4
		local e = pcf * CF(math.cos(a) * 0.42, top - 0.05, math.sin(a) * 0.42)
		K:seg("IVHook", (pcf * CF(0, top, 0)).Position, e.Position, 0.06, LK.chrome)
	end
	local drip = Vector3.zero
	if oo.bag ~= false then
		local bp = pcf * CF(0.42, top - 0.9, 0)
		K:box("IVBag", V3(0.55, 0.85, 0.14), bp, { c = C3(232, 240, 244), m = M.Glass, t = 0.35 })
		K:box("IVFluid", V3(0.5, 0.55 * (oo.level or 0.7), 0.1), bp * CF(0, -0.42 + 0.55 * (oo.level or 0.7) / 2 + 0.05, 0), { c = C3(250, 246, 214), m = M.Glass, t = 0.25 })
		K:plate("IVLabel", 0.34, 0.26, 0.01, bp * CF(0, 0.1, 0.07), Look.paper)
		local dc = bp * CF(0, -0.75, 0)
		K:vcyl("IVDripChamber", 0.35, 0.14, dc, { c = C3(236, 244, 246), m = M.Glass, t = 0.3 })
		drip = (K.cf * dc).Position
		local tubeEnd = oo.to or (pcf * V3(0.6, 2.2, -1.2))
		K:seg("IVTube", (dc * CF(0, -0.2, 0)).Position, pcf * V3(0.5, top - 3.0, 0), 0.04, { c = C3(230, 240, 240), m = M.Glass, t = 0.2 })
		K:seg("IVTube", pcf * V3(0.5, top - 3.0, 0), tubeEnd, 0.04, { c = C3(230, 240, 240), m = M.Glass, t = 0.2 })
		K:box("IVRoller", V3(0.12, 0.3, 0.1), pcf * CF(0.5, top - 2.2, 0), lk(120, 200, 220, M.Plastic))
	end
	if oo.pump then
		local pc = pcf * CF(0, 0.3 + h * 0.45, 0.2)
		K:box("InfusionPump", V3(0.9, 0.8, 0.5), pc, lk(240, 242, 240, M.Plastic))
		tx(K, "InfusionPumpLCD", 0.6, 0.3, pc * CF(0, 0.15, 0.255), "40 mL/h", C3(150, 255, 190), C3(10, 30, 20), { glow = 1.2, d = 0.01 })
	end
	return drip
end

-- 점적 애니메이션 (물방울 하나가 떨어짐)
local function dripAnim(K: any, chamber: Vector3)
	if chamber == Vector3.zero then
		return
	end
	local lp = K.cf:PointToObjectSpace(chamber)
	local d = K:ball("IVDrop", 0.05, CF(lp + Vector3.new(0, 0.1, 0)), { c = C3(250, 250, 230), m = M.Glass, t = 0.2 })
	local base = K.cf * CF(lp)
	Interact.anim(K, function(t)
		if d.Parent then
			local f = (t * 0.7) % 1
			d.CFrame = base * CF(0, 0.12 - f * 0.22, 0)
		end
	end)
end

-- 커튼 레일 + 커튼 ---------------------------------------------------------------------------------------------
-- pts = 로컬 xz 꺾은선 (Vector3, y 무시). 반환 ctl { set(f, tween), tab (손잡이 파트) }
local function curtainRun(K: any, pts: { Vector3 }, f0: number, o: any?): any
	local oo: any = o or {}
	local V = K.V
	local H = V.H
	local yTop = H - 0.18
	local yBot = oo.bottom or 0.9
	local meshH = oo.meshH or (if H > 9 then 1.6 else 1.1)
	local fab = oo.look or LK.curtain
	local meshL = LK.curtainMesh
	-- 레일
	K:free(function()
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			K:bar("CurtainTrack", Vector3.new(a.X, H - 0.05, a.Z), Vector3.new(b.X, H - 0.05, b.Z), 0.16, 0.1, LK.alu)
		end
		for _, p in pts do
			K:disc("CurtainTrackMount", 0.3, 0.04, CF(p.X, H - 0.02, p.Z), LK.alu)
		end
	end)
	-- 꺾은선 길이
	local segs, total = {}, 0
	for i = 1, #pts - 1 do
		local a = Vector3.new(pts[i].X, 0, pts[i].Z)
		local b = Vector3.new(pts[i + 1].X, 0, pts[i + 1].Z)
		local l = (b - a).Magnitude
		table.insert(segs, { a = a, b = b, l = l, s0 = total })
		total += l
	end
	local function pointAt(s: number): (Vector3, Vector3)
		for _, sg in segs do
			if s <= sg.s0 + sg.l + 1e-4 then
				local t = math.clamp((s - sg.s0) / sg.l, 0, 1)
				return sg.a:Lerp(sg.b, t), (sg.b - sg.a).Unit
			end
		end
		local sg = segs[#segs]
		return sg.b, (sg.b - sg.a).Unit
	end
	local N = math.clamp(math.ceil(total / 1.1), 3, 16)
	local fabH = yTop - meshH - yBot
	local function layout(f: number): { any }
		local out = {}
		local run = math.max(0.5, f * total)
		local seg = run / N
		local ang = math.rad(math.clamp(10 + (1 - f) * 55, 10, 62))
		for i = 1, N do
			local s = (i - 0.5) * seg
			local p, dir = pointAt(s)
			local yaw = math.atan2(dir.X, dir.Z) + PI / 2
			local z = (if i % 2 == 0 then 1 else -1) * ang
			local w = seg / math.cos(ang) + 0.04
			local base = CF(p.X, 0, p.Z) * ANG(0, yaw + z, 0)
			table.insert(out, { base * CF(0, yBot + fabH / 2, 0), V3(w, fabH, 0.05) })
			table.insert(out, { base * CF(0, yTop - meshH / 2, 0), V3(w, meshH, 0.03) })
		end
		return out
	end
	local parts = {}
	local lay = layout(f0)
	K:free(function()
		for i, l in lay do
			local isMesh = i % 2 == 0
			local p = K:box(if isMesh then "CurtainMesh" else "Curtain", l[2], l[1], if isMesh then meshL else fab)
			table.insert(parts, p)
		end
	end)
	local tab
	K:free(function()
		local p0, d0 = pointAt(0.05)
		tab = K:box("CurtainTab", V3(0.12, 0.5, 0.12), CF(p0.X, 3.8, p0.Z), lk(60, 70, 74, M.Plastic))
		_ = d0
	end)
	local ctl = { tab = tab, parts = parts }
	function ctl.set(f: number)
		local l2 = layout(f)
		for i, p in parts do
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = K.cf * l2[i][1], Size = l2[i][2] }):Play()
			end
		end
	end
	return ctl
end

-- 커튼 묶음 하나의 프롬프트 (여러 run 을 같이)
local function curtainToggle(K: any, runs: { any }, tabPart: BasePart?, object: string, f0: number)
	local tab = tabPart or (runs[1] and runs[1].tab)
	if not tab then
		return nil
	end
	return Interact.toggle(K, tab, {
		object = object,
		state = false,
		onText = "커튼 걷기",
		offText = "커튼 치기",
		sound = "rbxasset://sounds/clickfast.wav",
		on = function(closed: boolean)
			for _, r in runs do
				r.set(if closed then 1 else f0)
			end
		end,
	})
end

-- 침대 틀: BedSeat rec -> pcf (침대 가운데 바닥, +Z = 머리), 매트 길이, 폭
local function bedFrame(V: any, seat: any): (CFrame, number, number)
	local m = sibling(V, seat, "Mattress")
	local hb = sibling(V, seat, "Headboard") or sibling(V, seat, "Pillow")
	local c = if m then m.c else seat.c
	local alongZ = if m then m.size.Z >= m.size.X else seat.size.X >= seat.size.Z
	local len = if m then math.max(m.size.X, m.size.Z) else 7
	local wid = if m then math.min(m.size.X, m.size.Z) else 3.4
	local head: Vector3
	if alongZ then
		head = Vector3.new(0, 0, if hb and hb.c.Z < c.Z then -1 else 1)
	else
		head = Vector3.new(if hb and hb.c.X < c.X then -1 else 1, 0, 0)
	end
	return faceCF(Vector3.new(c.X, 0, c.Z), head), len, wid
end

-- 전동 병원침대 (맵 집 침대 위에 다시 지음, BedSeat 그대로). opts: rails ("both"|"head"), blanket color, chart text
local function hospitalBed(K: any, V: any, seat: any, o: any?): (CFrame, number, number)
	local oo: any = o or {}
	local bf, len, wid = bedFrame(V, seat)
	local L = math.max(6.6, len)
	local W = math.max(3.4, wid)
	local seatTop = seat.max.Y
	local mTop = seatTop - 0.07
	local ls = bf:PointToObjectSpace(seat.c)
	local keepZ0 = ls.Z - seat.size.Z / 2 - 0.35 -- (침대 틀에서) 좌석 keep 앞쪽 끝
	local keepZ1 = ls.Z + seat.size.Z / 2 + 0.35
	local frameL = lk(170, 176, 182, M.Metal)
	local absL = lk(236, 238, 238, M.Plastic)
	local absG = lk(150, 160, 168, M.Plastic)
	local accent = oo.accent or col(TEAL, M.Plastic)
	local zSplit = math.max(keepZ1 + 0.15, L / 2 - 2.5)
	K:free(function()
		-- 바퀴 · 받침
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local p = bf * CF(sx * (W / 2 - 0.45), 0, sz * (L / 2 - 0.55))
				K:box("BedCasterFork", V3(0.16, 0.36, 0.3), p * CF(0, 0.42, 0), LK.darkAlu)
				K:cyl("BedCaster", 0.16, 0.42, p * CF(0, 0.21, 0.04), LK.black)
				K:box("BedBumper", V3(0.4, 0.3, 0.4), bf * CF(sx * (W / 2 - 0.1), mTop - 0.75, sz * (L / 2 + 0.05)), absG)
			end
		end
		K:box("BedBase", V3(W - 0.9, 0.2, L - 1.2), bf * CF(0, 0.66, 0), frameL)
		for _, sz in { -1.9, 1.9 } do
			K:box("BedLift", V3(0.8, mTop - 1.35, 0.6), bf * CF(0, 0.76 + (mTop - 1.35) / 2, sz), absG)
		end
		K:box("BedMotor", V3(1.0, 0.45, 1.1), bf * CF(0, 1.0, 0), lk(90, 96, 102, M.Plastic))
		for _, sx in { -1, 1 } do
			K:box("BedSideTube", V3(0.16, 0.16, L - 0.4), bf * CF(sx * (W / 2 - 0.25), mTop - 0.62, 0), frameL)
		end
		K:box("BedDeck", V3(W - 0.2, 0.1, L - 0.3), bf * CF(0, mTop - 0.52, -0.05), frameL)
		-- 매트리스: 발 · 좌석 부분 평평, 머리 부분 25도 세움
		local flatLen = zSplit + L / 2 - 0.15
		local mt = 0.46
		K:box("BedMattress", V3(W - 0.05, mt, flatLen), bf * CF(0, mTop - mt / 2, -L / 2 + 0.15 + flatLen / 2), oo.mattress or LK.mattress)
		K:box("BedSheet", V3(W + 0.02, 0.03, flatLen - 0.1), bf * CF(0, mTop - 0.005, -L / 2 + 0.2 + flatLen / 2), LK.sheet)
		local headLen = L / 2 - 0.15 - zSplit
		local hinge = bf * CF(0, mTop - mt, zSplit)
		local hc = hinge * ANG(math.rad(oo.tilt or 22), 0, 0)
		K:box("BedMattressHead", V3(W - 0.05, mt, headLen), hc * CF(0, mt / 2, headLen / 2), oo.mattress or LK.mattress)
		K:box("BedSheetHead", V3(W + 0.02, 0.03, headLen - 0.05), hc * CF(0, mt + 0.01, headLen / 2), LK.sheet)
		K:ell("BedPillow", V3(W - 0.9, 0.42, 1.3), hc * CF(0, mt + 0.2, headLen - 0.85) * ANG(math.rad(-6), 0, 0), lk(250, 250, 250, M.Fabric))
		-- 접은 이불 (발치, 좌석 keep 밖)
		local bz1 = math.min(keepZ0, -L / 2 + 2.3)
		local bz0 = -L / 2 + 0.25
		if bz1 - bz0 > 0.6 then
			local bl = oo.blanket or lk(150, 196, 214, M.Fabric)
			K:box("BedBlanket", V3(W + 0.06, 0.16, bz1 - bz0), bf * CF(0, mTop + 0.07, (bz0 + bz1) / 2), bl)
			K:box("BedBlanketFold", V3(W + 0.08, 0.14, (bz1 - bz0) * 0.55), bf * CF(0, mTop + 0.21, bz1 - (bz1 - bz0) * 0.3), bl)
			K:box("BedBlanketStripe", V3(W + 0.1, 0.15, 0.12), bf * CF(0, mTop + 0.08, bz0 + 0.3), lk(240, 240, 236, M.Fabric))
		end
		-- 머리판 · 발판 (ABS)
		local hz = L / 2 + 0.1
		K:box("BedHeadPanel", V3(W + 0.2, 2.0, 0.22), bf * CF(0, mTop + 0.35, hz), absL)
		K:cyl("BedHeadTop", W + 0.2, 0.3, bf * CF(0, mTop + 1.35, hz), absL)
		K:box("BedHeadAccent", V3(W - 0.6, 0.16, 0.24), bf * CF(0, mTop + 0.85, hz), accent)
		K:box("BedHeadGrip", V3(W * 0.5, 0.26, 0.24), bf * CF(0, mTop + 1.1, hz), lk(120, 128, 134, M.Plastic))
		local fz = -L / 2 - 0.1
		K:box("BedFootPanel", V3(W + 0.2, 1.6, 0.22), bf * CF(0, mTop + 0.05, fz), absL)
		K:cyl("BedFootTop", W + 0.2, 0.28, bf * CF(0, mTop + 0.85, fz), absL)
		K:box("BedFootAccent", V3(W - 0.6, 0.14, 0.24), bf * CF(0, mTop + 0.45, fz), accent)
		K:box("BedBrake", V3(0.5, 0.1, 0.35), bf * CF(W / 2 - 0.7, 0.5, fz - 0.15), lk(220, 60, 40, M.Plastic))
		-- 발판 차트 · 환자 카드
		local cdcf = bf * CF(0, mTop - 0.2, fz - 0.12) * ANG(0, PI, 0)
		K:plate("BedChartBoard", 1.1, 0.75, 0.03, cdcf, lk(120, 90, 60, M.Wood))
		tx(K, "BedChartCard", 0.95, 0.6, cdcf * CF(0, -0.03, 0.035), oo.chart or "환자 정보\n낙상 주의 ●", INK, C3(250, 250, 246), { font = FONT_M, d = 0.01 })
		K:box("BedChartClip", V3(0.4, 0.08, 0.06), cdcf * CF(0, 0.36, 0.05), LK.chrome)
		-- 사이드레일: 머리 쪽 (세움), 발 쪽 (내림, 매트 아래)
		for _, sx in { -1, 1 } do
			local x = sx * (W / 2 + 0.12)
			local hz0, hz1 = zSplit - 0.4, L / 2 - 0.45
			local rc = bf * CF(x, mTop + 0.45, (hz0 + hz1) / 2)
			K:box("BedRailHead", V3(0.1, 0.8, hz1 - hz0), rc, absL)
			K:box("BedRailHeadSlot", V3(0.11, 0.26, (hz1 - hz0) * 0.55), rc * CF(0, 0.08, 0), lk(118, 126, 132, M.Plastic))
			K:box("BedRailHeadEdge", V3(0.12, 0.08, hz1 - hz0), rc * CF(0, 0.38, 0), accent)
			local fz0, fz1 = -L / 2 + 0.4, zSplit - 0.6
			if fz1 - fz0 > 1 then
				local fc = bf * CF(x, mTop - 0.62, (fz0 + fz1) / 2)
				K:box("BedRailFoot", V3(0.1, 0.62, fz1 - fz0), fc, absL)
				K:box("BedRailFootEdge", V3(0.12, 0.07, fz1 - fz0), fc * CF(0, 0.3, 0), absG)
			end
		end
		-- 리모컨 (머리 레일에 걸림)
		local side = oo.remoteSide or 1
		local rp = bf * CF(side * (W / 2 + 0.25), mTop + 0.2, zSplit + 0.4)
		K:box("BedRemote", V3(0.08, 0.55, 0.26), rp, lk(230, 232, 232, M.Plastic))
		K:box("BedRemoteKeys", V3(0.09, 0.32, 0.18), rp * CF(side * 0.01, -0.04, 0), lk(80, 150, 170, M.Plastic))
		K:seg("BedRemoteCord", (rp * CF(0, 0.27, 0)).Position, (bf * CF(side * (W / 2 + 0.15), mTop + 0.82, zSplit + 0.25)).Position, 0.03, LK.black)
	end)
	-- 맵 집 침대 숨김 (BedSeat 제외)
	for _, q in siblings(V, seat) do
		if q.part ~= seat.part and (q.name == "Headboard" or q.name == "Footboard" or q.name == "BedFrame" or q.name == "BedLeg" or q.name == "Mattress" or q.name == "Blanket" or q.name == "Pillow" or q.name == "SideRail" or q.name == "Curtain" or q.name == "CurtainRail") then
			hideRec(K, q)
		end
	end
	K:reserve((bf * CF(0, 0, 0)).Position - V3(W / 2 + 0.6, 0, L / 2 + 0.5), (bf * CF(0, 0, 0)).Position + V3(W / 2 + 0.6, 3.6, L / 2 + 0.5), "bed")
	return bf, L, W
end

-- 진찰대 (패드 + 등판 세움 + 일회용 롤 시트 + 서랍 받침 + 2단 발판). BedSeat 그대로
local function examCouch(K: any, V: any, seat: any, o: any?): (CFrame, number, number)
	local oo: any = o or {}
	local bf, len, wid = bedFrame(V, seat)
	local L = math.min(6.6, math.max(6.0, len - 0.4))
	local W = math.max(3.3, wid - 0.05)
	local seatTop = seat.max.Y
	local mTop = seatTop - 0.07
	local ls = bf:PointToObjectSpace(seat.c)
	local keepZ1 = ls.Z + seat.size.Z / 2 + 0.35
	local vinyl = oo.vinyl or lk(84, 160, 160, M.Leather)
	local cab = lk(242, 242, 238, M.SmoothPlastic)
	local zSplit = math.max(keepZ1 + 0.1, L / 2 - 2.1)
	K:free(function()
		K:box("CouchKick", V3(W - 0.7, 0.3, L - 1.1), bf * CF(0, 0.15, 0), lk(70, 74, 78))
		K:box("CouchCabinet", V3(W - 0.4, mTop - 0.85, L - 0.8), bf * CF(0, 0.3 + (mTop - 0.85) / 2, 0), cab)
		for i = 0, 2 do
			local z = -L / 2 + 0.4 + 0.2 + (L - 0.8) * (i + 0.5) / 3 - 0.2
			for _, sx in { -1, 1 } do
				local d = bf * CF(sx * (W / 2 - 0.2 + 0.01), 0.3 + (mTop - 0.85) * 0.62, z) * ANG(0, sx * PI / 2, 0)
				K:plate("CouchDrawer", (L - 1.0) / 3 - 0.12, (mTop - 0.85) * 0.42, 0.03, d, lk(232, 234, 232))
				K:plate("CouchDrawerPull", 0.6, 0.08, 0.06, d * CF(0, 0.12, 0.03), LK.chrome)
			end
		end
		K:box("CouchFrame", V3(W, 0.12, L), bf * CF(0, mTop - 0.49, 0), lk(196, 200, 204, M.Metal))
		local flat = zSplit + L / 2
		K:slab("CouchPad", W, flat, 0.42, 0.18, bf * CF(0, mTop - 0.21, -L / 2 + flat / 2), vinyl)
		local hl = L / 2 - zSplit
		local hc = bf * CF(0, mTop - 0.42, zSplit) * ANG(math.rad(oo.tilt or 18), 0, 0)
		K:slab("CouchBack", W, hl, 0.42, 0.18, hc * CF(0, 0.21, hl / 2), vinyl)
		-- 롤 시트: 머리 끝 롤 + 종이 (BedSeat 아래로 지나감)
		K:cyl("CouchPaperRoll", W - 0.5, 0.5, hc * CF(0, 0.05, hl + 0.3), Look.paper)
		K:box("CouchRollBracket", V3(W - 0.3, 0.08, 0.1), hc * CF(0, -0.05, hl + 0.3), LK.chrome)
		K:box("CouchPaper", V3(W - 0.6, 0.012, hl), hc * CF(0, 0.426, hl / 2), lk(248, 248, 242))
		K:box("CouchPaperFlat", V3(W - 0.6, 0.012, flat - 0.2), bf * CF(0, mTop + 0.006, -L / 2 + 0.2 + (flat - 0.2) / 2), lk(248, 248, 242))
		-- 2단 발판
		local sx = oo.stepSide or 1
		local sp = bf * CF(sx * (W / 2 + 0.9), 0, -0.3) * ANG(0, sx * PI / 2, 0)
		K:box("CouchStepFrame", V3(1.6, 0.06, 1.3), sp * CF(0, 0.6, 0), LK.chrome)
		K:box("CouchStepTread", V3(1.5, 0.05, 1.2), sp * CF(0, 0.65, 0), LK.rubber)
		K:box("CouchStepTread2", V3(1.5, 0.05, 0.6), sp * CF(0, 1.25, -0.3), LK.rubber)
		K:box("CouchStepFrame2", V3(1.6, 0.06, 0.65), sp * CF(0, 1.2, -0.3), LK.chrome)
		for _, a in { -0.7, 0.7 } do
			K:seg("CouchStepLeg", (sp * CF(a, 0, 0.6)).Position, (sp * CF(a, 0.6, 0.6)).Position, 0.07, LK.chrome)
			K:seg("CouchStepLeg", (sp * CF(a, 0, -0.6)).Position, (sp * CF(a, 1.2, -0.6)).Position, 0.07, LK.chrome)
		end
	end)
	for _, q in siblings(V, seat) do
		if q.part ~= seat.part and (q.name == "Headboard" or q.name == "Footboard" or q.name == "BedFrame" or q.name == "BedLeg" or q.name == "Mattress" or q.name == "Blanket" or q.name == "Pillow" or q.name == "SideRail" or q.name == "Curtain" or q.name == "CurtainRail") then
			hideRec(K, q)
		end
	end
	return bf, L, W
end

-- 침대 둘레 U 커튼 (침대 틀 bf, 길이 L, 폭 W). side 쪽 열린 상태: 양쪽 레일은 발 쪽 모서리에 모임
local function bedCurtains(K: any, bf: CFrame, L: number, W: number, o: any?): { any }
	local oo: any = o or {}
	local gx = W / 2 + (oo.gapX or 1.3)
	local headZ = L / 2 + (oo.headExt or 0.2)
	local footZ = -L / 2 - (oo.gapFoot or 1.2)
	local function p(x: number, z: number): Vector3
		return (bf * CF(x, 0, z)).Position
	end
	local runs = {}
	local f0 = oo.f0 or 0.12
	if oo.left ~= false then
		table.insert(runs, curtainRun(K, if oo.revLeft then { p(-gx, headZ), p(-gx, footZ) } else { p(-gx, footZ), p(-gx, headZ) }, f0, oo))
	end
	if oo.right ~= false then
		table.insert(runs, curtainRun(K, if oo.revRight then { p(gx, headZ), p(gx, footZ) } else { p(gx, footZ), p(gx, headZ) }, f0, oo))
	end
	if oo.foot ~= false then
		table.insert(runs, curtainRun(K, if oo.revFoot then { p(gx - 0.1, footZ), p(-gx + 0.1, footZ) } else { p(-gx + 0.1, footZ), p(gx - 0.1, footZ) }, f0, oo))
	end
	return runs
end

-- 맵 rec 의 상자를 pcf 로 (+Z = front 방향 단위벡터 쪽 면), 반환 pcf (바닥 가운데), w (폭), d (깊이), h
local function recFrame(r: any, front: Vector3): (CFrame, number, number, number)
	local f = if math.abs(front.X) > math.abs(front.Z) then Vector3.new(math.sign(front.X), 0, 0) else Vector3.new(0, 0, math.sign(front.Z))
	local w = if f.X ~= 0 then r.size.Z else r.size.X
	local d = if f.X ~= 0 then r.size.X else r.size.Z
	return faceCF(Vector3.new(r.c.X, r.min.Y, r.c.Z), f), w, d, r.size.Y
end

-- 의료용 손 세정대 (pcf = 캐비닛 앞 바닥 가운데 기준 상자 가운데, w x d x h). 벽 쪽 = -Z
local function sinkUnit(K: any, pcf: CFrame, w: number, d: number, h: number, o: any?)
	local oo: any = o or {}
	local top = h + 0.12
	K:free(function()
		K:box("SinkCab", V3(w - 0.1, h - 0.35, d - 0.15), pcf * CF(0, 0.35 + (h - 0.35) / 2, -0.05), lk(244, 244, 240))
		K:box("SinkKick", V3(w - 0.3, 0.35, d - 0.4), pcf * CF(0, 0.175, -0.15), lk(70, 74, 78))
		local nd = math.max(2, math.floor(w / 1.5))
		for i = 1, nd do
			local x = -w / 2 + 0.05 + (w - 0.1) * (i - 0.5) / nd
			local dc = pcf * CF(x, 0.35 + (h - 0.35) / 2, d / 2 - 0.12)
			K:plate("SinkDoor", (w - 0.1) / nd - 0.06, h - 0.5, 0.03, dc, lk(236, 238, 236))
			K:plate("SinkPull", 0.06, 0.6, 0.05, dc * CF(if i % 2 == 1 then (w - 0.1) / nd / 2 - 0.25 else -(w - 0.1) / nd / 2 + 0.25, 0.25, 0.03), LK.chrome)
		end
		K:box("SinkTopSlab", V3(w + 0.1, 0.16, d + 0.05), pcf * CF(0, h + 0.04, 0), lk(232, 232, 228, M.Marble))
		local bw, bd = math.min(w * 0.55, 3.0), math.min(d * 0.55, 2.0)
		K:box("SinkBasinRim", V3(bw + 0.12, 0.02, bd + 0.12), pcf * CF(0, h + 0.125, 0.1), LK.steel)
		K:box("SinkBasin", V3(bw, 0.04, bd), pcf * CF(0, h + 0.12, 0.1), lk(120, 124, 128, M.Metal))
		K:disc("SinkDrain", 0.25, 0.02, pcf * CF(0, h + 0.145, 0.1), lk(60, 62, 64, M.Metal))
		-- 거위목 수전 + 팔꿈치 레버
		local tb = pcf * CF(0, top, -d / 2 + 0.3)
		K:vcyl("SinkTapBase", 0.2, 0.28, tb * CF(0, 0.1, 0), LK.chrome)
		K:vcyl("SinkTapRiser", 1.3, 0.14, tb * CF(0, 0.85, 0), LK.chrome)
		K:ring("SinkTapNeck", tb * CF(0, 1.5, 0.35) * ANG(0, PI / 2, 0), 0.35, 0.13, 6, LK.chrome, 0, PI)
		K:vcyl("SinkTapSpout", 0.3, 0.12, tb * CF(0, 1.35, 0.7), LK.chrome)
		K:bar("SinkLever", (tb * CF(0, 0.7, 0)).Position, (tb * CF(0.9, 0.75, 0.05)).Position, 0.08, 0.08, LK.chrome)
		-- 뒤 타일 띠
		local bs = pcf * CF(0, top + 0.05, -d / 2 + 0.02)
		K:box("SinkSplash", V3(w + 0.1, 1.6, 0.05), bs * CF(0, 0.8, 0), lk(232, 240, 238, M.CeramicTiles))
		for i = 1, 3 do
			K:box("SinkSplashGrout", V3(w + 0.1, 0.03, 0.06), bs * CF(0, i * 0.4, 0.005), lk(200, 206, 204))
		end
		if oo.dispensers ~= false then
			local wallD = pcf * CF(0, 0, -d / 2 + 0.07)
			local dcf = CFrame.fromMatrix(wallD.Position, pcf.XVector, Vector3.yAxis, pcf.ZVector)
			soapDispenser(K, dcf * CF(-w * 0.32, top + 2.3, 0))
			sanitizerWall(K, dcf * CF(w * 0.32, top + 2.3, 0))
			towelDispenser(K, dcf * CF(w / 2 + 0.9, top + 2.1, 0))
		end
	end)
end

-- 손상성 폐기물 용기 (노란 통 + 빨간 뚜껑)
local function sharpsBox(K: any, pcf: CFrame, s: number?)
	local k = s or 1
	K:box("SharpsBody", V3(0.9 * k, 1.0 * k, 0.7 * k), pcf * CF(0, 0.5 * k, 0), lk(246, 206, 30, M.Plastic))
	K:box("SharpsLid", V3(0.94 * k, 0.16 * k, 0.74 * k), pcf * CF(0, 1.06 * k, 0), lk(200, 30, 36, M.Plastic))
	K:box("SharpsSlot", V3(0.5 * k, 0.02, 0.18 * k), pcf * CF(0, 1.15 * k, 0.1 * k), LK.black)
	tx(K, "SharpsLabel", 0.8 * k, 0.45 * k, pcf * CF(0, 0.55 * k, 0.35 * k + 0.005), "손상성\n폐기물", C3(190, 20, 30), C3(255, 238, 120), { d = 0.01 })
end

-- 의료폐기물 전용용기 (골판지 박스 + 비닐)
local function medWasteBox(K: any, pcf: CFrame, w: number?, h: number?)
	local ww, hh = w or 1.6, h or 1.9
	K:box("MedWasteBody", V3(ww, hh, ww * 0.9), pcf * CF(0, hh / 2, 0), lk(240, 196, 70, M.Cardboard))
	K:box("MedWasteLid", V3(ww + 0.04, 0.1, ww * 0.9 + 0.04), pcf * CF(0, hh + 0.05, 0), lk(230, 186, 60, M.Cardboard))
	K:box("MedWasteBag", V3(ww - 0.1, 0.18, ww * 0.9 - 0.1), pcf * CF(0, hh + 0.12, 0), lk(250, 230, 120, M.Plastic, { t = 0.2 }))
	tx(K, "MedWasteLabel", ww * 0.86, hh * 0.46, pcf * CF(0, hh * 0.55, ww * 0.45 + 0.005), "☣\n의료폐기물\n전용용기", C3(200, 20, 30), nil, { font = FONT_K, d = 0.01 })
end

-- 페달 휴지통 (스테인리스)
local function pedalBin(K: any, pcf: CFrame, h: number?, label: string?)
	local hh = h or 1.8
	K:vcyl("BinBody", hh, 1.0, pcf * CF(0, hh / 2, 0), LK.steel)
	K:vcyl("BinLid", 0.12, 1.04, pcf * CF(0, hh + 0.06, 0), LK.chrome)
	K:box("BinPedal", V3(0.4, 0.08, 0.3), pcf * CF(0, 0.12, 0.55), LK.black)
	if label then
		tx(K, "BinLabel", 0.7, 0.3, pcf * CF(0, hh * 0.6, 0.505), label, INK, WHITE, { font = FONT_M, d = 0.01 })
	end
end

-- 휠체어 (pcf 바닥, +Z = 앞)
local function wheelchair(K: any, pcf: CFrame)
	local fr = LK.chrome
	local seatY = 1.65
	for _, sx in { -1, 1 } do
		local wc = pcf * CF(sx * 0.95, 1.05, -0.35) * ANG(0, PI / 2, 0)
		K:ring("WheelRim", wc, 1.0, 0.1, 14, LK.black)
		K:ring("WheelPush", wc * CF(0, 0, sx * 0.0), 0.88, 0.05, 12, fr)
		K:cyl("WheelHub", 0.16, 0.28, pcf * CF(sx * 0.95, 1.05, -0.35), fr)
		for i = 0, 3 do
			local a = i * PI / 4
			K:seg("WheelSpoke", (pcf * CF(sx * 0.95, 1.05 + math.sin(a) * 0.95, -0.35 + math.cos(a) * 0.95)).Position, (pcf * CF(sx * 0.95, 1.05 - math.sin(a) * 0.95, -0.35 - math.cos(a) * 0.95)).Position, 0.025, fr)
		end
		K:seg("ChairFrameSide", pcf * V3(sx * 0.75, seatY - 0.1, -0.7), pcf * V3(sx * 0.75, seatY - 0.1, 0.75), 0.1, fr)
		K:seg("ChairFrontPost", pcf * V3(sx * 0.75, seatY - 0.1, 0.75), pcf * V3(sx * 0.75, 0.35, 0.9), 0.1, fr)
		K:ball("ChairCasterWheel", 0.36, pcf * CF(sx * 0.75, 0.18, 1.0), LK.black)
		K:seg("ChairBackPost", pcf * V3(sx * 0.72, seatY - 0.1, -0.75), pcf * V3(sx * 0.75, seatY + 1.9, -0.95), 0.1, fr)
		K:seg("ChairHandle", pcf * V3(sx * 0.75, seatY + 1.9, -0.95), pcf * V3(sx * 0.75, seatY + 1.9, -1.4), 0.12, LK.black)
		K:seg("ChairArmrest", pcf * V3(sx * 0.78, seatY + 0.75, -0.6), pcf * V3(sx * 0.78, seatY + 0.75, 0.4), 0.14, LK.black)
		K:seg("ChairArmPost", pcf * V3(sx * 0.78, seatY - 0.1, 0.3), pcf * V3(sx * 0.78, seatY + 0.75, 0.3), 0.08, fr)
		K:seg("ChairFootTube", pcf * V3(sx * 0.6, seatY - 0.2, 0.8), pcf * V3(sx * 0.5, 0.55, 1.35), 0.08, fr)
		K:box("ChairFootPlate", V3(0.55, 0.05, 0.45), pcf * CF(sx * 0.32, 0.52, 1.4), lk(50, 50, 54, M.Plastic))
	end
	K:box("ChairSling", V3(1.45, 0.08, 1.45), pcf * CF(0, seatY, 0), lk(30, 30, 34, M.Leather))
	K:box("ChairBackSling", V3(1.45, 1.6, 0.06), pcf * CF(0, seatY + 1.0, -0.86) * ANG(math.rad(-6), 0, 0), lk(30, 30, 34, M.Leather))
	K:seg("ChairCross", pcf * V3(-0.7, 0.9, -0.1), pcf * V3(0.7, seatY - 0.15, -0.1), 0.06, fr)
	K:seg("ChairCross", pcf * V3(0.7, 0.9, -0.1), pcf * V3(-0.7, seatY - 0.15, -0.1), 0.06, fr)
end

-- 스탠드 정수기 (pcf 바닥, +Z 앞) + 옆 종이컵 디스펜서. 반환 버튼 파트
local function purifier(K: any, pcf: CFrame, o: any?): BasePart
	local oo: any = o or {}
	local h = oo.h or 4.6
	K:rbox("PurifierBody", V3(1.55, h, 1.6), 0.12, pcf * CF(0, h / 2, 0) * ANG(0, PI / 2, 0), lk(246, 246, 244, M.Plastic))
	K:box("PurifierFace", V3(1.3, 1.6, 0.04), pcf * CF(0, h - 1.4, 0.81), lk(36, 40, 46, M.Glass, { r = 0.1 }))
	tx(K, "PurifierLCD", 0.9, 0.28, pcf * CF(0, h - 0.95, 0.835), "냉수 5°C  ·  온수 85°C", C3(140, 220, 255), nil, { glow = 1.3, d = 0.01, font = FONT_M })
	local cold = K:disc("PurifierCold", 0.3, 0.04, pcf * CF(-0.32, h - 1.45, 0.84) * ANG(PI / 2, 0, 0), col(C3(60, 140, 255), M.Neon))
	K:disc("PurifierHot", 0.3, 0.04, pcf * CF(0.32, h - 1.45, 0.84) * ANG(PI / 2, 0, 0), col(C3(255, 70, 50), M.Neon))
	tx(K, "PurifierBtnLabel", 1.1, 0.16, pcf * CF(0, h - 1.75, 0.835), "냉수        온수 (잠금)", C3(220, 220, 220), nil, { d = 0.01, font = FONT_M })
	K:box("PurifierNozzleBox", V3(0.5, 0.22, 0.35), pcf * CF(0, h - 2.35, 0.95), lk(220, 220, 218, M.Plastic))
	K:vcyl("PurifierNozzle", 0.14, 0.08, pcf * CF(0, h - 2.53, 1.0), LK.chrome)
	K:box("PurifierNiche", V3(1.1, 1.3, 0.05), pcf * CF(0, h - 3.05, 0.79), lk(200, 204, 206, M.Plastic))
	K:box("PurifierTray", V3(1.0, 0.1, 0.45), pcf * CF(0, h - 3.65, 0.98), lk(150, 156, 160, M.Plastic))
	K:box("PurifierTrayGrill", V3(0.9, 0.02, 0.36), pcf * CF(0, h - 3.59, 0.98), LK.chrome)
	tx(K, "PurifierBrand", 1.1, 0.2, pcf * CF(0, 0.7, 0.81), "냉온 정수기", GREY_T, nil, { d = 0.01 })
	if oo.cups ~= false then
		local cp = pcf * CF(1.05, h - 2.2, 0.2)
		K:vcyl("CupTube", 1.6, 0.42, cp, { c = C3(236, 242, 244), m = M.Glass, t = 0.45 })
		K:vcyl("CupStack", 1.4, 0.34, cp * CF(0, -0.05, 0), lk(250, 250, 248))
		K:box("CupTubeBracket", V3(0.18, 0.5, 0.5), cp * CF(-0.25, 0, 0), LK.alu)
		K:vcyl("CupBin", 1.3, 0.8, pcf * CF(1.25, 0.65, 0.4), lk(200, 206, 210, M.Plastic))
		tx(K, "CupBinLabel", 0.6, 0.3, pcf * CF(1.25, 0.9, 0.805), "컵\n버리는 곳", INK, nil, { d = 0.01, font = FONT_M })
	end
	return cold
end

-- 자동 혈압계 (책상형 본체 + 팔 넣는 통 + 화면). pcf = 받침 위 (+Z 환자 쪽). 반환 { screen label, cuff ring part }
local function bpMachine(K: any, pcf: CFrame): (TextLabel, BasePart)
	K:rbox("BPBody", V3(2.4, 1.7, 1.8), 0.25, pcf * CF(0, 0.85, -0.2) * ANG(0, PI / 2, 0), lk(244, 246, 246, M.Plastic))
	K:box("BPBodyBand", V3(2.42, 0.16, 1.82), pcf * CF(0, 1.5, -0.2), col(TEAL, M.Plastic))
	local ring = K:cyl("BPCuffTunnel", 1.0, 1.05, pcf * CF(-0.5, 0.75, 0.25) * ANG(0, PI / 2, 0), lk(60, 66, 72, M.Plastic))
	K:cyl("BPCuffInner", 1.02, 0.8, pcf * CF(-0.5, 0.75, 0.26) * ANG(0, PI / 2, 0), lk(30, 34, 38, M.Fabric))
	local sc = pcf * CF(0.55, 1.15, 0.72) * ANG(math.rad(-25), 0, 0)
	K:box("BPScreenBezel", V3(0.95, 0.75, 0.06), sc, LK.black)
	local _, lab = tx(K, "BPScreen", 0.85, 0.65, sc * CF(0, 0, 0.031), "SYS ---\nDIA ---\n맥박 --", C3(40, 255, 160), C3(8, 24, 20), { glow = 1.3, d = 0.01, font = FONT_B })
	K:disc("BPStart", 0.28, 0.06, pcf * CF(0.55, 0.62, 0.72) * ANG(PI / 2 - math.rad(25), 0, 0), col(C3(40, 200, 120), M.Neon))
	K:box("BPPrinter", V3(0.5, 0.06, 0.08), pcf * CF(0.55, 1.62, 0.25), LK.black)
	K:box("BPReceipt", V3(0.36, 0.02, 0.35), pcf * CF(0.55, 1.66, 0.38) * ANG(math.rad(25), 0, 0), Look.paper)
	tx(K, "BPLabel", 1.4, 0.24, pcf * CF(0, 1.32, 0.71), "자동 혈압계", TEAL_D, nil, { d = 0.01, font = FONT_K })
	return lab, ring
end

-- 혈압 재기 (Player.Fatigue 속성으로 값). screen = TextLabel
local function bpPrompt(K: any, part: BasePart, lab: TextLabel, object: string)
	local busy = false
	return Interact.prompt(K, part, {
		action = "혈압 재기",
		object = object,
		fn = function()
			if busy then
				return
			end
			busy = true
			local plr = Players.LocalPlayer
			local fat = 0
			if plr then
				local v = plr:GetAttribute("Fatigue")
				if type(v) == "number" then
					fat = math.clamp(v, 0, 100)
				end
			end
			local r = rng(os.time() % 1000)
			local sys = math.floor(112 + fat * 0.35 + r() * 10)
			local dia = math.floor(70 + fat * 0.18 + r() * 7)
			local hr = math.floor(66 + fat * 0.2 + r() * 12)
			task.spawn(function()
				for i = 1, 12 do
					if not lab.Parent then
						return
					end
					lab.Text = string.format("측정 중...\n가압 %d mmHg", 60 + i * 12)
					task.wait(0.25)
				end
				local verdict = if sys >= 140 or dia >= 90 then "고혈압 의심 · 진료 권장" elseif sys >= 130 or dia >= 80 then "고혈압 전단계" elseif sys >= 120 then "주의 혈압" else "정상 혈압"
				lab.Text = string.format("SYS %d\nDIA %d\n맥박 %d\n%s", sys, dia, hr, verdict)
				task.wait(8)
				if lab.Parent then
					lab.Text = "SYS ---\nDIA ---\n맥박 --"
				end
				busy = false
			end)
		end,
	})
end

-- 약 상자 (몸통 + 띠 + 글자판). base = 선반 위 pcf (+Z 앞), w h d, colours
local function medBox(K: any, base: CFrame, w: number, h: number, d: number, c: Color3, name: string, band: Color3?, white: boolean?)
	local body = if white then C3(248, 248, 246) else c
	K:box("MedBox", V3(w, h, d), base * CF(0, h / 2, 0), col(body))
	if band then
		K:box("MedBoxBand", V3(w + 0.01, h * 0.22, d + 0.01), base * CF(0, h * 0.25, 0), col(band))
	end
	tx(K, "MedBoxLabel", w * 0.92, h * 0.5, base * CF(0, h * 0.62, d / 2 + 0.002), name, if white then c else WHITE, nil, { d = 0.006, font = FONT_B })
end

-- 약품 서랍장 (벽 앞 판 + 칸 줄눈 + 이름표). dcf = 앞면 가운데 아래 (보는 쪽 +Z), cols x rows
local function drawerBank(K: any, dcf: CFrame, w: number, h: number, depth: number, cols: number, rows: number, names: { string }, seed: number?): { any }
	local r = rng(seed or 7)
	local cw, ch = w / cols, h / rows
	local bodyL = lk(244, 244, 240)
	K:box("DrawerCase", V3(w + 0.2, h + 0.3, depth), dcf * CF(0, h / 2 + 0.15, -depth / 2), bodyL)
	K:plate("DrawerFace", w, h, 0.02, dcf * CF(0, h / 2 + 0.15, 0), lk(236, 238, 236))
	for i = 1, cols - 1 do
		K:plate("DrawerGapV", 0.04, h, 0.03, dcf * CF(-w / 2 + i * cw, h / 2 + 0.15, 0), lk(170, 176, 178))
	end
	for j = 1, rows - 1 do
		K:plate("DrawerGapH", w, 0.04, 0.03, dcf * CF(0, 0.15 + j * ch, 0), lk(170, 176, 178))
	end
	local out = {}
	local k = 0
	for j = 1, rows do
		K:plate("DrawerPullRow", w - 0.2, 0.05, 0.06, dcf * CF(0, 0.15 + (j - 1) * ch + ch * 0.22, 0.02), lk(150, 156, 160, M.Metal))
		for i = 1, cols do
			k += 1
			local x = -w / 2 + (i - 0.5) * cw
			local y = 0.15 + (j - 0.5) * ch
			if r() < 0.86 then
				local nm = names[(k - 1) % #names + 1]
				tx(K, "DrawerTag", cw * 0.72, ch * 0.3, dcf * CF(x, y + ch * 0.12, 0.025), nm, INK, C3(250, 250, 244), { d = 0.008, font = FONT_M })
			end
			table.insert(out, { x = x, y = y })
		end
	end
	return out
end

-- 바퀴 카트 (처치 · 드레싱 · 투약). pcf 바닥, w d h, kind
local function cart(K: any, pcf: CFrame, w: number, d: number, h: number, kind: string)
	local fr = LK.steel
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:vcyl("CartPost", h - 0.35, 0.1, pcf * CF(sx * (w / 2 - 0.1), 0.35 + (h - 0.35) / 2, sz * (d / 2 - 0.1)), fr)
			K:ball("CartWheel", 0.3, pcf * CF(sx * (w / 2 - 0.15), 0.15, sz * (d / 2 - 0.15)), LK.black)
			K:box("CartFork", V3(0.08, 0.2, 0.08), pcf * CF(sx * (w / 2 - 0.15), 0.32, sz * (d / 2 - 0.15)), LK.darkAlu)
		end
	end
	if kind == "drawers" then
		local dc = { C3(220, 60, 60), C3(240, 180, 40), C3(60, 150, 220), C3(80, 180, 120), C3(160, 110, 200) }
		K:box("CartBody", V3(w - 0.1, h - 0.6, d - 0.1), pcf * CF(0, 0.45 + (h - 0.6) / 2, 0), lk(240, 242, 242, M.Plastic))
		local n = 5
		for i = 1, n do
			local y = 0.5 + (h - 0.75) * (i - 0.5) / n
			K:plate("CartDrawer", w - 0.3, (h - 0.75) / n - 0.08, 0.04, pcf * CF(0, y, d / 2 - 0.04), col(dc[(i - 1) % #dc + 1]:Lerp(WHITE, 0.25), M.Plastic))
			K:plate("CartDrawerPull", w * 0.4, 0.08, 0.07, pcf * CF(0, y + 0.05, d / 2 - 0.02), lk(240, 240, 240, M.Plastic))
		end
		K:box("CartTop", V3(w + 0.1, 0.12, d + 0.1), pcf * CF(0, h - 0.06, 0), lk(200, 206, 210, M.Plastic))
	else
		for _, y in { 0.7, h * 0.55, h - 0.06 } do
			K:box("CartShelf", V3(w, 0.07, d), pcf * CF(0, y, 0), fr)
			K:box("CartLip", V3(w, 0.15, 0.04), pcf * CF(0, y + 0.08, d / 2 - 0.02), fr)
		end
		K:bar("CartHandle", pcf * V3(-w / 2 + 0.1, h + 0.3, -d / 2 - 0.15), pcf * V3(w / 2 - 0.1, h + 0.3, -d / 2 - 0.15), 0.08, 0.08, fr)
	end
	-- 위 물건
	local top = h
	if kind == "dressing" or kind == "drawers" then
		K:box("CartTray", V3(1.3, 0.1, 0.9), pcf * CF(-w / 4, top + 0.05, 0), LK.steel)
		K:box("CartGauze", V3(0.6, 0.12, 0.5), pcf * CF(-w / 4 - 0.2, top + 0.16, 0), lk(250, 250, 248, M.Fabric))
		K:vcyl("CartBetadine", 0.5, 0.26, pcf * CF(w / 4, top + 0.25, -0.15), lk(120, 50, 30, M.Glass, { t = 0.15 }))
		K:vcyl("CartAlcohol", 0.55, 0.28, pcf * CF(w / 4 + 0.35, top + 0.28, 0.1), { c = C3(230, 240, 246), m = M.Glass, t = 0.3 })
		K:vcyl("CartTape", 0.12, 0.3, pcf * CF(w / 4 - 0.3, top + 0.06, 0.2), lk(250, 250, 250))
		K:box("CartGloves", V3(0.8, 0.4, 0.45), pcf * CF(0, 0.92, 0), lk(246, 246, 244))
		K:box("CartGlovesBand", V3(0.81, 0.12, 0.46), pcf * CF(0, 1.02, 0), col(C3(90, 140, 220)))
	end
end

-- 상호작용 공통 -----------------------------------------------------------------------------------------------
local function ding(part: BasePart)
	Interact.click(part, "rbxasset://sounds/electronicpingshort.wav")
end

-- 번호표 상태 (방마다 K 에 둠)
local function ticketNo(K: any): number
	K.clinicTicket = (K.clinicTicket or (20 + (os.time() // 600) % 40)) + 1
	return K.clinicTicket
end

-- 방 빌더 =========================================================================================================
local BUILD: { [string]: (any, any) -> () } = {}

-- 1F 로비 (접수 · 수납) -------------------------------------------------------------------------------------------
BUILD.lobby = function(K: any, V: any)
	step(K, "ceiling", function()
		ceilingKit(K, V, { lights = 5 })
	end)
	step(K, "floor", function()
		floorKit(K, V, { look = lk(228, 226, 220, M.Marble), grout = lk(190, 188, 182), tile = 2.04 })
		baseKit(K, V, { "back", "right" })
		lowerWall(K, V, { "back", "right" }, 3.0)
	end)
	local desk = V:first("WorkTop")
	local ledge = V:first("Ledge")
	local front = V:first("FrontPanel")
	-- 접수대 -----------------------------------------------------------------------------
	step(K, "desk", function()
		if not (desk and ledge and front) then
			return
		end
		local x0, x1 = front.min.X, front.max.X
		local cx = (x0 + x1) / 2
		local len = x1 - x0
		local fz = front.max.Z + 0.005
		local fdc = faceCF(Vector3.new(cx, 0, fz), Vector3.zAxis)
		local fh = ledge.min.Y - 0.35
		K:free(function()
			-- 앞판: 흰 솔리드 + 민트 아래 띠 + 청록 선 + 세로 줄눈
			K:plate("DeskFace", len, fh, 0.03, fdc * CF(0, 0.35 + fh / 2, 0), lk(244, 244, 240, M.Marble))
			K:plate("DeskFaceBand", len, 0.65, 0.04, fdc * CF(0, 0.35 + 0.33, 0), col(MINT))
			K:plate("DeskFaceLine", len, 0.07, 0.05, fdc * CF(0, 1.02, 0), col(TEAL))
			local n = math.floor(len / 2.5)
			for i = 1, n - 1 do
				K:plate("DeskFaceJoint", 0.03, fh - 0.7, 0.04, fdc * CF(-len / 2 + i * len / n, 1.05 + (fh - 0.7) / 2, 0), lk(220, 222, 220))
			end
			K:plate("DeskKickFace", len, 0.35, 0.02, fdc * CF(0, 0.175, -0.04), lk(60, 64, 68))
			tx(K, "DeskLogo", 4.2, 0.42, fdc * CF(-len / 2 + 3.0, 1.75, 0.035), "광안 메디컬 의원", TEAL_D, nil, { font = FONT_K })
			tx(K, "DeskLogoEn", 4.0, 0.25, fdc * CF(-len / 2 + 3.0, 1.38, 0.035), "GWANGAN MEDICAL CLINIC", GREY_T, nil, { font = FONT_M })
			-- 창구 번호
			for i, u in { -len / 3, 0, len / 3 } do
				tx(K, "DeskWindowNo", 1.6, 0.36, fdc * CF(u + 2.2, 2.55, 0.035), string.format("%d번 창구", i), TEAL_D, nil, { font = FONT_B })
			end
		end)
		-- 아크릴 가림막 (선반 뒤, 작업대 위)
		local az = ledge.min.Z - 0.08
		local bays = 3
		local ax0 = ledge.min.X + 2.0
		local bw = (ledge.max.X - 0.3 - ax0) / bays
		for i = 1, bays do
			local bx = ax0 + (i - 0.5) * bw
			K:box("AcrylicScreen", V3(bw - 0.3, 1.9, 0.06), CF(bx, ledge.max.Y + 0.45 + 0.95, az), { c = C3(232, 244, 246), m = M.Glass, t = 0.78, r = 0.2 })
			K:box("AcrylicEdge", V3(bw - 0.3, 0.05, 0.07), CF(bx, ledge.max.Y + 2.37, az), LK.alu)
			tx(K, "AcrylicSticker", 1.6, 0.3, faceCF(Vector3.new(bx, ledge.max.Y + 2.05, az + 0.035), Vector3.zAxis), "신분증을 제시해 주세요", TEAL_D, nil, { font = FONT_M, d = 0.005 })
		end
		for i = 0, bays do
			local bx = ax0 + i * bw
			K:box("AcrylicPost", V3(0.1, ledge.max.Y + 2.4 - desk.max.Y, 0.1), CF(bx, desk.max.Y + (ledge.max.Y + 2.4 - desk.max.Y) / 2, az), LK.alu)
		end
		-- 모니터 · 키보드 · 소품 (직원 쪽 -Z)
		hideNames(K, { "MonitorScreen", "MonitorStand", "Monitor", "Printer", "FileTray" })
		local ty = desk.max.Y + 0.005
		local zc = desk.min.Z + 2.1
		local screens = {
			"접수 대기 3명\n홍*동  10:42  내과 초진\n김*희  10:45  예방접종\n이*수  10:51  건강검진",
			"수납 · 처방전\n진찰료 5,700원\n처방전 1매 출력",
			"EMR · 오늘 내원 48명\n예약 12  ·  접수 29\n수납 완료 31",
		}
		for i, x in { x0 + 3.6, cx, x1 - 3.6 } do
			deskMonitor(K, CF(x, ty, desk.min.Z + 2.6) * ANG(0, PI, 0), 2.0, screens[i], C3(236, 244, 246), C3(30, 60, 70), { lift = 0.5 })
			keyboard(K, CF(x, ty, zc - 0.9) * ANG(0, PI, 0), 1.6)
		end
		-- 레이저 프린터 (원래 프린터 자리)
		local px = x0 + 1.4
		local pc = CF(px, ty, desk.min.Z + 1.6) * ANG(0, PI, 0)
		K:rbox("Printer", V3(1.9, 1.0, 1.5), 0.1, pc * CF(0, 0.5, 0) * ANG(0, PI / 2, 0), lk(232, 232, 228, M.Plastic))
		K:box("PrinterTray", V3(1.4, 0.06, 0.7), pc * CF(0, 0.75, 0.4) * ANG(math.rad(-8), 0, 0), lk(60, 62, 66, M.Plastic))
		K:box("PrinterPaper", V3(1.1, 0.04, 0.6), pc * CF(0, 0.8, 0.35), Look.paper)
		K:box("PrinterPanel", V3(0.5, 0.05, 0.25), pc * CF(0.55, 1.02, 0.45), lk(40, 44, 48))
		-- 영수증 프린터 · 카드 단말기 · 서명패드 (손님 쪽 창구 앞)
		Props.receiptPrinter(K, CF(cx + 1.6, ty, desk.max.Z - 0.6))
		Props.cardTerminal(K, CF(cx - 1.4, ty, desk.max.Z - 0.5))
		K:box("SignPad", V3(0.9, 0.06, 0.6), CF(cx - 2.6, ty + 0.03, desk.max.Z - 0.5), LK.black)
		K:box("SignPadLCD", V3(0.7, 0.01, 0.4), CF(cx - 2.6, ty + 0.07, desk.max.Z - 0.5), col(C3(170, 200, 210), M.Neon))
		deskPhone(K, CF(x1 - 1.2, ty, desk.min.Z + 1.2) * ANG(0, PI, 0))
		penCup(K, CF(x1 - 5.8, ty, desk.min.Z + 0.9))
		-- 서류 트레이 3단 (원래 FileTray 자리)
		local fx = x1 - 2.4
		for k = 0, 2 do
			K:box("DocTray", V3(1.4, 0.06, 1.0), CF(fx, ty + 0.1 + k * 0.32, desk.min.Z + 1.0), lk(60, 64, 70, M.Plastic))
			K:box("DocPaper", V3(1.1, 0.04, 0.8), CF(fx, ty + 0.16 + k * 0.32, desk.min.Z + 1.0), Look.paper)
		end
		-- 탁상 달력 2026 · 도장 · 손소독제
		local cc = CF(x0 + 6.4, ty, desk.min.Z + 0.6) * ANG(0, PI, 0)
		K:wedge("DeskCalendar", V3(0.9, 0.6, 0.4), cc * CF(0, 0.3, 0), lk(240, 240, 236))
		tx(K, "DeskCalendarFace", 0.8, 0.45, cc * CF(0, 0.32, 0.07) * ANG(math.rad(-34), 0, 0), "2026\n10 OCT", RED, WHITE, { d = 0.01 })
		K:vcyl("DeskSanitizer", 0.55, 0.3, CF(x1 - 7.5, ty + 0.275, desk.max.Z - 0.5), { c = C3(220, 240, 250), m = M.Glass, t = 0.3 })
		K:vcyl("DeskSanitizerPump", 0.18, 0.14, CF(x1 - 7.5, ty + 0.64, desk.max.Z - 0.5), lk(250, 250, 250))
		K:vcyl("DeskStamp", 0.3, 0.2, CF(x0 + 8.2, ty + 0.15, desk.min.Z + 0.7), lk(130, 30, 30, M.Plastic))
		-- 직원 의자 (원래 의자는 벽을 보고 있음 -> 책상 쪽으로)
		for _, ch in V.chairs do
			if ch.seat.name == "ChairSeat" then
				for _, r in ch.parts do
					hideRec(K, r)
				end
				K:free(function()
					officeChair(K, CF(ch.c.X, 0, ch.c.Z), ch.top + 0.15, { seat = lk(40, 60, 70, M.Fabric), mesh = lk(50, 60, 68, M.Fabric) })
				end)
			end
		end
	end)
	-- 진료시간 · 진료과목 판 (뒷벽) -----------------------------------------------------------
	step(K, "boards", function()
		local hrs = V:first("Sign_09:00 22:00")
		if hrs then
			local dcf = faceCF(Vector3.new(hrs.c.X, hrs.c.Y, hrs.max.Z + 0.01), Vector3.zAxis)
			K:free(function()
				K:plate("HoursBoard", hrs.size.X + 0.2, hrs.size.Y + 0.2, 0.06, dcf, col(WHITE))
				K:plate("HoursBand", hrs.size.X + 0.2, 0.5, 0.07, dcf * CF(0, hrs.size.Y / 2 - 0.15, 0), col(TEAL))
				tx(K, "HoursTitle", hrs.size.X, 0.4, dcf * CF(0, hrs.size.Y / 2 - 0.15, 0.075), "진료시간 안내 · 365일 진료", WHITE, nil, { font = FONT_K })
				tx(K, "HoursBody", hrs.size.X - 0.2, hrs.size.Y - 0.55, dcf * CF(0, -0.25, 0.065), "평　일  09:00 ~ 22:00\n토·일·공휴일  09:00 ~ 18:00\n점심시간  13:00 ~ 14:00\n접수 마감 : 진료 종료 30분 전", INK, nil, { font = FONT_M })
			end)
		end
		local d = wallSpot(K, "back", 5.2, 3.4, 6.9, V.walls.back.b - 3.2, 0.6)
		if d then
			poster(K, d, 5.0, 3.4, "진료과목", "내과 · 가정의학과\n소아청소년과 · 건강검진\n예방접종 · 영양수액\n수면내시경 (예약)", WHITE, INK, TEAL, WHITE, 0.24)
		end
	end)
	-- 무인 접수 · 번호표 키오스크 --------------------------------------------------------------
	step(K, "kiosk", function()
		local kr = V:first("TicketKiosk")
		if not kr then
			return
		end
		hideNames(K, { "TicketKiosk", "TicketSlot", "KioskScreen" })
		local kp = CF(kr.c.X, 0, kr.c.Z)
		local kioskL = lk(246, 246, 244, M.Plastic)
		local screenLab, ticket, slotY
		K:free(function()
			K:box("KioskFoot", V3(2.0, 0.12, 1.7), kp * CF(0, 0.06, -0.05), lk(60, 64, 70, M.Metal))
			K:box("KioskBody", V3(1.7, 3.3, 0.95), kp * CF(0, 0.12 + 1.65, -0.12), kioskL)
			K:box("KioskSideL", V3(0.08, 3.3, 0.97), kp * CF(-0.86, 0.12 + 1.65, -0.12), col(TEAL, M.Plastic))
			K:box("KioskSideR", V3(0.08, 3.3, 0.97), kp * CF(0.86, 0.12 + 1.65, -0.12), col(TEAL, M.Plastic))
			K:box("KioskSpeaker", V3(0.8, 0.12, 0.02), kp * CF(0, 1.35, 0.36), lk(60, 64, 70, M.DiamondPlate))
			local hc = kp * CF(0, 3.55, 0.05) * ANG(math.rad(-22), 0, 0)
			K:box("KioskHead", V3(1.8, 1.6, 0.4), hc, kioskL)
			K:box("KioskBezel", V3(1.6, 1.4, 0.04), hc * CF(0, 0, 0.2), LK.black)
			local _, lab = tx(K, "KioskScreen", 1.45, 1.25, hc * CF(0, 0, 0.225), "무인 접수 · 수납\n\n번호표 뽑기 ▶\n진료비 수납 ▶\n처방전 출력 ▶", C3(20, 60, 70), C3(236, 248, 246), { glow = 1.05, font = FONT_B })
			screenLab = lab
			K:box("KioskTop", V3(1.8, 0.45, 0.42), kp * CF(0, 4.6, -0.05), col(TEAL, M.Plastic))
			tx(K, "KioskTopLabel", 1.7, 0.36, faceCF((kp * CF(0, 4.6, 0.17)).Position, Vector3.zAxis), "접수 · 번호표", WHITE, nil, { font = FONT_K, glow = 1.1 })
			K:box("KioskCardSlot", V3(0.7, 0.12, 0.08), kp * CF(-0.35, 2.5, 0.42), LK.black)
			K:box("KioskCardLED", V3(0.2, 0.04, 0.02), kp * CF(-0.35, 2.62, 0.46), col(C3(60, 220, 120), M.Neon))
			K:box("KioskQR", V3(0.5, 0.4, 0.06), kp * CF(0.4, 2.55, 0.42), lk(30, 30, 34))
			K:box("KioskQRWin", V3(0.36, 0.26, 0.02), kp * CF(0.4, 2.55, 0.46), col(C3(255, 60, 60), M.Neon, { t = 0.3 }))
			slotY = 1.95
			K:box("KioskTicketSlot", V3(0.8, 0.08, 0.1), kp * CF(0, slotY, 0.42), LK.black)
			tx(K, "KioskSlotLabel", 0.9, 0.14, faceCF((kp * CF(0, slotY - 0.18, 0.41)).Position, Vector3.zAxis), "번호표 · 영수증", GREY_T, nil, { font = FONT_M, d = 0.005 })
			ticket = K:box("KioskTicket", V3(0.55, 0.02, 0.05), kp * CF(0, slotY, 0.42), Look.paper)
		end)
		-- 위에 매단 호출 번호 표시기 (접수대 앞)
		local num
		step(K, "callboard", function()
			if not desk then
				return
			end
			local cx = desk.max.X - 3.4
			local z = desk.max.Z + 2.6
			K:free(function()
				local c = CF(cx, 7.7, z)
				for _, sx in { -1, 1 } do
					K:seg("CallBoardWire", (c * CF(sx * 2.4, 0.6, 0)).Position, Vector3.new((c * CF(sx * 2.4, 0, 0)).X, V.H, z), 0.04, LK.alu)
				end
				K:box("CallBoard", V3(6.0, 1.3, 0.3), c, lk(20, 20, 22))
				tx(K, "CallBoardTitle", 2.2, 0.9, faceCF((c * CF(-1.7, 0, 0.16)).Position, Vector3.zAxis), "호출번호", C3(255, 200, 80), nil, { glow = 1.4, font = FONT_K })
				local _, l = tx(K, "CallBoardNo", 3.4, 1.0, faceCF((c * CF(1.2, 0, 0.16)).Position, Vector3.zAxis), "026 → 2번 창구", C3(255, 70, 50), nil, { glow = 1.6, font = FONT_K })
				num = l
				tx(K, "CallBoardBack", 5.6, 0.9, faceCF((c * CF(0, 0, -0.16)).Position, -Vector3.zAxis), "접수 · 수납", C3(120, 255, 200), nil, { glow = 1.3, font = FONT_K })
			end)
			if num then
				local cur = 26
				Interact.anim(K, function(t)
					local n = 26 + math.floor(t / 14) % 30
					if n ~= cur and num.Parent then
						cur = n
						num.Text = string.format("%03d → %d번 창구", n, n % 3 + 1)
					end
				end)
			end
		end)
		if ticket and screenLab then
			local base = ticket.CFrame
			Interact.prompt(K, ticket, {
				action = "번호표 뽑기",
				object = "무인 접수 키오스크",
				sound = "rbxasset://sounds/electronicpingshort.wav",
				fn = function()
					local n = ticketNo(K)
					local waitN = 2 + n % 4
					screenLab.Text = string.format("번호표 %03d번\n\n대기 %d명 · 약 %d분\n\n접수창구에서\n불러 드려요", n, waitN, waitN * 4)
					ticket.Size = V3(0.55, 0.02, 0.05)
					ticket.CFrame = base
					TweenService:Create(ticket, TweenInfo.new(0.6), { Size = V3(0.55, 0.85, 0.02), CFrame = base * CF(0, -0.42, 0.06) }):Play()
					if num then
						task.delay(6, function()
							if num.Parent then
								num.Text = string.format("%03d → 1번 창구", n)
								ding(ticket)
							end
						end)
					end
				end,
			})
		end
	end)
	-- 손 소독 스탠드 (원래 자리) ---------------------------------------------------------------
	step(K, "sanitizer", function()
		local pole = V:first("SanitizerPole")
		if not pole then
			return
		end
		hideNames(K, { "SanitizerPole", "SanitizerBase", "Sanitizer" })
		local sp = faceCF(Vector3.new(pole.c.X, 0, pole.c.Z), Vector3.new(-1, 0, 0.6))
		local drop, unit
		K:free(function()
			K:disc("SanStandBase", 1.3, 0.08, sp * CF(0, 0.04, 0), LK.steel)
			K:vcyl("SanStandPole", 3.3, 0.18, sp * CF(0, 1.7, 0), LK.steel)
			unit = K:box("SanStandUnit", V3(0.9, 1.4, 0.7), sp * CF(0, 3.95, 0.1), lk(250, 250, 248, M.Plastic))
			K:box("SanStandWindow", V3(0.5, 0.45, 0.02), sp * CF(0, 4.15, 0.46), { c = C3(150, 210, 230), m = M.Glass, t = 0.3 })
			K:box("SanStandSensor", V3(0.3, 0.08, 0.06), sp * CF(0, 3.4, 0.46), col(C3(60, 220, 160), M.Neon))
			K:box("SanStandTray", V3(0.8, 0.06, 0.6), sp * CF(0, 2.6, 0.3), LK.chrome)
			K:box("SanStandSign", V3(0.9, 1.1, 0.04), sp * CF(0, 5.25, 0.1), col(TEAL))
			tx(K, "SanStandSignText", 0.8, 1.0, sp * CF(0, 5.25, 0.125), "손 소독\n후\n접수", WHITE, nil, { font = FONT_K })
			drop = K:ball("SanDrop", 0.08, sp * CF(0, 3.25, 0.25), { c = C3(200, 230, 255), m = M.Glass, t = 1 })
		end)
		if unit and drop then
			local d0 = drop.CFrame
			Interact.prompt(K, unit, {
				action = "손 소독",
				object = "자동 손소독기",
				sound = "rbxasset://sounds/swoosh.wav",
				fn = function()
					drop.CFrame = d0
					drop.Transparency = 0.2
					TweenService:Create(drop, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = d0 * CF(0, -0.6, 0), Transparency = 1 }):Play()
				end,
			})
		end
	end)
	-- 열화상 체온 측정기 (입구 옆) --------------------------------------------------------------
	step(K, "thermal", function()
		local door = V.door
		local x = (door and door.x or 0) - 7.4
		local pcf = floorAt(K, x, V.z1 - 6.2, PI / 2, 1.4, 1.4, 5.6, 0.2) or floorAt(K, x + 1.2, V.z1 - 7.5, PI / 2, 1.4, 1.4, 5.6, 0.2)
		if not pcf then
			note(K, "thermal: no spot")
			return
		end
		K:disc("ThermalBase", 1.2, 0.08, pcf * CF(0, 0.04, 0), lk(50, 54, 58, M.Metal))
		K:vcyl("ThermalPole", 4.0, 0.16, pcf * CF(0, 2.08, 0), lk(60, 64, 68, M.Metal))
		local hc = pcf * CF(0, 4.6, 0)
		K:box("ThermalBody", V3(1.0, 1.5, 0.22), hc, lk(30, 32, 36, M.Plastic))
		K:box("ThermalCam", V3(0.3, 0.2, 0.08), hc * CF(0, 0.6, 0.13), LK.black)
		K:disc("ThermalLens", 0.14, 0.02, hc * CF(-0.07, 0.6, 0.17) * ANG(PI / 2, 0, 0), col(C3(120, 40, 160), M.Glass))
		local scr, lab = tx(K, "ThermalScreen", 0.85, 1.05, hc * CF(0, -0.12, 0.115), "체온 측정\n화면을\n바라봐 주세요", WHITE, C3(20, 70, 90), { glow = 1.2, d = 0.01 })
		K:box("ThermalStatus", V3(0.85, 0.05, 0.02), hc * CF(0, -0.7, 0.12), col(C3(60, 220, 120), M.Neon))
		Interact.prompt(K, scr, {
			action = "체온 재기",
			object = "열화상 체온계",
			sound = "rbxasset://sounds/electronicpingshort.wav",
			fn = function()
				local t = 36.3 + (os.clock() * 7 % 6) / 10
				lab.Text = "측정 중..."
				task.delay(1.2, function()
					if lab.Parent then
						lab.Text = string.format("%.1f°C\n정상 체온\n입장하세요", t)
						task.delay(6, function()
							if lab.Parent then
								lab.Text = "체온 측정\n화면을\n바라봐 주세요"
							end
						end)
					end
				end)
			end,
		})
	end)
	-- 입구: 우산 포장기 · 휠체어 · 유리 시트지 ----------------------------------------------------
	step(K, "entrance", function()
		local door = V.door
		local dx = door and door.x or 0
		local up = floorAt(K, dx + 7.6, V.z1 - 2.4, PI, 1.2, 1.0, 3.3, 0.1)
		if up then
			K:box("UmbrellaBody", V3(1.0, 2.8, 0.8), up * CF(0, 1.4, 0), lk(220, 222, 224, M.Metal))
			K:box("UmbrellaTop", V3(1.1, 0.2, 0.9), up * CF(0, 2.9, 0), col(TEAL, M.Plastic))
			K:box("UmbrellaHole", V3(0.4, 0.05, 0.4), up * CF(0, 3.0, 0), LK.black)
			K:box("UmbrellaBagRoll", V3(0.8, 0.4, 0.05), up * CF(0, 2.2, 0.42), { c = C3(230, 240, 244), m = M.Glass, t = 0.3 })
			tx(K, "UmbrellaLabel", 0.9, 0.7, up * CF(0, 1.4, 0.41), "우산\n비닐\n포장기", TEAL_D, nil, { font = FONT_B, d = 0.01 })
		end
		local wc = floorAt(K, dx + 15.5, V.z1 - 3.6, PI * 0.95, 2.4, 3.2, 3.8, 0.1)
		if wc then
			wheelchair(K, wc)
		end
		-- 유리창 시트지 띠 (문 제외)
		K:free(function()
			local x0 = (door and (door.x - door.w / 2 - 0.6)) or -4
			local x1 = (door and (door.x + door.w / 2 + 0.6)) or 4
			for _, s in { { V.x0 + 0.3, x0 }, { x1, V.x1 - 0.3 } } do
				if s[2] - s[1] > 1 then
					local c = (s[1] + s[2]) / 2
					K:box("GlassFilmBand", V3(s[2] - s[1], 0.9, 0.01), CF(c, 4.4, V.z1 - 0.02), { c = C3(230, 238, 238), m = M.Glass, t = 0.35 })
					K:box("GlassFilmLine", V3(s[2] - s[1], 0.08, 0.012), CF(c, 3.9, V.z1 - 0.025), col(TEAL, M.SmoothPlastic, { t = 0.2 }))
				end
			end
		end)
	end)
	-- 오른벽 (진료실 벽): 리플렛 꽂이 · 비급여 안내 · 의료진 소개 · AED ------------------------------
	step(K, "rightwall", function()
		local d = wallSpot(K, "right", 3.6, 2.4, 6.2, 3, 0.8)
		if d then
			K:plate("BrochureBack", 3.4, 3.6, 0.06, d, lk(236, 238, 238, M.Plastic))
			tx(K, "BrochureTitle", 3.2, 0.3, d * CF(0, 1.62, 0.065), "건강 정보 리플렛 · 자유롭게 가져가세요", TEAL_D, nil, { font = FONT_B })
			local titles = { "독감\n예방접종", "국가\n건강검진", "대상포진\n예방", "고혈압\n관리", "당뇨\n관리", "영양\n수액", "금연\n클리닉", "수면\n내시경", "골다공증\n검사" }
			local cs = { C3(60, 140, 200), C3(0, 128, 118), C3(230, 120, 40), C3(200, 50, 60), C3(90, 110, 200), C3(240, 180, 40), C3(120, 120, 120), C3(70, 160, 120), C3(160, 90, 170) }
			for i = 0, 8 do
				local cx = -1.1 + (i % 3) * 1.1
				local cy = 0.95 - (i // 3) * 1.12
				local pc = d * CF(cx, cy, 0.06)
				K:plate("BrochureLeaflet", 0.8, 0.95, 0.06, pc * CF(0, 0.08, 0), col(cs[i + 1]))
				tx(K, "BrochureLeafletText", 0.7, 0.5, pc * CF(0, 0.2, 0.065), titles[i + 1], WHITE, nil, { font = FONT_B, d = 0.005 })
				K:plate("BrochurePocket", 0.95, 0.5, 0.16, pc * CF(0, -0.25, 0), { c = C3(232, 244, 246), m = M.Glass, t = 0.55 })
			end
		end
		local d2 = wallSpot(K, "right", 5.2, 4.6, 8.8, -7, 0.6)
		if d2 then
			poster(K, d2, 5.0, 4.0, "비급여 진료비 안내", "영양수액 (비타민·마늘)  50,000 ~ 90,000원\n독감 예방접종 (4가)  40,000원\n대상포진 (재조합)  250,000원 / 회\n수면내시경 (위)  70,000원\n일반 진단서  20,000원\n진료확인서  3,000원\n※ 2026년 10월 기준 · 의료법 제45조", WHITE, INK, NAVY, WHITE, 0.16)
		end
		local d3 = wallSpot(K, "right", 3.4, 4.4, 8.4, 1.5, 0.6)
		if d3 then
			K:plate("DoctorFrame", 3.2, 4.0, 0.06, d3, lk(200, 204, 206, M.Metal))
			K:plate("DoctorFrameBg", 3.0, 3.8, 0.07, d3, col(C3(236, 244, 242)))
			tx(K, "DoctorFrameTitle", 2.8, 0.36, d3 * CF(0, 1.6, 0.075), "의료진 소개", TEAL_D, nil, { font = FONT_K })
			K:plate("DoctorPhotoBg", 1.5, 1.7, 0.075, d3 * CF(0, 0.45, 0), col(C3(190, 210, 220)))
			K:ell("DoctorPhotoHead", V3(0.6, 0.7, 0.05), d3 * CF(0, 0.75, 0.08), col(C3(232, 200, 176)))
			K:ell("DoctorPhotoHair", V3(0.62, 0.3, 0.051), d3 * CF(0, 1.02, 0.081), col(C3(40, 34, 30)))
			K:plate("DoctorPhotoCoat", 1.1, 0.6, 0.02, d3 * CF(0, 0.05, 0.075), col(WHITE))
			K:plate("DoctorPhotoTie", 0.12, 0.45, 0.02, d3 * CF(0, 0.08, 0.095), col(NAVY))
			tx(K, "DoctorFrameName", 2.8, 1.1, d3 * CF(0, -1.05, 0.075), "원장  김 선 생\n내과 전문의 · 소화기내과 분과\n대한내과학회 정회원", INK, nil, { font = FONT_M })
		end
		local d4 = wallSpot(K, "right", 2.0, 3.4, 5.8, 8.5, 0.8)
		if d4 then
			aedBox(K, d4)
		end
	end)
	-- 층별 안내판: 공중에 떠 있던 판에 받침 기둥 --------------------------------------------------
	step(K, "directory", function()
		local s = V:first("Sign_층별 안내")
		if not s then
			return
		end
		K:free(function()
			for _, sx in { -1, 1 } do
				local x = s.c.X + sx * (s.size.X / 2 - 0.3)
				K:box("DirectoryPost", V3(0.25, s.min.Y + 0.2, 0.25), CF(x, (s.min.Y + 0.2) / 2, s.c.Z - 0.2), lk(70, 74, 78, M.Metal))
				K:box("DirectoryFoot", V3(0.5, 0.1, 1.4), CF(x, 0.05, s.c.Z - 0.2), lk(70, 74, 78, M.Metal))
			end
			K:box("DirectoryFrameTop", V3(s.size.X + 0.2, 0.18, 0.3), CF(s.c.X, s.max.Y + 0.05, s.c.Z - 0.12), lk(70, 74, 78, M.Metal))
			K:box("DirectoryFrameBot", V3(s.size.X + 0.2, 0.18, 0.3), CF(s.c.X, s.min.Y - 0.05, s.c.Z - 0.12), lk(70, 74, 78, M.Metal))
			K:box("DirectoryBack", V3(s.size.X, s.size.Y, 0.06), CF(s.c.X, s.c.Y, s.c.Z - 0.22), lk(236, 238, 238))
		end)
	end)
	-- 천장 매단 안내판 ------------------------------------------------------------------------
	step(K, "hangsigns", function()
		hangSign(K, V.x0 + 4.5, 0.5, 5.2, 1.0, 7.6, -PI / 2, "대기실 →", "← 접수 · 수납")
		hangSign(K, V.x0 + 9.0, V.z0 + 2.4, 6.4, 1.0, 7.6, 0, "진료실 · 주사실 · 약국 ↑", "출입구 ↓")
	end)
end

-- 벽 u 좌표 (로컬 점 -> 그 벽의 u)
local function wallU(wn: string, p: Vector3): number
	if wn == "back" then
		return p.X
	elseif wn == "front" then
		return -p.X
	elseif wn == "left" then
		return -p.Z
	end
	return p.Z
end

-- 건강 포스터 세트 (제목, 본문, 띠색)
local HEALTH_POSTERS = {
	{ "2026-2027 독감 예방접종", "생후 6개월 ~ 13세 · 임신부 · 65세 이상\n무료 접종 (국가예방접종)\n일반 성인 4가 40,000원\n접종 후 20~30분 대기", C3(30, 110, 190) },
	{ "국가건강검진 2026", "올해 대상 : 짝수년도 출생자\n일반검진 · 암검진 무료\n건강보험공단 문자 확인\n예약 문의 2층 검진센터", TEAL },
	{ "대상포진 예방접종", "50세 이상 권장\n재조합 백신 2회 접종\n통증 · 신경통 예방\n부산시 65세 이상 지원", C3(220, 110, 30) },
	{ "고혈압 · 당뇨 관리", "만성질환 관리제 참여 의원\n혈압 140/90 이상이면 상담\n공복혈당 126 이상이면 상담\n꾸준한 복약이 중요해요", C3(196, 40, 52) },
	{ "올바른 손 씻기 6단계", "손바닥 · 손등 · 손가락 사이\n두 손 모아 · 엄지 · 손톱 밑\n흐르는 물에 30초 이상\n씻기 어려우면 손 소독제", C3(40, 150, 200) },
	{ "기침 예절", "기침할 땐 옷소매로 가리기\n호흡기 증상 시 마스크 착용\n사용한 휴지는 휴지통에\n대기 중 거리 두기", C3(90, 110, 130) },
}

local function healthPoster(K: any, dcf: CFrame, i: number, w: number?, h: number?)
	local p = HEALTH_POSTERS[(i - 1) % #HEALTH_POSTERS + 1]
	poster(K, dcf, w or 3.0, h or 4.0, p[1], p[2], WHITE, INK, p[3], WHITE, 0.24)
end

-- 1F 대기실 -----------------------------------------------------------------------------------------------------
BUILD.waiting = function(K: any, V: any)
	hideNames(K, { "WaitingRug" })
	step(K, "ceiling", function()
		ceilingKit(K, V, { lights = 4 })
	end)
	step(K, "floor", function()
		floorKit(K, V, { look = lk(228, 226, 220, M.Marble), grout = lk(190, 188, 182), tile = 2.04 })
		baseKit(K, V, { "back", "left" })
		lowerWall(K, V, { "back", "left" }, 3.0)
	end)
	-- 연결 의자 3줄 (자리 · 높이 그대로)
	step(K, "benches", function()
		local groups: { [Instance]: { any } } = {}
		for _, ch in V.chairs do
			if ch.seat.name == "BenchSeat" then
				local m = ch.seat.part.Parent :: Instance
				groups[m] = groups[m] or {}
				table.insert(groups[m], ch)
			end
		end
		for _, g in groups do
			beamChairs(K, g, { seat = LK.vinylTeal })
		end
	end)
	-- 대기 순번 모니터 (천장 매달림, 의자 쪽을 봄)
	step(K, "waitscreen", function()
		local z = V.z1 - 3.0
		local x = -5.5
		local c = CF(x, 8.0, z) * ANG(0, PI, 0)
		local lab
		K:free(function()
			K:seg("WaitScreenPole", (c * CF(0, 1.3, 0)).Position, Vector3.new(x, V.H, z), 0.16, LK.alu)
			K:box("WaitScreenMount", V3(1.0, 0.3, 0.4), c * CF(0, 1.25, -0.05), LK.alu)
			K:box("WaitScreenBody", V3(5.0, 2.95, 0.22), c, lk(16, 16, 18))
			local _, l = tx(K, "WaitScreen", 4.8, 2.75, c * CF(0, 0, 0.115), "", C3(240, 250, 250), C3(10, 60, 66), { glow = 1.2, font = FONT_B })
			lab = l
			tx(K, "WaitScreenBack", 4.6, 2.6, c * ANG(0, PI, 0) * CF(0, 0, 0.115), "광안 메디컬 의원\n\n오늘도 건강하세요", C3(200, 240, 236), C3(10, 50, 56), { glow = 1.0, font = FONT_K })
		end)
		if lab then
			Interact.screenLoop(K, nil, lab, {
				{ text = "진료 대기 현황 · 진료실 1 내과\n\n진료 중   홍*동 님\n다음 순서   김*희 · 이*수 · 박*민\n예상 대기 15분" },
				{ text = "진료 대기 현황 · 주사실\n\n수액 중   2명\n주사 대기   최*영 님\n주사 후 5분간 눌러 주세요" },
				{ text = "건강검진센터 (2층)\n\n오늘 검진 예약 12명\n금식 중이신 분은 물도 드시지 마세요\n결과 상담은 2층 검진센터에서" },
				{ text = "2026-2027 독감 예방접종 시작\n\n어르신 · 어린이 무료\n성인 4가 40,000원\n접수창구에 문의하세요" },
			}, 6)
		end
	end)
	-- 정수기 (원래 자리) ---------------------------------------------------------------------
	step(K, "purifier", function()
		local wp = V:first("WaterPurifier")
		if not wp then
			return
		end
		hideNames(K, { "WaterPurifier", "CupHolder", "PurifierPanel", "PurifierTap" })
		local pc = faceCF(Vector3.new(wp.c.X, 0, wp.c.Z), Vector3.zAxis)
		K:free(function()
			purifier(K, pc, { h = 4.6 })
		end)
		local d = wallSpot(K, "left", 2.6, 5.4, 6.6, wallU("left", Vector3.new(0, 0, wp.c.Z)), 0.5)
		if d then
			K:plate("PurifierSign", 2.4, 1.0, 0.04, d, col(WHITE))
			tx(K, "PurifierSignText", 2.3, 0.9, d * CF(0, 0, 0.045), "정수기 · 종이컵\n사용한 컵은 수거함에", TEAL_D, nil, { font = FONT_B })
		end
	end)
	-- 잡지 꽂이 (원래 자리, 방 안쪽을 봄) ------------------------------------------------------
	step(K, "magazines", function()
		local mr = V:first("MagazineRack")
		if not mr then
			return
		end
		hideNames(K, { "MagazineRack", "Magazine" })
		local pc = faceCF(Vector3.new(mr.c.X, 0, mr.c.Z), Vector3.xAxis)
		local wood = Look.lightOak
		local titles = { { "건강과 생활", C3(40, 130, 120) }, { "여성동아", C3(200, 60, 90) }, { "부산 매거진", C3(30, 90, 170) }, { "과학동아", C3(240, 160, 30) }, { "맛집 가이드\n광안리", C3(220, 90, 40) }, { "월간 산", C3(70, 130, 70) } }
		K:free(function()
			for _, sx in { -1, 1 } do
				K:box("MagRackSide", V3(0.1, 4.0, 1.3), pc * CF(sx * 0.95, 2.0, -0.2), wood)
			end
			K:box("MagRackBack", V3(1.9, 3.8, 0.08), pc * CF(0, 2.1, -0.8), wood)
			for i = 0, 2 do
				local y = 0.6 + i * 1.2
				local sc = pc * CF(0, y, 0) * ANG(math.rad(-16), 0, 0)
				K:box("MagRackShelf", V3(1.8, 0.06, 0.8), pc * CF(0, y - 0.35, -0.3), wood)
				K:box("MagRackLip", V3(1.8, 0.2, 0.05), pc * CF(0, y - 0.25, 0.12), wood)
				for j = 0, 1 do
					local t = titles[i * 2 + j + 1]
					local mc = sc * CF(-0.45 + j * 0.9, 0.3, -0.25)
					K:box("Magazine", V3(0.8, 1.05, 0.04), mc, col(WHITE))
					K:box("MagazineCover", V3(0.78, 0.7, 0.045), mc * CF(0, -0.12, 0), col(t[2]))
					tx(K, "MagazineTitle", 0.74, 0.28, mc * CF(0, 0.36, 0.025), t[1], t[2], nil, { font = FONT_K, d = 0.005 })
				end
			end
		end)
	end)
	-- 어린이 놀이 코너 --------------------------------------------------------------------
	step(K, "kids", function()
		local mat = V:first("PlayMat")
		if mat then
			hideRec(K, mat)
			local cs = { C3(250, 120, 110), C3(255, 210, 80), C3(120, 200, 120), C3(110, 170, 240), C3(200, 140, 220) }
			K:free(function()
				local nx = math.max(2, math.floor(mat.size.X / 1.6 + 0.5))
				local nz = math.max(1, math.floor(mat.size.Z / 1.6 + 0.5))
				local tw, td = mat.size.X / nx, mat.size.Z / nz
				for i = 0, nx - 1 do
					for j = 0, nz - 1 do
						K:box("PuzzleMat", V3(tw - 0.04, 0.12, td - 0.04), CF(mat.min.X + (i + 0.5) * tw, 0.06, mat.min.Z + (j + 0.5) * td), col(cs[(i + j * 2) % #cs + 1], M.Plastic))
					end
				end
			end)
		end
		-- 아이 의자 · 탁자 (자리 그대로)
		for _, st in V.stools do
			for _, r in st.parts do
				hideRec(K, r)
			end
			K:free(function()
				Props.stool(K, CF(st.c.X, 0, st.c.Z), { style = "plastic", seatTop = st.top, dia = 1.0, seat = lk(255, 170, 60, M.Plastic) })
			end)
		end
		for _, t in V.tables do
			if t.top.name == "TableTop" then
				hideList(K, t.parts)
				K:free(function()
					local c = CF((t.min.X + t.max.X) / 2, 0, (t.min.Z + t.max.Z) / 2)
					K:disc("KidsTableTop", math.min(t.max.X - t.min.X, t.max.Z - t.min.Z), 0.12, c * CF(0, t.y - 0.06, 0), lk(250, 250, 246, M.Plastic))
					K:disc("KidsTableEdge", math.min(t.max.X - t.min.X, t.max.Z - t.min.Z) + 0.06, 0.06, c * CF(0, t.y - 0.14, 0), lk(110, 190, 240, M.Plastic))
					for i = 0, 3 do
						local a = i * PI / 2 + PI / 4
						K:seg("KidsTableLeg", (c * CF(math.cos(a) * 0.55, t.y - 0.15, math.sin(a) * 0.55)).Position, (c * CF(math.cos(a) * 0.7, 0.02, math.sin(a) * 0.7)).Position, 0.16, col(({ C3(250, 120, 110), C3(255, 210, 80), C3(120, 200, 120), C3(110, 170, 240) })[i + 1], M.Plastic))
					end
				end)
			end
		end
		-- 장난감 · 그림책 낮은 선반 (바깥벽)
		local sp = wallFloorNear(K, "left", wallU("left", Vector3.new(0, 0, (mat and mat.c.Z or 8))), 3.2, 1.0, 2.4, 2, 0)
		if sp then
			local wood = Look.birch
			K:box("ToyShelfBody", V3(3.2, 0.1, 1.0), sp * CF(0, 2.35, 0), wood)
			K:box("ToyShelfMid", V3(3.2, 0.1, 1.0), sp * CF(0, 1.2, 0), wood)
			K:box("ToyShelfBase", V3(3.2, 0.12, 1.0), sp * CF(0, 0.06, 0), wood)
			for _, sx in { -1, 1 } do
				K:box("ToyShelfSide", V3(0.1, 2.4, 1.0), sp * CF(sx * 1.55, 1.2, 0), wood)
			end
			K:box("ToyShelfBack", V3(3.2, 2.4, 0.05), sp * CF(0, 1.2, -0.48), lk(250, 230, 180))
			Props.row(K, sp * CF(0, 1.25, 0.1), 3.0, "books", { colors = { C3(250, 120, 110), C3(255, 210, 80), C3(120, 200, 120), C3(110, 170, 240), C3(200, 140, 220) }, seed = 4 })
			K:ball("ToyBall", 0.6, sp * CF(-0.9, 0.42, 0.1), col(C3(240, 70, 60), M.Plastic))
			K:ball("ToyBall", 0.45, sp * CF(-0.3, 0.35, 0.2), col(C3(60, 140, 240), M.Plastic))
			K:box("ToyCar", V3(0.9, 0.35, 0.5), sp * CF(0.6, 0.3, 0.1), col(C3(250, 200, 40), M.Plastic))
			K:box("ToyCarTop", V3(0.5, 0.25, 0.45), sp * CF(0.55, 0.6, 0.1), col(C3(250, 200, 40), M.Plastic))
			for _, wx in { 0.3, 0.9 } do
				K:cyl("ToyCarWheel", 0.52, 0.22, sp * CF(wx, 0.12, 0.1) * ANG(0, PI / 2, 0), LK.black)
			end
			K:ell("ToyBear", V3(0.6, 0.7, 0.5), sp * CF(-0.6, 2.75, 0.1), col(C3(190, 140, 90), M.Fabric))
			K:ball("ToyBearHead", 0.45, sp * CF(-0.6, 3.25, 0.1), col(C3(190, 140, 90), M.Fabric))
			Props.row(K, sp * CF(0.5, 2.4, 0.1), 1.6, "boxes", { colors = { C3(120, 200, 120), C3(110, 170, 240) }, seed = 2, n = 2 })
		end
		-- 공중에 떠 있던 놀이방 표지에 기둥
		local ks = V:first("KidsSign")
		if ks then
			K:free(function()
				for _, x in { ks.min.X + 0.3, ks.max.X - 0.3 } do
					K:box("KidsSignPost", V3(0.16, ks.min.Y, 0.16), CF(x, ks.min.Y / 2, ks.c.Z), lk(255, 200, 60, M.Plastic))
					K:ball("KidsSignPostCap", 0.3, CF(x, 0.15, ks.c.Z), lk(255, 120, 100, M.Plastic))
				end
			end)
		end
	end)
	-- 혈압 측정 코너 (TV벽 오른쪽) ----------------------------------------------------------
	step(K, "bp", function()
		local pcf = wallFloorNear(K, "back", 7.6, 3.0, 2.0, 2.7, 2.5, 0)
		if not pcf then
			note(K, "waiting bp: no spot")
			return
		end
		K:box("BPTable", V3(3.0, 0.12, 2.0), pcf * CF(0, 2.5, 0), lk(244, 244, 240))
		K:box("BPTableBody", V3(2.8, 2.4, 1.8), pcf * CF(0, 1.2, -0.05), lk(236, 238, 236))
		K:box("BPTableBand", V3(2.82, 0.2, 1.82), pcf * CF(0, 2.2, -0.05), col(TEAL))
		local lab, ring = bpMachine(K, pcf * CF(0, 2.56, 0.05))
		tx(K, "BPTableNote", 2.6, 0.9, pcf * CF(0, 1.3, 0.86), "혈압 측정 방법\n① 팔을 깊이 넣고  ② 시작 버튼\n측정 중 말하지 마세요", INK, WHITE, { font = FONT_M, d = 0.01 })
		local cp = pcf * CF(0, 0, 2.4) * ANG(0, PI, 0)
		if K:spot(cp, V3(1.9, 3.6, 1.8), 0) then
			armChair(K, cp, 1.85, LK.vinylTeal)
		end
		bpPrompt(K, ring, lab, "자동 혈압계")
		local d = wallSpot(K, "back", 3.0, 3.4, 5.4, wallU("back", pcf.Position), 0.5)
		if d then
			poster(K, d, 2.8, 1.9, "혈압 분류 (2022 대한고혈압학회)", "정상  120 / 80 미만\n주의  120~129 / 80 미만\n전단계  130~139 / 80~89\n고혈압  140 / 90 이상", WHITE, INK, C3(196, 40, 52), WHITE, 0.26)
		end
	end)
	-- 공기청정기 (원래 자리) --------------------------------------------------------------
	step(K, "airpurifier", function()
		local ap = V:first("AirPurifier")
		if not ap then
			return
		end
		hideNames(K, { "AirPurifier", "PurifierLED" })
		local pc = faceCF(Vector3.new(ap.c.X, 0, ap.c.Z), Vector3.new(-1, 0, -1))
		local ringP, fan
		K:free(function()
			K:rbox("AirPurBody", V3(1.5, 3.4, 1.5), 0.45, pc * CF(0, 1.75, 0) * ANG(0, PI / 2, 0), lk(246, 246, 244, M.Plastic))
			K:box("AirPurBase", V3(1.4, 0.1, 1.4), pc * CF(0, 0.05, 0), lk(200, 204, 206, M.Plastic))
			K:box("AirPurGrilleF", V3(1.2, 2.2, 0.02), pc * CF(0, 1.5, 0.755), lk(214, 218, 220, M.DiamondPlate))
			K:disc("AirPurTop", 1.3, 0.06, pc * CF(0, 3.47, 0), lk(60, 64, 68, M.Plastic))
			fan = K:disc("AirPurFan", 1.0, 0.03, pc * CF(0, 3.5, 0), lk(120, 124, 128, M.Metal))
			ringP = K:box("AirPurRing", V3(1.0, 0.06, 0.02), pc * CF(0, 3.0, 0.76), col(C3(60, 140, 255), M.Neon))
			tx(K, "AirPurLabel", 1.0, 0.24, pc * CF(0, 2.75, 0.76), "공기질 좋음 · PM2.5 8", C3(40, 120, 220), nil, { font = FONT_M, d = 0.005 })
		end)
		if ringP and fan then
			local modes = { { "자동", C3(60, 140, 255), 0.6 }, { "터보", C3(60, 220, 120), 2.2 }, { "수면", C3(150, 110, 220), 0.2 } }
			local rate = 0.6
			local f0 = fan.CFrame
			Interact.anim(K, function(t)
				if fan.Parent then
					fan.CFrame = f0 * CFrame.Angles(t * rate * 6, 0, 0)
				end
			end)
			Interact.cycle(K, ringP, modes, {
				action = "모드 바꾸기",
				object = "공기청정기",
				on = function(_i, m)
					ringP.Color = m[2]
					rate = m[3]
				end,
			})
		end
	end)
	-- 벽: 건강 포스터 (바깥벽) · 손소독제 · 걸이 표지 ------------------------------------------
	step(K, "posters", function()
		local n = 0
		for i, z in { -4.2, 0.4, 5.0 } do
			local d = wallSpot(K, "left", 3.2, 4.6, 8.8, wallU("left", Vector3.new(0, 0, z)), 0.6)
			if d then
				n += 1
				healthPoster(K, d * CF(0, 0, 0), i, 3.0, 4.0)
			end
		end
		local d2 = wallSpot(K, "back", 1.0, 3.4, 4.8, -6.0, 0.6)
		if d2 then
			sanitizerWall(K, d2)
		end
		hangSign(K, V.x1 - 1.5, -3.5, 4.4, 1.0, 7.8, PI / 2, "대기실 · WAITING", "대기실 · WAITING")
		-- 유리 시트지 띠
		K:free(function()
			K:box("GlassFilmBand", V3(V.W - 0.6, 0.9, 0.01), CF(0, 4.4, V.z1 - 0.02), { c = C3(230, 238, 238), m = M.Glass, t = 0.35 })
			K:box("GlassFilmLine", V3(V.W - 0.6, 0.08, 0.012), CF(0, 3.9, V.z1 - 0.025), col(TEAL, M.SmoothPlastic, { t = 0.2 }))
		end)
	end)
end

-- 칸막이 벽 (바닥~천장, 문 구멍 선택). a -> b (로컬 xz), 문: { u0, u1 } (a 에서 거리), 두께 t
local function partition(K: any, a: Vector3, b: Vector3, doors: { { number } }?, o: any?): { any }
	local oo: any = o or {}
	local V = K.V
	local H = oo.h or V.H
	local t = oo.t or 0.45
	local L = (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z))
	local len = L.Magnitude
	local dir = L.Unit
	local n = Vector3.new(-dir.Z, 0, dir.X)
	local wallL = oo.look or lk(242, 242, 238, M.SmoothPlastic)
	local cuts = {}
	for _, d in doors or {} do
		table.insert(cuts, d)
	end
	table.sort(cuts, function(p, q)
		return p[1] < q[1]
	end)
	local function seg(s0: number, s1: number, y0: number, y1: number, name: string)
		if s1 - s0 < 0.05 or y1 - y0 < 0.05 then
			return
		end
		local mid = Vector3.new(a.X, 0, a.Z) + dir * ((s0 + s1) / 2)
		local cf = CFrame.fromMatrix(Vector3.new(mid.X, (y0 + y1) / 2, mid.Z), dir, Vector3.yAxis, dir:Cross(Vector3.yAxis))
		K:box(name, V3(s1 - s0, y1 - y0, t), cf, wallL)
		-- 걸레받이 양면
		if y0 < 0.1 then
			for _, sd in { 1, -1 } do
				K:box("PartitionBase", V3(s1 - s0, 0.45, 0.05), cf * CF(0, -(y1 - y0) / 2 + 0.225, sd * (t / 2 + 0.025)), lk(120, 128, 132))
			end
		end
	end
	local out = {}
	K:free(function()
		local cur = 0
		for _, d in cuts do
			seg(cur, d[1], 0, H, "Partition")
			seg(d[1], d[2], d[3] or 7.6, H, "PartitionHeader")
			-- 문틀
			for _, s in { d[1], d[2] } do
				local p = Vector3.new(a.X, 0, a.Z) + dir * s
				K:box("PartitionJamb", V3(0.14, d[3] or 7.6, t + 0.08), CFrame.fromMatrix(Vector3.new(p.X, (d[3] or 7.6) / 2, p.Z), dir, Vector3.yAxis, dir:Cross(Vector3.yAxis)), LK.alu)
			end
			local hp = Vector3.new(a.X, 0, a.Z) + dir * ((d[1] + d[2]) / 2)
			K:box("PartitionHead", V3(d[2] - d[1] + 0.28, 0.14, t + 0.08), CFrame.fromMatrix(Vector3.new(hp.X, (d[3] or 7.6) + 0.07, hp.Z), dir, Vector3.yAxis, dir:Cross(Vector3.yAxis)), LK.alu)
			table.insert(out, { s0 = d[1], s1 = d[2], h = d[3] or 7.6, mid = hp, dir = dir, n = n })
			cur = d[2]
		end
		seg(cur, len, 0, H, "Partition")
	end)
	return out
end

-- 미닫이 문짝 (문 구멍 정보 d, 열린 비율 f, 쪽 sd = 칸막이 법선 쪽)
local function slideDoor(K: any, d: any, f: number, sd: number, o: any?): BasePart
	local oo: any = o or {}
	local w = d.s1 - d.s0
	local cf = CFrame.fromMatrix(Vector3.new(d.mid.X, d.h / 2, d.mid.Z), d.dir, Vector3.yAxis, d.dir:Cross(Vector3.yAxis))
	cf = cf * CF(w * f, 0, sd * 0.32)
	local leaf = K:box("SlideDoorLeaf", V3(w, d.h - 0.1, 0.12), cf, oo.look or lk(214, 190, 150, M.Wood))
	K:box("SlideDoorWindow", V3(0.5, 2.2, 0.13), cf * CF(-w / 2 + 0.6, 0.8, 0), { c = C3(220, 232, 234), m = M.Glass, t = 0.35 })
	K:box("SlideDoorHandle", V3(0.12, 1.6, 0.26), cf * CF(-w / 2 + 0.25, 0, 0), LK.chrome)
	K:box("SlideDoorRail", V3(w * 2.1, 0.14, 0.16), CFrame.fromMatrix(Vector3.new(d.mid.X, d.h + 0.05, d.mid.Z), d.dir, Vector3.yAxis, d.dir:Cross(Vector3.yAxis)) * CF(w * 0.5, 0, sd * 0.32), LK.alu)
	return leaf
end

-- 액자 테두리만 (맵 표지 둘레)
local function frameAround(K: any, r: any, wn: string, fr: any?)
	local V = K.V
	local u = wallU(wn, r.c)
	local w = math.max(r.size.X, r.size.Z) + 0.18
	local h = r.size.Y + 0.18
	local d = V:wall(wn, u, r.c.Y, 0)
	local _, dist = V:wallCoord(wn, r.c)
	d = d * CF(0, 0, math.max(0, dist - 0.05))
	local L = fr or lk(150, 120, 80, M.Wood)
	K:free(function()
		K:plate("FrameTop", w, 0.12, 0.14, d * CF(0, h / 2 - 0.06, 0), L)
		K:plate("FrameBot", w, 0.12, 0.14, d * CF(0, -h / 2 + 0.06, 0), L)
		K:plate("FrameL", 0.12, h - 0.24, 0.14, d * CF(-w / 2 + 0.06, 0, 0), L)
		K:plate("FrameR", 0.12, h - 0.24, 0.14, d * CF(w / 2 - 0.06, 0, 0), L)
	end)
end

-- 흉부 X-ray 필름 (판 dcf 위, w x h): 어두운 판 + 갈비뼈 · 척추 · 폐 · 심장
local function xrayFilm(K: any, dcf: CFrame, w: number, h: number): { BasePart }
	local out = {}
	local bone = { c = C3(230, 236, 240), m = M.SmoothPlastic }
	table.insert(out, K:plate("XrayFilm", w, h, 0.02, dcf, col(C3(30, 34, 40))))
	for _, sx in { -1, 1 } do
		table.insert(out, K:ell("XrayLung", V3(w * 0.34, h * 0.62, 0.02), dcf * CF(sx * w * 0.2, h * 0.02, 0.025), col(C3(60, 66, 74))))
		for i = 0, 6 do
			local y = h * 0.3 - i * h * 0.085
			local p = K:plate("XrayRib", w * 0.32, 0.05, 0.035, dcf * CF(sx * w * 0.19, y, 0.02) * ANG(0, 0, sx * math.rad(-14 - i * 2)), bone)
			table.insert(out, p)
		end
		table.insert(out, K:plate("XrayClavicle", w * 0.3, 0.07, 0.035, dcf * CF(sx * w * 0.16, h * 0.38, 0.02) * ANG(0, 0, sx * math.rad(8)), bone))
	end
	table.insert(out, K:plate("XraySpine", w * 0.07, h * 0.82, 0.035, dcf * CF(0, -h * 0.02, 0.02), bone))
	table.insert(out, K:ell("XrayHeart", V3(w * 0.26, h * 0.26, 0.03), dcf * CF(w * 0.06, -h * 0.12, 0.03), col(C3(200, 206, 212))))
	tx(K, "XrayLabel", w * 0.4, h * 0.06, dcf * CF(-w * 0.28, h * 0.45, 0.04), "PA  R", C3(220, 220, 220), nil, { d = 0.005 })
	return out
end

-- 1F 진료실 1 · 내과 -----------------------------------------------------------------------------------------------
BUILD.consult = function(K: any, V: any)
	-- 초음파실 칸막이 (빈 서쪽 절반 앞쪽): x = xp 선과 z = zp 선
	local xp, zp = 5.6, 0.6
	step(K, "ceiling", function()
		ceilingKit(K, V, { lights = 5 })
	end)
	step(K, "floor", function()
		floorKit(K, V, { look = lk(196, 170, 136, M.WoodPlanks), grout = lk(150, 126, 96), tile = 1.4, plank = true })
		baseKit(K, V, { "back", "left", "right", "front" })
	end)
	step(K, "usroom", function()
		local dz = partition(K, Vector3.new(V.x1, 0, zp), Vector3.new(xp, 0, zp), { { 9.6, 13.0, 7.6 } })
		partition(K, Vector3.new(xp, 0, zp + 0.225), Vector3.new(xp, 0, V.z0))
		local d = dz[1]
		if d then
			-- 문 (반쯤 열림) + 문 위 표지 + 검사 중 등
			slideDoor(K, d, 0.55, 1)
			local sc = faceCF(Vector3.new(d.mid.X, 8.6, zp + 0.24), Vector3.zAxis)
			roomSign(K, sc, 4.0, 1.0, "초음파실", "ULTRASOUND")
			K:box("UsLampBox", V3(1.6, 0.5, 0.2), (sc * CF(0, 1.0, 0.1)), LK.black)
			tx(K, "UsLamp", 1.5, 0.42, sc * CF(0, 1.0, 0.205), "검사 중", C3(255, 70, 60), nil, { glow = 1.5, font = FONT_K, d = 0.01 })
		end
		-- 칸막이 바깥면 안내 포스터 (진료실 쪽 x < xp)
		local pc = faceCF(Vector3.new(xp - 0.24, 6.0, -6.5), -Vector3.xAxis)
		poster(K, pc, 3.2, 4.0, "복부 초음파 안내", "검사 8시간 전부터 금식\n물 · 커피 · 껌도 피해 주세요\n검사 시간 약 15분\n결과는 진료실에서 설명", WHITE, INK, TEAL, WHITE, 0.22)
		local pc2 = faceCF(Vector3.new(xp - 0.24, 6.0, -11.0), -Vector3.xAxis)
		poster(K, pc2, 3.2, 4.0, "위 · 대장 내시경 예약", "수면 내시경 가능 (보호자 동반)\n전날 저녁 9시 이후 금식\n장 정결제 복용 안내문 지참\n예약 : 접수창구", WHITE, INK, NAVY, WHITE, 0.22)
		-- 초음파실 안: 검사 침대 · 장비 · 의자 · 환자 모니터
		local bx, bz = (xp + V.x1) / 2 - 1.5, (V.z0 + zp) / 2 - 0.5
		local bed = CF(bx, 0, bz) * ANG(0, 0, 0)
		K:free(function()
			local L, W, top = 6.4, 2.8, 2.15
			K:box("UsBedBase", V3(W - 0.6, top - 0.6, L - 1.4), bed * CF(0, (top - 0.6) / 2, 0), lk(240, 240, 238))
			K:box("UsBedKick", V3(W - 0.8, 0.3, L - 1.6), bed * CF(0, 0.15, 0), lk(70, 74, 78))
			K:slab("UsBedPad", W, L - 2.0, 0.4, 0.16, bed * CF(0, top - 0.2, 1.0), lk(70, 110, 150, M.Leather))
			local hc = bed * CF(0, top - 0.4, -L / 2 + 2.0) * ANG(math.rad(-16), 0, 0)
			K:slab("UsBedBack", W, 2.0, 0.4, 0.16, hc * CF(0, 0.2, -1.0), lk(70, 110, 150, M.Leather))
			K:box("UsBedPaper", V3(W - 0.5, 0.012, L - 2.2), bed * CF(0, top + 0.006, 1.0), lk(248, 248, 242))
			K:box("UsBedTowel", V3(W - 0.4, 0.08, 0.9), bed * CF(0, top + 0.04, L / 2 - 0.8), lk(150, 196, 214, M.Fabric))
			K:ell("UsBedPillow", V3(1.8, 0.35, 0.9), hc * CF(0, 0.55, -1.4), lk(250, 250, 250, M.Fabric))
		end)
		-- 초음파 장비 (침대 오른쪽)
		local mp = CF(bx + 3.1, 0, bz - 1.0) * ANG(0, -PI / 2 + 0.35, 0)
		local scrLab, fan
		K:free(function()
			K:box("UsCartBase", V3(1.8, 0.5, 2.0), mp * CF(0, 0.35, 0), lk(220, 222, 224, M.Plastic))
			for _, sx in { -0.7, 0.7 } do
				for _, sz in { -0.8, 0.8 } do
					K:ball("UsCartWheel", 0.3, mp * CF(sx, 0.15, sz), LK.black)
				end
			end
			K:box("UsCartBody", V3(1.6, 2.2, 1.6), mp * CF(0, 1.7, -0.1), lk(236, 238, 238, M.Plastic))
			K:box("UsCartDesk", V3(2.2, 0.25, 1.7), mp * CF(0, 2.95, 0.15), lk(230, 232, 234, M.Plastic))
			K:box("UsKeyboard", V3(1.6, 0.06, 0.9), mp * CF(0, 3.11, 0.3) * ANG(math.rad(-8), 0, 0), lk(60, 64, 70, M.Plastic))
			K:ball("UsTrackball", 0.25, mp * CF(0, 3.18, 0.55), lk(80, 120, 180, M.Plastic))
			for i = -1, 1 do
				K:box("UsProbeHolder", V3(0.25, 0.4, 0.2), mp * CF(1.15, 2.8, i * 0.4), lk(200, 204, 206, M.Plastic))
				K:box("UsProbe", V3(0.12, 0.45, 0.16), mp * CF(1.15, 3.1, i * 0.4), lk(40, 44, 50, M.Plastic))
			end
			K:seg("UsProbeCable", (mp * CF(1.15, 3.3, 0)).Position, (mp * CF(0.9, 1.8, 0.7)).Position, 0.06, lk(60, 64, 70, M.Rubber))
			K:box("UsMonitorArm", V3(0.2, 1.4, 0.2), mp * CF(0, 3.75, -0.5), lk(200, 204, 206, M.Metal))
			local sc = mp * CF(0, 5.0, -0.35) * ANG(math.rad(-6), 0, 0)
			K:box("UsMonitor", V3(2.4, 1.7, 0.16), sc, lk(30, 32, 36))
			local _, l = tx(K, "UsScreen", 2.2, 1.5, sc * CF(0, 0, 0.085), "", C3(230, 230, 230), C3(6, 6, 8), { glow = 1.1, align = "Left", font = FONT_M })
			scrLab = l
			fan = {}
			for i = -2, 2 do
				local p = K:box("UsFan", V3(0.22, 0.95, 0.01), sc * CF(0.25 + i * 0.16, 0.05 - math.abs(i) * 0.06, 0.09) * ANG(0, 0, i * 0.2), col(C3(120, 120, 124)))
				table.insert(fan, p)
			end
			K:box("UsGelWarmer", V3(0.5, 0.6, 0.5), mp * CF(-0.8, 3.4, 0.4), lk(250, 250, 250, M.Plastic))
			K:vcyl("UsGel", 0.5, 0.18, mp * CF(-0.8, 3.75, 0.4), col(C3(90, 160, 230), M.Plastic))
			K:box("UsTissue", V3(0.6, 0.35, 0.4), mp * CF(-0.6, 3.25, -0.4), lk(250, 250, 250))
		end)
		local stp = CF(bx + 2.2, 0, bz + 1.0)
		if K:spot(stp, V3(1.6, 2.0, 1.6), 0) then
			rollStool(K, stp, 1.9, LK.vinylNavy)
		end
		-- 환자용 모니터 (벽, 침대에서 보임)
		local pm = wallSpot(K, "right", 3.2, 5.0, 7.2, wallU("right", Vector3.new(0, 0, bz)), 0.6)
		if pm then
			wallScreen(K, pm, 3.0, 1.7, "실시간 초음파 영상\n검사 중입니다", C3(6, 6, 8), C3(200, 200, 200), { glow = 0.8 })
		end
		if scrLab then
			local frames = {
				{ text = "  ABDOMEN   LIVER\n\n\n\n  15 cm   45 Hz   GN 52" },
				{ text = "  ABDOMEN   GB · CBD\n\n\n\n  12 cm   45 Hz   GN 50" },
				{ text = "  ABDOMEN   R KIDNEY\n\n\n\n  13 cm   45 Hz   GN 54" },
				{ text = "  ABDOMEN   PANCREAS\n\n\n\n  14 cm   45 Hz   GN 55" },
			}
			local i = 1
			local prt = fan and fan[3]
			if prt then
				Interact.prompt(K, prt, {
					action = "화면 바꾸기",
					object = "초음파 장비",
					fn = function()
						i = i % #frames + 1
						scrLab.Text = frames[i].text
						for k, p in fan do
							p.Size = V3(0.22, 0.75 + ((k + i) % 3) * 0.12, 0.01)
						end
					end,
				})
			end
			scrLab.Text = frames[1].text
		end
	end)
	-- 진찰대 + U 커튼 --------------------------------------------------------------------------
	step(K, "exambed", function()
		local seat
		for _, r in V.byName.BedSeat or {} do
			seat = r
		end
		if not seat then
			return
		end
		local bf, L, W = examCouch(K, V, seat, { vinyl = lk(70, 150, 150, M.Leather), stepSide = 1 })
		local footZ = (bf * CF(0, 0, -L / 2)).Position.Z
		local headZ = (bf * CF(0, 0, L / 2)).Position.Z
		local fz = math.min(footZ, headZ) - 1.4
		local hz = math.max(footZ, headZ) + 1.2
		local cx = -12.2
		local run = curtainRun(K, { Vector3.new(V.x0 + 0.2, 0, fz), Vector3.new(cx, 0, fz), Vector3.new(cx, 0, hz) }, 0.1)
		curtainToggle(K, { run }, run.tab, "진찰대 커튼", 0.1)
		K:free(function()
			K:bar("CurtainTrackEnd", Vector3.new(cx, V.H - 0.05, hz), Vector3.new(V.x0 + 0.2, V.H - 0.05, hz), 0.16, 0.1, LK.alu)
		end)
		Common.useCeil(K, cx, (fz + hz) / 2)
	end)
	-- 의사 책상 ---------------------------------------------------------------------------------
	step(K, "desk", function()
		local top = V:first("DeskTop")
		local body = V:first("DeskBody")
		if not top then
			return
		end
		hideNames(K, { "Monitor", "MonitorFoot", "Keyboard" })
		local ty = top.max.Y + 0.005
		local cx = (top.min.X + top.max.X) / 2
		-- 환자 쪽 가림판
		if body then
			local d = faceCF(Vector3.new(cx, 0, body.max.Z + 0.01), Vector3.zAxis)
			K:free(function()
				K:plate("DeskModesty", body.size.X, body.size.Y, 0.03, d * CF(0, body.min.Y + body.size.Y / 2, 0), lk(242, 242, 238))
				K:plate("DeskModestyBand", body.size.X, 0.14, 0.04, d * CF(0, body.max.Y - 0.3, 0), col(TEAL))
			end)
		end
		local zm = top.max.Z - 1.35
		deskMonitor(K, CF(cx - 2.4, ty, zm) * ANG(0, PI, 0), 2.6, "EMR · 진료 차트\n홍*동 (M/54)  초진\nBP 118/76  BT 36.6\nC.C. 속쓰림 · 소화불량\nRx  PPI 2주 · 위내시경 예약", C3(240, 246, 248), C3(30, 50, 60), { align = "Left" })
		local pcfP = CF(cx + 1.5, ty, zm) * ANG(0, PI - 0.45, 0)
		deskMonitor(K, pcfP, 2.6, "", C3(10, 10, 12), C3(200, 200, 200), {})
		xrayFilm(K, pcfP * CF(0, 0.55 + 0.78, -0.16) * ANG(math.rad(-4), 0, 0) * CF(0, 0, 0.052), 1.4, 1.35)
		keyboard(K, CF(cx - 0.6, ty, top.min.Z + 1.0) * ANG(0, PI, 0), 1.8)
		-- 청진기 (말아 둠)
		local sp = CF(cx + 3.2, ty, top.min.Z + 1.2)
		K:ring("StethoTube", sp * CF(0, 0.04, 0) * ANG(PI / 2, 0, 0), 0.35, 0.07, 10, lk(30, 30, 34, M.Rubber))
		K:disc("StethoHead", 0.3, 0.08, sp * CF(0.45, 0.05, 0.2), LK.chrome)
		K:seg("StethoEar", (sp * CF(-0.2, 0.05, -0.3)).Position, (sp * CF(-0.55, 0.05, -0.55)).Position, 0.05, LK.chrome)
		-- 설압자 통 · 알콜솜 통 · 체온계 · 펜라이트
		local jc = CF(top.max.X - 0.7, ty, top.min.Z + 0.6)
		K:vcyl("DepressorJar", 0.7, 0.42, jc * CF(0, 0.35, 0), { c = C3(230, 240, 244), m = M.Glass, t = 0.45 })
		for i = 0, 5 do
			local a = i * 1.05
			K:box("Depressor", V3(0.07, 0.95, 0.02), jc * CF(math.cos(a) * 0.08, 0.6, math.sin(a) * 0.08) * ANG(math.sin(a) * 0.15, a, math.cos(a) * 0.15), lk(222, 196, 150, M.Wood))
		end
		K:vcyl("CottonJar", 0.5, 0.5, jc * CF(-0.75, 0.25, 0), LK.steel)
		K:vcyl("CottonJarLid", 0.06, 0.54, jc * CF(-0.75, 0.53, 0), LK.chrome)
		K:box("Thermometer", V3(0.22, 0.12, 0.6), jc * CF(-1.4, 0.06, 0.1), lk(240, 240, 240, M.Plastic))
		K:box("PenLight", V3(0.06, 0.06, 0.6), jc * CF(-1.8, 0.03, 0.1), LK.chrome)
		penCup(K, CF(top.min.X + 0.6, ty, top.min.Z + 0.5))
		Props.cardTerminal(K, CF(top.min.X + 1.4, ty, top.max.Z - 0.6))
		-- 위 · 심장 모형 (책상 모서리)
		local mc = CF(top.min.X + 1.0, ty, zm - 0.2)
		K:box("ModelBase", V3(0.7, 0.08, 0.6), mc * CF(0, 0.04, 0), LK.black)
		K:vcyl("ModelRod", 0.5, 0.06, mc * CF(0, 0.3, 0), LK.chrome)
		K:ell("ModelStomach", V3(0.7, 0.5, 0.35), mc * CF(0, 0.75, 0) * ANG(0, 0, 0.5), col(C3(220, 120, 120), M.SmoothPlastic))
		K:ell("ModelLiver", V3(0.6, 0.3, 0.32), mc * CF(-0.25, 0.92, 0.02), col(C3(150, 60, 50), M.SmoothPlastic))
		-- 의사 의자 (리그가 앉는 자리 그대로)
		for _, ch in V.chairs do
			if ch.seat.name == "ChairSeat" then
				hideList(K, ch.parts)
				K:free(function()
					officeChair(K, CF(ch.c.X, 0, ch.c.Z), ch.top, { backH = 2.7 })
				end)
			elseif ch.seat.name == "Seat" then
				-- 환자 의자 (Seat 은 숨겨도 앉기 그대로)
				hideList(K, ch.parts)
				K:free(function()
					armChair(K, faceCF(Vector3.new(ch.c.X, 0, ch.c.Z), ch.face), ch.top, LK.vinylTeal)
				end)
			end
		end
		-- 보호자 의자
		local gp = CF(cx - 4.0, 0, top.max.Z + 3.4) * ANG(0, PI - 0.4, 0)
		if K:spot(gp, V3(2.0, 3.6, 1.9), 0) then
			armChair(K, gp, 1.85, LK.vinylGrey)
		end
	end)
	-- 의사 뒤 낮은 수납장 (창 아래) ------------------------------------------------------------
	step(K, "credenza", function()
		local pcf = floorAt(K, -3.4, V.z0 + 1.15 + 0.75, 0, 11.0, 1.5, 2.9, 0)
		if not pcf then
			note(K, "credenza: no spot")
			return
		end
		K:box("CredenzaBody", V3(11.0, 2.7, 1.5), pcf * CF(0, 1.45, 0), lk(232, 220, 200, M.Wood))
		K:box("CredenzaTop", V3(11.2, 0.12, 1.6), pcf * CF(0, 2.86, 0), lk(196, 170, 136, M.Wood))
		K:box("CredenzaKick", V3(10.8, 0.1, 1.3), pcf * CF(0, 0.05, -0.05), lk(70, 74, 78))
		for i = 0, 3 do
			local x = -11.0 / 2 + 1.375 + i * 2.75
			K:plate("CredenzaDoor", 2.65, 2.5, 0.03, pcf * CF(x, 1.45, 0.75), lk(238, 228, 210, M.Wood))
			K:plate("CredenzaPull", 0.08, 0.7, 0.05, pcf * CF(x + (if i % 2 == 0 then 1.1 else -1.1), 1.9, 0.78), LK.chrome)
		end
		local tp = pcf * CF(0, 2.92, 0)
		Props.row(K, tp * CF(-3.6, 0, -0.1), 3.0, "books", { colors = { C3(30, 60, 120), C3(140, 30, 40), C3(40, 90, 70), C3(200, 180, 140) }, seed = 11 })
		binderRow(K, tp * CF(-0.6, 0, -0.1), 6, { C3(0, 128, 118), C3(240, 240, 236), C3(30, 60, 120) }, { "검사", "결과", "공문", "보험", "약품", "교육" })
		-- 인체 모형 (상반신)
		local tc = tp * CF(2.6, 0, -0.1)
		K:box("TorsoBase", V3(0.9, 0.12, 0.7), tc * CF(0, 0.06, 0), LK.black)
		K:ell("TorsoBody", V3(0.85, 1.5, 0.5), tc * CF(0, 0.9, 0), col(C3(230, 200, 176)))
		K:ell("TorsoOrgans", V3(0.5, 0.8, 0.05), tc * CF(0.1, 0.9, 0.24), col(C3(200, 90, 90)))
		K:ball("TorsoHead", 0.55, tc * CF(0, 1.9, 0), col(C3(230, 200, 176)))
		Props.potPlant(K, tp * CF(4.6, 0, 0), 0.6, 1.1, { pot = lk(240, 240, 236) })
		-- 처방전 프린터
		local pp = tp * CF(1.2, 0, 0)
		K:rbox("RxPrinter", V3(1.5, 0.7, 1.1), 0.08, pp * CF(0, 0.35, 0) * ANG(0, PI / 2, 0), lk(60, 64, 70, M.Plastic))
		K:box("RxPaper", V3(1.0, 0.04, 0.5), pp * CF(0, 0.72, 0.4) * ANG(math.rad(12), 0, 0), Look.paper)
	end)
	-- 벽 진단 세트 (원래 자리) · 체중계 · 혈압 트롤리 -------------------------------------------
	step(K, "diag", function()
		local unit = V:first("OtoscopeUnit")
		if unit then
			hideNames(K, { "OtoscopeUnit", "Otoscope" })
			local d = faceCF(Vector3.new(V.x0 + 0.01, unit.c.Y - 0.2, unit.c.Z), Vector3.xAxis)
			K:free(function()
				K:plate("DiagBoard", 2.8, 1.9, 0.08, d, lk(220, 224, 226, M.Plastic))
				K:plate("DiagTransformer", 1.1, 0.7, 0.3, d * CF(0, 0.45, 0.08), lk(70, 76, 82, M.Plastic))
				K:plate("DiagLED", 0.18, 0.06, 0.02, d * CF(0.3, 0.6, 0.39), col(C3(60, 230, 120), M.Neon))
				for i, sx in { -0.9, 0.9 } do
					local hc = d * CF(sx, -0.25, 0.3)
					K:box("DiagCradle", V3(0.36, 0.5, 0.32), hc * CF(0, -0.2, -0.05), lk(60, 64, 70, M.Plastic))
					K:vcyl("DiagHandle", 1.0, 0.24, hc * CF(0, 0.15, 0.05), LK.black)
					K:box("DiagHead", V3(0.36, 0.36, 0.3), hc * CF(0, 0.75, 0.05), if i == 1 then lk(30, 30, 34) else lk(40, 44, 50))
					K:cyl("DiagSpec", 0.3, 0.14, hc * CF(0, 0.75, 0.3) * ANG(0, PI / 2, 0), lk(250, 250, 250, M.Plastic))
					K:ring("DiagCord", hc * CF(0, -0.6, 0.02), 0.18, 0.05, 8, LK.black)
				end
				K:plate("SpecDispenser", 0.6, 0.9, 0.35, d * CF(1.75, 0, 0), lk(240, 240, 240, M.Plastic))
				tx(K, "DiagLabel", 2.6, 0.22, d * CF(0, -0.85, 0.085), "이경 · 검안경 진단 세트", INK, nil, { font = FONT_M })
			end)
		end
		local sc = V:first("Scale")
		if sc then
			hideNames(K, { "Scale", "ScaleColumn", "ScaleDisplay" })
			local p = faceCF(Vector3.new(sc.c.X, 0, sc.c.Z), Vector3.xAxis)
			K:free(function()
				K:box("ScalePlatform", V3(2.0, 0.25, 2.0), p * CF(0, 0.125, 0.1), lk(236, 238, 238, M.Plastic))
				K:box("ScaleMat", V3(1.6, 0.03, 1.6), p * CF(0, 0.26, 0.15), lk(60, 64, 70, M.Rubber))
				K:box("ScaleColumn", V3(0.35, 6.4, 0.3), p * CF(0, 3.45, -0.85), lk(236, 238, 238, M.Plastic))
				K:box("ScaleRule", V3(0.12, 4.0, 0.02), p * CF(0, 4.2, -0.69), lk(240, 210, 60))
				K:box("ScaleHeadBar", V3(0.3, 0.12, 1.0), p * CF(0, 5.6, -0.35), lk(40, 44, 50, M.Plastic))
				K:box("ScaleHead", V3(1.4, 0.9, 0.3), p * CF(0, 6.9, -0.82), lk(236, 238, 238, M.Plastic))
				tx(K, "ScaleLCD", 1.1, 0.5, p * CF(0, 6.95, -0.66), "0.0 kg\n--- cm", C3(60, 230, 140), C3(10, 26, 20), { glow = 1.2, d = 0.01 })
			end)
		end
		local bp = V:first("TrolleyBase")
		if bp then
			hideNames(K, { "TrolleyBase", "TrolleyPole", "TrolleyTop", "BPUnit", "BPCuff" })
			local p = faceCF(Vector3.new(bp.c.X, 0, bp.c.Z), Vector3.new(-1, 0, 0.6))
			K:free(function()
				for i = 0, 4 do
					local a = i * 2 * PI / 5
					K:seg("VitalLeg", (p * CF(0, 0.25, 0)).Position, (p * CF(math.cos(a) * 0.9, 0.18, math.sin(a) * 0.9)).Position, 0.1, lk(200, 204, 206, M.Metal))
					K:ball("VitalCaster", 0.2, p * CF(math.cos(a) * 0.9, 0.1, math.sin(a) * 0.9), LK.black)
				end
				K:vcyl("VitalPole", 3.4, 0.14, p * CF(0, 1.95, 0), LK.chrome)
				K:box("VitalBasket", V3(1.0, 0.4, 0.7), p * CF(0, 2.6, 0.35), LK.alu)
				K:box("VitalCuff", V3(0.8, 0.25, 0.5), p * CF(0, 2.8, 0.35), lk(40, 70, 130, M.Fabric))
				local mc = p * CF(0, 4.05, 0.1) * ANG(math.rad(-8), 0, 0)
				K:box("VitalMonitor", V3(1.6, 1.2, 0.5), mc, lk(240, 240, 238, M.Plastic))
				tx(K, "VitalScreen", 1.35, 0.95, mc * CF(0, 0.05, 0.255), "NIBP 120/78\nSpO2 98%\nHR 72   BT 36.5", C3(80, 255, 160), C3(6, 16, 14), { glow = 1.3, d = 0.01, align = "Left" })
				K:seg("VitalHose", (mc * CF(0.7, -0.5, 0.1)).Position, (p * CF(0.3, 2.85, 0.35)).Position, 0.05, lk(40, 40, 44, M.Rubber))
			end)
		end
	end)
	-- 손 세정대 (원래 자리, 뒤 빈틈은 배관 벽으로) · 의료폐기물 · 휴지통 ------------------------------
	step(K, "sink", function()
		local cab = V:first("SinkCabinet")
		if cab then
			hideNames(K, { "SinkCabinet", "SinkTop", "Sink", "Tap", "Mirror", "PaperTowel" })
			local pcf, w, d, h = recFrame(cab, -Vector3.zAxis)
			pcf = CF(cab.c.X, 0, cab.c.Z) * ANG(0, PI, 0)
			sinkUnit(K, pcf, w, d, h, { dispensers = false })
			-- 배관 벽 (캐비닛 뒤 ~ 진료실 벽)
			local back = cab.max.Z
			local depth = V.z1 - back
			if depth > 0.2 then
				K:free(function()
					K:box("SinkChase", V3(w + 0.1, 5.2, depth), CF(cab.c.X, 2.6, back + depth / 2), lk(240, 240, 236))
					local f = faceCF(Vector3.new(cab.c.X, 0, back - 0.005), -Vector3.zAxis)
					K:plate("SinkMirror", 2.6, 1.8, 0.04, f * CF(0.6, 4.25, 0), Look.mirror)
					soapDispenser(K, f * CF(-1.5, 4.6, 0))
					towelDispenser(K, f * CF(-1.5, 3.4, 0) * CF(0, 0, 0))
					sanitizerWall(K, f * CF(2.45, 4.4, 0))
				end)
			end
		end
		local mw = V:first("MedWasteBin")
		if mw then
			hideNames(K, { "MedWasteBin", "MedWasteLabel" })
			K:free(function()
				medWasteBox(K, faceCF(Vector3.new(mw.c.X, 0, mw.c.Z), -Vector3.zAxis), 1.6, 2.4)
			end)
		end
		local bn = V:first("Bin")
		if bn then
			hideRec(K, bn)
			K:free(function()
				pedalBin(K, faceCF(Vector3.new(bn.c.X, 0, bn.c.Z), -Vector3.zAxis), 2.2, "일반")
			end)
		end
		local sh = wallFloorNear(K, "front", wallU("front", Vector3.new(9.5, 0, 0)), 1.2, 1.0, 1.4, 1.5, 0)
		if sh then
			sharpsBox(K, sh)
		end
	end)
	-- 판독 라이트박스 (복도 쪽 벽) · 표지 액자 -------------------------------------------------
	step(K, "lightbox", function()
		local d = wallSpot(K, "front", 4.4, 4.2, 7.6, wallU("front", Vector3.new(-2.0, 0, 0)), 0.5)
		if not d then
			note(K, "lightbox: no wall")
			return
		end
		K:plate("LightBoxCase", 4.3, 3.2, 0.3, d, lk(230, 232, 232, M.Plastic))
		local glow = K:plate("LightBoxPanel", 4.0, 2.7, 0.02, d * CF(0, 0.1, 0.3), col(C3(150, 156, 160)))
		local film = xrayFilm(K, d * CF(-1.0, 0.1, 0.33), 1.8, 2.4)
		local film2 = xrayFilm(K, d * CF(1.0, 0.1, 0.33), 1.8, 2.4)
		K:plate("LightBoxSwitch", 0.3, 0.2, 0.05, d * CF(1.7, -1.35, 0.3), lk(60, 200, 120, M.Plastic))
		local lit = { glow }
		Interact.toggle(K, glow, {
			object = "X-ray 판독 라이트박스",
			state = false,
			onText = "끄기",
			offText = "켜기",
			on = function(on: boolean)
				glow.Material = if on then M.Neon else M.SmoothPlastic
				glow.Color = if on then C3(236, 244, 255) else C3(150, 156, 160)
				for _, list in { film, film2 } do
					for _, p in list do
						if p.Name == "XrayFilm" then
							p.Transparency = if on then 0.25 else 0
						end
					end
				end
			end,
		})
		_ = lit
		for _, n in { "Sign_전문의 자격", "Sign_의사 면허증", "Sign_인체 해부도" } do
			local r = V:first(n)
			if r then
				frameAround(K, r, "front", lk(160, 130, 90, M.Wood))
			end
		end
		local s6 = V:first("Sign_손 씻기 6단계")
		if s6 then
			frameAround(K, s6, "right", LK.alu)
		end
	end)
	-- 벽: 손잡이 (복도 쪽), 혈압 분류 포스터, 시계는 공통 ------------------------------------------
	step(K, "walls", function()
		local d = wallSpot(K, "front", 3.0, 4.0, 6.2, wallU("front", Vector3.new(-6.5, 0, 0)), 0.6)
		if d then
			poster(K, d, 2.8, 2.0, "혈압 분류 (mmHg)", "정상  120 / 80 미만\n주의  120~129\n전단계  130~139 / 80~89\n고혈압  140 / 90 이상", WHITE, INK, C3(196, 40, 52), WHITE, 0.26)
		end
		local d2 = wallSpot(K, "left", 2.0, 3.4, 4.8, wallU("left", Vector3.new(0, 0, -9.0)), 0.6)
		if d2 then
			gloveHolder(K, d2, 3)
		end
	end)
end

-- 약 이름 (전문 · 일반의약품, 상자 색)
local DRUGS = {
	{ "아모잘탄", C3(200, 40, 60) }, { "노바스크", C3(40, 90, 170) }, { "리피토", C3(30, 120, 190) }, { "크레스토", C3(210, 80, 140) },
	{ "자누메트", C3(130, 60, 160) }, { "다이아벡스", C3(0, 140, 120) }, { "아스피린", C3(30, 140, 70) }, { "타이레놀", C3(220, 30, 40) },
	{ "부루펜", C3(240, 140, 30) }, { "록소닌", C3(60, 120, 200) }, { "무코스타", C3(0, 110, 160) }, { "가스모틴", C3(90, 160, 60) },
	{ "넥시움", C3(120, 40, 140) }, { "지르텍", C3(230, 120, 160) }, { "코대원", C3(200, 160, 30) }, { "시네츄라", C3(70, 150, 90) },
	{ "뮤코펙트", C3(40, 160, 200) }, { "오구멘틴", C3(220, 100, 40) }, { "세파클러", C3(160, 40, 50) }, { "판콜에이", C3(30, 80, 160) },
	{ "베아제", C3(40, 150, 60) }, { "훼스탈", C3(240, 190, 30) }, { "게보린", C3(240, 110, 30) }, { "판피린", C3(250, 210, 40) },
	{ "스멕타", C3(80, 120, 200) }, { "마그밀", C3(60, 170, 200) }, { "우루사", C3(30, 70, 140) }, { "인사돌", C3(180, 50, 50) },
}

-- 1F 약국 코너 (조제실) ----------------------------------------------------------------------------------------
BUILD.pharmacy = function(K: any, V: any)
	step(K, "ceiling", function()
		ceilingKit(K, V, { lights = 6 })
	end)
	step(K, "floor", function()
		floorKit(K, V, { look = lk(204, 206, 204, M.SmoothPlastic), grout = lk(170, 172, 170), tile = 2.04 })
		baseKit(K, V, { "back", "left", "right", "front" })
	end)
	-- 약품 진열장 다시 채우기 (맵 상자 · 가격표 숨김) ---------------------------------------------------
	step(K, "shelf", function()
		local boards = V.byName.Board or {}
		if #boards == 0 then
			return
		end
		hideNames(K, { "Product", "PriceRail" })
		local r = rng(31)
		local x0, x1 = math.huge, -math.huge
		local fz = -math.huge
		for _, b in boards do
			x0 = math.min(x0, b.min.X)
			x1 = math.max(x1, b.max.X)
			fz = math.max(fz, b.max.Z)
		end
		table.sort(boards, function(a, b)
			return a.max.Y < b.max.Y
		end)
		local labN = 0
		for li, b in boards do
			local y = b.max.Y
			local nextB = boards[li + 1]
			local room = if nextB then nextB.min.Y - y - 0.12 else 1.4
			-- 가격 · 위치 레일 (선반 앞 띠)
			K:free(function()
				K:box("ShelfLabelRail", V3(x1 - x0, 0.22, 0.05), CF((x0 + x1) / 2, y - 0.1, fz + 0.03), lk(250, 250, 248))
				tx(K, "ShelfLabelRailText", math.min(10, x1 - x0 - 1), 0.18, faceCF(Vector3.new((x0 + x1) / 2, y - 0.1, fz + 0.06), Vector3.zAxis), string.format("%d단 ·  %s", li, ({ "소화기계 · 위장약", "순환기 · 혈압 · 고지혈", "당뇨 · 내분비", "호흡기 · 항생제", "해열진통 · 소염", "외용 · 기타" })[li] or "기타"), GREY_T, nil, { font = FONT_M, d = 0.005, align = "Left" })
			end)
			local x = x0 + 0.15
			while x < x1 - 0.5 do
				local kind = r()
				local w = 0.55 + r() * 0.55
				if x + w > x1 - 0.1 then
					break
				end
				local cx = x + w / 2
				local base = CF(cx, y, fz - 0.65)
				K:free(function()
					if kind < 0.18 then
						-- 약병 (흰 HDPE + 색 뚜껑) 2개
						local cap = DRUGS[math.floor(r() * #DRUGS) + 1][2]
						for k = 0, 1 do
							local bp = base * CF(-w / 4 + k * w / 2, 0, 0.1)
							local h = math.min(room - 0.1, 0.75 + r() * 0.2)
							K:vcyl("PillBottle", h, math.min(0.42, w / 2 - 0.02), bp * CF(0, h / 2, 0), lk(246, 246, 242, M.Plastic))
							K:vcyl("PillBottleCap", 0.14, math.min(0.36, w / 2 - 0.06), bp * CF(0, h + 0.07, 0), col(cap, M.Plastic))
						end
					else
						local dg = DRUGS[math.floor(r() * #DRUGS) + 1]
						local h = math.min(room - 0.08, 0.55 + r() * 0.5)
						local d = 0.9 + r() * 0.3
						local white = r() < 0.55
						if r() < 0.62 and w > 0.62 then
							labN += 1
							medBox(K, base * CF(0, 0, 0.6 - d / 2 + 0.05), w - 0.04, h, d, dg[2], dg[1], if white then dg[2] else nil, white)
						else
							K:box("MedBox", V3(w - 0.04, h, d), base * CF(0, h / 2, 0.6 - d / 2 + 0.05), col(if white then WHITE else dg[2]))
							K:box("MedBoxBand", V3(w - 0.03, h * 0.18, d + 0.01), base * CF(0, h * 0.7, 0.6 - d / 2 + 0.05), col(if white then dg[2] else WHITE))
						end
					end
				end)
				x += w + 0.05 + r() * 0.08
			end
		end
		note(K, "pharmacy labels " .. labN)
	end)
	-- 약품 서랍장 (뒷벽 왼쪽) + 열리는 서랍 ---------------------------------------------------------------
	step(K, "drawers", function()
		local bp = V:first("BackPanel")
		local xr = (if bp then bp.min.X else -12) - 0.6
		local xl = V.x0 + 0.6
		local w = math.min(15.0, xr - xl)
		if w < 4 then
			return
		end
		local cx = xr - w / 2
		local depth = 1.6
		local pcf = CF(cx, 0, V.z0 + depth)
		if not K:spot(CF(cx, 0, V.z0 + depth / 2), V3(w + 0.2, 6.9, depth), 0) then
			note(K, "drawers: blocked")
			return
		end
		local names = {}
		for _, dg in DRUGS do
			table.insert(names, dg[1])
		end
		local cols, rows = math.floor(w / 1.5), 7
		drawerBank(K, pcf, w, 6.3, depth, cols, rows, names, 5)
		K:box("DrawerTopSign", V3(w, 0.6, 0.1), pcf * CF(0, 6.95, -0.05), col(TEAL))
		tx(K, "DrawerTopSignText", w - 0.4, 0.45, pcf * CF(0, 6.95, 0.01), "조제실 약품장  ·  가나다 순", WHITE, nil, { font = FONT_K })
		-- 열리는 서랍 하나 (가운데 아래 줄)
		local cw, ch = w / cols, 6.3 / rows
		local dx = -w / 2 + (math.floor(cols / 2) + 0.5) * cw
		local dy = 0.15 + 2.5 * ch
		local drawer = K:group("PharmDrawer", function()
			K:box("DrawerOpenFront", V3(cw - 0.06, ch - 0.06, 0.06), pcf * CF(dx, dy, 0.045), lk(250, 250, 246))
			K:box("DrawerOpenPull", V3(cw * 0.5, 0.06, 0.08), pcf * CF(dx, dy - ch * 0.28, 0.1), LK.chrome)
			K:box("DrawerOpenBox", V3(cw - 0.12, ch - 0.16, 1.2), pcf * CF(dx, dy - 0.02, -0.58), lk(236, 238, 236))
			for k = 0, 5 do
				K:ball("DrawerPill", 0.16, pcf * CF(dx - 0.4 + (k % 3) * 0.4, dy - ch / 2 + 0.2, -0.3 - (k // 3) * 0.4), col(if k % 2 == 0 then C3(250, 250, 250) else C3(240, 180, 60)))
			end
			tx(K, "DrawerOpenTag", cw * 0.72, ch * 0.3, pcf * CF(dx, dy + ch * 0.12, 0.08), "타이레놀", INK, C3(255, 250, 220), { d = 0.008 })
		end)
		local parts = {}
		for _, d in drawer:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, { p = d, cf = d.CFrame })
			end
		end
		local front = drawer:FindFirstChild("DrawerOpenFront") :: BasePart?
		if front then
			Interact.toggle(K, front, {
				object = "약품 서랍",
				state = false,
				onText = "닫기",
				offText = "열기",
				sound = "rbxasset://sounds/clickfast.wav",
				on = function(open: boolean)
					local off = K.cf.LookVector * -(if open then 1.0 else 0)
					for _, q in parts do
						if q.p.Parent then
							TweenService:Create(q.p, TweenInfo.new(0.35), { CFrame = q.cf + off }):Play()
						end
					end
				end,
			})
		end
	end)
	-- 조제대 (가운데 섬) ------------------------------------------------------------------------------
	step(K, "bench", function()
		local pcf = floorAt(K, -2.0, -2.6, PI, 13.0, 3.2, 3.2, 0.3)
		if not pcf then
			note(K, "bench: no spot")
			return
		end
		local h = 3.0
		K:box("BenchBody", V3(12.8, h - 0.4, 3.0), pcf * CF(0, 0.3 + (h - 0.4) / 2, 0), lk(244, 244, 240))
		K:box("BenchKick", V3(12.4, 0.3, 2.6), pcf * CF(0, 0.15, 0), lk(70, 74, 78))
		K:box("BenchTop", V3(13.0, 0.14, 3.2), pcf * CF(0, h - 0.03, 0), lk(232, 232, 228, M.Marble))
		for i = 0, 5 do
			for _, sd in { 1, -1 } do
				local x = -6.4 + 1.07 * (i * 2 + 1)
				local dc = pcf * CF(x, 2.1, sd * 1.505) * (if sd < 0 then ANG(0, PI, 0) else CF())
				K:plate("BenchDrawer", 2.0, 0.7, 0.03, dc, lk(236, 238, 236))
				K:plate("BenchDrawerPull", 0.7, 0.07, 0.05, dc * CF(0, 0.15, 0.03), LK.chrome)
				K:plate("BenchDoor", 2.0, 1.3, 0.03, dc * CF(0, -1.05, 0), lk(236, 238, 236))
			end
		end
		local ty = h + 0.04
		-- 조제 화면 + 키보드
		deskMonitor(K, pcf * CF(-4.6, ty, -0.6), 2.2, "조제 대기 4건\n#0247 홍*동  3일분 x3\n#0248 김*희  5일분 x2\n#0249 이*수  7일분 x3", C3(236, 246, 244), C3(20, 60, 60), { align = "Left" })
		keyboard(K, pcf * CF(-4.6, ty, 0.6), 1.6)
		-- 전자저울 · 정제 계수 트레이 · 분할기 · 유발 · 약포지 롤 · 바구니
		local sc = pcf * CF(-1.6, ty, 0.2)
		K:box("ScaleBase", V3(1.0, 0.25, 1.1), sc * CF(0, 0.125, 0), lk(230, 232, 232, M.Plastic))
		K:disc("ScalePan", 0.8, 0.04, sc * CF(0, 0.27, -0.1), LK.steel)
		tx(K, "ScaleLCD", 0.6, 0.16, faceCF((sc * CF(0, 0.15, 0.56)).Position, pcf.ZVector), "0.250 g", C3(60, 230, 140), C3(10, 26, 20), { glow = 1.2, d = 0.005 })
		local ct = pcf * CF(0.3, ty, 0.3)
		K:box("CountTray", V3(1.4, 0.08, 1.0), ct * CF(0, 0.04, 0), lk(80, 150, 200, M.Plastic))
		K:box("CountTrayChute", V3(0.3, 0.12, 0.5), ct * CF(0.55, 0.08, -0.2), lk(80, 150, 200, M.Plastic))
		for k = 0, 8 do
			K:ball("CountPill", 0.13, ct * CF(-0.45 + (k % 5) * 0.2, 0.12, -0.2 + (k // 5) * 0.25), col(C3(250, 250, 250)))
		end
		K:box("Spatula", V3(0.12, 0.02, 0.9), ct * CF(-0.2, 0.12, 0.25) * ANG(0, 0.4, 0), LK.steel)
		local mp = pcf * CF(2.0, ty, 0.4)
		K:vcyl("Mortar", 0.35, 0.7, mp * CF(0, 0.17, 0), lk(244, 244, 240, M.Marble))
		K:seg("Pestle", (mp * CF(0, 0.3, 0)).Position, (mp * CF(0.25, 0.85, 0.1)).Position, 0.14, lk(244, 244, 240, M.Marble))
		local rp = pcf * CF(3.6, ty, -0.6)
		K:cyl("PouchRoll", 1.2, 0.8, rp * CF(0, 0.45, 0), lk(250, 250, 248))
		K:box("PouchRollStand", V3(1.4, 0.06, 0.6), rp * CF(0, 0.03, 0), LK.alu)
		K:box("PouchStrip", V3(0.9, 0.01, 1.4), rp * CF(0, 0.02, 0.9), lk(250, 250, 246))
		for k = 0, 2 do
			K:box("PouchPrint", V3(0.7, 0.012, 0.3), rp * CF(0, 0.026, 0.4 + k * 0.45), lk(200, 220, 240))
		end
		for k, c in { C3(240, 120, 60), C3(80, 160, 220), C3(110, 190, 110) } do
			local bk = pcf * CF(4.9, ty, 0.9 - k * 0.6)
			K:box("RxBasket", V3(1.1, 0.35, 0.55), bk * CF(0, 0.18, 0), col(c, M.Plastic))
			K:box("RxSlip", V3(0.8, 0.02, 0.4), bk * CF(0, 0.37, 0), Look.paper)
		end
		K:vcyl("BenchSanitizer", 0.55, 0.3, pcf * CF(-6.0, ty + 0.27, 0.9), { c = C3(220, 240, 250), m = M.Glass, t = 0.3 })
		K:vcyl("BenchSanitizerPump", 0.18, 0.14, pcf * CF(-6.0, ty + 0.64, 0.9), lk(250, 250, 250))
		-- 약봉투 상자
		K:box("BagBox", V3(1.4, 0.7, 1.0), pcf * CF(-3.0, ty + 0.35, 0.7), LK.cardboard)
		K:box("BagStack", V3(1.1, 0.25, 0.8), pcf * CF(-3.0, ty + 0.8, 0.7), lk(250, 250, 246))
		tx(K, "BagLabel", 1.0, 0.3, faceCF((pcf * CF(-3.0, ty + 0.35, 1.21)).Position, pcf.ZVector), "약봉투", INK, nil, { d = 0.005 })
		-- 의자 (조제대 앞)
		local sp = pcf * CF(-4.6, 0, 2.6) * ANG(0, PI, 0)
		if K:spot(sp, V3(2.0, 3.5, 2.0), 0) then
			officeChair(K, sp, 1.9, { backH = 1.8 })
		end
	end)
	-- 자동 약포장기 (원래 자리) ---------------------------------------------------------------------
	step(K, "atc", function()
		local m = V:first("DispensingMachine")
		if not m then
			return
		end
		hideNames(K, { "DispensingMachine", "DispenserScreen", "DispenserOutlet" })
		local pcf = faceCF(Vector3.new(m.c.X, 0, m.c.Z), Vector3.zAxis)
		local w, d, h = m.size.X, m.size.Z, m.size.Y
		local strip, lab, lamp
		K:free(function()
			K:box("ATCBody", V3(w, h, d), pcf * CF(0, h / 2, 0), lk(242, 244, 244, M.Plastic))
			K:box("ATCHeader", V3(w, 0.7, 0.05), pcf * CF(0, h - 0.45, d / 2), col(TEAL))
			tx(K, "ATCHeaderText", w - 0.4, 0.5, pcf * CF(0, h - 0.45, d / 2 + 0.03), "ATC 전자동 약포장기", WHITE, nil, { font = FONT_K })
			-- 창 안 카세트 격자
			local ww, wh = w - 1.9, h - 2.6
			local wc = pcf * CF(-0.6, 1.4 + wh / 2, d / 2)
			K:box("ATCWindowBack", V3(ww, wh, 0.05), wc * CF(0, 0, -0.5), lk(60, 64, 70))
			local nc, nr = 9, 7
			local cs = { C3(240, 240, 236), C3(250, 220, 120), C3(200, 230, 250), C3(250, 200, 200) }
			for i = 0, nc - 1 do
				for j = 0, nr - 1 do
					K:box("ATCCanister", V3(ww / nc - 0.08, wh / nr - 0.1, 0.35), wc * CF(-ww / 2 + (i + 0.5) * ww / nc, -wh / 2 + (j + 0.5) * wh / nr, -0.3), col(cs[(i * 3 + j) % #cs + 1], M.Plastic))
				end
			end
			K:box("ATCWindow", V3(ww + 0.1, wh + 0.1, 0.04), wc * CF(0, 0, 0.02), { c = C3(220, 236, 240), m = M.Glass, t = 0.65, r = 0.15 })
			K:box("ATCWindowFrame", V3(ww + 0.25, 0.1, 0.08), wc * CF(0, wh / 2 + 0.05, 0.02), LK.alu)
			K:box("ATCWindowFrame", V3(ww + 0.25, 0.1, 0.08), wc * CF(0, -wh / 2 - 0.05, 0.02), LK.alu)
			-- 화면
			local sc = pcf * CF(w / 2 - 0.75, h - 2.3, d / 2 + 0.02)
			K:box("ATCScreenBezel", V3(1.2, 0.95, 0.06), sc, LK.black)
			local _, l = tx(K, "ATCScreen", 1.05, 0.8, sc * CF(0, 0, 0.035), "대기\n#0248\n5일분", C3(220, 250, 240), C3(10, 60, 60), { glow = 1.2, d = 0.01 })
			lab = l
			-- 신호등
			K:vcyl("ATCLampPole", 0.5, 0.08, pcf * CF(w / 2 - 0.3, h + 0.25, d / 2 - 0.3), LK.chrome)
			lamp = K:vcyl("ATCLamp", 0.3, 0.24, pcf * CF(w / 2 - 0.3, h + 0.65, d / 2 - 0.3), col(C3(60, 220, 120), M.Neon))
			-- 배출구 + 약포지 줄
			K:box("ATCOutlet", V3(2.2, 0.8, 0.5), pcf * CF(-0.6, 0.9, d / 2 + 0.2), lk(200, 204, 206, M.Plastic))
			K:box("ATCOutletSlot", V3(1.6, 0.08, 0.06), pcf * CF(-0.6, 1.15, d / 2 + 0.46), LK.black)
			strip = K:box("ATCPouchStrip", V3(1.0, 0.02, 0.3), pcf * CF(-0.6, 1.1, d / 2 + 0.6), lk(250, 250, 246))
			K:box("ATCTray", V3(2.0, 0.08, 1.2), pcf * CF(-0.6, 0.55, d / 2 + 0.8), lk(200, 206, 210, M.Plastic))
		end)
		if strip and lab and lamp then
			local s0 = strip.CFrame
			local busy = false
			Interact.prompt(K, lab.Parent and (lab.Parent :: any).Parent or strip, {
				action = "조제 시작",
				object = "자동 약포장기",
				fn = function()
					if busy then
						return
					end
					busy = true
					lamp.Color = C3(255, 190, 40)
					lab.Text = "조제 중\n#0248\n▶▶▶"
					strip.Size = V3(1.0, 0.02, 0.3)
					strip.CFrame = s0
					TweenService:Create(strip, TweenInfo.new(4, Enum.EasingStyle.Linear), { Size = V3(1.0, 0.02, 1.4), CFrame = s0 * CF(0, -0.35, 0.55) * ANG(math.rad(-30), 0, 0) }):Play()
					task.delay(4.2, function()
						if lab.Parent then
							lab.Text = "완료\n#0248\n15포"
							lamp.Color = C3(60, 220, 120)
							ding(strip)
						end
						busy = false
					end)
				end,
			})
		end
	end)
	-- 백신 냉장고 (원래 자리, 유리문 열림) -----------------------------------------------------------
	step(K, "fridge", function()
		local f = V:first("VaccineFridge")
		if not f then
			return
		end
		hideNames(K, { "VaccineFridge", "FridgeGlass", "FridgeLabel" })
		local pcf = faceCF(Vector3.new(f.c.X, 0, f.c.Z), Vector3.zAxis)
		local w, d, h = f.size.X, f.size.Z, f.size.Y
		K:free(function()
			K:box("VacBody", V3(w, h, d - 0.15), pcf * CF(0, h / 2, -0.08), lk(246, 246, 244, M.Plastic))
			K:box("VacInner", V3(w - 0.4, h - 1.3, 0.05), pcf * CF(0, 0.5 + (h - 1.3) / 2, -d / 2 + 0.3), lk(236, 240, 242))
			local lampP = K:box("VacLamp", V3(w - 0.6, 0.05, 0.12), pcf * CF(0, h - 0.85, d / 2 - 0.4), col(C3(230, 244, 255), M.Neon))
			K:light(lampP, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 5, Brightness = 0.6, Angle = 120, Color = C3(230, 244, 255) })
			for i = 0, 3 do
				local y = 0.6 + i * (h - 1.5) / 4
				K:box("VacShelf", V3(w - 0.45, 0.04, d - 0.7), pcf * CF(0, y, -0.1), LK.alu)
				for k = 0, 4 do
					local bx = -w / 2 + 0.55 + k * (w - 1.0) / 4
					if (i + k) % 3 == 0 then
						for v = 0, 2 do
							K:vcyl("VacVial", 0.35, 0.16, pcf * CF(bx - 0.2 + v * 0.2, y + 0.2, 0.4), { c = C3(236, 244, 248), m = M.Glass, t = 0.3 })
						end
					else
						K:box("VacBox", V3(0.6, 0.45, 0.8), pcf * CF(bx, y + 0.24, 0.2), col(({ C3(250, 250, 248), C3(200, 230, 250), C3(250, 236, 200) })[(i + k) % 3 + 1]))
					end
				end
			end
			K:box("VacKick", V3(w, 0.5, 0.1), pcf * CF(0, 0.25, d / 2 - 0.1), lk(70, 74, 78, M.DiamondPlate))
			tx(K, "VacTemp", 1.0, 0.35, pcf * CF(0, h - 0.3, d / 2 - 0.08), "4.2°C", C3(255, 80, 60), C3(16, 16, 18), { glow = 1.4, d = 0.01 })
			tx(K, "VacLabel", w - 0.4, 0.35, pcf * CF(0, h - 0.65, d / 2 - 0.08), "백신 · 냉장 의약품  2~8°C", TEAL_D, nil, { font = FONT_B, d = 0.01 })
		end)
		local door = K:group("VacDoor", function()
			K:free(function()
				local dc = pcf * CF(0, 0.55 + (h - 1.1) / 2, d / 2 + 0.03)
				K:box("VacDoorFrame", V3(w - 0.1, h - 1.1, 0.12), dc, lk(240, 240, 238, M.Plastic))
				K:box("VacDoorGlass", V3(w - 0.5, h - 1.5, 0.06), dc * CF(0, 0, 0.04), { c = C3(214, 232, 238), m = M.Glass, t = 0.7, r = 0.15 })
				K:box("VacDoorHandle", V3(0.12, (h - 1.1) * 0.55, 0.14), dc * CF(w / 2 - 0.35, 0, 0.12), LK.chrome)
			end)
		end)
		local hinge = (K.cf * pcf * CF(-w / 2 + 0.05, 0, d / 2 + 0.03)).Position
		Interact.swing(K, door, hinge, (K.cf * pcf).UpVector, -math.rad(100), { object = "백신 냉장고", openText = "문 열기", closeText = "문 닫기" })
	end)
	-- 약사 컴퓨터 책상 (서쪽 벽) ----------------------------------------------------------------------
	step(K, "pcdesk", function()
		local pcf = wallFloorNear(K, "right", 0.0, 8.0, 3.2, 2.9, 4, 0)
		if not pcf then
			note(K, "pcdesk: no spot")
			return
		end
		K:box("PCDeskTop", V3(8.0, 0.14, 3.2), pcf * CF(0, 2.75, 0), lk(232, 220, 200, M.Wood))
		K:box("PCDeskPedestal", V3(2.2, 2.6, 3.0), pcf * CF(-2.8, 1.35, 0), lk(244, 244, 240))
		K:box("PCDeskPanel", V3(0.12, 2.6, 3.0), pcf * CF(3.9, 1.35, 0), lk(244, 244, 240))
		for k = 0, 2 do
			K:plate("PCDeskDrawer", 2.1, 0.75, 0.03, pcf * CF(-2.8, 0.55 + k * 0.85, 1.5), lk(236, 238, 236))
		end
		local ty = 2.82
		deskMonitor(K, pcf * CF(-1.4, ty, -0.6), 2.2, "처방전 접수\nQR 처방전 2건 대기\n보험 청구 · DUR 확인", C3(240, 246, 248), C3(30, 50, 60), { align = "Left" })
		deskMonitor(K, pcf * CF(1.1, ty, -0.6), 2.2, "DUR 점검\n병용금기 없음 ✓\n중복처방 없음 ✓", C3(240, 248, 240), C3(30, 80, 40), { align = "Left" })
		keyboard(K, pcf * CF(-0.2, ty, 0.6), 1.7)
		local lp = pcf * CF(3.0, ty, 0.2)
		K:rbox("LabelPrinter", V3(0.9, 0.7, 1.1), 0.1, lp * CF(0, 0.35, 0) * ANG(0, PI / 2, 0), lk(60, 64, 70, M.Plastic))
		K:box("LabelRoll", V3(0.5, 0.04, 0.4), lp * CF(0, 0.72, 0.4), lk(250, 250, 246))
		deskPhone(K, pcf * CF(-3.3, ty, 0.6))
		penCup(K, pcf * CF(-2.4, ty, 1.0))
		local cp = pcf * CF(0, 0, 2.3) * ANG(0, PI, 0)
		if K:spot(cp, V3(2.0, 3.5, 2.0), 0) then
			officeChair(K, cp, 1.9)
		end
	end)
	-- 약품 창고 선반 (동쪽 벽) · 손 씻는 곳 ---------------------------------------------------------
	step(K, "storage", function()
		local labels = { "생리식염수 1L × 10", "포도당 5% 500mL", "하트만 수액", "알콜솜 1,000매", "KF94 마스크 50매", "멸균거즈 4×4", "주사기 3cc", "약포지 롤 6개", "약봉투 소 2,000", "시럽병 60mL" }
		local n = 0
		for _, u in { 4.5, -2.5 } do
			local pcf = wallFloorNear(K, "left", u, 6.0, 1.8, 7.0, 2, 0)
			if pcf then
				n += 1
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						K:box("RackPost", V3(0.12, 7.0, 0.12), pcf * CF(sx * 2.95, 3.5, sz * 0.84), lk(170, 176, 180, M.Metal))
					end
				end
				for k = 0, 4 do
					local y = 0.3 + k * 1.6
					K:box("RackShelf", V3(6.0, 0.08, 1.8), pcf * CF(0, y, 0), lk(196, 200, 204, M.DiamondPlate))
					if k < 4 then
						for b = 0, 2 do
							local bw = 1.7
							local bh = 0.9 + ((k + b) % 3) * 0.2
							local bc = pcf * CF(-2.0 + b * 2.0, y + 0.04, 0.05)
							K:box("Carton", V3(bw, bh, 1.5), bc * CF(0, bh / 2, 0), LK.cardboard)
							K:box("CartonTape", V3(0.3, 0.02, 1.52), bc * CF(0, bh + 0.005, 0), lk(220, 200, 150))
							tx(K, "CartonLabel", bw - 0.3, 0.32, bc * CF(0, bh * 0.55, 0.755), labels[(n * 7 + k * 3 + b) % #labels + 1], INK, C3(250, 250, 246), { font = FONT_M, d = 0.006 })
						end
					end
				end
			end
		end
		local sk = wallFloorNear(K, "left", -8.0, 3.4, 2.2, 3.0, 2.5, 0)
		if sk then
			sinkUnit(K, sk, 3.4, 2.2, 3.0, {})
		end
	end)
	-- 계산대: 직원 쪽 수납 + 손님 쪽 앞판 --------------------------------------------------------------
	step(K, "counter", function()
		local body = V:first("Body")
		if not body then
			return
		end
		local cx = body.c.X
		local inner = faceCF(Vector3.new(cx, 0, body.min.Z - 0.005), -Vector3.zAxis)
		local outer = faceCF(Vector3.new(cx, 0, body.max.Z + 0.005), Vector3.zAxis)
		local len = body.size.X
		K:free(function()
			local n = math.floor(len / 2.2)
			for i = 0, n - 1 do
				local x = -len / 2 + (i + 0.5) * len / n
				K:plate("CounterDoor", len / n - 0.1, 2.0, 0.03, inner * CF(x, 1.4, 0), lk(238, 238, 234))
				K:plate("CounterPull", 0.6, 0.07, 0.05, inner * CF(x, 2.2, 0.03), LK.chrome)
				if i % 3 == 1 then
					tx(K, "CounterDoorLabel", 1.2, 0.25, inner * CF(x, 1.9, 0.035), ({ "약봉투", "처방전 보관", "반납약" })[(i // 3) % 3 + 1], GREY_T, nil, { font = FONT_M, d = 0.005 })
				end
			end
			-- 손님 쪽: 흰 판 + 청록 띠 + 안내
			K:plate("CounterFrontFace", len, 2.6, 0.03, outer * CF(0, 0.6 + 1.3, 0), lk(246, 246, 242, M.Marble))
			K:plate("CounterFrontBand", len, 0.18, 0.04, outer * CF(0, 3.0, 0), col(TEAL))
			tx(K, "CounterFrontText", 9.0, 0.6, outer * CF(-len / 4, 1.95, 0.035), "처방약 수령 · 복약 상담", TEAL_D, nil, { font = FONT_K })
			tx(K, "CounterFrontText2", 9.0, 0.45, outer * CF(len / 4, 1.95, 0.035), "약은 꼭 약사의 설명을 듣고 받아 가세요", GREY_T, nil, { font = FONT_M })
		end)
		-- 약사 의자 (맵 의자는 진열장을 봄 -> 계산대 쪽으로)
		for _, ch in V.chairs do
			if ch.seat.name == "ChairSeat" then
				hideList(K, ch.parts)
				K:free(function()
					officeChair(K, faceCF(Vector3.new(ch.c.X, 0, ch.c.Z), Vector3.zAxis), ch.top + 0.25)
				end)
			end
		end
	end)
	-- 벽: 면허 · 개설 등록 · 관리 안내 ---------------------------------------------------------------
	step(K, "walls", function()
		local d = wallSpot(K, "left", 2.6, 5.0, 8.4, 0, 0.5)
		if d then
			Props.frame(K, d, 2.4, 3.2, { frame = Look.goldMetal, text = "약사 면허증\n\n제 2019-0417 호\n\n보건복지부 장관", fg = INK, textH = 0.9, border = 0.08, depth = 0.05 })
		end
		local d2 = wallSpot(K, "left", 2.6, 5.0, 8.4, -4.0, 0.5)
		if d2 then
			Props.frame(K, d2, 2.4, 3.2, { frame = Look.goldMetal, text = "약국 개설 등록증\n\n광안 메디컬 약국\n\n부산광역시 수영구청장", fg = INK, textH = 0.9, border = 0.08, depth = 0.05 })
		end
		local d3 = wallSpot(K, "right", 4.2, 4.6, 7.6, -5.0, 0.5)
		if d3 then
			poster(K, d3, 4.0, 3.0, "마약류 · 향정신성의약품 관리", "이중 잠금 금고 보관 · 출입 기록\n마약류통합관리시스템 실시간 보고\n재고 확인 : 매일 마감 시", WHITE, INK, C3(120, 40, 50), WHITE, 0.24)
		end
		local d4 = wallSpot(K, "right", 4.6, 3.6, 6.8, 6.0, 0.5)
		if d4 then
			K:plate("Whiteboard", 4.4, 3.0, 0.08, d4, lk(250, 250, 250))
			K:plate("WhiteboardTray", 4.4, 0.12, 0.25, d4 * CF(0, -1.5, 0), LK.alu)
			tx(K, "WhiteboardText", 4.0, 2.6, d4 * CF(0, 0.05, 0.085), "오늘 조제 현황\n외래 처방 63건 · 수액 12건\n품절 : 코대원 시럽 (화요일 입고)\n백신 재고 확인 14시", C3(30, 60, 160), nil, { font = FONT_M, align = "Left" })
		end
	end)
	K.clinicCommon = { clock = true }
end

-- 침상 사물함 (pcf 바닥, +Z 앞, 높이 h). 위에 물병 · 컵 · 휴지
local function bedLocker(K: any, pcf: CFrame, w: number, d: number, h: number, o: any?)
	local oo: any = o or {}
	K:box("LockerBody", V3(w, h - 0.15, d), pcf * CF(0, 0.15 + (h - 0.15) / 2, 0), lk(242, 242, 240, M.Plastic))
	K:box("LockerKick", V3(w - 0.1, 0.15, d - 0.1), pcf * CF(0, 0.075, 0), lk(150, 156, 160, M.Plastic))
	K:box("LockerTop", V3(w + 0.1, 0.1, d + 0.1), pcf * CF(0, h + 0.05, 0), lk(196, 176, 140, M.Wood))
	K:plate("LockerDrawer", w - 0.16, 0.55, 0.03, pcf * CF(0, h - 0.4, d / 2), lk(236, 238, 238, M.Plastic))
	K:plate("LockerDrawerPull", w * 0.45, 0.08, 0.05, pcf * CF(0, h - 0.3, d / 2 + 0.03), col(TEAL, M.Plastic))
	K:plate("LockerDoor", w - 0.16, h - 0.95, 0.03, pcf * CF(0, 0.2 + (h - 0.95) / 2, d / 2), lk(236, 238, 238, M.Plastic))
	K:plate("LockerDoorPull", 0.08, 0.5, 0.05, pcf * CF(w / 2 - 0.3, h - 1.1, d / 2 + 0.03), LK.chrome)
	if oo.fridge then
		tx(K, "LockerFridge", 0.6, 0.18, pcf * CF(-w / 4, h - 1.2, d / 2 + 0.04), "냉장", C3(60, 120, 200), nil, { d = 0.005 })
	end
	local t = pcf * CF(0, h + 0.1, 0)
	K:vcyl("LockerBottle", 0.75, 0.26, t * CF(-w / 4, 0.375, -0.1), { c = C3(220, 236, 246), m = M.Glass, t = 0.35 })
	K:vcyl("LockerBottleCap", 0.1, 0.18, t * CF(-w / 4, 0.8, -0.1), col(C3(30, 110, 200), M.Plastic))
	K:vcyl("LockerCup", 0.35, 0.28, t * CF(0.1, 0.175, 0.15), lk(250, 250, 250, M.Plastic))
	K:box("LockerTissue", V3(0.6, 0.3, 0.4), t * CF(w / 4, 0.15, -0.1), lk(250, 250, 250))
	K:box("LockerTissuePuff", V3(0.18, 0.08, 0.12), t * CF(w / 4, 0.33, -0.1), Look.paper)
end

-- 수액 리클라이너 의자 (pcf 바닥, +Z = 발 쪽 앞). 비닐 시트
local function recliner(K: any, pcf: CFrame, o: any?)
	local oo: any = o or {}
	local vl = oo.look or lk(60, 120, 140, M.Leather)
	local fr = lk(200, 204, 206, M.Metal)
	K:box("ReclBase", V3(2.0, 0.2, 2.6), pcf * CF(0, 0.1, 0), fr)
	K:box("ReclColumn", V3(1.0, 1.0, 1.2), pcf * CF(0, 0.7, -0.2), lk(150, 156, 160, M.Plastic))
	K:slab("ReclSeat", 2.2, 2.0, 0.45, 0.25, pcf * CF(0, 1.6, 0), vl)
	local bc = pcf * CF(0, 1.6, -1.0) * ANG(math.rad(-30), 0, 0)
	K:slab("ReclBack", 2.2, 2.6, 0.45, 0.25, bc * CF(0, 0.05, -1.3) * ANG(0, 0, 0), vl)
	local back = bc * CF(0, 0.05, -2.5)
	K:ell("ReclHead", V3(1.4, 0.35, 0.8), back * CF(0, 0.3, 0.1), vl)
	local lc = pcf * CF(0, 1.55, 1.0) * ANG(math.rad(-38), 0, 0)
	K:slab("ReclLeg", 2.0, 1.6, 0.36, 0.2, lc * CF(0, -0.05, 0.8), vl)
	for _, sx in { -1, 1 } do
		K:box("ReclArm", V3(0.36, 0.3, 1.9), pcf * CF(sx * 1.25, 2.25, -0.1), lk(60, 64, 70, M.Plastic))
		K:box("ReclArmPost", V3(0.16, 0.6, 0.16), pcf * CF(sx * 1.25, 1.9, -0.2), fr)
	end
	-- 팔 받침 (주사용)
	K:box("ReclArmBoard", V3(0.6, 0.12, 1.5), pcf * CF(1.45, 2.3, 0.6), lk(60, 120, 140, M.Leather))
end

-- 유리문 약품장 (속이 빈 몸통 + 선반 + 물건 + 유리문 그룹). box = 맵 rec (같은 자리), front 방향
local function glassCabinet(K: any, r: any, front: Vector3, items: string, o: any?): { Model }
	local oo: any = o or {}
	local pcf, w, d, h = recFrame(r, front)
	local y0 = r.min.Y
	local bodyL = oo.body or lk(244, 244, 240)
	local doors = {}
	K:free(function()
		K:box("CabBack", V3(w, h, 0.08), pcf * CF(0, h / 2, -d / 2 + 0.04), bodyL)
		K:box("CabTopP", V3(w, 0.1, d), pcf * CF(0, h - 0.05, 0), bodyL)
		K:box("CabBotP", V3(w, 0.12, d), pcf * CF(0, 0.06, 0), bodyL)
		for _, sx in { -1, 1 } do
			K:box("CabSide", V3(0.1, h, d), pcf * CF(sx * (w / 2 - 0.05), h / 2, 0), bodyL)
		end
		local nd = math.max(2, math.floor(w / 3.6 + 0.5))
		for i = 1, nd - 1 do
			K:box("CabDivider", V3(0.08, h - 0.2, d - 0.1), pcf * CF(-w / 2 + i * w / nd, h / 2, -0.05), bodyL)
		end
		local nsh = oo.shelves or 3
		local r2 = rng(oo.seed or 3)
		for j = 1, nsh do
			local y = 0.12 + (h - 0.22) * (j - 1) / nsh
			if j > 1 then
				K:box("CabShelf", V3(w - 0.2, 0.05, d - 0.2), pcf * CF(0, y, -0.05), { c = C3(220, 236, 238), m = M.Glass, t = 0.4 })
			end
			local gap = (h - 0.22) / nsh
			local x = -w / 2 + 0.3
			while x < w / 2 - 0.6 do
				local kind = r2()
				local base = pcf * CF(x, y + 0.04, -0.1)
				if items == "infusion" and j == 1 then
					K:box("IVPackBox", V3(1.3, math.min(gap - 0.2, 1.0), d - 0.6), base * CF(0.65, math.min(gap - 0.2, 1.0) / 2, 0), LK.cardboard)
					tx(K, "IVPackLabel", 1.1, 0.3, base * CF(0.65, 0.45, (d - 0.6) / 2 + 0.005), ({ "생리식염수", "포도당 5%", "하트만" })[math.floor(r2() * 3) + 1], INK, WHITE, { d = 0.005 })
					x += 1.45
				elseif kind < 0.35 then
					for v = 0, 3 do
						K:vcyl("CabVial", 0.4, 0.15, base * CF(0.12 + v * 0.2, 0.2, 0.1), { c = C3(236, 244, 248), m = M.Glass, t = 0.3 })
						K:vcyl("CabVialCap", 0.06, 0.16, base * CF(0.12 + v * 0.2, 0.43, 0.1), col(({ C3(220, 50, 50), C3(60, 130, 220), C3(250, 200, 40), C3(120, 200, 120) })[v + 1], M.Plastic))
					end
					x += 0.95
				else
					local dg = DRUGS[math.floor(r2() * #DRUGS) + 1]
					local bh = math.min(gap - 0.2, 0.5 + r2() * 0.4)
					local bw = 0.7 + r2() * 0.5
					K:box("CabBox", V3(bw, bh, 0.9), base * CF(bw / 2, bh / 2, 0), col(WHITE))
					K:box("CabBoxBand", V3(bw + 0.01, bh * 0.25, 0.91), base * CF(bw / 2, bh * 0.7, 0), col(dg[2]))
					x += bw + 0.1
				end
			end
		end
	end)
	-- 유리문 (경첩 = 각 문 바깥쪽 끝)
	local nd = math.max(2, math.floor(w / 3.6 + 0.5))
	for i = 1, nd do
		local dw = w / nd
		local x0 = -w / 2 + (i - 1) * dw
		local hingeLeft = i % 2 == 1
		local m = K:group("CabDoor_" .. i, function()
			K:free(function()
				local c = pcf * CF(x0 + dw / 2, h / 2, d / 2 + 0.03)
				K:box("CabDoorFrame", V3(dw - 0.04, h - 0.04, 0.06), c * CF(0, 0, 0), LK.alu)
				K:box("CabDoorGlass", V3(dw - 0.3, h - 0.3, 0.07), c, { c = C3(220, 236, 240), m = M.Glass, t = 0.72, r = 0.15 })
				K:box("CabDoorHandle", V3(0.08, 0.9, 0.12), c * CF((if hingeLeft then 1 else -1) * (dw / 2 - 0.25), 0, 0.07), LK.chrome)
			end)
		end)
		local hx = if hingeLeft then x0 else x0 + dw
		m:SetAttribute("Hinge", (K.cf * pcf * CF(hx, 0, d / 2 + 0.03)).Position)
		m:SetAttribute("HingeSign", if hingeLeft then 1 else -1)
		table.insert(doors, m)
	end
	_ = y0
	return doors
end

-- 여러 문짝 한꺼번에 여닫기 (glassCabinet 문: Hinge / HingeSign 속성)
local function swingDoors(K: any, models: { Model? }, angle: number, object: string, openT: string, closeT: string): ProximityPrompt?
	local recs = {}
	local handle: BasePart? = nil
	for _, m in models do
		if m then
			local hinge = m:GetAttribute("Hinge")
			local sgn = m:GetAttribute("HingeSign") or 1
			if typeof(hinge) == "Vector3" then
				local parts = {}
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						table.insert(parts, { p = d, cf = d.CFrame })
						if not handle and string.find(d.Name, "Handle") then
							handle = d
						end
					end
				end
				table.insert(recs, { hinge = hinge, sgn = sgn, parts = parts })
			end
		end
	end
	if not handle or #recs == 0 then
		return nil
	end
	local open = false
	return Interact.prompt(K, handle, {
		action = openT,
		object = object,
		sound = "rbxasset://sounds/clickfast.wav",
		fn = function(_n, pr)
			open = not open
			for _, r in recs do
				local rot = CFrame.new(r.hinge) * CFrame.fromAxisAngle(Vector3.yAxis, if open then r.sgn * angle else 0) * CFrame.new(-r.hinge)
				for _, q in r.parts do
					if q.p.Parent then
						TweenService:Create(q.p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = rot * q.cf }):Play()
					end
				end
			end
			pr.ActionText = if open then closeT else openT
		end,
	})
end

-- 벽시계 (실제 시각), dcf
local function wallClock(K: any, dcf: CFrame, dia: number?)
	local d = dia or 1.6
	local hr, mn = Props.clock(K, dcf, d, { frame = lk(230, 232, 232, M.Plastic) })
	Interact.clock(K, hr, mn, dcf, d)
end

-- 1F 주사실 · 처치실 -----------------------------------------------------------------------------------------------
BUILD.treat = function(K: any, V: any)
	step(K, "ceiling", function()
		ceilingKit(K, V, { lights = 6 })
	end)
	step(K, "floor", function()
		floorKit(K, V, { look = lk(206, 214, 216, M.SmoothPlastic), grout = lk(176, 184, 186), tile = 2.04 })
		baseKit(K, V, { "back", "left", "right", "front" })
	end)
	-- 침대 2 + 링거 + 사물함 + U 커튼 ----------------------------------------------------------------------
	local beds = {}
	for _, r in V.byName.BedSeat or {} do
		table.insert(beds, r)
	end
	table.sort(beds, function(a, b)
		return a.c.X < b.c.X
	end)
	local tabs = {}
	for i, seat in beds do
		step(K, "bed" .. i, function()
			local bf, L, W = hospitalBed(K, V, seat, { chart = if i == 1 then "TREAT 1\n응급 · 처치\n낙상 주의 ●" else "TREAT 2\n수액 · 주사\n알레르기 없음", blanket = lk(170, 206, 214, M.Fabric) })
			-- 링거 (맵 자리)
			local iv = nearest(V, "IVPole", seat.c, 8)
			if iv then
				for _, q in siblings(V, iv) do
					if q.name == "IVPole" or q.name == "IVBag" or q.name == "IVLine" or q.name == "IVBase" then
						hideRec(K, q)
					end
				end
				K:free(function()
					local drip = ivPole(K, CF(iv.c.X, 0, iv.c.Z), { pump = i == 1, to = (bf * CF(W / 2 - 0.3, seat.max.Y + 0.1, -0.6)).Position })
					dripAnim(K, drip)
				end)
			end
			-- 사물함 (맵 자리)
			local bc = nearest(V, "BedsideCabinet", seat.c, 8)
			if bc then
				for _, q in siblings(V, bc) do
					if q.name == "BedsideCabinet" or q.name == "BedsideTop" or q.name == "WaterCup" then
						hideRec(K, q)
					end
				end
				K:free(function()
					local face = if bc.c.X < seat.c.X then Vector3.xAxis else -Vector3.xAxis
					bedLocker(K, faceCF(Vector3.new(bc.c.X, 0, bc.c.Z), face), 1.8, 1.8, 2.6)
				end)
			end
			-- 오른쪽 침대는 문 쪽 커튼을 머리 쪽에 모음 (통로)
			local runs = bedCurtains(K, bf, L, W, { revLeft = i == #beds, gapX = 1.25 })
			if runs[1] then
				local t = curtainToggle(K, runs, runs[1].tab, string.format("%d번 침대 커튼", i), 0.12)
				table.insert(tabs, t)
			end
		end)
	end
	-- 약품장 (위: 유리문, 아래: 서랍) + 주사 준비대 -----------------------------------------------------------
	step(K, "cabinet", function()
		local up = V:first("UpperCabinet")
		if up then
			hideNames(K, { "UpperCabinet", "CabinetGlass", "MedBox" })
			local doors = glassCabinet(K, up, Vector3.zAxis, "infusion", { shelves = 3, seed = 9 })
			swingDoors(K, { doors[2], doors[3] }, -math.rad(105), "주사제 · 수액장", "약품장 열기", "약품장 닫기")
		end
		local base = V:first("CabinetBase")
		local top = V:first("CabinetTop")
		if base then
			local f = faceCF(Vector3.new(base.c.X, 0, base.max.Z + 0.005), Vector3.zAxis)
			K:free(function()
				local n = 8
				for i = 0, n - 1 do
					local x = -base.size.X / 2 + (i + 0.5) * base.size.X / n
					K:plate("CabDrawer", base.size.X / n - 0.08, 0.8, 0.03, f * CF(x, base.max.Y - 0.5, 0), lk(236, 238, 236))
					K:plate("CabDrawerPull", 0.8, 0.07, 0.05, f * CF(x, base.max.Y - 0.4, 0.03), LK.chrome)
					K:plate("CabDoorLow", base.size.X / n - 0.08, base.size.Y - 1.35, 0.03, f * CF(x, 0.3 + (base.size.Y - 1.35) / 2, 0), lk(236, 238, 236))
					tx(K, "CabDrawerTag", 1.0, 0.2, f * CF(x, base.max.Y - 0.62, 0.035), ({ "주사기", "수액세트", "알콜솜", "거즈", "반창고", "장갑", "카테터", "앰플" })[i + 1], GREY_T, WHITE, { d = 0.005, font = FONT_M })
				end
			end)
		end
		if top then
			local ty = top.max.Y + 0.005
			local cx, cz = top.c.X, top.c.Z
			K:free(function()
				local tr = CF(cx - 4.0, ty, cz + 0.2)
				K:box("PrepTray", V3(2.2, 0.08, 1.4), tr * CF(0, 0.04, 0), LK.steel)
				for k = 0, 3 do
					K:box("Syringe", V3(0.12, 0.12, 0.8), tr * CF(-0.7 + k * 0.3, 0.14, 0) * ANG(0, 0.1 * k, 0), { c = C3(236, 244, 248), m = M.Glass, t = 0.2 })
				end
				for k = 0, 4 do
					K:vcyl("Ampoule", 0.4, 0.12, tr * CF(0.4 + (k % 3) * 0.22, 0.28, -0.3 + (k // 3) * 0.3), { c = C3(200, 150, 90), m = M.Glass, t = 0.3 })
				end
				K:box("Tourniquet", V3(1.2, 0.03, 0.12), tr * CF(0.2, 0.1, 0.5), col(C3(60, 140, 220), M.Rubber))
				K:vcyl("SwabJar", 0.7, 0.55, CF(cx - 1.8, ty + 0.35, cz), LK.steel)
				K:vcyl("SwabJarLid", 0.08, 0.6, CF(cx - 1.8, ty + 0.74, cz), LK.chrome)
				K:vcyl("CottonJar", 0.65, 0.5, CF(cx - 1.0, ty + 0.33, cz), { c = C3(230, 240, 244), m = M.Glass, t = 0.4 })
				K:ball("CottonBalls", 0.42, CF(cx - 1.0, ty + 0.25, cz), lk(252, 252, 252, M.Fabric))
				sharpsBox(K, CF(cx + 0.8, ty, cz), 0.6)
				K:box("GloveBoxTop", V3(0.9, 0.45, 0.5), CF(cx + 2.2, ty + 0.225, cz), lk(246, 246, 244))
				K:box("GloveBoxBand", V3(0.91, 0.12, 0.51), CF(cx + 2.2, ty + 0.35, cz), col(C3(140, 110, 200)))
				K:box("SyringePack", V3(1.6, 0.5, 0.9), CF(cx + 4.4, ty + 0.25, cz - 0.2), lk(246, 246, 244))
				tx(K, "SyringePackLabel", 1.4, 0.3, faceCF(Vector3.new(cx + 4.4, ty + 0.25, cz + 0.255), Vector3.zAxis), "일회용 주사기 3cc · 100", NAVY, nil, { d = 0.005, font = FONT_M })
				K:box("Thermometer", V3(0.25, 0.14, 0.65), CF(cx + 6.0, ty + 0.07, cz + 0.3), lk(240, 240, 240, M.Plastic))
				tx(K, "PrepSign", 3.0, 0.4, faceCF(Vector3.new(cx - 4.0, ty + 0.25, top.max.Z - 0.02), Vector3.zAxis), "주사 준비대 · 무균 구역", TEAL_D, nil, { d = 0.005 })
			end)
		end
	end)
	-- 손 세정대 · 손상성 폐기물 · 의료폐기물 · 처치 카트 -----------------------------------------------------
	step(K, "sink", function()
		local cab = V:first("SinkCabinet")
		if cab then
			hideNames(K, { "SinkCabinet", "SinkTop", "Sink", "Tap" })
			sinkUnit(K, faceCF(Vector3.new(cab.c.X, 0, cab.c.Z), Vector3.zAxis), cab.size.X, cab.size.Z, cab.size.Y, {})
		end
		local st = V:first("SharpsStand")
		if st then
			hideNames(K, { "SharpsStand", "SharpsBin" })
			K:free(function()
				local p = faceCF(Vector3.new(st.c.X, 0, st.c.Z), Vector3.zAxis)
				K:box("SharpsStandFrame", V3(1.4, 0.08, 1.2), p * CF(-0.6, 1.9, 0), LK.steel)
				for _, sx in { -1.2, 0 } do
					K:box("SharpsStandLeg", V3(0.08, 1.9, 0.08), p * CF(sx, 0.95, 0.5), LK.steel)
					K:box("SharpsStandLeg", V3(0.08, 1.9, 0.08), p * CF(sx, 0.95, -0.5), LK.steel)
				end
				sharpsBox(K, p * CF(-0.6, 1.94, 0), 1)
				medWasteBox(K, p * CF(0.9, 0, 0), 1.4, 2.0)
			end)
		end
		local cb = V:first("CartBody")
		if cb then
			hideNames(K, { "CartBody", "CartTop", "Tray", "Bottle", "Gauze", "Wheel" })
			K:free(function()
				cart(K, faceCF(Vector3.new(cb.c.X, 0, cb.c.Z), Vector3.zAxis), 3.2, 2.2, 3.0, "drawers")
			end)
		end
	end)
	-- 수액실: 리클라이너 2 + 링거 + 칸막이 커튼 + TV ---------------------------------------------------------
	step(K, "infusion", function()
		local placed = {}
		for _, z in { -2.4, 4.4 } do
			local pcf = floorAt(K, V.x1 - 3.6, z, -PI / 2, 2.8, 4.8, 4.2, 0.1)
			if pcf then
				recliner(K, pcf, {})
				local drip = ivPole(K, pcf * CF(-1.9, 0, -0.6), { level = 0.5 })
				dripAnim(K, drip)
				local sp = pcf * CF(1.95, 0, 0.5)
				if K:spot(sp, V3(1.2, 2.4, 1.2), 0) then
					K:box("SideTable", V3(1.1, 0.08, 1.1), sp * CF(0, 2.3, 0), lk(196, 176, 140, M.Wood))
					K:vcyl("SideTablePole", 2.2, 0.12, sp * CF(0, 1.15, 0), LK.chrome)
					K:disc("SideTableBase", 0.9, 0.06, sp * CF(0, 0.03, 0), LK.chrome)
					K:vcyl("SideTableCup", 0.35, 0.28, sp * CF(0.2, 2.5, 0), lk(250, 250, 250, M.Plastic))
				end
				table.insert(placed, pcf)
			end
		end
		if #placed == 2 then
			local mid = (placed[1].Position + placed[2].Position) / 2
			local run = curtainRun(K, { Vector3.new(V.x1 - 0.2, 0, mid.Z), Vector3.new(V.x1 - 6.6, 0, mid.Z) }, 0.9)
			_ = run
		end
		local d = wallSpot(K, "right", 4.2, 5.6, 8.2, 1.0, 0.6)
		if d then
			local _, lab = wallScreen(K, d, 4.0, 2.25, "", C3(20, 60, 90), WHITE, { glow = 1.0 })
			Interact.screenLoop(K, nil, lab, {
				{ text = "수액 맞는 동안\n편하게 쉬세요\n남은 시간 약 25분" },
				{ text = "오늘의 날씨 · 광안리\n맑음 22°C\n파고 0.5m" },
				{ text = "수액 후 어지러우면\n천천히 일어나세요\n간호사 호출 : 손을 들어 주세요" },
			}, 7)
		end
		local d2 = wallSpot(K, "right", 4.2, 3.4, 5.4, 9.0, 0.6)
		if d2 then
			poster(K, d2, 4.0, 1.9, "영양 수액 안내 (비급여)", "비타민 C 고용량 60,000 · 마늘주사 50,000\n피로회복 · 숙취 70,000 · 백옥주사 50,000", WHITE, INK, TEAL, WHITE, 0.32)
		end
	end)
	-- 시계 (멈춘 맵 시계 그림 자리) · 포스터 · 휠체어 · 처치 조명 -----------------------------------------------
	step(K, "walls", function()
		local s = V:first("Sign_10:24")
		if s then
			hideRec(K, s)
			wallClock(K, faceCF(Vector3.new(s.c.X, s.c.Y, V.z0 + 0.01), Vector3.zAxis), 1.8)
			wallUse(K, "back", s.c.X - 1.2, s.c.X + 1.2, s.c.Y - 1.2, s.c.Y + 1.2)
		end
		for i, z in { -5.0, 1.5 } do
			local d = wallSpot(K, "left", 3.2, 4.6, 8.8, wallU("left", Vector3.new(0, 0, z)), 0.6)
			if d then
				if i == 1 then
					poster(K, d, 3.0, 4.0, "손 위생 5가지 순간", "① 환자 접촉 전\n② 무균 처치 전\n③ 체액 노출 후\n④ 환자 접촉 후\n⑤ 환자 주변 접촉 후", WHITE, INK, C3(40, 150, 200), WHITE, 0.2)
				else
					poster(K, d, 3.0, 4.0, "낙상 예방", "침대 난간을 올려 주세요\n일어날 때는 천천히\n어지러우면 호출하세요\n미끄럼 주의", WHITE, INK, C3(230, 140, 30), WHITE, 0.2)
				end
			end
		end
		local wc = floorAt(K, V.x0 + 2.0, 8.0, PI / 2, 2.4, 3.2, 3.8, 0.1)
		if wc then
			wheelchair(K, wc)
		end
		-- 이동식 처치등 (1번 침대 왼쪽)
		if beds[1] then
			local lp = floorAt(K, beds[1].c.X - 3.4, beds[1].c.Z - 3.8, 0, 1.8, 1.8, 6.5, 0)
			if lp then
				for i = 0, 4 do
					local a = i * 2 * PI / 5
					K:seg("ExamLampLeg", (lp * CF(0, 0.25, 0)).Position, (lp * CF(math.cos(a) * 0.8, 0.15, math.sin(a) * 0.8)).Position, 0.08, LK.chrome)
					K:ball("ExamLampCaster", 0.18, lp * CF(math.cos(a) * 0.8, 0.09, math.sin(a) * 0.8), LK.black)
				end
				K:vcyl("ExamLampPole", 4.2, 0.12, lp * CF(0, 2.35, 0), LK.chrome)
				K:seg("ExamLampNeck", (lp * CF(0, 4.45, 0)).Position, (lp * CF(0.6, 5.6, 1.4)).Position, 0.1, lk(60, 64, 70, M.Rubber))
				K:cyl("ExamLampHead", 0.35, 0.8, lp * CF(0.65, 5.55, 1.5) * ANG(0, 0, PI / 2) * ANG(0, 0, 0.5), lk(240, 240, 238, M.Plastic))
				K:disc("ExamLampLens", 0.62, 0.03, lp * CF(0.62, 5.32, 1.55), col(C3(250, 250, 240), M.Neon))
			end
		end
		local d3 = wallSpot(K, "back", 1.0, 3.4, 4.8, 13.0, 0.6)
		if d3 then
			sanitizerWall(K, d3)
		end
		local d4 = wallSpot(K, "back", 3.0, 3.6, 4.6, 3.0, 0.6)
		if d4 then
			gloveHolder(K, d4, 3)
		end
	end)
	K.clinicCommon = { clock = false }
end

-- 게시판 (코르크 + 공지문), dcf. 반환 공지 TextLabel (넘겨보기)
local function bulletinBoard(K: any, dcf: CFrame, w: number, h: number, title: string, notes: { { string } }): TextLabel?
	K:plate("BoardFrame", w + 0.2, h + 0.2, 0.08, dcf, lk(120, 96, 70, M.Wood))
	K:plate("BoardCork", w, h, 0.1, dcf, lk(176, 136, 96, M.Fabric))
	K:plate("BoardHeader", w, 0.6, 0.11, dcf * CF(0, h / 2 - 0.3, 0), col(TEAL))
	tx(K, "BoardTitle", w - 0.4, 0.45, dcf * CF(0, h / 2 - 0.3, 0.115), title, WHITE, nil, { font = FONT_K })
	local n = #notes
	local cols = math.min(4, n)
	local nw = (w - 0.4) / cols - 0.25
	local lab
	for i, nt in notes do
		local cx = -w / 2 + 0.2 + ((i - 1) % cols + 0.5) * (w - 0.4) / cols
		local cy = -0.4 - (((i - 1) // cols) * 1.6)
		local pc = dcf * CF(cx, cy + h / 2 - 1.6, 0.1) * ANG(0, 0, ((i * 7) % 5 - 2) * 0.02)
		local _, l = tx(K, "BoardNote", nw, 1.5, pc, nt[1], INK, nt[2] and C3(255, 248, 190) or C3(250, 250, 246), { font = FONT_M, d = 0.01 })
		K:ball("BoardPin", 0.1, pc * CF(0, 0.65, 0.03), col(({ C3(220, 40, 40), C3(40, 120, 220), C3(40, 170, 80) })[(i - 1) % 3 + 1]))
		if i == 1 then
			lab = l
		end
	end
	return lab
end

-- 1F 후면 홀 (계단 · 엘리베이터 · 화장실 · 비상구) --------------------------------------------------------------------
BUILD.backhall = function(K: any, V: any)
	local steps = V.byName.Step or {}
	local sx0, sx1, sz0, sz1 = math.huge, -math.huge, math.huge, -math.huge
	for _, r in steps do
		sx0 = math.min(sx0, r.min.X)
		sx1 = math.max(sx1, r.max.X)
		sz0 = math.min(sz0, r.min.Z)
		sz1 = math.max(sz1, r.max.Z)
	end
	step(K, "ceiling", function()
		local vd = if #steps > 0 then { sx0 + 6, sz0 - 0.6, sx1 + 0.6, sz1 + 0.6 } else nil
		ceilingKit(K, V, { lights = 7, void = vd, every = 3 })
	end)
	step(K, "floor", function()
		floorKit(K, V, { look = lk(228, 226, 220, M.Marble), grout = lk(190, 188, 182), tile = 2.04 })
		baseKit(K, V, { "back", "left", "right", "front" })
		lowerWall(K, V, { "back", "front" }, 3.0)
		-- 바닥 유도선 (초록 = 비상구)
		K:free(function()
			K:box("FloorGuideGreen", V3(30, 0.025, 0.4), CF(V.x0 + 16, 0.016, 6.6), col(GREEN_EXIT))
			for i = 0, 5 do
				tx(K, "FloorGuideArrow", 1.6, 0.36, CFrame.fromMatrix(Vector3.new(V.x0 + 4 + i * 5, 0.03, 6.6), Vector3.xAxis, -Vector3.zAxis, Vector3.yAxis), "◀ 비상구", WHITE, nil, { d = 0.005, free = true })
			end
		end)
	end)
	-- 계단: 디딤판 미끄럼방지 · 옆판 (스트링거) -------------------------------------------------------------
	step(K, "stairs", function()
		if #steps == 0 then
			return
		end
		table.sort(steps, function(a, b)
			return a.max.Y < b.max.Y
		end)
		local zA, zB = sz0 + 0.08, sz1 - 0.08
		local zc, zw = (zA + zB) / 2, zB - zA
		K:free(function()
			for _, r in steps do
				local y = r.max.Y
				if y < V.H - 0.2 then
					local x = r.min.X
					K:box("StairNosing", V3(0.3, 0.05, zw), CF(x + 0.15, y + 0.02, zc), lk(60, 62, 66, M.Rubber))
					K:box("StairNosingLine", V3(0.06, 0.055, zw), CF(x + 0.05, y + 0.022, zc), col(C3(250, 200, 40)))
					K:box("StairTread", V3(r.size.X - 0.3, 0.02, zw), CF(x + 0.3 + (r.size.X - 0.3) / 2, y + 0.008, zc), lk(206, 204, 198, M.Granite))
				end
			end
			-- 옆판: 경사 띠 (양쪽)
			local first, last = steps[1], steps[#steps]
			local a = Vector3.new(first.min.X, first.max.Y - 0.6, 0)
			local b = Vector3.new(last.max.X, last.max.Y - 0.6, 0)
			for _, z in { sz0 - 0.06, sz1 + 0.06 } do
				K:bar("StairStringer", Vector3.new(a.X, a.Y, z), Vector3.new(b.X, b.Y, z), 0.1, 1.2, lk(236, 236, 232))
				K:bar("StairStringerLine", Vector3.new(a.X, a.Y + 0.62, z), Vector3.new(b.X, b.Y + 0.62, z), 0.12, 0.08, col(TEAL))
			end
		end)
		-- 계단 아래 안내
		local d = faceCF(Vector3.new(sx0 - 0.4, 5.4, (sz0 + sz1) / 2), -Vector3.xAxis)
		K:free(function()
			K:box("StairSignPost", V3(0.16, 4.8, 0.16), CF(sx0 - 1.0, 2.4, sz1 - 0.6), lk(70, 74, 78, M.Metal))
			K:box("StairSignFoot", V3(1.0, 0.1, 1.0), CF(sx0 - 1.0, 0.05, sz1 - 0.6), lk(70, 74, 78, M.Metal))
			roomSign(K, faceCF(Vector3.new(sx0 - 1.1, 5.2, sz1 - 0.6), -Vector3.xAxis), 3.0, 1.4, "2F  ↑", "입원실 · 건강검진 · 휴게실", {})
		end)
		_ = d
	end)
	-- 벤치 (연결 의자) ------------------------------------------------------------------------------------------
	step(K, "bench", function()
		local g = {}
		for _, ch in V.chairs do
			if ch.seat.name == "BenchSeat" then
				table.insert(g, ch)
			end
		end
		beamChairs(K, g, { seat = LK.vinylTeal })
	end)
	-- 비상구 · 소화전 · 대피도 ----------------------------------------------------------------------------------
	step(K, "exit", function()
		local es = V:first("ExitSign")
		if es then
			hideRec(K, es)
			K:free(function()
				local d = faceCF(Vector3.new(V.x0 + 0.01, es.c.Y, es.c.Z), Vector3.xAxis)
				local lamp = exitSign(K, d, 2.6, "→")
				K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Back, Range = 6, Brightness = 0.5, Angle = 120, Color = GREEN_EXIT })
			end)
		end
		local d2 = wallSpot(K, "left", 2.8, 1.9, 6.3, wallU("left", Vector3.new(0, 0, -5.4)), 0.8)
		if d2 then
			hydrantBox(K, d2)
		end
		local d3 = wallSpot(K, "front", 4.6, 4.2, 7.6, wallU("front", Vector3.new(-40, 0, 0)), 0.6)
		if d3 then
			K:plate("EvacFrame", 4.4, 3.2, 0.06, d3, lk(200, 204, 206, M.Metal))
			K:plate("EvacMap", 4.2, 3.0, 0.07, d3, lk(250, 250, 246))
			tx(K, "EvacTitle", 4.0, 0.4, d3 * CF(0, 1.25, 0.075), "피난 안내도 · 1층", RED, nil, { font = FONT_K })
			-- 간단한 평면 (방 상자 + 경로)
			local rooms = { { -1.3, 0.3, 1.0, 0.9 }, { 0.1, 0.3, 1.2, 0.9 }, { 1.4, 0.3, 1.0, 0.9 }, { -1.3, -0.75, 1.6, 0.7 }, { 0.6, -0.75, 1.6, 0.7 } }
			for _, rm in rooms do
				K:plate("EvacRoom", rm[3], rm[4], 0.075, d3 * CF(rm[1], rm[2], 0.002), lk(220, 232, 240))
			end
			K:plate("EvacRoute", 3.6, 0.08, 0.08, d3 * CF(0, -0.25, 0.004), col(GREEN_EXIT))
			K:plate("EvacRoute2", 0.08, 0.9, 0.08, d3 * CF(-1.8, -0.7, 0.004), col(GREEN_EXIT))
			K:ball("EvacHere", 0.18, d3 * CF(0.4, -0.25, 0.1), col(RED))
			tx(K, "EvacHereLabel", 1.0, 0.22, d3 * CF(0.4, -0.05, 0.08), "현 위치", RED, nil, { d = 0.005 })
		end
	end)
	-- 게시판 (복도 쪽 벽) -----------------------------------------------------------------------------------
	step(K, "board", function()
		local d = wallSpot(K, "front", 9.0, 3.6, 8.2, wallU("front", Vector3.new(34, 0, 0)), 0.6)
		if not d then
			note(K, "board: no wall")
			return
		end
		local notes = {
			{ "병원 소식\n\n10월 독감 예방접종\n시작 (평일 09~18시)", true },
			{ "주차 안내\n\n진료 고객 2시간 무료\n접수창구 등록", false },
			{ "채용 공고\n\n병동 간호사 (3교대)\n방사선사 1명", true },
			{ "분실물 보관\n\n안경 · 우산 · 이어폰\n접수창구 문의", false },
			{ "금연 구역\n\n병원 건물 · 주차장\n전 구역 금연", false },
			{ "자원봉사 모집\n\n안내 · 길찾기 도우미\n주 1회 2시간", true },
			{ "건강강좌\n\n당뇨 바로 알기\n10/24(토) 11시 2층", false },
			{ "의료급여 · 실손보험\n\n서류 발급 안내\n진료비 영수증 · 세부내역서", false },
		}
		local lab = bulletinBoard(K, d, 9.0, 4.4, "광안 메디컬 게시판", notes)
		if lab then
			local pages = {
				"병원 소식\n\n10월 독감 예방접종\n시작 (평일 09~18시)",
				"병원 소식\n\n11월 3일 (화)\n오후 2시 휴진 (전산 점검)",
				"병원 소식\n\n건강검진 결과 상담\n2층 검진센터 예약",
			}
			local i = 1
			local notePart = lab.Parent and (lab.Parent :: any).Parent
			Interact.prompt(K, notePart, {
				action = "공지 넘겨 보기",
				object = "게시판",
				sound = "rbxasset://sounds/swoosh.wav",
				fn = function()
					i = i % #pages + 1
					lab.Text = pages[i]
				end,
			})
		end
	end)
	-- 정수기 (물 받기) · 휠체어 보관 · 층별 안내 · 화장실 표지 ----------------------------------------------------
	step(K, "amenity", function()
		local pp, u = wallFloorNear(K, "front", wallU("front", Vector3.new(-30, 0, 0)), 2.8, 1.8, 4.8, 4, 0)
		if pp then
			local btn = purifier(K, pp, { h = 4.6 })
			local cupL = { c = C3(250, 250, 250), m = M.SmoothPlastic, t = 1 }
			local cup = K:vcyl("WaterCup", 0.5, 0.36, pp * CF(0, 1.25, 1.0), cupL)
			local water = K:vcyl("WaterInCup", 0.02, 0.3, pp * CF(0, 1.02, 1.0), { c = C3(160, 210, 255), m = M.Glass, t = 1 })
			local c0, w0 = cup.CFrame, water.CFrame
			local busy = false
			Interact.prompt(K, btn, {
				action = "물 받기",
				object = "정수기",
				sound = "rbxasset://sounds/electronicpingshort.wav",
				fn = function()
					if busy then
						return
					end
					busy = true
					cup.Transparency = 0
					water.Transparency = 0.3
					water.Size = V3(0.02, 0.3, 0.3)
					water.CFrame = w0
					TweenService:Create(water, TweenInfo.new(1.6), { Size = V3(0.4, 0.3, 0.3), CFrame = w0 * CF(0.19, 0, 0) }):Play()
					task.delay(5, function()
						if cup.Parent then
							cup.Transparency = 1
							water.Transparency = 1
						end
						busy = false
					end)
					_ = c0
				end,
			})
			_ = u
		end
		-- 휠체어 보관 (STAFF ONLY 문 왼쪽)
		local n = 0
		for _, x in { 4.8, 7.0 } do
			local wc = floorAt(K, x, V.z0 + 2.0, 0, 2.2, 3.2, 3.8, 0)
			if wc then
				wheelchair(K, wc)
				n += 1
			end
		end
		if n > 0 then
			local d = wallSpot(K, "back", 3.6, 4.6, 5.8, 5.9, 0.4)
			if d then
				K:plate("WheelSign", 3.4, 1.0, 0.05, d, col(NAVY))
				tx(K, "WheelSignText", 3.2, 0.85, d * CF(0, 0, 0.055), "♿ 휠체어 보관 · 자유롭게 이용하세요", WHITE, nil, { font = FONT_B })
			end
		end
		-- 엘리베이터 옆 층별 안내
		local d2 = wallSpot(K, "back", 3.6, 3.8, 8.4, 38.6, 0.5)
		if d2 then
			K:plate("FloorDirFrame", 3.4, 4.4, 0.06, d2, lk(70, 74, 78, M.Metal))
			K:plate("FloorDirFace", 3.2, 4.2, 0.07, d2, lk(250, 250, 248))
			K:plate("FloorDirBand", 3.2, 0.6, 0.075, d2 * CF(0, 1.8, 0), col(TEAL))
			tx(K, "FloorDirTitle", 3.0, 0.45, d2 * CF(0, 1.8, 0.08), "층별 안내", WHITE, nil, { font = FONT_K })
			tx(K, "FloorDirR", 3.0, 0.8, d2 * CF(0, 1.0, 0.08), "R   옥상 (관계자 외 출입금지)", GREY_T, nil, { font = FONT_M, align = "Left" })
			tx(K, "FloorDir2", 3.0, 1.0, d2 * CF(0, 0.1, 0.08), "2F  입원실 201·202 · 간호사실\n      건강검진센터 · 휴게실", INK, nil, { font = FONT_B, align = "Left" })
			tx(K, "FloorDir1", 3.0, 1.0, d2 * CF(0, -1.2, 0.08), "1F  접수 · 진료실 · 주사실\n      약국 · 화장실", TEAL_D, nil, { font = FONT_B, align = "Left" })
		end
		-- 화장실 앞 매단 표지 · 손 소독제
		hangSign(K, 51.0, -4.6, 6.0, 1.0, 7.8, 0, "🚹 남자 화장실    여자 화장실 🚺", "🚹 남자 화장실    여자 화장실 🚺", { bg = WHITE, fg = NAVY, band = NAVY })
		local d3 = wallSpot(K, "back", 1.0, 3.4, 4.8, 57.6, 0.6)
		if d3 then
			sanitizerWall(K, d3)
		end
		hangSign(K, -14.0, 6.9, 5.0, 1.0, 7.8, PI / 2, "← 접수 · 진료실 · 약국", "엘리베이터 · 화장실 →")
		hangSign(K, -40.0, 3.0, 4.0, 1.0, 7.8, PI / 2, "← 비상구", "← 비상구", { bg = GREEN_EXIT, fg = WHITE, band = darker(GREEN_EXIT, 0.3) })
	end)
	-- 손잡이 (복도 쪽 벽 · 바깥벽 문 사이) · 코너 보호대 ---------------------------------------------------------------
	step(K, "rails", function()
		handrailSpans(K, "front", 2.9, 3)
		handrailSpans(K, "back", 2.9, 4)
		K:free(function()
			for _, x in { -12.0, 0.4 } do
				for _, sd in { -1, 1 } do
					K:box("CornerGuard", V3(0.12, 4.5, 0.6), CF(x + sd * 0.0, 2.6, V.z1 - 0.3), lk(200, 204, 206, M.Plastic))
				end
			end
		end)
	end)
	K.clinicCommon = { clock = true }
end

-- 침대 머리 쪽 헤드월 유닛 (산소 · 석션 · 콘센트 · 조명 · 호출). pcf = 유닛 앞면 가운데 바닥 (+Z 침대 쪽)
local function headwall(K: any, pcf: CFrame, w: number, h: number, label: string)
	K:box("HeadwallPanel", V3(w, h, 0.35), pcf * CF(0, h / 2, -0.175), lk(244, 244, 240))
	K:box("HeadwallWood", V3(w, 1.2, 0.37), pcf * CF(0, 2.6, -0.17), lk(196, 166, 126, M.Wood))
	K:box("HeadwallRail", V3(w - 0.2, 0.7, 0.2), pcf * CF(0, h - 0.9, 0.08), lk(230, 232, 232, M.Plastic))
	local lamp = K:box("HeadwallLamp", V3(w - 0.6, 0.06, 0.12), pcf * CF(0, h - 1.2, 0.12), col(C3(255, 240, 214), M.Neon))
	-- 산소 (초록) · 석션 (노랑) 아울렛 + 유량계
	local oc = pcf * CF(-w / 2 + 0.6, h - 0.9, 0.2)
	K:plate("O2Outlet", 0.42, 0.42, 0.06, oc, col(C3(40, 160, 80), M.Plastic))
	tx(K, "O2Label", 0.36, 0.14, oc * CF(0, 0.3, 0.02), "O₂", WHITE, C3(40, 160, 80), { d = 0.005 })
	K:vcyl("O2Flowmeter", 0.7, 0.18, oc * CF(0, -0.55, 0.25), { c = C3(220, 240, 230), m = M.Glass, t = 0.35 })
	K:ball("O2Ball", 0.1, oc * CF(0, -0.45, 0.25), col(C3(240, 240, 240)))
	K:vcyl("O2Humidifier", 0.5, 0.32, oc * CF(0, -1.1, 0.28), { c = C3(210, 236, 246), m = M.Glass, t = 0.4 })
	local sc = pcf * CF(-w / 2 + 1.25, h - 0.9, 0.2)
	K:plate("SuctionOutlet", 0.42, 0.42, 0.06, sc, col(C3(240, 200, 40), M.Plastic))
	K:vcyl("SuctionCanister", 0.8, 0.45, sc * CF(0, -0.8, 0.3), { c = C3(236, 240, 242), m = M.Glass, t = 0.35 })
	K:vcyl("SuctionLid", 0.08, 0.48, sc * CF(0, -0.36, 0.3), lk(60, 120, 200, M.Plastic))
	for k = 0, 1 do
		local pc = pcf * CF(w / 2 - 0.55 - k * 0.5, h - 0.9, 0.18)
		K:plate("PowerOutlet", 0.36, 0.42, 0.04, pc, lk(250, 250, 250, M.Plastic))
		K:disc("PowerSocket", 0.18, 0.02, pc * CF(0, 0, 0.05) * ANG(PI / 2, 0, 0), lk(220, 220, 216))
	end
	-- 간호사 호출 (빨간 버튼 + 줄)
	local cc = pcf * CF(w / 2 - 1.6, h - 0.9, 0.2)
	K:plate("NurseCallPlate", 0.5, 0.5, 0.05, cc, lk(250, 250, 250, M.Plastic))
	K:disc("NurseCallBtn", 0.26, 0.06, cc * CF(0, 0, 0.07) * ANG(PI / 2, 0, 0), col(C3(220, 40, 40), M.Neon))
	K:seg("NurseCallCord", (cc * CF(0, -0.25, 0.1)).Position, (cc * CF(0.2, -2.2, 0.6)).Position, 0.04, lk(240, 240, 240, M.Plastic))
	K:box("NurseCallPendant", V3(0.25, 0.5, 0.16), cc * CF(0.2, -2.45, 0.6), lk(240, 240, 240, M.Plastic))
	-- 환자 명패
	tx(K, "PatientCard", 1.4, 0.55, pcf * CF(0, 3.35, 0.01), label, INK, C3(250, 250, 246), { font = FONT_M, d = 0.01 })
	return lamp
end

-- 오버베드 테이블 (pcf 바닥, +Z = 침대 쪽)
local function overbedTable(K: any, pcf: CFrame, top: number?)
	local tp = top or 3.2
	K:box("OBTBase", V3(0.25, 0.15, 2.2), pcf * CF(-1.0, 0.25, 0), lk(200, 204, 206, M.Metal))
	K:box("OBTBase2", V3(1.4, 0.15, 0.25), pcf * CF(-0.4, 0.25, -1.0), lk(200, 204, 206, M.Metal))
	for _, z in { -1.0, 1.0 } do
		K:ball("OBTCaster", 0.2, pcf * CF(-1.0, 0.1, z), LK.black)
	end
	K:ball("OBTCaster", 0.2, pcf * CF(0.2, 0.1, -1.0), LK.black)
	K:box("OBTColumn", V3(0.2, tp - 0.3, 0.2), pcf * CF(-1.0, 0.3 + (tp - 0.3) / 2, -0.9), LK.chrome)
	K:box("OBTTop", V3(2.6, 0.12, 1.3), pcf * CF(0, tp, -0.3), lk(196, 166, 126, M.Wood))
	K:box("OBTEdge", V3(2.62, 0.06, 1.32), pcf * CF(0, tp - 0.08, -0.3), lk(230, 232, 232, M.Plastic))
	-- 환자식 식판 (죽 · 반찬 · 물)
	K:box("MealTray", V3(1.5, 0.08, 0.95), pcf * CF(0.2, tp + 0.1, -0.3), lk(250, 244, 230, M.Plastic))
	K:vcyl("MealBowl", 0.25, 0.5, pcf * CF(-0.15, tp + 0.26, -0.3), lk(250, 250, 250))
	K:disc("MealPorridge", 0.42, 0.02, pcf * CF(-0.15, tp + 0.38, -0.3), lk(244, 232, 200))
	K:vcyl("MealSide", 0.12, 0.3, pcf * CF(0.45, tp + 0.2, -0.5), lk(250, 250, 250))
	K:disc("MealKimchi", 0.24, 0.02, pcf * CF(0.45, tp + 0.27, -0.5), col(C3(200, 60, 40)))
	K:vcyl("MealSide", 0.12, 0.3, pcf * CF(0.45, tp + 0.2, -0.1), lk(250, 250, 250))
	K:disc("MealVeg", 0.24, 0.02, pcf * CF(0.45, tp + 0.27, -0.1), col(C3(90, 150, 60)))
	K:box("MealSpoon", V3(0.06, 0.02, 0.6), pcf * CF(0.75, tp + 0.15, -0.3), LK.chrome)
end

-- 보호자 간이침대 (접이식 비닐 소파베드), pcf 바닥, 길이 방향 = Z
local function guardianBed(K: any, pcf: CFrame)
	local vl = lk(46, 62, 92, M.Leather)
	K:box("GBFrame", V3(2.4, 0.12, 6.0), pcf * CF(0, 1.0, 0), lk(170, 176, 182, M.Metal))
	for _, sz in { -2.7, 2.7 } do
		for _, sx in { -1.0, 1.0 } do
			K:seg("GBLeg", pcf * V3(sx, 0.95, sz), pcf * V3(sx, 0.05, sz), 0.1, lk(170, 176, 182, M.Metal))
		end
	end
	for i = 0, 2 do
		K:slab("GBCushion", 2.4, 1.95, 0.45, 0.15, pcf * CF(0, 1.3, -2.0 + i * 2.0), vl)
	end
	K:box("GBBlanket", V3(2.3, 0.2, 1.2), pcf * CF(0, 1.62, 2.2), lk(230, 210, 160, M.Fabric))
	K:ell("GBPillow", V3(1.4, 0.3, 0.8), pcf * CF(0, 1.66, -2.4), lk(250, 250, 250, M.Fabric))
end

-- 병실 화장실 (칸막이 + 문 + 변기 · 세면대 · 손잡이 · 비상벨). 반환 문 Model, 경첩
local function wardBathroom(K: any, x0: number, x1: number, z0: number, z1: number, doorSide: string, doorU: number)
	local V = K.V
	local H = V.H
	local t = 0.4
	-- 칸막이: doorSide = "x" (x = xEdge 벽에 문) — 칸 안쪽은 (x0..x1, z0..z1)
	local xEdge = if doorSide == "xmin" then x0 else x1
	local dz0, dz1 = doorU - 1.6, doorU + 1.6
	local doorInfo
	K:free(function()
		local inner = col(C3(236, 240, 240), M.SmoothPlastic)
		-- z0 쪽 벽 (침대 방향)
		K:box("BathWall", V3(x1 - x0, H, t), CF((x0 + x1) / 2, H / 2, z0), lk(242, 242, 238))
		-- 문 쪽 벽 (구멍)
		local function wz(a: number, b: number, y0: number, y1: number)
			if b - a > 0.05 then
				K:box("BathWall", V3(t, y1 - y0, b - a), CF(xEdge, (y0 + y1) / 2, (a + b) / 2), lk(242, 242, 238))
			end
		end
		wz(z0 - t / 2, dz0, 0, H)
		wz(dz1, z1, 0, H)
		wz(dz0, dz1, 7.0, H)
		K:box("BathJamb", V3(t + 0.1, 7.0, 0.14), CF(xEdge, 3.5, dz0), LK.alu)
		K:box("BathJamb", V3(t + 0.1, 7.0, 0.14), CF(xEdge, 3.5, dz1), LK.alu)
		K:box("BathHead", V3(t + 0.1, 0.14, dz1 - dz0 + 0.14), CF(xEdge, 7.0, doorU), LK.alu)
		-- 안쪽: 타일 벽 · 바닥
		K:box("BathFloor", V3(x1 - x0 - t, 0.03, z1 - z0 - t), CF((x0 + x1) / 2, 0.025, (z0 + z1) / 2), lk(196, 200, 204, M.CeramicTiles))
		-- 변기 (안쪽 벽 쪽)
		local tx0 = if doorSide == "xmin" then x1 - 1.8 else x0 + 1.8
		local tz = z1 - 1.2
		local tcf = CF(tx0, 0, tz) * ANG(0, PI, 0)
		K:box("ToiletTank", V3(1.5, 1.4, 0.6), tcf * CF(0, 2.4, -0.8), lk(250, 250, 250))
		K:box("ToiletBase", V3(0.9, 1.3, 1.2), tcf * CF(0, 0.65, 0), lk(250, 250, 250))
		K:ell("ToiletBowl", V3(1.3, 0.5, 1.7), tcf * CF(0, 1.35, 0.15), lk(250, 250, 250))
		K:ell("ToiletSeat", V3(1.35, 0.12, 1.75), tcf * CF(0, 1.62, 0.15), lk(240, 240, 238))
		K:box("ToiletLid", V3(1.3, 1.3, 0.1), tcf * CF(0, 2.3, -0.48), lk(244, 244, 242))
		-- 안전 손잡이 (변기 옆 L 자) · 비상벨
		local gx = tx0 + (if doorSide == "xmin" then 1.2 else -1.2)
		K:seg("GrabBar", Vector3.new(gx, 2.4, tz - 1.0), Vector3.new(gx, 2.4, tz + 0.8), 0.14, LK.chrome)
		K:seg("GrabBar", Vector3.new(gx, 2.4, tz - 1.0), Vector3.new(gx, 4.4, tz - 1.0), 0.14, LK.chrome)
		K:box("BathCallBox", V3(0.1, 0.5, 0.4), CF(gx + (if doorSide == "xmin" then 0.4 else -0.4), 3.6, tz + 0.6), col(C3(220, 40, 40)))
		K:seg("BathCallCord", Vector3.new(gx, 3.4, tz + 0.6), Vector3.new(gx, 0.8, tz + 0.6), 0.04, col(C3(220, 40, 40)))
		-- 세면대 + 거울
		local sx = (x0 + x1) / 2 + (if doorSide == "xmin" then 0.6 else -0.6)
		K:box("BathBasin", V3(1.6, 0.4, 1.1), CF(sx, 2.7, z0 + t / 2 + 0.55), lk(250, 250, 250))
		K:vcyl("BathTap", 0.4, 0.1, CF(sx, 3.1, z0 + t / 2 + 0.2), LK.chrome)
		K:box("BathMirror", V3(1.6, 1.8, 0.04), CF(sx, 4.6, z0 + t / 2 + 0.03), Look.mirror)
		K:box("BathLamp", V3(1.2, 0.06, 0.4), CF((x0 + x1) / 2, H - 0.05, (z0 + z1) / 2), col(C3(255, 244, 226), M.Neon))
		-- 문 바깥 표지
		local sgn = if doorSide == "xmin" then -1 else 1
		tx(K, "BathSign", 1.6, 0.5, faceCF(Vector3.new(xEdge + sgn * (t / 2 + 0.02), 7.6, doorU), Vector3.new(sgn, 0, 0)), "화장실 · WC", WHITE, TEAL, { font = FONT_K, free = true })
		doorInfo = { x = xEdge, z0 = dz0, z1 = dz1, sgn = sgn }
		_ = inner
	end)
	local m = K:group("BathDoor", function()
		K:free(function()
			local zc = (dz0 + dz1) / 2
			K:box("BathDoorLeaf", V3(0.14, 6.85, dz1 - dz0 - 0.12), CF(xEdge, 3.45, zc), lk(236, 232, 224, M.SmoothPlastic))
			K:box("BathDoorHandle", V3(0.3, 0.12, 0.5), CF(xEdge + doorInfo.sgn * 0.12, 3.4, dz1 - 0.55), LK.chrome)
			K:box("BathDoorLouver", V3(0.15, 0.5, (dz1 - dz0) * 0.6), CF(xEdge, 0.6, zc), lk(200, 196, 188))
			tx(K, "BathDoorStatus", 0.8, 0.25, faceCF(Vector3.new(xEdge + doorInfo.sgn * 0.09, 4.4, dz1 - 0.55), Vector3.new(doorInfo.sgn, 0, 0)), "비어 있음", C3(40, 160, 80), WHITE, { d = 0.01, free = true })
		end)
	end)
	local hinge = (K.cf * CF(xEdge, 0, dz0 + 0.06)).Position
	return m, hinge, doorInfo
end

-- 가로 블라인드 (창 앞, 반쯤 내림) + 올리기/내리기
local function blinds(K: any, x0: number, x1: number, z: number, yTop: number, yLow: number, object: string)
	local slats = {}
	local n = math.floor((yTop - yLow) / 0.22)
	local w = x1 - x0
	local cx = (x0 + x1) / 2
	K:free(function()
		K:box("BlindHeadrail", V3(w, 0.3, 0.5), CF(cx, yTop + 0.15, z), lk(240, 240, 238, M.Metal))
		for i = 1, n do
			local s = K:box("BlindSlat", V3(w - 0.1, 0.03, 0.42), CF(cx, yTop - i * 0.22, z) * ANG(math.rad(-25), 0, 0), lk(236, 238, 236, M.Metal))
			table.insert(slats, s)
		end
		local br = K:box("BlindBottomRail", V3(w - 0.1, 0.08, 0.45), CF(cx, yTop - n * 0.22 - 0.1, z), lk(220, 222, 222, M.Metal))
		table.insert(slats, br)
		for _, x in { x0 + 1.0, x1 - 1.0 } do
			K:seg("BlindCord", Vector3.new(x, yTop, z + 0.26), Vector3.new(x, yTop - n * 0.22 - 1.2, z + 0.26), 0.03, lk(240, 240, 240))
		end
	end)
	local base = {}
	for i, s in slats do
		base[i] = s.CFrame
	end
	local tab = slats[#slats]
	if not tab then
		return
	end
	return Interact.toggle(K, tab, {
		object = object,
		state = false,
		onText = "블라인드 내리기",
		offText = "블라인드 올리기",
		sound = "rbxasset://sounds/swoosh.wav",
		on = function(up: boolean)
			for i, s in slats do
				if s.Parent then
					local target = if up then base[i] + K.cf.UpVector * ((i / #slats) * (yTop - yLow) * 0.92) else base[i]
					TweenService:Create(s, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { CFrame = target }):Play()
				end
			end
		end,
	})
end

-- 2F 입원실 201 · 202 -----------------------------------------------------------------------------------------------
BUILD.ward = function(K: any, V: any)
	local is201 = V.room == "ward201"
	local roomNo = if is201 then "201" else "202"
	-- 문 (구멍) 위치: Door_입원실 모델의 Jamb
	local jx = {}
	for _, r in V.byName.Jamb or {} do
		local p = r.part.Parent
		if p and string.find(p.Name, "입원실") then
			table.insert(jx, r.c.X)
		end
	end
	table.sort(jx)
	local doorX = if #jx >= 2 then (jx[1] + jx[#jx]) / 2 else (if is201 then -17.3 else 16.6)
	local doorLeft = doorX < 0
	-- 침대
	local seats = {}
	for _, r in V.byName.BedSeat or {} do
		table.insert(seats, r)
	end
	table.sort(seats, function(a, b)
		return a.c.X < b.c.X
	end)
	local avoid = {}
	for _, s in seats do
		local bf, L, W = bedFrame(V, s)
		local c = bf.Position
		table.insert(avoid, { c.X - W / 2 - 1.8, c.Z - L / 2 - 1.8, c.X + W / 2 + 1.8, c.Z + L / 2 + 1.2 })
	end
	step(K, "ceiling", function()
		ceilingKit(K, V, { lights = 5, avoid = avoid })
	end)
	step(K, "floor", function()
		floorKit(K, V, { look = lk(206, 182, 148, M.WoodPlanks), grout = lk(160, 136, 104), tile = 1.4, plank = true })
		baseKit(K, V, { "back", "left", "right", "front" })
	end)
	local labels = if is201 then { "201-1  김*수 님\n담당 김선생 · 낙상주의", "201-2  이*희 님\n담당 김선생 · 금식" } else { "202-1  박*민 님\n담당 김선생", "202-2  최*영 님\n담당 김선생 · 알레르기" }
	local nCurtain = 0
	for i, seat in seats do
		step(K, "bed" .. i, function()
			local bf, L, W = hospitalBed(K, V, seat, { chart = labels[i], blanket = if i == 1 then lk(150, 196, 214, M.Fabric) else lk(196, 220, 170, M.Fabric), remoteSide = if seat.c.X < 0 then 1 else -1 })
			local bc = bf.Position
			-- 헤드월 유닛 (머리 뒤)
			local hw = bf * CF(0, 0, L / 2 + 1.05) * ANG(0, PI, 0)
			if K:spot(hw * CF(0, 0, -0.2), V3(W + 1.6, 6.8, 0.6), 0) then
				K:free(function()
					headwall(K, hw, W + 1.6, 6.8, labels[i])
				end)
			end
			-- 링거 (맵 자리)
			local iv = nearest(V, "IVPole", seat.c, 8)
			if iv then
				for _, q in siblings(V, iv) do
					if q.name == "IVPole" or q.name == "IVBag" or q.name == "IVLine" or q.name == "IVBase" then
						hideRec(K, q)
					end
				end
				K:free(function()
					local drip = ivPole(K, CF(iv.c.X, 0, iv.c.Z), { pump = i == 2, to = (bf * CF(W / 2 - 0.3, seat.max.Y + 0.1, 0.6)).Position })
					dripAnim(K, drip)
				end)
			end
			-- 사물함 (맵 자리, 냉장 칸)
			local lc = nearest(V, "BedsideCabinet", seat.c, 8)
			if lc then
				for _, q in siblings(V, lc) do
					if q.name == "BedsideCabinet" or q.name == "BedsideTop" or q.name == "WaterCup" then
						hideRec(K, q)
					end
				end
				K:free(function()
					local face = if lc.c.X < seat.c.X then Vector3.xAxis else -Vector3.xAxis
					bedLocker(K, faceCF(Vector3.new(lc.c.X, 0, lc.c.Z), face), 1.9, 1.9, 2.8, { fridge = true })
				end)
			end
			-- 오버베드 테이블 (사물함 반대쪽 옆에 세워 둠)
			local side = if lc and lc.c.X > seat.c.X then -1 else 1
			local ob = bf * CF(side * (W / 2 + 1.6), 0, -1.6) * ANG(0, -side * PI / 2, 0)
			if K:spot(ob, V3(2.7, 3.4, 2.4), 0) then
				overbedTable(K, ob, 3.1)
			end
			-- 개인 TV (팔걸이 모니터, 침대 옆 위)
			local tvb = bf * CF(-side * (W / 2 + 0.55), 0, L / 2 - 0.2)
			K:free(function()
				K:seg("BedTVArm", (tvb * CF(0, 6.0, 0.4)).Position, (tvb * CF(0, 5.4, -1.6)).Position, 0.12, LK.alu)
				local tc = tvb * CF(0, 5.2, -1.7) * ANG(0, -side * 0.5, 0) * ANG(math.rad(-12), 0, 0)
				K:box("BedTV", V3(1.6, 1.0, 0.12), tc, lk(30, 30, 34, M.Plastic))
				tx(K, "BedTVScreen", 1.45, 0.85, tc * CF(0, 0, 0.065), "카드 TV\n채널 11 · 뉴스", C3(220, 230, 240), C3(20, 40, 70), { glow = 1.0, d = 0.005, free = true })
			end)
			-- U 커튼 (발 쪽에 모음)
			local runs = bedCurtains(K, bf, L, W, { gapX = 1.3, headExt = 0.4 })
			if runs[1] then
				nCurtain += 1
				curtainToggle(K, runs, runs[1].tab, string.format("%s-%d 침대 커튼", roomNo, i), 0.12)
			end
			-- 보호자 간이침대 (바깥쪽)
			local gx = if seat.c.X < 0 then V.x0 + 2.2 else V.x1 - 2.2
			local gp = CF(gx, 0, bc.Z - 0.5)
			if math.abs(gx - bc.X) > W / 2 + 3.6 and K:spot(gp, V3(2.6, 2.0, 6.2), 0) then
				guardianBed(K, gp)
			end
		end)
	end
	-- 방문객 의자 (Seat, 자리 그대로)
	step(K, "chairs", function()
		for _, ch in V.chairs do
			if ch.seat.name == "Seat" then
				hideList(K, ch.parts)
				K:free(function()
					armChair(K, faceCF(Vector3.new(ch.c.X, 0, ch.c.Z), ch.face), ch.top, LK.vinylMint)
				end)
			end
		end
	end)
	-- 옷장 (맵 자리) -------------------------------------------------------------------------------------------
	step(K, "wardrobe", function()
		local wr = V:first("Wardrobe")
		if not wr then
			return
		end
		hideNames(K, { "Wardrobe", "WardrobeSeam" })
		local pcf, w, d, h = recFrame(wr, Vector3.xAxis)
		K:free(function()
			K:box("WardrobeBody", V3(w, h, d), pcf * CF(0, h / 2, 0), lk(232, 220, 200, M.Wood))
			for k = 0, 1 do
				local x = -w / 4 + k * w / 2
				K:plate("WardrobeDoor", w / 2 - 0.08, h - 0.4, 0.04, pcf * CF(x, h / 2, d / 2), lk(214, 190, 150, M.Wood))
				K:plate("WardrobePull", 0.08, 1.4, 0.06, pcf * CF(x + (if k == 0 then w / 4 - 0.3 else -w / 4 + 0.3), h / 2, d / 2 + 0.04), LK.chrome)
				tx(K, "WardrobeNo", 0.9, 0.35, pcf * CF(x, h - 0.6, d / 2 + 0.045), string.format("%s-%d", roomNo, k + 1), INK, WHITE, { d = 0.005 })
			end
			K:box("WardrobeKick", V3(w - 0.1, 0.3, d - 0.1), pcf * CF(0, 0.15, -0.05), lk(70, 74, 78))
		end)
	end)
	-- 화장실 (방 구석 칸막이) ---------------------------------------------------------------------------------------
	step(K, "bath", function()
		local x0, x1, z0, z1, side
		if is201 then
			x0, x1, z0, z1, side = 15.2, V.x1, 6.4, V.z1, "xmin"
		else
			local wr = V:first("Wardrobe")
			local wx = if wr then wr.max.X + 0.3 else V.x0 + 3
			x0, x1, z0, z1, side = wx, wx + 6.8, 6.4, V.z1, "xmax"
		end
		local okSpot = K:spot(CF((x0 + x1) / 2, 0, (z0 + z1) / 2), V3(x1 - x0 - 0.2, 2, z1 - z0 - 0.2), 0)
		if not okSpot then
			note(K, "ward bath: spot blocked")
		end
		-- 화장실 벽면은 공통 부착물이 쓰지 않게
		wallUse(K, "front", -x1 - 0.3, -x0 + 0.3, 0, V.H)
		if x1 >= V.x1 - 0.5 then
			wallUse(K, "right", z0 - 0.3, z1 + 0.3, 0, V.H)
		end
		local m, hinge, info = wardBathroom(K, x0, x1, z0, z1, side, (z0 + z1) / 2 + 0.6)
		if m and hinge and info then
			Interact.swing(K, m, hinge, Vector3.yAxis, info.sgn * math.rad(95), { object = "병실 화장실", openText = "문 열기", closeText = "문 닫기" })
		end
		-- 맵 휴지통 · 호출판이 칸 안에 들면 숨김
		for _, n in { "Bin", "CallPanel" } do
			for _, r in V.byName[n] or {} do
				if r.c.X > x0 - 0.2 and r.c.X < x1 + 0.2 and r.c.Z > z0 - 0.2 then
					hideRec(K, r)
				end
			end
		end
		Common.useCeil(K, (x0 + x1) / 2, (z0 + z1) / 2)
	end)
	-- 블라인드 (창 앞) ----------------------------------------------------------------------------------------------
	step(K, "blind", function()
		hideNames(K, { "Blind", "BlindBox" })
		blinds(K, V.x0 + 0.3, V.x1 - 0.3, V.z0 + 0.45, V.H - 0.5, 4.6, "병실 블라인드")
	end)
	-- 세면대 · 손 소독 · 병실 안내 --------------------------------------------------------------------------------------
	step(K, "front", function()
		local su = wallU("front", Vector3.new(if doorLeft then 4.8 else -4.8, 0, 0))
		local sk = wallFloorNear(K, "front", su, 3.4, 2.2, 3.0, 3, 0)
		if sk then
			sinkUnit(K, sk, 3.4, 2.2, 3.0, {})
		end
		local du = wallU("front", Vector3.new(doorX + (if doorLeft then 3.2 else -3.2), 0, 0))
		local d = wallSpot(K, "front", 1.0, 3.6, 5.0, du, 0.6)
		if d then
			sanitizerWall(K, d)
		end
		local d2 = wallSpot(K, "front", 3.4, 4.8, 7.4, du + (if doorLeft then -2.6 else 2.6), 0.5)
		if d2 then
			poster(K, d2, 3.2, 2.5, "입원실 " .. roomNo .. " · 2인실", "면회  평일 18:00~20:00\n주말 10:00~12:00 · 18:00~20:00\n보호자 1인 상주 · 출입 시 손 소독", WHITE, INK, TEAL, WHITE, 0.24)
		end
		local d3 = wallSpot(K, "left", 3.0, 4.6, 7.0, 0, 0.6)
		if d3 then
			poster(K, d3, 2.8, 2.2, "낙상 예방 수칙", "침대 난간 올리기\n일어날 때 천천히\n밤에는 보호자와 함께\n미끄럼 방지 신발", WHITE, INK, C3(230, 140, 30), WHITE, 0.24)
		end
	end)
	K.clinicCommon = { clock = true }
end

-- 공통 마감 (방마다 끝에) ------------------------------------------------------------------------------------
local PLANTS = { "monstera", "ficus", "snake", "olive" }

local function finishCommon(K: any, V: any, o: any?)
	local oo: any = o or {}
	step(K, "upgrades", function()
		Common.upgrades(K, V, { plants = oo.plants or PLANTS })
	end)
	step(K, "fixtures", function()
		Common.fixtures(K, V, { license = false, clock = oo.clock ~= false, clockLook = { frame = lk(230, 232, 232, M.Plastic) } })
	end)
	step(K, "ceilfx", function()
		Common.ceiling(K, V, { ceiling = {}, cctv = oo.cctv, lights = { kind = "none" } })
	end)
end

function T.style(V: any): any
	-- Common 단계는 전부 build 에서 (틀을 다시 맞춘 V 로) 직접 부름
	return {
		chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false,
		clock = false, license = false, cctv = false, ceiling = false, lights = { kind = "none" },
		skip = { floor = true, ceiling = true, walls = true, chairs = true, stools = true, tables = true, counters = true, upgrades = true, fixtures = true },
	}
end

local ROOM_OF_TYPE = {
	clinic_lobby = "lobby", clinic_waiting = "waiting", clinic_consult = "consult", clinic_pharmacy = "pharmacy",
	clinic_treat = "treat", clinic_hall = "backhall", clinic_ward = "ward", clinic_nurse = "nurse", clinic_lounge = "lounge",
	clinic_checkup = "checkup",
}

function T.build(K: any, V: any, S: any)
	local V2 = refit(V)
	K.V = V2
	K.cf = V2.cf
	-- 프롬프트 금지 지점: 기본 + 병원 서버 프롬프트 앵커 (접수대 · 진료). DeskBell 은 이 시설에 서버 앵커가 없어 뺌
	local hp = {}
	for _, n in { "WaterPurifier", "WorkDesk", "FrontDesk", "HospitalPrompt_desk", "HospitalPrompt_doctor" } do
		for _, r in V2.byName[n] or {} do
			table.insert(hp, r.c)
		end
	end
	for _, t in V2.tables or {} do
		table.insert(hp, (t.min + t.max) / 2)
	end
	K.hostPts = hp
	local room = V.room or ""
	local key = if string.sub(room, 1, 4) == "ward" then "ward" else room
	local fn = BUILD[key] or BUILD[ROOM_OF_TYPE[V.type or ""] or ""]
	note(K, string.format("room %s W=%.1f D=%.1f angle=%.2f keep=%d", room, V2.W, V2.D, math.deg(V2.bAngle or 0), #V2.keep))
	if fn then
		local ok, err = pcall(fn, K, V2)
		if not ok then
			note(K, "room error: " .. tostring(err))
		end
	end
	finishCommon(K, V2, K.clinicCommon)
end

T._debug = {}

return T
