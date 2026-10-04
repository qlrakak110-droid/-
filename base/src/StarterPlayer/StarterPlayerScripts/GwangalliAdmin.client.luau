-- GwangalliAdmin (client): the OWNER / ADMIN live-config panel (docs/LIVE_UPDATES.md §3).
-- Built only when the server marks this player as an admin (Player attribute GwangalliAdmin); every
-- action is re-checked on the server (ReplicatedStorage.GwangalliLive.Admin), so hiding it is only
-- cosmetic. Normal players never get any of this GUI.
--
--   ⚙️ button (a free spot near the money chip, clear of the thumbstick / jump zones), the chat command
--   /admin, F6, or PlayerGui.GwangalliAdmin.Open:Fire() opens a side sheet (landscape) / bottom sheet
--   (portrait) with tabs:
--     가격 · 알바 · 이벤트 · 월드 · 공지 · 기록
--   Every change is saved + pushed to ALL running servers immediately (version number shown on top);
--   기록 lists the last versions with one-tap rollback.
-- Built with the GwangalliUI kit only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local TAG = "[GwangalliAdmin] "
local player = Players.LocalPlayer

local function requireOptional(name: string, wait: number): any
	local m = ReplicatedStorage:WaitForChild(name, wait)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn(TAG .. name .. " failed to load: " .. tostring(res))
	return nil
end

local LC = requireOptional("GwangalliLiveConfig", 30)
local K = requireOptional("GwangalliUI", 30)
if not LC or not K then
	return
end
local Layout = requireOptional("GwangalliLayout", 10)
local G = requireOptional("GwangalliGameplayShared", 10)
local folder = ReplicatedStorage:WaitForChild(LC.FOLDER, 60)
if not folder then
	return
end
local adminRemote = folder:WaitForChild(LC.REMOTE_ADMIN, 30)
local changedRemote = folder:WaitForChild(LC.REMOTE_CHANGED, 30)
if not adminRemote then
	return
end

-------------------------------------------------------------------------------------------------
-- Server calls
-------------------------------------------------------------------------------------------------
local function call(op: string, args: any?): any
	local ok, res = pcall(function()
		return adminRemote:InvokeServer(op, args)
	end)
	if not ok then
		return { ok = false, err = "서버에 연결하지 못했어요" }
	end
	if type(res) ~= "table" then
		return { ok = false, err = "응답이 없어요" }
	end
	return res
end

local state: any = nil -- last "state" reply {doc, mode, history, owner, happy, serverTime}
local toggle: () -> ()
local ui: any = nil
local render: (string?) -> ()
local busy = false

local function refresh(keepScroll: boolean?)
	local res = call("state")
	if res.ok then
		state = res
	end
	if ui and ui.sheet and ui.sheet.isOpen() then
		render(nil)
		if not keepScroll then
			ui.scroll.CanvasPosition = Vector2.zero
		end
	end
end

local function commit(op: string, args: any?)
	if busy then
		K.toast({ kind = "warn", title = "앞의 변경을 처리 중이에요", duration = 2 })
		return
	end
	busy = true
	local res = call(op, args)
	busy = false
	if res.ok and res.unchanged then
		K.toast({ kind = "info", title = "바뀐 게 없어요", body = "지금 값과 같아요 (v" .. tostring(res.v) .. ")", duration = 2 })
	elseif res.ok then
		K.toast({ kind = "success", title = "적용됨 · v" .. tostring(res.v), body = if state and state.unpublished then "게임에 바로 반영됐어요 (게시 전 테스트)" elseif state and state.mode == "datastore" then "모든 서버에 바로 반영돼요" else "이 서버에 반영 (저장 안 됨)", icon = "✅", duration = 3 })
	else
		K.toast({ kind = "error", title = "적용 안 됨", body = tostring(res.err or "알 수 없는 오류"), duration = 6 })
	end
	refresh(true)
end

-------------------------------------------------------------------------------------------------
-- Small builders
-------------------------------------------------------------------------------------------------
-- Rendering is spread over frames (a few cards per frame) so opening a tab never hitches the game;
-- a newer render (tab switch / refresh) aborts the older one.
local ABORT = {}
local renderToken = 0
local built = 0
local function yieldSometimes()
	built += 1
	if built % 3 == 0 then
		local mine = renderToken
		task.wait()
		if mine ~= renderToken then
			error(ABORT, 0)
		end
	end
end

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function textBox(parent: Instance, props: any): TextBox
	local tb = K.make("TextBox", {
		Name = props.Name or "Input",
		BackgroundColor3 = K.Color.card2,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Text = props.Text or "",
		PlaceholderText = props.PlaceholderText or "",
		PlaceholderColor3 = K.Color.faint,
		TextColor3 = K.Color.text,
		Font = K.Font.medium,
		TextSize = props.TextSize or K.Type.bodySm,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center,
		TextWrapped = props.MultiLine == true,
		MultiLine = props.MultiLine == true,
		TextYAlignment = if props.MultiLine then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
		Size = props.Size or UDim2.fromOffset(110, 44),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
	}, parent)
	K.corner(tb, K.Radius.sm)
	K.stroke(tb, nil, 1, 0.88)
	if props.MultiLine then
		K.pad(tb, 10, 10, 8, 8)
	end
	return tb
