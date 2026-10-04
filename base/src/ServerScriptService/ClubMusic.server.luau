-- ClubMusic (server): finds, verifies and schedules dance music for CLUB OCEAN 광안 with no uploads
-- and no ids typed by anyone.
--  * Playlist sources, in order: the club model's MusicAssetId attribute (one id or "id1, id2"),
--    the validated playlist cached in a DataStore by an earlier server, then Roblox's audio catalogue
--    (AssetService:SearchAudio with AudioSearchParams: Monstercat / APM / EDM / dance / house ...,
--    AudioSubType Music, 1.5-6 min), scored by title / artist / tags.
--  * Every candidate is loaded on the server first (Sound under SoundService, IsLoaded / TimeLength
--    with a timeout); audio the experience cannot play is dropped. If the server cannot load any
--    audio at all (no error, just no load) the search results are used unverified and clients report
--    tracks that fail for them (RemoteEvent ClubMusicReport), which skips them.
--  * Few HTTP calls: at most Search.MaxRequests searches per run, spaced, pcall'd, exponential
--    backoff; the verified playlist is cached (DataStore, pcall) so later servers start in seconds.
--  * Synced playback: TrackId / TrackTitle / TrackArtist / TrackStart (server time) / TrackLength /
--    TrackBpm / TrackSerial / NextTrackId on every ClubRuntime model and on
--    ReplicatedStorage.ClubMusicState (see ClubMusicShared). The next track is published
--    Play.Crossfade seconds before the current one ends (clients crossfade).
--  * MusicOwner = "ClubMusic" on the same instances: ClubLights' own optional MusicAssetId player
--    must stand down when it sees it (one-line guard, see ClubMusicShared / integration notes).
--  * No music found: MusicState = "none", TrackId = "" -> the club runs on its 126 BPM clock; one
--    more discovery attempt 5 minutes later.

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local mod = ReplicatedStorage:WaitForChild("ClubMusicShared", 30)
if not mod then
	warn("[ClubMusic] ReplicatedStorage.ClubMusicShared missing; club music disabled")
	return
end
local okM, S = pcall(require, mod)
if not okM or type(S) ~= "table" then
	warn("[ClubMusic] ClubMusicShared failed to load:", S)
	return
end

local A = S.Attr
local SEARCH = S.Search
local PLAY = S.Play
local TAG_RUNTIME = "ClubRuntime"
local TAG_VENUE = "ClubVenue"
local rng = Random.new()

local function log(...)
	print("[ClubMusic]", ...)
end

---------------------------------------------------------------------------------------------------
-- Publishing targets: every ClubRuntime model + ReplicatedStorage.ClubMusicState
---------------------------------------------------------------------------------------------------
local stateObj = ReplicatedStorage:FindFirstChild(S.STATE_NAME)
if not stateObj then
	stateObj = Instance.new("Configuration")
	stateObj.Name = S.STATE_NAME
	stateObj.Parent = ReplicatedStorage
end

local published: { [string]: any } = {
	[A.Owner] = S.OWNER,
	[A.State] = "searching",
	[A.TrackId] = "",
	[A.Title] = "",
	[A.Artist] = "",
	[A.Start] = 0,
	[A.Length] = 0,
	[A.Bpm] = 0,
	[A.Serial] = 0,
	[A.Next] = "",
}
local runtimes: { [Instance]: boolean } = {}

local function applyAll(inst: Instance)
	for k, v in published do
		pcall(inst.SetAttribute, inst, k, v)
	end
end

local function publish(values: { [string]: any })
	for k, v in values do
		published[k] = v
	end
	applyAll(stateObj)
	for rt in runtimes do
		if rt.Parent then
			applyAll(rt)
		end
	end
end

local function addRuntime(inst: Instance)
	if runtimes[inst] then
		return
	end
	runtimes[inst] = true
	applyAll(inst)
end
CollectionService:GetInstanceAddedSignal(TAG_RUNTIME):Connect(addRuntime)
CollectionService:GetInstanceRemovedSignal(TAG_RUNTIME):Connect(function(inst)
	runtimes[inst] = nil
end)
for _, inst in CollectionService:GetTagged(TAG_RUNTIME) do
	addRuntime(inst)
end
publish({})

