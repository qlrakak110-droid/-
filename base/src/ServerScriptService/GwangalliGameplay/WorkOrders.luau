--!nocheck
-- GwangalliGameplay/WorkOrders: the ORDER REGISTRY of the 알바 work simulation and the interface the NPC
-- session plugs its customers into (docs/WORK_SIM.md "NPC 연결"). This module never moves an NPC.
--
-- Order:  { id = "C-0012", store, customerId, source = "npc" | "test", name, items = { item... },
--           state = received | preparing | ready | delivered | closed | cancelled,
--           confirmed (POS 확인), createdAt, confirmedAt, readyAt, deliveredAt, patience, target,
--           remakes, changed, group, result? }
-- Item:   { spec = { menu, temp, size, extraShot } (cafe) | ..., itemId = <made item at pickup>?,
--           accuracy?, exact?, done }
-- One customer has at most ONE open order per store (placeOrder twice returns the same order);
-- an order id is never reused; every transition goes through WS.canMove.
--
-- NPC SESSION API (server scripts: require(ServerScriptService.GwangalliGameplay.WorkOrders)):
--   WorkOrders.registerProvider(storeId, provider) -> unregister()
--       provider = { name = "npc-session",
--                    onCall(order)        -- 픽업대 호출: walk the customer to the pick-up point
--                    onResult(result)     -- 결과: show 감사 / 보통 / 불평 / 퇴점 (see result below)
--                    onCancelled(order, reason) }
--       While a provider is registered the store spawns NO test customers.
--   WorkOrders.placeOrder(storeId, customerId, items?, info?) -> order?, err?
--       items = nil: the menu is chosen for the worker's skill level. info = { name?, patience?, group? }
--   WorkOrders.cancel(orderId, reason)           -- the customer gave up / left
--   WorkOrders.receive(orderId) -> result?       -- the customer took the order at the pick-up point
--   WorkOrders.byCustomer(storeId, customerId) -> order?
--   result = { orderId, customerId, storeId, accuracy (0..1), satisfaction (0..100),
--              reaction = "thanks" | "ok" | "complain" | "angry" | "left", waited (s), remake (bool) }
--   The same is fired on the BindableEvent ServerStorage.GwangalliWorkEvents ("result", result) /
--   ("call", order) / ("cancelled", order, reason) for code that prefers events.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local WorkOrders = {}

local C: any
local WS: any
local hooks: any = {} -- set by Work: { onChanged(storeId), onResolved(order, result), levelFor(storeId) }

local orders: { [string]: any } = {} -- id -> order
local byStore: { [string]: { any } } = {} -- storeId -> list of orders (open + recent)
local providers: { [string]: any } = {}
local serial = 0
local events: BindableEvent? = nil

local function fire(kind: string, ...: any)
	if events then
		events:Fire(kind, ...)
	end
end

function WorkOrders.init(cfg: any, ws: any, h: any)
	C = cfg
	WS = ws
	hooks = h or {}
	local e = ServerStorage:FindFirstChild("GwangalliWorkEvents")
	if not e then
		e = Instance.new("BindableEvent")
		e.Name = "GwangalliWorkEvents"
		e.Parent = ServerStorage
	end
	events = e :: BindableEvent
end

local function changed(storeId: string)
	if hooks.onChanged then
		pcall(hooks.onChanged, storeId)
	end
end

local function storeList(storeId: string): { any }
	local l = byStore[storeId]
	if not l then
		l = {}
		byStore[storeId] = l
	end
	return l
end

-------------------------------------------------------------------------------------------------
-- Providers (the NPC session)
-------------------------------------------------------------------------------------------------
function WorkOrders.registerProvider(storeId: string, provider: any): () -> ()
	providers[storeId] = provider
	return function()
		if providers[storeId] == provider then
			providers[storeId] = nil
		end
	end
end

function WorkOrders.hasProvider(storeId: string): boolean
	return providers[storeId] ~= nil
end

local function provider(storeId: string, fn: string, ...: any)
	local p = providers[storeId]
	if p and type(p[fn]) == "function" then
		local ok, err = pcall(p[fn], ...)
		if not ok then
			warn("[GwangalliWork] provider " .. fn .. " failed: " .. tostring(err))
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Queries
-------------------------------------------------------------------------------------------------
function WorkOrders.get(id: any): any?
	return if type(id) == "string" then orders[id] else nil
