-- GwangalliClinic/Consult (client): 진료실 1 · 내과 (김선생).
--   camera framing over the patient's shoulder · doctor dialogue tied to the real illness (문진: the 문진표
--   symptoms, the work log) · 진찰 mini-sequence, each step validated by the server in order:
--     temp 귀 체온계 (count-up) · throat "아~" (hold) · stetho 숨 들이쉬기/내쉬기 (hold ×2) · bp 커프 펌프 (tap) +
--     게이지 · palp 복부 촉진 (tap 3 points) · talk 생활 문진
--   → 활력징후 패널 (numbers from the server: fatigue / illness) → 진단 카드 (상병명 · KCD · 소견 · 원인 · 건강 상태 ·
--   권장 조치) → 치료 계획 (price = what Health / the 수납 will charge, effects, 잔액 부족)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Consult = {}

local ctx: any
local S: any
local C: any
local Ui: any
local Col: any
local F: any
local player = Players.LocalPlayer

local running = false
local runToken = 0
local panel: Frame -- minigame panel
local vitalsCard: Frame
local tiles: { [string]: TextLabel } = {}
local dxSheet: any
local planSheet: any
local savedCam: any = nil

local function alive(token: number): boolean
	local v = ctx.visit
	return token == runToken and v ~= nil and v.step == "consult"
end

-------------------------------------------------------------------------------------------------
-- camera
-------------------------------------------------------------------------------------------------
local function frameCamera(on: boolean)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if on then
		if savedCam then
			return
		end
		savedCam = { type = cam.CameraType }
		local spec = S.Sites.CONSULT_CAM
		cam.CameraType = Enum.CameraType.Scriptable
		Ui.tween(cam, 0.8, { CFrame = CFrame.lookAt(spec.eye, spec.focus) }, Enum.EasingStyle.Sine)
	else
		if not savedCam then
			return
		end
		cam.CameraType = if savedCam.type == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedCam.type
		savedCam = nil
	end
end

-------------------------------------------------------------------------------------------------
-- vitals panel
-------------------------------------------------------------------------------------------------
local TILE_ORDER = { "temp", "bp", "pulse", "spo2", "lung", "throat", "belly", "talk" }
local TILE_LABEL = { temp = "체온", bp = "혈압", pulse = "맥박", spo2 = "산소포화도", lung = "청진", throat = "인후", belly = "복부", talk = "생활" }

