-- GwangalliWorld/NightWindows (client): the NIGHT WINDOW CONTRACT (docs/buildings_contract.md).
--
-- Window glass tagged "NightWindow" (attributes LitChance, LitColor, Zone, optional LitSeed and
-- RoomBacked; the kit's A.nightWindow sets them) glows at night: a deterministic share of the panes
-- (seed < LitChance * LitScale[tier]) is switched on one by one after dusk, each at its own clock time
-- from its seed and zone schedule, and most switch off again late at night (homes 22:30-02:30, offices
-- 19:00-23:30, shops 21:30-02:00, hotels 23:00-03:00; corridors stay lit). Lit look = Material Neon,
-- Color = LitColor, Transparency 0, Reflectance 0 (a material swap: no Light instances). The day look
-- is recorded once per instance and restored at dawn.
--
-- Cost control:
--   * discovery through CollectionService signals only (Util.watchTag: streaming-safe, batched);
--   * a schedule pass every PassSeconds walks the known panes nearest-first (distance rings, no
--     sort) and writes only panes whose look changes, within the shared per-frame write budget
--     (Util.canDo / Util.spend) and EvalPerFrame records per frame. Only panes the schedule can
--     change are walked (the "lucky" ones plus any pane not wearing its rest look: about a third
--     of them); the others got their look on arrival. A tier change runs one pass over all panes;
--     the order is rebuilt when panes arrived or the camera moved more than 120 studs;
--   * MaxLit[tier] caps simultaneously lit panes; the nearest win (each pass hands the quota out
--     nearest-first, so the cap follows the camera);
--   * phones (Config.Mobile.OpaqueUpperWindows tiers) get opaque upper panes by day, like the older
--     Signage glass, so tagged panes never add transparent overdraw there.
-- RoomBacked panes (in front of the kit's fake rooms, which light themselves) are lit only on tiers
-- that hide RoomDepth (Config.Mobile.HideRoomDepth).
-- Streaming: a pane that streams out keeps its record until the shared registry pruner drops it
-- (restoring the server look first); one that streams back in as the same object is re-checked and
-- re-applied.
-- Panes tagged NightWindow are owned by this module; Signage's window code skips them.
-- Overrides: Config.NightWindows (same keys as DEFAULTS below).

local NightWindows = {}

local DEFAULTS = {
	LitScale = { low = 0.8, mid = 0.95, high = 1, saver = 0.65 },
	MaxLit = { low = 2500, mid = 5000, high = 10000, saver = 1200 },
	-- the schedule moves in clock minutes: no hurry (8 s = 8 in-game minutes at the 24-minute day)
	PassSeconds = { low = 8, mid = 5, high = 3, saver = 12 },
	EvalPerFrame = { low = 300, mid = 600, high = 1200, saver = 200 },
	-- clock hours; on = on0 + onSpan * a, off = off0 + offSpan * b (> 24 = after midnight);
	-- b > allNight keeps the pane lit until dawn (allNight >= 1: never, <= 0: always)
	Schedule = {
		home = { on0 = 17.6, onSpan = 3.0, off0 = 22.5, offSpan = 4.0, allNight = 0.88 },
		office = { on0 = 17.2, onSpan = 1.3, off0 = 19.0, offSpan = 4.5, allNight = 0.9 },
		shop = { on0 = 17.0, onSpan = 1.5, off0 = 21.5, offSpan = 4.5, allNight = 2 },
		hotel = { on0 = 18.0, onSpan = 3.0, off0 = 23.0, offSpan = 4.0, allNight = 0.85 },
		corridor = { on0 = 17.4, onSpan = 1.2, off0 = 30, offSpan = 0, allNight = 0 },
	},
	DefaultChance = 0.45,
	DefaultColor = Color3.fromRGB(214, 150, 86),
}

local function frac(x: number): number
	return x - math.floor(x)
end

-- contract §1.3 (only when LitSeed is missing)
local function hash01(p: Vector3): number
	local x, y, z = math.round(p.X), math.round(p.Y), math.round(p.Z)
	return frac(math.sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453)
end

function NightWindows.start(ctx: any)
	local Config, Util, DayNight = ctx.Config, ctx.Util, ctx.DayNight
	local user = type(Config.NightWindows) == "table" and Config.NightWindows or {}
	local cfg = table.clone(DEFAULTS)
	for k, v in user do
		cfg[k] = v
	end
	local schedule = table.clone(DEFAULTS.Schedule)
	if type(user.Schedule) == "table" then
		for k, v in user.Schedule do
			schedule[k] = v
		end
	end
	local mobileCfg = Config.Mobile or {}
	local NEON = Enum.Material.Neon
	local BLACK = Color3.new(0, 0, 0)
	local upperY = tonumber(mobileCfg.UpperWindowY) or 20
	local darken = math.clamp(tonumber(mobileCfg.OpaqueWindowDarken) or 0.12, 0, 0.8)
	local minReflect = math.clamp(tonumber(mobileCfg.OpaqueWindowMinReflectance) or 0.18, 0, 1)

	local function tierValue(v: any, fallback: number): number
		local x = if type(v) == "table" then Util.budget(v) else v
		return tonumber(x) or fallback
	end
	local function flagTier(key: string): boolean
		local t = mobileCfg[key]
		return type(t) == "table" and Util.budget(t) == true
	end

	local scale = tierValue(cfg.LitScale, 1)
	local maxLit = math.max(0, math.floor(tierValue(cfg.MaxLit, 5000)))
	local opaqueNow = flagTier("OpaqueUpperWindows")
	local roomsHidden = flagTier("HideRoomDepth")

	type Rec = {
		material: Enum.Material,
		color: Color3,
		transparency: number,
		reflectance: number,
		pos: Vector3,
		seed: number,
		chance: number,
		lit: Color3,
		on: number,
		off: number,
		rooms: boolean,
		upper: boolean,
		applied: string, -- "orig" | "opaque" | "lit" | "?" (unknown: everything is rewritten)
	}

	local litCount = 0
	local regVersion = 0 -- bumped when a pane is first registered (the pass order is rebuilt)

	-- strong registry; the pruner gives a pane that left the Workspace its server look back first
	local reg = Util.registry(function(inst: Instance, rec: Rec)
		if rec and rec.applied ~= "orig" then
			if rec.applied == "lit" then
				litCount -= 1
			end
			local part = inst :: BasePart
			part.Material = rec.material
			part.Color = rec.color
			part.Transparency = rec.transparency
			part.Reflectance = rec.reflectance
			Util.spend(4)
		end
	end)
	local recs: { [BasePart]: Rec } = reg.map :: any

	-- clock normalised to the night: after midnight counts as 24 + h
	local function nightClock(): number
		local ok, c = pcall(DayNight.clock)
		local t = if ok and type(c) == "number" then c else 21
		if t < 12 then
			t += 24
		end
		return t
	end

	local function makeRecord(part: BasePart): Rec
		local p = part.Position
		local seedAttr = part:GetAttribute("LitSeed")
		local seed = if type(seedAttr) == "number" then math.clamp(seedAttr, 0, 1) else hash01(p)
		local chanceAttr = part:GetAttribute("LitChance")
		local chance = if type(chanceAttr) == "number" then math.clamp(chanceAttr, 0, 1) else cfg.DefaultChance
		local colorAttr = part:GetAttribute("LitColor")
		local zoneAttr = part:GetAttribute("Zone")
		local zone = if type(zoneAttr) == "string" and schedule[zoneAttr] then zoneAttr else "home"
		local s = schedule[zone]
		local a, b = frac(seed * 9973.13), frac(seed * 7919.71)
		local off = s.off0 + s.offSpan * b
		if b > s.allNight then
			off = math.huge
		end
		return {
			material = part.Material,
			color = part.Color,
			transparency = part.Transparency,
			reflectance = part.Reflectance,
			pos = p,
			seed = seed,
			chance = chance,
			lit = if typeof(colorAttr) == "Color3" then colorAttr else cfg.DefaultColor,
			on = s.on0 + s.onSpan * a,
			off = off,
			rooms = part:GetAttribute("RoomBacked") == true,
			upper = p.Y > upperY and part.Transparency > 0.02,
			applied = "orig",
		}
	end

	local function lucky(rec: Rec): boolean
		return rec.seed < rec.chance * scale and (not rec.rooms or roomsHidden)
	end

	local function scheduledOn(rec: Rec, isNight: boolean, t: number): boolean
		return isNight and lucky(rec) and t >= rec.on and t < rec.off
	end

	local function restLook(rec: Rec): string
		return if opaqueNow and rec.upper then "opaque" else "orig"
	end

	-- Writes the look; returns the number of property writes.
	local function apply(part: BasePart, rec: Rec, look: string): number
		local was = rec.applied
		if look == was then
			return 0
		end
		if was == "lit" then
			litCount -= 1
		elseif look == "lit" then
			litCount += 1
		end
		rec.applied = look
		if look == "lit" then
			part.Material = NEON
			part.Color = rec.lit
			part.Transparency = 0
			part.Reflectance = 0
			return 4
		end
		local n = 3
		if was ~= "orig" and was ~= "opaque" then
			part.Material = rec.material -- from "lit" / unknown
			n += 1
		end
		if look == "opaque" then
			part.Color = rec.color:Lerp(BLACK, math.clamp(darken * rec.transparency / 0.2, 0, 0.35))
			part.Transparency = 0
			part.Reflectance = math.max(rec.reflectance, minReflect)
		else
			part.Color = rec.color
			part.Transparency = rec.transparency
			part.Reflectance = rec.reflectance
		end
		return n
	end

	-- The engine may hand back a streamed-in pane with its server look while we think it is lit.
	local function recheck(part: BasePart, rec: Rec)
		local wantT = if rec.applied == "orig" then rec.transparency else 0
		local wantM = if rec.applied == "lit" then NEON else rec.material
		if math.abs(part.Transparency - wantT) > 1e-3 or part.Material ~= wantM then
			if rec.applied == "lit" then
				litCount -= 1
			end
			rec.applied = "?"
		end
	end

	local function arrivalLook(rec: Rec): string
		if scheduledOn(rec, DayNight.isNight(), nightClock()) and litCount < maxLit then
			return "lit"
		end
		return restLook(rec)
	end

	Util.watchTag("NightWindow", function(inst)
		if not inst:IsA("BasePart") then
			return
		end
		local part = inst :: BasePart
		local rec = recs[part]
		if rec then
			rec.pos = part.Position
			recheck(part, rec)
		else
			rec = makeRecord(part)
			Util.regSet(reg, part, rec)
			regVersion += 1
		end
		Util.spend(apply(part, rec, arrivalLook(rec)) - 1)
	end, function(inst)
		local part = inst :: BasePart
		local rec = recs[part]
		if rec and inst:IsDescendantOf(workspace) then
			-- tag removed while the pane stays: give the server look back and forget it
			Util.regRemove(reg, part)
			Util.spend(apply(part, rec, "orig"))
		end
	end)

	---------------------------------------------------------------------------------------------
	-- Schedule passes
	---------------------------------------------------------------------------------------------
	local passGen = 0
	local function posOf(part: BasePart): Vector3?
		local rec = recs[part]
		return rec and rec.pos
	end

	-- by day nothing is scheduled: once a full day pass wrote nothing, passes idle until dusk / a tier
	-- change (arrivals get their look in the watchTag callback, so they need no pass)
	local dayClean = false

	-- nearest-first order, rebuilt only when panes arrived, the camera moved or it got old (panes
	-- that left are skipped by the pass; the pruner drops them). Normal passes walk only the panes
	-- a pass can change: lucky ones (the schedule / quota may light or unlight them) and any pane
	-- that does not wear its rest look. A pane that is not lucky never changes between tier
	-- changes (arrivals apply its look in the watchTag callback), so after a tier change one full
	-- pass (wantFull) brings every pane up to date and the filter applies again.
	local order: { Instance } = {}
	local orderCam: Vector3? = nil
	local orderVersion, orderAge = -1, 0
	local wantFull, orderFull = true, false
	local function passOrder(): { Instance }
		local cam = Util.cameraPosition()
		orderAge += 1
		if orderFull ~= wantFull or orderVersion ~= regVersion or orderAge > 30 or not cam or not orderCam or (cam - orderCam).Magnitude > 120 then
			local items = Util.regItems(reg)
			if not wantFull then
				local n = 0
				for _, inst in items do
					local rec = recs[inst :: BasePart]
					if rec and (lucky(rec) or rec.applied ~= restLook(rec)) then
						n += 1
						items[n] = inst
					end
				end
				for i = #items, n + 1, -1 do
					items[i] = nil
				end
			end
			order = Util.nearestFirst(items, cam, posOf)
			orderCam, orderVersion, orderAge, orderFull = cam, regVersion, 0, wantFull
		end
		return order
	end

	local function runPass(gen: number)
		if dayClean and not DayNight.isNight() then
			return
		end
		local items = passOrder()
		local full = orderFull
		local isNight = DayNight.isNight()
		local wroteAny = false
		local t = nightClock()
		local quota = maxLit
		local evalCap = math.max(50, math.floor(tierValue(cfg.EvalPerFrame, 800)))
		local examined, writes = 0, 0
		task.wait() -- work in the Heartbeat step (shared budget refill)
		for _, inst in items do
			if gen ~= passGen then
				return
			end
			local part = inst :: BasePart
			local rec = recs[part]
			if rec then
				local look
				if quota > 0 and scheduledOn(rec, isNight, t) then
					look = "lit"
					quota -= 1
				else
					look = restLook(rec)
				end
				if look ~= rec.applied and part:IsDescendantOf(workspace) then
					if not Util.canDo(writes, evalCap) then
						task.wait()
						if gen ~= passGen then
							return
						end
						writes, examined = 0, 0
						t = nightClock()
						isNight = DayNight.isNight()
					end
					Util.spend(apply(part, rec, look))
					writes += 1
					wroteAny = true
				end
			end
			examined += 1
			if examined >= evalCap then
				task.wait()
				examined, writes = 0, 0
			end
		end
		if gen == passGen then
			dayClean = not isNight and not wroteAny and not DayNight.isNight()
			if full then
				wantFull = false -- every pane is up to date: later passes walk the changeable ones
			end
		end
	end

	local running = false
	local kick = false
	local function passLoop()
		dayClean = false
		if running then
			kick = true
			passGen += 1 -- the running pass stops at its next check and a fresh one starts
			return
		end
		running = true
		task.spawn(function()
			while true do
				kick = false
				passGen += 1
				local ok, err = pcall(runPass, passGen)
				if not ok then
					Util.warn("NightWindows", err)
				end
				local waited = 0
				local period = tierValue(cfg.PassSeconds, 1.5)
				while waited < period and not kick do
					waited += task.wait(0.25)
				end
			end
		end)
	end

	DayNight.onChanged(function()
		passLoop() -- dusk / dawn: re-evaluate right away (nearest first)
	end)

	Util.onTierChanged(function()
		scale = tierValue(cfg.LitScale, 1)
		maxLit = math.max(0, math.floor(tierValue(cfg.MaxLit, 5000)))
		opaqueNow = flagTier("OpaqueUpperWindows")
		roomsHidden = flagTier("HideRoomDepth")
		wantFull = true -- rest looks and luck changed: one pass over every pane
		passLoop()
	end)

	passLoop()
end

return NightWindows
