-- GwangalliStreetLife/NavWorld: pedestrian-graph queries for the street life (GwangalliNav):
-- node / edge access, the nodes around the player, lazily computed "flow fields" (next hop toward an
-- area, like Nav.ped.toClub for the club), direction-persistent random walks inside an area, POIs by
-- kind / tag with occupancy, crosswalk signal states and the citizen area anchors.
-- Every query is allocation-light; flow fields are computed a few hundred nodes per frame
-- (NavWorld.stepFlows) so no single frame pays for a whole Dijkstra.

local CollectionService = game:GetService("CollectionService")

local W = {}

local ctx: any
local Nav: any
local Citizens: any
local Shared: any
local pos: { Vector3 } = {}
local adj: { { number } } = {}
local area: { number } = {}
local N = 0
local E: { number } = {}
local ekind: { number } = {}
local ewidth: { number } = {}
local ecost: { number } = {}
local QUEUE = -1
local SAND = -1
local XWALK, XING = -1, -1

W.pos = pos
W.adj = adj
W.area = area

local CELL = 64
local function gkey(x: number, z: number): number
	return (math.floor(x / CELL) + 512) * 2048 + (math.floor(z / CELL) + 512)
end

-------------------------------------------------------------------------------------------------
-- POIs
-------------------------------------------------------------------------------------------------
local poiPos: { Vector3 } = {}
local poiYaw: { number } = {}
local poiKind: { number } = {}
local poiTags: { number } = {}
local poiNode: { number } = {}
local poiCap: { number } = {}
local poiUse: { number } = {}
local poiGap: { number } = {} -- studs between the users of one POI
local poiGrid: { [number]: { number } } = {}
local nodeGrid: any = nil
W.poiPos, W.poiYaw, W.poiKind, W.poiTags, W.poiNode, W.poiCap, W.poiUse = poiPos, poiYaw, poiKind, poiTags, poiNode, poiCap, poiUse

function W.init(context: any)
	ctx = context
	Nav = ctx.Nav
	Citizens = ctx.Citizens
	Shared = ctx.Shared
	local c = Nav.decode()
	nodeGrid = c.grid
	N = Nav.ped.n
	for i = 1, N do
		pos[i] = c.pos[i]
		adj[i] = c.adj[i]
		area[i] = Nav.ped.area[i]
	end
	E = Nav.ped.edges
	QUEUE = Nav.KIND.queue or -1
	SAND = Nav.KIND.sand or -1
	XWALK = Nav.KIND.xwalk or -1
	XING = Nav.KIND.xing or -1
	local cost = {}
	for name, code in Nav.KIND do
		cost[code] = Nav.KIND_COST[name] or 1
	end
	for e = 1, #E // 4 do
		local k = (e - 1) * 4
		local a, b = E[k + 1], E[k + 2]
		ekind[e] = E[k + 4]
		ewidth[e] = E[k + 3]
		ecost[e] = (pos[a] - pos[b]).Magnitude * (cost[E[k + 4]] or 1)
	end
	local P = Nav.poi
	local n = #P // 9
	for i = 1, n do
		local k = (i - 1) * 9
		poiPos[i] = Vector3.new(P[k + 1], P[k + 2], P[k + 3])
		poiYaw[i] = math.rad(P[k + 4])
		poiKind[i] = P[k + 5]
		poiTags[i] = P[k + 6]
		poiNode[i] = P[k + 7]
		poiCap[i] = math.max(1, P[k + 8])
		poiUse[i] = 0
		if P[k + 7] > 0 then
			local key = gkey(P[k + 1], P[k + 3])
			local cell = poiGrid[key]
			if not cell then
				cell = {}
				poiGrid[key] = cell
			end
			table.insert(cell, i)
		end
	end
	-- seats: the block rigs are ~4 studs wide (arms included), so people sit / lie SEAT_GAP apart and
	-- a bench takes at most 2 of them, a towel spot 2 (a family picnic mat 3)
	local benchK, towelK = Nav.POI_KIND and Nav.POI_KIND.bench, Nav.POI_KIND and Nav.POI_KIND.towel
	for i = 1, n do
		local kind = poiKind[i]
		if kind == benchK then
			poiCap[i] = math.min(poiCap[i], 2)
			poiGap[i] = 3.0
		elseif kind == towelK then
			poiCap[i] = math.min(poiCap[i], 3)
			poiGap[i] = 3.8
		else
			poiGap[i] = 2.6
		end
	end
	W.n = N
	W.poiCount = n
