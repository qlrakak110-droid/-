-- GwangalliCarDealer/Contract (client): the modal sheets of the dealer.
--   Contract.open(entry, { colorId, loan, trade })  견적서 · 계약서: 차량 / 색상 / 결제 방식 / 차량 가격 / 오늘 결제 /
--       할부 조건 / 출고 후 환급 / 보상판매 (pick the car to trade in) / 결제 계좌 and 잔액 before → after, then
--       "길게 눌러 서명하기" (hold C.UI.signHold s) → server buy (idempotent nonce) → 출고 ceremony
--   Contract.sell(carView) -> result?   매각 확인 (매입가 · 남은 할부 · 통장 입금) with hold-to-confirm (yields)
--   Contract.rent(entry)               하루 렌트 확인
--   Contract.compare(idA, idB)         side-by-side comparison
--   Contract.notice(title, body, okText?, onOk?)   simple notice / confirm
--   Contract.isOpen()

local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local Contract = {}

local ctx: any
local Ui: any
local C: any
local U: any
local Cat: any
local Col: any

local gui: ScreenGui
local dim: TextButton
local sheet: Frame
local body: ScrollingFrame
local titleLbl: TextLabel
local footer: Frame
local openFlag = false
local closeCb: (() -> ())? = nil

local function build()
	gui = Ui.screen("GwangalliCarDealerContract", C.UI.order.contract)
	dim = Ui.make("TextButton", { Name = "Dim", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1), Selectable = false }, gui)
	sheet = Ui.glass(gui, { Name = "Sheet", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Col.bg2, BackgroundTransparency = 0.01, ZIndex = 2 })
	Ui.grad(sheet, Color3.fromRGB(255, 255, 255), Color3.fromRGB(215, 220, 232), 90)
	titleLbl = Ui.label(sheet, { Name = "Title", Font = Ui.F.black, TextSize = 19, Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -80, 0, 28), ZIndex = 3 })
	local x = Ui.button(sheet, { name = "Close", text = "✕", style = "ghost", size = UDim2.fromOffset(34, 34), anchor = Vector2.new(1, 0), pos = UDim2.new(1, -12, 0, 12), radius = 17, z = 4 })
	x.onClick(function()
		Contract.close()
	end)
	body = Ui.scroll(sheet, { Name = "Body", Position = UDim2.fromOffset(20, 52), ZIndex = 3 })
	Ui.list(body, "y", 8)
	Ui.pad(body, 0, 6, 0, 8)
	footer = Ui.frame(sheet, { Name = "Footer", ZIndex = 3 })
	Ui.list(footer, "x", 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
end

local function layout(hFooter: number?)
	local m = Ui.metrics()
	local W = math.min(560, m.w - 24)
	local H = math.min(m.h - m.inset - 24, if m.compact then m.h - m.inset - 16 else 640)
	sheet.Size = UDim2.fromOffset(W, H)
	sheet.Position = UDim2.new(0.5, 0, 0.5, m.inset / 2)
	local fh = hFooter or 60
	body.Size = UDim2.new(1, -40, 1, -52 - fh - 12)
	footer.Position = UDim2.new(0, 20, 1, -fh - 10)
	footer.Size = UDim2.new(1, -40, 0, fh)
end

local function clear()
	for _, ch in body:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	for _, ch in footer:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
end

local function bindBack(on: boolean)
	if on then
		ContextActionService:BindActionAtPriority("GwCarDealerContractBack", function(_, st)
			if st == Enum.UserInputState.Begin and not UserInputService:GetFocusedTextBox() then
				Contract.close()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, 3100, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction("GwCarDealerContractBack")
	end
end

local function show(title: string)
	if not gui then
		build()
	end
	clear()
	titleLbl.Text = title
	layout()
	openFlag = true
	Ui.show(gui, true)
	Ui.controls("contract", false)
	bindBack(true)
	if not Ui.reduced() then
		local sc = sheet:FindFirstChildOfClass("UIScale") or Ui.make("UIScale", {}, sheet)
		sc.Scale = 0.94
		Ui.tween(sc, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	Ui.sfx("open")
end

function Contract.isOpen(): boolean
	return openFlag
end

function Contract.close()
	if not openFlag then
		return
	end
	openFlag = false
	bindBack(false)
	Ui.controls("contract", true)
	Ui.deselect(gui)
	Ui.show(gui, false)
	local cb = closeCb
	closeCb = nil
	if cb then
		task.spawn(cb)
	end
end

-- rows ------------------------------------------------------------------------------------------------------
local orderN = 0
local function nextOrder(): number
	orderN += 1
	return orderN
end

local function line(left: string, right: string, opts: { [string]: any }?): Frame
	local o = opts or {}
	local r = Ui.frame(body, { Size = UDim2.new(1, 0, 0, o.h or 22), LayoutOrder = nextOrder(), ZIndex = 3 })
	Ui.label(r, { Text = left, Font = o.leftFont or Ui.F.med, TextSize = o.size or 14, TextColor3 = o.leftColor or Col.sub, Size = UDim2.new(0.45, 0, 1, 0), ZIndex = 3, TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.label(r, { Text = right, Font = o.rightFont or Ui.F.bold, TextSize = o.rightSize or o.size or 14, TextColor3 = o.rightColor or Col.ink, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.6, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3, TextTruncate = Enum.TextTruncate.AtEnd })
	return r
end

local function rule()
	local f = Ui.frame(body, { Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0.88, BackgroundColor3 = Col.line, LayoutOrder = nextOrder(), ZIndex = 3 })
	return f
end

local function para(text: string, color: Color3?, size: number?): TextLabel
	return Ui.label(body, { Text = text, Font = Ui.F.med, TextSize = size or 12, TextColor3 = color or Col.faint, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder(), ZIndex = 3 })
end

-- Hold-to-confirm button: fills over C.UI.signHold seconds of holding (mouse / touch / gamepad A / Enter).
local function holdButton(parent: Instance, text: string, style: string, width: number, onDone: () -> ()): any
	local b = Ui.button(parent, { name = "Hold", text = text, style = style, size = UDim2.fromOffset(width, 48), order = 10, textSize = 15, z = 4, sound = "toggle" })
	local fill = Ui.frame(b.inst, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundTransparency = 0.55, BackgroundColor3 = Col.white, ZIndex = 4 })
	local holding = false
	local t0 = 0
	local fired = false
	local conn: RBXScriptConnection? = nil
	local function stop()
		holding = false
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if not fired then
			Ui.tween(fill, 0.15, { Size = UDim2.fromScale(0, 1) })
		end
	end
	local function start()
		if holding or fired or not b.enabled then
			return
		end
		holding = true
		t0 = os.clock()
		conn = RunService.RenderStepped:Connect(function()
			local k = math.clamp((os.clock() - t0) / C.UI.signHold, 0, 1)
			fill.Size = UDim2.fromScale(k, 1)
			if k >= 1 and not fired then
				fired = true
				stop()
				Ui.sfx("success")
				task.spawn(onDone)
			end
		end)
	end
	b.inst.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			start()
		end
	end)
	b.inst.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			stop()
		end
	end)
	b.inst.MouseLeave:Connect(stop)
	local keyConnA = UserInputService.InputBegan:Connect(function(input: InputObject)
		if not openFlag then
			return
		end
		local kc = input.KeyCode
		if (kc == Enum.KeyCode.ButtonA and game:GetService("GuiService").SelectedObject == b.inst) or (kc == Enum.KeyCode.Return and not UserInputService:GetFocusedTextBox()) then
			start()
		end
	end)
	local keyConnB = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Return then
			stop()
		end
	end)
	b.inst.Destroying:Connect(function()
		keyConnA:Disconnect()
		keyConnB:Disconnect()
		stop()
	end)
	local api = b
	function api.reset()
		fired = false
		fill.Size = UDim2.fromScale(0, 1)
	end
	return api
end

-------------------------------------------------------------------------------------------------
-- purchase
-------------------------------------------------------------------------------------------------
function Contract.open(e: any, opts: { [string]: any })
	local GS = ctx.GS
	local colorId = opts.colorId or (GS and GS.DEFAULT_COLOR) or "white"
	local loan = opts.loan == true and e.canLoan and e.loan ~= nil
	local snap = ctx.Net.state.snap or {}
	local cars = ctx.Net.ownedCars()
	local full = (snap.owned or 0) >= (snap.max or 3)
	local tradeOn = (opts.trade == true or full) and #cars > 0 and C.TRADEIN.enabled
	local tradeId: string? = nil
	local nonce = ctx.Net.nonce()
	local signBtn: any = nil
	local errLbl: TextLabel? = nil
	local busy = false

	local function render()
		orderN = 0
		clear()
		local bank, cash = ctx.Net.money()
		local ben = Cat.benefits(e, { usedRate = ctx.Net.usedRate(), special = e.special })
		local due = if loan then e.loan.down else e.price
		-- trade-in value
		local tradeCar = nil
		local tradePayout, tradeBonus = 0, 0
		if tradeId then
			for _, c in cars do
				if c.id == tradeId then
					tradeCar = c
				end
			end
			if tradeCar then
				local remaining = if type(tradeCar.loan) == "table" then (tradeCar.loan.remaining or 0) else 0
				tradePayout = math.max(0, (tradeCar.sell or 0) - remaining)
				tradeBonus = U.round100((tradeCar.sell or 0) * (snap.tradeBonus or 0))
			end
		end
		local bankAfterTrade = bank + tradePayout + tradeBonus

		line("차량", e.name .. " (" .. Cat.gradeLabel(e) .. ")", { rightSize = 15 })
		local colorName = colorId
		if GS and GS.colorEntry then
			local okC, ce = pcall(GS.colorEntry, colorId)
			colorName = if okC and ce then ce.name else colorId
		end
		line("색상", colorName)
		line("결제 방식", if loan then string.format("할부 (%d일)", e.loan.days) else "일시불")
		rule()
		line("차량 가격", U.won(e.price))
		if loan then
			line("오늘 결제 · 계약금", U.won(e.loan.down), { rightColor = Col.accent, rightSize = 16 })
			line("하루 납입", string.format("%s × %d일", U.won(e.loan.daily), e.loan.days))
			line("총 할부금", U.won(e.loan.total))
		else
			line("오늘 결제", U.won(e.price), { rightColor = Col.accent, rightSize = 16 })
		end
		for _, l in ben.lines do
			local label = if l.key == "special" then "🔥 이달의 특가 환급" else "⭐ 레벨 혜택 환급"
			line(label .. " " .. U.pct(l.rate), "+" .. U.won(l.amount) .. " (출고 후)", { rightColor = Col.gold, leftColor = Col.gold })
		end
		-- trade-in picker
		if C.TRADEIN.enabled and #cars > 0 then
			rule()
			local tr = Ui.frame(body, { Size = UDim2.new(1, 0, 0, 36), LayoutOrder = nextOrder(), ZIndex = 3 })
			Ui.chip(tr, {
				text = if tradeOn then "🔁 보상판매 사용 ✓" else "🔁 보상판매 사용",
				height = 34,
				textSize = 13,
				on = tradeOn,
				onClick = function()
					if full and tradeOn then
						Ui.toast({ kind = "info", icon = "🅿", title = "차고가 가득 찼어요", body = "보상판매할 차를 골라야 계약할 수 있어요" })
						return
					end
					tradeOn = not tradeOn
					if not tradeOn then
						tradeId = nil
					end
					render()
				end,
			})
			if tradeOn then
				for _, c in cars do
					local remaining = if type(c.loan) == "table" then (c.loan.remaining or 0) else 0
					local payout = (c.sell or 0) - remaining
					local okSell = payout >= 0
					local rowB = Ui.make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if tradeId == c.id then Col.accentSoft else Col.card, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = nextOrder(), ZIndex = 3, Selectable = true }, body)
					Ui.corner(rowB, 12)
					Ui.stroke(rowB, if tradeId == c.id then Col.accent else Col.line, if tradeId == c.id then 2 else 1, if tradeId == c.id then 0 else 0.86)
					Ui.label(rowB, { Text = string.format("%s %s · %s", if tradeId == c.id then "◉" else "○", c.label or "내 차", c.plate or ""), Font = Ui.F.bold, TextSize = 13, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 20), ZIndex = 4 })
					Ui.label(rowB, { Text = if okSell then string.format("매입가 %s%s → 통장 +%s", U.won(c.sell or 0), if remaining > 0 then " - 남은 할부 " .. U.won(remaining) else "", U.won(payout)) else "남은 할부가 매입가보다 많아 보상판매할 수 없어요", Font = Ui.F.med, TextSize = 11, TextColor3 = if okSell then Col.sub else Col.red, Position = UDim2.fromOffset(12, 24), Size = UDim2.new(1, -24, 0, 16), ZIndex = 4 })
					rowB.Activated:Connect(function()
						if not okSell then
							Ui.sfx("error")
							return
						end
						Ui.sfx("toggle")
						tradeId = if tradeId == c.id then nil else c.id
						render()
					end)
				end
				if tradeCar then
					line("보상판매 매각", "+" .. U.won(tradePayout), { rightColor = Col.green })
					if tradeBonus > 0 then
						line("보상판매 추가 정산금 " .. U.pct(snap.tradeBonus or 0), "+" .. U.won(tradeBonus), { rightColor = Col.green })
					end
				end
			end
		end
		-- account
		rule()
		local acct, afterB, afterC
		if bankAfterTrade >= due then
			acct, afterB, afterC = "통장에서 결제", bankAfterTrade - due, cash
		elseif cash >= due then
			acct, afterB, afterC = "현금에서 결제", bankAfterTrade, cash - due
		end
		line("결제 계좌", acct or "잔액 부족 (통장 우선 · 부족하면 현금)", { rightColor = if acct then Col.ink else Col.red })
		line("결제 전 잔액", string.format("통장 %s · 현금 %s", U.won(bank), U.won(cash)), { size = 13 })
		if acct then
			line("결제 후 잔액", string.format("통장 %s · 현금 %s", U.won(afterB), U.won(afterC)), { size = 13, rightColor = Col.green })
			if ben.total > 0 then
				line("환급 후 통장", U.won(afterB + ben.total), { size = 13, rightColor = Col.gold })
			end
		else
			local short = due - math.max(bankAfterTrade, cash)
			line("부족한 금액", U.won(short), { rightColor = Col.red })
		end
		rule()
		para("🪪 부산 번호판이 자동으로 발급되고, 정비소 앞 출고 라인에서 인도해 드려요. 차는 최대 " .. tostring(snap.max or 3) .. "대까지 가질 수 있어요.")
		if loan then
			para("📅 할부금은 매일 통장에서 자동 납부돼요. 잔액이 모자라 3번 밀리면 차가 회수되니 꼭 확인해 주세요.", Col.orange)
		end
		if e.deliverAs then
			para("ℹ 이 모델은 3D 차량 준비 중이라 동급 " .. e.deliverAs .. "로 출고돼요.", Col.orange)
		end
		errLbl = para("", Col.red, 13)
		-- footer
		local cancel = Ui.button(footer, { text = "취소", style = "ghost", size = UDim2.fromOffset(90, 48), order = 1, z = 4 })
		cancel.onClick(function()
			Contract.close()
		end)
		local needTrade = full and not tradeCar
		local canSign = acct ~= nil and not needTrade
		signBtn = holdButton(footer, if loan then "길게 눌러 할부 계약 서명" else "길게 눌러 서명하기", "primary", math.max(180, math.min(290, math.min(560, Ui.metrics().w - 24) - 150)), function()
			if busy then
				return
			end
			busy = true
			signBtn.setText("계약 처리 중…", "⏳")
			local res = ctx.Net.call("buy", { entry = e.id, color = colorId, loan = loan, nonce = nonce, trade = if tradeCar then tradeCar.id else nil })
			busy = false
			if res.ok then
				Contract.close()
				ctx.Net.refresh()
				ctx.Ceremony.play(res, e, colorId)
				return
			end
			-- a failed contract after a completed trade-in: the next try is a new contract
			if res.sold then
				nonce = ctx.Net.nonce()
				tradeId = nil
				tradeOn = false
				ctx.Net.refresh()
				cars = ctx.Net.ownedCars()
				snap = ctx.Net.state.snap or snap
				full = (snap.owned or 0) >= (snap.max or 3)
			elseif res.code ~= "rate" and res.code ~= "busy" and res.code ~= "net" then
				nonce = ctx.Net.nonce()
			end
			render()
			if errLbl then
				errLbl.Text = "✖ " .. tostring(res.message or "계약하지 못했어요")
			end
			Ui.sfx("error")
		end)
		signBtn.setEnabled(canSign)
		if not canSign then
			signBtn.setText(if needTrade then "보상판매할 차를 골라 주세요" else "잔액이 부족해요", "✖")
		end
		Ui.select(signBtn.inst)
	end

	show("🧾 계약서 · 견적 확인")
	render()
