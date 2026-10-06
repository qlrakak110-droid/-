-- GwangalliMindShared: the NPC MIND of 광안리 GTA (owner: npc_mind). Personality, the five feelings,
-- memory, the free-text intent parser and the line composer that turns "what the player did" into
-- "what this person says back". Pure module: no instances, no Roblox globals at require time (the
-- node / Lune unit tests load it directly). Used by the server (ServerScriptService.GwangalliGameplay
-- .Mind: authoritative state, money, police) and the client (GwangalliStreetLife/Mind: bubbles,
-- behaviours, NPC <-> NPC scenes).
--
-- FEELINGS per NPC per player (0..100):
--   aff 호감도  = the 호감도 of GwangalliSocialShared (Relationships owns it: tiers, numbers, texts)
--   tr  신뢰도  trust: helping, keeping promises, honest apologies up; lies, bribes, violence down
--   an  분노도  anger: insults / 시비 / hits up; cools down by itself (AN_COOL per second)
--   fe  공포도  fear: threats / hits / a wanted player up; cools down by itself
--   cl  친밀도  intimacy: time and talk together (slow, capped per game day); unlocks the name,
--              the tastes, the number, dates and love
-- STAGES (Mind.stage): enemy 적대 | bad 사이 나쁨 | stranger | acquaintance | close | friend | bestie |
--   lover 연인. lover / enemy are sticky flags in the record (rec.st).
--
-- RECORD (rec, saved by the server; short keys):
--   tr an fe cl (numbers)  nm (name known)  kn = { food = {id..}, gift = {id..}, hobby = {key..} }
--   st ("" | "lover" | "enemy")  tk (talks)  lt (last talk unix)  fm (first met unix)
--   mem = { {t, k, x}, ... } newest last (MEM_MAX)   asked = { [intent] = {t, n} }
--   said = { [lineHash] = unix }  cd = { [key] = unix } per-NPC cooldowns
--   gd / gcl game-day key + intimacy gained that day  hit / ins / help / gifts counters
--   txt = { {f = "npc" | "me", m = text, t = unix}, ... } the phone thread   ap = appointment
--
-- COMPOSER: Mind.respond(c, rec, req, env) -> out
--   req = { intent, item?, outcome?, amount?, kind?, polite?, first?, chan? ("talk" | "call" | "text") }
--   env = { now (unix), clock (0..24), weather, area (label), areaKind, you (player name), aff, tier,
--           news = { live lines }, rnd = function, friend = name?, other = {id, name, area}? }
--   out = { lines = { text, ... }, face, emote, d = { aff, tr, an, fe, cl }, reveal = {...}?,
--           act = string?, ask = { kind, chips }?, mem = { k, x }?, mood, stage }
--   The server applies out.d / out.act; the client shows out.lines as bubbles.

local Lines = nil
do
	local ok, res = pcall(function()
		local rs = game and game:GetService("ReplicatedStorage")
		local m = rs and rs:FindFirstChild("GwangalliMindLines")
		return m and require(m)
	end)
	if ok and type(res) == "table" then
		Lines = res
	else
		local ok2, res2 = pcall(require, "GwangalliMindLines") -- unit tests (string require)
		if ok2 then
			Lines = res2
		end
	end
end

local Mind = {}
Mind.VERSION = 1
Mind.Lines = Lines

Mind.Folder = "GwangalliMind"
Mind.Remote = { Talk = "MindTalk", Event = "MindEvent", Get = "MindGet" }
Mind.Attr = {
	Wanted = "GwangalliWanted", -- Player attribute 0..5 (stars)
	WantedUntil = "GwangalliWantedUntil", -- server time the stars start cooling down
	Ready = "GwangalliMindReady",
	Busy = "GwangalliMindTalk", -- citizen id the player is talking to ("" = none)
}
Mind.DATASTORE = "GwangalliMind_v1"

Mind.MEM_MAX = 40
Mind.TXT_MAX = 40
Mind.REPEAT_WINDOW = 600 -- s: asking the same thing again inside this = "아까 말했잖아"
Mind.SAID_WINDOW = 900 -- s: a line is not used again for this player inside this
Mind.AN_COOL = 1 / 25 -- anger points per second
Mind.FE_COOL = 1 / 18
Mind.CL_DAY_CAP = 14 -- intimacy gained per NPC per game day
Mind.GAME_DAY = 1440
Mind.TALK_RANGE = 16 -- studs: a face-to-face conversation ends beyond this
Mind.NAME_AFF, Mind.NAME_CL = 10, 6
Mind.TASTE_AFF, Mind.TASTE_CL = 18, 10
Mind.NUMBER_AFF, Mind.NUMBER_CL = 30, 18
Mind.LOVE_AFF, Mind.LOVE_CL, Mind.LOVE_TR = 78, 55, 50
Mind.WANTED_MAX = 5
Mind.WANTED_COOL = 70 -- s without trouble before a star falls off

Mind.STATS = { "aff", "tr", "an", "fe", "cl" }
Mind.STAT_LABEL = { aff = "호감도", tr = "신뢰도", an = "분노도", fe = "공포도", cl = "친밀도" }
Mind.STAT_ICON = { aff = "💗", tr = "🤝", an = "💢", fe = "😨", cl = "🫶" }

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
Mind.isNum = isNum

local function clamp01(v: number): number
	return math.clamp(v, 0, 1)
end

local function c100(v: any): number
	if not isNum(v) then
		return 0
	end
	return math.clamp(math.floor(v * 10 + 0.5) / 10, 0, 100)
end
Mind.c100 = c100

