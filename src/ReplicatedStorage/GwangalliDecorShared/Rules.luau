--!strict
-- GwangalliDecorShared/Rules: placement validation of one piece (or a group) in a home, shared by the
-- server (final) and the client (live ghost tint). Pure: works on Unit.scan's index + an item index.
--   Rules.newIndex() -> idx { items = { [uid] = entry }, version }
--   Rules.entry(rec) -> entry (unit-frame boxes, tops, bounds) | nil      Rules.add / remove (idx)
--   Rules.support(U, idx, kind, x, z, yMax, ignore?, extra?) -> (top?, src?)
--   Rules.check(U, idx, cand, opts) -> (ok, code?, arg?, fixed?)
--       cand = { i, x, y, z, r }  (unit frame; y = bottom of the piece, r = yaw degrees)
--       opts = { ignore = {[uid]=true}, overlap = bool (겹치기 허용), people = {Vector3}, isNew = bool,
--                caps = {items, parts}, counts = {items, parts}, extra = {entries}, noPath = bool }
--       fixed = { x, y, z, r, lift, level, room } (snapped values the server stores)
--   Rules.checkGroup(U, idx, list, opts) -> (ok, code?, arg?, fixedList?, failIndex?)

local Config = require(script.Parent:WaitForChild("Config"))
local Geometry = require(script.Parent:WaitForChild("Geometry"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))
local Unit = require(script.Parent:WaitForChild("Unit"))
local Path = require(script.Parent:WaitForChild("Path"))

local Rules = {}

local finite = Geometry.finite
local overlapFast = Geometry.overlapFast

-------------------------------------------------------------------------------------------------
-- Item index
-------------------------------------------------------------------------------------------------
function Rules.newIndex(): any
	return { items = {}, version = 0 }
end

-- unit-frame geometry of a placed record (or a candidate)
function Rules.entry(rec: any): any?
	local def = Catalog.get(rec.i)
	if not def then
		return nil
	end
	local pose = Geometry.pose(rec.x, rec.y, rec.z, rec.r or 0)
	local boxes = {}
	for _, b in Catalog.boxes(rec.i) do
		table.insert(boxes, Geometry.prime(Geometry.obb(pose * b.cf, b.half)))
	end
	local tops = {}
	for _, t in Catalog.tops(rec.i) do
		local b = Geometry.prime(Geometry.obb(pose * t.cf, t.half))
		table.insert(tops, { box = b, y = b.hi.Y })
	end
	local cf, half = Catalog.box(rec.i)
	local bound = Geometry.prime(Geometry.obb(pose * cf, half))
	if def.place == "rug" then
		-- a rug carries pieces (and other rugs) on its full height, inlays included
		tops = { { box = bound, y = bound.hi.Y } }
	end
	return {
		u = rec.u,
		i = rec.i,
		kind = def.place,
		pose = pose,
		boxes = boxes,
		tops = tops,
		bound = bound,
		parts = Catalog.partCount(rec.i),
		lights = Catalog.lightCount(rec.i),
		cat = def.cat,
	}
end

function Rules.add(idx: any, rec: any): any?
	local e = Rules.entry(rec)
	if e then
		idx.items[rec.u] = e
		idx.version += 1
	end
	return e
end

function Rules.remove(idx: any, uid: number)
	if idx.items[uid] then
		idx.items[uid] = nil
		idx.version += 1
	end
end