local function buildVitals()
	for _, c in vitalsCard:GetChildren() do
		if c:IsA("Frame") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	tiles = {}
	Ui.text(vitalsCard, { Text = "🩺 진찰 기록", Font = F.black, TextSize = 14, TextColor3 = Col.tealDD, LayoutOrder = 0 })
	for i, id in TILE_ORDER do
		local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, Visible = false }, vitalsCard)
		Ui.text(row, { Text = TILE_LABEL[id], Font = F.med, TextSize = 12, TextColor3 = Col.sub, Size = UDim2.new(0, 72, 0, 18) })
		local val = Ui.text(row, { Text = "", Font = F.black, TextSize = 13, Position = UDim2.fromOffset(74, 0), Size = UDim2.new(1, -74, 0, 18), TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
		tiles[id] = val
	end
end

local function toneColor(t: string?): Color3
	return if t == "bad" then Col.red elseif t == "warn" then Col.orange else Col.green
end

local function setTile(id: string, text: string, tone: string?)
	local l = tiles[id]
	if not l then
		return
	end
	l.Text = text
	l.TextColor3 = if tone then toneColor(tone) else Col.ink
	if l.Parent then
		(l.Parent :: Frame).Visible = true
	end
end

local function showResult(kind: string, r: any)
	if kind == "temp" and r.temp then
		setTile("temp", string.format("%.1f℃ · %s", r.temp, r.tempClass or ""), r.tempTone)
	elseif kind == "bp" and r.sys then
		setTile("bp", string.format("%d/%d mmHg · %s", r.sys, r.dia, r.bpClass or ""), r.bpTone)
		setTile("pulse", string.format("%d회/분", r.pulse), if r.pulse > 100 then "bad" elseif r.pulse > 90 then "warn" else "ok")
		setTile("spo2", string.format("%d%%", r.spo2), if r.spo2 < 96 then "warn" else "ok")
	elseif kind == "stetho" and r.lung then
		setTile("lung", r.lung, if string.find(r.lung, "가래") or string.find(r.lung, "얕") then "warn" else "ok")
	elseif kind == "throat" and r.throat then
		setTile("throat", r.throat, if r.throat == "정상" then "ok" else "warn")
	elseif kind == "palp" and r.belly then
		setTile("belly", r.belly, if r.belly == "압통 없음" then "ok" else "bad")
	elseif kind == "talk" and r.talk then
		setTile("talk", r.talk, nil)
	end
end

-------------------------------------------------------------------------------------------------
-- minigames (flavour; the numbers come from the server)
-------------------------------------------------------------------------------------------------
local function clearPanel()
	for _, c in panel:GetChildren() do
		if not c:IsA("UICorner") and not c:IsA("UIStroke") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function openPanel(title: string): Frame
	clearPanel()
	panel.Visible = true
	Ui.text(panel, { Text = title, Font = F.black, TextSize = 16, TextColor3 = Col.tealDD, Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	local body = Ui.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -28) }, panel)
	return body
end

-- hold the button for `secs`; returns true when completed (nil when aborted)
local function holdButton(body: Frame, label: string, secs: number, token: number): boolean
	local b = Ui.btn(body, { text = label, style = "primary", size = UDim2.new(0.8, 0, 0, 56), pos = UDim2.new(0.5, 0, 1, -6), anchor = Vector2.new(0.5, 1), textSize = 17, sound = false })
	local bar = Ui.bar(body, { h = 12 })
	bar.frame.Position = UDim2.new(0.1, 0, 0, 6)
	bar.frame.Size = UDim2.new(0.8, 0, 0, 12)
	local holding = false
	local held = 0
	b.MouseButton1Down:Connect(function()
		holding = true
	end)
	b.MouseButton1Up:Connect(function()
		holding = false
	end)
	b.MouseLeave:Connect(function()
		holding = false
	end)
	local keyConn = UserInputService.InputBegan:Connect(function(io, gp)
		if not gp and (io.KeyCode == Enum.KeyCode.Space or io.KeyCode == Enum.KeyCode.ButtonA) then
			holding = true
		end
	end)
	local keyUp = UserInputService.InputEnded:Connect(function(io)
		if io.KeyCode == Enum.KeyCode.Space or io.KeyCode == Enum.KeyCode.ButtonA then
			holding = false
		end
	end)
	Ui.select(b)
	local ok = false
	while alive(token) do
		local dt = task.wait()
		if holding then
			held += dt
		else
			held = math.max(0, held - dt * 0.6)
		end
		bar.set(held / secs)
		if held >= secs then
			ok = true
			break
		end
	end
	keyConn:Disconnect()
	keyUp:Disconnect()
	return ok
end

local function tapButton(body: Frame, label: string, n: number, token: number, onTap: ((number) -> ())?): boolean
	local count = 0
	local b = Ui.btn(body, { text = string.format("%s (0/%d)", label, n), style = "primary", size = UDim2.new(0.8, 0, 0, 56), pos = UDim2.new(0.5, 0, 1, -6), anchor = Vector2.new(0.5, 1), textSize = 17 })
	b.Activated:Connect(function()
		count += 1
		b.Text = string.format("%s (%d/%d)", label, math.min(count, n), n)
		if onTap then
			pcall(onTap, count)
		end
	end)
	local keyConn = UserInputService.InputBegan:Connect(function(io, gp)
		if not gp and (io.KeyCode == Enum.KeyCode.Space or io.KeyCode == Enum.KeyCode.ButtonA) then
			count += 1
			b.Text = string.format("%s (%d/%d)", label, math.min(count, n), n)
			if onTap then
				pcall(onTap, count)
			end
		end
	end)
	Ui.select(b)
	while alive(token) and count < n do
		task.wait(0.05)
	end
	keyConn:Disconnect()
	return count >= n
end

local function exam(kind: string, token: number): any?
	local res = ctx.call("exam", { kind = kind }, { quiet = true })
	if not res.ok then
		if res.code == "tooSoon" or res.code == "rate" then
			task.wait(1.1)
			res = ctx.call("exam", { kind = kind })
		elseif res.message then
			Ui.toast(res.message, nil, "warn")
		end
		if not res.ok then
			return nil
		end
	end
	local _ = token
	return res
end

local GAMES: { [string]: (number) -> any? } = {}

GAMES.temp = function(token)
	local body = openPanel("🌡️ 귀 체온 측정")
	local num = Ui.text(body, { Text = "--.-℃", Font = F.black, TextSize = 46, Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 6), TextXAlignment = Enum.TextXAlignment.Center })
	local res = exam("temp", token)
	if not res then
		return nil
	end
	local target = res.result.temp or 36.5
	local t0 = os.clock()
	while os.clock() - t0 < 1.6 and alive(token) do
		local a = (os.clock() - t0) / 1.6
		num.Text = string.format("%.1f℃", 35.0 + (target - 35.0) * a)
		task.wait()
	end
	num.Text = string.format("%.1f℃", target)
	num.TextColor3 = toneColor(res.result.tempTone)
	Ui.sound("beep")
	task.wait(0.6)
	return res
