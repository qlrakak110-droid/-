--!nocheck
-- rbx.luau: a small Roblox client mock for running GwangalliBuildingInterior offline (luau CLI).
-- Instances (tree, properties with class defaults, attributes, tags, signals), services, task, workspace.
local Enums = require("./enums")
Enums.setData(require("./enumsdata"))
local DT = require("./datatypes")
local G = DT.globals
local CFrame, Vector3, Color3, Enum = G.CFrame, G.Vector3, G.Color3, G.Enum
local UDim2, UDim, Vector2 = G.UDim2, G.UDim, G.Vector2

local R = {}
R.G = G

-- signals ---------------------------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ _c = {} }, Signal)
end
function Signal:Connect(fn)
	local c = { Connected = true, _fn = fn }
	function c.Disconnect(self2)
		(self2 or c).Connected = false
	end
	table.insert(self._c, c)
	return c
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end
function Signal:Wait()
	return nil
end
function Signal:Fire(...)
	for _, c in table.clone(self._c) do
		if c.Connected then
			local ok, err = pcall(c._fn, ...)
			if not ok then
				print("[signal error] " .. tostring(err))
			end
		end
	end
end
R.Signal = Signal

-- classes ---------------------------------------------------------------------------------------------
local SUPER = {
	Part = "FormFactorPart", WedgePart = "FormFactorPart", FormFactorPart = "BasePart", CornerWedgePart = "BasePart",
	Seat = "Part", SpawnLocation = "Part", VehicleSeat = "BasePart", MeshPart = "BasePart", TrussPart = "BasePart",
	UnionOperation = "PartOperation", PartOperation = "BasePart", BasePart = "PVInstance", Model = "PVInstance",
	WorldRoot = "Model", Workspace = "WorldRoot", Camera = "PVInstance", PVInstance = "Instance", Folder = "Instance",
	PointLight = "Light", SpotLight = "Light", SurfaceLight = "Light", Light = "Instance",
	SurfaceGui = "SurfaceGuiBase", SurfaceGuiBase = "LayerCollector", BillboardGui = "LayerCollector", ScreenGui = "LayerCollector",
	LayerCollector = "GuiBase2d", GuiBase2d = "GuiBase", GuiBase = "Instance",
	Frame = "GuiObject", TextLabel = "GuiObject", TextBox = "GuiObject", ImageLabel = "GuiObject", ScrollingFrame = "GuiObject",
	TextButton = "GuiButton", ImageButton = "GuiButton", GuiButton = "GuiObject", GuiObject = "GuiBase2d",
	UICorner = "UIComponent", UIStroke = "UIComponent", UIGradient = "UIComponent", UIPadding = "UIComponent",
	UIListLayout = "UIGridStyleLayout", UIGridLayout = "UIGridStyleLayout", UIGridStyleLayout = "UILayout", UILayout = "UIComponent",
	UIAspectRatioConstraint = "UIConstraint", UITextSizeConstraint = "UIConstraint", UIConstraint = "UIComponent", UIComponent = "UIBase", UIBase = "Instance",
	SpecialMesh = "FileMesh", FileMesh = "DataModelMesh", BlockMesh = "BevelMesh", CylinderMesh = "BevelMesh", BevelMesh = "DataModelMesh", DataModelMesh = "Instance",
	Weld = "JointInstance", ManualWeld = "JointInstance", Motor6D = "Motor", Motor = "JointInstance", JointInstance = "Instance", WeldConstraint = "Instance",
	ProximityPrompt = "Instance", Attachment = "Instance", ParticleEmitter = "Instance", Sound = "Instance", Beam = "Instance", Highlight = "Instance",
	Decal = "FaceInstance", Texture = "Decal", FaceInstance = "Instance", ClickDetector = "Instance",
	ModuleScript = "LuaSourceContainer", LocalScript = "Script", Script = "BaseScript", BaseScript = "LuaSourceContainer", LuaSourceContainer = "Instance",
	StringValue = "ValueBase", NumberValue = "ValueBase", BoolValue = "ValueBase", IntValue = "ValueBase", ObjectValue = "ValueBase",
	Vector3Value = "ValueBase", CFrameValue = "ValueBase", Color3Value = "ValueBase", ValueBase = "Instance",
	Humanoid = "Instance", Player = "Instance", Players = "Instance", PlayerScripts = "Instance", Tool = "Instance", Configuration = "Instance",
	Lighting = "Instance", ReplicatedStorage = "Instance", DataModel = "Instance", Terrain = "BasePart",
}
local function isA(cls, c)
	local k = cls
	while k do
		if k == c then
			return true
		end
		k = SUPER[k]
	end
	return c == "Instance"
end

