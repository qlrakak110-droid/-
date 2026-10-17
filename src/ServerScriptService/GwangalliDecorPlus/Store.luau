--!strict
-- GwangalliDecorPlus/Store: the add-on's own DataStore (Config.DATASTORE, key "u_<UserId>"). The life-game
-- profile drops unknown keys and ids, so placed pieces, looks, 창고, presets, likes and the 방명록 of this
-- catalog live here. UpdateAsync + session lock (taken over when stale or after retries), autosave,
-- coalesced saveSoon, save + unlock on leave and BindToClose. Without DataStore access (unpublished
-- Studio, outage) a profile stays in memory only: Store.persistent(p) = false and the UI says so.
--   Store.load(p) (yields) / Store.get(p) / Store.wait(p, t) / Store.dirty(p) / Store.saveSoon(p)
--   Store.release(p) (yields) / Store.persistent(p) / Store.startAutosave()

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliDecorShared"))
local Codec = Shared.Codec
local Config = Shared.Config

local Store = {}

local store: DataStore? = nil
do
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE)
	end)
	if ok then
		store = ds
	end
end

type Slot = { data: any, persistent: boolean, dirty: boolean, lastSave: number, saving: boolean, soon: boolean, released: boolean }
local slots: { [Player]: Slot } = {}
local loading: { [Player]: boolean } = {}
local JOB = if game.JobId ~= "" then game.JobId else ("studio-" .. tostring(math.random(1, 1e9)))

local function key(p: Player): string
	return "u_" .. tostring(p.UserId)
end

-- errors that no retry will fix (unpublished place, Studio without API access)
local function fatal(err: any): boolean
	local s = tostring(err)
	return string.find(s, "StudioAccessToApisNotAllowed", 1, true) ~= nil or string.find(s, "API Services", 1, true) ~= nil or string.find(s, "not published", 1, true) ~= nil or string.find(s, "403", 1, true) ~= nil
end

local function retry<T>(n: number, fn: () -> T): (boolean, any)
	local lastErr = nil
	for i = 1, n do
		local ok, r = pcall(fn)
		if ok then
			return true, r
		end
		lastErr = r
		if fatal(r) then
			break
		end
		if i < n then
			task.wait(math.min(8, 1.5 * i))
		end
	end
	return false, lastErr
end

function Store.load(p: Player): any
	if slots[p] then
		return slots[p].data
	end
	if loading[p] then
		return Store.wait(p, 30)
	end
	loading[p] = true
	local data: any = nil
	local persistent = false
	if store then
		local attempts = 0
		local ok, res = false, nil
		while attempts < Config.LOAD_RETRIES and p.Parent == Players do
			attempts += 1
			local locked = false
			ok, res = retry(3, function()
				local out = nil
				;(store :: DataStore):UpdateAsync(key(p), function(old: any)
					local now = os.time()
					local lock = type(old) == "table" and old.lock or nil
					if type(lock) == "table" and lock.sid ~= JOB and type(lock.t) == "number" and now - lock.t < Config.LOCK_STALE and attempts < Config.LOAD_RETRIES then
						locked = true
						out = nil
						return nil -- keep it; try again shortly
					end
					local blob = if type(old) == "table" then old else {}
					blob.lock = { sid = JOB, t = now }
					out = blob
					return blob
				end)
				return out
			end)
			if not ok or not locked then
				break -- loaded, or failed for good (memory fallback below)
			end
			task.wait(4) -- another server still holds the session lock
		end
		if ok and type(res) == "table" then
			data = Codec.sanitize(res.data)
			persistent = true
		elseif ok and res == nil then
			data = Codec.newData()
			persistent = true
		else
			warn("[GwangalliDecorPlus] DataStore load failed for " .. p.Name .. ": " .. tostring(res) .. " (memory only)")
		end
	end
	if not data then
		data = Codec.newData()
	end
	loading[p] = nil
	if p.Parent ~= Players then
		return nil
	end
	slots[p] = { data = data, persistent = persistent, dirty = false, lastSave = os.clock(), saving = false, soon = false, released = false }
	return data
end

function Store.get(p: Player): any?
	local s = slots[p]
	return s and s.data or nil
end

function Store.wait(p: Player, timeout: number?): any?
	local t0 = os.clock()
	while p.Parent == Players and os.clock() - t0 < (timeout or 20) do
		local s = slots[p]
		if s then
			return s.data
		end
		task.wait(0.25)
	end
	local s = slots[p]
	return s and s.data or nil
end

function Store.persistent(p: Player): boolean
	local s = slots[p]
	return s ~= nil and s.persistent
end

function Store.dirty(p: Player)
	local s = slots[p]
	if s then
		s.dirty = true
	end
end

local function save(p: Player, release: boolean): boolean
	local s = slots[p]
	if not s or not s.persistent or not store then
		return false
	end
	if s.saving then
		-- one write at a time per key
		local t0 = os.clock()
		while s.saving and os.clock() - t0 < 15 do
			task.wait(0.2)
		end
	end
	s.saving = true
	local blob = Codec.serialize(s.data)
	s.dirty = false
	local ok, err = retry(if release then 4 else 2, function()
		(store :: DataStore):UpdateAsync(key(p), function(old: any)
			local cur = if type(old) == "table" then old else {}
			local lock = cur.lock
			if type(lock) == "table" and lock.sid ~= JOB and type(lock.t) == "number" and os.time() - lock.t < Config.LOCK_STALE then
				-- another server owns this profile now: never overwrite it
				return nil
			end
			cur.data = blob
			cur.lock = if release then nil else { sid = JOB, t = os.time() }
			cur.saved = os.time()
			return cur
		end)
	end)
	s.saving = false
	s.lastSave = os.clock()
	if not ok then
		s.dirty = true
		warn("[GwangalliDecorPlus] save failed for " .. p.Name .. ": " .. tostring(err))
	end
	return ok
end

function Store.saveSoon(p: Player)
	local s = slots[p]
	if not s then
		return
	end
	s.dirty = true
	if s.soon or not s.persistent then
		return
	end
	s.soon = true
	task.delay(Config.SAVE_SOON, function()
		s.soon = false
		if slots[p] == s and s.dirty and not s.released then
			local gap = os.clock() - s.lastSave
			if gap < Config.SAVE_MIN_GAP then
				task.wait(Config.SAVE_MIN_GAP - gap)
			end
			if slots[p] == s and not s.released then
				save(p, false)
			end
		end
	end)
end

function Store.release(p: Player)
	local s = slots[p]
	if not s or s.released then
		return
	end
	s.released = true
	save(p, true)
	slots[p] = nil
end

function Store.startAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_SECONDS)
			for p, s in slots do
				if s.dirty and not s.released and p.Parent == Players then
					task.spawn(save, p, false)
				end
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for p, s in slots do
			if not s.released then
				pending += 1
				task.spawn(function()
					s.released = true
					save(p, true)
					pending -= 1
				end)
			end
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < (if RunService:IsStudio() then 5 else 25) do
			task.wait(0.2)
		end
	end)
end

return Store
