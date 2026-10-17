-- GwangalliClinic/Checkup (client): 2층 건강검진센터.
--   접수대 (한선생) → 5 stations, any order, each a small real test (numbers from the server):
--     신장·체중 (height rod slides down, scale display) · 혈압 (cuff + gauge) · 시력 (Landolt C, ↑ ↓ ← →,
--     left / right eye, smaller each row) · 청력 (beeps left / right in 3D sound, press the side you hear) ·
--     심전도 (lying on the bed, live ECG trace)
--   → 결과 상담: 건강검진 결과 통보서 (grade A ~ D stamp, measurements with 판정, 소견, Health 의 조언, 생활
--   권장) · grade D → "1층 내과 바로 접수".

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Checkup = {}

local ctx: any
local S: any
local C: any
local Ui: any
local Col: any
local F: any
local player = Players.LocalPlayer

local stationSheet: any
local reportSheet: any
local running = false

local DIR_ROT = { right = 0, down = 90, left = 180, up = 270 }
local DIR_KEYS = { [Enum.KeyCode.Up] = "up", [Enum.KeyCode.Down] = "down", [Enum.KeyCode.Left] = "left", [Enum.KeyCode.Right] = "right", [Enum.KeyCode.DPadUp] = "up", [Enum.KeyCode.DPadDown] = "down", [Enum.KeyCode.DPadLeft] = "left", [Enum.KeyCode.DPadRight] = "right", [Enum.KeyCode.W] = "up", [Enum.KeyCode.S] = "down", [Enum.KeyCode.A] = "left", [Enum.KeyCode.D] = "right" }

local function stationAlive(id: string): boolean
	local v = ctx.visit
	return v ~= nil and v.chk ~= nil and v.chk.cur ~= nil and v.chk.cur.station == id
end

local function open(title: string, sub: string): Frame
	stationSheet.clear()
	stationSheet.title.Text = title
	stationSheet.sub.Text = sub
	stationSheet.open()
	return stationSheet.body
end

local function finishStation(id: string, result: any?)
	local res = ctx.call("checkup", { action = "station", station = id, result = result or {} }, { quiet = true })
	if res.code == "tooSoon" then
		task.wait(1.2)
		res = ctx.call("checkup", { action = "station", station = id, result = result or {} })
	elseif not res.ok and res.message then
		Ui.toast(res.message, nil, "warn")
	end
	stationSheet.close()
	if res.ok then
		local label = "검사"
		local v = ctx.visit
		for _, st in (v and v.chk and v.chk.stations) or {} do
			if st.id == id then
				label = st.label
			end
		end
		Ui.toast(string.format("✅ %s 검사 완료", label), res.text or "", "ok")
		if (res.left or 0) == 0 then
			Ui.toast("모든 검사가 끝났어요", "접수대로 가서 결과 상담을 받으세요", "info")
		end
	end
end

