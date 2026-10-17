--!strict
-- GwangalliDecorPlus/Panels: every screen of the 자유 배치 editor — top bar (stats, ↶ ↷, 마감재, 프리셋,
-- 목표, 사진, 설정), the catalog sheet (14 categories + 창고 + 추천 세트, 초성 search, style filter, sort,
-- 3D thumbnails), the context action bar + status line, the item info card, and the modals for
-- 벽지 · 바닥 · 조명, 배치 프리셋 3칸, 인테리어 점수 · 뱃지 · 목표 and 설정. Landscape = right panel,
-- portrait phones = bottom sheet. Draws from Editor.S and the server snapshot.
--   Panels.mount(ctx) / Panels.unmount() / Panels.score(view) / Panels.refresh()
--   ctx = { snap, model, U, onClose(), onPhoto() }

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliDecorShared"))
local Config, Catalog, Text, Palette, Finish, Unit = Shared.Config, Shared.Catalog, Shared.Text, Shared.Palette, Shared.Finish, Shared.Unit

local Ui = require(script.Parent:WaitForChild("Ui"))
local Net = require(script.Parent:WaitForChild("Net"))
local Editor = require(script.Parent:WaitForChild("Editor"))
local Preview = require(script.Parent:WaitForChild("Preview"))
local Picker = require(script.Parent:WaitForChild("Picker"))
local C, F = Ui.C, Ui.F

local Panels = {}

local gui: ScreenGui? = nil
local ctx: any = nil
local refs: any = {}
local cat = "living"
local style = "all"
local sortKey = "price"
local query = ""
local collapsed = false
local unsub: (() -> ())? = nil
local SORTS = { { "price", "가격 낮은 순" }, { "priceDesc", "가격 높은 순" }, { "decor", "인테리어 점수 순" }, { "new", "새로 나온 순" } }
local CM_PER_STUD = 32

local function S(): any
	return Editor.S
end

local function money(): string
	local b = S().balance or ctx.snap.balance or { cash = 0, bank = 0 }
	return "💳 " .. Text.wonShort(b.bank) .. " · 💵 " .. Text.wonShort(b.cash)
end

-------------------------------------------------------------------------------------------------
-- Top bar
-------------------------------------------------------------------------------------------------
local function chipLabel(parent: Instance, text: string, order: number): TextLabel
	local l = Ui.label(parent, text, 14, C.text, F.bold, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 40), LayoutOrder = order, BackgroundTransparency = 0.15, BackgroundColor3 = C.card, TextWrapped = false })
	Ui.corner(l, 20)
	Ui.pad(l, 12, 0, 12, 0)
	return l
end

local function buildTop(root: Frame)
	local bar = Ui.panel(root, { Name = "Top", Position = UDim2.new(0, 8, 0, 8), Size = UDim2.new(1, -16, 0, 58) })
	local sc = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.new(0, 6, 0, 0),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 0,
		Selectable = false,
		Parent = bar,
	})
	Ui.list(sc, "x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	Ui.button(sc, { text = "✓ " .. Text.UI.done, w = 96, h = 44, style = "primary", order = 1, onClick = function()
		ctx.onClose()
	end })
	local title = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 170, 0, 44), LayoutOrder = 2, Parent = sc })
	Ui.label(title, "✨ " .. Text.UI.title, 17, C.text, F.heavy, { Size = UDim2.new(1, 0, 0, 22), TextWrapped = false })
	Ui.label(title, ctx.snap.homeName, 12, C.sub, F.medium, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 23), TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
	refs.score = chipLabel(sc, "⭐ 0", 3)
	refs.money = chipLabel(sc, money(), 4)
	refs.count = chipLabel(sc, "🛋️ 0/0", 5)
	local function tb(text: string, order: number, fn: () -> ()): TextButton
		return Ui.button(sc, { text = text, auto = true, h = 44, style = "tonal", order = order, onClick = fn })
	end
	refs.undo = tb("↶", 10, function()
		Editor.undo()
	end)
	refs.redo = tb("↷", 11, function()
		Editor.redo()
	end)
	tb("🎨 " .. Text.UI.finish, 12, function()
		Panels.finish()
	end)
	tb("💾 " .. Text.UI.presets, 13, function()
		Panels.presets()
	end)
	tb("🏆 " .. Text.UI.goals, 14, function()
		Panels.goals()
	end)
	tb("📸", 15, function()
		ctx.onPhoto()
	end)
	tb("⚙️", 16, function()
		Panels.settings()
	end)
	tb("❔", 17, function()
		Panels.help()
	end)
	-- room / level quick focus
	local rooms = Ui.new("ScrollingFrame", {
		Name = "Rooms",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 72),
		Size = UDim2.new(1, -16, 0, 40),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 0,
		Selectable = false,
		Parent = root,
	})
	refs.rooms = rooms
	Ui.list(rooms, "x", 6)
	local Camera = require(script.Parent:WaitForChild("Camera"))
	local U = ctx.U
	for i, r in U.rooms do
		if r.area > 6 then
			local b = Ui.chip(rooms, r.icon .. " " .. r.name, false, function()
				Camera.focusRoom(r)
			end, i)
			b.Size = UDim2.new(0, 0, 0, 34)
		end
	end
	if #U.levels > 1 then
		for i, l in U.levels do
			local b = Ui.chip(rooms, "🪜 " .. l.name, false, function()
				Camera.setLevel(i)
			end, 100 + i)
			b.Size = UDim2.new(0, 0, 0, 34)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Catalog sheet
-------------------------------------------------------------------------------------------------
local function storageCount(id: string): number
	local st = S().storage or {}
	return st[id] or 0
end