end

local function card(parent: Instance, h: number): Frame
	yieldSometimes()
	local c = K.Card(parent, { Size = UDim2.new(1, 0, 0, h), LayoutOrder = nextOrder() })
	return c
end

local function header(parent: Instance, title: string, caption: string?)
	K.SectionHeader(parent, { title = title, caption = caption, order = nextOrder() })
end

local function note(parent: Instance, text: string, color: Color3?)
	local h = K.textHeight(text, K.Type.caption, math.max(200, (ui and ui.scroll.AbsoluteSize.X or 360) - 24)) + 8
	K.text(parent, { Name = "Note", Size = UDim2.new(1, 0, 0, h), Text = text, TextWrapped = true, TextColor3 = color or K.Color.sub, TextSize = K.Type.caption, LayoutOrder = nextOrder() })
end

local function chipRow(parent: Instance, items: { any }, selected: any, onPick: (any) -> ()): Frame
	local row = K.make("ScrollingFrame", {
		Name = "Chips",
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		LayoutOrder = nextOrder(),
	}, parent)
	K.list(row, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local chips = {}
	for i, it in items do
		local chip = K.Chip(row, {
			text = it.label,
			selected = it.id == selected,
			order = i,
			onClick = function()
				for _, c in chips do
					c.set(false)
				end
				chips[i].set(true)
				onPick(it.id)
			end,
		})
		chips[i] = chip
	end
	return row
end

local function rawText(f: any, v: any): string
	if v == nil then
		return ""
	end
	if f.type == "clock" then
		return LC.clockText(v)
	elseif f.type == "clocklist" then
		local parts = {}
		for _, c in v do
			table.insert(parts, LC.clockText(c))
		end
		return table.concat(parts, ", ")
	elseif f.type == "number" then
		return (string.gsub(string.format("%.2f", v), "%.?0+$", ""))
	end
	return tostring(v)
end

-------------------------------------------------------------------------------------------------
-- A settings row for one schema field
-------------------------------------------------------------------------------------------------
local function fieldRow(parent: Instance, f: any)
	local doc = state.doc
	local override = doc.values and doc.values[f.key]
	local value = LC.valueIn(doc, f.key)
	local changed = override ~= nil and not LC.same(override, f.default)
	local sub = "기본 " .. LC.describe(f.key, f.default) .. (if f.hint then " · " .. f.hint else "")
	local isBool = f.type == "bool"
	local isEnum = f.type == "enum"
	local h = if isBool then 64 elseif isEnum then 112 else 110
	local c = card(parent, h)
	K.pad(c, 12, 10, 8, 8)
	local title = K.text(c, { Name = "Title", Size = UDim2.new(1, if isBool then -70 else 0, 0, 20), Text = f.label .. (if changed then "  ●" else ""), Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd })
	if changed then
		title.TextColor3 = K.Color.gold
	end
	K.text(c, { Name = "Sub", Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, if isBool then -70 else 0, 0, 16), Text = sub, TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
	if isBool then
		local tg = K.Toggle(c, {
			value = value == true,
			onChange = function(v: boolean)
				commit("set", { key = f.key, value = v })
			end,
		})
		tg.button.AnchorPoint = Vector2.new(1, 0.5)
		tg.button.Position = UDim2.new(1, 0, 0.5, 0)
		return
	end
	if isEnum then
		local items = {}
		for _, o in f.options do
			table.insert(items, { id = o, label = (f.key == "events.club.themeNight" and LC.THEME_LABELS[o]) or o })
		end
		local holder = K.frame(c, { Name = "EnumHolder", Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 46) })
		local row = chipRow(holder, items, value, function(id: any)
			commit("set", { key = f.key, value = id })
		end)
		row.Position = UDim2.new()
		return
	end
	-- text / number editor: [ value box ][ ✓ ][ ↺ ]
	local line = K.frame(c, { Name = "Editor", Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 44) })
	local hasReset = override ~= nil
	local boxW = -((44 + 6) * (if hasReset then 2 else 1))
	local tb = textBox(line, { Text = rawText(f, value), Size = UDim2.new(1, boxW, 1, 0), PlaceholderText = LC.describe(f.key, f.default), TextXAlignment = Enum.TextXAlignment.Left })
	K.pad(tb, 10, 10, 0, 0)
	local function apply()
		local txt = tb.Text
		if txt == rawText(f, value) then
			return
		end
		commit("set", { key = f.key, value = txt })
	end
	local ok = K.Button(line, { name = "Apply", text = "✓", style = "primary", size = UDim2.fromOffset(44, 44), onClick = apply })
	ok.AnchorPoint = Vector2.new(1, 0)
	ok.Position = UDim2.new(1, if hasReset then -50 else 0, 0, 0)
	tb.FocusLost:Connect(function(enter: boolean)
		if enter then
			apply()
		end
	end)
	if hasReset then
		local rb = K.Button(line, {
			name = "Reset",
			text = "↺",
			style = "secondary",
			size = UDim2.fromOffset(44, 44),
			onClick = function()
				commit("reset", { key = f.key })
			end,
		})
		rb.AnchorPoint = Vector2.new(1, 0)
		rb.Position = UDim2.new(1, 0, 0, 0)
	end
end

