-- GwangalliKaraokePlus/Kit (client): a small UI kit in the look of the game's GwangalliUI (dark glass,
-- cyan / magenta / gold, rounded cards), sized for phones, PCs and gamepads.
--   Kit.gui                       PlayerGui.GwangalliKaraokePlus (ScreenGui, safe-area insets, UIScale)
--   Kit.new(class, props, parent) Kit.corner / stroke / pad / list / grad
--   Kit.text(parent, props)       Kit.btn(parent, opts)   Kit.chip(parent, opts)
--   Kit.sheet(name, opts) -> sheet { root, body, header, title, sub, open(), close(), isOpen }
--   Kit.slider(parent, opts) -> { frame, set(v) }     Kit.confirm(title, body, yes, no, fn)
--   Kit.toast(title, body?, tone?)  Kit.sound(name)  Kit.tween(inst, t, props, style?)
--   Kit.size() -> W, H (design units after UIScale)  Kit.touch() / Kit.gamepad()

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = {}

local K: any
local player = Players.LocalPlayer

Kit.C = {
	bg = Color3.fromRGB(10, 12, 20),
	glass = Color3.fromRGB(15, 18, 31),
	glass2 = Color3.fromRGB(23, 27, 44),
	card = Color3.fromRGB(25, 29, 45),
	card2 = Color3.fromRGB(37, 42, 61),
	card3 = Color3.fromRGB(54, 60, 84),
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
	white = Color3.new(1, 1, 1),
	black = Color3.new(0, 0, 0),
}
local C = Kit.C

Kit.F = {
	black = Enum.Font.GothamBlack,
	bold = Enum.Font.GothamBold,
	medium = Enum.Font.GothamMedium,
	reg = Enum.Font.Gotham,
}
local F = Kit.F

local UI: any = nil -- the game's GwangalliUI (its 설정 sound mute is respected), optional
local scaleObj: UIScale
local designW, designH = 1280, 720
local sheets: { any } = {}
local toastHolder: Frame

function Kit.rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

function Kit.new(class: string, props: { [string]: any }?, parent: Instance?): any
	local inst = Instance.new(class)
	if props then
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local new = Kit.new

function Kit.corner(parent: Instance, r: number?): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, r or 12) }, parent)
end

function Kit.stroke(parent: Instance, color: Color3?, thick: number?, transp: number?): UIStroke
	return new("UIStroke", { Color = color or C.white, Thickness = thick or 1, Transparency = transp or 0.85, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

function Kit.pad(parent: Instance, l: number, t: number?, r: number?, b: number?): UIPadding
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingTop = UDim.new(0, t or l),
		PaddingRight = UDim.new(0, r or l),
		PaddingBottom = UDim.new(0, b or t or l),
	}, parent)
end

function Kit.list(parent: Instance, dir: string?, gap: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return new("UIListLayout", {
		FillDirection = if dir == "h" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
	}, parent)
end

function Kit.grad(parent: Instance, a: Color3, b: Color3, rot: number?, transp: NumberSequence?): UIGradient
	return new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rot or 90, Transparency = transp or NumberSequence.new(0) }, parent)
end

function Kit.tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

function Kit.text(parent: Instance, props: { [string]: any }): TextLabel
	local p = {
		BackgroundTransparency = 1,
		Font = F.bold,
		TextColor3 = C.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		RichText = false,
		Size = UDim2.new(1, 0, 0, 22),
	}
	for k, v in props do
		p[k] = v
	end
	return new("TextLabel", p, parent)
end

local STYLE = {
	primary = { bg = C.cyan, fg = Color3.fromRGB(6, 20, 30) },
	magenta = { bg = C.magenta, fg = C.white },
	gold = { bg = C.gold, fg = Color3.fromRGB(40, 26, 0) },
	secondary = { bg = C.card2, fg = C.text },
	ghost = { bg = C.card, fg = C.sub },
	danger = { bg = C.red, fg = C.white },
	green = { bg = C.green, fg = Color3.fromRGB(4, 30, 14) },
}
Kit.STYLE = STYLE

