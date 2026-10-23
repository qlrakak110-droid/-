--!nocheck
-- t_crew.luau <fixture>: the crew brain end to end on a fake ShopLife bus (virtual time):
-- spawn -> seat (welcome + pushed dialog) -> player order -> cooking -> ready -> the waiter serves -> pay -> stand
-- -> clear; NPC diners arrive / order / eat / pay / leave; dialogs through Talk.choose; stand-down; no stuck orders.
local B = require("./simmods")
local req, R, SIM = B.req, B.R, B.SIM
local task = SIM.task
local G = R.G
local Vector3, CFrame = G.Vector3, G.CFrame
local Instance = R.env.Instance
local args = { ... }
local fx = require("../../../bprev/fx/" .. (args[1] or "kor_gukbap"))(G.Vector3, G.Color3, G.CFrame)
local model = R.loadFixture(fx)
local rec = req("Scan").shop(model, "street", 1)
assert(rec, "no rec")
local KEY = rec.key
local Shared = req("CS_init")
local Config = Shared.Config
Config.DINERS.occBase, Config.DINERS.occPeak, Config.DINERS.occNight, Config.DINERS.occLate = 1, 1, 1, 1
Config.DINERS.maxShare = 0.6
Config.DINERS.keepFree = 1
Config.DINERS.gap = { 2, 3 }
Config.DINERS.eat = { 6, 8 }
local Bridge = req("SV_Bridge")
local Net = req("SV_Net")
local Sites, Rig, Serve, Regulars, Crew, Diners, Talk, Augment, Director = req("SV_Sites"), req("SV_Rig"), req("SV_Serve"), req("SV_Regulars"), req("SV_Crew"), req("SV_Diners"), req("SV_Talk"), req("SV_Augment"), req("SV_Director")
Bridge.init(Config)
local SS = req("SS")
Bridge.SS = SS
-- fake looks
Bridge.Looks = {
	random = function(seed, hint) return { seed = seed, hint = hint } end,
	build = function(spec, opts)
		local m = Instance.new("Model")
		m.Name = opts.name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Parent = m
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Parent = m
		local torso = Instance.new("Part")
		torso.Name = "UpperTorso"
		torso.Parent = m
		m.PrimaryPart = root
		return { model = m, root = root, head = head, ground = 3 }
	end,
}
-- the player
local Players = R.env.game:GetService("Players")
local player = Players:GetPlayers()[1]
local UID = player.UserId
local ppos = rec.center + Vector3.new(0, 3, 0)
-- fake bus ----------------------------------------------------------------------------------------
local orders, seq = {}, 0
local seatTaken = {}
local session = { seat = nil }
local staff = nil
local events = {}
local dishes = {} -- tableId -> n
local function emit(kind, d)
	d.shop = KEY
	d.shopName = rec.name
	d.shopType = rec.type
	table.insert(events, string.format("%.1f %s %s", SIM.t, kind, tostring(d.orderId or d.npc or d.userId or "")))
	task.defer(function()
		Director.onBus(kind, d)
	end)
end
local function cook(o)
	task.delay(0.8, function()
		o.phase = "cooking"
		emit("cooking", { orderId = o.orderId, item = o.item, seconds = 3 })
		task.delay(3, function()
			o.phase = "ready"
			o.readyT = SIM.t
			emit("ready", { orderId = o.orderId, item = o.item, where = "table" })
			if not (staff and staff.serve) then
				task.delay(0.8, function()
					if o.phase == "ready" then
						o.phase = "served"
						dishes[o.table] = (dishes[o.table] or 0) + 1
						emit("served", { orderId = o.orderId, item = o.item, table = o.table, seat = o.seat, npc = o.npc, userId = o.owner })
					end
				end)
			end
		end)
	end)
end
local function place(owner, npc, item, tableId, seatId)
	seq += 1
	local o = { orderId = "o" .. seq, item = item, name = item, phase = "placed", table = tableId, seat = seatId, dest = "table", owner = owner, npc = npc }
	orders[o.orderId] = o
	cook(o)
	return o
