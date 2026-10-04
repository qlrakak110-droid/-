-- Interact/Memory (server): what each city NPC remembers about each player — the relationship.
--   rec = { aff (-100..100 호감), trust (0..100), fear (0..100), met (meetings), firstT, lastT (os.time),
--           greets { t... } (recent greetings), helped, hurt, insulted, robbed, apologies, gifts,
--           favorAsked (os.time), favorsDone, lastEvent = { kind, t } }
-- Session state is authoritative on the server; it is saved per player in its own DataStore
-- (GwangalliCityMemory_v1) — Profiles drops unknown keys, so the city memory never touches the
-- profile. Without DataStore access (studio / unpublished place) it stays in memory for the session.

local Players = game:GetService("Players")

local Memory = {}

local store: any = nil
local data: { [number]: { [string]: any } } = {} -- userId -> npcId -> rec
local dirty: { [number]: boolean } = {}
local loaded: { [number]: boolean } = {}

local function new(): any
	local t = os.time()
	return { aff = 0, trust = 20, fear = 0, met = 0, firstT = t, lastT = 0, greets = {}, helped = 0, hurt = 0, insulted = 0, robbed = 0, apologies = 0, gifts = 0, favorAsked = 0, favorsDone = 0, lastEvent = nil }
end

function Memory.get(player: Player, npcId: string): any
	local u = player.UserId
	local per = data[u]
	if not per then
		per = {}
		data[u] = per
	end
	local r = per[npcId]
	if not r then
		r = new()
		per[npcId] = r
	end
	return r
end

function Memory.peek(player: Player, npcId: string): any?
	local per = data[player.UserId]
	return per and per[npcId] or nil
end

-- tier from the record: enemy / wary / stranger / known / friendly / friend
function Memory.tier(r: any): string
	if not r or r.met == 0 then
		return "stranger"
	end
	if r.aff <= -40 or r.hurt >= 2 or r.robbed >= 1 then
		return "enemy"
	end
	if r.aff < -10 or r.fear > 50 then
		return "wary"
	end
	if r.aff >= 60 then
		return "friend"
	end
	if r.aff >= 25 then
		return "friendly"
	end
	if r.met >= 2 then
		return "known"
	end
	return "stranger"
end

local function clamp(v: number, a: number, b: number): number
	return math.max(a, math.min(b, v))
end

-- apply an event: kind = greet|talk|joke_good|joke_bad|tease|apology|gift|food|help|favor|bump|shove|
-- punch|rob|insult|follow|report_help|defended
local EFFECT = {
	greet = { aff = 1 },
	talk = { aff = 2, trust = 1 },
	joke_good = { aff = 4, trust = 1 },
	joke_bad = { aff = -2 },
	tease = { aff = -4 },
	tease_ok = { aff = 2 },
	apology = { aff = 3, trust = 2 },
	gift = { aff = 6, trust = 3, gifts = 1 },
	food = { aff = 9, trust = 5, gifts = 1, helped = 1 },
	help = { aff = 10, trust = 6, helped = 1 },
	favor = { aff = 12, trust = 8, favorsDone = 1, helped = 1 },
	bump = { aff = -3 },
	shove = { aff = -8, fear = 6 },
	punch = { aff = -25, fear = 25, trust = -20, hurt = 1 },
	rob = { aff = -35, fear = 30, trust = -30, robbed = 1 },
	insult = { aff = -8, insulted = 1 },
	follow = { aff = -2 },
	defended = { aff = 15, trust = 10, helped = 1 },
	police_help = { aff = 8, trust = 6 },
}

function Memory.event(player: Player, npcId: string, kind: string, scale: number?)
	local r = Memory.get(player, npcId)
	local e = EFFECT[kind]
	local k = scale or 1
	if e then
		r.aff = clamp(r.aff + (e.aff or 0) * k, -100, 100)
		r.trust = clamp(r.trust + (e.trust or 0) * k, 0, 100)
		r.fear = clamp(r.fear + (e.fear or 0) * k, 0, 100)
		for _, f in { "gifts", "helped", "hurt", "robbed", "insulted", "favorsDone" } do
			if e[f] then
				r[f] += e[f]
			end
		end
	end
	if kind == "apology" then
		r.apologies += 1
	end
	r.lastEvent = { kind = kind, t = os.time() }
	dirty[player.UserId] = true
	return r
end

-- a meeting (first contact of a conversation); returns the record + whether it is a new meeting
function Memory.meet(player: Player, npcId: string): (any, boolean)
	local r = Memory.get(player, npcId)
	local now = os.time()
	local fresh = now - (r.lastT or 0) > 180
	if fresh then
		r.met += 1
	end
	r.lastT = now
	dirty[player.UserId] = true
	return r, fresh
end

-- greetings in the last `window` seconds (and records this one)
function Memory.greet(player: Player, npcId: string, window: number): number
	local r = Memory.get(player, npcId)
	local now = os.clock()
	local keep = {}
	for _, t in r.greets do
		if now - t < window then
			table.insert(keep, t)
		end
	end
	table.insert(keep, now)
	r.greets = keep
	return #keep
end

-- fear / anger fade over time (called by Mind now and then)
function Memory.cool(player: Player, npcId: string, dt: number)
	local r = Memory.peek(player, npcId)
	if r and r.fear > 0 then
		r.fear = math.max(0, r.fear - dt * 0.05)
	end
end

---------------------------------------------------------------------------------------------------
-- persistence (best effort)
---------------------------------------------------------------------------------------------------
local function serial(per: { [string]: any }): any
	local out = {}
	for id, r in per do
		out[id] = { aff = r.aff, trust = r.trust, fear = r.fear, met = r.met, firstT = r.firstT, lastT = r.lastT, helped = r.helped, hurt = r.hurt, insulted = r.insulted, robbed = r.robbed, apologies = r.apologies, gifts = r.gifts, favorsDone = r.favorsDone, lastEvent = r.lastEvent }
	end
	return out
end

local function load(player: Player)
	if not store or loaded[player.UserId] then
		return
	end
	loaded[player.UserId] = true
	local ok, res = pcall(function()
		return store:GetAsync("u" .. player.UserId)
	end)
	if ok and type(res) == "table" then
		local per = data[player.UserId] or {}
		for id, r in res do
			if type(r) == "table" then
				local rec = new()
				for k, v in r do
					rec[k] = v
				end
				rec.greets = {}
				per[id] = rec
			end
		end
		data[player.UserId] = per
	end
end

local function save(player: Player)
	local u = player.UserId
	if not store or not dirty[u] or not data[u] then
		return
	end
	dirty[u] = nil
	local payload = serial(data[u])
	pcall(function()
		store:SetAsync("u" .. u, payload)
	end)
end

function Memory.onLoaded(player: Player)
	task.spawn(load, player)
end

function Memory.onLeave(player: Player)
	save(player)
	data[player.UserId] = nil
	dirty[player.UserId] = nil
	loaded[player.UserId] = nil
end

function Memory.init()
	local ok, ds = pcall(function()
		return game:GetService("DataStoreService"):GetDataStore("GwangalliCityMemory_v1")
	end)
	if ok and ds and game.PlaceId ~= 0 then
		store = ds
	end
	task.spawn(function()
		while true do
			task.wait(90)
			for _, p in Players:GetPlayers() do
				save(p)
			end
		end
	end)
end

return Memory
