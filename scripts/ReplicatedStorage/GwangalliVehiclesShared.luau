-- GwangalliVehiclesShared: the driving system's shared contract (server GwangalliVehicles + client
-- GwangalliDrive) and the vehicle physics controller both of them run.
--
--   local VS = require(ReplicatedStorage.GwangalliVehiclesShared)
--   VS.Remotes / VS.Attr / VS.Bits / VS.Tag      names (single source of truth)
--   VS.Specs[kind]                                handling per model (Ray slow, G80 fast, Porter heavy)
--   VS.Catalog                                    the six callable hero models (phone "차 부르기")
--   VS.Controller                                 raycast-suspension car controller (pure maths +
--                                                 a Roblox wrapper); unit-tested in Lune and Rapier
--   VS.kmh(studsPerSecond) / VS.studs(kmh)        1 stud = 0.3 m -> 1 stud/s = 1.08 km/h
--
-- WHY A RAYCAST CONTROLLER (and not CylindricalConstraint / SpringConstraint / HingeConstraint wheels):
--   * no wheel colliders: kerbs (0.5 studs), stairs and thin map parts cannot snag or wedge a wheel,
--     which is where constraint cars jitter, climb walls or "explode" when two assemblies overlap;
--   * two movers per car (one VectorForce + one Torque on an invisible root) instead of 4 cylindrical
--     + 4 spring + 2 servo + 4 motor constraints: cheapest possible solver load on phones, and the
--     parked car is simply Anchored (zero cost) until someone gets in;
--   * the suspension force is IMPLICIT (backward Euler over the frame step), so it stays stable at
--     phone frame rates (tested 15-60 fps) even with Roblox's 196.2 studs/s^2 gravity, which needs a
--     stiff (~3.5 Hz) spring for a true-scale car;
--   * lateral tyre grip is solved per axle as a 2x2 system (lateral + yaw) so it never over-corrects
--     at low frame rates; grip / top speed / mass are plain numbers per model (arcade GTA feel).
-- The driver's client owns the assembly (network ownership) and runs the controller every frame;
-- the server runs the same code for a driverless car that is still rolling, then anchors it.

local VS = {}
VS.VERSION = 1

-- Names -------------------------------------------------------------------------------------------
VS.Remotes = {
	Folder = "GwangalliVehiclesRemotes", -- Folder in ReplicatedStorage (created by the server)
	Event = "Drive", -- RemoteEvent, both directions (payload tables with an `op` field)
	Call = "CallCar", -- RemoteFunction client -> server: ("call", kind) / ("dismiss") / ("status")
}

-- CollectionService tag on every car model the rigger has prepared (parked-unlocked or spawned).
VS.Tag = "GwangalliDrivable"

-- Attributes on the car Model (server writes, everyone reads) -------------------------------------
VS.Attr = {
	Kind = "VehicleKind", -- set by the builder (build/kit/vehicles.luau)
	Rig = "DriveRig", -- JSON: wheel / seat / camera layout (VS.decodeRig)
	Rigged = "DriveRigged", -- true once the physics rig exists
	Unlocked = "DriveUnlocked", -- parked NPC car that may be entered (30 %, stable per position)
	Owner = "DriveOwner", -- UserId of the player who called this car (player cars only)
	Driver = "DriveDriver", -- UserId of the current driver (0 = none)
	State = "DriveState", -- VS.Bits bitmask from the driver (lamps / horn / indicators)
	Sleeping = "DriveSleeping", -- true while the root is anchored (parked, zero physics cost)
	Label = "DriveLabel", -- Korean model name for prompts / UI
	Sunk = "DriveSunk", -- true once it went into the sea (despawns)
	NoDrive = "NoDrive", -- builders / other systems: set true to keep a car out of the drive system
	-- owned cars (GwangalliGarageShared.Attr is the full list; written by Garage / Spawn)
	Condition = "DriveCondition", -- 0..100 engine / body condition (the controller reads it: VS.Condition)
	Plate = "DrivePlate", -- plate text of an owned car
	CarId = "DriveCarId", -- the owner's d.cars record id
	OwnedCar = "DriveOwnedCar", -- true: only the owner may take the driver's seat
	TestDrive = "DriveTestDrive", -- unix time a 시승 car is taken back
	JobKind = "DriveJobKind", -- job vehicle kind (SpawnJobVehicle)
}

VS.Bits = { BRAKE = 1, REVERSE = 2, LIGHTS = 4, LEFT = 8, RIGHT = 16, HAZARD = 32, HORN = 64, HANDBRAKE = 128 }

-- Names of the parts / instances the rigger creates inside a car model.
VS.Parts = {
	Base = "DriveBase", -- invisible root (ballast, owns the movers, RootPriority 127)
	Body = "DriveCollider", -- invisible collision box (the only colliding part of a rigged car)
	DriverSeat = "DriveSeat", -- VehicleSeat
	Passenger = "DrivePassenger", -- Seat (name .. index)
	Wheel = "DriveWheel", -- Motor6D base -> steer hub (name .. index); spin Motor6D "DriveSpin" .. index
	Force = "DriveForce", -- VectorForce (world space, at the centre of mass)
	Torque = "DriveTorque", -- Torque (world space)
	Prompt = "DrivePrompt", -- Attachment holding the ProximityPrompt (name .. "Driver" / "Passenger")
	Headlight = "DriveHeadlight", -- Attachment with the SpotLight
}

