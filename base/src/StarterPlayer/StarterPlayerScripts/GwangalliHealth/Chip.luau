-- GwangalliHealth/Chip: the debuff chip. Reads Player attributes Fatigue / Illness (set by the server),
-- shows "😮‍💨 피로 -30%" (orange) or "🤧 감기 -80%" (red, pulsing) with a thin fatigue bar, animated in / out.
-- Placement: right of the phone's money chip inside the Layout "topLeftChips" slot when there is room,
-- else just under that slot. Nothing runs per frame: attribute signals + Layout.changed only.

local TweenService = game:GetService("TweenService")

local Chip = {}

local ctx: any
local K: any
local HS: any
local chip: Frame? = nil
local label: TextLabel? = nil
local icon: Frame? = nil
local glyph: TextLabel? = nil
local stroke: UIStroke? = nil
local bar: any = nil
local shown = false
local H = 34
-- The 22 px tile shows ONE glyph: a ZWJ emoji sequence (😮‍💨, 😵‍💫) can render as two glyphs on a
-- device whose emoji font lacks it, so the chip uses single-codepoint emoji (the stat keeps its icon).
local TIRED = "😩"
local function simpleEmoji(s: any): string
	if type(s) ~= "string" or s == "" then
		return TIRED
	end
	local cut = string.find(s, "\u{200D}", 1, true)
	return if cut then string.sub(s, 1, cut - 1) else s
end

