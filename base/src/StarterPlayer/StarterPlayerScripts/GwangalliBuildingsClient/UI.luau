-- UI: the small widget kit every screen of the building system is made of. Dark glass panels, big
-- touch targets (44 px+), one bottom sheet at a time, toasts at the top, timer chips on the right.
--   UI.init()                                  create the ScreenGui (once)
--   UI.toast(text, kind?)                      "info" | "ok" | "warn"
--   UI.sheet({ title, sub?, h?, onClose? })    -> sheet { body, footer, close(), setSub(text) }
--   UI.row(parent, { title, sub?, right?, icon?, onClick?, disabled?, accent? })
--   UI.button(parent, text, onClick, { style?, size?, order? })
--   UI.label(parent, text, { size?, color?, bold?, h?, align?, order? })
--   UI.timer(label, seconds)                   countdown chip
--   UI.fade(seconds, text?)                    full-screen fade (sleep)
--   UI.banner(text, seconds?)                  big centre text (celebrate / score)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UI = {}

UI.C = {
	bg = Color3.fromRGB(16, 19, 26),
	bg2 = Color3.fromRGB(30, 35, 46),
	bg3 = Color3.fromRGB(44, 51, 66),
	line = Color3.fromRGB(70, 80, 100),
	text = Color3.fromRGB(240, 243, 248),
	sub = Color3.fromRGB(160, 170, 188),
	accent = Color3.fromRGB(70, 150, 255),
	ok = Color3.fromRGB(60, 200, 120),
	warn = Color3.fromRGB(255, 120, 90),
	gold = Color3.fromRGB(255, 196, 70),
}
local C = UI.C

local gui: ScreenGui = nil :: any
local toastBox: Frame = nil :: any
local timerBox: Frame = nil :: any
local current: any = nil
local order = 0

local function nextOrder(): number
	order += 1
	return order
end

function UI.corner(o: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12)
	c.Parent = o
	return c
end

function UI.stroke(o: Instance, color: Color3?, t: number?, transp: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or C.line
	s.Thickness = t or 1
	s.Transparency = transp or 0.4
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
	return s
end

function UI.pad(o: Instance, l: number, r: number?, t: number?, b: number?)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, l)
	p.PaddingRight = UDim.new(0, r or l)
	p.PaddingTop = UDim.new(0, t or l)
	p.PaddingBottom = UDim.new(0, b or t or l)
	p.Parent = o
	return p
end

function UI.list(o: Instance, gap: number?, horizontal: boolean?, align: string?)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap or 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	if align == "center" then
		l.HorizontalAlignment = Enum.HorizontalAlignment.Center
		l.VerticalAlignment = Enum.VerticalAlignment.Center
	elseif align == "right" then
		l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	end
	l.Parent = o
	return l
end