-------------------------------------------------------------------------------------------------
-- stations
-------------------------------------------------------------------------------------------------
local function heightGame(m: any)
	local b = open("📏 신장 · 체중 측정", "체중계에 바르게 서서 정면을 보세요")
	local box = Ui.card(b, { Size = UDim2.new(1, 0, 0, 220), AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 1 })
	local rod = Ui.new("Frame", { BackgroundColor3 = Col.faint, Position = UDim2.new(0.2, 0, 0, 10), Size = UDim2.new(0, 6, 1, -20) }, box)
	local head = Ui.new("Frame", { BackgroundColor3 = Col.teal, Position = UDim2.new(0.2, -30, 0, 10), Size = UDim2.fromOffset(66, 10) }, box)
	Ui.corner(head, 4)
	local _ = rod
	local hText = Ui.text(box, { Text = "--- cm", Font = F.black, TextSize = 34, Position = UDim2.new(0.4, 0, 0, 40), Size = UDim2.new(0.55, 0, 0, 40) })
	local wText = Ui.text(box, { Text = "--- kg", Font = F.black, TextSize = 26, TextColor3 = Col.sub, Position = UDim2.new(0.4, 0, 0, 90), Size = UDim2.new(0.55, 0, 0, 34) })
	local bText = Ui.text(box, { Text = "", Font = F.bold, TextSize = 16, TextColor3 = Col.tealDD, Position = UDim2.new(0.4, 0, 0, 132), Size = UDim2.new(0.55, 0, 0, 24) })
	Ui.tween(head, 1.6, { Position = UDim2.new(0.2, -30, 0, 50) }, Enum.EasingStyle.Quad)
	local t0 = os.clock()
	while os.clock() - t0 < 1.8 and stationAlive("height") do
		local a = (os.clock() - t0) / 1.8
		hText.Text = string.format("%.1f cm", 100 + (m.height - 100) * a)
		wText.Text = string.format("%.1f kg", m.weight * a)
		task.wait()
	end
	hText.Text = string.format("%.1f cm", m.height)
	wText.Text = string.format("%.1f kg", m.weight)
	local cls, tone = S.Medical.bmiClass(m.bmi)
	bText.Text = string.format("BMI %.1f · %s", m.bmi, cls)
	bText.TextColor3 = Ui.TONE[tone] or Col.tealDD
	Ui.sound("beep")
	task.wait(2.0)
	finishStation("height", {})
end

local function bpGame(m: any)
	local b = open("💓 혈압 측정", "팔을 커프에 끝까지 넣고 편하게 앉아 계세요")
	local box = Ui.card(b, { Size = UDim2.new(1, 0, 0, 180), AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 1 })
	local mm = Ui.text(box, { Text = "0", Font = F.mono, TextSize = 54, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 64), TextXAlignment = Enum.TextXAlignment.Center })
	local sub = Ui.text(box, { Text = "가압 중…", Font = F.bold, TextSize = 16, TextColor3 = Col.sub, Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center })
	local t0 = os.clock()
	while os.clock() - t0 < 1.6 and stationAlive("bp") do
		mm.Text = tostring(math.floor(190 * (os.clock() - t0) / 1.6))
		task.wait()
	end
	sub.Text = "측정 중… 움직이지 마세요"
	t0 = os.clock()
	while os.clock() - t0 < 1.8 and stationAlive("bp") do
		mm.Text = tostring(math.floor(190 - (190 - m.d) * (os.clock() - t0) / 1.8))
		task.wait()
	end
	local cls, tone = S.Medical.bpClass(m.s, m.d)
	mm.Text = string.format("%d / %d", m.s, m.d)
	mm.TextColor3 = Ui.TONE[tone] or Col.ink
	sub.Text = string.format("맥박 %d회/분 · %s", m.p, cls)
	Ui.sound("beep")
	task.wait(1.6)
	finishStation("bp", {})
end

