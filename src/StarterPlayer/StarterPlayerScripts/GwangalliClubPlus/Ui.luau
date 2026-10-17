-- GwangalliClubPlus.Ui: HUD rail + sheets of the club show add-on (client). Same look as GwangalliUI
-- (dark navy glass, cyan / magenta / gold accents, Gotham) but self-contained so it works whether or
-- not the kit is present; toasts go through GwangalliUI.toast when it exists.
--   rail      💸 후원 · 🏆 랭킹 · 🎧 DJ on the left edge (below the money chip, above the thumbstick
--             zone - GwangalliLayout), only inside the club and while no other HUD-hiding GUI is open
--   sheets    전광판 후원 (presets / custom amount, target, filtered message, tier preview, optional
--             Robux products) · 랭킹 (4 tabs + 내 기록) · 게스트 DJ (queue, turn, admin)
--   DJ pad    docked panel while it is your turn: 6 pads with cooldown rings, LED 문구, 부스로 이동,
--             끝내기 (PC: keys 1-5)
-- Touch: sheets are modal (character controls paused, HideGwangalliHUD set). Gamepad: D-pad left
-- focuses the rail, B closes a sheet. Every request carries a request id; the server answers with a
-- "receipt" (statuses -> Lines.Receipt).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")

local Ui = {}

local Core: any
local S: any
local L: any

local C = {
	glass = Color3.fromRGB(15, 18, 31),
	panel = Color3.fromRGB(24, 28, 48),
	row = Color3.fromRGB(32, 37, 62),
	cyan = Color3.fromRGB(61, 214, 245),
	magenta = Color3.fromRGB(255, 79, 163),
	gold = Color3.fromRGB(255, 194, 71),
	violet = Color3.fromRGB(139, 108, 255),
	green = Color3.fromRGB(61, 220, 132),
	red = Color3.fromRGB(255, 84, 104),
	text = Color3.fromRGB(240, 244, 255),
	sub = Color3.fromRGB(165, 176, 205),
	dark = Color3.fromRGB(12, 12, 22),
}

local gui: ScreenGui? = nil
local rail: Frame? = nil
local railButtons: { [string]: TextButton } = {}
local sheet: any = nil
local pad: any = nil
local menuData: any = nil
local menuWaiting = false
local djState: any = nil
local controlsOff = false
local donateForm: any = nil

-------------------------------------------------------------------------------------------------
-- small builders
-------------------------------------------------------------------------------------------------
local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end
local function stroke(inst: Instance, col: Color3, t: number, th: number?)
	local s = Instance.new("UIStroke")
	s.Color = col
	s.Transparency = t
	s.Thickness = th or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end
local function pad4(inst: Instance, l: number, r: number, t: number, b: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, l)
	p.PaddingRight = UDim.new(0, r)
	p.PaddingTop = UDim.new(0, t)
	p.PaddingBottom = UDim.new(0, b)
	p.Parent = inst
end
local function vlist(inst: Instance, gap: number): UIListLayout
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap)
	l.Parent = inst
	return l
end

