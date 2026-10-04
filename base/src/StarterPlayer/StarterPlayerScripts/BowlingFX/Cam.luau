--!strict
-- BowlingFX/Cam: the bowling camera director (Scriptable camera only while it directs).
--   aim(lf, len, char)              broadcast view from behind the bowler, tracks the approach
--   follow(ball, lf, len, onImpact) low chase cam behind the rolling ball; ~13 studs before the
--                                   pins it CUTS to the pin cam; onImpact(pos, speed) fires once
--                                   when the ball reaches the head pin (pin crash sound + shake)
--   pins(lf, len)                   pin-deck cam (side, slightly above), with the Fx shake
--   holdThen(seconds, fn)           keep the current shot, then call fn
--   release()                       back to the player's Custom camera
-- Coordinates are in the lane frame (x right, y up, z back from the foul line). One
-- BindToRenderStep binding exists only while a mode is active.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Cam = {}

local BIND = "BowlingCamDirector"
local Fx: any = nil
local mode: string? = nil
local bound = false
local lf = CFrame.identity
local len = 60.96
local char: Model? = nil
local ball: BasePart? = nil
local onImpact: ((Vector3, number) -> ())? = nil
local impactDone = false
local cutDone = false
local holdUntil: number? = nil
local holdFn: (() -> ())? = nil
local side = 1
local current: CFrame? = nil
local followSpeed = 0

function Cam.init(fx: any)
	Fx = fx
end

local function camera(): Camera?
	return workspace.CurrentCamera
end

local function lookAt(eye: Vector3, focus: Vector3): CFrame
	return CFrame.lookAt(eye, focus)
end

local function pinShot(): CFrame
	local eye = (lf * CFrame.new(side * 1.3, 2.35, -(len - 7.6))).Position
	local focus = (lf * CFrame.new(0, 0.55, -(len + 1.3))).Position
	return lookAt(eye, focus)
end

local function update(dt: number)
	local cam = camera()
	if not cam or not mode then
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local target: CFrame
	local alpha = 1 - math.exp(-dt * 6)
	if mode == "aim" then
		local cx, cz = -0.85, 11.5
		local c = char
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local rel = lf:PointToObjectSpace(hrp.Position)
			cx, cz = rel.X, math.clamp(rel.Z, 0, 18)
		end
		local eye = (lf * CFrame.new(cx * 0.55 + 0.45, 4.3, cz + 8.2)).Position
		local focus = (lf * CFrame.new(cx * 0.2 + 0.3, 0.4, -36)).Position
		target = lookAt(eye, focus)
	elseif mode == "follow" then
		local b = ball
		if not (b and b.Parent) then
			mode = "pins"
			target = pinShot()
			alpha = 1
		else
			local rel = lf:PointToObjectSpace(b.Position)
			local d = -rel.Z
			followSpeed = b.AssemblyLinearVelocity.Magnitude
			if not impactDone and d >= len - 0.9 then
				impactDone = true
				if onImpact then
					task.spawn(onImpact, b.Position, followSpeed)
				end
			end
			if not cutDone and d > len - 13 then
				cutDone = true
				side = if rel.X >= 0 then -1 else 1
				mode = "pins"
				target = pinShot()
				alpha = 1 -- a hard cut, like a TV pin cam
			else
				local x = math.clamp(rel.X, -2.5, 2.5)
				local eye = (lf * CFrame.new(x * 0.55, 1.75, rel.Z + 6.2)).Position
				local focus = (lf * CFrame.new(x * 0.7, 0.45, rel.Z - 12)).Position
				target = lookAt(eye, focus)
				alpha = 1 - math.exp(-dt * 9)
			end
		end
	else -- pins
		local b = ball
		if b and b.Parent and not impactDone then
			local rel = lf:PointToObjectSpace(b.Position)
			if -rel.Z >= len - 0.9 then
				impactDone = true
				if onImpact then
					task.spawn(onImpact, b.Position, b.AssemblyLinearVelocity.Magnitude)
				end
			end
		end
		target = pinShot()
	end
	local cur = current or cam.CFrame
	local nextCf = if alpha >= 1 then target else cur:Lerp(target, alpha)
	current = nextCf
	cam.CFrame = nextCf * (if Fx then Fx.shakeOffset() else CFrame.identity)
	if holdUntil and os.clock() >= holdUntil then
		local fn = holdFn
		holdUntil, holdFn = nil, nil
		if fn then
			task.spawn(fn)
		end
	end
end

local function bind()
	if bound then
		return
	end
	bound = true
	current = nil
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, update)
end

local function unbind()
	if not bound then
		return
	end
	bound = false
	pcall(function()
		RunService:UnbindFromRenderStep(BIND)
	end)
end

function Cam.aim(laneFrame: CFrame, laneLength: number, character: Model?)
	lf, len, char = laneFrame, laneLength, character
	mode = "aim"
	holdUntil, holdFn = nil, nil
	bind()
end

function Cam.follow(b: BasePart, laneFrame: CFrame, laneLength: number, impact: ((Vector3, number) -> ())?)
	lf, len, ball = laneFrame, laneLength, b
	onImpact = impact
	impactDone, cutDone = false, false
	mode = "follow"
	holdUntil, holdFn = nil, nil
	bind()
end

function Cam.pins(laneFrame: CFrame, laneLength: number)
	lf, len = laneFrame, laneLength
	mode = "pins"
	bind()
end

function Cam.holdThen(seconds: number, fn: () -> ())
	holdUntil = os.clock() + seconds
	holdFn = fn
end

function Cam.mode(): string?
	return mode
end

function Cam.release()
	mode = nil
	ball = nil
	onImpact = nil
	holdUntil, holdFn = nil, nil
	unbind()
	local cam = camera()
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		local c = Players.LocalPlayer.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
	end
end

return Cam
