-- Interact/Mind (server): the brains of the city NPCs (Cast). One record per person:
--   traits (Cast), mood { v (-1..1), anger, fear (0..1) }, patience (0..100), drunk (0..1), hp,
--   mode: routine | talk | conflict | flee | cower | watch | intervene | report | down | police |
--         custody | dodge | embarrassed,
--   conf[key] = { level 0..4 (항의 1 / 말다툼 2 / 위협 3 / 몸싸움 4), t, cause, starter, ... },
--   knows[incidentId] = { how = seen|heard|told, t }, talkWith (UserId in a conversation).
-- The routine (schedules, activities, facilities) lives in Routine; the player's verbs in Verbs.
-- Each NPC thinks at a rate set by its distance to the nearest player (LOD): near 4 Hz, mid ~1 Hz,
-- far every 3 s (no perception work, walks are skipped). Nothing compares all NPCs every frame.

local Players = game:GetService("Players")

local Mind = {}

local I: any
local C: any
local Cast: any
local Actors: any
local World: any
local Talk: any
local Memory: any
local Routine: any
local Police: any

local npcs: { [string]: any } = {}
Mind.list = npcs
local rnd = Random.new()

local function range(t: { number }): number
	return t[1] + (t[2] - t[1]) * rnd:NextNumber()
end
Mind.range = range

local function clamp(v: number, a: number, b: number): number
	return math.max(a, math.min(b, v))
end

function Mind.get(id: string): any?
	return npcs[id]
end

function Mind.byKey(key: string?): any?
	if type(key) == "string" and string.sub(key, 1, 2) == "n:" then
		return npcs[string.sub(key, 3)]
	end
	return nil
end

function Mind.byActor(a: any): any?
	for _, n in npcs do
		if n.a == a then
			return n
		end
	end
	return nil
end

function Mind.clock(): number
	local ok, env = pcall(I.ctx.env)
	if ok and type(env) == "table" and type(env.clock) == "number" then
		return env.clock
	end
	return 12
end

---------------------------------------------------------------------------------------------------
-- mood / expression / attributes the clients render
---------------------------------------------------------------------------------------------------
local function expression(n: any): string
	if n.mode == "down" then
		return "hurt"
	elseif n.mood.fear > 0.55 then
		return "scared"
	elseif n.mood.anger > 0.55 then
		return "angry"
	elseif n.mode == "embarrassed" then
		return "embarrassed"
	elseif n.drunk > 0.5 then
		return "drunk"
	elseif n.mood.v > 0.35 then
		return "happy"
	elseif n.mood.v < -0.35 then
		return "sad"
	elseif n.mode == "watch" then
		return "surprised"
	end
	return "neutral"
end

function Mind.sync(n: any)
	local a = n.a
	if not a or a.gone then
		return
	end
	Actors.setAttr(a, "GiMood", expression(n))
	Actors.setAttr(a, "GiMode", n.mode)
	-- conflicts with players (the wheel shows 사과 / 도망 first): "uid:level,uid:level"
	local parts = {}
	for key, c in n.conf do
		if c.level >= 1 and string.sub(key, 1, 2) == "p:" then
			table.insert(parts, string.sub(key, 3) .. ":" .. math.floor(c.level))
		end
	end
	Actors.setAttr(a, "GiConf", table.concat(parts, ","))
	local gait = n.def.gait or "normal"
	if n.mode == "flee" then
		gait = "run"
	elseif n.mode == "police" and n.policeRun then
		gait = "run"
	elseif (n.hp or 100) < (n.max or 100) * 0.35 then
		gait = "limp"
	end
	Actors.setAttr(a, "GiGait", gait)
end

function Mind.feel(n: any, d: { [string]: number })
	n.mood.anger = clamp(n.mood.anger + (d.anger or 0), 0, 1)
	n.mood.fear = clamp(n.mood.fear + (d.fear or 0), 0, 1)
	n.mood.v = clamp(n.mood.v + (d.v or 0), -1, 1)
	if d.patience then
		n.patience = clamp(n.patience + d.patience, 0, 100)
	end
	Mind.sync(n)
end

function Mind.setMode(n: any, mode: string, dur: number?)
	if n.mode == mode and not dur then
		return
	end
	local prev = n.mode
	n.mode = mode
	n.modeT = os.clock()
	n.modeUntil = if dur then os.clock() + dur else 0
	if prev == "routine" and mode ~= "routine" then
		Routine.pause(n)
	end
	if mode ~= "talk" and n.talkWith then
		local p = Players:GetPlayerByUserId(n.talkWith)
		n.talkWith = nil
		if p then
			I.closeCard(p, n.id)
		end
	end
	if n.a and not n.a.gone then
		if mode ~= "conflict" and mode ~= "police" then
			Actors.pose(n.a, Routine.restPose(n))
		end
	end
	Mind.sync(n)
end

function Mind.toRoutine(n: any, delay: number?)
	if n.mode == "custody" or n.mode == "police" then
		return
	end
	n.focus = nil
	if delay and delay > 0 then
		Mind.setMode(n, "recover", delay)
		return
	end
	Mind.setMode(n, "routine")
	Routine.resume(n)
end

