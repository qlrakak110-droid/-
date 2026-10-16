-- GwangalliClinic/Ui (client): the clinic's UI kit — premium 의원 look (white paper, teal / mint accents,
-- soft shadows), sized for phones, PCs and gamepads (UIScale relayout, 44 px+ touch targets, gamepad
-- selection on open, ESC / B closes non-critical sheets).
--   Ui.gui                          PlayerGui.GwangalliClinic (ScreenGui)
--   Ui.new / corner / stroke / pad / list / grad / tween / text
--   Ui.btn(parent, opts)            styles: primary · secondary · ghost · danger · dark · gold
--   Ui.chip(parent, opts) -> chip   toggle chip (chip.set(on), chip.on)
--   Ui.pill(parent, text, tone)     Ui.card(parent, props)   Ui.bar(parent, opts) -> { set(frac, color?) }
--   Ui.sheet(name, opts) -> sheet   centred modal card { root, body, title, sub, open(), close(), isOpen }
--   Ui.toast(title, body?, tone?)   Ui.sound(name, speed?)   Ui.ding()
--   Ui.say(who, text, opts?)        staff speech (dialog box with portrait + typewriter, auto hides)
--   Ui.ask(who, text, choices, opts?) -> index?   same box, yields until a choice (nil when aborted)
--   Ui.healthCard(parent, hv, opts?) 건강 상태 카드 (피로도 막대 · 질병 · 원인 · 권장 조치)
--   Ui.paper(parent, props)          document paper (영수증 · 처방전 · 결과지)
--   Ui.row(parent, left, right, opts?)  two-column line
--   Ui.size() / Ui.onLayout(fn) / Ui.touch() / Ui.gamepad() / Ui.select(obj)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ui = {}

local S: any
local C: any
local player = Players.LocalPlayer

Ui.C = {
	teal = Color3.fromRGB(15, 163, 163),
	tealD = Color3.fromRGB(11, 124, 124),
	tealDD = Color3.fromRGB(8, 84, 86),
	mint = Color3.fromRGB(230, 246, 244),
	mint2 = Color3.fromRGB(207, 237, 234),
	white = Color3.fromRGB(255, 255, 255),
	bg = Color3.fromRGB(247, 250, 250),
	paper = Color3.fromRGB(253, 253, 250),
	line = Color3.fromRGB(220, 230, 232),
	ink = Color3.fromRGB(30, 42, 50),
	sub = Color3.fromRGB(95, 107, 115),
	faint = Color3.fromRGB(152, 164, 171),
	red = Color3.fromRGB(229, 72, 77),
	orange = Color3.fromRGB(242, 153, 74),
	green = Color3.fromRGB(46, 184, 114),
	gold = Color3.fromRGB(242, 201, 76),
	blue = Color3.fromRGB(61, 123, 247),
	navy = Color3.fromRGB(26, 40, 74),
	black = Color3.fromRGB(0, 0, 0),
	shadow = Color3.fromRGB(10, 40, 44),
}
local Col = Ui.C

Ui.F = {
	black = Enum.Font.GothamBlack,
	bold = Enum.Font.GothamBold,
	med = Enum.Font.GothamMedium,
	reg = Enum.Font.Gotham,
	mono = Enum.Font.RobotoMono,
}
local F = Ui.F

Ui.TONE = { ok = Col.green, warn = Col.orange, bad = Col.red, info = Col.teal, gold = Col.gold }

Ui.WHO = {
	desk = { icon = "👩‍💼", name = "원무과", color = Col.navy },
	doctor = { icon = "👨‍⚕️", name = "내과 전문의 김선생", color = Col.tealDD },
	nurse = { icon = "👩‍⚕️", name = "간호사 박선생", color = Col.teal },
	nurse2 = { icon = "👩‍⚕️", name = "간호사 최선생", color = Col.teal },
	pharm = { icon = "🧑‍⚕️", name = "약사 정약사", color = Col.green },
	check = { icon = "👩‍🔬", name = "검진센터 한선생", color = Col.blue },
	system = { icon = "🏥", name = "광안 메디컬 의원", color = Col.teal },
}

local scaleObj: UIScale
local designW, designH = 1280, 720
local sheets: { any } = {}
local toastHolder: Frame
local soundFolder: Instance
local UI: any = nil -- the game's GwangalliUI (its sound mute setting), optional

