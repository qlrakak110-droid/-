-- GwangalliCarDealer/Catalog (client): the full-screen 차량 카탈로그 — a brand-configurator style showroom of
-- every car by type: header (통장 / 현금, 내 차고 n/3), category tabs (전체 · 이달의 특가 · 경차 · 세단 · SUV ·
-- 승합·밴 · 트럭 · 프리미엄 · 스포츠 · 전기·하이브리드 · 중고차 · 렌트: only the ones with cars), search, sort,
-- 라인업 / 브랜드 filter, quick filters (살 수 있는 차 · 할부 가능 · 찜), a card grid with lazy 3D thumbnails
-- (budget: C.PREVIEW.thumbs*), a 특가 banner, a compare tray, and the detail page (docked right on wide
-- screens, full overlay on phones).
--   CatalogUI.open(opts?)   opts = { cat, entry, pick, npc, trade }     CatalogUI.close()   CatalogUI.isOpen()
--   CatalogUI.toggleCompare(id)   CatalogUI.inCompare(id)   CatalogUI.ctxNpc()   CatalogUI.tradeMode()
-- Gamepad: LB / RB category, B back; keyboard: Backspace back (not while typing).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local CatalogUI = {}

local player = Players.LocalPlayer
local ctx: any
local Ui: any
local C: any
local U: any
local Cat: any
local Col: any

local gui: ScreenGui
local root: Frame
local content: Frame
local header: Frame
local titleSub: TextLabel
local moneyRow: Frame
local bankChip: any
local cashChip: any
local garageChip: any
local tabsScroll: ScrollingFrame
local toolbar: Frame
local searchBox: TextBox
local sortBtn: any
local brandBtn: any
local filterBtn: any
local quick: { [string]: any } = {}
local notice: Frame
local noticeText: TextLabel
local noticeBtn: any
local body: Frame
local gridScroll: ScrollingFrame
local gridHolder: Frame
local gridLayout: UIGridLayout
local banner: TextButton?
local emptyState: Frame
local detailHost: Frame
local compareTray: Frame
local compareText: TextLabel
local compareBtn: any

local isOpen = false
local state = {
	cat = "all",
	brand = nil :: string?,
	sort = "rec",
	query = "",
	affordableOnly = false,
	loanOnly = false,
	wishOnly = false,
	pick = nil :: string?,
	npc = nil :: any,
	trade = false,
	compare = {} :: { string },
}
local cards: { { e: any, inst: GuiObject, thumbHost: Frame, thumb: any, index: number } } = {}
local tabChips: { [string]: any } = {}
local cellW, cellH, cols = 240, 250, 3
local renderToken = 0
local mode = "dock"

local function money(): (number, number)
	return ctx.Net.money()
end

local function catLabel(id: string): string
	local c = Cat.CAT_BY_ID[id]
	return c and c.label or id
end

-------------------------------------------------------------------------------------------------
-- cards
-------------------------------------------------------------------------------------------------
local function destroyThumbs()
	for _, c in cards do
		if c.thumb then
			c.thumb.destroy()
			c.thumb = nil
		end
	end
end

local function clearCards()
	destroyThumbs()
	for _, c in cards do
		c.inst:Destroy()
	end
	cards = {}
end

local function benefitRate(e: any): number
	local b = Cat.benefits(e, { usedRate = ctx.Net.usedRate(), special = e.special })
	return b.rate
end

local function badgeRow(parent: Instance, e: any, z: number): Frame
	local row = Ui.frame(parent, { Name = "Badges", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -56, 0, 20), ZIndex = z })
	Ui.list(row, "x", 4)
	local n = 0
	local function add(text: string, tone: Color3)
		n += 1
		Ui.badge(row, text, tone, { order = n, z = z })
	end
	if e.isNew then
		add("NEW", Col.pink)
	end
	if e.special then
		add("🔥 특가", Col.gold)
	end
	add(Cat.gradeLabel(e), if e.grade == "used" then Col.orange elseif e.grade == "rent" then Col.green else Col.accent)
	if e.owned then
		add("보유 중", Col.green)
	end
	if e.tested then
		add("시승 완료", Color3.fromRGB(110, 120, 150))
	end
	if e.lock then
		add("🔒 Lv." .. tostring(e.lock.level), Col.red)
	end
	if not e.available then
		add("동급 출고", Color3.fromRGB(110, 120, 150))
	end
	return row
end

