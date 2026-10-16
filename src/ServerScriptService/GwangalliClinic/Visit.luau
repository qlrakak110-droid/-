-- GwangalliClinic/Visit: one patient's clinic visit, server-authoritative (state machine, timers, distance
-- and step checks; the client's minigames are flavour only).
--
--   ticket → desk_wait → desk_called → desk (접수 · 문진표) → consult_wait → consult_called → consult
--   (진찰 → 진단 → 치료 계획) → treat_go → treat (Health 의 주사 처치: 박선생 연출 · 결제 · 완치) →
--   [iv_go → iv (주사실 수액)] → pay_go (수납: 영수증 · 추가 서비스 결제) → [pharm_go → pharm_wait →
--   pharm_ready (약국 · 복약 안내 · 복약 시작)] → done
--   need_money: Health 처치비가 모자라면 멈춤 → ATM 다녀와서 창구에서 이어서 (Config.Wait.MoneyHold)
-- Exits: cancel (free before treatment; after it the unpaid part becomes d.health.debt like Health's own
-- ambulance debt), walking out (Config.Treat.UnpaidGrace), leaving the game, collapse / KO.
-- Money: Health ops charge their own price (G.HEALTH) + debt; our receipt itemises exactly that amount.

local Players = game:GetService("Players")

local Visit = {}

local K: any
local S: any
local C: any
local Bridge: any
local Site: any
local Net: any
local Queue: any
local Store: any
local Patient: any

local visits: { [Player]: any } = {}
local seq = 0

local WINDOWS = { "Win1", "Win2" }
local BEDS = {
	TreatBed1 = { mattress = "Mattress1", pillow = "Pillow1", bag = "IVBag1" },
	TreatBed2 = { mattress = "Mattress2", pillow = "Pillow2", bag = "IVBag2" },
}
local EMS_TRANSIT = Vector3.new(-465.3, 9.6, 304.5)

local function now(): number
	return os.clock()
end

local function log(...)
	if C.Debug then
		print("[GwangalliClinic/Visit]", ...)
	end
end

function Visit.get(player: Player): any?
	return visits[player]
end

function Visit.all(): { [Player]: any }
	return visits
end

local function setTreating(player: Player, on: boolean)
	local ch = player.Character
	if ch then
		ch:SetAttribute(S.NAMES.AttrTreating, on)
	end
end

local function targetOf(v: any): string?
	local st = v.step
	if st == "desk_called" or st == "desk" then
		return if v.window then "Win" .. v.window else "Win1"
	elseif st == "consult_called" or st == "consult" then
		return "ConsultSeat"
	elseif st == "treat_go" or st == "treat" then
		return "ExamBed"
	elseif st == "iv_go" or st == "iv" then
		return v.bed or "TreatBed1"
	elseif st == "pay_go" or st == "need_money" then
		return v.payWin or "Win1"
	elseif st == "pharm_go" or st == "pharm_wait" or st == "pharm_ready" then
		return "Pharmacy"
	elseif st == "desk_wait" or st == "consult_wait" then
		return "WaitArea"
	elseif st == "chk_go" or st == "chk_result" then
		return "CheckDesk"
	end
	return nil
end

local function publicPlan(p: any): any
	return {
		id = p.id,
		title = p.title,
		sub = p.sub,
		badge = p.badge,
		op = p.op,
		treat = p.treat,
		iv = p.iv,
		total = p.total,
		extra = p.extra,
		effects = p.effects,
		warn = p.warn,
		short = p.short,
		counsel = p.counsel,
		vaccine = p.vaccine,
	}
end

local function billView(v: any): any?
	if not v.plan or not v.c then
		return nil
	end
	local rows = S.Billing.rows(v.plan, v.c, C, v.opPaid)
	local sum = S.Billing.summary(rows, C)
	local cash, bank = Bridge.balance(v.player)
	return {
		id = v.billId,
		no = string.format("%s-%04d", os.date("!%y%m%d", os.time() + 9 * 3600), (v.id * 37) % 10000),
		patient = S.mask(v.player.DisplayName),
		chartNo = v.chartNo,
		dept = (C.Depts[v.dept] or C.Depts.im).name,
		doctor = C.Doctor.name,
		date = S.dateTime(os.time()),
		rows = rows,
		sum = sum,
		paidHow = v.opHow,
		methods = { card = bank or 0, cash = cash or 0 },
		night = v.night,
		paid = v.paid == true,
	}
end

function Visit.view(v: any): any
	local st = S.STEPS[v.step] or S.STEPS.done
	local out: any = {
		id = v.id,
		ticket = v.ticket,
		dept = v.dept,
		deptName = (C.Depts[v.dept] or C.Depts.im).name,
		step = v.step,
		stepLabel = st.label,
		stage = st.stage,
		hint = st.hint,
		purpose = v.purpose,
		window = v.window,
		target = targetOf(v),
		holds = v.holds,
		chartNo = v.chartNo,
		first = v.first,
		revisit = v.revisit,
		night = v.night,
		pass = v.pass,
		prio = v.prio,
		kind = v.kind,
		symptoms = v.symptoms,
		health = Patient.view(v.player),
	}
	if v.step == "desk_wait" then
		out.place, out.eta = Queue.place(v.player, "desk")
	elseif v.step == "consult_wait" then
		out.place, out.eta = Queue.place(v.player, "consult")
	end
	if v.exams then
		out.exams = v.exams
		out.examIdx = v.examIdx
		out.vitals = v.shown
	end
	if v.dx then
		out.dx = v.dx
	end
	if v.plans and v.step == "consult" then
		local ps = {}
		for _, p in v.plans do
			table.insert(ps, publicPlan(p))
		end
		out.plans = ps
		out.canPlanIn = math.max(0, math.ceil(C.Wait.MinConsult - (now() - (v.enteredAt or now()))))
	end
	if v.plan then
		out.plan = publicPlan(v.plan)
	end
	if v.iv then
		out.iv = { seconds = v.iv.seconds, progress = v.iv.progress, speed = v.iv.speed, bed = v.bed, bag = BEDS[v.bed or ""] and BEDS[v.bed].bag or nil }
	end
	if v.step == "pay_go" or v.step == "need_money" or v.paid then
		out.bill = billView(v)
	end
	if v.need then
		out.need = v.need
	end
	if v.rx then
		out.rx = v.rx
	end
	if v.chk and K.Checkup then
		out.chk = K.Checkup.viewOf(v)
	end
	return out