function Ui.new(class: string, props: { [string]: any }?, parent: Instance?): any
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
local new = Ui.new

function Ui.corner(parent: Instance, r: number?): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, r or 12) }, parent)
end

function Ui.stroke(parent: Instance, color: Color3?, thick: number?, transp: number?): UIStroke
	return new("UIStroke", { Color = color or Col.line, Thickness = thick or 1, Transparency = transp or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

function Ui.pad(parent: Instance, l: number, t: number?, r: number?, b: number?): UIPadding
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingTop = UDim.new(0, t or l),
		PaddingRight = UDim.new(0, r or l),
		PaddingBottom = UDim.new(0, b or t or l),
	}, parent)
end

function Ui.list(parent: Instance, dir: string?, gap: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return new("UIListLayout", {
		FillDirection = if dir == "h" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
	}, parent)
end

function Ui.grad(parent: Instance, a: Color3, b: Color3, rot: number?): UIGradient
	return new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rot or 90 }, parent)
end

function Ui.tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

function Ui.text(parent: Instance, props: { [string]: any }): TextLabel
	local p = {
		BackgroundTransparency = 1,
		Font = F.bold,
		TextColor3 = Col.ink,
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
	primary = { bg = Col.teal, fg = Col.white },
	secondary = { bg = Col.mint, fg = Col.tealDD },
	ghost = { bg = Col.white, fg = Col.ink, line = Col.line },
	danger = { bg = Col.red, fg = Col.white },
	dark = { bg = Col.navy, fg = Col.white },
	gold = { bg = Col.gold, fg = Color3.fromRGB(60, 44, 0) },
	disabled = { bg = Color3.fromRGB(232, 236, 238), fg = Col.faint },
}
Ui.STYLE = STYLE

