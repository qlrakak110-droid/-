-- GwangalliShopCrew/Sites: per-shop floor analysis, cached by shop key.
--   Sites.get(key) -> Site?        builds once (rebuilt when the shop model changes); Site.ok = false + Site.why
--   Sites.path(site, fromPos, toPos, mainOnly?) -> { Vector3 }?   feet-level polyline (NavGrid A* + string pulling)
--   Sites.publish(site) / Sites.unpublish(key)   invisible GwCrewSpot parts (Workspace.GwShopCrew/Spots/<key>)
--   Sites.drop(key)
-- A Site holds the shop frame (local x / z, floor level), the walk grid (every furniture part of the shop model
-- rasterised and inflated by Config.AGENT_R; walls bound it; a strip outside the door is walkable), and spots:
--   C  cook / barista / maker at the main station (any grid component: kitchens behind counters are fine)
--   S  service point where the waiter takes the tray (customer side of the pass / counter, main component)
--   H  waiter home, beside S, facing the room              K  cashier behind the POS / counter (optional)
--   A[tableId] = { seats = { [seatId] = spot }, best = spot }   where the waiter stands to serve each seat
--   Din / Dout  just inside / outside the door (NPC diners)  idle = a few roomy floor spots (floor / stocker)
-- spot = { pos = Vector3 (feet), yaw = degrees (NPC contract), lx, lz }

local CollectionService = game:GetService("CollectionService")

local Sites = {}

local Shared: any = nil
local Config: any = nil
local Bridge: any = nil
local NavGrid: any = nil
local Util: any = nil

local cache: { [string]: any } = {}
local spotRoot: Folder? = nil

local SKIP_NAMES = {
	ShopFloor = true,
	Sill = true,
	Baseboard = true,
	Skirting = true,
	Threshold = true,
	Wainscot = true,
	ShopBounds = true,
	LightHost = true,
	ShopCeiling = true,
	Rug = true,
	Mat = true,
	FloorMat = true,
	Carpet = true,
	Doormat = true,
	FloorTile = true,
	FloorTrim = true,
}
local FRIDGE_NAMES = { "Fridge", "ReachIn", "DrinkFridge", "Refrigerator", "BackCounter", "BackCabinet", "PrepTable", "Stove", "Range", "Fryer" }

function Sites.init(S: any, B: any)
	Shared = S
	Config = S.Config
	Util = S.Util
	NavGrid = S.NavGrid
	Bridge = B
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function yawTo(from: Vector3, to: Vector3): number?
	local d = flat(to - from)
	if d.Magnitude < 0.05 then
		return nil
	end
	return Util.yaw(d.X, d.Z)
end
Sites.yawTo = yawTo

-------------------------------------------------------------------------------------------------
-- frame helpers (site.frame: horizontal CFrame at floor level)
-------------------------------------------------------------------------------------------------
local function toLocal(site: any, p: Vector3): (number, number)
	local l = site.frame:PointToObjectSpace(Vector3.new(p.X, site.floorY, p.Z))
	return l.X, l.Z
end

local function toWorld(site: any, x: number, z: number): Vector3
	local w = site.frame:PointToWorldSpace(Vector3.new(x, 0, z))
	return Vector3.new(w.X, site.floorY, w.Z)
end
Sites.toLocal = toLocal
Sites.toWorld = toWorld

local function corners(cf: CFrame, size: Vector3): { Vector3 }
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local out = table.create(8)
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(out, cf:PointToWorldSpace(Vector3.new(hx * sx, hy * sy, hz * sz)))
			end
		end
	end
	return out
end

-- local footprint box + world height range of a part (or a CFrame + size)
local function localBox(site: any, cf: CFrame, size: Vector3): (number, number, number, number, number, number)
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	for _, c in corners(cf, size) do
		local l = site.frame:PointToObjectSpace(c)
		minX = math.min(minX, l.X)
		maxX = math.max(maxX, l.X)
		minZ = math.min(minZ, l.Z)
		maxZ = math.max(maxZ, l.Z)
		minY = math.min(minY, c.Y)
		maxY = math.max(maxY, c.Y)
	end
	return minX, minZ, maxX, maxZ, minY, maxY
end

local function makeSpot(site: any, x: number, z: number, yaw: number?): any
	return { pos = toWorld(site, x, z), yaw = yaw or 0, lx = x, lz = z }
end

