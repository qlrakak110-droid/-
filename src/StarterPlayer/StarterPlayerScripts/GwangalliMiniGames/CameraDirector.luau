--!strict
-- GwangalliMiniGames/CameraDirector: the minigame camera (client only).
--   focus(station, hint)  eases the camera from wherever it is to the station's camera hint part
--                         (CamA / CamB = over your own shoulder onto the table, CamSpec = the
--                         spectators' view from the walk) and holds it there (Scriptable) - the bay,
--                         the bridge and the people around stay in the shot
--   release()             eases back to the player's normal camera
--   lockControls(on)      movement off while you sit at a table / stand at a machine (the server also
--                         blocks jumping); restored on release
-- Players can still look around a little: dragging (touch / right mouse) orbits the hint view
-- by up to +-25 degrees, so the scene never feels frozen.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Cam = {}

local player = Players.LocalPlayer
local owning = false
local base: CFrame? = nil
local focusPos: Vector3? = nil
local yawOff, pitchOff = 0, 0
local conn: RBXScriptConnection? = nil
local dragConn: RBXScriptConnection? = nil
local controlsOff = false
local prevType: Enum.CameraType? = nil
local tween: Tween? = nil

local function controls(): any
	local ok, c = pcall(function()
		local ps = player:WaitForChild("PlayerScripts", 2)
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if not pm then
			return nil
		end
		return (require(pm :: ModuleScript) :: any):GetControls()
	end)
	return if ok then c else nil
end

function Cam.lockControls(on: boolean)
	if on == controlsOff then
		return
	end
	controlsOff = on
	local c = controls()
	if c then
		pcall(function()
			if on then
				c:Disable()
			else
				c:Enable()
			end
		end)
	end
end

function Cam.owning(): boolean
	return owning
end

local function apply()
	local cam = Workspace.CurrentCamera
	if not cam or not base or not focusPos then
		return
	end
	if tween and tween.PlaybackState == Enum.PlaybackState.Playing then
		return
	end
	local b = base :: CFrame
	local f = focusPos :: Vector3
	local offset = b.Position - f
	local rotated = CFrame.Angles(0, math.rad(yawOff), 0) * offset
	local right = rotated:Cross(Vector3.new(0, 1, 0))
	if right.Magnitude > 1e-3 then
		rotated = CFrame.fromAxisAngle(right.Unit, math.rad(pitchOff)) * rotated
	end
	cam.CFrame = CFrame.lookAt(f + rotated, f)
end

function Cam.focus(model: Model?, hintName: string)
	if not model then
		return
	end
	local hint = model:FindFirstChild(hintName)
	local focus = model:FindFirstChild("Focus")
	local cam = Workspace.CurrentCamera
	if not hint or not hint:IsA("BasePart") or not cam then
		return
	end
	if not owning then
		prevType = cam.CameraType
	end
	owning = true
	base = hint.CFrame
	focusPos = if focus and focus:IsA("BasePart") then focus.Position else hint.CFrame.Position + hint.CFrame.LookVector * 8
	yawOff, pitchOff = 0, 0
	cam.CameraType = Enum.CameraType.Scriptable
	if tween then
		tween:Cancel()
	end
	local t = TweenService:Create(cam, TweenInfo.new(1.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { CFrame = CFrame.lookAt(base.Position, focusPos :: Vector3) })
	tween = t
	t:Play()
	if not conn then
		conn = RunService.RenderStepped:Connect(function()
			if owning then
				apply()
			end
		end)
	end
	if not dragConn then
		dragConn = UserInputService.InputChanged:Connect(function(input, processed)
			if not owning or processed then
				return
			end
			local drag = input.UserInputType == Enum.UserInputType.Touch
				or (input.UserInputType == Enum.UserInputType.MouseMovement and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))
			if drag then
				yawOff = math.clamp(yawOff - input.Delta.X * 0.15, -25, 25)
				pitchOff = math.clamp(pitchOff - input.Delta.Y * 0.1, -12, 12)
			end
		end)
	end
end

function Cam.release()
	if not owning then
		return
	end
	owning = false
	base = nil
	focusPos = nil
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if dragConn then
		dragConn:Disconnect()
		dragConn = nil
	end
	if tween then
		tween:Cancel()
		tween = nil
	end
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = if prevType and prevType ~= Enum.CameraType.Scriptable then prevType else Enum.CameraType.Custom
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
	end
	Cam.lockControls(false)
end

return Cam