local function label(parent: Instance, text: string, size: number, props: { [string]: any }?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamMedium
	t.TextColor3 = C.text
	t.TextSize = size
	t.Text = text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true
	t.Size = UDim2.new(1, 0, 0, size + 6)
	t.AutomaticSize = Enum.AutomaticSize.Y
	if props then
		for k, v in props do
			(t :: any)[k] = v
		end
	end
	t.Parent = parent
	return t
end

local function feedback(kind: string)
	local K = Core.K
	if K and type(K.feedback) == "function" then
		pcall(K.feedback, kind)
	end
end

local STYLE = {
	primary = { bg = C.cyan, fg = C.dark },
	gold = { bg = C.gold, fg = Color3.fromRGB(40, 25, 0) },
	magenta = { bg = C.magenta, fg = Color3.new(1, 1, 1) },
	secondary = { bg = C.row, fg = C.text },
	ghost = { bg = C.panel, fg = C.sub },
	danger = { bg = C.red, fg = Color3.new(1, 1, 1) },
}
local function button(parent: Instance, text: string, style: string, onClick: () -> (), props: { [string]: any }?): TextButton
	local st = STYLE[style] or STYLE.secondary
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = st.bg
	b.TextColor3 = st.fg
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.Text = text
	b.Size = UDim2.new(1, 0, 0, 46)
	b.Selectable = true
	corner(b, 12)
	local sc = Instance.new("UIScale")
	sc.Parent = b
	if props then
		for k, v in props do
			(b :: any)[k] = v
		end
	end
	b.MouseButton1Down:Connect(function()
		Core.tween(sc, 0.08, { Scale = 0.96 })
	end)
	b.MouseButton1Up:Connect(function()
		Core.tween(sc, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	b.MouseLeave:Connect(function()
		Core.tween(sc, 0.12, { Scale = 1 })
	end)
	b.Activated:Connect(function()
		if b:GetAttribute("Disabled") then
			feedback("error")
			return
		end
		feedback("tap")
		onClick()
	end)
	b.Parent = parent
	return b
end
local function setEnabled(b: TextButton, on: boolean)
	b:SetAttribute("Disabled", not on)
	b.BackgroundTransparency = if on then 0 else 0.55
	b.TextTransparency = if on then 0 else 0.35
end

local function chip(parent: Instance, text: string, selected: boolean, onClick: () -> (), accent: Color3?): TextButton
	local b = button(parent, text, "secondary", onClick, { Size = UDim2.new(0, 0, 0, 38), AutomaticSize = Enum.AutomaticSize.X, TextSize = 14 })
	pad4(b, 14, 14, 0, 0)
	stroke(b, accent or C.cyan, if selected then 0 else 0.85, if selected then 2 else 1)
	b.BackgroundColor3 = if selected then (accent or C.cyan):Lerp(C.panel, 0.65) else C.row
	return b
end
local function markChip(b: TextButton, selected: boolean, accent: Color3?)
	local s = b:FindFirstChildOfClass("UIStroke")
	if s then
		s.Transparency = if selected then 0 else 0.85
		s.Thickness = if selected then 2 else 1
	end
	b.BackgroundColor3 = if selected then (accent or C.cyan):Lerp(C.panel, 0.65) else C.row
end

local function wrapRow(parent: Instance, h: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, h or 40)
	f.AutomaticSize = Enum.AutomaticSize.Y
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	pcall(function()
		(l :: any).Wraps = true
	end)
	l.Padding = UDim.new(0, 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
	f.Parent = parent
	return f
end

local function card(parent: Instance, h: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = C.panel
	f.BackgroundTransparency = 0.1
	f.Size = UDim2.new(1, 0, 0, h or 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	corner(f, 14)
	stroke(f, Color3.new(1, 1, 1), 0.88)
	pad4(f, 12, 12, 10, 10)
	vlist(f, 8)
	f.Parent = parent
	return f
end

local function input(parent: Instance, placeholder: string, maxChars: number, numeric: boolean): TextBox
	local box = Instance.new("TextBox")
	box.BackgroundColor3 = C.row
	box.TextColor3 = C.text
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = C.sub
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 15
	box.Text = ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Size = UDim2.new(1, 0, 0, 44)
	box.Selectable = true
	corner(box, 12)
	stroke(box, C.cyan, 0.8)
	pad4(box, 12, 12, 0, 0)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local t = box.Text
		if numeric then
			local digits = t:gsub("%D", "")
			if digits ~= t then
				box.Text = digits
				return
			end
		end
		local n = utf8.len(t)
		if n and n > maxChars then
			-- cut at a character boundary
			local cut = utf8.offset(t, maxChars + 1)
			if cut then
				box.Text = string.sub(t, 1, cut - 1)
			end
		end
	end)
	box.Parent = parent
	return box
end

-------------------------------------------------------------------------------------------------
-- screen gui, controls, layout
-------------------------------------------------------------------------------------------------
local function ensureGui(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "GwangalliClubPlusUI"
	g.DisplayOrder = 45
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = false
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pcall(function()
		(g :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	g.Parent = Core.playerGui()
	gui = g
	return g
end

local function touch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function setControls(enabled: boolean)
	if enabled == not controlsOff then
		return
	end
	controlsOff = not enabled
	pcall(function()
		local ps = Core.player:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if pm and pm:IsA("ModuleScript") then
			local controls = (require(pm) :: any):GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end)
end

local function viewport(): Vector2
	local cam = workspace.CurrentCamera
	return if cam then cam.ViewportSize else Vector2.new(1280, 720)
end

-- another add-on asked the HUD to step aside
local function hudHidden(): boolean
	local pg = Core.player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return false
	end
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and g ~= gui and g.Enabled and g:GetAttribute("HideGwangalliHUD") == true then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- toasts (fallback when GwangalliUI is missing)
-------------------------------------------------------------------------------------------------
local function fallbackToast(title: string, body: string, icon: string)
	local g = ensureGui()
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, -80)
	f.Size = UDim2.new(0, math.min(420, viewport().X - 32), 0, 64)
	f.BackgroundColor3 = C.glass
	f.BackgroundTransparency = 0.1
	f.ZIndex = 50
	corner(f, 16)
	stroke(f, C.cyan, 0.5)
	pad4(f, 14, 14, 8, 8)
	label(f, icon .. "  " .. title, 15, { Font = Enum.Font.GothamBold, ZIndex = 51, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 22) })
	label(f, body, 13, { TextColor3 = C.sub, ZIndex = 51, Position = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 26) })
	f.Parent = g
	Core.tween(f, 0.3, { Position = UDim2.new(0.5, 0, 0, 12) })
	task.delay(3.6, function()
		Core.tween(f, 0.3, { Position = UDim2.new(0.5, 0, 0, -90) })
		task.wait(0.32)
		f:Destroy()
	end)
end

local function toastPair(pair: { string }?, icon: string?, kind: string?, ...: any)
	if not pair then
		return
	end
	local body = pair[2] or ""
	if select("#", ...) > 0 then
		local ok, s = pcall(string.format, body, ...)
		if ok then
			body = s
		end
	end
	Core.toast(pair[1], body, icon or "📺", kind or "club")
end

-------------------------------------------------------------------------------------------------
-- sheet (right side on landscape / PC, bottom on portrait)
-------------------------------------------------------------------------------------------------
local function closeSheet()
	local sh = sheet
	if not sh then
		return
	end
	sheet = nil
	donateForm = nil
	pcall(ContextActionService.UnbindAction, ContextActionService, "GwClubPlusClose")
	local g = gui
	if g then
		g:SetAttribute("HideGwangalliHUD", false)
	end
	setControls(true)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(sh.root) then
		GuiService.SelectedObject = nil
	end
	Core.tween(sh.dim, 0.2, { BackgroundTransparency = 1 })
	Core.tween(sh.panel, 0.22, { Position = sh.hidden })
	task.delay(0.25, function()
		sh.root:Destroy()
	end)
	feedback("close")
end

local function openSheet(kind: string, title: string, subtitle: string): Frame
	if sheet then
		sheet.root:Destroy()
		sheet = nil
	end
	local g = ensureGui()
	local vp = viewport()
	local portrait = vp.Y > vp.X
	local root = Instance.new("Frame")
	root.Name = "Sheet"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 20
	root.Parent = g
	local dim = Instance.new("TextButton")
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 20
	dim.Selectable = false
	dim.Parent = root
	dim.Activated:Connect(closeSheet)
	local panel = Instance.new("Frame")
	panel.BackgroundColor3 = C.glass
	panel.BackgroundTransparency = 0.06
	panel.ZIndex = 21
	corner(panel, 20)
	stroke(panel, Color3.new(1, 1, 1), 0.86)
	local shown: UDim2, hidden: UDim2
	if portrait then
		local h = math.floor(vp.Y * 0.72)
		panel.AnchorPoint = Vector2.new(0.5, 1)
		panel.Size = UDim2.new(1, -16, 0, h)
		shown = UDim2.new(0.5, 0, 1, -8)
		hidden = UDim2.new(0.5, 0, 1, h + 20)
	else
		local w = math.clamp(math.floor(vp.X * 0.42), 320, 400)
		local Layout = Core.Layout
		if Layout then
			local ok, r = pcall(Layout.rect, "sheetRight")
			if ok and type(r) == "table" and type(r.w) == "number" and r.w >= 300 then
				w = math.min(420, math.floor(r.w))
			end
		end
		panel.AnchorPoint = Vector2.new(1, 0.5)
		panel.Size = UDim2.new(0, w, 1, -24)
		shown = UDim2.new(1, -10, 0.5, 0)
		hidden = UDim2.new(1, w + 30, 0.5, 0)
	end
	panel.Position = hidden
	panel.Parent = root
	-- header
	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 64)
	head.ZIndex = 22
	head.Parent = panel
	pad4(head, 18, 60, 12, 0)
	label(head, title, 19, { Font = Enum.Font.GothamBlack, ZIndex = 22, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 24) })
	label(head, subtitle, 13, { TextColor3 = C.sub, ZIndex = 22, Position = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 18) })
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.Size = UDim2.fromOffset(44, 44)
	close.BackgroundColor3 = C.row
	close.Text = "✕"
	close.TextColor3 = C.text
	close.Font = Enum.Font.GothamBold
	close.TextSize = 18
	close.ZIndex = 23
	corner(close, 22)
	close.Parent = panel
	close.Activated:Connect(closeSheet)
	-- content
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(0, 68)
	content.Size = UDim2.new(1, 0, 1, -76)
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 4
	content.ScrollBarImageColor3 = C.cyan
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.ZIndex = 22
	content.Selectable = false
	content.Parent = panel
	pad4(content, 14, 14, 4, 16)
	vlist(content, 10)
	sheet = { kind = kind, root = root, dim = dim, panel = panel, content = content, hidden = hidden }
	Core.tween(dim, 0.2, { BackgroundTransparency = 0.55 })
	Core.tween(panel, 0.28, { Position = shown })
	g:SetAttribute("HideGwangalliHUD", true)
	if touch() then
		setControls(false)
	end
	ContextActionService:BindAction("GwClubPlusClose", function(_, state)
		if state == Enum.UserInputState.Begin then
			closeSheet()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.ButtonB)
	if UserInputService.GamepadEnabled then
		task.defer(function()
			GuiService.SelectedObject = close
		end)
	end
	feedback("open")
	return content
end

local function sectionTitle(parent: Instance, text: string, order: number)
	label(parent, text, 14, { Font = Enum.Font.GothamBold, TextColor3 = C.sub, LayoutOrder = order })
end

-------------------------------------------------------------------------------------------------
-- 전광판 후원 sheet
-------------------------------------------------------------------------------------------------
local TIER_INFO = {
	"전광판 6.5초 · 바닥 LED 물결",
	"전광판 8.5초 · 레이저 컬러 연출",
	"전광판 10.5초 · CO2 · 컨페티 · 미러볼",
	"전광판 14초 · 레이저 쇼 · 폭죽 · 스트로브",
}

local function amountOk(n: number?): boolean
	return n ~= nil and S.amountOk(n)
end

local function refreshDonate()
	local f = donateForm
	if not f or not sheet then
		return
	end
	local amount = f.amount
	local ok = amountOk(amount)
	local m = menuData or {}
	local tier = if ok then S.donateTier(amount :: number) else 1
	local T = S.tier(tier)
	f.tierBar.BackgroundColor3 = T.color
	f.tierName.Text = string.format("%s 후원", T.label)
	f.tierName.TextColor3 = T.color:Lerp(Color3.new(1, 1, 1), 0.35)
	f.tierInfo.Text = TIER_INFO[tier]
	f.counter.Text = string.format("%d/%d", utf8.len(f.msg.Text) or 0, S.Config.Donate.MessageMax)
	local wait = math.max(0, (f.cooldownUntil or 0) - os.clock())
	local canSend = ok and not f.busy and wait <= 0 and m.gate ~= false and m.priced ~= false
	setEnabled(f.send, canSend)
	if f.busy then
		f.send.Text = "송출 준비 중…"
	elseif not ok then
		f.send.Text = "금액을 골라 주세요"
	elseif wait > 0 then
		f.send.Text = string.format("%d초 뒤에 다시 후원할 수 있어요", math.ceil(wait))
	else
		f.send.Text = string.format(L.UI.send, S.won(amount :: number))
	end
	local cash, bank = m.wallet and m.wallet.cash, m.wallet and m.wallet.bank
	if type(cash) == "number" or type(bank) == "number" then
		local total = (cash or 0) + (bank or 0)
		f.wallet.Text = string.format("💵 현금 %s · 🏦 통장 %s", S.won(cash or 0), S.won(bank or 0))
		if ok and total < (amount :: number) then
			f.wallet.Text ..= "  ·  잔액 부족"
			f.wallet.TextColor3 = C.red
		else
			f.wallet.TextColor3 = C.sub
		end
	elseif m.priced == false then
		f.wallet.Text = "지갑 시스템을 불러오지 못했어요"
		f.wallet.TextColor3 = C.red
	end
	for v, b in f.presetButtons do
		markChip(b, v == amount, S.tier(S.donateTier(v)).color)
	end
	for key, b in f.targetButtons do
		markChip(b, key == f.target, C.magenta)
	end
end

local function buildDonate(content: Frame, m: any)
	local f: any = { amount = nil, target = "all", busy = false, presetButtons = {}, targetButtons = {}, cooldownUntil = os.clock() + (tonumber(m.cooldown) or 0) }
	donateForm = f
	if m.gate == false then
		local warnCard = card(content)
		warnCard.LayoutOrder = 1
		label(warnCard, "🚪 " .. L.Receipt.gate[1], 15, { Font = Enum.Font.GothamBold, TextColor3 = C.gold })
		label(warnCard, L.Receipt.gate[2], 13, { TextColor3 = C.sub })
	end
	-- wallet
	f.wallet = label(content, "", 13, { TextColor3 = C.sub, LayoutOrder = 2 })
	-- amounts
	sectionTitle(content, "💰 " .. L.UI.amount, 3)
	local grid = wrapRow(content)
	grid.LayoutOrder = 4
	for _, v in m.presets or S.Config.Donate.Presets do
		local b = chip(grid, S.wonShort(v), false, function()
			f.amount = v
			f.custom.Text = ""
			refreshDonate()
		end, S.tier(S.donateTier(v)).color)
		f.presetButtons[v] = b
	end
	f.custom = input(content, string.format("%s · %s ~ %s", L.UI.custom, S.wonShort(m.min or S.Config.Donate.Min), S.wonShort(m.max or S.Config.Donate.Max)), 9, true)
	f.custom.LayoutOrder = 5
	f.custom:GetPropertyChangedSignal("Text"):Connect(function()
		local n = tonumber(f.custom.Text)
		if n then
			f.amount = n
		elseif f.custom.Text == "" and f.amount and not f.presetButtons[f.amount] then
			f.amount = nil
		end
		refreshDonate()
	end)
	-- tier preview
	local tierCard = card(content)
	tierCard.LayoutOrder = 6
	local barRow = Instance.new("Frame")
	barRow.BackgroundTransparency = 1
	barRow.Size = UDim2.new(1, 0, 0, 22)
	barRow.Parent = tierCard
	f.tierBar = Instance.new("Frame")
	f.tierBar.Size = UDim2.fromOffset(6, 22)
	f.tierBar.BorderSizePixel = 0
	corner(f.tierBar, 3)
	f.tierBar.Parent = barRow
	f.tierName = label(barRow, "", 16, { Font = Enum.Font.GothamBlack, Position = UDim2.fromOffset(14, 0), AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, -14, 0, 22) })
	f.tierInfo = label(tierCard, "", 13, { TextColor3 = C.sub })
	-- target
	sectionTitle(content, "🎯 " .. L.UI.target, 7)
	local targets = wrapRow(content)
	targets.LayoutOrder = 8
	local function addTarget(key: string, text: string)
		f.targetButtons[key] = chip(targets, text, key == f.target, function()
			f.target = key
			refreshDonate()
		end, C.magenta)
	end
	addTarget("all", "🌊 " .. L.UI.all)
	if type(m.djOn) == "table" then
		addTarget("dj", "🎧 DJ " .. tostring(m.djOn.n or ""))
	end
	for _, t in m.tables or {} do
		if type(t) == "table" and type(t.id) == "string" then
			addTarget(t.id, string.format("%s · %s님", t.id, tostring(t.n or "손님")))
		end
	end
	-- message
	sectionTitle(content, "💬 " .. string.format("메시지 (선택 · %d자)", S.Config.Donate.MessageMax), 9)
	f.msg = input(content, L.UI.messageHint, S.Config.Donate.MessageMax, false)
	f.msg.LayoutOrder = 10
	f.counter = label(content, "", 12, { TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 11 })
	f.msg:GetPropertyChangedSignal("Text"):Connect(refreshDonate)
	local tpl = wrapRow(content)
	tpl.LayoutOrder = 12
	for _, text in m.templates or S.Config.Donate.Templates do
		chip(tpl, text, false, function()
			f.msg.Text = text
		end, C.violet)
	end
	-- queue / info
	label(content, string.format("📺 " .. L.UI.queue, tonumber(m.queue) or 0) .. " · 메시지는 자동 필터링되고 모두에게 보여요", 12, { TextColor3 = C.sub, LayoutOrder = 13 })
	-- send
	f.send = button(content, "", "gold", function()
		if f.busy or not amountOk(f.amount) then
			return
		end
		f.busy = true
		f.rid = Core.rid()
		local msg = f.msg.Text
		Core.send("donate", { rid = f.rid, amount = f.amount, msg = if msg ~= "" then msg else nil, target = f.target })
		refreshDonate()
		-- no answer in 12 s: unlock the button again (the server may still deliver the receipt)
		local rid = f.rid
		task.delay(12, function()
			if donateForm == f and f.busy and f.rid == rid then
				f.busy = false
				refreshDonate()
			end
		end)
	end, { LayoutOrder = 14, Size = UDim2.new(1, 0, 0, 52), TextSize = 16 })
	-- Robux products (config; hidden when empty)
	local products = m.products or {}
	if #products > 0 then
		sectionTitle(content, L.UI.robux, 15)
		for i, pr in products do
			button(content, string.format("💎 %s · 전광판 %s 후원으로 송출", tostring(pr.label or "로벅스 후원"), S.wonShort(tonumber(pr.won) or 0)), "magenta", function()
				f.pendingProduct = pr.id
				local msg = f.msg.Text
				Core.send("robux", { rid = Core.rid(), product = pr.id, msg = if msg ~= "" then msg else nil, target = f.target })
			end, { LayoutOrder = 15 + i, TextSize = 14 })
		end
	end
	label(content, "후원금은 돌려받을 수 없어요 · 오늘의 후원 랭킹과 이번 주 랭킹에 반영돼요", 11, { TextColor3 = C.sub, LayoutOrder = 40 })
	refreshDonate()
end

local function openDonate()
	local content = openSheet("donate", L.UI.donateTitle, L.UI.donateSub)
	local loading = label(content, "불러오는 중…", 14, { TextColor3 = C.sub })
	menuWaiting = true
	Core.send("menu", {})
	task.delay(5, function()
		if menuWaiting and sheet and sheet.kind == "donate" then
			menuWaiting = false
			loading.Text = "메뉴를 불러오지 못했어요. 잠시 후 다시 열어 주세요"
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- 랭킹 sheet
-------------------------------------------------------------------------------------------------
local rankTab = 1
local function renderRank()
	if not sheet or sheet.kind ~= "rank" then
		return
	end
	local content = sheet.content
	for _, ch in content:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	local b = Core.state.Boards or {}
	label(content, string.format("%s 밤 · 이번 주 %s", tostring(b.nl or ""), tostring(b.wl or "")), 13, { TextColor3 = C.sub, LayoutOrder = 1 })
	local tabs = wrapRow(content)
	tabs.LayoutOrder = 2
	for i, name in L.Rank.tabs do
		chip(tabs, L.Rank.icons[i] .. " " .. name, i == rankTab, function()
			rankTab = i
			renderRank()
		end, C.gold)
	end
	local list = b[L.Rank.keys[rankTab]]
	local box = card(content)
	box.LayoutOrder = 3
	if type(list) ~= "table" or #list == 0 then
		label(box, L.Rank.none, 14, { TextColor3 = C.sub })
	else
		for r, e in list do
			if type(e) == "table" then
				local row = Instance.new("Frame")
				row.BackgroundColor3 = if r == 1 then C.gold:Lerp(C.panel, 0.75) else C.row
				row.Size = UDim2.new(1, 0, 0, 48)
				corner(row, 10)
				row.Parent = box
				local badge = label(row, if r == 1 then "👑" else tostring(r), 17, { Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.fromOffset(40, 48) })
				local _ = badge
				local nm = tostring(e.n or "손님")
				if type(e.x) == "string" and e.x ~= "" then
					nm ..= " · " .. e.x
				end
				label(row, nm, 15, { Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(44, 0), AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, -150, 0, 48), TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
				label(row, S.wonShort(tonumber(e.v) or 0), 15, { Font = Enum.Font.GothamBlack, TextColor3 = if r == 1 then C.gold else C.text, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(0, 100, 0, 48) })
			end
		end
	end
	local me = Core.player
	label(content, string.format(L.Rank.mine, S.won(tonumber(me:GetAttribute(S.Attr.Tonight)) or 0), S.won(tonumber(me:GetAttribute(S.Attr.Week)) or 0)), 13, { Font = Enum.Font.GothamBold, TextColor3 = C.cyan, LayoutOrder = 4 })
	label(content, L.Rank.shared, 11, { TextColor3 = C.sub, LayoutOrder = 5 })
end

local function openRank()
	openSheet("rank", L.Rank.title, "옆 전광판과 같은 실시간 랭킹")
	renderRank()
end

-------------------------------------------------------------------------------------------------
-- 게스트 DJ sheet
-------------------------------------------------------------------------------------------------
local function clockText(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function renderDj()
	if not sheet or sheet.kind ~= "dj" then
		return
	end
	local content = sheet.content
	for _, ch in content:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	local d = djState or {}
	local pub = Core.state.DJ or {}
	local now = Core.now()
	local cur = card(content)
	cur.LayoutOrder = 1
	if pub.on then
		label(cur, string.format("🎧 %s · DJ %s", L.UI.djNow, tostring(pub.n or "")), 16, { Font = Enum.Font.GothamBlack })
		label(cur, string.format("남은 시간 %s · %s", clockText((pub.untilT or 0) - now), string.format(L.UI.djQueue, tonumber(pub.count) or 0)), 13, { TextColor3 = C.sub })
	else
		label(cur, L.UI.djNone, 15, { Font = Enum.Font.GothamBold })
		label(cur, string.format(L.UI.djQueue, tonumber(pub.count) or 0), 13, { TextColor3 = C.sub })
	end
	if d.enabled == false then
		label(content, "지금은 게스트 DJ 타임이 꺼져 있어요", 14, { TextColor3 = C.gold, LayoutOrder = 2 })
		return
	end
	if d.me then
		label(content, string.format(L.UI.djMine, clockText((d.untilT or 0) - now)), 15, { Font = Enum.Font.GothamBold, TextColor3 = C.magenta, LayoutOrder = 3 })
		button(content, "🎛️ DJ 패드 열기", "magenta", function()
			closeSheet()
			Ui.showPad(true)
		end, { LayoutOrder = 4 })
		button(content, "🚶 " .. L.UI.djGoto, "secondary", function()
			Core.send("dj", { op = "goto" })
		end, { LayoutOrder = 5 })
		button(content, "⏹️ " .. L.UI.djEnd, "danger", function()
			Core.send("dj", { op = "leave" })
		end, { LayoutOrder = 6 })
	elseif type(d.pos) == "number" then
		label(content, string.format(L.UI.djWait, d.pos), 15, { Font = Enum.Font.GothamBold, TextColor3 = C.cyan, LayoutOrder = 3 })
		button(content, L.UI.djLeave, "secondary", function()
			Core.send("dj", { op = "leave" })
		end, { LayoutOrder = 4 })
	else
		local price = tonumber(d.price) or 0
		local again = tonumber(d.again) or 0
		local b = button(content, if price > 0 then string.format(L.UI.djJoinPrice, S.won(price)) else L.UI.djJoin, "primary", function()
			Core.send("dj", { op = "join" })
		end, { LayoutOrder = 3 })
		if again > 0 then
			setEnabled(b, false)
			b.Text = string.format("%d초 뒤에 다시 신청할 수 있어요", math.ceil(again))
		end
	end
	label(content, string.format(L.UI.djSub, math.floor((tonumber(d.turn) or S.Config.DJ.TurnSeconds) / 60)) .. " · DJ 부스 근처에서 패드를 쓸 수 있어요", 12, { TextColor3 = C.sub, LayoutOrder = 10 })
	if d.admin then
		sectionTitle(content, "🛠️ " .. L.UI.admin, 20)
		local row = wrapRow(content)
		row.LayoutOrder = 21
		chip(row, L.UI.adminSkip, false, function()
			Core.send("dj", { op = "admin", admin = "skip" })
		end, C.gold)
		chip(row, L.UI.adminClear, false, function()
			Core.send("dj", { op = "admin", admin = "clear" })
		end, C.gold)
		chip(row, "DJ 타임 멈추기", false, function()
			Core.send("dj", { op = "admin", admin = "stop" })
		end, C.red)
	end
end

local function openDj()
	openSheet("dj", L.UI.djTitle, string.format(L.UI.djSub, math.floor(S.Config.DJ.TurnSeconds / 60)))
	renderDj()
	Core.send("dj", { op = "state" })
end

-------------------------------------------------------------------------------------------------
-- DJ pad (docked)
-------------------------------------------------------------------------------------------------
local padCool: { [string]: number } = {}

local function railPos(): (number, number)
	local x, y = 12, 150
	local Layout = Core.Layout
	if Layout then
		local ok, r = pcall(Layout.rect, "topLeftChips")
		if ok and type(r) == "table" and type(r.x) == "number" then
			x = r.x
			y = r.y + r.h + 14
		end
	end
	return x, y
end

local function firePad(id: string, text: string?)
	local def = S.pad(id)
	if not def then
		return
	end
	local left = (padCool[id] or 0) - os.clock()
	if left > 0 then
		toastPair(L.DJ.cool, def.icon, "info", math.ceil(left))
		return
	end
	padCool[id] = os.clock() + def.cooldown
	Core.send("dj", { op = "pad", pad = id, text = text })
end

local function buildPad()
	local g = ensureGui()
	local x, y = railPos()
	local frame = Instance.new("Frame")
	frame.Name = "DjPad"
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(250, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = C.glass
	frame.BackgroundTransparency = 0.1
	frame.ZIndex = 10
	corner(frame, 16)
	stroke(frame, C.magenta, 0.4, 1.5)
	pad4(frame, 10, 10, 10, 10)
	vlist(frame, 8)
	frame.Parent = g
	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 24)
	head.Parent = frame
	local title = label(head, L.Pad.title, 15, { Font = Enum.Font.GothamBlack, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, -60, 0, 24), ZIndex = 11 })
	local fold = button(head, L.Pad.collapse, "ghost", function()
		Ui.showPad(false)
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(56, 24), TextSize = 12, ZIndex = 11 })
	local _ = fold
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Parent = frame
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.333, -6, 0, 58)
	gl.CellPadding = UDim2.fromOffset(6, 6)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	local cells = {}
	for i, def in S.Config.DJ.Pads do
		if def.id ~= "text" then
			local b = button(grid, "", "secondary", function()
				firePad(def.id)
			end, { LayoutOrder = i, ZIndex = 11 })
			stroke(b, C.magenta, 0.6)
			label(b, def.icon, 20, { TextXAlignment = Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 5), ZIndex = 12 })
			label(b, def.label, 11, { Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 34), ZIndex = 12 })
			local veil = Instance.new("Frame")
			veil.BackgroundColor3 = Color3.new(0, 0, 0)
			veil.BackgroundTransparency = 0.45
			veil.AnchorPoint = Vector2.new(0, 1)
			veil.Position = UDim2.fromScale(0, 1)
			veil.Size = UDim2.fromScale(1, 0)
			veil.ZIndex = 13
			corner(veil, 12)
			veil.Parent = b
			table.insert(cells, { id = def.id, veil = veil, cool = def.cooldown, key = i })
		end
	end
	local textRow = Instance.new("Frame")
	textRow.BackgroundTransparency = 1
	textRow.Size = UDim2.new(1, 0, 0, 40)
	textRow.Parent = frame
	local box = input(textRow, L.Pad.textHint, S.Config.DJ.TextMax, false)
	box.Size = UDim2.new(1, -72, 0, 40)
	box.ZIndex = 11
	local sendB = button(textRow, L.Pad.send, "magenta", function()
		local t = box.Text
		if t ~= "" then
			firePad("text", t)
			box.Text = ""
		end
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(66, 40), TextSize = 13, ZIndex = 11 })
	local _s = sendB
	local quick = wrapRow(frame)
	for _, line in L.DJText do
		local c = chip(quick, line, false, function()
			box.Text = line
		end, C.violet)
		c.TextSize = 12
		c.Size = UDim2.new(0, 0, 0, 30)
		c.ZIndex = 11
	end
	local bottom = Instance.new("Frame")
	bottom.BackgroundTransparency = 1
	bottom.Size = UDim2.new(1, 0, 0, 38)
	bottom.Parent = frame
	button(bottom, L.Pad.booth, "secondary", function()
		Core.send("dj", { op = "goto" })
	end, { Size = UDim2.new(0.5, -4, 0, 38), TextSize = 13, ZIndex = 11 })
	button(bottom, L.Pad.finish, "danger", function()
		Core.send("dj", { op = "leave" })
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.5, -4, 0, 38), TextSize = 13, ZIndex = 11 })
	pad = { frame = frame, title = title, cells = cells, box = box, open = true }