VS.Sounds = {
	-- Replace with licensed asset ids (e.g. "rbxassetid://<id>") when you have them. Empty = silent.
	-- Built-in content only by default (no uploads): a short low beep stands in for the horn.
	Horn = "rbxasset://sounds/electronicpingshort.wav",
	HornSpeed = 0.42,
	Engine = "",
}

-- Limits (server) ---------------------------------------------------------------------------------
VS.Limits = {
	MaxActive = 14, -- awake (unanchored) rigged cars per server
	MaxPlayerCars = 1, -- called cars per player
	CallCooldown = 8, -- seconds between car calls per player
	GlobalCallGap = 0.5, -- seconds between any two spawns on the server
	CallRadius = 260, -- nearest road lane must be within this many studs of the player
	IdleDespawn = 300, -- an unoccupied called car despawns after this many seconds
	FarDespawn = 700, -- ... or when its owner is farther than this for FarGrace seconds
	FarGrace = 45,
	RestoreAfter = 180, -- a moved parked NPC car goes back to its spot after this long unattended
	UnlockedShare = 0.3, -- parked NPC cars that are unlocked
	EventRate = 20, -- client -> server Drive events per second (burst bucket)
}

VS.WATER_Y = 0 -- sea surface (build/kit/plan.luau Plan.SEA)

function VS.kmh(studsPerSecond: number): number
	return studsPerSecond * 1.08
end
function VS.studs(kmh: number): number
	return kmh / 1.08
end

-- Handling per VehicleKind ------------------------------------------------------------------------
-- mass (RMU, rig total without occupants), topKmh / reverseKmh, accel (studs/s^2 at standstill),
-- brake (studs/s^2), drive FWD|RWD|AWD, grip (lateral mu vs Roblox gravity: 0.25 ~ 1.5 g at true
-- scale), steer (deg at low / high speed), ride (static sag E, bump travel U, damping ratio z),
-- hbGrip (rear lateral mu with the handbrake: drift), roll (0 = tyre forces at the contact patch,
-- 1 = at the centre of mass: no body roll / no tipping).
local Specs = {}
Specs.compact = { -- box-type 경차: light, tall, slow
	label = "큐비", model = "큐비 박스카", mass = 110, topKmh = 88, reverseKmh = 24, accel = 12, brake = 36, drive = "FWD",
	gripF = 0.24, gripR = 0.26, steerLow = 36, steerHigh = 11, E = 0.34, U = 0.5, z = 0.6, hbGrip = 0.1, roll = 0.62,
}
Specs.sedan = { -- mid-size sedan
	label = "미드 세단", model = "미드 세단", mass = 150, topKmh = 118, reverseKmh = 28, accel = 16, brake = 40, drive = "FWD",
	gripF = 0.26, gripR = 0.28, steerLow = 34, steerHigh = 9, E = 0.32, U = 0.55, z = 0.55, hbGrip = 0.09, roll = 0.55,
}
Specs.luxury = { -- flagship sedan: heavy but fast, rear-drive
	label = "플래그십", model = "플래그십 세단", mass = 178, topKmh = 142, reverseKmh = 30, accel = 21, brake = 44, drive = "RWD",
	gripF = 0.27, gripR = 0.28, steerLow = 33, steerHigh = 8, E = 0.3, U = 0.55, z = 0.6, hbGrip = 0.08, roll = 0.55,
}
Specs.suv = { -- compact SUV
	label = "트레일 SUV", model = "트레일 SUV", mass = 170, topKmh = 112, reverseKmh = 28, accel = 14.5, brake = 38, drive = "AWD",
	gripF = 0.26, gripR = 0.27, steerLow = 34, steerHigh = 9, E = 0.36, U = 0.6, z = 0.55, hbGrip = 0.1, roll = 0.6,
}
Specs.van = { -- 9-seat family van
	label = "패밀리 밴", model = "패밀리 9인승 밴", mass = 196, topKmh = 106, reverseKmh = 26, accel = 12.5, brake = 36, drive = "FWD",
	gripF = 0.24, gripR = 0.26, steerLow = 32, steerHigh = 9, E = 0.36, U = 0.6, z = 0.58, hbGrip = 0.1, roll = 0.62,
}
Specs.truck = { -- 1-ton cab-over truck: heavy, slow, soft rear, rear-drive
	label = "1톤 트럭", model = "든든 1톤 트럭", mass = 240, topKmh = 92, reverseKmh = 22, accel = 10, brake = 30, drive = "RWD",
	gripF = 0.22, gripR = 0.24, steerLow = 36, steerHigh = 11, E = 0.4, U = 0.6, z = 0.5, hbGrip = 0.1, roll = 0.62,
}
Specs.taxi = Specs.sedan
Specs.police = Specs.sedan
VS.Specs = Specs
VS.DEFAULT_KIND = "sedan"

-- Kinds a player may drive (parked NPC cars and called cars). Taxis belong to the taxi service,
-- police / ambulance / buses / scooters stay scenery; moving traffic is never enterable.
VS.Drivable = { sedan = true, luxury = true, compact = true, suv = true, van = true, truck = true }