end

function Visit.push(v: any)
	if v.player.Parent == Players then
		Net.fire(v.player, { kind = "visit", visit = Visit.view(v) })
	end
end

local function setStep(v: any, step: string)
	v.step = step
	v.stepAt = now()
	Visit.push(v)
end
Visit.setStep = setStep

local function callBanner(v: any, to: string, text: string)
	Net.fire(v.player, { kind = "call", to = to, number = v.ticket, window = v.window, text = text, target = targetOf(v) })
end

-------------------------------------------------------------------------------------------------
-- lifecycle
-------------------------------------------------------------------------------------------------
-- Creates a visit (one per player). opts = { dept, prio, purpose? }
function Visit.create(player: Player, dept: string, opts: any?): any
	seq += 1
	local o = opts or {}
	local chart, created = Store.chart(player)
	local revisit = (not created) and chart.last > 0 and (os.time() - chart.last) <= C.Fees.RevisitDays * 86400
	local v = {
		id = seq,
		player = player,
		uid = player.UserId,
		ticket = Queue.ticket(),
		dept = dept,
		purpose = o.purpose,
		step = "desk_wait",
		stepAt = now(),
		createdAt = now(),
		holds = 0,
		chartNo = chart.no,
		first = created or chart.visits == 0,
		revisit = revisit,
		night = S.isNight(),
		pass = Bridge.hasPass(player),
		prio = o.prio == true,
		kind = Bridge.illness(player),
		fatigue0 = math.floor(Bridge.fatigue(player) + 0.5),
		kind0 = Bridge.illness(player),
		mult0 = (Bridge.status(player) or {}).mult or 1,
		billId = tostring(seq) .. "-" .. tostring(math.random(1000, 9999)),
	}
	visits[player] = v
	return v
end

local function cleanup(v: any)
	local p = v.player
	Queue.leave(p)
	if v.window then
		Site.setAct("desk" .. v.window, "teller", 0)
	end
	if v.seated and p.Parent == Players then
		Site.unseat(p)
	end
	Site.unlie(p)
	for _, a in { "ExamBed", "TreatBed1", "TreatBed2", "ConsultSeat" } do
		Site.release(a, p)
	end
	if v.bed then
		Site.setBed(v.bed, "")
	end
	if v.step == "consult" then
		Site.setAct("doctor", "idle", 0)
	end
	setTreating(p, false)
	if visits[p] == v then
		visits[p] = nil
	end
	Queue.mark()
end

-- what the patient owes us right now if they leave (Health ops are paid at treatment time)
local function dueNow(v: any): number
	if v.paid or not v.plan then
		return 0
	end
	if v.step == "pay_go" then
		local rows = S.Billing.rows(v.plan, v.c, C, v.opPaid)
		return S.Billing.summary(rows, C).dueNew
	elseif v.step == "iv" and (v.plan.extra or 0) > 0 then
		return v.plan.extra
	end
	return 0
end
Visit.dueNow = dueNow

-- ends the visit. reason = "done" | "cancel" | "walkout" | "leave" | "collapse" | "timeout" | "hold"
function Visit.finish(v: any, reason: string, note: string?)
	if v.finished then
		return
	end
	v.finished = true
	local p = v.player
	local due = dueNow(v)
	if due > 0 and reason ~= "done" then
		Bridge.addDebt(p, due)
		Store.addMirrorDebt(p, due)
		v.deferred = (v.deferred or 0) + due
		if p.Parent == Players then
			Bridge.notify(p, "warn", string.format("미납 진료비 %s", S.won(due)), "다음 진료 · 수납 때 (또는 구급차 진료비에) 함께 청구돼요")
		end
	end
	local treated = v.opPaid ~= nil or v.delivered == true
	if treated then
		local chart = Store.chart(p)
		chart.visits += 1
		chart.last = os.time()
		chart.lastDx = v.kind0 or ""
		Store.addHistory(p, {
			t = os.time(),
			dept = v.dept,
			dx = v.dx and v.dx.name or "",
			code = v.dx and v.dx.code or "",
			plan = v.plan and v.plan.title or "",
			paid = (v.opPaid or 0) + (v.extraPaid or 0),
		})
	end
	cleanup(v)
	if p.Parent == Players then
		local st = Bridge.status(p) or {}
		Net.fire(p, {
			kind = "done",
			reason = reason,
			note = note,
			summary = {
				ticket = v.ticket,
				dx = v.dx and v.dx.name or nil,
				kindBefore = v.kind0,
				kindAfter = Bridge.illness(p),
				fatigueBefore = v.fatigue0,
				fatigueAfter = math.floor(Bridge.fatigue(p) + 0.5),
				multBefore = v.mult0,
				multAfter = st.mult or 1,
				paid = (v.opPaid or 0) + (v.extraPaid or 0),
				deferred = v.deferred or 0,
				rx = v.rx ~= nil and reason == "done",
				treated = treated,
			},
			health = Patient.view(p),
			meds = Patient.medsView(p),
		})
	end
	log("visit", v.id, "finished:", reason)
end

-------------------------------------------------------------------------------------------------
-- queue callbacks
-------------------------------------------------------------------------------------------------
local function onDeskCall(player: Player, entry: any, w: number)
	local v = visits[player]
	if not v or v.step ~= "desk_wait" or entry.n ~= v.ticket then
		Queue.releaseWindow(w)
		return
	end
	v.window = w
	v.calledAt = now()
	v.lastCall = now()
	Site.setAct("desk" .. w, "beckon", v.uid)
	setStep(v, "desk_called")
	callBanner(v, "desk", string.format("🔔 딩동! %s번 %s님, %d번 창구로 와 주세요", S.ticket(v.ticket), S.mask(player.DisplayName), w))
end