-- opts: text, style, size, pos, anchor, textSize, font, onClick, radius, order, name, sound (false = silent)
function Kit.btn(parent: Instance, opts: { [string]: any }): TextButton
	local st = STYLE[opts.style or "secondary"] or STYLE.secondary
	local b = new("TextButton", {
		Name = opts.name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = st.bg,
		BorderSizePixel = 0,
		Size = opts.size or UDim2.fromOffset(120, 44),
		Position = opts.pos or UDim2.new(),
		AnchorPoint = opts.anchor or Vector2.zero,
		Font = opts.font or F.bold,
		Text = opts.text or "",
		TextColor3 = st.fg,
		TextSize = opts.textSize or 16,
		TextWrapped = true,
		LayoutOrder = opts.order or 0,
		Selectable = true,
		ZIndex = opts.z or 1,
	}, parent)
	Kit.corner(b, opts.radius or 12)
	local scale = new("UIScale", { Scale = 1 }, b)
	b.MouseEnter:Connect(function()
		Kit.tween(b, 0.12, { BackgroundTransparency = 0.12 })
	end)
	b.MouseLeave:Connect(function()
		Kit.tween(b, 0.12, { BackgroundTransparency = 0 })
	end)
	b.MouseButton1Down:Connect(function()
		Kit.tween(scale, 0.08, { Scale = 0.95 })
	end)
	b.MouseButton1Up:Connect(function()
		Kit.tween(scale, 0.12, { Scale = 1 })
	end)
	if opts.onClick then
		b.Activated:Connect(function()
			Kit.tween(scale, 0.12, { Scale = 1 })
			if opts.sound ~= false then
				Kit.sound("tap")
			end
			local ok, err = pcall(opts.onClick, b)
			if not ok then
				warn("[GwangalliKaraokePlus] button:", err)
			end
		end)
	end
	return b
end

function Kit.restyle(b: TextButton, style: string)
	local st = STYLE[style] or STYLE.secondary
	b.BackgroundColor3 = st.bg
	b.TextColor3 = st.fg
end

function Kit.chip(parent: Instance, opts: { [string]: any }): TextButton
	opts.size = opts.size or UDim2.fromOffset(0, 34)
	opts.textSize = opts.textSize or 14
	opts.radius = 17
	local b = Kit.btn(parent, opts)
	b.AutomaticSize = Enum.AutomaticSize.X
	Kit.pad(b, 14, 0, 14, 0)
	return b
end

-------------------------------------------------------------------------------------------------
-- sounds (UI only; the band has its own pool)
-------------------------------------------------------------------------------------------------
local soundFolder: Folder
local SOUNDS = {
	tap = { id = "rbxasset://sounds/clickfast.wav", vol = 0.35, speed = 1.1 },
	ping = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.35, speed = 1 },
	swoosh = { id = "rbxasset://sounds/swoosh.wav", vol = 0.3, speed = 1.2 },
	coin = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.45, speed = 1.6 },
	error = { id = "rbxasset://sounds/clickfast.wav", vol = 0.4, speed = 0.55 },
}

function Kit.muted(): boolean
	return UI ~= nil and type(UI.settings) == "table" and UI.settings.sound == false
end

