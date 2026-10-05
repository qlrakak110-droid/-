--!nocheck
-- GwangalliWorkShared (WS): pure logic of the 알바 work simulation, shared by the server (validation,
-- the source of truth), the client (what the nearby station can do, the hints, the ticket text) and
-- the unit tests (tools/tests/work_shared_test.luau, plain Luau). No DataModel access.
--
--   * order state machine   접수(received) → 준비 중(preparing) → 완성(ready) → 전달(delivered) → 종료(closed)
--                            (+ 취소(cancelled) from any open state; a wrong delivery goes back to preparing)
--   * cafe recipes          a drink = cup (temp, size) + ingredients in the order they went in + lid.
--                            WS.judgeCup(cup, spec) compares a made drink to an order item exactly.
--   * satisfaction          accuracy x wait time -> 0..100 + reaction (thanks / ok / complain / angry)
--   * skill                 XP -> level -> real unlocks (menu, options, tools, base pay)
--   * payroll               WS.settle(summary) -> the 정산 lines (기본급 / 성과급 / 보너스 / 마감 수당
--                            + 실수 차감 / 팁 / 할증 extra lines)
--   * 편의점 (v2)           WS.changeOptions (거스름돈 고르기), WS.parcelBand (택배 요금), WS.noteCount (시재)
--   * 배달 (v2)             WS.deliveryQuote (거리 → 단가 / 제한 시간), WS.deliveryResult (시간 · 상태 · 날씨
--                            → 지급액), WS.travelMode (좌석 → 도보 / 자전거 / 오토바이 / 차)

local WS = {}

local C = nil -- GwangalliWorkConfig, set by WS.setConfig (the server / client / test pass it in)

function WS.setConfig(cfg: any)
	C = cfg
end
function WS.config(): any
	return C
end

local function round100(v: number): number
	return math.floor(v / 100 + 0.5) * 100
end
WS.round100 = round100

function WS.won(n: any): string
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(v))
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return (if v < 0 then "-" else "") .. s .. out .. "원"
end

-------------------------------------------------------------------------------------------------
-- Orders: states
-------------------------------------------------------------------------------------------------
WS.STATE_LABEL = {
	received = "접수",
	preparing = "준비 중",
	ready = "완성",
	delivered = "전달",
	closed = "종료",
	cancelled = "취소",
}
local NEXT = {
	received = { preparing = true, ready = true, cancelled = true },
	preparing = { ready = true, cancelled = true, received = true },
	ready = { delivered = true, preparing = true, cancelled = true },
	delivered = { closed = true, preparing = true }, -- preparing: the customer brought it back (wrong drink)
	closed = {},
	cancelled = {},
}
function WS.canMove(from: string, to: string): boolean
	local t = NEXT[from]
	return t ~= nil and t[to] == true
end
function WS.isOpen(state: string): boolean
	return state == "received" or state == "preparing" or state == "ready"
end

-------------------------------------------------------------------------------------------------
-- CAFE: ingredients, menu, recipes
-------------------------------------------------------------------------------------------------
WS.INGREDIENTS = {
	ice = { name = "얼음", icon = "🧊", color = { 210, 235, 250 }, liquid = false, stock = "ice" },
	shot = { name = "에스프레소 샷", icon = "☕", color = { 70, 40, 20 }, liquid = true, stock = "beans" },
	water = { name = "물", icon = "💧", color = { 150, 200, 235 }, liquid = true },
	hotwater = { name = "뜨거운 물", icon = "♨️", color = { 180, 200, 215 }, liquid = true },
	milk = { name = "우유", icon = "🥛", color = { 245, 242, 232 }, liquid = true, stock = "milk" },
	steamed = { name = "스팀 우유", icon = "🥛", color = { 240, 228, 205 }, liquid = true, stock = "milk" },
	foam = { name = "우유 거품", icon = "☁️", color = { 252, 250, 244 }, liquid = true, stock = "milk" },
	vanilla = { name = "바닐라 시럽", icon = "🍯", color = { 230, 200, 140 }, liquid = true, syrup = true, stock = "vanilla" },
	caramel = { name = "카라멜 드리즐", icon = "🍮", color = { 190, 120, 50 }, liquid = true, syrup = true, stock = "caramel" },
}

