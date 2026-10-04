-- GwangalliFeatures/ATM (owner: money): the ATM / bank counter screen. Opened by the server when the
-- player uses an ATM prompt (BankEvent {kind = "atm", atm = info}) or with F.open("atm", {atmId}).
--   ATM:     카드 넣기 (card slides into the slot) -> 비밀번호 (game PIN: any 4 digits, never sent) ->
--            거래 선택 (예금 출금 / 예금 입금 / 잔액 조회 / 거래 종료) -> 금액 (quick notes or the keypad,
--            만원 단위 for cash out, 천원 단위 for notes in) -> 확인 (금액 · 수수료 · 합계 · 거래 후 잔액) ->
--            처리 중 (counting notes) -> 현금을 받아 주세요 / 지폐 투입 -> 명세표 출력? -> 카드를 받아 주세요
--   창구:    번호표 (딩동! 0xx번 고객님) -> 한주임 teller -> 출금 / 입금 / 잔액 (any amount, coins OK,
--            09:00-16:00 game time) -> 확인 도장 -> 완료
-- Fees, units, limits and distance are decided by the server (GwangalliGameplay/Bank.luau); the screen
-- only shows the server's numbers. Built with the GwangalliUI kit (+ FeatureKit).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local M = {}
M.flows = { "atm" }

local F: any
local K: any
local FK: any

local player = Players.LocalPlayer

local BRAND = {
	bnk = { color = Color3.fromRGB(214, 0, 28), title = "BNK부산은행 365 자동화코너", logo = "BNK" },
	counter = { color = Color3.fromRGB(214, 0, 28), title = "BNK부산은행 창구", logo = "BNK" },
	cvs = { color = Color3.fromRGB(0, 132, 201), title = "편의점 ATM", logo = "ATM" },
	other = { color = Color3.fromRGB(0, 82, 155), title = "타행 ATM", logo = "ATM" },
}

local ui: any = nil -- built lazily
local atm: any = nil -- server info
local s: any = { step = "card", direction = "withdraw", amount = 0, pin = 0, input = "", result = nil, busy = false, ticket = 0 }
local token = 0 -- bumps on close / reopen (stale delayed steps check it)

-------------------------------------------------------------------------------------------------
-- Build
-------------------------------------------------------------------------------------------------
-- ATM keypad look: light metal keys, yellow 정정, green 확인
function M._styleKeys(pad: any)
	for _, b in pad.buttons do
		b.BackgroundColor3 = Color3.fromRGB(190, 196, 206)
		b.BackgroundTransparency = 0
		b.TextColor3 = Color3.fromRGB(20, 24, 32)
		K.gradient(b, { Color3.fromRGB(236, 239, 244), Color3.fromRGB(168, 175, 188) }, 90)
		if b.Name == "Key_fix" then
			b.Text = "정정"
			b.BackgroundColor3 = Color3.fromRGB(255, 210, 60)
			local g = b:FindFirstChildOfClass("UIGradient")
			if g then
				g.Color = ColorSequence.new(Color3.fromRGB(255, 226, 110), Color3.fromRGB(230, 170, 30))
			end
			b.Font = K.Font.bold
		elseif b.Name == "Key_ok" then
			b.Text = "확인"
			local g = b:FindFirstChildOfClass("UIGradient")
			if g then
				g.Color = ColorSequence.new(Color3.fromRGB(110, 236, 150), Color3.fromRGB(30, 170, 90))
			end
			b.Font = K.Font.bold
		end
	end
end