local function onConsultCall(player: Player, entry: any)
	local v = visits[player]
	if not v or v.step ~= "consult_wait" or entry.n ~= v.ticket then
		Queue.releaseRoom()
		return
	end
	v.calledAt = now()
	v.lastCall = now()
	setStep(v, "consult_called")
	callBanner(v, "consult", string.format("🔔 딩동! %s번 %s님, %s로 들어오세요", S.ticket(v.ticket), S.mask(player.DisplayName), C.Doctor.room))
end

-------------------------------------------------------------------------------------------------
-- helpers for handlers
-------------------------------------------------------------------------------------------------
local fail = function(code: string, ...: any): any
	return Net.fail(code, ...)
end

local function ready(player: Player): any?
	if not Bridge.profile(player) then
		return fail("loading")
	end
	if player:GetAttribute("GwCollapse") == true then
		return fail("collapse")
	end
	if Bridge.isRiding(player) then
		return fail("riding")
	end
	return nil
end

local function farMsg(anchor: string): any
	local a = Site.anchors[anchor]
	local label = a and a:GetAttribute(S.NAMES.AttrLabel) or "해당 장소"
	return Net.fail("far", tostring(label))
end

local function examResult(v: any, kind: string): any
	local vt = v.vitals
	if kind == "temp" then
		local cls, tone = S.Medical.tempClass(vt.temp)
		return { temp = vt.temp, tempClass = cls, tempTone = tone }
	elseif kind == "throat" then
		return { throat = vt.throat }
	elseif kind == "stetho" then
		return { lung = vt.lung }
	elseif kind == "bp" then
		local cls, tone = S.Medical.bpClass(vt.sys, vt.dia)
		return { sys = vt.sys, dia = vt.dia, pulse = vt.pulse, spo2 = vt.spo2, bpClass = cls, bpTone = tone }
	elseif kind == "palp" then
		return { belly = vt.belly }
	elseif kind == "talk" then
		local hv = Patient.view(v.player)
		local work = if hv.workSec >= 60 then S.dur(hv.workSec) else "기록 없음"
		return { talk = string.format("쉬지 않고 일한 시간 %s · 피로도 %d", work, hv.fatigue) }
	end
	return {}
end

local function buildDx(v: any)
	local p = v.player
	local hv = Patient.view(p)
	local kind = S.kind(Bridge.illness(p))
	v.kind = kind and kind.id or nil
	local med = if kind then kind.med else S.Medical.HEALTHY(hv.fatigue)
	local symLabels = {}
	for _, id in v.symptoms or {} do
		table.insert(symLabels, S.Medical.SYMPTOMS[id] or id)
	end
	local H = S.H() or {}
	local svc = H.services or {}
	local fat = H.fatigue or {}
	v.dx = {
		name = med.dx,
		code = med.code,
		icon = kind and kind.icon or "🩺",
		kindName = kind and kind.name or nil,
		find = if kind then med.lines.find else med.find,
		treatLine = if kind then med.lines.treat else nil,
		after = if kind then med.lines.after else nil,
		cause = hv.cause,
		advice = hv.advice,
		fatigue = hv.fatigue,
		riskPct = hv.riskPct,
		tier = hv.tier,
		mult = hv.mult,
		symptoms = symLabels,
		vacBlocked = v.dept == "vac" and kind ~= nil,
	}
	v.c = {
		dept = v.dept,
		kind = v.kind,
		kindName = kind and kind.name or nil,
		kindIcon = kind and kind.icon or nil,
		kindFee = kind and kind.fee or 0,
		kindCure = kind and kind.cure or "",
		treat = if kind then med.treat else nil,
		fatigue = hv.fatigue,
		debt = hv.debt,
		night = v.night,
		revisit = v.revisit,
		vitaminFee = (svc.vitamin and svc.vitamin.fee) or 30000,
		vitaminName = (svc.vitamin and svc.vitamin.name) or "영양주사",
		vitaminRest = fat.vitamin or 40,
		cured = fat.cured or 50,
		checkupFee = (svc.checkup and svc.checkup.fee) or 10000,
		canVitamin = hv.fatigue >= 5,
	}
	v.plans = S.Billing.plans(v.c, C)
	local cash, bank = Bridge.balance(p)
	local best = math.max(cash or 0, bank or 0)
	for _, pl in v.plans do
		-- Health ops need one account that covers the whole fee (bank first, then cash)
		if pl.op and pl.opFee > best then
			pl.short = string.format("잔액 부족 · %s 필요", S.won(pl.opFee))
		end
	end
end

local function pickIVBed(player: Player): string?
	local emsNear = false
	for _, pl in Players:GetPlayers() do
		local ch = pl.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		if ch and r and r:IsA("BasePart") and ch:GetAttribute("GwEmsPatient") and (r.Position - EMS_TRANSIT).Magnitude < 10 then
			emsNear = true
		end
	end
	local order = if emsNear then { "TreatBed2", "TreatBed1" } else { "TreatBed1", "TreatBed2" }
	for _, b in order do
		if Site.free(b, player) and Site.reserve(b, player) then
			return b
		end
	end
	return nil
end

local function afterTreatment(v: any)
	if v.finished then
		return
	end
	local p = v.player
	Site.release("ExamBed", p)
	if v.plan and v.plan.iv then
		v.bed = pickIVBed(p)
		setTreating(p, false)
		setStep(v, "iv_go")
		Net.line(p, "nurse", if v.bed then string.format("수액은 주사실에서 맞을게요. %s로 가 주세요.", (Site.anchors[v.bed] and Site.anchors[v.bed]:GetAttribute(S.NAMES.AttrLabel)) or "주사실") else "주사실 침대가 다 차 있어요. 주사실 앞에서 잠깐만 기다려 주세요.")
	else
		setTreating(p, false)
		setStep(v, "pay_go")
		Net.line(p, "nurse", S.Medical.line("nurse_press"))
	end
end

