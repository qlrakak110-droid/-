-- GwangalliPasses/Data (server): the add-on's own saved settings.
--   DataStore GwangalliPasses_v1, key u_<UserId>:
--     { v = 1, garage = { paint = { [carKey] = paintId } }, plate = { text?, style }, neon = id?, ko = id?, t = os.time() }
--   DataStore GwangalliPlates_v1, key Plates.claimKey(text) -> owner UserId (0 = released): unique custom plates.
-- Loads with retries; a profile whose load failed is never saved (no wipe on an outage). Saves are debounced,
-- on leave and on BindToClose. Studio without API access / no DataStore: memory only.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Data = {}

local Config: any, Util: any, PlatesShared: any
local store: DataStore? = nil
local plateStore: DataStore? = nil
local profiles: { [Player]: any } = {}
local state: { [Player]: { loaded: boolean, failed: boolean, dirty: boolean, saving: boolean } } = {}
local loadedEv = Instance.new("BindableEvent")
Data.loaded = loadedEv.Event -- (player, profile)

local function defaults(): any
	return { v = 1, garage = { paint = {} }, plate = { text = nil, style = Config.PLATE.DEFAULT_STYLE }, neon = nil, ko = nil, t = 0 }
end

-- keeps only known fields / types (never trust saved data blindly either)
local function sanitize(raw: any): any
	local d = defaults()
	if type(raw) ~= "table" then
		return d
	end
	if type(raw.garage) == "table" and type(raw.garage.paint) == "table" then
		for k, v in raw.garage.paint do
			if type(k) == "string" and #k <= 16 and type(v) == "string" and #v <= 24 then
				d.garage.paint[k] = v
			end
		end
	end
	if type(raw.plate) == "table" then
		if type(raw.plate.text) == "string" and #raw.plate.text <= 40 then
			d.plate.text = raw.plate.text
		end
		if type(raw.plate.style) == "string" and #raw.plate.style <= 16 then
			d.plate.style = raw.plate.style
		end
	end
	if type(raw.neon) == "string" and #raw.neon <= 16 then
		d.neon = raw.neon
	end
	if type(raw.ko) == "string" and #raw.ko <= 16 then
		d.ko = raw.ko
	end
	d.t = tonumber(raw.t) or 0
	return d
end

local function keyOf(player: Player): string
	return "u_" .. tostring(player.UserId)
end

-- changes made while the profile is still loading are replayed on the loaded copy (never lost, never saved
-- over an unread profile)
local pending: { [Player]: { (any) -> () } } = {}
local function flushPending(player: Player)
	local list = pending[player]
	pending[player] = nil
	local prof = profiles[player]
	local st = state[player]
	if not list or not prof or not st then
		return
	end
	for _, fn in list do
		local ok, err = pcall(fn, prof)
		if not ok then
			Util.warnOnce("pending update", err)
		end
	end
	if not st.failed then
		task.defer(Data.update, player, function() end) -- schedules the debounced save
	end
end

local function load(player: Player)
	local st = { loaded = false, failed = false, dirty = false, saving = false }
	state[player] = st
	profiles[player] = defaults()
	if not store then
		st.loaded = true
		task.defer(function()
			loadedEv:Fire(player, profiles[player])
		end)
		return
	end
	for i = 1, Config.DATA.RETRIES do
		local ok, res = pcall(function()
			return (store :: DataStore):GetAsync(keyOf(player))
		end)
		if ok then
			if player.Parent ~= Players then
				return
			end
			profiles[player] = sanitize(res)
			st.loaded = true
			flushPending(player)
			loadedEv:Fire(player, profiles[player])
			return
		end
		Util.warnOnce("load " .. player.UserId, res)
		-- Studio without "Enable Studio Access to API Services" / an unpublished place: no point retrying
		local msg = string.lower(tostring(res))
		if RunService:IsStudio() and (string.find(msg, "studio", 1, true) or string.find(msg, "publish", 1, true) or string.find(msg, "api", 1, true)) then
			break
		end
		if i < Config.DATA.RETRIES then
			task.wait(2 * i)
		end
	end
	if player.Parent ~= Players then
		return
	end
	st.failed = true -- keep defaults for this session, never overwrite the saved copy
	st.loaded = true
	flushPending(player)
	loadedEv:Fire(player, profiles[player])
end

