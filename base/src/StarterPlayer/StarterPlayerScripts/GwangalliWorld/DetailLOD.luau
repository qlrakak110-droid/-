-- DetailLOD: near-only detail, plus zone models (LOD = "zone": a venue interior hidden as a whole
-- while the camera is farther than its LODRadius, see "Zone models" below).
-- Models with attribute LOD = "near" (shop props, car interiors,
-- bottles, fish tanks ... see build/kit/interior.luau I.detail) are shown only within
-- Config.DetailLOD.Radius of the camera (high 120 / mid 100 / low 70 studs, + Hysteresis before
-- they hide again).
--
-- Hiding uses LocalTransparencyModifier through Util.setHidden (plus disabling guis / particles
-- inside): it is purely local and nothing structural changes, so streaming keeps working
-- (reparenting streamed instances into a client-side cache folder would break the engine's
-- stream-out bookkeeping, and moving them back costs more than an LTM write). While a model is
-- hidden, parts that stream into it later are hidden on arrival; a model that streams out is
-- dropped (AncestryChanged) and registered again when it streams back in (as a new instance, or
-- as the same object: Util.setHidden then rewrites parts that may still carry the old state).
--
-- Cost: static models live in a spatial grid (CellSize studs); UpdateHz (3) times per second only
-- the cells around the camera and the currently shown set are visited, never the whole list.
-- Models on unanchored parts (the taxi's cloned car interior rides on a tweened root) are kept in
-- a small "moving" set and re-positioned from a reference part on every update. The actual
-- LocalTransparencyModifier writes go through Util.setHidden's queue, capped per frame
-- (Config.DetailLOD.PartsPerFrame).
-- Discovery: tag "NearLOD" (Util.discover with tag: once the place is fully tagged, no per-instance
-- listener at all; before that, the shared Util.discover listener also checks every Model's
-- attribute).
-- Arrive hidden: most near models are saved hidden by the server (GwangalliEnvironment section 5,
-- attribute GwArrive; Util.setHidden writes Transparency for them). One that streams in beyond the
-- radius then costs nothing but its registration. Near models are registered only once the server
-- pass is done (Workspace attribute GwArriveReady present; at most 20 s wait on a fresh server).
-- Distance: to the model's bounding box (axis-aligned around its oriented box), not its centre, so
-- a long model (a wrack line along the beach, a facade detail) shows the part next to the camera.
-- Models wider than a grid cell are kept in a short "big" list checked on every update.
-- Workspace attribute GwDetailLODOff = true shows every near model and zone and stops hiding
-- (device A / B tests); false / nil resumes.

local DetailLOD = {}

type Rec = {
	model: Model,
	pos: Vector3,
	key: number,
	shown: boolean,
	conn: RBXScriptConnection?,
	-- moving models: position = ref.CFrame * offset (ref re-picked if it streams out)
	ref: BasePart?,
	offset: Vector3?,
	-- static models: world half extents of the bounding box (nil = small: centre distance)
	half: Vector3?,
	big: boolean?,
}

local SMALL_HALF = 12 -- a box no larger than this (half extent, studs) is measured from its centre

function DetailLOD.start(ctx: any)
	local Config, Util = ctx.Config, ctx.Util
	local cfg = Config.DetailLOD or {}
	local cell = math.max(16, tonumber(cfg.CellSize) or 64)
	local hysteresis = math.max(0, tonumber(cfg.Hysteresis) or 12)
	local updateHz = math.clamp(tonumber(cfg.UpdateHz) or 3, 1, 10)

	local function radius(): number
		local r = if type(cfg.Radius) == "table" then Util.budget(cfg.Radius) else cfg.Radius
		return math.max(10, tonumber(r) or 100)
	end

	Util.setHideBudget(function()
		local b = if type(cfg.PartsPerFrame) == "table" then Util.budget(cfg.PartsPerFrame) else cfg.PartsPerFrame
		return tonumber(b) or 400
	end)

	local grid: { [number]: { Rec } } = {}
	local recs: { [Model]: Rec } = {}
	local shown: { [Model]: Rec } = {}
	local moving: { [Model]: Rec } = {}
	local big: { [Model]: Rec } = {} -- static models wider than half a cell (checked every update)
	local bigHalf = cell * 0.5
	local off = workspace:GetAttribute("GwDetailLODOff") == true

	-- squared distance from `p` to the record's box (its centre for small / moving ones)
	local function dist2(rec: Rec, p: Vector3): number
		local d = rec.pos - p
		local h = rec.half
		if h then
			local x = math.abs(d.X) - h.X
			local y = math.abs(d.Y) - h.Y
			local z = math.abs(d.Z) - h.Z
			x = if x > 0 then x else 0
			y = if y > 0 then y else 0
			z = if z > 0 then z else 0
			return x * x + y * y + z * z
		end
		return d.X * d.X + d.Y * d.Y + d.Z * d.Z
	end
	-- models that streamed in without parts yet: { added, ancestry } connections
	local pendingParts: { [Model]: { RBXScriptConnection } } = {}

	local function dropPending(model: Model)
		local conns = pendingParts[model]
		if conns then
			pendingParts[model] = nil
			for _, c in conns do
				c:Disconnect()
			end
		end
	end

	local function keyOf(x: number, z: number): number
		-- cells within +-32767 of the origin (the map spans about +-10k studs)
		return (math.floor(x / cell) + 32768) * 65536 + (math.floor(z / cell) + 32768)
	end

	local function removeFromCell(rec: Rec)
		local list = grid[rec.key]
		if not list then
			return
		end
		local i = table.find(list, rec)
		if i then
			list[i] = list[#list]
			list[#list] = nil
		end
		if #list == 0 then
			grid[rec.key] = nil
		end
	end

	local function unregister(model: Model)
		local rec = recs[model]
		dropPending(model)
		if not rec then
			return
		end
		recs[model] = nil
		shown[model] = nil
		moving[model] = nil
		big[model] = nil
		if not rec.ref and not rec.big then
			removeFromCell(rec)
		end
		if rec.conn then
			rec.conn:Disconnect()
			rec.conn = nil
		end
		if model:IsDescendantOf(workspace) then
			Util.setHidden(model, false) -- attribute / tag removed but the model stays: show it again
		end
	end

	local function hasNearAncestor(model: Instance): boolean
		local a = model.Parent
		while a and a ~= workspace do
			if a:GetAttribute("LOD") == "near" then
				return true
			end
			a = a.Parent
		end
		return false
	end

	local function isNear(model: Model): boolean
		return model:GetAttribute("LOD") == "near" or model:HasTag("NearLOD")
	end

	-- Current world position of a moving record (nil when it has no parts left).
	local function movingPos(rec: Rec): Vector3?
		local ref = rec.ref
		if not ref or ref.Parent == nil or not ref:IsDescendantOf(rec.model) then
			local p = rec.model:FindFirstChildWhichIsA("BasePart", true)
			if not p then
				return nil
			end
			ref = p :: BasePart
			rec.ref = ref
			rec.offset = Vector3.zero
		end
		return (ref :: BasePart).CFrame:PointToWorldSpace(rec.offset or Vector3.zero)
	end

	local function place(model: Model): boolean
		local ref = model:FindFirstChildWhichIsA("BasePart", true) :: BasePart?
		if ref == nil then
			return false
		end
		local ok, cf, size = pcall(model.GetBoundingBox, model)
		if not ok then
			return false
		end
		local box = cf :: CFrame
		local pos = box.Position
		local rec: Rec = { model = model, pos = pos, key = 0, shown = true, conn = nil, ref = nil, offset = nil }
		recs[model] = rec
		if not ref.Anchored then
			-- rides on something that moves (welded to a tweened / simulated root)
			rec.ref = ref
			rec.offset = ref.CFrame:PointToObjectSpace(pos)
			moving[model] = rec
		else
			-- world-axis half extents of the oriented box
			local s = (size :: Vector3) * 0.5
			local rx, ry, rz = box.XVector, box.YVector, box.ZVector
			local h = Vector3.new(
				math.abs(rx.X) * s.X + math.abs(ry.X) * s.Y + math.abs(rz.X) * s.Z,
				math.abs(rx.Y) * s.X + math.abs(ry.Y) * s.Y + math.abs(rz.Y) * s.Z,
				math.abs(rx.Z) * s.X + math.abs(ry.Z) * s.Y + math.abs(rz.Z) * s.Z
			)
			if math.max(h.X, h.Y, h.Z) > SMALL_HALF then
				rec.half = h
			end
			if math.max(h.X, h.Z) > bigHalf then
				rec.big = true
				big[model] = rec
			else
				rec.key = keyOf(pos.X, pos.Z)
				local list = grid[rec.key]
				if not list then
					list = {}
					grid[rec.key] = list
				end
				table.insert(list, rec)
			end
		end
		rec.conn = model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				unregister(model)
			end
		end)
		-- decide right away (models arrive visible, unless the same object streamed back in with
		-- its old hidden state, which setHidden(false) rewrites)
		local camPos = Util.cameraPosition()
		local r = radius()
		if off or (camPos and dist2(rec, camPos) <= r * r) then
			shown[model] = rec
			Util.setHidden(model, false)
		else
			rec.shown = false
			Util.setHidden(model, true) -- (free for a model saved hidden: it already is)
		end
		return true
	end

	local function consider(inst: Instance)
		if not inst:IsA("Model") or recs[inst :: Model] or pendingParts[inst :: Model] then
			return
		end
		local model = inst :: Model
		if not isNear(model) then
			return
		end
		if not model:IsDescendantOf(workspace) or hasNearAncestor(model) then
			return -- an outer near model already covers it
		end
		if place(model) then
			return
		end
		-- streamed in empty (parts follow): place it when the first part arrives
		local added = model.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") and pendingParts[model] then
				dropPending(model)
				task.defer(function()
					if model:IsDescendantOf(workspace) and not recs[model] then
						place(model)
					end
				end)
			end
		end)
		local ancestry = model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				dropPending(model)
			end
		end)
		pendingParts[model] = { added, ancestry }
	end

	-- tag NearLOD (every near model once the place is tagged, see Util.discover), plus Models by
	-- class while the place is not tagged yet (attribute-only near models). Registered right away
	-- (the shared discovery starts after every module's start), but held back until the server's
	-- arrive-hidden pass is done, so no model is registered on the old path and then saved hidden.
	local arriveReady = workspace:GetAttribute("GwArriveReady") ~= nil
	local held: { Instance } = {}
	Util.discover({ class = "Model", tag = "NearLOD" }, function(inst: Instance)
		if arriveReady then
			consider(inst)
		else
			table.insert(held, inst)
		end
	end)
	if not arriveReady then
		task.spawn(function()
			local t0 = os.clock()
			while workspace:GetAttribute("GwArriveReady") == nil and os.clock() - t0 < 20 do
				task.wait(0.25)
			end
			arriveReady = true
			local list = held
			held = {}
			for i, inst in list do
				if inst:IsDescendantOf(workspace) then
					local ok, err = pcall(consider, inst)
					if not ok then
						Util.warn("DetailLOD", err)
					end
				end
				if i % 200 == 0 then
					task.wait()
				end
			end
		end)
	end
	-----------------------------------------------------------------------------------------------
	-- Zone models (LOD = "zone"): a whole venue interior hidden while the camera is outside
	-- LODRadius (+ Hysteresis) of its centre. Contract (set by the build): Model attribute
	-- LOD = "zone", LODRadius = studs, optional LODCenter = Vector3 (world; else the bounding box
	-- of what has streamed in), tag ZoneLOD. Near models inside keep their own radius (nested roots:
	-- Util.setHidden keeps them hidden while the zone is hidden). Few of them: all checked per update.
	-----------------------------------------------------------------------------------------------
	type ZoneRec = { model: Model, pos: Vector3?, r: number, shown: boolean, conn: RBXScriptConnection? }
	local zones: { [Model]: ZoneRec } = {}

	local function zoneCenter(model: Model): Vector3?
		local c = model:GetAttribute("LODCenter")
		if typeof(c) == "Vector3" then
			return c
		end
		if not model:FindFirstChildWhichIsA("BasePart", true) then
			return nil -- nothing streamed in yet: measured again on the next update
		end
		local ok, cf = pcall(model.GetBoundingBox, model)
		return if ok then (cf :: CFrame).Position else nil
	end

	local function considerZone(inst: Instance)
		if not inst:IsA("Model") or zones[inst :: Model] then
			return
		end
		local model = inst :: Model
		local r = model:GetAttribute("LODRadius")
		if model:GetAttribute("LOD") ~= "zone" or type(r) ~= "number" or r <= 0 or not model:IsDescendantOf(workspace) then
			return
		end
		local zr: ZoneRec = { model = model, pos = zoneCenter(model), r = r, shown = true, conn = nil }
		zones[model] = zr
		zr.conn = model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) and zones[model] == zr then
				zones[model] = nil
				if zr.conn then
					zr.conn:Disconnect()
				end
			end
		end)
		-- decide at once (a hidden zone must not flash its interior for a frame)
		local camPos = Util.cameraPosition()
		if not off and zr.pos and camPos and (zr.pos - camPos).Magnitude > r then
			zr.shown = false
			Util.setHidden(model, true)
		end
	end
	Util.discover({ class = "Model", tag = "ZoneLOD" }, considerZone)

	game:GetService("CollectionService"):GetInstanceRemovedSignal("NearLOD"):Connect(function(inst)
		-- (also fires on stream-out: unregister only a model that stays but lost its near marking)
		if recs[inst :: Model] and inst:IsDescendantOf(workspace) and inst:GetAttribute("LOD") ~= "near" then
			unregister(inst :: Model)
		end
	end)

	-- Periodic update: cells around the camera + the shown set + moving models ----------------
	local function setShown(rec: Rec, on: boolean)
		if rec.shown == on then
			return
		end
		rec.shown = on
		shown[rec.model] = if on then rec else nil
		Util.setHidden(rec.model, not on)
	end

	local function updateZones(camPos: Vector3)
		for model, zr in zones do
			local pos = zr.pos
			if not pos then
				pos = zoneCenter(model)
				zr.pos = pos
			end
			if pos then
				local d = (pos - camPos).Magnitude
				if zr.shown and d > zr.r + hysteresis then
					zr.shown = false
					Util.setHidden(model, true)
				elseif not zr.shown and d <= zr.r then
					zr.shown = true
					Util.setHidden(model, false)
				end
			end
		end
	end

	-- GwDetailLODOff: show everything (queued, budgeted), then stop hiding until it is cleared
	local function showAll()
		for _, rec in recs do
			setShown(rec, true)
		end
		for model, zr in zones do
			if not zr.shown then
				zr.shown = true
				Util.setHidden(model, false)
			end
		end
	end
	workspace:GetAttributeChangedSignal("GwDetailLODOff"):Connect(function()
		off = workspace:GetAttribute("GwDetailLODOff") == true
		if off then
			showAll()
		end
	end)

	local function update()
		local camPos = Util.cameraPosition()
		if not camPos or off then
			return
		end
		updateZones(camPos)
		local r = radius()
		local showR2 = r * r
		local hideR = r + hysteresis
		local hideR2 = hideR * hideR
		-- moving models: exact distance every update (a handful at most)
		for _, rec in moving do
			local p = movingPos(rec)
			if p then
				rec.pos = p
				local d = p - camPos
				local d2 = d.X * d.X + d.Y * d.Y + d.Z * d.Z
				if rec.shown and d2 > hideR2 then
					setShown(rec, false)
				elseif not rec.shown and d2 <= showR2 then
					setShown(rec, true)
				end
			end
		end
		-- hide shown static models that left the outer radius
		for _, rec in shown do
			if not rec.ref and dist2(rec, camPos) > hideR2 then
				setShown(rec, false)
			end
		end
		-- wide models: all of them (few; their box can reach the camera from a far cell)
		for _, rec in big do
			if not rec.shown and dist2(rec, camPos) <= showR2 then
				setShown(rec, true)
			end
		end
		-- show hidden static models inside the inner radius (only the cells that can contain them:
		-- a grid model's box reaches at most half a cell beyond its centre's cell)
		local span = math.ceil((r + bigHalf) / cell)
		local cx, cz = math.floor(camPos.X / cell), math.floor(camPos.Z / cell)
		for ix = cx - span, cx + span do
			for iz = cz - span, cz + span do
				local list = grid[(ix + 32768) * 65536 + (iz + 32768)]
				if list then
					for _, rec in list do
						if not rec.shown and dist2(rec, camPos) <= showR2 then
							setShown(rec, true)
						end
					end
				end
			end
		end
	end

	task.spawn(function()
		while true do
			task.wait(1 / updateHz)
			local ok, err = pcall(update)
			if not ok then
				Util.warn("DetailLOD", err)
			end
		end
	end)
end

return DetailLOD