-------------------------------------------------------------------------------------------------
-- Tabs
-------------------------------------------------------------------------------------------------
local function statusCard(parent: Instance)
	local c = card(parent, 58)
	K.pad(c, 12, 8, 6, 6)
	local datastore = state.mode == "datastore"
	local modeText = if state.unpublished then (if datastore then "게시 전 테스트 · 이 기기에 저장" else "게시 전 테스트 · 저장 안 됨") elseif datastore then "모든 서버 실시간" else "이 서버만 (저장소 연결 안 됨)"
	K.text(c, { Name = "Mode", Size = UDim2.new(1, -56, 0, 22), Text = string.format("v%d · %s%s", state.doc.version or 0, modeText, if state.happy then " · 🍾 해피아워 중" else ""), Font = K.Font.bold, TextSize = K.Type.bodySm, TextColor3 = if datastore and not state.unpublished then K.Color.green else K.Color.orange, TextTruncate = Enum.TextTruncate.AtEnd })
	local by = state.doc.updatedBy
	local who = if by == 0 then (if (state.doc.version or 0) == 0 then "기본값" else "Open Cloud / 서버") else ("UserId " .. tostring(by))
	K.text(c, { Name = "Last", Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -56, 0, 18), Text = "마지막 변경: " .. (if state.doc.note ~= "" then state.doc.note else "-") .. " · " .. who, TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
	local rb = K.Button(c, {
		name = "Refresh",
		text = "⟳",
		style = "icon",
		onClick = function()
			refresh(true)
		end,
	})
	rb.AnchorPoint = Vector2.new(1, 0.5)
	rb.Position = UDim2.new(1, 0, 0.5, 0)
end

local function groupFields(parent: Instance, group: string)
	for _, f in LC.FIELDS do
		if f.group == group and not f.hidden and not string.match(f.key, "^features%.") then
			fieldRow(parent, f)
		end
	end
end

local function priceTab(body: Instance)
	header(body, "가격", "택시·클럽·월세·집값 (알바비는 '알바' 탭)")
	groupFields(body, "price")
	header(body, "상품 가격 바꾸기", "이름으로 찾아서 가격을 바꿔요")
	if not G or type(G.ITEMS) ~= "table" then
		note(body, "상품 목록을 불러오지 못했어요.")
		return
	end
	local results = K.frame(nil, { Name = "Results", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 0 })
	K.list(results, false, 6)
	local search = K.SearchBar(body, { placeholder = "상품 이름 (예: 아메리카노, 수트)", order = nextOrder() })
	results.LayoutOrder = nextOrder()
	results.Parent = body
	local function fill(q: string)
		for _, ch in results:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		local n = 0
		local ids = {}
		for id in G.ITEMS do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ids do
			local it = G.ITEMS[id]
			local show = (q == "" and state.doc.itemPrices[id] ~= nil) or (q ~= "" and (string.find(it.name or "", q, 1, true) or string.find(id, q, 1, true)))
			if show and n < 12 and not it.hidden then
				n += 1
				local over = state.doc.itemPrices[id]
				local c = K.Card(results, { Size = UDim2.new(1, 0, 0, 104), LayoutOrder = n })
				K.pad(c, 12, 10, 8, 8)
				K.text(c, { Size = UDim2.new(1, 0, 0, 20), Text = tostring(it.name) .. (if over then "  ●" else ""), Font = K.Font.bold, TextColor3 = if over then K.Color.gold else K.Color.text, TextTruncate = Enum.TextTruncate.AtEnd })
				K.text(c, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 16), Text = id .. " · 지금 " .. LC.commas(it.price or 0) .. "원", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
				local line = K.frame(c, { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 44) })
				local tb = textBox(line, { Text = tostring(over or it.price or 0), Size = UDim2.new(1, if over then -100 else -50, 1, 0), TextXAlignment = Enum.TextXAlignment.Left })
				K.pad(tb, 10, 10, 0, 0)
				local okb = K.Button(line, {
					text = "✓",
					style = "primary",
					size = UDim2.fromOffset(44, 44),
					onClick = function()
						local v = tonumber((string.gsub(tb.Text, "[,%s원]", "")))
						if not v then
							K.toast({ kind = "error", title = "숫자로 입력하세요", duration = 3 })
							return
						end
						commit("itemPrice", { id = id, price = math.floor(v + 0.5) })
					end,
				})
				okb.AnchorPoint = Vector2.new(1, 0)
				okb.Position = UDim2.new(1, if over then -50 else 0, 0, 0)
				if over then
					local rb = K.Button(line, {
						text = "↺",
						style = "secondary",
						size = UDim2.fromOffset(44, 44),
						onClick = function()
							commit("itemPrice", { id = id, price = false })
						end,
					})
					rb.AnchorPoint = Vector2.new(1, 0)
					rb.Position = UDim2.new(1, 0, 0, 0)
				end
			end
		end
		if n == 0 then
			K.text(results, { Size = UDim2.new(1, 0, 0, 30), Text = if q == "" then "바꾼 상품 가격이 없어요. 위에서 찾아보세요." else "찾는 상품이 없어요.", TextColor3 = K.Color.faint, TextSize = K.Type.caption, LayoutOrder = 1 })
		end
	end
	search.box:GetPropertyChangedSignal("Text"):Connect(function()
		fill(search.get())
	end)
	fill("")
