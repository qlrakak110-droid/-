-- 택시 ("광안 콜택시"): destination search + list (distance, fare estimate) -> 호출 -> dispatch screen
-- (mini map with the car closing in, driver name + plate, ETA countdown, fare estimate, destination),
-- arrival / boarding, the ride (meter) and a receipt card on arrival. Built with the GwangalliUI kit.
--   PhoneAction "callTaxi" {name?}, "taxiDestination" {name}, "cancelTaxi" {}
--   TaxiState {state = coming|arrived|riding|done|cancelled, eta?, fare?, destination?, boarded?, reason?}
-- Fare estimate: GwangalliGameplayShared.taxiFare(straight-line studs, clock, 인기도) via Data.fareFor.
-- Driver / plate are generated from the player's UserId (stable per player).

return function(ctx: any)
	local K, Data, Net, Dest, AppKit = ctx.K, ctx.Data, ctx.Net, ctx.Dest, ctx.AppKit

	local CANCEL_TEXT = { money = "잔액이 부족해요", busy = "빈 택시가 없어요", noroad = "근처에 큰길이 없어요", player = "호출을 취소했어요" }
	local CANCEL_SUB = {
		money = "알바로 돈을 벌거나 통장에서 현금을 찾아 보세요",
		busy = "잠시 후 다시 불러 주세요",
		noroad = "차가 다니는 큰길로 나가서 다시 불러 주세요",
	}
	local DRIVERS = { "김광안", "이수영", "박민락", "최남천", "정해운", "강부산" }
	local CARS = { "쏘나타", "K5", "그랜저", "아이오닉 5" }

	local app = {}
	local header: any
	local pickView: Frame
	local search: any
	local listScroll: ScrollingFrame
	local dispatch: Frame
	local ride: Frame
	local receipt: Frame
	local notice: any
	local actionBar: Frame
	local primary: TextButton
	local secondary: TextButton
	-- dispatch widgets
	local miniCar: Frame
	local etaText: TextLabel
	local etaBar: any
	local fareText: TextLabel
	local destText: TextLabel
	local driverName: TextLabel
	local driverCar: TextLabel
	local plateText: TextLabel
	local statusPill: TextLabel
	-- ride / receipt widgets
	local rideTitle: TextLabel
	local rideFare: TextLabel
	local rideBar: any
	local rcFare: TextLabel
	local rcRows: { [string]: TextLabel } = {}

	local rows: { [string]: any } = {}
	local rowNames = ""
	local selected: string? = nil
	local visible = false
	local requesting = 0
	local tickSerial = 0
	local rideStart: { pos: Vector3?, at: number, from: string? }? = nil
	local lastReceipt: any = nil
	-- motion state
	local currentView: string? = nil
	local choosing = false -- "목적지 바꾸기": the list is open while the taxi keeps coming
	local radarStop: (() -> ())? = nil
	local driverShown = false
	local roadSerial = 0
	local mapCard: Frame
	local meDot: Frame
	local routeDots: { Frame } = {}
	local driverCard: Frame
	local paper: Frame
	local checkGlyph: TextLabel
	local roadStrip: Frame
	local rideHint: TextLabel
	local rideFx: any = nil

	local uid = math.abs(ctx.player.UserId or 7)
	local driver = DRIVERS[(uid % #DRIVERS) + 1]
	local car = CARS[((uid // 7) % #CARS) + 1]
	local plate = string.format("부산 %d%s %04d", 30 + (uid % 60), ({ "바", "사", "아", "자" })[(uid % 4) + 1], (uid * 37) % 10000)

	local function state(): string
		local t = Net.taxi
		local s = t and t.state or "idle"
		if s == "cancelled" and t.at and os.clock() - t.at > 10 then
			return "idle"
		end
		return s
	end

	local function rootPos(): Vector3?
		local char = ctx.player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root.Position else nil
	end

	local function popularity(): number?
		local stats = Net.profile.stats
		return if type(stats) == "table" then tonumber(stats.popularity) else nil
	end

	local function estimate(name: string?): (number?, number?)
		local from = rootPos()
		local p = name and Dest.position(name)
		if not (from and p) then
			return nil, nil
		end
		local d = (p - from).Magnitude
		return Data.fareFor(d, ctx.phone.clock(), popularity()), d
	end

	---------------------------------------------------------------------------------------------------
	-- Destination list
	---------------------------------------------------------------------------------------------------
	local function styleRow(ref: any)
		local on = ref.name == selected
		ref.row.BackgroundColor3 = if on then Color3.fromRGB(56, 48, 16) else K.Color.card
		ref.check.Visible = on
		ref.title.TextColor3 = if on then K.Color.gold else K.Color.text
	end

	local function rebuildRows()
		local list = Dest.list()
		local key = AppKit.keyOf(list, function(e)
			return e.name
		end)
		if key == rowNames then
			return
		end
		rowNames = key
		for _, ref in rows do
			ref.row:Destroy()
		end
		table.clear(rows)
		for i, e in list do
			local r = K.ListRow(listScroll, {
				name = "Dest_" .. i,
				icon = "📍",
				iconColor = K.Color.cyan,
				round = true,
				title = e.name,
				subtitle = "",
				trailing = "",
				trailingWidth = 30,
				height = 54,
				order = i,
				onClick = function()
					selected = if selected == e.name then nil else e.name
					for _, rr in rows do
						styleRow(rr)
					end
					app.refresh()
				end,
			})
			local check = K.text(r.row, { Name = "Check", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 0, BackgroundColor3 = K.Color.gold, Text = "✓", TextColor3 = K.Color.onGold, Font = K.Font.bold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 3 })
			K.corner(check, UDim.new(0.5, 0))
			rows[e.name] = { row = r.row, title = r.title, sub = r.subtitle, check = check, name = e.name, order = i, dist = math.huge }
		end
	end

	local function refreshRows()
		rebuildRows()
		local query = string.lower(search.get() or "")
		local from = rootPos()
		local sorted = {}
		for _, ref in rows do
			local p = Dest.position(ref.name)
			if p and from then
				local d = (p - from).Magnitude
				ref.dist = d
				local fare = Data.fareFor(d, ctx.phone.clock(), popularity())
				ref.sub.Text = string.format("%s · 예상 %s", K.meters(d), K.won(fare))
				ref.sub.Visible = true
			else
				ref.dist = math.huge
				ref.sub.Text = "요금은 도착 후 계산돼요"
				ref.sub.Visible = true
			end
			ref.row.Visible = query == "" or string.find(string.lower(ref.name), query, 1, true) ~= nil
			styleRow(ref)
			table.insert(sorted, ref)
		end
		table.sort(sorted, function(a, b)
			if a.dist ~= b.dist then
				return a.dist < b.dist
			end
			return a.order < b.order
		end)
		for i, ref in sorted do
			ref.row.LayoutOrder = i
		end
	end

	---------------------------------------------------------------------------------------------------
	-- Render
	---------------------------------------------------------------------------------------------------
	local function remainingEta(): number?
		local t = Net.taxi
		if t and t.eta and t.at then
			return math.max(0, math.ceil(t.eta - (os.clock() - t.at)))
		end
		return nil
	end

	local function setButtons(p: { any }?, s: { any }?)
		primary.Visible = p ~= nil
		secondary.Visible = s ~= nil
		if p then
			primary.Text = p[1]
			local style = p[2] or "gold"
			local st = K.ButtonStyles[style]
			local g = primary:FindFirstChildOfClass("UIGradient")
			if g and st and st.grad then
				g.Enabled = true
				g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, st.grad[1]), ColorSequenceKeypoint.new(1, st.grad[#st.grad]) })
				primary.BackgroundColor3 = Color3.new(1, 1, 1)
				primary.TextColor3 = st.fg
			elseif g then
				g.Enabled = false
				primary.BackgroundColor3 = K.Color.card2
				primary.TextColor3 = if p[3] == false then K.Color.faint else K.Color.text
			end
			local sheen = primary:FindFirstChild("Sheen")
			if sheen and sheen:IsA("GuiObject") then
				sheen.Visible = g ~= nil and g.Enabled
			end
			primary:SetAttribute("Disabled", if p[3] == false then true else nil)
		end
		if s then
			secondary.Text = s[1]
		end
		secondary.Size = UDim2.new(0.36, -5, 0, 44)
		primary.Size = if secondary.Visible then UDim2.new(0.64, -5, 0, 44) else UDim2.new(1, 0, 0, 44)
	end

	local VIEW_ORDER = { pick = 1, dispatch = 2, ride = 3, receipt = 4, notice = 4 }
	local function viewFrame(v: string): GuiObject
		if v == "pick" then
			return pickView
		elseif v == "dispatch" then
			return dispatch
		elseif v == "ride" then
			return ride
		elseif v == "receipt" then
			return receipt
		end
		return notice.frame
	end

	local function setRadar(on: boolean)
		if on and not radarStop then
			radarStop = K.radar(mapCard, meDot.Position, { color = K.Color.cyan, size = 96, period = 1.5, count = 2 })
		elseif not on and radarStop then
			radarStop()
			radarStop = nil
		end
	end

	-- the ride scene's parallax: skyline slow, bridge medium, road fast, the taxi bobs. Each layer is
	-- one infinite linear tween (no script loop); stopped and reset when the ride view goes away.
	local TweenService = game:GetService("TweenService")
	local function runRoad(on: boolean)
		roadSerial += 1
		local fx = rideFx
		if not fx then
			return
		end
		for _, tw in fx.tweens do
			tw:Cancel()
		end
		table.clear(fx.tweens)
		fx.far.Position = UDim2.fromScale(0, 0)
		fx.mid.Position = UDim2.fromScale(0, 0)
		fx.road.Position = UDim2.fromOffset(0, 0)
		fx.glyph.Position = UDim2.fromOffset(0, 0)
		if not on or K.reduced() then
			return
		end
		local function loop(inst: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, reverses: boolean?)
			local tw = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, reverses == true), goal)
			tw:Play()
			table.insert(fx.tweens, tw)
		end
		loop(fx.far, 26, { Position = UDim2.fromScale(-1, 0) })
		loop(fx.mid, 11, { Position = UDim2.fromScale(-1, 0) })
		loop(fx.road, 0.32, { Position = UDim2.fromOffset(-28, 0) })
		loop(fx.glyph, 0.42, { Position = UDim2.fromOffset(0, -1) }, Enum.EasingStyle.Sine, true)
	end

	-- ride progress from the start point to the destination (1 Hz while riding)
	local function rideProgress(dest: string?): (number?, number?)
		local p = dest and Dest.position(dest)
		local now = rootPos()
		if not (p and now and rideStart and rideStart.pos) then
			return nil, nil
		end
		local total = math.max(1, (p - rideStart.pos).Magnitude)
		local left = (p - now).Magnitude
		return math.clamp(1 - left / total, 0, 1), left
	end

	local function onEnter(v: string)
		if v == "receipt" then
			local sc = K.scaleOf(paper)
			sc.Scale = 0.86
			K.spring(sc, { Scale = 1 }, { duration = 0.5, amount = 0.25 })
			K.springIn(checkGlyph, 0.3, { amount = 0.5, duration = 0.5, delay = 0.12 })
			local fare = tonumber((Net.taxi or {}).fare)
			if fare then
				K.countUp(rcFare, fare, { from = 0, format = K.won, duration = 0.8 })
			end
			K.sheen(paper, { delay = 0.35, duration = 1.0, strength = 0.35 })
			K.feedback("success")
		elseif v == "ride" then
			runRoad(true)
		end
	end

	-- one place changes the visible view; forward steps push, backward steps pop (parallax)
	local function setView(v: string)
		if v == currentView then
			return
		end
		local prev = currentView
		currentView = v
		local L = ctx.phone.layout()
		local rest = UDim2.fromOffset(0, L.headerH + (if v == "notice" then 10 else 0))
		for _, name in { "pick", "dispatch", "ride", "receipt", "notice" } do
			if name ~= v and name ~= prev then
				viewFrame(name).Visible = false
			end
		end
		if prev == "ride" then
			runRoad(false)
		end
		local newF = viewFrame(v)
		if not prev or not visible then
			if prev then
				viewFrame(prev).Visible = false
			end
			newF.Visible = true
			newF.Position = rest
		elseif VIEW_ORDER[v] >= VIEW_ORDER[prev] then
			K.pushPage(newF, viewFrame(prev), { rest = rest })
		else
			K.popPage(viewFrame(prev), newF, { rest = rest })
		end
		if visible then
			onEnter(v)
		end
	end

	local function render()
		local s = state()
		local t = Net.taxi or {}
		local waiting = requesting > 0 and os.clock() - requesting < 7 and (s == "idle" or s == "done" or s == "cancelled")
		local view = "pick"
		if waiting or s == "coming" or s == "arrived" then
			view = "dispatch"
		elseif s == "riding" then
			view = "ride"
		elseif s == "done" then
			view = "receipt"
		elseif s == "cancelled" then
			view = "notice"
		end
		if choosing and (s == "coming" or s == "arrived") then
			view = "pick"
		elseif choosing then
			choosing = false
		end
		setView(view)
		setRadar(view == "dispatch" and waiting)

		if not Net.ready() then
			header.setSubtitle(if Net.status == "offline" then "택시 서비스 준비 중…" else "연결 중…", K.Color.orange)
			setButtons({ "연결 중…", "secondary", false }, nil)
			return
		end

		if view == "pick" and choosing then
			header.setSubtitle("새 목적지를 골라 주세요", K.Color.gold)
			local changed = selected ~= nil and selected ~= t.destination
			setButtons({ if changed then "목적지 설정 · " .. tostring(selected) else "목적지를 골라 주세요", if changed then "gold" else "secondary", changed }, { "돌아가기" })
		elseif view == "pick" then
			header.setSubtitle(if selected then "목적지 · " .. selected else "목적지를 고르고 호출하세요", if selected then K.Color.gold else nil)
			local fare = estimate(selected)
			setButtons({ if selected then ("🚕 호출 · " .. (if fare then K.won(fare) else selected)) else "🚕 택시 호출", "gold" }, nil)
		elseif view == "dispatch" then
			local eta = remainingEta()
			local arrived = s == "arrived"
			local boarded = type(t.raw) == "table" and t.raw.boarded == true
			if waiting then
				driverShown = false
				header.setSubtitle("근처 택시를 찾는 중…", K.Color.gold)
				statusPill.Text = "배차 중"
				etaText.Text = "…"
				etaBar.set(0.1)
				driverName.Text = "배차 중인 기사님을 찾고 있어요"
				driverCar.Text = ""
				plateText.Parent.Visible = false
			else
				if not driverShown then
					-- a driver was assigned: the card springs in and a light sweeps over it
					driverShown = true
					if visible then
						K.springIn(driverCard, 0.9, { amount = 0.35, duration = 0.46 })
						K.sheen(driverCard, { delay = 0.1, strength = 0.6 })
						K.springIn(plateText.Parent :: GuiObject, 0.6, { amount = 0.5, duration = 0.45, delay = 0.12 })
					end
				end
				plateText.Parent.Visible = true
				driverName.Text = driver .. " 기사님  ★4.9"
				driverCar.Text = car .. " · 흰색"
				plateText.Text = plate
				if arrived then
					header.setSubtitle(if boarded then "탑승 완료 · 목적지를 골라 주세요" else "택시가 도착했어요!", K.Color.green)
					statusPill.Text = "도착"
					statusPill.BackgroundColor3 = K.Color.green
					etaText.Text = "도착"
					etaBar.set(1)
					miniCar.Position = UDim2.fromScale(0.78, 0.5)
				else
					header.setSubtitle(if eta then string.format("택시가 오고 있어요 · 약 %d초", eta) else "택시가 오고 있어요", K.Color.gold)
					statusPill.Text = "오는 중"
					statusPill.BackgroundColor3 = K.Color.gold
					etaText.Text = if eta then (if eta >= 60 then string.format("%d분 %02d초", eta // 60, eta % 60) else string.format("%d초", eta)) else "곧 도착"
					local total = tonumber(t.eta) or 60
					local u = if eta then 1 - eta / math.max(1, total) else 0.5
					etaBar.set(u)
					local cx = 0.12 + 0.66 * u
					K.tween(miniCar, 0.95, { Position = UDim2.fromScale(cx, 0.56) }, Enum.EasingStyle.Linear)
					for i, d in routeDots do
						local x = (i - 0.5) / #routeDots
						d.Visible = x > cx and x < 0.84
					end
				end
			end
			local dest = t.destination or selected
			destText.Text = if dest then dest else "목적지를 선택해 주세요"
			destText.TextColor3 = if dest then K.Color.text else K.Color.gold
			local fare = estimate(dest)
			fareText.Text = if fare then "예상 " .. K.won(fare) else "요금은 도착 후 계산"
			if arrived then
				if selected and selected ~= t.destination then
					setButtons({ "탑승 · " .. K.ro(selected) .. " 출발", "gold" }, { "취소" })
				elseif t.destination then
					setButtons({ "택시에 타면 바로 출발해요", "secondary", false }, { "취소" })
				else
					setButtons({ "목적지를 골라 주세요", "secondary", false }, { "취소" })
				end
			elseif waiting then
				setButtons({ "호출 중…", "secondary", false }, nil)
			else
				if selected and selected ~= t.destination then
					setButtons({ "목적지 설정 · " .. selected, "gold" }, { "호출 취소" })
				else
					setButtons({ "목적지 바꾸기", "secondary" }, { "호출 취소" })
				end
			end
		elseif view == "ride" then
			local dest = t.destination or selected or "목적지"
			header.setSubtitle("운행 중 · 안전벨트를 매 주세요", K.Color.cyan)
			rideTitle.Text = K.ro(dest) .. " 가는 중"
			local fare = tonumber(t.fare)
			if fare and rideFare.Text ~= K.won(fare) then
				K.countUp(rideFare, fare, { from = tonumber((rideFare.Text:gsub("[^%d]", ""))) or 0, format = K.won, duration = 0.5 })
			elseif not fare then
				rideFare.Text = "미터기 작동 중"
			end
			local u, left = rideProgress(dest)
			rideBar.set(u or 0.1)
			if rideFx then
				rideFx.infoRows.dest.Text = dest
				rideFx.infoRows.driver.Text = driver .. " · " .. car .. " · " .. plate
			end
			rideHint.Text = if left and left > 12 then ("남은 거리 " .. K.meters(left) .. " · 광안대교 야경을 즐겨 보세요") else "창밖으로 광안대교 야경을 즐겨 보세요"
			setButtons({ "운행 중…", "secondary", false }, nil)
		elseif view == "receipt" then
			header.setSubtitle("이용해 주셔서 감사합니다", K.Color.green)
			local fare = tonumber(t.fare)
			rcFare.Text = if fare then K.won(fare) else "—"
			local dest = t.destination or selected or "—"
			rcRows.to.Text = dest
			rcRows.from.Text = (rideStart and rideStart.from) or "현재 위치"
			local dist = "—"
			if rideStart and rideStart.pos then
				local p = Dest.position(dest)
				if p then
					dist = K.meters((p - rideStart.pos).Magnitude)
				end
			end
			rcRows.dist.Text = dist
			rcRows.pay.Text = if fare then "통장 자동결제" else "—"
			rcRows.driver.Text = driver .. " · " .. plate
			setButtons({ "확인", "primary" }, nil)
		else
			local reason = type(t.raw) == "table" and t.raw.reason or nil
			header.setSubtitle("호출이 끝났어요", K.Color.faint)
			notice.set({ icon = if reason == "player" then "👋" else "🚫", title = CANCEL_TEXT[reason] or "호출이 취소됐어요", body = CANCEL_SUB[reason] or "언제든 다시 호출할 수 있어요", color = if reason == "money" then K.Color.orange else K.Color.faint })
			setButtons({ "🚕 다시 호출", "gold" }, nil)
		end
	end

	local function tick()
		tickSerial += 1
		local mine = tickSerial
		task.spawn(function()
			while visible and tickSerial == mine and (state() == "coming" or state() == "riding" or (requesting > 0 and os.clock() - requesting < 8)) do
				task.wait(1)
				if visible and tickSerial == mine then
					render()
				end
			end
		end)
	end

	local function callTaxi()
		if requesting > 0 and os.clock() - requesting < 6 then
			return
		end
		local ok, err = Net.send("callTaxi", if selected then { name = selected } else {})
		if ok then
			requesting = os.clock()
			rideStart = { pos = rootPos(), at = os.clock(), from = nil }
			tick()
			task.delay(7, function()
				if requesting > 0 and os.clock() - requesting >= 6.9 and state() == "idle" then
					requesting = 0
					ctx.phone.toast({ app = "taxi", title = "광안 콜택시", body = "근처에 빈 택시가 없어요. 잠시 후 다시 불러 주세요", kind = "warn", silent = true })
					render()
				end
			end)
		else
			ctx.phone.toast({ app = "taxi", title = "광안 콜택시", body = err or "호출할 수 없어요", kind = "error", silent = true })
		end
		render()
	end

	local function onPrimary()
		local s = state()
		if not Net.ready() then
			return
		end
		if s == "idle" then
			callTaxi()
		elseif s == "arrived" or s == "coming" then
			if selected and selected ~= (Net.taxi and Net.taxi.destination) then
				local ok, err = Net.send("taxiDestination", { name = selected })
				if ok then
					choosing = false
					K.feedback("success")
				else
					ctx.phone.toast({ app = "taxi", title = "광안 콜택시", body = err or "목적지를 보낼 수 없어요", kind = "error", silent = true })
				end
			elseif not choosing then
				-- change the destination: back to the list while the taxi keeps coming
				choosing = true
			end
		elseif s == "done" then
			Net.taxi = { state = "idle" }
			ctx.phone.setBadge("taxi", 0)
			selected = nil
		elseif s == "cancelled" then
			Net.taxi = { state = "idle" }
			callTaxi()
			return
		end
		render()
	end

	local function onSecondary()
		local s = state()
		if choosing and (s == "coming" or s == "arrived") then
			choosing = false
			render()
			return
		end
		if s == "coming" or s == "arrived" then
			ctx.phone.confirm({
				title = "호출을 취소할까요?",
				body = "오고 있는 택시가 돌아가요.",
				icon = "🚕",
				iconColor = K.Color.gold,
				confirmText = "호출 취소",
				cancelText = "기다릴게요",
				destructive = true,
				width = 280,
				onConfirm = function()
					local ok, err = Net.send("cancelTaxi", {})
					if not ok then
						ctx.phone.toast({ app = "taxi", title = "광안 콜택시", body = err or "취소할 수 없어요", kind = "error", silent = true })
					end
				end,
			})
		end
	end

	---------------------------------------------------------------------------------------------------
	-- Build
	---------------------------------------------------------------------------------------------------
	local function layout()
		local L = ctx.phone.layout()
		local top = L.headerH
		for _, f in { pickView, dispatch, ride, receipt } do
			f.Position = UDim2.fromOffset(0, top)
			f.Size = UDim2.new(1, 0, 1, -(top + 58))
		end
		notice.frame.Position = UDim2.fromOffset(0, top + 10)
		notice.frame.Size = UDim2.new(1, 0, 1, -(top + 78))
		local short = L.screenH < 400
		if rideHint then
			rideHint.Visible = not short
			-- short screens give the meter half the card so title / fare / bar never touch the edge
			if rideFx then
				rideFx.scene.Size = UDim2.fromScale(1, if short then 0.5 else 0.56)
				rideFx.meter.Size = UDim2.fromScale(1, if short then 0.5 else 0.44)
				-- tall screens: the ride card stays compact (<= 340 px) and a trip card (destination /
				-- driver) fills the space under it
				local rideH = (L.screenH - L.statusH - L.bottom) - top - 58
				local cardH = math.max(120, rideH - 12)
				local info = rideFx.info
				local showInfo = rideH - 12 - 340 >= 128
				if showInfo then
					cardH = 340
				end
				rideFx.card.Size = UDim2.new(1, -24, 0, cardH)
				info.Visible = showInfo
				info.Position = UDim2.fromOffset(12, 6 + cardH + 10)
			end
		end
		local map = dispatch:FindFirstChild("MiniMap", true) :: Frame?
		if map then
			map.Size = UDim2.new(1, 0, 0, if short then 58 else 110)
		end
	end

	function app.build(body: Frame)
		local L = ctx.phone.layout()
		header = ctx.phone.header(body, "광안 콜택시", { subtitle = "" })

		-- pick view: search + list
		pickView = K.frame(body, { Name = "Pick", Position = UDim2.fromOffset(0, L.headerH), Size = UDim2.new(1, 0, 1, -(L.headerH + 58)) })
		search = K.SearchBar(pickView, {
			placeholder = "목적지 검색 (예: 볼링, 클럽, 헬스)",
			onChange = function()
				if visible then
					refreshRows()
				end
			end,
		})
		search.frame.Position = UDim2.fromOffset(12, 2)
		search.frame.Size = UDim2.new(1, -24, 0, 44)
		listScroll = AppKit.scroll(pickView, 52, { name = "Destinations", gap = 6, topPad = 2 })

		-- dispatch view
		dispatch = K.frame(body, { Name = "Dispatch", Visible = false })
		local dScroll = AppKit.scroll(dispatch, 0, { name = "DispatchScroll", gap = 8, topPad = 4 })
		-- night mini map: sea, beach, the beach road with its centre line, a dotted route from the car
		-- to you (radar rings while a driver is being found)
		mapCard = K.frame(dScroll, { Name = "MiniMap", Size = UDim2.new(1, 0, 0, 110), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ClipsDescendants = true, LayoutOrder = 1, ZIndex = 1 })
		K.corner(mapCard, K.Radius.md)
		K.gradient(mapCard, { Color3.fromRGB(24, 30, 54), Color3.fromRGB(14, 18, 34) }, 90)
		K.stroke(mapCard, nil, 1, 0.86)
		local sea = K.frame(mapCard, { Name = "Sea", Size = UDim2.new(1, 0, 0.3, 0), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 1 })
		K.gradient(sea, { Color3.fromRGB(20, 52, 98), Color3.fromRGB(30, 78, 128) }, 90)
		K.frame(mapCard, { Name = "Beach", Position = UDim2.fromScale(0, 0.3), Size = UDim2.new(1, 0, 0, 5), BackgroundTransparency = 0.35, BackgroundColor3 = Color3.fromRGB(214, 190, 140), ZIndex = 1 })
		local road = K.frame(mapCard, { Name = "Road", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -10, 0.56, 0), Size = UDim2.new(1, 20, 0, 12), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(58, 66, 92), ZIndex = 1 })
		K.frame(road, { Name = "Lane", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0.45, BackgroundColor3 = Color3.fromRGB(255, 230, 150), ZIndex = 1 })
		for i = 1, 16 do
			local d = K.frame(mapCard, { Name = "Route", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale((i - 0.5) / 16, 0.56), Size = UDim2.fromOffset(4, 4), BackgroundTransparency = 0.1, BackgroundColor3 = K.Color.gold, ZIndex = 2, Visible = false })
			K.corner(d, UDim.new(0.5, 0))
			table.insert(routeDots, d)
		end
		meDot = K.frame(mapCard, { Name = "Me", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.86, 0.56), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 0, BackgroundColor3 = K.Color.cyan, ZIndex = 4 })
		K.corner(meDot, UDim.new(0.5, 0))
		K.stroke(meDot, Color3.new(1, 1, 1), 2, 0)
		local carShadow = K.frame(mapCard, { Name = "CarShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 6, 1, 6), BackgroundTransparency = 0.7, BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 3 })
		miniCar = K.frame(mapCard, { Name = "Car", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.12, 0.56), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 0, BackgroundColor3 = K.Color.gold, ZIndex = 5 })
		carShadow.Parent = miniCar
		carShadow.Position = UDim2.new(0.5, 0, 0.5, 2)
		carShadow.ZIndex = 5
		K.corner(carShadow, UDim.new(0.5, 0))
		K.corner(miniCar, UDim.new(0.5, 0))
		K.stroke(miniCar, Color3.new(1, 1, 1), 1.5, 0.2)
		K.text(miniCar, { Size = UDim2.fromScale(1, 1), Text = "🚕", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
		statusPill = K.text(mapCard, { Name = "Status", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(60, 22), BackgroundTransparency = 0, BackgroundColor3 = K.Color.gold, Text = "오는 중", TextColor3 = K.Color.onGold, Font = K.Font.bold, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
		K.corner(statusPill, UDim.new(0.5, 0))

		local eta = K.Card(dScroll, { Name = "Eta", Size = UDim2.new(1, 0, 0, 70), LayoutOrder = 2 })
		K.text(eta, { Name = "Caption", Position = UDim2.fromOffset(14, 10), Size = UDim2.new(0.5, 0, 0, 14), Text = "도착 예정", TextColor3 = K.Color.sub, TextSize = K.Type.micro, Font = K.Font.bold })
		etaText = K.text(eta, { Name = "Eta", Position = UDim2.fromOffset(14, 24), Size = UDim2.new(0.55, 0, 0, 28), Text = "—", Font = K.Font.bold, TextSize = K.Type.title, TextColor3 = K.Color.gold })
		K.mono(etaText)
		fareText = K.text(eta, { Name = "Fare", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 28), Size = UDim2.new(0.45, -14, 0, 20), Text = "", TextColor3 = K.Color.text, Font = K.Font.bold, TextSize = K.Type.caption + 1, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
		K.mono(fareText)
		etaBar = K.ProgressBar(eta, { color = K.Color.gold, height = 4 })
		etaBar.frame.Position = UDim2.new(0, 14, 1, -12)
		etaBar.frame.Size = UDim2.new(1, -28, 0, 4)

		local drv = K.Card(dScroll, { Name = "Driver", Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 3 })
		driverCard = drv
		-- the driver's initial on a gradient disc (a ZWJ emoji would split into two glyphs on some devices)
		local initial = string.sub(driver, 1, (utf8.offset(driver, 2) or (#driver + 1)) - 1)
		local av = K.avatar(drv, 40, initial, Color3.fromRGB(80, 120, 200))
		av.AnchorPoint = Vector2.new(0, 0.5)
		av.Position = UDim2.new(0, 12, 0.5, 0)
		driverName = K.text(drv, { Name = "Name", Position = UDim2.fromOffset(62, 12), Size = UDim2.new(1, -170, 0, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd })
		driverCar = K.text(drv, { Name = "Car", Position = UDim2.fromOffset(62, 33), Size = UDim2.new(1, -170, 0, 16), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextTruncate = Enum.TextTruncate.AtEnd })
		local plateBox = K.frame(drv, { Name = "Plate", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(96, 30), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(240, 242, 246) })
		K.corner(plateBox, 6)
		K.stroke(plateBox, Color3.fromRGB(20, 24, 40), 1.5, 0)
		plateText = K.text(plateBox, { Size = UDim2.fromScale(1, 1), Text = "", TextColor3 = Color3.fromRGB(18, 20, 30), Font = K.Font.bold, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center })

		local dst = K.Card(dScroll, { Name = "Destination", Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 4 })
		K.text(dst, { Name = "Pin", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 22, 1, 0), Text = "📍", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center })
		K.text(dst, { Name = "Caption", Position = UDim2.fromOffset(40, 8), Size = UDim2.new(1, -52, 0, 14), Text = "목적지", TextColor3 = K.Color.sub, TextSize = K.Type.micro, Font = K.Font.bold })
		destText = K.text(dst, { Name = "Dest", Position = UDim2.fromOffset(40, 23), Size = UDim2.new(1, -52, 0, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd })

		-- ride view: a night drive. Three parallax layers (skyline, the LED bridge, the road) loop on
		-- single infinite tweens (no per-frame script work); the taxi bobs; the meter sits below.
		ride = K.frame(body, { Name = "Ride", Visible = false })
		local rCard = K.frame(ride, { Name = "RideCard", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 1, -12), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card, ClipsDescendants = true })
		K.corner(rCard, K.Radius.lg)
		K.stroke(rCard, nil, 1, 0.88)
		local WHITE = Color3.new(1, 1, 1)
		local scene = K.frame(rCard, { Name = "Scene", Size = UDim2.fromScale(1, 0.56), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ClipsDescendants = true, ZIndex = 1 })
		K.gradient(scene, { Color3.fromRGB(6, 8, 26), Color3.fromRGB(28, 20, 70), Color3.fromRGB(84, 34, 104) }, 90)
		local horizonGlow = K.frame(scene, { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.66), Size = UDim2.fromScale(1.3, 0.5), BackgroundTransparency = 0.78, BackgroundColor3 = K.Color.magenta, ZIndex = 1 })
		K.corner(horizonGlow, UDim.new(0.5, 0))
		K.gradient(horizonGlow, { WHITE, WHITE }, 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }))
		-- a strip twice the scene width holding the same pattern twice: sliding it by -1 scene width
		-- and repeating is seamless
		local function strip(name: string, z: number): Frame
			return K.frame(scene, { Name = name, Size = UDim2.fromScale(2, 1), ZIndex = z })
		end
		local far = strip("Far", 2)
		for half = 0, 1 do
			for i, t in { { 0.02, 0.05, 0.3 }, { 0.08, 0.04, 0.42 }, { 0.13, 0.05, 0.24 }, { 0.2, 0.035, 0.34 }, { 0.3, 0.05, 0.2 }, { 0.37, 0.04, 0.3 }, { 0.62, 0.05, 0.16 }, { 0.7, 0.04, 0.26 }, { 0.8, 0.05, 0.2 }, { 0.9, 0.04, 0.12 } } do
				local tw = K.frame(far, { Name = "Tower", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(half * 0.5 + t[1] * 0.5, 0.62), Size = UDim2.fromScale(t[2] * 0.5, t[3]), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 2 })
				K.gradient(tw, { Color3.fromRGB(46, 36, 96), Color3.fromRGB(18, 14, 44) }, 90)
				if i % 2 == 1 then
					local win = K.frame(tw, { Name = "Lit", Position = UDim2.fromScale(0.3, 0.12), Size = UDim2.fromScale(0.2, 0.7), BackgroundTransparency = 0.55, BackgroundColor3 = Color3.fromRGB(255, 214, 150), ZIndex = 2 })
					K.gradient(win, { WHITE, WHITE }, 90, NumberSequence.new(0, 1))
				end
			end
		end
		local mid = strip("Bridge", 3)
		local led = ColorSequence.new({ ColorSequenceKeypoint.new(0, K.Color.cyan), ColorSequenceKeypoint.new(0.25, K.Color.violet), ColorSequenceKeypoint.new(0.5, K.Color.magenta), ColorSequenceKeypoint.new(0.75, K.Color.violet), ColorSequenceKeypoint.new(1, K.Color.cyan) })
		local deck = K.frame(mid, { Name = "Deck", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.62), Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 3 })
		K.gradient(deck, led, 0)
		local deckGlow = K.frame(mid, { Name = "DeckGlow", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.62), Size = UDim2.new(1, 0, 0, 8), BackgroundTransparency = 0.82, BackgroundColor3 = WHITE, ZIndex = 3 })
		K.gradient(deckGlow, led, 0)
		for half = 0, 1 do
			for _, px in { 0.22, 0.72 } do
				local x = half * 0.5 + px * 0.5
				K.frame(mid, { Name = "Pylon", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(x, 0.64), Size = UDim2.new(0, 2, 0.4, 0), BackgroundTransparency = 0.1, BackgroundColor3 = Color3.fromRGB(220, 224, 255), ZIndex = 3 })
			end
			for i = 0, 20 do
				local u = i / 20
				local x = half * 0.5 + (0.22 + 0.5 * u) * 0.5
				local y = 0.24 + 0.36 * (1 - (2 * u - 1) ^ 2)
				local d = K.frame(mid, { Name = "Cable", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(3, 3), BackgroundTransparency = 0.1, BackgroundColor3 = if math.abs(u - 0.5) < 0.2 then K.Color.magenta elseif math.abs(u - 0.5) < 0.38 then K.Color.violet else K.Color.cyan, ZIndex = 3 })
				K.corner(d, UDim.new(0.5, 0))
			end
		end
		-- the road: asphalt band with a scrolling centre line
		local roadBand = K.frame(scene, { Name = "Road", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.3, 0), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 4, ClipsDescendants = true })
		K.gradient(roadBand, { Color3.fromRGB(34, 36, 58), Color3.fromRGB(16, 17, 30) }, 90)
		K.frame(roadBand, { Name = "Edge", Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0.5, BackgroundColor3 = Color3.fromRGB(255, 214, 150), ZIndex = 4 })
		roadStrip = K.frame(roadBand, { Name = "Dashes", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 56, 1, 0), ZIndex = 4 })
		for i = 0, 30 do
			local dsh = K.frame(roadStrip, { Name = "Dash", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, i * 28, 0.62, 0), Size = UDim2.fromOffset(14, 2), BackgroundTransparency = 0.25, BackgroundColor3 = Color3.fromRGB(255, 230, 150), ZIndex = 4 })
			K.corner(dsh, UDim.new(0.5, 0))
		end
		-- the taxi (glyph on a soft headlight glow), bobbing gently
		local taxi = K.frame(scene, { Name = "Taxi", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.9, 0), Size = UDim2.fromOffset(56, 40), ZIndex = 6 })
		local beam = K.frame(taxi, { Name = "Headlights", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.8, 0, 0.7, 0), Size = UDim2.fromOffset(70, 18), BackgroundTransparency = 0.7, BackgroundColor3 = Color3.fromRGB(255, 240, 200), ZIndex = 5 })
		K.corner(beam, UDim.new(0.5, 0))
		K.gradient(beam, { WHITE, WHITE }, 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }))
		local shadow = K.frame(taxi, { Name = "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.96), Size = UDim2.fromOffset(46, 6), BackgroundTransparency = 0.55, BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 5 })
		K.corner(shadow, UDim.new(0.5, 0))
		local taxiGlyph = K.text(taxi, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "🚕", TextSize = 32, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
		local livePill = K.text(scene, { Name = "Live", Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(64, 22), BackgroundTransparency = 0.25, BackgroundColor3 = Color3.fromRGB(8, 10, 24), Text = "● 운행 중", TextColor3 = K.Color.cyan, Font = K.Font.bold, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
		K.corner(livePill, UDim.new(0.5, 0))
		-- scrim so the scene melts into the meter panel
		local melt = K.frame(scene, { Name = "Melt", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.18), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card, ZIndex = 7 })
		K.gradient(melt, { WHITE, WHITE }, 90, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) }))

		-- meter panel
		local meter = K.frame(rCard, { Name = "MeterPanel", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.44), ZIndex = 2 })
		K.pad(meter, 16, 16, 6, 12)
		K.list(meter, false, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		rideTitle = K.text(meter, { Name = "Title", Size = UDim2.new(1, 0, 0, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1, ZIndex = 2 })
		rideFare = K.text(meter, { Name = "Meter", Size = UDim2.new(1, 0, 0, 32), Text = "", Font = K.Font.bold, TextSize = K.Type.display, TextColor3 = K.Color.gold, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, ZIndex = 2 })
		K.mono(rideFare)
		rideBar = K.ProgressBar(meter, { color = K.Color.cyan, height = 4, order = 3 })
		rideBar.frame.Size = UDim2.new(1, 0, 0, 4)
		rideHint = K.text(meter, { Name = "Hint", Size = UDim2.new(1, 0, 0, 16), Text = "창밖으로 광안대교 야경을 즐겨 보세요", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 4, ZIndex = 2 })
		-- trip card under the ride card (tall screens only)
		local info = K.Card(ride, { Name = "TripInfo", Size = UDim2.new(1, -24, 0, 116), Visible = false })
		K.pad(info, 14, 14, 8, 8)
		K.list(info, false, 0)
		local infoRows = {}
		for i, def in { { "dest", "📍", "목적지" }, { "driver", "🚕", "기사님" } } do
			local r = K.frame(info, { Name = "Row_" .. def[1], Size = UDim2.new(1, 0, 0, 50), LayoutOrder = i })
			K.text(r, { Name = "Icon", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0, 24, 1, 0), Text = def[2], TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center })
			K.text(r, { Name = "Caption", Position = UDim2.fromOffset(34, 8), Size = UDim2.new(1, -34, 0, 14), Text = def[3], TextColor3 = K.Color.sub, TextSize = K.Type.micro, Font = K.Font.bold })
			infoRows[def[1]] = K.text(r, { Name = "Value", Position = UDim2.fromOffset(34, 23), Size = UDim2.new(1, -34, 0, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd })
			if i == 1 then
				K.frame(r, { Name = "Line", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 34, 1, 0), Size = UDim2.new(1, -34, 0, 1), BackgroundTransparency = 0.9, BackgroundColor3 = K.Color.line })
			end
		end
		rideFx = { far = far, mid = mid, road = roadStrip, taxi = taxi, glyph = taxiGlyph, scene = scene, meter = meter, card = rCard, info = info, infoRows = infoRows, tweens = {} }

		-- receipt view
		receipt = K.frame(body, { Name = "Receipt", Visible = false })
		local rcScroll = AppKit.scroll(receipt, 0, { name = "ReceiptScroll", gap = 0, topPad = 6 })
		-- explicit height: 12 + 28 + 18 + 32 + 1 + 5 x 20 + 8 gaps x 6 + 12 + 14 (tear edge) = 265
		paper = K.frame(rcScroll, { Name = "Paper", Size = UDim2.new(1, 0, 0, 265), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(246, 247, 250), LayoutOrder = 1 })
		K.corner(paper, K.Radius.md)
		-- perforated tear edge along the bottom (holes in the app background colour)
		local tear = K.frame(paper, { Name = "Tear", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 4), Size = UDim2.new(1, 0, 0, 8), ClipsDescendants = false })
		K.list(tear, true, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		for i = 1, 26 do
			local hole = K.frame(tear, { Name = "Hole", Size = UDim2.fromOffset(8, 8), BackgroundTransparency = 0, BackgroundColor3 = K.Color.bg, LayoutOrder = i })
			K.corner(hole, UDim.new(0.5, 0))
		end
		local stack = K.frame(paper, { Name = "Stack", Size = UDim2.new(1, 0, 1, -8) })
		K.pad(stack, 14, 14, 12, 12)
		K.list(stack, false, 6, Enum.HorizontalAlignment.Center)
		local dark = Color3.fromRGB(24, 26, 36)
		checkGlyph = K.text(stack, { Name = "Check", Size = UDim2.new(1, 0, 0, 28), Text = "✅", TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
		K.text(stack, { Name = "Title", Size = UDim2.new(1, 0, 0, 18), Text = "광안 콜택시 · 영수증", TextColor3 = Color3.fromRGB(90, 96, 112), Font = K.Font.bold, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })
		rcFare = K.text(stack, { Name = "Fare", Size = UDim2.new(1, 0, 0, 32), Text = "", TextColor3 = dark, Font = K.Font.bold, TextSize = K.Type.display, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3 })
		K.mono(rcFare)
		local sep = K.frame(stack, { Name = "Dash", Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0.6, BackgroundColor3 = Color3.fromRGB(150, 156, 170), LayoutOrder = 4 })
		local _ = sep
		for i, def in { { "from", "출발" }, { "to", "도착" }, { "dist", "거리" }, { "pay", "결제" }, { "driver", "기사" } } do
			local r = K.frame(stack, { Name = "Row_" .. def[1], Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 4 + i })
			K.text(r, { Name = "Label", Size = UDim2.new(0.3, 0, 1, 0), Text = def[2], TextColor3 = Color3.fromRGB(110, 116, 130), TextSize = K.Type.caption })
			rcRows[def[1]] = K.text(r, { Name = "Value", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.7, 0, 1, 0), Text = "", TextColor3 = dark, Font = K.Font.bold, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
		end

		notice = K.EmptyState(body, { name = "Notice", icon = "🚫", title = "", body = "" })
		notice.frame.Visible = false

		actionBar = K.frame(body, { Name = "Actions", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 56) })
		K.pad(actionBar, 12, 12, 6, 6)
		K.list(actionBar, true, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		secondary = K.Button(actionBar, { name = "Secondary", text = "취소", style = "secondary", size = UDim2.new(0.36, -5, 0, 44), order = 1 })
		secondary.Visible = false
		primary = K.Button(actionBar, { name = "Primary", text = "🚕 택시 호출", style = "gold", size = UDim2.new(1, 0, 0, 44), order = 2 })
		primary.Activated:Connect(function()
			if not primary:GetAttribute("Disabled") then
				onPrimary()
			end
		end)
		secondary.Activated:Connect(onSecondary)

		Net.on("taxi", function(t: any)
			requesting = 0
			if t.state ~= "coming" and t.state ~= "arrived" then
				choosing = false
			end
			if t.state == "riding" then
				if t.destination then
					selected = t.destination
				end
				if not rideStart then
					rideStart = { pos = rootPos(), at = os.clock(), from = nil }
				end
			elseif t.state == "done" then
				lastReceipt = t
			elseif t.state == "coming" and not rideStart then
				rideStart = { pos = rootPos(), at = os.clock(), from = nil }
			end
			if visible then
				render()
				if t.state == "coming" then
					tick()
				end
			end
		end)
		Net.on("status", function()
			if visible then
				render()
			end
		end)
		Dest.onChanged(function()
			rowNames = ""
			if visible then
				refreshRows()
			end
		end)
		ctx.phone.onLayout(layout)
		layout()
	end

	function app.show(args: any)
		visible = true
		currentView = nil -- appear directly on the current step (no transition when (re)opening)
		layout()
		if type(args) == "table" and type(args.destination) == "string" then
			selected = Dest.resolve(args.destination)
			search.clear()
		end
		refreshRows()
		render()
		if state() == "coming" or state() == "riding" or (type(args) == "table" and args.called) then
			if type(args) == "table" and args.called and state() == "idle" then
				requesting = os.clock()
			end
			tick()
		end
		local _ = lastReceipt
	end

	function app.hide()
		visible = false
		tickSerial += 1
		runRoad(false)
		setRadar(false)
		search.release()
	end

	app.refresh = function()
		if visible then
			render()
		end
	end

	return app
end
