-- GwangalliAmbience (server): finds, verifies and caches ambient sound loops for the coast with no
-- uploads and no ids typed by anyone (same approach as ClubMusic.server.luau). The client
-- (StarterPlayerScripts/GwangalliAmbience/Soundscape) plays them as spatial beds by zone.
--
-- Categories: waves (beach surf), gulls, traffic (city streets), crowd (people / chatter), wind.
-- Sources, in order:
--   1. Studio override: Workspace attribute GwangalliAmbience_<category> = "id" or "id1, id2"
--   2. the verified list cached in a DataStore by an earlier server (GwangalliAmbience_v1 / loops,
--      pcall'd, skipped in unpublished places)
--   3. Roblox's audio catalogue: AssetService:SearchAudioAsync (AudioSearchParams, SoundEffect,
--      8 s - 10 min), a few keyword queries per category, results scored by title / tags / length
--      (loops and ambiences preferred; music, cartoon, horror, single hits rejected)
-- Every candidate is loaded on the server first (Sound under SoundService: IsLoaded / TimeLength,
-- timeout). If the server cannot load any audio at all the best search results are published
-- unverified and clients report ids that fail for them (RemoteEvent GwangalliAmbienceReport),
-- which drops them. Few HTTP calls: MaxRequests searches per run, spaced, exponential backoff.
--
-- Contract: ReplicatedStorage.GwangalliAmbienceState (Configuration) attributes
--   State      "searching" | "ready" | "none"
--   Serial     increments whenever a list changes
--   <category> "rbxassetid://1,rbxassetid://2" best first ("" = nothing found -> that bed is silent)

