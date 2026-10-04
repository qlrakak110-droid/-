--!strict
-- BowlingFX/Sheet: the 10-frame score sheet (GwangalliUI kit style).
--   Compact card: title line (lane / frame / roll) + small player chips (name + total, the bowler
--   highlighted), then one row of 10 frame cells (marks + running total; 10th frame has 3 boxes)
--   + the game total + a 10-pin diagram of the pins still standing. Tap the card: a dropdown with
--   every player's full row (scrolls past 3 players); tap a row to follow that player in the card.
--   Strikes "X" magenta, spares "/" cyan, split balls red, the current frame outlined gold.
--   Sheet.new(K, parent) -> api: layout(w), render(data), setExpanded(on), frame, drop

local Sheet = {}

type Cell = { box: Frame, marks: TextLabel, score: TextLabel, stroke: UIStroke }
type Row = { frame: GuiObject, name: TextLabel?, cells: { Cell }, total: TextLabel }

local MIN_TEXT = 11

local function markText(fi: any, f: number): (string, Color3?)
	local marks = fi and fi.marks or {}
	local splits = fi and fi.splits or {}
	local parts = {}
	local col: Color3? = nil
	local n = if f == 10 then 3 else 2
	for k = 1, n do
		local s = marks[k] or ""
		if s == "" and k == 1 and f < 10 and marks[2] == "X" then
			continue
		end
		if s ~= "" then
			table.insert(parts, s)
		end
		if splits[k] and s ~= "" then
			col = Color3.fromRGB(255, 110, 110)
		end
	end
	return table.concat(parts, " "), col
end

