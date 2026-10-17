-- GwangalliShopCrew/Crew: the brain of one crewed shop (cook / waiter / cashier / barista / floor / stocker ...).
-- Each rig runs one job at a time (a coroutine with an abort token); jobs come from Bus events and the 4 Hz tick:
--   serve (1) > answer call / take order (2) > welcome · relay · diner order (3) > check on (5) > clear (6) > idle (9)
-- A higher-priority job interrupts a preemptible one (clear / idle / check on / a waiter waiting at a table).
--   Crew.init(Shared, Bridge, Net, mods)   mods = { Sites, Rig, Serve, Regulars }
--   Crew.new(site, opts) -> crew?   opts = { coexist = bool (no waiter / staffMode), mood = number }
--   Crew.destroy(crew, why)   Crew.tick(crew)   Crew.onBus(crew, kind, d)
--   Crew.enqueue(crew, role, job)   Crew.rigOf(crew, role) / greeter / cashierRig / waiter
--   Crew.say(crew, R, key, vars?, tone?) -> text?   Crew.line(crew, R, key, vars?) -> text?
--   Crew.walkTo(crew, R, tok, spot, speed) -> bool    Crew.hold(crew, R, tok, secs, cond?) -> "ok" | "abort" | "cond"
--   Crew.jobs  (job factories other modules use: dinerOrder, takeOrder, point ...)
-- staffMode { serve = true } is on only while the waiter rig is alive (and never in coexist mode); it goes off
-- (and every ready table order is served) before the waiter leaves.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local Crew = {}

local Config: any = nil
local Bridge: any = nil
local Net: any = nil
local Util: any = nil
local Lines: any = nil
local Personas: any = nil
local Sites: any = nil
local Rig: any = nil
local Serve: any = nil
local Regulars: any = nil
local Talk: any = nil

local P_SERVE, P_CALL, P_RELAY, P_CHECK, P_CLEAR, P_IDLE = 1, 2, 3, 5, 6, 9

Crew.jobs = {}

function Crew.init(S: any, B: any, N: any, mods: any)
	Config, Bridge, Net, Util = S.Config, B, N, S.Util
	Lines, Personas = S.Lines, S.Personas
	Sites, Rig, Serve, Regulars = mods.Sites, mods.Rig, mods.Serve, mods.Regulars
end

function Crew.setTalk(T: any)
	Talk = T
end

local function now(): number
	return os.clock()
end

local function rand(a: number, b: number): number
	return a + math.random() * (b - a)
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-------------------------------------------------------------------------------------------------
-- rigs by role
-------------------------------------------------------------------------------------------------
function Crew.rigOf(crew: any, role: string): any?
	local R = crew.rigs[role]
	return if R and Rig.alive(R) then R else nil
end

function Crew.waiter(crew: any): any?
	return Crew.rigOf(crew, "waiter")
end

-- who takes the money: the cashier, else the maker at the counter
function Crew.cashierRig(crew: any): any?
	return Crew.rigOf(crew, "cashier") or Crew.rigOf(crew, "pharmacist") or Crew.rigOf(crew, "cook") or Crew.rigOf(crew, "barista") or Crew.rigOf(crew, "baker") or Crew.rigOf(crew, "stylist") or Crew.rigOf(crew, "stocker") or Crew.rigOf(crew, "waiter")
end

function Crew.makerRig(crew: any): any?
	return Crew.rigOf(crew, "cook") or Crew.rigOf(crew, "barista") or Crew.rigOf(crew, "baker")
end

function Crew.greeter(crew: any): any?
	return Crew.rigOf(crew, "cashier") or Crew.rigOf(crew, "cook") or Crew.rigOf(crew, "barista") or Crew.rigOf(crew, "baker") or Crew.rigOf(crew, "pharmacist") or Crew.rigOf(crew, "stylist") or Crew.rigOf(crew, "stocker") or Crew.rigOf(crew, "waiter") or Crew.rigOf(crew, "floor")
end

local function homeOf(crew: any, role: string): any?
	local sp = crew.site.spots
	if role == "waiter" then
		return sp.H or sp.S
	elseif role == "cashier" then
		return sp.K
	elseif role == "pharmacist" or role == "stylist" then
		return sp.K or sp.C
	elseif role == "floor" then
		return sp.H or sp.idle[1] or sp.C
	elseif role == "stocker" then
		return sp.K or sp.H or sp.C
	end
	return sp.C or sp.K
end
Crew.homeOf = homeOf

-------------------------------------------------------------------------------------------------
-- lines
-------------------------------------------------------------------------------------------------
function Crew.line(crew: any, R: any?, key: string, vars: any?): string?
	local dialect = if R and R.persona then R.persona.dialect else "std"
	return Lines.get(key, { dialect = dialect, type = crew.site.type, vars = vars })
end

function Crew.say(crew: any, R: any?, key: string, vars: any?, tone: string?, dur: number?): string?
	if not R then
		return nil
	end
	local text = Crew.line(crew, R, key, vars)
	if text then
		Rig.say(R, text, dur, tone)
	end
	return text
end