-------------------------------------------------------------------------------------------------
-- ops
-------------------------------------------------------------------------------------------------
local function opHello(player: Player, _p: any): any
	local v = visits[player]
	local d = Store.get(player)
	local H = S.H() or {}
	local svc = H.services or {}
	return {
		ok = true,
		visit = if v then Visit.view(v) else nil,
		health = Patient.view(player),
		meds = Patient.medsView(player),
		chart = d.chart,
		report = d.report,
		fees = {
			vitamin = svc.vitamin and svc.vitamin.fee or nil,
			checkup = svc.checkup and svc.checkup.fee or nil,
			vaccine = C.Fees.Vaccine,
			consult = C.Fees.ConsultFirst,
		},
		night = S.isNight(),
		pass = Bridge.hasPass(player),
		ward = K.Ward and K.Ward.viewOf(player) or nil,
	}
end

local function opTicket(player: Player, p: any): any
	local bad = ready(player)
	if bad then
		return bad
	end
	local dept = S.oneOf(p.dept, C.Depts.Order)
	if not dept then
		return fail("bad")
	end
	local cur = visits[player]
	if cur then
		return fail("hasVisit", S.ticket(cur.ticket))
	end
	if not Site.near(player, "Kiosk", C.Reach.Kiosk) and not (dept == "chk" and Site.near(player, "CheckDesk", C.Reach.CheckDesk)) then
		return farMsg("Kiosk")
	end
	local kindId = Bridge.illness(player)
	local rerouted = false
	if kindId and dept ~= "im" then
		dept = "im"
		rerouted = true
	end
	if dept == "chk" then
		return K.Checkup.begin(player, "kiosk")
	end
	local hv = Patient.view(player)
	local prio = kindId ~= nil and (kindId == "burnout" or (hv.collapseIn ~= nil and hv.collapseIn < 240))
	local v = Visit.create(player, dept, { prio = prio })
	Queue.joinDesk(player, v.ticket, prio, v.pass)
	Patient.protect(player)
	Visit.push(v)
	return { ok = true, visit = Visit.view(v), ticket = v.ticket, rerouted = rerouted }
end

-- the patient reached the called window and pressed "접수하기"
local function opDesk(player: Player, _p: any): any
	local v = visits[player]
	if not v then
		return fail("noVisit")
	end
	if v.step ~= "desk_called" and v.step ~= "desk" then
		return fail("step")
	end
	local win = "Win" .. tostring(v.window or 1)
	if not Site.near(player, win, C.Reach.Window) then
		return farMsg(win)
	end
	if v.step == "desk_called" then
		Site.setAct("desk" .. v.window, "talk", v.uid)
		setStep(v, "desk")
	end
	return { ok = true, visit = Visit.view(v) }
end

local function opRegister(player: Player, p: any): any
	local v = visits[player]
	if not v then
		return fail("noVisit")
	end
	if v.step ~= "desk" then
		return fail("step")
	end
	if not Site.near(player, "Win" .. tostring(v.window or 1), C.Reach.Window + 4) then
		return farMsg("Win" .. tostring(v.window or 1))
	end
	local purpose = S.oneOf(p.purpose, { "ill", "tired", "general", "vaccine" }) or "general"
	local symptoms = {}
	if type(p.symptoms) == "table" then
		for _, id in p.symptoms do
			if type(id) == "string" and S.Medical.SYMPTOMS[id] and not table.find(symptoms, id) and #symptoms < 6 then
				table.insert(symptoms, id)
			end
		end
	end
	if #symptoms == 0 then
		local hv = Patient.view(player)
		for _, id in hv.symptoms or {} do
			table.insert(symptoms, id)
		end
	end
	v.purpose = purpose
	v.symptoms = symptoms
	-- the visit purpose can move a healthy patient between 내과 / 가정의학과 / 예방접종
	if not Bridge.illness(player) then
		if purpose == "vaccine" then
			v.dept = "vac"
		elseif purpose == "tired" and v.dept == "im" then
			v.dept = "fm"
		end
	end
	local w = v.window
	if w then
		Queue.releaseWindow(w)
		Site.setAct("desk" .. w, "teller", 0)
	end
	Queue.joinConsult(player, v.ticket, v.dept, v.prio, v.pass)
	setStep(v, "consult_wait")
	Net.line(player, "desk", S.Medical.line("desk_done", (C.Depts[v.dept] or C.Depts.im).name, if v.prio then "응급 우선 순서" else "진료 대기"), { name = C.Staff["desk" .. tostring(w or 1)] and C.Staff["desk" .. tostring(w or 1)].name or "원무과" })
	return { ok = true, visit = Visit.view(v) }
end

local function opEnter(player: Player, _p: any): any
	local v = visits[player]
	if not v then
		return fail("noVisit")
	end
	if v.step == "consult" then
		return { ok = true, visit = Visit.view(v) }
	end
	if v.step ~= "consult_called" then
		return fail("step")
	end
	if not Site.near(player, "ConsultSeat", C.Reach.Seat) then
		return farMsg("ConsultSeat")
	end
	local bad = ready(player)
	if bad then
		return bad
	end
	if not Site.free("ConsultSeat", player) then
		return fail("seatTaken")
	end
	Site.reserve("ConsultSeat", player)
	if Site.seats.ConsultSeat then
		Site.sit(player, "ConsultSeat")
		v.seated = true
	end
	setTreating(player, true)
	v.enteredAt = now()
	v.kind = Bridge.illness(player)
	local hv = Patient.view(player)
	local kind = S.kind(v.kind)
	local med = if kind then kind.med else S.Medical.HEALTHY(hv.fatigue)
	v.vitals = S.Medical.vitals(v.id * 7919 + (v.uid % 100000), hv.fatigue, v.kind)
	local exams = table.clone(med.exams)
	if v.dept == "vac" and not kind then
		exams = { "temp", "bp" }
	end
	v.exams = exams
	v.examIdx = 1
	v.shown = {}
	v.lastExam = now()
	Site.setAct("doctor", "listen", v.uid)
	if K.state then
		K.state:SetAttribute("Mon_consult", string.format("%s · %s · %s", S.mask(player.DisplayName), if v.revisit then "재진" else "초진", (C.Depts[v.dept] or C.Depts.im).name))
	end
	setStep(v, "consult")
	return { ok = true, visit = Visit.view(v), greet = S.Medical.GREET[v.dept] or S.Medical.GREET.im }
end

