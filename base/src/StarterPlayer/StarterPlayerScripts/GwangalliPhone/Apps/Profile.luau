-- 내 정보: player card (avatar, name, job, home, 총자산 count-up), stat bars (외모 / 체력 / 행복 /
-- 인기 / 근력, 0..100 with descriptions), careers per job and achievements (derived from the profile).
-- Built with the GwangalliUI kit. Event driven (ProfileChanged stats / job / home / money / careers).

return function(ctx: any)
	local K, Net, Life, AppKit = ctx.K, ctx.Net, ctx.Life, ctx.AppKit

	local STAT_COLORS = {
		appearance = Color3.fromRGB(255, 92, 160),
		stamina = Color3.fromRGB(61, 220, 132),
		happiness = Color3.fromRGB(255, 194, 71),
		popularity = Color3.fromRGB(150, 110, 255),
		strength = Color3.fromRGB(255, 128, 70),
	}

	local ACHIEVEMENTS = {
		{ id = "firstJob", icon = "💼", title = "첫 출근", test = function(p)
			return type(p.careers) == "table" and next(p.careers) ~= nil
		end },
		{ id = "firstPay", icon = "💵", title = "첫 월급", test = function(p)
			for _, e in (ctx.Net.transactions or {}) do
				if (tonumber(e.amount) or 0) > 0 and string.find(tostring(e.title or ""), "급여", 1, true) then
					return true
				end
			end
			return false
		end },
		{ id = "moveIn", icon = "🔑", title = "독립", test = function(p)
			return type(p.home) == "table" and p.home.listingId ~= nil
		end },
		{ id = "ownHome", icon = "🏡", title = "내 집 마련", test = function(p)
			return type(p.home) == "table" and p.home.owned == true
		end },
		{ id = "fashion", icon = "✨", title = "패셔니스타", test = function(p)
			return (tonumber(type(p.stats) == "table" and p.stats.appearance) or 0) >= 60
		end },
		{ id = "popular", icon = "⭐", title = "광안리 인싸", test = function(p)
			return (tonumber(type(p.stats) == "table" and p.stats.popularity) or 0) >= 50
		end },
		{ id = "strong", icon = "💪", title = "몸짱", test = function(p)
			return (tonumber(type(p.stats) == "table" and p.stats.strength) or 0) >= 50
		end },
		{ id = "rich", icon = "💎", title = "백만장자", test = function(p)
			return Life.totalAssets(p) >= 1000000
		end },
	}

	local app = {}
	local scroll: ScrollingFrame
	local conn: any
	local content: Frame
	local jobLabel: TextLabel
	local homeLabel: TextLabel
	local assets: any
	local bars: { [string]: any } = {}
	local careerHolder: Frame
	local achTiles: { [string]: any } = {}
	local achCount: TextLabel
	local visible = false
	local shownOnce = false

	local function statOrder(): { string }
		local G = ctx.Data.Shared
		if G and type(G.STAT_ORDER) == "table" then
			return G.STAT_ORDER
		end
		return Life.STAT_ORDER
	end

	local function statMeta(id: string): any
		local G = ctx.Data.Shared
		local s = G and G.STATS and G.STATS[id]
		local base = Life.stat(id)
		return {
			label = (s and s.short) or base.label,
			name = (s and s.name) or base.label,
			icon = (s and s.icon) or base.icon,
			desc = (s and s.desc) or "",
			color = STAT_COLORS[id] or base.color,
		}
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
		local stats = if type(p.stats) == "table" then p.stats else {}
		for id, b in bars do
			local v = math.clamp(tonumber(stats[id]) or 0, 0, 100)
			b.bar.set(v / 100, not animate)
			b.value.Text = tostring(math.floor(v + 0.5))
		end
		local j = p.job
		if type(j) == "table" and j.id then
			jobLabel.Text = string.format("💼 %s · Lv.%s %s%s", tostring(j.title or j.id), tostring(j.level or 1), tostring(j.levelTitle or ""), if j.onShift then " · 근무 중" else "")
		else
			jobLabel.Text = "💼 무직 · 알바 앱에서 일자리를 찾아보세요"
		end
		local h = p.home
		homeLabel.Text = if type(h) == "table" and h.name then string.format("🏠 %s (%s)", tostring(h.name), if h.owned then "자가" else "월세") else "🏠 집 없음"
		assets.set(Life.totalAssets(p), animate)

		AppKit.clear(careerHolder)
		local n = 0
		if type(p.careers) == "table" then
			for id, lv in p.careers do
				n += 1
				local def = Life.job(id)
				K.ListRow(careerHolder, {
					name = "Career_" .. tostring(id),
					icon = (def and def.icon) or "💼",
					iconColor = K.Color.gold,
					title = (def and def.title) or tostring(id),
					subtitle = (def and def.place) or "",
					trailing = "Lv." .. tostring(lv),
					trailingColor = K.Color.gold,
					trailingWidth = 50,
					height = 52,
					grouped = true,
					order = n,
				})
			end
		end
		if n == 0 then
			K.EmptyState(careerHolder, { order = 1, compact = true, icon = "📋", title = "아직 경력이 없어요", body = "첫 알바를 시작해 보세요", height = 110 })
		end

		local got = 0
		for _, a in ACHIEVEMENTS do
			local ok = false
			pcall(function()
				ok = a.test(p) == true
			end)
			local t = achTiles[a.id]
			if t then
				t.tile.BackgroundTransparency = if ok then 0 else 0.6
				t.glyph.TextTransparency = if ok then 0 else 0.6
				t.label.TextColor3 = if ok then K.Color.text else K.Color.faint
				t.lock.Visible = not ok
			end
			if ok then
				got += 1
			end
		end
		achCount.Text = string.format("%d / %d", got, #ACHIEVEMENTS)
	end

	function app.build(body: Frame)
		local L = ctx.phone.layout()
		ctx.phone.header(body, "내 정보")
		scroll = AppKit.scroll(body, L.headerH, { name = "Scroll", gap = 10, topPad = 2 })
		conn = AppKit.conn(scroll, ctx, 0)
		content = K.frame(scroll, { Name = "Content", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
		K.list(content, false, 10)

		local card = K.frame(content, { Name = "PlayerCard", Size = UDim2.new(1, 0, 0, 132), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 1 })
		K.corner(card, K.Radius.lg)
		K.gradient(card, { Color3.fromRGB(255, 84, 160), Color3.fromRGB(120, 84, 250), Color3.fromRGB(40, 36, 100) }, 30)
		K.stroke(card, Color3.new(1, 1, 1), 1, 0.8)
		local av = K.avatar(card, 54, string.upper(string.sub(ctx.player.DisplayName, 1, 1)), Color3.fromRGB(40, 40, 70))
		av.Position = UDim2.fromOffset(14, 14)
		K.stroke(av, Color3.new(1, 1, 1), 2, 0.4)
		K.text(card, { Name = "Name", Position = UDim2.fromOffset(78, 14), Size = UDim2.new(1, -90, 0, 24), Text = ctx.player.DisplayName, Font = K.Font.bold, TextSize = K.Type.title2, TextTruncate = Enum.TextTruncate.AtEnd })
		K.text(card, { Name = "Handle", Position = UDim2.fromOffset(78, 38), Size = UDim2.new(1, -90, 0, 15), Text = "@" .. ctx.player.Name, TextColor3 = Color3.fromRGB(255, 226, 244), TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
		jobLabel = K.text(card, { Name = "Job", Position = UDim2.fromOffset(14, 76), Size = UDim2.new(1, -28, 0, 16), Text = "", TextSize = K.Type.caption, TextColor3 = Color3.fromRGB(255, 236, 246), TextTruncate = Enum.TextTruncate.AtEnd })
		homeLabel = K.text(card, { Name = "Home", Position = UDim2.fromOffset(14, 94), Size = UDim2.new(0.5, -14, 0, 16), Text = "", TextSize = K.Type.caption, TextColor3 = Color3.fromRGB(255, 236, 246), TextTruncate = Enum.TextTruncate.AtEnd })
		K.text(card, { Name = "AssetsCaption", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 90), Size = UDim2.fromOffset(80, 14), Text = "총자산", TextSize = K.Type.micro, TextColor3 = Color3.fromRGB(255, 226, 244), TextXAlignment = Enum.TextXAlignment.Right })
		assets = K.MoneyLabel(card, { Name = "Assets", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 104), Size = UDim2.new(0.5, -14, 0, 20), Text = "0원", Font = K.Font.bold, TextSize = K.Type.body, TextXAlignment = Enum.TextXAlignment.Right })

		K.SectionHeader(content, { title = "능력치", order = 2 })
		local statCard = K.Card(content, { Name = "Stats", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 })
		K.list(statCard, false, 0)
		K.pad(statCard, 0, 0, 4, 4)
		for i, id in statOrder() do
			local meta = statMeta(id)
			local row = K.frame(statCard, { Name = "Stat_" .. id, Size = UDim2.new(1, 0, 0, 54), LayoutOrder = i })
			local icon = K.iconTile(row, 32, meta.icon, meta.color, true)
			icon.Position = UDim2.fromOffset(12, 11)
			K.text(row, { Name = "Label", Position = UDim2.fromOffset(54, 8), Size = UDim2.new(1, -110, 0, 18), Text = meta.name, Font = K.Font.bold, TextSize = K.Type.caption + 1 })
			local value = K.text(row, { Name = "Value", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.fromOffset(44, 18), Text = "0", Font = K.Font.bold, TextSize = K.Type.bodySm, TextColor3 = meta.color, TextXAlignment = Enum.TextXAlignment.Right })
			K.mono(value)
			local bar = K.ProgressBar(row, { color = meta.color, height = 6 })
			bar.frame.Position = UDim2.fromOffset(54, 30)
			bar.frame.Size = UDim2.new(1, -68, 0, 6)
			K.text(row, { Name = "Desc", Position = UDim2.fromOffset(54, 38), Size = UDim2.new(1, -68, 0, 14), Text = meta.desc, TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
			bars[id] = { bar = bar, value = value }
		end

		K.SectionHeader(content, { title = "경력", order = 4 })
		careerHolder = K.Card(content, { Name = "Careers", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5 })
		K.list(careerHolder, false, 0)

		local ah = K.SectionHeader(content, { title = "업적", order = 6 })
		achCount = K.text(ah.frame, { Name = "Count", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -2, 0, 26), Size = UDim2.fromOffset(60, 16), Text = "", TextColor3 = K.Color.gold, Font = K.Font.bold, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Right })
		local grid = K.frame(content, { Name = "Achievements", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 7 })
		K.make("UIGridLayout", { CellSize = UDim2.new(0.25, -6, 0, 76), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		for i, a in ACHIEVEMENTS do
			local cell = K.Card(grid, { Name = "Ach_" .. a.id, LayoutOrder = i })
			local tile = K.iconTile(cell, 36, a.icon, K.Color.gold, true)
			tile.AnchorPoint = Vector2.new(0.5, 0)
			tile.Position = UDim2.new(0.5, 0, 0, 8)
			local label = K.text(cell, { Name = "Title", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -6, 0, 16), Text = a.title, TextSize = K.Type.micro, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
			local lock = K.text(cell, { Name = "Lock", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(16, 16), Text = "🔒", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center })
			achTiles[a.id] = { tile = tile, glyph = tile:FindFirstChild("Glyph") :: TextLabel, label = label, lock = lock }
		end

		Net.on("profile", function(changed: any)
			if changed.stats or changed.job or changed.home or changed.money or changed.careers or changed.cash or changed.bank or changed.tx then
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
		end)
	end

	function app.show()
		visible = true
		refresh(not shownOnce)
		shownOnce = true
	end

	function app.hide()
		visible = false
	end

	return app
end