local WHITE = Color3.new(1, 1, 1)
local function defaults(cls)
	local d = {}
	if isA(cls, "BasePart") then
		d.Anchored = false; d.CanCollide = true; d.CanQuery = true; d.CanTouch = true; d.Massless = false
		d.CastShadow = true; d.Transparency = 0; d.LocalTransparencyModifier = 0; d.Reflectance = 0; d.Locked = false
		d.Color = Color3.fromRGB(163, 162, 165); d.Material = Enum.Material.Plastic; d.CFrame = CFrame.new()
		d.Size = Vector3.new(4, 1, 2); d.TopSurface = Enum.SurfaceType.Smooth; d.BottomSurface = Enum.SurfaceType.Smooth
		d.Archivable = true; d.CollisionGroup = "Default"; d.AssemblyLinearVelocity = Vector3.zero; d.MaterialVariant = ""
		if cls == "Part" or cls == "Seat" or cls == "SpawnLocation" then
			d.Shape = Enum.PartType.Block
		end
		if cls == "Seat" then
			d.Disabled = false
		end
	elseif isA(cls, "Light") then
		d.Enabled = true; d.Brightness = 1; d.Color = WHITE; d.Range = if cls == "PointLight" then 8 else 16; d.Shadows = false
		d.Angle = 90; d.Face = Enum.NormalId.Front
	elseif cls == "SurfaceGui" then
		d.Face = Enum.NormalId.Front; d.Enabled = true; d.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize; d.PixelsPerStud = 50
		d.CanvasSize = Vector2.new(800, 600); d.LightInfluence = 1; d.Brightness = 1; d.AlwaysOnTop = false; d.MaxDistance = 1000
		d.ClipsDescendants = false; d.ZOffset = 0; d.ResetOnSpawn = true
	elseif cls == "BillboardGui" or cls == "ScreenGui" then
		d.Enabled = true; d.Size = UDim2.new(0, 100, 0, 100); d.AlwaysOnTop = false; d.MaxDistance = 1000; d.LightInfluence = 0; d.StudsOffset = Vector3.zero
	elseif isA(cls, "GuiObject") then
		d.Size = UDim2.new(0, 100, 0, 100); d.Position = UDim2.new(); d.AnchorPoint = Vector2.new(); d.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
		d.BackgroundTransparency = 0; d.BorderSizePixel = 1; d.BorderColor3 = Color3.fromRGB(27, 42, 53); d.Visible = true; d.ZIndex = 1
		d.Rotation = 0; d.LayoutOrder = 0; d.ClipsDescendants = false
		if cls == "TextLabel" or cls == "TextButton" or cls == "TextBox" then
			d.Size = UDim2.new(0, 200, 0, 50); d.BackgroundColor3 = WHITE; d.Text = if cls == "TextBox" then "" else "Label"
			d.TextColor3 = Color3.fromRGB(27, 42, 53); d.TextScaled = false; d.TextSize = 14; d.Font = Enum.Font.Legacy
			d.FontFace = G.Font.fromEnum(Enum.Font.Legacy); d.TextWrapped = false; d.TextXAlignment = Enum.TextXAlignment.Center
			d.TextYAlignment = Enum.TextYAlignment.Center; d.TextTransparency = 0; d.TextStrokeTransparency = 1
			d.TextStrokeColor3 = Color3.new(0, 0, 0); d.RichText = false; d.LineHeight = 1
		end
		if cls == "ImageLabel" or cls == "ImageButton" then
			d.Image = ""; d.ImageColor3 = WHITE; d.ImageTransparency = 0; d.ScaleType = Enum.ScaleType.Stretch
		end
	elseif cls == "UIStroke" then
		d.Color = Color3.new(0, 0, 0); d.Thickness = 1; d.Transparency = 0; d.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; d.LineJoinMode = Enum.LineJoinMode.Round; d.Enabled = true
	elseif cls == "UICorner" then
		d.CornerRadius = UDim.new(0, 8)
	elseif cls == "UIGradient" then
		d.Color = G.ColorSequence.new(WHITE); d.Rotation = 0; d.Offset = Vector2.new(); d.Transparency = G.NumberSequence.new(0); d.Enabled = true
	elseif cls == "UIPadding" then
		d.PaddingLeft = UDim.new(); d.PaddingRight = UDim.new(); d.PaddingTop = UDim.new(); d.PaddingBottom = UDim.new()
	elseif cls == "UIListLayout" then
		d.FillDirection = Enum.FillDirection.Vertical; d.Padding = UDim.new(); d.SortOrder = Enum.SortOrder.LayoutOrder
		d.HorizontalAlignment = Enum.HorizontalAlignment.Left; d.VerticalAlignment = Enum.VerticalAlignment.Top
	elseif cls == "SpecialMesh" then
		d.MeshType = Enum.MeshType.Head; d.Scale = Vector3.one; d.Offset = Vector3.zero; d.MeshId = ""; d.TextureId = ""; d.VertexColor = Vector3.one
	elseif cls == "ProximityPrompt" then
		d.ActionText = "Interact"; d.ObjectText = ""; d.HoldDuration = 0; d.MaxActivationDistance = 10; d.KeyboardKeyCode = Enum.KeyCode.E
		d.GamepadKeyCode = Enum.KeyCode.ButtonX; d.RequiresLineOfSight = true; d.Enabled = true; d.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		d.Style = Enum.ProximityPromptStyle.Default; d.UIOffset = Vector2.new(); d.ClickablePrompt = true; d.AutoLocalize = true
	elseif cls == "Attachment" then
		d.CFrame = CFrame.new(); d.Visible = false
	elseif cls == "Sound" then
		d.SoundId = ""; d.Volume = 0.5; d.Playing = false; d.Looped = false; d.PlaybackSpeed = 1; d.RollOffMaxDistance = 10000
		d.RollOffMinDistance = 10; d.TimePosition = 0; d.IsLoaded = true; d.TimeLength = 1
	elseif cls == "ParticleEmitter" then
		d.Enabled = true; d.Rate = 20; d.Texture = ""; d.LightEmission = 0; d.Lifetime = G.NumberRange.new(5, 10); d.Speed = G.NumberRange.new(5)
		d.Color = G.ColorSequence.new(WHITE); d.Size = G.NumberSequence.new(1); d.Transparency = G.NumberSequence.new(0); d.SpreadAngle = Vector2.new()
		d.Acceleration = Vector3.zero; d.EmissionDirection = Enum.NormalId.Top; d.Drag = 0; d.LockedToPart = false; d.ZOffset = 0
		d.Rotation = G.NumberRange.new(0); d.RotSpeed = G.NumberRange.new(0); d.LightInfluence = 1
	elseif cls == "Beam" then
		d.Enabled = true; d.Width0 = 1; d.Width1 = 1; d.Color = G.ColorSequence.new(WHITE); d.Transparency = G.NumberSequence.new(0.5); d.LightEmission = 0; d.FaceCamera = false; d.Segments = 10
	elseif cls == "Decal" or cls == "Texture" then
		d.Face = Enum.NormalId.Front; d.Texture = ""; d.Transparency = 0; d.Color3 = WHITE
	elseif cls == "Model" or cls == "Workspace" then
		d.PrimaryPart = nil; d.WorldPivot = CFrame.new(); d.ModelStreamingMode = Enum.ModelStreamingMode.Default
	elseif cls == "Highlight" then
		d.Enabled = true; d.FillColor = Color3.new(1, 0, 0); d.FillTransparency = 0.5; d.OutlineColor = WHITE; d.OutlineTransparency = 0
	elseif cls == "Weld" or cls == "ManualWeld" or cls == "Motor6D" then
		d.C0 = CFrame.new(); d.C1 = CFrame.new(); d.Enabled = true
	elseif cls == "WeldConstraint" then
		d.Enabled = true
	elseif isA(cls, "ValueBase") then
		d.Value = nil
	end
	d.Archivable = true
	return d
