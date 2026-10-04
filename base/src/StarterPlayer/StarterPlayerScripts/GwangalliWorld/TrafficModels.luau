-- GwangalliWorld/TrafficModels: the car bodies of the client ambient traffic.
--
-- TEMPLATES: the map's own realistic cars (build/kit/vehicles.luau: Sonata, G80, Ray, Tucson, Carnival,
-- Porter, Busan taxi) are reused. The first complete car of a kind that streams in near the player
-- (ParkedVehicles / TrafficVehicles, offered by TrafficCars) is cloned ONCE and stripped for moving
-- traffic: the near-only "Detail" model goes, the "Interior" keeps only seats, dash and the steering
-- hub (the people sit in it), tiny trims and most SurfaceGuis go, every CollectionService tag goes (the
-- clones never join Signage / DetailLOD / MobileQuality). Every part becomes non-colliding, massless
-- and welded (WeldConstraint) to one anchored invisible root "TrafficRoot" at the car's ground point
-- (LookVector = the car's front), so moving a car is ONE CFrame write (TrafficCars sends all roots in
-- one workspace:BulkMoveTo). A kind with no template yet gets a built-in 16-part body of the same size.
--
-- POOL: Models.acquire(kind, color?) -> rec (a clone of the template; idle clones are reused and
-- repainted), Models.release(rec). rec = { kind, model, root, info, color, lamps, paint, ls }.
-- rec.info = car geometry in the car frame (front = -Z): len, width, side (x of the door skin), seats
-- (driver / passenger / rearL / rearR: { x, top (cushion top y), back (z of the backrest face) }),
-- doorF / doorR ({ z0, z1 }), sill / belt / roof heights.
--
-- LAMPS: Models.setLamps(rec, head 0|1|2, tail 0|1|2, ind nil|"L"|"R"|"H", blinkOn, sign) — head 0 off
-- / 1 daytime running lamps / 2 headlights; tail 0 off / 1 running / 2 brake; ind = indicators (H =
-- hazards). Writes only what changed. Models.flash(rec | static model) blinks for a lock chirp.
-- DOORS: the kit cars have no separate door parts, so Models.door(carCF, info, which, color) puts a
-- door skin (panel + window) over the body and swings it on a hinge (TweenService) — open(true/false),
-- remove(). SOUNDS: Models.play(part, id, speed, volume) (rbxasset:// sounds only).

local TweenService = game:GetService("TweenService")

local Models = {}

local Cfg: any
local Util: any
local folder: Instance
local lowTier = false

-- kinds the traffic uses and the names of their kit models (VehicleKind attribute)
Models.KINDS = { sedan = true, suv = true, taxi = true, compact = true, van = true, luxury = true, truck = true }
local KEEP_COLOR = { taxi = true, truck = true }

-- interior parts kept in the traffic clones (the cabin people sit in, seen through the glass)
local KEEP_INTERIOR = { SeatBack = true, SeatCushion = true, Dash = true, DashTop = true, WheelHub = true, Headrest = "mid" }
-- exterior parts dropped from the clones (tiny trims nobody sees on a moving car)
local DROP = { BrakeDisc = true, BeltChrome = true, WindowChrome = true, ArchCladding = true, Diffuser = true, LowerIntake = true, Caliper = true }
local DROP_LOW = { ArchTrim = true, NoseCorner = true, FrontLip = true, RoofRail = true, DoorHandle = true }
-- minimum exterior parts of a complete (fully streamed-in) car per kind
local MIN_PARTS = { sedan = 55, luxury = 60, taxi = 58, compact = 50, suv = 58, van = 60, truck = 45 }

local HEAD = { HeadlampLens = true, Headlamp = true, DRL = true, DRLBar = true, DRLWing = true, StarMapDRL = true, QuadLamp = true }
local DRL = { DRL = true, DRLBar = true, DRLWing = true, StarMapDRL = true }
local TAIL = { TailLamp = true, TailBar = true, TailLine = true, TailClaw = true }
local IND = { Repeater = true, TurnLamp = true }

local NEON = Enum.Material.Neon
local HEAD_ON = Color3.fromRGB(250, 252, 255)
local TAIL_RUN = Color3.fromRGB(200, 20, 26)
local TAIL_BRAKE = Color3.fromRGB(255, 40, 36)
local IND_ON = Color3.fromRGB(255, 150, 30)
local SIGN_ON = Color3.fromRGB(255, 214, 90)

local templates: { [string]: any } = {}
local tried: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local idle: { [string]: { any } } = {}
local stats = { clones = 0, reused = 0, fallback = 0, templates = 0, repaint = 0 }
Models.stats = stats

-- default geometry by kind (car frame, front = -Z) when a body has no interior to measure
local DEFAULT_INFO = {
	sedan = { len = 16.6, width = 6.2, side = 3.05, ftop = 2.0, fx = 1.25, fback = 1.03, rtop = 2.04, rback = 3.75, sill = 1.25, belt = 3.05, roof = 4.6, height = 5.1 },
	compact = { len = 12.2, width = 5.5, side = 2.7, ftop = 2.2, fx = 1.05, fback = 0.95, rtop = 2.2, rback = 3.55, sill = 1.25, belt = 3.1, roof = 5.4, height = 5.9 },
	suv = { len = 15.6, width = 6.3, side = 3.1, ftop = 2.35, fx = 1.25, fback = 1.05, rtop = 2.4, rback = 3.8, sill = 1.5, belt = 3.4, roof = 5.3, height = 5.8 },
	van = { len = 17.2, width = 6.5, side = 3.2, ftop = 2.4, fx = 1.3, fback = 0.4, rtop = 2.45, rback = 3.6, sill = 1.5, belt = 3.4, roof = 5.6, height = 6.1 },
	truck = { len = 17.0, width = 5.9, side = 2.95, ftop = 2.27, fx = 1.25, fback = -3.73, rtop = 2.27, rback = -3.73, sill = 1.5, belt = 3.6, roof = 5.9, height = 6.4, cabFwd = true },
}
DEFAULT_INFO.luxury = DEFAULT_INFO.sedan
DEFAULT_INFO.taxi = DEFAULT_INFO.sedan

local function infoFromDefault(kind: string): any
	local d = DEFAULT_INFO[kind] or DEFAULT_INFO.sedan
	local seats = {
		driver = { x = -d.fx, top = d.ftop, back = d.fback },
		passenger = { x = d.fx, top = d.ftop, back = d.fback },
	}
	if not d.cabFwd then
		seats.rearL = { x = -d.fx, top = d.rtop, back = d.rback }
		seats.rearR = { x = d.fx, top = d.rtop, back = d.rback }
	end
	return {
		len = d.len,
		width = d.width,
		side = d.side,
		height = d.height,
		seats = seats,
		doorF = { z0 = d.fback - 3.4, z1 = d.fback + 0.45 },
		doorR = if d.cabFwd then nil else { z0 = d.fback + 0.55, z1 = d.rback + 0.3 },
		sill = d.sill,
		belt = d.belt,
		roof = d.roof,
	}
end

-------------------------------------------------------------------------------------------------
-- Geometry of a kit car model
-------------------------------------------------------------------------------------------------

-- extents of a part along the axes of `frame` (half sizes) and its centre in frame space
local function extents(frame: CFrame, p: BasePart): (Vector3, number, number, number)
	local rc = frame:ToObjectSpace(p.CFrame)
	local s = p.Size * 0.5
	local r, u, l = rc.RightVector, rc.UpVector, rc.LookVector
	-- columns of the rotation: a part axis' contribution along frame X / Y / Z
	local ex = math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(-l.X) * s.Z
	local ey = math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(-l.Y) * s.Z
	local ez = math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(-l.Z) * s.Z
	return rc.Position, ex, ey, ez
end

-- Ground frame of a kit car (Underbody / Chassis centre at tyre-contact height, LookVector = front).
function Models.frameOf(model: Instance): CFrame?
	local ref = model:FindFirstChild("Underbody") or model:FindFirstChild("Chassis")
	if not ref or not ref:IsA("BasePart") then
		return nil
	end
	local cf = ref.CFrame
	local ground: number? = nil
	for _, c in model:GetChildren() do
		if c.Name == "Tyre" and c:IsA("BasePart") then
			local b = c.Position.Y - c.Size.Y * 0.5
			ground = if ground then math.min(ground, b) else b
		end
	end
	local pos = cf.Position
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.1 then
		return nil
	end
	local g = Vector3.new(pos.X, ground or (pos.Y - 0.765), pos.Z)
	return CFrame.lookAt(g, g + look.Unit)
end

-- Measures seats / doors / size of a car model in its ground frame. `kind` picks the defaults for
-- whatever is missing (a cabin that did not stream in).
function Models.analyze(model: Instance, frame: CFrame, kind: string): any
	local info = infoFromDefault(kind)
	local zMin, zMax, xMax, yMax = math.huge, -math.huge, 0, 0
	local sideX, sillY, beltY, roofY = 0, nil :: number?, nil :: number?, nil :: number?
	local cushions, backs = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "TrafficRoot" then
			local c, ex, ey, ez = extents(frame, d)
			local n = d.Name
			if n == "SeatCushion" then
				table.insert(cushions, { x = c.X, z = c.Z, top = c.Y + ey, ex = ex })
			elseif n == "SeatBack" then
				table.insert(backs, { x = c.X, z = c.Z, face = c.Z - ez, ex = ex })
			elseif d.Parent == model then
				zMin = math.min(zMin, c.Z - ez)
				zMax = math.max(zMax, c.Z + ez)
				xMax = math.max(xMax, math.abs(c.X) + ex)
				yMax = math.max(yMax, c.Y + ey)
				if n == "BodySide" or n == "Sill" or n == "Shoulder" or n == "CabSide" then
					sideX = math.max(sideX, math.abs(c.X) + ex)
				end
				if n == "Sill" then
					sillY = math.max(sillY or 0, c.Y + ey)
				elseif n == "Shoulder" or n == "CabSide" then
					beltY = math.max(beltY or 0, c.Y + ey)
				elseif n == "Roof" or n == "CabRoof" then
					roofY = c.Y - ey
				end
			end
		end
	end
	if zMax > zMin then
		info.len = zMax - zMin
		info.zMin, info.zMax = zMin, zMax
	end
	if xMax > 1 then
		info.width = xMax * 2
	end
	if yMax > 1 then
		info.height = yMax
	end
	if sideX > 1 then
		info.side = sideX
	end
	info.sill = sillY or info.sill
	info.belt = beltY or info.belt
	info.roof = roofY or info.roof
	-- seats: front cushions (smallest z) -> driver (x < 0) / passenger; the rear bench -> rearL / rearR
	if #cushions > 0 then
		table.sort(cushions, function(a, b)
			return a.z < b.z
		end)
		local zFront = cushions[1].z
		local function backFace(cu: any): number
			local best: number? = nil
			for _, b in backs do
				if math.abs(b.x - cu.x) < math.max(1.0, cu.ex) and b.z > cu.z and (best == nil or b.face < best) then
					best = b.face
				end
			end
			return best or (cu.z + 0.7)
		end
		local seats: any = {}
		for _, cu in cushions do
			if math.abs(cu.z - zFront) < 1.2 then
				if cu.ex > 1.6 then
					-- a bench across the cab (Porter): driver left, passenger right
					seats.driver = { x = cu.x - 1.2, top = cu.top, back = backFace(cu) }
					seats.passenger = { x = cu.x + 1.0, top = cu.top, back = backFace(cu) }
				elseif cu.x < 0 then
					seats.driver = { x = cu.x, top = cu.top, back = backFace(cu) }
				else
					seats.passenger = { x = cu.x, top = cu.top, back = backFace(cu) }
				end
			elseif cu.z > zFront + 1.5 and not seats.rearL then
				local half = if cu.ex > 1.6 then 1.2 else 0
				seats.rearL = { x = cu.x - half, top = cu.top, back = backFace(cu) }
				seats.rearR = { x = cu.x + half, top = cu.top, back = backFace(cu) }
			end
		end
		if seats.driver then
			seats.passenger = seats.passenger or { x = -seats.driver.x, top = seats.driver.top, back = seats.driver.back }
			info.seats = seats
			local fb = seats.driver.back
			info.doorF = { z0 = fb - 3.4, z1 = fb + 0.45 }
			if seats.rearL then
				info.doorR = { z0 = fb + 0.55, z1 = seats.rearL.back + 0.3 }
			else
				info.doorR = nil
			end
		end
	end
	return info
end

-------------------------------------------------------------------------------------------------
-- Lamps / paint discovery on a body (template clone or fallback)
-------------------------------------------------------------------------------------------------

local function scanBody(rec: any)
	local frame = rec.root.CFrame
	local lamps = { head = {}, drl = {}, tail = {}, indL = {}, indR = {}, sign = {} }
	local paint = {}
	local paintColor = rec.paintRef
	for _, d in rec.model:GetDescendants() do
		if d:IsA("BasePart") and d ~= rec.root then
			local n = d.Name
			local entry = { part = d, color = d.Color, mat = d.Material }
			if HEAD[n] then
				table.insert(lamps.head, entry)
				if DRL[n] then
					table.insert(lamps.drl, entry)
				end
			elseif TAIL[n] then
				table.insert(lamps.tail, entry)
			elseif n == "LampWrap" then
				local c = frame:PointToObjectSpace(d.Position)
				table.insert(if c.Z < 0 then lamps.head else lamps.tail, entry)
			elseif IND[n] then
				local c = frame:PointToObjectSpace(d.Position)
				table.insert(if c.X < 0 then lamps.indL else lamps.indR, entry)
			elseif n == "TaxiSign" then
				table.insert(lamps.sign, entry)
			elseif paintColor and d.Material ~= Enum.Material.Glass and d.Material ~= NEON and d.Parent == rec.model then
				local c = d.Color
				if math.abs(c.R - paintColor.R) + math.abs(c.G - paintColor.G) + math.abs(c.B - paintColor.B) < 0.03 then
					table.insert(paint, d)
				end
			end
		end
	end
	rec.lamps = lamps
	rec.paint = paint
	rec.ls = { head = -1, tail = -1, ind = nil, blink = false, sign = false }
end

local function paintOf(model: Instance): Color3?
	for _, n in { "Hood", "CabFront", "Roof", "BodySide" } do
		local p = model:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			return p.Color
		end
	end
	return nil
end
Models.paintOf = paintOf

-------------------------------------------------------------------------------------------------
-- Templates
-------------------------------------------------------------------------------------------------

local function stripTags(inst: Instance)
	for _, tag in inst:GetTags() do
		inst:RemoveTag(tag)
	end
end

local function makeRoot(model: Model, frame: CFrame): BasePart
	local root = Instance.new("Part")
	root.Name = "TrafficRoot"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = false
	root.CFrame = frame
	root.Parent = model
	model.PrimaryPart = root
	return root
end

local function weldAll(model: Model, root: BasePart)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			if lowTier or d.Size.X * d.Size.Y * d.Size.Z < 3.5 then
				d.CastShadow = false
			end
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
		end
	end
end

-- Is this streamed-in map car complete enough to copy? Returns the exterior part count or nil.
local function complete(model: Instance, kind: string): number?
	local n, tyres = 0, 0
	for _, c in model:GetChildren() do
		if c:IsA("BasePart") then
			n += 1
			if c.Name == "Tyre" then
				tyres += 1
			end
		end
	end
	if tyres < 4 or n < (MIN_PARTS[kind] or 50) then
		return nil
	end
	if not (model:FindFirstChild("Underbody") or model:FindFirstChild("Chassis")) then
		return nil
	end
	if not (model:FindFirstChild("Roof") or model:FindFirstChild("CabRoof")) then
		return nil
	end
	if not model:FindFirstChild("Windshield") then
		return nil
	end
	if kind == "taxi" and not model:FindFirstChild("TaxiSign") then
		return nil
	end
	local int = model:FindFirstChild("Interior")
	if not int or not int:FindFirstChild("SeatCushion") then
		return nil
	end
	return n
end

-- Offers a map car (any model with attribute VehicleKind) as the template of its kind. Cheap when
-- the kind already has one. Returns true when a template was made.
function Models.offer(model: Instance): boolean
	local kind = model:GetAttribute("VehicleKind")
	if type(kind) ~= "string" or not Models.KINDS[kind] or templates[kind] then
		return false
	end
	if kind == "taxi" and model:GetAttribute("CarModel") == nil then
		return false
	end
	local now = os.clock()
	local last = tried[model]
	if last and now - last < 6 then
		return false
	end
	tried[model] = now
	if not complete(model, kind) then
		return false
	end
	local frame = Models.frameOf(model)
	if not frame then
		return false
	end
	local ok, res = pcall(function()
		local clone = (model :: any):Clone() :: Model
		local paintRef = paintOf(clone)
		for _, d in clone:GetDescendants() do
			stripTags(d)
		end
		stripTags(clone)
		for _, k in clone:GetChildren() do
			if k:IsA("Model") then
				if k.Name == "Interior" then
					k:SetAttribute("LOD", nil)
					for _, p in k:GetChildren() do
						local keep = KEEP_INTERIOR[p.Name]
						if not keep or (keep == "mid" and lowTier) then
							p:Destroy()
						end
					end
				else
					k:Destroy() -- "Detail" (near-only trims) and anything else nested
				end
			elseif k:IsA("BasePart") and (DROP[k.Name] or (lowTier and DROP_LOW[k.Name])) then
				k:Destroy()
			end
		end
		for _, d in clone:GetDescendants() do
			if d:IsA("SurfaceGui") then
				local host = d.Parent
				local hn = host and host.Name or ""
				if hn == "PlateFront" or hn == "PlateRear" then
					d.MaxDistance = 60
				elseif hn ~= "TaxiSign" then
					d:Destroy()
				end
			elseif d:IsA("ProximityPrompt") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") or d:IsA("Light") then
				d:Destroy()
			end
		end
		for _, a in { "DriveUnlocked", "DriveRigged", "DriveDriver", "DriveLabel", "NoDrive" } do
			clone:SetAttribute(a, nil)
		end
		clone.Name = "Traffic_" .. kind
		local root = makeRoot(clone, frame)
		local info = Models.analyze(clone, frame, kind)
		weldAll(clone, root)
		local count = 0
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				count += 1
			end
		end
		return { model = clone, frame = frame, info = info, paintRef = paintRef, parts = count }
	end)
	if not ok then
		Util.warn("TrafficModels", "template", kind, res)
		return false
	end
	templates[kind] = res
	stats.templates += 1
	return true
end

function Models.hasTemplate(kind: string): boolean
	return templates[kind] ~= nil
end

function Models.templateParts(kind: string): number?
	local t = templates[kind]
	return t and t.parts
end

-------------------------------------------------------------------------------------------------
-- Built-in body (a kind without a template yet): 16 parts, same footprint as the kit car
-------------------------------------------------------------------------------------------------

local GLASS = Color3.fromRGB(26, 32, 38)
local TRIM = Color3.fromRGB(24, 24, 26)
local TYRE = Color3.fromRGB(30, 30, 32)

local function fallbackBody(kind: string): any
	local info = infoFromDefault(kind)
	local model = Instance.new("Model")
	model.Name = "Traffic_" .. kind .. "_basic"
	local root = makeRoot(model, CFrame.new())
	local L, W = info.len, info.width
	local hw = W / 2 - 0.15
	local paint = if kind == "taxi" then Color3.fromRGB(236, 237, 236) else Color3.fromRGB(238, 239, 238)
	local function box(name: string, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material?, transp: number?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(pos)
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Transparency = transp or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local belt = info.belt
	local roof = info.roof
	local cabZ0, cabZ1 = -L * 0.16, L * 0.3
	if kind == "truck" then
		cabZ0, cabZ1 = -L * 0.5 + 0.6, -L * 0.5 + 5.2
		box("Body", Vector3.new(W - 0.3, belt - 1.1, 5.6), Vector3.new(0, (belt + 1.1) / 2, -L * 0.5 + 3.4), paint)
		box("BedFloor", Vector3.new(W - 0.2, 0.4, L - 6.4), Vector3.new(0, 2.6, 2.9), Color3.fromRGB(176, 180, 184), Enum.Material.Metal)
		box("DropSide", Vector3.new(0.15, 1.2, L - 6.4), Vector3.new(-hw, 3.4, 2.9), Color3.fromRGB(176, 180, 184), Enum.Material.Metal)
		box("DropSide", Vector3.new(0.15, 1.2, L - 6.4), Vector3.new(hw, 3.4, 2.9), Color3.fromRGB(176, 180, 184), Enum.Material.Metal)
	else
		box("Body", Vector3.new(W - 0.3, belt - 1.0, L - 0.6), Vector3.new(0, (belt + 1.0) / 2, 0), paint)
		box("Hood", Vector3.new(W - 0.6, 0.3, -L / 2 - cabZ0 - 0.6), Vector3.new(0, belt + 0.1, (cabZ0 - L / 2) / 2), paint)
	end
	box("Glass", Vector3.new(W - 0.7, roof - belt - 0.2, cabZ1 - cabZ0), Vector3.new(0, (roof + belt) / 2 - 0.05, (cabZ0 + cabZ1) / 2), GLASS, Enum.Material.Glass, 0.25)
	box("Roof", Vector3.new(W - 0.9, 0.25, cabZ1 - cabZ0 - 0.6), Vector3.new(0, roof + 0.05, (cabZ0 + cabZ1) / 2), paint)
	for _, zx in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local z = zx[2] * (L / 2 - 3.2)
		local t = Instance.new("Part")
		t.Name = "Tyre"
		t.Shape = Enum.PartType.Cylinder
		t.Size = Vector3.new(0.75, 2.2, 2.2)
		t.CFrame = CFrame.new(zx[1] * (hw - 0.2), 1.1, z)
		t.Color = TYRE
		t.Material = Enum.Material.Rubber
		t.Parent = model
	end
	box("HeadlampLens", Vector3.new(1.2, 0.35, 0.1), Vector3.new(-hw + 0.9, belt - 0.5, -L / 2 + 0.25), Color3.fromRGB(208, 216, 226), Enum.Material.Glass)
	box("HeadlampLens", Vector3.new(1.2, 0.35, 0.1), Vector3.new(hw - 0.9, belt - 0.5, -L / 2 + 0.25), Color3.fromRGB(208, 216, 226), Enum.Material.Glass)
	box("TailLamp", Vector3.new(1.0, 0.4, 0.1), Vector3.new(-hw + 0.8, belt - 0.4, L / 2 - 0.25), Color3.fromRGB(150, 14, 22), Enum.Material.Glass)
	box("TailLamp", Vector3.new(1.0, 0.4, 0.1), Vector3.new(hw - 0.8, belt - 0.4, L / 2 - 0.25), Color3.fromRGB(150, 14, 22), Enum.Material.Glass)
	box("PlateRear", Vector3.new(1.6, 0.5, 0.06), Vector3.new(0, 1.6, L / 2 - 0.27), Color3.fromRGB(246, 246, 244))
	box("Bumper", Vector3.new(W - 0.2, 0.8, 0.5), Vector3.new(0, 1.0, -L / 2 + 0.25), TRIM)
	if kind == "taxi" then
		box("TaxiSign", Vector3.new(2.2, 0.55, 0.8), Vector3.new(0, roof + 0.45, (cabZ0 + cabZ1) / 2), Color3.fromRGB(240, 192, 40))
	end
	local seat = info.seats.driver
	box("SeatBack", Vector3.new(1.6, 1.9, 0.45), Vector3.new(seat.x, seat.top + 0.95, seat.back + 0.22), TRIM, Enum.Material.Fabric)
	weldAll(model, root)
	return { model = model, frame = CFrame.new(), info = info, paintRef = paint, parts = #model:GetChildren(), basic = true }
end

-------------------------------------------------------------------------------------------------
-- Pool
-------------------------------------------------------------------------------------------------

local function newRec(kind: string): any
	local tpl = templates[kind]
	local basic = false
	if not tpl then
		tpl = fallbackBody(kind)
		basic = true
		stats.fallback += 1
	end
	local model = if basic then tpl.model else tpl.model:Clone()
	local root = model.PrimaryPart or model:FindFirstChild("TrafficRoot") :: BasePart
	local rec = {
		kind = kind,
		model = model,
		root = root,
		info = tpl.info,
		paintRef = tpl.paintRef,
		color = tpl.paintRef,
		basic = basic,
		parts = tpl.parts,
	}
	scanBody(rec)
	stats.clones += 1
	return rec
end

local function repaint(rec: any, color: Color3)
	if rec.color == color then
		return
	end
	for _, p in rec.paint do
		p.Color = color
	end
	rec.color = color
	stats.repaint += 1
end

-- A car body of `kind` (pooled). color = paint (nil: keep). The model is parented to the traffic
-- folder; place it with rec.root.CFrame right away (same frame, before anything renders).
function Models.acquire(kind: string, color: Color3?): any
	local list = idle[kind]
	local rec = nil
	if list and #list > 0 then
		-- prefer a real (template) body over a basic one once the template exists
		for i = #list, 1, -1 do
			if not list[i].basic or not templates[kind] then
				rec = table.remove(list, i)
				break
			end
		end
		if not rec then
			local old = table.remove(list, 1)
			pcall(old.model.Destroy, old.model)
		end
	end
	if rec then
		stats.reused += 1
	else
		rec = newRec(kind)
	end
	if color and not KEEP_COLOR[kind] then
		repaint(rec, color)
	end
	rec.inUse = true
	rec.model.Parent = folder
	return rec
end

function Models.release(rec: any)
	if not rec or not rec.inUse then
		return
	end
	rec.inUse = false
	Models.setLamps(rec, 0, 0, nil, false, false)
	rec.model.Parent = nil
	local list = idle[rec.kind]
	if not list then
		list = {}
		idle[rec.kind] = list
	end
	table.insert(list, rec)
	-- keep a few spare bodies per kind
	while #list > 3 do
		local old = table.remove(list, 1)
		pcall(old.model.Destroy, old.model)
	end
end

-------------------------------------------------------------------------------------------------
-- Lamps
-------------------------------------------------------------------------------------------------

local function setGroup(group: { any }, on: boolean, color: Color3?)
	for _, e in group do
		local p = e.part
		if on then
			p.Material = NEON
			p.Color = color or e.color
		else
			p.Material = e.mat
			p.Color = e.color
		end
	end
end

function Models.setLamps(rec: any, head: number, tail: number, ind: string?, blinkOn: boolean, sign: boolean)
	local ls = rec.ls
	local L = rec.lamps
	if head ~= ls.head then
		ls.head = head
		if head == 2 then
			setGroup(L.head, true, HEAD_ON)
		elseif head == 1 then
			setGroup(L.head, false)
			setGroup(L.drl, true, HEAD_ON)
		else
			setGroup(L.head, false)
		end
	end
	if tail ~= ls.tail then
		ls.tail = tail
		if tail == 0 then
			setGroup(L.tail, false)
		else
			setGroup(L.tail, true, if tail == 2 then TAIL_BRAKE else TAIL_RUN)
		end
	end
	local litL = blinkOn and (ind == "L" or ind == "H")
	local litR = blinkOn and (ind == "R" or ind == "H")
	local wasL = ls.blink and (ls.ind == "L" or ls.ind == "H")
	local wasR = ls.blink and (ls.ind == "R" or ls.ind == "H")
	if litL ~= wasL then
		setGroup(L.indL, litL, IND_ON)
	end
	if litR ~= wasR then
		setGroup(L.indR, litR, IND_ON)
	end
	ls.ind, ls.blink = ind, blinkOn
	if sign ~= ls.sign then
		ls.sign = sign
		setGroup(L.sign, sign, SIGN_ON)
	end
end

-- Lamp groups of a STATIC map car (a parked car whose owner just got in): head / tail / indicator
-- parts, found once per scene. Returns a pseudo rec usable with Models.setLamps.
function Models.staticLamps(model: Instance, frame: CFrame): any
	local rec = { model = model, root = { CFrame = frame } }
	rec.paintRef = nil
	local lamps = { head = {}, drl = {}, tail = {}, indL = {}, indR = {}, sign = {} }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local n = d.Name
			local entry = { part = d, color = d.Color, mat = d.Material }
			if HEAD[n] then
				table.insert(lamps.head, entry)
				if DRL[n] then
					table.insert(lamps.drl, entry)
				end
			elseif TAIL[n] then
				table.insert(lamps.tail, entry)
			elseif n == "LampWrap" then
				table.insert(if frame:PointToObjectSpace(d.Position).Z < 0 then lamps.head else lamps.tail, entry)
			elseif IND[n] then
				table.insert(if frame:PointToObjectSpace(d.Position).X < 0 then lamps.indL else lamps.indR, entry)
			end
		end
	end
	rec.lamps = lamps
	rec.ls = { head = 0, tail = 0, ind = nil, blink = false, sign = false }
	return rec
end

-------------------------------------------------------------------------------------------------
-- Doors (a skin over the body that swings on a hinge)
-------------------------------------------------------------------------------------------------

-- which: "FL" driver, "FR" front passenger, "RL" / "RR" rear doors. Returns a door handle or nil.
function Models.door(carCF: CFrame, info: any, which: string, color: Color3?): any
	local range = if string.sub(which, 1, 1) == "F" then info.doorF else info.doorR
	if not range then
		return nil
	end
	local sx = if string.sub(which, 2, 2) == "L" then -1 else 1
	local z0, z1 = range.z0, range.z1
	local len = z1 - z0
	if len < 1.5 then
		return nil
	end
	local sill, belt, roof = info.sill or 1.2, info.belt or 3.0, info.roof or 4.5
	local x = sx * ((info.side or 3) + 0.04)
	local hingeLocal = CFrame.new(x, (sill + roof) / 2, z0)
	local hinge = Instance.new("Part")
	hinge.Name = "TrafficDoorHinge"
	hinge.Size = Vector3.new(0.2, 0.2, 0.2)
	hinge.Transparency = 1
	hinge.Anchored = true
	hinge.CanCollide = false
	hinge.CanTouch = false
	hinge.CanQuery = false
	hinge.CastShadow = false
	hinge.CFrame = carCF * hingeLocal
	local function skin(name: string, size: Vector3, offset: Vector3, c: Color3, mat: Enum.Material, transp: number)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = hinge.CFrame * CFrame.new(offset)
		p.Color = c
		p.Material = mat
		p.Transparency = transp
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Parent = hinge
		local w = Instance.new("WeldConstraint")
		w.Part0 = hinge
		w.Part1 = p
		w.Parent = p
		return p
	end
	local midY = (sill + roof) / 2
	local panelH = math.max(0.6, belt - sill)
	skin("DoorPanel", Vector3.new(0.16, panelH, len), Vector3.new(0, (sill + belt) / 2 - midY, len / 2), color or Color3.fromRGB(230, 230, 228), Enum.Material.SmoothPlastic, 0)
	skin("DoorWindow", Vector3.new(0.08, math.max(0.4, roof - belt - 0.15), len * 0.9), Vector3.new(0, (belt + roof - 0.15) / 2 - midY, len * 0.5), GLASS, Enum.Material.Glass, 0.45)
	skin("DoorHandle", Vector3.new(0.1, 0.12, 0.5), Vector3.new(sx * 0.1, belt - 0.3 - midY, len - 0.8), TRIM, Enum.Material.SmoothPlastic, 0)
	hinge.Parent = folder
	local handle = { hinge = hinge, closed = hinge.CFrame, sx = sx, open = false, tween = nil :: Tween? }
	return handle
end

function Models.swing(handle: any, open: boolean, duration: number?)
	if not handle or not handle.hinge.Parent then
		return
	end
	handle.open = open
	local goal = if open then handle.closed * CFrame.Angles(0, math.rad(62) * handle.sx, 0) else handle.closed
	if handle.tween then
		handle.tween:Cancel()
	end
	local tw = TweenService:Create(handle.hinge, TweenInfo.new(duration or (if open then 0.45 else 0.35), if open then Enum.EasingStyle.Quad else Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = goal })
	handle.tween = tw
	tw:Play()
end

function Models.removeDoor(handle: any)
	if handle and handle.hinge then
		if handle.tween then
			handle.tween:Cancel()
		end
		handle.hinge:Destroy()
	end
end

-------------------------------------------------------------------------------------------------
-- Sounds (one Sound per host part, reused)
-------------------------------------------------------------------------------------------------

function Models.play(host: Instance?, id: string, speed: number?, volume: number?)
	if not host or not host:IsA("BasePart") or id == "" then
		return
	end
	local s = host:FindFirstChild("TrafficSfx") :: Sound?
	if not s then
		local snd = Instance.new("Sound")
		snd.Name = "TrafficSfx"
		snd.RollOffMode = Enum.RollOffMode.InverseTapered
		snd.RollOffMinDistance = 12
		snd.RollOffMaxDistance = 130
		snd.Parent = host
		s = snd
	end
	local sound = s :: Sound
	if sound.SoundId ~= id then
		sound.SoundId = id
	end
	sound.PlaybackSpeed = speed or 1
	sound.Volume = volume or 0.5
	sound.TimePosition = 0
	sound:Play()
end

function Models.init(ctx: any, trafficFolder: Instance, cfg: any)
	Cfg = cfg
	Util = ctx.Util
	folder = trafficFolder
	lowTier = Util.isLow()
end

return Models
