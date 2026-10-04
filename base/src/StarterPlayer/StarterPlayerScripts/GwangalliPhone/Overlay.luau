-- GwangalliPhone/Overlay: the always-on life-game HUD pieces, built with the GwangalliUI kit and placed
-- with the GwangalliLayout slot contract.
--   * Money chip ("topLeftChips"): 현금 (mono, count-up + green / red flash) over 통장 (short form);
--     a "+12,000원" delta floats down under it; tap -> 통장 app.
--   * Shift card ("topRight"; the tracker widget steps aside while on shift): job icon (timer ring
--     for timed tasks), job + level, 퇴근 (asks first), the current task, shift progress and 오늘 번 돈.
--     "choice" tasks never pop up by themselves: the card pulses ("💬 탭해서 답하기") and a tap opens
--     the question in the dialog sheet (with the timer ring). Tasks without a world target complete
--     with a tap; others open the map on the target.
--   * NPC dialog (Dialog remote) in its own ScreenGui "GwangalliDialog" (DisplayOrder 35) in the
--     "dialog" slot: right of the thumbstick zone and above the jump button on landscape phones, so
--     the character controls stay usable (nothing is locked). On phones it carries HideGwangalliHUD
--     while shown (it covers the right column). Choices send "dialogChoice" {npcId, choiceId}.

local Players = game:GetService("Players")

local Overlay = {}

local ctx: any = nil
local K: any = nil
local Layout: any = nil
local player = Players.LocalPlayer

local hudGui: ScreenGui
local chip: TextButton
local chipScale: UIScale
local cashMoney: any
local bankMoney: any
local flash: TextLabel
local shiftCard: Frame
local shiftScale: UIScale
local shiftStroke: UIStroke
local shiftIcon: Frame
local shiftGlyph: TextLabel
local shiftRing: any
local shiftTitle: TextLabel
local shiftSub: TextLabel
local shiftTask: TextLabel
local shiftBar: any
local shiftEarn: any
local shiftEnd: TextButton
local dialogGui: ScreenGui
local dialog: any
local currentNpc: any = nil
local lastNotifyPay = -math.huge
local lastEarned: number? = nil
local lastMoney: number? = nil
local work: any = nil
local workDialogTask: any = nil -- the dialog currently shows this work task
local taskSeen: { [any]: number } = {} -- task id -> os.clock() when it arrived (timer rings)
local ringSerial = 0
local dialogSerial = 0
local mode = "phoneL"
local phoneOpen = false
local lastDialogShown = false
local confirmEnd = false

Overlay.hudShown = true
Overlay.otherShown = true
Overlay.onDialogChanged = nil :: any

local function dialogVisible(): boolean
	return dialog ~= nil and dialog.visible == true
end

function Overlay.dialogOpen(): boolean
	return dialogVisible()
end

---------------------------------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------------------------------
local function refreshShown()
	local onShift = type(work) == "table" and work.onShift == true
	local dlg = dialogVisible()
	if dialogGui then
		dialogGui.Enabled = Overlay.otherShown ~= false
		-- phones: the sheet covers the right column (이동 / 달리기 step aside meanwhile)
		dialogGui:SetAttribute("HideGwangalliHUD", dlg and (mode == "phoneL" or mode == "phoneP"))
	end
	if shiftCard then
		shiftCard.Visible = Overlay.hudShown and not phoneOpen and onShift and not (dlg and mode ~= "pc" and mode ~= "tablet")
	end
	if chip then
		chip.Visible = Overlay.hudShown
	end
	ctx.Tracker.setWidgetSuppressed(onShift or dlg)
	ctx.Tracker.setArrowSuppressed(dlg)
	-- tell the shell only when the dialog's visibility flips (it re-runs refreshHud -> setShown)
	if dlg ~= lastDialogShown then
		lastDialogShown = dlg
		if Overlay.onDialogChanged then
			task.defer(Overlay.onDialogChanged)
		end
	end
end

function Overlay.setOtherShown(shown: boolean)
	Overlay.otherShown = shown
	refreshShown()
end
function Overlay.setShown(shown: boolean, isPhoneOpen: boolean?)
	Overlay.hudShown = shown
	phoneOpen = isPhoneOpen == true
	refreshShown()
end

