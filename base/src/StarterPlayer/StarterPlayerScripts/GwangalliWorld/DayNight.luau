-- GwangalliWorld/DayNight (client): the local day/night clock and look.
--
-- The server only publishes the clock as workspace attributes (GwangalliClockAnchorTime /
-- GwangalliClockAnchorClock / GwangalliClockRate, set when the clock is re-anchored; a coarse
-- GwangalliClock about once a second) and the night state (GwangalliIsNight, GwangalliPhase).
-- It never writes Lighting after start. This module computes everything else locally:
--   * Lighting.ClockTime from the anchor, written whenever the sun has moved enough for the
--     quality tier (GwangalliQuality), at the default 24-minute day: about 1 Hz on low (phones),
--     6 Hz on mid and 15 Hz on high. A low step is 0.25 degrees of sun, which does not show, and
--     each sun move makes the voxel lighting that phones fall back to re-light, so fewer moves
--     spare their lighting thread.
--   * The base look, blended between keyframes (dawn / day / golden hour / sunset / blue hour /
--     night): Brightness, ExposureCompensation, Ambient, OutdoorAmbient, ColorShift_Top,
--     ShadowSoftness, the Atmosphere (density, colour, decay, haze and glare, i.e. the sky tones),
--     the colour grade, SunRays.Intensity, Bloom.Intensity / Threshold, the Clouds colour / Cover /
--     Density and the sea (Terrain.WaterColor / WaterReflectance). No writes at all while
--     the keyframes are flat (19:48-04:36 and 08:48-15:36), 1-4 blends/s otherwise.
--     While Lighting.GlobalShadows is off (phones), Ambient is lifted toward OutdoorAmbient
--     (Roblox lights everything with Ambient then); a GlobalShadows change re-blends at once.
--     The per-tier post-FX switches (Enabled on DepthOfField / SunRays / Clouds, Bloom.Size) belong
--     to GwangalliWorld/MobileQuality. This module never writes those properties.
--   * isNight() / onChanged(fn). The source of truth is workspace.GwangalliIsNight, which
--     ClubLights and other scripts read too. When it is missing, the night window is applied to
--     the local clock. isNight() already answers from the attribute before init() (Lights starts
--     before game.Loaded).
--   * Requiring the module primes ClockTime and the look once (see the end of the file), so the
--     sky is already right when the loading screen goes away.
--
-- Public API (GwangalliWorldBoot and the world modules): init(shared), isNight(), onChanged(fn),
-- clock().

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DayNight = {}

