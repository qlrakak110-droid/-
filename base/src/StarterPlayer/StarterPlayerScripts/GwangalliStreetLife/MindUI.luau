-- GwangalliStreetLife/MindUI: the conversation bar of the NPC mind (owner: npc_mind). The talk itself
-- happens in speech bubbles over the heads (GwangalliBumpShared bubble pool); this bar is only how the
-- player answers: a header (who, the relationship stage, 호감 / 신뢰 / 분노 / 공포 / 친밀), a row of
-- chips (topics, actions, the NPC's question answers first) with sub-menus, and a text box for
-- typing anything (the server parses it). Plus the 🚨 wanted stars chip while the police look for you.
-- Built from the GwangalliUI tokens only (colours / fonts), placed with GwangalliLayout's bottomCenter
-- slot (landscape phones: between the thumbstick and the jump button) and never over the joystick.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UI = {}

local player = Players.LocalPlayer
local K: any = nil
local Layout: any = nil
local gui: ScreenGui? = nil
local panel: Frame? = nil
local header: any = {}
local chipRow: ScrollingFrame? = nil
local input: TextBox? = nil
local sendBtn: TextButton? = nil
local typing: TextLabel? = nil
local wantedChip: Frame? = nil
local wantedText: TextLabel? = nil
local handlers: any = {}
local open = false
local stack: { any } = {} -- sub-menu stack: { {chips, title} }
local answers: { any } = {}
local baseChips: { any } = {}

local C = {
	glass = Color3.fromRGB(15, 18, 31),
	card = Color3.fromRGB(25, 29, 45),
	card2 = Color3.fromRGB(37, 42, 61),
	text = Color3.fromRGB(245, 247, 251),
	sub = Color3.fromRGB(170, 177, 196),
	cyan = Color3.fromRGB(61, 214, 245),
	magenta = Color3.fromRGB(255, 79, 163),
	gold = Color3.fromRGB(255, 194, 71),
	red = Color3.fromRGB(255, 90, 95),
	green = Color3.fromRGB(61, 220, 132),
}
local FONT_B, FONT_M = Enum.Font.GothamBold, Enum.Font.GothamMedium

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end
local function stroke(p: Instance, t: number?)
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(1, 1, 1)
	s.Transparency = t or 0.86
	s.Thickness = 1
	s.Parent = p
	return s
end
local function label(parent: Instance, props: any): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = props.font or FONT_M
	t.TextSize = props.size or 13
	t.TextColor3 = props.color or C.text
	t.TextXAlignment = props.align or Enum.TextXAlignment.Left
	t.Text = props.text or ""
	t.Size = props.sz or UDim2.new(1, 0, 0, 18)
	t.Position = props.pos or UDim2.new()
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Name = props.name or "Label"
	t.Parent = parent
	return t
end

local function feedback(kind: string)
	if K and type(K.feedback) == "function" then
		pcall(K.feedback, kind)
	end
end

-------------------------------------------------------------------------------------------------
-- build
-------------------------------------------------------------------------------------------------
local function place()
	if not panel then
		return
	end
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local w = math.min(640, vp.X - 24)
	local x, y = vp.X / 2, vp.Y - 12
	if Layout and type(Layout.rect) == "function" then
		local ok, r = pcall(Layout.rect, "bottomCenter")
		if ok and type(r) == "table" and r.w and r.w > 260 then
			-- the slot between the thumbstick and the jump button; wider screens get a roomier bar
			w = math.clamp(math.max(r.w, vp.X - 380), 340, 640)
			x = r.x + r.w / 2
			y = r.y + r.h
		end
	end
	panel.Size = UDim2.fromOffset(w, 150)
	panel.Position = UDim2.fromOffset(x, y)
end

local function build()
	if gui then
		return
	end
	local pg = player:WaitForChild("PlayerGui", 10)
	if not pg then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "GwangalliMindTalk"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = false
	g.DisplayOrder = 28
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	g.Parent = pg
	gui = g

	-- wanted stars (top centre, under the clock chip)
	local wc = Instance.new("Frame")
	wc.Name = "Wanted"
	wc.AnchorPoint = Vector2.new(0.5, 0)
	wc.Position = UDim2.new(0.5, 0, 0, 52)
	wc.Size = UDim2.fromOffset(176, 30)
	wc.BackgroundColor3 = Color3.fromRGB(60, 10, 18)
	wc.BackgroundTransparency = 0.12
	wc.Visible = false
	wc.Parent = g
	corner(wc, 15)
	stroke(wc, 0.6).Color = C.red
	wantedChip = wc
	wantedText = label(wc, { text = "", font = FONT_B, size = 14, color = Color3.fromRGB(255, 220, 120), align = Enum.TextXAlignment.Center, sz = UDim2.fromScale(1, 1) })

	local p = Instance.new("Frame")
	p.Name = "Talk"
	p.AnchorPoint = Vector2.new(0.5, 1)
	p.BackgroundColor3 = C.glass
	p.BackgroundTransparency = 0.12
	p.Visible = false
	p.Parent = g
	corner(p, 18)
	stroke(p, 0.84)
	panel = p

	-- header: stage icon + who + stats + close
	local h = Instance.new("Frame")
	h.Name = "Header"
	h.BackgroundTransparency = 1
	h.Position = UDim2.fromOffset(12, 8)
	h.Size = UDim2.new(1, -24, 0, 38)
	h.Parent = p
	header.frame = h
	header.title = label(h, { name = "Title", font = FONT_B, size = 15, sz = UDim2.new(1, -44, 0, 18) })
	header.sub = label(h, { name = "Sub", size = 11, color = C.sub, pos = UDim2.fromOffset(0, 20), sz = UDim2.new(0.42, 0, 0, 15) })
	-- 💗 호감 🤝 신뢰 💢 분노 😨 공포 🫶 친밀: one compact row, right of the subtitle
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.BackgroundTransparency = 1
	stats.AnchorPoint = Vector2.new(1, 0)
	stats.Position = UDim2.new(1, -40, 0, 17)
	stats.Size = UDim2.new(0.58, -40, 0, 20)
	stats.Parent = h
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Horizontal
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	sl.Padding = UDim.new(0, 3)
	sl.Parent = stats
	header.stats = {}
	for i, key in { "aff", "tr", "an", "fe", "cl" } do
		local pill = Instance.new("Frame")
		pill.Name = key
		pill.LayoutOrder = i
		pill.BackgroundColor3 = C.card
		pill.Size = UDim2.fromOffset(44, 20)
		pill.Parent = stats
		corner(pill, 10)
		local t = label(pill, { text = "", size = 11, font = FONT_B, align = Enum.TextXAlignment.Center, sz = UDim2.fromScale(1, 1) })
		header.stats[key] = t
	end
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(32, 32)
	close.BackgroundColor3 = C.card2
	close.Text = "✕"
	close.Font = FONT_B
	close.TextSize = 15
	close.TextColor3 = C.text
	close.AutoButtonColor = true
	close.Parent = h
	corner(close, 16)
	close.Activated:Connect(function()
		feedback("close")
		if handlers.onClose then
			handlers.onClose()
		end
	end)

	-- chips
	local row = Instance.new("ScrollingFrame")
	row.Name = "Chips"
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Position = UDim2.fromOffset(10, 52)
	row.Size = UDim2.new(1, -20, 0, 40)
	row.CanvasSize = UDim2.new()
	row.AutomaticCanvasSize = Enum.AutomaticSize.X
	row.ScrollingDirection = Enum.ScrollingDirection.X
	row.ScrollBarThickness = 2
	row.Parent = p
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.Padding = UDim.new(0, 6)
	rl.VerticalAlignment = Enum.VerticalAlignment.Center
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = row
	chipRow = row

	-- input
	local box = Instance.new("TextBox")
	box.Name = "Input"
	box.Position = UDim2.fromOffset(10, 102)
	box.Size = UDim2.new(1, -96, 0, 38)
	box.BackgroundColor3 = C.card
	box.TextColor3 = C.text
	box.PlaceholderColor3 = C.sub
	box.PlaceholderText = "직접 말 걸기… (예: 이름이 뭐예요? / 떡볶이 좋아해?)"
	box.Text = ""
	box.Font = FONT_M
	box.TextSize = 14
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.Parent = p
	corner(box, 12)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = box
	input = box
	local send = Instance.new("TextButton")
	send.Name = "Send"
	send.AnchorPoint = Vector2.new(1, 0)
	send.Position = UDim2.new(1, -10, 0, 102)
	send.Size = UDim2.fromOffset(76, 38)
	send.BackgroundColor3 = C.cyan
	send.Text = "말하기"
	send.Font = FONT_B
	send.TextSize = 14
	send.TextColor3 = Color3.fromRGB(4, 22, 32)
	send.Parent = p
	corner(send, 12)
	sendBtn = send
	local function submit()
		local t = box.Text
		if type(t) == "string" and string.match(t, "%S") then
			box.Text = ""
			feedback("tap")
			if handlers.onSend then
				handlers.onSend(t)
			end
		end
	end
	send.Activated:Connect(submit)
	box.FocusLost:Connect(function(enter)
		if enter then
			submit()
		end
	end)
	local ty = label(p, { name = "Typing", text = "", size = 11, color = C.cyan, pos = UDim2.new(1, -232, 0, 10), sz = UDim2.fromOffset(180, 16), align = Enum.TextXAlignment.Right })
	ty.Visible = false
	typing = ty
	place()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(place)
	end
	if Layout and Layout.changed then
		pcall(function()
			Layout.changed:Connect(place)
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- chips
-------------------------------------------------------------------------------------------------
local function chipButton(spec: any, order: number, kind: string?): TextButton
	local b = Instance.new("TextButton")
	b.Name = "Chip_" .. tostring(spec.id)
	b.LayoutOrder = order
	b.AutomaticSize = Enum.AutomaticSize.X
	b.Size = UDim2.fromOffset(0, 34)
	b.BackgroundColor3 = if kind == "answer" then Color3.fromRGB(20, 70, 90) elseif kind == "back" then C.card2 elseif spec.danger then Color3.fromRGB(80, 24, 34) else C.card
	b.Text = spec.label
	b.Font = FONT_B
	b.TextSize = 13
	b.TextColor3 = if kind == "answer" then Color3.fromRGB(190, 245, 255) else C.text
	b.AutoButtonColor = true
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = b
	corner(b, 17)
	if kind == "answer" then
		stroke(b, 0.4).Color = C.cyan
	end
	b.Parent = chipRow
	return b
end

local function render()
	if not chipRow then
		return
	end
	for _, ch in chipRow:GetChildren() do
		if ch:IsA("GuiButton") then
			ch:Destroy()
		end
	end
	local order = 0
	local top = stack[#stack]
	if top then
		order += 1
		local back = chipButton({ id = "back", label = "◀ " .. (top.title or "뒤로") }, order, "back")
		back.Activated:Connect(function()
			table.remove(stack)
			feedback("tap")
			render()
		end)
		for _, spec in top.chips do
			order += 1
			local b = chipButton(spec, order, nil)
			b.Activated:Connect(function()
				feedback("tap")
				if spec.keep ~= true then
					table.clear(stack)
				end
				if handlers.onChip then
					handlers.onChip(spec)
				end
				render()
			end)
		end
	else
		for _, spec in answers do
			order += 1
			local b = chipButton(spec, order, "answer")
			b.Activated:Connect(function()
				feedback("tap")
				table.clear(answers)
				if handlers.onAnswer then
					handlers.onAnswer(spec)
				end
				render()
			end)
		end
		for _, spec in baseChips do
			order += 1
			local b = chipButton(spec, order, nil)
			b.Activated:Connect(function()
				feedback("tap")
				if spec.sub then
					local sub = if type(spec.sub) == "function" then spec.sub() else spec.sub
					if sub and #sub > 0 then
						table.insert(stack, { chips = sub, title = spec.label })
						render()
						return
					end
				end
				if handlers.onChip then
					handlers.onChip(spec)
				end
			end)
		end
	end
	chipRow.CanvasPosition = Vector2.zero
end

function UI.setChips(list: { any })
	baseChips = list or {}
	if open then
		render()
	end
end

function UI.setAnswers(list: { any }?)
	answers = list or {}
	if #answers > 0 then
		table.clear(stack)
	end
	if open then
		render()
	end
end

function UI.openSub(title: string, chips: { any })
	table.insert(stack, { chips = chips, title = title })
	render()
end

-------------------------------------------------------------------------------------------------
-- header
-------------------------------------------------------------------------------------------------
local STAT_ICON = { aff = "💗", tr = "🤝", an = "💢", fe = "😨", cl = "🫶" }
function UI.setView(v: any)
	if not header.title or type(v) ~= "table" then
		return
	end
	local name = v.name or "???"
	header.title.Text = string.format("%s %s", v.stageIcon or "🤍", name)
	local who = v.label ~= "" and v.label or ""
	local job = v.job or ""
	if utf8.len(job) and (utf8.len(job) :: number) > 16 then
		job = ""
	end
	header.sub.Text = string.format("%s%s%s · %s", who, if who ~= "" and job ~= "" then " · " else "", job, v.stageLabel or "")
	for key, t in header.stats do
		local val = math.floor((v[key] or 0) + 0.5)
		t.Text = string.format("%s%d", STAT_ICON[key], val)
		local warn = (key == "an" or key == "fe") and val >= 40
		t.TextColor3 = if warn then C.red elseif key == "aff" and val >= 50 then C.magenta else C.text
	end
end

function UI.typing(on: boolean, who: string?)
	if typing then
		typing.Visible = on
		typing.Text = if on then string.format("%s 말하는 중…", who or "") else ""
	end
	if sendBtn then
		sendBtn.AutoButtonColor = not on
		sendBtn.BackgroundTransparency = if on then 0.5 else 0
	end
end

function UI.setWanted(stars: number)
	build()
	if not wantedChip or not wantedText then
		return
	end
	local n = math.clamp(math.floor(stars or 0), 0, 5)
	wantedChip.Visible = n > 0
	wantedText.Text = "🚨 " .. string.rep("★", n) .. string.rep("☆", 5 - n)
end

-------------------------------------------------------------------------------------------------
-- open / close
-------------------------------------------------------------------------------------------------
function UI.open(view: any, h: any)
	build()
	if not panel then
		return
	end
	handlers = h or {}
	table.clear(stack)
	table.clear(answers)
	open = true
	place()
	panel.Visible = true
	UI.setView(view)
	render()
	if K and type(K.pop) == "function" then
		pcall(K.pop, panel)
	end
end

function UI.close()
	open = false
	handlers = {}
	table.clear(stack)
	table.clear(answers)
	if panel then
		panel.Visible = false
	end
	if input and input:IsFocused() then
		input:ReleaseFocus()
	end
	UI.typing(false)
end

function UI.isOpen(): boolean
	return open
end

function UI.typingFocus(): boolean
	return input ~= nil and input:IsFocused()
end

function UI.init(kit: any, layout: any)
	K = kit
	Layout = layout
	if type(K) == "table" then
		pcall(function()
			local c = K.Color or {}
			for k, v in c do
				if C[k] ~= nil and typeof(v) == "Color3" then
					C[k] = v
				end
			end
			local f = K.Font or {}
			if typeof(f.bold) == "EnumItem" then
				FONT_B = f.bold
			end
			if typeof(f.medium) == "EnumItem" then
				FONT_M = f.medium
			end
		end)
	end
	local _ = UserInputService
end

return UI
