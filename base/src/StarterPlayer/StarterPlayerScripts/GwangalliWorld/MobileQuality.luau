-- MobileQuality: local look / cost switches per quality tier (GwangalliQuality: low / mid / high).
-- Everything here is a client-local override that a tier change undoes (originals are kept),
-- and nothing runs per frame: work happens on discovery (streaming), on external writes to the
-- overridden properties, and on tier changes.
--   * Post FX (Config.Mobile.PostFx): low turns DepthOfField, SunRays and Terrain Clouds off and
--     caps Bloom.Size (16); Atmosphere and ColorCorrection stay (cheap, they carry the look).
--     low also turns Lighting.GlobalShadows (the sun shadow map) and Terrain.Decoration (animated
--     grass) off: the two biggest GPU switches a script can reach on a phone. The saver sub-level
--     of low (GwangalliQuality.isSaver: a phone still under ~22 fps) also turns the Bloom pass off,
--     and shortens SurfaceGui draw distances further (x0.42, texture density x0.6).
--     The server writes Bloom.Intensity / Threshold and SunRays.Intensity, never Enabled or
--     Bloom.Size; if anything writes an overridden property anyway, its value becomes the new
--     original and the override is re-applied.
--   * SurfaceGuis (every one in Workspace, found through the shared Util.discover listener, so
--     guis that stream in later are handled too): MaxDistance x SurfaceGuiDistanceScale (0.6 on
--     low) and, for sign-kit guis ("SignGui", scale-based layouts), PixelsPerStud x
--     SurfaceGuiPixelScale (0.75 on low, ~0.56x texture memory). The originals are stored in the
--     attributes GwMaxDistance0 / GwPixelsPerStud0 on the gui and in the gui's registry record,
--     which wins: a gui that streams out and back in as the same object may come back with
--     either its server values or our local ones, and attributes may or may not survive that trip.
--   Known guis and rooms live in strong Util.registry sets (pruned in the background once they
--   leave the Workspace), never in weak-keyed tables: a tier change must reach every one of them.
--   * Models named "RoomDepth" (fake rooms behind upper-floor glass, or tagged "RoomDepth") are
--     hidden on tiers with Config.Mobile.HideRoomDepth (LocalTransparencyModifier via
--     Util.setHidden; nothing is reparented).
--   * Upper-floor window glass opacity is applied by Signage (it owns every window-glass write,
--     because the night lighting changes the same properties).
--   * Dynamic light budgets are tier-driven in Lights (Config.Lights.low / mid / high).

local Lighting = game:GetService("Lighting")

local MobileQuality = {}

