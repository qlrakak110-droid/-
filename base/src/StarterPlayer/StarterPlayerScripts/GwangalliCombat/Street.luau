-- GwangalliCombat/Street (client, cosmetic): how the client-side crowd (GwangalliStreetLife) reacts to violence.
-- Pedestrians exist only on this client, so all of this is local; the server only hears "report" (a witness phoned
-- the police) and "streetHit" (a pedestrian fighting back landed a punch), both validated and rate-limited there.
--   * Street.candidates(r)   punchable pedestrians around the local player (standing or staggering)
--   * Street.onHit(p)        our punch landed on a pedestrian: flinch / stagger / knockdown / KO (lies NPC_KO_TIME s),
--                            a victim line; violent people fight back
--   * Street.onAlarm(p)      ONE O(N) sweep around p.pos: most witnesses run away (and despawn GTA-style), 1-2 film
--                            with their phone, one calls 112 ("여보세요, 경찰이죠?" + FireServer("report") once per
--                            alarm on the attacker's client), some cower first; violent ones near the attacker
--                            (only when that is the local player) chase and punch (FireServer("streetHit"), cadence
--                            >= 0.9 s, give up after ~8 s)
-- It drives the StreetLife modules directly (same require cache as the boot script: Crowd / Agent / Anim / NavWorld /
-- SocialUI, found BY CLASS like the boot does) and adds "alarm" / "combatHit" to Crowd.api (LocalPlayer.
-- GwangalliStreetAPI). Per-agent overrides (think / react / bump / endIdle / nextSegment / stepKnock / afterKnock)
-- are instance fields that shadow the Agent methods for the duration of a reaction, so the 2.7k-line modules stay
-- untouched. Every guard of the crowd is honoured: gone / fading / done / club guests / companions / riding /
-- dodging / already knocked. Budget: one pass per alarm (N <= cap), decisions at the agents' own think rate.

local Players = game:GetService("Players")

local Street = {}

local ctx: any
local Combat: any
local CA: any
local Bump: any
local Social: any
local CFG: any
local player: Player

local SL: any = nil -- { Crowd, Agent, Anim, World, SocialUI }
local rng = Random.new()
local function rnd(): number
	return rng:NextNumber()
end

local FIGHT_TIME = 8 -- s a pedestrian keeps fighting before giving up
local FIGHT_REACH = 2.7 -- studs: close enough to swing
local FIGHT_STOP = 1.9 -- studs: where a chaser stops in front of the player
local MAX_FIGHTERS = 2
local FLEE_SPEED = { 12.5, 14.5 }

local fighters: { [any]: boolean } = {}
local tracked: { [any]: number } = {} -- agents whose rig we flagged GwEmuFK (cleared when they are gone)
local lastReport = -1e9
local lastAlarm = { pos = nil :: Vector3?, at = -1e9 }

local function yawOf(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

local function noop() end

local function speechOf(a: any): string
	return (a.c and a.c.speech) or "std"
end

local function say(a: any, text: string?, dur: number?)
	if text and SL and SL.SocialUI and not a.gone then
		pcall(SL.SocialUI.say, a, text, dur or 3)
	end
end

local function typeLine(a: any, kind: string): string?
	if Social and type(Social.typeLine) == "function" then
		local ok, l = pcall(Social.typeLine, a.type, kind, speechOf(a))
		if ok then
			return l
		end
	end
	return nil
end

-- emulator only (real Roblox ignores it): render this rig's Motor6D pose (punches, phone at the ear, cowering)
local function markFK(a: any)
	if tracked[a] then
		return
	end
	tracked[a] = os.clock()
	pcall(function()
		a.rig.model:SetAttribute("GwEmuFK", true)
	end)
end

-- can this agent take part in a reaction right now?
local function available(a: any): boolean
	return not a.gone and not a.fadeAt and not a.done and not a.clubGuest and not a.companion and not a.riding and not a.knock and a.mode ~= "dodge" and a.mode ~= "follow" and a.rig ~= nil and a.rig.model.Parent ~= nil
end

local function playerDown(): boolean
	local ch = player.Character
	if Bump and type(Bump.isDown) == "function" and Bump.isDown() then
		return true
	end
	return ch ~= nil and ch:GetAttribute("GwangalliKnocked") == true
end

-- the player can be chased / punched by a pedestrian right now
local function fightAllowed(): boolean
	local ch, hum = ctx.character()
	if not ch or not hum or hum.Health <= 0 or hum.Sit or hum.SeatPart then
		return false
	end
	if ch:GetAttribute(Combat.Attr.KO) == true or player:GetAttribute(Combat.Attr.Arrested) == true then
		return false
	end
	local pose = ch:GetAttribute(Combat.Attr.Pose)
	if type(pose) == "string" and pose ~= "" then
		return false
	end
	if SL.Crowd.playerInDialog and SL.Crowd.playerInDialog() then
		return false
	end
	return true
end

-- the common entry of every reaction: out of talk / chat / queue / group / seat, flashes and gestures dropped,
-- the schedule kept away while it lasts
local function prepare(a: any, now: number)
	pcall(function()
		if a.mode == "talk" then
			a:endTalk(now)
		end
		if a.chatState then
			a:endChat(now, false)
		end
	end)
	if a.chase and not a.gwFight then
		a.chase = nil
	end
	a:releasePoi()
	local Q = SL.Crowd.queue
	if Q and type(Q.leave) == "function" then
		pcall(Q.leave, a)
	end
	if a.leader then
		SL.Crowd.detachMember(a)
	end
	if a.members and #a.members > 0 then
		SL.Crowd.dissolve(a)
	end
	a.sitting, a.lying, a.napping = false, false, false
	if a.sitGround then
		a.sitGround = false
		SL.Anim.legs(a.rig, nil)
	end
	SL.Anim.cancelFlash(a.rig)
	pcall(SL.Anim.stopGesture, a.rig)
	a.nudgeTX, a.nudgeTZ, a.nudgeUntil = 0, 0, 0
	a.nextSchedule = now + 30
	a.react = noop
	a.moved = true
end

-------------------------------------------------------------------------------------------------
-- fleeing: run away and despawn (the "leave" plan ends with done = true; Crowd fades / removes)
-------------------------------------------------------------------------------------------------
-- while panicking nobody waits for the green man
local function fleeNextSegment(self: any, now: number): boolean
	local kind, v, e = self:pickNext()
	if kind == nil then
		self:arrive(now)
		return false
	end
	if kind == "point" then
		self:segTo(v, nil, nil)
		self.node = nil
		return true
	end
	self:segTo(SL.World.pos[v], e, v)
	return true
end

local function flee(a: any, threat: Vector3, now: number, fromLocal: boolean, scream: boolean?)
	if a.gone then
		return
	end
	prepare(a, now)
	a.walkPose = nil
	a.yaw = yawOf(a.pos.X - threat.X, a.pos.Z - threat.Z) -- the random walk keeps its heading: away
	a.node = SL.World.nearest(a.pos, 40)
	a.prev = nil
	a.plan = { kind = "leave", act = "walk", door = false }
	a.nextSegment = fleeNextSegment
	a.endIdle = nil
	local opts: any = { crossW = 0.05, sandW = 0.6 }
	if fromLocal then
		opts.away = threat -- (Agent.pickNext keeps it on the local player, which is the threat here)
	end
	a.gwReact = { kind = "flee", untilT = now + 30, sev = 3 }
	a:startNav({ mode = "random", steps = 16 + math.floor(rnd() * 10), opts = opts }, now, FLEE_SPEED[1] + rnd() * (FLEE_SPEED[2] - FLEE_SPEED[1]))
	SL.Anim.flash(a.rig, "startle", 0.7)
	if scream then
		say(a, Combat.line("witness", nil, speechOf(a)), 2.4)
	end
end

-- after an idle reaction (calling, cowering): run instead of the default plan logic
local function fleeAfterIdle(threat: Vector3, fromLocal: boolean)
	return function(self: any, now: number)
		self.endIdle = nil
		self.sitting, self.lying = false, false
		SL.Anim.setRestPose(self.rig, nil)
		if self.rig.phone then
			self.rig.phone.Transparency = 1
		end
		flee(self, threat, now, fromLocal, false)
	end
end

-------------------------------------------------------------------------------------------------
-- witnesses: film / call / cower / look
-------------------------------------------------------------------------------------------------
local function film(a: any, pos: Vector3, now: number, sev: number)
	prepare(a, now)
	markFK(a)
	a.endIdle = nil
	a.gwReact = { kind = "film", untilT = now + 12, sev = sev }
	a:setPlan({ kind = "film", act = "photo", dur = 6 + rnd() * 4, faceYaw = yawOf(pos.X - a.pos.X, pos.Z - a.pos.Z), resume = { kind = "leave", act = "walk", door = false } }, now)
	SL.Anim.setRestPose(a.rig, "photo")
	if rnd() < 0.6 then
		task.delay(0.4 + rnd() * 0.8, function()
			say(a, Combat.line("film"), 2.6)
		end)
	end
end

local function callPolice(a: any, pos: Vector3, now: number, sev: number, fromLocal: boolean)
	prepare(a, now)
	markFK(a)
	a.gwReact = { kind = "call", untilT = now + 9, sev = sev }
	a.plan = { kind = "gwreact", resume = { kind = "leave", act = "walk", door = false } }
	a:idleFor("gwcall", 5.5 + rnd() * 1.5, now, yawOf(pos.X - a.pos.X, pos.Z - a.pos.Z))
	SL.Anim.setRestPose(a.rig, "phonecall")
	if a.rig.phone then
		a.rig.phone.Transparency = 0
	end
	-- after the call: walk off (the default event-plan resume), not run: they are on the phone
	a.endIdle = function(self: any, t: number)
		self.endIdle = nil
		if self.rig.phone then
			self.rig.phone.Transparency = 1
		end
		self.nextSegment = fleeNextSegment
		SL.Agent.endIdle(self, t)
	end
	task.delay(0.5, function()
		if not a.gone then
			say(a, Combat.line("call", nil, speechOf(a)), 4.5)
		end
	end)
	if fromLocal and now - lastReport > 6 then
		lastReport = now
		ctx.fire("report", { id = a.id, pos = Combat.packV(a.pos) })
	end
end

local function cower(a: any, pos: Vector3, now: number, sev: number, fromLocal: boolean)
	prepare(a, now)
	markFK(a)
	a.gwReact = { kind = "cower", untilT = now + 6, sev = sev }
	a.plan = { kind = "gwreact", resume = { kind = "leave", act = "walk", door = false } }
	a:idleFor("gwcower", 2.2 + rnd() * 1.6, now, yawOf(pos.X - a.pos.X, pos.Z - a.pos.Z))
	SL.Anim.setRestPose(a.rig, "cower")
	SL.Anim.look(a.rig, 0, -0.45)
	a.endIdle = fleeAfterIdle(pos, fromLocal)
	if rnd() < 0.5 then
		say(a, Combat.line("witness", nil, speechOf(a)), 2.4)
	end
end

-- not involved enough to act: a long look, maybe a line, then on with the day (walking away a little later)
local function watch(a: any, pos: Vector3, now: number, line: boolean)
	a.lookUntil = now + 3
	pcall(a.lookAtPoint, a, pos, 3, now)
	if a.mode == "walk" then
		a.pauseUntil = now + 0.8 + rnd() * 0.6
	end
	if line then
		say(a, typeLine(a, "witness") or Combat.line("witness", nil, speechOf(a)), 2.6)
	end
end

-------------------------------------------------------------------------------------------------
-- fighting back (violent pedestrians, only against the LOCAL player)
-------------------------------------------------------------------------------------------------
local fightThink: (self: any, now: number) -> ()

local function fightStep(a: any, now: number, pp: Vector3)
	local dx, dz = pp.X - a.pos.X, pp.Z - a.pos.Z
	local d = math.max(0.05, math.sqrt(dx * dx + dz * dz))
	local stop = math.min(FIGHT_STOP, d)
	local target = Vector3.new(pp.X - dx / d * stop, a.pos.Y, pp.Z - dz / d * stop)
	a.nav = { mode = "points", pts = { target }, i = 1 }
	a.mode = "walk"
	a.faceYaw = nil
	a.pauseUntil = 0
	a.want = (Bump and Bump.VIOLENT and Bump.VIOLENT.chaseSpeed) or 11.5
	a:segTo(target, nil, nil)
	a.node = nil
	a.gwFight.retarget = now + 0.3
end

local function endFight(a: any, now: number, why: string)
	local f = a.gwFight
	a.gwFight = nil
	fighters[a] = nil
	if a.chase == f then
		a.chase = nil
	end
	a.think = nil
	a.bump = nil
	a.react = noop
	if a.gone then
		return
	end
	a.want, a.speed, a.nav = 0, 0, nil
	a.node = SL.World.nearest(a.pos, 40)
	a.prev = nil
	SL.Anim.setRestPose(a.rig, nil)
	local pp = SL.Crowd.playerPos()
	if why == "giveup" or why == "lost" then
		say(a, typeLine(a, "giveup") or typeLine(a, "bumped"), 3)
	end
	-- a glare, then walk off (the event-plan resume)
	a.plan = { kind = "gwreact", resume = { kind = "leave", act = "walk", door = false } }
	a.gwReact = { kind = "done", untilT = now + 10, sev = 3 }
	a:idleFor("idle", 1.4 + rnd() * 1.2, now, if pp then yawOf(pp.X - a.pos.X, pp.Z - a.pos.Z) else nil)
	a.lookUntil = now + 2
end

local function fighterSwing(a: any, f: any, now: number)
	f.combo = (f.combo % 3) + 1
	local pose = if f.combo == 2 then "cb_cross" elseif f.combo == 3 then "cb_hook" else "cb_jab"
	SL.Anim.flash(a.rig, pose, 0.34)
	f.nextHit = now + (CFG.STREET_HIT and CFG.STREET_HIT.rate or 0.9) + 0.08 + rnd() * 0.45
	local root = a.rig.root
	ctx.fire("streetHit", { id = a.id, pos = Combat.packV(if root then root.Position else a.pos), combo = f.combo })
	if rnd() < 0.25 then
		say(a, Combat.line("fightback", nil, speechOf(a)), 2)
	end
end

fightThink = function(self: any, now: number)
	local f = self.gwFight
	if self.gone or not f then
		self.think = nil
		return
	end
	local st = self.rig.anim
	if st and st.flashUntil then
		SL.Anim.tick(self.rig, now)
	end
	if self.knock then
		return -- stepKnock runs the fall; afterKnock (ours) resumes the fight
	end
	local pp = SL.Crowd.playerPos()
	if not pp or now > f.untilT or SL.Crowd.playerSeated() or not fightAllowed() then
		endFight(self, now, "giveup")
		return
	end
	local dx, dz = pp.X - self.pos.X, pp.Z - self.pos.Z
	local d = math.sqrt(dx * dx + dz * dz)
	if d > 30 or math.abs(pp.Y - self.pos.Y) > 6 then
		endFight(self, now, "lost")
		return
	end
	self.lookUntil = now + 1
	if d <= FIGHT_REACH then
		local yaw = yawOf(dx, dz)
		if self.mode ~= "idle" then
			self.want, self.speed, self.nav = 0, 0, nil
			self:idleFor("gwfight", 3, now, yaw)
			SL.Anim.setRestPose(self.rig, "cb_guard")
		else
			self.faceYaw = yaw
			self.idleUntil = now + 3
		end
		if now >= f.nextHit and not playerDown() then
			fighterSwing(self, f, now)
		end
	elseif now >= f.retarget or self.mode ~= "walk" then
		SL.Anim.setRestPose(self.rig, nil)
		fightStep(self, now, pp)
	end
	self:updateWalkAnim()
end

local function startFight(a: any, now: number): boolean
	if a.gone or a.riding or a.clubGuest or a.companion or a.gwFight then
		return false
	end
	local n = 0
	for o in fighters do
		if o.gone then
			fighters[o] = nil
		else
			n += 1
		end
	end
	if n >= MAX_FIGHTERS or not fightAllowed() then
		return false
	end
	local pp = SL.Crowd.playerPos()
	if not pp then
		return false
	end
	prepare(a, now)
	markFK(a)
	local f = { untilT = now + FIGHT_TIME, nextHit = now + 0.7 + rnd() * 0.3, retarget = 0, combo = 0, started = now }
	a.gwFight = f
	a.chase = f -- the crowd steps chasers every frame and thinks at 5 Hz; Agent.arrive idles a chaser
	a.think = fightThink
	a.bump = noop -- no startled nudge while trading punches
	a.walkPose = nil
	a.endIdle = nil
	a.plan = { kind = "wander", act = "walk", center = a.pos, radius = 120 }
	a.gwReact = { kind = "fight", untilT = now + FIGHT_TIME + 2, sev = 3 }
	fighters[a] = true
	say(a, Combat.line("fightback", nil, speechOf(a)) or typeLine(a, "chase"), 2.6)
	local dx, dz = pp.X - a.pos.X, pp.Z - a.pos.Z
	if math.sqrt(dx * dx + dz * dz) > FIGHT_REACH then
		fightStep(a, now, pp)
	else
		a:idleFor("gwfight", 3, now, yawOf(dx, dz))
		SL.Anim.setRestPose(a.rig, "cb_guard")
	end
	return true
end

-------------------------------------------------------------------------------------------------
-- victims (our punch landed): the knock timeline with a longer KO hold, then fight back or run
-------------------------------------------------------------------------------------------------
local function gwStepKnock(self: any, _dt: number, now: number)
	local kn = self.knock
	if not kn or not Bump then
		self.knock = nil
		return
	end
	local t = now - kn.t0
	local hold = kn.gwHold or 0
	if hold > 0 and kn.outcome == "knockdown" then
		local downAt = Bump.FALL_DUR + 0.35
		if t > downAt then
			t = math.max(downAt, t - hold)
		end
	end
	local phase, k = Bump.knockPhase(t, kn.outcome)
	kn.k = k
	self.moved = true
	if phase ~= kn.phase then
		kn.phase = phase
		if phase == "getup" then
			SL.Anim.setRestPose(self.rig, "stagger")
		elseif phase == "done" then
			self:afterKnock(now)
		end
	end
end

local function gwAfterKnock(self: any, now: number)
	self.stepKnock = nil
	self.afterKnock = nil
	local kn = self.knock
	self.knock = nil
	SL.Anim.setRestPose(self.rig, nil)
	self.node = SL.World.nearest(self.pos, 40)
	self.prev = nil
	if self.gone then
		return
	end
	local ko = kn and kn.gwHold ~= nil
	local f = self.gwFight
	if f and not ko and now < f.untilT and fightAllowed() then
		-- back on the feet mid-fight: straight back at it
		self.chase = f
		f.retarget = 0
		return
	elseif f then
		endFight(self, now, "down")
		return
	end
	if self.type == "violent" and not ko and self.gwWantsFight and startFight(self, now) then
		return
	end
	-- everyone else gets away from the attacker
	say(self, typeLine(self, "down"), 2.6)
	local pp = SL.Crowd.playerPos() or self.pos
	flee(self, pp, now, true, false)
end

local PUK = { "퍽!", "퍽!!", "윽!" }

-- our punch landed on pedestrian `id` (server "hit", target "street")
function Street.onHit(p: any)
	local id = p.id
	if type(id) ~= "string" then
		return
	end
	local outcome = p.outcome
	local dx, dz = tonumber(p.dx) or 0, tonumber(p.dz) or 0
	local a = SL and SL.Crowd.byId[id]
	if not a or a.gone then
		-- no direct access (or already gone): the public API still plays the knock
		if outcome ~= "hit" then
			ctx.street("knock", id, dx, dz, if outcome == "stagger" then "stagger" else "knockdown", if outcome == "stagger" then "퍽!" else "퍼억!!")
		end
		return
	end
	local now = os.clock()
	markFK(a)
	a.gwVictimAt = now
	a.gwWantsFight = a.type == "violent"
	local puk = if outcome == "hit" then PUK[math.random(1, #PUK)] elseif Social and Social.KNOCK_PUK and outcome ~= "stagger" then Social.KNOCK_PUK[math.random(1, #Social.KNOCK_PUK)] else "퍽!"
	if outcome == "hit" then
		if a.knock then
			return -- already falling: the number is enough
		end
		SL.Anim.flash(a.rig, "cb_flinch", 0.45)
		pcall(a.nudge, a, a.nudgeX + dx * 0.9, a.nudgeZ + dz * 0.9, 0.8, 8)
		if a.mode == "walk" then
			a.pauseUntil = now + 0.7
		end
		local pp = SL.Crowd.playerPos()
		if pp then
			pcall(a.lookAtPoint, a, pp, 2.5, now)
		end
		if Bump then
			local pool = Bump.bubbles({ types = Social and Social.TYPES })
			if pool and a.rig.root then
				pcall(pool.say, pool, a.rig.root, puk, "plain", 0.9, 2.1 * (a.scale or 1) + 1.6)
			end
		end
		task.delay(0.35, function()
			if a.gone or a.knock then
				return
			end
			if a.type == "violent" then
				if not a.gwFight then
					startFight(a, os.clock())
				end
			elseif not a.gwFight and not (a.gwReact and a.gwReact.kind == "flee") then
				say(a, Combat.line("victim", nil, speechOf(a)), 2.4)
				-- a plain victim backs off at once (others run on the alarm)
				if rnd() < 0.7 then
					flee(a, SL.Crowd.playerPos() or a.pos, os.clock(), true, false)
				end
			end
		end)
		return
	end
	-- stagger / knockdown / ko: the shared 어깨빵 fall timeline (root CFrame: renders everywhere)
	local kind = if outcome == "stagger" then "stagger" else "knockdown"
	if a.knock then
		if a.knock.outcome == "stagger" and kind == "knockdown" then
			a.knock = nil -- a stagger turns into a fall
		else
			return
		end
	end
	if a.gwFight and a.chase == a.gwFight then
		a.chase = nil -- (knockDown clears it anyway; afterKnock puts it back)
	end
	local ok = a:knockDown(dx, dz, kind, puk)
	if ok == false or not a.knock then
		return
	end
	if outcome == "ko" then
		a.knock.gwHold = CFG.NPC_KO_TIME or 5
	end
	a.stepKnock = gwStepKnock
	a.afterKnock = gwAfterKnock
	if outcome ~= "stagger" or rnd() < 0.5 then
		task.delay(0.5, function()
			say(a, Combat.line("victim", nil, speechOf(a)), 2.4)
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- the alarm sweep
-------------------------------------------------------------------------------------------------
type Cand = { a: any, d: number }
local cands: { Cand } = {}

function Street.alarm(pos: Vector3, radius: number?, severity: number?, victimId: string?, fromLocal: boolean?): number
	if not SL or typeof(pos) ~= "Vector3" then
		return 0
	end
	local now = os.clock()
	local R = math.clamp(tonumber(radius) or 22, 8, 40)
	local sev = math.clamp(math.floor(tonumber(severity) or 1), 1, 3)
	local localAttacker = fromLocal == true
	-- the same scene again (combo hits): only people not reacting yet are picked up, nobody re-rolls
	local repeatScene = lastAlarm.pos ~= nil and now - lastAlarm.at < 4 and ((lastAlarm.pos :: Vector3) - pos).Magnitude < 10
	lastAlarm.pos, lastAlarm.at = pos, now
	table.clear(cands)
	local R2, G2 = R * R, (R * 1.6) * (R * 1.6)
	for _, a in SL.Crowd.agents do
		if available(a) and not (localAttacker and a.id == victimId) then
			local dx, dz = a.pos.X - pos.X, a.pos.Z - pos.Z
			local d2 = dx * dx + dz * dz
			if d2 <= R2 and math.abs(a.pos.Y - pos.Y) < 10 then
				local r = a.gwReact
				if not r or now >= r.untilT or (r.sev < sev and r.kind ~= "flee" and r.kind ~= "fight") then
					-- insertion by distance (N is small)
					local d = math.sqrt(d2)
					local i = #cands + 1
					while i > 1 and cands[i - 1].d > d do
						cands[i] = cands[i - 1]
						i -= 1
					end
					cands[i] = { a = a, d = d }
				end
			elseif d2 <= G2 and a.near and not a.gwReact then
				pcall(a.lookAtPoint, a, pos, 2.5, now)
			end
		end
	end
	local callers = if repeatScene then 0 elseif localAttacker then 1 else (if rnd() < 0.5 then 1 else 0)
	local filmers = if repeatScene then 0 else (if sev >= 2 then 2 else 1)
	local lines = if repeatScene then 1 else 2
	local fleeP = if sev >= 3 then 1 elseif sev == 2 then 0.85 else 0.65
	local cowerP = if sev >= 2 then 0.3 else 0.15
	local n = 0
	for _, c in cands do
		local a, d = c.a, c.d
		n += 1
		local ok, err = pcall(function()
			if localAttacker and a.type == "violent" and d < 14 and rnd() < 0.7 and startFight(a, now) then
				return
			end
			if callers > 0 and d > 4 and a.type ~= "drunk" and a.type ~= "violent" then
				callers -= 1
				callPolice(a, pos, now, sev, localAttacker)
				return
			end
			if filmers > 0 and d > 6 and d < 20 and a.type ~= "violent" then
				filmers -= 1
				film(a, pos, now, sev)
				return
			end
			if d < 9 and a.type ~= "violent" and rnd() < cowerP then
				cower(a, pos, now, sev, localAttacker)
				return
			end
			if rnd() < fleeP then
				local scream = lines > 0 and rnd() < 0.6
				if scream then
					lines -= 1
				end
				flee(a, pos, now, localAttacker, scream)
				return
			end
			local line = lines > 0
			if line then
				lines -= 1
			end
			watch(a, pos, now, line)
			a.gwReact = { kind = "watch", untilT = now + 4, sev = sev }
		end)
		if not ok then
			ctx.warnOnce("street-alarm", "[GwangalliCombat] alarm: " .. tostring(err))
		end
	end
	table.clear(cands)
	return n
end

-- server "alarm" (FireAllClients): every client sweeps its own crowd
function Street.onAlarm(p: any)
	local pos = Combat.unpackV(p.pos)
	if not pos then
		return
	end
	local fromLocal = tonumber(p.attacker) == player.UserId
	Street.alarm(pos, tonumber(p.radius), tonumber(p.severity), if type(p.victim) == "string" then p.victim else nil, fromLocal)
end

-------------------------------------------------------------------------------------------------
-- queries for the other modules
-------------------------------------------------------------------------------------------------
-- punchable pedestrians within r of the local player: { {id, part} } (standing, walking or staggering)
function Street.candidates(r: number): { any }
	local out = {}
	if SL then
		local pp = SL.Crowd.playerPos()
		if not pp then
			return out
		end
		local r2 = r * r
		for _, a in SL.Crowd.agents do
			if not a.gone and not a.fadeAt and not a.clubGuest and not a.companion and not a.riding and a.rig and a.rig.model.Parent then
				local down = a.sitting or a.lying or a.sitGround or a.napping or (a.knock ~= nil and a.knock.outcome ~= "stagger")
				if not down then
					local dx, dz = a.pos.X - pp.X, a.pos.Z - pp.Z
					if dx * dx + dz * dz <= r2 and a.rig.root then
						table.insert(out, { id = a.id, part = a.rig.root })
					end
				end
			end
		end
		return out
	end
	local near = ctx.street("near", r)
	if type(near) == "table" then
		for _, e in near do
			if type(e) == "table" and type(e.id) == "string" and typeof(e.root) == "Instance" and e.root:IsA("BasePart") and not e.down then
				table.insert(out, { id = e.id, part = e.root })
			end
		end
	end
	return out
end

-- the part a damage number / bubble hangs on for pedestrian `id`
function Street.partOf(id: any): BasePart?
	if SL and type(id) == "string" then
		local a = SL.Crowd.byId[id]
		if a and not a.gone and a.rig then
			return a.rig.head or a.rig.root
		end
	end
	return nil
end

-- server "say" over a pedestrian; false when `id` is not one of ours
function Street.say(id: any, text: string, dur: number?): boolean
	if not SL or type(id) ~= "string" then
		return false
	end
	local a = SL.Crowd.byId[id]
	if not a or a.gone then
		return false
	end
	say(a, text, dur or 3.5)
	return true
end

function Street.ready(): boolean
	return SL ~= nil
end

-- test / debug snapshot: reactions by kind around the player
function Street.stats(): any
	local out = { agents = 0, flee = 0, film = 0, call = 0, cower = 0, fight = 0, watch = 0, knock = 0, done = 0 }
	if not SL then
		return out
	end
	for _, a in SL.Crowd.agents do
		if not a.gone then
			out.agents += 1
			if a.knock then
				out.knock += 1
			end
			local r = a.gwReact
			if r and out[r.kind] ~= nil then
				out[r.kind] += 1
			end
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- attach to GwangalliStreetLife
-------------------------------------------------------------------------------------------------
local function findFolder(): Instance?
	local ps = player:FindFirstChildOfClass("PlayerScripts") or player:WaitForChild("PlayerScripts", 20)
	if not ps then
		return nil
	end
	for _ = 1, 60 do
		for _, c in ps:GetChildren() do
			if c.Name == "GwangalliStreetLife" and c:IsA("Folder") then
				return c
			end
		end
		task.wait(0.5)
	end
	return nil
end

local function attach()
	-- the boot script publishes the API after its modules are initialised
	local api = player:WaitForChild("GwangalliStreetAPI", 90)
	if not api then
		return -- street life is off on this client (missing modules / disabled): nothing to react
	end
	local folder = findFolder()
	if not folder then
		return
	end
	local function req(name: string): any
		local m = folder:FindFirstChild(name)
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok and type(res) == "table" then
				return res
			end
		end
		return nil
	end
	local s = { Crowd = req("Crowd"), Agent = req("Agent"), Anim = req("Anim"), World = req("NavWorld"), SocialUI = req("SocialUI") }
	if not (s.Crowd and s.Agent and s.Anim and s.World and s.SocialUI) or type(s.Crowd.agents) ~= "table" or type(s.Crowd.byId) ~= "table" then
		warn("[GwangalliCombat] GwangalliStreetLife modules unavailable: the crowd will not react to fights")
		return
	end
	-- combat poses for the crowd rigs (CFrame offsets)
	if CA and type(CA.POSE_CF) == "table" and type(s.Anim.POSES) == "table" then
		for name, pose in CA.POSE_CF do
			if s.Anim.POSES[name] == nil then
				s.Anim.POSES[name] = pose
			end
		end
	end
	-- our reaction plans end by themselves and resume (the schedule check waits for them)
	if type(s.Agent.EVENT_PLANS) == "table" then
		s.Agent.EVENT_PLANS.gwreact = true
	end
	-- LocalPlayer.GwangalliStreetAPI: "alarm" (pos, radius, severity, victimId?, fromLocal?) and
	-- "combatHit" (the server "hit" payload) for other client scripts
	if type(s.Crowd.api) == "function" and not s.Crowd.__gwCombat then
		local base = s.Crowd.api
		s.Crowd.__gwCombat = true
		s.Crowd.api = function(method: any, ...: any): any
			if method == "alarm" then
				return Street.alarm(...)
			elseif method == "combatHit" then
				local p = ...
				if type(p) == "table" then
					Street.onHit(p)
					return true
				end
				return false
			end
			return base(method, ...)
		end
	end
	SL = s
	-- housekeeping (2 Hz): fighters that vanished, GwEmuFK flags on rigs that went back to the pool
	task.spawn(function()
		while true do
			task.wait(0.5)
			for a in fighters do
				if a.gone then
					fighters[a] = nil
				end
			end
			for a in tracked do
				if a.gone then
					tracked[a] = nil
					pcall(function()
						a.rig.model:SetAttribute("GwEmuFK", nil)
					end)
				end
			end
		end
	end)
end

function Street.init(c: any)
	ctx = c
	Combat = ctx.Combat
	CA = ctx.CA
	Bump = ctx.Bump
	Social = ctx.Social
	CFG = Combat.CONFIG
	player = Players.LocalPlayer
	task.spawn(function()
		local ok, err = pcall(attach)
		if not ok then
			warn("[GwangalliCombat] street reactions disabled: " .. tostring(err))
		end
	end)
end

return Street
