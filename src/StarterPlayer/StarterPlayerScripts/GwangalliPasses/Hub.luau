-- GwangalliPasses/Hub (client): the "👑 VIP 패스" app shell (own ScreenGui GwangalliPassesApp).
--   Hub.open(mode, tab?)   mode "phone": laid exactly over the phone's screen (PhoneHook gives the rect) and
--                          closed with it; "panel": a centred window (the HUD shortcut, /패스)
--   Hub.close() / Hub.isOpen() / Hub.refresh()
--   tabs: 패스 (store) · 차고 · 블랙마켓 · 꾸미기 (each a module with build(ctx, container) / show(state) / hide())
--   helpers for the tabs: Hub.scroll, Hub.section, Hub.chip, Hub.lockCard, Hub.buyButton, Hub.host()
-- Gamepad: the first tab is selected on open, ButtonB closes. Reduced motion: no zoom.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local Hub = {}

local ctx: any
local P: any, K: any, Lines: any
local gui: ScreenGui? = nil
local root: Frame? = nil
local rootScale: UIScale? = nil
local rootCorner: UICorner? = nil
local body: Frame? = nil
local seg: any = nil
local subLabel: TextLabel? = nil
local mode = "panel"
local openState = false
local current: string? = nil
local containers: { [string]: Frame } = {}
local built: { [string]: boolean } = {}
local tabs: { [string]: any } = {}
local lastState: any = nil
local follow: RBXScriptConnection? = nil

local TAB_ORDER = { "pass", "garage", "market", "flex" }
local TAB_LABEL = { pass = "패스", garage = "차고", market = "블랙마켓", flex = "꾸미기" }
local TAB_PASS = { garage = "PremiumGarage", market = "Convenience", flex = "Flex" }
local GOLD = Color3.fromRGB(255, 194, 71)
local MAGENTA = Color3.fromRGB(255, 79, 163)

function Hub.host(): Instance?
	return root
end

function Hub.state(): any
	return lastState
end

---------------------------------------------------------------------------------------------------
-- shared building blocks
---------------------------------------------------------------------------------------------------
function Hub.scroll(container: Instance): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Name = "Scroll"
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.Size = UDim2.fromScale(1, 1)
	s.ScrollBarThickness = 3
	s.ScrollBarImageColor3 = K.Color.sub
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.Selectable = false
	s.Parent = container
	K.list(s, false, 10)
	K.pad(s, 10, 10, 6, 18)
	return s
end

function Hub.section(parent: Instance, text: string, order: number): TextLabel
	return K.text(parent, { Name = "Section", Text = text, Font = K.Font.bold, TextSize = K.Type.caption, TextColor3 = K.Color.faint, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order })
end

function Hub.chip(parent: Instance, text: string, color: Color3, props: any?): TextLabel
	local l = K.text(parent, { Text = text, Font = K.Font.bold, TextSize = K.Type.micro, TextColor3 = color, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), BackgroundTransparency = 0.82, BackgroundColor3 = color, TextXAlignment = Enum.TextXAlignment.Center })
	K.corner(l, UDim.new(0.5, 0))
	K.pad(l, 8, 8, 0, 0)
	for k, v in props or {} do
		(l :: any)[k] = v
	end
	return l
end

-- the gold buy button of a pass (price from Roblox; Id 0 = 판매 준비 중)
function Hub.buyButton(parent: Instance, key: string, props: any): TextButton
	local id = P.idOf(key)
	local owned = P.has(Players.LocalPlayer, key)
	local b = K.Button(parent, {
		name = "Buy_" .. key,
		text = if owned then "✓ " .. Lines.t("owned") elseif id > 0 then Lines.t("buy_plain") else Lines.t("not_ready"),
		style = if owned then "tonal" elseif id > 0 then "gold" else "secondary",
		size = props.size or UDim2.new(1, 0, 0, 44),
		position = props.position,
		anchor = props.anchor,
		order = props.order,
		zIndex = props.zIndex,
		onClick = function()
			ctx.Store.buy(key)
		end,
	})
	if not owned and id > 0 then
		ctx.Store.price(key, function(price: number)
			if b.Parent and price > 0 then
				b.Text = Lines.t("buy", price)
			end
		end)
	end
	return b
end