end

function WorkOrders.open(storeId: string): { any }
	local out = {}
	for _, o in storeList(storeId) do
		if WS.isOpen(o.state) then
			table.insert(out, o)
		end
	end
	return out
end

function WorkOrders.byCustomer(storeId: string, customerId: any): any?
	for _, o in storeList(storeId) do
		if o.customerId == customerId and WS.isOpen(o.state) then
			return o
		end
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- Create / move
-------------------------------------------------------------------------------------------------
local function move(o: any, to: string): boolean
	if o.state == to then
		return true
	end
	if not WS.canMove(o.state, to) then
		warn(string.format("[GwangalliWork] order %s: %s -> %s refused", o.id, o.state, to))
		return false
	end
	o.state = to
	o.stateAt = os.clock()
	return true
end
WorkOrders.move = move

-- items: list of specs (validated by `validate`), or nil to generate `count` items with `gen`
function WorkOrders.create(storeId: string, customerId: any, specs: { any }, info: any?): (any?, string?)
	if customerId == nil then
		return nil, "customerId required"
	end
	local existing = WorkOrders.byCustomer(storeId, customerId)
	if existing then
		return existing, nil
	end
	if #specs == 0 then
		return nil, "empty order"
	end
	serial += 1
	local prefix = string.upper(string.sub(storeId, 1, 1))
	local o = {
		id = string.format("%s-%04d", prefix, serial),
		number = (serial - 1) % 99 + 1,
		store = storeId,
		customerId = customerId,
		source = if info and info.source == "test" then "test" else "npc",
		name = info and info.name or nil,
		items = {},
		state = "received",
		stateAt = os.clock(),
		confirmed = info and info.confirmed == true or false,
		createdAt = os.clock(),
		confirmedAt = nil,
		readyAt = nil,
		deliveredAt = nil,
		patience = info and tonumber(info.patience) or 90,
		target = info and tonumber(info.target) or 40,
		remakes = 0,
		changed = false,
		group = #specs >= 3,
		kind = info and info.kind or "cafe",
		meta = info and info.meta or nil,
	}
	for _, spec in specs do
		table.insert(o.items, { spec = spec, itemId = nil, done = false })
	end
	orders[o.id] = o
	table.insert(storeList(storeId), o)
	-- keep the list short: drop finished orders older than 2 minutes
	local l = storeList(storeId)
	for i = #l, 1, -1 do
		local x = l[i]
		if not WS.isOpen(x.state) and os.clock() - (x.stateAt or 0) > 120 then
			table.remove(l, i)
			orders[x.id] = nil
		end
	end
	changed(storeId)
	return o, nil
end

-- NPC session entry point (the menu is generated when items is nil)
function WorkOrders.placeOrder(storeId: string, customerId: any, items: { any }?, info: any?): (any?, string?)
	if hooks.placeOrder then
		return hooks.placeOrder(storeId, customerId, items, info)
	end
	return nil, "store not running"
end

function WorkOrders.confirm(o: any): boolean
	if o.confirmed or not WS.isOpen(o.state) then
		return false
	end
	o.confirmed = true
	o.confirmedAt = os.clock()
	changed(o.store)
	return true
end

function WorkOrders.cancel(orderId: any, reason: string?): boolean
	local o = WorkOrders.get(orderId)
	if not o or not WS.isOpen(o.state) then
		return false
	end
	move(o, "cancelled")
	o.cancelReason = reason or "cancelled"
	local result = { orderId = o.id, customerId = o.customerId, storeId = o.store, accuracy = 0, satisfaction = 0, reaction = "left", waited = os.clock() - o.createdAt, remake = false }
	o.result = result
	if hooks.onResolved then
		pcall(hooks.onResolved, o, result)
	end
	provider(o.store, "onCancelled", o, reason)
	fire("cancelled", o, reason)
	changed(o.store)
	return true
end