end

local Inst = {}
local Meta = {}
local nextId = 50000000
R.created = {} -- every instance made by Instance.new (sim dump)
R.byId = {}

local SIG = { ChildAdded = 1, ChildRemoved = 1, DescendantAdded = 1, DescendantRemoving = 1, AncestryChanged = 1, Destroying = 1, Changed = 1, AttributeChanged = 1, Triggered = 1, TriggerEnded = 1, PromptShown = 1, PromptHidden = 1, Touched = 1, TouchEnded = 1, Activated = 1, MouseButton1Click = 1, Ended = 1, Played = 1, Completed = 1, MouseClick = 1, PromptButtonHoldBegan = 1, PromptButtonHoldEnded = 1, OnServerEvent = 1, OnClientEvent = 1, Event = 1, PlayerRemoving = 1, PlayerAdded = 1, CharacterAdded = 1, Died = 1, Heartbeat = 1 }

local function sig(self, k)
	local s = rawget(self, "_sig")
	local v = s[k]
	if not v then
		v = Signal.new()
		s[k] = v
	end
	return v
end

local function fireUp(node, name, inst)
	local p = rawget(node, "_p").Parent
	while p do
		local s = rawget(p, "_sig")[name]
		if s then
			s:Fire(inst)
		end
		p = rawget(p, "_p").Parent
	end
end

