-- GwangalliClinic/Desk (client): 1층 무인 키오스크 · 접수 창구 · 수납 창구.
--   kiosk     진료과 선택 (내과 · 가정의학과 · 소아청소년과 · 예방접종 · 건강검진) + 내 건강 상태 → 번호표 출력
--             (UI ticket + a paper slip sliding out of the kiosk slot, local prop)
--   접수       원무과 직원 dialogue (신분증 → 초진/재진 진료카드 → 근무 중 / 미납금 안내) → 문진표 (방문 목적 ·
--             증상 칩, the real illness pre-checked) → 접수 완료
--   수납       진료비 계산서·영수증 (항목 · 급여 본인 / 공단 / 비급여 · 이미 결제 · 낼 금액) + 결제수단 (체크카드 /
--             현금, balances) → 처방전 (교부번호, 상병코드, 처방 의약품, 용법)
--   퇴원 수속  미납 응급 진료비 receipt (no visit needed) · 입원실 wake-up card

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Desk = {}

local ctx: any
local S: any
local C: any
local Ui: any
local Col: any
local F: any
local player = Players.LocalPlayer

local kioskSheet: any
local formSheet: any
local billSheet: any
local rxSheet: any
local ticketSheet: any

local function abortIf(step: string): () -> boolean
	local token = ctx.flow
	return function()
		local v = ctx.visit
		return ctx.flow ~= token or not v or v.step ~= step
	end
end

-------------------------------------------------------------------------------------------------
-- ticket paper
-------------------------------------------------------------------------------------------------
local function printSlip()
	local kiosk = ctx.anchor("Kiosk")
	if not kiosk then
		return
	end
	local slot = kiosk.Position + Vector3.new(0, -0.2, 1.62)
	local p = Instance.new("Part")
	p.Name = "TicketSlip"
	p.Size = Vector3.new(0.5, 0.02, 0.05)
	p.Color = Color3.fromRGB(250, 250, 246)
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CFrame = CFrame.new(slot)
	p.Parent = ctx.Tracker.localFolder()
	TweenService:Create(p, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Size = Vector3.new(0.5, 0.8, 0.02), CFrame = CFrame.new(slot + Vector3.new(0, -0.4, -0.06)) }):Play()
	task.delay(6, function()
		p:Destroy()
	end)
end

local function showTicket(v: any)
	ticketSheet.clear()
	ticketSheet.title.Text = "번호표가 나왔어요"
	ticketSheet.sub.Text = C.Venue.Name .. " · 무인 접수"
	local b = ticketSheet.body
	local paper = Ui.paper(b, { LayoutOrder = 1 })
	Ui.text(paper, { Text = C.Venue.Name, Font = F.black, TextSize = 15, TextColor3 = Col.tealDD, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	Ui.text(paper, { Text = "접수 대기 번호", Font = F.med, TextSize = 13, TextColor3 = Col.sub, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })
	local num = Ui.text(paper, { Text = "000", Font = F.black, TextSize = 64, TextColor3 = Col.ink, Size = UDim2.new(1, 0, 0, 70), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3 })
	Ui.text(paper, { Text = string.format("%s · %s", v.deptName or "", S.dateTime(os.time())), Font = F.med, TextSize = 13, TextColor3 = Col.sub, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 4 })
	Ui.text(paper, { Text = if (v.place or 0) > 1 then string.format("내 앞 대기 %d명 · 약 %d초", v.place - 1, v.eta or 0) else "곧 창구에서 불러 드려요", Font = F.bold, TextSize = 14, TextColor3 = Col.tealDD, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 5 })
	if v.prio then
		Ui.text(paper, { Text = "🚑 몸 상태가 좋지 않아 우선 순서로 접수됐어요", Font = F.bold, TextSize = 13, TextColor3 = Col.red, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6 })
	end
	if v.pass then
		Ui.text(paper, { Text = C.Pass.Label, Font = F.bold, TextSize = 13, TextColor3 = Col.gold:Lerp(Col.black, 0.35), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 7 })
	end
	Ui.text(paper, { Text = "번호를 부르면 화면에 표시된 창구로 오세요", Font = F.med, TextSize = 12, TextColor3 = Col.faint, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 8 })
	-- barcode-like strip
	local bar = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 9 }, paper)
	local rng = Random.new(v.ticket or 1)
	local x = 0.18
	while x < 0.82 do
		local w = rng:NextNumber(0.003, 0.012)
		Ui.new("Frame", { BackgroundColor3 = Col.ink, BorderSizePixel = 0, Position = UDim2.fromScale(x, 0), Size = UDim2.new(w, 0, 1, 0) }, bar)
		x += w + rng:NextNumber(0.004, 0.01)
	end
	Ui.btn(b, { text = "대기실에서 기다릴게요", style = "primary", size = UDim2.new(1, 0, 0, 48), order = 2, onClick = function()
		ticketSheet.close()
	end })
	ticketSheet.open()
	-- count-up of the number
	task.spawn(function()
		local target = v.ticket or 0
		for i = 1, 12 do
			num.Text = S.ticket(math.floor(target * i / 12))
			task.wait(0.03)
		end
		num.Text = S.ticket(target)
	end)