-- uids standing on the piece uid (anything whose bottom rests on one of its tops)
function Rules.standingOn(idx: any, uid: number): { number }
	local base = idx.items[uid]
	local out = {}
	if not base or #base.tops == 0 then
		return out
	end
	for u, e in idx.items do
		if u ~= uid and e.kind ~= "wall" and e.kind ~= "ceiling" then
			local p = e.pose.Position
			for _, t in base.tops do
				if math.abs(p.Y - t.y) < 0.08 and Geometry.pointInXZ(t.box, p, 0.02) then
					table.insert(out, u)
					break
				end
			end
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Supports
-------------------------------------------------------------------------------------------------
-- highest surface at (x, z) whose top is at or below yMax. kind "rug" only takes floors + rugs.
-- src = { kind = "floor" | "solid" | "item", floor?, solid?, uid?, level }
function Rules.support(U: any, idx: any, kind: string, x: number, z: number, yMax: number, ignore: { [number]: boolean }?, extra: { any }?): (number?, any?)
	local p = Vector3.new(x, 0, z)
	local best: number? = nil
	local src: any = nil
	local lim = yMax + 1e-3
	for _, f in U.floors do
		if f.top <= lim and (not best or f.top > best) and Geometry.pointInXZ(f.box, p, 0.01) then
			best, src = f.top, { kind = "floor", floor = f, level = f.level }
		end
	end
	if kind ~= "rug" then
		for _, s in U.solids do
			local t = s.top
			if t and t <= lim and (not best or t > best) and Geometry.pointInXZ(s.box, p, -0.02) then
				best, src = t, { kind = "solid", solid = s }
			end
		end
	end
	local function scan(e: any, u: any)
		if kind == "rug" and e.kind ~= "rug" then
			return
		end
		for _, t in e.tops do
			if t.y <= lim and (not best or t.y > best) and Geometry.pointInXZ(t.box, p, -0.01) then
				best, src = t.y, { kind = "item", uid = u, entry = e }
			end
		end
	end
	for u, e in idx.items do
		if not (ignore and ignore[u]) then
			scan(e, u)
		end
	end
	if extra then
		for _, e in extra do
			scan(e, e.u)
		end
	end
	if src and not src.level then
		src.level = Unit.levelAt(U, best :: number)
	end
	return best, src
end

-- the wall face the back of a wall piece rests against (unit frame), nearest first
local function wallFace(U: any, backCentre: Vector3, backDir: Vector3, maxDist: number): (any?, number)
	local bestF, bestS = nil, math.huge
	for _, w in U.walls do
		for _, f in w.faces do
			if f.n:Dot(backDir) < -0.96 then
				local rel = backCentre - f.c
				local s = rel:Dot(f.n)
				if s > -0.35 and s < maxDist and math.abs(s) < math.abs(bestS) then
					local u = rel:Dot(f.u)
					if math.abs(u) <= f.hu + 0.05 and math.abs(rel.Y) <= f.hv + 0.05 then
						bestF, bestS = f, s
					end
				end
			end
		end
	end
	return bestF, bestS
end

local function onAnyFace(U: any, p: Vector3, n: Vector3): boolean
	for _, w in U.walls do
		for _, f in w.faces do
			if f.n:Dot(n) > 0.96 then
				local rel = p - f.c
				if math.abs(rel:Dot(f.n)) < 0.2 and math.abs(rel:Dot(f.u)) <= f.hu + 0.04 and math.abs(rel.Y) <= f.hv + 0.04 then
					return true
				end
			end
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- Check
-------------------------------------------------------------------------------------------------
local function fail(code: string, arg: any?): (boolean, string?, any?, any?)
	return false, code, arg, nil
end

