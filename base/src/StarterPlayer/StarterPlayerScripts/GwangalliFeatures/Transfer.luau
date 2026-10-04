-- GwangalliFeatures/Transfer (owner: money): Korean mobile-banking style money flows.
--   transfer   송금: 받는 사람 (근처 60 studs / 친구·최근 / 전체 + 이름 검색) -> 금액 키패드 (+1만 / +5만 /
--              +10만 / 전액, live balance + 1일 한도 checks) -> 확인 (받는 분, 계좌, 수수료 0원, 송금 후 잔액,
--              메모 chips or free text, "취소할 수 없어요") -> 꾹 눌러서 보내기 (0.8 s) -> 완료 (check, confetti,
--              balance count-down)
--   request    송금 요청 (same picker / keypad, "요청 보내기")
--   requests   받은 요청 / 보낸 요청 (보내기 = transfer pre-filled, 거절, 취소)
--   statement  거래내역 grouped by day (전체 / 통장 / 현금), tap a row for the receipt
-- Incoming money requests show an interactive banner (FK.incoming). Server: BankRequest / BankEvent
-- (GwangalliGameplay/Bank.luau). Built with the GwangalliUI kit via FeatureKit.

local Players = game:GetService("Players")

local M = {}
M.flows = { "transfer", "request", "requests", "statement" }

local F: any
local K: any
local G: any
local FK: any
local flow: any

local player = Players.LocalPlayer

local BANK = {
	minTransfer = 1000,
	maxTransfer = 1000000,
	dailyLimit = 3000000,
	nearbyRadius = 60,
	account = "110-***-4567",
	bankName = "BNK부산은행",
}
local PRESET_ORDER = { "rice", "coffee", "taxi", "club", "split", "thanks", "allowance", "rent" }
local PRESETS = { rice = "밥값 🍚", coffee = "커피값 ☕", taxi = "택시비 🚕", club = "클럽 🎶", split = "N빵 🧾", thanks = "고마워 💛", allowance = "용돈 💸", rent = "월세 🏠" }

-- flow state
local st: any = {
	mode = "transfer", -- transfer | request
	target = nil, -- {u, n, un}
	amount = 0,
	preset = nil,
	memo = nil,
	requestId = nil,
	locked = false,
	summary = nil,
	returnTo = nil,
	busy = false,
}

local friendCache: { [number]: boolean } = {}
local incomingCards: { [string]: any } = {}

local function nameFor(userId: number, fallback: string?): string
	local p = Players:GetPlayerByUserId(userId)
	if p then
		return if p.DisplayName ~= "" then p.DisplayName else p.Name
	end
	return fallback or "알 수 없음"
end

local function myRoot(): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function distanceTo(userId: number): number?
	local p = Players:GetPlayerByUserId(userId)
	local me = myRoot()
	local ch = p and p.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	if me and r and r:IsA("BasePart") then
		return (r.Position - me.Position).Magnitude
	end
	return nil
end

local function particle(name: string): string
	-- 님에게 / 님이 are used everywhere, so the particle never depends on the last syllable
	return name .. "님"
end

