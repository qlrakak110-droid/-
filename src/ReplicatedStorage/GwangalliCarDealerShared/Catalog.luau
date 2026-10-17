-- GwangalliCarDealerShared/Catalog: the dealer's car list, built from the garage's own data
-- (GwangalliGarageShared CATALOG / MODELS / RENTAL / LOAN and GwangalliVehiclesShared handling), so prices,
-- models and names always follow the live game (older place versions without GS.MODELS work too).
-- Pure: no instances, no yields. The server and the client build the same list from the same modules.
--
--   Catalog.build(GS, VS, opts) -> entries, byId
--       opts = { avail = { [modelId] = true }, showAll = bool, specials = { [entryId] = true }, rent = bool }
--   Catalog.CATS                       category tabs (id, label, icon); Catalog.catsIn(entries) -> used ones
--   Catalog.parse(id) -> { type = "kit" | "model" | "rent", kind?, grade?, model? }?
--   Catalog.pickSpecials(entries, monthKey, count, minPrice) -> { [entryId] = true }
--   Catalog.benefits(entry, { usedRate, special }) -> { lines = {{ key, rate, amount }}, total, rate }
--   Catalog.affordable(entry, bank, cash) -> "full" | "loan" | nil
--   Catalog.filter(entries, f) / Catalog.sort(list, key, money) / Catalog.recommend(entries, budget, money)
--   Catalog.SORTS                      { id, label } list
--
-- ENTRY = { id, kind, grade ("new" | "used" | "rent"), model?, name, glyph, body, seats, price, loan?, canLoan,
--   tag?, cats = { catId }, perf = { top, accel, brake, mass, drive }, bars = { accel, top, brake, comfort,
--   utility } (1..5), fuel, eff, blurb, available, preview (ReplicatedStorage preview child name), brand,
--   isNew, special, rentSeconds?, cond = { lo, hi }?, order, deliverAs? (kit label when a model has no template) }

local Config = require(script.Parent:WaitForChild("Config"))
local U = require(script.Parent:WaitForChild("Util"))

local Catalog = {}

Catalog.CATS = {
	{ id = "all", label = "전체", icon = "🚘" },
	{ id = "special", label = "이달의 특가", icon = "🔥" },
	{ id = "compact", label = "경차", icon = "🚙" },
	{ id = "sedan", label = "세단", icon = "🚗" },
	{ id = "suv", label = "SUV", icon = "🏔️" },
	{ id = "van", label = "승합·밴", icon = "🚐" },
	{ id = "truck", label = "트럭", icon = "🛻" },
	{ id = "premium", label = "프리미엄", icon = "✨" },
	{ id = "sport", label = "스포츠", icon = "🏁" },
	{ id = "eco", label = "전기·하이브리드", icon = "⚡" },
	{ id = "used", label = "중고차", icon = "🏷️" },
	{ id = "rent", label = "렌트", icon = "🔑" },
}
Catalog.CAT_BY_ID = {}
for i, c in Catalog.CATS do
	c.order = i
	Catalog.CAT_BY_ID[c.id] = c
end

Catalog.SORTS = {
	{ id = "rec", label = "추천순" },
	{ id = "low", label = "낮은 가격순" },
	{ id = "high", label = "높은 가격순" },
	{ id = "fast", label = "최고속도순" },
}

local KIND_BODY = { compact = "경차", sedan = "중형 세단", suv = "SUV", truck = "1톤 트럭", van = "9인승 밴", luxury = "대형 세단" }
local DRIVE_KO = { FWD = "전륜구동", RWD = "후륜구동", AWD = "사륜구동" }
Catalog.DRIVE_KO = DRIVE_KO
local PREMIUM_PRICE = 4000000

local function bar(v: number, lo: number, hi: number): number
	if not U.finite(v) then
		return 3
	end
	return math.clamp(math.floor(1 + 4 * (v - lo) / math.max(1e-6, hi - lo) + 0.5), 1, 5)
end

local function has(s: any, word: string): boolean
	return type(s) == "string" and string.find(s, word, 1, true) ~= nil
end

local function perfOf(VS: any, kind: string): any
	local sp = nil
	if VS and type(VS.spec) == "function" then
		local ok, r = pcall(VS.spec, kind)
		if ok and type(r) == "table" then
			sp = r
		end
	end
	sp = sp or {}
	return {
		top = tonumber(sp.topKmh) or 120,
		accel = tonumber(sp.accel) or 18,
		brake = tonumber(sp.brake) or 42,
		mass = tonumber(sp.mass) or 150,
		drive = if type(sp.drive) == "string" then sp.drive else "FWD",
	}