function Rules.check(U: any, idx: any, cand: any, opts: any?): (boolean, string?, any?, any?)
	local o = opts or {}
	local def = Catalog.get(cand.i)
	if not def then
		return fail("unknown")
	end
	local x, y, z, r = cand.x, cand.y, cand.z, cand.r
	if not (finite(x) and finite(y) and finite(z) and finite(r)) then
		return fail("bad")
	end
	if math.abs(x) > Config.HOME_HALF or math.abs(z) > Config.HOME_HALF or y < Config.HOME_Y[1] or y > Config.HOME_Y[2] then
		return fail("outside")
	end
	r = Geometry.wrapYaw(r)
	local near15 = Geometry.snapYaw(r, 15)
	if math.abs(near15 - r) < 0.5 then
		r = near15
	end
	if o.isNew and o.caps and o.counts then
		if o.counts.items + 1 > o.caps.items then
			return fail("cap", o.caps.items)
		end
		if o.counts.parts + Catalog.partCount(cand.i) > o.caps.parts then
			return fail("parts")
		end
	end
	local kind = def.place
	local b = Catalog.bounds(cand.i)
	local ignore = o.ignore
	local extra = o.extra
	local lift = 0
	local level = 1
	local supportSrc: any = nil
	local floorY = 0

	if kind == "floor" or kind == "surface" or kind == "rug" then
		local top, src = Rules.support(U, idx, kind, x, z, y + Config.SUPPORT_TOL, ignore, extra)
		if not top then
			if Unit.floorTopAt(U, x, z, 1e6) then
				return fail("floating")
			end
			return fail("outside")
		end
		supportSrc = src
		lift = y - top
		if lift < Config.SUPPORT_TOL or kind == "rug" then
			y = top + (if kind == "rug" and src.kind == "item" then 0.004 else 0)
			lift = 0
		elseif lift > Config.MAX_LIFT then
			return fail("tooHigh")
		end
		if src.kind == "solid" and src.solid.stair then
			return fail("stair")
		end
		level = src.level or Unit.levelAt(U, top)
		local f = Unit.floorAt(U, x, z, top + 0.01)
		floorY = if f then f.top else top
		if f then
			level = f.level
		end
		-- every footprint corner must stand over a floor of the same level (inside the home)
		local pose = Geometry.pose(x, y, z, r)
		local cf, half = Catalog.box(cand.i)
		local foot = Geometry.obb(pose * cf, half)
		for _, c in Geometry.footCorners(foot, 0.15) do
			local fc = Unit.floorAt(U, c.X, c.Z, y + 0.05)
			if not fc or fc.level ~= level then
				return fail("outside")
			end
		end
	elseif kind == "wall" then
		local pose = Geometry.pose(x, y, z, r)
		local cx, cy = (b[1] + b[4]) / 2, (b[2] + b[5]) / 2
		local backDir = -pose.LookVector
		local backCentre = pose:PointToWorldSpace(Vector3.new(cx, cy, b[6]))
		local f, s = wallFace(U, backCentre, backDir, 0.9)
		if not f then
			return fail("noWall")
		end
		-- face the wall exactly and sit flush (gap)
		r = Geometry.yawFacing(f.n)
		local proj = backCentre - f.n * s
		local target = proj + f.n * Config.WALL_GAP
		local rot = CFrame.Angles(0, math.rad(r), 0)
		local origin = target - rot:VectorToWorldSpace(Vector3.new(cx, cy, b[6]))
		x, y, z = origin.X, origin.Y, origin.Z
		pose = Geometry.pose(x, y, z, r)
		for _, sx in { b[1] + 0.15, b[4] - 0.15 } do
			for _, sy in { b[2] + 0.15, b[5] - 0.15 } do
				local c = pose:PointToWorldSpace(Vector3.new(sx, sy, b[6]))
				if not onAnyFace(U, c - f.n * Config.WALL_GAP, f.n) then
					return fail("noWall")
				end
			end
		end
		local front = target + f.n * 0.6
		local fl = Unit.floorAt(U, front.X, front.Z, y + 0.5)
		if not fl then
			return fail("outside")
		end
		floorY = fl.top
		level = fl.level
		if y + b[2] < floorY + 0.05 then
			y = floorY + 0.05 - b[2]
		end
		local ceil = Unit.ceilingAbove(U, front.X, front.Z, floorY + 0.5)
		if ceil and y + b[5] > ceil - 0.02 then
			return fail("ceiling")
		end
		lift = y - floorY
	elseif kind == "ceiling" then
		local fl = Unit.floorAt(U, x, z, y + 0.5)
		if not fl then
			return fail("outside")
		end
		floorY = fl.top
		level = fl.level
		local ceil = Unit.ceilingAbove(U, x, z, floorY + 0.5)
		if not ceil then
			return fail("noCeiling")
		end
		y = ceil - b[5] - 0.01
		if y + b[2] < floorY + Config.CEILING_CLEARANCE then
			return fail("lowCeiling")
		end
		lift = y - floorY
	end

	local fixed = { x = Geometry.round(x, 0.01), y = Geometry.round(y, 0.005), z = Geometry.round(z, 0.01), r = Geometry.round(r, 0.1), lift = lift, level = level }
	local rec = { u = cand.u or -1, i = cand.i, x = fixed.x, y = fixed.y, z = fixed.z, r = fixed.r }
	local e = Rules.entry(rec) :: any
	local room = Unit.roomAt(U, Vector3.new(fixed.x, floorY, fixed.z))
	fixed.room = room and room.id or nil

	-- ceiling above (pieces standing / hanging below it)
	if kind ~= "ceiling" then
		local p = e.bound.cf.Position
		local ceil = Unit.ceilingAbove(U, p.X, p.Z, floorY + 0.5)
		if ceil and e.bound.hi.Y > ceil + 0.05 then
			return fail("ceiling")
		end
	end
	-- shell walls
	for _, bx in e.boxes do
		local sb = Geometry.prime(Geometry.shrink(bx, Config.WALL_SHRINK))
		for _, w in U.walls do
			if overlapFast(sb, w.box) then
				return fail("wall")
			end
		end
	end
	local allow = o.overlap == true and Config.ALLOW_OVERLAP_TOGGLE
	local onSolid = supportSrc and supportSrc.kind == "solid" and supportSrc.solid or nil
	local onItem = supportSrc and supportSrc.kind == "item" and supportSrc.uid or nil
	if kind ~= "rug" and not allow then
		-- fixed furniture / fixtures
		for _, bx in e.boxes do
			local sb = Geometry.prime(Geometry.shrink(bx, Config.OVERLAP_SHRINK))
			for _, s in U.solids do
				if s ~= onSolid and overlapFast(sb, s.box) then
					return fail(if s.stair then "stair" else "fixture")
				end
			end
		end
		-- slot envelopes (the life game's default furniture may be swapped for a bigger variant)
		local eb = Geometry.prime(Geometry.shrink(e.bound, 0.1))
		for _, s in U.slots do
			if s.category ~= "rug" and not (onSolid and onSolid.slot == s.id) and overlapFast(eb, s.box) then
				return fail("slot")
			end
		end
		-- other placed pieces
		local function against(other: any, u: any): boolean
			if (ignore and ignore[u]) or u == onItem or other.kind == "rug" then
				return false
			end
			for _, bx in e.boxes do
				local sb = Geometry.prime(Geometry.shrink(bx, Config.OVERLAP_SHRINK))
				for _, ob in other.boxes do
					if overlapFast(sb, ob) then
						-- a piece standing on this one is fine as long as it sits above its top
						return true
					end
				end
			end
			return false
		end
		for u, other in idx.items do
			if against(other, u) then
				return fail("overlap")
			end
		end
		if extra then
			for _, other in extra do
				if against(other, other.u) then
					return fail("overlap")
				end
			end
		end
	end
	-- keep zones
	if kind ~= "rug" and kind ~= "ceiling" then
		local kb = Geometry.prime(Geometry.shrink(e.bound, 0.05))
		local onFurniture = supportSrc ~= nil and supportSrc.kind ~= "floor"
		for _, k in U.keeps do
			local skip = (k.code == "interact" and (kind == "wall" or onFurniture)) or (k.code == "entry" and kind == "wall")
			if not skip and overlapFast(kb, k.box) then
				if k.code == "interact" then
					return fail("interact", k.label)
				end
				return fail(k.code)
			end
		end
	end
	-- people
	if o.people and kind ~= "rug" and kind ~= "ceiling" and kind ~= "wall" then
		local pb = Geometry.inflate(e.bound, Config.PERSON_INFLATE)
		for _, p in o.people do
			if Geometry.pointIn(pb, p, 0) then
				return fail("person")
			end
		end
	end
	-- reachability (low floor pieces only)
	if not o.noPath and (kind == "floor" or kind == "surface") and e.bound.lo.Y < floorY + 3 and (supportSrc == nil or supportSrc.kind == "floor") then
		local ok, label = Path.check(U, idx, { e }, ignore, level)
		if not ok then
			return fail("path", label)
		end
	end
	return true, nil, nil, fixed
end

-- several pieces moving together (group move / preset): checked in order of height so a piece can
-- stand on one that moves with it. list = { { u, i, x, y, z, r } }
function Rules.checkGroup(U: any, idx: any, list: { any }, opts: any?): (boolean, string?, any?, { any }?, number?)
	local o = table.clone(opts or {})
	local ignore = table.clone(o.ignore or {})
	for _, c in list do
		if c.u then
			ignore[c.u] = true
		end
	end
	o.ignore = ignore
	local order = {}
	for i in list do
		table.insert(order, i)
	end
	table.sort(order, function(a, b)
		return list[a].y < list[b].y
	end)
	local extra = {}
	o.extra = extra
	local fixed: { any } = {}
	for _, i in order do
		local c = list[i]
		o.noPath = true
		local ok, code, arg, fx = Rules.check(U, idx, c, o)
		if not ok then
			return false, code, arg, nil, i
		end
		fixed[i] = fx
		local e = Rules.entry({ u = c.u or -i, i = c.i, x = fx.x, y = fx.y, z = fx.z, r = fx.r })
		if e then
			table.insert(extra, e)
		end
	end
	-- one reachability check for the whole group
	if Config.PATH_CHECK and not (opts and opts.noPath) then
		local levels: { [number]: boolean } = {}
		for _, fx in fixed do
			levels[fx.level or 1] = true
		end
		for lv in levels do
			local ok, label = Path.check(U, idx, extra, ignore, lv)
			if not ok then
				return false, "path", label, nil, nil
			end
		end
	end
	return true, nil, nil, fixed, nil
end

return Rules