end

-------------------------------------------------------------------------------------------------
-- sell (yields until done / closed)
-------------------------------------------------------------------------------------------------
function Contract.sell(car: any): any
	local result: any = nil
	local done = false
	show("💸 내 차 팔기 · 매각 확인")
	orderN = 0
	local remaining = if type(car.loan) == "table" then (car.loan.remaining or 0) else 0
	local payout = (car.sell or 0) - remaining
	line("차량", string.format("%s · %s", car.label or "내 차", car.plate or ""), { rightSize = 15 })
	line("구입가", U.won(car.bought or 0))
	line("매입가 (구입가의 60%)", U.won(car.sell or 0))
	if remaining > 0 then
		line("남은 할부 정산", "-" .. U.won(remaining), { rightColor = Col.orange })
	end
	rule()
	line("통장 입금", if payout >= 0 then "+" .. U.won(payout) else "매각 불가", { rightColor = if payout >= 0 then Col.green else Col.red, rightSize = 17 })
	para("매각한 차는 되돌릴 수 없어요. 새 차로 바꾸실 거면 계약서에서 '보상판매'를 쓰면 추가 정산금도 받아요.")
	local errL = para("", Col.red, 13)
	local cancel = Ui.button(footer, { text = "취소", style = "ghost", size = UDim2.fromOffset(90, 48), order = 1, z = 4 })
	cancel.onClick(function()
		Contract.close()
	end)
	local busyS = false
	local b: any
	b = holdButton(footer, "길게 눌러 매각하기", "danger", 240, function()
		if busyS then
			return
		end
		busyS = true
		b.setText("처리 중…", "⏳")
		local res = ctx.Net.call("sell", { id = car.id })
		busyS = false
		if res.ok then
			result = res
			Ui.sfx("money")
			Contract.close()
		else
			errL.Text = "✖ " .. tostring(res.message or "팔지 못했어요")
			b.setText("길게 눌러 매각하기")
			b.reset()
		end
	end)
	b.setEnabled(payout >= 0)
	Ui.select(b.inst)
	closeCb = function()
		done = true
	end
	while not done do
		task.wait()
	end
	return result