-- a locked feature: pitch + perks + buy (the feature itself stays visible below it)
function Hub.lockCard(parent: Instance, key: string, order: number, note: string?): Frame
	local d = P.Config.PASSES[key]
	local card = K.Card(parent, { Name = "Lock_" .. key, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ClipsDescendants = true })
	K.list(card, false, 6)
	K.pad(card, 12, 12, 12, 12)
	local band = K.frame(card, { Name = "Band", Size = UDim2.new(1, 0, 0, 4), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 0 })
	K.corner(band, UDim.new(0.5, 0))
	K.gradient(band, { d.C1, d.C2 }, 0)
	local head = K.frame(card, { Name = "Head", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1 })
	local tile = K.frame(head, { Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
	K.corner(tile, UDim.new(0.3, 0))
	K.gradient(tile, { d.C1, d.C2 }, 120)
	K.text(tile, { Text = d.Glyph, TextSize = 22, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	K.text(head, { Text = Lines.t("locked", d.Title), Font = K.Font.bold, TextSize = K.Type.body, Position = UDim2.fromOffset(50, 0), Size = UDim2.new(1, -50, 0, 20) })
	K.text(head, { Text = note or d.Desc, TextSize = K.Type.micro, TextColor3 = K.Color.sub, TextWrapped = true, Position = UDim2.fromOffset(50, 20), Size = UDim2.new(1, -50, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd })
	for i, perk in d.Perks do
		K.text(card, { Text = perk, TextSize = K.Type.caption, TextColor3 = K.Color.text, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 + i })
	end
	Hub.buyButton(card, key, { order = 20 })
	return card
end

---------------------------------------------------------------------------------------------------
-- shell
---------------------------------------------------------------------------------------------------
local function ownedSummary(): string
	local bits = {}
	for _, key in P.ORDER do
		if P.available(key) and P.has(Players.LocalPlayer, key) then
			table.insert(bits, "✦ " .. P.Config.PASSES[key].Short)
		end
	end
	return if #bits > 0 then table.concat(bits, " · ") else Lines.t("app_sub")
end

local function tabList(): { any }
	local items = {}
	for _, id in TAB_ORDER do
		local key = TAB_PASS[id]
		if not key or P.available(key) then
			table.insert(items, { id = id, label = TAB_LABEL[id] })
		end
	end
	return items
end

local function showTab(id: string)
	if not body then
		return
	end
	if current and current ~= id and tabs[current] and tabs[current].hide then
		pcall(tabs[current].hide)
	end
	current = id
	for tid, c in containers do
		c.Visible = tid == id
	end
	local c = containers[id]
	if not c then
		c = K.frame(body, { Name = "Tab_" .. id, Size = UDim2.fromScale(1, 1), ClipsDescendants = true })
		containers[id] = c
	end
	c.Visible = true
	local t = tabs[id]
	if t and not built[id] then
		built[id] = true
		local ok, err = pcall(t.build, ctx, c)
		if not ok then
			warn("[GwangalliPasses] tab " .. id .. ": " .. tostring(err))
		end
	end
	if t and t.show then
		task.spawn(function()
			local ok, err = pcall(t.show, lastState)
			if not ok then
				warn("[GwangalliPasses] tab " .. id .. " show: " .. tostring(err))
			end
		end)
	end
end

local function build()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "GwangalliPassesApp"
	g.ResetOnSpawn = false
	g.DisplayOrder = 31
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Enabled = false
	g.Parent = pg
	gui = g
	local r = K.frame(g, { Name = "Root", BackgroundTransparency = 0, BackgroundColor3 = K.Color.bg, ClipsDescendants = true, Active = true })
	root = r
	rootCorner = K.corner(r, 24)
	rootScale = Instance.new("UIScale")
	rootScale.Parent = r
	K.gradient(r, { Color3.fromRGB(26, 22, 44), Color3.fromRGB(10, 12, 20), Color3.fromRGB(8, 10, 16) }, 90)
	local glow = K.frame(r, { Name = "Glow", Size = UDim2.new(1, 0, 0, 120), BackgroundTransparency = 0.82, BackgroundColor3 = Color3.new(1, 1, 1) })
	K.gradient(glow, { GOLD, MAGENTA }, 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }))
	local grad = glow:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Rotation = 90
		grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	end
	-- header
	local head = K.frame(r, { Name = "Header", Size = UDim2.new(1, 0, 0, 52), ZIndex = 3 })
	K.Button(head, { name = "Back", text = "‹", style = "glass", size = UDim2.fromOffset(44, 44), position = UDim2.fromOffset(6, 4), textSize = 24, zIndex = 4, onClick = function()
		Hub.close()
	end })
	K.text(head, { Name = "Title", Text = "👑  " .. Lines.t("app_title"), Font = K.Font.heavy, TextSize = K.Type.title2, Position = UDim2.fromOffset(56, 6), Size = UDim2.new(1, -64, 0, 22), ZIndex = 4 })
	subLabel = K.text(head, { Name = "Sub", Text = "", TextSize = K.Type.micro, Font = K.Font.bold, TextColor3 = GOLD, Position = UDim2.fromOffset(56, 28), Size = UDim2.new(1, -64, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
	-- tabs
	local tabHolder = K.frame(r, { Name = "Tabs", Position = UDim2.fromOffset(8, 54), Size = UDim2.new(1, -16, 0, 44), ZIndex = 3 })
	local items = tabList()
	seg = K.Segmented(tabHolder, { items = items, value = items[1].id, height = 34, onChange = function(id: string)
		showTab(id)
	end })
	if seg and seg.frame then
		seg.frame.Size = UDim2.new(1, 0, 0, 40)
	end
	body = K.frame(r, { Name = "Body", Position = UDim2.fromOffset(0, 102), Size = UDim2.new(1, 0, 1, -102), ZIndex = 2 })
end

local function phoneRect(): (Vector2?, Vector2?)
	local sc = ctx.PhoneHook and ctx.PhoneHook.screen()
	if not sc or not sc:IsDescendantOf(game) then
		return nil, nil
	end
	return sc.AbsolutePosition, sc.AbsoluteSize
end

local function layout()
	local r, s = root, rootScale
	if not r or not s or not gui then
		return
	end
	local g = gui :: ScreenGui
	local pg = if mode == "phone" and ctx.PhoneHook then ctx.PhoneHook.phoneGui() else nil
	if pg then
		-- the same coordinate space as the phone (its inset settings)
		g.IgnoreGuiInset = pg.IgnoreGuiInset
		pcall(function()
			(g :: any).ScreenInsets = (pg :: any).ScreenInsets
		end)
	else
		g.IgnoreGuiInset = false
		pcall(function()
			(g :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		end)
	end
	if mode == "phone" then
		local pos, size = phoneRect()
		if not pos or not size or size.X < 50 then
			Hub.close()
			return
		end
		local scale = math.clamp(size.X / 300, 0.6, 2.4)
		s.Scale = scale
		r.AnchorPoint = Vector2.zero
		r.Position = UDim2.fromOffset(pos.X, pos.Y)
		r.Size = UDim2.fromOffset(size.X / scale, size.Y / scale)
		if rootCorner then
			rootCorner.CornerRadius = UDim.new(0, 24)
		end
	else
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		local scale = math.clamp(math.min(vp.X * 0.94 / 360, vp.Y * 0.9 / 560), 0.55, 1.35)
		s.Scale = scale
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Position = UDim2.fromScale(0.5, 0.5)
		r.Size = UDim2.fromOffset(360, math.floor(math.min(660, vp.Y * 0.9 / scale)))
		if rootCorner then
			rootCorner.CornerRadius = UDim.new(0, 22)
		end
	end
end

local function phoneGone(): boolean
	local pg = ctx.PhoneHook and ctx.PhoneHook.phoneGui()
	return not pg or not pg.Enabled or (ctx.PhoneHook.appOpen and ctx.PhoneHook.appOpen())
end

function Hub.refresh()
	task.spawn(function()
		local st = ctx.Net.request("state")
		lastState = st
		if subLabel then
			subLabel.Text = ownedSummary()
		end
		if openState and current and tabs[current] and tabs[current].show then
			pcall(tabs[current].show, st)
		end
	end)
end

local function bindBack(on: boolean)
	if on then
		ContextActionService:BindActionAtPriority("GwPassesBack", function(_, state)
			if state == Enum.UserInputState.Begin then
				Hub.close()
			end
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction("GwPassesBack")
	end
end

function Hub.open(m: string?, tab: string?)
	if not gui then
		build()
	end
	mode = if m == "phone" then "phone" else "panel"
	if mode == "phone" and phoneGone() then
		mode = "panel"
	end
	openState = true
	layout()
	local g = gui :: ScreenGui
	g.Enabled = true
	if subLabel then
		subLabel.Text = ownedSummary()
	end
	local want = tab or current or "pass"
	local okTab = false
	for _, it in tabList() do
		if it.id == want then
			okTab = true
		end
	end
	if not okTab then
		want = "pass"
	end
	if seg then
		seg.set(want, true)
	end
	showTab(want)
	Hub.refresh()
	if root and not K.reduced() then
		local s = rootScale :: UIScale
		local target = s.Scale
		s.Scale = target * 0.94
		TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = target }):Play()
	end
	pcall(K.sound, "open")
	if follow then
		follow:Disconnect()
	end
	follow = RunService.RenderStepped:Connect(function()
		if not openState then
			return
		end
		if mode == "phone" then
			if phoneGone() then
				Hub.close()
				return
			end
			layout()
		end
	end)
	bindBack(true)
	local last = game:GetService("UserInputService"):GetLastInputType()
	if GuiService:IsTenFootInterface() or last == Enum.UserInputType.Gamepad1 then
		local first = seg and seg.frame and seg.frame:FindFirstChildWhichIsA("TextButton")
		if first then
			GuiService.SelectedObject = first
		end
	end
end

function Hub.close()
	if not openState then
		return
	end
	openState = false
	if follow then
		follow:Disconnect()
		follow = nil
	end
	if current and tabs[current] and tabs[current].hide then
		pcall(tabs[current].hide)
	end
	if gui then
		gui.Enabled = false
	end
	bindBack(false)
	if GuiService.SelectedObject and root and GuiService.SelectedObject:IsDescendantOf(root) then
		GuiService.SelectedObject = nil
	end
	pcall(K.sound, "close")
end

function Hub.isOpen(): boolean
	return openState
end

function Hub.mode(): string
	return mode
end

function Hub.start(c: any)
	ctx = c
	P, K, Lines = c.P, c.K, c.P.Lines
	tabs = { pass = c.PassTab, garage = c.GarageTab, market = c.MarketTab, flex = c.FlexTab }
	c.Store.changed(function()
		if openState then
			Hub.refresh()
		end
	end)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if openState then
			layout()
		end
	end)
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if openState then
				layout()
			end
		end)
	end
end

return Hub
