--!nocheck
-- GwangalliJobs/Shop: (1) the PURCHASE SHEET any player gets from a store / cafe station (drinks
-- fridge, shelf, cafe counter; docs/DESIGN_JOBS.md "냉장고 앞에서 상호작용 -> 새 UI -> 결제"), and (2) the
-- delivery office's DISPATCH CARDS (퀵 / 택배). Both are a right SIDE RAIL on landscape phones and a
-- bottom sheet (<= 38 %) on portrait ones; no dim, the centre of the screen stays clear, the
-- thumbstick keeps working on landscape (the rail sits over the jump / right column only).
-- Server: JobGame {op = "shop" | "bought" | "dispatch"} in, {op = "buy", item, anchor} /
-- {op = "dispatchPick", mode} out. Money is checked and taken on the server.

local Shop = {}

local J: any
local K: any
local gui: ScreenGui
local host: Frame? = nil
local hostKind: string? = nil
local watchConn: RBXScriptConnection? = nil
local anchorPos: Vector3? = nil

local function close()
	if watchConn then
		watchConn:Disconnect()
		watchConn = nil
	end
	local h = host
	host = nil
	hostKind = nil
	if h then
		K.tween(h, 0.16, { BackgroundTransparency = 1 })
		task.delay(0.18, function()
			if h.Parent then
				h:Destroy()
			end
		end)
	end
	J.lockControls(false, "shop")
end
Shop.close = close

