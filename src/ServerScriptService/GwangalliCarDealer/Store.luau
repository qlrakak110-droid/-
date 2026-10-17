-- GwangalliCarDealer/Store (server): the dealer's own small memory per player, DataStore
-- "GwangalliCarDealer_v1" key u_<UserId>. Cars, money and 할부 live in the garage's store; this one only keeps
-- what makes the dealer feel personal:
--   { v = 1, visits, last (unix), tested = { [entryId] = unix } (≤ 30), best = { [entryId] = { kmh, m } } (≤ 30),
--     wish = { entryId } (≤ C.WISH_MAX), bought (count via the dealer), cashback (won paid back) }
-- Loaded on join (3 tries), saved debounced (≥ saveEvery s), on leave and on shutdown. A failed read never
-- overwrites the saved record (canSave = false for that session).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Store = {}

local S: any
local C: any
local U: any
local ds: GlobalDataStore? = nil

type Rec = { v: number, visits: number, last: number, tested: { [string]: number }, best: { [string]: any }, wish: { string }, bought: number, cashback: number }
type Slot = { rec: Rec, loaded: boolean, canSave: boolean, dirty: boolean, savedAt: number, saving: boolean }

local slots: { [Player]: Slot } = {}

local function blank(): Rec
	return { v = 1, visits = 0, last = 0, tested = {}, best = {}, wish = {}, bought = 0, cashback = 0 }
end

local function num(v: any, lo: number, hi: number, d: number): number
	if type(v) ~= "number" or v ~= v then
		return d
	end
	return math.clamp(v, lo, hi)
end

local function okId(id: any): boolean
	return type(id) == "string" and #id <= 40 and S.Catalog.parse(id) ~= nil
end

local function sanitize(raw: any): Rec
	local r = blank()
	if type(raw) ~= "table" then
		return r
	end
	r.visits = math.floor(num(raw.visits, 0, 1e7, 0))
	r.last = math.floor(num(raw.last, 0, 4e9, 0))
	r.bought = math.floor(num(raw.bought, 0, 1e6, 0))
	r.cashback = math.floor(num(raw.cashback, 0, 1e12, 0))
	if type(raw.tested) == "table" then
		local n = 0
		for k, v in raw.tested do
			if okId(k) and type(v) == "number" and n < 30 then
				r.tested[k] = math.floor(v)
				n += 1
			end
		end
	end
	if type(raw.best) == "table" then
		local n = 0
		for k, v in raw.best do
			if okId(k) and type(v) == "table" and n < 30 then
				r.best[k] = { kmh = math.floor(num(v.kmh, 0, 999, 0)), m = math.floor(num(v.m, 0, 1e6, 0)) }
				n += 1
			end
		end
	end
	if type(raw.wish) == "table" then
		for _, id in raw.wish do
			if okId(id) and not table.find(r.wish, id) and #r.wish < C.WISH_MAX then
				table.insert(r.wish, id)
			end
		end
	end
	return r
end

function Store.init(shared: any)
	S = shared
	C = shared.Config
	U = shared.Util
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(C.STORE.name)
	end)
	if ok then
		ds = store
	else
		warn("[GwangalliCarDealer] DataStore unavailable (Studio API access off?): dealer memory is session-only")
	end
end

local function key(player: Player): string
	return "u_" .. tostring(player.UserId)
end

function Store.load(player: Player)
	if slots[player] then
		return
	end
	local slot: Slot = { rec = blank(), loaded = false, canSave = false, dirty = false, savedAt = os.clock(), saving = false }
	slots[player] = slot
	if not ds or player.UserId <= 0 then
		slot.loaded = true
		return
	end
	for attempt = 1, 3 do
		local ok, raw = pcall(function()
			return (ds :: GlobalDataStore):GetAsync(key(player))
		end)
		if ok then
			if slots[player] ~= slot then
				return
			end
			slot.rec = sanitize(raw)
			slot.canSave = true
			slot.loaded = true
			return
		end
		task.wait(attempt * 1.5)
	end
	warn("[GwangalliCarDealer] could not read the dealer record of " .. player.Name .. " (kept session-only)")
	slot.loaded = true
end

