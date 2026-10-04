-- Interact/Routine (server): the daily life of the city NPCs.
--   * SCHEDULE: Cast schedules by in-game hour (ctx.env().clock). "away" = off the block (no body);
--     a person appears at a portal / their spot out of the players' sight and walks in, and walks
--     off to a portal when their day here ends.
--   * ACTIVITIES run as cancellable threads (a conflict, a fright, a talk pauses them; they restart
--     afterwards). Every reservation (seat, queue slot) is a "hold" freed on cancel / despawn.
--     commute, stroll, photo, shop (GS25 광안리점: door -> browse -> queue -> order -> wait -> pickup
--     -> pay -> leave; hands off to JobWorld while a player works the 알바 shift), rest, hangout, roam,
--     beg, wander, drink, sleep, patrol, work (clerk), leave, lift (ElevatorButton ride)
--   * WALKING: routes over the nav graph (Actors.walkTo); a player standing in the way -> pause,
--     "잠시만요", side-step detour; three times -> annoyed (conflict level 1). A walk that never
--     arrives times out and the activity picks something else (no endless wall walking).
--   * INITIATIVES: what a person starts on their own when a player is near (greet, beg, prank, brag,
--     hassle, pick a fight, ask directions).

local Players = game:GetService("Players")

local Routine = {}

local I: any
local C: any
local Cast: any
local Actors: any
local Mind: any
local Talk: any
local Memory: any
local World: any
local Places: any
local Police: any

local rnd = Random.new()
local function range(t: { number }): number
	return t[1] + (t[2] - t[1]) * rnd:NextNumber()