end

local function jobsTab(body: Instance)
	header(body, "알바비", "배율 2 = 두 배 (전체 배율 × 알바별 배율)")
	groupFields(body, "jobs")
end

local function eventsTab(body: Instance)
	header(body, "지금 시작", "모든 서버에서 몇 초 안에 시작돼요")
	local row = K.frame(body, { Name = "NowButtons", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = nextOrder() })
	local b1 = K.Button(row, {
		text = "드론쇼",
		icon = "🚁",
		style = "primary", -- (a UIGradient tints the label too: keep dark text on gradient buttons)
		size = UDim2.new(0.5, -4, 1, 0),
		onClick = function()
			commit("droneNow")
		end,
	})
	b1.Position = UDim2.new()
	local b2 = K.Button(row, {
		text = "불꽃축제",
		icon = "🎆",
		style = "gold",
		size = UDim2.new(0.5, -4, 1, 0),
		onClick = function()
			commit("fireworksNow")
		end,
	})
	b2.Position = UDim2.new(0.5, 4, 0, 0)
	header(body, "이벤트 설정")
	groupFields(body, "events")
end

local function worldTab(body: Instance)
	header(body, "월드")
	groupFields(body, "world")
	header(body, "이 서버 시계", "각 서버의 시계는 따로 돌아요 (테스트용)")
	chipRow(body, {
		{ id = 7, label = "07:00" },
		{ id = 12, label = "12:00" },
		{ id = 18, label = "18:00" },
		{ id = 19.9, label = "노을" },
		{ id = 21, label = "21:00" },
		{ id = 0, label = "00:00" },
	}, nil, function(h: any)
		commit("setClock", { hour = h })
	end)
	header(body, "기능 켜기/끄기", "점검할 때 끄세요 (택시·클럽 등 해당 스크립트가 읽어요)")
	for _, f in LC.FIELDS do
		if string.match(f.key, "^features%.") then
			fieldRow(body, f)
		end
	end
	if state.owner then
		header(body, "관리자 (게임 주인만)", "UserId를 쉼표로: 이 사람들도 이 패널을 쓸 수 있어요")
		local c = card(body, 64)
		K.pad(c, 10, 10, 10, 10)
		local ids = {}
		for _, id in state.doc.admins or {} do
			table.insert(ids, tostring(id))
		end
		local tb = textBox(c, { Text = table.concat(ids, ", "), Size = UDim2.new(1, -50, 1, 0), PlaceholderText = "예: 12345, 67890", TextXAlignment = Enum.TextXAlignment.Left })
		K.pad(tb, 10, 10, 0, 0)
		local b = K.Button(c, {
			text = "✓",
			style = "primary",
			size = UDim2.fromOffset(44, 44),
			onClick = function()
				local list = {}
				for n in string.gmatch(tb.Text, "%d+") do
					table.insert(list, tonumber(n))
				end
				commit("admins", { list = list })
			end,
		})
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.new(1, 0, 0, 0)
	end
end

local STYLE_ITEMS = {
	{ id = "info", label = "📢 공지" },
	{ id = "event", label = "🎆 이벤트" },
	{ id = "club", label = "🎶 클럽" },
	{ id = "warn", label = "⚠️ 주의" },
	{ id = "update", label = "🔧 업데이트" },
}
local DURATIONS = {
	{ id = 10, label = "10분" },
	{ id = 60, label = "1시간" },
	{ id = 1440, label = "하루" },
	{ id = 10080, label = "1주일" },
}
local EFFECTS = {
	{ id = "happy", label = "😊 행복 +1", effect = { stats = { happiness = 1 } } },
	{ id = "stamina", label = "🔋 체력 +1", effect = { stats = { stamina = 1 } } },
	{ id = "pop", label = "⭐ 인기 +1", effect = { stats = { popularity = 1 } } },
	{ id = "energy", label = "⚡ 달리기 +3 (2분)", effect = { buff = "energy", buffSeconds = 120 } },
}
local draft = { style = "info", minutes = 60, banner = false, text = "", npc = nil :: string?, effect = "happy" }