end

local function barsOf(perf: any, kind: string): any
	local pt = Config.POWERTRAIN[kind] or {}
	return {
		accel = bar(perf.accel, 12, 28),
		top = bar(perf.top, 95, 170),
		brake = bar(perf.brake, 32, 52),
		comfort = math.clamp(pt.comfort or 3, 1, 5),
		utility = math.clamp(pt.utility or 3, 1, 5),
	}
end

local function newSet(): { [string]: boolean }
	local s = {}
	for _, id in Config.NEW_ARRIVALS do
		s[id] = true
	end
	return s
end

local function classify(e: any)
	local cats = { "all" }
	local function add(id: string)
		if not table.find(cats, id) then
			table.insert(cats, id)
		end
	end
	if e.grade == "rent" then
		add("rent")
		e.cats = cats
		return
	end
	local kind, body = e.kind, e.body or ""
	if e.model then
		if has(body, "SUV") or has(body, "크로스오버") then
			add("suv")
		elseif has(body, "밴") then
			add("van")
		elseif has(body, "트럭") then
			add("truck")
		elseif has(body, "경차") then
			add("compact")
		else
			add("sedan")
		end
	elseif kind == "luxury" then
		add("sedan")
	elseif kind == "compact" or kind == "sedan" or kind == "suv" or kind == "van" or kind == "truck" then
		add(kind)
	end
	if kind == "luxury" or (e.grade == "new" and e.price >= PREMIUM_PRICE) then
		add("premium")
	end
	if has(e.name, "하이브리드") or has(e.name, "전기") or has(e.blurb, "하이브리드") or has(e.blurb, "전기") or e.glyph == "⚡" then
		add("eco")
	end
	if e.tag == "고성능" or has(body, "쿠페") or has(e.name, "스포츠") then
		add("sport")
	end
	if e.grade == "used" then
		add("used")
	end
	if e.special then
		add("special")
	end
	e.cats = cats
end

local function powertrain(e: any): (string, string)
	if has(e.name, "전기") or has(e.blurb, "전기") or e.glyph == "⚡" then
		return Config.POWERTRAIN_EV.fuel, Config.POWERTRAIN_EV.eff
	end
	if has(e.name, "하이브리드") or has(e.blurb, "하이브리드") then
		return Config.POWERTRAIN_HYBRID.fuel, Config.POWERTRAIN_HYBRID.eff
	end
	local pt = Config.POWERTRAIN[e.kind] or Config.POWERTRAIN.sedan
	return pt.fuel, pt.eff
end

local function loanOf(GS: any, price: number): (any?, boolean)
	if type(GS.canLoan) == "function" and type(GS.loanQuote) == "function" then
		local okC, can = pcall(GS.canLoan, price)
		if okC and can then
			local okQ, q = pcall(GS.loanQuote, price)
			if okQ and type(q) == "table" then
				return q, true
			end
		end
	end
	return nil, false
end

local function brandOf(GS: any, kind: string, m: any?): string
	if m and GS.SHOW_REAL_NAMES == true and type(m.real) == "string" then
		local first = string.match(m.real, "^(%S+)")
		if first then
			return first
		end
	end
	return Config.LINEUPS[kind] or "광안 오토"
end

