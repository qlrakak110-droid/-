--!strict
-- GwangalliDecorPlus/Ui: the add-on's UI kit, styled like the place's GwangalliUI (glass navy panels,
-- cyan / magenta / gold accents, Gotham) but self-contained. Touch targets >= 44 px at the smallest
-- scale; one UIScale per root follows the viewport (phones, tablets, PC, console 10-foot).
--   Ui.C (colours) / Ui.F (fonts) / Ui.new(class, props, children?) / Ui.corner / Ui.stroke / Ui.pad / Ui.list
--   Ui.label / Ui.button / Ui.chip / Ui.panel / Ui.scroll / Ui.textbox / Ui.toggle / Ui.segmented / Ui.bar
--   Ui.toast(text, kind?) / Ui.modal(title, opts) / Ui.confirm(opts) / Ui.scale(gui) / Ui.isTouch()

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Ui = {}

Ui.C = {
	bg = Color3.fromRGB(10, 12, 20),
	glass = Color3.fromRGB(15, 18, 31),
	glass2 = Color3.fromRGB(23, 27, 44),
	card = Color3.fromRGB(25, 29, 45),
	card2 = Color3.fromRGB(37, 42, 61),
	card3 = Color3.fromRGB(54, 60, 84),
	line = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(245, 247, 251),
	sub = Color3.fromRGB(170, 177, 196),
	faint = Color3.fromRGB(116, 124, 146),
	cyan = Color3.fromRGB(61, 214, 245),
	magenta = Color3.fromRGB(255, 79, 163),
	gold = Color3.fromRGB(255, 194, 71),
	violet = Color3.fromRGB(139, 108, 255),
	green = Color3.fromRGB(61, 220, 132),
	orange = Color3.fromRGB(255, 176, 32),
	red = Color3.fromRGB(255, 90, 95),
	onAccent = Color3.fromRGB(4, 22, 32),
	onGold = Color3.fromRGB(44, 28, 0),
}
Ui.GLASS_T = 0.12
Ui.F = { regular = Enum.Font.Gotham, medium = Enum.Font.GothamMedium, bold = Enum.Font.GothamBold, heavy = Enum.Font.GothamBlack }

function Ui.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Ui.isGamepad(): boolean
	return UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled
end

function Ui.new(class: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(class)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(inst: Instance, r: number?): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, r or 12), Parent = inst })
end

function Ui.stroke(inst: Instance, color: Color3?, transparency: number?, thickness: number?): UIStroke
	return Ui.new("UIStroke", { Color = color or Ui.C.line, Transparency = transparency or 0.86, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst })
end

function Ui.pad(inst: Instance, l: number, t: number?, r: number?, b: number?): UIPadding
	return Ui.new("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingTop = UDim.new(0, t or l),
		PaddingRight = UDim.new(0, r or l),
		PaddingBottom = UDim.new(0, b or t or l),
		Parent = inst,
	})
end

function Ui.list(inst: Instance, dir: string?, padding: number?, halign: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?): UIListLayout
	return Ui.new("UIListLayout", {
		FillDirection = if dir == "x" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
		Parent = inst,
	})
end

function Ui.label(parent: Instance?, text: string, size: number?, color: Color3?, font: Enum.Font?, props: { [string]: any }?): TextLabel
	local l = Ui.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size or 15,
		TextColor3 = color or Ui.C.text,
		Font = font or Ui.F.medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		RichText = true,
		Size = UDim2.new(1, 0, 0, (size or 15) + 8),
		Parent = parent,
	})
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	return l
end

local STYLES = {
	primary = { bg = Ui.C.cyan, fg = Ui.C.onAccent, t = 0 },
	gold = { bg = Ui.C.gold, fg = Ui.C.onGold, t = 0 },
	magenta = { bg = Ui.C.magenta, fg = Color3.new(1, 1, 1), t = 0 },
	green = { bg = Ui.C.green, fg = Ui.C.onAccent, t = 0 },
	danger = { bg = Ui.C.red, fg = Color3.new(1, 1, 1), t = 0 },
	tonal = { bg = Ui.C.card2, fg = Ui.C.text, t = 0.05 },
	ghost = { bg = Ui.C.card, fg = Ui.C.text, t = 0.35 },
}

-- press feedback (scale) for any GuiButton
function Ui.pressable(btn: GuiButton)
	local sc = btn:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = btn })
	local function tw(v: number)
		TweenService:Create(sc, TweenInfo.new(0.08, Enum.EasingStyle.Quad), { Scale = v }):Play()
	end
	btn.MouseButton1Down:Connect(function()
		tw(0.94)
	end)
	btn.MouseButton1Up:Connect(function()
		tw(1)
	end)
	btn.MouseLeave:Connect(function()
		tw(1)
	end)
	btn.SelectionGained:Connect(function()
		tw(1.04)
	end)
	btn.SelectionLost:Connect(function()
		tw(1)
	end)