local function noticeTab(body: Instance)
	header(body, "새 공지", "모든 서버의 모든 플레이어에게 바로 떠요")
	local c = card(body, 96)
	K.pad(c, 8, 8, 8, 8)
	local tb = textBox(c, { Text = draft.text, MultiLine = true, Size = UDim2.fromScale(1, 1), PlaceholderText = "예: 오늘 밤 9시 부산불꽃축제! 해변으로 모여요 🎆\n(첫 줄 = 제목)", TextXAlignment = Enum.TextXAlignment.Left })
	tb:GetPropertyChangedSignal("Text"):Connect(function()
		draft.text = tb.Text
	end)
	chipRow(body, STYLE_ITEMS, draft.style, function(id: any)
		draft.style = id
	end)
	chipRow(body, DURATIONS, draft.minutes, function(id: any)
		draft.minutes = id
	end)
	local bc = card(body, 60)
	K.pad(bc, 12, 8, 6, 6)
	K.text(bc, { Size = UDim2.new(1, -70, 1, 0), Text = "화면 위 띠 배너로도 계속 보여주기", TextSize = K.Type.bodySm })
	local tg = K.Toggle(bc, {
		value = draft.banner,
		onChange = function(v: boolean)
			draft.banner = v
		end,
	})
	tg.button.AnchorPoint = Vector2.new(1, 0.5)
	tg.button.Position = UDim2.new(1, 0, 0.5, 0)
	K.Button(body, {
		text = "모두에게 보내기",
		icon = "📢",
		style = "primary",
		order = nextOrder(),
		onClick = function()
			if (draft.text or "") == "" then
				K.toast({ kind = "warn", title = "공지 내용을 적어 주세요", duration = 3 })
				return
			end
			local text = draft.text
			draft.text = ""
			commit("announce", { text = text, style = draft.style, minutes = draft.minutes, banner = draft.banner })
		end,
	})

	header(body, "지금 나오는 공지")
	local now = state.serverTime or os.time()
	local any = false
	for _, a in state.doc.announcements or {} do
		local active = (a.from == nil or now >= a.from) and (a.to == nil or now < a.to)
		any = true
		local st = LC.ANNOUNCE_STYLES[a.style or "info"] or LC.ANNOUNCE_STYLES.info
		local rc = card(body, 64)
		K.pad(rc, 12, 8, 6, 6)
		K.text(rc, { Size = UDim2.new(1, -60, 0, 20), Text = st.icon .. " " .. (string.gsub(a.text, "\n", " · ")), Font = K.Font.bold, TextTruncate = Enum.TextTruncate.AtEnd })
		local left = if a.to then math.max(0, a.to - now) else nil
		K.text(rc, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, -60, 0, 16), Text = (if active then "노출 중" else (if a.from and now < a.from then "예약" else "끝남")) .. (if left and active then " · " .. K.countdown(left) .. " 남음" else "") .. (if a.banner then " · 배너" else ""), TextColor3 = K.Color.faint, TextSize = K.Type.micro })
		local xb = K.Button(rc, {
			text = "내리기",
			style = "secondary",
			size = UDim2.fromOffset(56, 44),
			textSize = 12,
			onClick = function()
				commit("unannounce", { id = a.id })
			end,
		})
		xb.AnchorPoint = Vector2.new(1, 0.5)
		xb.Position = UDim2.new(1, 0, 0.5, 0)
	end
	if not any then
		note(body, "지금 나오는 공지가 없어요.")
	end

	-- NPC lines
	header(body, "NPC 오늘의 한마디", "대화창 첫 줄에 붙어요 (NPC 스크립트 연결 필요 · 문서 참고)")
	local npcItems = {}
	if G and G.NPC_ORDER then
		for _, id in G.NPC_ORDER do
			local d = G.NPCS[id]
			table.insert(npcItems, { id = id, label = (d and d.name or id) .. (if state.doc.npcLines[id] then " ●" else "") })
		end
	end
	draft.npc = draft.npc or (npcItems[1] and npcItems[1].id)
	local ltb: TextBox? = nil
	chipRow(body, npcItems, draft.npc, function(id: any)
		draft.npc = id
		if ltb then
			ltb.Text = state.doc.npcLines[id] or ""
		end
	end)
	local lineCard = card(body, 64)
	K.pad(lineCard, 10, 10, 10, 10)
	ltb = textBox(lineCard, { Text = (draft.npc and state.doc.npcLines[draft.npc]) or "", Size = UDim2.new(1, -100, 1, 0), PlaceholderText = "예: 오늘은 K-POP 나이트예요!", TextXAlignment = Enum.TextXAlignment.Left })
	K.pad(ltb :: TextBox, 10, 10, 0, 0)
	local sb = K.Button(lineCard, {
		text = "✓",
		style = "primary",
		size = UDim2.fromOffset(44, 44),
		onClick = function()
			if draft.npc then
				commit("npcLine", { id = draft.npc, text = (ltb :: TextBox).Text })
			end
		end,
	})
	sb.AnchorPoint = Vector2.new(1, 0)
	sb.Position = UDim2.new(1, -50, 0, 0)
	local cb = K.Button(lineCard, {
		text = "✕",
		style = "secondary",
		size = UDim2.fromOffset(44, 44),
		onClick = function()
			if draft.npc then
				commit("npcLine", { id = draft.npc, text = "" })
			end
		end,
	})
	cb.AnchorPoint = Vector2.new(1, 0)
	cb.Position = UDim2.new(1, 0, 0, 0)

	-- limited items (phone delivery)
	header(body, "기간 한정 상품", "폰 배달 메뉴에 바로 생겨요 (예: 추석 송편 세트)")
	local form = card(body, 64)
	K.pad(form, 10, 10, 10, 10)
	local ntb = textBox(form, { Text = "", Size = UDim2.new(0.55, -4, 1, 0), PlaceholderText = "이름", TextXAlignment = Enum.TextXAlignment.Left })
	K.pad(ntb, 10, 10, 0, 0)
	local ptb = textBox(form, { Text = "", Size = UDim2.new(0.45, -54, 1, 0), Position = UDim2.new(0.55, 4, 0, 0), PlaceholderText = "가격" })
	chipRow(body, EFFECTS, draft.effect, function(id: any)
		draft.effect = id
	end)
	local ab = K.Button(form, {
		text = "＋",
		style = "primary",
		size = UDim2.fromOffset(44, 44),
		onClick = function()
			local price = tonumber((string.gsub(ptb.Text, "[,%s원]", "")))
			local eff = EFFECTS[1].effect
			for _, e in EFFECTS do
				if e.id == draft.effect then
					eff = e.effect
				end
			end
			if ntb.Text == "" or not price then
				K.toast({ kind = "warn", title = "이름과 가격을 적어 주세요", duration = 3 })
				return
			end
			local id = "live_" .. tostring(os.time() % 100000000)
			commit("catalogAdd", { item = { id = id, name = ntb.Text, price = math.floor(price + 0.5), phone = true, effect = eff, dailyStatLimit = 3 } })
		end,
	})
	ab.AnchorPoint = Vector2.new(1, 0)
	ab.Position = UDim2.new(1, 0, 0, 0)
	for _, it in state.doc.catalog or {} do
		local rc = card(body, 60)
		K.pad(rc, 12, 8, 6, 6)
		K.text(rc, { Size = UDim2.new(1, -64, 0, 20), Text = (it.icon or "🎁") .. " " .. it.name, Font = K.Font.bold, TextTruncate = Enum.TextTruncate.AtEnd })
		K.text(rc, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -64, 0, 16), Text = LC.commas(it.price) .. "원 · " .. (it.desc or ""), TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
		local xb = K.Button(rc, {
			text = "내리기",
			style = "secondary",
			size = UDim2.fromOffset(56, 44),
			textSize = 12,
			onClick = function()
				commit("catalogRemove", { id = it.id })
			end,
		})
		xb.AnchorPoint = Vector2.new(1, 0.5)
		xb.Position = UDim2.new(1, 0, 0.5, 0)
	end
