-- GwangalliCarDealer/Ui (client): the dealer's UI kit — premium dark-glass showroom look (near-black navy
-- glass, hairline strokes, electric-blue accent, gold for 특가), sized for phones (compact metrics, 44 px+ touch
-- targets), PCs and gamepads (selectable buttons, Ui.select). Everything lives in our own ScreenGuis in
-- PlayerGui (never under map parts).
--   Ui.C / Ui.F                         colours / fonts
--   Ui.make(class, props, parent)       Ui.corner / stroke / pad / list / grad / tween
--   Ui.label(parent, props)             Ui.frame(parent, props)    Ui.glass(parent, props)
--   Ui.button(parent, opts) -> btn      { inst, label, setText, setEnabled, setStyle, onClick }
--   Ui.chip(parent, opts) -> chip       toggle chip { inst, set(on), on }
--   Ui.badge(parent, text, tone, props) Ui.dots(parent, n, max)    Ui.scroll(parent, props)
--   Ui.screen(name, order) -> ScreenGui (HideGwangalliHUD while Ui.show(gui, true))
--   Ui.menu(anchor, items, onPick)      small dropdown (items = { { id, label, on? } })
--   Ui.metrics() -> { w, h, compact, phone, portrait, touch, gamepad, inset }
--   Ui.onLayout(fn) -> disconnect       Ui.textWidth(text, size, font)
--   Ui.toast(data)                      GwangalliUI K.toast when present, else our own
--   Ui.sfx(kind)                        K.feedback kinds: tap toggle open close notify money success error
--   Ui.controls(key, enabled)           character controls off on touch while a sheet is up (ref-counted)
--   Ui.blur(on, key)                    background blur (ref-counted)
--   Ui.select(obj)                      gamepad selection

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Ui = {}

local player = Players.LocalPlayer
local K: any = nil

Ui.C = {
	bg = Color3.fromRGB(9, 11, 17),
	bg2 = Color3.fromRGB(15, 18, 27),
	glass = Color3.fromRGB(20, 24, 35),
	glass2 = Color3.fromRGB(28, 33, 47),
	card = Color3.fromRGB(22, 26, 38),
	cardHi = Color3.fromRGB(32, 38, 55),
	line = Color3.fromRGB(255, 255, 255),
	ink = Color3.fromRGB(244, 246, 250),
	sub = Color3.fromRGB(168, 176, 194),
	faint = Color3.fromRGB(108, 116, 134),
	accent = Color3.fromRGB(64, 132, 255),
	accentD = Color3.fromRGB(38, 92, 214),
	accentSoft = Color3.fromRGB(34, 52, 92),
	gold = Color3.fromRGB(242, 190, 82),
	goldD = Color3.fromRGB(150, 108, 30),
	green = Color3.fromRGB(52, 199, 123),
	red = Color3.fromRGB(240, 82, 82),
	orange = Color3.fromRGB(245, 152, 64),
	pink = Color3.fromRGB(255, 92, 138),
	white = Color3.fromRGB(255, 255, 255),
	black = Color3.fromRGB(0, 0, 0),
}
local Col = Ui.C

Ui.F = {
	black = Enum.Font.GothamBlack,
	bold = Enum.Font.GothamBold,
	med = Enum.Font.GothamMedium,
	reg = Enum.Font.Gotham,
}
local F = Ui.F

Ui.TONE = { ok = Col.green, warn = Col.orange, bad = Col.red, info = Col.accent, gold = Col.gold, pink = Col.pink, muted = Col.faint }

function Ui.init(k: any)
	K = k
end

function Ui.make(class: string, props: { [string]: any }?, parent: Instance?): any
	local o = Instance.new(class)
	if props then
		for k, v in props do
			(o :: any)[k] = v
		end
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local make = Ui.make

function Ui.corner(o: Instance, r: number?): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0, r or 12) }, o)
end

function Ui.stroke(o: Instance, color: Color3?, thick: number?, transp: number?): UIStroke
	return make("UIStroke", { Color = color or Col.line, Thickness = thick or 1, Transparency = transp or 0.88, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end

function Ui.pad(o: Instance, l: number, r: number?, t: number?, b: number?): UIPadding
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingRight = UDim.new(0, r or l),
		PaddingTop = UDim.new(0, t or l),
		PaddingBottom = UDim.new(0, b or t or l),
	}, o)