function MobileQuality.start(ctx: any)
	local Config, Util = ctx.Config, ctx.Util
	local cfg = Config.Mobile or {}

	local function tierValue(map: any, default: any): any
		if type(map) ~= "table" then
			return default
		end
		local v = Util.budget(map)
		if v == nil then
			return default
		end
		return v
	end

	-----------------------------------------------------------------------------------------------
	-- Post FX
	-----------------------------------------------------------------------------------------------
	-- Built-in tier defaults (look_roblox pass), used for every key Config.Mobile.PostFx does not
	-- set, so a phone sheds the heavy passes even if the config table is trimmed: low = no depth of
	-- field, sun rays, cloud layer, sun shadow map or animated grass, bloom radius capped; saver
	-- (a phone still under ~22 fps) also drops the bloom pass; mid keeps rays / clouds, no DoF.
	-- Atmosphere and ColorCorrection always stay: they are cheap and carry the look (the haze also
	-- hides the streaming edge). Light shadows are tiered in GwangalliWorld/Lights (hero lights).
	local DEFAULT_POSTFX = {
		low = { DepthOfField = false, SunRays = false, Clouds = false, BloomMaxSize = 16, GlobalShadows = false, TerrainDecoration = false },
		mid = { DepthOfField = false, SunRays = true, Clouds = true, BloomMaxSize = 22 },
		high = { DepthOfField = true, SunRays = true, Clouds = true },
		saver = { DepthOfField = false, SunRays = false, Clouds = false, BloomMaxSize = 16, GlobalShadows = false, TerrainDecoration = false, Bloom = false },
	}
	local function postFx(): { [string]: any }
		local base = tierValue(DEFAULT_POSTFX, {})
		local over = tierValue(cfg.PostFx, {})
		local merged = {}
		for k, v in base do
			merged[k] = v
		end
		if type(over) == "table" then
			for k, v in over do
				merged[k] = v
			end
		end
		return merged
	end
	type FxRec = { enabled: boolean, size: number?, wroteEnabled: boolean?, wroteSize: number? }
	local fx: { [Instance]: FxRec } = {}
	-- Enabled switched per tier (PostFx[tier][key] == false turns it off); Bloom also has its Size
	-- capped (BloomMaxSize) and is switched off only by the saver level (Bloom = false)
	local FX_KEY = {
		DepthOfFieldEffect = "DepthOfField",
		SunRaysEffect = "SunRays",
		Clouds = "Clouds",
		BloomEffect = "Bloom",
	}

	local function applyFx(inst: any)
		local rec = fx[inst]
		if not rec or inst.Parent == nil then
			return
		end
		local s = postFx()
		local key = FX_KEY[inst.ClassName]
		if key then
			local want = rec.enabled and s[key] ~= false
			rec.wroteEnabled = want
			if inst.Enabled ~= want then
				inst.Enabled = want
			end
		end
		if inst.ClassName == "BloomEffect" and rec.size then
			local want = rec.size
			local cap = tonumber(s.BloomMaxSize)
			if cap then
				want = math.min(want, cap)
			end
			rec.wroteSize = want
			if inst.Size ~= want then
				inst.Size = want
			end
		end
	end

	local function registerFx(inst: Instance)
		if fx[inst] then
			return
		end
		local cn = inst.ClassName
		if not FX_KEY[cn] then
			return
		end
		local any = inst :: any
		local rec: FxRec = { enabled = any.Enabled, size = if cn == "BloomEffect" then any.Size else nil }
		fx[inst] = rec
		-- Someone else wrote an overridden property: adopt it as the new original, re-apply.
		inst:GetPropertyChangedSignal("Enabled"):Connect(function()
			if any.Enabled ~= rec.wroteEnabled then
				rec.enabled = any.Enabled
				applyFx(inst)
			end
		end)
		if cn == "BloomEffect" then
			inst:GetPropertyChangedSignal("Size"):Connect(function()
				if any.Size ~= rec.wroteSize then
					rec.size = any.Size
					applyFx(inst)
				end
			end)
		end
		inst.AncestryChanged:Connect(function()
			if inst.Parent == nil then
				fx[inst] = nil
			end
		end)
		applyFx(inst)
	end

	local function safeRegister(inst: Instance)
		local ok, err = pcall(registerFx, inst)
		if not ok then
			Util.warn("MobileQuality", "post fx:", err)
		end
	end

	for _, child in Lighting:GetChildren() do
		safeRegister(child)
	end
	Lighting.ChildAdded:Connect(safeRegister)
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		for _, child in terrain:GetChildren() do
			safeRegister(child)
		end
		terrain.ChildAdded:Connect(safeRegister)
	end

	-- Global render switches (PostFx[tier].GlobalShadows / TerrainDecoration = false): on phones the
	-- sun shadow map re-renders every shadow caster in view each frame (tens of thousands of parts
	-- here), and animated grass adds its own pass. Both are local, and the built values come back
	-- on a tier that does not switch them off. Nothing else writes these properties.
	local builtShadows = Lighting.GlobalShadows
	local builtDecoration: boolean? = nil
	if terrain then
		local ok, v = pcall(function()
			return (terrain :: any).Decoration
		end)
		if ok and type(v) == "boolean" then
			builtDecoration = v
		end
	end
	local function applyGlobals()
		local s = postFx()
		local wantShadows = builtShadows and s.GlobalShadows ~= false
		if Lighting.GlobalShadows ~= wantShadows then
			Lighting.GlobalShadows = wantShadows
		end
		if terrain and builtDecoration ~= nil then
			local wantDecoration = builtDecoration and s.TerrainDecoration ~= false
			pcall(function()
				if (terrain :: any).Decoration ~= wantDecoration then
					(terrain :: any).Decoration = wantDecoration
				end
			end)
		end
	end
	local okGlobals, errGlobals = pcall(applyGlobals)
	if not okGlobals then
		Util.warn("MobileQuality", "globals:", errGlobals)
	end

	-----------------------------------------------------------------------------------------------
	-- SurfaceGuis
	-----------------------------------------------------------------------------------------------
	local ATTR_MD, ATTR_PPS = "GwMaxDistance0", "GwPixelsPerStud0"
	local minDistance = tonumber(cfg.SurfaceGuiMinDistance) or 40
	type GuiRec = { md: number?, pps: number? }
	local guiReg = Util.registry()
	local PPS_MODE = Enum.SurfaceGuiSizingMode.PixelsPerStud

	-- Original value of a property we scale: the gui's record, then the attribute, then (first
	-- sight, before any write of ours) the live value, which is recorded in both places.
	local function original(gui: any, rec: GuiRec, key: string, attr: string, live: number, record: boolean): number?
		local store: any = rec
		local v = store[key]
		if v then
			return v
		end
		local a = gui:GetAttribute(attr)
		if type(a) == "number" then
			store[key] = a
			return a
		end
		if not record then
			return nil
		end
		store[key] = live
		gui:SetAttribute(attr, live)
		Util.spend(1)
		return live
	end

	local function applyGui(gui: any)
		local rec: GuiRec? = guiReg.map[gui]
		if not rec or not Util.inWorld(gui) then
			return
		end
		local dScale = tierValue(cfg.SurfaceGuiDistanceScale, 1)
		local pScale = tierValue(cfg.SurfaceGuiPixelScale, 1)
		-- draw distance
		local md0 = original(gui, rec, "md", ATTR_MD, gui.MaxDistance, dScale ~= 1)
		if type(md0) == "number" and md0 > 0 and md0 < math.huge then
			local want = if dScale == 1 then md0 else math.max(math.min(md0, minDistance), md0 * dScale)
			if math.abs(gui.MaxDistance - want) > 0.01 then
				gui.MaxDistance = want -- (counted by the queue that called us)
			end
		end
		-- texture density: sign-kit guis only (their layouts are all scale-based + TextScaled)
		if gui.Name == "SignGui" and gui.SizingMode == PPS_MODE then
			local pps0 = original(gui, rec, "pps", ATTR_PPS, gui.PixelsPerStud, pScale ~= 1)
			if type(pps0) == "number" and pps0 > 0 then
				local want = if pScale == 1 then pps0 else math.max(4, math.floor(pps0 * pScale + 0.5))
				if gui.PixelsPerStud ~= want then
					gui.PixelsPerStud = want
					Util.spend(1)
				end
			end
		end
	end

	-- (re-delivered when a gui streams back in as the same object: applyGui is idempotent)
	Util.discover({ class = "SurfaceGui", tag = "GwSurfaceGui" }, function(inst)
		if guiReg.map[inst] == nil then
			Util.regSet(guiReg, inst, {})
		end
		applyGui(inst)
	end)

	-----------------------------------------------------------------------------------------------
	-- RoomDepth models
	-----------------------------------------------------------------------------------------------
	local roomReg = Util.registry()

	local function applyRoom(model: Instance)
		if not Util.inWorld(model) then
			return
		end
		Util.setHidden(model, tierValue(cfg.HideRoomDepth, false) == true)
	end

	-- idempotent: runs again when a room streams back in (setHidden is a no-op when nothing changes)
	local function considerRoom(inst: Instance)
		if not inst:IsA("Model") or not inst:IsDescendantOf(workspace) then
			return
		end
		Util.regSet(roomReg, inst, true)
		applyRoom(inst)
	end
	Util.discover({ name = "RoomDepth", tag = "RoomDepth" }, considerRoom)

	-----------------------------------------------------------------------------------------------
	-- Tier changes: re-apply everything known (guis in batches; they can number in the thousands)
	-----------------------------------------------------------------------------------------------
	local guiSweep = Util.sweeper(function()
		return Util.budget(cfg.DiscoverPerFrame or { low = 150, mid = 300, high = 600 })
	end)
	Util.onTierChanged(function(newTier, oldTier)
		for inst in fx do
			applyFx(inst)
		end
		pcall(applyGlobals)
		for _, model in roomReg.list do
			applyRoom(model) -- (queues; setHidden does the work in budgeted slices)
		end
		guiSweep(Util.regItems(guiReg), applyGui)
		print(string.format("[GwangalliWorld/MobileQuality] quality %s -> %s (%s)", tostring(oldTier), tostring(newTier), Util.Quality.reason()))
	end)
end

return MobileQuality
