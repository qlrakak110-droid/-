--!strict
-- GwangalliDecorPlus/Photo: 📸 집 사진 모드 — every other GUI hides, free orbit camera (drag / pinch / sticks /
-- WASD), photo filters (기본 · 따뜻하게 · 필름 · 야경 · 흑백) via a local ColorCorrection (+ depth of field
-- for 필름 when the engine has it), shutter flash, and the server's small daily reward.
--   Photo.open(U, fromEditor) / Photo.close() / Photo.isOpen()

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliDecorShared"))
local Text = Shared.Text

local Ui = require(script.Parent:WaitForChild("Ui"))
local Net = require(script.Parent:WaitForChild("Net"))
local Camera = require(script.Parent:WaitForChild("Camera"))
local C, F = Ui.C, Ui.F

local Photo = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local open = false
local fromEditor = false
local hidden: { [ScreenGui]: boolean } = {}
local conns: { RBXScriptConnection } = {}
local fx: { Instance } = {}

local FILTERS = {
	{ name = "기본" },
	{ name = "따뜻하게", tint = Color3.fromRGB(255, 236, 214), sat = 0.12, con = 0.05, bright = 0.02 },
	{ name = "필름", tint = Color3.fromRGB(240, 236, 220), sat = -0.18, con = 0.14, bright = 0, dof = true },
	{ name = "야경", tint = Color3.fromRGB(214, 222, 255), sat = 0.2, con = 0.12, bright = -0.06 },
	{ name = "흑백", tint = Color3.fromRGB(255, 255, 255), sat = -1, con = 0.12, bright = 0 },
}

local function clearFx()
	for _, e in fx do
		e:Destroy()
	end
	fx = {}
end

local function setFilter(i: number)
	clearFx()
	local f = FILTERS[i]
	if not f or not f.tint then
		return
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "GwDecorPlusPhotoCC"
	cc.TintColor = f.tint
	cc.Saturation = f.sat
	cc.Contrast = f.con
	cc.Brightness = f.bright
	cc.Parent = Lighting
	table.insert(fx, cc)
	if f.dof then
		pcall(function()
			local d = Instance.new("DepthOfFieldEffect")
			d.Name = "GwDecorPlusPhotoDOF"
			d.FarIntensity = 0.35
			d.FocusDistance = 18
			d.InFocusRadius = 14
			d.NearIntensity = 0.2
			d.Parent = Lighting
			table.insert(fx, d)
		end)
	end
end

local function hideOthers(on: boolean)
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then
		return
	end
	if on then
		for _, g in pg:GetChildren() do
			if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
				hidden[g] = true
				g.Enabled = false
			end
		end
	else
		for g in hidden do
			if g.Parent then
				g.Enabled = true
			end
		end
		hidden = {}
	end
end

local function shutter()
	if not gui then
		return
	end
	local flash = Ui.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, Size = UDim2.new(1, 0, 1, 0), ZIndex = 100, Parent = gui })
	TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	task.delay(0.5, function()
		flash:Destroy()
	end)
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = "rbxasset://sounds/clickfast.wav"
		s.Volume = 0.8
		s.Parent = gui
		s:Play()
		task.delay(1, function()
			s:Destroy()
		end)
	end)
	task.spawn(function()
		local res = Net.call("photo", {})
		if res.ok then
			Ui.toast(Text.UI.photoSaved .. (if res.gain then " · 행복 +1" else ""), "good")
		else
			Ui.toast("📸 찰칵!", "good")
		end
	end)
end

function Photo.open(U: any, fromEd: boolean)
	if open or not U then
		return
	end
	open = true
	fromEditor = fromEd
	gui = Ui.screen("GwangalliDecorPlusPhoto", 30)
	;(gui :: ScreenGui):SetAttribute("HideGwangalliHUD", true)
	Ui.scale(gui :: ScreenGui)
	hideOthers(true)
	if not fromEditor then
		local ch = player.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		local at = nil
		if hrp and hrp:IsA("BasePart") then
			at = U.F:PointToObjectSpace(hrp.Position) - Vector3.new(0, 1.5, 0)
		end
		Camera.start(U, at)
	end
	Camera.free(true)
	Camera.zoom(0.7)
	local bar = Ui.panel(gui, { Position = UDim2.new(0.5, -300, 1, -92), Size = UDim2.new(0, 600, 0, 76) })
	local sc = Ui.new("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(1, -16, 1, 0), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 0, Parent = bar })
	Ui.list(sc, "x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local sets: { (boolean) -> () } = {}
	for i, f in FILTERS do
		local _, set = Ui.chip(sc, f.name, i == 1, function()
			for j, s in sets do
				s(j == i)
			end
			setFilter(i)
		end, i)
		sets[i] = set
	end
	Ui.button(sc, { text = "📸 " .. Text.UI.shutter, w = 120, h = 56, style = "gold", order = 20, onClick = shutter })
	Ui.button(sc, { text = "✕", w = 56, h = 56, style = "ghost", order = 21, onClick = function()
		Photo.close()
	end })
	Ui.label(gui, "드래그로 시점 · 휠/두 손가락으로 확대 · WASD 이동", 13, C.sub, F.medium, { Position = UDim2.new(0.5, -300, 1, -120), Size = UDim2.new(0, 600, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	-- input
	local drag: Vector2? = nil
	local touches: { [InputObject]: Vector2 } = {}
	local pinchD: number? = nil
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
			drag = UserInputService:GetMouseLocation()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			touches[input] = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Space then
			shutter()
		elseif input.KeyCode == Enum.KeyCode.ButtonB then
			Photo.close()
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input, gp)
		if input.UserInputType == Enum.UserInputType.MouseMovement and drag then
			Camera.orbit(-input.Delta.X * 0.35, input.Delta.Y * 0.25)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not gp then
			Camera.zoom(if input.Position.Z > 0 then 0.88 else 1.14)
		elseif input.UserInputType == Enum.UserInputType.Touch and touches[input] then
			local p = Vector2.new(input.Position.X, input.Position.Y)
			local prev = touches[input]
			touches[input] = p
			local pts = {}
			for _, v in touches do
				table.insert(pts, v)
			end
			if #pts >= 2 then
				local d = (pts[1] - pts[2]).Magnitude
				if pinchD then
					Camera.zoom(math.clamp(pinchD / math.max(d, 1), 0.85, 1.18))
				end
				pinchD = d
			else
				local dd = p - prev
				Camera.orbit(-dd.X * 0.4, dd.Y * 0.3)
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			Camera.orbit(-input.Position.X * 4, input.Position.Y * 3)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			Camera.pan(input.Position.X * 0.5, input.Position.Y * 0.5)
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
			drag = nil
		elseif input.UserInputType == Enum.UserInputType.Touch then
			touches[input] = nil
			pinchD = nil
		end
	end))
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		if UserInputService:GetFocusedTextBox() then
			return
		end
		local x, z = 0, 0
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			z += 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			z -= 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			x -= 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			x += 1
		end
		if x ~= 0 or z ~= 0 then
			Camera.pan(x * dt * 12, z * dt * 12)
		end
	end))
end

function Photo.close()
	if not open then
		return
	end
	open = false
	for _, c in conns do
		c:Disconnect()
	end
	conns = {}
	clearFx()
	hideOthers(false)
	Camera.free(false)
	if not fromEditor then
		Camera.stop()
	end
	if gui then
		gui:Destroy()
		gui = nil
	end
end

function Photo.isOpen(): boolean
	return open
end

return Photo