end
local served = {}
Bridge.req = function(op, d)
	if op == "staffMode" then
		staff = if d.on == false then nil else d.roles
		return { ok = true }
	elseif op == "queue" then
		local l = {}
		for _, o in orders do
			if o.phase ~= "gone" then
				table.insert(l, { orderId = o.orderId, item = o.item, name = o.name, phase = o.phase, table = o.table, seat = o.seat, dest = o.dest })
			end
		end
		return { ok = true, orders = l }
	elseif op == "serve" then
		local o = orders[d.orderId]
		if not o or o.phase ~= "ready" then
			return { ok = false, code = "bad_phase" }
		end
		o.phase = "served"
		served[o.orderId] = (served[o.orderId] or 0) + 1
		dishes[o.table] = (dishes[o.table] or 0) + 1
		emit("served", { orderId = o.orderId, item = o.item, table = o.table, seat = o.seat, npc = o.npc, userId = o.owner })
		return { ok = true }
	elseif op == "claimSeat" then
		for _, tb in rec.tables do
			if tb.id == d.table then
				for _, s in tb.seats do
					if not seatTaken[tb.id .. ":" .. s.id] then
						seatTaken[tb.id .. ":" .. s.id] = d.npc
						emit("seat", { npc = d.npc, table = tb.id, seat = s.id, cf = s.cf })
						return { ok = true, seat = s.id, table = tb.id, cf = s.cf }
					end
				end
			end
		end
		return { ok = false, code = "full" }
	elseif op == "npcOrder" then
		local tableId, seatId
		for k, v in seatTaken do
			if v == d.npc then
				local a, b = string.match(k, "^(%d+):(%d+)$")
				tableId, seatId = tonumber(a), tonumber(b)
			end
		end
		local o = place(nil, d.npc, d.items[1], tableId, seatId)
		emit("order", { orderId = o.orderId, npc = d.npc, items = { { id = o.item, name = o.item, qty = 1 } }, table = tableId, seat = seatId })
		return { ok = true, orderId = o.orderId, orderIds = { o.orderId } }
	elseif op == "npcEat" then
		return { ok = true }
	elseif op == "npcLeave" then
		for k, v in seatTaken do
			if v == d.npc then
				seatTaken[k] = nil
				local a = string.match(k, "^(%d+):")
				emit("stand", { npc = d.npc, table = tonumber(a) })
				local tid = tonumber(a)
				task.delay(6, function()
					dishes[tid] = 0
				end)
			end
		end
		return { ok = true }
	elseif op == "shops" then
		return { ok = true, shops = { { key = KEY, active = true } } }
	elseif op == "menu" then
		return { ok = true, items = {} }
	end
	return { ok = false, code = "unknown_op" }
end
Bridge.shopRec = function(k) return if k == KEY then rec else nil end
Bridge.shops = function() return { rec } end
Bridge.staffSites = function() return {} end
Bridge.jobSites = function() return {} end
Bridge.has = function() return false end
local working = false
Bridge.working = function() return working end
Bridge.posOf = function(p) return if p == player then ppos else nil end
Bridge.playerById = function(uid) return if uid == UID then player else nil end
Bridge.seatOf = function(p) if session.seat then return KEY, session.seat.table, session.seat.seat end return nil end
Bridge.shopOf = function() return KEY end
Bridge.tableDishCount = function(_, t) return dishes[t] or 0 end
Bridge.dishesOfPlayer = function() return {} end
Bridge.bill = function() return 9000, { { name = "돼지국밥", qty = 1, price = 9000 } } end
local acts = {}
Bridge.lifeAct = function(_, a) table.insert(acts, "act:" .. a) if a == "order" then emit("call", { userId = UID, table = session.seat and session.seat.table }) end return { ok = true } end
Bridge.lifePrompt = function(_, _, kind) table.insert(acts, "prompt:" .. kind) return true end
Bridge.needs = function() return true end
Bridge.toast = function() return true end
Bridge.spend = function() return true end
Bridge.earn = function() return true end
Bridge.destinations = function() return { { name = "광안리해수욕장 (중앙)", pos = Vector3.new(-19.9, 3.2, -70), order = 11 }, { name = "광안리 SUP존", pos = Vector3.new(1715.6, 3.3, -135.6), order = 12 } } end
-- net
local fired = {}
Net.on = function() end
Net.fire = function(p, kind, d) table.insert(fired, kind) if kind == "dialog" then fired.lastDialog = d end end
Net.fireNear = function(_, _, kind, d) table.insert(fired, kind) if kind == "say" then fired.says = (fired.says or 0) + 1 fired.lastSay = d.text end end
-- wire like init.server
local mods = { Sites = Sites, Rig = Rig, Serve = Serve, Regulars = Regulars, Crew = Crew, Diners = Diners, Talk = Talk, Augment = Augment }
Sites.init(Shared, Bridge)
Rig.init(Shared, Bridge, Net)
Serve.init(Shared, Bridge, Net)
Regulars.init(Shared, Bridge, Net)
Crew.init(Shared, Bridge, Net, mods)
Diners.init(Shared, Bridge, Net, mods)
Talk.init(Shared, Bridge, Net, mods)
Augment.init(Shared, Bridge, Net, mods)
Director.init(Shared, Bridge, Net, mods)
Crew.setTalk(Talk)
Talk.setResolver(Director.resolve)
local function run(secs)
	local n = math.floor(secs / 0.05)
	for _ = 1, n do
		SIM.step(0.05)
	end