end

local function ago(t: number?): string
	if type(t) ~= "number" or t <= 0 then
		return "-"
	end
	local d = math.max(0, (state.serverTime or os.time()) - t)
	if d < 60 then
		return "방금"
	elseif d < 3600 then
		return math.floor(d / 60) .. "분 전"
	elseif d < 86400 then
		return math.floor(d / 3600) .. "시간 전"
	end
	return math.floor(d / 86400) .. "일 전"
end

local function historyTab(body: Instance)
	header(body, "버전 기록", "최근 " .. LC.HISTORY_MAX .. "개 · 눌러서 그 버전으로 되돌려요 (되돌리기도 새 버전으로 기록)")
	local list = state.history or {}
	local cur = state.doc.version or 0
	for i = #list, 1, -1 do
		local h = list[i]
		local rc = card(body, 60)
		K.pad(rc, 12, 8, 6, 6)
		local isCur = h.v == cur
		K.text(rc, { Size = UDim2.new(1, -76, 0, 20), Text = string.format("v%d%s · %s", h.v, if isCur then " (지금)" else "", if h.note and h.note ~= "" then h.note else "변경"), Font = K.Font.bold, TextColor3 = if isCur then K.Color.green else K.Color.text, TextTruncate = Enum.TextTruncate.AtEnd })
		K.text(rc, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -76, 0, 16), Text = ago(h.at) .. " · " .. (if h.by == 0 then "Open Cloud/서버" else "UserId " .. tostring(h.by)), TextColor3 = K.Color.faint, TextSize = K.Type.micro })
		if not isCur then
			local b = K.Button(rc, {
				text = "되돌리기",
				style = "secondary",
				size = UDim2.fromOffset(70, 44),
				textSize = 12,
				onClick = function()
					K.confirm(ui.gui, {
						title = "v" .. h.v .. "으로 되돌릴까요?",
						body = "모든 서버에 바로 적용돼요. 지금 설정은 기록에 남아서 다시 되돌릴 수 있어요.",
						icon = "⏪",
						confirmText = "되돌리기",
						zIndex = 80,
						onConfirm = function()
							commit("rollback", { version = h.v })
						end,
					})
				end,
			})
			b.AnchorPoint = Vector2.new(1, 0.5)
			b.Position = UDim2.new(1, 0, 0.5, 0)
		end
	end
	if #list == 0 then
		note(body, "아직 바꾼 기록이 없어요.")
	end
	K.Button(body, {
		text = "전부 기본값으로 (v0)",
		style = "danger", -- no gradient: a UIGradient would tint the white label into the background
		order = nextOrder(),
		onClick = function()
			K.confirm(ui.gui, {
				title = "전부 기본값으로 되돌릴까요?",
				body = "가격·이벤트·공지·한정 상품이 모두 게임 기본값으로 돌아가요.",
				icon = "⚠️",
				style = "danger",
				confirmText = "기본값으로",
				zIndex = 80,
				onConfirm = function()
					commit("rollback", { version = 0 })
				end,
			})
		end,
	})
end

local TABS = {
	{ id = "price", label = "가격", fn = priceTab },
	{ id = "jobs", label = "알바", fn = jobsTab },
	{ id = "events", label = "이벤트", fn = eventsTab },
	{ id = "world", label = "월드", fn = worldTab },
	{ id = "notice", label = "공지", fn = noticeTab },
	{ id = "history", label = "기록", fn = historyTab },
}

