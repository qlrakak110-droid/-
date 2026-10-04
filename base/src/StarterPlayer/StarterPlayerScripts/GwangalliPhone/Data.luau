-- GwangalliPhone/Data: read-only access to ReplicatedStorage.GwangalliGameplayShared (owned by the
-- gameplay core) plus normalisers for everything the phone shows. The shared module is optional
-- at start (the server core may not exist yet): every accessor falls back to sensible defaults and
-- the module keeps looking for it in the background, then calls the onLoaded listeners.
--
-- Normalised shapes used by the apps:
--   Quest  { id, title, giver, desc, steps = { step }, reward = { money, stats = { [stat] = n } },
--            repeatable, order, raw }
--   Thread { id, name, glyph, color, role, msgs = { { me, text, t } }, unread, choices = { { label,
--            value, index } }, lastT, lastText }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent:WaitForChild("UI"))

local Data = {}
Data.Shared = nil :: any

local loadedListeners: { () -> () } = {}
function Data.onLoaded(fn: () -> ())
	table.insert(loadedListeners, fn)
end

local function tryRequire(m: Instance?): any
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
		warn("[GwangalliPhone] GwangalliGameplayShared failed to load: " .. tostring(res))
	end
	return nil
end

function Data.start()
	local m = ReplicatedStorage:FindFirstChild("GwangalliGameplayShared")
	local mod = tryRequire(m)
	if mod then
		Data.Shared = mod
		return
	end
	task.spawn(function()
		while not Data.Shared do
			local found = ReplicatedStorage:WaitForChild("GwangalliGameplayShared", 20)
			if found then
				local loaded = tryRequire(found)
				if loaded then
					Data.Shared = loaded
					for _, fn in loadedListeners do
						task.spawn(fn)
					end
					return
				end
				task.wait(30) -- present but broken: do not spin
			end
		end
	end)
end

local function S(): any
	return Data.Shared
end

-- Generic table helpers -------------------------------------------------------------------------------
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
Data.field = field

local function str(v: any): string?
	if type(v) == "string" and v ~= "" then
		return v
	elseif type(v) == "number" then
		return tostring(v)
	end
	return nil
end

-- Iterates a dict-or-list definition table as (id, def) pairs, sorted by def.order / list index / id.
local function entries(tbl: any): { { id: string, def: any, order: number } }
	local out = {}
	if type(tbl) ~= "table" then
		return out
	end
	local isList = #tbl > 0
	for k, def in tbl do
		local id: string? = nil
		local order = 1000
		if isList and type(k) == "number" then
			order = k
			if type(def) == "table" then
				id = str(field(def, "id", "key", "name"))
			elseif type(def) == "string" then
				id = def
			end
		else
			id = str(k)
			if type(def) == "table" and type(def.order) == "number" then
				order = def.order
			end
		end
		if id then
			table.insert(out, { id = id, def = def, order = order })
		end
	end
	table.sort(out, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.id < b.id
	end)
	return out
end
Data.entries = entries

local function findDef(tbl: any, id: any): any
	if type(tbl) ~= "table" or id == nil then
		return nil
	end
	local direct = tbl[id]
	if direct ~= nil then
		return direct
	end
	for _, e in entries(tbl) do
		if e.id == id then
			return e.def
		end
	end
	return nil
end

-- Money ---------------------------------------------------------------------------------------------------
function Data.won(n: any): string
	local v = tonumber(n) or 0
	local shared = S()
	local fmt = shared and shared.format
	if type(fmt) == "table" and type(fmt.won) == "function" then
		local ok, s = pcall(fmt.won, v)
		if ok and type(s) == "string" then
			return s
		end
	end
	return UI.commas(v) .. "원"
end

-- Stats ----------------------------------------------------------------------------------------------------
Data.STAT_ORDER = { "appearance", "strength", "stamina", "popularity" }
local STAT_DEFAULT = { appearance = "외모지수", strength = "근력", stamina = "체력", popularity = "인기도" }
Data.STAT_ICON = { appearance = "✨", strength = "💪", stamina = "🏃", popularity = "⭐" }
Data.STAT_COLOR = { appearance = UI.C.pink, strength = UI.C.orange, stamina = UI.C.green, popularity = UI.C.purple }
Data.STAT_MAX = 100

