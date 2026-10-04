-- ClubMusicShared: contract + pure helpers for the CLUB OCEAN 광안 music system, and the client-side
-- beat signal other scripts (ClubLights, crowd) subscribe to.
--
-- Written by ClubMusic.server.luau (on the Persistent ClubRuntime model AND on
-- ReplicatedStorage.ClubMusicState, a Configuration that always exists):
--   MusicOwner  "ClubMusic"          -> ClubLights must NOT play its own MusicAssetId sound
--   MusicState  "searching" | "playing" | "none"
--   TrackId     "rbxassetid://123" | ""        TrackTitle / TrackArtist  strings
--   TrackStart  server time (workspace:GetServerTimeNow()) at which TimePosition = 0
--   TrackLength seconds                        TrackBpm  number (0 = unknown)
--   TrackSerial increments on every track change (also when the same id repeats)
--   NextTrackId the id that follows (clients may preload it)
--
-- Client signal (ClubMusic.client.luau feeds it; ModuleScripts are cached per peer, so every
-- LocalScript that requires this module sees the same state):
--   ClubMusicShared.Beat:Connect(function(intensity: number, isDrop: boolean) end) -> connection
--       (connection:Disconnect()). intensity 0..1. Fired on detected onsets of the playing track,
--       or on the 126 BPM clock (ShowEpoch aligned, like ClubLights) when there is no audible music.
--   ClubMusicShared.Drop:Connect(function(intensity: number) end)  -- only the drops
--   ClubMusicShared.level() -> 0..1 smoothed loudness envelope (synthetic pulse on the fallback clock)
--   ClubMusicShared.bpm()   -> estimated BPM of the playing track (126 fallback)
--   ClubMusicShared.isLive() -> true while beats come from real audio (false = fallback clock)
--   ClubMusicShared.nowPlaying() -> (title, artist) or nil
-- Handlers run synchronously inside pcall (an erroring handler never breaks the others); keep them
-- cheap (no yields). No instances are created here.

local M = {}

M.OWNER = "ClubMusic"
M.DEFAULT_BPM = 126
M.STATE_NAME = "ClubMusicState" -- Configuration under ReplicatedStorage
M.REMOTE_NAME = "ClubMusicReport" -- RemoteEvent under ReplicatedStorage (client -> server: "fail", trackId)

M.Attr = {
	Owner = "MusicOwner",
	State = "MusicState",
	TrackId = "TrackId",
	Title = "TrackTitle",
	Artist = "TrackArtist",
	Start = "TrackStart",
	Length = "TrackLength",
	Bpm = "TrackBpm",
	Serial = "TrackSerial",
	Next = "NextTrackId",
	Override = "MusicAssetId", -- on the club model (and its ClubRuntime copy): one id or "id1, id2, ..."
}

-- Discovery (server)
M.Search = {
	-- each entry is one SearchAudio request: { keyword } or { artist = "..." }
	Queries = {
		{ artist = "Monstercat" },
		{ keyword = "EDM" },
		{ keyword = "dance" },
		{ keyword = "house" },
		{ keyword = "electro" },
		{ keyword = "club" },
		{ keyword = "party" },
		{ keyword = "festival" },
		{ keyword = "bass" },
		{ artist = "APM Music", keyword = "dance" },
	},
	MaxRequests = 8, -- HTTP budget per discovery run
	RequestGap = 2.5, -- seconds between requests
	MinDuration = 90, -- 1.5 min
	MaxDuration = 360, -- 6 min
	Target = 16, -- validated playlist size aimed for
	MaxProbes = 36, -- server load checks per run
	ProbeTimeout = 10,
	ProbeParallel = 4,
	CacheStore = "ClubOceanMusic_v1",
	CacheKey = "playlist",
	CacheFreshSeconds = 3 * 24 * 3600,
}

M.Play = {
	Lead = 1.5, -- a new track starts this many seconds after it is published (clients load it)
	Crossfade = 2.5, -- the next track is published this long before the current one ends
	MaxVolume = 0.9,
	HearRadius = 120, -- studs from the dance floor where the music is still faintly audible
	ResyncDrift = 0.5,
	LoadTimeout = 12, -- client: a track that has not loaded after this is reported as failed
}

---------------------------------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------------------------------

-- number / "123" / "rbxassetid://123" / "id1, id2 id3" -> { "rbxassetid://123", ... } (deduped)
function M.parseIdList(value: any): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(n: string)
		local id = "rbxassetid://" .. n
		if not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end
	if type(value) == "number" then
		if value > 0 and value == math.floor(value) then
			add(string.format("%d", value))
		end
		return out
	end
	if type(value) ~= "string" then
		return out
	end
	for token in string.gmatch(value, "[^,;%s]+") do
		local n = string.match(token, "^rbxassetid://(%d+)$") or string.match(token, "^(%d+)$")
		if n then
			add(n)
		end
	end
	return out
end

-- asset id (number or string) -> "rbxassetid://n" or nil
function M.soundId(id: any): string?
	local list = M.parseIdList(id)
	return list[1]
