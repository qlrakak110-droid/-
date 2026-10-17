-- GwangalliCarDealer/Viewport (client): 3D car previews in ViewportFrames, cloned on demand from
-- ReplicatedStorage.GwangalliCarDealerPreviews (server-built, inert, front toward +Z, wheels on y = 0).
--   Viewport.supported() -> bool                (no ViewportFrame: the UI shows glyph tiles instead)
--   Viewport.stage(parent, opts) -> stage        studio backdrop + interactive orbit view (detail / ceremony)
--       stage:set(previewKey, colorId?, used?)   stage:setColor(colorId)   stage:zoom(delta)   stage:reset()
--       stage:setAuto(on)   stage:destroy()      opts = { interactive = true, spin = deg/s, zIndex }
--   Viewport.thumb(parent, previewKey, colorId?, used?) -> handle { destroy() }   static 3/4 front view
--   Viewport.live() -> number of live viewports (thumbnail budget)
-- Recolouring uses GwangalliGarageShared.applyColor (the same paint parts the delivered car gets).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Viewport = {}

local ctx: any
local Ui: any
local supported: boolean? = nil
local liveCount = 0

function Viewport.init(c: any)
	ctx = c
	Ui = c.Ui
end

function Viewport.supported(): boolean
	if supported == nil then
		local ok, vf = pcall(Instance.new, "ViewportFrame")
		supported = ok and vf ~= nil
		if ok and vf then
			vf:Destroy()
		end
	end
	return supported :: boolean
end

function Viewport.live(): number
	return liveCount
end

local function folder(): Instance?
	return ReplicatedStorage:FindFirstChild(ctx.S.NAMES.Previews)
end

-- Template by key; waits up to `wait` s for the server to build it.
local function template(key: string, wait: number?): Model?
	local f = folder()
	local t = f and f:FindFirstChild(key)
	if t and t:IsA("Model") then
		return t
	end
	if (wait or 0) <= 0 then
		return nil
	end
	local t0 = os.clock()
	while os.clock() - t0 < (wait :: number) do
		f = folder()
		t = f and f:FindFirstChild(key)
		if t and t:IsA("Model") then
			return t
		end
		if f and f:GetAttribute("Ready") == true then
			return nil
		end
		task.wait(0.25)
	end
	return nil
end
Viewport.template = template

local function paint(model: Model, colorId: string?, used: boolean?)
	local GS = ctx.GS
	if not GS or type(GS.applyColor) ~= "function" then
		return
	end
	pcall(function()
		if colorId then
			local c3 = GS.color3(colorId)
			if used and type(GS.dirtColor) == "function" then
				c3 = GS.dirtColor(c3, 0.25)
			end
			GS.applyColor(model, c3, colorId)
		end
	end)
end

local function sizeOf(model: Model): Vector3
	local s = model:GetAttribute("Size")
	if typeof(s) == "Vector3" then
		return s
	end
	local _, size = model:GetBoundingBox()
	return Vector3.new(math.min(size.X, size.Z), size.Y, math.max(size.X, size.Z))
end

local function floorDisc(radius: number): Part
	local p = Instance.new("Part")
	p.Name = "StageFloor"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.2, radius * 2, radius * 2)
	p.CFrame = CFrame.new(0, -0.1, 0) * CFrame.Angles(0, 0, math.rad(90))
	p.Color = Color3.fromRGB(26, 29, 38)
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0.12
	p.Anchored = true
	p.CanCollide = false
	local ring = Instance.new("Part")
	ring.Name = "StageRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.05, radius * 2 + 0.5, radius * 2 + 0.5)
	ring.CFrame = CFrame.new(0, -0.18, 0) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = Color3.fromRGB(64, 132, 255)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.35
	ring.Anchored = true
	ring.CanCollide = false
	ring.Parent = p
	return p
end

local function setupFrame(vf: ViewportFrame)
	vf.BackgroundTransparency = 1
	vf.Ambient = Color3.fromRGB(150, 152, 162)
	vf.LightColor = Color3.fromRGB(255, 248, 236)
	vf.LightDirection = Vector3.new(-0.55, -1, -0.35)
end