---------------------------------------------------------------------------------------------------
-- talking + facing helpers
---------------------------------------------------------------------------------------------------
function Mind.say(n: any, situation: string, vars: any?, dur: number?): string?
	if not n.a or n.a.gone then
		return nil
	end
	return Talk.say(n, situation, vars, dur)
end

function Mind.faceKey(n: any, key: string?)
	local p = World.posOf(key)
	if p and n.a then
		Actors.face(n.a, p)
		n.focus = key
		Actors.setAttr(n.a, "GiLook", key or "")
	end
end

function Mind.lookAt(n: any, key: string?)
	if n.a then
		Actors.setAttr(n.a, "GiLook", key or "")
	end
end

function Mind.myKey(n: any): string
	return "n:" .. n.id
end

function Mind.pos(n: any): Vector3?
	if n.a and not n.a.gone then
		return Actors.pos(n.a)
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- conflicts (the ladder): 0 none, 1 항의, 2 말다툼, 3 위협, 4 몸싸움
---------------------------------------------------------------------------------------------------
local LEVEL_SIT = { "complain", "argue", "threat", "fight_start" }
local LEVEL_INC = { nil, "argument", "threat", "fight" }

local function confOf(n: any, key: string): any
	local c = n.conf[key]
	if not c then
		c = { level = 0, t = os.clock(), since = os.clock(), cause = "", starter = nil, said = 0, nextAct = 0, hits = 0, farSince = nil }
		n.conf[key] = c
	end
	return c
end
Mind.confOf = confOf

function Mind.topConflict(n: any): (string?, any?)
	local bk, bc = nil, nil
	for key, c in n.conf do
		if c.level >= 1 and (not bc or c.level > bc.level or (c.level == bc.level and c.t > bc.t)) then
			bk, bc = key, c
		end
	end
	return bk, bc
end

local function incidentFor(n: any, key: string, c: any)
	local kind = LEVEL_INC[math.floor(c.level)]
	if not kind then
		return
	end
	local pos = Mind.pos(n)
	if not pos then
		return
	end
	local aggressor = if c.starter == "self" then Mind.myKey(n) else key
	local victim = if c.starter == "self" then key else Mind.myKey(n)
	c.inc = World.incident(kind, pos, { aggressor = aggressor, victim = victim })
end