end

local BAD_WORDS = {
	"sad", "slow", "calm", "relax", "sleep", "lullaby", "ambient", "meditat", "piano", "acoustic",
	"ballad", "horror", "scary", "creepy", "funeral", "sfx", "sound effect", "ringtone", "jingle",
	"intro only", "christmas", "lofi", "lo-fi", "chill", "orchestral", "cinematic", "classical",
}
local GOOD_WORDS = {
	"dance", "edm", "house", "electro", "club", "party", "bass", "festival", "techno", "trance",
	"dubstep", "drum", "disco", "rave", "upbeat", "energetic", "hype", "drop", "banger", "remix",
	"future", "big room", "anthem", "groove", "night",
}

-- 0 = reject, higher = better fit for a club
function M.scoreTrack(title: any, artist: any, tags: any, duration: any): number
	if type(title) ~= "string" then
		return 0
	end
	local t = string.lower(title)
	if #t < 2 or #t > 90 then
		return 0
	end
	if type(duration) == "number" and (duration < M.Search.MinDuration or duration > M.Search.MaxDuration) then
		return 0
	end
	local hay = t .. " " .. string.lower(type(artist) == "string" and artist or "")
	if type(tags) == "table" then
		for _, tag in tags do
			if type(tag) == "string" then
				hay ..= " " .. string.lower(tag)
			end
		end
	elseif type(tags) == "string" then
		hay ..= " " .. string.lower(tags)
	end
	for _, w in BAD_WORDS do
		if string.find(hay, w, 1, true) then
			return 0
		end
	end
	local s = 1
	for _, w in GOOD_WORDS do
		if string.find(hay, w, 1, true) then
			s += 1
		end
	end
	if string.find(hay, "monstercat", 1, true) then
		s += 1
	end
	return s
end

-- "Title (128 BPM)" -> 128, else 0
function M.bpmFromText(text: any): number
	if type(text) ~= "string" then
		return 0
	end
	local n = tonumber(string.match(string.lower(text), "(%d%d%d?)%s*bpm"))
	if n and n >= 70 and n <= 200 then
		return n
	end
	return 0
end

-- Fisher-Yates in place (rng: Random)
function M.shuffle(list: { any }, rng: Random?)
	local r = rng or Random.new()
	for i = #list, 2, -1 do
		local j = r:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

---------------------------------------------------------------------------------------------------
-- Beat / onset / drop detector (pure; fed with Sound.PlaybackLoudness samples)
---------------------------------------------------------------------------------------------------
-- step(loudness, dt) -> (beat: boolean, intensity: number, isDrop: boolean). Allocation free.
--  * Normalises by a slowly decaying running peak (PlaybackLoudness is 0..~1000, volume dependent).
--  * Onset = fast envelope (30 ms) rising above a slower one (220 ms) by more than an adaptive
--    threshold (running mean + 1.6 x running deviation of that difference), at most every 0.27 s.
--  * Drop = the 1.2 s loudness average jumps well above the quietest level of the previous 12 s,
--    after a real quiet build-up (well under the 8 s average), held for 0.45 s, cooldown 16 s.
local Detector = {}
Detector.__index = Detector

local function ease(dt: number, tau: number): number
	return 1 - math.exp(-dt / tau)
end

function M.newDetector()
	local self = setmetatable({
		t = 0,
		peak = 60,
		fast = 0,
		slow = 0,
		env = 0, -- displayed level
		mid = 0, -- 1.2 s average
		long = 0, -- 8 s average
		quiet = 1, -- quietest mid recently (rises slowly)
		lastQuietT = -1e9,
		dMean = 0,
		dDev = 0.05,
		lastBeatT = -1e9,
		lastDropT = -1e9,
		above = 0, -- seconds the drop condition has held
		armed = false,
		-- tempo: ring of the last 16 inter-onset intervals
		ioi = table.create(16, 0),
		ioiN = 0,
		ioiI = 0,
		sorted = table.create(16, 0),
		bpmEst = 0,
		level = 0,
	}, Detector)
	return self
end