end

function Ui.showPad(open: boolean)
	if open then
		if not pad or not pad.frame.Parent then
			buildPad()
		end
		pad.frame.Visible = true
		pad.open = true
		if railButtons.dj then
			railButtons.dj.Text = "🎛️"
		end
	elseif pad then
		pad.frame.Visible = false
		pad.open = false
	end
end

local function destroyPad()
	if pad then
		pad.frame:Destroy()
		pad = nil
	end
end

local function stepPad()
	if not pad or not pad.open then
		return
	end
	local d = djState
	local now = Core.now()
	if d and d.me then
		pad.title.Text = string.format("%s · %s", L.Pad.title, clockText((d.untilT or 0) - now))
	end
	local t = os.clock()
	for _, c in pad.cells do
		local left = math.max(0, (padCool[c.id] or 0) - t)
		c.veil.Size = UDim2.fromScale(1, math.clamp(left / c.cool, 0, 1))
	end
end

-------------------------------------------------------------------------------------------------
-- rail
-------------------------------------------------------------------------------------------------
local function buildRail()
	local g = ensureGui()
	local r = Instance.new("Frame")
	r.Name = "Rail"
	r.BackgroundTransparency = 1
	r.Size = UDim2.fromOffset(64, 0)
	r.AutomaticSize = Enum.AutomaticSize.Y
	r.Visible = false
	r.Parent = g
	vlist(r, 10)
	local small = touch()
	local size = if small then 50 else 48
	local function railButton(key: string, icon: string, text: string, order: number, onClick: () -> ())
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromOffset(64, size + 16)
		holder.LayoutOrder = order
		holder.Parent = r
		local b = Instance.new("TextButton")
		b.Name = key
		b.AutoButtonColor = false
		b.AnchorPoint = Vector2.new(0.5, 0)
		b.Position = UDim2.new(0.5, 0, 0, 0)
		b.Size = UDim2.fromOffset(size, size)
		b.BackgroundColor3 = C.glass
		b.BackgroundTransparency = 0.12
		b.Text = icon
		b.TextSize = 22
		b.Font = Enum.Font.GothamBold
		b.TextColor3 = C.text
		b.Selectable = true
		corner(b, math.floor(size / 2))
		stroke(b, if key == "donate" then C.gold elseif key == "dj" then C.magenta else C.cyan, 0.35, 1.5)
		local sc = Instance.new("UIScale")
		sc.Parent = b
		b.MouseButton1Down:Connect(function()
			Core.tween(sc, 0.08, { Scale = 0.94 })
		end)
		b.MouseButton1Up:Connect(function()
			Core.tween(sc, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
		b.Activated:Connect(function()
			feedback("tap")
			onClick()
		end)
		b.Parent = holder
		label(holder, text, 11, { Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, size + 2), TextStrokeTransparency = 0.5 })
		railButtons[key] = b
	end
	railButton("donate", "💸", L.UI.hudDonate, 1, openDonate)
	railButton("rank", "🏆", "랭킹", 2, openRank)
	if S.Config.DJ.Enabled then
		railButton("dj", "🎧", L.UI.hudDj, 3, function()
			if djState and djState.me then
				Ui.showPad(not (pad and pad.open))
			else
				openDj()
			end
		end)
	end
	rail = r
	local function place()
		local x, y = railPos()
		r.Position = UDim2.fromOffset(x, y)
		if pad then
			pad.frame.Position = UDim2.fromOffset(x, y)
		end
	end
	place()
	local Layout = Core.Layout
	if Layout and type(Layout.onChanged) == "function" then
		pcall(Layout.onChanged, place)
	end
	-- gamepad: D-pad left focuses the rail
	ContextActionService:BindAction("GwClubPlusRail", function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if r.Visible and not sheet and railButtons.donate then
			GuiService.SelectedObject = railButtons.donate
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.DPadLeft)
end

local function stepRail()
	local r = rail
	if not r then
		return
	end
	local show = Core.inside and not sheet and not hudHidden()
	local padOpen = pad ~= nil and pad.open and pad.frame.Visible
	r.Visible = show and not padOpen
	if pad then
		pad.frame.Visible = pad.open and Core.inside and not sheet
	end
	local dj = Core.state.DJ
	local b = railButtons.dj
	if b then
		local mine = djState and djState.me
		b.Text = if mine then "🎛️" else "🎧"
		local st = b:FindFirstChildOfClass("UIStroke")
		if st then
			st.Transparency = if type(dj) == "table" and dj.on then 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 4)) else 0.35
		end
	end
