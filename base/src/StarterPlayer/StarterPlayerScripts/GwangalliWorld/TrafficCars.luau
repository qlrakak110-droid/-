-- GwangalliWorld/TrafficCars: the client's moving ambient traffic (started by Traffic.luau).
--
-- Cars live only on this client, around the local player, on the lane graph of
-- ReplicatedStorage.GwangalliNav (road centrelines, junction connectors, stop lines; built offline from
-- the real roads, so a car never paths through a building). Bodies come from TrafficModels (the map's
-- own kit cars, cloned once per kind and welded to one anchored root); people in and around them come
-- from TrafficPeople.
--
-- ONE driver loop (Heartbeat) for every car and person:
--   * every frame: speed (an intelligent-driver-model follower: free road, the car ahead, a stop line,
--     a person in the lane), position along the lane curve (Hermite connectors through junctions, the
--     body's heading from its front and rear axle points so corners and lane kinks turn smoothly), body
--     pitch from braking / acceleration and the road slope, then ONE workspace:BulkMoveTo for all car
--     roots and the rigs riding in them. Writes are LOD'ed: every frame on screen within NearWrite,
--     every FarEvery frames farther, every OffEvery frames off screen, never for a car that stands still.
--   * ThinkHz per car (staggered): stop lines (GwangalliShared.vehicleState of the signal group,
--     amber = stop if it can), the car ahead on its own path (exact path distance) or across it (a
--     crossing car in front), people in the lane ahead (StreetLife pedestrians, scene walkers and the
--     player on foot; only cars within PedDist of the player), the player's car, the honk (once, when
--     the player keeps standing in the lane), indicators before turns / lane changes, brake / head lamps.
--   * one ground raycast per car per GroundEvery s (only cars within GroundDist), no other raycasts.
--   * spawns in a ring around the player (off screen, or far when in view), recycled when far / out of
--     view / stuck. Static "TrafficVehicles" (cars the map froze at red lights) are adopted: hidden
--     locally (and made non-colliding) and replaced by a live car at the same spot, so the map's queues
--     drive off when the light turns green. Static "TrafficVehicles" scooters are only hidden.
-- Debug / test hooks (workspace attributes): GwangalliTrafficOff (true = stop and clean up),
-- GwangalliTrafficCap (number = cap override), GwangalliTrafficDebug (true = print stats).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cars = {}