-- Builds every sellable entry: the kit kinds (신차 + 중고), the showroom models (when their template exists or
-- opts.showAll), and the 렌트 offer.
function Catalog.build(GS: any, VS: any, opts: any?): ({ any }, { [string]: any })
	local o = opts or {}
	local out: { any } = {}
	local byId: { [string]: any } = {}
	if type(GS) ~= "table" or type(GS.CATALOG) ~= "table" then
		return out, byId
	end
	local newIds = newSet()
	local specials = o.specials or {}
	local order = 0
	local function push(e: any)
		order += 1
		e.order = order
		e.isNew = newIds[e.id] == true
		e.special = specials[e.id] == true
		e.loan, e.canLoan = loanOf(GS, e.price)
		if e.grade == "rent" then
			e.loan, e.canLoan = nil, false
		end
		e.fuel, e.eff = powertrain(e)
		classify(e)
		table.insert(out, e)
		byId[e.id] = e
	end
	local kinds = if type(GS.KIND_ORDER) == "table" then GS.KIND_ORDER else { "compact", "sedan", "suv", "truck", "van", "luxury" }
	local condRange = if type(GS.USED_COND) == "table" then { GS.USED_COND[1], GS.USED_COND[2] } else { 55, 80 }
	for _, kind in kinds do
		local c = GS.CATALOG[kind]
		if type(c) == "table" and U.finite(c.new) then
			local perf = perfOf(VS, kind)
			for _, grade in { "new", "used" } do
				local price = if grade == "used" then c.used else c.new
				if U.finite(price) and price > 0 then
					push({
						id = "kit:" .. kind .. ":" .. grade,
						kind = kind,
						grade = grade,
						name = c.full or c.label or kind,
						short = c.label or c.full or kind,
						glyph = c.glyph or "🚗",
						body = KIND_BODY[kind] or "승용",
						seats = c.seats or 5,
						price = math.floor(price),
						tag = if grade == "new" then c.tag else (if kind == "compact" then "첫 차 추천" else nil),
						blurb = c.blurb or "",
						perf = perf,
						bars = barsOf(perf, kind),
						available = true,
						preview = "kit_" .. kind,
						brand = brandOf(GS, kind, nil),
						cond = if grade == "used" then condRange else nil,
					})
				end
			end
		end
	end
	if type(GS.MODELS) == "table" then
		local avail = o.avail or {}
		for _, m in GS.MODELS do
			if type(m) == "table" and type(m.id) == "string" and GS.CATALOG[m.kind] and U.finite(m.price) then
				local ok = avail[m.id] == true
				if ok or o.showAll then
					local perf = perfOf(VS, m.kind)
					local name = if type(GS.modelName) == "function" then GS.modelName(m) else (m.label or m.id)
					local kitInfo = GS.CATALOG[m.kind]
					push({
						id = "model:" .. m.id,
						kind = m.kind,
						grade = "new",
						model = m.id,
						name = name,
						short = name,
						glyph = m.glyph or "🚗",
						body = m.body or KIND_BODY[m.kind] or "승용",
						seats = m.seats or 5,
						price = math.floor(m.price),
						tag = m.tag,
						blurb = m.blurb or "",
						perf = perf,
						bars = barsOf(perf, m.kind),
						available = ok,
						preview = if ok then "model_" .. m.id else "kit_" .. m.kind,
						brand = brandOf(GS, m.kind, m),
						deliverAs = if ok then nil else (kitInfo.full or kitInfo.label),
					})
				end
			end
		end
	end
	local R = GS.RENTAL
	if o.rent ~= false and type(R) == "table" and GS.CATALOG[R.kind] and U.finite(R.fee) then
		local c = GS.CATALOG[R.kind]
		local perf = perfOf(VS, R.kind)
		push({
			id = "rent",
			kind = R.kind,
			grade = "rent",
			name = R.label or ((c.label or "") .. " 하루 렌트"),
			short = "하루 렌트",
			glyph = "🔑",
			body = (KIND_BODY[R.kind] or "승용") .. " · 렌터카",
			seats = c.seats or 4,
			price = math.floor(R.fee),
			blurb = string.format("게임 시간 하루(%d분) 동안 %s를 타요 · 차고 대수에 안 들어가요", math.floor((R.seconds or 2400) / 60), c.label or "경차"),
			perf = perf,
			bars = barsOf(perf, R.kind),
			available = true,
			preview = "kit_" .. R.kind,
			brand = Config.LINEUPS.rent or "렌터카",
			rentSeconds = R.seconds or 2400,
		})
	end
	return out, byId
end

-- The categories that hold at least one entry (in tab order).
function Catalog.catsIn(entries: { any }): { any }
	local used: { [string]: boolean } = { all = true }
	for _, e in entries do
		for _, c in e.cats or {} do
			used[c] = true
		end
	end
	local out = {}
	for _, c in Catalog.CATS do
		if used[c.id] then
			table.insert(out, c)
		end
	end
	return out
end

function Catalog.brandsIn(entries: { any }): { string }
	local seen, out = {}, {}
	for _, e in entries do
		if e.brand and not seen[e.brand] then
			seen[e.brand] = true
			table.insert(out, e.brand)
		end
	end
	return out
end