local function card(parent: Instance, id: string, order: number, mode: string?)
	local def = Catalog.get(id)
	local catInfo = Catalog.CAT_BY_ID[def.cat]
	local b = Ui.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.card, BackgroundTransparency = 0.05, LayoutOrder = order, Selectable = true, Parent = parent })
	Ui.corner(b, 14)
	Ui.stroke(b, C.line, 0.9)
	Ui.pressable(b)
	local thumb = Ui.new("Frame", { Name = "Thumb", BackgroundColor3 = C.glass2, BackgroundTransparency = 0, Size = UDim2.new(1, -10, 0, 82), Position = UDim2.new(0, 5, 0, 5), Parent = b })
	Ui.corner(thumb, 10)
	local icon = Ui.label(thumb, catInfo.icon, 34, C.text, F.bold, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
	if order <= Config.PREVIEW_CACHE then
		task.defer(function()
			if thumb.Parent and Preview.fill(thumb, id, nil) then
				icon.Visible = false
			end
		end)
	end
	Ui.label(b, def.name, 12, C.text, F.bold, { Position = UDim2.new(0, 7, 0, 90), Size = UDim2.new(1, -14, 0, 30), TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd })
	local n = storageCount(id)
	local priceText = if mode == "storage" or n > 0 then ("📦 " .. Text.fmt(Text.UI.stock, n) .. " · " .. Text.UI.free) else Text.won(def.price)
	Ui.label(b, priceText, 12, if n > 0 then C.green else C.gold, F.bold, { Position = UDim2.new(0, 7, 0, 120), Size = UDim2.new(1, -40, 0, 16), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.label(b, "⭐" .. def.decor, 11, C.sub, F.bold, { Position = UDim2.new(1, -38, 0, 120), Size = UDim2.new(0, 34, 0, 16), TextXAlignment = Enum.TextXAlignment.Right })
	local info = Ui.new("TextButton", { Text = "ⓘ", TextSize = 16, Font = F.bold, TextColor3 = C.sub, BackgroundTransparency = 1, Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(1, -32, 0, 4), Selectable = false, Parent = b })
	info.Activated:Connect(function()
		Panels.info(id, nil)
	end)
	b.Activated:Connect(function()
		Editor.pick(id, if storageCount(id) > 0 then "storage" else "buy", nil)
		if Ui.portrait() then
			Panels.collapse(true)
		end
		if Ui.isGamepad() then
			-- hand Ⓐ back to the world cursor (Ⓨ reopens the catalog)
			GuiService.SelectedObject = nil
		end
	end)
	return b
end

local function setCard(parent: Instance, set: any, order: number)
	local b = Ui.new("Frame", { BackgroundColor3 = C.card, BackgroundTransparency = 0.05, Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = parent })
	Ui.corner(b, 14)
	Ui.stroke(b, C.line, 0.9)
	Ui.pad(b, 12)
	Ui.list(b, "y", 6)
	Ui.label(b, set.icon .. " " .. set.name, 16, C.text, F.heavy, { LayoutOrder = 1 })
	Ui.label(b, set.desc, 13, C.sub, F.medium, { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.Y })
	local names = {}
	for _, id in set.items do
		table.insert(names, Catalog.get(id).name)
	end
	Ui.label(b, table.concat(names, " · "), 12, C.faint, F.medium, { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.Y })
	Ui.label(b, string.format("%d개 · 합계 %s", #set.items, Text.won(set.total)), 13, C.gold, F.bold, { LayoutOrder = 4 })
	Ui.button(b, { text = "🛍️ 세트 담고 하나씩 놓기", w = UDim2.new(1, 0, 0, 44), style = "primary", order = 5, onClick = function()
		Editor.startSet(set)
		if Ui.portrait() then
			Panels.collapse(true)
		end
	end })
end

local function fillGrid()
	local grid = refs.grid :: ScrollingFrame
	for _, c in grid:GetChildren() do
		if c:IsA("GuiObject") then
			Preview.clear(c:FindFirstChild("Thumb") or c)
			c:Destroy()
		end
	end
	local layout = refs.gridLayout
	local list = refs.listLayout
	if cat == "sets" then
		if layout then
			layout.Parent = nil
		end
		if list then
			list.Parent = grid
		end
		for i, set in Catalog.SETS do
			setCard(grid, set, i)
		end
		return
	end
	if list then
		list.Parent = nil
	end
	if layout then
		layout.Parent = grid
	end
	local ids
	if cat == "storage" then
		ids = {}
		for id, n in S().storage or {} do
			if n > 0 and Catalog.get(id) then
				table.insert(ids, id)
			end
		end
		if query ~= "" then
			ids = Catalog.search(query, ids)
		end
		table.sort(ids, function(a, b)
			return Catalog.get(a).order < Catalog.get(b).order
		end)
		if #ids == 0 then
			local l = Ui.label(grid, "창고가 비어 있어요. 놓인 가구를 📦 창고에 넣으면 여기서 꺼낼 수 있어요.", 13, C.sub, F.medium, { Size = UDim2.new(1, -8, 0, 60), LayoutOrder = 1 })
			l.TextXAlignment = Enum.TextXAlignment.Center
		end
	else
		ids = Catalog.list(if cat == "all" then nil else cat, { style = style, sort = sortKey, query = query })
	end
	for i, id in ids do
		local b = card(grid, id, i, if cat == "storage" then "storage" else nil)
		if cat == "storage" then
			local sell = Ui.new("TextButton", { Text = "💰", TextSize = 14, BackgroundColor3 = C.card2, Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(0, 8, 0, 8), Selectable = false, Parent = b })
			Ui.corner(sell, 15)
			sell.Activated:Connect(function()
				local amount = Catalog.resale(id, Config.SELL_RATE)
				Ui.confirm({ gui = gui, title = "창고 가구 팔기", body = string.format("%s 1개를 %s에 팔까요?", Catalog.get(id).name, Text.won(amount)), ok = "💰 팔기", okStyle = "gold", onOk = function()
					local res = Net.call("sellStored", { i = id, n = 1 })
					if res.ok then
						S().storage = res.storage
						S().balance = res.balance
						Ui.toast(Text.fmt(Text.TOAST.sold, Text.won(res.amount)), "gold")
						Panels.refresh()
					else
						Ui.toast("❌ " .. res.msg, "bad")
					end
				end })
			end)
		end
	end
end

local function buildCatalog(root: Frame)
	local portrait = Ui.portrait()
	local sheet = Ui.panel(root, { Name = "Catalog" })
	refs.sheet = sheet
	if portrait then
		sheet.Position = UDim2.new(0, 8, 0.58, 0)
		sheet.Size = UDim2.new(1, -16, 0.42, -8)
	else
		sheet.Position = UDim2.new(1, -364, 0, 120)
		sheet.Size = UDim2.new(0, 356, 1, -128)
	end
	-- category tabs
	local tabs = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 8),
		Size = UDim2.new(1, -60, 0, 42),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 0,
		Selectable = false,
		Parent = sheet,
	})
	Ui.list(tabs, "x", 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local tabSet: { [string]: (boolean) -> () } = {}
	local function addTab(id: string, text: string, order: number)
		local _, set = Ui.chip(tabs, text, cat == id, function()
			cat = id
			for k, f in tabSet do
				f(k == id)
			end
			fillGrid()
		end, order)
		tabSet[id] = set
	end
	addTab("all", Text.UI.all, 0)
	for i, c in Catalog.CATEGORIES do
		addTab(c.id, c.icon .. " " .. c.name, i)
	end
	addTab("storage", "📦 " .. Text.UI.storage, 40)
	addTab("sets", "🛍️ " .. Text.UI.sets, 41)
	local col = Ui.button(sheet, { text = if portrait then "▼" else "▶", w = 40, h = 40, style = "ghost", onClick = function()
		Panels.collapse(not collapsed)
	end })
	col.Position = UDim2.new(1, -48, 0, 9)
	refs.collapseBtn = col
	-- search + sort
	local search = Ui.textbox(sheet, Text.UI.search, { Position = UDim2.new(0, 10, 0, 56), Size = UDim2.new(1, -140, 0, 40) })
	search:GetPropertyChangedSignal("Text"):Connect(function()
		query = Text.clip(search.Text, 24)
		fillGrid()
	end)
	local sortBtn = Ui.button(sheet, { text = "↕ 가격", w = 116, h = 40, style = "tonal", size = 13 })
	sortBtn.Position = UDim2.new(1, -126, 0, 56)
	sortBtn.Activated:Connect(function()
		local i = 1
		for k, s in SORTS do
			if s[1] == sortKey then
				i = k
			end
		end
		local nx = SORTS[(i % #SORTS) + 1]
		sortKey = nx[1]
		sortBtn.Text = "↕ " .. string.gsub(nx[2], " 순", "")
		fillGrid()
	end)
	-- style chips
	local styles = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 102),
		Size = UDim2.new(1, -20, 0, 36),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 0,
		Selectable = false,
		Parent = sheet,
	})
	Ui.list(styles, "x", 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local styleSet: { [string]: (boolean) -> () } = {}
	local function addStyle(id: string, text: string, order: number)
		local b, set = Ui.chip(styles, text, style == id, function()
			style = id
			for k, f in styleSet do
				f(k == id)
			end
			fillGrid()
		end, order)
		b.Size = UDim2.new(0, 0, 0, 32)
		b.TextSize = 13
		styleSet[id] = set
	end
	addStyle("all", "모든 스타일", 0)
	for i, s in Catalog.STYLES do
		addStyle(s.id, s.name, i)
	end
	local grid = Ui.scroll(sheet, { Position = UDim2.new(0, 8, 0, 144), Size = UDim2.new(1, -16, 1, -150) })
	refs.gridLayout = Ui.new("UIGridLayout", { CellSize = UDim2.new(0, 104, 0, 142), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	local list = Ui.list(grid, "y", 8)
	list.Parent = nil
	refs.listLayout = list
	Ui.pad(grid, 2, 2, 2, 10)
	refs.grid = grid
	fillGrid()
end

function Panels.collapse(on: boolean)
	collapsed = on
	local sheet = refs.sheet
	if not sheet then
		return
	end
	local portrait = Ui.portrait()
	if portrait then
		sheet.Position = if on then UDim2.new(0, 8, 1, -60) else UDim2.new(0, 8, 0.58, 0)
		refs.collapseBtn.Text = if on then "▲" else "▼"
	else
		sheet.Position = if on then UDim2.new(1, -64, 0, 120) else UDim2.new(1, -364, 0, 120)
		refs.collapseBtn.Text = if on then "◀" else "▶"
		refs.collapseBtn.Position = if on then UDim2.new(0, 8, 0, 9) else UDim2.new(1, -48, 0, 9)
	end
	Panels.layoutBar()
end

-------------------------------------------------------------------------------------------------
-- Action bar + status
-------------------------------------------------------------------------------------------------
function Panels.layoutBar()
	local bar = refs.bar
	if not bar then
		return
	end
	local portrait = Ui.portrait()
	if portrait then
		local top = if collapsed then -134 else nil
		if top then
			bar.Position = UDim2.new(0, 8, 1, top)
		else
			bar.Position = UDim2.new(0, 8, 0.58, -76)
		end
		bar.Size = UDim2.new(1, -16, 0, 64)
	else
		local right = if collapsed then 72 else 372
		bar.Position = UDim2.new(0, 8, 1, -76)
		bar.Size = UDim2.new(1, -(right + 8), 0, 64)
	end
	refs.status.Position = bar.Position - UDim2.new(0, 0, 0, 42)
	refs.status.Size = UDim2.new(bar.Size.X.Scale, bar.Size.X.Offset, 0, 36)
end

local function abtn(text: string, style: string?, fn: () -> (), order: number, pinned: boolean?): TextButton
	local parent = if pinned then refs.barRight else refs.barList
	return Ui.button(parent, { text = text, auto = true, h = 50, w = if pinned then 64 else 50, style = style or "tonal", order = order, size = 15, onClick = fn })
end

local function gridText(): string
	local g = S().settings.grid
	return "📐 " .. (if g == 0 then "격자 끔" else ("격자 " .. tostring(g)))
end

local function rotText(): string
	local r = S().settings.rot
	return "⟳ " .. (if r <= 1 then "미세" else (tostring(r) .. "°"))
end

local function cycleRot()
	local steps = Config.ROT_STEPS
	local i = table.find(steps, S().settings.rot) or 1
	Editor.setRotStep(steps[(i % #steps) + 1])
end

local function settingChips(order: number)
	abtn(gridText(), "ghost", function()
		Editor.cycleGrid()
	end, order)
	abtn(rotText(), "ghost", cycleRot, order + 1)
	if Config.ALLOW_OVERLAP_TOGGLE then
		abtn((if S().settings.overlap then "🧩 겹치기 ✓" else "🧩 겹치기"), if S().settings.overlap then "magenta" else "ghost", function()
			Editor.setOverlap(not S().settings.overlap)
		end, order + 2)
	end
end

local function useButtons(u: number, order: number)
	local rec = S().recs[u]
	if not rec then
		return
	end
	local uses = Catalog.uses(rec.i)
	local m = Editor.itemModel(u)
	local function act(what: string)
		task.spawn(function()
			local res = Net.call("interact", { u = u, what = what })
			if not res.ok then
				Ui.toast("❌ " .. res.msg, "bad")
			end
			task.wait(0.25)
			Panels.refresh()
		end)
	end
	if uses.lamp or uses.fire then
		local on = rec.on ~= false
		if m then
			on = m:GetAttribute("LampOn") ~= false
		end
		abtn(if on then "💡 끄기" else "💡 켜기", "ghost", function()
			rec.on = if on then false else nil
			act(if uses.fire then "fire" else "lamp")
		end, order)
	end
	if uses.tv then
		abtn("📺 TV", "ghost", function()
			act("tv")
		end, order + 1)
		abtn("📡 채널", "ghost", function()
			act("channel")
		end, order + 2)
	end
	if uses.music then
		abtn("🎵 음악", "ghost", function()
			act("music")
		end, order + 3)
	end
	if uses.open then
		abtn("🚪 열기/닫기", "ghost", function()
			act("open")
		end, order + 4)
	end
end

function Panels.refreshBar()
	local list = refs.barList
	if not list then
		return
	end
	for _, holder in { list, refs.barRight } do
		for _, c in holder:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end
	local st = S()
	local status = refs.statusLbl :: TextLabel
	refs.status.Visible = true
	if st.mode == "place" or st.mode == "move" then
		abtn("⟲", nil, function()
			Editor.rotate(-1)
		end, 1)
		abtn("⟳", nil, function()
			Editor.rotate(1)
		end, 2)
		abtn("▲", nil, function()
			Editor.lift(1)
		end, 3)
		abtn("▼", nil, function()
			Editor.lift(-1)
		end, 4)
		if st.mode == "place" and st.members and #st.members == 1 then
			abtn("🎨", nil, function()
				local mb = st.members[1]
				Picker.item(gui :: ScreenGui, mb.i, mb.look, function(c, m)
					mb.look = { c = c, m = m }
					st.pickLook = mb.look
					Editor.pick(mb.i, st.pickSrc, mb.look)
				end, nil)
			end, 5)
		end
		settingChips(10)
		abtn("✕", "ghost", function()
			Editor.cancel()
		end, 20, true)
		local label
		if st.mode == "place" then
			local id = st.members and st.members[1] and st.members[1].i
			local n = 0
			local total = 0
			for _, mb in st.members or {} do
				n += 1
				if storageCount(mb.i) <= 0 then
					total += Catalog.price(mb.i)
				end
			end
			local fromStore = id and storageCount(id) > 0 and n == 1
			label = if fromStore then ("✓ " .. Text.UI.placeFree) else ("✓ " .. Text.UI.place .. " · " .. Text.won(total))
		else
			label = "✓ 확인"
		end
		abtn(label, if st.valid == false then "tonal" else "green", function()
			Editor.confirm()
		end, 30, true)
		-- status
		local nm = st.members and st.members[1] and Catalog.get(st.members[1].i)
		if st.valid == false then
			status.Text = "❌ " .. Text.reason(st.code, st.arg)
			status.TextColor3 = C.red
		else
			status.Text = "✅ " .. Text.UI.okHere .. (if nm then ("  ·  " .. nm.name) else "") .. (if (st.lift or 0) > 0.01 then string.format("  ·  ▲ %.2f", st.lift) else "")
			status.TextColor3 = C.green
		end
		if st.cart then
			local left = 0
			for k = st.cart.i, #st.cart.set.items do
				left += Catalog.price(st.cart.set.items[k])
			end
			status.Text ..= "   🛍️ " .. Text.fmt(Text.UI.setProgress, st.cart.i, #st.cart.set.items, Text.won(left))
		end
		return
	end
	local sel = Editor.selected()
	if #sel == 1 then
		local u = sel[1]
		local rec = st.recs[u]
		local def = rec and Catalog.get(rec.i)
		if not def then
			return
		end
		abtn("✥ " .. Text.UI.move, "primary", function()
			Editor.moveSelected()
		end, 1)
		abtn("⟳", nil, function()
			Editor.rotate(1)
		end, 2)
		abtn("🎨 " .. Text.UI.color, nil, function()
			Picker.item(gui :: ScreenGui, rec.i, { c = rec.c, m = rec.m }, function(c, m)
				Editor.recolor(u, c, m)
			end, nil)
		end, 3)
		abtn("⧉ " .. Text.UI.dup, nil, function()
			Editor.duplicate()
		end, 4)
		abtn("ℹ️", nil, function()
			Panels.info(rec.i, u)
		end, 5)
		useButtons(u, 6)
		abtn("📦 " .. Text.UI.toStorage, nil, function()
			Editor.removeSelected("store")
		end, 20)
		local fresh = Editor.freshLeft(u) > 1
		local sellText = if fresh then Text.fmt(Text.UI.priceFresh, Text.won(def.price)) else Text.fmt(Text.UI.priceSell, Text.won(Catalog.resale(rec.i, Config.SELL_RATE)))
		abtn(sellText, "gold", function()
			Ui.confirm({ gui = gui, title = if fresh then "구매 취소" else "가구 팔기", body = if fresh then "방금 산 가구라 전액 돌려받아요" else Text.fmt(Text.UI.confirmSell, math.floor(Config.SELL_RATE * 100)), ok = sellText, okStyle = "gold", onOk = function()
				Editor.removeSelected("sell")
			end })
		end, 21, true)
		status.Text = def.name .. "  ·  " .. Catalog.lookName(rec.i, rec.c, rec.m) .. "  ·  ⭐" .. def.decor
		status.TextColor3 = C.text
		return
	elseif #sel > 1 then
		abtn("✥ " .. Text.UI.groupMove, "primary", function()
			Editor.moveSelected()
		end, 1)
		abtn("⟳ 90°", nil, function()
			local r = S().settings.rot
			S().settings.rot = 90
			Editor.rotate(1)
			S().settings.rot = r
		end, 2)
		abtn("⧉ " .. Text.UI.dup, nil, function()
			Editor.duplicate()
		end, 3)
		abtn("📦 " .. Text.UI.toStorage, nil, function()
			Editor.removeSelected("store")
		end, 4)
		abtn("💰 " .. Text.UI.sell, "gold", function()
			Ui.confirm({ gui = gui, title = "가구 팔기", body = string.format("선택한 %d개를 팔까요? (산 지 10분이 안 된 가구는 전액 환불)", #sel), ok = "💰 팔기", okStyle = "gold", onOk = function()
				Editor.removeSelected("sell")
			end })
		end, 5)
		abtn("✕ 선택 해제", "ghost", function()
			Editor.select(nil, false)
		end, 6)
		status.Text = Text.fmt(Text.UI.selected, #sel) .. "  ·  Shift+클릭으로 더 고르기"
		status.TextColor3 = C.cyan
		return
	end
	-- browse, nothing selected
	settingChips(1)
	if Ui.isTouch() then
		abtn(if st.multi then "☑ 다중 선택" else "☐ 다중 선택", if st.multi then "primary" else "ghost", function()
			Editor.setMulti(not st.multi)
		end, 5)
	end
	abtn("🛋️ 카탈로그", "tonal", function()
		Panels.collapse(false)
	end, 6)
	status.Text = if Ui.isTouch() then "가구를 고르거나 놓인 가구를 탭하세요 · 길게 누르면 옮겨요" elseif Ui.isGamepad() then "Ⓐ 선택 · Ⓨ 카탈로그 · RB/LB 회전 · 스틱으로 이동" else Text.UI.keysPC
	status.TextColor3 = C.sub
end

local function buildBar(root: Frame)
	local bar = Ui.panel(root, { Name = "Actions" })
	refs.bar = bar
	local sc = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 7, 0, 0),
		Size = UDim2.new(1, -14, 1, 0),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 0,
		Selectable = false,
		Parent = bar,
	})
	Ui.list(sc, "x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	refs.barList = sc
	-- primary actions (✓ 놓기 · ✕ · 팔기) stay visible at the right end
	local right = Ui.new("Frame", { Name = "Pinned", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -7, 0, 0), Parent = bar })
	Ui.list(right, "x", 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	refs.barRight = right
	right:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local sc2 = refs.barList
		local scale = (gui :: ScreenGui):FindFirstChildOfClass("UIScale")
		local k = if scale then scale.Scale else 1
		if sc2 then
			sc2.Size = UDim2.new(1, -14 - right.AbsoluteSize.X / k - (if right.AbsoluteSize.X > 1 then 8 else 0), 1, 0)
		end
	end)
	local status = Ui.new("Frame", { Name = "Status", BackgroundColor3 = C.glass, BackgroundTransparency = 0.2, Parent = root })
	Ui.corner(status, 18)
	refs.status = status
	refs.statusLbl = Ui.label(status, "", 14, C.text, F.bold, { Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -28, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
	Panels.layoutBar()
	Panels.refreshBar()
end

-------------------------------------------------------------------------------------------------
-- Info card
-------------------------------------------------------------------------------------------------
function Panels.info(id: string, u: number?)
	local def = Catalog.get(id)
	if not def then
		return
	end
	local m = Ui.modal("ℹ️ " .. def.name, { gui = gui, w = 460, h = 0.72 })
	local catInfo = Catalog.CAT_BY_ID[def.cat]
	local st = Catalog.STYLE_BY_ID[def.style]
	local thumb = Ui.new("Frame", { BackgroundColor3 = C.glass2, Size = UDim2.new(1, 0, 0, 170), LayoutOrder = 1, Parent = m.body })
	Ui.corner(thumb, 12)
	local rec = u and S().recs[u]
	if not Preview.fill(thumb, id, rec and { c = rec.c, m = rec.m } or nil) then
		Ui.label(thumb, catInfo.icon, 60, C.text, F.bold, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
	end
	local dims = Catalog.dims(id)
	local lines = {
		string.format("%s %s · %s · %s", catInfo.icon, catInfo.name, st and st.name or "", Text.PLACE[def.place].icon .. " " .. Text.PLACE[def.place].name),
		string.format("가격 <b>%s</b> · 되팔기 %s · ⭐ 인테리어 +%d", Text.won(def.price), Text.won(Catalog.resale(id, Config.SELL_RATE)), def.decor),
		string.format("크기 가로 %dcm · 깊이 %dcm · 높이 %dcm", math.floor(dims.X * CM_PER_STUD + 0.5), math.floor(dims.Z * CM_PER_STUD + 0.5), math.floor(dims.Y * CM_PER_STUD + 0.5)),
	}
	local uses = Catalog.uses(id)
	local ut = {}
	if uses.sit then
		table.insert(ut, "🪑 앉기")
	end
	if uses.lie then
		table.insert(ut, "🛏️ 눕기")
	end
	if uses.lamp then
		table.insert(ut, "💡 불 켜기/끄기")
	end
	if uses.fire then
		table.insert(ut, "🔥 불 피우기")
	end
	if uses.tv then
		table.insert(ut, "📺 TV · 채널")
	end
	if uses.music then
		table.insert(ut, "🎵 음악")
	end
	if uses.open then
		table.insert(ut, "🚪 " .. uses.open)
	end
	if uses.feed then
		table.insert(ut, "🐠 먹이 주기")
	end
	if #ut > 0 then
		table.insert(lines, "할 수 있는 것: " .. table.concat(ut, " · "))
	end
	if #def.slots > 0 then
		local sl = {}
		for _, s in def.slots do
			table.insert(sl, s.label)
		end
		table.insert(lines, "🎨 바꿀 수 있는 색: " .. table.concat(sl, " · "))
	end
	if rec then
		table.insert(lines, "지금 모습: " .. Catalog.lookName(id, rec.c, rec.m))
	end
	local n = storageCount(id)
	if n > 0 then
		table.insert(lines, string.format("📦 창고에 %d개 있어요 (꺼내면 무료)", n))
	end
	for i, l in lines do
		Ui.label(m.body, l, 14, if i == 2 then C.gold else C.text, F.medium, { LayoutOrder = 1 + i, AutomaticSize = Enum.AutomaticSize.Y })
	end
	if not u then
		Ui.button(m.body, { text = if n > 0 then "📦 창고에서 꺼내 놓기" else ("✓ 놓아 보기 · " .. Text.won(def.price)), w = UDim2.new(1, 0, 0, 48), style = "primary", order = 20, onClick = function()
			m.close()
			Editor.pick(id, if n > 0 then "storage" else "buy", nil)
		end })
	end
end

-------------------------------------------------------------------------------------------------
-- 벽지 · 바닥 · 조명
-------------------------------------------------------------------------------------------------
local function rgbOf(hex: any, d: { number }?): { number }
	return Palette.unhex(hex) or d or { 200, 200, 200 }
end

local function patternSwatch(parent: Instance, def: any, a: { number }, b: { number }?): Frame
	local f = Ui.new("Frame", { BackgroundColor3 = Palette.color3(a), Size = UDim2.new(1, 0, 0, 56), ClipsDescendants = true, Parent = parent })
	Ui.corner(f, 8)
	local bc = Palette.color3(b or Palette.shade(a, 0.7))
	local p = def.pattern
	if p == "stripe" or p == "pinstripe" then
		local w = if p == "stripe" then 10 else 2
		for i = 0, 10 do
			Ui.new("Frame", { BackgroundColor3 = bc, BorderSizePixel = 0, Size = UDim2.new(0, w, 1, 0), Position = UDim2.new(i / 10, 0, 0, 0), Parent = f })
		end
	elseif p == "check" or p == "checker" then
		for i = 0, 7 do
			for j = 0, 3 do
				if (i + j) % 2 == 0 then
					Ui.new("Frame", { BackgroundColor3 = bc, BorderSizePixel = 0, BackgroundTransparency = if p == "check" then 0.45 else 0, Size = UDim2.new(1 / 8, 0, 0.25, 0), Position = UDim2.new(i / 8, 0, j / 4, 0), Parent = f })
				end
			end
		end
	elseif p == "dot" or p == "terrazzo" then
		for i = 0, 11 do
			local d = Ui.new("Frame", { BackgroundColor3 = bc, BorderSizePixel = 0, Size = UDim2.new(0, 7, 0, 7), Position = UDim2.new((i % 6) / 6 + 0.04, 0, (i // 6) / 2 + 0.2, 0), Parent = f })
			Ui.corner(d, 4)
		end
	elseif p == "wainscot" then
		Ui.new("Frame", { BackgroundColor3 = bc, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0.42, 0), Position = UDim2.new(0, 0, 0.58, 0), Parent = f })
	elseif p == "subway" or p == "herringbone" then
		for j = 0, 4 do
			Ui.new("Frame", { BackgroundColor3 = bc, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, j / 5, 0), Parent = f })
		end
	elseif p == "gradient" or p == "mural" then
		local g = Ui.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 1, 0), Parent = f })
		Ui.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Palette.color3(a), bc), Parent = g })
		if p == "mural" then
			Ui.new("Frame", { BackgroundColor3 = C.cyan, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 0.62, 0), Parent = f })
		end
	end
	local md = (Palette.MATERIALS :: any)[def.mat]
	Ui.label(f, md and md.name or "", 10, Color3.new(1, 1, 1), F.bold, { Position = UDim2.new(0, 6, 1, -16), Size = UDim2.new(1, -12, 0, 14), TextStrokeTransparency = 0.5 })
	return f
end

function Panels.finish()
	local snap = ctx.snap
	local m = Ui.modal("🎨 벽지 · 바닥 · 조명", { gui = gui, w = 620, h = 0.88 })
	local body = m.body
	local rooms = snap.rooms or {}
	local state = { room = rooms[1] and rooms[1].id or nil, kind = "wall", pick = nil :: string?, a = nil :: string?, b = nil :: string? }
	local content = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5, Parent = body })
	Ui.list(content, "y", 10)
	local fin = snap.fin or { rooms = {} }
	local function redraw()
		for _, c in content:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if state.kind == "light" then
			Ui.label(content, "집 전체 조명 연출 (모든 방)", 13, C.sub, F.medium, { LayoutOrder = 1 })
			local grid = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = content })
			Ui.new("UIGridLayout", { CellSize = UDim2.new(0, 178, 0, 104), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
			for i, id in Finish.LIGHT_ORDER do
				local def = Finish.LIGHTS[id]
				local cur = (fin.light or "default") == id
				local b = Ui.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if cur then C.card2 else C.card, LayoutOrder = i, Selectable = true, Parent = grid })
				Ui.corner(b, 12)
				Ui.stroke(b, if cur then C.cyan else C.line, if cur then 0 else 0.88, if cur then 2 else 1)
				Ui.pad(b, 10)
				Ui.list(b, "y", 2)
				Ui.label(b, def.icon .. " " .. def.name .. (if cur then "  ✓" else ""), 15, C.text, F.heavy, { LayoutOrder = 1 })
				Ui.label(b, def.desc, 11, C.sub, F.medium, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 30) })
				local price = Finish.price("light", id, snap.tierKey, nil)
				Ui.label(b, if price > 0 then Text.won(price) else "무료", 12, C.gold, F.bold, { LayoutOrder = 3 })
				Ui.pressable(b)
				b.Activated:Connect(function()
					if cur then
						return
					end
					local res = Net.call("finish", { kind = "light", id = id })
					if res.ok then
						fin = res.fin
						snap.fin = res.fin
						S().balance = res.balance
						Ui.toast(Text.fmt(Text.TOAST.finished, "조명", def.name), "good")
						redraw()
						Panels.refresh()
					else
						Ui.toast("❌ " .. res.msg, "bad")
					end
				end)
			end
			return
		end
		if not state.room then
			Ui.label(content, "꾸밀 수 있는 방이 없어요", 14, C.sub)
			return
		end
		local kind = state.kind
		local order = if kind == "wall" then Finish.WALL_ORDER else Finish.FLOOR_ORDER
		local key = if kind == "wall" then "w" else "f"
		local curE = fin.rooms[state.room] and fin.rooms[state.room][key]
		local grid = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = content })
		Ui.new("UIGridLayout", { CellSize = UDim2.new(0, 132, 0, 118), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for i, id in order do
			local def = Finish.def(kind, id)
			local sel = state.pick == id
			local isCur = curE and curE.p == id
			local b = Ui.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.card, LayoutOrder = i, Selectable = true, Parent = grid })
			Ui.corner(b, 12)
			Ui.stroke(b, if sel then C.cyan else C.line, if sel then 0 else 0.88, if sel then 2 else 1)
			Ui.pad(b, 6)
			Ui.list(b, "y", 3)
			local a = if sel and state.a then rgbOf(state.a, def.a) elseif isCur and curE.a then rgbOf(curE.a, def.a) else def.a
			local bb = if sel and state.b then rgbOf(state.b, def.b) elseif isCur and curE.b then rgbOf(curE.b, def.b) else def.b
			local sw = patternSwatch(b, def, a, bb)
			sw.LayoutOrder = 1
			Ui.label(b, def.name .. (if isCur then " ✓" else ""), 12, C.text, F.bold, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
			Ui.label(b, Text.won(Finish.price(kind, id, snap.tierKey, state.room)), 11, C.gold, F.bold, { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 14) })
			Ui.pressable(b)
			b.Activated:Connect(function()
				state.pick = id
				state.a, state.b = nil, nil
				if isCur then
					state.a, state.b = curE.a, curE.b
				end
				redraw()
			end)
		end
		-- colours + apply
		if state.pick then
			local def = Finish.def(kind, state.pick)
			local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), LayoutOrder = 3, Parent = content })
			Ui.list(row, "x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
			local function colorBtn(label: string, which: string, d: { number })
				local cur = rgbOf(if which == "a" then state.a else state.b, d)
				local cb = Ui.button(row, { text = label, auto = true, h = 46, style = "tonal" })
				local dot = Ui.new("Frame", { BackgroundColor3 = Palette.color3(cur), Size = UDim2.new(0, 18, 0, 18), Position = UDim2.new(0, 8, 0.5, -9), Parent = cb })
				Ui.corner(dot, 9)
				cb.Text = "      " .. label
				cb.Activated:Connect(function()
					Picker.color(gui :: ScreenGui, label, cur, function(rgb)
						if which == "a" then
							state.a = Palette.hex(rgb)
						else
							state.b = Palette.hex(rgb)
						end
						redraw()
					end)
				end)
			end
			colorBtn(if def.b then "바탕 색" else "색", "a", def.a)
			if def.b then
				colorBtn("무늬 색", "b", def.b)
			end
			local isSame = curE and curE.p == state.pick
			local full = Finish.price(kind, state.pick, snap.tierKey, state.room)
			local price = if isSame then math.floor(full / 4000 + 0.5) * 1000 else full
			Ui.button(row, { text = "✓ 적용 · " .. Text.won(price), auto = true, h = 46, style = "primary", onClick = function()
				local res = Net.call("finish", { room = state.room, kind = kind, id = state.pick, a = state.a, b = state.b })
				if res.ok then
					fin = res.fin
					snap.fin = res.fin
					S().balance = res.balance
					Ui.toast(Text.fmt(Text.TOAST.finished, if kind == "wall" then "벽" else "바닥", def.name), "good")
					redraw()
					Panels.refresh()
				else
					Ui.toast("❌ " .. res.msg, "bad")
				end
			end })
		end
		if curE then
			Ui.button(content, { text = "↩ 이 방 " .. (if kind == "wall" then "벽" else "바닥") .. "을 원래대로 (무료)", w = UDim2.new(1, 0, 0, 44), style = "ghost", order = 4, onClick = function()
				local res = Net.call("finish", { room = state.room, kind = kind, id = "default" })
				if res.ok then
					fin = res.fin
					snap.fin = res.fin
					state.pick = nil
					redraw()
				else
					Ui.toast("❌ " .. res.msg, "bad")
				end
			end })
		end
		-- the life game's own themes (🛠️ 인테리어) for this room
		local ht = snap.hostThemes and snap.hostThemes[kind]
		local remotes = ReplicatedStorage:FindFirstChild("GwangalliRemotes")
		local homeAction = remotes and remotes:FindFirstChild("HomeAction")
		if ht and homeAction and homeAction:IsA("RemoteEvent") then
			Ui.label(content, "🏠 집 기본 테마 (인테리어 점수에 반영)", 13, C.sub, F.bold, { LayoutOrder = 6 })
			local hrow = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 7, Parent = content })
			Ui.new("UIGridLayout", { CellSize = UDim2.new(0, 132, 0, 40), CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = hrow })
			for i, t in ht do
				local b = Ui.button(hrow, { text = t.name, style = "tonal", size = 12, order = i })
				local dot = Ui.new("Frame", { BackgroundColor3 = Color3.fromRGB(t.color[1], t.color[2], t.color[3]), Size = UDim2.new(0, 10, 1, -12), Position = UDim2.new(0, 6, 0, 6), Parent = b })
				Ui.corner(dot, 4)
				b.Activated:Connect(function()
					Ui.confirm({ gui = gui, title = "집 기본 테마", body = string.format("%s · %s (약 %s, 방에 따라 달라요)", t.name, if kind == "wall" then "벽지" else "바닥", Text.won(t.price)), ok = "적용", onOk = function()
						local ha = homeAction :: RemoteEvent
						ha:FireServer("setTheme", { room = state.room, kind = kind, id = t.id })
						Ui.toast("🏠 집 기본 테마를 요청했어요")
					end })
				end)
			end
		end
	end
	-- room chips + kind tabs
	local roomRow = Ui.new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 42), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 0, LayoutOrder = 1, Selectable = false, Parent = body })
	Ui.list(roomRow, "x", 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local roomSet: { [string]: (boolean) -> () } = {}
	for i, r in rooms do
		local _, set = Ui.chip(roomRow, r.icon .. " " .. r.name, r.id == state.room, function()
			state.room = r.id
			state.pick = nil
			for k, f in roomSet do
				f(k == r.id)
			end
			redraw()
		end, i)
		roomSet[r.id] = set
	end
	local seg = Ui.segmented(body, { { "wall", "🧱 벽" }, { "floor", "🪵 바닥" }, { "light", "💡 조명" } }, "wall", function(k)
		state.kind = k
		state.pick = nil
		roomRow.Visible = k ~= "light"
		redraw()
	end)
	seg.LayoutOrder = 2
	redraw()
end

-------------------------------------------------------------------------------------------------
-- 프리셋
-------------------------------------------------------------------------------------------------
function Panels.presets()
	local snap = ctx.snap
	local m = Ui.modal("💾 배치 프리셋 (이 집 구조 · 3칸)", { gui = gui, w = 560, h = 0.8 })
	local function draw()
		for _, c in m.body:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		Ui.label(m.body, "지금 배치를 저장해 두었다가 언제든 다시 불러와요. 없는 가구는 사서 채우거나 빼고 불러올 수 있어요.", 13, C.sub, F.medium, { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 0 })
		for i = 1, Config.PRESET_SLOTS do
			local pr = snap.presets and snap.presets[i]
			local cardF = Ui.new("Frame", { BackgroundColor3 = C.card, Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, Parent = m.body })
			Ui.corner(cardF, 14)
			Ui.pad(cardF, 12)
			Ui.list(cardF, "y", 8)
			if pr then
				Ui.label(cardF, string.format("%d. %s", i, pr.n), 16, C.text, F.heavy, { LayoutOrder = 1 })
				Ui.label(cardF, string.format("가구 %d개 · %s 저장", pr.count, os.date("%m/%d %H:%M", pr.t)), 12, C.sub, F.medium, { LayoutOrder = 2 })
			else
				Ui.label(cardF, string.format("%d. %s", i, Text.UI.presetEmpty), 16, C.faint, F.heavy, { LayoutOrder = 1 })
			end
			local name = Ui.textbox(cardF, "이름 (예: 여름 바다 테마)", { LayoutOrder = 3 })
			local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 4, Parent = cardF })
			Ui.list(row, "x", 8)
			Ui.button(row, { text = "💾 " .. Text.UI.presetSave, auto = true, h = 44, style = "primary", onClick = function()
				local function go()
					local res = Net.call("preset", { op = "save", slot = i, name = name.Text })
					if res.ok then
						snap.presets = res.presets
						Ui.toast(Text.fmt(Text.TOAST.presetSaved, res.name), "good")
						draw()
					else
						Ui.toast("❌ " .. res.msg, "bad")
					end
				end
				if pr then
					Ui.confirm({ gui = gui, title = "덮어쓰기", body = string.format("'%s'에 지금 배치를 덮어쓸까요?", pr.n), ok = "덮어쓰기", onOk = go })
				else
					go()
				end
			end })
			if pr then
				Ui.button(row, { text = "📥 " .. Text.UI.presetLoad, auto = true, h = 44, style = "tonal", onClick = function()
					local plan = Net.call("preset", { op = "plan", slot = i })
					if not plan.ok then
						Ui.toast("❌ " .. plan.msg, "bad")
						return
					end
					local body = Text.fmt(Text.UI.presetPlan, plan.fromStorage, plan.move, plan.buy, Text.won(plan.cost))
					if plan.finCost > 0 then
						body ..= "\n벽지 · 바닥 · 조명 " .. Text.won(plan.finCost)
					end
					if plan.leftover > 0 then
						body ..= string.format("\n지금 놓인 가구 중 %d개는 창고로 가요", plan.leftover)
					end
					local function load(buy: boolean)
						local res = Net.call("preset", { op = "load", slot = i, buy = buy })
						if res.ok then
							m.close()
							ctx.snap = res
							Editor.resync(res)
							Ui.toast(Text.fmt(Text.TOAST.presetLoaded, res.name, if res.skipped > 0 then string.format(" · %d개는 놓을 수 없어 뺐어요", res.skipped) else ""), "good")
							Panels.refresh()
						else
							Ui.toast("❌ " .. res.msg, "bad")
						end
					end
					if plan.buy > 0 then
						Ui.confirm({ gui = gui, title = "📥 " .. plan.name, body = body .. "\n\n없는 가구도 사서 채울까요?", ok = "🛒 사서 채우기 · " .. Text.won(plan.cost + plan.finCost), cancel = "빼고 불러오기", onOk = function()
							load(true)
						end, onCancel = function()
							load(false)
						end })
					else
						Ui.confirm({ gui = gui, title = "📥 " .. plan.name, body = body, ok = "불러오기", onOk = function()
							load(false)
						end })
					end
				end })
				Ui.button(row, { text = "🗑", w = 50, h = 44, style = "ghost", onClick = function()
					Ui.confirm({ gui = gui, title = "프리셋 지우기", body = string.format("'%s'를 지울까요?", pr.n), ok = "지우기", okStyle = "danger", onOk = function()
						local res = Net.call("preset", { op = "delete", slot = i })
						if res.ok then
							snap.presets = res.presets
							draw()
						end
					end })
				end })
			end
		end
	end
	draw()
