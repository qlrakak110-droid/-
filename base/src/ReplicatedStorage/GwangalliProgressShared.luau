--!nocheck
-- GwangalliProgressShared (P): data + pure helpers of 돈 버는 맛 / 인생 레벨 / 일일·주간 목표 / 업적 /
-- 마일스톤 (docs/ECONOMY.md). Required by the server (GwangalliGameplay/Progress.luau) and the client
-- (GwangalliProgress.client.luau). Nothing here touches the DataModel at require time (plain Lune loads it).
--
-- SERVER AUTHORITY: every number below is computed on the server from server-side events (the cash /
-- bank ledger, player attributes set by other server modules, and Progress.track hooks). The client
-- only renders what ProgressEvent / ProgressRequest return.
--
-- REMOTES (inside ReplicatedStorage.GwangalliRemotes, created by Progress.luau):
--   ProgressEvent   RemoteEvent    server -> client, one table per event, field k =
--     "pop"     {amt, cat, label, big (0 | 1 = gold | 2 = jackpot), acct, n (coalesced entries), today}
--     "goal"    {goal = goalView, cash, pop, allDone?}            a daily / weekly goal completed
--     "ach"     {id, name, desc, icon, tier, cash, pop}           an achievement unlocked
--     "level"   {level, title, from, unlocks = {{id, name, desc, icon}}}
--     "ms"      {id, title, body, icon, camera = bool}            a big-purchase milestone (celebration)
--     "payday"  {scope = "day" | "shift", day = dayView, history = {dayView...}, today?}
--     "upd"     {goals = {goalView...}, weekly = goalView, level, lp, earned}   (progress changed)
--   ProgressRequest RemoteFunction client -> server (op, payload?) -> table | nil
--     "snapshot"  -> P.snapshot shape (below)        "reroll" {index} -> {ok, message?, goals}
--     "payday"    -> {day = today so far, history}
--
-- SNAPSHOT { level, title, lp (0..1), earned, nextAt, levelAt, goals = {goalView x3}, weekly = goalView,
--   allDone, rerolls = {used, max}, achievements = {{id, name, desc, icon, tier, n, have, done, t, live}},
--   unlocks = {{level, id, name, desc, icon, have}}, history = {dayView...}, today = dayView,
--   stats = {goalsDone, weeklyDone, bestPay, bestDay, achDone, achTotal} }
-- goalView { id, key, icon, text, n, have, done, cash, pop, group, money, live }
-- dayView  { d (life day), e (earned), s (spent), net, cats = {[cat] = amount}, ecats = {[cat] = amount},
--   best (biggest single income) }
--
-- PLAYER ATTRIBUTES (server writes, anyone reads): LifeLevel (int), LifeLevelProgress (0..1),
--   LifeTitle (string), GoalsDone / GoalsTotal (today's daily goals).
-- SERVER API: ctx.progress (feature modules) and ServerStorage.GwangalliProgressAPI (BindableFunction,
--   other server Scripts): see the header of GwangalliGameplay/Progress.luau.
-- CLIENT API: LocalPlayer.GwangalliProgressOpen (BindableEvent) :Fire(tab?) opens the panel
--   (tab = "goals" | "ach" | "level" | "pay").

local P = {}

P.VERSION = 1
P.DATASTORE = "GwangalliProgress_v1" -- fallback store while Profiles.sanitize drops d.progress
P.KEY_PREFIX = "u_"
P.Remotes = { Event = "ProgressEvent", Request = "ProgressRequest" }
P.API = "GwangalliProgressAPI"
P.OPEN_EVENT = "GwangalliProgressOpen"
P.Attr = {
	Level = "LifeLevel",
	LevelProgress = "LifeLevelProgress",
	Title = "LifeTitle",
	GoalsDone = "GoalsDone",
	GoalsTotal = "GoalsTotal",
}

-- Money pops (client) and their server-side thresholds.
P.POP = {
	min = 100, -- incomes below this do not pop (rounding noise)
	big = 50000, -- one income >= this: short gold flash
	jackpot = 300000, -- >= this: gold flash + coin burst
	coalesce = 0.3, -- s: incomes of one player inside this window become one pop ("+n건")
}

-------------------------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------------------------
local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
P.finite = finite

local function num(v: any, default: number, lo: number?, hi: number?): number
	local x = if finite(v) then v else default
	if lo and x < lo then
		x = lo
	end
	if hi and x > hi then
		x = hi
	end
	return x
end
P.num = num

local function int(v: any, default: number, lo: number?, hi: number?): number
	return math.floor(num(v, default, lo, hi))
end

function P.won(n: any): string
	local v = if finite(n) then math.floor(math.abs(n) + 0.5) else 0
	local s = tostring(v):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if s:sub(1, 1) == "," then
		s = s:sub(2)
	end
	return s .. "원"
end

-- "1.2만원" / "350만원" / "1.2억원" (goal texts)
function P.wonShort(n: any): string
	local v = if finite(n) then math.floor(math.abs(n)) else 0
	if v >= 100000000 then
		local e = v / 100000000
		return (if e == math.floor(e) then tostring(math.floor(e)) else string.format("%.1f", e)) .. "억원"
	elseif v >= 10000 then
		local m = v / 10000
		return (if m == math.floor(m) then tostring(math.floor(m)) else string.format("%.1f", m)) .. "만원"
	end
	return P.won(v)
end

-- Real-day keys (KST, the Korean player's midnight) for the daily / weekly goals.
function P.kstDay(unix: number): number
	return math.floor((unix + 9 * 3600) / 86400)
end
-- Week index starting on Monday (1970-01-01 was a Thursday: +3 days moves the boundary to Monday).
function P.kstWeek(unix: number): number
	return math.floor((P.kstDay(unix) + 3) / 7)
end

-- Deterministic small RNG (no Random / math.random: the same player + day always rolls the same goals).
function P.rng(seed: number): (n: number) -> number
	local s = math.floor(math.abs(seed)) % 2147483647
	if s == 0 then
		s = 1234567
	end
	return function(n: number): number
		s = (s * 48271) % 2147483647
		return (s % math.max(1, n)) + 1
	end
end

local function has(s: string, words: { string }): boolean
	for _, w in words do
		if string.find(s, w, 1, true) then
			return true
		end
	end
	return false
end
P.has = has

-------------------------------------------------------------------------------------------------
-- Ledger classification. Every cash / bank change on the server goes through G.ledger; Progress
-- watches it and classifies each entry here. Positive entries that are not earnings (own cash <-> bank
-- moves, money from other players, refunds, selling a home / furniture / car, loans) never count toward
-- 인생 레벨 (no alt-account farming, no buy-sell loops).
-------------------------------------------------------------------------------------------------
P.EARN_CATS = { "wage", "tip", "sale", "reward", "income" }
P.EARN_NAMES = { wage = "급여", tip = "팁", sale = "판매", reward = "보상", income = "기타 수입" }
P.SPEND_CATS = { "home", "car", "life", "fun", "med", "give", "send", "fee" }
P.SPEND_NAMES = { home = "주거", car = "교통", life = "생활", fun = "여가", med = "병원", give = "선물·기부", send = "송금", fee = "수수료" }
P.CAT_COLORS = {
	wage = { 61, 220, 132 }, tip = { 255, 194, 71 }, sale = { 61, 214, 245 }, reward = { 255, 79, 163 }, income = { 139, 108, 255 },
	home = { 40, 204, 196 }, car = { 84, 140, 255 }, life = { 255, 176, 32 }, fun = { 139, 108, 255 }, med = { 255, 90, 95 },
	give = { 255, 79, 163 }, send = { 170, 177, 196 }, fee = { 116, 124, 146 },
}
P.POP_GLYPH = { wage = "💼", tip = "🪙", sale = "🧾", reward = "🎁", income = "💰", transfer = "💸", refund = "↩️", asset = "🏷️" }

local INTERNAL_WORDS = { "현금 → 통장", "통장 → 현금", "(현금→통장)", "(통장→현금)" }
local INTERNAL_EXACT = { ["현금 입금"] = true, ["ATM 출금"] = true }
local REFUND_WORDS = { "환불", "반환", "취소", "정산금", "보증금 돌려" }
local ASSET_WORDS = { "가구 판매", "매도", "되팔기", "차량 판매", "차 판매", "중고차 판매", "매각", "중고 매입", "자동차 판매" }
local LOAN_WORDS = { "대출 실행", "대출금 입금", "대출 입금" }
local TIP_WORDS = { "팁" }
local WAGE_WORDS = { "급여", "시급", "월급", "일당", "수당", "알바비", "근무", "주급", "봉급" }
local REWARD_WORDS = { "보상", "상금", "보너스", "목표", "업적", "축하금", "용돈", "선물 받", "당첨" }
local SALE_WORDS = { "판매", "매출", "수익", "정산", "팔았", "낚시" }

local HOME_WORDS = { "월세", "보증금", "관리비", "공과금", "매매", "계약", "주택", "대출", "경매", "인테리어", "가구", "리모델링", "도배", "에어컨", "스마트홈", "주방", "테라스", "자동이체", "집들이" }
local CAR_WORDS = { "택시", "렌트", "정비", "세차", "견인", "시승", "차량", "신차", "중고차", "할부", "주유", "탑차", "큐비", "세단", "SUV", "트럭", "밴 ", "플래그십", "자동차" }
local FUN_WORDS = { "CLUB", "클럽", "입장료", "VIP", "테이블", "보틀", "볼링", "노래방", "PC방", "SUP", "패들보드", "게임", "레포츠", "공연" }
local MED_WORDS = { "메디컬", "병원", "진료", "주사", "검진", "약국", "치료", "수액" }
local GIVE_WORDS = { "선물", "적선", "기부" }

-- delta (+ income / - spending), account ("cash" | "bank"), label, meta (bank meta: {kind, ...} or nil)
-- -> cat, group ("earn" | "spend" | "skip"); "skip" = never counted (internal moves, transfers in,
-- refunds, asset sales, loans). Transfers in / refunds / asset sales still pop (cat transfer / refund /
-- asset) but do not count.
function P.classify(delta: number, _account: string?, label: string?, meta: any?): (string, string)
	local l = if type(label) == "string" then label else ""
	local kind = if type(meta) == "table" and type(meta.kind) == "string" then meta.kind else nil
	if kind == "atm_wd" or kind == "atm_dep" or INTERNAL_EXACT[l] or has(l, INTERNAL_WORDS) then
		return "internal", "skip"
	end
	if delta > 0 then
		if kind == "p2p_in" or kind == "cash_in" then
			return "transfer", "skip"
		end
		if kind == "refund" or has(l, REFUND_WORDS) then
			return "refund", "skip"
		end
		if has(l, ASSET_WORDS) then
			return "asset", "skip"
		end
		if has(l, LOAN_WORDS) then
			return "loan", "skip"
		end
		if has(l, TIP_WORDS) then
			return "tip", "earn"
		end
		if has(l, WAGE_WORDS) then
			return "wage", "earn"
		end
		if has(l, REWARD_WORDS) then
			return "reward", "earn"
		end
		if has(l, SALE_WORDS) then
			return "sale", "earn"
		end
		return "income", "earn"
	end
	if kind == "fee" or string.find(l, "수수료", 1, true) then
		return "fee", "spend"
	end
	if kind == "p2p_out" or kind == "cash_out" or string.find(l, "송금", 1, true) or string.find(l, "현금 전달", 1, true) then
		return "send", "spend"
	end
	if string.sub(l, 1, #"택시") == "택시" then
		return "car", "spend" -- "택시비 · 광안메디컬" is a ride, not a hospital bill
	end
	if has(l, MED_WORDS) then
		return "med", "spend"
	end
	if has(l, GIVE_WORDS) then
		return "give", "spend"
	end
	if has(l, FUN_WORDS) then
		return "fun", "spend"
	end
	if has(l, CAR_WORDS) then
		return "car", "spend"
	end
	if has(l, HOME_WORDS) then
		return "home", "spend"
	end
	return "life", "spend"
end

-- Auto-tracked goal / achievement keys for one classified ledger entry: { {key, n}, ... }.
-- foodNames = { [item display name] = true } (built by the server from G.ITEMS / G.HOME_FOOD).
function P.ledgerKeys(delta: number, cat: string, group: string, label: string?, foodNames: { [string]: boolean }?): { { any } }
	local l = if type(label) == "string" then label else ""
	local out = {}
	local amt = math.abs(math.floor(delta))
	if group == "earn" then
		table.insert(out, { "earn", amt })
		table.insert(out, { "earn_" .. cat, amt })
		if cat == "tip" then
			table.insert(out, { "tip_total", amt })
		end
		if cat == "wage" and string.find(l, "근무 완료", 1, true) then
			table.insert(out, { "shift", 1 })
		end
		if cat == "wage" then
			table.insert(out, { "payday", 1 })
		end
	elseif group == "spend" then
		table.insert(out, { "spend", amt })
		if string.sub(l, 1, #"택시비") == "택시비" then
			table.insert(out, { "taxi_ride", 1 })
		end
		if string.find(l, "세차", 1, true) then
			table.insert(out, { "car_wash", 1 })
		end
		if cat == "med" then
			table.insert(out, { "hospital", 1 })
		end
		if string.find(l, "선물", 1, true) then
			table.insert(out, { "gift", 1 })
		end
		if string.find(l, "적선", 1, true) or string.find(l, "기부", 1, true) then
			table.insert(out, { "donate", 1 })
		end
		if cat == "send" and string.find(l, "송금", 1, true) then
			table.insert(out, { "transfer", 1 })
		end
		if string.find(l, "VIP", 1, true) and (string.find(l, "테이블", 1, true) or string.find(l, "룸", 1, true)) then
			table.insert(out, { "vip_table", 1 })
		end
		if string.find(l, "보틀", 1, true) then
			table.insert(out, { "bottle", 1 })
		end
		local food = false
		if foodNames then
			for name in foodNames do
				if string.find(l, name, 1, true) then
					food = true
					break
				end
			end
		end
		if food or string.find(l, "배달 주문", 1, true) then
			table.insert(out, { "eat", 1 })
		end
		if cat == "life" and amt >= 1000 then
			table.insert(out, { "shop_buy", 1 })
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Track keys. auto = detected by Progress without any hook; owner = who reports it with
-- ctx.progress.track(player, key, n) (or ServerStorage.GwangalliProgressAPI "track").
-- A key that is neither auto nor `live` becomes live on this server the first time a hook reports it
-- (and for a player who already has progress on it), so daily goals never ask for something that
-- cannot be done yet. Flip live = true here once the owner's hook ships.
-------------------------------------------------------------------------------------------------
P.KEYS = {
	earn = { name = "번 돈", auto = true },
	earn_wage = { name = "급여", auto = true },
	earn_tip = { name = "팁", auto = true },
	earn_sale = { name = "판매 수익", auto = true },
	earn_reward = { name = "보상", auto = true },
	earn_income = { name = "기타 수입", auto = true },
	tip_total = { name = "팁", auto = true },
	spend = { name = "쓴 돈", auto = true },
	shift = { name = "알바 근무 완료", auto = true }, -- ledger "급여 · ... (근무 완료)"
	payday = { name = "급여 입금", auto = true },
	taxi_ride = { name = "택시 탑승", auto = true },
	car_wash = { name = "세차", auto = true },
	hospital = { name = "병원 진료", auto = true },
	gift = { name = "선물", auto = true },
	donate = { name = "적선", auto = true },
	transfer = { name = "송금", auto = true },
	vip_table = { name = "VIP 테이블", auto = true },
	bottle = { name = "보틀 주문", auto = true },
	eat = { name = "맛집", auto = true },
	shop_buy = { name = "결제", auto = true },
	club_enter = { name = "클럽 입장", auto = true }, -- attribute ClubOceanWristband
	bowl_game = { name = "볼링 게임", auto = true }, -- attribute LastBowlingScore
	drive_min = { name = "운전 (분)", auto = true }, -- seconds in a VehicleSeat / 60
	gym_set = { name = "헬스 세트", auto = true }, -- d.gym.sets grew
	goal_done = { name = "일일 목표 달성", auto = true },
	delivery = { name = "배달 완료", auto = true, owner = "jobs" }, -- notify "배달 완료" fallback + hook
	promotion = { name = "승진", auto = true, owner = "jobs" }, -- notify "승진!" fallback + hook
	hired = { name = "알바 합격", auto = true, owner = "jobs" }, -- notify "합격!" fallback + hook
	-- hooks (owner modules call ctx.progress.track)
	job_task = { name = "알바 업무", owner = "jobs" },
	cvs_customer = { name = "편의점 손님 계산", owner = "jobs" },
	cvs_restock = { name = "편의점 재고 정리", owner = "jobs" },
	cafe_drink = { name = "카페 음료", owner = "jobs" },
	parcel = { name = "택배 배송", owner = "jobs" },
	perfect_round = { name = "퍼펙트 라운드", owner = "jobs" },
	bowl_strike = { name = "볼링 스트라이크", owner = "bowling" },
	bowl_spare = { name = "볼링 스페어", owner = "bowling" },
	bowl_turkey = { name = "볼링 터키", owner = "bowling" },
	talk_npc = { name = "NPC 대화", owner = "npc" },
	fish_catch = { name = "낚시", owner = "interactions" },
	karaoke_song = { name = "노래방", owner = "interiors" },
	pc_game = { name = "PC방 게임", owner = "interiors" },
	car_buy = { name = "차 구매", owner = "garage" },
	car_repair = { name = "정비", owner = "garage" },
	home_meal = { name = "집밥", owner = "homes" },
	furniture = { name = "가구 배치", owner = "homes" },
	housewarming = { name = "집들이", owner = "homes" },
	sleep_home = { name = "집에서 잠", owner = "homes" },
}

-------------------------------------------------------------------------------------------------
-- 인생 레벨: from lifetime earnings (P.classify group "earn"). L1 알바 ~29,000원 per ~6 min shift
-- (~250-300k원 per real hour) -> Lv2 in ~10 min, Lv5 ~2 h, Lv10 ~17 h, Lv20 ~180 h.
-------------------------------------------------------------------------------------------------
P.LEVELS = {
	0, 50000, 150000, 300000, 600000, -- 1-5
	1000000, 1600000, 2400000, 3500000, 5000000, -- 6-10
	7000000, 9500000, 12500000, 16000000, 20000000, -- 11-15
	25000000, 31000000, 38000000, 46000000, 55000000, -- 16-20
	65000000, 76000000, 88000000, 101000000, 115000000, -- 21-25
	130000000, 146000000, 163000000, 181000000, 200000000, -- 26-30
}
P.MAX_LEVEL = #P.LEVELS

P.TITLES = {
	{ 1, "광안리 새내기" }, { 3, "알바 루키" }, { 5, "성실한 알바생" }, { 7, "광안리 단골" }, { 10, "동네 유명인" },
	{ 13, "광안리 실세" }, { 15, "자수성가" }, { 18, "광안리 큰손" }, { 20, "광안리 재벌" }, { 25, "바다뷰 건물주" }, { 30, "광안리 전설" },
}

-- -> level, progress to the next level (0..1), amount of the current level, amount of the next (nil at max)
function P.levelFor(earned: any): (number, number, number, number?)
	local e = num(earned, 0, 0)
	local lv = 1
	for i, need in P.LEVELS do
		if e >= need then
			lv = i
		end
	end
	local at = P.LEVELS[lv]
	local nxt = P.LEVELS[lv + 1]
	if not nxt then
		return lv, 1, at, nil
	end
	return lv, math.clamp((e - at) / (nxt - at), 0, 1), at, nxt
end

function P.titleFor(level: number): string
	local t = P.TITLES[1][2]
	for _, e in P.TITLES do
		if level >= e[1] then
			t = e[2]
		end
	end
	return t
end

-- Level unlocks. owner = who applies the perk (progress = this system; others read it with
-- ctx.progress.perk(player, id) -> value | false; see docs/ECONOMY.md for the one-line hooks).
P.UNLOCKS = {
	{ level = 2, id = "goal_reroll", name = "목표 새로고침", desc = "일일 목표 하나를 하루 1번 바꿀 수 있어요", icon = "🔄", owner = "progress", value = 1 },
	{ level = 3, id = "used_car_discount", name = "중고차 5% 할인", desc = "광안 오토 중고차를 5% 싸게 살 수 있어요", icon = "🚙", owner = "garage", value = 0.05 },
	{ level = 4, id = "taxi_regular", name = "콜택시 단골 5% 할인", desc = "광안콜택시 요금 5% 할인", icon = "🚕", owner = "taxi", value = 0.05 },
	{ level = 5, id = "home_loan", name = "주택담보대출 가능", desc = "오피스텔·아파트를 대출로 살 수 있어요", icon = "🏦", owner = "homes", value = 1 },
	{ level = 6, id = "club_cover_discount", name = "클럽 입장료 20% 할인", desc = "CLUB OCEAN 단골 대우", icon = "🎶", owner = "club", value = 0.2 },
	{ level = 7, id = "goal_bonus_10", name = "목표 보상 +10%", desc = "일일·주간 목표 현금 보상 10% 추가", icon = "🎯", owner = "progress", value = 0.1 },
	{ level = 8, id = "car_loan", name = "자동차 할부 가능", desc = "신차·중고차를 할부로 살 수 있어요", icon = "🚗", owner = "garage", value = 1 },
	{ level = 10, id = "vip_discount", name = "VIP 테이블 10% 할인", desc = "MD가 알아보고 자리를 챙겨 줘요", icon = "🍾", owner = "club", value = 0.1 },
	{ level = 12, id = "goal_reroll_2", name = "목표 새로고침 2번", desc = "하루 2번까지 목표를 바꿀 수 있어요", icon = "🔄", owner = "progress", value = 2 },
	{ level = 14, id = "goal_bonus_20", name = "목표 보상 +20%", desc = "일일·주간 목표 현금 보상 20% 추가", icon = "🎯", owner = "progress", value = 0.2 },
	{ level = 15, id = "penthouse", name = "펜트하우스 매매 자격", desc = "아쿠아펠리스 펜트하우스를 계약할 수 있어요", icon = "🌊", owner = "homes", value = 1 },
	{ level = 18, id = "luxury_new", name = "플래그십 신차 자격", desc = "드림카 플래그십 신차 출고 가능", icon = "🏎️", owner = "garage", value = 1 },
	{ level = 20, id = "gold_card", name = "골드 카드", desc = "모든 ATM 수수료 면제", icon = "💳", owner = "bank", value = 1 },
	{ level = 25, id = "title_tycoon", name = "칭호: 바다뷰 건물주", desc = "이름표에 특별 칭호", icon = "👑", owner = "progress", value = 1 },
}

-- Highest value of a perk at `level` (false when locked). Later unlocks of the same family override.
function P.perk(level: number, id: string): any
	local best: any = false
	for _, u in P.UNLOCKS do
		if u.id == id and level >= u.level then
			best = u.value
		end
	end
	if id == "goal_reroll" then
		for _, u in P.UNLOCKS do
			if u.id == "goal_reroll_2" and level >= u.level then
				best = u.value
			end
		end
	elseif id == "goal_bonus" then
		for _, u in P.UNLOCKS do
			if (u.id == "goal_bonus_10" or u.id == "goal_bonus_20") and level >= u.level then
				best = u.value
			end
		end
	end
	return best
end

function P.unlocksAt(level: number): { any }
	local out = {}
	for _, u in P.UNLOCKS do
		if u.level == level then
			table.insert(out, u)
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Daily goals (일일 목표): 3 a day (KST midnight), one per group (work / life / fun) when possible.
-- n = {band1 (Lv1-4), band2 (Lv5-9), band3 (Lv10+)}; cash is scaled by band (x1 / x1.5 / x2) and the
-- goal_bonus perk. needs = "car" | "home": only rolled when the player has one.
-------------------------------------------------------------------------------------------------
P.GROUPS = { "work", "life", "fun" }
P.GROUP_NAMES = { work = "일", life = "생활", fun = "놀거리" }
P.GOALS = {
	{ id = "earn", key = "earn", group = "work", icon = "💰", text = "오늘 %s 벌기", money = true, n = { 80000, 150000, 300000 }, cash = 10000, pop = 1 },
	{ id = "shift", key = "shift", group = "work", icon = "💼", text = "알바 근무 %d번 끝까지 하기", n = { 1, 2, 3 }, cash = 9000, pop = 1 },
	{ id = "cvs", key = "cvs_customer", group = "work", icon = "🏪", text = "편의점 손님 %d명 계산하기", n = { 5, 8, 12 }, cash = 8000, pop = 1 },
	{ id = "restock", key = "cvs_restock", group = "work", icon = "📦", text = "편의점 진열대 %d번 채우기", n = { 2, 3, 5 }, cash = 7000, pop = 1 },
	{ id = "cafe", key = "cafe_drink", group = "work", icon = "☕", text = "카페 음료 %d잔 만들기", n = { 4, 6, 10 }, cash = 8000, pop = 1 },
	{ id = "quick", key = "delivery", group = "work", icon = "🛵", text = "배달 %d건 완료하기", n = { 2, 3, 5 }, cash = 9000, pop = 1 },
	{ id = "parcel", key = "parcel", group = "work", icon = "🚚", text = "택배 %d건 배송하기", n = { 3, 5, 8 }, cash = 10000, pop = 1 },
	{ id = "tips", key = "tip_total", group = "work", icon = "🪙", text = "팁 %s 받기", money = true, n = { 3000, 6000, 12000 }, cash = 7000, pop = 1 },
	{ id = "perfect", key = "perfect_round", group = "work", icon = "✨", text = "알바 퍼펙트 %d번", n = { 2, 3, 5 }, cash = 8000, pop = 1 },
	{ id = "eat", key = "eat", group = "life", icon = "🍜", text = "맛있는 거 %d번 사 먹기", n = { 1, 2, 3 }, cash = 5000, pop = 0 },
	{ id = "gym", key = "gym_set", group = "life", icon = "💪", text = "헬스장에서 %d세트 운동하기", n = { 3, 5, 8 }, cash = 6000, pop = 1 },
	{ id = "drive", key = "drive_min", group = "life", icon = "🚗", text = "%d분 운전하기", n = { 3, 5, 8 }, cash = 6000, pop = 0 },
	{ id = "taxi", key = "taxi_ride", group = "life", icon = "🚕", text = "콜택시 타고 이동하기", n = { 1, 1, 2 }, cash = 5000, pop = 0 },
	{ id = "shop", key = "shop_buy", group = "life", icon = "🛍️", text = "가게에서 %d번 결제하기", n = { 2, 3, 4 }, cash = 5000, pop = 0 },
	{ id = "gift", key = "gift", group = "life", icon = "🎁", text = "동네 사람에게 선물하기", n = { 1, 1, 2 }, cash = 5000, pop = 2 },
	{ id = "donate", key = "donate", group = "life", icon = "🤲", text = "어려운 이웃 도와주기", n = { 1, 1, 2 }, cash = 3000, pop = 1 },
	{ id = "talk", key = "talk_npc", group = "life", icon = "💬", text = "동네 사람 %d명과 대화하기", n = { 2, 3, 5 }, cash = 5000, pop = 1 },
	{ id = "wash", key = "car_wash", group = "life", icon = "🧽", text = "정비소에서 세차하기", n = { 1, 1, 1 }, cash = 4000, pop = 0, needs = "car" },
	{ id = "meal", key = "home_meal", group = "life", icon = "🍚", text = "집에서 밥 해 먹기", n = { 1, 2, 2 }, cash = 4000, pop = 0, needs = "home" },
	{ id = "club", key = "club_enter", group = "fun", icon = "🎶", text = "CLUB OCEAN 입장하기", n = { 1, 1, 1 }, cash = 6000, pop = 2 },
	{ id = "bowl", key = "bowl_game", group = "fun", icon = "🎳", text = "볼링 한 게임 치기", n = { 1, 1, 2 }, cash = 6000, pop = 1 },
	{ id = "strike", key = "bowl_strike", group = "fun", icon = "🎳", text = "볼링 스트라이크 %d번", n = { 1, 2, 3 }, cash = 8000, pop = 2 },
	{ id = "karaoke", key = "karaoke_song", group = "fun", icon = "🎤", text = "노래방에서 %d곡 부르기", n = { 1, 2, 3 }, cash = 6000, pop = 1 },
	{ id = "pc", key = "pc_game", group = "fun", icon = "🖥️", text = "PC방에서 게임 %d판", n = { 1, 2, 3 }, cash = 6000, pop = 1 },
	{ id = "fish", key = "fish_catch", group = "fun", icon = "🎣", text = "물고기 %d마리 낚기", n = { 2, 3, 5 }, cash = 7000, pop = 1 },
	{ id = "bottle", key = "bottle", group = "fun", icon = "🍾", text = "클럽에서 보틀 주문하기", n = { 1, 1, 1 }, cash = 10000, pop = 3, minLevel = 6 },
}
P.GOAL_BY_ID = {}
for _, g in P.GOALS do
	P.GOAL_BY_ID[g.id] = g
end
P.DAILY_COUNT = 3
P.ALL_DONE = { cash = 10000, pop = 2, happiness = 5 } -- 올클리어 bonus (x band)
P.BAND_CASH = { 1, 1.5, 2 }

P.WEEKLY = {
	{ id = "w_earn", key = "earn", icon = "📈", text = "이번 주 %s 벌기", money = true, n = { 600000, 1500000, 4000000 }, cash = 100000, pop = 5 },
	{ id = "w_shift", key = "shift", icon = "🗓️", text = "이번 주 알바 %d번 끝까지 하기", n = { 8, 15, 25 }, cash = 100000, pop = 5 },
	{ id = "w_goals", key = "goal_done", icon = "🎯", text = "이번 주 일일 목표 %d개 달성", n = { 9, 12, 15 }, cash = 120000, pop = 6 },
}
P.WEEKLY_BY_ID = {}
for _, g in P.WEEKLY do
	P.WEEKLY_BY_ID[g.id] = g
end

function P.band(level: number): number
	return if level >= 10 then 3 elseif level >= 5 then 2 else 1
end

-- The text of a goal for target n.
function P.goalText(def: any, n: number): string
	local t = def.text
	if def.money then
		return string.format(t, P.wonShort(n))
	end
	if string.find(t, "%%d") then
		return string.format(t, n)
	end
	return t
end

-- Rolls today's goals. live(key) -> bool; has = {car = bool, home = bool}; level; seed (userId + day).
-- Returns { {id, n, have = 0, done = false} x P.DAILY_COUNT }.
function P.rollDaily(seed: number, level: number, live: (string) -> boolean, owns: { [string]: boolean }?): { any }
	local rand = P.rng(seed)
	local band = P.band(level)
	local o = owns or {}
	local function ok(g: any): boolean
		if not live(g.key) then
			return false
		end
		if g.needs and not o[g.needs] then
			return false
		end
		if g.minLevel and level < g.minLevel then
			return false
		end
		return true
	end
	local picked: { any } = {}
	local used: { [string]: boolean } = {}
	local function pickFrom(list: { any })
		if #list == 0 or #picked >= P.DAILY_COUNT then
			return
		end
		local g = list[rand(#list)]
		used[g.id] = true
		used["key:" .. g.key] = true
		table.insert(picked, { id = g.id, n = g.n[band] or g.n[#g.n], have = 0, done = false })
	end
	for _, grp in P.GROUPS do
		local list = {}
		for _, g in P.GOALS do
			if g.group == grp and ok(g) and not used[g.id] and not used["key:" .. g.key] then
				table.insert(list, g)
			end
		end
		pickFrom(list)
	end
	-- fewer than 3 groups had a live goal: fill from anything left
	local guard = 0
	while #picked < P.DAILY_COUNT and guard < 10 do
		guard += 1
		local list = {}
		for _, g in P.GOALS do
			if ok(g) and not used[g.id] and not used["key:" .. g.key] then
				table.insert(list, g)
			end
		end
		if #list == 0 then
			break
		end
		pickFrom(list)
	end
	return picked
end

function P.rollWeekly(seed: number, level: number): any
	local rand = P.rng(seed + 7777)
	local g = P.WEEKLY[rand(#P.WEEKLY)]
	local band = P.band(level)
	return { id = g.id, n = g.n[band] or g.n[#g.n], have = 0, done = false }
end

-- Cash reward of a goal for this level (band + goal_bonus perk), rounded to 100.
function P.goalCash(def: any, level: number, weekly: boolean?): number
	local base = def.cash or 0
	local mult = if weekly then 1 else (P.BAND_CASH[P.band(level)] or 1)
	local bonus = P.perk(level, "goal_bonus")
	if bonus then
		mult *= 1 + bonus
	end
	return math.floor(base * mult / 100 + 0.5) * 100
end

-------------------------------------------------------------------------------------------------
-- 업적 (achievements). metric: "earned" | "c:<key>" (lifetime counter) | "bank" | "net" | "level" |
-- "bestPay" | "bestDay" | "goals" | "weekly" | "stat:<name>" | "cars" | "homeTier" | "homeOwned" |
-- "jobs" (careers with xp) | "topRank" | "promo" | "friends" | "outfits" | "gymSets" | "shifts" | "ms:<id>"
-- Rewards by tier (cash into the bank + 인기도). key = the track key whose liveness gates the badge
-- (badges of hook keys that are not live yet show "준비 중").
-------------------------------------------------------------------------------------------------
P.TIER_ORDER = { "bronze", "silver", "gold", "platinum" }
P.TIERS = {
	bronze = { name = "브론즈", color = { 214, 142, 84 }, cash = 5000, pop = 1 },
	silver = { name = "실버", color = { 200, 208, 222 }, cash = 20000, pop = 2 },
	gold = { name = "골드", color = { 255, 194, 71 }, cash = 50000, pop = 3 },
	platinum = { name = "플래티넘", color = { 140, 232, 255 }, cash = 150000, pop = 5 },
}
P.ACH_CATS = { "money", "work", "life", "social", "fun" }
P.ACH_CAT_NAMES = { money = "돈", work = "일", life = "생활", social = "인맥·밤", fun = "놀거리·건강" }
P.ACHIEVEMENTS = {
	-- 돈
	{ id = "first_pay", cat = "money", name = "첫 월급날", desc = "알바 급여를 처음 받았어요", icon = "💵", tier = "bronze", metric = "c:payday", n = 1 },
	{ id = "earn_100k", cat = "money", name = "십만 원의 행복", desc = "누적 수입 10만원", icon = "💰", tier = "bronze", metric = "earned", n = 100000 },
	{ id = "earn_1m", cat = "money", name = "백만장자 지망생", desc = "누적 수입 100만원", icon = "💰", tier = "silver", metric = "earned", n = 1000000 },
	{ id = "earn_10m", cat = "money", name = "천만 원 클럽", desc = "누적 수입 1,000만원", icon = "💎", tier = "gold", metric = "earned", n = 10000000 },
	{ id = "earn_100m", cat = "money", name = "광안리 큰손", desc = "누적 수입 1억원", icon = "👑", tier = "platinum", metric = "earned", n = 100000000 },
	{ id = "big_day", cat = "money", name = "하루 이십만", desc = "게임 하루에 20만원 벌기", icon = "📈", tier = "silver", metric = "bestDay", n = 200000 },
	{ id = "big_pay", cat = "money", name = "대박 한 방", desc = "한 번에 10만원 이상 받기", icon = "💥", tier = "silver", metric = "bestPay", n = 100000 },
	{ id = "saver", cat = "money", name = "알뜰살뜰", desc = "통장 잔고 100만원 모으기", icon = "🐷", tier = "silver", metric = "bank", n = 1000000 },
	{ id = "net_10m", cat = "money", name = "순자산 1천만", desc = "총자산 1,000만원 달성", icon = "🏦", tier = "gold", metric = "net", n = 10000000 },
	{ id = "tips_50k", cat = "money", name = "팁 부자", desc = "팁으로만 5만원 받기", icon = "🪙", tier = "silver", metric = "c:tip_total", n = 50000, key = "tip_total" },
	-- 일
	{ id = "hired", cat = "work", name = "합격입니다!", desc = "첫 알바에 합격했어요", icon = "📝", tier = "bronze", metric = "c:hired", n = 1 },
	{ id = "shift_1", cat = "work", name = "첫 출근", desc = "알바 근무 1번 끝까지 하기", icon = "💼", tier = "bronze", metric = "shifts", n = 1 },
	{ id = "shift_10", cat = "work", name = "성실 근무자", desc = "알바 근무 10번 완료", icon = "🗓️", tier = "silver", metric = "shifts", n = 10 },
	{ id = "shift_50", cat = "work", name = "프로 알바러", desc = "알바 근무 50번 완료", icon = "🏅", tier = "gold", metric = "shifts", n = 50 },
	{ id = "promoted", cat = "work", name = "승진했어요", desc = "처음으로 승진하기", icon = "📈", tier = "silver", metric = "promo", n = 1 },
	{ id = "top_rank", cat = "work", name = "점장님", desc = "한 직장에서 최고 직급 달성", icon = "🎖️", tier = "gold", metric = "topRank", n = 1 },
	{ id = "multi_job", cat = "work", name = "N잡러", desc = "서로 다른 알바 3곳 경험", icon = "🔀", tier = "silver", metric = "jobs", n = 3 },
	{ id = "cvs_100", cat = "work", name = "편의점 계산왕", desc = "편의점 손님 100명 계산", icon = "🏪", tier = "gold", metric = "c:cvs_customer", n = 100, key = "cvs_customer" },
	{ id = "cafe_100", cat = "work", name = "라떼 장인", desc = "카페 음료 100잔 만들기", icon = "☕", tier = "gold", metric = "c:cafe_drink", n = 100, key = "cafe_drink" },
	{ id = "delivery_50", cat = "work", name = "번개 라이더", desc = "배달 50건 완료", icon = "🛵", tier = "gold", metric = "c:delivery", n = 50, key = "delivery" },
	{ id = "parcel_30", cat = "work", name = "택배의 신", desc = "택배 30건 배송", icon = "🚚", tier = "gold", metric = "c:parcel", n = 30, key = "parcel" },
	-- 생활
	{ id = "first_home", cat = "life", name = "내 방 생겼다", desc = "처음으로 집 계약하기", icon = "🔑", tier = "bronze", metric = "ms:first_home", n = 1 },
	{ id = "own_home", cat = "life", name = "내 집 마련", desc = "집을 매매로 사기", icon = "🏡", tier = "gold", metric = "homeOwned", n = 1 },
	{ id = "penthouse", cat = "life", name = "펜트하우스 입주", desc = "오션뷰 펜트하우스의 주인", icon = "🌊", tier = "platinum", metric = "homeTier", n = 5 },
	{ id = "first_car", cat = "life", name = "첫 차 뽑았다", desc = "내 차를 처음 사기", icon = "🚗", tier = "silver", metric = "cars", n = 1 },
	{ id = "car_3", cat = "life", name = "카 컬렉터", desc = "차 3대 보유", icon = "🏎️", tier = "gold", metric = "cars", n = 3 },
	{ id = "drive_30", cat = "life", name = "베스트 드라이버", desc = "누적 30분 운전", icon = "🛣️", tier = "silver", metric = "c:drive_min", n = 30 },
	{ id = "taxi_10", cat = "life", name = "택시 단골", desc = "콜택시 10번 타기", icon = "🚕", tier = "bronze", metric = "c:taxi_ride", n = 10 },
	{ id = "shopper", cat = "life", name = "쇼핑 중독", desc = "가게에서 30번 결제", icon = "🛍️", tier = "bronze", metric = "c:shop_buy", n = 30 },
	{ id = "fashion", cat = "life", name = "패셔니스타", desc = "옷·헤어 5개 갖기", icon = "👗", tier = "silver", metric = "outfits", n = 5 },
	{ id = "gourmet", cat = "life", name = "광안리 미식가", desc = "맛집에서 20번 사 먹기", icon = "🍜", tier = "silver", metric = "c:eat", n = 20 },
	-- 인맥·밤
	{ id = "club_first", cat = "social", name = "클럽 데뷔", desc = "CLUB OCEAN 첫 입장", icon = "🎶", tier = "bronze", metric = "c:club_enter", n = 1 },
	{ id = "club_10", cat = "social", name = "클럽 죽돌이", desc = "클럽 10번 입장", icon = "🪩", tier = "silver", metric = "c:club_enter", n = 10 },
	{ id = "vip_table", cat = "social", name = "오늘 주인공은 나", desc = "VIP 테이블 잡기", icon = "🍾", tier = "gold", metric = "ms:first_vip", n = 1 },
	{ id = "friends_3", cat = "social", name = "인싸", desc = "동네 친구 3명 사귀기", icon = "🤝", tier = "silver", metric = "friends", n = 3 },
	{ id = "popular_50", cat = "social", name = "핵인싸", desc = "인기도 50 달성", icon = "⭐", tier = "gold", metric = "stat:popularity", n = 50 },
	{ id = "donor", cat = "social", name = "기부 천사", desc = "어려운 이웃 5번 돕기", icon = "😇", tier = "bronze", metric = "c:donate", n = 5 },
	{ id = "gift_5", cat = "social", name = "선물 요정", desc = "선물 5번 하기", icon = "🎁", tier = "silver", metric = "c:gift", n = 5 },
	{ id = "transfer_1", cat = "social", name = "첫 송금", desc = "다른 플레이어에게 송금하기", icon = "💸", tier = "bronze", metric = "c:transfer", n = 1 },
	-- 놀거리·건강
	{ id = "bowl_first", cat = "fun", name = "볼링 입문", desc = "볼링 한 게임 치기", icon = "🎳", tier = "bronze", metric = "c:bowl_game", n = 1 },
	{ id = "bowl_strike", cat = "fun", name = "스트라이크!", desc = "첫 스트라이크", icon = "🎳", tier = "bronze", metric = "c:bowl_strike", n = 1, key = "bowl_strike" },
	{ id = "bowl_turkey", cat = "fun", name = "터키!", desc = "스트라이크 3연속", icon = "🦃", tier = "gold", metric = "c:bowl_turkey", n = 1, key = "bowl_turkey" },
	{ id = "bowl_200", cat = "fun", name = "200점 클럽", desc = "볼링 200점 이상", icon = "🏆", tier = "platinum", metric = "c:bowl_200", n = 1 },
	{ id = "gym_100", cat = "fun", name = "헬스 마니아", desc = "헬스 100세트", icon = "🏋️", tier = "silver", metric = "gymSets", n = 100 },
	{ id = "strong_50", cat = "fun", name = "근육맨", desc = "근력 50 달성", icon = "💪", tier = "silver", metric = "stat:strength", n = 50 },
	{ id = "face_75", cat = "fun", name = "광안리 얼짱", desc = "외모지수 75 달성", icon = "✨", tier = "gold", metric = "stat:appearance", n = 75 },
	{ id = "fish_10", cat = "fun", name = "강태공", desc = "물고기 10마리 낚기", icon = "🎣", tier = "silver", metric = "c:fish_catch", n = 10, key = "fish_catch" },
	{ id = "karaoke_1", cat = "fun", name = "노래방 가수", desc = "노래방에서 한 곡", icon = "🎤", tier = "bronze", metric = "c:karaoke_song", n = 1, key = "karaoke_song" },
	{ id = "hospital", cat = "fun", name = "아프면 병원", desc = "병원에서 진료 받기", icon = "🏥", tier = "bronze", metric = "c:hospital", n = 1 },
	-- 목표 · 레벨
	{ id = "goals_10", cat = "money", name = "목표 달성러", desc = "일일 목표 10개 달성", icon = "🎯", tier = "silver", metric = "goals", n = 10 },
	{ id = "goals_100", cat = "money", name = "갓생러", desc = "일일 목표 100개 달성", icon = "🔥", tier = "gold", metric = "goals", n = 100 },
	{ id = "weekly_4", cat = "money", name = "주간 챔피언", desc = "주간 목표 4번 달성", icon = "🗓️", tier = "gold", metric = "weekly", n = 4 },
	{ id = "level_10", cat = "money", name = "동네 유명인", desc = "인생 레벨 10", icon = "🌟", tier = "gold", metric = "level", n = 10 },
	{ id = "level_20", cat = "money", name = "광안리 재벌", desc = "인생 레벨 20", icon = "👑", tier = "platinum", metric = "level", n = 20 },
}
P.ACH_BY_ID = {}
for _, a in P.ACHIEVEMENTS do
	P.ACH_BY_ID[a.id] = a
end

-------------------------------------------------------------------------------------------------
-- Milestones (the purchases that must feel big): a celebration on the client (confetti, camera
-- pull-back, banner) + a phone message from a friend NPC (ctx.sendMessage contact).
-------------------------------------------------------------------------------------------------
P.MILESTONES = {
	first_pay = { title = "첫 월급! 💵", body = "통장에 첫 급여가 들어왔어요", icon = "💵", camera = false, friend = "minji", msg = "첫 월급 축하해!! 🎉 오늘 치맥 쏘는 거지? ㅋㅋ 🍗" },
	first_home = { title = "내 방이 생겼어요! 🔑", body = "%s 계약 완료 · 오늘부터 여기가 내 집!", icon = "🔑", camera = true, friend = "minji", msg = "헐 너 이사했다며?? 집들이 언제 해!! 🏠🎉" },
	own_home = { title = "내 집 마련 성공! 🏡", body = "%s · 이제 진짜 집주인이에요", icon = "🏡", camera = true, friend = "junho", msg = "와 진짜 집 샀어?? 광안리 집주인 ㄷㄷ 축하한다 🍾" },
	penthouse = { title = "펜트하우스 입주! 🌊", body = "광안대교가 한눈에 보이는 꼭대기 층", icon = "🌊", camera = true, friend = "minji", msg = "펜트하우스라고?!?! 야경 보러 놀러 가도 돼?? 😍🌉" },
	first_car = { title = "첫 차 뽑았다! 🚗", body = "%s · 이제 어디든 내 차로!", icon = "🚗", camera = true, friend = "junho", msg = "차 뽑았다며?! 오늘 밤 광안대교 드라이브 콜? 🚗✨" },
	first_vip = { title = "오늘의 주인공은 나 🍾", body = "CLUB OCEAN VIP 테이블 세팅 완료", icon = "🍾", camera = true, friend = "minji", msg = "VIP 테이블 잡았다는 소문 돌던데?? 나도 불러줘 ㅋㅋ 🥂" },
}
P.MILESTONE_ORDER = { "first_pay", "first_home", "own_home", "penthouse", "first_car", "first_vip" }

-- Friend texts on some level-ups (contact id, text).
P.LEVEL_TEXTS = {
	[3] = { "minji", "요즘 알바 열심히 한다며? 멋지다 👍" },
	[5] = { "junho", "야 너 요즘 잘나간다? 레벨 5면 대출도 된다더라 ㅋㅋ 🏦" },
	[10] = { "minji", "동네에서 다 너 얘기해 ㅋㅋ 유명인 다 됐네 🌟" },
	[15] = { "junho", "자수성가의 아이콘… 나도 좀 알려 줘라 😂" },
	[20] = { "minji", "광안리 재벌님 밥 한 번 사 주세요 🙏💎" },
}

-------------------------------------------------------------------------------------------------
-- Persistent record (d.progress) + sanitize / merge.
-------------------------------------------------------------------------------------------------
P.HISTORY_DAYS = 7
P.MAX_COUNTER = 1e12

function P.defaultData(now: number?): any
	return {
		v = P.VERSION,
		earned = 0, -- lifetime earnings (group "earn")
		spent = 0,
		level = 1,
		c = {}, -- [key] = lifetime count
		ach = {}, -- [achId] = unix time unlocked
		ms = {}, -- [milestoneId] = unix time celebrated
		daily = { day = -1, goals = {}, rerolls = 0, allDone = false },
		weekly = { week = -1, goal = nil },
		days = {}, -- { {d, e, s, cats = {}, ecats = {}, best} } newest last, at most HISTORY_DAYS + 1
		best = { pay = 0, day = 0 },
		goalsDone = 0,
		weeklyDone = 0,
		seen = { cars = 0, tier = 0, owned = false, lifeDay = 0 },
		seeded = false,
		t = now or 0,
	}
end

local function cleanGoal(g: any, byId: { [string]: any }): any?
	if type(g) ~= "table" or type(g.id) ~= "string" or not byId[g.id] then
		return nil
	end
	local n = int(g.n, 1, 1, 1e9)
	return { id = g.id, n = n, have = int(g.have, 0, 0, 1e12), done = g.done == true }
end

local function cleanCats(t: any, allowed: { string }): { [string]: number }
	local out = {}
	if type(t) == "table" then
		for _, k in allowed do
			local v = t[k]
			if finite(v) and v > 0 then
				out[k] = math.floor(math.min(v, P.MAX_COUNTER))
			end
		end
	end
	return out
end

function P.cleanDay(x: any): any?
	if type(x) ~= "table" or not finite(x.d) then
		return nil
	end
	return {
		d = math.floor(x.d),
		e = int(x.e, 0, 0, P.MAX_COUNTER),
		s = int(x.s, 0, 0, P.MAX_COUNTER),
		cats = cleanCats(x.cats, P.SPEND_CATS),
		ecats = cleanCats(x.ecats, P.EARN_CATS),
		best = int(x.best, 0, 0, P.MAX_COUNTER),
	}
end

-- Never errors on garbage; drops unknown ids.
function P.sanitize(raw: any, now: number?): any
	local d = P.defaultData(now)
	if type(raw) ~= "table" then
		return d
	end
	d.earned = int(raw.earned, 0, 0, P.MAX_COUNTER)
	d.spent = int(raw.spent, 0, 0, P.MAX_COUNTER)
	d.level = (P.levelFor(d.earned))
	if type(raw.c) == "table" then
		for k, v in raw.c do
			if type(k) == "string" and #k <= 32 and finite(v) and v > 0 then
				d.c[k] = math.floor(math.min(v, P.MAX_COUNTER))
			end
		end
	end
	if type(raw.ach) == "table" then
		for id, t in raw.ach do
			if P.ACH_BY_ID[id] then
				d.ach[id] = if finite(t) then math.floor(t) else 1
			end
		end
	end
	if type(raw.ms) == "table" then
		for id, t in raw.ms do
			if P.MILESTONES[id] then
				d.ms[id] = if finite(t) then math.floor(t) else 1
			end
		end
	end
	if type(raw.daily) == "table" then
		d.daily.day = int(raw.daily.day, -1)
		d.daily.rerolls = int(raw.daily.rerolls, 0, 0, 9)
		d.daily.allDone = raw.daily.allDone == true
		if type(raw.daily.goals) == "table" then
			for _, g in raw.daily.goals do
				local cg = cleanGoal(g, P.GOAL_BY_ID)
				if cg and #d.daily.goals < P.DAILY_COUNT then
					table.insert(d.daily.goals, cg)
				end
			end
		end
	end
	if type(raw.weekly) == "table" then
		d.weekly.week = int(raw.weekly.week, -1)
		d.weekly.goal = cleanGoal(raw.weekly.goal, P.WEEKLY_BY_ID)
	end
	if type(raw.days) == "table" then
		for _, x in raw.days do
			local cd = P.cleanDay(x)
			if cd then
				table.insert(d.days, cd)
			end
		end
		table.sort(d.days, function(a, b)
			return a.d < b.d
		end)
		while #d.days > P.HISTORY_DAYS + 1 do
			table.remove(d.days, 1)
		end
	end
	if type(raw.best) == "table" then
		d.best.pay = int(raw.best.pay, 0, 0, P.MAX_COUNTER)
		d.best.day = int(raw.best.day, 0, 0, P.MAX_COUNTER)
	end
	d.goalsDone = int(raw.goalsDone, 0, 0, 1e9)
	d.weeklyDone = int(raw.weeklyDone, 0, 0, 1e9)
	if type(raw.seen) == "table" then
		d.seen.cars = int(raw.seen.cars, 0, 0, 999)
		d.seen.tier = int(raw.seen.tier, 0, 0, 9)
		d.seen.owned = raw.seen.owned == true
		d.seen.lifeDay = int(raw.seen.lifeDay, 0, 0)
	end
	d.seeded = raw.seeded == true
	d.t = num(raw.t, now or 0)
	return d
end

-- Merges two records (a server hop can make the fallback store and the live profile diverge): every
-- monotonic number takes the max, unlocks are unioned, daily / weekly goals keep the newer day (max
-- progress on the same day), the history keeps the larger record per day.
function P.merge(a: any, b: any): any
	local x, y = P.sanitize(a), P.sanitize(b)
	local out = P.defaultData(math.max(x.t, y.t))
	out.earned = math.max(x.earned, y.earned)
	out.spent = math.max(x.spent, y.spent)
	out.level = (P.levelFor(out.earned))
	for _, src in { x.c, y.c } do
		for k, v in src do
			out.c[k] = math.max(out.c[k] or 0, v)
		end
	end
	for _, src in { x.ach, y.ach } do
		for k, v in src do
			out.ach[k] = if out.ach[k] then math.min(out.ach[k], v) else v
		end
	end
	for _, src in { x.ms, y.ms } do
		for k, v in src do
			out.ms[k] = if out.ms[k] then math.min(out.ms[k], v) else v
		end
	end
	-- daily
	local dx, dy = x.daily, y.daily
	if dx.day > dy.day then
		out.daily = dx
	elseif dy.day > dx.day then
		out.daily = dy
	else
		out.daily = if #dx.goals >= #dy.goals then dx else dy
		local other = if out.daily == dx then dy else dx
		for i, g in out.daily.goals do
			local og = other.goals[i]
			if og and og.id == g.id then
				g.have = math.max(g.have, og.have)
				g.done = g.done or og.done
			end
		end
		out.daily.rerolls = math.max(dx.rerolls, dy.rerolls)
		out.daily.allDone = dx.allDone or dy.allDone
	end
	-- weekly
	local wx, wy = x.weekly, y.weekly
	if wx.week > wy.week then
		out.weekly = wx
	elseif wy.week > wx.week then
		out.weekly = wy
	else
		out.weekly = wx
		if wx.goal and wy.goal and wx.goal.id == wy.goal.id then
			out.weekly.goal.have = math.max(wx.goal.have, wy.goal.have)
			out.weekly.goal.done = wx.goal.done or wy.goal.done
		elseif not wx.goal then
			out.weekly = wy
		end
	end
	-- history
	local byDay: { [number]: any } = {}
	for _, src in { x.days, y.days } do
		for _, dd in src do
			local cur = byDay[dd.d]
			if not cur or dd.e + dd.s > cur.e + cur.s then
				byDay[dd.d] = dd
			end
		end
	end
	for _, dd in byDay do
		table.insert(out.days, dd)
	end
	table.sort(out.days, function(p, q)
		return p.d < q.d
	end)
	while #out.days > P.HISTORY_DAYS + 1 do
		table.remove(out.days, 1)
	end
	out.best.pay = math.max(x.best.pay, y.best.pay)
	out.best.day = math.max(x.best.day, y.best.day)
	out.goalsDone = math.max(x.goalsDone, y.goalsDone)
	out.weeklyDone = math.max(x.weeklyDone, y.weeklyDone)
	out.seen.cars = math.max(x.seen.cars, y.seen.cars)
	out.seen.tier = math.max(x.seen.tier, y.seen.tier)
	out.seen.owned = x.seen.owned or y.seen.owned
	out.seen.lifeDay = math.max(x.seen.lifeDay, y.seen.lifeDay)
	out.seeded = x.seeded or y.seeded
	return out
end

-------------------------------------------------------------------------------------------------
-- Views (server -> client)
-------------------------------------------------------------------------------------------------
function P.goalView(g: any, weekly: boolean?, level: number, live: boolean?): any?
	if type(g) ~= "table" then
		return nil
	end
	local def = if weekly then P.WEEKLY_BY_ID[g.id] else P.GOAL_BY_ID[g.id]
	if not def then
		return nil
	end
	return {
		id = g.id,
		key = def.key,
		icon = def.icon,
		text = P.goalText(def, g.n),
		n = g.n,
		have = math.min(g.have, g.n),
		done = g.done,
		cash = P.goalCash(def, level, weekly),
		pop = def.pop or 0,
		group = def.group or "weekly",
		money = def.money == true,
		live = live ~= false,
		weekly = weekly == true,
	}
end

function P.dayView(x: any): any?
	if type(x) ~= "table" then
		return nil
	end
	return { d = x.d, e = x.e, s = x.s, net = x.e - x.s, cats = table.clone(x.cats or {}), ecats = table.clone(x.ecats or {}), best = x.best or 0 }
end

-- Checks the data tables (Lune unit test / server start).
function P.validate(): { string }
	local problems = {}
	local seen = {}
	for _, a in P.ACHIEVEMENTS do
		if seen[a.id] then
			table.insert(problems, "duplicate achievement " .. a.id)
		end
		seen[a.id] = true
		if not P.TIERS[a.tier] then
			table.insert(problems, "achievement " .. a.id .. " bad tier")
		end
		if type(a.metric) ~= "string" or not finite(a.n) then
			table.insert(problems, "achievement " .. a.id .. " bad metric")
		end
	end
	for _, g in P.GOALS do
		if not P.KEYS[g.key] then
			table.insert(problems, "goal " .. g.id .. " unknown key " .. g.key)
		end
		if #g.n ~= 3 then
			table.insert(problems, "goal " .. g.id .. " needs 3 bands")
		end
	end
	for _, g in P.WEEKLY do
		if not P.KEYS[g.key] then
			table.insert(problems, "weekly " .. g.id .. " unknown key " .. g.key)
		end
	end
	for i = 2, #P.LEVELS do
		if P.LEVELS[i] <= P.LEVELS[i - 1] then
			table.insert(problems, "levels not increasing at " .. i)
		end
	end
	if #P.ACHIEVEMENTS < 30 then
		table.insert(problems, "fewer than 30 achievements")
	end
	return problems
end

return P
