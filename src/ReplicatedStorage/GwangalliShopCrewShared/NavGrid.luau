-- GwangalliShopCrewShared/NavGrid: the pure grid planner the shop crew walks with (no instances, no services).
-- The server rasterises a shop's furniture (part boxes in the shop's local frame, inflated by the agent radius)
-- into a grid, then asks for paths between spots. Deterministic and cheap (a 40 x 20 stud shop at 0.5 studs is
-- 3,200 cells; one path is well under a millisecond), so it also runs in the Luau CLI tests.
--   local g = NavGrid.new(minX, minZ, maxX, maxZ, cell)
--   g:block(minX, minZ, maxX, maxZ) / g:open(...)   cells whose centre lies inside the rectangle
--   g:finalize()                                    clearance + connected components (call after editing)
--   g:free(x, z) -> bool    g:comp(x, z) -> id (0 = blocked)    g:clearance(x, z) -> cells to the nearest wall
--   g:nearestFree(x, z, maxR, comp?, minClear?) -> (x, z)?   the closest free cell centre (rings)
--   g:los(ax, az, bx, bz) -> bool       straight walk stays on free cells
--   g:path(ax, az, bx, bz, comp?) -> { {x, z} }?   A* (8-way, no corner cutting, soft wall cost) + string pulling
--   g:pathLength(pts) -> studs
-- Coordinates are the caller's (the shop's local x / z); every returned point is a cell centre except the
-- exact start / goal when they are free.

local NavGrid = {}
NavGrid.__index = NavGrid

local SQRT2 = math.sqrt(2)

export type Grid = {
	x0: number,
	z0: number,
	nx: number,
	nz: number,
	cell: number,
	blk: { number },
	clr: { number },
	cmp: { number },
	ready: boolean,
}

function NavGrid.new(minX: number, minZ: number, maxX: number, maxZ: number, cell: number?): any
	local c = cell or 0.5
	local nx = math.max(1, math.ceil((maxX - minX) / c))
	local nz = math.max(1, math.ceil((maxZ - minZ) / c))
	local n = nx * nz
	local self = setmetatable({
		x0 = minX,
		z0 = minZ,
		nx = nx,
		nz = nz,
		cell = c,
		blk = table.create(n, 0),
		clr = table.create(n, 0),
		cmp = table.create(n, 0),
		ready = false,
	}, NavGrid)
	return self
end

-- cell index helpers ------------------------------------------------------------------------------
function NavGrid:cellOf(x: number, z: number): (number, number)
	return math.floor((x - self.x0) / self.cell), math.floor((z - self.z0) / self.cell)
end

function NavGrid:center(ix: number, iz: number): (number, number)
	return self.x0 + (ix + 0.5) * self.cell, self.z0 + (iz + 0.5) * self.cell
end

function NavGrid:inside(ix: number, iz: number): boolean
	return ix >= 0 and iz >= 0 and ix < self.nx and iz < self.nz
end

function NavGrid:idx(ix: number, iz: number): number
	return iz * self.nx + ix + 1
end

function NavGrid:isBlocked(ix: number, iz: number): boolean
	if ix < 0 or iz < 0 or ix >= self.nx or iz >= self.nz then
		return true
	end
	return self.blk[iz * self.nx + ix + 1] ~= 0
end

local function fillRect(self: any, minX: number, minZ: number, maxX: number, maxZ: number, v: number)
	if maxX < minX then
		minX, maxX = maxX, minX
	end
	if maxZ < minZ then
		minZ, maxZ = maxZ, minZ
	end
	local c = self.cell
	-- cells whose centre lies inside [min, max]
	local ix0 = math.max(0, math.ceil((minX - self.x0) / c - 0.5))
	local ix1 = math.min(self.nx - 1, math.floor((maxX - self.x0) / c - 0.5))
	local iz0 = math.max(0, math.ceil((minZ - self.z0) / c - 0.5))
	local iz1 = math.min(self.nz - 1, math.floor((maxZ - self.z0) / c - 0.5))
	if ix1 < ix0 or iz1 < iz0 then
		return 0
	end
	local nx = self.nx
	local blk = self.blk
	for iz = iz0, iz1 do
		local row = iz * nx + 1
		for ix = ix0, ix1 do
			blk[row + ix] = v
		end
	end
	self.ready = false
	return (ix1 - ix0 + 1) * (iz1 - iz0 + 1)
end

function NavGrid:block(minX: number, minZ: number, maxX: number, maxZ: number): number
	return fillRect(self, minX, minZ, maxX, maxZ, 1)