local function eyeGame(ch: any)
	local b = open("👁️ 시력 검사", "C 의 뚫린 쪽을 고르세요 (방향키 · D-패드도 돼요)")
	local info = Ui.text(b, { Text = "", Font = F.black, TextSize = 15, TextColor3 = Col.tealDD, LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Center })
	local board = Ui.card(b, { Size = UDim2.new(1, 0, 0, 190), AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 2 })
	local cLabel = Ui.text(board, { Text = "C", Font = Enum.Font.GothamBold, TextSize = 120, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(170, 170), TextXAlignment = Enum.TextXAlignment.Center })
	local pad = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 120), LayoutOrder = 3 }, b)
	local answers = {}
	local idx = 1
	local picked: string? = nil
	local function btn(text: string, dir: string, pos: UDim2)
		return Ui.btn(pad, { text = text, style = "secondary", size = UDim2.fromOffset(64, 52), pos = pos, anchor = Vector2.new(0.5, 0.5), textSize = 22, onClick = function()
			picked = dir
		end })
	end
	local up = btn("↑", "up", UDim2.new(0.5, 0, 0, 28))
	btn("↓", "down", UDim2.new(0.5, 0, 0, 90))
	btn("←", "left", UDim2.new(0.5, -74, 0, 60))
	btn("→", "right", UDim2.new(0.5, 74, 0, 60))
	stationSheet.focus = up
	Ui.select(up)
	local conn = UserInputService.InputBegan:Connect(function(io, gp)
		local d = DIR_KEYS[io.KeyCode]
		if d and (not gp or io.KeyCode.Name:find("DPad")) then
			picked = d
		end
	end)
	while idx <= #ch.seq and stationAlive("eye") and stationSheet.isOpen do
		local item = ch.seq[idx]
		info.Text = string.format("%s 눈 · 시력표 %.1f 줄 (%d/%d)", if item.eye == "l" then "왼쪽" else "오른쪽", item.v, idx, #ch.seq)
		cLabel.Rotation = DIR_ROT[item.dir] or 0
		cLabel.TextSize = math.floor(130 - (item.row - 1) * 17)
		picked = nil
		while picked == nil and stationAlive("eye") and stationSheet.isOpen do
			task.wait(0.03)
		end
		if picked then
			answers[idx] = picked
			Ui.sound(if picked == item.dir then "tap" else "error")
			idx += 1
		end
	end
	conn:Disconnect()
	if idx > #ch.seq then
		finishStation("eye", { answers = answers })
	end
end

local function tone(side: string, freq: string)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local p = Instance.new("Part")
	p.Name = "EarTone"
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CFrame = cam.CFrame * CFrame.new(if side == "L" then -5 else 5, 0, 0)
	local speed = ({ ["500Hz"] = 0.7, ["1000Hz"] = 1.0, ["2000Hz"] = 1.4, ["4000Hz"] = 1.9 })[freq] or 1.0
	local s = Instance.new("Sound")
	s.SoundId = C.Sounds.Ding
	s.Volume = 0.55
	s.PlaybackSpeed = speed
	s.RollOffMinDistance = 2
	s.RollOffMaxDistance = 40
	s.Parent = p
	p.Parent = ctx.Tracker.localFolder()
	s:Play()
	task.delay(2, function()
		p:Destroy()
	end)
end

local function earGame(ch: any)
	local b = open("🎧 청력 검사", "헤드폰에서 '삐-' 소리가 들리면 들린 쪽을 누르세요")
	local info = Ui.text(b, { Text = "준비…", Font = F.black, TextSize = 16, TextColor3 = Col.tealDD, LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Center })
	local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 70), LayoutOrder = 2 }, b)
	local current = 0
	local answers = {}
	local function press(side: string)
		if current > 0 then
			answers[current] = side
			Ui.sound("tap")
		end
	end
	local l = Ui.btn(row, { text = "◀ 왼쪽", style = "primary", size = UDim2.new(0.5, -6, 1, 0), textSize = 18, sound = false, onClick = function()
		press("L")
	end })
	Ui.btn(row, { text = "오른쪽 ▶", style = "primary", size = UDim2.new(0.5, -6, 1, 0), pos = UDim2.new(0.5, 6, 0, 0), textSize = 18, sound = false, onClick = function()
		press("R")
	end })
	Ui.text(b, { Text = "헤드폰이나 이어폰을 끼면 더 정확해요", Font = F.med, TextSize = 12, TextColor3 = Col.faint, LayoutOrder = 3, TextXAlignment = Enum.TextXAlignment.Center })
	stationSheet.focus = l
	local conn = UserInputService.InputBegan:Connect(function(io, _gp)
		if io.KeyCode == Enum.KeyCode.Left or io.KeyCode == Enum.KeyCode.A or io.KeyCode == Enum.KeyCode.ButtonL1 then
			press("L")
		elseif io.KeyCode == Enum.KeyCode.Right or io.KeyCode == Enum.KeyCode.D or io.KeyCode == Enum.KeyCode.ButtonR1 then
			press("R")
		end
	end)
	task.wait(1.0)
	for i, t in ch.tones do
		if not stationAlive("ear") or not stationSheet.isOpen then
			break
		end
		task.wait(t.gap)
		current = i
		info.Text = string.format("신호음 %d / %d", i, #ch.tones)
		tone(t.ear, t.freq)
	end
	task.wait(1.6)
	conn:Disconnect()
	if stationAlive("ear") and stationSheet.isOpen then
		finishStation("ear", { answers = answers })
	end
end

local function ecgGame(m: any)
	local b = open("📈 심전도 검사", "편하게 누워 계세요 · 움직이면 파형이 흔들려요")
	local box = Ui.new("Frame", { BackgroundColor3 = Color3.fromRGB(8, 24, 20), Size = UDim2.new(1, 0, 0, 170), LayoutOrder = 1, ClipsDescendants = true }, b)
	Ui.corner(box, 10)
	local rate = Ui.text(box, { Text = string.format("♥ %d bpm", m.rate or 72), Font = F.black, TextSize = 18, TextColor3 = Color3.fromRGB(110, 255, 160), Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 22), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 })
	local _ = rate
	local dots = {}
	local N = 90
	for i = 1, N do
		local d = Ui.new("Frame", { BackgroundColor3 = Color3.fromRGB(110, 255, 160), BorderSizePixel = 0, Size = UDim2.fromOffset(3, 3), Position = UDim2.fromScale((i - 1) / N, 0.6), ZIndex = 2 }, box)
		dots[i] = d
	end
	local bpm = m.rate or 72
	local t0 = os.clock()
	local function wave(ph: number): number
		-- P, QRS, T shape over one beat (0..1)
		if ph < 0.1 then
			return 0.08 * math.sin(ph / 0.1 * math.pi)
		elseif ph < 0.16 then
			return 0
		elseif ph < 0.18 then
			return -0.12
		elseif ph < 0.21 then
			return 0.9
		elseif ph < 0.24 then
			return -0.25
		elseif ph < 0.4 then
			return 0
		elseif ph < 0.55 then
			return 0.18 * math.sin((ph - 0.4) / 0.15 * math.pi)
		end
		return 0
	end
	local conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		for i, d in dots do
			local x = (i - 1) / N
			local time = t - (1 - x) * 2.5
			local ph = (time * bpm / 60) % 1
			d.Position = UDim2.fromScale(x, 0.62 - wave(ph) * 0.45)
		end
	end)
	local wait0 = os.clock()
	while os.clock() - wait0 < 4.2 and stationAlive("ecg") and stationSheet.isOpen do
		task.wait(0.1)
	end
	conn:Disconnect()
	Ui.text(b, { Text = "판독 · " .. (m.rhythm or "정상 동리듬"), Font = F.black, TextSize = 15, TextColor3 = if (m.rhythm or "") == "정상 동리듬" then Col.green else Col.orange, LayoutOrder = 2 })
	task.wait(1.2)
	if stationAlive("ecg") then
		finishStation("ecg", {})
	end