function Detector:step(loudness: number, dt: number): (boolean, number, boolean)
	if dt <= 0 then
		return false, 0, false
	end
	if dt > 0.25 then
		dt = 0.25
	end
	local x = if loudness == loudness and loudness > 0 then loudness else 0
	self.t += dt
	local t = self.t
	-- running peak (decays over ~20 s, floor 60)
	local pk = self.peak * math.exp(-dt / 20)
	if x > pk then
		pk = x
	end
	if pk < 60 then
		pk = 60
	end
	self.peak = pk
	local n = x / pk

	local fast = self.fast + (n - self.fast) * ease(dt, 0.03)
	local slow = self.slow + (n - self.slow) * ease(dt, 0.22)
	self.fast, self.slow = fast, slow
	self.env += (n - self.env) * ease(dt, if n > self.env then 0.04 else 0.18)
	self.level = math.clamp(self.env * 1.15, 0, 1)
	local mid = self.mid + (n - self.mid) * ease(dt, 1.2)
	local long = self.long + (n - self.long) * ease(dt, 8)
	self.mid, self.long = mid, long

	-- onset
	local d = fast - slow
	local dm = self.dMean + (d - self.dMean) * ease(dt, 2)
	local dd = self.dDev + (math.abs(d - dm) - self.dDev) * ease(dt, 2)
	self.dMean, self.dDev = dm, dd
	local thr = dm + 1.6 * dd
	if thr < 0.05 then
		thr = 0.05
	end
	local beat = false
	local intensity = 0
	if d > thr and fast > 0.12 and fast > slow * 1.25 and t - self.lastBeatT >= 0.27 then
		beat = true
		local gap = t - self.lastBeatT
		self.lastBeatT = t
		if gap < 2 then
			self.ioiI = self.ioiI % 16 + 1
			self.ioi[self.ioiI] = gap
			if self.ioiN < 16 then
				self.ioiN += 1
			end
		end
		intensity = math.clamp(0.3 + 0.7 * math.min(1, fast) * math.min(1.5, d / (thr * 2)), 0, 1)
	end

	-- drop
	if mid < self.quiet then
		self.quiet = mid
	else
		self.quiet += (mid - self.quiet) * ease(dt, 12)
	end
	if long > 0.05 and mid < long * 0.6 then
		self.lastQuietT = t
		self.armed = true
	end
	local isDrop = false
	local sinceQuiet = t - self.lastQuietT
	if self.armed and sinceQuiet < 12 and mid > self.quiet + 0.2 and mid > long * 1.05 and t - self.lastDropT > 16 then
		self.above += dt
		if self.above >= 0.45 then
			isDrop = true
			self.lastDropT = t
			self.above = 0
			self.armed = false
			self.quiet = mid
			if not beat then
				beat = true
				intensity = 1
			else
				intensity = 1
			end
		end
	else
		self.above = 0
	end
	return beat, intensity, isDrop
end

-- tempo from the inter-onset intervals: mean of the middle half (robust against the 30 Hz frame
-- quantisation and the odd missed / extra onset), folded into 90..180 BPM (0 = not enough data)
function Detector:tempo(): number
	local n = self.ioiN
	if n < 6 then
		return 0
	end
	local s = self.sorted
	for i = 1, n do
		s[i] = self.ioi[i]
	end
	for i = n + 1, 16 do
		s[i] = math.huge
	end
	table.sort(s)
	local lo, hi = n // 4 + 1, n - n // 4
	local sum = 0
	for i = lo, hi do
		sum += s[i]
	end
	local mean = sum / (hi - lo + 1)
	if mean <= 0 or mean == math.huge then
		return 0
	end
	local bpm = 60 / mean
	while bpm < 90 do
		bpm *= 2
	end
	while bpm > 180 do
		bpm /= 2
	end
	return bpm
end

function Detector:reset()
	self.peak, self.fast, self.slow, self.env, self.level = 60, 0, 0, 0, 0
	self.mid, self.long, self.quiet, self.above, self.armed = 0, 0, 1, 0, false
	self.ioiN, self.ioiI = 0, 0
end

M.Detector = Detector

---------------------------------------------------------------------------------------------------
-- Client signal (pure Luau: no Instance needed)
---------------------------------------------------------------------------------------------------
local function newSignal()
	local sig = { _h = {} :: { (...any) -> () } }
	function sig:Connect(fn: (...any) -> ())
		assert(type(fn) == "function", "Connect expects a function")
		local copy = table.clone(sig._h)
		table.insert(copy, fn)
		sig._h = copy
		local conn = { Connected = true }
		function conn:Disconnect()
			if not conn.Connected then
				return
			end
			conn.Connected = false
			local c = table.clone(sig._h)
			local i = table.find(c, fn)
			if i then
				table.remove(c, i)
			end
			sig._h = c
		end
		return conn
	end
	function sig:_fire(a: any, b: any)
		for _, fn in sig._h do -- snapshot: (dis)connects replace the array
			local ok, err = pcall(fn, a, b)
			if not ok then
				warn("[ClubMusicShared] handler error:", err)
			end
		end
	end
	return sig
end

M.Beat = newSignal()
M.Drop = newSignal()

local live = { level = 0, bpm = M.DEFAULT_BPM, isLive = false, title = nil :: string?, artist = nil :: string? }

function M.level(): number
	return live.level
end
function M.bpm(): number
	return live.bpm
end
function M.isLive(): boolean
	return live.isLive
end
function M.nowPlaying(): (string?, string?)
	return live.title, live.artist
end

-- internal (ClubMusic.client only)
function M._setLevel(level: number, isLive: boolean, bpm: number)
	live.level, live.isLive, live.bpm = level, isLive, bpm
end
function M._setTrack(title: string?, artist: string?)
	live.title, live.artist = title, artist
end
function M._beat(intensity: number, isDrop: boolean)
	M.Beat:_fire(intensity, isDrop)
	if isDrop then
		M.Drop:_fire(intensity)
	end
end

return M