-- the container: side rail (landscape) / bottom sheet (portrait)
local function container(kind: string, titleText: string, sub: string, icon: string): (Frame, Frame, any)
	if host then
		host:Destroy()
		host = nil
	end
	local m = J.metrics()
	local h = K.Panel(gui, { Name = "ShopSheet", BackgroundTransparency = 0.04, Radius = K.Radius.lg, ZIndex = 50 })
	h.Active = true
	K.stroke(h, K.Color.cyan, 1.2, 0.55)
	if m.landscape then
		local w = math.min(330, math.floor(m.W * 0.42))
		h.AnchorPoint = Vector2.new(1, 1)
		h.Position = UDim2.new(1, -8, 1, -8)
		h.Size = UDim2.fromOffset(w, math.min(m.H - 86, 300))
	else
		h.AnchorPoint = Vector2.new(0.5, 1)
		h.Position = UDim2.new(0.5, 0, 1, -4)
		h.Size = UDim2.fromOffset(m.W - 12, m.sheetMax)
		-- portrait: the sheet covers the thumbstick zone, so the controls pause while it is open
		J.lockControls(true, "shop")
	end
	K.text(h, { Name = "Icon", Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(30, 30), Text = icon, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 51 })
	K.text(h, { Name = "Title", Position = UDim2.fromOffset(46, 6), Size = UDim2.new(1, -100, 0, 20), Text = titleText, Font = K.Font.heavy, TextSize = K.Type.bodySm + 1, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 51 })
	local subLabel = K.text(h, { Name = "Sub", Position = UDim2.fromOffset(46, 25), Size = UDim2.new(1, -100, 0, 15), Text = sub, TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 51 })
	K.IconButton(h, { name = "Close", icon = "✕", anchor = Vector2.new(1, 0), position = UDim2.new(1, -6, 0, 4), size = UDim2.fromOffset(44, 44), zIndex = 52, onClick = close })
	local list = K.make("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(8, 48),
		Size = UDim2.new(1, -16, 1, -56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.5,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 51,
	}, h)
	if m.landscape then
		K.list(list, false, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	else
		K.make("UIGridLayout", { CellPadding = UDim2.fromOffset(6, 6), CellSize = UDim2.new(0.5, -4, 0, 60), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	end
	host = h
	hostKind = kind
	K.springIn(h, 0.94, { amount = 0.12, duration = 0.28 })
	pcall(K.feedback, "open")
	return h, list, subLabel
end

-- closes the sheet when the player walks away from the station
local function watchDistance(pos: Vector3?, reach: number)
	anchorPos = pos
	if watchConn then
		watchConn:Disconnect()
		watchConn = nil
	end
	if not pos then
		return
	end
	local mine = host
	task.spawn(function()
		while host == mine and host do
			task.wait(0.5)
			local rp = J.rootPos()
			if host == mine and rp and anchorPos and (rp - anchorPos).Magnitude > reach then
				close()
				return
			end
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Purchase sheet
-------------------------------------------------------------------------------------------------
local pending = false

function Shop.shop(p: any)
	local money = string.format("현금 %s · 통장 %s", K.won(tonumber(p.cash) or 0), K.won(tonumber(p.bank) or 0))
	local h, list, subLabel = container("shop", string.format("%s · %s", tostring(p.title or "상품"), tostring(p.place or "")), money, tostring(p.icon or "🛒"))
	local landscape = J.metrics().landscape
	for i, it in p.items or {} do
		local row = K.make("TextButton", { Name = "Item_" .. tostring(it.id), Size = if landscape then UDim2.new(1, 0, 0, 56) else UDim2.new(), BackgroundColor3 = K.Color.card2, BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = i, ZIndex = 52 }, list)
		K.corner(row, K.Radius.sm)
		K.stroke(row, nil, 1, 0.88)
		K.text(row, { Name = "Icon", Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0, 36, 1, 0), Text = tostring(it.icon or "🛒"), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 53 })
		K.text(row, { Name = "Name", Position = UDim2.fromOffset(44, 6), Size = UDim2.new(1, -120, 0, 18), Text = tostring(it.name or ""), Font = K.Font.bold, TextSize = K.Type.caption + 1, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 53 })
		K.text(row, { Name = "Desc", Position = UDim2.fromOffset(44, 26), Size = UDim2.new(1, -120, 0, 24), Text = tostring(it.desc or ""), TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 53 })
		local price = K.text(row, { Name = "Price", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(70, 30), Text = K.won(it.price), Font = K.Font.heavy, TextSize = K.Type.caption + 1, TextColor3 = K.Color.gold, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 53 })
		K.mono(price)
		K.pressable(row, { scale = 0.97 })
		row.Activated:Connect(function()
			if pending then
				return
			end
			pending = true
			K.setText(subLabel, "결제 중…")
			J.send({ op = "buy", item = it.id, anchor = p.anchor })
			task.delay(1.2, function()
				pending = false
			end)
		end)
	end
	local anchor = p.anchor
	watchDistance(if typeof(anchor) == "Instance" and anchor:IsA("BasePart") then anchor.Position else J.rootPos(), 16)
	local _ = h
end

function Shop.bought(p: any)
	pending = false
	J.sfx("coin")
	if host and hostKind == "shop" then
		local sub = host:FindFirstChild("Sub")
		if sub then
			K.setText(sub, string.format("%s %s 구매 완료!%s", tostring(p.icon or ""), tostring(p.name or ""), if p.note and p.note ~= "" then " · " .. tostring(p.note) else ""))
		end
		local row = host:FindFirstChild("List") and host.List:FindFirstChild("Item_" .. tostring(p.item))
		if row then
			K.pop(row, 1.06)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Dispatch cards (광안 딜리버리 배차 테이블)
-------------------------------------------------------------------------------------------------
function Shop.dispatch(p: any)
	local h, list = container("dispatch", "배차 테이블 · 광안 딜리버리", "퀵은 걸어서 번화가, 택배는 탑차로 맵 전체! 신호 위반은 배달비 차감", "🛵")
	local landscape = J.metrics().landscape
	if not landscape then
		local grid = list:FindFirstChildOfClass("UIGridLayout")
		if grid then
			grid.CellSize = UDim2.new(0.5, -4, 1, -4)
		end
	end
	for i, m in p.modes or {} do
		local card = K.frame(list, { Name = "Mode_" .. tostring(m.mode), Size = if landscape then UDim2.new(1, 0, 0, 112) else UDim2.new(), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card2, LayoutOrder = i, ZIndex = 52 })
		K.corner(card, K.Radius.md)
		K.stroke(card, if m.current then K.Color.gold else nil, 1.2, if m.current then 0.2 else 0.85)
		K.text(card, { Name = "Title", Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 20), Text = string.format("%s %s%s", tostring(m.icon or ""), tostring(m.title or ""), if m.current then " · 지금 직업" else ""), Font = K.Font.heavy, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 53 })
		K.text(card, { Name = "Pay", Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 0, 16), Text = string.format("%s · %s · %d건/근무", tostring(m.payRange or ""), tostring(m.level or ""), tonumber(m.drops) or 4), TextColor3 = K.Color.gold, Font = K.Font.bold, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 53 })
		K.text(card, { Name = "Desc", Position = UDim2.fromOffset(10, 43), Size = UDim2.new(1, -20, 0, if landscape then 22 else 40), Text = tostring(m.desc or ""), TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 53 })
		K.Button(card, { name = "Go", text = if m.drive then "🚚 탑차 받고 출근" else "🛵 퀵 출근", style = if m.drive then "gold" else "primary", anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, -6), size = UDim2.new(1, -16, 0, 44), textSize = K.Type.caption + 1, zIndex = 54, onClick = function()
			J.send({ op = "dispatchPick", mode = m.mode })
			close()
		end })
	end
	watchDistance(J.rootPos(), 18)
	local _ = h
end

function Shop.init(ctx: any)
	J = ctx
	K = ctx.K
	gui = ctx.gui
end

return Shop
