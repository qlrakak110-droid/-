--!native
-- GwangalliTerrainBaker: runs the generated terrain operations (ServerStorage.GwangalliTerrainOps)
-- either at server start (GwangalliEnvironment calls RunProgressive) or once in Studio edit mode
-- so the sand / sea bed / water are saved in the place file:
--
--   Command bar (edit mode):
--     require(game.ServerStorage.GwangalliTerrainBaker).Bake()
--     require(game.ServerStorage.GwangalliTerrainBaker).ClearWater()   -- see the sea bed
--     require(game.ServerStorage.GwangalliTerrainBaker).Unbake()       -- clear terrain + flag
--
-- After Bake() the workspace attribute GwangalliTerrainBaked = true makes the runtime skip the
-- fill entirely.
--
-- Runtime fill (RunProgressive), built so players can already walk around while it runs:
--   * Big axis-aligned Block / Wedge ops are split into tiles on a world grid whose lines are
--     multiples of the 4-stud voxel. Every voxel then lies in exactly one tile, so the result is
--     identical to the single big fill, but no single call takes more than a few milliseconds.
--   * Terrain ops overwrite each other, so their order matters where they touch. Each op waits for
--     every earlier op whose box (padded by two voxels) overlaps its own. Ops that do not touch can
--     run in any order, so the result is the same as running the list in order.
--   * Among the ops that are free to run, the one nearest to a focus point runs first: the spawn
--     and every player's character. An op that blocks a near op inherits its priority. The
--     beach around the spawn is therefore complete within the first frames, and the fill then
--     spreads outward.
--   * Every frame gets a time budget. The cost of the next op is predicted from the measured
--     seconds per voxel, and the op is left for the next frame when it would overrun the budget.
--   * "Covers" (the EditorOnly water preview parts) are removed one by one, as soon as every op
--     under their footprint has succeeded.
--   * --!native: planning and the priority pass are plain number crunching over ~8k pieces, so
--     native code (Roblox servers / Studio) shortens them; elsewhere the directive is ignored.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local Baker = {}

local BAKED_ATTR = "GwangalliTerrainBaked"
local READY_ATTR = "GwangalliTerrainReady"
local EDITOR_ONLY = "EditorOnly"

-- Fallback extents for ClearWater (studs) when the ops cannot be read: the true-scale map's water
-- runs from the Suyeong river mouth (x ~ -6700) past Namcheon (x ~ 5500), from beyond Gwangan
-- Bridge (z ~ -5000) up the river (z ~ 7000); the sea surface is y = 0.
Baker.Extents = { min = Vector3.new(-6784, -64, -5120), max = Vector3.new(5632, 16, 7040) }

local materialCache: { [string]: Enum.Material | false } = {}
local function material(name: any): Enum.Material?
	if typeof(name) == "EnumItem" then
		return name
	end
	if type(name) ~= "string" then
		return nil
	end
	local cached = materialCache[name]
	if cached == nil then
		local ok, value = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		cached = (ok and value) or false
		materialCache[name] = cached
	end
	return cached or nil
end

local function applyOp(terrain: Terrain, op: any): (boolean, string?)
	if type(op) ~= "table" then
		return false, "op is not a table"
	end
	local kind = op[1]
	if kind == "Block" or kind == "Wedge" then
		local cf, size, mat = op[2], op[3], material(op[4])
		if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" or not mat then
			return false, "bad " .. tostring(kind) .. " arguments"
		end
		if kind == "Block" then
			terrain:FillBlock(cf, size, mat)
		else
			terrain:FillWedge(cf, size, mat)
		end
		return true, nil
	elseif kind == "Ball" then
		local center, radius, mat = op[2], op[3], material(op[4])
		if typeof(center) ~= "Vector3" or type(radius) ~= "number" or not mat then
			return false, "bad Ball arguments"
		end
		terrain:FillBall(center, radius, mat)
		return true, nil
	elseif kind == "Cylinder" then
		local cf, height, radius, mat = op[2], op[3], op[4], material(op[5])
		if typeof(cf) ~= "CFrame" or type(height) ~= "number" or type(radius) ~= "number" or not mat then
			return false, "bad Cylinder arguments"
		end
		terrain:FillCylinder(cf, height, radius, mat)
		return true, nil
	end
	return false, "unknown op " .. tostring(kind)
end

-- Loads the generated ops table. Returns nil (and warns) when the module is missing/broken.
function Baker.LoadOps(): { any }?
	local mod = ServerStorage:FindFirstChild("GwangalliTerrainOps")
	if not mod or not mod:IsA("ModuleScript") then
		warn("[GwangalliTerrainBaker] ServerStorage.GwangalliTerrainOps not found")
		return nil
	end
	local ok, ops = pcall(require, mod)
	if not ok or type(ops) ~= "table" then
		warn("[GwangalliTerrainBaker] could not load terrain ops (regenerate the place with a fixed build/build.luau): " .. tostring(ops))
		return nil
	end
	local valid, reason = Baker.Validate(ops)
	if not valid then
		warn("[GwangalliTerrainBaker] GwangalliTerrainOps rejected: " .. tostring(reason))
		return nil
	end
	return ops
end

