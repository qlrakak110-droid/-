-- ClubLights (client): the CLUB OCEAN 광안 light show, the crowd, the bottle-service parade and the
-- LED wall. The club's UI (dance buttons, bottle menu, toasts) is ClubDance.client.luau.
--
-- * Idles unless the local player is near / inside the club (zone check every 0.5 s against the
--   persistent ClubZone boxes). Near = exterior only (facade LED line, slits, portal, logo, tunnel),
--   and only while the camera actually looks at the facade: otherwise the frame does no work.
-- * Music: subscribes to ReplicatedStorage.ClubMusicShared (optional, pcall). While real music is
--   audible (ClubMusicShared.isLive) the show follows it: a phase-locked beat from the detected
--   onsets (+ bpm()), the kick envelope from the onsets, sections from the loudness (level()):
--   breakdown when it drops well under its 8 s average, build while it rises again, DROP when the
--   detector fires a Drop, groove otherwise. Without live music: the 126 BPM 64-bar clock synchronised
--   to workspace:GetServerTimeNow() (+ ShowEpoch on ClubRuntime): intro -> build -> drop ->
--   breakdown -> build -> drop.
-- * DROP moments: LED-wall countdown during the build-up (clock: 8..1 on the last two bars; live:
--   4-3-2-1 per bar once the build is under way), then a white flash + "DROP!", CO2 jets, a confetti
--   burst, a laser fan, a strobe / blinder burst and the crowd jumping with hands up. Low tier:
--   lighter CO2 / confetti (scaled rates, shorter), fewer lasers / strobes / reacting NPCs.
-- * LED wall overlays (main 32 x 11 wall; the side wall mirrors it where it can): countdown, DROP,
--   bottle-service banners from the server (WallMsg*: "VIP <NAME>", "HAPPY BIRTHDAY <NAME>"),
--   "NOW PLAYING <title - artist>" when a track starts (and again now and then in calm sections), the
--   local player's photo moment (ClubShared.Bus.photoAt from ClubDance: 3-2-1, flash, framed logo).
-- * Quality tier from ReplicatedStorage.GwangalliQuality (pcall; fallback: touch device without a
--   keyboard = "low"). low: show updated at 30 Hz, at most 60 property writes per frame in total
--   (show + parade walk + animation starts), no haze / fixture beams / pin spots / mirror rays / low
--   fog / flames / cold sparks / glints, 6 show SpotLights, at most 30 animated NPCs. mid / high:
--   every frame, 200 writes; touch devices on mid / high keep at most 8 fixture beams and half the
--   haze with capped particle sizes. Every loop is a round-robin over an array (no item starves) and
--   unchanged values are not written. The saver sub-level of low (GwangalliQuality.isSaver(): a
--   phone still under ~22 fps on low) goes lighter again: 15 Hz x 36 writes, 12 animated rigs.
-- * Drives LED floor tiles (ClubFloorTile Row/Col), LED wall / ceiling / booth / strips (ClubLight
--   Kind=...), moving heads + beam fixtures (CFramed locally around their mounts, SpotLights on),
--   strobes, blinders, lasers (ClubLaser beams: fan / sweep / tunnel / flicker), CO2 + confetti
--   bursts, sparklers at VIP tables in the breakdowns, haze density.
-- * Heavy translucent effects are saved disabled by the builder (ClubHaze emitters, fixture beams,
--   ClubShowBeam pin spots, ClubMirrorRay rays, ClubFX low fog / flames): this script enables them
--   only while the player is inside and only on the mid / high tiers.
-- * Owns the facade logo SurfaceGui (the builder drops its NightGlow tag): day / night state from
--   workspace.GwangalliIsNight, kick pulse at night while near the club.
-- * Kinetic LED tubes (ClubLight Kind=Kinetic) rise / fall in waves, the mirror ball (Kind=MirrorBall)
--   turns and throws rays (ClubMirrorRay beams) + glints in the slow sections, stage FX (ClubFX:
--   ColdSpark / Flame / LowFog / MirrorGlint) fire on the cues.
-- * Crowd (ClubNPC models, AnimationController + Animator; Humanoid rigs still work): Roblox's public
--   R6 animations picked from the Anim attribute (ClubShared.animFor), played locally only while the
--   player is inside the club or within 120 studs of the dance floor (the queue / bouncers outside
--   within 70 studs of the camera). The nearest rigs get the animation slots (tier cap; low: 24
--   nearest + 6 round-robin slots rotating every 4 s), rigs behind the camera rank lower, starts are
--   queued and staggered (1-3 per frame, start phase from AnimOffset / position, AnimSpeed variation).
--   Dance speed follows the music's BPM; hands-up ravers (attribute Bounce) hop on the beat, and on
--   mid / high the nearest dancers bob on it too; on every drop the nearest guests jump and cheer
--   (hands up); guests near the local player cheer when the player starts dancing. At night more of
--   the idle guests dance (most of them at the 22:00-04:00 peak).
-- * Bottle-service parade: staff walk the server's ParadePath (route start -> any table; fallback:
--   ClubRuntime/ParadeRoute WP1..WPn, floor found by a ray under each point), line up in front of the
--   table with their sparklers burning, then walk back. Start time = ClubRuntime attribute ParadeAt
--   (Club.server; fixed fallback schedule without the server). CFrames written on
--   RunService.PreSimulation, walk animation on the rig's Animator (procedural hip swing otherwise).
-- * Tables (ClubTable models): when the server stamps BottleAt on a table, clients near it put
--   sparkler champagne bottles on the table top (cloned from one local template, LOD="near", one
--   table per zone tick).
-- * Legacy music: a Sound from the club's MusicAssetId attribute (empty by default), only while
--   inside and never when the music system owns the music (ClubRuntime / ClubMusicState attribute
--   MusicOwner = "ClubMusic", or ClubMusicShared present and not published yet).
-- StreamingEnabled-safe: every registry follows CollectionService added / removed signals.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Shared: any
do
	local sharedModule = ReplicatedStorage:WaitForChild("ClubShared", 60)
	if not sharedModule then
		warn("[ClubLights] ReplicatedStorage.ClubShared missing; club show disabled")
		return
	end
	local okShared, res = pcall(require, sharedModule)
	if not okShared or type(res) ~= "table" then
		warn("[ClubLights] failed to load ClubShared:", res)
		return
	end
	Shared = res
end

local TAG = Shared.Tags
local ATTR = Shared.Attr or {}
local NAMES = Shared.Names or {}
local NAME_ROUTE = NAMES.ParadeRoute or "ParadeRoute"
local NAME_SERVE = NAMES.ServePoint or "ServePoint"
local ANIMS = Shared.Animations
local danceIds: { [string]: boolean } = {}
for _, id in ANIMS.Dance do
	danceIds[id] = true
end
local PARADE = Shared.Parade
	or { Period = 150, FirstDelay = 25, Speed = 4.2, Gap = 3.4, Hold = 22, Spread = 2.6, Busy = 85, RetargetRadius = 36 }
local TCFG = Shared.TableCfg or { BottleSeconds = 26, VisualRadius = 90 }

local K = {
	ZONE_INTERVAL = 0.5,
	FIXTURE_RADIUS = 260, -- fixtures further than this from the camera are not moved
	KINETIC_RADIUS = 170, -- kinetic tubes / mirror ball only move when the camera is this close
	BOUNCE_RADIUS = 90, -- hopping NPCs only move when the camera is this close
	LASER_RADIUS = 150, -- lasers only move when the camera is this close to their emitter
	LASER_INTERVAL = 1 / 30, -- lasers are re-aimed at 30 Hz
	NPC_FLOOR_RADIUS = 120, -- NPCs animate while inside, or while this close to the dance floor
	NPC_EXTERIOR_RADIUS = 70, -- the queue / bouncers outside animate while the camera is this close
	NPC_ROTATE_SECONDS = 4, -- the round-robin animation slots move on this often
	PARADE_RETARGET = math.max(36, PARADE.RetargetRadius or 36),
}

-- Per-tier budgets. hz = show update rate (0 = every frame); writes = property writes per update
-- (colours, CFrames, Enabled, Brightness) across the whole show; the per-system caps are taken in
-- priority order from that budget and the LED colours get the rest.
local TIERS = {
	low = {
		hz = 20, -- (phones: 20 Hz x 48 writes = <= 960 property writes/s for the whole show)
		writes = 48,
		visits = 240, -- colour items evaluated per update (the colour maths is the CPU cost)
		strobes = 4,
		fixtures = 12,
		movingSpotsOnly = true, -- only fixtures whose SpotLight is on are moved
		lasers = 8,
		laserEvery = 2, -- every 2nd laser only
		kinetic = 6,
		bounce = 8,
		spots = 4,
		npcCap = 20, -- animated rigs are the club's biggest CPU cost on a phone
		npcFixed = 16,
		npcStarts = 6,
		npcRadius = 90,
		haze = 0,
		beams = false,
		maxBeams = 0,
		rays = false,
		pins = false,
		fx = { ColdSpark = false, Flame = false, LowFog = false, MirrorGlint = false },
		co2 = true,
		co2Scale = 0.3, -- CO2 jets on drops: 30 % of the built rate for 0.7 s
		co2Secs = 0.7,
		confetti = true,
		confettiScale = 0.4,
		fxScale = 0.5,
		bottleFx = 0.5,
		reactions = 10, -- NPCs that jump / cheer on a drop
		bob = false, -- animated dancers do not bob on the beat (writes)
		startsPerFrame = 1, -- animation starts per frame (queued)
	},
	mid = {
		hz = 0,
		writes = 200,
		visits = math.huge,
		strobes = 32,
		fixtures = 72,
		movingSpotsOnly = false,
		lasers = 64,
		laserEvery = 1,
		kinetic = 56,
		bounce = 18,
		spots = 10,
		npcCap = 60,
		npcFixed = 48,
		npcStarts = 12,
		npcRadius = 140,
		haze = 0.6,
		beams = true,
		maxBeams = 24,
		rays = true,
		pins = true,
		fx = { ColdSpark = true, Flame = true, LowFog = true, MirrorGlint = true },
		co2 = true,
		co2Scale = 1,
		co2Secs = 1.3,
		confetti = true,
		confettiScale = 1,
		fxScale = 0.8,
		bottleFx = 0.8,
		reactions = 24,
		bob = true,
		startsPerFrame = 2,
	},
	high = {
		hz = 0,
		writes = 200,
		visits = math.huge,
		strobes = 32,
		fixtures = 72,
		movingSpotsOnly = false,
		lasers = 64,
		laserEvery = 1,
		kinetic = 56,
		bounce = 18,
		spots = math.huge,
		npcCap = 200,
		npcFixed = 200,
		npcStarts = 24,
		npcRadius = 220,
		haze = 1,
		beams = true,
		maxBeams = math.huge,
		rays = true,
		pins = true,
		fx = { ColdSpark = true, Flame = true, LowFog = true, MirrorGlint = true },
		co2 = true,
		co2Scale = 1,
		co2Secs = 1.3,
		confetti = true,
		confettiScale = 1,
		fxScale = 1,
		bottleFx = 1,
		reactions = 60,
		bob = true,
		startsPerFrame = 3,
	},
}

local function warnf(...)
	warn("[ClubLights]", ...)
end