end

-- opts = { text, style, w (px or scale UDim2), h, size (text), onClick, order, icon }
function Ui.button(parent: Instance?, opts: any): TextButton
	local st = STYLES[opts.style or "tonal"] or STYLES.tonal
	local b = Ui.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = st.bg,
		BackgroundTransparency = st.t,
		Text = opts.text or "",
		TextColor3 = st.fg,
		TextSize = opts.size or 15,
		Font = Ui.F.bold,
		TextWrapped = true,
		RichText = true,
		Size = if typeof(opts.w) == "UDim2" then opts.w elseif opts.auto then UDim2.new(0, opts.w or 0, 0, opts.h or 44) else UDim2.new(0, opts.w or 120, 0, opts.h or 44),
		LayoutOrder = opts.order or 0,
		Selectable = true,
		Parent = parent,
	})
	if opts.auto then
		b.AutomaticSize = Enum.AutomaticSize.X
		Ui.pad(b, 14, 0, 14, 0)
	end
	Ui.corner(b, opts.radius or 12)
	if st.t > 0 then
		Ui.stroke(b, Ui.C.line, 0.88)
	end
	Ui.pressable(b)
	if opts.onClick then
		b.Activated:Connect(function()
			opts.onClick(b)
		end)
	end
	;(b :: any):SetAttribute("DPStyle", opts.style or "tonal")
	return b
end

function Ui.restyle(b: TextButton, style: string)
	local st = STYLES[style] or STYLES.tonal
	b.BackgroundColor3 = st.bg
	b.BackgroundTransparency = st.t
	b.TextColor3 = st.fg
	b:SetAttribute("DPStyle", style)
end

-- toggle chip: returns the button + set(selected)
function Ui.chip(parent: Instance?, text: string, selected: boolean, onClick: ((TextButton) -> ())?, order: number?): (TextButton, (boolean) -> ())
	local b = Ui.new("TextButton", {
		AutoButtonColor = false,
		Text = text,
		TextSize = 14,
		Font = Ui.F.bold,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 38),
		LayoutOrder = order or 0,
		Selectable = true,
		Parent = parent,
	})
	Ui.pad(b, 14, 0, 14, 0)
	Ui.corner(b, 19)
	local stroke = Ui.stroke(b, Ui.C.line, 0.85)
	local function set(on: boolean)
		b.BackgroundColor3 = if on then Ui.C.cyan else Ui.C.card2
		b.BackgroundTransparency = if on then 0 else 0.1
		b.TextColor3 = if on then Ui.C.onAccent else Ui.C.text
		stroke.Transparency = if on then 1 else 0.85
		b:SetAttribute("On", on)
	end
	set(selected)
	Ui.pressable(b)
	if onClick then
		b.Activated:Connect(function()
			onClick(b)
		end)
	end
	return b, set
end

function Ui.panel(parent: Instance?, props: { [string]: any }?): Frame
	local f = Ui.new("Frame", {
		BackgroundColor3 = Ui.C.glass,
		BackgroundTransparency = Ui.GLASS_T,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	Ui.corner(f, 16)
	Ui.stroke(f, Ui.C.line, 0.88)
	Ui.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.08) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 206, 230)),
		Parent = f,
	})
	return f
end

function Ui.scroll(parent: Instance?, props: { [string]: any }?): ScrollingFrame
	local s = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Ui.C.sub,
		ScrollBarImageTransparency = 0.4,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(s :: any)[k] = v
		end
	end
	return s
end

function Ui.textbox(parent: Instance?, placeholder: string, props: { [string]: any }?): TextBox
	local t = Ui.new("TextBox", {
		BackgroundColor3 = Ui.C.card,
		BackgroundTransparency = 0.05,
		PlaceholderText = placeholder,
		PlaceholderColor3 = Ui.C.faint,
		Text = "",
		TextColor3 = Ui.C.text,
		TextSize = 15,
		Font = Ui.F.medium,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = parent,
	})
	Ui.corner(t, 12)
	Ui.stroke(t, Ui.C.line, 0.85)
	Ui.pad(t, 12, 0, 12, 0)
	if props then
		for k, v in props do
			(t :: any)[k] = v
		end
	end
	return t
end

