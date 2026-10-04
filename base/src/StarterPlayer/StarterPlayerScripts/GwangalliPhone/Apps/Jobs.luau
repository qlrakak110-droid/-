-- 알바 · 구인: my job card (title / level, XP bar, today's pay, 출근 / 퇴근 / 그만두기 with confirm
-- modals), job offers that arrived by message, and the listings (place + distance, hourly wage,
-- requirements, level ladder, 지원하기 -> PhoneAction "applyJob" {jobId}; switching jobs asks first).
-- Built with the GwangalliUI kit. Event driven (ProfileChanged job / careers / stats / offers,
-- WorkState).

return function(ctx: any)
	local K, Net, Life, Dest, AppKit = ctx.K, ctx.Net, ctx.Life, ctx.Dest, ctx.AppKit

	local app = {}
	local scroll: ScrollingFrame
	local conn: any
	local content: Frame
	local myCard: Frame
	local myIcon: Frame
	local myTitle: TextLabel
	local mySub: TextLabel
	local xpBar: any
	local xpText: TextLabel
	local todayText: TextLabel
	local shiftBtn: TextButton
	local quitBtn: TextButton
	local noJob: any
	local offerHolder: Frame
	local listHolder: Frame
	local visible = false
	local listKey = ""

	local function onShift(): boolean
		local j = Net.profile.job
		if type(j) == "table" and j.onShift ~= nil and j.onShift == true then
			return true
		end
		return Net.work ~= nil and Net.work.onShift == true
	end

	local function say(text: string, kind: string?)
		ctx.phone.toast({ app = "jobs", title = "알바", body = text, kind = kind or "job", silent = true })
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

	---------------------------------------------------------------------------------------------------
	-- My job
	---------------------------------------------------------------------------------------------------
	local function renderMine()
		local p = Net.profile
		local j = p.job
		local hasJob = type(j) == "table" and j.id ~= nil
		myCard.Visible = hasJob
		noJob.frame.Visible = not hasJob
		if not hasJob then
			return
		end
		local def = Life.job(j.id)
		local level = tonumber(j.level) or 1
		local xp = tonumber(j.xp) or 0
		local need = tonumber(j.nextXp)
		myTitle.Text = tostring(j.title or (def and def.title) or j.id)
		mySub.Text = string.format("Lv.%d %s · 📍 %s", level, tostring(j.levelTitle or (def and def.ranks[level]) or ""), tostring(j.place or (def and def.place) or "근무지"))
		local glyph = myIcon:FindFirstChild("Glyph") :: TextLabel?
		if glyph then
			glyph.Text = tostring(j.icon or (def and def.icon) or "💼")
		end
		if need and need > 0 then
			xpBar.set(math.clamp(xp / need, 0, 1))
			xpText.Text = string.format("경험치 %d / %d · 다음 직급까지 %d", math.floor(xp), math.floor(need), math.max(0, math.floor(need - xp)))
		else
			xpBar.set(1)
			xpText.Text = string.format("경험치 %d · 최고 직급 달성 🏆", math.floor(xp))
		end
		local w = Net.work
		local today = if type(w) == "table" and tonumber(w.earnedToday) then tonumber(w.earnedToday) else 0
		todayText.Text = string.format("시급 %s · 오늘 번 돈 %s", K.won(tonumber(j.wage) or (def and def.wage) or 0), K.won(today or 0))
		local on = onShift()
		shiftBtn.Text = if on then "🏁  퇴근하기" else "🚀  출근하기"
		local g = shiftBtn:FindFirstChildOfClass("UIGradient")
		if g then
			local grad = if on then K.Grad.danger else K.Grad.success
			g.Color = ColorSequence.new(grad[1], grad[2])
		end
		shiftBtn.TextColor3 = if on then Color3.new(1, 1, 1) else K.Color.onAccent
		quitBtn.Visible = not on
		shiftBtn.Size = if on then UDim2.new(1, 0, 0, 44) else UDim2.new(0.62, -4, 0, 44)
	end

	---------------------------------------------------------------------------------------------------
	-- Offers + listings
	---------------------------------------------------------------------------------------------------
	local function jobOffers(): { any }
		local out = {}
		local o = Net.profile.offers
		if type(o) == "table" then
			for _, v in o do
				if type(v) == "table" and (v.kind == "applyJob" or v.kind == "job") then
					table.insert(out, v)
				end
			end
		end
		return out
	end

	local function renderLists()
		local p = Net.profile
		local j = p.job
		local offers = jobOffers()
		local jobs = Life.jobs()
		local key = AppKit.keyOf(offers, function(o)
			return tostring(o.id)
		end) .. "|" .. (if type(j) == "table" then tostring(j.id) else "-") .. "|" .. AppKit.keyOf(jobs, function(x)
			local _, ok = Life.reqText(x, p.stats)
			return x.id .. tostring(ok)
		end)
		if key == listKey then
			return
		end
		listKey = key
		AppKit.clear(offerHolder)
		for i, o in offers do
			local c = ctx.Data.contact(o.contact)
			local card = K.Card(offerHolder, { Name = "JobOffer_" .. tostring(o.id), Size = UDim2.new(1, 0, 0, 60), LayoutOrder = i })
			K.stroke(card, K.Color.gold, 1, 0.5)
			local av = K.avatar(card, 36, c.glyph, c.color)
			av.AnchorPoint = Vector2.new(0, 0.5)
			av.Position = UDim2.new(0, 10, 0.5, 0)
			K.text(card, { Name = "Title", Position = UDim2.fromOffset(56, 11), Size = UDim2.new(1, -150, 0, 18), Text = "📩 " .. tostring(o.title or "알바 제안"), Font = K.Font.bold, TextSize = K.Type.caption + 1, TextTruncate = Enum.TextTruncate.AtEnd })
			K.text(card, { Name = "From", Position = UDim2.fromOffset(56, 30), Size = UDim2.new(1, -150, 0, 15), Text = c.name .. " · " .. c.role, TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
			K.Button(card, { name = "Open", text = "답장하기", style = "gold", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -8, 0.5, 0), size = UDim2.fromOffset(84, 44), textSize = K.Type.caption, onClick = function()
				ctx.phone.launch("messages", { contact = o.contact })
			end })
		end
		offerHolder.Visible = #offers > 0

		AppKit.clear(listHolder)
		local from = rootPos()
		local cards = {}
		for i, job in jobs do
			local reqText, reqOk = Life.reqText(job, p.stats)
			local mine = type(j) == "table" and j.id == job.id
			local card = K.Card(listHolder, { Name = "Job_" .. job.id, Size = UDim2.new(1, 0, 0, 124), LayoutOrder = i })
			if mine then
				K.stroke(card, K.Color.green, 1, 0.45)
			end
			local icon = K.iconTile(card, 40, job.icon, K.Color.gold)
			icon.Position = UDim2.fromOffset(12, 12)
			K.text(card, { Name = "Title", Position = UDim2.fromOffset(62, 11), Size = UDim2.new(1, -170, 0, 19), Text = job.title, Font = K.Font.bold, TextSize = K.Type.bodySm + 1, TextTruncate = Enum.TextTruncate.AtEnd })
			local dist = ""
			local pos = job.place ~= "" and Dest.position(job.place) or nil
			if pos and from then
				dist = " · " .. K.meters((pos - from).Magnitude)
			end
			K.text(card, { Name = "Place", Position = UDim2.fromOffset(62, 31), Size = UDim2.new(1, -74, 0, 15), Text = "📍 " .. (if job.place ~= "" then job.place else "광안리") .. dist, TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
			local wage = K.text(card, { Name = "Wage", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(100, 18), Text = K.won(job.wage), TextColor3 = K.Color.green, Font = K.Font.bold, TextSize = K.Type.bodySm, TextXAlignment = Enum.TextXAlignment.Right })
			K.mono(wage)
			K.text(card, { Name = "Per", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 30), Size = UDim2.fromOffset(100, 14), Text = "시급", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Right })
			local ladder = if #job.ranks > 0 then table.concat(job.ranks, " → ") else ""
			K.text(card, { Name = "Ladder", Position = UDim2.fromOffset(12, 58), Size = UDim2.new(1, -24, 0, 15), Text = if ladder ~= "" then "📈 " .. ladder else "", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
			K.text(card, { Name = "Req", Position = UDim2.fromOffset(12, 88), Size = UDim2.new(1, -140, 0, 24), Text = (if reqOk then "✅ " else "🔒 ") .. reqText, TextColor3 = if reqOk then K.Color.sub else K.Color.orange, TextSize = K.Type.micro, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd })
			local b = K.Button(card, {
				name = "Apply_" .. job.id,
				text = if mine then "근무 중" elseif reqOk then "지원하기" else "조건 부족",
				style = if mine then "secondary" elseif reqOk then "primary" else "secondary",
				anchor = Vector2.new(1, 1),
				position = UDim2.new(1, -10, 1, -10),
				size = UDim2.fromOffset(112, 44),
				textSize = K.Type.caption + 1,
				onClick = function()
					if mine then
						return
					end
					if not reqOk then
						say("조건이 부족해요 · " .. reqText, "warn")
						return
					end
					local cur = Net.profile.job
					if type(cur) == "table" and cur.id then
						ctx.phone.confirm({
							title = "이직할까요?",
							body = string.format("지금 직업(%s)을 그만두고 %s에 지원해요. 경력은 그대로 남아요.", tostring(cur.title or cur.id), job.title),
							icon = job.icon,
							iconColor = K.Color.gold,
							confirmText = "지원하기",
							width = 290,
							onConfirm = function()
								if send("applyJob", { jobId = job.id }) then
									K.feedback("success")
								end
							end,
						})
					elseif send("applyJob", { jobId = job.id }) then
						K.feedback("success")
						say(job.title .. "에 지원했어요")
					end
				end,
			})
			if mine or not reqOk then
				K.setButtonEnabled(b, false)
			end
			table.insert(cards, card)
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
		renderMine()
		renderLists()
	end

	---------------------------------------------------------------------------------------------------
	-- Build
	---------------------------------------------------------------------------------------------------
	function app.build(body: Frame)
		local L = ctx.phone.layout()
		ctx.phone.header(body, "알바 · 구인")
		scroll = AppKit.scroll(body, L.headerH, { name = "Scroll", gap = 10, topPad = 2 })
		conn = AppKit.conn(scroll, ctx, 0)
		content = K.frame(scroll, { Name = "Content", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
		K.list(content, false, 10)

		myCard = K.frame(content, { Name = "MyJob", Size = UDim2.new(1, 0, 0, 186), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 1 })
		K.corner(myCard, K.Radius.lg)
		K.gradient(myCard, { Color3.fromRGB(70, 54, 22), Color3.fromRGB(30, 30, 46) }, 110)
		K.stroke(myCard, K.Color.gold, 1, 0.6)
		K.text(myCard, { Name = "Caption", Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 14), Text = "내 직업", TextColor3 = K.Color.gold, TextSize = K.Type.micro, Font = K.Font.bold })
		myIcon = K.iconTile(myCard, 42, "💼", K.Color.gold)
		myIcon.Position = UDim2.fromOffset(14, 28)
		myTitle = K.text(myCard, { Name = "Title", Position = UDim2.fromOffset(66, 28), Size = UDim2.new(1, -78, 0, 22), Text = "", Font = K.Font.bold, TextSize = K.Type.body + 1, TextTruncate = Enum.TextTruncate.AtEnd })
		mySub = K.text(myCard, { Name = "Sub", Position = UDim2.fromOffset(66, 51), Size = UDim2.new(1, -78, 0, 16), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
		xpBar = K.ProgressBar(myCard, { color = K.Color.gold, height = 6 })
		xpBar.frame.Position = UDim2.fromOffset(14, 80)
		xpBar.frame.Size = UDim2.new(1, -28, 0, 6)
		xpText = K.text(myCard, { Name = "Xp", Position = UDim2.fromOffset(14, 90), Size = UDim2.new(1, -28, 0, 15), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
		todayText = K.text(myCard, { Name = "Today", Position = UDim2.fromOffset(14, 106), Size = UDim2.new(1, -28, 0, 15), Text = "", TextColor3 = K.Color.green, TextSize = K.Type.micro, Font = K.Font.bold, TextTruncate = Enum.TextTruncate.AtEnd })
		local row = K.frame(myCard, { Name = "Buttons", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -12), Size = UDim2.new(1, -28, 0, 44) })
		K.list(row, true, 8)
		shiftBtn = K.Button(row, {
			name = "Shift",
			text = "🚀  출근하기",
			style = "success",
			size = UDim2.new(0.62, -4, 0, 44),
			order = 1,
			onClick = function()
				if onShift() then
					ctx.phone.confirm({
						title = "퇴근할까요?",
						body = "오늘 번 돈은 통장으로 들어가요.",
						icon = "🏁",
						iconColor = K.Color.orange,
						confirmText = "퇴근하기",
						destructive = true,
						width = 280,
						onConfirm = function()
							send("endShift", {})
						end,
					})
				elseif send("startShift", {}) then
					K.feedback("success")
					ctx.phone.close()
				end
			end,
		})
		quitBtn = K.Button(row, {
			name = "Quit",
			text = "그만두기",
			style = "danger",
			size = UDim2.new(0.38, -4, 0, 44),
			order = 2,
			textSize = K.Type.caption + 1,
			onClick = function()
				local j = Net.profile.job
				ctx.phone.confirm({
					title = "정말 그만둘까요?",
					body = string.format("%s을(를) 그만둬요. 쌓은 경력(직급)은 남아서 다시 지원하면 이어져요.", tostring(type(j) == "table" and j.title or "지금 직업")),
					icon = "👋",
					iconColor = K.Color.red,
					confirmText = "그만두기",
					destructive = true,
					width = 290,
					onConfirm = function()
						send("quitJob", {})
					end,
				})
			end,
		})
		noJob = K.EmptyState(content, { order = 1, compact = true, icon = "💼", title = "아직 직업이 없어요", body = "아래에서 일자리를 골라 지원해 보세요", color = K.Color.gold })
		noJob.frame.Visible = false

		offerHolder = K.frame(content, { Name = "Offers", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Visible = false })
		K.list(offerHolder, false, 8)
		K.SectionHeader(content, { title = "채용 중인 일자리", order = 3 })
		listHolder = K.frame(content, { Name = "Listings", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 })
		K.list(listHolder, false, 8)

		Net.on("profile", function(changed: any)
			if changed.job or changed.careers or changed.stats or changed.offers then
				if changed.job or changed.offers or changed.stats then
					listKey = ""
				end
				refresh()
			end
		end)
		Net.on("work", function()
			refresh()
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
		refresh()
	end

	function app.hide()
		visible = false
	end

	return app
end