Meta.__index = function(self, k)
	local m = Inst[k]
	if m then
		return m
	end
	local p = rawget(self, "_p")
	local v = p[k]
	if v ~= nil then
		return v
	end
	if SIG[k] then
		return sig(self, k)
	end
	local cls = p.ClassName
	if k == "Position" and p.CFrame then
		return p.CFrame.Position
	elseif k == "Orientation" and p.CFrame then
		local rx, ry, rz = p.CFrame:ToOrientation()
		return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
	elseif k == "Rotation" and p.CFrame and isA(cls, "BasePart") then
		local rx, ry, rz = p.CFrame:ToEulerAnglesXYZ()
		return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
	elseif k == "WorldCFrame" and cls == "Attachment" then
		local par = p.Parent
		return (par and par.CFrame or CFrame.new()) * p.CFrame
	elseif k == "WorldPosition" and cls == "Attachment" then
		local par = p.Parent
		return ((par and par.CFrame or CFrame.new()) * p.CFrame).Position
	elseif k == "AbsoluteSize" then
		return Vector2.new(100, 100)
	elseif k == "Value" then
		return nil
	end
	-- child access by name (Roblox: inst.ChildName)
	for _, c in rawget(self, "_ch") do
		if rawget(c, "_p").Name == k then
			return c
		end
	end
	if k == "Parent" or k == "PrimaryPart" or k == "Adornee" or k == "Value" or k == "Part0" or k == "Part1" or k == "Character" then
		return nil
	end
	error(string.format("%s is not a valid member of %s \"%s\"", tostring(k), cls, tostring(p.Name)), 2)
end

Meta.__newindex = function(self, k, v)
	local p = rawget(self, "_p")
	if p._destroyed and k == "Parent" and v ~= nil then
		error("The Parent property of " .. tostring(p.Name) .. " is locked, current parent: NULL, new parent " .. tostring(v.Name), 2)
	end
	if k == "Parent" then
		local old = p.Parent
		if old == v then
			return
		end
		if v == self then
			error("Attempt to set parent of " .. p.Name .. " to itself", 2)
		end
		if old then
			local ch = rawget(old, "_ch")
			for i, c in ch do
				if c == self then
					table.remove(ch, i)
					break
				end
			end
			local s = rawget(old, "_sig").ChildRemoved
			if s then
				s:Fire(self)
			end
		end
		p.Parent = v
		if v then
			table.insert(rawget(v, "_ch"), self)
			local s = rawget(v, "_sig").ChildAdded
			if s then
				s:Fire(self)
			end
			fireUp(self, "DescendantAdded", self)
		end
		local s = rawget(self, "_sig").AncestryChanged
		if s then
			s:Fire(self, v)
		end
		return
	end
	if k == "Position" and p.CFrame then
		local cf = p.CFrame
		p.CFrame = cf - cf.Position + v
		k = "CFrame"
	elseif k == "Orientation" and p.CFrame then
		p.CFrame = CFrame.new(p.CFrame.Position) * CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
		k = "CFrame"
	else
		local old = p[k]
		p[k] = v
		if old == v then
			return
		end
	end
	local ps = rawget(self, "_psig")[k]
	if ps then
		ps:Fire()
	end
	local ch = rawget(self, "_sig").Changed
	if ch then
		ch:Fire(k)
	end
end
Meta.__tostring = function(self)
	return rawget(self, "_p").Name
end

local function newInst(cls, id)
	local p = defaults(cls)
	p.ClassName = cls
	p.Name = cls
	local o = setmetatable({ _p = p, _ch = {}, _attr = {}, _tags = {}, _sig = {}, _psig = {}, _asig = {} }, Meta)
	if id then
		p._id = id
	else
		nextId += 1
		p._id = nextId
		table.insert(R.created, o)
	end
	R.byId[p._id] = o
	return o
end
R.newInst = newInst

function Inst:IsA(c)
	return isA(rawget(self, "_p").ClassName, c)
end
function Inst:GetChildren()
	return table.clone(rawget(self, "_ch"))
end
function Inst:GetDescendants()
	local t = {}
	local function w(n)
		for _, c in rawget(n, "_ch") do
			table.insert(t, c)
			w(c)
		end
	end
	w(self)
	return t
end
function Inst:FindFirstChild(name, rec)
	for _, c in rawget(self, "_ch") do
		if rawget(c, "_p").Name == name then
			return c
		end
	end
	if rec then
		for _, c in rawget(self, "_ch") do
			local r = c:FindFirstChild(name, true)
			if r then
				return r
			end
		end
	end
	return nil
end
function Inst:FindFirstChildOfClass(cls)
	for _, c in rawget(self, "_ch") do
		if rawget(c, "_p").ClassName == cls then
			return c
		end
	end
	return nil
end
function Inst:FindFirstChildWhichIsA(cls, rec)
	for _, c in rawget(self, "_ch") do
		if c:IsA(cls) then
			return c
		end
	end
	if rec then
		for _, c in rawget(self, "_ch") do
			local r = c:FindFirstChildWhichIsA(cls, true)
			if r then
				return r
			end
		end
	end
	return nil
