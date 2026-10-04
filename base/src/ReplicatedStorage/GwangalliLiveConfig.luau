-- GwangalliLiveConfig: the LIVE CONFIG contract (docs/LIVE_UPDATES.md). Values that can change while
-- the game runs, on every server at once, without a restart: prices, job pay, taxi fares, rent, club
-- prices, events (drone show / 불꽃축제 / happy hour / club theme night), announcements, NPC lines,
-- extra shop items and feature switches.
--
-- Shared by the server (ServerScriptService.GwangalliLiveOps applies + stores + broadcasts) and the
-- clients (StarterPlayerScripts.GwangalliLive mirrors prices into the client's data tables and shows
-- announcements; GwangalliAdmin is the owner-only panel). Pure data + pure functions; nothing is
-- created at require time and nothing yields.
--
-- READ A VALUE (any script, server or client):
--   local Live = require(ReplicatedStorage.GwangalliLiveConfig)
--   Live.get("taxi.baseFare")            -> configured value (override or default)
--   Live.enabled("taxi")                 -> feature switch features.<id> (true when unknown)
--   Live.npcLine("club_md")              -> today's extra line for that NPC, or nil
--   Live.announcements()                 -> active announcements { {id, text, style, from?, to?, banner?} }
--   Live.happyHour()                     -> true while the happy hour window is active
--   Live.version()                       -> config version number (0 = defaults)
--   Live.onChanged(function(version) end) -> RBXScriptConnection (snapshot replaced)
-- Most values need NO reading code at all: the applier writes them straight into the game's own data
-- tables (GwangalliGameplayShared.TAXI / CLUB / LISTINGS / JOBS / ITEMS, ClubShared.Menu,
-- GwangalliConfig.DroneShow) on each peer, so code that reads those tables at use time is live.
--
-- DOCUMENT (DataStore "GwangalliLiveConfig_v1" key "current"; Open Cloud writes the same JSON):
--   { schema = 1, version = n, updatedAt = unix, updatedBy = userId (0 = Open Cloud), note = "",
--     values = { ["taxi.baseFare"] = 5200, ... }       -- overrides only; missing = default
--     announcements = { {id, text, style, from?, to?, banner?} },
--     npcLines = { [npcId] = "text" }, itemPrices = { [itemId] = won },
--     catalog = { {id = "live_...", name, price, phone? | shop? | nearDest?, desc?, effect, dailyStatLimit?} },
--     admins = { userId, ... } }                        -- extra admins (owner-only to change)
-- MESSAGE (MessagingService topic "GwangalliLiveConfig", JSON string <= 1 kB):
--   { t = "cfg", v = version, by = userId (0 = Open Cloud), src = "server"|"opencloud", d? = doc }
--   Servers treat it as a "new version exists" signal and re-read the DataStore (the source of truth);
--   the inline doc `d` is only used when the DataStore is unavailable (Studio / tests).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LC = {}

LC.SCHEMA = 1
LC.TOPIC = "GwangalliLiveConfig"
LC.DATASTORE = "GwangalliLiveConfig_v1"
LC.KEY_CURRENT = "current"
LC.KEY_HISTORY = "history"
LC.HISTORY_MAX = 20
LC.FOLDER = "GwangalliLive" -- ReplicatedStorage: snapshot attributes, Doc (StringValue), remotes
LC.DOC_VALUE = "Doc" -- StringValue: JSON of the public document
LC.REMOTE_CHANGED = "Changed" -- RemoteEvent server -> clients {v, keys, announce?, happy?}
LC.REMOTE_ADMIN = "Admin" -- RemoteFunction client -> server (admins only; re-checked every call)
LC.API_NAME = "GwangalliLiveOpsAPI" -- ServerStorage BindableFunction (server scripts)
LC.CHANGED_NAME = "GwangalliLiveOpsChanged" -- ServerStorage BindableEvent (version, keys)
LC.ADMIN_ATTR = "GwangalliAdmin" -- Player attribute: UI hint only, the server re-checks
LC.MESSAGE_MAX = 1000 -- bytes; MessagingService rejects messages over 1 kB
LC.DOC_MAX = 60000 -- bytes of JSON
LC.POLL_SECONDS = 60 -- servers re-read the DataStore this often (a missed message still converges)

-- Extra admin UserIds baked into the place. The game's owner (user game) or the owning group's
-- rank >= 254 are always admins; the owner can add more live (document field `admins`).
LC.ADMINS = {} :: { number }

---------------------------------------------------------------------------------------------------
-- Schema
---------------------------------------------------------------------------------------------------
-- field = { key, group, label, type, default, min?, max?, step?, unit?, options?, maxLen?,
--           maxItems?, bind? = {root, k1, k2, ...}, happy? (x happy-hour multiplier), serverOnly?, hint? }
-- types: int | number | bool | string | enum | clock (0-24) | clocklist ({clock...})
-- bind roots: "G" = ReplicatedStorage.GwangalliGameplayShared, "Club" = ReplicatedStorage.ClubShared,
--             "Config" = ReplicatedStorage.GwangalliConfig, "WS" = a Workspace attribute (server only).
--             A path element {id = "x"} picks the array entry whose .id == "x".
-- Bound fields: when not overridden the game's own value is used (the `default` below documents it;
-- tools/liveops/test_liveops.luau checks the two stay equal).

LC.GROUPS = {
	{ id = "price", label = "가격", icon = "💰" },
	{ id = "jobs", label = "알바", icon = "💼" },
	{ id = "events", label = "이벤트", icon = "🎆" },
	{ id = "world", label = "월드·기능", icon = "🌏" },
}

local FIELDS: { any } = {}
local BY_KEY: { [string]: any } = {}
local function field(spec: any)
	table.insert(FIELDS, spec)
	BY_KEY[spec.key] = spec
end

