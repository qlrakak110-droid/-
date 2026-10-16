-- GwangalliClinic/Patient: the patient's real health state, read from the game's Health system, plus the
-- small bookkeeping the clinic adds on top of it:
--   view(player)      건강 상태 카드 (피로도 · 급여 배율 · 질병 · 원인 · 권장 조치 · 미납금 · 근무 기록)
--   work log          쉬지 않고 일한 시간 (OnShift / Job attributes, sampled every 5 s; reset after a real rest)
--                     -> the diagnosis names the cause ("GS25 광안리점 편의점 알바를 쉬지 않고 1시간 12분…")
--   medication course 약국에서 받은 약: 3 doses, each Health.rest(Meds.Rest) + risk -Meds.Risk (Health API)
--   vaccine immunity  예방접종 후 Config.Treat.VaccineHours 동안 일하면서 쌓이는 위험도의 일부를 덜어 줌
--   health mirror     illness / risk / debt copied into our store every 30 s and restored on join
--   collapse grace    Patient.protect(player): a registered patient inside the clinic keeps
--                     Config.Treat.CollapseGrace seconds before Health's 600 s collapse

local Players = game:GetService("Players")

local Patient = {}

local K: any
local S: any
local C: any
local Bridge: any
local Store: any

local lastRisk: { [Player]: number } = {}
local lastMirror: { [Player]: string } = {}

local function now(): number
	return os.time()
end

function Patient.medsView(player: Player): any?
	local m = Store.get(player).meds
	if not m then
		return nil
	end
	return {
		kind = m.kind,
		name = m.name,
		items = m.items,
		times = m.times,
		total = m.total,
		taken = m.taken,
		nextIn = math.max(0, math.floor(m.nextAt - now())),
		due = now() >= m.nextAt,
	}
end

function Patient.view(player: Player): any
	local d = Store.get(player)
	local H = S.H() or {}
	local f = Bridge.fatigue(player)
	local st = Bridge.status(player)
	local kindId = Bridge.illness(player)
	local kind = S.kind(kindId)
	local risk = Bridge.risk(player)
	local thr = Bridge.riskThreshold()
	local w = d.work or { job = "", sec = 0, night = 0 }
	local jobId = player:GetAttribute("Job")
	if type(jobId) ~= "string" or jobId == "" then
		jobId = w.job
	end
	local title, place = Bridge.jobInfo(if w.job ~= "" then w.job else jobId)
	local online = Bridge.illOnline(player)
	local collapseIn = if kind then math.max(0, Bridge.collapseAfter() - online) else nil
	local info = {
		kind = if kind then kindId else nil,
		kindName = kind and kind.name or nil,
		fatigue = f,
		riskPct = math.floor(100 * risk / math.max(1, thr) + 0.5),
		jobTitle = title,
		jobPlace = place,
		workSec = w.sec,
		nightSec = w.night,
		onShift = Bridge.onShift(player),
		collapseIn = collapseIn,
	}
	local med = if kind then kind.med else S.Medical.HEALTHY(f)
	local tier = st and st.tierLabel or ""
	local vac = d.vac and d.vac.untilT > now()
	return {
		fatigue = math.floor(f + 0.5),
		tier = tier,
		mult = st and st.mult or 1,
		risk = math.floor(risk + 0.5),
		riskPct = info.riskPct,
		kind = info.kind,
		kindName = kind and kind.name or nil,
		kindIcon = kind and kind.icon or nil,
		kindDesc = kind and kind.desc or nil,
		kindCure = kind and kind.cure or nil,
		kindFee = kind and kind.fee or nil,
		illMinutes = st and st.illness and st.illness.minutes or 0,
		collapseIn = collapseIn,
		debt = Bridge.debt(player),
		onShift = info.onShift,
		jobTitle = title,
		jobPlace = place,
		workSec = math.floor(w.sec),
		nightSec = math.floor(w.night),
		dx = med.dx,
		code = med.code,
		symptoms = med.symptoms,
		cause = S.Medical.cause(info),
		advice = S.Medical.advice(info, H),
		vaccinated = vac == true,
		vacLeft = if vac then math.floor(d.vac.untilT - now()) else 0,
		meds = Patient.medsView(player),
		pass = Bridge.hasPass(player),
		cash = select(1, Bridge.balance(player)) or 0,
		bank = select(2, Bridge.balance(player)) or 0,
		stats = st and st.stats or nil,
	}
end

-- keeps a registered patient from collapsing in the middle of the visit
function Patient.protect(player: Player)
	if not Bridge.illness(player) then
		return
	end
	Bridge.clampOnline(player, Bridge.collapseAfter() - C.Treat.CollapseGrace)
end

-------------------------------------------------------------------------------------------------
-- medication course
-------------------------------------------------------------------------------------------------
function Patient.startMeds(player: Player, kindId: string)
	local kind = S.kind(kindId)
	if not kind then
		return
	end
	local items = {}
	for _, it in kind.med.meds do
		table.insert(items, it.name)
	end
	local M = C.Meds
	Store.get(player).meds = {
		kind = kindId,
		name = string.format("%s 처방약 (%d일분)", kind.name, kind.med.days or 3),
		items = items,
		times = kind.med.times,
		total = M.Doses,
		taken = 0,
		nextAt = now(),
		untilT = now() + M.Doses * M.Every + M.Window * 2,
	}
	Store.markDirty(player)