function Store.get(player: Player): Rec
	local slot = slots[player]
	if not slot then
		return blank()
	end
	return slot.rec
end

function Store.ready(player: Player): boolean
	local slot = slots[player]
	return slot ~= nil and slot.loaded
end

function Store.dirty(player: Player)
	local slot = slots[player]
	if slot then
		slot.dirty = true
	end
end

local function save(player: Player, slot: Slot): boolean
	if not ds or not slot.canSave or slot.saving then
		return false
	end
	slot.saving = true
	slot.dirty = false
	local data = slot.rec
	local ok, err = pcall(function()
		(ds :: GlobalDataStore):UpdateAsync(key(player), function()
			return data
		end)
	end)
	slot.saving = false
	slot.savedAt = os.clock()
	if not ok then
		slot.dirty = true
		warn("[GwangalliCarDealer] save failed for " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

function Store.release(player: Player)
	local slot = slots[player]
	if not slot then
		return
	end
	if slot.dirty then
		save(player, slot)
	end
	slots[player] = nil
end

function Store.flushAll()
	local threads = 0
	for player, slot in slots do
		if slot.dirty then
			threads += 1
			task.spawn(function()
				save(player, slot)
				threads -= 1
			end)
		end
	end
	local t0 = os.clock()
	while threads > 0 and os.clock() - t0 < 20 do
		task.wait(0.1)
	end
end

-- Periodic saver (call once)
function Store.run()
	task.spawn(function()
		while true do
			task.wait(5)
			for player, slot in slots do
				if slot.dirty and os.clock() - slot.savedAt >= C.STORE.saveEvery and player.Parent == Players then
					task.spawn(save, player, slot)
				end
			end
		end
	end)
end

-- Helpers used by the service --------------------------------------------------------------------------------
-- A visit counts once per C.STORE.visitGap seconds. -> rec, isNewVisit
function Store.visit(player: Player): (Rec, boolean)
	local r = Store.get(player)
	local now = os.time()
	local fresh = now - r.last >= C.STORE.visitGap
	if fresh then
		r.visits += 1
		r.last = now
		Store.dirty(player)
	end
	return r, fresh
end

local function trim(map: { [string]: any }, limit: number, stamp: (any) -> number)
	local n = 0
	for _ in map do
		n += 1
	end
	while n > limit do
		local oldK, oldT = nil, math.huge
		for k, v in map do
			local t = stamp(v)
			if t < oldT then
				oldK, oldT = k, t
			end
		end
		if not oldK then
			break
		end
		map[oldK] = nil
		n -= 1
	end
end

function Store.tested(player: Player, entryId: string, kmh: number?, meters: number?): boolean
	local r = Store.get(player)
	r.tested[entryId] = os.time()
	trim(r.tested, 30, function(v)
		return v
	end)
	local record = false
	if kmh and U.finite(kmh) then
		local b = r.best[entryId]
		local k = math.floor(math.clamp(kmh, 0, 999))
		local m = math.floor(math.clamp(meters or 0, 0, 1e6))
		if not b or k > b.kmh then
			record = b ~= nil and k > b.kmh
			r.best[entryId] = { kmh = k, m = m }
			trim(r.best, 30, function(v)
				return v.kmh
			end)
		end
	end
	Store.dirty(player)
	return record
end

function Store.lastTested(player: Player): (string?, number?)
	local r = Store.get(player)
	local best, at = nil, 0
	for k, t in r.tested do
		if t > at then
			best, at = k, t
		end
	end
	return best, if best then at else nil
end

function Store.setWish(player: Player, entryId: string, on: boolean): { string }
	local r = Store.get(player)
	local i = table.find(r.wish, entryId)
	if on and not i then
		if #r.wish >= C.WISH_MAX then
			table.remove(r.wish, 1)
		end
		table.insert(r.wish, entryId)
		Store.dirty(player)
	elseif not on and i then
		table.remove(r.wish, i)
		Store.dirty(player)
	end
	return r.wish
end

function Store.bought(player: Player, cashback: number)
	local r = Store.get(player)
	r.bought += 1
	r.cashback += math.max(0, math.floor(cashback))
	Store.dirty(player)
end

return Store