-- Sanity check before filling: a generator bug that loses the CFrames (every op collapsing onto
-- the same point) would otherwise dump hundreds of sand/water/rock volumes on the spawn plaza.
-- Returns (ok, reason?).
function Baker.Validate(ops: { any }): (boolean, string?)
	if type(ops) ~= "table" then
		return false, "ops is not a table"
	end
	local positioned, distinct, seen = 0, 0, {}
	for _, op in ops do
		if type(op) == "table" then
			local anchor = op[2]
			local pos: Vector3? = nil
			if typeof(anchor) == "CFrame" then
				pos = anchor.Position
			elseif typeof(anchor) == "Vector3" then
				pos = anchor
			end
			if pos then
				positioned += 1
				-- (concatenation, not %d: a NaN or huge coordinate must not throw here)
				local key = math.floor(pos.X) .. "," .. math.floor(pos.Y) .. "," .. math.floor(pos.Z)
				if not seen[key] then
					seen[key] = true
					distinct += 1
				end
			end
		end
	end
	if #ops > 0 and positioned == 0 then
		return false, "no op has a CFrame/Vector3 anchor"
	end
	if positioned >= 40 and distinct * 20 < positioned then
		return false, string.format("%d of %d ops share only %d positions (CFrames lost by the generator?)", positioned, #ops, distinct)
	end
	return true, nil
end

-- Executes ops in list order (edit-mode bake). opts.yield = true -> task.wait() whenever
-- opts.frameBudget seconds were used. opts.onProgress(done, total) is called after every batch.
-- Returns (applied, failed).
function Baker.RunOps(ops: { any }, opts: { yield: boolean?, frameBudget: number?, onProgress: ((number, number) -> ())? }?): (number, number)
	local o = opts or {}
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		warn("[GwangalliTerrainBaker] Workspace has no Terrain")
		return 0, #ops
	end
	local budget = o.frameBudget or 0.008
	local applied, failed = 0, 0
	local total = #ops
	local t0 = os.clock()
	local reported = 0
	for i = 1, total do
		local ok, result, reason = pcall(applyOp, terrain, ops[i])
		if ok and result then
			applied += 1
		else
			failed += 1
			if failed <= 5 then
				warn(string.format("[GwangalliTerrainBaker] op %d failed: %s", i, tostring(ok and reason or result)))
			end
		end
		if o.yield and os.clock() - t0 >= budget then
			if o.onProgress then
				o.onProgress(i, total)
			end
			reported = i
			task.wait()
			t0 = os.clock()
		end
	end
	if o.onProgress and reported ~= total then
		o.onProgress(total, total)
	end
	if failed > 5 then
		warn(string.format("[GwangalliTerrainBaker] %d terrain ops failed in total", failed))
	end
	return applied, failed
end

---------------------------------------------------------------------------------------------------
-- Progressive runtime fill: split -> dependency graph -> nearest-first, frame-budgeted execution
---------------------------------------------------------------------------------------------------

local VOXEL = 4
-- Split steps (studs) tried from coarse to fine; all are multiples of VOXEL, so every cut plane
-- lies on a voxel boundary and each voxel ends up in exactly one piece.
local SPLIT_STEPS_XZ = { 512, 256, 128, 64 }
local SPLIT_STEP_Y = 64
local TARGET_VOXELS = 16384 -- aligned ops above this many 4-stud voxels are split (~1M studs^3)
local PAD = 2 * VOXEL -- boxes closer than this may share a voxel, so their order is kept
local CELL = 256 -- spatial hash cell size (studs) for the overlap search
local MAX_CELL_SPAN = 4096 -- an op covering more cells than this is tested against every op
local ALIGN_EPS = 1e-4
-- The generator writes rotation components with 3 decimals, so a box turned by ~0.6 degrees
-- arrives as RightVector (1, 0, 0.011): its main component is exactly 1 although it is not
-- aligned. Such an axis must not count as a world axis (a 1,000-stud box would be cut 5-11 studs
-- off its true faces), so the other two components must be ~0 as well.
local OFF_AXIS_EPS = 1e-5
local MIN_COST_VOXELS = 512 -- per-call overhead, in voxels, for the cost prediction
local PLAN_YIELD_PIECES = 1024 -- planning also yields after this many pieces (besides the budget)
-- A further piece may start in a frame when its predicted end stays within budget * this factor
-- (a 25 % overrun of an 8 ms budget is harmless; stopping early would waste half of each frame).
local BUDGET_SLACK = 1.25

local function finiteVector(v: Vector3): boolean
	local s = v.X + v.Y + v.Z
	return s == s and s ~= math.huge and s ~= -math.huge
end

-- 1, 2 or 3 when `v` points along world X, Y or Z (either sign), else nil.
local function worldAxis(v: Vector3): number?
	local x, y, z = math.abs(v.X), math.abs(v.Y), math.abs(v.Z)
	if x >= 1 - ALIGN_EPS and y <= OFF_AXIS_EPS and z <= OFF_AXIS_EPS then
		return 1
	elseif y >= 1 - ALIGN_EPS and x <= OFF_AXIS_EPS and z <= OFF_AXIS_EPS then
		return 2
	elseif z >= 1 - ALIGN_EPS and x <= OFF_AXIS_EPS and y <= OFF_AXIS_EPS then
		return 3
	end
	return nil
end

local function component(v: Vector3, axis: number): number
	return if axis == 1 then v.X elseif axis == 2 then v.Y else v.Z
end

local function withComponent(v: Vector3, axis: number, value: number): Vector3
	if axis == 1 then
		return Vector3.new(value, v.Y, v.Z)
	elseif axis == 2 then
		return Vector3.new(v.X, value, v.Z)
	end
	return Vector3.new(v.X, v.Y, value)
end

-- Rotation-aware world AABB half extents of a box (cf, size).
local function boxHalfExtents(cf: CFrame, s: Vector3): Vector3
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return Vector3.new(
		0.5 * (math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z),
		0.5 * (math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z),
		0.5 * (math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z)
	)
end

-- Boundaries of [a, b] cut at the multiples of `step` that lie strictly inside.
local function cuts(a: number, b: number, step: number): { number }
	local out = { a }
	local k = math.floor(a / step) + 1
	while k * step < b - 1e-3 do
		if k * step > a + 1e-3 then
			table.insert(out, k * step)
		end
		k += 1
	end
	table.insert(out, b)
	return out
end

-- Coarsest XZ step whose tile (step x height x step) stays within TARGET_VOXELS.
local function splitStep(height: number): number
	local h = math.max(height, VOXEL)
	for _, step in SPLIT_STEPS_XZ do
		if step * step * math.min(h, SPLIT_STEP_Y) / 64 <= TARGET_VOXELS then
			return step
		end
	end
	return SPLIT_STEPS_XZ[#SPLIT_STEPS_XZ]
end

-- Calls emit(op, lo, hi, voxels) once per piece (lo/hi = world AABB, nil for an invalid op).
local function splitOp(op: any, emit: (any, Vector3?, Vector3?, number) -> ())
	if type(op) ~= "table" then
		emit(op, nil, nil, 0)
		return
	end
	local kind = op[1]
	if kind == "Block" or kind == "Wedge" then
		local cf, size = op[2], op[3]
		if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" or not finiteVector(cf.Position) or not finiteVector(size) then
			emit(op, nil, nil, 0)
			return
		end
		local half = boxHalfExtents(cf, size)
		local lo, hi = cf.Position - half, cf.Position + half
		local divisor = if kind == "Block" then 64 else 128
		local voxels = math.abs(size.X * size.Y * size.Z) / divisor
		if voxels <= TARGET_VOXELS then
			emit(op, lo, hi, voxels)
			return
		end
		local ar = worldAxis(cf.RightVector)
		if kind == "Block" then
			local au, al = worldAxis(cf.UpVector), worldAxis(cf.LookVector)
			if not (ar and au and al) then
				-- Rotated box. When one of its axes is still a world axis (e.g. a river reach turned
				-- about Y), its cross-section is constant along that axis: cut there on the voxel
				-- grid. Otherwise it cannot be cut exactly and is kept whole.
				local axis, which, localLength, cross = nil, "", 0, 0
				if au then
					axis, which, localLength, cross = au, "Y", size.Y, math.abs(size.X * size.Z)
				elseif ar then
					axis, which, localLength, cross = ar, "X", size.X, math.abs(size.Y * size.Z)
				elseif al then
					axis, which, localLength, cross = al, "Z", size.Z, math.abs(size.X * size.Y)
				end
				if not axis then
					emit(op, lo, hi, voxels)
					return
				end
				local a0 = axis :: number
				-- step: the longest multiple of VOXEL whose slab stays within TARGET_VOXELS
				local perStud = cross / 64
				local step = math.max(VOXEL, math.floor(TARGET_VOXELS / math.max(perStud, 1e-6) / VOXEL) * VOXEL)
				local a, b = component(lo, a0), component(hi, a0)
				local cs = cuts(a, b, step)
				if #cs == 2 then
					emit(op, lo, hi, voxels)
					return
				end
				local rotation = cf - cf.Position
				for ci = 1, #cs - 1 do
					local c0, c1 = cs[ci], cs[ci + 1]
					local pos = withComponent(cf.Position, a0, (c0 + c1) / 2)
					local len = c1 - c0
					local psize = if which == "Y" then Vector3.new(size.X, len, size.Z)
						elseif which == "X" then Vector3.new(len, size.Y, size.Z)
						else Vector3.new(size.X, size.Y, len)
					emit(
						{ "Block", CFrame.new(pos) * rotation, psize, op[4] },
						withComponent(lo, a0, c0),
						withComponent(hi, a0, c1),
						voxels * len / math.max(localLength, 1e-6)
					)
				end
				return
			end
			-- An axis-aligned box is the same box whatever its axis permutation: pieces use an
			-- identity rotation and world-space sizes.
			local step = splitStep(hi.Y - lo.Y)
			local xs, ys, zs = cuts(lo.X, hi.X, step), cuts(lo.Y, hi.Y, SPLIT_STEP_Y), cuts(lo.Z, hi.Z, step)
			if #xs == 2 and #ys == 2 and #zs == 2 then
				emit(op, lo, hi, voxels)
				return
			end
			for xi = 1, #xs - 1 do
				for zi = 1, #zs - 1 do
					for yi = 1, #ys - 1 do
						local plo = Vector3.new(xs[xi], ys[yi], zs[zi])
						local phi = Vector3.new(xs[xi + 1], ys[yi + 1], zs[zi + 1])
						local psize = phi - plo
						emit({ "Block", CFrame.new((plo + phi) / 2), psize, op[4] }, plo, phi, psize.X * psize.Y * psize.Z / 64)
					end
				end
			end
			return
		end
		-- Wedge: its cross-section is constant along the local X axis, so it can be cut there
		-- (only when local X is a world axis, so the cut planes stay on the voxel grid).
		if not ar then
			emit(op, lo, hi, voxels)
			return
		end
		local axis = ar :: number
		local crossVoxels = math.abs(size.Y * size.Z) / 128 -- voxels per stud of length
		local step = SPLIT_STEPS_XZ[#SPLIT_STEPS_XZ]
		for _, s in SPLIT_STEPS_XZ do
			if s * crossVoxels <= TARGET_VOXELS then
				step = s
				break
			end
		end
		local cs = cuts(component(lo, axis), component(hi, axis), step)
		if #cs == 2 then
			emit(op, lo, hi, voxels)
			return
		end
		local rotation = cf - cf.Position
		for ci = 1, #cs - 1 do
			local a, b = cs[ci], cs[ci + 1]
			local pos = withComponent(cf.Position, axis, (a + b) / 2)
			local psize = Vector3.new(b - a, size.Y, size.Z)
			emit(
				{ "Wedge", CFrame.new(pos) * rotation, psize, op[4] },
				withComponent(lo, axis, a),
				withComponent(hi, axis, b),
				psize.X * psize.Y * psize.Z / 128
			)
		end
		return
	elseif kind == "Ball" then
		local center, radius = op[2], op[3]
		if typeof(center) ~= "Vector3" or type(radius) ~= "number" or not finiteVector(center) or radius ~= radius then
			emit(op, nil, nil, 0)
			return
		end
		local e = Vector3.one * math.abs(radius)
		emit(op, center - e, center + e, 4.19 * math.abs(radius) ^ 3 / 64)
		return
	elseif kind == "Cylinder" then
		local cf, height, radius = op[2], op[3], op[4]
		if typeof(cf) ~= "CFrame" or type(height) ~= "number" or type(radius) ~= "number" or not finiteVector(cf.Position) or height ~= height or radius ~= radius then
			emit(op, nil, nil, 0)
			return
		end
		-- The cylinder axis is the CFrame's UpVector.
		local u = cf.UpVector
		local h, r = math.abs(height) / 2, math.abs(radius)
		local e = Vector3.new(
			math.abs(u.X) * h + r * math.sqrt(math.max(0, 1 - u.X * u.X)),
			math.abs(u.Y) * h + r * math.sqrt(math.max(0, 1 - u.Y * u.Y)),
			math.abs(u.Z) * h + r * math.sqrt(math.max(0, 1 - u.Z * u.Z))
		)
		emit(op, cf.Position - e, cf.Position + e, math.pi * r * r * math.abs(height) / 64)
		return
	end
	emit(op, nil, nil, 0)
end

local function cellKey(cx: number, cz: number): number
	return cx * 65536 + cz -- unique while |cz| < 32768 cells (8.3M studs)
end

export type Plan = {
	opCount: number,
	count: number, -- pieces
	op: { any },
	index: { number }, -- original op index of each piece
	lo: { Vector3 | false },
	hi: { Vector3 | false },
	-- the same boxes as plain numbers (hot loops avoid Vector3 reads); invalid pieces get an empty
	-- box (x0 = math.huge, x1 = -math.huge) that overlaps nothing
	x0: { number },
	x1: { number },
	y0: { number },
	y1: { number },
	z0: { number },
	z1: { number },
	voxels: { number },
	totalVoxels: number,
	succ: { { number } | false },
	preds: { number },
	edges: number,
	cells: { [number]: { number } },
	wide: { number }, -- pieces too wide for the cell grid
}

-- Splits the ops and builds the ordering graph. opts.yield = true yields (task.wait) whenever
-- opts.frameBudget seconds were used. Returns the plan used by NewFill.
function Baker.Plan(ops: { any }, opts: { yield: boolean?, frameBudget: number? }?): Plan
	local o = opts or {}
	local budget = o.frameBudget or 0.008
	local t0 = os.clock()
	local sinceYield = 0
	local function maybeYield(work: number)
		sinceYield += work
		if o.yield and (sinceYield >= PLAN_YIELD_PIECES or os.clock() - t0 >= budget) then
			task.wait()
			t0 = os.clock()
			sinceYield = 0
		end
	end

	local pOp, pIndex, pLo, pHi, pVox = {}, {}, {}, {}, {}
	local X0, X1, Y0, Y1, Z0, Z1 = {}, {}, {}, {}, {}, {}
	local n = 0
	local totalVoxels = 0
	local currentIndex = 0
	local function emit(op: any, lo: Vector3?, hi: Vector3?, voxels: number)
		n += 1
		pOp[n] = op
		pIndex[n] = currentIndex
		pLo[n] = lo or false
		pHi[n] = hi or false
		if lo and hi then
			X0[n], X1[n], Y0[n], Y1[n], Z0[n], Z1[n] = lo.X, hi.X, lo.Y, hi.Y, lo.Z, hi.Z
		else
			X0[n], X1[n], Y0[n], Y1[n], Z0[n], Z1[n] = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
		end
		pVox[n] = voxels
		totalVoxels += voxels
	end
	for i = 1, #ops do
		currentIndex = i
		local before = n
		splitOp(ops[i], emit)
		maybeYield(n - before)
	end

	-- Ordering graph: piece j must run before piece i when j comes from an earlier op and their
	-- padded boxes overlap. Edges always point from a lower to a higher piece number.
	local succ: { { number } | false } = table.create(n, false)
	local preds: { number } = table.create(n, 0)
	local mark: { number } = table.create(n, 0)
	local cells: { [number]: { number } } = {}
	local wide: { number } = {}
	local edges = 0

	local function link(j: number, i: number)
		if X0[j] > X1[i] + PAD or X0[i] > X1[j] + PAD then
			return
		end
		if Z0[j] > Z1[i] + PAD or Z0[i] > Z1[j] + PAD then
			return
		end
		if Y0[j] > Y1[i] + PAD or Y0[i] > Y1[j] + PAD then
			return
		end
		local list = succ[j]
		if list then
			table.insert(list, i)
		else
			succ[j] = { i }
		end
		preds[i] += 1
		edges += 1
	end

	for i = 1, n do
		if pLo[i] then
			local idx = pIndex[i]
			-- earlier pieces that are too wide for the grid
			for _, j in wide do
				if mark[j] ~= i and pIndex[j] < idx then
					mark[j] = i
					link(j, i)
				end
			end
			local x0, x1 = math.floor((X0[i] - PAD) / CELL), math.floor((X1[i] + PAD) / CELL)
			local z0, z1 = math.floor((Z0[i] - PAD) / CELL), math.floor((Z1[i] + PAD) / CELL)
			local span = (x1 - x0 + 1) * (z1 - z0 + 1)
			if span > MAX_CELL_SPAN then
				-- test against every earlier piece, then keep it in the wide list
				for j = 1, i - 1 do
					if mark[j] ~= i and pIndex[j] < idx then
						mark[j] = i
						link(j, i)
					end
				end
				table.insert(wide, i)
			else
				for cx = x0, x1 do
					for cz = z0, z1 do
						local key = cellKey(cx, cz)
						local list = cells[key]
						if list then
							for _, j in list do
								if mark[j] ~= i and pIndex[j] < idx then
									mark[j] = i
									link(j, i)
								end
							end
							table.insert(list, i)
						else
							cells[key] = { i }
						end
					end
				end
			end
		end
		maybeYield(1)
	end

	return {
		opCount = #ops,
		count = n,
		op = pOp,
		index = pIndex,
		lo = pLo,
		hi = pHi,
		x0 = X0,
		x1 = X1,
		y0 = Y0,
		y1 = Y1,
		z0 = Z0,
		z1 = Z1,
		voxels = pVox,
		totalVoxels = totalVoxels,
		succ = succ,
		preds = preds,
		edges = edges,
		cells = cells,
		wide = wide,
	}
end

export type FillJob = {
	plan: Plan,
	SetFocus: (self: FillJob, points: { Vector3 }) -> (),
	AddCover: (self: FillJob, lo: Vector3, hi: Vector3, onClear: () -> ()) -> (),
	Step: (self: FillJob, budget: number) -> boolean,
	NextPriority: (self: FillJob) -> number,
	IsDone: (self: FillJob) -> boolean,
	Progress: (self: FillJob) -> number,
	Result: (self: FillJob) -> (number, number),
}

-- Creates an executor for a plan. Pieces run nearest-first (see SetFocus) within Step budgets.
function Baker.NewFill(plan: Plan): FillJob
	local n = plan.count
	local pOp, pVox, pIndex = plan.op, plan.voxels, plan.index
	local X0, X1, Z0, Z1 = plan.x0, plan.x1, plan.z0, plan.z1
	local succ = plan.succ
	local waiting: { number } = table.clone(plan.preds)
	local done: { boolean } = table.create(n, false)
	local eff: { number } = table.create(n, math.huge)
	local heap: { number } = {}
	local heapSize = 0
	local finished = 0
	local doneVoxels = 0
	local opFailed: { [number]: boolean } = {}
	local failedPieces = 0
	local secondsPerVoxel = 50e-9 -- initial guess (20M voxels/s); measured while running

	-- covers
	local coverPending: { number } = {}
	local coverTainted: { boolean } = {}
	local coverFired: { boolean } = {}
	local coverFn: { () -> () } = {}
	local pieceCovers: { [number]: { number } } = {}

	local function less(a: number, b: number): boolean
		local ea, eb = eff[a], eff[b]
		if ea ~= eb then
			return ea < eb
		end
		return a < b
	end
	local function siftUp(pos: number)
		local item = heap[pos]
		while pos > 1 do
			local parent = pos // 2
			local p = heap[parent]
			if less(item, p) then
				heap[pos] = p
				pos = parent
			else
				break
			end
		end
		heap[pos] = item
	end
	local function siftDown(pos: number)
		local item = heap[pos]
		while true do
			local left = pos * 2
			if left > heapSize then
				break
			end
			local child = left
			local right = left + 1
			if right <= heapSize and less(heap[right], heap[left]) then
				child = right
			end
			if less(heap[child], item) then
				heap[pos] = heap[child]
				pos = child
			else
				break
			end
		end
		heap[pos] = item
	end
	local function push(i: number)
		heapSize += 1
		heap[heapSize] = i
		siftUp(heapSize)
	end
	local function pop(): number
		local top = heap[1]
		heap[1] = heap[heapSize]
		heap[heapSize] = nil
		heapSize -= 1
		if heapSize > 0 then
			siftDown(1)
		end
		return top
	end

	local focusX: { number } = {}
	local focusZ: { number } = {}
	local function ownPriority(i: number): number
		local x0, x1, z0, z1 = X0[i], X1[i], Z0[i], Z1[i]
		if x0 > x1 then
			return math.huge -- invalid piece
		end
		local best = math.huge
		for k = 1, #focusX do
			local px, pz = focusX[k], focusZ[k]
			local dx = math.max(x0 - px, 0, px - x1)
			local dz = math.max(z0 - pz, 0, pz - z1)
			local d = dx * dx + dz * dz
			if d < best then
				best = d
			end
		end
		return math.sqrt(best)
	end
	local function recompute()
		-- successors always have higher piece numbers: one reverse pass propagates priorities
		for i = n, 1, -1 do
			if not done[i] then
				local e = ownPriority(i)
				local list = succ[i]
				if list then
					for _, j in list do
						local ej = eff[j]
						if ej < e then
							e = ej
						end
					end
				end
				eff[i] = e
			else
				eff[i] = math.huge
			end
		end
		for pos = heapSize // 2, 1, -1 do
			siftDown(pos)
		end
	end

	-- Ready pieces in ascending order: with every priority still math.huge (no focus yet) that
	-- array already is a valid heap. SetFocus computes the real priorities.
	for i = 1, n do
		if waiting[i] == 0 then
			heapSize += 1
			heap[heapSize] = i
		end
	end

	local terrain: Terrain? = nil
	local job = {} :: any
	job.plan = plan

	function job.SetFocus(_self, points: { Vector3 })
		table.clear(focusX)
		table.clear(focusZ)
		for k, p in points do
			focusX[k] = p.X
			focusZ[k] = p.Z
		end
		recompute()
	end

	-- onClear runs once every piece whose XZ box meets [lo, hi] has been applied successfully.
	-- It never runs when one of them failed, or when no piece lies under the cover at all.
	function job.AddCover(_self, lo: Vector3, hi: Vector3, onClear: () -> ())
		local id = #coverFn + 1
		coverFn[id] = onClear
		coverPending[id] = 0
		coverTainted[id] = false
		coverFired[id] = false
		local loX, loZ, hiX, hiZ = lo.X, lo.Z, hi.X, hi.Z
		local seen: { [number]: boolean } = {}
		local function consider(i: number)
			if seen[i] then
				return
			end
			seen[i] = true
			if X0[i] > X1[i] then
				return -- invalid piece
			end
			if X0[i] > hiX + PAD or loX > X1[i] + PAD or Z0[i] > hiZ + PAD or loZ > Z1[i] + PAD then
				return
			end
			if done[i] then
				return
			end
			coverPending[id] += 1
			local list = pieceCovers[i]
			if list then
				table.insert(list, id)
			else
				pieceCovers[i] = { id }
			end
		end
		for _, i in plan.wide do
			consider(i)
		end
		local x0, x1 = math.floor((loX - PAD) / CELL), math.floor((hiX + PAD) / CELL)
		local z0, z1 = math.floor((loZ - PAD) / CELL), math.floor((hiZ + PAD) / CELL)
		if (x1 - x0 + 1) * (z1 - z0 + 1) > MAX_CELL_SPAN then
			for i = 1, n do
				consider(i)
			end
		else
			for cx = x0, x1 do
				for cz = z0, z1 do
					local list = plan.cells[cellKey(cx, cz)]
					if list then
						for _, i in list do
							consider(i)
						end
					end
				end
			end
		end
		-- A cover with no piece under it is left alone: the caller's final sweep decides.
	end

	local function settle(i: number, ok: boolean)
		done[i] = true
		finished += 1
		doneVoxels += pVox[i]
		local covers = pieceCovers[i]
		if covers then
			pieceCovers[i] = nil
			for _, id in covers do
				if not ok then
					coverTainted[id] = true
				end
				coverPending[id] -= 1
				if coverPending[id] <= 0 and not coverTainted[id] and not coverFired[id] then
					coverFired[id] = true
					task.spawn(coverFn[id])
				end
			end
		end
		local list = succ[i]
		if list then
			for _, j in list do
				waiting[j] -= 1
				if waiting[j] == 0 then
					push(j)
				end
			end
		end
	end

	-- Runs pieces until `budget` seconds are used (at least one piece per call). Returns true when
	-- everything has run.
	function job.Step(_self, budget: number): boolean
		if finished >= n then
			return true
		end
		if not terrain or not terrain.Parent then
			terrain = workspace:FindFirstChildOfClass("Terrain")
		end
		local t = terrain
		local t0 = os.clock()
		local ran = 0
		while heapSize > 0 do
			local i = heap[1]
			local cost = math.max(pVox[i], MIN_COST_VOXELS)
			if ran > 0 and os.clock() - t0 + cost * secondsPerVoxel > budget * BUDGET_SLACK then
				break
			end
			pop()
			local ok, result, reason
			if t then
				local s = os.clock()
				ok, result, reason = pcall(applyOp, t, pOp[i])
				local dt = os.clock() - s
				if ok and result then
					local measured = math.clamp(dt / cost, 1e-10, 1e-5)
					secondsPerVoxel = secondsPerVoxel * 0.75 + measured * 0.25
				end
			else
				ok, result, reason = true, false, "Workspace has no Terrain"
			end
			local success = ok and result == true
			if not success then
				failedPieces += 1
				local idx = pIndex[i]
				if not opFailed[idx] then
					opFailed[idx] = true
					if failedPieces <= 5 then
						warn(string.format("[GwangalliTerrainBaker] op %d failed: %s", idx, tostring(if ok then reason else result)))
					end
				end
			end
			settle(i, success)
			ran += 1
			if os.clock() - t0 >= budget then
				break
			end
		end
		if heapSize == 0 and finished < n then
			-- cannot happen (edges only point forward); never spin forever
			warn(string.format("[GwangalliTerrainBaker] %d terrain pieces were never ready", n - finished))
			for i = 1, n do
				if not done[i] then
					settle(i, false)
					opFailed[pIndex[i]] = true
				end
			end
		end
		return finished >= n
	end

	function job.NextPriority(_self): number
		return if heapSize > 0 then eff[heap[1]] else math.huge
	end

	function job.IsDone(_self): boolean
		return finished >= n
	end

	function job.Progress(_self): number
		if plan.totalVoxels <= 0 then
			return if n == 0 then 1 else finished / n
		end
		return math.clamp(doneVoxels / plan.totalVoxels, 0, 1)
	end

	-- (applied ops, failed ops), counted per original op (an op fails when any piece failed).
	function job.Result(_self): (number, number)
		local failed = 0
		for _ in opFailed do
			failed += 1
		end
		return plan.opCount - failed, failed
	end

	return job :: FillJob
end

export type ProgressiveOptions = {
	frameBudget: number?, -- seconds per frame while work near a focus point remains (default 8 ms)
	backgroundBudget: number?, -- seconds per frame for the rest (default frameBudget / 2)
	nearRadius: number?, -- studs; work within this distance of a focus point uses frameBudget
	getFocus: (() -> { Vector3 })?, -- polled every focusInterval seconds
	focusInterval: number?,
	focusMoveThreshold: number?, -- studs a focus point must move before priorities are recomputed
	focusMinInterval: number?, -- seconds between recomputes for walking; a new or gone point, or a
	-- jump of more than focusJumpStuds between two polls (quick travel), recomputes at once
	focusJumpStuds: number?,
	isBusy: (() -> boolean)?, -- true when players are in the server (background budget applies)
	covers: { { min: Vector3, max: Vector3, onClear: () -> () } }?,
	onPlanned: ((Plan) -> ())?,
	onNearDone: (() -> ())?, -- once, when nothing within nearRadius of a focus point is left
	onProgress: ((number) -> ())?, -- fraction 0..1 (by voxels), every progressInterval seconds
	progressInterval: number?,
}

-- Runtime fill (yields). Returns (applied ops, failed ops).
function Baker.RunProgressive(ops: { any }, opts: ProgressiveOptions?): (number, number)
	local o: ProgressiveOptions = opts or {}
	local budget = o.frameBudget or 0.008
	local background = o.backgroundBudget or budget * 0.5
	local nearRadius = o.nearRadius or 512
	local focusInterval = o.focusInterval or 0.25
	local moveThreshold = o.focusMoveThreshold or 128
	local focusMinInterval = o.focusMinInterval or 1
	local jumpStuds = o.focusJumpStuds or 200
	local progressInterval = o.progressInterval or 0.5

	local plan = Baker.Plan(ops, { yield = true, frameBudget = budget })
	if o.onPlanned then
		o.onPlanned(plan)
	end
	-- The plan's last slice used this frame; the executor setup and the first priority pass (one
	-- pass over every piece and edge each) get frames of their own.
	task.wait()
	local job = Baker.NewFill(plan)

	local tYield = os.clock()
	local function maybeYield()
		if os.clock() - tYield >= budget then
			task.wait()
			tYield = os.clock()
		end
	end

	-- Priorities are recomputed (one pass over every piece and edge) when a focus point appears,
	-- disappears or jumps (quick travel), and at most once per focusMinInterval for walking.
	local lastFocus: { Vector3 } = {} -- points used by the last recompute
	local lastPolled: { Vector3 } = {} -- points seen by the last poll
	local lastRecompute = -math.huge
	local function refreshFocus()
		if not o.getFocus then
			return
		end
		local ok, points = pcall(o.getFocus)
		if not ok or type(points) ~= "table" then
			return
		end
		local changed = #points ~= #lastFocus or #points ~= #lastPolled
		if not changed then
			for k, p in points do
				if (p - lastPolled[k]).Magnitude > jumpStuds then
					changed = true
					break
				end
			end
		end
		if not changed and os.clock() - lastRecompute >= focusMinInterval then
			for k, p in points do
				if (p - lastFocus[k]).Magnitude > moveThreshold then
					changed = true
					break
				end
			end
		end
		lastPolled = points
		if changed then
			lastFocus = points
			lastRecompute = os.clock()
			job:SetFocus(points)
		end
	end
	maybeYield()
	refreshFocus()
	maybeYield()

	if o.covers then
		for _, c in o.covers do
			job:AddCover(c.min, c.max, c.onClear)
			maybeYield()
		end
	end

	local lastFocusAt = os.clock()
	local lastProgressAt = -math.huge
	local nearDone = false
	while not job:IsDone() do
		local now = os.clock()
		if now - lastFocusAt >= focusInterval then
			lastFocusAt = now
			refreshFocus()
		end
		local spent = os.clock() - now -- a recompute counts against this frame's budget
		local b = budget
		if job:NextPriority() > nearRadius then
			if not nearDone then
				nearDone = true
				if o.onNearDone then
					task.spawn(o.onNearDone)
				end
			end
			if o.isBusy == nil or o.isBusy() then
				b = background
			end
		end
		job:Step(math.max(b - spent, 0))
		if o.onProgress and os.clock() - lastProgressAt >= progressInterval then
			lastProgressAt = os.clock()
			o.onProgress(job:Progress())
		end
		if not job:IsDone() then
			task.wait()
		end
	end
	if not nearDone and o.onNearDone then
		task.spawn(o.onNearDone)
	end
	if o.onProgress then
		o.onProgress(1)
	end
	return job:Result()
end

---------------------------------------------------------------------------------------------------
-- EditorOnly previews
---------------------------------------------------------------------------------------------------

-- Instances that only exist to preview terrain in edit mode: tag "EditorOnly". The builder tags
-- every one of them, so the runtime never walks the map. includeAttributes = true (edit-mode
-- bake only) also scans the map model for the attribute EditorOnly = true.
function Baker.CollectEditorOnly(includeAttributes: boolean?): { Instance }
	local out = {}
	local seen: { [Instance]: boolean } = {}
	for _, inst in CollectionService:GetTagged(EDITOR_ONLY) do
		if inst:IsDescendantOf(workspace) and not seen[inst] then
			seen[inst] = true
			table.insert(out, inst)
		end
	end
	if includeAttributes then
		local root = workspace:FindFirstChild("Gwangalli")
		if root then
			for _, inst in root:GetDescendants() do
				if not seen[inst] and inst:GetAttribute(EDITOR_ONLY) == true then
					seen[inst] = true
					table.insert(out, inst)
				end
			end
		end
	end
	return out
end

function Baker.DestroyEditorOnly(includeAttributes: boolean?): number
	local list = Baker.CollectEditorOnly(includeAttributes)
	local n = 0
	for _, inst in list do
		if inst.Parent then
			pcall(inst.Destroy, inst)
			n += 1
		end
	end
	return n
end

local function withUndo(name: string, fn: () -> ())
	local ChangeHistoryService: any = nil
	pcall(function()
		ChangeHistoryService = game:GetService("ChangeHistoryService")
	end)
	local recording: any = nil
	if ChangeHistoryService then
		pcall(function()
			recording = ChangeHistoryService:TryBeginRecording(name)
		end)
	end
	local ok, err = pcall(fn)
	if ChangeHistoryService and recording then
		pcall(function()
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end)
	end
	if not ok then
		error(err, 0)
	end
end

-- Edit-mode bake. opts.keepEditorOnly = true keeps preview parts; opts.clearFirst = true wipes
-- the existing terrain before filling. Returns (applied, failed).
function Baker.Bake(opts: { keepEditorOnly: boolean?, clearFirst: boolean?, yield: boolean? }?): (number, number)
	local o = opts or {}
	local ops = Baker.LoadOps()
	if not ops then
		return 0, 0
	end
	local applied, failed = 0, 0
	withUndo("Bake Gwangalli terrain", function()
		if o.clearFirst then
			workspace.Terrain:Clear()
		end
		applied, failed = Baker.RunOps(ops, { yield = o.yield == true })
		if not o.keepEditorOnly and applied > 0 and failed <= applied * 0.1 then
			local removed = Baker.DestroyEditorOnly(true)
			if removed > 0 then
				print(string.format("[GwangalliTerrainBaker] removed %d EditorOnly instances", removed))
			end
		end
		if applied > 0 then
			workspace:SetAttribute(BAKED_ATTR, true)
		end
	end)
	print(string.format("[GwangalliTerrainBaker] baked %d terrain ops (%d failed). Save the place to keep it.", applied, failed))
	return applied, failed
end

-- Removes the baked flag and clears all terrain (the runtime will fill it again).
function Baker.Unbake()
	withUndo("Unbake Gwangalli terrain", function()
		workspace.Terrain:Clear()
		workspace:SetAttribute(BAKED_ATTR, nil)
		workspace:SetAttribute(READY_ATTR, nil)
	end)
	print("[GwangalliTerrainBaker] terrain cleared; it will be generated at runtime again.")
end

-- World-space bounding box of every Water op (rotation-aware), padded by 8 studs; nil when the
-- ops are missing or contain no water.
function Baker.WaterBounds(ops: { any }?): (Vector3?, Vector3?)
	local list = ops or Baker.LoadOps()
	if not list then
		return nil, nil
	end
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local found = false
	for _, op in list do
		if type(op) == "table" then
			local kind = op[1]
			local lo, hi = nil, nil
			if (kind == "Block" or kind == "Wedge") and op[4] == "Water" and typeof(op[2]) == "CFrame" and typeof(op[3]) == "Vector3" then
				local cf, s = op[2], op[3]
				local e = boxHalfExtents(cf, s)
				lo, hi = cf.Position - e, cf.Position + e
			elseif kind == "Ball" and op[4] == "Water" and typeof(op[2]) == "Vector3" and type(op[3]) == "number" then
				local e = Vector3.one * op[3]
				lo, hi = op[2] - e, op[2] + e
			elseif kind == "Cylinder" and op[5] == "Water" and typeof(op[2]) == "CFrame" and type(op[3]) == "number" and type(op[4]) == "number" then
				local e = Vector3.one * math.max(op[3] / 2, op[4])
				lo, hi = op[2].Position - e, op[2].Position + e
			end
			if lo and hi then
				found = true
				minX, minY, minZ = math.min(minX, lo.X), math.min(minY, lo.Y), math.min(minZ, lo.Z)
				maxX, maxY, maxZ = math.max(maxX, hi.X), math.max(maxY, hi.Y), math.max(maxZ, hi.Z)
			end
		end
	end
	if not found then
		return nil, nil
	end
	return Vector3.new(minX - 8, minY - 8, minZ - 8), Vector3.new(maxX + 8, maxY + 8, maxZ + 8)
end

-- Replaces Water voxels with Air inside the water ops' bounds (or Baker.Extents, or
-- opts.min/opts.max), in chunks small enough for Terrain:ReplaceMaterial. Handy for editing
-- the sea bed.
function Baker.ClearWater(opts: { min: Vector3?, max: Vector3?, yield: boolean? }?): number
	local o = opts or {}
	local lo, hi = o.min, o.max
	if not lo or not hi then
		local wlo, whi = Baker.WaterBounds()
		lo = lo or wlo or Baker.Extents.min
		hi = hi or whi or Baker.Extents.max
	end
	local lo3, hi3 = lo :: Vector3, hi :: Vector3
	lo = Vector3.new(math.min(lo3.X, hi3.X), math.min(lo3.Y, hi3.Y), math.min(lo3.Z, hi3.Z))
	hi = Vector3.new(math.max(lo3.X, hi3.X), math.max(lo3.Y, hi3.Y), math.max(lo3.Z, hi3.Z))
	local terrain = workspace.Terrain
	local CHUNK = 512
	local calls = 0
	withUndo("Clear Gwangalli water", function()
		local x = lo.X
		while x < hi.X do
			local z = lo.Z
			while z < hi.Z do
				local y = lo.Y
				while y < hi.Y do
					local region = Region3.new(
						Vector3.new(x, y, z),
						Vector3.new(math.min(x + CHUNK, hi.X), math.min(y + CHUNK, hi.Y), math.min(z + CHUNK, hi.Z))
					):ExpandToGrid(4)
					local ok, err = pcall(function()
						terrain:ReplaceMaterial(region, 4, Enum.Material.Water, Enum.Material.Air)
					end)
					if not ok then
						warn("[GwangalliTerrainBaker] ReplaceMaterial failed: " .. tostring(err))
					end
					calls += 1
					y += CHUNK
				end
				z += CHUNK
				if o.yield then
					task.wait()
				end
			end
			x += CHUNK
		end
	end)
	print(string.format("[GwangalliTerrainBaker] cleared water in %d chunks", calls))
	return calls
end

return Baker
