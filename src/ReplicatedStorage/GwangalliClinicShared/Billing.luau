-- GwangalliClinicShared/Billing: 치료 계획(plan)과 진료비 계산서·영수증 항목 (순수 계산, 서버/클라 공용).
--
-- 돈이 움직이는 길은 두 가지뿐입니다.
--   1) Health 의 처치 op (treat · vitamin · checkup): 기존 G.HEALTH 가격(질병 fee / 영양주사 / 건강검진)
--      + 미납금(d.health.debt) 을 Health 가 직접 결제합니다 (통장 먼저, 다음 현금). 영수증에서는 그 금액을
--      진찰료 · 야간 가산 · 주사료(처치료) · 원내 약제비로 "나눠서 보여줄" 뿐이고 합계는 Health 가 받은 금액과
--      정확히 같습니다.
--   2) 이 애드온의 추가 서비스 (상담만 받을 때 진찰료 · 영양수액 추가 · 예방접종 · 퇴원 수속 미납금):
--      수납 창구에서 결제수단(카드/현금)을 골라 결제합니다.
--
--   Billing.round100(n)                          100원 단위 (원 단위 절사)
--   Billing.consult(revisit, night, cfg)         -> base, nightAdd
--   Billing.plans(c, cfg) -> { plan }            c = 진료 컨텍스트 (아래)
--   Billing.rows(plan, c, cfg) -> { row }        영수증 항목 (row = {label, amount, cover, paid, note?})
--   Billing.summary(rows, cfg) -> totals         {selfTotal, insurer, nonCovered, total, paid, due}
--
-- c = { dept, kind?, kindName, kindIcon, kindFee, kindCure, treat ("inject" | "iv"), fatigue, debt, night,
--       revisit, vitaminFee, vitaminName, checkupFee, canVitamin }

local Billing = {}

function Billing.round100(n: number): number
	return math.floor((tonumber(n) or 0) / 100 + 1e-9) * 100
end
local round100 = Billing.round100