-------------------------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------------------------
local function buildPick(frame: Frame, fl: any): any
	local tab = "near"
	local query = ""
	local data: any = nil
	local loading = false
	local top = K.frame(frame, { Name = "Top", ZIndex = 23 })
	local seg = K.Segmented(top, {
		items = { { id = "near", label = "📍 근처" }, { id = "friends", label = "⭐ 친구·최근" }, { id = "all", label = "👥 전체" } },
		value = "near",
		onChange = function(id: string)
			tab = id
			M._renderPick()
		end,
	})
	local search = K.SearchBar(top, {
		placeholder = "이름으로 찾기",
		onChange = function(t: string)
			query = string.lower(t or "")
			if query ~= "" and tab ~= "all" then
				tab = "all"
				seg.set("all", true)
			end
			M._renderPick()
		end,
	})
	local status = K.text(frame, { Name = "Status", Size = UDim2.new(1, -24, 0, 16), Text = "", TextColor3 = K.Color.faint, TextSize = K.Type.micro, ZIndex = 24 })
	local listHost = K.frame(frame, { Name = "ListHost", ZIndex = 23 })
	local scroll, content = FK.scroll(listHost, "List")

	local function row(e: any, order: number, sub: string, dim: boolean?)
		local r = K.ListRow(content, {
			name = "Person_" .. tostring(e.u),
			title = e.n,
			subtitle = sub,
			chevron = not dim,
			height = 58,
			order = order,
			onClick = if dim then nil else function()
				st.target = { u = e.u, n = e.n, un = e.un }
				fl.go("amount", {})
			end,
		})
		local av = FK.avatar(r.row, 38, e.u, e.n)
		av.AnchorPoint = Vector2.new(0, 0.5)
		av.Position = UDim2.new(0, 10, 0.5, 0)
		r.title.Position = UDim2.new(0, 60, 0, 58 / 2 - 19)
		r.subtitle.Position = UDim2.new(0, 60, 0, 58 / 2 + 1)
		r.title.Size = UDim2.new(1, -96, 0, 20)
		r.subtitle.Size = UDim2.new(1, -96, 0, 17)
		if dim then
			r.row.BackgroundTransparency = 0.5
			r.title.TextTransparency = 0.45
			r.subtitle.TextTransparency = 0.3
			av.BackgroundTransparency = 0.5
		end
		return r
	end

	function M._renderPick()
		FK.clear(content)
		if loading and not data then
			K.Skeleton(content, { order = 1, rows = 4, rowHeight = 58 })
			status.Text = "사람들을 찾는 중…"
			return
		end
		if not data then
			K.EmptyState(content, { order = 1, compact = true, icon = "📡", title = "연결이 원활하지 않아요", body = "잠시 후 다시 열어 주세요" })
			status.Text = ""
			return
		end
		local order = 0
		local shown = 0
		if tab == "near" then
			local list = {}
			for _, e in data.players do
				local d = distanceTo(e.u)
				if d and d <= BANK.nearbyRadius then
					table.insert(list, { e = e, d = d })
				end
			end
			table.sort(list, function(a, b)
				return a.d < b.d
			end)
			for _, x in list do
				order += 1
				shown += 1
				row(x.e, order, "@" .. x.e.un .. " · " .. FK.distText(x.d) .. (if friendCache[x.e.u] then " · 친구" else ""))
			end
			status.Text = string.format("내 주변 %s 안 · %d명", K.meters(BANK.nearbyRadius), shown)
			if shown == 0 then
				K.EmptyState(content, { order = 1, compact = true, icon = "📍", title = "근처에 아무도 없어요", body = "가까이 가거나 '전체' 탭에서 찾아보세요" })
			end
		elseif tab == "friends" then
			local seen: { [number]: boolean } = {}
			if #data.recent > 0 then
				order += 1
				K.SectionHeader(content, { title = "최근 보낸 사람", order = order })
				for _, r in data.recent do
					seen[r.u] = true
					order += 1
					shown += 1
					local sub = string.format("최근 %s · %s", K.wonShort(r.a or 0), FK.ago(r.t or 0))
					if not r.online then
						sub = "지금 이 서버에 없어요 · " .. sub
					end
					row({ u = r.u, n = r.n, un = r.n }, order, sub, not r.online)
				end
			end
			local friends = {}
			for _, e in data.players do
				if friendCache[e.u] and not seen[e.u] then
					table.insert(friends, e)
				end
			end
			if #friends > 0 then
				order += 1
				K.SectionHeader(content, { title = "이 서버의 친구", order = order })
				for _, e in friends do
					order += 1
					shown += 1
					local d = distanceTo(e.u)
					row(e, order, "@" .. e.un .. (if d then " · " .. FK.distText(d) else ""))
				end
			end
			status.Text = "최근 보낸 사람과 같은 서버의 Roblox 친구"
			if shown == 0 then
				K.EmptyState(content, { order = 1, compact = true, icon = "⭐", title = "아직 보낸 사람이 없어요", body = "근처나 전체 탭에서 받는 사람을 골라 보세요" })
			end
		else
			for _, e in data.players do
				local hay = string.lower(e.n .. " " .. e.un)
				if query == "" or string.find(hay, query, 1, true) then
					order += 1
					shown += 1
					local d = distanceTo(e.u)
					row(e, order, "@" .. e.un .. (if d then " · " .. FK.distText(d) else " · 멀리 있어요") .. (if e.blocked then " · 차단됨" else ""))
				end
			end
			status.Text = string.format("이 서버 · %d명", shown)
			if shown == 0 then
				if query ~= "" then
					K.EmptyState(content, { order = 1, compact = true, icon = "🔍", title = "'" .. query .. "' 검색 결과가 없어요", body = "같은 서버에 있는 사람에게만 보낼 수 있어요" })
				else
					K.EmptyState(content, { order = 1, compact = true, icon = "👥", title = "이 서버에 다른 사람이 없어요", body = "친구를 초대하면 바로 송금할 수 있어요" })
				end
			end
		end
		local rows = {}
		for _, c in content:GetChildren() do
			if c:IsA("GuiButton") then
				table.insert(rows, c)
			end
		end
		K.stagger(rows, K.Color.glass2)
	end

	local function checkFriends()
		if not data then
			return
		end
		task.spawn(function()
			local changed = false
			for _, e in data.players do
				if friendCache[e.u] == nil then
					local ok, res = pcall(player.IsFriendsWith, player, e.u)
					friendCache[e.u] = ok and res == true
					changed = changed or friendCache[e.u]
				end
			end
			if changed and fl.current() == "pick" then
				M._renderPick()
			end
		end)
	end

	local page = { title = "누구에게 보낼까요?", subtitle = "같은 서버에 있는 사람에게 바로 보내요" }
	function page.layout(wide: boolean, w: number, h: number)
		local pad = 12
		if wide then
			top.Position = UDim2.fromOffset(pad, 2)
			top.Size = UDim2.fromOffset(w - pad * 2, 50)
			seg.frame.Position = UDim2.fromOffset(0, 0)
			seg.frame.Size = UDim2.new(0.56, -4, 0, 50)
			search.frame.Position = UDim2.new(0.56, 4, 0, 3)
			search.frame.Size = UDim2.new(0.44, -4, 0, 44)
			status.Position = UDim2.fromOffset(pad + 2, 56)
			listHost.Position = UDim2.fromOffset(pad, 74)
			listHost.Size = UDim2.fromOffset(w - pad * 2, h - 78)
		else
			top.Position = UDim2.fromOffset(pad, 2)
			top.Size = UDim2.fromOffset(w - pad * 2, 100)
			seg.frame.Position = UDim2.fromOffset(0, 0)
			seg.frame.Size = UDim2.new(1, 0, 0, 50)
			search.frame.Position = UDim2.fromOffset(0, 56)
			search.frame.Size = UDim2.new(1, 0, 0, 44)
			status.Position = UDim2.fromOffset(pad + 2, 106)
			listHost.Position = UDim2.fromOffset(pad, 124)
			listHost.Size = UDim2.fromOffset(w - pad * 2, h - 128)
		end
		status.Size = UDim2.fromOffset(w - pad * 2, 16)
	end
	function page.show(_args: any)
		page.title = if st.mode == "request" then "누구에게 요청할까요?" else "누구에게 보낼까요?"
		page.subtitle = "같은 서버에 있는 사람만 · 근처 " .. K.meters(BANK.nearbyRadius)
		fl.setTitle(page.title, page.subtitle)
		search.clear()
		query = ""
		loading = true
		M._renderPick()
		task.spawn(function()
			local r = FK.call("recipients", {})
			loading = false
			data = if r.ok then r else nil
			if data then
				-- default tab: nearby when someone is near, else recent / all
				local anyNear = false
				for _, e in data.players do
					local d = distanceTo(e.u)
					if d and d <= BANK.nearbyRadius then
						anyNear = true
						break
					end
				end
				if not anyNear then
					tab = if #data.recent > 0 then "friends" else "all"
					seg.set(tab, true)
				end
			end
			M._renderPick()
			checkFriends()
		end)
	end
	function page.resume()
		M._renderPick()
	end
	scroll.Name = "People"
	return page
end