function Kit.sound(name: string)
	if Kit.muted() then
		return
	end
	local def = SOUNDS[name]
	if not def then
		return
	end
	local s = soundFolder:FindFirstChild(name) :: Sound?
	if not s then
		s = new("Sound", { Name = name, SoundId = def.id, Volume = def.vol, PlaybackSpeed = def.speed }, soundFolder)
	end
	local snd = s :: Sound
	snd.TimePosition = 0
	snd:Play()
	if name == "coin" then
		task.delay(0.09, function()
			snd.PlaybackSpeed = 2.1
			snd.TimePosition = 0
			snd:Play()
			task.delay(0.3, function()
				snd.PlaybackSpeed = def.speed
			end)
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- toasts
-------------------------------------------------------------------------------------------------
local TONE = { info = C.cyan, success = C.green, warn = C.orange, error = C.red, gold = C.gold }

function Kit.toast(title: string, body: string?, tone: string?)
	local f = new("Frame", {
		Size = UDim2.fromOffset(380, if body and body ~= "" then 62 else 44),
		BackgroundColor3 = C.glass,
		BackgroundTransparency = 0.06,
		LayoutOrder = -math.floor(os.clock() * 100),
	}, toastHolder)
	Kit.corner(f, 14)
	Kit.stroke(f, TONE[tone or "info"] or C.cyan, 1.5, 0.35)
	Kit.pad(f, 14, 8)
	Kit.text(f, { Text = title, TextSize = 16, Size = UDim2.new(1, 0, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
	if body and body ~= "" then
		Kit.text(f, { Text = body, Font = F.medium, TextSize = 13, TextColor3 = C.sub, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd })
	end
	if tone == "warn" or tone == "error" then
		Kit.sound("error")
	else
		Kit.sound("ping")
	end
	task.delay(3.6, function()
		if f.Parent then
			Kit.tween(f, 0.25, { BackgroundTransparency = 1 })
			for _, d in f:GetDescendants() do
				if d:IsA("TextLabel") then
					Kit.tween(d, 0.25, { TextTransparency = 1 })
				elseif d:IsA("UIStroke") then
					Kit.tween(d, 0.25, { Transparency = 1 })
				end
			end
			task.wait(0.3)
			f:Destroy()
		end
	end)
	local kids = {}
	for _, c in toastHolder:GetChildren() do
		if c:IsA("Frame") then
			table.insert(kids, c)
		end
	end
	if #kids > 3 then
		table.sort(kids, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		kids[1]:Destroy()
	end
end

-------------------------------------------------------------------------------------------------
-- layout helpers
-------------------------------------------------------------------------------------------------
function Kit.size(): (number, number)
	return designW, designH
end

function Kit.touch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Kit.gamepad(): boolean
	local t = UserInputService:GetLastInputType()
	return t == Enum.UserInputType.Gamepad1 or t == Enum.UserInputType.Gamepad2
end

function Kit.select(obj: GuiObject?)
	if obj and Kit.gamepad() then
		pcall(function()
			GuiService.SelectedObject = obj
		end)
	end
end

local layoutFns: { () -> () } = {}
function Kit.onLayout(fn: () -> ())
	table.insert(layoutFns, fn)
	pcall(fn)
end

local function relayout()
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local s = math.clamp(math.min(vp.X / 1100, vp.Y / 640), 0.7, 1.15)
	scaleObj.Scale = s
	local inset = GuiService:GetGuiInset()
	designW = vp.X / s
	designH = (vp.Y - inset.Y) / s
	for _, fn in layoutFns do
		pcall(fn)
	end
end

-------------------------------------------------------------------------------------------------
-- sheets (modal panels: 노래책, 리모컨, 결제 ...)
-------------------------------------------------------------------------------------------------
function Kit.closeAll(except: any?)
	for _, sh in sheets do
		if sh ~= except and sh.isOpen then
			sh.close()
		end
	end
end

function Kit.anyOpen(): boolean
	for _, sh in sheets do
		if sh.isOpen then
			return true
		end
	end
	return false
end

-- opts: title, sub, w, h, accent, scroll (default true)
function Kit.sheet(name: string, opts: { [string]: any }): any
	local root = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(opts.w or 560, opts.h or 600),
		BackgroundColor3 = C.glass,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 20,
		Active = true,
	}, Kit.gui)
	Kit.corner(root, 22)
	Kit.stroke(root, opts.accent or C.cyan, 1.5, 0.55)
	Kit.grad(root, Color3.fromRGB(28, 32, 54), Color3.fromRGB(12, 14, 24), 90)
	local sc = new("UIScale", { Scale = 1 }, root)
	local header = new("Frame", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 62), ZIndex = 21 }, root)
	Kit.pad(header, 20, 10, 64, 4)
	local title = Kit.text(header, { Name = "Title", Text = opts.title or "", Font = F.black, TextSize = 21, Size = UDim2.new(1, 0, 0, 28), ZIndex = 21, TextTruncate = Enum.TextTruncate.AtEnd })
	local sub = Kit.text(header, { Name = "Sub", Text = opts.sub or "", Font = F.medium, TextSize = 13, TextColor3 = C.sub, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 18), ZIndex = 21, TextTruncate = Enum.TextTruncate.AtEnd })
	local sheet: any = { root = root, header = header, title = title, sub = sub, isOpen = false, onClose = nil, onOpen = nil, w = opts.w or 560, h = opts.h or 600 }
	local close = Kit.btn(root, {
		name = "Close",
		text = "✕",
		style = "ghost",
		size = UDim2.fromOffset(44, 44),
		pos = UDim2.new(1, -12, 0, 10),
		anchor = Vector2.new(1, 0),
		textSize = 18,
		radius = 22,
		z = 22,
		onClick = function()
			sheet.close()
		end,
	})
	sheet.closeBtn = close
	local body
	if opts.scroll == false then
		body = new("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 1, -64), ZIndex = 21 }, root)
	else
		body = new("ScrollingFrame", {
			Name = "Body",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 64),
			Size = UDim2.new(1, 0, 1, -64),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = C.card3,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = 21,
			Selectable = false,
		}, root)
		Kit.pad(body, 16, 4, 16, 16)
		Kit.list(body, "v", 10)
	end
	sheet.body = body
	local function fit()
		local W, H = Kit.size()
		local w = math.min(sheet.w, W - 20)
		local h = math.min(sheet.h, H - 16)
		root.Size = UDim2.fromOffset(w, h)
	end
	Kit.onLayout(fit)
	function sheet.open()
		if sheet.isOpen then
			return
		end
		Kit.closeAll(sheet)
		fit()
		sheet.isOpen = true
		root.Visible = true
		sc.Scale = 0.92
		Kit.tween(sc, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		Kit.sound("swoosh")
		if sheet.onOpen then
			pcall(sheet.onOpen)
		end
		task.defer(function()
			local first = sheet.focus or close
			Kit.select(first)
		end)
	end
	function sheet.close()
		if not sheet.isOpen then
			return
		end
		sheet.isOpen = false
		root.Visible = false
		pcall(function()
			if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
				GuiService.SelectedObject = nil
			end
		end)
		if sheet.onClose then
			pcall(sheet.onClose)
		end
	end
	function sheet.toggle()
		if sheet.isOpen then
			sheet.close()
		else
			sheet.open()
		end
	end
	table.insert(sheets, sheet)
	return sheet
end

-- horizontal slider; opts: min, max, value, step, w, onChange(v), color
function Kit.slider(parent: Instance, opts: { [string]: any }): any
	local mn, mx = opts.min or 0, opts.max or 1
	local frame = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = opts.order or 0 }, parent)
	local track = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.card3, Size = UDim2.new(1, -16, 0, 8), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Selectable = true }, frame)
	Kit.corner(track, 4)
	local fill = new("Frame", { BackgroundColor3 = opts.color or C.cyan, Size = UDim2.fromScale(0, 1), BorderSizePixel = 0 }, track)
	Kit.corner(fill, 4)
	local knob = new("Frame", { BackgroundColor3 = C.white, Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5) }, track)
	Kit.corner(knob, 11)
	local api = { frame = frame, value = opts.value or mn }
	local function show(v: number)
		local a = (v - mn) / math.max(1e-6, mx - mn)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
	end
	function api.set(v: number)
		api.value = math.clamp(v, mn, mx)
		show(api.value)
	end
	local dragging = false
	local function fromX(x: number)
		local a = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		local v = mn + a * (mx - mn)
		if opts.step then
			v = math.floor(v / opts.step + 0.5) * opts.step
		end
		api.set(v)
		if opts.onChange then
			pcall(opts.onChange, api.value, false)
		end
	end
	track.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(io.Position.X)
		elseif io.KeyCode == Enum.KeyCode.DPadLeft or io.KeyCode == Enum.KeyCode.DPadRight then
			local stp = opts.step or (mx - mn) / 10
			api.set(api.value + (if io.KeyCode == Enum.KeyCode.DPadRight then stp else -stp))
			if opts.onChange then
				pcall(opts.onChange, api.value, true)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
			fromX(io.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			if opts.onChange then
				pcall(opts.onChange, api.value, true)
			end
		end
	end)
	api.set(api.value)
	return api
