-- GwangalliGoals (LocalScript; owner: goals): the "다음 목표" card (right side, under 내 차 / 알바). Shows
-- the goal the server (GwangalliGameplay.Goals) ranks first — the active 수배, the next car / home,
-- the closest 알바 level-up, the NPC closest to the next 호감도 tier, the next crime unlock, the next
-- police rank — with a progress bar, cycles through the top three every few seconds and opens the
-- full list on tap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local folder = ReplicatedStorage:WaitForChild("GwangalliGoals", 60)
if not folder then
	return
end
local remote = folder:WaitForChild("Goals", 30) :: RemoteEvent
if not remote then
	return
end

local NAVY = Color3.fromRGB(16, 22, 44)
local INK = Color3.fromRGB(236, 240, 255)
local SUB = Color3.fromRGB(160, 172, 205)

local function new(cls: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(cls)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

local gui = new("ScreenGui", { Name = "GwangalliGoals", ResetOnSpawn = false, DisplayOrder = 12 }, player:WaitForChild("PlayerGui"))
local card = new("TextButton", { Name = "Goal", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 264), Size = UDim2.fromOffset(276, 58), BackgroundColor3 = NAVY, BackgroundTransparency = 0.12, Text = "", AutoButtonColor = false, Visible = false }, gui)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
new("UIStroke", { Color = Color3.fromRGB(255, 210, 90), Transparency = 0.6 }, card)
local cap = new("TextLabel", { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 14), BackgroundTransparency = 1, Text = "🎯 다음 목표", TextColor3 = Color3.fromRGB(255, 210, 90), Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left }, card)
local _ = cap
local text = new("TextLabel", { Position = UDim2.fromOffset(10, 18), Size = UDim2.new(1, -20, 0, 20), BackgroundTransparency = 1, Text = "", TextColor3 = INK, Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, card)
local sub = new("TextLabel", { Position = UDim2.fromOffset(10, 37), Size = UDim2.new(1, -20, 0, 12), BackgroundTransparency = 1, Text = "", TextColor3 = SUB, Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, card)
local barBg = new("Frame", { Position = UDim2.new(0, 10, 1, -6), Size = UDim2.new(1, -20, 0, 3), BackgroundColor3 = Color3.fromRGB(44, 52, 86), BorderSizePixel = 0 }, card)
local bar = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 210, 90), BorderSizePixel = 0 }, barBg)

local list = new("Frame", { Name = "All", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 326), Size = UDim2.fromOffset(276, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = NAVY, BackgroundTransparency = 0.08, Visible = false }, gui)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, list)
new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, list)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)

local goals: { any } = {}
local idx = 1

local function show()
	local g = goals[idx]
	card.Visible = g ~= nil
	if not g then
		return
	end
	text.Text = (g.icon or "🎯") .. " " .. (g.text or "")
	sub.Text = g.sub or ""
	bar.Size = UDim2.fromScale(math.clamp(g.pct or 0, 0, 1), 1)
end

local function fillList()
	for _, c in list:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for i, g in goals do
		new("TextLabel", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Text = string.format("%s %s\n<font color='#a0acd0'>%s</font>", g.icon or "🎯", g.text or "", g.sub or (if (g.pct or 0) > 0 then math.floor((g.pct or 0) * 100) .. "%" else "")), RichText = true, TextColor3 = INK, Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, LayoutOrder = i }, list)
	end
end

card.Activated:Connect(function()
	list.Visible = not list.Visible
	if list.Visible then
		fillList()
	end
end)

remote.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" or type(msg.goals) ~= "table" then
		return
	end
	local firstId = goals[idx] and goals[idx].id
	goals = msg.goals
	idx = 1
	for i, g in goals do
		if g.id == firstId and i <= 3 then
			idx = i
		end
	end
	show()
	if list.Visible then
		fillList()
	end
end)

task.spawn(function()
	remote:FireServer("refresh")
	while true do
		task.wait(7)
		if #goals > 1 and not list.Visible then
			-- urgent goals (수배 / 유치장) stay put
			if not (goals[1] and (goals[1].id == "wanted" or goals[1].id == "jail")) then
				idx = (idx % math.min(3, #goals)) + 1
			else
				idx = 1
			end
			show()
		end
	end
end)