-- The six drivable kinds. Players call only the cars they OWN (GwangalliGarageShared / Garage.luau);
-- this free list is shown only to admins / with the dev switch (VS.freeSpawnAllowed).
VS.Catalog = {
	{ kind = "sedan", glyph = "🚗", blurb = "무난한 국민 세단" },
	{ kind = "luxury", glyph = "🏎️", blurb = "가장 빠른 후륜 세단" },
	{ kind = "compact", glyph = "🚙", blurb = "작고 느긋한 경차" },
	{ kind = "suv", glyph = "🚙", blurb = "사륜구동 SUV" },
	{ kind = "van", glyph = "🚐", blurb = "9인승 패밀리 밴" },
	{ kind = "truck", glyph = "🛻", blurb = "무거운 1톤 트럭" },
}

function VS.spec(kind: string?): any
	return Specs[kind or ""] or Specs[VS.DEFAULT_KIND]
end

-- Free spawning of any kind ("차 부르기" without owning the car): dev switch or admin only.
-- Server: Player attribute GwangalliAdmin is written by GwangalliLiveOps (server authority).
function VS.freeSpawnAllowed(player: any): boolean
	if workspace:GetAttribute("GwangalliDriveUnlockAll") == true then
		return true
	end
	return player ~= nil and player:GetAttribute("GwangalliAdmin") == true
end

-- Condition -> engine (docs/GARAGE.md). Bands match GwangalliGarageShared.COND: below `worn` the
-- engine stutters (short torque dips, more often the worse it gets), below `bad` the top speed drops by
-- 40 % and the torque by 25 %, at 0 the engine is dead (no drive force; brakes / steering still work).
VS.Condition = {
	worn = 60,
	bad = 30,
	badTop = 0.6,
	badPower = 0.75,
	dipPower = 0.3, -- torque share during a stutter dip
	dipLen = { 0.25, 0.55 }, -- s, at the top / bottom of the worn band
	period = { 6, 2.2 }, -- s between dips, at the top / bottom of the worn band
}

-- power (torque share), top (top-speed share) for a condition at time t (seconds, any clock).
function VS.enginePower(cond: number?, t: number, seed: number?): (number, number)
	local C = VS.Condition
	if type(cond) ~= "number" or cond ~= cond or cond >= C.worn then
		return 1, 1
	end
	if cond <= 0 then
		return 0, 0
	end
	local power, top = 1, 1
	if cond < C.bad then
		power, top = C.badPower, C.badTop
	end
	local sev = math.clamp((C.worn - cond) / C.worn, 0, 1)
	local period = C.period[1] + (C.period[2] - C.period[1]) * sev
	local len = C.dipLen[1] + (C.dipLen[2] - C.dipLen[1]) * sev
	local x = (t + (seed or 0)) / period
	local cycle = math.floor(x)
	-- irregular: each cycle's dip starts at a hashed offset inside the cycle
	local jitter = (math.sin(cycle * 12.9898 + (seed or 0) * 0.37) * 43758.5453) % 1
	local phase = (x - cycle) * period - jitter * (period - len)
	if phase >= 0 and phase < len then
		power *= C.dipPower
	end
	return power, top
end

-- Rig JSON (VS.Attr.Rig) ------------------------------------------------------------------------------
-- { v = 1, kind, L, W, H, wheels = { {x, y, z, r, side, front, drive, steer, w} }, seats = { {x, y, z} },
--   eye = {x, y, z}, hood = {x, y, z}, I = {yaw, pitch, roll} (per unit mass), comY }
-- All coordinates in DriveBase space (x right, y up, -z forward = the base's LookVector).
function VS.decodeRig(json: string?): any
	if type(json) ~= "string" or json == "" then
		return nil
	end
	local ok, res = pcall(function()
		return game:GetService("HttpService"):JSONDecode(json)
	end)
	if ok and type(res) == "table" and type(res.wheels) == "table" then
		return res
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Controller
---------------------------------------------------------------------------------------------------
local Ctl = {}
VS.Controller = Ctl

Ctl.GRAVITY = 196.2
-- Rays per wheel: along the car's forward axis at these multiples of the tyre radius. The tyre is
-- a circle, so the edge rays let a wheel "see" a kerb before its centre reaches it (smooth climb).
Ctl.RAY_OFFSETS = { 0, 0.62, -0.62 }
Ctl.LAT_GAIN = 0.8 -- share of an axle's sideways slip cancelled per frame
Ctl.DRAG = 0.22 -- aero drag at top speed, as a share of the standstill acceleration force
Ctl.ROLLING = 0.012 -- rolling resistance (1/s)
Ctl.LONG_GRIP = 0.45 -- longitudinal tyre mu (traction, braking) vs Roblox gravity
Ctl.HOLD_GRIP = 0.85 -- static mu while parked with no input (slope hold)
Ctl.HOLD_ENGAGE = 2.0 -- studs/s: pedals free and slower than this -> parking hold (static friction)
Ctl.HOLD_RELEASE = 12 -- studs/s: a shove faster than this frees a held car (a pedal always does)
Ctl.REVERSE_DELAY = 0.25 -- s the brake must be held at a standstill before it becomes reverse
Ctl.ENGINE_BRAKE = 0.35 -- off-throttle deceleration as a share of spec.accel (GTA feel: lifting the gas slows the car)
-- Roblox gravity (196.2 studs/s^2) is six times the game's scale (1 stud = 0.3 m -> 32.7 would be
-- true scale), so an uncompensated 15 deg ramp pulls at 51 studs/s^2: more than any car's engine, and
-- every descent a runaway. While grounded, this share of gravity's along-road component is cancelled
-- (through the centre of mass), which leaves hills at about true-scale strength.
Ctl.SLOPE_ASSIST = 0.8
Ctl.MAX_DT = 1 / 15
Ctl.MIN_DT = 1 / 240

