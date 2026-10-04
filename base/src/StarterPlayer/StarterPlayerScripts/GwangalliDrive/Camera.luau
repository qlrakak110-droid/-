-- GwangalliDrive/Camera: driving cameras (Scriptable while seated, restored on exit).
--   chase     behind the car, heading smoothed toward the direction of travel (drift look), height /
--             distance from the car size, pulled in front of walls, FOV kick with speed
--   hood      on the hood at the windshield base, horizon kept level-ish
--   interior  first person from the seat: dashboard, steering wheel, cluster / nav screens and the
--             interior trim in view; the local avatar is hidden, the glass made clearer locally
-- Touch / right-mouse drag orbits the chase camera (or turns the head inside), easing back after
-- 1.2 s; the mouse wheel zooms the chase camera.
-- Feel: getting in blends the walking camera into the chase view over 0.7 s (no cut), and the
-- cabin / hood views sway with the car: lateral acceleration rolls and shifts the head, braking and
-- throttle pitch it a little, both smoothed (seat camera sway); the chase view rolls a touch too.
-- Camera.onMode(fn) tells Drive about mode changes (interior -> radio clear / muffled).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Camera = {}

local player = Players.LocalPlayer
local S: any = {
	active = false,
	mode = "chase",
	driverModes = { "chase", "hood", "interior" },
	passengerModes = { "chase", "interior" },
	heading = nil :: Vector3?,
	yawOff = 0,
	pitchOff = 0,
	zoom = 0,
	lastDrag = 0,
	fov = 70,
	saved = nil :: any,
	hidden = {} :: { [Instance]: number },
	glass = {} :: { [BasePart]: number },
	camPos = nil :: Vector3?,
	blendFrom = nil :: CFrame?,
	blendT0 = 0,
	lastVel = nil :: Vector3?,
	accLat = 0, -- smoothed lateral acceleration (studs/s^2, + right)
	accLong = 0, -- smoothed forward acceleration
	onMode = nil :: ((string) -> ())?,
}
Camera.state = S

function Camera.onMode(fn: (string) -> ())
	S.onMode = fn
end

local function modeChanged()
	if S.onMode then
		task.spawn(S.onMode, S.mode)
	end
end

local GLASS = { "windshield", "sideglass", "rearglass", "cabglass", "glass", "window" }
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.IgnoreWater = true

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return f.Unit
end

local function v3(t: any, default: Vector3): Vector3
	if type(t) == "table" and #t >= 3 then
		return Vector3.new(t[1], t[2], t[3])
	end
	return default
end

local function setCharHidden(on: boolean)
	if on then
		local ch = player.Character
		if not ch then
			return
		end
		for _, d in ch:GetDescendants() do
			if (d:IsA("BasePart") or d:IsA("Decal")) and S.hidden[d] == nil then
				S.hidden[d] = (d :: any).LocalTransparencyModifier
				;(d :: any).LocalTransparencyModifier = 1
			end
		end
	else
		for d, old in S.hidden do
			if d.Parent then
				(d :: any).LocalTransparencyModifier = old
			end
		end
		S.hidden = {}
	end
end

local function setGlassClear(on: boolean)
	if on and S.car then
		for _, d in S.car:GetDescendants() do
			if d:IsA("BasePart") and S.glass[d] == nil and d.Transparency > 0.05 and d.Transparency < 0.95 then
				local lower = string.lower(d.Name)
				for _, g in GLASS do
					if string.find(lower, g, 1, true) then
						S.glass[d] = d.LocalTransparencyModifier
						d.LocalTransparencyModifier = 0.6
						break
					end
				end
			end
		end
	elseif not on then
		for d, old in S.glass do
			if d.Parent then
				d.LocalTransparencyModifier = old
			end
		end
		S.glass = {}
	end
end

local function applyModeSideEffects()
	local inside = S.mode == "interior"
	setCharHidden(inside)
	setGlassClear(inside)
end

function Camera.modes(): { string }
	return if S.role == "driver" then S.driverModes else S.passengerModes
end

function Camera.label(): string
	return if S.mode == "chase" then "3인칭" elseif S.mode == "hood" then "보닛" else "운전석"
end

