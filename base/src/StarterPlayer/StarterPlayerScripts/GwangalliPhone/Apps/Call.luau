-- 전화: 즐겨찾기 / 연락처 / 최근 tabs and a full-screen call screen (pulsing avatar, call timer,
-- mute / speaker / keypad toggles, big end button). Built with the GwangalliUI kit only.
--   광안 콜택시 -> call screen -> PhoneAction "callTaxi" -> the 택시 app (dispatch, ETA, fare)
--   a person   -> call screen -> PhoneAction "callContact" {contactId}; the server answers with a
--                 Dialog (remote = true), which closes the phone and opens the dialog sheet. No
--                 answer in 7 s -> "전화를 받지 않아요".
-- 최근: this session's calls (outgoing / missed, duration).

return function(ctx: any)
	local K, Net, Life, AppKit = ctx.K, ctx.Net, ctx.Life, ctx.AppKit

	local app = {}
	local root: Frame
	local bodyRef: Frame? = nil
	local tabs: any
	local views: { [string]: ScrollingFrame } = {}
	local favKey, contactsKey, recentsKey = "", "", ""
	local calls: { any } = {} -- recents, newest first
	local visible = false
	local tab = "favorites"

	-- call screen
	local callView: Frame
	local callName: TextLabel
	local callRole: TextLabel
	local callState: TextLabel
	local callTimer: TextLabel
	local callAvatar: Frame
	local rings: { Frame } = {}
	local callSerial = 0
	local inCall: any = nil

	local function contacts(): { any }
		return Life.contacts(Net.profile.contacts)
	end

	local function byId(id: string): any
		for _, c in contacts() do
			if c.id == id then
				return c
			end
		end
		return nil
	end

	local function kindOf(c: any): string
		if c.kind == "taxi" or c.id == "taxi" then
			return "service"
		end
		local G = ctx.Data.Shared
		local def = G and G.CONTACTS and G.CONTACTS[c.id]
		return (def and def.kind) or "npc"
	end

	---------------------------------------------------------------------------------------------------
	-- Call screen
	---------------------------------------------------------------------------------------------------
	local function fmtDur(s: number): string
		s = math.max(0, math.floor(s))
		return string.format("%02d:%02d", s // 60, s % 60)
	end

	local function logCall(c: any, status: string, dur: number)
		table.insert(calls, 1, { id = c.id, name = c.name, glyph = c.glyph, color = c.color, status = status, dur = dur, at = os.clock() })
		while #calls > 20 do
			table.remove(calls)
		end
		recentsKey = ""
	end

	local function endCall(status: string?)
		callSerial += 1
		local c = inCall
		if c then
			logCall(c.contact, status or c.status or "ended", os.clock() - (c.started or os.clock()))
		end
		inCall = nil
		if bodyRef then
			bodyRef.Visible = true
		end
		if callView.Visible then
			K.tween(callView, 0.2, { Position = UDim2.fromScale(0, 0.06) })
			task.delay(0.12, function()
				if not inCall then
					callView.Visible = false
					callView.Position = UDim2.fromScale(0, 0)
				end
			end)
		end
		if visible then
			app.refresh()
		end
	end

	local function pulseRings(mine: number)
		task.spawn(function()
			while callSerial == mine and inCall and not inCall.started do
				for i, r in rings do
					if callSerial ~= mine then
						return
					end
					r.Size = UDim2.fromOffset(88, 88)
					r.BackgroundTransparency = 0.6
					K.tween(r, 1.1, { Size = UDim2.fromOffset(160, 160), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
					task.wait(0.35 + (i - 1) * 0.05)
				end
				task.wait(0.3)
			end
		end)
	end

	local function startCall(c: any)
		callSerial += 1
		local mine = callSerial
		inCall = { contact = c, status = "outgoing", started = nil }
		callView.Visible = true
		if bodyRef then
			-- the call screen covers the whole app: its controls are the only live ones
			task.delay(0.2, function()
				if inCall and bodyRef then
					bodyRef.Visible = false
				end
			end)
		end
		callView.Position = UDim2.fromScale(0, 0.06)
		K.tween(callView, 0.25, { Position = UDim2.fromScale(0, 0) })
		callName.Text = c.name
		callRole.Text = c.role or ""
		local glyph = callAvatar:FindFirstChild("Glyph") :: TextLabel?
		if glyph then
			glyph.Text = c.glyph
		end
		local g = callAvatar:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ColorSequence.new(K.shade(c.color, -0.08, 0.12), K.shade(c.color, 0.1, -0.25))
		end
		callState.Text = "연결 중…"
		callState.TextColor3 = K.Color.sub
		callTimer.Text = ""
		K.feedback("open")
		pulseRings(mine)
		task.spawn(function()
			task.wait(1.6)
			if callSerial ~= mine then
				return
			end
			if c.kind == "taxi" then
				local ok, err = Net.send("callTaxi", {})
				if not ok then
					callState.Text = err or "연결할 수 없어요"
					callState.TextColor3 = K.Color.orange
					task.wait(1.6)
					if callSerial == mine then
						endCall("failed")
					end
					return
				end
				inCall.started = os.clock()
				callState.Text = "배차 요청 완료 🚕"
				callState.TextColor3 = K.Color.gold
				task.wait(0.9)
				if callSerial == mine then
					endCall("ended")
					ctx.phone.launch("taxi", { called = true })
				end
			else
				local ok, err = Net.send("callContact", { contactId = c.id, contact = c.id })
				if not ok then
					callState.Text = err or "연결할 수 없어요"
					callState.TextColor3 = K.Color.orange
					task.wait(1.6)
					if callSerial == mine then
						endCall("failed")
					end
					return
				end
				inCall.started = os.clock()
				callState.Text = "통화 중"
				callState.TextColor3 = K.Color.green
				K.feedback("success")
				-- call timer (1 Hz); the server's Dialog normally takes over within a second
				local t0 = os.clock()
				while callSerial == mine and inCall do
					callTimer.Text = fmtDur(os.clock() - t0)
					if os.clock() - t0 > 7 then
						callState.Text = "전화를 받지 않아요"
						callState.TextColor3 = K.Color.orange
						task.wait(1.4)
						if callSerial == mine then
							endCall("missed")
						end
						return
					end
					task.wait(1)
				end
			end
		end)
	end

	---------------------------------------------------------------------------------------------------
	-- Views
	---------------------------------------------------------------------------------------------------
	local function renderFavorites()
		local list = contacts()
		local key = AppKit.keyOf(list, function(c)
			return c.id .. c.name
		end) .. tostring(Net.hasProfile)
		if key == favKey then
			return
		end
		favKey = key
		local v = views.favorites
		AppKit.clear(v)
		-- taxi hero card
		local hero = K.make("TextButton", { Name = "Fav_taxi", Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = Color3.new(1, 1, 1), AutoButtonColor = false, Text = "", LayoutOrder = 1 }, v)
		K.corner(hero, K.Radius.lg)
		K.gradient(hero, { Color3.fromRGB(255, 206, 84), Color3.fromRGB(240, 140, 30) }, 20)
		local car = K.iconTile(hero, 44, "🚕", Color3.fromRGB(40, 30, 10), true)
		car.AnchorPoint = Vector2.new(0, 0.5)
		car.Position = UDim2.new(0, 12, 0.5, 0)
		K.text(hero, { Name = "Title", Position = UDim2.fromOffset(66, 14), Size = UDim2.new(1, -128, 0, 22), Text = "광안 콜택시", Font = K.Font.bold, TextSize = K.Type.body + 1, TextColor3 = K.Color.onGold, TextTruncate = Enum.TextTruncate.AtEnd })
		K.text(hero, { Name = "Sub", Position = UDim2.fromOffset(66, 37), Size = UDim2.new(1, -128, 0, 16), Text = "24시간 · 1분 배차", TextSize = K.Type.caption, TextColor3 = Color3.fromRGB(80, 50, 0), TextTruncate = Enum.TextTruncate.AtEnd })
		local callBtn = K.frame(hero, { Name = "CallPill", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 0, BackgroundColor3 = K.Color.onGold })
		K.corner(callBtn, UDim.new(0.5, 0))
		K.text(callBtn, { Size = UDim2.fromScale(1, 1), Text = "📞", TextColor3 = K.Color.gold, Font = K.Font.bold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center })
		K.pressable(hero, { scale = 0.97 })
		hero.Activated:Connect(function()
			startCall(Life.contacts(nil)[1])
		end)
		K.SectionHeader(v, { title = "즐겨찾기", order = 2 })
		local gridF = K.frame(v, { Name = "FavGrid", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 })
		K.make("UIGridLayout", { CellSize = UDim2.new(0.25, -6, 0, 88), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, gridF)
		local favs = {}
		local job = Net.profile.job
		local G = ctx.Data.Shared
		local jobContact = type(job) == "table" and G and G.JOBS and G.JOBS[job.id] and G.JOBS[job.id].contact or nil
		for _, c in list do
			local k = kindOf(c)
			if c.id ~= "taxi" and (k == "friend" or c.id == jobContact) then
				table.insert(favs, c)
			end
		end
		for i, c in favs do
			if i > 8 then
				break
			end
			local cell = K.make("TextButton", { Name = "Fav_" .. c.id, BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = i }, gridF)
			local av = K.avatar(cell, 52, c.glyph, c.color)
			av.AnchorPoint = Vector2.new(0.5, 0)
			av.Position = UDim2.new(0.5, 0, 0, 4)
			K.text(cell, { Name = "Name", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.new(1, 0, 0, 16), Text = c.name, Font = K.Font.bold, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
			K.text(cell, { Name = "Role", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 75), Size = UDim2.new(1, 0, 0, 13), Text = c.role or "", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
			K.pressable(cell, { veil = false, scale = 0.93 })
			cell.Activated:Connect(function()
				startCall(c)
			end)
		end
		if #favs == 0 then
			K.EmptyState(v, { order = 4, compact = true, icon = "⭐", title = "즐겨찾기가 없어요", body = "친구와 직장 연락처가 여기에 모여요" })
		end
	end

	local GROUPS = { { id = "friend", title = "친구" }, { id = "npc", title = "직장 · 가게" }, { id = "service", title = "서비스" } }
	local function renderContacts()
		local list = contacts()
		local key = AppKit.keyOf(list, function(c)
			return c.id .. c.name
		end)
		if key == contactsKey then
			return
		end
		contactsKey = key
		local v = views.contacts
		AppKit.clear(v)
		local order = 0
		local rows = {}
		for _, grp in GROUPS do
			local members = {}
			for _, c in list do
				if kindOf(c) == grp.id then
					table.insert(members, c)
				end
			end
			if #members > 0 then
				order += 1
				K.SectionHeader(v, { title = grp.title, order = order })
				order += 1
				local card = K.Card(v, { Name = "Group_" .. grp.id, Size = UDim2.new(1, 0, 0, #members * 56), LayoutOrder = order, ClipsDescendants = true })
				K.list(card, false, 0)
				for i, c in members do
					local r = K.ListRow(card, {
						name = "Contact_" .. c.id,
						icon = c.glyph,
						iconColor = c.color,
						round = true,
						title = c.name,
						subtitle = c.role,
						trailing = "📞",
						trailingColor = K.Color.green,
						trailingWidth = 36,
						grouped = true,
						height = 56,
						order = i,
						onClick = function()
							startCall(c)
						end,
					})
					table.insert(rows, r.row)
				end
			end
		end
		K.stagger(rows, K.Color.card)
	end

	local function renderRecents()
		local key = tostring(#calls) .. (calls[1] and tostring(calls[1].at) or "")
		if key == recentsKey then
			-- refresh the "n분 전" labels only
			return
		end
		recentsKey = key
		local v = views.recents
		AppKit.clear(v)
		if #calls == 0 then
			K.EmptyState(v, { order = 1, icon = "🕘", title = "최근 통화가 없어요", body = "택시를 부르거나 친구에게 전화해 보세요" })
			return
		end
		local card = K.Card(v, { Name = "Recents", Size = UDim2.new(1, 0, 0, #calls * 56), LayoutOrder = 1, ClipsDescendants = true })
		K.list(card, false, 0)
		for i, c in calls do
			local ago = os.clock() - c.at
			local when = if ago < 60 then "방금" else string.format("%d분 전", math.floor(ago / 60))
			local status = if c.status == "missed" then "받지 않음" elseif c.status == "failed" then "연결 실패" else "발신 · " .. fmtDur(c.dur)
			K.ListRow(card, {
				name = "Recent" .. i,
				icon = c.glyph,
				iconColor = c.color,
				round = true,
				title = c.name,
				subtitle = (if c.status == "missed" or c.status == "failed" then "↗ " else "↗ ") .. status,
				trailing = when,
				trailingColor = K.Color.faint,
				trailingWidth = 60,
				grouped = true,
				height = 56,
				order = i,
				onClick = function()
					local cc = byId(c.id) or Life.contacts(nil)[1]
					startCall(cc)
				end,
			})
		end
	end

	function app.refresh()
		if not visible then
			return
		end
		for id, v in views do
			v.Visible = id == tab
		end
		if tab == "favorites" then
			renderFavorites()
		elseif tab == "contacts" then
			renderContacts()
		else
			renderRecents()
		end
	end

	---------------------------------------------------------------------------------------------------
	-- Build
	---------------------------------------------------------------------------------------------------
	function app.build(body: Frame, r: Frame)
		root = r
		bodyRef = body
		local L = ctx.phone.layout()
		ctx.phone.header(body, "전화")
		tabs = K.Tabs(body, {
			tabs = { { id = "favorites", label = "즐겨찾기" }, { id = "contacts", label = "연락처" }, { id = "recents", label = "최근" } },
			value = "favorites",
			onChange = function(id: string)
				tab = id
				app.refresh()
			end,
		})
		tabs.frame.Position = UDim2.fromOffset(0, L.headerH)
		for _, id in { "favorites", "contacts", "recents" } do
			views[id] = AppKit.scroll(body, L.headerH + 46, { name = "View_" .. id, topPad = 8 })
			views[id].Visible = id == "favorites"
		end

		-- call screen (covers the app, status bar stays on top)
		callView = K.frame(root, { Name = "CallScreen", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), Visible = false, ZIndex = 20, Active = true })
		K.corner(callView, L.radius)
		K.gradient(callView, { Color3.fromRGB(34, 40, 92), Color3.fromRGB(16, 16, 36), Color3.fromRGB(8, 8, 16) }, 90)
		for i = 1, 2 do
			local ring = K.frame(callView, { Name = "Ring" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.33), Size = UDim2.fromOffset(88, 88), BackgroundTransparency = 1, BackgroundColor3 = K.Color.cyan, ZIndex = 21 })
			K.corner(ring, UDim.new(0.5, 0))
			rings[i] = ring
		end
		callAvatar = K.avatar(callView, 84, "🙂", K.Color.violet)
		callAvatar.AnchorPoint = Vector2.new(0.5, 0.5)
		callAvatar.Position = UDim2.fromScale(0.5, 0.33)
		callAvatar.ZIndex = 22
		for _, d in callAvatar:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 22
			end
		end
		K.stroke(callAvatar, Color3.new(1, 1, 1), 2, 0.6)
		callName = K.text(callView, { Name = "Name", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.33, 50), Size = UDim2.new(1, -24, 0, 26), Text = "", Font = K.Font.bold, TextSize = K.Type.title, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
		callRole = K.text(callView, { Name = "Role", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.33, 76), Size = UDim2.new(1, -24, 0, 16), Text = "", TextColor3 = K.Color.faint, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
		callState = K.text(callView, { Name = "State", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.33, 94), Size = UDim2.new(1, -24, 0, 18), Text = "", TextColor3 = K.Color.sub, Font = K.Font.bold, TextSize = K.Type.bodySm, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
		callTimer = K.text(callView, { Name = "Timer", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.33, 112), Size = UDim2.new(1, -24, 0, 18), Text = "", TextColor3 = K.Color.text, TextSize = K.Type.bodySm, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
		K.mono(callTimer)
		-- controls: mute / speaker / keypad (toggle visuals) + end call
		local controls = K.frame(callView, { Name = "Controls", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -80), Size = UDim2.fromOffset(200, 52), ZIndex = 22 })
		K.list(controls, true, 22, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		for i, def in { { "Mute", "🔇" }, { "Speaker", "🔊" }, { "Keypad", "⌨️" } } do
			local b = K.Button(controls, { name = def[1], style = "glass", icon = def[2], size = UDim2.fromOffset(48, 48), order = i, zIndex = 23, textSize = 18 })
			K.corner(b, UDim.new(0.5, 0))
			local on = false
			b.Activated:Connect(function()
				on = not on
				b.BackgroundColor3 = if on then K.Color.text else K.Color.glass
				b.BackgroundTransparency = if on then 0.1 else K.GLASS_T
			end)
		end
		local hang = K.Button(callView, { name = "HangUp", style = "destructive", icon = "📞", anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, -16), size = UDim2.fromOffset(60, 60), zIndex = 23, textSize = 24, sound = "close" })
		K.corner(hang, UDim.new(0.5, 0))
		hang.Rotation = 135
		hang.Activated:Connect(function()
			endCall("ended")
		end)

		Net.on("profile", function(changed: any)
			if changed.contacts or changed.job then
				favKey, contactsKey = "", ""
				app.refresh()
			end
		end)
		Net.on("dialog", function(d: any)
			if inCall and type(d) == "table" and d.close ~= true then
				endCall("ended")
			end
		end)
		ctx.phone.onLayout(function()
			local l = ctx.phone.layout()
			tabs.frame.Position = UDim2.fromOffset(0, l.headerH)
			for _, v in views do
				v.Position = UDim2.fromOffset(0, l.headerH + 46)
				v.Size = UDim2.new(1, 0, 1, -(l.headerH + 46))
			end
			local c = callView:FindFirstChildOfClass("UICorner")
			if c then
				c.CornerRadius = UDim.new(0, l.radius)
			end
			local short = l.screenH < 400
			local cy = if short then 0.3 else 0.33
			for _, ring in rings do
				ring.Position = UDim2.fromScale(0.5, cy)
			end
			callAvatar.Position = UDim2.fromScale(0.5, cy)
			callAvatar.Size = UDim2.fromOffset(if short then 64 else 84, if short then 64 else 84)
			local off = if short then 36 else 50
			callName.Position = UDim2.new(0.5, 0, cy, off)
			callRole.Position = UDim2.new(0.5, 0, cy, off + 25)
			callState.Position = UDim2.new(0.5, 0, cy, off + 42)
			callTimer.Position = UDim2.new(0.5, 0, cy, off + 60)
			controls.Visible = not short
			-- clear of the home bar (tall screens reserve l.bottom px for it)
			controls.Position = UDim2.new(0.5, 0, 1, -(l.bottom + 84))
			hang.Position = UDim2.new(0.5, 0, 1, -(l.bottom + (if short then -2 else 12)))
			hang.Size = UDim2.fromOffset(if short then 52 else 60, if short then 52 else 60)
		end)
	end

	function app.show(args: any)
		visible = true
		recentsKey = ""
		app.refresh()
		if type(args) == "table" and args.call == "taxi" then
			startCall(Life.contacts(nil)[1])
		end
	end

	function app.hide()
		visible = false
		if inCall then
			endCall("ended")
		end
	end

	return app
end
