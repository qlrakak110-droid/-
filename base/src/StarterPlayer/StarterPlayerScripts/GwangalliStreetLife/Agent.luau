-- GwangalliStreetLife/Agent: one pedestrian (named citizen or anonymous passer-by).
--
-- MOVEMENT: the agent walks the GwangalliNav pedestrian graph node by node (keeping right within the
--   edge's clear width, corner-cutting, smoothed heading), off the graph only for the last metres to a
--   POI / queue spot. Where to go next comes from a "nav" strategy:
--     random  direction-persistent random walk inside the plan's area (wandering, jogging, leaving)
--     list    a short A* route (Nav.route) to a POI / a spot
--     flow    next hop toward a citizen area (NavWorld flow field) - schedule transits
--     club    Nav.ped.toClub toward the CLUB OCEAN queue tail - the night flow
--     points  explicit points (queue shuffle, entering the club, hang-out spots)
--   Signalised crosswalks: the agent waits at the kerb until GwangalliShared.pedState says "walk"
--   (never starts on the flashing green) and never steps out in front of a fast car; unsignalised
--   crossings: a short look left / right first.
-- PLANS (GwangalliCitizens.ACT_STYLE.move): wander, spot (bench / cafe / window / towel / photo spot /
--   bus stop: sit, eat, look, sunbathe, photo, wait ...), loop (jog), post (work / busk / fish near the
--   anchor), transit (walk to the next scheduled area), queue (club line), enter (through the door),
--   hang (club smoking area), leave (walk away - often into a shop / the metro - and despawn), follow
--   (friend companion: walks with the player, rides along in a free car seat or waits when there is
--   none), member (walks / stands with a group leader), clubdance (a named citizen dancing inside
--   CLUB OCEAN, ClubCrowd), watch (the drone show over the bay), audience (the busker), customer
--   (buys at a street food cart), film (films the dancing player).
--   Activity people usually START at their spot (Crowd places them there: settleAtPoi) instead of
--   walking to it, and idle spots have small sub-states every few seconds (photo -> check the photo
--   -> selfie, bench -> phone / look around / talk to the neighbour, queue -> chat / sway / phone).
-- REACTIONS (close agents): step aside early when the player's path would hit them (time to
--   collision), a startled jump + a line when the player walks into them, a glance (not a stare) at
--   a sprinting player, slowing down and looking when the player walks up to a named citizen, a wave
--   from friends (친한 사이+), the evening club pitch (rare, one at a time). Cars: people jump out of
--   the way of a fast car (Crowd decides who), then complain and walk off; a horn turns heads.

local Agent = {}
Agent.__index = Agent

local ctx: any
local W: any
local Anim: any
local Config: any
local Citizens: any
local Night: any
local rng = Random.new()

local function rnd(): number
	return rng:NextNumber()
end

