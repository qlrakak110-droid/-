-- GwangalliPhone/UI: theme (One UI dark style) and small instance builders shared by every phone
-- module. Pure helpers: nothing here yields or talks to the server.

local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local UI = {}

-- Colours ------------------------------------------------------------------------------------------
UI.C = {
	-- mirrors GwangalliUI.Color (the kit) so legacy helpers match the new design language
	black = Color3.fromRGB(0, 0, 0),
	bg = Color3.fromRGB(10, 12, 20),
	card = Color3.fromRGB(25, 29, 45),
	card2 = Color3.fromRGB(37, 42, 61),
	line = Color3.fromRGB(54, 60, 84),
	text = Color3.fromRGB(245, 247, 251),
	sub = Color3.fromRGB(170, 177, 196),
	faint = Color3.fromRGB(116, 124, 146),
	accent = Color3.fromRGB(61, 214, 245),
	yellow = Color3.fromRGB(255, 194, 71),
	yellowText = Color3.fromRGB(44, 28, 0),
	green = Color3.fromRGB(61, 220, 132),
	red = Color3.fromRGB(255, 90, 95),
	orange = Color3.fromRGB(255, 176, 32),
	purple = Color3.fromRGB(139, 108, 255),
	pink = Color3.fromRGB(255, 79, 163),
	teal = Color3.fromRGB(40, 204, 196),
	hud = Color3.fromRGB(15, 18, 31),
}

UI.F = {
	regular = Enum.Font.Gotham,
	medium = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
	heavy = Enum.Font.GothamBlack,
}

UI.MIN_TEXT = 11 -- rendered px floor for TextScaled labels on phones

-- Builders -----------------------------------------------------------------------------------------
function UI.make(className: string, props: { [string]: any }?, parent: Instance?): any
	local inst = Instance.new(className)
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
local make = UI.make

-- radius: px (number) or a UDim
function UI.corner(inst: Instance, radius: any): UICorner
	local r = if typeof(radius) == "UDim" then radius else UDim.new(0, radius or 8)
	return make("UICorner", { CornerRadius = r }, inst)
end

