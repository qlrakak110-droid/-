-- GwangalliHealthShared (owner: health): pure helpers for 피로도 / 질병 / 병원 shared by the server
-- (GwangalliGameplay/Health.luau) and the client (StarterPlayerScripts/GwangalliHealth.client.luau).
-- Every number lives in G.HEALTH (ReplicatedStorage.GwangalliGameplayShared); this module only reads
-- it, so tuning happens in one place (docs/HEALTH.md). Nothing yields, nothing is created at require.
--
--   local HS = require(ReplicatedStorage.GwangalliHealthShared)
--   HS.tier(fatigue) -> { min, mult, label, color }        pay tier for a fatigue value
--   HS.payMultiplier(fatigue, ill: boolean) -> number       1.0 / 0.7 / 0.4 / 0.2 (0.2 while ill)
--   HS.debuffText(fatigue, illKind?) -> string?            "피로 -30%" / "감기 -80%" / nil when none
--   HS.fatigueColor(fatigue) -> {r,g,b}
--   HS.workGain(seconds, night) -> number                  fatigue gained by `seconds` of work
--   HS.restLoss(seconds) -> number                          fatigue lost by `seconds` off shift
--   HS.riskGain(fatigue, seconds) -> number                 illness risk gained while working
--   HS.riskDecay(seconds) -> number
--   HS.pickKind(fatigue, clock, jobId, salt) -> kind id     deterministic-ish illness choice
--   HS.kind(id) -> KINDS entry   HS.fee(kind) -> 진료비   HS.ambulanceFee(kind) -> 구급차 포함
--   HS.defaultHealth() -> the d.health table defaults   HS.sanitizeHealth(raw) -> safe copy
--   HS.statusView(d, now) -> what the client sees (fatigue, tier, illness, risk, debt, fees)
--   HS.adviceFor(status) -> one Korean sentence for the 건강검진 report

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HS = {}
HS.VERSION = 1

local G: any = nil
local function g(): any
	if G then
		return G
	end
	local m = ReplicatedStorage:FindFirstChild("GwangalliGameplayShared")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			G = res
		end
	end
	return G
end
HS.G = g

-- defaults used when G.HEALTH is missing (unit tests / a partial place)
local FALLBACK = {
	fatigue = { workSecondsDay = 32, workSecondsNight = 22, taskBonus = 1.5, taskBonusNight = 0.5, restSeconds = 90, sleep = 70, meal = 6, vitamin = 40, cured = 50, collapse = 50 },
	tiers = {
		{ min = 90, mult = 0.2, label = "탈진", color = { 255, 90, 95 } },
		{ min = 75, mult = 0.4, label = "과로", color = { 255, 120, 70 } },
		{ min = 50, mult = 0.7, label = "피로", color = { 255, 176, 32 } },
		{ min = 0, mult = 1.0, label = "", color = { 61, 220, 132 } },
	},
	illMult = 0.2,
	illWalkSpeed = 0.7,
	illHappinessEvery = 60,
	coughEvery = { 14, 22 },
	friendMessageAfter = 45,
	collapseAfter = 600,
	ambulanceFee = 20000,
	ambulanceFeeMult = 1.5,
	risk = { from = 80, perSecond = 1 / 30, slopePer5 = 1, taskBonus = 2, decayPerSecond = 1 / 60, threshold = 25 },
	KIND_ORDER = { "cold", "ache", "gastritis", "burnout" },
	KINDS = {
		cold = { name = "감기", icon = "🤧", fee = 15000, desc = "", cure = "", emote = "cough" },
		ache = { name = "몸살", icon = "🥵", fee = 25000, desc = "", cure = "", emote = "shiver" },
		gastritis = { name = "위염", icon = "🤢", fee = 35000, desc = "", cure = "", emote = "cough" },
		burnout = { name = "번아웃", icon = "😵‍💫", fee = 45000, desc = "", cure = "", emote = "shiver" },
	},
	services = {
		vitamin = { name = "영양주사", icon = "💉", fee = 30000, desc = "" },
		checkup = { name = "건강검진", icon = "🩺", fee = 10000, desc = "" },
	},
	messages = { friend = "병원 가 봐…", ambulance = "쓰러졌어요… 🚑" },
	place = "광안메디컬",
	name = "광안 메디컬 의원",
	reach = 14,
}

function HS.H(): any
	local GG = g()
	return (GG and GG.HEALTH) or FALLBACK
end

local function clamp01to100(v: any): number
	local n = tonumber(v)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.clamp(n, 0, 100)
end
HS.clampFatigue = clamp01to100