local function opExam(player: Player, p: any): any
	local v = visits[player]
	if not v or v.step ~= "consult" then
		return fail("step")
	end
	local kind = S.oneOf(p.kind, { "temp", "throat", "stetho", "bp", "palp", "talk" })
	if not kind then
		return fail("bad")
	end
	if v.examIdx > #v.exams then
		return { ok = true, visit = Visit.view(v), done = true }
	end
	if v.exams[v.examIdx] ~= kind then
		return fail("order")
	end
	if now() - (v.lastExam or 0) < C.Wait.ExamGap then
		return fail("tooSoon")
	end
	v.lastExam = now()
	local res = examResult(v, kind)
	for k2, val in res do
		v.shown[k2] = val
	end
	v.examIdx += 1
	local done = v.examIdx > #v.exams
	if done then
		buildDx(v)
		Site.setAct("doctor", "talk", v.uid)
	end
	Visit.push(v)
	return { ok = true, result = res, done = done, visit = Visit.view(v) }
end

local function opPlan(player: Player, p: any): any
	local v = visits[player]
	if not v or v.step ~= "consult" or not v.plans then
		return fail("step")
	end
	if now() - (v.enteredAt or now()) < C.Wait.MinConsult then
		return fail("tooSoon")
	end
	local id = S.str(p.id, 4)
	local plan = nil
	for _, pl in v.plans do
		if pl.id == id then
			plan = pl
		end
	end
	if not plan then
		return fail("bad")
	end
	v.plan = plan
	Site.setAct("doctor", "idle", 0)
	Queue.releaseRoom()
	if v.seated then
		Site.unseat(player)
		v.seated = false
	end
	Site.release("ConsultSeat", player)
	if plan.counsel then
		-- 상담만: 생활습관 처방 (질병 위험도 x CounselRiskFactor), 수납에서 진찰료
		local r = Bridge.risk(player)
		if r > 0 then
			Bridge.setRisk(player, r * C.Treat.CounselRiskFactor)
		end
		v.delivered = true
		setTreating(player, false)
		setStep(v, "pay_go")
		Net.line(player, "doctor", if v.kind then "알겠어요. 대신 무리하면 쓰러질 수 있어요. 아프면 꼭 다시 오세요." else "생활습관 처방전 드릴게요. 잘 자고 잘 먹는 게 제일이에요!")
		return { ok = true, visit = Visit.view(v) }
	end
	if plan.op and plan.short then
		v.need = plan.opFee
		v.needAt = now()
		setTreating(player, false)
		setStep(v, "need_money")
		Net.line(player, "doctor", string.format("진료비 %s 이 필요한데 잔액이 모자라요. ATM 에서 찾아 오시면 바로 치료해 드릴게요.", S.won(plan.opFee)))
		return { ok = true, visit = Visit.view(v) }
	end
	setStep(v, "treat_go")
	Net.line(player, "doctor", if plan.vaccine then "예진 괜찮네요. 옆 진찰대에서 박선생님이 접종해 드릴 거예요." else ((v.dx and v.dx.treatLine) or "옆 진찰대로 가세요. 박선생님이 주사 놔 드릴 거예요."))
	return { ok = true, visit = Visit.view(v) }
end

local function startIV(v: any): any
	local p = v.player
	local bed = v.bed
	if not bed then
		bed = pickIVBed(p)
		v.bed = bed
	end
	if not bed then
		return fail("bedTaken")
	end
	if not Site.near(p, bed, C.Reach.Bed) then
		return farMsg(bed)
	end
	local keys = BEDS[bed]
	local ok = Site.lie(p, bed, keys.mattress, keys.pillow)
	if not ok then
		ok = Site.sit(p, bed)
		v.seated = ok
	end
	if not ok then
		return fail("error")
	end
	setTreating(p, true)
	v.iv = { seconds = v.plan.iv or C.Treat.IVSeconds, progress = 0, speed = 1, given = 0, acc = 0, total = v.plan.ivRest or 0, half = false, t0 = S.now() }
	Site.setBed(bed, string.format("%d|iv|%.2f|%d", v.uid, S.now(), v.iv.seconds))
	Site.setAct("nurse2", "iv", v.uid)
	setStep(v, "iv")
	Net.line(p, "nurse2", S.Medical.line("nurse_iv", math.floor(v.iv.seconds)), { name = C.Staff.nurse2.name })
	return { ok = true, visit = Visit.view(v) }
end

local function finishIV(v: any, early: boolean)
	local p = v.player
	local iv = v.iv
	if not iv then
		return
	end
	-- the rest of the earned relief (whole points through Health.rest)
	local earned = iv.total * math.clamp(iv.progress / math.max(1, iv.seconds), 0, 1)
	local give = math.floor(earned - iv.given + 0.5)
	if give > 0 then
		Bridge.rest(p, give)
		iv.given += give
	end
	if v.plan and v.plan.op == "vitamin" or (v.plan and (v.plan.extra or 0) > 0) then
		pcall(function()
			local h = Bridge.healthData(p)
			if h then
				h.lastVitamin = os.time()
			end
		end)
	end
	Site.unlie(p)
	if v.seated then
		Site.unseat(p)
		v.seated = false
	end
	if v.bed then
		Site.setBed(v.bed, "")
		Site.release(v.bed, p)
	end
	Site.setAct("nurse2", "clipboard", 0)
	setTreating(p, false)
	v.iv = nil
	v.delivered = true
	setStep(v, "pay_go")
	Net.line(p, "nurse2", if early then "수액은 여기까지만 할게요. 무리하지 마세요~" else S.Medical.line("nurse_iv_done"), { name = C.Staff.nurse2.name })
end