end
task.spawn(Director.start)
emit("open", {})
run(3)
local st = Director.status()
print("crews", #st.crews, "rigs", st.rigs, "site", st.sites[KEY] and st.sites[KEY].ok, st.sites[KEY] and st.sites[KEY].why)
assert(#st.crews == 1, "crew spawned")
assert(staff and staff.serve, "staffMode on")
local crew = Director.crewOf(KEY)
local waiter = Crew.waiter(crew)
assert(waiter, "waiter")
-- 1. the player sits at table 1
local tb1 = rec.tables[1]
session.seat = { table = tb1.id, seat = tb1.seats[1].id }
ppos = tb1.seats[1].top + Vector3.new(0, 2, 0)
emit("seat", { userId = UID, table = tb1.id, seat = tb1.seats[1].id, cf = tb1.seats[1].cf })
run(10)
print("dialog pushed", fired.lastDialog and fired.lastDialog.text, "waiter job", waiter.job and waiter.job.kind)
assert(fired.lastDialog, "welcome dialog pushed")
-- 2. the player picks 주문할게요 in the pushed dialog
ppos = waiter.pos + Vector3.new(1, 3, 0)
local dlg = fired.lastDialog
local r = Talk.choose(player, { crew = dlg.crewId, token = dlg.token, choice = "order" })
print("choose order ->", r.ok, r.close, table.concat(acts, ","))
run(1)
-- 3. order arrives
local o1 = place(UID, nil, "dwaeji", tb1.id, tb1.seats[1].id)
emit("order", { userId = UID, items = { { id = "dwaeji", name = "돼지국밥", qty = 1 } }, table = tb1.id, seat = tb1.seats[1].id })
local t0 = SIM.t
run(16)
local readyT, servedT
for _, e in events do
	local t, k, id = string.match(e, "^([%d%.]+) (%S+) (%S*)")
	if id == o1.orderId and k == "ready" then readyT = tonumber(t) end
	if id == o1.orderId and k == "served" then servedT = tonumber(t) end
end
print("o1 phase", o1.phase, "served count", served[o1.orderId], "ready->served", servedT and readyT and (servedT - readyT))
assert(o1.phase == "served" and served[o1.orderId] == 1, "served once by the waiter")
print("waiter carry now", waiter.carry, waiter.job and waiter.job.kind)
-- 4. paid + stand + clear
emit("paid", { userId = UID, total = 9000, items = { { name = "돼지국밥", qty = 1, price = 9000 } } })
run(1)
session.seat = nil
emit("stand", { userId = UID, table = tb1.id, seat = tb1.seats[1].id })
task.delay(8, function() dishes[tb1.id] = 0 end)
run(20)
print("events", #events, "fired", #fired, "says", fired.says, fired.lastSay)
-- 5. dialogs
ppos = waiter.pos + Vector3.new(1, 3, 0)
local T = Director.resolve(waiter.id)
local d1 = Talk.open(player, T, true)
assert(d1 and #d1.choices > 0, "root dialog")
local ids = {}
for _, c in d1.choices do table.insert(ids, c.id) end
print("root:", d1.text, table.concat(ids, ","))
local d2 = Talk.choose(player, { crew = T.id, token = d1.token, choice = "more" })
local d3 = Talk.choose(player, { crew = T.id, token = d2.dialog.token, choice = "dirs" })
print("dirs:", d3.dialog.text, d3.dialog.choices[1].label)
local d4 = Talk.choose(player, { crew = T.id, token = d3.dialog.token, choice = "d_1" })
print("d_1:", d4.dialog and d4.dialog.text)
local d5 = Talk.choose(player, { crew = T.id, token = d4.dialog.token, choice = "tip" })
local d6 = Talk.choose(player, { crew = T.id, token = d5.dialog.token, choice = "tip_1000" })
print("tip:", d6.dialog.text, d6.dialog.choices[1].id)
local d7 = Talk.choose(player, { crew = T.id, token = d6.dialog.token, choice = d6.dialog.choices[1].id })
print("tip forced:", d7.dialog and d7.dialog.text)
local bad = Talk.choose(player, { crew = T.id, token = d1.token, choice = "more" })
assert(bad.ok == false, "stale token refused")
local bad2 = Talk.choose(player, { crew = T.id, token = d7.dialog.token, choice = "paynow" })
assert(bad2.ok == false, "not-offered choice refused")
ppos = waiter.pos + Vector3.new(30, 3, 0)
local far = Talk.choose(player, { crew = T.id, token = d7.dialog.token, choice = "back" })
assert(far.close == true, "too far closes")
Talk.endSession(player)
ppos = rec.center + Vector3.new(0, 3, 0)
-- 5b. every offered choice of every rig, seated and standing, plus fake counter / venue staff
local function sweep(T, label)
	local okN, n = 0, 0
	local d0 = Talk.open(player, T, true)
	if not d0 then print("  no dialog", label) return end
	local function walkNode(dlg, depth)
		for _, ch in dlg.choices do
			-- a fresh session at this node for every choice
			local fresh = Talk.open(player, T, true)
			local nodeDlg = fresh
			if dlg ~= d0 and depth > 0 then
				nodeDlg = Talk.choose(player, { crew = T.id, token = fresh.token, choice = dlg.__via }).dialog or fresh
			end
			local r2 = Talk.choose(player, { crew = T.id, token = nodeDlg.token, choice = ch.id })
			n += 1
			if r2 and (r2.ok or r2.close) then okN += 1 else print("  FAIL", label, ch.id) end
			if depth == 0 and r2 and r2.dialog and (ch.id == "more" or ch.id == "complain" or ch.id == "tip" or ch.id == "buy" or ch.id == "refill" or ch.id == "dirs") then
				r2.dialog.__via = ch.id
				walkNode(r2.dialog, 1)
			end
			run(0.2)
		end
	end
	walkNode(d0, 0)
	Talk.endSession(player)
	print(string.format("  sweep %-22s %d/%d ok", label, okN, n))
end
for role, R2 in crew.rigs do
	ppos = R2.pos + Vector3.new(1, 3, 0)
	session.seat = { table = tb1.id, seat = tb1.seats[1].id }
	sweep(Director.resolve(R2.id), role .. " seated")
	session.seat = nil
	sweep(Director.resolve(R2.id), role .. " standing")
end
do
	local Personas = Shared.Personas
	local m = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = rec.center + Vector3.new(0, 3, 0)
	root.Parent = m
	local fakes = {}
	for _, spec in { { "cvs", nil }, { "game", "pc" }, { "pharmacy", nil }, { "hotel", "hotel" } } do
		local id = "aug_test_" .. spec[1]
		fakes[id] = { id = id, kind = "staff", root = root, persona = Personas.forStaff(spec[1], "점원", id), role = "cashier", shopName = "테스트 가게", aug = { menuKind = if spec[2] then spec[2] else spec[1], venue = spec[2], model = m } }
	end
	Talk.setResolver(function(id) return fakes[id] or Director.resolve(id) end)
	ppos = root.Position
	for id, T in fakes do
		sweep(T, id)
	end
	Talk.setResolver(Director.resolve)
end
ppos = rec.center + Vector3.new(0, 3, 0)

-- 6. diners for a while
run(90)
local st2 = Director.status()
print("diners live", st2.diners, "serve", st2.serve.tracked, st2.serve.guardServed, "events", #events)
local dinerOrders, dinerServed = 0, 0
for _, o in orders do
	if o.npc then
		dinerOrders += 1
		if o.phase == "served" then dinerServed += 1 end
	end
end
print("diner orders", dinerOrders, "served", dinerServed)
-- 7. no stuck orders
local stuck = 0
local maxWait = 0
for _, o in orders do
	if o.phase == "ready" and SIM.t - o.readyT > 19 then stuck += 1 end
	if o.phase == "ready" then maxWait = math.max(maxWait, SIM.t - o.readyT) end
end
print("stuck ready", stuck, "longest ready wait now", maxWait)
-- 8. stand-down
working = true
run(5)
print("after shift: crews", #Director.status().crews, "staffMode", staff)
assert(#Director.status().crews == 0 and staff == nil, "stood down, staffMode off")
working = false
print("SIM errors", SIM.errors, "crew errors", st2.errors.brain, st2.lastError)
for i = math.max(1, #events - 12), #events do print("  ", events[i]) end
print(if SIM.errors == 0 then "CREW OK" else "CREW ERRORS")
