-- GwangalliPhone/Life: life-game data for the phone apps (jobs, home listings, contacts, stats),
-- read from GwangalliGameplayShared when it has them (JOBS / JOB_ORDER, LISTINGS | HOMES /
-- LISTING_ORDER, NPCS, CONTACTS) and otherwise from the fallback catalogue below, which mirrors
-- docs/LIFE_GAME_DESIGN.md so the apps always have something to show. Field names are read
-- leniently (title | name, wage | hourly | pay, ...). Pure data: never yields after start.

local Data = require(script.Parent:WaitForChild("Data"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Life = {}

local shared: any = nil
local function S(): any
	if shared then
		return shared
	end
	local m = ReplicatedStorage:FindFirstChild("GwangalliGameplayShared")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			shared = res
		end
	end
	return shared
end

local function field(t: any, ...: string): any
	if type(t) ~= "table" then
		return nil
	end
	for _, k in { ... } do
		local v = t[k]
		if v ~= nil then
			return v
		end
	end
	return nil
end
local function str(v: any, d: string?): string
	return if type(v) == "string" and v ~= "" then v else (d or "")
end
local function num(v: any, d: number?): number
	local n = tonumber(v)
	return if n and n == n then n else (d or 0)
end
local function color(v: any, d: Color3): Color3
	if typeof(v) == "Color3" then
		return v
	elseif type(v) == "table" and tonumber(v[1]) then
		return Color3.fromRGB(num(v[1]), num(v[2]), num(v[3]))
	end
	return d
end

-- Fallback catalogue -----------------------------------------------------------------------------------
local FALLBACK_JOBS = {
	{ id = "cvs", title = "편의점 알바", place = "GS25 광안리점", wage = 10000, icon = "🏪", ranks = { "알바", "매니저", "점장" }, req = {} },
	{ id = "cafe", title = "카페 바리스타", place = "스타벅스 광안리점", wage = 11000, icon = "☕", ranks = { "바리스타", "슈퍼바이저" }, req = { appearance = 20 } },
	{ id = "delivery", title = "배달 라이더", place = "민락회타운", wage = 13000, icon = "🛵", ranks = { "라이더", "베테랑" }, req = { stamina = 20 } },
	{ id = "sashimi", title = "횟집 서빙", place = "민락회타운", wage = 12000, icon = "🐟", ranks = { "서버", "실장" }, req = {} },
	{ id = "lifeguard", title = "해수욕장 안전요원", place = "광안리해수욕장 (중앙)", wage = 14000, icon = "🛟", ranks = { "요원", "팀장" }, req = { stamina = 40 } },
	{ id = "taxi", title = "택시 기사", place = "광안리 만남의 광장", wage = 15000, icon = "🚕", ranks = { "기사", "베테랑" }, req = { popularity = 10 } },
}

local FALLBACK_LISTINGS = {
	{ id = "goshiwon", name = "광안 고시원", tier = 1, kind = "rent", rentPerDay = 3000, price = 0, place = "지하철 광안역 6번 출구", desc = "침대 하나, 공용 샤워실" },
	{ id = "oneroom", name = "광안동 원룸", tier = 2, kind = "rent", rentPerDay = 8000, price = 0, place = "광안동우체국", desc = "풀옵션 원룸" },
	{ id = "officetel", name = "테라스타오션 오피스텔", tier = 3, kind = "rent", rentPerDay = 20000, price = 0, place = "테라스타오션", desc = "바다가 살짝 보이는 오피스텔" },
	{ id = "apartment", name = "광안자이 32평", tier = 4, kind = "buy", rentPerDay = 0, price = 30000000, place = "광안자이 (정문)", desc = "대단지 아파트 · 매매" },
	{ id = "penthouse", name = "오션뷰 펜트하우스", tier = 5, kind = "buy", rentPerDay = 0, price = 150000000, place = "광안지웰에스테이트", desc = "광안대교 정면 뷰 · 매매" },
}

local STAT_META = {
	appearance = { label = "외모", icon = "✨", color = Color3.fromRGB(255, 92, 150) },
	stamina = { label = "체력", icon = "💪", color = Color3.fromRGB(52, 211, 120) },
	happiness = { label = "행복", icon = "😊", color = Color3.fromRGB(255, 204, 64) },
	popularity = { label = "인기", icon = "⭐", color = Color3.fromRGB(156, 92, 255) },
}
Life.STAT_ORDER = { "appearance", "stamina", "happiness", "popularity" }
function Life.stat(id: string): any
	return STAT_META[id] or { label = id, icon = "•", color = Color3.fromRGB(88, 130, 255) }
end

-- Jobs ---------------------------------------------------------------------------------------------------
local function normJob(id: string, j: any, order: number): any
	local ranks = field(j, "ranks", "titles", "levels", "promotions")
	local rankList = {}
	if type(ranks) == "table" then
		for _, r in ranks do
			if type(r) == "string" then
				table.insert(rankList, r)
			elseif type(r) == "table" then
				table.insert(rankList, str(field(r, "title", "name")))
			end
		end
	end
	local req = field(j, "req", "requirements", "requires")
	return {
		id = id,
		title = str(field(j, "title", "name"), id),
		place = str(field(j, "place", "location", "dest", "destination", "workplace")),
		wage = num(field(j, "wage", "hourly", "pay", "basePay", "wagePerTask"), num(type(ranks) == "table" and type(ranks[1]) == "table" and ranks[1].wage)),
		icon = str(field(j, "icon", "glyph", "emoji"), "💼"),
		desc = str(field(j, "desc", "description", "summary")),
		ranks = rankList,
		req = if type(req) == "table" then req else {},
		order = num(field(j, "order"), order),
	}
end

function Life.jobs(): { any }
	local G = S()
	local src = G and (G.JOBS or G.Jobs)
	local out = {}
	if type(src) == "table" and next(src) then
		local order = G.JOB_ORDER
		if type(order) == "table" and #order > 0 then
			for i, id in order do
				if src[id] then
					table.insert(out, normJob(id, src[id], i))
				end
			end
		end
		if #out == 0 then
			for k, j in src do
				local id = if type(k) == "string" then k else str(field(j, "id"), tostring(k))
				table.insert(out, normJob(id, j, #out + 1))
			end
			table.sort(out, function(a, b)
				if a.order ~= b.order then
					return a.order < b.order
				end
				return a.id < b.id
			end)
		end
		return out
	end
	for i, j in FALLBACK_JOBS do
		table.insert(out, normJob(j.id, j, i))
	end
	return out
end

function Life.job(id: any): any
	if type(id) ~= "string" then
		return nil
	end
	for _, j in Life.jobs() do
		if j.id == id then
			return j
		end
	end
	return nil
end

-- requirement text + whether the profile meets it
function Life.reqText(job: any, stats: any): (string, boolean)
	local parts, ok = {}, true
	for k, v in job.req or {} do
		local need = num(v)
		if need > 0 then
			local have = num(type(stats) == "table" and stats[k])
			local meta = Life.stat(tostring(k))
			table.insert(parts, string.format("%s %d", meta.label, need))
			if have < need then
				ok = false
			end
		end
	end
	if #parts == 0 then
		return "조건 없음", true
	end
	return table.concat(parts, " · ") .. " 이상", ok
end

-- Listings -----------------------------------------------------------------------------------------------
local function normListing(id: string, l: any, order: number): any
	local kind = str(field(l, "kind", "type", "mode", "contract"))
	local rent = num(field(l, "rentPerDay", "rent", "dailyRent"))
	local price = num(field(l, "price", "buyPrice", "salePrice", "value"))
	if kind == "" then
		kind = if rent > 0 then "rent" else "buy"
	end
	if kind == "월세" or kind == "lease" then
		kind = "rent"
	elseif kind == "매매" or kind == "sale" or kind == "own" then
		kind = "buy"
	end
	return {
		id = id,
		name = str(field(l, "name", "title"), id),
		tier = num(field(l, "tier", "level"), order),
		kind = kind,
		rentPerDay = rent,
		deposit = num(field(l, "deposit")),
		price = price,
		place = str(field(l, "place", "building", "dest", "destination", "location")),
		desc = str(field(l, "desc", "description", "summary")),
		order = num(field(l, "order"), order),
		canBuy = price > 0 and (kind == "buy" or field(l, "buyable") == true),
		canRent = rent > 0,
	}
end

function Life.listings(): { any }
	local G = S()
	local src = G and (G.LISTINGS or G.HOMES or G.HOME_LISTINGS or G.Listings)
	local out = {}
	if type(src) == "table" and next(src) then
		local order = G.LISTING_ORDER or G.HOME_ORDER
		if type(order) == "table" and #order > 0 then
			for i, id in order do
				if src[id] then
					table.insert(out, normListing(id, src[id], i))
				end
			end
		end
		if #out == 0 then
			for k, l in src do
				local id = if type(k) == "string" then k else str(field(l, "id"), tostring(k))
				table.insert(out, normListing(id, l, #out + 1))
			end
		end
	else
		for i, l in FALLBACK_LISTINGS do
			table.insert(out, normListing(l.id, l, i))
		end
	end
	table.sort(out, function(a, b)
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		return a.order < b.order
	end)
	return out
end

function Life.listing(id: any): any
	for _, l in Life.listings() do
		if l.id == id then
			return l
		end
	end
	return nil
end

-- Contacts for the 전화 app ----------------------------------------------------------------------------------
-- { id, name, role, glyph, color, kind = "taxi"|"person" }. The taxi entry is always first.
function Life.contacts(profileContacts: any): { any }
	local out = { { id = "taxi", name = "택시 호출", role = "부산 콜택시 · 24시간", glyph = "🚕", color = Color3.fromRGB(255, 196, 0), kind = "taxi" } }
	local seen = { taxi = true, driver = true }
	local function add(id: string, c: any)
		if seen[id] then
			return
		end
		seen[id] = true
		local base = Data.contact(id)
		table.insert(out, {
			id = id,
			name = str(field(c, "name"), base.name),
			role = str(field(c, "role", "title"), base.role),
			glyph = str(field(c, "icon", "glyph", "emoji"), base.glyph),
			color = color(field(c, "color", "portraitColor"), base.color),
			kind = "person",
		})
	end
	-- the server's per-player contact list wins (ids or tables)
	if type(profileContacts) == "table" then
		for k, c in profileContacts do
			if type(k) == "string" then
				add(k, if type(c) == "table" then c else nil)
			elseif type(c) == "string" then
				add(c, nil)
			elseif type(c) == "table" and type(c.id) == "string" then
				add(c.id, c)
			end
		end
	end
	local G = S()
	if #out <= 1 and G and type(G.CONTACTS) == "table" then
		local order = if type(G.CONTACT_ORDER) == "table" then G.CONTACT_ORDER else {}
		for _, id in order do
			if G.CONTACTS[id] then
				add(id, G.CONTACTS[id])
			end
		end
		for id, c in G.CONTACTS do
			if type(id) == "string" then
				add(id, c)
			end
		end
	end
	return out
end

-- "12:34 후" style countdown for a number of real seconds
function Life.countdown(sec: any): string
	local s = math.max(0, math.floor(num(sec)))
	if s >= 3600 then
		return string.format("%d시간 %d분", s // 3600, (s % 3600) // 60)
	elseif s >= 60 then
		return string.format("%d분 %d초", s // 60, s % 60)
	end
	return string.format("%d초", s)
end

-- Money helpers -------------------------------------------------------------------------------------------
function Life.cash(p: any): number
	return num(type(p) == "table" and (p.cash or (p.bank == nil and p.money)))
end
function Life.bank(p: any): number
	return num(type(p) == "table" and p.bank)
end
function Life.homeValue(p: any): number
	local h = type(p) == "table" and p.home
	if type(h) ~= "table" or not h.owned then
		return 0
	end
	local v = num(h.value or h.price)
	if v <= 0 and type(p.netWorth) == "number" then
		return math.max(0, p.netWorth - Life.cash(p) - Life.bank(p))
	end
	if v > 0 then
		return v
	end
	local l = Life.listing(h.listingId)
	return if l then l.price else 0
end
function Life.totalAssets(p: any): number
	return Life.cash(p) + Life.bank(p) + Life.homeValue(p)
end

return Life