end

function NavGrid:open(minX: number, minZ: number, maxX: number, maxZ: number): number
	return fillRect(self, minX, minZ, maxX, maxZ, 0)
end

-- block every cell outside the rectangle (the shop's walls / the door strip are cut back open by the caller)
function NavGrid:blockOutside(minX: number, minZ: number, maxX: number, maxZ: number)
	local c = self.cell
	for iz = 0, self.nz - 1 do
		local z = self.z0 + (iz + 0.5) * c
		for ix = 0, self.nx - 1 do
			local x = self.x0 + (ix + 0.5) * c
			if x < minX or x > maxX or z < minZ or z > maxZ then
				self.blk[iz * self.nx + ix + 1] = 1
			end
		end
	end
	self.ready = false
end

-- clearance (4-way BFS distance to the nearest blocked cell, capped) + connected components (8-way, no
-- corner cutting, the same moves the planner makes)
function NavGrid:finalize()
	local nx, nz = self.nx, self.nz
	local n = nx * nz
	local blk, clr, cmp = self.blk, self.clr, self.cmp
	local CAP = 6
	local queue = table.create(n)
	local head, tail = 1, 0
	for i = 1, n do
		if blk[i] ~= 0 then
			clr[i] = 0
			tail += 1
			queue[tail] = i
		else
			clr[i] = CAP
		end
	end
	-- the grid edge counts as a wall
	for iz = 0, nz - 1 do
		for ix = 0, nx - 1 do
			if ix == 0 or iz == 0 or ix == nx - 1 or iz == nz - 1 then
				local i = iz * nx + ix + 1
				if blk[i] == 0 and clr[i] > 1 then
					clr[i] = 1
					tail += 1
					queue[tail] = i
				end
			end
		end
	end
	while head <= tail do
		local i = queue[head]
		head += 1
		local d = clr[i] + 1
		if d < CAP then
			local i0 = i - 1
			local ix, iz = i0 % nx, i0 // nx
			if ix > 0 and clr[i - 1] > d then
				clr[i - 1] = d
				tail += 1
				queue[tail] = i - 1
			end
			if ix < nx - 1 and clr[i + 1] > d then
				clr[i + 1] = d
				tail += 1
				queue[tail] = i + 1
			end
			if iz > 0 and clr[i - nx] > d then
				clr[i - nx] = d
				tail += 1
				queue[tail] = i - nx
			end
			if iz < nz - 1 and clr[i + nx] > d then
				clr[i + nx] = d
				tail += 1
				queue[tail] = i + nx
			end
		end
	end
	-- components
	for i = 1, n do
		cmp[i] = 0
	end
	local nextId = 0
	local sizes = {}
	for start = 1, n do
		if blk[start] == 0 and cmp[start] == 0 then
			nextId += 1
			local size = 0
			head, tail = 1, 1
			queue[1] = start
			cmp[start] = nextId
			while head <= tail do
				local i = queue[head]
				head += 1
				size += 1
				local i0 = i - 1
				local ix, iz = i0 % nx, i0 // nx
				for dz = -1, 1 do
					for dx = -1, 1 do
						if dx ~= 0 or dz ~= 0 then
							local jx, jz = ix + dx, iz + dz
							if jx >= 0 and jz >= 0 and jx < nx and jz < nz then
								local j = jz * nx + jx + 1
								if blk[j] == 0 and cmp[j] == 0 then
									local okMove = true
									if dx ~= 0 and dz ~= 0 then
										okMove = blk[iz * nx + jx + 1] == 0 and blk[jz * nx + ix + 1] == 0
									end
									if okMove then
										cmp[j] = nextId
										tail += 1
										queue[tail] = j
									end
								end
							end
						end
					end
				end
			end
			sizes[nextId] = size
		end
	end
	self.sizes = sizes
	self.ready = true
end

function NavGrid:free(x: number, z: number): boolean
	local ix, iz = self:cellOf(x, z)
	return not self:isBlocked(ix, iz)
end

function NavGrid:comp(x: number, z: number): number
	if not self.ready then
		self:finalize()
	end
	local ix, iz = self:cellOf(x, z)
	if not self:inside(ix, iz) then
		return 0
	end
	return self.cmp[iz * self.nx + ix + 1]
end

function NavGrid:clearance(x: number, z: number): number
	if not self.ready then
		self:finalize()
	end
	local ix, iz = self:cellOf(x, z)
	if not self:inside(ix, iz) then
		return 0
	end
	return self.clr[iz * self.nx + ix + 1]
end

-- the largest component's id (the shop floor)
function NavGrid:mainComp(): number
	if not self.ready then
		self:finalize()
	end
	local best, bestN = 0, 0
	for id, n in self.sizes or {} do
		if n > bestN then
			best, bestN = id, n
		end
	end
	return best
end

-- closest free cell centre to (x, z) within maxR studs (optionally in component `comp`, optionally with at
-- least `minClear` cells of clearance); ties go to the larger clearance
function NavGrid:nearestFree(x: number, z: number, maxR: number?, comp: number?, minClear: number?): (number?, number?)
	if not self.ready then
		self:finalize()
	end
	local cx, cz = self:cellOf(x, z)
	local rCells = math.ceil((maxR or 3) / self.cell)
	local best, bestD, bestC = nil, math.huge, -1
	local nx = self.nx
	for r = 0, rCells do
		for iz = cz - r, cz + r do
			for ix = cx - r, cx + r do
				if (math.abs(ix - cx) == r or math.abs(iz - cz) == r) and self:inside(ix, iz) then
					local i = iz * nx + ix + 1
					if self.blk[i] == 0 and (not comp or self.cmp[i] == comp) and self.clr[i] >= (minClear or 0) then
						local px, pz = self:center(ix, iz)
						local d = (px - x) * (px - x) + (pz - z) * (pz - z)
						if d < bestD - 1e-6 or (math.abs(d - bestD) <= 1e-6 and self.clr[i] > bestC) then
							best, bestD, bestC = i, d, self.clr[i]
						end
					end
				end
			end
		end
		-- a ring further out can still be closer in true distance only by < one cell: finish one more ring
		if best and math.sqrt(bestD) < (r - 1) * self.cell then
			break
		end
	end
	if not best then
		return nil, nil
	end
	if math.sqrt(bestD) > (maxR or 3) + self.cell then
		return nil, nil
	end
	local i0 = best - 1
	return self:center(i0 % nx, i0 // nx)
end

-- straight line over free cells only (sampled at a quarter cell)
function NavGrid:los(ax: number, az: number, bx: number, bz: number): boolean
	local dx, dz = bx - ax, bz - az
	local len = math.sqrt(dx * dx + dz * dz)
	local steps = math.max(1, math.ceil(len / (self.cell * 0.25)))
	for s = 0, steps do
		local t = s / steps
		local ix, iz = self:cellOf(ax + dx * t, az + dz * t)
		if self:isBlocked(ix, iz) then
			return false
		end
	end
	return true
end

-- binary heap on f-cost ------------------------------------------------------------------------------
local function heapPush(h: { number }, f: { number }, i: number)
	table.insert(h, i)
	local k = #h
	while k > 1 do
		local p = k // 2
		if f[h[p]] <= f[h[k]] then
			break
		end
		h[p], h[k] = h[k], h[p]
		k = p
	end
end

local function heapPop(h: { number }, f: { number }): number?
	local n = #h
	if n == 0 then
		return nil
	end
	local top = h[1]
	h[1] = h[n]
	h[n] = nil
	n -= 1
	local k = 1
	while true do
		local l, r = k * 2, k * 2 + 1
		local m = k
		if l <= n and f[h[l]] < f[h[m]] then
			m = l
		end
		if r <= n and f[h[r]] < f[h[m]] then
			m = r
		end
		if m == k then
			break
		end
		h[m], h[k] = h[k], h[m]
		k = m
	end
	return top
end

local WALL_COST = { [0] = 99, [1] = 0.9, [2] = 0.35, [3] = 0.1 }

function NavGrid:path(ax: number, az: number, bx: number, bz: number, comp: number?): { { number } }?
	if not self.ready then
		self:finalize()
	end
	local nx, nz = self.nx, self.nz
	local blk, clr, cmpT = self.blk, self.clr, self.cmp
	-- endpoints: snap to free cells (the caller's spots are normally free already)
	local sx, sz = ax, az
	if not self:free(ax, az) then
		local x, z = self:nearestFree(ax, az, 2.5, comp)
		if not x then
			return nil
		end
		sx, sz = x :: number, z :: number
	end
	local gx, gz = bx, bz
	if not self:free(bx, bz) then
		local x, z = self:nearestFree(bx, bz, 2.5, comp)
		if not x then
			return nil
		end
		gx, gz = x :: number, z :: number
	end
	local six, siz = self:cellOf(sx, sz)
	local gix, giz = self:cellOf(gx, gz)
	local si = siz * nx + six + 1
	local gi = giz * nx + gix + 1
	if cmpT[si] ~= cmpT[gi] or cmpT[si] == 0 then
		return nil
	end
	local pts: { { number } }
	if si == gi then
		pts = { { ax, az }, { bx, bz } }
	else
		local g: { number } = {}
		local f: { number } = {}
		local from: { number } = {}
		local closed: { [number]: boolean } = {}
		local open: { number } = {}
		local function h(i: number): number
			local i0 = i - 1
			local dx = math.abs(i0 % nx - gix)
			local dz = math.abs(i0 // nx - giz)
			return (dx + dz) + (SQRT2 - 2) * math.min(dx, dz)
		end
		g[si] = 0
		f[si] = h(si)
		heapPush(open, f, si)
		local found = false
		local guard = 0
		while true do
			local i = heapPop(open, f)
			if not i then
				break
			end
			guard += 1
			if guard > nx * nz * 2 then
				break
			end
			if i == gi then
				found = true
				break
			end
			if not closed[i] then
				closed[i] = true
				local i0 = i - 1
				local ix, iz = i0 % nx, i0 // nx
				for dz = -1, 1 do
					for dx = -1, 1 do
						if dx ~= 0 or dz ~= 0 then
							local jx, jz = ix + dx, iz + dz
							if jx >= 0 and jz >= 0 and jx < nx and jz < nz then
								local j = jz * nx + jx + 1
								if blk[j] == 0 and not closed[j] then
									local okMove = true
									local step = 1
									if dx ~= 0 and dz ~= 0 then
										okMove = blk[iz * nx + jx + 1] == 0 and blk[jz * nx + ix + 1] == 0
										step = SQRT2
									end
									if okMove then
										local ng = g[i] + step * (1 + (WALL_COST[clr[j]] or 0))
										if g[j] == nil or ng < g[j] then
											g[j] = ng
											f[j] = ng + h(j)
											from[j] = i
											heapPush(open, f, j)
										end
									end
								end
							end
						end
					end
				end
			end
		end
		if not found then
			return nil
		end
		local cells = {}
		local cur: number? = gi
		while cur do
			table.insert(cells, 1, cur)
			cur = from[cur]
		end
		pts = {}
		for k, i in cells do
			local i0 = i - 1
			local x, z = self:center(i0 % nx, i0 // nx)
			if k == 1 then
				x, z = sx, sz
			elseif k == #cells then
				x, z = gx, gz
			end
			table.insert(pts, { x, z })
		end
		-- exact endpoints when they were free
		if sx ~= ax or sz ~= az then
			table.insert(pts, 1, { ax, az })
		end
		if gx ~= bx or gz ~= bz then
			table.insert(pts, { bx, bz })
		end
	end
	return self:smooth(pts)
end

-- string pulling: keep only the corners a straight walk cannot skip (free-cell line of sight)
function NavGrid:smooth(pts: { { number } }): { { number } }
	if #pts <= 2 then
		return pts
	end
	local out = { pts[1] }
	local i = 1
	while i < #pts do
		local j = #pts
		while j > i + 1 do
			if self:los(pts[i][1], pts[i][2], pts[j][1], pts[j][2]) then
				break
			end
			j -= 1
		end
		table.insert(out, pts[j])
		i = j
	end
	return out
end

function NavGrid.pathLength(_self: any, pts: { { number } }): number
	local d = 0
	for k = 2, #pts do
		local dx, dz = pts[k][1] - pts[k - 1][1], pts[k][2] - pts[k - 1][2]
		d += math.sqrt(dx * dx + dz * dz)
	end
	return d
end

-- debug: ASCII map ("#" blocked, "." free, digits = marks)
function NavGrid:ascii(marks: { { number } }?): string
	local rows = {}
	local mark: { [number]: string } = {}
	for k, m in marks or {} do
		local ix, iz = self:cellOf(m[1], m[2])
		if self:inside(ix, iz) then
			mark[iz * self.nx + ix + 1] = string.sub(tostring(k % 10), 1, 1)
		end
	end
	for iz = self.nz - 1, 0, -1 do
		local row = table.create(self.nx)
		for ix = 0, self.nx - 1 do
			local i = iz * self.nx + ix + 1
			row[ix + 1] = mark[i] or (if self.blk[i] ~= 0 then "#" else ".")
		end
		table.insert(rows, table.concat(row))
	end
	return table.concat(rows, "\n")
end

return NavGrid
