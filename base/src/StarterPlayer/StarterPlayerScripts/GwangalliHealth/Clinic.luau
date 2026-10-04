-- GwangalliHealth/Clinic: the hospital UI (광안 메디컬 의원), opened by the server's HealthEvent "clinic"
-- (ProximityPrompt "진료 받기" on the doctor / "접수하기" at the desk). A kit BottomSheet (right side on
-- landscape, bottom on portrait) with a status card (fatigue bar, pay multiplier, illness pill) and
-- rows: 진료 받기 (when ill) / 영양주사 / 건강검진. Each row -> K.confirm with the fee and balance ->
-- HealthRequest op -> the server runs the choreography and fires cured / vitamin / checkup.
-- Modal while open: HideGwangalliHUD + touch controls off (ctx.modal).

local Clinic = {}

local ctx: any
local K: any
local HS: any
local G: any
local sheet: any = nil
local status: any = nil
local rows: { [string]: any } = {}
local card: any = nil
local busy = false
local setRowsActive: (on: boolean) -> ()

-- one glyph per icon tile: cut a ZWJ emoji sequence (😵‍💫) down to its first emoji (😵)
local function simpleEmoji(s: any): string
	if type(s) ~= "string" or s == "" then
		return "🤒"
	end
	local cut = string.find(s, "\u{200D}", 1, true)
	return if cut then string.sub(s, 1, cut - 1) else s
end

local function won(n: any): string
	return K.won(n)
end

local function tierColor(st: any): Color3
	if st.illness then
		return K.Color.red
	end
	local c = HS.fatigueColor(st.fatigue or 0)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function landscape(): boolean
	local gui = ctx.gui
	return gui.AbsoluteSize.X > gui.AbsoluteSize.Y * 1.25
end