WS.CAFE_MENU_ORDER = { "americano", "latte", "vanilla_latte", "cappuccino", "caramel_macchiato" }
WS.CAFE_MENU = {
	americano = { name = "아메리카노", icon = "☕", temps = { "ice", "hot" } },
	latte = { name = "카페 라떼", icon = "🥛", temps = { "ice", "hot" } },
	vanilla_latte = { name = "바닐라 라떼", icon = "🍯", temps = { "ice", "hot" } },
	cappuccino = { name = "카푸치노", icon = "☁️", temps = { "hot" } },
	caramel_macchiato = { name = "카라멜 마키아토", icon = "🍮", temps = { "ice", "hot" } },
}
WS.SIZE_LABEL = { tall = "톨", grande = "그란데" }
WS.TEMP_LABEL = { ice = "ICE", hot = "HOT" }

-- spec = { menu, temp = "ice"|"hot", size = "tall"|"grande", extraShot = 0|1 }
function WS.shotsFor(spec: any): number
	return (if spec.size == "grande" then 2 else 1) + (tonumber(spec.extraShot) or 0)
end

-- The exact ingredient counts of a drink, plus the order rules (quality, not identity).
function WS.cafeRecipe(spec: any): any
	local need: { [string]: number } = {}
	local function add(id: string, n: number?)
		need[id] = (need[id] or 0) + (n or 1)
	end
	local iced = spec.temp == "ice"
	local shots = WS.shotsFor(spec)
	local m = spec.menu
	if m == "americano" then
		if iced then
			add("ice")
			add("water")
		else
			add("hotwater")
		end
		add("shot", shots)
	elseif m == "latte" or m == "vanilla_latte" then
		if m == "vanilla_latte" then
			add("vanilla")
		end
		if iced then
			add("ice")
			add("milk")
		else
			add("steamed")
		end
		add("shot", shots)
	elseif m == "cappuccino" then
		add("foam")
		add("shot", shots)
	elseif m == "caramel_macchiato" then
		add("vanilla")
		if iced then
			add("ice")
			add("milk")
		else
			add("steamed")
		end
		add("shot", shots)
		add("caramel")
	end
	-- rules: { a, b, text } = every `a` must go in before any `b` (a minor quality point when broken)
	local rules = {}
	if iced then
		table.insert(rules, { "ice", "liquid", "얼음을 먼저 넣어야 해요" })
	end
	if m == "vanilla_latte" or m == "caramel_macchiato" then
		table.insert(rules, { "vanilla", "milkish", "시럽은 우유보다 먼저" })
	end
	if m == "caramel_macchiato" then
		table.insert(rules, { "milkish", "shot", "마키아토는 우유 위에 샷을 부어요" })
		table.insert(rules, { "shot", "caramel", "카라멜 드리즐은 마지막에" })
	end
	if m == "latte" or m == "vanilla_latte" or m == "cappuccino" then
		table.insert(rules, { "shot", "milkish", "라떼는 샷 위에 우유를 부어요" })
	end
	return { need = need, rules = rules, temp = spec.temp, size = spec.size }
end

local MILKISH = { milk = true, steamed = true, foam = true }

local function matchesClass(id: string, class: string): boolean
	if class == "liquid" then
		local ing = WS.INGREDIENTS[id]
		return ing ~= nil and ing.liquid == true and not ing.syrup
	elseif class == "milkish" then
		return MILKISH[id] == true
	end
	return id == class
end

function WS.specText(spec: any): string
	local menu = WS.CAFE_MENU[spec.menu]
	local name = menu and menu.name or tostring(spec.menu)
	local parts = { (WS.TEMP_LABEL[spec.temp] or "") .. " " .. name, WS.SIZE_LABEL[spec.size] or "톨" }
	if (tonumber(spec.extraShot) or 0) > 0 then
		table.insert(parts, "샷 추가")
	end
	return table.concat(parts, " · ")
end

-- the recipe as an ordered list of steps (for the ticket / step hints)
function WS.cafeSteps(spec: any): { string }
	local r = WS.cafeRecipe(spec)
	local out = { if spec.temp == "ice" then "cup_ice" else "cup_hot" }
	local order = { "vanilla", "ice", "shot", "water", "hotwater", "milk", "steamed", "foam", "caramel" }
	if spec.menu == "caramel_macchiato" then
		order = { "vanilla", "ice", "milk", "steamed", "shot", "caramel" }
	elseif spec.menu == "latte" or spec.menu == "vanilla_latte" or spec.menu == "cappuccino" then
		order = { "vanilla", "ice", "shot", "milk", "steamed", "foam" }
	end
	for _, id in order do
		for _ = 1, r.need[id] or 0 do
			table.insert(out, id)
		end
	end
	table.insert(out, "lid")
	return out
