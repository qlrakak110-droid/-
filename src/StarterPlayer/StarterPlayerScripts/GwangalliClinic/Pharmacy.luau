-- GwangalliClinic/Pharmacy (client): 원내 약국 (약사 정약사).
--   처방전 내기 → 조제 대기 (progress, PrescriptionScreen shows "조제 중 042") → "042번 약 나왔습니다" (call) →
--   약 받기 → 약봉투 + 복약 안내 card (약 이름 · 성분 · 1회 용량 · ☀️🌤️🌙 복용 시간 · 주의사항 · "충분히 쉬세요")
--   → "지금 한 번 드실래요?" (dose 1 of 3 on the server). A paper bag prop rests in the hand for a moment
--   (local only).

local Players = game:GetService("Players")

local Pharmacy = {}

local ctx: any
local S: any
local C: any
local Ui: any
local Col: any
local F: any
local player = Players.LocalPlayer

local waitCard: Frame
local waitBar: any
local bagSheet: any
local waitToken = 0

local function bagProp()
	local ch = player.Character
	local hand = ch and (ch:FindFirstChild("RightHand") or ch:FindFirstChild("Right Arm"))
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local p = Instance.new("Part")
	p.Name = "PillBag"
	p.Size = Vector3.new(0.75, 0.95, 0.25)
	p.Color = Color3.fromRGB(250, 250, 244)
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CFrame = hand.CFrame * CFrame.new(0, -0.55, -0.15)
	local band = Instance.new("Part")
	band.Name = "Band"
	band.Size = Vector3.new(0.77, 0.18, 0.27)
	band.Color = Color3.fromRGB(15, 163, 163)
	band.Material = Enum.Material.SmoothPlastic
	band.CanCollide = false
	band.CanTouch = false
	band.CanQuery = false
	band.Massless = true
	band.CFrame = p.CFrame * CFrame.new(0, 0.28, 0)
	local w1 = Instance.new("WeldConstraint")
	w1.Part0 = hand
	w1.Part1 = p
	w1.Parent = p
	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = p
	w2.Part1 = band
	w2.Parent = band
	band.Parent = p
	p.Parent = ctx.Tracker.localFolder()
	task.delay(8, function()
		p:Destroy()
	end)
end

local function timeIcons(times: string?): string
	local t = times or ""
	if string.find(t, "2번") then
		return "☀️ 아침   🌙 저녁"
	end
	return "☀️ 아침   🌤️ 점심   🌙 저녁"
end

