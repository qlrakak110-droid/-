-- GwangalliAmbience/Soundscape (client): spatial ambience by zone with smooth crossfades.
--
-- Loops come from ReplicatedStorage.GwangalliAmbienceState (found and verified by
-- GwangalliAmbience.server; no uploads). Each bed is one looping Sound; spatial beds sit on an
-- Attachment on the Terrain that glides to the right place for the listener (the camera):
--   waves    the nearest point of the coastline (beach waterline, Millak breakwater / terraces,
--            Namcheon sea wall) with that stretch's surf strength: louder near the water, from the
--            sea side
--   gulls    the gull flock around the camera (Birds), else 민락항; quieter at night
--   traffic  the nearest of 광안해변로 / 광남로 / 수영로 / 광안로; a little quieter late at night
--   crowd    만남의 광장 and the busy promenade; busiest in the evening
--   wind     non-spatial, by exposure (near the water, up on the bridge deck) and wind speed
--   club     at night outside CLUB OCEAN 광안: the club's current track (ReplicatedStorage.
--            ClubMusicState, time-synced) through a heavy low-pass, i.e. the bass through the walls,
--            fading out where ClubMusic.client's own door-side sound takes over (~110 studs from the
--            dance floor) and fading in toward the club from ~380 studs
-- Indoors (a ceiling above the camera and the character) everything is ducked and low-passed.
-- A bed whose ids all fail to load (reported to the server once each) stays silent; with no loops
-- at all nothing plays and nothing warns. Volumes: SoundService.GwangalliAmbience (SoundGroup) is
-- the master a settings UI can scale.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")

local Soundscape = {}

local STATE_NAME = "GwangalliAmbienceState"
local REMOTE_NAME = "GwangalliAmbienceReport"
local LOAD_TIMEOUT = 10
local TAU = 1.3 -- crossfade time constant (s)

type Bed = {
	key: string,
	cat: string?,
	spatial: boolean,
	vol: number,
	rollMin: number,
	rollMax: number,
	sound: Sound?,
	att: Attachment?,
	eq: EqualizerSoundEffect?,
	ids: { string },
	idIndex: number,
	loading: boolean,
	dead: boolean,
	current: number,
	target: number,
	pos: Vector3?,
	targetPos: Vector3?,
	silentFor: number,
	playing: boolean,
	loadedId: string?,
}

