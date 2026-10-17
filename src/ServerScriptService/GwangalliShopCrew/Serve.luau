-- GwangalliShopCrew/Serve: order tracking (orderId <-> table / seat / owner), the players' order tickets and the
-- SERVE GUARD that makes sure no order ever gets stuck because a waiter exists.
--   While a shop runs in ShopLife staffMode { serve = true }, ShopLife cooks but leaves table orders "ready" for
--   staff to bring (and silently drops them after 240 s). So:
--     * any tracked ready table order older than Config.SERVE_TIMEOUT is served directly (Bus "serve")
--     * Serve.flush(key) serves every ready table order of a shop (called right after staffMode goes off)
--     * crewed shops are polled ("queue") every Config.QUEUE_POLL s: ready orders we missed are adopted
--   Serve.init(Shared, Bridge, Net)
--   Serve.onOrder(d) / onCooking(d) / onReady(d) -> order? / onServed(d) / onPickup(d)
--   Serve.readyFor(key) -> { order }   Serve.claim(order, by) / release(order)   Serve.serveNow(order, why)
--   Serve.flush(key)   Serve.poll(key) -> { newly adopted ready orders }   Serve.guard(isCrewed(key) -> bool)
--   Serve.byId(id)   Serve.playerOrders(uid, key) -> { order }
-- order = { id, shop, item, name, qty, table?, seat?, owner? (UserId), npc?, dest, phase, number?, placedAt,
--           cookUntil?, readyAt?, served, claimed? (role), carriedAt? }

local Serve = {}

local Config: any = nil
local Bridge: any = nil
local Net: any = nil

local orders: { [string]: any } = {}
local lastPoll: { [string]: number } = {}
local ticketDirty: { [string]: boolean } = {} -- "<uid>|<shop>"
local stats = { tracked = 0, guardServed = 0, flushed = 0, adopted = 0 }

function Serve.init(S: any, B: any, N: any)
	Config, Bridge, Net = S.Config, B, N
end

local function now(): number
	return os.clock()
end

local function itemOf(menuKey: string?, id: any): any?
	local SS = Bridge.SS
	if SS and type(SS.item) == "function" and menuKey then
		local ok, it = pcall(SS.item, menuKey, id)
		if ok then
			return it
		end
	end
	return nil
end

local function markTicket(o: any)
	if o.owner then
		ticketDirty[tostring(o.owner) .. "|" .. o.shop] = true
	end
end

local function track(key: string, q: any, owner: number?, npc: string?, menuKey: string?): any
	local o = orders[q.orderId]
	if o then
		return o
	end
	local it = itemOf(menuKey, q.item)
	o = {
		id = q.orderId,
		shop = key,
		item = q.item,
		name = q.name or (it and it.name) or tostring(q.item),
		icon = it and it.icon,
		dish = it and it.dish,
		fx = it and it.fx,
		menu = menuKey,
		qty = tonumber(q.qty) or 1,
		table = q.table,
		seat = q.seat,
		owner = owner,
		npc = npc,
		dest = q.dest or (if q.table then "table" else "pickup"),
		phase = q.phase or "placed",
		number = q.number,
		placedAt = now(),
		served = false,
	}
	if o.phase == "ready" then
		o.readyAt = now()
	end
	orders[o.id] = o
	stats.tracked += 1
	markTicket(o)
	return o
end

local function queueOf(key: string): { any }
	local r = Bridge.req("queue", { shop = key })
	return if r.ok and type(r.orders) == "table" then r.orders else {}
end