local function showBag(res: any)
	bagSheet.clear()
	local rx = res.rx or {}
	bagSheet.title.Text = "약봉투 · 복약 안내"
	bagSheet.sub.Text = string.format("%s번 · %s · 약사 정약사", S.ticket(rx.ticket or 0), rx.patient or "")
	local b = bagSheet.body
	local bag = Ui.paper(b, { LayoutOrder = 1 })
	Ui.text(bag, { Text = C.Venue.Name .. " 원내 약국", Font = F.black, TextSize = 16, TextColor3 = Col.tealDD, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	Ui.text(bag, { Text = string.format("%s님 · %s", rx.patient or "", rx.dxName or ""), Font = F.bold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })
	Ui.text(bag, { Text = timeIcons(rx.items and rx.items[1] and rx.items[1].times), Font = F.black, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3 })
	for i, it in rx.items or {} do
		local row = Ui.new("Frame", { BackgroundColor3 = if i % 2 == 0 then Col.mint else Col.white, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 10 + i }, bag)
		Ui.corner(row, 8)
		Ui.text(row, { Text = "💊 " .. it.name, Font = F.bold, TextSize = 14, Position = UDim2.fromOffset(8, 2), Size = UDim2.new(0.6, -8, 0, 20) })
		Ui.text(row, { Text = it.generic or "", Font = F.med, TextSize = 11, TextColor3 = Col.sub, Position = UDim2.fromOffset(28, 21), Size = UDim2.new(0.6, -28, 0, 16) })
		Ui.text(row, { Text = string.format("1회 %s · %d일", it.dose or "1정", it.days or 3), Font = F.bold, TextSize = 13, TextColor3 = Col.tealDD, Position = UDim2.fromScale(0.6, 0), Size = UDim2.new(0.4, -8, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	end
	Ui.text(bag, { Text = res.guide or "", Font = F.med, TextSize = 13, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 40 })
	if res.caution then
		Ui.text(bag, { Text = "⚠️ " .. res.caution, Font = F.bold, TextSize = 13, TextColor3 = Col.orange:Lerp(Col.black, 0.25), TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 41 })
	end
	Ui.text(bag, { Text = "🛏️ " .. (res.rest or "충분히 쉬세요"), Font = F.black, TextSize = 14, TextColor3 = Col.tealDD, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 42 })
	local hv = ctx.health
	if hv and type(hv.advice) == "table" then
		for i, line in hv.advice do
			if string.find(line, "🛏️") or string.find(line, "🍜") then
				Ui.text(bag, { Text = line, Font = F.med, TextSize = 12, TextColor3 = Col.sub, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 50 + i })
			end
		end
	end
	local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), LayoutOrder = 9 }, b)
	local now = Ui.btn(row, { text = "💧 지금 한 번 먹기", style = "primary", size = UDim2.new(0.5, -5, 1, 0), textSize = 15, onClick = function()
		local r = ctx.call("dose", {})
		if r.ok and r.dose then
			Ui.toast(string.format("💊 약을 먹었어요 (%d/%d)", r.dose.taken, r.dose.total), string.format("피로도 -%d · 질병 위험도 -%d · 다음은 %s 뒤", r.dose.rest or C.Meds.Rest, C.Meds.Risk, S.dur(C.Meds.Every)), "ok")
			ctx.meds = r.meds
			ctx.Tracker.renderMeds()
			bagSheet.close()
		end
	end })
	Ui.btn(row, { text = "나중에 먹을게요", style = "ghost", size = UDim2.new(0.5, -5, 1, 0), pos = UDim2.new(0.5, 5, 0, 0), textSize = 15, onClick = function()
		bagSheet.close()
	end })
	bagSheet.focus = now
	bagSheet.open()
end

function Pharmacy.submit()
	local res = ctx.call("pharmacy", { action = "submit" })
	if res.ok then
		Ui.sound("print")
	end
end

function Pharmacy.collect()
	local res = ctx.call("pharmacy", { action = "collect" })
	if res.ok then
		Ui.say("pharm", (res.guide or "") .. " " .. (res.rest or ""), { name = C.Staff.pharm.name, hold = 6 })
		bagProp()
		showBag(res)
	end
end

function Pharmacy.onVisit(v: any, prev: any)
	local step = v and v.step
	if step == "pharm_wait" and (prev and prev.step) ~= "pharm_wait" then
		waitToken += 1
		local token = waitToken
		waitCard.Visible = true
		local secs = C.Wait.Dispense * (if v.pass then C.Pass.WaitFactor else 1)
		task.spawn(function()
			local t0 = os.clock()
			while token == waitToken and ctx.visit and ctx.visit.step == "pharm_wait" do
				waitBar.set(math.min(1, (os.clock() - t0) / secs))
				task.wait(0.05)
			end
			waitBar.set(1)
		end)
	elseif step ~= "pharm_wait" then
		waitToken += 1
		waitCard.Visible = false
	end
end

function Pharmacy.init(c: any)
	ctx = c
	S = c.S
	C = c.C
	Ui = c.Ui
	Col = Ui.C
	F = Ui.F
	waitCard = Ui.card(Ui.gui, { Name = "Dispense", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(380, 0), Visible = false, ZIndex = 31 })
	Ui.pad(waitCard, 14, 10, 14, 12)
	Ui.list(waitCard, "v", 8)
	Ui.text(waitCard, { Text = "💊 약 조제 중 · 잠시만 기다려 주세요", Font = F.black, TextSize = 15, TextColor3 = Col.tealDD, LayoutOrder = 1 })
	waitBar = Ui.bar(waitCard, { h = 12, order = 2 })
	Ui.text(waitCard, { Text = "약국 화면에 내 번호가 '조제 완료'로 바뀌면 받으러 오세요", Font = F.med, TextSize = 12, TextColor3 = Col.sub, LayoutOrder = 3, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
	Ui.onLayout(function()
		local W = Ui.size()
		waitCard.Size = UDim2.fromOffset(math.min(380, W - 24), 0)
		Ui.placeBottom(waitCard, 380, 24)
	end)
	bagSheet = Ui.sheet("GwClinic_Bag", { title = "약봉투", w = 500, h = 640 })
end

return Pharmacy