end

GAMES.throat = function(token)
	local body = openPanel("👄 입 크게 벌리고 '아~'")
	Ui.text(body, { Text = "버튼을 꾹 누르는 동안 '아~' 해요", Font = F.med, TextSize = 14, TextColor3 = Col.sub, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 24), TextXAlignment = Enum.TextXAlignment.Center })
	if not holdButton(body, "아~ (꾹 누르기)", 1.2, token) then
		return nil
	end
	return exam("throat", token)
end

GAMES.stetho = function(token)
	local body = openPanel("🩺 청진 · 숨 크게 들이쉬고 내쉬기")
	for i = 1, 2 do
		if not alive(token) then
			return nil
		end
		Ui.say("doctor", if i == 1 then "숨 크게 들이쉬세요…" else "한 번 더… 크게 들이쉬고, 천천히 내쉬세요.")
		if not holdButton(body, string.format("들이쉬기 %d/2 (꾹)", i), 1.1, token) then
			return nil
		end
		clearPanel()
		body = openPanel("🩺 …천천히 내쉬세요")
		task.wait(0.9)
	end
	return exam("stetho", token)
end

GAMES.bp = function(token)
	local body = openPanel("💓 혈압 측정 · 커프를 부풀리세요")
	local gauge = Ui.bar(body, { h = 16, color = Col.red })
	gauge.frame.Position = UDim2.new(0.1, 0, 0, 30)
	gauge.frame.Size = UDim2.new(0.8, 0, 0, 16)
	local mm = Ui.text(body, { Text = "0 mmHg", Font = F.black, TextSize = 24, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 0), TextXAlignment = Enum.TextXAlignment.Center })
	ctx.Treat.cuff(true)
	local ok = tapButton(body, "펌프 꾹꾹", 6, token, function(n)
		gauge.set(n / 6 * 0.9, nil, 0.15)
		mm.Text = string.format("%d mmHg", math.floor(n / 6 * 180))
		Ui.sound("tap", 0.8 + n * 0.05)
		ctx.Treat.cuffInflate(n / 6)
	end)
	if not ok then
		ctx.Treat.cuff(false)
		return nil
	end
	local res = exam("bp", token)
	if not res then
		ctx.Treat.cuff(false)
		return nil
	end
	local r = res.result
	local t0 = os.clock()
	while os.clock() - t0 < 1.8 and alive(token) do
		local a = (os.clock() - t0) / 1.8
		local p = 180 - (180 - (r.dia or 70)) * a
		mm.Text = string.format("%d mmHg", math.floor(p))
		gauge.set(p / 200)
		ctx.Treat.cuffInflate(1 - a)
		task.wait()
	end
	mm.Text = string.format("%d / %d · 맥박 %d", r.sys or 0, r.dia or 0, r.pulse or 0)
	mm.TextColor3 = toneColor(r.bpTone)
	Ui.sound("beep")
	ctx.Treat.cuffInflate(0)
	task.wait(0.7)
	ctx.Treat.cuff(false)
	return res