end

function Ui.list(o: Instance, dir: string?, gap: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return make("UIListLayout", {
		FillDirection = if dir == "x" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
	}, o)
end

function Ui.grad(o: Instance, a: Color3, b: Color3, rot: number?, ta: number?, tb: number?): UIGradient
	local g = make("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rot or 90 }, o)
	if ta or tb then
		g.Transparency = NumberSequence.new(ta or 0, tb or 0)
	end
	return g
end

function Ui.tween(o: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

function Ui.reduced(): boolean
	if K and type(K.reduced) == "function" then
		local ok, v = pcall(K.reduced)
		if ok then
			return v == true
		end
	end
	return false
end

function Ui.frame(parent: Instance?, props: { [string]: any }?): Frame
	local f = make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, nil)
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	f.Parent = parent
	return f
end

function Ui.label(parent: Instance?, props: { [string]: any }?): TextLabel
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = F.med,
		TextSize = 15,
		TextColor3 = Col.ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		RichText = false,
		Size = UDim2.new(1, 0, 0, 20),
		Text = "",
	}, nil)
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	l.Parent = parent
	return l
end

function Ui.glass(parent: Instance?, props: { [string]: any }?): Frame
	local f = Ui.frame(nil, { BackgroundTransparency = 0.06, BackgroundColor3 = Col.glass })
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	Ui.corner(f, 16)
	Ui.stroke(f, Col.line, 1, 0.9)
	f.Parent = parent
	return f
end

function Ui.textWidth(text: string, size: number, font: Enum.Font?): number
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, font or F.med, Vector2.new(4000, 200)).X
	end)
	return if ok then v else #text * size * 0.55
end

-- Sounds / haptics: the game's own feedback when its UI kit is there, else built-in sounds.
local SFX = { tap = "rbxasset://sounds/clickfast.wav", toggle = "rbxasset://sounds/clickfast.wav", open = "rbxasset://sounds/swoosh.wav", close = "rbxasset://sounds/swoosh.wav", notify = "rbxasset://sounds/electronicpingshort.wav", money = "rbxasset://sounds/electronicpingshort.wav", success = "rbxasset://sounds/electronicpingshort.wav", error = "rbxasset://sounds/clickfast.wav" }
local sounds: { [string]: Sound } = {}
function Ui.sfx(kind: string)
	if K and type(K.feedback) == "function" then
		if pcall(K.feedback, kind) then
			return
		end
	end
	pcall(function()
		local s = sounds[kind]
		if not s then
			s = make("Sound", { SoundId = SFX[kind] or SFX.tap, Volume = if kind == "tap" or kind == "toggle" then 0.25 else 0.4, Name = "GwDealerSfx_" .. kind }, SoundService)
			sounds[kind] = s
		end
		SoundService:PlayLocalSound(s)
	end)
end

-- Buttons ------------------------------------------------------------------------------------------------
local STYLES = {
	primary = { bg = Col.accent, bg2 = Col.accentD, text = Col.white, stroke = 1 },
	gold = { bg = Col.gold, bg2 = Color3.fromRGB(214, 150, 46), text = Color3.fromRGB(30, 22, 6), stroke = 1 },
	secondary = { bg = Col.glass2, bg2 = Col.glass2, text = Col.ink, stroke = 0.82 },
	ghost = { bg = Col.glass, bg2 = Col.glass, text = Col.sub, stroke = 0.86, transp = 0.4 },
	danger = { bg = Col.red, bg2 = Color3.fromRGB(196, 52, 52), text = Col.white, stroke = 1 },
	green = { bg = Col.green, bg2 = Color3.fromRGB(34, 150, 92), text = Col.white, stroke = 1 },
}

