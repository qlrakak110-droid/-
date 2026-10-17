-- GwangalliCarDealer/Detail (client): one car's page inside the catalog — a 3D studio stage (auto-turn, drag /
-- pinch / wheel / right stick to orbit and zoom, ↺ reset), 신차 / 중고 switch (kit cars), 8 paint colours (the
-- garage's own GS.COLORS, previewed on the 3D model), price box with the dealer's benefits (이달의 특가, 레벨
-- 혜택) and the 할부 quote (계약금 · 하루 납입 × 일수 · 총 할부금), live affordability, specs from the game's
-- handling data (최고 속도 · 구동 · 정원 · 파워트레인 · 연비 · 공차 중량) with rating bars, the player's own test
-- record, and the actions 🏁 시승하기 · 🛒 계약하기 (or 🔑 하루 렌트) · ❤ 찜 · ⇄ 비교 담기.
--   Detail.mount(host)   Detail.show(entry)   Detail.hide()   Detail.isOpen()   Detail.refresh()   Detail.layout()

local Players = game:GetService("Players")

local Detail = {}

local ctx: any
local Ui: any
local C: any
local U: any
local Cat: any
local Col: any

local host: Frame
local panel: Frame
local stageHolder: Frame
local stage: any = nil
local info: ScrollingFrame
local actions: Frame
local backBtn: any
local zoomIn: any
local zoomOut: any
local resetBtn: any

local testBtn: any
local buyBtn: any
local wishBtn: any
local cmpBtn: any
local reasonLbl: TextLabel

local current: any = nil
local colorId = "white"
local loanOn = false
local openFlag = false
local _player = Players.LocalPlayer

local function snap(): any
	return ctx.Net.state.snap or {}
end

local function clearInfo()
	for _, ch in info:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
end

local function section(order: number, h: number?): Frame
	local f = Ui.frame(info, { Name = "S" .. order, Size = UDim2.new(1, -8, 0, h or 0), AutomaticSize = if h then Enum.AutomaticSize.None else Enum.AutomaticSize.Y, LayoutOrder = order })
	return f
end

local function card(order: number): Frame
	local f = Ui.glass(info, { Name = "Card" .. order, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, BackgroundColor3 = Col.card })
	Ui.pad(f, 14, 14, 12, 12)
	Ui.list(f, "y", 6)
	return f
end

local function row(parent: Instance, order: number, left: string, right: string, opts: { [string]: any }?): Frame
	local o = opts or {}
	local r = Ui.frame(parent, { Name = "Row" .. order, Size = UDim2.new(1, 0, 0, o.h or 20), LayoutOrder = order })
	Ui.label(r, { Text = left, Font = o.leftFont or Ui.F.med, TextSize = o.size or 13, TextColor3 = o.leftColor or Col.sub, Size = UDim2.new(0.5, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.label(r, { Text = right, Font = o.rightFont or Ui.F.bold, TextSize = o.rightSize or o.size or 13, TextColor3 = o.rightColor or Col.ink, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.62, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
	return r
end

local function colorName(id: string): string
	local GS = ctx.GS
	if GS and type(GS.colorEntry) == "function" then
		local ok, c = pcall(GS.colorEntry, id)
		if ok and c then
			return c.name
		end
	end
	return id
end

-------------------------------------------------------------------------------------------------
-- content
-------------------------------------------------------------------------------------------------
local function reasons(e: any): (string?, string?, boolean, boolean)
	-- -> testReason?, buyReason?, canTest, canBuy
	local s = snap()
	local testR, buyR = nil, nil
	local canTest, canBuy = true, true
	if s.garageReady == false then
		return "정비소 전산 점검 중", "정비소 전산 점검 중", false, false
	end
	if e.grade == "rent" then
		canTest = false
		if s.rentActive then
			canBuy = false
			buyR = "이미 렌트한 차가 있어요 · '내 차'에서 부를 수 있어요"
		end
	else
		if s.testing then
			canTest = false
			testR = "시승이 끝난 뒤 다시 신청할 수 있어요"
		elseif (s.testCooldown or 0) > 0.5 then
			canTest = false
			testR = string.format("시승차 정비 중 · %d초 뒤 가능", math.ceil(s.testCooldown))
		end
		if e.owned and e.model then
			canBuy = false
			buyR = "이미 가진 차예요 · '내 차'에서 부를 수 있어요"
		elseif e.lock then
			canBuy = false
			buyR = "🔒 " .. e.lock.why .. " · 지금은 시승만 할 수 있어요"
		elseif (s.owned or 0) >= (s.max or 3) then
			buyR = string.format("차고가 가득 찼어요 (%d/%d) · 보상판매로 바꿀 수 있어요", s.owned or 0, s.max or 3)
		end
	end
	if s.near == false then
		local far = "매장에서 상담원과 시승 · 계약할 수 있어요"
		testR = testR or far
		buyR = buyR or far
	end
	return testR, buyR, canTest, canBuy
end

local function buildContent(e: any)
	clearInfo()
	local GS = ctx.GS
	local s = snap()
	local bank, cash = ctx.Net.money()
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	-- title
	local t = section(nextOrder())
	Ui.list(t, "y", 4)
	local badges = Ui.frame(t, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1 })
	Ui.list(badges, "x", 4)
	local bn = 0
	local function badge(text: string, tone: Color3)
		bn += 1
		Ui.badge(badges, text, tone, { order = bn })
	end
	if e.isNew then
		badge("NEW", Col.pink)
	end
	if e.special then
		badge("🔥 이달의 특가", Col.gold)
	end
	badge(Cat.gradeLabel(e), if e.grade == "used" then Col.orange elseif e.grade == "rent" then Col.green else Col.accent)
	if e.owned then
		badge("보유 중", Col.green)
	end
	if e.tag then
		badge("✨ " .. e.tag, Color3.fromRGB(70, 60, 120))
	end
	Ui.label(t, { Text = e.name, Font = Ui.F.black, TextSize = 24, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 2, TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.label(t, { Text = Cat.subline(e) .. " · " .. tostring(e.brand or ""), Font = Ui.F.med, TextSize = 13, TextColor3 = Col.sub, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 3 })
	if e.blurb and e.blurb ~= "" then
		Ui.label(t, { Text = e.blurb, Font = Ui.F.reg, TextSize = 13, TextColor3 = Col.sub, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 4 })
	end

	-- grade switch (kit)
	local sib = Cat.sibling(e, ctx.Net.state.byId)
	if sib then
		local g = section(nextOrder(), 40)
		Ui.list(g, "x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		local newE = if e.grade == "new" then e else sib
		local usedE = if e.grade == "used" then e else sib
		for i, pair in { { newE, "신차" }, { usedE, "중고" } } do
			local en = pair[1]
			Ui.chip(g, {
				text = string.format("%s · %s", pair[2], U.man(en.price)),
				order = i,
				height = 36,
				textSize = 13,
				on = en.id == e.id,
				tone = if pair[2] == "중고" then Col.orange else Col.accent,
				onClick = function()
					if en.id ~= e.id then
						Detail.show(en)
					end
				end,
			})
		end
	end

	-- colours
	if e.grade ~= "rent" and GS and type(GS.COLORS) == "table" then
		local cc = section(nextOrder())
		Ui.list(cc, "y", 6)
		Ui.label(cc, { Text = "색상 · " .. colorName(colorId), Font = Ui.F.bold, TextSize = 13, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1 })
		local sw = Ui.frame(cc, { Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 2 })
		Ui.list(sw, "x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		for i, c in GS.COLORS do
			local b = Ui.make("TextButton", { Name = "Color_" .. c.id, Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(30, 30), BackgroundColor3 = Color3.fromRGB(c.rgb[1], c.rgb[2], c.rgb[3]), LayoutOrder = i, Selectable = true }, sw)
			Ui.corner(b, 15)
			Ui.stroke(b, if c.id == colorId then Col.accent else Col.line, if c.id == colorId then 3 else 1, if c.id == colorId then 0 else 0.6)
			b.Activated:Connect(function()
				Ui.sfx("toggle")
				colorId = c.id
				if stage then
					stage:setColor(colorId)
				end
				buildContent(e)
			end)
		end
		if e.model and GS.DEFAULT_COLOR then
			Ui.label(cc, { Text = "쇼룸 모델은 기본 색상(" .. colorName(GS.DEFAULT_COLOR) .. ")이 공장 출고 도색이에요", Font = Ui.F.reg, TextSize = 11, TextColor3 = Col.faint, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 3 })
		end
	end

	-- price
	local pc = card(nextOrder())
	local ben = Cat.benefits(e, { usedRate = ctx.Net.usedRate(), special = e.special })
	row(pc, 1, if e.grade == "rent" then "렌트비 (게임 시간 하루)" else "차량 가격", U.man(e.price) .. "  (" .. U.won(e.price) .. ")", { rightSize = 14 })
	local ro = 1
	for _, l in ben.lines do
		ro += 1
		local label = if l.key == "special" then string.format("🔥 이달의 특가 %s 환급", U.pct(l.rate)) else string.format("⭐ 레벨 혜택 · 중고차 %s 환급", U.pct(l.rate))
		row(pc, ro, label, "-" .. U.won(l.amount), { rightColor = Col.gold, leftColor = Col.gold })
	end
	if ben.total > 0 then
		ro += 1
		row(pc, ro, "실 구매가 (출고 후 통장 환급)", U.man(e.price - ben.total), { h = 24, size = 14, leftFont = Ui.F.bold, leftColor = Col.ink, rightFont = Ui.F.black, rightSize = 17 })
	end
	if e.canLoan and e.loan then
		ro += 1
		local gates = s.gates or {}
		local loanLocked = gates.enforce and gates.hasLoan == false
		local blocked = s.loanBlocked == true
		local lr = Ui.frame(pc, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = ro })
		local chip = Ui.chip(lr, {
			text = if loanOn then "📅 할부로 살게요 ✓" else "📅 할부로 살게요",
			height = 36,
			textSize = 13,
			on = loanOn,
			onClick = function()
				if blocked or loanLocked then
					Ui.toast({ kind = "info", icon = "📅", title = "할부를 이용할 수 없어요", body = if blocked then "밀린 할부가 있어서 새 할부를 할 수 없어요" else string.format("할부는 레벨 %d부터 이용할 수 있어요", gates.loanLevel or 8) })
					return
				end
				loanOn = not loanOn
				buildContent(e)
				Detail.updateActions()
			end,
		})
		local _ = chip
		if blocked or loanLocked then
			Ui.label(lr, { Text = if blocked then "밀린 할부가 있어요" else string.format("레벨 %d부터", gates.loanLevel or 8), Font = Ui.F.bold, TextSize = 12, TextColor3 = Col.red, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(160, 18), TextXAlignment = Enum.TextXAlignment.Right })
		end
		if loanOn then
			local q = e.loan
			local rate = if ctx.GS and ctx.GS.LOAN then ctx.GS.LOAN.rate else 0.05
			ro += 1
			row(pc, ro, string.format("계약금 (%s)", U.pct(if ctx.GS and ctx.GS.LOAN then ctx.GS.LOAN.down else 0.3)), U.won(q.down), { rightColor = Col.accent, rightSize = 15 })
			ro += 1
			row(pc, ro, "하루 납입", string.format("%s × %d일", U.won(q.daily), q.days))
			ro += 1
			row(pc, ro, string.format("총 할부금 (이자 %s)", U.pct(rate)), U.won(q.total))
			ro += 1
			Ui.label(pc, { Text = "할부금은 매일 통장에서 자동으로 빠져나가요 · 3번 밀리면 차가 회수돼요", Font = Ui.F.reg, TextSize = 11, TextColor3 = Col.faint, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = ro })
		end
	end
	-- affordability
	if e.grade ~= "rent" then
		ro += 1
		local due = if loanOn and e.loan then e.loan.down else e.price
		local okBank, okCash = bank >= due, cash >= due
		local txt, colr
		if okBank then
			txt, colr = string.format("✔ 통장에서 바로 결제돼요 · 결제 후 통장 %s", U.won(bank - due)), Col.green
		elseif okCash then
			txt, colr = string.format("✔ 현금으로 결제돼요 · 결제 후 현금 %s", U.won(cash - due)), Col.green
		else
			local short = due - math.max(bank, cash)
			txt, colr = string.format("✖ %s 부족해요 (통장 %s · 현금 %s)%s", U.won(short), U.man(bank), U.man(cash), if not loanOn and e.canLoan then " · 할부를 이용해 보세요" else ""), Col.red
		end
		Ui.label(pc, { Text = txt, Font = Ui.F.bold, TextSize = 12, TextColor3 = colr, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = ro })
	end

	-- notes
	local notes = {}
	if e.cond then
		table.insert(notes, string.format("🔧 중고차 상태 %d~%d%% (출고 때 정해져요) · 정비 베이에서 수리할 수 있어요", e.cond[1], e.cond[2]))
	end
	if e.deliverAs then
		table.insert(notes, "ℹ 3D 모델 준비 중 · 출고 차량은 동급 " .. e.deliverAs .. "예요")
	end
	if e.grade == "rent" then
		table.insert(notes, string.format("🔑 게임 시간 하루(%d분) 동안 타요 · 차고 대수에 안 들어가요 · 허 번호판", math.floor((e.rentSeconds or 2400) / 60)))
	else
		table.insert(notes, "🪪 부산 번호판 자동 발급 · 정비소 앞 출고 라인에서 인도해 드려요")
	end
	if e.best then
		table.insert(notes, string.format("🏁 내 시승 기록 · 최고 %dkm/h · %s", e.best.kmh or 0, U.meters(e.best.m or 0)))
	elseif e.tested then
		table.insert(notes, "🏁 시승해 본 차예요")
	end
	local nc = card(nextOrder())
	for i, n in notes do
		Ui.label(nc, { Text = n, Font = Ui.F.med, TextSize = 12, TextColor3 = Col.sub, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = i })
	end

	-- specs
	local sc = card(nextOrder())
	Ui.label(sc, { Text = "제원", Font = Ui.F.bold, TextSize = 14, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 0 })
	local p = e.perf
	local specs = {
		{ "최고 속도", string.format("%d km/h", p.top) },
		{ "구동 방식", Cat.DRIVE_KO[p.drive] or p.drive },
		{ "승차 정원", string.format("%d인승", e.seats or 5) },
		{ "파워트레인", e.fuel or "-" },
		{ "연비", e.eff or "-" },
		{ "공차 중량", U.comma(math.floor(p.mass * C.MASS_TO_KG / 10 + 0.5) * 10) .. " kg" },
		{ "차체", e.body or "-" },
	}
	for i, sp in specs do
		row(sc, i, sp[1], sp[2])
	end
	local bars = e.bars
	local bl = { { "가속", bars.accel }, { "최고 속도", bars.top }, { "제동", bars.brake }, { "승차감", bars.comfort }, { "실용성", bars.utility } }
	for i, b in bl do
		local r = Ui.frame(sc, { Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 20 + i })
		Ui.label(r, { Text = b[1], Font = Ui.F.med, TextSize = 12, TextColor3 = Col.sub, Size = UDim2.new(0.4, 0, 1, 0) })
		Ui.dots(r, b[2], 5, Col.accent, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0) })
	end
	local _ = s
end

-------------------------------------------------------------------------------------------------
-- actions
-------------------------------------------------------------------------------------------------
function Detail.updateActions()
	local e = current
	if not e or not testBtn then
		return
	end
	local testR, buyR, canTest, canBuy = reasons(e)
	local s = snap()
	testBtn.inst.Visible = e.grade ~= "rent"
	testBtn.setEnabled(canTest)
	local secs = if e.model and e.available then C.TEST.seconds else 60
	testBtn.setText(string.format("시승하기 (%d초)", secs), "🏁")
	if e.grade == "rent" then
		buyBtn.setText("하루 렌트 · " .. U.man(e.price), "🔑")
	elseif (s.owned or 0) >= (s.max or 3) and not (e.owned and e.model) then
		buyBtn.setText("보상판매로 계약", "🔁")
	else
		buyBtn.setText(if loanOn and e.canLoan then "할부로 계약하기" else "계약하기", "🛒")
	end
	buyBtn.setEnabled(canBuy)
	local wished = ctx.Net.state.wish[e.id] == true
	wishBtn.setText(if wished then "❤" else "♡")
	wishBtn.label.TextColor3 = if wished then Col.pink else Col.ink
	local inCmp = ctx.CatalogUI.inCompare(e.id)
	cmpBtn.setText(if inCmp then "⇄ ✓" else "⇄")
	cmpBtn.inst.Visible = e.grade ~= "rent"
	reasonLbl.Text = buyR or testR or ""
	reasonLbl.Visible = reasonLbl.Text ~= ""
end

local function farGuard(): boolean
	if snap().near == false then
		ctx.Contract.notice("📍 매장에서 상담해 주세요", "시승과 계약은 광안 오토 매장에서 상담원과 할 수 있어요. 지도에 길을 표시해 드릴까요?", "🧭 길 안내", function()
			ctx.Net.call("waypoint", nil)
		end)
		return true
	end
	return false
end

local function onTest()
	local e = current
	if not e or farGuard() then
		return
	end
	local _, _, canTest = reasons(e)
	if not canTest then
		local testR = reasons(e)
		Ui.toast({ kind = "info", icon = "🏁", title = "지금은 시승할 수 없어요", body = testR or "" })
		return
	end
	testBtn.setEnabled(false)
	testBtn.setText("시승차 준비 중…", "⏳")
	local res = ctx.TestHud.request(e, colorId)
	if res.ok then
		ctx.CatalogUI.close()
	else
		Ui.toast({ kind = "error", icon = "🏁", title = "시승을 시작하지 못했어요", body = res.message or "" })
		ctx.Net.refresh()
		Detail.updateActions()
	end
end

local function onBuy()
	local e = current
	if not e or farGuard() then
		return
	end
	local _, buyR, _, canBuy = reasons(e)
	if not canBuy then
		Ui.toast({ kind = "info", icon = "🛒", title = "지금은 계약할 수 없어요", body = buyR or "" })
		return
	end
	if e.grade == "rent" then
		ctx.Contract.rent(e)
		return
	end
	local s = snap()
	ctx.Contract.open(e, { colorId = colorId, loan = loanOn and e.canLoan, trade = ctx.CatalogUI.tradeMode() or (s.owned or 0) >= (s.max or 3) })
end

-------------------------------------------------------------------------------------------------
-- layout / mount
-------------------------------------------------------------------------------------------------
function Detail.layout()
	if not panel or not openFlag then
		return
	end
	local W, H = host.AbsoluteSize.X, host.AbsoluteSize.Y
	if W <= 0 or H <= 0 then
		task.defer(Detail.layout)
		return
	end
	local m = Ui.metrics()
	local actH = if m.compact then 50 else 58
	local split = W >= H * 1.25 and W >= 700
	if split then
		local sw = math.floor(W * 0.5)
		stageHolder.Position = UDim2.fromOffset(12, 12)
		stageHolder.Size = UDim2.new(0, sw - 18, 1, -24 - actH - 8)
		info.Position = UDim2.fromOffset(sw + 6, 12)
		info.Size = UDim2.new(1, -sw - 18, 1, -24 - actH - 8)
	else
		local sh = math.floor(math.clamp(H * 0.38, 160, 320))
		stageHolder.Position = UDim2.fromOffset(12, 12)
		stageHolder.Size = UDim2.new(1, -24, 0, sh)
		info.Position = UDim2.fromOffset(12, 12 + sh + 10)
		info.Size = UDim2.new(1, -24, 1, -(12 + sh + 10) - actH - 16)
	end
	actions.Size = UDim2.new(1, -24, 0, actH)
	actions.Position = UDim2.new(0, 12, 1, -actH - 10)
	local bw = W - 24
	local small = if m.compact then 44 else 50
	local wide = math.max(110, (bw - small * 2 - 8 * 3) / 2)
	testBtn.inst.Size = UDim2.fromOffset(wide, actH - 6)
	buyBtn.inst.Size = UDim2.fromOffset(wide, actH - 6)
	wishBtn.inst.Size = UDim2.fromOffset(small, actH - 6)
	cmpBtn.inst.Size = UDim2.fromOffset(small, actH - 6)
	reasonLbl.Position = UDim2.new(0, 12, 1, -actH - 30)
	if current and current.grade == "rent" then
		buyBtn.inst.Size = UDim2.fromOffset(bw - small - 8, actH - 6)
	end
end

function Detail.mount(h: Frame)
	host = h
	panel = Ui.glass(host, { Name = "Panel", BackgroundColor3 = Col.bg2, BackgroundTransparency = 0.02, ZIndex = 10 })
	stageHolder = Ui.frame(panel, { Name = "StageHolder", ZIndex = 11 })
	info = Ui.scroll(panel, { Name = "Info", ZIndex = 11 })
	Ui.list(info, "y", 12)
	Ui.pad(info, 0, 4, 0, 10)
	actions = Ui.frame(panel, { Name = "Actions", ZIndex = 12 })
	Ui.list(actions, "x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	testBtn = Ui.button(actions, { name = "Test", text = "시승하기", icon = "🏁", style = "secondary", order = 1, textSize = 14, z = 12 })
	buyBtn = Ui.button(actions, { name = "Buy", text = "계약하기", icon = "🛒", style = "primary", order = 2, textSize = 15, z = 12 })
	wishBtn = Ui.button(actions, { name = "Wish", text = "♡", style = "secondary", order = 3, textSize = 18, z = 12 })
	cmpBtn = Ui.button(actions, { name = "Compare", text = "⇄", style = "secondary", order = 4, textSize = 15, z = 12 })
	testBtn.onClick(onTest)
	buyBtn.onClick(onBuy)
	wishBtn.onClick(function()
		if current then
			ctx.CatalogUI.toggleWish(current.id)
		end
	end)
	cmpBtn.onClick(function()
		if current then
			ctx.CatalogUI.toggleCompare(current.id)
			Ui.toast({ kind = "info", icon = "⇄", title = "비교함", body = "두 대를 담으면 아래 '비교하기'로 나란히 볼 수 있어요" })
		end
	end)
	reasonLbl = Ui.label(panel, { Name = "Reason", Font = Ui.F.bold, TextSize = 12, TextColor3 = Col.orange, Size = UDim2.new(1, -24, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12, Visible = false })
	backBtn = Ui.button(panel, { name = "Back", text = "← 목록", style = "secondary", size = UDim2.fromOffset(84, 34), pos = UDim2.fromOffset(20, 20), textSize = 13, radius = 17, z = 15 })
	backBtn.onClick(function()
		ctx.CatalogUI.closeDetail()
	end)
	zoomIn = Ui.button(panel, { name = "ZoomIn", text = "+", style = "ghost", size = UDim2.fromOffset(34, 34), textSize = 18, radius = 17, z = 15 })
	zoomOut = Ui.button(panel, { name = "ZoomOut", text = "−", style = "ghost", size = UDim2.fromOffset(34, 34), textSize = 18, radius = 17, z = 15 })
	resetBtn = Ui.button(panel, { name = "Reset", text = "↺", style = "ghost", size = UDim2.fromOffset(34, 34), textSize = 16, radius = 17, z = 15 })
	zoomIn.onClick(function()
		if stage then
			stage:zoom(-0.12)
		end
	end)
	zoomOut.onClick(function()
		if stage then
			stage:zoom(0.12)
		end
	end)
	resetBtn.onClick(function()
		if stage then
			stage:reset()
		end
	end)
	stageHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local p, s = stageHolder.AbsolutePosition - panel.AbsolutePosition, stageHolder.AbsoluteSize
		zoomIn.inst.Position = UDim2.fromOffset(p.X + s.X - 44, p.Y + 10)
		zoomOut.inst.Position = UDim2.fromOffset(p.X + s.X - 44, p.Y + 50)
		resetBtn.inst.Position = UDim2.fromOffset(p.X + s.X - 44, p.Y + 90)
	end)
	stageHolder:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		local p, s = stageHolder.AbsolutePosition - panel.AbsolutePosition, stageHolder.AbsoluteSize
		zoomIn.inst.Position = UDim2.fromOffset(p.X + s.X - 44, p.Y + 10)
		zoomOut.inst.Position = UDim2.fromOffset(p.X + s.X - 44, p.Y + 50)
		resetBtn.inst.Position = UDim2.fromOffset(p.X + s.X - 44, p.Y + 90)
	end)
	host:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if openFlag then
			Detail.layout()
		end
	end)
	local hint = Ui.label(stageHolder, { Name = "Hint", Text = "↔ 드래그해서 돌려 보세요", Font = Ui.F.med, TextSize = 11, TextColor3 = Col.sub, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(200, 14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 14 })
	local _ = hint
end

function Detail.isOpen(): boolean
	return openFlag
end

function Detail.current(): any
	return current
end

function Detail.show(e: any)
	local GS = ctx.GS
	local same = current and current.id == e.id
	if not current or (current.kind ~= e.kind or current.model ~= e.model) then
		colorId = (GS and GS.DEFAULT_COLOR) or "white"
		loanOn = false
	end
	if not e.canLoan then
		loanOn = false
	end
	current = e
	openFlag = true
	host.Visible = true
	if not stage then
		stage = ctx.Viewport.stage(stageHolder, { interactive = true, zIndex = 12 })
	end
	if not same then
		stage:set(e.preview, if e.grade == "rent" then "mint" else colorId, e.grade == "used", e.glyph)
		stage:reset()
	end
	buildContent(e)
	info.CanvasPosition = Vector2.zero
	Detail.updateActions()
	Detail.layout()
	if Ui.metrics().gamepad then
		Ui.select(buyBtn.inst)
	end
end

function Detail.refresh()
	if not openFlag or not current then
		return
	end
	local fresh = ctx.Net.state.byId[current.id]
	if fresh then
		current = fresh
	end
	buildContent(current)
	Detail.updateActions()
end

function Detail.hide()
	if not openFlag then
		return
	end
	openFlag = false
	if host then
		host.Visible = false
	end
	if stage then
		stage:destroy()
		stage = nil
	end
	current = nil
end

function Detail.init(c: any)
	ctx = c
	Ui = c.Ui
	C = c.C
	U = c.S.Util
	Cat = c.S.Catalog
	Col = Ui.C
end

return Detail