local function opTreat(player: Player, p: any): any
	local v = visits[player]
	if not v then
		return fail("noVisit")
	end
	local action = S.oneOf(p.action, { "start", "nap", "stop" })
	if not action then
		return fail("bad")
	end
	if action == "nap" then
		if v.step ~= "iv" or not v.iv then
			return fail("step")
		end
		v.iv.speed = C.Treat.NapSpeed
		local remaining = (v.iv.seconds - v.iv.progress) / C.Treat.NapSpeed
		if remaining < C.Treat.NapMinSeconds then
			v.iv.speed = math.max(1, (v.iv.seconds - v.iv.progress) / C.Treat.NapMinSeconds)
		end
		Visit.push(v)
		return { ok = true, visit = Visit.view(v) }
	elseif action == "stop" then
		if v.step ~= "iv" then
			return fail("step")
		end
		finishIV(v, true)
		return { ok = true, visit = Visit.view(v) }
	end
	-- start
	local bad = ready(player)
	if bad then
		return bad
	end
	if v.step == "iv_go" then
		return startIV(v)
	end
	if v.step ~= "treat_go" then
		return fail("step")
	end
	if not Site.near(player, "ExamBed", C.Reach.Bed) then
		return farMsg("ExamBed")
	end
	if not Site.free("ExamBed", player) then
		return fail("seatTaken")
	end
	Site.reserve("ExamBed", player)
	local plan = v.plan
	if plan.op then
		local ok, res, how = Bridge.healthOp(player, plan.op)
		if not ok then
			Site.release("ExamBed", player)
			local code = res and res.code
			if code == "insufficient" then
				v.need = plan.opFee
				v.needAt = now()
				setStep(v, "need_money")
				return { ok = false, code = "money", message = res.message or S.err("money", S.won(plan.opFee), "-", "-"), visit = Visit.view(v) }
			elseif code == "healthy" or code == "notNeeded" then
				-- the state changed meanwhile (cured elsewhere / no fatigue): counsel instead
				for _, pl in v.plans do
					if pl.counsel then
						v.plan = pl
					end
				end
				v.delivered = true
				setStep(v, "pay_go")
				return { ok = false, code = code, message = res.message or S.err("healthy"), visit = Visit.view(v) }
			end
			return { ok = false, code = code or "health", message = (res and res.message) or S.err("health") }
		end
		v.opPaid = math.floor(tonumber(res.fee) or plan.opFee)
		v.opHow = how
		v.treatUntil = now() + 5
		setTreating(player, true)
		setStep(v, "treat")
		Net.line(player, "nurse", S.Medical.line("nurse_inject"), { name = "간호사 박선생" })
		return { ok = true, visit = Visit.view(v), fee = v.opPaid }
	elseif plan.vaccine then
		local ok = Site.sit(player, "ExamBed")
		v.seated = ok
		v.treatUntil = now() + C.Treat.InjectSeconds
		v.vaccinating = true
		setTreating(player, true)
		Site.setAct("nurse", "inject", v.uid)
		setStep(v, "treat")
		Net.line(player, "nurse", S.Medical.line("nurse_vac"), { name = "간호사 박선생" })
		return { ok = true, visit = Visit.view(v) }
	end
	return fail("step")
end

-- 수납 창구: view the bill / pay (method) / defer (미납) / resume (need_money)
local function opPay(player: Player, p: any): any
	local v = visits[player]
	local action = S.oneOf(p.action, { "view", "pay", "defer", "resume" }) or "view"
	if not v then
		if K.Ward then
			return K.Ward.pay(player, p)
		end
		return fail("noVisit")
	end
	local win = Site.nearestOf(player, WINDOWS, C.Reach.Window)
	if not win then
		return farMsg("Win1")
	end
	v.payWin = win
	if action == "resume" then
		if v.step ~= "need_money" or not v.plan then
			return fail("step")
		end
		if not Bridge.canAfford(player, v.plan.opFee) then
			local cash, bank = Bridge.balance(player)
			return fail("money", S.won(v.plan.opFee), S.won(bank or 0), S.won(cash or 0))
		end
		v.need = nil
		v.plan.short = nil
		setStep(v, "treat_go")
		Net.line(player, "desk", "확인됐어요. 진료실 옆 진찰대로 가시면 바로 처치해 드릴게요.", { name = C.Staff.desk1.name })
		return { ok = true, visit = Visit.view(v) }
	end
	if v.step ~= "pay_go" then
		return fail("step")
	end
	local bill = billView(v)
	if action == "view" then
		Site.setAct(if win == "Win1" then "desk1" else "desk2", "talk", v.uid)
		return { ok = true, bill = bill, visit = Visit.view(v) }
	end
	if bill and type(p.bill) == "string" and p.bill ~= v.billId then
		return fail("bad")
	end
	if v.paid then
		return fail("paid")
	end
	local due = bill and bill.sum.due or 0
	local oldDebt = bill and bill.sum.oldDebt or 0
	if action == "defer" then
		local new = bill and bill.sum.dueNew or 0
		if new > 0 then
			Bridge.addDebt(player, new)
			Store.addMirrorDebt(player, new)
			v.deferred = (v.deferred or 0) + new
		end
		v.paid = true
	else
		if due > 0 then
			local method = S.oneOf(p.method, { "card", "cash" }) or C.Fees.DefaultMethod
			local label = string.format("%s 진료비", C.Venue.Name)
			local res = Bridge.charge(player, due, label, method)
			if res == "money" then
				local cash, bank = Bridge.balance(player)
				return { ok = false, code = "money", message = S.err("money", S.won(due), S.won(bank or 0), S.won(cash or 0)), bill = billView(v) }
			elseif res ~= "ok" then
				return fail(if res == "noapi" then "noMoney" elseif res == "busy" then "busy" else "error")
			end
			v.extraPaid = (v.extraPaid or 0) + due
			v.payMethod = method
			if oldDebt > 0 then
				-- our bill carried the old 미납금 row: it is settled now
				Bridge.setDebt(player, math.max(0, Bridge.debt(player) - oldDebt))
			end
		end
		v.paid = true
	end
	v.delivered = true
	Site.setAct(if win == "Win1" then "desk1" else "desk2", "give", v.uid)
	local finalBill = billView(v)
	-- 처방전 (illness plans) -> 약국
	if v.plan and v.plan.rx and v.kind0 then
		local kind = S.kind(v.kind0)
		if kind then
			local items = {}
			for _, it in kind.med.meds do
				table.insert(items, { name = it.name, generic = it.generic, dose = it.dose, times = kind.med.times, days = kind.med.days })
			end
			v.rx = {
				no = string.format("%s-%05d", os.date("!%Y%m%d", os.time() + 9 * 3600), (v.id * 131) % 100000),
				issued = S.date(os.time()),
				patient = S.mask(player.DisplayName),
				chartNo = v.chartNo,
				dxCode = (v.dx and v.dx.code) or kind.med.code,
				dxName = (v.dx and v.dx.name) or kind.med.dx,
				doctor = C.Doctor.name,
				clinic = C.Venue.Name,
				items = items,
				caution = kind.med.caution,
				ticket = v.ticket,
			}
			setStep(v, "pharm_go")
			Net.line(player, "desk", S.Medical.line("desk_paid"), { name = C.Staff.desk1.name })
			return { ok = true, bill = finalBill, rx = v.rx, visit = Visit.view(v) }
		end
	end
	Net.line(player, "desk", S.Medical.line("desk_paid_norx"), { name = C.Staff.desk1.name })
	local result = { ok = true, bill = finalBill }
	Visit.finish(v, "done")
	return result
