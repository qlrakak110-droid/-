-- 메시지: pending offers (profile.offers: 수락 / 거절 cards), the thread list (avatar, name, last
-- message, time, unread badge) and a chat view (bubbles with date separators, an offer card with
-- 수락 / 거절 when the thread carries an offer, reply choices instead of a keyboard, typing dots).
-- Built with the GwangalliUI kit.
--   PhoneAction "readThread" {contactId}, "reply" {contactId, choice} (choice id or 1-based index)

return function(ctx: any)
	local K, Data, Net, AppKit = ctx.K, ctx.Data, ctx.Net, ctx.AppKit

	local app = {}
	local listView: Frame
	local listScroll: ScrollingFrame
	local conn: any
	local chatView: Frame
	local chatHeader: any
	local chatScroll: ScrollingFrame
	local replyBar: Frame
	local openId: string? = nil
	local visible = false
	local pending: { [string]: number } = {} -- contact -> os.clock() of a sent reply (typing dots)
	local lastReadSent: { [string]: number } = {}
	local listKey = ""
	local chatKey = ""

	local function threads(): { any }
		return Data.threads(Net.profile.messages)
	end

	local function findThread(key: any): any
		if key == nil then
			return nil
		end
		local ts = threads()
		for _, th in ts do
			if th.id == key then
				return th
			end
		end
		local c = Data.contact(key)
		for _, th in ts do
			if th.name == c.name or th.id == c.id then
				return th
			end
		end
		return nil
	end

	local function offers(): { any }
		local o = Net.profile.offers
		local out = {}
		if type(o) == "table" then
			for _, v in o do
				if type(v) == "table" and v.id then
					table.insert(out, v)
				end
			end
		end
		return out
	end

	local function offerFor(contactId: string?, offerId: any): any
		for _, o in offers() do
			if (offerId and o.id == offerId) or (not offerId and o.contact == contactId) then
				return o
			end
		end
		return nil
	end

	local function isPending(id: string): boolean
		local t = pending[id]
		return t ~= nil and os.clock() - t < 5
	end

	local function sendReply(contactId: string, choice: any)
		local ok, err = Net.send("reply", { contactId = contactId, contact = contactId, choice = choice })
		if ok then
			pending[contactId] = os.clock()
			K.feedback("success")
			chatKey, listKey = "", ""
			task.delay(5.1, function()
				chatKey, listKey = "", ""
				app.refresh()
			end)
			app.refresh()
		else
			ctx.phone.toast({ app = "messages", title = "메시지", body = err or "보낼 수 없어요", kind = "error", silent = true })
		end
	end

	---------------------------------------------------------------------------------------------------
	-- Offer card (list + chat)
	---------------------------------------------------------------------------------------------------
	local function offerCard(parent: Instance, o: any, order: number, compact: boolean?): Frame
		local c = Data.contact(o.contact)
		local card = K.frame(parent, { Name = "Offer_" .. tostring(o.id), Size = UDim2.new(1, 0, 0, if compact then 122 else 132), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = order })
		K.corner(card, K.Radius.md)
		K.gradient(card, { Color3.fromRGB(52, 44, 20), Color3.fromRGB(28, 28, 40) }, 110)
		K.stroke(card, K.Color.gold, 1, 0.55)
		local av = K.avatar(card, 36, c.glyph, c.color)
		av.Position = UDim2.fromOffset(12, 12)
		K.text(card, { Name = "Title", Position = UDim2.fromOffset(58, 11), Size = UDim2.new(1, -130, 0, 18), Text = tostring(o.title or "제안"), Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd })
		K.text(card, { Name = "From", Position = UDim2.fromOffset(58, 29), Size = UDim2.new(1, -130, 0, 15), Text = c.name .. " · " .. c.role, TextColor3 = K.Color.gold, TextSize = K.Type.micro, Font = K.Font.bold, TextTruncate = Enum.TextTruncate.AtEnd })
		K.Pill(card, { name = "Kind", text = if o.kind == "applyJob" then "알바 제안" elseif o.kind == "clubPass" then "초대" elseif o.kind == "meet" then "약속" else "안내", color = K.Color.gold }).Position = UDim2.new(1, -72, 0, 12)
		K.text(card, { Name = "Body", Position = UDim2.fromOffset(12, 54), Size = UDim2.new(1, -24, 0, 30), Text = tostring(o.body or ""), TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd })
		local busy = isPending(o.contact)
		local decline = K.Button(card, { name = "Decline", text = "거절", style = "secondary", anchor = Vector2.new(0, 1), position = UDim2.new(0, 12, 1, -10), size = UDim2.new(0.38, -12, 0, 40), textSize = K.Type.caption + 1 })
		local accept = K.Button(card, { name = "Accept", text = "수락", style = "gold", anchor = Vector2.new(1, 1), position = UDim2.new(1, -12, 1, -10), size = UDim2.new(0.62, -12, 0, 40), textSize = K.Type.caption + 1 })
		decline.Size = UDim2.new(0.38, -12, 0, 44)
		accept.Size = UDim2.new(0.62, -12, 0, 44)
		if busy then
			K.setButtonLoading(accept, true, "보내는 중…")
			K.setButtonEnabled(decline, false)
		end
		accept.Activated:Connect(function()
			if not accept:GetAttribute("Disabled") then
				sendReply(o.contact, "accept")
			end
		end)
		decline.Activated:Connect(function()
			if not decline:GetAttribute("Disabled") then
				sendReply(o.contact, "decline")
			end
		end)
		return card
	end

	---------------------------------------------------------------------------------------------------
	-- List view
	---------------------------------------------------------------------------------------------------
	local function renderList()
		local ready = conn.update()
		local ts = threads()
		local os_ = offers()
		local key = AppKit.keyOf(ts, function(th)
			return th.id .. ":" .. th.unread .. ":" .. tostring(th.lastT) .. ":" .. th.lastText
		end) .. "|" .. AppKit.keyOf(os_, function(o)
			return tostring(o.id) .. (if isPending(o.contact) then "p" else "")
		end) .. tostring(ready)
		if key == listKey then
			return
		end
		listKey = key
		AppKit.clear(listScroll, { [conn.frame] = true })
		if not ready then
			return
		end
		local order = 1
		local rows = {}
		if #os_ > 0 then
			K.SectionHeader(listScroll, { title = string.format("받은 제안 %d", #os_), order = order })
			order += 1
			for _, o in os_ do
				table.insert(rows, offerCard(listScroll, o, order))
				order += 1
			end
		end
		if #ts == 0 then
			K.EmptyState(listScroll, { order = order, icon = "💬", title = "아직 받은 메시지가 없어요", body = "친구와 사장님들이 곧 연락할 거예요" })
			return
		end
		K.SectionHeader(listScroll, { title = "대화", order = order })
		order += 1
		local card = K.Card(listScroll, { Name = "Threads", Size = UDim2.new(1, 0, 0, #ts * 66), LayoutOrder = order, ClipsDescendants = true })
		K.list(card, false, 0)
		for i, th in ts do
			local row = K.make("TextButton", { Name = "Thread_" .. th.id, Size = UDim2.new(1, 0, 0, 66), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = i }, card)
			local av = K.avatar(row, 44, th.glyph, th.color)
			av.AnchorPoint = Vector2.new(0, 0.5)
			av.Position = UDim2.new(0, 10, 0.5, 0)
			local nameW = math.min(170, math.ceil(K.textSize(th.name, K.Type.bodySm, K.Font.bold).X) + 4)
			K.text(row, { Name = "Name", Position = UDim2.fromOffset(64, 12), Size = UDim2.fromOffset(nameW, 18), Text = th.name, Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd })
			if th.role ~= "" then
				K.text(row, { Name = "Role", Position = UDim2.fromOffset(64 + nameW + 6, 13), Size = UDim2.new(1, -(64 + nameW + 6 + 70), 0, 16), Text = th.role, TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
			end
			K.text(row, { Name = "Preview", Position = UDim2.fromOffset(64, 33), Size = UDim2.new(1, -110, 0, 18), Text = if th.lastText ~= "" then th.lastText else "새 대화", TextColor3 = if th.unread > 0 then K.Color.text else K.Color.sub, TextSize = K.Type.caption, TextTruncate = Enum.TextTruncate.AtEnd })
			K.text(row, { Name = "Time", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 13), Size = UDim2.fromOffset(62, 14), Text = Data.timeText(th.lastT), TextColor3 = if th.unread > 0 then K.Color.cyan else K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Right })
			local badge = K.Badge(row, { size = 20, position = UDim2.new(1, -12, 0, 42), anchor = Vector2.new(1, 0.5) })
			badge.set(th.unread)
			if #th.choices > 0 then
				K.Pill(row, { name = "NeedsReply", text = "답장 필요", color = K.Color.gold, height = 18 }).Position = UDim2.new(1, -80, 0, 32)
			end
			if i < #ts then
				K.frame(row, { Name = "Hairline", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 64, 1, 0), Size = UDim2.new(1, -64, 0, 1), BackgroundTransparency = 0.93, BackgroundColor3 = K.Color.line })
			end
			K.pressable(row, { scale = 0.985 })
			row.Activated:Connect(function()
				app.openChat(th.id)
			end)
			table.insert(rows, row)
		end
		K.stagger(rows)
	end

	---------------------------------------------------------------------------------------------------
	-- Chat view
	---------------------------------------------------------------------------------------------------
	local KOR_DAYS = { "일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일" }
	local function dayLabel(t: number?): string
		if type(t) ~= "number" or t < 1e8 then
			return "오늘"
		end
		local ok, d = pcall(os.date, "*t", math.floor(t))
		local okN, n = pcall(os.date, "*t", math.floor(workspace:GetServerTimeNow()))
		if not (ok and okN and type(d) == "table" and type(n) == "table") then
			return "오늘"
		end
		if d.year == n.year and d.yday == n.yday then
			return "오늘"
		elseif d.year == n.year and d.yday == n.yday - 1 then
			return "어제"
		end
		return string.format("%d월 %d일 %s", d.month, d.day, KOR_DAYS[d.wday] or "")
	end

	local function replyChoices(th: any): { any }
		if not th then
			return {}
		end
		return th.choices or {}
	end

	local function renderReplies(th: any): number
		AppKit.clear(replyBar)
		local choices = replyChoices(th)
		local offerMode = th and th.offerId ~= nil
		if #choices == 0 or offerMode then
			-- the offer card inside the chat carries the answer; otherwise a disabled field
			local field = K.frame(replyBar, { Name = "Field", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.new(1, -24, 0, 36), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card })
			K.corner(field, UDim.new(0.5, 0))
			K.text(field, { Name = "Hint", Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), Text = if offerMode then "위 제안에 수락 / 거절로 답해 주세요" else "답장할 수 있는 메시지가 오면 여기에 떠요", TextColor3 = K.Color.faint, TextSize = K.Type.caption, TextTruncate = Enum.TextTruncate.AtEnd })
			return 48
		end
		local busy = th and isPending(th.id)
		local holder = K.make("ScrollingFrame", { Name = "Choices", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 0 }, replyBar)
		K.list(holder, true, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		K.pad(holder, 12, 12, 0, 0)
		for i, choice in choices do
			local w = math.clamp(math.ceil(K.textSize(choice.label, K.Type.caption + 1, K.Font.bold).X) + 32, 72, 220)
			local b = K.Button(holder, { name = "Reply" .. i, text = choice.label, style = if i == 1 then "primary" else "secondary", size = UDim2.fromOffset(w, 44), order = i, textSize = K.Type.caption + 1 })
			if busy then
				K.setButtonEnabled(b, false)
			end
			b.Activated:Connect(function()
				if not b:GetAttribute("Disabled") and th then
					sendReply(th.id, choice.value)
				end
			end)
		end
		return 56
	end

	-- Chat rows in a vertical list: every bubble is fixed-width (measured) with an automatic height,
	-- so wrapped text always fits. Returns nothing; the canvas sizes itself.
	local function bubbles(th: any, parentW: number)
		AppKit.clear(chatScroll)
		local msgs = th.msgs
		local first = math.max(1, #msgs - 59)
		local maxW = math.floor(math.min(parentW * 0.72, 300))
		local order = 0
		local function row(name: string, h: number?): Frame
			order += 1
			return K.frame(chatScroll, { Name = name, Size = UDim2.new(1, 0, 0, h or 0), AutomaticSize = if h then Enum.AutomaticSize.None else Enum.AutomaticSize.Y, LayoutOrder = order })
		end
		local lastDay = nil
		for i = first, #msgs do
			local m = msgs[i]
			local prev = msgs[i - 1]
			local nextM = msgs[i + 1]
			local day = dayLabel(m.t)
			if day ~= lastDay then
				lastDay = day
				local r = row("DateRow", 30)
				local w = math.ceil(K.textSize(day, K.Type.micro, K.Font.bold).X) + 24
				local sep = K.text(r, { Name = "DateSeparator", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, 20), BackgroundTransparency = 0.2, BackgroundColor3 = K.Color.card2, Text = day, TextColor3 = K.Color.sub, Font = K.Font.bold, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center })
				K.corner(sep, UDim.new(0.5, 0))
			end
			local startRun = i == first or not prev or prev.me ~= m.me or prev.sys ~= m.sys or dayLabel(prev.t) ~= day
			local endRun = not nextM or nextM.me ~= m.me or nextM.sys ~= m.sys
			if m.sys then
				local r = row("SystemRow")
				local sw = math.min(parentW - 40, math.ceil(K.textWidth(m.text, K.Type.micro)) + 28)
				local pill = K.text(r, { Name = "System", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(sw, K.textHeight(m.text, K.Type.micro, sw - 20) + 10), BackgroundTransparency = 0.3, BackgroundColor3 = K.Color.card2, Text = m.text, TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })
				K.corner(pill, 10)
				K.pad(pill, 10, 10, 5, 5)
				continue
			end
			if startRun and i ~= first then
				row("Gap", 4)
			end
			local fs = K.Type.caption + 1
			local tw = math.ceil(K.textWidth(m.text, fs))
			local bw = math.clamp(tw + 30, 44, maxW)
			local bh = K.textHeight(m.text, fs, bw - 26) + 16
			local when = if endRun then Data.msgTime(m) else ""
			if not m.me and startRun then
				local head = row("SenderRow", 34)
				K.avatar(head, 30, th.glyph, th.color, { Position = UDim2.fromOffset(12, 2) })
				K.text(head, { Name = "Sender", Position = UDim2.fromOffset(50, 18), Size = UDim2.fromOffset(200, 15), Text = th.name, TextColor3 = K.Color.sub, TextSize = K.Type.micro, Font = K.Font.bold })
			end
			local r = row(if m.me then "OutRow" else "InRow")
			local line = K.frame(r, { Name = "Line", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
			K.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), HorizontalAlignment = if m.me then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left, VerticalAlignment = Enum.VerticalAlignment.Bottom }, line)
			K.pad(line, if m.me then 0 else 50, if m.me then 12 else 0, 0, 0)
			local bubble = K.text(line, { Name = if m.me then "Out" else "In", Size = UDim2.fromOffset(bw, bh), BackgroundTransparency = 0, BackgroundColor3 = if m.me then Color3.new(1, 1, 1) else K.Color.card2, Text = m.text, TextColor3 = if m.me then K.Color.onAccent else K.Color.text, TextSize = K.Type.caption + 1, Font = K.Font.medium, TextWrapped = true, LayoutOrder = if m.me then 2 else 1 })
			if m.me then
				K.gradient(bubble, K.Grad.primary, 15)
			end
			K.corner(bubble, 16)
			K.pad(bubble, 12, 12, 8, 8)
			if when ~= "" then
				K.text(line, { Name = "Time", Size = UDim2.fromOffset(52, 14), Text = when, TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = if m.me then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left, LayoutOrder = if m.me then 1 else 2 })
			end
		end
		-- offer card at the end of the thread
		if th.offerId ~= nil then
			local o = offerFor(th.id, th.offerId) or { id = th.offerId, contact = th.id, title = "제안", body = (msgs[#msgs] and msgs[#msgs].text) or "", kind = "info" }
			local r = row("OfferRow", 132)
			local holder = K.frame(r, { Name = "OfferHolder", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 122) })
			offerCard(holder, o, 1, true).Size = UDim2.new(1, 0, 0, 122)
		end
		if isPending(th.id) then
			local r = row("TypingRow", 38)
			local dots = K.text(r, { Name = "Typing", Position = UDim2.fromOffset(50, 4), Size = UDim2.fromOffset(54, 30), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card2, Text = "• • •", TextColor3 = K.Color.sub, TextSize = K.Type.bodySm, TextXAlignment = Enum.TextXAlignment.Center })
			K.corner(dots, 15)
		end
		if #msgs == 0 then
			local r = row("EmptyRow", 124)
			K.EmptyState(r, { compact = true, icon = "👋", title = "대화를 시작해 보세요", body = "" })
		end
		row("End", 8)
	end

	local function scrollToEnd()
		task.defer(function()
			local ok = pcall(function()
				local lay = chatScroll:FindFirstChildOfClass("UIListLayout")
				local contentH = if lay then lay.AbsoluteContentSize.Y else 0
				chatScroll.CanvasPosition = Vector2.new(0, math.max(0, contentH - chatScroll.AbsoluteSize.Y))
			end)
			if not ok then
				chatScroll.CanvasPosition = Vector2.zero
			end
		end)
	end

	local function renderChat()
		local th = findThread(openId)
		local L = ctx.phone.layout()
		if not th then
			local c = Data.contact(openId)
			chatHeader.title.Text = c.name
			chatHeader.setSubtitle(c.role)
			local h = renderReplies(nil)
			chatScroll.Size = UDim2.new(1, 0, 1, -(L.headerH + h))
			replyBar.Size = UDim2.new(1, 0, 0, h)
			bubbles({ msgs = {}, glyph = c.glyph, color = c.color, name = c.name, id = c.id }, L.screenW)
			return
		end
		local key = th.id .. ":" .. #th.msgs .. ":" .. tostring(th.lastT) .. ":" .. #th.choices .. ":" .. tostring(th.offerId) .. ":" .. tostring(isPending(th.id))
		chatHeader.title.Text = th.name
		chatHeader.setSubtitle(th.role)
		if key ~= chatKey then
			chatKey = key
			local h = renderReplies(th)
			replyBar.Size = UDim2.new(1, 0, 0, h)
			chatScroll.Position = UDim2.fromOffset(0, L.headerH)
			chatScroll.Size = UDim2.new(1, 0, 1, -(L.headerH + h))
			bubbles(th, L.screenW)
			scrollToEnd()
		end
		if th.unread > 0 and os.clock() - (lastReadSent[th.id] or -10) > 2 then
			lastReadSent[th.id] = os.clock()
			Net.send("readThread", { contactId = th.id, contact = th.id })
		end
	end

	---------------------------------------------------------------------------------------------------
	-- API
	---------------------------------------------------------------------------------------------------
	function app.refresh()
		if not visible then
			return
		end
		if openId then
			renderChat()
		else
			renderList()
		end
	end

	-- list -> chat pushes (the list drifts left under a veil), back pops; opening straight into a chat
	-- (from a notification) appears without a transition
	function app.openChat(id: string, instant: boolean?)
		openId = id
		chatKey = ""
		if instant or not listView.Visible then
			listView.Visible = false
			chatView.Visible = true
			chatView.Position = UDim2.fromScale(0, 0)
		else
			K.pushPage(chatView, listView)
		end
		renderChat()
	end

	local function showList()
		openId = nil
		listKey = ""
		if chatView.Visible then
			K.popPage(chatView, listView)
		else
			listView.Visible = true
		end
		renderList()
	end

	function app.build(body: Frame)
		local L = ctx.phone.layout()
		listView = K.frame(body, { Name = "List", Size = UDim2.fromScale(1, 1) })
		ctx.phone.header(listView, "메시지")
		listScroll = AppKit.scroll(listView, L.headerH, { name = "Threads", gap = 8, topPad = 2 })
		conn = AppKit.conn(listScroll, ctx, 0)

		chatView = K.frame(body, { Name = "Chat", Size = UDim2.fromScale(1, 1), Visible = false, BackgroundTransparency = 0, BackgroundColor3 = K.Color.bg })
		chatHeader = ctx.phone.header(chatView, "", {
			subtitle = "",
			onBack = function(): boolean
				showList()
				return true
			end,
		})
		chatScroll = K.make("ScrollingFrame", {
			Name = "Bubbles",
			Position = UDim2.fromOffset(0, L.headerH),
			Size = UDim2.new(1, 0, 1, -(L.headerH + 48)),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(14, 17, 28),
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = K.Color.sub,
		}, chatView)
		K.list(chatScroll, false, 4)
		K.pad(chatScroll, 0, 0, 6, 6)
		replyBar = K.frame(chatView, { Name = "Replies", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 0, BackgroundColor3 = K.Color.bg })

		Net.on("profile", function(changed: any)
			if changed.messages or changed.offers or changed.threads then
				for id in pending do
					pending[id] = nil
				end
				listKey, chatKey = "", ""
				app.refresh()
			end
		end)
		Net.on("status", function()
			listKey = ""
			app.refresh()
		end)
		Data.onLoaded(app.refresh)
		ctx.phone.onLayout(function()
			local l = ctx.phone.layout()
			listScroll.Position = UDim2.fromOffset(0, l.headerH)
			listScroll.Size = UDim2.new(1, 0, 1, -l.headerH)
			listKey, chatKey = "", ""
			app.refresh()
		end)
	end

	function app.show(args: any)
		visible = true
		if type(args) == "table" and args.contact ~= nil then
			local th = findThread(args.contact)
			app.openChat(if th then th.id else tostring(args.contact), true)
			return
		end
		listKey = ""
		app.refresh()
	end

	function app.hide()
		visible = false
	end

	return app
end