-------------------------------------------------------------------------------------------------
-- eligibility
-------------------------------------------------------------------------------------------------
local function eligible(rec: any): (boolean, string?)
	if rec.model and rec.model:GetAttribute("ShopCrew") == false then
		return false, "ShopCrew=false"
	end
	if rec.source == "venue" then
		return false, "venue"
	end
	if rec.source == "gwshop" and Bridge.has("ShopLife") then
		-- the map's own shop server runs these when present (ShopLife deactivates them too)
		local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("GwangalliRemotes")
		if remotes and remotes:FindFirstChild("ShopRequest") then
			return false, "gwshop host"
		end
	end
	for _, n in Config.SKIP_SHOPS do
		if rec.name == n then
			return false, "skip list"
		end
	end
	if Config.SKIP_TYPES[rec.type] then
		return false, "skip type"
	end
	local c = rec.center
	if typeof(c) == "Vector3" then
		for _, p in Bridge.jobSites() do
			if (flat(p) - flat(c)).Magnitude < Config.JOB_SITE_R and math.abs(p.Y - c.Y) < 30 then
				return false, "job site"
			end
		end
	end
	return true, nil
end

-- is a ShopStaff counter rig / GwShopClerk / venue staff working inside this shop already
local function staffedBy(site: any): (boolean, { Model })
	local found = {}
	local function inside(pos: Vector3): boolean
		local x, z = toLocal(site, pos)
		return math.abs(x) <= site.sx / 2 + 1 and math.abs(z) <= site.sz / 2 + 1 and pos.Y > site.floorY - 4 and pos.Y < site.floorY + 14
	end
	for _, s in Bridge.staffSites() do
		if inside(s.pos) then
			if s.model then
				table.insert(found, s.model)
			end
			return true, found
		end
	end
	for _, tag in { "GwShopClerk", "VenueStaff" } do
		for _, m in CollectionService:GetTagged(tag) do
			if m:IsA("Model") then
				local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
				if root and root:IsA("BasePart") and inside(root.Position) then
					table.insert(found, m)
				end
			end
		end
	end
	return #found > 0, found
end

-------------------------------------------------------------------------------------------------
-- the walk grid
-------------------------------------------------------------------------------------------------
local function doorSide(site: any): (string, number)
	local dx, dz = toLocal(site, site.door)
	local ex = site.sx / 2 - math.abs(dx)
	local ez = site.sz / 2 - math.abs(dz)
	if ez <= ex then
		return "z", if dz >= 0 then 1 else -1
	end
	return "x", if dx >= 0 then 1 else -1
end

local function isDoorPart(part: BasePart, stop: Instance): boolean
	local a = part.Parent
	while a and a ~= stop do
		if a:IsA("Model") and (string.sub(a.Name, 1, 8) == "AutoDoor" or CollectionService:HasTag(a, "AutoDoor")) then
			return true
		end
		a = a.Parent
	end
	return false
end

