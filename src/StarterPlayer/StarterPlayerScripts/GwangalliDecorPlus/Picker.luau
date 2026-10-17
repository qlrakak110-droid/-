--!strict
-- GwangalliDecorPlus/Picker: 색 · 재질 picker — curated swatch groups (Palette), an HSV picker (saturation /
-- value square + hue bar, drag with mouse, touch or gamepad), hex readout, and the slot's material chips.
--   Picker.item(gui, id, look, onApply(c, m), onPreview?(c, m))  per colour slot of a catalog piece
--   Picker.color(gui, title, rgb, onApply(rgb))                   one free colour (벽지 · 바닥 colours)

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliDecorShared"))
local Catalog, Palette = Shared.Catalog, Shared.Palette

local Ui = require(script.Parent:WaitForChild("Ui"))
local C, F = Ui.C, Ui.F

local Picker = {}

-- HSV block: returns frame + set(rgb) ; onChange(rgb) while dragging
local function hsvBlock(parent: Instance, rgb: { number }, onChange: ({ number }) -> ()): (Frame, ({ number }) -> ())
	local h, s, v = Palette.hsv(rgb)
	local holder = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 214), Parent = parent })
	local sq = Ui.new("ImageButton", { Name = "SV", AutoButtonColor = false, BackgroundColor3 = Color3.fromHSV(h, 1, 1), Size = UDim2.new(1, -70, 0, 170), Selectable = true, Parent = holder })
	Ui.corner(sq, 10)
	local white = Ui.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 1, 0), Parent = sq })
	Ui.corner(white, 10)
	Ui.new("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
	local black = Ui.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.new(1, 0, 1, 0), Parent = sq })
	Ui.corner(black, 10)
	Ui.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = black })
	local knob = Ui.new("Frame", { Size = UDim2.new(0, 18, 0, 18), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Parent = sq })
	Ui.corner(knob, 9)
	Ui.stroke(knob, Color3.new(1, 1, 1), 0, 3)
	local hue = Ui.new("ImageButton", { Name = "Hue", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0, 26, 0, 170), Position = UDim2.new(1, -56, 0, 0), Selectable = true, Parent = holder })
	Ui.corner(hue, 8)
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 % 1, 1, 1)))
	end
	Ui.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(keys), Parent = hue })
	local hk = Ui.new("Frame", { Size = UDim2.new(1, 8, 0, 6), Position = UDim2.new(0, -4, 0, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Parent = hue })
	Ui.corner(hk, 3)
	local sw = Ui.new("Frame", { Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(1, -24, 0, 0), BackgroundColor3 = Palette.color3(rgb), Parent = holder })
	Ui.corner(sw, 11)
	local hex = Ui.label(holder, "#" .. string.upper(Palette.hex(rgb)), 13, C.sub, F.medium, { Position = UDim2.new(0, 0, 0, 178), Size = UDim2.new(1, 0, 0, 22) })
	local function redraw()
		sq.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		knob.Position = UDim2.new(s, 0, 1 - v, 0)
		hk.Position = UDim2.new(0, -4, h, 0)
		local c = Palette.fromHsv(h, s, v)
		sw.BackgroundColor3 = Palette.color3(c)
		hex.Text = "#" .. string.upper(Palette.hex(c))
	end
	redraw()
	local function emit()
		onChange(Palette.fromHsv(h, s, v))
	end
	local dragging: string? = nil
	local function at(target: GuiObject, pos: Vector2): (number, number)
		local p, sz = target.AbsolutePosition, target.AbsoluteSize
		return math.clamp((pos.X - p.X) / math.max(sz.X, 1), 0, 1), math.clamp((pos.Y - p.Y) / math.max(sz.Y, 1), 0, 1)
	end
	local function move(pos: Vector2)
		if dragging == "sv" then
			local x, y = at(sq, pos)
			s, v = x, 1 - y
		elseif dragging == "hue" then
			local _, y = at(hue, pos)
			h = math.clamp(y, 0, 0.999)
		end
		redraw()
		emit()
	end
	local function begin(which: string)
		return function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = which
				move(Vector2.new(input.Position.X, input.Position.Y))
			end
		end
	end
	sq.InputBegan:Connect(begin("sv"))
	hue.InputBegan:Connect(begin("hue"))
	local c1 = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			move(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = nil
		end
	end)
	-- gamepad: d-pad / stick nudges while the square or bar is selected
	local c3 = UserInputService.InputBegan:Connect(function(input)
		local sel = GuiService.SelectedObject
		if sel ~= sq and sel ~= hue then
			return
		end
		local k = input.KeyCode
		local dx = if k == Enum.KeyCode.DPadRight then 1 elseif k == Enum.KeyCode.DPadLeft then -1 else 0
		local dy = if k == Enum.KeyCode.DPadDown then 1 elseif k == Enum.KeyCode.DPadUp then -1 else 0
		if dx == 0 and dy == 0 then
			return
		end
		if sel == sq then
			s = math.clamp(s + dx * 0.08, 0, 1)
			v = math.clamp(v - dy * 0.08, 0, 1)
		else
			h = (h + dy * 0.03) % 1
		end
		redraw()
		emit()
	end)
	holder.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
		c3:Disconnect()
	end)
	local function set(c: { number })
		h, s, v = Palette.hsv(c)
		redraw()
	end
	return holder, set
end

