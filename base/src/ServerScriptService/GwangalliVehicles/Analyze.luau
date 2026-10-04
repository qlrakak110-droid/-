-- GwangalliVehicles/Analyze: reads a car Model built by build/kit/vehicles.luau (or anything that
-- follows docs/vehicles_contract.md) and returns its driving layout WITHOUT changing it:
--   frame (car frame on the ground: LookVector = front, UpVector = up, origin = centre between the
--   axles at tyre-contact height), body box, wheel clusters (+ the parts that spin with them), seats,
--   lamps, door / camera points. Names first (Tyre, SeatCushion, Underbody, Grille ...), geometry as
--   the fallback (cylinder parts low in the model, bench-like parts in the cabin), so later look
--   changes of the car models keep working.
-- Pure reads: only CFrame / Size / Name / Shape / attributes, so the same code runs in Lune tests.

local Analyze = {}

local TYRE_NAMES = { Tyre = true, Tire = true, Tyres = true, Tires = true, WheelTyre = true, WheelTire = true }
local SEAT_NAMES = { SeatCushion = true, Seat = true, BusSeat = true, DriverSeat = true, SeatBase = true }
-- parts that never belong to a wheel even when they sit inside the wheel circle
local NOT_WHEEL = { "well", "housing", "arch", "fender", "mudguard", "flap", "clad", "sill", "bumper", "step", "body" }
local FRONT_NAMES = { "grille", "headlamp", "headlight", "frontbumper", "platefront", "windshield", "hood", "drl", "nose", "bonnet" }
local REAR_NAMES = { "taillamp", "taillight", "platerear", "rearbumper", "tailgate", "trunk", "rearglass", "diffuser", "tailbar" }
local HEAD_LAMPS = { "headlamp", "headlight", "drl" }
local TAIL_LAMPS = { "taillamp", "taillight", "tailbar", "tailline", "brakelamp", "brakelight" }
local TURN_LAMPS = { "repeater", "turnlamp", "indicator", "blinker" }
local ANY_LAMP = { "lamp", "light", "led" } -- other lamps: front half -> head, rear half -> tail
local NOT_LAMP = { "wrap", "bezel", "housing", "trim", "arm", "base", "pod", "cover", "ceiling", "interior", "ambient" }
local NO_COLLIDE_BOX = { "mirror", "antenna", "sharkfin", "wiper", "flag", "sign", "lightbar", "beacon", "repeater", "handle" }

local function hasAny(lower: string, list: { string }): boolean
	for _, frag in list do
		if string.find(lower, frag, 1, true) then
			return true
		end
	end
	return false
end

local function insideInterior(p: Instance, model: Instance): boolean
	local node = p.Parent
	while node and node ~= model do
		if node.Name == "Interior" then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Half extent of an oriented part along a world direction.
local function halfAlong(cf: CFrame, size: Vector3, dir: Vector3): number
	return 0.5 * (math.abs(cf.RightVector:Dot(dir)) * size.X + math.abs(cf.UpVector:Dot(dir)) * size.Y + math.abs(cf.LookVector:Dot(dir)) * size.Z)
end

local function isCylinder(p: BasePart): boolean
	local ok, shape = pcall(function()
		return (p :: any).Shape
	end)
	return ok and shape == Enum.PartType.Cylinder
end

-- Tyre axis (world) for a tyre part: cylinders spin about their X axis; a block / mesh tyre about
-- its thinnest axis.
local function tyreAxis(p: BasePart): (Vector3, number, number)
	local cf, s = p.CFrame, p.Size
	if isCylinder(p) then
		return cf.RightVector, math.min(s.Y, s.Z) / 2, s.X
	end
	if s.X <= s.Y and s.X <= s.Z then
		return cf.RightVector, math.max(s.Y, s.Z) / 2, s.X
	elseif s.Z <= s.Y then
		return cf.LookVector, math.max(s.X, s.Y) / 2, s.Z
	end
	return cf.UpVector, math.max(s.X, s.Z) / 2, s.Y
end