end

-------------------------------------------------------------------------------------------------
-- Nodes / edges
-------------------------------------------------------------------------------------------------
function W.edgeBetween(a: number, b: number): number?
	local l = adj[a]
	if not l then
		return nil
	end
	for k = 1, #l, 2 do
		if l[k] == b then
			return l[k + 1]
		end
	end
	return nil
end

function W.edgeKind(e: number): number
	return ekind[e] or 0
end

function W.edgeWidth(e: number): number
	return ewidth[e] or 3
end

function W.isCrossingKind(k: number): boolean
	return k == XWALK or k == XING
end

function W.isSand(k: number): boolean
	return k == SAND
end

function W.areaIndex(name: string): number?
	for i, n in Nav.AREA do
		if n == name then
			return i
		end
	end
	return nil
end

local setCache: { [any]: { [number]: boolean } } = {}
-- { "promenade", "beach" } -> { [areaIndex] = true } (cached per list table)
function W.areaSet(list: { string }?): { [number]: boolean }?
	if not list then
		return nil
	end
	local s = setCache[list]
	if s then
		return s
	end
	s = {}
	for _, name in list do
		local i = W.areaIndex(name)
		if i then
			s[i] = true
		end
	end
	setCache[list] = s
	return s
end

function W.nearest(p: Vector3, maxDist: number?, allow: { [number]: boolean }?): number?
	local r = maxDist or 64
	local best, bestD = nil, r * r
	local c0x, c0z = math.floor((p.X - r) / CELL), math.floor((p.Z - r) / CELL)
	local c1x, c1z = math.floor((p.X + r) / CELL), math.floor((p.Z + r) / CELL)
	for cx = c0x, c1x do
		for cz = c0z, c1z do
			local cell = nodeGrid[(cx + 512) * 2048 + (cz + 512)]
			if cell then
				for _, i in cell do
					if not allow or allow[area[i]] then
						local q = pos[i]
						local dx, dy, dz = q.X - p.X, (q.Y - p.Y) * 2, q.Z - p.Z
						local d = dx * dx + dy * dy + dz * dz
						if d < bestD then
							best, bestD = i, d
						end
					end
				end
			end
		end
	end
	return best
end

