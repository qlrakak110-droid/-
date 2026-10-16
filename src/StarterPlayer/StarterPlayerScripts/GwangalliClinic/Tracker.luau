-- GwangalliClinic/Tracker (client): the patient's always-on guidance.
--   visit card (top right): 번호표 · 단계 · 안내 · 진행 점 (접수 → 진료 → 처치 → 수납 → 약국) · 다음 장소 + 거리 ·
--     대기 n명 / 예상 시간 · [진료 기록] [취소]; for 건강검진, the station checklist
--   health chip (no visit): 아플 때 / 미납금 / 병실 휴식 · the way to the clinic
--   meds chip: 💊 2/3 · 지금 드세요 [약 먹기] (real effect on the server)
--   call banner: 🔔 딩동! 042번 홍*동님, 1번 창구로 와 주세요 (the screens play the chime inside the clinic)
--   guidance: a teal Beam from the character to the next anchor + a floating marker
--   summary card when a visit ends (질병 · 피로도 · 급여 배율 before → after, 결제 / 미납)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Tracker = {}

local ctx: any
local S: any
local C: any
local Ui: any
local Col: any
local F: any
local player = Players.LocalPlayer

local card: Frame
local cardBody: Frame
local chip: Frame
local medsChip: Frame
local banner: Frame
local bannerText: TextLabel
local summarySheet: any
local guidePart: Part? = nil
local guideAttach: Attachment? = nil
local charAttach: Attachment? = nil
local beam: Beam? = nil
local marker: BillboardGui? = nil
local markerText: TextLabel? = nil
local distLabel: TextLabel? = nil
local etaLabel: TextLabel? = nil
local collapsed = false
local restInfo: any = nil

local function localFolder(): Folder
	local f = workspace:FindFirstChild(S.NAMES.Local)
	if not f then
		f = Instance.new("Folder")
		f.Name = S.NAMES.Local
		f.Parent = workspace
	end
	return f :: Folder
end
Tracker.localFolder = localFolder

-------------------------------------------------------------------------------------------------
-- guidance beam + marker
-------------------------------------------------------------------------------------------------
local function ensureGuide()
	if guidePart and guidePart.Parent then
		return
	end
	local p = Instance.new("Part")
	p.Name = "ClinicGuide"
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Parent = localFolder()
	guidePart = p
	guideAttach = Ui.new("Attachment", { Name = "To" }, p)
	marker = Ui.new("BillboardGui", { Name = "Marker", Adornee = p, Size = UDim2.fromOffset(170, 52), StudsOffset = Vector3.new(0, 2.2, 0), AlwaysOnTop = true, MaxDistance = 250, LightInfluence = 0, Enabled = false }, p)
	local m = Ui.new("Frame", { BackgroundColor3 = Col.teal, Size = UDim2.new(1, 0, 0, 30) }, marker)
	Ui.corner(m, 15)
	markerText = Ui.text(m, { Text = "", Font = F.black, TextSize = 14, TextColor3 = Col.white, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	Ui.text(marker :: any, { Text = "▼", Font = F.black, TextSize = 20, TextColor3 = Col.teal, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
end

local function ensureCharAttach(): Attachment?
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	if charAttach and charAttach.Parent == root then
		return charAttach
	end
	if charAttach then
		charAttach:Destroy()
	end
	charAttach = Ui.new("Attachment", { Name = "GwClinicGuide", Position = Vector3.new(0, -1.6, 0) }, root)
	if beam then
		beam:Destroy()
	end
	beam = Ui.new("Beam", {
		Name = "GwClinicBeam",
		Attachment0 = charAttach,
		Attachment1 = guideAttach,
		Color = ColorSequence.new(Col.teal, Color3.fromRGB(120, 230, 220)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(0.15, 0.35), NumberSequenceKeypoint.new(1, 0.2) }),
		Width0 = 0.35,
		Width1 = 0.35,
		FaceCamera = true,
		LightEmission = 0.6,
		Segments = 12,
		Enabled = false,
	}, root)
	return charAttach
end

local function targetAnchor(): BasePart?
	local v = ctx.visit
	if not v then
		local hv = ctx.health
		if hv and (hv.debt or 0) > 0 and ctx.ward and ctx.ward.woke then
			return ctx.anchor("Win1")
		end
		return nil
	end
	if v.chk and v.step == "chk_course" then
		-- the nearest station still to do
		local best, bestD = nil, math.huge
		local p = ctx.rootPos()
		for _, st in v.chk.stations do
			if not st.done then
				local a = ctx.anchor(st.anchor)
				if a and p then
					local d = (a.Position - p).Magnitude
					if d < bestD then
						best, bestD = a, d
					end
				end
			end
		end
		return best
	end
	if v.target then
		return ctx.anchor(v.target)
	end
	return nil
end

local function targetLabel(a: BasePart): string
	return tostring(a:GetAttribute(S.NAMES.AttrLabel) or "")
end

-------------------------------------------------------------------------------------------------
-- cards
-------------------------------------------------------------------------------------------------
local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") and not c:IsA("UICorner") and not c:IsA("UIStroke") then
			c:Destroy()
		end
	end
end

local function dots(parent: Instance, stage: number)
	local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 4 }, parent)
	local n = #S.STAGES
	for i, name in S.STAGES do
		local x = (i - 0.5) / n
		local done = stage > i
		local cur = stage == i
		local d = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, 0), Size = UDim2.fromOffset(if cur then 14 else 10, if cur then 14 else 10), BackgroundColor3 = if done or cur then Col.teal else Col.line }, row)
		Ui.corner(d, 7)
		if cur then
			Ui.stroke(d, Col.mint2, 3, 0)
		end
		Ui.text(row, { Text = name, Font = if cur then F.black else F.med, TextSize = 11, TextColor3 = if cur then Col.tealDD else Col.faint, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, 16), Size = UDim2.fromOffset(52, 16), TextXAlignment = Enum.TextXAlignment.Center })
		if i < n then
			local line = Ui.new("Frame", { BackgroundColor3 = if done then Col.teal else Col.line, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(x, 8, 0, 6), Size = UDim2.new(1 / n, -16, 0, 2) }, row)
			local _ = line
		end
	end