end

-- one dose (실제 효과: 피로도 -Rest, 위험도 -Risk). Returns ok, result table.
function Patient.dose(player: Player): (boolean, any)
	local d = Store.get(player)
	local m = d.meds
	if not m then
		return false, { code = "noMeds" }
	end
	local t = now()
	if t < m.nextAt then
		return false, { code = "notDue", arg = S.dur(m.nextAt - t) }
	end
	local M = C.Meds
	m.taken += 1
	m.nextAt = t + M.Every
	Bridge.rest(player, M.Rest)
	local risk = Bridge.risk(player)
	if risk > 0 then
		Bridge.setRisk(player, math.max(0, risk - M.Risk))
	end
	local finished = m.taken >= m.total
	if finished then
		d.meds = nil
		if M.FinishHappiness > 0 then
			Bridge.addStats(player, { happiness = M.FinishHappiness }, "처방약 다 먹음")
		end
	end
	Store.markDirty(player)
	return true, { taken = m.taken, total = m.total, finished = finished, rest = M.Rest }
end

function Patient.vaccinate(player: Player)
	local d = Store.get(player)
	d.vac = { untilT = now() + math.floor(C.Treat.VaccineHours * 3600) }
	lastRisk[player] = 0
	Bridge.setRisk(player, 0)
	Store.markDirty(player)
end

-------------------------------------------------------------------------------------------------
-- tick (5 s)
-------------------------------------------------------------------------------------------------
local mirrorAcc = 0

local function tickPlayer(player: Player, dt: number, doMirror: boolean)
	if not Store.isLoaded(player) then
		return
	end
	local d = Store.get(player)
	-- work log
	local w = d.work
	local f = Bridge.fatigue(player)
	if Bridge.onShift(player) then
		w.sec += dt
		local job = player:GetAttribute("Job")
		if type(job) == "string" and job ~= "" then
			w.job = job
		end
		local HS = S.HS()
		local night = if HS and HS.isNightClock then HS.isNightClock(S.clock()) else S.isNight()
		if night then
			w.night += dt
		end
		Store.markDirty(player)
	elseif f < 20 and w.sec > 0 then
		w.sec, w.night = 0, 0 -- a real rest: the record starts over
		Store.markDirty(player)
	end
	-- vaccine immunity: take back part of the risk gained while working
	if d.vac then
		if d.vac.untilT <= now() then
			d.vac = nil
			lastRisk[player] = nil
			Store.markDirty(player)
		elseif not Bridge.illness(player) then
			local r = Bridge.risk(player)
			local prev = lastRisk[player]
			if prev and r > prev then
				local back = (r - prev) * C.Treat.VaccineRiskDamp
				r = math.max(0, r - back)
				Bridge.setRisk(player, r)
			end
			lastRisk[player] = r
		end
	end
	-- expired medication course
	if d.meds and d.meds.untilT <= now() then
		d.meds = nil
		Store.markDirty(player)
	end
	-- health mirror
	if doMirror and C.PersistHealth then
		local m = Bridge.mirror(player)
		if m then
			local key = S.encode({ m.illness and m.illness.kind or "", m.debt, math.floor((m.risk or 0) / 5) })
			if key ~= lastMirror[player] then
				lastMirror[player] = key
				d.mirror = m
				Store.markDirty(player)
			end
		end
	end
end

function Patient.init(k: any)
	K = k
	S = k.S
	C = S.Config
	Bridge = k.Bridge
	Store = k.Store
end

function Patient.start()
	-- restore the mirror once the game's profile is ready
	Store.onLoaded(function(player: Player, d: any)
		task.spawn(function()
			local t0 = os.clock()
			while player.Parent == Players and not Bridge.healthData(player) and os.clock() - t0 < 40 do
				task.wait(0.5)
			end
			if player.Parent ~= Players or not Bridge.healthData(player) then
				return
			end
			task.wait(1.5) -- after the core's own Health.onLoaded
			if C.PersistHealth and d.mirror then
				local kindId, debtAdded = Bridge.restoreMirror(player, d.mirror)
				local kind = S.kind(kindId)
				if kind then
					Bridge.notify(player, "warn", string.format("아직 %s 기운이 남아 있어요 %s", kind.name, kind.icon), string.format("%s 에서 치료받아요 🏥", C.Venue.Name))
					Bridge.setWaypoint(player, (S.H() or {}).place or "광안메디컬")
				end
				if debtAdded > 0 then
					Bridge.notify(player, "info", string.format("광안 메디컬 미납 진료비 %s", S.won(Bridge.debt(player))), "다음 진료 · 수납 때 함께 정산돼요")
				end
			end
			K.Net.fire(player, { kind = "health", health = Patient.view(player) })
		end)
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastRisk[p] = nil
		lastMirror[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			mirrorAcc += 5
			local doMirror = mirrorAcc >= 30
			if doMirror then
				mirrorAcc = 0
			end
			for _, p in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, p, 5, doMirror)
				if not ok then
					warn("[GwangalliClinic] patient tick:", err)
				end
			end
		end
	end)
end

return Patient