local function swatchGrid(parent: Instance, onPick: ({ number }) -> (), lights: boolean?)
	local groups: { any } = {}
	if lights then
		table.insert(groups, { name = "빛 색", list = Palette.LIGHTS })
	end
	for _, g in Palette.SWATCH_GROUPS do
		table.insert(groups, { name = g.name, list = (Palette.SWATCHES :: any)[g.id] })
	end
	for gi, g in groups do
		Ui.label(parent, g.name, 13, C.sub, F.bold, { LayoutOrder = gi * 2, Size = UDim2.new(1, 0, 0, 18) })
		local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = gi * 2 + 1, Parent = parent })
		Ui.new("UIGridLayout", { CellSize = UDim2.new(0, 40, 0, 40), CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
		for i, s in g.list do
			local b = Ui.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Palette.color3(s[3]), LayoutOrder = i, Selectable = true, Parent = row })
			Ui.corner(b, 20)
			Ui.stroke(b, Color3.new(1, 1, 1), 0.7, 1)
			Ui.pressable(b)
			b:SetAttribute("Tip", s[2])
			b.Activated:Connect(function()
				onPick(s[3])
			end)
		end
	end
end

-- per-slot colour + material of a catalog piece
function Picker.item(gui: Instance, id: string, look: any, onApply: (any, any) -> (), onPreview: ((any, any) -> ())?)
	local def = Catalog.get(id)
	if not def or #def.slots == 0 then
		Ui.toast("이 가구는 색을 바꿀 수 없어요")
		return
	end
	local c = table.clone(look and look.c or {})
	local m = table.clone(look and look.m or {})
	for i = 1, #def.slots do
		if c[i] == nil then
			c[i] = false
		end
		if m[i] == nil then
			m[i] = 1
		end
	end
	local modal = Ui.modal("🎨 " .. def.name, { gui = gui, w = 460, h = 0.86 })
	local body = modal.body
	local slot = 1
	local function cur(): { number }
		local s = def.slots[slot]
		return if type(c[slot]) == "string" then (Palette.unhex(c[slot]) or s.rgb) else s.rgb
	end
	local setHsv: any = nil
	local matRow: Frame? = nil
	local nameLbl = Ui.label(body, "", 14, C.text, F.bold, { LayoutOrder = 3 })
	local function preview()
		if onPreview then
			onPreview(c, m)
		end
	end
	local function refreshMats()
		if matRow then
			matRow:Destroy()
		end
		local s = def.slots[slot]
		if #s.mats <= 1 then
			matRow = nil
			return
		end
		matRow = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6, Parent = body })
		local lay = Ui.list(matRow :: Frame, "x", 8)
		pcall(function()
			(lay :: any).Wraps = true
		end)
		local sets = {}
		for mi, key in s.mats do
			local md = (Palette.MATERIALS :: any)[key]
			local btn, setOn = Ui.chip(matRow, md and md.name or key, (m[slot] or 1) == mi, nil, mi)
			sets[mi] = setOn
			btn.Activated:Connect(function()
				m[slot] = mi
				for j, f in sets do
					f(j == mi)
				end
				preview()
			end)
		end
	end
	local function refreshName()
		local s = def.slots[slot]
		nameLbl.Text = s.label .. " · " .. (if s.isLight then "빛 색" else Palette.nameOf(cur()))
	end
	if #def.slots > 1 then
		local opts = {}
		for i, s in def.slots do
			table.insert(opts, { i, s.label })
		end
		local seg = Ui.segmented(body, opts, 1, function(i)
			slot = i
			if setHsv then
				setHsv(cur())
			end
			refreshName()
			refreshMats()
		end)
		seg.LayoutOrder = 1
	end
	refreshName()
	local hsv, set = hsvBlock(body, cur(), function(rgb)
		c[slot] = Palette.hex(rgb)
		refreshName()
		preview()
	end)
	hsv.LayoutOrder = 4
	setHsv = set
	refreshMats()
	local sw = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 8, Parent = body })
	Ui.list(sw, "y", 6)
	swatchGrid(sw, function(rgb)
		c[slot] = Palette.hex(rgb)
		set(rgb)
		refreshName()
		preview()
	end, def.slots[slot].isLight or def.slotIndex.light ~= nil)
	local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), LayoutOrder = 10, Parent = body })
	Ui.list(row, "x", 10, Enum.HorizontalAlignment.Right)
	Ui.button(row, { text = "기본값", w = 100, h = 46, style = "ghost", onClick = function()
		for i = 1, #def.slots do
			c[i] = false
			m[i] = 1
		end
		set(cur())
		refreshName()
		refreshMats()
		preview()
	end })
	Ui.button(row, { text = "✓ 적용", w = 140, h = 46, style = "primary", onClick = function()
		modal.close()
		onApply(c, m)
	end })
	return modal
end

-- one free colour (finish colours)
function Picker.color(gui: Instance, title: string, rgb: { number }, onApply: ({ number }) -> ())
	local modal = Ui.modal(title, { gui = gui, w = 440, h = 0.8 })
	local cur = rgb
	local hsv, set = hsvBlock(modal.body, rgb, function(c)
		cur = c
	end)
	hsv.LayoutOrder = 1
	local sw = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = modal.body })
	Ui.list(sw, "y", 6)
	swatchGrid(sw, function(c)
		cur = c
		set(c)
	end, false)
	local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), LayoutOrder = 3, Parent = modal.body })
	Ui.list(row, "x", 10, Enum.HorizontalAlignment.Right)
	Ui.button(row, { text = "✓ 이 색으로", w = 150, h = 46, style = "primary", onClick = function()
		modal.close()
		onApply(cur)
	end })
	return modal
end

return Picker