function Ui.button(parent: Instance?, opts: { [string]: any }): any
	local st = STYLES[opts.style or "secondary"] or STYLES.secondary
	local b = make("TextButton", {
		Name = opts.name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = st.bg,
		BackgroundTransparency = st.transp or 0,
		BorderSizePixel = 0,
		Size = opts.size or UDim2.fromOffset(160, 44),
		Position = opts.pos or UDim2.new(),
		AnchorPoint = opts.anchor or Vector2.zero,
		Text = "",
		LayoutOrder = opts.order or 0,
		ZIndex = opts.z or 1,
		Selectable = true,
		ClipsDescendants = true,
	}, nil)
	Ui.corner(b, opts.radius or 12)
	local stroke = Ui.stroke(b, Col.line, 1, st.stroke)
	local grad = Ui.grad(b, Col.white, Color3.fromRGB(205, 210, 222), 90)
	local lbl = Ui.label(b, {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = (if opts.icon then opts.icon .. "  " else "") .. (opts.text or ""),
		Font = opts.font or F.bold,
		TextSize = opts.textSize or 15,
		TextColor3 = st.text,
		TextXAlignment = opts.align or Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = (opts.z or 1) + 1,
	})
	if opts.align == Enum.TextXAlignment.Left then
		Ui.pad(lbl, 14, 10, 0, 0)
	end
	local api: any = { inst = b, label = lbl, enabled = true, style = opts.style or "secondary" }
	local cbs = {}
	if opts.onClick then
		table.insert(cbs, opts.onClick)
	end
	function api.onClick(fn: () -> ())
		table.insert(cbs, fn)
	end
	function api.setText(t: string, icon: string?)
		lbl.Text = (if icon then icon .. "  " else "") .. t
	end
	function api.setStyle(name: string)
		local s = STYLES[name] or STYLES.secondary
		st = s
		api.style = name
		b.BackgroundColor3 = s.bg
		b.BackgroundTransparency = if api.enabled then (s.transp or 0) else 0.55
		lbl.TextColor3 = s.text
		stroke.Transparency = s.stroke
	end
	function api.setEnabled(on: boolean)
		api.enabled = on
		b.BackgroundTransparency = if on then (st.transp or 0) else 0.55
		lbl.TextTransparency = if on then 0 else 0.45
		b.Selectable = true
	end
	b.MouseEnter:Connect(function()
		if api.enabled then
			grad.Color = ColorSequence.new(Col.white, Color3.fromRGB(225, 230, 240))
		end
	end)
	b.MouseLeave:Connect(function()
		grad.Color = ColorSequence.new(Col.white, Color3.fromRGB(205, 210, 222))
	end)
	b.SelectionGained:Connect(function()
		stroke.Color = Col.accent
		stroke.Transparency = 0
		stroke.Thickness = 2
	end)
	b.SelectionLost:Connect(function()
		stroke.Color = Col.line
		stroke.Transparency = st.stroke
		stroke.Thickness = 1
	end)
	b.Activated:Connect(function()
		if not api.enabled and not opts.clickWhenDisabled then
			Ui.sfx("error")
			return
		end
		Ui.sfx(opts.sound or "tap")
		if not Ui.reduced() then
			local sc = b:FindFirstChildOfClass("UIScale") or make("UIScale", {}, b)
			sc.Scale = 0.96
			Ui.tween(sc, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		for _, fn in cbs do
			task.spawn(fn)
		end
	end)
	b.Parent = parent
	return api
end

-- A toggle chip ("살 수 있는 차", category tabs)
function Ui.chip(parent: Instance?, opts: { [string]: any }): any
	local h = opts.height or 36
	local text = (if opts.icon then opts.icon .. " " else "") .. (opts.text or "")
	local size = opts.textSize or 14
	local w = opts.width or (Ui.textWidth(text, size, F.bold) + 30)
	local b = make("TextButton", {
		Name = opts.name or "Chip",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(w, h),
		Text = "",
		LayoutOrder = opts.order or 0,
		BackgroundColor3 = Col.glass2,
		Selectable = true,
		ZIndex = opts.z or 1,
	}, nil)
	Ui.corner(b, h // 2)
	local stroke = Ui.stroke(b, Col.line, 1, 0.84)
	local lbl = Ui.label(b, { Size = UDim2.fromScale(1, 1), Text = text, Font = F.bold, TextSize = size, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = (opts.z or 1) + 1 })
	local api: any = { inst = b, label = lbl, on = false, width = w }
	local tone = opts.tone or Col.accent
	function api.set(on: boolean)
		api.on = on
		b.BackgroundColor3 = if on then tone else Col.glass2
		lbl.TextColor3 = if on then (if tone == Col.gold then Color3.fromRGB(30, 22, 6) else Col.white) else Col.sub
		stroke.Transparency = if on then 1 else 0.84
	end
	function api.setText(t: string)
		lbl.Text = t
		if not opts.width then
			api.width = Ui.textWidth(t, size, F.bold) + 30
			b.Size = UDim2.fromOffset(api.width, h)
		end
	end
	b.SelectionGained:Connect(function()
		stroke.Color = Col.accent
		stroke.Transparency = 0
		stroke.Thickness = 2
	end)
	b.SelectionLost:Connect(function()
		stroke.Color = Col.line
		stroke.Thickness = 1
		stroke.Transparency = if api.on then 1 else 0.84
	end)
	b.Activated:Connect(function()
		Ui.sfx("toggle")
		if opts.onClick then
			task.spawn(opts.onClick, api)
		end
	end)
	api.set(opts.on == true)
	b.Parent = parent
	return api
end

function Ui.badge(parent: Instance?, text: string, tone: Color3?, props: { [string]: any }?): Frame
	local size = (props and props.textSize) or 12
	local h = (props and props.height) or 20
	local w = Ui.textWidth(text, size, F.bold) + 14
	local f = Ui.frame(nil, { Size = UDim2.fromOffset(w, h), BackgroundTransparency = 0.05, BackgroundColor3 = tone or Col.accent, LayoutOrder = (props and props.order) or 0, ZIndex = (props and props.z) or 1 })
	Ui.corner(f, 6)
	local dark = tone == Col.gold or tone == Col.green
	Ui.label(f, { Size = UDim2.fromScale(1, 1), Text = text, Font = F.bold, TextSize = size, TextColor3 = if dark then Color3.fromRGB(20, 18, 10) else Col.white, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = ((props and props.z) or 1) + 1 })
	f.Parent = parent
	return f
end

-- 5-dot rating bar
function Ui.dots(parent: Instance?, n: number, max: number?, color: Color3?, props: { [string]: any }?): Frame
	local m = max or 5
	local f = Ui.frame(nil, { Size = UDim2.fromOffset(m * 18, 10) })
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	Ui.list(f, "x", 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	for i = 1, m do
		local d = Ui.frame(f, { Size = UDim2.fromOffset(14, 6), BackgroundTransparency = 0, BackgroundColor3 = if i <= n then (color or Col.accent) else Col.glass2, LayoutOrder = i })
		Ui.corner(d, 3)
	end
	f.Parent = parent
	return f
end

function Ui.scroll(parent: Instance?, props: { [string]: any }?): ScrollingFrame
	local s = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Col.sub,
		ScrollBarImageTransparency = 0.4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Selectable = false,
	}, nil)
	if props then
		for k, v in props do
			(s :: any)[k] = v
		end
	end
	s.Parent = parent
	return s
end

-- Screens ------------------------------------------------------------------------------------------------
function Ui.screen(name: string, order: number): ScreenGui
	local pg = player:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local g = make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order,
		Enabled = false,
	}, nil)
	pcall(function()
		(g :: any).ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- keep clear of phone notches
	end)
	g:SetAttribute("HideGwangalliHUD", false)
	g.Parent = pg
	return g