function Sheet.new(K: any, parent: Instance): any
	local C = K.Color
	local api: any = {}
	local expanded = false
	local focusId: number? = nil
	local lastData: any = nil
	local width = 520
	local rowsFor: { [number]: Row } = {}

	-- compact card (a button: tap to expand)
	local card = Instance.new("TextButton")
	card.Name = "Sheet"
	card.Text = ""
	card.AutoButtonColor = false
	card.BackgroundColor3 = C.glass
	card.BackgroundTransparency = 0.12
	card.BorderSizePixel = 0
	card.Size = UDim2.fromOffset(width, 66)
	card.ClipsDescendants = false
	K.corner(card, 14)
	K.stroke(card, nil, 1, 0.86)
	card.Parent = parent
	api.frame = card

	local title = K.text(card, { Name = "Title", Position = UDim2.fromOffset(10, 4), Size = UDim2.new(0.5, -10, 0, 20), Font = K.Font.bold, TextSize = 13, TextColor3 = C.text, TextTruncate = Enum.TextTruncate.AtEnd })
	local chips = K.frame(card, { Name = "Chips", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -30, 0, 4), Size = UDim2.new(0.5, -34, 0, 20) })
	local chipList = K.list(chips, true, 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local _ = chipList
	local caret = K.text(card, { Name = "Caret", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 3), Size = UDim2.fromOffset(18, 20), Text = "⌄", Font = K.Font.bold, TextSize = 16, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Center })

	local function makeCell(holder: Instance, f: number): Cell
		local box = K.frame(holder, { Name = if f <= 10 then ("F" .. f) else "Total", BackgroundTransparency = 0, BackgroundColor3 = C.card })
		K.corner(box, 6)
		local st = K.stroke(box, C.gold, 1.5, 1)
		local marks = K.text(box, { Name = "Marks", Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 0.5, 0), Font = K.Font.heavy, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Text = "" })
		local score = K.text(box, { Name = "Score", Position = UDim2.new(0, 1, 0.5, 0), Size = UDim2.new(1, -2, 0.5, -1), Font = K.Font.bold, TextSize = 13, TextColor3 = Color3.fromRGB(255, 232, 170), TextXAlignment = Enum.TextXAlignment.Center, Text = "" })
		return { box = box, marks = marks, score = score, stroke = st }
	end

	local function makeRow(holder: Instance, withName: boolean): Row
		local cells = {}
		for f = 1, 10 do
			cells[f] = makeCell(holder, f)
		end
		local tot = K.frame(holder, { Name = "TotalBox", BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(20, 44, 58) })
		K.corner(tot, 6)
		local total = K.text(tot, { Name = "Total", Size = UDim2.fromScale(1, 1), Font = K.Font.heavy, TextSize = 17, TextColor3 = C.cyan, TextXAlignment = Enum.TextXAlignment.Center, Text = "0" })
		local name = nil
		if withName then
			name = K.text(holder, { Name = "Name", Font = K.Font.bold, TextSize = 13, TextColor3 = C.text, TextTruncate = Enum.TextTruncate.AtEnd })
		end
		return { frame = holder :: any, name = name, cells = cells, total = total }
	end

	local cellsHolder = K.frame(card, { Name = "Cells", Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 0, 34) })
	local mainRow = makeRow(cellsHolder, false)

	-- pin diagram (back row on top)
	local pins = K.frame(cellsHolder, { Name = "Pins", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(38, 34) })
	local pinDots: { Frame } = {}
	local PX = { 0, -0.508, 0.508, -1.016, 0, 1.016, -1.524, -0.508, 0.508, 1.524 }
	local PR = { 1, 2, 2, 3, 3, 3, 4, 4, 4, 4 }
	for n = 1, 10 do
		local d = K.frame(pins, { Name = "P" .. n, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale((PX[n] + 1.524) / 3.048 * 0.82 + 0.09, (4 - PR[n]) / 3 * 0.78 + 0.11), Size = UDim2.fromOffset(7, 7), BackgroundTransparency = 0, BackgroundColor3 = C.text })
		K.corner(d, UDim.new(0.5, 0))
		pinDots[n] = d
	end

	-- dropdown: every player's row
	local drop = Instance.new("ScrollingFrame")
	drop.Name = "SheetDrop"
	drop.BackgroundColor3 = C.glass
	drop.BackgroundTransparency = 0.08
	drop.BorderSizePixel = 0
	drop.ScrollBarThickness = 4
	drop.ScrollingDirection = Enum.ScrollingDirection.Y
	drop.AutomaticCanvasSize = Enum.AutomaticSize.Y
	drop.CanvasSize = UDim2.new()
	drop.Visible = false
	drop.Active = true
	K.corner(drop, 14)
	K.stroke(drop, nil, 1, 0.86)
	drop.Parent = parent
	api.drop = drop
	local dropList = K.list(drop, false, 4)
	local _2 = dropList
	K.pad(drop, 8, 8, 8, 8)

	local function layoutRow(row: Row, w: number, h: number, nameW: number, pinsW: number)
		local gap = 2
		local inner = w - nameW - pinsW - (if pinsW > 0 then 6 else 0)
		local unit = (inner - 10 * gap - 4) / 11.6
		local x = nameW
		if row.name then
			row.name.Position = UDim2.fromOffset(0, 0)
			row.name.Size = UDim2.fromOffset(nameW - 6, h)
		end
		for f = 1, 10 do
			local cw = if f == 10 then unit * 1.32 else unit
			local cell = row.cells[f]
			cell.box.Position = UDim2.fromOffset(x, 0)
			cell.box.Size = UDim2.fromOffset(cw, h)
			x += cw + gap
		end
		local tb = row.total.Parent :: Frame
		tb.Position = UDim2.fromOffset(x + 2, 0)
		tb.Size = UDim2.fromOffset(unit * 1.28, h)
		local small = unit < 26
		for f = 1, 10 do
			local cell = row.cells[f]
			cell.marks.TextSize = if small then MIN_TEXT + 1 else 13
			cell.score.TextSize = if small then MIN_TEXT + 1 else 13
		end
	end

	function api.layout(w: number)
		width = w
		card.Size = UDim2.fromOffset(w, 66)
		layoutRow(mainRow, w - 16, 34, 0, 44)
		drop.Size = UDim2.fromOffset(w, math.min(#(lastData and lastData.players or {}) * 50 + 16, 216))
		for _, r in rowsFor do
			layoutRow(r, w - 16, 44, 70, 0);
			(r.frame :: Frame).Size = UDim2.new(1, 0, 0, 46)
		end
	end

	local function fillRow(row: Row, p: any, current: boolean)
		local b = p and p.board
		local frames = b and b.frames or {}
		local gp = b and b.current or 1
		for f = 1, 10 do
			local cell = row.cells[f]
			local fi = frames[f]
			local txt, col = markText(fi, f)
			cell.marks.Text = txt
			cell.marks.TextColor3 = col or (if string.find(txt, "X", 1, true) then C.magenta elseif string.find(txt, "/", 1, true) then C.cyan else C.text)
			cell.score.Text = if fi and fi.score then tostring(fi.score) else ""
			local cur = current and b and not b.over and f == gp
			cell.stroke.Transparency = if cur then 0.05 else 1
			cell.box.BackgroundColor3 = if cur then C.card2 else C.card
		end
		row.total.Text = tostring(b and b.total or 0)
	end

	local function chip(i: number): TextLabel
		local c = chips:FindFirstChild("Chip" .. i) :: TextLabel?
		if c then
			return c
		end
		local l = K.text(chips, { Name = "Chip" .. i, LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), Font = K.Font.bold, TextSize = 12, TextColor3 = C.sub, BackgroundTransparency = 0.2, BackgroundColor3 = C.card2 })
		K.corner(l, UDim.new(0.5, 0))
		K.pad(l, 7, 7, 0, 0)
		return l
	end

	local function rowButton(uid: number): Row
		local r = rowsFor[uid]
		if r then
			return r
		end
		local holder = Instance.new("TextButton")
		holder.Name = "Player_" .. uid
		holder.Text = ""
		holder.AutoButtonColor = false
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, 0, 0, 46)
		holder.Parent = drop
		local row = makeRow(holder, true)
		rowsFor[uid] = row
		holder.Activated:Connect(function()
			focusId = uid
			api.setExpanded(false)
			if lastData then
				api.render(lastData)
			end
			K.feedback("tap")
		end)
		layoutRow(row, width - 16, 44, 70, 0)
		return row
	end

	-- data = { title, players = {{userId, name, board, total, over}}, bowler, me, standing = {0/1 x10} }
	function api.render(data: any)
		lastData = data
		title.Text = data.title or ""
		local players = data.players or {}
		-- the card follows: the focused player, else the bowler, else me, else the first player
		local show = nil
		for _, p in players do
			if p.userId == focusId then
				show = p
			end
		end
		if not show then
			focusId = nil
			for _, p in players do
				if p.userId == data.bowler then
					show = p
				end
			end
		end
		if not show then
			for _, p in players do
				if p.userId == data.me then
					show = p
				end
			end
		end
		show = show or players[1]
		fillRow(mainRow, show, show ~= nil and show.userId == data.bowler)
		for i = 1, 4 do
			local p = players[i]
			local c = chip(i)
			c.Visible = p ~= nil
			if p then
				local isB = p.userId == data.bowler
				c.Text = (if isB then "● " else "") .. string.sub(p.name or "?", 1, 14) .. " " .. tostring(p.total or 0)
				c.TextColor3 = if isB then C.onGold else (if p.over then C.faint else C.text)
				c.BackgroundColor3 = if isB then C.gold else C.card2
				c.BackgroundTransparency = if p == show and not isB then 0 else (if isB then 0 else 0.3)
			end
		end
		caret.Visible = #players > 1
		-- pins
		local st = data.standing or {}
		for n = 1, 10 do
			pinDots[n].BackgroundTransparency = if (st[n] == 1 or st[n] == true) then 0 else 0.82
		end
		-- dropdown rows
		local seen = {}
		for i, p in players do
			seen[p.userId] = true
			local r = rowButton(p.userId)
			local holder = r.frame :: TextButton
			holder.LayoutOrder = i
			if r.name then
				r.name.Text = (if p.userId == data.bowler then "▶ " else "") .. (p.name or "?")
				r.name.TextColor3 = if p.userId == data.bowler then C.gold elseif p.over then C.faint else C.text
			end
			fillRow(r, p, p.userId == data.bowler)
		end
		for uid, r in rowsFor do
			if not seen[uid] then
				(r.frame :: Instance):Destroy()
				rowsFor[uid] = nil
			end
		end
		drop.Size = UDim2.fromOffset(width, math.min(#players * 50 + 16, 216))
	end

	local collapseAt = 0
	function api.setExpanded(on: boolean)
		local can = lastData and #(lastData.players or {}) > 0
		expanded = on and can == true
		drop.Visible = expanded
		caret.Text = if expanded then "⌃" else "⌄"
		if expanded then
			drop.Position = card.Position + UDim2.fromOffset(0, 70)
			drop.AnchorPoint = card.AnchorPoint
			K.springIn(drop, 0.94, { duration = 0.24 })
			collapseAt = os.clock() + 7
			local mine = collapseAt
			task.delay(7.1, function()
				if expanded and collapseAt == mine then
					api.setExpanded(false)
				end
			end)
		end
	end

	function api.expanded(): boolean
		return expanded
	end

	card.Activated:Connect(function()
		api.setExpanded(not expanded)
		K.feedback("tap")
	end)

	return api
end

return Sheet