end

-------------------------------------------------------------------------------------------------
-- 목표 · 뱃지
-------------------------------------------------------------------------------------------------
function Panels.goals()
	local snap = ctx.snap
	local m = Ui.modal("🏆 인테리어 점수 · 목표 · 뱃지", { gui = gui, w = 560, h = 0.86 })
	local sc = snap.score or { total = 0, grade = "", icon = "", parts = {} }
	local head = Ui.new("Frame", { BackgroundColor3 = C.card, Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = m.body })
	Ui.corner(head, 14)
	Ui.pad(head, 14)
	Ui.list(head, "y", 6)
	Ui.label(head, string.format("⭐ %d점  %s %s", sc.total, sc.icon or "", sc.grade or ""), 22, C.gold, F.heavy, { LayoutOrder = 1 })
	if sc.next then
		Ui.label(head, string.format("다음 등급 '%s'까지 %d점", sc.nextName, sc.next - sc.total), 13, C.sub, F.medium, { LayoutOrder = 2 })
		local bar = Ui.bar(head, sc.total / math.max(1, sc.next), C.gold)
		bar.LayoutOrder = 3
	end
	for i, p in sc.parts or {} do
		Ui.label(head, string.format("· %s  +%d", p.label, p.value), 13, C.text, F.medium, { LayoutOrder = 10 + i, Size = UDim2.new(1, 0, 0, 18) })
	end
	Ui.label(m.body, "🎯 목표 (달성하면 행복 · 인기도 보상)", 15, C.text, F.heavy, { LayoutOrder = 2 })
	for i, g in snap.goals or {} do
		local row = Ui.new("Frame", { BackgroundColor3 = C.card, Size = UDim2.new(1, -4, 0, 62), LayoutOrder = 10 + i, Parent = m.body })
		Ui.corner(row, 12)
		Ui.label(row, string.format("%s %s%s", g.icon, g.name, if g.done then "  ✅" else ""), 14, if g.done then C.green else C.text, F.bold, { Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -24, 0, 20) })
		Ui.label(row, string.format("%d / %d · 보상 %s", g.value, g.target, g.reward), 12, C.sub, F.medium, { Position = UDim2.new(0, 12, 0, 26), Size = UDim2.new(1, -24, 0, 16) })
		local bar = Ui.bar(row, g.value / math.max(1, g.target), if g.done then C.green else C.cyan)
		bar.Position = UDim2.new(0, 12, 1, -14)
		bar.Size = UDim2.new(1, -24, 0, 6)
	end
	Ui.label(m.body, "🏅 뱃지", 15, C.text, F.heavy, { LayoutOrder = 100 })
	local grid = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 101, Parent = m.body })
	Ui.new("UIGridLayout", { CellSize = UDim2.new(0, 120, 0, 92), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, b in snap.badges or {} do
		local got = b.t ~= nil
		local f = Ui.new("Frame", { BackgroundColor3 = if got then C.card2 else C.card, BackgroundTransparency = if got then 0 else 0.4, LayoutOrder = i, Parent = grid })
		Ui.corner(f, 12)
		Ui.label(f, b.icon, 28, if got then C.text else C.faint, F.bold, { Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = if got then 0 else 0.6 })
		Ui.label(f, b.name, 12, if got then C.gold else C.faint, F.bold, { Position = UDim2.new(0, 4, 0, 40), Size = UDim2.new(1, -8, 0, 16), TextXAlignment = Enum.TextXAlignment.Center })
		Ui.label(f, b.desc, 10, C.sub, F.medium, { Position = UDim2.new(0, 4, 0, 56), Size = UDim2.new(1, -8, 0, 32), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top })
	end
end

-------------------------------------------------------------------------------------------------
-- 설정 · 도움말
-------------------------------------------------------------------------------------------------
function Panels.settings()
	local st = S()
	local m = Ui.modal("⚙️ " .. Text.UI.settings, { gui = gui, w = 480, h = 0.78 })
	Ui.label(m.body, Text.UI.grid, 14, C.sub, F.bold, { LayoutOrder = 1 })
	local g = Ui.segmented(m.body, { { 0, "끔" }, { 0.25, "0.25" }, { 0.5, "0.5" }, { 1, "1" } }, st.settings.grid, function(v)
		st.settings.grid = v
		Panels.refreshBar()
	end)
	g.LayoutOrder = 2
	Ui.label(m.body, Text.UI.rot, 14, C.sub, F.bold, { LayoutOrder = 3 })
	local r = Ui.segmented(m.body, { { 15, "15°" }, { 45, "45°" }, { 90, "90°" }, { 1, "미세" } }, st.settings.rot, function(v)
		Editor.setRotStep(v)
	end)
	r.LayoutOrder = 4
	local cut = Ui.toggle(m.body, "🧱 " .. Text.UI.cut, st.settings.cut, function(v)
		Editor.setCut(v)
	end)
	cut.LayoutOrder = 5
	if Config.ALLOW_OVERLAP_TOGGLE then
		local ov = Ui.toggle(m.body, "🧩 " .. Text.UI.overlapOn .. " (가구끼리 겹쳐 놓기)", st.settings.overlap, function(v)
			Editor.setOverlap(v)
		end)
		ov.LayoutOrder = 6
	end
	local mu = Ui.toggle(m.body, "☑ " .. Text.UI.multi .. " (탭으로 여러 개 고르기)", st.multi, function(v)
		Editor.setMulti(v)
	end)
	mu.LayoutOrder = 7
	Ui.label(m.body, "⌨️ " .. Text.UI.keysPC, 12, C.sub, F.medium, { LayoutOrder = 8, AutomaticSize = Enum.AutomaticSize.Y })
	Ui.label(m.body, "🎮 Ⓐ 놓기·선택 · Ⓑ 취소 · Ⓧ/RB 회전 · LB 반대 회전 · ↑↓ 높이 · → 격자 · ← 겹치기 · 왼쪽 스틱 이동 · 오른쪽 스틱 시점 · LT/RT 확대", 12, C.sub, F.medium, { LayoutOrder = 9, AutomaticSize = Enum.AutomaticSize.Y })
	Ui.label(m.body, "📱 한 손가락 끌기 = 시점 / 가구 옮기기 · 두 손가락 = 확대·이동 · 길게 누르기 = 옮기기", 12, C.sub, F.medium, { LayoutOrder = 10, AutomaticSize = Enum.AutomaticSize.Y })
	if not ctx.snap.persistent then
		Ui.label(m.body, Text.UI.notSaved, 13, C.orange, F.bold, { LayoutOrder = 11, AutomaticSize = Enum.AutomaticSize.Y })
	end
end

function Panels.help()
	local m = Ui.modal("❔ 자유 배치 도움말", { gui = gui, w = 520, h = 0.7 })
	Ui.label(m.body, Text.UI.help, 15, C.text, F.medium, { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
	local tips = {
		"🪑 소품은 테이블·선반 위에 올라가요 (쌓기)",
		"🖼️ 벽걸이는 벽에, 💡 천장 조명은 천장에 붙어요",
		"▲▼ / Q·E로 띄워서 공중 선반도 만들 수 있어요",
		"🧩 겹치기 허용을 켜면 가구끼리 겹쳐 놓을 수 있어요",
		"✥ 테이블을 옮기면 위에 놓인 소품도 같이 움직여요",
		"↩ 산 지 10분 안에 빼면 전액 환불돼요",
		"💾 프리셋에 배치를 저장해 두고 언제든 바꿔요",
		"❤️ 친구가 놀러 오면 좋아요와 방명록을 남길 수 있어요",
	}
	for i, t in tips do
		Ui.label(m.body, t, 14, C.sub, F.medium, { LayoutOrder = 1 + i, AutomaticSize = Enum.AutomaticSize.Y })
	end
end

-------------------------------------------------------------------------------------------------
-- Refresh / mount
-------------------------------------------------------------------------------------------------
function Panels.score(view: any)
	ctx.snap.score = view.score or ctx.snap.score
	if view.goals then
		ctx.snap.goals = view.goals
	end
	Panels.refresh()
end

function Panels.refresh()
	if not gui then
		return
	end
	local st = S()
	local counts = Editor.counts()
	local caps = ctx.snap.caps
	refs.score.Text = "⭐ " .. tostring(ctx.snap.score and ctx.snap.score.total or 0)
	refs.money.Text = money()
	refs.count.Text = string.format("🛋️ %d/%d", counts.items, caps.items)
	refs.undo.TextTransparency = if #st.undo > 0 then 0 else 0.6
	refs.redo.TextTransparency = if #st.redo > 0 then 0 else 0.6
	Panels.refreshBar()
end

function Panels.mount(c: any)
	ctx = c
	refs = {}
	gui = Ui.screen("GwangalliDecorPlus", Config.DISPLAY_ORDER)
	;(gui :: ScreenGui):SetAttribute("HideGwangalliHUD", true)
	Ui.scale(gui :: ScreenGui)
	local root = Ui.new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Parent = gui })
	buildTop(root)
	buildCatalog(root)
	buildBar(root)
	if Ui.isGamepad() then
		-- the gamepad aims with the screen centre
		local cross = Ui.label(gui, "⊕", 34, C.cyan, F.bold, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 40, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4 })
		cross.Name = "Crosshair"
	end
	if not ctx.snap.persistent then
		local warnL = Ui.label(root, Text.UI.notSaved, 13, C.orange, F.bold, { Position = UDim2.new(0, 12, 0, 116), Size = UDim2.new(0, 420, 0, 22), TextWrapped = false })
		local _ = warnL
	end
	unsub = Editor.onChange(function(why: string)
		if not gui then
			return
		end
		if why == "close" then
			return
		elseif why == "requestClose" then
			ctx.onClose()
			return
		elseif why == "toggleCatalog" then
			Panels.collapse(not collapsed)
			if not collapsed and Ui.isGamepad() then
				local first = refs.grid and refs.grid:FindFirstChildWhichIsA("TextButton")
				if first then
					GuiService.SelectedObject = first
				end
			elseif collapsed then
				GuiService.SelectedObject = nil
			end
			return
		elseif why == "placed" or why == "removed" or why == "resync" or why == "undo" or why == "redo" then
			if cat == "storage" or why == "resync" then
				fillGrid()
			end
		end
		Panels.refresh()
	end)
	Panels.refresh()
	-- some devices do not fire ViewportSize changes on rotation: poll the orientation too
	do
		local was = Ui.portrait()
		local acc = 0
		local conn: RBXScriptConnection? = nil
		conn = game:GetService("RunService").Heartbeat:Connect(function(dt)
			acc += dt
			if acc < 1 then
				return
			end
			acc = 0
			if not gui or not gui.Parent or not root.Parent then
				if conn then
					conn:Disconnect()
				end
				return
			end
			if Ui.portrait() ~= was then
				was = Ui.portrait()
				for _, ch in root:GetChildren() do
					ch:Destroy()
				end
				refs = {}
				buildTop(root)
				buildCatalog(root)
				buildBar(root)
				Panels.refresh()
			end
		end)
	end
	if Ui.isGamepad() then
		task.defer(function()
			local grid = refs.grid
			local first = grid and grid:FindFirstChildWhichIsA("TextButton")
			if first then
				GuiService.SelectedObject = first
			end
		end)
	end
	-- first time: help
	if not game:GetService("Players").LocalPlayer:GetAttribute("DPHelpSeen") then
		game:GetService("Players").LocalPlayer:SetAttribute("DPHelpSeen", true)
		task.delay(0.6, function()
			if gui then
				Panels.help()
			end
		end)
	end
	local _ = Unit
end

function Panels.unmount()
	if unsub then
		unsub()
		unsub = nil
	end
	if gui then
		gui:Destroy()
	end
	gui = nil
	refs = {}
	GuiService.SelectedObject = nil
end

function Panels.gui(): ScreenGui?
	return gui
end

return Panels
