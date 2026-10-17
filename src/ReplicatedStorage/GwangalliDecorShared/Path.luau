--!strict
-- GwangalliDecorShared/Path: keeps doors and the life-game fixtures (침대 · 냉장고 · 샤워 ...) reachable.
-- A level of the home is rasterised at Config.PATH_CELL; walls, fixed furniture, slot envelopes and
-- low placed pieces block cells (grown by the character radius). BFS from the 현관 (level 1) or the
-- top of the stairs (upper level). A target that was reachable before the change and is not after
-- it fails the placement with its label.
--   Path.check(U, idx, extra, ignore, level) -> (ok, label?)

local Config = require(script.Parent:WaitForChild("Config"))
local Geometry = require(script.Parent:WaitForChild("Geometry"))

local Path = {}

local function grid(U: any, level: number): any?
	U.pathCache = U.pathCache or {}
	local g = U.pathCache[level]
	if g then
		return g
	end
	local lv = U.levels[level]
	if not lv then
		return nil
	end
	local cell = Config.PATH_CELL
	local lo, hi = Vector3.new(math.huge, 0, math.huge), Vector3.new(-math.huge, 0, -math.huge)
	local floors = {}
	for _, f in U.floors do
		if f.level == level then
			table.insert(floors, f)
			lo = Vector3.new(math.min(lo.X, f.box.lo.X), 0, math.min(lo.Z, f.box.lo.Z))
			hi = Vector3.new(math.max(hi.X, f.box.hi.X), 0, math.max(hi.Z, f.box.hi.Z))
		end
	end
	if #floors == 0 then
		return nil
	end
	local nx = math.max(1, math.ceil((hi.X - lo.X) / cell))
	local nz = math.max(1, math.ceil((hi.Z - lo.Z) / cell))
	if nx * nz > 40000 then
		return nil -- never on the five templates; protects against odd custom homes
	end
	g = { level = level, x0 = lo.X, z0 = lo.Z, nx = nx, nz = nz, cell = cell, y = lv.y, floor = {}, block = {}, force = {} }
	local function idx(ix: number, iz: number): number
		return iz * nx + ix
	end
	g.idx = idx
	-- floor mask
	for iz = 0, nz - 1 do
		for ix = 0, nx - 1 do
			local p = Vector3.new(lo.X + (ix + 0.5) * cell, 0, lo.Z + (iz + 0.5) * cell)
			for _, f in floors do
				if Geometry.pointInXZ(f.box, p, 0) then
					g.floor[idx(ix, iz)] = true
					break
				end
			end
		end
	end
	local function mark(b: any, pad: number, into: { [number]: boolean })
		local blo, bhi = b.lo, b.hi
		if not blo then
			blo, bhi = Geometry.aabb(b)
		end
		local ix0 = math.max(0, math.floor((blo.X - pad - lo.X) / cell))
		local ix1 = math.min(nx - 1, math.floor((bhi.X + pad - lo.X) / cell))
		local iz0 = math.max(0, math.floor((blo.Z - pad - lo.Z) / cell))
		local iz1 = math.min(nz - 1, math.floor((bhi.Z + pad - lo.Z) / cell))
		for iz = iz0, iz1 do
			for ix = ix0, ix1 do
				local p = Vector3.new(lo.X + (ix + 0.5) * cell, 0, lo.Z + (iz + 0.5) * cell)
				if Geometry.pointInXZ(b, p, pad) then
					into[idx(ix, iz)] = true
				end
			end
		end
	end
	g.mark = mark
	local r = Config.PATH_RADIUS
	local yLo, yHi = lv.y + 0.35, lv.y + 3
	local function blocks(b: any): boolean
		return b.hi.Y > yLo and b.lo.Y < yHi
	end
	for _, w in U.walls do
		if blocks(w.box) then
			mark(w.box, r, g.block)
		end
	end
	for _, s in U.solids do
		if blocks(s.box) and not s.stair then
			mark(s.box, r, g.block)
		end
	end
	for _, s in U.slots do
		if s.category ~= "rug" and s.category ~= "art" and blocks(s.box) then
			mark(s.box, r * 0.6, g.block)
		end
	end
	-- doorways are always open; targets
	g.targets = {}
	for _, k in U.keeps do
		local ky = k.box.lo.Y
		if k.code == "door" and math.abs(ky - lv.y) < 2 then
			mark(k.box, 0, g.force)
			table.insert(g.targets, k)
		elseif k.target and math.abs(k.box.cf.Position.Y - (lv.y + 2)) < 3.5 then
			table.insert(g.targets, k)
		end
	end
	-- starts
	g.starts = {}
	if level == 1 then
		local sp = U.spawn
		local ix = math.floor((sp.X - lo.X) / cell)
		local iz = math.floor((sp.Z - lo.Z) / cell)
		if ix >= 0 and ix < nx and iz >= 0 and iz < nz then
			table.insert(g.starts, idx(ix, iz))
		end
	elseif U.stair then
		local st: any = {}
		mark(Geometry.inflate(U.stair, 1.5, 0, 1.5), 0, st)
		for k in st do
			if g.floor[k] then
				table.insert(g.starts, k)
			end
		end
	end
	U.pathCache[level] = g
	return g