-- 32-bit FNV-1a (same as GwangalliCitizens.hash)
local function hash(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (h * 16777619) % 4294967296
	end
	return h
end
Mind.hash = hash

local function hash01(s: string, n: number?): number
	return (hash(s .. "#" .. tostring(n or 0)) % 10007) / 10007
end

-------------------------------------------------------------------------------------------------
-- Archetypes: traits 0..1 (warm temper brave humor greed pride chatty), starting trust / fear,
-- banmal = talks down to everybody, hostile = picks fights, authority = police
-------------------------------------------------------------------------------------------------
Mind.ARCH = {
	citizen = { label = "시민", warm = 0.6, temper = 0.3, brave = 0.4, humor = 0.5, greed = 0.3, pride = 0.4, chatty = 0.5, tr0 = 30 },
	student = { label = "학생", warm = 0.6, temper = 0.35, brave = 0.35, humor = 0.75, greed = 0.4, pride = 0.3, chatty = 0.6, tr0 = 25 },
	office = { label = "직장인", warm = 0.5, temper = 0.4, brave = 0.4, humor = 0.45, greed = 0.4, pride = 0.55, chatty = 0.45, tr0 = 28 },
	police = { label = "경찰", warm = 0.55, temper = 0.3, brave = 0.95, humor = 0.35, greed = 0.05, pride = 0.6, chatty = 0.4, tr0 = 35, authority = true },
	drunk = { label = "취객", warm = 0.7, temper = 0.55, brave = 0.65, humor = 0.7, greed = 0.3, pride = 0.6, chatty = 0.9, tr0 = 40, banmal = true },
	homeless = { label = "노숙자", warm = 0.55, temper = 0.25, brave = 0.3, humor = 0.35, greed = 0.85, pride = 0.2, chatty = 0.6, tr0 = 20 },
	punk = { label = "걸렁뱅이", warm = 0.3, temper = 0.7, brave = 0.6, humor = 0.55, greed = 0.7, pride = 0.75, chatty = 0.85, tr0 = 10, banmal = true, hostile = true },
	thug = { label = "불량배", warm = 0.2, temper = 0.85, brave = 0.85, humor = 0.3, greed = 0.8, pride = 0.9, chatty = 0.4, tr0 = 5, banmal = true, hostile = true },
	fool = { label = "동네바보", warm = 0.9, temper = 0.1, brave = 0.5, humor = 0.95, greed = 0.2, pride = 0.05, chatty = 1, tr0 = 50, banmal = true },
	clerk = { label = "점원", warm = 0.65, temper = 0.3, brave = 0.35, humor = 0.5, greed = 0.35, pride = 0.35, chatty = 0.55, tr0 = 30 },
	parttimer = { label = "알바생", warm = 0.6, temper = 0.4, brave = 0.35, humor = 0.6, greed = 0.5, pride = 0.3, chatty = 0.55, tr0 = 28 },
	rich = { label = "부자", warm = 0.35, temper = 0.45, brave = 0.4, humor = 0.3, greed = 0.1, pride = 0.95, chatty = 0.4, tr0 = 20 },
	tourist = { label = "관광객", warm = 0.75, temper = 0.2, brave = 0.3, humor = 0.6, greed = 0.25, pride = 0.3, chatty = 0.75, tr0 = 35 },
	elder = { label = "어르신", warm = 0.7, temper = 0.45, brave = 0.5, humor = 0.5, greed = 0.25, pride = 0.7, chatty = 0.7, tr0 = 35, banmal = true },
	rider = { label = "배달 라이더", warm = 0.6, temper = 0.4, brave = 0.45, humor = 0.55, greed = 0.45, pride = 0.4, chatty = 0.5, tr0 = 30 },
	hothead = { label = "성깔 있는 사람", warm = 0.25, temper = 0.95, brave = 0.8, humor = 0.2, greed = 0.4, pride = 0.8, chatty = 0.3, tr0 = 10, hostile = true },
}

local TYPE_ARCH = { police = "police", beggar = "homeless", punk = "punk", thug = "thug", fool = "fool", drunk = "drunk", rich = "rich", violent = "hothead" }
local PERSONA_ARCH = {
	hs = "student", uni = "student", office = "office", dev = "office", tourist = "tourist", foreigner = "tourist",
	grandma = "elder", grandpa = "elder", barista = "clerk", merchant = "clerk", chef = "clerk", clerk = "clerk",
	police = "police", street = "homeless", punk = "punk", thug = "thug", rich = "rich", rider = "rider",
}

function Mind.archOf(c: any): string
	if type(c) ~= "table" then
		return "citizen"
	end
	local a = TYPE_ARCH[c.type or ""] or PERSONA_ARCH[c.persona or ""] or "citizen"
	if a == "clerk" and type(c.age) == "number" and c.age < 26 and c.persona == "clerk" then
		a = "parttimer"
	end
	return a
end

-- the archetype's traits jittered per person (deterministic), warmth from the roster's `social`
local traitCache: { [string]: any } = {}
function Mind.traits(c: any): any
	local id = (type(c) == "table" and c.id) or "?"
	local t = traitCache[id]
	if t then
		return t
	end
	local arch = Mind.archOf(c)
	local A = Mind.ARCH[arch] or Mind.ARCH.citizen
	t = { arch = arch }
	for _, k in { "warm", "temper", "brave", "humor", "greed", "pride", "chatty" } do
		t[k] = clamp01((A[k] or 0.5) + (hash01(id, #k) - 0.5) * 0.2)
	end
	if type(c) == "table" and isNum(c.social) then
		t.warm = clamp01(t.warm * 0.6 + c.social * 0.4)
		t.chatty = clamp01(t.chatty * 0.7 + c.social * 0.3)
	end
	-- the roster may pin someone's nerve (배달 라이더: who surrenders, who runs, who calls 112)
	if type(c) == "table" and isNum(c.nerve) then
		t.brave = clamp01(c.nerve)
	end
	t.tr0 = A.tr0 or 30
	t.banmal = A.banmal == true
	t.hostile = A.hostile == true
	t.authority = A.authority == true
	traitCache[id] = t
	return t
end

-------------------------------------------------------------------------------------------------
-- Records
-------------------------------------------------------------------------------------------------
function Mind.newRec(c: any, now: number): any
	local t = Mind.traits(c)
	return {
		v = Mind.VERSION,
		tr = t.tr0,
		an = 0,
		fe = 0,
		cl = 0,
		nm = false,
		kn = { food = {}, gift = {}, hobby = {} },
		st = "",
		tk = 0,
		lt = 0,
		fm = 0,
		mem = {},
		asked = {},
		said = {},
		cd = {},
		gd = 0,
		gcl = 0,
		hit = 0,
		ins = 0,
		help = 0,
		gifts = 0,
		txt = {},
		u = now,
		at = now, -- last cooling step (an / fe)
	}
end

-- sanitise a loaded record (old / foreign data never breaks the server)
function Mind.fixRec(rec: any, c: any, now: number): any
	if type(rec) ~= "table" then
		return Mind.newRec(c, now)
	end
	local base = Mind.newRec(c, now)
	for k, v in base do
		if type(rec[k]) ~= type(v) then
			rec[k] = v
		end
	end
	for _, k in { "tr", "an", "fe", "cl" } do
		rec[k] = c100(rec[k])
	end
	for _, k in { "food", "gift", "hobby" } do
		if type(rec.kn[k]) ~= "table" then
			rec.kn[k] = {}
		end
	end
	if #rec.mem > Mind.MEM_MAX then
		local keep = {}
		for i = #rec.mem - Mind.MEM_MAX + 1, #rec.mem do
			table.insert(keep, rec.mem[i])
		end
		rec.mem = keep
	end
	return rec
end

-- anger / fear cool down with time; intimacy fades a little after long absences
function Mind.cool(rec: any, now: number)
	local dt = math.max(0, now - (rec.at or now))
	rec.at = now
	if dt <= 0 then
		return
	end
	rec.an = c100(rec.an - dt * Mind.AN_COOL)
	rec.fe = c100(rec.fe - dt * Mind.FE_COOL)
	local days = (now - (rec.lt or now)) / 86400
	if days > 3 and rec.cl > 10 then
		local floorV = math.max(10, (rec.clPeak or rec.cl) * 0.5)
		local lose = math.min(dt / 86400, 2)
		rec.cl = c100(math.max(floorV, rec.cl - lose))
	end
end

function Mind.remember(rec: any, kind: string, x: any, now: number)
	table.insert(rec.mem, { t = now, k = kind, x = x })
	while #rec.mem > Mind.MEM_MAX do
		table.remove(rec.mem, 1)
	end
end

function Mind.lastOf(rec: any, kind: string): any?
	for i = #rec.mem, 1, -1 do
		local m = rec.mem[i]
		if m.k == kind then
			return m
		end
	end
	return nil
end

function Mind.countSince(rec: any, kind: string, since: number): number
	local n = 0
	for i = #rec.mem, 1, -1 do
		local m = rec.mem[i]
		if m.t < since then
			break
		end
		if m.k == kind then
			n += 1
		end
	end
	return n
end

-- apply feeling deltas (intimacy capped per game day); returns the clamped applied deltas
function Mind.apply(rec: any, d: any, now: number): any
	local out = {}
	if type(d) ~= "table" then
		return out
	end
	local gd = math.floor(now / Mind.GAME_DAY)
	if rec.gd ~= gd then
		rec.gd = gd
		rec.gcl = 0
	end
	for _, k in { "tr", "an", "fe", "cl" } do
		local v = d[k]
		if isNum(v) and v ~= 0 then
			if k == "cl" and v > 0 then
				v = math.min(v, math.max(0, Mind.CL_DAY_CAP - rec.gcl))
				rec.gcl += v
			end
			local before = rec[k]
			rec[k] = c100(before + v)
			out[k] = rec[k] - before
			if k == "cl" then
				rec.clPeak = math.max(rec.clPeak or 0, rec.cl)
			end
		end
	end
	rec.u = now
	return out
end

-------------------------------------------------------------------------------------------------
-- Stages + mood + register
-------------------------------------------------------------------------------------------------
Mind.STAGES = {
	enemy = { label = "적대", icon = "⚔️", color = { 255, 70, 80 } },
	bad = { label = "사이 나쁨", icon = "💢", color = { 255, 140, 90 } },
	stranger = { label = "모르는 사이", icon = "🤍", color = { 190, 190, 200 } },
	acquaintance = { label = "아는 사이", icon = "💛", color = { 255, 214, 90 } },
	close = { label = "친한 사이", icon = "🧡", color = { 255, 150, 60 } },
	friend = { label = "친구", icon = "💖", color = { 255, 105, 160 } },
	bestie = { label = "절친", icon = "💞", color = { 230, 70, 200 } },
	lover = { label = "연인", icon = "💘", color = { 255, 60, 120 } },
}
local TIER_STAGE = { "stranger", "acquaintance", "close", "friend", "bestie" }

function Mind.tierOfAff(a: number): number
	if a >= 95 then
		return 5
	elseif a >= 75 then
		return 4
	elseif a >= 50 then
		return 3
	elseif a >= 20 then
		return 2
	end
	return 1
end

function Mind.stage(rec: any, aff: number): string
	if rec.st == "enemy" then
		return "enemy"
	elseif rec.st == "lover" then
		return "lover"
	end
	if (rec.an >= 70 and aff < 20) or (rec.hit or 0) >= 3 then
		return "enemy"
	end
	if rec.an >= 40 or ((rec.ins or 0) >= 3 and aff < 15) then
		return "bad"
	end
	return TIER_STAGE[Mind.tierOfAff(aff)]
end

-- mood: good | neutral | bad | angry | scared | lover | enemy
function Mind.mood(c: any, rec: any, aff: number, env: any?): string
	local t = Mind.traits(c)
	local st = Mind.stage(rec, aff)
	if st == "enemy" then
		return if rec.fe >= 55 then "scared" else "enemy"
	end
	if rec.fe >= 55 then
		return "scared"
	end
	if rec.an >= 60 then
		return "angry"
	end
	if rec.an >= 28 then
		return "bad"
	end
	if st == "lover" then
		return "lover"
	end
	if aff >= 45 or (aff >= 22 and rec.tr >= 45) or (t.arch == "fool") or (t.arch == "drunk" and aff >= 5) then
		return "good"
	end
	if t.hostile and aff < 12 then
		return "bad"
	end
	return "neutral"
end

local MOOD_FALLBACK = {
	good = { "good", "neutral" },
	neutral = { "neutral" },
	bad = { "bad", "neutral" },
	angry = { "angry", "bad", "neutral" },
	scared = { "scared", "bad", "neutral" },
	lover = { "lover", "good", "neutral" },
	enemy = { "enemy", "angry", "bad", "neutral" },
}

-- p = 존댓말, c = 반말
function Mind.register(c: any, rec: any, aff: number): string
	local t = Mind.traits(c)
	if t.banmal or rec.bm == true then
		return "c" -- (rec.bm: they agreed to 말 놓기, GwangalliGameplay.Mind.Talk)
	end
	local st = Mind.stage(rec, aff)
	if st == "lover" or st == "enemy" then
		return "c"
	end
	if t.arch == "police" or t.arch == "rich" then
		return if aff >= 75 then "c" else "p"
	end
	return if aff >= 50 then "c" else "p"
end

-------------------------------------------------------------------------------------------------
-- Tastes (food / gifts / hobbies): what the player can find out by talking
-------------------------------------------------------------------------------------------------
Mind.FOODS = {
	tteokbokki = { name = "떡볶이", price = 6000, icon = "🍢" },
	gukbap = { name = "돼지국밥", price = 9000, icon = "🍲" },
	hoe = { name = "회 한 접시", price = 30000, icon = "🐟" },
	chicken = { name = "치킨", price = 21000, icon = "🍗" },
	ramen = { name = "컵라면", price = 1800, icon = "🍜" },
	burger = { name = "수제버거", price = 11000, icon = "🍔" },
	bungeoppang = { name = "붕어빵", price = 3000, icon = "🐟" },
	hotteok = { name = "씨앗호떡", price = 2500, icon = "🥞" },
	coffee = { name = "아이스 아메리카노", price = 4500, icon = "☕" },
	icecream = { name = "아이스크림", price = 2000, icon = "🍦" },
	gimbap = { name = "삼각김밥", price = 1500, icon = "🍙" },
	milmyeon = { name = "밀면", price = 8000, icon = "🍜" },
	saltbread = { name = "소금빵", price = 4000, icon = "🥐" },
	soju = { name = "포차 안주 한상", price = 18000, icon = "🍶", adult = true },
	omakase = { name = "오마카세", price = 90000, icon = "🍣" },
	jjajang = { name = "짜장면", price = 7000, icon = "🍝" },
	malatang = { name = "마라탕", price = 12000, icon = "🌶️" },
	fishcake = { name = "부산 어묵", price = 3000, icon = "🍥" },
}
Mind.FOOD_ORDER = { "bungeoppang", "hotteok", "fishcake", "gimbap", "ramen", "icecream", "coffee", "saltbread", "tteokbokki", "jjajang", "milmyeon", "gukbap", "burger", "malatang", "soju", "chicken", "hoe", "omakase" }

local ARCH_FOODS = {
	citizen = { "tteokbokki", "chicken", "gukbap", "coffee", "milmyeon" },
	student = { "tteokbokki", "malatang", "chicken", "icecream", "ramen" },
	office = { "gukbap", "hoe", "chicken", "coffee", "soju" },
	police = { "gukbap", "jjajang", "gimbap", "coffee", "fishcake" },
	drunk = { "soju", "gukbap", "fishcake", "hoe", "ramen" },
	homeless = { "gukbap", "bungeoppang", "ramen", "fishcake", "hotteok" },
	punk = { "ramen", "tteokbokki", "chicken", "gimbap", "malatang" },
	thug = { "gukbap", "chicken", "soju", "jjajang", "hoe" },
	fool = { "bungeoppang", "icecream", "hotteok", "tteokbokki", "ramen" },
	clerk = { "gimbap", "ramen", "tteokbokki", "coffee", "saltbread" },
	parttimer = { "gimbap", "ramen", "malatang", "icecream", "chicken" },
	rich = { "omakase", "hoe", "coffee", "saltbread", "burger" },
	tourist = { "gukbap", "milmyeon", "hotteok", "hoe", "fishcake" },
	elder = { "gukbap", "hoe", "fishcake", "bungeoppang", "milmyeon" },
	hothead = { "gukbap", "chicken", "soju", "jjajang", "ramen" },
}
-- gift ids of GwangalliSocialShared that are food -> our food ids
local GIFT_FOOD = { bungeoppang = "bungeoppang", hotteok = "hotteok", tteokbokki = "tteokbokki", saltbread = "saltbread", fishcake = "fishcake", americano = "coffee", latte = "coffee", beer = "soju", soju = "soju" }
Mind.HOBBY = {
	food = "맛집 탐방", sea = "바다 보며 멍 때리기", music = "음악 듣기", club = "클럽 가기", work = "일… 일이 취미예요", study = "공부 (억지로)",
	fashion = "쇼핑", games = "게임", travel = "여행", fitness = "운동", baseball = "야구 보기", family = "가족이랑 시간 보내기",
	art = "그림 그리기", coffee = "카페 투어", money = "재테크", photo = "사진 찍기",
}

local prefCache: { [string]: any } = {}
function Mind.prefs(c: any, giftName: ((string) -> string?)?): any
	local id = (type(c) == "table" and c.id) or "?"
	local p = prefCache[id]
	if p then
		return p
	end
	local arch = Mind.archOf(c)
	local foods = {}
	local function addFood(f: string?)
		if f and Mind.FOODS[f] and not table.find(foods, f) then
			table.insert(foods, f)
		end
	end
	if type(c) == "table" then
		for _, g in c.love or {} do
			addFood(GIFT_FOOD[g])
		end
	end
	local pool = ARCH_FOODS[arch] or ARCH_FOODS.citizen
	local start = (hash(id) % #pool) + 1
	for i = 0, #pool - 1 do
		addFood(pool[(start + i - 1) % #pool + 1])
		if #foods >= 3 then
			break
		end
	end
	if type(c) == "table" and c.minor then
		for i = #foods, 1, -1 do
			if Mind.FOODS[foods[i]].adult then
				table.remove(foods, i)
			end
		end
		addFood("tteokbokki")
	end
	-- one food they do not like (not one of theirs)
	local nofood = nil
	for k = 0, #Mind.FOOD_ORDER - 1 do
		local f = Mind.FOOD_ORDER[(hash(id .. "no") + k) % #Mind.FOOD_ORDER + 1]
		if not table.find(foods, f) and not table.find(pool, f) then
			nofood = f
			break
		end
	end
	local gifts = {}
	if type(c) == "table" then
		for _, g in c.love or {} do
			table.insert(gifts, g)
		end
		for _, g in c.like or {} do
			if type(g) == "string" and string.sub(g, 1, 4) ~= "cat:" then
				table.insert(gifts, g)
			end
		end
	end
	local hobbies = {}
	if type(c) == "table" then
		for _, tp in c.topics or {} do
			if Mind.HOBBY[tp] then
				table.insert(hobbies, tp)
			end
		end
	end
	if #hobbies == 0 then
		table.insert(hobbies, "sea")
	end
	p = { foods = foods, nofood = nofood, gifts = gifts, hobbies = hobbies, giftName = giftName }
	prefCache[id] = p
	return p
end

-- how they take a food: love | like | neutral | dislike
function Mind.foodPref(c: any, foodId: string): string
	local p = Mind.prefs(c)
	local arch = Mind.archOf(c)
	if p.foods[1] == foodId or p.foods[2] == foodId then
		return "love"
	elseif table.find(p.foods, foodId) then
		return "like"
	elseif p.nofood == foodId then
		return "dislike"
	end
	if arch == "homeless" then
		return "like" -- hungry people like every food
	end
	if arch == "rich" then
		local f = Mind.FOODS[foodId]
		return if f and f.price < 5000 then "neutral" else "like"
	end
	return "neutral"
end

-------------------------------------------------------------------------------------------------
-- Intent parser (free text -> intent). Hangul keywords, scored; the best score wins.
-------------------------------------------------------------------------------------------------
Mind.INTENT_LABEL = {
	greet = "인사", bye = "작별", how = "안부", doing = "뭐 해?", name = "이름", age = "나이", job = "직업", food_q = "좋아하는 음식",
	like_q = "좋아하는 것", hobby_q = "취미", place_q = "추천 장소", news_q = "주변 소식", number = "번호", about = "그 사람 얘기",
	weather = "날씨", food_talk = "음식 이야기", gift_talk = "선물 이야기", joke = "농담", compliment = "칭찬", flirt = "작업",
	confess = "고백", insult = "욕하기", provoke = "시비 걸기", threaten = "협박", apologize = "사과", thank = "고마워",
	request = "부탁", comfort = "위로", brag = "자랑", yes = "응", no = "아니", small = "수다", invite = "같이 놀자",
}

local KW = {
	greet = { "안녕", "하이", "hello", "hi ", "반가", "처음 뵙", "좋은 아침", "굿모닝", "여보세요", "ㅎㅇ", "방가" },
	bye = { "잘가", "잘 가", "안녕히", "바이", "다음에 봐", "또 봐", "나중에 봐", "간다", "갈게", "잘 있어", "ㅂㅂ", "빠이" },
	how = { "잘 지내", "잘지내", "기분 어때", "기분어때", "어떻게 지내", "요즘 어때", "별일 없", "컨디션", "괜찮아요?", "괜찮아?", "힘들지" },
	doing = { "뭐해", "뭐 해", "뭐하세요", "뭐 하세요", "뭐 하고", "어디 가", "뭐하고", "뭐하냐", "뭐 하냐" },
	name = { "이름", "누구세요", "성함", "뭐라고 불러", "누구야", "누구냐" },
	age = { "몇 살", "몇살", "나이", "연세", "몇 년생", "띠가" },
	job = { "직업", "무슨 일", "뭐 하는 사람", "직장", "일 해", "일해", "회사 다녀", "학생이", "뭐 하시는" },
	food_q = { "좋아하는 음식", "뭐 먹", "맛집", "배고", "먹을래", "뭐 좋아해 음식", "음식 뭐", "최애 음식", "입맛" },
	like_q = { "뭐 좋아", "좋아하는 거", "취향", "갖고 싶", "선물 뭐", "원하는 거", "좋아하는게", "좋아하는 게" },
	hobby_q = { "취미", "주말에 뭐", "쉴 때", "시간 날 때", "쉬는 날" },
	place_q = { "추천", "가볼 만", "가 볼 만", "어디 가면", "길 좀", "가는 길", "어디 있", "어딨", "위치", "어디로 가" },
	news_q = { "무슨 일 있", "사건", "소문", "뉴스", "소식", "요즘 동네", "들었어", "무슨 일이야", "별일" },
	number = { "번호", "연락처", "전화번호", "카톡", "인스타", "연락할게", "연락 줘" },
	weather = { "날씨", "덥", "춥", "비 와", "비와", "맑", "바람", "흐리" },
	gift_talk = { "선물" },
	joke = { "ㅋㅋㅋ", "농담", "웃긴", "개그", "아재", "재밌는 얘기", "드립", "웃겨" },
	compliment = { "예쁘", "이쁘", "잘생", "멋지", "멋있", "귀엽", "최고", "짱", "착하", "대단", "센스", "매력", "좋은 사람", "인상 좋" },
	flirt = { "데이트", "내 스타일", "연애", "남친", "여친", "애인 있", "결혼", "보고 싶", "설레" },
	confess = { "사귀", "너 좋아", "널 좋아", "너를 좋아", "당신을 좋아", "좋아하는 것 같아", "사랑해", "고백", "사귈래", "1일", "반했" },
	insult = { "바보", "멍청", "꺼져", "닥쳐", "짜증", "미친", "병신", "개새", "등신", "못생", "찐따", "한심", "쓰레기", "재수없", "씨발", "시발", "ㅅㅂ", "새끼", "또라이", "븅신" },
	provoke = { "뭘 봐", "뭘봐", "한판", "붙을래", "덤벼", "맞을래", "쳐 봐", "쳐봐", "어쩔", "시비", "까불", "한 판", "꼬나", "째려" },
	threaten = { "죽여", "죽는다", "패버", "혼난다", "가만 안", "두고 봐", "신고한다" },
	apologize = { "미안", "죄송", "사과", "잘못했", "용서", "쏘리", "sorry" },
	thank = { "고마", "감사", "땡큐", "thank", "ㄱㅅ" },
	request = { "부탁", "도와", "해줄래", "해 줄래", "해 줄 수", "해줄 수", "빌려", "알려 줘", "알려줘", "해 주세요", "해주세요" },
	comfort = { "힘내", "괜찮을 거", "위로", "걱정 마", "걱정마", "울지 마", "토닥" },
	brag = { "나 부자", "내가 최고", "자랑", "나 잘나", "부럽지" },
	invite = { "같이 놀", "놀자", "놀래", "가자", "갈래", "만나자", "약속", "한잔", "당구", "노래방", "코노", "볼링", "산책하자", "밥 먹자", "밥먹자" },
	yes = { "응", "네", "넹", "그래", "좋아", "오케이", "ok", "콜", "당연", "그럼", "맞아", "ㅇㅇ" },
	no = { "아니", "싫어", "별로", "안 돼", "안돼", "노노", "됐어", "ㄴㄴ", "글쎄" },
}
-- weights: strong intents beat incidental words ("아니 그게 아니라 너 이름 뭐야")
local KW_W = {
	insult = 3, provoke = 2.6, threaten = 2.8, confess = 2.6, apologize = 2.4, number = 2.4, name = 2.2, age = 2.2, job = 2,
	food_q = 1.8, like_q = 1.8, hobby_q = 2, place_q = 1.6, news_q = 1.6, invite = 1.8, flirt = 2, compliment = 1.8, joke = 1.4,
	request = 1.6, comfort = 1.6, thank = 1.6, how = 1.6, doing = 1.6, weather = 1.1, gift_talk = 1.2, brag = 1.4, greet = 1.2,
	bye = 1.3, yes = 0.6, no = 0.7,
}

-- polite = 존댓말 ending
function Mind.isPolite(text: string): boolean
	local t = string.gsub(text, "[%s%p~]+$", "")
	if string.find(t, "요$") or string.find(t, "요[%s%p~]") or string.find(t, "니다") or string.find(t, "세요") or string.find(t, "십니까") or string.find(t, "죠$") or string.find(t, "까요") or string.find(t, "습니까") or string.find(t, "십시오") then
		return true
	end
	return false
end

-- text -> intent, { polite, item (food id), other (citizen id) }. names = { {id, name, short} } of
-- citizens the speaker may mention.
function Mind.parse(text: any, names: { any }?): (string, any)
	local slots = { polite = false }
	if type(text) ~= "string" then
		return "small", slots
	end
	local s = string.lower(text)
	slots.polite = Mind.isPolite(text)
	local best, bestScore = "small", 0
	for intent, words in KW do
		local score = 0
		for _, w in words do
			if string.find(s, w, 1, true) then
				score += KW_W[intent] or 1
			end
		end
		if score > bestScore then
			best, bestScore = intent, score
		end
	end
	-- food words: talking about a food (or asking for one)
	if Lines and Lines.FOOD_WORDS then
		for fid, words in Lines.FOOD_WORDS do
			for _, w in words do
				if string.find(s, w, 1, true) then
					slots.item = fid
					break
				end
			end
			if slots.item then
				break
			end
		end
	end
	if slots.item and (best == "small" or best == "yes" or best == "no" or best == "weather" or best == "like_q") then
		best = "food_talk"
	end
	-- another person by name
	if names then
		for _, n in names do
			if (n.name and n.name ~= "" and string.find(text, n.name, 1, true)) or (n.short and #n.short >= 6 and string.find(text, n.short, 1, true)) then
				slots.other = n.id
				if best == "small" or best == "yes" or best == "no" then
					best = "about"
				end
				break
			end
		end
	end
	-- a bare question mark on unknown text: they will answer as small talk with a question back
	if best == "small" and string.find(text, "?", 1, true) then
		slots.question = true
	end
	return best, slots
end

-------------------------------------------------------------------------------------------------
-- Text helpers: fill placeholders (+ the right 조사 after them), Busan dialect, the archetype voice
-------------------------------------------------------------------------------------------------
local function lastHangul(word: string): number?
	local last = nil
	for _, cp in utf8.codes(word) do
		last = cp
	end
	return last
end

local function hasBatchim(word: string): boolean
	local cp = lastHangul(word)
	if cp and cp >= 0xAC00 and cp <= 0xD7A3 then
		return (cp - 0xAC00) % 28 ~= 0
	end
	if cp and cp >= 48 and cp <= 57 then
		-- digits read in Korean: 0 영 1 일 3 삼 6 육 7 칠 8 팔 have a final consonant
		local d = cp - 48
		return d == 0 or d == 1 or d == 3 or d == 6 or d == 7 or d == 8
	end
	return false
end
Mind.hasBatchim = hasBatchim

-- { batchim form, no-batchim form } (longest first)
local JOSA = {
	{ "이에요", "예요" }, { "이었", "였" }, { "이라고", "라고" }, { "이랑", "랑" }, { "이야", "야" }, { "이요", "요" },
	{ "으로", "로" }, { "은", "는" }, { "이", "가" }, { "을", "를" }, { "과", "와" }, { "아", "야" },
}

function Mind.fill(s: string, vars: { [string]: any }?): string
	if type(s) ~= "string" then
		return ""
	end
	local v = vars or {}
	local out = {}
	local i = 1
	local n = #s
	while i <= n do
		local a, b, key = string.find(s, "{(%w+)}", i)
		if not a then
			table.insert(out, string.sub(s, i))
			break
		end
		table.insert(out, string.sub(s, i, a - 1))
		local val = v[key]
		val = if val == nil then "" else tostring(val)
		table.insert(out, val)
		i = b + 1
		-- fix the particle right after the placeholder
		if val ~= "" then
			for _, pair in JOSA do
				local matched = nil
				for k, form in pair do
					if string.sub(s, i, i + #form - 1) == form then
						-- "요" alone only after a noun placeholder; "이" / "가" / "아" only when no Hangul follows
						matched = { k = k, form = form }
						break
					end
				end
				if matched then
					local nxt = string.sub(s, i + #matched.form, i + #matched.form + 2)
					local nextIsHangul = #nxt >= 3 and string.byte(nxt, 1) >= 0xEA and string.byte(nxt, 1) <= 0xED
					local single = matched.form == "이" or matched.form == "가" or matched.form == "아" or matched.form == "야" or matched.form == "요" or matched.form == "은" or matched.form == "는" or matched.form == "을" or matched.form == "를"
					if not (single and nextIsHangul and matched.form ~= "요") then
						local want = if hasBatchim(val) then pair[1] else pair[2]
						table.insert(out, want)
						i += #matched.form
					end
					break
				end
			end
		end
	end
	return table.concat(out)
end

-- Busan dialect over standard Korean (light touch: endings and a few words)
local BUSAN_C = {
	{ "뭐 해%?", "뭐 하노?" }, { "뭐해%?", "뭐하노?" }, { "왜%?", "와?" }, { "어디", "어데" }, { "그래%?", "그렇나?" },
	{ "아니야", "아이다" }, { "있어%?", "있나?" }, { "없어%?", "없나?" }, { "했어%?", "했나?" }, { "먹었어%?", "묵었나?" },
	{ "먹", "묵" }, { "좋아!", "좋다!" }, { "괜찮아", "괜찮다" }, { "그렇지", "그렇제" }, { "맞아", "맞다" },
	{ "너는", "니는" }, { "너도", "니도" }, { "너랑", "니랑" }, { "너한테", "니한테" }, { "너 ", "니 " }, { "하지 마%.", "하지 마라." },
	{ "거야%?", "기가?" }, { "알아%?", "아나?" }, { "봐%.", "봐라." }, { "가자!", "가자!" }, { "진짜 ", "진짜로 " },
}
local BUSAN_P = {
	{ "습니다", "습니더" }, { "입니다", "입니더" }, { "하세요%?", "하능교?" }, { "세요%?", "능교?" }, { "가세요", "가이소" }, { "오세요", "오이소" }, { "하세요", "하이소" },
	{ "있어요", "있어예" }, { "했어요", "했어예" }, { "네요", "네예" }, { "거예요", "기라예" }, { "그래요", "그래예" }, { "아니에요", "아이라예" },
	{ "먹", "묵" }, { "어디", "어데" }, { "죠%?", "지예?" }, { "에요%.", "에예." }, { "해요%.", "해예." },
}
function Mind.dialect(s: string, reg: string, rnd: (() -> number)?): string
	local r = rnd or math.random
	local rules = if reg == "c" then BUSAN_C else BUSAN_P
	local out = s
	for _, rule in rules do
		if r() < 0.75 then
			out = string.gsub(out, rule[1], rule[2])
		end
	end
	return out
end

-- lines that already open with an interjection keep it alone ("아… 네" never becomes "오 아… 네")
local INTERJ = {}
for _, ch in { "아", "어", "오", "에", "음", "헐", "와", "우", "히", "허", "흠", "네", "응", "야", "엥", "앗", "헉", "흥", "쳇", "하", "푸", "꺄", "으", "어머" } do
	INTERJ[ch] = true
end
local function firstCp(s: string): number?
	for _, cp in utf8.codes(s) do
		return cp
	end
	return nil
end

-- 동네바보 맞춤법 (on purpose, 킹받게): common words misspelled, now and then a stray ㅋ
local TYPO = {
	{ "안녕하세요", "안녕하세여" }, { "안녕", "안뇽" }, { "했어", "햇어" }, { "있어", "잇어" }, { "없어", "업서" }, { "괜찮", "갠찬" },
	{ "몰라", "몰랑" }, { "진짜", "진쨔" }, { "뭐", "머" }, { "그래", "구래" }, { "됐어", "됬어" }, { "돼", "되" }, { "왜", "외" },
	{ "너무", "넘" }, { "친구", "칭구" }, { "좋아", "조아" }, { "재밌", "재밋" }, { "싫어", "시러" }, { "말이야", "마리야" },
	{ "같아", "가타" }, { "맞아", "마자" }, { "있잖아", "잇자나" }, { "어디", "어듸" }, { "보고 싶", "보구 십" }, { "미안", "미아내" },
	{ "아니야", "아니얌" }, { "바다", "빠다" }, { "먹었", "머겄" }, { "봤어", "바써" }, { "할래", "할랭" }, { "이거", "이고" },
	{ "그렇지", "그치" }, { "알았어", "아라써" }, { "하지 마", "하지마" }, { "웃겨", "웃겨ㅋ" }, { "사랑해", "사랑행" },
}
function Mind.typo(s: string, rnd: (() -> number)?): string
	local r = rnd or math.random
	local out = s
	for _, rule in TYPO do
		if r() < 0.8 then
			out = string.gsub(out, rule[1], rule[2])
		end
	end
	out = string.gsub(out, "습니다", "슴다")
	if r() < 0.35 and not string.find(out, "ㅋ$") then
		out ..= " ㅋ"
	end
	return out
end

function Mind.voice(s: string, arch: string, rnd: (() -> number)?, upset: boolean?): string
	if arch == "fool" then
		s = Mind.typo(s, rnd)
	end
	local V = Lines and Lines.VOICE and Lines.VOICE[arch]
	if not V or s == "" then
		return s
	end
	local r = rnd or math.random
	local out = s
	if not upset and r() < (V.rate or 0.3) then
		local pre = V.pre[1 + math.floor(r() * #V.pre)]
		-- never "아 아…" / "히히 히히": skip when the line already opens with the same sound or a tic
		local f0, f1 = firstCp(pre), firstCp(out)
		if pre ~= "" and f0 ~= f1 and string.sub(out, 1, 1) ~= "(" and not string.find(out, "^[%.…]") and not INTERJ[utf8.char(f1 or 32)] then
			out = pre .. out
		end
	end
	if r() < (V.rate or 0.3) then
		local post = V.post[1 + math.floor(r() * #V.post)]
		local last = lastHangul(out) or 0
		-- a line that already ends with a tic (ㅋ ㅎ ㅠ, an emoji, ~) keeps its ending
		local endsTic = (last >= 0x3131 and last <= 0x318E) or last >= 0x2600 or last == 126
		if post ~= "" and not endsTic and not string.find(out, post, 1, true) and not (last == 63 and string.sub(post, -1) == "!") then
			out = out .. post
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Bank lookup + no-repeat pick
-------------------------------------------------------------------------------------------------
local function listOf(entry: any, reg: string): { string }?
	if type(entry) ~= "table" then
		return nil
	end
	if entry[1] ~= nil then
		return entry
	end
	local l = entry[reg] or entry[if reg == "c" then "p" else "c"]
	if type(l) == "table" and #l > 0 then
		return l
	end
	return nil
end

-- the bank for intent + mood (archetype first, then generic), following the mood fallbacks
function Mind.bank(arch: string, intent: string, mood: string, reg: string): { string }?
	if not Lines then
		return nil
	end
	local A = Lines.A[arch]
	local order = MOOD_FALLBACK[mood] or { mood, "neutral" }
	if A and A[intent] then
		for _, m in order do
			local l = listOf(A[intent][m], reg)
			if l then
				return l
			end
		end
		local l = listOf(A[intent].any, reg)
		if l then
			return l
		end
	end
	local G = Lines.G[intent]
	if G then
		for _, m in order do
			local l = listOf(G[m], reg)
			if l then
				return l
			end
		end
		local l = listOf(G.any, reg)
		if l then
			return l
		end
	end
	return nil
end

function Mind.sub(intent: string, key: string, arch: string, reg: string): { string }?
	if not Lines then
		return nil
	end
	local A = Lines.A[arch]
	if A and A[intent] then
		local l = listOf(A[intent][key], reg) or (key ~= "any" and nil)
		if l then
			return l
		end
	end
	local G = Lines.G[intent]
	return G and listOf(G[key], reg) or nil
end

-- pick a line not said to this player recently (rec.said); marks it
function Mind.pick(list: { string }?, rec: any?, now: number, rnd: (() -> number)?): string?
	if not list or #list == 0 then
		return nil
	end
	local r = rnd or math.random
	local start = 1 + math.floor(r() * #list)
	local best, bestT = nil, math.huge
	for k = 0, #list - 1 do
		local s = list[(start + k - 1) % #list + 1]
		local h = tostring(hash(s) % 1000003)
		local t = rec and rec.said and rec.said[h] or 0
		if now - t > Mind.SAID_WINDOW then
			best = s
			bestT = -1
			break
		end
		if t < bestT then
			best, bestT = s, t
		end
	end
	if rec and rec.said and best then
		rec.said[tostring(hash(best) % 1000003)] = now
		-- keep the table small
		local n = 0
		for _ in rec.said do
			n += 1
		end
		if n > 120 then
			for k, t in rec.said do
				if now - t > Mind.SAID_WINDOW then
					rec.said[k] = nil
				end
			end
		end
	end
	return best
end

-------------------------------------------------------------------------------------------------
-- Faces / gestures by mood and intent
-------------------------------------------------------------------------------------------------
-- face: smile laugh angry annoyed shy scared sad neutral wary smug drunk surprised love dizzy
local MOOD_FACE = { good = "smile", neutral = "neutral", bad = "annoyed", angry = "angry", scared = "scared", lover = "love", enemy = "angry" }
local INTENT_FACE = {
	joke = { good = "laugh", neutral = "smug", bad = "annoyed" },
	compliment = { good = "shy", neutral = "smile", bad = "wary" },
	flirt = { good = "shy", neutral = "surprised", bad = "annoyed", lover = "love" },
	insult = { good = "sad", neutral = "angry", bad = "angry", scared = "scared" },
	provoke = { good = "surprised", neutral = "wary", bad = "angry", scared = "scared" },
	apologize = { bad = "wary", angry = "annoyed" },
	thank = { good = "smile" },
	news_q = { good = "surprised" },
	name = { good = "smile" },
}
-- emote (gesture): wave laugh cheer point think refuse shy nod shrug cross startle clap phone dance turn look
local INTENT_EMOTE = {
	greet = { good = "wave", neutral = "nod", bad = "turn", angry = "cross", scared = "startle", lover = "wave", enemy = "cross" },
	bye = { good = "wave", neutral = "nod", bad = "turn", lover = "wave" },
	joke = { good = "laugh", neutral = "shrug", bad = "turn" },
	compliment = { good = "shy", neutral = "nod", bad = "shrug" },
	flirt = { good = "shy", neutral = "shrug", bad = "refuse", lover = "shy" },
	insult = { good = "startle", neutral = "point", bad = "point", angry = "point", scared = "startle" },
	provoke = { neutral = "cross", bad = "point", angry = "point", scared = "startle" },
	threaten = { neutral = "cross", angry = "point", scared = "startle" },
	apologize = { good = "nod", neutral = "nod", bad = "cross" },
	thank = { good = "nod" },
	place_q = { good = "point", neutral = "point" },
	news_q = { good = "think", neutral = "think" },
	how = { good = "nod", neutral = "shrug" },
	name = { good = "wave", neutral = "nod", guard = "shrug" },
	request = { good = "nod", neutral = "think" },
	small = { good = "nod", neutral = "think", bad = "turn" },
}

-------------------------------------------------------------------------------------------------
-- The composer
-------------------------------------------------------------------------------------------------
-- friendly talk: may get a context tail / a question back
local CHAT_INTENTS = { greet = true, how = true, doing = true, name = true, age = true, job = true, food_q = true, like_q = true, hobby_q = true, place_q = true, news_q = true, weather = true, food_talk = true, gift_talk = true, joke = true, compliment = true, thank = true, small = true, about = true, yes = true, no = true, comfort = true }
local ASK_INTENTS = { name = true, age = true, job = true, food_q = true, like_q = true, hobby_q = true, place_q = true, news_q = true, number = true, how = true, doing = true }

local function rndOf(env: any): () -> number
	return (env and env.rnd) or math.random
end

local function agoText(sec: number): string
	if sec < 3600 then
		return string.format("%d분", math.max(1, sec // 60))
	elseif sec < 86400 then
		return string.format("%d시간", sec // 3600)
	end
	return string.format("%d일", sec // 86400)
end

-- the memory prefix of a meeting (first exchange of a session)
local function memoryLine(c: any, rec: any, env: any, reg: string, mood: string): string?
	if not Lines then
		return nil
	end
	local now = env.now
	local r = rndOf(env)
	local M = Lines.MEM
	local function line(key: string): string?
		return Mind.pick(listOf(M[key], reg), rec, now, r)
	end
	if mood == "lover" then
		return line("lover")
	elseif mood == "enemy" then
		return line("enemy")
	end
	local hit = Mind.lastOf(rec, "hit")
	if hit and now - hit.t < 7 * 86400 then
		return line("hit")
	end
	local ins = Mind.lastOf(rec, "insult")
	if ins and now - ins.t < 3 * 86400 and rec.an > 5 then
		return line("insulted")
	end
	local br = Mind.lastOf(rec, "broken")
	if br and now - br.t < 3 * 86400 then
		return line("broken")
	end
	if (rec.tk or 0) == 0 or (rec.lt or 0) <= 0 then
		return nil
	end
	local since = now - rec.lt
	if since < 300 then
		return line("again")
	end
	local g = Mind.lastOf(rec, "gift")
	if g and now - g.t < 2 * 86400 and r() < 0.6 then
		env.vars.gift = g.x
		return line("gift")
	end
	local f = Mind.lastOf(rec, "food")
	if f and now - f.t < 2 * 86400 and r() < 0.6 then
		local fd = Mind.FOODS[f.x]
		env.vars.gift = fd and fd.name or tostring(f.x)
		return line("food")
	end
	local h = Mind.lastOf(rec, "help")
	if h and now - h.t < 3 * 86400 and r() < 0.5 then
		return line("helped")
	end
	local k = Mind.lastOf(rec, "kept")
	if k and now - k.t < 2 * 86400 and r() < 0.5 then
		return line("promise")
	end
	if since < 3 * 3600 then
		return if r() < 0.5 then line("today") else nil
	elseif since < 2 * 86400 then
		return nil
	elseif since < 10 * 86400 then
		env.vars.ago = agoText(since)
		return line("days")
	end
	return line("long")
end

local function tailLine(rec: any, env: any, reg: string): string?
	if not Lines then
		return nil
	end
	local r = rndOf(env)
	local keys = {}
	local tod = env.tod or "day"
	table.insert(keys, tod)
	if env.weather == "rain" or env.weather == "cloudy" then
		table.insert(keys, env.weather)
		table.insert(keys, env.weather)
	elseif env.weather == "clear" then
		table.insert(keys, "clear")
	end
	if env.areaKind and Lines.TAIL[env.areaKind] then
		table.insert(keys, env.areaKind)
	end
	local key = keys[1 + math.floor(r() * #keys)]
	return Mind.pick(listOf(Lines.TAIL[key], reg), rec, env.now, r)
end

local ASK_ORDER = { "often", "food", "mood", "job", "music", "date", "yourname" }
local function askBack(c: any, rec: any, env: any, reg: string, mood: string, aff: number): any?
	if not Lines then
		return nil
	end
	local r = rndOf(env)
	local now = env.now
	local options = {}
	for _, k in ASK_ORDER do
		local ok = true
		if k == "date" and (aff < 45 or (c.minor and true)) then
			ok = false
		end
		if k == "yourname" and (rec.tk or 0) > 3 then
			ok = false
		end
		local last = rec.cd["ask:" .. k] or 0
		if now - last < 1800 then
			ok = false
		end
		if ok then
			table.insert(options, k)
		end
	end
	if #options == 0 then
		return nil
	end
	local k = options[1 + math.floor(r() * #options)]
	local A = Lines.ASK[k]
	local text = Mind.pick(listOf(A, reg), rec, now, r)
	if not text then
		return nil
	end
	rec.cd["ask:" .. k] = now
	return { kind = k, text = text, chips = A.chips }
end

local function giftNameOf(env: any, id: string?): string
	if not id then
		return "작은 선물"
	end
	if env.giftName then
		local ok, n = pcall(env.giftName, id)
		if ok and type(n) == "string" then
			return n
		end
	end
	return id
end

-- deltas helper
local function D(aff: number?, tr: number?, an: number?, fe: number?, cl: number?): any
	return { aff = aff or 0, tr = tr or 0, an = an or 0, fe = fe or 0, cl = cl or 0 }
end

function Mind.respond(c: any, rec: any, req: any, env: any): any
	local r = rndOf(env)
	local now = env.now or os.time()
	local t = Mind.traits(c)
	local arch = t.arch
	local aff = env.aff or 0
	local intent = req.intent or "small"
	local mood = Mind.mood(c, rec, aff, env)
	local reg = Mind.register(c, rec, aff)
	local st = Mind.stage(rec, aff)
	local P = Mind.prefs(c)
	local vars = env.vars or {}
	env.vars = vars
	vars.you = env.you or "친구"
	vars.me = c.name or "?"
	vars.job = c.job or "그냥 이것저것"
	vars.age = c.age or 20
	vars.food = Mind.FOODS[P.foods[1] or "tteokbokki"].name
	vars.food2 = Mind.FOODS[P.foods[2] or P.foods[1] or "gukbap"].name
	vars.nofood = P.nofood and Mind.FOODS[P.nofood].name or "오이"
	vars.gift = giftNameOf(env, P.gifts[1])
	vars.hobby = Mind.HOBBY[P.hobbies[1]] or "산책"
	vars.place = env.recommend or "민락회타운"
	vars.time = env.timeText or "지금"
	vars.weather = if env.weather == "rain" then "비 오는 날" elseif env.weather == "cloudy" then "흐린 날" else "맑은 날"
	vars.friend = env.friend or "친구"
	vars.area = env.area or "해변"
	vars.tod = env.tod or "day"
	local out = { lines = {}, d = D(), mood = mood, stage = st, reg = reg }
	local main: string? = nil
	local face = MOOD_FACE[mood] or "neutral"
	local emoteKey = mood
	local sub = nil -- name / taste "guard" etc.

	-- a busy stranger cuts it short: talking too much in a row annoys (spam)
	local recentTalks = Mind.countSince(rec, "talk", now - 60)
	if recentTalks >= 9 and intent ~= "apologize" and intent ~= "bye" then
		out.d.an = 6
		main = Mind.pick(Mind.bank(arch, "small", "bad", reg), rec, now, r) or "…"
		out.lines = { Mind.fill(main, vars) }
		out.face, out.emote = "annoyed", "turn"
		out.mem = { k = "talk" }
		return out
	end

	-- repeats ("아까 말했잖아")
	local repeatPrefix: string? = nil
	if ASK_INTENTS[intent] and Lines then
		local a = rec.asked[intent]
		if a and now - a.t < Mind.REPEAT_WINDOW then
			a.n += 1
			a.t = now
			if a.n >= 4 then
				out.d.an = 8
				out.d.aff = -1
				main = Mind.pick(listOf(Lines.REPEAT.stop, reg), rec, now, r)
				out.lines = { Mind.fill(main or "…", vars) }
				out.face, out.emote = "annoyed", "turn"
				out.mem = { k = "talk" }
				return out
			end
			local key = if a.n >= 3 then "annoyed" else "soft"
			repeatPrefix = Mind.pick(listOf(Lines.REPEAT[key], reg), rec, now, r)
			if a.n >= 3 then
				out.d.an = 4
			end
		else
			rec.asked[intent] = { t = now, n = 1 }
		end
	end

	-- 반말 to people who mind it (strangers, older or proud)
	local longText = type(req.text) == "string" and (utf8.len(req.text) or 0) >= 4
	if req.polite == false and longText and not t.banmal and aff < 50 and (arch == "rich" or arch == "police" or arch == "office" or ((c.age or 20) >= 40 and arch ~= "homeless" and arch ~= "tourist")) and intent ~= "insult" and intent ~= "provoke" then
		if r() < 0.55 and Lines then
			local bl = { p = { "어… 처음 보는데 반말이세요?", "말이 좀 짧으시네요?", "저 아세요? 왜 반말이에요?", "반말은 좀… ㅎㅎ" } }
			table.insert(out.lines, Mind.fill(Mind.pick(bl.p, rec, now, r) or "", vars))
			out.d.aff = (out.d.aff or 0) - 1
			out.d.an = (out.d.an or 0) + 3
			face = "annoyed"
		end
	end
	if req.polite == false and longText and arch == "elder" and aff < 40 and intent ~= "insult" and r() < 0.5 and Lines then
		table.insert(out.lines, Mind.fill(Mind.pick(Mind.sub("banmal", "any", "elder", "c"), rec, now, r) or "", vars))
		out.d.an = (out.d.an or 0) + 3
	end

	-- the main reply
	if intent == "greet" then
		main = Mind.pick(Mind.bank(arch, "greet", mood, reg), rec, now, r)
		if mood ~= "bad" and mood ~= "angry" and mood ~= "enemy" then
			out.d.aff = (out.d.aff or 0) + 1
			out.d.cl = 0.6
		end
	elseif intent == "bye" then
		main = Mind.pick(Mind.bank(arch, "bye", mood, reg), rec, now, r)
		out.act = "end"
	elseif intent == "name" then
		local allowed = rec.nm or aff >= Mind.NAME_AFF or rec.cl >= Mind.NAME_CL or rec.tr >= 45 or arch == "fool" or arch == "drunk" or arch == "clerk"
		if mood == "angry" or mood == "enemy" or mood == "scared" then
			allowed = false
		end
		if allowed then
			main = Mind.pick(Mind.bank(arch, "name", if mood == "good" or mood == "lover" then "good" else "neutral", reg), rec, now, r)
			if not rec.nm then
				out.reveal = { name = true }
				out.d.cl = 2
				out.d.tr = 1
			end
			face = "smile"
		else
			sub = "guard"
			main = Mind.pick(Mind.sub("name", if mood == "bad" or mood == "angry" or mood == "scared" then mood else "guard", arch, reg) or Mind.sub("name", "guard", arch, reg), rec, now, r)
			face = "smug"
		end
	elseif intent == "age" or intent == "job" then
		local okMood = if aff >= 3 or arch == "fool" or arch == "drunk" or arch == "elder" then mood else (if mood == "good" then "neutral" else mood)
		main = Mind.pick(Mind.bank(arch, intent, okMood, reg), rec, now, r)
		out.d.cl = 0.8
	elseif intent == "food_q" or intent == "like_q" or intent == "hobby_q" then
		local allowed = aff >= Mind.TASTE_AFF or rec.cl >= Mind.TASTE_CL or (mood == "good" and r() < 0.5) or arch == "fool" or arch == "homeless" or arch == "drunk"
		if mood == "angry" or mood == "enemy" or mood == "scared" or mood == "bad" then
			allowed = false
		end
		if allowed then
			main = Mind.pick(Mind.bank(arch, intent, if mood == "lover" then "good" else mood, reg), rec, now, r)
			local key = if intent == "food_q" then "food" elseif intent == "like_q" then "gift" else "hobby"
			local list = if key == "food" then P.foods elseif key == "gift" then P.gifts else P.hobbies
			local known = rec.kn[key]
			local newOnes = {}
			for i = 1, math.min(#list, 2) do
				if not table.find(known, list[i]) then
					table.insert(newOnes, list[i])
				end
			end
			if key == "food" and P.nofood and not table.find(rec.kn.nofood or {}, P.nofood) then
				rec.kn.nofood = { P.nofood }
			end
			if #newOnes > 0 then
				out.reveal = { [key] = newOnes }
				out.d.cl = 1.5
			end
		else
			sub = "guard"
			main = Mind.pick(Mind.sub(intent, if mood == "bad" or mood == "angry" or mood == "scared" then mood else "guard", arch, reg) or Mind.sub(intent, "guard", arch, reg), rec, now, r)
			face = "smug"
		end
	elseif intent == "number" then
		if req.outcome == "already" then
			main = Mind.pick(Mind.sub("number", "already", arch, reg), rec, now, r)
		elseif mood == "angry" or mood == "enemy" or mood == "scared" then
			main = Mind.pick(Mind.sub("number", "angry", arch, reg), rec, now, r)
		elseif not rec.nm and aff < Mind.NUMBER_AFF + 10 then
			main = Mind.pick(Mind.sub("number", "noname", arch, reg), rec, now, r)
			face = "smug"
		elseif aff >= Mind.NUMBER_AFF and rec.cl >= Mind.NUMBER_CL then
			out.act = "number" -- the server asks Relationships; its line replaces this one when it says no
			main = Mind.pick(Mind.sub("number", "yes", arch, reg), rec, now, r)
			face = "smile"
			out.emoteOverride = "phone"
		else
			main = Mind.pick(Mind.sub("number", "no", arch, reg), rec, now, r)
			face = "shy"
			out.emoteOverride = "refuse"
		end
	elseif intent == "about" then
		local o = env.other
		if o then
			vars.other = o.name
			vars.area = o.area or vars.area
		end
		main = Mind.pick(Mind.bank(arch, "about", if o and o.friend then "good" else mood, reg), rec, now, r)
		out.d.cl = 0.6
	elseif intent == "news_q" then
		local news = env.news or {}
		vars.news = news[1 + math.floor(r() * math.max(1, #news))] or (Lines and Lines.NEWS[1 + math.floor(r() * #Lines.NEWS)]) or "별일 없어요."
		main = Mind.pick(Mind.bank(arch, "news_q", mood, reg), rec, now, r)
		out.d.cl = 0.8
	elseif intent == "food_talk" then
		local item = req.item
		local f = item and Mind.FOODS[item]
		vars.item = f and f.name or "그거"
		local pref = if item then Mind.foodPref(c, item) else "neutral"
		local key = if mood == "bad" or mood == "angry" or mood == "scared" then mood elseif pref == "love" then "love" elseif pref == "dislike" then "hate" else (if mood == "good" then "good" else "neutral")
		main = Mind.pick(Mind.sub("food_talk", key, arch, reg) or Mind.bank(arch, "food_talk", mood, reg), rec, now, r)
		if key == "love" then
			out.d.aff = 2
			out.d.cl = 1.2
			face = "laugh"
			if item and not table.find(rec.kn.food, item) then
				out.reveal = { food = { item } }
			end
		elseif key == "hate" then
			if P.nofood and not table.find(rec.kn.nofood or {}, P.nofood) then
				rec.kn.nofood = { P.nofood }
			end
		else
			out.d.cl = 0.5
		end
	elseif intent == "joke" then
		local good = mood == "good" or mood == "lover" or (mood == "neutral" and r() < t.humor)
		main = Mind.pick(Mind.bank(arch, "joke", if good and mood ~= "lover" then "good" else mood, reg), rec, now, r)
		if good then
			out.d.aff = 2
			out.d.cl = 1
			face = "laugh"
			emoteKey = "good"
		elseif mood == "bad" or mood == "angry" then
			out.d.an = 3
		end
	elseif intent == "compliment" then
		local likes = arch == "rich" or arch == "elder" or arch == "tourist" or arch == "fool" or arch == "student"
		local suspicious = (arch == "punk" or arch == "thug") and aff < 40
		if mood == "bad" or mood == "angry" or mood == "enemy" or mood == "scared" then
			main = Mind.pick(Mind.bank(arch, "compliment", mood, reg), rec, now, r)
			out.d.an = -3
		elseif suspicious then
			main = Mind.pick(Mind.bank(arch, "compliment", "neutral", reg), rec, now, r)
			out.d.tr = -1
			face = "wary"
		else
			main = Mind.pick(Mind.bank(arch, "compliment", if mood == "lover" then "lover" elseif likes or mood == "good" then "good" else "neutral", reg), rec, now, r)
			out.d.aff = if likes then 3 else 2
			out.d.cl = 1
			face = "shy"
			emoteKey = "good"
		end
	elseif intent == "flirt" then
		if st == "lover" then
			main = Mind.pick(Mind.bank(arch, "flirt", "lover", reg), rec, now, r)
			out.d.aff, out.d.cl = 2, 2
		elseif c.minor then
			main = Mind.pick(Mind.sub("confess", "minor", arch, reg), rec, now, r)
			out.d.tr = -2
			face = "annoyed"
		elseif mood == "good" and rec.cl >= 30 then
			main = Mind.pick(Mind.bank(arch, "flirt", "good", reg), rec, now, r)
			out.d.aff, out.d.cl = 2, 1.5
			face = "shy"
			emoteKey = "good"
		elseif mood == "bad" or mood == "angry" or mood == "scared" then
			main = Mind.pick(Mind.bank(arch, "flirt", mood, reg), rec, now, r)
			out.d.an = 6
			out.d.aff = -2
		else
			main = Mind.pick(Mind.bank(arch, "flirt", "neutral", reg), rec, now, r)
			out.d.tr = -1
			face = "surprised"
			emoteKey = "neutral"
		end
	elseif intent == "confess" then
		if st == "lover" then
			main = Mind.pick(Mind.sub("confess", "already", arch, reg), rec, now, r)
			out.d.cl = 1
			face = "love"
		elseif c.minor then
			main = Mind.pick(Mind.sub("confess", "minor", arch, reg), rec, now, r)
			out.d.tr = -3
			face = "annoyed"
		elseif env.partner then
			main = Mind.pick(Mind.sub("confess", "taken", arch, reg), rec, now, r)
			face = "sad"
		elseif aff >= Mind.LOVE_AFF and rec.cl >= Mind.LOVE_CL and rec.tr >= Mind.LOVE_TR and mood ~= "bad" and mood ~= "angry" then
			main = Mind.pick(Mind.sub("confess", "yes", arch, reg), rec, now, r)
			out.act = "lover"
			out.d.cl, out.d.tr = 5, 5
			face = "love"
			out.emoteOverride = "cheer"
		elseif aff < 40 or rec.cl < 25 then
			main = Mind.pick(Mind.sub("confess", "early", arch, reg), rec, now, r)
			out.d.aff = -2
			out.d.tr = -2
			face = "surprised"
		else
			main = Mind.pick(Mind.sub("confess", "no", arch, reg), rec, now, r)
			out.d.cl = 1
			face = "sad"
		end
	elseif intent == "insult" then
		if st == "lover" then
			main = Mind.pick(Mind.bank(arch, "insult", "lover", reg), rec, now, r)
			out.act = "breakup"
			out.d.an, out.d.tr, out.d.cl = 40, -30, -20
			face = "sad"
		else
			main = Mind.pick(Mind.bank(arch, "insult", mood, reg), rec, now, r)
			out.d.aff = -6
			out.d.an = 22 + t.temper * 18
			out.d.tr = -8
			out.d.fe = if t.brave < 0.4 then 6 else 0
			face = if mood == "scared" or t.brave < 0.3 then "scared" elseif t.temper > 0.6 then "angry" else "sad"
			if t.authority then
				out.act = "warn"
			elseif t.hostile and rec.an + out.d.an >= 55 then
				out.act = if r() < 0.5 then "shove" else "escalate"
			elseif rec.fe + out.d.fe >= 50 then
				out.act = "flee"
			elseif rec.an + out.d.an >= 75 and not t.hostile then
				out.act = "leave"
			end
		end
		out.mem = { k = "insult" }
	elseif intent == "provoke" or intent == "threaten" then
		local key = intent
		if t.hostile and mood ~= "scared" then
			-- 걸렁뱅이 / 불량배: answering back makes it worse, unless they are scared of you
			main = Mind.pick(Mind.sub("escalate", "any", arch, reg) or Mind.bank(arch, key, mood, reg), rec, now, r)
			out.d.an = 16 + t.temper * 14
			out.act = if rec.an + out.d.an >= 50 and r() < 0.6 then "shove" else "escalate"
			face = "angry"
		elseif t.authority then
			main = Mind.pick(Mind.bank(arch, key, mood, reg), rec, now, r)
			out.act = "warn"
			out.d.tr = -10
			face = "wary"
		else
			main = Mind.pick(Mind.bank(arch, key, mood, reg), rec, now, r)
			out.d.an = 12 + t.temper * 12
			out.d.fe = (1 - t.brave) * (if key == "threaten" then 40 else 24)
			out.d.tr = if key == "threaten" then -15 else -6
			out.d.aff = if key == "threaten" then -5 else -4
			if rec.fe + out.d.fe >= 50 then
				out.act = if r() < 0.5 then "report" else "flee"
				face = "scared"
			elseif t.temper > 0.7 and rec.an + out.d.an >= 50 then
				out.act = "shove"
				face = "angry"
			else
				face = "wary"
			end
		end
		out.mem = { k = key }
	elseif intent == "apologize" then
		local offense = Mind.lastOf(rec, "insult") or Mind.lastOf(rec, "hit") or Mind.lastOf(rec, "provoke") or Mind.lastOf(rec, "bump") or Mind.lastOf(rec, "broken")
		local recent = offense and now - offense.t < 3 * 86400
		if st == "lover" and (rec.an > 10 or recent) then
			main = Mind.pick(Mind.sub("apologize", "lover", arch, reg), rec, now, r)
			out.d.an, out.d.tr = -30, 3
		elseif rec.an > 12 or recent then
			local p = t.warm * 0.5 + (rec.tr / 100) * 0.35 + r() * 0.35 - (rec.hit or 0) * 0.15
			if Mind.countSince(rec, "apologize", now - 600) >= 2 then
				p -= 0.3 -- sorry, sorry, sorry: means nothing any more
			end
			if p > 0.5 then
				main = Mind.pick(Mind.sub("apologize", "accept", arch, reg), rec, now, r)
				out.d.an, out.d.tr, out.d.aff, out.d.fe = -38, 4, 1, -10
				face = "smile"
			else
				main = Mind.pick(Mind.sub("apologize", "cold", arch, reg), rec, now, r)
				out.d.an, out.d.fe = -14, -5
				face = "wary"
			end
			if t.hostile then
				out.act = "backoff"
			end
		else
			main = Mind.pick(Mind.sub("apologize", "none", arch, reg), rec, now, r)
			out.d.aff = 0.5
			face = "surprised"
		end
		out.mem = { k = "apologize" }
	elseif intent == "thank" then
		main = Mind.pick(Mind.bank(arch, "thank", mood, reg), rec, now, r)
		out.d.aff, out.d.tr = 1, 1
	elseif intent == "request" then
		local yes = (aff >= 22 or (t.warm > 0.7 and mood == "good") or t.authority or arch == "clerk" or arch == "tourist") and mood ~= "bad" and mood ~= "angry" and mood ~= "enemy"
		if mood == "scared" then
			main = Mind.pick(Mind.sub("request", "scared", arch, reg), rec, now, r)
		elseif yes then
			main = Mind.pick(Mind.sub("request", "yes", arch, reg), rec, now, r)
			out.d.cl, out.d.tr = 1, 1
			out.act = "help_player"
		else
			main = Mind.pick(Mind.sub("request", if mood == "angry" then "angry" else "no", arch, reg), rec, now, r)
		end
	elseif intent == "comfort" then
		main = Mind.pick(Mind.bank(arch, "comfort", mood, reg), rec, now, r)
		if mood == "good" or mood == "neutral" or mood == "lover" then
			out.d.aff, out.d.tr, out.d.cl = 2, 2, 1
		end
	elseif intent == "invite" then
		main = Mind.pick(Mind.bank(arch, "invite", mood, reg), rec, now, r)
		if mood == "good" or mood == "lover" or (mood == "neutral" and aff >= 20) then
			out.act = "meet_menu"
		end
	elseif intent == "gift_r" or intent == "food_r" or intent == "money_r" or intent == "play_r" or intent == "meet_r" or intent == "hit_r" then
		local key = req.outcome or "neutral"
		vars.item = req.itemName or vars.item or "선물"
		vars.money = req.moneyText or ""
		vars.kind = req.kindName or ""
		vars.place = req.placeName or vars.place
		main = Mind.pick(Mind.sub(intent, key, arch, reg), rec, now, r) or Mind.pick(Mind.sub(intent, "neutral", arch, reg), rec, now, r)
		local FACE_R = { love = "love", like = "smile", happy = "laugh", greedy = "smug", neutral = "smile", dislike = "annoyed", refuse = "wary", much = "surprised", nomoney = "smug", full = "smile", awkward = "surprised", insulted = "annoyed", bribe = "angry", rps_win = "surprised", rps_lose = "laugh", rps_tie = "laugh", selfie = "laugh", prank = "laugh", prank_bad = "annoyed", walk = "smile", yes = "smile", now = "laugh", no = "sad", minor = "smug", busy = "sad", scared = "scared", angry = "angry", fight = "angry", lover = "sad" }
		face = FACE_R[key] or face
		local EMO_R = { love = "cheer", like = "nod", happy = "cheer", greedy = "laugh", dislike = "shrug", refuse = "refuse", insulted = "turn", bribe = "point", rps_win = "startle", rps_lose = "cheer", selfie = "point", prank = "laugh", prank_bad = "cross", yes = "nod", now = "cheer", no = "refuse", scared = "startle", angry = "point", fight = "point" }
		out.emoteOverride = EMO_R[key]
	elseif intent == "yes" or intent == "no" then
		main = Mind.pick(Mind.bank(arch, intent, mood, reg), rec, now, r)
		if mood == "good" then
			out.d.cl = 0.4
		end
	elseif intent == "weather" or intent == "how" or intent == "doing" or intent == "place_q" or intent == "gift_talk" or intent == "brag" then
		main = Mind.pick(Mind.bank(arch, intent, mood, reg), rec, now, r)
		if mood == "good" or mood == "neutral" or mood == "lover" then
			out.d.aff = (out.d.aff or 0) + (if intent == "brag" then 0 else 0.6)
			out.d.cl = 0.8
		end
	else
		main = Mind.pick(Mind.bank(arch, "small", mood, reg), rec, now, r)
		if mood == "good" or mood == "lover" then
			out.d.aff = 0.5
			out.d.cl = 0.6
		end
		intent = "small"
	end
	main = main or "…"

	-- memory prefix on the first exchange
	if req.first and intent ~= "bye" then
		local m = memoryLine(c, rec, env, reg, mood)
		if m and m ~= "" then
			table.insert(out.lines, 1, Mind.fill(m, vars))
		end
	end
	if repeatPrefix then
		main = repeatPrefix .. main
	end
	table.insert(out.lines, Mind.fill(main, vars))

	-- a context tail now and then (only in a calm mood, after friendly talk)
	local calm = (mood == "good" or mood == "neutral" or mood == "lover") and CHAT_INTENTS[intent] == true and (out.d.an or 0) <= 0 and not out.act
	if calm and intent ~= "yes" and intent ~= "no" and not repeatPrefix and r() < 0.28 then
		local tl = tailLine(rec, env, reg)
		if tl then
			out.lines[#out.lines] ..= " " .. Mind.fill(tl, vars)
		end
	end
	-- a question back (keeps the conversation going)
	if calm and req.chan ~= "text" and r() < t.chatty * 0.32 then
		local ask = askBack(c, rec, env, reg, mood, aff)
		if ask then
			table.insert(out.lines, Mind.fill(ask.text, vars))
			out.ask = { kind = ask.kind, chips = ask.chips }
		end
	end

	-- voice + dialect
	local upset = face == "sad" or face == "angry" or face == "scared" or face == "annoyed" or mood == "angry" or mood == "scared" or mood == "enemy"
	for i, s in out.lines do
		local v = Mind.voice(s, arch, r, upset)
		if c.speech == "busan" then
			v = Mind.dialect(v, reg, r)
		end
		out.lines[i] = v
	end

	out.face = if sub == "guard" then "smug" else face
	local em = INTENT_EMOTE[intent]
	out.emote = out.emoteOverride or (em and (em[sub or ""] or em[emoteKey] or em[mood])) or nil
	out.emoteOverride = nil
	out.intent = intent
	if not out.mem then
		out.mem = { k = "talk", x = intent }
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- NPC-initiated openers (걸렁뱅이 시비, 동네바보 장난, 노숙자 천원만, 경찰 질문, a chatty person)
-------------------------------------------------------------------------------------------------
-- kind: punk | punk_toss | fool | fool_weird | fool_back | fool_bump | beg | police | chatty | thug | friend
function Mind.opener(c: any, rec: any, kind: string, env: any): any
	local r = rndOf(env)
	local now = env.now or os.time()
	local t = Mind.traits(c)
	local arch = t.arch
	local aff = env.aff or 0
	local mood = Mind.mood(c, rec, aff, env)
	local reg = Mind.register(c, rec, aff)
	local vars = env.vars or {}
	env.vars = vars
	vars.you = env.you or "친구"
	vars.me = c.name or "?"
	local out = { lines = {}, d = D(), mood = mood, stage = Mind.stage(rec, aff), reg = reg, opener = kind }
	local main
	if kind == "punk" or kind == "thug" then
		if mood == "good" or mood == "lover" then
			main = Mind.pick(Mind.bank(arch, "greet", "good", reg), rec, now, r)
			out.face, out.emote = "smile", "wave"
		else
			main = Mind.pick(Mind.sub("open", "any", arch, reg), rec, now, r)
			out.face, out.emote = if mood == "angry" or mood == "enemy" then "angry" else "smug", "point"
			out.ask = { kind = kind, chips = Lines and Lines.ASK[kind] and Lines.ASK[kind].chips or nil }
			if r() < 0.45 and Lines then
				local follow = Mind.pick(listOf(Lines.ASK[kind], reg), rec, now, r)
				if follow then
					table.insert(out.lines, Mind.fill(main or "", vars))
					main = follow
				end
			end
		end
	elseif kind == "punk_toss" then
		main = Mind.pick(Mind.sub("open_toss", "any", arch, reg), rec, now, r)
		out.face, out.emote = "smug", "look"
	elseif kind == "fool" or kind == "fool_weird" then
		main = Mind.pick(Mind.sub(if kind == "fool" then "open" else "weird", "any", "fool", "c"), rec, now, r)
		out.face, out.emote = "laugh", if kind == "fool" then "wave" else "point"
		if kind == "fool" then
			out.ask = { kind = "fool", chips = Lines and Lines.ASK.fool.chips }
		end
	elseif kind == "fool_back" or kind == "fool_runaway" or kind == "fool_stare" or kind == "fool_follow" or kind == "fool_block" or kind == "fool_bump" then
		local key = string.sub(kind, 6)
		if key == "bump" then
			key = "bumped"
		end
		main = Mind.pick(Mind.sub(key, "any", "fool", "c"), rec, now, r)
		out.face = if key == "stare" then "neutral" else "laugh"
		out.emote = if key == "runaway" then "laugh" elseif key == "block" then "dance" else "point"
		if key == "bumped" then
			out.ask = { kind = "foolbump", chips = { "ㅋㅋ 괜찮아요", "야! 조심 좀 해!", "(무시한다)" } }
		end
	elseif kind == "beg" then
		main = Mind.pick(Lines and listOf(Lines.ASK.beg, "p"), rec, now, r)
		out.face, out.emote = "sad", "shy"
		out.ask = { kind = "beg", chips = Lines and Lines.ASK.beg.chips }
	elseif kind == "police" then
		main = Mind.pick(Lines and listOf(Lines.ASK.police, "p"), rec, now, r)
		out.face, out.emote = "wary", "point"
		out.ask = { kind = "police", chips = Lines and Lines.ASK.police.chips }
	elseif kind == "friend" then
		main = Mind.pick(Mind.bank(arch, "greet", if mood == "lover" then "lover" else "good", reg), rec, now, r)
		out.face, out.emote = if mood == "lover" then "love" else "smile", "wave"
	else
		main = Mind.pick(Mind.bank(arch, "greet", mood, reg), rec, now, r)
		out.face, out.emote = "smile", "wave"
		if Lines then
			local ask = askBack(c, rec, env, reg, mood, aff)
			if ask then
				table.insert(out.lines, Mind.fill(main or "", vars))
				main = ask.text
				out.ask = { kind = ask.kind, chips = ask.chips }
			end
		end
	end
	table.insert(out.lines, Mind.fill(main or "…", vars))
	for i, s in out.lines do
		local v = Mind.voice(s, arch, r)
		if c.speech == "busan" then
			v = Mind.dialect(v, reg, r)
		end
		out.lines[i] = v
	end
	out.mem = { k = "met", x = kind }
	return out
end

-- one line of a kind for street behaviours (ignore / backoff / escalate / stare / ...)
function Mind.line(c: any, key: string, env: any, rec: any?): string?
	local r = rndOf(env)
	local t = Mind.traits(c)
	local reg = if rec then Mind.register(c, rec, env.aff or 0) else (if t.banmal then "c" else "p")
	local l = Mind.sub(key, "any", t.arch, reg)
	local s = Mind.pick(l, rec, env.now or os.time(), r)
	if not s then
		return nil
	end
	local vars = env.vars or { you = env.you or "친구", me = c.name }
	s = Mind.voice(Mind.fill(s, vars), t.arch, r)
	if c.speech == "busan" then
		s = Mind.dialect(s, reg, r)
	end
	return s
end

-- what the PLAYER says for a chip (their own bubble)
function Mind.playerLine(intent: string, close: boolean, vars: any?, rnd: (() -> number)?): string
	local P = Lines and Lines.PLAYER and Lines.PLAYER[intent]
	if not P then
		return Mind.INTENT_LABEL[intent] or "…"
	end
	local list = listOf(P, if close then "c" else "p")
	local r = rnd or math.random
	local s = list and list[1 + math.floor(r() * #list)] or "…"
	return Mind.fill(s, vars or {})
end

-------------------------------------------------------------------------------------------------
-- NPC <-> NPC scenes: which scene a pair plays (a = the first speaker)
-------------------------------------------------------------------------------------------------
function Mind.scenePair(ca: any, cb: any, rel: any?, rnd: (() -> number)?): (string?, any, any)
	local r = rnd or math.random
	local A, B = Mind.archOf(ca), Mind.archOf(cb)
	local function either(x: string): (boolean, any, any)
		if A == x then
			return true, ca, cb
		elseif B == x then
			return true, cb, ca
		end
		return false, ca, cb
	end
	if rel and rel.couple then
		return "couple", ca, cb
	end
	if A == "drunk" and B == "drunk" then
		return (if r() < 0.5 then "drunkfight" else "drunk"), ca, cb
	end
	local ok, x, y = either("police")
	if ok and Mind.archOf(y) ~= "police" then
		return "police", x, y
	end
	ok, x, y = either("fool")
	if ok then
		return "fool", x, y
	end
	ok, x, y = either("punk")
	if ok and not (rel and rel.friends) then
		return "punk", x, y
	end
	ok, x, y = either("thug")
	if ok and (Mind.archOf(y) == "thug" or (rel and rel.friends)) then
		return "thug", x, y
	end
	ok, x, y = either("drunk")
	if ok then
		return "drunk", x, y
	end
	ok, x, y = either("homeless")
	if ok then
		return "beg", x, y
	end
	ok, x, y = either("clerk")
	if not ok then
		ok, x, y = either("parttimer")
	end
	if ok and rel and rel.atWork then
		-- the clerk is "b" in the clerk scenes (the customer speaks first)
		return "clerk", y, x
	end
	ok, x, y = either("rich")
	if ok and (Mind.archOf(y) == "clerk" or Mind.archOf(y) == "parttimer") then
		return "rich", x, y
	end
	ok, x, y = either("tourist")
	if ok and Mind.archOf(y) ~= "tourist" then
		return "tourist", x, y
	end
	ok, x, y = either("elder")
	if ok and (Mind.archOf(y) == "student" or Mind.archOf(y) == "parttimer") then
		return "elder", x, y
	end
	if rel and rel.friends then
		return "friends", ca, cb
	end
	return "strangers", ca, cb
end

function Mind.scene(key: string, rnd: (() -> number)?): { any }?
	local list = Lines and Lines.SCENES[key]
	if not list or #list == 0 then
		return nil
	end
	local r = rnd or math.random
	return list[1 + math.floor(r() * #list)]
end

-------------------------------------------------------------------------------------------------
-- Witnesses: how somebody reacts to trouble nearby (severity 1 = shouting, 2 = a shove, 3 = a hit)
-------------------------------------------------------------------------------------------------
function Mind.witness(c: any, severity: number, rnd: (() -> number)?): string
	local r = rnd or math.random
	local t = Mind.traits(c)
	local arch = t.arch
	if arch == "police" then
		return "police"
	elseif arch == "thug" then
		return if r() < 0.6 then "gang" else "watch"
	elseif arch == "punk" then
		return if r() < 0.5 then "cheer" elseif r() < 0.5 then "film" else "watch"
	elseif arch == "fool" then
		return if r() < 0.6 then "cheer" else "watch"
	elseif arch == "drunk" then
		return if r() < 0.5 then "watch" else "cheer"
	end
	local x = r()
	local fear = (1 - t.brave) * 0.5 + severity * 0.12
	if x < fear then
		return "flee"
	end
	x -= fear
	if severity >= 2 and x < 0.18 + (if arch == "office" or arch == "rich" or arch == "elder" or arch == "clerk" then 0.12 else 0) then
		return "report"
	end
	x -= 0.18
	if x < 0.16 and (arch == "student" or arch == "parttimer" or arch == "tourist") then
		return "film"
	end
	if x < 0.24 and t.brave > 0.55 and t.warm > 0.5 then
		return "stop"
	end
	return "watch"
end

-------------------------------------------------------------------------------------------------
-- Crime + police: wanted stars for what the player did, fines
-------------------------------------------------------------------------------------------------
Mind.CRIMES = {
	insult_police = { stars = 1, label = "경찰관 모욕" },
	threat = { stars = 1, label = "협박" },
	shove = { stars = 1, label = "시비 · 몸싸움" },
	assault = { stars = 2, label = "폭행" },
	assault_police = { stars = 3, label = "경찰관 폭행" },
	bribe = { stars = 1, label = "뇌물 공여" },
	flee = { stars = 1, label = "도주" },
	bumps = { stars = 1, label = "연쇄 어깨빵" },
}
Mind.FINE = { 0, 30000, 70000, 150000, 300000, 500000 }
function Mind.fineFor(stars: number): number
	return Mind.FINE[math.clamp(math.floor(stars), 0, 5) + 1]
end

function Mind.won(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out .. "원"
end

function Mind.policeLine(kind: string, vars: any?, rnd: (() -> number)?): string
	local list = Lines and Lines.POLICE[kind]
	if not list then
		return "…"
	end
	local r = rnd or math.random
	return Mind.fill(list[1 + math.floor(r() * #list)], vars or {})
end

function Mind.witnessLine(kind: string, rnd: (() -> number)?): string?
	local list = Lines and Lines.WITNESS[kind]
	if not list then
		return nil
	end
	local r = rnd or math.random
	return list[1 + math.floor(r() * #list)]
end

-- the chips the conversation bar offers right now (context-aware: stage, arch, pending question)
-- 걸렁뱅이 돈 요구 (GwangalliGameplay.Mind: an approach turns into a demand; no money / no = a fight)
Mind.DEMAND = {
	ask = { "야, 너 돈 좀 있냐? {money}만 빌려 줘. 금방 갚을게 ㅋ", "형이 오늘 좀 급해서 그래. {money}만 줘 봐.", "지나가려면 통행료 내야지? {money}.", "{money}만 줘. 그럼 조용히 보내 줄게 ㅋ" },
	again = { "돈 있냐고 묻잖아. 귀 먹었냐?", "말 돌리지 말고. {money}.", "어허, 대답 안 하네? {money} 내놔." },
	paid = { "오~ 착하네 ㅋ 다음에도 부탁한다~", "ㅋㅋ 말 잘 듣네. 가 봐.", "그래 이래야 서로 편하지. 잘 가라~" },
	nomoney = { "야, 없잖아? 장난하냐? 이리 와 봐.", "돈도 없으면서 뭘 준다는 거야? 맞자.", "주머니 털어도 안 나오네? 그럼 몸으로 때워야지." },
	refuse = { "싫어? 이게 미쳤나. 한번 맞아 볼래?", "없다고? 그럼 맞아야지 ㅋ", "오냐, 오늘 제대로 걸렸다.", "돈 없으면 맞고 가는 거다." },
	insult = { "뭐? 이게 진짜 죽고 싶나!", "말 다 했냐? 덤벼!" },
	sorry = { "미안하면 돈으로 보여 줘야지?", "말로만? {money} 내놓으면 봐준다." },
	chips = { "💵 여기요, 드릴게요", "돈 없어요", "싫은데요", "죄송해요…" },
}
Mind.DEMAND_AMOUNTS = { 5000, 10000, 10000, 20000 }

Mind.CHIPS = {
	{ id = "greet", label = "👋 인사" },
	{ id = "ask", label = "❓ 질문", sub = { "how", "doing", "name", "age", "job", "food_q", "like_q", "hobby_q", "place_q", "news_q", "number" } },
	{ id = "joke", label = "😂 농담" },
	{ id = "compliment", label = "😊 칭찬" },
	{ id = "talkabout", label = "💬 이야기", sub = { "food_talk", "gift_talk", "weather", "comfort", "brag", "flirt" } },
	{ id = "request", label = "🤝 부탁" },
	{ id = "apologize", label = "🙏 사과" },
	{ id = "gift", label = "🎁 선물" },
	{ id = "food", label = "🍢 음식 사주기" },
	{ id = "money", label = "💵 돈 주기" },
	{ id = "play", label = "🎮 같이 놀기" },
	{ id = "meet", label = "📅 약속 잡기" },
	{ id = "confess", label = "💘 고백" },
	{ id = "insult", label = "🤬 욕하기" },
	{ id = "provoke", label = "😠 시비 걸기" },
	{ id = "hit", label = "👊 때리기" },
	{ id = "bye", label = "👋 작별" },
}
Mind.PLAY = {
	{ id = "rps", label = "✊ 가위바위보" },
	{ id = "selfie", label = "📸 같이 셀카" },
	{ id = "walk", label = "🚶 같이 다니기" },
	{ id = "prank", label = "😜 장난치기" },
}
Mind.MONEY = { 1000, 5000, 10000, 50000 }
Mind.MEET = {
	{ id = "meal", label = "🍔 같이 밥 먹기" },
	{ id = "walk", label = "🌉 광안리에서 만나기" },
	{ id = "pocha", label = "🍶 포차에서 한잔" },
	{ id = "billiards", label = "🎱 당구장 가기" },
	{ id = "cafe", label = "☕ 카페 가기" },
	{ id = "karaoke", label = "🎤 코노 가기" },
	{ id = "bowling", label = "🎳 볼링 치기" },
	{ id = "club", label = "🎶 클럽 가기" },
	{ id = "now", label = "🚶 지금 같이 다니기" },
}

-- unit-test helper: every intent composes for every archetype and mood without errors
function Mind.selfTest(rnd: (() -> number)?): { string }
	local problems = {}
	if not Lines then
		return { "GwangalliMindLines missing" }
	end
	local fake = { id = "t", name = "테스트", age = 30, job = "테스터", persona = "uni", speech = "busan", love = { "tteokbokki" }, topics = { "food" } }
	for arch in Mind.ARCH do
		for intent in Mind.INTENT_LABEL do
			for _, aff in { 0, 30, 60, 90 } do
				local c = table.clone(fake)
				c.id = "t_" .. arch .. intent .. aff
				local typeOf = { police = "police", homeless = "beggar", punk = "punk", thug = "thug", fool = "fool", drunk = "drunk", rich = "rich", hothead = "violent" }
				c.type = typeOf[arch]
				local per = { student = "uni", office = "office", tourist = "tourist", elder = "grandma", clerk = "barista", parttimer = "clerk" }
				c.persona = per[arch] or "uni"
				local rec = Mind.newRec(c, 1000)
				local ok, res = pcall(Mind.respond, c, rec, { intent = intent, first = true, text = "테스트야", polite = false }, { now = 1000, aff = aff, you = "플레이어", rnd = rnd, tod = "evening", weather = "rain", areaKind = "beach" })
				if not ok then
					table.insert(problems, string.format("%s/%s/%d: %s", arch, intent, aff, tostring(res)))
				elseif type(res.lines) ~= "table" or #res.lines == 0 or res.lines[#res.lines] == "" then
					table.insert(problems, string.format("%s/%s/%d: empty", arch, intent, aff))
				else
					for _, l in res.lines do
						if string.find(l, "{", 1, true) then
							table.insert(problems, string.format("%s/%s: unfilled %s", arch, intent, l))
						end
					end
				end
			end
		end
	end
	return problems
end

return Mind
