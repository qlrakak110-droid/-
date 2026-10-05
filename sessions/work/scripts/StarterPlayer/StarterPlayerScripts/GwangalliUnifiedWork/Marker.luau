--!nocheck
-- GwangalliUnifiedWork/Marker: the world marker over the next station of the 알바 hint ("▼ 얼음통 · 6m").
-- A client-only anchored, invisible, non-colliding Part in the Workspace with an AlwaysOnTop BillboardGui
-- (the emulator renders BillboardGuis only in the Workspace / directly under PlayerGui). The distance
-- text is refreshed 4x a second; the marker bobs a little so it reads as "go here".

local Players = game:GetService("Players")

local Marker = {}
Marker.__index = Marker

function Marker.new(): any
	local self = setmetatable({}, Marker)
	local part = Instance.new("Part")
	part.Name = "GwangalliWorkMarker"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CastShadow = false
	local bb = Instance.new("BillboardGui")
	bb.Name = "WorkMarker"
	bb.Size = UDim2.fromOffset(170, 58)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 2000
	bb.Enabled = false
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.new(1, 0, 0, 30)
	label.BackgroundColor3 = Color3.fromRGB(255, 194, 71)
	label.BackgroundTransparency = 0.05
	label.TextColor3 = Color3.fromRGB(40, 26, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Text = ""
	label.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = label
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Size = UDim2.new(1, 0, 0, 26)
	arrow.Position = UDim2.fromOffset(0, 30)
	arrow.BackgroundTransparency = 1
	arrow.TextColor3 = Color3.fromRGB(255, 194, 71)
	arrow.Font = Enum.Font.GothamBold
	arrow.TextSize = 24
	arrow.Text = "▼"
	arrow.Parent = bb
	bb.Parent = part
	self.part = part
	self.bb = bb
	self.label = label
	self.pos = nil
	self.text = ""
	task.spawn(function()
		local t = 0
		while true do
			task.wait(0.25)
			t += 0.25
			self:refresh(t)
		end
	end)
	return self
end

function Marker:set(pos: Vector3?, text: string?)
	self.pos = pos
	self.text = text or ""
	if not pos then
		self.bb.Enabled = false
		return
	end
	if not self.part.Parent then
		self.part.Parent = workspace
	end
	self:refresh(0)
end

function Marker:refresh(t: number)
	local pos = self.pos
	if not pos then
		self.bb.Enabled = false
		return
	end
	local char = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local dist = root and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude or 0
	-- very close: the action buttons are on screen already
	self.bb.Enabled = dist > 3.5
	self.part.CFrame = CFrame.new(pos + Vector3.new(0, 4.2 + math.sin(t * 3) * 0.25, 0))
	local m = dist * 0.28 -- studs → metres (map scale)
	self.label.Text = string.format("%s · %s", self.text, if m >= 1000 then string.format("%.1fkm", m / 1000) else string.format("%dm", math.floor(m + 0.5)))
end

return Marker
