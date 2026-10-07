-- GwangalliGameplay/Law/Hospital (server; owner: npc_mind): the people of 광안 메디컬 의원 (the map's
-- hospital). NPC + AI only: the building, its clinic UI (GwangalliGameplay/Health: the static 의사 김선생 /
-- 간호사 박선생 and their prompts) and any job / pay are not touched.
--
--   * WHO: 접수 (1), 의사 (2), 간호사 (3), 외래 환자 (3, they come and go), 입원 환자 (1), 보호자 (2).
--   * WHAT: a routine per role — the receptionist types at the desk, takes the next patient (a short
--     exchange), fetches a chart from the pharmacy corner; doctors do rounds (consult room -> treatment
--     room -> elevator -> wards -> nurse station); nurses move between the nurse station, the wards, the
--     treatment room and the lobby (calling the next patient); outpatients walk in from the forecourt,
--     check in, wait on a bench, go to the consult room and the pharmacy, then leave; a guardian walks
--     with them / sits by the inpatient's bed. Short talks when two of them meet at a spot.
--   * 응급실: Hospital.emergency(spec) (Law/Rescue when an ambulance delivers): a nurse and a doctor go to
--     the entrance, an emergency patient is taken to the treatment room.
--   * MOVE: a small graph of named spots (both floors; the elevator links them: they ride it out of
--     sight a few seconds) walked with the Police motion contract (Police.newActor / moveAlong: the
--     clients play walk / idle from the leg speed and the NpcAct attribute).
--   * COST: only while a player is within ACTIVE_R of the hospital (spawned on approach, removed a
--     while after everybody left); one think per actor every 0.5 s.
-- Debug: Hospital.status() (Law debug act "hospital").

local Players = game:GetService("Players")

local Hospital = {}

local Law: any
local ctx: any
local P: any

Hospital.CENTER = Vector3.new(-515, 7, 300)
Hospital.ACTIVE_R = 170
Hospital.IDLE_OFF = 45 -- s with nobody near before they are removed

-- spots: x, z, floor (1 = ground floor, 2 = upstairs). y comes from the floor under the spot.
local F1, F2 = 7.2, 21.2
local SPOTS = {
	fore = { -496, 252, 1 }, -- the forecourt, in front of the door
	door = { -496, 270, 1 }, -- just inside the automatic door
	lobby = { -505, 276, 1 },
	desk_front = { -515, 281, 1 }, -- the patient side of the reception desk
	desk = { -503, 284, 1 }, -- the staff end of the reception counter
	wait1 = { -466, 275, 1 },
	wait2 = { -466, 281, 1 },
	wait3 = { -466, 287, 1 },
	hall = { -505, 300, 1 },
	hall2 = { -525, 294, 1 }, -- the back corridor
	bench = { -520, 328, 1 }, -- the elevator hall
	pharm = { -540, 294, 1 }, -- the pharmacy window on the corridor
	cons_door = { -537, 297, 1 },
	cons = { -545, 285, 1 },
	treat_door = { -485, 296, 1 },
	treat = { -478, 308, 1 },
	treat_bed = { -468, 309, 1 },
	lift1 = { -548, 332, 1 },
	lift2 = { -548, 332, 2 },
	landing = { -540, 294, 2 }, -- between the elevator hall and the ward corridor
	corr2 = { -520, 290, 2 }, -- the ward corridor
	station = { -515, 284, 2 },
	w201_door = { -497, 293, 2 },
	w201 = { -480, 283, 2 },
	w201_bed = { -466, 282, 2 },
	w202_door = { -537, 292, 2 },
	w202 = { -550, 281, 2 },
	w202_bed = { -540, 281, 2 },
	check_door = { -543, 298, 2 },
	check = { -552, 312, 2 },
	lounge = { -478, 311, 2 },
}
local EDGES = {
	{ "fore", "door" }, { "door", "lobby" }, { "lobby", "desk_front" }, { "lobby", "wait1" }, { "wait1", "wait2" }, { "wait2", "wait3" },
	{ "lobby", "hall" }, { "desk_front", "hall" }, { "desk", "hall" }, { "wait3", "hall" }, { "hall", "hall2" }, { "hall2", "bench" },
	{ "hall2", "pharm" }, { "bench", "lift1" }, { "pharm", "lift1" }, { "hall2", "cons_door" }, { "cons_door", "cons" }, { "hall", "treat_door" },
	{ "treat_door", "treat" }, { "treat", "treat_bed" }, { "lift1", "lift2", lift = true },
	{ "lift2", "landing" }, { "landing", "corr2" }, { "corr2", "station" }, { "corr2", "w201_door" }, { "w201_door", "w201" }, { "w201", "w201_bed" },
	{ "corr2", "w202_door" }, { "w202_door", "w202" }, { "w202", "w202_bed" }, { "corr2", "check_door" }, { "check_door", "check" }, { "landing", "lounge" },
}
Hospital.SPOTS = SPOTS