-- the day's recommendation: a main dish picked by (day, shop)
function Crew.recommend(crew: any): any?
	local SS = Bridge.SS
	if not SS or not crew.site.menuKey then
		return nil
	end
	local ok, menu = pcall(SS.menu, crew.site.menuKey)
	if not ok or type(menu) ~= "table" or #menu == 0 then
		return nil
	end
	local mains = {}
	for _, it in menu do
		if it.cat == "main" or it.cat == nil then
			table.insert(mains, it)
		end
	end
	if #mains == 0 then
		mains = menu
	end
	return mains[(Util.hash(Util.dayKey() .. crew.key) % #mains) + 1]
end

-------------------------------------------------------------------------------------------------
-- motion helpers
-------------------------------------------------------------------------------------------------
local function valid(crew: any, R: any, tok: number): boolean
	return crew.alive and Rig.alive(R) and R.token == tok
end
Crew.valid = valid

function Crew.hold(crew: any, R: any, tok: number, secs: number, cond: (() -> boolean)?): string
	local t1 = now() + secs
	while now() < t1 do
		task.wait(math.min(0.25, math.max(0.03, t1 - now())))
		if not valid(crew, R, tok) then
			return "abort"
		end
		if cond and cond() then
			return "cond"
		end
	end
	return "ok"
end

-- walk to a spot (or a Vector3); false when aborted / unreachable
function Crew.walkTo(crew: any, R: any, tok: number, spot: any, speed: number?, act: string?): boolean
	if not spot then
		return false
	end
	local dest: Vector3 = if typeof(spot) == "Vector3" then spot else spot.pos
	local yaw = if typeof(spot) == "Vector3" then nil else spot.yaw
	local from = Rig.feet(R)
	if flatDist(from, dest) < 0.35 then
		Rig.place(R, dest, yaw)
		return valid(crew, R, tok)
	end
	local pts = Sites.path(crew.site, from, dest, nil)
	if not pts then
		if flatDist(from, dest) > 4 then
			return false
		end
		pts = { from, dest }
	end
	if act then
		Rig.act(R, act)
	end
	local secs = Rig.walk(R, pts, speed or R.persona.speed or 6)
	local res = Crew.hold(crew, R, tok, secs)
	if res == "abort" then
		-- (abortJob already stopped the rig where it was; a newer job owns the legs now)
		return false
	end
	Rig.arrive(R, yaw)
	return true
end

local function goHome(crew: any, R: any, tok: number, act: string?): boolean
	local h = homeOf(crew, R.role)
	if not h then
		return true
	end
	local ok = Crew.walkTo(crew, R, tok, h, nil, if R.role == "waiter" then "behind" else nil)
	if ok then
		Rig.act(R, act or crew.restAct[R.role] or "idle")
		if h.face then
			Rig.face(R, h.face)
		end
	end
	return ok
end
Crew.goHome = goHome

-------------------------------------------------------------------------------------------------
-- jobs
-------------------------------------------------------------------------------------------------
function Crew.enqueue(crew: any, role: string, job: any)
	if not Crew.rigOf(crew, role) then
		return false
	end
	job.prio = job.prio or P_IDLE
	job.at = now()
	local q = crew.queue[role]
	-- one job of a kind per key (the same table / player)
	if job.key then
		for _, j in q do
			if j.key == job.key then
				return false
			end
		end
		local cur = crew.rigs[role].job
		if cur and cur.key == job.key and not cur.done then
			return false
		end
	end
	table.insert(q, job)
	table.sort(q, function(a, b)
		if a.prio ~= b.prio then
			return a.prio < b.prio
		end
		return a.at < b.at
	end)
	return true
end

local function startJob(crew: any, R: any, job: any)
	R.token += 1
	local tok = R.token
	R.job = job
	job.tok = tok
	job.started = now()
	task.spawn(function()
		local ok, err = pcall(job.run, crew, R, job, tok)
		if not ok then
			crew.errors += 1
			crew.lastError = tostring(err)
			Bridge.warnOnce("job" .. tostring(job.kind), "job " .. tostring(job.kind) .. " @" .. crew.site.name .. ": " .. tostring(err))
			if job.orders then
				for _, o in job.orders do
					Serve.release(o)
				end
			end
		end
		job.done = true
		if R.job == job then
			R.job = nil
		end
	end)
end

local function abortJob(crew: any, R: any)
	local j = R.job
	if not j then
		return
	end
	R.token += 1
	R.job = nil
	j.done = true
	-- stop mid-walk right here (synchronously: the next job's leg starts from this point)
	if R.walking then
		Rig.halt(R)
	end
	if j.orders then
		for _, o in j.orders do
			Serve.release(o)
		end
	end
	if j.requeue then
		j.done = false
		j.requeue = j.requeue - 1
		if j.requeue >= 0 then
			Crew.enqueue(crew, R.role, j)
		end
	end
	if j.onAbort then
		pcall(j.onAbort, crew, R, j)
	end
end
Crew.abortJob = abortJob

-- serve: the tray from the pass to the table ------------------------------------------------------
local HOT = { soup = true, noodle = true, chinese = true }

local function carryOf(orders: { any }): string
	local list = {}
	for _, o in orders do
		table.insert(list, { kind = "dish", menu = o.menu or "", item = o.item or "", qty = o.qty or 1 })
	end
	return Util.encodeCarry(list)
end

local function serveRun(crew: any, R: any, job: any, tok: number)
	local site = crew.site
	local sp = site.spots
	local tableId = job.table
	-- to the pass
	if sp.S and flatDist(Rig.feet(R), sp.S.pos) > 0.8 then
		if not Crew.walkTo(crew, R, tok, sp.S, nil, "behind") then
			return
		end
	end
	if sp.S then
		Rig.face(R, sp.S.face)
	end
	-- everything ready for this table now goes on the same tray
	local orders = {}
	for _, o in Serve.readyFor(crew.key) do
		if o.table == tableId and #orders < Config.MAX_BATCH then
			table.insert(orders, o)
		end
	end
	for _, o in job.orders or {} do
		if not o.served and not table.find(orders, o) and #orders < Config.MAX_BATCH then
			table.insert(orders, o)
		end
	end
	local live = {}
	for _, o in orders do
		if not o.served and o.phase == "ready" then
			Serve.claim(o, "waiter")
			table.insert(live, o)
		end
	end
	job.orders = live
	if #live == 0 then
		goHome(crew, R, tok)
		return
	end
	if math.random() < 0.5 then
		Crew.say(crew, R, "takeTray", nil, "busy", 2)
	end
	if Crew.hold(crew, R, tok, 0.5) == "abort" then
		return
	end
	local heavy = HOT[site.type] == true or #live > 1
	Rig.carry(R, carryOf(live))
	Rig.act(R, if heavy then "crew_tray2" else "crew_tray")
	local first = live[1]
	local e = sp.A[tableId]
	local dest = e and ((first.seat and e.seats[first.seat]) or e.best)
	if not dest then
		-- no way to that table: ShopLife puts it down itself
		for _, o in live do
			Serve.serveNow(o, "nopath")
		end
		Rig.carry(R, "")
		goHome(crew, R, tok)
		return
	end
	if not Crew.walkTo(crew, R, tok, dest, Config.WALK.tray, if heavy then "crew_tray2" else "crew_tray") then
		Rig.carry(R, "")
		for _, o in live do
			Serve.release(o)
		end
		if valid(crew, R, tok) then
			-- unreachable after all: served directly
			for _, o in live do
				Serve.serveNow(o, "nopath")
			end
			goHome(crew, R, tok)
		end
		return
	end
	Rig.face(R, dest.face)
	Rig.emote(R, "give")
	if Crew.hold(crew, R, tok, 0.4) == "abort" then
		return
	end
	local served = {}
	for _, o in live do
		if Serve.serveNow(o, "waiter") then
			table.insert(served, o)
		end
	end
	Rig.carry(R, "")
	Rig.act(R, "idle")
	job.orders = nil
	if #served > 0 then
		local o = served[1]
		local owner = o.owner and Bridge.playerById(o.owner)
		if owner then
			Rig.talk(R, owner.UserId)
		end
		local tb = site.tableById[tableId]
		if #served > 1 then
			Crew.say(crew, R, "serveMany", { item = o.name, count = #served - 1 }, "happy")
		elseif tb and tb.grill then
			Crew.say(crew, R, "serveGrill", { item = o.name }, "happy")
		elseif HOT[site.type] and math.random() < 0.6 then
			Crew.say(crew, R, "serveHot", { item = o.name }, "happy")
		else
			Crew.say(crew, R, "serve", { item = o.name }, "happy")
		end
		crew.lastServe[tableId] = now()
		if Crew.hold(crew, R, tok, 1.4) == "abort" then
			return
		end
		Rig.talk(R, 0)
	end
	goHome(crew, R, tok)
end

function Crew.jobs.serve(tableId: number, orders: { any }): any
	return { kind = "serve", prio = P_SERVE, key = "serve" .. tableId, table = tableId, orders = orders, run = serveRun }
end

-- welcome a seated player: water + menu, then the "주문하시겠어요?" dialog --------------------------------
local function waitOrder(crew: any, R: any, tok: number, uid: number, secs: number): string
	local t0 = now()
	return Crew.hold(crew, R, tok, secs, function()
		local ordered = crew.orderedAt[uid]
		if ordered and ordered >= t0 - 0.5 then
			return true
		end
		-- the tray comes first: a ready order elsewhere interrupts the wait
		if #Serve.readyFor(crew.key) > 0 then
			return true
		end
		return false
	end)
end

local function seatedHere(crew: any, uid: number, tableId: number?): boolean
	local s = crew.seatOf["u" .. uid]
	return s ~= nil and (tableId == nil or s.table == tableId)
end
Crew.seatedHere = seatedHere

local function approachFor(crew: any, tableId: number, seatId: number?): any?
	local e = crew.site.spots.A[tableId]
	if not e then
		return nil
	end
	return (seatId and e.seats[seatId]) or e.best
end
Crew.approachFor = approachFor

local function tableVisitRun(crew: any, R: any, job: any, tok: number)
	local uid = job.uid
	local p = Bridge.playerById(uid)
	if not p or not seatedHere(crew, uid, job.table) then
		return
	end
	local dest = approachFor(crew, job.table, job.seat)
	if not dest then
		return
	end
	if job.mode == "call" then
		Crew.say(crew, R, "callAnswer", nil, "busy", 2.2)
	end
	if job.mode == "welcome" then
		Rig.carry(R, "water")
	end
	if not Crew.walkTo(crew, R, tok, dest, nil, if job.mode == "welcome" then "crew_tray" else "behind") then
		Rig.carry(R, "")
		return
	end
	Rig.face(R, dest.face)
	Rig.talk(R, uid)
	if job.mode == "welcome" then
		Rig.emote(R, "give")
		if Crew.hold(crew, R, tok, 0.6) == "abort" then
			return
		end
		Rig.carry(R, "menu")
		local rec = Crew.recommend(crew)
		Crew.say(crew, R, "welcomeSeat", { item = rec and rec.name or "오늘의 메뉴" }, "plain", 4.2)
		Rig.act(R, "teller")
		if Talk then
			Talk.push(p, crew, R, "welcome")
		end
		if Crew.hold(crew, R, tok, 1.2) == "abort" then
			return
		end
		Rig.carry(R, "")
	elseif job.mode == "call" then
		Crew.say(crew, R, "callArrive", nil, "plain", 3.2)
		Rig.act(R, "crew_note")
	elseif job.mode == "check" then
		Crew.say(crew, R, "checkOn", nil, "plain", 3.2)
		Rig.act(R, "listen")
		if Talk and job.push then
			Talk.push(p, crew, R, "check")
		end
	elseif job.mode == "take" then
		Rig.act(R, "crew_note")
	end
	-- taking the order: stay while the player picks from the menu
	local stay = if job.mode == "call" or job.mode == "take" then Config.CALL_STAY elseif job.mode == "welcome" then 7 else 3
	if crew.taking[uid] and now() < crew.taking[uid] then
		stay = math.max(stay, crew.taking[uid] - now())
		Rig.act(R, "crew_note")
	end
	local res = waitOrder(crew, R, tok, uid, stay)
	if res == "abort" then
		return
	end
	if crew.taking[uid] and now() < crew.taking[uid] and res ~= "cond" then
		-- the dialog said "주문할게요" during the welcome: keep standing there with the order pad
		Rig.act(R, "crew_note")
		res = waitOrder(crew, R, tok, uid, math.max(0, crew.taking[uid] - now()))
		if res == "abort" then
			return
		end
	end
	if res == "cond" and not (crew.orderedAt[uid] and crew.orderedAt[uid] >= job.started - 0.5) then
		-- interrupted by a tray: say so when the player was waiting with the menu open
		if crew.taking[uid] and now() < crew.taking[uid] then
			Crew.say(crew, R, "busyWait", nil, "busy", 2.6)
		end
	end
	Rig.talk(R, 0)
	if #Serve.readyFor(crew.key) > 0 then
		-- a tray is waiting: the serve job walks from here
		Rig.act(R, "idle")
		return
	end
	goHome(crew, R, tok)
end

function Crew.jobs.visit(mode: string, uid: number, tableId: number, seatId: number?, push: boolean?): any
	local prio = if mode == "call" or mode == "take" then P_CALL elseif mode == "check" then P_CHECK else P_RELAY
	return { kind = mode, prio = prio, key = "visit" .. uid, uid = uid, table = tableId, seat = seatId, mode = mode, push = push, run = tableVisitRun, preempt = mode ~= "take" and mode ~= "call", onAbort = function(_, R2)
		Rig.carry(R2, "")
		Rig.talk(R2, 0)
	end }
end

-- relay an order to the kitchen ----------------------------------------------------------------------
local function relayRun(crew: any, R: any, job: any, tok: number)
	local sp = crew.site.spots
	-- a tray waiting beats walking an order slip over (the cook heard it anyway)
	if #Serve.readyFor(crew.key) == 0 and sp.S and flatDist(Rig.feet(R), sp.S.pos) > 1.2 then
		if not Crew.walkTo(crew, R, tok, sp.S, nil, "crew_note") then
			return
		end
		Rig.face(R, sp.S.face)
	end
	Crew.say(crew, R, "relay", { item = job.item, table = job.table or "" }, "busy", 2.4)
	local cook = Crew.makerRig(crew)
	if cook and cook ~= R then
		task.delay(0.9, function()
			if Rig.alive(cook) then
				Rig.emote(cook, "nod")
				Crew.say(crew, cook, "cookAck", { item = job.item }, "plain", 2.2)
			end
		end)
	end
	if Crew.hold(crew, R, tok, 1.0) == "abort" then
		return
	end
	goHome(crew, R, tok)
end

function Crew.jobs.relay(item: string, tableId: number?): any
	return { kind = "relay", prio = P_RELAY, key = "relay" .. tostring(tableId or "c") .. item, item = item, table = tableId, run = relayRun, preempt = true }
end

-- clear a table after the guests left ----------------------------------------------------------------
local function occupied(crew: any, tableId: number): boolean
	for _, s in crew.seatOf do
		if s.table == tableId then
			return true
		end
	end
	return false
end
Crew.occupied = occupied

local function clearRun(crew: any, R: any, job: any, tok: number)
	local tableId = job.table
	if occupied(crew, tableId) then
		return
	end
	local had = Bridge.tableDishCount(crew.key, tableId)
	local e = crew.site.spots.A[tableId]
	if not e then
		return
	end
	if not Crew.walkTo(crew, R, tok, e.best, nil, "behind") then
		return
	end
	Rig.face(R, e.best.face)
	Rig.act(R, "wipe")
	if had > 0 and math.random() < 0.6 then
		Crew.say(crew, R, "clear", nil, "plain", 2.4)
	end
	-- wipe until ShopLife takes the dishes away (it does, ~25 s after the guests left)
	local res = Crew.hold(crew, R, tok, if had > 0 then 30 else 4, function()
		return occupied(crew, tableId) or (had > 0 and Bridge.tableDishCount(crew.key, tableId) == 0)
	end)
	if res == "abort" then
		return
	end
	Rig.act(R, "idle")
	if had > 0 and not occupied(crew, tableId) then
		Rig.carry(R, "empty")
		local sp = crew.site.spots
		if sp.S then
			if not Crew.walkTo(crew, R, tok, sp.S, nil, "crew_tray2") then
				Rig.carry(R, "")
				return
			end
			Rig.face(R, sp.S.face)
			if Crew.hold(crew, R, tok, 0.6) == "abort" then
				Rig.carry(R, "")
				return
			end
		end
		Rig.carry(R, "")
	end
	goHome(crew, R, tok)
end

function Crew.jobs.clear(tableId: number): any
	return { kind = "clear", prio = P_CLEAR, key = "clear" .. tableId, table = tableId, run = clearRun, preempt = true, requeue = 2, onAbort = function(_, R2)
		Rig.carry(R2, "")
	end }
end

-- point the way to a free table (the dialog's 자리 있어요?) --------------------------------------------
local function pointRun(crew: any, R: any, job: any, tok: number)
	local e = crew.site.spots.A[job.table]
	if e then
		Rig.face(R, e.best.pos)
	end
	Rig.emote(R, "point_proc")
	Crew.hold(crew, R, tok, 1.6)
end

function Crew.jobs.point(tableId: number): any
	return { kind = "point", prio = P_RELAY, table = tableId, run = pointRun, preempt = true }
end

-- idle life ---------------------------------------------------------------------------------------------
local REST = {
	cook = { "cook", "chop", "wipe", "arms_crossed", "cook" },
	barista = { "cup", "wipe", "teller", "cup" },
	baker = { "cook", "wipe", "teller" },
	cashier = { "teller", "typing", "behind" },
	pharmacist = { "typing", "teller", "clipboard" },
	stylist = { "behind", "teller", "phone" },
	waiter = { "behind", "look", "teller" },
	floor = { "behind", "look" },
	stocker = { "work", "look", "behind" },
}
local COOK_ACTS: { [string]: { string } } = {
	pub = { "cup", "wipe", "arms_crossed" },
	cafe = { "cup", "wipe", "teller" },
	rawfish = { "chop", "chop", "wipe" },
	seafood = { "chop", "cook", "wipe" },
	grill = { "flip", "wipe", "arms_crossed" },
	pocha = { "cook", "chop", "wipe" },
	burger = { "flip", "cook", "wipe" },
	dessert = { "cup", "wipe", "teller" },
}

local function freeTables(crew: any): { number }
	local out = {}
	for id, _ in crew.site.spots.A do
		if not occupied(crew, id) then
			table.insert(out, id)
		end
	end
	return out
end
Crew.freeTables = freeTables

local function idleRun(crew: any, R: any, job: any, tok: number)
	local role = R.role
	local sp = crew.site.spots
	local roll = math.random()
	if role == "waiter" or role == "floor" then
		local free = freeTables(crew)
		if #free > 0 and roll < 0.45 then
			local id = free[math.random(1, #free)]
			local e = sp.A[id]
			if e and Crew.walkTo(crew, R, tok, e.best, nil, "behind") then
				Rig.face(R, e.best.face)
				Rig.act(R, "wipe")
				if Crew.hold(crew, R, tok, rand(3, 5)) == "abort" then
					return
				end
				goHome(crew, R, tok)
			end
			return
		end
		if role == "floor" and #sp.idle > 0 and roll < 0.8 then
			local s = sp.idle[math.random(1, #sp.idle)]
			if Crew.walkTo(crew, R, tok, s, nil, "behind") then
				Rig.face(R, s.face)
				Rig.act(R, "wipe")
				if Crew.hold(crew, R, tok, rand(3, 6)) == "abort" then
					return
				end
				goHome(crew, R, tok)
			end
			return
		end
		Rig.act(R, REST[role][math.random(1, #REST[role])])
		Crew.hold(crew, R, tok, rand(6, 12))
		return
	end
	if role == "stocker" and #sp.idle > 0 and roll < 0.7 then
		local s = sp.idle[math.random(1, #sp.idle)]
		Rig.carry(R, "box")
		if Crew.walkTo(crew, R, tok, s, nil, "crew_box") then
			Rig.face(R, s.face)
			Rig.carry(R, "")
			Rig.act(R, "work")
			if Crew.hold(crew, R, tok, rand(4, 7)) == "abort" then
				return
			end
		end
		Rig.carry(R, "")
		goHome(crew, R, tok)
		return
	end
	-- makers and counter staff work in place
	local list = (role == "cook" and COOK_ACTS[crew.site.type]) or REST[role] or REST.cashier
	if crew.cookUntil > now() then
		return
	end
	Rig.act(R, list[math.random(1, #list)])
	Crew.hold(crew, R, tok, rand(7, 14))
end

function Crew.jobs.idle(): any
	return { kind = "idle", prio = P_IDLE, run = idleRun, preempt = true }
end

-------------------------------------------------------------------------------------------------
-- spawn / despawn
-------------------------------------------------------------------------------------------------
local function accentOf(site: any): string?
	local a = site.def and site.def.accent
	if type(a) == "table" and #a >= 3 then
		return string.format("%d,%d,%d", a[1], a[2], a[3])
	end
	return nil
end

function Crew.new(site: any, opts: any?): any?
	local o = opts or {}
	local crew: any = {
		key = site.key,
		site = site,
		rigs = {},
		queue = {},
		alive = true,
		born = now(),
		lastTick = now(),
		errors = 0,
		staffModeOn = false,
		coexist = o.coexist == true,
		seatOf = {}, -- "u<uid>" / "n<npc>" -> { table, seat }
		orderedAt = {}, -- uid -> time of the last order event
		taking = {}, -- uid -> until (the player said 주문할게요)
		greetAt = {},
		pushedAt = {},
		checked = {},
		lastServe = {},
		lastLine = {},
		cookUntil = 0,
		cookLineAt = 0,
		banterAt = now() + rand(20, 40),
		restAct = {},
		moodRef = o.moodRef or { v = Config.MOOD.base },
		diners = {},
	}
	local spawned = 0
	local color = accentOf(site)
	for _, def in site.roles do
		if not (crew.coexist and def.role == "waiter") then
			local home = homeOf(crew, def.role)
			if home then
				local persona = Personas.make(site.key, site.type, def)
				local id = Config.NPC_PREFIX .. Util.hash6(site.key) .. "_" .. def.role
				local R = Rig.build({
					id = id,
					name = "Crew_" .. def.role .. "_" .. persona.given,
					persona = persona,
					role = def.role,
					shop = site.key,
					pos = home.pos,
					yaw = home.yaw,
					kind = "crew",
					prompt = true,
					color = color,
					act = REST[def.role] and REST[def.role][1] or "idle",
					seed = persona.seed,
				})
				if R then
					R.crew = crew
					crew.rigs[def.role] = R
					crew.queue[def.role] = {}
					crew.restAct[def.role] = REST[def.role] and REST[def.role][1] or "idle"
					R.nextIdle = now() + rand(4, 12)
					if home.face then
						Rig.face(R, home.face)
					end
					spawned += 1
				end
			end
		end
	end
	if spawned == 0 then
		return nil
	end
	-- serving belongs to our waiter now (ShopLife still cooks)
	if Crew.waiter(crew) and not crew.coexist then
		local r = Bridge.req("staffMode", { shop = site.key, on = true, roles = { cook = false, serve = true } })
		crew.staffModeOn = r.ok == true
	end
	-- players already seated (the crew arrives while they eat)
	for _, p in Players:GetPlayers() do
		local key, tableId, seatId = Bridge.seatOf(p)
		if key == site.key and tableId then
			crew.seatOf["u" .. p.UserId] = { table = tableId, seat = seatId }
		end
	end
	Sites.publish(site)
	return crew
end

function Crew.staffModeOff(crew: any)
	if crew.staffModeOn then
		crew.staffModeOn = false
		Bridge.req("staffMode", { shop = crew.key, on = false })
		Serve.flush(crew.key)
	end
end

function Crew.destroy(crew: any, why: string?)
	if not crew.alive then
		return
	end
	crew.alive = false
	crew.why = why
	-- serving goes back to ShopLife first: nothing waits for a waiter that is leaving
	Crew.staffModeOff(crew)
	for _, R in crew.rigs do
		if R.job and R.job.orders then
			for _, o in R.job.orders do
				Serve.release(o)
			end
		end
		Rig.destroy(R)
	end
	crew.rigs = {}
	crew.queue = {}
end

-------------------------------------------------------------------------------------------------
-- the 4 Hz tick
-------------------------------------------------------------------------------------------------
local function nearestPlayer(pos: Vector3, r: number): (Player?, number)
	local best, bd = nil, r
	for _, p in Players:GetPlayers() do
		local pp = Bridge.posOf(p)
		if pp and math.abs(pp.Y - pos.Y - 3) < 6 then
			local d = flatDist(pp, pos)
			if d < bd then
				best, bd = p, d
			end
		end
	end
	return best, bd
end
Crew.nearestPlayer = nearestPlayer

local function banter(crew: any)
	local idle = {}
	for _, R in crew.rigs do
		if Rig.alive(R) and (not R.job or R.job.kind == "idle") then
			table.insert(idle, R)
		end
	end
	if #idle < 2 then
		return
	end
	local p = nearestPlayer(idle[1].pos, 20)
	if not p then
		return
	end
	local a, b = idle[1], idle[2]
	local i = math.random(1, 4)
	local la = Lines.list("banterA", a.persona.dialect, crew.site.type)
	local lb = Lines.list("banterB", b.persona.dialect, crew.site.type)
	if not la or not lb then
		return
	end
	Rig.face(a, b.pos)
	Rig.say(a, la[((i - 1) % #la) + 1], 3)
	task.delay(1.8, function()
		if crew.alive and Rig.alive(b) then
			Rig.face(b, a.pos)
			Rig.say(b, lb[((i - 1) % #lb) + 1], 3)
		end
	end)
end

function Crew.tick(crew: any)
	if not crew.alive then
		return
	end
	local t = now()
	crew.lastTick = t
	local key = crew.key
	-- trays first: a ready table order makes a serve job for its table
	local waiter = Crew.waiter(crew)
	if waiter then
		for _, o in Serve.poll(key, crew.site.menuKey) do
			local _ = o -- (adopted: readyFor() below picks it up)
		end
		for _, o in Serve.readyFor(key) do
			if o.table and t - (o.readyAt or t) >= 0.6 then
				Crew.enqueue(crew, "waiter", Crew.jobs.serve(o.table, { o }))
			end
		end
	end
	for role, R in crew.rigs do
		if Rig.alive(R) then
			local q = crew.queue[role]
			local cur = R.job
			if cur and cur.done then
				R.job = nil
				cur = nil
			end
			-- preempt
			if cur and q[1] and cur.preempt and q[1].prio < cur.prio then
				abortJob(crew, R)
				cur = nil
			end
			if not cur and q[1] then
				local job = table.remove(q, 1)
				startJob(crew, R, job)
			elseif not cur and t >= (R.nextIdle or 0) then
				R.nextIdle = t + rand(14, 32)
				startJob(crew, R, Crew.jobs.idle())
			end
			-- a player walking up to an idle rig gets a look
			if (not R.job or R.job.kind == "idle") and not R.walking then
				local p, d = nearestPlayer(R.pos, 4)
				local want = if p and d < 4 then p.UserId else 0
				if (R.looking or 0) ~= want then
					R.looking = want
					Rig.look(R, want)
				end
			end
		end
	end
	if t > crew.banterAt then
		crew.banterAt = t + Config.BANTER_GAP + rand(0, 40)
		banter(crew)
	end
	-- mood recovers slowly
	local m = crew.moodRef
	if m.v < Config.MOOD.base then
		m.v = math.min(Config.MOOD.base, m.v + Config.MOOD.recoverPerMin * Config.TICK / 60)
	end
end

-------------------------------------------------------------------------------------------------
-- bus events
-------------------------------------------------------------------------------------------------
local FX_ACT = { boil = "cook", steam = "cook", pot = "cook", fry = "cook", wok = "cook", chop = "chop", cut = "chop", sashimi = "chop", grill = "flip", flip = "flip", espresso = "cup", pour = "cup", tap = "cup", scoop = "cup", blend = "cup", ice = "cup", bake = "cook", toast = "flip" }

local function greet(crew: any, uid: number)
	local R = Crew.greeter(crew)
	if not R or crew.site.staffed then
		return
	end
	local t = now()
	if crew.greetAt[uid] and t - crew.greetAt[uid] < Config.GREET_GAP then
		return
	end
	crew.greetAt[uid] = t
	local p = Bridge.playerById(uid)
	if not p then
		return
	end
	local v = Regulars.view(uid, crew.key)
	local key = "greet"
	local vars: any = { name = p.DisplayName, fav = v.fav }
	local flow = crew.site.flow
	if v.level >= Config.REGULAR.nameLevel and v.fav then
		key = "greetRegular"
	elseif v.level >= Config.REGULAR.nameLevel then
		key = "greetNamed"
	elseif (Bridge.need(p, "Satiety") or 100) < 25 and (flow == "table" or flow == "counter") then
		key = "greetHungry"
	elseif flow == "kiosk" then
		key = "greetKiosk"
	elseif flow == "counter" then
		key = "greetCounter"
	elseif flow == "pick" or flow == "service" then
		key = "greetShop"
	else
		local c = Lighting.ClockTime
		if c >= 22 or c < 4 then
			key = "greetNight"
		end
	end
	Rig.look(R, uid)
	Rig.emote(R, if math.random() < 0.5 then "wave_small" else "bow")
	Crew.say(crew, R, key, vars, "happy", 3.4)
	task.delay(3.5, function()
		if Rig.alive(R) and (R.looking or 0) == 0 then
			Rig.look(R, 0)
		end
	end)
end

local function itemName(crew: any, id: any): string
	local SS = Bridge.SS
	if SS and crew.site.menuKey then
		local ok, it = pcall(SS.item, crew.site.menuKey, id)
		if ok and it then
			return it.name
		end
	end
	return tostring(id)
end
Crew.itemName = itemName

local function itemDef(crew: any, id: any): any?
	local SS = Bridge.SS
	if SS and crew.site.menuKey then
		local ok, it = pcall(SS.item, crew.site.menuKey, id)
		if ok then
			return it
		end
	end
	return nil
end

function Crew.onBus(crew: any, kind: string, d: any)
	if not crew.alive then
		return
	end
	local uid = tonumber(d.userId)
	local site = crew.site
	if kind == "enter" and uid then
		greet(crew, uid)
	elseif kind == "seat" then
		if uid and type(d.table) == "number" then
			crew.seatOf["u" .. uid] = { table = d.table, seat = d.seat }
			crew.checked[uid] = nil
			local t = now()
			local waiter = Crew.waiter(crew)
			if waiter and site.flow == "table" and (not crew.pushedAt[uid] or t - crew.pushedAt[uid] > Config.PUSH_GAP) then
				crew.pushedAt[uid] = t
				Crew.enqueue(crew, "waiter", Crew.jobs.visit("welcome", uid, d.table, d.seat, true))
			end
		elseif d.npc and type(d.table) == "number" then
			crew.seatOf["n" .. tostring(d.npc)] = { table = d.table, seat = d.seat }
		end
	elseif kind == "stand" then
		local k = if uid then "u" .. uid elseif d.npc then "n" .. tostring(d.npc) else nil
		if k then
			local s = crew.seatOf[k]
			crew.seatOf[k] = nil
			local tableId = (s and s.table) or d.table
			if type(tableId) == "number" and not occupied(crew, tableId) and Crew.waiter(crew) then
				task.delay(2.5, function()
					if crew.alive and not occupied(crew, tableId) then
						Crew.enqueue(crew, "waiter", Crew.jobs.clear(tableId))
					end
				end)
			end
		end
		if uid then
			crew.taking[uid] = nil
		end
	elseif kind == "order" then
		local list = Serve.onOrder(d, site.menuKey)
		local first = type(d.items) == "table" and d.items[1]
		local name = if first then tostring(first.name or itemName(crew, first.id)) else "주문"
		local count = if type(d.items) == "table" then #d.items else 1
		if uid then
			crew.orderedAt[uid] = now()
			crew.taking[uid] = nil
			local waiter = Crew.waiter(crew)
			if site.flow == "table" and waiter and d.table then
				local job = waiter.job
				local atTable = job and (job.kind == "welcome" or job.kind == "call" or job.kind == "take") and job.uid == uid
				local e = site.spots.A[d.table]
				local near = e and flatDist(Rig.feet(waiter), e.best.pos) < 6
				if atTable or near then
					Rig.emote(waiter, "nod")
				end
				Crew.say(crew, waiter, if count > 1 then "orderAckMany" else "orderAck", { item = name, count = count - 1 }, "happy", 2.6)
				Crew.enqueue(crew, "waiter", Crew.jobs.relay(name, d.table))
			else
				local R = Crew.cashierRig(crew)
				if R then
					Rig.emote(R, "nod")
					Crew.say(crew, R, if site.flow == "kiosk" then "kioskAck" elseif count > 1 then "orderAckMany" else "orderAck", { item = name, count = count - 1 }, "happy", 2.6)
				end
			end
		elseif d.npc then
			if Crew.waiter(crew) then
				Crew.enqueue(crew, "waiter", Crew.jobs.relay(name, d.table))
			end
		end
		local _ = list
	elseif kind == "cooking" then
		local o = Serve.onCooking(d)
		local R = Crew.makerRig(crew)
		local secs = tonumber(d.seconds) or 8
		local it = itemDef(crew, d.item)
		if R then
			local act = (it and FX_ACT[it.fx or ""]) or (COOK_ACTS[site.type] and COOK_ACTS[site.type][1]) or "cook"
			crew.cookUntil = now() + secs
			if not R.job or R.job.kind == "idle" then
				if R.job then
					abortJob(crew, R)
				end
				Rig.act(R, act)
			end
			local t = now()
			if t - crew.cookLineAt > 20 and math.random() < 0.6 then
				crew.cookLineAt = t
				task.delay(rand(1, 3), function()
					if crew.alive and Rig.alive(R) then
						Crew.say(crew, R, "cooking", { item = it and it.name or "" }, "busy", 3)
					end
				end)
			end
			task.delay(secs, function()
				if crew.alive and Rig.alive(R) and now() >= crew.cookUntil - 0.05 and (not R.job or R.job.kind == "idle") then
					Rig.act(R, crew.restAct[R.role] or "idle")
				end
			end)
			-- the kitchen fx (steam / sizzle / progress) on the clients near the cook
			Net.fireNear(R.pos, 45, "cook", { shop = crew.key, id = R.id, item = it and it.name or "", icon = it and it.icon or "🍳", fx = it and it.fx or "boil", seconds = secs, order = o and o.id })
		end
	elseif kind == "ready" then
		local o = Serve.onReady(d, site.menuKey)
		local R = Crew.makerRig(crew)
		local name = (o and o.name) or itemName(crew, d.item)
		if d.where == "table" then
			if R and Crew.waiter(crew) then
				Rig.emote(R, "nod")
				Crew.say(crew, R, "readyCall", { item = name, table = (o and o.table) or "" }, "busy", 2.6)
			end
		elseif d.where == "pickup" then
			local caller = R or Crew.cashierRig(crew)
			if caller then
				Rig.carry(caller, Util.encodeCarry({ { kind = "dish", menu = site.menuKey or "", item = tostring(d.item), qty = 1 } }))
				task.delay(1.4, function()
					if crew.alive and Rig.alive(caller) then
						local n = tonumber(d.number)
						Crew.say(crew, caller, "pickupCall", { n = if n then string.format("%03d", n) else "", item = name }, "happy", 3.4)
						task.delay(2.2, function()
							if Rig.alive(caller) then
								Rig.carry(caller, "")
							end
						end)
					end
				end)
			end
		end
	elseif kind == "served" then
		Serve.onServed(d)
	elseif kind == "pickup" then
		Serve.onPickup(d)
		local R = Crew.cashierRig(crew)
		if R and uid then
			Rig.look(R, uid)
			Crew.say(crew, R, "pickupThanks", nil, "happy", 2.4)
		end
	elseif kind == "finished" and uid then
		local s = crew.seatOf["u" .. uid]
		if s and not crew.checked[uid] and Crew.waiter(crew) then
			crew.checked[uid] = true
			task.delay(8, function()
				if crew.alive and seatedHere(crew, uid, s.table) then
					Crew.enqueue(crew, "waiter", Crew.jobs.visit("check", uid, s.table, s.seat, true))
				end
			end)
		end
	elseif kind == "call" and uid and type(d.table) == "number" then
		local waiter = Crew.waiter(crew)
		if waiter then
			local job = waiter.job
			local already = job and (job.kind == "welcome" or job.kind == "call" or job.kind == "take") and job.uid == uid and not job.done
			if already then
				crew.taking[uid] = now() + Config.CALL_STAY
			else
				local s = crew.seatOf["u" .. uid]
				Crew.enqueue(crew, "waiter", Crew.jobs.visit("call", uid, d.table, s and s.seat, false))
			end
		end
	elseif kind == "cheers" then
		local waiter = Crew.waiter(crew)
		if waiter and type(d.table) == "number" then
			local e = site.spots.A[d.table]
			if e and flatDist(Rig.feet(waiter), e.best.pos) < 14 then
				Rig.emote(waiter, "clap")
				Crew.say(crew, waiter, "cheers", nil, "happy", 2.4)
			end
		end
	elseif kind == "grill" and d.action == "burnt" then
		local waiter = Crew.waiter(crew) or Crew.makerRig(crew)
		if waiter then
			Crew.say(crew, waiter, "burnt", nil, "busy", 3)
		end
	elseif kind == "paid" and uid then
		local p = Bridge.playerById(uid)
		local R = Crew.cashierRig(crew)
		local res = if p then Regulars.onPaid(p, crew.key, site.name, d) else {}
		if R and p then
			local pp = Bridge.posOf(p)
			if pp and flatDist(pp, R.pos) < 26 then
				Rig.look(R, uid)
				Rig.emote(R, "bow")
				if res.coupon then
					Crew.say(crew, R, "couponUse", nil, "happy", 3)
				elseif res.up then
					Crew.say(crew, R, "regularUp", nil, "happy", 3.4)
				elseif res.visit and res.stamp and math.random() < 0.5 then
					Crew.say(crew, R, "stamp", { stamps = res.stamp }, "happy", 3)
				else
					Crew.say(crew, R, "paid", nil, "happy", 3)
				end
			end
		end
		if p then
			local lines = {}
			for _, it in (if type(d.items) == "table" then d.items else {}) do
				if type(it) == "table" then
					table.insert(lines, { name = tostring(it.name or it.id or "?"), qty = tonumber(it.qty) or 1, price = tonumber(it.price) or 0 })
				end
			end
			local v = Regulars.view(uid, crew.key)
			Net.fire(p, "receipt", {
				shop = crew.key,
				shopName = site.name,
				items = lines,
				total = tonumber(d.total) or 0,
				auto = d.auto == true,
				mode = d.mode,
				stamp = res.stamp,
				stampsMax = Config.REGULAR.stampsPerCoupon,
				coupon = res.coupon,
				newCoupon = res.newCoupon,
				level = v.level,
				title = v.title,
				staff = R and R.persona.title or nil,
			})
			if res.up then
				Net.fire(p, "regular.up", { shop = crew.key, shopName = site.name, level = res.level, title = res.title })
			end
			if res.coupon then
				Bridge.toast(p, string.format("🎟️ 단골 쿠폰 사용! %s 돌려받았어요", Util.won(res.coupon)), "ok")
			end
		end
	elseif kind == "dash" and uid then
		local R = Crew.cashierRig(crew)
		if R then
			Crew.say(crew, R, "dash", nil, "busy", 3)
		end
	elseif kind == "leave" and uid then
		crew.taking[uid] = nil
		local R = Crew.greeter(crew)
		if R and not site.staffed and (tonumber(d.unpaid) or 0) <= 0 then
			local t = now()
			if not crew.lastLine["bye" .. uid] or t - crew.lastLine["bye" .. uid] > 60 then
				crew.lastLine["bye" .. uid] = t
				Crew.say(crew, R, "bye", nil, "happy", 2.4)
			end
		end
	end
end

-- a player said 주문할게요 in a dialog: the waiter stays at the table with the order pad
function Crew.takingOrder(crew: any, uid: number)
	crew.taking[uid] = now() + Config.CALL_STAY
	local waiter = Crew.waiter(crew)
	local s = crew.seatOf["u" .. uid]
	if waiter and s then
		local job = waiter.job
		if not (job and job.uid == uid and not job.done) then
			Crew.enqueue(crew, "waiter", Crew.jobs.visit("take", uid, s.table, s.seat, false))
		end
	end
end

function Crew.status(crew: any): any
	local rigs = {}
	for role, R in crew.rigs do
		rigs[role] = { id = R.id, job = R.job and R.job.kind or "-", queue = #crew.queue[role] }
	end
	return { key = crew.key, name = crew.site.name, rigs = rigs, staffMode = crew.staffModeOn, errors = crew.errors, lastError = crew.lastError }
end

return Crew
