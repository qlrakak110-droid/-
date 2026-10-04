-- GwangalliConfig: tunables shared by the server and client runtime scripts.
-- Plain data only (no instances, no side effects) so it is safe to require from anywhere.
-- Times marked "clock" are in-game hours (Lighting.ClockTime, 0-24).
--
-- Client quality tiers: GwangalliQuality.get() returns "low" (phones, graphics slider 1-3, or a
-- sustained low frame rate), "mid" or "high". "low" has a SAVER sub-level (GwangalliQuality.isSaver():
-- a phone still under ~22 fps on low): budget maps { low =, mid =, high = } may add `saver =` and a
-- system's Tier table may add `saver = { ... }` (laid over Tier.low while the saver is on).
-- A system table may carry a `Tier` sub-table, e.g. Config.Bridge.Tier.low = { MaxDistance = 4500 }: the client world modules read
-- Util.tierConfig(Config.Bridge), which is the base table with the current tier's keys laid over
-- it. The base keys are the desktop ("high") values, so readers that ignore tiers keep working.

local Config = {}

---------------------------------------------------------------------------------------------
-- Day / night clock (server authoritative)
---------------------------------------------------------------------------------------------
Config.DayLengthMinutes = 24 -- real minutes per in-game day (24 -> 1 in-game hour per real minute)
Config.StartClockTime = 17.0 -- clock at server start (golden hour, night follows shortly)
Config.ClockUpdateInterval = 0.1 -- seconds between Lighting.ClockTime writes on the server
Config.LightingUpdateInterval = 0.5 -- seconds between lighting keyframe writes on the server

-- Night window used for city lights, signs and windows (clock). NightStart > NightEnd (wraps midnight).
Config.NightStart = 17.8
Config.NightEnd = 6.2

-- Named phases replicated as workspace attribute "GwangalliPhase" (clock ranges, start inclusive).
Config.Phases = {
	{ name = "Dawn", from = 4.8, to = 7.0 },
	{ name = "Day", from = 7.0, to = 16.8 },
	{ name = "Sunset", from = 16.8, to = 19.3 },
	-- everything else is "Night"
}

---------------------------------------------------------------------------------------------
-- Terrain
---------------------------------------------------------------------------------------------
Config.Terrain = {
	FrameBudget = 0.008, -- seconds of terrain filling per server frame before yielding
	HoldSpawnUntilReady = true, -- keep CharacterAutoLoads off until the terrain is filled
	HoldSpawnTimeout = 90, -- seconds; spawns are released even if filling is still running
	-- EditorOnly preview parts (e.g. the water preview) are destroyed only when at least this
	-- share of the terrain ops succeeded, so a broken ops module never leaves the map without sea.
	MinSuccessRatio = 0.9,
}

---------------------------------------------------------------------------------------------
-- 광안리 M 드론라이트쇼 (client-side, synchronised to server time)
---------------------------------------------------------------------------------------------
Config.DroneShow = {
	Enabled = true,
	-- In-game clock times at which a show starts (the real show runs Saturdays at 20:00 and 22:00).
	-- A show lasts Duration REAL seconds; with a 24-minute day that is 3 in-game hours, so start
	-- times closer together than that are skipped while a show is still running.
	Times = { 20.0, 23.5 },
	Duration = 180, -- real seconds
	DroneCount = 300,
	DroneSize = 3.6, -- studs (neon balls read as points of light from the beach ~1,200 studs away)
	-- Centre of the show volume over the bay, between the beach (waterline z ~ -280 at x = 0) and
	-- Gwangan Bridge (deck centreline z = -3300). Formations span roughly y = 200..420.
	Center = Vector3.new(0, 310, -1400),
	SeaY = 4, -- launch barge deck height (drones take off from / land on it)
	FacingZ = 1, -- formations face +Z (toward the beach)
	MaxViewDistance = 5200, -- skip the show when the camera is further than this from Center
	UpdateHzDesktop = 60,
	UpdateHzMobile = 20, -- legacy key (the client reads Tier.low.UpdateHz)
	ColorHz = 15, -- colour refresh rate
	StartOnServerStart = false, -- debug: start a show a few seconds after the server starts
	-- Per quality tier (client). On a phone the beach is ~1,200 studs from the show: a 3.6-stud
	-- ball is < 1 px there and low quality levels cull such parts, so "low" draws every drone as
	-- a BillboardGui point sprite (Sprite = true): SpriteStuds studs + SpritePixels px wide, i.e.
	-- never smaller than SpritePixels on screen, LightInfluence 0 so it glows. The sprite size is
	-- kept close to the formation pitch (text pixels are 11 studs apart) so letters stay readable.
	-- Fewer drones on phones: every formation is generated for any count.
	Tier = {
		low = { DroneCount = 180, Sprite = true, SpriteStuds = 3.5, SpritePixels = 2, SpriteBrightness = 1.6, UpdateHz = 15, ColorHz = 6 },
		saver = { DroneCount = 120, UpdateHz = 10, ColorHz = 4 },
		mid = { DroneCount = 240, DroneSize = 5, UpdateHz = 30, ColorHz = 12 },
		high = { UpdateHz = 60 },
	},
	-- Skip position / colour writes while the whole show is behind the camera (dot of the view
	-- direction and the direction to Center below this) and the camera is further than ViewSkipMin.
	ViewSkipDot = -0.2,
	ViewSkipMin = 700,
	-- A drone is re-positioned only when it moved more than this fraction of the camera distance
	-- since its last write (0.0015 ~ half a pixel on a phone): slow hold animations seen from the
	-- beach skip most writes. 0 = write every drone on every update.
	MoveEpsilon = 0.0015,
}