local LINES = {
	desk_greet = { "어서 오세요, 접수 도와드릴게요.", "어디가 불편해서 오셨어요?", "처음 오셨어요? 신분증 주시겠어요?" },
	patient_desk = { "배가 너무 아파서요…", "어제부터 열이 나요.", "예약했는데요, 김○○이요.", "목이 따끔거려서요." },
	desk_wait = { "번호표 뽑고 잠시만 기다려 주세요.", "앉아 계시면 불러 드릴게요.", "곧 진료실에서 부를 거예요." },
	nurse_call = { "다음 분 진료실로 들어오세요~", "○○○님, 진료실 1번으로 오세요.", "기다리셨죠? 들어가실게요." },
	doctor_talk = { "어디 한번 봅시다…", "숨 크게 들이쉬어 보세요.", "약 처방해 드릴게요. 푹 쉬세요.", "큰 문제는 없어 보여요." },
	patient_thanks = { "감사합니다, 선생님.", "네, 알겠습니다.", "약은 어디서 받아요?" },
	pharm = { "약 나왔습니다, 하루 세 번이에요.", "식후 삼십 분에 드세요." },
	ward = { "오늘은 좀 어떠세요?", "열 재 볼게요~", "식사는 하셨어요?", "링거 확인할게요." },
	inpatient = { "많이 좋아졌어요.", "언제 퇴원해요?", "밥이 좀 싱거워요 ㅎㅎ", "밤에 잠이 잘 안 와요." },
	guardian = { "괜찮아? 조금만 참아.", "의사 선생님이 괜찮대.", "뭐 마실 거 사 올까?", "걱정 마, 금방 나을 거야." },
	staff_chat = { "201호 환자분 열 내렸어요.", "점심 드셨어요?", "오늘 환자 많네요…", "202호 링거 교체 부탁해요." },
	er_call = { "응급 환자 왔어요!", "처치실 비워 주세요, 응급이에요!", "들것 이쪽으로요!" },
	er_doctor = { "상태 어때요? 처치실로 바로!", "바이탈 체크하고 엑스레이 준비해요." },
}

local ROLE_LOOK = {
	doctor = { style = "doctor", age = "adult", acc = { "stethoscope" } },
	nurse = { style = "nurse", body = "f", age = "young", acc = { "clipboard" } },
	reception = { style = "reception", body = "f", age = "young" },
	patient = { age = "adult" },
	inpatient = { style = "gown", age = "adult", acc = { "bandage" } },
	guardian = { age = "adult" },
	er = { style = "gown", age = "adult", acc = { "bandage" } },
}
local ROLE_SPEED = { doctor = 6.4, nurse = 7, reception = 5.6, patient = 4.6, inpatient = 3.4, guardian = 5, er = 7 }

local actors: { any } = {}
local active = false
local lastNear = -1e9
local seqN = 0
local queue: { any } = {} -- emergencies waiting for staff
local broken: { string } = {} -- spots that are not reachable (test report)

local function now(): number
	return os.clock()
end

local function rnd(): number
	return math.random()
end