local function save(player: Player, final: boolean?)
	local st = state[player]
	local prof = profiles[player]
	if not st or not prof or st.failed or not st.loaded or not store then
		return
	end
	if not st.dirty and not final then
		return
	end
	if st.saving then
		return
	end
	st.saving = true
	st.dirty = false
	prof.t = os.time()
	local copy = table.clone(prof)
	for i = 1, Config.DATA.RETRIES do
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(keyOf(player), function()
				return copy
			end)
		end)
		if ok then
			break
		end
		Util.warnOnce("save " .. player.UserId, err)
		if i < Config.DATA.RETRIES then
			task.wait(2 * i)
		else
			st.dirty = true
		end
	end
	st.saving = false
end

function Data.get(player: Player): any
	return profiles[player] or defaults()
end

-- fn(player, profile) for every player whose profile is (or becomes) loaded, including those loaded already
function Data.onLoaded(fn: (Player, any) -> ())
	loadedEv.Event:Connect(fn)
	for p, st in state do
		if st.loaded and p.Parent == Players then
			task.spawn(fn, p, profiles[p])
		end
	end
end

function Data.isLoaded(player: Player): boolean
	local st = state[player]
	return st ~= nil and st.loaded
end

-- fn(profile) mutates; the save follows SAVE_DEBOUNCE s later
function Data.update(player: Player, fn: (any) -> ())
	local prof = profiles[player]
	local st = state[player]
	if not prof or not st then
		return
	end
	fn(prof)
	if not st.loaded then
		-- applied to the session copy now (attributes / UI react at once) and replayed after the load
		local list = pending[player] or {}
		pending[player] = list
		table.insert(list, fn)
		return
	end
	st.dirty = true
	if (st :: any).scheduled then
		return
	end
	(st :: any).scheduled = true
	task.delay(Config.DATA.SAVE_DEBOUNCE, function()
		(st :: any).scheduled = false
		if player.Parent == Players then
			save(player)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- unique plates
---------------------------------------------------------------------------------------------------
local localClaims: { [string]: number } = {} -- this server (fallback + fast check)

-- -> ok, code ("taken" | nil)
function Data.claimPlate(player: Player, clean: string): (boolean, string?)
	local key = PlatesShared.claimKey(clean)
	local uid = player.UserId
	local holder = localClaims[key]
	if holder and holder ~= uid then
		local other = Players:GetPlayerByUserId(holder)
		if other then
			return false, "taken"
		end
	end
	if Config.PLATE.UNIQUE and plateStore then
		local taken = false
		local ok, err = pcall(function()
			(plateStore :: DataStore):UpdateAsync(key, function(old: any)
				local o = tonumber(old)
				if o ~= nil and o ~= 0 and o ~= uid then
					taken = true
					return nil
				end
				return uid
			end)
		end)
		if ok and taken then
			return false, "taken"
		end
		if not ok then
			Util.warnOnce("plate claim", err) -- outage: this server's check only
		end
	end
	localClaims[key] = uid
	return true, nil
end

function Data.releasePlate(player: Player, clean: string?)
	if type(clean) ~= "string" or clean == "" then
		return
	end
	local key = PlatesShared.claimKey(clean)
	local uid = player.UserId
	if localClaims[key] == uid then
		localClaims[key] = nil
	end
	if Config.PLATE.UNIQUE and plateStore then
		task.spawn(function()
			pcall(function()
				(plateStore :: DataStore):UpdateAsync(key, function(old: any)
					if tonumber(old) == uid then
						return 0
					end
					return nil
				end)
			end)
		end)
	end
end

function Data.start(ctx: any)
	Config, Util = ctx.Config, ctx.Util
	PlatesShared = ctx.P.mod("Plates")
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(Config.DATA.STORE)
	end)
	if ok then
		store = s
	else
		Util.warnOnce("datastore", "not available, settings are kept for this session only (" .. tostring(s) .. ")")
	end
	local okP, ps = pcall(function()
		return DataStoreService:GetDataStore(Config.DATA.PLATES)
	end)
	if okP then
		plateStore = ps
	end
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerAdded:Connect(function(p: Player)
		load(p)
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		save(p, true)
		profiles[p] = nil
		state[p] = nil
		pending[p] = nil
		for k, uid in localClaims do
			if uid == p.UserId then
				localClaims[k] = nil
			end
		end
	end)
	game:BindToClose(function()
		local n = 0
		for _, p in Players:GetPlayers() do
			n += 1
			task.spawn(function()
				save(p, true)
				n -= 1
			end)
		end
		local t0 = os.clock()
		while n > 0 and os.clock() - t0 < 20 do
			task.wait(0.2)
		end
	end)
end

return Data