local function build()
	local gui = F.gui
	local root = K.frame(gui, { Name = "ATM", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 50 })
	local dim = K.dim(root, "Dim", 50, nil)
	local machine = K.frame(root, { Name = "Machine", BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 51, ClipsDescendants = true })
	K.corner(machine, 22)
	K.gradient(machine, { Color3.fromRGB(58, 63, 74), Color3.fromRGB(30, 33, 41), Color3.fromRGB(20, 22, 28) }, 100)
	K.stroke(machine, Color3.new(1, 1, 1), 1.5, 0.8)
	K.shadow(machine, 22, 8, "strong")
	-- brand strip
	local strip = K.frame(machine, { Name = "Brand", Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 52 })
	local stripGrad = K.gradient(strip, { Color3.fromRGB(214, 0, 28), Color3.fromRGB(150, 0, 20) }, 0)
	local logo = K.text(strip, { Name = "Logo", Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(44, 24), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), Text = "BNK", TextColor3 = Color3.fromRGB(214, 0, 28), Font = K.Font.heavy, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 53 })
	K.corner(logo, 6)
	local brandTitle = K.text(strip, { Name = "Title", Position = UDim2.fromOffset(64, 0), Size = UDim2.new(1, -230, 1, 0), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextColor3 = Color3.new(1, 1, 1), ZIndex = 53, TextTruncate = Enum.TextTruncate.AtEnd })
	local feeChip = K.text(strip, { Name = "Fee", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -56, 0.5, 0), Size = UDim2.fromOffset(120, 24), BackgroundTransparency = 0.75, BackgroundColor3 = Color3.new(0, 0, 0), Text = "", Font = K.Font.bold, TextSize = K.Type.micro, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 53 })
	K.corner(feeChip, UDim.new(0.5, 0))
	local closeB = K.IconButton(strip, { name = "Close", icon = "✕", textSize = 14, zIndex = 54 })
	closeB.AnchorPoint = Vector2.new(1, 0.5)
	closeB.Position = UDim2.new(1, -4, 0.5, 0)
	closeB.Size = UDim2.fromOffset(44, 44)
	closeB.BackgroundTransparency = 1
	closeB.TextColor3 = Color3.new(1, 1, 1)

	-- screen (blue ATM display)
	local bezel = K.frame(machine, { Name = "Bezel", BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(8, 10, 14), ZIndex = 52 })
	K.corner(bezel, 14)
	local screen = K.frame(bezel, { Name = "Screen", Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 53, ClipsDescendants = true })
	K.corner(screen, 10)
	local screenGrad = K.gradient(screen, { Color3.fromRGB(26, 86, 196), Color3.fromRGB(14, 46, 120) }, 90)
	local glare = K.frame(screen, { Name = "Glare", Size = UDim2.fromScale(1, 0.45), BackgroundTransparency = 0.93, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 54 })
	K.gradient(glare, { Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, 90, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }))
	local status = K.text(screen, { Name = "Status", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -4), Size = UDim2.new(1, -20, 0, 14), Text = "", TextColor3 = Color3.fromRGB(190, 210, 255), TextSize = K.Type.micro, ZIndex = 56, TextTruncate = Enum.TextTruncate.AtEnd })
	local stage = K.frame(screen, { Name = "Stage", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 1, -18), ZIndex = 55 })

	-- controls (card slot, keypad, cash slot)
	local panel = K.frame(machine, { Name = "Controls", ZIndex = 52 })
	local slot = K.frame(panel, { Name = "CardSlot", Size = UDim2.new(1, -20, 0, 14), Position = UDim2.fromOffset(10, 8), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(6, 7, 9), ZIndex = 53 })
	K.corner(slot, UDim.new(0.5, 0))
	local slotLed = K.stroke(slot, Color3.fromRGB(80, 255, 140), 2, 0.3)
	local slotLbl = K.text(panel, { Name = "SlotLabel", Position = UDim2.fromOffset(10, 23), Size = UDim2.new(1, -20, 0, 12), Text = "카드 / 명세표", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 53 })
	local card = K.frame(panel, { Name = "Card", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(62, 38), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 56, Visible = false, ClipsDescendants = true })
	K.corner(card, 5)
	K.gradient(card, { Color3.fromRGB(96, 84, 250), Color3.fromRGB(24, 28, 80) }, 35)
	local chipF = K.frame(card, { Name = "Chip", Position = UDim2.fromOffset(6, 12), Size = UDim2.fromOffset(12, 9), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 57 })
	K.corner(chipF, 2)
	K.gradient(chipF, K.Grad.gold, 30)
	K.text(card, { Name = "Bank", Position = UDim2.fromOffset(6, 2), Size = UDim2.new(1, -8, 0, 10), Text = "BNK", TextColor3 = Color3.new(1, 1, 1), Font = K.Font.heavy, TextSize = 11, ZIndex = 57 })
	local keysHost = K.frame(panel, { Name = "Keys", ZIndex = 53 })
	local cashSlot = K.frame(panel, { Name = "CashSlot", BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(6, 7, 9), ZIndex = 53 })
	K.corner(cashSlot, 6)
	local cashLed = K.stroke(cashSlot, Color3.fromRGB(255, 196, 70), 2, 0.9)
	local cashLbl = K.text(panel, { Name = "CashLabel", Size = UDim2.new(1, -20, 0, 12), Text = "지폐 입출금구", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 53 })
	local bills = K.frame(panel, { Name = "Bills", ZIndex = 57, ClipsDescendants = false })

	ui = {
		root = root,
		dim = dim,
		machine = machine,
		strip = strip,
		stripGrad = stripGrad,
		logo = logo,
		brandTitle = brandTitle,
		feeChip = feeChip,
		closeB = closeB,
		bezel = bezel,
		screen = screen,
		screenGrad = screenGrad,
		status = status,
		stage = stage,
		panel = panel,
		slot = slot,
		slotLed = slotLed,
		slotLbl = slotLbl,
		card = card,
		keysHost = keysHost,
		cashSlot = cashSlot,
		cashLed = cashLed,
		cashLbl = cashLbl,
		bills = bills,
		keypad = nil,
		wide = false,
	}

	-- ATM keypad: 1-9, 정정 / 0 / 확인 (+ the screen's own buttons)
	ui.keypad = FK.keypad(keysHost, {
		keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "fix", "0", "ok" },
		onKey = function(k: string)
			M._key(k)
		end,
	})
	M._styleKeys(ui.keypad)
	closeB.Activated:Connect(function()
		M._cancel()
	end)
	F.Layout.onChanged(function()
		if root.Visible then
			M._layout()
		end
	end)
end

local function isCounterNow(): boolean
	return atm ~= nil and atm.counter == true
end

function M._layout()
	local m = F.Layout.metrics()
	local sw, sh = m.W or 800, m.H or 400
	local wide = sw >= 560 and sh < 560
	ui.wide = wide
	local W, H
	if wide then
		W = math.min(sw - 16, 700)
		H = sh - 20
		ui.machine.AnchorPoint = Vector2.new(0.5, 0)
		ui.machine.Position = UDim2.new(0.5, 0, 0, 4)
	else
		W = math.min(sw - 16, 400)
		H = math.min(sh - 28, 720)
		ui.machine.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.machine.Position = UDim2.fromScale(0.5, 0.5)
	end
	ui.machine.Size = UDim2.fromOffset(W, H)
	local top = 40
	local pad = 10
	local cw, ch
	if wide then
		cw = math.clamp(math.floor(W * 0.3), 170, 210)
		ui.bezel.Position = UDim2.fromOffset(pad, top + pad)
		ui.bezel.Size = UDim2.fromOffset(W - cw - pad * 3, H - top - pad * 2)
		ui.panel.Position = UDim2.fromOffset(W - cw - pad, top + pad)
		ui.panel.Size = UDim2.fromOffset(cw, H - top - pad * 2)
		ch = H - top - pad * 2
	else
		ch = math.min(300, math.floor((H - top) * 0.46))
		cw = W - pad * 2
		ui.bezel.Position = UDim2.fromOffset(pad, top + pad)
		ui.bezel.Size = UDim2.fromOffset(W - pad * 2, H - top - ch - pad * 3)
		ui.panel.Position = UDim2.fromOffset(pad, H - ch - pad)
		ui.panel.Size = UDim2.fromOffset(cw, ch)
	end
	-- controls: card slot (top), keypad, cash slot (bottom)
	local keysTop = 46
	local cashH = 26
	local keysH = ch - keysTop - cashH - 26
	local keysW = math.min(cw - 16, 3 * 64 + 12)
	ui.keysHost.Position = UDim2.fromOffset(math.floor((cw - keysW) / 2), keysTop)
	ui.keysHost.Size = UDim2.fromOffset(keysW, keysH)
	ui.keypad.layout(keysW, keysH)
	ui.cashSlot.Position = UDim2.fromOffset(16, ch - cashH - 14)
	ui.cashSlot.Size = UDim2.fromOffset(cw - 32, 12)
	ui.cashLbl.Position = UDim2.fromOffset(10, ch - 14)
	ui.bills.Position = UDim2.fromOffset(16, ch - cashH - 8)
	ui.bills.Size = UDim2.fromOffset(cw - 32, 10)
	ui.card.Position = UDim2.new(0.5, 0, 0, 40)
	if isCounterNow() then
		-- the counter has no machine controls: the screen takes the whole body
		ui.bezel.Position = UDim2.fromOffset(pad, top + pad)
		ui.bezel.Size = UDim2.fromOffset(W - pad * 2, H - top - pad * 2)
	end
	if M._relayoutStage then
		M._relayoutStage()
	end