end

-- a small centred confirm card
local confirmSheet: any = nil
function Kit.confirm(title: string, body: string, yes: string, no: string, fn: (boolean) -> ())
	if not confirmSheet then
		confirmSheet = Kit.sheet("GwKP_Confirm", { title = "", w = 420, h = 230, scroll = false, accent = C.gold })
		local b = confirmSheet.body
		confirmSheet.msg = Kit.text(b, { Text = "", Font = F.medium, TextSize = 15, TextColor3 = C.sub, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -40, 0, 70), ZIndex = 22 })
		confirmSheet.no = Kit.btn(b, { text = "", style = "secondary", size = UDim2.new(0.5, -26, 0, 48), pos = UDim2.new(0, 20, 1, -64), z = 22 })
		confirmSheet.yes = Kit.btn(b, { text = "", style = "magenta", size = UDim2.new(0.5, -26, 0, 48), pos = UDim2.new(0.5, 6, 1, -64), z = 22 })
		confirmSheet.focus = confirmSheet.no
		confirmSheet.no.Activated:Connect(function()
			local cb = confirmSheet.cb
			confirmSheet.cb = nil
			confirmSheet.close()
			if cb then
				task.spawn(cb, false)
			end
		end)
		confirmSheet.yes.Activated:Connect(function()
			local cb = confirmSheet.cb
			confirmSheet.cb = nil
			confirmSheet.close()
			if cb then
				task.spawn(cb, true)
			end
		end)
	end
	confirmSheet.title.Text = title
	confirmSheet.msg.Text = body
	confirmSheet.yes.Text = yes
	confirmSheet.no.Text = no
	confirmSheet.cb = fn
	confirmSheet.open()
end

function Kit.init(k: any)
	K = k
	local okUI, mod = pcall(function()
		local m = ReplicatedStorage:FindFirstChild("GwangalliUI")
		return if m and m:IsA("ModuleScript") then require(m) :: any else nil
	end)
	if okUI and type(mod) == "table" then
		UI = mod
	end
	soundFolder = new("Folder", { Name = "GwKP_UI" }, SoundService)
	local pg = player:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild(k.S.NAMES.Gui)
	if old then
		old:Destroy()
	end
	local gui = new("ScreenGui", {
		Name = k.S.NAMES.Gui,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 44,
	})
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	scaleObj = new("UIScale", { Scale = 1 }, gui)
	Kit.gui = gui
	toastHolder = new("Frame", { Name = "GwKP_Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(380, 240), ZIndex = 60 }, gui)
	Kit.list(toastHolder, "v", 6, Enum.HorizontalAlignment.Center)
	gui.Parent = pg
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local c2 = workspace.CurrentCamera
		if c2 then
			c2:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
			relayout()
		end
	end)
	relayout()
end

return Kit