function Soundscape.start(Env: any)
	local player = Players.LocalPlayer
	local stateObj = ReplicatedStorage:WaitForChild(STATE_NAME, 30)
	local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local D = Env.D

	-- master group + indoor low-pass
	local group = SoundService:FindFirstChild("GwangalliAmbience")
	if not (group and group:IsA("SoundGroup")) then
		group = Instance.new("SoundGroup")
		group.Name = "GwangalliAmbience"
		;(group :: SoundGroup).Volume = 1
		group.Parent = SoundService
	end
	local groupEq = Instance.new("EqualizerSoundEffect")
	groupEq.Name = "IndoorMuffle"
	groupEq.HighGain = 0
	groupEq.MidGain = 0
	groupEq.LowGain = 0
	groupEq.Parent = group

	local beds: { Bed } = {}
	local function bed(key: string, cat: string?, spatial: boolean, vol: number, rollMin: number, rollMax: number): Bed
		local b: Bed = {
			key = key, cat = cat, spatial = spatial, vol = vol, rollMin = rollMin, rollMax = rollMax,
			sound = nil, att = nil, eq = nil, ids = {}, idIndex = 0, loading = false, dead = false,
			current = 0, target = 0, pos = nil, targetPos = nil, silentFor = 0, playing = false, loadedId = nil,
		}
		table.insert(beds, b)
		return b
	end
	local waves = bed("waves", "waves", true, 0.7, 45, 700)
	local gulls = bed("gulls", "gulls", true, 0.42, 30, 420)
	local traffic = bed("traffic", "traffic", true, 0.38, 45, 460)
	local crowd = bed("crowd", "crowd", true, 0.42, 40, 320)
	local wind = bed("wind", "wind", false, 0.24, 0, 0)
	local club = bed("club", nil, true, 0.55, 70, 420)

	local function parse(v: any): { string }
		local out = {}
		if type(v) == "string" then
			for token in string.gmatch(v, "[^,%s]+") do
				if string.match(token, "^rbxassetid://%d+$") then
					table.insert(out, token)
				end
			end
		end
		return out
	end

	local function report(b: Bed, id: string)
		if remote and remote:IsA("RemoteEvent") and b.cat then
			pcall(function()
				(remote :: RemoteEvent):FireServer("fail", b.cat, id)
			end)
		end
	end

	local function ensureSound(b: Bed): Sound
		if b.sound then
			return b.sound :: Sound
		end
		local s = Instance.new("Sound")
		s.Name = "Ambience_" .. b.key
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = group :: SoundGroup
		if b.spatial and terrain then
			local att = Instance.new("Attachment")
			att.Name = "AmbienceEmitter_" .. b.key
			att.CFrame = CFrame.new(Env.focus())
			att.Parent = terrain
			b.att = att
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = b.rollMin
			s.RollOffMaxDistance = b.rollMax
			s.Parent = att
		else
			s.Parent = SoundService
		end
		b.sound = s
		return s
	end

	-- try the bed's ids in order until one loads
	local function load(b: Bed)
		if b.loading or b.dead then
			return
		end
		b.loading = true
		task.spawn(function()
			while b.idIndex < #b.ids do
				b.idIndex += 1
				local id = b.ids[b.idIndex]
				local s = ensureSound(b)
				local ok = pcall(function()
					s.SoundId = id
				end)
				local t0 = os.clock()
				local loaded = false
				while ok and os.clock() - t0 < LOAD_TIMEOUT do
					local okL, isL = pcall(function()
						return s.IsLoaded
					end)
					if okL and isL then
						loaded = true
						break
					end
					task.wait(0.25)
				end
				if loaded then
					b.loadedId = id
					pcall(function()
						local len = s.TimeLength
						if type(len) == "number" and len > 1 then
							s.TimePosition = math.random() * len * 0.9
						end
					end)
					b.loading = false
					return
				end
				report(b, id)
			end
			b.dead = #b.ids > 0
			b.loading = false
		end)
	end

	local function applyState()
		if not stateObj then
			return
		end
		for _, b in beds do
			if b.cat then
				local ids = parse(stateObj:GetAttribute(b.cat))
				local changed = #ids ~= #b.ids
				if not changed then
					for i, id in ids do
						if b.ids[i] ~= id then
							changed = true
							break
						end
					end
				end
				if changed then
					-- keep a working sound if its id is still listed
					local keep = b.loadedId and table.find(ids, b.loadedId)
					b.ids = ids
					if not keep then
						b.idIndex = 0
						b.dead = false
						b.loadedId = nil
						if #ids > 0 then
							load(b)
						end
					else
						b.idIndex = keep :: number
					end
				end
			end
		end
	end
	if stateObj then
		stateObj:GetAttributeChangedSignal("Serial"):Connect(applyState)
		applyState()
	end

	-- club track (ClubMusic) ------------------------------------------------------------------------
	local clubState = ReplicatedStorage:FindFirstChild("ClubMusicState")
	local clubFloor: Vector3? = nil
	local function findClubFloor(): Vector3?
		for _, z in CollectionService:GetTagged("ClubZone") do
			if z:IsA("BasePart") and z:GetAttribute("Zone") == "Main" then
				return z.Position
			end
		end
		return if typeof(D.club) == "Vector3" then D.club else nil
	end
	local clubTrack = ""
	local function syncClub(s: Sound, force: boolean)
		if not clubState then
			return
		end
		local start = clubState:GetAttribute("TrackStart")
		if type(start) ~= "number" then
			return
		end
		local pos = Env.now() - start
		local len = s.TimeLength
		if type(len) == "number" and len > 0 then
			pos = pos % len
		end
		if force or math.abs(s.TimePosition - pos) > 0.6 then
			pcall(function()
				s.TimePosition = math.max(0, pos)
			end)
		end
	end

	-- indoor test (2 Hz) -------------------------------------------------------------------------------
	local indoor = 0
	local indoorTarget = 0
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	local function covered(from: Vector3): boolean
		local hit = workspace:Raycast(from, Vector3.new(0, 70, 0), rayParams)
		return hit ~= nil and hit.Instance ~= nil
	end
	local indoorAcc = 1

	local function roadNearest(px: number, pz: number): (Vector3?, number)
		local best: Vector3? = nil
		local bestScore, bestW = math.huge, 0
		if type(D.roads) ~= "table" then
			return nil, 0
		end
		for _, r in D.roads do
			local w, line = r[1], r[2]
			if type(line) == "table" and #line >= 2 then
				local x, z, d = Env.nearestOn(line, px, pz)
				local sc = d / math.max(0.2, w)
				if sc < bestScore then
					bestScore = sc
					best = Vector3.new(x, 8, z)
					bestW = w
				end
			end
		end
		return best, bestW
	end

	local function crowdNearest(px: number, pz: number): (Vector3?, number)
		local best: Vector3? = nil
		local bestD, bestW = math.huge, 0
		if typeof(D.plaza) == "Vector3" then
			local d = (Vector3.new(px, 0, pz) - Vector3.new(D.plaza.X, 0, D.plaza.Z)).Magnitude - 50
			best, bestD, bestW = D.plaza + Vector3.new(0, 2, 0), d, 1
		end
		if type(D.promenade) == "table" and #D.promenade >= 2 then
			local x, z, d, w = Env.nearestOn(D.promenade, px, pz)
			if d < bestD then
				best, bestD, bestW = Vector3.new(x, Env.WALK + 2, z), d, w
			end
		end
		return best, bestW
	end

	local function crowdTime(): number
		local c = Env.clock()
		if c >= 17 and c < 23.5 then
			return 1.15
		elseif c >= 9 and c < 17 then
			return 1
		elseif c >= 23.5 or c < 2 then
			return 0.7
		end
		return 0.25
	end

	Env.every("sound", 8, function(now: number, dt: number)
		dt = math.min(dt, 1)
		local cam = Env.focus()
		local char = player and player.Character
		-- indoor
		indoorAcc += dt
		if indoorAcc >= 0.5 then
			indoorAcc = 0
			local exclude = { Env.folder }
			if char then
				table.insert(exclude, char)
			end
			rayParams.FilterDescendantsInstances = exclude
			local okA, a = pcall(covered, cam)
			local head = char and char:FindFirstChild("Head")
			local okB, b = true, okA and a
			if head and head:IsA("BasePart") then
				okB, b = pcall(covered, head.Position + Vector3.new(0, 1, 0))
			end
			indoorTarget = if okA and a and okB and b then 1 else 0
		end
		indoor += (indoorTarget - indoor) * math.min(1, dt * 2)
		groupEq.HighGain = -22 * indoor
		groupEq.MidGain = -8 * indoor
		local duck = 1 - 0.7 * indoor
		local night = Env.isNight()
		local day = Env.daylight()

		-- waves
		if type(D.coast) == "table" and #D.coast >= 2 then
			local x, z, d, w = Env.nearestOn(D.coast, cam.X, cam.Z)
			waves.targetPos = Vector3.new(x, 1.5, z)
			waves.target = if d < waves.rollMax * 1.1 then waves.vol * math.clamp(w, 0.2, 1) * duck else 0
		end
		-- gulls
		local gc = Env.gulls and Env.gulls.center
		if gc and (Env.gulls.count or 0) > 0 then
			gulls.targetPos = gc
			gulls.target = gulls.vol * math.clamp(Env.gulls.count / 3, 0.35, 1) * (0.25 + 0.75 * day) * duck
		elseif type(D.gulls) == "table" and type(D.gulls.harbour) == "table" and typeof(D.gulls.harbour.center) == "Vector3" then
			local hc = D.gulls.harbour.center + Vector3.new(0, 20, 0)
			gulls.targetPos = hc
			gulls.target = if (hc - cam).Magnitude < gulls.rollMax then gulls.vol * 0.7 * (0.2 + 0.8 * day) * duck else 0
		else
			gulls.target = 0
		end
		-- traffic
		local rp, rw = roadNearest(cam.X, cam.Z)
		if rp then
			traffic.targetPos = rp
			local late = if Env.hourIn(1, 5.5) then 0.55 elseif night then 0.85 else 1
			traffic.target = if (rp - cam).Magnitude < traffic.rollMax * 1.1 then traffic.vol * math.clamp(rw, 0.3, 1) * late * (0.35 + 0.65 * duck) else 0
		end
		-- crowd
		local cp, cw = crowdNearest(cam.X, cam.Z)
		if cp then
			crowd.targetPos = cp
			crowd.target = if (cp - cam).Magnitude < crowd.rollMax * 1.1 then crowd.vol * math.clamp(cw, 0.2, 1) * crowdTime() * duck else 0
		end
		-- wind: exposure near the water / high up
		do
			local _, _, dCoast = 0, 0, math.huge
			if type(D.coast) == "table" and #D.coast >= 2 then
				_, _, dCoast = Env.nearestOn(D.coast, cam.X, cam.Z)
			end
			local exposure = math.clamp(1 - dCoast / 500, 0, 1) * 0.7 + math.clamp((cam.Y - 30) / 120, 0, 1)
			local speedK = math.clamp(Env.windSpeed / 10, 0.3, 1.6)
			wind.target = wind.vol * math.clamp(0.25 + exposure, 0, 1.3) * speedK * (1 - 0.9 * indoor)
		end
		-- club bass through the walls (night)
		do
			clubFloor = clubFloor or findClubFloor()
			local target = 0
			if clubState and clubFloor and night then
				local stateName = clubState:GetAttribute("MusicState")
				local track = clubState:GetAttribute("TrackId")
				local d = (clubFloor - cam).Magnitude
				if stateName == "playing" and type(track) == "string" and track ~= "" and d < 390 and d > 95 then
					if track ~= clubTrack then
						clubTrack = track
						club.ids = { track }
						club.idIndex = 0
						club.dead = false
						club.loadedId = nil
						load(club)
					end
					local fadeIn = math.clamp((d - 100) / 30, 0, 1)
					local fadeOut = math.clamp((390 - d) / 260, 0, 1)
					target = club.vol * fadeIn * fadeOut * (0.45 + 0.55 * duck)
					club.targetPos = clubFloor + Vector3.new(0, 6, 0)
				end
			end
			club.target = target
			if club.sound and not club.eq then
				local eq = Instance.new("EqualizerSoundEffect")
				eq.HighGain = -48
				eq.MidGain = -24
				eq.LowGain = 4
				eq.Parent = club.sound
				club.eq = eq
			end
		end

		-- apply: crossfade, glide the emitters, start / stop
		local k = 1 - math.exp(-dt / TAU)
		for _, b in beds do
			local ready = b.loadedId ~= nil and b.sound ~= nil
			local target = if ready then b.target else 0
			b.current += (target - b.current) * k
			if b.current < 0.002 and target == 0 then
				b.current = 0
			end
			local s = b.sound
			if s and ready then
				if b.att and b.targetPos then
					local p = b.pos or b.targetPos
					p = p:Lerp(b.targetPos :: Vector3, math.min(1, dt * 2))
					b.pos = p
					b.att.CFrame = CFrame.new(p)
				end
				if b.current > 0.003 then
					b.silentFor = 0
					if not b.playing then
						b.playing = true
						pcall(function()
							if b == club then
								syncClub(s, true)
							end
							s:Play()
						end)
					elseif b == club then
						syncClub(s, false)
					end
				else
					b.silentFor += dt
					if b.playing and b.silentFor > 3 then
						b.playing = false
						pcall(function()
							s:Stop()
						end)
					end
				end
				local v = math.floor(b.current * 1000 + 0.5) / 1000
				if math.abs(s.Volume - v) > 0.002 then
					s.Volume = v
				end
			end
		end
	end)
end

return Soundscape