-- Static thumbnail -------------------------------------------------------------------------------------------
function Viewport.thumb(parent: GuiObject, key: string, colorId: string?, used: boolean?): any
	local handle: any = { alive = true }
	if not Viewport.supported() then
		function handle.destroy() end
		return handle
	end
	local vf = Instance.new("ViewportFrame")
	vf.Name = "Thumb"
	vf.Size = UDim2.fromScale(1, 1)
	vf.ZIndex = parent.ZIndex + 1
	setupFrame(vf)
	vf.Parent = parent
	liveCount += 1
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vf
	vf.CurrentCamera = cam
	function handle.destroy()
		if handle.alive then
			handle.alive = false
			liveCount -= 1
			vf:Destroy()
		end
	end
	task.spawn(function()
		local t = template(key, 20)
		if not t or not handle.alive then
			return
		end
		local m = t:Clone()
		paint(m, colorId, used)
		m.Parent = vf
		local s = sizeOf(m)
		local target = Vector3.new(0, s.Y * 0.42, 0)
		local dist = (math.max(s.Z, s.X * 1.7) * 0.5) / math.tan(math.rad(cam.FieldOfView / 2)) * 1.08
		local yaw, pitch = math.rad(38), math.rad(10)
		local dir = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
		cam.CFrame = CFrame.lookAt(target + dir * dist, target)
	end)
	return handle
end

-- Interactive stage ------------------------------------------------------------------------------------------
local Stage = {}
Stage.__index = Stage

function Viewport.stage(parent: GuiObject, opts: { [string]: any }?): any
	local o = opts or {}
	local C = Ui.C
	local z = o.zIndex or (parent.ZIndex + 1)
	local root = Ui.frame(parent, { Name = "Stage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(16, 19, 28), ZIndex = z, ClipsDescendants = true })
	Ui.corner(root, o.radius or 18)
	Ui.grad(root, Color3.fromRGB(46, 54, 76), Color3.fromRGB(10, 12, 18), 90)
	-- soft spotlight glow behind the car
	local glow = Ui.frame(root, { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromScale(0.9, 0.55), BackgroundTransparency = 0.82, BackgroundColor3 = Color3.fromRGB(120, 160, 255), ZIndex = z })
	Ui.corner(glow, 999)
	local self = setmetatable({
		root = root,
		vf = nil :: ViewportFrame?,
		cam = nil :: Camera?,
		model = nil :: Model?,
		key = nil :: string?,
		colorId = nil :: string?,
		used = false,
		yaw = math.rad(32),
		pitch = math.rad(9),
		zoomK = 1,
		baseDist = 14,
		target = Vector3.new(0, 1.6, 0),
		auto = true,
		spin = o.spin or (ctx.C.PREVIEW.spinDegPerSec),
		dragging = false,
		idleAt = 0,
		conns = {} :: { RBXScriptConnection },
		alive = true,
		token = 0,
	}, Stage)
	if not Viewport.supported() then
		local glyph = Ui.label(root, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "🚗", TextSize = 72, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 1 })
		self.glyph = glyph
		return self
	end
	local vf = Instance.new("ViewportFrame")
	vf.Name = "View"
	vf.Size = UDim2.fromScale(1, 1)
	vf.ZIndex = z + 1
	setupFrame(vf)
	vf.Parent = root
	liveCount += 1
	local cam = Instance.new("Camera")
	cam.FieldOfView = 34
	cam.Parent = vf
	vf.CurrentCamera = cam
	self.vf = vf
	self.cam = cam
	local loading = Ui.label(root, { Name = "Loading", Size = UDim2.fromScale(1, 1), Text = "", TextSize = 64, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.2, ZIndex = z + 2 })
	self.loading = loading
	if o.interactive ~= false then
		local touches: { [InputObject]: Vector2 } = {}
		table.insert(self.conns, vf.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				self.dragging = true
				self.auto = false
				touches[input] = Vector2.new(input.Position.X, input.Position.Y)
			end
		end))
		table.insert(self.conns, UserInputService.InputChanged:Connect(function(input: InputObject)
			if not self.alive then
				return
			end
			local t = input.UserInputType
			if self.dragging and (t == Enum.UserInputType.MouseMovement or (t == Enum.UserInputType.Touch and touches[input])) then
				local d: Vector2
				if t == Enum.UserInputType.Touch then
					local last = touches[input]
					local now = Vector2.new(input.Position.X, input.Position.Y)
					d = now - last
					touches[input] = now
					local n = 0
					for _ in touches do
						n += 1
					end
					if n > 1 then
						return -- pinch handled below
					end
				else
					d = Vector2.new(input.Delta.X, input.Delta.Y)
				end
				self.yaw -= d.X * 0.012
				self.pitch = math.clamp(self.pitch + d.Y * 0.006, math.rad(-2), math.rad(38))
				self.idleAt = os.clock()
				self:_frame()
			elseif t == Enum.UserInputType.MouseWheel and self.hover then
				self:zoom(-input.Position.Z * 0.08)
			end
		end))
		table.insert(self.conns, UserInputService.InputEnded:Connect(function(input: InputObject)
			touches[input] = nil
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if next(touches) == nil then
					self.dragging = false
					self.idleAt = os.clock()
				end
			end
		end))
		table.insert(self.conns, vf.MouseEnter:Connect(function()
			self.hover = true
		end))
		table.insert(self.conns, vf.MouseLeave:Connect(function()
			self.hover = false
		end))
		table.insert(self.conns, UserInputService.TouchPinch:Connect(function(_pos, scale, _vel, state)
			if not self.dragging then
				return
			end
			if state == Enum.UserInputState.Change then
				self:zoom((1 - scale) * 0.25)
			end
		end))
	end
	table.insert(self.conns, RunService.RenderStepped:Connect(function(dt)
		if not self.alive or not self.model then
			return
		end
		if not root.Visible or not root:FindFirstAncestorWhichIsA("ScreenGui") or not (root:FindFirstAncestorWhichIsA("ScreenGui") :: ScreenGui).Enabled then
			return
		end
		-- gamepad right stick orbits
		local pads = {}
		if UserInputService.GamepadEnabled then
			local okP, list = pcall(UserInputService.GetGamepadState, UserInputService, Enum.UserInputType.Gamepad1)
			pads = if okP and type(list) == "table" then list else {}
		end
		for _, st in pads do
			if st.KeyCode == Enum.KeyCode.Thumbstick2 and st.Position.Magnitude > 0.2 then
				self.yaw -= st.Position.X * dt * 2.4
				self.pitch = math.clamp(self.pitch + st.Position.Y * dt * 1.2, math.rad(-2), math.rad(38))
				self.auto = false
				self.idleAt = os.clock()
			end
		end
		if not self.auto and not self.dragging and os.clock() - self.idleAt > 4 then
			self.auto = true
		end
		if self.auto and not Ui.reduced() then
			self.yaw += math.rad(self.spin) * dt
		end
		self:_frame()
	end))
	return self