end

local function renderCard()
	local v = ctx.visit
	clear(cardBody)
	distLabel = nil
	etaLabel = nil
	if not v then
		card.Visible = false
		return
	end
	card.Visible = true
	local head = Ui.new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = Col.teal, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1 }, cardBody)
	Ui.corner(head, 10)
	Ui.text(head, { Text = "🏥 " .. C.Venue.Name, Font = F.black, TextSize = 13, TextColor3 = Col.white, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -60, 1, 0) })
	Ui.text(head, { Text = (if v.pass then "⚡ " else "") .. (if collapsed then "▾" else "▴"), Font = F.black, TextSize = 13, TextColor3 = Col.white, Position = UDim2.new(1, -50, 0, 0), Size = UDim2.new(0, 42, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	head.Activated:Connect(function()
		collapsed = not collapsed
		renderCard()
	end)
	local top = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 2 }, cardBody)
	Ui.text(top, { Text = S.ticket(v.ticket), Font = F.black, TextSize = 34, TextColor3 = Col.tealDD, Size = UDim2.new(0, 84, 1, 0) })
	Ui.text(top, { Text = v.stepLabel or "", Font = F.black, TextSize = 17, Position = UDim2.fromOffset(88, 2), Size = UDim2.new(1, -88, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.text(top, { Text = string.format("%s%s", v.deptName or "", if v.prio then " · 응급 우선" else ""), Font = F.med, TextSize = 12, TextColor3 = if v.prio then Col.red else Col.sub, Position = UDim2.fromOffset(88, 24), Size = UDim2.new(1, -88, 0, 16) })
	if collapsed then
		return
	end
	Ui.text(cardBody, { Text = v.hint or "", Font = F.med, TextSize = 13, TextColor3 = Col.sub, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 3 })
	if v.chk then
		local list = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 }, cardBody)
		Ui.list(list, "v", 3)
		for i, st in v.chk.stations do
			Ui.text(list, { Text = string.format("%s %s %s", if st.done then "✅" else "⬜", st.icon or "", st.label) .. (if st.done and st.text ~= "" then "  " .. st.text else ""), Font = if st.done then F.med else F.bold, TextSize = 12, TextColor3 = if st.done then Col.sub else Col.ink, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
		end
	else
		dots(cardBody, v.stage or 1)
	end
	local info = Ui.new("Frame", { BackgroundColor3 = Col.mint, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5 }, cardBody)
	Ui.corner(info, 10)
	Ui.pad(info, 10, 6, 10, 6)
	Ui.list(info, "v", 2)
	distLabel = Ui.text(info, { Text = "", Font = F.bold, TextSize = 13, TextColor3 = Col.tealDD, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1 })
	etaLabel = Ui.text(info, { Text = "", Font = F.med, TextSize = 12, TextColor3 = Col.sub, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 2 })
	if v.step == "desk_wait" or v.step == "consult_wait" then
		etaLabel.Text = if (v.place or 0) > 1 then string.format("내 앞에 %d명 · 약 %d초", v.place - 1, v.eta or 0) else string.format("곧 불러요 · 약 %d초", v.eta or 0)
	elseif v.step == "need_money" then
		etaLabel.Text = string.format("필요 %s · 통장 %s · 현금 %s", S.won(v.need or 0), S.won(v.health and v.health.bank or 0), S.won(v.health and v.health.cash or 0))
		etaLabel.TextColor3 = Col.red
	elseif v.step == "iv" and v.iv then
		etaLabel.Text = string.format("수액 %d%% · %s", math.floor(100 * (v.iv.progress or 0) / math.max(1, v.iv.seconds or 1)), if (v.iv.speed or 1) > 1 then "😴 자는 중 (빨리 감기)" else "편하게 누워 계세요")
	else
		etaLabel.Text = ""
	end
	local btns = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 6 }, cardBody)
	Ui.btn(btns, { text = "📋 진료 기록", style = "secondary", size = UDim2.new(0.5, -4, 1, 0), textSize = 13, onClick = function()
		ctx.Chart.open()
	end })
	local cancelable = v.step ~= "treat" and v.step ~= "done"
	if cancelable then
		Ui.btn(btns, { text = if v.chk then "검진 취소" else "진료 취소", style = "ghost", size = UDim2.new(0.5, -4, 1, 0), pos = UDim2.new(0.5, 4, 0, 0), textSize = 13, onClick = function()
			local due = v.bill and v.bill.sum and v.bill.sum.dueNew or 0
			local msg = if due > 0 then string.format("지금 나가면 %s 이 미납금으로 남아요. 정말 취소할까요?", S.won(due)) else "접수를 취소할까요?"
			local pick = Ui.ask("system", msg, { "계속 진료받기", "취소할게요" })
			if pick == 2 then
				if v.chk then
					ctx.call("checkup", { action = "cancel" })
				else
					ctx.call("cancel", {})
				end
			else
				Ui.hideDialog()
			end
		end })
	end
end

local function renderChip()
	clear(chip)
	local hv = ctx.health
	local v = ctx.visit
	if v or not hv then
		chip.Visible = false
		return
	end
	local lines = {}
	if hv.kind then
		table.insert(lines, { text = string.format("%s %s · %s에서 치료받아요", hv.kindIcon or "🤒", hv.kindName or "질병", C.Venue.Name), color = Col.red })
		if hv.collapseIn and hv.collapseIn < 300 then
			table.insert(lines, { text = string.format("⚠️ 약 %d분 뒤 쓰러질 수 있어요", math.max(1, math.ceil(hv.collapseIn / 60))), color = Col.red })
		end
	end
	if (hv.debt or 0) > 0 then
		table.insert(lines, { text = string.format("🧾 미납 진료비 %s · 1층 원무과에서 정산", S.won(hv.debt)), color = Col.orange })
	end
	if restInfo then
		table.insert(lines, { text = string.format("🛏️ 병실 휴식 · 피로도 -%d / -%d", restInfo.given or 0, restInfo.max or C.Ward.RestMaxPerStay), color = Col.tealDD })
	end
	if #lines == 0 then
		chip.Visible = false
		return
	end
	chip.Visible = true
	for i, l in lines do
		Ui.text(chip, { Text = l.text, Font = F.bold, TextSize = 13, TextColor3 = l.color, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = i })
	end
	distLabel = Ui.text(chip, { Text = "", Font = F.med, TextSize = 12, TextColor3 = Col.sub, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 10 })
end

local function renderMeds()
	clear(medsChip)
	local m = ctx.meds
	if not m then
		medsChip.Visible = false
		return
	end
	medsChip.Visible = true
	Ui.text(medsChip, { Text = string.format("💊 %s %d/%d", m.name or "처방약", m.taken or 0, m.total or 3), Font = F.black, TextSize = 13, TextColor3 = Col.tealDD, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, TextTruncate = Enum.TextTruncate.AtEnd })
	local due = m.due or (m.nextIn or 0) <= 0
	local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 2 }, medsChip)
	local status = Ui.text(row, { Name = "Status", Text = if due then "지금 드실 시간이에요" else string.format("다음 복용까지 %s", S.dur(m.nextIn or 0)), Font = F.med, TextSize = 12, TextColor3 = Col.sub, Size = UDim2.new(1, -96, 1, 0) })
	local _ = status
	Ui.btn(row, { text = "약 먹기", style = if due then "primary" else "disabled", size = UDim2.fromOffset(88, 32), pos = UDim2.new(1, 0, 0, 1), anchor = Vector2.new(1, 0), textSize = 13, onClick = function()
		local res = ctx.call("dose", {})
		if res.ok and res.dose then
			Ui.toast(string.format("💊 약을 먹었어요 (%d/%d)", res.dose.taken, res.dose.total), string.format("피로도 -%d · 질병 위험도 -%d%s", res.dose.rest or C.Meds.Rest, C.Meds.Risk, if res.dose.finished then " · 처방약을 다 먹었어요!" else ""), "ok")
			ctx.meds = res.meds
			renderMeds()
		end
	end })