end

-------------------------------------------------------------------------------------------------
-- kiosk
-------------------------------------------------------------------------------------------------
function Desk.openKiosk()
	if ctx.visit then
		Ui.toast(string.format("이미 %s번으로 접수돼 있어요", S.ticket(ctx.visit.ticket)), ctx.visit.stepLabel, "info")
		return
	end
	kioskSheet.clear()
	local b = kioskSheet.body
	local hv = ctx.health or {}
	kioskSheet.sub.Text = string.format("진료시간 09:00 ~ 22:00 · 야간 당직 진료 %s", if S.isNight() then "중 (야간 가산)" else "")
	Ui.healthCard(b, hv, { order = 1, compact = true })
	if hv.kind then
		local warn = Ui.card(b, { BackgroundColor3 = Color3.fromRGB(255, 244, 236), LayoutOrder = 2 })
		Ui.pad(warn, 12, 8, 12, 8)
		Ui.text(warn, { Text = string.format("%s %s 증상이 있어 내과로 바로 안내해요%s", hv.kindIcon or "🤒", hv.kindName or "", if hv.kind == "burnout" or (hv.collapseIn or 999) < 240 then " · 우선 순서" else ""), Font = F.bold, TextSize = 13, TextColor3 = Col.orange:Lerp(Col.black, 0.25), TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
	end
	Ui.text(b, { Text = "진료과를 선택하세요", Font = F.black, TextSize = 16, LayoutOrder = 3 })
	local grid = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 }, b)
	local gl = Ui.new("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 78), CellPadding = UDim2.fromOffset(12, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local _ = gl
	local board = ctx.Screens.board() or {}
	local depts = board.depts or {}
	local first: GuiObject? = nil
	for i, id in C.Depts.Order do
		local d = C.Depts[id]
		local disabled = hv.kind ~= nil and id ~= "im"
		local btn = Ui.new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = if disabled then Color3.fromRGB(240, 243, 244) else Col.white, LayoutOrder = i, Selectable = true }, grid)
		Ui.corner(btn, 14)
		Ui.stroke(btn, if id == "im" and hv.kind then Col.teal else Col.line, if id == "im" and hv.kind then 2 else 1, 0)
		Ui.text(btn, { Text = d.icon, TextSize = 28, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 40, 1, 0) })
		Ui.text(btn, { Text = d.name, Font = F.black, TextSize = 17, TextColor3 = if disabled then Col.faint else Col.ink, Position = UDim2.fromOffset(58, 12), Size = UDim2.new(1, -64, 0, 22) })
		local waitN = if id == "chk" then nil else depts[id]
		Ui.text(btn, { Text = d.sub .. (if waitN and waitN > 0 then string.format(" · 대기 %d", waitN) else ""), Font = F.med, TextSize = 12, TextColor3 = Col.sub, Position = UDim2.fromOffset(58, 38), Size = UDim2.new(1, -64, 0, 30), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		if not first and not disabled then
			first = btn
		end
		btn.Activated:Connect(function()
			if disabled then
				Ui.sound("error")
				Ui.toast("아프실 땐 내과 진료부터 받아요", nil, "warn")
				return
			end
			Ui.sound("tap")
			local res = ctx.call("ticket", { dept = id })
			if res.ok then
				kioskSheet.close()
				Ui.sound("print")
				printSlip()
				if res.rerouted then
					Ui.toast("내과로 접수했어요", "몸이 아프신 분은 내과 진료가 먼저예요", "info")
				end
				if res.visit then
					if res.visit.chk then
						Ui.toast(string.format("건강검진 %s번 · 2층 건강검진센터로 가세요", S.ticket(res.visit.ticket)), "계단 / 엘리베이터로 2층", "info")
					else
						showTicket(res.visit)
					end
				end
			end
		end)
	end
	kioskSheet.focus = first
	kioskSheet.open()
end

-------------------------------------------------------------------------------------------------
-- 접수 (원무과)
-------------------------------------------------------------------------------------------------
local function openForm(v: any)
	formSheet.clear()
	formSheet.sub.Text = string.format("%s번 · %s · 등록번호 %s", S.ticket(v.ticket), if v.first then "초진" else "재진", v.chartNo or "")
	local b = formSheet.body
	local hv = v.health or ctx.health or {}
	Ui.healthCard(b, hv, { order = 1, title = "🩺 접수 시 건강 상태" })
	Ui.text(b, { Text = "방문 목적", Font = F.black, TextSize = 15, LayoutOrder = 2 })
	local purposeRow = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 }, b)
	local pl = Ui.list(purposeRow, "h", 8)
	pcall(function()
		(pl :: any).Wraps = true
	end)
	local purpose = if hv.kind then "ill" elseif v.dept == "vac" then "vaccine" elseif (hv.fatigue or 0) >= 40 then "tired" else "general"
	local pchips = {}
	for i, pdef in S.Medical.PURPOSES do
		local locked = hv.kind ~= nil and pdef.id ~= "ill"
		local ch
		ch = Ui.chip(purposeRow, {
			text = pdef.icon .. " " .. pdef.label,
			on = pdef.id == purpose,
			order = i,
			onChange = function()
				if locked then
					ch.set(false)
					Ui.toast("아픈 증상이 있어 '몸이 아파요'로 접수해요", nil, "info")
					return
				end
				purpose = pdef.id
				for id2, c2 in pchips do
					c2.set(id2 == purpose)
				end
			end,
		})
		pchips[pdef.id] = ch
	end
	Ui.text(b, { Text = "문진표 · 지금 증상 (해당하는 것 모두)", Font = F.black, TextSize = 15, LayoutOrder = 4 })
	Ui.text(b, { Text = S.Medical.line("desk_symptoms"), Font = F.med, TextSize = 12, TextColor3 = Col.sub, LayoutOrder = 5, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
	local symRow = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6 }, b)
	local sl = Ui.list(symRow, "h", 8)
	pcall(function()
		(sl :: any).Wraps = true
	end)
	local chosen: { [string]: boolean } = {}
	for _, id in hv.symptoms or {} do
		chosen[id] = true
	end
	local chips = {}
	for i, id in S.Medical.SYMPTOM_ORDER do
		chips[id] = Ui.chip(symRow, {
			text = S.Medical.SYMPTOMS[id],
			on = chosen[id] == true,
			order = i,
			onChange = function(on)
				chosen[id] = on or nil
				if id == "none" and on then
					for id2, c2 in chips do
						if id2 ~= "none" then
							c2.set(false)
							chosen[id2] = nil
						end
					end
				elseif on and chips.none then
					chips.none.set(false)
					chosen.none = nil
				end
			end,
		})
	end
	-- life questions (real: 문진표)
	local life = Ui.card(b, { LayoutOrder = 7 })
	Ui.pad(life, 12, 10, 12, 10)
	Ui.list(life, "v", 4)
	Ui.text(life, { Text = "생활 문진", Font = F.black, TextSize = 13, TextColor3 = Col.tealDD, LayoutOrder = 1 })
	Ui.text(life, { Text = string.format("· 최근 쉬지 않고 일한 시간: %s%s", if (hv.workSec or 0) >= 60 then S.dur(hv.workSec) else "없음", if (hv.nightSec or 0) >= 60 then string.format(" (밤샘 %s)", S.dur(hv.nightSec)) else ""), Font = F.med, TextSize = 13, LayoutOrder = 2, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
	if hv.jobTitle then
		Ui.text(life, { Text = string.format("· 직업: %s%s", hv.jobTitle, if hv.jobPlace then " · " .. hv.jobPlace else ""), Font = F.med, TextSize = 13, LayoutOrder = 3, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
	end
	Ui.text(life, { Text = "· 복용 중인 약: " .. (if ctx.meds then ctx.meds.name else "없음"), Font = F.med, TextSize = 13, LayoutOrder = 4 })
	local done = false
	local submit = Ui.btn(b, { text = "📝 문진표 제출 · 접수 완료", style = "primary", size = UDim2.new(1, 0, 0, 50), order = 9, onClick = function()
		if done then
			return
		end
		local list = {}
		for _, id in S.Medical.SYMPTOM_ORDER do
			if chosen[id] then
				table.insert(list, id)
			end
		end
		local res = ctx.call("register", { purpose = purpose, symptoms = list })
		if res.ok then
			done = true
			formSheet.close()
			Ui.sound("print")
		end
	end })
	formSheet.focus = submit
	formSheet.open()
end

function Desk.beginRegister()
	local v = ctx.visit
	if not v then
		return
	end
	local res = ctx.call("desk", {})
	if not res.ok then
		return
	end
	v = ctx.visit
	if not v or v.step ~= "desk" then
		return
	end
	local who = "desk"
	local name = (C.Staff["desk" .. tostring(v.window or 1)] or C.Staff.desk1).name
	local abort = abortIf("desk")
	local hv = v.health or ctx.health or {}
	if not Ui.ask(who, S.Medical.line("desk_hello", v.ticket), { "🪪 신분증 드리기" }, { name = name, abort = abort }) then
		return
	end
	local line = if v.first then S.Medical.line("desk_first", v.chartNo or "") else S.Medical.line("desk_revisit")
	if not Ui.ask(who, line, { "네" }, { name = name, abort = abort }) then
		return
	end
	if hv.onShift then
		if not Ui.ask(who, S.Medical.line("desk_shift") .. " 퇴근하고 진료받으면 피로가 안 쌓여요.", { "알겠어요" }, { name = name, abort = abort }) then
			return
		end
	end
	if (hv.debt or 0) > 0 then
		if not Ui.ask(who, S.Medical.line("desk_debt", S.won(hv.debt)), { "네, 알겠어요" }, { name = name, abort = abort }) then
			return
		end
	end
	Ui.say(who, S.Medical.line("desk_purpose") .. " 문진표 작성 부탁드려요.", { name = name, hold = 4 })
	openForm(v)
end

-------------------------------------------------------------------------------------------------
-- 영수증
-------------------------------------------------------------------------------------------------
local function receipt(parent: Instance, bill: any, order: number)
	local paper = Ui.paper(parent, { LayoutOrder = order })
	Ui.text(paper, { Text = "진료비 계산서 · 영수증", Font = F.black, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	Ui.text(paper, { Text = string.format("[ 외래 ] %s", C.Venue.Name), Font = F.med, TextSize = 12, TextColor3 = Col.sub, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })
	local meta = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 }, paper)
	Ui.list(meta, "v", 0)
	Ui.row(meta, "환자 성명", bill.patient or "", { order = 1, size = 13 })
	Ui.row(meta, "등록번호", bill.chartNo or "", { order = 2, size = 13 })
	Ui.row(meta, "진료과 · 담당의", string.format("%s · %s", bill.dept or "", bill.doctor or ""), { order = 3, size = 13 })
	Ui.row(meta, "진료일", bill.date or "", { order = 4, size = 13 })
	Ui.row(meta, "영수증 번호", bill.no or "", { order = 5, size = 13 })
	Ui.new("Frame", { BackgroundColor3 = Col.ink, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), LayoutOrder = 4 }, paper)
	local head = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 5 }, paper)
	Ui.text(head, { Text = "항목", Font = F.black, TextSize = 12, TextColor3 = Col.sub, Size = UDim2.new(0.46, 0, 1, 0) })
	Ui.text(head, { Text = "본인부담", Font = F.black, TextSize = 12, TextColor3 = Col.sub, Size = UDim2.new(0.18, 0, 1, 0), Position = UDim2.fromScale(0.46, 0), TextXAlignment = Enum.TextXAlignment.Right })
	Ui.text(head, { Text = "공단부담", Font = F.black, TextSize = 12, TextColor3 = Col.sub, Size = UDim2.new(0.18, 0, 1, 0), Position = UDim2.fromScale(0.64, 0), TextXAlignment = Enum.TextXAlignment.Right })
	Ui.text(head, { Text = "비급여", Font = F.black, TextSize = 12, TextColor3 = Col.sub, Size = UDim2.new(0.18, 0, 1, 0), Position = UDim2.fromScale(0.82, 0), TextXAlignment = Enum.TextXAlignment.Right })
	local ratio = C.Fees.InsurerRatio
	for i, r in bill.rows or {} do
		local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 10 + i }, paper)
		Ui.text(row, { Text = r.label .. (if r.paid then " ✓" else ""), Font = F.med, TextSize = 13, Size = UDim2.new(0.46, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
		local cov = r.cover == "급여"
		local nonCov = r.cover == "비급여"
		Ui.text(row, { Text = if cov or r.cover == "기타" then S.won(r.amount) else "", Font = F.bold, TextSize = 13, Size = UDim2.new(0.18, 0, 1, 0), Position = UDim2.fromScale(0.46, 0), TextXAlignment = Enum.TextXAlignment.Right })
		Ui.text(row, { Text = if cov then S.won(S.Billing.round100(r.amount * ratio)) else "", Font = F.med, TextSize = 13, TextColor3 = Col.sub, Size = UDim2.new(0.18, 0, 1, 0), Position = UDim2.fromScale(0.64, 0), TextXAlignment = Enum.TextXAlignment.Right })
		Ui.text(row, { Text = if nonCov then S.won(r.amount) else "", Font = F.bold, TextSize = 13, Size = UDim2.new(0.18, 0, 1, 0), Position = UDim2.fromScale(0.82, 0), TextXAlignment = Enum.TextXAlignment.Right })
	end
	Ui.new("Frame", { BackgroundColor3 = Col.line, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), LayoutOrder = 60 }, paper)
	local sum = bill.sum or {}
	local tot = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 61 }, paper)
	Ui.list(tot, "v", 0)
	Ui.row(tot, "진료비 총액", S.won(sum.grand or 0), { order = 1, size = 13 })
	Ui.row(tot, "공단 부담 총액", S.won(sum.insurer or 0), { order = 2, size = 13 })
	Ui.row(tot, "환자 부담 총액", S.won(sum.patient or 0), { order = 3, size = 14, rightFont = F.black })
	if (sum.paid or 0) > 0 then
		local how = if bill.paidHow == "card" then "체크카드" elseif bill.paidHow == "cash" then "현금" elseif bill.paidHow == "mixed" then "통장 + 현금" else "결제"
		Ui.row(tot, "이미 납부한 금액 (처치 시 " .. how .. ")", S.won(sum.paid), { order = 4, size = 13, rightColor = Col.green })
	end
	Ui.row(tot, if bill.paid then "납부한 금액" else "납부할 금액", S.won(sum.due or 0), { order = 5, size = 17, h = 30, leftFont = F.black, leftColor = Col.ink, rightFont = F.black, rightColor = if bill.paid then Col.green else Col.red })
	if bill.night then
		Ui.text(paper, { Text = "* 야간 진료로 진찰료에 야간 가산이 적용됐어요", Font = F.med, TextSize = 11, TextColor3 = Col.faint, LayoutOrder = 70 })
	end
	if bill.paid then
		local stamp = Ui.text(paper, { Text = "수 납 완 료", Font = F.black, TextSize = 22, TextColor3 = Col.red, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 71, Rotation = -8 })
		local st = Ui.stroke(stamp, Col.red, 2, 0)
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	end
	return paper