---------------------------------------------------------------------------------------------------
-- Money chip
---------------------------------------------------------------------------------------------------
local function fitChip()
	if not chip then
		return
	end
	local s = chipScale.Scale
	local slot = Layout.rect("topLeftChips")
	local cashW = K.textSize(cashMoney.label.Text, 15, K.Font.bold).X + 6
	local bankW = K.textSize(bankMoney.label.Text, 11, K.Font.medium).X + 4
	-- narrow (portrait) screens can give a slot thinner than the 132 px minimum: clamp needs min <= max
	local maxW = math.max(1, math.floor(slot.w / s))
	local w = math.clamp(math.ceil(math.max(cashW, bankW, 70)) + 56, math.min(132, maxW), maxW)
	chip.Size = UDim2.fromOffset(w, math.floor(slot.h / s))
end

local function refreshMoney(animate: boolean)
	local p = ctx.Net.profile
	local cash = ctx.Life.cash(p)
	local bank = ctx.Life.bank(p)
	if not ctx.Net.hasProfile then
		K.setText(cashMoney.label, "연결 중…")
		K.setText(bankMoney.label, "🏦 —")
		fitChip()
		return
	end
	cashMoney.set(cash, animate)
	bankMoney.set(bank, false)
	local total = cash + bank
	if lastMoney and animate and total ~= lastMoney then
		local d = total - lastMoney
		flash.Text = (if d > 0 then "+" else "") .. K.won(d)
		flash.TextColor3 = if d > 0 then K.Color.green else Color3.fromRGB(255, 130, 130)
		flash.Position = UDim2.new(0, 44, 1, 0)
		flash.TextTransparency = 0
		flash.TextStrokeTransparency = 0.45
		flash.Visible = true
		K.tween(flash, 1.5, { Position = UDim2.new(0, 44, 1, 16), TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad)
		local mine = flash.Text
		task.delay(1.6, function()
			if flash.Text == mine then
				flash.Visible = false
			end
		end)
		local sc = chip:FindFirstChild("Bump") :: UIScale?
		if sc and not K.reduced() then
			sc.Scale = 1.06
			K.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	lastMoney = total
	fitChip()
end

---------------------------------------------------------------------------------------------------
-- Shift card
---------------------------------------------------------------------------------------------------
local function jobTitle(jobId: any, w: any?): string
	if type(w) == "table" and type(w.jobTitle) == "string" then
		return w.jobTitle
	end
	local j = ctx.Net.profile.job
	if type(j) == "table" and j.id == jobId and type(j.title) == "string" then
		return j.title
	end
	local def = ctx.Life.job(jobId)
	return (def and def.title) or "근무"
end

local function jobIcon(w: any): string
	if type(w) == "table" and type(w.icon) == "string" and w.icon ~= "" then
		return w.icon
	end
	local def = type(w) == "table" and ctx.Life.job(w.jobId) or nil
	return (def and def.icon) or "💼"
end

local function choicesOf(t: any): { any }
	local out = {}
	if type(t) == "table" and type(t.choices) == "table" then
		for i, label in t.choices do
			table.insert(out, { id = i, label = if type(label) == "table" then tostring(label.label or label.text or i) else tostring(label), style = "secondary" })
		end
	end
	if out[1] then
		out[1].style = "primary"
	end
	return out
end

local function timerFor(t: any): any
	local limit = type(t) == "table" and tonumber(t.timeLimit) or nil
	if not limit or limit <= 0 or t.id == nil then
		return nil
	end
	local seen = taskSeen[t.id] or os.clock()
	return { total = limit, left = math.max(0, limit - (os.clock() - seen)) }
end

-- ring around the job icon: time left for timed tasks
local function runRing(t: any)
	ringSerial += 1
	local mine = ringSerial
	local timer = timerFor(t)
	if not timer then
		shiftRing.frame.Visible = false
		return
	end
	shiftRing.frame.Visible = true
	local t0 = os.clock()
	task.spawn(function()
		while ringSerial == mine and shiftCard.Parent do
			local left = math.max(0, timer.left - (os.clock() - t0))
			shiftRing.set(left / timer.total)
			shiftRing.setColor(if left / timer.total < 0.25 then K.Color.red else K.Color.gold)
			if left <= 0 then
				break
			end
			task.wait(0.2)
		end
	end)
end

local function openWorkQuestion()
	local w = work
	local t = type(w) == "table" and w.task or nil
	if type(t) ~= "table" or t.kind ~= "choice" or t.id == nil then
		return
	end
	local choices = choicesOf(t)
	if #choices == 0 then
		return
	end
	currentNpc = nil
	confirmEnd = false
	workDialogTask = t.id
	if ctx.phone.isOpen() then
		ctx.phone.close()
	end
	Overlay.layoutDialog()
	K.pulse(shiftStroke, false)
	dialog.show({ name = jobTitle(w.jobId, w), role = tostring(w.place or "근무 중"), portraitColor = K.Color.gold, icon = jobIcon(w), text = t.prompt or "", choices = choices, timer = timerFor(t) })
	refreshShown()
end

local function applyWork(w: any)
	work = w
	local on = type(w) == "table" and w.onShift == true
	if not on then
		ctx.Tracker.setWorkTarget(nil)
		lastEarned = nil
		if confirmEnd then
			confirmEnd = false
			if currentNpc == nil and dialogVisible() then
				dialog.hide()
			end
		end
		K.pulse(shiftStroke, false)
		ringSerial += 1
		if workDialogTask ~= nil then
			workDialogTask = nil
			if currentNpc == nil and dialogVisible() then
				dialog.hide()
			end
		end
		refreshShown()
		return
	end
	local title = jobTitle(w.jobId, w)
	K.setText(shiftTitle, title)
	K.setText(shiftSub, string.format("Lv.%s %s", tostring(w.level or 1), tostring(w.levelTitle or "")))
	shiftGlyph.Text = jobIcon(w)
	local t = if type(w.task) == "table" then w.task else nil
	if t and t.id ~= nil and not taskSeen[t.id] then
		taskSeen[t.id] = os.clock()
	end
	local prompt = if t and type(t.prompt) == "string" then t.prompt else "다음 작업을 기다리는 중…"
	local pulse = false
	if t and t.kind == "tap" then
		prompt = "👆 " .. prompt .. " · 탭!"
		pulse = true
	elseif t and t.kind == "choice" then
		prompt = "💬 " .. prompt
		pulse = true
	elseif t and t.kind == "goto" then
		prompt = "📍 " .. prompt
	elseif t and t.kind == "hold" then
		prompt = "✋ " .. prompt
	end
	K.setText(shiftTask, prompt)
	-- the second line carries the call to action when the task wants a tap, else the level
	local cta = if t and t.kind == "choice" then "탭해서 답하기 ›" elseif t and t.kind == "tap" then "탭해서 완료 ›" else nil
	if cta then
		K.setText(shiftSub, cta)
		shiftSub.TextColor3 = K.Color.gold
	else
		K.setText(shiftSub, string.format("Lv.%s %s", tostring(w.level or 1), tostring(w.levelTitle or "")))
		shiftSub.TextColor3 = K.Color.sub
	end
	K.pulse(shiftStroke, pulse and not dialogVisible())
	if not pulse then
		shiftStroke.Transparency = 0.6
	end
	local prog = if type(w.progress) == "table" then w.progress else nil
	local total = prog and tonumber(prog.total) or 0
	local done = prog and tonumber(prog.done) or 0
	shiftBar.set(if total > 0 then done / total else 0)
	local stepText = shiftCard:FindFirstChild("Step") :: TextLabel?
	if stepText then
		stepText.Text = if total > 0 then string.format("%d/%d", math.min(total, done + (if t then 1 else 0)), total) else ""
	end
	runRing(t)
	-- a choice question already on screen: close it if the task moved on
	if workDialogTask ~= nil and (not t or t.id ~= workDialogTask) then
		workDialogTask = nil
		if currentNpc == nil and dialogVisible() then
			dialog.hide()
		end
	end
	local earned = tonumber(w.earnedToday) or 0
	shiftEarn.set(earned, lastEarned ~= nil)
	if lastEarned and earned > lastEarned and os.clock() - lastNotifyPay > 1.5 then
		ctx.phone.toast({ app = "bank", title = "급여 +" .. K.won(earned - lastEarned), body = title .. " · 오늘 " .. K.won(earned), glyph = "💵", kind = "pay" })
	end
	lastEarned = earned
	local where = if t then (if typeof(t.position) == "Vector3" then t.position else t.target) else nil
	if where ~= nil then
		ctx.Tracker.setWorkTarget({ title = jobIcon(w) .. " " .. title, text = t.prompt or "", target = where })
	else
		ctx.Tracker.setWorkTarget(nil)
	end
	refreshShown()
end

---------------------------------------------------------------------------------------------------
-- Dialog
---------------------------------------------------------------------------------------------------
function Overlay.layoutDialog()
	if not dialog then
		return
	end
	local r = Layout.rect("dialog")
	local bottom = mode == "tablet" or mode == "pc"
	dialog.place(r, bottom)
end

local function endConversation(sendClose: boolean)
	local npc = currentNpc
	currentNpc = nil
	dialogSerial += 1
	if dialogVisible() then
		dialog.hide()
	end
	if sendClose and npc ~= nil then
		ctx.Net.send("dialogChoice", { npcId = npc, choiceId = "close" })
	end
end

local function onDialog(data: any)
	if data.close == true then
		currentNpc = nil
		if dialogVisible() then
			dialog.hide()
		end
		return
	end
	currentNpc = data.npcId
	workDialogTask = nil
	confirmEnd = false
	if ctx.phone.isOpen() then
		ctx.phone.close()
	end
	Overlay.layoutDialog()
	dialog.show(data)
	refreshShown()
	-- a face-to-face conversation ends when the player walks away (the server may not say so)
	dialogSerial += 1
	local mine = dialogSerial
	if data.remote == true then
		-- a phone call hangs up by itself after a while
		task.delay(45, function()
			if dialogSerial == mine and dialogVisible() then
				endConversation(true)
			end
		end)
	else
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local origin = root.Position
			task.spawn(function()
				while dialogSerial == mine and dialogVisible() do
					task.wait(0.5)
					local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if dialogSerial == mine and dialogVisible() and (not (r and r:IsA("BasePart")) or (r.Position - origin).Magnitude > 24) then
						endConversation(true)
						break
					end
				end
			end)
		end
	end
end

-- The phone opened: a face-to-face conversation ends; a work question steps aside (the card
-- keeps pulsing, a tap brings it back).
function Overlay.onPhoneOpened()
	if not dialogVisible() then
		return
	end
	if workDialogTask ~= nil and currentNpc == nil then
		workDialogTask = nil
		dialog.hide()
		return
	end
	endConversation(true)
end

---------------------------------------------------------------------------------------------------
-- Layout (called from Phone.applyLayout)
---------------------------------------------------------------------------------------------------
function Overlay.layout(m: string, hs: number)
	mode = m
	if not chip then
		return
	end
	local s = Layout.metrics().s
	chipScale.Scale = s
	local slot = Layout.rect("topLeftChips")
	chip.AnchorPoint = Vector2.new(0, 0)
	chip.Position = UDim2.fromOffset(slot.x, slot.y)
	fitChip()

	shiftScale.Scale = s
	local tr = Layout.rect("topRight")
	shiftCard.AnchorPoint = Vector2.new(1, 0)
	shiftCard.Position = UDim2.fromOffset(tr.x + tr.w, tr.y)
	shiftCard.Size = UDim2.fromOffset(math.floor(tr.w / s), math.min(104, math.floor(tr.h / s)))
	Overlay.layoutDialog()
	refreshShown()
	local _ = hs
end

---------------------------------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------------------------------
function Overlay.init(c: any, gui: ScreenGui, playerGui: PlayerGui)
	ctx = c
	K = c.K
	Layout = c.Layout
	hudGui = gui
	local Net = c.Net

	-- money chip ------------------------------------------------------------------------------------------
	chip = K.make("TextButton", { Name = "MoneyChip", Size = UDim2.fromOffset(150, 44), BackgroundColor3 = K.Color.glass, BackgroundTransparency = K.GLASS_T, Text = "", AutoButtonColor = false, ZIndex = 3 }, hudGui)
	chipScale = K.make("UIScale", { Scale = 1 }, chip)
	K.make("UIScale", { Name = "Bump", Scale = 1 }, K.frame(chip, { Name = "BumpHost" }))
	K.corner(chip, K.Radius.md)
	K.stroke(chip, Color3.new(1, 1, 1), 1, 0.84)
	K.shadow(chip, K.Radius.md, 4, "soft")
	local coin = K.iconTile(chip, 30, "₩", K.Color.gold, true)
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 7, 0.5, 0)
	coin.ZIndex = 4
	for _, d in coin:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 4
		end
		if d:IsA("TextLabel") then
			d.TextColor3 = K.Color.onGold
			d.Font = K.Font.heavy
		end
	end
	cashMoney = K.MoneyLabel(chip, { Name = "Cash", Position = UDim2.fromOffset(44, 5), Size = UDim2.new(1, -50, 0, 19), Text = "0원", Font = K.Font.bold, TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
	bankMoney = K.MoneyLabel(chip, { Name = "Bank", Position = UDim2.fromOffset(44, 24), Size = UDim2.new(1, -50, 0, 15), Text = "0원", TextColor3 = K.Color.sub, Font = K.Font.medium, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4, Mono = false })
	bankMoney.prefix = "🏦 "
	bankMoney.format = K.wonShort
	bankMoney.flash = false
	flash = K.text(chip, { Name = "Flash", Position = UDim2.new(0, 44, 1, 0), Size = UDim2.new(1, -44, 0, 18), Text = "", Font = K.Font.bold, TextSize = 14, TextStrokeTransparency = 0.45, Visible = false, ZIndex = 4 })
	K.mono(flash)
	K.pressable(chip, { scale = 0.96 })
	chip.Activated:Connect(function()
		c.phone.open("bank")
	end)

	-- shift card -------------------------------------------------------------------------------------------
	shiftCard = K.frame(hudGui, { Name = "ShiftCard", Size = UDim2.fromOffset(260, 104), BackgroundTransparency = 0.08, BackgroundColor3 = K.Color.glass2, Visible = false, Active = true, ZIndex = 3 })
	shiftScale = K.make("UIScale", { Scale = 1 }, shiftCard)
	K.corner(shiftCard, K.Radius.lg)
	shiftStroke = K.stroke(shiftCard, K.Color.gold, 1.5, 0.6)
	K.shadow(shiftCard, K.Radius.lg, 6, "mid")
	-- the card is tappable everywhere except the 퇴근 button column on the right
	local tap = K.make("TextButton", { Name = "Tap", Size = UDim2.new(1, -66, 1, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 4 }, shiftCard)
	shiftIcon = K.iconTile(shiftCard, 36, "💼", K.Color.gold)
	shiftIcon.Position = UDim2.fromOffset(12, 12)
	shiftIcon.ZIndex = 5
	shiftGlyph = shiftIcon:FindFirstChild("Glyph") :: TextLabel
	for _, d in shiftIcon:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 5
		end
	end
	shiftRing = K.Ring(shiftCard, { name = "TaskTimer", size = 44, thickness = 3, color = K.Color.gold })
	shiftRing.frame.Position = UDim2.fromOffset(8, 8)
	shiftRing.frame.ZIndex = 6
	for _, d in shiftRing.frame:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 6
		end
	end
	shiftRing.frame.Visible = false
	shiftTitle = K.text(shiftCard, { Name = "Title", Position = UDim2.fromOffset(58, 11), Size = UDim2.new(1, -116, 0, 18), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
	shiftSub = K.text(shiftCard, { Name = "Level", Position = UDim2.fromOffset(58, 29), Size = UDim2.new(1, -116, 0, 15), Text = "", TextColor3 = K.Color.gold, Font = K.Font.bold, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
	shiftEnd = K.Button(shiftCard, { name = "EndShift", text = "퇴근", style = "danger", anchor = Vector2.new(1, 0), position = UDim2.new(1, -8, 0, 8), size = UDim2.fromOffset(52, 44), textSize = K.Type.caption, zIndex = 6 })
	shiftTask = K.text(shiftCard, { Name = "Task", Position = UDim2.fromOffset(12, 54), Size = UDim2.new(1, -24, 0, 28), Text = "", TextColor3 = K.Color.text, TextSize = K.Type.caption, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
	shiftBar = K.ProgressBar(shiftCard, { color = K.Color.gold, height = 4 })
	shiftBar.frame.Position = UDim2.new(0, 12, 1, -14)
	shiftBar.frame.Size = UDim2.new(0.42, -12, 0, 4)
	shiftBar.frame.ZIndex = 5
	shiftBar.fill.ZIndex = 5
	K.text(shiftCard, { Name = "Step", Position = UDim2.new(0.42, 6, 1, -21), Size = UDim2.fromOffset(34, 16), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.micro, Font = K.Font.bold, ZIndex = 5 })
	shiftEarn = K.MoneyLabel(shiftCard, { Name = "Earned", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -8), Size = UDim2.new(0.5, -12, 0, 16), Text = "", TextColor3 = K.Color.green, Font = K.Font.bold, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
	shiftEarn.prefix = "오늘 +"
	shiftEarn.flash = false
	-- 퇴근 asks first, in the dialog sheet (the safe "dialog" slot, clear of the thumbstick zone)
	shiftEnd.Activated:Connect(function()
		if ctx.phone.isOpen() then
			ctx.phone.close()
		end
		currentNpc = nil
		workDialogTask = nil
		confirmEnd = true
		Overlay.layoutDialog()
		K.pulse(shiftStroke, false)
		dialog.show({
			name = "퇴근할까요?",
			role = jobTitle(work and work.jobId, work),
			portraitColor = K.Color.orange,
			icon = "🏁",
			text = "오늘 번 돈은 통장으로 들어가요. 진행 중인 작업은 사라져요.",
			choices = { { id = "end", label = "퇴근하기", style = "destructive" }, { id = "stay", label = "계속 일하기", style = "secondary" } },
		})
		refreshShown()
	end)
	K.pressable(tap, { scale = 0.985 })
	tap.Activated:Connect(function()
		local t = work and work.task
		if type(t) ~= "table" then
			return
		end
		if t.kind == "choice" and t.id ~= nil then
			openWorkQuestion()
		elseif (t.kind == "tap" or (t.target == nil and t.position == nil)) and t.id ~= nil then
			Net.send("workTask", { taskId = t.id, ok = true })
			K.feedback("success")
		elseif type(t.target) == "string" then
			c.phone.open("map", { focus = t.target })
		end
	end)

	-- dialog -----------------------------------------------------------------------------------------------
	local old = playerGui:FindFirstChild("GwangalliDialog")
	if old then
		old:Destroy()
	end
	dialogGui = K.make("ScreenGui", {
		Name = "GwangalliDialog",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 35, -- above the phone (30): a conversation is never hidden behind it
		Enabled = true,
	})
	dialog = K.DialogBox(dialogGui)
	dialog.onChoice = function(choiceId: any)
		if confirmEnd then
			confirmEnd = false
			dialog.hide()
			if choiceId == "end" then
				local ok, err = Net.send("endShift", {})
				if not ok then
					K.toast({ kind = "error", title = "퇴근할 수 없어요", body = err or "" })
				end
			end
			return
		end
		local npc = currentNpc
		if npc == nil and workDialogTask ~= nil then
			Net.send("workTask", { taskId = workDialogTask, choice = choiceId })
			workDialogTask = nil
			dialog.hide()
			return
		end
		if choiceId == "close" then
			dialog.hide()
		end
		if npc ~= nil then
			Net.send("dialogChoice", { npcId = npc, choiceId = choiceId })
		end
	end
	dialog.onClose = function()
		confirmEnd = false
		workDialogTask = nil
		local npc = currentNpc
		currentNpc = nil
		if npc ~= nil then
			Net.send("dialogChoice", { npcId = npc, choiceId = "close" })
		end
	end
	dialog.onHidden = function()
		refreshShown()
		if work then
			-- a work question that was closed keeps pulsing on the card
			local t = work.task
			if type(t) == "table" and t.kind == "choice" then
				K.pulse(shiftStroke, true)
			end
		end
	end
	dialogGui.Parent = playerGui

	-- events -----------------------------------------------------------------------------------------------
	Net.on("profile", function(changed: any)
		if changed.money or changed.cash or changed.bank then
			refreshMoney(lastMoney ~= nil)
		end
		if changed.job and work then
			applyWork(work)
		end
	end)
	Net.on("work", function(w: any)
		local ok, err = pcall(applyWork, w)
		if not ok then
			warn("[GwangalliPhone] work: " .. tostring(err))
		end
	end)
	Net.on("dialog", function(d: any)
		local ok, err = pcall(onDialog, d)
		if not ok then
			warn("[GwangalliPhone] dialog: " .. tostring(err))
		end
	end)
	Net.on("notify", function(n: any)
		if n.kind == "money" or n.kind == "pay" then
			lastNotifyPay = os.clock()
		end
	end)
	player.CharacterAdded:Connect(function()
		-- a respawn ends any conversation on screen (the server re-sends if it still wants one)
		if dialogVisible() then
			currentNpc = nil
			workDialogTask = nil
			dialog.hide()
		end
	end)
	refreshMoney(false)
	if Net.work then
		applyWork(Net.work)
	end
	refreshShown()
end

return Overlay
