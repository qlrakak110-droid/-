--!nocheck
-- GwangalliJobs/Stage: the round BOTTOM SHEET (feedback stage: "UI가 앞을 가림" fixed).
--   * no dim, no centred panel: a sheet docked to the bottom edge, at most 30 % of the screen height
--     on landscape phones and 38 % on portrait (J.metrics().sheetMax); a 4 px timer bar on its top
--     edge, a 26 px header (icon · title · hint · seconds), the round's body below (Games.luau)
--   * "chip" mode (restock: you walk around carrying the box): the sheet collapses into a compact
--     chip in the Layout "bottomCenter" band and the controls stay free; the builder expands it
--     again when you reach a shelf slot
--   * results are small pills that rise above the sheet for ~1.3 s (pay, combo, speed, tip,
--     debuff); the world (boss bubble, customer) tells the rest
--   * the shift summary is a side rail on the right (landscape) / a bottom sheet (portrait)
--   * while the full sheet is up the character controls are locked (the sheet covers the
--     thumbstick / jump zones) and the station camera framing is World.luau's
-- One timer driver (0.1 s task loop) while a round is open; everything else is event / tween driven.

local Stage = {}

local J: any
local K: any
local JS: any
local gui: ScreenGui

local root: Frame? = nil
local sheet: Frame
local sheetStroke: UIStroke
local timerBar: any
local header: Frame
local iconLabel: TextLabel
local titleLabel: TextLabel
local hintLabel: TextLabel
local secLabel: TextLabel
local body: Frame
local pillRow: Frame
local chip: Frame
local chipText: TextLabel
local chipSec: TextLabel

local current: any = nil -- { p, api, deadline, submitted, resolved, compact, bodyH }
local queued: any = nil
local timerSerial = 0
local open = false
local summaryHost: Frame? = nil

function Stage.init(ctx: any)
	J = ctx
	K = ctx.K
	JS = ctx.JS
	gui = ctx.gui
end

function Stage.isOpen(): boolean
	return open
end

-------------------------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------------------------
local HEADER_H = 26
local PAD = 8

local function sheetWidth(m: any): number
	return if m.landscape then math.min(m.W - 16, 820) else m.W - 12
end

local function layout()
	if not root then
		return
	end
	local m = J.metrics()
	local c = current
	local compact = c and c.compact
	sheet.Visible = open and not compact
	chip.Visible = open and compact == true
	local w = sheetWidth(m)
	local maxBody = math.max(56, m.sheetMax - HEADER_H - 4 - PAD * 2)
	local want = (c and c.bodyH) or (if m.landscape then 70 else 200)
	local bh = math.clamp(want, 56, maxBody)
	local h = 4 + HEADER_H + bh + PAD * 2
	sheet.AnchorPoint = Vector2.new(0.5, 1)
	sheet.Position = UDim2.new(0.5, 0, 1, -4)
	sheet.Size = UDim2.fromOffset(w, h)
	header.Position = UDim2.fromOffset(PAD, 4 + 3)
	header.Size = UDim2.new(1, -PAD * 2, 0, HEADER_H)
	body.Position = UDim2.fromOffset(PAD, 4 + HEADER_H + PAD)
	body.Size = UDim2.new(1, -PAD * 2, 0, bh)
	hintLabel.Visible = m.landscape or w >= 360
	-- chip: the bottom-centre band (between the thumbstick zone and the jump button / above it)
	local r = nil
	pcall(function()
		r = J.Layout.rect("bottomCenter")
	end)
	chip.AnchorPoint = Vector2.new(0.5, 1)
	if r then
		chip.Position = UDim2.fromOffset(r.x + r.w / 2, r.y + r.h)
		chip.Size = UDim2.fromOffset(math.min(r.w, 360), math.min(r.h, 54))
	else
		chip.Position = UDim2.new(0.5, 0, 1, -110)
		chip.Size = UDim2.fromOffset(math.min(m.W - 16, 340), 54)
	end
	pillRow.AnchorPoint = Vector2.new(0.5, 1)
	pillRow.Position = UDim2.new(0.5, 0, 1, -(h + 10))
	if c and c.api and type(c.api.relayout) == "function" then
		task.defer(function()
			if current == c and c.api then
				pcall(c.api.relayout, m, bh)
			end
		end)
	end