local function makeCard(e: any, index: number): any
	local z = 3
	local b = Ui.make("TextButton", {
		Name = "Card_" .. e.id,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Col.card,
		BackgroundTransparency = 0.02,
		LayoutOrder = index,
		Selectable = true,
		ZIndex = z,
		ClipsDescendants = true,
	}, gridHolder)
	Ui.corner(b, 16)
	local stroke = Ui.stroke(b, if state.pick == e.id then Col.gold else Col.line, if state.pick == e.id then 2 else 1, if state.pick == e.id then 0 else 0.88)
	local thumbH = math.floor(cellW * 0.5)
	local thumbHost = Ui.frame(b, { Name = "Thumb", Size = UDim2.new(1, 0, 0, thumbH), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(30, 35, 50), ZIndex = z })
	Ui.grad(thumbHost, Color3.fromRGB(58, 66, 92), Color3.fromRGB(18, 21, 30), 90)
	Ui.label(thumbHost, { Name = "Glyph", Text = e.glyph or "🚗", TextSize = math.floor(thumbH * 0.42), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.1, ZIndex = z })
	badgeRow(b, e, z + 3)
	-- 찜
	local wished = ctx.Net.state.wish[e.id] == true
	local heart = Ui.make("TextButton", { Name = "Wish", Text = if wished then "❤" else "♡", Font = Ui.F.bold, TextSize = 18, TextColor3 = if wished then Col.pink else Col.ink, BackgroundColor3 = Col.bg, BackgroundTransparency = 0.35, Size = UDim2.fromOffset(34, 34), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), ZIndex = z + 4, AutoButtonColor = false, Selectable = false }, b)
	Ui.corner(heart, 17)
	heart.Activated:Connect(function()
		CatalogUI.toggleWish(e.id)
	end)
	-- text block
	local y = thumbH + 10
	Ui.label(b, { Name = "Name", Text = e.name, Font = Ui.F.bold, TextSize = 16, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = z + 1 })
	Ui.label(b, { Name = "Sub", Text = Cat.subline(e), Font = Ui.F.med, TextSize = 12, TextColor3 = Col.sub, Position = UDim2.fromOffset(12, y + 21), Size = UDim2.new(1, -24, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = z + 1 })
	local num, unit = U.manShort(e.price)
	local priceLbl = Ui.label(b, { Name = "Price", Text = num, Font = Ui.F.black, TextSize = 24, Position = UDim2.fromOffset(12, y + 42), Size = UDim2.fromOffset(Ui.textWidth(num, 24, Ui.F.black) + 2, 28), ZIndex = z + 1 })
	Ui.label(b, { Name = "Unit", Text = unit .. (if e.grade == "rent" then " / 하루" else ""), Font = Ui.F.bold, TextSize = 13, TextColor3 = Col.sub, Position = UDim2.fromOffset(14 + priceLbl.Size.X.Offset, y + 50), Size = UDim2.fromOffset(80, 18), ZIndex = z + 1 })
	local rate = benefitRate(e)
	if rate > 0 then
		Ui.label(b, { Name = "Benefit", Text = "출고 후 " .. U.pct(rate) .. " 환급", Font = Ui.F.bold, TextSize = 12, TextColor3 = Col.gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, y + 52), Size = UDim2.fromOffset(120, 16), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = z + 1 })
	end
	local fine = ""
	if e.grade == "rent" then
		fine = string.format("게임 시간 하루 (%d분) · 차고 대수 제외", math.floor((e.rentSeconds or 2400) / 60))
	elseif e.canLoan and e.loan then
		fine = string.format("할부 계약금 %s · 하루 %s × %d일", U.man(e.loan.down), U.man(e.loan.daily), e.loan.days)
	else
		fine = "일시불 · 할부는 30만원 이상 차량"
	end
	Ui.label(b, { Name = "Fine", Text = fine, Font = Ui.F.med, TextSize = 11, TextColor3 = Col.faint, Position = UDim2.fromOffset(12, y + 74), Size = UDim2.new(1, -24, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = z + 1 })
	local bank, cash = money()
	local how = Cat.affordable(e, bank, cash)
	local tagText = e.tag or (if state.pick == e.id then "상담원 추천" else nil)
	local tagY = y + 94
	if tagText then
		Ui.badge(b, "✨ " .. tagText, Color3.fromRGB(70, 60, 120), { z = z + 1 }).Position = UDim2.fromOffset(12, tagY)
	end
	local status = Ui.label(b, { Name = "Status", Font = Ui.F.bold, TextSize = 11, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, tagY + 2), Size = UDim2.fromOffset(110, 16), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = z + 1 })
	if e.grade ~= "rent" then
		if how == "full" then
			status.Text = "● 바로 출고 가능"
			status.TextColor3 = Col.green
		elseif how == "loan" then
			status.Text = "● 할부로 가능"
			status.TextColor3 = Col.accent
		else
			status.Text = "● 잔액 부족"
			status.TextColor3 = Col.faint
		end
	end
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = Col.cardHi
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = Col.card
	end)
	b.SelectionGained:Connect(function()
		stroke.Color = Col.accent
		stroke.Transparency = 0
		stroke.Thickness = 2
		-- keep the selected card in view (gamepad)
		local top = b.AbsolutePosition.Y - gridScroll.AbsolutePosition.Y
		if top < 0 or top + b.AbsoluteSize.Y > gridScroll.AbsoluteSize.Y then
			gridScroll.CanvasPosition = Vector2.new(0, math.max(0, gridScroll.CanvasPosition.Y + top - 12))
		end
	end)
	b.SelectionLost:Connect(function()
		stroke.Color = if state.pick == e.id then Col.gold else Col.line
		stroke.Transparency = if state.pick == e.id then 0 else 0.88
		stroke.Thickness = if state.pick == e.id then 2 else 1
	end)
	b.Activated:Connect(function()
		Ui.sfx("tap")
		CatalogUI.openDetail(e.id)
	end)
	return { e = e, inst = b, thumbHost = thumbHost, thumb = nil, index = index }
end

