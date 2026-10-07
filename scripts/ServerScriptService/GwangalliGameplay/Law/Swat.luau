-- GwangalliGameplay/Law/Swat (server; owner: law): 특임대 — the tactical unit for BIG incidents only.
-- Comes in on top of the normal police (Law/Police keeps chasing as before) when a player commits a big
-- crime (은행 / 카지노 습격, 대규모 총격전, 금고 털이: LS.SWAT.MAJOR, via Law.major / Law.crime) or the
-- wanted level reaches LS.SWAT.MIN_STARS. Numbers: LS.SWAT.
--
--   * ARRIVAL: one dark 특임대 van per team (Police.newCar, car kind "swat", 4 seats), spawned far away
--     out of sight and DRIVEN in (never a teleport); 4 operators get out at the scene.
--   * KNOWLEDGE (never a wall-hack): an operator knows where the suspect is only when he SEES him
--     (range / cone / line of sight: Police.canSee with LS.SWAT eyes) or from the radio (the case's
--     last reported position, Law.seen by any unit). Out of sight = the last seen spot.
--   * TEAM: they spread out and come in from up to four directions around the last known position
--     (front / left / right / behind), share sightings, then search the last seen area sector by
--     sector. LS.SWAT.SEARCH_S without a sighting -> 철수 (they board the van and leave): a suspect
--     who breaks line of sight, changes cars or gets far enough away really escapes.
--   * ENGAGE: in sight within FIRE_RANGE they take cover (a spot where the line to the suspect is
--     blocked low and open high = peek-and-shoot) and fire 진압용 고무탄: every shot is a ray that
--     must reach the suspect (walls stop it), the hit chance falls with distance, a sprinting / driving
--     target, the shooter moving and the first shot after acquiring (never sure, LS.SWAT.HIT_CAP).
--     Damage never kills (HP floor); low HP = a short stun (slower), when they rush in and cuff
--     (Law.arrest). Close in they push and grab (a better grab than the police, still not certain).
--   * CAR: a suspect who drives off -> the team runs back to the van and the van chases on the road
--     (Police's car brain: remount -> chase).
--   * SPEED: RUN a little under the player's run, a short BURST when close; never faster than that.
-- API: Swat.deploy(player, why) / Swat.teams() (tests, other modules).

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local Swat = {}

local Law: any
local ctx: any
local LS: any
local SW: any
local P: any -- Law/Police

local teams: { [Player]: any } = {}
local shots: { { pos: Vector3, t: number } } = {} -- recent gunfire (Law/Rescue keeps out)

local UNIT = nil

local function now(): number
	return os.clock()
end

local function rnd(): number
	return math.random()
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function pick(list: { string }): string
	return list[1 + math.floor(rnd() * #list)]
end

local EYES = nil -- the tier table Police.canSee reads (sight / fov)

-------------------------------------------------------------------------------------------------
-- team
-------------------------------------------------------------------------------------------------
local function wanted(player: Player): (boolean, any?)
	local s = Law.sess(player)
	if not s or s.cuffed or s.jail or (s.stars or 0) <= 0 then
		return false, s
	end
	if (s.stars or 0) >= SW.MIN_STARS then
		return true, s
	end
	if s.majorUntil and now() < s.majorUntil then
		return true, s
	end
	return false, s
end

local function teamCount(): number
	local n = 0
	for _, t in teams do
		if not t.done then
			n += 1
		end
	end
	return n
end

local function teamOf(o: any): any?
	for _, t in teams do
		if t.ops and table.find(t.ops, o) then
			return t
		end
	end
	return nil
end

function Swat.deploy(player: Player, why: string?): any?
	if teams[player] and not teams[player].done then
		return teams[player]
	end
	if teamCount() >= SW.MAX_TEAMS then
		return nil
	end
	local s = Law.sess(player)
	local case = P.caseOf(player, true)
	case.stars = math.max(case.stars or 0, s and s.stars or 0)
	case.knownPos = case.knownPos or (s and s.knownPos) or Law.posOf(player)
	case.knownT = case.knownT or now()
	if not case.knownPos then
		return nil
	end
	local van = P.newCar(case, case.knownPos, "swat", UNIT)
	if not van then
		return nil
	end
	local t = { player = player, case = case, van = van, ops = {}, created = now(), knownPos = case.knownPos, knownT = case.knownT, lastSight = now(), why = why, state = "inbound", sector = 0 }
	for _, o in van.crew do
		table.insert(t.ops, o)
		o.team = t
		o.hp = SW.HP
		o.k = #t.ops
	end
	teams[player] = t
	Law.push(player, { kind = "radio", text = "🚨 특임대 출동! (" .. (if why and LS.CRIMES[why] then LS.CRIMES[why].label else "중대 사건") .. ")" })
	return t
end

local function pullOut(t: any, line: boolean)
	if t.done then
		return
	end
	t.done = true
	for _, o in t.ops do
		if not o.gone and o.role == "swat" then
			if line then
				P.say(o, pick(SW.LINES.pullout))
				line = false
			end
			o.state = "leave"
			o.leaveAt = now() + 40
		end
	end
	if t.van and not t.van.gone and P.carLeave then
		pcall(P.carLeave, t.van)
	end
end

-------------------------------------------------------------------------------------------------
-- seeing, shooting
-------------------------------------------------------------------------------------------------
local function sees(o: any, player: Player): (boolean, Vector3?, number)
	return P.canSee(o, player, EYES)
end

local function hitChance(o: any, player: Player, d: number): number
	local p = SW.HIT[#SW.HIT][2]
	for _, band in SW.HIT do
		if d <= band[1] then
			p = band[2]
			break
		end
	end
	local sp = P.suspectSpeed(player)
	if P.suspectInCar(player) then
		p *= 0.5
	elseif sp > 20 then
		p *= 0.55 -- sprinting
	elseif sp > 10 then
		p *= 0.75
	end
	if o.speed and o.speed > 2 then
		p *= 0.7 -- shooting on the move
	end
	if now() - (o.acquiredT or 0) < 1.2 then
		p *= 0.6 -- the first shot after spotting
	end
	return math.min(p, SW.HIT_CAP)
end

local function tracer(from: Vector3, to: Vector3)
	local d = (to - from).Magnitude
	if d < 0.5 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "SwatTracer"
	beam.Anchored = true
	beam.CanCollide, beam.CanQuery, beam.CanTouch, beam.CastShadow = false, false, false, false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 226, 150)
	beam.Size = Vector3.new(0.08, 0.08, d)
	beam.CFrame = CFrame.lookAt((from + to) / 2, to)
	beam.Parent = workspace
	Debris:AddItem(beam, 0.09)
	local flash = Instance.new("Part")
	flash.Name = "SwatFlash"
	flash.Anchored = true
	flash.CanCollide, flash.CanQuery, flash.CanTouch, flash.CastShadow = false, false, false, false
	flash.Transparency = 1
	flash.Size = Vector3.new(0.2, 0.2, 0.2)
	flash.CFrame = CFrame.new(from)
	local l = Instance.new("PointLight")
	l.Range = 9
	l.Brightness = 5
	l.Color = Color3.fromRGB(255, 210, 120)
	l.Parent = flash
	flash.Parent = workspace
	Debris:AddItem(flash, 0.07)
end

local stunned: { [Player]: { untilT: number, ws: number } } = {}

local function stun(player: Player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local st = stunned[player]
	if st then
		st.untilT = now() + SW.STUN_S
		return
	end
	stunned[player] = { untilT = now() + SW.STUN_S, ws = hum.WalkSpeed }
	hum.WalkSpeed = math.min(hum.WalkSpeed, SW.STUN_SPEED)
	player:SetAttribute("LawStunned", workspace:GetServerTimeNow() + SW.STUN_S)
	Law.push(player, { kind = "toast", text = "⚡ 고무탄에 맞아 휘청거려요!" })
end

local function stunTick()
	for player, st in stunned do
		if now() >= st.untilT or not player.Parent then
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.WalkSpeed <= SW.STUN_SPEED + 0.01 then
				hum.WalkSpeed = st.ws
			end
			player:SetAttribute("LawStunned", nil)
			stunned[player] = nil
		end
	end
end

local function isStunned(player: Player): boolean
	local st = stunned[player]
	return st ~= nil and now() < st.untilT
end

-- one shot: a ray from the muzzle; walls stop it; the roll decides hit / miss
local function fire(o: any, player: Player, pp: Vector3, d: number)
	local muzzle = o.pos + Vector3.new(0, 3.6 * (P.CREW_SCALE or 0.84), 0)
	local aim = pp + Vector3.new(0, 1.2, 0)
	table.insert(shots, { pos = o.pos, t = now() })
	while #shots > 40 do
		table.remove(shots, 1)
	end
	-- the street hears it (clients: people nearby scatter by personality)
	if ctx.fight and type(ctx.fight.tell) == "function" and now() - (o.toldShot or 0) > 2 then
		o.toldShot = now()
		for _, pl in Players:GetPlayers() do
			local q = Law.posOf(pl)
			if q and flat(q, o.pos) < 160 then
				pcall(ctx.fight.tell, pl, { kind = "gunfire", pos = { o.pos.X, o.pos.Y, o.pos.Z } })
			end
		end
	end
	P.faceTo(o, pp)
	P.emote(o, "point_proc")
	if not P.losClear(muzzle, aim) then
		tracer(muzzle, muzzle + (aim - muzzle).Unit * math.min(d, 6))
		return false
	end
	local hit = rnd() < hitChance(o, player, d)
	if hit then
		tracer(muzzle, aim)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			local dmg = math.random(SW.DMG[1], SW.DMG[2])
			hum.Health = math.max(SW.HP_FLOOR, hum.Health - dmg)
			if hum.Health <= SW.STUN_HP then
				stun(player)
			end
		end
	else
		-- a miss lands near them (a puff of the near miss)
		local off = Vector3.new((rnd() - 0.5) * 6, (rnd() - 0.3) * 3, (rnd() - 0.5) * 6)
		tracer(muzzle, aim + off)
	end
	return hit
end

-- a cover spot near o: the low line to the suspect blocked, the high line open (peek and shoot)
local function coverNear(o: any, pp: Vector3): Vector3?
	local best, bestD = nil, math.huge
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2 + rnd() * 0.3
		local r = SW.COVER_R[1] + rnd() * (SW.COVER_R[2] - SW.COVER_R[1])
		local q = o.pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local y = P.groundAt(q, o.pos.Y)
		if math.abs(y - o.pos.Y) < 3 then
			q = Vector3.new(q.X, y, q.Z)
			local low = not P.losClear(q + Vector3.new(0, 1.3, 0), pp + Vector3.new(0, 1.2, 0))
			local high = P.losClear(q + Vector3.new(0, 4.4, 0), pp + Vector3.new(0, 1.2, 0))
			if low and high then
				local dd = flat(q, o.pos)
				if dd < bestD then
					best, bestD = q, dd
				end
			end
		end
	end
	return best
end

-------------------------------------------------------------------------------------------------
-- the operator brain (Police.unitThink.swat)
-------------------------------------------------------------------------------------------------
local function sectorPoint(center: Vector3, k: number, rMin: number, rMax: number, base: number?): Vector3
	local a = (base or 0) + (k - 1) * (math.pi / 2) + (rnd() - 0.5) * 0.6
	local r = rMin + rnd() * (rMax - rMin)
	local q = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	return Vector3.new(q.X, P.groundAt(q, center.Y), q.Z)
end

local function think(o: any)
	local t = o.team or teamOf(o)
	o.team = t
	if not t or t.done then
		o.state = "leave"
		o.leaveAt = now() + 40
		return
	end
	local player = t.player
	local on, s = wanted(player)
	if not player.Parent or not on then
		pullOut(t, true)
		return
	end
	if now() < (o.pauseUntil or 0) then
		return
	end
	-- the radio: a newer sighting by anybody (police included) moves the team's picture
	local case = t.case
	if case and case.knownT and case.knownT > (t.knownT or 0) and case.knownPos then
		t.knownT, t.knownPos = case.knownT, case.knownPos
	end
	-- eyes
	local seeing, pp, d = false, nil, math.huge
	if now() >= (o.nextSight or 0) then
		o.nextSight = now() + 0.25
		local ok, p, dist = sees(o, player)
		pp, d = p, dist
		if ok then
			o.glimpse = o.glimpse or now()
			seeing = now() - o.glimpse >= SW.react or dist < 10
		else
			o.glimpse = nil
		end
		o.seeing = seeing
	else
		seeing = o.seeing
		if seeing then
			pp = Law.posOf(player)
			d = pp and flat(o.pos, pp) or math.huge
		end
	end
	if seeing and pp then
		if not o.wasSeeing then
			o.acquiredT = now()
			if now() - (t.spotLine or 0) > 6 then
				t.spotLine = now()
				P.say(o, pick(SW.LINES.spot), 3)
			end
		end
		o.wasSeeing = true
		t.knownPos, t.knownT = pp, now()
		t.lastSight = now()
		t.engaged = true
		Law.seen(player, pp, o.name)
		if case then
			case.knownPos, case.knownT = pp, now()
		end
	else
		if o.wasSeeing then
			o.lostT = now()
		end
		o.wasSeeing = false
	end
	-- pulled out after a long time without anybody seeing him (the suspect really got away)
	if now() - (t.lastSight or t.created) > SW.SEARCH_S and now() - t.created > SW.SEARCH_S then
		pullOut(t, true)
		return
	end
	local st = o.state
	if st == "deploy" then
		if now() - (t.deployLine or 0) > 8 then
			t.deployLine = now()
			P.say(o, pick(SW.LINES.deploy), 3)
		end
		-- come in from my own side of the last known spot (front / left / right / behind)
		local center = t.knownPos or o.pos
		local base = math.atan2(o.pos.Z - center.Z, o.pos.X - center.X)
		local q = sectorPoint(center, o.k or 1, 8, 14, base)
		P.assignGoal(o, q, SW.RUN, nil)
		o.state = "approach"
		o.goalAt = now()
		return
	end
	if seeing and pp then
		-- the suspect drove off: back to the van (the van brain does the road chase)
		if P.suspectInCar(player) and d > 25 and t.van and not t.van.gone then
			if now() - (t.carLine or 0) > 8 then
				t.carLine = now()
				P.say(o, pick(SW.LINES.car))
			end
			P.boardOfficer(o, t.van)
			return
		end
		-- grab range: cuff (a stunned / slow suspect is caught)
		if d <= (LS.GRAB_RANGE or 3.4) + 0.4 and now() >= (o.grabAt or 0) then
			o.grabAt = now() + 1.1
			local base = LS.grabChance(math.max(4, s.stars or 4), P.suspectSpeed(player), P.suspectInCar(player))
			local chance = if isStunned(player) then 1 else math.min(0.9, base * SW.GRAB_MULT)
			if rnd() < chance then
				P.standAt(o, P.legPos(o, now()))
				P.faceTo(o, pp)
				P.say(o, pick(SW.LINES.grab))
				Law.arrest(player, { by = "npc", officer = o, forced = true })
				pullOut(t, false)
				return
			end
			o.pauseUntil = now() + 0.5
			return
		end
		-- close: push in (two operators at most rush, the rest cover)
		local rushers = 0
		for _, m in t.ops do
			if m ~= o and not m.gone and m.state == "rush" then
				rushers += 1
			end
		end
		if d < 16 and (rushers < 2 or isStunned(player)) then
			if o.state ~= "rush" and now() - (t.pushLine or 0) > 6 then
				t.pushLine = now()
				P.say(o, pick(SW.LINES.push))
			end
			o.state = "rush"
			if now() >= (o.nextRepath or 0) then
				o.nextRepath = now() + 0.45
				o.pos = P.legPos(o, now())
				local burst = d < 12 and now() >= (o.burstReady or 0)
				if burst then
					o.burstReady = now() + 5
					o.burstUntil = now() + 1.5
				end
				P.assignGoal(o, pp, if now() < (o.burstUntil or 0) then SW.BURST else SW.RUN, nil)
			end
			return
		end
		-- in range: cover, then peek and shoot
		if d <= SW.FIRE_RANGE then
			if o.state ~= "cover" and o.state ~= "fire" then
				o.state = "cover"
				local c = coverNear(o, pp)
				if c then
					P.assignGoal(o, c, 12.5, nil)
					if now() - (t.coverLine or 0) > 7 then
						t.coverLine = now()
						P.say(o, pick(SW.LINES.cover))
					end
				else
					o.state = "fire"
					P.standAt(o, P.legPos(o, now()))
				end
				o.nextShot = now() + 0.6 + rnd() * 0.5
			elseif o.state == "cover" and P.arrived(o) then
				o.state = "fire"
				P.setAct(o, "guard")
			end
			if now() >= (o.nextShot or 0) then
				o.nextShot = now() + SW.FIRE_GAP[1] + rnd() * (SW.FIRE_GAP[2] - SW.FIRE_GAP[1])
				o.pos = P.legPos(o, now())
				fire(o, player, pp, d)
			end
			-- keep the pressure: now and then one moves up (flank) to a spot closer
			if o.state == "fire" and now() >= (o.moveUpAt or 0) then
				o.moveUpAt = now() + 4 + rnd() * 3
				if rnd() < 0.45 then
					local q = sectorPoint(pp, o.k or 1, math.max(8, d * 0.5), math.max(10, d * 0.7), math.atan2(o.pos.Z - pp.Z, o.pos.X - pp.X))
					o.state = "cover"
					P.assignGoal(o, q, SW.RUN, nil)
				end
			end
			return
		end
		-- far but seen: close in
		if now() >= (o.nextRepath or 0) then
			o.nextRepath = now() + 0.9
			o.pos = P.legPos(o, now())
			P.assignGoal(o, pp, SW.RUN, nil)
			o.state = "pursue"
		end
		return
	end
	-- not seeing him myself: the last known spot (team / radio), then a sector search
	if st == "rush" or st == "cover" or st == "fire" or st == "pursue" then
		if now() - (o.lostT or 0) > 1.2 then
			o.state = "pursue"
			o.pos = P.legPos(o, now())
			if t.knownPos then
				if now() - (t.lostLine or 0) > 8 then
					t.lostLine = now()
					P.say(o, pick(SW.LINES.lost))
				end
				P.assignGoal(o, sectorPoint(t.knownPos, o.k or 1, 2, 7), SW.RUN, nil)
			end
			o.state = "approach"
			o.goalAt = now()
		end
		return
	end
	if st == "approach" then
		-- a fresher radio fix while on the way: re-aim
		if t.knownT and t.knownT > (o.goalAt or 0) + 2 and t.knownPos then
			o.goalAt = now()
			o.pos = P.legPos(o, now())
			P.assignGoal(o, sectorPoint(t.knownPos, o.k or 1, 6, 12, math.atan2(o.pos.Z - t.knownPos.Z, o.pos.X - t.knownPos.X)), SW.RUN, nil)
			return
		end
		if P.arrived(o) then
			o.state = "search"
			o.searchLeft = 3 + math.floor(rnd() * 2)
			P.setAct(o, "lookout")
			o.pauseUntil = now() + 0.8 + rnd() * 1.2
		end
		return
	end
	if st == "search" then
		if P.arrived(o) then
			o.pos = P.legPos(o, now())
			o.searchLeft = (o.searchLeft or 3) - 1
			local center = t.knownPos or o.pos
			-- my own sector, a little wider every round
			local ring = math.clamp(10 + (now() - (t.knownT or now())) * 0.6, 10, 38)
			local q = sectorPoint(center, o.k or 1, ring * 0.5, ring)
			if rnd() < 0.3 then
				P.say(o, pick(SW.LINES.search))
			end
			P.assignGoal(o, q, 9.5, nil)
			o.pauseUntil = now() + 0.5 + rnd() * 1.4
		end
		return
	end
	if st == "pursue" then
		o.state = "approach"
		o.goalAt = now()
		if t.knownPos then
			P.assignGoal(o, sectorPoint(t.knownPos, o.k or 1, 3, 8), SW.RUN, nil)
		end
		return
	end
	-- anything else (after boarding failed etc.)
	o.state = "deploy"
end

-------------------------------------------------------------------------------------------------
-- Law child contract
-------------------------------------------------------------------------------------------------
local acc = 0
function Swat.tick(dt: number)
	stunTick()
	acc += dt
	if acc < 1 then
		return
	end
	acc = 0
	for _, player in Players:GetPlayers() do
		local on = wanted(player)
		local t = teams[player]
		if on and (not t or t.done) then
			local s = Law.sess(player)
			Swat.deploy(player, s and s.majorKind or nil)
		elseif not on and t and not t.done then
			pullOut(t, true)
		end
	end
	for player, t in teams do
		if t.done then
			local alive = false
			for _, o in t.ops do
				if not o.gone then
					alive = true
				end
			end
			if not alive or not player.Parent then
				teams[player] = nil
			end
		end
	end
end

function Swat.onLeave(player: Player)
	local t = teams[player]
	if t then
		pullOut(t, false)
	end
	stunned[player] = nil
end

-- recent gunfire near a point (Law/Rescue keeps the ambulance back)
function Swat.gunfireNear(pos: Vector3, r: number, secs: number): boolean
	local t0 = now() - secs
	for i = #shots, 1, -1 do
		local sh = shots[i]
		if sh.t < t0 then
			break
		end
		if flat(sh.pos, pos) < r then
			return true
		end
	end
	return false
end

-- an engaged team near a point (the scene is not safe yet)
function Swat.activeNear(pos: Vector3, r: number): boolean
	for _, t in teams do
		if not t.done and t.engaged and t.knownPos and flat(t.knownPos, pos) < r and now() - (t.lastSight or 0) < 15 then
			return true
		end
	end
	return false
end

function Swat.teams(): any
	return teams
end

function Swat.init(law: any, context: any)
	Law = law
	ctx = context
	LS = Law.LS or require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliLawShared")) :: any
	SW = LS.SWAT
	P = Law.children.Police
	assert(P and SW, "Law/Swat needs Law/Police and LS.SWAT")
	EYES = { sight = SW.sight, fov = SW.fov }
	UNIT = {
		kind = "swat",
		car = "swat",
		crew = SW.TEAM,
		label = "특임대",
		prefix = "swat_",
		names = SW.NAMES,
		look = { style = "swat", body = "m", age = "adult", acc = { "tac_helmet", "rifle" } },
		extraCap = SW.TEAM * SW.MAX_TEAMS,
		extraCars = SW.MAX_TEAMS,
	}
	P.unitThink.swat = think
	ctx.swat = Swat
end

return Swat
