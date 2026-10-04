-- Builder/Plan: the DATA plan of a building (no instances). An archetype fills a plan once at server
-- start (cheap): floors, footprint rectangles, slab holes, facade openings, stairs, elevators, units,
-- shops and special rooms. The shell builder, the interior builders, the housing listings and the
-- elevator stops all read the same plan, so the facade, the interior and the services never disagree.
--
-- Building-local space: x across the frontage (-W/2 .. W/2), z into the lot (0 = street facade .. D),
-- y = height above the 1F finished floor (FFL). rec.cf maps it to the world.
-- Walls are centred on rectangle edges; a rectangle's usable inside is its edges minus half a wall.

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Homes = Shared.Homes
local Rng = Shared.Rng
local Palette = Shared.Palette

local Plan = {}

local V3, CF = Vector3.new, CFrame.new
local abs, min, max = math.abs, math.min, math.max

-------------------------------------------------------------------------------------------------
-- building
-------------------------------------------------------------------------------------------------
function Plan.new(def: any): any
	local rec = {
		id = def.id,
		archetype = def.archetype,
		name = def.name,
		nameEn = def.nameEn or "",
		seed = def.seed or Rng.hash(def.id),
		wear = def.wear or 0,
		cf = def.cf,
		W = def.W,
		D = def.D,
		floors = {},
		floorByLabel = {},
		stairs = {},
		elevators = {},
		units = {},
		unitList = {},
		shops = {},
		shopList = {},
		doors = {}, -- data of doors that belong to the shell (entrances, roof)
		signs = {},
		roof = def.roof or {},
		lot = def.lot, -- { x0, z0, x1, z1 } site area for ramps / forecourt
		ramp = nil,
		lobbyLabel = def.lobbyLabel or "1F",
		hooks = {}, -- archetype callbacks: floor(ctx, fl), furnish(ctx, fl), shell(ctx)
	}
	rec.rng = Rng.new(rec.seed)
	-- facade style with seeded tones
	local style = Palette.STYLES[def.style] or Palette.STYLES.commercial
	local r = Rng.child(rec.seed, "style")
	rec.styleId = def.style
	rec.style = style
	rec.tone = {
		wall = r:pick(style.wall.tones),
		accent = r:pick(style.accent.tones),
		base = r:pick(style.base.tones),
	}
	return rec
end

