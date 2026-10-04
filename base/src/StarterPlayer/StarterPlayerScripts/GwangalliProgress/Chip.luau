-- GwangalliProgress/Chip: the 인생 레벨 chip next to the phone's money chip (below it when the top row is
-- too narrow): a gold progress ring with the level, three dots for today's goals and a badge when
-- something new waits in the sheet. 56 px touch target; tap -> the progress sheet. Reads the server's
-- player attributes (LifeLevel / LifeLevelProgress / GoalsDone / GoalsTotal): no polling.

local Chip = {}

local C: any = nil
local K: any = nil
local P: any = nil

local button: TextButton
local body: Frame
local bodyScale: UIScale
local bump: UIScale
local ring: any
local dots: { Frame } = {}
local badge: Frame
local stroke: UIStroke
local unseen = 0
local lastLevel = 0
local chipConn: RBXScriptConnection? = nil

local function attr(name: string, default: number): number
	local v = C.player:GetAttribute(name)
	return if type(v) == "number" then v else default
end

local function refresh()
	local lv = attr(P.Attr.Level, 0)
	local lp = attr(P.Attr.LevelProgress, 0)
	if lv <= 0 then
		ring.label.Text = "…"
		ring.set(0)
	else
		ring.label.Text = tostring(lv)
		ring.set(lp)
	end
	local done = attr(P.Attr.GoalsDone, 0)
	local total = attr(P.Attr.GoalsTotal, 0)
	for i, d in dots do
		d.Visible = i <= math.max(total, 3)
		local on = i <= done
		d.BackgroundColor3 = if on then K.Color.green else K.Color.card3
		d.BackgroundTransparency = if on then 0 else 0.15
	end
	badge.Visible = unseen > 0
	if lv > lastLevel and lastLevel > 0 then
		Chip.bump(true)
	end
	lastLevel = lv
end

local function place()
	local g = C.geometry()
	local hit = math.max(56, g.level.h)
	button.Size = UDim2.fromOffset(math.max(44, g.level.w), hit)
	button.Position = UDim2.fromOffset(g.level.x + g.level.w / 2, g.level.y + g.level.h / 2)
	bodyScale.Scale = g.s
	body.Size = UDim2.fromOffset(math.floor(g.level.w / g.s), math.floor(g.level.h / g.s))
end

-- small bounce (money landed / level up)
function Chip.bump(big: boolean?)
	if K.reduced() then
		return
	end
	bump.Scale = if big then 1.18 else 1.08
	K.tween(bump, if big then 0.42 else 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	if big then
		K.pulse(stroke, true)
		task.delay(2.2, function()
			K.pulse(stroke, false)
			stroke.Transparency = 0.55
		end)
	end
end

function Chip.markUnseen(n: number?)
	unseen += n or 1
	badge.Visible = unseen > 0
end

function Chip.clearUnseen()
	unseen = 0
	badge.Visible = false
end

local function watchMoneyChip()
	if chipConn then
		chipConn:Disconnect()
		chipConn = nil
	end
	local chip = C.moneyChip()
	if chip then
		local function moved()
			task.defer(function()
				place()
				C.emit("chipmoved")
			end)
		end
		chipConn = chip:GetPropertyChangedSignal("Size"):Connect(moved)
		chip:GetPropertyChangedSignal("AbsoluteSize"):Connect(moved)
	end
end

function Chip.init(c: any)
	C = c
	K = c.K
	P = c.P
	button = K.make("TextButton", { Name = "LifeLevelChip", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(56, 56), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 3 }, c.hud)
	local holder = K.frame(button, { Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	bump = K.make("UIScale", { Name = "Bump", Scale = 1 }, holder)
	body = K.frame(holder, { Name = "Body", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(56, 44), BackgroundColor3 = K.Color.glass, BackgroundTransparency = K.GLASS_T, ZIndex = 3 })
	bodyScale = K.make("UIScale", { Scale = 1 }, body)
	K.corner(body, K.Radius.md)
	stroke = K.stroke(body, K.Color.gold, 1, 0.55)
	ring = K.Ring(body, { name = "LevelRing", size = 30, thickness = 3, color = K.Color.gold, text = "…" })
	ring.frame.AnchorPoint = Vector2.new(0.5, 0)
	ring.frame.Position = UDim2.new(0.5, 0, 0, 3)
	ring.label.Font = K.Font.heavy
	ring.label.TextSize = 13
	for _, d in ring.frame:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 4
		end
	end
	ring.frame.ZIndex = 4
	local row = K.frame(body, { Name = "Goals", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(30, 6), ZIndex = 4 })
	K.list(row, true, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for i = 1, 3 do
		local d = K.frame(row, { Name = "Dot" .. i, Size = UDim2.fromOffset(6, 6), BackgroundTransparency = 0.15, BackgroundColor3 = K.Color.card3, LayoutOrder = i, ZIndex = 4 })
		K.corner(d, UDim.new(0.5, 0))
		dots[i] = d
	end
	badge = K.frame(body, { Name = "NewBadge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -3, 0, 3), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 0, BackgroundColor3 = K.Color.red, Visible = false, ZIndex = 6 })
	K.corner(badge, UDim.new(0.5, 0))
	K.stroke(badge, K.Color.glass, 1.5, 0)
	K.pressable(button, { scale = 0.94, veil = false })
	button.Activated:Connect(function()
		if C.Panel then
			C.Panel.toggle()
		end
	end)
	for _, a in { P.Attr.Level, P.Attr.LevelProgress, P.Attr.GoalsDone, P.Attr.GoalsTotal } do
		c.player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	c.on("layout", place)
	c.on("phonehud", function()
		task.defer(function()
			watchMoneyChip()
			place()
		end)
	end)
	c.on("ach", function()
		Chip.markUnseen(1)
	end)
	c.on("goal", function()
		Chip.markUnseen(1)
	end)
	watchMoneyChip()
	place()
	refresh()
end

return Chip