end

-- cup = { temp, size, parts = { ingredient ids in order }, lid }
-- -> { complete, exact, accuracy 0..1, fixable, missing = {id=n}, issues = { {text, severity} } }
function WS.judgeCup(cup: any, spec: any): any
	local r = WS.cafeRecipe(spec)
	local issues = {}
	local accuracy = 1
	local fixable = true
	local function issue(text: string, sev: string, cost: number)
		table.insert(issues, { text = text, severity = sev })
		accuracy -= cost
	end
	if cup.temp ~= spec.temp then
		issue(if spec.temp == "ice" then "아이스 컵이 아니에요" else "핫 컵이 아니에요", "major", 0.8)
		fixable = false
	end
	if cup.size ~= spec.size then
		issue(string.format("사이즈가 달라요 (%s 주문)", WS.SIZE_LABEL[spec.size] or "?"), "minor", 0.35)
		fixable = false
	end
	local have: { [string]: number } = {}
	for _, id in cup.parts or {} do
		have[id] = (have[id] or 0) + 1
	end
	local missing: { [string]: number } = {}
	for id, n in r.need do
		local h = have[id] or 0
		if h < n then
			missing[id] = n - h
		end
	end
	for id, h in have do
		local n = r.need[id] or 0
		if h > n then
			local ing = WS.INGREDIENTS[id]
			if n == 0 then
				issue(string.format("%s이(가) 들어가면 안 돼요", ing and ing.name or id), "major", 0.7)
			elseif id == "shot" then
				issue(string.format("샷이 %d개 많아요", h - n), "minor", 0.35)
			else
				issue(string.format("%s을(를) 너무 많이 넣었어요", ing and ing.name or id), "minor", 0.3)
			end
			fixable = false
		end
	end
	local missingCount = 0
	for id, n in missing do
		missingCount += n
		local ing = WS.INGREDIENTS[id]
		issue(string.format("%s 빠짐", ing and ing.name or id), if cup.lid then "major" else "todo", if cup.lid then 0.5 else 0)
	end
	if cup.lid and missingCount > 0 then
		fixable = false
	end
	-- order rules (quality)
	for _, rule in r.rules do
		local seenB = false
		local broken = false
		for _, id in cup.parts or {} do
			if matchesClass(id, rule[2]) and not matchesClass(id, rule[1]) then
				seenB = true
			elseif matchesClass(id, rule[1]) and seenB then
				broken = true
			end
		end
		if broken then
			issue(rule[3], "quality", 0.1)
		end
	end
	if cup.spilled then
		issue("음료를 쏟았어요", "major", 0.8)
		fixable = false
	end
	local complete = missingCount == 0 and cup.lid == true
	local exact = complete and #issues == 0
	if not cup.lid and missingCount == 0 and fixable then
		table.insert(issues, { text = "뚜껑을 닫아야 해요", severity = "todo" })
	end
	return {
		complete = complete,
		exact = exact,
		accuracy = math.clamp(accuracy, 0, 1),
		fixable = fixable,
		missing = missing,
		issues = issues,
	}
end

-- the next step for a cup being made for `spec` (hints); nil when done
function WS.cafeNextStep(cup: any?, spec: any): string?
	if not cup then
		return if spec.temp == "ice" then "cup_ice" else "cup_hot"
	end
	local j = WS.judgeCup(cup, spec)
	if not j.fixable then
		return "discard"
	end
	for _, step in WS.cafeSteps(spec) do
		if j.missing[step] and j.missing[step] > 0 then
			return step
		end
	end
	if not cup.lid then
		return "lid"
	end
	return "pickup"
end

WS.STEP_LABEL = {
	cup_ice = "아이스 컵 꺼내기",
	cup_hot = "핫 컵 꺼내기",
	ice = "얼음 담기",
	shot = "에스프레소 추출",
	water = "물 붓기",
	hotwater = "뜨거운 물 붓기",
	milk = "우유 붓기",
	steamed = "우유 스팀 → 붓기",
	foam = "우유 거품 올리기",
	vanilla = "바닐라 시럽 펌프",
	caramel = "카라멜 드리즐",
	lid = "뚜껑 닫기",
	pickup = "픽업대에 올리고 호출",
	discard = "다시 만들기 (폐기)",
}
-- the station where a step happens
WS.STEP_STATION = {
	cup_ice = "cups",
	cup_hot = "cups",
	ice = "ice",
	shot = "machine1", -- Cafe.hint swaps in machine2 when machine 1 is busy / missing
	water = "water",
	hotwater = "water",
	milk = "milk",
	steamed = "steam",
	foam = "steam",
	vanilla = "syrup",
	caramel = "syrup",
	lid = "lids",
	pickup = "pickup",
	discard = "trash",
}