-- floors are added bottom-up; the floor labelled lobbyLabel ("1F") has y = 0
function Plan.floors(rec: any, list: { any })
	local lobbyIdx = 1
	for i, f in list do
		if f.label == rec.lobbyLabel then
			lobbyIdx = i
		end
	end
	-- y of each FFL relative to 1F
	local ys = {}
	ys[lobbyIdx] = 0
	for i = lobbyIdx + 1, #list do
		ys[i] = ys[i - 1] + list[i - 1].h
	end
	for i = lobbyIdx - 1, 1, -1 do
		ys[i] = ys[i + 1] - list[i].h
	end
	for i, f in list do
		local fl = {
			index = i,
			label = f.label,
			level = f.level or i - lobbyIdx + 1, -- 1 = 1F, 0 = B1 ...
			y = ys[i],
			h = f.h,
			kind = f.kind or "res",
			rects = f.rects or {},
			holes = {},
			openings = {},
			open = {}, -- railing edges instead of walls { side, line, a0, a1 }
			units = {},
			shops = {},
			rooms = {},
			doors = {},
			name = f.name,
			ceiling = f.h - Config.SLAB,
			noSlab = f.noSlab,
			data = f.data or {},
		}
		rec.floors[i] = fl
		rec.floorByLabel[f.label] = fl
	end
	local top = rec.floors[#rec.floors]
	rec.roofY = top.y + top.h
	rec.H = rec.roofY
end

function Plan.floor(rec: any, label: string): any
	return rec.floorByLabel[label]
end

-- floors whose label is in the list (or all residential floors when nil)
function Plan.each(rec: any, fn: (any) -> ())
	for _, fl in rec.floors do
		fn(fl)
	end
end

-------------------------------------------------------------------------------------------------
-- rectangles
-------------------------------------------------------------------------------------------------
function Plan.rect(x0: number, z0: number, x1: number, z1: number): any
	return { x0 = min(x0, x1), z0 = min(z0, z1), x1 = max(x0, x1), z1 = max(z0, z1) }
end

-- subtract holes from a rectangle -> list of rectangles (column decomposition)
function Plan.subtract(r: any, holes: { any }): { any }
	local xs = { r.x0, r.x1 }
	for _, h in holes do
		if h.x1 > r.x0 and h.x0 < r.x1 and h.z1 > r.z0 and h.z0 < r.z1 then
			table.insert(xs, max(r.x0, h.x0))
			table.insert(xs, min(r.x1, h.x1))
		end
	end
	table.sort(xs)
	local out = {}
	for i = 1, #xs - 1 do
		local a, b = xs[i], xs[i + 1]
		if b - a > 0.01 then
			local mid = (a + b) / 2
			local spans = {}
			for _, h in holes do
				if h.x0 <= mid and mid <= h.x1 and h.z1 > r.z0 and h.z0 < r.z1 then
					table.insert(spans, { max(r.z0, h.z0), min(r.z1, h.z1) })
				end
			end
			table.sort(spans, function(p, q)
				return p[1] < q[1]
			end)
			local z = r.z0
			for _, s in spans do
				if s[1] - z > 0.01 then
					table.insert(out, Plan.rect(a, z, b, s[1]))
				end
				z = max(z, s[2])
			end
			if r.z1 - z > 0.01 then
				table.insert(out, Plan.rect(a, z, b, r.z1))
			end
		end
	end
	-- merge vertically-identical neighbours along x (fewer parts)
	local merged = {}
	for _, q in out do
		local last = merged[#merged]
		if last and abs(last.x1 - q.x0) < 0.01 and abs(last.z0 - q.z0) < 0.01 and abs(last.z1 - q.z1) < 0.01 then
			last.x1 = q.x1
		else
			table.insert(merged, q)
		end
	end
	return merged
end

-- exterior edges of a union of non-overlapping rectangles: { {side, line, a0, a1} }
-- side: "-z" (street facade), "+z" (rear), "-x" (left), "+x" (right)
function Plan.edges(rects: { any }): { any }
	local out = {}
	local eps = 0.05
	local function covered(px: number, pz: number): boolean
		for _, r in rects do
			if px > r.x0 and px < r.x1 and pz > r.z0 and pz < r.z1 then
				return true
			end
		end
		return false
	end
	local function addEdge(side: string, line: number, a0: number, a1: number, probe: (number) -> (number, number))
		-- walk the edge, splitting where the outside is covered by another rect
		local cuts = { a0, a1 }
		for _, r in rects do
			if side == "-z" or side == "+z" then
				if r.x0 > a0 and r.x0 < a1 then
					table.insert(cuts, r.x0)
				end
				if r.x1 > a0 and r.x1 < a1 then
					table.insert(cuts, r.x1)
				end
			else
				if r.z0 > a0 and r.z0 < a1 then
					table.insert(cuts, r.z0)
				end
				if r.z1 > a0 and r.z1 < a1 then
					table.insert(cuts, r.z1)
				end
			end
		end
		table.sort(cuts)
		local runStart: number? = nil
		local runEnd = a0
		for i = 1, #cuts - 1 do
			local s, e = cuts[i], cuts[i + 1]
			if e - s > 0.01 then
				local px, pz = probe((s + e) / 2)
				if covered(px, pz) then
					if runStart then
						table.insert(out, { side = side, line = line, a0 = runStart, a1 = runEnd })
						runStart = nil
					end
				else
					runStart = runStart or s
					runEnd = e
				end
			end
		end
		if runStart then
			table.insert(out, { side = side, line = line, a0 = runStart, a1 = runEnd })
		end
	end
	for _, r in rects do
		addEdge("-z", r.z0, r.x0, r.x1, function(a)
			return a, r.z0 - eps
		end)
		addEdge("+z", r.z1, r.x0, r.x1, function(a)
			return a, r.z1 + eps
		end)
		addEdge("-x", r.x0, r.z0, r.z1, function(a)
			return r.x0 - eps, a
		end)
		addEdge("+x", r.x1, r.z0, r.z1, function(a)
			return r.x1 + eps, a
		end)
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- openings (facade holes): side + line identify the wall; a0..a1 along it; y0..y1 above the FFL
-------------------------------------------------------------------------------------------------
function Plan.opening(fl: any, side: string, line: number, a0: number, a1: number, y0: number, y1: number, kind: string, extra: any?)
	local o = { side = side, line = line, a0 = min(a0, a1), a1 = max(a0, a1), y0 = y0, y1 = y1, kind = kind }
	if extra then
		for k, v in extra do
			o[k] = v
		end
	end
	table.insert(fl.openings, o)
	return o
end

-- open edge: a railing / parapet instead of a wall (open-air corridors, terraces, 필로티)
function Plan.openEdge(fl: any, side: string, line: number, a0: number, a1: number, rail: string?)
	table.insert(fl.open, { side = side, line = line, a0 = min(a0, a1), a1 = max(a0, a1), rail = rail or "parapet" })
end

-- axis + sign of a building-local direction
local function sideOf(v: Vector3): string
	if abs(v.X) > abs(v.Z) then
		return if v.X > 0 then "+x" else "-x"
	end
	return if v.Z > 0 then "+z" else "-z"
end
Plan.sideOf = sideOf

local function along(side: string, p: Vector3): number
	return if side == "-z" or side == "+z" then p.X else p.Z
end
local function lineOf(side: string, p: Vector3): number
	return if side == "-z" or side == "+z" then p.Z else p.X
end
Plan.along = along
Plan.lineOf = lineOf

-- a local frame's (u, v) rectangle edge at v = d mapped to a facade side
function Plan.frameEdge(frame: CFrame, u0: number, u1: number, d: number): (string, number, number, number)
	local n = frame:VectorToWorldSpace(V3(0, 0, 1))
	local side = sideOf(n)
	local p0 = frame * V3(u0, 0, d)
	local p1 = frame * V3(u1, 0, d)
	return side, lineOf(side, p0), along(side, p0), along(side, p1)
end

-------------------------------------------------------------------------------------------------
-- frames: a component frame in building-local space. rot = yaw in degrees (0 = local +Z is building +z)
-------------------------------------------------------------------------------------------------
function Plan.frame(x: number, y: number, z: number, rot: number?): CFrame
	return CF(x, y, z) * CFrame.Angles(0, math.rad(rot or 0), 0)
end

-- AABB (building-local) of a rectangle given in a component frame
function Plan.boxOf(frame: CFrame, u0: number, v0: number, u1: number, v1: number): any
	local ps = { frame * V3(u0, 0, v0), frame * V3(u1, 0, v0), frame * V3(u0, 0, v1), frame * V3(u1, 0, v1) }
	local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ps do
		x0, z0 = min(x0, p.X), min(z0, p.Z)
		x1, z1 = max(x1, p.X), max(z1, p.Z)
	end
	return Plan.rect(x0, z0, x1, z1)
end

-------------------------------------------------------------------------------------------------
-- stairs: a switchback stair (see Core.stairFloor). The stair frame: origin at the centre of the
-- entry wall line at FFL, +Z into the stairwell. Width SW (u = -SW/2..SW/2), depth SL (v = 0..SL).
-- floors: list of labels served bottom-up (flights connect consecutive labels); roof = true adds the
-- flight from the top floor to the roof and the roof stair tower.
-------------------------------------------------------------------------------------------------
Plan.STAIR_FW = 4.6
Plan.STAIR_GAP = 0.8
Plan.STAIR_LD = 4.4

function Plan.stairRun(rec: any, labels: { string }): number
	local run = 7.6
	for i = 1, #labels - 1 do
		local fl = rec.floorByLabel[labels[i]]
		run = max(run, (fl.h / 2) / 0.72)
	end
	return math.ceil(run * 2) / 2
end

function Plan.stair(rec: any, def: any): any
	local labels = def.floors
	local run = def.run or Plan.stairRun(rec, labels)
	local s = {
		id = def.id or (rec.id .. "_stair" .. (#rec.stairs + 1)),
		frame = Plan.frame(def.x, 0, def.z, def.rot or 0),
		SW = 2 * Plan.STAIR_FW + Plan.STAIR_GAP,
		LD = Plan.STAIR_LD,
		run = run,
		floors = labels,
		roof = def.roof == true,
		door = def.door or "fire", -- door kind at each landing
		doorAt = def.doorAt or 0, -- u of the landing door centre
		noDoor = def.noDoor or {}, -- labels without a landing door (open stair)
		window = def.window, -- facade window at the mid landing: true when the far wall is exterior
		private = def.private, -- { [label] = unitId } locked landings
		style = def.style or "concrete",
		exterior = def.exterior, -- { entry?, left?, right?, far? } walls the shell already provides
		extFn = def.extFn, -- (label) -> exterior table for that storey (overrides exterior)
		roofDoor = def.roofDoor, -- "entry" | "left" | "right": side of the roof tower door
	}
	s.SL = 2 * s.LD + run
	-- slab holes: every served floor above the first gets the flight / mid landing region opened
	local hole = Plan.boxOf(s.frame, -s.SW / 2 - 0.05, s.LD, s.SW / 2 + 0.05, s.SL + 0.05)
	for i = 2, #labels do
		table.insert(rec.floorByLabel[labels[i]].holes, hole)
	end
	if s.roof then
		s.roofHole = hole
	end
	s.box = Plan.boxOf(s.frame, -s.SW / 2 - 0.4, -0.4, s.SW / 2 + 0.4, s.SL + 0.4)
	table.insert(rec.stairs, s)
	return s
end

-------------------------------------------------------------------------------------------------
-- elevators: frame origin at the centre of the hall-door line at the lowest stop's FFL.. the car
-- interior is u = -cw/2..cw/2, v = 0.6 .. 0.6 + cd (behind the hall door sill)
-------------------------------------------------------------------------------------------------
function Plan.elevator(rec: any, def: any): any
	local cw, cd = Config.ELEV_CAR_W, Config.ELEV_CAR_D
	local e = {
		id = def.id or (rec.id .. "_ev" .. (#rec.elevators + 1)),
		name = def.name or "승강기",
		frame = Plan.frame(def.x, 0, def.z, def.rot or 0),
		cw = cw,
		cd = cd,
		EW = cw + 2.0, -- shaft inner width
		ED = cd + 1.6, -- shaft inner depth
		stops = {},
		home = def.home or rec.lobbyLabel,
		restricted = def.restricted or {}, -- { [label] = unitId } (penthouse floors: owner only)
	}
	for _, label in def.floors do
		local fl = rec.floorByLabel[label]
		table.insert(e.stops, { label = label, y = fl.y, fl = fl })
	end
	local hole = Plan.boxOf(e.frame, -e.EW / 2 - 0.05, 0, e.EW / 2 + 0.05, e.ED + 0.05)
	for i, st in e.stops do
		if i > 1 then
			table.insert(st.fl.holes, hole)
		end
	end
	e.hole = hole
	e.box = Plan.boxOf(e.frame, -e.EW / 2 - 0.4, -0.4, e.EW / 2 + 0.4, e.ED + 0.4)
	table.insert(rec.elevators, e)
	return e
end

-------------------------------------------------------------------------------------------------
-- units (homes). def = { template, frame (building-local; origin = entrance-wall corner u = 0, v = 0,
-- +Z into the unit), door = u of the door centre, number = "1203", view = "ocean" | "city" | "street",
-- windows = override list }. The template's exterior windows are registered as facade openings.
-------------------------------------------------------------------------------------------------
function Plan.unit(rec: any, fl: any, def: any): any
	local t = Homes.TEMPLATES[def.template]
	assert(t, "unknown unit template " .. tostring(def.template))
	local id = rec.id .. "-" .. def.number
	local u = {
		id = id,
		buildingId = rec.id,
		number = def.number,
		label = def.number .. "호",
		floor = fl.label,
		level = fl.level,
		template = def.template,
		variant = def.variant or 1,
		tier = t.tier,
		w = def.w or t.w,
		d = def.d or t.d,
		frame = def.frame,
		door = def.door or 3,
		view = def.view or "city",
		price = 0,
		fl = fl,
		rec = rec,
		exterior = def.exterior or "far", -- which edge is the facade: "far" (v = d) / "left" / "right"
		balcony = def.balcony,
		extraWindows = def.windows,
	}
	u.price = Homes.price(def.template, fl.level, u.view, rec.wear)
	rec.units[id] = u
	table.insert(rec.unitList, u)
	table.insert(fl.units, u)
	return u
end

-- shops / tenant bays. def = { kind, name, frame, w, d, door = {u, w, kind}, street = bool }
function Plan.shop(rec: any, fl: any, def: any): any
	local id = def.id or (rec.id .. "_" .. def.kind .. (#rec.shopList + 1))
	local s = {
		id = id,
		buildingId = rec.id,
		kind = def.kind,
		name = def.name,
		frame = def.frame,
		w = def.w,
		d = def.d,
		fl = fl,
		rec = rec,
		data = def.data or {},
	}
	rec.shops[id] = s
	table.insert(rec.shopList, s)
	table.insert(fl.shops, s)
	return s
end

-- special rooms built by the archetype hook (lobby, restroom, office, parking ...)
function Plan.room(fl: any, def: any): any
	table.insert(fl.rooms, def)
	return def
end

-------------------------------------------------------------------------------------------------
-- world helpers
-------------------------------------------------------------------------------------------------
function Plan.world(rec: any, local_: CFrame): CFrame
	return rec.cf * local_
end

-- building-local AABB of the whole building incl. roof equipment, for streaming distances
function Plan.bounds(rec: any): (CFrame, Vector3)
	local bottom = rec.floors[1].y - Config.SLAB
	local top = rec.roofY + 12
	local cx = 0
	local cz = rec.D / 2
	local cy = (bottom + top) / 2
	return rec.cf * CF(cx, cy, cz), V3(rec.W + 2, top - bottom, rec.D + 2)
end

return Plan