-- raise the conflict with `key` by amount (scaled by the NPC's temper); starter = "self" when this
-- NPC started it
function Mind.provoke(n: any, key: string, amount: number, cause: string, starter: string?)
	if n.mode == "custody" then
		return
	end
	local T = n.traits
	local c = confOf(n, key)
	if c.level == 0 then
		c.starter = starter or "other"
		c.since = os.clock()
	end
	local before = math.floor(c.level)
	local k = 0.6 + T.temper * 0.8 + n.drunk * 0.3 - (n.patience / 100) * 0.4
	c.level = clamp(c.level + amount * k, 0, 4)
	c.t = os.clock()
	c.cause = cause
	c.farSince = nil
	Mind.feel(n, { anger = 0.12 * amount * (0.5 + T.temper), patience = -8 * amount, v = -0.05 * amount })
	if n.mode ~= "conflict" and n.mode ~= "police" and n.mode ~= "down" then
		Mind.setMode(n, "conflict")
	end
	local after = math.floor(c.level)
	if after > before then
		c.said = 0
		if after >= 2 then
			incidentFor(n, key, c)
		end
	end
	Mind.faceKey(n, key)
	Mind.sync(n)
end

-- lower the conflict; returns the new level
function Mind.calm(n: any, key: string, amount: number, cause: string?): number
	local c = n.conf[key]
	if not c then
		return 0
	end
	c.level = math.max(0, c.level - amount)
	c.t = os.clock()
	if c.level < 1 then
		n.conf[key] = nil
		-- a quarrel that calms down ends its incident; a real crime (assault / robbery / KO) stays on
		-- record for the witnesses and the police until it goes stale (World.tick)
		if c.inc and c.inc.status ~= "resolved" and (c.inc.sev or 1) <= 2 and (c.inc.aggressor == key or c.inc.aggressor == Mind.myKey(n)) then
			World.resolve(c.inc, cause or "calmed")
		end
		if not Mind.topConflict(n) and n.mode == "conflict" then
			Mind.toRoutine(n, 2.5)
		end
	end
	Mind.sync(n)
	return c.level
end

-- the NPC decides to back off (retreat / scared)
function Mind.retreat(n: any, fromKey: string, situation: string?)
	if situation then
		Mind.say(n, situation)
	end
	n.conf[fromKey] = nil
	Mind.flee(n, World.posOf(fromKey), 5 + rnd:NextNumber() * 3, false)
end

---------------------------------------------------------------------------------------------------
-- fear: flee / cower
---------------------------------------------------------------------------------------------------
function Mind.flee(n: any, from: Vector3?, secs: number, scream: boolean)
	local a = n.a
	if not a or a.gone then
		return
	end
	Mind.setMode(n, "flee", secs)
	local me = Actors.pos(a)
	local d = if from then Vector3.new(me.X - from.X, 0, me.Z - from.Z) else Vector3.new(1, 0, 0)
	if d.Magnitude < 0.2 then
		d = Vector3.new(rnd:NextNumber(-1, 1), 0, rnd:NextNumber(-1, 1))
	end
	local target = Routine.safePoint(n, me + d.Unit * 24) or (me + d.Unit * 18)
	Actors.walkTo(a, target, (Cast.ARCH[n.arch] or Cast.ARCH.citizen).run)
	if scream then
		Mind.say(n, "flee_scream")
	end
end

function Mind.cower(n: any, secs: number, line: string?)
	Mind.setMode(n, "cower", secs)
	if n.a then
		Actors.stop(n.a)
		Actors.pose(n.a, "cower")
	end
	if line then
		Mind.say(n, line)
	end
end

---------------------------------------------------------------------------------------------------
-- hits between NPCs and players
---------------------------------------------------------------------------------------------------
local function dirTo(from: Vector3, to: Vector3): (number, number)
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if d.Magnitude < 1e-3 then
		return 0, -1
	end
	d = d.Unit
	return d.X, d.Z
end
Mind.dirTo = dirTo

-- this NPC lands a punch on `key` (player or NPC)
function Mind.punch(n: any, key: string, c: any?)
	local me = Mind.pos(n)
	local them = World.posOf(key)
	if not me or not them then
		return
	end
	local dx, dz = dirTo(me, them)
	Actors.face(n.a, them)
	Actors.emote(n.a, "punch")
	local T = C.typeOf(if n.arch == "police" then "police" elseif n.arch == "thug" then "violent" elseif n.arch == "drunk" then "drunk" else "plain")
	local dmg = math.floor(range(T.dmg) * (0.8 + n.traits.aggression * 0.4) + 0.5)
	if c then
		c.hits += 1
	end
	local outcome = if c and c.hits % 3 == 0 then "knockdown" else "stagger"
	local p = World.playerOf(key)
	if p then
		I.hurtPlayer(p, dmg, { by = n.name, dx = dx, dz = dz, outcome = outcome, actor = n.id, line = if rnd:NextNumber() < 0.35 then Talk.line(n, "fight_start") else nil })
	else
		local v = Mind.byKey(key)
		if v then
			Mind.hitNPC(v, n, dmg, outcome, dx, dz)
		end
	end
	local inc = World.incident(if c and c.starter == "self" then "assault" else "fight", me, { aggressor = if c and c.starter ~= "self" then key else Mind.myKey(n), victim = if c and c.starter ~= "self" then Mind.myKey(n) else key })
	if c then
		c.inc = inc
	end
end

-- an NPC gets hit (by a player via Verbs, or by another NPC)
function Mind.hitNPC(v: any, byN: any?, dmg: number, outcome: string, dx: number, dz: number, byKey: string?)
	local a = v.a
	if not a or a.gone then
		return
	end
	v.hp = math.max(0, (v.hp or 50) - dmg)
	a.hp = v.hp
	Actors.setHP(a)
	if v.hp <= 0 then
		outcome = "ko"
	end
	local key = byKey or (byN and Mind.myKey(byN))
	if key then
		task.defer(function()
			for _, inc in World.incidents do
				if inc.victim == Mind.myKey(v) and inc.aggressor == key and inc.status ~= "resolved" then
					v.victimInc = inc
					v.fleeInc = inc
				end
			end
		end)
	end
	if outcome == "ko" then
		Actors.down(a, dx, dz, "ko", range(C.KO_TIME))
		Mind.setMode(v, "down")
		v.downThen = "flee"
		v.hp = math.floor(v.max * 0.5)
		task.delay(0.2, function()
			if v.victimInc then
				Mind.laterReport(v, v.victimInc, 14 + rnd:NextNumber() * 4, 0.4 + v.traits.civic * 0.5)
			end
		end)
		if key then
			v.conf[key] = nil
		end
		Mind.say(v, "hurt")
		return outcome
	end
	Actors.down(a, dx, dz, outcome, if outcome == "knockdown" then 1.6 else nil)
	Actors.emote(a, "hurt")
	Mind.feel(v, { fear = 0.25 * (1 - v.traits.courage), anger = 0.3 * v.traits.aggression + 0.1 })
	if not key then
		return outcome
	end
	-- fight back or run (courage, anger, aggression, how hurt)
	local T = v.traits
	local hurtK = 1 - (v.hp / math.max(1, v.max))
	local fight = T.aggression * 0.55 + T.courage * 0.45 + v.mood.anger * 0.3 - hurtK * 0.6 - v.mood.fear * 0.4
	if v.arch == "police" then
		fight = 1
	elseif v.arch == "fool" or v.arch == "homeless" then
		fight = fight - 0.5
	end
	v.downThen = if fight > 0.45 then "fight" elseif fight > 0.15 then "cower" else "flee"
	v.downKey = key
	if v.downThen ~= "fight" and v.arch ~= "police" then
		-- the victim calls the police once away from the attacker
		task.delay(0.2, function()
			if v.victimInc then
				Mind.laterReport(v, v.victimInc, 9 + rnd:NextNumber() * 4, 0.35 + T.civic * 0.5)
			end
		end)
	end
	Mind.setMode(v, "down")
	if v.downThen == "fight" then
		local c = confOf(v, key)
		c.level = 4
		c.t = os.clock()
		if not c.starter then
			c.starter = "other"
		end
	end
	return outcome
end

---------------------------------------------------------------------------------------------------
-- perception: what an NPC does about an incident it saw / heard / was told
---------------------------------------------------------------------------------------------------
local function busyMode(n: any): boolean
	return n.mode == "down" or n.mode == "custody" or n.mode == "police" or n.mode == "flee" or n.mode == "report" or n.mode == "dodge"
end

-- somebody who ran (a witness, the victim) calls 112 once safe — unless it is over or already called in
local function laterReport(n: any, inc: any, delay: number, chance: number)
	if rnd:NextNumber() > chance then
		return
	end
	task.delay(delay, function()
		if not n.present or not n.a or n.mode == "down" or n.mode == "custody" or n.mode == "conflict" or n.mode == "report" then
			return
		end
		if inc.status == "resolved" or inc.report ~= nil or (inc.reporting or 0) >= 1 then
			return
		end
		Mind.report(n, inc)
	end)
end
Mind.laterReport = laterReport

function Mind.perceive(n: any, inc: any, how: string)
	if n.arch == "police" then
		if Police then
			Police.onPerceive(n, inc, how)
		end
		return
	end
	if busyMode(n) or n.mode == "conflict" then
		return
	end
	local me = Mind.pos(n)
	if not me then
		return
	end
	local T = n.traits
	local dist = (me - inc.pos).Magnitude
	local sev = inc.sev
	local closeK = clamp(1 - dist / 40, 0, 1)
	local seen = how == "seen"
	-- fear rises with the severity and the distance, against courage
	Mind.feel(n, { fear = (sev / 4) * (if seen then 0.6 else 0.3) * (0.4 + closeK) * (1.1 - T.courage), v = -0.05 * sev })
	-- a talk with a player is interrupted by anything serious nearby
	if n.mode == "talk" and (sev >= 2 or dist < 15) then
		Mind.say(n, "distracted", World.describe(inc))
	end
	if sev <= 1 and not seen then
		-- a shout somewhere: turn and look
		Actors.face(n.a, inc.pos)
		return
	end
	if not seen then
		-- heard it: look there; the curious walk closer to see what is going on
		Actors.face(n.a, inc.pos)
		if T.curiosity > 0.6 and n.mood.fear < 0.5 and n.mode == "routine" then
			Mind.setMode(n, "watch", 25)
			n.watchInc = inc
			Mind.say(n, "distracted", World.describe(inc))
		end
		return
	end
	-- seen it: the archetypes first
	if n.arch == "thug" then
		local copNear = Police and Police.copNear(me, 22)
		if copNear then
			Mind.say(n, "back_off_police")
			Mind.flee(n, copNear, 6, false)
			return
		end
		Mind.setMode(n, "watch", 30)
		n.watchInc = inc
		if rnd:NextNumber() < 0.5 then
			Mind.say(n, "watch_comment", World.describe(inc))
		end
		return
	elseif n.arch == "fool" and sev <= 3 then
		Mind.setMode(n, "watch", 20)
		n.watchInc = inc
		Mind.say(n, "watch_comment", World.describe(inc))
		Actors.emote(n.a, if rnd:NextNumber() < 0.5 then "cheer" else "laugh")
		return
	end
	local reported = inc.report ~= nil or (inc.reporting or 0) >= 1
	local scores = {
		flee = n.mood.fear * 1.3 + (if sev >= 3 and dist < 14 then 0.3 else 0),
		watch = T.curiosity * (1 - n.mood.fear) * 0.9,
		report = if reported then 0.05 else T.civic * (if sev >= 2 then 1 else 0.35) * (1 - n.mood.fear * 0.4),
		intervene = if sev <= 3 then T.kindness * T.courage * 0.9 * (1 - n.drunk) else 0,
		ignore = (1 - T.curiosity) * 0.45 + (if dist > 30 then 0.3 else 0),
	}
	if n.arch == "drunk" then
		scores.report = scores.report * 0.3
		scores.watch += 0.3
	end
	local best, bs = "ignore", -1
	for k, v in scores do
		local s = v + rnd:NextNumber() * 0.25
		if s > bs then
			best, bs = k, s
		end
	end
	if best == "flee" then
		Mind.flee(n, inc.pos, 7, sev >= 3)
		n.fleeInc = inc
		if sev >= 2 then
			laterReport(n, inc, 8 + rnd:NextNumber() * 3, 0.2 + T.civic * 0.6)
		end
	elseif best == "report" then
		Mind.report(n, inc)
	elseif best == "intervene" then
		Mind.setMode(n, "intervene", 12)
		n.watchInc = inc
		local p = Routine.nearPoint(me, inc.pos, 4)
		Actors.walkTo(n.a, p, (Cast.ARCH[n.arch] or Cast.ARCH.citizen).walk * 1.4)
	elseif best == "watch" then
		Mind.setMode(n, "watch", 30)
		n.watchInc = inc
		local p = Routine.nearPoint(me, inc.pos, 14)
		Actors.walkTo(n.a, p, (Cast.ARCH[n.arch] or Cast.ARCH.citizen).walk)
		if rnd:NextNumber() < 0.5 then
			Mind.say(n, "watch_comment", World.describe(inc))
		end
	else
		Actors.face(n.a, inc.pos)
	end
end

-- call 112: phone pose, the call line, then the police know (where the caller saw it)
function Mind.report(n: any, inc: any)
	inc.reporting = (inc.reporting or 0) + 1
	Mind.setMode(n, "report", 5)
	n.watchInc = inc
	if n.a then
		Actors.stop(n.a)
		Actors.face(n.a, inc.pos)
		Actors.pose(n.a, "phone")
	end
	local words = World.describe(inc)
	Mind.say(n, "call_police", words, 4.5)
	task.delay(4, function()
		if n.mode == "report" and Police then
			local suspectPos = World.posOf(inc.aggressor, inc.pos)
			local seesSuspect = suspectPos and World.canSee(n, suspectPos)
			Police.report(inc, { by = Mind.myKey(n), pos = inc.pos, suspectPos = if seesSuspect then suspectPos else nil, name = n.name })
		end
		if n.mode == "report" then
			if n.a then
				Actors.pose(n.a, Routine.restPose(n))
			end
			Mind.setMode(n, "watch", 18)
		end
	end)
end

-- an incident is over: watchers, the frightened and the reporters go back to their day
function Mind.onResolved(inc: any)
	for _, n in npcs do
		if (n.watchInc == inc or n.fleeInc == inc) and (n.mode == "watch" or n.mode == "intervene" or n.mode == "cower") then
			n.watchInc = nil
			n.fleeInc = nil
			Mind.feel(n, { fear = -0.3 })
			Mind.toRoutine(n, range({ 1, 3 }))
		end
	end
end

---------------------------------------------------------------------------------------------------
-- per-mode behaviour
---------------------------------------------------------------------------------------------------
local function conflictStep(n: any, now: number)
	local key, c = Mind.topConflict(n)
	if not key then
		Mind.toRoutine(n, 1.5)
		return
	end
	local a = n.a
	local me = Actors.pos(a)
	local them = World.posOf(key)
	local pl = World.playerOf(key)
	local otherN = Mind.byKey(key)
	if not them or (pl and I.state(pl).busy) or (otherN and (otherN.mode == "custody" or not otherN.present)) then
		n.conf[key] = nil
		return
	end
	local dist = Vector3.new(them.X - me.X, 0, them.Z - me.Z).Magnitude
	local T = n.traits
	local level = math.floor(c.level)
	-- police nearby: the troublemakers stand down (unless furious and brave)
	if Police and (n.arch == "thug" or n.arch == "drunk") and level >= 2 then
		local cop = Police.copNear(me, 20)
		if cop and not (n.mood.anger > 0.85 and T.courage > 0.8) then
			Mind.say(n, "back_off_police")
			Mind.calm(n, key, 4, "police")
			Mind.flee(n, cop, 6, false)
			return
		end
	end
	-- distance cools things down
	if dist > 16 then
		c.farSince = c.farSince or now
		local far = now - c.farSince
		if level >= 3 and T.aggression * n.mood.anger > 0.45 and far < 6 and dist < 40 then
			-- chase a little
			if now >= c.nextAct then
				c.nextAct = now + 0.6
				Actors.walkTo(a, Routine.nearPoint(me, them, 2.6), (Cast.ARCH[n.arch] or Cast.ARCH.citizen).run, dist < 26)
				if not c.chased then
					c.chased = true
					Mind.say(n, "taunt_flee")
				end
			end
			return
		end
		if far > 4 then
			if c.chased and not c.gaveUp then
				c.gaveUp = true
				Mind.say(n, "give_up_chase")
			end
			Mind.calm(n, key, 1, "distance")
			c.farSince = now
		end
		Actors.stop(a)
		Actors.face(a, them)
		return
	end
	c.farSince = nil
	Actors.face(a, them)
	Mind.lookAt(n, key)
	if level >= 4 then
		Actors.pose(a, "fight")
		if dist > C.NPC_FIGHT.reach then
			if now >= c.nextAct then
				c.nextAct = now + 0.4
				Actors.walkTo(a, Routine.nearPoint(me, them, C.NPC_FIGHT.reach - 0.8), C.NPC_FIGHT.speed, true)
			end
			return
		end
		Actors.stop(a)
		-- losing: run
		if (n.hp or 100) < (n.max or 100) * 0.25 and n.arch ~= "police" then
			Mind.say(n, "lose")
			n.conf[key] = nil
			Mind.flee(n, them, 8, false)
			return
		end
		-- the other one is down: gloat and step back
		local downOther = (otherN and otherN.a and Actors.isDown(otherN.a)) or (pl and I.state(pl).hp <= 25)
		if downOther then
			if not c.won then
				c.won = true
				Mind.say(n, "win")
				Actors.emote(a, "point")
			end
			c.level = 2.5
			return
		end
		if now >= c.nextAct then
			c.nextAct = now + range(C.NPC_FIGHT.every)
			Mind.punch(n, key, c)
		end
		if now - c.since > C.NPC_FIGHT.timeout then
			Mind.calm(n, key, 2, "tired")
		end
		return
	end
	-- 1-3: talk it out / threaten; an escalation roll now and then; calm down when ignored
	if level == 3 then
		Actors.pose(a, "fight")
	else
		Actors.pose(a, "")
	end
	if level >= 2 and dist > 4 then
		if now >= c.nextAct then
			c.nextAct = now + 0.8
			Actors.walkTo(a, Routine.nearPoint(me, them, 3.2), (Cast.ARCH[n.arch] or Cast.ARCH.citizen).walk * 1.3, true)
		end
	else
		Actors.stop(a)
	end
	if now - c.said > range({ 3.5, 5.5 }) then
		c.said = now
		Mind.say(n, LEVEL_SIT[level] or "complain")
		Actors.emote(a, if level >= 2 then "point" else "shake")
		if level >= 2 and c.inc then
			c.inc.tLast = now
		end
	end
	local quiet = now - c.t
	if level == 3 then
		-- fight or back down
		if n.mood.fear > T.courage + 0.15 then
			Mind.retreat(n, key, "retreat")
			return
		end
		if quiet > 3 and T.aggression * (0.5 + n.mood.anger) > 0.55 and rnd:NextNumber() < 0.35 then
			c.level = 4
			c.since = now
			c.said = 0
			Mind.say(n, "fight_start")
			incidentFor(n, key, c)
		elseif quiet > 9 then
			Mind.calm(n, key, 1, "cooled")
		end
	elseif level == 2 then
		if quiet > 4 and T.temper * n.mood.anger > 0.35 and rnd:NextNumber() < 0.25 then
			c.level = 3
			c.t = now
			c.said = 0
			incidentFor(n, key, c)
		elseif quiet > 10 then
			Mind.calm(n, key, 1, "cooled")
		end
	elseif level == 1 and quiet > 6 then
		Mind.calm(n, key, 1, "cooled")
	end
end

local function watchStep(n: any, now: number)
	local inc = n.watchInc
	if not inc or inc.status == "resolved" or (n.modeUntil > 0 and now > n.modeUntil) then
		n.watchInc = nil
		Mind.toRoutine(n, 1)
		return
	end
	local me = Actors.pos(n.a)
	local focus = World.posOf(inc.aggressor, inc.pos) or inc.pos
	Actors.face(n.a, focus)
	if n.mode == "intervene" then
		local d = (me - focus).Magnitude
		if d < 6 and not n.intervened then
			n.intervened = true
			Mind.say(n, "intervene")
			Actors.emote(n.a, "stop_hand")
			-- the fighters may listen (an NPC fighter with low anger calms down)
			local ag = Mind.byKey(inc.aggressor)
			local vk = inc.victim
			if ag and vk and ag.conf[vk] and ag.mood.anger < 0.7 and rnd:NextNumber() < 0.5 then
				Mind.calm(ag, vk, 2, "stopped")
			elseif ag and vk and rnd:NextNumber() < 0.25 then
				-- the peacemaker gets dragged in
				Mind.provoke(ag, Mind.myKey(n), 2, "meddling", "self")
			end
			n.modeUntil = now + 6
		end
		return
	end
	if now - (n.lastSay or 0) > range({ 7, 12 }) and rnd:NextNumber() < 0.45 then
		Mind.say(n, "watch_comment", World.describe(inc))
	end
	-- the curious drift closer, the cautious keep their distance
	local d = (me - focus).Magnitude
	local want = if n.mood.fear > 0.4 then 20 else 13
	if math.abs(d - want) > 5 and not Actors.moving(n.a) then
		Actors.walkTo(n.a, Routine.nearPoint(me, focus, want), (Cast.ARCH[n.arch] or Cast.ARCH.citizen).walk)
	end
end

local function downStep(n: any, now: number)
	if Actors.isDown(n.a) then
		return
	end
	local after = n.downThen or "routine"
	local key = n.downKey
	n.downThen, n.downKey = nil, nil
	if after == "fight" and key then
		Mind.setMode(n, "conflict")
		local c = confOf(n, key)
		c.level = math.max(c.level, 4)
		Mind.say(n, "fight_start")
	elseif after == "flee" then
		Mind.flee(n, World.posOf(key or ""), 9, true)
		Mind.say(n, "flee_scream")
	elseif after == "cower" then
		Mind.cower(n, 4, "cower")
	elseif Mind.topConflict(n) then
		Mind.setMode(n, "conflict")
	else
		Mind.toRoutine(n, 1)
	end
end

local function talkStep(n: any, now: number)
	local p = n.talkWith and Players:GetPlayerByUserId(n.talkWith)
	local f = p and I.feetOf(p)
	local me = Mind.pos(n)
	if not p or not f or not me or (f - me).Magnitude > 16 or now - (n.talkT or 0) > 25 then
		if p and f and me and (f - me).Magnitude > 16 then
			Mind.say(n, "talk_tired")
		end
		n.talkWith = nil
		Mind.toRoutine(n, 0.5)
		return
	end
	Actors.stop(n.a)
	Actors.face(n.a, f)
	Mind.lookAt(n, "p:" .. p.UserId)
end

---------------------------------------------------------------------------------------------------
-- ambient awareness of players (near LOD): bumps, following, greetings, archetype initiatives
---------------------------------------------------------------------------------------------------
local function ambient(n: any, now: number)
	local me = Mind.pos(n)
	if not me then
		return
	end
	for _, p in Players:GetPlayers() do
		local f = I.feetOf(p)
		local st = I.state(p)
		if f and not st.busy then
			local key = "p:" .. p.UserId
			local d = Vector3.new(f.X - me.X, 0, f.Z - me.Z).Magnitude
			local per = n.seen[p.UserId]
			if not per then
				per = { near = 0, close = 0, bumpT = 0, greetT = -1e9, followT = 0, away = true, awayT = -1e9 }
				n.seen[p.UserId] = per
			end
			-- a "meeting" starts when you come back after being away (out of sight range) for a while
			if d > 22 then
				if not per.away then
					per.away = true
					per.awayT = now
				end
			end
			-- walked into: a light bump
			if d < 1.7 and math.abs(f.Y - me.Y) < 4 and now - per.bumpT > 6 then
				per.bumpT = now
				local rec = Memory.get(p, n.id)
				Memory.event(p, n.id, "bump")
				if n.mode == "routine" or n.mode == "talk" then
					local tier = Memory.tier(rec)
					if n.arch == "fool" then
						Mind.say(n, "prank")
						Actors.emote(n.a, "laugh")
					elseif tier == "friend" or tier == "friendly" then
						Mind.say(n, "greet_friend")
					else
						Mind.provoke(n, key, if n.arch == "thug" or n.arch == "drunk" then 1.6 else 1, "bump", "other")
						Mind.say(n, "bump_complain")
					end
				end
			end
			-- following: a player stays within 4.5 studs of a walking NPC for a while
			if d < 4.5 and Actors.moving(n.a) and n.mode == "routine" then
				per.followT += 0.25
				if per.followT > 10 then
					per.followT = 0
					Memory.event(p, n.id, "follow")
					Mind.feel(n, { patience = -15 })
					if n.patience < 40 or n.arch == "thug" then
						Mind.provoke(n, key, if n.arch == "thug" then 2 else 1, "follow", "self")
					end
					Mind.say(n, "follow_annoyed")
				end
			else
				per.followT = math.max(0, per.followT - 0.5)
			end
			-- first sight this meeting (back after 40 s+ away): those who remember you say so
			local newMeeting = per.away and now - per.awayT > 40 and now - per.greetT > 90
			if d < 9 and (n.mode == "routine" or n.mode == "recover") and newMeeting and World.canSee(n, f, 12) then
				per.greetT = now
				per.away = false
				local rec = Memory.peek(p, n.id)
				if rec and rec.met > 0 then
					if (rec.helped > 0 or rec.gifts > 0) and Memory.tier(rec) ~= "enemy" then
						Mind.faceKey(n, key)
						Mind.say(n, "remember_helped")
						Actors.emote(n.a, "wave")
						-- the homeless who were helped may ask a small favour (once in a while)
						if n.arch == "homeless" and os.time() - (rec.favorAsked or 0) > 600 then
							rec.favorAsked = os.time()
							n.favorFor = p.UserId
							task.delay(3, function()
								if n.present and n.mode == "routine" then
									Mind.say(n, "favor_ask")
								end
							end)
						end
					elseif rec.hurt > 0 or rec.robbed > 0 then
						Mind.faceKey(n, key)
						Mind.say(n, "remember_hurt")
						if n.arch == "thug" then
							Mind.provoke(n, key, 2, "grudge", "self")
						elseif rec.fear > 30 then
							Mind.flee(n, f, 5, false)
						end
					elseif Memory.tier(rec) == "friend" or Memory.tier(rec) == "friendly" then
						Mind.say(n, "greet_friend")
						Actors.emote(n.a, "wave")
					end
				end
			end
			if d < 9 and per.away and not newMeeting then
				per.away = false -- (only a short step away: the same meeting goes on)
			end
			-- archetype initiatives
			if n.mode == "routine" and now >= (n.initiativeT or 0) then
				Routine.initiative(n, p, d, now)
			end
		end
	end
end

-- two NPCs who meet share news (gossip), now and then
local function gossip(n: any, now: number)
	if n.traits.sociability < 0.4 or now < (n.gossipT or 0) then
		return
	end
	n.gossipT = now + range({ 12, 25 })
	local inc, info = World.recentKnown(n, 300)
	if not inc then
		return
	end
	local me = Mind.pos(n)
	for _, o in npcs do
		if o ~= n and o.present and o.mode == "routine" and not o.knows[inc.id] and o.arch ~= "police" then
			local op = Mind.pos(o)
			if op and (op - me).Magnitude < 6 then
				Mind.say(n, "gossip", World.describe(inc, info))
				Actors.face(n.a, op)
				Actors.face(o.a, me)
				World.tell(n, o, inc)
				return
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- the scheduler
---------------------------------------------------------------------------------------------------
local function lodOf(n: any): (string, number)
	local me = Mind.pos(n)
	if not me then
		return "far", math.huge
	end
	local best = math.huge
	for _, p in Players:GetPlayers() do
		local f = I.feetOf(p)
		if f then
			best = math.min(best, (f - me).Magnitude)
		end
	end
	if best < 90 then
		return "near", best
	elseif best < 220 then
		return "mid", best
	end
	return "far", best
end

local INTERVAL = { near = 0.25, mid = 0.9, far = 3 }

local function think(n: any, now: number)
	Routine.schedule(n, now)
	if not n.present or not n.a or n.a.gone then
		return
	end
	n.lod, n.playerDist = lodOf(n)
	Actors.setAttr(n.a, "GiLod", n.lod)
	-- mood drifts back to the person's baseline; patience regrows
	local dt = now - (n.lastThink or now)
	n.lastThink = now
	local base = (n.def.mood and n.def.mood.valence) or 0
	n.mood.v += (base - n.mood.v) * math.min(1, dt * 0.02)
	n.mood.anger = math.max(0, n.mood.anger - dt * 0.012)
	n.mood.fear = math.max(0, n.mood.fear - dt * 0.02)
	n.patience = math.min(n.traits.patience * 100, n.patience + dt * 0.6)
	if n.hp < n.max and not Mind.topConflict(n) then
		n.hp = math.min(n.max, n.hp + dt * 0.5)
		n.a.hp = n.hp
	end
	n.drunk = Routine.drunkLevel(n)
	local mode = n.mode
	if mode == "down" then
		downStep(n, now)
	elseif mode == "conflict" then
		conflictStep(n, now)
	elseif mode == "flee" or mode == "cower" or mode == "dodge" or mode == "recover" or mode == "embarrassed" then
		if n.modeUntil > 0 and now > n.modeUntil then
			if mode == "embarrassed" then
				Routine.embarrassedEnd(n)
			end
			local inc = n.fleeInc or n.victimInc
			n.victimInc = nil
			if mode == "flee" and inc and inc.status ~= "resolved" and not inc.report and n.traits.civic > 0.35 and Police then
				Mind.report(n, inc)
			else
				Mind.toRoutine(n, if mode == "flee" then range({ 1.5, 3 }) else 0)
				if mode == "flee" then
					Mind.say(n, if n.mood.fear > 0.4 then "idle_grumpy" else "idle_mutter")
				end
			end
		end
	elseif mode == "watch" or mode == "intervene" then
		watchStep(n, now)
	elseif mode == "talk" then
		talkStep(n, now)
	elseif mode == "police" then
		if Police then
			Police.copStep(n, now)
		end
	elseif mode == "routine" then
		Routine.step(n, now)
	end
	if n.lod == "near" and n.present then
		ambient(n, now)
		if n.mode == "routine" then
			gossip(n, now)
		end
	end
	-- conflicts with people who left
	for key, c in n.conf do
		if c.level < 1 or (now - c.t > 90 and n.mode ~= "conflict") then
			n.conf[key] = nil
		end
	end
	Mind.sync(n)
end

local doorT = 0
function Mind.loop()
	local now = os.clock()
	if now >= doorT then
		doorT = now + 0.25
		pcall(I.Places.doorTick)
	end
	for _, n in npcs do
		if now >= n.nextThink then
			local ok, err = pcall(think, n, now)
			if not ok then
				warn("[GwangalliCity] " .. n.id .. ": " .. tostring(err))
			end
			n.nextThink = now + (INTERVAL[n.lod] or 1) + rnd:NextNumber() * 0.1
		end
	end
end

-- a record that is not in the Cast (police responders): removed again with Mind.removeTemp
function Mind.addTemp(def: any): any
	local arch = Cast.ARCH[def.arch] or Cast.ARCH.citizen
	local n = {
		id = def.id,
		def = def,
		name = def.name,
		arch = def.arch,
		style = def.style,
		traits = def.traits,
		mood = { v = 0, anger = 0, fear = 0 },
		patience = def.traits.patience * 100,
		drunk = 0,
		hp = arch.hp,
		max = arch.hp,
		mode = "police",
		modeT = os.clock(),
		modeUntil = 0,
		conf = {},
		knows = {},
		seen = {},
		present = false,
		temp = true,
		nextThink = os.clock(),
		lod = "near",
		lastSay = 0,
		recentLines = {},
	}
	npcs[def.id] = n
	return n
end

function Mind.removeTemp(n: any)
	if npcs[n.id] == n then
		npcs[n.id] = nil
	end
	if n.a then
		Actors.remove(n.a)
		n.a = nil
	end
	n.present = false
end

function Mind.onLeave(player: Player)
	local key = "p:" .. player.UserId
	for _, n in npcs do
		n.conf[key] = nil
		n.seen[player.UserId] = nil
		if n.talkWith == player.UserId then
			n.talkWith = nil
			if n.mode == "talk" then
				Mind.toRoutine(n)
			end
		end
	end
end

function Mind.init(interact: any)
	I = interact
	C = I.C
	Cast = I.Cast
	Actors = I.Actors
	World = I.World
	Talk = I.Talk
	Memory = I.Memory
	Routine = I.Routine
	Police = I.Police
	for _, def in Cast.LIST do
		local arch = Cast.ARCH[def.arch] or Cast.ARCH.citizen
		npcs[def.id] = {
			id = def.id,
			def = def,
			name = def.name,
			arch = def.arch,
			style = def.style,
			traits = def.traits,
			mood = { v = (def.mood and def.mood.valence) or 0, anger = 0, fear = 0 },
			patience = def.traits.patience * 100,
			drunk = def.drunkBase or 0,
			hp = arch.hp,
			max = arch.hp,
			mode = "routine",
			modeT = 0,
			modeUntil = 0,
			conf = {},
			knows = {},
			seen = {},
			present = false,
			nextThink = os.clock() + rnd:NextNumber() * 2,
			lod = "far",
			lastSay = 0,
			recentLines = {},
		}
	end
end

return Mind
