-- GwangalliDrive/Drive: the local player's side of driving.
--   * seat detection (Humanoid.SeatPart on a rigged car's DriveSeat / DrivePassenger seats) and the
--     server's enter / exit events -> begin / finish
--   * while driving: character controls off (hides Roblox's thumbstick + jump button), car prompts
--     off, drive keys bound, the controller (GwangalliVehiclesShared.Controller) run every physics
--     frame on the car this client owns, wheel hubs animated from the controller state, lamp /
--     horn / indicator bits sent to the server when they change (<= 10 / s)
--   * cameras (Camera), HUD (UI), headlights on automatically at night, flip-back button
--   * feel: door sounds (built-in rbxasset clips) when getting in / out, the camera blends into the
--     chase view, the radio (Radio) rides along and is muffled unless the camera is inside
--   * "내 차" world marker after a call

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Drive = {}

local player = Players.LocalPlayer
local ctx: any = nil
local VS: any = nil
local remote: RemoteEvent? = nil

local cur: any = nil -- { car, base, rig, role, seat, ctl, vf, tq, motors, spec, params }
local lightsOn = false
local lightsManual = false
local indicator = 0 -- 0 none, VS.Bits.LEFT / RIGHT / HAZARD
local lastBits = -1
local lastSent = 0
local flippedFor = 0
local controlsOff = false
local promptsWere: boolean? = nil
local charRefreshAt = 0
local marker: BillboardGui? = nil
local sfx: { [string]: Sound } = {}

-- Built-in clips only (no uploads): the door swing + latch, the seat belt click.
local function sound(name: string, id: string, speed: number, volume: number): Sound
	local s = sfx[name]
	if s and s.Parent then
		return s
	end
	s = Instance.new("Sound")
	s.Name = "GwangalliDrive_" .. name
	s.SoundId = id
	s.PlaybackSpeed = speed
	s.Volume = volume
	s.Parent = game:GetService("SoundService")
	sfx[name] = s
	return s
end

local function doorSounds(open: boolean)
	pcall(function()
		local swing = sound("door", "rbxasset://sounds/swoosh.wav", if open then 0.55 else 0.7, 0.45)
		swing:Play()
		task.delay(if open then 0.42 else 0.25, function()
			local latch = sound("latch", "rbxasset://sounds/clickfast.wav", 0.6, 0.6)
			latch:Play()
		end)
	end)
end

function Drive.role(): string?
	return cur and cur.role
end
function Drive.car(): Model?
	return cur and cur.car
end
Drive.current = function()
	return cur
end

local function controls(): any
	local ps = player:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if not pm then
		return nil
	end
	local ok, res = pcall(function()
		return (require(pm) :: any):GetControls()
	end)
	return if ok then res else nil
end

local function setControls(enabled: boolean)
	local c = controls()
	if c then
		pcall(function()
			if enabled then
				c:Enable()
			else
				c:Disable()
			end
		end)
	end
	controlsOff = not enabled
end

local function setPrompts(enabled: boolean)
	pcall(function()
		if not enabled then
			if promptsWere == nil then
				promptsWere = ProximityPromptService.Enabled
			end
			ProximityPromptService.Enabled = false
		elseif promptsWere ~= nil then
			ProximityPromptService.Enabled = promptsWere
			promptsWere = nil
		end
	end)
end

local function refreshParams()
	if not cur or not cur.params then
		return
	end
	local ex = { cur.car }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ex, p.Character)
		end
	end
	cur.params.FilterDescendantsInstances = ex
end

local function isNight(): boolean
	return workspace:GetAttribute("GwangalliIsNight") == true
end

local function send(payload: any)
	if remote then
		remote:FireServer(payload)
	end
end

---------------------------------------------------------------------------------------------------
-- Begin / finish
---------------------------------------------------------------------------------------------------
local function begin(car: Model, role: string, seat: BasePart?)
	if cur and cur.car == car and cur.role == role then
		return
	end
	if cur then
		Drive.finish()
	end
	local rig = VS.decodeRig(car:GetAttribute(VS.Attr.Rig))
	local t0 = os.clock()
	while not rig and os.clock() - t0 < 3 and car.Parent do
		task.wait(0.1)
		rig = VS.decodeRig(car:GetAttribute(VS.Attr.Rig))
	end
	local base = car:FindFirstChild(VS.Parts.Base)
	if not rig or not (base and base:IsA("BasePart")) then
		warn("[GwangalliDrive] car without a drive rig: " .. car:GetFullName())
		return
	end
	local spec = VS.spec(rig.kind)
	local c: any = { car = car, base = base, rig = rig, role = role, seat = seat, spec = spec }
	if role == "driver" then
		c.vf = base:FindFirstChild(VS.Parts.Force)
		c.tq = base:FindFirstChild(VS.Parts.Torque)
		c.ctl = VS.Controller.new(rig, spec)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		params.IgnoreWater = true
		c.params = params
		c.motors = {}
		for i = 1, #rig.wheels do
			local m1 = base:FindFirstChild(VS.Parts.Wheel .. i)
			local hub = m1 and (m1 :: any).Part1
			local m2 = hub and hub:FindFirstChild("DriveSpin" .. i)
			c.motors[i] = { steer = m1, spin = m2 }
		end
	end
	cur = c
	refreshParams()
	setControls(false)
	setPrompts(false)
	ctx.Input.reset()
	ctx.Input.bind()
	lightsManual = false
	lightsOn = isNight()
	indicator = 0
	lastBits = -1
	flippedFor = 0
	ctx.UI.show(role, spec.label)
	ctx.Camera.begin(car, base, rig, role, seat)
	ctx.Radio.attach(car, base)
	ctx.Radio.setInside(ctx.Camera.state.mode == "interior")
	ctx.UI.setRadio(ctx.Radio.isOn(), (ctx.Radio.nowPlaying()))
	doorSounds(true)
	if role == "driver" then
		ctx.Visuals.setSkip(car)
	end
	if marker then
		marker:Destroy()
		marker = nil
	end
	ctx.Api.fireChanged(role, car)
end

function Drive.finish()
	if not cur then
		return
	end
	local c = cur
	cur = nil
	if c.vf then
		pcall(function()
			c.vf.Force = Vector3.zero
			c.tq.Torque = Vector3.zero
		end)
	end
	ctx.Input.unbind()
	ctx.UI.hide()
	ctx.Camera.finish()
	ctx.Radio.detach()
	doorSounds(false)
	ctx.Visuals.setSkip(nil)
	setControls(true)
	setPrompts(true)
	ctx.Api.fireChanged(nil, nil)
end

-- Seat watcher (works even if a server event is lost)
local function checkSeat(hum: Humanoid)
	local seat = hum.SeatPart
	if seat and seat.Parent and seat.Parent:IsA("Model") and seat.Parent:GetAttribute(VS.Attr.Rigged) then
		local role = if seat.Name == VS.Parts.DriverSeat then "driver" else "passenger"
		task.spawn(begin, seat.Parent :: Model, role, seat)
	elseif cur then
		Drive.finish()
	end
end

local function watchCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	if not (hum and hum:IsA("Humanoid")) then
		return
	end
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		checkSeat(hum)
	end)
	hum.Died:Connect(function()
		if cur then
			Drive.finish()
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------------
function Drive.exit()
	if cur then
		send({ op = "exit" })
	end
end

function Drive.toggleLights()
	lightsManual = true
	lightsOn = not lightsOn
	ctx.K.feedback("toggle")
end

function Drive.cycleCamera()
	if cur then
		ctx.Camera.cycle()
		ctx.K.feedback("tap")
	end
end

function Drive.flip()
	if cur and cur.role == "driver" then
		send({ op = "flip" })
	end
end

function Drive.setIndicator(bit: number)
	indicator = if indicator == bit then 0 else bit
end

function Drive.toggleRadio()
	if not cur then
		return
	end
	local on = ctx.Radio.toggle()
	ctx.UI.setRadio(on, (ctx.Radio.nowPlaying()))
	ctx.K.feedback("toggle")
end

-- A floating "내 차" tag over a freshly called car (30 s or until someone gets in).
function Drive.markCar(car: Model)
	if marker then
		marker:Destroy()
	end
	local K = ctx.K
	local target = car:FindFirstChild(VS.Parts.Body) or car.PrimaryPart
	if not target then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "GwangalliMyCarMarker"
	bb.Adornee = target :: BasePart
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(110, 40)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	bb.MaxDistance = 1500
	bb.ResetOnSpawn = false
	local pill = K.frame(bb, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.1, BackgroundColor3 = K.Color.glass2 })
	K.corner(pill, UDim.new(0.5, 0))
	K.stroke(pill, K.Color.cyan, 1.5, 0.2)
	K.text(pill, { Size = UDim2.fromScale(1, 1), Text = "🚗 내 차", Font = K.Font.bold, TextSize = K.Type.bodySm, TextXAlignment = Enum.TextXAlignment.Center })
	bb.Parent = player:FindFirstChildOfClass("PlayerGui")
	marker = bb
	task.delay(30, function()
		if marker == bb then
			bb:Destroy()
			marker = nil
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Frame loops
---------------------------------------------------------------------------------------------------
local function stateBits(input: any, st: any): number
	local B = VS.Bits
	local bits = 0
	if st and st.braking then
		bits += B.BRAKE
	end
	if st and st.gear == "R" then
		bits += B.REVERSE
	end
	if lightsOn then
		bits += B.LIGHTS
	end
	if input.horn then
		bits += B.HORN
	end
	if input.handbrake then
		bits += B.HANDBRAKE
	end
	bits += indicator
	return bits
end

local function physics(dt: number)
	local c = cur
	if not c or c.role ~= "driver" then
		return
	end
	if not c.base.Parent or not c.vf or not c.tq then
		return
	end
	local t = os.clock()
	if t > charRefreshAt then
		charRefreshAt = t + 1
		refreshParams()
	end
	local input = ctx.Input.read()
	if c.base.Anchored then
		-- server has not woken it yet (or took it back): nothing to push
		c.vf.Force = Vector3.zero
		c.tq.Torque = Vector3.zero
	else
		VS.Controller.stepRoblox(c.ctl, dt, input, c.base, c.vf, c.tq, c.params)
	end
	for i, m in c.motors do
		if m.steer and m.spin then
			local hub, spin = VS.Controller.wheelTransforms(c.ctl, i)
			m.steer.Transform = hub
			m.spin.Transform = spin
		end
	end
	-- lamp / horn bits
	if not lightsManual then
		lightsOn = isNight()
	end
	local bits = stateBits(input, c.ctl)
	if bits ~= lastBits and t - lastSent > 0.1 then
		lastBits = bits
		lastSent = t
		send({ op = "state", bits = bits })
	end
	-- flipped on its side / roof and slow: offer the flip button
	if VS.isFlipped(c.base.CFrame) and math.abs(c.ctl.speed) < 6 then
		flippedFor += dt
	else
		flippedFor = 0
	end
end

local function render(dt: number)
	local c = cur
	if not c then
		return
	end
	local vel = c.base.AssemblyLinearVelocity
	local speed = vel:Dot(c.base.CFrame.LookVector)
	local top = VS.studs(c.spec.topKmh)
	local input = ctx.Input.read()
	ctx.Camera.update(dt, { speed = speed, top = top, steer = if c.role == "driver" then input.steer else 0, vel = vel })
	ctx.UI.update({
		kmh = VS.kmh(speed),
		frac = math.abs(speed) / top,
		gear = if c.ctl then c.ctl.gear else "N",
		lights = lightsOn,
		flipped = flippedFor > 1.2,
	})
end

---------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------
function Drive.start(c: any)
	ctx = c
	VS = c.VS
	local remotes = ReplicatedStorage:WaitForChild(VS.Remotes.Folder, 60)
	if remotes then
		remote = remotes:WaitForChild(VS.Remotes.Event, 30) :: RemoteEvent
		ctx.callFn = remotes:WaitForChild(VS.Remotes.Call, 30)
	else
		warn("[GwangalliDrive] " .. VS.Remotes.Folder .. " missing (server script not running?)")
	end
	if remote then
		(remote :: RemoteEvent).OnClientEvent:Connect(function(payload: any)
			if type(payload) ~= "table" then
				return
			end
			if payload.op == "enter" and typeof(payload.car) == "Instance" then
				task.spawn(begin, payload.car, if payload.role == "driver" then "driver" else "passenger", payload.seat)
			elseif payload.op == "exit" then
				if cur and (payload.car == nil or payload.car == cur.car) then
					Drive.finish()
				end
			elseif payload.op == "toast" then
				ctx.K.toast({ kind = payload.kind or "info", title = tostring(payload.title or ""), body = payload.body })
			end
		end)
	end

	local Input = ctx.Input
	Input.on("camera", Drive.cycleCamera)
	Input.on("lights", Drive.toggleLights)
	Input.on("exit", Drive.exit)
	Input.on("flip", Drive.flip)
	Input.on("left", function()
		Drive.setIndicator(VS.Bits.LEFT)
	end)
	Input.on("right", function()
		Drive.setIndicator(VS.Bits.RIGHT)
	end)
	Input.on("hazard", function()
		Drive.setIndicator(VS.Bits.HAZARD)
	end)
	Input.on("radio", Drive.toggleRadio)
	local UI = ctx.UI
	UI.on("camera", Drive.cycleCamera)
	UI.on("lights", Drive.toggleLights)
	UI.on("radio", Drive.toggleRadio)
	UI.on("exit", Drive.exit)
	UI.on("flip", Drive.flip)
	ctx.Camera.onMode(function(mode: string)
		ctx.Radio.setInside(mode == "interior")
	end)
	ctx.Radio.changed:Connect(function(on: boolean, title: string?)
		ctx.UI.setRadio(on, title)
	end)
	UI.on("call", function(kind: string)
		ctx.Api.callCar(kind)
	end)
	UI.on("dismiss", function()
		ctx.Api.dismiss()
	end)

	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(ch)
		if cur then
			Drive.finish()
		end
		watchCharacter(ch)
	end)

	RunService.PreSimulation:Connect(physics)
	RunService:BindToRenderStep("GwangalliDriveCamera", Enum.RenderPriority.Camera.Value + 1, render)
end

return Drive
