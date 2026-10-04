-- ClubMusic (client): plays the server's club track in sync, feeds ClubMusicShared's beat signal and
-- shows a small "Now Playing" widget while the player is in CLUB OCEAN 광안.
--  * Track = attributes of ReplicatedStorage.ClubMusicState (written by ClubMusic.server; the same
--    values are on the ClubRuntime model). Playback position = GetServerTimeNow() - TrackStart,
--    re-synced when it drifts by more than Play.ResyncDrift; a new track crossfades with the old one.
--  * Audible only in the ClubZone boxes (persistent, under ClubRuntime) or within Play.HearRadius of
--    the dance floor: full on the main floor (Muffle 0), quieter + low-passed in the rooms with a
--    Muffle attribute (lobby 0.55, restrooms 0.8, ...), faint and heavily muffled outside near the
--    door. Elsewhere the Sound is stopped and destroyed after a few seconds (nothing streams).
--  * Beat signal: Sound.PlaybackLoudness -> ClubMusicShared detector (30 Hz on low-tier / touch
--    devices, 60 Hz otherwise, 10 Hz when far away) -> ClubMusicShared.Beat / Drop / level().
--    Without audible music the beats come from the 126 BPM clock aligned to ShowEpoch (the same clock
--    ClubLights runs), with drops on the first beat of the show's drop sections.
--  * A track that does not load within Play.LoadTimeout is reported to the server once (it skips
--    tracks that fail for players) and the beat falls back to the clock.
-- Nothing here drives lights or NPCs; ClubLights / the crowd subscribe to ClubMusicShared.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local mod = ReplicatedStorage:WaitForChild("ClubMusicShared", 60)
if not mod then
	warn("[ClubMusic] ReplicatedStorage.ClubMusicShared missing")
	return
end
local okM, S = pcall(require, mod)
if not okM or type(S) ~= "table" then
	warn("[ClubMusic] ClubMusicShared failed to load:", S)
	return
end
local A = S.Attr
local PLAY = S.Play

local ClubShared: any = nil
do
	local m = ReplicatedStorage:FindFirstChild("ClubShared")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			ClubShared = res
		end
	end
end
local TAG_ZONE = (ClubShared and ClubShared.Tags and ClubShared.Tags.Zone) or "ClubZone"
local TAG_RUNTIME = (ClubShared and ClubShared.Tags and ClubShared.Tags.Runtime) or "ClubRuntime"
local BPM = (ClubShared and ClubShared.BPM) or S.DEFAULT_BPM

-- sampling rate: low tier / touch-only devices sample loudness at 30 Hz
local lowTier = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
do
	local q = ReplicatedStorage:FindFirstChild("GwangalliQuality")
	if q and q:IsA("ModuleScript") then
		local ok, Quality = pcall(require, q)
		if ok and type(Quality) == "table" and type(Quality.get) == "function" then
			local okT, t = pcall(Quality.get)
			if okT and type(t) == "string" then
				lowTier = t == "low"
			end
		end
	end
end
local ACTIVE_HZ = if lowTier then 30 else 60
local IDLE_HZ = 10

---------------------------------------------------------------------------------------------------
-- Zones (persistent ClubZone boxes) + epoch
---------------------------------------------------------------------------------------------------
local zones: { [BasePart]: boolean } = {}
local runtimes: { [Instance]: boolean } = {}
local function watch(tag: string, set: { [any]: boolean }, filter: (Instance) -> boolean)
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		if filter(inst) then
			set[inst] = true
		end
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		set[inst] = nil
	end)
	for _, inst in CollectionService:GetTagged(tag) do
		if filter(inst) then
			set[inst] = true
		end
	end
end
watch(TAG_ZONE, zones, function(i)
	return i:IsA("BasePart")
end)
watch(TAG_RUNTIME, runtimes, function()
	return true
end)