-------------------------------------------------------------------------------------------------
-- Tiers / multipliers
-------------------------------------------------------------------------------------------------
function HS.tier(fatigue: any): any
	local f = clamp01to100(fatigue)
	local tiers = HS.H().tiers
	for _, t in tiers do
		if f >= t.min then
			return t
		end
	end
	return tiers[#tiers]
end

function HS.payMultiplier(fatigue: any, ill: boolean?): number
	if ill then
		return HS.H().illMult
	end
	return HS.tier(fatigue).mult
end

function HS.kind(id: any): any?
	if type(id) ~= "string" then
		return nil
	end
	return HS.H().KINDS[id]
end

function HS.fee(kindId: any): number
	local k = HS.kind(kindId)
	return k and k.fee or 0
end

function HS.ambulanceFee(kindId: any): number
	local H = HS.H()
	return math.floor((HS.fee(kindId) * H.ambulanceFeeMult + H.ambulanceFee) / 100) * 100
end

-- "피로 -30%" / "감기 -80%" / nil (nothing to show)
function HS.debuffText(fatigue: any, illKind: any): string?
	local k = HS.kind(illKind)
	if k then
		return string.format("%s %s -%d%%", k.icon, k.name, math.floor((1 - HS.H().illMult) * 100 + 0.5))
	end
	local t = HS.tier(fatigue)
	if t.mult >= 0.999 then
		return nil
	end
	return string.format("😮‍💨 %s -%d%%", t.label, math.floor((1 - t.mult) * 100 + 0.5))
end

function HS.fatigueColor(fatigue: any): { number }
	return HS.tier(fatigue).color
end

-- Why the pay is reduced, as the jobs module prints it ("<reason> -30%" via JS.describeMult):
-- "🤧 감기 때문에 몸이 안 좋아요" / "피로해서 집중이 안 돼요" / nil at full pay.
function HS.payReason(fatigue: any, illKind: any): string?
	local k = HS.kind(illKind)
	if k then
		return string.format("%s %s 때문에 몸이 안 좋아요", k.icon, k.name)
	end
	local t = HS.tier(fatigue)
	if t.mult >= 0.999 then
		return nil
	end
	if t.mult <= 0.25 then
		return "탈진 직전이에요. 쉬어야 해요"
	elseif t.mult <= 0.45 then
		return "과로로 손이 느려요"
	end
	return "피로해서 집중이 안 돼요"
end

-------------------------------------------------------------------------------------------------
-- Curves
-------------------------------------------------------------------------------------------------
function HS.isNightClock(clock: any): boolean
	local c = tonumber(clock) or 12
	return c >= 22 or c < 6
end

-- fatigue gained by `seconds` of shift work
function HS.workGain(seconds: number, night: boolean?): number
	local f = HS.H().fatigue
	local per = if night then f.workSecondsNight else f.workSecondsDay
	return math.max(0, seconds) / math.max(1, per)
end

function HS.taskGain(night: boolean?): number
	local f = HS.H().fatigue
	return f.taskBonus + (if night then f.taskBonusNight else 0)
end

function HS.restLoss(seconds: number): number
	local f = HS.H().fatigue
	return math.max(0, seconds) / math.max(1, f.restSeconds)
end

-- illness risk gained while WORKING for `seconds` at `fatigue`
function HS.riskGain(fatigue: any, seconds: number): number
	local r = HS.H().risk
	local f = clamp01to100(fatigue)
	if f < r.from then
		return 0
	end
	local steps = (f - r.from) / 5
	local perSecond = r.perSecond * (1 + r.slopePer5 * steps)
	return perSecond * math.max(0, seconds)
end

function HS.riskDecay(seconds: number): number
	return HS.H().risk.decayPerSecond * math.max(0, seconds)
end

-- Deterministic-ish illness choice: night work -> 감기, total exhaustion -> 번아웃, delivery / heavy
-- jobs -> 몸살, food / counter jobs -> 위염; `salt` (e.g. lifeDay) breaks ties.
function HS.pickKind(fatigue: any, clock: any, jobId: any, salt: any): string
	local f = clamp01to100(fatigue)
	if f >= 97 then
		return "burnout"
	end
	if HS.isNightClock(clock) then
		return "cold"
	end
	local j = tostring(jobId or "")
	if j == "rider" or j == "taxi_driver" or j == "lifeguard" then
		return "ache"
	end
	if j == "hoe" or j == "gs25" or j == "convenience" or j == "starbucks" then
		return "gastritis"
	end
	local s = math.floor(tonumber(salt) or 0)
	local order = HS.H().KIND_ORDER
	return order[(s % 3) + 1] or "cold"
end

-------------------------------------------------------------------------------------------------
-- Profile data (d.health)
-------------------------------------------------------------------------------------------------
function HS.defaultHealth(): any
	return {
		illness = nil, -- { kind, since (unix), online (s ill while online) }
		risk = 0, -- 0..threshold+
		debt = 0, -- unpaid hospital bill (charged on the next payment)
		visits = 0,
		cured = 0,
		collapses = 0,
		lastVitamin = 0,
		lastCheckup = 0,
	}
end

local function num(v: any, default: number, lo: number, hi: number): number
	local n = tonumber(v)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return math.clamp(n, lo, hi)
end

function HS.sanitizeHealth(raw: any): any
	local d = HS.defaultHealth()
	if type(raw) ~= "table" then
		return d
	end
	if type(raw.illness) == "table" and HS.kind(raw.illness.kind) then
		d.illness = { kind = raw.illness.kind, since = num(raw.illness.since, 0, 0, 4e9), online = num(raw.illness.online, 0, 0, 1e7) }
	end
	d.risk = num(raw.risk, 0, 0, 100)
	d.debt = math.floor(num(raw.debt, 0, 0, 1e9))
	d.visits = math.floor(num(raw.visits, 0, 0, 1e7))
	d.cured = math.floor(num(raw.cured, 0, 0, 1e7))
	d.collapses = math.floor(num(raw.collapses, 0, 0, 1e7))
	d.lastVitamin = num(raw.lastVitamin, 0, 0, 4e9)
	d.lastCheckup = num(raw.lastCheckup, 0, 0, 4e9)
	return d
end

-- The view the client renders (safe to send; no functions / instances).
function HS.statusView(d: any, now: number?): any
	local H = HS.H()
	local h = (type(d) == "table" and type(d.health) == "table") and d.health or HS.defaultHealth()
	local stats = (type(d) == "table" and type(d.stats) == "table") and d.stats or {}
	local fatigue = clamp01to100(stats.fatigue)
	local ill = h.illness
	local kind = ill and HS.kind(ill.kind) or nil
	local tier = HS.tier(fatigue)
	local out: any = {
		fatigue = math.floor(fatigue + 0.5),
		tierLabel = tier.label,
		mult = HS.payMultiplier(fatigue, kind ~= nil),
		risk = math.floor(math.clamp(h.risk or 0, 0, 100) + 0.5),
		riskThreshold = H.risk.threshold,
		debt = h.debt or 0,
		visits = h.visits or 0,
		cured = h.cured or 0,
		collapses = h.collapses or 0,
		fees = { vitamin = H.services.vitamin.fee, checkup = H.services.checkup.fee },
		stats = {},
	}
	for _, k in { "appearance", "stamina", "happiness", "popularity", "strength" } do
		out.stats[k] = math.floor(clamp01to100(stats[k]) + 0.5)
	end
	if kind and ill then
		local t = tonumber(now) or 0
		out.illness = {
			kind = ill.kind,
			name = kind.name,
			icon = kind.icon,
			desc = kind.desc,
			cure = kind.cure,
			fee = kind.fee + (h.debt or 0),
			since = ill.since,
			minutes = if t > 0 and ill.since > 0 then math.floor((t - ill.since) / 60) else 0,
		}
	end
	return out
end

-- One sentence for the 건강검진 report.
function HS.adviceFor(status: any): string
	if type(status) ~= "table" then
		return "검진 결과를 불러올 수 없어요."
	end
	if status.illness then
		return string.format("%s 진단. 바로 치료받으세요 (진료비 %s).", status.illness.name, HS.won(status.illness.fee))
	end
	local f = status.fatigue or 0
	local risk = status.risk or 0
	if f >= 90 then
		return "탈진 직전이에요. 오늘은 일 그만하고 집에서 푹 자요."
	elseif f >= 75 then
		return string.format("과로 상태 (질병 위험 %d%%). 영양주사나 수면이 필요해요.", math.floor(100 * risk / math.max(1, status.riskThreshold or 25)))
	elseif f >= 50 then
		return "피로가 쌓이고 있어요. 급여가 30% 깎이니 쉬어 가며 일해요."
	end
	local st = status.stats or {}
	if (st.stamina or 100) < 30 then
		return "체력이 낮아요. 식사하고 집에서 자면 회복돼요."
	end
	return "아주 건강해요! 지금 컨디션이면 어떤 알바도 거뜬해요 💪"
end

function HS.won(n: any): string
	local GG = g()
	if GG and GG.format and GG.format.won then
		return GG.format.won(n)
	end
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(v)
	local out = string.reverse(string.gsub(string.reverse(s), "(%d%d%d)", "%1,"))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out .. "원"
end

return HS