local AssetService = game:GetService("AssetService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local STATE_NAME = "GwangalliAmbienceState"
local REMOTE_NAME = "GwangalliAmbienceReport"
local CACHE_STORE = "GwangalliAmbience_v1"
local CACHE_KEY = "loops"
local CACHE_FRESH = 5 * 24 * 3600
local MAX_REQUESTS = 12
local REQUEST_GAP = 2.5
local PROBE_TIMEOUT = 8
local PROBE_PARALLEL = 4
local PER_CATEGORY = 3 -- verified ids kept per category
local PROBES_PER_CATEGORY = 6

local CATEGORIES = { "waves", "gulls", "traffic", "crowd", "wind" }
local SPEC = {
	waves = {
		queries = { "ocean waves", "beach waves", "sea waves loop" },
		good = { "wave", "ocean", "sea", "beach", "shore", "surf", "coast", "seaside", "tide" },
		bad = { "underwater", "splash", "drip", "drop", "river", "stream", "rain", "storm", "thunder", "bubble", "horn", "sonar", "whale" },
	},
	gulls = {
		queries = { "seagulls", "seagull", "seaside birds" },
		good = { "gull", "seagull", "sea bird", "seabird", "harbor", "harbour", "seaside", "coast", "beach" },
		bad = { "crow", "owl", "chicken", "parrot", "pigeon", "jungle", "forest", "night" },
	},
	traffic = {
		queries = { "city traffic", "traffic ambience", "street ambience" },
		good = { "traffic", "city", "street", "cars", "urban", "road", "downtown", "busy" },
		bad = { "crash", "siren", "police", "race", "racing", "rev", "drift", "engine start", "honk", "horn", "skid", "explosion" },
	},
	crowd = {
		queries = { "crowd chatter", "crowd ambience", "people talking ambience" },
		good = { "crowd", "people", "chatter", "talking", "murmur", "walla", "busy", "market", "restaurant", "plaza" },
		bad = { "cheer", "applause", "clap", "scream", "stadium", "laugh", "boo", "riot", "panic", "chant" },
	},
	wind = {
		queries = { "wind ambience", "gentle wind", "coastal wind" },
		good = { "wind", "breeze", "gust", "air", "coastal", "outdoor" },
		bad = { "storm", "hurricane", "tornado", "blizzard", "howl", "whoosh", "swoosh", "swing", "chime" },
	},
}
local COMMON_BAD = {
	"music", "song", "remix", "beat", "cartoon", "comedy", "horror", "scary", "creepy", "meme", "earrape",
	"loud", "jumpscare", "voice", "vocal", "sing", "piano", "guitar", "ringtone", "notification", "button", "ui ",
}
local LOOP_WORDS = { "loop", "ambience", "ambient", "atmosphere", "background", "calm", "gentle", "distant", "soft" }

local function log(...)
	print("[GwangalliAmbience]", ...)
end

---------------------------------------------------------------------------------------------------
-- State object + remote
---------------------------------------------------------------------------------------------------
local state = ReplicatedStorage:FindFirstChild(STATE_NAME)
if not state then
	state = Instance.new("Configuration")
	state.Name = STATE_NAME
	state.Parent = ReplicatedStorage
end
local serial = 0
local lists: { [string]: { any } } = {} -- category -> { { id, title, len, verified } }
local banned: { [string]: boolean } = {}

local function publish(stateName: string?)
	serial += 1
	for _, cat in CATEGORIES do
		local ids = {}
		for _, tr in lists[cat] or {} do
			if not banned[tr.id] then
				table.insert(ids, tr.id)
			end
		end
		state:SetAttribute(cat, table.concat(ids, ","))
	end
	if stateName then
		state:SetAttribute("State", stateName)
	end
	state:SetAttribute("Serial", serial)
end
state:SetAttribute("State", "searching")
publish(nil)

local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
end
local reports: { [string]: { [number]: boolean } } = {}
local lastReport: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(p)
	lastReport[p] = nil
end)
;(remote :: RemoteEvent).OnServerEvent:Connect(function(plr: Player, kind: any, cat: any, id: any)
	if kind ~= "fail" or type(cat) ~= "string" or type(id) ~= "string" or not SPEC[cat] or #id > 64 then
		return
	end
	local now = os.clock()
	if lastReport[plr] and now - lastReport[plr] < 5 then
		return
	end
	lastReport[plr] = now
	local known = false
	local verified = false
	for _, tr in lists[cat] or {} do
		if tr.id == id then
			known = true
			verified = tr.verified == true
		end
	end
	if not known or banned[id] then
		return
	end
	local set = reports[id] or {}
	reports[id] = set
	set[plr.UserId] = true
	local n = 0
	for _ in set do
		n += 1
	end
	local need = if verified then math.max(2, math.ceil(#Players:GetPlayers() * 0.34)) else 1
	if n >= need then
		banned[id] = true
		log("dropping", cat, "loop that fails for players:", id)
		publish(nil)
	end
end)

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------
local function parseIds(value: any): { string }
	local out, seen = {}, {}
	local function add(n: string)
		local id = "rbxassetid://" .. n
		if not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end
	if type(value) == "number" and value > 0 and value == math.floor(value) then
		add(string.format("%d", value))
	elseif type(value) == "string" then
		for token in string.gmatch(value, "[^,;%s]+") do
			local n = string.match(token, "^rbxassetid://(%d+)$") or string.match(token, "^(%d+)$")
			if n then
				add(n)
			end
		end
	end
	return out
end

local function score(cat: string, title: any, artist: any, tags: any, duration: any): number
	if type(title) ~= "string" or #title < 2 or #title > 100 then
		return 0
	end
	if type(duration) == "number" and duration < 5 then
		return 0
	end
	local hay = " " .. string.lower(title) .. " " .. string.lower(if type(artist) == "string" then artist else "")
	if type(tags) == "table" then
		for _, t in tags do
			if type(t) == "string" then
				hay ..= " " .. string.lower(t)
			end
		end
	elseif type(tags) == "string" then
		hay ..= " " .. string.lower(tags)
	end
	local spec = SPEC[cat]
	for _, w in COMMON_BAD do
		if string.find(hay, w, 1, true) then
			return 0
		end
	end
	for _, w in spec.bad do
		if string.find(hay, w, 1, true) then
			return 0
		end
	end
	local s = 0
	for _, w in spec.good do
		if string.find(hay, w, 1, true) then
			s += 2
		end
	end
	if s == 0 then
		return 0
	end
	for _, w in LOOP_WORDS do
		if string.find(hay, w, 1, true) then
			s += 1
		end
	end
	if type(duration) == "number" then
		if duration >= 20 then
			s += 1
		end
		if duration >= 45 then
			s += 1
		end
	end
	return s
end

---------------------------------------------------------------------------------------------------
-- Probing
---------------------------------------------------------------------------------------------------
local probeFolder = Instance.new("Folder")
probeFolder.Name = "GwangalliAmbienceProbe"
probeFolder.Parent = SoundService
local probeLoads, probeErrors = 0, 0

local function probe(id: string): number?
	local s = Instance.new("Sound")
	s.Name = "Probe"
	s.Volume = 0
	local okSet = pcall(function()
		s.SoundId = id
		s.Parent = probeFolder
	end)
	if not okSet then
		s:Destroy()
		probeErrors += 1
		return nil
	end
	local t0 = os.clock()
	local len: number? = nil
	while os.clock() - t0 < PROBE_TIMEOUT do
		local ok, loaded, tl = pcall(function()
			return s.IsLoaded, s.TimeLength
		end)
		if ok and loaded and type(tl) == "number" and tl > 0 then
			len = tl
			break
		end
		task.wait(0.25)
	end
	s:Destroy()
	if len then
		probeLoads += 1
		if len < 5 or len > 900 then
			return nil
		end
	end
	return len
end

local function probeMany(cands: { any }, limit: number, onOk: (any) -> ())
	local running = 0
	for i = 1, math.min(#cands, limit) do
		local tr = cands[i]
		running += 1
		task.spawn(function()
			local len = probe(tr.id)
			if len then
				tr.len = len
				tr.verified = true
				local ok, err = pcall(onOk, tr)
				if not ok then
					warn("[GwangalliAmbience] onOk:", err)
				end
			end
			running -= 1
		end)
		while running >= PROBE_PARALLEL do
			task.wait(0.1)
		end
	end
	local t0 = os.clock()
	while running > 0 and os.clock() - t0 < PROBE_TIMEOUT + 4 do
		task.wait(0.2)
	end
end

local function addTo(cat: string, tr: any)
	local list = lists[cat]
	if not list then
		list = {}
		lists[cat] = list
	end
	for _, t in list do
		if t.id == tr.id then
			return
		end
	end
	if #list >= PER_CATEGORY then
		return
	end
	table.insert(list, tr)
end

---------------------------------------------------------------------------------------------------
-- Cache
---------------------------------------------------------------------------------------------------
local store: any = nil
local function getStore()
	if store then
		return store
	end
	if game.PlaceId == 0 then
		return nil
	end
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore(CACHE_STORE)
	end)
	if ok then
		store = ds
	end
	return store
end

local function loadCache(): ({ [string]: { any } }, number)
	local ds = getStore()
	if not ds then
		return {}, 0
	end
	local ok, data = pcall(function()
		return ds:GetAsync(CACHE_KEY)
	end)
	if not ok or type(data) ~= "table" or type(data.cats) ~= "table" then
		return {}, 0
	end
	local out = {}
	for _, cat in CATEGORIES do
		local list = data.cats[cat]
		if type(list) == "table" then
			out[cat] = {}
			for _, t in list do
				if type(t) == "table" then
					local id = parseIds(t.id)[1]
					if id then
						table.insert(out[cat], { id = id, title = tostring(t.title or ""), len = tonumber(t.len) })
					end
				end
			end
		end
	end
	return out, tonumber(data.t) or 0
end

local function saveCache()
	local ds = getStore()
	if not ds then
		return
	end
	local cats, total = {}, 0
	for _, cat in CATEGORIES do
		cats[cat] = {}
		for _, tr in lists[cat] or {} do
			if tr.verified and not banned[tr.id] and not tr.override then
				table.insert(cats[cat], { id = tr.id, title = string.sub(tr.title or "", 1, 80), len = tr.len })
				total += 1
			end
		end
	end
	if total < 2 then
		return
	end
	local ok, err = pcall(function()
		ds:SetAsync(CACHE_KEY, { v = 1, t = os.time(), cats = cats })
	end)
	if not ok then
		warn("[GwangalliAmbience] cache save failed:", err)
	end
end

---------------------------------------------------------------------------------------------------
-- Catalogue search
---------------------------------------------------------------------------------------------------
local requests = 0
local searchUnavailable = false

local function search(cat: string, keyword: string): ({ any }?, string?)
	local ok, pages = pcall(function()
		local p = Instance.new("AudioSearchParams")
		p.SearchKeyword = keyword
		pcall(function()
			p.AudioSubType = Enum.AudioSubType.SoundEffect
		end)
		pcall(function()
			p.MinDuration = 8
			p.MaxDuration = 600
		end)
		local okAsync, res = pcall(function()
			return (AssetService :: any):SearchAudioAsync(p)
		end)
		if okAsync then
			return res
		end
		if not string.find(string.lower(tostring(res)), "not a valid member", 1, true) then
			error(res, 0)
		end
		return (AssetService :: any):SearchAudio(p)
	end)
	if not ok or pages == nil then
		return nil, tostring(pages)
	end
	local okPage, items = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not okPage or type(items) ~= "table" then
		return nil, tostring(items)
	end
	local out = {}
	for _, it in items do
		if type(it) == "table" then
			local id = parseIds(it.Id or it.AssetId or it.id)[1]
			local title = it.Title or it.Name or it.title
			local dur = tonumber(it.Duration or it.duration)
			local sc = score(cat, title, it.Artist or it.artist, it.Tags, dur)
			if id and sc > 0 then
				table.insert(out, { id = id, title = title, len = dur, score = sc })
			end
		end
	end
	return out, nil
end

local function discover()
	-- 1) Studio overrides
	for _, cat in CATEGORIES do
		local ids = parseIds(workspace:GetAttribute("GwangalliAmbience_" .. cat))
		if #ids > 0 then
			local cands = {}
			for _, id in ids do
				table.insert(cands, { id = id, title = "override", override = true })
			end
			probeMany(cands, #cands, function(tr)
				addTo(cat, tr)
			end)
			if not lists[cat] or #lists[cat] == 0 then
				for _, c in cands do
					addTo(cat, c) -- trust the owner's ids; clients report failures
				end
			end
		end
	end
	-- 2) cache
	local cached, savedAt = loadCache()
	local anyCached = false
	for _, cat in CATEGORIES do
		local list = cached[cat]
		if list and #list > 0 then
			anyCached = true
			local before = if lists[cat] then #lists[cat] else 0
			probeMany(list, PER_CATEGORY, function(tr)
				addTo(cat, tr)
			end)
			if (not lists[cat] or #lists[cat] == before) and probeLoads == 0 then
				for _, c in list do
					addTo(cat, c)
				end
			end
		end
	end
	if anyCached then
		publish("ready")
	end
	local fresh = os.time() - savedAt < CACHE_FRESH
	-- 3) catalogue search for the categories still short
	local fails, backoff = 0, 4
	for _, cat in CATEGORIES do
		if searchUnavailable then
			break
		end
		local have = if lists[cat] then #lists[cat] else 0
		if have >= 2 and fresh then
			continue
		end
		if have >= PER_CATEGORY then
			continue
		end
		local cands, seen = {}, {}
		for _, tr in lists[cat] or {} do
			seen[tr.id] = true
		end
		for _, q in SPEC[cat].queries do
			if requests >= MAX_REQUESTS or #cands >= PROBES_PER_CATEGORY * 2 then
				break
			end
			requests += 1
			local res, err = search(cat, q)
			if res then
				fails, backoff = 0, 4
				for _, c in res do
					if not seen[c.id] then
						seen[c.id] = true
						table.insert(cands, c)
					end
				end
				task.wait(REQUEST_GAP)
			elseif err and string.find(string.lower(err), "not a valid member", 1, true) then
				searchUnavailable = true
				log("AssetService:SearchAudio is not available here; no catalogue search")
				break
			else
				fails += 1
				warn("[GwangalliAmbience] audio search failed:", err)
				if fails >= 3 then
					searchUnavailable = true
					break
				end
				task.wait(backoff)
				backoff *= 2
			end
		end
		if #cands > 0 then
			table.sort(cands, function(a, b)
				return (a.score or 0) > (b.score or 0)
			end)
			local before = if lists[cat] then #lists[cat] else 0
			probeMany(cands, PROBES_PER_CATEGORY, function(tr)
				addTo(cat, tr)
			end)
			if (not lists[cat] or #lists[cat] == before) and probeLoads == 0 and probeErrors < #cands then
				-- this server cannot load audio: publish the best results unverified
				for i = 1, math.min(#cands, PER_CATEGORY) do
					addTo(cat, cands[i])
				end
			end
			-- best score first among the verified ones
			table.sort(lists[cat] or {}, function(a, b)
				return (a.score or 0) > (b.score or 0)
			end)
			publish(nil)
		end
	end
end

task.spawn(function()
	task.wait(4) -- ClubMusic searches first; spread the HTTP calls
	local ok, err = pcall(discover)
	if not ok then
		warn("[GwangalliAmbience] discovery error:", err)
	end
	local total = 0
	local summary = {}
	for _, cat in CATEGORIES do
		local n = if lists[cat] then #lists[cat] else 0
		total += n
		table.insert(summary, cat .. " " .. n)
	end
	publish(if total > 0 then "ready" else "none")
	log(if total > 0 then "ambient loops: " .. table.concat(summary, ", ") else "no ambient loops found; the soundscape stays silent")
	if total > 0 then
		saveCache()
	end
end)
