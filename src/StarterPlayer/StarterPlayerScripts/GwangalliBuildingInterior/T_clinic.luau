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
	K:free(function()
		K:box("CeilingSkin", V3(V.W - 0.04, 0.02, V.D - 0.04), CF(0, H - 0.018, 0), oo.skin or lk(238, 237, 232, M.Plaster))
		for _, x in mx do
			K:box("CeilingTBar", V3(0.18, 0.08, V.D - 0.08), CF(x, H - 0.05, 0), barL)
		end
		for _, z in mz do
			K:box("CeilingTBar", V3(V.W - 0.08, 0.08, 0.18), CF(0, H - 0.05, z), barL)
		end
	end)
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
		K:seg("IVTube", (dc * CF(0, -0.2, 0)).Position, (pcf * V3(0.5, top - 3.0, 0)).Position, 0.04, { c = C3(230, 240, 240), m = M.Glass, t = 0.2 })
		K:seg("IVTube", (pcf * V3(0.5, top - 3.0, 0)).Position, tubeEnd, 0.04, { c = C3(230, 240, 240), m = M.Glass, t = 0.2 })
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
		table.insert(runs, curtainRun(K, { p(-gx, footZ), p(-gx, headZ) }, f0, oo))
	end
	if oo.right ~= false then
		table.insert(runs, curtainRun(K, { p(gx, footZ), p(gx, headZ) }, f0, oo))
	end
	if oo.foot ~= false then
		table.insert(runs, curtainRun(K, { p(-gx + 0.1, footZ), p(gx - 0.1, footZ) }, f0, oo))
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
			K:rbox("KioskBody", V3(1.6, 3.4, 1.0), 0.3, kp * CF(0, 0.12 + 1.7, -0.1) * ANG(0, PI / 2, 0), kioskL)
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
			local cx = (desk.min.X + desk.max.X) / 2
			local z = desk.max.Z + 2.2
			K:free(function()
				local c = CF(cx, 8.2, z)
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
	for _, n in { "WaterPurifier", "Bin", "TrashBin", "WorkDesk", "FrontDesk", "HospitalPrompt_desk", "HospitalPrompt_doctor", "BedSeat" } do
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