end

function Checkup.station(id: any)
	if running or type(id) ~= "string" then
		return
	end
	running = true
	local ok, err = pcall(function()
		local res = ctx.call("checkup", { action = "begin", station = id })
		if not res.ok then
			return
		end
		if id == "height" then
			heightGame(res.measure)
		elseif id == "bp" then
			bpGame(res.measure)
		elseif id == "eye" then
			eyeGame(res.challenge)
		elseif id == "ear" then
			earGame(res.challenge)
		elseif id == "ecg" then
			ecgGame(res.measure)
		end
	end)
	if not ok then
		warn("[GwangalliClinic] station:", err)
	end
	running = false
end

-------------------------------------------------------------------------------------------------
-- desk + report
-------------------------------------------------------------------------------------------------
local function showReport(r: any)
	reportSheet.clear()
	reportSheet.title.Text = "건강검진 결과 통보서"
	reportSheet.sub.Text = string.format("%s · %s · %s", r.no or "", r.patient or "", r.date or "")
	local b = reportSheet.body
	local g = S.Medical.GRADES[r.grade or "A"] or S.Medical.GRADES.A
	local gc = Color3.fromRGB(g.color[1], g.color[2], g.color[3])
	local top = Ui.paper(b, { LayoutOrder = 1 })
	Ui.text(top, { Text = C.Venue.Name .. " 건강검진센터", Font = F.black, TextSize = 15, TextColor3 = Col.tealDD, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	local gradeRow = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 76), LayoutOrder = 2 }, top)
	local stamp = Ui.text(gradeRow, { Text = r.grade or "A", Font = F.black, TextSize = 46, TextColor3 = gc, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.fromOffset(70, 70), TextXAlignment = Enum.TextXAlignment.Center, Rotation = -8 })
	Ui.stroke(stamp, gc, 3, 0).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	Ui.corner(stamp, 35)
	Ui.text(gradeRow, { Text = "종합 판정 · " .. g.label, Font = F.black, TextSize = 18, TextColor3 = gc, Position = UDim2.fromOffset(92, 12), Size = UDim2.new(1, -92, 0, 26) })
	Ui.text(gradeRow, { Text = g.sub, Font = F.med, TextSize = 13, TextColor3 = Col.sub, Position = UDim2.fromOffset(92, 40), Size = UDim2.new(1, -92, 0, 20) })
	local t = Ui.paper(b, { LayoutOrder = 2 })
	Ui.text(t, { Text = "검사 결과", Font = F.black, TextSize = 14, LayoutOrder = 0 })
	local function line(order: number, name: string, value: string, judge: string, tone: string?)
		local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order }, t)
		Ui.text(row, { Text = name, Font = F.med, TextSize = 13, TextColor3 = Col.sub, Size = UDim2.new(0.3, 0, 1, 0) })
		Ui.text(row, { Text = value, Font = F.bold, TextSize = 13, Size = UDim2.new(0.42, 0, 1, 0), Position = UDim2.fromScale(0.3, 0) })
		Ui.text(row, { Text = judge, Font = F.black, TextSize = 13, TextColor3 = Ui.TONE[tone or "ok"] or Col.green, Size = UDim2.new(0.28, 0, 1, 0), Position = UDim2.fromScale(0.72, 0), TextXAlignment = Enum.TextXAlignment.Right })
	end
	if r.height then
		local cls, tone = S.Medical.bmiClass(r.bmi or 22)
		line(1, "신장 · 체중", string.format("%.1fcm · %.1fkg", r.height, r.weight or 0), "", nil)
		line(2, "체질량지수", string.format("BMI %.1f", r.bmi or 0), cls, tone)
	end
	if r.bp then
		local cls, tone = S.Medical.bpClass(r.bp.s, r.bp.d)
		line(3, "혈압", string.format("%d/%d mmHg", r.bp.s, r.bp.d), cls, tone)
	end
	if r.vision then
		local low = r.vision.l < 0.6 or r.vision.r < 0.6
		line(4, "시력 (좌/우)", string.format("%.1f / %.1f", r.vision.l, r.vision.r), if low then "저하" else "정상", if low then "warn" else "ok")
	end
	if r.hearing then
		local bad = r.hearing.l == false or r.hearing.r == false
		line(5, "청력 (좌/우)", string.format("%s / %s", if r.hearing.l then "정상" else "저하", if r.hearing.r then "정상" else "저하"), if bad then "재검" else "정상", if bad then "warn" else "ok")
	end
	if r.ecg then
		line(6, "심전도", string.format("%s", r.ecg), if r.ecg == "정상 동리듬" then "정상" else "주의", if r.ecg == "정상 동리듬" then "ok" else "warn")
	end
	line(7, "피로도", string.format("%d / 100", r.fatigue or 0), if (r.fatigue or 0) >= 75 then "과로" elseif (r.fatigue or 0) >= 50 then "피로" else "양호", if (r.fatigue or 0) >= 75 then "bad" elseif (r.fatigue or 0) >= 50 then "warn" else "ok")
	line(8, "질병 위험도", string.format("%d%%", r.riskPct or 0), if (r.riskPct or 0) >= 50 then "주의" else "양호", if (r.riskPct or 0) >= 50 then "warn" else "ok")
	if r.illName then
		line(9, "현재 질병", r.illName, "진료 필요", "bad")
	end
	local n = Ui.paper(b, { LayoutOrder = 3 })
	Ui.text(n, { Text = "소견", Font = F.black, TextSize = 14, LayoutOrder = 0 })
	for i, note in r.notes or {} do
		Ui.text(n, { Text = "· " .. note, Font = F.med, TextSize = 13, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i })
	end
	if r.advice then
		Ui.text(n, { Text = "의사 소견 · " .. r.advice, Font = F.bold, TextSize = 13, TextColor3 = Col.tealDD, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 20 })
	end
	for i, tip in r.tips or {} do
		Ui.text(n, { Text = tip, Font = F.med, TextSize = 12, TextColor3 = Col.sub, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 30 + i })
	end
	if r.grade == "D" and r.ill then
		Ui.btn(b, { text = "🩺 1층 내과 바로 접수 (우선 순서)", style = "danger", size = UDim2.new(1, 0, 0, 50), order = 8, onClick = function()
			local res = ctx.call("checkup", { action = "refer" })
			if res.ok then
				reportSheet.close()
				Ui.toast("내과 진료 대기에 올렸어요", "1층 진료실 앞에서 호출을 기다려 주세요", "ok")
			end
		end })
	end
	Ui.btn(b, { text = "확인", style = "primary", size = UDim2.new(1, 0, 0, 48), order = 9, onClick = function()
		reportSheet.close()
	end })
	reportSheet.open()