end

local function setHint(t: string)
	if root then
		K.setText(hintLabel, t or "")
	end
end

local function build()
	if root then
		return
	end
	root = K.frame(gui, { Name = "Stage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = true, ZIndex = 10 })
	sheet = K.Panel(root, { Name = "Sheet", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(380, 120), BackgroundTransparency = 0.06, Radius = K.Radius.lg, ZIndex = 11 })
	sheet.Active = true -- taps on the sheet never reach the world / thumbstick
	sheet.Visible = false
	sheetStroke = K.stroke(sheet, K.Color.gold, 1.5, 0.7)
	timerBar = K.ProgressBar(sheet, { color = K.Color.gold, height = 4 })
	timerBar.frame.Position = UDim2.fromOffset(14, 2)
	timerBar.frame.Size = UDim2.new(1, -28, 0, 4)
	timerBar.frame.ZIndex = 12
	timerBar.fill.ZIndex = 12
	header = K.frame(sheet, { Name = "Header", ZIndex = 12 })
	iconLabel = K.text(header, { Name = "Icon", Size = UDim2.fromOffset(26, 26), Text = "🎮", TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 })
	titleLabel = K.text(header, { Name = "Title", Position = UDim2.fromOffset(30, 0), Size = UDim2.new(0, 150, 1, 0), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12 })
	hintLabel = K.text(header, { Name = "Hint", Position = UDim2.fromOffset(186, 0), Size = UDim2.new(1, -236, 1, 0), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12 })
	secLabel = K.text(header, { Name = "Seconds", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(46, 26), Text = "", Font = K.Font.heavy, TextSize = K.Type.title2, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 12 })
	K.mono(secLabel)
	body = K.frame(sheet, { Name = "Body", ZIndex = 12 })
	body.ClipsDescendants = false
	pillRow = K.frame(root, { Name = "Pills", Size = UDim2.fromOffset(420, 30), ZIndex = 30 })
	K.list(pillRow, true, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	-- compact chip (restock: walk with the box)
	chip = K.Panel(root, { Name = "RoundChip", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(320, 54), BackgroundTransparency = 0.08, Radius = K.Radius.md, ZIndex = 11 })
	chip.Visible = false
	K.stroke(chip, K.Color.gold, 1, 0.6)
	chipText = K.text(chip, { Name = "Text", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -66, 1, 0), Text = "", Font = K.Font.bold, TextSize = K.Type.caption + 1, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12 })
	chipSec = K.text(chip, { Name = "Seconds", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(46, 30), Text = "", Font = K.Font.heavy, TextSize = K.Type.title2, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 12 })
	K.mono(chipSec)
	local function relayout()
		if open then
			layout()
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	local function bindCamera()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
		end
	end
	bindCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	if J.Layout and J.Layout.changed then
		pcall(function()
			J.Layout.changed:Connect(relayout)
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- Feedback
-------------------------------------------------------------------------------------------------
function Stage.shake(amp: number?)
	if not root or K.reduced() then
		return
	end
	local a = amp or 8
	local target = if current and current.compact then chip else sheet
	task.spawn(function()
		local base = target.Position
		for _, dx in { a, -a, a * 0.6, -a * 0.6, a * 0.25, 0 } do
			if not target.Parent then
				return
			end
			target.Position = base + UDim2.fromOffset(dx, 0)
			task.wait(0.03)
		end
		target.Position = base
	end)
	pcall(K.haptic, "error")
end

function Stage.flash(ok: boolean)
	if not root then
		return
	end
	sheetStroke.Color = if ok then K.Color.green else K.Color.red
	sheetStroke.Transparency = 0.1
	K.tween(sheetStroke, 0.5, { Transparency = 0.7 })
	task.delay(0.5, function()
		if sheetStroke.Parent then
			sheetStroke.Color = K.Color.gold
		end
	end)
	pcall(K.feedback, if ok then "success" else "error")
end

-- "😮‍💨 피로해서 집중이 안 돼요 -30%": the face only when the reason has no emoji of its own
local function withFace(reason: any): string
	local s = tostring(reason or "")
	local ok, cp = pcall(utf8.codepoint, s, 1)
	if ok and type(cp) == "number" and (cp < 0x2000 or (cp >= 0xAC00 and cp <= 0xD7A3)) then
		return "😮‍💨 " .. s
	end
	return s
end

local pillSerial = 0
local function pill(text: string, color: Color3, order: number)
	local p = K.Pill(pillRow, { text = text, color = color, height = 28, order = order })
	p.TextSize = K.Type.caption + 1
	local tw = K.textSize(text, K.Type.caption + 1, K.Font.bold).X
	p.Size = UDim2.fromOffset(math.ceil(tw) + 22, 28)
	p.BackgroundTransparency = 0.12
	p.BackgroundColor3 = K.Color.glass2
	p.TextColor3 = color
	K.stroke(p, color, 1, 0.4)
	p.ZIndex = 30
	return p
end

-- small pills above the sheet / near the bottom: "+3,100원 ✨ 완벽해요" · "🔥 x3 +30%" · ...
function Stage.flashResult(p: any)
	build()
	pillSerial += 1
	local mine = pillSerial
	for _, c in pillRow:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local m = J.metrics()
	local h = if open and current and not current.compact then sheet.AbsoluteSize.Y else (if m.landscape then 60 else 120)
	pillRow.AnchorPoint = Vector2.new(0.5, 1)
	pillRow.Position = UDim2.new(0.5, 0, 1, -(h + 14))
	pillRow.Size = UDim2.fromOffset(math.min(m.W - 16, 560), 30)
	local pay = tonumber(p.pay) or 0
	local ok = p.ok == true
	local head = if pay > 0 then "+" .. K.won(pay) else (if p.game == "order" then "주문 접수" elseif ok then "완료" else "0원")
	local msg = tostring(p.message or "")
	pill(head .. (if msg ~= "" and not m.landscape and #msg < 40 then "  " .. msg elseif msg ~= "" and m.landscape then "  " .. msg else ""), if pay > 0 then K.Color.green elseif ok then K.Color.cyan else K.Color.red, 1)
	local combo = tonumber(p.combo) or 0
	if ok and combo > 1 then
		pill(string.format("🔥 x%d +%d%%", combo, math.floor((JS.comboMult(combo) - 1) * 100 + 0.5)), K.Color.orange, 2)
	end
	if p.speedBonus then
		pill(if p.game == "deliver" then "⚡ 빠른 배달" else string.format("⚡ +%d%%", math.floor(JS.SPEED_BONUS * 100 + 0.5)), K.Color.cyan, 3)
	end
	if (tonumber(p.tip) or 0) > 0 then
		pill("💝 팁 +" .. K.won(p.tip), K.Color.gold, 4)
	end
	if (tonumber(p.fine) or 0) > 0 then
		pill("🚦 -" .. K.won(p.fine), K.Color.red, 5)
	end
	if p.payReason and ok then
		local why = withFace(p.payReason)
		if m.landscape == false and #why > 30 then
			why = (string.match(why, "^(%S+)") or "😮‍💨") .. " " .. (string.match(why, "(%-%d+%%)") or "")
		end
		pill(why, K.Color.orange, 6)
	end
	for _, c in pillRow:GetChildren() do
		if c:IsA("GuiObject") then
			K.springIn(c, 0.85, { amount = 0.2, duration = 0.3 })
		end
	end
	task.delay(JS.RESULT_SECONDS + 0.6, function()
		if pillSerial ~= mine then
			return
		end
		for _, c in pillRow:GetChildren() do
			if c:IsA("GuiObject") then
				K.tween(c, 0.25, { TextTransparency = 1, BackgroundTransparency = 1 })
				task.delay(0.3, function()
					if c.Parent then
						c:Destroy()
					end
				end)
			end
		end
	end)
	if ok then
		pcall(K.sound, if pay > 0 then "money" else "success")
	else
		pcall(K.feedback, "error")
	end
end

-------------------------------------------------------------------------------------------------
-- Rounds
-------------------------------------------------------------------------------------------------
local function clearBody()
	if current and current.api and type(current.api.destroy) == "function" then
		pcall(current.api.destroy)
	end
	for _, c in body:GetChildren() do
		c:Destroy()
	end
end

local function setCompact(c: any, on: boolean)
	c.compact = on
	J.lockControls(open and not on, "stage")
	layout()
	if on then
		K.springIn(chip, 0.9, { amount = 0.15, duration = 0.25 })
	else
		K.springIn(sheet, 0.95, { amount = 0.1, duration = 0.28 })
	end
end

local function showSheet()
	build()
	if open then
		return
	end
	open = true
	J.publishState(true)
	pcall(K.feedback, "open")
end

local function hideSheet()
	if not open then
		return
	end
	open = false
	timerSerial += 1
	clearBody()
	current = nil
	if root then
		sheet.Visible = false
		chip.Visible = false
	end
	J.lockControls(false, "stage")
	J.publishState(false)
	if J.World and type(J.World.roundClosed) == "function" then
		pcall(J.World.roundClosed)
	end
end

local function submit(answer: any)
	local c = current
	if not c or c.submitted then
		return
	end
	c.submitted = true
	timerSerial += 1
	setHint("확인 중…")
	J.send({ op = "answer", taskId = c.p.taskId, answer = answer })
	task.delay(5, function()
		if current == c and open and not c.resolved then
			hideSheet()
		end
	end)
end

local function startTimer(c: any)
	timerSerial += 1
	local mine = timerSerial
	local total = math.max(1, tonumber(c.p.timeLimit) or 20)
	timerBar.setColor(K.Color.gold)
	timerBar.set(1, true)
	task.spawn(function()
		while timerSerial == mine and current == c and open do
			local left = c.deadline - os.clock()
			local frac = math.clamp(left / total, 0, 1)
			timerBar.fill.Size = UDim2.fromScale(frac, 1)
			local txt = tostring(math.max(0, math.ceil(left)))
			K.setText(secLabel, txt)
			K.setText(chipSec, txt)
			local hurry = frac < 0.25
			secLabel.TextColor3 = if hurry then K.Color.red else K.Color.text
			chipSec.TextColor3 = secLabel.TextColor3
			if hurry then
				timerBar.setColor(K.Color.red)
			end
			if left <= 0 then
				local partial = nil
				if c.api and type(c.api.timeout) == "function" then
					local ok, res = pcall(c.api.timeout)
					if ok then
						partial = res
					end
				end
				Stage.shake(6)
				submit(partial)
				break
			end
			task.wait(0.1)
		end
	end)
end

local function openRound(p: any)
	showSheet()
	clearBody()
	local def = JS.GAMES[p.game] or {}
	local c: any = { p = p, game = p.game, submitted = false, resolved = false, compact = false, bodyH = nil }
	c.deadline = os.clock() + math.max(1, tonumber(p.timeLeft) or tonumber(p.timeLimit) or 20)
	current = c
	K.setText(iconLabel, tostring(p.icon or def.icon or "🎮"))
	K.setText(titleLabel, tostring(p.title or def.title or "알바"))
	local tw = K.textSize(titleLabel.Text, K.Type.bodySm, K.Font.bold).X
	titleLabel.Size = UDim2.new(0, math.min(170, math.ceil(tw) + 4), 1, 0)
	hintLabel.Position = UDim2.fromOffset(30 + math.min(170, math.ceil(tw) + 4) + 8, 0)
	hintLabel.Size = UDim2.new(1, -(30 + math.min(170, math.ceil(tw) + 4) + 8 + 50), 1, 0)
	setHint(tostring(p.hint or def.hint or ""))
	local builder = J.Games[p.game]
	if type(builder) ~= "function" then
		setHint("이 라운드는 이 버전에서 지원하지 않아요")
		layout()
		task.delay(0.5, function()
			submit(nil)
		end)
		return
	end
	local m = J.metrics()
	local api = {
		K = K,
		JS = JS,
		J = J,
		World = J.World,
		body = body,
		metrics = m,
		landscape = m.landscape,
		p = p,
		submit = submit,
		shake = Stage.shake,
		flash = Stage.flash,
		setHint = setHint,
		setBodyHeight = function(h: number)
			if current == c then
				c.bodyH = h
				layout()
			end
		end,
		bodyMax = function(): number
			local mm = J.metrics()
			return math.max(56, mm.sheetMax - HEADER_H - 4 - PAD * 2)
		end,
		setCompact = function(on: boolean)
			if current == c then
				setCompact(c, on)
			end
		end,
		setChip = function(text: string)
			if current == c then
				K.setText(chipText, text)
			end
		end,
		isCurrent = function()
			return current == c and not c.submitted
		end,
		timeLeft = function(): number
			return c.deadline - os.clock()
		end,
	}
	c.api = {}
	local ok, res = pcall(builder, api, p.view or {}, p)
	if not ok then
		warn("[GwangalliJobs] game " .. tostring(p.game) .. " failed: " .. tostring(res))
		layout()
		task.delay(0.5, function()
			submit(nil)
		end)
		return
	end
	c.api = res or {}
	if type(c.api.bodyHeight) == "number" and not c.bodyH then
		c.bodyH = c.api.bodyHeight
	end
	if c.api.compact == true then
		c.compact = true
	end
	J.lockControls(not c.compact, "stage")
	layout()
	if c.compact then
		K.springIn(chip, 0.9, { amount = 0.15, duration = 0.25 })
	else
		K.springIn(sheet, 0.95, { amount = 0.12, duration = 0.3 })
	end
	startTimer(c)
	if p.resend ~= true then
		pcall(K.sound, "notify")
	end
end

function Stage.round(p: any)
	if current and current.submitted and open and not current.resolved then
		queued = p
		return
	end
	openRound(p)
end

function Stage.result(p: any)
	build()
	local c = current
	if c then
		c.resolved = true
		if c.api and type(c.api.onResult) == "function" then
			pcall(c.api.onResult, p)
		end
	end
	Stage.flash(p.ok == true)
	if p.ok ~= true then
		Stage.shake(7)
	end
	Stage.flashResult(p)
	-- the sheet goes away right away: the world shows the customer leaving / the boss reacting
	task.delay(0.35, function()
		if current == c then
			hideSheet()
		end
		if queued then
			local nxt = queued
			queued = nil
			openRound(nxt)
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Shift summary: side rail (landscape) / bottom sheet (portrait), no dim
-------------------------------------------------------------------------------------------------
local function mmss(sec: number): string
	local s = math.max(0, math.floor(sec))
	return string.format("%d분 %02d초", s // 60, s % 60)
end

function Stage.summary(p: any)
	build()
	queued = nil
	hideSheet()
	if summaryHost then
		summaryHost:Destroy()
		summaryHost = nil
	end
	local m = J.metrics()
	local completed = p.completed == true
	local rows = {}
	local rounds = tonumber(p.rounds) or 0
	table.insert(rows, { if rounds > 0 then "라운드" else "업무", if rounds > 0 then string.format("%d개 · 퍼펙트 %d", rounds, tonumber(p.perfect) or 0) else string.format("%d / %d", tonumber(p.tasks) or 0, tonumber(p.total) or 0) })
	table.insert(rows, { "급여", K.won(tonumber(p.earned) or 0) })
	local bonus = tonumber(p.bonus) or 0
	if bonus > 0 then
		table.insert(rows, { "근무 완료 보너스", "+" .. K.won(bonus), K.Color.green })
	end
	if (tonumber(p.redLights) or 0) > 0 then
		table.insert(rows, { "신호 위반", string.format("%d회 🚦", p.redLights), K.Color.red })
	end
	if (tonumber(p.maxCombo) or 0) > 1 then
		table.insert(rows, { "최대 콤보", string.format("x%d 🔥", p.maxCombo), K.Color.orange })
	end
	table.insert(rows, { "통장 입금", K.won(tonumber(p.paid) or 0), K.Color.gold })
	if p.hourly then
		table.insert(rows, { "시급 환산", K.won(p.hourly) .. "/시간" })
	end
	table.insert(rows, { "근무 시간", mmss(tonumber(p.seconds) or 0) })
	local rowH = 22
	local w = if m.landscape then math.min(320, math.floor(m.W * 0.42)) else m.W - 12
	local headH = 52
	local h = headH + #rows * rowH + 12 + 48 + 10
	local maxH = if m.landscape then m.H - 90 else m.sheetMax
	if h > maxH then
		-- drop the least important rows until it fits
		while h > maxH and #rows > 3 do
			table.remove(rows, #rows)
			h -= rowH
		end
	end
	local host = K.Panel(root, { Name = "Summary", BackgroundTransparency = 0.04, Radius = K.Radius.lg, ZIndex = 40 })
	host.Active = true
	summaryHost = host
	K.stroke(host, if completed then K.Color.gold else K.Color.orange, 1.5, 0.4)
	if m.landscape then
		host.AnchorPoint = Vector2.new(1, 1)
		host.Position = UDim2.new(1, -8, 1, -8)
	else
		host.AnchorPoint = Vector2.new(0.5, 1)
		host.Position = UDim2.new(0.5, 0, 1, -4)
	end
	host.Size = UDim2.fromOffset(w, h)
	K.text(host, { Name = "Icon", Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(32, 32), Text = tostring(p.jobIcon or "💼"), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 41 })
	K.text(host, { Name = "Title", Position = UDim2.fromOffset(52, 8), Size = UDim2.new(1, -64, 0, 22), Text = if completed then "🎉 근무 완료!" else "🏁 " .. tostring(p.reason or "퇴근"), Font = K.Font.heavy, TextSize = K.Type.title2, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 41 })
	K.text(host, { Name = "Sub", Position = UDim2.fromOffset(52, 30), Size = UDim2.new(1, -64, 0, 16), Text = string.format("%s · %s%s", tostring(p.jobTitle or ""), tostring(p.place or ""), if p.boss then " · " .. tostring(p.boss) .. ": 수고했어요!" else ""), TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 41 })
	for i, r in rows do
		local y = headH + (i - 1) * rowH
		K.text(host, { Name = "K" .. i, Position = UDim2.fromOffset(14, y), Size = UDim2.new(0.5, -14, 0, rowH), Text = r[1], TextColor3 = K.Color.sub, TextSize = K.Type.caption + 1, ZIndex = 41 })
		local v = K.text(host, { Name = "V" .. i, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, y), Size = UDim2.new(0.5, -14, 0, rowH), Text = r[2], TextColor3 = r[3] or K.Color.text, Font = K.Font.bold, TextSize = K.Type.bodySm, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 41 })
		K.mono(v)
	end
	local function close()
		if summaryHost == host then
			summaryHost = nil
		end
		K.tween(host, 0.18, { BackgroundTransparency = 1 })
		task.delay(0.2, function()
			if host.Parent then
				host:Destroy()
			end
		end)
	end
	K.Button(host, { name = "Ok", text = "확인", style = if completed then "gold" else "primary", anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, -10), size = UDim2.new(1, -24, 0, 46), zIndex = 42, onClick = close })
	K.springIn(host, 0.92, { amount = 0.15, duration = 0.32 })
	pcall(K.feedback, if completed then "success" else "close")
	task.delay(25, function()
		if summaryHost == host then
			close()
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Close
-------------------------------------------------------------------------------------------------
function Stage.closeRound()
	queued = nil
	if open then
		hideSheet()
	end
end

function Stage.close()
	queued = nil
	hideSheet()
end

-- the World module needs the current round's api (restock slots call back into the builder)
function Stage.currentApi(): any
	return current and current.api or nil
end

return Stage
