-- GwangalliCarDealer/Ceremony (client): the 출고 (delivery) moment after a successful contract — blurred world,
-- the new car turning on a lit stage in its chosen paint, the Busan plate revealed letter by letter, a key
-- hand-over, confetti, the contract summary (결제 · 계좌 · 할부 · 환급 · 보상판매), the dealer's line and two
-- choices: 🚗 지금 타기 (the garage calls the car and seats the player) or 나중에 탈게요 (how to call it later).
-- The game's own first-car milestone banner waits while the HUD is hidden, so it plays right after this.
--   Ceremony.play(buyResult, entry, colorId)   Ceremony.isOpen()

local Players = game:GetService("Players")

local Ceremony = {}

local player = Players.LocalPlayer
local ctx: any
local Ui: any
local C: any
local U: any
local Col: any

local gui: ScreenGui
local openFlag = false
local stage: any = nil

function Ceremony.isOpen(): boolean
	return openFlag
end

local CONFETTI = { Color3.fromRGB(255, 92, 138), Color3.fromRGB(64, 132, 255), Color3.fromRGB(242, 190, 82), Color3.fromRGB(52, 199, 123), Color3.fromRGB(255, 255, 255) }

local function confetti(parent: Instance, n: number)
	if Ui.reduced() then
		return
	end
	local rng = Random.new()
	for i = 1, n do
		local s = rng:NextInteger(6, 12)
		local p = Ui.frame(parent, {
			Name = "Confetti",
			Size = UDim2.fromOffset(s, math.floor(s * 0.55)),
			Position = UDim2.new(rng:NextNumber(0.05, 0.95), 0, 0, -20),
			BackgroundTransparency = 0,
			BackgroundColor3 = CONFETTI[rng:NextInteger(1, #CONFETTI)],
			Rotation = rng:NextNumber(0, 360),
			ZIndex = 30,
		})
		local t = rng:NextNumber(1.8, 3.2)
		task.delay(rng:NextNumber(0, 0.6) + (i % 3) * 0.05, function()
			if not p.Parent then
				return
			end
			Ui.tween(p, t, { Position = UDim2.new(p.Position.X.Scale + rng:NextNumber(-0.12, 0.12), 0, 1.05, 0), Rotation = p.Rotation + rng:NextNumber(-540, 540) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(t, function()
				p:Destroy()
			end)
		end)
	end
end

local function close()
	if not openFlag then
		return
	end
	openFlag = false
	Ui.unbind("GwCarDealerCeremony")
	Ui.blur(false, "ceremony")
	Ui.controls("ceremony", true)
	Ui.deselect(gui)
	if stage then
		stage:destroy()
		stage = nil
	end
	Ui.show(gui, false)
	for _, ch in gui:GetChildren() do
		ch:Destroy()
	end
end

-- Plate reveal: letters flip in one by one.
local function plateReveal(lbl: TextLabel, text: string)
	local chars = {}
	for _, cp in utf8.codes(text) do
		table.insert(chars, utf8.char(cp))
	end
	if Ui.reduced() then
		lbl.Text = text
		return
	end
	local pool = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "가", "나", "다", "라", "마", "바", "사", "아", "자", "하" }
	local shown = ""
	for i, ch in chars do
		if ch == " " then
			shown ..= " "
		else
			for _ = 1, 3 do
				if not lbl.Parent then
					return
				end
				lbl.Text = shown .. pool[math.random(1, #pool)]
				task.wait(0.035)
			end
			shown ..= ch
		end
		lbl.Text = shown
		local _ = i
	end
	lbl.Text = text
end

function Ceremony.play(res: any, e: any, colorId: string)
	if not gui then
		gui = Ui.screen("GwangalliCarDealerCeremony", C.UI.order.ceremony)
	end
	if openFlag then
		close()
	end
	openFlag = true
	local m = Ui.metrics()
	local receipt = type(res.receipt) == "table" and res.receipt or {}
	local car = type(res.car) == "table" and res.car or {}
	local plate = receipt.plate or car.plate or "부산 00가 0000"
	local npc = ctx.CatalogUI.ctxNpc()
	Ui.show(gui, true)
	Ui.blur(true, "ceremony")
	Ui.controls("ceremony", false)
	Ui.sfx("money")

	local dim = Ui.frame(gui, { Name = "Dim", BackgroundTransparency = 0.25, BackgroundColor3 = Color3.fromRGB(4, 5, 9) })
	Ui.grad(dim, Color3.fromRGB(40, 50, 90), Color3.fromRGB(0, 0, 0), 90, 0.2, 0)
	local W = math.min(720, m.w - 24)
	local H = math.min(m.h - m.inset - 20, if m.compact then m.h - m.inset - 12 else 600)
	local card = Ui.glass(gui, { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, m.inset / 2), Size = UDim2.fromOffset(W, H), BackgroundColor3 = Col.bg2, ZIndex = 2 })
	Ui.stroke(card, Col.gold, 2, 0.35)
	local split = W >= 640 and H < 520
	local titleH = if m.compact then 56 else 72
	Ui.label(card, { Text = "🎉 출고를 축하드려요!", Font = Ui.F.black, TextSize = if m.compact then 20 else 26, TextColor3 = Col.gold, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	Ui.label(card, { Text = e.name .. " · " .. (receipt.label or ""), Font = Ui.F.bold, TextSize = if m.compact then 13 else 15, TextColor3 = Col.sub, Position = UDim2.fromOffset(16, 12 + 32), Size = UDim2.new(1, -32, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })

	local stageBox = Ui.frame(card, { Name = "StageBox", ZIndex = 3 })
	local infoBox = Ui.frame(card, { Name = "Info", ZIndex = 3 })
	local btnH = if m.compact then 48 else 54
	if split then
		stageBox.Position = UDim2.fromOffset(16, titleH)
		stageBox.Size = UDim2.new(0.52, -20, 1, -titleH - btnH - 28)
		infoBox.Position = UDim2.new(0.52, 4, 0, titleH)
		infoBox.Size = UDim2.new(0.48, -20, 1, -titleH - btnH - 28)
	else
		local sh = math.floor(math.clamp((H - titleH - btnH - 40) * 0.5, 120, 260))
		stageBox.Position = UDim2.fromOffset(16, titleH)
		stageBox.Size = UDim2.new(1, -32, 0, sh)
		infoBox.Position = UDim2.fromOffset(16, titleH + sh + 10)
		infoBox.Size = UDim2.new(1, -32, 1, -(titleH + sh + 10) - btnH - 24)
	end
	stage = ctx.Viewport.stage(stageBox, { interactive = true, spin = 28, zIndex = 4 })
	stage:set(e.preview, colorId, e.grade == "used", e.glyph)

	-- plate
	Ui.list(infoBox, "y", 8, Enum.HorizontalAlignment.Center)
	local plateF = Ui.frame(infoBox, { Name = "Plate", Size = UDim2.fromOffset(240, 52), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(248, 248, 246), LayoutOrder = 1, ZIndex = 4 })
	Ui.corner(plateF, 8)
	Ui.stroke(plateF, Color3.fromRGB(30, 30, 30), 2, 0)
	local plateL = Ui.label(plateF, { Text = "", Font = Ui.F.black, TextSize = 24, TextColor3 = Color3.fromRGB(20, 20, 20), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	task.spawn(plateReveal, plateL, plate)
	-- summary
	local lines = {}
	if receipt.loan then
		table.insert(lines, string.format("📅 계약금 %s 결제 · 하루 %s × %d일", U.won(receipt.loan.down or receipt.paid or 0), U.won(receipt.loan.daily or 0), receipt.loan.days or 10))
	else
		table.insert(lines, string.format("💳 %s 결제 (%s)", U.won(receipt.paid or receipt.price or e.price), if receipt.account == "cash" then "현금" else "통장"))
	end
	if (res.cashback or 0) > 0 then
		table.insert(lines, string.format("🎁 출고 혜택 %s 통장 환급 완료", U.won(res.cashback)))
	end
	if type(res.trade) == "table" then
		table.insert(lines, string.format("🔁 보상판매 %s · +%s", tostring(res.trade.name), U.won((res.trade.payout or 0) + (res.trade.bonus or 0))))
	end
	table.insert(lines, "🔑 언제든 화면 오른쪽 위 '🚗 내 차' 버튼이나 휴대폰에서 부를 수 있어요")
	for i, t in lines do
		Ui.label(infoBox, { Text = t, Font = Ui.F.med, TextSize = if m.compact then 12 else 13, TextColor3 = if i == #lines then Col.faint else Col.ink, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 + i, ZIndex = 4 })
	end
	local voice = (npc and npc.voice) or "consult"
	local quote = ctx.S.Lines.get(voice, "delivered", { car = e.short or e.name, plate = plate })
	Ui.label(infoBox, { Text = "💬 " .. ((npc and npc.name) or "광안 오토") .. " · “" .. quote .. "”", Font = Ui.F.bold, TextSize = if m.compact then 12 else 13, TextColor3 = Col.accent, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 20, ZIndex = 4 })

	-- key hand-over
	local key = Ui.label(card, { Text = "🔑", TextSize = 56, Size = UDim2.fromOffset(80, 80), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, -0.1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 20 })
	if Ui.reduced() then
		key.Visible = false
	else
		Ui.tween(key, 0.7, { Position = UDim2.fromScale(0.5, 0.42) }, Enum.EasingStyle.Back)
		task.delay(1.4, function()
			if key.Parent then
				Ui.tween(key, 0.45, { Position = UDim2.new(0.25, 0, 1, -btnH / 2 - 12), TextSize = 20 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				task.delay(0.5, function()
					key:Destroy()
				end)
			end
		end)
	end
	confetti(gui, if m.phone then 40 else 70)
	if npc then
		ctx.NpcFx.emote(npc.id, "give")
		task.delay(2.2, function()
			ctx.NpcFx.emote(npc.id, "bow")
		end)
		ctx.NpcFx.say(npc.id, "축하드려요! 🎉", 4)
	end

	-- buttons
	local row = Ui.frame(card, { Name = "Buttons", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -32, 0, btnH), ZIndex = 5 })
	Ui.list(row, "x", 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local bw = math.floor((W - 32 - 10) / 2)
	local drive = Ui.button(row, { text = "지금 타기", icon = "🚗", style = "gold", size = UDim2.fromOffset(bw, btnH), order = 1, textSize = 16, z = 6 })
	local later = Ui.button(row, { text = "나중에 탈게요", style = "secondary", size = UDim2.fromOffset(bw, btnH), order = 2, textSize = 15, z = 6 })
	local busy = false
	drive.onClick(function()
		if busy then
			return
		end
		local id = car.id
		if type(id) ~= "string" then
			close()
			return
		end
		busy = true
		drive.setText("차를 가져오는 중…", "⏳")
		local r = ctx.Net.call("deliver", { id = id })
		busy = false
		if r.ok then
			close()
			ctx.CatalogUI.close()
			Ui.toast({ kind = "success", icon = "🚗", title = (r.label or e.short or e.name) .. " 출고!", body = if r.seated then "운전석에 앉았어요 · 안전 운전하세요!" else string.format("%dm 앞에 세워 뒀어요", tonumber(r.meters) or 0) })
		else
			drive.setText("지금 타기", "🚗")
			Ui.toast({ kind = "error", icon = "🚗", title = "차를 부르지 못했어요", body = r.message or "'🚗 내 차'에서 다시 불러 주세요" })
		end
	end)
	later.onClick(function()
		close()
		Ui.toast({ kind = "info", icon = "🔑", title = "언제든 부를 수 있어요", body = "화면 오른쪽 위 '🚗 내 차' 버튼 · 휴대폰 '내 차' 앱에서 불러 타세요" })
	end)
	Ui.select(drive.inst)
	Ui.bind("GwCarDealerCeremony", function(_, st)
		if st == Enum.UserInputState.Begin then
			close()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, 3200, Enum.KeyCode.ButtonB)
	if not Ui.reduced() then
		local sc = Ui.make("UIScale", { Scale = 0.9 }, card)
		Ui.tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	local _ = player
end

function Ceremony.init(c: any)
	ctx = c
	Ui = c.Ui
	C = c.C
	U = c.S.Util
	Col = Ui.C
end

return Ceremony