end
Checkup.showReport = showReport

function Checkup.desk()
	local v = ctx.visit
	if v and v.step == "chk_result" then
		Ui.say("check", "검사 결과 나왔어요. 하나씩 설명해 드릴게요.", { name = C.Staff.check.name })
		local res = ctx.call("checkup", { action = "finish" })
		if res.ok and res.report then
			ctx.report = res.report
			showReport(res.report)
		end
		return
	end
	if not v then
		local H = ctx.fees or {}
		local pick = Ui.ask("check", string.format("건강검진 받으시겠어요? 신장·체중 · 혈압 · 시력 · 청력 · 심전도 다섯 가지예요. 검진비 %s은 결과 상담 때 결제돼요.", S.won(H.checkup or 10000)), { "네, 받을게요", "다음에요" }, { name = C.Staff.check.name })
		if pick ~= 1 then
			Ui.hideDialog()
			return
		end
	end
	local res = ctx.call("checkup", { action = "start" })
	if res.ok then
		Ui.toast("건강검진 시작", "트래커의 순서대로 아무 검사부터 받으세요", "info")
	end
end

function Checkup.onReport(r: any)
	if r and not reportSheet.isOpen then
		ctx.report = r
		showReport(r)
	end
end

function Checkup.init(c: any)
	ctx = c
	S = c.S
	C = c.C
	Ui = c.Ui
	Col = Ui.C
	F = Ui.F
	stationSheet = Ui.sheet("GwClinic_Station", { title = "검사", w = 460, h = 520, scroll = true, sticky = true })
	reportSheet = Ui.sheet("GwClinic_Report", { title = "건강검진 결과 통보서", w = 560, h = 680 })
	local _ = player
end

return Checkup