function Cars.start(ctx: any)
	local Shared, Util, DayNight = ctx.Shared, ctx.Util, ctx.DayNight
	local folderMod = ctx.Folder
	local Cfg = require(folderMod:WaitForChild("TrafficConfig") :: any)
	if Cfg.Enabled == false then
		return
	end
	local Models = require(folderMod:WaitForChild("TrafficModels") :: any)
	local People = require(folderMod:WaitForChild("TrafficPeople") :: any)

	local navModule = ReplicatedStorage:WaitForChild("GwangalliNav", 60)
	if not navModule or not navModule:IsA("ModuleScript") then
		Util.warn("Traffic", "GwangalliNav missing: no moving traffic")
		return
	end
	local okNav, Nav = pcall(require, navModule)
	if not okNav or type(Nav) ~= "table" or not Nav.lanes or (Nav.lanes.n or 0) < 2 then
		Util.warn("Traffic", "GwangalliNav failed to load: ", tostring(Nav))
		return
	end
	local okDecode, D = pcall(Nav.decode)
	if not okDecode then
		Util.warn("Traffic", "GwangalliNav.decode failed: ", tostring(D))
		return
	end

	local player = Players.LocalPlayer
	local old = workspace:FindFirstChild("GwangalliTraffic")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "GwangalliTraffic" -- client-only (never replicated, never streamed)
	folder.Parent = workspace
	Models.init(ctx, folder, Cfg)

	-------------------------------------------------------------------------------------------------
	-- Lane graph (flat arrays, built once)
	-------------------------------------------------------------------------------------------------
	local lanePos: { Vector3 } = D.lanePos
	local laneStop = D.laneStop
	local laneGrid = D.laneGrid
	local LE = Nav.lanes.edges
	local nE = #LE // 4
	local eFrom, eTo, eSpd, eKind, eLen = table.create(nE), table.create(nE), table.create(nE), table.create(nE), table.create(nE)
	local outE: { [number]: { number } } = {}
	local inE: { [number]: { number } } = {}
	for e = 1, nE do
		local k = (e - 1) * 4
		local a, b = LE[k + 1], LE[k + 2]
		eFrom[e], eTo[e] = a, b
		eSpd[e] = (LE[k + 3] or 30) / 1.08
		eKind[e] = LE[k + 4]
		eLen[e] = math.max(0.01, (lanePos[b] - lanePos[a]).Magnitude)
		local o = outE[a]
		if not o then
			o = {}
			outE[a] = o
		end
		table.insert(o, e)
		local i = inE[b]
		if not i then
			i = {}
			inE[b] = i
		end
		table.insert(i, e)
	end
	local LK = Nav.LANE_KIND or {}
	local K_LANE, K_BUS, K_STRAIGHT, K_TURN, K_CHANGE, K_UTURN = LK.lane or 1, LK.bus or 2, LK.straight or 3, LK.turn or 4, LK.change or 5, LK.uturn or 6
	local KIND_NAME = {}
	for name, code in LK do
		KIND_NAME[code] = name
	end
	local wByKind = {}
	for code, name in KIND_NAME do
		wByKind[code] = Cfg.EdgeWeight[name] or 0.5
	end
	local portal: { [number]: boolean } = {}
	do
		local P = Nav.lanes.portals or {}
		for i = 1, #P // 2 do
			portal[P[(i - 1) * 2 + 1]] = true
		end
	end
	local signals = Nav.signals or {}
	local function drivable(e: number): boolean
		local k = eKind[e]
		return k == K_LANE or k == K_STRAIGHT
	end
	local function chordDir(e: number): Vector3
		local d = lanePos[eTo[e]] - lanePos[eFrom[e]]
		local m = d.Magnitude
		return if m > 0.001 then d / m else Vector3.xAxis
	end

	-------------------------------------------------------------------------------------------------
	-- Segments: straight lane edges, Hermite connectors (turn / change / uturn / scene manoeuvres)
	-------------------------------------------------------------------------------------------------
	local function herm(p0: Vector3, p1: Vector3, t0: Vector3, t1: Vector3, u: number): Vector3
		local u2 = u * u
		local u3 = u2 * u
		return p0 * (2 * u3 - 3 * u2 + 1) + t0 * (u3 - 2 * u2 + u) + p1 * (-2 * u3 + 3 * u2) + t1 * (u3 - u2)
	end
	local function curveSeg(p0: Vector3, p1: Vector3, d0: Vector3, d1: Vector3, mag: number, e: number): any
		local t0, t1 = d0 * mag, d1 * mag
		local len, prev = 0, p0
		for i = 1, 6 do
			local p = herm(p0, p1, t0, t1, i / 6)
			len += (p - prev).Magnitude
			prev = p
		end
		return { curve = true, p0 = p0, p1 = p1, t0 = t0, t1 = t1, L = math.max(0.05, len), e = e, dEnd = d1 }
	end
	local function makeSeg(e: number, dIn: Vector3?, dOut: Vector3?): any
		local a, b = lanePos[eFrom[e]], lanePos[eTo[e]]
		local k = eKind[e]
		local chord = b - a
		local L = chord.Magnitude
		local cd = if L > 0.001 then chord / L else (dIn or Vector3.xAxis)
		if (k == K_TURN or k == K_CHANGE or k == K_UTURN) and dIn and dOut and L > 0.5 then
			local mag = L * (if k == K_UTURN then 1.7 elseif k == K_CHANGE then 0.6 else 1.0)
			return curveSeg(a, b, dIn, dOut, mag, e)
		end
		return { curve = false, a = a, d = cd, L = math.max(0.01, L), e = e, dEnd = cd }
	end
	local function segPoint(sg: any, s: number): Vector3
		if sg.curve then
			local u = s / sg.L
			if u < 0 then
				return sg.p0 + sg.t0.Unit * s
			elseif u > 1 then
				return sg.p1 + sg.dEnd * (s - sg.L)
			end
			return herm(sg.p0, sg.p1, sg.t0, sg.t1, u)
		end
		return sg.a + sg.d * s
	end

	-------------------------------------------------------------------------------------------------
	-- Cars
	-------------------------------------------------------------------------------------------------
	local T: any = {} -- shared with TrafficPeople
	local cars: { any } = {}
	local nextId = 0
	local rng = Random.new()
	local frameNo = 0
	local nowT = 0
	local playerPos: Vector3? = nil
	local playerVel = Vector3.zero
	local playerOnFoot = true
	local playerCarPos: Vector3? = nil
	local camPos, camLook = Vector3.zero, Vector3.zAxis
	local cosView = 0.5
	local night = false
	local stats = { spawned = 0, removed = 0, adopted = 0, honks = 0, maxCars = 0, writes = 0 }
	T.stats = stats

	local function inView(p: Vector3): boolean
		local d = p - camPos
		local m = d.Magnitude
		if m < 12 then
			return true
		end
		return d:Dot(camLook) > cosView * m
	end
	T.inView = inView

	local function chooseNext(node: number, fromE: number, car: any): number?
		local outs = outE[node]
		if not outs or #outs == 0 then
			return nil
		end
		local route = car.route
		if route and #route > 0 then
			local want = route[1]
			for _, e in outs do
				if e == want then
					table.remove(route, 1)
					return e
				end
			end
			car.route = nil -- off the forced route (should not happen): drive on freely
		end
		if #outs == 1 then
			return outs[1]
		end
		local fromKind = eKind[fromE]
		local back = eFrom[fromE]
		local total = 0
		local ws = car.wsBuf
		for i, e in outs do
			local w = wByKind[eKind[e]] or 0.5
			if fromKind == K_CHANGE and eKind[e] == K_CHANGE then
				w *= 0.05
			end
			if eTo[e] == back then
				w *= 0.01
			end
			ws[i] = w
			total += w
		end
		local r = rng:NextNumber() * total
		for i, e in outs do
			r -= ws[i]
			if r <= 0 then
				return e
			end
		end
		return outs[#outs]
	end

	local function segAfter(prev: any, e: number, nextE: number?): any
		return makeSeg(e, prev and prev.dEnd or chordDir(e), if nextE then chordDir(nextE) else nil)
	end

	local function extendPlan(car: any)
		local plan, planSeg = car.plan, car.planSeg
		while #plan < 3 do
			local lastE = plan[#plan] or car.e
			if lastE <= 0 then
				break
			end
			local node = eTo[lastE]
			if car.terminalNode == node then
				break
			end
			local e2 = chooseNext(node, lastE, car)
			if not e2 then
				break
			end
			table.insert(plan, e2)
		end
		-- geometry for every plan edge whose successor is known (curves need the exit direction)
		for i = 1, #plan do
			if not planSeg[i] then
				local nxt = plan[i + 1]
				if nxt or i == #plan and (car.terminalNode == eTo[plan[i]] or not outE[eTo[plan[i]]]) then
					planSeg[i] = segAfter(planSeg[i - 1] or car.seg, plan[i], nxt)
				else
					break
				end
			end
		end
	end

	local function segLenAt(car: any, i: number): number
		local sg = car.planSeg[i]
		if sg then
			return sg.L
		end
		local e = car.plan[i]
		return if e then eLen[e] else 0
	end

	local function pathPoint(car: any, r: number): Vector3
		local sg = car.seg
		if r < 0 then
			local pv = car.prevSeg
			if pv then
				return segPoint(pv, pv.L + r)
			end
			return segPoint(sg, r)
		end
		if r <= sg.L then
			return segPoint(sg, r)
		end
		r -= sg.L
		local planSeg = car.planSeg
		for i = 1, #planSeg do
			local ps = planSeg[i]
			if not ps then
				break
			end
			if r <= ps.L then
				return segPoint(ps, r)
			end
			r -= ps.L
			sg = ps
		end
		return segPoint(sg, sg.L + r)
	end

	local function advance(car: any)
		car.s -= car.seg.L
		car.prevSeg = car.seg
		local e = table.remove(car.plan, 1)
		local sg = table.remove(car.planSeg, 1)
		if not e then
			-- end of the road (terminal manoeuvre or a dead end): stay at the end
			car.s = car.prevSeg.L
			car.seg = car.prevSeg
			car.atEnd = true
			return false
		end
		car.e = e
		car.seg = sg or segAfter(car.prevSeg, e, car.plan[1])
		car.v0e = math.min(eSpd[e] * Cfg.SpeedFactor * car.pers, if eKind[e] == K_TURN or eKind[e] == K_UTURN then Cfg.TurnKmh / 1.08 elseif eKind[e] == K_CHANGE then Cfg.ChangeKmh / 1.08 else math.huge)
		if portal[eTo[e]] then
			car.leaving = true
		end
		extendPlan(car)
		return true
	end

	local function poseCar(car: any)
		local half = car.wb * 0.5
		local f = pathPoint(car, car.s + half)
		local r = pathPoint(car, car.s - half)
		local d = f - r
		d = Vector3.new(d.X, 0, d.Z)
		local m = d.Magnitude
		if m > 0.05 then
			car.dir = d / m
		end
		local mid = (f + r) * 0.5
		car.pos = Vector3.new(mid.X, car.y, mid.Z)
	end

	local function carCFrame(car: any): CFrame
		local p = car.pos
		local dir = car.dir
		return CFrame.lookAt(p, p + dir) * CFrame.Angles(car.pitch, 0, 0)
	end

	local KIND_LIST, KIND_TOTAL = {}, 0
	for _, kw in Cfg.Kinds do
		table.insert(KIND_LIST, kw)
		KIND_TOTAL += kw[2]
	end
	local function pickKind(): string
		local r = rng:NextNumber() * KIND_TOTAL
		for _, kw in KIND_LIST do
			r -= kw[2]
			if r <= 0 then
				return kw[1]
			end
		end
		return "sedan"
	end
	local function pickPaint(): Color3
		local c = Cfg.Paint[rng:NextInteger(1, #Cfg.Paint)]
		return Color3.fromRGB(c[1], c[2], c[3])
	end

	-- opts: { kind, color, seg (custom first segment), route (forced edges after it), terminalNode,
	-- v (start speed), y (ground height), static (scene body placed by hand, no lane yet), scene }
	local function spawnCar(e: number, s: number, opts: any?): any?
		local o = opts or {}
		local kind = o.kind or pickKind()
		local okRec, rec = pcall(Models.acquire, kind, o.color or pickPaint())
		if not okRec or not rec then
			Util.warn("Traffic", "car body failed: ", tostring(rec))
			return nil
		end
		nextId += 1
		local info = rec.info
		local car: any = {
			id = nextId,
			kind = kind,
			rec = rec,
			info = info,
			len = info.len,
			halfLen = info.len * 0.5,
			hw = info.width * 0.5,
			wb = info.len * 0.62,
			e = e,
			s = s,
			plan = {},
			planSeg = {},
			wsBuf = {},
			route = o.route,
			terminalNode = o.terminalNode,
			v = o.v or 0,
			acc = 0,
			pers = 0.88 + rng:NextNumber() * 0.24,
			odo = s,
			y = o.y or 6,
			gy = o.y or 6,
			lastGy = o.y or 6,
			pitch = 0,
			slope = 0,
			nextThink = nowT + rng:NextNumber() * (1 / Cfg.ThinkHz),
			groundAt = nowT + rng:NextNumber() * Cfg.GroundEvery,
			spawnedAt = nowT,
			movedAt = nowT,
			dir = Vector3.zAxis,
			pos = Vector3.zero,
			stopOdo = nil,
			leadGap = nil,
			leadV = 0,
			honkAt = -1e9,
			honkWait = 0,
			lamp = { head = -1, tail = -1, ind = nil },
			scene = o.scene,
			passengerWanted = o.passenger,
			writeEvery = 1,
		}
		if o.seg then
			car.seg = o.seg
			car.e = o.seg.e
			car.v0e = (o.manoeuvreKmh or 12) / 1.08
		else
			car.seg = makeSeg(e, chordDir(e), nil)
			car.v0e = math.min(eSpd[e] * Cfg.SpeedFactor * car.pers, if drivable(e) then math.huge else Cfg.TurnKmh / 1.08)
		end
		if o.firstEdge then
			car.plan[1] = o.firstEdge
		end
		extendPlan(car)
		if car.seg.curve == false and #car.planSeg > 0 then
			-- the first straight segment did not know its exit direction: fine for a lane edge
		end
		poseCar(car)
		car.cf = carCFrame(car)
		rec.root.CFrame = car.cf
		table.insert(cars, car)
		stats.spawned += 1
		if #cars > stats.maxCars then
			stats.maxCars = #cars
		end
		People.onCarSpawn(car)
		return car
	end
	T.spawnCar = spawnCar

	local function removeCar(car: any)
		if car.removed then
			return
		end
		car.removed = true
		pcall(People.onCarRemove, car)
		Models.release(car.rec)
		for i, c in cars do
			if c == car then
				table.remove(cars, i)
				break
			end
		end
		stats.removed += 1
	end
	T.removeCar = removeCar

	-- Replaces the car's path with a manoeuvre curve from where it is now to `toCF` (ground frame,
	-- LookVector = the car's heading there), then `after` edges (or stop at the end: terminal).
	function T.manoeuvre(car: any, toCF: CFrame, kmh: number, nextEdge: number?)
		local p0 = Vector3.new(car.pos.X, 6, car.pos.Z)
		local p1 = Vector3.new(toCF.Position.X, 6, toCF.Position.Z)
		local d1 = Vector3.new(toCF.LookVector.X, 0, toCF.LookVector.Z).Unit
		local dist = (p1 - p0).Magnitude
		nextId += 1
		local sg = curveSeg(p0, p1, car.dir, d1, math.max(4, dist * 0.9), -nextId)
		car.prevSeg = nil
		car.seg = sg
		car.e = sg.e
		car.s = 0
		car.atEnd = false
		car.v0e = kmh / 1.08
		table.clear(car.plan)
		table.clear(car.planSeg)
		car.route = nil
		car.terminalNode = nil
		if nextEdge then
			car.plan[1] = nextEdge
			extendPlan(car)
		else
			car.terminal = true
		end
		car.stopOdo = nil
	end
	-- A manoeuvre segment from a hand-placed frame (scene: pulling out of a bay), for spawnCar opts.seg.
	function T.curveFrom(fromCF: CFrame, toPos: Vector3, toDir: Vector3): any
		local p0 = Vector3.new(fromCF.Position.X, 6, fromCF.Position.Z)
		local d0 = Vector3.new(fromCF.LookVector.X, 0, fromCF.LookVector.Z).Unit
		local p1 = Vector3.new(toPos.X, 6, toPos.Z)
		nextId += 1
		return curveSeg(p0, p1, d0, toDir, math.max(4, (p1 - p0).Magnitude * 0.9), -nextId)
	end

	-------------------------------------------------------------------------------------------------
	-- Lane queries for scenes
	-------------------------------------------------------------------------------------------------
	local CELL = 64
	local function cellKey(cx: number, cz: number): number
		return (cx + 512) * 2048 + (cz + 512)
	end
	-- nearest point on a drivable lane edge: returns edge, s, lateral (+ = right of the lane), point
	function T.laneNear(p: Vector3, maxDist: number, dir: Vector3?, minDot: number?): (number?, number, number, Vector3?)
		local best, bestS, bestLat, bestP, bestD = nil, 0, 0, nil, maxDist
		local c0x, c0z = math.floor((p.X - maxDist - 120) / CELL), math.floor((p.Z - maxDist - 120) / CELL)
		local c1x, c1z = math.floor((p.X + maxDist + 120) / CELL), math.floor((p.Z + maxDist + 120) / CELL)
		local seen = {}
		for cx = c0x, c1x do
			for cz = c0z, c1z do
				local cell = laneGrid[cellKey(cx, cz)]
				if cell then
					for _, n in cell do
						local outs = outE[n]
						if outs then
							for _, e in outs do
								if not seen[e] and drivable(e) then
									seen[e] = true
									local a = lanePos[n]
									local d = chordDir(e)
									if not dir or d:Dot(dir) >= (minDot or 0.7) then
										local rel = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
										local s = math.clamp(rel:Dot(d), 0, eLen[e])
										local q = a + d * s
										local off = Vector3.new(p.X - q.X, 0, p.Z - q.Z)
										local dist = off.Magnitude
										if dist < bestD then
											local right = Vector3.new(-d.Z, 0, d.X)
											best, bestS, bestLat, bestP, bestD = e, s, off:Dot(right), q, dist
										end
									end
								end
							end
						end
					end
				end
			end
		end
		return best, bestS, bestLat, bestP
	end
	-- an upstream chain of drivable edges ending with `e`, at least `dist` long: returns { edges },
	-- the start s on the first edge (0) or nil
	function T.upstream(e: number, dist: number): { number }?
		local chain = { e }
		local acc = 0
		local cur = e
		for _ = 1, 30 do
			local ins = inE[eFrom[cur]]
			if not ins or #ins == 0 then
				break
			end
			local pick = nil
			for _, ie in ins do
				if drivable(ie) and eTo[ie] ~= eFrom[e] then
					pick = ie
					if rng:NextNumber() < 0.5 then
						break
					end
				end
			end
			if not pick then
				break
			end
			table.insert(chain, 1, pick)
			acc += eLen[pick]
			cur = pick
			if acc >= dist then
				return chain
			end
		end
		return if acc >= dist * 0.5 then chain else nil
	end
	-- true when no other lane runs beside this edge on its right (the kerb lane)
	function T.isKerbLane(e: number): boolean
		local a, d = lanePos[eFrom[e]], chordDir(e)
		local mid = a + d * (eLen[e] * 0.5)
		local right = Vector3.new(-d.Z, 0, d.X)
		local probe = mid + right * 11
		local e2, _, lat = T.laneNear(probe, 6, d, 0.8)
		return e2 == nil or math.abs(lat) > 5.5
	end
	T.eFrom, T.eTo, T.eLen, T.eKind, T.lanePos, T.outE, T.inE, T.chordDir, T.drivable = eFrom, eTo, eLen, eKind, lanePos, outE, inE, chordDir, drivable
	T.Nav, T.D, T.cars, T.folder, T.Cfg, T.Models, T.Util, T.Shared = Nav, D, cars, folder, Cfg, Models, Util, Shared
	T.segPoint = segPoint
	T.carCFrame = carCFrame

	-------------------------------------------------------------------------------------------------
	-- Static map cars: ParkedVehicles (scenes, templates) and TrafficVehicles (adopted)
	-------------------------------------------------------------------------------------------------
	local parked: { [Instance]: any } = {}
	T.parked = parked
	local adopted: { [Instance]: any } = {}
	local containers: { [string]: Instance } = {}
	local hiddenStatic: { [Instance]: { [BasePart]: { boolean } } } = {}

	-- local hide (Util.setHidden: LocalTransparencyModifier, batched) + no collision / query, so an
	-- invisible map car never blocks the local player
	local function hideStatic(model: Instance, hide: boolean)
		Util.setHidden(model, hide)
		if hide then
			if hiddenStatic[model] then
				return
			end
			local saved = {}
			hiddenStatic[model] = saved
			task.spawn(function()
				local n = 0
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") and hiddenStatic[model] == saved then
						saved[d] = { d.CanCollide, d.CanQuery }
						d.CanCollide = false
						d.CanQuery = false
						n += 1
						if n % 120 == 0 then
							task.wait()
						end
					end
				end
			end)
		else
			local saved = hiddenStatic[model]
			hiddenStatic[model] = nil
			if saved then
				task.spawn(function()
					local n = 0
					for p, v in saved do
						if p.Parent then
							p.CanCollide = v[1]
							p.CanQuery = v[2]
						end
						n += 1
						if n % 120 == 0 then
							task.wait()
						end
					end
				end)
			end
		end
	end
	T.hideStatic = hideStatic

	local function noteParked(m: Instance)
		if not m:IsA("Model") then
			return
		end
		local kind = m:GetAttribute("VehicleKind")
		if type(kind) ~= "string" then
			return
		end
		if not parked[m] then
			parked[m] = { model = m, kind = kind }
		end
		Models.offer(m)
	end

	local function adopt(m: Instance)
		if not m:IsA("Model") or adopted[m] then
			return
		end
		local kind = m:GetAttribute("VehicleKind")
		if type(kind) ~= "string" then
			return
		end
		local frame = Models.frameOf(m)
		if not frame then
			return
		end
		Models.offer(m)
		adopted[m] = { model = m, kind = kind, frame = frame, done = false }
	end

	-- adoption runs from the think loop (player near enough, template ready or not)
	local function processAdoptions()
		if not playerPos then
			return
		end
		for m, a in adopted do
			if not a.done and m.Parent then
				local d = (a.frame.Position - playerPos).Magnitude
				if d < 320 then
					a.done = true
					hideStatic(m, true)
					stats.adopted += 1
					if Models.KINDS[a.kind] then
						local look = Vector3.new(a.frame.LookVector.X, 0, a.frame.LookVector.Z).Unit
						local e, s, lat = T.laneNear(a.frame.Position, 9, look, 0.85)
						if e and math.abs(lat) < 6 and #cars < (T.cap or 12) + 4 then
							local blocked = false
							local p = lanePos[eFrom[e]] + chordDir(e) * s
							for _, c in cars do
								if (c.pos - p).Magnitude < 14 then
									blocked = true
									break
								end
							end
							if not blocked then
								spawnCar(e, s, { kind = a.kind, color = Models.paintOf(m), y = a.frame.Position.Y, v = 0 })
							end
						end
					end
				end
			elseif a.done and not m.Parent then
				adopted[m] = nil -- streamed out: a fresh copy is adopted again when it comes back
				hiddenStatic[m] = nil
			end
		end
	end

	local function watchContainer(name: string, onChild: (Instance) -> ())
		local root = workspace:FindFirstChild("Gwangalli")
		local roads = root and root:FindFirstChild("roads")
		local c = roads and roads:FindFirstChild(name)
		if not c or containers[name] == c then
			return
		end
		containers[name] = c
		c.ChildAdded:Connect(function(ch)
			local ok, err = pcall(onChild, ch)
			if not ok then
				Util.warn("Traffic", err)
			end
		end)
		c.ChildRemoved:Connect(function(ch)
			if name == "ParkedVehicles" then
				local rec = parked[ch]
				if rec and not rec.scene then
					parked[ch] = nil
				end
			end
		end)
		for _, ch in c:GetChildren() do
			pcall(onChild, ch)
		end
	end
	local function scanContainers()
		watchContainer("ParkedVehicles", function(ch)
			noteParked(ch)
			if ch:IsA("Model") and ch:GetAttribute("VehicleKind") == nil then
				-- nested groups (DeliveryScooters / StreetScenes): templates only
				for _, g in ch:GetChildren() do
					if g:IsA("Model") and g:GetAttribute("VehicleKind") then
						Models.offer(g)
					end
				end
			end
		end)
		watchContainer("TrafficVehicles", adopt)
		-- the club forecourt / GS25 lot cars also make good templates
		if not Models.hasTemplate("taxi") or not Models.hasTemplate("truck") or not Models.hasTemplate("compact") then
			local root = workspace:FindFirstChild("Gwangalli")
			for _, path in { { "convenience", "GS25 광안리점" }, { "club", "CLUB OCEAN 광안", "Forecourt" } } do
				local node: Instance? = root
				for _, n in path do
					node = node and node:FindFirstChild(n)
				end
				if node then
					for _, ch in node:GetChildren() do
						if ch:IsA("Model") and ch:GetAttribute("VehicleKind") then
							Models.offer(ch)
						end
					end
				end
			end
		end
	end
	T.parkedFrame = function(rec: any): CFrame?
		if not rec.frame or rec.frameAt ~= rec.model then
			rec.frame = Models.frameOf(rec.model)
			rec.frameAt = rec.model
		end
		return rec.frame
	end

	-------------------------------------------------------------------------------------------------
	-- Ground (one raycast per car per GroundEvery s)
	-------------------------------------------------------------------------------------------------
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	local excludeList: { Instance } = { folder }
	local function refreshExclude()
		table.clear(excludeList)
		table.insert(excludeList, folder)
		for _, plr in Players:GetPlayers() do
			if plr.Character then
				table.insert(excludeList, plr.Character)
			end
		end
		for _, n in { "GwangalliStreetLife", "GwangalliTaxis", "GwangalliPlayerCars" } do
			local f = workspace:FindFirstChild(n)
			if f then
				table.insert(excludeList, f)
			end
		end
		rayParams.FilterDescendantsInstances = excludeList
	end
	refreshExclude()
	T.rayParams = rayParams

	local function sampleGround(car: any)
		local p = car.pos
		local res = workspace:Raycast(Vector3.new(p.X, car.y + 4, p.Z), Vector3.new(0, -10, 0), rayParams)
		if res then
			local y = res.Position.Y
			if math.abs(y - car.y) < 4 then
				car.gy = y
			end
		end
	end

	-------------------------------------------------------------------------------------------------
	-- Think (ThinkHz per car)
	-------------------------------------------------------------------------------------------------
	local peds: { Vector3 } = {}
	local pedIsPlayer: { boolean } = {}
	local pedCount = 0
	local function gatherPeds()
		pedCount = 0
		if not playerPos then
			return
		end
		local lim = Cfg.PedDist + 40
		local lim2 = lim * lim
		local function add(p: Vector3, isPlayer: boolean)
			local d = p - playerPos
			if d.X * d.X + d.Z * d.Z < lim2 then
				pedCount += 1
				peds[pedCount] = p
				pedIsPlayer[pedCount] = isPlayer
			end
		end
		if playerOnFoot and playerPos then
			add(playerPos, true)
		end
		local sl = workspace:FindFirstChild("GwangalliStreetLife")
		if sl then
			for _, m in sl:GetChildren() do
				if m:IsA("Model") then
					local r = m.PrimaryPart
					if r then
						add(r.Position, false)
					end
				end
			end
		end
		for _, p in People.walkers() do
			add(p, false)
		end
		for _, plr in Players:GetPlayers() do
			if plr ~= player then
				local ch = plr.Character
				local r = ch and ch.PrimaryPart
				if r then
					add(r.Position, false)
				end
			end
		end
	end

	local function think(car: any, now: number)
		local v = car.v
		local dir = car.dir
		local right = Vector3.new(-dir.Z, 0, dir.X)
		local pos = car.pos
		local segStartOdo = car.odo - car.s
		-- stop lines ahead along the path
		car.stopOdo = nil
		car.waitSignal = false
		local slowTo = nil
		if not car.terminal and not car.parked then
			local look = math.max(45, v * v / (2 * Cfg.Brake) + 30)
			local dist = car.seg.L - car.s
			local acc = segStartOdo + car.seg.L
			local nodeE = car.e
			local i = 0
			while dist < look and nodeE do
				local node = if nodeE > 0 then eTo[nodeE] else nil
				local nxt = car.plan[i + 1]
				if node and nxt then
					local st = laneStop[node]
					if st then
						local sig = st[1]
						if sig and sig > 0 then
							local group = signals[sig]
							local state = if group then Shared.vehicleState(group, st[2], workspace:GetServerTimeNow()) else "green"
							local toLine = dist - car.halfLen - Cfg.StopLine
							if toLine > -0.5 then
								if state == "red" or (state == "amber" and toLine > v * v / (2 * Cfg.Brake) + 1.5) then
									car.stopOdo = acc
									car.waitSignal = true
									break
								end
							end
						elseif dist < 22 then
							slowTo = 11 -- unsignalised: slow, look, go (people in the way stop it below)
						end
					end
				end
				i += 1
				nodeE = car.plan[i]
				if not nodeE then
					break
				end
				local L = segLenAt(car, i)
				dist += L
				acc += L
			end
		end
		if car.terminal then
			car.stopOdo = segStartOdo + car.seg.L + car.halfLen + Cfg.StopLine
		end
		car.slowTo = slowTo
		-- the car ahead: same path (exact distance) or across it (geometric)
		local bestGap, bestV, bestCar, bestPath = math.huge, 0, nil, false
		local look = math.max(30, v * 2.6 + 18)
		for _, o in cars do
			if o ~= car then
				local gapPath = nil
				if o.e == car.e and o.s > car.s then
					gapPath = o.s - car.s
				elseif o.e > 0 then
					local d0 = car.seg.L - car.s
					for k = 1, #car.plan do
						if car.plan[k] == o.e then
							gapPath = d0 + o.s
							break
						end
						d0 += segLenAt(car, k)
						if d0 > look then
							break
						end
					end
				end
				if gapPath then
					local g = gapPath - car.halfLen - o.halfLen
					if g < bestGap then
						bestGap, bestV, bestCar, bestPath = g, o.v, o, true
					end
				else
					local d = o.pos - pos
					local f = d.X * dir.X + d.Z * dir.Z
					if f > 0 and f < look then
						local lat = math.abs(d.X * right.X + d.Z * right.Z)
						local band = (car.hw + o.hw) * 0.8
						if lat < band and not (car.ignoreCar == o and now < car.ignoreUntil) then
							local g = f - car.halfLen - o.halfLen * 0.8
							if g < bestGap then
								local along = o.dir:Dot(dir)
								bestGap, bestV, bestCar, bestPath = g, o.v * math.max(0, along), o, false
							end
						end
					end
				end
			end
		end
		-- deadlock guard: two cars blocking each other across a junction -> the younger one creeps on
		if bestCar and not bestPath and v < 0.3 then
			car.crossWait = (car.crossWait or 0) + 1 / Cfg.ThinkHz
			if car.crossWait > 4 and car.id > bestCar.id then
				car.ignoreCar, car.ignoreUntil = bestCar, now + 4
				car.crossWait = 0
			end
		else
			car.crossWait = 0
		end
		-- the player's car
		if playerCarPos then
			local d = playerCarPos - pos
			local f = d.X * dir.X + d.Z * dir.Z
			if f > 0 and f < look then
				local lat = math.abs(d.X * right.X + d.Z * right.Z)
				if lat < car.hw + 3.6 then
					local g = f - car.halfLen - 8
					if g < bestGap then
						local pv = playerVel.X * dir.X + playerVel.Z * dir.Z
						bestGap, bestV, bestCar = g, math.max(0, pv), nil
					end
				end
			end
		end
		-- people in the lane ahead (only near the player: nobody sees the others)
		local blockedByPlayer = false
		if playerPos and pedCount > 0 then
			local dp = pos - playerPos
			if dp.X * dp.X + dp.Z * dp.Z < Cfg.PedDist * Cfg.PedDist then
				local reach = car.halfLen + v * v / (2 * Cfg.Brake) + Cfg.PedLook
				local side = car.hw + Cfg.PedSide
				for i = 1, pedCount do
					local p = peds[i]
					local d = p - pos
					if math.abs(d.Y) < 8 then
						local f = d.X * dir.X + d.Z * dir.Z
						if f > car.halfLen * 0.4 and f < reach then
							local lat = math.abs(d.X * right.X + d.Z * right.Z)
							if lat < side then
								local g = f - car.halfLen - 1.2
								if g < bestGap then
									bestGap, bestV, bestCar = g, 0, nil
								end
								if pedIsPlayer[i] then
									blockedByPlayer = true
								end
							end
						end
					end
				end
			end
		end
		if bestGap < math.huge then
			car.leadGap, car.leadV = bestGap, bestV
		else
			car.leadGap = nil
		end
		car.leadCar = bestCar
		-- honk once at the player standing in the lane
		if blockedByPlayer and v < 0.6 then
			car.honkWait += 1 / Cfg.ThinkHz
			if car.honkWait > Cfg.HonkAfter and now - car.honkAt > Cfg.HonkCooldown then
				car.honkAt = now
				car.honkWait = -2
				stats.honks += 1
				Models.play(car.rec.root, Cfg.Sounds.Horn, Cfg.Sounds.HornSpeed, 0.7)
				People.onHonk(car)
			end
		elseif not blockedByPlayer then
			car.honkWait = 0
		end
		-- indicators before a turn / lane change within 35 studs (scenes set car.indForce)
		local ind = car.indForce
		if ind == nil and not car.parked then
			local dist = car.seg.L - car.s
			local k = car.e > 0 and eKind[car.e] or nil
			local function sideOf(e: number, sg: any?): string?
				local kk = eKind[e]
				if kk ~= K_TURN and kk ~= K_CHANGE and kk ~= K_UTURN then
					return nil
				end
				local d0 = if sg and sg.curve then sg.t0.Unit else chordDir(e)
				local d1 = if sg then sg.dEnd else chordDir(e)
				local cross = d0.X * d1.Z - d0.Z * d1.X
				if kk == K_CHANGE then
					local c = chordDir(e)
					cross = d0.X * c.Z - d0.Z * c.X
				end
				if math.abs(cross) < 0.05 then
					return nil
				end
				return if cross > 0 then "R" else "L"
			end
			if k and (k == K_TURN or k == K_CHANGE or k == K_UTURN) then
				ind = sideOf(car.e, car.seg)
			else
				for i = 1, math.min(2, #car.plan) do
					if dist > 35 then
						break
					end
					ind = sideOf(car.plan[i], car.planSeg[i])
					if ind then
						break
					end
					dist += segLenAt(car, i)
				end
			end
		end
		car.ind = ind
	end

	-------------------------------------------------------------------------------------------------
	-- Spawner
	-------------------------------------------------------------------------------------------------
	local candCellKey: number? = nil
	local candNodes: { number } = {}
	local function refreshCandidates(p: Vector3, maxR: number)
		local key = cellKey(math.floor(p.X / CELL), math.floor(p.Z / CELL))
		if key == candCellKey then
			return
		end
		candCellKey = key
		table.clear(candNodes)
		local c0x, c0z = math.floor((p.X - maxR - CELL) / CELL), math.floor((p.Z - maxR - CELL) / CELL)
		local c1x, c1z = math.floor((p.X + maxR + CELL) / CELL), math.floor((p.Z + maxR + CELL) / CELL)
		for cx = c0x, c1x do
			for cz = c0z, c1z do
				local cell = laneGrid[cellKey(cx, cz)]
				if cell then
					for _, n in cell do
						local outs = outE[n]
						if outs then
							for _, e in outs do
								if drivable(e) and eLen[e] > 8 then
									table.insert(candNodes, n)
									break
								end
							end
						end
					end
				end
			end
		end
	end

	local function trySpawn(capNow: number)
		if not playerPos or #cars >= capNow then
			return
		end
		local tc = Util.tierConfig(Cfg)
		local maxR = Util.budget(Cfg.SpawnMax)
		refreshCandidates(playerPos, maxR)
		if #candNodes == 0 then
			return
		end
		local minR = Cfg.SpawnMin
		local _ = tc
		for _ = 1, 10 do
			local n = candNodes[rng:NextInteger(1, #candNodes)]
			local p = lanePos[n]
			local d = (p - playerPos).Magnitude
			if d >= minR and d <= maxR and (d >= Cfg.SpawnViewMin or not inView(p)) and not portal[n] or (portal[n] and d >= minR and not inView(p)) then
				local free = true
				for _, c in cars do
					if (c.pos - p).Magnitude < Cfg.SpawnGap then
						free = false
						break
					end
				end
				if free then
					local outs = outE[n]
					local choices = {}
					for _, e in outs do
						if drivable(e) and eLen[e] > 8 then
							table.insert(choices, e)
						end
					end
					if #choices > 0 then
						local e = choices[rng:NextInteger(1, #choices)]
						local s = math.min(eLen[e] * 0.3, 6)
						local v0 = eSpd[e] * Cfg.SpeedFactor
						local car = spawnCar(e, s, { v = if inView(p) then v0 * 0.85 else v0 * 0.6, y = 6 })
						if car then
							car.passengerWanted = rng:NextNumber() < (if car.kind == "taxi" then 0.4 else Cfg.PassengerShare)
						end
						return
					end
				end
			end
		end
	end

	-------------------------------------------------------------------------------------------------
	-- Lamps (cars within LampDist; writes only on change)
	-------------------------------------------------------------------------------------------------
	local function updateLamps(car: any, now: number, near: boolean)
		local head, tail = 0, 0
		if not car.parked then
			head = if night then 2 else 1
			local braking = car.acc < -2.5 or (car.v < 0.4 and (car.leadGap ~= nil or car.stopOdo ~= nil or car.hold))
			tail = if braking then 2 elseif night then 1 else 0
		end
		if car.lampOverride then
			head, tail = car.lampOverride[1], car.lampOverride[2]
		end
		local ind = if near then car.ind else nil
		local blinkOn = ind ~= nil and math.floor(now * Cfg.BlinkHz * 2) % 2 == 0
		local sign = car.kind == "taxi" and night and not car.hired
		Models.setLamps(car.rec, head, tail, ind, blinkOn, sign)
	end

	-------------------------------------------------------------------------------------------------
	-- Main loop
	-------------------------------------------------------------------------------------------------
	local moveParts: { BasePart } = {}
	local moveCFs: { CFrame } = {}
	local thinkInterval = 1 / Cfg.ThinkHz
	local spawnAt, adoptAt, scanAt, excludeAt, debugAt, despawnAt = 0, 0, 0, 0, 0, 0
	local running = true
	local lastPlayerPos: Vector3? = nil

	People.init(ctx, T)

	local function capNow(): number
		local forced = workspace:GetAttribute("GwangalliTrafficCap")
		if type(forced) == "number" then
			return math.clamp(math.floor(forced), 0, 40)
		end
		local c = Util.budget(Cfg.Cap)
		local clock = DayNight.clock and DayNight.clock() or 12
		if clock < 6 then
			c = math.floor(c * Cfg.NightShare + 0.5)
		end
		return c
	end

	local function shutdown()
		running = false
		for i = #cars, 1, -1 do
			removeCar(cars[i])
		end
		People.shutdown()
		for m in hiddenStatic do
			hideStatic(m, false)
		end
		for m in adopted do
			adopted[m] = nil
		end
	end

	local function step(dt: number)
		frameNo += 1
		local now = os.clock()
		nowT = now
		T.now = now
		T.frame = frameNo
		dt = math.min(dt, 0.1)
		-- player / camera
		local ch = player.Character
		local hrp = ch and ch.PrimaryPart
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local cam = workspace.CurrentCamera
		if cam then
			local cf = cam.CFrame
			camPos, camLook = cf.Position, cf.LookVector
			local vp = cam.ViewportSize
			local aspect = if vp.Y > 0 then vp.X / vp.Y else 1.6
			local vfov = math.rad(cam.FieldOfView)
			local hfov = 2 * math.atan(math.tan(vfov / 2) * aspect)
			cosView = math.cos(math.min(math.rad(85), hfov / 2 + math.rad(12)))
		end
		if hrp then
			local p = hrp.Position
			if lastPlayerPos and dt > 0 then
				playerVel = (p - lastPlayerPos) / dt
			end
			lastPlayerPos = p
			playerPos = p
			local seat = hum and hum.SeatPart
			playerOnFoot = seat == nil
			playerCarPos = if seat then p else nil
		else
			playerPos = camPos
			playerOnFoot = false
			playerCarPos = nil
		end
		T.playerPos, T.playerOnFoot, T.camPos, T.camLook = playerPos, playerOnFoot, camPos, camLook
		night = DayNight.isNight()
		T.night = night

		-- slow housekeeping
		if now >= scanAt then
			scanAt = now + 2
			scanContainers()
		end
		if now >= excludeAt then
			excludeAt = now + 3
			refreshExclude()
		end
		if now >= adoptAt then
			adoptAt = now + 0.5
			processAdoptions()
		end
		local cap = capNow()
		T.cap = cap
		if now >= spawnAt then
			spawnAt = now + Cfg.SpawnEvery
			trySpawn(cap)
		end
		local thinkRound = false
		if now >= (T.pedAt or 0) then
			T.pedAt = now + thinkInterval
			gatherPeds()
			thinkRound = true
		end
		local _ = thinkRound
		-- despawn checks (2 Hz)
		if now >= despawnAt and playerPos then
			despawnAt = now + 0.5
			local far = Util.budget(Cfg.Despawn)
			for i = #cars, 1, -1 do
				local car = cars[i]
				if not car.scene then
					local d = (car.pos - playerPos).Magnitude
					local vis = inView(car.pos)
					local stuck = car.v < 0.2 and not car.waitSignal and now - car.movedAt > Cfg.StuckDespawn
					if d > far or (d > Cfg.DespawnOff and not vis) or (car.atEnd and not vis and d > 60) or (stuck and not vis and d > 40) or (car.parked and not vis and d > 100 and now - (car.parkedAt or now) > 3) or (car.parked and now - (car.parkedAt or now) > Cfg.ParkedKeep and not vis) or #cars > cap + 6 and not vis then
						removeCar(car)
					end
				end
			end
		end

		-- cars
		table.clear(moveParts)
		table.clear(moveCFs)
		local nearW2 = Cfg.NearWrite * Cfg.NearWrite
		local lampD2 = Cfg.LampDist * Cfg.LampDist
		for i = #cars, 1, -1 do
			local car = cars[i]
			if car.removed then
				continue
			end
			if now >= car.nextThink then
				car.nextThink = now + thinkInterval
				local ok, err = pcall(think, car, now)
				if not ok then
					Util.warn("Traffic", "think: ", err)
				end
				-- ground
				if now >= car.groundAt then
					car.groundAt = now + Cfg.GroundEvery
					if playerPos and (car.pos - playerPos).Magnitude < Cfg.GroundDist and car.v > 0.2 then
						local y0 = car.gy
						sampleGround(car)
						local moved = car.v * Cfg.GroundEvery
						if moved > 1 then
							car.slope = math.clamp((car.gy - y0) / moved, -0.25, 0.25)
						end
					end
				end
			end
			local moving = false
			if not car.parked and not car.static then
				-- intelligent driver model
				local v = car.v
				local v0 = car.v0e or 10
				if car.slowTo then
					v0 = math.min(v0, car.slowTo)
				end
				local A, B = Cfg.Accel, Cfg.Brake
				local ratio = v / math.max(1, v0)
				local a = A * (1 - ratio * ratio * ratio * ratio)
				local gap = car.leadGap
				local lv = car.leadV
				if car.stopOdo then
					local g = car.stopOdo - car.odo - car.halfLen - Cfg.StopLine
					if gap == nil or g < gap then
						gap, lv = g, 0
					end
				end
				if car.hold then
					gap, lv = 0, 0
				end
				if gap then
					local dv = v - lv
					local sStar = Cfg.MinGap + math.max(0, v * Cfg.Headway + v * dv / (2 * math.sqrt(A * B)))
					local g = math.max(0.05, gap)
					a -= A * (sStar / g) * (sStar / g)
					if gap <= 0.1 then
						a = math.min(a, -Cfg.HardBrake)
					end
				end
				a = math.clamp(a, -Cfg.HardBrake, A)
				v = math.max(0, v + a * dt)
				if gap and gap <= 0.1 and v < 1.5 then
					v = 0
				end
				car.v, car.acc = v, a
				if v > 0.01 then
					local ds = v * dt
					car.s += ds
					car.odo += ds
					if car.leadGap then
						car.leadGap -= (v - car.leadV) * dt
					end
					local guard = 0
					while car.s > car.seg.L and guard < 4 do
						guard += 1
						if not advance(car) then
							break
						end
					end
					car.movedAt = now
					moving = true
				end
			end
			-- body motion: ground height, slope, brake dive / squat
			local yTarget = car.gy
			local dy = yTarget - car.y
			if math.abs(dy) > 0.01 then
				car.y += dy * math.min(1, dt * 5)
				moving = true
			end
			local pitchTarget = -math.atan(car.slope) * 0.9 + math.clamp(-car.acc * 0.0022, -0.03, 0.025)
			if car.parked or car.v < 0.05 then
				pitchTarget = -math.atan(car.slope) * 0.9
			end
			local dp = pitchTarget - car.pitch
			if math.abs(dp) > 0.0005 then
				car.pitch += dp * math.min(1, dt * 4)
				moving = true
			end
			if moving or car.forceWrite then
				poseCar(car)
				-- write LOD
				local d = car.pos - camPos
				local d2 = d.X * d.X + d.Z * d.Z
				local vis = inView(car.pos)
				local every = if not vis then Cfg.OffEvery elseif d2 > nearW2 then Cfg.FarEvery else 1
				if car.forceWrite or every == 1 or (frameNo + car.id) % every == 0 then
					car.forceWrite = false
					local cf = carCFrame(car)
					car.cf = cf
					car.wroteFrame = frameNo
					table.insert(moveParts, car.rec.root)
					table.insert(moveCFs, cf)
				end
			end
			-- lamps
			if playerPos then
				local dl = car.pos - playerPos
				local dl2 = dl.X * dl.X + dl.Z * dl.Z
				if dl2 < lampD2 then
					updateLamps(car, now, dl2 < 140 * 140)
				end
			end
		end
		-- people (seated rigs follow their cars, walkers, animation LOD, scenes)
		local okP, errP = pcall(People.step, dt, now, moveParts, moveCFs)
		if not okP then
			Util.warn("Traffic", "people: ", errP)
		end
		if #moveParts > 0 then
			stats.writes += #moveParts
			local ok = pcall(workspace.BulkMoveTo, workspace, moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
			if not ok then
				for k, p in moveParts do
					p.CFrame = moveCFs[k]
				end
			end
		end
		if now >= debugAt then
			debugAt = now + (Cfg.DebugEvery or 5)
			if workspace:GetAttribute("GwangalliTrafficDebug") == true then
				local ps = People.stats()
				print(string.format("[GwangalliTraffic] cars %d/%d (spawned %d, removed %d, adopted %d, honks %d) rigs %d/%d scenes %d (%s) bodies %d clones %d reused %d basic %d templates %d",
					#cars, cap, stats.spawned, stats.removed, stats.adopted, stats.honks, ps.inUse, ps.built, ps.scenes, ps.sceneKinds, Models.stats.clones, Models.stats.clones, Models.stats.reused, Models.stats.fallback, Models.stats.templates))
			end
		end
	end

	local conn: RBXScriptConnection? = nil
	local function setRunning(on: boolean)
		if on and not conn then
			running = true
			conn = RunService.Heartbeat:Connect(function(dt)
				local ok, err = pcall(step, dt)
				if not ok then
					Util.warn("Traffic", err)
				end
			end)
		elseif not on and conn then
			conn:Disconnect()
			conn = nil
			shutdown()
		end
	end
	setRunning(workspace:GetAttribute("GwangalliTrafficOff") ~= true)
	workspace:GetAttributeChangedSignal("GwangalliTrafficOff"):Connect(function()
		setRunning(workspace:GetAttribute("GwangalliTrafficOff") ~= true)
	end)
	local _ = running
	T.statsAll = function()
		return stats, People.stats(), Models.stats
	end
	-- read-only debug view for tests / tools (cars, people, scenes)
	local api = Instance.new("BindableFunction")
	api.Name = "GwangalliTrafficQuery"
	api.OnInvoke = function(what: string?)
		if what == "cars" then
			local out = {}
			for _, c in cars do
				table.insert(out, {
					id = c.id,
					kind = c.kind,
					pos = c.pos,
					v = c.v,
					e = c.e,
					waitSignal = c.waitSignal,
					stopOdo = c.stopOdo,
					odo = c.odo,
					halfLen = c.halfLen,
					leadGap = c.leadGap,
					driver = c.driver ~= nil,
					passenger = c.passenger ~= nil,
					scene = c.scene and c.scene.kind or nil,
					parked = c.parked == true,
					basic = c.rec.basic == true,
					parts = c.rec.parts,
					honkAt = c.honkAt,
					ind = c.ind,
				})
			end
			return out
		elseif what == "stats" then
			local ps = People.stats()
			return { cars = #cars, cap = T.cap, spawned = stats.spawned, removed = stats.removed, adopted = stats.adopted, honks = stats.honks, maxCars = stats.maxCars, writes = stats.writes, people = ps, models = Models.stats }
		elseif what == "scenes" then
			return People.sceneInfo()
		end
		return nil
	end
	api.Parent = folder
	T.api = api
end

return Cars