-- opts: text, style, size, pos, anchor, textSize, font, onClick, radius, order, name, z, sound (false)
function Ui.btn(parent: Instance, opts: { [string]: any }): TextButton
	local st = STYLE[opts.style or "secondary"] or STYLE.secondary
	local b = new("TextButton", {
		Name = opts.name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = st.bg,
		BorderSizePixel = 0,
		Size = opts.size or UDim2.fromOffset(140, 46),
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
	Ui.corner(b, opts.radius or 12)
	if st.line then
		Ui.stroke(b, st.line, 1.2, 0)
	end
	local sc = new("UIScale", { Scale = 1 }, b)
	b.MouseEnter:Connect(function()
		Ui.tween(b, 0.12, { BackgroundTransparency = 0.08 })
	end)
	b.MouseLeave:Connect(function()
		Ui.tween(b, 0.12, { BackgroundTransparency = 0 })
	end)
	b.MouseButton1Down:Connect(function()
		Ui.tween(sc, 0.08, { Scale = 0.96 })
	end)
	b.MouseButton1Up:Connect(function()
		Ui.tween(sc, 0.12, { Scale = 1 })
	end)
	if opts.onClick then
		b.Activated:Connect(function()
			if b:GetAttribute("Disabled") then
				Ui.sound("error")
				return
			end
			Ui.tween(sc, 0.12, { Scale = 1 })
			if opts.sound ~= false then
				Ui.sound("tap")
			end
			task.spawn(function()
				local ok, err = pcall(opts.onClick, b)
				if not ok then
					warn("[GwangalliClinic] button:", err)
				end
			end)
		end)
	end
	return b
end

function Ui.restyle(b: TextButton, style: string)
	local st = STYLE[style] or STYLE.secondary
	b.BackgroundColor3 = st.bg
	b.TextColor3 = st.fg
	b:SetAttribute("Disabled", style == "disabled")
end

-- toggle chip. opts: text, on, onChange(on), order
function Ui.chip(parent: Instance, opts: { [string]: any }): any
	local chip: any = { on = opts.on == true }
	local b = new("TextButton", {
		AutoButtonColor = false,
		Text = opts.text or "",
		Font = F.bold,
		TextSize = 14,
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0,
		LayoutOrder = opts.order or 0,
		Selectable = true,
	}, parent)
	Ui.corner(b, 18)
	local stroke = Ui.stroke(b, Col.line, 1.2, 0)
	Ui.pad(b, 14, 0, 14, 0)
	local function paint()
		b.BackgroundColor3 = if chip.on then Col.teal else Col.white
		b.TextColor3 = if chip.on then Col.white else Col.ink
		stroke.Color = if chip.on then Col.teal else Col.line
		b.Text = (if chip.on then "✓ " else "") .. (opts.text or "")
	end
	function chip.set(on: boolean)
		chip.on = on
		paint()
	end
	b.Activated:Connect(function()
		chip.set(not chip.on)
		Ui.sound("tap")
		if opts.onChange then
			pcall(opts.onChange, chip.on)
		end
	end)
	chip.button = b
	paint()
	return chip
end

function Ui.pill(parent: Instance, text: string, tone: string?, order: number?): TextLabel
	local color = Ui.TONE[tone or "info"] or Col.teal
	local l = new("TextLabel", {
		BackgroundColor3 = color,
		BackgroundTransparency = 0.86,
		Text = text,
		TextColor3 = color:Lerp(Col.black, 0.25),
		Font = F.bold,
		TextSize = 13,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order or 0,
	}, parent)
	Ui.corner(l, 13)
	Ui.pad(l, 10, 0, 10, 0)
	return l
end

function Ui.card(parent: Instance, props: { [string]: any }?): Frame
	local p: any = {
		BackgroundColor3 = Col.white,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local f = new("Frame", p, parent)
	Ui.corner(f, (props and props.radius) or 14)
	Ui.stroke(f, Col.line, 1, 0)
	return f
end

-- progress bar. opts: h, color, bg, order -> { frame, fill, set(frac, color?) }
function Ui.bar(parent: Instance, opts: { [string]: any }?): any
	local o = opts or {}
	local frame = new("Frame", { BackgroundColor3 = o.bg or Color3.fromRGB(232, 238, 239), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, o.h or 10), LayoutOrder = o.order or 0 }, parent)
	Ui.corner(frame, math.floor((o.h or 10) / 2))
	local fill = new("Frame", { BackgroundColor3 = o.color or Col.teal, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) }, frame)
	Ui.corner(fill, math.floor((o.h or 10) / 2))
	local api = { frame = frame, fill = fill }
	function api.set(frac: number, color: Color3?, t: number?)
		local a = math.clamp(frac, 0, 1)
		if t and t > 0 then
			Ui.tween(fill, t, { Size = UDim2.fromScale(a, 1) })
		else
			fill.Size = UDim2.fromScale(a, 1)
		end
		if color then
			fill.BackgroundColor3 = color
		end
	end
	return api
end

function Ui.row(parent: Instance, left: string, right: string, opts: { [string]: any }?): Frame
	local o = opts or {}
	local f = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, o.h or 24), LayoutOrder = o.order or 0 }, parent)
	Ui.text(f, { Text = left, Font = o.leftFont or F.med, TextSize = o.size or 14, TextColor3 = o.leftColor or Col.sub, Size = UDim2.new(0.6, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.text(f, { Text = right, Font = o.rightFont or F.bold, TextSize = o.size or 14, TextColor3 = o.rightColor or Col.ink, Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.fromScale(0.6, 0), TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
	return f
end

function Ui.paper(parent: Instance, props: { [string]: any }?): Frame
	local p: any = {
		BackgroundColor3 = Col.paper,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local f = new("Frame", p, parent)
	Ui.corner(f, 6)
	Ui.stroke(f, Color3.fromRGB(214, 222, 222), 1, 0)
	Ui.pad(f, 16, 14, 16, 16)
	Ui.list(f, "v", 6)
	return f
end

-------------------------------------------------------------------------------------------------
-- sounds (built-in only)
-------------------------------------------------------------------------------------------------
local SOUNDS: { [string]: { id: string, vol: number, speed: number } } = {}

function Ui.muted(): boolean
	return UI ~= nil and type(UI.settings) == "table" and UI.settings.sound == false
end

function Ui.sound(name: string, speed: number?)
	if Ui.muted() then
		return
	end
	local def = SOUNDS[name]
	if not def then
		return
	end
	local s = new("Sound", { SoundId = def.id, Volume = def.vol, PlaybackSpeed = speed or def.speed }, soundFolder)
	s:Play()
	task.delay(3, function()
		s:Destroy()
	end)
end

-- 딩-동 (two tones)
function Ui.ding()
	Ui.sound("ding", 1.0)
	task.delay(0.42, function()
		Ui.sound("ding", 0.78)
	end)
end

-------------------------------------------------------------------------------------------------
-- toasts
-------------------------------------------------------------------------------------------------
function Ui.toast(title: string, body: string?, tone: string?)
	local color = Ui.TONE[tone or "info"] or Col.teal
	local f = new("Frame", {
		Size = UDim2.fromOffset(400, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Col.white,
		LayoutOrder = -math.floor(os.clock() * 100),
	}, toastHolder)
	Ui.corner(f, 14)
	Ui.stroke(f, color, 1.5, 0.2)
	Ui.pad(f, 14, 10, 14, 10)
	Ui.list(f, "v", 2)
	new("Frame", { BackgroundColor3 = color, Size = UDim2.new(0, 4, 1, -16), Position = UDim2.fromOffset(-8, 8), BorderSizePixel = 0 }, f)
	Ui.text(f, { Text = title, TextSize = 15, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 20) })
	if body and body ~= "" then
		Ui.text(f, { Text = body, Font = F.med, TextSize = 13, TextColor3 = Col.sub, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 18) })
	end
	Ui.sound(if tone == "warn" or tone == "bad" then "error" else "ping")
	task.delay(4.2, function()
		if f.Parent then
			Ui.tween(f, 0.25, { BackgroundTransparency = 1 })
			for _, d in f:GetDescendants() do
				if d:IsA("TextLabel") then
					Ui.tween(d, 0.25, { TextTransparency = 1 })
				elseif d:IsA("UIStroke") then
					Ui.tween(d, 0.25, { Transparency = 1 })
				elseif d:IsA("Frame") then
					Ui.tween(d, 0.25, { BackgroundTransparency = 1 })
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
-- layout
-------------------------------------------------------------------------------------------------
function Ui.size(): (number, number)
	return designW, designH
end

function Ui.touch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Ui.gamepad(): boolean
	local t = UserInputService:GetLastInputType()
	return t == Enum.UserInputType.Gamepad1 or t == Enum.UserInputType.Gamepad2
end

function Ui.select(obj: GuiObject?)
	if obj and Ui.gamepad() then
		pcall(function()
			GuiService.SelectedObject = obj
		end)
	end
end

local layoutFns: { () -> () } = {}
function Ui.onLayout(fn: () -> ())
	table.insert(layoutFns, fn)
	pcall(fn)
end

local function relayout()
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local s = math.clamp(math.min(vp.X / 1100, vp.Y / 640), 0.62, 1.15)
	scaleObj.Scale = s
	local inset = GuiService:GetGuiInset()
	designW = vp.X / s
	designH = (vp.Y - inset.Y) / s
	for _, fn in layoutFns do
		pcall(fn)
	end
end

-------------------------------------------------------------------------------------------------
-- modal etiquette (blur, touch controls, the game's HUD)
-------------------------------------------------------------------------------------------------
local modalKeys: { [string]: boolean } = {}
local blur: BlurEffect? = nil
local controlsOff = false

local function controls(): any
	local ok, pm = pcall(function()
		local ps = player:WaitForChild("PlayerScripts", 2)
		local mod = ps and ps:FindFirstChild("PlayerModule")
		return mod and require(mod :: ModuleScript) or nil
	end)
	if ok and pm and pm.GetControls then
		local ok2, c = pcall(pm.GetControls, pm)
		if ok2 then
			return c
		end
	end
	return nil
end

function Ui.modal(on: boolean, key: string)
	modalKeys[key] = if on then true else nil
	local any = next(modalKeys) ~= nil
	if any and not blur then
		blur = new("BlurEffect", { Name = "GwClinicBlur", Size = 0 }, Lighting)
		Ui.tween(blur :: BlurEffect, 0.2, { Size = 10 })
	elseif not any and blur then
		local b = blur :: BlurEffect
		blur = nil
		Ui.tween(b, 0.15, { Size = 0 })
		task.delay(0.2, function()
			b:Destroy()
		end)
	end
	Ui.gui:SetAttribute("HideGwangalliHUD", any)
	if Ui.touch() then
		if any and not controlsOff then
			local c = controls()
			if c then
				pcall(c.Disable, c)
				controlsOff = true
			end
		elseif not any and controlsOff then
			local c = controls()
			if c then
				pcall(c.Enable, c)
			end
			controlsOff = false
		end
	end
end

-------------------------------------------------------------------------------------------------
-- sheets
-------------------------------------------------------------------------------------------------
function Ui.closeAll(except: any?)
	for _, sh in sheets do
		if sh ~= except and sh.isOpen and not sh.sticky then
			sh.close()
		end
	end
end

function Ui.anyOpen(): boolean
	for _, sh in sheets do
		if sh.isOpen then
			return true
		end
	end
	return false
end

-- opts: title, sub, w, h, scroll (default true), accent, sticky (not closed by others), noClose, z
function Ui.sheet(name: string, opts: { [string]: any }): any
	local z = opts.z or 20
	local root = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(opts.w or 560, opts.h or 600),
		BackgroundColor3 = Col.bg,
		Visible = false,
		ZIndex = z,
		Active = true,
	}, Ui.gui)
	Ui.corner(root, 20)
	Ui.stroke(root, Col.line, 1, 0)
	-- soft shadow
	local shadow = new("Frame", { Name = "Shadow", BackgroundColor3 = Col.shadow, BackgroundTransparency = 0.82, Size = UDim2.new(1, 10, 1, 12), Position = UDim2.fromOffset(-5, 2), ZIndex = z - 1 }, root)
	Ui.corner(shadow, 24)
	local sc = new("UIScale", { Scale = 1 }, root)
	local header = new("Frame", { Name = "Header", BackgroundColor3 = opts.accent or Col.teal, Size = UDim2.new(1, 0, 0, 64), ZIndex = z + 1 }, root)
	Ui.corner(header, 20)
	new("Frame", { BackgroundColor3 = opts.accent or Col.teal, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -20), ZIndex = z + 1 }, header)
	Ui.grad(header, Color3.new(1, 1, 1), Color3.fromRGB(205, 225, 225), 90)
	local title = Ui.text(header, { Name = "Title", Text = opts.title or "", Font = F.black, TextSize = 20, TextColor3 = Col.white, Position = UDim2.fromOffset(20, 10), Size = UDim2.new(1, -84, 0, 26), ZIndex = z + 2, TextTruncate = Enum.TextTruncate.AtEnd })
	local sub = Ui.text(header, { Name = "Sub", Text = opts.sub or "", Font = F.med, TextSize = 13, TextColor3 = Color3.fromRGB(226, 246, 244), Position = UDim2.fromOffset(20, 36), Size = UDim2.new(1, -84, 0, 18), ZIndex = z + 2, TextTruncate = Enum.TextTruncate.AtEnd })
	local sheet: any = { root = root, header = header, title = title, sub = sub, isOpen = false, sticky = opts.sticky, w = opts.w or 560, h = opts.h or 600 }
	if not opts.noClose then
		sheet.closeBtn = Ui.btn(header, {
			name = "Close",
			text = "✕",
			style = "ghost",
			size = UDim2.fromOffset(44, 44),
			pos = UDim2.new(1, -10, 0, 10),
			anchor = Vector2.new(1, 0),
			textSize = 18,
			radius = 22,
			z = z + 3,
			onClick = function()
				sheet.close()
			end,
		})
	end
	local body
	if opts.scroll == false then
		body = new("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 1, -64), ZIndex = z + 1 }, root)
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
			ScrollBarImageColor3 = Col.faint,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = z + 1,
			Selectable = false,
		}, root)
		Ui.pad(body, 16, 12, 16, 18)
		Ui.list(body, "v", 10)
	end
	sheet.body = body
	local function fit()
		local W, H = Ui.size()
		local w = math.min(sheet.w, W - 16)
		local h = math.min(sheet.h, H - 12)
		root.Size = UDim2.fromOffset(w, h)
	end
	Ui.onLayout(fit)
	function sheet.clear()
		for _, c in body:GetChildren() do
			if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
				c:Destroy()
			end
		end
	end
	function sheet.open()
		if sheet.isOpen then
			return
		end
		Ui.closeAll(sheet)
		fit()
		sheet.isOpen = true
		root.Visible = true
		sc.Scale = 0.94
		Ui.tween(sc, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		Ui.sound("swoosh")
		Ui.modal(true, name)
		task.defer(function()
			Ui.select(sheet.focus or sheet.closeBtn)
		end)
		if sheet.onOpen then
			pcall(sheet.onOpen)
		end
	end
	function sheet.close()
		if not sheet.isOpen then
			return
		end
		sheet.isOpen = false
		root.Visible = false
		Ui.modal(false, name)
		pcall(function()
			if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
				GuiService.SelectedObject = nil
			end
		end)
		if sheet.onClose then
			pcall(sheet.onClose)
		end
	end
	table.insert(sheets, sheet)
	return sheet
end

-------------------------------------------------------------------------------------------------
-- staff dialogue box (portrait + typewriter + choices)
-------------------------------------------------------------------------------------------------
local dlg: any = nil
local dlgToken = 0

local function buildDialog()
	local root = new("Frame", {
		Name = "Dialog",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(720, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Col.white,
		Visible = false,
		ZIndex = 40,
		Active = true,
	}, Ui.gui)
	Ui.corner(root, 18)
	Ui.stroke(root, Col.line, 1, 0)
	local shadow = new("Frame", { BackgroundColor3 = Col.shadow, BackgroundTransparency = 0.85, Size = UDim2.new(1, 8, 1, 10), Position = UDim2.fromOffset(-4, 2), ZIndex = 39 }, root)
	Ui.corner(shadow, 22)
	Ui.pad(root, 16, 14, 16, 14)
	local avatar = new("TextLabel", { Name = "Avatar", BackgroundColor3 = Col.mint, Size = UDim2.fromOffset(60, 60), Text = "👩‍⚕️", TextSize = 34, Font = F.bold, ZIndex = 41 }, root)
	Ui.corner(avatar, 30)
	local avStroke = Ui.stroke(avatar, Col.teal, 2, 0)
	local name = Ui.text(root, { Name = "Who", Text = "", Font = F.black, TextSize = 15, TextColor3 = Col.tealDD, Position = UDim2.fromOffset(74, 0), Size = UDim2.new(1, -74, 0, 20), ZIndex = 41 })
	local body = Ui.text(root, {
		Name = "Text",
		Text = "",
		Font = F.med,
		TextSize = 17,
		TextColor3 = Col.ink,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(74, 24),
		Size = UDim2.new(1, -74, 0, 46),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 41,
	})
	local choices = new("Frame", { Name = "Choices", BackgroundTransparency = 1, Position = UDim2.fromOffset(74, 0), Size = UDim2.new(1, -74, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 41 }, root)
	local cl = Ui.list(choices, "h", 8, Enum.HorizontalAlignment.Left)
	cl.Wraps = true
	local layout = new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, nil)
	layout:Destroy()
	-- stack the text and the choices under the name (manual: avatar is absolute)
	local holder = new("Frame", { Name = "Stack", BackgroundTransparency = 1, Position = UDim2.fromOffset(74, 22), Size = UDim2.new(1, -74, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 41 }, root)
	Ui.list(holder, "v", 10)
	body.Parent = holder
	body.Position = UDim2.new()
	body.Size = UDim2.new(1, 0, 0, 24)
	body.LayoutOrder = 1
	choices.Parent = holder
	choices.Position = UDim2.new()
	choices.Size = UDim2.new(1, 0, 0, 0)
	choices.LayoutOrder = 2
	local minH = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 62), ZIndex = 40 }, root)
	local _ = minH
	Ui.onLayout(function()
		local W = Ui.size()
		root.Size = UDim2.fromOffset(math.min(720, W - 20), 0)
	end)
	dlg = { root = root, avatar = avatar, avStroke = avStroke, name = name, body = body, choices = choices }
end

function Ui.typewrite(label: TextLabel, text: string, cps: number?, token: number?)
	label.Text = text
	local ok, n = pcall(function()
		return utf8.len(text) or #text
	end)
	local total = if ok and n then n else #text
	label.MaxVisibleGraphemes = 0
	local rate = cps or 42
	local t0 = os.clock()
	while label.Parent do
		if token and token ~= dlgToken then
			break
		end
		local shown = math.floor((os.clock() - t0) * rate)
		if shown >= total then
			break
		end
		label.MaxVisibleGraphemes = shown
		task.wait()
	end
	label.MaxVisibleGraphemes = -1
end

local function showDialog(who: string, text: string, nameOverride: string?): number
	if not dlg then
		buildDialog()
	end
	dlgToken += 1
	local token = dlgToken
	local w = Ui.WHO[who] or Ui.WHO.system
	dlg.avatar.Text = w.icon
	dlg.avStroke.Color = w.color
	dlg.name.Text = nameOverride or w.name
	dlg.name.TextColor3 = w.color
	for _, c in dlg.choices:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	dlg.root.Visible = true
	task.spawn(Ui.typewrite, dlg.body, text, 44, token)
	return token
end

-- non-blocking line; hides after `hold` seconds unless another line replaced it
function Ui.say(who: string, text: string, opts: { [string]: any }?)
	local o = opts or {}
	local token = showDialog(who, text, o.name)
	local hold = o.hold or math.clamp(1.6 + #text / 28, 2.4, 6.5)
	task.delay(hold, function()
		if dlg and dlgToken == token then
			dlg.root.Visible = false
		end
	end)
end

function Ui.hideDialog()
	if dlg then
		dlgToken += 1
		dlg.root.Visible = false
	end
end

-- blocking choice: returns the chosen index, or nil when replaced / aborted (opts.abort() -> true)
function Ui.ask(who: string, text: string, choices: { string }, opts: { [string]: any }?): number?
	local o = opts or {}
	local token = showDialog(who, text, o.name)
	local picked: number? = nil
	local first: GuiObject? = nil
	for i, label in choices do
		local b = Ui.btn(dlg.choices, {
			text = label,
			style = if i == 1 then "primary" else "ghost",
			size = UDim2.fromOffset(0, 44),
			textSize = 15,
			order = i,
			z = 42,
			onClick = function()
				if dlgToken == token then
					picked = i
				end
			end,
		})
		b.AutomaticSize = Enum.AutomaticSize.X
		Ui.pad(b, 16, 0, 16, 0)
		if i == 1 then
			first = b
		end
	end
	Ui.select(first)
	while picked == nil do
		if dlgToken ~= token then
			return nil
		end
		if o.abort and o.abort() then
			if dlgToken == token then
				Ui.hideDialog()
			end
			return nil
		end
		task.wait(0.05)
	end
	if not o.keep then
		for _, c in dlg.choices:GetChildren() do
			if c:IsA("GuiButton") then
				c:Destroy()
			end
		end
	end
	return picked
end

-------------------------------------------------------------------------------------------------
-- 건강 상태 카드
-------------------------------------------------------------------------------------------------
local function fatigueColor(f: number): Color3
	if f >= 90 then
		return Col.red
	elseif f >= 75 then
		return Color3.fromRGB(240, 110, 70)
	elseif f >= 50 then
		return Col.orange
	end
	return Col.green
end
Ui.fatigueColor = fatigueColor

-- hv = server health view (Patient.view). opts: compact, order, title
function Ui.healthCard(parent: Instance, hv: any, opts: { [string]: any }?): Frame
	local o = opts or {}
	local card = Ui.card(parent, { LayoutOrder = o.order or 0 })
	Ui.pad(card, 14, 12, 14, 12)
	Ui.list(card, "v", 8)
	local head = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1 }, card)
	Ui.text(head, { Text = o.title or "🩺 내 건강 상태", Font = F.black, TextSize = 15, Size = UDim2.new(0.6, 0, 1, 0) })
	local mult = tonumber(hv.mult) or 1
	Ui.text(head, { Text = string.format("급여 x%.1f", mult), Font = F.bold, TextSize = 13, TextColor3 = if mult < 1 then Col.red else Col.green, Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.fromScale(0.6, 0), TextXAlignment = Enum.TextXAlignment.Right })
	-- fatigue
	local f = tonumber(hv.fatigue) or 0
	local fr = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 2 }, card)
	Ui.text(fr, { Text = string.format("피로도 %d%s", f, if hv.tier and hv.tier ~= "" then " · " .. hv.tier else ""), Font = F.bold, TextSize = 14, TextColor3 = fatigueColor(f), Size = UDim2.new(1, 0, 0, 18) })
	local bar = Ui.bar(fr, { h = 10, color = fatigueColor(f) })
	bar.frame.Position = UDim2.fromOffset(0, 22)
	bar.set(f / 100)
	-- illness
	if hv.kind then
		local ill = Ui.card(card, { BackgroundColor3 = Color3.fromRGB(255, 240, 240), LayoutOrder = 3, radius = 10 })
		Ui.pad(ill, 10, 8, 10, 8)
		Ui.list(ill, "v", 2)
		Ui.text(ill, { Text = string.format("%s %s%s", hv.kindIcon or "🤒", hv.kindName or "질병", if (hv.illMinutes or 0) > 0 then string.format(" · %d분째", hv.illMinutes) else ""), Font = F.black, TextSize = 15, TextColor3 = Col.red })
		if hv.kindDesc and hv.kindDesc ~= "" then
			Ui.text(ill, { Text = hv.kindDesc, Font = F.med, TextSize = 13, TextColor3 = Col.sub, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
		end
		if hv.collapseIn and hv.collapseIn < 300 then
			Ui.text(ill, { Text = string.format("⚠️ 이대로면 약 %d분 뒤 쓰러져요", math.max(1, math.ceil(hv.collapseIn / 60))), Font = F.bold, TextSize = 13, TextColor3 = Col.red })
		end
	elseif (hv.riskPct or 0) > 0 then
		local rr = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3 }, card)
		Ui.text(rr, { Text = string.format("질병 위험도 %d%%", hv.riskPct), Font = F.bold, TextSize = 13, TextColor3 = if hv.riskPct >= 60 then Col.red else Col.orange, Size = UDim2.new(1, 0, 0, 16) })
		local rb = Ui.bar(rr, { h = 8, color = if hv.riskPct >= 60 then Col.red else Col.orange })
		rb.frame.Position = UDim2.fromOffset(0, 20)
		rb.set((hv.riskPct or 0) / 100)
	end
	if not o.compact then
		if hv.cause and hv.cause ~= "" then
			local cz = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 }, card)
			Ui.list(cz, "v", 2)
			Ui.text(cz, { Text = "원인", Font = F.black, TextSize = 13, TextColor3 = Col.tealDD })
			Ui.text(cz, { Text = hv.cause, Font = F.med, TextSize = 13, TextColor3 = Col.ink, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
		end
		if type(hv.advice) == "table" and #hv.advice > 0 then
			local ad = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5 }, card)
			Ui.list(ad, "v", 2)
			Ui.text(ad, { Text = "권장 조치", Font = F.black, TextSize = 13, TextColor3 = Col.tealDD })
			for i, line in hv.advice do
				Ui.text(ad, { Text = line, Font = F.med, TextSize = 13, TextColor3 = Col.sub, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i })
			end
		end
	end
	if (hv.debt or 0) > 0 then
		Ui.pill(card, string.format("미납 진료비 %s", S.won(hv.debt)), "warn", 6)
	end
	if hv.onShift then
		Ui.pill(card, "근무 중 · 피로가 계속 쌓여요", "warn", 7)
	end
	return card