-- the menu / options a cafe worker of `level` gets
function WS.cafeUnlocks(level: number): any
	local menus = {}
	for lv = 1, math.clamp(level, 1, #C.CAFE.menuByLevel) do
		for _, m in C.CAFE.menuByLevel[lv] do
			table.insert(menus, m)
		end
	end
	local opts = {}
	for k, lv in C.CAFE.optionsByLevel do
		opts[k] = level >= lv
	end
	local tools = {}
	for k, t in C.CAFE.tools do
		tools[k] = level >= t.level
	end
	return { menus = menus, options = opts, tools = tools }
end

-- a random order item for a customer (test customers; NPC orders may pass their own spec)
function WS.genCafeItem(rand: (number) -> number, level: number): any
	local u = WS.cafeUnlocks(level)
	local menu = u.menus[rand(#u.menus)]
	local def = WS.CAFE_MENU[menu]
	local temp = def.temps[1]
	if #def.temps > 1 then
		-- before the temp option unlocks, lattes / americanos come iced only for beginners
		if u.options.temp or menu == "americano" then
			temp = def.temps[rand(#def.temps)]
		end
	end
	local size = if u.options.size and rand(2) == 1 then "grande" else "tall"
	local extra = if u.options.shot and rand(5) == 1 then 1 else 0
	return { menu = menu, temp = temp, size = size, extraShot = extra }
end

function WS.validItem(spec: any): boolean
	if type(spec) ~= "table" or not WS.CAFE_MENU[spec.menu] then
		return false
	end
	if not table.find(WS.CAFE_MENU[spec.menu].temps, spec.temp) then
		return false
	end
	return (spec.size == "tall" or spec.size == "grande") and (spec.extraShot == 0 or spec.extraShot == 1)
end

function WS.cafePerf(spec: any): number
	local base = C.CAFE.perfByMenu[spec.menu] or 1000
	local opts = 0
	if spec.size == "grande" then
		opts += 1
	end
	if (tonumber(spec.extraShot) or 0) > 0 then
		opts += 1
	end
	if spec.temp == "hot" and spec.menu ~= "cappuccino" then
		opts += 1 -- steaming takes longer
	end
	return base + opts * C.CAFE.perfPerOption
end

-- the cup an order item needs (stock id)
function WS.cupStock(temp: string): string
	return if temp == "hot" then "cup_hot" else "cup_ice"
end

-------------------------------------------------------------------------------------------------
-- Satisfaction (0..100) and the reaction the NPC session shows
-------------------------------------------------------------------------------------------------
-- accuracy 0..1 (mean over the items), waited = seconds from order to hand-over
function WS.satisfaction(accuracy: number, waited: number, target: number, patience: number): (number, string)
	local S = C.SATISFACTION
	local speed = 1
	if waited > target then
		speed = math.clamp(1 - (waited - target) / math.max(1, patience - target), 0, 1)
	end
	local score = math.floor((math.clamp(accuracy, 0, 1) * S.weightAccuracy + speed * S.weightSpeed) * 100 + 0.5)
	local reaction = if score >= S.thanks then "thanks" elseif score >= S.ok then "ok" elseif score >= S.complain then "complain" else "angry"
	return score, reaction
end

WS.REACTION_LABEL = { thanks = "감사", ok = "보통", complain = "불평", angry = "불만 퇴점", left = "기다리다 떠남" }

-------------------------------------------------------------------------------------------------
-- Skill
-------------------------------------------------------------------------------------------------
function WS.level(xp: any): number
	local x = tonumber(xp) or 0
	local lv = 1
	for i, need in C.LEVELS.xp do
		if x >= need then
			lv = i
		end
	end
	return lv
end

function WS.levelTitle(track: string, level: number): string
	local t = C.LEVELS.titles[track]
	return t and t[math.clamp(level, 1, #t)] or ("Lv." .. level)
end

-- 직급 (신입 / 직원 / 숙련 직원 / 매니저급), the same for every track
function WS.levelRank(level: number): string
	local r = C.LEVELS.ranks
	return r and r[math.clamp(level, 1, #r)] or ("Lv." .. level)
end

-- is a duty of a track unlocked at this level? (C.UNLOCKS; unknown duty = always)
function WS.unlocked(track: string, duty: string, level: number): boolean
	local u = C.UNLOCKS and C.UNLOCKS[track] and C.UNLOCKS[track][duty]
	return u == nil or level >= u.level
end

-- XP needed for the next level (nil at max) and progress 0..1
function WS.levelProgress(xp: any): (number?, number)
	local x = tonumber(xp) or 0
	local lv = WS.level(x)
	local cur = C.LEVELS.xp[lv]
	local nxt = C.LEVELS.xp[lv + 1]
	if not nxt then
		return nil, 1
	end
	return nxt, math.clamp((x - cur) / math.max(1, nxt - cur), 0, 1)
end

function WS.baseRate(level: number): number
	local list = C.PAY.baseRateByLevel
	return list[math.clamp(level, 1, #list)]
end

-- what reaching `level` on `track` changes (shown on level-up and on the job board)
function WS.unlocksAt(track: string, level: number): { string }
	local out = {}
	local prev = WS.baseRate(level - 1)
	local now = WS.baseRate(level)
	if level > 1 and now > prev then
		table.insert(out, string.format("기본급 %s → %s /분", WS.won(prev), WS.won(now)))
	end
	if track == "cafe" then
		for _, m in C.CAFE.menuByLevel[level] or {} do
			table.insert(out, "새 메뉴: " .. (WS.CAFE_MENU[m] and WS.CAFE_MENU[m].name or m))
		end
		local optName = { size = "사이즈 옵션 (톨/그란데)", temp = "온도 선택 (HOT/ICE)", shot = "샷 추가 주문" }
		for k, lv in C.CAFE.optionsByLevel do
			if lv == level then
				table.insert(out, "주문 옵션: " .. optName[k])
			end
		end
		for _, t in C.CAFE.tools do
			if t.level == level then
				table.insert(out, "도구: " .. t.label .. " — " .. t.desc)
			end
		end
	end
	for _, u in (C.UNLOCKS and C.UNLOCKS[track]) or {} do
		if u.level == level then
			table.insert(out, "새 업무: " .. u.label)
		end
	end
	if C.LEVELS.ranks and level > 1 and C.LEVELS.ranks[level] ~= C.LEVELS.ranks[level - 1] then
		table.insert(out, "직급: " .. C.LEVELS.ranks[level])
	end
	if C.PAY.perfMultByLevel and level > 1 then
		local a, b = C.PAY.perfMultByLevel[level - 1], C.PAY.perfMultByLevel[level]
		if a and b and b > a then
			table.insert(out, string.format("성과급 배율 x%.2f → x%.2f", a, b))
		end
	end
	for jobId, job in C.JOBS do
		if job.requires and job.requires[track] == level then
			table.insert(out, "새 근무처 지원 가능: " .. job.title)
		end
	end
	return out
end

-- can a player with these track levels apply to `jobId`?  -> ok, reason
function WS.canApply(jobId: string, levels: { [string]: number }): (boolean, string?)
	local job = C.JOBS[jobId]
	if not job then
		return false, "없는 공고예요"
	end
	if not job.requires then
		return true, nil
	end
	local need = {}
	local okAny = false
	local okAll = true
	for track, lv in job.requires do
		local have = levels[track] or 1
		if have >= lv then
			okAny = true
		else
			okAll = false
		end
		table.insert(need, string.format("%s Lv.%d", C.LEVELS.titles[track] and C.LEVELS.titles[track][1] and ({ cafe = "카페", cvs = "편의점", kitchen = "주방", delivery = "배달" })[track] or track, lv))
	end
	local ok = if job.requiresAny then okAny else okAll
	if ok then
		return true, nil
	end
	return false, "필요 숙련도: " .. table.concat(need, if job.requiresAny then " 또는 " else ", ")
end

-------------------------------------------------------------------------------------------------
-- Payroll: the 정산 of one shift
--   s = { level, workedSeconds, early (bool), closeDone (bool), units = { { perf, accuracy (0..1),
--          fast (bool), exact (bool), group (bool) } }, tasks = n, taskPerf = won }
-- -> { lines = { { key, label, note, amount } }, total }
-------------------------------------------------------------------------------------------------
function WS.settle(s: any): any
	local lines = {}
	local function add(key: string, label: string, note: string?, amount: number)
		amount = round100(amount)
		if amount ~= 0 then
			table.insert(lines, { key = key, label = label, note = note, amount = amount })
		end
	end
	local rate = WS.baseRate(s.level or 1)
	local minutes = math.max(0, (tonumber(s.workedSeconds) or 0) / 60)
	add("base", "기본급", string.format("%.1f분 × %s (Lv.%d)", minutes, WS.won(rate), s.level or 1), rate * minutes)
	local perf, acc, fast, group = 0, 0, 0, 0
	local count, exact = 0, 0
	for _, u in s.units or {} do
		count += 1
		local p = (tonumber(u.perf) or 0) * math.clamp(tonumber(u.accuracy) or 0, 0, 1)
		perf += p
		if u.exact then
			exact += 1
			acc += (tonumber(u.perf) or 0) * C.PAY.accuracyBonus
		end
		if u.fast then
			fast += (tonumber(u.perf) or 0) * C.PAY.serviceBonus
		end
		if u.group and u.exact then
			group += (tonumber(u.perf) or 0) * C.PAY.groupBonus
		end
	end
	perf += tonumber(s.taskPerf) or 0
	local mult = (C.PAY.perfMultByLevel and C.PAY.perfMultByLevel[math.clamp(s.level or 1, 1, #C.PAY.perfMultByLevel)]) or 1
	perf *= mult
	acc *= mult
	fast *= mult
	group *= mult
	add("perf", "성과급", string.format("완료 %d건 + 작업 %d건%s", count, tonumber(s.tasks) or 0, if mult > 1 then string.format(" · x%.2f", mult) else ""), perf)
	add("accuracy", "정확도 보너스", string.format("완벽 %d / %d건", exact, count), acc)
	add("service", "빠른 서비스 보너스", nil, fast)
	add("group", "단체 주문 보너스", nil, group)
	if s.closeDone and not s.early then
		add("close", "마감 수당", "마감 업무 완료", rate * C.PAY.closeBonusMinutes)
	end
	-- extra lines (팁 / 우천 할증 / 단체 배달 ...): { key, label, note?, amount >= 0 }
	for _, e in s.extras or {} do
		local amt = tonumber(e.amount) or 0
		if amt > 0 then
			add(tostring(e.key or "extra"), tostring(e.label or "추가 수당"), e.note, amt)
		end
	end
	-- 실수 차감: only out of the performance part (never below zero, the base pay stays)
	local penalty = 0
	local notes = {}
	for _, pz in s.penalties or {} do
		local amt = math.max(0, tonumber(pz.amount) or 0)
		if amt > 0 then
			penalty += amt
			if #notes < 3 then
				table.insert(notes, tostring(pz.label or "실수"))
			end
		end
	end
	if penalty > 0 then
		local perfPart = 0
		for _, l in lines do
			if l.key ~= "base" and l.key ~= "close" and l.key ~= "tip" then
				perfPart += l.amount
			end
		end
		local cap = perfPart * (C.PAY.penaltyCap or 1)
		penalty = math.min(penalty, cap)
		if penalty > 0 then
			add("penalty", "실수 차감", table.concat(notes, ", ") .. (if #(s.penalties or {}) > 3 then " 외" else ""), -penalty)
		end
	end
	local total = 0
	for _, l in lines do
		total += l.amount
	end
	if (C.PAY.taxRate or 0) > 0 and total > 0 then
		local tax = math.floor(total * C.PAY.taxRate / 10) * 10
		table.insert(lines, { key = "tax", label = "원천징수", note = string.format("%.1f%%", C.PAY.taxRate * 100), amount = -tax })
		total -= tax
	end
	if total < (C.PAY.minPayout or 0) then
		total = 0
	end
	return { lines = lines, total = total, exact = exact, count = count }
end

-------------------------------------------------------------------------------------------------
-- 편의점 (CVS) helpers
-------------------------------------------------------------------------------------------------
function WS.product(id: string): any?
	for _, p in C.CVS.products do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- the note a cash customer hands over for `total` (the smallest note or two that cover it)
function WS.cashPaid(total: number, rand: (number) -> number): number
	local notes = C.CVS.cashNotes
	for _, n in notes do
		if n >= total then
			-- now and then the customer pays with a bigger note
			if rand(3) == 1 then
				for _, m in notes do
					if m > n and m <= n * 10 then
						return m
					end
				end
			end
			return n
		end
	end
	return math.ceil(total / notes[#notes]) * notes[#notes]
end

-- 거스름돈 choices: the right change + 2 plausible mistakes, shuffled. -> { amounts }, correct index
function WS.changeOptions(total: number, paid: number, rand: (number) -> number): ({ number }, number)
	local right = paid - total
	local wrongs = {}
	for _, d in { 1000, -1000, 500, -500, 100, -100, 5000 } do
		local v = right + d
		if v >= 0 and v ~= right and not table.find(wrongs, v) then
			table.insert(wrongs, v)
		end
	end
	-- 2 random distinct wrong values
	local opts = { right }
	while #opts < 3 and #wrongs > 0 do
		table.insert(opts, table.remove(wrongs, rand(#wrongs)))
	end
	for i = #opts, 2, -1 do
		local j = rand(i)
		opts[i], opts[j] = opts[j], opts[i]
	end
	return opts, table.find(opts, right) :: number
end

-- 택배 요금 band for a weight; nil = over the limit (refuse)
function WS.parcelBand(kg: number): number?
	if kg > C.CVS.parcelMaxKg then
		return nil
	end
	for i, b in C.CVS.parcelRates do
		if kg <= b.max then
			return i
		end
	end
	return nil
end

-- the drawer split into notes / coins (for the 시재 count) -> { { value, n } }
function WS.noteCount(amount: number): { any }
	local out = {}
	local left = math.max(0, math.floor(amount))
	for _, v in { 50000, 10000, 5000, 1000, 500, 100, 50, 10 } do
		local n = left // v
		if n > 0 then
			table.insert(out, { value = v, n = n })
			left -= n * v
		end
	end
	return out
end

function WS.cvsPerf(itemCount: number): number
	return C.CVS.perfBase + C.CVS.perfPerItem * math.max(0, itemCount - 1)
end

-------------------------------------------------------------------------------------------------
-- 배달 (DELIVERY) helpers
-------------------------------------------------------------------------------------------------
-- how the courier travels: seated vehicle kind / model name -> walk | bicycle | motorbike | car
function WS.travelMode(seated: boolean, kind: string?, name: string?): string
	if not seated then
		return "walk"
	end
	local k = string.lower(tostring(kind or "") .. " " .. tostring(name or ""))
	if string.find(k, "bicycle", 1, true) or string.find(k, "bike", 1, true) and not string.find(k, "motor", 1, true) or string.find(k, "자전거", 1, true) then
		return "bicycle"
	end
	if string.find(k, "motor", 1, true) or string.find(k, "scooter", 1, true) or string.find(k, "오토바이", 1, true) or string.find(k, "스쿠터", 1, true) then
		return "motorbike"
	end
	return "car"
end
WS.MODE_LABEL = { walk = "도보", bicycle = "자전거", motorbike = "오토바이", car = "차량" }

-- the offer for a call: kind = "food" | "quick"; dist in studs -> pay, time limit (s)
function WS.deliveryQuote(kind: string, dist: number, opts: any?): (number, number)
	local D = C.DELIVERY
	local m = D[kind] or D.food
	local d = math.clamp(dist, 0, D.maxDist * 1.5)
	local pay = m.base + d * m.perStud
	local limit = m.timeBase + d / m.timeSpeed
	local o = opts or {}
	if o.premium then
		pay *= D.premiumMult
		limit *= 0.9
	end
	if o.size and o.size > 1 then
		pay *= 1 + 0.15 * (o.size - 1)
	end
	return round100(pay), math.floor(limit)
end

-- the result of one drop: info = { pay, limit, elapsed, condition (0..100), rain, mistakes, premium }
-- -> { pay (won, before rain), rainBonus, lateFactor, onTime, accuracy 0..1, exact, grade }
function WS.deliveryResult(info: any): any
	local D = C.DELIVERY
	local pay = tonumber(info.pay) or 0
	local limit = math.max(1, tonumber(info.limit) or 60)
	local elapsed = math.max(0, tonumber(info.elapsed) or 0)
	local cond = math.clamp(tonumber(info.condition) or 100, 0, 100)
	local late = math.max(0, elapsed - limit)
	local lateFactor = if late <= 0 then 1 else math.max(D.lateMinFactor, 1 - late / limit)
	local condFactor = 0.4 + 0.6 * (cond / 100)
	if info.premium then
		condFactor = 0.2 + 0.8 * (cond / 100)
	end
	local mistakes = math.max(0, tonumber(info.mistakes) or 0)
	local accuracy = math.clamp(condFactor - 0.08 * mistakes, 0, 1)
	local base = round100(pay * lateFactor)
	local rainBonus = if info.rain then round100(base * D.rainBonus) else 0
	local onTime = late <= 0
	local exact = onTime and cond >= 90 and mistakes == 0
	local grade = if exact then "완벽" elseif onTime and cond >= 70 then "좋음" elseif onTime then "음식 상태 나쁨" else "지각"
	return { pay = base, rainBonus = rainBonus, lateFactor = lateFactor, onTime = onTime, accuracy = accuracy, exact = exact, grade = grade, late = late }
end

-------------------------------------------------------------------------------------------------
-- Shift phases
-------------------------------------------------------------------------------------------------
-- t = seconds since clock-in, len = shift seconds -> phase id, phase index, phase progress 0..1
function WS.phaseAt(t: number, len: number): (string, number, number)
	local acc = 0
	for i, p in C.SHIFT.phases do
		local d = p.share * len
		if t < acc + d or i == #C.SHIFT.phases then
			return p.id, i, math.clamp((t - acc) / math.max(1, d), 0, 1)
		end
		acc += d
	end
	return "close", #C.SHIFT.phases, 1
end

function WS.shiftLength(id: any): number
	for _, l in C.SHIFT.lengths do
		if l.id == id then
			return l.seconds
		end
	end
	for _, l in C.SHIFT.lengths do
		if l.id == C.SHIFT.defaultLength then
			return l.seconds
		end
	end
	return 300
end

-------------------------------------------------------------------------------------------------
-- Save data (profile field `work`): sanitize what came from the DataStore
--   { v, xp = { track = n }, paid = { shiftId, ... } (last 40), goal = { kind, id, ... }?,
--     history = { { t, job, net } } (last 10), hints = 0|1|2|nil, length = "short"|"normal"|"long",
--     open = { id, job, startedAt, units, worked } (an unsettled shift; settled on the next load) }
-------------------------------------------------------------------------------------------------
function WS.sanitizeSave(raw: any): any
	local out = { v = 1, xp = {}, paid = {}, history = {}, goal = nil, hints = nil, length = nil, open = nil }
	if type(raw) ~= "table" then
		return out
	end
	if type(raw.xp) == "table" then
		for track, x in raw.xp do
			if type(track) == "string" and C.LEVELS.titles[track] and type(x) == "number" and x == x then
				out.xp[track] = math.clamp(math.floor(x), 0, 10 ^ 7)
			end
		end
	end
	if type(raw.paid) == "table" then
		for _, id in raw.paid do
			if type(id) == "string" and #id <= 40 then
				table.insert(out.paid, id)
			end
		end
		while #out.paid > 40 do
			table.remove(out.paid, 1)
		end
	end
	if type(raw.history) == "table" then
		for _, h in raw.history do
			if type(h) == "table" and type(h.net) == "number" and h.net == h.net then
				table.insert(out.history, { t = tonumber(h.t) or 0, job = if type(h.job) == "string" then string.sub(h.job, 1, 30) else "", net = math.max(0, math.floor(h.net)) })
			end
		end
		while #out.history > 10 do
			table.remove(out.history, 1)
		end
	end
	if type(raw.goal) == "table" and type(raw.goal.kind) == "string" and type(raw.goal.id) == "string" then
		out.goal = { kind = string.sub(raw.goal.kind, 1, 20), id = string.sub(raw.goal.id, 1, 40), grade = if type(raw.goal.grade) == "string" then string.sub(raw.goal.grade, 1, 10) else nil, field = if type(raw.goal.field) == "string" then string.sub(raw.goal.field, 1, 10) else nil }
	end
	if raw.hints == 0 or raw.hints == 1 or raw.hints == 2 then
		out.hints = raw.hints
	end
	if raw.length == "short" or raw.length == "normal" or raw.length == "long" then
		out.length = raw.length
	end
	if type(raw.open) == "table" and type(raw.open.id) == "string" and type(raw.open.job) == "string" then
		local o = raw.open
		out.open = {
			id = string.sub(o.id, 1, 40),
			job = string.sub(o.job, 1, 30),
			level = math.clamp(math.floor(tonumber(o.level) or 1), 1, 5),
			worked = math.clamp(tonumber(o.worked) or 0, 0, 3600),
			perf = math.clamp(tonumber(o.perf) or 0, 0, 10 ^ 6),
			count = math.clamp(math.floor(tonumber(o.count) or 0), 0, 1000),
			t = tonumber(o.t) or 0,
		}
	end
	return out
end

function WS.isPaid(save: any, shiftId: string): boolean
	for _, id in save.paid do
		if id == shiftId then
			return true
		end
	end
	return false
end

return WS