end

-------------------------------------------------------------------------------------------------
-- server events
-------------------------------------------------------------------------------------------------
local function onMenu(m: any)
	menuData = m
	if type(m.dj) == "table" then
		djState = m.dj
	end
	if menuWaiting and sheet and sheet.kind == "donate" then
		menuWaiting = false
		for _, ch in sheet.content:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		buildDonate(sheet.content, m)
	end
end

local function onReceipt(r: any)
	local status = tostring(r.status or "error")
	local f = donateForm
	if r.op == "robux" then
		if status == "robuxOk" and type(r.product) == "number" then
			local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, Core.player, r.product)
			if not ok then
				warn("[GwangalliClubPlus] PromptProductPurchase failed:", err)
				toastPair(L.Receipt.error, "💎", "warn")
			end
			return
		end
		if status == "ok" then
			return -- (Donate.grantRobux already sent a toast)
		end
	end
	if f then
		f.busy = false
	end
	local pair = L.Receipt[status] or L.Receipt.error
	if status == "ok" then
		local wait = math.max(0, math.floor((tonumber(r.at) or Core.now()) - Core.now()))
		if (tonumber(r.pos) or 1) <= 1 and wait <= 2 then
			toastPair(L.Receipt.okNow, "📺", "club")
		else
			toastPair(L.Receipt.ok, "📺", "club", tonumber(r.pos) or 1, wait)
		end
		feedback("money")
		if f then
			f.cooldownUntil = os.clock() + S.Config.Donate.Cooldown
		end
		if sheet and sheet.kind == "donate" and not r.late then
			closeSheet()
		end
	elseif status == "wait" then
		toastPair(pair, "⏳", "warn", tonumber(r.wait) or 0)
		if f then
			f.cooldownUntil = os.clock() + (tonumber(r.wait) or 0)
		end
	elseif status == "slow" then
		toastPair(pair, "⏳", "warn")
	else
		toastPair(pair, "⚠️", "warn")
		feedback("error")
	end
	refreshDonate()