-------------------------------------------------------------------------------------------------
-- Sheet
-------------------------------------------------------------------------------------------------
local function buildSheet()
	local gui = ctx.gui
	local side = if landscape() then "right" else "bottom"
	local s = K.BottomSheet(gui, {
		name = "ClinicSheet",
		title = HS.H().name or "광안 메디컬 의원",
		subtitle = "접수 · 진료 · 영양주사 · 건강검진",
		side = side,
		width = if side == "right" then 0.46 else nil,
		height = if side == "bottom" then 0.72 else nil,
		zIndex = 40,
		onClose = function()
			ctx.modal(false)
		end,
	})
	local content = s.content :: Frame
	local scroll = K.make("ScrollingFrame", {
		Name = "Scroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.5,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 42,
	}, content)
	K.list(scroll, false, 8)
	K.pad(scroll, 0, 6, 2, 8)

	-- status card
	local c = K.Card(scroll, { Name = "Status", Size = UDim2.new(1, 0, 0, 76), LayoutOrder = 1, ZIndex = 42 })
	local tile = K.iconTile(c, 40, "😩", K.Color.orange, true)
	tile.AnchorPoint = Vector2.new(0, 0.5)
	tile.Position = UDim2.new(0, 12, 0.5, 0)
	for _, d in tile:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 44
		end
	end
	tile.ZIndex = 43
	local title = K.text(c, { Name = "Title", Position = UDim2.fromOffset(62, 10), Size = UDim2.new(1, -74, 0, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.body, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 43 })
	local sub = K.text(c, { Name = "Sub", Position = UDim2.fromOffset(62, 32), Size = UDim2.new(1, -74, 0, 16), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 43 })
	local bar = K.ProgressBar(c, { height = 6, color = K.Color.orange })
	bar.frame.AnchorPoint = Vector2.new(0, 1)
	bar.frame.Position = UDim2.new(0, 62, 1, -12)
	bar.frame.Size = UDim2.new(1, -74, 0, 6)
	bar.frame.ZIndex = 43
	bar.fill.ZIndex = 44
	local pill = K.Pill(c, { text = "", color = K.Color.red, name = "IllPill" })
	pill.AnchorPoint = Vector2.new(1, 0)
	pill.Position = UDim2.new(1, -12, 0, 10)
	pill.ZIndex = 44
	pill.Visible = false
	card = { frame = c, tile = tile, glyph = tile:FindFirstChild("Glyph"), title = title, sub = sub, bar = bar, pill = pill }

	-- rows
	local function row(id: string, order: number, icon: string, color: Color3, titleText: string, subText: string, onClick: () -> ())
		local r = K.ListRow(scroll, { name = "Row_" .. id, icon = icon, iconColor = color, title = titleText, subtitle = subText, trailing = "", trailingWidth = 96, chevron = true, height = 60, order = order, onClick = onClick })
		r.row.ZIndex = 42
		for _, d in r.row:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = math.max(d.ZIndex, 43)
			end
		end
		rows[id] = r
		return r
	end
	row("treat", 2, "🩹", K.Color.red, "진료 받기", "", function()
		Clinic.ask("treat")
	end)
	row("vitamin", 3, "💉", K.Color.cyan, HS.H().services.vitamin.name, HS.H().services.vitamin.desc, function()
		Clinic.ask("vitamin")
	end)
	row("checkup", 4, "🩺", K.Color.violet, HS.H().services.checkup.name, HS.H().services.checkup.desc, function()
		Clinic.ask("checkup")
	end)
	-- hint + close
	K.text(scroll, { Name = "Hint", Size = UDim2.new(1, 0, 0, 30), Text = "진료비는 통장에서 먼저, 부족하면 현금으로 결제돼요", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 8, ZIndex = 43 })
	local close = K.Button(scroll, { name = "CloseButton", text = "나가기", style = "secondary", order = 9, zIndex = 43 })
	close.Activated:Connect(function()
		Clinic.close()
	end)
	sheet = s
	sheet.side = side
end

local function refresh()
	if not card or not status then
		return
	end
	local st = status
	local H = HS.H()
	local color = tierColor(st)
	local fatigue = st.fatigue or 0
	local mult = st.mult or 1
	if st.illness then
		card.glyph.Text = simpleEmoji(st.illness.icon or "🤒")
		card.title.Text = string.format("%s 진단 · 급여 %d%%", st.illness.name, math.floor(mult * 100 + 0.5))
		card.sub.Text = string.format("피로도 %d · %s", fatigue, st.illness.desc or "")
		card.pill.Visible = true
		card.pill.Text = string.format("%s %d분째", st.illness.icon or "", st.illness.minutes or 0)
		card.pill.Size = UDim2.fromOffset(math.ceil(K.textSize(card.pill.Text, K.Type.micro, K.Font.bold).X) + 16, 22)
		rows.treat.row.Visible = true
		rows.treat.title.Text = string.format("진료 받기 · %s", st.illness.name)
		rows.treat.subtitle.Text = st.illness.cure or "치료"
		rows.treat.trailing.Text = won(st.illness.fee)
	else
		card.glyph.Text = if fatigue >= 50 then "😩" else "😊"
		local label = if (st.tierLabel or "") ~= "" then st.tierLabel else "건강"
		card.title.Text = string.format("%s · 급여 %d%%", label, math.floor(mult * 100 + 0.5))
		card.sub.Text = string.format("피로도 %d / 100 · 질병 위험 %d%%", fatigue, math.floor(100 * (st.risk or 0) / math.max(1, st.riskThreshold or 25) + 0.5))
		card.pill.Visible = false
		rows.treat.row.Visible = false
	end
	local grad = card.tile:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(K.shade(color, -0.08, 0.12), K.shade(color, 0.1, -0.22))
	end
	card.bar.setColor(color)
	card.bar.set(fatigue / 100)
	local debt = st.debt or 0
	rows.vitamin.trailing.Text = won((st.fees and st.fees.vitamin or H.services.vitamin.fee) + debt)
	rows.checkup.trailing.Text = won((st.fees and st.fees.checkup or H.services.checkup.fee) + debt)
	rows.vitamin.subtitle.Text = if fatigue < 5 then "지금은 피로가 거의 없어요" else H.services.vitamin.desc
	if debt > 0 then
		rows.checkup.subtitle.Text = string.format("미납 진료비 %s 포함", won(debt))
	end
end

-------------------------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------------------------
function Clinic.setStatus(st: any)
	if type(st) == "table" then
		status = st
		refresh()
	end
end

function Clinic.open(payload: any)
	if not sheet or (sheet.side == "right") ~= landscape() then
		if sheet then
			pcall(sheet.close, true)
			if sheet.frame then
				sheet.frame:Destroy()
			end
			if sheet.dim then
				sheet.dim:Destroy()
			end
			sheet = nil
			rows = {}
			card = nil
		end
		buildSheet()
	end
	if type(payload) == "table" and type(payload.status) == "table" then
		status = payload.status
	end
	refresh()
	setRowsActive(true)
	ctx.modal(true)
	sheet.open()
	-- stagger the rows in
	local list = {}
	for _, id in { "treat", "vitamin", "checkup" } do
		if rows[id] and rows[id].row.Visible then
			table.insert(list, rows[id].row)
		end
	end
	pcall(K.stagger, list)
end

-- rows ignore taps while a request is in flight (and come back afterwards: the sheet is reused)
setRowsActive = function(on: boolean)
	for _, id in { "treat", "vitamin", "checkup" } do
		local r = rows[id]
		if r and r.row then
			r.row.Active = on
		end
	end
end

function Clinic.close()
	if sheet and sheet.isOpen() then
		sheet.close()
	else
		ctx.modal(false)
	end
end

function Clinic.isOpen(): boolean
	return sheet ~= nil and sheet.isOpen()
end

local function fail(res: any)
	ctx.toast({ kind = "warn", title = "광안메디컬", body = (type(res) == "table" and res.message) or "잠시 후 다시 시도해 주세요" })
	pcall(K.feedback, "error")
end

-- confirm dialog -> remote call
function Clinic.ask(op: string)
	if busy or not status then
		return
	end
	local H = HS.H()
	local st = status
	local debt = st.debt or 0
	local title, body, fee, icon, color
	if op == "treat" then
		if not st.illness then
			return
		end
		title = string.format("%s 치료", st.illness.name)
		body = string.format("%s · 치료 후 피로도 -%d, 행복 +5", st.illness.cure or "치료", H.fatigue.cured)
		fee = st.illness.fee
		icon = st.illness.icon
		color = K.Color.red
	elseif op == "vitamin" then
		title = H.services.vitamin.name
		body = string.format("처치실에서 바로 맞아요 · 피로도 -%d, 체력 +10", H.fatigue.vitamin)
		fee = (st.fees and st.fees.vitamin or H.services.vitamin.fee) + debt
		icon = "💉"
		color = K.Color.cyan
	else
		title = H.services.checkup.name
		body = "피로도 · 질병 위험도 · 능력치 리포트와 의사 선생님 조언"
		fee = (st.fees and st.fees.checkup or H.services.checkup.fee) + debt
		icon = "🩺"
		color = K.Color.violet
	end
	local bank = ctx.player:GetAttribute(G.Attr.Bank) or 0
	local cash = ctx.player:GetAttribute(G.Attr.Money) or 0
	local details = { { "진료비", won(fee), color }, { "통장", won(bank) }, { "현금", won(cash) } }
	if debt > 0 then
		table.insert(details, 2, { "미납금 포함", won(debt), K.Color.orange })
	end
	K.confirm(ctx.gui, {
		title = title,
		body = body,
		icon = icon,
		iconColor = color,
		details = details,
		confirmText = "결제하고 진행",
		cancelText = "취소",
		zIndex = 70,
		onConfirm = function()
			if busy then
				return
			end
			busy = true
			setRowsActive(false)
			task.spawn(function()
				local res = ctx.call(op, {})
				busy = false
				setRowsActive(true)
				if type(res) ~= "table" or not res.ok then
					fail(res)
					return
				end
				if op == "checkup" then
					if sheet then
						sheet.close(true)
					end
					Clinic.showReport(res.status, res.advice, res.fee)
				else
					if sheet then
						sheet.close(true)
					end
					ctx.toast({ kind = "info", title = "진료 시작", body = string.format("%s 진행 중… 침대에 앉아 주세요 (%s)", res.name or title, won(res.fee or fee)) })
					pcall(K.feedback, "money")
				end
			end)
		end,
	})
end

-------------------------------------------------------------------------------------------------
-- 건강검진 report
-------------------------------------------------------------------------------------------------
function Clinic.showReport(st: any, advice: string?, fee: number?)
	if type(st) ~= "table" then
		return
	end
	status = st
	local stats = st.stats or {}
	-- compact rows (a landscape phone is only ~390 px tall: 6-7 rows + a one-line body fit)
	local details = {}
	local fc = tierColor(st)
	if st.illness then
		table.insert(details, { "진단", st.illness.name, K.Color.red })
	end
	table.insert(details, { "피로도", string.format("%d / 100%s", st.fatigue or 0, if (st.tierLabel or "") ~= "" then " · " .. st.tierLabel else " · 건강"), fc })
	table.insert(details, { "질병 위험", string.format("%d%%", math.floor(100 * (st.risk or 0) / math.max(1, st.riskThreshold or 25) + 0.5)), if (st.risk or 0) > 0 then K.Color.orange else K.Color.green })
	table.insert(details, { "급여 배율", string.format("%d%%", math.floor((st.mult or 1) * 100 + 0.5)), if (st.mult or 1) < 0.999 then K.Color.orange else K.Color.green })
	table.insert(details, { "체력 · 행복", string.format("%d · %d", stats.stamina or 0, stats.happiness or 0) })
	table.insert(details, { "외모 · 근력 · 인기", string.format("%d · %d · %d", stats.appearance or 0, stats.strength or 0, stats.popularity or 0) })
	if fee then
		table.insert(details, { "검진비", won(fee) .. " 결제", K.Color.sub })
	end
	-- the touch controls stay off while the report is up (the sheet released them when it closed)
	ctx.modal(true)
	local released = false
	local function release()
		if not released then
			released = true
			ctx.modal(false)
		end
	end
	K.Modal(ctx.gui, {
		title = "건강검진 결과 🩺",
		body = advice or HS.adviceFor(st),
		icon = "🩺",
		iconColor = K.Color.violet,
		details = details,
		width = 340,
		zIndex = 70,
		onDismiss = release,
		buttons = { { text = "확인", style = "primary", onClick = release } },
	})
	pcall(K.feedback, "success")
end

function Clinic.init(c: any)
	ctx = c
	K = c.K
	HS = c.HS
	G = c.G
	ctx.on("event:clinic", function(p: any)
		Clinic.open(p)
	end)
	ctx.on("event:status", function(p: any)
		Clinic.setStatus(p.status)
	end)
	ctx.on("event:cured", function(p: any)
		Clinic.setStatus(p.status)
	end)
	ctx.on("event:vitamin", function(p: any)
		Clinic.setStatus(p.status)
	end)
	ctx.on("event:checkup", function(p: any)
		Clinic.setStatus(p.status)
	end)
	ctx.on("event:ill", function(p: any)
		Clinic.setStatus(p.status)
	end)
	ctx.on("event:woke", function(p: any)
		Clinic.setStatus(p.status)
	end)
	-- ask the server once at start so the sheet opens with fresh numbers even before any event
	task.spawn(function()
		task.wait(4)
		local res = ctx.call("status", {}, 6)
		if type(res) == "table" and res.ok then
			Clinic.setStatus(res.status)
		end
	end)
end

return Clinic
