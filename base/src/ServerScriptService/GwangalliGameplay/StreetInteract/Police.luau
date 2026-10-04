-- Interact/Police (server): 광안리 치안. Cases, not omniscience:
--   * a CASE starts when a cop SEES an incident (Mind.perceive -> onPerceive) or somebody REPORTS it
--     (a citizen's 112 call, the player telling a cop): the police know only the reported position and
--     what the caller saw (suspectPos). Never the player's live position.
--   * stages: enroute (walk / run to the reported spot) -> assess (look around, ask a witness who
--     points the way) -> warn ("거기 멈추세요") -> comply (minor: warning / 범칙금, NPCs are sent off;
--     serious: arrest) | refuse / run -> chase (last seen position) -> search (the last seen spot +
--     3 points around it) -> lost | arrest -> done (상황 종료, back to the beat).
--   * suspects can be players or NPCs (a thug who beat somebody is cuffed and taken away).
--   * response: the beat officers of the block first (Cast: 순경 오해변 / 경장 한밤); serious cases or
--     no free officer -> a patrol car (a clone of the map 순찰차, light bar + siren) DRIVES in along the
--     lane graph (GwangalliGameplay.TaxiDispatch, the taxi's pure routing) and pulls over; the officers
--     get out, and get back in when the case is closed; the car drives off.
--   * how hard: severity / wanted stars / a cop who was hit -> run vs walk, baton vs cuffs, backup.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Police = {}

local I: any
local C: any
local Mind: any
local World: any
local Actors: any
local Talk: any
local Routine: any
local Places: any
local D: any = nil -- TaxiDispatch
local graph: any = nil

local rnd = Random.new()
local function range(t: { number }): number
	return t[1] + (t[2] - t[1]) * rnd:NextNumber()
end

local cases: { any } = {}
Police.cases = cases
local respSeq = 0
local unitSeq = 20
local carsFolder: Folder? = nil
local carTemplate: Model? = nil
local carOffsetY = 2.6

---------------------------------------------------------------------------------------------------
-- officers
---------------------------------------------------------------------------------------------------
local function cops(): { any }
	local out = {}
	for _, n in Mind.list do
		if n.arch == "police" and n.present and n.a and not n.a.gone then
			table.insert(out, n)
		end
	end
	return out
end
Police.cops = cops

function Police.copNear(pos: Vector3, r: number): Vector3?
	for _, n in cops() do
		if not Actors.isDown(n.a) then
			local p = Actors.pos(n.a)
			if (p - pos).Magnitude < r then
				return p
			end
		end
	end
	return nil
end

-- does any officer see this spot right now?
function Police.copSees(pos: Vector3, _player: Player?): boolean
	for _, n in cops() do
		if World.canSee(n, pos, C.COP_SIGHT) then
			return true
		end
	end
	return false
end

-- (seen by an officer now, an officer close enough to keep the chase on)
function Police.sight(_player: Player, pos: Vector3): (boolean, boolean)
	local seen, near = false, false
	for _, n in cops() do
		if not Actors.isDown(n.a) then
			local p = Actors.pos(n.a)
			if (p - pos).Magnitude < C.EVADE_NEAR then
				near = true
			end
			if not seen and World.canSee(n, pos, C.COP_SIGHT) then
				seen = true
			end
		end
	end
	return seen, near
end

local function say(n: any, sit: string, vars: any?)
	return Mind.say(n, sit, vars)
end

---------------------------------------------------------------------------------------------------
-- the patrol car (scenery clone moved like the taxi: anchored root, welded body, lane paths)
---------------------------------------------------------------------------------------------------
local function findTemplate(): Model?
	if carTemplate then
		return carTemplate
	end
	local map = workspace:FindFirstChild("Gwangalli")
	local roads = map and map:FindFirstChild("roads")
	local parked = roads and roads:FindFirstChild("ParkedVehicles")
	local src = parked and parked:FindFirstChild("Car_Police")
	if not src then
		return nil
	end
	local ok, clone = pcall(function()
		return src:Clone()
	end)
	if not ok or not clone then
		return nil
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("ProximityPrompt") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") or d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") then
			d:Destroy()
		elseif d:IsA("Seat") or d:IsA("VehicleSeat") then
			pcall(function()
				(d :: any).Disabled = true
			end)
		end
	end
	local okP, pv = pcall(function()
		return src:GetPivot()
	end)
	if okP then
		local gy = Actors.groundAt(pv.Position, pv.Position.Y - 2.6)
		carOffsetY = math.clamp(pv.Position.Y - gy, 0.5, 5)
	end
	-- one anchored root, everything else welded to it (moves as one assembly)
	local root = Instance.new("Part")
	root.Name = "CarRoot"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = clone:GetPivot()
	root.Parent = clone
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
		end
		for _, tag in CollectionService:GetTags(d) do
			CollectionService:RemoveTag(d, tag)
		end
	end
	for _, tag in CollectionService:GetTags(clone) do
		CollectionService:RemoveTag(clone, tag)
	end
	clone.PrimaryPart = root
	clone:SetAttribute("VehicleKind", nil)
	carTemplate = clone
	return clone
end

local function lightBar(car: Model)
	local okB, cf, size = pcall(function()
		return car:GetBoundingBox()
	end)
	local at = if okB then cf * CFrame.new(0, size.Y * 0.5 + 0.18, 0) else car:GetPivot() * CFrame.new(0, 2.5, 0)
	local root = car.PrimaryPart
	for i, spec in { { "GiLightR", { 255, 40, 50 }, -0.75 }, { "GiLightB", { 40, 90, 255 }, 0.75 } } do
		local p = Instance.new("Part")
		p.Name = spec[1]
		p.Size = Vector3.new(1.3, 0.35, 0.6)
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(spec[2][1], spec[2][2], spec[2][3])
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Anchored = root == nil
		p.CFrame = at * CFrame.new(spec[3], 0, 0)
		local l = Instance.new("PointLight")
		l.Color = p.Color
		l.Range = 16
		l.Brightness = 3
		l.Parent = p
		if root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
		end
		p.Parent = car
		local _ = i
	end
end

local function heights(q: Vector3): number?
	return Actors.groundAt(Vector3.new(q.X, 8, q.Z), 6) + carOffsetY
end

-- a car that drives in along the lanes and pulls over at the kerb nearest `pos`
local function carTo(pos: Vector3): any?
	local tpl = findTemplate()
	if not tpl or not D or not graph then
		return nil
	end
	local okL, loc = pcall(D.nearestLocation, graph, pos, { maxDist = 90, side = pos, kerbOnly = true })
	if not okL or not loc then
		okL, loc = pcall(D.nearestLocation, graph, pos, { maxDist = 140 })
	end
	if not okL or not loc then
		return nil
	end
	local okA, pts = pcall(D.approach, graph, loc, 260, 140)
	if not okA or not pts or #pts < 2 then
		return nil
	end
	local okP, path = pcall(D.buildPath, pts, { cruise = 44, v0 = 30, v1 = 0, pullOver = { offset = 2.2, len = 26 }, heights = heights })
	if not okP or not path then
		return nil
	end
	unitSeq += 1
	local car = tpl:Clone()
	car.Name = "GI_PatrolCar_광안" .. unitSeq
	car:SetAttribute("GiCar", true)
	car:SetAttribute("GiSiren", true)
	car:SetAttribute("GiUnit", "광안" .. unitSeq)
	local p0, d0 = D.sample(path.pts, path.times, 0)
	car:PivotTo(D.cframe(p0, d0))
	lightBar(car)
	local host = car.PrimaryPart
	if host then
		local snd = Instance.new("Sound")
		snd.Name = "GwSiren"
		snd.SoundId = C.SOUND_IDS.siren or ""
		snd.Looped = true
		snd.Volume = 0.55
		snd.RollOffMaxDistance = 260
		snd.RollOffMinDistance = 18
		snd.Parent = host
		pcall(function()
			snd:Play()
		end)
	end
	car.Parent = carsFolder
	local rec = { model = car, path = path, t0 = os.clock(), arrived = false, unit = "광안" .. unitSeq, leaving = false }
	task.spawn(function()
		while car.Parent and not rec.leaving do
			local t = os.clock() - rec.t0
			local p, dir = D.sample(path.pts, path.times, t)
			car:PivotTo(D.cframe(p, dir))
			if t >= path.total then
				rec.arrived = true
				rec.cf = car:GetPivot()
				break
			end
			task.wait(1 / 12)
		end
	end)
	return rec
end

local function carLeave(rec: any)
	if not rec or not rec.model or not rec.model.Parent then
		return
	end
	rec.leaving = true
	local car = rec.model
	car:SetAttribute("GiSiren", false)
	local s = car:FindFirstChild("GwSiren", true)
	if s and s:IsA("Sound") then
		pcall(function()
			s:Stop()
		end)
	end
	local okL, loc = pcall(D.nearestLocation, graph, car:GetPivot().Position, { maxDist = 60 })
	if not okL or not loc then
		car:Destroy()
		return
	end
	local okF, pts = pcall(D.forward, graph, loc, 220)
	local okP, path = pcall(D.buildPath, if okF then pts else {}, { cruise = 36, v0 = 0, v1 = 30, pullOut = { offset = 2.2, len = 22 }, heights = heights })
	if not okP or not path then
		car:Destroy()
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while car.Parent do
			local t = os.clock() - t0
			local p, dir = D.sample(path.pts, path.times, t)
			car:PivotTo(D.cframe(p, dir))
			if t >= path.total then
				break
			end
			task.wait(1 / 12)
		end
		car:Destroy()
	end)