---------------------------------------------------------------------------------------------
-- Client lighting budgets
---------------------------------------------------------------------------------------------
Config.Lights = {
	EvaluateInterval = 0.5, -- seconds between nearest-N passes
	-- nearest-N dynamic lights per quality tier (Future lighting: every light costs on phones)
	-- low (phones): every enabled light costs a Future-lighting light pass / voxel relight
	low = { City = 8, CityRadius = 360, Interior = 6, InteriorRadius = 90 },
	mid = { City = 20, CityRadius = 560, Interior = 16, InteriorRadius = 140 },
	high = { City = 40, CityRadius = 700, Interior = 24, InteriorRadius = 160 },
	saver = { City = 4, CityRadius = 260, Interior = 3, InteriorRadius = 60 }, -- weak phones (see top)
	-- legacy two-way keys (Util.budget maps "low" -> Mobile, otherwise Desktop)
	Desktop = { City = 40, CityRadius = 700, Interior = 24, InteriorRadius = 160 },
	Mobile = { City = 8, CityRadius = 360, Interior = 6, InteriorRadius = 90 },
}

-- Chunk sizes for day/night sweeps over many instances (per frame). The dusk / dawn sweep covers
-- ~12k items (NightGlow, NightNeon, lit windows) and runs nearest-to-the-camera first.
Config.SweepPerFrame = { low = 120, mid = 250, high = 400, saver = 100, Desktop = 400, Mobile = 120 }

---------------------------------------------------------------------------------------------
-- Client quality (GwangalliQuality + GwangalliWorld/MobileQuality + GwangalliWorld/DetailLOD)
---------------------------------------------------------------------------------------------
Config.Quality = {
	FpsLow = 27, -- "< 30 fps": margin so a device capped at 30 fps is not demoted by rounding
	FpsLowSeconds = 5,
	FpsMid = 40, -- desktops only
	FpsMidSeconds = 10,
	WarmupSeconds = 20, -- no measuring right after join (streaming burst)
	-- A desktop holding a steady 30 fps (Roblox's frame-rate cap, 30 Hz screens, laptops on battery:
	-- within SteadyFpsTolerance, no frame longer than SteadyMaxFrame frame periods) runs smoothly and
	-- is not demoted to "mid" for being under FpsMid. SteadyFps = 0 turns the exception off.
	SteadyFps = 30,
	SteadyFpsTolerance = 2.5,
	SteadyMaxFrame = 1.5,
	MobileSmallScreen = 500, -- touch device with a keyboard but a viewport short side <= this px = phone
	-- SAVER sub-level of "low": on when a phone on "low" still stays under SaverFps for SaverSeconds
	SaverFps = 22,
	SaverSeconds = 8,
}

