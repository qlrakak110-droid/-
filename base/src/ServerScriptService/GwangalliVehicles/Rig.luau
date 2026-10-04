-- GwangalliVehicles/Rig: turns a static car Model into a drivable assembly at runtime.
--
--   DriveBase      invisible ballast root at axle height (85 % of the mass, RootPriority 127): the
--                  controller's reference frame, owns the movers (VectorForce + Torque)
--   DriveCollider  invisible box around the body (15 % of the mass): the ONLY colliding part
--   DriveWheel<i>  Motor6D base -> steer hub (suspension travel + steering, animated locally)
--   DriveSpin<i>   Motor6D hub -> spin part (rolling); tyre / rim / disc / spokes are welded to it
--   DriveSeat      VehicleSeat (driver) + DrivePassenger<i> Seats, invisible, Disabled until used
--   every visual part: WeldConstraint to DriveBase (or its wheel), Massless, no collide / touch /
--   query. The rig is born asleep (DriveBase anchored); Cars.wake() unanchors it.
-- Near-only sub-models (Interior / Detail, attribute LOD = "near") are replaced by fresh clones first:
-- the client DetailLOD registers anchored models by their position once, so a moving car needs new
-- instances that are born unanchored (it then tracks them as "moving" and keeps the cabin visible).

local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local Rig = {}

local VS: any = nil
local Analyze: any = nil

function Rig.init(shared: any, analyze: any)
	VS = shared
	Analyze = analyze
end

local function newPart(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Transparency = 1
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart, parent: Instance?): WeldConstraint
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = parent or b
	return w
end

local function v3t(v: Vector3): { number }
	local function r(n: number): number
		return math.floor(n * 1000 + 0.5) / 1000
	end
	return { r(v.X), r(v.Y), r(v.Z) }
end

-- Replace the LOD sub-models with unanchored clones (see header). Must run synchronously with the
-- welding that follows (no yields), so nothing falls.
local function freshLodModels(model: Model)
	for _, ch in model:GetChildren() do
		if ch:IsA("Model") and ch:GetAttribute("LOD") == "near" then
			local copy = ch:Clone()
			for _, d in copy:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = false
				end
			end
			ch:Destroy()
			copy.Parent = model
		end
	end
end