local function buildAmount(frame: Frame, fl: any): any
	local panes = FK.panes(frame, 0.5)
	local A, B = panes.a, panes.b
	local chip = K.Card(A, { Name = "To", Size = UDim2.new(1, 0, 0, 48), ZIndex = 24 })
	local chipAv: Frame? = nil
	local chipName = K.text(chip, { Name = "Name", Position = UDim2.fromOffset(52, 6), Size = UDim2.new(1, -60, 0, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
	local chipSub = K.text(chip, { Name = "Sub", Position = UDim2.fromOffset(52, 25), Size = UDim2.new(1, -60, 0, 16), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
	local amountV = FK.amountView(A, { height = 68 })
	local info = K.text(A, { Name = "Info", Size = UDim2.new(1, 0, 0, 16), Text = "", TextColor3 = K.Color.faint, TextSize = K.Type.micro, ZIndex = 24, TextTruncate = Enum.TextTruncate.AtEnd })
	local chipsRow = K.frame(A, { Name = "Quick", Size = UDim2.new(1, 0, 0, 44), ZIndex = 24 })
	K.list(chipsRow, true, 6)
	local nextBtn: TextButton
	local keypadHost = K.frame(B, { Name = "PadHost", ZIndex = 24 })

	local function limits(): (number, number, number)
		local s = st.summary
		local bank = if s then s.bank else math.huge
		local remaining = if s then s.remaining else BANK.dailyLimit
		local maxT = if s then s.max else BANK.maxTransfer
		return bank, remaining, maxT
	end

	local function validate(): boolean
		local n = st.amount
		local bank, remaining, maxT = limits()
		local ok = false
		if n <= 0 then
			amountV.setHint(if st.mode == "request" then "받을 금액을 입력해 주세요" else "보낼 금액을 입력해 주세요", K.Color.sub)
		elseif n < BANK.minTransfer then
			amountV.setHint("1,000원부터 " .. (if st.mode == "request" then "요청" else "보낼") .. "할 수 있어요", K.Color.orange)
		elseif n > maxT then
			amountV.setHint("한 번에 최대 " .. K.wonShort(maxT) .. "까지 가능해요", K.Color.red)
		elseif st.mode == "transfer" and n > bank then
			amountV.setHint("잔액이 부족해요 · 통장 " .. K.won(bank), K.Color.red)
		elseif st.mode == "transfer" and n > remaining then
			amountV.setHint("오늘 남은 이체 한도는 " .. K.won(remaining) .. "이에요", K.Color.red)
		else
			amountV.setHint(FK.koreanWon(n), K.Color.cyan)
			ok = true
		end
		K.setButtonEnabled(nextBtn, ok)
		return ok
	end

	local function setAmount(n: number, pop: boolean?)
		st.amount = math.max(0, math.floor(n))
		amountV.set(st.amount, pop)
		validate()
	end

	for i, def in { { "+1만", 10000 }, { "+5만", 50000 }, { "+10만", 100000 }, { "전액", -1 } } do
		K.Chip(chipsRow, {
			name = "Q" .. i,
			text = def[1],
			order = i,
			minWidth = 56,
			onClick = function()
				if def[2] < 0 then
					local bank, remaining, maxT = limits()
					if st.mode == "request" then
						return
					end
					setAmount(math.max(0, math.min(bank, remaining, maxT)), true)
				else
					local n = st.amount + def[2]
					local _, _, maxT = limits()
					if n > maxT then
						n = maxT
						FK.shake(amountV.label, 5)
					end
					setAmount(n, true)
				end
			end,
		})
	end

	local pad = FK.keypad(keypadHost, {
		onKey = function(k: string)
			if k == "back" then
				setAmount(st.amount // 10, false)
			elseif k == "clear" then
				setAmount(0, false)
			else
				local s = (if st.amount > 0 then tostring(st.amount) else "") .. k
				local n = tonumber(s) or 0
				if n > 99999999 then
					amountV.error("금액이 너무 커요")
					return
				end
				setAmount(n, true)
			end
		end,
	})

	nextBtn = K.Button(frame, {
		name = "Next",
		text = "다음",
		style = "primary",
		zIndex = 25,
		onClick = function()
			if validate() then
				fl.go("confirm", {})
			else
				amountV.error(amountV.hint.Text)
			end
		end,
	})

	local page = { title = "얼마를 보낼까요?", subtitle = "" }
	function page.layout(wide: boolean, w: number, h: number)
		local p = 12
		if wide then
			panes.layout(true, w, h, 0)
			local aw = A.Size.X.Offset
			chip.Position = UDim2.fromOffset(0, 2)
			amountV.frame.Position = UDim2.fromOffset(4, 60)
			info.Position = UDim2.fromOffset(4, 128)
			chipsRow.Position = UDim2.fromOffset(0, 148)
			nextBtn.Size = UDim2.fromOffset(aw, 48)
			nextBtn.Position = UDim2.fromOffset(p, h - p - 48)
			keypadHost.Position = UDim2.fromOffset(0, 0)
			keypadHost.Size = UDim2.new(1, 0, 1, 0)
			pad.layout(B.Size.X.Offset, B.Size.Y.Offset)
		else
			panes.layout(false, w, h, 200)
			chip.Position = UDim2.fromOffset(0, 2)
			amountV.frame.Position = UDim2.fromOffset(4, 58)
			info.Position = UDim2.fromOffset(4, 128)
			chipsRow.Position = UDim2.fromOffset(0, 148)
			nextBtn.Size = UDim2.fromOffset(w - p * 2, 48)
			nextBtn.Position = UDim2.fromOffset(p, h - p - 48)
			local bh = B.Size.Y.Offset - 60
			keypadHost.Position = UDim2.fromOffset(0, 0)
			keypadHost.Size = UDim2.new(1, 0, 0, bh)
			pad.layout(B.Size.X.Offset, bh)
		end
	end
	function page.show(args: any)
		local t = st.target
		page.title = if st.mode == "request" then "얼마를 요청할까요?" else "얼마를 보낼까요?"
		page.subtitle = if st.mode == "request" then "받을 금액" else "수수료 0원 · 계좌이체"
		fl.setTitle(page.title, page.subtitle)
		if chipAv then
			chipAv:Destroy()
		end
		chipAv = FK.avatar(chip, 36, t and t.u, t and t.n)
		local av = chipAv :: Frame
		av.AnchorPoint = Vector2.new(0, 0.5)
		av.Position = UDim2.new(0, 8, 0.5, 0)
		chipName.Text = (if t then particle(t.n) else "") .. (if st.mode == "request" then "에게 요청" else "에게")
		chipSub.Text = if t and t.un then "@" .. t.un else ""
		setAmount(tonumber(args.amount) or 0, false)
		info.Text = "잔액 확인 중…"
		task.spawn(function()
			local s = FK.call("summary", {})
			if s.ok then
				st.summary = s
				info.Text = if st.mode == "request" then string.format("요청은 5분 동안 유효해요 · 최대 %s", K.wonShort(s.max)) else string.format("내 통장 %s · 오늘 남은 한도 %s%s", K.won(s.bank), K.won(s.remaining), if s.limited then " (한도제한계좌)" else "")
				validate()
			else
				info.Text = s.message
			end
		end)
	end
	return page
end

local function buildConfirm(frame: Frame, fl: any): any
	local panes = FK.panes(frame, 0.42)
	local A, B = panes.a, panes.b
	local hero = K.frame(A, { Name = "Hero", Size = UDim2.fromScale(1, 1), ZIndex = 24 })
	local heroAv: Frame? = nil
	local toLine = K.text(hero, { Name = "To", Size = UDim2.new(1, 0, 0, 20), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.body, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
	local amountL = K.text(hero, { Name = "Amount", Size = UDim2.new(1, 0, 0, 36), Text = "", Font = K.Font.bold, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25 })
	K.mono(amountL)
	local ask = K.text(hero, { Name = "Ask", Size = UDim2.new(1, 0, 0, 20), Text = "보낼까요?", TextColor3 = K.Color.text, TextSize = K.Type.body, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25 })
	local reading = K.text(hero, { Name = "Reading", Size = UDim2.new(1, 0, 0, 16), Text = "", TextColor3 = K.Color.faint, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25 })

	local scroll, content = FK.scroll(B, "Details")
	local details = K.Card(content, { Name = "Details", Size = UDim2.new(1, 0, 0, 4 * 26 + 12), LayoutOrder = 1, ZIndex = 24 })
	K.pad(details, 12, 12, 6, 6)
	K.list(details, false, 0)
	local detailVals: { [string]: TextLabel } = {}
	for i, key in { "받는 분", "보내는 계좌", "수수료", "송금 후 잔액" } do
		local r = K.frame(details, { Name = "D" .. i, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, ZIndex = 25 })
		K.text(r, { Name = "Label", Size = UDim2.new(0.4, 0, 1, 0), Text = key, TextColor3 = K.Color.sub, TextSize = K.Type.caption, ZIndex = 25 })
		local v = K.text(r, { Name = "Value", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.6, 0, 1, 0), Text = "", Font = K.Font.bold, TextSize = K.Type.caption + 1, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
		detailVals[key] = v
	end
	local memoHead = K.text(content, { Name = "MemoHead", Size = UDim2.new(1, 0, 0, 18), Text = "메모 (받는 분에게 보여요)", TextColor3 = K.Color.sub, TextSize = K.Type.caption, LayoutOrder = 2, ZIndex = 24 })
	local memoRow = K.make("ScrollingFrame", { Name = "MemoChips", Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, LayoutOrder = 3, ZIndex = 24 }, content)
	K.list(memoRow, true, 6)
	local memoBox = K.make("TextBox", { Name = "MemoBox", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = K.Color.card, BorderSizePixel = 0, Text = "", PlaceholderText = "직접 입력 (최대 20자)", PlaceholderColor3 = K.Color.faint, TextColor3 = K.Color.text, TextSize = K.Type.bodySm, Font = K.Font.medium, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 4, Visible = false, ZIndex = 24 }, content)
	K.corner(memoBox, K.Radius.sm)
	K.pad(memoBox, 12, 12, 0, 0)
	K.stroke(memoBox, nil, 1, 0.88)
	local warnL = K.text(frame, { Name = "Warn", Size = UDim2.new(1, 0, 0, 18), Text = "⚠️ 보낸 뒤에는 취소할 수 없어요 · 받는 분 이름을 꼭 확인해 주세요", TextColor3 = K.Color.orange, TextSize = K.Type.caption, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
	local errL = K.text(content, { Name = "Error", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = "", TextColor3 = K.Color.red, TextSize = K.Type.caption, TextWrapped = true, LayoutOrder = 6, Visible = false, ZIndex = 24 })

	local memoChips: { [string]: any } = {}
	local customChip: any = nil
	local function selectPreset(id: string?)
		st.preset = id
		for pid, c in memoChips do
			c.set(pid == id)
		end
		if customChip then
			customChip.set(id == "custom")
		end
		memoBox.Visible = id == "custom"
		if id == "custom" then
			task.defer(function()
				pcall(function()
					memoBox:CaptureFocus()
				end)
			end)
		end
	end
	for i, id in PRESET_ORDER do
		memoChips[id] = K.Chip(memoRow, {
			name = "Memo_" .. id,
			text = PRESETS[id],
			order = i,
			onClick = function()
				selectPreset(if st.preset == id then nil else id)
			end,
		})
	end
	customChip = K.Chip(memoRow, { name = "Memo_custom", text = "✏️ 직접 입력", order = 99, onClick = function()
		selectPreset(if st.preset == "custom" then nil else "custom")
	end })
	memoBox:GetPropertyChangedSignal("Text"):Connect(function()
		local t = memoBox.Text
		if utf8.len(t) and (utf8.len(t) :: number) > 20 then
			local cut = utf8.offset(t, 21)
			if cut then
				memoBox.Text = string.sub(t, 1, cut - 1)
			end
		end
	end)

	local hold: any
	local reqBtn: TextButton
	local function showError(msg: string)
		errL.Text = "⛔ " .. msg
		errL.Visible = true
		FK.shake(errL, 6)
		K.feedback("error")
	end

	local function send()
		if st.busy then
			return
		end
		st.busy = true
		errL.Visible = false
		local payload: { [string]: any } = { to = st.target.u, amount = st.amount, rid = FK.rid() }
		if st.requestId then
			payload.requestId = st.requestId
		end
		if st.preset and st.preset ~= "custom" and not st.locked then
			payload.preset = st.preset
		elseif st.preset == "custom" and memoBox.Text ~= "" then
			payload.memo = memoBox.Text
		end
		local before = if st.summary then st.summary.bank else nil
		local op = if st.mode == "request" then "request" else "transfer"
		local r = FK.call(op, payload, 12)
		st.busy = false
		if r.ok then
			if st.requestId then
				FK.dismissIncoming("req_" .. st.requestId)
			end
			fl.replace("done", { result = r, before = before, mode = st.mode, target = st.target })
		else
			if hold then
				hold.reset()
			end
			K.setButtonLoading(reqBtn, false)
			showError(r.message or "보내지 못했어요")
			if r.code == "offline" or r.code == "blocked" then
				task.delay(1.4, function()
					if fl.current() == "confirm" and not st.locked then
						fl.back()
						fl.back()
					end
				end)
			end
		end
	end

	hold = FK.holdButton(frame, { name = "HoldSend", text = "꾹 눌러서 보내기", holdText = "계속 누르면 보내져요…", doneText = "보내는 중…", duration = 0.8, onComplete = send })
	reqBtn = K.Button(frame, { name = "SendRequest", text = "요청 보내기", style = "primary", zIndex = 25, onClick = function()
		K.setButtonLoading(reqBtn, true, "보내는 중…")
		send()
	end })

	local page = { title = "보내기 전에 확인해요", subtitle = "" }
	local lastWide = false
	function page.layout(wide: boolean, w: number, h: number)
		lastWide = wide
		local p = 12
		local btnH = 52
		local warnH = if warnL.Visible then 22 else 0
		if wide then
			panes.layout(true, w, h - btnH - p - warnH, 0)
			hero.Size = UDim2.fromScale(1, 1)
			local ah = A.Size.Y.Offset
			local y0 = math.max(0, math.floor(ah / 2 - 100))
			if heroAv then
				heroAv.Position = UDim2.new(0.5, 0, 0, y0)
			end
			toLine.Position = UDim2.fromOffset(0, y0 + 76)
			amountL.Position = UDim2.fromOffset(0, y0 + 98)
			ask.Position = UDim2.fromOffset(0, y0 + 136)
			reading.Position = UDim2.fromOffset(0, y0 + 160)
			local bw = B.Size.X.Offset
			hold.button.Size = UDim2.fromOffset(bw, btnH)
			hold.button.Position = UDim2.fromOffset(B.Position.X.Offset, h - p - btnH)
			reqBtn.Size = hold.button.Size
			reqBtn.Position = hold.button.Position
			warnL.Size = UDim2.fromOffset(bw, 18)
			warnL.Position = UDim2.fromOffset(B.Position.X.Offset, h - p - btnH - 21)
		else
			panes.layout(false, w, h - btnH - p - warnH, 176)
			hero.Size = UDim2.fromScale(1, 1)
			if heroAv then
				heroAv.Position = UDim2.new(0.5, 0, 0, 2)
			end
			toLine.Position = UDim2.fromOffset(0, 70)
			amountL.Position = UDim2.fromOffset(0, 90)
			ask.Position = UDim2.fromOffset(0, 126)
			reading.Position = UDim2.fromOffset(0, 148)
			hold.button.Size = UDim2.fromOffset(w - p * 2, btnH)
			hold.button.Position = UDim2.fromOffset(p, h - p - btnH)
			reqBtn.Size = hold.button.Size
			reqBtn.Position = hold.button.Position
			warnL.Size = UDim2.fromOffset(w - p * 2, 18)
			warnL.Position = UDim2.fromOffset(p, h - p - btnH - 21)
		end
	end
	function page.show(_args: any)
		local t = st.target
		local req = st.mode == "request"
		page.title = if st.locked then "송금 요청에 답하기" elseif req then "요청 보내기 전에 확인해요" else "보내기 전에 확인해요"
		page.subtitle = if req then "상대방 폰으로 요청이 가요" else "계좌이체 · 수수료 0원"
		fl.setTitle(page.title, page.subtitle)
		if heroAv then
			heroAv:Destroy()
		end
		heroAv = FK.avatar(hero, 64, t.u, t.n)
		local av = heroAv :: Frame
		av.AnchorPoint = Vector2.new(0.5, 0)
		toLine.Text = particle(t.n) .. (if req then "에게" else "에게")
		amountL.Text = K.won(st.amount)
		ask.Text = if req then "요청할까요?" else "보낼까요?"
		reading.Text = FK.koreanWon(st.amount)
		detailVals["받는 분"].Text = t.n .. (if t.un and t.un ~= t.n then " (@" .. t.un .. ")" else "")
		detailVals["보내는 계좌"].Text = BANK.bankName .. " " .. BANK.account
		detailVals["수수료"].Text = "0원 (면제)"
		detailVals["수수료"].TextColor3 = K.Color.green
		if req then
			detailVals["송금 후 잔액"].Parent.Visible = false
			detailVals["보내는 계좌"].Text = "받을 계좌 · " .. BANK.account
			details.Size = UDim2.new(1, 0, 0, 3 * 26 + 12)
		else
			detailVals["송금 후 잔액"].Parent.Visible = true
			details.Size = UDim2.new(1, 0, 0, 4 * 26 + 12)
			local s = st.summary
			detailVals["송금 후 잔액"].Text = if s then K.won(s.bank - st.amount) else "확인 중…"
		end
		-- memo
		memoBox.Text = ""
		if st.locked then
			memoHead.Text = if st.memo then "요청 메모" else "메모"
			memoRow.Visible = false
			memoBox.Visible = false
			if st.memo then
				memoHead.Text = "요청 메모 · " .. st.memo
			end
		else
			memoHead.Text = "메모 (받는 분에게 보여요)"
			memoRow.Visible = true
			selectPreset(nil)
		end
		warnL.Visible = not req
		errL.Visible = false
		hold.reset()
		hold.button.Visible = not req
		reqBtn.Visible = req
		K.setButtonLoading(reqBtn, false)
		page.layout(lastWide, fl.size())
		scroll.CanvasPosition = Vector2.zero
		if not st.summary and not req then
			task.spawn(function()
				local s = FK.call("summary", {})
				if s.ok then
					st.summary = s
					detailVals["송금 후 잔액"].Text = K.won(s.bank - st.amount)
				end
			end)
		end
	end
	function page.hide()
		pcall(function()
			memoBox:ReleaseFocus()
		end)
	end
	return page
end

local function buildDone(frame: Frame, fl: any): any
	local panes = FK.panes(frame, 0.5)
	local A, B = panes.a, panes.b
	local check = FK.checkmark(A, 76)
	check.frame.AnchorPoint = Vector2.new(0.5, 0)
	local title = K.text(A, { Name = "Title", Size = UDim2.new(1, 0, 0, 28), Text = "송금 완료", Font = K.Font.bold, TextSize = K.Type.title, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25 })
	local sub = K.text(A, { Name = "Sub", Size = UDim2.new(1, 0, 0, 40), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.bodySm, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25 })
	local card = K.Card(B, { Name = "Balance", Size = UDim2.new(1, 0, 0, 92), ZIndex = 24 })
	local capL = K.text(card, { Name = "Cap", Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 16), Text = "통장 잔액", TextColor3 = K.Color.sub, TextSize = K.Type.caption, ZIndex = 25 })
	local bal = K.MoneyLabel(card, { Name = "Value", Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -28, 0, 30), Text = "0원", Font = K.Font.bold, TextSize = 24, ZIndex = 25 })
	local meta = K.text(card, { Name = "Meta", Position = UDim2.fromOffset(14, 62), Size = UDim2.new(1, -28, 0, 16), Text = "", TextColor3 = K.Color.faint, TextSize = K.Type.micro, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
	local btns = K.frame(B, { Name = "Buttons", Size = UDim2.new(1, 0, 0, 48), ZIndex = 24 })
	local doneMode = "transfer"
	local stmt = K.Button(btns, { name = "Statement", text = "거래내역", style = "secondary", size = UDim2.new(0.5, -4, 1, 0), zIndex = 25, onClick = function()
		fl.go(if doneMode == "request" then "requests" else "statement", {})
	end })
	local okB = K.Button(btns, { name = "Done", text = "확인", style = "primary", size = UDim2.new(0.5, -4, 1, 0), position = UDim2.new(0.5, 4, 0, 0), zIndex = 25, onClick = function()
		fl.close()
	end })
	local _ = okB
	local page = { title = "", subtitle = "", back = false }
	local lastWide = false
	function page.layout(wide: boolean, w: number, h: number)
		lastWide = wide
		if wide then
			panes.layout(true, w, h, 0)
			local ah = A.Size.Y.Offset
			local y0 = math.max(0, math.floor(ah / 2 - 90))
			check.frame.Position = UDim2.new(0.5, 0, 0, y0 + 6)
			title.Position = UDim2.fromOffset(0, y0 + 96)
			sub.Position = UDim2.fromOffset(0, y0 + 128)
			local bh = B.Size.Y.Offset
			local by = math.max(0, math.floor(bh / 2 - 80))
			card.Position = UDim2.fromOffset(0, by)
			btns.Position = UDim2.fromOffset(0, by + 104)
		else
			panes.layout(false, w, h, 190)
			check.frame.Position = UDim2.new(0.5, 0, 0, 8)
			title.Position = UDim2.fromOffset(0, 96)
			sub.Position = UDim2.fromOffset(0, 128)
			card.Position = UDim2.fromOffset(0, 8)
			btns.Position = UDim2.fromOffset(0, 112)
		end
	end
	function page.show(args: any)
		local r = args.result or {}
		local t = args.target or st.target or { n = "" }
		doneMode = args.mode or "transfer"
		stmt.Visible = true
		if args.mode == "request" then
			title.Text = "요청을 보냈어요"
			sub.Text = string.format("%s에게 %s을 요청했어요.\n5분 안에 보내 주면 입금 알림이 와요.", particle(t.n), K.won(r.amount or st.amount))
			capL.Text = "요청 금액"
			bal.set(r.amount or st.amount, false)
			meta.Text = if r.memo then "메모 · " .. r.memo else "답이 오면 알림으로 알려 드려요"
			check.setColor(K.Color.cyan)
			stmt.Text = "요청 목록"
		else
			title.Text = "송금 완료"
			sub.Text = string.format("%s에게 %s을 보냈어요", particle(t.n), K.won(r.amount or st.amount))
			capL.Text = "통장 잔액"
			local after = r.bank or 0
			local before = args.before or (after + (r.amount or 0))
			bal.value = before
			bal.set(before, false)
			task.delay(0.45, function()
				bal.set(after, true)
			end)
			meta.Text = FK.timeOfDay(r.t or FK.now()) .. (if r.memo then " · " .. r.memo else "") .. (if r.memoDropped then " · 메모는 전달되지 않았어요" else "")
			check.setColor(K.Color.green)
			stmt.Text = "거래내역"
		end
		page.layout(lastWide, fl.size())
		check.play()
		task.delay(0.25, function()
			FK.confetti(fl.card, if args.mode == "request" then 10 else 20)
		end)
		K.feedback("money")
	end
	return page
end

local function buildRequests(frame: Frame, fl: any): any
	local scroll, content = FK.scroll(frame, "Requests")
	local host = scroll
	local page = { title = "송금 요청", subtitle = "받은 요청 · 보낸 요청" }
	local function render(data: any)
		FK.clear(content)
		if not data then
			K.EmptyState(content, { order = 1, compact = true, icon = "📡", title = "불러오지 못했어요", body = "잠시 후 다시 열어 주세요" })
			return
		end
		local order = 0
		order += 1
		K.SectionHeader(content, { title = "받은 요청", order = order, caption = "보내기를 누르면 확인 화면으로 가요" })
		if #data.incoming == 0 then
			order += 1
			K.EmptyState(content, { order = order, compact = true, height = 110, icon = "📭", title = "받은 요청이 없어요" })
		end
		for _, r in data.incoming do
			order += 1
			local c = K.Card(content, { Name = "In_" .. r.id, Size = UDim2.new(1, 0, 0, 112), LayoutOrder = order, ZIndex = 24 })
			local av = FK.avatar(c, 38, r.fromId, r.fromName)
			av.Position = UDim2.fromOffset(12, 12)
			K.text(c, { Name = "T", Position = UDim2.fromOffset(60, 12), Size = UDim2.new(1, -72, 0, 18), Text = string.format("%s이 %s을 요청했어요", particle(r.fromName), K.won(r.amount)), Font = K.Font.bold, TextSize = K.Type.bodySm, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
			K.text(c, { Name = "S", Position = UDim2.fromOffset(60, 31), Size = UDim2.new(1, -72, 0, 16), Text = (if r.memo then r.memo .. " · " else "") .. K.countdown(r.expiresIn) .. " 남음", TextColor3 = K.Color.sub, TextSize = K.Type.caption, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
			local row = K.frame(c, { Name = "Btns", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -10), Size = UDim2.new(1, -24, 0, 44), ZIndex = 25 })
			K.Button(row, { name = "Decline", text = "거절", style = "secondary", size = UDim2.new(0.5, -4, 1, 0), zIndex = 26, onClick = function()
				local res = FK.call("requestAnswer", { requestId = r.id, accept = false, rid = FK.rid() })
				FK.dismissIncoming("req_" .. r.id)
				K.toast({ kind = if res.ok then "info" else "error", title = if res.ok then "요청을 거절했어요" else "처리하지 못했어요", body = if res.ok then particle(r.fromName) .. "에게 알렸어요" else res.message })
				page.show({})
			end })
			K.Button(row, { name = "Pay", text = "보내기", style = "primary", size = UDim2.new(0.5, -4, 1, 0), position = UDim2.new(0.5, 4, 0, 0), zIndex = 26, onClick = function()
				M.payRequest(r)
			end })
		end
		order += 1
		K.SectionHeader(content, { title = "보낸 요청", order = order })
		if #data.outgoing == 0 then
			order += 1
			K.EmptyState(content, { order = order, compact = true, height = 110, icon = "📤", title = "보낸 요청이 없어요", actionText = "송금 요청하기", onAction = function()
				M.startRequest({})
			end })
		end
		for _, r in data.outgoing do
			order += 1
			local rr = K.ListRow(content, { name = "Out_" .. r.id, title = string.format("%s에게 %s", particle(r.toName), K.won(r.amount)), subtitle = (if r.memo then r.memo .. " · " else "") .. "답을 기다리는 중 · " .. K.countdown(r.expiresIn) .. " 남음", height = 58, order = order, trailing = "", trailingWidth = 70 })
			local av = FK.avatar(rr.row, 38, r.toId, r.toName)
			av.AnchorPoint = Vector2.new(0, 0.5)
			av.Position = UDim2.new(0, 10, 0.5, 0)
			rr.title.Position = UDim2.new(0, 60, 0, 58 / 2 - 19)
			rr.subtitle.Position = UDim2.new(0, 60, 0, 58 / 2 + 1)
			local cancel = K.Button(rr.row, { name = "Cancel", text = "취소", style = "danger", size = UDim2.fromOffset(60, 44), zIndex = 26, onClick = function()
				local res = FK.call("requestAnswer", { requestId = r.id, rid = FK.rid() })
				K.toast({ kind = if res.ok then "info" else "error", title = if res.ok then "요청을 취소했어요" else "처리하지 못했어요", body = if res.ok then nil else res.message })
				page.show({})
			end })
			cancel.AnchorPoint = Vector2.new(1, 0.5)
			cancel.Position = UDim2.new(1, -8, 0.5, 0)
		end
	end
	function page.layout(_wide: boolean, w: number, h: number)
		host.Position = UDim2.fromOffset(12, 0)
		host.Size = UDim2.fromOffset(w - 24, h - 8)
	end
	function page.show(_args: any)
		FK.clear(content)
		K.Skeleton(content, { order = 1, rows = 3, rowHeight = 64 })
		task.spawn(function()
			local r = FK.call("requests", {})
			render(if r.ok then r else nil)
		end)
	end
	return page
end

local KIND_ICON = {
	p2p_out = { "↑" },
	p2p_in = { "↓" },
	cash_out = { "💵" },
	cash_in = { "💵" },
	atm_wd = { "🏧" },
	atm_dep = { "🏧" },
	fee = { "🧾" },
	refund = { "↩" },
}

local function buildStatement(frame: Frame, fl: any): any
	local account: string? = nil
	local top = K.frame(frame, { Name = "Top", ZIndex = 23 })
	local sumCard = K.Card(top, { Name = "Summary", Size = UDim2.new(1, 0, 0, 58), ZIndex = 24 })
	local sumL = {}
	for i, def in { { "bank", "🏦 통장" }, { "cash", "💵 현금" }, { "today", "📤 오늘 보낸 돈" } } do
		local col = K.frame(sumCard, { Name = "S_" .. def[1], Position = UDim2.new((i - 1) / 3, 0, 0, 0), Size = UDim2.new(1 / 3, 0, 1, 0), ZIndex = 25 })
		K.text(col, { Name = "L", Position = UDim2.fromOffset(12, 9), Size = UDim2.new(1, -16, 0, 14), Text = def[2], TextColor3 = K.Color.sub, TextSize = K.Type.micro, Font = K.Font.bold, ZIndex = 25 })
		local v = K.MoneyLabel(col, { Name = "V", Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -16, 0, 20), Text = "…", Font = K.Font.bold, TextSize = K.Type.caption + 2, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
		v.format = K.wonShort
		sumL[def[1]] = v
	end
	local seg = K.Segmented(top, { items = { { id = "all", label = "전체" }, { id = "bank", label = "통장" }, { id = "cash", label = "현금" } }, value = "all", onChange = function(id: string)
		account = if id == "all" then nil else id
		M._loadStatement()
	end })
	local listHost = K.frame(frame, { Name = "ListHost", ZIndex = 23 })
	local scroll, content = FK.scroll(listHost, "Entries")
	local page = { title = "거래내역", subtitle = BANK.bankName .. " " .. BANK.account }
	local lastWide = false

	local function detail(e: any)
		local isIn = e.amount >= 0
		local rows = {
			{ "거래", e.label },
			{ "금액", (if isIn then "+" else "−") .. K.won(math.abs(e.amount)), if isIn then K.Color.green else Color3.fromRGB(255, 128, 132) },
			{ "계좌", if e.account == "cash" then "현금 (지갑)" else BANK.bankName .. " " .. BANK.account },
			{ "거래 후 잔액", K.won(e.balance or 0) },
			{ "일시", FK.dayTitle(e.t) .. " " .. FK.timeOfDay(e.t) },
		}
		if e.peer then
			table.insert(rows, 2, { if isIn then "보낸 분" else "받는 분", e.peer })
		end
		if e.memo then
			table.insert(rows, { "메모", e.memo })
		end
		if e.fee then
			table.insert(rows, { "수수료", K.won(e.fee) })
		end
		if e.place then
			table.insert(rows, { "장소", e.place })
		end
		if e.ref then
			table.insert(rows, { "거래번호", string.upper(string.sub(e.ref, 1, 10)) })
		end
		K.Modal(fl.card, { title = "거래 상세", icon = "🧾", iconColor = K.Color.cyan, details = rows, buttons = { { text = "닫기", style = "primary" } }, zIndex = 60, width = 320 })
	end

	local function render(r: any)
		FK.clear(content)
		if not r or not r.ok then
			K.EmptyState(content, { order = 1, compact = true, icon = "📡", title = "거래내역을 불러오지 못했어요", body = r and r.message or "", actionText = "다시 시도", onAction = function()
				M._loadStatement()
			end })
			return
		end
		local s = r.summary
		if s then
			sumL.bank.set(s.bank, false)
			sumL.cash.set(s.cash, false)
			sumL.today.set(s.sentToday, false)
		end
		if #r.entries == 0 then
			K.EmptyState(content, { order = 1, compact = true, icon = "🧾", title = "아직 거래가 없어요", body = "알바 급여, 송금, ATM 거래가 여기에 쌓여요" })
			return
		end
		local order = 0
		local lastDay: number? = nil
		local card: Frame? = nil
		local inCard = 0
		local rows = {}
		for i, e in r.entries do
			local day = FK.dayKey(e.t or 0)
			if day ~= lastDay then
				lastDay = day
				order += 1
				local dayIn, dayOut = 0, 0
				for _, x in r.entries do
					if FK.dayKey(x.t or 0) == day then
						if x.amount >= 0 then
							dayIn += x.amount
						else
							dayOut -= x.amount
						end
					end
				end
				local h = K.SectionHeader(content, { title = FK.dayTitle(e.t or 0), order = order })
				local tot = K.text(h.frame, { Name = "Totals", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -2, 0, 26), Size = UDim2.fromOffset(170, 16), Text = string.format("+%s  −%s", K.wonShort(dayIn), K.wonShort(dayOut)), TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 25 })
				K.mono(tot)
				order += 1
				card = K.Card(content, { Name = "Day_" .. day, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ClipsDescendants = true, ZIndex = 24 })
				K.list(card :: Frame, false, 0)
				inCard = 0
			end
			inCard += 1
			local amt = e.amount or 0
			local isIn = amt >= 0
			local icon = (KIND_ICON[e.kind or ""] or { if isIn then "↓" else "↑" })[1]
			local color = if e.kind == "fee" then K.Color.orange elseif e.kind == "atm_wd" or e.kind == "atm_dep" then K.Color.violet elseif e.kind == "cash_in" or e.kind == "cash_out" then K.Color.teal elseif isIn then K.Color.green else K.Color.red
			local title = e.label or ""
			if e.kind == "p2p_out" and e.peer then
				title = e.peer .. "님에게 송금"
			elseif e.kind == "p2p_in" and e.peer then
				title = e.peer .. "님이 보냄"
			elseif e.kind == "cash_out" and e.peer then
				title = e.peer .. "님에게 현금"
			elseif e.kind == "cash_in" and e.peer then
				title = e.peer .. "님에게 받은 현금"
			end
			local sub = FK.timeOfDay(e.t or 0) .. " · " .. (if e.account == "cash" then "현금" else "통장")
			if e.memo then
				sub ..= " · " .. e.memo
			elseif e.place then
				sub ..= " · " .. e.place
			end
			local rr = FK.row(card :: Frame, {
				name = "Tx" .. i,
				icon = icon,
				iconColor = color,
				round = true,
				title = title,
				subtitle = sub,
				trailing = (if isIn then "+" else "−") .. K.won(math.abs(amt)),
				trailingColor = if isIn then K.Color.green else Color3.fromRGB(255, 128, 132),
				trailing2 = "잔액 " .. K.wonShort(e.balance or 0),
				trailingWidth = 112,
				grouped = true,
				height = 58,
				order = inCard,
				onClick = function()
					detail(e)
				end,
			})
			K.mono(rr.trailing)
			table.insert(rows, rr.row)
		end
		K.stagger(rows, K.Color.card)
	end

	function M._loadStatement()
		FK.clear(content)
		K.Skeleton(content, { order = 1, rows = 5, rowHeight = 54 })
		task.spawn(function()
			local r = FK.call("statement", { account = account })
			render(r)
		end)
	end

	function page.layout(wide: boolean, w: number, h: number)
		lastWide = wide
		local p = 12
		if wide then
			top.Position = UDim2.fromOffset(p, 0)
			top.Size = UDim2.fromOffset(w - p * 2, 58)
			sumCard.Size = UDim2.new(0.62, -4, 0, 58)
			seg.frame.Position = UDim2.new(0.62, 4, 0, 4)
			seg.frame.Size = UDim2.new(0.38, -4, 0, 50)
			listHost.Position = UDim2.fromOffset(p, 66)
			listHost.Size = UDim2.fromOffset(w - p * 2, h - 70)
		else
			top.Position = UDim2.fromOffset(p, 0)
			top.Size = UDim2.fromOffset(w - p * 2, 116)
			sumCard.Size = UDim2.new(1, 0, 0, 58)
			seg.frame.Position = UDim2.fromOffset(0, 64)
			seg.frame.Size = UDim2.new(1, 0, 0, 50)
			listHost.Position = UDim2.fromOffset(p, 124)
			listHost.Size = UDim2.fromOffset(w - p * 2, h - 128)
		end
	end
	function page.show(args: any)
		account = if args.account == "cash" or args.account == "bank" then args.account else nil
		seg.set(account or "all", true)
		page.layout(lastWide, fl.size())
		M._loadStatement()
	end
	page.refresh = function()
		if fl.isOpen() and fl.current() == "statement" then
			M._loadStatement()
		end
	end
	M._statementPage = page
	return page
end

-------------------------------------------------------------------------------------------------
-- Entry points
-------------------------------------------------------------------------------------------------
local function resetState(mode: string, args: any)
	st.mode = mode
	st.amount = 0
	st.preset = nil
	st.memo = nil
	st.requestId = nil
	st.locked = false
	st.target = nil
	st.busy = false
	st.returnTo = if type(args.from) == "string" then args.from else nil
end

local function targetFromArgs(args: any): any?
	local u = tonumber(args.to)
	if not u or u <= 0 or u == player.UserId then
		return nil
	end
	local p = Players:GetPlayerByUserId(u)
	return { u = u, n = if type(args.name) == "string" then args.name else nameFor(u), un = if p then p.Name else (args.name or "") }
end

function M.startTransfer(args: any)
	resetState("transfer", args)
	local t = targetFromArgs(args)
	if t then
		st.target = t
		flow.open("amount", { amount = args.amount })
	else
		flow.open("pick", {})
	end
end

function M.startRequest(args: any)
	resetState("request", args)
	local t = targetFromArgs(args)
	if t then
		st.target = t
		flow.open("amount", { amount = args.amount })
	else
		flow.open("pick", {})
	end
end

function M.payRequest(r: any)
	resetState("transfer", {})
	st.target = { u = r.fromId, n = r.fromName, un = nameFor(r.fromId, r.fromName) }
	local p = Players:GetPlayerByUserId(r.fromId)
	if p then
		st.target.un = p.Name
	end
	st.amount = r.amount
	st.requestId = r.id
	st.memo = r.memo
	st.locked = true
	if flow.isOpen() then
		flow.go("confirm", {})
	else
		flow.open("confirm", {})
	end
end

function M.open(flowId: string, args: any)
	if flowId == "transfer" then
		if args.requestId and args.to and args.amount then
			M.payRequest({ id = args.requestId, fromId = args.to, fromName = args.name or nameFor(args.to), amount = args.amount, memo = args.memo })
		else
			M.startTransfer(args)
		end
	elseif flowId == "request" then
		M.startRequest(args)
	elseif flowId == "requests" then
		resetState("transfer", args)
		flow.open("requests", {})
	elseif flowId == "statement" then
		resetState("transfer", args)
		flow.open("statement", args)
	end
end

function M.close()
	if flow then
		flow.close()
	end
end

function M.isOpen(): boolean
	return flow ~= nil and flow.isOpen()
end

-------------------------------------------------------------------------------------------------
-- Server events
-------------------------------------------------------------------------------------------------
local function onBankEvent(e: any)
	if type(e) ~= "table" then
		return
	end
	if e.kind == "request" and type(e.request) == "table" then
		local r = e.request
		if type(r.id) ~= "string" or type(r.amount) ~= "number" then
			return
		end
		incomingCards[r.id] = FK.incoming({
			id = "req_" .. r.id,
			userId = r.fromId,
			name = r.fromName,
			color = K.Color.gold,
			title = string.format("💸 송금 요청 · %s", K.won(r.amount)),
			body = string.format("%s이 요청했어요%s", particle(tostring(r.fromName)), if r.memo then " · " .. tostring(r.memo) else ""),
			timeout = math.min(45, tonumber(r.expiresIn) or 45),
			secondary = { text = "거절", onClick = function()
				local res = FK.call("requestAnswer", { requestId = r.id, accept = false, rid = FK.rid() })
				K.toast({ kind = if res.ok then "info" else "error", title = if res.ok then "요청을 거절했어요" else "처리하지 못했어요", body = if res.ok then particle(tostring(r.fromName)) .. "에게 알렸어요" else res.message })
			end },
			primary = { text = "보내기", onClick = function()
				M.payRequest(r)
			end },
		})
	elseif e.kind == "requestAnswered" then
		if type(e.requestId) == "string" then
			FK.dismissIncoming("req_" .. e.requestId)
		end
		local by = tostring(e.byName or "상대방")
		if e.declined then
			K.toast({ kind = "info", title = "송금 요청을 거절했어요", body = string.format("%s이 %s 요청을 거절했어요", particle(by), K.won(e.amount or 0)), icon = "🙅" })
		elseif e.expired then
			K.toast({ kind = "info", title = "송금 요청이 끝났어요", body = "5분 동안 답이 없어서 요청이 만료됐어요", icon = "⌛" })
		elseif e.cancelled then
			K.toast({ kind = "info", title = "송금 요청이 취소됐어요", body = if e.reason == "left" then particle(by) .. "이 서버를 떠났어요" else particle(by) .. "이 요청을 취소했어요", icon = "↩" })
		end
		if flow and flow.isOpen() and flow.current() == "requests" then
			local p = flow
			task.defer(function()
				p.go("requests", {})
			end)
		end
	elseif e.kind == "received" or e.kind == "sent" then
		st.summary = nil
		local sp = M._statementPage
		if sp and sp.refresh then
			sp.refresh()
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------------------------
function M.init(ctx: any)
	F = ctx
	K = ctx.K
	G = ctx.G
	FK = require(script.Parent:WaitForChild("FeatureKit"))
	FK.bind(ctx)
	if G and G.BANK then
		BANK.minTransfer = G.BANK.minTransfer
		BANK.maxTransfer = G.BANK.maxTransfer
		BANK.dailyLimit = G.BANK.dailyLimit
		BANK.nearbyRadius = G.BANK.nearbyRadius
		BANK.account = G.BANK.account
		BANK.bankName = G.BANK.bankName
	end
	if G and G.BANK_PRESETS and G.BANK_PRESET_ORDER then
		PRESETS = G.BANK_PRESETS
		PRESET_ORDER = G.BANK_PRESET_ORDER
	end
	flow = FK.Flow("money", {
		title = "송금",
		onClose = function()
			st.busy = false
			local back = st.returnTo
			st.returnTo = nil
			if back then
				F.phone(back)
			end
		end,
	})
	flow.page("pick", buildPick)
	flow.page("amount", buildAmount)
	flow.page("confirm", buildConfirm)
	flow.page("done", buildDone)
	flow.page("requests", buildRequests)
	flow.page("statement", buildStatement)
	-- "요청 목록" after sending a request
	M.flowRef = flow
	task.spawn(function()
		local ev = F.remote("BankEvent", 60)
		if ev and ev:IsA("RemoteEvent") then
			ev.OnClientEvent:Connect(function(e: any)
				local ok, err = pcall(onBankEvent, e)
				if not ok then
					warn("[GwangalliFeatures] transfer event: " .. tostring(err))
				end
			end)
		end
	end)
end

return M