-- switch row: label + pill switch
function Ui.toggle(parent: Instance?, text: string, value: boolean, onChange: (boolean) -> ()): (Frame, (boolean) -> ())
	local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = parent })
	Ui.label(row, text, 15, Ui.C.text, Ui.F.medium, { Size = UDim2.new(1, -70, 1, 0) })
	local sw = Ui.new("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.new(0, 54, 0, 30), Position = UDim2.new(1, -56, 0.5, -15), Parent = row, Selectable = true })
	Ui.corner(sw, 15)
	local knob = Ui.new("Frame", { Size = UDim2.new(0, 24, 0, 24), BackgroundColor3 = Color3.new(1, 1, 1), Parent = sw })
	Ui.corner(knob, 12)
	local cur = value
	local function set(v: boolean)
		cur = v
		sw.BackgroundColor3 = if v then Ui.C.cyan else Ui.C.card3
		TweenService:Create(knob, TweenInfo.new(0.12), { Position = if v then UDim2.new(1, -27, 0.5, -12) else UDim2.new(0, 3, 0.5, -12) }):Play()
	end
	set(value)
	sw.Activated:Connect(function()
		set(not cur)
		onChange(cur)
	end)
	return row, set
end

-- options = { {id, text} }; returns frame + set(id)
function Ui.segmented(parent: Instance?, options: { any }, value: any, onChange: (any) -> ()): (Frame, (any) -> ())
	local f = Ui.new("Frame", { BackgroundColor3 = Ui.C.card, BackgroundTransparency = 0.05, Size = UDim2.new(1, 0, 0, 40), Parent = parent })
	Ui.corner(f, 12)
	Ui.list(f, "x", 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	Ui.pad(f, 4)
	local btns = {}
	local function set(id: any)
		for oid, b in btns do
			local on = oid == id
			b.BackgroundColor3 = if on then Ui.C.cyan else Ui.C.card
			b.BackgroundTransparency = if on then 0 else 1
			b.TextColor3 = if on then Ui.C.onAccent else Ui.C.sub
		end
	end
	for i, o in options do
		local b = Ui.new("TextButton", {
			AutoButtonColor = false,
			Text = o[2],
			TextSize = 14,
			Font = Ui.F.bold,
			Size = UDim2.new(1 / #options, -4, 1, 0),
			LayoutOrder = i,
			Selectable = true,
			Parent = f,
		})
		Ui.corner(b, 9)
		btns[o[1]] = b
		b.Activated:Connect(function()
			set(o[1])
			onChange(o[1])
		end)
	end
	set(value)
	return f, set
end

function Ui.bar(parent: Instance?, frac: number, color: Color3?): Frame
	local track = Ui.new("Frame", { BackgroundColor3 = Ui.C.card3, BackgroundTransparency = 0.2, Size = UDim2.new(1, 0, 0, 8), Parent = parent })
	Ui.corner(track, 4)
	local fill = Ui.new("Frame", { BackgroundColor3 = color or Ui.C.cyan, Size = UDim2.new(math.clamp(frac, 0, 1), 0, 1, 0), Parent = track })
	Ui.corner(fill, 4)
	return track
end

-------------------------------------------------------------------------------------------------
-- Root GUI + scale
-------------------------------------------------------------------------------------------------
function Ui.screen(name: string, order: number): ScreenGui
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local g = Ui.new("ScreenGui", { Name = name, ResetOnSpawn = false, DisplayOrder = order, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	pcall(function()
		(g :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	g.Parent = pg
	return g
end

-- one UIScale per gui following the viewport
function Ui.scale(gui: Instance): UIScale
	local sc = Ui.new("UIScale", { Parent = gui })
	local function update()
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		local s = math.min(vp.X / 1180, vp.Y / 700)
		local lo = if UserInputService.TouchEnabled then 0.82 else 0.7
		if GuiService:IsTenFootInterface() then
			s = math.max(s, 1.15)
		end
		sc.Scale = math.clamp(s, lo, 1.25)
	end
	update()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return sc
end

function Ui.viewport(): Vector2
	local cam = workspace.CurrentCamera
	return if cam then cam.ViewportSize else Vector2.new(1280, 720)
end

function Ui.portrait(): boolean
	local v = Ui.viewport()
	return v.Y > v.X * 1.05
end

-------------------------------------------------------------------------------------------------
-- Toasts
-------------------------------------------------------------------------------------------------
local toastGui: ScreenGui? = nil
local toastHolder: Frame? = nil
function Ui.toast(text: string, kind: string?)
	if not toastGui or not toastGui.Parent then
		toastGui = Ui.screen("GwangalliDecorPlusToast", 40)
		Ui.scale(toastGui :: ScreenGui)
		toastHolder = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 560, 0, 220), Position = UDim2.new(0.5, -280, 0, 64), Parent = toastGui })
		Ui.list(toastHolder :: Frame, "y", 6, Enum.HorizontalAlignment.Center)
	end
	local col = if kind == "bad" then Ui.C.red elseif kind == "good" then Ui.C.green elseif kind == "gold" then Ui.C.gold else Ui.C.cyan
	local t = Ui.panel(toastHolder, { AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0.06 })
	Ui.pad(t, 16, 10, 16, 10)
	local bar = Ui.new("Frame", { BackgroundColor3 = col, Size = UDim2.new(0, 4, 1, 0), Position = UDim2.new(0, -10, 0, 0), Parent = t })
	Ui.corner(bar, 2)
	local l = Ui.label(t, text, 15, Ui.C.text, Ui.F.bold, { AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(0, 0, 0, 0), TextWrapped = false })
	local cons = Ui.new("UISizeConstraint", { MaxSize = Vector2.new(540, 200), Parent = l })
	local _ = cons
	l.TextWrapped = true
	local holder = toastHolder :: Frame
	local n = 0
	for _, c in holder:GetChildren() do
		if c:IsA("Frame") then
			n += 1
		end
	end
	if n > 4 then
		for _, c in holder:GetChildren() do
			if c:IsA("Frame") and c ~= t then
				c:Destroy()
				break
			end
		end
	end
	task.delay(if kind == "bad" then 3.6 else 2.8, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
			task.wait(0.27)
			t:Destroy()
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Modal sheet (centred card on PC / landscape, bottom sheet on portrait phones)
-------------------------------------------------------------------------------------------------
-- opts = { gui, w, h (fraction of viewport height), onClose }
function Ui.modal(title: string, opts: any): any
	local gui = opts.gui
	local dim = Ui.new("TextButton", { Name = "DPModal", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, Size = UDim2.new(1, 0, 1, 0), ZIndex = 50, Selectable = false, Parent = gui })
	local portrait = Ui.portrait()
	local w = opts.w or 520
	local card = Ui.panel(dim, {
		ZIndex = 51,
		Size = if portrait then UDim2.new(1, -16, opts.h or 0.78, 0) else UDim2.new(0, w, opts.h or 0.8, 0),
		Position = if portrait then UDim2.new(0, 8, 1 - (opts.h or 0.78), -8) else UDim2.new(0.5, -w / 2, 0.5 - (opts.h or 0.8) / 2, 0),
		BackgroundTransparency = 0.04,
		Active = true,
	})
	local head = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), ZIndex = 52, Parent = card })
	Ui.label(head, title, 19, Ui.C.text, Ui.F.heavy, { Position = UDim2.new(0, 18, 0, 0), Size = UDim2.new(1, -80, 1, 0), ZIndex = 52 })
	local m: any = { dim = dim, card = card }
	local closeBtn = Ui.button(head, { text = "✕", w = 44, h = 44, style = "ghost", onClick = function()
		m.close()
	end })
	closeBtn.Position = UDim2.new(1, -52, 0, 4)
	closeBtn.ZIndex = 53
	local body = Ui.scroll(card, { Position = UDim2.new(0, 14, 0, 54), Size = UDim2.new(1, -28, 1, -64), ZIndex = 52 })
	Ui.list(body, "y", 10)
	Ui.pad(body, 2, 2, 6, 12)
	m.body = body
	m.head = head
	local closed = false
	function m.close()
		if closed then
			return
		end
		closed = true
		dim:Destroy()
		if opts.onClose then
			opts.onClose()
		end
	end
	dim.Activated:Connect(function()
		m.close()
	end)
	card.Position += UDim2.new(0, 0, 0, 24)
	TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = card.Position - UDim2.new(0, 0, 0, 24) }):Play()
	if Ui.isGamepad() then
		GuiService.SelectedObject = closeBtn
	end
	return m