-------------------------------------------------------------------------------------------------
-- bus events
-------------------------------------------------------------------------------------------------
-- a player's order event has no orderId: the shop queue tells which new orders belong to that table
function Serve.onOrder(d: any, menuKey: string?): { any }
	local key = d.shop
	local out = {}
	if type(key) ~= "string" then
		return out
	end
	if d.npc and d.orderId then
		local ln = (type(d.items) == "table" and d.items[1]) or {}
		local o = track(key, { orderId = d.orderId, item = ln.id, name = ln.name, qty = ln.qty, table = d.table, seat = d.seat, dest = "table", phase = "placed" }, nil, tostring(d.npc), menuKey)
		table.insert(out, o)
		return out
	end
	local uid = tonumber(d.forUserId) or tonumber(d.userId)
	for _, q in queueOf(key) do
		if not orders[q.orderId] and (q.phase == "placed" or q.phase == "cooking" or q.phase == "ready") then
			-- the new ones: same table (table orders) or no table (pickup orders of this player)
			local mine = (d.table ~= nil and q.table == d.table) or (d.table == nil and q.dest ~= "table")
			if mine then
				local o = track(key, q, uid, nil, menuKey)
				table.insert(out, o)
			end
		end
	end
	return out
end

function Serve.onCooking(d: any): any?
	local o = orders[tostring(d.orderId)]
	if o then
		o.phase = "cooking"
		o.cookUntil = now() + (tonumber(d.seconds) or 8)
		markTicket(o)
	end
	return o
end

function Serve.onReady(d: any, menuKey: string?): any?
	local id = tostring(d.orderId)
	local o = orders[id]
	if not o and type(d.shop) == "string" then
		for _, q in queueOf(d.shop) do
			if q.orderId == id then
				o = track(d.shop, q, nil, nil, menuKey)
				stats.adopted += 1
			end
		end
	end
	if o then
		o.phase = "ready"
		o.readyAt = o.readyAt or now()
		o.dest = d.where or o.dest
		markTicket(o)
	end
	return o
end

function Serve.onServed(d: any): any?
	local o = orders[tostring(d.orderId)]
	if o then
		o.phase = "served"
		o.served = true
		o.servedAt = now()
		o.claimed = nil
		markTicket(o)
	end
	return o
end

function Serve.onPickup(d: any)
	local o = orders[tostring(d.orderId)]
	if o then
		o.phase = "picked"
		o.served = true
		o.servedAt = now()
		markTicket(o)
	end
end

-------------------------------------------------------------------------------------------------
-- waiter side
-------------------------------------------------------------------------------------------------
function Serve.byId(id: string): any?
	return orders[id]
end

-- ready table orders of a shop that nobody carries yet (oldest first)
function Serve.readyFor(key: string): { any }
	local out = {}
	for _, o in orders do
		if o.shop == key and o.phase == "ready" and o.dest == "table" and not o.served and not o.claimed then
			table.insert(out, o)
		end
	end
	table.sort(out, function(a, b)
		return (a.readyAt or 0) < (b.readyAt or 0)
	end)
	return out
end

function Serve.claim(o: any, by: string)
	o.claimed = by
	o.carriedAt = now()
	markTicket(o)
end

function Serve.release(o: any)
	o.claimed = nil
end

function Serve.serveNow(o: any, why: string?): boolean
	if o.served or o.phase ~= "ready" then
		return false
	end
	local r = Bridge.req("serve", { orderId = o.id })
	if r.ok then
		o.served = true
		o.phase = "served"
		o.servedAt = now()
		o.claimed = nil
		if why == "guard" then
			stats.guardServed += 1
		end
		markTicket(o)
		return true
	end
	-- not ready any more (served by someone else / gone): stop tracking it as ready
	if r.code == "bad_phase" then
		o.served = true
		o.phase = "served"
		o.servedAt = now()
		markTicket(o)
	end
	return false
end

-- every ready table order of the shop, straight onto the tables (staffMode went off / the crew left)
function Serve.flush(key: string): number
	local n = 0
	for _, q in queueOf(key) do
		if q.phase == "ready" and q.dest == "table" then
			local r = Bridge.req("serve", { orderId = q.orderId })
			if r.ok then
				n += 1
			end
			local o = orders[q.orderId]
			if o then
				o.served = true
				o.phase = "served"
				o.servedAt = now()
				o.claimed = nil
				markTicket(o)
			end
		end
	end
	stats.flushed += n
	return n
end

