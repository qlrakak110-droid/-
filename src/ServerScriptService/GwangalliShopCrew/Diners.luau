-- GwangalliShopCrew/Diners: NPC customers (손님) for crewed table shops, through ShopLife's NPC ops.
--   arrive (sidewalk -> auto door -> seat: claimSeat) -> the waiter takes the order at the table (npcOrder)
--   -> the kitchen cooks, the waiter serves (the same pipeline as players) -> eat (npcEat) -> npcLeave
--   -> pay at the counter (the cashier bows) -> out through the door.
-- Seat budget: parties only take whole EMPTY tables, at most Config.DINERS.maxShare of a shop's tables, always
-- leaving keepFree (+1 per 2 players inside) free; when a player walks in and free tables run low, the party
-- that is furthest along wraps up early. Never alcohol; ids start with "shop_diner_" (+ ShopCustomer = true).
--   Diners.init(Shared, Bridge, Net, mods)   mods = { Crew, Rig, Sites, Serve }
--   Diners.tick(crew)   Diners.onBus(crew, kind, d)   Diners.clear(crew)   Diners.count() -> live diners

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Diners = {}

local Shared: any = nil
local Config: any = nil
local Bridge: any = nil
local Crew: any = nil
local Rig: any = nil
local Sites: any = nil

local live = 0
local serial = 0

local STYLES = { "casual", "office", "street", "tourist", "hoodie", "trendy", "casual", "sporty" }
local AGES = { "young", "young", "adult", "adult", "middle", "senior" }

function Diners.init(S: any, B: any, N: any, mods: any)
	Shared, Config, Bridge = S, S.Config, B
	local _ = N
	Crew, Rig, Sites = mods.Crew, mods.Rig, mods.Sites
end

local function now(): number
	return os.clock()
end

local function rand(a: number, b: number): number
	return a + math.random() * (b - a)
end

local function cfg(): any
	return Config.DINERS
end

local function occupancy(shopType: string): number
	local c = Lighting.ClockTime % 24
	local D = cfg()
	if c >= 3 and c < 7 then
		return D.occLate
	end
	if (shopType == "pocha" or shopType == "grill" or shopType == "pub") and (c >= 19 or c < 2) then
		return D.occNight
	end
	if (c >= 11.5 and c < 13.5) or (c >= 18 and c < 20.5) then
		return D.occPeak
	end
	return D.occBase
end

local function state(crew: any): any
	local st = crew.dinerState
	if not st then
		st = { parties = {}, nextAt = now() + rand(6, 14) }
		crew.dinerState = st
	end
	return st
end

local function playersInside(crew: any): number
	local n = 0
	for _, p in Players:GetPlayers() do
		local pos = Bridge.posOf(p)
		if pos and Sites.inside(crew.site, pos, 1) then
			n += 1
		end
	end
	return n
end

local function partyTables(st: any): { [number]: boolean }
	local out = {}
	for _, party in st.parties do
		if party.table then
			out[party.table] = true
		end
	end
	return out
end

-- tables a party could take: empty, no dishes on them, reachable, not just cleared
local function emptyTables(crew: any): { any }
	local out = {}
	local st = state(crew)
	local taken = partyTables(st)
	for _, tb in crew.site.tables do
		local e = crew.site.spots.A[tb.id]
		if e and not taken[tb.id] and not Crew.occupied(crew, tb.id) and #tb.seats > 0 and tb.kind ~= "bar" and tb.kind ~= "counter" then
			if Bridge.tableDishCount(crew.key, tb.id) == 0 then
				table.insert(out, tb)
			end
		end
	end
	return out
end