-- 가격 -------------------------------------------------------------------------------------------
field({ key = "taxi.baseFare", group = "price", label = "택시 기본요금", type = "int", min = 0, max = 100000, step = 100, unit = "원", default = 4800, bind = { "G", "TAXI", "baseFare" } })
field({ key = "taxi.perStud", group = "price", label = "택시 거리요금 (1스터드당)", type = "number", min = 0, max = 20, step = 0.1, unit = "원", default = 1.2, bind = { "G", "TAXI", "perStud" } })
field({ key = "taxi.maxFare", group = "price", label = "택시 최대요금", type = "int", min = 1000, max = 1000000, step = 1000, unit = "원", default = 30000, bind = { "G", "TAXI", "maxFare" } })
field({ key = "taxi.nightSurcharge", group = "price", label = "택시 심야 할증", type = "number", min = 0, max = 1, step = 0.05, unit = "", default = 0.2, bind = { "G", "TAXI", "nightSurcharge" }, hint = "0.2 = 20% 할증" })
field({ key = "club.cover", group = "price", label = "클럽 입장료", type = "int", min = 0, max = 5000000, step = 1000, unit = "원", default = 20000, bind = { "G", "CLUB", "cover" }, happy = true })
field({ key = "club.vipTable", group = "price", label = "클럽 VIP 테이블", type = "int", min = 0, max = 50000000, step = 10000, unit = "원", default = 300000, bind = { "G", "CLUB", "vipTable" }, happy = true })
field({ key = "club.entryAppearance", group = "price", label = "클럽 무료입장 외모지수", type = "int", min = 0, max = 100, step = 1, unit = "", default = 30, bind = { "G", "CLUB", "entryAppearance" } })
field({ key = "club.bottle.champagne", group = "price", label = "샴페인 1병", type = "int", min = 0, max = 50000000, step = 10000, unit = "원", default = 150000, bind = { "Club", "Menu", { id = "champagne" }, "price" }, happy = true })
field({ key = "club.bottle.vip", group = "price", label = "VIP 보틀 퍼레이드", type = "int", min = 0, max = 50000000, step = 10000, unit = "원", default = 300000, bind = { "Club", "Menu", { id = "vip" }, "price" }, happy = true })
field({ key = "club.bottle.birthday", group = "price", label = "생일 축하 보틀", type = "int", min = 0, max = 50000000, step = 10000, unit = "원", default = 250000, bind = { "Club", "Menu", { id = "birthday" }, "price" }, happy = true })
field({ key = "rent.goshiwon", group = "price", label = "고시원 하루 월세", type = "int", min = 0, max = 10000000, step = 500, unit = "원", default = 6000, bind = { "G", "LISTINGS", "goshiwon", "rentPerDay" } })
field({ key = "rent.oneroom", group = "price", label = "원룸 하루 월세", type = "int", min = 0, max = 10000000, step = 500, unit = "원", default = 14000, bind = { "G", "LISTINGS", "oneroom", "rentPerDay" } })
field({ key = "rent.officetel", group = "price", label = "오피스텔 하루 월세", type = "int", min = 0, max = 10000000, step = 500, unit = "원", default = 30000, bind = { "G", "LISTINGS", "officetel", "rentPerDay" } })
field({ key = "home.xi_apt.price", group = "price", label = "광안자이 매매가", type = "int", min = 0, max = 10000000000, step = 100000, unit = "원", default = 12000000, bind = { "G", "LISTINGS", "xi_apt", "price" } })
field({ key = "home.aqua_ph.price", group = "price", label = "펜트하우스 매매가", type = "int", min = 0, max = 10000000000, step = 100000, unit = "원", default = 48000000, bind = { "G", "LISTINGS", "aqua_ph", "price" } })
field({ key = "home.groceries", group = "price", label = "장보기 (집밥 5끼)", type = "int", min = 0, max = 1000000, step = 500, unit = "원", default = 18000, bind = { "G", "HOME_FOOD", "groceries", "price" } })

-- 알바 -------------------------------------------------------------------------------------------
LC.JOBS = {
	{ id = "gs25", label = "편의점 알바" },
	{ id = "starbucks", label = "카페 바리스타" },
	{ id = "rider", label = "배달 라이더" },
	{ id = "hoe", label = "횟집 서빙" },
	{ id = "lifeguard", label = "해수욕장 안전요원" },
	{ id = "taxi_driver", label = "택시 기사" },
}
field({ key = "jobs.payMultiplier", group = "jobs", label = "전체 알바비 배율", type = "number", min = 0.1, max = 5, step = 0.1, unit = "배", default = 1, hint = "2 = 알바비 2배 이벤트" })
for _, j in LC.JOBS do
	field({ key = "jobs." .. j.id .. ".payMultiplier", group = "jobs", label = j.label .. " 시급 배율", type = "number", min = 0.1, max = 5, step = 0.1, unit = "배", default = 1 })
end
field({ key = "jobs.xpMultiplier", group = "jobs", label = "알바 경험치 배율", type = "number", min = 0.5, max = 5, step = 0.5, unit = "배", default = 1 })

-- 이벤트 -----------------------------------------------------------------------------------------
LC.THEMES = { "none", "hiphop", "edm", "kpop", "retro", "white", "neon" }
LC.THEME_LABELS = { none = "없음", hiphop = "힙합 나이트", edm = "EDM 나이트", kpop = "K-POP 나이트", retro = "레트로 나이트", white = "화이트 파티", neon = "네온 파티" }
field({ key = "events.droneShow.enabled", group = "events", label = "드론라이트쇼 자동 시작", type = "bool", default = true, bind = { "Config", "DroneShow", "Enabled" } })
field({ key = "events.droneShow.times", group = "events", label = "드론쇼 시각 (게임 시계)", type = "clocklist", maxItems = 6, default = { 20, 23.5 }, bind = { "Config", "DroneShow", "Times" } })
field({ key = "events.droneShow.startAt", group = "events", label = "드론쇼 수동 시작 (유닉스 시각)", type = "int", min = 0, max = 2 ^ 40, step = 1, unit = "", default = 0, hidden = true, hint = "관리자 패널의 '지금 시작' 버튼이 씀: 모든 서버가 이 시각에 시작" })
field({ key = "events.fireworks.enabled", group = "events", label = "불꽃축제", type = "bool", default = false, hint = "켜면 정해진 시각에 드론쇼+불꽃 연출이 시작돼요" })
field({ key = "events.fireworks.times", group = "events", label = "불꽃축제 시각 (게임 시계)", type = "clocklist", maxItems = 4, default = { 21 } })
field({ key = "events.fireworks.title", group = "events", label = "불꽃축제 이름", type = "string", maxLen = 40, default = "부산불꽃축제" })
field({ key = "events.fireworks.startAt", group = "events", label = "불꽃축제 수동 시작 (유닉스 시각)", type = "int", min = 0, max = 2 ^ 40, step = 1, unit = "", default = 0, hidden = true })
field({ key = "events.club.themeNight", group = "events", label = "클럽 테마 나이트", type = "enum", options = LC.THEMES, default = "none" })
field({ key = "events.happyHour.enabled", group = "events", label = "해피아워", type = "bool", default = false, hint = "시간 안에는 클럽 가격이 배율만큼 내려가요" })
field({ key = "events.happyHour.from", group = "events", label = "해피아워 시작 (게임 시계)", type = "clock", default = 18 })
field({ key = "events.happyHour.to", group = "events", label = "해피아워 끝 (게임 시계)", type = "clock", default = 20 })
field({ key = "events.happyHour.multiplier", group = "events", label = "해피아워 가격 배율", type = "number", min = 0.1, max = 1, step = 0.05, unit = "배", default = 0.7, hint = "0.7 = 30% 할인" })

-- 월드 / 기능 ------------------------------------------------------------------------------------
field({ key = "world.dayLengthMinutes", group = "world", label = "하루 길이 (실제 분)", type = "number", min = 2, max = 240, step = 1, unit = "분", default = 24, bind = { "WS", "GwangalliDayLengthMinutes" }, serverOnly = true })
field({ key = "world.clockPaused", group = "world", label = "시계 멈춤", type = "bool", default = false, bind = { "WS", "GwangalliClockPaused" }, serverOnly = true })
LC.FEATURES = {
	{ id = "taxi", label = "택시" },
	{ id = "club", label = "클럽" },
	{ id = "bowling", label = "볼링" },
	{ id = "jobs", label = "알바" },
	{ id = "housing", label = "부동산·집" },
	{ id = "shops", label = "상점" },
	{ id = "bank", label = "은행·송금" },
	{ id = "npcSocial", label = "NPC 친구" },
}
for _, f in LC.FEATURES do
	field({ key = "features." .. f.id, group = "world", label = f.label .. " 기능", type = "bool", default = true })
end

LC.FIELDS = FIELDS
LC.BY_KEY = BY_KEY

