-- 쇼핑 / 옷장: every item of GwangalliGameplayShared.ITEMS, grouped like the real places that sell
-- them (배달 anywhere · 매점 · 옷 · 헤어 · 맛집), plus 옷장 (owned outfits / hair -> 입기 = PhoneAction
-- "equip" {itemId}). The server decides purchases ("buy" {itemId}): shop items need the player near a
-- matching ShopCounter / SalonChair, place items near their Destination; elsewhere the button offers
-- "🚕 가기" (taxi to the place). Buying takes two taps (the button turns into "결제 확인" for 3 s).
-- A ShopCounter prompt sends Notify {shop}; tapping that toast opens this app on that tab.
-- Built with the GwangalliUI kit.

local CollectionService = game:GetService("CollectionService")

return function(ctx: any)
	local K, Data, Net, Dest, AppKit = ctx.K, ctx.Data, ctx.Net, ctx.Dest, ctx.AppKit

	local TABS = {
		{ id = "delivery", text = "배달", icon = "🛵" },
		{ id = "gym_store", text = "매점", icon = "🥤" },
		{ id = "clothing", text = "옷", icon = "👕" },
		{ id = "salon", text = "헤어", icon = "💇" },
		{ id = "places", text = "맛집", icon = "🍔" },
		{ id = "wardrobe", text = "옷장", icon = "🧥" },
	}
	local TAB_INFO = {
		delivery = "어디서나 주문하면 바로 배달돼요",
		gym_store = "광안 휘트니스 24 매점 카운터에서 살 수 있어요",
		clothing = "헤어살롱 & 편집숍 의류 카운터에서 살 수 있어요",
		salon = "헤어살롱 & 편집숍 헤어 의자에서 할 수 있어요",
		places = "각 가게 앞에서 주문할 수 있어요",
		wardrobe = "산 옷과 헤어를 골라 입어요",
	}
	local GLYPH = {
		protein = "🥤",
		energy_drink = "⚡",
		chicken_box = "🍱",
		water = "💧",
		millac_burger = "🍔",
		sup_rental = "🏄",
		bread_set = "🥐",
		gs25_snack = "🍙",
		americano = "☕",
		hoe_platter = "🐟",
		delivery_chicken = "🍗",
		cup_ramen = "🍜",
	}
	local TAB_COLOR = { delivery = K.Color.orange, gym_store = K.Color.green, clothing = K.Color.violet, salon = K.Color.magenta, places = K.Color.gold, wardrobe = K.Color.cyan }

	local app = {}
	local header: any
	local chipApis: { [string]: any } = {}
	local info: TextLabel
	local listScroll: ScrollingFrame
	local conn: any
	local itemsHolder: Frame
	local tab = "delivery"
	local visible = false
	local armed: { id: string, at: number }? = nil
	local waiting: { [string]: number } = {}
	local nearKey = ""
	local loopSerial = 0

	local function rootPos(): Vector3?
		local char = ctx.player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root.Position else nil
	end

	local function tabOf(it: any): string?
		if it.phone then
			return "delivery"
		elseif it.shop == "gym_store" or it.shop == "clothing" or it.shop == "salon" then
			return it.shop
		elseif it.nearDest then
			return "places"
		end
		return nil
	end

	local function nearShop(shopId: string, from: Vector3): boolean
		local reach = Data.shopReach() + 6
		local tags = if shopId == "salon" then { "ShopCounter", "SalonChair" } else { "ShopCounter" }
		for _, tag in tags do
			for _, inst in CollectionService:GetTagged(tag) do
				if tag == "SalonChair" or inst:GetAttribute("ShopId") == shopId then
					local p: Vector3? = nil
					if inst:IsA("BasePart") then
						p = inst.Position
					elseif inst:IsA("Model") then
						local ok, cf = pcall(inst.GetPivot, inst)
						p = if ok then cf.Position else nil
					end
					if p and (p - from).Magnitude <= reach then
						return true
					end
				end
			end
		end
		return false
	end

	local function nearPlace(dest: string, from: Vector3): boolean
		local p = Dest.position(dest)
		return p ~= nil and (p - from).Magnitude <= Data.nearDestRadius() + 5
	end

	local function canBuyHere(it: any, from: Vector3?): boolean
		if it.phone then
			return true
		end
		if not from then
			return false
		end
		if it.shop then
			return nearShop(it.shop, from)
		elseif it.nearDest then
			return nearPlace(it.nearDest, from)
		end
		return false
	end

	local function placeOf(it: any): string?
		if it.nearDest then
			return it.nearDest
		elseif it.shop then
			return Data.SHOP_DEST and Data.SHOP_DEST[it.shop] or nil
		end
		return nil
	end

	local function owned(it: any): boolean
		local o = Net.profile.owned
		if type(o) ~= "table" or not it.ref then
			return false
		end
		if it.kind == "outfit" then
			return type(o.outfits) == "table" and o.outfits[it.ref] == true
		elseif it.kind == "hair" then
			return type(o.hair) == "table" and o.hair[it.ref] == true
		end
		return false
	end

	local function wearing(it: any): boolean
		if it.kind == "outfit" then
			return it.ref ~= nil and Net.profile.outfit == it.ref
		elseif it.kind == "hair" then
			return it.ref ~= nil and Net.profile.hair == it.ref
		end
		return false
	end

	local function invCount(id: string): number
		local inv = Net.profile.inventory
		local v = type(inv) == "table" and inv[id] or nil
		return if type(v) == "number" then v else 0
	end

	local function itemsFor(which: string): { any }
		local out = {}
		for _, it in Data.items() do
			if which == "wardrobe" then
				if (it.kind == "outfit" or it.kind == "hair") and owned(it) then
					table.insert(out, it)
				end
			elseif tabOf(it) == which then
				table.insert(out, it)
			end
		end
		return out
	end

	local function glyphOf(it: any): string
		if it.kind == "outfit" then
			return "👕"
		elseif it.kind == "hair" then
			return "💇"
		end
		return GLYPH[it.id] or "🛍️"
	end

	local render: () -> ()

	local function sendAction(action: string, it: any)
		local ok, err = Net.send(action, { itemId = it.id })
		if ok then
			waiting[it.id] = os.clock()
			K.feedback(if action == "buy" then "money" else "success")
			task.delay(4, function()
				if waiting[it.id] and os.clock() - waiting[it.id] >= 3.9 then
					waiting[it.id] = nil
					if visible then
						render()
					end
				end
			end)
		else
			ctx.phone.toast({ app = "shop", title = "쇼핑", body = err or "지금은 살 수 없어요", kind = "error", silent = true })
		end
	end

	local function onItem(it: any, mode: string)
		if mode == "equip" then
			sendAction("equip", it)
		elseif mode == "buy" then
			if armed and armed.id == it.id and os.clock() - armed.at < 3 then
				armed = nil
				sendAction("buy", it)
			else
				armed = { id = it.id, at = os.clock() }
				task.delay(3.1, function()
					if armed and armed.id == it.id and os.clock() - armed.at >= 3 then
						armed = nil
						if visible then
							render()
						end
					end
				end)
			end
		elseif mode == "go" then
			local place = placeOf(it)
			if place then
				ctx.phone.launch("taxi", { destination = place })
			end
		end
		render()
	end

	render = function()
		if not visible then
			return
		end
		for id, api in chipApis do
			api.set(id == tab)
		end
		local ready = conn.update()
		header.setSubtitle(if Net.hasProfile then "현금 " .. K.won(ctx.Life.cash(Net.profile)) else "연결 중…")
		itemsHolder.Visible = ready
		AppKit.clear(itemsHolder)
		local from = rootPos()
		local list = itemsFor(tab)
		local nearAny = false
		local keyParts = {}
		local cash = ctx.Life.cash(Net.profile)
		local rows = {}
		for i, it in list do
			local here = canBuyHere(it, from)
			nearAny = nearAny or (here and not it.phone)
			table.insert(keyParts, if here then "1" else "0")
			local card = K.Card(itemsHolder, { Name = "Item_" .. it.id, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = i })
			local icon = K.iconTile(card, 40, glyphOf(it), TAB_COLOR[tabOf(it) or tab] or K.Color.cyan)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 10, 0.5, 0)
			K.text(card, { Name = "Name", Position = UDim2.fromOffset(60, 8), Size = UDim2.new(1, -146, 0, 18), Text = it.name, Font = K.Font.bold, TextSize = K.Type.caption + 1, TextTruncate = Enum.TextTruncate.AtEnd })
			local cnt = invCount(it.id)
			local sub = it.desc
			if cnt > 0 then
				sub = string.format("보유 %s · %s", Data.int(cnt), sub)
			end
			K.text(card, { Name = "Desc", Position = UDim2.fromOffset(60, 26), Size = UDim2.new(1, -146, 0, 15), Text = sub, TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
			local price = K.text(card, { Name = "Price", Position = UDim2.fromOffset(60, 42), Size = UDim2.new(1, -146, 0, 15), Text = if it.price > 0 then K.won(it.price) else "무료", TextColor3 = K.Color.gold, Font = K.Font.bold, TextSize = K.Type.micro })
			K.mono(price)
			local mode, text, style = "none", "", "secondary"
			local isOwned = owned(it)
			if waiting[it.id] then
				text = "처리 중…"
			elseif (it.kind == "outfit" or it.kind == "hair") and wearing(it) then
				text = "착용 중 ✓"
			elseif (it.kind == "outfit" or it.kind == "hair") and isOwned then
				mode, text, style = "equip", "입기", "tonal"
			elseif here then
				if Net.hasProfile and cash < it.price then
					text = "잔액 부족"
				elseif armed and armed.id == it.id then
					mode, text, style = "buy", "결제 확인", "gold"
				else
					mode, text, style = "buy", "구매", "primary"
				end
			elseif placeOf(it) then
				mode, text, style = "go", "🚕 가기", "secondary"
			end
			local b = K.Button(card, { name = "Action_" .. it.id, text = text, style = style, anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -8, 0.5, 0), size = UDim2.fromOffset(74, 44), textSize = K.Type.caption })
			if mode == "none" then
				K.setButtonEnabled(b, false)
			else
				b.Activated:Connect(function()
					onItem(it, mode)
				end)
			end
			table.insert(rows, card)
		end
		if #list == 0 then
			if tab == "wardrobe" then
				K.EmptyState(itemsHolder, { order = 1, compact = true, icon = "🧥", title = "옷장이 비어 있어요", body = "편집숍에서 옷이나 헤어를 사 보세요" })
			else
				K.EmptyState(itemsHolder, { order = 1, compact = true, icon = "🛍️", title = if Data.Shared then "판매 중인 상품이 없어요" else "상품 정보를 불러오는 중…", body = "" })
			end
		end
		nearKey = tab .. ":" .. table.concat(keyParts)
		if tab ~= "delivery" and tab ~= "wardrobe" and nearAny then
			K.setText(info, "📍 매장 근처예요 · 여기서 바로 살 수 있어요")
			info.TextColor3 = K.Color.green
		else
			K.setText(info, TAB_INFO[tab] or "")
			info.TextColor3 = K.Color.sub
		end
		return
	end

	local function startLoop()
		loopSerial += 1
		local mine = loopSerial
		task.spawn(function()
			while visible and loopSerial == mine do
				task.wait(1)
				if not (visible and loopSerial == mine) then
					break
				end
				local from = rootPos()
				local parts = {}
				for _, it in itemsFor(tab) do
					table.insert(parts, if canBuyHere(it, from) then "1" else "0")
				end
				if tab .. ":" .. table.concat(parts) ~= nearKey then
					render()
				end
			end
		end)
	end

	local function layout()
		local L = ctx.phone.layout()
		local tabsBar = listScroll.Parent:FindFirstChild("Tabs") :: ScrollingFrame?
		if tabsBar then
			tabsBar.Position = UDim2.fromOffset(0, L.headerH)
		end
		info.Position = UDim2.fromOffset(14, L.headerH + 46)
		listScroll.Position = UDim2.fromOffset(0, L.headerH + 66)
		listScroll.Size = UDim2.new(1, 0, 1, -(L.headerH + 66))
	end

	function app.build(body: Frame)
		local L = ctx.phone.layout()
		header = ctx.phone.header(body, "쇼핑", { subtitle = "" })
		local tabsBar = K.make("ScrollingFrame", { Name = "Tabs", Position = UDim2.fromOffset(0, L.headerH), Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 0 }, body)
		K.pad(tabsBar, 12, 12, 0, 0)
		K.list(tabsBar, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		for i, t in TABS do
			chipApis[t.id] = K.Chip(tabsBar, {
				name = "Tab_" .. t.id,
				text = t.text,
				icon = t.icon,
				color = TAB_COLOR[t.id],
				selected = t.id == tab,
				order = i,
				onClick = function()
					tab = t.id
					armed = nil
					listScroll.CanvasPosition = Vector2.zero
					render()
				end,
			})
		end
		info = K.text(body, { Name = "Info", Size = UDim2.new(1, -28, 0, 16), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
		listScroll = AppKit.scroll(body, L.headerH + 66, { name = "Items", gap = 8, topPad = 2 })
		conn = AppKit.conn(listScroll, ctx, 0)
		itemsHolder = K.frame(listScroll, { Name = "ItemList", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
		K.list(itemsHolder, false, 8)
		layout()

		Net.on("profile", function(changed: any)
			if changed.money or changed.cash or changed.inventory or changed.owned or changed.outfit or changed.hair then
				table.clear(waiting)
				render()
			end
		end)
		Net.on("status", render)
		Data.onLoaded(render)
		ctx.phone.onLayout(function()
			layout()
			render()
		end)
	end

	function app.show(args: any)
		visible = true
		if type(args) == "table" and type(args.shop) == "string" then
			for _, t in TABS do
				if t.id == args.shop then
					tab = t.id
				end
			end
			listScroll.CanvasPosition = Vector2.zero
		end
		armed = nil
		layout()
		render()
		startLoop()
	end

	function app.hide()
		visible = false
		loopSerial += 1
		armed = nil
	end

	return app
end