function Catalog.parse(id: any): any?
	if type(id) ~= "string" or #id > 40 then
		return nil
	end
	if id == "rent" then
		return { type = "rent" }
	end
	local kind, grade = string.match(id, "^kit:(%l+):(%l+)$")
	if kind then
		if grade ~= "new" and grade ~= "used" then
			return nil
		end
		return { type = "kit", kind = kind, grade = grade }
	end
	local model = string.match(id, "^model:([%w_]+)$")
	if model and #model <= 24 then
		return { type = "model", model = model }
	end
	return nil
end

-- 이달의 특가: `count` entries picked by a stable hash of the month, at most one per kind, never 렌트.
function Catalog.pickSpecials(entries: { any }, monthKey: string, count: number, minPrice: number): { [string]: boolean }
	local pool = {}
	for _, e in entries do
		if e.grade ~= "rent" and e.available and e.price >= minPrice then
			table.insert(pool, { e = e, h = U.hash(monthKey .. "|" .. e.id) })
		end
	end
	table.sort(pool, function(a, b)
		if a.h ~= b.h then
			return a.h < b.h
		end
		return a.e.id < b.e.id
	end)
	local out, kinds, n = {}, {}, 0
	for _, p in pool do
		if n >= count then
			break
		end
		if not kinds[p.e.kind] then
			kinds[p.e.kind] = true
			out[p.e.id] = true
			n += 1
		end
	end
	return out
end

-- Dealer benefits paid back after the purchase (refund-labelled). ctx = { usedRate = number, special = bool }
function Catalog.benefits(e: any, ctx: any): any
	local lines = {}
	local rate = 0
	if not e or e.grade == "rent" then
		return { lines = lines, total = 0, rate = 0 }
	end
	if Config.SPECIALS.enabled and (ctx.special == true or e.special == true) then
		table.insert(lines, { key = "special", rate = Config.SPECIALS.rate, label = "이달의 특가" })
		rate += Config.SPECIALS.rate
	end
	local ur = tonumber(ctx.usedRate) or 0
	if Config.USED_DISCOUNT_CASHBACK and e.grade == "used" and ur > 0 then
		table.insert(lines, { key = "used", rate = ur, label = "레벨 혜택 · 중고차" })
		rate += ur
	end
	local capRate = math.min(rate, Config.MAX_CASHBACK_RATE)
	local total = 0
	local left = U.round100(e.price * capRate)
	for _, l in lines do
		local amt = math.min(left, U.round100(e.price * l.rate))
		l.amount = amt
		left -= amt
		total += amt
	end
	return { lines = lines, total = total, rate = capRate }
end

-- Can the player pay today? "full" (one account covers the price), "loan" (one covers the 계약금), nil.
-- The garage charges one account (통장 first, else 현금), never a split.
function Catalog.affordable(e: any, bank: number, cash: number): string?
	if not e then
		return nil
	end
	if bank >= e.price or cash >= e.price then
		return "full"
	end
	if e.canLoan and e.loan and (bank >= e.loan.down or cash >= e.loan.down) then
		return "loan"
	end
	return nil
end

local function lower(s: string): string
	return string.lower(s)
end

-- f = { cat, brand, query, money = { bank, cash }, affordableOnly, loanOnly, wish = { [id] = true }, wishOnly }
function Catalog.filter(entries: { any }, f: any): { any }
	local out = {}
	local q = if type(f.query) == "string" then lower((string.gsub(f.query, "^%s+", ""))) else ""
	q = (string.gsub(q, "%s+$", ""))
	for _, e in entries do
		local ok = true
		if f.cat and f.cat ~= "all" and not table.find(e.cats, f.cat) then
			ok = false
		end
		if ok and f.brand and e.brand ~= f.brand then
			ok = false
		end
		if ok and f.affordableOnly and f.money and not Catalog.affordable(e, f.money.bank or 0, f.money.cash or 0) then
			ok = false
		end
		if ok and f.loanOnly and not e.canLoan then
			ok = false
		end
		if ok and f.wishOnly and not (f.wish and f.wish[e.id]) then
			ok = false
		end
		if ok and q ~= "" then
			local hay = lower(table.concat({ e.name or "", e.short or "", e.body or "", e.blurb or "", e.brand or "", e.tag or "", e.fuel or "", if e.grade == "used" then "중고" elseif e.grade == "rent" then "렌트" else "신차" }, " "))
			for _, c in e.cats do
				local cat = Catalog.CAT_BY_ID[c]
				if cat then
					hay ..= " " .. lower(cat.label)
				end
			end
			if not string.find(hay, q, 1, true) then
				ok = false
			end
		end
		if ok then
			table.insert(out, e)
		end
	end
	return out