function Analyze.parts(model: Instance): { BasePart }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- Returns info or nil, reason.
function Analyze.run(model: Model): (any?, string?)
	local parts = Analyze.parts(model)
	if #parts == 0 then
		return nil, "no parts"
	end
	local kind = model:GetAttribute("VehicleKind")

	-- 1) tyres: by name (outside the Interior), attribute DriveWheel, else low cylinders ---------------
	local tyres = {}
	for _, p in parts do
		if (TYRE_NAMES[p.Name] or p:GetAttribute("DriveWheel") == true) and not insideInterior(p, model) then
			table.insert(tyres, p)
		end
	end
	if #tyres < 3 then
		-- geometry fallback: cylinders 1.2-4.5 studs across, thinner than wide, in the lower part
		local minY, maxY = math.huge, -math.huge
		for _, p in parts do
			local y = p.CFrame.Position.Y
			minY, maxY = math.min(minY, y), math.max(maxY, y)
		end
		tyres = {}
		for _, p in parts do
			if isCylinder(p) and not insideInterior(p, model) then
				local s = p.Size
				local d = math.min(s.Y, s.Z)
				if d >= 1.2 and d <= 4.5 and s.X <= d * 0.75 and p.CFrame.Position.Y <= minY + (maxY - minY) * 0.45 then
					table.insert(tyres, p)
				end
			end
		end
	end
	if #tyres < 3 then
		return nil, "fewer than 3 tyres"
	end

	-- 2) frame --------------------------------------------------------------------------------------
	local up = Vector3.yAxis
	local axis = tyreAxis(tyres[1])
	axis = (axis - up * axis:Dot(up))
	if axis.Magnitude < 0.3 then
		return nil, "tyres not upright"
	end
	local right = axis.Unit
	local fwd = up:Cross(right) -- sign fixed below
	local function horiz(v: Vector3): Vector3
		local h = v - up * v:Dot(up)
		return if h.Magnitude > 1e-4 then h.Unit else v
	end
	local sign = 0
	local under = model:FindFirstChild("Underbody")
	if under and under:IsA("BasePart") then
		sign = if horiz(under.CFrame.LookVector):Dot(fwd) >= 0 then 1 else -1
	end
	if sign == 0 then
		local fSum, fN, rSum, rN = Vector3.zero, 0, Vector3.zero, 0
		for _, p in parts do
			if not insideInterior(p, model) then
				local lower = string.lower(p.Name)
				if hasAny(lower, FRONT_NAMES) then
					fSum += p.CFrame.Position
					fN += 1
				elseif hasAny(lower, REAR_NAMES) then
					rSum += p.CFrame.Position
					rN += 1
				end
			end
		end
		if fN > 0 and rN > 0 then
			local d = fSum / fN - rSum / rN
			if math.abs(d:Dot(fwd)) > 0.5 then
				sign = if d:Dot(fwd) > 0 then 1 else -1
			end
		end
	end
	if sign == 0 then
		-- steering wheel (Interior WheelRim / SteeringWheel) sits ahead of the seats' centre
		local sw, swN, seat, seatN = Vector3.zero, 0, Vector3.zero, 0
		for _, p in parts do
			local n = p.Name
			if n == "WheelRim" or n == "SteeringWheel" or n == "WheelHub" then
				sw += p.CFrame.Position
				swN += 1
			elseif SEAT_NAMES[n] then
				seat += p.CFrame.Position
				seatN += 1
			end
		end
		if swN > 0 and seatN > 0 then
			sign = if (sw / swN - seat / seatN):Dot(fwd) >= 0 then 1 else -1
		end
	end
	if sign == 0 then
		sign = 1
	end
	fwd *= sign
	right = fwd:Cross(up) -- Roblox: RightVector = LookVector x UpVector

	-- tyre metrics in a provisional frame (origin = tyre centroid)
	local c0 = Vector3.zero
	for _, t in tyres do
		c0 += t.CFrame.Position
	end
	c0 /= #tyres
	local frame0 = CFrame.fromMatrix(c0, right, up, -fwd)
	local tyreInfo = {}
	local groundY = math.huge
	for _, t in tyres do
		local _, r, w = tyreAxis(t)
		local l = frame0:PointToObjectSpace(t.CFrame.Position)
		table.insert(tyreInfo, { part = t, l = l, r = r, w = w })
		groundY = math.min(groundY, l.Y - r)
	end

	-- 3) wheel clusters: same side, same axle (dual rear tyres merge) -----------------------------
	local clusters = {}
	for _, t in tyreInfo do
		local side = if t.l.X >= 0 then 1 else -1
		local found = nil
		for _, c in clusters do
			if c.side == side and math.abs(c.z - t.l.Z) < math.max(c.r, t.r) then
				found = c
				break
			end
		end
		if found then
			table.insert(found.tyres, t)
			local n = #found.tyres
			found.z = (found.z * (n - 1) + t.l.Z) / n
			found.r = math.max(found.r, t.r)
		else
			table.insert(clusters, { side = side, z = t.l.Z, r = t.r, tyres = { t } })
		end
	end
	if #clusters < 3 then
		return nil, "fewer than 3 wheel positions"
	end
	local minZ, maxZ = math.huge, -math.huge
	for _, c in clusters do
		minZ, maxZ = math.min(minZ, c.z), math.max(maxZ, c.z)
	end
	local midZ = (minZ + maxZ) / 2
	local wheelbase = maxZ - minZ
	if wheelbase < 2 then
		return nil, "wheelbase too short"
	end
	-- final frame: origin between the axles, laterally centred, on the ground
	local xs, xn = 0, 0
	for _, c in clusters do
		local x0, x1 = math.huge, -math.huge
		for _, t in c.tyres do
			x0 = math.min(x0, t.l.X - t.w / 2)
			x1 = math.max(x1, t.l.X + t.w / 2)
		end
		c.x0, c.x1 = x0, x1
		xs += (x0 + x1) / 2
		xn += 1
	end
	local centreLocal = Vector3.new(0, groundY, midZ) -- keep x = 0 (tyre centroid is centred)
	local frame = frame0 * CFrame.new(centreLocal)
	local shift = -centreLocal
	local wheels = {}
	for _, c in clusters do
		local y = 0
		for _, t in c.tyres do
			y += t.l.Y
		end
		y = y / #c.tyres
		local ctr = Vector3.new((c.x0 + c.x1) / 2, y, c.z) + shift
		table.insert(wheels, {
			center = ctr,
			r = c.r,
			x0 = c.x0 + shift.X,
			x1 = c.x1 + shift.X,
			side = c.side,
			front = ctr.Z < 0, -- -Z = forward
			tyres = c.tyres,
			parts = {},
			calipers = {},
		})
	end
	table.sort(wheels, function(a, b)
		if a.front ~= b.front then
			return a.front
		end
		return a.side < b.side
	end)

	-- 4) parts that spin with a wheel (tyre, rim, disc, spokes, cap) / steer only (caliper) ---------
	local owner: { [BasePart]: boolean } = {}
	for _, p in parts do
		if insideInterior(p, model) then
			continue
		end
		local lower = string.lower(p.Name)
		if hasAny(lower, NOT_WHEEL) then
			continue
		end
		local l = frame:PointToObjectSpace(p.CFrame.Position)
		local s = p.Size
		local big = math.max(s.X, s.Y, s.Z)
		for _, wh in wheels do
			if big <= 2 * wh.r + 0.35 and l.X >= wh.x0 - 0.35 and l.X <= wh.x1 + 0.35 then
				local dy, dz = l.Y - wh.center.Y, l.Z - wh.center.Z
				if math.sqrt(dy * dy + dz * dz) <= wh.r * 1.02 then
					if string.find(lower, "caliper", 1, true) then
						table.insert(wh.calipers, p)
					else
						table.insert(wh.parts, p)
					end
					owner[p] = true
					break
				end
			end
		end
	end
	for _, wh in wheels do
		for _, t in wh.tyres do
			if not owner[t.part] then
				owner[t.part] = true
				table.insert(wh.parts, t.part)
			end
		end
	end

	-- 5) body box (collider), lamps --------------------------------------------------------------------
	local bb = { x0 = math.huge, x1 = -math.huge, y0 = math.huge, y1 = -math.huge, z0 = math.huge, z1 = -math.huge }
	local body = {}
	local lamps = { head = {}, tail = {}, turn = {} }
	local frontTop = -math.huge
	local frontAxleZ = math.huge
	local rearAxleZ = -math.huge
	for _, wh in wheels do
		if wh.front then
			frontAxleZ = math.min(frontAxleZ, wh.center.Z)
		else
			rearAxleZ = math.max(rearAxleZ, wh.center.Z)
		end
	end
	if frontAxleZ == math.huge then
		frontAxleZ = minZ - midZ
	end
	local fX, fY, fZ = frame.RightVector, frame.UpVector, frame.LookVector
	for _, p in parts do
		if owner[p] then
			continue
		end
		table.insert(body, p)
		local lower = string.lower(p.Name)
		local interior = insideInterior(p, model)
		local cf, s = p.CFrame, p.Size
		local l = frame:PointToObjectSpace(cf.Position)
		if not interior then
			if hasAny(lower, TURN_LAMPS) then
				table.insert(lamps.turn, p)
			elseif hasAny(lower, HEAD_LAMPS) then
				table.insert(lamps.head, p)
			elseif hasAny(lower, TAIL_LAMPS) then
				table.insert(lamps.tail, p)
			elseif hasAny(lower, ANY_LAMP) and not hasAny(lower, NOT_LAMP) then
				table.insert(if l.Z < 0 then lamps.head else lamps.tail, p)
			end
		end
		if interior or hasAny(lower, NO_COLLIDE_BOX) or p.Transparency >= 0.99 or math.max(s.X, s.Y, s.Z) < 0.5 then
			continue
		end
		if p.Parent and p.Parent:IsA("Model") and p.Parent ~= model and p.Parent:GetAttribute("LOD") == "near" then
			continue -- fine exterior detail (handles, badges, wipers)
		end
		local hx, hy, hz = halfAlong(cf, s, fX), halfAlong(cf, s, fY), halfAlong(cf, s, fZ)
		bb.x0, bb.x1 = math.min(bb.x0, l.X - hx), math.max(bb.x1, l.X + hx)
		bb.y0, bb.y1 = math.min(bb.y0, l.Y - hy), math.max(bb.y1, l.Y + hy)
		bb.z0, bb.z1 = math.min(bb.z0, l.Z - hz), math.max(bb.z1, l.Z + hz)
		if math.abs(l.Z - frontAxleZ) < 1.6 and math.abs(l.X) < 1.5 and p.Transparency < 0.3 then
			frontTop = math.max(frontTop, l.Y + hy)
		end
	end
	if bb.x0 == math.huge then
		return nil, "no body parts"
	end
	local roofY = bb.y1
	if frontTop == -math.huge then
		frontTop = roofY * 0.7
	end

	-- 6) seats ------------------------------------------------------------------------------------------
	local cushions = {}
	for _, p in parts do
		if SEAT_NAMES[p.Name] and not owner[p] then
			local l = frame:PointToObjectSpace(p.CFrame.Position)
			local hx = halfAlong(p.CFrame, p.Size, fX)
			local hy = halfAlong(p.CFrame, p.Size, fY)
			if l.Y > 0.3 and l.Y < roofY - 1 then
				table.insert(cushions, { l = l, w = 2 * hx, top = l.Y + hy, part = p })
			end
		end
	end
	local seats = {}
	if #cushions > 0 then
		local frontZ = math.huge
		for _, c in cushions do
			frontZ = math.min(frontZ, c.l.Z)
		end
		local driver, driverX = nil, math.huge
		for _, c in cushions do
			if c.l.Z <= frontZ + 1.0 and c.l.X < driverX then
				driver, driverX = c, c.l.X
			end
		end
		local function seatAt(x: number, c: any, role: string)
			table.insert(seats, { pos = Vector3.new(x, c.top, c.l.Z), role = role, width = c.w })
		end
		if driver then
			if driver.w >= 3 then -- front bench: driver on its left half
				seatAt(driver.l.X - driver.w / 4, driver, "driver")
				seatAt(driver.l.X + driver.w / 4, driver, "front")
			else
				seatAt(driver.l.X, driver, "driver")
			end
		end
		table.sort(cushions, function(a, b)
			if math.abs(a.l.Z - b.l.Z) > 0.5 then
				return a.l.Z < b.l.Z
			end
			return a.l.X > b.l.X
		end)
		for _, c in cushions do
			if c ~= driver then
				local role = if c.l.Z <= frontZ + 1.0 then "front" else "rear"
				if c.w >= 3 then
					seatAt(c.l.X + c.w / 4, c, role)
					seatAt(c.l.X - c.w / 4, c, role)
				else
					seatAt(c.l.X, c, role)
				end
			end
		end
	end
	if #seats == 0 then
		-- geometry fallback: a driver seat behind the front axle on the left
		local z = frontAxleZ + wheelbase * 0.42
		table.insert(seats, { pos = Vector3.new((bb.x0 + bb.x1) / 2 - (bb.x1 - bb.x0) * 0.2, math.min(2.1, roofY * 0.45), z), role = "driver", width = 1.6 })
		table.insert(seats, { pos = Vector3.new((bb.x0 + bb.x1) / 2 + (bb.x1 - bb.x0) * 0.2, math.min(2.1, roofY * 0.45), z), role = "front", width = 1.6 })
	end

	-- 7) camera / door points ------------------------------------------------------------------------------
	local drv = seats[1]
	local halfW = math.max(math.abs(bb.x0), math.abs(bb.x1))
	local info = {
		kind = kind,
		frame = frame,
		L = bb.z1 - bb.z0,
		W = bb.x1 - bb.x0,
		H = roofY,
		box = bb,
		clearance = math.max(0, bb.y0),
		wheels = wheels,
		wheelbase = wheelbase,
		seats = seats,
		lamps = lamps,
		body = body,
		frontTop = frontTop,
		eye = drv.pos + Vector3.new(0, math.clamp(roofY - drv.pos.Y - 0.55, 1.6, 2.45), 0.15),
		hood = Vector3.new(0, frontTop + 1.05, math.max(bb.z0 + 1.5, frontAxleZ + 1.2)),
		doorDriver = Vector3.new(-(halfW + 0.4), drv.pos.Y + 0.4, drv.pos.Z),
		doorPassenger = Vector3.new(halfW + 0.4, drv.pos.Y + 0.4, (seats[2] and seats[2].pos.Z) or drv.pos.Z),
		lod = {},
	}
	for _, ch in model:GetChildren() do
		if ch:IsA("Model") and ch:GetAttribute("LOD") == "near" then
			table.insert(info.lod, ch)
		end
	end
	return info, nil
end

return Analyze
