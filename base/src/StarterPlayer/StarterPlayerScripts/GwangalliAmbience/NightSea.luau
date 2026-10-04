-- GwangalliAmbience/NightSea (client): sky, breeze and the bridge-light reflections on the bay.
--
--   * Sky: a client-side Sky (default skybox textures) with a realistic small sun / moon disc and
--     city-dimmed stars (Busan's light pollution), only when the place has no Sky of its own.
--   * Breeze: Workspace.GlobalWind (local) blends the day sea breeze (onshore, from the bay, with
--     slow swells) into the weaker night land breeze (offshore) through dusk and dawn. Flags,
--     parasols, spray mist, clouds and terrain grass all follow it.
--   * Bridge reflections (night): Roblox water reflects the sky but not the lights, so the long
--     coloured light columns under 광안대교 are drawn: for a set of the bridge's LED parts (tag
--     BridgeLED, animated by GwangalliWorld/Bridge) a broken streak of Neon dashes lies on the water
--     from under the light toward the camera, fading with distance, its dashes shimmering, its
--     colour following the LED show. Re-aimed as the camera moves; hidden by day, far away or high
--     above. Cost: streaks x dashes parts (low 12 x 3 .. high 34 x 6), one BulkMoveTo per update,
--     colours at 2 Hz.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local NightSea = {}

local TIERS = {
	low = { streaks = 12, dashes = 3, hz = 4, colorHz = 1 },
	saver = { streaks = 6, dashes = 2, hz = 3, colorHz = 0.5 }, -- weak phones (GwangalliQuality saver)
	mid = { streaks = 22, dashes = 5, hz = 8, colorHz = 2 },
	high = { streaks = 34, dashes = 6, hz = 10, colorHz = 2 },
}
-- dash transparency from the far dash (under the light, TR_FAR) to the one nearest the camera
-- (TR_NEAR), spread evenly over however many dashes the tier uses
local TR_FAR, TR_NEAR = 0.22, 0.82
local function dashTr(j: number, n: number): number
	return if n <= 1 then TR_FAR else TR_FAR + (TR_NEAR - TR_FAR) * (j - 1) / (n - 1)
end
local ANGULAR_W = 0.0048 -- dash width / distance from the camera (~0.28 degrees)
local GAP = 0.04 -- share of each dash span left dark at both ends (small: the column reads unbroken)