end

local TAG_RANK = { ["첫 차 추천"] = 1, ["가성비"] = 2, ["최저가"] = 3, ["고성능"] = 4, ["드림카"] = 5 }

function Catalog.sort(list: { any }, key: string, money: any?): { any }
	local bank = money and money.bank or 0
	local cash = money and money.cash or 0
	local function recScore(e: any): number
		local s = 0
		if e.special then
			s -= 300
		end
		local a = Catalog.affordable(e, bank, cash)
		if a == "full" then
			s -= 200
		elseif a == "loan" then
			s -= 120
		end
		if e.grade == "rent" then
			s += 260 -- 렌트 last: it is not a car to buy
		end
		if e.tag and TAG_RANK[e.tag] then
			s -= 30 - TAG_RANK[e.tag]
		end
		return s
	end
	table.sort(list, function(a, b)
		if key == "low" then
			if a.price ~= b.price then
				return a.price < b.price
			end
		elseif key == "high" then
			if a.price ~= b.price then
				return a.price > b.price
			end
		elseif key == "fast" then
			if a.perf.top ~= b.perf.top then
				return a.perf.top > b.perf.top
			end
			if a.price ~= b.price then
				return a.price > b.price
			end
		else
			local sa, sb = recScore(a), recScore(b)
			if sa ~= sb then
				return sa < sb
			end
			if a.price ~= b.price then
				return a.price < b.price
			end
		end
		return a.order < b.order
	end)
	return list
end

-- The dealer's pick for a budget (won; nil = no limit): the best car one account can pay in full within it,
-- else the best whose 계약금 fits (할부). -> entry?, "full" | "loan" | nil
function Catalog.recommend(entries: { any }, budget: number?, money: any): (any?, string?)
	local bank, cash = money.bank or 0, money.cash or 0
	local best, bestHow = nil, nil
	local function better(e: any): boolean
		if not best then
			return true
		end
		if budget == nil then
			if e.price ~= best.price then
				return e.price > best.price
			end
			return e.order < best.order
		end
		-- within a budget: the priciest that fits, a 첫 차 추천 wins ties under 50만
		if e.price ~= best.price then
			return e.price > best.price
		end
		return (e.tag == "첫 차 추천") and best.tag ~= "첫 차 추천"
	end
	for _, e in entries do
		if e.grade ~= "rent" and e.available then
			local fits = budget == nil or e.price <= budget
			local how = Catalog.affordable(e, bank, cash)
			if fits and how == "full" and (bestHow ~= "full" or better(e)) then
				best, bestHow = e, "full"
			end
		end
	end
	if best then
		return best, bestHow
	end
	for _, e in entries do
		if e.grade ~= "rent" and e.available and e.canLoan and e.loan then
			local fits = budget == nil or e.loan.down <= budget
			if fits and Catalog.affordable(e, bank, cash) == "loan" and better(e) then
				best, bestHow = e, "loan"
			end
		end
	end
	if best then
		return best, bestHow
	end
	-- nothing payable today: the cheapest within the budget (a goal to save for)
	for _, e in entries do
		if e.grade ~= "rent" and e.available and (budget == nil or e.price <= budget) then
			if not best or e.price < best.price then
				best = e
			end
		end
	end
	return best, nil
end

function Catalog.gradeLabel(e: any): string
	if e.grade == "used" then
		return "중고"
	elseif e.grade == "rent" then
		return "렌트"
	end
	return "신차"
end

-- "SUV · 5인승 · 사륜구동"
function Catalog.subline(e: any): string
	return string.format("%s · %d인승 · %s", e.body or "", e.seats or 5, DRIVE_KO[e.perf.drive] or e.perf.drive)
end

-- The sibling grade of a kit entry (신차 <-> 중고), nil for models / 렌트.
function Catalog.sibling(e: any, byId: { [string]: any }): any?
	if not e or e.model or e.grade == "rent" then
		return nil
	end
	local other = if e.grade == "new" then "used" else "new"
	return byId["kit:" .. e.kind .. ":" .. other]
end

return Catalog
