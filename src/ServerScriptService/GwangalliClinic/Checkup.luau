-- GwangalliClinic/Checkup: 2층 건강검진센터 코스 (server-authoritative).
--   접수 (키오스크 "건강검진" 번호표 → 2층 접수대, 또는 접수대에서 바로) → 5 stations in any order:
--     height 신장·체중 (avatar height → cm, weight from height + 근력 → BMI)
--     bp     혈압 (sit at the 자동 혈압계; numbers from the real fatigue / illness)
--     eye    시력 (Landolt C, left / right eye, the rows the patient reads → 0.1 ~ 1.5)
--     ear    청력 (L / R beeps, the ones heard → 정상 / 경도 저하)
--     ecg    심전도 (lying on the checkup bed; illness / exhaustion → 동성빈맥)
--   → 결과 상담 at the desk: Health's own "checkup" op is the charge (G.HEALTH.services.checkup.fee +
--   debt) and its advice / HealthEvent; we add the 결과지 (grade A ~ D, stored) and, for D, a direct
--   referral to the 1F 내과 queue (skips the kiosk / desk).

local Players = game:GetService("Players")

local Checkup = {}

local K: any
local S: any
local C: any
local Bridge: any
local Site: any
local Net: any
local Store: any
local Patient: any
local Visit: any

local rng = Random.new()
local locks: { [string]: { player: Player, t: number } } = {}

local STATIONS = {
	height = { label = "신장 · 체중", icon = "📏", anchor = "CheckScale" },
	bp = { label = "혈압", icon = "💓", anchor = "CheckBP" },
	eye = { label = "시력", icon = "👁️", anchor = "CheckEye" },
	ear = { label = "청력", icon = "🎧", anchor = "CheckEar" },
	ecg = { label = "심전도", icon = "📈", anchor = "CheckECG" },
}
Checkup.STATIONS = STATIONS
local DIRS = { "up", "down", "left", "right" }

local function now(): number
	return os.clock()
end

local function fail(code: string, ...: any): any
	return Net.fail(code, ...)
end

local function resultText(id: string, r: any): string
	if not r then
		return ""
	end
	if id == "height" then
		return string.format("%.1fcm · %.1fkg · BMI %.1f", r.height, r.weight, r.bmi)
	elseif id == "bp" then
		return string.format("%d/%d mmHg · 맥박 %d", r.s, r.d, r.p)
	elseif id == "eye" then
		return string.format("좌 %.1f · 우 %.1f", r.l, r.r)
	elseif id == "ear" then
		return string.format("좌 %s · 우 %s", if r.l then "정상" else "저하", if r.r then "정상" else "저하")
	elseif id == "ecg" then
		return string.format("%s · %d회/분", r.rhythm, r.rate)
	end
	return ""
end

function Checkup.viewOf(v: any): any
	local chk = v.chk
	local list = {}
	for _, id in C.Checkup.Stations do
		local st = STATIONS[id]
		table.insert(list, { id = id, label = st.label, icon = st.icon, anchor = st.anchor, done = chk.results[id] ~= nil, text = resultText(id, chk.results[id]) })
	end
	return {
		stations = list,
		cur = chk.cur and { station = chk.cur.station, challenge = chk.cur.challenge, measure = chk.cur.measure } or nil,
		left = chk.left,
		report = chk.report,
		fee = chk.fee,
	}
end

local function remaining(v: any): number
	local n = 0
	for _, id in C.Checkup.Stations do
		if not v.chk.results[id] then
			n += 1
		end
	end
	return n
end

local function unlock(player: Player)
	for id, l in locks do
		if l.player == player then
			locks[id] = nil
		end
	end
end

-------------------------------------------------------------------------------------------------
-- measurements (server numbers)
-------------------------------------------------------------------------------------------------
local function heightCm(player: Player): number
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local head = ch and ch:FindFirstChild("Head")
	local studs = 5.0
	if hum and root and root:IsA("BasePart") and head and head:IsA("BasePart") then
		local feet = root.Position.Y - root.Size.Y / 2 - hum.HipHeight
		local top = head.Position.Y + head.Size.Y / 2
		local h = top - feet
		if h > 2 and h < 12 then
			studs = h
		end
	end
	local cm = 100 + studs * 13 + ((player.UserId % 13) - 6) * 0.6
	return math.floor(math.clamp(cm, 110, 198) * 10 + 0.5) / 10
end

local function measureHeight(player: Player, hv: any): any
	local h = heightCm(player)
	local st = hv.stats or {}
	local strength = tonumber(st.strength) or 50
	local bmiT = 21 + (strength - 50) * 0.05 + ((player.UserId % 7) - 3) * 0.4 + (if hv.fatigue >= 75 then -0.6 else 0)
	bmiT = math.clamp(bmiT, 17.5, 29)
	local m = h / 100
	local w = math.floor(bmiT * m * m * 10 + 0.5) / 10
	return { height = h, weight = w, bmi = S.Medical.bmi(h, w) }