function UI.frame(parent: Instance, props: any?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = C.bg2
	f.Size = UDim2.new(1, 0, 0, 40)
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	f.Parent = parent
	return f
end

function UI.label(parent: Instance, text: string, o: any?): TextLabel
	o = o or {}
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = o.color or C.text
	l.Font = if o.bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize = o.size or 15
	l.TextWrapped = true
	l.RichText = o.rich == true
	l.TextXAlignment = if o.align == "center" then Enum.TextXAlignment.Center elseif o.align == "right" then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Size = o.sizeU or UDim2.new(1, 0, 0, o.h or ((o.size or 15) + 8))
	if o.auto then
		l.AutomaticSize = Enum.AutomaticSize.Y
	end
	l.LayoutOrder = o.order or nextOrder()
	l.Parent = parent
	return l
end

local STYLE = {
	primary = { bg = C.accent, fg = Color3.new(1, 1, 1) },
	ok = { bg = C.ok, fg = Color3.fromRGB(10, 30, 16) },
	ghost = { bg = C.bg3, fg = C.text },
	danger = { bg = C.warn, fg = Color3.new(1, 1, 1) },
	gold = { bg = C.gold, fg = Color3.fromRGB(40, 28, 0) },
}

function UI.button(parent: Instance, text: string, onClick: (() -> ())?, o: any?): TextButton
	o = o or {}
	local st = STYLE[o.style or "primary"] or STYLE.primary
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.BackgroundColor3 = st.bg
	b.TextColor3 = st.fg
	b.Font = Enum.Font.GothamBold
	b.TextSize = o.textSize or 16
	b.Text = text
	b.TextWrapped = true
	b.Size = o.size or UDim2.new(1, 0, 0, 46)
	b.LayoutOrder = o.order or nextOrder()
	UI.corner(b, 10)
	local busy = false
	b.Activated:Connect(function()
		if busy or not onClick then
			return
		end
		busy = true
		local ok, err = pcall(onClick :: () -> ())
		if not ok then
			warn("[GwangalliBuildings] ui: " .. tostring(err))
		end
		task.delay(0.25, function()
			busy = false
		end)
	end)
	b.Parent = parent
	return b
end

-- list row: [icon] title / sub ............ right
function UI.row(parent: Instance, o: any): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = o.onClick ~= nil and not o.disabled
	b.Text = ""
	b.BorderSizePixel = 0
	b.BackgroundColor3 = if o.accent then C.bg3 else C.bg2
	b.Size = UDim2.new(1, 0, 0, o.h or (if o.sub then 58 else 46))
	b.LayoutOrder = o.order or nextOrder()
	UI.corner(b, 10)
	if o.accent then
		UI.stroke(b, C.accent, 1.5, 0.1)
	end
	local x = 12
	if o.icon then
		local ic = Instance.new("TextLabel")
		ic.BackgroundTransparency = 1
		ic.Text = o.icon
		ic.TextSize = 24
		ic.Font = Enum.Font.GothamBold
		ic.TextColor3 = C.text
		ic.Size = UDim2.new(0, 34, 1, 0)
		ic.Position = UDim2.new(0, 8, 0, 0)
		ic.Parent = b
		x = 46
	end
	local rightW = if o.right then (o.rightW or 110) else 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = o.title
	t.TextColor3 = if o.disabled then C.sub else C.text
	t.Font = Enum.Font.GothamBold
	t.TextSize = 15
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Position = UDim2.new(0, x, 0, if o.sub then 8 else 0)
	t.Size = UDim2.new(1, -x - rightW - 10, 0, if o.sub then 22 else (o.h or 46))
	t.Parent = b
	if o.sub then
		local s = Instance.new("TextLabel")
		s.BackgroundTransparency = 1
		s.Text = o.sub
		s.TextColor3 = C.sub
		s.Font = Enum.Font.Gotham
		s.TextSize = 13
		s.TextXAlignment = Enum.TextXAlignment.Left
		s.TextTruncate = Enum.TextTruncate.AtEnd
		s.Position = UDim2.new(0, x, 0, 30)
		s.Size = UDim2.new(1, -x - rightW - 10, 0, 18)
		s.Parent = b
	end
	if o.right then
		local r = Instance.new("TextLabel")
		r.BackgroundTransparency = 1
		r.Text = o.right
		r.TextColor3 = o.rightColor or (if o.disabled then C.sub else C.gold)
		r.Font = Enum.Font.GothamBold
		r.TextSize = 15
		r.TextXAlignment = Enum.TextXAlignment.Right
		r.Position = UDim2.new(1, -rightW - 12, 0, 0)
		r.Size = UDim2.new(0, rightW, 1, 0)
		r.Parent = b
	end
	if o.onClick and not o.disabled then
		local busy = false
		b.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			local ok, err = pcall(o.onClick)
			if not ok then
				warn("[GwangalliBuildings] ui: " .. tostring(err))
			end
			task.delay(0.25, function()
				busy = false
			end)
		end)
	end
	b.Parent = parent
	return b
end