local V3 = Vector3.new
local ZERO = Vector3.zero
local UP = Vector3.yAxis

local function clamp(x: number, a: number, b: number): number
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

-- rig: decoded VS.Attr.Rig table; spec: VS.Specs entry. Returns the controller state.
function Ctl.new(rig: any, spec: any): any
	local wheels = {}
	local nDrive = 0
	for i, w in rig.wheels do
		local drive = w.drive
		if drive == nil then
			if spec.drive == "AWD" then
				drive = true
			elseif spec.drive == "RWD" then
				drive = not w.front
			else
				drive = w.front
			end
		end
		if drive then
			nDrive += 1
		end
		wheels[i] = {
			x = w.x, y = w.y, z = w.z, r = w.r, side = w.side, front = w.front, drive = drive,
			steer = if w.steer == nil then w.front else w.steer,
			s = 0, -- displacement from the rest pose (+ up), studs
			grounded = false,
			spin = 0, -- rolling angle (rad)
			load = 0,
			contact = nil :: Vector3?,
			normal = nil :: Vector3?,
			material = nil,
		}
	end
	local I = rig.I or {}
	return {
		rig = rig,
		spec = spec,
		wheels = wheels,
		nDrive = math.max(1, nDrive),
		steer = 0, -- current road-wheel angle (rad)
		gear = "P",
		speed = 0, -- forward speed (studs/s, + forward)
		grounded = 0,
		Iyaw = I.yaw or 30, -- per unit mass (studs^2)
		Ipitch = I.pitch or 30,
		Iroll = I.roll or 6,
		reverseLatch = false,
		stopHold = 0, -- s the brake has been held at a standstill (reverse engages after REVERSE_DELAY)
		holding = false, -- parking hold latch (static friction; see solve)
		lastForce = ZERO,
		lastTorque = ZERO,
	}
end

