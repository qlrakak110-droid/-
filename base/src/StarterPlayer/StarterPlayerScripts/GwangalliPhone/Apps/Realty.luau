-- 부동산: my home card (name, 월세 / 자가, next automatic transfer countdown, overdue warning with
-- 지금 납부, and 집으로 가기 + 길안내 away from home / 나가기 + 잠자기 at home -> PhoneAction
-- "enterHome" / "leaveHome" / "sleep"), a 월세 vs 매매 explainer, a filter and the listings (building
-- silhouette drawn from frames, price, deposit, comfort, distance, 계약하기 -> a confirm modal with
-- the cost breakdown -> "rentHome" / "buyHome" {listingId}). Built with the GwangalliUI kit.

return function(ctx: any)
	local K, Net, Life, Dest, AppKit = ctx.K, ctx.Net, ctx.Life, ctx.Dest, ctx.AppKit

	local app = {}
	local scroll: ScrollingFrame
	local conn: any
	local content: Frame
	local homeCard: Frame
	local homeArt: Frame
	local homeTitle: TextLabel
	local homeSub: TextLabel
	local homeStatus: TextLabel
	local dueBar: any
	local btnRow: Frame
	local goBtn: TextButton
	local guideBtn: TextButton
	local leaveBtn: TextButton
	local sleepBtn: TextButton
	local payBtn: TextButton
	local noHome: any
	local listHolder: Frame
	local filter = "all"
	local visible = false
	local atHome = false
	local listKey = ""
	local loopSerial = 0
	local homeArtTier = -1

	local function say(text: string, kind: string?)
		ctx.phone.toast({ app = "realty", title = "부동산", body = text, kind = kind or "home", silent = true })
	end

	local function send(action: string, payload: any?): boolean
		local ok, err = Net.send(action, payload)
		if not ok then
			say(err or "보낼 수 없어요", "error")
		end
		return ok
	end

	local function rootPos(): Vector3?
		local char = ctx.player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root.Position else nil
	end

	local function sharedListing(id: string?): any
		local G = ctx.Data.Shared
		return G and G.LISTINGS and id and G.LISTINGS[id] or nil
	end

	-- client-side mirror of the server's "at home" test (inside the unit, or near the entrance)
	local function computeAtHome(): boolean
		local h = Net.profile.home
		local pos = rootPos()
		if type(h) ~= "table" or not pos then
			return false
		end
		local unit = workspace:FindFirstChild("HomeUnit_" .. tostring(h.tier))
		if unit and unit:IsA("Model") then
			local ok, cf, size = pcall(unit.GetBoundingBox, unit)
			if ok then
				local rel = cf:PointToObjectSpace(pos)
				if math.abs(rel.X) <= size.X / 2 + 8 and math.abs(rel.Y) <= size.Y / 2 + 8 and math.abs(rel.Z) <= size.Z / 2 + 8 then
					return true
				end
			end
		end
		local e = type(h.place) == "string" and Dest.position(h.place) or nil
		return e ~= nil and (pos - e).Magnitude <= 60
	end

	---------------------------------------------------------------------------------------------------
	-- Building silhouette (tier 1..5), drawn from frames on a dusk-sky tile
	---------------------------------------------------------------------------------------------------
	local function silhouette(parent: Instance, tier: number, size: number): Frame
		local tile = K.frame(parent, { Name = "Art", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ClipsDescendants = true })
		K.corner(tile, K.Radius.sm)
		K.gradient(tile, { Color3.fromRGB(34, 38, 96), Color3.fromRGB(150, 70, 130) }, 90)
		local ground = K.frame(tile, { Name = "Ground", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.12, 0), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(20, 20, 36) })
		local _ = ground
		local specs = {
			{ w = 0.46, h = 0.34, win = 1 }, -- 고시원: small block
			{ w = 0.5, h = 0.48, win = 2 },
			{ w = 0.44, h = 0.64, win = 3 },
			{ w = 0.34, h = 0.8, win = 5 },
			{ w = 0.3, h = 0.9, win = 6 },
		}
		local sp = specs[math.clamp(tier, 1, 5)]
		local body = K.frame(tile, { Name = "Tower", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.9), Size = UDim2.fromScale(sp.w, sp.h * 0.88), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
		K.gradient(body, { Color3.fromRGB(58, 60, 110), Color3.fromRGB(22, 22, 44) }, 90)
		if tier >= 4 then
			local side = K.frame(tile, { Name = "Side", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0.5 + sp.w / 2, 0.9), Size = UDim2.fromScale(0.16, sp.h * 0.6), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(30, 30, 58) })
			local _s = side
		end
		for i = 1, sp.win do
			local y = 0.12 + (i - 1) * (0.8 / math.max(1, sp.win))
			for c = 0, 1 do
				local lit = (i + c + tier) % 3 ~= 0
				K.frame(body, { Name = "Win", Position = UDim2.fromScale(0.2 + c * 0.38, y), Size = UDim2.fromScale(0.22, 0.5 / math.max(2, sp.win)), BackgroundTransparency = if lit then 0.1 else 0.7, BackgroundColor3 = Color3.fromRGB(255, 214, 140) })
			end
		end
		if tier == 5 then
			local crown = K.frame(tile, { Name = "Glow", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.9 - sp.h * 0.88, 0), Size = UDim2.fromScale(sp.w + 0.06, 0.05), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
			K.gradient(crown, K.Grad.bridge, 0)
		end
		return tile
	end

	---------------------------------------------------------------------------------------------------
	-- My home
	---------------------------------------------------------------------------------------------------
	local function layoutButtons(list: { TextButton })
		for _, b in { goBtn, guideBtn, leaveBtn, sleepBtn, payBtn } do
			b.Visible = false
		end
		local n = #list
		for i, b in list do
			b.Visible = true
			b.LayoutOrder = i
			b.Size = UDim2.new(1 / n, if n > 1 then -4 else 0, 0, 44)
		end
	end

	local function renderHome()
		local h = Net.profile.home
		local has = type(h) == "table" and (h.listingId or h.name) ~= nil
		homeCard.Visible = has
		noHome.frame.Visible = not has
		if not has then
			return
		end
		local tier = tonumber(h.tier) or 1
		if homeArtTier ~= tier then
			homeArtTier = tier
			homeArt:ClearAllChildren()
			silhouette(homeArt, tier, 56).Position = UDim2.fromOffset(0, 0)
		end
		homeTitle.Text = tostring(h.name or "내 집")
		homeSub.Text = "📍 " .. tostring(h.place or "") .. (if atHome then " · 지금 집이에요" else "")
		local missed = tonumber(h.missed) or 0
		if h.owned then
			local l = sharedListing(h.listingId)
			homeStatus.Text = string.format("자가 🏡 · 관리비 %s/일 자동이체", K.won(tonumber(h.rentPerDay) or (l and l.upkeepPerDay) or 0))
			homeStatus.TextColor3 = Color3.fromRGB(200, 240, 236)
			dueBar.frame.Visible = false
		elseif missed > 0 then
			homeStatus.Text = string.format("⚠️ 월세 연체 %d일 · %d일 밀리면 퇴거돼요", missed, 3)
			homeStatus.TextColor3 = Color3.fromRGB(255, 150, 150)
			dueBar.frame.Visible = false
		else
			local due = tonumber(h.dueIn) or 0
			homeStatus.Text = string.format("월세 %s/일 · 다음 자동이체 %s 후", K.won(tonumber(h.rentPerDay) or 0), K.countdown(due))
			homeStatus.TextColor3 = Color3.fromRGB(200, 240, 236)
			dueBar.frame.Visible = true
			dueBar.set(1 - math.clamp(due / 1440, 0, 1))
		end
		local list = {}
		if missed > 0 and not h.owned then
			table.insert(list, payBtn)
		end
		if atHome then
			table.insert(list, sleepBtn)
			table.insert(list, leaveBtn)
		else
			table.insert(list, goBtn)
			if #list < 2 then
				table.insert(list, guideBtn)
			end
		end
		layoutButtons(list)
	end

	---------------------------------------------------------------------------------------------------
	-- Listings
	---------------------------------------------------------------------------------------------------
	local function openContract(l: any)
		local p = Net.profile
		local cash, bank = Life.cash(p), Life.bank(p)
		local isBuy = l.canBuy and not l.canRent
		local sl = sharedListing(l.id)
		local deposit = tonumber(l.deposit) or 0
		local total = if isBuy then l.price else deposit + l.rentPerDay
		local details = {}
		if isBuy then
			table.insert(details, { "매매가", K.won(l.price) })
			table.insert(details, { "관리비", K.won(sl and sl.upkeepPerDay or 0) .. "/일" })
		else
			table.insert(details, { "보증금", if deposit > 0 then K.won(deposit) else "없음" })
			table.insert(details, { "월세 (매일)", K.won(l.rentPerDay) })
		end
		table.insert(details, { "지금 낼 돈", K.won(total), K.Color.gold })
		table.insert(details, { "내 돈 (현금+통장)", K.won(cash + bank), if cash + bank >= total then K.Color.green else K.Color.red })
		local cur = p.home
		local moving = type(cur) == "table" and cur.listingId ~= nil
		ctx.phone.confirm({
			title = (if isBuy then "매매 계약" else "월세 계약") .. " · " .. l.name,
			body = if moving then "지금 집에서 이사해요. 월세 보증금은 돌려받아요." else (if isBuy then "한 번에 사서 평생 내 집! 총자산에 포함돼요." else "통장(모자라면 현금)에서 매일 자동이체돼요."),
			icon = "📝",
			iconColor = K.Color.teal,
			details = details,
			confirmText = if cash + bank >= total then "계약하기" else "돈이 부족해요",
			style = "gold",
			width = 300,
			onConfirm = function()
				if cash + bank < total then
					say(string.format("돈이 부족해요 · %s 필요", K.won(total)), "warn")
					return
				end
				if send(if isBuy then "buyHome" else "rentHome", { listingId = l.id }) then
					K.feedback("success")
				end
			end,
		})
	end

	local function renderListings()
		local p = Net.profile
		local h = p.home
		local cash = Life.cash(p) + Life.bank(p)
		local listings = Life.listings()
		local key = filter .. "|" .. tostring(type(h) == "table" and h.listingId) .. "|" .. tostring(math.floor(cash / 1000)) .. "|" .. #listings
		if key == listKey then
			return
		end
		listKey = key
		AppKit.clear(listHolder)
		local from = rootPos()
		local n = 0
		local cards = {}
		for _, l in listings do
			local show = filter == "all" or (filter == "rent" and l.canRent) or (filter == "buy" and l.canBuy)
			if show then
				n += 1
				local mine = type(h) == "table" and h.listingId == l.id
				local isBuy = l.canBuy and not l.canRent
				local cost = if isBuy then l.price else (tonumber(l.deposit) or 0) + l.rentPerDay
				local sl = sharedListing(l.id)
				local card = K.Card(listHolder, { Name = "Listing_" .. l.id, Size = UDim2.new(1, 0, 0, 128), LayoutOrder = n })
				if mine then
					K.stroke(card, K.Color.teal, 1, 0.4)
				end
				local art = silhouette(card, l.tier, 64)
				art.Position = UDim2.fromOffset(10, 10)
				K.text(card, { Name = "Name", Position = UDim2.fromOffset(84, 10), Size = UDim2.new(1, -96, 0, 19), Text = l.name, Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd })
				local pos = l.place ~= "" and Dest.position(l.place) or nil
				K.text(card, { Name = "Place", Position = UDim2.fromOffset(84, 29), Size = UDim2.new(1, -96, 0, 15), Text = "📍 " .. l.place .. (if pos and from then " · " .. K.meters((pos - from).Magnitude) else ""), TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
				local tags = K.frame(card, { Name = "Tags", Position = UDim2.fromOffset(84, 48), Size = UDim2.new(1, -96, 0, 20) })
				K.list(tags, true, 4)
				K.Pill(tags, { text = if isBuy then "매매" else "월세", color = if isBuy then K.Color.violet else K.Color.teal, height = 20, order = 1 })
				if not isBuy then
					K.Pill(tags, { text = if (tonumber(l.deposit) or 0) > 0 then "보증금 " .. K.wonShort(l.deposit) else "보증금 없음", color = K.Color.cyan, height = 20, order = 2 })
				end
				if sl and sl.comfort and sl.comfort > 0 then
					K.Pill(tags, { text = "행복 +" .. tostring(sl.comfort), color = K.Color.gold, height = 20, order = 3 })
				end
				local price = K.text(card, { Name = "Price", Position = UDim2.fromOffset(12, 84), Size = UDim2.new(1, -150, 0, 20), Text = if isBuy then K.wonShort(l.price) else K.won(l.rentPerDay) .. "/일", TextColor3 = K.Color.gold, Font = K.Font.bold, TextSize = K.Type.body })
				K.mono(price)
				K.text(card, { Name = "PriceCaption", Position = UDim2.fromOffset(12, 104), Size = UDim2.new(1, -150, 0, 14), Text = if isBuy then "매매가 · 관리비 " .. K.wonShort(sl and sl.upkeepPerDay or 0) .. "/일" else "매일 자동이체", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
				local b = K.Button(card, {
					name = "Contract_" .. l.id,
					text = if mine then "내 집" elseif cash >= cost then "계약하기" else "돈 모으기",
					style = if mine then "secondary" elseif cash >= cost then "gold" else "secondary",
					anchor = Vector2.new(1, 1),
					position = UDim2.new(1, -10, 1, -10),
					size = UDim2.fromOffset(112, 44),
					textSize = K.Type.caption + 1,
					onClick = function()
						if mine then
							return
						end
						openContract(l)
					end,
				})
				if mine then
					K.setButtonEnabled(b, false)
				end
				table.insert(cards, card)
			end
		end
		if n == 0 then
			K.EmptyState(listHolder, { order = 1, compact = true, icon = "🏚️", title = "매물이 없어요", body = "다른 조건으로 찾아보세요" })
		end
		K.stagger(cards)
	end

	local function refresh()
		if not visible then
			return
		end
		local ready = conn.update()
		content.Visible = ready
		if not ready then
			return
		end
		renderHome()
		renderListings()
	end

	local function startLoop()
		loopSerial += 1
		local mine = loopSerial
		task.spawn(function()
			while visible and loopSerial == mine do
				local now = computeAtHome()
				if now ~= atHome then
					atHome = now
					refresh()
				elseif homeCard.Visible then
					renderHome()
				end
				task.wait(1)
			end
		end)
	end

	---------------------------------------------------------------------------------------------------
	-- Build
	---------------------------------------------------------------------------------------------------
	function app.build(body: Frame)
		local L = ctx.phone.layout()
		ctx.phone.header(body, "부동산")
		scroll = AppKit.scroll(body, L.headerH, { name = "Scroll", gap = 10, topPad = 2 })
		conn = AppKit.conn(scroll, ctx, 0)
		content = K.frame(scroll, { Name = "Content", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
		K.list(content, false, 10)

		homeCard = K.frame(content, { Name = "MyHome", Size = UDim2.new(1, 0, 0, 156), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 1 })
		K.corner(homeCard, K.Radius.lg)
		K.gradient(homeCard, { Color3.fromRGB(20, 118, 140), Color3.fromRGB(26, 44, 100) }, 30)
		K.stroke(homeCard, Color3.new(1, 1, 1), 1, 0.8)
		K.text(homeCard, { Name = "Caption", Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -90, 0, 14), Text = "내 집", TextColor3 = Color3.fromRGB(190, 240, 236), TextSize = K.Type.micro, Font = K.Font.bold })
		homeArt = K.frame(homeCard, { Name = "ArtHolder", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(56, 56) })
		homeTitle = K.text(homeCard, { Name = "Title", Position = UDim2.fromOffset(14, 26), Size = UDim2.new(1, -90, 0, 22), Text = "", Font = K.Font.bold, TextSize = K.Type.body + 1, TextTruncate = Enum.TextTruncate.AtEnd })
		homeSub = K.text(homeCard, { Name = "Sub", Position = UDim2.fromOffset(14, 48), Size = UDim2.new(1, -90, 0, 15), Text = "", TextColor3 = Color3.fromRGB(210, 236, 240), TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
		homeStatus = K.text(homeCard, { Name = "Status", Position = UDim2.fromOffset(14, 72), Size = UDim2.new(1, -28, 0, 15), Text = "", TextSize = K.Type.micro, Font = K.Font.bold, TextTruncate = Enum.TextTruncate.AtEnd })
		dueBar = K.ProgressBar(homeCard, { color = K.Color.cyan, height = 4 })
		dueBar.frame.Position = UDim2.fromOffset(14, 92)
		dueBar.frame.Size = UDim2.new(1, -28, 0, 4)
		btnRow = K.frame(homeCard, { Name = "Buttons", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -12), Size = UDim2.new(1, -28, 0, 44) })
		K.list(btnRow, true, 8)
		goBtn = K.Button(btnRow, { name = "GoHome", text = "🏠 집으로 가기", style = "primary", textSize = K.Type.caption + 1, onClick = function()
			if send("enterHome", {}) then
				K.feedback("success")
				ctx.phone.close()
			end
		end })
		guideBtn = K.Button(btnRow, { name = "GuideHome", text = "🧭 길안내", style = "glass", textSize = K.Type.caption + 1, onClick = function()
			local h = Net.profile.home
			if type(h) == "table" and type(h.place) == "string" then
				ctx.Tracker.setWaypoint(h.place)
				Net.send("setWaypoint", { destination = h.place })
				say("🧭 집까지 길안내를 시작해요")
			end
		end })
		leaveBtn = K.Button(btnRow, { name = "LeaveHome", text = "🚪 나가기", style = "glass", textSize = K.Type.caption + 1, onClick = function()
			if send("leaveHome", {}) then
				ctx.phone.close()
			end
		end })
		sleepBtn = K.Button(btnRow, { name = "Sleep", text = "😴 잠자기", style = "primary", textSize = K.Type.caption + 1, onClick = function()
			ctx.phone.confirm({
				title = "잠을 잘까요?",
				body = "체력이 가득 차고 행복이 올라요. 시간이 8시간 흘러요 (월세 이체도 가까워져요).",
				icon = "😴",
				iconColor = K.Color.violet,
				confirmText = "잘 자요",
				width = 290,
				onConfirm = function()
					if send("sleep", {}) then
						ctx.phone.close()
					end
				end,
			})
		end })
		payBtn = K.Button(btnRow, { name = "PayRent", text = "💸 지금 납부", style = "gold", textSize = K.Type.caption + 1, onClick = function()
			if send("reply", { contactId = "landlord", contact = "landlord", choice = "pay" }) then
				K.feedback("money")
			end
		end })
		noHome = K.EmptyState(content, { order = 1, compact = true, icon = "🏚️", title = "아직 집이 없어요", body = "보증금 없는 고시원부터 시작해 보세요", color = K.Color.teal })
		noHome.frame.Visible = false

		-- 월세 vs 매매
		local info = K.Card(content, { Name = "RentVsBuy", Size = UDim2.new(1, 0, 0, 74), LayoutOrder = 2 })
		local half = function(x: number, title: string, lines: string, color: Color3)
			local f = K.frame(info, { Name = title, Position = UDim2.new(x, if x > 0 then 4 else 12, 0, 10), Size = UDim2.new(0.5, -16, 1, -20) })
			K.text(f, { Name = "Title", Size = UDim2.new(1, 0, 0, 16), Text = title, TextColor3 = color, Font = K.Font.bold, TextSize = K.Type.caption })
			K.text(f, { Name = "Body", Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 1, -18), Text = lines, TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		end
		half(0, "🔑 월세", "보증금 + 매일 자동이체\n이사하면 보증금 환급", K.Color.teal)
		half(0.5, "🏙️ 매매", "한 번에 구매, 관리비만\n총자산에 포함돼요", K.Color.violet)
		K.frame(info, { Name = "Divider", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 1, 1, -24), BackgroundTransparency = 0.88, BackgroundColor3 = K.Color.line })

		local seg = K.Segmented(content, {
			items = { { id = "all", label = "전체" }, { id = "rent", label = "월세" }, { id = "buy", label = "매매" } },
			value = "all",
			order = 3,
			onChange = function(id: string)
				filter = id
				listKey = ""
				refresh()
			end,
		})
		local _ = seg
		listHolder = K.frame(content, { Name = "Listings", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 })
		K.list(listHolder, false, 8)

		Net.on("profile", function(changed: any)
			if changed.home or changed.money or changed.cash or changed.bank then
				listKey = ""
				refresh()
			end
		end)
		Net.on("status", function()
			refresh()
		end)
		ctx.phone.onLayout(function()
			local l = ctx.phone.layout()
			scroll.Position = UDim2.fromOffset(0, l.headerH)
			scroll.Size = UDim2.new(1, 0, 1, -l.headerH)
		end)
	end

	function app.show()
		visible = true
		atHome = computeAtHome()
		listKey = ""
		refresh()
		startLoop()
	end

	function app.hide()
		visible = false
		loopSerial += 1
	end

	return app
end