local function pickItems(crew: any, n: number): { string }
	local SS = Bridge.SS
	local out = {}
	if not SS or not crew.site.menuKey then
		return out
	end
	local ok, menu = pcall(SS.menu, crew.site.menuKey)
	if not ok or type(menu) ~= "table" then
		return out
	end
	local mains, others = {}, {}
	for _, it in menu do
		if it.cat ~= "alcohol" and it.dish then
			if it.cat == "main" or it.cat == nil then
				table.insert(mains, it)
			elseif it.cat == "side" or it.cat == "drink" or it.cat == "dessert" then
				table.insert(others, it)
			end
		end
	end
	if #mains == 0 then
		mains = others
	end
	for _ = 1, n do
		if #mains > 0 then
			table.insert(out, mains[math.random(1, #mains)].id)
		end
	end
	return out
end

local function itemName(crew: any, id: string): string
	return Crew.itemName(crew, id)
end

-------------------------------------------------------------------------------------------------
-- a party's life (one coroutine)
-------------------------------------------------------------------------------------------------
local function dinerSay(crew: any, d: any, key: string, vars: any?)
	if d.R then
		local text = Shared.Lines.get(key, { dialect = d.dialect, type = crew.site.type, vars = vars })
		if text then
			Rig.say(d.R, text, 3, "plain")
		end
	end
end

local function partyAlive(crew: any, party: any): boolean
	return crew.alive and not party.gone
end

local function walkDiner(crew: any, d: any, to: Vector3, yaw: number?, viaDoor: string?): boolean
	if not Rig.alive(d.R) then
		return false
	end
	local from = Rig.feet(d.R)
	local pts = Sites.path(crew.site, from, to, crew.site.main)
	if not pts then
		pts = { from, to }
	end
	local secs = Rig.walk(d.R, pts, Config.WALK.diner)
	local door = crew.site.door
	if viaDoor and door then
		local dd = (Vector3.new(door.X, 0, door.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude / Config.WALK.diner
		if viaDoor == "in" then
			Rig.doorProxy(d.R, door, 0, dd + 1.6)
		else
			local fromEnd = (Vector3.new(door.X, 0, door.Z) - Vector3.new(to.X, 0, to.Z)).Magnitude / Config.WALK.diner
			Rig.doorProxy(d.R, door, math.max(0, secs - fromEnd - 1.6), secs + 0.6)
		end
	end
	local t1 = now() + secs
	while now() < t1 do
		task.wait(0.25)
		if not Rig.alive(d.R) then
			return false
		end
	end
	Rig.arrive(d.R, yaw)
	return true
end

local function despawnParty(crew: any, party: any)
	if party.gone then
		return
	end
	party.gone = true
	for _, d in party.members do
		if d.claimed then
			Bridge.req("npcLeave", { shop = crew.key, npc = d.npc })
			d.claimed = false
		end
		if d.R then
			Rig.destroy(d.R)
			d.R = nil
			live -= 1
		end
	end
	local st = state(crew)
	local i = table.find(st.parties, party)
	if i then
		table.remove(st.parties, i)
	end
end

local function leaveRun(crew: any, party: any)
	if party.leaving then
		return
	end
	party.leaving = true
	party.phase = "leaving"
	local sp = crew.site.spots
	-- dishes stay for the waiter to clear, seats are freed
	for _, d in party.members do
		if d.claimed then
			Bridge.req("npcLeave", { shop = crew.key, npc = d.npc })
			d.claimed = false
		end
	end
	local payAt = sp.K or sp.S or sp.Din
	for i, d in party.members do
		if Rig.alive(d.R) then
			local e = sp.A[party.table]
			local stand = (e and e.seats[d.seat]) or (e and e.best)
			if stand then
				Rig.place(d.R, stand.pos, stand.yaw)
			end
			Rig.act(d.R, "idle")
			if i == 1 then
				dinerSay(crew, d, "dinerBye")
			end
		end
	end
	task.wait(0.6)
	-- the first one pays at the counter, the rest wait by the door
	local payer = party.members[1]
	if payer and Rig.alive(payer.R) and payAt and partyAlive(crew, party) then
		local near = Sites.freeNear(crew.site, payAt.pos, 3, crew.site.main) or payAt.pos
		if walkDiner(crew, payer, near, nil, nil) then
			local cashier = Crew.cashierRig(crew)
			if cashier then
				Rig.face(payer.R, cashier.pos)
				Rig.emote(payer.R, "give")
				Rig.look(cashier, 0)
				Rig.face(cashier, Rig.feet(payer.R))
				Rig.emote(cashier, "bow")
				Crew.say(crew, cashier, "paid", nil, "happy", 2.6)
			end
			task.wait(1.4)
		end
	end
	local out = sp.Dout
	for i, d in party.members do
		if Rig.alive(d.R) and out and partyAlive(crew, party) then
			task.delay((i - 1) * 0.5, function()
				if Rig.alive(d.R) then
					walkDiner(crew, d, out.pos, nil, "out")
				end
			end)
		end
	end
	task.wait(1.0)
	-- out of sight: gone
	local t1 = now() + 14
	while now() < t1 and partyAlive(crew, party) do
		local walking = false
		for _, d in party.members do
			if d.R and d.R.walking then
				walking = true
			end
		end
		if not walking then
			break
		end
		task.wait(0.5)
	end
	despawnParty(crew, party)
end

local function orderNow(crew: any, party: any)
	if party.ordered then
		return
	end
	party.ordered = true
	party.phase = "ordered"
	local items = pickItems(crew, #party.members)
	for i, d in party.members do
		local id = items[i]
		if id and d.claimed then
			local r = Bridge.req("npcOrder", { shop = crew.key, npc = d.npc, items = { id } })
			if r.ok then
				d.item = id
				d.orderIds = r.orderIds or { r.orderId }
			end
		end
	end
	party.orderedAt = now()
end

-- the waiter's job: take a party's order at the table
local function dinerOrderRun(crew: any, R: any, job: any, tok: number)
	local party = job.party
	if not partyAlive(crew, party) or party.ordered then
		return
	end
	local e = crew.site.spots.A[party.table]
	if not e then
		orderNow(crew, party)
		return
	end
	if not Crew.walkTo(crew, R, tok, e.best, nil, "behind") then
		-- interrupted (a tray first): the party orders anyway, the kitchen starts
		if partyAlive(crew, party) and not party.ordered then
			task.delay(4, function()
				if partyAlive(crew, party) then
					orderNow(crew, party)
				end
			end)
		end
		return
	end
	Rig.face(R, e.best.face)
	Rig.act(R, "crew_note")
	Crew.say(crew, R, "callArrive", nil, "plain", 2.6)
	local items = pickItems(crew, 1)
	local first = party.members[1]
	if first and Rig.alive(first.R) then
		task.delay(1.2, function()
			if partyAlive(crew, party) then
				dinerSay(crew, first, "dinerOrder", { item = itemName(crew, items[1] or "") })
			end
		end)
	end
	if Crew.hold(crew, R, tok, 3.0) == "abort" then
		if partyAlive(crew, party) then
			orderNow(crew, party)
		end
		return
	end
	orderNow(crew, party)
	Rig.emote(R, "nod")
	local d1 = party.members[1]
	Crew.say(crew, R, if #party.members > 1 then "orderAckMany" else "orderAck", { item = itemName(crew, d1 and d1.item or ""), count = #party.members - 1 }, "happy", 2.4)
	if Crew.hold(crew, R, tok, 0.8) == "abort" then
		return
	end
	Crew.goHome(crew, R, tok)
end

local function dinerOrderJob(party: any): any
	return { kind = "dinerOrder", prio = 3, key = "diner" .. party.id, party = party, run = dinerOrderRun, preempt = true }
end

local function arriveRun(crew: any, party: any)
	local sp = crew.site.spots
	local tb = crew.site.tableById[party.table]
	-- walk in one by one
	for i, d in party.members do
		task.delay((i - 1) * 0.7, function()
			if not partyAlive(crew, party) or not Rig.alive(d.R) then
				return
			end
			local e = sp.A[party.table]
			local stand = (e and e.seats[d.seat]) or (e and e.best)
			if not stand then
				return
			end
			if walkDiner(crew, d, stand.pos, stand.yaw, "in") and partyAlive(crew, party) then
				local seat = nil
				for _, s in tb.seats do
					if s.id == d.seat then
						seat = s
					end
				end
				if seat then
					Rig.sit(d.R, seat.top, tb.center)
				end
				d.seated = true
			end
		end)
	end
	-- everyone sat down (or gave up)
	local t1 = now() + 25
	while now() < t1 and partyAlive(crew, party) do
		local all = true
		for _, d in party.members do
			if not d.seated then
				all = false
			end
		end
		if all then
			break
		end
		task.wait(0.4)
	end
	if not partyAlive(crew, party) then
		return
	end
	party.phase = "seated"
	party.seatedAt = now()
	task.wait(rand(2, 5))
	if not partyAlive(crew, party) then
		return
	end
	if Crew.waiter(crew) then
		Crew.enqueue(crew, "waiter", dinerOrderJob(party))
		-- nobody came within 25 s: they order at the counter's bell
		task.delay(25, function()
			if partyAlive(crew, party) and not party.ordered then
				orderNow(crew, party)
			end
		end)
	else
		orderNow(crew, party)
	end
	-- give up after a long wait for the food
	task.delay(150, function()
		if partyAlive(crew, party) and not party.leaving then
			task.spawn(leaveRun, crew, party)
		end
	end)
end

local function spawnParty(crew: any, tb: any, size: number): boolean
	local st = state(crew)
	local sp = crew.site.spots
	if not sp.Dout or not crew.site.doorLinked then
		return false
	end
	serial += 1
	local party: any = { id = serial, members = {}, table = tb.id, phase = "arriving", born = now() }
	-- seats first (ShopLife marks them taken so no player is put there)
	for i = 1, size do
		serial += 1
		local npc = Config.DINER_PREFIX .. tostring(serial)
		local r = Bridge.req("claimSeat", { shop = crew.key, npc = npc, table = tb.id })
		if not r.ok then
			break
		end
		table.insert(party.members, { npc = npc, seat = r.seat, claimed = true, dialect = if math.random() < 0.5 then "busan" else "std" })
		local _ = i
	end
	if #party.members == 0 then
		return false
	end
	local useAvatar = live < cfg().avatarCap
	for _, d in party.members do
		local R = Rig.build({
			id = d.npc,
			name = "Diner_" .. d.npc,
			role = "diner",
			shop = crew.key,
			kind = "diner",
			pos = sp.Dout.pos,
			yaw = sp.Dout.yaw,
			look = { style = STYLES[math.random(1, #STYLES)], age = AGES[math.random(1, #AGES)] },
			seed = d.npc .. crew.key,
			avatar = if useAvatar then nil else false,
			act = "idle",
		})
		if R then
			d.R = R
			live += 1
		end
	end
	local any = false
	for _, d in party.members do
		if d.R then
			any = true
		end
	end
	if not any then
		despawnParty(crew, party)
		return false
	end
	table.insert(st.parties, party)
	task.spawn(function()
		local ok, err = pcall(arriveRun, crew, party)
		if not ok then
			Bridge.warnOnce("diner", "diner party: " .. tostring(err))
			despawnParty(crew, party)
		end
	end)
	return true
end

-------------------------------------------------------------------------------------------------
-- director hooks
-------------------------------------------------------------------------------------------------
function Diners.tick(crew: any)
	local D = cfg()
	if not D.enabled or not crew.alive or crew.site.flow ~= "table" or not Crew.waiter(crew) then
		return
	end
	local st = state(crew)
	local t = now()
	if t < st.nextAt then
		return
	end
	st.nextAt = t + rand(D.gap[1], D.gap[2])
	if live >= D.max then
		return
	end
	local mine = 0
	for _, party in st.parties do
		mine += #party.members
	end
	if mine >= D.perShop then
		return
	end
	local nTables = 0
	for _, tb in crew.site.tables do
		if tb.kind ~= "bar" and tb.kind ~= "counter" and crew.site.spots.A[tb.id] then
			nTables += 1
		end
	end
	local target = math.floor(nTables * math.min(occupancy(crew.site.type), D.maxShare) + 0.5)
	local free = emptyTables(crew)
	local keep = D.keepFree + math.ceil(playersInside(crew) / 2)
	if #st.parties >= target or #free <= keep then
		return
	end
	local tb = free[math.random(1, #free)]
	local size = math.clamp(math.random(1, 3), 1, math.min(#tb.seats, D.perShop - mine))
	spawnParty(crew, tb, size)
end

function Diners.onBus(crew: any, kind: string, d: any)
	local st = crew.dinerState
	if not st then
		return
	end
	if kind == "served" and d.npc then
		for _, party in st.parties do
			for _, m in party.members do
				if m.npc == d.npc and not m.served then
					m.served = true
					if Rig.alive(m.R) then
						Rig.act(m.R, "crew_sit_eat")
						if math.random() < 0.6 then
							dinerSay(crew, m, "dinerServed")
						end
					end
					-- the whole party has its food: eat, then go
					local all = true
					for _, m2 in party.members do
						if m2.orderIds and not m2.served then
							all = false
						end
					end
					if all and not party.eating then
						party.eating = true
						party.phase = "eating"
						local secs = rand(Config.DINERS.eat[1], Config.DINERS.eat[2])
						party.eatUntil = now() + secs
						for _, m2 in party.members do
							if m2.claimed then
								Bridge.req("npcEat", { shop = crew.key, npc = m2.npc, seconds = secs })
							end
						end
						task.delay(secs * 0.5, function()
							if partyAlive(crew, party) and #party.members > 1 and math.random() < 0.7 then
								dinerSay(crew, party.members[math.random(1, #party.members)], "dinerChat")
							end
						end)
						task.delay(secs + 2, function()
							if partyAlive(crew, party) then
								task.spawn(leaveRun, crew, party)
							end
						end)
					end
				end
			end
		end
	elseif kind == "enter" and d.userId then
		-- a player walked in: make room when free tables run low
		local free = emptyTables(crew)
		local keep = Config.DINERS.keepFree + math.ceil(playersInside(crew) / 2)
		if #free < keep then
			local best, bestT = nil, math.huge
			for _, party in st.parties do
				if party.eating and not party.leaving and (party.eatUntil or math.huge) < bestT then
					best, bestT = party, party.eatUntil
				end
			end
			if best then
				for _, m in best.members do
					if m.claimed then
						Bridge.req("npcEat", { shop = crew.key, npc = m.npc, seconds = 3 })
					end
				end
				task.delay(4, function()
					if partyAlive(crew, best) then
						task.spawn(leaveRun, crew, best)
					end
				end)
			end
		end
	end
end

function Diners.clear(crew: any)
	local st = crew.dinerState
	if not st then
		return
	end
	local list = table.clone(st.parties)
	for _, party in list do
		despawnParty(crew, party)
	end
end

function Diners.count(): number
	return live
end

return Diners