local function build()
	local gui = ctx.gui
	local f = K.frame(gui, {
		Name = "HealthChip",
		Size = UDim2.fromOffset(120, H),
		BackgroundTransparency = K.GLASS_T,
		BackgroundColor3 = K.Color.glass,
		Visible = false,
		ZIndex = 3,
	})
	K.corner(f, 12)
	stroke = K.stroke(f, K.Color.orange, 1, 0.5)
	K.shadow(f, 12, 4, "soft")
	icon = K.iconTile(f, 22, TIRED, K.Color.orange, true)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 6, 0.5, 0)
	glyph = icon:FindFirstChild("Glyph") :: TextLabel?
	label = K.text(f, {
		Name = "Label",
		Position = UDim2.fromOffset(34, 3),
		Size = UDim2.new(1, -40, 0, 16),
		Text = "",
		Font = K.Font.bold,
		TextSize = K.Type.caption,
		TextColor3 = K.Color.text,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	bar = K.ProgressBar(f, { height = 3, color = K.Color.orange })
	bar.frame.AnchorPoint = Vector2.new(0, 1)
	bar.frame.Position = UDim2.new(0, 34, 1, -6)
	bar.frame.Size = UDim2.new(1, -42, 0, 3)
	chip = f
end

local function place()
	local f = chip
	if not f then
		return
	end
	local gui = ctx.gui
	local Layout = ctx.Layout
	local w = f.Size.X.Offset
	local x, y = 12, 12
	if Layout then
		local ok, slot = pcall(Layout.rect, "topLeftChips")
		if ok and slot then
			x, y = slot.x, slot.y + slot.h + 6
			-- to the right of the phone's money chip when the slot has room
			local money = ctx.playerGui:FindFirstChild("MoneyChip", true)
			if money and money:IsA("GuiObject") and money.Visible and money.AbsoluteSize.X > 0 then
				local gx, gy = gui.AbsolutePosition.X, gui.AbsolutePosition.Y
				local mx = money.AbsolutePosition.X + money.AbsoluteSize.X + 8 - gx
				local my = money.AbsolutePosition.Y + (money.AbsoluteSize.Y - H) / 2 - gy
				local roomRight = slot.x + slot.w + 36
				if mx + w <= roomRight and my >= slot.y - 2 then
					x, y = mx, my
				end
			end
		end
	end
	-- the owner's admin gear (GwangalliAdmin.AdminToggle) uses the same fallback spot under the
	-- chips on a portrait phone: step to its right when we would overlap it
	local gear = ctx.playerGui:FindFirstChild("AdminToggle", true)
	if gear and gear:IsA("GuiObject") and gear.Visible and gear.AbsoluteSize.X > 0 then
		local gx, gy = gui.AbsolutePosition.X, gui.AbsolutePosition.Y
		local ax, ay = gear.AbsolutePosition.X - gx, gear.AbsolutePosition.Y - gy
		local aw, ah = gear.AbsoluteSize.X, gear.AbsoluteSize.Y
		if x < ax + aw and x + w > ax and y < ay + ah and y + H > ay then
			x = ax + aw + 8
			if x + w > gui.AbsoluteSize.X - 8 then
				x = ax
				y = ay + ah + 6
			end
		end
	end
	f.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

local function colorOf(ill: boolean, fatigue: number): Color3
	if ill then
		return K.Color.red
	end
	local c = HS.fatigueColor(fatigue)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function refresh()
	if not chip or not label or not icon or not stroke then
		return
	end
	local player = ctx.player
	local fatigue = tonumber(player:GetAttribute(ctx.G.Attr.Fatigue)) or 0
	local illness = player:GetAttribute(ctx.G.Attr.Illness)
	local illKind = if type(illness) == "string" and illness ~= "" then illness else nil
	local text = HS.debuffText(fatigue, illKind)
	local f = chip :: Frame
	if not text then
		if shown then
			shown = false
			K.pulse(stroke, false)
			K.tween(f, 0.2, { Position = f.Position - UDim2.fromOffset(0, 10), BackgroundTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			for _, d in f:GetDescendants() do
				if d:IsA("TextLabel") then
					K.tween(d, 0.2, { TextTransparency = 1 })
				elseif d:IsA("UIStroke") then
					K.tween(d, 0.2, { Transparency = 1 })
				end
			end
			task.delay(0.22, function()
				if not shown and chip then
					(chip :: Frame).Visible = false
				end
			end)
		end
		return
	end
	-- content
	local kind = HS.kind(illKind)
	local color = colorOf(kind ~= nil, fatigue)
	local shownText = if kind then string.format("%s -%d%%", kind.name, math.floor((1 - HS.H().illMult) * 100 + 0.5)) else string.gsub(text, "^%S+%s", "")
	label.Text = shownText
	label.TextColor3 = if kind then Color3.fromRGB(255, 190, 190) else K.Color.text
	if glyph then
		glyph.Text = if kind then simpleEmoji(kind.icon) else TIRED
	end
	local grad = icon:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(K.shade(color, -0.08, 0.12), K.shade(color, 0.1, -0.22))
	end
	stroke.Color = color
	bar.setColor(color)
	bar.set(fatigue / 100)
	local tw = K.textSize(shownText, K.Type.caption, K.Font.bold).X
	local w = math.max(96, math.ceil(tw) + 46)
	f.Size = UDim2.fromOffset(w, H)
	place()
	if not shown then
		shown = true
		f.Visible = true
		f.BackgroundTransparency = 1
		local rest = f.Position
		f.Position = rest - UDim2.fromOffset(0, 10)
		for _, d in f:GetDescendants() do
			if d:IsA("TextLabel") then
				d.TextTransparency = 1
				K.tween(d, 0.25, { TextTransparency = 0 })
			elseif d:IsA("UIStroke") then
				d.Transparency = 1
				K.tween(d, 0.25, { Transparency = 0.5 })
			end
		end
		K.tween(f, 0.28, { Position = rest, BackgroundTransparency = K.GLASS_T })
		K.pop(f, 0.9)
	end
	K.pulse(stroke, kind ~= nil, 0.1, 0.75)
end

function Chip.init(c: any)
	ctx = c
	K = c.K
	HS = c.HS
	build()
	local player = ctx.player
	player:GetAttributeChangedSignal(ctx.G.Attr.Fatigue):Connect(refresh)
	player:GetAttributeChangedSignal(ctx.G.Attr.Illness):Connect(refresh)
	if ctx.Layout and type(ctx.Layout.onChanged) == "function" then
		pcall(ctx.Layout.onChanged, function()
			if shown then
				place()
			end
		end)
	end
	-- the money chip appears a little after us: re-place once it exists
	task.delay(3, function()
		if shown then
			place()
		end
	end)
	refresh()
	local _ = TweenService
end

function Chip.refresh()
	refresh()
end

return Chip