end
local function pick(t: { any }): any
	return t[rnd:NextInteger(1, #t)]
end

Routine.allDay = false -- dev switch (Workspace.GwCityAllDay): everybody is around all day

---------------------------------------------------------------------------------------------------
-- helpers used by Mind
---------------------------------------------------------------------------------------------------
function Routine.nearPoint(from: Vector3, to: Vector3, dist: number): Vector3
	return Places.nearPoint(from, to, dist)
end

-- a walkable point near p (a nav node of the block), for fleeing / searching
function Routine.safePoint(_n: any, p: Vector3): Vector3?
	local Nav = Places.Nav
	if Nav and Nav.nearest and Nav.decode then
		local okC, cache = pcall(Nav.decode)
		local ok, node = pcall(Nav.nearest, p, 30)
		if okC and ok and node and cache.pos[node] then
			return cache.pos[node]
		end
	end
	return nil
end

function Routine.restPose(n: any): string
	if n.sitting then
		return n.sitting
	end
	return ""
end

-- how drunk a drunk is right now (rises through the night)
function Routine.drunkLevel(n: any): number
	local base = n.def.drunkBase
	if not base then
		return 0
	end
	local h = Mind.clock()
	local late = if h >= 22 or h < 3 then 0.15 elseif h >= 19 then 0.05 else -0.2
	return math.clamp(base + late, 0, 1)
end

---------------------------------------------------------------------------------------------------
-- bodies
---------------------------------------------------------------------------------------------------
local TYPE_OF = { thug = "violent", drunk = "drunk", homeless = "beggar", fool = "fool", police = "police", citizen = "plain", clerk = "plain" }
local COLOR_OF = { thug = { 230, 70, 70 }, drunk = { 200, 140, 90 }, homeless = { 160, 140, 110 }, fool = { 255, 194, 71 }, police = { 84, 140, 255 }, citizen = { 150, 170, 200 }, clerk = { 61, 200, 140 } }

local function playersNear(p: Vector3, r: number): boolean
	for _, pl in Players:GetPlayers() do
		local f = I.feetOf(pl)
		if f and (f - p).Magnitude < r then
			return true
		end
	end
	return false
end

local PORTALS = { "portalW", "portalE", "portalN" }
local function hiddenPortal(near: Vector3?): Vector3
	local best, bs = nil, -math.huge
	for _, name in PORTALS do
		local p = Places.spot(name)
		if p then
			local score = 0
			for _, pl in Players:GetPlayers() do
				local f = I.feetOf(pl)
				if f then
					score += math.min(120, (f - p).Magnitude)
				end
			end
			if near then
				score -= (p - near).Magnitude * 0.3
			end
			if score > bs then
				best, bs = p, score
			end
		end
	end
	return best or Vector3.new(-350, 6.5, 26)
end

local function spawnBody(n: any, at: Vector3, yaw: number?)
	local def = n.def
	local a = Actors.spawn({
		id = n.id,
		kind = n.arch,
		name = n.name,
		role = def.role,
		color = COLOR_OF[n.arch] or { 150, 150, 160 },
		type = def.type,
		look = def.look,
		feet = at,
		yaw = yaw or 0,
		hp = n.max,
		typeId = TYPE_OF[n.arch] or "plain",
		police = def.police == true,
		baton = false,
	})
	if not a then
		return false
	end
	n.a = a
	a.hp = n.hp
	Actors.setHP(a)
	Actors.setAttr(a, "GiArch", n.arch)
	Actors.setAttr(a, "GiStyle", n.style)
	Actors.setAttr(a, "GiGait", def.gait or "normal")
	n.present = true
	n.sitting = nil
	Mind.sync(n)
	return true
end

local function despawnBody(n: any)
	Routine.pause(n)
	Places.releaseAll(n)
	if n.a then
		Actors.remove(n.a)
	end
	n.a = nil
	n.present = false
	n.sitting = nil
	table.clear(n.conf)
	n.mode = "routine"
end
Routine.despawnBody = despawnBody

---------------------------------------------------------------------------------------------------
-- activity threads
---------------------------------------------------------------------------------------------------
local function checkCancel(n: any)
	local A = n.act
	if not A or A.kill or A.thread ~= coroutine.running() or not n.a or n.a.gone then
		error("__cancel", 0)
	end
end

local function wait(n: any, secs: number)
	local t = os.clock() + secs
	while os.clock() < t do
		task.wait(math.min(0.5, t - os.clock() + 0.01))
		checkCancel(n)
	end
end

local EXCUSE = {
	citizen = { "잠시만요~", "지나갈게요!", "저기, 좀 비켜 주실래요?" },
	thug = { "비켜라.", "길 막지 마라." },
	fool = { "비켜비켜~ 만복이 지나간다!", "빵빵~!" },
	homeless = { "좀 지나가입시더…", "에헴, 실례…" },
	drunk = { "어이~ 길 좀 비키라~", "딸꾹… 저리 가~" },
	police = { "잠시 지나가겠습니다.", "길 좀 비켜 주세요." },
	clerk = { "잠시만 지나갈게요~" },
}

-- a player standing right where the NPC walks next
local function blocker(n: any): Player?
	local a = n.a
	local st = workspace:GetServerTimeNow()
	local p0 = Actors.pos(a)
	local p1 = Actors.pos(a, st + 0.45)
	if (p1 - p0).Magnitude < 0.3 then
		return nil
	end
	for _, pl in Players:GetPlayers() do
		local f = I.feetOf(pl)
		if f and Vector3.new(f.X - p1.X, 0, f.Z - p1.Z).Magnitude < 1.5 and math.abs(f.Y - p1.Y) < 4 then
			return pl
		end
	end
	return nil
end

-- walk to target; true = arrived, false = gave up (blocked / never arrived)
local function go(n: any, target: Vector3, speed: number, straight: boolean?): boolean
	checkCancel(n)
	local a = n.a
	if n.lod == "far" then
		Actors.place(a, target, nil)
		return true
	end
	Actors.walkTo(a, target, speed, straight)
	local t0 = os.clock()
	local eta = (if a.path then a.path.len / a.path.speed else 0) + 6
	local blocks = 0
	while Actors.moving(a) do
		task.wait(0.25)
		checkCancel(n)
		if os.clock() - t0 > eta + 10 then
			n.stuckCount = (n.stuckCount or 0) + 1
			Actors.stop(a)
			return false
		end
		if n.lod == "near" then
			local pl = blocker(n)
			if pl then
				Actors.stop(a)
				blocks += 1
				Actors.say(a, pick(EXCUSE[n.arch] or EXCUSE.citizen), 2)
				Actors.face(a, I.feetOf(pl) or target)
				wait(n, 1.1)
				if blocker(n) or (I.feetOf(pl) and (I.feetOf(pl) - Actors.pos(a)).Magnitude < 2.2) then
					-- step around them
					local me = Actors.pos(a)
					local d = Vector3.new(target.X - me.X, 0, target.Z - me.Z)
					if d.Magnitude > 0.5 then
						local side = Vector3.new(-d.Z, 0, d.X).Unit * (if rnd:NextNumber() < 0.5 then 2.6 else -2.6)
						local detour = me + side + d.Unit * 1.5
						Actors.walkTo(a, Vector3.new(detour.X, Actors.groundAt(detour, me.Y), detour.Z), speed, true)
						wait(n, 0.9)
					end
				end
				if blocks >= 3 then
					Memory.event(pl, n.id, "bump")
					n.pendingProvoke = { key = "p:" .. pl.UserId, amount = 1, cause = "blocked" }
					return false
				end
				Actors.walkTo(a, target, speed, straight)
				t0 = os.clock()
				eta = (if a.path then a.path.len / a.path.speed else 0) + 6
			end
		end
	end
	n.stuckCount = 0
	return true
end
Routine.go = go

local function speedOf(n: any, kind: string?): number
	local arch = Cast.ARCH[n.arch] or Cast.ARCH.citizen
	local g = n.def.gait
	local w = arch.walk
	if g == "brisk" then
		w *= 1.25
	elseif g == "elderly" then
		w *= 0.8
	elseif g == "stroll" then
		w *= 0.85
	elseif g == "drunk" then
		w *= 0.75
	end
	if kind == "run" then
		return arch.run
	end
	return w
end
Routine.speedOf = speedOf

-- walk up to the seat, turn round and sit down on it (false = could not get there)
local function sitDown(n: any, seat: any, pose: string?): boolean
	local a = n.a
	local front = Places.seatApproach(seat)
	if not go(n, front, speedOf(n)) then
		Places.releaseSeat(n, seat)
		return false
	end
	Actors.place(a, front, seat.yaw)
	wait(n, 0.35) -- turn round before sitting
	Actors.place(a, seat.pos, seat.yaw)
	n.sitting = pose or "sit"
	Actors.pose(a, n.sitting)
	return true
end

-- get up: step off the seat to the front
local function standUp(n: any, seat: any)
	n.sitting = nil
	Actors.pose(n.a, "")
	if n.a and not n.a.gone then
		Actors.place(n.a, Places.seatApproach(seat), seat.yaw)
	end
	Places.releaseSeat(n, seat)
end

local function sit(n: any, seat: any, secs: number, pose: string?)
	if not sitDown(n, seat, pose) then
		return false
	end
	standUp(n, seat)
	return true
end

local function idleAt(n: any, secs: number, faceTo: Vector3?)
	local a = n.a
	if faceTo then
		Actors.face(a, faceTo)
	end
	local t = os.clock() + secs
	while os.clock() < t do
		wait(n, math.min(t - os.clock(), range({ 2.5, 5 })))
		if os.clock() >= t then
			break
		end
		local r = rnd:NextNumber()
		if r < 0.18 then
			Actors.emote(a, "look_around")
		elseif r < 0.26 and n.arch ~= "police" then
			Actors.pose(a, "phone")
			wait(n, range({ 2, 4 }))
			Actors.pose(a, "")
		elseif r < 0.32 and n.lod == "near" and os.clock() - (n.lastSay or 0) > 20 then
			Mind.say(n, if n.mood.v > 0.3 then "idle_happy" elseif n.mood.v < -0.2 then "idle_grumpy" else "idle_mutter")
		end
	end
end

local function spot(name: string?): Vector3?
	return Places.spot(name)
end

local ACT = {}

-- walk off to a portal and leave the block
function ACT.leave(n: any, _e: any)
	local me = Actors.pos(n.a)
	local p = hiddenPortal(me)
	go(n, p, speedOf(n))
	-- nobody around: vanish (else keep walking a little and try again)
	for _ = 1, 6 do
		if not playersNear(Actors.pos(n.a), 35) then
			break
		end
		wait(n, 2)
	end
	n.leaving = true
	task.defer(despawnBody, n)
	wait(n, 5)
end

function ACT.commute(n: any, e: any)
	local pts = {}
	for _, v in (e.via or {}) do
		local p = spot(v)
		if p then
			table.insert(pts, p)
		end
	end
	for i, p in pts do
		go(n, p, speedOf(n))
		if i == 1 and e.shop and rnd:NextNumber() < e.shop then
			ACT.shop(n, e)
		elseif e.stroll and rnd:NextNumber() < e.stroll then
			idleAt(n, range({ 6, 14 }), nil)
		end
	end
	local to = spot(e.to) or hiddenPortal(nil)
	go(n, to, speedOf(n))
	if e.loop then
		-- out of sight for a while, then back on the next round
		n.leaving = true
		task.defer(function()
			despawnBody(n)
			n.returnAt = os.clock() + range({ 25, 70 })
		end)
		wait(n, 5)
	else
		ACT.leave(n, e)
	end
end

function ACT.stroll(n: any, e: any)
	local last = nil
	while true do
		local names = e.spots or { "plaza" }
		local name = pick(names)
		if name == last and #names > 1 then
			name = pick(names)
		end
		last = name
		local p = spot(name)
		if p then
			local off = Vector3.new(rnd:NextNumber(-5, 5), 0, rnd:NextNumber(-4, 4))
			local target = Vector3.new(p.X + off.X, Actors.groundAt(p + off + Vector3.new(0, 1, 0), p.Y), p.Z + off.Z)
			if not go(n, target, speedOf(n)) then
				wait(n, range({ 2, 4 }))
			end
		end
		if e.rest and rnd:NextNumber() < e.rest then
			local seat = Places.takeSeat(n, Actors.pos(n.a), 45)
			if seat then
				sit(n, seat, range({ 18, 40 }))
			else
				idleAt(n, range({ 6, 12 }), nil)
			end
		else
			idleAt(n, range({ 8, 18 }), nil)
		end
	end
end

function ACT.photo(n: any, e: any)
	local p = spot(e.spot or "photo") or spot("plaza")
	go(n, p, speedOf(n))
	while true do
		Actors.face(n.a, Vector3.new(p.X, p.Y, p.Z - 20))
		Actors.pose(n.a, "camera")
		wait(n, range({ 6, 12 }))
		Actors.pose(n.a, "")
		Actors.emote(n.a, if rnd:NextNumber() < 0.5 then "cheer" else "point")
		idleAt(n, range({ 4, 8 }), nil)
		local off = Vector3.new(rnd:NextNumber(-8, 8), 0, rnd:NextNumber(-6, 6))
		go(n, Vector3.new(p.X + off.X, p.Y, p.Z + off.Z), speedOf(n))
	end
end

function ACT.rest(n: any, e: any)
	while true do
		local around = spot(pick(e.spots or { "plaza" })) or Actors.pos(n.a)
		local seat = Places.takeSeat(n, around, 40)
		if seat then
			sit(n, seat, range({ 30, 70 }))
		else
			-- every seat is taken: stand around, try again later
			go(n, around, speedOf(n))
			idleAt(n, range({ 10, 20 }), nil)
		end
		idleAt(n, range({ 4, 8 }), nil)
	end
end

---------------------------------------------------------------------------------------------------
-- shopping at GS25 광안리점
---------------------------------------------------------------------------------------------------
local function storeClerk(): any?
	local c = Places.store.clerk
	if c and c.present and c.mode == "routine" and c.atCounter then
		return c
	end
	return nil
end

-- hand-off to the running 알바 shift: our person becomes a JobWorld customer for the visit
local function shopViaJob(n: any): boolean
	local door = Places.storeStation("door_out")
	if not door then
		return false
	end
	if not go(n, door.feet, speedOf(n)) then
		return false
	end
	local cust = Places.spawnJobCustomer()
	if not cust then
		Mind.say(n, "queue_wait")
		return false
	end
	-- our body steps out of the way while JobWorld's customer shops
	local a = n.a
	Actors.place(a, door.feet + Vector3.new(0, -60, 0), nil)
	n.handoff = cust
	local t0 = os.clock()
	while not Places.jobCustomerDone(cust) and os.clock() - t0 < 180 do
		wait(n, 1)
	end
	n.handoff = nil
	Actors.place(a, door.feet, door.yaw)
	return true
end

function ACT.shop(n: any, e: any)
	local st = Places.store
	if not st.ok then
		return
	end
	if Places.storeWorking() then
		shopViaJob(n)
		return
	end
	local door = Places.storeStation("door_out")
	local doorIn = Places.storeStation("door_in")
	if not go(n, door.feet, speedOf(n)) then
		return
	end
	if not storeClerk() then
		-- nobody at the counter: look in, grumble, leave
		Actors.face(n.a, doorIn.feet)
		wait(n, 2)
		Mind.say(n, "idle_grumpy")
		return
	end
	go(n, doorIn.feet, speedOf(n), true)
	Places.chime()
	local clerk = storeClerk()
	if clerk then
		Mind.say(clerk, "clerk_greet")
	end
	-- browse a little
	if #st.browse > 0 and rnd:NextNumber() < 0.75 then
		local b = pick(st.browse)
		for _, p in Places.browsePath(b) do
			go(n, p, speedOf(n) * 0.85, true)
		end
		Actors.pose(n.a, "")
		idleAt(n, range({ 3, 7 }), nil)
		local front = Places.storeStation("front")
		if front then
			local back = Places.browsePath(b)
			for i = #back - 1, 1, -1 do
				go(n, back[i], speedOf(n) * 0.9, true)
			end
			go(n, front.feet, speedOf(n), true)
		end
	end
	-- queue
	local slot = Places.queueJoin(n)
	local waitStart = os.clock()
	while not slot do
		Mind.say(n, "queue_wait")
		wait(n, 3)
		slot = Places.queueJoin(n)
		if os.clock() - waitStart > 25 then
			Mind.say(n, "queue_cancel")
			Mind.feel(n, { v = -0.15, patience = -10 })
			return
		end
	end
	local patience = 25 + n.traits.patience * 60 -- seconds this person waits before giving up
	local complained = false
	while true do
		slot = Places.queueSlot(n)
		if not slot then
			return
		end
		local q = Places.queueFeet(slot)
		if q and (Actors.pos(n.a) - q).Magnitude > 0.8 then
			go(n, q, speedOf(n), true)
		end
		Actors.face(n.a, Places.storeStation("counter").feet)
		if slot == 1 and storeClerk() and not (storeClerk() :: any).serving then
			break
		end
		-- somebody (a player) standing at the head of the line = cutting in
		local head = Places.queueFeet(1)
		if head and slot > 1 then
			for _, pl in Players:GetPlayers() do
				local f = I.feetOf(pl)
				if f and (f - head).Magnitude < 1.8 and not complained then
					complained = true
					Mind.say(n, "complain")
					n.pendingProvoke = { key = "p:" .. pl.UserId, amount = 1, cause = "cut_in" }
				end
			end
		end
		wait(n, 1)
		local waited = os.clock() - waitStart
		if waited > patience * 0.6 and not complained then
			complained = true
			Mind.say(n, "queue_complain")
			Mind.feel(n, { v = -0.1, patience = -8 })
		end
		if waited > patience then
			Mind.say(n, "queue_cancel")
			Mind.feel(n, { v = -0.2, anger = 0.1, patience = -15 })
			Places.queueLeave(n)
			go(n, doorIn.feet, speedOf(n), true)
			go(n, door.feet, speedOf(n), true)
			return
		end
		if not storeClerk() and waited > 6 then
			Mind.say(n, "idle_grumpy")
			Places.queueLeave(n)
			go(n, door.feet, speedOf(n))
			return
		end
	end
	-- order / wait / pickup / pay
	clerk = storeClerk() :: any
	clerk.serving = n.id
	local item = Talk.item()
	Mind.say(n, "order", { item = item })
	wait(n, 1.6)
	Mind.say(clerk, "clerk_ack", { item = item })
	Actors.emote(clerk.a, "nod")
	local prep = range({ 3, 6 }) * (1.3 - clerk.traits.patience * 0.4)
	wait(n, math.min(3, prep))
	if prep > 3 then
		Mind.say(clerk, "clerk_wait")
		wait(n, prep - 3)
	end
	-- a mistake now and then (a tired clerk makes more)
	local mistake = rnd:NextNumber() < (0.08 + (if clerk.id == "k_jungi" then 0.07 else 0))
	if mistake then
		local wrong = Talk.item()
		Mind.say(clerk, "clerk_hand", { item = wrong })
		wait(n, 1.4)
		if n.traits.patience < 0.35 or n.mood.anger > 0.4 then
			Mind.say(n, "wrong_order", { item = item })
			Mind.feel(n, { anger = 0.15, v = -0.1 })
			Actors.emote(n.a, "point")
		else
			Mind.say(n, "wrong_order", { item = item })
		end
		wait(n, 1.4)
		Mind.say(clerk, "clerk_sorry")
		Actors.emote(clerk.a, "bow")
		wait(n, range({ 2.5, 4 }))
	end
	Mind.say(clerk, "clerk_hand", { item = item })
	Actors.emote(clerk.a, "give")
	wait(n, 1)
	Actors.emote(n.a, "receive")
	Mind.say(n, "thanks_clerk")
	Mind.feel(n, { v = 0.08 })
	clerk.serving = nil
	clerk.served = (clerk.served or 0) + 1
	Places.queueLeave(n)
	wait(n, 0.6)
	Mind.say(clerk, "clerk_bye")
	go(n, Places.storeStation("front").feet, speedOf(n), true)
	go(n, doorIn.feet, speedOf(n), true)
	Places.chime()
	go(n, door.feet, speedOf(n), true)
	-- eat outside
	if e.eat or rnd:NextNumber() < 0.35 then
		local seat = Places.takeSeat(n, door.feet, 40)
		if seat then
			sit(n, seat, range({ 15, 28 }), "sit")
		end
	end
end

-- the clerk at the counter (steps back while a player works the shift)
function ACT.work(n: any, _e: any)
	local st = Places.store
	if not st.ok then
		ACT.stroll(n, { spots = { "storeTerrace" } })
		return
	end
	Places.store.clerk = n
	local counter = Places.storeStation("counter")
	local backroom = Places.storeStation("backroom") or Places.storeStation("boss")
	local door = Places.storeStation("door_out")
	go(n, door.feet, speedOf(n))
	go(n, Places.storeStation("door_in").feet, speedOf(n), true)
	while true do
		if Places.storeWorking() then
			n.atCounter = false
			if backroom then
				go(n, backroom.feet, speedOf(n), true)
				Actors.face(n.a, counter.feet)
			end
			wait(n, 4)
		else
			if not n.atCounter then
				go(n, Places.storeStation("front").feet, speedOf(n), true)
				go(n, counter.feet, speedOf(n), true)
				Actors.place(n.a, counter.feet, counter.yaw)
				n.atCounter = true
			end
			Actors.pose(n.a, "")
			-- a customer that stopped mid-order (shoved, fled, despawned) frees the counter
			local s = n.serving and Mind.get(n.serving)
			if n.serving and not (s and s.present and s.act and s.act.kind == "shop" and not s.act.done) then
				n.serving = nil
			end
			wait(n, range({ 3, 6 }))
			if not n.serving and rnd:NextNumber() < 0.15 then
				Actors.emote(n.a, if rnd:NextNumber() < 0.5 then "look_around" else "nod")
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- the street people
---------------------------------------------------------------------------------------------------
function ACT.hangout(n: any, e: any)
	local boss = e.follow and Mind.get(e.follow)
	while true do
		if boss and boss.present and boss.a and boss.mode == "routine" then
			-- a minion sticks to the boss
			local bp = Actors.pos(boss.a)
			local me = Actors.pos(n.a)
			if (bp - me).Magnitude > 5 then
				go(n, Places.nearPoint(me, bp, 3), speedOf(n), true)
			end
			Actors.face(n.a, bp)
			wait(n, range({ 3, 6 }))
		else
			local p = spot(pick(e.spots or { "plazaWcorner" }))
			if p then
				local off = Vector3.new(rnd:NextNumber(-3, 3), 0, rnd:NextNumber(-3, 3))
				go(n, Vector3.new(p.X + off.X, p.Y, p.Z + off.Z), speedOf(n))
			end
			idleAt(n, range({ 25, 60 }), nil)
		end
		-- the duo's banter can turn into a real fight (somebody started it; police not around)
		if boss and boss.present and boss.mode == "routine" and n.mode == "routine" and rnd:NextNumber() < 0.08 and not (Police and Police.copNear(Actors.pos(n.a), 45)) then
			Mind.say(n, "boast")
			wait(n, 2)
			Mind.say(boss, "tease_angry")
			n.pendingProvoke = { key = "n:" .. boss.id, amount = 2, cause = "banter", starter = "self", mutual = true }
			wait(n, 1)
		end
	end
end

function ACT.roam(n: any, _e: any)
	local center = spot("plaza") or Actors.pos(n.a)
	local nodes = n.roamNodes
	if not nodes then
		nodes = Actors.nodesAround(center, 75, 5.8, 7.2)
		n.roamNodes = nodes
	end
	while true do
		local target = if #nodes > 0 then pick(nodes) else center
		go(n, target, speedOf(n))
		local r = rnd:NextNumber()
		if r < 0.3 then
			Actors.emote(n.a, "dance")
			wait(n, range({ 3, 6 }))
		elseif r < 0.5 then
			Actors.emote(n.a, "cheer")
		end
		wait(n, range({ 1.5, 4 }))
	end
end

function ACT.beg(n: any, e: any)
	local home = spot(n.def.spot) or spot("beggarSpot") or Actors.pos(n.a)
	while true do
		if (Actors.pos(n.a) - home).Magnitude > 1.2 then
			go(n, home, speedOf(n))
		end
		local d = (spot("plaza") or home) - home
		Actors.place(n.a, home, math.deg(math.atan2(-d.X, -d.Z)))
		n.sitting = "beg"
		Actors.pose(n.a, "beg")
		wait(n, range({ 25, 60 }))
		if e.wander and rnd:NextNumber() < e.wander then
			n.sitting = nil
			Actors.pose(n.a, "")
			local p = spot(pick({ "truckW", "plazaW", "stage" }))
			if p then
				go(n, p, speedOf(n))
				idleAt(n, range({ 6, 12 }), nil)
			end
		end
	end
end

-- stand and wait (for somebody / a scripted scene), facing e.face if given
function ACT.wait(n: any, e: any)
	if e.at then
		go(n, e.at, speedOf(n))
	else
		Actors.stop(n.a)
	end
	idleAt(n, e.secs or 3600, e.face)
end

function ACT.wander(n: any, e: any)
	ACT.stroll(n, { spots = e.spots, rest = e.rest or 0.5 })
end

function ACT.drink(n: any, e: any)
	while true do
		local around = spot(pick(e.spots or { "plaza" })) or Actors.pos(n.a)
		local seat = Places.takeSeat(n, around, 50)
		if seat then
			if sitDown(n, seat, "sit") then
				local t = os.clock() + range({ 25, 55 })
				while os.clock() < t do
					wait(n, range({ 5, 9 }))
					if n.lod == "near" then
						local r = rnd:NextNumber()
						if r < 0.3 then
							-- a song the whole street hears
							Mind.say(n, "sing")
							World.incident("disturbance", Actors.pos(n.a), { aggressor = "n:" .. n.id })
						elseif r < 0.55 then
							Mind.say(n, if n.style == "drunk_sad" then "sentimental" else "idle_grumpy")
						end
					end
				end
				standUp(n, seat)
			end
		end
		-- stagger somewhere else
		local p = spot(pick(e.spots or { "plaza" }))
		if p then
			go(n, p, speedOf(n))
		end
		idleAt(n, range({ 5, 12 }), nil)
	end
end

function ACT.sleep(n: any, _e: any)
	local home = spot(n.def.spot) or Actors.pos(n.a)
	go(n, home, speedOf(n))
	n.sitting = "sleep"
	Actors.pose(n.a, "sleep")
	while true do
		wait(n, range({ 15, 30 }))
		if n.lod == "near" and rnd:NextNumber() < 0.4 then
			Mind.say(n, "sleep_talk")
		end
	end
end

function ACT.patrol(n: any, e: any)
	local beat = {}
	for _, name in (e.beat or { "plaza" }) do
		local p = spot(name)
		if p then
			table.insert(beat, p)
		end
	end
	local i = rnd:NextInteger(1, math.max(1, #beat))
	while true do
		local p = beat[i]
		if p then
			go(n, p, speedOf(n))
			Actors.pose(n.a, "")
			-- stop and look around (the next think's senses do the noticing)
			Actors.emote(n.a, "look_around")
			wait(n, range({ 4, 8 }))
		end
		i = (i % math.max(1, #beat)) + 1
	end
end

-- an elevator ride through the existing ElevatorButton interface (press, wait for the car, ride)
function ACT.lift(n: any, e: any)
	local buttons = Places.elevatorButtons(e.near or Actors.pos(n.a), e.radius or 40)
	local from, to = nil, nil
	for _, b in buttons do
		if b.from == e.fromFloor and b.floor == e.toFloor then
			from = b
		end
	end
	from = from or buttons[1]
	if not from then
		n.liftResult = "no_button"
		return
	end
	local press = Vector3.new(from.part.Position.X, Actors.groundAt(from.part.Position, from.part.Position.Y - 3), from.part.Position.Z)
	n.liftResult = "walking"
	go(n, Places.nearPoint(Actors.pos(n.a), press, 2), speedOf(n), true)
	Actors.face(n.a, from.part.Position)
	Actors.emote(n.a, "point")
	n.liftResult = "called"
	wait(n, range({ 2.5, 4 })) -- waiting for the car
	local stop = Places.elevatorStop(from.button, from.target)
	if not stop then
		n.liftResult = "no_stop"
		return
	end
	n.liftResult = "riding"
	wait(n, 1.2)
	to = Vector3.new(stop.Position.X, Actors.groundAt(stop.Position + Vector3.new(0, 2, 0), stop.Position.Y), stop.Position.Z)
	Actors.place(n.a, to, nil)
	n.liftResult = "arrived"
	wait(n, 2)
end

---------------------------------------------------------------------------------------------------
-- schedule
---------------------------------------------------------------------------------------------------
local function inWindow(h: number, a: number, b: number): boolean
	if a <= b then
		return h >= a and h < b
	end
	return h >= a or h < b
end

local function entryFor(n: any): any
	-- a scripted override (cutscenes / events of other sessions / tests): Routine.force
	if n.forceEntry then
		return n.forceEntry
	end
	local h = Mind.clock()
	for _, e in n.def.schedule do
		if e[3] ~= "away" and inWindow(h, e[1], e[2]) then
			return e
		end
	end
	if Routine.allDay or workspace:GetAttribute("GwCityAllDay") == true then
		for _, e in n.def.schedule do
			if e[3] ~= "away" then
				return e
			end
		end
	end
	for _, e in n.def.schedule do
		if e[3] == "away" then
			return e
		end
	end
	return { 0, 24, "away" }
end

local function startAct(n: any, kind: string, e: any)
	Routine.pause(n)
	local A = { kind = kind, kill = false, done = false, thread = nil :: thread? }
	n.act = A
	-- create first, spawn second: the thread checks A.thread == coroutine.running() on its first step
	A.thread = coroutine.create(function()
		local fn = ACT[kind] or ACT.stroll
		local ok, err = pcall(fn, n, e)
		if not ok and err ~= "__cancel" then
			warn("[GwangalliCity] " .. n.id .. " " .. kind .. ": " .. tostring(err))
		end
		A.done = true
	end)
	task.spawn(A.thread :: thread)
end

function Routine.pause(n: any)
	local A = n.act
	n.act = nil
	if A then
		A.kill = true
		if A.thread and coroutine.running() ~= A.thread and coroutine.status(A.thread) ~= "dead" then
			pcall(task.cancel, A.thread)
		end
	end
	-- somebody interrupted while seated stands up in front of the seat first
	if n.sitting and n.holds and n.a and not n.a.gone then
		for k, seat in n.holds do
			if type(k) == "string" and string.sub(k, 1, 5) == "seat:" then
				Actors.place(n.a, Places.seatApproach(seat), seat.yaw)
				break
			end
		end
	end
	n.sitting = nil
	Places.releaseAll(n)
end

function Routine.resume(n: any)
	if not n.present then
		return
	end
	local e = n.entry
	if not e or e[3] == "away" then
		startAct(n, "leave", e)
		return
	end
	startAct(n, e[3], e)
end

function Routine.schedule(n: any, now: number)
	if n.temp or now < (n.schedT or 0) then
		return
	end
	n.schedT = now + 3
	if n.mode == "custody" then
		return
	end
	if n.returnAt and now < n.returnAt then
		return
	end
	n.returnAt = nil
	local e = entryFor(n)
	local changed = e ~= n.entry
	n.entry = e
	if e[3] == "away" then
		if n.present and changed and n.mode == "routine" and not n.leaving then
			startAct(n, "leave", e)
		end
		return
	end
	if not n.present then
		-- appear out of sight (their spot when nobody looks, else a far portal) and walk in
		local wantAt = spot(e.from) or spot(n.def.spot) or spot(e.spots and e.spots[1]) or spot((e.beat or {})[1]) or spot("plaza")
		local at = wantAt
		if wantAt and playersNear(wantAt, 45) and not e.from then
			at = hiddenPortal(wantAt)
		end
		n.leaving = false
		if spawnBody(n, at or hiddenPortal(nil), 0) then
			n.mode = "routine"
			startAct(n, e[3], e)
		end
		return
	end
	if changed and n.mode == "routine" then
		startAct(n, e[3], e)
	end
end

-- make somebody do one thing until released: Routine.force(n, { 0, 24, "shop" }) / Routine.force(n, nil)
-- (activity names: commute stroll photo rest shop work hangout roam beg wander drink sleep patrol lift
-- wait leave; the entry table carries the activity's options, e.g. spots / near / secs)
function Routine.force(n: any, entry: any?)
	n.forceEntry = entry
	n.schedT = 0
	if n.present and (n.mode == "routine" or n.mode == "recover") then
		Mind.setMode(n, "routine")
		n.entry = entryFor(n)
		startAct(n, n.entry[3], n.entry)
	end
end

function Routine.step(n: any, now: number)
	-- something an activity thread asked the brain to do (it cannot change its own mode safely)
	local pp = n.pendingProvoke
	if pp then
		n.pendingProvoke = nil
		local other = Mind.byKey(pp.key)
		Mind.provoke(n, pp.key, pp.amount, pp.cause, pp.starter or "self")
		if pp.mutual and other then
			Mind.provoke(other, "n:" .. n.id, pp.amount, pp.cause, "other")
		end
		return
	end
	if n.handoff and Places.jobCustomerDone(n.handoff) then
		n.handoff = nil
	end
	if not n.act or n.act.done then
		Routine.resume(n)
	end
end

---------------------------------------------------------------------------------------------------
-- initiatives: things people start on their own when a player passes by
---------------------------------------------------------------------------------------------------
function Routine.initiative(n: any, p: Player, d: number, now: number)
	local key = "p:" .. p.UserId
	local T = n.traits
	local rec = Memory.peek(p, n.id)
	local tier = Memory.tier(rec)
	local per = n.seen[p.UserId]
	n.initiativeT = now + range({ 6, 12 })
	if per and now - (per.initiative or 0) < 60 then
		return
	end
	local function mark()
		if per then
			per.initiative = now
		end
	end
	if n.arch == "homeless" and n.def.style == "homeless_kind" and d < 14 and d > 3 and tier ~= "enemy" then
		mark()
		Mind.faceKey(n, key)
		Mind.say(n, if rec and rec.helped > 0 then "remember_helped" else "beg")
		Actors.emote(n.a, "beg")
	elseif n.arch == "homeless" and d < 6 and rnd:NextNumber() < 0.5 then
		mark()
		Mind.faceKey(n, key)
		Mind.say(n, if tier == "friend" or tier == "friendly" then "greet_friend" else "idle_grumpy")
	elseif n.arch == "fool" and d < 16 then
		mark()
		local r = rnd:NextNumber()
		if r < 0.45 then
			Routine.foolBrag(n, p)
		elseif r < 0.8 and (n.noBump or {})[p.UserId] == nil then
			Routine.foolPrank(n, p)
		else
			Mind.say(n, "weird_request")
			Mind.faceKey(n, key)
		end
	elseif n.arch == "thug" and d < 9 and n.def.style == "thug_boss" and not (Police and Police.copNear(Actors.pos(n.a), 35)) then
		local roll = T.aggression * (0.4 + n.mood.anger) + (if tier == "enemy" then 0.4 elseif tier == "wary" then 0.2 else 0)
		if rnd:NextNumber() < roll * 0.6 then
			mark()
			Mind.say(n, "hassle")
			Mind.provoke(n, key, 1.6, "hassle", "self")
		end
	elseif n.arch == "drunk" and d < 8 then
		mark()
		if n.style == "drunk_rowdy" and rnd:NextNumber() < (n.drunk * 0.6 + n.mood.anger) then
			Mind.say(n, "pick_fight")
			Mind.provoke(n, key, 1.8, "drunk", "self")
		else
			Mind.faceKey(n, key)
			Mind.say(n, if n.style == "drunk_sad" then "sentimental" else "sing")
		end
	elseif n.arch == "citizen" and d < 7 then
		if n.entry and n.entry.askDirections and (not rec or (rec.favorAsked or 0) == 0) then
			mark()
			Routine.askDirections(n, p)
		elseif n.def.style == "grandma" and rnd:NextNumber() < 0.4 then
			mark()
			Mind.faceKey(n, key)
			Mind.say(n, "talk_good")
		elseif (tier == "friendly" or tier == "friend") and rnd:NextNumber() < 0.6 then
			mark()
			Mind.faceKey(n, key)
			Mind.say(n, "greet_friend")
			Actors.emote(n.a, "wave")
		end
	elseif n.arch == "police" and d < 10 and rnd:NextNumber() < 0.35 then
		mark()
		Mind.faceKey(n, key)
		Mind.say(n, "cop_patrol")
	end
end

-- 만복이: runs at the player and gives them a giggling 어깨빵
function Routine.foolPrank(n: any, p: Player)
	Mind.say(n, "prank")
	local key = "p:" .. p.UserId
	Mind.setMode(n, "dodge", 8)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 7 and n.mode == "dodge" and n.a and not n.a.gone do
			local f = I.feetOf(p)
			if not f then
				break
			end
			local me = Actors.pos(n.a)
			local d = Vector3.new(f.X - me.X, 0, f.Z - me.Z)
			if d.Magnitude < 2.6 then
				local u = d.Unit
				Actors.emote(n.a, "shove")
				Mind.say(n, "prank")
				local st = I.state(p)
				if not st.busy then
					local streak = p:GetAttribute("BumpStreak")
					local kd = 0.3 + (if type(streak) == "number" and streak >= 2 then 0.25 else 0)
					I.hurtPlayer(p, 1, { by = n.name, dx = u.X, dz = u.Z, outcome = if rnd:NextNumber() < kd then "knockdown" else "stagger", actor = n.id })
				end
				World.incident("bump", me, { aggressor = "n:" .. n.id, victim = key })
				task.wait(0.7)
				Actors.emote(n.a, "laugh")
				local away = me - u * 9
				Actors.walkTo(n.a, Vector3.new(away.X, Actors.groundAt(away, me.Y), away.Z), 13, true)
				break
			end
			Actors.walkTo(n.a, f + d.Unit * 0.6, 13, d.Magnitude < 24)
			task.wait(0.4)
		end
		if n.mode == "dodge" then
			Mind.toRoutine(n, 1.5)
		end
	end)
end

-- 만복이 shows off ("내가 광안리에서 제일 빠르다!"), trips and has to live with it
function Routine.foolBrag(n: any, p: Player)
	Mind.faceKey(n, "p:" .. p.UserId)
	Mind.say(n, "brag")
	Mind.setMode(n, "dodge", 6)
	task.spawn(function()
		task.wait(1.6)
		if n.mode ~= "dodge" or not n.a then
			return
		end
		local me = Actors.pos(n.a)
		local dir = Vector3.new(rnd:NextNumber(-1, 1), 0, rnd:NextNumber(-1, 1))
		if dir.Magnitude < 0.2 then
			dir = Vector3.new(1, 0, 0)
		end
		dir = dir.Unit
		local to = me + dir * 9
		Actors.walkTo(n.a, Vector3.new(to.X, Actors.groundAt(to, me.Y), to.Z), 14, true)
		task.wait(0.55)
		if n.mode ~= "dodge" or not n.a then
			return
		end
		-- the trip
		Actors.down(n.a, dir.X, dir.Z, "knockdown", 1.4)
		World.incident("disturbance", Actors.pos(n.a), { aggressor = "n:" .. n.id })
		task.wait(1.6)
		Mind.say(n, "brag_fall")
		Mind.setMode(n, "embarrassed", 10)
		n.embarrassedBy = p.UserId
		n.embarrassedReact = nil
	end)
end

-- nobody said anything while he was embarrassed
function Routine.embarrassedEnd(n: any)
	if not n.embarrassedReact then
		Mind.say(n, "embarrassed")
	end
	n.embarrassedBy = nil
	n.embarrassedReact = nil
end

-- a tourist asks the player the way (a dialog card)
function Routine.askDirections(n: any, p: Player)
	local rec = Memory.get(p, n.id)
	rec.favorAsked = os.time()
	Mind.setMode(n, "talk")
	n.talkWith = p.UserId
	n.talkT = os.clock()
	Mind.faceKey(n, "p:" .. p.UserId)
	local text = Talk.line(n, "favor_ask") or "실례합니다… 광안대교 사진 찍기 좋은 곳 어디예요?"
	Actors.say(n.a, text, 4)
	I.card(p, n.id, { name = n.name, role = n.def.role, color = { 150, 170, 200 }, icon = "🗺️", bye = "모르겠어요" }, text, {
		{ id = "show", label = "같이 가서 알려주기" },
		{ id = "point", label = "저쪽이에요 (손으로 가리키기)" },
	}, function(choice)
		if choice == "show" or choice == "point" then
			Memory.event(p, n.id, "help")
			Mind.say(n, "favor_thanks")
			Actors.emote(n.a, "bow")
			Mind.feel(n, { v = 0.25 })
			pcall(I.ctx.addStats, p, { happiness = 1, popularity = 1 }, nil, true)
		else
			Memory.event(p, n.id, "follow", 0)
			Mind.say(n, "favor_refused")
		end
		n.talkWith = nil
		Mind.toRoutine(n, 1)
	end)
end

function Routine.init(interact: any)
	I = interact
	C = I.C
	Cast = I.Cast
	Actors = I.Actors
	Mind = I.Mind
	Talk = I.Talk
	Memory = I.Memory
	World = I.World
	Places = I.Places
	Police = I.Police
end

return Routine
