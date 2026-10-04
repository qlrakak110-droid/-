-- Night/day switching for signs and glass:
--   NightGlow (SurfaceGui / BillboardGui): LightInfluence 1 by day; 0 + GlowBrightness at night.
--   NightNeon (BasePart): Neon + warm tint at night, original material/colour by day.
--   NeonTube (BasePart): always Neon.
--   Window glass (tag "Window", or Glass parts named "Window" / "RoomGlass"):
--     * a deterministic ~40 % of "Window" panes are lit at night (Neon, warm/cool colour,
--       Transparency 0) and restored by day;
--     * on tiers where Config.Mobile.OpaqueUpperWindows is set ("low": phones), every pane above
--       Config.Mobile.UpperWindowY is made opaque (Transparency 0, colour darkened a little,
--       reflectance kept) day and night. Semi-transparent panes are drawn one by one with
--       overdraw, which phones feel most. "RoomGlass" (glass in front of fake rooms, which are
--       hidden on the same tier) then joins the random lit set so facades still glow at night.
--   Window glass is owned by this module only (lighting and opacity touch the same properties).
-- Everything is applied once per transition in chunks, nearest to the camera first, and
-- immediately for instances that stream in, so the steady-state cost is zero.
-- NightNeon / NightGlow inside a "RoomDepth" model (room lights behind upper-floor glass, well
-- over half of all NightNeon parts) are left alone while the current tier hides those rooms
-- (Config.Mobile.HideRoomDepth): they are invisible there. A tier change that shows the rooms
-- again brings them up to date.
-- Discovery: CollectionService tags where the builders set them; untagged glass is found by
-- name through the shared Util.discover listener (batched, no per-frame scans). Window records
-- live in a strong Util.registry; the background pruner drops panes that left the Workspace and
-- first gives a pane that still wears our look its server look back.
-- Streaming: an instance that streams out can come back as the SAME object, with either its
-- server look or the look this module gave it. The day look is therefore recorded once per
-- instance and never re-read from a part that may still wear its night look; the current look is
-- re-applied on every arrival. (glowSeen / neonSeen are weak caches for that: the entry of a
-- tagged instance cannot go away while `glow` / `neon` hold the instance.)

local Signage = {}

