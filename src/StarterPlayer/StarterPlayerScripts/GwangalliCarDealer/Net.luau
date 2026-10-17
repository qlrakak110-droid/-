-- GwangalliCarDealer/Net (client): the dealer remotes (Request / Event), the garage's GarageEvent, and the
-- catalog state every screen reads:
--   Net.call(op, payload?) -> result (never errors; { ok = false, code = "net" } on timeouts)
--   Net.on(k, fn)                         our Event (k = "test" | "toast" | "state")
--   Net.onGarage(kind, fn)                GwangalliRemotes.GarageEvent (kind = "testdrive" | "cars" ...)
--   Net.refresh() -> ok                   fetch the catalog snapshot and rebuild the entries
--   Net.state = { snap, entries, byId, wish = { [id] = true }, loaded }
--   Net.money() -> bank, cash             live from the Bank / Money player attributes (snapshot fallback)
--   Net.onChanged(fn)                     after every refresh / wish change

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Net = {}

local player = Players.LocalPlayer
local ctx: any
local request: RemoteFunction? = nil
local event: RemoteEvent? = nil
local handlers: { [string]: { (any) -> () } } = {}
local garageHandlers: { [string]: { (any) -> () } } = {}
local changed: { () -> () } = {}

Net.state = { snap = nil, entries = {}, byId = {}, wish = {}, loaded = false, at = 0 }

local function dispatch(map: { [string]: { (any) -> () } }, key: any, payload: any)
	local list = type(key) == "string" and map[key]
	if list then
		for _, fn in list do
			task.spawn(fn, payload)
		end
	end
end

function Net.init(c: any)
	ctx = c
	local N = c.S.NAMES
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(N.Remotes, 120)
		if not folder then
			warn("[GwangalliCarDealer] remotes not found (is the server script installed?)")
			return
		end
		local rf = folder:WaitForChild(N.Request, 10)
		local re = folder:WaitForChild(N.Event, 10)
		if rf and rf:IsA("RemoteFunction") then
			request = rf
		end
		if re and re:IsA("RemoteEvent") then
			event = re
			re.OnClientEvent:Connect(function(payload: any)
				if type(payload) == "table" then
					dispatch(handlers, payload.k, payload)
				end
			end)
		end
	end)
	task.spawn(function()
		local g = ReplicatedStorage:WaitForChild(N.Garage.Remotes, 120)
		local ge = g and g:WaitForChild(N.Garage.Event, 30)
		if ge and ge:IsA("RemoteEvent") then
			ge.OnClientEvent:Connect(function(payload: any)
				if type(payload) == "table" then
					dispatch(garageHandlers, payload.kind, payload)
				end
			end)
		end
	end)
end

function Net.ready(): boolean
	return request ~= nil
end

function Net.call(op: string, payload: { [string]: any }?): { [string]: any }
	local t0 = os.clock()
	while not request and os.clock() - t0 < 8 do
		task.wait(0.1)
	end
	local rf = request
	if not rf then
		return { ok = false, code = "net", message = "딜러 서버에 연결하지 못했어요" }
	end
	local done, res = false, nil
	task.spawn(function()
		local ok, r = pcall(rf.InvokeServer, rf, op, payload)
		res = if ok then r else nil
		done = true
	end)
	while not done and os.clock() - t0 < 20 do
		task.wait()
	end
	if not done then
		return { ok = false, code = "net", message = "응답이 늦어요 · 잠시 후 다시 시도해 주세요" }
	end
	if type(res) ~= "table" then
		return { ok = false, code = "net", message = "연결이 불안정해요 · 잠시 후 다시 시도해 주세요" }
	end
	return res
end

function Net.nonce(): string
	local ok, g = pcall(HttpService.GenerateGUID, HttpService, false)
	local s = if ok and type(g) == "string" then string.gsub(g, "[^%w]", "") else tostring(math.random(1, 2 ^ 30)) .. tostring(os.clock())
	return string.sub(s, 1, 24)
end

function Net.on(k: string, fn: (any) -> ())
	handlers[k] = handlers[k] or {}
	table.insert(handlers[k], fn)
end

function Net.onGarage(kind: string, fn: (any) -> ())
	garageHandlers[kind] = garageHandlers[kind] or {}
	table.insert(garageHandlers[kind], fn)
end

function Net.onChanged(fn: () -> ())
	table.insert(changed, fn)
end

function Net.notify()
	for _, fn in changed do
		task.spawn(fn)
	end
end

local function set(list: any): { [string]: boolean }
	local s = {}
	if type(list) == "table" then
		for _, v in list do
			if type(v) == "string" then
				s[v] = true
			end
		end
	end
	return s
end

-- Marks owned / tested / wished / locked on the entries from the snapshot.
local function decorate(snap: any)
	local st = Net.state
	local cars = if type(snap.cars) == "table" then snap.cars else {}
	local gates = snap.gates or {}
	for _, e in st.entries do
		local owned = false
		if e.grade == "rent" then
			owned = snap.rentActive == true
		else
			for _, c in cars do
				if type(c) == "table" and not c.rental then
					if e.model then
						owned = owned or c.model == e.model
					elseif c.model == nil and c.kind == e.kind and c.grade == e.grade then
						owned = true
					end
				end
			end
		end
		e.owned = owned
		e.tested = if type(snap.tested) == "table" then snap.tested[e.id] else nil
		e.best = if type(snap.best) == "table" then snap.best[e.id] else nil
		e.lock = nil
		if gates.enforce then
			if e.kind == "luxury" and e.grade == "new" and not e.model and gates.hasLuxury == false then
				e.lock = { level = gates.luxuryLevel or 18, why = string.format("레벨 %d부터 출고", gates.luxuryLevel or 18) }
			end
		end
	end
end

function Net.refresh(): boolean
	local snap = Net.call("catalog", nil)
	if not snap.ok then
		return false
	end
	local GS = ctx.GS
	if not GS then
		GS = ctx.S.GS(5)
		ctx.GS = GS
	end
	local list, byId = ctx.S.Catalog.build(GS, ctx.VS, { avail = set(snap.avail), showAll = snap.showAll == true, specials = set(snap.specials), rent = true })
	local st = Net.state
	st.snap = snap
	st.entries = list
	st.byId = byId
	st.wish = set(snap.wish)
	st.loaded = true
	st.at = os.clock()
	decorate(snap)
	Net.notify()
	return true
end

function Net.setWish(list: any)
	Net.state.wish = set(list)
	Net.notify()
end

function Net.money(): (number, number)
	local b = player:GetAttribute("Bank")
	local m = player:GetAttribute("Money")
	local snap = Net.state.snap
	local bank = if type(b) == "number" then b elseif snap then snap.bank or 0 else 0
	local cash = if type(m) == "number" then m elseif snap then snap.cash or 0 else 0
	return bank, cash
end

function Net.usedRate(): number
	local snap = Net.state.snap
	return snap and tonumber(snap.usedRate) or 0
end

-- The owned (non-rental) cars of the snapshot (carViews).
function Net.ownedCars(): { any }
	local out = {}
	local snap = Net.state.snap
	for _, c in (snap and snap.cars) or {} do
		if type(c) == "table" and not c.rental then
			table.insert(out, c)
		end
	end
	return out
end

return Net