LC.ANNOUNCE_STYLES = {
	info = { label = "공지", icon = "📢", kind = "info" },
	event = { label = "이벤트", icon = "🎆", kind = "stat" },
	club = { label = "클럽", icon = "🎶", kind = "club" },
	warn = { label = "주의", icon = "⚠️", kind = "warn" },
	update = { label = "업데이트", icon = "🔧", kind = "warn" },
}
LC.ANNOUNCE_MAX = 10
LC.NPC_LINES_MAX = 40
LC.ITEM_PRICES_MAX = 150
LC.CATALOG_MAX = 20
LC.ADMINS_MAX = 20
LC.TEXT_MAX = 200
LC.STATS = { "appearance", "stamina", "happiness", "popularity", "strength" } -- G.STAT_ORDER
LC.BUFFS = { "protein", "energy", "sup" } -- G.BUFFS keys
LC.CATALOG_SHOPS = { "gym_store" } -- consumables only; phone = true (delivery) or nearDest also work

---------------------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------------------
local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end
LC.deepCopy = deepCopy

local function same(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		if type(a) == "number" and type(b) == "number" then
			return math.abs(a - b) < 1e-9
		end
		return false
	end
	for k, v in a do
		if not same(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end
LC.same = same

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isInt(v: any): boolean
	return isFinite(v) and math.floor(v) == v
end

local function isArray(t: any): boolean
	if type(t) ~= "table" then
		return false
	end
	local n = 0
	for k in t do
		if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
			return false
		end
		n += 1
	end
	return n == #t
end

local function count(t: any): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Cuts `s` to at most maxBytes without splitting a UTF-8 character (Korean is 3 bytes a letter).
local function clip(s: string, maxBytes: number): string
	if #s <= maxBytes then
		return s
	end
	local cut = 0
	local ok = pcall(function()
		for p in utf8.codes(s) do
			if p - 1 > maxBytes then
				break
			end
			cut = p - 1 -- bytes before this character are whole characters
		end
	end)
	if not ok then
		return string.sub(s, 1, maxBytes) -- not UTF-8 anyway (validation rejects it)
	end
	return string.sub(s, 1, cut)
end
LC.clip = clip

-- A clean single- or multi-line text: valid UTF-8, no control characters except \n, trimmed.
local function cleanText(s: any, maxLen: number, allowNewline: boolean?): (string?, string?)
	if type(s) ~= "string" then
		return nil, "글자가 아니에요"
	end
	if utf8.len(s) == nil then
		return nil, "잘못된 글자(UTF-8)"
	end
	if allowNewline then
		s = string.gsub(s, "\r\n?", "\n") -- Windows / old Mac line ends
	end
	local bad = if allowNewline then "[%z\1-\9\11-\31\127]" else "[%z\1-\31\127]"
	if string.find(s, bad) then
		return nil, "제어 문자가 들어 있어요"
	end
	s = string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")
	if #s == 0 then
		return nil, "비어 있어요"
	end
	if #s > maxLen then
		return nil, string.format("너무 길어요 (한글 %d자 · 영문 %d자까지)", maxLen // 3, maxLen)
	end
	return s, nil
end
LC.cleanText = cleanText

local function idOk(s: any, maxLen: number, pattern: string?): boolean
	return type(s) == "string" and #s >= 1 and #s <= maxLen and string.match(s, pattern or "^[%w_]+$") ~= nil
end

local function round(v: number, stepv: number): number
	return math.floor(v / stepv + 0.5) * stepv
end
LC.round = round

function LC.attrName(key: string): string
	return "L_" .. (string.gsub(key, "%.", "_"))
end

function LC.jsonEncode(v: any): (string?, string?)
	local ok, res = pcall(function()
		return HttpService:JSONEncode(v)
	end)
	if ok and type(res) == "string" then
		return res, nil
	end
	return nil, tostring(res)
end

function LC.jsonDecode(s: any): any
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local ok, res = pcall(function()
		return HttpService:JSONDecode(s)
	end)
	return if ok then res else nil
end

---------------------------------------------------------------------------------------------------
-- Value validation
---------------------------------------------------------------------------------------------------
-- Returns (cleanValue, nil) or (nil, "reason").
function LC.checkValue(f: any, v: any): (any, string?)
	local t = f.type
	if t == "int" then
		if not isInt(v) then
			return nil, "정수가 아니에요"
		end
	elseif t == "number" then
		if not isFinite(v) then
			return nil, "숫자가 아니에요"
		end
	elseif t == "bool" then
		if type(v) ~= "boolean" then
			return nil, "켜짐/꺼짐(true/false)이 아니에요"
		end
		return v, nil
	elseif t == "string" then
		local s, why = cleanText(v, f.maxLen or LC.TEXT_MAX, false)
		if not s then
			return nil, why
		end
		return s, nil
	elseif t == "enum" then
		if type(v) ~= "string" or not table.find(f.options, v) then
			return nil, "선택지에 없어요 (" .. table.concat(f.options, "/") .. ")"
		end
		return v, nil
	elseif t == "clock" then
		if not isFinite(v) or v < 0 or v >= 24 then
			return nil, "시각은 0 이상 24 미만이어야 해요"
		end
		return v, nil
	elseif t == "clocklist" then
		if not isArray(v) then
			return nil, "시각 목록이 아니에요"
		end
		if #v > (f.maxItems or 6) then
			return nil, string.format("시각은 %d개까지예요", f.maxItems or 6)
		end
		local out = {}
		for _, c in v do
			if not isFinite(c) or c < 0 or c >= 24 then
				return nil, "시각은 0 이상 24 미만이어야 해요"
			end
			local dup = false
			for _, o in out do
				if math.abs(o - c) < 1e-6 then
					dup = true
				end
			end
			if not dup then
				table.insert(out, c)
			end
		end
		table.sort(out)
		return out, nil
	else
		return nil, "알 수 없는 형식"
	end
	-- int / number range
	if f.min and v < f.min or f.max and v > f.max then
		return nil, string.format("범위 밖 (%s ~ %s)", tostring(f.min), tostring(f.max))
	end
	return v, nil
end

local function checkEffect(e: any, errs: { string }, where: string): any
	if type(e) ~= "table" then
		table.insert(errs, where .. ": effect가 없어요")
		return nil
	end
	local out: any = {}
	if e.stats ~= nil then
		if type(e.stats) ~= "table" or isArray(e.stats) and #e.stats > 0 then
			table.insert(errs, where .. ".stats: {능력치 = 변화량} 형식이어야 해요")
			return nil
		end
		out.stats = {}
		local n = 0
		for k, d in e.stats do
			if not table.find(LC.STATS, k) then
				table.insert(errs, where .. ".stats: 모르는 능력치 " .. tostring(k))
				return nil
			end
			if not isFinite(d) or d < -5 or d > 5 or d == 0 then
				table.insert(errs, where .. ".stats." .. k .. ": -5 ~ 5 (0 제외)")
				return nil
			end
			out.stats[k] = d
			n += 1
		end
		if n == 0 then
			out.stats = nil
		end
	end
	if e.buff ~= nil then
		if not table.find(LC.BUFFS, e.buff) then
			table.insert(errs, where .. ".buff: 모르는 버프 " .. tostring(e.buff))
			return nil
		end
		out.buff = e.buff
		if e.buffSeconds ~= nil then
			if not isInt(e.buffSeconds) or e.buffSeconds < 10 or e.buffSeconds > 3600 then
				table.insert(errs, where .. ".buffSeconds: 10 ~ 3600 정수")
				return nil
			end
			out.buffSeconds = e.buffSeconds
		end
		if e.buffSets ~= nil then
			if not isInt(e.buffSets) or e.buffSets < 1 or e.buffSets > 10 then
				table.insert(errs, where .. ".buffSets: 1 ~ 10 정수")
				return nil
			end
			out.buffSets = e.buffSets
		end
		if out.buffSeconds == nil and out.buffSets == nil then
			out.buffSeconds = 120
		end
	end
	if out.stats == nil and out.buff == nil then
		table.insert(errs, where .. ": 효과(stats 또는 buff)가 하나는 있어야 해요")
		return nil
	end
	return out
end

local function checkCatalogItem(it: any, errs: { string }, where: string, strict: boolean): any
	if type(it) ~= "table" then
		table.insert(errs, where .. ": 항목이 표가 아니에요")
		return nil
	end
	local known = { id = true, name = true, price = true, phone = true, shop = true, nearDest = true, desc = true, icon = true, effect = true, dailyStatLimit = true, kind = true }
	if strict then
		for k in it do
			if not known[k] then
				table.insert(errs, where .. ": 모르는 칸 " .. tostring(k))
				return nil
			end
		end
	end
	if it.kind ~= nil and it.kind ~= "consumable" then
		table.insert(errs, where .. ".kind: consumable 만 돼요")
		return nil
	end
	if not idOk(it.id, 40, "^live_[%w_]+$") then
		table.insert(errs, where .. ".id: live_로 시작하는 영문/숫자/_ (40자 이하)")
		return nil
	end
	local name, why = cleanText(it.name, 40, false)
	if not name then
		table.insert(errs, where .. ".name: " .. tostring(why))
		return nil
	end
	if not isInt(it.price) or it.price < 0 or it.price > 10000000 then
		table.insert(errs, where .. ".price: 0 ~ 10,000,000 정수")
		return nil
	end
	local out: any = { id = it.id, name = name, price = it.price, kind = "consumable" }
	local places = 0
	if it.phone ~= nil then
		if type(it.phone) ~= "boolean" then
			table.insert(errs, where .. ".phone: true/false")
			return nil
		end
		if it.phone then
			out.phone = true
			places += 1
		end
	end
	if it.shop ~= nil then
		if not table.find(LC.CATALOG_SHOPS, it.shop) then
			table.insert(errs, where .. ".shop: " .. table.concat(LC.CATALOG_SHOPS, "/") .. " 중 하나")
			return nil
		end
		out.shop = it.shop
		places += 1
	end
	if it.nearDest ~= nil then
		local d, why2 = cleanText(it.nearDest, 60, false)
		if not d then
			table.insert(errs, where .. ".nearDest: " .. tostring(why2))
			return nil
		end
		out.nearDest = d
		places += 1
	end
	if places ~= 1 then
		table.insert(errs, where .. ": 파는 곳은 phone / shop / nearDest 중 딱 하나")
		return nil
	end
	if it.desc ~= nil then
		local d, why3 = cleanText(it.desc, 80, false)
		if not d then
			table.insert(errs, where .. ".desc: " .. tostring(why3))
			return nil
		end
		out.desc = d
	end
	if it.icon ~= nil then
		local ic, why4 = cleanText(it.icon, 16, false)
		if not ic then
			table.insert(errs, where .. ".icon: " .. tostring(why4))
			return nil
		end
		out.icon = ic
	end
	local e = checkEffect(it.effect, errs, where .. ".effect")
	if not e then
		return nil
	end
	out.effect = e
	if it.dailyStatLimit ~= nil then
		if not isInt(it.dailyStatLimit) or it.dailyStatLimit < 1 or it.dailyStatLimit > 10 then
			table.insert(errs, where .. ".dailyStatLimit: 1 ~ 10 정수")
			return nil
		end
		out.dailyStatLimit = it.dailyStatLimit
	end
	if out.desc == nil then
		out.desc = "기간 한정 상품"
	end
	return out
end

-- Validates a whole document. strict = unknown keys are errors (tools, admin ops); otherwise they
-- are dropped with a note (a newer tool / place version during a rolling update).
-- Returns (cleanDoc, errors, notes). cleanDoc is nil when there is any error: updates are atomic.
function LC.validate(doc: any, opts: any?): (any?, { string }, { string })
	local strict = opts and opts.strict == true
	local errs: { string } = {}
	local notes: { string } = {}
	if type(doc) ~= "table" then
		return nil, { "문서가 표(JSON 객체)가 아니에요" }, notes
	end
	local known = { schema = true, version = true, updatedAt = true, updatedBy = true, note = true, values = true, announcements = true, npcLines = true, itemPrices = true, catalog = true, admins = true }
	for k in doc do
		if not known[k] then
			if strict then
				table.insert(errs, "모르는 칸: " .. tostring(k))
			else
				table.insert(notes, "무시한 칸: " .. tostring(k))
			end
		end
	end
	local out: any = LC.emptyDoc()
	-- header
	if doc.schema ~= nil then
		if not isInt(doc.schema) or doc.schema < 1 or doc.schema > 1000 then
			table.insert(errs, "schema: 1 이상의 정수")
		else
			out.schema = doc.schema
		end
	end
	if doc.version ~= nil then
		if not isInt(doc.version) or doc.version < 0 or doc.version > 2 ^ 31 then
			table.insert(errs, "version: 0 이상의 정수")
		else
			out.version = doc.version
		end
	end
	if doc.updatedAt ~= nil then
		if not isFinite(doc.updatedAt) or doc.updatedAt < 0 then
			table.insert(errs, "updatedAt: 숫자(유닉스 시간)")
		else
			out.updatedAt = doc.updatedAt
		end
	end
	if doc.updatedBy ~= nil then
		if not isInt(doc.updatedBy) or doc.updatedBy < 0 then
			table.insert(errs, "updatedBy: 0 이상의 정수 (UserId, 0 = Open Cloud)")
		else
			out.updatedBy = doc.updatedBy
		end
	end
	if doc.note ~= nil and doc.note ~= "" then
		-- metadata: line breaks / tabs become spaces and long notes are clipped instead of rejected
		local raw = if type(doc.note) == "string" then clip((string.gsub(doc.note, "[\t\r\n]+", " ")), 120) else doc.note
		local n, why = cleanText(raw, 120, false)
		if not n then
			table.insert(errs, "note: " .. tostring(why))
		else
			out.note = n
		end
	end
	-- values
	if doc.values ~= nil then
		if type(doc.values) ~= "table" or (isArray(doc.values) and #doc.values > 0) then
			table.insert(errs, "values: {키 = 값} 형식이어야 해요")
		else
			for k, v in doc.values do
				local f = type(k) == "string" and BY_KEY[k]
				if not f then
					if strict then
						table.insert(errs, "values: 모르는 키 " .. tostring(k))
					else
						table.insert(notes, "무시한 키: " .. tostring(k))
					end
				else
					local cv, why = LC.checkValue(f, v)
					if cv == nil then
						table.insert(errs, string.format("values.%s: %s (받은 값: %s)", k, tostring(why), tostring(v)))
					elseif not same(cv, f.default) or f.bind then
						out.values[k] = cv
					end
				end
			end
		end
	end
	-- announcements
	if doc.announcements ~= nil then
		if not isArray(doc.announcements) then
			table.insert(errs, "announcements: 목록이어야 해요")
		elseif #doc.announcements > LC.ANNOUNCE_MAX then
			table.insert(errs, string.format("announcements: %d개까지예요", LC.ANNOUNCE_MAX))
		else
			local seen = {}
			for i, a in doc.announcements do
				local w = "announcements[" .. i .. "]"
				if type(a) ~= "table" then
					table.insert(errs, w .. ": 표가 아니에요")
					continue
				end
				if not idOk(a.id, 24, "^[%w_%-]+$") or seen[a.id] then
					table.insert(errs, w .. ".id: 영문/숫자/_/- 24자 이하, 중복 없이")
					continue
				end
				seen[a.id] = true
				local text, why = cleanText(a.text, LC.TEXT_MAX, true)
				if not text then
					table.insert(errs, w .. ".text: " .. tostring(why))
					continue
				end
				local style = a.style or "info"
				if type(style) ~= "string" or not LC.ANNOUNCE_STYLES[style] then
					table.insert(errs, w .. ".style: info/event/club/warn/update")
					continue
				end
				local rec: any = { id = a.id, text = text, style = style }
				if a.from ~= nil then
					if not isFinite(a.from) or a.from < 0 then
						table.insert(errs, w .. ".from: 유닉스 시간")
						continue
					end
					rec.from = a.from
				end
				if a.to ~= nil then
					if not isFinite(a.to) or a.to < 0 or (rec.from and a.to <= rec.from) then
						table.insert(errs, w .. ".to: from보다 뒤의 유닉스 시간")
						continue
					end
					rec.to = a.to
				end
				if a.banner ~= nil then
					if type(a.banner) ~= "boolean" then
						table.insert(errs, w .. ".banner: true/false")
						continue
					end
					rec.banner = a.banner or nil
				end
				table.insert(out.announcements, rec)
			end
		end
	end
	-- npcLines
	if doc.npcLines ~= nil then
		if type(doc.npcLines) ~= "table" or (isArray(doc.npcLines) and #doc.npcLines > 0) then
			table.insert(errs, "npcLines: {NPC id = 대사} 형식이어야 해요")
		elseif count(doc.npcLines) > LC.NPC_LINES_MAX then
			table.insert(errs, string.format("npcLines: %d개까지예요", LC.NPC_LINES_MAX))
		else
			for k, v in doc.npcLines do
				if not idOk(k, 40) then
					table.insert(errs, "npcLines: NPC id는 영문/숫자/_ 40자 이하 (" .. tostring(k) .. ")")
				else
					local t, why = cleanText(v, LC.TEXT_MAX, true)
					if not t then
						table.insert(errs, "npcLines." .. k .. ": " .. tostring(why))
					else
						out.npcLines[k] = t
					end
				end
			end
		end
	end
	-- itemPrices
	if doc.itemPrices ~= nil then
		if type(doc.itemPrices) ~= "table" or (isArray(doc.itemPrices) and #doc.itemPrices > 0) then
			table.insert(errs, "itemPrices: {상품 id = 가격} 형식이어야 해요")
		elseif count(doc.itemPrices) > LC.ITEM_PRICES_MAX then
			table.insert(errs, string.format("itemPrices: %d개까지예요", LC.ITEM_PRICES_MAX))
		else
			for k, v in doc.itemPrices do
				if not idOk(k, 40) then
					table.insert(errs, "itemPrices: 상품 id는 영문/숫자/_ 40자 이하 (" .. tostring(k) .. ")")
				elseif not isInt(v) or v < 0 or v > 100000000 then
					table.insert(errs, string.format("itemPrices.%s: 0 ~ 100,000,000 정수 (받은 값: %s)", k, tostring(v)))
				else
					out.itemPrices[k] = v
				end
			end
		end
	end
	-- catalog
	if doc.catalog ~= nil then
		if not isArray(doc.catalog) then
			table.insert(errs, "catalog: 목록이어야 해요")
		elseif #doc.catalog > LC.CATALOG_MAX then
			table.insert(errs, string.format("catalog: %d개까지예요", LC.CATALOG_MAX))
		else
			local seen = {}
			for i, it in doc.catalog do
				local c = checkCatalogItem(it, errs, "catalog[" .. i .. "]", strict)
				if c then
					if seen[c.id] then
						table.insert(errs, "catalog: 중복 id " .. c.id)
					else
						seen[c.id] = true
						table.insert(out.catalog, c)
					end
				end
			end
		end
	end
	-- admins
	if doc.admins ~= nil then
		if not isArray(doc.admins) then
			table.insert(errs, "admins: UserId 목록이어야 해요")
		elseif #doc.admins > LC.ADMINS_MAX then
			table.insert(errs, string.format("admins: %d명까지예요", LC.ADMINS_MAX))
		else
			for _, id in doc.admins do
				if not isInt(id) or id < 1 or id > 2 ^ 53 then
					table.insert(errs, "admins: UserId는 1 이상의 정수 (" .. tostring(id) .. ")")
				elseif not table.find(out.admins, id) then
					table.insert(out.admins, id)
				end
			end
		end
	end
	if #errs == 0 then
		local json = LC.jsonEncode(out)
		if json and #json > LC.DOC_MAX then
			table.insert(errs, string.format("문서가 너무 커요 (%d바이트 > %d)", #json, LC.DOC_MAX))
		end
	end
	if #errs > 0 then
		return nil, errs, notes
	end
	return out, errs, notes
end

function LC.emptyDoc(): any
	return { schema = LC.SCHEMA, version = 0, updatedAt = 0, updatedBy = 0, note = "", values = {}, announcements = {}, npcLines = {}, itemPrices = {}, catalog = {}, admins = {} }
end

-- The document minus admin-only data (sent to every client).
function LC.publicDoc(doc: any): any
	local p = deepCopy(doc)
	p.admins = nil
	return p
end

-- Configured value of `key` in `doc` (override or schema default).
function LC.valueIn(doc: any, key: string): any
	local f = BY_KEY[key]
	if not f then
		return nil
	end
	local v = doc and doc.values and doc.values[key]
	if v == nil then
		return deepCopy(f.default)
	end
	return v
end

function LC.inWindow(clock: number, from: number, to: number): boolean
	if from <= to then
		return clock >= from and clock < to
	end
	return clock >= from or clock < to
end

function LC.happyActiveAt(doc: any, clock: number?): boolean
	if not LC.valueIn(doc, "events.happyHour.enabled") or type(clock) ~= "number" then
		return false
	end
	return LC.inWindow(clock, LC.valueIn(doc, "events.happyHour.from"), LC.valueIn(doc, "events.happyHour.to"))
end

-- Active announcements at unix time `now`.
function LC.activeAnnouncements(doc: any, now: number): { any }
	local out = {}
	for _, a in (doc and doc.announcements) or {} do
		if (a.from == nil or now >= a.from) and (a.to == nil or now < a.to) then
			table.insert(out, a)
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------
-- Operations (admin panel / chat commands / server API). Each returns a NEW document (deep copy)
-- or (nil, reason). The caller validates the result with LC.validate(doc, {strict = true}).
---------------------------------------------------------------------------------------------------
local opSerial = 0
local function newId(now: number): string
	opSerial = (opSerial + 1) % 1000
	return string.format("a%d_%d", math.floor(now) % 100000000, opSerial)
end

function LC.applyOp(doc: any, op: string, a: any, b: any, now: number?): (any?, string?)
	local t = now or os.time()
	local d = deepCopy(doc)
	d.values = d.values or {}
	d.announcements = d.announcements or {}
	d.npcLines = d.npcLines or {}
	d.itemPrices = d.itemPrices or {}
	d.catalog = d.catalog or {}
	d.admins = d.admins or {}
	if op == "set" then
		local f = type(a) == "string" and BY_KEY[a]
		if not f then
			return nil, "모르는 설정: " .. tostring(a)
		end
		local v, why = LC.checkValue(f, b)
		if v == nil then
			return nil, f.label .. ": " .. tostring(why)
		end
		if same(v, f.default) and not f.bind then
			d.values[a] = nil
		else
			d.values[a] = v
		end
	elseif op == "reset" then
		if type(a) ~= "string" or not BY_KEY[a] then
			return nil, "모르는 설정: " .. tostring(a)
		end
		d.values[a] = nil
	elseif op == "resetAll" then
		d.values = {}
	elseif op == "announce" then
		local o = if type(a) == "table" then a else { text = a }
		local text, why = cleanText(o.text, LC.TEXT_MAX, true)
		if not text then
			return nil, "공지: " .. tostring(why)
		end
		local style = if type(o.style) == "string" and LC.ANNOUNCE_STYLES[o.style] then o.style else "info"
		local minutes = if isFinite(o.minutes) then math.clamp(o.minutes, 1, 60 * 24 * 30) else 60
		local rec: any = { id = newId(t), text = text, style = style, from = t, to = t + math.floor(minutes * 60) }
		if o.banner == true then
			rec.banner = true
		end
		-- drop expired, then the oldest when full
		local keep = {}
		for _, x in d.announcements do
			if x.to == nil or x.to > t then
				table.insert(keep, x)
			end
		end
		while #keep >= LC.ANNOUNCE_MAX do
			table.remove(keep, 1)
		end
		table.insert(keep, rec)
		d.announcements = keep
	elseif op == "unannounce" then
		local keep = {}
		local found = false
		for _, x in d.announcements do
			if x.id == a then
				found = true
			else
				table.insert(keep, x)
			end
		end
		if not found then
			return nil, "없는 공지예요"
		end
		d.announcements = keep
	elseif op == "npcLine" then
		if not idOk(a, 40) then
			return nil, "NPC id가 이상해요"
		end
		if b == nil or b == "" or b == false then
			d.npcLines[a] = nil
		else
			local text, why = cleanText(b, LC.TEXT_MAX, true)
			if not text then
				return nil, "대사: " .. tostring(why)
			end
			d.npcLines[a] = text
		end
	elseif op == "itemPrice" then
		if not idOk(a, 40) then
			return nil, "상품 id가 이상해요"
		end
		if b == nil or b == false then
			d.itemPrices[a] = nil
		elseif not isInt(b) or b < 0 or b > 100000000 then
			return nil, "가격은 0 ~ 100,000,000 정수"
		else
			d.itemPrices[a] = b
		end
	elseif op == "catalogAdd" then
		local errs = {}
		local c = checkCatalogItem(a, errs, "상품", true)
		if not c then
			return nil, errs[1]
		end
		local replaced = false
		for i, x in d.catalog do
			if x.id == c.id then
				d.catalog[i] = c
				replaced = true
			end
		end
		if not replaced then
			table.insert(d.catalog, c)
		end
	elseif op == "catalogRemove" then
		local keep = {}
		for _, x in d.catalog do
			if x.id ~= a then
				table.insert(keep, x)
			end
		end
		if #keep == #d.catalog then
			return nil, "없는 상품이에요"
		end
		d.catalog = keep
	elseif op == "admins" then
		if not isArray(a) then
			return nil, "UserId 목록이어야 해요"
		end
		d.admins = deepCopy(a)
	elseif op == "replace" then
		if type(a) ~= "table" then
			return nil, "문서가 아니에요"
		end
		local keep = { version = d.version, admins = d.admins }
		d = deepCopy(a)
		d.version = keep.version
		if d.admins == nil then
			d.admins = keep.admins
		end
	else
		return nil, "모르는 명령: " .. tostring(op)
	end
	return d, nil
end

-- Human-readable value ("5,200원", "×1.5", "20:00, 23:30", "켜짐").
local function commas(n: number): string
	local neg = n < 0
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if neg then "-" else "") .. out
end
LC.commas = commas

local function clockText(c: number): string
	local m = math.floor(c * 60 + 0.5)
	return string.format("%02d:%02d", (m // 60) % 24, m % 60)
end
LC.clockText = clockText

function LC.describe(key: string, v: any): string
	local f = BY_KEY[key]
	if not f then
		return tostring(v)
	end
	if v == nil then
		return "-"
	end
	local t = f.type
	if t == "bool" then
		return if v then "켜짐" else "꺼짐"
	elseif t == "clock" then
		return clockText(v)
	elseif t == "clocklist" then
		local parts = {}
		for _, c in v do
			table.insert(parts, clockText(c))
		end
		return if #parts == 0 then "없음" else table.concat(parts, ", ")
	elseif t == "enum" then
		return (f.key == "events.club.themeNight" and LC.THEME_LABELS[v]) or tostring(v)
	elseif t == "int" and f.unit == "원" then
		return commas(v) .. "원"
	elseif f.unit == "배" then
		return "×" .. (string.gsub(string.format("%.2f", v), "%.?0+$", ""))
	elseif t == "number" then
		return (string.gsub(string.format("%.2f", v), "%.?0+$", "")) .. (f.unit or "")
	end
	return tostring(v) .. (f.unit or "")
end

-- Parses admin text input for a field ("5200", "5,200원", "켜짐", "20:00, 23:30").
function LC.parseInput(key: string, s: any): (any, string?)
	local f = BY_KEY[key]
	if not f then
		return nil, "모르는 설정"
	end
	if type(s) ~= "string" then
		return LC.checkValue(f, s)
	end
	local t = f.type
	local function num(x: string): number?
		x = string.gsub(x, "[,%s원배×x%%]", "")
		return tonumber(x)
	end
	local function clock(x: string): number?
		local h, m = string.match(x, "^%s*(%d+)%s*:%s*(%d+)%s*$")
		if h then
			return tonumber(h) + tonumber(m) / 60
		end
		return tonumber((string.gsub(x, "%s", "")))
	end
	local v: any
	if t == "bool" then
		local l = string.lower(s)
		if l == "true" or l == "on" or s == "켜짐" or s == "켜기" or l == "1" then
			v = true
		elseif l == "false" or l == "off" or s == "꺼짐" or s == "끄기" or l == "0" then
			v = false
		else
			return nil, "켜짐/꺼짐으로 입력하세요"
		end
	elseif t == "int" or t == "number" then
		v = num(s)
		if v == nil then
			return nil, "숫자로 입력하세요"
		end
		if t == "int" then
			v = math.floor(v + 0.5)
		end
	elseif t == "clock" then
		v = clock(s)
		if v == nil then
			return nil, "20:00 처럼 입력하세요"
		end
	elseif t == "clocklist" then
		v = {}
		for part in string.gmatch(s, "[^,/]+") do
			local c = clock(part)
			if c == nil then
				return nil, "20:00, 23:30 처럼 입력하세요"
			end
			table.insert(v, c)
		end
	else
		v = s
	end
	return LC.checkValue(f, v)
end

---------------------------------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------------------------------
-- Parses a MessagingService payload (JSON string or table). Returns (msg, nil) or (nil, reason).
function LC.parseMessage(data: any): (any?, string?)
	local raw = data
	if type(data) == "string" then
		if #data > LC.MESSAGE_MAX then
			return nil, "메시지가 너무 커요"
		end
		raw = LC.jsonDecode(data)
		if raw == nil then
			return nil, "JSON이 아니에요"
		end
	end
	if type(raw) ~= "table" then
		return nil, "메시지 형식이 아니에요"
	end
	if raw.t ~= "cfg" then
		return nil, "모르는 메시지 종류"
	end
	if not isInt(raw.v) or raw.v < 1 or raw.v > 2 ^ 31 then
		return nil, "version이 이상해요"
	end
	local by = raw.by
	if by == nil then
		by = 0
	end
	if not isInt(by) or by < 0 or by > 2 ^ 53 then
		return nil, "by(UserId)가 이상해요"
	end
	local src = raw.src
	if src ~= nil and (type(src) ~= "string" or #src > 16) then
		return nil, "src가 이상해요"
	end
	if raw.d ~= nil and type(raw.d) ~= "table" then
		return nil, "d가 표가 아니에요"
	end
	return { t = "cfg", v = raw.v, by = by, src = src or "server", d = raw.d }, nil
end

-- Builds the JSON message for version `v`; the doc is inlined only when it fits.
function LC.buildMessage(doc: any, by: number, src: string?): string
	local withDoc = LC.jsonEncode({ t = "cfg", v = doc.version, by = by, src = src or "server", d = doc })
	if withDoc and #withDoc <= LC.MESSAGE_MAX then
		return withDoc
	end
	return (LC.jsonEncode({ t = "cfg", v = doc.version, by = by, src = src or "server" })) :: string
end

---------------------------------------------------------------------------------------------------
-- Applier: writes the document into the game's data tables on THIS peer, remembering the original
-- (baseline) values so a reset / rollback restores them exactly.
--   local ap = LC.newApplier({ G = gameplayShared, Club = clubShared, Config = config, WS = workspace }, "server")
--   local changed = ap:apply(doc, happyActive)     -- { "G.TAXI.baseFare", ... }
--   ap:baseline("taxi.baseFare")                    -- the game's own value
---------------------------------------------------------------------------------------------------
local Applier = {}
Applier.__index = Applier

function LC.newApplier(targets: any, peer: string): any
	return setmetatable({ targets = targets or {}, peer = peer or "server", base = {}, hasBase = {}, applied = {}, warned = {} }, Applier)
end

local function pathId(bind: { any }): string
	local parts = {}
	for _, k in bind do
		if type(k) == "table" then
			table.insert(parts, "[" .. tostring(k.id) .. "]")
		else
			table.insert(parts, tostring(k))
		end
	end
	return table.concat(parts, ".")
end
LC.pathId = pathId

-- Resolves a bind path to (container table, final key) on this peer, or nil.
function Applier:resolve(bind: { any }): (any, any)
	local root = bind[1]
	if root == "WS" then
		return nil, nil
	end
	local t = self.targets[root]
	for i = 2, #bind - 1 do
		if type(t) ~= "table" then
			return nil, nil
		end
		local k = bind[i]
		if type(k) == "table" then
			local found = nil
			for _, e in t do
				if type(e) == "table" and e.id == k.id then
					found = e
					break
				end
			end
			t = found
		else
			t = t[k]
		end
	end
	if type(t) ~= "table" then
		return nil, nil
	end
	return t, bind[#bind]
end

-- slot = {read = () -> any, write = (any) -> ()} for a bind path, or nil when it does not exist here.
function Applier:slot(bind: { any }): any
	local root = bind[1]
	if root == "WS" then
		local ws = self.targets.WS
		if self.peer ~= "server" or ws == nil then
			return nil
		end
		local name = bind[2]
		return {
			read = function()
				return ws:GetAttribute(name)
			end,
			write = function(v: any)
				ws:SetAttribute(name, v)
			end,
		}
	end
	local t, k = self:resolve(bind)
	if t == nil then
		return nil
	end
	local cur = t[k]
	if type(cur) == "table" and isArray(cur) then
		-- lists are replaced IN PLACE so scripts holding the table see the change
		return {
			read = function()
				return deepCopy(t[k])
			end,
			write = function(v: any)
				local list = t[k]
				if type(list) ~= "table" then
					t[k] = deepCopy(v)
					return
				end
				table.clear(list)
				for _, x in v or {} do
					table.insert(list, x)
				end
			end,
		}
	end
	return {
		read = function()
			return deepCopy(t[k])
		end,
		write = function(v: any)
			t[k] = deepCopy(v)
		end,
	}
end

function Applier:warnOnce(msg: string)
	if not self.warned[msg] then
		self.warned[msg] = true
		warn("[GwangalliLiveConfig] " .. msg)
	end
end

-- Remembers the original value the first time a slot is seen.
function Applier:captured(id: string, slot: any): any
	if not self.hasBase[id] then
		self.hasBase[id] = true
		self.base[id] = slot.read()
	end
	return self.base[id]
end

function Applier:baseline(key: string): any
	local f = BY_KEY[key]
	if not f or not f.bind then
		return f and deepCopy(f.default)
	end
	local id = pathId(f.bind)
	if self.hasBase[id] then
		return deepCopy(self.base[id])
	end
	local s = self:slot(f.bind)
	if s then
		return s.read()
	end
	return deepCopy(f.default)
end

-- Applies `doc` (validated) on this peer. Returns the list of slot ids that changed.
function Applier:apply(doc: any, happy: boolean?): { string }
	local desired: { [string]: any } = {} -- id -> {slot, value}
	local function want(id: string, slot: any, value: any)
		desired[id] = { slot = slot, value = value }
	end
	local mult = LC.valueIn(doc, "events.happyHour.multiplier")
	local vals = doc.values or {}

	-- 1. bound scalar fields
	for _, f in FIELDS do
		if f.bind and not (f.serverOnly and self.peer ~= "server") then
			local s = self:slot(f.bind)
			if not s then
				self:warnOnce("대상이 없어요: " .. f.key .. " -> " .. pathId(f.bind))
				continue
			end
			local id = pathId(f.bind)
			local base = self:captured(id, s)
			local v = vals[f.key]
			if f.happy and happy and isFinite(v or base) then
				want(id, s, math.max(0, round((v or base) * mult, 100)))
			elseif v ~= nil then
				want(id, s, v)
			end
			-- no override and no happy hour: not desired -> restored below
		end
	end

	-- 2. job wages and XP (derived from multipliers)
	local G = self.targets.G
	if type(G) == "table" and type(G.JOBS) == "table" then
		local all = LC.valueIn(doc, "jobs.payMultiplier")
		for jobId, job in G.JOBS do
			local m = all * (LC.valueIn(doc, "jobs." .. tostring(jobId) .. ".payMultiplier") or 1)
			if type(job) == "table" and type(job.levels) == "table" then
				for i in job.levels do
					local bind = { "G", "JOBS", jobId, "levels", i, "wage" }
					local s = self:slot(bind)
					if s then
						local id = pathId(bind)
						local base = self:captured(id, s)
						if math.abs(m - 1) > 1e-9 and isFinite(base) then
							want(id, s, math.max(0, round(base * m, 10)))
						end
					end
				end
			end
		end
		local xm = LC.valueIn(doc, "jobs.xpMultiplier")
		for _, k in { "TASK_XP", "SHIFT_XP" } do
			local bind = { "G", k }
			local s = self:slot(bind)
			if s then
				local id = pathId(bind)
				local base = self:captured(id, s)
				if math.abs(xm - 1) > 1e-9 and isFinite(base) then
					want(id, s, math.max(1, math.floor(base * xm + 0.5)))
				end
			end
		end

		-- 3. item price overrides (outfits / hair also update their source tables)
		if type(G.ITEMS) == "table" then
			for itemId, price in doc.itemPrices or {} do
				local it = G.ITEMS[itemId]
				if type(it) ~= "table" then
					self:warnOnce("모르는 상품 id (가격 무시): " .. tostring(itemId))
					continue
				end
				local bind = { "G", "ITEMS", itemId, "price" }
				local s = self:slot(bind)
				if s then
					local id = pathId(bind)
					self:captured(id, s)
					want(id, s, price)
				end
				local src = if it.kind == "outfit" then "CLOTHES" elseif it.kind == "hair" then "SALON" else nil
				if src and it.ref then
					local b2 = { "G", src, it.ref, "price" }
					local s2 = self:slot(b2)
					if s2 then
						local id2 = pathId(b2)
						self:captured(id2, s2)
						want(id2, s2, price)
					end
				end
			end

			-- 4. catalogue additions: whole item defs + display order membership
			for _, c in doc.catalog or {} do
				local existing = G.ITEMS[c.id]
				local id = "G.ITEMS." .. c.id
				local s = {
					read = function()
						return deepCopy(G.ITEMS[c.id])
					end,
					write = function(v: any)
						G.ITEMS[c.id] = deepCopy(v)
					end,
				}
				if existing ~= nil and not self.hasBase[id] and not self.applied[id] then
					-- never overwrite a real game item with a live one of the same id
					self:warnOnce("이미 있는 상품 id라 추가하지 않았어요: " .. c.id)
					continue
				end
				self:captured(id, s)
				local def = deepCopy(c)
				def.id = nil
				def.live = true
				want(id, s, def)
				if type(G.ITEM_ORDER) == "table" then
					local oid = "G.ITEM_ORDER+" .. c.id
					local os_ = {
						read = function()
							return table.find(G.ITEM_ORDER, c.id) ~= nil
						end,
						write = function(v: any)
							local at = table.find(G.ITEM_ORDER, c.id)
							if v and not at then
								table.insert(G.ITEM_ORDER, c.id)
							elseif not v and at then
								table.remove(G.ITEM_ORDER, at)
							end
						end,
					}
					self:captured(oid, os_)
					want(oid, os_, true)
				end
			end
		end

		-- 5. NPC lines for the gameplay NPCs (G.NPCS[id].liveLine; others via LC.npcLine)
		if type(G.NPCS) == "table" then
			for npcId, text in doc.npcLines or {} do
				if type(G.NPCS[npcId]) == "table" then
					local bind = { "G", "NPCS", npcId, "liveLine" }
					local s = self:slot(bind)
					if s then
						local id = pathId(bind)
						self:captured(id, s)
						want(id, s, text)
					end
				end
			end
		end
	end

	-- restore slots that are no longer desired, then write the desired values
	local changed = {}
	for id, rec in self.applied do
		if desired[id] == nil then
			local ok, err = pcall(rec.write, self.base[id])
			if ok then
				table.insert(changed, id)
			else
				self:warnOnce("복원 실패 " .. id .. ": " .. tostring(err))
			end
			self.applied[id] = nil
		end
	end
	for id, rec in desired do
		local cur = rec.slot.read()
		if not same(cur, rec.value) then
			local ok, err = pcall(rec.slot.write, rec.value)
			if ok then
				table.insert(changed, id)
			else
				self:warnOnce("적용 실패 " .. id .. ": " .. tostring(err))
			end
		end
		self.applied[id] = rec.slot
	end
	table.sort(changed)
	return changed
end

-- Keys whose configured value differs between two documents (for change notes).
function LC.diffKeys(a: any, b: any): { string }
	local out = {}
	for _, f in FIELDS do
		if not same(LC.valueIn(a, f.key), LC.valueIn(b, f.key)) then
			table.insert(out, f.key)
		end
	end
	for _, sec in { "announcements", "npcLines", "itemPrices", "catalog", "admins" } do
		if not same((a and a[sec]) or {}, (b and b[sec]) or {}) then
			table.insert(out, sec)
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------
-- Reader API (server + client): reads the replicated snapshot in ReplicatedStorage.GwangalliLive.
---------------------------------------------------------------------------------------------------
local cache = { raw = nil :: string?, doc = nil :: any }

function LC.folder(): Instance?
	return ReplicatedStorage:FindFirstChild(LC.FOLDER)
end

function LC.version(): number
	local f = LC.folder()
	local v = f and f:GetAttribute("Version")
	return if type(v) == "number" then v else 0
end

-- The current public document (decoded once per version).
function LC.current(): any
	local f = LC.folder()
	if not f then
		return LC.emptyDoc()
	end
	-- cached by the replicated JSON itself (the Version attribute may replicate before the Doc value)
	local sv = f:FindFirstChild(LC.DOC_VALUE)
	local raw = if sv and sv:IsA("StringValue") then sv.Value else ""
	if cache.raw == raw and cache.doc then
		return cache.doc
	end
	local doc = LC.jsonDecode(raw)
	if type(doc) ~= "table" then
		doc = LC.emptyDoc()
	end
	cache.raw = raw
	cache.doc = doc
	return doc
end

function LC.get(key: string): any
	local f = LC.folder()
	local fld = BY_KEY[key]
	if not fld then
		return nil
	end
	if f and fld.type ~= "clocklist" then
		local v = f:GetAttribute(LC.attrName(key))
		if v ~= nil then
			return v
		end
	end
	return LC.valueIn(LC.current(), key)
end

function LC.enabled(featureId: string): boolean
	local v = LC.get("features." .. tostring(featureId))
	return v ~= false
end

function LC.happyHour(): boolean
	local f = LC.folder()
	return f ~= nil and f:GetAttribute("HappyHourActive") == true
end

function LC.npcLine(npcId: string): string?
	local lines = LC.current().npcLines
	local t = lines and lines[npcId]
	return if type(t) == "string" and t ~= "" then t else nil
end

function LC.announcements(now: number?): { any }
	return LC.activeAnnouncements(LC.current(), now or os.time())
end

-- fn(version) after every snapshot change on this peer. Returns a connection-like {Disconnect}.
function LC.onChanged(fn: (number) -> ()): any
	local conns = {}
	local alive = true
	local function hook(f: Instance)
		local sv = f:FindFirstChild(LC.DOC_VALUE)
		if sv then
			table.insert(
				conns,
				sv.Changed:Connect(function()
					if alive then
						task.spawn(fn, LC.version())
					end
				end)
			)
		end
		table.insert(
			conns,
			f:GetAttributeChangedSignal("Version"):Connect(function()
				if alive then
					task.spawn(fn, LC.version())
				end
			end)
		)
		table.insert(
			conns,
			f:GetAttributeChangedSignal("HappyHourActive"):Connect(function()
				if alive then
					task.spawn(fn, LC.version())
				end
			end)
		)
	end
	local f = LC.folder()
	if f then
		hook(f)
	else
		local c
		c = ReplicatedStorage.ChildAdded:Connect(function(ch: Instance)
			if ch.Name == LC.FOLDER and alive then
				c:Disconnect()
				hook(ch)
				task.spawn(fn, LC.version())
			end
		end)
		table.insert(conns, c)
	end
	return {
		Disconnect = function()
			alive = false
			for _, c in conns do
				c:Disconnect()
			end
		end,
	}
end

return LC