end

GAMES.palp = function(token)
	local body = openPanel("✋ 복부 촉진 · 누르는 곳을 확인해요")
	local spots = { { "명치", 0.5, 0.18 }, { "오른쪽 아래", 0.3, 0.62 }, { "왼쪽 아래", 0.7, 0.62 } }
	local done = 0
	local torso = Ui.new("Frame", { BackgroundColor3 = Color3.fromRGB(246, 220, 200), Size = UDim2.fromOffset(160, 110), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0) }, body)
	Ui.corner(torso, 40)
	for _, sp in spots do
		local b = Ui.btn(torso, { text = sp[1], style = "secondary", size = UDim2.fromOffset(74, 30), pos = UDim2.fromScale(sp[2], sp[3]), anchor = Vector2.new(0.5, 0), textSize = 12 })
		b.Activated:Connect(function()
			if b:GetAttribute("Pressed") then
				return
			end
			b:SetAttribute("Pressed", true)
			Ui.restyle(b, "primary")
			done += 1
		end)
	end
	while alive(token) and done < 3 do
		task.wait(0.05)
	end
	if not alive(token) then
		return nil
	end
	local kind = ctx.visit and ctx.visit.kind
	if kind == "gastritis" then
		Ui.ask("doctor", "여기 명치 누르면 아프세요?", { "악, 아파요!" }, { abort = function()
			return not alive(token)
		end })
	else
		Ui.ask("doctor", "누르면 아픈 곳 있어요?", { "괜찮아요" }, { abort = function()
			return not alive(token)
		end })
	end
	return exam("palp", token)
end

GAMES.talk = function(token)
	openPanel("💬 생활 문진")
	local hv = ctx.health or {}
	local choices = if (hv.workSec or 0) >= 3600 then { "알바를 쉬지 않고 계속했어요", "잠을 거의 못 잤어요" } else { "적당히 일해요", "요즘 좀 바빴어요" }
	if not Ui.ask("doctor", S.Medical.EXAMS.talk.say, choices, { abort = function()
		return not alive(token)
	end }) then
		return nil
	end
	return exam("talk", token)
end