local function range(t: { number }): number
	return t[1] + (t[2] - t[1]) * rnd()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist2(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function yawOf(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

local function angleDiff(a: number, b: number): number
	local d = (b - a) % (2 * math.pi)
	if d > math.pi then
		d -= 2 * math.pi
	end
	return d
end

local function pick(list: { string }): string
	return list[1 + math.floor(rnd() * #list)]
end

local TWO_PI = 2 * math.pi

-- street-life styles that are not in GwangalliCitizens.ACT_STYLE
local LOCAL_STYLE = {
	wait = { move = "spot", kinds = { "busstop", "taxi", "metro" }, tags = { "wait" }, idle = "phone", speed = 1, label = "기다리는 중" },
}
local WATCH_STYLE = { move = "spot", kinds = { "view", "photo", "step" }, tags = { "photo", "watch" }, idle = "watch", speed = 1.1, label = "드론쇼 보는 중" }
local DOOR_STYLE = { move = "spot", kinds = { "shop", "cafe", "metro", "food" }, idle = "idle", speed = 1 }
Agent.LOCAL_STYLE = LOCAL_STYLE

-- reaction lines (street register; key citizens keep their own dialog lines)
local LINES = {
	bump = { "아 깜짝이야!", "조심 좀 하세요!", "어머, 죄송해요~", "앞 좀 보고 다니세요~", "헉!", "아야..." },
	bumpBusan = { "아이고 깜짝아!", "마 좀 보고 댕기라~", "어데 보고 댕기노!" },
	car = { "아 깜짝이야!! 운전 똑바로 해요!", "와 미쳤나 진짜!", "사람 있는 거 안 보여요?!", "어휴 큰일 날 뻔했네...", "천천히 좀 다녀요!" },
	carBusan = { "마! 운전 똑바로 해라!", "아이고 깜짝이야, 와 이래 빨리 달리노!", "니 미쳤나!" },
	horn = { "아 깜짝이야!", "빵빵거리지 좀 마요!", "네네 비켜요~" },
	wait = { "나 여기서 기다릴게!", "자리가 없네~ 나 여기 있을게!", "다녀와~ 여기서 기다릴게!" },
	rejoin = { "왔어? 가자!", "오 왔다 왔다~", "기다렸잖아 ㅎㅎ" },
	catchUp = { "나 택시 타고 왔어 ㅎㅎ", "헉헉 겨우 따라왔네!", "같이 가~!" },
}

local BUMP: any = nil -- GwangalliBumpShared (rules, knockdown motion, bubbles)
local SOCIAL: any = nil -- GwangalliSocialShared (type lines)

function Agent.init(context: any)
	ctx = context
	W = ctx.World
	Anim = ctx.Anim
	Config = ctx.Config
	Citizens = ctx.Citizens
	Night = ctx.Night
	BUMP = ctx.BumpShared
	SOCIAL = ctx.Social
end

-- def = { id, named, citizen?, speed, style? (act for extras), extra = true?, lure = bool }
function Agent.new(def: any, rig: any, node: number?, pos: Vector3, yaw: number): any
	local a = setmetatable({}, Agent)
	a.id = def.id
	a.named = def.named == true
	a.c = def.citizen
	a.def = def
	a.rig = rig
	a.root = rig.root
	a.ground = rig.ground
	a.scale = rig.scale
	a.node = node
	a.prev = nil
	a.pos = pos
	a.yaw = yaw
	a.faceYaw = nil
	a.walkSpeed = def.speed or 6
	a.baseWalkSpeed = a.walkSpeed
	a.speed = 0
	a.want = 0
	a.lat = 0.3 + rnd() * 0.65
	-- world-space offset (stepping aside / apart), eased toward (nudgeTX, nudgeTZ) until nudgeUntil
	a.nudgeX, a.nudgeZ, a.nudgeTX, a.nudgeTZ, a.nudgeUntil, a.nudgeRate = 0, 0, 0, 0, 0, 3
	a.mode = "idle"
	a.segA, a.segB, a.segLen, a.segT, a.segEdge = pos, pos, 0, 0, nil
	a.nav = nil
	a.plan = nil
	a.idleKind = "idle"
	a.idleUntil = 0
	a.nextSub = 0
	a.poi = nil
	a.seat = 0
	a.nextThink = 0
	a.nextSchedule = os.clock() + 3 + rnd() * 5
	a.acc = 0
	a.interval = 0
	a.dist = 0
	a.near = false
	a.onScreen = true
	a.moved = true
	a.cf = nil
	a.lookUntil = 0
	a.gazeUntil = 0
	a.glanceAt = 0
	a.lastWave = -1e9
	a.bumpAt = -1e9
	a.lure = def.lure == true
	a.members = {}
	a.leader = nil
	a.slot = nil
	a.pauseUntil = 0
	a.heyUntil = 0
	a.animState = nil
	a.walkPose = nil
	a.gone = false
	a.done = false
	a.born = os.clock()
	-- NPC type (npc_types): plain | violent | fool | beggar | drunk (GwangalliCitizens c.type)
	local c = def.citizen
	a.type = (c and c.type) or def.type or "plain"
	a.chatty = (c and c.chatty == true) or def.chatty == true
	if workspace:GetAttribute("GwangalliNpcTypes") == false then
		-- kill switch (server / Studio sets Workspace.GwangalliNpcTypes = false): everybody behaves as a
		-- 그냥 NPC and nobody walks up to talk (performance A/B, live-ops)
		a.type, a.chatty = "plain", false
	end
	a.knock = nil -- { t0, dx, dz, outcome, puk, prev }: knocked down / staggering (어깨빵)
	a.wobbleT = rnd() * 10
	a.nextTypeLine = os.clock() + 6 + rnd() * 10
	a.closeSince = nil
	a.lastFoolBump = -1e9
	a.chatState = nil -- "approach" | "talking" (chatty / beggar walk-ups)
	a.chatAt = -1e9
	a.chase = nil -- { untilT, nextHit, retarget }: a 폭력적인 NPC running after the player (6-8 s)
	if a.type == "drunk" then
		a.walkSpeed = a.walkSpeed * (BUMP and BUMP.DRUNK.speed or 0.62)
		a.walkPose = "sway"
	end
	return a
end

-------------------------------------------------------------------------------------------------
-- movement primitives
-------------------------------------------------------------------------------------------------
function Agent:right(): (number, number)
	-- right vector of the facing (yaw): (cos, -sin)
	return math.cos(self.yaw), -math.sin(self.yaw)
end

function Agent:stopMoving()
	self.segA, self.segB, self.segLen, self.segT = self.pos, self.pos, 0, 0
end

-- step aside / apart by (dx, dz) studs for dur seconds (eased at rate studs/s)
function Agent:nudge(dx: number, dz: number, dur: number, rate: number?)
	if self.sitting or self.lying or self.sitGround or self.mode == "dodge" or self.clubGuest or self.riding then
		return
	end
	local m = math.sqrt(dx * dx + dz * dz)
	if m > 3 then
		dx, dz = dx / m * 3, dz / m * 3
	end
	self.nudgeTX, self.nudgeTZ = dx, dz
	self.nudgeUntil = os.clock() + dur
	self.nudgeRate = rate or 3
end

-- set a segment from the current position toward point p (optionally along edge e toward node n)
function Agent:segTo(p: Vector3, e: number?, n: number?)
	local a = self.pos
	local dx, dz = p.X - a.X, p.Z - a.Z
	local len = math.sqrt(dx * dx + dz * dz)
	local target = p
	if e and len > 0.5 then
		local w = W.edgeWidth(e)
		local off = self.lat * math.max(0, w * 0.5 - 0.9)
		if off > 0.05 then
			local rx, rz = -dz / len, dx / len
			target = Vector3.new(p.X + rx * off, p.Y, p.Z + rz * off)
			dx, dz = target.X - a.X, target.Z - a.Z
			len = math.sqrt(dx * dx + dz * dz)
		end
	end
	self.segA = a
	self.segB = target
	self.segLen = math.max(len, 0.001)
	self.segT = 0
	self.segEdge = e
	self.segCross = e ~= nil and W.isCrossingKind(W.edgeKind(e))
	if n then
		self.prev = self.node
		self.node = n
	end
end

-- next target from the nav strategy: returns ("node", n, e) | ("point", p) | nil (arrived)
function Agent:pickNext(): (string?, any, any)
	local nav = self.nav
	if not nav then
		return nil
	end
	local cur = self.node
	if nav.start then
		local s = nav.start
		nav.start = nil
		if cur ~= s or (self.pos - W.pos[s]).Magnitude > 1.5 then
			return "node", s, nil
		end
	end
	local m = nav.mode
	if m == "points" then
		local i = nav.i or 1
		local p = nav.pts[i]
		nav.i = i + 1
		if p then
			return "point", p, nil
		end
		return nil
	end
	if not cur then
		cur = W.nearest(self.pos, 40)
		if not cur then
			return nil
		end
		self.node = cur
		return "node", cur, nil
	end
	if m == "list" then
		local i = nav.i or 1
		local n = nav.list[i]
		nav.i = i + 1
		if n then
			return "node", n, W.edgeBetween(cur, n)
		end
		if nav.goal then
			local g = nav.goal
			nav.goal = nil
			return "point", g, nil
		end
		return nil
	elseif m == "flow" then
		local f = nav.field
		if f and f.ready then
			if f.dist[cur] <= (nav.arrive or 0) then
				if nav.goal then
					local g = nav.goal
					nav.goal = nil
					return "point", g, nil
				end
				return nil
			end
			local n = f.next[cur]
			if n and n > 0 then
				return "node", n, W.edgeBetween(cur, n)
			end
			if nav.goal then
				local g = nav.goal
				nav.goal = nil
				return "point", g, nil
			end
			return nil
		end
		-- field still computing: drift with a random step
		local hx, hz = -math.sin(self.yaw), -math.cos(self.yaw)
		local n, e = W.randomStep(cur, self.prev, hx, hz, nav.opts or {}, rnd)
		if n then
			return "node", n, e
		end
		return nil
	elseif m == "club" then
		local n = W.toClub(cur)
		if n and n > 0 then
			return "node", n, W.edgeBetween(cur, n)
		end
		if nav.goal then
			local g = nav.goal
			nav.goal = nil
			return "point", g, nil
		end
		return nil
	elseif m == "random" then
		nav.steps -= 1
		if nav.steps < 0 then
			return nil
		end
		local hx, hz = -math.sin(self.yaw), -math.cos(self.yaw)
		local opts = nav.opts
		if opts.away then
			local pp = ctx.Crowd.playerPos()
			if pp then
				opts.away = pp
			end
		end
		local n, e = W.randomStep(cur, self.prev, hx, hz, opts, rnd)
		if n then
			return "node", n, e
		end
		return nil
	end
	return nil
end

-- start the next segment; false when the agent stopped (arrived / waiting at a crossing)
function Agent:nextSegment(now: number): boolean
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
	-- crossing?
	if e and W.isCrossingKind(W.edgeKind(e)) then
		local st = W.crossState(e, workspace:GetServerTimeNow())
		if st == "walk" and ctx.Crowd.carComing(self.pos, 38) then
			st = "wait" -- green for us, but a car is coming fast: let it pass
		end
		if st == "wait" then
			self.mode = "wait"
			self.waitNode, self.waitEdge = v, e
			self.waitSince = now
			local q = W.pos[v]
			self.faceYaw = yawOf(q.X - self.pos.X, q.Z - self.pos.Z)
			self.want = 0
			self.speed = 0
			if rnd() < 0.4 then
				Anim.setRestPose(self.rig, "phone")
			end
			self:setAnim(if rnd() < 0.3 then "idle2" else "idle")
			return false
		elseif st == "look" and self.lookedEdge ~= e then
			self.lookedEdge = e
			self.mode = "wait"
			self.waitNode, self.waitEdge = v, e
			self.waitSince = now
			self.waitLook = now + 0.6 + rnd() * 0.8
			local q = W.pos[v]
			self.faceYaw = yawOf(q.X - self.pos.X, q.Z - self.pos.Z)
			self.want = 0
			self.speed = 0
			self.gazeUntil = now + 1.2
			Anim.look(self.rig, if rnd() < 0.5 then 0.8 else -0.8, 0)
			self:setAnim("idle")
			return false
		end
	end
	self:segTo(W.pos[v], e, v)
	return true
end

-- the arm pose while walking (phone walkers, street food, hand in hand)
function Agent:applyWalkPose()
	local wp = self.walkPose
	if self.carry and os.clock() < (self.carryUntil or 0) then
		wp = self.carry
	elseif self.carry then
		self.carry = nil
	end
	if self.handWith then
		if self.handWith.gone or self.handWith.leader ~= self then
			self.handWith = nil
		else
			wp = self.handSide
		end
	end
	Anim.setRestPose(self.rig, wp)
end

local WALK_POSE_KINDS = { wander = true, transit = true, leave = true, hang = true, queue = true }
function Agent:pickWalkPose(kind: string)
	if self.type == "drunk" then
		self.walkPose = "sway" -- 주정뱅이: always the swaying walk (never the phone walk)
	elseif WALK_POSE_KINDS[kind] and not self.def.dog and rnd() < Config.PhoneWalk then
		self.walkPose = "phone"
	else
		self.walkPose = nil
	end
end

function Agent:resumeWalk(now: number)
	self.mode = "walk"
	self.faceYaw = nil
	self.want = self.walkSpeed
	self:applyWalkPose()
	Anim.look(self.rig, 0, 0)
	if not self:nextSegment(now) then
		return
	end
end

function Agent:startNav(nav: any, now: number, speed: number?)
	self.nav = nav
	self.mode = "walk"
	self.faceYaw = nil
	local sp = speed or self.walkSpeed
	if self.walkPose == "phone" then
		sp *= 0.85
	end
	self.want = sp
	self.lookedEdge = nil
	self:releasePoi()
	self.lying = false
	self.sitting = false
	if self.sitGround then
		self.sitGround = false
		Anim.legs(self.rig, nil)
	end
	Anim.cancelFlash(self.rig)
	self:applyWalkPose()
	self:stopMoving()
	self:nextSegment(now)
end

function Agent:goRandom(steps: number, opts: any, now: number, speed: number?)
	self:startNav({ mode = "random", steps = steps, opts = opts }, now, speed)
end

-- walk to a spot off the graph: A* to its nearest node, then straight to the spot
function Agent:goToSpot(spot: Vector3, now: number, speed: number?)
	local from = self.node or W.nearest(self.pos, 40)
	local target = W.nearest(spot, 30)
	local route = nil
	if from and target and from ~= target and (W.pos[from] - W.pos[target]).Magnitude < 260 then
		local ok, r = pcall(ctx.Nav.route, from, target)
		if ok then
			route = r
		end
	end
	if route then
		self:startNav({ mode = "list", list = route, i = 2, goal = spot }, now, speed)
	else
		self:startNav({ mode = "points", pts = { spot } }, now, speed)
	end
end

-------------------------------------------------------------------------------------------------
-- POIs / idling
-------------------------------------------------------------------------------------------------
function Agent:releasePoi()
	if self.poi then
		W.release(self.poi, self.seat)
		self.poi = nil
	end
end

local IDLE_BASE = { sit = "sit", dance = "dance", dance2 = "dance2", dance3 = "dance3", sunbathe = "none", lie = "none" }
local IDLE_POSE = {
	phone = "phone",
	photo = "photo",
	chat = "chat",
	eat = "eat",
	stretch = "stretch",
	look = "look",
	guitar = "guitar",
	paint = "paint",
	fish = "fish",
	think = "think",
	work = nil,
	sunbathe = "lie",
	study = "phone",
	groundsit = "lean",
	groundphone = "phone",
	watch = nil,
	customer = nil,
}
local GROUND = { groundsit = true, groundphone = true }

function Agent:setAnim(name: string, speed: number?)
	if self.animState == name and not speed then
		return
	end
	self.animState = name
	Anim.base(self.rig, name, speed)
end

-- idle in place: kind = idle hint (GwangalliCitizens.ACT_STYLE idle), dur seconds
function Agent:idleFor(kind: string, dur: number, now: number, faceYaw: number?)
	self.mode = "idle"
	self.idleKind = kind
	self.idleUntil = now + dur
	self.nextSub = now + range(Config.SubIdle)
	self.want = 0
	self.speed = 0
	self.faceYaw = faceYaw
	self:stopMoving()
	local base = IDLE_BASE[kind] or "idle"
	self.sitting = kind == "sit"
	self.lying = kind == "sunbathe"
	local ground = GROUND[kind] == true
	if ground ~= (self.sitGround == true) then
		self.sitGround = ground
		Anim.legs(self.rig, if ground then "ground" else nil)
	end
	self:setAnim(base)
	Anim.setRestPose(self.rig, IDLE_POSE[kind])
	self.moved = true
end

function Agent:endIdle(now: number)
	self.sitting = false
	self.lying = false
	if self.sitGround then
		self.sitGround = false
		Anim.legs(self.rig, nil)
	end
	Anim.setRestPose(self.rig, nil)
	self:releasePoi()
	if self.afterDive then
		self.afterDive = nil
		self.node = W.nearest(self.pos, 40)
		self.prev = nil
		self:setPlan({ kind = "leave", act = "walk" }, now)
		return
	end
	self:nextPlan(now)
end

-- sitting / standing at the reserved POI (self.poi / self.poiSpot): the activity starts here.
-- frac < 1 = somebody who has already been there a while (spawned in place)
function Agent:settleAtPoi(now: number, frac: number?)
	local plan = self.plan or {}
	local poi = self.poi
	local kind = self.arriveIdle or (plan.style and plan.style.idle) or "idle"
	local yaw = self.poiYaw
	if W.poiHasTag(poi, "sunbathe") then
		-- a towel on the sand: lie in the sun, or sit on it (legs forward, never a chair pose)
		local clock = ctx.clock()
		local sunny = clock >= 9 and clock < 18
		if kind == "sunbathe" and sunny then
			kind = "sunbathe"
		elseif kind == "photo" then
			kind = "photo"
		elseif sunny and rnd() < 0.45 then
			kind = "sunbathe"
		else
			kind = if kind == "phone" or kind == "study" or rnd() < 0.45 then "groundphone" else "groundsit"
		end
	elseif W.poiHasTag(poi, "sit") and (kind == "sit" or kind == "phone" or kind == "chat" or kind == "idle" or kind == "study" or kind == "paint" or kind == "eat" or (kind == "watch" and rnd() < 0.5)) then
		kind = if kind == "phone" or kind == "study" then "sitphone" else "sit"
	elseif W.poiHasTag(poi, "photo") and kind ~= "paint" then
		kind = "photo"
	elseif W.poiHasTag(poi, "window") then
		kind = "look"
	end
	self.pos = self.poiSpot
	local dur = range(Config.SpotTime) * (frac or 1)
	if plan.kind == "watch" then
		dur = math.max(4, (plan.untilT or now) - now)
		if kind ~= "sit" and kind ~= "sitphone" then
			yaw = plan.faceYaw or yaw
			if kind ~= "photo" then
				kind = "watch"
			end
		end
	end
	if kind == "sitphone" then
		self:idleFor("sit", dur, now, yaw)
		Anim.setRestPose(self.rig, "phone")
	else
		self:idleFor(kind, dur, now, yaw)
	end
end

-- reserve POI i and put the agent straight there (spawned in place / arrived)
function Agent:takePoi(poi: number, style: any?)
	self.seat = W.reserve(poi)
	self.poi = poi
	local spot, yaw = W.poiSpot(poi, self.seat)
	self.poiSpot, self.poiYaw = spot, yaw
	self.arriveIdle = (style and style.idle) or nil
end

-------------------------------------------------------------------------------------------------
-- plans
-------------------------------------------------------------------------------------------------
local DEFAULT_STYLE = { move = "wander", idle = "phone", speed = 1 }
local function styleOf(act: string?): any
	if not act then
		return DEFAULT_STYLE
	end
	return (Citizens and Citizens.ACT_STYLE and Citizens.ACT_STYLE[act]) or LOCAL_STYLE[act] or DEFAULT_STYLE
end
Agent.styleOf = styleOf

-- plans that end by themselves (the schedule check waits for them)
local EVENT_PLANS = { watch = true, audience = true, customer = true, film = true }
Agent.EVENT_PLANS = EVENT_PLANS

-- plan = { kind, area?, act, style, center?, radius?, allow?, info? }
function Agent:setPlan(plan: any, now: number)
	self.plan = plan
	self:beginPlan(now)
end

function Agent:wanderOpts(plan: any): any
	local c = plan.center or self.pos
	return {
		allow = plan.allow,
		cx = c.X,
		cz = c.Z,
		r = plan.radius or 140,
		crossW = plan.crossW or 0.45,
		sandW = plan.sandW or (if plan.act == "walk" then 0.6 else 1),
	}
end

function Agent:beginPlan(now: number)
	local plan = self.plan
	if not plan then
		self:idleFor("idle", 3, now)
		return
	end
	local style = plan.style or styleOf(plan.act)
	plan.style = style
	local kind = plan.kind
	self:pickWalkPose(kind)
	local speed = self.walkSpeed * (style.speed or 1)
	-- commute hours: people walk faster
	local clock = ctx.clock()
	if (kind == "transit" or kind == "wander") and ((clock >= 7.5 and clock < 9.3) or (clock >= 18 and clock < 19.3)) then
		speed *= 1.18
	end
	if kind == "wander" then
		self:goRandom(4 + math.floor(rnd() * 10), self:wanderOpts(plan), now, speed)
	elseif kind == "loop" then
		local opts = self:wanderOpts(plan)
		opts.crossW = 0.15
		opts.sandW = 0.25
		self:goRandom(18 + math.floor(rnd() * 20), opts, now, math.max(speed, 9.5))
	elseif kind == "spot" then
		self:goSpot(plan, now, speed)
	elseif kind == "post" then
		local anchorNode, anchorPos = W.anchor(plan.area)
		if plan.center then
			anchorPos = plan.center
		end
		if anchorPos and (flat(self.pos - anchorPos)).Magnitude > 40 and anchorNode then
			local f = W.flowToArea(plan.area)
			if f then
				self:startNav({ mode = "flow", field = f, arrive = 18, opts = self:wanderOpts(plan) }, now, speed)
				return
			end
		end
		-- a spot of the post's kinds nearby (busk / view), else stand where we are
		if style.kinds and rnd() < 0.8 then
			local filter = W.poiFilter(style)
			local poi = W.findPoi(self.pos, 45, filter, Night.hype(ctx.clock()) > 0.3, rnd)
			if poi then
				self:toPoi(poi, now, speed, style)
				return
			end
		end
		self:idleFor(style.idle or "idle", range({ 14, 34 }), now)
	elseif kind == "transit" then
		local f = W.flowToArea(plan.area)
		if not f then
			self:goRandom(10, self:wanderOpts(plan), now, speed)
			return
		end
		local r = W.areaRadius(plan.area)
		self:startNav({ mode = "flow", field = f, arrive = math.clamp(r * 0.45, 25, 160), opts = self:wanderOpts(plan) }, now, speed * 1.05)
	elseif kind == "queue" then
		local Q = ctx.Crowd.queue
		if Q and Q.nearTail(self) then
			self:joinQueue(now)
			return
		end
		self:startNav({ mode = "club" }, now, speed * 1.05)
	elseif kind == "hang" then
		-- friends take the spots next to each other in the smokers' ring
		ctx.Crowd.dissolve(self)
		local spot, face = ctx.Crowd.queue.hangSpot(self)
		if spot then
			self.hangFace = face
			if (flat(self.pos - spot)).Magnitude > 60 then
				self:startNav({ mode = "club", goal = spot }, now, speed)
			else
				self:startNav({ mode = "points", pts = { spot } }, now, speed)
			end
		else
			self:goRandom(8, self:wanderOpts(plan), now, speed)
		end
	elseif kind == "enter" then
		self:startNav({ mode = "points", pts = plan.pts }, now, speed * 0.9)
	elseif kind == "leave" then
		-- often into a shop / café / the metro nearby (not right next to the player), else away
		local pp = ctx.Crowd.playerPos()
		if plan.door == nil and rnd() < 0.55 then
			local night = Night.hype(ctx.clock()) > 0.35
			plan.door = W.findPoi(self.pos, 70, W.poiFilter(DOOR_STYLE), night, rnd, pp, 22) or false
		end
		if plan.door then
			self:goToSpot(W.poiPos[plan.door], now, speed * 1.05)
			return
		end
		local opts = { away = pp, crossW = 0.5, sandW = 0.5 }
		self:goRandom(80, opts, now, speed * 1.05)
	elseif kind == "follow" then
		self.mode = "follow"
		self.nav = nil
		self:releasePoi()
		self.sitting, self.lying = false, false
		if self.sitGround then
			self.sitGround = false
			Anim.legs(self.rig, nil)
		end
		Anim.setRestPose(self.rig, nil)
	elseif kind == "member" then
		self.mode = "member"
		self.nav = nil
	elseif kind == "watch" then
		-- the drone show: to the sea side (a viewpoint / photo spot / the steps nearby), face the bay
		local poi = if plan.stay then nil else W.findPoi(self.pos, 30, W.poiFilter(WATCH_STYLE), true, rnd)
		if poi and not W.poiHasTag(poi, "sunbathe") then
			self:toPoi(poi, now, speed, WATCH_STYLE)
			return
		end
		self:idleFor(if rnd() < 0.5 then "photo" else "watch", math.max(4, (plan.untilT or now) - now), now, plan.faceYaw)
	elseif kind == "audience" or kind == "customer" or kind == "film" then
		if kind == "film" then
			self:idleFor("photo", plan.dur or 6, now, plan.faceYaw)
			return
		end
		self:goToSpot(plan.spot, now, speed)
	else
		self:goRandom(8, self:wanderOpts(plan), now, speed)
	end
end

function Agent:toPoi(poi: number, now: number, speed: number, style: any)
	self:takePoi(poi, style)
	local spot = self.poiSpot
	local target = W.poiNode[poi]
	local from = self.node or W.nearest(self.pos, 40)
	local route = nil
	if from and target and from ~= target and (W.pos[from] - W.pos[target]).Magnitude < 260 then
		local ok, r = pcall(ctx.Nav.route, from, target)
		if ok then
			route = r
		end
	end
	local poiRef = poi
	local keep = self.poi
	if route then
		self:startNav({ mode = "list", list = route, i = 2, goal = spot }, now, speed)
	else
		self:startNav({ mode = "points", pts = { W.pos[target] or spot, spot } }, now, speed)
	end
	-- startNav released the reservation: take the same seat again
	if keep and not self.poi then
		self.seat = W.reserve(poiRef, self.seat)
		self.poi = poiRef
	end
	self.arriveIdle = style.idle or "idle"
end

function Agent:goSpot(plan: any, now: number, speed: number)
	local style = plan.style
	local filter = W.poiFilter(style)
	local center = plan.center or self.pos
	local night = Night.hype(ctx.clock()) > 0.35
	-- prefer spots near the agent but inside the plan's area
	local poi = W.findPoi(self.pos, 90, filter, night, rnd)
	if poi and plan.center and plan.radius then
		local d = (flat(W.poiPos[poi] - center)).Magnitude
		if d > plan.radius + 40 then
			poi = nil
		end
	end
	if not poi then
		poi = W.findPoi(center, math.min(plan.radius or 120, 160), filter, night, rnd)
		if poi and (W.poiPos[poi] - self.pos).Magnitude > 220 then
			poi = nil
		end
	end
	if poi then
		self:toPoi(poi, now, speed, style)
	else
		-- no free spot: wander a little and idle with the style's gesture
		plan.noSpot = (plan.noSpot or 0) + 1
		if plan.noSpot > 2 then
			self:idleFor(if style.idle == "sit" then "phone" else (style.idle or "phone"), range({ 8, 18 }), now)
		else
			self:goRandom(4 + math.floor(rnd() * 6), self:wanderOpts(plan), now, speed)
		end
	end
end

-- after a plan step finished: what next (schedule / extra behaviour)
function Agent:nextPlan(now: number)
	local plan = self.plan
	if self.mode == "member" or self.mode == "follow" then
		return
	end
	if self.clubGuest then
		-- dancing inside CLUB OCEAN until ClubCrowd lets them go
		self:idleFor(self.clubDance or "dance", 1e9, now, self.clubYaw)
		return
	end
	local k = plan and plan.kind
	if k and EVENT_PLANS[k] then
		-- the drone show ended / enough busking / bought something / done filming: back to the day
		self.plan = plan.resume
		if k == "customer" then
			self.carry = "eat"
			self.carryUntil = now + 18 + rnd() * 22
		end
		if self.named and self.c and ctx.Crowd.scheduleCheck(self, now, true) then
			return
		end
		local resume = plan.resume
		if resume and not EVENT_PLANS[resume.kind] and resume.kind ~= "queueing" and resume.kind ~= "member" then
			self:setPlan(resume, now)
		else
			self:setPlan({ kind = "wander", act = "walk", center = self.pos, radius = 180 }, now)
		end
		return
	end
	if self.named and self.c then
		if ctx.Crowd.scheduleCheck(self, now, true) then
			return
		end
	end
	if not plan then
		self:setPlan({ kind = "wander", act = "walk" }, now)
		return
	end
	if k == "transit" then
		-- arrived in the scheduled area: act there
		ctx.Crowd.planInArea(self, plan.area, plan.act, now)
	elseif k == "spot" then
		if plan.act == "wait" then
			-- the bus / taxi came: gone once nobody watches, else wait a little longer
			if not self.onScreen then
				self.done = true
			else
				self:idleFor(self.idleKind or "phone", 6 + rnd() * 8, now, self.faceYaw)
			end
			return
		end
		-- another spot or a short wander between spots
		if rnd() < 0.55 then
			self:goRandom(3 + math.floor(rnd() * 6), self:wanderOpts(plan), now)
			plan.afterWander = true
		else
			self:beginPlan(now)
		end
	elseif k == "leave" then
		self.done = true
	elseif k == "enter" then
		self.done = true
	else
		self:beginPlan(now)
	end
end

-- arrived at the end of the nav strategy
function Agent:arrive(now: number)
	if self.chase then
		-- chasing the player: the point was where they stood; chaseTick retargets right away
		self.want, self.speed, self.nav = 0, 0, nil
		self:idleFor("idle", 0.4, now)
		return
	end
	if now == self.arriveAt then
		self.arriveDepth = (self.arriveDepth or 0) + 1
		if self.arriveDepth > 4 then
			-- plans that end immediately (no route / no neighbour): rest a moment instead of looping
			self.arriveDepth = 0
			self.nav = nil
			self:idleFor("idle", 2 + rnd() * 3, now)
			return
		end
	else
		self.arriveAt = now
		self.arriveDepth = 0
	end
	local plan = self.plan
	self.want = 0
	self.speed = 0
	self.nav = nil
	if not plan then
		self:idleFor("idle", range(Config.PauseTime), now)
		return
	end
	local k = plan.kind
	if self.poi and self.poiSpot then
		self:settleAtPoi(now, 1)
		return
	end
	if k == "queue" then
		self:joinQueue(now)
		return
	elseif k == "queueing" then
		local e = Night.clubEntrance()
		local f = e and e.queueFace or Vector3.new(0, 0, 1)
		self.queueWalk = false
		self:idleFor(if rnd() < 0.5 then "phone" else "idle", 1e6, now, yawOf(f.X, f.Z))
		return
	elseif k == "hang" then
		local face = self.hangFace
		local yaw = if face then yawOf(face.X - self.pos.X, face.Z - self.pos.Z) else nil
		self:idleFor(if rnd() < 0.6 then "chat" else "phone", range({ 20, 45 }), now, yaw)
		return
	elseif k == "enter" then
		self.done = true
		return
	elseif k == "leave" then
		self.done = true
		return
	elseif k == "post" then
		self:idleFor(plan.style.idle or "idle", range({ 14, 34 }), now)
		return
	elseif k == "audience" then
		local f = plan.face
		self:idleFor("watch", math.max(5, (plan.untilT or now) - now), now, if f then yawOf(f.X - self.pos.X, f.Z - self.pos.Z) else nil)
		return
	elseif k == "customer" then
		local f = plan.face
		self:idleFor("customer", 4 + rnd() * 5, now, if f then yawOf(f.X - self.pos.X, f.Z - self.pos.Z) else nil)
		return
	elseif k == "watch" then
		self:idleFor("watch", math.max(4, (plan.untilT or now) - now), now, plan.faceYaw)
		return
	elseif k == "wander" or k == "loop" then
		if plan.afterWander then
			plan.afterWander = nil
		end
		-- pause (look around, phone, stretch after a jog), a little off the path's centre line
		local rx, rz = self:right()
		local j = (rnd() - 0.5) * 1.8
		self.pos = Vector3.new(self.pos.X + rx * j, self.pos.Y, self.pos.Z + rz * j)
		local idle = if k == "loop" then (if rnd() < 0.5 then "stretch" else "idle") else (if rnd() < 0.45 then "phone" elseif rnd() < 0.5 then "look" else "idle")
		self:idleFor(idle, range(Config.PauseTime), now)
		return
	elseif k == "spot" and plan.afterWander then
		plan.afterWander = nil
		self:beginPlan(now)
		return
	end
	self:nextPlan(now)
end

-------------------------------------------------------------------------------------------------
-- club queue
-------------------------------------------------------------------------------------------------
function Agent:joinQueue(now: number)
	ctx.Crowd.dissolve(self)
	local Q = ctx.Crowd.queue
	local idx = Q and Q.join(self)
	if not idx then
		-- line full: hang around the entrance
		self.plan = { kind = "hang", act = "hangout", style = styleOf("hangout") }
		self:beginPlan(now)
		return
	end
	self.queueIdx = idx
	local spot = Q.spot(idx)
	self.plan = { kind = "queueing", act = "queue", style = styleOf("queue") }
	self:startNav({ mode = "points", pts = { spot } }, now, self.walkSpeed * 0.8)
	self.queueWalk = true
end

-- the queue manager moved this member to spot idx
function Agent:queueMove(idx: number, now: number)
	self.queueIdx = idx
	local spot = ctx.Crowd.queue.spot(idx)
	self.sitting = false
	self.nav = { mode = "points", pts = { spot } }
	self.mode = "walk"
	self.want = self.walkSpeed * 0.6
	self.faceYaw = nil
	self:stopMoving()
	self:nextSegment(now)
	self.queueWalk = true
end

-------------------------------------------------------------------------------------------------
-- per-frame step
-------------------------------------------------------------------------------------------------
local ANIM_WALK = 6.4
local ANIM_RUN = 12.8

function Agent:updateWalkAnim()
	local sp = self.speed
	if sp > 8.8 then
		self:setAnim("run")
		local st = self.rig.anim
		if st and math.abs((st.baseSpeed or 1) - sp / ANIM_RUN) > 0.08 then
			Anim.base(self.rig, "run", math.clamp(sp / ANIM_RUN, 0.6, 1.6))
		end
	elseif sp > 0.4 then
		self:setAnim("walk")
		local st = self.rig.anim
		local want = math.clamp(sp / ANIM_WALK, 0.45, 1.5)
		if st and math.abs((st.baseSpeed or 1) - want) > 0.08 then
			Anim.base(self.rig, "walk", want)
		end
	else
		local base = if self.mode == "idle" then (IDLE_BASE[self.idleKind] or "idle") else "idle"
		if base == "idle" and self.animState == "idle2" then
			base = "idle2"
		end
		self:setAnim(base)
	end
end

function Agent:advance(dt: number, now: number)
	-- speed ramps (a short stop when the player is in the way, slower while the player walks up)
	local want = self.want
	if now < self.pauseUntil then
		want = 0
	elseif now < self.heyUntil then
		want = math.min(want, 1.5)
	end
	local sp = self.speed
	if sp < want then
		sp = math.min(want, sp + 9 * dt)
	elseif sp > want then
		sp = math.max(want, sp - 12 * dt)
	end
	self.speed = sp
	if self.wobble then
		self.wobbleT += dt
	end
	local move = sp * dt
	local guard = 0
	while move > 0 and guard < 8 do
		guard += 1
		local remain = self.segLen - self.segT
		if move < remain then
			self.segT += move
			move = 0
		else
			move -= remain
			self.segT = self.segLen
			self.pos = self.segB
			if not self:nextSegment(now) then
				move = 0
				break
			end
		end
	end
	if self.mode == "walk" and self.segLen > 0.001 then
		local a, b = self.segA, self.segB
		local t = self.segT / self.segLen
		local y = a.Y + (b.Y - a.Y) * t
		if self.segCross and self.segLen > 3 then
			-- carriageway under a crossing is 0.5 below the kerbs
			local d0, d1 = self.segT, self.segLen - self.segT
			if d0 > 1 and d1 > 1 then
				y = math.min(y, 6.0)
			end
		end
		self.pos = Vector3.new(a.X + (b.X - a.X) * t, y, a.Z + (b.Z - a.Z) * t)
		local dx, dz = b.X - a.X, b.Z - a.Z
		if dx * dx + dz * dz > 0.01 then
			local target = yawOf(dx, dz)
			local d = angleDiff(self.yaw, target)
			local turn = math.clamp(d, -7 * dt, 7 * dt)
			self.yaw = (self.yaw + turn) % TWO_PI
		end
	end
end

-- the vehicle model a seat belongs to (a GwangalliDrivable car, a taxi ...)
local CollectionService = game:GetService("CollectionService")
local function carOf(seat: BasePart): Model?
	local m = seat.Parent
	local first: Model? = nil
	while m and m ~= workspace do
		if m:IsA("Model") then
			first = first or m
			if CollectionService:HasTag(m, "GwangalliDrivable") or m:GetAttribute("VehicleKind") ~= nil then
				return m
			end
		end
		m = m.Parent
	end
	return first
end

-- a free passenger seat in the player's vehicle (nobody real sits there)
local function freeSeat(car: Model, taken: BasePart): Seat?
	local best, bd = nil, math.huge
	for _, d in car:GetDescendants() do
		if d:IsA("Seat") and d ~= taken and d.Occupant == nil then
			local dist = (d.Position - taken.Position).Magnitude
			if dist < bd then
				best, bd = d, dist
			end
		end
	end
	return best
end

function Agent:setCompanionState(state: string)
	if self.companionState == state then
		return
	end
	self.companionState = state
	-- client-only attribute for the local UI (phone / relationships): "follow" | "ride" | "wait"
	if self.followPlayer == ctx.player then
		pcall(function()
			ctx.player:SetAttribute("GwangalliCompanionState", state)
		end)
	end
end

function Agent:stopRiding(root: BasePart?)
	local seat = self.riding
	self.riding = nil
	self.rideCF = nil
	self.sitting = false
	if seat and seat.Parent then
		-- climb out on the seat's side
		local cf = seat.CFrame
		local out = cf.Position + cf.RightVector * 3.2
		local gy = if root then root.Position.Y - 3 else out.Y
		self.pos = Vector3.new(out.X, gy, out.Z)
		self.yaw = yawOf(cf.LookVector.X, cf.LookVector.Z)
	end
	self.moved = true
end

function Agent:stepFollow(dt: number, now: number)
	local target = self.followPlayer
	local ch = target and target.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		self.want = 0
		self.speed = 0
		self:setAnim("idle")
		return
	end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	local seatPart = ctx.Crowd.seatOf(target)
	-- only vehicles count (a bench / chair seat: the friend just stands by)
	if seatPart then
		local car = carOf(seatPart)
		if not (seatPart:IsA("VehicleSeat") or (car and (CollectionService:HasTag(car, "GwangalliDrivable") or car:GetAttribute("VehicleKind") ~= nil))) then
			seatPart = nil
		end
	end
	-- a GwangalliTaxi ride (the player is welded in, no Seat): the friend takes the other side of
	-- the back seat (a client-only visual seat, mirrored across the taxi's centre line)
	local taxiRoot: BasePart? = nil
	if not seatPart and target:GetAttribute("InTaxi") == true then
		local f = workspace:FindFirstChild("GwangalliTaxis")
		local m = f and f:FindFirstChild("GwangalliTaxi_" .. tostring(target.UserId))
		local pr = m and (m :: Model).PrimaryPart
		if pr then
			taxiRoot = pr
		end
	end
	if taxiRoot then
		local loc = taxiRoot.CFrame:ToObjectSpace(root.CFrame)
		local x = if math.abs(loc.X) < 0.6 then loc.X + 2.6 else -loc.X
		local rot = loc - loc.Position
		self.rideCF = taxiRoot.CFrame * CFrame.new(x, loc.Y - 0.25, loc.Z) * rot
		self.pos = self.rideCF.Position - Vector3.new(0, 1.45 * self.scale, 0)
		if not self.taxiRide then
			self.taxiRide = true
			self.riding = nil
			self.waitCar = nil
			self.sitting = true
			self.speed = 0
			Anim.setRestPose(self.rig, nil)
			self:setAnim("sit")
			self:setCompanionState("ride")
		end
		self.moved = true
		return
	elseif self.taxiRide then
		-- out of the taxi: climb out next to the friend
		self.taxiRide = nil
		self.rideCF = nil
		self.sitting = false
		local rcf = root.CFrame
		self.pos = rcf.Position + rcf.RightVector * 3 - Vector3.new(0, 3, 0)
		self:setCompanionState("follow")
		self.moved = true
	end
	-- the friend got into a vehicle: ride along in a free seat, or wait here
	if seatPart then
		if self.riding then
			local seat = self.riding :: Seat
			if seat.Parent and seat.Occupant == nil and seat:IsDescendantOf(workspace) then
				local s = seat.Size
				self.rideCF = seat.CFrame * CFrame.new(0, s.Y * 0.5 + 1.45 * self.scale, 0)
				self.pos = self.rideCF.Position - Vector3.new(0, 1.45 * self.scale, 0)
				self.moved = true
				return
			end
			self:stopRiding(root)
		end
		if not self.waitCar then
			local car = carOf(seatPart)
			local seat = car and freeSeat(car, seatPart)
			if seat and (seat.Position - self.pos).Magnitude < 40 then
				self.riding = seat
				self.sitting = true
				self.speed = 0
				Anim.setRestPose(self.rig, nil)
				self:setAnim("sit")
				self:setCompanionState("ride")
				return
			end
			-- no seat: wait here with the phone
			self.waitCar = { since = now, far = nil }
			self.speed = 0
			self.want = 0
			self:setAnim("idle")
			Anim.setRestPose(self.rig, "phone")
			self:setCompanionState("wait")
			ctx.SocialUI.say(self, pick(LINES.wait), 4)
		end
		self.moved = true
		return
	end
	if self.riding then
		self:stopRiding(root)
		self:setCompanionState("follow")
	end
	local cf = root.CFrame
	local look = flat(cf.LookVector)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	local right = Vector3.new(-look.Z, 0, look.X)
	local groundY = cf.Position.Y - 3
	if hum and hum.RigType == Enum.HumanoidRigType.R15 then
		groundY = cf.Position.Y - hum.HipHeight - root.Size.Y / 2
	end
	local anchor = cf.Position - look * 2.6 + right * 3.2
	anchor = Vector3.new(anchor.X, groundY, anchor.Z)
	local d = (flat(anchor - self.pos)).Magnitude
	local wc = self.waitCar
	if wc then
		-- waiting for the friend to come back (on foot) - or catching up when they got out far away
		if d < 40 then
			self.waitCar = nil
			Anim.setRestPose(self.rig, nil)
			self:setCompanionState("follow")
			ctx.SocialUI.say(self, pick(LINES.rejoin), 3)
		else
			if d > 250 then
				wc.far = wc.far or now
			else
				wc.far = nil
			end
			if wc.far and now - wc.far > 15 then
				self.waitCar = nil
				Anim.setRestPose(self.rig, nil)
				self.pos = cf.Position - look * 9 - Vector3.new(0, cf.Position.Y - groundY, 0)
				self.speed = 0
				self:setCompanionState("follow")
				ctx.SocialUI.say(self, pick(LINES.catchUp), 4)
				self.moved = true
			end
			return
		end
	end
	if d > 80 then
		-- quick travel / respawn: join the friend
		self.pos = anchor
		self.speed = 0
		self.moved = true
		return
	end
	local want = 0
	if d > 3 then
		want = math.clamp(d * 1.7, 4.5, 24)
	elseif d > 1 and self.speed > 0.5 then
		want = math.max(2.5, self.speed * 0.8)
	end
	local sp = self.speed
	if sp < want then
		sp = math.min(want, sp + 14 * dt)
	else
		sp = math.max(want, sp - 16 * dt)
	end
	self.speed = sp
	if sp > 0.05 and d > 0.05 then
		local dir = flat(anchor - self.pos).Unit
		local step = math.min(d, sp * dt)
		local np = self.pos + dir * step
		self.pos = Vector3.new(np.X, self.pos.Y + (groundY - self.pos.Y) * math.min(1, dt * 8), np.Z)
		local ty = yawOf(dir.X, dir.Z)
		self.yaw = (self.yaw + math.clamp(angleDiff(self.yaw, ty), -9 * dt, 9 * dt)) % TWO_PI
	else
		self.pos = Vector3.new(self.pos.X, self.pos.Y + (groundY - self.pos.Y) * math.min(1, dt * 8), self.pos.Z)
		-- stand facing the same way as the friend, turned a little toward them
		local ty = yawOf(look.X - right.X * 0.6, look.Z - right.Z * 0.6)
		self.yaw = (self.yaw + math.clamp(angleDiff(self.yaw, ty), -3 * dt, 3 * dt)) % TWO_PI
	end
	-- dancing with the friend in the club (the friend stands still inside at night)
	local still = sp < 0.3 and (ctx.Crowd.playerSpeed(target) or 0) < 1
	if still then
		self.stillFor = (self.stillFor or 0) + dt
	else
		self.stillFor = 0
	end
	if self.stillFor > 2.5 and ctx.Crowd.inClub(cf.Position) then
		self:setAnim("dance")
	else
		self:updateWalkAnim()
	end
	self.moved = true
end

function Agent:stepMember(dt: number, now: number)
	local L = self.leader
	if not L or L.gone then
		self.leader = nil
		self.mode = "walk"
		self:setPlan({ kind = "wander", act = "walk", radius = 160 }, now)
		return
	end
	local lp = L.pos
	local ly = L.yaw
	local fx, fz = -math.sin(ly), -math.cos(ly)
	local rx, rz = math.cos(ly), -math.sin(ly)
	local slot = self.slot or { side = 1, back = 0 }
	local sideW = Config.GroupSide
	local target: Vector3
	local faceLeader = false
	local walking = L.mode == "walk" or L.mode == "follow"
	if walking then
		target = Vector3.new(lp.X + rx * slot.side * sideW - fx * slot.back * 1.8, lp.Y, lp.Z + rz * slot.side * sideW - fz * slot.back * 1.8)
	elseif L.sitting or L.sitGround then
		-- stand in front of the bench / towel, chatting
		target = Vector3.new(lp.X + fx * 2.8 + rx * slot.side * 1.6, lp.Y, lp.Z + fz * 2.8 + rz * slot.side * 1.6)
		faceLeader = true
	elseif L.mode == "wait" then
		target = Vector3.new(lp.X + rx * slot.side * sideW - fx * slot.back * 1.2, lp.Y, lp.Z + rz * slot.side * sideW - fz * slot.back * 1.2)
	else
		-- a small circle: leader + members face each other
		local ang = (if slot.side > 0 then 0.95 else -0.95) + slot.back * 0.9
		local ox, oz = fx * math.cos(ang) + rx * math.sin(ang), fz * math.cos(ang) + rz * math.sin(ang)
		target = Vector3.new(lp.X + ox * 3.0, lp.Y, lp.Z + oz * 3.0)
		faceLeader = true
	end
	local d = (flat(target - self.pos)).Magnitude
	if d > 30 then
		self.pos = target
		self.speed = 0
	else
		local want = 0
		if d > 0.6 then
			want = math.clamp(d * 2.2, 1.5, (L.speed or 6) * 1.4 + 2)
		end
		local sp = self.speed
		sp = if sp < want then math.min(want, sp + 10 * dt) else math.max(want, sp - 14 * dt)
		self.speed = sp
		if sp > 0.05 and d > 0.05 then
			local dir = flat(target - self.pos).Unit
			local np = self.pos + dir * math.min(d, sp * dt)
			self.pos = Vector3.new(np.X, np.Y + (target.Y - np.Y) * math.min(1, dt * 6), np.Z)
		end
	end
	local ty
	if faceLeader and d < 1.2 then
		ty = yawOf(lp.X - self.pos.X, lp.Z - self.pos.Z)
		if not L.sitting and not L.sitGround and L.mode == "idle" and not L.lying then
			L.faceYaw = L.faceYaw or yawOf(self.pos.X - lp.X, self.pos.Z - lp.Z)
		end
	elseif self.speed > 0.4 then
		local dir = flat(target - self.pos)
		ty = if dir.Magnitude > 0.05 then yawOf(dir.X, dir.Z) else ly
	else
		ty = ly
	end
	self.yaw = (self.yaw + math.clamp(angleDiff(self.yaw, ty), -8 * dt, 8 * dt)) % TWO_PI
	-- gestures while standing together; hand in hand while walking (couples)
	local st = self.rig.anim
	if st then
		local rest = Anim.restPose(self.rig)
		if not walking and d < 1.5 then
			if rest ~= "chat" and rest ~= "phone" then
				Anim.setRestPose(self.rig, if slot.phone then "phone" else "chat")
			end
		elseif walking then
			local want = if slot.hand and d < 1.2 then (if slot.side > 0 then "handL" else "handR") else nil
			if rest ~= want then
				Anim.setRestPose(self.rig, want)
			end
		end
	end
	self:updateWalkAnim()
	self.moved = true
end

-- advance by dt (accumulated for far agents); sets self.moved when the CFrame changed
function Agent:step(dt: number, now: number)
	local mode = self.mode
	if self.knock then
		self:stepKnock(dt, now)
		return
	end
	if mode == "walk" then
		self:advance(dt, now)
		self:updateWalkAnim()
		self.moved = true
	elseif mode == "follow" then
		self:stepFollow(dt, now)
	elseif mode == "member" then
		self:stepMember(dt, now)
	elseif mode == "dodge" then
		-- jumping / running out of a car's way
		local k = math.clamp((self.dodgeUntil - now) / 0.25, 0.35, 1)
		self.pos = Vector3.new(self.pos.X + self.dodgeX * dt * k, self.pos.Y, self.pos.Z + self.dodgeZ * dt * k)
		local ty = yawOf(self.dodgeX, self.dodgeZ)
		self.yaw = (self.yaw + math.clamp(angleDiff(self.yaw, ty), -14 * dt, 14 * dt)) % TWO_PI
		self.speed = math.sqrt(self.dodgeX * self.dodgeX + self.dodgeZ * self.dodgeZ) * k
		self:updateWalkAnim()
		self.moved = true
		if now >= self.dodgeUntil then
			self:afterDodge(now)
		end
	else
		if self.speed > 0 then
			self.speed = 0
			self:updateWalkAnim()
		end
	end
	-- turn toward a facing target (idle at a spot, waiting at a crossing, talking)
	local fy = self.faceYaw
	if fy and mode ~= "walk" and mode ~= "member" and mode ~= "follow" and mode ~= "dodge" then
		local d = angleDiff(self.yaw, fy)
		if math.abs(d) > 0.01 then
			self.yaw = (self.yaw + math.clamp(d, -5 * dt, 5 * dt)) % TWO_PI
			self.moved = true
		end
	end
	-- stepping aside / apart (world-space offset, eased)
	local tx, tz = 0, 0
	if now < self.nudgeUntil then
		tx, tz = self.nudgeTX, self.nudgeTZ
	end
	local ox, oz = self.nudgeX, self.nudgeZ
	if ox ~= tx or oz ~= tz then
		local ex, ez = tx - ox, tz - oz
		local e = math.sqrt(ex * ex + ez * ez)
		local r = self.nudgeRate * dt
		if e <= r then
			ox, oz = tx, tz
		else
			ox += ex / e * r
			oz += ez / e * r
		end
		if tx == 0 and tz == 0 and mode ~= "walk" and mode ~= "member" and mode ~= "follow" then
			-- standing people stay where they stepped to (no drift back)
			self.pos = Vector3.new(self.pos.X + ox, self.pos.Y, self.pos.Z + oz)
			ox, oz = 0, 0
		end
		self.nudgeX, self.nudgeZ = ox, oz
		self.moved = true
	end
end

function Agent:computeCFrame(): CFrame
	local rc = self.rideCF
	if rc then
		return rc
	end
	local p = self.pos
	local yaw = self.yaw
	local kn = self.knock
	if kn and BUMP then
		local feet = Vector3.new(p.X + self.nudgeX, p.Y, p.Z + self.nudgeZ)
		if kn.outcome == "knockdown" then
			return BUMP.fallRootCFrame(feet, yaw, kn.dx, kn.dz, kn.k or 0, self.ground, self.scale)
		end
		local off, lean = BUMP.staggerOffset(kn.dx, kn.dz, kn.k or 0, self.scale)
		return CFrame.new(feet + Vector3.new(0, self.ground, 0) + off) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, lean)
	end
	if self.napping then
		-- asleep on the bench (주정뱅이): on the seat, on the side
		return CFrame.new(p.X, p.Y + 1.5 * self.scale + 0.35, p.Z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.new(0, -0.3 * self.scale, 0)
	end
	local wob = self.wobble
	if wob and wob > 0 and self.mode == "walk" and self.speed > 0.5 then
		-- 동네바보 / 주정뱅이: a sinusoidal sideways drift and a yaw wiggle while walking
		local t = self.wobbleT
		local rx, rz = self:right()
		local amp = math.sin(t * (if self.type == "drunk" then 1.9 else 2.6)) * wob
		local wy = math.sin(t * 1.3 + 1) * (if self.type == "drunk" then 0.22 else 0.12)
		return CFrame.new(p.X + self.nudgeX + rx * amp, p.Y + self.ground, p.Z + self.nudgeZ + rz * amp) * CFrame.Angles(0, yaw + wy, 0)
	end
	if self.lying then
		return CFrame.new(p.X, p.Y + 0.55 * self.scale, p.Z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.pi / 2, 0, 0) * CFrame.new(0, -0.6 * self.scale, 0)
	elseif self.sitGround then
		-- on the sand: thighs on the ground (hip pivot ~0.95 below the root centre, thigh half 0.5)
		return CFrame.new(p.X, p.Y + 1.42 * self.scale, p.Z) * CFrame.Angles(0, yaw, 0)
	elseif self.sitting then
		return CFrame.new(p.X, p.Y + 1.5 * self.scale, p.Z) * CFrame.Angles(0, yaw, 0)
	end
	return CFrame.new(p.X + self.nudgeX, p.Y + self.ground, p.Z + self.nudgeZ) * CFrame.Angles(0, yaw, 0)
end

-------------------------------------------------------------------------------------------------
-- think: decisions + reactions (near: ~5 Hz, far: ~1 Hz)
-------------------------------------------------------------------------------------------------
function Agent:think(now: number)
	local st = self.rig.anim
	if st and st.flashUntil then
		Anim.tick(self.rig, now)
	end
	local mode = self.mode
	if mode == "wait" then
		local e = self.waitEdge
		local go = false
		if self.waitLook then
			if now >= self.waitLook then
				self.waitLook = nil
				Anim.look(self.rig, 0, 0)
				go = not ctx.Crowd.carComing(self.pos, 38)
			end
		else
			local cst = e and W.crossState(e, workspace:GetServerTimeNow())
			go = (cst ~= "wait" and not ctx.Crowd.carComing(self.pos, 38)) or now - (self.waitSince or now) > 45
		end
		if go and e then
			self.mode = "walk"
			self.faceYaw = nil
			self.want = self.walkSpeed * (if self.plan and self.plan.style then self.plan.style.speed or 1 else 1)
			self:applyWalkPose()
			self:segTo(W.pos[self.waitNode], e, self.waitNode)
			self.waitNode, self.waitEdge = nil, nil
		end
	elseif mode == "idle" then
		if now >= self.idleUntil then
			self:endIdle(now)
		elseif now >= self.nextSub then
			self:subIdle(now)
		end
	elseif mode == "talk" then
		if now >= (self.talkUntil or 0) then
			self:endTalk(now)
		end
	end
	if self.chase then
		self:chaseTick(now)
	elseif self.near then
		self:react(now)
	elseif now > self.lookUntil and now > self.gazeUntil and st and st.wantYaw ~= 0 then
		Anim.look(self.rig, 0, 0)
	end
	-- schedule / night changes (not in the middle of a chase / a walk-up to talk to the player: the
	-- new slot would send them off mid-sentence; the check runs again a few seconds after it ended)
	if now >= self.nextSchedule and mode ~= "talk" and mode ~= "follow" and mode ~= "member" and mode ~= "dodge" and not self.chase and not self.chatState and not self.knock then
		self.nextSchedule = now + 6 + rnd() * 4
		if self.named then
			ctx.Crowd.scheduleCheck(self, now, false)
		else
			ctx.Crowd.extraCheck(self, now)
		end
	end
end

-- a look around (not at the player)
function Agent:glanceAround(now: number)
	self.gazeUntil = now + 1.4 + rnd()
	Anim.look(self.rig, (rnd() - 0.5) * 1.8, (rnd() - 0.5) * 0.3)
end

-- the closest other agent within r studs that satisfies ok(agent)
function Agent:neighbour(r: number, ok: ((any) -> boolean)?): any?
	local best, bd = nil, r * r
	for _, o in ctx.Crowd.agents do
		if o ~= self and not o.gone then
			local dx, dz = o.pos.X - self.pos.X, o.pos.Z - self.pos.Z
			local d2 = dx * dx + dz * dz
			if d2 < bd and (not ok or ok(o)) then
				best, bd = o, d2
			end
		end
	end
	return best
end

local function isSitting(o: any): boolean
	return o.sitting == true or o.sitGround == true
end

-- small changes while idling (every Config.SubIdle s)
function Agent:subIdle(now: number)
	self.nextSub = now + range(Config.SubIdle)
	if self.clubGuest or self.companion then
		return
	end
	local rig = self.rig
	local kind = self.idleKind
	local plan = self.plan
	local r = rnd()
	if plan and plan.kind == "queueing" then
		local hype = Night.hype(ctx.clock())
		self.queueYaw = self.queueYaw or self.faceYaw
		if r < 0.28 then
			local nb = self:neighbour(3.2, function(o)
				return o.plan ~= nil and o.plan.kind == "queueing"
			end)
			if nb then
				self.faceYaw = yawOf(nb.pos.X - self.pos.X, nb.pos.Z - self.pos.Z)
				Anim.setRestPose(rig, "chat")
				return
			end
		end
		self.faceYaw = self.queueYaw
		if hype > 0.6 and r < 0.6 then
			Anim.setRestPose(rig, "sway")
		elseif r < 0.78 then
			Anim.setRestPose(rig, "phone")
		elseif r < 0.9 then
			Anim.setRestPose(rig, "cross")
		else
			Anim.setRestPose(rig, nil)
			self:setAnim(if rnd() < 0.5 then "idle2" else "idle")
			self:glanceAround(now)
		end
		return
	end
	if kind == "photo" then
		if r < 0.35 then
			Anim.setRestPose(rig, "photo")
		elseif r < 0.55 then
			Anim.setRestPose(rig, "selfie")
		elseif r < 0.8 then
			Anim.setRestPose(rig, "phone") -- checking the shot
		else
			Anim.setRestPose(rig, nil)
			self:glanceAround(now)
		end
	elseif kind == "sit" then
		local nb = self:neighbour(3, isSitting)
		if nb and r < 0.4 then
			Anim.setRestPose(rig, "chat")
			self.gazeUntil = now + 3
			local lx, lz = nb.pos.X - self.pos.X, nb.pos.Z - self.pos.Z
			local c, s = math.cos(self.yaw), math.sin(self.yaw)
			Anim.look(rig, math.atan2(-(lx * c - lz * s), -(lx * s + lz * c)), 0)
		elseif r < 0.6 then
			Anim.setRestPose(rig, "phone")
		elseif r < 0.68 then
			Anim.flash(rig, "stretch", 2.8)
		else
			Anim.setRestPose(rig, nil)
			self:glanceAround(now)
		end
	elseif kind == "groundsit" or kind == "groundphone" then
		if self.wasLying and r < 0.35 then
			-- back to sunbathing
			self.wasLying = nil
			self.idleKind = "sunbathe"
			self.sitGround = false
			Anim.legs(rig, nil)
			self.lying = true
			self:setAnim("none")
			Anim.setRestPose(rig, "lie")
			self.moved = true
		elseif r < 0.5 then
			Anim.setRestPose(rig, "phone")
		else
			Anim.setRestPose(rig, "lean")
			self:glanceAround(now)
		end
	elseif kind == "sunbathe" then
		if r < 0.14 then
			-- sit up on the towel for a while
			self.wasLying = true
			self.lying = false
			self.idleKind = "groundphone"
			self.sitGround = true
			Anim.legs(rig, "ground")
			self:setAnim("idle")
			Anim.setRestPose(rig, "phone")
			self.moved = true
		end
	elseif kind == "watch" then
		local drone = plan and plan.kind == "watch"
		if drone and r < 0.4 then
			Anim.setRestPose(rig, "photo")
		elseif r < 0.12 then
			Anim.flash(rig, "clap", 2.2)
		elseif r < 0.4 then
			Anim.setRestPose(rig, "cross")
		elseif r < 0.55 then
			Anim.setRestPose(rig, "phone")
		else
			Anim.setRestPose(rig, nil)
			if not drone then
				self:glanceAround(now)
			end
		end
	elseif kind == "phone" or kind == "idle" or kind == "look" or kind == "customer" then
		if kind == "look" and r < 0.6 then
			self:glanceAround(now)
			return
		end
		if r < 0.35 then
			Anim.setRestPose(rig, "phone")
		elseif r < 0.48 then
			Anim.setRestPose(rig, "cross")
		elseif r < 0.62 then
			Anim.setRestPose(rig, nil)
			self:setAnim(if self.animState == "idle2" then "idle" else "idle2")
		else
			Anim.setRestPose(rig, IDLE_POSE[kind])
			self:glanceAround(now)
		end
	elseif kind == "chat" then
		if r < 0.2 then
			Anim.setRestPose(rig, "phone")
		elseif r < 0.3 then
			Anim.flash(rig, "clap", 1.2) -- laughing
		else
			Anim.setRestPose(rig, "chat")
		end
	elseif kind == "eat" then
		if r < 0.25 then
			Anim.setRestPose(rig, "phone")
		else
			Anim.setRestPose(rig, "eat")
		end
	end
end

local function lineFor(self: any, kind: string): string?
	local C = Citizens
	if not C then
		return nil
	end
	local c = self.c
	local tier = if self.named then ctx.SocialUI.tier(self.id) else 1
	local reg = if tier >= 3 then "c" else "p"
	local speech = (c and c.speech) or "std"
	local vars = { name = ctx.player.DisplayName }
	if kind == "lure" then
		local bank = C.CLUB_LINES and C.CLUB_LINES[reg]
		local list = bank and (bank[speech] or bank.std)
		local s = list and list[1 + math.floor(rnd() * #list)]
		return s and C.fill(s, vars)
	elseif kind == "greet" and self.named then
		local ok, lines = pcall(C.linesFor, self.id, tier, ctx.clock(), true)
		if ok and type(lines) == "table" and #lines > 0 then
			return C.fill(lines[1 + math.floor(rnd() * math.min(#lines, 4))], vars)
		end
	end
	return nil
end

-- a short reaction line (bump / car / horn), rate limited across the crowd
function Agent:quip(kind: string, chance: number)
	if rnd() > chance or not ctx.Crowd.canSay(os.clock()) then
		return
	end
	if kind == "bump" and self.type ~= "plain" then
		local l = self:typeLine("bumped")
		if l then
			ctx.SocialUI.say(self, l, 3)
			return
		end
	end
	local busan = self.c and self.c.speech == "busan"
	local list = (busan and LINES[kind .. "Busan"]) or LINES[kind]
	if list then
		ctx.SocialUI.say(self, pick(list), 3)
	end
end

-- head toward a world point for dur s
function Agent:lookAtPoint(p: Vector3, dur: number, now: number)
	local lx, lz = p.X - self.pos.X, p.Z - self.pos.Z
	local c, s = math.cos(self.yaw), math.sin(self.yaw)
	local x = lx * c - lz * s
	local z = -(lx * s + lz * c)
	self.gazeUntil = now + dur
	Anim.look(self.rig, math.atan2(-x, z), 0)
end

-- the player walked into us (Crowd, per frame)
function Agent:bump(now: number, pp: Vector3)
	if now - self.bumpAt < Config.BumpCooldown or self.mode == "dodge" or self.mode == "talk" or self.companion or self.clubGuest or self.knock then
		return
	end
	self.bumpAt = now
	if self.type == "drunk" and BUMP and not (self.sitting or self.lying or self.sitGround or self.napping) then
		-- 주정뱅이 bumps into people by accident: a light stagger for both
		local dx0, dz0 = self.pos.X - pp.X, self.pos.Z - pp.Z
		local d0 = math.max(0.05, math.sqrt(dx0 * dx0 + dz0 * dz0))
		self:knockDown(dx0 / d0, dz0 / d0, "stagger", nil)
		self:hitPlayer(-dx0 / d0, -dz0 / d0, "stagger", self:typeLine("accident"))
		return
	end
	if self.type == "fool" and BUMP and now - self.lastFoolBump > BUMP.FOOL.bumpCooldown and not (self.sitting or self.lying or self.sitGround or self.napping) and math.abs(pp.Y - self.pos.Y) < 4 then
		-- walked into the 동네바보: he shoulder-bumps you right back, giggling
		self:foolBump(now, pp)
		return
	end
	local dx, dz = self.pos.X - pp.X, self.pos.Z - pp.Z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 0.05 then
		dx, dz = self:right()
		d = 1
	end
	dx, dz = dx / d, dz / d
	if not (self.sitting or self.lying or self.sitGround) then
		self:nudge(self.nudgeX + dx * 2.2, self.nudgeZ + dz * 2.2, 1.6, 9)
		if self.mode == "walk" then
			self.pauseUntil = now + 0.8
		end
		Anim.flash(self.rig, "startle", 0.7)
	end
	self.lookUntil = now + 2
	self:quip("bump", 0.65)
end

-- a car is about to hit us (Crowd): jump / run sideways away from its path
function Agent:dive(now: number, ax: number, az: number, carPos: Vector3)
	if self.mode == "dodge" or self.clubGuest or self.companion or self.mode == "follow" or self.riding then
		return
	end
	if self.mode == "talk" then
		self.mode = "idle"
	end
	ctx.Crowd.queue.leave(self)
	if self.leader then
		ctx.Crowd.detachMember(self)
	end
	self:releasePoi()
	self.sitting, self.lying = false, false
	if self.sitGround then
		self.sitGround = false
		Anim.legs(self.rig, nil)
	end
	local sp = range(Config.DiveSpeed)
	ctx.Crowd.stats.dives += 1
	self.mode = "dodge"
	self.dodgeX, self.dodgeZ = ax * sp, az * sp
	self.dodgeUntil = now + 0.5 + rnd() * 0.35
	self.dodgeFrom = carPos
	self.faceYaw = nil
	self.nav = nil
	self.nudgeX, self.nudgeZ, self.nudgeTX, self.nudgeTZ = 0, 0, 0, 0
	Anim.stopGesture(self.rig)
	Anim.setRestPose(self.rig, nil)
	Anim.flash(self.rig, "startle", 1.6)
	self.moved = true
end

function Agent:afterDodge(now: number)
	self.speed = 0
	local c = self.dodgeFrom or self.pos
	self.afterDive = true
	self:idleFor("idle", 1.3 + rnd() * 0.8, now, yawOf(c.X - self.pos.X, c.Z - self.pos.Z))
	Anim.flash(self.rig, "startle", 0.9)
	self:quip("car", 0.85)
end

-- a horn nearby: turn toward it, step back a little
function Agent:hornReact(now: number, carPos: Vector3)
	if self.mode == "dodge" or self.clubGuest or self.companion or self.mode == "talk" then
		return
	end
	self:lookAtPoint(carPos, 1.6, now)
	local dx, dz = self.pos.X - carPos.X, self.pos.Z - carPos.Z
	local d = math.max(0.1, math.sqrt(dx * dx + dz * dz))
	self:nudge(dx / d * 1.2, dz / d * 1.2, 1.4, 5)
	self:quip("horn", 0.3)
end

function Agent:react(now: number)
	local Crowd = ctx.Crowd
	local pp, pv = Crowd.playerPos(), Crowd.playerVel()
	local st = self.rig.anim
	if not pp or Crowd.playerSeated() then
		-- in a vehicle: cars have their own reactions (Crowd)
		if st and now > self.lookUntil and now > self.gazeUntil and st.wantYaw ~= 0 then
			Anim.look(self.rig, 0, 0)
		end
		return
	end
	local dx, dz = pp.X - self.pos.X, pp.Z - self.pos.Z
	local d = math.sqrt(dx * dx + dz * dz)
	if d > 30 or math.abs(pp.Y - self.pos.Y) > 14 then
		if st and now > self.lookUntil and now > self.gazeUntil and st.wantYaw ~= 0 then
			Anim.look(self.rig, 0, 0)
		end
		return
	end
	local fx, fz = -math.sin(self.yaw), -math.cos(self.yaw)
	local toX, toZ = dx / math.max(d, 0.01), dz / math.max(d, 0.01)
	local ahead = fx * toX + fz * toZ -- > 0: the player is in front
	local pvx, pvz = pv.X, pv.Z
	local pspeed = math.sqrt(pvx * pvx + pvz * pvz)
	if self.knock then
		return
	end
	if self:typeReact(now, pp, d, toX, toZ, ahead, pspeed) then
		return
	end
	local mode = self.mode
	local sprinting = pspeed > Config.SprintSpeed
	local standing = not (self.sitting or self.lying or self.sitGround)
	local tier = if self.named then ctx.SocialUI.tier(self.id) else 1

	-- 1. make way early: time to the closest approach of the player's path and ours
	if standing and (mode == "walk" or mode == "idle" or mode == "wait") and not self.clubGuest then
		local vx, vz = 0, 0
		if mode == "walk" then
			vx, vz = fx * self.speed, fz * self.speed
		end
		local rvx, rvz = pvx - vx, pvz - vz -- the player's velocity relative to us
		local rv2 = rvx * rvx + rvz * rvz
		if rv2 > 4 then
			local ttc = -(dx * rvx + dz * rvz) / rv2
			if ttc > 0 and ttc < Config.AvoidTTC then
				local cx, cz = dx + rvx * ttc, dz + rvz * ttc -- where the player passes us
				local miss = math.sqrt(cx * cx + cz * cz)
				if miss < 2.6 then
					local ox, oz
					if miss > 0.3 then
						ox, oz = -cx / miss, -cz / miss
					else
						local rv = math.sqrt(rv2)
						ox, oz = -rvz / rv, rvx / rv
						if (ox * fx + oz * fz) < 0 and rnd() < 0.5 then
							ox, oz = -ox, -oz
						end
					end
					local amount = math.min(Config.AvoidShift, 2.6 - miss + 0.6)
					self:nudge(ox * amount, oz * amount, ttc + 1.1, Config.AvoidRate)
					if mode == "walk" and ttc < 0.5 and d < 3 then
						self.pauseUntil = now + 0.6
					end
				end
			end
		end
	end

	-- 2. glances (not stares): a sprinting player / somebody walking right past us; at most
	--    Config.GlanceMax people look at once
	if now >= self.lookUntil and now >= self.glanceAt then
		self.glanceAt = now + 1.8 + rnd() * 2.5
		local chance = 0
		if sprinting and d < 12 then
			chance = Config.GlanceChance * 1.25
		elseif d < 5.5 and ahead > 0.35 and pspeed > 2 then
			chance = Config.GlanceChance * (if self.named then 1 else 0.6)
		end
		if chance > 0 and rnd() < chance and Crowd.takeGlance(now) then
			self.lookUntil = now + 0.8 + rnd() * 1.2
		end
	end
	if sprinting and d < 3 and standing and mode ~= "walk" and now >= self.nudgeUntil then
		local side = (fx * toZ - fz * toX)
		local rx, rz = self:right()
		local s = if side > 0 then 1.2 else -1.2
		self:nudge(rx * s, rz * s, 1.2, 6)
	end

	-- 3. walking up to a named citizen: they slow down and look ("hey" beat); once the 말 걸기 prompt
	--    has been up a moment they stop for a few seconds
	if self.named and mode == "walk" and d < 12 then
		local hx, hz
		if pspeed > 2 then
			hx, hz = pvx / pspeed, pvz / pspeed
		else
			local lv = Crowd.playerLook()
			hx, hz = lv.X, lv.Z
		end
		if -(hx * toX + hz * toZ) > 0.77 then
			self.heyUntil = now + 1.2
			self.lookUntil = math.max(self.lookUntil, now + 1.2)
		end
	end
	if self.promptSince and now - self.promptSince > 0.6 and not self.heyPaused then
		self.heyPaused = true
		if mode == "walk" then
			self.pauseUntil = now + (if tier >= 2 then 3 else 1.8)
			self.lookUntil = math.max(self.lookUntil, self.pauseUntil)
		end
	end

	-- 4. friends wave (친한 사이+), once in a while; an arm wave while walking / sitting
	if self.named and d < 22 and now - self.lastWave > 110 and mode ~= "talk" and not self.lying and tier >= 3 then
		self.lastWave = now
		self.lookUntil = now + 3
		if mode == "walk" or not standing then
			Anim.flash(self.rig, "wavep", 1.8)
		else
			Anim.gesture(self.rig, "wave")
		end
		local line = lineFor(self, "greet")
		if line then
			ctx.SocialUI.say(self, line, 4)
		end
	end

	-- 5. evening: the club pitch (one person at a time, not the same person again, never right
	--    after the player walked away from one)
	if self.lure and d < 13 and mode ~= "talk" and Night.isLureTime(ctx.clock()) and Crowd.canLure(self, now) then
		local lookAt = -(toX * pvx + toZ * pvz) -- player walking toward us
		if lookAt > -2 then
			Crowd.noteLure(self, now)
			self.lookUntil = now + 4
			local line = lineFor(self, "lure")
			if line then
				ctx.SocialUI.say(self, line, 5)
			end
			local e = Night.clubEntrance()
			if mode == "walk" or not standing then
				Anim.flash(self.rig, "pointp", 1.6)
			else
				if e and e.door then
					self.faceYaw = yawOf(e.door.X - self.pos.X, e.door.Z - self.pos.Z)
					task.delay(1.6, function()
						if not self.gone and self.mode == "idle" then
							self.faceYaw = yawOf(pp.X - self.pos.X, pp.Z - self.pos.Z)
						end
					end)
				end
				Anim.gesture(self.rig, "point")
			end
		end
	end

	-- 6. head: the player when told to (glance, talk, hey) or a known face close in front; anyone
	--    the player walks straight at
	local look = now < self.lookUntil or mode == "talk"
	if not look and tier >= 2 and d < 12 and ahead > -0.2 then
		look = true
	end
	if not look and d < 4.5 and ahead > 0.5 and pspeed > 2 and -(toX * pvx + toZ * pvz) / pspeed > 0.6 then
		look = true
	end
	if look then
		local lx = toX * math.cos(self.yaw) - toZ * math.sin(self.yaw) -- player in rig-local x (right)
		local lz = -(toX * math.sin(self.yaw) + toZ * math.cos(self.yaw)) -- forward component
		local yaw = math.atan2(-lx, lz)
		local pitch = math.atan2((pp.Y + 1.5) - (self.pos.Y + self.ground + 1.6 * self.scale), math.max(d, 1)) * 0.6
		Anim.look(self.rig, yaw, pitch)
	elseif st and st.wantYaw ~= 0 and now > self.gazeUntil then
		Anim.look(self.rig, 0, 0)
	end
end

-------------------------------------------------------------------------------------------------
-- talking (말 걸기)
-------------------------------------------------------------------------------------------------
function Agent:beginTalk(now: number, dur: number?)
	if self.mode == "follow" then
		self.talkFollow = true
	end
	if self.mode == "dodge" then
		return
	end
	self.talkPrev = { mode = self.mode, idleKind = self.idleKind, idleUntil = self.idleUntil, faceYaw = if self.clubGuest then self.faceYaw else nil }
	self.mode = "talk"
	self.talkUntil = now + (dur or 30)
	self.want = 0
	self.speed = 0
	self:stopMoving()
	local pp = ctx.Crowd.playerPos()
	if pp and not self.lying then
		self.faceYaw = yawOf(pp.X - self.pos.X, pp.Z - self.pos.Z)
	end
	self.lookUntil = now + (dur or 30)
	if self.lying then
		self.lying = false
		Anim.setRestPose(self.rig, nil)
	end
	if not self.sitting and not self.sitGround then
		self:setAnim("idle")
		Anim.setRestPose(self.rig, "chat")
	end
	ctx.Crowd.noteTalk(self)
end

function Agent:endTalk(now: number)
	if self.mode ~= "talk" then
		return
	end
	self.lookUntil = now
	Anim.setRestPose(self.rig, nil)
	local prev = self.talkPrev
	self.talkPrev = nil
	if self.talkFollow then
		self.talkFollow = nil
		self.mode = "follow"
		return
	end
	if prev and prev.mode == "idle" and prev.idleUntil > now then
		self.mode = "idle"
		self.idleUntil = prev.idleUntil
		self.idleKind = prev.idleKind
		self.lying = prev.idleKind == "sunbathe"
		self:setAnim(IDLE_BASE[prev.idleKind] or "idle")
		Anim.setRestPose(self.rig, IDLE_POSE[prev.idleKind])
		if prev.faceYaw then
			self.faceYaw = prev.faceYaw
		end
		self.moved = true
		return
	end
	if self.plan and (self.plan.kind == "queueing") then
		self.mode = "idle"
		self.idleUntil = now + 999
		return
	end
	self:nextPlan(now)
end

-- say something with a gesture (emote hints from SocialState lines)
local EMOTE = { greet = "wave", cheer = "cheer", dance = "dance", shy = "laugh", phone = nil, think = nil, refuse = nil }
function Agent:emote(kind: string?)
	if not kind or self.lying then
		return
	end
	local g = EMOTE[kind]
	if kind == "think" then
		Anim.flash(self.rig, "think", 2.5)
	elseif kind == "phone" then
		Anim.setRestPose(self.rig, "phone")
	elseif kind == "refuse" then
		Anim.look(self.rig, 0.5, -0.1)
		task.delay(0.35, function()
			if not self.gone then
				Anim.look(self.rig, -0.5, -0.1)
			end
		end)
	elseif g == "dance" then
		self:setAnim("dance")
	elseif g and (self.sitting or self.sitGround) then
		if g == "wave" then
			Anim.flash(self.rig, "wavep", 1.6)
		end
	elseif g then
		Anim.gesture(self.rig, g)
	end
end

-------------------------------------------------------------------------------------------------
-- NPC TYPES (npc_types): 폭력적 / 동네바보 / 걸렁뱅이 / 주정뱅이 street behaviours + 어깨빵 knockdowns.
-- Everything here runs only for close agents (Agent.react) or inside the knock timeline.
-------------------------------------------------------------------------------------------------
-- a line from the type bank (GwangalliSocialShared.TYPE_LINES, Busan dialect for busan speakers)
function Agent:typeLine(kind: string): string?
	if not SOCIAL or type(SOCIAL.typeLine) ~= "function" then
		return nil
	end
	local ok, l = pcall(SOCIAL.typeLine, self.type, kind, self.c and self.c.speech or "std")
	return if ok then l else nil
end

local function remoteFire(kind: string, payload: any)
	local f = ctx.bumpRemote
	if not f or not f.Parent then
		local folder = BUMP and game:GetService("ReplicatedStorage"):FindFirstChild(BUMP.Folder)
		f = folder and folder:FindFirstChild(BUMP.Remote.Action)
		ctx.bumpRemote = f
	end
	if f and f:IsA("RemoteEvent") then
		f:FireServer(kind, payload)
	end
end

-- the LOCAL player gets staggered / knocked down by this pedestrian (fool passing by, drunk
-- accident, violent shove). The motion plays here at once; the server only learns about it
-- ("fell") to take the 체력 and open the fool's card: it can never hurt anyone else.
function Agent:hitPlayer(dx: number, dz: number, outcome: string, text: string?)
	if not BUMP or not SOCIAL then
		return
	end
	local ch = ctx.player.Character
	if not ch or BUMP.isDown() then
		return
	end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Sit or hum.PlatformStand then
		return
	end
	if ctx.Crowd.playerInDialog() then
		return -- talking to somebody (dialog card open): nobody knocks you over mid-sentence
	end
	local ok = BUMP.knockCharacter(ch, dx, dz, outcome, { anim = ctx.AnimLib })
	if not ok then
		return
	end
	local head = ch:FindFirstChild("Head")
	local pool = BUMP.bubbles({ types = SOCIAL and SOCIAL.TYPES })
	if pool and head then
		local puk = if outcome == "knockdown" then SOCIAL.KNOCK_PUK[1 + math.floor(rnd() * #SOCIAL.KNOCK_PUK)] else SOCIAL.PUK[1 + math.floor(rnd() * #SOCIAL.PUK)]
		pool:say(head, puk, "plain", 1.3, 3.4)
	end
	BUMP.shakeCamera(if outcome == "knockdown" then BUMP.SHAKE else 0.14, 0.4)
	if text then
		ctx.SocialUI.say(self, text, 3.5)
	end
	ctx.Crowd.stats.hits = (ctx.Crowd.stats.hits or 0) + 1
	remoteFire("fell", { id = self.id, outcome = outcome, pos = BUMP.packV(self.pos) })
end

-- 어깨빵 landed on this pedestrian (the server decided the outcome): fall / stagger timeline
function Agent:knockDown(dx: number, dz: number, outcome: string, puk: string?)
	if not BUMP or self.knock or self.riding or self.clubGuest then
		return false
	end
	local now = os.clock()
	if self.mode == "dodge" then
		return false
	end
	if self.mode == "talk" then
		self:endTalk(now)
	end
	self:releasePoi()
	ctx.Crowd.queue.leave(self)
	if self.leader then
		ctx.Crowd.detachMember(self)
	end
	local prevMode = self.mode
	self.knock = { t0 = now, dx = dx, dz = dz, outcome = outcome, puk = puk, k = 0, phase = "", prev = prevMode, wasSitting = self.sitting or self.napping }
	self.chase = nil -- (a chaser that gets bumped starts over after it is back on its feet)
	self.sitting, self.lying, self.napping = false, false, false
	if self.sitGround then
		self.sitGround = false
		Anim.legs(self.rig, nil)
	end
	self.chatState = nil
	self.want, self.speed = 0, 0
	self.faceYaw = nil
	self.nudgeTX, self.nudgeTZ, self.nudgeUntil = 0, 0, 0
	Anim.stopGesture(self.rig)
	Anim.cancelFlash(self.rig)
	self:setAnim("idle")
	Anim.setRestPose(self.rig, if outcome == "knockdown" then "knock" else "stagger")
	if puk then
		local pool = BUMP.bubbles({ types = SOCIAL and SOCIAL.TYPES })
		if pool and self.rig.root then
			pool:say(self.rig.root, puk, "plain", 1.2, 2.1 * self.scale + 1.6)
		end
	end
	ctx.Crowd.stats.knocks = (ctx.Crowd.stats.knocks or 0) + 1
	-- witnesses
	local n = 0
	for _, o in ctx.Crowd.agents do
		if o ~= self and not o.gone and not o.knock and o.near and n < 2 then
			local ox, oz = o.pos.X - self.pos.X, o.pos.Z - self.pos.Z
			if ox * ox + oz * oz < 14 * 14 and rnd() < 0.5 then
				n += 1
				o:lookAtPoint(self.pos, 2.5, now)
				local l = o:typeLine("witness")
				if l and ctx.Crowd.canSay(now) then
					ctx.SocialUI.say(o, l, 3)
				end
			end
		end
	end
	self.moved = true
	return true
end

function Agent:stepKnock(_dt: number, now: number)
	local kn = self.knock
	if not kn or not BUMP then
		self.knock = nil
		return
	end
	local phase, k = BUMP.knockPhase(now - kn.t0, kn.outcome)
	kn.k = k
	self.moved = true
	if phase ~= kn.phase then
		kn.phase = phase
		if phase == "getup" then
			Anim.setRestPose(self.rig, "stagger")
		elseif phase == "done" then
			self:afterKnock(now)
		end
	end
end

-- back on the feet: react by type, then go on with the day
function Agent:afterKnock(now: number)
	local kn = self.knock
	self.knock = nil
	Anim.setRestPose(self.rig, nil)
	local pp = ctx.Crowd.playerPos()
	local face = if pp then yawOf(pp.X - self.pos.X, pp.Z - self.pos.Z) else self.yaw
	local line = self:typeLine(if kn and kn.outcome == "knockdown" then "down" else "bumped")
	if self.type == "violent" then
		line = self:typeLine("bumped")
		self.lookUntil = now + 4
		Anim.gesture(self.rig, "point")
		-- the player ran off before the bump back landed (the server only bumps back within 14
		-- studs): run after them for 6-8 s, then give up
		local ch = ctx.player.Character
		local knocked = ch and ch:GetAttribute(BUMP and BUMP.Attr.Knocked or "GwangalliKnocked")
		if pp and BUMP and not knocked and not ctx.Crowd.playerSeated() then
			local dx, dz = pp.X - self.pos.X, pp.Z - self.pos.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > 6 and d < 32 and math.abs(pp.Y - self.pos.Y) < 6 then
				if line then
					ctx.SocialUI.say(self, line, 2)
				end
				self.node = W.nearest(self.pos, 40)
				self.prev = nil
				self:startChase(now, pp)
				return
			end
		end
	elseif self.type == "fool" then
		line = self:typeLine("bumped")
		Anim.gesture(self.rig, "laugh")
	elseif self.type == "beggar" then
		line = self:typeLine("beg")
		Anim.flash(self.rig, "startle", 1.2)
	elseif self.type == "drunk" then
		line = self:typeLine("mumble")
	else
		Anim.flash(self.rig, "startle", 1.0)
	end
	if line then
		ctx.SocialUI.say(self, line, 3.5)
	end
	self.lookUntil = math.max(self.lookUntil, now + 2.5)
	self.node = W.nearest(self.pos, 40)
	self.prev = nil
	self:idleFor("idle", 1.6 + rnd() * 1.2, now, face)
end

-- the pedestrian's own 어깨빵 hit the player (fool passing by)
function Agent:foolBump(now: number, pp: Vector3)
	self.lastFoolBump = now
	local dx, dz = pp.X - self.pos.X, pp.Z - self.pos.Z
	local d = math.max(0.05, math.sqrt(dx * dx + dz * dz))
	local streak = ctx.player:GetAttribute(BUMP and BUMP.Attr.Streak or "BumpStreak")
	local outcome = if type(streak) == "number" and streak >= 2 then "knockdown" else "stagger"
	Anim.flash(self.rig, "pointp", 0.6)
	self:hitPlayer(dx / d, dz / d, outcome, self:typeLine("foolbump"))
	self.pauseUntil = now + 0.5
	self.lookUntil = now + 2
	ctx.Crowd.stats.foolBumps = (ctx.Crowd.stats.foolBumps or 0) + 1
	-- cannot bump the same player again for a while
	task.delay(1.2, function()
		if not self.gone and not self.knock then
			Anim.gesture(self.rig, "laugh")
		end
	end)
end

-- walk up to the player (chatty / beggar): off the graph for the last metres
function Agent:approachSpot(now: number, pp: Vector3, stopAt: number)
	local dx, dz = self.pos.X - pp.X, self.pos.Z - pp.Z
	local d = math.max(0.1, math.sqrt(dx * dx + dz * dz))
	local spot = Vector3.new(pp.X + dx / d * stopAt, self.pos.Y, pp.Z + dz / d * stopAt)
	self.chatSpot = spot
	self.chatPP = pp
	local speed = self.walkSpeed * (if self.type == "beggar" then 0.8 else 1.15)
	if flatDist2(self.pos, spot) < 14 then
		-- the last metres go straight (graph routing would walk off to the nearest node first)
		self:startNav({ mode = "points", pts = { spot } }, now, speed)
	else
		self:goToSpot(spot, now, speed)
	end
end

function Agent:approachPlayer(now: number, pp: Vector3, stopAt: number, state: string)
	self.chatState = state
	self.chatAt = now
	self.chatUntil = now + 14
	self.chatRetarget = now + 1
	self.sitting, self.lying, self.napping = false, false, false
	if self.sitGround then
		self.sitGround = false
		Anim.legs(self.rig, nil)
	end
	Anim.setRestPose(self.rig, nil)
	self:releasePoi()
	ctx.Crowd.queue.leave(self)
	self.plan = { kind = "wander", act = "walk", center = self.pos, radius = 120, resume = self.plan }
	self:approachSpot(now, pp, stopAt)
	self.lookUntil = now + 14
end

-------------------------------------------------------------------------------------------------
-- 폭력적인 NPC: the chase (6-8 s, BUMP.VIOLENT.chase) after a player bumped it and got away.
-- Runs from think() (not react) because the chaser is usually behind the player, off-screen.
-------------------------------------------------------------------------------------------------
function Agent:startChase(now: number, pp: Vector3)
	if not BUMP or self.chase or self.riding or self.clubGuest or self.companion then
		return
	end
	if self.mode == "talk" then
		self:endTalk(now)
	end
	self:releasePoi()
	ctx.Crowd.queue.leave(self)
	if self.leader then
		ctx.Crowd.detachMember(self)
	end
	self.sitting, self.lying, self.napping, self.chatState = false, false, false, nil
	if self.sitGround then
		self.sitGround = false
		Anim.legs(self.rig, nil)
	end
	Anim.setRestPose(self.rig, nil)
	Anim.cancelFlash(self.rig)
	self.walkPose = nil
	self.nudgeTX, self.nudgeTZ, self.nudgeUntil = 0, 0, 0
	self.chase = { untilT = now + range(BUMP.VIOLENT.chase), nextHit = now + 0.4, retarget = 0, started = now }
	self.plan = self.plan or { kind = "wander", act = "walk", center = self.pos, radius = 120 }
	self.lookUntil = self.chase.untilT
	ctx.Crowd.stats.chases = (ctx.Crowd.stats.chases or 0) + 1
	local l = self:typeLine("chase")
	if l then
		ctx.SocialUI.say(self, l, 3)
	end
	self:chaseStep(now, pp)
end

-- aim straight at where the player is now (a short "points" nav, refreshed ~3 times a second)
function Agent:chaseStep(now: number, pp: Vector3)
	local target = Vector3.new(pp.X, self.pos.Y, pp.Z)
	self.nav = { mode = "points", pts = { target }, i = 1 }
	self.mode = "walk"
	self.faceYaw = nil
	self.pauseUntil = 0
	self.want = BUMP.VIOLENT.chaseSpeed
	self:segTo(target, nil, nil)
	self.node = nil
	self.chase.retarget = now + 0.35
end

function Agent:endChase(now: number, caught: boolean)
	local chs = self.chase
	self.chase = nil
	if not chs then
		return
	end
	self.want, self.speed, self.nav = 0, 0, nil
	local pp = ctx.Crowd.playerPos()
	local face = if pp then yawOf(pp.X - self.pos.X, pp.Z - self.pos.Z) else self.yaw
	if not caught then
		local l = self:typeLine("giveup")
		if l then
			ctx.SocialUI.say(self, l, 3)
		end
		Anim.flash(self.rig, "think", 1.6)
	end
	self.node = W.nearest(self.pos, 40)
	self.prev = nil
	self.lookUntil = now + 3
	self:idleFor("idle", 2.2 + rnd() * 1.6, now, face)
end

function Agent:chaseTick(now: number)
	local chs = self.chase
	if not chs or not BUMP then
		self.chase = nil
		return
	end
	local Crowd = ctx.Crowd
	local pp = Crowd.playerPos()
	if not pp or Crowd.playerSeated() or now > chs.untilT then
		self:endChase(now, false)
		return
	end
	local dx, dz = pp.X - self.pos.X, pp.Z - self.pos.Z
	local d = math.sqrt(dx * dx + dz * dz)
	if d > 34 or math.abs(pp.Y - self.pos.Y) > 6 then
		self:endChase(now, false)
		return
	end
	local ch = ctx.player.Character
	if ch and ch:GetAttribute(BUMP.Attr.Knocked) then
		-- somebody (the server's bump back) already put the player down: no need to run
		self:endChase(now, true)
		return
	end
	if d < BUMP.FOOL.bumpReach + 0.3 and now >= chs.nextHit then
		-- caught up: the bump back lands (reported as "fell"; the server takes the 체력)
		Anim.flash(self.rig, "pointp", 0.6)
		self:hitPlayer(dx / math.max(d, 0.05), dz / math.max(d, 0.05), "knockdown", self:typeLine("retaliate"))
		self:endChase(now, true)
		return
	end
	if now >= chs.retarget or self.mode ~= "walk" then
		self:chaseStep(now, pp)
	end
	self:updateWalkAnim()
end

-- stopped next to the player: the opener bubble + the server opens the card
function Agent:startChat(now: number, pp: Vector3)
	self.chatState = "talking"
	self.chatUntil = now + 45
	self:beginTalk(now, 45)
	local kind = if self.type == "beggar" then "beg" else "opener"
	local l = self:typeLine(kind)
	if l then
		ctx.SocialUI.say(self, l, 5)
	end
	if self.type == "beggar" then
		Anim.setRestPose(self.rig, "eat") -- the cup held out
		remoteFire("beg", { id = self.id, pos = BUMP.packV(self.pos) })
	else
		Anim.gesture(self.rig, "wave")
		remoteFire("chat", { id = self.id, pos = BUMP.packV(self.pos) })
	end
	ctx.Crowd.noteChat(self, now)
	ctx.Crowd.stats.chats = (ctx.Crowd.stats.chats or 0) + 1
end

function Agent:endChat(now: number, shrug: boolean)
	local st = self.chatState
	self.chatState = nil
	if shrug then
		local l = self:typeLine("shrug")
		if l then
			ctx.SocialUI.say(self, l, 3)
		end
		Anim.flash(self.rig, "startle", 0.8)
	end
	if self.mode == "talk" then
		self:endTalk(now)
	elseif st == "approach" then
		self:nextPlan(now)
	end
end

-- the per-type reactions; returns true when the generic reactions should be skipped this tick
function Agent:typeReact(now: number, pp: Vector3, d: number, toX: number, toZ: number, ahead: number, pspeed: number): boolean
	if not BUMP or not SOCIAL then
		return false
	end
	local t = self.type
	local Crowd = ctx.Crowd
	if self.chase then
		return true -- chaseTick (think) runs the chase
	end
	-- chatty / beggar approach in progress
	local cs = self.chatState
	if cs == "approach" then
		if d > 22 or now > (self.chatUntil or 0) then
			self:endChat(now, d <= 30)
		elseif d <= BUMP.CHAT_STOP + 1.6 or (d <= BUMP.CHAT_STOP + 3 and self.mode ~= "walk" and self.mode ~= "wait" and self.mode ~= "dodge") then
			-- close enough (arrived a step short: the crowd spacing keeps people apart)
			self:startChat(now, pp)
		elseif self.mode == "wait" or self.mode == "dodge" then
			-- a crossing light / a car: the walk goes on after it
		elseif self.mode ~= "walk" or (self.chatPP and flatDist2(pp, self.chatPP) > 3.5) then
			-- arrived short of the player, or they moved on: aim for them again (at most ~1 Hz)
			if now >= (self.chatRetarget or 0) then
				self.chatRetarget = now + 1
				self:approachSpot(now, pp, if self.type == "beggar" then 3.2 else BUMP.CHAT_STOP)
			end
		end
		return true
	elseif cs == "talking" then
		if d > 15 or now > (self.chatUntil or 0) or self.mode ~= "talk" then
			self:endChat(now, d > 15 and d < 40)
		end
		return true
	end
	-- ambient type lines now and then (the people around the player hear them)
	if t ~= "plain" and d < 18 and now >= self.nextTypeLine and self.mode ~= "talk" then
		self.nextTypeLine = now + 14 + rnd() * 16
		if Crowd.canSay(now) and rnd() < 0.7 then
			local kind = if t == "drunk" then (if rnd() < 0.5 then "mumble" else "hiccup") elseif t == "fool" then (if rnd() < 0.5 then "giggle" else "ambient") else "ambient"
			local l = self:typeLine(kind)
			if l then
				ctx.SocialUI.say(self, l, 3)
			end
		end
	end
	local standing = not (self.sitting or self.lying or self.sitGround or self.napping)
	if t == "violent" then
		-- glares (face the player), blocks the way for a moment, shoves when you stand too close too long
		if d < BUMP.VIOLENT.glare then
			self.lookUntil = math.max(self.lookUntil, now + 1)
			if self.mode == "idle" and standing then
				self.faceYaw = yawOf(pp.X - self.pos.X, pp.Z - self.pos.Z)
			end
			if now >= (self.nextGlare or 0) then
				self.nextGlare = now + 9 + rnd() * 8
				if Crowd.canSay(now) and rnd() < 0.6 then
					ctx.SocialUI.say(self, self:typeLine(if rnd() < 0.5 then "glare" else "insult") or "…", 3)
				end
			end
		end
		if self.mode == "walk" and d < BUMP.VIOLENT.block and ahead > 0.6 and standing and now >= (self.nextBlock or 0) then
			self.nextBlock = now + 25 + rnd() * 20
			self.pauseUntil = now + 2.2
			self.lookUntil = now + 2.5
			Anim.flash(self.rig, "cross", 2.2)
			if Crowd.canSay(now) then
				ctx.SocialUI.say(self, self:typeLine("block") or "…", 3)
			end
		end
		if d < BUMP.VIOLENT.shoveClose and standing and pspeed < 2 then
			self.closeSince = self.closeSince or now
			if now - self.closeSince > BUMP.VIOLENT.shoveAfter and now >= (self.nextShove or 0) then
				self.nextShove = now + 12
				self.closeSince = nil
				Anim.gesture(self.rig, "point")
				self:hitPlayer(toX, toZ, "stagger", self:typeLine("shove"))
			end
		else
			self.closeSince = nil
		end
		return false
	elseif t == "fool" then
		self.wobble = BUMP.FOOL.wobble
		-- passing by (or standing there as you pass): a deliberate shoulder bump
		if (self.mode == "walk" or (self.mode == "idle" and standing)) and d < BUMP.FOOL.bumpReach and now - self.lastFoolBump > BUMP.FOOL.bumpCooldown and math.abs(pp.Y - self.pos.Y) < 4 then
			self:foolBump(now, pp)
		end
		-- bumps into other pedestrians too
		if self.mode == "walk" and now - self.lastFoolBump > BUMP.FOOL.bumpCooldown * 0.5 and now >= (self.nextNpcBump or 0) then
			self.nextNpcBump = now + 2
			local o = self:neighbour(2.2, function(x)
				return x.mode == "walk" and not x.knock and not x.companion and not x.clubGuest
			end)
			if o then
				self.lastFoolBump = now
				local ox, oz = o.pos.X - self.pos.X, o.pos.Z - self.pos.Z
				local od = math.max(0.05, math.sqrt(ox * ox + oz * oz))
				o:knockDown(ox / od, oz / od, "stagger", nil)
				Anim.flash(self.rig, "pointp", 0.6)
				if Crowd.canSay(now) then
					ctx.SocialUI.say(self, self:typeLine("foolbump") or "히히", 2.5)
				end
			end
		end
	elseif t == "drunk" then
		self.wobble = BUMP.DRUNK.sway
		-- a nap on the bench
		if self.sitting and not self.napping and now >= (self.nextNap or 0) then
			self.nextNap = now + 40
			if rnd() < BUMP.DRUNK.napChance then
				self.napping = true
				self.idleUntil = math.max(self.idleUntil, now + range(BUMP.DRUNK.napTime))
				Anim.setRestPose(self.rig, "nap")
				self:setAnim("none")
				if Crowd.canSay(now) then
					ctx.SocialUI.say(self, self:typeLine("nap") or "쿨…", 3)
				end
				self.moved = true
			end
		end
		if self.napping then
			if self.mode ~= "idle" then
				self.napping = false
				Anim.setRestPose(self.rig, nil)
				self.moved = true
			elseif now >= (self.nextSnore or 0) and d < 14 then
				self.nextSnore = now + 5 + rnd() * 4
				if Crowd.canSay(now) then
					ctx.SocialUI.say(self, "쿨… 쿨…", 2.5)
				end
			end
			return true
		end
	elseif t == "beggar" then
		-- shuffles toward players within reach with the cup
		if d < BUMP.BEG_RANGE and d > 4 and (standing or self.sitting) and (self.mode == "walk" or self.mode == "idle") and now - self.chatAt > 90 and Crowd.canChat(now, self) and not Crowd.playerSeated() then
			self:approachPlayer(now, pp, 3.2, "approach")
			Anim.setRestPose(self.rig, "eat")
			return true
		end
	end
	-- somebody who talks to you first
	if self.chatty and t ~= "beggar" and d < BUMP.CHAT_RANGE and d > 5 and (standing or self.sitting) and (self.mode == "walk" or self.mode == "idle") and now - self.chatAt > BUMP.CHAT_COOLDOWN and Crowd.canChat(now, self) and not Crowd.playerSeated() and pspeed < 14 then
		self:approachPlayer(now, pp, BUMP.CHAT_STOP, "approach")
		return true
	end
	return false
end

return Agent