-- Nodes within `radius` of `center` (flat), refreshed only when the centre moved > 18 studs.
local nearList: { number } = {}
local nearCenter: Vector3? = nil
local nearRadius = 0
function W.nearNodes(center: Vector3, radius: number): { number }
	if nearCenter and radius == nearRadius and (Vector3.new(center.X - nearCenter.X, 0, center.Z - nearCenter.Z)).Magnitude < 18 then
		return nearList
	end
	nearCenter = center
	nearRadius = radius
	table.clear(nearList)
	local r = radius + 18
	local r2 = r * r
	local c0x, c0z = math.floor((center.X - r) / CELL), math.floor((center.Z - r) / CELL)
	local c1x, c1z = math.floor((center.X + r) / CELL), math.floor((center.Z + r) / CELL)
	for cx = c0x, c1x do
		for cz = c0z, c1z do
			local cell = nodeGrid[(cx + 512) * 2048 + (cz + 512)]
			if cell then
				for _, i in cell do
					local q = pos[i]
					local dx, dz = q.X - center.X, q.Z - center.Z
					if dx * dx + dz * dz <= r2 and math.abs(q.Y - center.Y) < 40 then
						nearList[#nearList + 1] = i
					end
				end
			end
		end
	end
	return nearList
end

-- The walkable point closest to p on the level of levelY (within the clear width of a graph edge,
-- keepOff studs short of p): where somebody on that level stands to watch something at p (the
-- busker on the sand seen from the promenade edge above, ...). nil when no edge is near.
function W.closestWalkable(p: Vector3, levelY: number, maxR: number, keepOff: number): Vector3?
	local q0 = Vector3.new(p.X, levelY, p.Z)
	local n = W.nearest(q0, maxR)
	if not n or math.abs(pos[n].Y - levelY) > 2.5 then
		return nil
	end
	local best, bd = nil, math.huge
	local a = pos[n]
	local l = adj[n]
	for k = 1, #l, 2 do
		local m, e = l[k], l[k + 1]
		local b = pos[m]
		if math.abs(b.Y - levelY) < 2.5 and ekind[e] ~= QUEUE then
			local abx, abz = b.X - a.X, b.Z - a.Z
			local len2 = abx * abx + abz * abz
			local t = if len2 > 1e-6 then math.clamp(((p.X - a.X) * abx + (p.Z - a.Z) * abz) / len2, 0, 1) else 0
			local qx, qz = a.X + abx * t, a.Z + abz * t
			local lx, lz = p.X - qx, p.Z - qz
			local d = math.sqrt(lx * lx + lz * lz)
			local allowed = math.max(0, (ewidth[e] or 3) * 0.5 - 1.2)
			local step = math.min(allowed, math.max(0, d - keepOff))
			local sx, sz = qx, qz
			if d > 0.01 then
				sx, sz = qx + lx / d * step, qz + lz / d * step
			end
			local rem = math.sqrt((p.X - sx) ^ 2 + (p.Z - sz) ^ 2)
			if rem < bd then
				best, bd = Vector3.new(sx, a.Y + (b.Y - a.Y) * t, sz), rem
			end
		end
	end
	return best
end

-------------------------------------------------------------------------------------------------
-- Citizen areas (GwangalliCitizens.AREAS) -> anchor node / position
-------------------------------------------------------------------------------------------------
local anchors: { [string]: any } = {}
local destParts: { [string]: BasePart } = {}
local destScanned = 0

local function destPart(name: string): BasePart?
	local p = destParts[name]
	if p and p:IsDescendantOf(workspace) then
		return p
	end
	local now = os.clock()
	if now < destScanned then
		return nil
	end
	destScanned = now + 8
	for _, d in CollectionService:GetTagged("Destination") do
		if d:IsA("BasePart") then
			local dn = d:GetAttribute("DisplayName")
			if type(dn) == "string" then
				destParts[dn] = d
			end
		end
	end
	return destParts[name]
end

-- node, position of a citizen area's anchor (nil when unknown / not streamed yet)
function W.anchor(areaId: string?): (number?, Vector3?)
	if not areaId then
		return nil, nil
	end
	local a = anchors[areaId]
	if a then
		return a.node, a.pos
	end
	local def = Citizens and Citizens.AREAS and Citizens.AREAS[areaId]
	local key = if def then def.dest else areaId
	local pl = Nav.places[key] or Nav.places[areaId]
	if pl then
		a = { node = pl.node, pos = Vector3.new(pl.x, pl.y, pl.z) }
		anchors[areaId] = a
		return a.node, a.pos
	end
	local part = destPart(key)
	if part then
		local p = part.Position
		local node = W.nearest(p, 260)
		if node then
			a = { node = node, pos = p }
			anchors[areaId] = a
			return node, p
		end
	end
	return nil, nil
end

function W.areaPos(areaId: string): Vector3?
	local _, p = W.anchor(areaId)
	return p
end

function W.areaRadius(areaId: string?): number
	local def = areaId and Citizens and Citizens.AREAS and Citizens.AREAS[areaId]
	return if def then def.r else 140
end

function W.areaNav(areaId: string?): { [number]: boolean }?
	local list = areaId and Citizens and Citizens.AREA_NAV and Citizens.AREA_NAV[areaId]
	return W.areaSet(list)
end

-------------------------------------------------------------------------------------------------
-- Flow fields: next hop toward a set of source nodes (Dijkstra, computed incrementally)
-------------------------------------------------------------------------------------------------
type Field = { next: { number }, dist: { number }, ready: boolean, hk: { number }, hv: { number }, used: number }
local fields: { [string]: Field } = {}
local pending: { Field } = {}
local fieldCount = 0

local function heapPush(f: Field, k: number, v: number)
	local hk, hv = f.hk, f.hv
	local i = #hk + 1
	hk[i], hv[i] = k, v
	while i > 1 do
		local p = i // 2
		if hk[p] <= hk[i] then
			break
		end
		hk[p], hk[i] = hk[i], hk[p]
		hv[p], hv[i] = hv[i], hv[p]
		i = p
	end
end

local function heapPop(f: Field): (number, number)
	local hk, hv = f.hk, f.hv
	local k, v = hk[1], hv[1]
	local n = #hk
	hk[1], hv[1] = hk[n], hv[n]
	hk[n], hv[n] = nil, nil
	n -= 1
	local i = 1
	while true do
		local l, r = i * 2, i * 2 + 1
		local s = i
		if l <= n and hk[l] < hk[s] then
			s = l
		end
		if r <= n and hk[r] < hk[s] then
			s = r
		end
		if s == i then
			break
		end
		hk[s], hk[i] = hk[i], hk[s]
		hv[s], hv[i] = hv[i], hv[s]
		i = s
	end
	return k, v
end

-- field toward `sources` (node list); key caches it. Returns the field (maybe not ready yet).
function W.flow(key: string, sources: { number }): Field?
	local f = fields[key]
	if f then
		f.used = os.clock()
		return f
	end
	if #sources == 0 then
		return nil
	end
	-- keep at most 14 fields: drop the least recently used ready one
	if fieldCount >= 14 then
		local oldK, oldT = nil, math.huge
		for k, g in fields do
			if g.ready and g.used < oldT then
				oldK, oldT = k, g.used
			end
		end
		if oldK then
			fields[oldK] = nil
			fieldCount -= 1
		end
	end
	f = { next = table.create(N, -1), dist = table.create(N, math.huge), ready = false, hk = {}, hv = {}, used = os.clock() }
	for _, s in sources do
		if s and s > 0 and s <= N then
			f.dist[s] = 0
			f.next[s] = 0
			heapPush(f, 0, s)
		end
	end
	fields[key] = f
	fieldCount += 1
	table.insert(pending, f)
	return f
end

function W.flowToArea(areaId: string): Field?
	local node = W.anchor(areaId)
	if not node then
		return nil
	end
	return W.flow("area:" .. areaId, { node })
end

-- advance pending fields by up to `budget` node expansions (call once per frame)
function W.stepFlows(budget: number)
	while budget > 0 and #pending > 0 do
		local f = pending[1]
		local dist, nxt = f.dist, f.next
		while budget > 0 and #f.hk > 0 do
			local d, v = heapPop(f)
			if d <= dist[v] then
				budget -= 1
				local l = adj[v]
				for k = 1, #l, 2 do
					local w, e = l[k], l[k + 1]
					if ekind[e] ~= QUEUE then
						local nd = d + ecost[e]
						if nd < dist[w] then
							dist[w] = nd
							nxt[w] = v
							heapPush(f, nd, w)
						end
					end
				end
			end
		end
		if #f.hk == 0 then
			f.ready = true
			f.hk, f.hv = {}, {}
			table.remove(pending, 1)
		end
	end
end

function W.flowsPending(): number
	return #pending
end

-- Night steering toward the CLUB OCEAN queue tail (precomputed in GwangalliNav)
function W.toClub(node: number): number
	return Nav.ped.toClub[node] or 0
end

-------------------------------------------------------------------------------------------------
-- Random walk step with direction persistence
-------------------------------------------------------------------------------------------------
local weights: { number } = {}
local cands: { number } = {}
local candE: { number } = {}
-- opts: { allow = {[areaIdx]=true}?, cx, cz, r (keep within r of (cx, cz)), crossW, sandW, away = Vector3? }
function W.randomStep(cur: number, prev: number?, hx: number, hz: number, opts: any, rnd: () -> number): (number?, number?)
	local l = adj[cur]
	if not l or #l == 0 then
		return nil, nil
	end
	local p0 = pos[cur]
	local total = 0
	local n = 0
	local allow = opts.allow
	local cx, cz, r = opts.cx, opts.cz, opts.r
	local r2 = if r then r * r else nil
	for k = 1, #l, 2 do
		local w, e = l[k], l[k + 1]
		local kind = ekind[e]
		if kind ~= QUEUE then
			local q = pos[w]
			local dx, dz = q.X - p0.X, q.Z - p0.Z
			local len = math.sqrt(dx * dx + dz * dz)
			local wt = 1
			if len > 0.01 then
				local dot = (dx * hx + dz * hz) / len
				local f = 0.3 + math.max(0, dot)
				wt = f * f * f
			end
			if w == prev then
				wt *= 0.015
			end
			if allow and not allow[area[w]] then
				wt *= 0.06
			end
			if r2 then
				local ox, oz = q.X - cx, q.Z - cz
				local d2 = ox * ox + oz * oz
				if d2 > r2 then
					-- outside the wander circle: strongly prefer steps that head back in
					local bx, bz = p0.X - cx, p0.Z - cz
					if d2 > bx * bx + bz * bz then
						wt *= 0.05
					end
				end
			end
			if kind == XWALK or kind == XING then
				wt *= opts.crossW or 0.45
			elseif kind == SAND then
				wt *= opts.sandW or 1
			end
			if opts.away then
				local ax, az = q.X - opts.away.X, q.Z - opts.away.Z
				local bx, bz = p0.X - opts.away.X, p0.Z - opts.away.Z
				if ax * ax + az * az < bx * bx + bz * bz then
					wt *= 0.2
				end
			end
			n += 1
			cands[n] = w
			candE[n] = e
			weights[n] = wt
			total += wt
		end
	end
	if n == 0 or total <= 0 then
		return nil, nil
	end
	local x = rnd() * total
	for i = 1, n do
		x -= weights[i]
		if x <= 0 then
			return cands[i], candE[i]
		end
	end
	return cands[n], candE[n]
end

-------------------------------------------------------------------------------------------------
-- POIs
-------------------------------------------------------------------------------------------------
local kindSetCache: { [any]: any } = {}
-- ACT_STYLE entry -> { kinds = {[code]=true}, mask = tag bits }
function W.poiFilter(style: any): any
	if not style then
		return nil
	end
	local f = kindSetCache[style]
	if f then
		return f
	end
	f = { kinds = {}, mask = 0 }
	for _, k in style.kinds or {} do
		local code = Nav.POI_KIND[k]
		if code then
			f.kinds[code] = true
		end
	end
	for _, t in style.tags or {} do
		local bit = Nav.TAG[t]
		if bit then
			f.mask = bit32.bor(f.mask, bit)
		end
	end
	kindSetCache[style] = f
	return f
end

local poiCand: { number } = {}
local poiW: { number } = {}
-- a free POI near p matching the filter; night = true skips day-only spots (and the other way round)
function W.findPoi(p: Vector3, radius: number, filter: any, night: boolean, rnd: () -> number, avoid: Vector3?, avoidR: number?): number?
	if not filter then
		return nil
	end
	local TAG = Nav.TAG
	local dayBit, nightBit = TAG.day or 0, TAG.night or 0
	local r2 = radius * radius
	local n = 0
	local total = 0
	local c0x, c0z = math.floor((p.X - radius) / CELL), math.floor((p.Z - radius) / CELL)
	local c1x, c1z = math.floor((p.X + radius) / CELL), math.floor((p.Z + radius) / CELL)
	for cx = c0x, c1x do
		for cz = c0z, c1z do
			local cell = poiGrid[(cx + 512) * 2048 + (cz + 512)]
			if cell then
				for _, i in cell do
					if poiUse[i] < poiCap[i] then
						local ok = filter.kinds[poiKind[i]] == true or (filter.mask ~= 0 and bit32.btest(poiTags[i], filter.mask))
						if ok then
							local tags = poiTags[i]
							if night and bit32.btest(tags, dayBit) then
								ok = false
							elseif not night and bit32.btest(tags, nightBit) and not bit32.btest(tags, dayBit) then
								ok = rnd() < 0.2
							end
						end
						if ok then
							local q = poiPos[i]
							local dx, dz = q.X - p.X, q.Z - p.Z
							local d2 = dx * dx + dz * dz
							if d2 <= r2 and math.abs(q.Y - p.Y) < 30 then
								if avoid and avoidR then
									local ax, az = q.X - avoid.X, q.Z - avoid.Z
									if ax * ax + az * az < avoidR * avoidR then
										ok = false
									end
								end
								if ok then
									n += 1
									poiCand[n] = i
									local wt = 1 / (1 + math.sqrt(d2) / 35)
									poiW[n] = wt
									total += wt
								end
							end
						end
					end
				end
			end
		end
	end
	if n == 0 then
		return nil
	end
	local x = rnd() * total
	for i = 1, n do
		x -= poiW[i]
		if x <= 0 then
			return poiCand[i]
		end
	end
	return poiCand[n]
end

-- take a seat of POI i: returns the lowest free seat index (seats are tracked, so a new user
-- never sits on somebody who stayed when an earlier user left)
local poiTaken: { [number]: { [number]: boolean } } = {}
function W.reserve(i: number, want: number?): number
	local t = poiTaken[i]
	if not t then
		t = {}
		poiTaken[i] = t
	end
	local k = want
	if not k or t[k] then
		k = 1
		while t[k] do
			k += 1
		end
	end
	t[k] = true
	poiUse[i] = (poiUse[i] or 0) + 1
	return k
end

function W.release(i: number, k: number?)
	local t = poiTaken[i]
	if t and k then
		t[k] = nil
	end
	poiUse[i] = math.max(0, (poiUse[i] or 0) - 1)
end

-- seat / stand spot of a POI for the k-th user (seats poiGap studs apart along the bench / towel)
function W.poiSpot(i: number, k: number): (Vector3, number)
	local p, yaw = poiPos[i], poiYaw[i]
	local cap = poiCap[i]
	if cap <= 1 then
		return p, yaw
	end
	local off = ((k - 1) - (cap - 1) / 2) * (poiGap[i] or 2.6)
	local rx, rz = math.cos(yaw), -math.sin(yaw) -- right vector of CFrame.Angles(0, yaw, 0)
	return Vector3.new(p.X + rx * off, p.Y, p.Z + rz * off), yaw
end

function W.poiHasTag(i: number, tag: string): boolean
	local bit = Nav.TAG[tag]
	return bit ~= nil and bit32.btest(poiTags[i], bit)
end

function W.poiKindName(i: number): string?
	local code = poiKind[i]
	return Nav.POI_KIND and (function()
		for name, c in Nav.POI_KIND do
			if c == code then
				return name
			end
		end
		return nil
	end)()
end

-------------------------------------------------------------------------------------------------
-- Crosswalks
-------------------------------------------------------------------------------------------------
-- "walk" (go), "wait" (red / flashing: wait at the kerb), "look" (unsignalised: look, then go), nil
function W.crossState(e: number, serverNow: number): string?
	local k = ekind[e]
	if k ~= XWALK and k ~= XING then
		return nil
	end
	local isX, sig, ph = Nav.crossing(e)
	if not isX then
		return nil
	end
	if not sig then
		return "look"
	end
	if not (Shared and Shared.pedState) then
		return "walk"
	end
	local ok, st = pcall(Shared.pedState, sig, ph, serverNow)
	if not ok then
		return "walk"
	end
	return if st == "walk" then "walk" else "wait"
end

return W