-- override ids from the club model (or its ClubRuntime copy)
local function overrideIds(): { string }
	local venues = CollectionService:GetTagged(TAG_VENUE)
	for rt in runtimes do
		if rt.Parent then
			table.insert(venues, rt.Parent)
			table.insert(venues, rt)
		end
	end
	for _, v in venues do
		local ok, value = pcall(v.GetAttribute, v, A.Override)
		if ok then
			local list = S.parseIdList(value)
			if #list > 0 then
				return list
			end
		end
	end
	return {}
end

---------------------------------------------------------------------------------------------------
-- Probing (can this experience play the id?)
---------------------------------------------------------------------------------------------------
local probeFolder = Instance.new("Folder")
probeFolder.Name = "ClubMusicProbe"
probeFolder.Parent = SoundService

local probeLoads = 0 -- probes that loaded (0 after many tries = the server cannot load audio)
local probeErrors = 0

-- -> length (seconds) or nil
local function probe(id: string): number?
	local s = Instance.new("Sound")
	s.Name = "Probe"
	s.Volume = 0
	s.Looped = false
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
	while os.clock() - t0 < SEARCH.ProbeTimeout do
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
		if len < 60 or len > 600 then
			return nil
		end
	end
	return len
end

-- probes `cands` (array of track records) up to `limit` in parallel batches; calls onOk(track)
local function probeMany(cands: { any }, limit: number, onOk: (any) -> ())
	local i = 0
	local running = 0
	while i < #cands and i < limit do
		i += 1
		local tr = cands[i]
		running += 1
		task.spawn(function()
			local len = probe(tr.id)
			if len then
				tr.len = len
				tr.verified = true
				local ok, err = pcall(onOk, tr)
				if not ok then
					warn("[ClubMusic] onOk:", err)
				end
			end
			running -= 1
		end)
		while running >= SEARCH.ProbeParallel do
			task.wait(0.1)
		end
	end
	local t0 = os.clock()
	while running > 0 and os.clock() - t0 < SEARCH.ProbeTimeout + 5 do
		task.wait(0.2)
	end
end

---------------------------------------------------------------------------------------------------
-- Playlist + playback
---------------------------------------------------------------------------------------------------
local playlist: { any } = {} -- { id, title, artist, len, bpm, verified }
local inList: { [string]: boolean } = {}
local banned: { [string]: boolean } = {}
local order: { number } = {} -- shuffled indices into playlist
local orderPos = 0
local current: any = nil
local serial = 0
local wake = false -- set to advance now (failed track, first track found)

local function addTrack(tr: any)
	if inList[tr.id] or banned[tr.id] then
		return
	end
	inList[tr.id] = true
	tr.bpm = tr.bpm or S.bpmFromText(tr.title)
	table.insert(playlist, tr)
	if not current then
		wake = true
	end
end