function Data.statLabel(id: string): string
	local shared = S()
	local stats = shared and (shared.STATS or shared.Stats)
	local def = findDef(stats, id)
	if type(def) == "string" then
		return def
	elseif type(def) == "table" then
		local n = str(field(def, "label", "name", "title", "kr"))
		if n then
			return n
		end
	end
	return STAT_DEFAULT[id] or id
end

function Data.statMax(id: string): number
	local shared = S()
	local def = findDef(shared and (shared.STATS or shared.Stats), id)
	local m = type(def) == "table" and tonumber(field(def, "max", "cap")) or nil
	return m or tonumber(shared and shared.STAT_MAX) or Data.STAT_MAX
end

function Data.statIcon(id: string): string
	local shared = S()
	local def = findDef(shared and (shared.STATS or shared.Stats), id)
	return (type(def) == "table" and str(field(def, "icon", "emoji"))) or Data.STAT_ICON[id] or "•"
end

function Data.statDesc(id: string): string
	local shared = S()
	local def = findDef(shared and (shared.STATS or shared.Stats), id)
	return (type(def) == "table" and str(field(def, "desc", "description"))) or ""
end

-- Stat values carry one decimal (12.3); never feed them to "%d" (Luau errors on non-integers).
function Data.fmtStat(v: any): string
	local n = tonumber(v) or 0
	if n ~= n then
		n = 0
	end
	n = math.floor(n * 10 + 0.5) / 10
	if n == math.floor(n) then
		return tostring(math.floor(n))
	end
	return string.format("%.1f", n)
end

-- "+1.5" / "-2"
function Data.fmtDelta(v: any): string
	local n = tonumber(v) or 0
	return (if n >= 0 then "+" else "-") .. Data.fmtStat(math.abs(n))
end

-- Integer text for counters that might arrive as floats.
function Data.int(v: any): string
	local n = tonumber(v) or 0
	if n ~= n or n == math.huge or n == -math.huge then
		n = 0
	end
	return tostring(math.floor(n + 0.5))
end

-- 외모지수 grade text
function Data.appearanceGrade(v: number): string
	if v >= 90 then
		return "연예인급"
	elseif v >= 75 then
		return "훈훈함"
	elseif v >= 55 then
		return "호감형"
	elseif v >= 35 then
		return "깔끔함"
	end
	return "평범함"
end

-- Contacts --------------------------------------------------------------------------------------------------
local DEFAULT_CONTACTS = {
	{ id = "minji", name = "민지", role = "친구" },
	{ id = "junho", name = "준호", role = "친구" },
	{ id = "coach", name = "김코치", role = "트레이너" },
	{ id = "taeyang", name = "태양", role = "클럽 MD" },
	{ id = "boss", name = "사장님", role = "GS25" },
	{ id = "driver", name = "기사님", role = "택시" },
}
local PALETTE = { UI.C.pink, UI.C.accent, UI.C.orange, UI.C.purple, UI.C.green, UI.C.teal, Color3.fromRGB(255, 120, 80) }