local function attrNum(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	return if type(v) == "number" and v == v then v else default
end

local function epoch(): number
	for rt in runtimes do
		local e = rt:GetAttribute("ShowEpoch")
		if type(e) == "number" and e == e then
			return e
		end
	end
	return 0
end

-- -> zoneName ("" outside), muffle 0..1, distance to the dance floor (math.huge if unknown)
local function listen(): (string, number, number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local pos: Vector3? = nil
	if root and root:IsA("BasePart") then
		pos = root.Position
	else
		local cam = workspace.CurrentCamera
		pos = cam and cam.CFrame.Position
	end
	if not pos then
		return "", 1, math.huge
	end
	local best: BasePart? = nil
	local bestPri = -math.huge
	local floorDist = math.huge
	for z in zones do
		if z.Parent then
			local lp = z.CFrame:PointToObjectSpace(pos)
			local h = z.Size * 0.5
			if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
				local pri = attrNum(z, "Priority", 0)
				if pri > bestPri then
					best, bestPri = z, pri
				end
			end
			if z:GetAttribute("Zone") == "Main" then
				local d = (z.Position - pos).Magnitude
				if d < floorDist then
					floorDist = d
				end
			end
		end
	end
	if not best then
		return "", 1, floorDist
	end
	local name = best:GetAttribute("Zone")
	return if type(name) == "string" then name else "Main", math.clamp(attrNum(best, "Muffle", 0), 0, 1), floorDist
end

---------------------------------------------------------------------------------------------------
-- Track state
---------------------------------------------------------------------------------------------------
local stateObj = ReplicatedStorage:FindFirstChild(S.STATE_NAME)
local track = { id = "", title = "", artist = "", start = 0, len = 0, bpm = 0, serial = -1 }
local trackDirty = false

local function readTrack()
	local src: Instance? = stateObj
	if not src then
		for rt in runtimes do
			if rt:GetAttribute(A.Owner) == S.OWNER then
				src = rt
				break
			end
		end
	end
	if not src then
		return
	end
	local id = src:GetAttribute(A.TrackId)
	local serial = attrNum(src, A.Serial, 0)
	local sid = if type(id) == "string" then id else ""
	if sid ~= track.id or serial ~= track.serial then
		trackDirty = true
	end
	track.id = sid
	track.serial = serial
	track.title = tostring(src:GetAttribute(A.Title) or "")
	track.artist = tostring(src:GetAttribute(A.Artist) or "")
	track.start = attrNum(src, A.Start, 0)
	track.len = attrNum(src, A.Length, 0)
	track.bpm = attrNum(src, A.Bpm, 0)
end

local function hookState(obj: Instance)
	obj.AttributeChanged:Connect(function(name)
		if name == A.TrackId or name == A.Serial or name == A.Start or name == A.Title then
			readTrack()
		end
	end)
	readTrack()
end
if stateObj then
	hookState(stateObj)
else
	task.spawn(function()
		local o = ReplicatedStorage:WaitForChild(S.STATE_NAME, 120)
		if o then
			stateObj = o
			hookState(o)
		end
	end)
end

local remote: RemoteEvent? = nil
local function report(id: string)
	if not remote then
		local r = ReplicatedStorage:FindFirstChild(S.REMOTE_NAME)
		if r and r:IsA("RemoteEvent") then
			remote = r
		end
	end
	if remote then
		pcall(function()
			(remote :: RemoteEvent):FireServer("fail", id)
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- Playback
---------------------------------------------------------------------------------------------------
type Voice = {
	sound: Sound,
	eq: EqualizerSoundEffect,
	id: string,
	serial: number,
	created: number,
	started: boolean,
	failed: boolean,
	vol: number,
	fadeOut: boolean,
}
local voice: Voice? = nil
local fading: { Voice } = {}
local reported: { [string]: boolean } = {}
local muted = false
local targetVol = 0 -- zone volume (before mute)
local eqMuffle = 1
local silentSince = 0

local function newVoice(): Voice?
	if track.id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = "ClubOceanTrack"
	s.Looped = false
	s.Volume = 0
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain = 2
	eq.MidGain = 0
	eq.HighGain = 0
	eq.Parent = s
	local ok = pcall(function()
		s.SoundId = track.id
		s.Parent = SoundService
	end)
	if not ok then
		s:Destroy()
		return nil
	end
	return {
		sound = s,
		eq = eq,
		id = track.id,
		serial = track.serial,
		created = os.clock(),
		started = false,
		failed = false,
		vol = 0,
		fadeOut = false,
	}
end

local function dropVoice(v: Voice, fade: boolean)
	if fade and v.started then
		v.fadeOut = true
		table.insert(fading, v)
	else
		pcall(function()
			v.sound:Stop()
		end)
		v.sound:Destroy()
	end
end

local function trackPos(): number
	return workspace:GetServerTimeNow() - track.start
end

-- 4 Hz housekeeping: create / start / resync / fail / release
local resyncClock = 0
local function manageVoice(dt: number)
	if trackDirty then
		trackDirty = false
		if voice and voice.serial ~= track.serial then
			dropVoice(voice, true)
			voice = nil
		end
	end
	local wanted = targetVol > 0.005 and track.id ~= "" and not reported[track.id]
	if wanted then
		silentSince = 0
		if not voice then
			voice = newVoice()
		end
	elseif voice then
		silentSince += dt
		if silentSince > 4 or track.id == "" then
			dropVoice(voice, false)
			voice = nil
		end
	end
	local v = voice
	if not v or v.failed then
		return
	end
	local s = v.sound
	if not v.started then
		local ok, loaded = pcall(function()
			return s.IsLoaded
		end)
		if ok and loaded then
			local pos = trackPos()
			if pos >= 0 and (track.len <= 0 or pos < track.len) then
				pcall(function()
					if s.TimeLength > 0 and pos < s.TimeLength then
						s.TimePosition = pos
					end
					s:Play()
				end)
				v.started = true
				resyncClock = 0
			end
		elseif os.clock() - v.created > PLAY.LoadTimeout then
			v.failed = true
			if not reported[v.id] then
				reported[v.id] = true
				report(v.id)
			end
		end
		return
	end
	resyncClock += dt
	if resyncClock >= 1 then
		resyncClock = 0
		pcall(function()
			local want = trackPos()
			if s.TimeLength > 0 and want < s.TimeLength then
				if math.abs(s.TimePosition - want) > PLAY.ResyncDrift then
					s.TimePosition = want
				end
				if not s.IsPlaying then
					s:Play()
				end
			end
		end)
	end
end

-- per sample: volumes + EQ (writes only when changed)
local function applyVoice(v: Voice, target: number, dt: number)
	local k = math.clamp(dt * (if v.fadeOut then 1 / PLAY.Crossfade * 2.3 else 3), 0, 1)
	v.vol += (target - v.vol) * k
	local s = v.sound
	if math.abs(s.Volume - v.vol) > 0.004 then
		s.Volume = v.vol
	end
	local hg = -40 * eqMuffle
	if math.abs(v.eq.HighGain - hg) > 0.5 then
		v.eq.HighGain = hg
		v.eq.MidGain = -16 * eqMuffle
		v.eq.LowGain = 2 - 3 * eqMuffle
	end
end

---------------------------------------------------------------------------------------------------
-- Beat detection / fallback clock
---------------------------------------------------------------------------------------------------
local det = S.newDetector()
local lastLoudT = -1e9
local fbBeat = -1
local clockOut = {}
local liveBpm = BPM

local function sampleBeat(dt: number)
	local now = os.clock()
	local v = voice
	local live = false
	if v and v.started and not v.failed and v.vol > 0.01 then
		local okL, loud = pcall(function()
			return v.sound.PlaybackLoudness
		end)
		if okL and type(loud) == "number" and loud > 1 then
			lastLoudT = now
		end
		if now - lastLoudT < 1.5 then
			live = true
			local beat, intensity, isDrop = det:step(if okL and type(loud) == "number" then loud else 0, dt)
			local tb = det:tempo()
			if tb > 0 then
				liveBpm = tb
			elseif track.bpm > 0 then
				liveBpm = track.bpm
			end
			S._setLevel(det.level, true, liveBpm)
			if beat then
				S._beat(intensity, isDrop)
			end
		end
	end
	if not live then
		local serverNow = workspace:GetServerTimeNow()
		local ep = epoch()
		local beatF = (serverNow - ep) * BPM / 60
		local b = math.floor(beatF)
		local frac = beatF - b
		S._setLevel(0.2 + 0.6 * math.exp(-frac * 5), false, BPM)
		if b ~= fbBeat then
			local first = fbBeat < 0
			fbBeat = b
			if not first then
				local energy, isDrop = 0.7, false
				if ClubShared and type(ClubShared.clock) == "function" then
					local ok = pcall(ClubShared.clock, serverNow, ep, BPM, clockOut)
					local sec = ok and clockOut.section
					if type(sec) == "table" then
						energy = tonumber(sec.energy) or 0.7
						isDrop = sec.name == "drop" and clockOut.barInSection == 0 and clockOut.beatInBar < 1
					end
				end
				local accent = if b % 4 == 0 then 1 else 0.75
				S._beat(math.clamp((0.35 + 0.65 * energy) * accent, 0, 1), isDrop)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Now Playing widget: GwangalliUI kit styling (dark glass, hairline, cyan / magenta accents) in the
-- GwangalliLayout "bottomCenter" slot (between the thumbstick zone and the jump button on landscape
-- phones). Album tile with equaliser bars, title marquee (scrolls when the title is too long),
-- artist line ("♪ NOW PLAYING" for a few seconds after a new track), 44 px mute button.
-- Built once on first use; hidden while another full-screen UI (phone, bowling, travel sheet) carries
-- HideGwangalliHUD. Styling / placement only: the playback / beat logic above is unchanged.
---------------------------------------------------------------------------------------------------
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local function optional(name: string): any
	local m = ReplicatedStorage:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
	end
	return nil
end
local UIK: any = optional("GwangalliUI")
local LayoutM: any = optional("GwangalliLayout")

local COL = {
	glass = Color3.fromRGB(20, 22, 30),
	card = Color3.fromRGB(30, 32, 42),
	card2 = Color3.fromRGB(44, 47, 60),
	line = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(246, 247, 251),
	sub = Color3.fromRGB(170, 176, 192),
	accent = Color3.fromRGB(61, 214, 245), -- cyan (Gwangan bridge)
	accent2 = Color3.fromRGB(255, 79, 163), -- magenta
}
local FONT_BOLD = Enum.Font.BuilderSansBold
local FONT_HEAVY = Enum.Font.BuilderSansExtraBold
local FONT_REG = Enum.Font.BuilderSansMedium
if UIK then
	pcall(function()
		local c = UIK.Color or {}
		COL.glass = c.glass or COL.glass
		COL.card = c.card or COL.card
		COL.card2 = c.card2 or COL.card2
		COL.line = c.line or COL.line
		COL.text = c.text or COL.text
		COL.sub = c.sub or COL.sub
		COL.accent = c.cyan or COL.accent
		COL.accent2 = c.magenta or COL.accent2
		local f = UIK.Font or {}
		FONT_BOLD = f.bold or FONT_BOLD
		FONT_HEAVY = f.heavy or FONT_HEAVY
		FONT_REG = f.medium or f.regular or FONT_REG
	end)
end

-- Motion policy (docs/ui_kit_requests.md #1): phones default to the "low" graphics tier, but UI tweens
-- are cheap; motion is reduced only for the player's setting, a low graphics slider or low fps.
local motionCache, motionAt = false, -math.huge
local function motionReduced(): boolean
	local now = os.clock()
	if now - motionAt < 1 then
		return motionCache
	end
	motionAt = now
	local r = false
	-- the kit's own policy once it has the fixed K.reduced (it ships with K.spring): one rule for
	-- every screen in the game
	if UIK and type(UIK.spring) == "function" and type(UIK.reduced) == "function" then
		local okK, red = pcall(UIK.reduced)
		if okK then
			motionCache = red == true
			return motionCache
		end
	end
	if UIK and type(UIK.settings) == "table" and UIK.settings.reducedMotion == true then
		r = true
	else
		local q = optional("GwangalliQuality")
		if q and type(q.isLow) == "function" and q.isLow() == true then
			local why = if type(q.reason) == "function" then string.lower(tostring(q.reason())) else ""
			r = string.find(why, "frame", 1, true) ~= nil or string.find(why, "slider", 1, true) ~= nil or string.find(why, "chosen", 1, true) ~= nil
		end
	end
	motionCache = r
	return r
end

local function tween(inst: Instance, t: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween?
	if motionReduced() or t <= 0 then
		for k, v in goals do
			pcall(function()
				(inst :: any)[k] = v
			end)
		end
		return nil
	end
	local ok, tw = pcall(function()
		local x = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goals)
		x:Play()
		return x
	end)
	return if ok then tw else nil
end
local springSerial: { [Instance]: number } = {}
local function spring(inst: Instance, t: number, past: { [string]: any }, goals: { [string]: any })
	local n = (springSerial[inst] or 0) + 1
	springSerial[inst] = n
	local first = tween(inst, t * 0.7, past)
	if not first then
		tween(inst, 0, goals)
		return
	end
	first.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and springSerial[inst] == n then
			tween(inst, t * 0.45, goals, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	end)
end

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local function corner(inst: Instance, r: any)
	new("UICorner", { CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, r) }, inst)
end
local function hairline(inst: Instance, color: Color3?, transparency: number?): UIStroke
	return new("UIStroke", { Color = color or COL.line, Transparency = transparency or 0.88, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inst)
end
local function textWidth(str: string, size: number): number
	local w = 0
	for _, cp in utf8.codes(str) do
		if cp >= 0x1F000 or (cp >= 0x2600 and cp < 0x2800) then
			w += 1.25
		elseif cp >= 0x1100 then
			w += 0.95
		elseif cp == 32 then
			w += 0.3
		else
			w += 0.62 -- a little wide: a title that just fits is better scrolled than cut
		end
	end
	return math.ceil(w * size)
end

local BARS = 5
local BAR_MAX = 24
local ui: any = nil
local uiVisible = false
local toastUntil = 0
local lastSerialShown = -1
local hiddenByOther = false
local marqueeSerial = 0

local function buildUI()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local old = pg:FindFirstChild("ClubMusicHUD")
	if old then
		old:Destroy()
	end
	local g = new("ScreenGui", { Name = "ClubMusicHUD", ResetOnSpawn = false, DisplayOrder = 7, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false, IgnoreGuiInset = false })
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	local probe = new("Frame", { Name = "AreaProbe", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Active = false }, g)
	local f = new("Frame", {
		Name = "NowPlaying",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(320, 56),
		BackgroundColor3 = COL.glass,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Active = true,
		ClipsDescendants = true,
	}, g)
	corner(f, 18)
	local st = hairline(f, COL.line, 0.86)
	local scale = new("UIScale", { Scale = 1 }, f)
	-- album tile: the Gwangan bridge gradient (cyan -> violet -> magenta) with a mirrored equaliser
	local art = new("Frame", { Name = "Art", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 7, 0.5, 0), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, f)
	corner(art, 12)
	new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 170, 220)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(110, 80, 220)), ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 60, 150)) }), Rotation = 125 }, art)
	new("Frame", { Name = "Gloss", Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88, BorderSizePixel = 0 }, art)
	local bars, barH = {}, {}
	for i = 1, BARS do
		local b = new("Frame", {
			Name = "Bar" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 9 + (i - 1) * 6, 0.5, 0),
			Size = UDim2.fromOffset(3, 4),
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.05,
		}, art)
		corner(b, UDim.new(0.5, 0))
		bars[i], barH[i] = b, 4
	end
	-- title marquee + artist
	local clip = new("Frame", { Name = "TitleClip", Position = UDim2.fromOffset(58, 9), Size = UDim2.new(1, -58 - 56, 0, 20), BackgroundTransparency = 1, ClipsDescendants = true }, f)
	local title = new("TextLabel", { Name = "Title", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT_HEAVY, TextSize = 15, TextColor3 = COL.text, TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, clip)
	local artist = new("TextLabel", { Name = "Artist", Position = UDim2.fromOffset(58, 30), Size = UDim2.new(1, -58 - 56, 0, 16), BackgroundTransparency = 1, Font = FONT_REG, TextSize = 12, TextColor3 = COL.sub, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "" }, f)
	-- track progress: a 2 px line along the bottom edge, filled by one linear tween per track
	local track = new("Frame", { Name = "Progress", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -3), Size = UDim2.new(1, -36, 0, 2), BackgroundColor3 = COL.line, BackgroundTransparency = 0.9, BorderSizePixel = 0 }, f)
	corner(track, UDim.new(0.5, 0))
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, track)
	corner(fill, UDim.new(0.5, 0))
	new("UIGradient", { Color = ColorSequence.new(COL.accent, COL.accent2) }, fill)
	-- 44 px mute button with a drawn speaker (body + cone + two sound arcs; a slash when muted)
	local mute = new("TextButton", {
		Name = "Mute",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = COL.card2,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, f)
	corner(mute, UDim.new(0.5, 0))
	hairline(mute, nil, 0.9)
	local icon = new("Frame", { Name = "Speaker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 18), BackgroundTransparency = 1 }, mute)
	new("Frame", { Name = "Body", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(5, 7), BackgroundColor3 = COL.text, BorderSizePixel = 0 }, icon)
	local cone = new("Frame", { Name = "Cone", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 5, 0.5, 0), Size = UDim2.fromOffset(9, 9), Rotation = 45, BackgroundColor3 = COL.text, BorderSizePixel = 0 }, icon)
	corner(cone, 2)
	local waves = {}
	for i, d in { 10, 16 } do
		local clipW = new("Frame", { Name = "Wave" .. i, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(d / 2 + 1, d + 2), BackgroundTransparency = 1, ClipsDescendants = true }, icon)
		local arc = new("Frame", { Name = "Arc", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1 }, clipW)
		corner(arc, UDim.new(0.5, 0))
		new("UIStroke", { Color = COL.text, Thickness = 1.6, Transparency = 0 }, arc)
		waves[i] = clipW
	end
	local slash = new("Frame", { Name = "Slash", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(2, 24), Rotation = -45, BackgroundColor3 = Color3.fromRGB(255, 110, 120), BorderSizePixel = 0, Visible = false }, mute)
	corner(slash, UDim.new(0.5, 0))
	local muteScale = new("UIScale", { Scale = 1 }, mute)
	mute.MouseButton1Down:Connect(function()
		tween(muteScale, 0.08, { Scale = 0.9 }, Enum.EasingStyle.Quad)
	end)
	local function up()
		spring(muteScale, 0.3, { Scale = 1.05 }, { Scale = 1 })
	end
	mute.MouseButton1Up:Connect(up)
	mute.MouseLeave:Connect(up)
	mute.Activated:Connect(function()
		muted = not muted
		slash.Visible = muted
		for _, w in waves do
			w.Visible = not muted
		end
		mute.BackgroundColor3 = if muted then Color3.fromRGB(70, 28, 36) else COL.card2
		if UIK and type(UIK.feedback) == "function" then
			pcall(UIK.feedback, "toggle")
		end
	end)
	g.Parent = pg
	return { gui = g, probe = probe, frame = f, scale = scale, bars = bars, barH = barH, clip = clip, title = title, artist = artist, mute = mute, stroke = st, target = UDim2.new(), fill = fill, fillTween = nil :: Tween? }
end

-- bottomCenter slot: GwangalliLayout when present, else the same rule locally (between the
-- thumbstick zone and the jump button on landscape touch screens, above the thumbstick zone in
-- portrait, bottom centre on PC)
local function slotRect(): (number, number, number, number)
	if LayoutM and type(LayoutM.rect) == "function" then
		pcall(function()
			if type(LayoutM.refresh) == "function" then
				LayoutM.refresh()
			end
		end)
		local ok, r = pcall(LayoutM.rect, "bottomCenter")
		if ok and type(r) == "table" and type(r.w) == "number" and r.w > 100 then
			return r.x, r.y, r.w, r.h
		end
	end
	local area = ui.probe.AbsoluteSize
	if area.X < 100 then
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		area = Vector2.new(vp.X, vp.Y - 58)
	end
	local W, H = area.X, area.Y
	local ox = math.max(0, ui.probe.AbsolutePosition.X)
	local top = 58
	pcall(function()
		top = GuiService:GetGuiInset().Y
	end)
	local touch = UserInputService.TouchEnabled
	if not touch then
		return W / 2 - 180, H - 16 - 60, 360, 60
	end
	local sw, sh = W + 2 * ox, H + top
	local small = math.min(sw, sh) <= 500
	local jx = W - (if small then 95 else 170)
	local thumbRight = sw * 0.4 - ox
	if W >= H then
		local left, right = thumbRight + 8, jx - 12
		local w = math.min(360, right - left)
		return left + (right - left - w) / 2, H - 8 - 60, w, 60
	end
	local thumbTop = sh * 0.4 - top
	local w = math.min(340, W - 16)
	return W / 2 - w / 2, thumbTop - 8 - 60, w, 60
end

local function layoutUI()
	if not ui then
		return
	end
	local x, y, w, h = slotRect()
	local hh = math.clamp(h, 52, 64)
	local k = hh / 56
	ui.scale.Scale = k
	local ww = math.min(w, 360 * k)
	ui.frame.Size = UDim2.fromOffset(math.floor(ww / k), 56)
	ui.target = UDim2.fromOffset(math.floor(x + w / 2), math.floor(y + h))
	ui.frame.Position = ui.target
end

-- title marquee: scrolls a too-long title left, pauses, jumps back (tweens only; stops when hidden)
local function startMarquee()
	if not ui then
		return
	end
	marqueeSerial += 1
	local mine = marqueeSerial
	local title, clip = ui.title, ui.clip
	title.Position = UDim2.new()
	task.defer(function()
		-- the clip's width from the layout (its AbsoluteSize may still be stale right after Enabled)
		local clipW = ui.frame.Size.X.Offset - 58 - 56
		local textW = math.max(title.TextBounds.X, textWidth(title.Text, 15))
		if clipW < 20 or textW <= clipW then
			title.Size = UDim2.fromScale(1, 1)
			return
		end
		title.Size = UDim2.new(0, textW + 4, 1, 0)
		local dist = textW - clipW + 12
		while marqueeSerial == mine and uiVisible do
			task.wait(1.8)
			if marqueeSerial ~= mine or not uiVisible then
				break
			end
			tween(title, dist / 30, { Position = UDim2.fromOffset(-dist, 0) }, Enum.EasingStyle.Linear)
			task.wait(dist / 30 + 1.2)
			if marqueeSerial ~= mine then
				break
			end
			-- soft wrap-around: fade out, jump back, fade in (no hard cut)
			tween(title, 0.22, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
			task.wait(0.24)
			if marqueeSerial ~= mine then
				title.TextTransparency = 0
				break
			end
			title.Position = UDim2.new()
			tween(title, 0.3, { TextTransparency = 0 }, Enum.EasingStyle.Quad)
		end
		title.TextTransparency = 0
	end)
end

local watchedGuis: { [Instance]: { RBXScriptConnection } } = {}
local function refreshHidden()
	local hide = false
	for g in watchedGuis do
		if g.Parent and (g :: ScreenGui).Enabled and g:GetAttribute("HideGwangalliHUD") == true then
			hide = true
			break
		end
	end
	hiddenByOther = hide
end
local function watchGui(g: Instance)
	if not g:IsA("ScreenGui") or g.Name == "ClubMusicHUD" or watchedGuis[g] then
		return
	end
	watchedGuis[g] = {
		g:GetPropertyChangedSignal("Enabled"):Connect(refreshHidden),
		g:GetAttributeChangedSignal("HideGwangalliHUD"):Connect(refreshHidden),
	}
	refreshHidden()
end
task.spawn(function()
	local pg = player:WaitForChild("PlayerGui", 30)
	if not pg then
		return
	end
	pg.ChildAdded:Connect(watchGui)
	pg.ChildRemoved:Connect(function(g)
		local conns = watchedGuis[g]
		if conns then
			for _, c in conns do
				c:Disconnect()
			end
			watchedGuis[g] = nil
			refreshHidden()
		end
	end)
	for _, g in pg:GetChildren() do
		watchGui(g)
	end
end)

-- track progress line: one linear tween from the current position to the end of the track
local function startProgress()
	if not ui then
		return
	end
	if ui.fillTween then
		ui.fillTween:Cancel()
		ui.fillTween = nil
	end
	local len = tonumber(track.len) or 0
	local bar = ui.fill.Parent
	if len <= 0 or not track.start or track.start <= 0 then
		bar.Visible = false
		return
	end
	bar.Visible = true
	local elapsed = math.clamp(workspace:GetServerTimeNow() - track.start, 0, len)
	ui.fill.Size = UDim2.fromScale(elapsed / len, 1)
	local remaining = len - elapsed
	if remaining > 0.2 then
		local ok, t = pcall(function()
			local x = TweenService:Create(ui.fill, TweenInfo.new(remaining, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
			x:Play()
			return x
		end)
		if ok then
			ui.fillTween = t
		end
	end
end

local barPhase = table.create(BARS, 0)
local function updateUI(show: boolean, dt: number)
	show = show and not hiddenByOther
	if show and not ui then
		ui = buildUI()
		if ui then
			layoutUI()
			local cam = workspace.CurrentCamera
			if cam then
				cam:GetPropertyChangedSignal("ViewportSize"):Connect(layoutUI)
			end
			ui.probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutUI)
			if LayoutM and typeof(LayoutM.changed) == "RBXScriptSignal" then
				LayoutM.changed:Connect(layoutUI)
			end
		end
	end
	if not ui then
		return
	end
	if show ~= uiVisible then
		uiVisible = show
		ui.gui.Enabled = show
		if show then
			layoutUI()
			toastUntil = os.clock() + 4
			-- rise in with a small overshoot, then settle
			ui.frame.Position = ui.target + UDim2.fromOffset(0, 28)
			spring(ui.frame, 0.42, { Position = ui.target - UDim2.fromOffset(0, 4) }, { Position = ui.target })
			startMarquee()
			startProgress()
		else
			marqueeSerial += 1
			if ui.fillTween then
				ui.fillTween:Cancel()
				ui.fillTween = nil
			end
		end
	end
	if not show then
		return
	end
	if track.serial ~= lastSerialShown then
		lastSerialShown = track.serial
		ui.title.Text = if track.title ~= "" then track.title else "CLUB OCEAN 광안"
		toastUntil = os.clock() + 4
		startMarquee()
		startProgress()
	end
	local toasting = os.clock() < toastUntil
	local artistW = ui.frame.Size.X.Offset - 58 - 56
	local artistText
	if toasting then
		artistText = "♪ 지금 재생 중"
		for _, v in { "♪ NOW PLAYING · 지금 재생 중", "♪ NOW PLAYING" } do
			if textWidth(v, 12) <= artistW then
				artistText = v
				break
			end
		end
	else
		artistText = if track.artist ~= "" then track.artist else "CLUB OCEAN 광안"
	end
	if ui.artist.Text ~= artistText then
		ui.artist.Text = artistText
		ui.artist.TextColor3 = if toasting then COL.accent else COL.sub
	end
	local lv = if muted then 0.15 else S.level()
	for i = 1, BARS do
		barPhase[i] += dt * (5 + i * 1.7)
		-- mirrored bars (centred on the tile), the middle ones a little taller
		local shape = 0.7 + 0.3 * (1 - math.abs(i - (BARS + 1) / 2) / ((BARS - 1) / 2))
		local h = math.floor(4 + (BAR_MAX - 4) * shape * math.clamp(lv * (0.55 + 0.45 * math.abs(math.sin(barPhase[i]))), 0, 1))
		if h ~= ui.barH[i] then
			ui.barH[i] = h
			ui.bars[i].Size = UDim2.fromOffset(3, h)
		end
	end
	local sc = if toasting then COL.accent else COL.line
	local stT = if toasting then 0.5 else 0.86
	if ui.stroke.Transparency ~= stT then
		ui.stroke.Color = sc
		ui.stroke.Transparency = stT
	end
end

---------------------------------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------------------------------
local zoneClock = 1
local manageClock = 1
local acc = 0
local inClub = false

RunService.Heartbeat:Connect(function(frameDt)
	acc += frameDt
	local hz = if inClub then ACTIVE_HZ else IDLE_HZ
	if acc < 1 / hz - 0.002 then
		return
	end
	local dt = math.min(acc, 0.25)
	acc = 0

	zoneClock += dt
	if zoneClock >= 0.25 then
		zoneClock = 0
		local name, muffle, floorDist = listen()
		if name ~= "" and name ~= "Near" then
			targetVol = PLAY.MaxVolume * (1 - 0.6 * muffle)
			eqMuffle = muffle
			inClub = true
		elseif floorDist <= PLAY.HearRadius or name == "Near" then
			local k = if floorDist < math.huge then math.clamp(1 - floorDist / PLAY.HearRadius, 0, 1) else 0.3
			targetVol = PLAY.MaxVolume * (0.06 + 0.16 * k)
			eqMuffle = 1
			inClub = floorDist <= PLAY.HearRadius
		else
			targetVol = 0
			eqMuffle = 1
			inClub = false
		end
	end

	manageClock += dt
	if manageClock >= 0.25 then
		local mdt = manageClock
		manageClock = 0
		manageVoice(mdt)
	end

	local v = voice
	if v then
		applyVoice(v, if muted then 0 else targetVol, dt)
	end
	for i = #fading, 1, -1 do
		local fv = fading[i]
		applyVoice(fv, 0, dt)
		if fv.vol < 0.01 then
			table.remove(fading, i)
			pcall(function()
				fv.sound:Stop()
			end)
			fv.sound:Destroy()
		end
	end

	sampleBeat(dt)

	local playing = v ~= nil and v.started and not v.failed
	S._setTrack(if playing then track.title else nil, if playing then track.artist else nil)
	updateUI(playing and targetVol > PLAY.MaxVolume * 0.3, dt)
end)