end

local function measureBP(v: any, hv: any): any
	local vt = S.Medical.vitals(v.id * 104729 + (v.uid % 1000), hv.fatigue, hv.kind)
	return { s = vt.sys, d = vt.dia, p = vt.pulse }
end

local function measureECG(v: any, hv: any): any
	local vt = S.Medical.vitals(v.id * 104729 + (v.uid % 1000), hv.fatigue, hv.kind)
	local rhythm = "정상 동리듬"
	if vt.pulse > 100 then
		rhythm = "동성빈맥 (맥박이 빨라요)"
	elseif vt.pulse < 55 then
		rhythm = "동성서맥"
	end
	return { rhythm = rhythm, rate = vt.pulse }
end

local function eyeChallenge(): any
	local seqList = {}
	for _, eye in { "l", "r" } do
		for i, row in C.Checkup.EyeRows do
			table.insert(seqList, { eye = eye, row = i, v = row, dir = DIRS[rng:NextInteger(1, 4)] })
		end
	end
	return { kind = "eye", seq = seqList }
end

local function earChallenge(): any
	local tones = {}
	local freqs = { "500Hz", "1000Hz", "2000Hz", "4000Hz" }
	local nL, nR = 0, 0
	for i = 1, C.Checkup.EarTones do
		local ear = if rng:NextNumber() < 0.5 then "L" else "R"
		-- keep both ears tested
		if i == C.Checkup.EarTones - 1 and nL == 0 then
			ear = "L"
		elseif i == C.Checkup.EarTones and nR == 0 then
			ear = "R"
		end
		if ear == "L" then
			nL += 1
		else
			nR += 1
		end
		table.insert(tones, { ear = ear, gap = math.floor(rng:NextNumber(1.2, 2.6) * 10) / 10, freq = freqs[rng:NextInteger(1, #freqs)] })
	end
	return { kind = "ear", tones = tones }
end

local function scoreEye(chal: any, answers: any): any
	local best = { l = 0.1, r = 0.1 }
	local misses = { l = 0, r = 0 }
	local stop = { l = false, r = false }
	for i, item in chal.seq do
		local a = type(answers) == "table" and answers[i] or nil
		local eye = item.eye
		if not stop[eye] then
			if a == item.dir then
				best[eye] = math.max(best[eye], item.v)
				misses[eye] = 0
			else
				misses[eye] += 1
				if misses[eye] >= 2 then
					stop[eye] = true
				end
			end
		end
	end
	return { l = best.l, r = best.r }
end

local function scoreEar(chal: any, answers: any): any
	local hit = { L = 0, R = 0 }
	local total = { L = 0, R = 0 }
	for i, tone in chal.tones do
		total[tone.ear] += 1
		local a = type(answers) == "table" and answers[i] or nil
		if a == tone.ear then
			hit[tone.ear] += 1
		end
	end
	local function ok(e: string): boolean
		return total[e] == 0 or hit[e] / total[e] >= 0.6
	end
	return { l = ok("L"), r = ok("R"), hits = hit.L + hit.R, total = total.L + total.R }
end

-------------------------------------------------------------------------------------------------
-- flow
-------------------------------------------------------------------------------------------------
-- starts a checkup course. from = "kiosk" (번호표: walk up to 2F) | "desk" (at the 2F desk)
function Checkup.begin(player: Player, from: string): any
	if Visit.get(player) then
		return fail("hasVisit", S.ticket(Visit.get(player).ticket))
	end
	if Bridge.illness(player) then
		-- 아픈 환자는 검진보다 진료 먼저 (내과로 안내)
		return { ok = false, code = "ill", message = "몸이 아프실 땐 검진보다 진료가 먼저예요. 1층 키오스크에서 내과 진료를 접수해 주세요." }
	end
	local H = S.H() or {}
	local fee = (H.services and H.services.checkup and H.services.checkup.fee or 10000) + Bridge.debt(player)
	if not Bridge.canAfford(player, fee) then
		local cash, bank = Bridge.balance(player)
		return fail("money", S.won(fee), S.won(bank or 0), S.won(cash or 0))
	end
	local v = Visit.create(player, "chk", { purpose = "checkup" })
	v.chk = { results = {}, cur = nil, startedAt = now(), fee = fee, left = #C.Checkup.Stations, report = nil }
	v.step = if from == "kiosk" then "chk_go" else "chk_course"
	v.stepAt = now()
	if from ~= "kiosk" then
		Site.setAct("check", "talk", v.uid)
		Net.line(player, "check", S.Medical.line("check_hello"), { name = C.Staff.check.name })
	end
	Visit.push(v)
	return { ok = true, visit = Visit.view(v), ticket = v.ticket }
end

local function opCheckup(player: Player, p: any): any
	local action = S.oneOf(p.action, { "start", "begin", "station", "finish", "refer", "cancel" })
	if not action then
		return fail("bad")
	end
	local v = Visit.get(player)
	if action == "refer" then
		-- D 판정: 바로 1층 내과 진료 대기열로 (위급 순서)
		if v then
			return fail("hasVisit", S.ticket(v.ticket))
		end
		if not Bridge.illness(player) then
			return fail("healthy")
		end
		local nv = Visit.create(player, "im", { prio = true })
		nv.purpose = "ill"
		nv.symptoms = Patient.view(player).symptoms
		K.Queue.joinConsult(player, nv.ticket, "im", true, nv.pass)
		Visit.setStep(nv, "consult_wait")
		return { ok = true, visit = Visit.view(nv) }
	end
	if action == "start" then
		if not Site.near(player, "CheckDesk", C.Reach.CheckDesk) then
			return Net.fail("far", "건강검진센터 접수대")
		end
		if not v then
			return Checkup.begin(player, "desk")
		end
		if not v.chk then
			return fail("hasVisit", S.ticket(v.ticket))
		end
		if v.step == "chk_go" then
			Site.setAct("check", "talk", v.uid)
			Visit.setStep(v, "chk_course")
			Net.line(player, "check", S.Medical.line("check_hello"), { name = C.Staff.check.name })
		end
		return { ok = true, visit = Visit.view(v) }
	end
	if not v or not v.chk then
		return fail("noVisit")
	end
	local chk = v.chk
	if action == "cancel" then
		unlock(player)
		Site.unlie(player)
		Site.unseat(player)
		Visit.finish(v, "cancel")
		return { ok = true }
	end
	if action == "begin" then
		if v.step ~= "chk_course" then
			return fail("step")
		end
		local id = S.oneOf(p.station, C.Checkup.Stations)
		if not id then
			return fail("bad")
		end
		if chk.results[id] then
			return fail("station")
		end
		local st = STATIONS[id]
		if not Site.near(player, st.anchor, C.Reach.Station) then
			return Net.fail("far", st.label .. " 검사 장소")
		end
		local l = locks[id]
		if l and l.player ~= player and l.player.Parent == Players and now() - l.t < C.Checkup.StationTimeout then
			return fail("stationBusy")
		end
		if chk.cur and chk.cur.station ~= id then
			locks[chk.cur.station] = nil
			Site.unlie(player)
			Site.unseat(player)
		end
		locks[id] = { player = player, t = now() }
		local hv = Patient.view(player)
		local cur: any = { station = id, t0 = now() }
		if id == "height" then
			cur.measure = measureHeight(player, hv)
		elseif id == "bp" then
			if Site.seats.CheckBP then
				Site.sit(player, "CheckBP")
			end
			cur.measure = measureBP(v, hv)
		elseif id == "eye" then
			cur.challenge = eyeChallenge()
		elseif id == "ear" then
			cur.challenge = earChallenge()
		elseif id == "ecg" then
			if not Site.lie(player, "CheckECG", "MattressECG", "PillowECG") and Site.seats.CheckECG then
				Site.sit(player, "CheckECG")
			end
			cur.measure = measureECG(v, hv)
		end
		chk.cur = cur
		Visit.push(v)
		return { ok = true, station = id, challenge = cur.challenge, measure = cur.measure, visit = Visit.view(v) }
	end
	if action == "station" then
		local cur = chk.cur
		local id = S.oneOf(p.station, C.Checkup.Stations)
		if not cur or cur.station ~= id then
			return fail("step")
		end
		if now() - cur.t0 < C.Checkup.MinStation then
			return fail("tooSoon")
		end
		local res = type(p.result) == "table" and p.result or {}
		local r: any
		if id == "eye" then
			local answers = {}
			if type(res.answers) == "table" then
				for i = 1, math.min(#res.answers, 40) do
					local a = res.answers[i]
					answers[i] = if type(a) == "string" then a else ""
				end
			end
			r = scoreEye(cur.challenge, answers)
		elseif id == "ear" then
			local answers = {}
			if type(res.answers) == "table" then
				for i = 1, math.min(#res.answers, 20) do
					local a = res.answers[i]
					answers[i] = if a == "L" or a == "R" then a else ""
				end
			end
			r = scoreEar(cur.challenge, answers)
		else
			r = cur.measure
		end
		chk.results[id] = r
		chk.cur = nil
		locks[id] = nil
		if id == "bp" then
			Site.unseat(player)
		elseif id == "ecg" then
			Site.unlie(player)
			Site.unseat(player)
		end
		chk.left = remaining(v)
		if chk.left == 0 then
			Site.setAct("check", "beckon", v.uid)
			Visit.setStep(v, "chk_result")
			Net.line(player, "check", S.Medical.line("check_done"), { name = C.Staff.check.name })
		else
			Visit.push(v)
		end
		return { ok = true, station = id, result = r, text = resultText(id, r), left = chk.left, visit = Visit.view(v) }
	end
	-- finish: 결과 상담 + Health 의 건강검진 (결제 · 조언)
	if v.step ~= "chk_result" then
		if remaining(v) > 0 then
			return fail("stations", remaining(v))
		end
		return fail("step")
	end
	if not Site.near(player, "CheckDesk", C.Reach.CheckDesk) then
		return Net.fail("far", "건강검진센터 접수대")
	end
	local ok, res = Bridge.healthOp(player, "checkup")
	if not ok then
		local code = res and res.code
		if code == "insufficient" then
			return { ok = false, code = "money", message = res.message or S.err("money", S.won(chk.fee), "-", "-") }
		end
		return { ok = false, code = code or "health", message = (res and res.message) or S.err("health") }
	end
	v.opPaid = math.floor(tonumber(res.fee) or chk.fee)
	v.delivered = true
	local hv = Patient.view(player)
	local rs = chk.results
	local report: any = {
		t = os.time(),
		date = S.date(os.time()),
		no = string.format("HC-%s-%04d", os.date("!%y%m%d", os.time() + 9 * 3600), (v.id * 53) % 10000),
		patient = S.mask(player.DisplayName),
		chartNo = v.chartNo,
		height = rs.height and rs.height.height or nil,
		weight = rs.height and rs.height.weight or nil,
		bmi = rs.height and rs.height.bmi or nil,
		bp = rs.bp,
		vision = rs.eye and { l = rs.eye.l, r = rs.eye.r } or nil,
		hearing = rs.ear and { l = rs.ear.l, r = rs.ear.r } or nil,
		ecg = rs.ecg and rs.ecg.rhythm or nil,
		ecgRate = rs.ecg and rs.ecg.rate or nil,
		fatigue = hv.fatigue,
		riskPct = hv.riskPct,
		ill = hv.kind,
		illName = hv.kindName,
		advice = type(res.advice) == "string" and string.sub(res.advice, 1, 160) or nil,
		fee = v.opPaid,
	}
	local grade, notes = S.Medical.grade(report)
	report.grade = grade
	report.notes = notes
	report.tips = hv.advice
	chk.report = report
	local d = Store.get(player)
	d.report = report
	local day = math.floor((os.time() + 9 * 3600) / 86400)
	if d.daily.day ~= day then
		d.daily.day = day
		d.daily.checkup = 0
	end
	if d.daily.checkup == 0 and C.Checkup.HappinessOncePerDay > 0 then
		d.daily.checkup = 1
		Bridge.addStats(player, { happiness = C.Checkup.HappinessOncePerDay }, "건강검진 결과 상담")
	end
	Store.markDirty(player)
	Site.setAct("check", "give", v.uid)
	v.dx = { name = "일반 건강검진", code = "Z00.0" }
	v.plan = { id = "K", title = "건강검진 코스", checkup = true }
	Visit.finish(v, "done")
	Net.fire(player, { kind = "report", report = report })
	return { ok = true, report = report }
end

function Checkup.init(k: any)
	K = k
	S = k.S
	C = S.Config
	Bridge = k.Bridge
	Site = k.Site
	Net = k.Net
	Store = k.Store
	Patient = k.Patient
	Visit = k.Visit
	Net.handle("checkup", "act", opCheckup)
end

function Checkup.start()
	Players.PlayerRemoving:Connect(function(p)
		unlock(p)
	end)
	-- course timeout / leaving the clinic
	task.spawn(function()
		while true do
			task.wait(2)
			for p, v in Visit.all() do
				if v.chk and not v.finished then
					local inZone = Site.playerInZone(p)
					if not inZone then
						v.outSince = v.outSince or now()
					else
						v.outSince = nil
					end
					if p.Parent ~= Players then
						unlock(p)
						Visit.finish(v, "leave")
					elseif (v.outSince and now() - v.outSince > 90) or now() - v.chk.startedAt > C.Checkup.CourseTimeout then
						unlock(p)
						Site.unlie(p)
						Visit.finish(v, "timeout", "건강검진 시간이 지나 코스가 취소됐어요")
					elseif v.chk.cur and now() - v.chk.cur.t0 > C.Checkup.StationTimeout then
						locks[v.chk.cur.station] = nil
						if v.chk.cur.station == "ecg" then
							Site.unlie(p)
						end
						Site.unseat(p)
						v.chk.cur = nil
						Visit.push(v)
					end
				end
			end
		end
	end)
end

return Checkup
