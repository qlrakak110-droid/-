-- 설정: graphics quality (자동 / 낮음 / 중간 / 높음 -> GwangalliQuality.setOverride; the workspace
-- attribute "GwangalliQualityForce" as a fallback), 소리 / 진동 / 알림 / 길안내 표시 / 모션 줄이기 toggles
-- (they drive GwangalliUI.settings, so every kit component follows), 사진 모드 and app info.
-- Built with the GwangalliUI kit.

return function(ctx: any)
	local K, AppKit = ctx.K, ctx.AppKit
	local Quality = ctx.Quality

	local FORCE_ATTR = "GwangalliQualityForce"
	local TIER_TEXT = { low = "낮음", mid = "중간", high = "높음" }

	local app = {}
	local scroll: ScrollingFrame
	local tierSeg: any
	local tierNow: TextLabel
	local toggles: { [string]: any } = {}
	local visible = false

	local function currentOverride(): string
		if Quality and type(Quality.getOverride) == "function" then
			local ok, t = pcall(Quality.getOverride)
			if ok and TIER_TEXT[t] then
				return t
			end
		end
		local f = workspace:GetAttribute(FORCE_ATTR)
		if type(f) == "string" and TIER_TEXT[string.lower(f)] then
			return string.lower(f)
		end
		return ctx.settings.quality or "auto"
	end

	local function setTier(id: string)
		ctx.settings.quality = id
		local value = if id == "auto" then nil else id
		local done = false
		if Quality then
			for _, fname in { "setOverride", "set", "override" } do
				if type(Quality[fname]) == "function" then
					done = pcall(Quality[fname], value)
					if done then
						break
					end
				end
			end
		end
		if not done then
			pcall(function()
				workspace:SetAttribute(FORCE_ATTR, value)
			end)
		end
	end

	local function renderTier()
		local tier = "?"
		local reason = ""
		if Quality and type(Quality.get) == "function" then
			local ok, t = pcall(Quality.get)
			tier = if ok and TIER_TEXT[t] then TIER_TEXT[t] else "?"
			if type(Quality.reason) == "function" then
				local okR, r = pcall(Quality.reason)
				reason = if okR and type(r) == "string" then r else ""
			end
		end
		K.setText(tierNow, "지금 적용: " .. tier .. (if reason ~= "" then " · " .. reason else ""))
	end

	local function toggleRow(parent: Instance, key: string, icon: string, color: Color3, title: string, sub: string, order: number, value: boolean, onChange: (boolean) -> ())
		local row = K.frame(parent, { Name = "Row_" .. key, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = order })
		local ic = K.iconTile(row, 32, icon, color)
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.new(0, 12, 0.5, 0)
		K.text(row, { Name = "Title", Position = UDim2.fromOffset(56, 11), Size = UDim2.new(1, -130, 0, 18), Text = title, Font = K.Font.bold, TextSize = K.Type.bodySm })
		K.text(row, { Name = "Sub", Position = UDim2.fromOffset(56, 30), Size = UDim2.new(1, -130, 0, 15), Text = sub, TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
		local t = K.Toggle(row, { value = value, onChange = onChange })
		t.button.Name = "Toggle_" .. key
		t.button.AnchorPoint = Vector2.new(1, 0.5)
		t.button.Position = UDim2.new(1, -14, 0.5, 0)
		K.frame(row, { Name = "Hairline", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 56, 1, 0), Size = UDim2.new(1, -56, 0, 1), BackgroundTransparency = 0.93, BackgroundColor3 = K.Color.line })
		toggles[key] = t
	end

	function app.build(body: Frame)
		local L = ctx.phone.layout()
		ctx.phone.header(body, "설정")
		scroll = AppKit.scroll(body, L.headerH, { name = "Content", gap = 8, topPad = 2 })

		K.SectionHeader(scroll, { title = "그래픽 품질", caption = "폰이 뜨거우면 '낮음'을 골라 보세요", order = 1 })
		tierSeg = K.Segmented(scroll, {
			items = { { id = "auto", label = "자동" }, { id = "low", label = "낮음" }, { id = "mid", label = "중간" }, { id = "high", label = "높음" } },
			value = currentOverride(),
			order = 2,
			onChange = function(id: string)
				setTier(id)
				task.delay(0.1, renderTier)
				renderTier()
			end,
		})
		tierNow = K.text(scroll, { Name = "TierNow", Size = UDim2.new(1, 0, 0, 16), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 3 })

		K.SectionHeader(scroll, { title = "소리 · 알림", order = 4 })
		local card = K.Card(scroll, { Name = "Feedback", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5 })
		K.list(card, false, 0)
		toggleRow(card, "sound", "🔊", K.Color.cyan, "소리", "버튼 클릭음 · 알림음", 1, ctx.settings.sound ~= false, function(v)
			ctx.settings.sound = v
			K.settings.sound = v
		end)
		toggleRow(card, "haptics", "📳", K.Color.violet, "진동", "알림 · 버튼 진동 (지원 기기)", 2, ctx.settings.haptics ~= false, function(v)
			ctx.settings.haptics = v
			K.settings.haptics = v
			if v then
				K.haptic("notify")
			end
		end)
		toggleRow(card, "banners", "🔔", K.Color.gold, "알림 배너", "화면 위쪽에 알림 띄우기", 3, ctx.settings.banners ~= false, function(v)
			ctx.settings.banners = v
			K.settings.notifications = v
		end)

		K.SectionHeader(scroll, { title = "게임", order = 6 })
		local game2 = K.Card(scroll, { Name = "Game", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 7 })
		K.list(game2, false, 0)
		toggleRow(game2, "marker", "🧭", K.Color.teal, "길안내 · 근무 목표 표시", "목표 마커와 화면 가장자리 화살표", 1, ctx.settings.marker ~= false, function(v)
			ctx.settings.marker = v
			ctx.Tracker.refresh()
		end)
		toggleRow(game2, "motion", "🌀", K.Color.magenta, "모션 줄이기", "애니메이션을 짧게 (낮은 화질에서는 자동)", 2, K.settings.reducedMotion == true, function(v)
			K.settings.reducedMotion = v
		end)
		local photo = K.ListRow(game2, {
			name = "PhotoMode",
			icon = "📷",
			iconColor = Color3.fromRGB(150, 156, 176),
			title = "사진 모드",
			subtitle = "버튼을 모두 숨기고 야경 찍기",
			chevron = true,
			grouped = true,
			height = 58,
			order = 3,
			onClick = function()
				ctx.phone.home()
				ctx.phone.setPhotoMode(true)
			end,
		})
		local _ = photo

		K.SectionHeader(scroll, { title = "정보", order = 8 })
		local about = K.Card(scroll, { Name = "About", Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 9 })
		K.text(about, { Name = "Title", Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 18), Text = "광안리 GTA · Gwangan OS 2.0", Font = K.Font.bold, TextSize = K.Type.caption + 1 })
		K.text(about, { Name = "Sub", Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -28, 0, 16), Text = "PC: P 키로 폰 열기/닫기 · Esc로 닫기", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })

		if Quality and Quality.changed then
			pcall(function()
				Quality.changed:Connect(function()
					if visible then
						renderTier()
					end
				end)
			end)
		end
		ctx.phone.onLayout(function()
			local l = ctx.phone.layout()
			scroll.Position = UDim2.fromOffset(0, l.headerH)
			scroll.Size = UDim2.new(1, 0, 1, -l.headerH)
		end)
	end

	function app.show()
		visible = true
		tierSeg.set(currentOverride(), true)
		renderTier()
	end

	function app.hide()
		visible = false
	end

	return app
end