function UI.stroke(inst: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return make("UIStroke", {
		Color = color or Color3.new(1, 1, 1),
		Thickness = thickness or 1,
		Transparency = transparency or 0.85,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
end

-- colors: { Color3 } evenly spaced, or a ColorSequence
function UI.gradient(inst: Instance, colors: any, rotation: number?, transparency: NumberSequence?): UIGradient
	local seq = colors
	if type(colors) == "table" then
		local kps = {}
		local n = #colors
		for i, c in colors do
			table.insert(kps, ColorSequenceKeypoint.new(if n == 1 then 0 else (i - 1) / (n - 1), c))
		end
		if n == 1 then
			table.insert(kps, ColorSequenceKeypoint.new(1, colors[1]))
		end
		seq = ColorSequence.new(kps)
	end
	local g = make("UIGradient", { Color = seq, Rotation = rotation or 90 }, inst)
	if transparency then
		g.Transparency = transparency
	end
	return g
end

function UI.pad(inst: Instance, l: number, r: number?, t: number?, b: number?): UIPadding
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingRight = UDim.new(0, r or l),
		PaddingTop = UDim.new(0, t or l),
		PaddingBottom = UDim.new(0, b or t or l),
	}, inst)
end

function UI.list(inst: Instance, horizontal: boolean?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return make("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, padding or 0),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
	}, inst)
end

function UI.frame(parent: Instance?, props: { [string]: any }?): Frame
	local base: { [string]: any } = { BackgroundTransparency = 1, BorderSizePixel = 0 }
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return make("Frame", base, parent)
end

function UI.label(parent: Instance?, props: { [string]: any }?): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextColor3 = UI.C.text,
		Font = UI.F.medium,
		TextSize = 14,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return make("TextLabel", base, parent)
end

function UI.button(parent: Instance?, props: { [string]: any }?): TextButton
	local base: { [string]: any } = {
		BackgroundColor3 = UI.C.card2,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		TextColor3 = UI.C.text,
		Font = UI.F.bold,
		TextSize = 15,
		Text = "",
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return make("TextButton", base, parent)
end

-- TextScaled with a readable floor and a ceiling.
function UI.scaled(label: Instance, minSize: number, maxSize: number): UITextSizeConstraint
	(label :: any).TextScaled = true
	return make("UITextSizeConstraint", { MinTextSize = minSize, MaxTextSize = maxSize }, label)
end

function UI.setText(label: any, value: string)
	if label.Text ~= value then
		label.Text = value
	end
end

function UI.clear(container: Instance, keepClass: { [string]: boolean }?)
	for _, c in container:GetChildren() do
		if not (keepClass and keepClass[c.ClassName]) then
			c:Destroy()
		end
	end
end

-- Circle "avatar" with an initial or emoji.
function UI.avatar(parent: Instance, size: number, glyph: string, color: Color3, props: { [string]: any }?): Frame
	local f = UI.frame(parent, { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 0, BackgroundColor3 = color })
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	UI.corner(f, UDim.new(0.5, 0))
	local h, s, v = color:ToHSV()
	UI.gradient(f, { Color3.fromHSV(h, math.max(0, s - 0.15), math.min(1, v + 0.12)), Color3.fromHSV(h, math.min(1, s + 0.1), v * 0.78) }, 120)
	UI.label(f, {
		Name = "Glyph",
		Size = UDim2.fromScale(1, 1),
		Text = glyph,
		Font = UI.F.bold,
		TextSize = math.floor(size * 0.46),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	return f
end

-- Red notification badge (hidden at 0).
function UI.badge(parent: Instance, size: number?): TextLabel
	local s = size or 20
	local b = UI.label(parent, {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -3, 0, 3),
		Size = UDim2.fromOffset(s, s),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = UI.C.red,
		Text = "",
		Font = UI.F.bold,
		TextSize = math.floor(s * 0.62),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 5,
		Visible = false,
	})
	UI.corner(b, UDim.new(0.5, 0))
	UI.pad(b, math.floor(s * 0.28), math.floor(s * 0.28), 0, 0)
	UI.stroke(b, UI.C.bg, 1.5, 0)
	return b
end

function UI.setBadge(b: TextLabel?, n: number)
	if not b then
		return
	end
	if n and n > 0 then
		b.Visible = true
		UI.setText(b, if n > 99 then "99+" else tostring(math.floor(n)))
	else
		b.Visible = false
	end
end

-- Measured text height/width (TextService, with an estimate as fallback).
function UI.textSize(text: string, size: number, font: Enum.Font, width: number): Vector2
	local ok, v = pcall(TextService.GetTextSize, TextService, text, size, font, Vector2.new(width, 10000))
	if ok and typeof(v) == "Vector2" and v.Y > 0 then
		return v
	end
	-- estimate: Hangul ~0.93 em, Latin ~0.55 em
	local units = 0
	for _, cp in utf8.codes(text) do
		units += if cp >= 0x1100 then 0.93 elseif cp == 32 then 0.3 else 0.56
	end
	local w = units * size
	local lines = math.max(1, math.ceil(w / math.max(1, width)))
	for _ in string.gmatch(text, "\n") do
		lines += 1
	end
	return Vector2.new(math.min(w, width), lines * size * 1.2)
end

function UI.tween(inst: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween?
	local ok, t = pcall(function()
		local tw = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goals)
		tw:Play()
		return tw
	end)
	if ok then
		return t
	end
	for k, v in goals do
		pcall(function()
			(inst :: any)[k] = v
		end)
	end
	return nil
end

-- Money / distance / time formatting ---------------------------------------------------------------
function UI.commas(n: number): string
	local neg = n < 0
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if neg then "-" else "") .. out
end

-- 1 stud = 0.3 m (true-scale map)
function UI.meters(studs: number): string
	local m = studs * 0.3
	if m < 1000 then
		return string.format("%dm", math.floor(m / 5 + 0.5) * 5)
	end
	return string.format("%.1fkm", m / 1000)
end

-- In-game clock (0-24) -> "오후 5:32"
function UI.korClock(clock: number): string
	local minutes = math.floor((clock % 24) * 60 + 1e-6)
	local h, m = minutes // 60, minutes % 60
	local ampm = if h < 12 then "오전" else "오후"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%s %d:%02d", ampm, h12, m)
end

function UI.clock24(clock: number): string
	local minutes = math.floor((clock % 24) * 60 + 1e-6)
	return string.format("%02d:%02d", minutes // 60, minutes % 60)
end

-- Korean object particle: (으)로
function UI.ro(word: string): string
	local last = 0
	for _, cp in utf8.codes(word) do
		last = cp
	end
	if last >= 0xAC00 and last <= 0xD7A3 then
		local jong = (last - 0xAC00) % 28
		if jong == 0 or jong == 8 then -- no final consonant, or ㄹ
			return word .. "로"
		end
		return word .. "으로"
	end
	return word .. "(으)로"
end

return UI