function Camera.begin(car: Model, base: BasePart, rig: any, role: string, seat: BasePart?)
	local cam = workspace.CurrentCamera
	if not S.active then
		S.saved = { type = cam.CameraType, subject = cam.CameraSubject, fov = cam.FieldOfView }
	end
	S.active = true
	S.car, S.base, S.rig, S.role, S.seat = car, base, rig, role, seat
	local modes = Camera.modes()
	if not table.find(modes, S.mode) then
		S.mode = "chase"
	end
	S.heading = flat(base.CFrame.LookVector)
	S.yawOff, S.pitchOff, S.zoom = 0, 0, 0
	S.fov = cam.FieldOfView
	S.camPos = nil
	S.lastVel, S.accLat, S.accLong = nil, 0, 0
	-- blend from where the walking camera was (getting into the car is not a cut)
	S.blendFrom = cam.CFrame
	S.blendT0 = os.clock()
	cam.CameraType = Enum.CameraType.Scriptable
	applyModeSideEffects()
	modeChanged()
end

function Camera.cycle(): string
	local modes = Camera.modes()
	local i = table.find(modes, S.mode) or 0
	S.mode = modes[i % #modes + 1]
	S.yawOff, S.pitchOff = 0, 0
	S.camPos = nil
	applyModeSideEffects()
	modeChanged()
	return S.mode
end

function Camera.set(mode: string)
	if table.find(Camera.modes(), mode) then
		S.mode = mode
		S.camPos = nil
		applyModeSideEffects()
		modeChanged()
	end
end

function Camera.finish()
	if not S.active then
		return
	end
	S.active = false
	setCharHidden(false)
	setGlassClear(false)
	local cam = workspace.CurrentCamera
	local saved = S.saved or {}
	cam.CameraType = if saved.type == Enum.CameraType.Scriptable or saved.type == nil then Enum.CameraType.Custom else saved.type
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	cam.CameraSubject = hum or saved.subject
	cam.FieldOfView = saved.fov or 70
	S.car, S.base, S.rig, S.seat = nil, nil, nil, nil
end

-- Orbit / head-look input -----------------------------------------------------------------------------
local drag: InputObject? = nil
local lastPos: Vector3? = nil
UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
	if not S.active or gp then
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton2 then
		drag = input
		lastPos = input.Position
	end
end)
UserInputService.InputChanged:Connect(function(input: InputObject, gp: boolean)
	if not S.active then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseWheel and not gp then
		S.zoom = math.clamp(S.zoom - input.Position.Z * 2, -6, 14)
		return
	end
	local d = drag
	if not d then
		return
	end
	local same = input == d or (d.UserInputType == Enum.UserInputType.MouseButton2 and input.UserInputType == Enum.UserInputType.MouseMovement)
	if same and lastPos then
		local delta = input.Position - lastPos
		lastPos = input.Position
		S.yawOff = math.clamp(S.yawOff - delta.X * 0.008, -math.pi, math.pi)
		S.pitchOff = math.clamp(S.pitchOff - delta.Y * 0.005, -0.5, 0.6)
		S.lastDrag = os.clock()
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if drag and (input == drag or (drag.UserInputType == Enum.UserInputType.MouseButton2 and input.UserInputType == Enum.UserInputType.MouseButton2)) then
		drag = nil
		lastPos = nil
		S.lastDrag = os.clock()
	end
end)

