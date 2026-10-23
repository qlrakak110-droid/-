--!nocheck
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
local Config = require("./Config")
local Billing = require("./Billing")
local Medical = require("./Medical")
local KINDS = { cold = { fee = 15000, name = "감기", cure = "주사 한 방 + 감기약 3일분", treat = "inject" }, ache = { fee = 25000, name = "몸살", cure = "해열 주사 + 근육이완제", treat = "inject" }, gastritis = { fee = 35000, name = "위염", cure = "위장약 처방 + 수액", treat = "iv" }, burnout = { fee = 45000, name = "번아웃", cure = "영양 수액 + 휴식 처방", treat = "iv" } }
local fails = 0
local function check(cond, msg) if not cond then fails += 1; print("FAIL", msg) end end
for id, k in KINDS do
  for _, night in { false, true } do
    for _, revisit in { false, true } do
      for _, debt in { 0, 7300 } do
        local c = { dept = "im", kind = id, kindName = k.name, kindFee = k.fee, kindCure = k.cure, treat = k.treat, fatigue = 88, debt = debt, night = night, revisit = revisit, vitaminFee = 30000, vitaminName = "영양주사", vitaminRest = 40, cured = 50, checkupFee = 10000, canVitamin = true }
        local plans = Billing.plans(c, Config)
        check(#plans == 3, id .. " plans " .. #plans)
        local A = plans[1]
        check(A.op == "treat" and A.opFee == k.fee + debt, id .. " A opFee")
        -- before the op
        local rows0 = Billing.rows(A, c, Config, nil)
        local s0 = Billing.summary(rows0, Config)
        -- after the op (Health charged fee + debt)
        local rows = Billing.rows(A, c, Config, k.fee + debt)
        local s = Billing.summary(rows, Config)
        check(s.paid == k.fee + debt, string.format("%s paid %d vs %d", id, s.paid, k.fee + debt))
        check(s.due == 0, id .. " due after op " .. s.due)
        local B = plans[2]
        local sB = Billing.summary(Billing.rows(B, c, Config, k.fee + debt), Config)
        check(sB.due == Config.Fees.IVExtra and sB.dueNew == Config.Fees.IVExtra, id .. " B due")
        local Cp = plans[3]
        local sC = Billing.summary(Billing.rows(Cp, c, Config, nil), Config)
        local base, add = Billing.consult(revisit, night, Config)
        check(sC.due == base + add + debt and sC.dueNew == base + add and sC.oldDebt == debt, id .. " counsel due " .. sC.due)
        if not night and not revisit and debt == 0 then
          local parts = {}
          for _, r in rows do table.insert(parts, r.label .. "=" .. r.amount) end
          print(id, table.concat(parts, ", "), "patient", s.patient, "insurer", s.insurer)
        end
      end
    end
  end
end
-- healthy
local c = { dept = "fm", fatigue = 72, debt = 0, night = false, revisit = false, vitaminFee = 30000, vitaminName = "영양주사", vitaminRest = 40, cured = 50, checkupFee = 10000, canVitamin = true }
local plans = Billing.plans(c, Config)
for _, p in plans do print("healthy plan", p.id, p.title, p.total, p.op, p.treat, p.iv) end
c.dept = "vac"
for _, p in Billing.plans(c, Config) do print("vac plan", p.id, p.title, p.total) end
local sV = Billing.summary(Billing.rows(Billing.plans(c, Config)[1], c, Config, nil), Config)
check(sV.due == Config.Fees.Vaccine, "vaccine due")
-- ward
local sW = Billing.summary(Billing.rows({ ward = true }, { debt = 52500 }, Config, nil), Config)
check(sW.due == 52500 and sW.oldDebt == 52500, "ward")
-- vitals
for _, k in { "cold", "ache", "gastritis", "burnout" } do
  local v = Medical.vitals(12345, 91, k)
  print(k, v.temp, v.sys .. "/" .. v.dia, v.pulse, v.spo2, Medical.bpClass(v.sys, v.dia))
end
local v = Medical.vitals(7, 20, nil)
print("healthy", v.temp, v.sys .. "/" .. v.dia, v.pulse)
print(Medical.cause({ kind = "cold", kindName = "감기", fatigue = 91, riskPct = 0, jobTitle = "편의점 알바", jobPlace = "GS25 광안리점", workSec = 4400, nightSec = 2900 }))
print(Medical.cause({ fatigue = 78, riskPct = 44, workSec = 1200 }))
for _, a in Medical.advice({ kind = "cold", kindName = "감기", fatigue = 91, collapseIn = 200 }, nil) do print(" ", a) end
print(Medical.grade({ fatigue = 60, riskPct = 10, bp = { s = 134, d = 84 }, bmi = 24, vision = { l = 1.0, r = 0.5 }, hearing = { l = true, r = true }, ecg = "정상 동리듬" }))
print(Medical.grade({ ill = "cold", illName = "감기", fatigue = 90, riskPct = 0, bp = { s = 141, d = 88 }, ecg = "동성빈맥 (맥박이 빨라요)" }))
print(Medical.line("desk_hello", 42), Medical.line("pharm_ready", 7), Billing.won(1234567))
print("fails", fails)