-- Lazy 3D thumbnails: only cards in (or one row around) the view, within the live budget.
local thumbQueued = false
local function updateThumbs()
	if thumbQueued then
		return
	end
	thumbQueued = true
	task.delay(0.12, function()
		thumbQueued = false
		if not isOpen or not ctx.Viewport.supported() then
			return
		end
		local m = Ui.metrics()
		local budget = if m.phone then C.PREVIEW.thumbsPhone else C.PREVIEW.thumbsDesktop
		local viewTop = gridScroll.AbsolutePosition.Y
		local viewBottom = viewTop + gridScroll.AbsoluteSize.Y
		local margin = cellH * 0.6
		local want = {}
		for _, c in cards do
			local y0 = c.inst.AbsolutePosition.Y
			local y1 = y0 + c.inst.AbsoluteSize.Y
			if y1 >= viewTop - margin and y0 <= viewBottom + margin then
				table.insert(want, c)
			elseif c.thumb then
				c.thumb.destroy()
				c.thumb = nil
			end
		end
		local live = 0
		for _, c in cards do
			if c.thumb then
				live += 1
			end
		end
		for _, c in want do
			if not c.thumb and live < budget then
				local e = c.e
				local GS = ctx.GS
				local colorId = (GS and GS.DEFAULT_COLOR) or "white"
				c.thumb = ctx.Viewport.thumb(c.thumbHost, e.preview, colorId, e.grade == "used")
				live += 1
			end
		end
	end)
end

local function sizeGrid()
	local m = Ui.metrics()
	local W = gridScroll.AbsoluteSize.X - 16
	if W <= 0 then
		return
	end
	local minW = if m.compact then 210 else 248
	local gap = if m.compact then 10 else 14
	cols = math.max(1, math.floor((W + gap) / (minW + gap)))
	cellW = math.floor((W - (cols - 1) * gap) / cols)
	cellH = math.floor(cellW * 0.5) + 124
	gridLayout.CellPadding = UDim2.fromOffset(gap, gap)
	gridLayout.CellSize = UDim2.fromOffset(cellW, cellH)
	gridHolder.Size = UDim2.new(1, -16, 0, 0)
end

local function filtered(): { any }
	local st = ctx.Net.state
	local bank, cash = money()
	local list = Cat.filter(st.entries, {
		cat = state.cat,
		brand = state.brand,
		query = state.query,
		money = { bank = bank, cash = cash },
		affordableOnly = state.affordableOnly,
		loanOnly = state.loanOnly,
		wishOnly = state.wishOnly,
		wish = st.wish,
	})
	return Cat.sort(list, state.sort, { bank = bank, cash = cash })
end