end

function Ui.init(ctx: any)
	S = ctx.S
	C = S.Config
	SOUNDS = {
		tap = { id = C.Sounds.Tap, vol = 0.3, speed = 1.1 },
		ping = { id = C.Sounds.Ding, vol = 0.3, speed = 1.3 },
		ding = { id = C.Sounds.Ding, vol = C.Sounds.Volume, speed = 1 },
		swoosh = { id = C.Sounds.Swoosh, vol = 0.25, speed = 1.2 },
		error = { id = C.Sounds.Tap, vol = 0.35, speed = 0.55 },
		print = { id = C.Sounds.Tap, vol = 0.35, speed = 0.7 },
		beep = { id = C.Sounds.Ding, vol = 0.35, speed = 1.9 },
	}
	local okUI, mod = pcall(function()
		local m = ReplicatedStorage:FindFirstChild("GwangalliUI")
		return if m and m:IsA("ModuleScript") then require(m) :: any else nil
	end)
	if okUI and type(mod) == "table" then
		UI = mod
	end
	soundFolder = new("Folder", { Name = "GwClinicUI" }, SoundService)
	local pg = player:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild(S.NAMES.Gui)
	if old then
		old:Destroy()
	end
	local gui = new("ScreenGui", {
		Name = S.NAMES.Gui,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 46,
	})
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	scaleObj = new("UIScale", { Scale = 1 }, gui)
	Ui.gui = gui
	toastHolder = new("Frame", { Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(400, 260), ZIndex = 60 }, gui)
	Ui.list(toastHolder, "v", 6, Enum.HorizontalAlignment.Center)
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
	-- ESC / gamepad B closes the top non-critical sheet
	UserInputService.InputBegan:Connect(function(io, gp)
		if io.KeyCode == Enum.KeyCode.Escape or io.KeyCode == Enum.KeyCode.ButtonB then
			for i = #sheets, 1, -1 do
				local sh = sheets[i]
				if sh.isOpen and not sh.noEsc then
					sh.close()
					break
				end
			end
		end
		local _ = gp
	end)
	relayout()
end

return Ui