-- Per frame ---------------------------------------------------------------------------------------------
-- info = { speed (studs/s, signed forward), top (studs/s), steer (-1..1), vel (Vector3, optional) }
function Camera.update(dt: number, info: { [string]: any })
	if not S.active or not S.base or not S.base.Parent then
		return
	end
	local cam = workspace.CurrentCamera
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local base: BasePart = S.base
	local rig = S.rig or {}
	local cf = base.CFrame
	local speed = math.abs(info.speed or 0)
	local s01 = math.clamp(speed / math.max(1, info.top or 100), 0, 1.2)
	-- body-referenced acceleration (smoothed): the seat sway below
	do
		local vel: Vector3 = info.vel or base.AssemblyLinearVelocity
		local last = S.lastVel
		if last and dt > 1e-4 then
			local a = (vel - last) / dt
			local k = 1 - math.exp(-dt * 6)
			S.accLat += (math.clamp(a:Dot(cf.RightVector), -60, 60) - S.accLat) * k
			S.accLong += (math.clamp(a:Dot(cf.LookVector), -60, 60) - S.accLong) * k
		end
		S.lastVel = vel
	end
	local swayRoll = -S.accLat * 0.0016 -- rad: lean out of the corner like a passenger
	local swayPitch = -S.accLong * 0.0012 -- nose dips on braking, lifts on throttle
	-- ease the orbit back behind the car
	if os.clock() - S.lastDrag > 1.2 and drag == nil then
		local k = 1 - math.exp(-dt * 3)
		S.yawOff -= S.yawOff * k
		S.pitchOff -= S.pitchOff * k
	end
	local fovTarget = 70
	if S.mode == "chase" then
		local fwd = flat(cf.LookVector)
		local target = fwd
		local vel = base.AssemblyLinearVelocity
		local vf = Vector3.new(vel.X, 0, vel.Z)
		if vf.Magnitude > 10 then
			if vf.Unit:Dot(fwd) > 0 then
				target = (fwd * 0.65 + vf.Unit * 0.35).Unit
			end
		end
		local h = S.heading or fwd
		local k = 1 - math.exp(-dt * (3.2 + s01 * 3))
		h = (h + (target - h) * k)
		if h.Magnitude < 1e-3 then
			h = fwd
		end
		h = h.Unit
		S.heading = h
		local rot = CFrame.Angles(0, S.yawOff, 0)
		local dir = rot:VectorToWorldSpace(h)
		local L = rig.L or 16
		local H = rig.H or 5
		local dist = L * 0.85 + 8 + s01 * 4 + S.zoom
		local height = H * 0.6 + 2.6 + S.pitchOff * dist * 0.8
		local focus = cf.Position + Vector3.new(0, H * 0.45, 0)
		local want = focus - dir * dist + Vector3.new(0, height, 0)
		-- walls between the car and the camera pull it in
		local ex = { S.car }
		if player.Character then
			table.insert(ex, player.Character)
		end
		rayParams.FilterDescendantsInstances = ex
		local off = want - focus
		local hit = workspace:Raycast(focus, off, rayParams)
		if hit then
			want = hit.Position - off.Unit * 0.8
		end
		local cur = S.camPos
		if cur == nil or (cur - want).Magnitude > 60 then
			cur = want
		else
			cur = cur:Lerp(want, 1 - math.exp(-dt * 12))
		end
		S.camPos = cur
		cam.CFrame = CFrame.lookAt(cur, focus + dir * 5 + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, swayRoll * 0.35)
		fovTarget = 70 + 16 * s01 ^ 1.5
	elseif S.mode == "hood" then
		local hood = v3(rig.hood, Vector3.new(0, 4, -3))
		local p = cf:PointToWorldSpace(hood)
		local up = Vector3.yAxis:Lerp(cf.UpVector, 0.5).Unit
		local look = (cf * CFrame.Angles(math.rad(-3) + S.pitchOff * 0.5 + swayPitch * 0.5, S.yawOff * 0.5, 0)).LookVector
		cam.CFrame = CFrame.lookAt(p, p + look * 20, up) * CFrame.Angles(0, 0, swayRoll * 0.5)
		fovTarget = 74 + 14 * s01 ^ 1.5
	else
		local eye = v3(rig.eye, Vector3.new(-1.2, 3.2, 0.5))
		if S.role ~= "driver" and S.seat then
			local l = cf:PointToObjectSpace(S.seat.Position)
			eye = Vector3.new(l.X, eye.Y, l.Z + 0.15)
		end
		-- the head sways: shifts against the lateral g (up to ~0.18 studs), sinks a little under braking
		local shift = Vector3.new(math.clamp(-S.accLat * 0.004, -0.18, 0.18), math.clamp(S.accLong * 0.0015, -0.08, 0.05), 0)
		local p = cf:PointToWorldSpace(eye + shift)
		local headYaw = -(info.steer or 0) * math.rad(7) + S.yawOff
		local rot = cf * CFrame.Angles(0, headYaw, 0) * CFrame.Angles(math.rad(-9) + S.pitchOff + swayPitch, 0, swayRoll)
		cam.CFrame = CFrame.lookAt(p, p + rot.LookVector * 10, rot.UpVector)
		fovTarget = 72 + 8 * s01
	end
	-- getting in: ease from the walking camera into the first driving frame
	if S.blendFrom then
		local a = (os.clock() - S.blendT0) / 0.7
		if a >= 1 then
			S.blendFrom = nil
		else
			local e = 1 - (1 - a) * (1 - a) * (1 - a)
			cam.CFrame = (S.blendFrom :: CFrame):Lerp(cam.CFrame, e)
		end
	end
	S.fov += (fovTarget - S.fov) * (1 - math.exp(-dt * 4))
	cam.FieldOfView = S.fov
	-- the avatar can change while seated (accessories stream in): keep it hidden inside
	if S.mode == "interior" and player.Character and next(S.hidden) == nil then
		setCharHidden(true)
	end
end

return Camera