end

local function opPharmacy(player: Player, p: any): any
	local v = visits[player]
	if not v then
		return fail("noVisit")
	end
	local action = S.oneOf(p.action, { "submit", "collect" })
	if not action then
		return fail("bad")
	end
	if not Site.near(player, "Pharmacy", C.Reach.Pharmacy) then
		return farMsg("Pharmacy")
	end
	if action == "submit" then
		if v.step ~= "pharm_go" then
			return fail("step")
		end
		local secs = C.Wait.Dispense * (if v.pass then C.Pass.WaitFactor else 1)
		v.readyAt = now() + secs
		Queue.rxSubmit(v.ticket, v.uid, secs)
		Site.setAct("pharm", "cook", v.uid)
		setStep(v, "pharm_wait")
		Net.line(player, "pharm", S.Medical.line("pharm_submit", v.ticket), { name = C.Staff.pharm.name })
		return { ok = true, visit = Visit.view(v), seconds = secs }
	end
	if v.step ~= "pharm_ready" then
		return fail("step")
	end
	Queue.rxCollect(v.ticket, v.uid)
	Site.setAct("pharm", "give", v.uid)
	if v.kind0 then
		Patient.startMeds(player, v.kind0)
	end
	local kind = S.kind(v.kind0)
	local guide = if kind then S.Medical.line("pharm_guide", kind.med.times) else ""
	local rx = v.rx
	Visit.finish(v, "done")
	return { ok = true, rx = rx, guide = guide, rest = S.Medical.line("pharm_rest"), caution = kind and kind.med.caution or nil, meds = Patient.medsView(player) }
end

local function opDose(player: Player, _p: any): any
	local ok, res = Patient.dose(player)
	if not ok then
		if res.code == "notDue" then
			return fail("notDue", res.arg)
		end
		return fail(res.code or "noMeds")
	end
	return { ok = true, dose = res, meds = Patient.medsView(player), health = Patient.view(player) }
end

local function opCancel(player: Player, _p: any): any
	local v = visits[player]
	if not v then
		return fail("noVisit")
	end
	if v.step == "treat" then
		return fail("busy")
	end
	if v.step == "iv" then
		finishIV(v, true)
	end
	Visit.finish(v, "cancel")
	return { ok = true }
end

local function opChart(player: Player, _p: any): any
	local d = Store.get(player)
	return { ok = true, chart = d.chart, history = d.history, report = d.report, meds = Patient.medsView(player), health = Patient.view(player) }
end

-------------------------------------------------------------------------------------------------
-- tick
-------------------------------------------------------------------------------------------------
local WAITING = { desk_wait = true, consult_wait = true, desk_called = true, consult_called = true, chk_go = true }