function render(tabId: string?)
	if not ui or not ui.scroll then
		return
	end
	local id = tabId or ui.tab
	ui.tab = id
	local body = ui.scroll
	for _, ch in body:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	order = 0
	built = 0
	renderToken += 1
	if not state then
		note(body, "설정을 불러오는 중…")
		return
	end
	statusCard(body)
	for _, t in TABS do
		if t.id == id then
			local ok, err = pcall(t.fn, body)
			if not ok then
				if err == ABORT then
					return -- a newer render took over
				end
				warn(TAG .. "tab " .. id .. " failed: " .. tostring(err))
				note(body, "이 탭을 그리지 못했어요: " .. tostring(err), K.Color.red)
			end
		end
	end
	ui.sheet.setTitle("라이브 설정", string.format("v%d · %s", state.doc.version or 0, if state.unpublished then "게시 전 테스트" elseif state.mode == "datastore" then "저장됨 · 모든 서버" else "이 서버만 (저장 안 됨)"))
end

-------------------------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------------------------
local function screenSize(): Vector2
	local cam = workspace.CurrentCamera
	return if cam then cam.ViewportSize else Vector2.new(844, 390)
end

-- The ⚙️ button is not part of the Layout slot contract: try a few spots and take the first one that
-- stays clear of the reserved zones (thumbstick, jump) and of the chips / toasts / tracker / column.
local function overlap(a: any, b: any): number
	local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	return if w > 0 and h > 0 then w * h else 0
end

local function placeButton(btn: GuiObject)
	if not Layout then
		btn.Position = UDim2.fromOffset(8, 60)
		return
	end
	local ok, err = pcall(function()
		local met = Layout.metrics()
		local chips = Layout.rect("topLeftChips")
		local toasts = Layout.rect("toasts")
		local col = Layout.rect("rightColumn")
		local tracker = Layout.rect("topRight")
		local S = 44
		-- reserved zones (never cover) and our own HUD elements (avoid)
		local reserved = {}
		if met.thumb then
			table.insert(reserved, met.thumb)
		end
		if met.jump then
			local j = met.jump
			table.insert(reserved, { x = j.cx - j.r, y = j.cy - j.r, w = 2 * j.r, h = 2 * j.r })
		end
		local blocks = { chips, toasts, col }
		if tracker and tracker.h > 0 then
			table.insert(blocks, tracker)
		end
		-- the announcement banner (GwangalliLive) under the clock chip, while it is shown
		local pg = player:FindFirstChild("PlayerGui")
		local bannerGui = pg and pg:FindFirstChild("GwangalliLiveBanner")
		local bannerFrame = bannerGui and bannerGui:FindFirstChild("Banner")
		if bannerGui and bannerGui:IsA("ScreenGui") and bannerGui.Enabled and bannerFrame and bannerFrame:IsA("GuiObject") then
			local p, sz = bannerFrame.AbsolutePosition, bannerFrame.AbsoluteSize
			table.insert(blocks, { x = p.X, y = p.Y, w = sz.X, h = sz.Y })
		end
		local below = math.max(chips.y + chips.h, toasts.y + toasts.h) + 4
		-- +1: the thumbstick zone is 40 % of the screen width, often a fractional pixel past the rounded rect
		local thumbRight = if met.thumb then met.thumb.x + met.thumb.w + 1 else chips.x
		local candidates = {
			{ x = chips.x, y = chips.y + chips.h + 4 }, -- under the money chip
			{ x = chips.x, y = below }, -- under the toast row
			{ x = thumbRight, y = below }, -- just right of the thumbstick zone
			{ x = thumbRight, y = chips.y + chips.h + 4 },
			{ x = chips.x + chips.w + 4, y = chips.y }, -- right of the chips
			{ x = col.x - 8 - S, y = met.margin or 8 }, -- left of the right column
		}
		local W, H = met.W or 800, met.H or 400
		local best, bestScore = candidates[1], math.huge
		for _, c in candidates do
			local r = { x = c.x, y = c.y, w = S, h = S }
			local score = if r.x < 0 or r.y < 0 or r.x + S > W or r.y + S > H then 1e9 else 0
			for _, z in reserved do
				score += 1000 * overlap(r, z)
			end
			for _, b in blocks do
				score += overlap(r, b)
			end
			if score < bestScore then
				best, bestScore = c, score
			end
			if score == 0 then
				break -- first clear spot wins
			end
		end
		btn.Position = UDim2.fromOffset(best.x, best.y)
	end)
	if not ok then
		warn(TAG .. "placement: " .. tostring(err))
		btn.Position = UDim2.fromOffset(8, 60)
	end
end

