-- GwangalliDrive/Radio: the car radio ("노래도 나오게"), local only, no uploads.
--   * ONE station for now: "광안 FM — CLUB OCEAN 라이브": it relays the club's music system
--     (ClubMusic.server discovers licensed dance tracks with AssetService:SearchAudioAsync and
--     publishes the playing track on ReplicatedStorage.ClubMusicState: TrackId / TrackStart /
--     TrackSerial / TrackTitle / TrackArtist, see ClubMusicShared). The radio plays the same track
--     in sync (TimePosition from the shared server clock), so the club's playlist is the radio's
--     playlist without a second discovery pass. No music published yet -> "방송 준비 중…" and silence.
--   * a Sound on the car's DriveBase (3D, RollOffMaxDistance 60) with an EqualizerSoundEffect:
--     muffled (highs / mids cut, quieter) while the camera is outside the car (chase / hood), clear in
--     the interior view. Only the local player's car has a radio Sound (other cars: nothing).
--   * Radio.toggle() OFF -> ON -> OFF; the choice survives getting out and into the next car.
-- API: Radio.start(ctx) once; Radio.attach(car, base) / Radio.detach() from Drive; Radio.setInside(bool)
-- from Camera; Radio.toggle() -> on; Radio.isOn(); Radio.nowPlaying() -> title, artist | nil; Radio.changed
-- (BindableEvent.Event: on, title).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Radio = {}

local STATE_NAME = "ClubMusicState"
local ATTR = { State = "MusicState", TrackId = "TrackId", Title = "TrackTitle", Artist = "TrackArtist", Start = "TrackStart", Length = "TrackLength", Serial = "TrackSerial" }
Radio.STATION = "광안 FM · CLUB OCEAN 라이브"

local ctx: any = nil
local on = false -- user preference
local inside = false
local sound: Sound? = nil
local eq: EqualizerSoundEffect? = nil
local car: Model? = nil
local stateInst: Instance? = nil
local stateConn: RBXScriptConnection? = nil
local serialSeen: any = nil
local changedEvent = Instance.new("BindableEvent")
Radio.changed = changedEvent.Event

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(t) == "number" then t else os.clock()
end

local function stateSource(): Instance?
	if stateInst and stateInst.Parent then
		return stateInst
	end
	stateInst = ReplicatedStorage:FindFirstChild(STATE_NAME)
	return stateInst
end

function Radio.nowPlaying(): (string?, string?)
	local src = stateSource()
	if not src then
		return nil, nil
	end
	local id = src:GetAttribute(ATTR.TrackId)
	if type(id) ~= "string" or id == "" or src:GetAttribute(ATTR.State) ~= "playing" then
		return nil, nil
	end
	local title = tostring(src:GetAttribute(ATTR.Title) or "")
	local artist = tostring(src:GetAttribute(ATTR.Artist) or "")
	return if title ~= "" then title else "방송 중", artist
end

local function applyMix()
	if not sound then
		return
	end
	local s = sound :: Sound
	if inside then
		s.Volume = 0.55
		if eq then
			eq.HighGain = 0
			eq.MidGain = 0
			eq.LowGain = 2
		end
	else
		s.Volume = 0.32
		if eq then
			eq.HighGain = -20
			eq.MidGain = -9
			eq.LowGain = 1
		end
	end
end

-- (Re)tunes the Sound to the club's current track, in sync with the shared clock.
local function tune()
	if not sound or not on then
		return
	end
	local s = sound :: Sound
	local src = stateSource()
	local id = src and src:GetAttribute(ATTR.TrackId)
	local state = src and src:GetAttribute(ATTR.State)
	if type(id) ~= "string" or id == "" or state ~= "playing" then
		if s.IsPlaying or s.Playing then
			s:Stop()
		end
		s.SoundId = ""
		return
	end
	local start = src:GetAttribute(ATTR.Start)
	local pos = if type(start) == "number" then math.max(0, serverNow() - start) else 0
	local length = src:GetAttribute(ATTR.Length)
	if type(length) == "number" and length > 1 and pos > length + 2 then
		pos = pos % length
	end
	if s.SoundId ~= id then
		s.SoundId = id
	end
	pcall(function()
		s.TimePosition = pos
	end)
	if not s.Playing then
		s:Play()
	end
end

local function watchState()
	if stateConn then
		stateConn:Disconnect()
		stateConn = nil
	end
	local src = stateSource()
	if not src then
		return
	end
	serialSeen = src:GetAttribute(ATTR.Serial)
	stateConn = src.AttributeChanged:Connect(function(name: string)
		if name == ATTR.Serial or name == ATTR.TrackId or name == ATTR.State then
			local serial = src:GetAttribute(ATTR.Serial)
			if serial ~= serialSeen or name ~= ATTR.Serial then
				serialSeen = serial
				tune()
				local title = Radio.nowPlaying()
				changedEvent:Fire(on, title)
			end
		end
	end)
end

function Radio.start(c: any)
	ctx = c
	task.spawn(function()
		local t0 = os.clock()
		while not stateSource() and os.clock() - t0 < 60 do
			task.wait(1)
		end
		watchState()
	end)
end

function Radio.isOn(): boolean
	return on
end

-- A radio exists only while I sit in `car`; parented to the base so it moves with the car.
function Radio.attach(m: Model, base: BasePart)
	Radio.detach()
	car = m
	local s = Instance.new("Sound")
	s.Name = "GwangalliCarRadio"
	s.Looped = false
	s.Volume = 0
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = 60
	local e = Instance.new("EqualizerSoundEffect")
	e.Name = "Muffle"
	e.HighGain = -20
	e.MidGain = -9
	e.LowGain = 1
	e.Parent = s
	s.Parent = base
	sound, eq = s, e
	applyMix()
	if on then
		tune()
	end
	-- the next track (or the first one published while we sit in the car)
	if not stateConn then
		watchState()
	end
	-- a track that ended before the serial changed (length known): nothing to do, Ended is silent
	s.Ended:Connect(function()
		if on and sound == s then
			task.delay(0.5, tune)
		end
	end)
end

function Radio.detach()
	local s = sound
	if s then
		pcall(function()
			s:Stop()
		end)
		s:Destroy()
	end
	sound, eq, car = nil, nil, nil
end

function Radio.setInside(v: boolean)
	if inside == v then
		return
	end
	inside = v
	applyMix()
end

-- Returns the new state. The HUD text is the caller's (UI) job through Radio.changed.
function Radio.toggle(): boolean
	on = not on
	local s = sound
	if on then
		tune()
	elseif s then
		pcall(function()
			s:Stop()
		end)
	end
	-- the HUD's speedometer line shows the station / track (no toast: it would sit over the buttons)
	local title, artist = Radio.nowPlaying()
	changedEvent:Fire(on, if title then (title .. (if artist and artist ~= "" then " — " .. artist else "")) else nil)
	return on
end

-- Keeps a long-playing station in sync (drift / a late stream of the asset): 1 Hz, cheap.
task.spawn(function()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < 1 then
			return
		end
		acc = 0
		if on and sound and not (sound :: Sound).Playing then
			tune()
		end
	end)
end)

return Radio