local function buildGrid(site: any)
	local rec = site.rec
	local hx, hz = site.sx / 2, site.sz / 2
	local axis, sign = doorSide(site)
	site.doorAxis, site.doorSign = axis, sign
	local strip = Config.DOOR_STRIP
	local minX, maxX, minZ, maxZ = -hx - 0.5, hx + 0.5, -hz - 0.5, hz + 0.5
	if axis == "z" then
		if sign > 0 then
			maxZ += strip
		else
			minZ -= strip
		end
	else
		if sign > 0 then
			maxX += strip
		else
			minX -= strip
		end
	end
	local g = NavGrid.new(minX, minZ, maxX, maxZ, Config.CELL)
	local r = Config.AGENT_R
	local band0, band1 = site.floorY + 0.35, site.floorY + 5.5
	local area = site.sx * site.sz
	local n = 0
	local function consider(p: BasePart, stop: Instance)
		if SKIP_NAMES[p.Name] or string.sub(p.Name, 1, 5) == "Sign_" then
			return
		end
		if p.Transparency >= 0.95 and not p.CanCollide then
			return
		end
		if isDoorPart(p, stop) then
			return
		end
		local m = p:FindFirstAncestorOfClass("Model")
		if m and m ~= stop and (m:FindFirstChild("HumanoidRootPart") or m:FindFirstChildOfClass("Humanoid")) then
			return
		end
		local x0, z0, x1, z1, y0, y1 = localBox(site, p.CFrame, p.Size)
		if y1 < band0 or y0 > band1 or y0 > site.floorY + 4.6 then
			return
		end
		if y1 - y0 < 0.15 and y0 < site.floorY + 0.5 then
			return
		end
		if (x1 - x0) * (z1 - z0) > area * 0.6 then
			return
		end
		g:block(x0 - r, z0 - r, x1 + r, z1 + r)
	end
	if rec.model then
		for _, d in rec.model:GetDescendants() do
			if d:IsA("BasePart") then
				consider(d, rec.model)
				n += 1
				if n % 400 == 0 then
					task.wait()
				end
			end
		end
	end
	-- ShopLife's own station props (water purifier, bin) live in its shop folder
	local folder = rec.folder
	if typeof(folder) == "Instance" then
		for _, ch in folder:GetChildren() do
			if ch.Name ~= "Anchors" and ch.Name ~= "Dishes" then
				for _, d in ch:GetDescendants() do
					if d:IsA("BasePart") then
						consider(d, folder)
					end
				end
				if ch:IsA("BasePart") then
					consider(ch, folder)
				end
			end
		end
	end
	-- seats (chairs / stools / cushions) are never walked through, even when their parts are thin or hidden
	for _, tb in site.tables do
		for _, seat in tb.seats do
			local c = seat.top
			local lx, lz = toLocal(site, c)
			g:block(lx - 0.75 - r * 0.5, lz - 0.75 - r * 0.5, lx + 0.75 + r * 0.5, lz + 0.75 + r * 0.5)
		end
		-- dining tables as a whole (thin / hidden legs); a bar or counter "table" box also spans its stools and
		-- the bartender's side, and the counter's own parts are already in the grid
		if tb.min and tb.max and tb.kind ~= "bar" and tb.kind ~= "counter" then
			local x0, z0, x1, z1 = localBox(site, CFrame.new((tb.min + tb.max) / 2), tb.max - tb.min)
			g:block(x0 - r, z0 - r, x1 + r, z1 + r)
		end
	end
	-- outside the footprint: blocked, except the strip in front of the door (diners walk in from the street)
	g:blockOutside(-hx + 0.2, -hz + 0.2, hx - 0.2, hz - 0.2)
	local dlx, dlz = toLocal(site, site.door)
	local half = 1.4
	if axis == "z" then
		local edge = sign * hz
		g:open(dlx - half, math.min(edge - sign * 0.3, edge + sign * strip), dlx + half, math.max(edge - sign * 0.3, edge + sign * strip))
	else
		local edge = sign * hx
		g:open(math.min(edge - sign * 0.3, edge + sign * strip), dlz - half, math.max(edge - sign * 0.3, edge + sign * strip), dlz + half)
	end
	g:finalize()
	site.nav = g
	site.inward = if axis == "z" then { 0, -sign } else { -sign, 0 }
end

-------------------------------------------------------------------------------------------------
-- spots
-------------------------------------------------------------------------------------------------
local function snap(site: any, x: number, z: number, maxR: number, comp: number?, minClear: number?): (number?, number?)
	return site.nav:nearestFree(x, z, maxR, comp, minClear)
end

-- the four sides of a part (local): { staff = away from the door, customer = toward it, lat1, lat2 }, each a
-- list of { x, z, faceX, faceZ } points `push` studs out from the part's local box: the side's middle first, then
-- along the edge (a long bar counter whose middle is taken by a tap still has room further along)
local ALONG = { 0, -0.28, 0.28, -0.42, 0.42 }
local function sides(site: any, part: BasePart, push: number): any
	local x0, z0, x1, z1 = localBox(site, part.CFrame, part.Size)
	local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
	local w, d = x1 - x0, z1 - z0
	local inX, inZ = site.inward[1], site.inward[2] -- from the door into the shop
	local defs = {
		{ 0, 1, mx, z1 + push, w, true },
		{ 0, -1, mx, z0 - push, w, true },
		{ 1, 0, x1 + push, mz, d, false },
		{ -1, 0, x0 - push, mz, d, false },
	}
	local out: any = {}
	for _, c in defs do
		local pts = {}
		for _, f in ALONG do
			if f == 0 or c[5] > 2.4 then
				local px = if c[6] then c[3] + f * c[5] else c[3]
				local pz = if c[6] then c[4] else c[4] + f * c[5]
				-- face the part where it is across from this point
				local fx = if c[6] then px else mx
				local fz = if c[6] then mz else pz
				table.insert(pts, { px, pz, fx, fz })
			end
		end
		local dot = c[1] * inX + c[2] * inZ
		if dot > 0.5 then
			out.staff = pts
		elseif dot < -0.5 then
			out.customer = pts
		elseif not out.lat1 then
			out.lat1 = pts
		else
			out.lat2 = pts
		end
	end
	out.staff = out.staff or out.lat1 or {}
	out.customer = out.customer or out.lat2 or {}
	return out
end

local function ordered(sd: any, keys: { string }): { { number } }
	local out = {}
	for _, k in keys do
		for _, pt in sd[k] or {} do
			table.insert(out, pt)
		end
	end
	return out
end

