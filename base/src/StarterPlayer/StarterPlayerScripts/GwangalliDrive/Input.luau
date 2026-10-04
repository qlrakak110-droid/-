-- GwangalliDrive/Input: one driving input state from every source.
--   PC keyboard  W/↑ gas, S/↓ brake·reverse, A/D ←/→ steer, Space handbrake, H horn, V/C camera,
--                L lights, F exit, R flip back, Q / E indicators, X hazard, T radio
--   gamepad      left stick steer, R2 gas, L2 brake, X (Square) handbrake, Y exit, B horn,
--                D-pad up camera / down lights
--   touch        set by the drive UI (Input.touch.* fields)
-- Keys are bound through ContextActionService only while driving (high priority, sunk), so the
-- HUD's own keys and the character controls never see them.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Input = {}

Input.touch = { throttle = 0, brake = 0, steer = 0, handbrake = false, horn = false }
local keys = { up = false, down = false, left = false, right = false, space = false, horn = false }
local pad = { throttle = 0, brake = 0, steer = 0, handbrake = false, horn = false }
local actions: { [string]: () -> () } = {}
local bound = false

local ACTION = "GwangalliDriveKeys"
local PRIORITY = Enum.ContextActionPriority.High.Value + 50

-- fn names: camera, lights, exit, flip, left, right, hazard, radio
function Input.on(name: string, fn: () -> ())
	actions[name] = fn
end

local function fire(name: string)
	local f = actions[name]
	if f then
		task.spawn(f)
	end
end

local KEYMAP: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.W] = "up",
	[Enum.KeyCode.Up] = "up",
	[Enum.KeyCode.S] = "down",
	[Enum.KeyCode.Down] = "down",
	[Enum.KeyCode.A] = "left",
	[Enum.KeyCode.Left] = "left",
	[Enum.KeyCode.D] = "right",
	[Enum.KeyCode.Right] = "right",
	[Enum.KeyCode.Space] = "space",
	[Enum.KeyCode.H] = "horn",
}
local TAPS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.V] = "camera",
	[Enum.KeyCode.C] = "camera",
	[Enum.KeyCode.L] = "lights",
	[Enum.KeyCode.F] = "exit",
	[Enum.KeyCode.R] = "flip",
	[Enum.KeyCode.Q] = "left",
	[Enum.KeyCode.E] = "right",
	[Enum.KeyCode.X] = "hazard",
	[Enum.KeyCode.T] = "radio",
	[Enum.KeyCode.ButtonY] = "exit",
	[Enum.KeyCode.DPadUp] = "camera",
	[Enum.KeyCode.DPadDown] = "lights",
}

local function handle(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local kc = input.KeyCode
	local down = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
	if state == Enum.UserInputState.Cancel then
		down = false
	end
	local k = KEYMAP[kc]
	if k then
		keys[k] = down
		return Enum.ContextActionResult.Sink
	end
	if kc == Enum.KeyCode.ButtonR2 then
		pad.throttle = if down then math.max(0.2, input.Position.Z) else 0
	elseif kc == Enum.KeyCode.ButtonL2 then
		pad.brake = if down then math.max(0.2, input.Position.Z) else 0
	elseif kc == Enum.KeyCode.Thumbstick1 then
		local x = input.Position.X
		pad.steer = if math.abs(x) > 0.15 then x else 0
	elseif kc == Enum.KeyCode.ButtonX then
		pad.handbrake = down
	elseif kc == Enum.KeyCode.ButtonB then
		pad.horn = down
	elseif TAPS[kc] then
		if state == Enum.UserInputState.Begin then
			fire(TAPS[kc])
		end
	else
		return Enum.ContextActionResult.Pass
	end
	return Enum.ContextActionResult.Sink
end

function Input.bind()
	if bound then
		return
	end
	bound = true
	local codes = {}
	for kc in KEYMAP do
		table.insert(codes, kc)
	end
	for kc in TAPS do
		table.insert(codes, kc)
	end
	for _, kc in { Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2, Enum.KeyCode.Thumbstick1, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonB } do
		table.insert(codes, kc)
	end
	ContextActionService:BindActionAtPriority(ACTION, handle, false, PRIORITY, table.unpack(codes))
end

function Input.unbind()
	if not bound then
		return
	end
	bound = false
	pcall(function()
		ContextActionService:UnbindAction(ACTION)
	end)
	Input.reset()
end

function Input.reset()
	for k in keys do
		keys[k] = false
	end
	pad.throttle, pad.brake, pad.steer, pad.handbrake, pad.horn = 0, 0, 0, false, false
	local t = Input.touch
	t.throttle, t.brake, t.steer, t.handbrake, t.horn = 0, 0, 0, false, false
end

-- Combined state: { throttle, brake, steer, handbrake, horn }
function Input.read(): { [string]: any }
	local t = Input.touch
	local steerKeys = (if keys.right then 1 else 0) - (if keys.left then 1 else 0)
	local steer = steerKeys
	if steer == 0 then
		steer = if math.abs(pad.steer) > math.abs(t.steer) then pad.steer else t.steer
	end
	return {
		throttle = math.max(if keys.up then 1 else 0, pad.throttle, t.throttle),
		brake = math.max(if keys.down then 1 else 0, pad.brake, t.brake),
		steer = math.clamp(steer, -1, 1),
		handbrake = keys.space or pad.handbrake or t.handbrake,
		horn = keys.horn or pad.horn or t.horn,
	}
end

function Input.keyboard(): boolean
	return UserInputService.KeyboardEnabled
end

return Input