-- Local look / cost switches per tier (MobileQuality). The server never writes Enabled or
-- Bloom.Size, so these local changes stick; they are re-applied if something else writes them.
Config.Mobile = {
	PostFx = {
		-- low: also no sun shadow map (GlobalShadows) and no animated grass (Terrain.Decoration):
		-- the shadow pass re-draws every shadow-casting part in view on the phone's GPU
		low = { DepthOfField = false, SunRays = false, Clouds = false, BloomMaxSize = 16, GlobalShadows = false, TerrainDecoration = false },
		mid = { DepthOfField = false, SunRays = true, Clouds = true, BloomMaxSize = 22 },
		high = { DepthOfField = true, SunRays = true, Clouds = true }, -- as built
		-- saver (weak phones on low): also no bloom pass
		saver = { DepthOfField = false, SunRays = false, Clouds = false, BloomMaxSize = 16, GlobalShadows = false, TerrainDecoration = false, Bloom = false },
	},
	-- SurfaceGui draw distance and texture density (the originals are kept in the attributes
	-- GwMaxDistance0 / GwPixelsPerStud0 on each gui so a tier change restores them).
	SurfaceGuiDistanceScale = { low = 0.6, mid = 0.85, high = 1, saver = 0.42 },
	SurfaceGuiPixelScale = { low = 0.75, mid = 1, high = 1, saver = 0.6 },
	SurfaceGuiMinDistance = 40, -- a scaled draw distance never drops below this (bowling consoles: 60)
	-- Upper-floor window glass (tag "Window", or parts named "Window" / "RoomGlass") above this world
	-- height turns opaque on "low" (transparent parts are drawn one by one, with overdraw). The
	-- colour is darkened a little (OpaqueWindowDarken for a pane of Transparency 0.2, scaled with
	-- the pane's transparency) and the reflectance kept so it still reads as glass. Panes that are
	-- already opaque are left alone.
	OpaqueUpperWindows = { low = true, mid = false, high = false },
	UpperWindowY = 20,
	OpaqueWindowDarken = 0.12,
	OpaqueWindowMinReflectance = 0.18,
	-- Models named "RoomDepth" (fake rooms behind upper-floor glass) are hidden on these tiers.
	HideRoomDepth = { low = true, mid = false, high = false },
	-- Instances discovered by name / class (one shared Workspace DescendantAdded listener; tags are
	-- used first where the builders set them) are processed in batches of this many per frame.
	DiscoverPerFrame = { low = 150, mid = 300, high = 600, saver = 120 },
	-- One work budget per frame shared by every chunked client queue (tag arrivals, discovery, local
	-- hide / show, day-night and tier sweeps; each also keeps its own cap above). After a quick-travel
	-- they are all busy at once; this caps their sum (each busy queue still gets 16 per frame).
	FrameWriteBudget = { low = 350, mid = 700, high = 1200, saver = 260 },
	-- false: tags only (Window, NearLOD, RoomDepth). SurfaceGuis carry no tag, so they would then keep
	-- their built draw distance / density, and untagged LOD = "near" models would stay visible.
	ScanDescendants = true,
}

-- Near-only detail (Models with attribute LOD = "near": shop props, car interiors): hidden beyond
-- Radius studs from the camera with LocalTransparencyModifier (no reparenting, streaming-safe).
Config.DetailLOD = {
	Radius = { low = 70, mid = 100, high = 150, saver = 48 }, -- (high 150: rule 9 of the build made facade trims near-only too)
	Hysteresis = 12, -- shown again inside Radius, hidden again beyond Radius + Hysteresis
	UpdateHz = 3,
	CellSize = 64,
	PartsPerFrame = { low = 200, mid = 400, high = 800 }, -- LocalTransparencyModifier writes per frame
	-- Arrive hidden (GwangalliEnvironment.server section 5): eligible near models (no script-driven
	-- parts, guis, lights, effects, prompts; not in a zone / RoomDepth / vehicle / home) are saved
	-- with Transparency 1 at server start, so they stream in hidden and a phone only pays for the
	-- few it shows. false = every near model keeps the LocalTransparencyModifier path.
	ArriveHidden = true,
}

-- Night look for signs / parts / windows.
Config.Night = {
	NeonTint = Color3.fromRGB(255, 206, 150), -- NightNeon parts are tinted toward this at night
	NeonTintAmount = 0.35,
	GlowBrightnessScale = 1.0, -- multiplier for NightGlow SurfaceGui GlowBrightness
	WindowLitFraction = 0.4, -- share of "Window" glass parts lit at night
	WindowColors = { -- weighted palette for lit windows (muted so bloom stays tasteful)
		{ weight = 0.45, color = Color3.fromRGB(196, 146, 92) }, -- warm incandescent
		{ weight = 0.25, color = Color3.fromRGB(190, 178, 156) }, -- warm white LED
		{ weight = 0.20, color = Color3.fromRGB(146, 172, 196) }, -- cool fluorescent
		{ weight = 0.10, color = Color3.fromRGB(108, 128, 188) }, -- TV glow
	},
}

-- LED screens (tag LEDScreen, attribute Messages = "a|b|c").
Config.Screens = {
	MessageSeconds = 3,
	MaxDistance = 700, -- screens further than this are not updated
	-- Text changes re-fit TextScaled labels; phones only update the nearby screens.
	Tier = { low = { MaxDistance = 350 }, mid = { MaxDistance = 550 }, saver = { MaxDistance = 220 } },
}

---------------------------------------------------------------------------------------------
-- Traffic signals (synchronised with workspace:GetServerTimeNow())
---------------------------------------------------------------------------------------------
Config.Traffic = {
	Green = 12,
	Amber = 3,
	AllRed = 2,
	PedFlash = 4, -- last seconds of pedestrian green that blink
	ArrowWithGreen = true, -- left-turn arrow lit together with green (직좌 동시신호)
	UpdateInterval = 0.25,
	MaxDistance = 900, -- housings further than this from the camera are not updated
	Tier = { low = { MaxDistance = 450, UpdateInterval = 0.3 }, mid = { MaxDistance = 650 }, saver = { MaxDistance = 300, UpdateInterval = 0.5 } },
	Colors = {
		Red = Color3.fromRGB(255, 42, 32),
		Amber = Color3.fromRGB(255, 176, 24),
		Green = Color3.fromRGB(24, 236, 160),
		Arrow = Color3.fromRGB(24, 236, 160),
		PedRed = Color3.fromRGB(255, 50, 40),
		PedGreen = Color3.fromRGB(40, 240, 130),
	},
	OffColorScale = 0.35, -- "off" lamps: original colour darkened (fallback when unknown)
}

---------------------------------------------------------------------------------------------
-- Gwangan Bridge LED shows (tag BridgeLED, attribute Segment 0..1)
---------------------------------------------------------------------------------------------
Config.Bridge = {
	-- Fallback centre (suspension span, Plan.bridge.centerZ / upperDeckY) when no BridgeLED part
	-- is streamed in yet.
	Center = Vector3.new(0, 150, -3300),
	MaxDistance = 9000, -- animate within this distance; beyond it (at night) the LEDs hold StaticColor
	UpdateHz = 10, -- every LED is refreshed about this often (in chunks)
	MaxPerFrame = 700,
	ColorTolerance = 0.012, -- colours are written only when R+G+B changed by more than this
	PatternSeconds = 36, -- each pattern plays this long, then crossfades to the next
	CrossfadeSeconds = 3,
	-- Updates pause (colours freeze) while every sample point along the bridge is more than
	-- ~78 degrees off the view direction (dot < ViewDot) and the camera is not close to it.
	ViewDot = 0.2,
	ViewNear = 450, -- studs: closer than this to any sample point counts as "in view"
	StaticColor = Color3.fromRGB(60, 110, 230), -- lit but not animated (night, out of range)
	-- "low": Grouped mode. The 1,372 LEDs are bucketed into Groups along Segment; a 10 Hz tick
	-- computes one colour per group and rewrites a whole group only when its colour changed,
	-- at most MaxWritesPerTick part writes per tick (~0.6k writes/s instead of ~8k).
	Tier = {
		-- (phones: 6 Hz ticks, <= 100 part writes each: <= 600 writes/s)
		low = { MaxDistance = 4500, Grouped = true, Groups = 40, TickHz = 6, MaxWritesPerTick = 100, ColorTolerance = 0.06 },
		saver = { MaxDistance = 3500, Groups = 24, TickHz = 3, MaxWritesPerTick = 60, ColorTolerance = 0.1 },
		mid = { MaxDistance = 6500, UpdateHz = 6, MaxPerFrame = 350, ColorTolerance = 0.02 },
	},
}

---------------------------------------------------------------------------------------------
-- Doors, travel, HUD
---------------------------------------------------------------------------------------------
Config.Doors = {
	Radius = 10, -- studs from the door model pivot (model attribute OpenRadius overrides)
	CloseDelay = 1.5, -- seconds without anyone in range before closing (attribute CloseDelay)
	TweenTime = 0.6,
	CheckInterval = 0.15,
}

Config.Travel = {
	Cooldown = 3, -- seconds between successful travels
	SpamInterval = 0.4, -- minimum seconds between any two requests
	LiftStuds = 3, -- target = destination CFrame + this many studs up
	StreamTimeout = 8, -- seconds to wait for the area to stream in before moving (LTE phones: 4 s was short)
}

Config.Sprint = {
	WalkSpeed = 16,
	RunSpeed = 26,
	KeyMode = "hold", -- "hold" (Shift held) or "toggle" (Shift toggles); the touch button always toggles
	Keys = { Enum.KeyCode.LeftShift },
	GamepadToggle = Enum.KeyCode.ButtonL3,
	RebindShiftLock = true, -- move Shift Lock to LeftControl/RightShift so LeftShift can sprint
	ShiftLockKeys = "LeftControl,RightShift",
}

Config.HUD = {
	LocationName = "광안리 · GWANGALLI",
	TravelKey = Enum.KeyCode.M,
	DisplayOrder = 5,
}

-- "real": signs carry the real business names researched for the map (builders read this
-- through the build too). Kept here so runtime systems can branch on it later.
Config.SignageMode = "real"

return Config