end

-------------------------------------------------------------------------------------------------
-- rent / notice / compare
-------------------------------------------------------------------------------------------------
function Contract.rent(e: any)
	show("🔑 하루 렌트")
	orderN = 0
	local bank, cash = ctx.Net.money()
	line("차량", e.name, { rightSize = 15 })
	line("기간", string.format("게임 시간 하루 (%d분)", math.floor((e.rentSeconds or 2400) / 60)))
	line("렌트비", U.won(e.price), { rightColor = Col.accent, rightSize = 16 })
	line("결제 전 잔액", string.format("통장 %s · 현금 %s", U.won(bank), U.won(cash)), { size = 13 })
	para("렌트한 차는 차고 대수에 안 들어가요. 정비소 앞에 바로 가져다 드려요 (허 번호판).")
	local errL = para("", Col.red, 13)
	local cancel = Ui.button(footer, { text = "취소", style = "ghost", size = UDim2.fromOffset(90, 48), order = 1, z = 4 })
	cancel.onClick(function()
		Contract.close()
	end)
	local ok = Ui.button(footer, { text = "렌트하기 · " .. U.man(e.price), icon = "🔑", style = "primary", size = UDim2.fromOffset(220, 48), order = 2, z = 4 })
	local busyR = false
	ok.onClick(function()
		if busyR then
			return
		end
		busyR = true
		ok.setText("처리 중…", "⏳")
		local res = ctx.Net.call("rent", nil)
		busyR = false
		if res.ok then
			Ui.sfx("money")
			Contract.close()
			ctx.CatalogUI.close()
			ctx.Net.refresh()
			Ui.toast({ kind = "success", icon = "🔑", title = "렌트 완료!", body = "정비소 앞 출고 라인에 차를 가져다 놨어요 · 즐거운 드라이브 되세요" })
		else
			errL.Text = "✖ " .. tostring(res.message or "렌트하지 못했어요")
			ok.setText("렌트하기 · " .. U.man(e.price), "🔑")
		end
	end)
	Ui.select(ok.inst)