end

local function reach(g: any, dyn: { [number]: boolean }): { [number]: boolean }
	local nx, nz = g.nx, g.nz
	local seen: { [number]: boolean } = {}
	local q: { number } = {}
	local function open(k: number): boolean
		if not g.floor[k] then
			return false
		end
		if g.force[k] then
			return true
		end
		return not g.block[k] and not dyn[k]
	end
	for _, s in g.starts do
		-- the start cell itself may sit next to a wall: open its neighbourhood
		if g.floor[s] and not seen[s] then
			seen[s] = true
			table.insert(q, s)
		end
	end
	local head = 1
	while head <= #q do
		local k = q[head]
		head += 1
		local ix, iz = k % nx, k // nx
		local nb = { { ix + 1, iz }, { ix - 1, iz }, { ix, iz + 1 }, { ix, iz - 1 } }
		for _, n in nb do
			local x, z = n[1], n[2]
			if x >= 0 and x < nx and z >= 0 and z < nz then
				local kk = z * nx + x
				if not seen[kk] and open(kk) then
					seen[kk] = true
					table.insert(q, kk)
				end
			end
		end
	end
	return seen
end

local function targetHit(g: any, t: any, seen: { [number]: boolean }): boolean
	local cells: any = {}
	g.mark(t.box, 0.25, cells)
	for k in cells do
		if seen[k] then
			return true
		end
	end
	return false
end

local function dynamicBlocks(g: any, idx: any, ignore: { [number]: boolean }?, extra: { any }?): { [number]: boolean }
	local dyn: { [number]: boolean } = {}
	local r = Config.PATH_RADIUS
	local yLo, yHi = g.y + 0.35, g.y + 3
	local function add(e: any)
		if e.kind == "rug" or e.kind == "wall" or e.kind == "ceiling" then
			return
		end
		for _, b in e.boxes do
			if b.hi.Y > yLo and b.lo.Y < yHi then
				g.mark(b, r, dyn)
			end
		end
	end
	for u, e in idx.items do
		if not (ignore and ignore[u]) then
			add(e)
		end
	end
	if extra then
		for _, e in extra do
			add(e)
		end
	end
	return dyn
end

-- extra = the candidate entries (unit-frame boxes), ignore = uids being moved
function Path.check(U: any, idx: any, extra: { any }, ignore: { [number]: boolean }?, level: number): (boolean, string?)
	if not Config.PATH_CHECK then
		return true, nil
	end
	local g = grid(U, level)
	if not g or #g.starts == 0 or #g.targets == 0 then
		return true, nil
	end
	-- before (cached per index version)
	g.before = g.before or {}
	local key = tostring(idx.version) .. ":" .. (if ignore then "i" else "-")
	local before = g.before[key]
	if not before then
		local seen = reach(g, dynamicBlocks(g, idx, nil, nil))
		before = {}
		for i, t in g.targets do
			before[i] = targetHit(g, t, seen)
		end
		g.before = { [key] = before }
	end
	local seen = reach(g, dynamicBlocks(g, idx, ignore, extra))
	for i, t in g.targets do
		if before[i] and not targetHit(g, t, seen) then
			return false, t.labelTo or t.label
		end
	end
	return true, nil
end

function Path.invalidate(U: any)
	U.pathCache = nil
end

return Path
