--!nocheck
-- GwangalliJobsShared (JS): data and pure functions for the 알바 MINI-GAMES (docs/JOBS.md).
-- Required by the server (GwangalliGameplay/Jobs + JobGames), the client (GwangalliJobs) and the
-- Lune unit test. Nothing here touches the DataModel, so it also loads in plain Lune.
--
-- A shift task with kind = "game" is one ROUND of one of these games. The server generates the
-- round with JS.gen[game](rand, info) -> { secret, view }: `view` goes to the client, `secret` stays
-- on the server and is checked with JS.check[game](secret, view, answer) -> score 0..1.
--
-- Remote: RemoteEvent "JobGame" in ReplicatedStorage.GwangalliRemotes (created by Jobs.luau).
--   client -> server  { op = "answer", taskId, answer }        the round's answer (one per round)
--                     { op = "ready",  taskId }                the UI is up (optional)
--                     { op = "quit" }                          leave the shift (pays what was earned)
--   server -> client  { op = "round", taskId, game, title, icon, prompt, view, timeLimit, round,
--                       total, combo, earned, jobId, jobTitle, jobIcon, payMult, payReason }
--                     { op = "result", taskId, ok, score, pay, base, combo, comboMult, speedBonus,
--                       payMult, payReason, message, earned, last }
--                     { op = "summary", jobId, jobTitle, jobIcon, rounds, perfect, earned, bonus,
--                       total, maxCombo, seconds, reason, completed }
--                     { op = "delivery", ... }                 current delivery (see Jobs.luau)
--                     { op = "close" }                         hide everything

local JS = {}

JS.VERSION = 1
JS.Remote = "JobGame"

-------------------------------------------------------------------------------------------------
-- Tuning (docs/JOBS.md has the table)
-------------------------------------------------------------------------------------------------
JS.NET_SLACK = 1.5 -- seconds of grace on every timer (remote latency)
JS.COMBO_STEP = 0.1 -- +10 % pay per combo step
JS.COMBO_MAX = 5 -- combo caps at x1.5
JS.SPEED_BONUS = 0.25 -- +25 % when a perfect round finishes within SPEED_FRACTION of the time
JS.SPEED_FRACTION = 0.5
JS.PARTIAL_FLOOR = 0.5 -- a half-right round pays score * this + ... (see JS.scoreMult)
JS.RESULT_SECONDS = 1.3 -- the client shows the result card this long before the next round
JS.MIN_ROUND_SECONDS = 0.6 -- answers faster than this are bots
JS.PASS_SCORE = 0.5 -- below this the round counts as failed (no pay, combo reset)

-- Games -------------------------------------------------------------------------------------------
-- timeLimit: seconds for the round; the shift task may override it.
JS.GAME_ORDER = { "pos", "shelf", "expiry", "parcel", "drink", "latte", "order", "sale", "ask" }
JS.GAMES = {
	pos = { title = "계산대", icon = "🧾", timeLimit = 22, hint = "손님 장바구니 순서대로 상품을 찍어요" },
	shelf = { title = "재고 정리", icon = "📦", timeLimit = 60, hint = "빈 칸 앞에서 박스 속 상품을 골라 넣어요" },
	expiry = { title = "유통기한 체크", icon = "📅", timeLimit = 20, hint = "빛나는 상품 중 날짜 지난 걸 톡!" },
	parcel = { title = "택배 접수", icon = "📦", timeLimit = 20, hint = "무게를 보고 요금표에서 골라요" },
	drink = { title = "음료 만들기", icon = "🥤", timeLimit = 22, hint = "주문서 순서대로 재료를 넣어요" },
	latte = { title = "라떼 아트", icon = "🎨", timeLimit = 9, hint = "링이 컵에 닿는 순간 탭!" },
	order = { title = "배달 주문 고르기", icon = "🛵", timeLimit = 40, hint = "거리와 팁을 보고 주문을 골라요" },
	-- world rounds (GwangalliJobs/World.luau shows them IN the store; the bottom sheet only helps)
	sale = { title = "계산", icon = "🧾", timeLimit = 30, hint = "카운터 위 상품을 톡톡 찍고 거스름돈을 골라요" },
	ask = { title = "손님 응대", icon = "💬", timeLimit = 15, hint = "손님 말에 알맞게 대답해요" },
}

-------------------------------------------------------------------------------------------------
-- Catalogs (generic Korean names, no trademarks)
-------------------------------------------------------------------------------------------------
JS.CATEGORY_ORDER = { "food", "snack", "drink", "life" }
JS.CATEGORIES = {
	food = { name = "즉석식품", icon = "🍱" },
	snack = { name = "과자·간식", icon = "🍫" },
	drink = { name = "음료", icon = "🥤" },
	life = { name = "생활용품", icon = "🧴" },
}