-- World-space rays for the current base CFrame: array of { origin, dir, wheel, off } (3 per wheel).
function Ctl.buildRays(st: any, cf: CFrame): { any }
	local rays = table.create(#st.wheels * #Ctl.RAY_OFFSETS)
	local spec = st.spec
	local up = cf.UpVector
	local fwd = cf.LookVector
	for i, w in st.wheels do
		local anchor = cf:PointToWorldSpace(V3(w.x, w.y + spec.U, w.z))
		for _, k in Ctl.RAY_OFFSETS do
			local off = k * w.r
			local reach = spec.U + spec.E + math.sqrt(math.max(0, w.r * w.r - off * off))
			table.insert(rays, { origin = anchor + fwd * off, dir = -up * reach, wheel = i, off = off })
		end
	end
	return rays
end

-- Gear logic (GTA style): brake while rolling forward, reverse from a standstill (after the brake
-- has been held REVERSE_DELAY s there, so a hard stop never creeps backwards by itself).
-- Returns driveCmd (-1..1), brakeCmd (0..1).
local function pedals(st: any, input: any, vF: number, h: number): (number, number)
	local thr = clamp(input.throttle or 0, 0, 1)
	local brk = clamp(input.brake or 0, 0, 1)
	local drive, braking = 0, 0
	if thr > 0.02 and brk > 0.02 then
		braking = brk
		st.reverseLatch = false
		st.stopHold = 0
	elseif thr > 0.02 then
		st.reverseLatch = false
		st.stopHold = 0
		if vF < -1.5 then
			braking = thr -- rolling backward: gas brakes first
		else
			drive = thr
		end
	elseif brk > 0.02 then
		if st.reverseLatch then
			drive = -brk
		elseif vF > 1.2 or vF < -1.5 then
			braking = brk -- rolling (either way, e.g. bounced off a wall): the pedal stops the car first
			st.stopHold = 0
		else
			st.stopHold = (st.stopHold or 0) + h
			if st.stopHold >= Ctl.REVERSE_DELAY then
				st.reverseLatch = true
				drive = -brk
			else
				braking = brk
			end
		end
	else
		if vF > -1.5 then
			st.reverseLatch = false -- coasting backward keeps the reverse gear for the next press
		end
		st.stopHold = 0
	end
	return drive, braking
end

-- One controller update. kin = { cf, vel, angVel, mass, com }; hits[i] = raycast result for
-- rays[i] ({ position, normal, distance, material }) or false. input = { throttle, brake, steer,
-- handbrake, park? }. park = true is the server's "stop and stay" for a driverless car (static hold,
-- never reverse). Returns world force, world torque (to apply for the next dt).
function Ctl.solve(st: any, dt: number, input: any, kin: any, rays: { any }, hits: { any }): (Vector3, Vector3)
	local h = clamp(dt, Ctl.MIN_DT, Ctl.MAX_DT)
	local spec = st.spec
	local g = Ctl.GRAVITY
	local cf: CFrame = kin.cf
	local up = cf.UpVector
	local fwd = cf.LookVector
	local right = cf.RightVector
	local vel: Vector3 = kin.vel
	local w: Vector3 = kin.angVel
	local M = math.max(1, kin.mass)
	local com: Vector3 = kin.com
	local nW = #st.wheels
	local mi = M / nW
	local vF = vel:Dot(fwd)
	st.speed = vF

	-- steering (speed sensitive, rate limited)
	local vTop = VS.studs(spec.topKmh)
	local sp = math.abs(vF)
	local maxDeg = spec.steerLow + (spec.steerHigh - spec.steerLow) * clamp(sp / (vTop * 0.75), 0, 1)
	local target = clamp(input.steer or 0, -1, 1) * math.rad(maxDeg)
	local rate = if math.abs(target) < math.abs(st.steer) then 5 else 3
	st.steer += clamp(target - st.steer, -rate * h, rate * h)

	local driveCmd, brakeCmd = pedals(st, input, vF, h)
	local handbrake = input.handbrake == true
	-- parking hold = static friction: engaged when the pedals are free and the car is (nearly) still,
	-- kept until a pedal is pressed or something shoves the car hard; also while the brake is held at a
	-- standstill, and always with input.park (the server settling a driverless car: never reverse).
	local anyPedal = (input.throttle or 0) > 0.02 or (input.brake or 0) > 0.02
	if input.park == true then
		driveCmd, brakeCmd = 0, 0
		st.holding = true
	elseif anyPedal then
		st.holding = false
	elseif not st.holding and sp < Ctl.HOLD_ENGAGE then
		st.holding = true
	elseif st.holding and sp > Ctl.HOLD_RELEASE then
		st.holding = false
	end
	local hold = st.holding or (brakeCmd > 0.02 and driveCmd == 0 and sp < Ctl.HOLD_ENGAGE)
	st.gear = if driveCmd < 0 then "R" elseif driveCmd > 0 then "D" elseif hold then "P" else "N"
	st.braking = brakeCmd > 0.02 or input.handbrake == true

	-- 1) suspension: per wheel, pick the ray that pushes the wheel highest
	local E, U = spec.E, spec.U
	local k = mi * g / E
	local omega = math.sqrt(k / mi)
	local c = 2 * (spec.z or 0.55) * mi * omega
	local gUp = g * math.max(0, up.Y)
	local total = ZERO
	local torque = ZERO
	local grounded = 0
	local nRays = #Ctl.RAY_OFFSETS
	local x = table.create(nW, 0)
	for i, wh in st.wheels do
		local best, bestHit = math.huge, nil
		for j = 1, nRays do
			local idx = (i - 1) * nRays + j
			local hit = hits[idx]
			if hit then
				local ray = rays[idx]
				local off = ray.off
				-- equivalent centre-ray distance
				local dEff = hit.distance - math.sqrt(math.max(0, wh.r * wh.r - off * off)) + wh.r
				if dEff < best then
					best, bestHit = dEff, hit
				end
			end
		end
		if bestHit then
			local s = U - (best - wh.r) -- displacement from rest (+ up)
			wh.s = clamp(s, -E, U)
			wh.grounded = true
			wh.contact = bestHit.position
			wh.normal = bestHit.normal
			wh.material = bestHit.material
			x[i] = clamp(s + E, 0, U + E + 0.5)
			grounded += 1
		else
			wh.s = clamp(wh.s - 3 * h, -E, U) -- droop out when airborne
			wh.grounded = false
			wh.contact = nil
			x[i] = -1
		end
	end
	st.grounded = grounded

	-- coupled implicit suspension: all grounded corners at once through the body's mobility matrix
	-- A_ij = 1/M + (r_i x n) . I^-1 (r_j x n), springs K (+ anti-roll pairs), dampers c:
	--   (Id + h A (hK + cId)) u1 = u0 - h g_n + h A K x0 ;  F = K x0 - (hK + cId) u1
	-- (backward Euler over the frame: stable at any frame rate, also in the light roll / pitch modes)
	local loads = table.create(nW, 0)
	local gi = {}
	for i = 1, nW do
		if x[i] >= 0 then
			table.insert(gi, i)
		end
	end
	local n = #gi
	if n > 0 then
		local I = { st.Ipitch * M, st.Iyaw * M, st.Iroll * M } -- base axes x, y, z
		local rx, ry, rz = cf.RightVector, cf.UpVector, -cf.LookVector
		local function Iinv(v: Vector3): Vector3
			return rx * (v:Dot(rx) / I[1]) + ry * (v:Dot(ry) / I[2]) + rz * (v:Dot(rz) / I[3])
		end
		local arm = table.create(n)
		local u0 = table.create(n)
		for a, i in gi do
			local wh = st.wheels[i]
			local p = wh.contact or cf:PointToWorldSpace(V3(wh.x, wh.y - wh.r, wh.z))
			local r = p - com
			arm[a] = r:Cross(up)
			u0[a] = (vel + w:Cross(r)):Dot(up)
		end
		local A = table.create(n)
		for a = 1, n do
			local row = table.create(n)
			local ia = Iinv(arm[a])
			for b = 1, n do
				row[b] = 1 / M + arm[b]:Dot(ia)
			end
			A[a] = row
		end
		-- spring matrix with anti-roll pairs (same axle, opposite sides)
		local arK = k * 0.45
		local K = table.create(n)
		for a = 1, n do
			local row = table.create(n, 0)
			row[a] = k
			K[a] = row
		end
		for a = 1, n do
			for b = a + 1, n do
				local wa, wb = st.wheels[gi[a]], st.wheels[gi[b]]
				if wa.front == wb.front and wa.side ~= wb.side then
					K[a][a] += arK
					K[b][b] += arK
					K[a][b] -= arK
					K[b][a] -= arK
				end
			end
		end
		-- B = hK + cI ; lhs = I + h A B ; rhs = u0 - h g + h A K x0
		local Kx = table.create(n, 0)
		for a = 1, n do
			local sum = 0
			for b = 1, n do
				sum += K[a][b] * x[gi[b]]
			end
			Kx[a] = sum
		end
		local lhs = table.create(n)
		local rhs = table.create(n, 0)
		for a = 1, n do
			local row = table.create(n + 1, 0)
			for b = 1, n do
				local sum = 0
				for q = 1, n do
					local Bqb = h * K[q][b] + (if q == b then c else 0)
					sum += A[a][q] * Bqb
				end
				row[b] = (if a == b then 1 else 0) + h * sum
			end
			local akx = 0
			for q = 1, n do
				akx += A[a][q] * Kx[q]
			end
			rhs[a] = u0[a] - h * gUp + h * akx
			lhs[a] = row
		end
		-- Gaussian elimination with partial pivoting
		for col = 1, n do
			local piv, best = col, math.abs(lhs[col][col])
			for r = col + 1, n do
				if math.abs(lhs[r][col]) > best then
					piv, best = r, math.abs(lhs[r][col])
				end
			end
			if best < 1e-12 then
				continue
			end
			lhs[col], lhs[piv] = lhs[piv], lhs[col]
			rhs[col], rhs[piv] = rhs[piv], rhs[col]
			for r = col + 1, n do
				local f = lhs[r][col] / lhs[col][col]
				if f ~= 0 then
					for q = col, n do
						lhs[r][q] -= f * lhs[col][q]
					end
					rhs[r] -= f * rhs[col]
				end
			end
		end
		local u1 = table.create(n, 0)
		for r = n, 1, -1 do
			local sum = rhs[r]
			for q = r + 1, n do
				sum -= lhs[r][q] * u1[q]
			end
			local d = lhs[r][r]
			u1[r] = if math.abs(d) > 1e-12 then sum / d else 0
		end
		for a, i in gi do
			local Bu = 0
			for q = 1, n do
				Bu += (h * K[a][q] + (if a == q then c else 0)) * u1[q]
			end
			local F = Kx[a] - Bu
			if F ~= F then
				F = 0
			end
			loads[i] = clamp(F, 0, 7 * mi * g)
		end
	end
	for i, wh in st.wheels do
		wh.load = loads[i]
	end

	-- slope assist (see Ctl.SLOPE_ASSIST): cancel most of gravity's along-road component while the car
	-- stands on the road (average contact normal; nothing on walls / when airborne)
	local assist = 0
	local nAvg: Vector3 = up
	do
		local nSum = ZERO
		for i, wh in st.wheels do
			if x[i] >= 0 and wh.normal then
				nSum += wh.normal :: Vector3
			end
		end
		if nSum.Magnitude > 1e-3 then
			nAvg = nSum.Unit
		end
	end
	local gAlong = Vector3.new(0, -g, 0) - nAvg * (-g * nAvg.Y) -- gravity along the road plane
	if grounded >= 2 and nAvg.Y > 0.5 then
		assist = Ctl.SLOPE_ASSIST
		total += -gAlong * (M * assist)
	end
	-- parking hold (static friction): a dead-beat cancel of the along-road velocity plus the pull the
	-- assist left over, both through the centre of mass (a contact-point brake would rock the body in
	-- pitch and walk the car), capped by the static friction of every grounded tyre
	if hold and grounded >= 1 then
		local vT = vel - nAvg * vel:Dot(nAvg)
		local want = -vT * (M * 0.85 / h) - gAlong * (M * (1 - assist))
		local sumN = 0
		for i = 1, nW do
			sumN += loads[i]
		end
		local cap = Ctl.HOLD_GRIP * sumN
		if cap > 0 and want.Magnitude > cap then
			want = want.Unit * cap
		elseif cap <= 0 then
			want = ZERO
		end
		total += want
	end

	-- 2) tyre forces: per axle lateral solve (2x2: lateral + yaw), longitudinal per wheel
	local vTopRev = VS.studs(spec.reverseKmh)
	local steerRight = right * math.cos(st.steer) + fwd * math.sin(-st.steer)
	local steerFwd = fwd * math.cos(st.steer) + right * math.sin(st.steer)
	-- axle geometry (longitudinal offset of each axle from the COM along fwd)
	local axF, axR = { z = 0, n = 0, v = 0 }, { z = 0, n = 0, v = 0 }
	for i, wh in st.wheels do
		if x[i] >= 0 and wh.contact then
			local ax = if wh.front then axF else axR
			local p = wh.contact :: Vector3
			local rel = p - com
			local vc = vel + w:Cross(rel)
			local lat = if wh.steer then steerRight else right
			ax.z += rel:Dot(fwd)
			ax.v += vc:Dot(lat)
			ax.n += 1
		end
	end
	local Ff, Fr = 0, 0
	do
		local Iyaw = st.Iyaw * M
		local hasF, hasR = axF.n > 0, axR.n > 0
		local zf = if hasF then axF.z / axF.n else 0
		local zr = if hasR then axR.z / axR.n else 0
		local vf = if hasF then axF.v / axF.n else 0
		local vr = if hasR then axR.v / axR.n else 0
		local gain = Ctl.LAT_GAIN
		-- dv_f = (Ff + Fr) h / M + (Ff zf + Fr zr) zf h / I   (same for r) ; want dv = -gain v
		if hasF and hasR then
			local a11 = h / M + zf * zf * h / Iyaw
			local a12 = h / M + zr * zf * h / Iyaw
			local a21 = h / M + zf * zr * h / Iyaw
			local a22 = h / M + zr * zr * h / Iyaw
			local det = a11 * a22 - a12 * a21
			if math.abs(det) > 1e-9 then
				local bf, br = -gain * vf, -gain * vr
				Ff = (bf * a22 - a12 * br) / det
				Fr = (a11 * br - a21 * bf) / det
			end
		elseif hasF then
			Ff = -gain * vf / (h / M + zf * zf * h / Iyaw)
		elseif hasR then
			Fr = -gain * vr / (h / M + zr * zr * h / Iyaw)
		end
	end

	-- engine / brakes (totals). spec.accel is the NET acceleration curve: the engine also covers the
	-- drag + rolling losses below, so the car really reaches topKmh (net accel -> 0 at vTop).
	local cd = M * spec.accel * Ctl.DRAG / (vTop * vTop)
	local losses = cd * vF * vF + M * Ctl.ROLLING * sp
	local driveForce = 0
	-- engine condition (owned cars, VS.enginePower via stepRoblox): torque share + top-speed share
	local power = st.enginePower or 1
	local vCap = vTop * (st.engineTop or 1)
	if driveCmd > 0 then
		local r = clamp(math.max(0, vF) / math.max(vCap, 1), 0, 1.2)
		driveForce = driveCmd * power * (M * spec.accel * math.max(0, 1 - r * r * r) + (if vF > 0 and vF < vCap then losses else 0))
		if vF > vCap then
			driveForce = 0
		end
	elseif driveCmd < 0 then
		local r = clamp(math.max(0, -vF) / vTopRev, 0, 1.2)
		driveForce = driveCmd * power * (M * spec.accel * 0.6 * math.max(0, 1 - r * r) + (if vF < 0 then losses else 0))
	end
	local brakeTotal = brakeCmd * M * spec.brake
	-- engine braking: pedals free, rolling -> a steady deceleration on every grounded wheel (no brake lights)
	local coastBrake = 0
	if driveCmd == 0 and brakeCmd == 0 and not hold and not handbrake and sp > 0.5 then
		coastBrake = M * spec.accel * Ctl.ENGINE_BRAKE
	end

	local groundedDrive = 0
	for i, wh in st.wheels do
		if x[i] >= 0 and wh.drive then
			groundedDrive += 1
		end
	end
	local rollH = spec.roll or 0.55
	for i, wh in st.wheels do
		if x[i] < 0 or not wh.contact then
			if wh.drive and driveCmd ~= 0 then
				wh.spin += driveCmd * 12 * h -- spin up in the air
			end
			continue
		end
		local N = loads[i]
		local p = wh.contact :: Vector3
		local rel = p - com
		local vc = vel + w:Cross(rel)
		local wf = if wh.steer then steerFwd else fwd
		local wr = if wh.steer then steerRight else right
		-- project on the ground plane
		local n = wh.normal or up
		wf = (wf - n * wf:Dot(n))
		if wf.Magnitude > 1e-3 then
			wf = wf.Unit
		else
			wf = fwd
		end
		wr = (wr - n * wr:Dot(n))
		if wr.Magnitude > 1e-3 then
			wr = wr.Unit
		else
			wr = right
		end
		local vLong = vc:Dot(wf)
		wh.spin += vLong / wh.r * h

		-- lateral (axle force split by load share)
		local axleF = if wh.front then Ff else Fr
		local axleLoad = 0
		for j, o in st.wheels do
			if o.front == wh.front and x[j] >= 0 then
				axleLoad += loads[j]
			end
		end
		local share = if axleLoad > 1e-6 then N / axleLoad else 0.5
		local fLat = axleF * share
		local mu = if wh.front then spec.gripF else spec.gripR
		local rearHb = handbrake and not wh.front
		if rearHb then
			mu = spec.hbGrip
		end

		-- longitudinal
		local fLong = 0
		if wh.drive and groundedDrive > 0 then
			fLong += driveForce / groundedDrive
		end
		local nGround = math.max(1, grounded)
		local bShare = if wh.front then 0.6 else 0.4
		local b = (brakeTotal * bShare * 2 + coastBrake) / nGround
		if rearHb then
			b = math.max(b, spec.hbGrip * N * 1.2)
		end
		if hold then
			-- the hold acts through the centre of mass (above); the wheel only rolls with resistance
		elseif b > 0 then
			-- never reverse the wheel's motion within one frame
			local stop = math.abs(vLong) * mi / h
			fLong += -math.sign(vLong) * math.min(b, stop)
		end
		fLong += -vLong * mi * Ctl.ROLLING -- rolling resistance

		-- friction ellipse: lateral grip mu (spec), longitudinal Ctl.LONG_GRIP (traction / braking),
		-- static Ctl.HOLD_GRIP while parked (holds on ~40 deg slopes), a sliding rear with the handbrake
		local latLim = mu * N
		local longLim = (if rearHb then spec.hbGrip * 1.5 else Ctl.LONG_GRIP) * N
		if hold then
			latLim = Ctl.HOLD_GRIP * N
			longLim = Ctl.HOLD_GRIP * N
		end
		local e = 0
		if latLim > 1e-6 then
			e += (fLat / latLim) ^ 2
		end
		if longLim > 1e-6 then
			e += (fLong / longLim) ^ 2
		end
		if e > 1 then
			local sc = 1 / math.sqrt(e)
			fLat *= sc
			fLong *= sc
		end

		local F = up * N + wr * fLat + wf * fLong
		-- apply the tyre forces between the contact patch and the COM height (roll centre); the
		-- longitudinal force acts from the car's centre plane (no yaw from an off-centre brake / drive
		-- split: the car brakes straight even with the driver's mass on one side), the lateral force at
		-- its true contact; the sideways slope hold goes through the centre of mass (no torque)
		local hUp = (com - p):Dot(up)
		local pApply = p + up * (hUp * rollH)
		local pLong = pApply - right * ((pApply - com):Dot(right))
		total += F
		torque += (pApply - com):Cross(wr * fLat) + (pLong - com):Cross(wf * fLong)
		torque += (p - com):Cross(up * N)
	end

	-- 3) body forces: aero drag + downforce, yaw / air damping
	local v2 = vel.Magnitude
	if v2 > 0.1 then
		total += -vel * (v2 * cd)
		total += -up * (M * 0.0015 * vF * vF)
	end
	if grounded == 0 then
		torque += -w * (M * 1.6 * (st.Iroll + st.Iyaw) * 0.25)
	else
		torque += -up * (w:Dot(up) * M * st.Iyaw * 0.35)
	end

	-- NaN / blow-up guards
	if total ~= total or torque ~= torque or total.Magnitude > M * g * 12 then
		total, torque = ZERO, ZERO
	end
	st.lastForce, st.lastTorque = total, torque
	return total, torque