end

-- opts = { gui, title, body, ok, cancel, okStyle, onOk, onCancel }
function Ui.confirm(opts: any)
	local m = Ui.modal(opts.title, { gui = opts.gui, w = 420, h = 0.42 })
	Ui.label(m.body, opts.body or "", 15, Ui.C.sub, Ui.F.medium, { AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), ZIndex = 53 })
	local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), ZIndex = 53, Parent = m.body })
	Ui.list(row, "x", 10, Enum.HorizontalAlignment.Right)
	local c = Ui.button(row, { text = opts.cancel or "취소", w = 120, h = 46, style = "tonal", onClick = function()
		m.close()
		if opts.onCancel then
			opts.onCancel()
		end
	end })
	c.ZIndex = 53
	local o = Ui.button(row, { text = opts.ok or "확인", w = 150, h = 46, style = opts.okStyle or "primary", onClick = function()
		m.close()
		if opts.onOk then
			opts.onOk()
		end
	end })
	o.ZIndex = 53
	if Ui.isGamepad() then
		GuiService.SelectedObject = o
	end
	return m
end

-- ZIndex for everything inside a modal body
function Ui.lift(root: Instance, z: number)
	if root:IsA("GuiObject") then
		root.ZIndex = z
	end
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = z
		end
	end
end

return Ui
