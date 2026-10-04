-- GwangalliEnvironment (server)
--  1. Terrain. Fills the generated terrain (ServerStorage.GwangalliTerrainOps) while players are
--     already in the game, unless it was baked in edit mode (workspace attribute
--     GwangalliTerrainBaked).
--     * Players spawn at once. Config.Terrain.HoldSpawnUntilReady is ignored on purpose: it held
--       every joining player for 10-45 s.
--     * GwangalliTerrainBaker.RunProgressive fills nearest-first around the spawn and every
--       player's character, within a per-frame budget. The spawn plaza is made of parts, and the
--       beach around it is complete in the first frames.
--     * The EditorOnly water previews disappear area by area as the real water arrives.
--     * workspace.GwangalliTerrainProgress (0..1) reports progress. workspace.GwangalliTerrainReady
--       is set when the fill is complete.
--  2. Clock. The authoritative day/night clock is published as attributes only (no Lighting
--     writes after start):
--       GwangalliClockAnchorTime / GwangalliClockAnchorClock / GwangalliClockRate: set only when
--         the clock is (re)anchored. Clients extrapolate:
--         clock = anchorClock + (workspace:GetServerTimeNow() - anchorTime) * rate
--       GwangalliClock: the clock (hours, 3 decimals) about once a second, for tools and simple
--         readers
--       GwangalliPhase, GwangalliIsNight: set when they change, at the boundary itself
--     GwangalliWorld/DayNight on each client sets Lighting.ClockTime and the look (Atmosphere,
--     colour grade, bloom, sun rays, clouds) locally. The server used to replicate ~46 Lighting
--     property writes/s to every phone (ClockTime at 10 Hz plus 18 look properties at 2 Hz); now
--     it sends about one attribute per second, and the sun moves smoothly.
--  3. Drone show schedule. Publishes the start time of the 광안리 M 드론라이트쇼
--     (GwangalliDroneShowStart / GwangalliDroneShowDuration).
--  4. Client discovery tags (mobile perf): tags SurfaceGuis / near-LOD models / window glass once
--     at start and sets workspace.GwDiscoverTagged, so clients need no Workspace-wide listener.
--  5. Near-only detail arrives hidden (mobile perf): eligible near models are set to Transparency 1
--     at start (attribute GwArrive), so they stream in hidden and each client only shows the few
--     within its DetailLOD radius (details in section 5 below).
--
-- Studio helpers (set on Workspace while playing, server side):
--   GwangalliSetClock (number)       jump the clock, e.g. 19.9
--   GwangalliDayLengthMinutes (num)  real minutes per in-game day (overrides the config)
--   GwangalliClockPaused (bool)      freeze / resume the clock
--   GwangalliStartDroneShow (bool)   start a drone show now

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local configModule = ReplicatedStorage:WaitForChild("GwangalliConfig", 30)
local sharedModule = ReplicatedStorage:WaitForChild("GwangalliShared", 30)
if not configModule or not sharedModule then
	warn("[GwangalliEnvironment] GwangalliConfig / GwangalliShared missing from ReplicatedStorage")
	return
end
local Config = require(configModule)
local Shared = require(sharedModule)
local A = Shared.Attr

local CLOCK_ATTR = "GwangalliClock" -- coarse clock (hours), ~1 Hz
local PROGRESS_ATTR = "GwangalliTerrainProgress"
local EDITOR_ONLY = "EditorOnly"

---------------------------------------------------------------------------------------------------
-- 1. Terrain
---------------------------------------------------------------------------------------------------

local terrainCfg = Config.Terrain or {}
local FRAME_BUDGET = tonumber(terrainCfg.FrameBudget) or 0.008
local BACKGROUND_BUDGET = FRAME_BUDGET * 0.5 -- once the areas around the players are filled
local NEAR_RADIUS = 512 -- studs around the spawn / characters filled at the full budget
local FALLBACK_FOCUS = Vector3.new(0, 0, 0) -- beach centre, used when no SpawnLocation is found
-- Focus points cost a pass over every terrain piece each when priorities are recomputed (~2 ms
-- per point in a plain Luau VM). Characters therefore count once per FOCUS_CELL x FOCUS_CELL
-- cell (players cluster at the spawn), and at most MAX_CHARACTER_FOCUS cells are used.
local FOCUS_CELL = 256
local MAX_CHARACTER_FOCUS = 8