local function hash(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end

local function firstGlyph(name: string): string
	for _, cp in utf8.codes(name) do
		return utf8.char(cp)
	end
	return "?"
end

-- Returns { id, name, role, glyph, color } for a contact id or display name (never nil).
function Data.contact(key: any): { id: string, name: string, role: string, glyph: string, color: Color3 }
	local id = str(key) or "?"
	local shared = S()
	local tbl = shared and (shared.CONTACTS or shared.Contacts)
	local def = findDef(tbl, id)
	if def == nil and type(tbl) == "table" then
		-- maybe keyed by id while we were given the display name
		for _, e in entries(tbl) do
			local d = e.def
			if type(d) == "table" and str(field(d, "name", "displayName", "title")) == id then
				def = d
				id = e.id
				break
			elseif d == id then
				def = d
				id = e.id
				break
			end
		end
	end
	if def == nil then
		for _, d in DEFAULT_CONTACTS do
			if d.id == id or d.name == id then
				def = d
				break
			end
		end
	end
	local name, role = id, ""
	local color: Color3? = nil
	local glyph: string? = nil
	if type(def) == "string" then
		name = def
	elseif type(def) == "table" then
		name = str(field(def, "name", "displayName", "title")) or id
		role = str(field(def, "role", "desc", "subtitle", "relation")) or ""
		local c = field(def, "color", "colour")
		if typeof(c) == "Color3" then
			color = c
		elseif type(c) == "table" and tonumber(c[1]) and tonumber(c[2]) and tonumber(c[3]) then
			color = Color3.fromRGB(math.clamp(tonumber(c[1]) :: number, 0, 255), math.clamp(tonumber(c[2]) :: number, 0, 255), math.clamp(tonumber(c[3]) :: number, 0, 255))
		end
		glyph = str(field(def, "emoji", "icon", "glyph"))
	end
	return {
		id = id,
		name = name,
		role = role,
		glyph = glyph or firstGlyph(name),
		color = color or PALETTE[hash(id) % #PALETTE + 1],
	}
end

-- Items / styles --------------------------------------------------------------------------------------------
export type Item = {
	id: string,
	name: string,
	price: number,
	shop: string?,
	nearDest: string?,
	phone: boolean,
	kind: string,
	ref: string?,
	desc: string,
}

function Data.item(id: any): Item
	local sid = str(id) or "?"
	local shared = S()
	local def = nil
	for _, key in { "ITEMS", "Items", "CLOTHES", "Clothes", "SALON", "Salon" } do
		def = findDef(shared and shared[key], sid)
		if def ~= nil then
			break
		end
	end
	if type(def) == "table" then
		return {
			id = sid,
			name = str(field(def, "name", "title", "label")) or sid,
			price = tonumber(field(def, "price", "cost")) or 0,
			shop = str(field(def, "shop", "shopId", "ShopId")),
			nearDest = str(field(def, "nearDest", "destination")),
			phone = field(def, "phone") == true,
			kind = str(field(def, "kind", "category")) or "consumable",
			ref = str(field(def, "ref")),
			desc = str(field(def, "desc", "description", "effectText")) or "",
		}
	end
	return { id = sid, name = if type(def) == "string" then def else sid, price = 0, shop = nil, nearDest = nil, phone = false, kind = "consumable", ref = nil, desc = "" }
end

-- Every item in display order (G.ITEM_ORDER, then the rest by id).
function Data.items(): { Item }
	local shared = S()
	local tbl = shared and (shared.ITEMS or shared.Items)
	local out = {}
	if type(tbl) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	local order = shared.ITEM_ORDER
	if type(order) == "table" then
		for _, id in order do
			if type(id) == "string" and tbl[id] ~= nil and not seen[id] then
				seen[id] = true
				table.insert(out, Data.item(id))
			end
		end
	end
	for _, e in entries(tbl) do
		if not seen[e.id] then
			seen[e.id] = true
			table.insert(out, Data.item(e.id))
		end
	end
	return out
end

-- Shop metadata: { id, name, title }
local SHOP_DEFAULT = {
	clothing = { name = "편집숍", title = "헤어살롱 & 편집숍 · 의류" },
	salon = { name = "헤어살롱", title = "헤어살롱 & 편집숍 · 헤어" },
	gym_store = { name = "휘트니스 매점", title = "광안 휘트니스 24 · 매점" },
}
function Data.shop(id: string): { id: string, name: string, title: string }
	local shared = S()
	local def = findDef(shared and (shared.SHOPS or shared.Shops), id)
	local d = SHOP_DEFAULT[id]
	return {
		id = id,
		name = (type(def) == "table" and str(field(def, "name"))) or (d and d.name) or id,
		title = (type(def) == "table" and str(field(def, "title", "name"))) or (d and d.title) or id,
	}
end

function Data.nearDestRadius(): number
	local shared = S()
	return tonumber(shared and shared.NEAR_DEST_RADIUS) or 45
end

function Data.shopReach(): number
	local shared = S()
	return tonumber(shared and shared.SHOP_REACH) or 14
end

-- Buff display name / description.
function Data.buff(id: string): { name: string, desc: string }
	local shared = S()
	local def = findDef(shared and (shared.BUFFS or shared.Buffs), id)
	return {
		name = (type(def) == "table" and str(field(def, "name"))) or id,
		desc = (type(def) == "table" and str(field(def, "desc"))) or "",
	}
end

local function styleName(keys: { string }, id: any): string?
	local sid = str(id)
	if not sid then
		return nil
	end
	local shared = S()
	for _, key in keys do
		local def = findDef(shared and shared[key], sid)
		if type(def) == "table" then
			return str(field(def, "name", "title", "label")) or sid
		elseif type(def) == "string" then
			return def
		end
	end
	return sid
end
function Data.outfitName(id: any): string?
	return styleName({ "CLOTHES", "Clothes", "OUTFITS" }, id)
end
function Data.hairName(id: any): string?
	return styleName({ "SALON", "Salon", "HAIR" }, id)
end

-- Taxi fares ---------------------------------------------------------------------------------------------------
function Data.taxi(): { base: number, perStud: number, max: number }
	local shared = S()
	local t = shared and (shared.TAXI or shared.Taxi)
	return {
		base = tonumber(field(t, "baseFare", "base", "BaseFare")) or 4800,
		perStud = tonumber(field(t, "perStud", "perStudRate", "rate", "PerStud")) or 4,
		max = tonumber(field(t, "max", "maxFare", "Max")) or 30000,
	}
end

-- Fare estimate for a ride of `studs` (straight line; the server charges the real fare).
-- clock: in-game clock (night surcharge), popularity: 인기도 (regular discount).
function Data.fareFor(studs: number, clock: number?, popularity: number?): number
	local shared = S()
	local fn = shared and shared.taxiFare
	if type(fn) == "function" then
		local ok, v = pcall(fn, studs, clock, popularity)
		if ok and type(v) == "number" and v == v then
			return v
		end
	end
	local t = Data.taxi()
	local fare = math.min(t.max, t.base + t.perStud * math.max(0, studs))
	return math.floor(fare / 100 + 0.5) * 100
end

-- Is the night surcharge active at this clock? (22:00-04:00 by default)
function Data.taxiNight(clock: number): boolean
	local shared = S()
	local T = shared and (shared.TAXI or shared.Taxi)
	local from = tonumber(field(T, "nightFrom")) or 22
	local to = tonumber(field(T, "nightTo")) or 4
	local c = clock % 24
	if from <= to then
		return c >= from and c < to
	end
	return c >= from or c < to
end

-- Quests --------------------------------------------------------------------------------------------------------
local function normReward(r: any): { money: number, stats: { [string]: number }, items: { string } }
	local out = { money = 0, stats = {}, items = {} }
	if type(r) ~= "table" then
		return out
	end
	out.money = tonumber(field(r, "money", "won", "cash")) or 0
	local st = field(r, "stats", "stat")
	if type(st) == "table" then
		for k, v in st do
			if type(k) == "string" and tonumber(v) then
				out.stats[k] = tonumber(v) :: number
			end
		end
	end
	for _, id in Data.STAT_ORDER do
		if tonumber(r[id]) then
			out.stats[id] = tonumber(r[id]) :: number
		end
	end
	local items = field(r, "items", "item")
	if type(items) == "string" then
		table.insert(out.items, items)
	elseif type(items) == "table" then
		for _, v in items do
			if type(v) == "string" then
				table.insert(out.items, v)
			end
		end
	end
	return out
end

local function normQuest(id: string, def: any, order: number): any
	if type(def) ~= "table" then
		return nil
	end
	local steps = field(def, "steps", "objectives", "tasks")
	if type(steps) ~= "table" then
		steps = {}
	end
	return {
		id = id,
		title = str(field(def, "title", "name")) or id,
		giver = str(field(def, "giver", "contact", "from")),
		desc = str(field(def, "desc", "description", "summary", "intro", "text")) or "",
		category = str(field(def, "category", "kind")) or "side",
		steps = steps,
		reward = normReward(field(def, "reward", "rewards")),
		repeatable = field(def, "repeatable", "repeat") == true,
		order = tonumber(def.order) or order,
		raw = def,
	}
end

local CATEGORY = {
	main = { text = "메인", color = Color3.fromRGB(255, 159, 10) },
	side = { text = "사이드", color = Color3.fromRGB(62, 145, 255) },
	job = { text = "알바", color = Color3.fromRGB(52, 199, 89) },
}
function Data.category(id: string?): { text: string, color: Color3 }
	return CATEGORY[id or "side"] or CATEGORY.side
end

function Data.quests(): { any }
	local shared = S()
	local out = {}
	local tbl = shared and (shared.QUESTS or shared.Quests)
	local order = shared and shared.QUEST_ORDER
	local rank: { [string]: number } = {}
	if type(order) == "table" then
		for i, id in order do
			if type(id) == "string" then
				rank[id] = i
			end
		end
	end
	for _, e in entries(tbl) do
		local q = normQuest(e.id, e.def, rank[e.id] or (1000 + e.order))
		if q then
			table.insert(out, q)
		end
	end
	table.sort(out, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.id < b.id
	end)
	return out
end

function Data.quest(id: any): any
	local sid = str(id)
	if not sid then
		return nil
	end
	local shared = S()
	local tbl = shared and (shared.QUESTS or shared.Quests)
	local def = findDef(tbl, sid)
	if def then
		local order = 1000
		if type(shared.QUEST_ORDER) == "table" then
			order = table.find(shared.QUEST_ORDER, sid) or 1000
		end
		return normQuest(sid, def, order)
	end
	return nil
end

-- profile.quests.active -> { [questId] = progress } (accepts a dict or a list of ids / { id, ... })
function Data.activeQuests(q: any): { [string]: any }
	local a = type(q) == "table" and q.active or nil
	local out = {}
	if type(a) ~= "table" then
		return out
	end
	for k, v in a do
		if type(k) == "string" then
			if v ~= false then
				out[k] = if v == true then 1 else v
			end
		elseif type(k) == "number" then
			if type(v) == "string" then
				out[v] = 1
			elseif type(v) == "table" then
				local id = str(field(v, "id", "quest", "questId"))
				if id then
					out[id] = v
				end
			end
		end
	end
	return out
end

-- profile.quests.done -> { [questId] = true }
function Data.doneQuests(q: any): { [string]: boolean }
	local d = type(q) == "table" and q.done or nil
	local out = {}
	if type(d) ~= "table" then
		return out
	end
	for k, v in d do
		if type(k) == "string" and v then
			out[k] = true
		elseif type(k) == "number" and type(v) == "string" then
			out[v] = true
		end
	end
	return out
end

-- Progress value -> (step index 1-based, count within the step, raw table?)
function Data.progress(p: any, quest: any?): (number, number, any)
	if type(p) == "number" then
		return math.max(1, math.floor(p)), 0, nil
	elseif type(p) == "table" then
		local step = tonumber(field(p, "step", "stepIndex", "index", "current", "stage")) or 1
		local count = tonumber(field(p, "count", "reps", "n", "value", "progress", "done")) or 0
		if step < 1 then
			step += 1 -- tolerate 0-based
		end
		return math.floor(step), count, p
	end
	return 1, 0, nil
end

local function destOf(step: any): string?
	return str(field(step, "destination", "dest", "target", "place", "to", "name", "location"))
end

local TAG_TEXT = {
	GymStation = "헬스장 기구에서 운동하기",
	SalonChair = "헤어살롱에서 머리하기",
	ShopCounter = "가게 카운터 이용하기",
	ElevatorButton = "엘리베이터 타기",
}

-- Korean text for a step (count = progress inside the step).
function Data.stepText(step: any, count: number?): string
	if type(step) == "string" then
		return step
	end
	if type(step) ~= "table" then
		return "?"
	end
	local explicit = str(field(step, "text", "desc", "label", "title", "hint"))
	local kind = str(field(step, "type", "kind")) or ""
	local c = count or 0
	local text: string
	if explicit then
		text = explicit
	elseif kind == "goto" then
		text = UI.ro(destOf(step) or "목적지") .. " 가기"
	elseif kind == "taxi" then
		text = "택시 타고 " .. UI.ro(destOf(step) or "목적지") .. " 가기"
	elseif kind == "deliver" then
		local from = str(field(step, "from", "pickup")) or "출발지"
		local to = str(field(step, "to", "dropoff", "destination")) or "도착지"
		text = string.format("%s에서 받아 %s까지 배달", from, to)
	elseif kind == "interact" then
		local tag = str(field(step, "tag")) or ""
		text = TAG_TEXT[tag] or "상호작용하기"
	elseif kind == "stat" then
		local stat = str(field(step, "stat", "id")) or "appearance"
		local need = tonumber(field(step, "value", "min", "n", "amount", "target")) or 0
		text = string.format("%s %s 이상 만들기", Data.statLabel(stat), Data.fmtStat(need))
	elseif kind == "gym" then
		local reps = tonumber(field(step, "reps", "sets", "count", "n")) or 1
		text = string.format("헬스장에서 운동 %s세트", Data.int(reps))
	elseif kind == "buy" then
		local itemId = field(step, "itemId", "item", "id")
		local cat = str(field(step, "category"))
		if itemId == nil and cat == "hair" then
			text = "헤어살롱에서 스타일 바꾸기"
		elseif itemId == nil and cat == "outfit" then
			text = "편집숍에서 옷 사기"
		else
			text = Data.item(itemId).name .. " 사기"
		end
	elseif kind == "bowling" then
		local score = tonumber(field(step, "score", "min", "value", "n")) or 100
		text = string.format("볼링 %s점 이상 치기", Data.int(score))
	else
		text = "목표 진행하기"
	end
	-- counters
	if kind == "gym" then
		local reps = tonumber(field(step, "reps", "sets", "count", "n")) or 1
		if reps > 1 or c > 0 then
			text ..= string.format(" (%s/%s)", Data.int(math.min(c, reps)), Data.int(reps))
		end
	end
	return text
end

-- Where the step happens: { name = DestinationName } | { tag, attr, value } | { pos = Vector3 } | nil.
local SHOP_DEST = {
	salon = "헤어살롱 & 편집숍",
	clothing = "헤어살롱 & 편집숍",
	gym_store = "광안 휘트니스 24 (헬스장)",
	gs25 = "GS25 광안리점",
	convenience = "GS25 광안리점",
}
Data.GYM = "광안 휘트니스 24 (헬스장)"
Data.SALON = "헤어살롱 & 편집숍"
Data.SHOP_DEST = SHOP_DEST
local TAG_DEST = { ClubIDCheck = "CLUB OCEAN 광안" }

function Data.stepTarget(step: any, count: number?, prog: any?): any
	if type(step) ~= "table" then
		return nil
	end
	local pos = field(step, "position", "pos")
	if typeof(pos) == "Vector3" then
		return { pos = pos }
	end
	local kind = str(field(step, "type", "kind")) or ""
	if kind == "goto" or kind == "taxi" then
		local d = destOf(step)
		return d and { name = d } or nil
	elseif kind == "deliver" then
		local picked = false
		if type(prog) == "table" then
			picked = field(prog, "picked", "pickedUp", "carrying", "hasPackage") == true or (tonumber(field(prog, "phase", "leg")) or 1) >= 2
		end
		if (count or 0) >= 1 then
			picked = true
		end
		local from = str(field(step, "from", "pickup"))
		local to = str(field(step, "to", "dropoff", "destination"))
		local d = if picked then to else (from or to)
		return d and { name = d } or nil
	elseif kind == "interact" then
		local d = str(field(step, "destination", "dest", "place"))
		local tag = str(field(step, "tag"))
		local attr = str(field(step, "attribute", "attr"))
		local value = field(step, "value", "attrValue")
		if tag == "GymStation" and not d then
			d = Data.GYM
		elseif (tag == "SalonChair") and not d then
			d = Data.SALON
		elseif tag == "ShopCounter" and not d then
			d = SHOP_DEST[tostring(value or "")] or nil
		elseif tag == "Destination" and not d and type(value) == "string" then
			d = value
		elseif tag and TAG_DEST[tag] and not d then
			d = TAG_DEST[tag]
		end
		return { tag = tag, attr = attr, value = value, name = d }
	elseif kind == "gym" then
		return { name = str(field(step, "destination")) or Data.GYM }
	elseif kind == "buy" then
		local itemId = field(step, "itemId", "item", "id")
		local cat = str(field(step, "category"))
		local d = str(field(step, "destination"))
		if not d and itemId ~= nil then
			local item = Data.item(itemId)
			d = item.nearDest or (item.shop and SHOP_DEST[item.shop]) or nil
		elseif not d and (cat == "hair" or cat == "outfit") then
			d = Data.SALON
		end
		return d and { name = d } or nil
	elseif kind == "bowling" then
		return { name = str(field(step, "destination")) or "광안 락볼링클럽 (볼링장)" }
	elseif kind == "stat" then
		local stat = str(field(step, "stat", "id")) or ""
		if stat == "strength" or stat == "stamina" then
			return { name = Data.GYM }
		elseif stat == "appearance" then
			return { name = Data.SALON }
		end
	end
	local d = destOf(step)
	return d and { name = d } or nil
end

-- Everything the UI shows about an active quest's current step. The server's progress view
-- (GwangalliGameplayShared: { step, steps, count, need, carrying, target, text, type }) wins; the
-- quest definition fills the gaps (older / partial payloads).
--   { index, total, text, count, need, carrying, target = DestinationName?, where = stepTarget(), kind }
function Data.progressInfo(quest: any, p: any): any
	local steps = if type(quest) == "table" and type(quest.steps) == "table" then quest.steps else {}
	local index, count, raw = Data.progress(p, quest)
	local total = tonumber(type(raw) == "table" and raw.steps) or #steps
	local step = steps[math.clamp(index, 1, math.max(1, #steps))]
	local need = tonumber(type(raw) == "table" and raw.need) or nil
	if not need and type(step) == "table" then
		local k = step.type
		need = if k == "gym" then (tonumber(step.reps) or 1) elseif k == "interact" then (tonumber(step.count) or 1) elseif k == "deliver" then 2 else 1
	end
	need = math.max(1, need or 1)
	local carrying = type(raw) == "table" and raw.carrying == true
	local text = type(raw) == "table" and str(raw.text) or nil
	if not text then
		text = if step then Data.stepText(step, count) else nil
	end
	local kind = (type(raw) == "table" and str(raw.type)) or (type(step) == "table" and str(step.type)) or nil
	if text and kind ~= "deliver" and need > 1 and not string.find(text, "%(%d+/%d+%)") then
		text ..= string.format(" (%s/%s)", Data.int(math.min(count, need)), Data.int(need))
	end
	if kind == "deliver" and type(step) == "table" then
		local to = str(field(step, "to", "dropoff"))
		local from = str(field(step, "from", "pickup"))
		if carrying and to then
			text = "🛵 배달 중 → " .. to
		elseif from then
			text = "픽업하러 가기 → " .. from
		end
	end
	local where = if step then Data.stepTarget(step, count, raw) else nil
	local target = type(raw) == "table" and str(raw.target) or nil
	if target then
		where = { name = target, tag = where and where.tag, attr = where and where.attr, value = where and where.value }
	end
	return {
		index = index,
		total = total,
		text = text or (if type(quest) == "table" and quest.desc ~= "" then quest.desc else "진행 중"),
		count = count,
		need = need,
		carrying = carrying,
		target = where and where.name or nil,
		where = where,
		kind = kind,
	}
end

-- Message threads ---------------------------------------------------------------------------------------------
local function isMine(m: any): boolean
	if type(m) ~= "table" then
		return false
	end
	if m.me == true or m.mine == true or m.outgoing == true or m.fromPlayer == true or m.player == true then
		return true
	end
	local from = field(m, "from", "sender", "who", "side", "dir")
	return from == "me" or from == "player" or from == "you" or from == "right" or from == "out" or from == "self"
end

local function normMsgs(list: any): { any }
	local out = {}
	if type(list) ~= "table" then
		return out
	end
	for _, m in list do
		if type(m) == "string" then
			table.insert(out, { me = false, sys = false, text = m, t = nil, clock = nil })
		elseif type(m) == "table" then
			local text = str(field(m, "text", "body", "msg", "message", "content")) or str(m[2]) or str(m[1])
			if text then
				local t = field(m, "t", "time", "ts", "timestamp", "at")
				local clock = field(m, "clock", "gameClock")
				local from = field(m, "from", "sender", "who")
				table.insert(out, {
					me = isMine(m),
					sys = from == "system" or m.system == true,
					text = text,
					t = if type(t) == "number" then t else nil,
					clock = if type(clock) == "number" and clock >= 0 and clock <= 24.01 then clock else nil,
				})
			end
		end
	end
	return out
end

local function normChoices(c: any): { any }
	local out = {}
	if type(c) == "table" and type(c.choices) == "table" then
		c = c.choices
	end
	if type(c) ~= "table" then
		return out
	end
	for i, ch in c do
		if type(i) == "number" then
			if type(ch) == "string" then
				table.insert(out, { label = ch, value = i, index = i })
			elseif type(ch) == "table" then
				local label = str(field(ch, "text", "label", "title", "reply"))
				if label then
					local v = field(ch, "id", "key", "value")
					table.insert(out, { label = label, value = if v ~= nil then v else i, index = i })
				end
			end
		end
	end
	return out
end

local function normThread(key: any, t: any): any
	if type(t) ~= "table" then
		return nil
	end
	local id = str(field(t, "contact", "id", "contactId", "with")) or str(key)
	if not id then
		return nil
	end
	local list = field(t, "messages", "msgs", "log", "history", "lines", "chat")
	if list == nil and #t > 0 then
		list = t
	end
	local msgs = normMsgs(list)
	local unread = field(t, "unread", "unreadCount", "new")
	local n = 0
	if type(unread) == "number" then
		n = unread
	elseif unread == true then
		n = 1
	else
		for _, m in (type(list) == "table" and list or {}) do
			if type(m) == "table" and m.read == false and not isMine(m) then
				n += 1
			end
		end
	end
	local contact = Data.contact(id)
	local last = msgs[#msgs]
	local lastT = tonumber(field(t, "updated", "last", "lastT", "time")) or (last and last.t) or 0
	return {
		id = id, -- contact key the server used (sent back in PhoneAction payloads)
		name = contact.name,
		role = contact.role,
		glyph = contact.glyph,
		color = contact.color,
		msgs = msgs,
		unread = n,
		choices = normChoices(field(t, "choices", "options", "replies", "pending", "reply")),
		lastT = lastT,
		lastText = last and last.text or "",
	}
end

-- messages = { threads = ... } | threads ; threads = { [contact] = thread } | { thread }
function Data.threads(messages: any): { any }
	local threads = messages
	if type(messages) == "table" and type(messages.threads) == "table" then
		threads = messages.threads
	end
	local out = {}
	if type(threads) ~= "table" then
		return out
	end
	for k, t in threads do
		local th = normThread(if type(k) == "string" then k else nil, t)
		if th then
			table.insert(out, th)
		end
	end
	table.sort(out, function(a, b)
		if a.lastT ~= b.lastT then
			return a.lastT > b.lastT
		end
		return a.name < b.name
	end)
	return out
end

function Data.unreadTotal(messages: any): number
	local n = 0
	for _, th in Data.threads(messages) do
		n += th.unread
	end
	return n
end

-- Bubble time for a normalised message: the in-game clock when the server sent one.
function Data.msgTime(m: any): string
	if type(m) ~= "table" then
		return ""
	end
	if type(m.clock) == "number" then
		return UI.korClock(m.clock)
	end
	return Data.timeText(m.t)
end

-- Message time: in-game clock (0-24) or a server timestamp.
function Data.timeText(t: number?): string
	if type(t) ~= "number" then
		return ""
	end
	if t >= 0 and t <= 24.001 then
		return UI.korClock(t)
	end
	if t > 1e8 then
		local now = workspace:GetServerTimeNow()
		local d = now - t
		if d < 60 then
			return "방금"
		elseif d < 3600 then
			return string.format("%d분 전", math.floor(d / 60))
		elseif d < 86400 then
			return string.format("%d시간 전", math.floor(d / 3600))
		end
		return string.format("%d일 전", math.floor(d / 86400))
	end
	return ""
end

return Data