function NightSea.start(Env: any)
	local cfg = Env.pick(TIERS)
	Env.onTier(function()
		cfg = Env.pick(TIERS)
	end)

	-- Sky ------------------------------------------------------------------------------------------
	pcall(function()
		if not Lighting:FindFirstChildOfClass("Sky") then
			local sky = Instance.new("Sky")
			sky.Name = "GwangalliSky"
			sky.SunAngularSize = 11
			sky.MoonAngularSize = 8
			sky.StarCount = 800 -- Busan light pollution: only the brighter stars
			sky.Parent = Lighting
		end
	end)

	-- Breeze ---------------------------------------------------------------------------------------
	local DAY_WIND = Vector3.new(-3, 0, 10)
	local NIGHT_WIND = Vector3.new(2.5, 0, -5.5)
	local lastWind: Vector3? = nil
	local canWriteWind = true
	Env.every("breeze", 1, function(now: number)
		local k = Env.daylight()
		local swell = 1 + 0.18 * math.sin(now / 37) + 0.08 * math.sin(now / 11.3)
		local w = (NIGHT_WIND:Lerp(DAY_WIND, k)) * swell
		if canWriteWind and (not lastWind or (w - (lastWind :: Vector3)).Magnitude > 0.25) then
			local ok = pcall(function()
				workspace.GlobalWind = w
			end)
			if ok then
				lastWind = w
			else
				canWriteWind = false
			end
		end
		Env.readWind()
	end)

	-- Bridge reflections -----------------------------------------------------------------------------
	local B = Env.D.bridge
	local bridgeZ = if type(B) == "table" and tonumber(B.z) then B.z else -3300
	local deckY = if type(B) == "table" and tonumber(B.deckY) then B.deckY else 150
	local anchorX = if type(B) == "table" and tonumber(B.anchorX) then B.anchorX else 1500
	local root = Env.sub("BridgeReflections")
	root.Parent = nil

	type Streak = { source: BasePart?, base: Vector3, color: Color3, dashes: { BasePart }, phase: number }
	local sizeCache: { [BasePart]: Vector3 } = {}
	local trCache: { [any]: number } = {}
	local streaks: { Streak } = {}
	local leds: { BasePart } = {}
	local ledsDirty = true
	local function onLed(inst: Instance)
		if inst:IsA("BasePart") then
			ledsDirty = true
		end
	end
	CollectionService:GetInstanceAddedSignal("BridgeLED"):Connect(onLed)
	CollectionService:GetInstanceRemovedSignal("BridgeLED"):Connect(onLed)

	local function pickSources(n: number): { any }
		-- LEDs on the beach-facing side of the suspension section, spread along its length
		table.clear(leds)
		for _, inst in CollectionService:GetTagged("BridgeLED") do
			if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
				local p = inst.Position
				if math.abs(p.X) < anchorX + 60 and p.Z > bridgeZ - 8 and p.Y > deckY - 60 then
					table.insert(leds, inst)
				end
			end
		end
		table.sort(leds, function(a, b)
			return a.Position.X < b.Position.X
		end)
		local out = {}
		if #leds > 0 then
			for i = 1, n do
				local led = leds[math.clamp(math.floor((i - 0.5) / n * #leds) + 1, 1, #leds)]
				table.insert(out, { source = led, base = Vector3.new(led.Position.X, 0, led.Position.Z) })
			end
		else
			-- no LEDs streamed / built: warm white deck lights along the main span
			for i = 1, n do
				local x = -anchorX + (i - 0.5) / n * anchorX * 2
				table.insert(out, { source = nil, base = Vector3.new(x, 0, bridgeZ + 30) })
			end
		end
		return out
	end

	local function clearStreaks()
		for _, s in streaks do
			for _, d in s.dashes do
				sizeCache[d] = nil
				trCache[d] = nil
				d:Destroy()
			end
		end
		table.clear(streaks)
	end

	local fallback = false
	local function buildStreaks()
		clearStreaks()
		local sources = pickSources(cfg.streaks)
		fallback = #leds == 0
		for i, src in sources do
			local dashes = {}
			for j = 1, cfg.dashes do
				local d = Env.part(root, Vector3.new(6, 0.05, 20), Color3.fromRGB(255, 240, 210), Enum.Material.Neon, dashTr(j, cfg.dashes), "BridgeReflection")
				table.insert(dashes, d)
			end
			table.insert(streaks, { source = src.source, base = src.base, color = Color3.fromRGB(255, 240, 210), dashes = dashes, phase = Env.hash(i, 9.1) * 6.28 })
		end
		ledsDirty = false
	end

	local shown = false
	local builtFor = ""
	local colorAcc = 0
	local partsOut: { BasePart } = {}
	local cfOut: { CFrame } = {}

	Env.every("reflections", function()
		return if shown then cfg.hz else 1
	end, function(now: number, dt: number)
		local cam = Env.focus()
		local horiz = Vector3.new(cam.X, 0, cam.Z)
		local toBridge = (horiz - Vector3.new(0, 0, bridgeZ)).Magnitude
		-- (from high above, e.g. the bridge deck or a rooftop, the columns would need a different
		-- construction: shown only from the shore, promenade and low buildings)
		local want = Env.isNight() and toBridge < 6500 and cam.Y < 90 and cam.Z > bridgeZ + 150
		if want ~= shown then
			shown = want
			root.Parent = if want then Env.folder else nil
		end
		if not shown then
			return
		end
		local key = cfg.streaks .. "x" .. cfg.dashes
		if key ~= builtFor or (ledsDirty and (fallback or #streaks == 0)) then
			builtFor = key
			buildStreaks()
		end
		-- colours follow the LED show
		colorAcc += dt
		local doColor = colorAcc >= 1 / cfg.colorHz
		if doColor then
			colorAcc = 0
		end
		-- Geometry of a reflection column: a light at height h, horizontal distance D, seen from a
		-- camera at height hc mirrors at dm = hc * D / (h + hc) from the camera (a few hundred studs
		-- for a beach camera). Wave facets smear it from the horizon (under the light) down to about
		-- that point, so the dashes run from under the light to ~0.7 dm, spaced geometrically (equal
		-- steps on screen) and ANGULAR_W wide as seen from the camera (width grows with distance).
		local camH = math.max(2, cam.Y)
		for _, s in streaks do
			local src = s.source
			local lightY = deckY
			if src and src.Parent then
				local sp = src.Position
				s.base = Vector3.new(sp.X, 0, sp.Z)
				lightY = math.max(20, sp.Y)
			end
			local toBase = Vector3.new(s.base.X - cam.X, 0, s.base.Z - cam.Z)
			local D = toBase.Magnitude
			if D < 80 or (not doColor and Env.behind(s.base, 0)) then
				continue -- (behind the camera: the dashes lie between it and the light, all out of view)
			end
			local dir = toBase / D
			local dm = camH * D / (lightY + camH)
			local dNear = math.clamp(dm * 0.7, 30, D * 0.5)
			local nd = #s.dashes
			local ratio = (dNear / D) ^ (1 / nd)
			if doColor then
				local c = if src and src.Parent then src.Color else Color3.fromRGB(255, 236, 200)
				local lum = c.R * 0.3 + c.G * 0.59 + c.B * 0.11
				s.color = c
				for j, d in s.dashes do
					d.Color = c
					Env.setNum(d, "Transparency", if lum < 0.08 then 1 else dashTr(j, #s.dashes), trCache, 0.01)
				end
			end
			local camG = Vector3.new(cam.X, 0.2, cam.Z)
			for j, d in s.dashes do
				-- j = 1 is the far dash under the light, j = nd the one nearest the camera
				local far = D * ratio ^ (j - 1)
				local near = D * ratio ^ j
				local span = far - near
				local wob = 0.06 * span * math.sin(now * 1.3 + j * 1.7 + s.phase)
				local a = near + span * GAP + wob
				local b = far - span * GAP + wob
				local len = math.max(1, b - a)
				local md = (a + b) * 0.5
				local mid = camG + dir * md
				-- the glitter spreads a little toward the viewer (wider, fainter near dashes)
				local spread = 1 + 0.3 * (j - 1) / math.max(1, nd - 1)
				local w = math.max(0.25, md * ANGULAR_W * spread * (1 + 0.15 * math.sin(now * 2.1 + j + s.phase)))
				local have = sizeCache[d]
				if not have or math.abs(have.Z - len) > len * 0.03 or math.abs(have.X - w) > w * 0.05 then
					local want3 = Vector3.new(w, 0.05, len)
					sizeCache[d] = want3
					d.Size = want3
				end
				table.insert(partsOut, d)
				table.insert(cfOut, CFrame.lookAt(mid, mid + dir))
			end
		end
		Env.move(partsOut, cfOut)
		table.clear(partsOut)
		table.clear(cfOut)
	end)
end

return NightSea