end

local function onDj(d: any)
	djState = d
	if d.me then
		if not pad then
			Ui.showPad(true)
		end
		-- server cooldowns win
		if type(d.cooldowns) == "table" then
			local t = os.clock()
			for id, left in d.cooldowns do
				if type(left) == "number" then
					padCool[id] = t + left
				end
			end
		end
	else
		destroyPad()
	end
	renderDj()
end

function Ui.init(core: any)
	Core = core
	S = core.S
	L = core.L
	if not Core.K or type(Core.K.toast) ~= "function" then
		Core.fallbackToast = fallbackToast
	end
	buildRail()
	Core.onEvent("menu", onMenu)
	Core.onEvent("receipt", onReceipt)
	Core.onEvent("dj", onDj)
	Core.onEvent("toast", function(t: any)
		Core.toast(tostring(t.title or ""), tostring(t.body or ""), t.icon, t.kind)
	end)
	Core.on("Boards", function()
		renderRank()
	end)
	Core.on("DJ", function(pub: any)
		-- my turn ended elsewhere (admin / time): the private state follows on the "dj" event
		if djState and djState.me and type(pub) == "table" and pub.u ~= Core.player.UserId then
			djState.me = false
			destroyPad()
		end
		renderDj()
	end)
	Core.job("ui", 10, function()
		stepRail()
		stepPad()
		if donateForm and donateForm.cooldownUntil and donateForm.cooldownUntil > os.clock() - 0.2 then
			refreshDonate()
		end
		return true
	end)
	-- PC: keys 1-5 fire the DJ pads while the pad is open (not while typing)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not pad or not pad.open or UserInputService:GetFocusedTextBox() then
			return
		end
		local map = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5 }
		local i = map[input.KeyCode]
		if i and pad.cells[i] then
			firePad(pad.cells[i].id)
		end
	end)
	-- leaving the club closes our sheet
	local wasInside = Core.inside
	Core.job("uigate", 2, function()
		if wasInside and not Core.inside and sheet then
			closeSheet()
		end
		wasInside = Core.inside
		return true
	end)
end

return Ui