end
Desk.receipt = receipt

local function rxPaper(parent: Instance, rx: any, order: number)
	local paper = Ui.paper(parent, { LayoutOrder = order })
	Ui.text(paper, { Text = "처 방 전", Font = F.black, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	Ui.text(paper, { Text = "[ 약국 제출용 ]", Font = F.med, TextSize = 12, TextColor3 = Col.sub, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })
	local meta = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 }, paper)
	Ui.list(meta, "v", 0)
	Ui.row(meta, "교부번호", rx.no or "", { order = 1, size = 13 })
	Ui.row(meta, "교부 연월일", rx.issued or "", { order = 2, size = 13 })
	Ui.row(meta, "환자", rx.patient or "", { order = 3, size = 13 })
	Ui.row(meta, "질병분류기호", string.format("%s · %s", rx.dxCode or "", rx.dxName or ""), { order = 4, size = 13 })
	Ui.row(meta, "의료기관 · 처방의", string.format("%s · %s", rx.clinic or "", rx.doctor or ""), { order = 5, size = 13 })
	Ui.new("Frame", { BackgroundColor3 = Col.ink, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), LayoutOrder = 4 }, paper)
	for i, it in rx.items or {} do
		local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 10 + i }, paper)
		Ui.text(row, { Text = it.name, Font = F.bold, TextSize = 14, Size = UDim2.new(0.62, 0, 0, 18) })
		Ui.text(row, { Text = it.generic or "", Font = F.med, TextSize = 11, TextColor3 = Col.sub, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(0.62, 0, 0, 16) })
		Ui.text(row, { Text = string.format("%s · %s · %d일", it.dose or "1정", it.times or "", it.days or 3), Font = F.med, TextSize = 12, TextColor3 = Col.ink, Position = UDim2.fromScale(0.62, 0), Size = UDim2.new(0.38, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = true })
	end
	if rx.caution then
		Ui.text(paper, { Text = "⚠️ " .. rx.caution, Font = F.med, TextSize = 12, TextColor3 = Col.orange:Lerp(Col.black, 0.25), TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 50 })
	end
	local stamp = Ui.text(paper, { Text = string.format("%s 의사 %s (인)", rx.clinic or "", rx.doctor or ""), Font = F.bold, TextSize = 12, TextColor3 = Col.red, TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 51 })
	local _ = stamp
	return paper
end
Desk.rxPaper = rxPaper

local function methodButtons(parent: Instance, bill: any, onPay: (string) -> (), onDefer: (() -> ())?)
	local m = bill.methods or {}
	local due = bill.sum and bill.sum.due or 0
	local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = 80 }, parent)
	local card = Ui.btn(row, { text = string.format("💳 체크카드\n통장 %s", S.won(m.card or 0)), style = if (m.card or 0) >= due then "primary" else "disabled", size = UDim2.new(0.5, -5, 1, 0), textSize = 14, onClick = function()
		onPay("card")
	end })
	Ui.btn(row, { text = string.format("💵 현금\n지갑 %s", S.won(m.cash or 0)), style = if (m.cash or 0) >= due then "dark" else "disabled", size = UDim2.new(0.5, -5, 1, 0), pos = UDim2.new(0.5, 5, 0, 0), textSize = 14, onClick = function()
		onPay("cash")
	end })
	if onDefer and (m.card or 0) < due and (m.cash or 0) < due then
		Ui.text(parent, { Text = "잔액이 모자라요. ATM에서 출금하거나, 미납으로 처리하고 다음에 낼 수 있어요.", Font = F.med, TextSize = 12, TextColor3 = Col.red, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 81 })
		Ui.btn(parent, { text = "🧾 미납으로 처리 (다음 진료 때 청구)", style = "ghost", size = UDim2.new(1, 0, 0, 44), order = 82, onClick = onDefer })
	end
	return card
