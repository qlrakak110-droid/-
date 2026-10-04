--!nocheck
-- GwangalliJobs/Games: one COMPACT builder per round for the bottom sheet (Stage.luau). The world does
-- the showing (World.luau: counter props, glowing shelf items, the cup at the machine); the sheet only
-- carries the few big buttons a phone needs (>= 56 px), in ONE ROW on landscape phones (the sheet is
-- <= 30 % of the screen height) and a small grid on portrait ones.
-- builder(api, view, p) -> { timeout() -> partial answer, destroy()?, bodyHeight?, compact?, onResult? }
-- api: { K, JS, J, World, body, landscape, p, submit, shake, flash, setHint, setBodyHeight, bodyMax,
--        setCompact, setChip, isCurrent, timeLeft }

local TweenService = game:GetService("TweenService")

local Games = {}

local GAP = 8
local TILE = 60 -- tile height (touch target >= 56 px)

local function world(api: any, fn: string, ...: any): any
	local W = api.World
	if W and type(W[fn]) == "function" then
		local ok, res = pcall(W[fn], ...)
		if ok then
			return res
		end
		warn("[GwangalliJobs] World." .. fn .. ": " .. tostring(res))
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- Pieces
-------------------------------------------------------------------------------------------------
-- a big tile: icon + label (+ sub). states: idle / done / wrong / dim / gold
local function tile(K: any, parent: Instance, o: any): any
	local b = K.make("TextButton", {
		Name = o.name or "Tile",
		Size = o.size or UDim2.fromOffset(o.w or 76, o.h or TILE),
		BackgroundColor3 = K.Color.card2,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = o.order or 0,
		ZIndex = 13,
	}, parent)
	K.corner(b, K.Radius.sm)
	local stroke = K.stroke(b, nil, 1.2, 0.85)
	local hasSub = o.sub ~= nil and o.sub ~= ""
	local icon = K.text(b, { Name = "Icon", Position = UDim2.new(0, 0, 0, if hasSub then 3 else 5), Size = UDim2.new(1, 0, 0, if o.iconOnly then (o.h or TILE) - 10 else 26), Text = o.icon or "", TextSize = if o.iconOnly then 28 else 22, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 14 })
	local title = K.text(b, { Name = "Title", Position = UDim2.new(0, 3, 0, if hasSub then 29 else 33), Size = UDim2.new(1, -6, 0, 15), Text = o.title or "", Font = K.Font.bold, TextSize = K.Type.micro + 1, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Visible = not o.iconOnly, ZIndex = 14 })
	local sub = K.text(b, { Name = "Sub", Position = UDim2.new(0, 3, 0, 44), Size = UDim2.new(1, -6, 0, 13), Text = o.sub or "", TextColor3 = o.subColor or K.Color.sub, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Visible = hasSub, ZIndex = 14 })
	K.pressable(b, { scale = 0.94 })
	local api = { button = b, stroke = stroke, icon = icon, title = title, sub = sub, state = "idle" }
	function api.setState(state: string)
		api.state = state
		if state == "done" then
			stroke.Color, stroke.Transparency = K.Color.green, 0.2
			b.BackgroundColor3 = Color3.fromRGB(28, 60, 46)
		elseif state == "wrong" then
			stroke.Color, stroke.Transparency = K.Color.red, 0.2
			b.BackgroundColor3 = Color3.fromRGB(70, 30, 36)
		elseif state == "gold" then
			stroke.Color, stroke.Transparency = K.Color.gold, 0
			b.BackgroundColor3 = Color3.fromRGB(62, 54, 30)
		elseif state == "dim" then
			stroke.Color, stroke.Transparency = K.Color.line, 0.92
			b.BackgroundColor3 = K.Color.card
		else
			stroke.Color, stroke.Transparency = K.Color.line, 0.85
			b.BackgroundColor3 = K.Color.card2
		end
	end
	if o.onClick then
		b.Activated:Connect(function()
			if api.state == "done" or api.state == "dim" then
				return
			end
			local ok, err = pcall(o.onClick, api)
			if not ok then
				warn("[GwangalliJobs] tile: " .. tostring(err))
			end
		end)
	end
	return api