end
Tracker.renderMeds = renderMeds

-------------------------------------------------------------------------------------------------
-- banner + summary
-------------------------------------------------------------------------------------------------
local bannerToken = 0
function Tracker.banner(text: string, tone: Color3?)
	bannerToken += 1
	local token = bannerToken
	bannerText.Text = text
	banner.BackgroundColor3 = tone or Col.teal
	banner.Visible = true
	banner.Position = UDim2.new(0.5, 0, 0, -80)
	Ui.tween(banner, 0.35, { Position = UDim2.new(0.5, 0, 0, 12) }, Enum.EasingStyle.Back)
	task.delay(5.5, function()
		if token == bannerToken then
			Ui.tween(banner, 0.3, { Position = UDim2.new(0.5, 0, 0, -90) })
			task.wait(0.32)
			if token == bannerToken then
				banner.Visible = false
			end
		end
	end)
end

function Tracker.onCall(p: any)
	Tracker.banner(p.text or "", Col.teal)
	if not ctx.Screens.inClinic() then
		Ui.ding()
	end
	pcall(function()
		local hs = game:GetService("HapticService")
		hs:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0.4)
		task.delay(0.25, function()
			hs:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
		end)
	end)
end

function Tracker.onDone(p: any)
	local sm = p.summary or {}
	if sm.checkup and sm.treated then
		return -- the 결과지 is the summary of a checkup
	end
	if not sm.treated then
		if p.note then
			Ui.toast(p.note, nil, if p.reason == "done" then "ok" else "warn")
		end
		return
	end
	summarySheet.clear()
	summarySheet.title.Text = "진료 완료 · 몸조리 잘 하세요"
	summarySheet.sub.Text = string.format("%s번 · %s", S.ticket(sm.ticket), sm.dx or "")
	local b = summarySheet.body
	local function kindName(k: any): string
		local kd = S.kind(k)
		return if kd then kd.icon .. " " .. kd.name else "건강 😊"
	end
	local box = Ui.card(b, { LayoutOrder = 1 })
	Ui.pad(box, 14, 12, 14, 12)
	Ui.list(box, "v", 6)
	Ui.row(box, "질병", string.format("%s  →  %s", kindName(sm.kindBefore), kindName(sm.kindAfter)), { order = 1 })
	Ui.row(box, "피로도", string.format("%d  →  %d", sm.fatigueBefore or 0, sm.fatigueAfter or 0), { order = 2, rightColor = Ui.fatigueColor(sm.fatigueAfter or 0) })
	Ui.row(box, "알바 급여", string.format("x%.1f  →  x%.1f", sm.multBefore or 1, sm.multAfter or 1), { order = 3, rightColor = if (sm.multAfter or 1) >= 1 then Col.green else Col.orange })
	Ui.row(box, "결제한 진료비", S.won(sm.paid or 0), { order = 4 })
	if (sm.deferred or 0) > 0 then
		Ui.row(box, "미납 (다음에 청구)", S.won(sm.deferred), { order = 5, rightColor = Col.orange })
	end
	if p.meds then
		Ui.text(b, { Text = string.format("💊 %s · %d번 드세요 (%s)", p.meds.name or "처방약", p.meds.total or 3, p.meds.times or ""), Font = F.bold, TextSize = 14, TextColor3 = Col.tealDD, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	end
	if p.health then
		Ui.healthCard(b, p.health, { order = 3, title = "🌿 지금 내 상태" })
	end
	Ui.btn(b, { text = "확인", style = "primary", size = UDim2.new(1, 0, 0, 48), order = 9, onClick = function()
		summarySheet.close()
	end })
	summarySheet.open()
end

function Tracker.onWard(p: any)
	if p.rest == "tick" then
		restInfo = { given = p.given, max = p.max }
		renderChip()
	elseif p.rest == "end" then
		restInfo = nil
		renderChip()
		if (p.given or 0) > 0 then
			Ui.toast("🛏️ 병실 휴식 끝", string.format("피로도 -%d", p.given), "ok")
		end
	end
	if p.wake then
		ctx.ward = { woke = true, debt = p.debt }
		renderChip()
	end
end

function Tracker.onVisit(_v: any)
	renderCard()
	renderChip()
end

function Tracker.onHealth(_h: any)
	renderChip()
	if ctx.visit and not collapsed then
		-- keep the money line of need_money fresh
		if ctx.visit.step == "need_money" then
			renderCard()
		end
	end
end

function Tracker.onMeds(_m: any)
	renderMeds()
end

function Tracker.init(c: any)
	ctx = c
	S = c.S
	C = c.C
	Ui = c.Ui
	Col = Ui.C
	F = Ui.F
	local gui = Ui.gui
	local right = Ui.new("Frame", { Name = "RightStack", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 96), Size = UDim2.fromOffset(300, 0), AutomaticSize = Enum.AutomaticSize.Y }, gui)
	Ui.list(right, "v", 8, Enum.HorizontalAlignment.Right)
	card = Ui.card(right, { Name = "VisitCard", Size = UDim2.fromOffset(300, 0), LayoutOrder = 1, Visible = false })
	cardBody = card
	Ui.pad(card, 10, 10, 10, 10)
	Ui.list(card, "v", 8)
	chip = Ui.card(right, { Name = "HealthChip", Size = UDim2.fromOffset(300, 0), LayoutOrder = 2, Visible = false })
	Ui.pad(chip, 12, 8, 12, 8)
	Ui.list(chip, "v", 3)
	medsChip = Ui.card(right, { Name = "MedsChip", Size = UDim2.fromOffset(300, 0), LayoutOrder = 3, Visible = false })
	Ui.pad(medsChip, 12, 8, 12, 8)
	Ui.list(medsChip, "v", 4)
	Ui.onLayout(function()
		local W, H = Ui.size()
		local w = if W < 760 then 250 else 300
		right.Size = UDim2.fromOffset(w, 0)
		for _, f in { card, chip, medsChip } do
			f.Size = UDim2.fromOffset(w, 0)
		end
		right.Position = UDim2.new(1, -10, 0, if H < 460 then 60 else 96)
	end)
	banner = Ui.new("Frame", { Name = "CallBanner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -90), Size = UDim2.fromOffset(640, 64), BackgroundColor3 = Col.teal, Visible = false, ZIndex = 55 }, gui)
	Ui.corner(banner, 18)
	Ui.stroke(banner, Col.white, 2, 0.3)
	bannerText = Ui.text(banner, { Text = "", Font = F.black, TextSize = 19, TextColor3 = Col.white, TextWrapped = true, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 56 })
	Ui.onLayout(function()
		local W = Ui.size()
		banner.Size = UDim2.fromOffset(math.min(640, W - 20), 64)
	end)
	summarySheet = Ui.sheet("GwClinic_Summary", { title = "진료 완료", w = 480, h = 600 })
	ensureGuide()
	-- distance / beam / marker
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local a = targetAnchor()
		local p = ctx.rootPos()
		ensureGuide()
		local att = ensureCharAttach()
		if a and p and guidePart and att and beam and marker then
			guidePart.CFrame = CFrame.new(a.Position + Vector3.new(0, -1.4, 0))
			local d = (a.Position - p).Magnitude
			local show = d > 7 and d < 260
			beam.Enabled = show
			marker.Enabled = show
			if markerText then
				markerText.Text = string.format("%s · %dm", targetLabel(a), math.floor(d * 0.28 + 0.5))
			end
			if distLabel then
				distLabel.Text = if d <= 7 then string.format("📍 %s 도착", targetLabel(a)) else string.format("→ %s · %dm", targetLabel(a), math.floor(d * 0.28 + 0.5))
			end
		else
			if beam then
				beam.Enabled = false
			end
			if marker then
				marker.Enabled = false
			end
			if distLabel then
				local v = ctx.visit
				if v and (v.step == "consult" or v.step == "treat" or v.step == "iv") then
					distLabel.Text = "📍 " .. (v.stepLabel or "")
				elseif not v then
					-- health chip: distance to the clinic door
					local k = ctx.anchor("Kiosk")
					distLabel.Text = if k and p then string.format("🏥 %s까지 %dm", C.Venue.Name, math.floor((k.Position - p).Magnitude * 0.28 + 0.5)) else ""
				else
					distLabel.Text = ""
				end
			end
		end
	end)
	-- meds countdown
	task.spawn(function()
		while true do
			task.wait(5)
			local m = ctx.meds
			if m and (m.nextIn or 0) > 0 then
				m.nextIn = math.max(0, m.nextIn - 5)
				if m.nextIn == 0 then
					m.due = true
					Ui.toast("💊 약 먹을 시간이에요", m.name, "info")
				end
				renderMeds()
			end
		end
	end)
	renderCard()
	renderChip()
	renderMeds()
end

return Tracker