local function partValidStation(site: any, p: BasePart?): boolean
	if not p or not p:IsA("BasePart") or not p.Parent then
		return false
	end
	local _, _, _, _, y0 = localBox(site, p.CFrame, p.Size)
	if y0 > site.floorY + 5 then
		-- a hood / sign above head height
		return false
	end
	local lx, lz = toLocal(site, p.Position)
	for _, tb in site.tables do
		if tb.min and tb.max and tb.kind ~= "bar" and tb.kind ~= "counter" then
			local x0, z0, x1, z1 = localBox(site, CFrame.new((tb.min + tb.max) / 2), tb.max - tb.min)
			if lx > x0 - 0.5 and lx < x1 + 0.5 and lz > z0 - 0.5 and lz < z1 + 0.5 then
				return false
			end
		end
	end
	return true
end

local function findNamed(site: any, names: { string }): BasePart?
	local model = site.rec.model
	if not model then
		return nil
	end
	for _, n in names do
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == n or string.sub(d.Name, 1, #n) == n) and partValidStation(site, d) then
				return d
			end
		end
	end
	return nil
end

-- the main work station of the shop's maker (cook / barista / baker ...)
local function mainStation(site: any): BasePart?
	local rec = site.rec
	local t = site.type
	local order: { any }
	if t == "cafe" then
		order = { rec.espresso, rec.cook, rec.pass, rec.pos, rec.counter }
	elseif t == "pub" then
		order = { rec.tap, rec.counter, rec.cook, rec.pass }
	elseif t == "rawfish" or t == "seafood" then
		order = { rec.cutting, rec.counter, rec.cook, rec.pass, rec.tank }
	elseif t == "bakery" or t == "cvs" or t == "retail" then
		order = { rec.display, rec.pos, rec.counter }
	elseif t == "salon" then
		order = { rec.counter, rec.pos }
	elseif t == "pharmacy" then
		order = { rec.counter, rec.pos }
	else
		order = { rec.cook, rec.pass, rec.counter, rec.pos, rec.kiosk }
	end
	for _, p in order do
		if typeof(p) == "Instance" and partValidStation(site, p) then
			return p
		end
	end
	return findNamed(site, FRIDGE_NAMES)
end

local function placeAt(site: any, cands: { { number } }, maxR: number, comp: number?): (number?, number?, number?, number?)
	-- a close snap along the whole list first, then the wider radius (keeps the middle of the right side)
	for _, r in { math.min(0.8, maxR), maxR } do
		for _, c in cands do
			local x, z = snap(site, c[1], c[2], r, comp, 1)
			if x then
				return x, z, c[3], c[4]
			end
		end
	end
	return nil, nil, nil, nil
end

local function computeSpots(site: any)
	local g = site.nav
	local rec = site.rec
	local inX, inZ = site.inward[1], site.inward[2]
	local spots: any = { A = {}, idle = {} }
	site.spots = spots
	-- door / main component
	local dlx, dlz = toLocal(site, site.door)
	local ix, iz = snap(site, dlx + inX * 1.8, dlz + inZ * 1.8, 3)
	local doorComp = if ix then g:comp(ix, iz :: number) else 0
	-- the main component is the one most seats can be served in (a vestibule split off by an inner door must
	-- not cut the dining room away); ties go to the door's own component
	local votes: { [number]: number } = {}
	for _, tb in site.tables do
		for _, seat in tb.seats do
			local lx, lz = toLocal(site, seat.top)
			for _, off in { { 1.7, 0 }, { -1.7, 0 }, { 0, 1.7 }, { 0, -1.7 } } do
				local x, z = snap(site, lx + off[1], lz + off[2], 0.8, nil, 1)
				if x then
					local c = g:comp(x, z :: number)
					votes[c] = (votes[c] or 0) + 1
					break
				end
			end
		end
	end
	local main, best = doorComp, votes[doorComp] or 0
	for c, n in votes do
		if n > best then
			main, best = c, n
		end
	end
	if main == 0 then
		main = g:mainComp()
	end
	site.main = main
	site.doorLinked = doorComp ~= 0 and doorComp == main
	if ix and site.doorLinked then
		spots.Din = makeSpot(site, ix, iz :: number, Util.yaw(inX, inZ))
	end
	local ox, oz = snap(site, dlx - inX * (Config.DOOR_STRIP - 0.8), dlz - inZ * (Config.DOOR_STRIP - 0.8), 1.5, main)
	if ox then
		spots.Dout = makeSpot(site, ox, oz :: number, Util.yaw(inX, inZ))
	end
	-- maker station + spot
	local station = mainStation(site)
	site.station = station
	local cx, cz, sx2, sz2
	if station then
		cx, cz, sx2, sz2 = placeAt(site, ordered(sides(site, station, 0.95), { "staff", "customer" }), 1.3, nil)
		if not cx then
			cx, cz, sx2, sz2 = placeAt(site, ordered(sides(site, station, 1.6), { "staff", "customer", "lat1", "lat2" }), 2.2, nil)
		end
	end
	if not cx then
		-- no station (해변포차 style): the middle of the back wall, facing the room
		local backX, backZ = inX * (site.sx / 2 - 1.6), inZ * (site.sz / 2 - 1.6)
		cx, cz = snap(site, backX, backZ, 4, main, 1)
		sx2, sz2 = if cx then cx - inX else nil, if cz then cz - inZ else nil
	end
	if cx then
		local yaw = Util.yaw((sx2 or cx) - cx, (sz2 or cz) - cz)
		if (sx2 or cx) == cx and (sz2 or cz) == cz then
			yaw = Util.yaw(-inX, -inZ)
		end
		spots.C = makeSpot(site, cx, cz :: number, yaw)
		spots.C.face = toWorld(site, sx2 or cx, sz2 or cz)
	end
	-- service point S: customer side of the pass (or counter / station), main component
	local servePart = rec.pass or rec.counter or station
	local sxp, szp
	if typeof(servePart) == "Instance" then
		local x, z, fx, fz = placeAt(site, ordered(sides(site, servePart, 1.1), { "customer", "lat1", "lat2" }), 2.2, main)
		if x then
			sxp, szp = x, z
			spots.S = makeSpot(site, x, z :: number, Util.yaw((fx :: number) - x, (fz :: number) - (z :: number)))
			spots.S.face = toWorld(site, fx :: number, fz :: number)
		end
	end
	if not spots.S and spots.C then
		local x, z = snap(site, spots.C.lx + inX * -1.4, spots.C.lz + inZ * -1.4, 4, main, 1)
		if x then
			sxp, szp = x, z
			spots.S = makeSpot(site, x, z :: number, spots.C.yaw)
			spots.S.face = spots.C.face
		end
	end
	local function farFrom(x: number, z: number, list: { any }, d: number): boolean
		for _, sp in list do
			if sp and (sp.lx - x) ^ 2 + (sp.lz - z) ^ 2 < d * d then
				return false
			end
		end
		return true
	end
	local rx, rz = -inZ, inX -- perpendicular to the room axis
	-- the waiter's service point must not be the cook's own spot (a wall pass: both stand in front of it)
	if spots.S and spots.C and not farFrom(spots.S.lx, spots.S.lz, { spots.C }, 1.4) then
		local moved = false
		for _, off in { 1.8, -1.8, 2.6, -2.6 } do
			local x, z = snap(site, spots.C.lx + rx * off, spots.C.lz + rz * off, 0.8, main, 1)
			if x and farFrom(x, z :: number, { spots.C }, 1.4) then
				spots.S = makeSpot(site, x, z :: number, spots.S.yaw)
				spots.S.face = spots.C.face
				sxp, szp = x, z
				moved = true
				break
			end
		end
		if not moved then
			local x, z = snap(site, spots.C.lx - inX * 1.6, spots.C.lz - inZ * 1.6, 1.2, main, 1)
			if x then
				spots.S = makeSpot(site, x, z :: number, spots.S.yaw)
				spots.S.face = spots.C.face
				sxp, szp = x, z
			end
		end
	end
	-- waiter home H beside S, facing the room (toward the door)
	if sxp then
		for _, off in { { 2.3, -0.4 }, { -2.3, -0.4 }, { 0, -1.6 }, { 3.2, -1.0 }, { -3.2, -1.0 } } do
			local x, z = snap(site, sxp + rx * off[1] + inX * off[2], (szp :: number) + rz * off[1] + inZ * off[2], 0.9, main, 2)
			if x and farFrom(x, z :: number, { spots.C, spots.S }, 1.3) then
				spots.H = makeSpot(site, x, z :: number, Util.yaw(-inX, -inZ))
				break
			end
		end
		if not spots.H then
			for _, r in { 1.5, 2.5, 3.5 } do
				for a = 0, 7 do
					local ang = a * math.pi / 4
					local x, z = snap(site, sxp + math.cos(ang) * r, (szp :: number) + math.sin(ang) * r, 0.5, main, 2)
					if x and farFrom(x, z :: number, { spots.C, spots.S }, 1.3) then
						spots.H = makeSpot(site, x, z :: number, Util.yaw(-inX, -inZ))
						break
					end
				end
				if spots.H then
					break
				end
			end
		end
		if not spots.H then
			spots.H = makeSpot(site, sxp, szp :: number, Util.yaw(-inX, -inZ))
		end
	end
	-- cashier K behind the POS / counter, facing the door (none when it would be the cook's own spot: the cook
	-- takes the money then)
	local pos = rec.pos or rec.kiosk or rec.gwOrder or rec.counter
	if typeof(pos) == "Instance" and pos:IsA("BasePart") then
		local kx, kz, fx, fz = placeAt(site, ordered(sides(site, pos, 0.95), { "staff", "lat1", "lat2" }), 1.4, nil)
		if kx and farFrom(kx, kz :: number, { spots.C, spots.S, spots.H }, 1.4) then
			spots.K = makeSpot(site, kx, kz :: number, Util.yaw(-inX, -inZ))
			spots.K.face = toWorld(site, fx :: number, fz :: number)
		end
	end
	-- table approaches
	local sPos = spots.S and spots.S.pos
	for _, tb in site.tables do
		local entry = { seats = {}, best = nil }
		local bestD = math.huge
		for _, seat in tb.seats do
			local cf: CFrame = seat.cf
			local top: Vector3 = seat.top
			local look = flat(cf.LookVector)
			if look.Magnitude < 0.1 then
				look = flat(tb.center - top)
			end
			look = if look.Magnitude > 0.05 then look.Unit else Vector3.new(0, 0, -1)
			local right = Vector3.new(-look.Z, 0, look.X)
			local spotPos = if typeof(seat.spot) == "CFrame" then seat.spot.Position else tb.center
			local cands = {
				top + right * 1.7,
				top - right * 1.7,
				top - look * 1.6,
				top + right * 1.5 + look * 0.8,
				top - right * 1.5 + look * 0.8,
				top + right * 2.4,
				top - right * 2.4,
			}
			local best, bestScore = nil, math.huge
			for k, w in cands do
				local lx, lz = toLocal(site, w)
				local x, z = snap(site, lx, lz, 1.1, main, 1)
				if x then
					local wp = toWorld(site, x, z :: number)
					local score = (flat(wp - top)).Magnitude + k * 0.05
					if sPos then
						score += (flat(wp - sPos)).Magnitude * 0.04
					end
					if score < bestScore then
						best, bestScore = { x = x, z = z, w = wp }, score
					end
				end
			end
			if best then
				local sp = makeSpot(site, best.x, best.z, yawTo(best.w, spotPos) or 0)
				sp.face = spotPos
				sp.seat = seat.id
				entry.seats[seat.id] = sp
				local d = if sPos then (flat(best.w - sPos)).Magnitude else 0
				if d < bestD then
					bestD = d
					entry.best = sp
				end
			end
		end
		if entry.best then
			-- the table's own approach faces the table middle (clearing / wiping)
			entry.best = table.clone(entry.best)
			entry.best.yaw = yawTo(entry.best.pos, tb.center) or entry.best.yaw
			entry.best.face = tb.center
			spots.A[tb.id] = entry
		end
	end
	-- roomy idle spots (floor staff / stockers wander between them)
	local list = {}
	for _, e in spots.A do
		table.insert(list, e.best)
	end
	for _, sh in (if type(rec.shelves) == "table" then rec.shelves else {}) do
		if typeof(sh.at) == "Vector3" then
			local cands: { { number } }
			if typeof(sh.part) == "Instance" and sh.part:IsA("BasePart") then
				cands = ordered(sides(site, sh.part, 1.0), { "customer", "lat1", "lat2", "staff" })
			else
				local lx, lz = toLocal(site, sh.at)
				cands = { { lx - inX * 1.3, lz - inZ * 1.3 }, { lx + inX * 1.3, lz + inZ * 1.3 } }
			end
			local x, z = placeAt(site, cands, 1.2, main)
			if x then
				local sp = makeSpot(site, x, z :: number, yawTo(toWorld(site, x, z :: number), sh.at) or 0)
				sp.face = sh.at
				table.insert(list, sp)
			end
		end
	end
	spots.idle = list
end

-------------------------------------------------------------------------------------------------
-- build / cache
-------------------------------------------------------------------------------------------------
local function tablesOf(rec: any): { any }
	local out = {}
	for _, tb in (if type(rec.tables) == "table" then rec.tables else {}) do
		if type(tb) == "table" and type(tb.id) == "number" then
			local seats = {}
			for _, s in (if type(tb.seats) == "table" then tb.seats else {}) do
				if type(s) == "table" and typeof(s.cf) == "CFrame" then
					local top = if typeof(s.top) == "Vector3" then s.top else s.cf.Position
					table.insert(seats, { id = s.id, cf = s.cf, top = top, spot = s.spot })
				end
			end
			local center = if typeof(tb.center) == "Vector3" then tb.center else (if #seats > 0 then seats[1].top else nil)
			if center then
				table.insert(out, { id = tb.id, kind = tb.kind or "table", center = center, min = tb.min, max = tb.max, seats = seats, grill = tb.grill ~= nil and tb.grill ~= false })
			end
		end
	end
	return out
end

-- the entrance: ShopLife's AutoDoor position when the shop has one; open-front shops (포차 · 천막) have none and
-- ShopLife falls back to one end of the floor, so the edge opposite ShopBackWall (or the Threshold / ShutterBox)
-- is used instead
function Sites.frontDoor(site: any): Vector3
	local model = site.rec.model
	local door: Vector3 = site.door
	if not model then
		return door
	end
	if model:FindFirstChild("AutoDoor") or model:FindFirstChild("AutoDoor_GS25") then
		return door
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Model") and CollectionService:HasTag(d, "AutoDoor") then
			return door
		end
	end
	local hx, hz = site.sx / 2, site.sz / 2
	local mark = model:FindFirstChild("Threshold", true) or model:FindFirstChild("ShutterBox", true)
	if mark and mark:IsA("BasePart") then
		local x, z = toLocal(site, mark.Position)
		if math.abs(z) / hz > math.abs(x) / hx then
			return toWorld(site, x, (if z >= 0 then 1 else -1) * hz)
		end
		return toWorld(site, (if x >= 0 then 1 else -1) * hx, z)
	end
	local back = model:FindFirstChild("ShopBackWall", true)
	if back and back:IsA("BasePart") then
		local x, z = toLocal(site, back.Position)
		if math.abs(z) / hz > math.abs(x) / hx then
			return toWorld(site, 0, (if z >= 0 then -1 else 1) * hz)
		end
		return toWorld(site, (if x >= 0 then -1 else 1) * hx, 0)
	end
	return door
end

function Sites.build(key: string): any?
	local rec = Bridge.shopRec(key)
	if not rec or typeof(rec.frame) ~= "CFrame" then
		return nil
	end
	local fr: CFrame = rec.frame
	local floorY = tonumber(rec.floorY) or fr.Y
	local _, yaw, _ = fr:ToEulerAnglesYXZ()
	local site: any = {
		key = key,
		rec = rec,
		model = rec.model,
		name = tostring(rec.name or key),
		type = tostring(rec.type or ""),
		flow = rec.def and rec.def.flow or "table",
		menuKey = rec.menuKey,
		def = rec.def,
		frame = CFrame.new(fr.X, floorY, fr.Z) * CFrame.Angles(0, yaw, 0),
		floorY = floorY,
		sx = tonumber(rec.sx) or 20,
		sz = tonumber(rec.sz) or 18,
		door = if typeof(rec.door) == "Vector3" then rec.door else fr.Position,
		center = if typeof(rec.center) == "Vector3" then rec.center else fr.Position,
		ok = false,
		why = nil,
		built = os.clock(),
	}
	site.door = Sites.frontDoor(site)
	site.tables = tablesOf(rec)
	site.tableById = {}
	for _, tb in site.tables do
		site.tableById[tb.id] = tb
	end
	local okE, why = eligible(rec)
	site.eligible = okE
	if not okE then
		site.why = why
		return site
	end
	local staffed, staffModels = staffedBy(site)
	site.staffed = staffed
	site.staffModels = staffModels
	site.roles = Shared.Personas.roster(site.type, { tables = #site.tables, flow = site.flow, staffed = staffed })
	-- a map clerk who cooks (GwShopClerk Role "cook": 주방 이모) keeps the kitchen; we bring the hall only
	local cookCovered = rec.source == "gwshop"
	for _, m in staffModels do
		if m:GetAttribute("Role") == "cook" then
			cookCovered = true
		end
	end
	if cookCovered then
		local keep = {}
		for _, def in site.roles do
			if def.role ~= "cook" and def.role ~= "cashier" then
				table.insert(keep, def)
			end
		end
		site.roles = keep
		site.cookCovered = true
	end
	if #site.roles == 0 then
		site.why = "no roles"
		return site
	end
	local okB, err = pcall(buildGrid, site)
	if not okB then
		site.why = "grid: " .. tostring(err)
		Bridge.warnOnce("grid" .. key, "grid " .. key .. ": " .. tostring(err))
		return site
	end
	local okS, err2 = pcall(computeSpots, site)
	if not okS then
		site.why = "spots: " .. tostring(err2)
		Bridge.warnOnce("spots" .. key, "spots " .. key .. ": " .. tostring(err2))
		return site
	end
	-- roles without the spot they need are dropped (a waiter needs S + H; a maker needs C; a cashier K)
	local roles = {}
	for _, def in site.roles do
		local r = def.role
		local need = if r == "waiter" then (site.spots.S and site.spots.H) elseif r == "cashier" then site.spots.K elseif r == "pharmacist" then (site.spots.K or site.spots.C) else (site.spots.C or site.spots.K)
		if r == "floor" or r == "stocker" then
			need = (#site.spots.idle > 0) and (site.spots.C or site.spots.H or site.spots.K)
		end
		if need then
			table.insert(roles, def)
		end
	end
	site.roles = roles
	site.ok = #roles > 0
	if not site.ok then
		site.why = "no spots"
	end
	return site
end

function Sites.get(key: string): any?
	local s = cache[key]
	if s then
		local rec = Bridge.shopRec(key)
		if rec and rec.model == s.model and (s.model == nil or s.model.Parent ~= nil) then
			return s
		end
		Sites.drop(key)
	end
	local built = Sites.build(key)
	if built then
		cache[key] = built
	end
	return built
end

function Sites.drop(key: string)
	cache[key] = nil
	Sites.unpublish(key)
end

-------------------------------------------------------------------------------------------------
-- paths (world, feet level)
-------------------------------------------------------------------------------------------------
function Sites.path(site: any, from: Vector3, to: Vector3, comp: number?): { Vector3 }?
	if not site.nav then
		return nil
	end
	local ax, az = toLocal(site, from)
	local bx, bz = toLocal(site, to)
	local pts = site.nav:path(ax, az, bx, bz, comp)
	if not pts then
		return nil
	end
	local out = table.create(#pts)
	for _, p in pts do
		table.insert(out, toWorld(site, p[1], p[2]))
	end
	-- the exact goal height / position
	out[#out] = Vector3.new(to.X, site.floorY, to.Z)
	out[1] = Vector3.new(from.X, site.floorY, from.Z)
	return out
end

-- a free floor spot near a world point (for stepping aside / looking busy), or nil
function Sites.freeNear(site: any, p: Vector3, r: number, comp: number?): Vector3?
	if not site.nav then
		return nil
	end
	local lx, lz = toLocal(site, p)
	local x, z = site.nav:nearestFree(lx, lz, r, comp, 1)
	if not x then
		return nil
	end
	return toWorld(site, x, z :: number)
end

-- is a world point inside the footprint (pad studs)
function Sites.inside(site: any, p: Vector3, pad: number?): boolean
	local x, z = toLocal(site, p)
	local g = pad or 0
	return math.abs(x) <= site.sx / 2 + g and math.abs(z) <= site.sz / 2 + g and p.Y > site.floorY - 4 and p.Y < site.floorY + 14
end

-------------------------------------------------------------------------------------------------
-- published spots (other systems / the client interior keep these clear)
-------------------------------------------------------------------------------------------------
local function root(): Folder
	if spotRoot and spotRoot.Parent then
		return spotRoot
	end
	local w = workspace:FindFirstChild(Shared.WORLD)
	if not w then
		w = Instance.new("Folder")
		w.Name = Shared.WORLD
		w.Parent = workspace
	end
	local f = w:FindFirstChild("Spots")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Spots"
		f.Parent = w
	end
	spotRoot = f :: Folder
	return f :: Folder
end

local function safeName(key: string): string
	return (string.gsub(key, "[^%w가-힣@,_%-#]", "_"))
end

function Sites.publish(site: any)
	if not site.spots then
		return
	end
	local name = safeName(site.key)
	local f = root():FindFirstChild(name)
	if f then
		return
	end
	local nf = Instance.new("Folder")
	nf.Name = name
	nf:SetAttribute("ShopKey", site.key)
	local function put(kind: string, sp: any?)
		if not sp then
			return
		end
		local p = Instance.new("Part")
		p.Name = "Spot_" .. kind
		p.Size = Vector3.new(1.2, 0.2, 1.2)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.CFrame = CFrame.new(sp.pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, math.rad(sp.yaw or 0), 0)
		p:SetAttribute("ShopKey", site.key)
		p:SetAttribute("Kind", kind)
		p:SetAttribute("Radius", 1.2)
		p.Parent = nf
		CollectionService:AddTag(p, Shared.SPOT_TAG)
	end
	put("cook", site.spots.C)
	put("service", site.spots.S)
	put("home", site.spots.H)
	put("cashier", site.spots.K)
	for _, e in site.spots.A do
		put("approach", e.best)
	end
	nf.Parent = root()
end

function Sites.unpublish(key: string)
	local f = spotRoot and spotRoot:FindFirstChild(safeName(key))
	if f then
		f:Destroy()
	end
end

function Sites.status(): any
	local out = {}
	for k, s in cache do
		out[k] = { ok = s.ok, why = s.why, roles = s.roles and #s.roles or 0, tables = #s.tables }
	end
	return out
end

return Sites