end
function Inst:FindFirstAncestor(name)
	local p = rawget(self, "_p").Parent
	while p do
		if p.Name == name then
			return p
		end
		p = rawget(p, "_p").Parent
	end
	return nil
end
function Inst:FindFirstAncestorOfClass(cls)
	local p = rawget(self, "_p").Parent
	while p do
		if rawget(p, "_p").ClassName == cls then
			return p
		end
		p = rawget(p, "_p").Parent
	end
	return nil
end
function Inst:FindFirstAncestorWhichIsA(cls)
	local p = rawget(self, "_p").Parent
	while p do
		if p:IsA(cls) then
			return p
		end
		p = rawget(p, "_p").Parent
	end
	return nil
end
function Inst:IsDescendantOf(a)
	local p = rawget(self, "_p").Parent
	while p do
		if p == a then
			return true
		end
		p = rawget(p, "_p").Parent
	end
	return false
end
function Inst:IsAncestorOf(d)
	return d:IsDescendantOf(self)
end
function Inst:WaitForChild(n, t)
	local c = self:FindFirstChild(n)
	if not c and t == nil then
		print("[WaitForChild] infinite yield possible on " .. self:GetFullName() .. ":" .. n)
	end
	return c
end
function Inst:GetFullName()
	local t = {}
	local n = self
	while n and rawget(n, "_p").ClassName ~= "DataModel" do
		table.insert(t, 1, rawget(n, "_p").Name)
		n = rawget(n, "_p").Parent
	end
	return table.concat(t, ".")
end
function Inst:GetAttribute(k)
	return rawget(self, "_attr")[k]
end
function Inst:GetAttributes()
	return table.clone(rawget(self, "_attr"))
end
function Inst:SetAttribute(k, v)
	local a = rawget(self, "_attr")
	if a[k] == v then
		return
	end
	a[k] = v
	local s = rawget(self, "_asig")[k]
	if s then
		s:Fire()
	end
	local s2 = rawget(self, "_sig").AttributeChanged
	if s2 then
		s2:Fire(k)
	end
end
function Inst:GetAttributeChangedSignal(k)
	local s = rawget(self, "_asig")
	if not s[k] then
		s[k] = Signal.new()
	end
	return s[k]
end
function Inst:GetPropertyChangedSignal(k)
	local s = rawget(self, "_psig")
	if not s[k] then
		s[k] = Signal.new()
	end
	return s[k]
end
function Inst:GetTags()
	local t = {}
	for k in rawget(self, "_tags") do
		table.insert(t, k)
	end
	return t
end
function Inst:HasTag(t)
	return rawget(self, "_tags")[t] == true
end
function Inst:AddTag(t)
	rawget(self, "_tags")[t] = true
end
function Inst:RemoveTag(t)
	rawget(self, "_tags")[t] = nil
end
function Inst:ClearAllChildren()
	for _, c in table.clone(rawget(self, "_ch")) do
		c:Destroy()
	end
end
function Inst:Destroy()
	local s = rawget(self, "_sig").Destroying
	if s then
		s:Fire()
	end
	fireUp(self, "DescendantRemoving", self)
	for _, c in table.clone(rawget(self, "_ch")) do
		c:Destroy()
	end
	self.Parent = nil
	rawget(self, "_p")._destroyed = true
end
function Inst:Remove()
	self.Parent = nil
end
function Inst:Clone()
	local p = rawget(self, "_p")
	local o = newInst(p.ClassName)
	for k, v in p do
		if k ~= "Parent" and k ~= "_id" and k ~= "_destroyed" then
			rawget(o, "_p")[k] = v
		end
	end
	for k, v in rawget(self, "_attr") do
		rawget(o, "_attr")[k] = v
	end
	for k in rawget(self, "_tags") do
		rawget(o, "_tags")[k] = true
	end
	for _, c in rawget(self, "_ch") do
		c:Clone().Parent = o
	end
	return o
end
-- PVInstance / Model
local function partsOf(m)
	local t = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(t, d)
		end
	end
	return t
end
function Inst:GetBoundingBox()
	local p = rawget(self, "_p")
	local base = if p.PrimaryPart then p.PrimaryPart.CFrame else p.WorldPivot or CFrame.new()
	local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local any = false
	for _, b in partsOf(self) do
		any = true
		local cf, s = b.CFrame, b.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = cf * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz)
					local l = base:PointToObjectSpace(w)
					mn = mn:Min(l)
					mx = mx:Max(l)
				end
			end
		end
	end
	if not any then
		return base, Vector3.zero
	end
	return base * CFrame.new((mn + mx) / 2), mx - mn
end
function Inst:GetExtentsSize()
	local _, s = self:GetBoundingBox()
	return s