-------------------------------------------------------------------------------------------------
-- diagnosis + plans
-------------------------------------------------------------------------------------------------
local function showPlans(v: any, token: number)
	planSheet.clear()
	planSheet.sub.Text = string.format("%s · %s", v.dx and v.dx.name or "", if v.night then "야간 진료" else "주간 진료")
	local b = planSheet.body
	Ui.text(b, { Text = "김선생: 이렇게 치료하면 돼요. 어떻게 하실래요?", Font = F.bold, TextSize = 14, TextColor3 = Col.tealDD, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 0 })
	local first: GuiObject? = nil
	local sending = false
	for i, pl in v.plans or {} do
		local disabled = pl.short ~= nil
		local cardBtn = Ui.new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = if disabled then Color3.fromRGB(243, 245, 246) else Col.white, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, Selectable = true }, b)
		Ui.corner(cardBtn, 14)
		Ui.stroke(cardBtn, if pl.badge and not disabled then Col.teal else Col.line, if pl.badge and not disabled then 2 else 1, 0)
		Ui.pad(cardBtn, 14, 10, 14, 12)
		Ui.list(cardBtn, "v", 4)
		local head = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1 }, cardBtn)
		Ui.text(head, { Text = (if pl.badge then "★ " else "") .. pl.title, Font = F.black, TextSize = 16, TextColor3 = if disabled then Col.faint else Col.ink, Size = UDim2.new(0.68, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
		Ui.text(head, { Text = S.won(pl.total or 0), Font = F.black, TextSize = 17, TextColor3 = if disabled then Col.faint else Col.tealDD, Size = UDim2.new(0.32, 0, 1, 0), Position = UDim2.fromScale(0.68, 0), TextXAlignment = Enum.TextXAlignment.Right })
		Ui.text(cardBtn, { Text = pl.sub or "", Font = F.med, TextSize = 12, TextColor3 = Col.sub, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
		local pills = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 }, cardBtn)
		local pll = Ui.list(pills, "h", 6)
		pcall(function()
			(pll :: any).Wraps = true
		end)
		for j, e in pl.effects or {} do
			Ui.pill(pills, e, if string.find(e, "그대로") then "warn" else "ok", j)
		end
		if pl.badge then
			Ui.pill(pills, pl.badge, "info", 0)
		end
		if pl.warn then
			Ui.text(cardBtn, { Text = "⚠️ " .. pl.warn, Font = F.bold, TextSize = 12, TextColor3 = Col.red, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 })
		end
		if pl.short then
			Ui.text(cardBtn, { Text = "💳 " .. pl.short .. " · ATM에서 출금 후 다시 와도 돼요", Font = F.bold, TextSize = 12, TextColor3 = Col.red, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5 })
		end
		if not first and not disabled then
			first = cardBtn
		end
		Ui.onActivate(cardBtn, function()
			if sending then
				return
			end
			Ui.sound("tap")
			if disabled then
				local pick = Ui.ask("doctor", string.format("이 치료는 %s이 필요해요. 진료비를 준비해 오시겠어요?", S.won(pl.total or 0)), { "ATM 다녀올게요", "다른 방법 볼게요" })
				if pick ~= 1 then
					return
				end
			end
			sending = true
			-- the doctor needs a little time with the patient (server MinConsult)
			local cv = ctx.visit
			local wait = cv and cv.canPlanIn or 0
			if wait > 0 then
				Ui.say("doctor", "잠깐만요, 차트 정리하고요…", { hold = wait + 0.5 })
				task.wait(wait)
			end
			local res = ctx.call("plan", { id = pl.id })
			sending = false
			if res.ok then
				planSheet.close()
			end
		end)
	end
	planSheet.focus = first
	planSheet.open()
	local _ = token
end

local function showDx(v: any, token: number)
	local dx = v.dx
	if not dx then
		return
	end
	dxSheet.clear()
	dxSheet.title.Text = "진단 결과"
	dxSheet.sub.Text = string.format("%s · %s %s", C.Doctor.room, C.Doctor.title, C.Doctor.name)
	local b = dxSheet.body
	local top = Ui.card(b, { LayoutOrder = 1 })
	Ui.pad(top, 14, 12, 14, 12)
	Ui.list(top, "v", 6)
	local h = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1 }, top)
	Ui.text(h, { Text = string.format("%s %s", dx.icon or "🩺", dx.name or ""), Font = F.black, TextSize = 20, Size = UDim2.new(0.78, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	local code = Ui.pill(h, "KCD " .. (dx.code or ""), "info")
	code.AnchorPoint = Vector2.new(1, 0.5)
	code.Position = UDim2.new(1, 0, 0.5, 0)
	if dx.find then
		Ui.text(top, { Text = "소견 · " .. dx.find, Font = F.med, TextSize = 14, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	end
	if dx.symptoms and #dx.symptoms > 0 then
		Ui.text(top, { Text = "주 증상 · " .. table.concat(dx.symptoms, " · "), Font = F.med, TextSize = 13, TextColor3 = Col.sub, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 })
	end
	if dx.vacBlocked then
		Ui.text(top, { Text = "💉 열이 있어서 오늘은 예방접종 대신 치료부터 해요", Font = F.bold, TextSize = 13, TextColor3 = Col.orange, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 })
	end
	Ui.healthCard(b, v.health or ctx.health or {}, { order = 2, title = "📋 건강 상태 · 원인 · 권장 조치" })
	local btn = Ui.btn(b, { text = "치료 계획 보기 ▶", style = "primary", size = UDim2.new(1, 0, 0, 50), order = 3, onClick = function()
		dxSheet.close()
		local cv = ctx.visit
		if cv and cv.step == "consult" then
			showPlans(cv, token)
		end
	end })
	dxSheet.focus = btn
	dxSheet.open()
end

-------------------------------------------------------------------------------------------------
-- flow
-------------------------------------------------------------------------------------------------
local function symptomAnswer(v: any): { string }
	local labels = {}
	for i, id in v.symptoms or {} do
		if i > 3 then
			break
		end
		if id ~= "none" then
			table.insert(labels, S.Medical.SYMPTOMS[id] or id)
		end
	end
	local out = {}
	if #labels > 0 then
		table.insert(out, table.concat(labels, " · ") .. " 있어요")
	end
	if v.dept == "vac" then
		table.insert(out, "독감 예방접종 하러 왔어요")
	end
	table.insert(out, "요즘 너무 피곤해서요")
	return out
end

local function run(greet: string?)
	if running then
		return
	end
	running = true
	runToken += 1
	local token = runToken
	local abort = function()
		return not alive(token)
	end
	local ok, err = pcall(function()
		frameCamera(true)
		buildVitals()
		vitalsCard.Visible = true
		local v = ctx.visit
		local hv = v.health or ctx.health or {}
		if (v.examIdx or 1) <= 1 then
			if not Ui.ask("doctor", greet or S.Medical.GREET[v.dept] or S.Medical.GREET.im, symptomAnswer(v), { abort = abort }) then
				return
			end
			local when = if (hv.nightSec or 0) >= 60 then "밤샘 알바 끝나고부터요" elseif (hv.workSec or 0) >= 1800 then "알바를 오래 하고 나서부터요" else "오늘부터요"
			if not Ui.ask("doctor", "언제부터 그랬어요?", { when, "며칠 됐어요" }, { abort = abort }) then
				return
			end
			if (hv.workSec or 0) >= 1800 then
				Ui.say("doctor", string.format("%s 쉬지 않고 일하셨네요… 피로도가 %d까지 올라 있어요. 진찰해 볼게요.", S.dur(hv.workSec), hv.fatigue or 0))
			else
				Ui.say("doctor", "알겠어요. 진찰해 볼게요.")
			end
			task.wait(1.4)
		end
		-- 진찰
		while alive(token) do
			v = ctx.visit
			local idx = v.examIdx or 1
			if idx > #(v.exams or {}) then
				break
			end
			local kind = v.exams[idx]
			local def = S.Medical.EXAMS[kind]
			Ui.say("doctor", def and def.say or "진찰할게요.", { hold = 3 })
			local mini = GAMES[kind]
			local res = if mini then mini(token) else exam(kind, token)
			if not res then
				return
			end
			showResult(kind, res.result or {})
			if res.done then
				break
			end
			task.wait(0.4)
		end
		panel.Visible = false
		if not alive(token) then
			return
		end
		v = ctx.visit
		-- 진단
		if v.dx then
			Ui.say("doctor", v.dx.find or "진찰 끝났어요.", { hold = 4 })
			task.wait(2.2)
			-- the doctor names the real cause (work log · fatigue) before the diagnosis card
			local cause = v.dx.cause
			if type(cause) == "string" and cause ~= "" and alive(token) then
				local reply = if v.dx.kindName then "네… 너무 무리했나 봐요" elseif (v.dx.fatigue or 0) >= 50 then "요즘 좀 바빴어요" else "다행이네요!"
				Ui.ask("doctor", cause .. (if v.dx.after then " " .. v.dx.after else ""), { reply }, { abort = abort })
			end
			if not alive(token) then
				return
			end
			showDx(v, token)
		end
		-- wait until the step changes (plan chosen) or the visit ends; a closed sheet leaves a way back
		local reopen: TextButton? = nil
		while alive(token) do
			task.wait(0.25)
			local cv = ctx.visit
			if cv and cv.plans and not dxSheet.isOpen and not planSheet.isOpen then
				if not reopen or not reopen.Parent then
					local body = openPanel("진료실 · " .. C.Doctor.name)
					reopen = Ui.btn(body, { text = "📋 치료 계획 보기", style = "primary", size = UDim2.new(0.8, 0, 0, 56), pos = UDim2.new(0.5, 0, 0.5, 0), anchor = Vector2.new(0.5, 0.5), textSize = 17, onClick = function()
						panel.Visible = false
						local nv = ctx.visit
						if nv and nv.step == "consult" then
							showPlans(nv, token)
						end
					end })
				end
				panel.Visible = true
			elseif reopen and (dxSheet.isOpen or planSheet.isOpen) then
				panel.Visible = false
			end
		end
	end)
	if not ok then
		warn("[GwangalliClinic] consult flow:", err)
	end
	running = false
	panel.Visible = false
	vitalsCard.Visible = false
	pcall(ctx.Treat.cuff, false)
	frameCamera(false)
	if dxSheet.isOpen then
		dxSheet.close()
	end
	if planSheet.isOpen then
		planSheet.close()
	end
end

function Consult.enter()
	local res = ctx.call("enter", {})
	if res.ok then
		task.spawn(run, res.greet)
	end
end

function Consult.onVisit(v: any, _prev: any)
	if v and v.step == "consult" and not running then
		-- reconnect / respawn while in the consult room: pick the flow up where the server is
		task.spawn(run, nil)
	end
	if v and v.step == "consult" and v.dx and not dxSheet.isOpen and not planSheet.isOpen and running and v.examIdx and v.exams and v.examIdx > #v.exams then
		-- (the dx is shown by the running flow)
		return
	end
end

function Consult.init(c: any)
	ctx = c
	S = c.S
	C = c.C
	Ui = c.Ui
	Col = Ui.C
	F = Ui.F
	panel = Ui.new("Frame", { Name = "ExamPanel", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -196), Size = UDim2.fromOffset(420, 150), BackgroundColor3 = Col.white, Visible = false, ZIndex = 30, Active = true }, Ui.gui)
	Ui.corner(panel, 16)
	Ui.stroke(panel, Col.teal, 1.5, 0.2)
	Ui.pad(panel, 12, 10, 12, 10)
	vitalsCard = Ui.card(Ui.gui, { Name = "Vitals", AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(12, 96), Size = UDim2.fromOffset(250, 0), Visible = false })
	Ui.pad(vitalsCard, 12, 10, 12, 10)
	Ui.list(vitalsCard, "v", 4)
	Ui.onLayout(function()
		local W, H = Ui.size()
		panel.Size = UDim2.fromOffset(math.min(420, W - 24), 150)
		Ui.placeBottom(panel, 420, if H < 480 then 176 else 196)
		vitalsCard.Size = UDim2.fromOffset(if W < 760 then 200 else 250, 0)
		-- the vitals card sits under the game's top-left chips when the layout module tells us where
		local tl = Ui.slotRect("topLeftChips")
		vitalsCard.Position = UDim2.fromOffset(12, if tl then tl.y + tl.h + 8 else 96)
	end)
	dxSheet = Ui.sheet("GwClinic_Dx", { title = "진단 결과", w = 560, h = 660, sticky = true })
	planSheet = Ui.sheet("GwClinic_Plan", { title = "치료 계획", w = 560, h = 640, sticky = true })
	-- stepping off the consult seat restores the camera (the server keeps the visit)
	RunService.Heartbeat:Connect(function()
		if savedCam and not running then
			frameCamera(false)
		end
	end)
	local _ = player
end

return Consult