-- 12 products: id, name, icon, price (won), cat
JS.PRODUCTS = {
	{ id = "samgak", name = "삼각김밥", icon = "🍙", price = 1200, cat = "food" },
	{ id = "dosirak", name = "도시락", icon = "🍱", price = 4500, cat = "food" },
	{ id = "ramen", name = "컵라면", icon = "🍜", price = 1500, cat = "food" },
	{ id = "sandwich", name = "샌드위치", icon = "🥪", price = 2800, cat = "food" },
	{ id = "choco", name = "초코바", icon = "🍫", price = 1000, cat = "snack" },
	{ id = "chips", name = "감자칩", icon = "🥔", price = 1700, cat = "snack" },
	{ id = "gum", name = "껌", icon = "🍬", price = 800, cat = "snack" },
	{ id = "icecream", name = "아이스크림", icon = "🍦", price = 1300, cat = "snack" },
	{ id = "water", name = "생수", icon = "💧", price = 900, cat = "drink" },
	{ id = "cola", name = "콜라", icon = "🥤", price = 1800, cat = "drink" },
	{ id = "milk", name = "우유", icon = "🥛", price = 1600, cat = "drink" },
	{ id = "coffee", name = "캔커피", icon = "☕", price = 1400, cat = "drink" },
	{ id = "tissue", name = "물티슈", icon = "🧻", price = 2000, cat = "life" },
	{ id = "battery", name = "건전지", icon = "🔋", price = 3500, cat = "life" },
	{ id = "soap", name = "손세정제", icon = "🧴", price = 2500, cat = "life" },
	{ id = "umbrella", name = "우산", icon = "☂️", price = 6000, cat = "life" },
}
JS.PRODUCT_BY_ID = {}
for _, p in JS.PRODUCTS do
	JS.PRODUCT_BY_ID[p.id] = p
end

-- 편의점 택배 요금표 (generic): weight bands
JS.PARCEL_RATES = {
	{ max = 1, label = "1kg 이하", price = 1800 },
	{ max = 5, label = "5kg 이하", price = 2300 },
	{ max = 10, label = "10kg 이하", price = 2800 },
	{ max = 20, label = "20kg 이하", price = 3800 },
}
JS.PARCEL_MAX_KG = 20
JS.PARCEL_DESTS = { "서울", "대구", "대전", "울산", "창원", "제주", "광주", "인천" }

-- Cafe ingredients + recipes (2-3 steps)
JS.INGREDIENT_ORDER = { "shot", "milk", "ice", "syrup", "water", "foam", "cream", "tea" }
JS.INGREDIENTS = {
	shot = { name = "샷", icon = "☕" },
	milk = { name = "우유", icon = "🥛" },
	ice = { name = "얼음", icon = "🧊" },
	syrup = { name = "시럽", icon = "🍯" },
	water = { name = "물", icon = "💧" },
	foam = { name = "우유 폼", icon = "☁️" },
	cream = { name = "크림", icon = "🍦" },
	tea = { name = "티백", icon = "🍵" },
}
JS.DRINKS = {
	{ id = "americano_hot", name = "아메리카노 (HOT)", icon = "☕", steps = { "shot", "water" } },
	{ id = "americano_ice", name = "아이스 아메리카노", icon = "🧋", steps = { "shot", "water", "ice" } },
	{ id = "latte_hot", name = "카페 라떼 (HOT)", icon = "🥛", steps = { "shot", "milk" } },
	{ id = "latte_ice", name = "아이스 카페 라떼", icon = "🥤", steps = { "shot", "milk", "ice" } },
	{ id = "vanilla", name = "바닐라 라떼", icon = "🍮", steps = { "syrup", "shot", "milk" } },
	{ id = "cappuccino", name = "카푸치노", icon = "☁️", steps = { "shot", "milk", "foam" } },
	{ id = "cream_latte", name = "크림 라떼", icon = "🍦", steps = { "shot", "milk", "cream" } },
	{ id = "icetea", name = "아이스 티", icon = "🍹", steps = { "tea", "water", "ice" } },
	{ id = "milktea", name = "밀크티", icon = "🧋", steps = { "tea", "milk", "syrup" } },
}

-- Delivery dishes (rider job)
JS.DISHES = {
	{ name = "모둠회 세트", icon = "🐟" },
	{ name = "매운탕", icon = "🍲" },
	{ name = "떡볶이 세트", icon = "🍢" },
	{ name = "치킨", icon = "🍗" },
	{ name = "피자", icon = "🍕" },
	{ name = "김밥 세트", icon = "🍙" },
	{ name = "커피 4잔", icon = "☕" },
	{ name = "조개구이", icon = "🦪" },
	{ name = "돈까스", icon = "🍱" },
	{ name = "빙수", icon = "🍧" },
}

-- Delivery pay: base (the job's task pay) + distance pay + tip when under the time limit.
JS.DELIVERY = {
	perStud = 1.5, -- won per stud of pickup -> drop-off distance (600 studs = +900원)
	minDist = 120, -- studs; shorter orders are not offered
	tipRate = 0.3, -- tip = (base + distance pay) * tipRate when delivered within the time limit
	timeBase = 25, -- seconds + dist / timeSpeed
	timeSpeed = 8, -- studs per second the time limit assumes (walking is ~16)
	offers = 3, -- orders to choose from
	radius = 30, -- arrive within this of the Destination
}

-------------------------------------------------------------------------------------------------
-- Pure helpers
-------------------------------------------------------------------------------------------------
local function round100(v: number): number
	return math.floor(v / 100 + 0.5) * 100
end
JS.round100 = round100

function JS.comboMult(combo: number): number
	local c = math.clamp(math.floor(tonumber(combo) or 0), 0, JS.COMBO_MAX)
	return 1 + JS.COMBO_STEP * c
end

-- Score 0..1 -> pay multiplier: fail (< PASS_SCORE) = 0, otherwise 0.5..1.
function JS.scoreMult(score: number): number
	local s = math.clamp(tonumber(score) or 0, 0, 1)
	if s < JS.PASS_SCORE then
		return 0
	end
	return JS.PARTIAL_FLOOR + (1 - JS.PARTIAL_FLOOR) * s
end

-- "피로해서 집중이 안 돼요 -30%" (shown when the health module lowers pay)
function JS.describeMult(mult: number, reason: string?): string?
	local m = tonumber(mult) or 1
	if m >= 0.999 then
		return nil
	end
	local pct = math.floor((1 - m) * 100 + 0.5)
	local why = if type(reason) == "string" and reason ~= "" then reason else "피로해서 집중이 안 돼요"
	return string.format("%s -%d%%", why, pct)
end

function JS.won(n: any): string
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(v))
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return (if v < 0 then "-" else "") .. s .. out .. "원"
end