end

function Ui.show(g: ScreenGui, on: boolean, hideHud: boolean?)
	g.Enabled = on
	g:SetAttribute("HideGwangalliHUD", on and hideHud ~= false)
end

function Ui.metrics(): any
	local cam = workspace.CurrentCamera
	local vs = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local inset = Vector2.new(0, 36)
	pcall(function()
		local tl = GuiService:GetGuiInset()
		inset = tl
	end)
	pcall(function()
		local r = (GuiService :: any).TopbarInset
		if r and r.Height and r.Height > inset.Y then
			inset = Vector2.new(0, r.Height)
		end
	end)
	local w, h = vs.X, vs.Y
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local gamepad = UserInputService.GamepadEnabled and UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
	return {
		w = w,
		h = h,
		inset = inset.Y,
		compact = h < 560 or w < 760,
		phone = math.min(w, h) < 560,
		portrait = h > w * 1.05,
		touch = touch,
		gamepad = gamepad,
		wide = w >= 1100 and h >= 620,
	}
end

local layoutCbs: { [number]: (any) -> () } = {}
local layoutN = 0
local hooked = false
local function fireLayout()
	local m = Ui.metrics()
	for _, fn in layoutCbs do
		task.spawn(fn, m)
	end
end
function Ui.onLayout(fn: (any) -> ()): () -> ()
	layoutN += 1
	local id = layoutN
	layoutCbs[id] = fn
	if not hooked then
		hooked = true
		local function bind(cam: Camera?)
			if cam then
				cam:GetPropertyChangedSignal("ViewportSize"):Connect(fireLayout)
			end
		end
		bind(workspace.CurrentCamera)
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			bind(workspace.CurrentCamera)
			fireLayout()
		end)
	end
	return function()
		layoutCbs[id] = nil
	end