-- horizontal tab strip; onPick(i) when a tab is pressed
function UI.tabs(parent: Instance, names: { string }, selected: number, onPick: (number) -> ()): Frame
	local strip = Instance.new("ScrollingFrame")
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Size = UDim2.new(1, 0, 0, 40)
	strip.ScrollBarThickness = 0
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.CanvasSize = UDim2.new(0, 0, 0, 0)
	strip.LayoutOrder = nextOrder()
	UI.list(strip, 6, true)
	for i, n in names do
		local b = UI.button(strip, n, function()
			onPick(i)
		end, { style = if i == selected then "primary" else "ghost", size = UDim2.new(0, math.max(64, 14 * utf8.len(n) :: number + 24), 0, 36), textSize = 14, order = i })
		b.Name = "Tab" .. i
	end
	strip.Parent = parent
	return strip :: any
end

function UI.init()
	if gui then
		return
	end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "GwangalliBuildingsUI"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 30
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = pg
	gui = g
	toastBox = UI.frame(g, {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 132),
		Size = UDim2.new(0, 460, 0, 200),
		ZIndex = 50,
	})
	local uic = Instance.new("UISizeConstraint")
	uic.MaxSize = Vector2.new(460, 200)
	uic.Parent = toastBox
	toastBox.Size = UDim2.new(0.9, 0, 0, 200)
	UI.list(toastBox, 6, false, "center")
	timerBox = UI.frame(g, {
		Name = "Timers",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 64),
		Size = UDim2.new(0, 190, 0, 220),
	})
	UI.list(timerBox, 6, false, "right")
end

function UI.root(): ScreenGui
	return gui
end

function UI.screen(): Vector2
	return if gui then gui.AbsoluteSize else Vector2.new(1280, 720)
end

function UI.toast(text: string, kind: string?)
	if not gui or type(text) ~= "string" or text == "" then
		return
	end
	local kids = {}
	for _, c in toastBox:GetChildren() do
		if c:IsA("Frame") then
			table.insert(kids, c)
		end
	end
	if #kids >= 3 then
		kids[1]:Destroy()
	end
	local f = UI.frame(toastBox, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.bg, BackgroundTransparency = 0.08, LayoutOrder = nextOrder(), ZIndex = 50 })
	UI.corner(f, 12)
	UI.stroke(f, if kind == "warn" then C.warn elseif kind == "ok" then C.ok else C.line, 1.5, 0.15)
	UI.pad(f, 14, 14, 10, 10)
	local l = UI.label(f, text, { size = 15, bold = true, align = "center", auto = true, h = 0 })
	l.ZIndex = 51
	task.delay(if #text > 60 then 4.6 else 3.2, function()
		if f.Parent then
			local ok = pcall(function()
				TweenService:Create(f, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
				TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			end)
			task.wait(if ok then 0.32 else 0)
			f:Destroy()
		end
	end)
end

-- bottom sheet: only one at a time (opening another closes the first)
function UI.sheet(o: any): any
	if current then
		current.close()
	end
	local scr = UI.screen()
	local w = math.min(o.w or 460, scr.X - 24)
	local h = math.min(o.h or 400, scr.Y - 70)
	local f = UI.frame(gui, {
		Name = "Sheet",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(0, w, 0, h),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.04,
		ZIndex = 20,
	})
	UI.corner(f, 16)
	UI.stroke(f, C.line, 1, 0.3)
	local head = UI.frame(f, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, if o.sub then 56 else 46) })
	local title = UI.label(head, o.title or "", { size = 18, bold = true })
	title.Position = UDim2.new(0, 16, 0, 8)
	title.Size = UDim2.new(1, -70, 0, 26)
	local sub
	if o.sub then
		sub = UI.label(head, o.sub, { size = 13, color = C.sub })
		sub.Position = UDim2.new(0, 16, 0, 32)
		sub.Size = UDim2.new(1, -70, 0, 18)
	end
	local sheet: any = {}
	local closed = false
	local x = UI.button(head, "✕", function()
		sheet.close()
	end, { style = "ghost", size = UDim2.new(0, 40, 0, 40) })
	x.Position = UDim2.new(1, -48, 0, 6)
	local footH = if o.footer then (o.footerH or 56) else 0
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.new(0, 10, 0, head.Size.Y.Offset)
	body.Size = UDim2.new(1, -20, 1, -head.Size.Y.Offset - footH - 8)
	body.ScrollBarThickness = 4
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new(0, 0, 0, 0)
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.Parent = f
	if o.grid then
		local g = Instance.new("UIGridLayout")
		g.CellSize = o.grid
		g.CellPadding = UDim2.new(0, 8, 0, 8)
		g.SortOrder = Enum.SortOrder.LayoutOrder
		g.HorizontalAlignment = Enum.HorizontalAlignment.Center
		g.Parent = body
	else
		UI.list(body, 6)
	end
	UI.pad(body, 2, 6, 2, 8)
	local footer
	if o.footer then
		footer = UI.frame(f, { BackgroundTransparency = 1, Position = UDim2.new(0, 10, 1, -footH - 4), Size = UDim2.new(1, -20, 0, footH) })
		UI.list(footer, 8, true, "center")
	end
	sheet.frame = f
	sheet.body = body
	sheet.footer = footer
	sheet.kind = o.kind
	function sheet.close()
		if closed then
			return
		end
		closed = true
		if current == sheet then
			current = nil
		end
		f:Destroy()
		if o.onClose then
			pcall(o.onClose)
		end
	end
	function sheet.isOpen(): boolean
		return not closed
	end
	function sheet.setSub(text: string)
		if sub then
			sub.Text = text
		end
	end
	function sheet.clear()
		for _, c in body:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end
	current = sheet
	return sheet