end

local function bump(K: any, g: GuiObject, ok: boolean)
	if K.reduced() then
		return
	end
	task.spawn(function()
		local base = g.Position
		if ok then
			K.pop(g, 1.12)
		else
			for _, dx in { 6, -6, 4, -4, 0 } do
				if not g.Parent then
					return
				end
				g.Position = base + UDim2.fromOffset(dx, 0)
				task.wait(0.03)
			end
			g.Position = base
		end
	end)
end

-- a row of tiles (landscape: one horizontal scrolling row; portrait: a wrapping grid)
local function tileArea(api: any, parent: Instance, landscape: boolean, cols: number?): ScrollingFrame
	local K = api.K
	local sf = K.make("ScrollingFrame", {
		Name = "Tiles",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.5,
		ScrollingDirection = if landscape then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = if landscape then Enum.AutomaticSize.X else Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.Never,
		ZIndex = 13,
	}, parent)
	if landscape then
		K.list(sf, true, GAP, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	else
		local g = K.make("UIGridLayout", {
			CellPadding = UDim2.fromOffset(GAP, GAP),
			CellSize = UDim2.new(1 / (cols or 3), -GAP, 0, TILE),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, sf)
		local _ = g
	end
	return sf
end

local function label(K: any, parent: Instance, props: any): TextLabel
	local p = table.clone(props)
	p.ZIndex = p.ZIndex or 13
	return K.text(parent, p)
end

local function bigChoice(api: any, parent: Instance, text: string, order: number, onClick: () -> ()): TextButton
	local K = api.K
	return K.Button(parent, { name = "Choice" .. order, text = text, style = "secondary", order = order, size = UDim2.new(1, 0, 0, TILE - 4), textSize = K.Type.bodySm, zIndex = 13, onClick = onClick })
end

-- left info block + right content (landscape) / stacked (portrait)
local function split(api: any, infoW: number, infoH: number): (Frame, Frame)
	local K = api.K
	local body = api.body
	local info = K.frame(body, { Name = "Info", BackgroundTransparency = 0.35, BackgroundColor3 = K.Color.card, ZIndex = 13 })
	K.corner(info, K.Radius.sm)
	local main = K.frame(body, { Name = "Main", ZIndex = 13 })
	if api.landscape then
		info.Size = UDim2.new(0, infoW, 1, 0)
		main.Position = UDim2.fromOffset(infoW + GAP, 0)
		main.Size = UDim2.new(1, -(infoW + GAP), 1, 0)
	else
		info.Size = UDim2.new(1, 0, 0, infoH)
		main.Position = UDim2.fromOffset(0, infoH + GAP)
		main.Size = UDim2.new(1, 0, 1, -(infoH + GAP))
	end
	return info, main
end

-------------------------------------------------------------------------------------------------
-- 계산 (world sale): tap the items ON THE COUNTER (or the tiles), then the change / card
-------------------------------------------------------------------------------------------------
Games.sale = function(api: any, view: any, _p: any): any
	local K = api.K
	local items = view.items or {}
	local scans: { string } = {}
	local scanned: { [number]: boolean } = {}
	local total = 0
	local phase = "scan"
	local changePick: number? = nil
	local tiles: { any } = {}
	local info, main = split(api, 170, 40)
	local status = label(K, info, { Name = "Status", Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 18), Text = "", Font = K.Font.bold, TextSize = K.Type.caption + 1, TextTruncate = Enum.TextTruncate.AtEnd })
	local totalLabel = label(K, info, { Name = "Total", Position = UDim2.new(0, 8, 0, if api.landscape then 24 else 20), Size = UDim2.new(1, -16, 0, 18), Text = "합계 0원", TextColor3 = K.Color.green, Font = K.Font.heavy, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd })
	K.mono(totalLabel)
	local sayLabel = label(K, info, { Name = "Say", Position = UDim2.fromOffset(8, 44), Size = UDim2.new(1, -16, 0, 16), Text = string.format("%s \"%s\"", tostring(view.customer or "🧑"), tostring(view.say or "계산이요")), TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd, Visible = api.landscape })
	local _ = sayLabel
	local area = tileArea(api, main, api.landscape, 5)
	area.Size = UDim2.fromScale(1, 1)

	local function refresh()
		K.setText(status, string.format("🧾 스캔 %d/%d", #scans, #items))
		K.setText(totalLabel, "합계 " .. K.won(total))
		world(api, "saleTotal", #scans, total, items, scanned)
	end

	local function finish()
		local ans: any = { scans = scans, change = changePick }
		api.submit(ans)
	end

	local function payPhase()
		phase = "pay"
		for _, c in area:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if view.method == "cash" then
			api.setHint(string.format("현금 %s 받았어요 · 거스름돈은?", K.won(view.paid or 0)))
			K.setText(status, string.format("💵 받은 돈 %s", K.won(view.paid or 0)))
			world(api, "salePay", "cash", view.paid)
			for i, ch in view.choices or {} do
				local t = tile(K, area, { name = "Change" .. i, icon = "🪙", title = tostring(ch), sub = "거스름돈", w = 108, order = i, onClick = function(self)
					if phase ~= "pay" then
						return
					end
					phase = "done"
					changePick = i
					self.setState("gold")
					api.J.sfx("coin")
					world(api, "saleChange", i)
					task.delay(0.25, finish)
				end })
				local _ = t
			end
		else
			api.setHint("카드 결제예요 · 단말기에 꽂아 주세요")
			K.setText(status, "💳 카드 결제")
			world(api, "salePay", "card")
			tile(K, area, { name = "Card", icon = "💳", title = "카드 결제 완료", sub = K.won(total), w = 160, order = 1, onClick = function(self)
				if phase ~= "pay" then
					return
				end
				phase = "done"
				self.setState("gold")
				api.J.sfx("beep")
				task.delay(0.25, finish)
			end })
		end
	end

	local function scan(i: number)
		if phase ~= "scan" or scanned[i] or not api.isCurrent() then
			return
		end
		local it = items[i]
		if not it then
			return
		end
		scanned[i] = true
		table.insert(scans, it.id)
		total += tonumber(it.price) or 0
		api.J.sfx("beep")
		pcall(api.K.haptic, "light")
		if tiles[i] then
			tiles[i].setState("done")
			bump(K, tiles[i].button, true)
		end
		world(api, "saleScanned", i, it)
		refresh()
		if #scans >= #items then
			task.delay(0.35, payPhase)
		end
	end

	for i, it in items do
		tiles[i] = tile(K, area, { name = "Item" .. i, icon = it.icon, title = it.name, sub = K.won(it.price), w = 76, order = i, onClick = function()
			scan(i)
		end })
	end
	world(api, "saleStart", api.p, scan)
	refresh()
	api.setBodyHeight(if api.landscape then TILE + 4 else 40 + GAP + TILE * 2 + GAP + 4)
	return {
		timeout = function()
			return { scans = scans, change = changePick }
		end,
		destroy = function()
			world(api, "saleStop")
		end,
	}
end

-------------------------------------------------------------------------------------------------
-- 재고 정리 (world restock): carry the box (compact chip, walk freely), at a glowing slot pick the
-- items that belong there
-------------------------------------------------------------------------------------------------
Games.shelf = function(api: any, view: any, _p: any): any
	local K = api.K
	local items = view.items or {}
	local bins = view.bins or {}
	local placed: { [string]: string } = {} -- item id -> category
	local left = #items
	local currentCat: string? = nil
	local done = false
	local binName: { [string]: string } = {}
	for _, b in bins do
		binName[b.cat] = b.name
	end

	local function boxText(): string
		local icons = {}
		for _, it in items do
			if not placed[it.id] then
				table.insert(icons, it.icon)
			end
		end
		return string.format("📦 박스: %s  ·  빛나는 칸 앞에서 진열", table.concat(icons, " "))
	end

	local function answer(): any
		local out = {}
		for id, cat in placed do
			table.insert(out, { id = id, cat = cat })
		end
		return out
	end

	local function finish()
		if done then
			return
		end
		done = true
		world(api, "restockStop")
		api.submit(answer())
	end

	local info, main = split(api, 160, 34)
	local catLabel = label(K, info, { Name = "Cat", Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 18), Text = "", Font = K.Font.bold, TextSize = K.Type.caption + 1, TextTruncate = Enum.TextTruncate.AtEnd })
	local subLabel = label(K, info, { Name = "Sub", Position = UDim2.fromOffset(8, 22), Size = UDim2.new(1, -16, 0, 30), Text = "이 칸에 맞는 상품을 골라요", TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextWrapped = true, Visible = api.landscape })
	local _ = subLabel
	local area = tileArea(api, main, api.landscape, 4)
	area.Size = UDim2.fromScale(1, 1)

	local function closePicker()
		currentCat = nil
		api.setChip(boxText())
		api.setCompact(true)
		api.setHint("빛나는 진열 칸으로 박스를 들고 가요")
	end

	local function fill()
		for _, c in area:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for i, it in items do
			if not placed[it.id] then
				tile(K, area, { name = "Item" .. i, icon = it.icon, title = it.name, w = 76, order = i, onClick = function(self)
					if done or not currentCat or placed[it.id] then
						return
					end
					placed[it.id] = currentCat
					left -= 1
					self.setState("done")
					api.J.sfx("place")
					world(api, "restockPlace", currentCat, it)
					if left <= 0 then
						task.delay(0.3, finish)
					else
						task.delay(0.15, function()
							if not done and currentCat then
								fill()
							end
						end)
					end
				end })
			end
		end
		K.Button(area, { name = "Close", text = "다른 칸", style = "ghost", order = 99, size = UDim2.fromOffset(76, TILE), textSize = K.Type.caption, zIndex = 13, onClick = closePicker })
	end

	-- a slot prompt in the world was used
	local function onSlot(cat: string)
		if done or not api.isCurrent() then
			return
		end
		currentCat = cat
		K.setText(catLabel, "🧺 " .. tostring(binName[cat] or cat) .. " 칸")
		api.setHint(string.format("%s 칸에 넣을 상품을 톡! (다 넣으면 끝)", tostring(binName[cat] or cat)))
		fill()
		api.setCompact(false)
	end

	world(api, "restockStart", api.p, onSlot)
	api.setChip(boxText())
	api.setHint("창고 박스를 들었어요 · 빛나는 진열 칸으로!")
	api.setBodyHeight(if api.landscape then TILE + 4 else 34 + GAP + TILE * 2 + GAP + 4)
	return {
		compact = true,
		timeout = function()
			return answer()
		end,
		destroy = function()
			world(api, "restockStop")
		end,
	}
end

-------------------------------------------------------------------------------------------------
-- 유통기한 (world expiry): the 4 items glow on the showcase; tap the expired one (world or tile)
-------------------------------------------------------------------------------------------------
Games.expiry = function(api: any, view: any, _p: any): any
	local K = api.K
	local picked = false
	local info, main = split(api, 140, 30)
	label(K, info, { Name = "Today", Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 18), Text = "📅 오늘 " .. tostring(view.today or ""), Font = K.Font.bold, TextSize = K.Type.caption + 1, TextTruncate = Enum.TextTruncate.AtEnd })
	label(K, info, { Name = "Sub", Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -16, 0, 30), Text = "날짜 지난 걸 빼요", TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextWrapped = true, Visible = api.landscape })
	local area = tileArea(api, main, api.landscape, 4)
	area.Size = UDim2.fromScale(1, 1)
	local tiles = {}
	local function pick(i: number)
		if picked or not api.isCurrent() then
			return
		end
		picked = true
		if tiles[i] then
			tiles[i].setState("gold")
		end
		api.J.sfx("place")
		world(api, "expiryPicked", i)
		task.delay(0.25, function()
			api.submit(i)
		end)
	end
	for i, it in view.items or {} do
		tiles[i] = tile(K, area, { name = "Item" .. i, icon = it.icon, title = it.name, sub = "~" .. tostring(it.date or ""), subColor = K.Color.orange, w = 84, order = i, onClick = function()
			pick(i)
		end })
	end
	world(api, "expiryStart", api.p, pick)
	api.setBodyHeight(if api.landscape then TILE + 4 else 30 + GAP + TILE * 2 + GAP + 4)
	return {
		timeout = function()
			return nil
		end,
		destroy = function()
			world(api, "expiryStop")
		end,
	}
end

-------------------------------------------------------------------------------------------------
-- 택배 접수 (customer with a box on the counter): weight + destination, pick the fee
-------------------------------------------------------------------------------------------------
Games.parcel = function(api: any, view: any, _p: any): any
	local K = api.K
	local picked = false
	local info, main = split(api, 200, 44)
	label(K, info, { Name = "Box", Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 18), Text = string.format("📦 %s → %s", tostring(view.weight or "?"), tostring(view.dest or "")), Font = K.Font.bold, TextSize = K.Type.caption + 1, TextTruncate = Enum.TextTruncate.AtEnd })
	local rates = {}
	for _, r in view.rates or {} do
		table.insert(rates, string.format("%s %s", r.label, r.price))
	end
	label(K, info, { Name = "Rates", Position = UDim2.fromOffset(8, 22), Size = UDim2.new(1, -16, 1, -24), Text = table.concat(rates, " · ") .. string.format(" · %dkg 초과 불가", tonumber(view.maxKg) or 20), TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	local area = tileArea(api, main, api.landscape, 3)
	area.Size = UDim2.fromScale(1, 1)
	for i, ch in view.choices or {} do
		tile(K, area, { name = "Fee" .. i, icon = if string.find(tostring(ch), "불가") then "🚫" else "💰", title = tostring(ch), w = 120, order = i, onClick = function(self)
			if picked or not api.isCurrent() then
				return
			end
			picked = true
			self.setState("gold")
			api.J.sfx("printer")
			task.delay(0.25, function()
				api.submit(i)
			end)
		end })
	end
	world(api, "parcelStart", api.p)
	api.setBodyHeight(if api.landscape then TILE + 4 else 44 + GAP + TILE + 4)
	return {
		timeout = function()
			return nil
		end,
		destroy = function()
			world(api, "parcelStop")
		end,
	}
end

-------------------------------------------------------------------------------------------------
-- 손님 응대 (ask): the customer's question (also in its bubble) + 3 answers
-------------------------------------------------------------------------------------------------
Games.ask = function(api: any, view: any, _p: any): any
	local K = api.K
	local picked = false
	local info, main = split(api, 230, 40)
	local q = tostring(view.question or "")
	q = string.gsub(q, "^손님:%s*", "")
	label(K, info, { Name = "Q", Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -16, 1, -6), Text = string.format("%s %s", tostring(view.customer or "🧑"), q), Font = K.Font.bold, TextSize = K.Type.caption, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Center })
	local area = tileArea(api, main, api.landscape, 1)
	area.Size = UDim2.fromScale(1, 1)
	if not api.landscape then
		local grid = area:FindFirstChildOfClass("UIGridLayout")
		if grid then
			grid.CellSize = UDim2.new(1, 0, 0, TILE - 8)
		end
	end
	for i, ch in view.choices or {} do
		local b = K.Button(area, { name = "Answer" .. i, text = tostring(ch), style = "secondary", order = i, size = UDim2.fromOffset(150, TILE - 4), textSize = K.Type.caption + 1, zIndex = 13 })
		b.TextWrapped = true
		b.Activated:Connect(function()
			if picked or not api.isCurrent() then
				return
			end
			picked = true
			b.BackgroundColor3 = Color3.fromRGB(62, 54, 30)
			task.delay(0.2, function()
				api.submit(i)
			end)
		end)
	end
	api.setBodyHeight(if api.landscape then TILE + 4 else 40 + GAP + 3 * (TILE - 8 + GAP) + 4)
	return {
		timeout = function()
			return nil
		end,
	}
end

-------------------------------------------------------------------------------------------------
-- 음료 만들기 (cafe): the order card + ingredients; each tap pours into the cup at the machine
-------------------------------------------------------------------------------------------------
Games.drink = function(api: any, view: any, _p: any): any
	local K = api.K
	local steps = view.steps or {}
	local seq: { string } = {}
	local done = false
	local info, main = split(api, 190, 40)
	local d = view.drink or {}
	label(K, info, { Name = "Order", Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -16, 0, 18), Text = string.format("%s %s · %s", tostring(d.icon or "☕"), tostring(d.name or ""), tostring(view.size or "")), Font = K.Font.bold, TextSize = K.Type.caption + 1, TextTruncate = Enum.TextTruncate.AtEnd })
	local parts = {}
	for i, s in steps do
		table.insert(parts, string.format("%d %s%s", i, s.icon or "", s.name or ""))
	end
	local recipe = label(K, info, { Name = "Recipe", Position = UDim2.fromOffset(8, 21), Size = UDim2.new(1, -16, 0, 16), Text = table.concat(parts, " → "), TextColor3 = K.Color.gold, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
	local _ = recipe
	local area = tileArea(api, main, api.landscape, 3)
	area.Size = UDim2.fromScale(1, 1)
	for i, g in view.grid or {} do
		tile(K, area, { name = "Ing" .. i, icon = g.icon, title = g.name, w = 70, order = i, onClick = function(self)
			if done or not api.isCurrent() then
				return
			end
			table.insert(seq, g.id)
			local n = #seq
			local right = steps[n] and steps[n].id == g.id
			self.setState(if right then "done" else "wrong")
			if not right then
				api.shake(5)
			end
			api.J.sfx("pour")
			world(api, "cupLayer", g.id, right)
			task.delay(0.35, function()
				if not done and self.button.Parent then
					self.setState("idle")
				end
			end)
			if n >= #steps then
				done = true
				task.delay(0.4, function()
					api.submit(seq)
				end)
			end
		end })
	end
	world(api, "cupStart", api.p)
	api.setBodyHeight(if api.landscape then TILE + 4 else 40 + GAP + TILE * 2 + GAP + 4)
	return {
		timeout = function()
			return seq
		end,
		destroy = function()
			world(api, "cupStop")
		end,
	}
end

-------------------------------------------------------------------------------------------------
-- 라떼 아트: a ring shrinks onto the cup 3 times; tap the big button when it meets the cup
-------------------------------------------------------------------------------------------------
Games.latte = function(api: any, view: any, _p: any): any
	local K = api.K
	local t0 = os.clock()
	local taps: { number } = {}
	local beats = view.beats or { 1.6, 3.0, 4.4 }
	local ringS = tonumber(view.ring) or 1.2
	local done = false
	local info, main = split(api, 120, 0)
	if not api.landscape then
		info.Visible = false
		main.Position = UDim2.new()
		main.Size = UDim2.fromScale(1, 1)
	end
	label(K, info, { Name = "Art", Size = UDim2.fromScale(1, 1), Text = tostring(view.art or "🌷") .. " 라떼 아트", Font = K.Font.bold, TextSize = K.Type.caption + 1, TextXAlignment = Enum.TextXAlignment.Center })
	local stage = K.frame(main, { Name = "Cup", Size = UDim2.new(0, TILE, 1, 0), ZIndex = 13 })
	local cup = K.frame(stage, { Name = "CupDisc", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(196, 150, 110), ZIndex = 14 })
	K.corner(cup, UDim.new(0.5, 0))
	local ring = K.frame(stage, { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1, ZIndex = 15 })
	K.corner(ring, UDim.new(0.5, 0))
	K.stroke(ring, K.Color.gold, 3, 0)
	local count = K.text(main, { Name = "Count", Position = UDim2.fromOffset(TILE + GAP, 0), Size = UDim2.new(0, 60, 1, 0), Text = "0 / 3", Font = K.Font.heavy, TextSize = K.Type.title2, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 13 })
	local tap = K.Button(main, { name = "Tap", text = "탭!", style = "gold", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, 0, 0.5, 0), size = UDim2.new(0.5, 0, 0, TILE - 4), textSize = K.Type.title2, zIndex = 13 })
	local alive = true
	-- one ring per beat: grows big, then shrinks onto the cup at the beat time (TweenService)
	for _, b in beats do
		task.delay(math.max(0, b - ringS), function()
			if not alive or done then
				return
			end
			ring.Size = UDim2.fromOffset(TILE + 30, TILE + 30)
			pcall(function()
				TweenService:Create(ring, TweenInfo.new(ringS, Enum.EasingStyle.Linear), { Size = UDim2.fromOffset(36, 36) }):Play()
			end)
		end)
	end
	tap.Activated:Connect(function()
		if done or not api.isCurrent() then
			return
		end
		table.insert(taps, os.clock() - t0)
		K.setText(count, string.format("%d / 3", #taps))
		api.J.sfx("pour")
		bump(K, cup, true)
		world(api, "cupLayer", "foam", true)
		if #taps >= #beats then
			done = true
			task.delay(0.3, function()
				api.submit({ taps = taps })
			end)
		end
	end)
	world(api, "cupStart", api.p)
	api.setBodyHeight(TILE + 4)
	return {
		timeout = function()
			return { taps = taps }
		end,
		destroy = function()
			alive = false
			world(api, "cupStop")
		end,
	}
end

-------------------------------------------------------------------------------------------------
-- legacy rounds (not in the current shifts, kept for older shift data): pos (grid order), order
-------------------------------------------------------------------------------------------------
Games.pos = function(api: any, view: any, _p: any): any
	local K = api.K
	if view.mode == "total" then
		local info, main = split(api, 180, 40)
		local list = {}
		for _, it in view.items or {} do
			table.insert(list, string.format("%s%s", it.icon, if (it.qty or 1) > 1 then "x" .. it.qty else ""))
		end
		label(K, info, { Name = "Basket", Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -16, 1, -6), Text = "🧺 " .. table.concat(list, " ") .. " 합계는?", Font = K.Font.bold, TextSize = K.Type.caption + 1, TextWrapped = true })
		local area = tileArea(api, main, api.landscape, 3)
		area.Size = UDim2.fromScale(1, 1)
		local picked = false
		for i, ch in view.choices or {} do
			tile(K, area, { icon = "💰", title = tostring(ch), w = 110, order = i, onClick = function(self)
				if picked then
					return
				end
				picked = true
				self.setState("gold")
				api.submit(i)
			end })
		end
		api.setBodyHeight(if api.landscape then TILE + 4 else 40 + GAP + TILE + 4)
		return { timeout = function()
			return nil
		end }
	end
	local order = {}
	local info, main = split(api, 150, 30)
	local want = {}
	for _, it in view.items or {} do
		table.insert(want, it.icon)
	end
	label(K, info, { Name = "Want", Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -16, 1, -6), Text = "순서: " .. table.concat(want, " "), Font = K.Font.bold, TextSize = K.Type.caption + 1, TextWrapped = true })
	local area = tileArea(api, main, api.landscape, 3)
	area.Size = UDim2.fromScale(1, 1)
	for i, it in view.grid or {} do
		tile(K, area, { icon = it.icon, title = it.name, w = 70, order = i, onClick = function(self)
			table.insert(order, it.id)
			self.setState("done")
			api.J.sfx("beep")
			if #order >= #(view.items or {}) then
				api.submit(order)
			end
		end })
	end
	api.setBodyHeight(if api.landscape then TILE + 4 else 30 + GAP + TILE * 3 + GAP * 2 + 4)
	return { timeout = function()
		return order
	end }
end

Games.order = function(api: any, view: any, _p: any): any
	local K = api.K
	local area = tileArea(api, api.body, api.landscape, 1)
	area.Size = UDim2.fromScale(1, 1)
	local picked = false
	for i, o in view.orders or {} do
		local b = K.Button(area, { name = "Order" .. i, text = string.format("%s %s → %s · %s", tostring(o.icon or "🛵"), tostring(o.dish or ""), tostring(o.drop or ""), K.won(o.pay or 0)), style = "secondary", order = i, size = UDim2.fromOffset(220, TILE - 4), textSize = K.Type.caption, zIndex = 13 })
		b.Activated:Connect(function()
			if picked then
				return
			end
			picked = true
			api.submit(i)
		end)
	end
	api.setBodyHeight(if api.landscape then TILE + 4 else 3 * (TILE + GAP))
	return { timeout = function()
		return 1
	end }
end

return Games