local function tickVisit(v: any, dt: number)
	local p = v.player
	if p.Parent ~= Players then
		Visit.finish(v, "leave")
		return
	end
	if v.chk then
		return -- Checkup.luau runs its own clock
	end
	local t = now()
	local W = C.Wait
	local inZone = Site.playerInZone(p)
	-- emergencies end the visit (Health's collapse / KO flows take over)
	local ch = p.Character
	if p:GetAttribute("GwCollapse") == true or (ch and ch:GetAttribute("GwKO") == true) then
		if v.step == "iv" then
			finishIV(v, true)
		end
		Visit.finish(v, "collapse", "응급 상황으로 진료가 중단됐어요")
		return
	end
	if inZone then
		v.outSince = nil
		Patient.protect(p)
	else
		v.outSince = v.outSince or t
		local away = t - v.outSince
		local due = dueNow(v)
		if due > 0 and away > C.Treat.UnpaidGrace then
			Visit.finish(v, "walkout", "수납하지 않고 병원을 떠났어요")
			return
		elseif due == 0 and away > (if WAITING[v.step] then 150 else C.Treat.UnpaidGrace + 60) then
			Visit.finish(v, "walkout", "병원을 떠나서 접수가 취소됐어요")
			return
		end
	end
	local step = v.step
	if step == "desk_called" or step == "consult_called" then
		local which = if step == "desk_called" then "desk" else "consult"
		if t - (v.calledAt or t) > W.CallTimeout then
			local holds = Queue.hold(p, which)
			v.holds = holds
			if holds > W.MaxHolds then
				Visit.finish(v, "hold", "호출에 응답하지 않아 접수가 취소됐어요")
				return
			end
			if which == "desk" and v.window then
				Site.setAct("desk" .. v.window, "teller", 0)
				v.window = nil
			end
			setStep(v, if which == "desk" then "desk_wait" else "consult_wait")
			Net.toast(p, "호출에 안 오셔서 순서가 한 칸 뒤로 밀렸어요", string.format("보류 %d/%d", holds, W.MaxHolds), "warn")
		elseif t - (v.lastCall or t) > W.CallRepeat then
			v.lastCall = t
			if which == "desk" then
				Queue.announce("desk", v.ticket, S.mask(p.DisplayName), v.window, string.format("%s번 %s님, %d번 창구로 와 주세요", S.ticket(v.ticket), S.mask(p.DisplayName), v.window or 1))
				callBanner(v, "desk", string.format("🔔 다시 불러요 · %d번 창구로 와 주세요", v.window or 1))
			else
				Queue.announce("consult", v.ticket, S.mask(p.DisplayName), nil, string.format("%s번 %s님, %s로 들어오세요", S.ticket(v.ticket), S.mask(p.DisplayName), C.Doctor.room))
				callBanner(v, "consult", string.format("🔔 다시 불러요 · %s로 들어오세요", C.Doctor.room))
			end
		end
	elseif step == "desk" then
		if t - v.stepAt > W.RegisterTimeout then
			Visit.finish(v, "timeout", "접수 시간이 지나 취소됐어요")
		end
	elseif step == "consult" then
		-- the patient stood up and walked away from the consult seat
		if v.seated and not Site.isSeatedOn(p, "ConsultSeat") and Site.dist(p, "ConsultSeat") > C.Reach.Seat + 6 then
			v.seated = false
		end
		if t - v.stepAt > W.ConsultTimeout then
			Visit.finish(v, "timeout", "진료 시간이 지나 진료가 끝났어요")
		end
	elseif step == "treat" then
		if v.treatUntil and t >= v.treatUntil then
			v.treatUntil = nil
			if v.vaccinating then
				v.vaccinating = false
				Patient.vaccinate(p)
				Site.setAct("nurse", "idle", 0)
				if v.seated then
					Site.unseat(p)
					v.seated = false
				end
				v.delivered = true
				Bridge.notify(p, "success", "예방접종 완료 💉", string.format("%d시간 동안 질병 위험도가 덜 쌓여요 · 접종 부위는 문지르지 마세요", C.Treat.VaccineHours))
			end
			afterTreatment(v)
		end
	elseif step == "iv_go" then
		if not v.bed then
			v.bed = pickIVBed(p)
			if v.bed then
				Visit.push(v)
			end
		end
	elseif step == "iv" then
		local iv = v.iv
		if iv then
			-- the patient was moved off the bed (respawn / something else)
			if not Site.isLying(p) and not (v.seated and v.bed and Site.isSeatedOn(p, v.bed)) then
				finishIV(v, true)
				return
			end
			iv.progress += dt * iv.speed
			iv.acc += dt * iv.speed
			if iv.acc >= C.Treat.SliceEvery then
				iv.acc = 0
				local earned = iv.total * math.clamp(iv.progress / math.max(1, iv.seconds), 0, 1)
				local give = math.floor(earned - iv.given)
				if give > 0 then
					Bridge.rest(p, give)
					iv.given += give
				end
			end
			if not iv.half and iv.progress >= iv.seconds / 2 then
				iv.half = true
				Net.line(p, "nurse2", S.Medical.line("nurse_iv_half"), { name = C.Staff.nurse2.name })
			end
			if iv.progress >= iv.seconds then
				finishIV(v, false)
			end
		end
	elseif step == "need_money" then
		if t - (v.needAt or t) > W.MoneyHold then
			Visit.finish(v, "timeout", "진료비가 준비되지 않아 진료가 취소됐어요 (다시 접수해 주세요)")
		end
	elseif step == "pharm_wait" then
		if Queue.rxIsReady(v.ticket, v.uid) or (v.readyAt and t >= v.readyAt + 2) then
			Site.setAct("pharm", "teller", 0)
			setStep(v, "pharm_ready")
			local text = S.Medical.line("pharm_ready", v.ticket)
			Queue.announce("pharm", v.ticket, S.mask(p.DisplayName), nil, text)
			callBanner(v, "pharm", "🔔 " .. text)
		end
	end
	-- the step a player has to walk to: give up after a long time inside the clinic too
	if (step == "treat_go" or step == "iv_go" or step == "pharm_go" or step == "pharm_ready") and t - v.stepAt > W.GoTimeout * 2 then
		Visit.finish(v, "timeout", "시간이 너무 지나 진료가 마무리됐어요")
	end
end

function Visit.init(k: any)
	K = k
	S = k.S
	C = S.Config
	Bridge = k.Bridge
	Site = k.Site
	Net = k.Net
	Queue = k.Queue
	Store = k.Store
	Patient = k.Patient
	Queue.callbacks.desk = onDeskCall
	Queue.callbacks.consult = onConsultCall
	Net.handle("hello", "ui", opHello)
	Net.handle("ticket", "act", opTicket)
	Net.handle("desk", "act", opDesk)
	Net.handle("register", "act", opRegister)
	Net.handle("enter", "act", opEnter)
	Net.handle("exam", "ui", opExam)
	Net.handle("plan", "act", opPlan)
	Net.handle("treat", "act", opTreat)
	Net.handle("pay", "money", opPay)
	Net.handle("pharmacy", "act", opPharmacy)
	Net.handle("dose", "act", opDose)
	Net.handle("cancel", "act", opCancel)
	Net.handle("chart", "ui", opChart)
end

function Visit.start()
	Players.PlayerRemoving:Connect(function(p)
		local v = visits[p]
		if v then
			pcall(Visit.finish, v, "leave")
		end
	end)
	-- a respawn breaks seats / beds: end a running IV, release the consult seat
	local function hookCharacter(p: Player)
		p.CharacterAdded:Connect(function()
			local v = visits[p]
			if not v then
				return
			end
			task.defer(function()
				if v.step == "iv" then
					finishIV(v, true)
				elseif v.step == "consult" then
					v.seated = false
					Site.release("ConsultSeat", p)
				end
			end)
		end)
	end
	for _, p in Players:GetPlayers() do
		hookCharacter(p)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	task.spawn(function()
		local last = now()
		local pushAcc = 0
		while true do
			task.wait(0.5)
			local t = now()
			local dt = math.min(2, t - last)
			last = t
			pushAcc += dt
			local treating = 0
			for _, v in visits do
				local ok, err = pcall(tickVisit, v, dt)
				if not ok then
					warn("[GwangalliClinic] visit tick:", err)
				end
				if v.step == "treat" or v.step == "iv" then
					treating += 1
				end
			end
			Queue.setTreatCount(treating)
			-- waiting patients get their place / ETA refreshed every 4 s
			if pushAcc >= 4 then
				pushAcc = 0
				for _, v in visits do
					if v.step == "desk_wait" or v.step == "consult_wait" or v.step == "iv" then
						Visit.push(v)
					end
				end
			end
		end
	end)
end

return Visit