end

function UI.current(): any
	return current
end

function UI.closeSheet(kind: string?)
	if current and (kind == nil or current.kind == kind) then
		current.close()
	end
end

-- countdown chip on the right edge
function UI.timer(label: string, seconds: number)
	if not gui then
		return
	end
	local f = UI.frame(timerBox, { Size = UDim2.new(0, 180, 0, 34), BackgroundColor3 = C.bg, BackgroundTransparency = 0.1, LayoutOrder = nextOrder() })
	UI.corner(f, 17)
	UI.stroke(f, C.gold, 1, 0.3)
	local l = UI.label(f, "", { size = 14, bold = true, align = "center" })
	l.Size = UDim2.fromScale(1, 1)
	local t1 = os.clock() + seconds
	task.spawn(function()
		while f.Parent do
			local left = t1 - os.clock()
			if left <= 0 then
				l.Text = "✅ " .. label .. " 완료!"
				task.wait(2.2)
				break
			end
			l.Text = string.format("⏱ %s  %d:%02d", label, math.floor(left) // 60, math.floor(left) % 60)
			task.wait(0.25)
		end
		f:Destroy()
	end)
end

function UI.fade(seconds: number, text: string?)
	if not gui then
		return
	end
	local f = UI.frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 80 })
	local l = UI.label(f, text or "", { size = 22, bold = true, align = "center", color = Color3.fromRGB(220, 226, 240) })
	l.Size = UDim2.fromScale(1, 1)
	l.TextTransparency = 1
	l.ZIndex = 81
	local fadeIn = math.min(0.8, seconds / 4)
	pcall(function()
		TweenService:Create(f, TweenInfo.new(fadeIn), { BackgroundTransparency = 0 }):Play()
		TweenService:Create(l, TweenInfo.new(fadeIn), { TextTransparency = 0 }):Play()
	end)
	task.delay(seconds - fadeIn, function()
		pcall(function()
			TweenService:Create(f, TweenInfo.new(fadeIn), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(fadeIn), { TextTransparency = 1 }):Play()
		end)
		task.wait(fadeIn + 0.05)
		f:Destroy()
	end)
end

function UI.banner(text: string, seconds: number?)
	if not gui then
		return
	end
	local f = UI.frame(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.new(0, 0, 0, 64), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.bg, BackgroundTransparency = 0.05, ZIndex = 60 })
	UI.corner(f, 20)
	UI.stroke(f, C.gold, 2, 0)
	UI.pad(f, 24, 24, 8, 8)
	local l = UI.label(f, text, { size = 24, bold = true, align = "center", color = C.gold })
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.new(0, 0, 1, 0)
	l.TextWrapped = false
	l.ZIndex = 61
	task.delay(seconds or 3, function()
		f:Destroy()
	end)
end

return UI