end

function Stage:_frame()
	local cam = self.cam
	if not cam then
		return
	end
	local dist = self.baseDist * self.zoomK
	local dir = Vector3.new(math.sin(self.yaw) * math.cos(self.pitch), math.sin(self.pitch), math.cos(self.yaw) * math.cos(self.pitch))
	cam.CFrame = CFrame.lookAt(self.target + dir * dist, self.target)
end

function Stage:set(key: string?, colorId: string?, used: boolean?, glyph: string?)
	self.token += 1
	local token = self.token
	self.key = key
	self.colorId = colorId
	self.used = used == true
	if self.model then
		self.model:Destroy()
		self.model = nil
	end
	if self.glyph then
		self.glyph.Text = glyph or "🚗"
		return
	end
	if self.loading then
		self.loading.Text = glyph or "🚗"
	end
	if not key or not self.vf then
		return
	end
	task.spawn(function()
		local t = template(key, 25)
		if token ~= self.token or not self.alive then
			return
		end
		if not t then
			if self.loading then
				self.loading.Text = glyph or "🚗"
			end
			return
		end
		local m = t:Clone()
		paint(m, colorId, used)
		local s = sizeOf(m)
		local disc = floorDisc(math.max(s.Z, s.X) * 0.62)
		disc.Parent = m
		m.Parent = self.vf
		self.model = m
		if self.loading then
			self.loading.Text = ""
		end
		self.target = Vector3.new(0, s.Y * 0.4, 0)
		self.baseDist = (math.max(s.Z, s.X * 1.6) * 0.5) / math.tan(math.rad((self.cam :: Camera).FieldOfView / 2)) * 1.15
		self:_frame()
	end)
end

function Stage:setColor(colorId: string)
	self.colorId = colorId
	if self.model then
		paint(self.model, colorId, self.used)
	end
end

function Stage:zoom(delta: number)
	self.zoomK = math.clamp(self.zoomK + delta, 0.62, 1.6)
	self.idleAt = os.clock()
	self:_frame()
end

function Stage:reset()
	self.yaw = math.rad(32)
	self.pitch = math.rad(9)
	self.zoomK = 1
	self.auto = true
	self:_frame()
end

function Stage:setAuto(on: boolean)
	self.auto = on
end

function Stage:destroy()
	if not self.alive then
		return
	end
	self.alive = false
	for _, c in self.conns do
		c:Disconnect()
	end
	if self.vf then
		liveCount -= 1
	end
	self.root:Destroy()
end

return Viewport