local function pick(list: { string }): string
	return list[1 + math.floor(rnd() * #list)]
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-------------------------------------------------------------------------------------------------
-- walkable grid (built from the real walls / furniture on start: no hand-made links through walls)
-------------------------------------------------------------------------------------------------
local G = { x0 = -582, z0 = 250, cell = 2, nx = 70, nz = 48 }
local grids: { [number]: any } = {} -- [floor] = { free = { [i] = bool }, y = floorY }
local spotCell: { [string]: any } = {} -- name -> { floor, ix, iz, pos }

local function idx(ix: number, iz: number): number
	return iz * G.nx + ix
end

local function cellPos(fl: number, ix: number, iz: number): Vector3
	return Vector3.new(G.x0 + (ix + 0.5) * G.cell, grids[fl].y, G.z0 + (iz + 0.5) * G.cell)
end

-- door leaves are open for people (a closed leaf blocks the ray, not the walk)
local function passable(part: BasePart): boolean
	if not part.CanCollide or part.Transparency >= 0.95 then
		return true
	end
	local n = part.Name
	if string.find(n, "Leaf") or string.find(n, "Threshold") or string.find(n, "Track") or string.find(n, "Prompt") or string.find(n, "Floor") or string.find(n, "Rug") or string.find(n, "Mat") then
		return true
	end
	local m = part.Parent
	while m and m ~= workspace do
		if m:IsA("Model") and string.sub(m.Name, 1, 5) == "Door_" then
			return not (string.find(n, "Jamb") or string.find(n, "Frame") or string.find(n, "Wall"))
		end
		m = m.Parent
	end
	return false
end

local function buildGrid(fl: number, floorY: number)
	local ov = OverlapParams.new()
	ov.FilterType = Enum.RaycastFilterType.Exclude
	local ex = {}
	for _, n in { "GwangalliNPCs", "GwangalliStreetLife", "GwangalliLawCars", "GwangalliTaxis", "GwangalliPlayerCars" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ex, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ex, p.Character)
		end
	end
	ov.FilterDescendantsInstances = ex
	local free = {}
	local size = Vector3.new(G.cell * 0.6, 3.2, G.cell * 0.6)
	for iz = 0, G.nz - 1 do
		for ix = 0, G.nx - 1 do
			local c = Vector3.new(G.x0 + (ix + 0.5) * G.cell, floorY + 0.6 + 1.6, G.z0 + (iz + 0.5) * G.cell)
			local okQ, parts = pcall(function()
				return workspace:GetPartBoundsInBox(CFrame.new(c), size, ov)
			end)
			local ok = okQ
			if okQ then
				for _, part in parts do
					if not passable(part) then
						ok = false
						break
					end
				end
			end
			-- something to stand on (not the outside drop / a hole)
			if ok then
				local hit = P.rayHit(Vector3.new(c.X, floorY + 2.4, c.Z), Vector3.new(c.X, floorY - 3, c.Z))
				if not hit or math.abs(hit.Position.Y - floorY) > 1.6 then
					ok = false
				end
			end
			free[idx(ix, iz)] = ok
		end
	end
	-- doorways are open: carve every door model's footprint on this floor (a closed leaf, a narrow
	-- gap between the jambs that the cell test would miss)
	local H = workspace:FindFirstChild("Gwangalli")
	H = H and H:FindFirstChild("hospital")
	H = H and H:FindFirstChild("광안 메디컬 의원")
	if H then
		for _, m in H:GetDescendants() do
			if m:IsA("Model") and (string.sub(m.Name, 1, 5) == "Door_" or string.sub(m.Name, 1, 8) == "AutoDoor") then
				local okB, cf, sz = pcall(function()
					return m:GetBoundingBox()
				end)
				if okB and math.abs(cf.Position.Y - (floorY + 4.5)) < 5 then
					local half = Vector3.new(sz.X * 0.5 + 0.6, 0, sz.Z * 0.5 + 0.6)
					local lo = (cf.Position - half)
					local hi = (cf.Position + half)
					for iz = math.max(0, math.floor((lo.Z - G.z0) / G.cell)), math.min(G.nz - 1, math.floor((hi.Z - G.z0) / G.cell)) do
						for ix = math.max(0, math.floor((lo.X - G.x0) / G.cell)), math.min(G.nx - 1, math.floor((hi.X - G.x0) / G.cell)) do
							free[idx(ix, iz)] = true
						end
					end
				end
			end
		end
	end
	grids[fl] = { free = free, y = floorY }
end

local function cellOf(p: Vector3): (number, number)
	return math.floor((p.X - G.x0) / G.cell), math.floor((p.Z - G.z0) / G.cell)
end

local function isFree(fl: number, ix: number, iz: number): boolean
	if ix < 0 or iz < 0 or ix >= G.nx or iz >= G.nz then
		return false
	end
	return grids[fl].free[idx(ix, iz)] == true
end

-- the nearest free cell to a point (spots that fall on furniture move next to it)
local function snap(fl: number, p: Vector3): (number?, number?)
	local cx, cz = cellOf(p)
	for r = 0, 5 do
		local best, bd = nil, math.huge
		for dz = -r, r do
			for dx = -r, r do
				if math.max(math.abs(dx), math.abs(dz)) == r and isFree(fl, cx + dx, cz + dz) then
					local d = dx * dx + dz * dz
					if d < bd then
						best, bd = { cx + dx, cz + dz }, d
					end
				end
			end
		end
		if best then
			return best[1], best[2]
		end
	end
	return nil, nil
end

-- A* on one floor (8 neighbours, no corner cutting) -> cells
local DIRS = { { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 }, { 1, 1, 1.414 }, { 1, -1, 1.414 }, { -1, 1, 1.414 }, { -1, -1, 1.414 } }
local function astar(fl: number, ax: number, az: number, bx: number, bz: number): { any }?
	local start, goal = idx(ax, az), idx(bx, bz)
	local g = { [start] = 0 }
	local prev = {}
	local open = { start }
	local inOpen = { [start] = true }
	local function h(i: number): number
		local x, z = i % G.nx, i // G.nx
		return math.sqrt((x - bx) ^ 2 + (z - bz) ^ 2)
	end
	local guard = 0
	while #open > 0 do
		guard += 1
		if guard > 6000 then
			return nil
		end
		local bi, bf = 1, math.huge
		for k, i in open do
			local f = g[i] + h(i)
			if f < bf then
				bi, bf = k, f
			end
		end
		local cur = table.remove(open, bi)
		inOpen[cur] = nil
		if cur == goal then
			local out = {}
			local n = cur
			while n do
				table.insert(out, 1, { n % G.nx, n // G.nx })
				n = prev[n]
			end
			return out
		end
		local cx, cz = cur % G.nx, cur // G.nx
		for _, d in DIRS do
			local nx, nz = cx + d[1], cz + d[2]
			if isFree(fl, nx, nz) and (d[3] < 1.2 or (isFree(fl, cx + d[1], cz) and isFree(fl, cx, cz + d[2]))) then
				local ni = idx(nx, nz)
				local ng = g[cur] + d[3]
				if ng < (g[ni] or math.huge) then
					g[ni] = ng
					prev[ni] = cur
					if not inOpen[ni] then
						inOpen[ni] = true
						table.insert(open, ni)
					end
				end
			end
		end
	end
	return nil
end

-- straight runs where the grid line between two cells is all free
local function lineFree(fl: number, a: any, b: any): boolean
	local n = math.max(math.abs(b[1] - a[1]), math.abs(b[2] - a[2])) * 2
	for k = 0, n do
		local u = if n == 0 then 0 else k / n
		local x = a[1] + (b[1] - a[1]) * u
		local z = a[2] + (b[2] - a[2]) * u
		for _, o in { { 0.25, 0.25 }, { -0.25, -0.25 }, { 0.25, -0.25 }, { -0.25, 0.25 } } do
			if not isFree(fl, math.floor(x + 0.5 + o[1]), math.floor(z + 0.5 + o[2])) then
				return false
			end
		end
	end
	return true
end

local function smooth(fl: number, cells: { any }): { Vector3 }
	local pts = {}
	local i = 1
	table.insert(pts, cellPos(fl, cells[1][1], cells[1][2]))
	while i < #cells do
		local j = #cells
		while j > i + 1 and not lineFree(fl, cells[i], cells[j]) do
			j -= 1
		end
		table.insert(pts, cellPos(fl, cells[j][1], cells[j][2]))
		i = j
	end
	return pts
end

local function buildWorld()
	table.clear(broken)
	buildGrid(1, F1)
	buildGrid(2, F2)
	for name, s in SPOTS do
		local fl = s[3]
		local p = Vector3.new(s[1], grids[fl].y, s[2])
		local ix, iz = snap(fl, p)
		if ix then
			spotCell[name] = { floor = fl, ix = ix, iz = iz, pos = cellPos(fl, ix, iz) }
		else
			table.insert(broken, name .. "(no floor)")
		end
	end
	-- every spot reachable from the door / the lift on its floor?
	for name, sc in spotCell do
		local from = spotCell[if sc.floor == 1 then "door" else "lift2"]
		if from and name ~= "fore" and not astar(sc.floor, from.ix, from.iz, sc.ix, sc.iz) then
			table.insert(broken, name)
		end
	end
end

-- the route between two spots: { { floor, pts }, ... } (a floor change = the elevator in between)
local routeCache: { [string]: any } = {}
local function routeOf(a: string, b: string): { any }?
	local key = a .. ">" .. b
	if routeCache[key] ~= nil then
		return routeCache[key] or nil
	end
	local A, B = spotCell[a], spotCell[b]
	local out = nil
	if A and B then
		local function leg(fl: number, x: any, y: any): { Vector3 }?
			local cells = astar(fl, x.ix, x.iz, y.ix, y.iz)
			return cells and smooth(fl, cells) or nil
		end
		if A.floor == B.floor then
			local pts = leg(A.floor, A, B)
			out = pts and { { floor = A.floor, pts = pts } } or nil
		else
			local L1, L2 = spotCell[if A.floor == 1 then "lift1" else "lift2"], spotCell[if B.floor == 1 then "lift1" else "lift2"]
			local p1 = L1 and leg(A.floor, A, L1)
			local p2 = L2 and leg(B.floor, L2, B)
			out = if p1 and p2 then { { floor = A.floor, pts = p1 }, { floor = B.floor, pts = p2, lift = true } } else nil
		end
	end
	routeCache[key] = out or false
	return out
end

-------------------------------------------------------------------------------------------------
-- actors
-------------------------------------------------------------------------------------------------
local function at(name: string): Vector3
	local n = spotCell[name]
	return if n then n.pos else Hospital.CENTER
end

local function spawnActor(role: string, where: string, k: number?): any?
	seqN += 1
	local o = P.newActor(at(where), "hosp_" .. role .. "_" .. seqN, ROLE_LOOK[role] or { age = "adult" }, "hospital")
	if not o then
		return nil
	end
	o.hrole = role
	o.k = k or 1
	o.node = where
	o.tasks = {}
	o.speedW = ROLE_SPEED[role] or 5
	o.model:SetAttribute("HospitalRole", role)
	o.home = o.model.Parent
	table.insert(actors, o)
	return o
end

local function removeActor(o: any)
	o.gone = true
	local i = table.find(actors, o)
	if i then
		table.remove(actors, i)
	end
	P.removeActor(o)
end

-- tasks: { go = spot } | { act = name, dur = s, say = lines?, face = spot? } | { wait = fn } | { call = fn }
local function push(o: any, list: { any })
	for _, t in list do
		table.insert(o.tasks, t)
	end
end

local function startGo(o: any, to: string): boolean
	if o.node == to then
		return false
	end
	local r = routeOf(o.node, to)
	o.goal = to
	if not r then
		o.node = to -- (unreachable: they give it up)
		return false
	end
	o.route = r
	o.routeI = 0
	return true
end

-- walk the route leg by leg; between floors they ride the elevator out of sight a few seconds
local function stepRoute(o: any): boolean
	local r = o.route
	if not r then
		return true
	end
	if not P.arrived(o) then
		return false
	end
	if o.inLift then
		if now() < o.inLift then
			return false
		end
		o.inLift = nil
		o.model.Parent = o.home
	end
	local i = o.routeI + 1
	if i > #r then
		o.node = o.goal or o.node
		o.route = nil
		return true
	end
	o.routeI = i
	local leg = r[i]
	if leg.lift and not o.liftDone then
		o.liftDone = true
		o.routeI = i - 1
		o.inLift = now() + 3 + rnd() * 2
		P.standAt(o, leg.pts[1])
		o.model.Parent = nil
		return false
	end
	o.liftDone = nil
	local pts = table.clone(leg.pts)
	pts[1] = o.pos
	if #pts < 2 or flat(pts[1], pts[#pts]) < 0.3 then
		return false
	end
	P.faceTo(o, pts[2])
	P.moveAlong(o, pts, o.speedW)
	return false
end

local function nextTask(o: any)
	local t = table.remove(o.tasks, 1)
	o.task = t
	if not t then
		return
	end
	if t.go then
		startGo(o, t.go)
	elseif t.act then
		o.taskUntil = now() + (t.dur or 4)
		if t.face then
			P.faceTo(o, at(t.face))
		end
		P.setAct(o, t.act)
		if t.say and rnd() < (t.chance or 1) then
			P.say(o, pick(t.say), 3)
		end
	elseif t.call then
		pcall(t.call, o)
		o.task = nil
	end
end

local function others(role: string, near: string?): { any }
	local out = {}
	for _, o in actors do
		if o.hrole == role and not o.gone and (not near or o.node == near) then
			table.insert(out, o)
		end
	end
	return out
end

-- a short exchange: o says a line, another actor at the same spot answers
local function exchange(o: any, list: { string }, answerRole: string?, answers: { string }?)
	P.say(o, pick(list), 3)
	if answerRole and answers then
		local other = others(answerRole, o.node)[1]
		if other then
			task.delay(1.6, function()
				if not other.gone then
					P.faceTo(other, o.pos)
					P.say(other, pick(answers), 3)
				end
			end)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- routines
-------------------------------------------------------------------------------------------------
local WAITS = { "wait1", "wait2", "wait3" }

local function routine(o: any)
	local r = o.hrole
	if r == "reception" then
		if rnd() < 0.25 then
			push(o, { { go = "pharm" }, { act = "talk", dur = 4, say = LINES.staff_chat, chance = 0.5 }, { go = "desk" } })
		end
		push(o, { { act = "typing", dur = 12 + rnd() * 14, face = "desk_front" } })
	elseif r == "doctor" then
		local rounds = if o.k == 1 then { "cons", "treat", "w201_bed", "station", "cons" } else { "treat", "w202_bed", "check", "station", "treat" }
		for _, spot in rounds do
			push(o, { { go = spot }, { act = if spot == "station" then "talk" else "clipboard", dur = 7 + rnd() * 8, say = if spot == "station" then LINES.staff_chat else LINES.ward, chance = 0.55 } })
		end
	elseif r == "nurse" then
		if o.k == 1 then
			push(o, { { go = "station" }, { act = "typing", dur = 10 + rnd() * 8 }, { go = "w201_bed" }, { act = "clipboard", dur = 6, say = LINES.ward, chance = 0.7 }, { go = "w202_bed" }, { act = "clipboard", dur = 6, say = LINES.ward, chance = 0.7 }, { go = "check" }, { act = "wipe", dur = 5 } })
		elseif o.k == 2 then
			push(o, { { go = "treat" }, { act = "work", dur = 8 + rnd() * 6 }, { go = "lobby" }, { act = "talk", dur = 4, say = LINES.nurse_call, chance = 0.9, face = "wait2" }, { go = "pharm" }, { act = "work", dur = 6 } })
		else
			push(o, { { go = "lobby" }, { act = "look", dur = 4 }, { go = "station" }, { act = "talk", dur = 6, say = LINES.staff_chat, chance = 0.5 }, { go = "lounge" }, { act = "clipboard", dur = 5 } })
		end
	elseif r == "patient" then
		local w = WAITS[1 + math.floor(rnd() * #WAITS)]
		push(o, {
			{ go = "door" }, { go = "desk_front" },
			{ call = function(a)
				exchange(a, LINES.patient_desk, "reception", LINES.desk_greet)
			end },
			{ act = "talk", dur = 4.5, face = "desk" },
			{ call = function(a)
				local rc = others("reception", "desk")[1]
				if rc then
					P.say(rc, pick(LINES.desk_wait), 3)
				end
			end },
			{ go = w }, { act = "sit", dur = 14 + rnd() * 12 },
			{ go = "cons" }, { act = "listen", dur = 9, face = "cons", say = LINES.patient_thanks, chance = 0.4 },
			{ go = "pharm" }, { call = function(a)
				local n = others("nurse")[1]
				P.say(a, pick(LINES.patient_thanks), 3)
				if n and n.node == "pharm" then
					P.say(n, pick(LINES.pharm), 3)
				end
			end }, { act = "idle", dur = 3 },
			{ go = "door" }, { go = "fore" }, { call = function(a)
				a.done = true
			end },
		})
		-- a guardian comes along now and then
		local g = o.guardian
		if g and not g.gone then
			g.follow = o
		end
	elseif r == "inpatient" then
		if rnd() < 0.3 then
			push(o, { { go = "lounge" }, { act = "sit", dur = 10 + rnd() * 8 }, { go = "w201_bed" } })
		end
		push(o, { { act = "sit", dur = 18 + rnd() * 16, say = LINES.inpatient, chance = 0.25 } })
	elseif r == "guardian" then
		if o.follow and not o.follow.gone then
			return -- following its patient (think)
		end
		push(o, { { go = "w201" }, { act = "talk", dur = 10 + rnd() * 8, face = "w201_bed", say = LINES.guardian, chance = 0.6 }, { go = "lounge" }, { act = "phone", dur = 8 + rnd() * 6 } })
	elseif r == "er" then
		push(o, { { go = "treat_bed" }, { act = "sit", dur = 50 }, { call = function(a)
			a.done = true
		end } })
	end
end

local function think(o: any)
	if o.gone or now() < (o.nextThink or 0) then
		return
	end
	o.nextThink = now() + 0.5
	o.pos = P.legPos(o, now())
	if o.done then
		removeActor(o)
		return
	end
	-- a guardian walks a step behind the patient they came with
	if o.hrole == "guardian" and o.follow then
		local f = o.follow
		if f.gone or f.done then
			o.follow = nil
			o.leaving = true
			o.tasks = { { go = "door" }, { go = "fore" }, { call = function(a)
				a.done = true
			end } }
			o.task, o.route = nil, nil
		elseif f.node and f.node ~= o.followNode and P.arrived(o) and not o.route then
			o.followNode = f.node
			o.tasks = { { go = f.node }, { act = if f.task and f.task.act == "sit" then "sit" else "idle", dur = 2 } }
			o.task = nil
		elseif f.task and f.task.act == "sit" and o.node == f.node and now() - (o.hLine or 0) > 18 then
			o.hLine = now()
			if rnd() < 0.5 then
				P.say(o, pick(LINES.guardian), 3)
			end
		end
	end
	local t = o.task
	if t and t.go then
		if stepRoute(o) then
			o.task = nil
		end
		return
	end
	if t and t.act then
		if now() < (o.taskUntil or 0) then
			return
		end
		o.task = nil
	end
	if #o.tasks == 0 then
		routine(o)
	end
	nextTask(o)
end

-------------------------------------------------------------------------------------------------
-- 응급실
-------------------------------------------------------------------------------------------------
function Hospital.emergency(spec: any?)
	table.insert(queue, { t = now(), spec = spec })
end

local function serveEmergency()
	if #queue == 0 or not active then
		return
	end
	table.remove(queue, 1)
	local nurse = nil
	for _, o in others("nurse") do
		if o.k == 2 or not nurse then
			nurse = o
		end
	end
	local doctor = others("doctor")[1]
	local er = spawnActor("er", "door")
	if er then
		er.speedW = 3.2
		er.tasks = {}
		push(er, { { act = "idle", dur = 3 } })
	end
	for _, o in { nurse, doctor } do
		if o and not o.gone then
			o.tasks = {}
			o.task, o.route = nil, nil
			o.speedW = 9.5
			o.pos = P.legPos(o, now())
			push(o, {
				{ go = "door" },
				{ act = "talk", dur = 3, say = if o == doctor then LINES.er_doctor else LINES.er_call, chance = 1 },
				{ go = "treat" },
				{ act = "work", dur = 14 },
				{ call = function(a)
					a.speedW = ROLE_SPEED[a.hrole] or 5
				end },
			})
		end
	end
end

-------------------------------------------------------------------------------------------------
-- life cycle
-------------------------------------------------------------------------------------------------
local function playerNear(): boolean
	for _, p in Players:GetPlayers() do
		local pp = Law.posOf(p)
		if pp and flat(pp, Hospital.CENTER) < Hospital.ACTIVE_R then
			return true
		end
	end
	return false
end

local function start()
	active = true
	if not grids[1] then
		buildWorld()
	end
	spawnActor("reception", "desk")
	spawnActor("doctor", "cons", 1)
	spawnActor("doctor", "treat", 2)
	spawnActor("nurse", "station", 1)
	spawnActor("nurse", "treat", 2)
	spawnActor("nurse", "lobby", 3)
	local ip = spawnActor("inpatient", "w201_bed")
	local g1 = spawnActor("guardian", "w201")
	local _ = ip and g1
	for i = 1, 3 do
		local pt = spawnActor("patient", if i == 1 then "wait1" else "fore")
		if pt and i == 2 then
			local g = spawnActor("guardian", "fore")
			if g then
				pt.guardian = g
				g.follow = pt
			end
		end
	end
end

local function stop()
	active = false
	for i = #actors, 1, -1 do
		removeActor(actors[i])
	end
end

local acc = 0
local respawnAt = 0
function Hospital.tick(dt: number)
	acc += dt
	if acc < 0.25 then
		return
	end
	acc = 0
	local near = playerNear()
	if near then
		lastNear = now()
		if not active then
			start()
		end
	elseif active and now() - lastNear > Hospital.IDLE_OFF then
		stop()
	end
	if not active then
		return
	end
	for i = #actors, 1, -1 do
		local o = actors[i]
		local ok, err = pcall(think, o)
		if not ok then
			warn("[GwangalliLaw.Hospital] " .. tostring(err))
			removeActor(o)
		end
	end
	-- outpatients keep coming (3 at a time)
	if #others("patient") < 3 and now() >= respawnAt then
		respawnAt = now() + 12 + rnd() * 18
		local pt = spawnActor("patient", "fore")
		if pt and rnd() < 0.4 and #others("guardian") < 3 then
			local g = spawnActor("guardian", "fore")
			if g then
				pt.guardian = g
				g.follow = pt
			end
		end
	end
	serveEmergency()
end

-- test: the walkable grid as text rows ("." free, "#" blocked, letters = spots)
function Hospital.dump(fl: number, z0: number?, z1: number?): string
	if not grids[fl] then
		buildWorld()
	end
	local marks = {}
	for name, sc in spotCell do
		if sc.floor == fl then
			marks[idx(sc.ix, sc.iz)] = string.upper(string.sub(name, 1, 1))
		end
	end
	local rows = {}
	for iz = z0 or 0, math.min(G.nz - 1, z1 or G.nz - 1) do
		local line = {}
		for ix = 0, G.nx - 1 do
			local i = idx(ix, iz)
			table.insert(line, marks[i] or (if grids[fl].free[i] then "." else "#"))
		end
		table.insert(rows, string.format("%3d ", G.z0 + iz * G.cell) .. table.concat(line))
	end
	local ph = P.rayHit(Vector3.new(-515, (if fl == 2 then F2 else F1) + 2.4, 300), Vector3.new(-515, (if fl == 2 then F2 else F1) - 3, 300))
	local probe = if ph then ph.Position.Y else -999
	return string.format("floor %d y=%.2f probe=%.2f\n", fl, grids[fl].y, probe) .. table.concat(rows, "\n")
end

function Hospital.status(): any
	local roles = {}
	for _, o in actors do
		roles[o.hrole] = (roles[o.hrole] or 0) + 1
	end
	local where = {}
	for _, o in actors do
		table.insert(where, string.format("%s@%s:%s%s(%.0f,%.0f,%.0f)", o.hrole, tostring(o.node), o.task and (o.task.go or o.task.act) or "-", if o.route then "~" else "", o.pos.X, o.pos.Y, o.pos.Z))
	end
	return { active = active, roles = roles, broken = broken, where = where }
end

function Hospital.init(law: any, context: any)
	Law = law
	ctx = context
	P = Law.children.Police
	assert(P, "Law/Hospital needs Law/Police")
	ctx.hospital = Hospital
end

return Hospital