-- every item of the order sits at the pick-up point -> 완성 + call the customer
function WorkOrders.call(o: any): boolean
	for _, it in o.items do
		if not it.itemId then
			return false
		end
	end
	if o.state == "received" then
		move(o, "preparing")
	end
	if not move(o, "ready") then
		return false
	end
	o.readyAt = os.clock()
	provider(o.store, "onCall", o)
	fire("call", o)
	changed(o.store)
	return true
end

-- the customer took the order. judge(o) -> per-item { accuracy, exact } is supplied by the store kind.
function WorkOrders.receive(orderId: any): any?
	local o = WorkOrders.get(orderId)
	if not o or o.state ~= "ready" then
		return nil
	end
	if hooks.judge then
		local ok, err = pcall(hooks.judge, o)
		if not ok then
			warn("[GwangalliWork] judge failed: " .. tostring(err))
		end
	end
	move(o, "delivered")
	o.deliveredAt = os.clock()
	local acc, n, worst = 0, 0, 1
	for _, it in o.items do
		n += 1
		acc += it.accuracy or 0
		worst = math.min(worst, it.accuracy or 0)
	end
	acc = if n > 0 then acc / n else 0
	-- each remake already cost the customer time and patience
	acc = math.max(0, acc - 0.15 * o.remakes)
	local waited = o.deliveredAt - o.createdAt
	local sat, reaction = WS.satisfaction(acc, waited, o.target, o.patience)
	-- a clearly wrong drink comes back for a remake (once); the order goes back to 준비 중
	local remake = worst < 0.5 and o.remakes < 1
	local result = { orderId = o.id, customerId = o.customerId, storeId = o.store, accuracy = acc, satisfaction = sat, reaction = if remake then "complain" else reaction, waited = waited, remake = remake }
	o.result = result
	if remake then
		o.remakes += 1
		for _, it in o.items do
			if (it.accuracy or 0) < 0.5 then
				it.itemId = nil
				it.done = false
				it.accuracy = nil
				it.exact = nil
			end
		end
		move(o, "preparing")
	else
		move(o, "closed")
	end
	if hooks.onResolved then
		pcall(hooks.onResolved, o, result)
	end
	provider(o.store, "onResult", result)
	fire("result", result)
	changed(o.store)
	return result
end

-- the customer asks for something else while the order is being made (주문 변경 event)
function WorkOrders.change(o: any, index: number, spec: any, why: string?): boolean
	local it = o.items[index]
	if not it or it.itemId or not WS.isOpen(o.state) or o.state == "ready" then
		return false
	end
	it.prev = it.spec
	it.spec = spec
	it.changedAt = os.clock()
	o.changed = true
	o.changeText = why
	changed(o.store)
	return true
end

-- patience: the customer gives up
function WorkOrders.tick(storeId: string, now: number)
	for _, o in WorkOrders.open(storeId) do
		if o.state ~= "ready" and now - o.createdAt > o.patience then
			WorkOrders.cancel(o.id, "waited too long")
		elseif o.state == "ready" and now - (o.readyAt or now) > 45 then
			-- called but nobody came (NPC lost): close it as delivered on the counter
			WorkOrders.receive(o.id)
		end
	end
end

-- the store closed / everyone clocked out: open orders are cancelled (no pay for them)
function WorkOrders.closeStore(storeId: string, reason: string)
	for _, o in WorkOrders.open(storeId) do
		WorkOrders.cancel(o.id, reason)
	end
end

-- view for the client tickets
function WorkOrders.view(o: any, now: number): any
	local items = {}
	for i, it in o.items do
		items[i] = { spec = it.spec, text = if WS.specText and o.kind == "cafe" then WS.specText(it.spec) else it.text, placed = it.itemId ~= nil, prev = if it.prev and WS.specText and o.kind == "cafe" then WS.specText(it.prev) else nil, label = it.label }
	end
	return {
		id = o.id,
		number = o.number,
		state = o.state,
		confirmed = o.confirmed,
		source = o.source,
		name = o.name,
		items = items,
		waited = math.floor(now - o.createdAt),
		patience = o.patience,
		left = math.max(0, math.floor(o.patience - (now - o.createdAt))),
		group = o.group,
		changed = o.changed,
		changeText = o.changeText,
		remakes = o.remakes,
		kind = o.kind,
		meta = o.meta,
	}
end

WorkOrders.all = orders
return WorkOrders
