-- GwangalliGameplay/TaxiDispatch: the pure half of the phone-called taxi (owner: taxi_call).
-- No instances, no services: road routing on the traffic-lane graph of ReplicatedStorage.GwangalliNav,
-- the drive path (smoothing, kerb pull-over / pull-out, speed profile, compact encoding), the fare
-- breakdown and the driver / car / plate generator. Unit-tested with Lune (fake Nav tables).
--
--   local D = require(TaxiDispatch)
--   local graph = D.graph(Nav)                         -- Nav = require(ReplicatedStorage.GwangalliNav)
--   local loc = D.nearestLocation(graph, pos, {maxDist, side = pos?, kerbOnly})  -- {edge, s, point, dist}
--   local nodes, len = D.route(graph, fromLoc, toLoc)  -- forward lane path (Dijkstra, time weighted)
--   local nodes, len = D.approach(graph, toLoc, want)  -- a start `want` studs of road before toLoc
--   local path = D.buildPath(graph, pts, speeds, opts)  -- {pts, times, total, length}
--   local pos, dir = D.sample(path.pts, path.times, t) -- the same sampler runs on every client
--
-- Locations are points ON a lane edge: {edge = e, s = studs from the edge's start node, point}.
-- Korea drives on the right: the kerb (and the passenger door) is on the right of the heading.

local D = {}

local UP = Vector3.new(0, 1, 0)

-- lane kinds (GwangalliNav.LANE_KIND)
local K_LANE, K_BUS, K_STRAIGHT, K_TURN, K_CHANGE, K_UTURN = 1, 2, 3, 4, 5, 6
D.KIND = { lane = K_LANE, bus = K_BUS, straight = K_STRAIGHT, turn = K_TURN, change = K_CHANGE, uturn = K_UTURN }

D.CFG = {
	speedScale = 1.35, -- game feel: taxis drive a bit faster than the posted limit
	minCruise = 26, -- studs/s
	maxCruise = 62,
	turnSpeed = 18,
	latAccel = 7, -- studs/s^2 in curves
	accel = 14,
	decel = 11,
	densify = 6, -- studs between path samples before decimation
	keepEvery = 48, -- decimation: keep at least one point every N studs
	CELL = 64,
}

-------------------------------------------------------------------------------------------------
-- Vector helpers
-------------------------------------------------------------------------------------------------
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unitFlat(v: Vector3): Vector3?
	local f = flat(v)
	local m = f.Magnitude
	if m < 1e-4 then
		return nil
	end
	return f / m
end

local function rightOf(dir: Vector3): Vector3
	return dir:Cross(UP)
end
D.rightOf = rightOf

-- CFrame at `pos` looking along `dir` (flat), without CFrame.lookAt (Lune mirrors it).
function D.cframe(pos: Vector3, dir: Vector3): CFrame
	local look = unitFlat(dir) or Vector3.new(0, 0, -1)
	local right = look:Cross(UP)
	return CFrame.fromMatrix(pos, right, UP, -look)
end

local function smoothstep(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-------------------------------------------------------------------------------------------------
-- Graph
-------------------------------------------------------------------------------------------------
export type Graph = {
	n: number,
	pos: { Vector3 },
	eFrom: { number },
	eTo: { number },
	eLen: { number },
	eSpeed: { number }, -- studs/s (game scaled)
	eKind: { number },
	out: { { number } },
	inn: { { number } },
	grid: { [number]: { number } },
	nEdges: number,
}

local function gkey(x: number, z: number, cell: number): number
	return (math.floor(x / cell) + 1024) * 4096 + (math.floor(z / cell) + 1024)
end

function D.graph(Nav: any): Graph?
	local L = Nav and Nav.lanes
	if type(L) ~= "table" or type(L.n) ~= "number" or L.n < 2 or type(L.pos) ~= "table" or type(L.edges) ~= "table" then
		return nil
	end
	local cfg = D.CFG
	local n = L.n
	local pos = table.create(n)
	local out = table.create(n)
	local inn = table.create(n)
	for i = 1, n do
		local x, z = L.pos[(i - 1) * 2 + 1], L.pos[(i - 1) * 2 + 2]
		if type(x) ~= "number" or type(z) ~= "number" then
			return nil
		end
		pos[i] = Vector3.new(x, 6, z)
		out[i] = {}
		inn[i] = {}
	end
	local g: Graph = { n = n, pos = pos, eFrom = {}, eTo = {}, eLen = {}, eSpeed = {}, eKind = {}, out = out, inn = inn, grid = {}, nEdges = 0 }
	local E = L.edges
	local ne = #E // 4
	for e = 1, ne do
		local k = (e - 1) * 4
		local a, b, kmh, kind = E[k + 1], E[k + 2], E[k + 3], E[k + 4]
		if type(a) == "number" and type(b) == "number" and pos[a] and pos[b] and a ~= b then
			local len = (pos[b] - pos[a]).Magnitude
			g.nEdges += 1
			local id = g.nEdges
			g.eFrom[id] = a
			g.eTo[id] = b
			g.eLen[id] = math.max(0.5, len)
			local v = (tonumber(kmh) or 30) / 1.08 * cfg.speedScale
			if kind == K_TURN or kind == K_UTURN then
				v = math.min(v, cfg.turnSpeed)
			end
			g.eSpeed[id] = math.clamp(v, 8, cfg.maxCruise)
			g.eKind[id] = tonumber(kind) or K_LANE
			table.insert(out[a], id)
			table.insert(inn[b], id)
			-- spatial index: every cell the edge passes through
			local steps = math.max(1, math.ceil(len / (cfg.CELL / 4)))
			local seen = {}
			for j = 0, steps do
				local p = pos[a]:Lerp(pos[b], j / steps)
				local key = gkey(p.X, p.Z, cfg.CELL)
				if not seen[key] then
					seen[key] = true
					local cellList = g.grid[key]
					if not cellList then
						cellList = {}
						g.grid[key] = cellList
					end
					table.insert(cellList, id)
				end
			end
		end
	end
	if g.nEdges == 0 then
		return nil
	end
	return g
end

function D.edgeDir(g: Graph, e: number): Vector3
	return unitFlat(g.pos[g.eTo[e]] - g.pos[g.eFrom[e]]) or Vector3.new(0, 0, -1)
end

function D.pointOn(g: Graph, e: number, s: number): Vector3
	local a, b = g.pos[g.eFrom[e]], g.pos[g.eTo[e]]
	return a:Lerp(b, math.clamp(s / g.eLen[e], 0, 1))
end

export type Loc = { edge: number, s: number, point: Vector3, dist: number }

-- Edges whose spatial cells are within `r` of `p`.
local function edgesNear(g: Graph, p: Vector3, r: number): { number }
	local cell = D.CFG.CELL
	local out, seen = {}, {}
	local c0x, c0z = math.floor((p.X - r) / cell), math.floor((p.Z - r) / cell)
	local c1x, c1z = math.floor((p.X + r) / cell), math.floor((p.Z + r) / cell)
	for cx = c0x, c1x do
		for cz = c0z, c1z do
			local list = g.grid[(cx + 1024) * 4096 + (cz + 1024)]
			if list then
				for _, e in list do
					if not seen[e] then
						seen[e] = true
						table.insert(out, e)
					end
				end
			end
		end
	end
	return out
end
D.edgesNear = edgesNear

-- Closest point on edge e to p (flat): s, point, dist.
local function project(g: Graph, e: number, p: Vector3): (number, Vector3, number)
	local a = g.pos[g.eFrom[e]]
	local len = g.eLen[e]
	local dir = D.edgeDir(g, e)
	local s = math.clamp(flat(p - a):Dot(dir), 0, len)
	local q = a + dir * s
	return s, q, flat(p - q).Magnitude
end

-- Is there another same-direction travel lane 5..16 studs to the right of `point` on edge e?
function D.hasLaneRight(g: Graph, e: number, point: Vector3): boolean
	local dir = D.edgeDir(g, e)
	local right = rightOf(dir)
	for _, o in edgesNear(g, point + right * 10, 18) do
		if o ~= e then
			local k = g.eKind[o]
			if (k == K_LANE or k == K_BUS) and D.edgeDir(g, o):Dot(dir) > 0.9 then
				local _, q = project(g, o, point)
				local lat = (q - point):Dot(right)
				local along = math.abs((q - point):Dot(dir))
				if lat > 5 and lat < 16 and along < 6 then
					return true
				end
			end
		end
	end
	return false
end

-- Nearest stopping location to `p` on a travel lane. opts:
--   maxDist (studs, default 260)
--   side: Vector3? -> the location must have this point on its RIGHT (kerb side) when possible
--   kerbOnly: prefer kerb lanes (no travel lane further right)
--   margin: keep this far from the edge ends (junction stop lines), default 6
-- Returns the best Loc or nil. Locations on the requested side win over the other side; kerb lanes
-- win over inner lanes; then the shortest distance.
function D.nearestLocation(g: Graph, p: Vector3, opts: { [string]: any }?): Loc?
	local o = opts or {}
	local maxDist = o.maxDist or 260
	local margin = o.margin or 6
	local best: Loc? = nil
	local bestScore = math.huge
	for _, e in edgesNear(g, p, maxDist) do
		local k = g.eKind[e]
		if (k == K_LANE or k == K_BUS) and g.eLen[e] > 2 * margin + 1 then
			local s, q, dist = project(g, e, p)
			s = math.clamp(s, margin, g.eLen[e] - margin)
			q = D.pointOn(g, e, s)
			dist = flat(p - q).Magnitude
			if dist <= maxDist then
				local score = dist
				if o.side then
					local dir = D.edgeDir(g, e)
					if flat(o.side - q):Dot(rightOf(dir)) < 0 then
						score += 1000 -- wrong side of the road: only when nothing else is near
					end
				end
				if o.kerbOnly and score < bestScore and D.hasLaneRight(g, e, q) then
					score += 60
				end
				if score < bestScore then
					bestScore = score
					best = { edge = e, s = s, point = q, dist = dist }
				end
			end
		end
	end
	return best
end

-------------------------------------------------------------------------------------------------
-- Routing (binary heap Dijkstra)
-------------------------------------------------------------------------------------------------
local function heapPush(h: { any }, node: number, key: number)
	table.insert(h, { node, key })
	local i = #h
	while i > 1 do
		local parent = i // 2
		if h[parent][2] <= h[i][2] then
			break
		end
		h[parent], h[i] = h[i], h[parent]
		i = parent
	end
end

local function heapPop(h: { any }): (number?, number?)
	local n = #h
	if n == 0 then
		return nil, nil
	end
	local top = h[1]
	h[1] = h[n]
	h[n] = nil
	n -= 1
	local i = 1
	while true do
		local l, r = i * 2, i * 2 + 1
		local m = i
		if l <= n and h[l][2] < h[m][2] then
			m = l
		end
		if r <= n and h[r][2] < h[m][2] then
			m = r
		end
		if m == i then
			break
		end
		h[m], h[i] = h[i], h[m]
		i = m
	end
	return top[1], top[2]
end

local function edgeCost(g: Graph, e: number): number
	local c = g.eLen[e] / g.eSpeed[e]
	local k = g.eKind[e]
	if k == K_UTURN then
		c = c * 3 + 4
	elseif k == K_CHANGE then
		c += 0.6
	end
	return c
end

-- Forward path of node ids from node `a` to node `b` (inclusive) and its length in studs.
function D.routeNodes(g: Graph, a: number, b: number, maxNodes: number?): ({ number }?, number)
	if a == b then
		return { a }, 0
	end
	local dist: { [number]: number } = { [a] = 0 }
	local prevEdge: { [number]: number } = {}
	local h = {}
	heapPush(h, a, 0)
	local visited = 0
	local limit = maxNodes or (g.n + 10)
	while true do
		local u, du = heapPop(h)
		if not u then
			break
		end
		if du <= (dist[u] or math.huge) + 1e-9 then
			if u == b then
				break
			end
			visited += 1
			if visited > limit then
				break
			end
			for _, e in g.out[u] do
				local v = g.eTo[e]
				local nd = du + edgeCost(g, e)
				if nd < (dist[v] or math.huge) then
					dist[v] = nd
					prevEdge[v] = e
					heapPush(h, v, nd)
				end
			end
		end
	end
	if not dist[b] then
		return nil, 0
	end
	local nodes = { b }
	local len = 0
	local cur = b
	local guard = 0
	while cur ~= a do
		local e = prevEdge[cur]
		if not e then
			return nil, 0
		end
		len += g.eLen[e]
		cur = g.eFrom[e]
		table.insert(nodes, cur)
		guard += 1
		if guard > g.n + 5 then
			return nil, 0
		end
	end
	-- reverse
	local nn = #nodes
	for i = 1, nn // 2 do
		nodes[i], nodes[nn - i + 1] = nodes[nn - i + 1], nodes[i]
	end
	return nodes, len
end

-- Road path between two locations: a list of Vector3 points (from.point ... to.point) and its length.
function D.route(g: Graph, from: Loc, to: Loc): ({ Vector3 }?, number)
	if from.edge == to.edge and to.s >= from.s - 0.5 then
		return { from.point, to.point }, math.max(0, to.s - from.s)
	end
	local nodes, mid = D.routeNodes(g, g.eTo[from.edge], g.eFrom[to.edge])
	if not nodes then
		return nil, 0
	end
	local pts = { from.point }
	for _, id in nodes do
		table.insert(pts, g.pos[id])
	end
	table.insert(pts, to.point)
	local len = (g.eLen[from.edge] - from.s) + mid + to.s
	return pts, len
end

-- A start point roughly `want` studs of road BEFORE `to` (reverse Dijkstra by distance) and the
-- forward path from it to `to`. Prefers ordinary lanes; never starts on a U-turn loop.
function D.approach(g: Graph, to: Loc, want: number, minWant: number?): ({ Vector3 }?, number)
	local startNode = g.eFrom[to.edge]
	local lo = minWant or want * 0.5
	local dist: { [number]: number } = { [startNode] = to.s }
	local nextEdge: { [number]: number } = {}
	local h = {}
	heapPush(h, startNode, to.s)
	local bestNode, bestScore = nil, math.huge
	local visited = 0
	while true do
		local u, du = heapPop(h)
		if not u then
			break
		end
		if du <= (dist[u] or math.huge) + 1e-9 then
			visited += 1
			if visited > g.n + 10 then
				break
			end
			if du >= lo then
				local score = math.abs(du - want)
				-- a node whose way in is a normal lane looks like "coming down the road"
				local inKind = 0
				for _, e in g.inn[u] do
					inKind = math.max(inKind, if g.eKind[e] == K_LANE or g.eKind[e] == K_BUS then 1 else 0)
				end
				if inKind == 0 then
					score += 40
				end
				if score < bestScore then
					bestScore, bestNode = score, u
				end
			end
			if du < want * 1.6 then
				for _, e in g.inn[u] do
					if g.eKind[e] ~= K_UTURN then
						local v = g.eFrom[e]
						local nd = du + g.eLen[e]
						if nd < (dist[v] or math.huge) then
							dist[v] = nd
							nextEdge[v] = e
							heapPush(h, v, nd)
						end
					end
				end
			end
		end
	end
	if not bestNode then
		-- a short road: start at the beginning of the pickup edge
		local a = g.pos[startNode]
		return { a, to.point }, to.s
	end
	local pts = {}
	local cur = bestNode
	local guard = 0
	while cur ~= startNode do
		table.insert(pts, g.pos[cur])
		local e = nextEdge[cur]
		if not e then
			return nil, 0
		end
		cur = g.eTo[e]
		guard += 1
		if guard > g.n + 5 then
			return nil, 0
		end
	end
	table.insert(pts, g.pos[startNode])
	table.insert(pts, to.point)
	return pts, dist[bestNode]
end

-- A drive-away path: `want` studs forward from `from` (first out-edge of each node, preferring lanes).
function D.forward(g: Graph, from: Loc, want: number): { Vector3 }
	local pts = { from.point }
	local left = want - (g.eLen[from.edge] - from.s)
	local node = g.eTo[from.edge]
	table.insert(pts, g.pos[node])
	local guard = 0
	while left > 0 and guard < 60 do
		guard += 1
		local pick = nil
		for _, e in g.out[node] do
			local k = g.eKind[e]
			if k == K_LANE or k == K_BUS or k == K_STRAIGHT then
				pick = e
				break
			end
		end
		pick = pick or g.out[node][1]
		if not pick or g.eKind[pick] == K_UTURN then
			break
		end
		node = g.eTo[pick]
		table.insert(pts, g.pos[node])
		left -= g.eLen[pick]
	end
	return pts
end

-------------------------------------------------------------------------------------------------
-- Path building
-------------------------------------------------------------------------------------------------
local function polyLength(pts: { Vector3 }): number
	local len = 0
	for i = 2, #pts do
		len += flat(pts[i] - pts[i - 1]).Magnitude
	end
	return len
end
D.polyLength = polyLength

-- Drops consecutive duplicates (< 0.3 studs apart).
local function dedupe(pts: { Vector3 }): { Vector3 }
	local out = { pts[1] }
	for i = 2, #pts do
		if flat(pts[i] - out[#out]).Magnitude > 0.3 then
			table.insert(out, pts[i])
		end
	end
	if #out == 1 and #pts > 1 then
		table.insert(out, pts[#pts])
	end
	return out
end

-- Chaikin corner cutting (endpoints kept) so lane changes / junction connectors look driven.
function D.smooth(pts: { Vector3 }, iterations: number?): { Vector3 }
	local cur = dedupe(pts)
	for _ = 1, iterations or 2 do
		if #cur < 3 then
			return cur
		end
		local nxt = { cur[1] }
		for i = 1, #cur - 1 do
			local a, b = cur[i], cur[i + 1]
			local segLen = flat(b - a).Magnitude
			if segLen > 40 then
				-- long straight: only round the ends (keeps the road line exact)
				if i > 1 then
					table.insert(nxt, a:Lerp(b, 8 / segLen))
				end
				if i < #cur - 1 then
					table.insert(nxt, a:Lerp(b, 1 - 8 / segLen))
				end
			else
				if i > 1 then
					table.insert(nxt, a:Lerp(b, 0.25))
				end
				if i < #cur - 1 then
					table.insert(nxt, a:Lerp(b, 0.75))
				end
			end
		end
		table.insert(nxt, cur[#cur])
		cur = dedupe(nxt)
	end
	return cur
end

-- Evenly re-sampled polyline, at most `step` studs between points.
function D.densify(pts: { Vector3 }, step: number?): { Vector3 }
	local st = step or D.CFG.densify
	local out = { pts[1] }
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local len = flat(b - a).Magnitude
		local k = math.max(1, math.ceil(len / st))
		for j = 1, k do
			table.insert(out, a:Lerp(b, j / k))
		end
	end
	return dedupe(out)
end

-- Shifts the last `len` studs of the path `offset` studs to the right (kerb pull-over), or the first
-- `len` studs when `atStart` (pull-out from the kerb). Blend = smoothstep.
function D.lateral(pts: { Vector3 }, offset: number, len: number, atStart: boolean?): { Vector3 }
	if math.abs(offset) < 0.05 or #pts < 2 then
		return pts
	end
	local n = #pts
	local out = table.clone(pts)
	-- distance of every point from the end (or the start)
	local acc = table.create(n, 0)
	if atStart then
		for i = 2, n do
			acc[i] = acc[i - 1] + flat(pts[i] - pts[i - 1]).Magnitude
		end
	else
		for i = n - 1, 1, -1 do
			acc[i] = acc[i + 1] + flat(pts[i + 1] - pts[i]).Magnitude
		end
	end
	for i = 1, n do
		local d = acc[i]
		if d < len then
			local dir: Vector3?
			if i < n then
				dir = unitFlat(pts[i + 1] - pts[i])
			end
			if not dir and i > 1 then
				dir = unitFlat(pts[i] - pts[i - 1])
			end
			if dir then
				local w = smoothstep(1 - d / len)
				out[i] = pts[i] + rightOf(dir) * offset * w
			end
		end
	end
	return out
end

-- Speed profile: times (s, from 0) for every point. vmax per point, v0 / v1 start / end speed.
function D.profile(pts: { Vector3 }, vmax: { number }, v0: number, v1: number, accel: number?, decel: number?): ({ number }, number)
	local a = accel or D.CFG.accel
	local dcl = decel or D.CFG.decel
	local n = #pts
	local v = table.create(n, 0)
	local L = table.create(n, 0)
	for i = 1, n - 1 do
		L[i] = flat(pts[i + 1] - pts[i]).Magnitude
	end
	v[1] = math.min(v0, vmax[1])
	for i = 1, n - 1 do
		v[i + 1] = math.min(vmax[i + 1], math.sqrt(v[i] * v[i] + 2 * a * L[i]))
	end
	v[n] = math.min(v[n], v1)
	for i = n - 1, 1, -1 do
		v[i] = math.min(v[i], math.sqrt(v[i + 1] * v[i + 1] + 2 * dcl * L[i]))
	end
	local times = table.create(n, 0)
	for i = 1, n - 1 do
		local avg = (v[i] + v[i + 1]) / 2
		local dt
		if avg < 0.3 then
			dt = if L[i] < 0.01 then 0 else math.sqrt(2 * L[i] / math.max(a, 0.1))
		else
			dt = L[i] / avg
		end
		times[i + 1] = times[i] + dt
	end
	return times, times[n]
end

-- Per-point speed limits from the posted speed and the local curvature.
function D.limits(pts: { Vector3 }, cruise: number): { number }
	local cfg = D.CFG
	local n = #pts
	local vm = table.create(n, cruise)
	for i = 2, n - 1 do
		local d1 = unitFlat(pts[i] - pts[i - 1])
		local d2 = unitFlat(pts[i + 1] - pts[i])
		if d1 and d2 then
			local ang = math.acos(math.clamp(d1:Dot(d2), -1, 1))
			if ang > 0.02 then
				local seg = (flat(pts[i] - pts[i - 1]).Magnitude + flat(pts[i + 1] - pts[i]).Magnitude) / 2
				local radius = seg / ang
				vm[i] = math.min(cruise, math.max(cfg.turnSpeed * 0.6, math.sqrt(cfg.latAccel * radius)))
			end
		end
	end
	return vm
end

-- Keeps the points a linear-in-time sampler needs: direction changes, speed changes, every
-- keepEvery studs. times must match pts.
function D.decimate(pts: { Vector3 }, times: { number }): ({ Vector3 }, { number })
	local n = #pts
	if n <= 2 then
		return pts, times
	end
	local keepEvery = D.CFG.keepEvery
	local op, ot = { pts[1] }, { times[1] }
	local lastI = 1
	local sinceKeep = 0
	for i = 2, n - 1 do
		sinceKeep += flat(pts[i] - pts[i - 1]).Magnitude
		local keep = sinceKeep >= keepEvery
		if not keep then
			local d1 = unitFlat(pts[i] - pts[lastI])
			local d2 = unitFlat(pts[i + 1] - pts[i])
			if d1 and d2 and d1:Dot(d2) < 0.9992 then -- ~2.3 degrees
				keep = true
			end
		end
		if not keep then
			-- speed change since the last kept point (linear-in-time must stay accurate)
			local segA = flat(pts[i] - pts[i - 1]).Magnitude / math.max(1e-3, times[i] - times[i - 1])
			local segB = flat(pts[i + 1] - pts[i]).Magnitude / math.max(1e-3, times[i + 1] - times[i])
			local avgKept = flat(pts[i] - pts[lastI]).Magnitude / math.max(1e-3, times[i] - times[lastI])
			if math.abs(segB - avgKept) > 1.2 or math.abs(segA - segB) > 1.2 then
				keep = true
			end
		end
		if keep then
			table.insert(op, pts[i])
			table.insert(ot, times[i])
			lastI = i
			sinceKeep = 0
		end
	end
	table.insert(op, pts[n])
	table.insert(ot, times[n])
	return op, ot
end

export type Path = { pts: { Vector3 }, times: { number }, total: number, length: number }

-- Full path from raw road points. opts:
--   cruise (studs/s), v0 (start speed; 0 = standing start), v1 (end speed, default 0),
--   pullOut = {offset, len}, pullOver = {offset, len}, maxSeconds (time scale cap), heights (fn
--   (Vector3) -> y?) to put every point on the real road surface.
function D.buildPath(pts: { Vector3 }, opts: { [string]: any }?): Path?
	local o = opts or {}
	if #pts < 2 then
		return nil
	end
	local cruise = math.clamp(o.cruise or 40, D.CFG.minCruise, D.CFG.maxCruise)
	local p = D.smooth(pts, 2)
	p = D.densify(p, D.CFG.densify)
	if #p < 2 then
		return nil
	end
	if o.pullOut and o.pullOut.offset then
		p = D.lateral(p, o.pullOut.offset, o.pullOut.len or 26, true)
	end
	if o.pullOver and o.pullOver.offset then
		p = D.lateral(p, o.pullOver.offset, o.pullOver.len or 30, false)
	end
	if o.heights then
		for i, q in p do
			local ok, y = pcall(o.heights, q)
			if ok and type(y) == "number" and y == y then
				p[i] = Vector3.new(q.X, y, q.Z)
			end
		end
	end
	local vm = D.limits(p, cruise)
	local times, total = D.profile(p, vm, o.v0 or 0, o.v1 or 0)
	local maxS = o.maxSeconds
	if maxS and total > maxS and total > 0 then
		local f = math.min(o.maxScale or 3, total / maxS)
		for i = 1, #times do
			times[i] /= f
		end
		total /= f
	end
	local length = polyLength(p)
	local dp, dt = D.decimate(p, times)
	return { pts = dp, times = dt, total = total, length = length }
end

-------------------------------------------------------------------------------------------------
-- Sampling (identical copy in the client TaxiRide module)
-------------------------------------------------------------------------------------------------
local function posAt(pts: { Vector3 }, times: { number }, t: number): (Vector3, number)
	local n = #pts
	if n == 0 then
		return Vector3.zero, 1
	end
	if t <= times[1] or n == 1 then
		return pts[1], 1
	end
	if t >= times[n] then
		return pts[n], n - 1
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if times[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local span = times[hi] - times[lo]
	local u = if span > 1e-6 then (t - times[lo]) / span else 1
	return pts[lo]:Lerp(pts[hi], u), lo
end
D.posAt = posAt

-- Position + flat heading at time t (seconds since the path started).
function D.sample(pts: { Vector3 }, times: { number }, t: number): (Vector3, Vector3)
	local p, i = posAt(pts, times, t)
	local a = posAt(pts, times, t - 0.3)
	local b = posAt(pts, times, t + 0.3)
	local dir = unitFlat(b - a)
	if not dir or flat(b - a).Magnitude < 0.4 then
		-- stopped / at the ends: direction of the nearest real segment
		local n = #pts
		local j = math.clamp(i, 1, math.max(1, n - 1))
		dir = nil
		for k = j, 1, -1 do
			if k + 1 <= n then
				dir = unitFlat(pts[k + 1] - pts[k])
				if dir and flat(pts[k + 1] - pts[k]).Magnitude > 0.4 then
					break
				end
			end
		end
		if not dir then
			for k = j, n - 1 do
				dir = unitFlat(pts[k + 1] - pts[k])
				if dir then
					break
				end
			end
		end
	end
	return p, dir or Vector3.new(0, 0, -1)
end

-- Distance travelled along the path at time t.
function D.distanceAt(pts: { Vector3 }, times: { number }, t: number): number
	local p, i = posAt(pts, times, t)
	local d = 0
	for k = 2, i do
		d += flat(pts[k] - pts[k - 1]).Magnitude
	end
	return d + flat(p - pts[i]).Magnitude
end

-- Compact string for a model attribute: "x,y,z,t;..." (0.1 stud / 1 ms).
function D.encode(pts: { Vector3 }, times: { number }): string
	local parts = table.create(#pts)
	for i, p in pts do
		parts[i] = string.format("%.1f,%.1f,%.1f,%.3f", p.X, p.Y, p.Z, times[i])
	end
	return table.concat(parts, ";")
end

function D.decode(s: string): ({ Vector3 }, { number })
	local pts, times = {}, {}
	for x, y, z, t in string.gmatch(s, "([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)") do
		local nx, ny, nz, nt = tonumber(x), tonumber(y), tonumber(z), tonumber(t)
		if nx and ny and nz and nt then
			table.insert(pts, Vector3.new(nx, ny, nz))
			table.insert(times, nt)
		end
	end
	return pts, times
end

-------------------------------------------------------------------------------------------------
-- Fare breakdown (mirrors G.taxiFare; lines always add up to the fare)
-------------------------------------------------------------------------------------------------
function D.fareBreakdown(G: any, studs: number, clock: number?, popularity: number?): { [string]: any }
	local T = G.TAXI
	local total = G.taxiFare(studs, clock, popularity)
	local base = T.baseFare
	local distRaw = math.max(0, studs - T.baseStuds) * T.perStud
	local night = clock ~= nil and G.inClockWindow(clock % 24, T.nightFrom, T.nightTo)
	local regular = popularity ~= nil and popularity >= T.regularPopularity
	local nightAmt = if night then math.floor((base + distRaw) * T.nightSurcharge / 100 + 0.5) * 100 else 0
	local discAmt = if regular then math.floor((base + distRaw + nightAmt) * T.regularDiscount / 100 + 0.5) * 100 else 0
	local dist = total - base - nightAmt + discAmt -- absorbs rounding and the cap
	if dist < 0 then
		-- capped / tiny rides: fold everything into the base line
		base = total
		dist, nightAmt, discAmt = 0, 0, 0
	end
	return { total = total, base = base, distance = dist, night = nightAmt, discount = discAmt, isNight = night, isRegular = regular }
end

-- The meter shown during a ride: flag fall, then 100원 steps as the distance runs, never above fare.
function D.meterAt(fare: number, base: number, progress: number): number
	local p = math.clamp(progress, 0, 1)
	if p >= 0.999 then
		return fare
	end
	local extra = math.max(0, fare - base)
	return math.min(fare, base + math.floor(extra * p / 100) * 100)
end

-------------------------------------------------------------------------------------------------
-- Driver / car / plate
-------------------------------------------------------------------------------------------------
local SURNAMES = { "김", "이", "박", "최", "정", "강", "조", "윤", "장", "임", "한", "오", "서", "신", "권", "황" }
local GIVEN = { "광수", "영철", "민호", "정훈", "성진", "동욱", "재석", "상철", "현우", "영미", "순자", "경희", "태식", "기영", "만수", "종국" }
local CARS = {
	{ model = "쏘나타", color = "주황색" },
	{ model = "쏘나타", color = "은색" },
	{ model = "K5", color = "흰색" },
	{ model = "쏘나타", color = "흰색" },
	{ model = "아이오닉 5", color = "하늘색" },
	{ model = "그랜저", color = "검은색" },
}
local PLATE_USE = { "바", "사", "아", "자" } -- 영업용 (taxi) plates

-- rng: a Random-like object with :NextInteger(lo, hi) / :NextNumber(lo, hi).
function D.driver(rng: any): { [string]: any }
	local name = SURNAMES[rng:NextInteger(1, #SURNAMES)] .. GIVEN[rng:NextInteger(1, #GIVEN)]
	local car = CARS[rng:NextInteger(1, #CARS)]
	local plate = string.format("부산 %d%s %04d", rng:NextInteger(10, 99), PLATE_USE[rng:NextInteger(1, #PLATE_USE)], rng:NextInteger(1000, 9999))
	local rating = math.floor(rng:NextNumber(4.6, 5.0) * 10 + 0.5) / 10
	local years = rng:NextInteger(3, 31)
	return {
		name = name,
		title = name .. " 기사님",
		car = car.model,
		color = car.color,
		plate = plate,
		rating = math.min(5, rating),
		years = years,
		phone = string.format("050-%04d-%04d", rng:NextInteger(1000, 9999), rng:NextInteger(1000, 9999)), -- 안심번호
	}
end

return D