local function markTerrainReady()
	workspace:SetAttribute(PROGRESS_ATTR, 1)
	workspace:SetAttribute(A.TerrainReady, true)
end

local lastProgress = -1
local function publishProgress(fraction: number)
	local rounded = math.floor(math.clamp(fraction, 0, 1) * 100 + 0.5) / 100
	if rounded ~= lastProgress then
		lastProgress = rounded
		workspace:SetAttribute(PROGRESS_ATTR, rounded)
	end
end

-- The SpawnLocation (coast owns exactly one), found without walking the whole map.
local function spawnPoints(): { Vector3 }
	local out = {}
	local root = workspace:FindFirstChild("Gwangalli")
	local coast = root and root:FindFirstChild("coast")
	local spawnLocation = coast and coast:FindFirstChildWhichIsA("SpawnLocation")
	if not spawnLocation then
		spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	end
	if spawnLocation and spawnLocation:IsA("BasePart") then
		table.insert(out, spawnLocation.Position)
	else
		table.insert(out, FALLBACK_FOCUS)
	end
	return out
end

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local primary = character.PrimaryPart
	return primary and primary.Position or nil
end

-- World AABB of a part (rotation-aware).
local function partBounds(part: BasePart): (Vector3, Vector3)
	local cf, s = part.CFrame, part.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local half = Vector3.new(
		0.5 * (math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z),
		0.5 * (math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z),
		0.5 * (math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z)
	)
	return cf.Position - half, cf.Position + half
end