end
function Inst:GetPivot()
	local p = rawget(self, "_p")
	if isA(p.ClassName, "BasePart") then
		return p.CFrame
	end
	if p.PrimaryPart then
		return p.PrimaryPart.CFrame
	end
	local parts = partsOf(self)
	if #parts == 0 then
		return p.WorldPivot or CFrame.new()
	end
	local cf = self:GetBoundingBox()
	return cf
end
function Inst:PivotTo(cf)
	local p = rawget(self, "_p")
	if isA(p.ClassName, "BasePart") then
		self.CFrame = cf
		return
	end
	local cur = self:GetPivot()
	local d = cf * cur:Inverse()
	for _, b in partsOf(self) do
		b.CFrame = d * b.CFrame
	end
	p.WorldPivot = cf
end
-- sound / particles / tweens
function Inst:Play()
	self.Playing = true
end
function Inst:Stop()
	self.Playing = false
end
function Inst:Pause()
	self.Playing = false
end
function Inst:Resume()
	self.Playing = true
end
function Inst:Emit(n)
	rawget(self, "_p")._emitted = (rawget(self, "_p")._emitted or 0) + (n or 1)
end
function Inst:Clear() end
function Inst:InputHoldBegin() end
function Inst:InputHoldEnd() end
function Inst:GetTouchingParts()
	return {}
end
function Inst:GetConnectedParts()
	return {}
end
function Inst:BreakJoints() end

local Instance = {}
function Instance.new(cls, parent)
	local o = newInst(cls)
	if parent then
		o.Parent = parent
	end
	return o
end
function Instance.fromExisting(o)
	return o:Clone()
end
R.Instance = Instance

-- services ---------------------------------------------------------------------------------------------
local game = newInst("DataModel", 1)
rawget(game, "_p").Name = "Game"
local workspace = newInst("Workspace", 2)
rawget(workspace, "_p").Name = "Workspace"
workspace.Parent = game
local cam = newInst("Camera", 3)
rawget(cam, "_p").Name = "Camera"
rawget(cam, "_p").CFrame = CFrame.new(0, 10, 0)
rawget(cam, "_p").FieldOfView = 70
rawget(cam, "_p").ViewportSize = Vector2.new(1280, 720)
cam.Parent = workspace
rawget(workspace, "_p").CurrentCamera = cam
rawget(workspace, "_p").StreamingEnabled = true
function workspace:Raycast()
	return nil
end
function workspace:GetPartBoundsInBox()
	return {}
end
function workspace:GetPartBoundsInRadius()
	return {}
end
function workspace:GetServerTimeNow()
	return os.clock()
end

local services = {}
local function svc(name, cls)
	local s = newInst(cls or name, nil)
	rawget(s, "_p").Name = name
	s.Parent = game
	services[name] = s
	return s
end
svc("Workspace")
services.Workspace = workspace
local Players = svc("Players")
local Lighting = svc("Lighting")
rawget(Lighting, "_p").ClockTime = 14
rawget(Lighting, "_p").Brightness = 2
function Lighting:GetMinutesAfterMidnight()
	return self.ClockTime * 60
end
local RS = svc("ReplicatedStorage")
local RunService = svc("RunService", "Folder")
for _, n in { "Heartbeat", "RenderStepped", "Stepped", "PreRender", "PostSimulation", "PreSimulation" } do
	rawget(RunService, "_p")[n] = Signal.new()
end
function RunService:IsClient()
	return true
end
function RunService:IsServer()
	return false
end
function RunService:IsStudio()
	return false
end
function RunService:IsRunning()
	return true
end
function RunService:BindToRenderStep() end
function RunService:UnbindFromRenderStep() end
local CS = svc("CollectionService", "Folder")
local tagSig = {}
function CS:GetTagged(tag)
	local t = {}
	for _, d in game:GetDescendants() do
		if rawget(d, "_tags")[tag] then
			table.insert(t, d)
		end
	end
	return t
end
function CS:HasTag(i, t)
	return i:HasTag(t)
end
function CS:AddTag(i, t)
	i:AddTag(t)
end
function CS:RemoveTag(i, t)
	i:RemoveTag(t)
end
function CS:GetTags(i)
	return i:GetTags()
end
function CS:GetInstanceAddedSignal(t)
	tagSig[t] = tagSig[t] or Signal.new()
	return tagSig[t]
end
function CS:GetInstanceRemovedSignal(t)
	return Signal.new()
end
local TS = svc("TweenService", "Folder")
R.tweens = {}
function TS:Create(inst, info, goal)
	local tw = { Instance = inst, TweenInfo = info, PlaybackState = Enum.PlaybackState.Begin, Completed = Signal.new() }
	function tw.Play(self2)
		for k, v in goal do
			inst[k] = v
		end
		tw.PlaybackState = Enum.PlaybackState.Completed
		table.insert(R.tweens, tw)
		tw.Completed:Fire(Enum.PlaybackState.Completed)
	end
	function tw.Cancel() end
	function tw.Pause() end
	function tw.Destroy() end
	return tw