end

-- Roblox wrapper: raycasts with `params` (RaycastParams excluding the car and characters, with
-- RespectCanCollide) and writes the VectorForce / Torque. Returns force, torque.
function Ctl.stepRoblox(st: any, dt: number, input: any, base: BasePart, vf: VectorForce, tq: Torque, params: RaycastParams): (Vector3, Vector3)
	-- owned-car condition (model attribute, re-read twice a second) -> engine power / top speed
	local clock = os.clock()
	if not st.condAt or clock - st.condAt > 0.5 then
		st.condAt = clock
		local model = base.Parent
		local c = model and model:GetAttribute(VS.Attr.Condition)
		st.cond = if type(c) == "number" then c else nil
		st.condSeed = st.condSeed or (base.Position.X % 7)
		-- 연료 (GwangalliGameplay.Fuel): an empty tank stops the engine like a dead one
		local f = model and model:GetAttribute("DriveFuel")
		st.fuel = if type(f) == "number" then f else nil
	end
	if st.cond ~= nil then
		st.enginePower, st.engineTop = VS.enginePower(st.cond, clock, st.condSeed)
	else
		st.enginePower, st.engineTop = nil, nil
	end
	if st.fuel ~= nil and st.fuel <= 0 then
		st.enginePower, st.engineTop = 0, 0
	end
	local cf = base.CFrame
	local rays = Ctl.buildRays(st, cf)
	local hits = table.create(#rays)
	for i, ray in rays do
		local res = workspace:Raycast(ray.origin, ray.dir, params)
		if res then
			hits[i] = { position = res.Position, normal = res.Normal, distance = res.Distance, material = res.Material }
		else
			hits[i] = false
		end
	end
	local kin = {
		cf = cf,
		vel = base.AssemblyLinearVelocity,
		angVel = base.AssemblyAngularVelocity,
		mass = base.AssemblyMass,
		com = base.AssemblyCenterOfMass,
	}
	local f, t = Ctl.solve(st, dt, input, kin, rays, hits)
	vf.Force = f
	tq.Torque = t
	return f, t
end

-- Local transform for wheel i's steer hub (suspension travel + steering) and spin joint.
function Ctl.wheelTransforms(st: any, i: number): (CFrame, CFrame)
	local wh = st.wheels[i]
	local hub = CFrame.new(0, wh.s, 0)
	if wh.steer then
		hub *= CFrame.Angles(0, -st.steer, 0)
	end
	return hub, CFrame.Angles(-wh.spin, 0, 0)
end

-- Upright test: true when the car lies on its side / roof.
function VS.isFlipped(cf: CFrame): boolean
	return cf.UpVector.Y < 0.35
end

return VS