end

-------------------------------------------------------------------------------------------------
-- Screen helpers
-------------------------------------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)
local SOFT = Color3.fromRGB(200, 218, 255)

local function clearStage()
	FK.clear(ui.stage)
	M._relayoutStage = nil
end

local function stageText(props: { [string]: any }): TextLabel
	local p = table.clone(props)
	p.TextColor3 = p.TextColor3 or WHITE
	p.ZIndex = 56
	p.TextXAlignment = p.TextXAlignment or Enum.TextXAlignment.Center
	return K.text(ui.stage, p)
end

-- A big ATM touch button on the screen.
local function screenButton(parent: Instance, text: string, sub: string?, onClick: () -> (), style: string?): TextButton
	local b = K.make("TextButton", { Name = "Btn_" .. text, BackgroundColor3 = WHITE, BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 57 }, parent)
	K.corner(b, 10)
	local c1, c2 = Color3.fromRGB(250, 252, 255), Color3.fromRGB(206, 218, 240)
	if style == "primary" then
		c1, c2 = Color3.fromRGB(255, 226, 110), Color3.fromRGB(240, 180, 40)
	elseif style == "muted" then
		c1, c2 = Color3.fromRGB(120, 150, 210), Color3.fromRGB(80, 108, 170)
	end
	K.gradient(b, { c1, c2 }, 90)
	K.stroke(b, Color3.fromRGB(10, 30, 80), 1, 0.6)
	K.text(b, { Name = "Label", Position = UDim2.fromOffset(8, if sub then 4 else 0), Size = UDim2.new(1, -16, if sub then 0.6 else 1, if sub then -4 else 0), Text = text, TextColor3 = if style == "muted" then WHITE else Color3.fromRGB(14, 30, 70), Font = K.Font.bold, TextSize = K.Type.bodySm, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 58, TextTruncate = Enum.TextTruncate.AtEnd })
	if sub then
		K.text(b, { Name = "Sub", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -4), Size = UDim2.new(1, -16, 0.4, 0), Text = sub, TextColor3 = if style == "muted" then SOFT else Color3.fromRGB(60, 80, 120), TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 58, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	K.pressable(b, { scale = 0.95, sound = "tap" })
	b.Activated:Connect(function()
		if not s.busy then
			onClick()
		end
	end)
	return b
end

-- Lays out buttons in a grid inside `area` (Frame) with `cols` columns.
local function grid(area: Frame, buttons: { GuiObject }, cols: number, rowH: number?)
	local function place()
		local w = area.AbsoluteSize.X
		local h = area.AbsoluteSize.Y
		if w <= 0 then
			w = ui.stage.AbsoluteSize.X - 24
		end
		local rows = math.ceil(#buttons / cols)
		local gap = 8
		local bh = rowH or math.max(44, math.min(64, math.floor((h - gap * (rows - 1)) / math.max(1, rows))))
		local bw = math.floor((w - gap * (cols - 1)) / cols)
		for i, b in buttons do
			local c = (i - 1) % cols
			local r = (i - 1) // cols
			b.Position = UDim2.fromOffset(c * (bw + gap), r * (bh + gap))
			b.Size = UDim2.fromOffset(bw, bh)
		end
	end
	place()
	M._relayoutStage = place
	area:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
end

local function setLeds(cardOn: boolean, cashOn: boolean)
	K.breathe(ui.slotLed, cardOn, 0.05, 0.8)
	if not cardOn then
		ui.slotLed.Transparency = 0.85
	end
	K.breathe(ui.cashLed, cashOn, 0.05, 0.8)
	if not cashOn then
		ui.cashLed.Transparency = 0.9
	end
end

local function kindOf(): any
	return BRAND[atm and atm.kind or "other"] or BRAND.other
end

local function isCounter(): boolean
	return atm ~= nil and atm.counter == true
end

local function after(t: number, fn: () -> ())
	local mine = token
	task.delay(t, function()
		if mine == token and ui.root.Visible then
			fn()
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Steps
-------------------------------------------------------------------------------------------------
local show: { [string]: (any?) -> () } = {}

local function go(step: string, arg: any?)
	s.step = step
	clearStage()
	local fn = show[step]
	if fn then
		local ok, err = pcall(fn, arg)
		if not ok then
			warn("[GwangalliFeatures] atm step " .. step .. ": " .. tostring(err))
		end
	end
	-- screen content fade-in
	local veil = K.frame(ui.stage, { Name = "Veil", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(14, 46, 120), ZIndex = 60 })
	K.tween(veil, 0.2, { BackgroundTransparency = 1 })
	task.delay(0.22, function()
		veil:Destroy()
	end)
end
M._go = go

local function title(text: string, y: number?, size: number?)
	return stageText({ Name = "Title", Position = UDim2.new(0, 12, 0, y or 14), Size = UDim2.new(1, -24, 0, 26), Text = text, Font = K.Font.bold, TextSize = size or K.Type.title2, TextWrapped = true })
end

local function subtitle(text: string, y: number?)
	return stageText({ Name = "Sub", Position = UDim2.new(0, 12, 0, y or 42), Size = UDim2.new(1, -24, 0, 18), Text = text, TextColor3 = SOFT, TextSize = K.Type.caption, TextWrapped = true })
end

show.card = function()
	if isCounter() then
		go("ticket")
		return
	end
	title("카드를 넣어 주세요", 22)
	subtitle("체크카드 · 신용카드 · 통장 모두 가능해요", 52)
	local hint = stageText({ Name = "Hint", Position = UDim2.new(0, 12, 0.5, 10), Size = UDim2.new(1, -24, 0, 18), Text = "👉 오른쪽 카드 투입구", TextColor3 = Color3.fromRGB(255, 226, 110), TextSize = K.Type.caption, Font = K.Font.bold })
	local _ = hint
	setLeds(true, false)
	-- the card slides up into the slot
	-- the card's tail sticks out under the slot, then slides in (drawn between the slot and the keys)
	local c = ui.card
	c.Visible = true
	c.Size = UDim2.fromOffset(62, 20)
	c.Position = UDim2.new(0.5, 0, 0, 22)
	c.BackgroundTransparency = 0
	after(0.35, function()
		K.tween(c, 0.2, { Position = UDim2.new(0.5, 0, 0, 18) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		after(0.3, function()
			K.tween(c, 0.22, { Size = UDim2.fromOffset(62, 0), Position = UDim2.new(0.5, 0, 0, 14) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			K.sound("toggle")
			after(0.24, function()
				c.Visible = false
				go("reading")
			end)
		end)
	end)
end

show.reading = function()
	title("카드를 읽고 있어요", 30)
	subtitle("잠시만 기다려 주세요…", 60)
	local bar = K.ProgressBar(ui.stage, { height = 8, color = Color3.fromRGB(255, 226, 110) })
	bar.frame.Position = UDim2.new(0.15, 0, 0, 96)
	bar.frame.Size = UDim2.new(0.7, 0, 0, 8)
	FK.raise(bar.frame, 57)
	bar.set(1)
	setLeds(false, false)
	after(0.7, function()
		go("pin")
	end)
end

show.pin = function()
	s.pin = 0
	title("비밀번호 4자리를 눌러 주세요", 14)
	local dots = K.frame(ui.stage, { Name = "Dots", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 58), Size = UDim2.fromOffset(4 * 30 + 3 * 12, 30), ZIndex = 56 })
	for i = 1, 4 do
		local d = K.frame(dots, { Name = "Dot" .. i, Position = UDim2.fromOffset((i - 1) * 42, 0), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 0.7, BackgroundColor3 = WHITE, ZIndex = 57 })
		K.corner(d, UDim.new(0.5, 0))
		K.stroke(d, WHITE, 1.5, 0.3)
	end
	M._dots = dots
	stageText({ Name = "Tip", Position = UDim2.new(0, 12, 0, 100), Size = UDim2.new(1, -24, 0, 34), Text = "🔒 게임 속 비밀번호예요 · 아무 숫자 4개를 누르세요\n(실제 카드 비밀번호는 절대 입력하지 마세요)", TextColor3 = SOFT, TextSize = K.Type.micro, TextWrapped = true })
	local area = K.frame(ui.stage, { Name = "Quick", Position = UDim2.new(0, 12, 1, -54), Size = UDim2.new(1, -24, 0, 44), ZIndex = 56 })
	grid(area, { screenButton(area, "취소", nil, function()
		M._cancel()
	end, "muted") }, 1, 44)
	setLeds(false, false)
end

local function pinKey()
	if s.step ~= "pin" or s.pin >= 4 then
		return
	end
	s.pin += 1
	local dots = M._dots
	local d = dots and dots:FindFirstChild("Dot" .. s.pin)
	if d then
		d.BackgroundTransparency = 0
		K.pop(d, 0.6)
	end
	if s.pin >= 4 then
		s.busy = true
		after(0.35, function()
			s.busy = false
			go("menu")
		end)
	end
end

show.ticket = function()
	s.ticket = math.random(12, 48)
	title("번호표를 뽑아 주세요", 16)
	subtitle("BNK부산은행 광안동지점 · 영업시간 오전 9시~오후 4시", 46)
	local area = K.frame(ui.stage, { Name = "Quick", Position = UDim2.new(0.15, 0, 0, 84), Size = UDim2.new(0.7, 0, 0, 56), ZIndex = 56 })
	grid(area, { screenButton(area, "🎫 번호표 뽑기", "예금 · 출금 · 잔액", function()
		go("called")
	end, "primary") }, 1, 56)
	if atm and atm.open == false then
		stageText({ Name = "Closed", Position = UDim2.new(0, 12, 0, 150), Size = UDim2.new(1, -24, 0, 36), Text = "지금은 영업시간이 아니에요 🌙\n365 자동화코너 ATM을 이용해 주세요", TextColor3 = Color3.fromRGB(255, 190, 120), TextSize = K.Type.caption, TextWrapped = true })
		area.Visible = false
	end
end

show.called = function()
	title(string.format("🔔 딩동! %03d번 고객님", s.ticket), 22, K.Type.title)
	subtitle("2번 창구로 와 주세요", 56)
	K.feedback("notify")
	after(1.1, function()
		go("menu")
	end)
end

show.menu = function()
	s.direction = "withdraw"
	s.amount = 0
	s.input = ""
	setLeds(false, false)
	if isCounter() then
		local av = K.avatar(ui.stage, 40, "🏦", Color3.fromRGB(214, 30, 60))
		av.Position = UDim2.fromOffset(12, 10)
		FK.raise(av, 57)
		stageText({ Name = "Teller", Position = UDim2.fromOffset(60, 10), Size = UDim2.new(1, -72, 0, 20), Text = "한주임 · BNK부산은행", TextColor3 = SOFT, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Left })
		stageText({ Name = "Title", Position = UDim2.fromOffset(60, 28), Size = UDim2.new(1, -72, 0, 22), Text = "어서 오세요! 무엇을 도와드릴까요?", Font = K.Font.bold, TextSize = K.Type.body, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	else
		title("원하시는 거래를 선택하세요", 12)
	end
	local area = K.frame(ui.stage, { Name = "Menu", Position = UDim2.new(0, 12, 0, 62), Size = UDim2.new(1, -24, 1, -70), ZIndex = 56 })
	local fee = atm and atm.fee or 0
	local feeText = if fee > 0 then "수수료 " .. K.won(fee) else "수수료 없음"
	grid(area, {
		screenButton(area, "💵 예금 출금", feeText, function()
			s.direction = "withdraw"
			go("amount")
		end, "primary"),
		screenButton(area, "🏦 예금 입금", if isCounter() then "동전도 가능" else feeText, function()
			s.direction = "deposit"
			go("amount")
		end),
		screenButton(area, "🔍 잔액 조회", "통장 · 현금", function()
			go("balance")
		end),
		screenButton(area, "↩ 거래 종료", if isCounter() then nil else "카드 반환", function()
			go("eject")
		end, "muted"),
	}, 2)
	-- refresh the server numbers (fee may change with the clock)
	task.spawn(function()
		if not atm then
			return
		end
		local r = FK.call("atmOpen", { atmId = atm.id })
		if r.ok and r.atm then
			atm = r.atm
			M._brand()
		end
	end)
end

show.balance = function()
	title("잔액 조회", 12)
	local cardF = K.frame(ui.stage, { Name = "Balance", Position = UDim2.new(0, 16, 0, 48), Size = UDim2.new(1, -32, 0, 96), BackgroundTransparency = 0.82, BackgroundColor3 = WHITE, ZIndex = 56 })
	K.corner(cardF, 12)
	K.text(cardF, { Name = "L1", Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 16), Text = "통장 잔액 · " .. (atm and atm.account or ""), TextColor3 = SOFT, TextSize = K.Type.caption, ZIndex = 57 })
	local v = K.text(cardF, { Name = "V", Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -24, 0, 32), Text = "0원", Font = K.Font.bold, TextSize = 26, TextColor3 = WHITE, ZIndex = 57 })
	K.mono(v)
	K.countUp(v, atm and atm.bank or 0, { format = K.commas, suffix = "원", duration = 0.7 })
	K.text(cardF, { Name = "L2", Position = UDim2.fromOffset(12, 64), Size = UDim2.new(1, -24, 0, 16), Text = string.format("현금 %s · 오늘 ATM 출금 가능 %s", K.won(atm and atm.cash or 0), K.won(atm and atm.atmLeft or 0)), TextColor3 = SOFT, TextSize = K.Type.micro, ZIndex = 57, TextTruncate = Enum.TextTruncate.AtEnd })
	local area = K.frame(ui.stage, { Name = "Btns", Position = UDim2.new(0, 12, 1, -54), Size = UDim2.new(1, -24, 0, 44), ZIndex = 56 })
	grid(area, { screenButton(area, "처음으로", nil, function()
		go("menu")
	end, "muted"), screenButton(area, "거래 종료", nil, function()
		go("eject")
	end) }, 2, 44)
end

local function unit(): number
	if not atm then
		return 10000
	end
	return if s.direction == "withdraw" then atm.withdrawUnit else atm.depositUnit
end

local function amountLimits(): (number, number)
	if not atm then
		return 10000, 700000
	end
	local maxV = if s.direction == "withdraw" then atm.maxWithdraw else atm.maxDeposit
	local minV = if s.direction == "withdraw" then atm.min else (atm.depositUnit or 1000)
	return minV, maxV
end

local amountLabel: TextLabel? = nil
local amountHint: TextLabel? = nil
local function refreshAmount()
	if amountLabel then
		amountLabel.Text = if s.amount > 0 then K.commas(s.amount) .. "원" else "0원"
	end
	if amountHint then
		local u = unit()
		local minV, maxV = amountLimits()
		local have = if s.direction == "withdraw" then (atm and atm.bank or 0) else (atm and atm.cash or 0)
		local txt = string.format("%s · 최소 %s · 최대 %s", if u >= 10000 then "만원 단위" elseif u >= 1000 then "천원 단위 (동전 불가)" else "1원 단위", K.wonShort(minV), K.wonShort(maxV))
		local col = SOFT
		if s.amount > 0 and s.amount % u ~= 0 then
			txt = if u >= 10000 then "만원 단위로만 출금돼요" else "천원 단위 지폐만 넣을 수 있어요"
			col = Color3.fromRGB(255, 170, 150)
		elseif s.amount > maxV then
			txt = "한 번에 최대 " .. K.won(maxV) .. "까지예요"
			col = Color3.fromRGB(255, 170, 150)
		elseif s.amount > have then
			txt = if s.direction == "withdraw" then "통장 잔액이 부족해요 (" .. K.won(have) .. ")" else "가진 현금이 부족해요 (" .. K.won(have) .. ")"
			col = Color3.fromRGB(255, 170, 150)
		end
		amountHint.Text = txt
		amountHint.TextColor3 = col
	end
end

show.amount = function()
	local wd = s.direction == "withdraw"
	title(if wd then "출금하실 금액을 선택하세요" else "넣으실 금액을 선택하세요", 8, K.Type.body)
	local lbl = stageText({ Name = "Amount", Position = UDim2.new(0, 12, 0, 32), Size = UDim2.new(1, -24, 0, 30), Text = "0원", Font = K.Font.bold, TextSize = 26 })
	K.mono(lbl)
	amountLabel = lbl
	amountHint = stageText({ Name = "Hint", Position = UDim2.new(0, 12, 0, 62), Size = UDim2.new(1, -24, 0, 14), Text = "", TextColor3 = SOFT, TextSize = K.Type.micro })
	local area = K.frame(ui.stage, { Name = "Quick", Position = UDim2.new(0, 12, 0, 82), Size = UDim2.new(1, -24, 1, -90), ZIndex = 56 })
	local picks: { any }
	if isCounter() then
		picks = { 10000, 50000, 100000, 300000, 1000000 }
	elseif wd then
		picks = { 10000, 30000, 50000, 100000, 200000, 500000 }
	else
		local cash = atm and atm.cash or 0
		local all = cash - cash % 1000
		picks = { 10000, 30000, 50000, 100000, 200000, math.max(1000, all) }
	end
	local buttons = {}
	for i, v in picks do
		local isAll = (not wd) and i == #picks and not isCounter()
		table.insert(buttons, screenButton(area, if isAll then "전액 " .. K.wonShort(v) else K.wonShort(v), nil, function()
			s.amount = v
			refreshAmount()
			go("confirm")
		end))
	end
	table.insert(buttons, screenButton(area, "직접 입력 → 키패드", nil, function()
		s.input = ""
		s.amount = 0
		refreshAmount()
		K.pulse(ui.keysHost, false)
		for _, b in ui.keypad.buttons do
			K.pop(b, 0.9)
		end
	end, "muted"))
	table.insert(buttons, screenButton(area, "확인", nil, function()
		M._key("ok")
	end, "primary"))
	if isCounter() then
		-- the counter has no machine keypad: quick picks on the left, a keypad on the right
		table.remove(buttons, #buttons - 1):Destroy() -- "직접 입력 → 키패드"
		area.Size = UDim2.new(0.56, -18, 1, -90)
		lbl.Size = UDim2.new(0.56, -24, 0, 30)
		amountHint.Size = UDim2.new(0.56, -24, 0, 14)
		local padHost = K.frame(ui.stage, { Name = "CounterPad", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.new(0.44, -12, 1, -18), ZIndex = 56 })
		local pad = FK.keypad(padHost, { keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "fix", "0", "ok" }, onKey = function(k: string)
			M._key(k)
		end })
		M._styleKeys(pad)
		local function placePad()
			pad.layout(padHost.AbsoluteSize.X, padHost.AbsoluteSize.Y)
		end
		placePad()
		padHost:GetPropertyChangedSignal("AbsoluteSize"):Connect(placePad)
		grid(area, buttons, if ui.wide then 3 else 2)
	else
		grid(area, buttons, if ui.wide then 4 else 2)
	end
	s.input = ""
	s.amount = 0
	refreshAmount()
end

show.confirm = function()
	local wd = s.direction == "withdraw"
	local fee = atm and atm.fee or 0
	title(if wd then "출금 내용을 확인해 주세요" else "입금 내용을 확인해 주세요", 10, K.Type.body)
	local box = K.frame(ui.stage, { Name = "Details", Position = UDim2.new(0, 16, 0, 38), Size = UDim2.new(1, -32, 0, 4 * 24 + 12), BackgroundTransparency = 0.85, BackgroundColor3 = WHITE, ZIndex = 56 })
	K.corner(box, 10)
	K.pad(box, 12, 12, 6, 6)
	K.list(box, false, 0)
	local bank = atm and atm.bank or 0
	local rows = {
		{ "거래", if wd then "예금 출금" else "예금 입금" },
		{ "금액", K.won(s.amount) },
		{ "수수료", if fee > 0 then K.won(fee) .. (if atm and atm.night then " (야간)" else "") else "없음" },
		{ "거래 후 잔액", K.won(if wd then bank - s.amount - fee else bank + s.amount - fee) },
	}
	for i, r in rows do
		local f = K.frame(box, { Name = "R" .. i, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = i, ZIndex = 57 })
		K.text(f, { Name = "L", Size = UDim2.new(0.45, 0, 1, 0), Text = r[1], TextColor3 = SOFT, TextSize = K.Type.caption, ZIndex = 57 })
		local v = K.text(f, { Name = "V", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.55, 0, 1, 0), Text = r[2], TextColor3 = if i == 3 and fee > 0 then Color3.fromRGB(255, 210, 120) else WHITE, Font = K.Font.bold, TextSize = K.Type.caption + 1, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 57 })
		K.mono(v)
	end
	local area = K.frame(ui.stage, { Name = "Btns", Position = UDim2.new(0, 12, 1, -54), Size = UDim2.new(1, -24, 0, 44), ZIndex = 56 })
	grid(area, {
		screenButton(area, "취소", nil, function()
			go("menu")
		end, "muted"),
		screenButton(area, "확인", nil, function()
			if wd then
				go("work")
			else
				go(if isCounter() then "work" else "insert")
			end
		end, "primary"),
	}, 2, 44)
end

local function billFrame(parent: Instance, i: number, color: Color3?): Frame
	local b = K.frame(parent, { Name = "Bill" .. i, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(84, 40), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 58 })
	K.corner(b, 3)
	K.gradient(b, { color or Color3.fromRGB(150, 205, 150), K.shade(color or Color3.fromRGB(150, 205, 150), 0.05, -0.18) }, 0)
	K.stroke(b, Color3.fromRGB(40, 90, 50), 1, 0.5)
	K.text(b, { Name = "V", Size = UDim2.fromScale(1, 1), Text = "10000", TextColor3 = Color3.fromRGB(28, 70, 36), Font = K.Font.heavy, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 59 })
	return b
end

show.insert = function()
	title("투입구에 현금을 넣어 주세요", 20)
	subtitle(K.won(s.amount) .. " · 지폐를 가지런히 펴서 넣어 주세요", 50)
	setLeds(false, true)
	-- notes slide into the cash slot
	local host = ui.bills
	FK.clear(host)
	for i = 1, 3 do
		local b = billFrame(host, i)
		b.Position = UDim2.new(0.5, (i - 2) * 6, 0, -70 - i * 4)
		K.tweenD(b, 0.3, { Position = UDim2.new(0.5, 0, 0, -4), Size = UDim2.fromOffset(84, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.35 + i * 0.12)
	end
	after(1.05, function()
		FK.clear(host)
		go("work")
	end)
end

show.work = function()
	local wd = s.direction == "withdraw"
	title(if isCounter() then "처리하고 있어요" else "지폐를 세고 있어요", 30)
	subtitle("잠시만 기다려 주세요…", 60)
	local bar = K.ProgressBar(ui.stage, { height = 8, color = Color3.fromRGB(255, 226, 110) })
	bar.frame.Position = UDim2.new(0.15, 0, 0, 96)
	bar.frame.Size = UDim2.new(0.7, 0, 0, 8)
	FK.raise(bar.frame, 57)
	bar.set(0.85)
	setLeds(false, false)
	s.busy = true
	local mine = token
	task.spawn(function()
		-- 차르르: note counting ticks while the server works
		for _ = 1, 8 do
			if mine ~= token then
				break
			end
			K.sound("tap")
			task.wait(0.07)
		end
	end)
	task.spawn(function()
		local r = FK.call("atm", { atmId = atm.id, direction = s.direction, amount = s.amount, rid = FK.rid() }, 12)
		if mine ~= token then
			return
		end
		s.busy = false
		bar.set(1)
		if r.ok then
			s.result = r
			atm.cash = r.cash
			atm.bank = r.bank
			atm.atmLeft = r.atmLeft
			K.feedback("money")
			if wd and not isCounter() then
				go("take")
			elseif isCounter() then
				go("stamp")
			else
				go("receiptAsk")
			end
		else
			go("error", r.message)
		end
	end)
end

show.take = function()
	title("현금을 받아 주세요", 20)
	subtitle(K.won(s.amount) .. " · 지폐를 꼭 챙기세요", 50)
	setLeds(false, true)
	local host = ui.bills
	FK.clear(host)
	local n = math.clamp(math.floor(s.amount / 10000), 1, 4)
	local notes = {}
	for i = 1, n do
		local b = billFrame(host, i)
		b.Size = UDim2.fromOffset(84, 0)
		b.Position = UDim2.new(0.5, (i - (n + 1) / 2) * 5, 0, 0)
		K.tweenD(b, 0.3, { Size = UDim2.fromOffset(84, 40) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.1 + i * 0.08)
		table.insert(notes, b)
	end
	local area = K.frame(ui.stage, { Name = "Btns", Position = UDim2.new(0.2, 0, 1, -60), Size = UDim2.new(0.6, 0, 0, 48), ZIndex = 56 })
	grid(area, { screenButton(area, "💵 현금 받기", nil, function()
		for i, b in notes do
			K.tweenD(b, 0.25, { Position = b.Position + UDim2.fromOffset(0, 60), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, (i - 1) * 0.05)
		end
		K.feedback("money")
		after(0.4, function()
			FK.clear(host)
			go("receiptAsk")
		end)
	end, "primary") }, 1, 48)
end

show.stamp = function()
	title("처리됐어요", 18)
	subtitle(string.format("%s %s · 한주임이 도장을 찍었어요", if s.direction == "withdraw" then "출금" else "입금", K.won(s.amount)), 48)
	local stamp = stageText({ Name = "Stamp", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(96, 96), Text = "BNK\n확인", TextColor3 = Color3.fromRGB(255, 90, 95), Font = K.Font.heavy, TextSize = 20, TextWrapped = true })
	K.corner(stamp, UDim.new(0.5, 0))
	local st = K.stroke(stamp, Color3.fromRGB(255, 90, 95), 3, 0)
	local _ = st
	stamp.Rotation = -14
	local sc = K.scaleOf(stamp)
	sc.Scale = 2
	stamp.TextTransparency = 1
	K.tween(sc, 0.18, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	K.tween(stamp, 0.12, { TextTransparency = 0 })
	K.feedback("success")
	after(1.1, function()
		go("receiptAsk")
	end)
end

show.receiptAsk = function()
	title("명세표를 출력할까요?", 22)
	subtitle("종이를 아끼면 지구가 좋아해요 🌱", 52)
	local area = K.frame(ui.stage, { Name = "Btns", Position = UDim2.new(0, 12, 1, -54), Size = UDim2.new(1, -24, 0, 44), ZIndex = 56 })
	grid(area, { screenButton(area, "출력 안 함", nil, function()
		go("eject")
	end, "muted"), screenButton(area, "🧾 출력", nil, function()
		go("receipt")
	end, "primary") }, 2, 44)
end

show.receipt = function()
	local r = s.result or {}
	title("명세표가 나왔어요", 8, K.Type.body)
	local paper = K.frame(ui.stage, { Name = "Receipt", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 10), Size = UDim2.new(0, math.min(240, ui.stage.AbsoluteSize.X - 30), 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(250, 250, 244), ZIndex = 58, Rotation = -1.5 })
	K.corner(paper, 3)
	K.pad(paper, 12, 12, 10, 10)
	K.list(paper, false, 2)
	local now = FK.now()
	local lines = {
		{ "BNK부산은행 거래명세표", true },
		{ (atm and atm.name or "") },
		{ string.rep("-", 28) },
		{ "일시  " .. FK.dayTitle(now) .. " " .. FK.timeOfDay(now) },
		{ "거래  " .. (if s.direction == "withdraw" then "예금 출금" else "예금 입금") },
		{ "금액  " .. K.won(r.amount or s.amount) },
		{ "수수료  " .. K.won(r.fee or 0) },
		{ "거래 후 잔액  " .. K.won(r.bank or 0) },
		{ "거래번호  " .. string.upper(string.sub(tostring(r.ref or ""), 1, 10)) },
		{ string.rep("-", 28) },
		{ "이용해 주셔서 감사합니다" },
	}
	for i, l in lines do
		local t = K.text(paper, { Name = "L" .. i, Size = UDim2.new(1, 0, 0, if l[2] then 18 else 15), Text = l[1], TextColor3 = Color3.fromRGB(40, 40, 40), Font = if l[2] then K.Font.bold else K.Font.regular, TextSize = if l[2] then 13 else 11, LayoutOrder = i, ZIndex = 59, TextXAlignment = if l[2] then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left })
		if not l[2] then
			K.mono(t, Enum.FontWeight.Regular)
		end
	end
	K.tween(paper, 0.45, { Position = UDim2.new(0.5, 0, 0, 34) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	K.sound("open")
	local area = K.frame(ui.stage, { Name = "Btns", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -8), Size = UDim2.fromOffset(110, 44), ZIndex = 60 })
	grid(area, { screenButton(area, "받았어요", nil, function()
		go("eject")
	end, "primary") }, 1, 44)
end

show.eject = function()
	if isCounter() then
		title("감사합니다, 또 오세요!", 30)
		subtitle("BNK부산은행 광안동지점", 60)
		after(1.1, function()
			M.close()
		end)
		return
	end
	title("카드를 받아 주세요", 30)
	subtitle("카드를 꼭 챙기세요 💳", 60)
	setLeds(true, false)
	local c = ui.card
	c.Visible = true
	c.Size = UDim2.fromOffset(62, 0)
	c.Position = UDim2.new(0.5, 0, 0, 14)
	K.tween(c, 0.25, { Size = UDim2.fromOffset(62, 22), Position = UDim2.new(0.5, 0, 0, 20) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	K.sound("toggle")
	after(1.0, function()
		K.tween(c, 0.25, { Position = UDim2.new(0.5, 0, 0, 34), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		after(0.3, function()
			c.Visible = false
			M.close()
		end)
	end)
end

show.error = function(msg: any)
	title("거래를 완료하지 못했어요", 22)
	stageText({ Name = "Msg", Position = UDim2.new(0, 16, 0, 56), Size = UDim2.new(1, -32, 0, 40), Text = tostring(msg or ""), TextColor3 = Color3.fromRGB(255, 190, 170), TextSize = K.Type.caption, TextWrapped = true })
	K.feedback("error")
	local area = K.frame(ui.stage, { Name = "Btns", Position = UDim2.new(0, 12, 1, -54), Size = UDim2.new(1, -24, 0, 44), ZIndex = 56 })
	grid(area, { screenButton(area, "거래 종료", nil, function()
		go("eject")
	end, "muted"), screenButton(area, "처음으로", nil, function()
		go("menu")
	end, "primary") }, 2, 44)
end

-------------------------------------------------------------------------------------------------
-- Keypad
-------------------------------------------------------------------------------------------------
function M._key(k: string)
	if s.busy then
		return
	end
	if s.step == "pin" then
		if k ~= "fix" and k ~= "ok" and k ~= "clear" and k ~= "back" then
			pinKey()
		elseif k == "fix" and s.pin > 0 then
			go("pin")
		end
		return
	end
	if s.step == "amount" then
		if k == "fix" or k == "clear" or k == "back" then
			s.input = ""
			s.amount = 0
			refreshAmount()
		elseif k == "ok" then
			local minV, maxV = amountLimits()
			local u = unit()
			local have = if s.direction == "withdraw" then (atm and atm.bank or 0) else (atm and atm.cash or 0)
			if s.amount < minV or s.amount > maxV or s.amount % u ~= 0 or s.amount > have then
				if amountLabel then
					FK.shake(amountLabel, 6)
				end
				K.feedback("error")
				refreshAmount()
			else
				go("confirm")
			end
		else
			if #s.input >= 8 then
				return
			end
			s.input ..= k
			s.amount = tonumber(s.input) or 0
			refreshAmount()
			if amountLabel then
				K.pop(amountLabel, 0.95)
			end
		end
		return
	end
	if k == "ok" and s.step == "menu" then
		s.direction = "withdraw"
		go("amount")
	end
end

-------------------------------------------------------------------------------------------------
-- Open / close
-------------------------------------------------------------------------------------------------
function M._brand()
	local b = kindOf()
	ui.stripGrad.Color = ColorSequence.new(b.color, K.shade(b.color, 0.05, -0.2))
	ui.logo.Text = b.logo
	ui.logo.TextColor3 = b.color
	ui.brandTitle.Text = (atm and atm.name) or b.title
	local fee = atm and atm.fee or 0
	if isCounter() then
		ui.feeChip.Text = if atm and atm.open == false then "영업시간 외" else "창구 · 수수료 없음"
	elseif fee > 0 then
		ui.feeChip.Text = string.format("수수료 %s%s", K.won(fee), if atm.night then " · 야간" else "")
	else
		ui.feeChip.Text = "수수료 면제 · 자행"
	end
	ui.status.Text = string.format("%s님 · %s %s · 현금 %s", atm and atm.holder or player.DisplayName, "BNK", atm and atm.account or "", K.won(atm and atm.cash or 0))
	-- counters are warm wood / white, ATMs are blue screens
	if isCounter() then
		ui.screenGrad.Color = ColorSequence.new(Color3.fromRGB(34, 60, 110), Color3.fromRGB(18, 30, 64))
		ui.panel.Visible = false
	else
		ui.screenGrad.Color = ColorSequence.new(Color3.fromRGB(26, 86, 196), Color3.fromRGB(14, 46, 120))
		ui.panel.Visible = true
	end
end

function M.open(_flowId: string, args: any)
	if not ui then
		build()
	end
	local info = args.atm
	if type(info) ~= "table" and type(args.atmId) == "string" then
		local r = FK.call("atmOpen", { atmId = args.atmId })
		if not r.ok then
			K.toast({ kind = "warn", title = "ATM", body = r.message })
			return
		end
		info = r.atm
	end
	if type(info) ~= "table" or type(info.id) ~= "string" then
		return
	end
	token += 1
	atm = info
	s.busy = false
	s.result = nil
	ui.root.Visible = true
	F.modal(true, "atm")
	M._brand()
	M._layout()
	ui.dim.BackgroundTransparency = 1
	K.tween(ui.dim, 0.25, { BackgroundTransparency = 0.4 })
	K.springIn(ui.machine, 0.93)
	K.feedback("open")
	FK.clear(ui.bills)
	ui.card.Visible = false
	go("card")
end

function M._cancel()
	if s.busy then
		return
	end
	if s.step == "card" or s.step == "reading" or s.step == "ticket" or s.step == "called" or s.step == "eject" then
		M.close()
	else
		go("eject")
	end
end

function M.close()
	if not ui or not ui.root.Visible then
		return
	end
	token += 1
	s.busy = false
	F.modal(false, "atm")
	K.tween(ui.dim, 0.18, { BackgroundTransparency = 1 })
	local sc = K.scaleOf(ui.machine)
	K.tween(sc, 0.18, { Scale = 0.95 })
	K.sound("close")
	setLeds(false, false)
	local mine = token
	task.delay(0.19, function()
		if mine == token then
			ui.root.Visible = false
			sc.Scale = 1
		end
	end)
end

function M.isOpen(): boolean
	return ui ~= nil and ui.root.Visible
end

function M.init(ctx: any)
	F = ctx
	K = ctx.K
	FK = require(script.Parent:WaitForChild("FeatureKit"))
	FK.bind(ctx)
	task.spawn(function()
		local ev = F.remote("BankEvent", 60)
		if ev and ev:IsA("RemoteEvent") then
			ev.OnClientEvent:Connect(function(e: any)
				if type(e) == "table" and e.kind == "atm" and type(e.atm) == "table" then
					local ok, err = pcall(M.open, "atm", { atm = e.atm })
					if not ok then
						warn("[GwangalliFeatures] atm open: " .. tostring(err))
					end
				end
			end)
		end
	end)
	-- walking away (PC keeps the controls) or dying closes the machine
	task.spawn(function()
		while true do
			task.wait(1)
			if ui and ui.root.Visible and atm and not s.busy then
				local ch = player.Character
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if not (root and root:IsA("BasePart")) or (hum and hum.Health <= 0) then
					M.close()
				elseif typeof(atm.pos) == "Vector3" and (root.Position - atm.pos).Magnitude > (atm.reach or 14) + 6 then
					M.close()
					K.toast({ kind = "info", title = if isCounter() then "창구" else "ATM", body = "기기에서 멀어져서 거래를 끝냈어요" })
				end
			end
		end
	end)
	local _ = TweenService
end

return M