function Billing.won(n: number): string
	local v = math.floor(tonumber(n) or 0)
	local neg = v < 0
	local str = tostring(math.abs(v))
	local out = string.reverse((string.gsub(string.reverse(str), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if neg then "-" else "") .. out .. "원"
end
local won = Billing.won

function Billing.consult(revisit: boolean, night: boolean, cfg: any): (number, number)
	local F = cfg.Fees
	local base = if revisit then F.ConsultRevisit else F.ConsultFirst
	local add = if night then round100(base * F.NightAddRate) else 0
	return base, add
end

local function effectPills(...: string): { string }
	return { ... }
end

-- The plans the doctor offers (first = 권장). Every plan:
--   { id, title, sub, badge?, op = "treat" | "vitamin" | nil, treat = "inject" | "iv" | "vaccine" | nil,
--     iv = seconds?, ivRest = n, opFee = n (Health will charge, incl. 미납금), extra = n (수납 창구),
--     extraLabel?, rx = bool, cure = bool, effects = { string }, warn = string?, total = n }
function Billing.plans(c: any, cfg: any): { any }
	local F, T = cfg.Fees, cfg.Treat
	local out = {}
	local debt = math.max(0, math.floor(tonumber(c.debt) or 0))
	local base, add = Billing.consult(c.revisit == true, c.night == true, cfg)
	local function counsel(title: string, sub: string, warn: string?): any
		local extra = base + add
		return {
			id = "C",
			title = title,
			sub = sub,
			op = nil,
			treat = nil,
			ivRest = 0,
			opFee = 0,
			extra = extra,
			extraLabel = "진찰료",
			rx = false,
			cure = false,
			counsel = true,
			effects = if c.kind then effectPills("질병 그대로", "진찰료만") else effectPills("질병 위험 절반", "생활습관 처방"),
			warn = warn,
			total = extra + debt,
		}
	end
	if c.kind then
		-- 아픈 환자: Health 의 "treat" (질병 fee + 미납금) 이 실제 결제 · 완치 · 피로도 -cured
		local isIV = c.treat == "iv"
		local A = {
			id = "A",
			title = c.kindCure ~= "" and c.kindCure or "주사 + 약 처방",
			sub = if isIV then string.format("진찰대에서 수액 라인 → 주사실 수액 %d초 → 약국", T.IVSeconds) else "진찰대에서 주사 → 수납 → 약국에서 약 받기",
			badge = "권장",
			op = "treat",
			treat = if isIV then "iv" else "inject",
			iv = if isIV then T.IVSeconds else nil,
			ivRest = if isIV then T.IVIncludedRest else 0,
			opFee = c.kindFee + debt,
			extra = 0,
			rx = true,
			cure = true,
			effects = effectPills(string.format("%s 완치", c.kindName or "질병"), string.format("피로도 -%d%s", c.cured or 50, if isIV then string.format(" (+수액 -%d)", T.IVIncludedRest) else ""), "행복 +5", "약 3일분"),
			total = c.kindFee + debt,
		}
		table.insert(out, A)
		local B = {
			id = "B",
			title = (if isIV then "고농도 영양 수액으로 업그레이드" else "주사 + 영양수액 추가"),
			sub = string.format("완치 처치 + 주사실에서 %d초 영양수액 (비급여 %s 추가)", T.IVExtraSeconds, won(F.IVExtra)),
			op = "treat",
			treat = "iv",
			iv = T.IVExtraSeconds,
			ivRest = T.IVExtraRest + (if isIV then T.IVIncludedRest else 0),
			opFee = c.kindFee + debt,
			extra = F.IVExtra,
			extraLabel = "영양수액 (비급여)",
			rx = true,
			cure = true,
			effects = effectPills(string.format("%s 완치", c.kindName or "질병"), string.format("피로도 -%d", (c.cured or 50) + T.IVExtraRest + (if isIV then T.IVIncludedRest else 0)), "행복 +5", "약 3일분"),
			total = c.kindFee + debt + F.IVExtra,
		}
		table.insert(out, B)
		table.insert(out, counsel("오늘은 진찰만 받고 갈게요", "치료 없이 진찰료만 · 증상은 그대로예요", "치료하지 않으면 쓰러져서 구급차로 실려 올 수 있어요"))
		return out
	end
	if c.dept == "vac" then
		table.insert(out, {
			id = "V",
			title = F.VaccineName,
			sub = "진찰대에서 박선생이 접종 · 접종 후 15분 무리하지 않기",
			badge = "예진 통과",
			op = nil,
			treat = "vaccine",
			ivRest = 0,
			opFee = 0,
			extra = F.Vaccine,
			extraLabel = F.VaccineName .. " (비급여)",
			rx = false,
			cure = false,
			vaccine = true,
			effects = effectPills("질병 위험도 0", string.format("%d시간 면역 · 위험도 %d%% 덜 쌓임", T.VaccineHours, math.floor(T.VaccineRiskDamp * 100))),
			total = F.Vaccine + debt,
		})
	end
	if c.canVitamin then
		local vf = c.vitaminFee
		table.insert(out, {
			id = "N",
			title = c.vitaminName or "영양주사",
			sub = "진찰대에서 바로 맞는 영양주사 (Health 영양주사)",
			badge = if (c.fatigue or 0) >= 50 and c.dept ~= "vac" then "추천" else nil,
			op = "vitamin",
			treat = "inject",
			ivRest = 0,
			opFee = vf + debt,
			extra = 0,
			rx = false,
			cure = false,
			effects = effectPills(string.format("피로도 -%d", c.vitaminRest or 40), "체력 +10", "행복 +2"),
			total = vf + debt,
		})
		table.insert(out, {
			id = "M",
			title = "영양수액 (누워서 푹)",
			sub = string.format("영양주사 + 주사실에서 %d초 수액 · 비급여 %s 추가", T.IVExtraSeconds, won(F.IVExtra)),
			op = "vitamin",
			treat = "iv",
			iv = T.IVExtraSeconds,
			ivRest = T.IVExtraRest,
			opFee = vf + debt,
			extra = F.IVExtra,
			extraLabel = "영양수액 (비급여)",
			rx = false,
			cure = false,
			effects = effectPills(string.format("피로도 -%d", (c.vitaminRest or 40) + T.IVExtraRest), "체력 +10", "행복 +2"),
			total = vf + debt + F.IVExtra,
		})
	end
	table.insert(out, counsel(if c.dept == "vac" then "오늘은 상담만 받을게요" else "건강 상담 + 생활습관 처방", "진찰료만 · 질병 위험도 절반으로"))
	return out
end

-- Receipt rows of the chosen plan. `opPaid` = what the Health op actually charged (nil = not yet / none).
function Billing.rows(plan: any, c: any, cfg: any, opPaid: number?): { any }
	local F = cfg.Fees
	local rows = {}
	local debtBefore = math.max(0, math.floor(tonumber(c.debt) or 0))
	local base, add = Billing.consult(c.revisit == true, c.night == true, cfg)
	local paidOp = opPaid ~= nil
	if plan.op == "treat" then
		local fee = math.max(0, math.floor(tonumber(c.kindFee) or 0))
		local cBase = math.min(base, fee)
		local cAdd = math.min(add, fee - cBase)
		local rest = fee - cBase - cAdd
		local share = (F.PharmShare and F.PharmShare[c.kind]) or 0.4
		local pharm = round100(rest * share)
		local treat = rest - pharm
		table.insert(rows, { label = if c.revisit then "진찰료 (재진)" else "진찰료 (초진)", amount = cBase, cover = "급여", paid = paidOp })
		if cAdd > 0 then
			table.insert(rows, { label = "야간·공휴일 가산", amount = cAdd, cover = "급여", paid = paidOp })
		end
		table.insert(rows, { label = if c.treat == "iv" then "수액 처치료 · 주사료" else "주사료 (근육주사)", amount = treat, cover = "급여", paid = paidOp })
		table.insert(rows, { label = "원내 약제비 (3일분)", amount = pharm, cover = "급여", paid = paidOp })
		local debtPaid = if paidOp then math.max(0, (opPaid :: number) - fee) else debtBefore
		if debtPaid > 0 then
			table.insert(rows, { label = "지난 미납 진료비", amount = debtPaid, cover = "기타", paid = paidOp })
		end
	elseif plan.op == "vitamin" then
		local fee = math.max(0, math.floor(tonumber(c.vitaminFee) or 0))
		table.insert(rows, { label = (c.vitaminName or "영양주사") .. " (비급여)", amount = fee, cover = "비급여", paid = paidOp })
		local debtPaid = if paidOp then math.max(0, (opPaid :: number) - fee) else debtBefore
		if debtPaid > 0 then
			table.insert(rows, { label = "지난 미납 진료비", amount = debtPaid, cover = "기타", paid = paidOp })
		end
	elseif plan.counsel then
		table.insert(rows, { label = if c.revisit then "진찰료 (재진)" else "진찰료 (초진)", amount = base, cover = "급여", paid = false })
		if add > 0 then
			table.insert(rows, { label = "야간·공휴일 가산", amount = add, cover = "급여", paid = false })
		end
	elseif plan.vaccine then
		table.insert(rows, { label = plan.extraLabel or "예방접종 (비급여)", amount = plan.extra, cover = "비급여", paid = false })
	elseif plan.checkup then
		local fee = math.max(0, math.floor(tonumber(c.checkupFee) or 0))
		table.insert(rows, { label = "일반 건강검진 (비급여)", amount = fee, cover = "비급여", paid = paidOp })
		local debtPaid = if paidOp then math.max(0, (opPaid :: number) - fee) else debtBefore
		if debtPaid > 0 then
			table.insert(rows, { label = "지난 미납 진료비", amount = debtPaid, cover = "기타", paid = paidOp })
		end
	elseif plan.ward then
		table.insert(rows, { label = "응급 진료비 (구급차 이송) 미납금", amount = debtBefore, cover = "기타", paid = false })
	end
	-- our own extras (paid at the 수납 window)
	if plan.op ~= nil and (plan.extra or 0) > 0 then
		table.insert(rows, { label = plan.extraLabel or "추가 처치 (비급여)", amount = plan.extra, cover = "비급여", paid = false })
	end
	-- 미납금 on our own bills (Health ops collect it themselves)
	if plan.op == nil and not plan.ward and debtBefore > 0 then
		table.insert(rows, { label = "지난 미납 진료비", amount = debtBefore, cover = "기타", paid = false })
	end
	return rows
end

function Billing.summary(rows: { any }, cfg: any): any
	local ratio = cfg.Fees.InsurerRatio or (7 / 3)
	local selfTotal, insurer, nonCovered, other, paid, due = 0, 0, 0, 0, 0, 0
	for _, r in rows do
		local a = math.max(0, math.floor(r.amount or 0))
		if r.cover == "급여" then
			selfTotal += a
			insurer += round100(a * ratio)
		elseif r.cover == "비급여" then
			nonCovered += a
		else
			other += a
		end
		if r.paid then
			paid += a
		else
			due += a
		end
	end
	return {
		selfCovered = selfTotal, -- 급여 본인부담금
		insurer = insurer, -- 공단부담금 (표시용)
		nonCovered = nonCovered, -- 비급여
		other = other, -- 미납금 등
		patient = selfTotal + nonCovered + other, -- 환자 부담 총액
		grand = selfTotal + insurer + nonCovered + other, -- 진료비 총액
		paid = paid, -- 이미 낸 금액 (Health 처치 때 결제됨)
		due = due, -- 지금 낼 금액
	}
end

return Billing