local function reshuffle()
	table.clear(order)
	for i = 1, #playlist do
		if not banned[playlist[i].id] then
			table.insert(order, i)
		end
	end
	S.shuffle(order, rng)
	-- do not repeat the track that just played
	if current and #order > 1 and playlist[order[1]] == current then
		order[1], order[#order] = order[#order], order[1]
	end
	orderPos = 0
end

local function nextTrack(): any
	for _ = 1, #playlist + 1 do
		if orderPos >= #order then
			reshuffle()
			if #order == 0 then
				return nil
			end
		end
		orderPos += 1
		local tr = playlist[order[orderPos]]
		if tr and not banned[tr.id] then
			return tr
		end
	end
	return nil
end

local function peekNext(): string
	local i = orderPos + 1
	local tr = order[i] and playlist[order[i]]
	return if tr then tr.id else ""
end

local function startTrack(tr: any)
	current = tr
	serial += 1
	local start = workspace:GetServerTimeNow() + PLAY.Lead
	tr.startAt = start
	publish({
		[A.State] = "playing",
		[A.TrackId] = tr.id,
		[A.Title] = tostring(tr.title or ""),
		[A.Artist] = tostring(tr.artist or ""),
		[A.Start] = start,
		[A.Length] = tr.len or 150,
		[A.Bpm] = tr.bpm or 0,
		[A.Serial] = serial,
		[A.Next] = peekNext(),
	})
	log(("now playing %s - %s (%s, %.0f s)"):format(tostring(tr.artist), tostring(tr.title), tr.id, tr.len or 0))
end

local function publishNone()
	current = nil
	publish({
		[A.State] = "none",
		[A.TrackId] = "",
		[A.Title] = "",
		[A.Artist] = "",
		[A.Start] = 0,
		[A.Length] = 0,
		[A.Bpm] = 0,
		[A.Next] = "",
	})
end

-- scheduler: starts the first track as soon as one is verified, advances at the crossfade point
task.spawn(function()
	while true do
		local advance = wake
		if current and current.startAt then
			local endAt = current.startAt + (current.len or 150) - PLAY.Crossfade
			if workspace:GetServerTimeNow() >= endAt then
				advance = true
			end
		elseif not current and #playlist > 0 then
			advance = true
		end
		if advance then
			wake = false
			local tr = nextTrack()
			if tr then
				startTrack(tr)
			elseif published[A.State] == "playing" then
				publishNone()
			end
		end
		task.wait(0.5)
	end
end)

---------------------------------------------------------------------------------------------------
-- Client failure reports (unverified tracks, or audio that fails for players)
---------------------------------------------------------------------------------------------------
local remote = ReplicatedStorage:FindFirstChild(S.REMOTE_NAME)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = S.REMOTE_NAME
	remote.Parent = ReplicatedStorage
end
local reports: { [string]: { [number]: boolean } } = {}
local lastReport: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(p)
	lastReport[p] = nil
end)
;(remote :: RemoteEvent).OnServerEvent:Connect(function(plr: Player, kind: any, id: any)
	if kind ~= "fail" or type(id) ~= "string" or not current or id ~= current.id then
		return
	end
	local now = os.clock()
	if lastReport[plr] and now - lastReport[plr] < 10 then
		return
	end
	lastReport[plr] = now
	local set = reports[id] or {}
	reports[id] = set
	set[plr.UserId] = true
	local n = 0
	for _ in set do
		n += 1
	end
	local need = if current.verified then math.max(2, math.ceil(#Players:GetPlayers() * 0.34)) else 1
	if n >= need then
		banned[id] = true
		log("skipping track that fails for players:", id)
		wake = true
	end
end)

---------------------------------------------------------------------------------------------------
-- Discovery
---------------------------------------------------------------------------------------------------
local store: any = nil
local function getStore()
	if store then
		return store
	end
	if game.PlaceId == 0 then
		return nil -- unpublished place (Studio / tests): no DataStore
	end
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore(SEARCH.CacheStore)
	end)
	if ok then
		store = ds
	end
	return store
end

local function loadCache(): ({ any }, number)
	local ds = getStore()
	if not ds then
		return {}, 0
	end
	local ok, data = pcall(function()
		return ds:GetAsync(SEARCH.CacheKey)
	end)
	if not ok or type(data) ~= "table" or type(data.tracks) ~= "table" then
		return {}, 0
	end
	local out = {}
	for _, t in data.tracks do
		if type(t) == "table" then
			local id = S.soundId(t.id)
			if id then
				table.insert(out, { id = id, title = tostring(t.title or ""), artist = tostring(t.artist or ""), len = tonumber(t.len) })
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
	local tracks = {}
	for _, tr in playlist do
		if tr.verified and not banned[tr.id] and not tr.override then
			table.insert(tracks, { id = tr.id, title = string.sub(tr.title or "", 1, 90), artist = string.sub(tr.artist or "", 1, 60), len = tr.len })
		end
	end
	if #tracks < 4 then
		return
	end
	local ok, err = pcall(function()
		ds:SetAsync(SEARCH.CacheKey, { v = 1, t = os.time(), tracks = tracks })
	end)
	if not ok then
		warn("[ClubMusic] cache save failed:", err)
	end
end

-- one SearchAudio request -> array of candidate records
local function search(q: any): ({ any }?, string?)
	local ok, pages = pcall(function()
		local p = Instance.new("AudioSearchParams")
		if q.keyword then
			p.SearchKeyword = q.keyword
		end
		if q.artist then
			p.Artist = q.artist
		end
		pcall(function()
			p.AudioSubType = Enum.AudioSubType.Music
		end)
		pcall(function()
			p.MinDuration = SEARCH.MinDuration
			p.MaxDuration = SEARCH.MaxDuration
		end)
		-- SearchAudioAsync is the current name; SearchAudio is the deprecated alias
		local okAsync, res = pcall(function()
			return (AssetService :: any):SearchAudioAsync(p)
		end)
		if okAsync then
			return res
		end
		if not string.find(string.lower(tostring(res)), "not a valid member", 1, true) then
			error(res, 0) -- a real failure (rate limit, network): let the caller back off
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
			local id = S.soundId(it.Id or it.AssetId or it.id)
			local title = it.Title or it.Name or it.title
			local artist = it.Artist or it.artist or ""
			local dur = tonumber(it.Duration or it.duration)
			local score = S.scoreTrack(title, artist, it.Tags, dur)
			if id and score > 0 then
				table.insert(out, { id = id, title = title, artist = artist, len = dur, score = score })
			end
		end
	end
	return out, nil
end

local searchUnavailable = false

local function discover()
	publish({ [A.State] = if current then "playing" else "searching" })
	-- 1) override
	local ids = overrideIds()
	if #ids > 0 then
		local cands = {}
		for _, id in ids do
			table.insert(cands, { id = id, title = "CLUB OCEAN 광안", artist = "Resident DJ", override = true })
		end
		probeMany(cands, 20, addTrack)
		if #playlist == 0 and probeLoads == 0 then
			-- the server could not load them; trust the owner's ids, clients report failures
			for _, c in cands do
				c.len = c.len or 180
				addTrack(c)
			end
		end
		log(#playlist, "override track(s)")
	end
	-- 2) cache
	local cached, savedAt = loadCache()
	if #cached > 0 then
		local before = #playlist
		probeMany(cached, SEARCH.Target, addTrack)
		if #playlist == before and probeLoads == 0 then
			-- verified by an earlier server; this one cannot load audio itself
			for _, c in cached do
				c.len = c.len or 150
				addTrack(c)
			end
		end
		log(#playlist, "track(s) after the cache")
	end
	local fresh = os.time() - savedAt < SEARCH.CacheFreshSeconds
	if #playlist >= math.floor(SEARCH.Target * 0.6) and fresh then
		return
	end
	-- 3) catalogue search
	local cands: { any } = {}
	local seen: { [string]: boolean } = {}
	for _, tr in playlist do
		seen[tr.id] = true
	end
	local fails, backoff, requests = 0, 4, 0
	for _, q in SEARCH.Queries do
		if requests >= SEARCH.MaxRequests or #cands >= SEARCH.MaxProbes * 2 then
			break
		end
		requests += 1
		local res, err = search(q)
		if res then
			fails, backoff = 0, 4
			for _, c in res do
				if not seen[c.id] then
					seen[c.id] = true
					table.insert(cands, c)
				end
			end
			task.wait(SEARCH.RequestGap)
		elseif err and string.find(string.lower(err), "not a valid member", 1, true) then
			searchUnavailable = true
			log("AssetService:SearchAudio is not available here; no catalogue search")
			break
		else
			fails += 1
			warn("[ClubMusic] audio search failed:", err)
			if fails >= 3 then
				break
			end
			task.wait(backoff)
			backoff *= 2
		end
	end
	if #cands == 0 then
		log("no catalogue results")
		return
	end
	table.sort(cands, function(a, b)
		return (a.score or 0) > (b.score or 0)
	end)
	-- shuffle within equal-ish scores so servers do not all play the same order
	local need = SEARCH.Target - #playlist
	local verifiedBefore = #playlist
	local probed = math.min(#cands, SEARCH.MaxProbes)
	local batch = {}
	for i = 1, probed do
		table.insert(batch, cands[i])
	end
	-- probe in chunks until the playlist is full
	local pos = 1
	while pos <= #batch and #playlist - verifiedBefore < need do
		local chunk = {}
		for i = pos, math.min(#batch, pos + SEARCH.ProbeParallel * 2 - 1) do
			table.insert(chunk, batch[i])
		end
		pos += #chunk
		probeMany(chunk, #chunk, addTrack)
	end
	if #playlist == verifiedBefore and probeLoads == 0 and probeErrors < probed then
		-- nothing loaded on this server (and no hard errors): use the search results unverified
		log("server could not load any audio; using search results unverified")
		for i = 1, math.min(#cands, SEARCH.Target) do
			local c = cands[i]
			c.len = c.len or 150
			addTrack(c)
		end
	end
	log(#playlist, "track(s) in the playlist")
	saveCache()
end

task.spawn(function()
	task.wait(2) -- let the world scripts start first
	local ok, err = pcall(discover)
	if not ok then
		warn("[ClubMusic] discovery error:", err)
	end
	if #playlist == 0 then
		log("no playable music found; the club runs on its 126 BPM clock")
		publishNone()
		if searchUnavailable then
			return
		end
		task.wait(300)
		ok, err = pcall(discover)
		if not ok then
			warn("[ClubMusic] discovery retry error:", err)
		end
		if #playlist == 0 then
			publishNone()
		end
	end
end)