end

function Contract.notice(title: string, text: string, okText: string?, onOk: (() -> ())?)
	show(title)
	orderN = 0
	para(text, Col.ink, 14)
	local cancel = Ui.button(footer, { text = if okText then "닫기" else "확인", style = if okText then "ghost" else "primary", size = UDim2.fromOffset(100, 48), order = 1, z = 4 })
	cancel.onClick(function()
		Contract.close()
	end)
	if okText and onOk then
		local ok = Ui.button(footer, { text = okText, style = "primary", size = UDim2.fromOffset(160, 48), order = 2, z = 4 })
		ok.onClick(function()
			Contract.close()
			onOk()
		end)
		Ui.select(ok.inst)
	else
		Ui.select(cancel.inst)
	end
end

function Contract.compare(idA: string, idB: string)
	local A = ctx.Net.state.byId[idA]
	local B = ctx.Net.state.byId[idB]
	if not A or not B then
		return
	end
	show("⇄ 차량 비교")
	orderN = 0
	local head = Ui.frame(body, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = nextOrder(), ZIndex = 3 })
	Ui.label(head, { Text = A.name .. "\n" .. Cat.gradeLabel(A), Font = Ui.F.bold, TextSize = 13, Size = UDim2.new(0.36, 0, 1, 0), Position = UDim2.fromScale(0.28, 0), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, ZIndex = 3 })
	Ui.label(head, { Text = B.name .. "\n" .. Cat.gradeLabel(B), Font = Ui.F.bold, TextSize = 13, Size = UDim2.new(0.36, 0, 1, 0), Position = UDim2.fromScale(0.64, 0), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, ZIndex = 3 })
	local function cmp(label: string, a: any, b: any, va: number?, vb: number?, higherBetter: boolean?)
		local r = Ui.frame(body, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = nextOrder(), ZIndex = 3 })
		Ui.label(r, { Text = label, Font = Ui.F.med, TextSize = 12, TextColor3 = Col.sub, Size = UDim2.new(0.28, 0, 1, 0), ZIndex = 3 })
		local winA = va and vb and va ~= vb and ((higherBetter and va > vb) or (not higherBetter and va < vb))
		local winB = va and vb and va ~= vb and not winA
		Ui.label(r, { Text = tostring(a), Font = Ui.F.bold, TextSize = 13, TextColor3 = if winA then Col.green else Col.ink, Size = UDim2.new(0.36, 0, 1, 0), Position = UDim2.fromScale(0.28, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		Ui.label(r, { Text = tostring(b), Font = Ui.F.bold, TextSize = 13, TextColor3 = if winB then Col.green else Col.ink, Size = UDim2.new(0.36, 0, 1, 0), Position = UDim2.fromScale(0.64, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	end
	cmp("가격", U.man(A.price), U.man(B.price), A.price, B.price, false)
	cmp("최고 속도", A.perf.top .. " km/h", B.perf.top .. " km/h", A.perf.top, B.perf.top, true)
	cmp("가속", string.rep("●", A.bars.accel), string.rep("●", B.bars.accel), A.bars.accel, B.bars.accel, true)
	cmp("제동", string.rep("●", A.bars.brake), string.rep("●", B.bars.brake), A.bars.brake, B.bars.brake, true)
	cmp("승차감", string.rep("●", A.bars.comfort), string.rep("●", B.bars.comfort), A.bars.comfort, B.bars.comfort, true)
	cmp("구동", Cat.DRIVE_KO[A.perf.drive] or A.perf.drive, Cat.DRIVE_KO[B.perf.drive] or B.perf.drive)
	cmp("정원", A.seats .. "인승", B.seats .. "인승", A.seats, B.seats, true)
	cmp("연비", A.eff or "-", B.eff or "-")
	cmp("할부 계약금", if A.loan then U.man(A.loan.down) else "일시불만", if B.loan then U.man(B.loan.down) else "일시불만", A.loan and A.loan.down, B.loan and B.loan.down, false)
	cmp("하루 납입", if A.loan then U.man(A.loan.daily) else "-", if B.loan then U.man(B.loan.daily) else "-", A.loan and A.loan.daily, B.loan and B.loan.daily, false)
	local bA = Ui.button(footer, { text = A.short .. " 보기", style = "secondary", size = UDim2.fromOffset(170, 48), order = 1, z = 4, textSize = 13 })
	local bB = Ui.button(footer, { text = B.short .. " 보기", style = "primary", size = UDim2.fromOffset(170, 48), order = 2, z = 4, textSize = 13 })
	bA.onClick(function()
		Contract.close()
		ctx.CatalogUI.openDetail(A.id)
	end)
	bB.onClick(function()
		Contract.close()
		ctx.CatalogUI.openDetail(B.id)
	end)
	Ui.select(bB.inst)
end

function Contract.init(c: any)
	ctx = c
	Ui = c.Ui
	C = c.C
	U = c.S.Util
	Cat = c.S.Catalog
	Col = Ui.C
	Ui.onLayout(function()
		if openFlag then
			layout()
		end
	end)
end

return Contract