function Signage.start(ctx: any)
	local Config, Shared, Util, DayNight = ctx.Config, ctx.Shared, ctx.Util, ctx.DayNight
	local nightCfg = Config.Night
	local mobileCfg = Config.Mobile or {}
	local sweep = Util.sweeper(function()
		return Util.budget(Config.SweepPerFrame)
	end)
	local NEON = Enum.Material.Neon

	-- RoomDepth rooms hidden on this tier (MobileQuality hides them with the same Config key)
	local function roomsHiddenTier(): boolean
		local t = mobileCfg.HideRoomDepth
		return type(t) == "table" and Util.budget(t) == true
	end
	local roomsHidden = roomsHiddenTier()
	local function inRoom(inst: Instance): boolean
		return inst:FindFirstAncestor("RoomDepth") ~= nil
	end

	-----------------------------------------------------------------------------------------------
	-- NightGlow
	-----------------------------------------------------------------------------------------------
	type GlowRec = { li: number, br: number, pos: Vector3?, room: boolean }
	local glow: { [Instance]: GlowRec } = {} -- currently tagged and present
	local glowSeen: { [Instance]: GlowRec } = setmetatable({}, { __mode = "k" }) :: any -- day look per instance

	local function guiPosition(gui: any): Vector3?
		local host = gui.Adornee or gui.Parent
		if host and host:IsA("BasePart") then
			return host.Position
		end
		return nil
	end

	local function applyGlow(gui: any, rec: GlowRec, isNight: boolean)
		if isNight then
			local b = gui:GetAttribute("GlowBrightness")
			gui.LightInfluence = 0
			gui.Brightness = (if type(b) == "number" then b else rec.br) * nightCfg.GlowBrightnessScale
		else
			gui.LightInfluence = rec.li
			gui.Brightness = rec.br
		end
		Util.spend(1) -- (2 writes; the queue that called us counted 1)
	end

	Util.watchTag("NightGlow", function(inst)
		if not (inst:IsA("SurfaceGui") or inst:IsA("BillboardGui")) then
			return
		end
		local gui = inst :: any
		local rec = glowSeen[inst]
		if rec then
			rec.pos = guiPosition(gui)
			rec.room = inRoom(inst)
		else
			rec = { li = gui.LightInfluence, br = gui.Brightness, pos = guiPosition(gui), room = inRoom(inst) }
			glowSeen[inst] = rec
		end
		glow[inst] = rec
		if rec.room and roomsHidden then
			return -- hidden with its room on this tier (the tier change that shows it catches up)
		end
		local isNight = DayNight.isNight()
		if isNight or gui.LightInfluence ~= rec.li or gui.Brightness ~= rec.br then
			applyGlow(gui, rec, isNight)
		end
	end, function(inst)
		local rec = glow[inst]
		glow[inst] = nil
		-- Streamed out (the removed subtree keeps its inner Parent links, so test the ancestry,
		-- not Parent): leave the look alone, it is re-checked if the same object comes back.
		-- Still in the Workspace: the tag was removed, so restore the day look.
		if rec and inst:IsDescendantOf(workspace) then
			glowSeen[inst] = nil
			applyGlow(inst, rec, false)
		end
	end)

	-----------------------------------------------------------------------------------------------
	-- NightNeon
	-----------------------------------------------------------------------------------------------
	type PartRec = { material: Enum.Material, color: Color3, night: Color3, pos: Vector3, room: boolean }
	local neon: { [BasePart]: PartRec } = {} -- currently tagged and present
	local neonSeen: { [BasePart]: PartRec } = setmetatable({}, { __mode = "k" }) :: any -- day look per instance

	local function applyNeon(part: BasePart, rec: PartRec, isNight: boolean)
		if isNight then
			part.Material = NEON
			part.Color = rec.night
		else
			part.Material = rec.material
			part.Color = rec.color
		end
		Util.spend(1) -- (2 writes; the queue that called us counted 1)
	end

	Util.watchTag("NightNeon", function(inst)
		if not inst:IsA("BasePart") then
			return
		end
		local part = inst :: BasePart
		local rec = neonSeen[part]
		if rec then
			rec.pos = part.Position
			rec.room = inRoom(part)
		else
			local override = part:GetAttribute("NightColor")
			local nightColor = if typeof(override) == "Color3"
				then override
				else part.Color:Lerp(nightCfg.NeonTint, nightCfg.NeonTintAmount)
			rec = { material = part.Material, color = part.Color, night = nightColor, pos = part.Position, room = inRoom(part) }
			neonSeen[part] = rec
		end
		neon[part] = rec
		if rec.room and roomsHidden then
			return -- hidden with its room on this tier (the tier change that shows it catches up)
		end
		local isNight = DayNight.isNight()
		if isNight or part.Material ~= rec.material or part.Color ~= rec.color then
			applyNeon(part, rec, isNight)
		end
	end, function(inst)
		local rec = neon[inst :: BasePart]
		neon[inst :: BasePart] = nil
		if rec and inst:IsDescendantOf(workspace) then -- tag removed, instance kept: restore
			neonSeen[inst :: BasePart] = nil
			applyNeon(inst :: BasePart, rec, false)
		end
	end)

	-----------------------------------------------------------------------------------------------
	-- NeonTube (always on)
	-----------------------------------------------------------------------------------------------
	Util.watchTag("NeonTube", function(inst)
		if inst:IsA("BasePart") and inst.Material ~= NEON then
			inst.Material = NEON
		end
	end)

	-----------------------------------------------------------------------------------------------
	-- Window glass
	-----------------------------------------------------------------------------------------------
	type WindowRec = {
		material: Enum.Material,
		color: Color3,
		transparency: number,
		reflectance: number,
		pos: Vector3,
		upper: boolean, -- above UpperWindowY and see-through (candidate for opaque glass)
		roomGlass: boolean,
		lucky: boolean, -- inside the deterministic lit share
		lit: Color3,
		applied: string, -- "orig" | "opaque" | "lit" | "?" (unknown: everything is rewritten)
	}
	-- part -> record, or false for panes seen but never touched (kept so a tier change can reach
	-- them). A pane that left the Workspace is dropped by the registry's pruner; if it still wears
	-- our look it gets its server look back first (a write on a part outside the Workspace draws
	-- nothing), so a pane that streams back in as the same object is recorded afresh, correctly.
	local windowReg = Util.registry(function(inst: Instance, rec: WindowRec | false)
		if rec and rec.applied ~= "orig" then
			local part = inst :: BasePart
			part.Material = rec.material
			part.Color = rec.color
			part.Transparency = rec.transparency
			part.Reflectance = rec.reflectance
			Util.spend(4)
		end
	end)
	local windows: { [BasePart]: WindowRec | false } = windowReg.map :: any
	local GLASS = Enum.Material.Glass
	local litFraction = nightCfg.WindowLitFraction
	local palette = nightCfg.WindowColors
	local upperY = tonumber(mobileCfg.UpperWindowY) or 20
	-- darkening for a pane of Transparency 0.2 (scaled with the pane's transparency: the dark room
	-- behind see-through glass made it look darker than its colour)
	local darken = math.clamp(tonumber(mobileCfg.OpaqueWindowDarken) or 0.12, 0, 0.8)
	local minReflect = math.clamp(tonumber(mobileCfg.OpaqueWindowMinReflectance) or 0.18, 0, 1)
	local BLACK = Color3.new(0, 0, 0)
	local totalWeight = 0
	for _, entry in palette do
		totalWeight += entry.weight
	end

	local function opaqueTier(): boolean
		local t = mobileCfg.OpaqueUpperWindows
		return type(t) == "table" and Util.budget(t) == true
	end
	local opaqueNow = opaqueTier()

	local function pickColor(h: number): Color3
		local x = h * totalWeight
		for _, entry in palette do
			x -= entry.weight
			if x <= 0 then
				return entry.color
			end
		end
		return palette[#palette].color
	end

	-- RoomGlass joins the lit set only while its rooms are hidden behind opaque glass.
	local function litEligible(rec: WindowRec): boolean
		return rec.lucky and (not rec.roomGlass or opaqueNow)
	end

	local function wantedLook(rec: WindowRec, isNight: boolean): string
		if isNight and litEligible(rec) then
			return "lit"
		elseif opaqueNow and rec.upper then
			return "opaque"
		end
		return "orig"
	end

	local function applyWindow(part: BasePart, rec: WindowRec, isNight: boolean)
		local look = wantedLook(rec, isNight)
		local was = rec.applied
		if look == was then
			return
		end
		rec.applied = look
		if look == "lit" then
			part.Material = NEON
			part.Color = rec.lit
			part.Transparency = 0
			part.Reflectance = 0
			Util.spend(3) -- (4 writes; the queue that called us counted 1)
			return
		end
		if was ~= "orig" and was ~= "opaque" then
			part.Material = rec.material -- from "lit" / unknown ("orig" <-> "opaque" keeps the material)
			Util.spend(1)
		end
		Util.spend(2)
		if look == "opaque" then
			part.Color = rec.color:Lerp(BLACK, math.clamp(darken * rec.transparency / 0.2, 0, 0.35))
			part.Transparency = 0
			part.Reflectance = math.max(rec.reflectance, minReflect)
		else
			part.Color = rec.color
			part.Transparency = rec.transparency
			part.Reflectance = rec.reflectance
		end
	end

	-- Would this pane need a record under the current tier (lit share or opaque upper floor)?
	local function needsRecord(part: BasePart, roomGlass: boolean): boolean
		local p = part.Position
		if opaqueNow and p.Y > upperY and part.Transparency > 0.02 then
			return true
		end
		if roomGlass and not opaqueNow then
			return false
		end
		return Shared.hash01(p.X, p.Y, p.Z) < litFraction
	end

	local function makeRecord(part: BasePart, roomGlass: boolean): WindowRec
		local p = part.Position
		return {
			material = part.Material,
			color = part.Color,
			transparency = part.Transparency,
			reflectance = part.Reflectance,
			pos = p,
			upper = p.Y > upperY and part.Transparency > 0.02,
			roomGlass = roomGlass,
			lucky = Shared.hash01(p.X, p.Y, p.Z) < litFraction,
			lit = pickColor(Shared.hash01(p.Z, p.X, p.Y, 17)),
			applied = "orig",
		}
	end

	-- A pane seen before arrives again (streamed back in as the same object, or reported by both
	-- the tag and the name listener): if its look no longer matches what was applied (the engine
	-- restored the server look), apply it again.
	local function recheckWindow(part: BasePart, rec: WindowRec)
		local wantT = if rec.applied == "orig" then rec.transparency else 0
		local wantM = if rec.applied == "lit" then NEON else rec.material
		if math.abs(part.Transparency - wantT) > 1e-3 or part.Material ~= wantM then
			rec.applied = "?"
		end
		applyWindow(part, rec, DayNight.isNight())
	end

	local function considerWindow(inst: Instance)
		if not inst:IsA("BasePart") or inst:HasTag("NightWindow") then
			return -- (NightWindow panes belong to GwangalliWorld/NightWindows, docs/buildings_contract.md)
		end
		local seen = windows[inst :: BasePart]
		if seen ~= nil then
			if seen and Util.inWorld(inst) then
				recheckWindow(inst :: BasePart, seen)
			end
			return
		end
		local part = inst :: BasePart
		if part.Material ~= GLASS or not part:IsDescendantOf(workspace) then
			return
		end
		local roomGlass = part.Name == "RoomGlass"
		if not needsRecord(part, roomGlass) then
			Util.regSet(windowReg, part, false) -- seen, untouched
			return
		end
		local rec = makeRecord(part, roomGlass)
		Util.regSet(windowReg, part, rec)
		applyWindow(part, rec, DayNight.isNight())
	end

	-- (tags "Window" / "RoomGlass": set by the build or GwangalliEnvironment.server, see Util.discover)
	Util.discover({ name = "Window", tag = "Window" }, considerWindow)
	Util.discover({ name = "RoomGlass", tag = "RoomGlass" }, considerWindow)

	-----------------------------------------------------------------------------------------------
	-- Transitions (night <-> day, quality tier)
	-----------------------------------------------------------------------------------------------
	local function posOf(inst: any): Vector3?
		local g = glow[inst]
		if g then
			return g.pos
		end
		local n = neon[inst]
		if n then
			return n.pos
		end
		local w = windows[inst]
		if w then
			return w.pos
		end
		return nil
	end

	local function applyAny(inst: any)
		if not Util.inWorld(inst) then
			return
		end
		local isNight = DayNight.isNight()
		local g = glow[inst]
		if g then
			applyGlow(inst, g, isNight)
			return
		end
		local n = neon[inst]
		if n then
			applyNeon(inst, n, isNight)
			return
		end
		local w = windows[inst]
		if w then
			applyWindow(inst, w, isNight)
		end
	end

	local function onNightChanged()
		local items = {}
		for gui, rec in glow do
			if not (rec.room and roomsHidden) then
				table.insert(items, gui)
			end
		end
		for part, rec in neon do
			if not (rec.room and roomsHidden) then
				table.insert(items, part)
			end
		end
		for _, part in windowReg.list do
			local rec = windows[part :: BasePart]
			if rec and litEligible(rec) then
				table.insert(items, part)
			end
		end
		sweep(Util.nearestFirst(items, Util.cameraPosition(), posOf), applyAny)
	end
	DayNight.onChanged(onNightChanged)

	-- Tier change: opacity and the RoomGlass lit share may change for every known pane, and room
	-- lights skipped while their rooms were hidden need the current look once the rooms show.
	local tierSweep = Util.sweeper(function()
		return Util.budget(Config.SweepPerFrame)
	end)
	Util.onTierChanged(function()
		local items = {}
		local nowRooms = roomsHiddenTier()
		if nowRooms ~= roomsHidden then
			roomsHidden = nowRooms
			if not nowRooms then
				for gui, rec in glow do
					if rec.room then
						table.insert(items, gui)
					end
				end
				for part, rec in neon do
					if rec.room then
						table.insert(items, part)
					end
				end
			end
		end
		local nowOpaque = opaqueTier()
		if nowOpaque ~= opaqueNow then
			opaqueNow = nowOpaque
			for _, inst in Util.regItems(windowReg) do
				local part = inst :: BasePart
				local rec = windows[part]
				if rec then
					table.insert(items, part)
				elseif rec == false and Util.inWorld(part) and needsRecord(part, part.Name == "RoomGlass") then
					Util.regSet(windowReg, part, makeRecord(part, part.Name == "RoomGlass"))
					table.insert(items, part)
				end
			end
		end
		if #items > 0 then
			tierSweep(Util.nearestFirst(items, Util.cameraPosition(), posOf), applyAny)
		end
	end)
end

return Signage
