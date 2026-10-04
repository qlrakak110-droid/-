-- 통장: bank card (통장 잔고 count-up), 현금 / 통장 / 총자산 (집 포함) tiles, 입금 / 출금 buttons (a
-- bottom sheet with a Slider, quick-amount chips and a confirm button -> PhoneAction "bankTransfer"
-- {direction, amount}), this week's income / expense bars per game day, the rent line and the
-- transactions grouped by game day (+ green / − red, 현금 / 통장 account labels, balance after).
-- Built with the GwangalliUI kit. Event driven (ProfileChanged cash / bank / transactions / home).

return function(ctx: any)
	local K, Net, Life, AppKit = ctx.K, ctx.Net, ctx.Life, ctx.AppKit

	local DAY = 1440 -- real seconds per in-game day (GwangalliGameplayShared.DAY_SECONDS)

	local app = {}
	local root: Frame
	local scroll: ScrollingFrame
	local conn: any
	local content: Frame
	local balance: any
	local tiles: { [string]: any } = {}
	local homeRow: Frame
	local homeText: TextLabel
	local chartBars: { any } = {}
	local incomeText: TextLabel
	local expenseText: TextLabel
	local txHolder: Frame
	local sheet: any
	local sheetDir = "deposit"
	local amountText: TextLabel
	local availText: TextLabel
	local slider: any
	local confirmBtn: TextButton
	local chips: { any } = {}
	local visible = false
	local txKey = ""
	local shownOnce = false

	local function gameDay(t: number): number
		return math.floor(t / DAY)
	end

	local function dayTitle(d: number, today: number): string
		if d == today then
			return "오늘"
		elseif d == today - 1 then
			return "어제"
		end
		return string.format("%d일 전", today - d)
	end

	local function timeText(t: number): string
		if t <= 0 then
			return ""
		end
		local ok, s = pcall(function()
			local d = workspace:GetServerTimeNow() - t
			if d < 60 then
				return "방금"
			elseif d < 3600 then
				return string.format("%d분 전", math.floor(d / 60))
			end
			return string.format("%d시간 전", math.floor(d / 3600))
		end)
		return if ok then s else ""
	end

	---------------------------------------------------------------------------------------------------
	-- Transfer sheet
	---------------------------------------------------------------------------------------------------
	local function maxAmount(): number
		local p = Net.profile
		return if sheetDir == "deposit" then Life.cash(p) else Life.bank(p)
	end

	local function updateSheet()
		local v = slider.get()
		amountText.Text = K.won(v)
		confirmBtn.Text = (if sheetDir == "deposit" then "입금하기" else "출금하기") .. (if v > 0 then " · " .. K.won(v) else "")
		K.setButtonEnabled(confirmBtn, v > 0)
	end

	local function openSheet(dir: string)
		sheetDir = dir
		local maxV = maxAmount()
		sheet.setTitle(if dir == "deposit" then "현금 → 통장 입금" else "통장 → 현금 출금", "보낼 수 있는 돈 " .. K.won(maxV))
		availText.Text = if dir == "deposit" then "💵 현금 " .. K.won(Life.cash(Net.profile)) else "🏦 통장 " .. K.won(Life.bank(Net.profile))
		slider.setRange(0, math.max(1000, maxV), if maxV >= 20000 then 1000 else 100)
		slider.set(math.min(maxV, 10000), true)
		local fill = slider.frame:FindFirstChild("Fill", true)
		local g = fill and fill:FindFirstChildOfClass("UIGradient")
		if g then
			local col = if dir == "deposit" then K.Color.cyan else K.Color.gold
			g.Color = ColorSequence.new(K.shade(col, 0, 0.1), col)
		end
		for _, c in chips do
			c.set(false)
		end
		updateSheet()
		sheet.open()
	end

	local function sendTransfer()
		local v = slider.get()
		if v <= 0 then
			return
		end
		local ok, err = Net.send("bankTransfer", { direction = sheetDir, amount = math.floor(v) })
		if ok then
			K.feedback("money")
			sheet.close(true)
		else
			ctx.phone.toast({ app = "bank", title = "통장", body = err or "보낼 수 없어요", kind = "error", silent = true })
		end
	end

	---------------------------------------------------------------------------------------------------
	-- Render
	---------------------------------------------------------------------------------------------------
	local function renderChart(list: { any })
		local today = gameDay(workspace:GetServerTimeNow())
		local inc, exp = {}, {}
		for i = 0, 6 do
			inc[i], exp[i] = 0, 0
		end
		local tIn, tOut = 0, 0
		for _, e in list do
			local d = today - gameDay(tonumber(e.time) or 0)
			local a = tonumber(e.amount) or 0
			local label = tostring(e.title or "")
			-- transfers between my own accounts are not income / expense
			local internal = string.find(label, "입금", 1, true) and string.find(label, "현금", 1, true) or string.find(label, "출금", 1, true) and string.find(label, "통장", 1, true)
			if d >= 0 and d <= 6 and not internal then
				if a > 0 then
					inc[d] += a
					tIn += a
				else
					exp[d] += -a
					tOut += -a
				end
			end
		end
		local maxV = 1
		for i = 0, 6 do
			maxV = math.max(maxV, inc[i], exp[i])
		end
		for i = 0, 6 do
			local bar = chartBars[7 - i]
			if bar then
				bar.inc.Size = UDim2.new(0.42, 0, math.max(0.02, inc[i] / maxV), 0)
				bar.exp.Size = UDim2.new(0.42, 0, math.max(0.02, exp[i] / maxV), 0)
				bar.inc.BackgroundTransparency = if inc[i] > 0 then 0 else 0.7
				bar.exp.BackgroundTransparency = if exp[i] > 0 then 0 else 0.7
				bar.label.Text = if i == 0 then "오늘" else string.format("-%d", i)
				bar.label.TextColor3 = if i == 0 then K.Color.text else K.Color.faint
			end
		end
		incomeText.Text = "수입 +" .. K.won(tIn)
		expenseText.Text = "지출 −" .. K.won(tOut)
	end

	local function renderTx(list: { any })
		local key = tostring(#list) .. ":" .. (list[1] and (tostring(list[1].time) .. tostring(list[1].amount)) or "")
		if key == txKey then
			return
		end
		txKey = key
		AppKit.clear(txHolder)
		if #list == 0 then
			K.EmptyState(txHolder, { order = 1, compact = true, icon = "🧾", title = "아직 거래 내역이 없어요", body = "알바로 첫 급여를 받아 보세요!" })
			return
		end
		local today = gameDay(workspace:GetServerTimeNow())
		local order = 0
		local lastDay: number? = nil
		local card: Frame? = nil
		local rowsIn = 0
		local allRows = {}
		for i, e in list do
			if i > 40 then
				break
			end
			local d = gameDay(tonumber(e.time) or 0)
			if d ~= lastDay then
				lastDay = d
				order += 1
				K.SectionHeader(txHolder, { title = dayTitle(d, today), order = order })
				order += 1
				card = K.Card(txHolder, { Name = "Day_" .. d, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ClipsDescendants = true })
				K.list(card :: Frame, false, 0)
				rowsIn = 0
			end
			rowsIn += 1
			local amt = tonumber(e.amount) or 0
			local acct = if e.account == "cash" then "현금" elseif e.account == "bank" then "통장" else nil
			local sub = timeText(tonumber(e.time) or 0)
			if acct then
				sub = acct .. (if sub ~= "" then " · " .. sub else "")
			end
			if e.balance then
				sub = sub .. " · 잔액 " .. K.wonShort(e.balance)
			end
			local r = K.ListRow(card, {
				name = "Tx" .. i,
				icon = if amt >= 0 then "↓" else "↑",
				iconColor = if amt >= 0 then K.Color.green else K.Color.red,
				round = true,
				title = tostring(e.title or ""),
				subtitle = sub,
				trailing = (if amt >= 0 then "+" else "−") .. K.won(math.abs(amt)),
				trailingColor = if amt >= 0 then K.Color.green else Color3.fromRGB(255, 128, 132),
				trailingWidth = 104,
				grouped = true,
				height = 54,
				order = rowsIn,
			})
			K.mono(r.trailing)
			table.insert(allRows, r.row)
		end
		K.stagger(allRows, K.Color.card)
	end

	local function refresh(animate: boolean)
		if not visible then
			return
		end
		local ready = conn.update()
		content.Visible = ready
		if not ready then
			return
		end
		local p = Net.profile
		balance.set(Life.bank(p), animate)
		tiles.cash.set(Life.cash(p), animate)
		tiles.bank.set(Life.bank(p), animate)
		tiles.total.set(Life.totalAssets(p), animate)
		local h = p.home
		if type(h) == "table" and (h.name or h.listingId) then
			homeRow.Visible = true
			if h.owned then
				homeText.Text = string.format("%s · 자가 · 관리비 자동이체", tostring(h.name or "내 집"))
			else
				local missed = tonumber(h.missed) or 0
				homeText.Text = string.format("%s · 월세 %s/일 · %s", tostring(h.name or "내 집"), K.won(tonumber(h.rentPerDay) or 0), if missed > 0 then string.format("⚠️ 연체 %d일", missed) else "다음 자동이체 " .. K.countdown(tonumber(h.dueIn) or 0) .. " 후")
			end
		else
			homeRow.Visible = false
		end
		local list = Net.transactions or {}
		renderChart(list)
		renderTx(list)
	end

	---------------------------------------------------------------------------------------------------
	-- Build
	---------------------------------------------------------------------------------------------------
	local function tile(parent: Instance, id: string, label: string, color: Color3, order: number)
		local f = K.Card(parent, { Name = "Tile_" .. id, Size = UDim2.new(1 / 3, -6, 1, 0), LayoutOrder = order })
		K.text(f, { Name = "Label", Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 14), Text = label, TextColor3 = K.Color.sub, TextSize = K.Type.micro, Font = K.Font.bold })
		local m = K.MoneyLabel(f, { Name = "Value", Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -16, 0, 20), Text = "0원", Font = K.Font.bold, TextSize = K.Type.caption + 1, TextColor3 = color, TextTruncate = Enum.TextTruncate.AtEnd })
		m.format = K.wonShort
		tiles[id] = m
	end

	function app.build(body: Frame, r: Frame)
		root = r
		local L = ctx.phone.layout()
		ctx.phone.header(body, "통장")
		scroll = AppKit.scroll(body, L.headerH, { name = "Scroll", gap = 10, topPad = 2 })
		conn = AppKit.conn(scroll, ctx, 0)
		content = K.frame(scroll, { Name = "Content", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
		K.list(content, false, 10)

		-- bank card (입금 / 출금 live on the card, so they are always above the fold)
		local card = K.frame(content, { Name = "BankCard", Size = UDim2.new(1, 0, 0, 158), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 1 })
		K.corner(card, K.Radius.lg)
		K.gradient(card, { Color3.fromRGB(96, 84, 250), Color3.fromRGB(58, 70, 220), Color3.fromRGB(24, 28, 80) }, 35)
		K.stroke(card, Color3.new(1, 1, 1), 1, 0.78)
		local stripe = K.frame(card, { Name = "BridgeStripe", Position = UDim2.fromOffset(0, 94), Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 0.35, BackgroundColor3 = Color3.new(1, 1, 1) })
		K.gradient(stripe, K.Grad.bridge, 0)
		K.text(card, { Name = "Bank", Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -70, 0, 16), Text = "BNK 광안리 통장 · 110-***-4567", TextColor3 = Color3.fromRGB(220, 226, 255), TextSize = K.Type.micro, Font = K.Font.bold, TextTruncate = Enum.TextTruncate.AtEnd })
		local chip = K.frame(card, { Name = "Chip", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 12), Size = UDim2.fromOffset(30, 22), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
		K.corner(chip, 5)
		K.gradient(chip, K.Grad.gold, 30)
		K.text(card, { Name = "Caption", Position = UDim2.fromOffset(16, 34), Size = UDim2.new(0.6, 0, 0, 14), Text = "통장 잔고", TextColor3 = Color3.fromRGB(210, 218, 255), TextSize = K.Type.micro })
		K.text(card, { Name = "Holder", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 40), Size = UDim2.new(0.4, 0, 0, 14), Text = string.upper(ctx.player.DisplayName), TextColor3 = Color3.fromRGB(210, 218, 255), TextSize = K.Type.micro, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
		balance = K.MoneyLabel(card, { Name = "Balance", Position = UDim2.fromOffset(16, 50), Size = UDim2.new(1, -32, 0, 32), Text = "0원", Font = K.Font.bold, TextSize = 26 })
		local actions = K.frame(card, { Name = "Actions", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -10), Size = UDim2.new(1, -24, 0, 44) })
		K.list(actions, true, 8)
		K.Button(actions, { name = "Transfer_withdraw", text = "↑ 출금", style = "glass", size = UDim2.new(0.5, -4, 0, 44), order = 1, onClick = function()
			openSheet("withdraw")
		end })
		K.Button(actions, { name = "Transfer_deposit", text = "↓ 입금", style = "primary", size = UDim2.new(0.5, -4, 0, 44), order = 2, onClick = function()
			openSheet("deposit")
		end })

		-- tiles
		local tileRow = K.frame(content, { Name = "Tiles", Size = UDim2.new(1, 0, 0, 54), LayoutOrder = 2 })
		K.list(tileRow, true, 8)
		tile(tileRow, "cash", "💵 현금", K.Color.text, 1)
		tile(tileRow, "bank", "🏦 통장", K.Color.text, 2)
		tile(tileRow, "total", "💎 총자산", K.Color.gold, 3)

		-- rent line
		homeRow = K.Card(content, { Name = "Home", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 4 })
		K.text(homeRow, { Name = "Icon", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 20, 1, 0), Text = "🏠", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center })
		homeText = K.text(homeRow, { Name = "Text", Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -48, 1, 0), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextTruncate = Enum.TextTruncate.AtEnd })

		-- weekly chart
		local chart = K.Card(content, { Name = "Week", Size = UDim2.new(1, 0, 0, 136), LayoutOrder = 5 })
		K.text(chart, { Name = "Title", Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 18), Text = "이번 주 수입 · 지출", Font = K.Font.bold, TextSize = K.Type.bodySm })
		incomeText = K.text(chart, { Name = "Income", Position = UDim2.fromOffset(14, 30), Size = UDim2.new(0.5, -14, 0, 14), Text = "", TextColor3 = K.Color.green, TextSize = K.Type.micro, Font = K.Font.bold })
		expenseText = K.text(chart, { Name = "Expense", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 30), Size = UDim2.new(0.5, -14, 0, 14), Text = "", TextColor3 = Color3.fromRGB(255, 128, 132), TextSize = K.Type.micro, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Right })
		local bars = K.frame(chart, { Name = "Bars", Position = UDim2.fromOffset(14, 50), Size = UDim2.new(1, -28, 0, 64) })
		K.list(bars, true, 0)
		for i = 1, 7 do
			local col = K.frame(bars, { Name = "Day" .. i, Size = UDim2.new(1 / 7, 0, 1, 0), LayoutOrder = i })
			local area = K.frame(col, { Name = "Area", Size = UDim2.new(1, 0, 1, -16) })
			local inc = K.frame(area, { Name = "Income", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -1, 1, 0), Size = UDim2.new(0.42, 0, 0.02, 0), BackgroundTransparency = 0, BackgroundColor3 = K.Color.green })
			K.corner(inc, 3)
			local ex = K.frame(area, { Name = "Expense", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, 1, 1, 0), Size = UDim2.new(0.42, 0, 0.02, 0), BackgroundTransparency = 0, BackgroundColor3 = K.Color.red })
			K.corner(ex, 3)
			local lbl = K.text(col, { Name = "Label", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 13), Text = "", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center })
			chartBars[i] = { inc = inc, exp = ex, label = lbl }
		end
		K.text(chart, { Name = "Note", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -6), Size = UDim2.new(1, -28, 0, 13), Text = "게임 속 하루 단위 · 내 계좌 간 이체 제외", TextColor3 = K.Color.faint, TextSize = K.Type.micro })

		K.SectionHeader(content, { title = "거래 내역", order = 6 })
		txHolder = K.frame(content, { Name = "Transactions", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 7 })
		K.list(txHolder, false, 6)

		-- transfer sheet (inside the app root, over the content)
		sheet = K.BottomSheet(root, { name = "Sheet", title = "입금", height = 0.9, zIndex = 30, shield = body })
		K.list(sheet.content, false, 8, Enum.HorizontalAlignment.Center)
		availText = K.text(sheet.content, { Name = "Avail", Size = UDim2.new(1, 0, 0, 16), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1, ZIndex = 32 })
		amountText = K.text(sheet.content, { Name = "Amount", Size = UDim2.new(1, 0, 0, 34), Text = "0원", Font = K.Font.bold, TextSize = K.Type.display, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, ZIndex = 32 })
		K.mono(amountText)
		slider = K.Slider(sheet.content, { min = 0, max = 10000, value = 0, order = 3, onChange = function()
			updateSheet()
		end })
		slider.frame.Name = "AmountSlider"
		local chipRow = K.frame(sheet.content, { Name = "Quick", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 4, ZIndex = 32 })
		K.list(chipRow, true, 6, Enum.HorizontalAlignment.Center)
		for i, def in { { "1만", 10000 }, { "5만", 50000 }, { "10만", 100000 }, { "전액", -1 } } do
			local chipApi
			chipApi = K.Chip(chipRow, {
				name = "Quick" .. i,
				text = def[1],
				order = i,
				minWidth = 58,
				onClick = function()
					local v = if def[2] < 0 then maxAmount() else math.min(def[2], maxAmount())
					slider.set(v)
					for _, c in chips do
						c.set(c == chipApi)
					end
					updateSheet()
				end,
			})
			table.insert(chips, chipApi)
		end
		confirmBtn = K.Button(sheet.content, { name = "Confirm", text = "입금하기", style = "primary", size = UDim2.new(1, 0, 0, 44), order = 5, onClick = sendTransfer })
		for _, d in sheet.content:GetDescendants() do
			if d:IsA("GuiObject") and d.ZIndex < 32 then
				d.ZIndex = 32
			end
		end

		Net.on("profile", function(changed: any)
			if changed.money or changed.cash or changed.bank or changed.tx or changed.home or changed.transactions then
				refresh(true)
			end
		end)
		Net.on("status", function()
			refresh(false)
		end)
		ctx.phone.onLayout(function()
			local l = ctx.phone.layout()
			scroll.Position = UDim2.fromOffset(0, l.headerH)
			scroll.Size = UDim2.new(1, 0, 1, -l.headerH)
			sheet.relayout()
		end)
	end

	function app.show()
		visible = true
		refresh(not shownOnce)
		shownOnce = true
	end

	function app.hide()
		visible = false
		if sheet and sheet.isOpen() then
			sheet.close(true)
		end
	end

	return app
end