local CLOCK_ATTR = "GwangalliClock"
-- = GwangalliShared.Attr.* (usable before init, when Shared is not known yet)
local IS_NIGHT_ATTR = "GwangalliIsNight"
local ANCHOR_TIME_ATTR = "GwangalliClockAnchorTime"
local ANCHOR_CLOCK_ATTR = "GwangalliClockAnchorClock"
local RATE_ATTR = "GwangalliClockRate"
local JUMP_HOURS = 0.25 -- a clock change bigger than this is a jump (debug SetClock): apply at once
-- Share of the way Ambient is lifted toward OutdoorAmbient while Lighting.GlobalShadows is off
-- (phones: Roblox then uses Ambient for every surface; see applyLook).
local NO_SHADOW_AMBIENT_MIX = 0.6
-- Local effects other scripts add to Lighting (ClubLights' interior grade): never ours to blend.
local FOREIGN_EFFECTS: { [string]: boolean } = { ClubOceanGrade = true }

---------------------------------------------------------------------------------------------------
-- Keyframes (moved from the server). t = clock. Colours are chosen for Future lighting; night
-- keeps enough ambient to stay readable.
---------------------------------------------------------------------------------------------------
local rgb = Color3.fromRGB
-- Photo presets, tuned against photos of Gwangalli / Suyeong Bay (sea pass, then the look_roblox
-- pass of 10-03). build/kit/look.luau carries the exact blend of this table at 17.2 (smoothstep
-- between the 16.6 and 17.4 keys): recompute it there when those keys change. Keys: night (flat
-- 19:48-04:36), pre-dawn blue, sunrise out of the sea, morning mist, day (flat 08:48-15:36), late
-- afternoon, golden hour, sunset, blue hour. Sun path: see GeographicLatitude in look.luau (the
-- sun crosses the bay side of the sky, rising at +X and setting at -X).
--   * The day keeps the sunlit side bright (Brightness 2.8) but the shade cooler and darker than
--     before (OutdoorAmbient 114,118,130 instead of 136,136,142): with EnvironmentDiffuseScale 1
--     the sky already fills the shadows, and the old value flattened every facade.
--   * Exposure rides the time of day (0 by day, +0.1 golden, +0.2 sunset, +0.32 blue hour/night),
--     like a camera's auto exposure, so dusk keeps detail without lifting the black of the sea.
--   * Soft = Lighting.ShadowSoftness: crisp at noon (0.18), longer softer shadows at golden hour /
--     sunset, soft moonlight at night.
-- Terrain water (Water = WaterColor, WaterRefl = WaterReflectance) and the cloud deck (Cover,
-- CloudDensity) follow the time of day too.
local KEYS = {
	-- night (flat to 04:36): inky blue sea, near-black zenith, warm mauve Busan glow on the haze / cloud base
	{ t = 0.0, Brightness = 1.0, Exposure = 0.35, Outdoor = rgb(78, 86, 116), Ambient = rgb(52, 56, 80), Shift = rgb(8, 12, 30),
		Density = 0.34, AtmColor = rgb(92, 78, 96), Decay = rgb(20, 26, 54), Haze = 1.7, Glare = 0,
		Tint = rgb(224, 232, 255), Saturation = 0.1, Contrast = 0.14, SunRays = 0, Bloom = 1.0, Threshold = 1.2, Clouds = rgb(84, 72, 84), Grade = 0.02,
		Water = rgb(6, 22, 40), WaterRefl = 0.9, Cover = 0.38, CloudDensity = 0.34, Soft = 0.5 },
	{ t = 4.6, Brightness = 1.0, Exposure = 0.35, Outdoor = rgb(78, 86, 116), Ambient = rgb(52, 56, 80), Shift = rgb(8, 12, 30),
		Density = 0.34, AtmColor = rgb(92, 78, 96), Decay = rgb(20, 26, 54), Haze = 1.7, Glare = 0,
		Tint = rgb(224, 232, 255), Saturation = 0.1, Contrast = 0.14, SunRays = 0, Bloom = 1.0, Threshold = 1.2, Clouds = rgb(84, 72, 84), Grade = 0.02,
		Water = rgb(6, 22, 40), WaterRefl = 0.9, Cover = 0.38, CloudDensity = 0.34, Soft = 0.5 },
	-- pre-dawn blue: violet-blue horizon over the bay, lights still on
	{ t = 5.3, Brightness = 1.1, Exposure = 0.32, Outdoor = rgb(82, 88, 118), Ambient = rgb(54, 58, 80), Shift = rgb(14, 14, 34),
		Density = 0.33, AtmColor = rgb(122, 114, 152), Decay = rgb(40, 48, 92), Haze = 1.9, Glare = 0.1,
		Tint = rgb(232, 234, 255), Saturation = 0.08, Contrast = 0.12, SunRays = 0, Bloom = 0.9, Threshold = 1.3, Clouds = rgb(142, 122, 152), Grade = 0.02,
		Water = rgb(10, 34, 60), WaterRefl = 0.86, Cover = 0.42, CloudDensity = 0.4, Soft = 0.5 },
	-- sunrise out of the sea beyond the bridge's Namcheon end (+X): rose-peach glare, pink cloud bellies, the bay mirrors it
	{ t = 5.9, Brightness = 1.5, Exposure = 0.22, Outdoor = rgb(118, 106, 122), Ambient = rgb(68, 62, 78), Shift = rgb(60, 30, 24),
		Density = 0.32, AtmColor = rgb(232, 168, 150), Decay = rgb(98, 104, 150), Haze = 2.2, Glare = 0.7,
		Tint = rgb(255, 234, 226), Saturation = 0.08, Contrast = 0.1, SunRays = 0.16, Bloom = 0.65, Threshold = 1.5, Clouds = rgb(246, 190, 176), Grade = 0.02,
		Water = rgb(18, 52, 80), WaterRefl = 0.8, Cover = 0.46, CloudDensity = 0.45, Soft = 0.42 },
	-- morning: soft sea mist, warm-white sun, long soft shadows
	{ t = 6.9, Brightness = 2.2, Exposure = 0.08, Outdoor = rgb(124, 124, 134), Ambient = rgb(70, 72, 82), Shift = rgb(22, 14, 6),
		Density = 0.28, AtmColor = rgb(220, 212, 204), Decay = rgb(106, 124, 152), Haze = 1.7, Glare = 0.3,
		Tint = rgb(255, 246, 238), Saturation = 0.08, Contrast = 0.1, SunRays = 0.1, Bloom = 0.5, Threshold = 1.7, Clouds = rgb(250, 240, 230), Grade = 0.01,
		Water = rgb(14, 68, 94), WaterRefl = 0.6, Cover = 0.48, CloudDensity = 0.5, Soft = 0.3 },
	-- day (flat 08:48-15:36): crisp sun, cool blue skylight in the shade, humid white sea haze that softens the bridge and Marine City
	{ t = 8.8, Brightness = 2.8, Exposure = 0, Outdoor = rgb(114, 118, 130), Ambient = rgb(68, 70, 80), Shift = rgb(12, 8, 2),
		Density = 0.26, AtmColor = rgb(204, 210, 218), Decay = rgb(100, 126, 160), Haze = 1.6, Glare = 0.2,
		Tint = rgb(255, 252, 247), Saturation = 0.08, Contrast = 0.12, SunRays = 0.05, Bloom = 0.42, Threshold = 1.85, Clouds = rgb(252, 250, 246), Grade = 0,
		Water = rgb(12, 76, 98), WaterRefl = 0.52, Cover = 0.5, CloudDensity = 0.58, Soft = 0.18 },
	{ t = 15.6, Brightness = 2.8, Exposure = 0, Outdoor = rgb(114, 118, 130), Ambient = rgb(68, 70, 80), Shift = rgb(12, 8, 2),
		Density = 0.26, AtmColor = rgb(204, 210, 218), Decay = rgb(100, 126, 160), Haze = 1.6, Glare = 0.2,
		Tint = rgb(255, 252, 247), Saturation = 0.08, Contrast = 0.12, SunRays = 0.05, Bloom = 0.42, Threshold = 1.85, Clouds = rgb(252, 250, 246), Grade = 0,
		Water = rgb(12, 76, 98), WaterRefl = 0.52, Cover = 0.5, CloudDensity = 0.58, Soft = 0.18 },
	-- late afternoon: the light warms, haze turns cream
	{ t = 16.6, Brightness = 2.6, Exposure = 0.05, Outdoor = rgb(124, 120, 122), Ambient = rgb(72, 70, 76), Shift = rgb(30, 18, 6),
		Density = 0.27, AtmColor = rgb(226, 206, 180), Decay = rgb(104, 120, 152), Haze = 1.7, Glare = 0.4,
		Tint = rgb(255, 244, 228), Saturation = 0.1, Contrast = 0.12, SunRays = 0.1, Bloom = 0.48, Threshold = 1.7, Clouds = rgb(255, 236, 210), Grade = 0,
		Water = rgb(13, 70, 96), WaterRefl = 0.58, Cover = 0.52, CloudDensity = 0.55, Soft = 0.24 },
	-- golden hour: low gold sun over the bay toward Millak / Marine City (-X) raking the beachfront facades; the sky away from the sun stays blue-grey
	{ t = 17.4, Brightness = 2.3, Exposure = 0.12, Outdoor = rgb(138, 122, 112), Ambient = rgb(80, 70, 70), Shift = rgb(58, 30, 8),
		Density = 0.29, AtmColor = rgb(242, 190, 140), Decay = rgb(110, 112, 146), Haze = 1.95, Glare = 0.75,
		Tint = rgb(255, 234, 210), Saturation = 0.14, Contrast = 0.13, SunRays = 0.18, Bloom = 0.6, Threshold = 1.55, Clouds = rgb(255, 206, 160), Grade = 0.01,
		Water = rgb(16, 62, 88), WaterRefl = 0.68, Cover = 0.54, CloudDensity = 0.52, Soft = 0.32 },
	-- sunset over the water behind Marine City: orange glare, rose clouds, the bay mirrors the warm sky
	{ t = 18.05, Brightness = 1.7, Exposure = 0.2, Outdoor = rgb(130, 104, 102), Ambient = rgb(80, 62, 66), Shift = rgb(80, 34, 12),
		Density = 0.31, AtmColor = rgb(246, 150, 104), Decay = rgb(116, 94, 132), Haze = 2.3, Glare = 1.0,
		Tint = rgb(255, 220, 198), Saturation = 0.16, Contrast = 0.13, SunRays = 0.2, Bloom = 0.7, Threshold = 1.45, Clouds = rgb(255, 160, 128), Grade = 0,
		Water = rgb(20, 54, 78), WaterRefl = 0.8, Cover = 0.55, CloudDensity = 0.5, Soft = 0.42 },
	-- blue hour: deep saturated blue sky and sea, the bridge LEDs and windows reading against it
	{ t = 18.8, Brightness = 1.15, Exposure = 0.32, Outdoor = rgb(86, 94, 134), Ambient = rgb(54, 60, 90), Shift = rgb(20, 16, 44),
		Density = 0.31, AtmColor = rgb(98, 110, 170), Decay = rgb(44, 54, 110), Haze = 2.0, Glare = 0.22,
		Tint = rgb(224, 232, 255), Saturation = 0.14, Contrast = 0.12, SunRays = 0.03, Bloom = 0.9, Threshold = 1.3, Clouds = rgb(110, 100, 148), Grade = 0.02,
		Water = rgb(10, 36, 66), WaterRefl = 0.86, Cover = 0.48, CloudDensity = 0.42, Soft = 0.5 },
	-- night
	{ t = 19.8, Brightness = 1.0, Exposure = 0.35, Outdoor = rgb(78, 86, 116), Ambient = rgb(52, 56, 80), Shift = rgb(8, 12, 30),
		Density = 0.34, AtmColor = rgb(92, 78, 96), Decay = rgb(20, 26, 54), Haze = 1.7, Glare = 0,
		Tint = rgb(224, 232, 255), Saturation = 0.1, Contrast = 0.14, SunRays = 0, Bloom = 1.0, Threshold = 1.2, Clouds = rgb(84, 72, 84), Grade = 0.02,
		Water = rgb(6, 22, 40), WaterRefl = 0.9, Cover = 0.38, CloudDensity = 0.34, Soft = 0.5 },
}
table.sort(KEYS, function(a, b)
	return a.t < b.t
end)

-- flatAfter[k] = true when KEYS[k] and the next key hold the same look (no blending needed).
local flatAfter: { [any]: boolean } = {}
do
	local n = #KEYS
	for i = 1, n do
		local a, b = KEYS[i], KEYS[i % n + 1]
		local same = true
		for field, value in a do
			if field ~= "t" and b[field] ~= value then
				same = false
				break
			end
		end
		flatAfter[a] = same
	end
end

local function sampleKeys(clock: number)
	local n = #KEYS
	for i = 1, n do
		local a, b = KEYS[i], KEYS[i % n + 1]
		local ta, tb = a.t, b.t
		if tb <= ta then
			tb += 24
		end
		local c = clock
		if c < ta then
			c += 24
		end
		if c >= ta and c < tb then
			local f = (c - ta) / (tb - ta)
			return a, b, f * f * (3 - 2 * f)
		end
	end
	return KEYS[1], KEYS[1], 0
end

local function lerp(a: number, b: number, f: number): number
	return a + (b - a) * f
end

---------------------------------------------------------------------------------------------------
-- Quality tier
---------------------------------------------------------------------------------------------------
type TierSettings = {
	tick: number, -- seconds between updates
	clockStep: number, -- in-game hours the clock must move before Lighting.ClockTime is written
	lookInterval: number, -- seconds between keyframe blends
}
local TIERS: { [string]: TierSettings } = {
	low = { tick = 0.25, clockStep = 1 / 60, lookInterval = 1.0 },
	mid = { tick = 0.1, clockStep = 1 / 360, lookInterval = 0.5 },
	high = { tick = 1 / 30, clockStep = 1 / 1200, lookInterval = 0.25 },
	-- the saver sub-level of low (GwangalliQuality.isSaver: weak phones): the sun moves every 2 s
	saver = { tick = 0.5, clockStep = 2 / 60, lookInterval = 2.0 },
}

local Quality: any = nil
local function loadQuality()
	local mod = ReplicatedStorage:FindFirstChild("GwangalliQuality")
	if not mod or not mod:IsA("ModuleScript") then
		return
	end
	local ok, result = pcall(require, mod)
	if ok and type(result) == "table" and type(result.get) == "function" then
		Quality = result
	else
		warn("[GwangalliWorld/DayNight] GwangalliQuality failed to load: " .. tostring(result))
	end
end

local function currentTier(): string
	if Quality then
		local ok, t = pcall(Quality.get)
		if ok and TIERS[t] then
			if t == "low" and type(Quality.isSaver) == "function" then
				local okS, saver = pcall(Quality.isSaver)
				if okS and saver == true then
					return "saver"
				end
			end
			return t
		end
	end
	-- fallback: touch-only devices are phones / tablets -> low
	local okTouch, touchOnly = pcall(function()
		return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	end)
	return if okTouch and touchOnly then "low" else "high"
end

---------------------------------------------------------------------------------------------------
-- Effects (resolved once, re-resolved when replaced)
---------------------------------------------------------------------------------------------------
local effectCache: { [string]: Instance } = {}
local function effect(parent: Instance?, className: string): any
	if not parent then
		return nil
	end
	local key = className
	local cached = effectCache[key]
	if cached and cached.Parent == parent then
		return cached
	end
	local found: Instance? = parent:FindFirstChild(className)
	if not (found and found.ClassName == className) then
		found = nil
		for _, child in parent:GetChildren() do
			if child.ClassName == className and not FOREIGN_EFFECTS[child.Name] then
				found = child
				break
			end
		end
	end
	if found then
		effectCache[key] = found
	end
	return found
end

local function terrainOf(): Instance?
	return workspace:FindFirstChildOfClass("Terrain")
end

local tierName = "high"
local settings: TierSettings = TIERS.high

---------------------------------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------------------------------
local lastA, lastB, lastF = nil, nil, -1

local function applyLook(clock: number, force: boolean?)
	local a, b, f = sampleKeys(clock)
	if flatAfter[a] then
		b, f = a, 0
	end
	local q = math.floor(f * 1000 + 0.5) / 1000
	if not force and a == lastA and b == lastB and q == lastF then
		return -- nothing visible changed since the last blend
	end
	lastA, lastB, lastF = a, b, q
	f = q

	Lighting.Brightness = lerp(a.Brightness, b.Brightness, f)
	Lighting.ExposureCompensation = lerp(a.Exposure, b.Exposure, f)
	local outdoor = a.Outdoor:Lerp(b.Outdoor, f)
	local ambient = a.Ambient:Lerp(b.Ambient, f)
	-- Without GlobalShadows (MobileQuality turns them off on phones) Roblox ignores OutdoorAmbient
	-- and lights every surface with Ambient, the dim INDOOR value: the whole street went dull and
	-- dark on the low tier. Lift Ambient most of the way to OutdoorAmbient there (interiors still
	-- read a little darker), and back as soon as the shadows return (see the GlobalShadows hook).
	if not Lighting.GlobalShadows then
		ambient = ambient:Lerp(outdoor, NO_SHADOW_AMBIENT_MIX)
	end
	Lighting.OutdoorAmbient = outdoor
	Lighting.Ambient = ambient
	Lighting.ColorShift_Top = a.Shift:Lerp(b.Shift, f)
	if a.Soft and b.Soft then
		Lighting.ShadowSoftness = lerp(a.Soft, b.Soft, f)
	end

	local atmosphere = effect(Lighting, "Atmosphere")
	if atmosphere then
		atmosphere.Density = lerp(a.Density, b.Density, f)
		atmosphere.Color = a.AtmColor:Lerp(b.AtmColor, f)
		atmosphere.Decay = a.Decay:Lerp(b.Decay, f)
		atmosphere.Haze = lerp(a.Haze, b.Haze, f)
		atmosphere.Glare = lerp(a.Glare, b.Glare, f)
	end
	local grade = effect(Lighting, "ColorCorrectionEffect")
	if grade then
		grade.TintColor = a.Tint:Lerp(b.Tint, f)
		grade.Brightness = lerp(a.Grade or 0, b.Grade or 0, f)
		grade.Saturation = lerp(a.Saturation, b.Saturation, f)
		grade.Contrast = lerp(a.Contrast, b.Contrast, f)
	end
	-- written even while MobileQuality has the effect disabled, so it is right when re-enabled
	local rays = effect(Lighting, "SunRaysEffect")
	if rays then
		rays.Intensity = lerp(a.SunRays, b.SunRays, f)
	end
	local bloom = effect(Lighting, "BloomEffect")
	if bloom then
		bloom.Intensity = lerp(a.Bloom, b.Bloom, f)
		bloom.Threshold = lerp(a.Threshold, b.Threshold, f)
	end
	local terrain = terrainOf()
	local clouds = effect(terrain, "Clouds")
	if clouds then
		clouds.Color = a.Clouds:Lerp(b.Clouds, f)
		if a.Cover and b.Cover then
			clouds.Cover = lerp(a.Cover, b.Cover, f)
			clouds.Density = lerp(a.CloudDensity, b.CloudDensity, f)
		end
	end
	-- the sea: inky blue at night, deep blue-green by day, mirroring the warm sky at sunset
	if terrain and a.Water and b.Water then
		(terrain :: any).WaterColor = a.Water:Lerp(b.Water, f);
		(terrain :: any).WaterReflectance = lerp(a.WaterRefl, b.WaterRefl, f)
	end
end

---------------------------------------------------------------------------------------------------
-- Clock + night state
---------------------------------------------------------------------------------------------------
local Shared: any = nil
local night = false
local listeners: { (boolean) -> () } = {}
local started = false
local localClock: number? = nil -- last clock applied to Lighting.ClockTime
local lastLookAt = -math.huge
local forceNext = true

-- The server clock: the anchor attributes (smooth), else the coarse GwangalliClock, else nil.
local function serverClock(): number?
	local A = if Shared then Shared.Attr else nil
	local t0 = workspace:GetAttribute(if A then A.ClockAnchorTime else ANCHOR_TIME_ATTR)
	local c0 = workspace:GetAttribute(if A then A.ClockAnchorClock else ANCHOR_CLOCK_ATTR)
	local rate = workspace:GetAttribute(if A then A.ClockRate else RATE_ATTR)
	if type(t0) == "number" and type(c0) == "number" and type(rate) == "number" and t0 == t0 and c0 == c0 and rate == rate then
		return (c0 + (workspace:GetServerTimeNow() - t0) * rate) % 24
	end
	local coarse = workspace:GetAttribute(CLOCK_ATTR)
	if type(coarse) == "number" and coarse == coarse then
		return coarse % 24
	end
	return nil
end

local function computeNight(clock: number): boolean
	local attr = workspace:GetAttribute(Shared.Attr.IsNight)
	if type(attr) == "boolean" then
		return attr
	end
	return Shared.isNightClock(clock)
end

local function refreshNight(clock: number)
	local n = computeNight(clock)
	if n == night then
		return
	end
	night = n
	for _, fn in listeners do
		task.spawn(fn, n)
	end
end

local function update()
	local force = forceNext
	forceNext = false
	local clock = serverClock()
	if clock then
		local previous = localClock
		local delta = if previous then math.abs((clock - previous + 12) % 24 - 12) else math.huge
		if delta > JUMP_HOURS then
			force = true
		end
		if force or delta >= settings.clockStep then
			Lighting.ClockTime = clock
			localClock = clock
		end
	else
		clock = Lighting.ClockTime
	end
	local c = clock :: number
	local now = os.clock()
	if force or now - lastLookAt >= settings.lookInterval then
		lastLookAt = now
		applyLook(c, force)
	end
	refreshNight(c)
end

local function setTier(t: string)
	tierName = t
	settings = TIERS[t] or TIERS.high
end

function DayNight.init(shared: any)
	if started then
		return
	end
	started = true
	Shared = shared

	loadQuality()
	setTier(currentTier())
	if Quality and Quality.changed then
		pcall(function()
			local function onChange()
				local t = currentTier()
				if t ~= tierName then
					setTier(t)
				end
			end
			Quality.changed:Connect(onChange)
			if Quality.saverChanged then
				Quality.saverChanged:Connect(onChange)
			end
		end)
	end

	local ok, err = pcall(update)
	if not ok then
		warn("[GwangalliWorld/DayNight] " .. tostring(err))
	end
	night = computeNight(localClock or Lighting.ClockTime)

	local A = Shared.Attr
	workspace:GetAttributeChangedSignal(A.IsNight):Connect(function()
		pcall(refreshNight, localClock or Lighting.ClockTime)
	end)
	-- Re-anchored (debug jump, pause, day length): apply at once, not on the next tick. The server
	-- sets the three attributes together; one deferred update covers them all.
	local applyQueued = false
	local function applyNow()
		applyQueued = false
		local okNow, errNow = pcall(update)
		if not okNow then
			warn("[GwangalliWorld/DayNight] " .. tostring(errNow))
		end
	end
	local function queueApply()
		forceNext = true
		if not applyQueued then
			applyQueued = true
			task.defer(applyNow)
		end
	end
	for _, name in { A.ClockAnchorTime, A.ClockAnchorClock, A.ClockRate } do
		workspace:GetAttributeChangedSignal(name):Connect(queueApply)
	end
	-- MobileQuality switches the sun shadow map per tier: re-blend at once so Ambient gets (or
	-- loses) the no-shadow lift together with the shadows (an event, nothing polls it).
	Lighting:GetPropertyChangedSignal("GlobalShadows"):Connect(queueApply)

	task.spawn(function()
		while true do
			task.wait(settings.tick)
			local okUpdate, errUpdate = pcall(update)
			if not okUpdate then
				warn("[GwangalliWorld/DayNight] " .. tostring(errUpdate))
				task.wait(2)
			end
		end
	end)
end

function DayNight.isNight(): boolean
	if not started then
		local attr = workspace:GetAttribute(IS_NIGHT_ATTR)
		if type(attr) == "boolean" then
			return attr
		end
	end
	return night
end

function DayNight.onChanged(fn: (boolean) -> ())
	table.insert(listeners, fn)
end

-- Current local clock (hours, 0-24).
function DayNight.clock(): number
	return localClock or Lighting.ClockTime
end

-- Prime once at require time. GwangalliWorldBoot requires this module before game.Loaded but calls
-- init() after it; without this a late joiner would come out of the loading screen with the
-- place's saved golden-hour sky and Lighting.ClockTime (the server never updates them) and see
-- it jump to the real time a moment later. Effects that have not replicated yet are skipped;
-- init() applies everything again.
do
	local ok, err = pcall(function()
		local clock = serverClock()
		if clock then
			Lighting.ClockTime = clock
			localClock = clock
			applyLook(clock, true)
		end
	end)
	if not ok then
		warn("[GwangalliWorld/DayNight] prime: " .. tostring(err))
	end
end

return DayNight