end

---------------------------------------------------------------------------------------------------
-- responders (officers who come with a car; temporary Mind records)
---------------------------------------------------------------------------------------------------
local function newResponder(at: Vector3, yaw: number): any?
	respSeq += 1
	local name = C.POLICE_NAMES[((respSeq - 1) % #C.POLICE_NAMES) + 1]
	local look = table.clone(C.POLICE_LOOK)
	look.skin = 1 + (respSeq % 4)
	local def = {
		id = "cop_r" .. respSeq,
		name = name,
		role = "광안지구대",
		arch = "police",
		style = "cop",
		gait = "alert",
		look = look,
		police = true,
		traits = { kindness = 0.5, aggression = 0.4, patience = 0.5, courage = 0.9, humor = 0.3, sociability = 0.4, suspicion = 0.7, pride = 0.5, greed = 0, civic = 1, curiosity = 0.6, temper = 0.35 },
		schedule = { { 0, 24, "away" } },
	}
	local n = Mind.addTemp(def)
	local a = Actors.spawn({ id = def.id, kind = "police", name = name, role = def.role, color = { 84, 140, 255 }, look = look, feet = at, yaw = yaw, hp = n.max, typeId = "police", police = true, baton = true })
	if not a then
		Mind.removeTemp(n)
		return nil
	end
	n.a = a
	n.present = true
	Actors.setAttr(a, "GiArch", "police")
	Actors.setAttr(a, "GiStyle", "cop")
	Actors.setAttr(a, "GiGait", "alert")
	Mind.sync(n)
	return n
end

---------------------------------------------------------------------------------------------------
-- cases
---------------------------------------------------------------------------------------------------
local function suspectPlayer(cs: any): Player?
	return World.playerOf(cs.suspect)
end

local function suspectN(cs: any): any?
	return Mind.byKey(cs.suspect)
end

local function caseFor(inc: any): any?
	for _, cs in cases do
		if not cs.done and (cs.inc == inc or (inc and cs.suspect and cs.suspect == inc.aggressor)) then
			return cs
		end
	end
	return nil
end

local function assign(cs: any, n: any)
	if n.case == cs then
		return
	end
	if n.case and not n.case.done then
		return
	end
	n.case = cs
	n.caseStage = cs.stage
	table.insert(cs.cops, n)
	Mind.setMode(n, "police")
	n.retarget = 0
	n.nextHit = 0
	n.hits = 0
	n.spotted = false
	n.warned = false
	n.searchPts = nil
	n.stageT = os.clock()
end

local function freeCops(pos: Vector3, maxD: number): { any }
	local out = {}
	for _, n in cops() do
		if not n.temp and (not n.case or n.case.done) and n.mode ~= "down" then
			local d = (Actors.pos(n.a) - pos).Magnitude
			if d < maxD then
				table.insert(out, { n = n, d = d })
			end
		end
	end
	table.sort(out, function(a, b)
		return a.d < b.d
	end)
	local r = {}
	for _, e in out do
		table.insert(r, e.n)
	end
	return r
end

-- officers for a case: the beat officers close by, a car with responders for serious cases
local function staff(cs: any)
	local want = 1
	local pl = suspectPlayer(cs)
	if pl then
		local st = I.state(pl)
		want = C.COPS[math.max(1, st.stars)] or 1
	elseif cs.sev >= 3 then
		want = 2
	end
	local have = 0
	for _, n in cs.cops do
		if n.present and n.case == cs then
			have += 1
		end
	end
	for _, n in freeCops(cs.pos, 450) do
		if have >= want then
			break
		end
		assign(cs, n)
		have += 1
	end
	if have < want and not cs.carPending and (os.clock() - (cs.carT or -1e9)) > 20 then
		cs.carPending = true
		cs.carT = os.clock()
		local nCops = math.min(2, want - have)
		local car = carTo(cs.lastPos or cs.pos)
		if pl then
			I.fire(pl, { kind = "radio", text = string.format(C.RADIO.dispatch, unitSeq) })
		end
		if not car then
			-- no road nearby: they come on foot from out of sight
			cs.carPending = false
			for k = 1, nCops do
				local p = Routine.safePoint(nil, (cs.lastPos or cs.pos) + Vector3.new(rnd:NextNumber(-1, 1), 0, rnd:NextNumber(-1, 1)).Unit * 70) or cs.pos
				local n = newResponder(p, 0)
				if n then
					assign(cs, n)
				end
				local _ = k
			end
			return
		end
		table.insert(cs.cars, car)
		task.spawn(function()
			local t0 = os.clock()
			while not car.arrived and car.model and car.model.Parent and os.clock() - t0 < 25 do
				task.wait(0.25)
			end
			cs.carPending = false
			if cs.done or not car.model or not car.model.Parent then
				carLeave(car)
				return
			end
			local cf = car.cf or car.model:GetPivot()
			for k = 1, nCops do
				local side = if k % 2 == 1 then 3.6 else -3.6
				local door = (cf * CFrame.new(side, 0, -1)).Position
				local feet = Vector3.new(door.X, Actors.groundAt(door + Vector3.new(0, 2, 0), door.Y - carOffsetY), door.Z)
				local d = (cs.lastPos or cs.pos) - feet
				local n = newResponder(feet, Actors.yawOf(d.X, d.Z))
				if n then
					n.car = car
					assign(cs, n)
					if k == 1 then
						say(n, if cs.sev >= 3 then "cop_chase" else "cop_assess")
					end
				end
			end
		end)
	end
end

local function newCase(inc: any, info: any?): any
	local cs = caseFor(inc)
	if cs then
		if info and info.suspectPos then
			cs.lastPos = info.suspectPos
			cs.lastT = os.clock()
		end
		cs.sev = math.max(cs.sev, inc.sev)
		return cs
	end
	cs = {
		inc = inc,
		pos = (info and info.pos) or inc.pos,
		lastPos = (info and info.suspectPos) or (info and info.pos) or inc.pos,
		lastT = os.clock(),
		suspect = inc.aggressor,
		victim = inc.victim,
		sev = inc.sev,
		stage = "enroute",
		cops = {},
		cars = {},
		t0 = os.clock(),
		done = false,
		reportedBy = info and info.name,
	}
	table.insert(cases, cs)
	inc.status = "police"
	inc.case = cs
	return cs
end

-- somebody reported an incident (a citizen on the phone, a player telling a cop)
function Police.report(inc: any, info: any)
	inc.report = inc.report or { by = info.by, t = os.clock(), pos = info.pos }
	local cs = newCase(inc, info)
	local pl = suspectPlayer(cs)
	if pl then
		I.policeKnow(pl, inc, false)
		I.fire(pl, { kind = "radio", text = string.format(C.RADIO.report, inc.label or "신고") })
	end
	staff(cs)
end

-- an officer saw / heard something
function Police.onPerceive(n: any, inc: any, how: string)
	if inc.aggressor and string.sub(inc.aggressor, 1, 2) == "n:" and Mind.byKey(inc.aggressor) and Mind.byKey(inc.aggressor).arch == "police" then
		return
	end
	local busy = n.case and not n.case.done
	if busy then
		local cs = n.case
		if cs.suspect == inc.aggressor and how == "seen" then
			cs.lastPos = World.posOf(inc.aggressor, inc.pos)
			cs.lastT = os.clock()
		end
		return
	end
	if inc.sev < 1 or inc.kind == "disturbance" and inc.sev <= 1 and how ~= "seen" then
		if how == "heard" then
			Actors.face(n.a, inc.pos)
		end
		return
	end
	local cs = newCase(inc, { pos = inc.pos, suspectPos = if how == "seen" then World.posOf(inc.aggressor, inc.pos) else nil, name = n.name })
	local pl = suspectPlayer(cs)
	if pl and how == "seen" then
		I.policeKnow(pl, inc, true)
	end
	assign(cs, n)
	if how == "seen" then
		cs.stage = if cs.sev >= 3 then "chase" else "warn"
		say(n, if cs.sev >= 3 then "cop_chase" else "cop_warn")
	end
	staff(cs)
end

-- a player's wanted level went up (Interact): make sure the police are on it
function Police.onWanted(player: Player, stars: number, prev: number)
	local key = "p:" .. player.UserId
	local cs = nil
	for _, c in cases do
		if not c.done and c.suspect == key then
			cs = c
		end
	end
	if not cs then
		local pos = I.state(player).lastSeenPos or I.feetOf(player)
		if not pos then
			return
		end
		local inc = World.incident("assault", pos, { aggressor = key })
		cs = newCase(inc, { pos = pos })
	end
	cs.sev = math.max(cs.sev, math.min(4, stars))
	if stars > prev and #cs.cops > 0 then
		I.fire(player, { kind = "radio", text = C.RADIO.backup })
	end
	staff(cs)
end

function Police.onCopHit(n: any, player: Player)
	n.angry = true
	local key = "p:" .. player.UserId
	local cs = n.case
	if not cs or cs.done or cs.suspect ~= key then
		local inc = World.incident("cop_assault", Actors.pos(n.a), { aggressor = key, victim = "n:" .. n.id })
		cs = newCase(inc, { pos = Actors.pos(n.a), suspectPos = I.feetOf(player) })
		n.case = nil
		assign(cs, n)
	end
	cs.stage = "chase"
	cs.lastPos = I.feetOf(player) or cs.lastPos
	cs.lastT = os.clock()
	staff(cs)
end

-- a player asked an officer for help against somebody threatening them
function Police.interveneFor(n: any, threat: any, player: Player)
	local inc = World.incident("threat", Actors.pos(threat.a), { aggressor = "n:" .. threat.id, victim = "p:" .. player.UserId })
	local cs = newCase(inc, { pos = inc.pos, suspectPos = Actors.pos(threat.a), name = player.DisplayName })
	n.case = nil
	assign(cs, n)
	cs.stage = "warn"
end

local function closeCase(cs: any, reason: string)
	if cs.done then
		return
	end
	cs.done = true
	cs.reason = reason
	if cs.inc and cs.inc.status ~= "resolved" then
		World.resolve(cs.inc, reason)
	end
	for _, n in cs.cops do
		if n.case == cs then
			n.case = nil
			n.angry = false
			if n.present and n.a and not n.a.gone then
				if reason == "lost" then
					say(n, "cop_lost")
				elseif reason ~= "arrested" then
					say(n, "cop_resolved")
				end
				Actors.pose(n.a, "")
				if n.temp then
					n.mode = "leaving"
					Mind.sync(n)
				else
					Mind.setMode(n, "routine")
					Routine.resume(n)
				end
			end
		end
	end
	-- the temp officers walk back to the car (or out of sight) and the car drives off
	task.spawn(function()
		task.wait(1.5)
		for _, n in cs.cops do
			if n.temp and n.present and n.a then
				local target = if n.car and n.car.cf then (n.car.cf * CFrame.new(3.6, 0, -1)).Position else Routine.safePoint(nil, Actors.pos(n.a) + Vector3.new(60, 0, 0))
				if target then
					Actors.walkTo(n.a, Vector3.new(target.X, Actors.groundAt(target + Vector3.new(0, 2, 0), target.Y), target.Z), 7)
				end
			end
		end
		local t0 = os.clock()
		while os.clock() - t0 < 25 do
			task.wait(1)
			local all = true
			for _, n in cs.cops do
				if n.temp and n.present and n.a and n.a.path and Actors.moving(n.a) then
					all = false
				end
			end
			if all then
				break
			end
		end
		for _, n in cs.cops do
			if n.temp then
				Mind.removeTemp(n)
			end
		end
		for _, car in cs.cars do
			carLeave(car)
		end
	end)
end
Police.closeCase = closeCase

-- the player's case ends when the stars are gone (evaded / arrested / hospital / warned)
function Police.standDown(player: Player, reason: string)
	local key = "p:" .. player.UserId
	for _, cs in cases do
		if not cs.done and cs.suspect == key then
			closeCase(cs, if reason == "evaded" then "lost" elseif reason == "arrested" then "arrested" else reason)
		end
	end
end

function Police.onArrest(player: Player, officer: any?)
	local f = I.feetOf(player)
	if officer and officer.a and not officer.a.gone then
		Actors.stop(officer.a)
		if f then
			Actors.face(officer.a, f)
		end
		Actors.pose(officer.a, "fight")
		say(officer, "cop_arrest")
	end
	if f then
		I.fireAll({ kind = "sound", name = "cuff", pos = C.packV(f) })
	end
end

function Police.onSurrender(player: Player, _s: any)
	for _, cs in cases do
		if not cs.done and cs.suspect == "p:" .. player.UserId then
			for _, n in cs.cops do
				if n.present and n.a and not Actors.isDown(n.a) then
					say(n, "cop_surrender")
					cs.stage = "arrest"
					break
				end
			end
		end
	end
end

function Police.onAirPunch(_player: Player, _s: any) end

function Police.onLeave(player: Player)
	Police.standDown(player, "left")
end

---------------------------------------------------------------------------------------------------
-- the officer's step (4 Hz while on a case)
---------------------------------------------------------------------------------------------------
local function moveTo(n: any, target: Vector3, run: boolean, stop: number, straight: boolean?)
	local me = Actors.pos(n.a)
	local d = Vector3.new(target.X - me.X, 0, target.Z - me.Z)
	if d.Magnitude <= stop then
		Actors.stop(n.a)
		return true
	end
	local now = os.clock()
	if now >= (n.retarget or 0) then
		n.retarget = now + (if run then 0.5 else 1.0)
		local to = target - d.Unit * math.max(0, stop - 0.4)
		local speed = if run then (C.COP_SPEED[math.clamp((n.case and n.case.sev) or 1, 1, 5)] or 17) else 7
		Actors.walkTo(n.a, Vector3.new(to.X, Actors.groundAt(to + Vector3.new(0, 2, 0), target.Y), to.Z), speed, straight)
	end
	n.policeRun = run
	return false
end

local function arrestNpc(n: any, sus: any, cs: any)
	say(n, "cop_npc_arrest")
	Actors.stop(n.a)
	Actors.face(n.a, Actors.pos(sus.a))
	for key in sus.conf do
		sus.conf[key] = nil
	end
	Routine.pause(sus)
	sus.mode = "custody"
	Actors.stop(sus.a)
	Actors.pose(sus.a, "cuffed")
	Mind.sync(sus)
	I.fireAll({ kind = "sound", name = "cuff", pos = C.packV(Actors.pos(sus.a)) })
	closeCase(cs, "arrested")
	-- led away: the suspect follows the officer out of the block, both come back another time
	task.spawn(function()
		local exit = Routine.safePoint(nil, Actors.pos(n.a) + Vector3.new(0, 0, 70)) or Places.spot("portalN")
		if n.temp and n.car and n.car.cf then
			exit = (n.car.cf * CFrame.new(-3.6, 0, -1)).Position
		end
		Actors.walkTo(n.a, exit, 5.5)
		local t0 = os.clock()
		while os.clock() - t0 < 30 and n.a and sus.a and Actors.moving(n.a) do
			local p = Actors.pos(n.a)
			local s = Actors.pos(sus.a)
			local dd = Vector3.new(p.X - s.X, 0, p.Z - s.Z)
			if dd.Magnitude > 2.4 then
				Actors.walkTo(sus.a, p - dd.Unit * 1.8, 5.8, true)
			end
			task.wait(0.5)
		end
		Routine.despawnBody(sus)
		sus.mode = "routine"
		sus.returnAt = os.clock() + 300
		sus.mood.anger = 0.6
		sus.hp = sus.max
		if not n.temp and n.present then
			Mind.setMode(n, "routine")
			Routine.resume(n)
		end
	end)
end

local function ticket(n: any, pl: Player, cs: any)
	local fine = if cs.sev >= 2 then 50000 else 30000
	say(n, "cop_ticket")
	local label = cs.inc and cs.inc.label or "경범죄"
	task.delay(1.5, function()
		say(n, "cop_explain")
		local paid = I.payUpTo(pl, fine, "범칙금 · 광안지구대 (" .. label .. ")")
		I.fire(pl, { kind = "ticket", fine = fine, paid = paid, reason = label, by = n.name })
		I.notify(pl, "warn", "범칙금 " .. C.won(fine) .. " 🚓", string.format("사유: %s · %s 순경이 발부", label, n.name), { icon = "🧾" })
		I.clearWanted(pl, "ticket")
	end)
	closeCase(cs, "ticket")
end

function Police.copStep(n: any, now: number)
	local cs = n.case
	if n.mode == "leaving" then
		return
	end
	if not cs or cs.done then
		n.case = nil
		if n.temp then
			n.mode = "leaving"
			return
		end
		Mind.setMode(n, "routine")
		Routine.resume(n)
		return
	end
	if Actors.isDown(n.a) then
		return
	end
	local me = Actors.pos(n.a)
	local pl = suspectPlayer(cs)
	local sus = suspectN(cs)
	local spos = World.posOf(cs.suspect)
	if pl and I.state(pl).busy then
		Actors.stop(n.a)
		return
	end
	if sus and (not sus.present or sus.mode == "custody") then
		closeCase(cs, "gone")
		return
	end
	local sees = spos ~= nil and World.canSee(n, spos, C.COP_SIGHT)
	if sees then
		cs.lastPos = spos
		cs.lastT = now
		if not n.spotted then
			n.spotted = true
			Actors.emote(n.a, "point")
		end
	end
	local stars = if pl then I.state(pl).stars else 0
	local serious = cs.sev >= 3 or stars >= C.COP_HIT_FROM or n.angry
	Actors.setAttr(n.a, "GiLook", if sees then cs.suspect else "")
	if cs.stage == "enroute" then
		local arrived = moveTo(n, cs.pos, serious or cs.sev >= 2, 5)
		if sees then
			cs.stage = if serious then "chase" else "warn"
			say(n, if serious then "cop_chase" else "cop_warn")
		elseif arrived then
			cs.stage = "assess"
			n.stageT = now
			say(n, "cop_assess")
		end
	elseif cs.stage == "assess" then
		Actors.stop(n.a)
		Actors.emote(n.a, "look_around")
		-- a witness nearby points the way
		if not n.asked then
			for id, w in (cs.inc and cs.inc.witnesses or {}) do
				local wn = Mind.get(id)
				if wn and wn.present and wn.a and w.how == "seen" and (Actors.pos(wn.a) - me).Magnitude < 22 then
					n.asked = true
					Actors.face(n.a, Actors.pos(wn.a))
					Mind.say(wn, "witness_tell_cop", World.describe(cs.inc, w))
					if spos and World.canSee(wn, spos) then
						Actors.face(wn.a, spos)
						Actors.emote(wn.a, "point")
						cs.lastPos = spos
						cs.lastT = now
					end
					break
				end
			end
		end
		if sees then
			cs.stage = if serious then "chase" else "warn"
			say(n, if serious then "cop_chase" else "cop_warn")
		elseif now - (n.stageT or now) > 6 then
			cs.stage = "search"
			n.searchPts = nil
		end
	elseif cs.stage == "warn" then
		if not spos then
			cs.stage = "search"
			return
		end
		local d = (spos - me).Magnitude
		moveTo(n, spos, d > 16, 4.5, d < 24)
		if not n.warned and d < 12 then
			n.warned = true
			n.warnT = now
			say(n, if sus and (sus.arch == "thug" or sus.arch == "drunk") and cs.sev <= 2 then "cop_disperse" else "cop_warn")
			Actors.emote(n.a, "stop_hand")
			if sus then
				-- comply? courage / anger / how serious
				local T = sus.traits
				local comply = 0.85 - T.courage * 0.35 - sus.mood.anger * 0.3 - (if cs.sev >= 3 then 0.15 else 0) + rnd:NextNumber() * 0.25
				n.npcComply = comply > 0.45
			end
		end
		if n.warned then
			if sus then
				if n.npcComply then
					if cs.sev >= 3 then
						if d < 4 then
							arrestNpc(n, sus, cs)
						end
					else
						Mind.say(sus, "back_off_police")
						for key in sus.conf do
							Mind.calm(sus, key, 4, "police")
						end
						say(n, "cop_resolved")
						closeCase(cs, "warned")
						task.delay(1, function()
							if sus.present and sus.mode ~= "custody" then
								Routine.pause(sus)
								sus.mode = "routine"
								sus.returnAt = os.clock() + 120
								Routine.despawnBody(sus)
							end
						end)
					end
				else
					Mind.say(sus, "taunt_flee")
					Mind.flee(sus, me, 14, false)
					cs.stage = "chase"
				end
			elseif pl then
				local st = I.state(pl)
				if serious then
					cs.stage = "arrest"
				else
					-- stand still (or hands up) for the ticket; walking away = running
					local still = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") and (pl.Character.HumanoidRootPart :: BasePart).AssemblyLinearVelocity.Magnitude < 3
					if st.handsUp or (still and d < 9) then
						n.stillT = (n.stillT or 0) + 0.25
						if n.stillT > 2 then
							ticket(n, pl, cs)
						end
					else
						n.stillT = 0
						if d > 14 and now - (n.warnT or now) > 2 then
							I.crime(pl, "resist", me)
							I.policeKnow(pl, cs.inc, true)
							cs.stage = "chase"
							say(n, "cop_chase")
						end
					end
				end
			end
		end
	elseif cs.stage == "chase" or cs.stage == "arrest" then
		local target = if sees then spos else cs.lastPos
		if not target then
			cs.stage = "search"
			return
		end
		local d = (target - me).Magnitude
		if sees and spos and (spos - me).Magnitude <= 3.4 then
			Actors.stop(n.a)
			Actors.face(n.a, spos)
			if sus then
				arrestNpc(n, sus, cs)
				return
			end
			if pl then
				local st = I.state(pl)
				if st.handsUp or (stars < C.COP_HIT_FROM and not n.angry) or st.hp <= C.CUFF_HP then
					Actors.pose(n.a, "")
					I.arrest(pl, n)
					closeCase(cs, "arrested")
					return
				end
				Actors.pose(n.a, "fight")
				if now >= (n.nextHit or 0) then
					n.nextHit = now + range({ 1.0, 1.35 })
					n.hits = (n.hits or 0) + 1
					Actors.emote(n.a, "punch")
					local dx, dz = Mind.dirTo(me, spos)
					I.hurtPlayer(pl, math.floor(range(C.TYPES.police.dmg) + 0.5), { by = n.name, dx = dx, dz = dz, outcome = if n.hits % 3 == 0 then "knockdown" else "stagger", line = if n.hits % 2 == 1 then Talk.line(n, "cop_baton") else nil, actor = n.id })
				end
			end
			return
		end
		if n.a.attrs.GiPose == "fight" and d > 5 then
			Actors.pose(n.a, "")
		end
		moveTo(n, target, true, 2.2, sees and d < 26)
		if now - (n.lastSay or 0) > range({ 6, 10 }) and sees then
			say(n, if serious then "cop_baton" else "cop_chase")
		end
		if not sees and now - cs.lastT > 3 and d < 3 then
			cs.stage = "search"
			n.searchPts = nil
		end
	elseif cs.stage == "search" then
		if sees then
			cs.stage = "chase"
			say(n, "cop_chase")
			return
		end
		if not n.searchPts then
			n.searchPts = {}
			local around = cs.lastPos or cs.pos
			for _ = 1, 3 do
				local p = Routine.safePoint(nil, around + Vector3.new(rnd:NextNumber(-1, 1), 0, rnd:NextNumber(-1, 1)).Unit * rnd:NextNumber(10, 26))
				if p then
					table.insert(n.searchPts, p)
				end
			end
			table.insert(n.searchPts, 1, around)
			n.searchI = 1
			n.searchLook = 0
			say(n, "cop_search")
		end
		local p = n.searchPts[n.searchI]
		if not p then
			closeCase(cs, "lost")
			if pl then
				-- the stars go when the evade timer runs out (Interact tick)
			end
			return
		end
		if moveTo(n, p, false, 2.5) then
			n.searchLook += 0.25
			if n.searchLook > 2.5 then
				n.searchLook = 0
				n.searchI += 1
				Actors.emote(n.a, "look_around")
			end
		end
	end
end

function Police.init(interact: any)
	I = interact
	C = I.C
	Mind = I.Mind
	World = I.World
	Actors = I.Actors
	Talk = I.Talk
	Routine = I.Routine
	Places = I.Places
	local gg = script.Parent.Parent
	local tdm = gg and gg:FindFirstChild("TaxiDispatch")
	local navM = ReplicatedStorage:FindFirstChild("GwangalliNav")
	if tdm and tdm:IsA("ModuleScript") and navM then
		local ok, res = pcall(require, tdm)
		local okN, Nav = pcall(require, navM)
		if ok and okN and type(res) == "table" then
			D = res
			local okG, g = pcall(D.graph, Nav)
			if okG then
				graph = g
			end
		end
	end
	local f = workspace:FindFirstChild("GwangalliInteractCars")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwangalliInteractCars"
		f.Parent = workspace
	end
	carsFolder = f :: Folder
	task.spawn(findTemplate)
	-- old cases are forgotten
	task.spawn(function()
		while true do
			task.wait(5)
			for i = #cases, 1, -1 do
				local cs = cases[i]
				if cs.done and os.clock() - cs.t0 > 120 then
					table.remove(cases, i)
				elseif not cs.done and os.clock() - cs.t0 > 240 then
					closeCase(cs, "stale")
				end
			end
		end
	end)
end

return Police