function JS.deliveryTimeLimit(dist: number): number
	return math.floor(JS.DELIVERY.timeBase + math.max(0, dist) / JS.DELIVERY.timeSpeed)
end

function JS.deliveryPay(basePay: number, dist: number): (number, number)
	local pay = round100(basePay + math.max(0, dist) * JS.DELIVERY.perStud)
	local tip = round100(pay * JS.DELIVERY.tipRate)
	return pay, tip
end

-- Fisher-Yates with the caller's rand(n) -> 1..n
local function shuffle(list: { any }, rand: (number) -> number): { any }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = rand(i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end
JS.shuffle = shuffle

local function pick(list: { any }, rand: (number) -> number): any
	return list[rand(#list)]
end

local function productView(p: any): any
	return { id = p.id, name = p.name, icon = p.icon, price = p.price }
end

-------------------------------------------------------------------------------------------------
-- Round generators: JS.gen[game](rand, info) -> { secret = {...}, view = {...} }
--   rand(n) -> 1..n ; info = { today = { month, day }?, dests = {...}? , basePay = n? }
-------------------------------------------------------------------------------------------------
JS.gen = {}
JS.check = {}

-- 계산대: "scan" (tap the basket items in order on a 3x3 grid) or "total" (pick the total of the
-- basket among 3 choices).
JS.gen.pos = function(rand: (number) -> number, info: any?): any
	local mode = if rand(3) == 3 then "total" else "scan"
	local pool = shuffle(JS.PRODUCTS, rand)
	if mode == "scan" then
		local n = 2 + rand(2) -- 3 or 4 items to scan (rand(2) -> 1..2)
		local basket = {}
		for i = 1, n do
			table.insert(basket, pool[i])
		end
		local grid = {}
		for i = 1, 9 do
			table.insert(grid, pool[i])
		end
		grid = shuffle(grid, rand)
		local order = {}
		local items = {}
		for _, p in basket do
			table.insert(order, p.id)
			table.insert(items, productView(p))
		end
		local gridView = {}
		for _, p in grid do
			table.insert(gridView, productView(p))
		end
		return {
			secret = { mode = mode, order = order },
			view = { mode = mode, items = items, grid = gridView, customer = pick({ "👩", "👨", "🧑", "👵", "👴", "🧒" }, rand) },
		}
	end
	local n = 2 + rand(2)
	local items = {}
	local total = 0
	for i = 1, n do
		local p = pool[i]
		local qty = if rand(3) == 1 then 2 else 1
		total += p.price * qty
		local v = productView(p)
		v.qty = qty
		table.insert(items, v)
	end
	-- 3 choices: the total plus two near misses (never equal)
	local offsets = { 0, pick({ -1000, -500, 500, 1000, 1500 }, rand), pick({ -700, -300, 300, 800, 1200 }, rand) }
	if offsets[2] == offsets[3] then
		offsets[3] = offsets[3] + 400
	end
	local choices = {}
	local correct = 0
	local orderIdx = shuffle({ 1, 2, 3 }, rand)
	for slot, k in orderIdx do
		local v = math.max(100, total + offsets[k])
		table.insert(choices, JS.won(v))
		if k == 1 then
			correct = slot
		end
	end
	return {
		secret = { mode = mode, answer = correct, total = total },
		view = { mode = mode, items = items, choices = choices, customer = pick({ "👩", "👨", "🧑", "👵", "👴", "🧒" }, rand) },
	}
end

JS.check.pos = function(secret: any, view: any, answer: any): number
	if secret.mode == "total" then
		return if tonumber(answer) == secret.answer then 1 else 0
	end
	if type(answer) ~= "table" then
		return 0
	end
	local hit = 0
	for i, id in secret.order do
		if answer[i] == id then
			hit += 1
		end
	end
	return hit / math.max(1, #secret.order)
end

-- 진열: 4 items -> 3 category bins
JS.gen.shelf = function(rand: (number) -> number, _info: any?): any
	local cats = shuffle(JS.CATEGORY_ORDER, rand)
	local bins = { cats[1], cats[2], cats[3] }
	local byCat = {}
	for _, p in JS.PRODUCTS do
		byCat[p.cat] = byCat[p.cat] or {}
		table.insert(byCat[p.cat], p)
	end
	local items = {}
	local secret = {}
	-- one item per bin, plus one more from a random bin (4 in total)
	local sources = { bins[1], bins[2], bins[3], bins[rand(3)] }
	local used = {}
	for _, cat in sources do
		local list = shuffle(byCat[cat], rand)
		for _, p in list do
			if not used[p.id] then
				used[p.id] = true
				table.insert(items, { id = p.id, name = p.name, icon = p.icon })
				secret[p.id] = cat
				break
			end
		end
	end
	items = shuffle(items, rand)
	local binView = {}
	for _, c in bins do
		table.insert(binView, { cat = c, name = JS.CATEGORIES[c].name, icon = JS.CATEGORIES[c].icon })
	end
	return { secret = { cats = secret, n = #items }, view = { items = items, bins = binView } }
end

-- answer = { { id = productId, cat = category }, ... } or { [id] = cat }
JS.check.shelf = function(secret: any, _view: any, answer: any): number
	if type(answer) ~= "table" then
		return 0
	end
	local map = {}
	for k, v in answer do
		if type(v) == "table" and type(v.id) == "string" then
			map[v.id] = v.cat
		elseif type(k) == "string" then
			map[k] = v
		end
	end
	local hit = 0
	for id, cat in secret.cats do
		if map[id] == cat then
			hit += 1
		end
	end
	return hit / math.max(1, secret.n)
end

-- 유통기한: 4 dated items, exactly one expired
local function addDays(month: number, day: number, delta: number): (number, number)
	local dim = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	local m, d = month, day + delta
	while d > dim[m] do
		d -= dim[m]
		m = m % 12 + 1
	end
	while d < 1 do
		m = (m - 2) % 12 + 1
		d += dim[m]
	end
	return m, d
end
JS.addDays = addDays

JS.gen.expiry = function(rand: (number) -> number, info: any?): any
	local today = (info and info.today) or { month = 10, day = 2 }
	local pool = shuffle(JS.PRODUCTS, rand)
	local items = {}
	local expiredSlot = rand(4)
	for i = 1, 4 do
		local p = pool[i]
		local delta = if i == expiredSlot then -rand(9) else rand(20)
		local m, d = addDays(today.month, today.day, delta)
		table.insert(items, { id = p.id, name = p.name, icon = p.icon, date = string.format("%02d.%02d", m, d), m = m, d = d })
	end
	return {
		secret = { answer = expiredSlot },
		view = { items = items, today = string.format("%d월 %d일", today.month, today.day) },
	}
end

JS.check.expiry = function(secret: any, _view: any, answer: any): number
	return if tonumber(answer) == secret.answer then 1 else 0
end

-- 택배 접수: weight -> price band (3 choices), or an over-limit parcel that must be refused
JS.gen.parcel = function(rand: (number) -> number, _info: any?): any
	local overLimit = rand(5) == 5
	local kg: number
	if overLimit then
		kg = JS.PARCEL_MAX_KG + rand(8)
	else
		kg = (rand(190) + 2) / 10 -- 0.3 .. 19.2
	end
	local band = nil
	for _, r in JS.PARCEL_RATES do
		if kg <= r.max then
			band = r
			break
		end
	end
	local rates = {}
	for _, r in JS.PARCEL_RATES do
		table.insert(rates, { label = r.label, price = JS.won(r.price) })
	end
	local choices = {}
	local correct = 0
	if overLimit then
		local opts = shuffle({ "접수 불가 (20kg 초과)", JS.won(3800), JS.won(2800) }, rand)
		for i, c in opts do
			table.insert(choices, c)
			if c == "접수 불가 (20kg 초과)" then
				correct = i
			end
		end
	else
		local idx = table.find(JS.PARCEL_RATES, band) or 1
		local alt1 = JS.PARCEL_RATES[(idx % #JS.PARCEL_RATES) + 1].price
		local alt2 = JS.PARCEL_RATES[((idx + 1) % #JS.PARCEL_RATES) + 1].price
		local opts = shuffle({ band.price, alt1, alt2 }, rand)
		for i, c in opts do
			table.insert(choices, JS.won(c))
			if c == band.price then
				correct = i
			end
		end
	end
	return {
		secret = { answer = correct },
		view = {
			weight = string.format("%.1fkg", kg),
			dest = pick(JS.PARCEL_DESTS, rand),
			customer = pick({ "👩", "👨", "🧑", "👵", "👴" }, rand),
			rates = rates,
			maxKg = JS.PARCEL_MAX_KG,
			choices = choices,
		},
	}
end

JS.check.parcel = function(secret: any, _view: any, answer: any): number
	return if tonumber(answer) == secret.answer then 1 else 0
end

-- 음료 만들기: the recipe's steps in order on a grid of 6 ingredients
JS.gen.drink = function(rand: (number) -> number, _info: any?): any
	local drink = pick(JS.DRINKS, rand)
	local present = {}
	local grid = {}
	for _, s in drink.steps do
		present[s] = true
		table.insert(grid, s)
	end
	for _, s in shuffle(JS.INGREDIENT_ORDER, rand) do
		if #grid >= 6 then
			break
		end
		if not present[s] then
			present[s] = true
			table.insert(grid, s)
		end
	end
	grid = shuffle(grid, rand)
	local gridView = {}
	for _, s in grid do
		table.insert(gridView, { id = s, name = JS.INGREDIENTS[s].name, icon = JS.INGREDIENTS[s].icon })
	end
	local steps = {}
	for _, s in drink.steps do
		table.insert(steps, { id = s, name = JS.INGREDIENTS[s].name, icon = JS.INGREDIENTS[s].icon })
	end
	return {
		secret = { order = table.clone(drink.steps) },
		view = { drink = { id = drink.id, name = drink.name, icon = drink.icon }, steps = steps, grid = gridView, size = pick({ "톨", "그란데", "숏" }, rand), hot = drink.steps[#drink.steps] ~= "ice" },
	}
end

JS.check.drink = function(secret: any, _view: any, answer: any): number
	if type(answer) ~= "table" then
		return 0
	end
	local hit = 0
	for i, id in secret.order do
		if answer[i] == id then
			hit += 1
		end
	end
	return hit / math.max(1, #secret.order)
end

-- 라떼 아트: tap when the shrinking ring meets the cup, 3 beats. The client measures the tap times
-- since the round opened; the server accepts |tap - beat| <= window (and checks total elapsed).
JS.LATTE = { beats = { 1.6, 3.0, 4.4 }, window = 0.35, ringSeconds = 1.2 }
JS.gen.latte = function(rand: (number) -> number, _info: any?): any
	local beats = table.clone(JS.LATTE.beats)
	local jitter = (rand(5) - 3) * 0.1
	for i, b in beats do
		beats[i] = b + jitter * i
	end
	return {
		secret = { beats = beats, window = JS.LATTE.window },
		view = { beats = table.clone(beats), window = JS.LATTE.window, ring = JS.LATTE.ringSeconds, art = pick({ "🌷", "🍀", "❤️", "🦢", "🌙" }, rand) },
	}
end

-- answer = { taps = { t1, t2, t3 } } seconds since the round opened (client clock)
JS.check.latte = function(secret: any, _view: any, answer: any): number
	if type(answer) ~= "table" or type(answer.taps) ~= "table" then
		return 0
	end
	local total = 0
	for i, beat in secret.beats do
		local t = tonumber(answer.taps[i])
		if t then
			local off = math.abs(t - beat)
			if off <= secret.window then
				total += 1 - 0.5 * (off / secret.window)
			end
		end
	end
	return total / math.max(1, #secret.beats)
end

-- 배달 주문 고르기: info.pickups / info.drops = { { name, pos = Vector3 or {x,y,z} } }, info.basePay
local function posOf(p: any): any
	local v = p.pos
	if type(v) == "table" then
		return { x = v[1] or v.x or 0, y = v[2] or v.y or 0, z = v[3] or v.z or 0 }
	end
	-- Vector3 (Roblox) or anything with X/Y/Z
	local ok, x, y, z = pcall(function()
		return v.X, v.Y, v.Z
	end)
	if ok then
		return { x = x, y = y, z = z }
	end
	return { x = 0, y = 0, z = 0 }
end
local function dist(a: any, b: any): number
	local pa, pb = posOf(a), posOf(b)
	local dx, dz = pa.x - pb.x, pa.z - pb.z
	return math.sqrt(dx * dx + dz * dz)
end
JS.flatDistance = dist

JS.gen.order = function(rand: (number) -> number, info: any): any
	local pickups = (info and info.pickups) or {}
	local drops = (info and info.drops) or {}
	local basePay = (info and tonumber(info.basePay)) or 3300
	-- every pickup x drop pair, far ones first (shuffled), then unique drops
	local pairs_: { any } = {}
	for _, pu in pickups do
		for _, dr in drops do
			if dr.name ~= pu.name then
				table.insert(pairs_, { pu = pu, dr = dr, d = dist(pu, dr) })
			end
		end
	end
	pairs_ = shuffle(pairs_, rand)
	local far, near = {}, {}
	for _, pr in pairs_ do
		table.insert(if pr.d >= JS.DELIVERY.minDist then far else near, pr)
	end
	for _, pr in near do
		table.insert(far, pr)
	end
	local orders = {}
	local usedDrop = {}
	for _, pr in far do
		if #orders >= JS.DELIVERY.offers then
			break
		end
		if usedDrop[pr.dr.name] then
			continue
		end
		usedDrop[pr.dr.name] = true
		local dish = pick(JS.DISHES, rand)
		local pay, tip = JS.deliveryPay(basePay, pr.d)
		table.insert(orders, {
			id = #orders + 1,
			dish = dish.name,
			icon = dish.icon,
			pickup = pr.pu.name,
			drop = pr.dr.name,
			dist = math.floor(pr.d),
			pay = pay,
			tip = tip,
			timeLimit = JS.deliveryTimeLimit(pr.d),
			customer = pick({ "👩", "👨", "🧑", "👵", "👴", "🧒" }, rand),
		})
	end
	return { secret = { orders = orders }, view = { orders = orders } }
end

-- answer = order index; any listed order is "right" (score 1)
JS.check.order = function(secret: any, _view: any, answer: any): number
	local i = tonumber(answer)
	return if i and secret.orders[i] then 1 else 0
end

-------------------------------------------------------------------------------------------------
-- 계산 (world sale): the customer NPC puts its basket on the counter; the worker taps every item
-- (scanner beep, POS screen total), then picks the change for a cash payment (card = no change).
--   view   = { customer, items = { {id, name, icon, price, n} } (one entry per unit), total,
--              method = "cash" | "card", paid?, choices? (3 change amounts), say }
--   answer = { scans = { id, ... }, change = choice index? }
-------------------------------------------------------------------------------------------------
JS.CASH_NOTES = { 5000, 10000, 20000, 50000 }
JS.CUSTOMER_FACES = { "👩", "👨", "🧑", "👵", "👴", "🧒", "👱", "🧔" }
JS.SALE_LINES = {
	"이거 계산이요~", "계산해 주세요!", "봉투는 괜찮아요", "영수증 버려 주세요", "이거 2+1 맞죠?", "카드 돼요?",
}

local function pickBasket(rand: (number) -> number, n: number, pool: { any }?): { any }
	local src = shuffle(pool or JS.PRODUCTS, rand)
	local out = {}
	for i = 1, math.min(n, #src) do
		table.insert(out, src[i])
	end
	return out
end

JS.gen.sale = function(rand: (number) -> number, info: any?): any
	local n = 2 + rand(3) -- 3..5 units
	local basket = pickBasket(rand, math.min(n, 4), info and info.pool)
	local items = {}
	local total = 0
	for i = 1, n do
		local p = basket[((i - 1) % #basket) + 1]
		table.insert(items, { id = p.id, name = p.name, icon = p.icon, price = p.price, n = i })
		total += p.price
	end
	local method = if rand(3) == 1 then "card" else "cash"
	local view: any = { customer = pick(JS.CUSTOMER_FACES, rand), items = items, total = total, method = method, say = pick(JS.SALE_LINES, rand) }
	local secret: any = { total = total, method = method }
	local need = {}
	for _, it in items do
		need[it.id] = (need[it.id] or 0) + 1
	end
	secret.need = need
	secret.units = #items
	if method == "cash" then
		local paid = JS.CASH_NOTES[#JS.CASH_NOTES]
		for _, note in JS.CASH_NOTES do
			if note >= total then
				paid = note
				break
			end
		end
		if paid < total then
			paid = math.ceil(total / 10000) * 10000
		end
		local change = paid - total
		local offsets = shuffle({ 0, pick({ -1000, 1000, 500 }, rand), pick({ -500, 2000, -100, 100 }, rand) }, rand)
		local choices = {}
		local used = {}
		local answer = 1
		for i, o in offsets do
			local v = math.max(0, change + o)
			while used[v] do
				v += 100
			end
			used[v] = true
			table.insert(choices, JS.won(v))
			if o == 0 then
				answer = i
			end
		end
		view.paid = paid
		view.choices = choices
		secret.change = answer
	end
	return { secret = secret, view = view }
end

JS.check.sale = function(secret: any, _view: any, answer: any): number
	if type(answer) ~= "table" or type(answer.scans) ~= "table" then
		return 0
	end
	local left = table.clone(secret.need)
	local matched, extra = 0, 0
	for i, id in answer.scans do
		if i > 20 then
			break
		end
		if type(id) == "string" and (left[id] or 0) > 0 then
			left[id] -= 1
			matched += 1
		else
			extra += 1
		end
	end
	local scan = math.clamp((matched - 0.5 * extra) / math.max(1, secret.units), 0, 1)
	if secret.method ~= "cash" then
		return scan
	end
	local changeOk = tonumber(answer.change) == secret.change
	return scan * (if changeOk then 1 else 0.45)
end

-------------------------------------------------------------------------------------------------
-- 손님 응대 (ask): a customer question with 3 answers; the task carries the data
--   info = { question, choices, answer }   view = { question, choices, customer }
-------------------------------------------------------------------------------------------------
JS.gen.ask = function(rand: (number) -> number, info: any?): any
	local q = info and info.question or "손님: \"화장실 어디예요?\""
	local choices = info and info.choices or { "건물 2층이에요", "없어요", "모르겠어요" }
	local answer = info and tonumber(info.answer) or 1
	-- shuffle the choices so the right one is not always first
	local order = shuffle({ 1, 2, 3 }, rand)
	local outChoices = {}
	local outAnswer = 1
	for i, k in order do
		if choices[k] then
			table.insert(outChoices, choices[k])
			if k == answer then
				outAnswer = #outChoices
			end
		end
		local _ = i
	end
	return { secret = { answer = outAnswer }, view = { question = q, choices = outChoices, customer = pick(JS.CUSTOMER_FACES, rand) } }
end

JS.check.ask = function(secret: any, _view: any, answer: any): number
	return if tonumber(answer) == secret.answer then 1 else 0
end

-------------------------------------------------------------------------------------------------
-- STORE PURCHASES (any player, never another player): drinks fridge / shelf / cafe counter
-- -> purchase sheet -> pay (cash first, then the bank) -> effect. Server: GwangalliGameplay/JobShop.
--   effect = { stats = { stamina, happiness, ... } } via ctx.addStats; hold = seconds a held prop
--   (drink cup / snack) stays in the right hand; fatigue = health module rest (pcall, optional)
-------------------------------------------------------------------------------------------------
JS.SHOP = {
	-- station kind -> item ids (display order)
	stations = {
		store_drink = { title = "음료 냉장고", icon = "🧃", items = { "cvs_water", "cvs_cola", "cvs_banana", "cvs_coffee", "cvs_energy", "cvs_tea" } },
		store_shelf = { title = "진열대", icon = "🛒", items = { "cvs_samgak", "cvs_ramen", "cvs_dosirak", "cvs_sandwich", "cvs_choco", "cvs_chips" } },
		cafe_counter = { title = "카페 주문", icon = "☕", items = { "cafe_americano", "cafe_latte", "cafe_vanilla", "cafe_icetea", "cafe_cake", "cafe_croissant" } },
	},
	items = {
		cvs_water = { name = "생수", icon = "💧", price = 900, effect = { stats = { stamina = 1 } }, hold = 6, prop = "bottle", color = { 160, 210, 245 } },
		cvs_cola = { name = "콜라", icon = "🥤", price = 1800, effect = { stats = { happiness = 1, stamina = 0.5 } }, hold = 6, prop = "can", color = { 200, 30, 40 } },
		cvs_banana = { name = "바나나맛 우유", icon = "🍌", price = 1700, effect = { stats = { happiness = 1.5 } }, hold = 6, prop = "bottle", color = { 250, 220, 90 } },
		cvs_coffee = { name = "캔커피", icon = "☕", price = 1400, effect = { stats = { stamina = 1 }, fatigue = -2 }, hold = 6, prop = "can", color = { 110, 70, 40 } },
		cvs_energy = { name = "에너지 드링크", icon = "⚡", price = 2500, effect = { stats = { stamina = 2 }, fatigue = -4 }, hold = 6, prop = "can", color = { 40, 60, 200 } },
		cvs_tea = { name = "보리차", icon = "🍵", price = 1500, effect = { stats = { happiness = 0.5, stamina = 0.5 } }, hold = 6, prop = "bottle", color = { 190, 140, 70 } },
		cvs_samgak = { name = "삼각김밥", icon = "🍙", price = 1200, effect = { stats = { stamina = 2 } }, hold = 5, prop = "snack", color = { 240, 240, 240 } },
		cvs_ramen = { name = "컵라면", icon = "🍜", price = 1500, effect = { stats = { stamina = 2.5, happiness = 0.5 } }, hold = 6, prop = "cup", color = { 220, 60, 40 } },
		cvs_dosirak = { name = "도시락", icon = "🍱", price = 4500, effect = { stats = { stamina = 4, happiness = 1 } }, hold = 5, prop = "box", color = { 230, 180, 60 } },
		cvs_sandwich = { name = "샌드위치", icon = "🥪", price = 2800, effect = { stats = { stamina = 2.5 } }, hold = 5, prop = "snack", color = { 240, 220, 170 } },
		cvs_choco = { name = "초코바", icon = "🍫", price = 1000, effect = { stats = { happiness = 1 } }, hold = 4, prop = "snack", color = { 90, 50, 30 } },
		cvs_chips = { name = "감자칩", icon = "🥔", price = 1700, effect = { stats = { happiness = 1.5 } }, hold = 5, prop = "box", color = { 250, 200, 40 } },
		cafe_americano = { name = "아이스 아메리카노", icon = "🧋", price = 4500, effect = { stats = { stamina = 1.5 }, fatigue = -5 }, hold = 8, prop = "cup", color = { 60, 35, 20 } },
		cafe_latte = { name = "카페 라떼", icon = "🥛", price = 5000, effect = { stats = { stamina = 1, happiness = 1 }, fatigue = -3 }, hold = 8, prop = "cup", color = { 210, 180, 140 } },
		cafe_vanilla = { name = "바닐라 라떼", icon = "🍮", price = 5500, effect = { stats = { happiness = 2 }, fatigue = -3 }, hold = 8, prop = "cup", color = { 235, 215, 170 } },
		cafe_icetea = { name = "복숭아 아이스티", icon = "🍹", price = 4500, effect = { stats = { happiness = 1.5 } }, hold = 8, prop = "cup", color = { 240, 150, 110 } },
		cafe_cake = { name = "치즈 케이크", icon = "🍰", price = 6500, effect = { stats = { happiness = 3 } }, hold = 6, prop = "box", color = { 250, 235, 190 } },
		cafe_croissant = { name = "크루아상", icon = "🥐", price = 4000, effect = { stats = { stamina = 2, happiness = 1 } }, hold = 6, prop = "snack", color = { 220, 160, 70 } },
	},
	cooldown = 1.0, -- seconds between purchases
	dailyStatLimit = 6, -- purchases per item per (real) day that still give stats
	reach = 12, -- studs from the station anchor
}

-------------------------------------------------------------------------------------------------
-- DELIVERY OFFICE (광안 딜리버리): 퀵 (on foot, downtown, hand the parcel to a waiting NPC) and
-- 택배 (탑차, all over the map, drive into the ring; red lights cost money). Pay per drop:
--   pay = base + perStud * distance (+ tip when within the time limit) - red-light fines
-- Pay balance (docs/careers_contract.md): convenience / cafe ~65 % of 택배; 퀵 ~90 % of 택배.
-------------------------------------------------------------------------------------------------
JS.DELIVERY_MODES = {
	quick = {
		title = "퀵 배달", icon = "🛵", job = "delivery_quick",
		base = 1600, perStud = 5.2, tipRate = 0.25, timeBase = 30, timeSpeed = 11,
		minDist = 90, maxDist = 520, radius = 9, drops = 4,
	},
	parcel = {
		title = "택배 배달", icon = "🚚", job = "delivery_parcel",
		base = 2400, perStud = 2.9, tipRate = 0.2, timeBase = 40, timeSpeed = 34,
		minDist = 260, maxDist = 2600, radius = 13, drops = 4,
		redLightFine = 1500, -- won per red light (taken from the drop's pay, never below 0)
		redLightGrace = 1.0, -- seconds into the red phase that still count as amber
		redLightSpeed = 6, -- studs/s along the lane needed to count as "driving through"
		redLightCooldown = 8, -- one fine per intersection group per this many seconds
	},
}
JS.ROOM_FLOORS = { 2, 3, 5, 7, 9, 11, 12, 15, 17, 21 }

-- "광안자이 1502호 - 배달요망"
function JS.roomLabel(dest: string, rand: (number) -> number): string
	local floor = JS.ROOM_FLOORS[rand(#JS.ROOM_FLOORS)]
	local unit = rand(4)
	return string.format("%s %d%02d호 - 배달요망", tostring(dest), floor, unit)
end

function JS.dropPay(mode: string, dist: number): (number, number, number)
	local m = JS.DELIVERY_MODES[mode] or JS.DELIVERY_MODES.quick
	local d = math.clamp(dist, 0, m.maxDist * 1.5)
	local pay = round100(m.base + d * m.perStud)
	local tip = round100(pay * m.tipRate)
	local limit = math.floor(m.timeBase + d / m.timeSpeed)
	return pay, tip, limit
end

-------------------------------------------------------------------------------------------------
-- Boss / customer lines (speech bubbles in the world; the worker's client shows them)
-------------------------------------------------------------------------------------------------
JS.BOSS = {
	gs25 = {
		name = "김사장님",
		greet = { "오, 왔어? 오늘도 잘 부탁해! 😊", "어서 와~ 앞치마 챙겨 입고!", "출근했네! 손님 오시면 바로 계산 부탁해" },
		brief = "카운터 손님 계산, 창고 박스 진열, 쇼케이스 유통기한 체크! 모르면 물어봐~",
		good = { "오~ 손 빠르네! 👍", "역시 믿고 맡긴다!", "완벽해! 이대로만 해", "손님이 좋아하시네 😊" },
		bad = { "괜찮아, 다음엔 천천히!", "앗, 다시 확인해 보자~", "실수해도 돼, 배우는 중이니까" },
		wait = "손님 기다리신다! 카운터로~",
		left = "어이쿠, 손님 그냥 가셨네… 다음엔 빨리!",
		bye = "수고했어! 조심히 들어가 🙌",
		tired = "얼굴이 피곤해 보여… 쉬엄쉬엄 해",
	},
	starbucks = {
		name = "이점장",
		greet = { "좋은 아침! 오늘 주문 많을 거예요 ☕", "왔어요? 앞치마 하고 바로 시작해요!" },
		brief = "카운터에서 주문 받고, 머신에서 레시피대로! 라떼 아트는 보너스예요",
		good = { "라떼 맛있게 나왔네요 ☕", "손님 칭찬 들었어요!", "굿굿! 👍" },
		bad = { "레시피 다시 한 번 볼까요?", "괜찮아요, 다음 잔은 완벽하게!" },
		wait = "주문 들어왔어요~ 카운터 봐 주세요!",
		left = "손님이 기다리다 가셨어요 😢",
		bye = "오늘 고생 많았어요! 커피 한 잔 하고 가요",
		tired = "피곤하면 잠깐 쉬어도 돼요",
	},
	delivery = {
		name = "배차 실장",
		greet = { "출근 완료! 퀵이든 택배든 골라서 가 봐 🛵", "왔구나! 오늘 물량 많다~" },
		brief = "테이블에서 퀵이나 택배를 골라. 택배는 차고 탑차! 신호 위반하면 배달비 깎인다",
		good = { "빠르다 빨라! 🚀", "고객 평점 5점 들어왔어!" },
		bad = { "신호는 꼭 지키자!", "다음 건은 더 빨리!" },
		wait = "물건 챙겨서 출발!",
		left = "",
		bye = "수고했어! 차 반납 고마워",
		tired = "운전 조심해, 피곤하면 쉬고",
	},
}
JS.CUSTOMER_LINES = {
	thanks = { "감사합니다~", "수고하세요!", "고마워요 😊", "잘 먹을게요!" },
	slow = { "아직이에요…?", "좀 바빠서요…" },
	angry = { "너무 오래 걸리네… 그냥 갈게요", "다음에 올게요…" },
	browse = { "음… 뭐 먹지", "오 신상이다", "2+1 있네?" },
	parcel = { "택배 보내려고요!", "이거 부산 말고 서울로요" },
	recipient = { "아 택배요? 감사합니다!", "고생 많으세요~", "벌써 왔네요? 빠르다!" },
}

-------------------------------------------------------------------------------------------------
-- Validation (called by G.validate-style self checks / the unit test)
-------------------------------------------------------------------------------------------------
function JS.validate(): { string }
	local problems = {}
	for _, id in JS.GAME_ORDER do
		if not JS.GAMES[id] then
			table.insert(problems, "GAME_ORDER lists missing game " .. id)
		end
		if not JS.gen[id] or not JS.check[id] then
			table.insert(problems, "game " .. id .. " without gen/check")
		end
	end
	for _, d in JS.DRINKS do
		for _, s in d.steps do
			if not JS.INGREDIENTS[s] then
				table.insert(problems, "drink " .. d.id .. " unknown ingredient " .. s)
			end
		end
	end
	for _, p in JS.PRODUCTS do
		if not JS.CATEGORIES[p.cat] then
			table.insert(problems, "product " .. p.id .. " unknown category")
		end
	end
	return problems
end

return JS