end

local function showRx(rx: any)
	rxSheet.clear()
	rxSheet.title.Text = "처방전을 받았어요"
	rxSheet.sub.Text = "원내 약국에 제출하세요 · 1층 오른쪽 복도"
	rxPaper(rxSheet.body, rx, 1)
	Ui.btn(rxSheet.body, { text = "💊 약국으로 가기", style = "primary", size = UDim2.new(1, 0, 0, 48), order = 9, onClick = function()
		rxSheet.close()
	end })
	rxSheet.open()
end

function Desk.openBill()
	local res = ctx.call("pay", { action = "view" })
	if not res.ok or not res.bill then
		return
	end
	local bill = res.bill
	local name = C.Staff.desk1.name
	Ui.say("desk", S.Medical.line("desk_pay"), { name = name })
	billSheet.clear()
	billSheet.title.Text = "수납 · 진료비 계산서"
	billSheet.sub.Text = string.format("%s · %s", bill.patient or "", bill.date or "")
	receipt(billSheet.body, bill, 1)
	local due = bill.sum and bill.sum.due or 0
	local function after(r: any)
		if r.ok then
			billSheet.close()
			Ui.sound("print")
			if r.rx then
				showRx(r.rx)
			elseif r.bill then
				billSheet.clear()
				billSheet.title.Text = "영수증"
				receipt(billSheet.body, r.bill, 1)
				Ui.btn(billSheet.body, { text = "확인", style = "primary", size = UDim2.new(1, 0, 0, 48), order = 90, onClick = function()
					billSheet.close()
				end })
				billSheet.open()
			end
		end
	end
	if due > 0 then
		billSheet.focus = methodButtons(billSheet.body, bill, function(method)
			after(ctx.call("pay", { action = "pay", method = method, bill = bill.id }))
		end, function()
			after(ctx.call("pay", { action = "defer", bill = bill.id }))
		end)
	else
		billSheet.focus = Ui.btn(billSheet.body, { text = "🧾 영수증 받기", style = "primary", size = UDim2.new(1, 0, 0, 50), order = 80, onClick = function()
			after(ctx.call("pay", { action = "pay", bill = bill.id }))
		end })
	end
	billSheet.open()