-- Character controls are off while the sheet is open on touch screens (the Layout contract: a side
-- sheet covers the jump button), like the phone does.
local function setControls(enabled: boolean)
	local ps = player:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if not (pm and pm:IsA("ModuleScript")) then
		return
	end
	pcall(function()
		local mod = require(pm) :: any
		local controls = mod:GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

local function isOpen(): boolean
	return ui ~= nil and ui.sheet ~= nil and ui.sheet.isOpen()
end

-- The sheet is built on first use (a normal session never pays for it) and rebuilt when the phone
-- was turned since (side sheet in landscape, bottom sheet in portrait).
local function ensureSheet()
	local sz = screenSize()
	local landscape = sz.X >= sz.Y
	if ui.sheet and ui.landscape == landscape then
		return
	end
	if ui.sheet then
		ui.sheet.frame:Destroy()
		if ui.sheet.dim then
			ui.sheet.dim:Destroy()
		end
		ui.sheet = nil
	end
	local gui = ui.gui
	local sheet = K.BottomSheet(gui, {
		name = "AdminSheet",
		title = "라이브 설정",
		subtitle = "불러오는 중…",
		side = if landscape then "right" else "bottom",
		width = math.clamp(math.floor(sz.X * 0.5), 320, 460),
		height = 0.86,
		zIndex = 40,
		onClose = function()
			gui:SetAttribute("HideGwangalliHUD", false)
			if UserInputService.TouchEnabled then
				setControls(true)
			end
		end,
	})
	local content = sheet.content
	local tabs = K.Tabs(content, {
		tabs = TABS,
		value = ui.tab or "price",
		onChange = function(id: string)
			render(id)
			ui.scroll.CanvasPosition = Vector2.zero
		end,
	})
	tabs.frame.Size = UDim2.new(1, 0, 0, 44)
	local scroll = K.make("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = K.Color.faint,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = content.ZIndex,
	}, content)
	K.list(scroll, false, 8)
	K.pad(scroll, 0, 8, 4, 24)
	ui.sheet, ui.tabs, ui.scroll, ui.landscape = sheet, tabs, scroll, landscape
end

function toggle()
	if not ui then
		return
	end
	if isOpen() then
		ui.sheet.close()
	else
		ensureSheet()
		ui.gui:SetAttribute("HideGwangalliHUD", true)
		if UserInputService.TouchEnabled then
			setControls(false)
		end
		ui.button.Visible = false
		ui.sheet.open()
		task.spawn(render, nil) -- the last known state right away (spread over frames) ...
		task.spawn(refresh, false) -- ... replaced by the fresh one when it arrives
	end
end

local function build()
	if ui then
		return
	end
	local pg = player:WaitForChild("PlayerGui", 30)
	if not pg then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GwangalliAdmin"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local btn = K.Button(gui, { name = "AdminToggle", text = "⚙️", style = "glass", size = UDim2.fromOffset(44, 44), textSize = 18 })
	K.stroke(btn, K.Color.gold, 1.5, 0.35)
	placeButton(btn)
	if Layout and Layout.onChanged then
		pcall(Layout.onChanged, function()
			placeButton(btn)
		end)
	end
	-- other client scripts (e.g. a phone "관리자" app) open the panel with PlayerGui.GwangalliAdmin.Open:Fire()
	local openEvent = Instance.new("BindableEvent")
	openEvent.Name = "Open"
	openEvent.Parent = gui
	openEvent.Event:Connect(function()
		if ui and not isOpen() then
			toggle()
		end
	end)
	gui.Parent = pg
	ui = { gui = gui, button = btn, sheet = nil, scroll = nil, tabs = nil, tab = "price" }
	btn.Activated:Connect(function()
		toggle()
	end)
	-- step aside while another full-screen UI (phone, dialog, bowling, home sheet) is up
	task.spawn(function()
		local bannerWas = false
		while ui and ui.gui == gui do
			local bg = pg:FindFirstChild("GwangalliLiveBanner")
			local bannerOn = bg ~= nil and bg:IsA("ScreenGui") and bg.Enabled
			if bannerOn ~= bannerWas then
				bannerWas = bannerOn
				placeButton(btn)
			end
			local other = false
			for _, g in pg:GetChildren() do
				if g ~= gui and g:IsA("ScreenGui") and g.Enabled and g:GetAttribute("HideGwangalliHUD") == true then
					other = true
					break
				end
			end
			if other and isOpen() then
				ui.sheet.close() -- never stack on top of the phone / a dialog / the bowling lane UI
			end
			btn.Visible = not other and not isOpen()
			task.wait(0.5)
		end
	end)
end

local function destroy()
	if ui then
		if isOpen() and UserInputService.TouchEnabled then
			setControls(true)
		end
		ui.gui:Destroy()
		ui = nil
	end
end


local function onFlag()
	if player:GetAttribute(LC.ADMIN_ATTR) == true then
		local ok, err = pcall(build)
		if not ok then
			warn(TAG .. "build failed: " .. tostring(err))
		end
	else
		destroy()
	end
end
player:GetAttributeChangedSignal(LC.ADMIN_ATTR):Connect(onFlag)
onFlag()

-- someone (another admin, Open Cloud, another server) changed the config: refresh an open panel
if changedRemote then
	local pending = false
	changedRemote.OnClientEvent:Connect(function(p: any)
		if type(p) ~= "table" or p.reply or not isOpen() then
			return
		end
		if state and p.v == state.doc.version and not p.happy then
			return
		end
		if not pending then
			pending = true
			task.delay(0.5, function()
				pending = false
				refresh(true)
			end)
		end
	end)
end

-- /admin (chat) and F6 (keyboard) open the panel
pcall(function()
	player.Chatted:Connect(function(msg: string)
		if string.lower(msg) == "/admin" then
			toggle()
		end
	end)
end)
UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
	if not gp and input.KeyCode == Enum.KeyCode.F6 then
		toggle()
	end
end)