end

-- Dropdown menu below/above an anchor GuiObject; closes on pick or outside tap.
local openMenu: Frame? = nil
function Ui.closeMenu()
	if openMenu then
		openMenu:Destroy()
		openMenu = nil
	end
end
function Ui.menu(anchor: GuiObject, items: { any }, onPick: (any) -> (), opts: { [string]: any }?)
	Ui.closeMenu()
	local gui = anchor:FindFirstAncestorWhichIsA("ScreenGui")
	if not gui then
		return
	end
	local rowH = 40
	local w = (opts and opts.width) or 0
	for _, it in items do
		w = math.max(w, Ui.textWidth(it.label, 14, F.bold) + 56)
	end
	w = math.max(w, anchor.AbsoluteSize.X)
	local h = #items * rowH + 12
	local catcher = make("TextButton", { Name = "GwDealerMenu", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 80, AutoButtonColor = false, Selectable = false }, gui)
	openMenu = catcher :: any
	catcher.Activated:Connect(Ui.closeMenu)
	local ap, as = anchor.AbsolutePosition, anchor.AbsoluteSize
	local gs = (gui :: ScreenGui).AbsoluteSize
	local y = ap.Y + as.Y + 6
	if y + h > gs.Y - 8 then
		y = math.max(8, ap.Y - h - 6)
	end
	local x = math.clamp(ap.X, 8, math.max(8, gs.X - w - 8))
	local panel = Ui.glass(catcher, { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), ZIndex = 81, BackgroundColor3 = Col.glass2, BackgroundTransparency = 0.02 })
	Ui.pad(panel, 6)
	Ui.list(panel, "y", 0)
	local first: GuiObject? = nil
	for i, it in items do
		local row = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Col.cardHi, BackgroundTransparency = if it.on then 0.2 else 1, Size = UDim2.new(1, 0, 0, rowH), LayoutOrder = i, ZIndex = 82 }, panel)
		Ui.corner(row, 10)
		Ui.label(row, { Text = (if it.on then "✓  " else "     ") .. it.label, Font = F.bold, TextSize = 14, TextColor3 = if it.on then Col.ink else Col.sub, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(12, 0), ZIndex = 83 })
		row.Activated:Connect(function()
			Ui.sfx("tap")
			Ui.closeMenu()
			onPick(it)
		end)
		first = first or row
	end
	if first and Ui.metrics().gamepad then
		Ui.select(first)
	end
end