end

function Desk.resume()
	local res = ctx.call("pay", { action = "resume" })
	if res.ok then
		Ui.toast("진찰대로 가서 치료받으세요", nil, "ok")
	end
end

function Desk.openWardBill()
	local res = ctx.call("pay", { action = "view" })
	if not res.ok or not res.bill then
		return
	end
	local bill = res.bill
	billSheet.clear()
	billSheet.title.Text = "퇴원 수속 · 미납 진료비"
	billSheet.sub.Text = string.format("%s · 응급 진료", bill.patient or "")
	receipt(billSheet.body, bill, 1)
	billSheet.focus = methodButtons(billSheet.body, bill, function(method)
		local r = ctx.call("pay", { action = "pay", method = method, bill = bill.id })
		if r.ok then
			billSheet.close()
			Ui.toast("퇴원 수속 완료", "미납 진료비를 모두 냈어요", "ok")
			ctx.ward = nil
			local h = ctx.health
			if h then
				h.debt = 0
				ctx.setHealth(h)
			end
		end
	end, nil)
	billSheet.open()
end

function Desk.onWard(p: any)
	if not p.wake then
		return
	end
	task.wait(1.5)
	local debt = p.debt or 0
	local line = if p.wake == "collapse" then "정신이 드세요? 쓰러지셔서 구급차로 실려 오셨어요. 이제 괜찮아요." else "정신이 드세요? 다치셔서 응급실로 오셨어요. 많이 놀라셨죠."
	if debt > 0 then
		local pick = Ui.ask("nurse2", line .. string.format(" 응급 진료비 중 %s이 미납이에요. 퇴원하실 때 1층 원무과에 들러 주세요.", S.won(debt)), { "알겠어요", "조금 더 누워 있을게요" }, { name = "입원실 간호사" })
		if pick == 2 then
			ctx.call("ward", { action = "rest" }, { quiet = true })
		end
	else
		Ui.say("nurse2", line .. " 진료비는 정산됐어요. 오늘은 무리하지 마세요.", { name = "입원실 간호사", hold = 6 })
	end
end

function Desk.onVisit(v: any, prev: any)
	-- the server moved us to the 접수 step from somewhere else (e.g. a re-call)
	if v and prev and v.step ~= prev.step and v.step ~= "desk" and formSheet.isOpen then
		formSheet.close()
	end
	if not v and prev and (formSheet.isOpen or kioskSheet.isOpen) then
		formSheet.close()
	end
end

function Desk.init(c: any)
	ctx = c
	S = c.S
	C = c.C
	Ui = c.Ui
	Col = Ui.C
	F = Ui.F
	kioskSheet = Ui.sheet("GwClinic_Kiosk", { title = "무인 접수 · 번호표", w = 560, h = 640 })
	formSheet = Ui.sheet("GwClinic_Form", { title = "문진표", w = 580, h = 660 })
	billSheet = Ui.sheet("GwClinic_Bill", { title = "수납", w = 560, h = 680 })
	rxSheet = Ui.sheet("GwClinic_Rx", { title = "처방전", w = 520, h = 620 })
	ticketSheet = Ui.sheet("GwClinic_Ticket", { title = "번호표", w = 400, h = 520 })
	local _ = player
end

return Desk