local tierName = "high"
local tierKey = ""
local T: any = TIERS.high
local policyDirty = true -- tier changed: effects / emitters are re-applied on the next zone tick
local refreshTier
do
	-- Touch device without a keyboard (phones / tablets). Re-read on every call because a keyboard can
	-- be attached mid-session. Only the fallback when GwangalliQuality is unavailable.
	local function isTouchOnly(): boolean
		local ok, res = pcall(function()
			return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		end)
		return ok and res == true
	end
	local function isTouch(): boolean
		local ok, res = pcall(function()
			return UserInputService.TouchEnabled
		end)
		return ok and res == true
	end

	-- a touch device on mid / high (a strong phone or tablet): mobile GPUs still pay for overdraw, so
	-- at most 8 fixture beams, half the haze and haze particles capped at 12 studs
	local function derive(t: string, touch: boolean): any
		local base = TIERS[t] or TIERS.high
		if not touch or t == "low" then
			return base
		end
		local d = table.clone(base)
		d.maxBeams = math.min(base.maxBeams, 8)
		d.haze = base.haze * 0.5
		d.hazeSizeCap = 12
		return d
	end

	---------------------------------------------------------------------------------------------------
	-- Quality tier (ReplicatedStorage.GwangalliQuality, loaded lazily with a pcall)
	---------------------------------------------------------------------------------------------------
	local Quality: any = nil -- module table once loaded, false when it failed

	local function loadQuality()
		if Quality ~= nil then
			return
		end
		local mod = ReplicatedStorage:FindFirstChild("GwangalliQuality")
		if not mod then
			return -- not replicated (or not in this place): retry on the next call, isTouchOnly meanwhile
		end
		if not mod:IsA("ModuleScript") then
			Quality = false
			return
		end
		local ok, q = pcall(require, mod)
		if ok and type(q) == "table" and type(q.get) == "function" then
			Quality = q
		else
			Quality = false
			warnf("GwangalliQuality failed to load:", q)
		end
	end

	local function currentTier(): string
		loadQuality()
		if Quality then
			local ok, t = pcall(Quality.get)
			if ok and (t == "low" or t == "mid" or t == "high") then
				return t
			end
		end
		return if isTouchOnly() then "low" else "high"
	end

	-- the SAVER sub-level of "low" (GwangalliQuality.isSaver: a phone still under ~22 fps on low)
	local function saverOn(): boolean
		if Quality and type(Quality.isSaver) == "function" then
			local ok, on = pcall(Quality.isSaver)
			return ok and on == true
		end
		return false
	end

	function refreshTier()
		local t = currentTier()
		local touch = isTouch()
		local saver = t == "low" and saverOn()
		local key = t .. (if touch then ":touch" else "") .. (if saver then ":saver" else "")
		if key ~= tierKey then
			tierKey = key
			tierName = t
			T = derive(t, touch)
			if saver then
				-- weak phones: fewer animated rigs (the club's biggest CPU cost), a slower, lighter show
				local d = table.clone(T)
				d.hz = 15
				d.writes = 36
				d.visits = 160
				d.strobes = 2
				d.fixtures = 8
				d.lasers = 4
				d.kinetic = 4
				d.bounce = 4
				d.spots = 3
				d.npcCap = 12
				d.npcFixed = 10
				d.npcStarts = 4
				d.npcRadius = 70
				d.co2Scale = 0.2
				d.confettiScale = 0.25
				d.fxScale = 0.35
				d.bottleFx = 0.35
				d.reactions = 6
				T = d
			end
			policyDirty = true
		end
	end
end

refreshTier()
policyDirty = true

---------------------------------------------------------------------------------------------------
-- Day / night (the facade logo gui is owned by this script, not by the NightGlow runtime)
-- Source of truth: workspace attribute GwangalliIsNight (GwangalliEnvironment.server); fallback:
-- the night window of ReplicatedStorage.GwangalliConfig applied to Lighting.ClockTime.
---------------------------------------------------------------------------------------------------
local nightCfg = { from = 17.8, to = 6.2, glowScale = 1, loaded = false }
local computeNight: () -> boolean
do
local function loadNightConfig()
	if nightCfg.loaded then
		return
	end
	local mod = ReplicatedStorage:FindFirstChild("GwangalliConfig")
	if not mod or not mod:IsA("ModuleScript") then
		return -- not replicated yet: keep the defaults and retry on the next call
	end
	nightCfg.loaded = true
	local ok, cfg = pcall(require, mod)
	if ok and type(cfg) == "table" then
		if type(cfg.NightStart) == "number" then
			nightCfg.from = cfg.NightStart
		end
		if type(cfg.NightEnd) == "number" then
			nightCfg.to = cfg.NightEnd
		end
		if type(cfg.Night) == "table" and type(cfg.Night.GlowBrightnessScale) == "number" then
			nightCfg.glowScale = cfg.Night.GlowBrightnessScale
		end
	end
end

function computeNight(): boolean
	local attr = workspace:GetAttribute("GwangalliIsNight")
	if type(attr) == "boolean" then
		return attr
	end
	loadNightConfig()
	local c = Lighting.ClockTime
	if nightCfg.from <= nightCfg.to then
		return c >= nightCfg.from and c < nightCfg.to
	end
	return c >= nightCfg.from or c < nightCfg.to
end
end

local nightNow = false
pcall(function()
	nightNow = computeNight()
end)

-- 0 = day, 1 = night, 2 = the 22:00-04:00 peak (more of the crowd dances)
local function nightLevel(): number
	if not nightNow then
		return 0
	end
	local c = Lighting.ClockTime
	return if c >= 22 or c < 4 then 2 else 1
end

---------------------------------------------------------------------------------------------------
-- Music: ReplicatedStorage.ClubMusicShared (optional) + the client bus shared with ClubDance
---------------------------------------------------------------------------------------------------
local Bus: any = Shared.Bus
if type(Bus) ~= "table" then
	Bus = {}
	Shared.Bus = Bus
end
local scriptStart = os.clock()
local CM: any = nil -- the ClubMusicShared module once loaded (false = unusable)
-- onsets as the music detector reports them (ClubMusicShared.Beat); read by the live show
local Live = { onsets = 0, seen = 0, onsetT = -1e9, onsetK = 0, dropPending = false, dropSeenT = -1e9 }

do
local function onMusicBeat(intensity: any, isDrop: any)
	local t = os.clock()
	Live.onsets += 1
	Live.onsetT = t
	Live.onsetK = if type(intensity) == "number" and intensity == intensity then math.clamp(intensity, 0, 1) else 0.7
	if isDrop == true then
		Live.dropPending = true
		Live.dropSeenT = t
	end
end

local function hookMusic(mod: Instance)
	if CM ~= nil then
		return
	end
	if not mod:IsA("ModuleScript") then
		CM = false
		return
	end
	local ok, res = pcall(require, mod)
	if ok and type(res) == "table" and type(res.Beat) == "table" and type(res.Beat.Connect) == "function" then
		local okC, err = pcall(function()
			res.Beat:Connect(onMusicBeat)
		end)
		if okC then
			CM = res
		else
			CM = false
			warnf("ClubMusicShared.Beat:Connect failed:", err)
		end
	else
		CM = false
		warnf("ClubMusicShared failed to load:", res)
	end
end
do
	local m = ReplicatedStorage:FindFirstChild("ClubMusicShared")
	if m then
		hookMusic(m)
	else
		task.spawn(function()
			local w = ReplicatedStorage:WaitForChild("ClubMusicShared", 120)
			if w then
				hookMusic(w)
			end
		end)
	end
end
end

-- ClubMusicShared.<name>() with a fallback (never errors)
local function cm(name: string, default: any): (any, any)
	local f = CM and CM[name]
	if type(f) ~= "function" then
		return default, nil
	end
	local ok, a, b = pcall(f)
	if ok then
		return a, b
	end
	return default, nil
end

---------------------------------------------------------------------------------------------------
-- Registries (filled / emptied by tag signals; StreamingEnabled adds and removes instances)
---------------------------------------------------------------------------------------------------
local zones: { [BasePart]: boolean } = {}
local colourItems: { [Instance]: any } = {}
local interiorList: { any } = {} -- round-robin order inside (everything but the facade, + tunnel)
local exteriorList: { any } = {} -- facade items (Near state)
local wallList: { any } = {} -- LED wall pixels (main + side), updated first
local listDirty = true
local fixtures: { [BasePart]: any } = {}
local fixtureList: { any } = {}
local fixturesDirty = true
local strobes: { [BasePart]: any } = {}
local strobeList: { any } = {}
local strobesDirty = true
local lasers: { [Beam]: any } = {}
local laserList: { any } = {} -- round-robin order for the laser write budget
local laserListDirty = true
local co2: { [ParticleEmitter]: any } = {} -- emitter -> { rate = built Rate, k = applied scale }
local confetti: { [ParticleEmitter]: any } = {}
local sparklers: { [ParticleEmitter]: boolean } = {}
local hazes: { [ParticleEmitter]: any } = {} -- emitter -> { rate = built Rate }
local npcs: { [Model]: any } = {}
local bounceList: { any } = {} -- NPCs with a Bounce attribute (round-robin)
local bounceListDirty = true
local runtimes: { [Instance]: boolean } = {}
local kinetics: { [BasePart]: any } = {}
local kineticList: { any } = {}
local kineticsDirty = true
local balls: { [BasePart]: any } = {}
local rays: { [Beam]: boolean } = {}
local showBeams: { [Beam]: string } = {} -- pin spots etc. -> Room
local flameGlows: { [BasePart]: any } = {}
local fx: { [ParticleEmitter]: any } = {} -- emitter -> { kind, rate } (global stage FX)
local fxWant: { [string]: boolean } = {} -- what the show cues ask for
local fxOn: { [string]: boolean } = {} -- what is applied (cue and tier policy)
local raysWant = false
local raysOn = false
local spotsRoom = "" -- which room's show SpotLights are enabled ("" = none)
local sparkOn = false -- VIP sparklers currently burning
local hazeApplied = { on = false, rate = -1 }
local extraWrites = 0 -- writes made outside the show update (parade, animation starts), charged to it
local floorSum = Vector3.zero -- dance-floor centre = mean of the LED floor tiles
local floorCount = 0

local applyHazeSize: (ParticleEmitter, any) -> ()
local EXTERIOR_KINDS = { FacadeLine = true, FacadeSlit = true, Portal = true, Logo = true, Tunnel = true, CameraFlash = true }
local IGNORED_KINDS = { Wearable = true, LaserEmitter = true }
local FX_KINDS = { ColdSpark = true, Flame = true, LowFog = true, MirrorGlint = true }

-- haze particle size capped on touch devices (T.hazeSizeCap), restored otherwise
local function cappedSequence(seq: NumberSequence, cap: number): NumberSequence
	local kps = {}
	for _, kp in seq.Keypoints do
		table.insert(kps, NumberSequenceKeypoint.new(kp.Time, math.min(kp.Value, cap), math.min(kp.Envelope, cap * 0.25)))
	end
	return NumberSequence.new(kps)
end
function applyHazeSize(pe: ParticleEmitter, rec: any)
	local cap = T.hazeSizeCap
	local want = type(cap) == "number"
	if rec.capped == want or not pe.Parent then
		return
	end
	rec.capped = want
	local ok, err = pcall(function()
		pe.Size = if want then cappedSequence(rec.size, cap) else rec.size
	end)
	if not ok then
		warnf("haze size:", err)
	end
end

local function watch(tag: string, onAdded: (Instance) -> (), onRemoved: (Instance) -> ())
	local tracked: { [Instance]: boolean } = {}
	local function add(inst: Instance)
		if tracked[inst] or not inst:IsDescendantOf(workspace) then
			return
		end
		tracked[inst] = true
		local ok, err = pcall(onAdded, inst)
		if not ok then
			warnf(tag, "add failed:", err)
		end
	end
	local function remove(inst: Instance)
		if not tracked[inst] then
			return
		end
		tracked[inst] = nil
		local ok, err = pcall(onRemoved, inst)
		if not ok then
			warnf(tag, "remove failed:", err)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
	-- initial pass spread over frames (~1,100 tagged club instances when the place is not streamed)
	for _, inst in CollectionService:GetTagged(tag) do
		add(inst)
		K.bootAdds = (K.bootAdds or 0) + 1
		if K.bootAdds % 150 == 0 then
			task.wait()
		end
	end
end

local function num(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	if type(v) == "number" and v == v then
		return v
	end
	return default
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- colour items --------------------------------------------------------------------------------------

-- Facade logo SurfaceGui (channel letters, Kind = Logo). The builder removes its NightGlow tag, so
-- this script owns it: by day LightInfluence 1 at the built brightness, at night emissive
-- (LightInfluence 0) at GlowBrightness, pulsing on the kick while the show runs (pulse >= 1).
-- The values match the NightGlow runtime, so an old place where the tag is still present agrees.
local function applyLogoGui(rec: any, pulse: number): number
	local gui = rec.gui
	if not gui or not gui.Parent then
		return 0
	end
	local gb = gui:GetAttribute("GlowBrightness")
	local base = if type(gb) == "number" then gb else rec.guiBase
	local li, b
	if nightNow then
		li, b = 0, base * nightCfg.glowScale * pulse
	else
		li, b = 1, base
	end
	local w = 0
	if gui.LightInfluence ~= li then
		gui.LightInfluence = li
		w += 1
	end
	if math.abs(gui.Brightness - b) > 0.05 then
		gui.Brightness = b
		w += 1
	end
	return w
end

local function addColourItem(part: BasePart, kind: string)
	local rec = {
		part = part,
		kind = kind,
		row = num(part, "Row", 0),
		col = num(part, "Col", 0),
		index = num(part, "Index", 0),
		count = math.max(1, num(part, "Count", 1)),
		exterior = EXTERIOR_KINDS[kind] == true,
		base = part.Color,
		last = part.Color,
		gui = nil :: SurfaceGui?,
		guiBase = 0,
		pos = part.Position,
		tableId = part:GetAttribute("TableId"), -- TableRing: which ClubTable it belongs to
		side = part:GetAttribute("Screen") == "Side", -- side LED wall (samples the main wall's Row / Col)
	}
	if kind == "Logo" and part.Transparency > 0.95 then
		local gui = part:FindFirstChildWhichIsA("SurfaceGui")
		if gui then
			rec.gui = gui
			rec.guiBase = gui.Brightness
		end
	end
	if kind == "Floor" then
		floorSum += rec.pos
		floorCount += 1
	end
	colourItems[part] = rec
	listDirty = true
	if rec.gui then
		applyLogoGui(rec, 1) -- streamed in: match the current day / night state at once
	end
end

local function removeColourItem(inst: Instance)
	local rec = colourItems[inst]
	if rec then
		if rec.kind == "Floor" then
			floorSum -= rec.pos
			floorCount = math.max(0, floorCount - 1)
		end
		colourItems[inst] = nil
		listDirty = true
	end
end

-- fixtures ------------------------------------------------------------------------------------------
local function resolveFixture(rec: any)
	local model = rec.head.Parent
	if not model then
		return
	end
	if not rec.yoke then
		local y = model:FindFirstChild("Yoke")
		if y and y:IsA("BasePart") then
			rec.yoke = y
			rec.yokeRest = y.CFrame
			rec.headOff = y.CFrame:ToObjectSpace(rec.headRest)
		end
	end
	if not rec.lens then
		local l = model:FindFirstChild("Lens")
		if l and l:IsA("BasePart") then
			rec.lens = l
			rec.lensOff = rec.headRest:ToObjectSpace(l.CFrame)
		end
	end
end

local function addFixture(head: BasePart, kind: string)
	local rec = {
		head = head,
		kind = kind,
		index = num(head, "Index", 0),
		side = num(head, "Side", 1),
		room = (head:GetAttribute("Room") == "HipHop") and "HipHop" or "Main",
		headRest = head.CFrame,
		yoke = nil :: BasePart?,
		yokeRest = nil :: CFrame?,
		headOff = CFrame.new(0, -(head.Size.Y / 2 + 0.7), 0),
		lens = nil :: BasePart?,
		lensOff = nil :: CFrame?,
		beam = head:FindFirstChildWhichIsA("Beam"),
		spot = head:FindFirstChildWhichIsA("SpotLight"),
		lastColour = nil :: Color3?,
		resolveAt = 0,
		spotDist = 0,
	}
	resolveFixture(rec)
	-- streamed in: dark until the zone loop's next setSpots() picks the spots / beams to light
	if rec.spot and rec.spot.Enabled then
		rec.spot.Enabled = false
	end
	if rec.beam and rec.beam.Enabled then
		rec.beam.Enabled = false
	end
	fixtures[head] = rec
	fixturesDirty = true
end

watch(TAG.Light, function(inst)
	if not inst:IsA("BasePart") then
		return
	end
	local kind = inst:GetAttribute("Kind")
	if type(kind) ~= "string" or IGNORED_KINDS[kind] then
		return
	end
	if kind == "MovingHead" or kind == "Beam" then
		addFixture(inst, kind)
	elseif kind == "Kinetic" then
		kinetics[inst] = {
			part = inst,
			rest = inst.CFrame,
			row = num(inst, "Row", 0),
			col = num(inst, "Col", 0),
			index = num(inst, "Index", 0),
			travel = math.clamp(num(inst, "Travel", 6), 0, 12),
			lastD = 0,
			lastColour = inst.Color,
		}
		kineticsDirty = true
	elseif kind == "MirrorBall" then
		balls[inst] = { part = inst, rest = inst.CFrame }
	elseif kind == "FlameGlow" then
		flameGlows[inst] = { part = inst, base = inst.Color, on = false }
	elseif kind == "Strobe" or kind == "Blinder" then
		strobes[inst] = { part = inst, kind = kind, index = num(inst, "Index", 0), on = nil, base = inst.Color }
		strobesDirty = true
	else
		addColourItem(inst, kind)
	end
end, function(inst)
	if fixtures[inst :: BasePart] then
		fixtures[inst :: BasePart] = nil
		fixturesDirty = true
	end
	if strobes[inst :: BasePart] then
		strobes[inst :: BasePart] = nil
		strobesDirty = true
	end
	if kinetics[inst :: BasePart] then
		kinetics[inst :: BasePart] = nil
		kineticsDirty = true
	end
	balls[inst :: BasePart] = nil
	flameGlows[inst :: BasePart] = nil
	removeColourItem(inst)
end)

watch(TAG.FloorTile, function(inst)
	if inst:IsA("BasePart") then
		addColourItem(inst, "Floor")
	end
end, removeColourItem)

watch(TAG.Laser, function(inst)
	if not inst:IsA("Beam") then
		return
	end
	lasers[inst] = {
		beam = inst,
		emitter = num(inst, "Emitter", 1),
		index = num(inst, "Index", 0),
		count = math.max(1, num(inst, "Count", 8)),
		base = inst.Color,
		enabled = inst.Enabled,
		lastColour = nil :: Color3?,
		lastTarget = nil :: Vector3?,
	}
	laserListDirty = true
end, function(inst)
	lasers[inst :: Beam] = nil
	laserListDirty = true
end)

local function emitterWatch(tag: string, registry: { [ParticleEmitter]: any })
	watch(tag, function(inst)
		if inst:IsA("ParticleEmitter") then
			registry[inst] = { rate = inst.Rate, k = 1 }
			if inst.Enabled then
				inst.Enabled = false -- bursts are fired by the show cues
			end
		end
	end, function(inst)
		registry[inst :: ParticleEmitter] = nil
	end)
end
emitterWatch(TAG.CO2, co2)
emitterWatch(TAG.Confetti, confetti)
watch(TAG.Sparkler, function(inst)
	if inst:IsA("ParticleEmitter") then
		sparklers[inst] = true
		inst.Enabled = sparkOn -- streamed in mid-show: match the current state
	end
end, function(inst)
	sparklers[inst :: ParticleEmitter] = nil
end)
watch(TAG.Haze, function(inst)
	if not inst:IsA("ParticleEmitter") then
		return
	end
	local rec = { rate = inst.Rate, size = inst.Size, capped = false }
	hazes[inst] = rec
	-- saved disabled by the builder; streamed in mid-show: match the applied state
	if hazeApplied.on then
		inst.Rate = rec.rate * hazeApplied.rate
	end
	inst.Enabled = hazeApplied.on
	if T.hazeSizeCap then
		applyHazeSize(inst, rec)
	end
end, function(inst)
	hazes[inst :: ParticleEmitter] = nil
end)
watch(TAG.FX or "ClubFX", function(inst)
	if not inst:IsA("ParticleEmitter") then
		return
	end
	local kind = inst:GetAttribute("Kind")
	if type(kind) == "string" and FX_KINDS[kind] then
		local rec = { kind = kind, rate = inst.Rate }
		fx[inst] = rec
		inst.Rate = rec.rate * T.fxScale
		inst.Enabled = fxOn[kind] == true -- streamed in mid-show: match the current state
	end
end, function(inst)
	fx[inst :: ParticleEmitter] = nil
end)
watch(TAG.MirrorRay or "ClubMirrorRay", function(inst)
	if inst:IsA("Beam") then
		rays[inst] = true
		inst.Enabled = raysOn
	end
end, function(inst)
	rays[inst :: Beam] = nil
end)
watch(TAG.ShowBeam or "ClubShowBeam", function(inst)
	if inst:IsA("Beam") then
		local room = inst:GetAttribute("Room")
		showBeams[inst] = if room == "HipHop" then "HipHop" else "Main"
		inst.Enabled = T.pins and spotsRoom ~= "" and showBeams[inst] == spotsRoom
	end
end, function(inst)
	showBeams[inst :: Beam] = nil
end)

watch(TAG.Zone, function(inst)
	if inst:IsA("BasePart") then
		zones[inst] = true
	end
end, function(inst)
	zones[inst :: BasePart] = nil
end)

-- LED wall banner (Club.server: WallMsg / WallMsgAt / WallMsgFor / WallMsgKind on ClubRuntime)
local wallMsg = { text = "", at = 0, dur = 0, kind = "", cols = nil :: { { boolean } }? }
local function readWallMsg(rt: Instance)
	local text = rt:GetAttribute(ATTR.WallMsg or "WallMsg")
	local at = rt:GetAttribute(ATTR.WallMsgAt or "WallMsgAt")
	local dur = rt:GetAttribute(ATTR.WallMsgFor or "WallMsgFor")
	local kind = rt:GetAttribute(ATTR.WallMsgKind or "WallMsgKind")
	if type(text) ~= "string" or type(at) ~= "number" or type(dur) ~= "number" then
		return
	end
	local clean = if Shared.ledText then Shared.ledText(text, 40) else text
	if clean ~= wallMsg.text then
		wallMsg.cols = if clean ~= "" then Shared.textColumns(clean) else nil
	end
	wallMsg.text, wallMsg.at, wallMsg.dur = clean, at, math.clamp(dur, 0, 120)
	wallMsg.kind = if type(kind) == "string" then kind else ""
end
local runtimeConns: { [Instance]: RBXScriptConnection } = {}
watch(TAG.Runtime, function(inst)
	runtimes[inst] = true
	readWallMsg(inst)
	runtimeConns[inst] = inst:GetAttributeChangedSignal(ATTR.WallMsgSerial or "WallMsgSerial"):Connect(function()
		readWallMsg(inst)
	end)
end, function(inst)
	runtimes[inst] = nil
	local c = runtimeConns[inst]
	if c then
		c:Disconnect()
		runtimeConns[inst] = nil
	end
end)

-- zone lookup for a world position: highest-priority ClubZone box containing it
local function zoneAt(pos: Vector3): (BasePart?, string?)
	local best: BasePart? = nil
	local bestPri = -math.huge
	for z in zones do
		if z.Parent then
			local lp = z.CFrame:PointToObjectSpace(pos)
			local h = z.Size * 0.5
			if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
				local pri = num(z, "Priority", 0)
				if pri > bestPri then
					best, bestPri = z, pri
				end
			end
		end
	end
	if not best then
		return nil, nil
	end
	local name = best:GetAttribute("Zone")
	return best, if type(name) == "string" then name else "Main"
end

-- dance-floor centre (LED tiles), else the Main zone box
local function danceFloorPos(): Vector3?
	if floorCount > 0 then
		return floorSum / floorCount
	end
	for z in zones do
		if z.Parent and z:GetAttribute("Zone") == "Main" then
			return z.Position
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Zones / state (evaluated every K.ZONE_INTERVAL by the zone loop at the bottom)
---------------------------------------------------------------------------------------------------
local state = "Idle" -- Idle | Near | Inside
local zoneName = ""
local muffle = 1
local inClub = false -- inside, or within K.NPC_FLOOR_RADIUS of the dance floor (NPCs / parade run)

local function listenerPosition(): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position
end

local function evaluateZones()
	local pos = listenerPosition()
	if not pos then
		return "Idle", "", 1
	end
	local best, name = zoneAt(pos)
	if not best or not name then
		return "Idle", "", 1
	end
	local m = math.clamp(num(best, "Muffle", 0), 0, 1)
	if name == "Near" then
		return "Near", name, m
	end
	return "Inside", name, m
end

---------------------------------------------------------------------------------------------------
-- NPC animation (local playback of Roblox's public R6 animations on the rig's Animator)
---------------------------------------------------------------------------------------------------
local npcListDirty = true
local paradeActive = false -- the parade staff are walked (player in the club); set by the zone loop
local stopAnim, playAnim, stopAllAnims, updateNPCAnim, processAnimQueue, crowdReact, updateReactions
local bpmK = 1 -- dance speed factor from the music's BPM (1 = 126 BPM); set by the frame
local nightLvl = 0 -- nightLevel() at the last zone tick
do
	local animObjects: { [string]: Animation } = {}
	local npcList: { any } = {} -- non-parade NPC records (array, rebuilt when dirty)
	local npcCands: { any } = {}
	local rrOffset = 0
	local rrClock = 0
	local rrSlotsLast = 0
	local animsLive = false -- a track may be playing (false after an inactive tick stopped them all)

	local function animObject(id: string): Animation
		local a = animObjects[id]
		if not a then
			a = Instance.new("Animation")
			a.AnimationId = id
			animObjects[id] = a
		end
		return a
	end

	-- Animator under the AnimationController (builder contract) or under a Humanoid (older rigs).
	-- If the rig has neither after ~3 s (streaming / older place), one is created locally: local tracks
	-- on server-owned rigs play client-side only, which is all this script needs.
	local function findAnimator(rec: any): Animator?
		local model = rec.model
		local host = model:FindFirstChildOfClass("AnimationController") or model:FindFirstChildOfClass("Humanoid")
		if host then
			local a = host:FindFirstChildOfClass("Animator")
			if a then
				return a
			end
		end
		rec.animatorWait += 1
		if rec.animatorWait < 6 then
			return nil
		end
		local ok, created = pcall(function()
			local h = host
			if not h then
				local c = Instance.new("AnimationController")
				c.Name = "AnimationController"
				c.Parent = model
				h = c
			end
			local a = Instance.new("Animator")
			a.Parent = h
			return a
		end)
		if ok then
			return created
		end
		return nil
	end

	local function getTrack(rec: any, id: string): AnimationTrack?
		local track = rec.tracks[id]
		if track then
			return track
		end
		if rec.failed >= 3 then
			return nil
		end
		local animator = findAnimator(rec)
		if not animator then
			return nil
		end
		local ok, res = pcall(function()
			return (animator :: Animator):LoadAnimation(animObject(id))
		end)
		if not ok or not res then
			rec.failed += 1
			return nil
		end
		local tr = res :: AnimationTrack
		tr.Looped = true
		tr.Priority = if id == ANIMS.Walk then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Core
		rec.tracks[id] = tr
		return tr
	end

	-- start phase (0..1 of the track): AnimOffset, else from the rig's position
	local function applyOffset(rec: any): boolean
		local track = rec.current
		if not track or rec.noOffset then
			return true
		end
		local len = track.Length
		if len and len > 0 then
			pcall(function()
				track.TimePosition = (rec.seed * len) % len
			end)
			return true
		end
		return false
	end

	function stopAnim(rec: any)
		local track = rec.current
		if track then
			pcall(function()
				track:Stop(0.3)
			end)
		end
		rec.current, rec.currentId, rec.playing, rec.pendingOffset = nil, nil, false, false
	end

	function playAnim(rec: any, id: string, speed: number, noOffset: boolean?): boolean
		rec.noOffset = noOffset == true
		if rec.playing and rec.currentId == id and rec.current then
			if math.abs((rec.curSpeed or 1) - speed) > 0.01 then
				local tr = rec.current
				pcall(function()
					tr:AdjustSpeed(speed)
				end)
				rec.curSpeed = speed
			end
			return true
		end
		local track = getTrack(rec, id)
		if not track then
			return false
		end
		if rec.current and rec.current ~= track then
			local old = rec.current
			pcall(function()
				old:Stop(0.3)
			end)
		end
		local ok = pcall(function()
			track:Play(0.35, 1, speed)
		end)
		if not ok then
			return false
		end
		rec.current, rec.currentId, rec.curSpeed, rec.playing = track, id, speed, true
		animsLive = true
		rec.pendingOffset = not applyOffset(rec) -- length unknown until the asset loads: retry per tick
		rec.offsetTries = 0
		return true
	end

	function stopAllAnims()
		for _, rec in npcs do
			if rec.playing then
				stopAnim(rec)
			end
		end
	end

	-- interior NPC (inside the building) vs exterior (queue, bouncers, valet)
	-- rooms that see each other (the show rooms are open to one another; the restrooms and the
	-- 2F lounge / terrace / VIP stair are walled off): a rig in another group than the camera's
	-- room only animates when it is close (doorways)
	local ZONE_GROUP = {
		Main = "show", Lobby = "show", Corridor = "show", HipHop = "show",
		Restroom = "wc",
		Lounge = "up", Terrace = "up", VIPStair = "up",
	}
	local DOORWAY_RADIUS = 25

	local function npcInterior(rec: any): boolean
		if rec.interior ~= nil then
			return rec.interior
		end
		local z = Shared.zoneKey(rec.model:GetAttribute(ATTR.Zone or "Zone"))
		if z then
			rec.interior = z ~= "Near" and z ~= "Outside" and z ~= "Forecourt" and z ~= "Street"
			rec.group = ZONE_GROUP[z] or "show"
			return rec.interior
		end
		if next(zones) == nil or not rec.home then
			return true -- zones not replicated yet: decide on a later tick
		end
		local _, name = zoneAt(rec.home.Position)
		rec.interior = name ~= nil and name ~= "Near"
		rec.group = ZONE_GROUP[name or ""] or "show"
		return rec.interior
	end

	local function byScore(a: any, b: any): boolean
		return a.score < b.score
	end

	-- the animation a rig should play now: the night-time dance of an idle guest, else its own
	local function desiredAnim(rec: any): (string?, number)
		local id = rec.animId
		if rec.nightId and rec.nightNeed and nightLvl >= rec.nightNeed then
			id = rec.nightId
		end
		if not id then
			return nil, 1
		end
		local speed = rec.animSpeed
		if rec.danceAnim or id == rec.nightId then
			speed *= bpmK -- dancers follow the tempo of the track
		end
		return id, speed
	end

	-- animation starts wait here and are made a few per frame by the show update (charged to its
	-- write budget: Looped / Priority on first load + TimePosition)
	local startQueue: { any } = {}
	local startHead = 1

	local function enqueue(rec: any)
		if not rec.queued then
			rec.queued = true
			table.insert(startQueue, rec)
		end
	end

	-- Every zone tick: pick the rigs that get an animation slot, stop the others, queue the starts.
	function updateNPCAnim(now: number)
		if npcListDirty then
			table.clear(npcList)
			for _, rec in npcs do
				if not rec.member then
					table.insert(npcList, rec)
				end
			end
			npcListDirty = false
		end
		local cam = workspace.CurrentCamera
		local n = 0
		local active = state ~= "Idle" or inClub
		if active and cam then
			local cf = cam.CFrame
			local cp, look = cf.Position, cf.LookVector
			local interiorOk = state == "Inside" or inClub
			local _, camZone = zoneAt(cp)
			local camGroup = ZONE_GROUP[camZone or zoneName] or "show"
			for _, rec in npcList do
				rec.want = false
				if rec.animId and rec.home and rec.model.Parent then
					local interior = npcInterior(rec)
					local limit = if interior then (if interiorOk then T.npcRadius else -1) else K.NPC_EXTERIOR_RADIUS
					local dv = rec.home.Position - cp
					local d = dv.Magnitude
					if interior and d > DOORWAY_RADIUS and (rec.group or "show") ~= camGroup then
						limit = -1 -- behind the walls of another room
					end
					if d <= limit then
						local sc = d
						if d > 10 and look:Dot(dv) < -0.2 * d then
							sc = d * 2.5 + 20 -- behind the camera
						end
						if rec.playing then
							sc *= 0.85 -- hysteresis: no flip-flop at the slot boundary
						end
						rec.score = sc
						n += 1
						npcCands[n] = rec
					end
				end
			end
		else
			if not animsLive and not npcListDirty then
				return -- outside the club and nothing playing: no work
			end
			for _, rec in npcList do
				rec.want = false
			end
		end
		for i = #npcCands, n + 1, -1 do
			npcCands[i] = nil
		end
		if n > 1 then
			table.sort(npcCands, byScore)
		end
		local fixed = math.min(n, T.npcFixed)
		for i = 1, fixed do
			npcCands[i].want = true
		end
		local rest = n - fixed
		local slots = math.min(math.max(0, T.npcCap - fixed), rest)
		if now - rrClock >= K.NPC_ROTATE_SECONDS then
			rrClock = now
			rrOffset += rrSlotsLast
		end
		rrSlotsLast = slots
		if slots > 0 then
			for k = 0, slots - 1 do
				npcCands[fixed + 1 + (rrOffset + k) % rest].want = true
			end
		end
		-- stops first; starts (nearest first) and animation changes go to the queue; speed changes
		-- (the track's BPM) are applied in place
		for _, rec in npcList do
			if rec.playing and not rec.want then
				stopAnim(rec)
				rec.reacting = false
			end
		end
		for i = 1, n do
			local rec = npcCands[i]
			if rec.want and rec.failed < 3 and not rec.reacting then
				local id, speed = desiredAnim(rec)
				if id then
					if not rec.playing or rec.currentId ~= id then
						enqueue(rec)
					elseif math.abs((rec.curSpeed or 1) - speed) > 0.03 then
						playAnim(rec, id, speed) -- same track: AdjustSpeed only
					end
				end
			end
		end
		for _, rec in npcList do
			if rec.pendingOffset and rec.playing then
				rec.offsetTries = (rec.offsetTries or 0) + 1
				if applyOffset(rec) or rec.offsetTries > 20 then
					rec.pendingOffset = false
				end
			end
		end
		if n == 0 and not paradeActive then
			animsLive = false -- every non-parade track was stopped above; parade staff are idle too
		end
	end

	-- Show update: make up to T.startsPerFrame queued starts within `budget` writes. Returns writes.
	function processAnimQueue(budget: number, maxStarts: number?): number
		local writes = 0
		local made = 0
		local cap = maxStarts or T.startsPerFrame
		while startHead <= #startQueue and made < cap and writes + 3 <= budget do
			local rec = startQueue[startHead]
			startQueue[startHead] = false :: any
			startHead += 1
			rec.queued = false
			if rec.want and not rec.reacting and rec.failed < 3 and npcs[rec.model] == rec then
				local id, speed = desiredAnim(rec)
				if id and (not rec.playing or rec.currentId ~= id) then
					made += 1
					writes += 3
					playAnim(rec, id, speed)
				end
			end
		end
		if startHead > #startQueue then
			table.clear(startQueue)
			startHead = 1
		end
		return writes
	end

	-- Crowd reaction: `count` guests closest to `pos` (nil = the camera's animation ranking) jump,
	-- and the ones without a baked pose cheer with their hands up for ~2.5 s. Staggered starts.
	local reactList: { any } = {}
	local reactCands: { any } = {}
	local function byReactD(a: any, b: any): boolean
		return a.reactD < b.reactD
	end
	function crowdReact(now: number, count: number, pos: Vector3?)
		if count <= 0 then
			return
		end
		table.clear(reactCands)
		for _, rec in npcList do
			if rec.canReact and rec.want and rec.playing and not rec.reacting and rec.home then
				rec.reactD = if pos then (rec.home.Position - pos).Magnitude else rec.score
				if not pos or rec.reactD < 40 then
					table.insert(reactCands, rec)
				end
			end
		end
		table.sort(reactCands, byReactD)
		for i = 1, math.min(count, #reactCands) do
			local rec = reactCands[i]
			rec.reactAt = now + rec.seed * 0.35 + (i - 1) * 0.02
			rec.reactUntil = rec.reactAt + 2.2 + rec.seed * 0.8
			rec.jumpAt = rec.reactAt
			if not table.find(reactList, rec) then
				table.insert(reactList, rec)
			end
		end
	end

	-- Show update: switch reacting rigs to the cheer and back (within `budget` writes). Returns writes.
	function updateReactions(now: number, budget: number): number
		local writes = 0
		local i = 1
		while i <= #reactList do
			local rec = reactList[i]
			local done = false
			if not rec.want or npcs[rec.model] ~= rec or (not rec.playing and not rec.reacting) then
				rec.reacting = false
				done = true
			elseif not rec.reacting then
				if now >= rec.reactAt then
					if rec.posed then
						done = true -- a baked pose: it only jumps (updateBounce)
					elseif writes + 3 <= budget then
						writes += 3
						rec.reacting = true
						playAnim(rec, ANIMS.Cheer, 1, true)
					end
				end
			elseif now >= rec.reactUntil and writes + 3 <= budget then
				writes += 3
				rec.reacting = false
				local id, speed = desiredAnim(rec)
				if id then
					playAnim(rec, id, speed)
				end
				done = true
			end
			if done then
				table.remove(reactList, i)
			else
				i += 1
			end
		end
		return writes
	end
end

---------------------------------------------------------------------------------------------------
-- Tables (ClubTable models: TableId, TableType, ServePoint)
---------------------------------------------------------------------------------------------------
local tables: { [Instance]: any } = {}
local tablesById: { [string]: any } = {}
local ordersActive: { [any]: boolean } = {}

local function servePos(t: any): Vector3?
	local sp = t.serve
	if not (sp and sp.Parent) and t.model.Parent then
		-- the table models stream non-atomically: the ServePoint part can arrive after the Model
		local found = t.model:FindFirstChild(NAME_SERVE, true)
		sp = if found and (found:IsA("BasePart") or found:IsA("Attachment")) then found else nil
		t.serve = sp
	end
	if sp and sp.Parent then
		if sp:IsA("BasePart") then
			return sp.Position
		elseif sp:IsA("Attachment") then
			return sp.WorldPosition
		end
	end
	local ok, cf = pcall(function()
		return (t.model :: Model):GetPivot()
	end)
	return if ok then cf.Position else nil
end

local function tableCentre(t: any): Vector3?
	local ok, cf = pcall(function()
		return (t.model :: Model):GetBoundingBox()
	end)
	if ok and typeof(cf) == "CFrame" then
		return cf.Position
	end
	return servePos(t)
end

local clearBottles: (t: any) -> () -- defined with the bottle visuals below

watch(TAG.Table or "ClubTable", function(inst)
	if not inst:IsA("Model") then
		return
	end
	local id = inst:GetAttribute(ATTR.TableId or "TableId")
	if type(id) ~= "string" or id == "" then
		id = inst.Name
	end
	local kind = inst:GetAttribute(ATTR.TableType or "TableType")
	local sp = inst:FindFirstChild(NAME_SERVE, true)
	local t = {
		model = inst,
		id = id,
		kind = if type(kind) == "string" then kind else "Standing",
		serve = if sp and (sp:IsA("BasePart") or sp:IsA("Attachment")) then sp else nil,
		visual = nil :: Model?,
		bottleAt = 0, -- server time the bottles land (a parade may still be carrying them)
		bottleUntil = 0,
		sparkUntil = 0,
		sparkLit = false,
		topCF = nil :: CFrame?,
		conn = nil :: RBXScriptConnection?,
	}
	tables[inst] = t
	tablesById[id] = t
	local function onBottle()
		local at = inst:GetAttribute(ATTR.BottleAt or "BottleAt")
		if type(at) ~= "number" then
			return
		end
		local secs = TCFG.BottleSeconds or 26
		t.bottleAt = at
		t.bottleUntil = at + secs
		t.sparkUntil = at + math.min(secs, 18)
		if t.visual then
			clearBottles(t) -- a new order: rebuild with fresh sparklers
		end
		if workspace:GetServerTimeNow() < t.bottleUntil then
			ordersActive[t] = true
		end
	end
	t.conn = inst:GetAttributeChangedSignal(ATTR.BottleAt or "BottleAt"):Connect(onBottle)
	onBottle() -- streamed in while the bottles are still on the table
end, function(inst)
	local t = tables[inst]
	if t then
		if t.conn then
			t.conn:Disconnect()
		end
		if clearBottles then
			clearBottles(t)
		end
		ordersActive[t] = nil
		tables[inst] = nil
		if tablesById[t.id] == t then
			tablesById[t.id] = nil
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- Bottle-service parade
---------------------------------------------------------------------------------------------------
local isParadeStaff, addParadeMember, removeParadeMember, setMemberSparks, ensureParadePaths, paradeSchedule, paradeStep, restoreParade
do
	local route = {
		folder = nil :: Instance?,
		raw = {} :: { any }, -- { pos, bottom } per WP part, in order
		target = "",
		version = 0,
		conns = {} :: { RBXScriptConnection },
		dirty = true,
	}
	local paradeMembers: { any } = {}
	local paradeDirty = true
	local paradeBuilt = { version = -1, target = "\0", path = "\0" }
	local recruitVersion = -1
	local paradeParts: { BasePart } = {}
	local paradeCFrames: { CFrame } = {}
	local REST = CFrame.new()

	local function vecAttr(inst: Instance, name: string): Vector3?
		local v = inst:GetAttribute(name)
		if typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z then
			return v
		end
		return nil
	end

	-- legacy rigs: WP1..WPn attributes on the NPC (HumanoidRootPart centres)
	local function legacyPoints(model: Model): { Vector3 }?
		local n = math.floor(num(model, "ParadeCount", 0))
		if n < 2 or n > 64 then
			return nil
		end
		local pts: { Vector3 } = {}
		for i = 1, n do
			local v = vecAttr(model, "WP" .. i)
			if not v then
				return nil
			end
			pts[i] = v
		end
		return pts
	end

	local PARADE_POSES = { carryBottle = true, carrySign = true, walkBottle = true, walkSign = true }
	function isParadeStaff(model: Model): boolean
		if model:GetAttribute("Parade") == true or type(model:GetAttribute("ParadeSlot")) == "number" then
			return true
		end
		if type(model:GetAttribute("ParadeCount")) == "number" then
			return true
		end
		local pose = model:GetAttribute("Pose")
		if type(pose) == "string" and PARADE_POSES[pose] then
			return true
		end
		local p = model.Parent
		while p and p ~= workspace do
			if p.Name == NAME_ROUTE then
				return true
			end
			p = p.Parent
		end
		return false
	end

	local function hipHeight(model: Model, hrp: BasePart): number
		local low = math.huge
		for _, name in { "Left Leg", "Right Leg" } do
			local leg = model:FindFirstChild(name)
			if leg and leg:IsA("BasePart") then
				low = math.min(low, leg.Position.Y - leg.Size.Y / 2)
			end
		end
		if low == math.huge then
			return 3
		end
		return math.clamp(hrp.Position.Y - low, 1.5, 5)
	end

	function addParadeMember(rec: any)
		local model = rec.model
		local pose = model:GetAttribute("Pose")
		local m = {
			rec = rec,
			slotKey = num(model, "ParadeSlot", num(model, "ParadeDelay", 1000 + #paradeMembers)),
			slot = 0,
			delay = 0, -- seconds after the parade start this member sets off
			hip = hipHeight(model, rec.hrp),
			legacy = legacyPoints(model),
			pts = {} :: { Vector3 },
			cum = {} :: { number },
			total = 0,
			face = flat(rec.home.LookVector),
			idleCF = rec.home,
			emitters = {} :: { ParticleEmitter },
			hips = {} :: { Motor6D },
			shoulders = {} :: { Motor6D },
			-- carries a bottle / sign in a pose baked into the shoulder C0s: the walk track must not
			-- swing those arms (their Transform is held at rest while walking)
			carry = type(pose) == "string" and PARADE_POSES[pose] == true,
			phase = nil :: string?,
			sparkOn = nil :: boolean?,
			procedural = false,
			retryAt = 0,
			needsWrite = true,
		}
		if m.face.Magnitude < 1e-3 then
			m.face = Vector3.new(0, 0, -1)
		else
			m.face = m.face.Unit
		end
		local stick: BasePart? = nil
		for _, d in model:GetDescendants() do
			if d:IsA("ParticleEmitter") and d:GetAttribute("Kind") == "ParadeSparkler" then
				table.insert(m.emitters, d)
			elseif d:IsA("Motor6D") and (d.Name == "Right Hip" or d.Name == "Left Hip") then
				table.insert(m.hips, d)
			elseif d:IsA("Motor6D") and (d.Name == "Right Shoulder" or d.Name == "Left Shoulder") then
				table.insert(m.shoulders, d)
			elseif d:IsA("BasePart") then
				if string.find(d.Name, "Sparkler") or string.find(d.Name, "Bottle") then
					m.carry = true
					if not stick then
						stick = d
					end
				elseif string.find(d.Name, "Sign") then
					m.carry = true
				end
			end
		end
		if #m.emitters > 0 then
			m.carry = true
		end
		if #m.emitters == 0 and stick then
			-- staff carrying a bottle without a built sparkler: a local one (visual only)
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "ParadeSparklerLocal"
			pe.Enabled = false
			pe.Rate = 60
			pe.Lifetime = NumberRange.new(0.3, 0.7)
			pe.Speed = NumberRange.new(3, 7)
			pe.SpreadAngle = Vector2.new(30, 30)
			pe.EmissionDirection = Enum.NormalId.Top
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.05) })
			pe.Color = ColorSequence.new(Color3.fromRGB(255, 244, 210), Color3.fromRGB(255, 170, 60))
			pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			pe.LightEmission = 1
			pe.Acceleration = Vector3.new(0, -12, 0)
			pe.Parent = stick
			table.insert(m.emitters, pe)
		end
		rec.member = m
		table.insert(paradeMembers, m)
		paradeDirty = true
		npcListDirty = true
		bounceListDirty = true
	end

	function removeParadeMember(rec: any)
		local i = table.find(paradeMembers, rec.member)
		if i then
			table.remove(paradeMembers, i)
		end
		rec.member = nil
		paradeDirty = true
		npcListDirty = true
		bounceListDirty = true
	end

	-- no marked parade staff but a route exists: up to 3 staff waiting near the route start
	local function recruitParadeStaff()
		if recruitVersion == route.version or #route.raw == 0 then
			return
		end
		recruitVersion = route.version
		local start = route.raw[1].pos
		local picks: { any } = {}
		for _, rec in npcs do
			if not rec.member and rec.hrp and rec.home then
				local role = rec.model:GetAttribute(ATTR.Role or "Role")
				local anim = rec.model:GetAttribute(ATTR.Anim or "Anim")
				role = if type(role) == "string" then string.lower(role) else ""
				anim = if type(anim) == "string" then string.lower(anim) else ""
				if (role == "staff" or role == "server" or anim == "serve") and (rec.home.Position - start).Magnitude <= 30 then
					rec.recruitD = (rec.home.Position - start).Magnitude
					table.insert(picks, rec)
				end
			end
		end
		table.sort(picks, function(a, b)
			return a.recruitD < b.recruitD
		end)
		for i = 1, math.min(3, #picks) do
			if picks[i].playing then
				stopAnim(picks[i])
			end
			addParadeMember(picks[i])
		end
	end

	local function readRoute()
		route.dirty = false
		for _, c in route.conns do
			c:Disconnect()
		end
		table.clear(route.conns)
		table.clear(route.raw)
		route.folder, route.target = nil, ""
		for rt in runtimes do
			local f = rt.Parent and rt:FindFirstChild(NAME_ROUTE)
			if f then
				route.folder = f
				break
			end
		end
		local f = route.folder
		if f then
			local t = f:GetAttribute(ATTR.TargetTable or "TargetTable")
			route.target = if type(t) == "string" then t else ""
			for i = 1, 64 do
				local wp = f:FindFirstChild("WP" .. i)
				if not wp then
					break
				end
				if wp:IsA("BasePart") then
					-- floor fallback when the ray below finds nothing: a flat marker lies on the floor,
					-- a block marker stands at HumanoidRootPart height (like the tables' ServePoint)
					local bottom = if wp.Size.Y < 0.6 then wp.Position.Y - wp.Size.Y / 2 else wp.Position.Y - 3
					table.insert(route.raw, { pos = wp.Position, bottom = bottom })
				elseif wp:IsA("Attachment") then
					table.insert(route.raw, { pos = wp.WorldPosition, bottom = wp.WorldPosition.Y })
				else
					break
				end
			end
			local function dirty()
				route.dirty = true
			end
			table.insert(route.conns, f.ChildAdded:Connect(dirty))
			table.insert(route.conns, f.ChildRemoved:Connect(dirty))
			table.insert(route.conns, f.AttributeChanged:Connect(dirty))
			table.insert(route.conns, f.AncestryChanged:Connect(dirty))
		end
		route.version += 1
	end

	local function floorUnder(pos: Vector3, fallbackY: number, params: RaycastParams): Vector3
		local ok, hit = pcall(function()
			return workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), params)
		end)
		local y = fallbackY
		if ok and hit then
			y = hit.Position.Y
		end
		return Vector3.new(pos.X, y, pos.Z)
	end

	-- the part of a polyline that starts `offset` studs along it (at most 90 % into its last leg)
	local function trimFront(points: { Vector3 }, offset: number): { Vector3 }
		local n = #points
		if n < 2 or offset <= 0 then
			return points
		end
		local out: { Vector3 } = {}
		local run = 0
		for i = 2, n do
			local a, b = points[i - 1], points[i]
			local seg = (b - a).Magnitude
			if i == n or run + seg > offset then
				local k = if seg > 1e-3 then math.clamp((offset - run) / seg, 0, 0.9) else 0
				table.insert(out, a:Lerp(b, k))
				for j = i, n do
					table.insert(out, points[j])
				end
				return out
			end
			run += seg
		end
		return points
	end

	local function buildMemberPath(m: any, floorPts: { Vector3 }, dest: Vector3?, centre: Vector3?, faceHint: Vector3?, count: number, routeEndPt: Vector3?)
		local rec = m.rec
		local home = rec.home.Position
		local pts: { Vector3 } = {}
		local gap = PARADE.Gap or 3.4
		m.idleAtHome = true
		m.delay = m.slot * gap / math.max(0.1, PARADE.Speed or 4.2) -- single file behind the leader
		if #floorPts > 0 then
			local up = Vector3.new(0, m.hip, 0)
			local first = floorPts[1] + up
			-- staff built at the table end (the arrival tableau at the route's own table) wait at the
			-- route start instead, queued single file along its first metres (leader in front); they
			-- all set off together. Tested against the route end, not a retargeted table: the tableau
			-- stays where it was built whichever VIP table ordered.
			local routeEnd = (routeEndPt or floorPts[#floorPts]) + up
			local dEnd = math.min((home - routeEnd).Magnitude, if dest then (home - (dest + up)).Magnitude else math.huge)
			local homeNearEnd = dEnd < 12 and dEnd < (home - first).Magnitude
			local legs = floorPts
			if homeNearEnd then
				legs = trimFront(floorPts, (count - 1 - m.slot) * gap)
				m.delay = 0
			elseif (home - first).Magnitude > 1.5 then
				table.insert(pts, home)
			end
			for _, p in legs do
				table.insert(pts, p + up)
			end
			if dest then
				table.insert(pts, dest + up)
			end
			m.idleAtHome = not homeNearEnd
		elseif m.legacy then
			-- per-rig WP attributes (older places): they share the start, so queue there too
			for _, p in trimFront(m.legacy, (count - 1 - m.slot) * gap) do
				table.insert(pts, p)
			end
			m.delay = 0
			m.idleAtHome = false
		end
		local n = #pts
		if n >= 2 then
			local endP = pts[n]
			local dir = flat(endP - pts[n - 1])
			if dir.Magnitude < 1e-3 then
				dir = flat(rec.home.LookVector)
			end
			local face = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(0, 0, -1)
			if faceHint then
				face = faceHint
			elseif centre and #floorPts > 0 then
				local f = flat(centre - endP)
				if f.Magnitude > 0.5 then
					face = f.Unit
				end
			end
			m.face = face
			if #floorPts > 0 and count > 1 then
				-- line up side by side in front of the table
				local right = face:Cross(Vector3.yAxis)
				local k = (m.slot - (count - 1) / 2) * (PARADE.Spread or 2.6)
				if math.abs(k) > 0.05 then
					table.insert(pts, endP + right * k)
					n += 1
				end
			end
			if not m.idleAtHome then
				local d0 = flat(pts[2] - pts[1])
				m.idleCF = if d0.Magnitude > 1e-3 then CFrame.lookAt(pts[1], pts[1] + d0.Unit) else CFrame.new(pts[1])
			else
				m.idleCF = rec.home
			end
		end
		local cum = { 0 }
		for i = 2, n do
			cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
		end
		m.pts, m.cum = pts, cum
		m.total = if n >= 2 then cum[n] else 0
		m.phase = nil
		m.needsWrite = true
	end

	function ensureParadePaths(targetId: string, pathStr: string?)
		if route.dirty then
			readRoute()
		end
		if #paradeMembers == 0 then
			recruitParadeStaff()
		end
		local pathKey = pathStr or ""
		if not paradeDirty and paradeBuilt.version == route.version and paradeBuilt.target == targetId and paradeBuilt.path == pathKey then
			return
		end
		paradeDirty = false
		paradeBuilt.version, paradeBuilt.target, paradeBuilt.path = route.version, targetId, pathKey
		table.sort(paradeMembers, function(a, b)
			return a.slotKey < b.slotKey
		end)
		for i, m in paradeMembers do
			m.slot = i - 1
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ex: { Instance } = {}
		if route.folder then
			table.insert(ex, route.folder)
		end
		for model in npcs do
			table.insert(ex, model)
		end
		if player.Character then
			table.insert(ex, player.Character)
		end
		params.FilterDescendantsInstances = ex
		local routeFloor: { Vector3 } = {}
		for i, w in route.raw do
			routeFloor[i] = floorUnder(w.pos, w.bottom, params)
		end
		local routeEnd = routeFloor[#routeFloor]
		local floorPts = routeFloor
		local t = tablesById[route.target]
		local ordered = if targetId ~= "" and targetId ~= route.target then tablesById[targetId] else nil
		if #route.raw > 0 and targetId ~= "" and targetId ~= route.target then
			-- the server's walk to the ordered table (heights from the floor under each point), else
			-- the same path computed here without the furniture test
			local y = route.raw[1].pos.Y
			local pts = Shared.decodePath and Shared.decodePath(pathStr, y) or nil
			if not pts and ordered and Shared.paradePath then
				local sp = servePos(ordered)
				if sp then
					local raw: { Vector3 } = {}
					for i, w in route.raw do
						raw[i] = w.pos
					end
					pts = Shared.paradePath(raw, sp, Shared.PARADE_MAX_LEG or 60, Shared.PARADE_EXTEND or 48)
				end
			end
			if pts then
				floorPts = {}
				local drop = route.raw[1].pos.Y - route.raw[1].bottom
				for i, p in pts do
					floorPts[i] = floorUnder(p, p.Y - drop, params)
				end
				if ordered then
					t = ordered
				end
			end
		end
		local centre = t and tableCentre(t)
		-- the table's ServePoint faces the table: the staff line up facing the same way
		local faceHint: Vector3? = nil
		if t then
			servePos(t) -- re-resolves t.serve when the ServePoint streamed in late
		end
		local serve = t and t.serve
		if serve and serve.Parent and serve:IsA("BasePart") and #floorPts > 0 then
			local endP = floorPts[#floorPts]
			local look = flat(serve.CFrame.LookVector)
			if look.Magnitude > 0.5 and (flat(serve.Position) - flat(endP)).Magnitude <= 8 then
				faceHint = look.Unit
			end
		end
		for _, m in paradeMembers do
			buildMemberPath(m, floorPts, nil, centre, faceHint, #paradeMembers, routeEnd)
		end
	end

	-- start time + table of the current parade (server attributes, else the fixed fallback schedule)
	function paradeSchedule(now: number): (number, string, string?)
		for rt in runtimes do
			local at = rt:GetAttribute(ATTR.ParadeAt or "ParadeAt")
			if type(at) == "number" and at > 0 then
				local tbl = rt:GetAttribute(ATTR.ParadeTable or "ParadeTable")
				local path = rt:GetAttribute(ATTR.ParadePath or "ParadePath")
				return at, if type(tbl) == "string" then tbl else route.target, if type(path) == "string" then path else nil
			end
		end
		local epoch = 0
		for rt in runtimes do
			local e = rt:GetAttribute(ATTR.ShowEpoch or "ShowEpoch")
			if type(e) == "number" then
				epoch = e
				break
			end
		end
		return Shared.paradeFallbackStart(now, epoch), route.target, nil
	end

	local function paradeSample(m: any, dist: number): (Vector3, Vector3)
		local pts, cum = m.pts, m.cum
		local n = #pts
		dist = math.clamp(dist, 0, m.total)
		for i = 2, n do
			if dist <= cum[i] or i == n then
				local seg = cum[i] - cum[i - 1]
				local a = if seg > 1e-3 then (dist - cum[i - 1]) / seg else 1
				return pts[i - 1]:Lerp(pts[i], math.clamp(a, 0, 1)), pts[i] - pts[i - 1]
			end
		end
		return pts[n], pts[n] - pts[n - 1]
	end

	local function flatLook(pos: Vector3, dir: Vector3, fallback: CFrame): CFrame
		local f = flat(dir)
		if f.Magnitude < 1e-3 then
			return fallback - fallback.Position + pos
		end
		return CFrame.lookAt(pos, pos + f.Unit)
	end

	function setMemberSparks(m: any, on: boolean)
		if m.sparkOn == on then
			return
		end
		m.sparkOn = on
		for _, pe in m.emitters do
			if pe.Parent then
				pe.Enabled = on
			end
		end
	end

	-- RunService.PreSimulation (after the animation step): walk the parade staff. Returns the number
	-- of property writes made (charged to this frame's show budget).
	function paradeStep(): number
		if not paradeActive or #paradeMembers == 0 then
			return 0
		end
		local now = workspace:GetServerTimeNow()
		local t0, targetId, pathStr = paradeSchedule(now)
		if paradeDirty or route.dirty or paradeBuilt.target ~= targetId or paradeBuilt.path ~= (pathStr or "") then
			ensureParadePaths(targetId, pathStr)
		end
		table.clear(paradeParts)
		table.clear(paradeCFrames)
		local speed = PARADE.Speed or 4.2
		local walkAnimSpeed = math.clamp(speed / 14.5, 0.25, 1.2) -- R6 walk: 1.0 = 14.5 studs / s
		local inside = state == "Inside"
		local jointWrites = 0
		for _, m in paradeMembers do
			local rec = m.rec
			local hrp = rec.hrp
			if hrp and hrp.Parent and m.total > 0 then
				local tt = now - t0 - (m.delay or 0)
				local dist, walking, forward, spark, phase = Shared.paradeAt(tt, m.total, speed, PARADE.Hold or 22)
				local cf: CFrame
				if phase == "hold" then
					local pos = m.pts[#m.pts]
					cf = CFrame.lookAt(pos, pos + m.face)
				elseif walking then
					local pos, dir = paradeSample(m, dist)
					if not forward then
						dir = -dir
					end
					if m.procedural then
						pos += Vector3.new(0, 0.1 * math.abs(math.sin(now * 6.5)), 0)
					end
					cf = flatLook(pos, dir, rec.home)
				else
					cf = if m.idleAtHome then rec.home else m.idleCF
				end
				if phase ~= m.phase then
					m.phase = phase
					m.needsWrite = true
					jointWrites += 3 -- track start (TimePosition / first-load Looped + Priority)
					if walking then
						m.procedural = not playAnim(rec, ANIMS.Walk, walkAnimSpeed)
						m.retryAt = now + 1
					else
						m.procedural = false
						if rec.animId then
							playAnim(rec, rec.animId, rec.animSpeed)
						else
							playAnim(rec, ANIMS.Idle, 1)
						end
						for _, hip in m.hips do
							if hip.Parent then
								hip.Transform = REST
							end
						end
					end
				elseif walking and m.procedural and now >= m.retryAt then
					m.retryAt = now + 1
					m.procedural = not playAnim(rec, ANIMS.Walk, walkAnimSpeed)
				end
				if walking or m.needsWrite then
					m.needsWrite = false
					table.insert(paradeParts, hrp)
					table.insert(paradeCFrames, cf)
					rec.moved = true
				end
				if walking and m.procedural then
					-- no walk track: swing the hips (R6 hip axes are mirrored: one angle = opposite legs)
					local swing = CFrame.Angles(0, 0, 0.55 * math.sin(now * 6.5))
					for _, hip in m.hips do
						if hip.Parent then
							hip.Transform = swing
							jointWrites += 1
						end
					end
				end
				if walking and m.carry then
					-- PreSimulation runs after the animation step: hold the carrying arms in their baked
					-- pose (bottle / sign held up) while the walk track swings the legs
					for _, sh in m.shoulders do
						if sh.Parent then
							sh.Transform = REST
							jointWrites += 1
						end
					end
				end
				setMemberSparks(m, spark and inside)
			end
		end
		if #paradeParts > 0 then
			local ok, err = pcall(function()
				workspace:BulkMoveTo(paradeParts, paradeCFrames, Enum.BulkMoveMode.FireCFrameChanged)
			end)
			if not ok then
				warnf("parade BulkMoveTo failed:", err)
			end
		end
		return jointWrites + #paradeParts
	end

	function restoreParade()
		table.clear(paradeParts)
		table.clear(paradeCFrames)
		for _, m in paradeMembers do
			local rec = m.rec
			setMemberSparks(m, false)
			for _, hip in m.hips do
				if hip.Parent then
					hip.Transform = REST
				end
			end
			if rec.playing then
				stopAnim(rec)
			end
			if rec.moved and rec.hrp and rec.hrp.Parent and rec.home then
				table.insert(paradeParts, rec.hrp)
				table.insert(paradeCFrames, rec.home)
			end
			rec.moved = false
			m.phase = nil
			m.needsWrite = true
			m.procedural = false
		end
		if #paradeParts > 0 then
			pcall(function()
				workspace:BulkMoveTo(paradeParts, paradeCFrames, Enum.BulkMoveMode.FireCFrameChanged)
			end)
		end
	end
end

-- NPC registry ----------------------------------------------------------------------------------------
watch(TAG.NPC, function(inst)
	if not inst:IsA("Model") then
		return
	end
	local model = inst :: Model
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		hrp = model.PrimaryPart
	end
	local root = if hrp and hrp:IsA("BasePart") then hrp else nil
	local home = if root then root.CFrame else nil
	local seed = num(model, ATTR.AnimOffset or "AnimOffset", -1)
	if seed < 0 or seed >= 1 then
		seed = if home then Shared.hash(home.Position.X, home.Position.Z) else 0.5
	end
	local id, speed = Shared.animFor(
		model:GetAttribute(ATTR.Anim or "Anim"),
		model:GetAttribute("AnimIndex"),
		model:GetAttribute("Pose"),
		seed
	)
	local role = model:GetAttribute(ATTR.Role or "Role")
	local guest = type(role) == "string" and string.lower(role) == "guest"
	local poseAttr = model:GetAttribute("Pose")
	local posed = type(poseAttr) == "string" and poseAttr ~= ""
	local poseL = if type(poseAttr) == "string" then string.lower(poseAttr) else ""
	local animAttr = model:GetAttribute(ATTR.Anim or "Anim")
	local animName = if type(animAttr) == "string" then string.lower(animAttr) else ""
	local seated = animName == "sit" or string.find(poseL, "sit", 1, true) ~= nil or string.find(poseL, "perch", 1, true) ~= nil
	local rec = {
		model = model,
		hrp = root,
		home = home,
		seed = seed,
		animId = id,
		animSpeed = speed * math.clamp(num(model, ATTR.AnimSpeed or "AnimSpeed", 1), 0.2, 3),
		tracks = {} :: { [string]: AnimationTrack },
		current = nil :: AnimationTrack?,
		currentId = nil :: string?,
		curSpeed = 1,
		playing = false,
		pendingOffset = false,
		offsetTries = 0,
		failed = 0,
		animatorWait = 0,
		want = false,
		score = 0,
		interior = nil :: boolean?,
		group = nil :: string?, -- ZONE_GROUP of the rig's room (set with interior)
		bounce = math.clamp(num(model, "Bounce", 0), 0, 1.5),
		moved = false,
		member = nil :: any,
		-- crowd behaviour
		danceAnim = danceIds[id or ""] == true, -- follows the BPM, bobs on the beat (mid / high)
		posed = posed,
		canReact = guest and not seated, -- jumps / cheers on drops
		nightId = nil :: string?, -- dance of an idle guest at night
		nightNeed = nil :: number?, -- nightLevel() it needs (1 night, 2 peak)
		nightBounce = nil :: number?, -- hop height of a posed guest at night
		queued = false,
		reacting = false,
		reactAt = 0,
		reactUntil = 0,
		reactD = 0,
		jumpAt = -1e9,
		lastH = 0,
		noOffset = false,
	}
	-- night density: inside, more guests dance (free-standing / chatting ones) or bounce on the beat
	-- (the ones holding a phone / drink in a baked pose); a third from nightfall, most at the peak
	local zoneK = Shared.zoneKey(model:GetAttribute(ATTR.Zone or "Zone"))
	local indoor = zoneK ~= nil and zoneK ~= "Near" and zoneK ~= "Outside" and zoneK ~= "Forecourt" and zoneK ~= "Street"
	if guest and indoor and not seated and (animName == "idle" or animName == "drink") then
		local h = Shared.hash(seed * 97.1, 3.7)
		if h < 0.8 then
			rec.nightNeed = if h < 0.35 then 1 else 2
			if not posed or poseL == "chat" then
				rec.nightId = if h < 0.4 then ANIMS.Dance[1] else ANIMS.Dance[2]
			elseif rec.bounce <= 0 then
				rec.nightBounce = 0.25 + 0.2 * h
			end
		end
	end
	npcs[model] = rec
	npcListDirty = true
	bounceListDirty = true
	if root and home and isParadeStaff(model) then
		addParadeMember(rec)
	end
end, function(inst)
	local rec = npcs[inst :: Model]
	if rec then
		stopAnim(rec)
		if rec.member then
			setMemberSparks(rec.member, false)
			removeParadeMember(rec)
		end
		npcs[inst :: Model] = nil
		npcListDirty = true
	bounceListDirty = true
	end
end)

---------------------------------------------------------------------------------------------------
-- Show helpers
---------------------------------------------------------------------------------------------------
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

local function scale(c: Color3, k: number): Color3
	k = math.clamp(k, 0, 1.5)
	return Color3.new(math.min(1, c.R * k), math.min(1, c.G * k), math.min(1, c.B * k))
end

local function differs(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) > 0.03
end

-- per-frame show state (computed once per frame)
local F = {
	t = 0,
	clk = nil :: any,
	pal = Shared.Palettes[1],
	energy = 0.3,
	env = 0,
	downbeat = false,
	drop = false, -- drop patterns (a real drop, or the live "groove")
	realDrop = false, -- a real drop section (strobes, blinders, logo flash, flames)
	groove = false,
	build = false,
	breakdown = false,
	intro = false,
	variant = 0,
	logoFlash = 0,
	logoOffset = 0,
	live = false, -- following real music
	bpm = 126,
	beatSec = 60 / 126,
	buildProgress = 0,
	countdown = 0, -- LED-wall countdown digit (0 = none)
	dropT = -1e9, -- os.clock() of the last drop moment
	dropAge = 1e9,
	fanK = 0, -- laser fan after a drop (1 = on)
	burst = false, -- strobe / blinder burst right after a drop
	-- cues (what the stage FX should do now; the tier / room decide what is allowed)
	cue = { coldSpark = false, flame = false, lowFog = false, mirror = false, sparkler = false },
}

local burstFX: (string) -> () -- CO2 / confetti burst (effects section)
local dropMoment: (number) -> ()

local computeFrame: (number, number, number) -> ()
do
local clkBuf = {} -- reused every frame (no per-frame garbage)
local liveClk = {}
local lastClockBar = -1
local lastDropBar = -1
local lastLiveBar = -1
local lastBeatN = -1

-- live show (ClubMusicShared): sections from the loudness, beat from the onsets
local LS = {
	on = false,
	wantSince = -1e9,
	offSince = -1e9,
	phase = 0, -- continuous beat count, phase-locked to the onsets
	lastT = 0,
	mid = 0, -- 1.2 s loudness average
	slow = 0, -- 8 s loudness average
	midRef = 0,
	midRefT = 0,
	rising = false,
	section = "groove",
	secT = 0,
	secBeat0 = 0,
	quietMin = 1,
	quietT = -1e9,
	buildT = -1e9,
	drops = 0,
}
local LIVE_SECTIONS = {
	intro = { name = "intro", energy = 0.3, palette = 1 },
	build = { name = "build", energy = 0.6, palette = 2 },
	drop = { name = "drop", energy = 1, palette = 3 },
	breakdown = { name = "breakdown", energy = 0.35, palette = 4 },
	groove = { name = "groove", energy = 0.7, palette = 1 },
}

local function setLiveSection(name: string, t: number, force: boolean?)
	if LS.section == name and not force then
		return
	end
	LS.section = name
	LS.secT = t
	LS.secBeat0 = math.floor(LS.phase + 0.5)
	if name == "build" then
		LS.buildT = t
	elseif name == "breakdown" then
		LS.quietMin = LS.mid
	end
end

-- live or clock? Live after 1.5 s of audible music with onsets, back to the clock after 3 s without
local function updateLiveMode(now: number): boolean
	local liveNow = CM ~= nil and CM ~= false and cm("isLive", false) == true and now - Live.onsetT < 3
	if liveNow then
		LS.offSince = -1e9
		if not LS.on then
			if LS.wantSince < -1e8 then
				LS.wantSince = now
			elseif now - LS.wantSince >= 1.5 then
				LS.on = true
				LS.lastT = now
				LS.phase = if F.clk then F.clk.beat else 0 -- continuity from the clock
				LS.mid, LS.slow = 0.4, 0.4
				setLiveSection("groove", now, true)
				Live.dropPending = false
			end
		end
	else
		LS.wantSince = -1e9
		if LS.on then
			if LS.offSince < -1e8 then
				LS.offSince = now
			elseif now - LS.offSince >= 3 then
				LS.on = false
				lastClockBar, lastDropBar = -1, -1
			end
		end
	end
	return LS.on
end

local function computeLiveFrame(now: number, serverT: number, epoch: number)
	local dt = math.clamp(now - LS.lastT, 0, 0.25)
	LS.lastT = now
	local bpmRaw = cm("bpm", 126)
	local bpm = math.clamp(if type(bpmRaw) == "number" and bpmRaw == bpmRaw then bpmRaw else 126, 80, 180)
	local prev = LS.phase
	LS.phase += dt * bpm / 60
	if Live.onsets ~= Live.seen then
		Live.seen = Live.onsets
		-- pull the phase toward the onset's beat (never backwards: patterns count whole beats)
		local err = math.floor(LS.phase + 0.5) - LS.phase
		LS.phase = math.max(prev, LS.phase + err * 0.35)
	end
	local lvlRaw = cm("level", 0)
	local lvl = math.clamp(if type(lvlRaw) == "number" and lvlRaw == lvlRaw then lvlRaw else 0, 0, 1)
	LS.mid += (lvl - LS.mid) * (1 - math.exp(-dt / 1.2))
	LS.slow += (lvl - LS.slow) * (1 - math.exp(-dt / 8))
	if now - LS.midRefT >= 1 then
		LS.rising = LS.mid > LS.midRef + 0.012
		LS.midRef, LS.midRefT = LS.mid, now
	end
	local beatSec = 60 / bpm
	-- section state machine
	if Live.dropPending then
		Live.dropPending = false
		if now - Live.dropSeenT < 1 then -- a drop reported while we were not looking is stale
			LS.drops += 1
			setLiveSection("drop", now, true)
			dropMoment(now)
		end
	end
	local sName = LS.section
	local inSec = now - LS.secT
	if sName == "drop" then
		if inSec > 64 * beatSec or (inSec > 16 * beatSec and LS.mid < LS.slow * 0.7) then
			setLiveSection("groove", now)
		end
	else
		local quiet = LS.slow > 0.06 and LS.mid < LS.slow * 0.62
		if quiet then
			LS.quietT = now
		end
		if sName == "breakdown" then
			LS.quietMin = math.min(LS.quietMin, LS.mid)
			if LS.rising and LS.mid > LS.quietMin + 0.1 then
				setLiveSection("build", now)
			elseif now - LS.quietT > 4 and LS.mid >= LS.slow * 0.85 then
				setLiveSection("groove", now)
			end
		elseif sName == "build" then
			if inSec > 24 then
				setLiveSection("groove", now) -- the drop never came
			elseif quiet and not LS.rising and inSec > 3 then
				setLiveSection("breakdown", now)
			end
		elseif quiet then
			setLiveSection("breakdown", now)
		else
			local want = if LS.mid > 0.42 then "groove" else "intro"
			if want ~= sName and inSec > 8 then
				setLiveSection(want, now)
			end
		end
	end
	sName = LS.section
	local sec = LIVE_SECTIONS[sName] or LIVE_SECTIONS.groove
	local rel = math.max(0, LS.phase - LS.secBeat0)
	local clk = liveClk
	clk.beat = LS.phase
	clk.showBeat = LS.phase
	clk.frac = LS.phase % 1
	clk.beatInBar = rel % 4
	clk.bar = math.floor(rel / 4)
	local progress = 0
	if sName == "build" then
		progress = math.clamp((now - LS.buildT) / 12, 0, 1)
		clk.sectionBars = 8
		clk.barInSection = math.min(7, math.floor(progress * 8))
	else
		clk.sectionBars = 16
		clk.barInSection = math.floor(rel / 4)
	end
	local energy
	if sName == "drop" then
		energy = 1
		sec.palette = if LS.drops % 2 == 1 then 3 else 5
	elseif sName == "build" then
		energy = 0.55 + 0.45 * progress
	elseif sName == "breakdown" then
		energy = 0.3
	elseif sName == "groove" then
		energy = 0.55 + 0.4 * math.clamp(LS.mid * 1.4, 0, 1)
		sec.palette = if LS.drops % 2 == 0 then 1 else 3
	else
		energy = 0.3 + 0.3 * math.clamp(LS.mid * 1.5, 0, 1)
	end
	sec.energy = energy
	clk.section = sec
	F.clk = clk
	F.t = serverT - epoch
	F.pal = Shared.Palettes[sec.palette] or Shared.Palettes[1]
	F.intro = sName == "intro"
	F.build = sName == "build"
	F.realDrop = sName == "drop"
	F.groove = sName == "groove"
	F.drop = F.realDrop or F.groove
	F.breakdown = sName == "breakdown"
	F.energy = energy
	F.bpm, F.beatSec = bpm, beatSec
	F.buildProgress = progress
	-- kick envelope from the real onsets (the loudness keeps a floor under it)
	F.env = math.max(Live.onsetK * math.exp(-(now - Live.onsetT) * 6), 0.3 * LS.mid)
	F.downbeat = clk.beatInBar < 1
	F.variant = math.floor(clk.bar / 4) % 3
	F.logoFlash = (F.realDrop and clk.beatInBar < 0.5) and 1 or 0
	F.logoOffset = math.floor(F.t * (F.breakdown and 5 or 8))
	F.countdown = if F.build and progress >= 0.35 then 4 - math.floor(clk.beatInBar) else 0
	local cue = F.cue
	local sinceDrop = now - F.dropT
	cue.coldSpark = sinceDrop < 8 * beatSec
	cue.flame = F.realDrop and clk.barInSection < 4 and ((clk.beatInBar < 0.32) or (clk.beatInBar >= 2 and clk.beatInBar < 2.32))
	cue.lowFog = F.breakdown
	cue.mirror = F.breakdown or F.intro
	cue.sparkler = F.breakdown
	-- extra CO2 every 8 bars of a long drop
	if F.realDrop and clk.bar ~= lastLiveBar then
		if clk.bar > 0 and clk.bar % 8 == 0 then
			burstFX("co2")
		end
	end
	lastLiveBar = clk.bar
end

local function computeClockFrame(now: number, serverT: number, epoch: number)
	local clk = Shared.clock(serverT, epoch, nil, clkBuf)
	local sec = clk.section
	F.clk = clk
	F.t = serverT - epoch
	F.pal = Shared.Palettes[sec.palette] or Shared.Palettes[1]
	F.intro = sec.name == "intro"
	F.build = sec.name == "build"
	F.drop = sec.name == "drop"
	F.realDrop = F.drop
	F.groove = false
	F.breakdown = sec.name == "breakdown"
	local e = sec.energy
	local progress = clk.barInSection / math.max(1, clk.sectionBars)
	if F.build then
		e = sec.energy + (1 - sec.energy) * progress
	end
	F.energy = e
	F.bpm, F.beatSec = Shared.BPM, 60 / Shared.BPM
	F.buildProgress = if F.build then progress else 0
	F.env = math.exp(-clk.frac * 5) -- kick envelope
	F.downbeat = clk.beatInBar < 1
	F.variant = math.floor(clk.bar / 4) % 3
	F.logoFlash = (F.drop and clk.beatInBar < 0.5) and 1 or 0
	F.logoOffset = math.floor(F.t * (F.breakdown and 5 or 8))
	-- countdown 8..1 over the last two bars of a build (lands on the drop)
	local last2 = clk.sectionBars - 2
	F.countdown = if F.build and clk.barInSection >= last2
		then math.clamp(8 - math.floor((clk.barInSection - last2) * 4 + clk.beatInBar), 1, 8)
		else 0
	-- drop moment on the first beat of a drop section; CO2 on the other CO2 bars
	local cues = Shared.Cues
	if clk.bar ~= lastClockBar then
		local fresh = lastClockBar >= 0
		lastClockBar = clk.bar
		if F.drop and clk.barInSection == 0 and clk.beatInBar < 1 and lastDropBar ~= clk.bar then
			lastDropBar = clk.bar
			dropMoment(now)
		elseif fresh and cues.CO2[clk.bar] then
			burstFX("co2")
		end
	end
	local cue = F.cue
	local bar = clk.bar
	local sparkBars = 0
	if cues.ColdSpark then
		for b = math.max(0, bar - 3), bar do
			local len = cues.ColdSpark[b]
			if type(len) == "number" and bar < b + len then
				sparkBars = len
			end
		end
	end
	cue.coldSpark = sparkBars > 0
	cue.flame = cues.Flame ~= nil and cues.Flame[bar] == true
		and ((clk.beatInBar < 0.32) or (clk.beatInBar >= 2 and clk.beatInBar < 2.32))
	cue.lowFog = cues.LowFog ~= nil and Shared.inRanges(bar, cues.LowFog)
	cue.mirror = cues.MirrorBall ~= nil and Shared.inRanges(bar, cues.MirrorBall)
	cue.sparkler = bar >= cues.SparklerFrom and bar < cues.SparklerTo
end

function computeFrame(now: number, serverT: number, epoch: number)
	F.live = updateLiveMode(now)
	if F.live then
		computeLiveFrame(now, serverT, epoch)
	else
		computeClockFrame(now, serverT, epoch)
	end
	F.dropAge = now - F.dropT
	F.fanK = if F.dropAge < 4 * F.beatSec then 1 else 0
	F.burst = F.dropAge < 2 * F.beatSec
	bpmK = if F.live then math.clamp(math.floor(F.bpm / 126 * 20 + 0.5) / 20, 0.85, 1.25) else 1
	-- bus for ClubDance
	Bus.section = if F.groove then "groove" else F.clk.section.name
	Bus.live = F.live
	Bus.bpm = F.bpm
	Bus.energy = F.energy
	Bus.countdown = F.countdown
	local beatN = math.floor(F.clk.beat)
	if beatN ~= lastBeatN then
		lastBeatN = beatN
		Bus.beatAt = now
		Bus.beatSerial = (Bus.beatSerial or 0) + 1
	end
end
end

---------------------------------------------------------------------------------------------------
-- LED wall overlays (countdown, DROP, banners, now playing, photo moment)
---------------------------------------------------------------------------------------------------
local WALL_COLS = 32
local OV = {
	mode = nil :: string?, -- photo | flash | drop | count | msg | np
	digit = nil :: { string }?, -- glyph of the big digit
	colour = Color3.new(1, 1, 1),
	bg = Color3.new(0, 0, 0),
	cols = nil :: { { boolean } }?,
	offset = 0,
	progress = 0,
	frame = false, -- photo: framed logo
	twinkle = 0,
}
local DROP_COLS = Shared.textColumns("DROP!")
local GOLD = Color3.fromRGB(255, 206, 110)
local updateNowPlaying: (number) -> ()
local computeOverlay: (number, number) -> ()
do
local NP = { title = "", text = "", cols = nil :: { { boolean } }?, start = -1e9, nextT = 0, pass = 0 }
local MSG_COLOURS = {
	vip = { Color3.fromRGB(255, 206, 110), Color3.fromRGB(60, 30, 4) },
	birthday = { Color3.fromRGB(255, 120, 200), Color3.fromRGB(50, 8, 40) },
	welcome = { Color3.fromRGB(80, 230, 255), Color3.fromRGB(4, 30, 50) },
}

-- Now Playing (zone tick): a new track scrolls its title once; calm sections repeat it every 75 s
function updateNowPlaying(now: number)
	local title, artist = cm("nowPlaying", nil)
	if type(title) ~= "string" or title == "" then
		NP.title = ""
		return
	end
	if title ~= NP.title then
		NP.title = title
		local a = if type(artist) == "string" and artist ~= "" then "  -  " .. artist else ""
		local text = Shared.ledText and Shared.ledText(title .. a, 44) or ""
		NP.text = if text ~= "" then "~ NOW PLAYING   " .. text .. " ~" else "~ NOW PLAYING ~"
		NP.cols = Shared.textColumns(NP.text)
		NP.start = now
		NP.pass = (#NP.cols + WALL_COLS) / 10
		NP.nextT = now + 75
	elseif now >= NP.nextT and now - NP.start > NP.pass and (F.intro or F.breakdown or F.groove) then
		NP.start = now
		NP.nextT = now + 75
	end
end

function computeOverlay(now: number, serverT: number)
	OV.mode = nil
	OV.frame = false
	OV.digit = nil
	local pt = now - (Bus.photoAt or -1e9)
	if pt >= 0 and pt < 4.8 then
		OV.mode = "photo"
		if pt < 2.7 then
			OV.digit = Shared.Glyphs[tostring(3 - math.floor(pt / 0.9))]
			OV.colour = Color3.new(1, 1, 1)
		elseif pt < 2.95 then
			OV.mode = "flash"
		else
			OV.frame = true
		end
		return
	end
	local age = F.dropAge
	if age < 0.18 then
		OV.mode = "flash"
		return
	elseif age < 1.8 and F.realDrop then
		OV.mode = "drop"
		return
	end
	if F.countdown > 0 then
		OV.mode = "count"
		OV.digit = Shared.Glyphs[tostring(F.countdown)]
		OV.colour = if F.clk.frac < 0.5 then Color3.new(1, 1, 1) else F.pal[3]
		OV.progress = F.buildProgress
		return
	end
	if wallMsg.cols and serverT >= wallMsg.at and serverT < wallMsg.at + wallMsg.dur then
		OV.mode = "msg"
		OV.cols = wallMsg.cols
		OV.offset = math.floor((serverT - wallMsg.at) * 8)
		local c = MSG_COLOURS[wallMsg.kind] or MSG_COLOURS.vip
		OV.colour, OV.bg = c[1], c[2]
		OV.twinkle = math.floor(now * 6)
		return
	end
	if NP.cols and NP.title ~= "" and now - NP.start < NP.pass and not F.build then
		OV.mode = "np"
		OV.cols = NP.cols
		OV.offset = math.floor((now - NP.start) * 10)
		return
	end
end
end

dropMoment = function(now: number)
	F.dropT = now
	Bus.dropAt = now
	Bus.dropSerial = (Bus.dropSerial or 0) + 1
	burstFX("co2")
	burstFX("confetti")
	if state == "Inside" and spotsRoom ~= "" then
		crowdReact(now, T.reactions or 10, nil)
	end
end

local itemColour
do
	local TEXT_SCROLL = Shared.textColumns("CLUB OCEAN   ")
	local TEXT_LOGO = Shared.textColumns("OCEAN")
	local WALL_ROWS = 11
	local TEXT_TOP_ROW = 8 -- glyph row 1 sits on wall Row 8 (Row 0 = bottom)

	local function textPixel(cols: { { boolean } }, c: number, r: number, offset: number, wrap: boolean): boolean
		local gr = TEXT_TOP_ROW - r + 1
		if gr < 1 or gr > 7 then
			return false
		end
		local idx
		if wrap then
			idx = (c + offset) % (#cols + WALL_COLS) + 1 - WALL_COLS
		else
			idx = c - offset + 1
		end
		local column = cols[idx]
		return column ~= nil and column[gr] == true
	end

	-- Colour for one item ---------------------------------------------------------------------------------
	local function floorColour(rec: any): Color3
		local clk, pal = F.clk, F.pal
		local c, r = rec.col, rec.row
		local cx, cy = (c - 5.5) / 6, (r - 4.5) / 5
		local d = math.sqrt(cx * cx + cy * cy)
		if F.intro then
			local k = 0.5 + 0.5 * math.sin(c * 0.55 + r * 0.3 - F.t * 0.9)
			return scale(pal[1]:Lerp(pal[2], k), 0.35 + 0.3 * F.env)
		elseif F.build then
			local sub = (clk.barInSection >= clk.sectionBars - 2) and 4 or 2
			local stripe = (c + r + math.floor(clk.beat * sub)) % 4 == 0
			if stripe then
				return scale(pal[3], 0.6 + 0.4 * F.energy)
			end
			return scale(pal[1], 0.15 + 0.35 * F.energy * F.env)
		elseif F.drop then
			if F.variant == 0 then
				local on = (c + r + math.floor(clk.beat)) % 2 == 0
				return if on then scale(pal[1], 0.5 + 0.6 * F.env) else scale(pal[2], 0.25 + 0.3 * F.env)
			elseif F.variant == 1 then
				local ring = math.abs(d - clk.frac * 1.6)
				local k = math.exp(-ring * ring * 30)
				return pal[1]:Lerp(pal[3], k * F.env):Lerp(BLACK, 0.6 * (1 - k))
			else
				local sweep = ((c - r) * 0.5 + clk.beat * 2) % 6
				return if sweep < 1.5 then scale(pal[3], 0.9) else scale(pal[2], 0.3 + 0.4 * F.env)
			end
		end
		-- breakdown: slow breathing with a rotating highlight
		local ang = math.atan2(cy, cx)
		local hi = 0.5 + 0.5 * math.cos(ang - F.t * 0.8)
		return scale(pal[1]:Lerp(pal[2], hi), 0.25 + 0.25 * math.sin(F.t * 1.3) ^ 2 + 0.2 * hi)
	end

	local function wallColour(rec: any): Color3
		local clk, pal = F.clk, F.pal
		local c, r = rec.col, rec.row
		if F.breakdown or F.intro then
			if textPixel(TEXT_SCROLL, c, r, F.logoOffset, true) then
				return if F.breakdown then Color3.fromRGB(255, 214, 150) else WHITE
			end
			local k = 0.5 + 0.5 * math.sin(c * 0.25 + F.t * 0.6)
			return scale(pal[2]:Lerp(pal[1], k), 0.28 + 0.12 * (r / WALL_ROWS))
		elseif F.build then
			local last = clk.barInSection >= clk.sectionBars - 2
			if last and (clk.beat * 4) % 1 < 0.5 then
				return WHITE
			end
			local h = (math.sin(c * 0.7 + clk.beat * 3.1) * 0.5 + 0.5) * WALL_ROWS * (0.4 + 0.6 * F.energy)
			return if r < h then pal[1]:Lerp(pal[3], r / WALL_ROWS) else scale(pal[2], 0.12)
		end
		-- drop: logo flash on every bar downbeat, EQ / rings otherwise
		if F.logoFlash > 0 then
			local offset = math.floor((WALL_COLS - #TEXT_LOGO) / 2)
			return if textPixel(TEXT_LOGO, c, r, offset + 1, false) then WHITE else BLACK
		end
		if F.variant == 1 then
			local dx, dy = (c - 15.5) / 16, (r - 5) / 5.5
			local ring = math.abs(math.sqrt(dx * dx + dy * dy) - clk.frac * 1.5)
			return pal[1]:Lerp(pal[3], math.exp(-ring * ring * 25))
		end
		local h = (Shared.hash(c, math.floor(clk.beat * 2)) * 0.7 + 0.3 * F.env) * WALL_ROWS
		return if r < h then pal[1]:Lerp(pal[2], r / WALL_ROWS) else scale(pal[2], 0.08)
	end

	-- LED wall overlay pixel: a colour, or nil + dim (show the pattern dimmed behind scrolling text)
	local DIGIT_X0 = 11 -- big digits: 10 x 11 pixels in the middle of the 32 x 11 wall
	local function bigDigit(glyph: { string }?, c: number, r: number): boolean
		if not glyph or c < DIGIT_X0 or c > DIGIT_X0 + 9 then
			return false
		end
		local gc = math.floor((c - DIGIT_X0) / 2) + 1
		local gr = math.clamp(math.floor((10 - r) * 7 / 11) + 1, 1, 7)
		return string.sub(glyph[gr], gc, gc) == "#"
	end
	local function overlayColour(rec: any): (Color3?, boolean)
		local mode = OV.mode
		local c, r = rec.col, rec.row
		if mode == "flash" then
			return WHITE, false
		elseif mode == "photo" then
			if OV.frame then
				if r <= 0 or r >= WALL_ROWS - 1 or c <= 0 or c >= WALL_COLS - 1 then
					return GOLD, false
				end
				local offset = math.floor((WALL_COLS - #TEXT_LOGO) / 2)
				return if textPixel(TEXT_LOGO, c, r, offset + 1, false) then WHITE else BLACK, false
			end
			return if bigDigit(OV.digit, c, r) then OV.colour else BLACK, false
		elseif mode == "count" then
			if bigDigit(OV.digit, c, r) then
				return OV.colour, false
			end
			if r == 0 and c < OV.progress * WALL_COLS then
				return scale(F.pal[3], 0.7), false
			end
			return scale(F.pal[1], 0.06 + 0.14 * F.env), false
		end
		if rec.side then
			-- the side wall samples every other pixel: text would be unreadable there
			if mode == "msg" then
				local tw = Shared.hash(c * 3.1 + r, OV.twinkle) > 0.8
				return if tw then OV.colour else scale(OV.bg, 1.6), false
			end
			return nil, false
		end
		if mode == "drop" then
			if textPixel(DROP_COLS, c, r, 1, false) then
				return if F.clk.frac < 0.5 then WHITE else F.pal[3], false
			end
			return nil, false
		elseif mode == "msg" then
			if OV.cols and textPixel(OV.cols, c, r, OV.offset, true) then
				return OV.colour, false
			end
			if Shared.hash(c * 7.3 + r * 1.7, OV.twinkle) > 0.965 then
				return scale(OV.colour, 0.8), false -- sparkles around the banner
			end
			return OV.bg, false
		elseif mode == "np" then
			if OV.cols and textPixel(OV.cols, c, r, OV.offset, true) then
				return WHITE, false
			end
			return nil, r >= 1 and r <= 9
		end
		return nil, false
	end

	-- family of an LED kind this script has no pattern for: "wall" (pixel matrix with Row / Col),
	-- "chase" (strip with Index / Count) or "" (static, left alone). Cached per kind.
	local familyCache: { [string]: string } = {}
	local function genericFamily(kind: string): string
		local f = familyCache[kind]
		if f then
			return f
		end
		local k = string.lower(kind)
		if string.find(k, "wall", 1, true) or string.find(k, "screen", 1, true) or string.find(k, "pixel", 1, true) or string.find(k, "matrix", 1, true) then
			f = "wall"
		elseif string.find(k, "strip", 1, true) or string.find(k, "edge", 1, true) or string.find(k, "rim", 1, true) or string.find(k, "chase", 1, true) or string.find(k, "led", 1, true) or string.find(k, "table", 1, true) then
			f = "chase"
		else
			f = ""
		end
		familyCache[kind] = f
		return f
	end

	function itemColour(rec: any): Color3?
		local kind = rec.kind
		local clk, pal = F.clk, F.pal
		if kind == "Floor" then
			return floorColour(rec)
		elseif kind == "Wall" then
			if OV.mode then
				local oc, dim = overlayColour(rec)
				if oc then
					return oc
				elseif dim then
					return scale(wallColour(rec), 0.3)
				end
			end
			return wallColour(rec)
		elseif kind == "Ceiling" then
			if F.drop then
				local on = (rec.col + math.floor(clk.beat * 2)) % 3 == 0
				return if on then scale(pal[2], 0.8) else scale(pal[1], 0.12)
			end
			local k = 0.5 + 0.5 * math.sin(rec.col * 0.5 + rec.row * 0.4 + F.t * 0.5)
			return scale(pal[1]:Lerp(pal[2], k), 0.18 + 0.2 * F.energy)
		elseif kind == "Booth" then
			local on = (rec.col + rec.row + math.floor(clk.beat * 2)) % 4 == 0
			return if on then pal[3] else scale(pal[1], 0.35 + 0.5 * F.env * F.energy)
		elseif kind == "Tunnel" then
			local head = (F.t * 7) % rec.count
			local dist = (rec.index - head) % rec.count
			return if dist < 1.5 then WHITE else scale(Color3.fromRGB(40, 220, 255):Lerp(Color3.fromRGB(150, 60, 255), rec.index / rec.count), 0.45)
		elseif kind == "Column" then
			local on = (rec.index + math.floor(clk.beat)) % 4 == 0
			return if on then pal[3] else scale(pal[1], 0.4 + 0.4 * F.env)
		elseif kind == "Fascia" or kind == "VIPEdge" or kind == "BarFront" or kind == "HipHopStrip" then
			local speed = (kind == "BarFront") and 1 or 4
			local head = (clk.beat * speed / 4) % rec.count
			local dist = (rec.index - head) % rec.count
			local baseC = pal[1]
			if kind == "BarFront" then
				baseC = Color3.fromRGB(255, 160, 60):Lerp(pal[1], F.drop and 0.5 or 0.15)
			elseif kind == "VIPEdge" then
				baseC = Color3.fromRGB(255, 60, 170)
			elseif kind == "HipHopStrip" then
				baseC = Color3.fromRGB(255, 60, 40):Lerp(Color3.fromRGB(255, 160, 30), 0.5 + 0.5 * math.sin(F.t + rec.index))
				return scale(baseC, 0.35 + 0.65 * math.exp(-((clk.beat * 0.75) % 1) * 4))
			end
			return scale(baseC, dist < 1 and 1.1 or (0.35 + 0.25 * F.env))
		elseif kind == "Podium" then
			return scale(pal[(rec.index % 2) + 1], 0.4 + 0.6 * F.env)
		elseif kind == "BarBack" then
			return scale(Color3.fromRGB(255, 196, 120), 0.85 + 0.15 * F.env * (F.drop and 1 or 0))
		elseif kind == "FacadeLine" then
			local head = (F.t * 5) % rec.count
			local dist = (rec.index - head) % rec.count
			return if dist < 1 then WHITE else Color3.fromRGB(40, 220, 255)
		elseif kind == "FacadeSlit" then
			local on = (rec.index + math.floor(clk.beat / 2)) % 5 == 0
			return if on then WHITE else scale(Color3.fromRGB(40, 220, 255), 0.55 + 0.4 * F.env)
		elseif kind == "Portal" then
			return scale(Color3.fromRGB(40, 220, 255), 0.65 + 0.35 * math.sin(F.t * 2) ^ 2)
		elseif kind == "Logo" then
			return scale(Color3.fromRGB(40, 220, 255), 0.75 + 0.35 * (F.downbeat and F.env or 0))
		elseif kind == "CameraFlash" then
			-- the door photographer fires a flash every few seconds (~0.1 s)
			local slot = math.floor(F.t * 10)
			local fire = Shared.hash(math.floor(slot / 30), rec.index) * 30
			return if math.abs((slot % 30) - math.floor(fire)) < 1 then WHITE else rec.base
		elseif kind == "IceBucket" then
			local h = (F.t * 0.04 + rec.index * 0.13) % 1
			return Color3.fromHSV(h, 0.55, 0.75 + 0.25 * (F.drop and F.env or 0))
		elseif kind == "SparklerTip" then
			return nil -- handled with the sparkler emitters
		elseif kind == "AccentLine" then
			-- red neon trim of the hall: keeps its built colour, pulses on the kick
			return scale(rec.base, 0.6 + 0.4 * F.env * (if F.drop then 1 else F.energy))
		elseif kind == "TableRing" then
			-- LED ring of a standing / DJ table: breathes with the kick; flashes gold while that
			-- table has bottle service on it
			local t = if type(rec.tableId) == "string" then tablesById[rec.tableId] else nil
			if t and ordersActive[t] then
				return if (math.floor(F.t * 8) + rec.index) % 2 == 0 then Color3.fromRGB(255, 214, 120) else WHITE
			end
			return scale(pal[(rec.index % 2) + 1], 0.4 + 0.5 * F.env * F.energy)
		end
		-- LED kinds added by later builds (e.g. a side LED wall, table rims): animated by family
		local fam = genericFamily(kind)
		if fam == "wall" then
			if OV.mode then
				local oc, dim = overlayColour(rec)
				if oc then
					return oc
				elseif dim then
					return scale(wallColour(rec), 0.3)
				end
			end
			return wallColour(rec)
		elseif fam == "chase" then
			local n = math.max(rec.count, 8)
			local head = (clk.beat * 2) % n
			local dist = (rec.index - head) % n
			return scale(pal[1]:Lerp(pal[3], 0.5 + 0.5 * math.sin(F.t * 0.7 + rec.index * 0.3)), dist < 1 and 1.1 or (0.35 + 0.3 * F.env))
		end
		return nil
	end
end

---------------------------------------------------------------------------------------------------
-- Frame update
---------------------------------------------------------------------------------------------------
local cur = { interior = 1, exterior = 1, wall = 1, fixture = 1, strobe = 1, kinetic = 1, bounce = 1 }
local fxDeadline = { co2 = 0, confetti = 0 }

local function rebuildLists()
	table.clear(interiorList)
	table.clear(exteriorList)
	table.clear(wallList)
	for _, rec in colourItems do
		if rec.exterior then
			table.insert(exteriorList, rec)
		end
		if not rec.exterior or rec.kind == "Tunnel" then
			if rec.kind == "Wall" then
				table.insert(wallList, rec)
			else
				table.insert(interiorList, rec)
			end
		end
	end
	cur.interior, cur.exterior, cur.wall = 1, 1, 1
	listDirty = false
end

local function setEmitters(registry: { [ParticleEmitter]: any }, on: boolean)
	for pe in registry do
		if pe.Parent and pe.Enabled ~= on then
			pe.Enabled = on
		end
	end
end

local function setLasers(on: boolean)
	for beam, rec in lasers do
		if beam.Parent and rec.enabled ~= on then
			beam.Enabled = on
			rec.enabled = on
		end
	end
end

-- Show SpotLights, fixture beams and pin spots of the room the player is in. The tier caps the
-- SpotLights (nearest to the camera first) and the beams (low: none); called every zone tick, so
-- the set follows the camera. Writes only what changes.
local setSpots
do
	local spotCands: { any } = {}
	local spotWant: { [any]: boolean } = {}
	local beamWant: { [any]: boolean } = {}
	local function byDist(a: any, b: any): boolean
		return a.spotDist < b.spotDist
	end
	function setSpots(room: string)
		spotsRoom = room
		table.clear(spotCands)
		table.clear(spotWant)
		table.clear(beamWant)
		if room ~= "" then
			for _, rec in fixtures do
				if rec.head.Parent and rec.room == room then
					table.insert(spotCands, rec)
				end
			end
			local cam = workspace.CurrentCamera
			local p = if cam then cam.CFrame.Position else Vector3.zero
			for _, rec in spotCands do
				rec.spotDist = (rec.headRest.Position - p).Magnitude
			end
			table.sort(spotCands, byDist)
			local spots, beams = 0, 0
			for _, rec in spotCands do
				if rec.spot and spots < T.spots then
					spots += 1
					spotWant[rec] = true
				end
				if rec.beam and T.beams and beams < T.maxBeams then
					beams += 1
					beamWant[rec] = true
				end
			end
		end
		for _, rec in fixtures do
			local spot = rec.spot
			if spot and spot.Parent then
				local on = spotWant[rec] == true
				if spot.Enabled ~= on then
					spot.Enabled = on
					extraWrites += 1
				end
			end
			local beam = rec.beam
			if beam and beam.Parent then
				local on = beamWant[rec] == true
				if beam.Enabled ~= on then
					beam.Enabled = on
					extraWrites += 1
				end
			end
		end
		for beam, beamRoom in showBeams do
			if beam.Parent then
				local on = T.pins and room ~= "" and beamRoom == room
				if beam.Enabled ~= on then
					beam.Enabled = on
					extraWrites += 1
				end
			end
		end
	end
end

local updateFixtures
do
	local movedParts: { BasePart } = {}
	local movedCFrames: { CFrame } = {}
	local function fixtureAim(rec: any): (number, number)
		local clk = F.clk
		local i, s = rec.index, rec.side
		local tt = F.t
		if rec.room == "HipHop" then
			tt = tt * 0.6
			return 0.7 * math.sin(tt * 0.9 + i), 0.55 + 0.25 * math.sin(tt * 1.3 + i * 0.5)
		end
		if rec.kind == "Beam" then
			if F.drop then
				return tt * 1.8 + i * 0.8, 0.35 + 0.3 * math.sin(clk.beat * math.pi / 2 + i)
			end
			return 0.6 * math.sin(tt * 0.5 + i), 0.25 + 0.2 * math.sin(tt * 0.7 + i)
		end
		if F.intro then
			return 0.8 * math.sin(tt * 0.25 + i * 0.7), 0.45 + 0.25 * math.sin(tt * 0.37 + i)
		elseif F.build then
			local sp = 1 + F.energy
			return s * 0.9 * math.sin(clk.beat * math.pi / 4 * sp + i * 0.4), 0.5 + 0.35 * math.sin(clk.beat * math.pi / 2)
		elseif F.drop then
			if F.variant == 2 then
				return s * (0.3 + 0.9 * F.env), 0.65 + 0.2 * F.env
			end
			return tt * 2.2 * s + i * 0.8, 0.7 + 0.25 * math.sin(clk.beat * math.pi)
		end
		return tt * 0.2 + i, 1.25 + 0.15 * math.sin(tt * 0.5 + i) -- breakdown: slow ballyhoo over the crowd's heads
	end

	local function fixtureColour(rec: any): Color3
		local pal = F.pal
		if rec.room == "HipHop" then
			return (rec.index % 2 == 0) and Color3.fromRGB(255, 60, 40) or Color3.fromRGB(255, 170, 40)
		end
		if rec.kind == "Beam" then
			return if F.drop and F.downbeat then WHITE else pal[3]
		end
		if F.drop and F.downbeat and F.env > 0.6 then
			return pal[3]
		end
		return pal[(rec.index % 2) + 1]
	end

	-- Round-robin over the fixtures within K.FIXTURE_RADIUS (low tier: only the ones whose SpotLight or
	-- beam is on). Returns the writes (CFrames + colours + brightness).
	function updateFixtures(camPos: Vector3, budget: number): number
		if fixturesDirty then
			table.clear(fixtureList)
			for _, rec in fixtures do
				table.insert(fixtureList, rec)
			end
			cur.fixture = 1
			fixturesDirty = false
		end
		table.clear(movedParts)
		table.clear(movedCFrames)
		local n = #fixtureList
		local now = os.clock()
		local r2 = K.FIXTURE_RADIUS * K.FIXTURE_RADIUS
		local writes = 0
		local visited = 0
		while visited < n and writes + 6 <= budget do
			if cur.fixture > n then
				cur.fixture = 1
			end
			local rec = fixtureList[cur.fixture]
			cur.fixture += 1
			visited += 1
			local head = rec.head
			local lit = (rec.spot ~= nil and rec.spot.Enabled) or (rec.beam ~= nil and rec.beam.Enabled)
			if head.Parent and (lit or not T.movingSpotsOnly) then
				-- parts of a fixture can stream separately: drop stale references and re-resolve
				if rec.yoke and not rec.yoke.Parent then
					rec.yoke, rec.yokeRest = nil, nil
				end
				if rec.lens and not rec.lens.Parent then
					rec.lens, rec.lensOff = nil, nil
				end
				if (not rec.yoke or not rec.lens) and now >= rec.resolveAt then
					rec.resolveAt = now + 1
					resolveFixture(rec)
				end
				local d = rec.headRest.Position - camPos
				if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2 then
					local pan, tilt = fixtureAim(rec)
					local yokeRest = rec.yokeRest or (rec.headRest * rec.headOff:Inverse())
					local panCF = yokeRest * CFrame.Angles(0, pan, 0)
					local headCF = panCF * rec.headOff * CFrame.Angles(tilt, 0, 0)
					if rec.yoke and rec.yoke.Parent then
						table.insert(movedParts, rec.yoke)
						table.insert(movedCFrames, panCF)
						writes += 1
					end
					table.insert(movedParts, head)
					table.insert(movedCFrames, headCF)
					writes += 1
					if rec.lens and rec.lens.Parent and rec.lensOff then
						table.insert(movedParts, rec.lens)
						table.insert(movedCFrames, headCF * rec.lensOff)
						writes += 1
					end
					local col = fixtureColour(rec)
					if not rec.lastColour or differs(col, rec.lastColour) then
						rec.lastColour = col
						if rec.beam and rec.beam.Parent and rec.beam.Enabled then
							rec.beam.Color = ColorSequence.new(col)
							writes += 1
						end
						if rec.spot and rec.spot.Parent then
							rec.spot.Color = col
							writes += 1
						end
						if rec.lens and rec.lens.Parent then
							rec.lens.Color = col
							writes += 1
						end
					end
					local spot = rec.spot
					if spot and spot.Parent and spot.Enabled then
						local sb = 2 + 5 * F.energy * (0.6 + 0.4 * F.env)
						if math.abs(spot.Brightness - sb) > 0.25 then
							spot.Brightness = sb
							writes += 1
						end
					end
				end
			end
		end
		if #movedParts > 0 then
			local ok, err = pcall(function()
				workspace:BulkMoveTo(movedParts, movedCFrames, Enum.BulkMoveMode.FireCFrameChanged)
			end)
			if not ok then
				warnf("BulkMoveTo failed:", err)
			end
		end
		return writes
	end
end

local function updateStrobes(budget: number): number
	if strobesDirty then
		table.clear(strobeList)
		for _, rec in strobes do
			table.insert(strobeList, rec)
		end
		cur.strobe = 1
		strobesDirty = false
	end
	local clk = F.clk
	local writes = 0
	local strobeOn = false
	if F.burst then
		strobeOn = (clk.beat * 2) % 1 < 0.35 -- two flashes a beat right after the drop
	elseif F.realDrop then
		local lastBarOfSection = clk.barInSection == clk.sectionBars - 1
		if lastBarOfSection then
			strobeOn = (clk.beat * 4) % 1 < 0.3
		else
			strobeOn = (clk.beatInBar < 0.1) or (clk.beatInBar >= 2 and clk.beatInBar < 2.1)
		end
	elseif F.build and clk.barInSection >= clk.sectionBars - 2 then
		local sub = (clk.barInSection == clk.sectionBars - 1) and 8 or 4
		strobeOn = (clk.beat * sub / 4) % 1 < 0.35
	end
	local blinder = F.realDrop and clk.barInSection % 8 == 0 and clk.beatInBar < 1
	local blinderK = blinder and math.exp(-clk.beatInBar * 3) or 0
	if F.burst then
		blinderK = math.max(blinderK, math.exp(-F.dropAge * 2))
	end
	local n = #strobeList
	local visited = 0
	while visited < n and writes < budget do
		if cur.strobe > n then
			cur.strobe = 1
		end
		local rec = strobeList[cur.strobe]
		cur.strobe += 1
		visited += 1
		local part = rec.part
		if part.Parent then
			local col
			if rec.kind == "Strobe" then
				col = strobeOn and WHITE or Color3.fromRGB(46, 46, 50)
			else
				col = Color3.fromRGB(70, 50, 30):Lerp(Color3.fromRGB(255, 214, 150), blinderK)
			end
			if rec.on == nil or differs(col, rec.on) then
				rec.on = col
				part.Color = col
				writes += 1
			end
		end
	end
	return writes
end

-- Lasers: re-aimed at 30 Hz (K.LASER_INTERVAL), round-robin within a write budget, and only while
-- the camera is within K.LASER_RADIUS of the emitter and the player is in a room they can be seen
-- from; low tier: every 2nd laser. Returns the number of writes (attachment moves, Enabled toggles,
-- colours).
local updateLasers
do
	local laserClock = 0
	local laserCursor = 1

	local function laserTarget(rec: any): (number, number, number, boolean)
		local clk = F.clk
		local e, i, n = rec.emitter, rec.index, rec.count
		local spread = (i - (n - 1) / 2) / math.max(1, (n - 1) / 2)
		local x, y, z = 0, -12, 70
		local on = true
		if F.fanK > 0 then
			-- laser fan right after the drop: a flat sheet over the crowd, all beams on
			return spread * 34, -9 + 2 * math.sin(clk.beat * math.pi), z, true
		elseif F.breakdown or F.intro then
			-- slow tunnel / cone through the haze
			local ang = (i / n) * math.pi * 2 + F.t * 1.2 * (e % 2 == 0 and 1 or -1)
			x, y = math.cos(ang) * 14, math.sin(ang) * 10 - 6
		elseif F.build then
			local w = 10 + 26 * F.energy
			x, y = spread * w, -16 + 12 * math.sin(clk.beat * math.pi / 2)
			on = (i + math.floor(clk.beat * 2)) % 2 == 0 or F.energy > 0.9
		else
			if F.variant == 0 then
				local w = 20 + 16 * math.sin(F.t * 2 + e)
				x, y = spread * w, -14 + 8 * math.sin(clk.beat * math.pi / 2)
			elseif F.variant == 1 then
				x, y = spread * 6 + 30 * math.sin(clk.beat * math.pi / 4 + e), -12
			else
				local ang = (i / n) * math.pi * 2 + F.t * 3
				x, y = math.cos(ang) * 22, math.sin(ang) * 14 - 8
				on = (clk.beat * 4) % 1 < 0.7
			end
		end
		return x, y, z, on
	end

	function updateLasers(camPos: Vector3, dt: number, budget: number): number
		laserClock += dt
		if laserClock < K.LASER_INTERVAL then
			return 0
		end
		laserClock = math.min(laserClock - K.LASER_INTERVAL, K.LASER_INTERVAL) -- no catch-up bursts
		local clk = F.clk
		local visibleRoom = zoneName == "Main" or zoneName == "Lobby" or zoneName == "Corridor"
		local active = visibleRoom
			and (F.fanK > 0 or F.drop or F.breakdown or (F.build and clk.barInSection >= 2) or (F.intro and clk.barInSection >= 12))
		local writes = 0
		if not active then
			for beam, rec in lasers do
				if rec.enabled and beam.Parent then
					beam.Enabled = false
					writes += 1
				end
				rec.enabled = false
			end
			return writes
		end
		if laserListDirty then
			table.clear(laserList)
			for _, rec in lasers do
				table.insert(laserList, rec)
			end
			laserListDirty = false
			laserCursor = 1
		end
		local n = #laserList
		local pal = F.pal
		local r2 = K.LASER_RADIUS * K.LASER_RADIUS
		local every = math.max(1, T.laserEvery)
		local visited = 0
		while visited < n and writes + 3 <= budget do
			if laserCursor > n then
				laserCursor = 1
			end
			local rec = laserList[laserCursor]
			laserCursor += 1
			visited += 1
			local beam = rec.beam
			if beam.Parent then
				local a0, a1 = beam.Attachment0, beam.Attachment1
				local near = false
				if a0 and a0.Parent then
					local d = a0.WorldPosition - camPos
					near = d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2
				end
				local x, y, z, on = laserTarget(rec)
				on = on and near and (every == 1 or math.floor(rec.index) % every == 0)
				if on and a1 and a1.Parent then
					local target = Vector3.new(x, y, z)
					local last = rec.lastTarget
					if not last or (last - target).Magnitude > 0.05 then
						rec.lastTarget = target
						a1.Position = target
						writes += 1
					end
				end
				if rec.enabled ~= on then
					beam.Enabled = on
					rec.enabled = on
					writes += 1
				end
				if on then
					local e = rec.emitter
					local col = if F.fanK > 0 then (if F.dropAge < F.beatSec then WHITE else pal[3])
						elseif F.drop and e >= 3 then pal[(e % 2) + 1]
						else rec.base.Keypoints[1].Value
					if not rec.lastColour or differs(col, rec.lastColour) then
						rec.lastColour = col
						beam.Color = ColorSequence.new(col)
						writes += 1
					end
				end
			end
		end
		return writes
	end
end

---------------------------------------------------------------------------------------------------
-- Kinetic LED tubes, mirror ball, stage FX, hopping ravers
---------------------------------------------------------------------------------------------------
local updateKinetic, restoreKinetic
do
	local kinParts: { BasePart } = {}
	local kinCFrames: { CFrame } = {}

	-- 0 = at rest (top), 1 = fully lowered
	local function kineticDepth(rec: any): number
		local clk = F.clk
		local r, c = rec.row, rec.col
		if F.intro then
			return 0.5 + 0.5 * math.sin(F.t * 0.6 + c * 0.7 + r * 0.45)
		elseif F.build then
			-- everything rises toward the top as the build peaks, rippling on the beat
			local k = 1 - F.energy
			return math.clamp(k * (0.6 + 0.4 * math.sin(clk.beat * math.pi / 2 + c * 0.9)), 0, 1)
		elseif F.drop then
			if F.variant == 0 then
				return if (r + c + math.floor(clk.beat)) % 2 == 0 then 0.9 * F.env + 0.1 else 0.15
			elseif F.variant == 1 then
				local wave = (c - clk.beat * 1.5) % 6
				return math.clamp(1 - math.abs(wave - 3) / 3, 0, 1)
			end
			local dx, dy = c - 2.5, r - 2
			local ring = math.sqrt(dx * dx + dy * dy)
			return 0.5 + 0.5 * math.sin(ring * 1.4 - clk.beat * math.pi)
		end
		-- breakdown: slow breathing ripple from the mirror ball outwards
		local dx, dy = c - 2.5, r - 2
		return 0.5 + 0.5 * math.sin(math.sqrt(dx * dx + dy * dy) * 0.9 - F.t * 1.1)
	end

	local function kineticColour(_rec: any, depth: number): Color3
		local pal = F.pal
		if F.drop and F.downbeat and F.env > 0.7 then
			return WHITE
		end
		return pal[1]:Lerp(pal[3], depth)
	end

	function updateKinetic(camPos: Vector3, budget: number): number
		if kineticsDirty then
			table.clear(kineticList)
			for _, rec in kinetics do
				table.insert(kineticList, rec)
			end
			cur.kinetic = 1
			kineticsDirty = false
		end
		table.clear(kinParts)
		table.clear(kinCFrames)
		local writes = 0
		local r2 = K.KINETIC_RADIUS * K.KINETIC_RADIUS
		-- mirror ball first (one part, turns every update)
		for part, rec in balls do
			if writes + 1 > budget then
				break
			end
			if part.Parent then
				local d = rec.rest.Position - camPos
				if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2 then
					table.insert(kinParts, part)
					table.insert(kinCFrames, rec.rest * CFrame.Angles(0, (F.t * 0.32) % (math.pi * 2), 0))
					writes += 1
				end
			end
		end
		local n = #kineticList
		local visited = 0
		while visited < n and writes + 2 <= budget do
			if cur.kinetic > n then
				cur.kinetic = 1
			end
			local rec = kineticList[cur.kinetic]
			cur.kinetic += 1
			visited += 1
			local part = rec.part
			if part.Parent then
				local d = rec.rest.Position - camPos
				if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2 then
					local depth = math.clamp(kineticDepth(rec), 0, 1)
					local dy = depth * rec.travel
					if math.abs(dy - rec.lastD) > 0.02 then
						rec.lastD = dy
						table.insert(kinParts, part)
						table.insert(kinCFrames, rec.rest - Vector3.new(0, dy, 0))
						writes += 1
					end
					local col = kineticColour(rec, depth)
					if differs(col, rec.lastColour) then
						rec.lastColour = col
						part.Color = col
						writes += 1
					end
				end
			end
		end
		if #kinParts > 0 then
			local ok, err = pcall(function()
				workspace:BulkMoveTo(kinParts, kinCFrames, Enum.BulkMoveMode.FireCFrameChanged)
			end)
			if not ok then
				warnf("kinetic BulkMoveTo failed:", err)
			end
		end
		return writes
	end

	function restoreKinetic()
		table.clear(kinParts)
		table.clear(kinCFrames)
		for part, rec in kinetics do
			if part.Parent and rec.lastD ~= 0 then
				rec.lastD = 0
				table.insert(kinParts, part)
				table.insert(kinCFrames, rec.rest)
			end
		end
		if #kinParts > 0 then
			pcall(function()
				workspace:BulkMoveTo(kinParts, kinCFrames, Enum.BulkMoveMode.FireCFrameChanged)
			end)
		end
	end
end

-- Stage FX / mirror rays / haze: the show cue says what it wants, the tier policy what is allowed.
local function applyFX(kind: string)
	local on = fxWant[kind] == true and T.fx[kind] == true
	if fxOn[kind] == on then
		return
	end
	fxOn[kind] = on
	for pe, rec in fx do
		if rec.kind == kind and pe.Parent then
			pe.Enabled = on
		end
	end
end

local function setFX(kind: string, want: boolean)
	fxWant[kind] = want
	applyFX(kind)
end

local function setRays(want: boolean)
	raysWant = want
	local on = want and T.rays
	if raysOn == on then
		return
	end
	raysOn = on
	for beam in rays do
		if beam.Parent then
			beam.Enabled = on
		end
	end
end

-- haze: off on the low tier and outside; `k` = section density (1 normal, 1.85 slow sections)
local function applyHaze(want: boolean, k: number)
	local on = want and T.haze > 0
	local rateK = if on then T.haze * k else 0
	if hazeApplied.on == on and math.abs(hazeApplied.rate - rateK) < 1e-3 then
		return
	end
	hazeApplied.on, hazeApplied.rate = on, rateK
	for pe, rec in hazes do
		if pe.Parent then
			if on then
				pe.Rate = rec.rate * rateK
			end
			if pe.Enabled ~= on then
				pe.Enabled = on
			end
		end
	end
end

local function allFXOff()
	for kind in FX_KINDS do
		setFX(kind, false)
	end
	setRays(false)
	applyHaze(false, 1)
	for part, rec in flameGlows do
		if rec.on and part.Parent then
			part.Color = rec.base
		end
		rec.on = false
	end
end

-- tier changed: re-apply everything the policy gates (called by the zone loop)
local function applyPolicy()
	policyDirty = false
	for pe, rec in fx do
		if pe.Parent then
			pe.Rate = rec.rate * T.fxScale
		end
	end
	for kind in FX_KINDS do
		applyFX(kind)
	end
	setRays(raysWant)
	hazeApplied.rate = -1 -- re-applied by the next updateEffects (inside) or allFXOff
	if hazeApplied.on and T.haze <= 0 then
		applyHaze(false, 1)
	end
	for pe, rec in hazes do
		applyHazeSize(pe, rec)
	end
	if not T.co2 then
		setEmitters(co2, false)
	end
	if not T.confetti then
		setEmitters(confetti, false)
	end
	if T.laserEvery > 1 then
		for _, rec in lasers do
			rec.lastTarget = nil -- odd lasers get switched off by the next round
		end
	end
	setSpots(spotsRoom)
end

-- Hopping ravers, beat bob, drop jumps ---------------------------------------------------------------
-- Posed ravers with a Bounce attribute hop on the beat (drops / builds), animated dancers bob on the
-- beat on mid / high, and the guests picked by crowdReact jump once when they cheer.
local updateBounce, restoreNPCs
do
	local bounceParts: { BasePart } = {}
	local bounceCFrames: { CFrame } = {}

	function updateBounce(camPos: Vector3, budget: number): number
		if bounceListDirty then
			table.clear(bounceList)
			for _, rec in npcs do
				if not rec.member and rec.hrp and rec.home and (rec.bounce > 0 or rec.danceAnim or rec.canReact or rec.nightBounce) then
					table.insert(bounceList, rec)
				end
			end
			cur.bounce = 1
			bounceListDirty = false
		end
		table.clear(bounceParts)
		table.clear(bounceCFrames)
		local clk = F.clk
		local k = 0
		if F.realDrop then
			k = 1
		elseif F.groove then
			k = 0.6
		elseif F.build then
			k = 0.35 * F.energy
		elseif F.breakdown or F.intro then
			k = 0.15
		end
		local frac = clk.frac
		local hop = 4 * frac * (1 - frac) -- parabola 0 -> 1 -> 0 over one beat
		local f2 = (frac + 0.5) % 1
		local hop2 = 4 * f2 * (1 - f2) -- the off-beat half of the crowd
		local now = os.clock()
		local r2 = K.BOUNCE_RADIUS * K.BOUNCE_RADIUS
		local n = #bounceList
		local visited = 0
		while visited < n and #bounceParts < budget do
			if cur.bounce > n then
				cur.bounce = 1
			end
			local rec = bounceList[cur.bounce]
			cur.bounce += 1
			visited += 1
			if rec.hrp.Parent and not rec.member then
				local d = rec.home.Position - camPos
				if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2 then
					local ph = if rec.seed > 0.5 then hop else hop2
					local h = 0
					if rec.bounce > 0 then
						h = rec.bounce * k * ph * (if nightLvl >= 2 then 1.25 else 1)
					elseif rec.nightBounce and rec.nightNeed and nightLvl >= rec.nightNeed then
						h = rec.nightBounce * k * ph
					elseif T.bob and rec.danceAnim and rec.playing and not rec.reacting then
						h = 0.2 * k * ph
					end
					local jt = now - rec.jumpAt
					if jt >= 0 and jt < 0.5 then
						local q = jt / 0.5
						h += 1.4 * 4 * q * (1 - q)
					end
					if h > 0.02 or rec.lastH > 0.02 then
						rec.lastH = if h > 0.02 then h else 0
						table.insert(bounceParts, rec.hrp)
						table.insert(bounceCFrames, rec.home + Vector3.new(0, rec.lastH, 0))
						rec.moved = true
					end
				end
			end
		end
		if #bounceParts > 0 then
			local ok, err = pcall(function()
				workspace:BulkMoveTo(bounceParts, bounceCFrames, Enum.BulkMoveMode.FireCFrameChanged)
			end)
			if not ok then
				warnf("bounce BulkMoveTo failed:", err)
			end
		end
		return #bounceParts
	end

	-- put every NPC the show moved back where the server built it
	function restoreNPCs()
		restoreParade()
		table.clear(bounceParts)
		table.clear(bounceCFrames)
		for _, rec in npcs do
			if rec.moved and not rec.member and rec.hrp and rec.hrp.Parent and rec.home then
				table.insert(bounceParts, rec.hrp)
				table.insert(bounceCFrames, rec.home)
			end
			if not rec.member then
				rec.moved = false
				rec.lastH = 0
			end
		end
		if #bounceParts > 0 then
			pcall(function()
				workspace:BulkMoveTo(bounceParts, bounceCFrames, Enum.BulkMoveMode.FireCFrameChanged)
			end)
		end
	end
end

-- CO2 / confetti bursts (drop moments and CO2 cue bars): only while the player is in a room that
-- sees the main show; the tier scales the rate (low: 30 % CO2 for 0.7 s, 40 % confetti).
burstFX = function(kind: string)
	if not (state == "Inside" and spotsRoom == "Main") then
		return
	end
	local now = os.clock()
	local reg, scaleK, secs
	if kind == "co2" then
		if not T.co2 then
			return
		end
		reg, scaleK, secs = co2, T.co2Scale or 1, T.co2Secs or 1.3
		fxDeadline.co2 = now + secs
	elseif kind == "confetti" then
		if not T.confetti then
			return
		end
		reg, scaleK, secs = confetti, T.confettiScale or 1, 3
		fxDeadline.confetti = now + secs
	else
		return
	end
	local w = 0
	for pe, rec in reg do
		if pe.Parent then
			if rec.k ~= scaleK then
				rec.k = scaleK
				pe.Rate = rec.rate * scaleK
				w += 1
			end
			if not pe.Enabled then
				pe.Enabled = true
				w += 1
			end
		end
	end
	extraWrites += w -- charged to this update's budget (the frame takes extraWrites right after)
end

local function updateEffects(budget: number): number
	local now = os.clock()
	local writes = 0
	-- only in the rooms that see the show (Main / Lobby / Corridor, HipHop): the restrooms, the stair
	-- and the 2F lounge / terrace get none of the heavy translucent effects
	local inside = state == "Inside" and spotsRoom ~= ""
	local cue = F.cue
	if fxDeadline.co2 > 0 and now >= fxDeadline.co2 then
		fxDeadline.co2 = 0
		setEmitters(co2, false)
	end
	if fxDeadline.confetti > 0 and now >= fxDeadline.confetti then
		fxDeadline.confetti = 0
		setEmitters(confetti, false)
	end
	local wantSpark = inside and cue.sparkler
	if wantSpark ~= sparkOn then
		sparkOn = wantSpark
		setEmitters(sparklers, wantSpark)
		for _, rec in colourItems do
			if rec.kind == "SparklerTip" and rec.part.Parent then
				local c = if wantSpark then Color3.fromRGB(255, 240, 200) else rec.base
				if differs(c, rec.last) then
					rec.part.Color = c
					rec.last = c
					writes += 1
				end
			end
		end
	end
	setFX("ColdSpark", inside and cue.coldSpark)
	local flameNow = inside and cue.flame
	setFX("Flame", flameNow)
	for part, rec in flameGlows do
		if rec.on ~= flameNow and part.Parent and writes < budget then
			rec.on = flameNow
			part.Color = if flameNow then Color3.fromRGB(255, 200, 90) else rec.base
			writes += 1
		end
	end
	setFX("LowFog", inside and cue.lowFog)
	setFX("MirrorGlint", inside and cue.mirror)
	setRays(inside and cue.mirror)
	applyHaze(inside, if F.breakdown or F.intro then 2.6 / 1.4 else 1)
	return writes
end

-- LED colours: round-robin over each list, at most `budget` writes and `maxVisits` evaluations per
-- update, unchanged colours are skipped.
local function runList(list: { any }, key: string, budget: number, maxVisits: number): number
	local n = #list
	if n == 0 or budget <= 0 or maxVisits <= 0 then
		return 0
	end
	local cursor = cur[key]
	local visits = math.min(n, maxVisits)
	local writes, visited = 0, 0
	while writes < budget and visited < visits do
		if cursor > n then
			cursor = 1
		end
		local rec = list[cursor]
		cursor += 1
		visited += 1
		local part = rec.part
		if part.Parent then
			if rec.gui then
				-- pulses on the kick at night only (applyLogoGui ignores the pulse by day)
				writes += applyLogoGui(rec, 1 + 0.5 * (F.downbeat and F.env or 0))
			else
				local col = itemColour(rec)
				if col and differs(col, rec.last) then
					rec.last = col
					part.Color = col
					writes += 1
				end
			end
		end
	end
	cur[key] = cursor
	return writes
end

-- The LED walls get the first share (60 % while an overlay - countdown, banner, title - is on, else
-- 45 %) so text scrolls without tearing; unused writes go back to the wall after the rest.
local function updateColours(budget: number): number
	if listDirty then
		rebuildLists()
	end
	if state == "Near" then
		return runList(exteriorList, "exterior", budget, T.visits)
	end
	local share = if OV.mode then 0.6 else 0.45
	local wallVisits = if T.visits == math.huge then math.huge else math.floor(T.visits * share)
	local restVisits = if T.visits == math.huge then math.huge else T.visits - wallVisits
	local w = runList(wallList, "wall", math.floor(budget * share), wallVisits)
	w += runList(interiorList, "interior", budget - w, restVisits)
	if w < budget and OV.mode then
		w += runList(wallList, "wall", budget - w, wallVisits) -- text on the wall: spare writes go there
	end
	return w
end

---------------------------------------------------------------------------------------------------
-- Legacy music (MusicAssetId on the club model, empty by default). Never plays while the music
-- system owns the music: MusicOwner = "ClubMusic" on ClubRuntime / ReplicatedStorage.ClubMusicState,
-- or ClubMusicShared is installed and has not published an owner yet (first 20 s).
---------------------------------------------------------------------------------------------------
local legacy = { sound = nil :: Sound?, eq = nil :: EqualizerSoundEffect?, id = nil :: string?, desired = nil :: string?, vol = 0 }

local function musicOwnedElsewhere(): boolean
	local ownerAttr = ATTR.MusicOwner or "MusicOwner"
	for rt in runtimes do
		if rt:GetAttribute(ownerAttr) == "ClubMusic" then
			return true
		end
	end
	local st = ReplicatedStorage:FindFirstChild("ClubMusicState")
	if st and st:GetAttribute(ownerAttr) == "ClubMusic" then
		return true
	end
	return ReplicatedStorage:FindFirstChild("ClubMusicShared") ~= nil and os.clock() - scriptStart < 20
end

local function currentMusicId(): string?
	if musicOwnedElsewhere() then
		return nil
	end
	for rt in runtimes do
		if rt.Parent then
			local parentVenue = rt.Parent
			local v = parentVenue and parentVenue:GetAttribute(Shared.Attr.MusicAssetId)
			local id = Shared.soundIdFrom(v)
			if id then
				return id
			end
			id = Shared.soundIdFrom(rt:GetAttribute(Shared.Attr.MusicAssetId))
			if id then
				return id
			end
		end
	end
	return nil
end

local function currentEpoch(): number
	for rt in runtimes do
		local e = rt:GetAttribute(Shared.Attr.ShowEpoch)
		if type(e) == "number" and e == e then
			return e
		end
	end
	return 0
end

local function stopLegacyMusic()
	if legacy.sound then
		legacy.sound:Destroy()
	end
	legacy.sound, legacy.eq, legacy.id = nil, nil, nil
end

local function updateMusic(dt: number): number
	local wanted = if state == "Inside" then legacy.desired else nil
	if wanted ~= legacy.id then
		stopLegacyMusic()
		legacy.id = wanted
		if wanted then
			local s = Instance.new("Sound")
			s.Name = "ClubOceanMusic"
			s.SoundId = wanted
			s.Looped = true
			s.Volume = 0
			local efx = Instance.new("EqualizerSoundEffect")
			efx.LowGain = 2
			efx.MidGain = 0
			efx.HighGain = 0
			efx.Parent = s
			s.Parent = SoundService
			legacy.sound, legacy.eq, legacy.vol = s, efx, 0
			local ok = pcall(function()
				s:Play()
			end)
			if ok then
				task.spawn(function()
					for _ = 1, 50 do
						if legacy.sound ~= s or not s.Parent then
							return
						end
						if s.TimeLength > 0 then
							pcall(function()
								s.TimePosition = (workspace:GetServerTimeNow() - currentEpoch()) % s.TimeLength
							end)
							return
						end
						task.wait(0.2)
					end
				end)
			end
		end
	end
	local w = 0
	local snd, eq = legacy.sound, legacy.eq
	if snd and eq then
		local target = (state == "Inside") and (0.85 * (1 - 0.8 * muffle)) or 0
		legacy.vol += (target - legacy.vol) * math.clamp(dt * 3, 0, 1)
		if math.abs(snd.Volume - legacy.vol) > 0.005 then
			snd.Volume = legacy.vol
			w += 1
		end
		local hg = -40 * muffle
		if eq.HighGain ~= hg then
			eq.HighGain = hg
			eq.MidGain = -14 * muffle
			eq.LowGain = 2 - 2 * muffle
			w += 3
		end
	end
	return w
end

---------------------------------------------------------------------------------------------------
-- Colour grade while inside (local effect, the server never touches it)
---------------------------------------------------------------------------------------------------
local grade = { inst = nil :: ColorCorrectionEffect?, k = 0, written = -1 }
local function updateGrade(dt: number): number
	local target = (state == "Inside") and 1 or 0
	if not grade.inst and target == 0 then
		return 0
	end
	if not grade.inst or not grade.inst.Parent then
		local g = Instance.new("ColorCorrectionEffect")
		g.Name = "ClubOceanGrade"
		g.Enabled = false
		g.Parent = Lighting
		grade.inst = g
		grade.written = -1
	end
	grade.k += (target - grade.k) * math.clamp(dt * 2, 0, 1)
	if math.abs(grade.k - target) < 0.004 then
		grade.k = target
	end
	if math.abs(grade.k - grade.written) < 0.004 then
		return 0
	end
	grade.written = grade.k
	local g = grade.inst :: ColorCorrectionEffect
	g.Brightness = -0.05 * grade.k
	g.Contrast = 0.16 * grade.k
	g.Saturation = 0.18 * grade.k
	local on = grade.k > 0.01
	if g.Enabled ~= on then
		g.Enabled = on
	end
	return 4
end

---------------------------------------------------------------------------------------------------
-- Bottle service visuals (local parts on the ordered table; LOD = "near")
---------------------------------------------------------------------------------------------------
local updateOrders
do
	local BOTTLE_GREEN = Color3.fromRGB(18, 44, 26)
	local GOLD_FOIL = Color3.fromRGB(214, 170, 72)
	local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis (X) vertical

	-- top surface of the table: a part named BottleSpot / TableTop / MarbleTop / Top, else rays down through the
	-- table model between its centre and the ServePoint, else above the ServePoint
	local function tableTop(t: any): Vector3?
		if t.topPos then
			return t.topPos
		end
		local model = t.model :: Model
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		for _, name in { "BottleSpot", "TableTop", "MarbleTop", "Tabletop", "Top" } do
			local p = model:FindFirstChild(name, true)
			if p and p:IsA("BasePart") then
				-- top of the part along world Y (works for rotated cylinders; no ray, the optimizer
				-- saves most table parts with CanQuery off)
				local cf, sz = p.CFrame, p.Size
				local halfY = 0.5 * (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z)
				local pos = p.Position + Vector3.new(0, halfY, 0)
				t.topPos = pos
				return pos
			end
		end
		local sp = servePos(t)
		local ok, cf, size = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok and typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
			params.FilterDescendantsInstances = { model }
			local floorY = cf.Position.Y - size.Y / 2
			local topY = cf.Position.Y + size.Y / 2 + 1
			for _, a in { 0, 0.3, 0.55, 0.8 } do
				local p = if sp then cf.Position:Lerp(sp, a) else cf.Position
				local hit = workspace:Raycast(Vector3.new(p.X, topY, p.Z), Vector3.new(0, -(size.Y + 2), 0), params)
				if hit and hit.Normal.Y > 0.8 then
					local h = hit.Position.Y - floorY
					if h >= 1.2 and h <= 6 then
						t.topPos = hit.Position
						return hit.Position
					end
				end
				if not sp then
					break
				end
			end
		end
		if sp then
			-- ServePoint = HumanoidRootPart height in front of the table, facing it
			local serve = t.serve
			local look = if serve and serve:IsA("BasePart") then flat(serve.CFrame.LookVector) else Vector3.zero
			local ahead = if look.Magnitude > 0.5 then look.Unit * 2.4 else Vector3.zero
			return sp + ahead - Vector3.new(0, 0.6, 0)
		end
		return nil
	end

	local function bottlePart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
		return p
	end

	clearBottles = function(t: any)
		if t.visual then
			t.visual:Destroy()
		end
		t.visual = nil
		t.emitters = nil
		t.sparkLit = false
	end

	-- one local template (built on first use, re-rated when the tier changes); every order clones it
	-- and moves the clone onto the table top (a few writes instead of ~150)
	local template: Model? = nil
	local templateFx = -1
	local function getTemplate(): Model
		local m = template
		if m and templateFx == T.bottleFx then
			return m
		end
		if not m then
			local nm = Instance.new("Model")
			nm.Name = "ClubBottleService"
			nm:SetAttribute("LOD", "near")
			nm:AddTag("NearLOD") -- (DetailLOD discovers near models by this tag)
			local c = CFrame.new()
			bottlePart(nm, "BottleGlow", Vector3.new(0.1, 2.0, 2.0), c * CFrame.new(0, 0.05, 0) * UPRIGHT, Color3.fromRGB(255, 60, 170), Enum.Material.Neon, Enum.PartType.Cylinder)
			for _, sd in { -1, 1 } do
				local b = c * CFrame.new(sd * 0.45, 0.1, 0)
				local body = bottlePart(nm, "Champagne", Vector3.new(1.0, 0.4, 0.4), b * CFrame.new(0, 0.5, 0) * UPRIGHT, BOTTLE_GREEN, Enum.Material.Glass, Enum.PartType.Cylinder)
				body.Transparency = 0.08
				bottlePart(nm, "Label", Vector3.new(0.32, 0.41, 0.41), b * CFrame.new(0, 0.42, 0) * UPRIGHT, Color3.fromRGB(236, 226, 200), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
				bottlePart(nm, "Shoulder", Vector3.new(0.38, 0.38, 0.38), b * CFrame.new(0, 1.0, 0), BOTTLE_GREEN, Enum.Material.Glass, Enum.PartType.Ball)
				bottlePart(nm, "Foil", Vector3.new(0.42, 0.17, 0.17), b * CFrame.new(0, 1.32, 0) * UPRIGHT, GOLD_FOIL, Enum.Material.Foil, Enum.PartType.Cylinder)
				local stick = bottlePart(nm, "SparklerStick", Vector3.new(0.05, 0.55, 0.05), b * CFrame.new(0, 1.8, 0), Color3.fromRGB(255, 236, 190), Enum.Material.Neon)
				local att = Instance.new("Attachment")
				att.Name = "SparkTip"
				att.Position = Vector3.new(0, 0.28, 0)
				att.Parent = stick
				local pe = Instance.new("ParticleEmitter")
				pe.Name = "BottleSparkler"
				pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				pe.Lifetime = NumberRange.new(0.3, 0.7)
				pe.Speed = NumberRange.new(3, 7)
				pe.SpreadAngle = Vector2.new(30, 30)
				pe.EmissionDirection = Enum.NormalId.Top
				pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.04) })
				pe.Color = ColorSequence.new(Color3.fromRGB(255, 244, 210), Color3.fromRGB(255, 170, 60))
				pe.LightEmission = 1
				pe.Acceleration = Vector3.new(0, -10, 0)
				pe.Enabled = false
				pe.Parent = att
			end
			pcall(function()
				nm.WorldPivot = CFrame.new()
			end)
			m = nm
			template = nm
		end
		local tm = m :: Model
		templateFx = T.bottleFx
		for _, d in tm:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				d.Rate = math.max(10, math.floor(70 * T.bottleFx))
			end
		end
		return tm
	end

	local function makeBottles(t: any, sparkling: boolean): boolean
		local top = tableTop(t)
		if not top then
			return false
		end
		local m = getTemplate():Clone()
		m.Name = "ClubBottleService_" .. t.id
		local okPivot = pcall(function()
			m:PivotTo(CFrame.new(top))
		end)
		if not okPivot then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.CFrame = CFrame.new(top) * d.CFrame
				end
			end
		end
		local emitters: { ParticleEmitter } = {}
		for _, d in m:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				d.Enabled = sparkling
				table.insert(emitters, d)
			end
		end
		m.Parent = workspace
		t.visual = m
		t.emitters = emitters
		t.sparkLit = sparkling
		return true
	end

	-- zone tick: show / expire the bottles of recent orders near the camera (at most one table's
	-- bottles are built per tick)
	function updateOrders()
		if next(ordersActive) == nil then
			return
		end
		local now = workspace:GetServerTimeNow()
		local cam = workspace.CurrentCamera
		local cp = cam and cam.CFrame.Position
		local built = false
		for t in ordersActive do
			if now >= t.bottleUntil or not t.model.Parent then
				clearBottles(t)
				ordersActive[t] = nil
			else
				local sp = servePos(t)
				-- (the table's LED ring already flashes while a parade carries the bottles over)
				local near = now >= t.bottleAt and cp ~= nil and sp ~= nil and (sp - cp).Magnitude <= (TCFG.VisualRadius or 90)
				if near and not t.visual then
					if not built then
						built = makeBottles(t, now < t.sparkUntil)
						if built then
							extraWrites += 14 -- clone + pivot + emitters, charged to the next frame
						end
					end
				elseif not near and t.visual then
					clearBottles(t)
				end
				if t.visual and t.sparkLit and now >= t.sparkUntil then
					t.sparkLit = false
					for _, pe in t.emitters or {} do
						if pe.Parent then
							pe.Enabled = false
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Main loops
---------------------------------------------------------------------------------------------------
local loop = {
	heartbeat = nil :: RBXScriptConnection?,
	preSim = nil :: RBXScriptConnection?,
	facadeVisible = false,
	sinceRun = 0,
	accum = 0,
	spent = 0, -- writes the parade walk made this frame (PreSimulation runs before Heartbeat)
	frameWarn = -math.huge,
	paradeWarn = -math.huge,
	danceSeen = -1e9, -- Bus.playerDanceAt already reacted to
}

local preSimSignal: RBXScriptSignal = RunService.Stepped
do
	local ok, sig = pcall(function()
		return (RunService :: any).PreSimulation
	end)
	if ok and typeof(sig) == "RBXScriptSignal" then
		preSimSignal = sig
	end
end

-- One show update. `spent` = writes already made this frame (parade walk): everything this script
-- writes in a frame shares T.writes (low: 60).
local function frame(dt: number, spent: number)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local now = os.clock()
	local serverT = workspace:GetServerTimeNow()
	computeFrame(now, serverT, currentEpoch())
	computeOverlay(now, serverT)
	local budget = math.max(0, T.writes - spent)
	local extra = math.min(extraWrites, math.floor(T.writes / 3))
	extraWrites -= extra
	local writes = extra + updateMusic(dt) + updateGrade(dt)
	writes += processAnimQueue(math.min(9, budget - writes), nil)
	writes += updateReactions(now, math.min(9, budget - writes))
	if state == "Inside" then
		local camPos = cam.CFrame.Position
		writes += updateStrobes(math.min(T.strobes, budget - writes))
		writes += updateFixtures(camPos, math.min(T.fixtures, budget - writes))
		writes += updateLasers(camPos, dt, math.min(T.lasers, budget - writes))
		writes += updateKinetic(camPos, math.min(T.kinetic, budget - writes))
		writes += updateBounce(camPos, math.min(T.bounce, budget - writes))
		writes += updateEffects(math.max(0, budget - writes))
	end
	updateColours(math.max(0, budget - writes))
end

local function onHeartbeat(dt: number)
	local spent = loop.spent
	loop.spent = 0
	if state ~= "Inside" and not (state == "Near" and loop.facadeVisible) then
		-- outside and not looking at the club (or only near the dance floor through a wall): no
		-- show work, only the exit fades finish
		loop.sinceRun = 0
		extraWrites = 0
		if legacy.sound or (grade.inst and grade.k > 0) then
			updateMusic(dt)
			updateGrade(dt)
		end
		return
	end
	loop.sinceRun += dt
	local hz = T.hz
	if hz > 0 then
		local step = 1 / hz
		loop.accum += dt
		if loop.accum < step then
			return
		end
		loop.accum = math.min(loop.accum - step, step)
	end
	local fdt = loop.sinceRun
	loop.sinceRun = 0
	local ok, err = pcall(frame, fdt, spent)
	if not ok and os.clock() - loop.frameWarn > 5 then
		loop.frameWarn = os.clock()
		warnf("frame error:", err)
	end
end

local function onPreSimulation()
	if not paradeActive then
		return
	end
	local ok, res = pcall(paradeStep)
	if ok then
		loop.spent += if type(res) == "number" then res else 0
	elseif os.clock() - loop.paradeWarn > 5 then
		loop.paradeWarn = os.clock()
		warnf("parade step error:", res)
	end
end

-- logo guis at rest (no pulse) for the current day / night state; cheap (a handful of guis) and
-- write-free when nothing changed, so the zone loop calls it every tick
local function restoreGuis()
	if listDirty then
		rebuildLists()
	end
	for _, rec in exteriorList do
		if rec.gui then
			applyLogoGui(rec, 1)
		end
	end
end

-- is any facade item in front of the camera (generous cone) and within sight?
local function facadeInView(): boolean
	local cam = workspace.CurrentCamera
	if not cam then
		return false
	end
	if listDirty then
		rebuildLists()
	end
	local n = #exteriorList
	if n == 0 then
		return false
	end
	local cf = cam.CFrame
	local p, look = cf.Position, cf.LookVector
	local step = math.max(1, math.floor(n / 16))
	for i = 1, n, step do
		local part = exteriorList[i].part
		if part.Parent then
			local dv = part.Position - p
			local d = dv.Magnitude
			-- close up: anything not behind the camera; further away: inside a generous view cone
			local dot = look:Dot(dv)
			if (d < 40 and dot > -0.2 * d) or (d < 700 and dot > 0.4 * d) then
				return true
			end
		end
	end
	return false
end

local function leaveInside()
	setLasers(false)
	setEmitters(co2, false)
	setEmitters(confetti, false)
	setEmitters(sparklers, false)
	if sparkOn then
		for _, rec in colourItems do
			if rec.kind == "SparklerTip" and rec.part.Parent then
				rec.part.Color = rec.base
				rec.last = rec.base
			end
		end
	end
	sparkOn = false
	fxDeadline.co2, fxDeadline.confetti = 0, 0
	allFXOff()
	restoreKinetic()
	restoreNPCs()
end

local function spotRoomFor(zone: string): string
	if zone == "HipHop" then
		return "HipHop"
	elseif zone == "Main" or zone == "Lobby" or zone == "Corridor" then
		return "Main"
	end
	return ""
end

local function zoneTick()
	refreshTier()
	local newState, newZone, newMuffle = evaluateZones()
	local prev = state
	state, zoneName, muffle = newState, newZone, newMuffle
	nightNow = computeNight()
	nightLvl = nightLevel()
	legacy.desired = if newState == "Inside" then currentMusicId() else nil
	local pos = listenerPosition()
	local df = danceFloorPos()
	inClub = newState == "Inside" or (pos ~= nil and df ~= nil and (pos - df).Magnitude <= K.NPC_FLOOR_RADIUS)
	local wanted = newState ~= "Idle" or inClub
	if wanted then
		if not loop.heartbeat then
			loop.accum, loop.sinceRun, loop.spent = 0, 0, 0
			loop.heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
		end
		if not loop.preSim then
			loop.preSim = preSimSignal:Connect(onPreSimulation)
		end
	end
	if policyDirty then
		applyPolicy()
	end
	-- facade logo gui: the Near frame pulses it while the facade is in view; at rest otherwise
	if newState == "Near" then
		local vis = facadeInView()
		if loop.facadeVisible and not vis then
			restoreGuis()
		end
		loop.facadeVisible = vis
	else
		loop.facadeVisible = false
		restoreGuis()
	end
	local room = if newState == "Inside" then spotRoomFor(newZone) else ""
	if newState == "Inside" then
		setSpots(room)
	elseif prev == "Inside" then
		leaveInside()
		setSpots("")
	end
	-- bus for ClubDance
	Bus.state, Bus.zone, Bus.showRoom, Bus.night = newState, newZone, room ~= "", nightNow
	-- bottle-service parade (walked on PreSimulation while the player is in the club)
	local wasActive = paradeActive
	paradeActive = inClub
	if paradeActive then
		local _, target, path = paradeSchedule(workspace:GetServerTimeNow())
		ensureParadePaths(target, path)
	elseif wasActive then
		restoreParade()
	end
	local now = os.clock()
	updateNPCAnim(now)
	-- the show frame makes the queued animation starts; when it is not running (outside, facade
	-- not in view) the zone tick makes them
	if not (newState == "Inside" or (newState == "Near" and loop.facadeVisible)) then
		extraWrites += processAnimQueue(18, 6)
	end
	if newState == "Inside" then
		updateNowPlaying(now)
		-- guests near the local player cheer when the player starts dancing (ClubDance)
		local danceAt = Bus.playerDanceAt or -1e9
		if danceAt ~= loop.danceSeen then
			loop.danceSeen = danceAt
			if now - danceAt < 2 and pos then
				crowdReact(now, 4, pos)
			end
		end
	end
	updateOrders()
	if not wanted then
		if loop.heartbeat then
			loop.heartbeat:Disconnect()
			loop.heartbeat = nil
		end
		if loop.preSim then
			loop.preSim:Disconnect()
			loop.preSim = nil
		end
		if prev ~= "Idle" then
			stopAllAnims()
			restoreNPCs()
		end
		stopLegacyMusic()
		if grade.inst then
			grade.inst.Enabled = false
			grade.k = 0
			grade.written = -1
		end
	end
end

task.spawn(function()
	while true do
		local ok, err = pcall(zoneTick)
		if not ok then
			warnf("zone loop error:", err)
		end
		task.wait(K.ZONE_INTERVAL)
	end
end)