local function prepareTerrain()
	local bakerModule = ServerStorage:FindFirstChild("GwangalliTerrainBaker")
	local Baker = nil
	if bakerModule and bakerModule:IsA("ModuleScript") then
		local ok, result = pcall(require, bakerModule)
		if ok then
			Baker = result
		else
			warn("[GwangalliEnvironment] GwangalliTerrainBaker failed to load: " .. tostring(result))
		end
	end

	local function destroyEditorOnly()
		if Baker then
			local ok, n = pcall(Baker.DestroyEditorOnly)
			if ok and type(n) == "number" and n > 0 then
				print(string.format("[GwangalliEnvironment] removed %d EditorOnly instances", n))
			end
		end
	end

	if workspace:GetAttribute(A.TerrainBaked) == true then
		destroyEditorOnly()
		markTerrainReady()
		return
	end

	-- Interim preview builds ship their own filler script; do not fill twice (and never hold
	-- spawns for it either).
	local external = ServerScriptService:FindFirstChild("InterimEnvironment") or ServerScriptService:FindFirstChild("InterimTerrain")
	if external and external:IsA("Script") then
		local deadline = os.clock() + (tonumber(terrainCfg.HoldSpawnTimeout) or 90)
		while workspace:GetAttribute(A.TerrainReady) ~= true and os.clock() < deadline do
			task.wait(0.5)
		end
		if workspace:GetAttribute(A.TerrainReady) == true then
			destroyEditorOnly()
		end
		markTerrainReady()
		return
	end

	if not Baker then
		markTerrainReady()
		return
	end
	local ops = Baker.LoadOps()
	if not ops then
		-- Missing or rejected ops: keep the EditorOnly previews (they are the only sea left).
		markTerrainReady()
		return
	end
	if #ops == 0 then
		destroyEditorOnly()
		markTerrainReady()
		return
	end

	workspace:SetAttribute(PROGRESS_ATTR, 0)
	-- Requiring + validating the ops used this frame; planning starts on a fresh one.
	task.wait()
	local t0 = os.clock()
	local spawns = spawnPoints()

	-- Focus: the spawn (every new character appears there) plus the characters, so a player who
	-- quick-travels during the fill gets the terrain around them next. One point per occupied
	-- cell, the spawn's cells included, in player order (stable between polls).
	local function focusCell(p: Vector3): number
		return math.floor(p.X / FOCUS_CELL) * 65536 + math.floor(p.Z / FOCUS_CELL)
	end
	local spawnCells: { [number]: boolean } = {}
	for _, p in spawns do
		spawnCells[focusCell(p)] = true
	end
	local function getFocus(): { Vector3 }
		local points = table.clone(spawns)
		local used = table.clone(spawnCells)
		local extra = 0
		for _, player in Players:GetPlayers() do
			if extra >= MAX_CHARACTER_FOCUS then
				break
			end
			local pos = characterPosition(player)
			if pos and pos == pos then
				local key = focusCell(pos)
				if not used[key] then
					used[key] = true
					extra += 1
					table.insert(points, pos)
				end
			end
		end
		return points
	end

	-- EditorOnly water previews: each goes as soon as the terrain under it is complete.
	local removedPreviews = 0
	local covers = {}
	for _, inst in CollectionService:GetTagged(EDITOR_ONLY) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			local lo, hi = partBounds(inst)
			table.insert(covers, {
				min = lo,
				max = hi,
				onClear = function()
					if inst.Parent then
						pcall(inst.Destroy, inst)
						removedPreviews += 1
					end
				end,
			})
		end
	end

	local applied, failed = 0, 0
	local ok, err = pcall(function()
		applied, failed = Baker.RunProgressive(ops, {
			frameBudget = FRAME_BUDGET,
			backgroundBudget = BACKGROUND_BUDGET,
			nearRadius = NEAR_RADIUS,
			getFocus = getFocus,
			isBusy = function()
				return #Players:GetPlayers() > 0
			end,
			covers = covers,
			onPlanned = function(plan)
				print(string.format("[GwangalliEnvironment] terrain: %d ops -> %d pieces planned in %.2fs", #ops, plan.count, os.clock() - t0))
			end,
			onNearDone = function()
				print(string.format("[GwangalliEnvironment] terrain within %d studs of the spawn and players ready after %.2fs", NEAR_RADIUS, os.clock() - t0))
			end,
			onProgress = publishProgress,
		})
	end)
	if not ok then
		-- Planner / scheduler failure: fall back to the plain in-order fill (same final terrain).
		warn("[GwangalliEnvironment] progressive terrain fill failed, filling in order: " .. tostring(err))
		local ok2, err2 = pcall(function()
			applied, failed = Baker.RunOps(ops, {
				yield = true,
				frameBudget = BACKGROUND_BUDGET,
				onProgress = function(done: number, total: number)
					publishProgress(done / math.max(1, total))
				end,
			})
		end)
		if not ok2 then
			warn("[GwangalliEnvironment] terrain fill error: " .. tostring(err2))
		end
	end
	print(string.format(
		"[GwangalliEnvironment] terrain: %d ops (%d failed) in %.1fs, %d water previews replaced on the way",
		applied,
		failed,
		os.clock() - t0,
		removedPreviews
	))
	if applied > 0 and applied >= #ops * (tonumber(terrainCfg.MinSuccessRatio) or 0.9) then
		destroyEditorOnly()
	else
		warn(string.format("[GwangalliEnvironment] only %d of %d terrain ops applied; keeping EditorOnly previews", applied, #ops))
	end
	markTerrainReady()
end

task.spawn(function()
	-- Whatever fails in here, the terrain must end up "ready": the HUD shows "지형 생성 중" until
	-- then and hides the drone show badge.
	local ok, err = pcall(prepareTerrain)
	if not ok then
		warn("[GwangalliEnvironment] terrain preparation failed: " .. tostring(err))
		markTerrainReady()
	end
end)

---------------------------------------------------------------------------------------------------
-- 2. Clock
---------------------------------------------------------------------------------------------------

local function dayRate(): number
	-- Workspace attribute GwangalliDayLengthMinutes (Studio) overrides Config.DayLengthMinutes.
	local minutes = workspace:GetAttribute("GwangalliDayLengthMinutes")
	if type(minutes) ~= "number" or minutes ~= minutes or minutes <= 0 then
		minutes = tonumber(Config.DayLengthMinutes) or 24
	end
	return 24 / (math.max(0.1, minutes :: number) * 60) -- in-game hours per real second
end
local rate = dayRate()
local paused = false
local anchorTime = workspace:GetServerTimeNow()
local anchorClock = (tonumber(Config.StartClockTime) or 17) % 24

local function publishAnchor()
	workspace:SetAttribute(A.ClockAnchorTime, anchorTime)
	workspace:SetAttribute(A.ClockAnchorClock, anchorClock)
	workspace:SetAttribute(A.ClockRate, paused and 0 or rate)
end

local function clockAt(now: number): number
	if paused then
		return anchorClock
	end
	return (anchorClock + (now - anchorTime) * rate) % 24
end

local lastClockPublish = -math.huge
local function publishClock(clock: number)
	lastClockPublish = os.clock()
	workspace:SetAttribute(CLOCK_ATTR, math.floor(clock * 1000 + 0.5) / 1000)
end

publishAnchor()
-- One write before any client joins, so the initial Lighting snapshot matches the start clock.
-- After this the server never touches Lighting (clients own it; a later server write would
-- overwrite their local value).
pcall(function()
	Lighting.ClockTime = anchorClock
end)

---------------------------------------------------------------------------------------------------
-- 3. Drone show schedule
---------------------------------------------------------------------------------------------------

local showCfg = Config.DroneShow
local showStartedAt = -math.huge

local function startDroneShow(reason: string)
	if not showCfg.Enabled then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now - showStartedAt < showCfg.Duration then
		return -- a show is still running
	end
	showStartedAt = now
	workspace:SetAttribute(A.DroneShowDuration, showCfg.Duration)
	workspace:SetAttribute(A.DroneShowStart, now)
	print("[GwangalliEnvironment] 광안리 M 드론라이트쇼 started (" .. reason .. ")")
end

-- Did the clock pass `t` while moving forward from `prev` to `cur` (both 0-24)?
local function crossed(prev: number, cur: number, t: number): boolean
	local d = (cur - prev) % 24
	if d <= 0 or d > 1 then
		return false -- not moving, or a jump (handled explicitly)
	end
	local rel = (t - prev) % 24
	return rel > 0 and rel <= d
end

-- Clock values at which an attribute changes: night window, phases and show times.
local boundaries: { number } = {}
local function addBoundary(v: any)
	if type(v) == "number" and v == v then
		table.insert(boundaries, v % 24)
	end
end
addBoundary(Config.NightStart)
addBoundary(Config.NightEnd)
for _, p in Config.Phases or {} do
	addBoundary(p.from)
	addBoundary(p.to)
end
if showCfg.Enabled then
	for _, t in showCfg.Times do
		addBoundary(t)
	end
end

-- Real seconds until the clock reaches the next boundary (math.huge when paused).
local function secondsToNextBoundary(clock: number): number
	if paused or rate <= 0 then
		return math.huge
	end
	local best = math.huge
	for _, b in boundaries do
		local d = (b - clock) % 24
		if d < 1e-6 then
			d = 24
		end
		if d < best then
			best = d
		end
	end
	return best / rate
end

---------------------------------------------------------------------------------------------------
-- 4. Client discovery tags (mobile perf)
---------------------------------------------------------------------------------------------------
-- The client world systems (GwangalliWorld/Util.discover) find untagged instances by class / name:
-- SurfaceGuis (MobileQuality draw distance / texture scale), Models with attribute LOD = "near"
-- (DetailLOD), glass named Window / RoomGlass (Signage) and RoomDepth models. Without tags every
-- client runs a Workspace-wide DescendantAdded handler for each of the ~270k instances that stream
-- in (a burst of tens of thousands after every quick travel). The server sees the whole map, so it
-- tags those instances once at start (about 10k tags, chunked) and then sets the Workspace
-- attribute GwDiscoverTagged: clients switch to tag signals only. Skipped when the build already
-- tagged the place (attribute set in the place file).
local DISCOVER_ATTR = "GwDiscoverTagged"
local function discoveryTag(inst: Instance): string?
	local cn = inst.ClassName
	if cn == "SurfaceGui" then
		return "GwSurfaceGui"
	elseif cn == "Model" then
		if inst.Name == "RoomDepth" then
			return "RoomDepth"
		elseif inst:GetAttribute("LOD") == "near" then
			-- outermost near models only (DetailLOD ignores nested ones)
			local a = inst.Parent
			while a and a ~= workspace do
				if a:GetAttribute("LOD") == "near" then
					return nil
				end
				a = a.Parent
			end
			return "NearLOD"
		end
	elseif cn == "Part" or cn == "WedgePart" or cn == "MeshPart" then
		local n = inst.Name
		if n == "RoomGlass" then
			return "RoomGlass"
		elseif n == "Window" and (inst :: BasePart).Material == Enum.Material.Glass and not inst:HasTag("NightWindow") then
			return "Window"
		end
	end
	return nil
end

-- Instances created at runtime (spawned cars with a near-LOD interior, props) keep the contract:
-- the server tags them as they are added (one ClassName read per new instance, server only; the
-- server does not stream, so this fires only for real creations / reparents).
workspace.DescendantAdded:Connect(function(inst)
	local tag = discoveryTag(inst)
	if tag and not inst:HasTag(tag) then
		inst:AddTag(tag)
	end
end)

task.spawn(function()
	if workspace:GetAttribute(DISCOVER_ATTR) == true then
		return
	end
	local t0 = os.clock()
	local PER_STEP = 4000 -- instances looked at per frame
	local tagged, seen = 0, 0
	local mapRoot = workspace:FindFirstChild("Gwangalli")
	local tops = if mapRoot then mapRoot:GetChildren() else {}
	for _, top in workspace:GetChildren() do
		if top ~= mapRoot and not top:IsA("Terrain") and not top:IsA("Camera") and not Players:GetPlayerFromCharacter(top) then
			table.insert(tops, top)
		end
	end
	local function visit(inst: Instance)
		local tag = discoveryTag(inst)
		if tag and not inst:HasTag(tag) then
			inst:AddTag(tag)
			tagged += 1
		end
		seen += 1
		if seen % PER_STEP == 0 then
			task.wait()
		end
	end
	local ok, err = pcall(function()
		-- module -> its direct children -> GetDescendants of each child: no single call returns a
		-- giant list (a district module holds up to ~50k instances)
		for _, top in tops do
			if top.Parent == nil then
				continue
			end
			visit(top)
			for _, child in top:GetChildren() do
				visit(child)
				for _, inst in child:GetDescendants() do
					visit(inst)
				end
			end
		end
	end)
	if ok then
		workspace:SetAttribute(DISCOVER_ATTR, true)
		print(string.format("[GwangalliEnvironment] discovery tags: %d added over %d instances in %.2fs", tagged, seen, os.clock() - t0))
	else
		warn("[GwangalliEnvironment] discovery tagging failed (clients keep their listener): " .. tostring(err))
	end
end)

---------------------------------------------------------------------------------------------------
-- 5. Near-only detail arrives hidden (mobile perf)
---------------------------------------------------------------------------------------------------
-- Clients hide near-only models (tag NearLOD) beyond ~70-150 studs with LocalTransparencyModifier
-- (GwangalliWorld/DetailLOD). With streaming, every near model that streams in far away used to
-- arrive VISIBLE and needed a hide job (a write per part, render cost until the job reached it):
-- after a quick travel that is thousands of parts, of which only a few hundred are ever shown.
-- Here the server saves the eligible ones hidden once at start: Transparency = 1 on every part /
-- decal (the shown value is kept in attribute GwT where it is not 0; the model gets GwTMix), and
-- attribute GwArrive = true on the model. Clients show such a model by writing Transparency locally
-- (never replicated) and hide it by writing 1 back; one that streams in far away costs them nothing,
-- and a fresh copy that streams back in is hidden again. Studio edit mode is unchanged (runtime only).
-- Eligible: an outermost near model inside workspace.Gwangalli, not in homes / npcnav, not inside a
-- zone (LOD = "zone" / ZoneLOD), a RoomDepth model, a vehicle (VehicleKind) or a rig, anchored parts
-- only, and nothing a script drives or that draws on its own: no tagged / attributed parts, lights,
-- guis, effects, prompts / click detectors, scripts, seats, humanoids or highlights inside. Those
-- keep the LocalTransparencyModifier path. Workspace attribute GwArriveReady (true when done, false
-- when disabled) lets clients wait for the pass instead of racing it on a fresh server. A model the
-- build already saved hidden (GwArrive set in the place file) is left as it is.
local ARRIVE_ATTR, ARRIVE_T_ATTR, ARRIVE_MIX_ATTR, ARRIVE_READY = "GwArrive", "GwT", "GwTMix", "GwArriveReady"
local ARRIVE_PARTS = {
	Part = true, WedgePart = true, CornerWedgePart = true, TrussPart = true, MeshPart = true,
	UnionOperation = true, IntersectOperation = true, NegateOperation = true,
}
local ARRIVE_DECALS = { Decal = true, Texture = true }
local ARRIVE_BLOCKERS = {
	Humanoid = true, PointLight = true, SpotLight = true, SurfaceLight = true, SurfaceGui = true,
	BillboardGui = true, ParticleEmitter = true, Beam = true, Trail = true, Fire = true, Smoke = true,
	Sparkles = true, ProximityPrompt = true, ClickDetector = true, DragDetector = true, Script = true,
	LocalScript = true, ModuleScript = true, Seat = true, VehicleSeat = true, SpawnLocation = true,
	Highlight = true, Actor = true,
}

task.spawn(function()
	local detailCfg = Config.DetailLOD or {}
	if detailCfg.ArriveHidden == false then
		workspace:SetAttribute(ARRIVE_READY, false)
		return
	end
	-- the pass reads tag NearLOD: wait for the discovery tags (section 4; set in the place file by the build)
	local waited = 0
	while workspace:GetAttribute(DISCOVER_ATTR) ~= true and waited < 60 do
		waited += task.wait(0.2)
	end
	local mapRoot = workspace:FindFirstChild("Gwangalli")
	if not mapRoot then
		workspace:SetAttribute(ARRIVE_READY, false)
		return
	end
	local t0 = os.clock()
	local PER_STEP = 4000 -- instances looked at per frame
	local seen, models, parts, skipped, already = 0, 0, 0, 0, 0

	local function blockedByAncestor(m: Instance): boolean
		local a = m.Parent
		local top: Instance? = nil
		while a and a ~= workspace do
			if a == mapRoot then
				break
			end
			if a:IsA("Model") then
				if a.Name == "RoomDepth" or a:HasTag("RoomDepth") or a:HasTag("ZoneLOD") or a:GetAttribute("LOD") == "zone"
					or a:GetAttribute("LOD") == "near" or a:GetAttribute("VehicleKind") ~= nil or a:FindFirstChildOfClass("Humanoid") then
					return true
				end
			end
			top = a
			a = a.Parent
		end
		if a ~= mapRoot then
			return true -- outside the static map (spawned vehicles, NPCs, client folders)
		end
		return top ~= nil and (top.Name == "homes" or top.Name == "npcnav")
	end

	local function convert(m: Model)
		if m:GetAttribute(ARRIVE_ATTR) ~= nil then
			already += 1
			return
		end
		if m:GetAttribute("VehicleKind") ~= nil or blockedByAncestor(m) then
			skipped += 1
			return
		end
		local desc = m:GetDescendants()
		seen += #desc
		local targets = table.create(#desc)
		for _, d in desc do
			local cn = d.ClassName
			if ARRIVE_PARTS[cn] then
				local p = d :: BasePart
				if not p.Anchored or #p:GetTags() > 0 or next(p:GetAttributes()) ~= nil then
					skipped += 1
					return
				end
				table.insert(targets, d)
			elseif ARRIVE_DECALS[cn] then
				table.insert(targets, d)
			elseif ARRIVE_BLOCKERS[cn] or (cn == "Model" and d:GetAttribute("VehicleKind") ~= nil) then
				skipped += 1
				return
			end
		end
		if #targets == 0 then
			return
		end
		local mix = false
		for _, d in targets do
			local x = d :: any
			local t = x.Transparency
			if t ~= 0 then
				d:SetAttribute(ARRIVE_T_ATTR, t)
				mix = true
			end
			if t ~= 1 then
				x.Transparency = 1
			end
		end
		if mix then
			m:SetAttribute(ARRIVE_MIX_ATTR, true)
		end
		m:SetAttribute(ARRIVE_ATTR, true) -- last: a model carrying it is complete
		models += 1
		parts += #targets
	end

	local ok, err = pcall(function()
		local list = CollectionService:GetTagged("NearLOD")
		local budget = PER_STEP
		for _, inst in list do
			if inst:IsA("Model") and inst:IsDescendantOf(mapRoot) then
				local before = seen
				convert(inst :: Model)
				budget -= math.max(1, seen - before)
				if budget <= 0 then
					budget = PER_STEP
					task.wait()
				end
			end
		end
	end)
	if ok then
		workspace:SetAttribute(ARRIVE_READY, true)
		print(string.format("[GwangalliEnvironment] near detail saved hidden: %d models (%d parts / decals), %d kept visible, %d already, %d instances looked at in %.2fs",
			models, parts, skipped, already, seen, os.clock() - t0))
	else
		-- models already converted carry GwArrive and work on their own; the rest keep the old path
		workspace:SetAttribute(ARRIVE_READY, false)
		warn("[GwangalliEnvironment] arrive-hidden pass failed: " .. tostring(err))
	end
end)

---------------------------------------------------------------------------------------------------
-- Main loop (no per-frame work: wakes about once a second, or exactly at the next boundary)
---------------------------------------------------------------------------------------------------

local lastClock = clockAt(workspace:GetServerTimeNow())
local lastPhase: string? = nil
local lastNight: boolean? = nil

local function step()
	local clock = clockAt(workspace:GetServerTimeNow())

	local phase = Shared.phaseForClock(clock)
	if phase ~= lastPhase then
		lastPhase = phase
		workspace:SetAttribute(A.Phase, phase)
	end
	local night = Shared.isNightClock(clock)
	if night ~= lastNight then
		lastNight = night
		workspace:SetAttribute(A.IsNight, night)
	end

	if showCfg.Enabled and not paused then
		for _, t in showCfg.Times do
			if crossed(lastClock, clock, t) then
				startDroneShow(string.format("%.2f", t))
				break
			end
		end
	end
	lastClock = clock

	if os.clock() - lastClockPublish >= 0.95 then
		publishClock(clock)
	end
end

local function safeStep()
	local ok, err = pcall(step)
	if not ok then
		warn("[GwangalliEnvironment] clock step failed: " .. tostring(err))
	end
end

---------------------------------------------------------------------------------------------------
-- Debug attributes
---------------------------------------------------------------------------------------------------

local function reanchor(newClock: number?)
	local now = workspace:GetServerTimeNow()
	anchorClock = (newClock or clockAt(now)) % 24
	anchorTime = now
	publishAnchor()
end

workspace:GetAttributeChangedSignal("GwangalliSetClock"):Connect(function()
	local v = workspace:GetAttribute("GwangalliSetClock")
	if type(v) == "number" and v == v then
		reanchor(v)
		workspace:SetAttribute("GwangalliSetClock", nil)
		lastClock = clockAt(workspace:GetServerTimeNow()) -- a jump never triggers a show
		publishClock(lastClock)
		safeStep()
	end
end)

workspace:GetAttributeChangedSignal("GwangalliDayLengthMinutes"):Connect(function()
	reanchor()
	rate = dayRate()
	publishAnchor()
end)

workspace:GetAttributeChangedSignal("GwangalliClockPaused"):Connect(function()
	local v = workspace:GetAttribute("GwangalliClockPaused") == true
	if v ~= paused then
		local now = workspace:GetServerTimeNow()
		anchorClock = clockAt(now)
		anchorTime = now
		paused = v
		publishAnchor()
		publishClock(anchorClock)
	end
end)

workspace:GetAttributeChangedSignal("GwangalliStartDroneShow"):Connect(function()
	if workspace:GetAttribute("GwangalliStartDroneShow") == true then
		workspace:SetAttribute("GwangalliStartDroneShow", false)
		showStartedAt = -math.huge
		startDroneShow("manual")
	end
end)

safeStep()
if showCfg.Enabled and showCfg.StartOnServerStart then
	task.delay(5, startDroneShow, "server start")
end

while true do
	local clock = clockAt(workspace:GetServerTimeNow())
	-- wake at the next boundary (+20 ms so the clock is past it), at least every second
	task.wait(math.clamp(secondsToNextBoundary(clock) + 0.02, 0.05, 1))
	safeStep()
end