local function renderBanner()
	if banner then
		banner:Destroy()
		banner = nil
	end
	local st = ctx.Net.state
	local m = Ui.metrics()
	if state.cat ~= "all" or state.query ~= "" or m.compact then
		return
	end
	local names = {}
	for _, e in st.entries do
		if e.special then
			table.insert(names, e.name .. " " .. Cat.gradeLabel(e))
		end
	end
	if #names == 0 then
		return
	end
	local snap = st.snap or {}
	local month = tonumber(string.match(snap.month or "", "%-(%d+)$")) or 1
	local b = Ui.make("TextButton", { Name = "Banner", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(60, 44, 16), Size = UDim2.new(1, -16, 0, 74), LayoutOrder = 0, Selectable = true, ZIndex = 3 }, gridScroll)
	Ui.corner(b, 16)
	Ui.grad(b, Color3.fromRGB(255, 214, 120), Color3.fromRGB(150, 96, 30), 0)
	Ui.stroke(b, Col.gold, 1, 0.3)
	Ui.label(b, { Text = string.format("🔥 %d월 이달의 특가", month), Font = Ui.F.black, TextSize = 18, TextColor3 = Color3.fromRGB(34, 22, 4), Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -200, 0, 24), ZIndex = 4 })
	Ui.label(b, { Text = table.concat(names, " · ") .. string.format(" · 출고 즉시 차값의 %s 통장 환급", U.pct(C.SPECIALS.rate)), Font = Ui.F.bold, TextSize = 13, TextColor3 = Color3.fromRGB(60, 40, 10), Position = UDim2.fromOffset(18, 40), Size = UDim2.new(1, -200, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
	Ui.label(b, { Text = string.format("D-%d  ▶ 특가 보기", math.max(0, (snap.daysLeft or 1) - 1)), Font = Ui.F.black, TextSize = 15, TextColor3 = Color3.fromRGB(34, 22, 4), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -18, 0.5, 0), Size = UDim2.fromOffset(170, 24), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
	b.Activated:Connect(function()
		CatalogUI.setCat("special")
	end)
	banner = b
end

local function renderTabs()
	for _, c in tabChips do
		c.inst:Destroy()
	end
	tabChips = {}
	local st = ctx.Net.state
	local cats = Cat.catsIn(st.entries)
	local counts: { [string]: number } = {}
	for _, e in st.entries do
		for _, c in e.cats do
			counts[c] = (counts[c] or 0) + 1
		end
	end
	local m = Ui.metrics()
	for i, c in cats do
		local chip = Ui.chip(tabsScroll, {
			name = "Tab_" .. c.id,
			text = string.format("%s %s  %d", c.icon, c.label, counts[c.id] or 0),
			order = i,
			height = if m.compact then 34 else 38,
			textSize = if m.compact then 13 else 14,
			tone = if c.id == "special" then Col.gold else Col.accent,
			on = state.cat == c.id,
			onClick = function()
				CatalogUI.setCat(c.id)
			end,
		})
		tabChips[c.id] = chip
	end
	if not Cat.CAT_BY_ID[state.cat] or not tabChips[state.cat] then
		state.cat = "all"
		if tabChips.all then
			tabChips.all.set(true)
		end
	end
end

local function renderEmpty(show: boolean)
	emptyState.Visible = show
end

local function render()
	if not isOpen then
		return
	end
	renderToken += 1
	clearCards()
	sizeGrid()
	renderBanner()
	local list = filtered()
	for i, e in list do
		table.insert(cards, makeCard(e, i))
	end
	renderEmpty(#list == 0)
	local st = ctx.Net.state
	titleSub.Text = string.format("차량 카탈로그 · %s %d대", catLabel(state.cat), #list)
	local snap = st.snap or {}
	garageChip.setText(string.format("🅿 내 차고 %d/%d", snap.owned or 0, snap.max or 3))
	updateThumbs()
end

-------------------------------------------------------------------------------------------------
-- header / toolbar / notice
-------------------------------------------------------------------------------------------------
local function updateMoney()
	if not bankChip then
		return
	end
	local bank, cash = money()
	local m = Ui.metrics()
	if m.compact then
		bankChip.setText("💳 " .. U.man(bank))
		cashChip.setText("💵 " .. U.man(cash))
	else
		bankChip.setText("💳 통장 " .. U.won(bank))
		cashChip.setText("💵 현금 " .. U.won(cash))
	end
end

local function updateNotice()
	local st = ctx.Net.state
	local snap = st.snap or {}
	local text, btn = nil, nil
	if snap.garageReady == false then
		text = "🛠 정비소 전산 점검 중이에요 · 차량은 구경만 할 수 있어요"
	elseif snap.near == false then
		text = "📍 매장 밖에서 둘러보는 중이에요 · 시승과 계약은 광안 오토 상담원과 할 수 있어요"
		btn = "🧭 길 안내"
	elseif state.trade then
		text = "🔁 보상판매 상담 중 · 계약할 때 타던 차를 넘기면 매입가 + " .. U.pct((snap.tradeBonus or 0)) .. " 추가 정산금"
	elseif (snap.owned or 0) >= (snap.max or 3) then
		text = string.format("🅿 차고가 가득 찼어요 (%d/%d) · 계약할 때 보상판매로 바꿀 수 있어요", snap.owned or 0, snap.max or 3)
	end
	notice.Visible = text ~= nil
	if text then
		noticeText.Text = text
		noticeBtn.inst.Visible = btn ~= nil
		if btn then
			noticeBtn.setText(btn)
		end
	end
end

local function sortLabel(): string
	for _, s in Cat.SORTS do
		if s.id == state.sort then
			return s.label
		end
	end
	return "추천순"
end

local function brandTitle(): string
	local GS = ctx.GS
	return if GS and GS.SHOW_REAL_NAMES == true then "브랜드" else "라인업"
end

local function updateToolbar()
	sortBtn.setText("↕ " .. sortLabel() .. " ▾")
	local brands = Cat.brandsIn(ctx.Net.state.entries)
	brandBtn.inst.Visible = #brands >= 2 and not Ui.metrics().compact
	brandBtn.setText(brandTitle() .. " · " .. (state.brand or "전체") .. " ▾")
	local n = (if state.affordableOnly then 1 else 0) + (if state.loanOnly then 1 else 0) + (if state.wishOnly then 1 else 0) + (if state.brand then 1 else 0)
	filterBtn.setText("⚙ 필터" .. (if n > 0 then " " .. n else "") .. " ▾")
	for k, chip in quick do
		chip.set(state[k] == true)
	end
end

local function layout()
	if not root then
		return
	end
	local m = Ui.metrics()
	local top = m.inset + (if m.compact then 6 else 10)
	local side = if m.compact then 12 else 22
	content.Position = UDim2.fromOffset(side, top)
	content.Size = UDim2.new(1, -side * 2, 1, -top - (if m.compact then 6 else 14))
	local hh = if m.compact then 44 else 56
	header.Size = UDim2.new(1, 0, 0, hh)
	local th = if m.compact then 38 else 44
	tabsScroll.Position = UDim2.fromOffset(0, hh + 4)
	tabsScroll.Size = UDim2.new(1, 0, 0, th)
	local tb = if m.compact then 40 else 44
	toolbar.Position = UDim2.fromOffset(0, hh + 4 + th + 4)
	toolbar.Size = UDim2.new(1, 0, 0, tb)
	local y = hh + 4 + th + 4 + tb + 6
	if notice.Visible then
		notice.Position = UDim2.fromOffset(0, y)
		notice.Size = UDim2.new(1, 0, 0, 34)
		y += 40
	end
	body.Position = UDim2.fromOffset(0, y)
	body.Size = UDim2.new(1, 0, 1, -y)
	-- search box width
	local search = toolbar:FindFirstChild("Search") :: Frame
	search.Size = UDim2.fromOffset(if m.compact then math.max(140, m.w * 0.28) else 260, tb)
	for _, chip in quick do
		chip.inst.Visible = not m.compact and m.w >= 1180
	end
	filterBtn.inst.Visible = m.compact or m.w < 1180
	-- detail placement
	local detailOpen = ctx.Detail.isOpen()
	mode = if m.w >= 1000 and not m.portrait then "dock" else "overlay"
	if detailOpen and mode == "dock" then
		local dw = math.clamp(math.floor(m.w * 0.4), 420, 620)
		gridScroll.Size = UDim2.new(1, -dw - 14, 1, 0)
		detailHost.Position = UDim2.new(1, -dw, 0, 0)
		detailHost.Size = UDim2.new(0, dw, 1, 0)
		detailHost.Parent = body
	elseif detailOpen then
		gridScroll.Size = UDim2.fromScale(1, 1)
		detailHost.Position = UDim2.fromOffset(0, 0)
		detailHost.Size = UDim2.fromScale(1, 1)
		detailHost.Parent = content
	else
		gridScroll.Size = UDim2.fromScale(1, 1)
	end
	gridScroll.Visible = not (detailOpen and mode == "overlay")
	tabsScroll.Visible = not (detailOpen and mode == "overlay")
	toolbar.Visible = not (detailOpen and mode == "overlay")
	if detailOpen and mode == "overlay" then
		notice.Visible = false
	end
	detailHost.Visible = detailOpen
	if not (detailOpen and mode == "overlay") then
		updateNotice()
	end
	compareTray.Position = UDim2.new(0.5, 0, 1, -(if m.compact then 8 else 16))
	updateMoney()
	ctx.Detail.layout()
	task.defer(function()
		local oldCols = cols
		sizeGrid()
		if oldCols ~= cols or (#cards > 0 and cards[1].thumbHost.Size.Y.Offset ~= math.floor(cellW * 0.5)) then
			render()
		else
			updateThumbs()
		end
	end)
end

local function updateCompareTray()
	local n = #state.compare
	compareTray.Visible = n > 0 and isOpen
	if n == 0 then
		return
	end
	local names = {}
	for _, id in state.compare do
		local e = ctx.Net.state.byId[id]
		table.insert(names, e and e.short or id)
	end
	compareText.Text = string.format("⇄ 비교함 %d/2 · %s", n, table.concat(names, " vs "))
	compareBtn.setEnabled(n == 2)
end

local function build()
	gui = Ui.screen("GwangalliCarDealerUI", C.UI.order.catalog)
	root = Ui.frame(gui, { Name = "Root", BackgroundTransparency = 0.02, BackgroundColor3 = Col.bg })
	Ui.grad(root, Color3.fromRGB(24, 28, 42), Color3.fromRGB(6, 7, 11), 90)
	content = Ui.frame(root, { Name = "Content" })

	-- header
	header = Ui.frame(content, { Name = "Header" })
	local logo = Ui.frame(header, { Name = "Logo", Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), BackgroundTransparency = 0, BackgroundColor3 = Col.accent })
	Ui.corner(logo, 12)
	Ui.grad(logo, Color3.fromRGB(120, 170, 255), Color3.fromRGB(40, 90, 220), 45)
	Ui.label(logo, { Text = "GW", Font = Ui.F.black, TextSize = 16, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	Ui.label(header, { Name = "Title", Text = "광안 오토", Font = Ui.F.black, TextSize = 20, Position = UDim2.new(0, 52, 0.5, -20), Size = UDim2.fromOffset(240, 22) })
	titleSub = Ui.label(header, { Name = "Sub", Text = "차량 카탈로그", Font = Ui.F.med, TextSize = 12, TextColor3 = Col.sub, Position = UDim2.new(0, 52, 0.5, 3), Size = UDim2.fromOffset(300, 16) })
	moneyRow = Ui.frame(header, { Name = "Right", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.7, 0, 0, 40) })
	Ui.list(moneyRow, "x", 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	bankChip = Ui.chip(moneyRow, { name = "Bank", text = "💳 통장", order = 1, height = 34, textSize = 13 })
	cashChip = Ui.chip(moneyRow, { name = "Cash", text = "💵 현금", order = 2, height = 34, textSize = 13 })
	garageChip = Ui.chip(moneyRow, {
		name = "Garage",
		text = "🅿 내 차고 0/3",
		order = 3,
		height = 34,
		textSize = 13,
		onClick = function()
			CatalogUI.close()
			local ev = player:FindFirstChild(ctx.S.NAMES.Garage.Open)
			if ev and ev:IsA("BindableEvent") then
				ev:Fire({ tab = "mine" })
			end
		end,
	})
	local close = Ui.button(moneyRow, { name = "Close", text = "✕", style = "secondary", size = UDim2.fromOffset(40, 40), order = 4, radius = 20, textSize = 16 })
	close.onClick(function()
		if ctx.Detail.isOpen() then
			CatalogUI.closeDetail()
		else
			CatalogUI.close()
		end
	end)

	-- tabs
	tabsScroll = Ui.scroll(content, { Name = "Tabs", ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 0 })
	Ui.list(tabsScroll, "x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

	-- toolbar
	toolbar = Ui.frame(content, { Name = "Toolbar" })
	Ui.list(toolbar, "x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local search = Ui.frame(toolbar, { Name = "Search", BackgroundTransparency = 0, BackgroundColor3 = Col.glass2, LayoutOrder = 1 })
	Ui.corner(search, 12)
	Ui.stroke(search, Col.line, 1, 0.86)
	Ui.label(search, { Text = "🔍", TextSize = 14, Size = UDim2.fromOffset(32, 44), Position = UDim2.fromOffset(6, 0), TextXAlignment = Enum.TextXAlignment.Center })
	searchBox = Ui.make("TextBox", {
		Name = "Box",
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "차 이름 · 차종 검색",
		PlaceholderColor3 = Col.faint,
		TextColor3 = Col.ink,
		Font = Ui.F.med,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -46, 1, 0),
	}, search)
	local typingToken = 0
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		typingToken += 1
		local my = typingToken
		task.delay(0.25, function()
			if my == typingToken and isOpen then
				state.query = string.sub(searchBox.Text, 1, 40)
				render()
			end
		end)
	end)
	sortBtn = Ui.button(toolbar, { name = "Sort", text = "↕ 추천순 ▾", style = "secondary", size = UDim2.fromOffset(140, 40), order = 2, textSize = 13 })
	sortBtn.onClick(function()
		local items = {}
		for _, s in Cat.SORTS do
			table.insert(items, { id = s.id, label = s.label, on = state.sort == s.id })
		end
		Ui.menu(sortBtn.inst, items, function(it)
			state.sort = it.id
			updateToolbar()
			render()
		end)
	end)
	brandBtn = Ui.button(toolbar, { name = "Brand", text = "라인업 · 전체 ▾", style = "secondary", size = UDim2.fromOffset(170, 40), order = 3, textSize = 13 })
	brandBtn.onClick(function()
		local items = { { id = "", label = "전체", on = state.brand == nil } }
		for _, b in Cat.brandsIn(ctx.Net.state.entries) do
			table.insert(items, { id = b, label = b, on = state.brand == b })
		end
		Ui.menu(brandBtn.inst, items, function(it)
			state.brand = if it.id == "" then nil else it.id
			updateToolbar()
			render()
		end)
	end)
	local function quickChip(key: string, text: string, order: number)
		quick[key] = Ui.chip(toolbar, {
			name = "Q_" .. key,
			text = text,
			order = order,
			height = 36,
			textSize = 13,
			onClick = function()
				state[key] = not state[key]
				updateToolbar()
				render()
			end,
		})
	end
	quickChip("affordableOnly", "💳 살 수 있는 차", 4)
	quickChip("loanOnly", "📅 할부 가능", 5)
	quickChip("wishOnly", "❤ 찜한 차", 6)
	filterBtn = Ui.button(toolbar, { name = "Filter", text = "⚙ 필터 ▾", style = "secondary", size = UDim2.fromOffset(110, 40), order = 7, textSize = 13 })
	filterBtn.onClick(function()
		local items = {
			{ id = "affordableOnly", label = "💳 살 수 있는 차만", on = state.affordableOnly },
			{ id = "loanOnly", label = "📅 할부 가능", on = state.loanOnly },
			{ id = "wishOnly", label = "❤ 찜한 차", on = state.wishOnly },
		}
		local brands = Cat.brandsIn(ctx.Net.state.entries)
		if #brands >= 2 then
			table.insert(items, { id = "brand:", label = brandTitle() .. " · 전체", on = state.brand == nil })
			for _, b in brands do
				table.insert(items, { id = "brand:" .. b, label = brandTitle() .. " · " .. b, on = state.brand == b })
			end
		end
		table.insert(items, { id = "reset", label = "↺ 필터 초기화" })
		Ui.menu(filterBtn.inst, items, function(it)
			if it.id == "reset" then
				state.affordableOnly, state.loanOnly, state.wishOnly, state.brand = false, false, false, nil
			elseif string.sub(it.id, 1, 6) == "brand:" then
				local b = string.sub(it.id, 7)
				state.brand = if b == "" then nil else b
			else
				state[it.id] = not state[it.id]
			end
			updateToolbar()
			render()
		end)
	end)

	-- notice bar
	notice = Ui.glass(content, { Name = "Notice", BackgroundColor3 = Col.accentSoft, Visible = false })
	noticeText = Ui.label(notice, { Font = Ui.F.bold, TextSize = 12, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -150, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	noticeBtn = Ui.button(notice, { name = "Go", text = "🧭 길 안내", style = "primary", size = UDim2.fromOffset(110, 28), anchor = Vector2.new(1, 0.5), pos = UDim2.new(1, -4, 0.5, 0), textSize = 12, radius = 10 })
	noticeBtn.onClick(function()
		local r = ctx.Net.call("waypoint", nil)
		if not r.ok and r.message and r.message ~= "" then
			Ui.toast({ kind = "info", icon = "🧭", title = "길 안내", body = r.message })
		end
	end)

	-- body
	body = Ui.frame(content, { Name = "Body" })
	gridScroll = Ui.scroll(body, { Name = "Grid" })
	Ui.list(gridScroll, "y", 14)
	Ui.pad(gridScroll, 0, 6, 2, 90)
	gridHolder = Ui.frame(gridScroll, { Name = "Cards", AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -16, 0, 0), LayoutOrder = 1 })
	gridLayout = Ui.make("UIGridLayout", { SortOrder = Enum.SortOrder.LayoutOrder, CellPadding = UDim2.fromOffset(14, 14), CellSize = UDim2.fromOffset(240, 250) }, gridHolder)
	gridScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(updateThumbs)
	gridScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if not isOpen then
			return
		end
		local oldCols, oldW = cols, cellW
		sizeGrid()
		if oldCols ~= cols or math.abs(oldW - cellW) > 6 then
			render()
		end
	end)
	emptyState = Ui.frame(gridScroll, { Name = "Empty", Size = UDim2.new(1, -16, 0, 180), LayoutOrder = 2, Visible = false })
	Ui.label(emptyState, { Text = "🔎", TextSize = 40, Size = UDim2.new(1, 0, 0, 56), TextXAlignment = Enum.TextXAlignment.Center })
	Ui.label(emptyState, { Text = "조건에 맞는 차가 없어요", Font = Ui.F.bold, TextSize = 17, Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center })
	local reset = Ui.button(emptyState, { text = "↺ 필터 초기화", style = "primary", size = UDim2.fromOffset(160, 42), anchor = Vector2.new(0.5, 0), pos = UDim2.new(0.5, 0, 0, 100) })
	reset.onClick(function()
		state.affordableOnly, state.loanOnly, state.wishOnly, state.brand, state.query = false, false, false, nil, ""
		searchBox.Text = ""
		CatalogUI.setCat("all")
	end)
	detailHost = Ui.frame(body, { Name = "DetailHost", Visible = false, ZIndex = 10 })
	ctx.Detail.mount(detailHost)

	-- compare tray
	compareTray = Ui.glass(root, { Name = "Compare", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(520, 56), BackgroundColor3 = Col.glass2, Visible = false, ZIndex = 20 })
	compareText = Ui.label(compareTray, { Font = Ui.F.bold, TextSize = 13, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -250, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 21 })
	compareBtn = Ui.button(compareTray, { text = "비교하기", style = "primary", size = UDim2.fromOffset(110, 40), anchor = Vector2.new(1, 0.5), pos = UDim2.new(1, -10, 0.5, 0), textSize = 13, z = 21 })
	compareBtn.onClick(function()
		if #state.compare == 2 then
			ctx.Contract.compare(state.compare[1], state.compare[2])
		end
	end)
	local clearC = Ui.button(compareTray, { text = "비우기", style = "ghost", size = UDim2.fromOffset(84, 40), anchor = Vector2.new(1, 0.5), pos = UDim2.new(1, -128, 0.5, 0), textSize = 13, z = 21 })
	clearC.onClick(function()
		state.compare = {}
		updateCompareTray()
		ctx.Detail.refresh()
	end)

	Ui.onLayout(function()
		if isOpen then
			layout()
		end
	end)
	for _, attr in { "Bank", "Money" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if isOpen then
				updateMoney()
				ctx.Detail.refresh()
			end
		end)
	end
	ctx.Net.onChanged(function()
		if isOpen then
			renderTabs()
			updateToolbar()
			updateNotice()
			render()
			ctx.Detail.refresh()
			layout()
		end
	end)
	ctx.Net.onGarage("cars", function()
		if isOpen then
			ctx.Net.refresh()
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- input
-------------------------------------------------------------------------------------------------
local function cycleCat(dir: number)
	local cats = Cat.catsIn(ctx.Net.state.entries)
	local idx = 1
	for i, c in cats do
		if c.id == state.cat then
			idx = i
		end
	end
	idx = ((idx - 1 + dir) % #cats) + 1
	CatalogUI.setCat(cats[idx].id)
end

local function bindKeys(on: boolean)
	if on then
		Ui.bind("GwCarDealerCatalog", function(_, st, input)
			if st ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end
			if ctx.Contract.isOpen() or ctx.Ceremony.isOpen() then
				return Enum.ContextActionResult.Pass
			end
			local kc = input.KeyCode
			if kc == Enum.KeyCode.ButtonB or kc == Enum.KeyCode.Backspace then
				Ui.closeMenu()
				if ctx.Detail.isOpen() then
					CatalogUI.closeDetail()
				else
					CatalogUI.close()
				end
				return Enum.ContextActionResult.Sink
			elseif kc == Enum.KeyCode.ButtonL1 then
				cycleCat(-1)
				return Enum.ContextActionResult.Sink
			elseif kc == Enum.KeyCode.ButtonR1 then
				cycleCat(1)
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, 2900, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	else
		Ui.unbind("GwCarDealerCatalog")
	end
end

-------------------------------------------------------------------------------------------------
-- API
-------------------------------------------------------------------------------------------------
function CatalogUI.isOpen(): boolean
	return isOpen
end

function CatalogUI.ctxNpc(): any
	return state.npc
end

function CatalogUI.tradeMode(): boolean
	return state.trade
end

function CatalogUI.setCat(id: string)
	state.cat = id
	for cid, chip in tabChips do
		chip.set(cid == id)
	end
	local chip = tabChips[id]
	if chip then
		-- keep the active tab visible
		local x = chip.inst.AbsolutePosition.X - tabsScroll.AbsolutePosition.X
		if x < 0 or x + chip.inst.AbsoluteSize.X > tabsScroll.AbsoluteSize.X then
			tabsScroll.CanvasPosition = Vector2.new(math.max(0, tabsScroll.CanvasPosition.X + x - 20), 0)
		end
	end
	gridScroll.CanvasPosition = Vector2.zero
	render()
	if Ui.metrics().gamepad and cards[1] then
		Ui.select(cards[1].inst)
	end
end

function CatalogUI.toggleWish(id: string)
	local on = not ctx.Net.state.wish[id]
	ctx.Net.state.wish[id] = if on then true else nil
	Ui.sfx(if on then "success" else "toggle")
	for _, c in cards do
		if c.e.id == id then
			local h = c.inst:FindFirstChild("Wish") :: TextButton?
			if h then
				h.Text = if on then "❤" else "♡"
				h.TextColor3 = if on then Col.pink else Col.ink
			end
		end
	end
	ctx.Detail.refresh()
	task.spawn(function()
		local r = ctx.Net.call("wish", { entry = id, on = on })
		if r.ok and type(r.wish) == "table" then
			local s = {}
			for _, w in r.wish do
				s[w] = true
			end
			ctx.Net.state.wish = s
		end
		if on then
			Ui.toast({ kind = "info", icon = "❤", title = "찜했어요", body = "상담원이 기억해 둘게요 · '❤ 찜한 차' 필터로 모아 볼 수 있어요" })
		end
	end)
end

function CatalogUI.inCompare(id: string): boolean
	return table.find(state.compare, id) ~= nil
end

function CatalogUI.toggleCompare(id: string)
	local i = table.find(state.compare, id)
	if i then
		table.remove(state.compare, i)
	else
		if #state.compare >= 2 then
			table.remove(state.compare, 1)
		end
		table.insert(state.compare, id)
	end
	updateCompareTray()
	ctx.Detail.refresh()
end

function CatalogUI.openDetail(id: string)
	local e = ctx.Net.state.byId[id]
	if not e then
		return
	end
	local wasOpen = ctx.Detail.isOpen()
	ctx.Detail.show(e)
	layout()
	if not wasOpen and not Ui.reduced() then
		-- phones: the detail slides up like a bottom sheet; wide screens: it slides in from the right
		if mode == "overlay" then
			detailHost.Position = UDim2.new(0, 0, 1, 0)
			Ui.tween(detailHost, 0.3, { Position = UDim2.fromOffset(0, 0) })
		else
			local target = detailHost.Position
			detailHost.Position = target + UDim2.fromOffset(60, 0)
			Ui.tween(detailHost, 0.25, { Position = target })
		end
	end
end

function CatalogUI.closeDetail()
	ctx.Detail.hide()
	layout()
	for _, c in cards do
		if Ui.metrics().gamepad then
			Ui.select(c.inst)
			break
		end
	end
end

function CatalogUI.open(opts: { [string]: any }?)
	local o = opts or {}
	if not gui then
		build()
	end
	if ctx.Dialog.isOpen() then
		ctx.Dialog.close()
	end
	state.cat = o.cat or (if o.entry then "all" else state.cat)
	state.pick = o.pick
	state.npc = o.npc or state.npc
	state.trade = o.trade == true
	state.query = ""
	searchBox.Text = ""
	isOpen = true
	Ui.show(gui, true)
	Ui.controls("catalog", false)
	bindKeys(true)
	Ui.sfx("open")
	if not Ui.reduced() then
		root.BackgroundTransparency = 1
		Ui.tween(root, 0.25, { BackgroundTransparency = 0.02 })
	end
	titleSub.Text = "차량 정보를 불러오는 중…"
	layout()
	task.spawn(function()
		local ok = ctx.Net.refresh()
		if not isOpen then
			return
		end
		if not ok and not ctx.Net.state.loaded then
			titleSub.Text = "차량 정보를 불러오지 못했어요 · 잠시 후 다시 열어 주세요"
			return
		end
		renderTabs()
		updateToolbar()
		updateNotice()
		layout()
		render()
		updateCompareTray()
		if o.entry and ctx.Net.state.byId[o.entry] then
			CatalogUI.openDetail(o.entry)
		elseif Ui.metrics().gamepad and cards[1] then
			Ui.select(cards[1].inst)
		end
	end)
end

function CatalogUI.close()
	if not isOpen then
		return
	end
	isOpen = false
	Ui.closeMenu()
	ctx.Detail.hide()
	destroyThumbs()
	clearCards()
	bindKeys(false)
	Ui.controls("catalog", true)
	Ui.deselect(gui)
	Ui.show(gui, false)
	compareTray.Visible = false
	Ui.sfx("close")
end

function CatalogUI.init(c: any)
	ctx = c
	Ui = c.Ui
	C = c.C
	U = c.S.Util
	Cat = c.S.Catalog
	Col = Ui.C
	player.CharacterAdded:Connect(function()
		CatalogUI.close()
	end)
end

return CatalogUI