end
function TS:GetValue(a)
	return a
end
local SoundService = svc("SoundService", "Folder")
local PPS = svc("ProximityPromptService", "Folder")
rawget(PPS, "_p").PromptTriggered = Signal.new()
rawget(PPS, "_p").PromptShown = Signal.new()
rawget(PPS, "_p").PromptHidden = Signal.new()
rawget(PPS, "_p").Enabled = true
local UIS = svc("UserInputService", "Folder")
rawget(UIS, "_p").TouchEnabled = false
rawget(UIS, "_p").KeyboardEnabled = true
rawget(UIS, "_p").InputBegan = Signal.new()
rawget(UIS, "_p").InputEnded = Signal.new()
local HttpService = svc("HttpService", "Folder")
function HttpService:GenerateGUID()
	nextId += 1
	return "guid-" .. nextId
end
function HttpService:JSONEncode(t)
	return R.json(t)
end
local Debris = svc("Debris", "Folder")
function Debris:AddItem(i, t) end
local StarterGui = svc("StarterGui", "Folder")
function StarterGui:SetCore() end

-- local player + character
local player = newInst("Player")
rawget(player, "_p").Name = "Tester"
rawget(player, "_p").UserId = 1
player.Parent = Players
rawget(Players, "_p").LocalPlayer = player
local ps = newInst("PlayerScripts")
rawget(ps, "_p").Name = "PlayerScripts"
ps.Parent = player
local pg = newInst("Folder")
rawget(pg, "_p").Name = "PlayerGui"
pg.Parent = player
local char = newInst("Model")
rawget(char, "_p").Name = "Tester"
local hrp = newInst("Part")
rawget(hrp, "_p").Name = "HumanoidRootPart"
rawget(hrp, "_p").Size = Vector3.new(2, 2, 1)
hrp.Parent = char
local hum = newInst("Humanoid")
rawget(hum, "_p").Health = 100
rawget(hum, "_p").SeatPart = nil
hum.Parent = char
rawget(char, "_p").PrimaryPart = hrp
char.Parent = workspace
rawget(player, "_p").Character = char
rawget(player, "_p").CharacterAdded = Signal.new()
rawget(player, "_p").CharacterRemoving = Signal.new()
function player:GetMouse()
	return { Hit = CFrame.new(), Target = nil }
end
function Players:GetPlayers()
	return { player }
end
function Players:GetPlayerFromCharacter(c)
	return if c == char then player else nil
end
rawget(Players, "_p").PlayerAdded = Signal.new()
rawget(Players, "_p").PlayerRemoving = Signal.new()

function game:GetService(name)
	local s = services[name]
	if not s then
		s = svc(name, "Folder")
	end
	return s
end
function game:FindService(name)
	return services[name]
end
function game:IsLoaded()
	return true
end
rawget(game, "_p").Loaded = Signal.new()
rawget(game, "_p").PlaceId = 0
rawget(game, "_p").JobId = "sim"
rawget(game, "_p").Workspace = workspace

R.game, R.workspace, R.player, R.character, R.hrp, R.camera, R.services = game, workspace, player, char, hrp, cam, services
R.PlayerScripts = ps

-- task -------------------------------------------------------------------------------------------------
R.delayed = {}
R.clock = 0
local task = {}
function task.wait(t)
	R.clock += (t or 0.016)
	return t or 0.016
end
function task.spawn(f, ...)
	if type(f) == "thread" then
		coroutine.resume(f, ...)
		return f
	end
	local co = coroutine.create(f)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		print("[task.spawn error] " .. tostring(err) .. "\n" .. debug.traceback(co))
	end
	return co
end
function task.defer(f, ...)
	return task.spawn(f, ...)
end
function task.delay(t, f, ...)
	local args = table.pack(...)
	local rec = { t = R.clock + (t or 0), f = f, args = args }
	table.insert(R.delayed, rec)
	return rec
end
function task.cancel(x)
	for i, d in R.delayed do
		if d == x then
			table.remove(R.delayed, i)
			return
		end
	end
end
function task.synchronize() end
function task.desynchronize() end
-- run delayed callbacks up to time t
function R.advance(dt)
	R.clock += dt
	local due = {}
	for i = #R.delayed, 1, -1 do
		if R.delayed[i].t <= R.clock then
			table.insert(due, table.remove(R.delayed, i))
		end
	end
	for _, d in due do
		task.spawn(d.f, table.unpack(d.args, 1, d.args.n))
	end
	RunService.Heartbeat:Fire(dt)
	RunService.RenderStepped:Fire(dt)