-- ready table orders the bus events did not tell us about (adopted)
function Serve.poll(key: string, menuKey: string?): { any }
	local out = {}
	local t = now()
	if lastPoll[key] and t - lastPoll[key] < Config.QUEUE_POLL then
		return out
	end
	lastPoll[key] = t
	local seen = {}
	for _, q in queueOf(key) do
		seen[q.orderId] = true
		local o = orders[q.orderId]
		if not o then
			o = track(key, q, nil, nil, menuKey)
			stats.adopted += 1
			if q.phase == "ready" and q.dest == "table" then
				table.insert(out, o)
			end
		elseif o.phase ~= q.phase and not o.served then
			o.phase = q.phase
			if q.phase == "ready" then
				o.readyAt = o.readyAt or t
				table.insert(out, o)
			end
			markTicket(o)
		end
	end
	-- orders ShopLife let go of (served / picked / purged)
	for id, o in orders do
		if o.shop == key and not seen[id] and not o.served then
			o.served = true
			o.phase = if o.dest == "table" then "served" else "picked"
			o.servedAt = t
			markTicket(o)
		end
	end
	return out
end

-- 1 Hz, independent of the crews: nothing waits longer than SERVE_TIMEOUT for a waiter. Only shops we put in
-- staffMode are touched (elsewhere ShopLife serves by itself); ours(key) -> (owned, waiterUp)
function Serve.guard(ours: (string) -> (boolean, boolean))
	local t = now()
	for id, o in orders do
		if o.phase == "ready" and o.dest == "table" and not o.served then
			local owned, up = ours(o.shop)
			local age = t - (o.readyAt or t)
			if owned and (age > Config.SERVE_TIMEOUT or (not up and age > 1)) then
				Serve.serveNow(o, "guard")
			end
		end
		-- forget old ones
		if o.served and o.servedAt and t - o.servedAt > 90 then
			orders[id] = nil
		elseif t - o.placedAt > 900 then
			orders[id] = nil
		end
	end
end

-------------------------------------------------------------------------------------------------
-- tickets (주문서) for players
-------------------------------------------------------------------------------------------------
function Serve.playerOrders(uid: number, key: string?): { any }
	local out = {}
	for _, o in orders do
		if o.owner == uid and (key == nil or o.shop == key) then
			table.insert(out, o)
		end
	end
	table.sort(out, function(a, b)
		return a.placedAt < b.placedAt
	end)
	return out
end

local PHASE_KR = { placed = "주문 접수", cooking = "조리 중", ready = "준비 완료", served = "서빙 완료", picked = "픽업 완료" }

-- send changed tickets (called by the director ~4 Hz)
function Serve.flushTickets(shopName: (string) -> string)
	for k in ticketDirty do
		ticketDirty[k] = nil
		local uidS, key = string.match(k, "^(%d+)|(.+)$")
		local p = uidS and Bridge.playerById(tonumber(uidS))
		if p and key then
			local list = Serve.playerOrders(p.UserId, key)
			local items = {}
			local open = 0
			local tableId, number = nil, nil
			local t = now()
			for _, o in list do
				local phase = o.phase
				if o.claimed and phase == "ready" then
					phase = "carrying"
				end
				if not o.served then
					open += 1
				end
				-- finished lines stay on the ticket for a little while
				if not o.served or (o.servedAt and t - o.servedAt < 8) then
					table.insert(items, {
						name = o.name,
						icon = o.icon,
						qty = o.qty,
						phase = phase,
						label = if phase == "carrying" then "가져가는 중" else (PHASE_KR[phase] or phase),
						left = if o.cookUntil and phase == "cooking" then math.max(0, math.floor(o.cookUntil - t)) else nil,
						dest = o.dest,
					})
				end
				tableId = tableId or o.table
				number = number or o.number
			end
			Net.fire(p, "ticket", { shop = key, shopName = shopName(key), table = tableId, number = number, items = items, open = open })
		end
	end
end

function Serve.stats(): any
	local n = 0
	for _ in orders do
		n += 1
	end
	return { live = n, tracked = stats.tracked, guardServed = stats.guardServed, flushed = stats.flushed, adopted = stats.adopted }
end

return Serve