-- Toasts --------------------------------------------------------------------------------------------------
local toastGui: ScreenGui? = nil
function Ui.toast(data: { [string]: any })
	if K and type(K.toast) == "function" then
		if pcall(K.toast, { kind = data.kind or "info", icon = data.icon, title = data.title, body = data.body, force = data.force }) then
			return
		end
	end
	if not toastGui then
		toastGui = Ui.screen("GwangalliCarDealerToast", 45)
		;(toastGui :: ScreenGui).Enabled = true
	end
	local g = toastGui :: ScreenGui
	local m = Ui.metrics()
	local w = math.min(420, m.w - 32)
	local t = Ui.glass(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, m.inset + 10), Size = UDim2.fromOffset(w, 64), BackgroundColor3 = Col.glass2, ZIndex = 50 })
	Ui.pad(t, 14, 14, 10, 10)
	Ui.label(t, { Text = (data.icon and (data.icon .. "  ") or "") .. (data.title or ""), Font = F.bold, TextSize = 15, Size = UDim2.new(1, 0, 0, 20), ZIndex = 51 })
	Ui.label(t, { Text = data.body or "", Font = F.reg, TextSize = 13, TextColor3 = Col.sub, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 51 })
	Ui.sfx("notify")
	task.delay(3.6, function()
		Ui.tween(t, 0.3, { BackgroundTransparency = 1 })
		task.wait(0.3)
		t:Destroy()
	end)
end

-- Character controls / blur / selection ---------------------------------------------------------------------
local controlsOff: { [string]: boolean } = {}
local controlsObj: any = nil
local function controls(): any
	if controlsObj then
		return controlsObj
	end
	pcall(function()
		local ps = player:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if pm then
			controlsObj = (require(pm :: ModuleScript) :: any):GetControls()
		end
	end)
	return controlsObj
end
function Ui.controls(key: string, enabled: boolean)
	controlsOff[key] = if enabled then nil else true
	if not UserInputService.TouchEnabled then
		return
	end
	local c = controls()
	if not c then
		return
	end
	pcall(function()
		if next(controlsOff) then
			c:Disable()
		else
			c:Enable()
		end
	end)
end

local blurKeys: { [string]: boolean } = {}
local blurFx: BlurEffect? = nil
function Ui.blur(on: boolean, key: string)
	if K and type(K.blur) == "function" then
		if pcall(K.blur, on, "GwCarDealer_" .. key) then
			return
		end
	end
	blurKeys[key] = if on then true else nil
	pcall(function()
		local want = next(blurKeys) ~= nil
		if want and not (blurFx and blurFx.Parent) then
			blurFx = make("BlurEffect", { Name = "GwangalliCarDealerBlur", Size = 0 }, workspace.CurrentCamera)
		end
		if blurFx then
			Ui.tween(blurFx, 0.25, { Size = if want then 14 else 0 })
		end
	end)
end

function Ui.select(obj: GuiObject?)
	pcall(function()
		if obj and (UserInputService.GamepadEnabled) then
			GuiService.SelectedObject = obj
		end
	end)
end

function Ui.deselect(root: Instance)
	pcall(function()
		local sel = GuiService.SelectedObject
		if sel and sel:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
	end)
end

-- ContextActionService wrappers (pcall: never break a screen over an input binding)
function Ui.bind(name: string, fn: (string, Enum.UserInputState, InputObject) -> any, touchButton: boolean, priority: number, ...: Enum.KeyCode)
	local keys = { ... }
	pcall(function()
		game:GetService("ContextActionService"):BindActionAtPriority(name, fn, touchButton, priority, table.unpack(keys))
	end)
end

function Ui.unbind(name: string)
	pcall(function()
		game:GetService("ContextActionService"):UnbindAction(name)
	end)
end

-- Runs fn once when inst is destroyed / leaves the DataModel.
function Ui.onDestroy(inst: Instance, fn: () -> ())
	local fired = false
	local function once()
		if not fired then
			fired = true
			fn()
		end
	end
	local ok = pcall(function()
		inst.Destroying:Connect(once)
	end)
	if not ok then
		inst.AncestryChanged:Connect(function()
			if not inst:IsDescendantOf(game) then
				once()
			end
		end)
	end
end

-- Loads GwangalliUI (K) when present (toasts / feedback / blur match the game).
function Ui.loadK(): any
	local m = ReplicatedStorage:FindFirstChild("GwangalliUI")
	if m and m:IsA("ModuleScript") then
		local ok, k = pcall(require, m)
		if ok and type(k) == "table" then
			K = k
			return k
		end
	end
	return nil
end

return Ui