end
R.task = task

-- fixture loading ----------------------------------------------------------------------------------------
local function mk(node, parent)
	local o = newInst(node.cls, node.id)
	local p = rawget(o, "_p")
	p.Name = node.name
	if node.cf then
		local c = node.cf
		p.CFrame = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
	end
	if node.size then
		p.Size = Vector3.new(node.size[1], node.size[2], node.size[3])
	end
	if node.col then
		p.Color = Color3.new(node.col[1], node.col[2], node.col[3])
	end
	if node.mat then
		p.Material = Enum.Material[node.mat] or Enum.Material.Plastic
	end
	if node.t then
		p.Transparency = node.t
	end
	if node.rf then
		p.Reflectance = node.rf
	end
	if node.shape then
		p.Shape = Enum.PartType[node.shape]
	end
	if node.cc ~= nil then
		p.CanCollide = node.cc
	end
	if node.anch ~= nil then
		p.Anchored = node.anch
	elseif isA(node.cls, "BasePart") then
		p.Anchored = true
	end
	if node.meshType then
		p.MeshType = Enum.MeshType[node.meshType]
		p.Scale = Vector3.new(node.scale[1], node.scale[2], node.scale[3])
	end
	if node.text then
		p.Text = node.text
	end
	if node.on ~= nil then
		p.Enabled = node.on
	end
	if node.attrs then
		for k, v in node.attrs do
			rawget(o, "_attr")[k] = v
		end
	end
	if node.tags then
		for _, t in node.tags do
			rawget(o, "_tags")[t] = true
		end
	end
	if node.kids then
		for _, k in node.kids do
			mk(k, o)
		end
	end
	if parent then
		rawset(p, "Parent", parent)
		table.insert(rawget(parent, "_ch"), o)
	end
	return o
end
-- fx = { chain = { {cls,name,id}... DataModel, Workspace, Gwangalli, ... }, tree = {...} }
function R.loadFixture(fx)
	local parent = game
	for _, c in fx.chain do
		if c.cls == "DataModel" then
			parent = game
		elseif c.cls == "Workspace" then
			parent = workspace
		else
			local ex = parent:FindFirstChild(c.name)
			if not ex then
				ex = newInst(c.cls, c.id)
				rawget(ex, "_p").Name = c.name
				rawset(rawget(ex, "_p"), "Parent", parent)
				table.insert(rawget(parent, "_ch"), ex)
			end
			parent = ex
		end
	end
	return mk(fx.tree, parent)
end

-- JSON ---------------------------------------------------------------------------------------------------
local function jstr(s)
	return '"' .. string.gsub(s, '[%c"\\]', function(c)
		if c == '"' then
			return '\\"'
		elseif c == "\\" then
			return "\\\\"
		elseif c == "\n" then
			return "\\n"
		elseif c == "\t" then
			return "\\t"
		end
		return string.format("\\u%04x", string.byte(c))
	end) .. '"'
end
function R.json(v)
	local t = type(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "0"
		end
		if math.floor(v) == v and math.abs(v) < 1e15 then
			return string.format("%d", v)
		end
		return string.format("%.8g", v)
	elseif t == "string" then
		return jstr(v)
	elseif t == "table" then
		if #v > 0 or next(v) == nil then
			local o = {}
			for i, x in v do
				o[i] = R.json(x)
			end
			return "[" .. table.concat(o, ",") .. "]"
		end
		local o = {}
		for k, x in v do
			table.insert(o, jstr(tostring(k)) .. ":" .. R.json(x))
		end
		return "{" .. table.concat(o, ",") .. "}"
	end
	return jstr(tostring(v))
end

R.env = {
	game = game, workspace = workspace, Workspace = workspace, Instance = Instance, task = task, Enum = Enum,
	CFrame = CFrame, Vector3 = Vector3, Color3 = Color3, UDim2 = UDim2, UDim = UDim, Vector2 = Vector2,
	NumberRange = G.NumberRange, NumberSequence = G.NumberSequence, NumberSequenceKeypoint = G.NumberSequenceKeypoint,
	ColorSequence = G.ColorSequence, ColorSequenceKeypoint = G.ColorSequenceKeypoint, TweenInfo = G.TweenInfo,
	BrickColor = G.BrickColor, Ray = G.Ray, RaycastParams = G.RaycastParams, OverlapParams = G.OverlapParams, Random = G.Random,
	Font = G.Font, Region3 = G.Region3, Rect = G.Rect, PhysicalProperties = G.PhysicalProperties, DateTime = G.DateTime,
	typeof = G.typeof, tick = function() return os.clock() end, time = function() return R.clock end,
	warn = function(...) print("[warn]", ...) end,
}
return R