-- Remove joints a builder or an earlier rig may have left (the rig owns every joint).
local function stripJoints(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint") then
			d:Destroy()
		end
	end
end

-- Pure layout maths (also used by the physics tests): base / collider boxes, densities, inertia per
-- unit mass (ballast 85 % + collider 15 %, about their combined centre of mass), wheel positions.
function Rig.plan(info: any, spec: any): { [string]: any }
	local rAvg = 0
	for _, wh in info.wheels do
		rAvg += wh.r
	end
	rAvg /= #info.wheels
	local frame: CFrame = info.frame
	local baseCF = frame * CFrame.new(0, rAvg, 0)
	local bb = info.box
	local L, W = info.L, info.W
	local M = spec.mass
	local bs = Vector3.new(math.max(1, W * 0.8), 0.4, math.max(2, L * 0.85))
	local y0 = math.max(info.clearance, 0.55) + 0.1
	local y1 = math.max(y0 + 1.5, info.H * 0.98)
	local cSize = Vector3.new(math.max(1, W * 0.96), y1 - y0, math.max(2, L * 0.96))
	local cLocal = Vector3.new((bb.x0 + bb.x1) / 2, (y0 + y1) / 2, (bb.z0 + bb.z1) / 2)
	local colliderCF = frame * CFrame.new(cLocal)
	local cOff = baseCF:PointToObjectSpace(colliderCF.Position)
	local yc = 0.15 * cOff.Y
	local zc = 0.15 * cOff.Z
	local Iyaw = 0.85 * ((bs.X ^ 2 + bs.Z ^ 2) / 12 + zc ^ 2) + 0.15 * ((cSize.X ^ 2 + cSize.Z ^ 2) / 12 + (cOff.Z - zc) ^ 2)
	local Ipitch = 0.85 * ((bs.Y ^ 2 + bs.Z ^ 2) / 12 + yc ^ 2 + zc ^ 2) + 0.15 * ((cSize.Y ^ 2 + cSize.Z ^ 2) / 12 + (cOff.Y - yc) ^ 2 + (cOff.Z - zc) ^ 2)
	local Iroll = 0.85 * ((bs.X ^ 2 + bs.Y ^ 2) / 12 + yc ^ 2) + 0.15 * ((cSize.X ^ 2 + cSize.Y ^ 2) / 12 + (cOff.Y - yc) ^ 2)
	local wheels = {}
	for _, wh in info.wheels do
		local l = baseCF:PointToObjectSpace(frame:PointToWorldSpace(wh.center))
		table.insert(wheels, { x = l.X, y = l.Y, z = l.Z, r = wh.r, side = wh.side, front = wh.front, w = wh.x1 - wh.x0 })
	end
	return {
		rAvg = rAvg,
		baseCF = baseCF,
		baseSize = bs,
		baseDensity = math.clamp(M * 0.85 / (bs.X * bs.Y * bs.Z), 0.01, 100),
		colliderSize = cSize,
		colliderCF = colliderCF,
		colliderDensity = math.clamp(M * 0.15 / (cSize.X * cSize.Y * cSize.Z), 0.01, 100),
		I = { yaw = Iyaw, pitch = Ipitch, roll = Iroll },
		wheels = wheels,
	}
end

-- model: car Model (in the workspace or not). Returns the rig record or nil, reason.
function Rig.rig(model: Model, opts: { [string]: any }?): (any?, string?)
	local o = opts or {}
	if model:GetAttribute(VS.Attr.Rigged) then
		return nil, "already rigged"
	end
	local kind = model:GetAttribute(VS.Attr.Kind)
	local spec = VS.spec(kind)
	stripJoints(model)
	freshLodModels(model)
	local info, why = Analyze.run(model)
	if not info then
		return nil, why
	end

	local P = Rig.plan(info, spec)
	local frame: CFrame = info.frame
	local baseCF: CFrame = P.baseCF
	local bb = info.box
	local L, W = info.L, info.W
	local rAvg = P.rAvg

	local base = newPart(VS.Parts.Base, P.baseSize, baseCF, model)
	base.Massless = false
	base.RootPriority = 127
	base.CustomPhysicalProperties = PhysicalProperties.new(P.baseDensity, 0.3, 0, 1, 1)

	-- collider: body box from just above the ground clearance to the roof
	local cSize = P.colliderSize
	local collider = newPart(VS.Parts.Body, cSize, P.colliderCF, model)
	collider.Massless = false
	collider.CanCollide = true
	collider.CanQuery = true -- other cars' suspension rays and exit checks see it
	collider.CustomPhysicalProperties = PhysicalProperties.new(P.colliderDensity, 0.35, 0.05, 1, 1)
	weld(base, collider)
	local Iyaw, Ipitch, Iroll = P.I.yaw, P.I.pitch, P.I.roll

	-- wheels: steer hub + spin part per cluster
	local wheelOwned: { [BasePart]: boolean } = {}
	local wheelJson = {}
	local motors = {}
	for i, wh in info.wheels do
		local centreWorld = frame:PointToWorldSpace(wh.center)
		local hubCF = CFrame.fromMatrix(centreWorld, baseCF.RightVector, baseCF.UpVector, -baseCF.LookVector)
		local hub = newPart("DriveHub" .. i, Vector3.new(0.2, 0.2, 0.2), hubCF, model)
		local spin = newPart("DriveSpinPart" .. i, Vector3.new(0.2, 0.2, 0.2), hubCF, model)
		local m1 = Instance.new("Motor6D")
		m1.Name = VS.Parts.Wheel .. i
		m1.Part0 = base
		m1.Part1 = hub
		m1.C0 = baseCF:ToObjectSpace(hubCF)
		m1.C1 = CFrame.new()
		m1.Parent = base
		local m2 = Instance.new("Motor6D")
		m2.Name = "DriveSpin" .. i
		m2.Part0 = hub
		m2.Part1 = spin
		m2.C0 = CFrame.new()
		m2.C1 = CFrame.new()
		m2.Parent = hub
		for _, p in wh.parts do
			wheelOwned[p] = true
			weld(spin, p, spin)
		end
		for _, p in wh.calipers do
			wheelOwned[p] = true
			weld(hub, p, hub)
		end
		table.insert(wheelJson, P.wheels[i])
		motors[i] = { steer = m1, spin = m2 }
	end

	-- every other visual part rides on the base
	local visuals = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= base and d ~= collider then
			table.insert(visuals, d)
			if not wheelOwned[d] and not string.find(d.Name, "^DriveHub") and not string.find(d.Name, "^DriveSpinPart") then
				weld(base, d, d)
			end
		end
	end
	for _, p in visuals do
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.Anchored = false
	end
	base.Anchored = true

	-- seats
	local seats = {}
	local seatJson = {}
	for si, s in info.seats do
		local pos = frame:PointToWorldSpace(s.pos)
		local cls = if si == 1 then "VehicleSeat" else "Seat"
		local seat = Instance.new(cls) :: any
		seat.Name = if si == 1 then VS.Parts.DriverSeat else VS.Parts.Passenger .. (si - 1)
		seat.Size = Vector3.new(1.4, 0.3, 1.4)
		-- the top of the seat part sits a little into the cushion (keeps heads under the headliner)
		seat.CFrame = CFrame.fromMatrix(pos - baseCF.UpVector * 0.4, baseCF.RightVector, baseCF.UpVector, -baseCF.LookVector)
		seat.Anchored = false
		seat.CanCollide = false
		seat.CanTouch = false
		seat.CanQuery = false
		seat.Massless = true
		seat.Transparency = 1
		seat.Disabled = true
		if cls == "VehicleSeat" then
			seat.HeadsUpDisplay = false
			seat.MaxSpeed = 0
			seat.Torque = 0
			seat.TurnSpeed = 0
		end
		seat:SetAttribute("Sittable", false)
		seat:SetAttribute("SeatRole", s.role)
		seat.Parent = model
		weld(base, seat, seat)
		table.insert(seats, seat)
		local l = baseCF:PointToObjectSpace(pos)
		table.insert(seatJson, { x = l.X, y = l.Y, z = l.Z, role = s.role })
	end

	-- movers
	local att = Instance.new("Attachment")
	att.Name = "DriveMover"
	att.Parent = base
	local vf = Instance.new("VectorForce")
	vf.Name = VS.Parts.Force
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.zero
	vf.Parent = base
	local tq = Instance.new("Torque")
	tq.Name = VS.Parts.Torque
	tq.Attachment0 = att
	tq.RelativeTo = Enum.ActuatorRelativeTo.World
	tq.Torque = Vector3.zero
	tq.Parent = base

	-- headlight (one SpotLight, switched by the server) + horn
	local hlAtt = Instance.new("Attachment")
	hlAtt.Name = VS.Parts.Headlight
	local frontLocal = baseCF:PointToObjectSpace(frame:PointToWorldSpace(Vector3.new(0, math.min(info.frontTop, 3), bb.z0 - 0.3)))
	hlAtt.CFrame = CFrame.new(frontLocal)
	hlAtt.Parent = base
	local light = Instance.new("SpotLight")
	light.Name = "Headlight"
	light.Face = Enum.NormalId.Front
	light.Angle = 75
	light.Range = 70
	light.Brightness = 3.5
	light.Color = Color3.fromRGB(255, 244, 222)
	light.Shadows = false
	light.Enabled = false
	light.Parent = hlAtt
	local horn = Instance.new("Sound")
	horn.Name = "Horn"
	horn.SoundId = VS.Sounds.Horn
	horn.PlaybackSpeed = VS.Sounds.HornSpeed
	horn.Volume = 0.8
	horn.Looped = true
	horn.RollOffMaxDistance = 260
	horn.Parent = base
	local engine: Sound? = nil
	if VS.Sounds.Engine ~= "" then
		engine = Instance.new("Sound")
		local e = engine :: Sound
		e.Name = "Engine"
		e.SoundId = VS.Sounds.Engine
		e.Looped = true
		e.Volume = 0.35
		e.RollOffMaxDistance = 160
		e.Parent = base
	end

	-- lamp originals (the server switches materials on brake / lights)
	local lamps = { head = {}, tail = {}, turn = {} }
	for key, list in info.lamps do
		for _, p in list do
			table.insert(lamps[key], { part = p, material = p.Material, color = p.Color })
			-- keep the night-neon system away from lamps the drive system controls
			if CollectionService:HasTag(p, "NightNeon") then
				CollectionService:RemoveTag(p, "NightNeon")
			end
		end
	end

	-- camera / layout JSON for the clients
	local eyeL = baseCF:PointToObjectSpace(frame:PointToWorldSpace(info.eye))
	local hoodL = baseCF:PointToObjectSpace(frame:PointToWorldSpace(info.hood))
	local rigTable = {
		v = 1,
		kind = kind,
		L = L,
		W = W,
		H = info.H,
		rAvg = rAvg,
		wheels = wheelJson,
		seats = seatJson,
		eye = v3t(eyeL),
		hood = v3t(hoodL),
		I = { yaw = Iyaw, pitch = Ipitch, roll = Iroll },
		collider = { v3t(cSize), v3t(baseCF:PointToObjectSpace(collider.CFrame.Position)) },
	}
	local json = HttpService:JSONEncode(rigTable)
	model:SetAttribute(VS.Attr.Rig, json)
	model:SetAttribute(VS.Attr.Rigged, true)
	model:SetAttribute(VS.Attr.Driver, 0)
	model:SetAttribute(VS.Attr.State, 0)
	model:SetAttribute(VS.Attr.Sleeping, true)
	model:SetAttribute(VS.Attr.Label, spec.label)
	model.PrimaryPart = base
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	CollectionService:AddTag(model, VS.Tag)

	local rec = {
		model = model,
		kind = kind,
		spec = spec,
		info = info,
		rig = rigTable,
		base = base,
		collider = collider,
		seat = seats[1],
		passengers = { table.unpack(seats, 2) },
		seats = seats,
		motors = motors,
		vf = vf,
		tq = tq,
		light = light,
		horn = horn,
		engine = engine,
		lamps = lamps,
		rAvg = rAvg,
		doors = {
			driver = baseCF:PointToObjectSpace(frame:PointToWorldSpace(info.doorDriver)),
			passenger = baseCF:PointToObjectSpace(frame:PointToWorldSpace(info.doorPassenger)),
		},
		controller = nil,
		createdAt = os.clock(),
	}
	if o.onRigged then
		o.onRigged(rec)
	end
	return rec, nil
end

-- Base CFrame for a car standing on `groundFrame` (ground point, LookVector = heading).
function Rig.baseFor(rec: any, groundFrame: CFrame): CFrame
	return groundFrame * CFrame.new(0, rec.rAvg + 0.05, 0)
end

return Rig
