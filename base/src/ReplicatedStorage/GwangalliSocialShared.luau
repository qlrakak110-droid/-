-- GwangalliSocialShared: data + PURE helpers for the 호감도 / 친구 system (owner: npc_social).
-- Used by the server (ServerScriptService.GwangalliGameplay.Relationships), the street-life client,
-- the key-NPC dialogs, the club and the homes code. No instances are created and no Roblox globals
-- are touched at require time (Lune unit tests load it directly).
--
-- TIERS (affinity 0..100 per NPC per player):
--   1 모르는 사이 (0)  2 아는 사이 (20)  3 친한 사이 (50)  4 친구 (75)  5 절친 (95)
--   Social.tierOf(affinity) -> tierIndex, tierDef
--
-- REMOTES (Folder ReplicatedStorage.GwangalliSocial, created by the server; clients WaitForChild with
-- a timeout):
--   SocialAction RemoteEvent client -> server (citizenId: string, action: string, payload: table?)
--     "greet"     {pos?}                 quick 말 걸기 bubble: +daily greet, reply = SocialState "line"
--     "talk"      {pos?}                 opens the full conversation (Dialog remote; key NPC ids open
--                                        their own dialog, which embeds the "soc:" choices)
--     "reply"     {choice = 1..3}        answers the pending question of that NPC (custom UIs; the
--                                        Dialog overlay sends dialogChoice "soc:r:<n>" instead)
--     "compliment" {pos?}                칭찬하기: +compliment once per NPC per game day (the persona
--                                        decides: love / like / neutral / meh / dislike)
--     "number"    {pos?}                 번호 물어보기 (>= 아는 사이): yes -> a phone contact (call / texts /
--                                        club invitations); 친한 사이+ always say yes; a no = ask
--                                        again the next game day
--     "gift"      {gift = giftId, pos?}  buys the gift through the ledger (cash, then check card)
--     "invite"    {kind = inviteKind, pos?}   see Social.INVITES
--     "hangout"   {op = "start"|"call"|"stop", pos?}   friend companion (start in person >= 친한 사이,
--                                        call by phone >= 친구)
--     "dance"     {pos?}                 in the club with the companion / a citizen who is at the club
--     "drink"     {pos?}                 buy them a drink (club zone or with the companion at a bar)
--     "errand"    {op = "accept"|"decline"|"done"}
--     "bday"      {pos?}                 생일 축하 (only on their birthday)
--     "call"      {}                     phone call (>= 친한 사이 with the number) -> Dialog remote=true
--     "textReply" {msg = id, choice = "accept"|"decline"}   answer a text invitation
--     "dismiss"   {}                     send the companion home
--   (pos = the client-side position of a roaming citizen (Vector3); key NPCs use their server position)
--   SocialState  RemoteEvent server -> client, one table per event, field `kind`:
--     "snapshot"  full state (see Relationships.snapshot)            "affinity" {id, a, delta, tier, source, reason}
--     "tier"      {id, from, to, up, text}                           "line"     {id, text, emote, tier, a}
--     "companion" {id | false, name?, tier?, state?, dest?, until?}  "text"     {msg = inbox message}
--     "errand"    {id, stage, text?, dest?, untilIn?}                "promise"  {id, kind, dest, untilIn, state}
--     "event"     {id, event, text}  (bestie / birthday / housewarming / friend)
--     "contact"   {id, name, added = true, via = "ask" | "tier"}  a new phone contact (number exchanged)
--   GetSocial    RemoteFunction client -> server () -> snapshot (nil while loading)
-- SERVER API: BindableFunction ServerStorage.GwangalliSocialAPI:Invoke(method, player, ...) — see
--   Relationships.luau (award / joint / affinity / tier / isFriend / friends / companion / perk /
--   greeting / smallTalk / menuChoice / choices / handleChoice / snapshot / openDialog).
-- PLAYER ATTRIBUTES (server-set): GwangalliCompanion = citizenId | "" (replicates: every client can
--   draw the companion), GwangalliCompanionTier = 0..5, GwangalliSocialReady = true once loaded.

local Social = {}

Social.VERSION = 1
Social.Folder = "GwangalliSocial"
Social.Remote = { Action = "SocialAction", State = "SocialState", Get = "GetSocial" }
Social.API_NAME = "GwangalliSocialAPI"
Social.Attr = {
	Companion = "GwangalliCompanion",
	CompanionTier = "GwangalliCompanionTier",
	Ready = "GwangalliSocialReady",
}
-- Fallback persistence (used only while the Profiles module does not keep `social` itself).
Social.DATASTORE = "GwangalliSocial_v1"
Social.KEY_PREFIX = "u_"

Social.MAX = 100
Social.MAX_RECORDS = 160 -- NPC records kept per player (lowest affinity dropped beyond)
Social.INBOX_MAX = 20

Social.ACTIONS = {
	greet = true,
	talk = true,
	reply = true,
	gift = true,
	invite = true,
	hangout = true,
	dance = true,
	drink = true,
	errand = true,
	bday = true,
	call = true,
	textReply = true,
	dismiss = true,
	compliment = true,
	number = true,
}

-------------------------------------------------------------------------------------------------
-- Tiers
-------------------------------------------------------------------------------------------------
Social.TIERS = {
	{ id = "stranger", name = "모르는 사이", min = 0, icon = "🤍", color = { 190, 190, 200 }, perks = "처음 만났어요. 먼저 인사해 볼까요?" },
	{ id = "acquaintance", name = "아는 사이", min = 20, icon = "💛", color = { 255, 214, 90 }, perks = "이름을 기억하고 반갑게 인사해요" },
	{ id = "close", name = "친한 사이", min = 50, icon = "🧡", color = { 255, 150, 60 }, perks = "연락처 교환 · 같이 다니기 · 속마음 이야기" },
	{ id = "friend", name = "친구", min = 75, icon = "💖", color = { 255, 105, 160 }, perks = "전화로 불러내기 · 일터 10% 할인 · 클럽 입장 도움 · 꿀팁" },
	{ id = "bestie", name = "절친", min = 95, icon = "💞", color = { 230, 70, 200 }, perks = "20% 할인 · VIP 테이블 할인 · 특별 이벤트" },
}
Social.TIER_STRANGER, Social.TIER_ACQ, Social.TIER_CLOSE, Social.TIER_FRIEND, Social.TIER_BESTIE = 1, 2, 3, 4, 5

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
Social.isNum = isNum

function Social.clampA(v: any): number
	if not isNum(v) then
		return 0
	end
	return math.clamp(math.floor(v * 10 + 0.5) / 10, 0, Social.MAX)
end

function Social.tierOf(a: any): (number, any)
	local v = Social.clampA(a)
	local idx = 1
	for i, t in Social.TIERS do
		if v >= t.min then
			idx = i
		end
	end
	return idx, Social.TIERS[idx]
end

function Social.tierMin(idx: number): number
	local t = Social.TIERS[math.clamp(idx, 1, #Social.TIERS)]
	return t.min
end

-- Progress inside the current tier (0..1) and the affinity needed for the next one (nil at 절친).
function Social.tierProgress(a: any): (number, number?)
	local v = Social.clampA(a)
	local idx = Social.tierOf(v)
	local lo = Social.TIERS[idx].min
	local nxt = Social.TIERS[idx + 1]
	if not nxt then
		return 1, nil
	end
	return math.clamp((v - lo) / (nxt.min - lo), 0, 1), nxt.min
end

-------------------------------------------------------------------------------------------------
-- Days. Game day = one in-game day (G.DAY_SECONDS = 1440 real seconds); real day = KST calendar day.
-------------------------------------------------------------------------------------------------
Social.GAME_DAY_SECONDS = 1440
Social.KST = 9 * 3600

function Social.gameDay(unix: number): number
	return math.floor(unix / Social.GAME_DAY_SECONDS)
end

function Social.realDay(unix: number): number
	return math.floor((unix + Social.KST) / 86400)
end

-- KST calendar date: month, day, year
function Social.kstDate(unix: number): (number, number, number)
	local t = os.date("!*t", math.floor(unix + Social.KST)) :: any
	return t.month, t.day, t.year
end

-------------------------------------------------------------------------------------------------
-- Affinity sources. base = default amount; max = rewarded times per NPC per game day (later ones
-- give 0); dim = multiplier for the 1st, 2nd, ... time that game day (default DIM); nocap = not
-- limited by the daily caps. Negative sources are never capped (floor 0).
-------------------------------------------------------------------------------------------------
Social.DIM = { 1, 0.6, 0.35, 0.2 }
Social.GAME_DAY_CAP = 15 -- max positive affinity per NPC per game day (24 real minutes; one full chat + gift fits)
Social.REAL_DAY_CAP = 30 -- max positive affinity per NPC per real (KST) day
Social.UPSET_SECONDS = 600 -- after a rude reply positive gains are halved this long
Social.FRIEND_FORGIVE = 0.75 -- friends (>= 친구) take rude replies a bit less hard

Social.SOURCES = {
	-- conversation
	greet = { base = 1, max = 2, label = "인사" },
	chat = { base = 3, max = 1, label = "수다" },
	reply = { base = 1, max = 3, label = "대화" }, -- amount from the reply outcome (REPLY_GAIN)
	call = { base = 1, max = 1, label = "통화" },
	compliment = { base = 2, max = 1, label = "칭찬" }, -- amount from COMPLIMENT_GAIN
	number = { base = 2, max = 1, label = "번호 교환" },
	intro = { base = 3, max = 1, label = "친구의 친구" }, -- first meeting with a friend of someone you are close to (once per NPC)
	-- gifts / help
	gift = { base = 3, max = 3, dim = { 1, 0.5, 0.25 }, label = "선물" }, -- amount from Social.giftGain
	errand = { base = 6, max = 1, label = "부탁 들어주기" },
	visit = { base = 2, max = 1, label = "일터 방문" },
	-- plans / time together
	invite = { base = 2, max = 1, label = "약속 잡기" },
	promise = { base = 5, max = 2, label = "약속 지킴" },
	hangout = { base = 1, max = 4, label = "같이 놀기" },
	club = { base = 4, max = 1, label = "클럽에서 만남" },
	dance = { base = 3, max = 2, label = "같이 춤" },
	drink = { base = 4, max = 1, label = "음료 삼" },
	table = { base = 5, max = 1, label = "테이블 합석" },
	beach = { base = 2, max = 1, label = "바다 산책" },
	meal = { base = 3, max = 1, label = "같이 밥" },
	cafe = { base = 2, max = 1, label = "카페 데이트" },
	karaoke = { base = 3, max = 1, label = "코노" },
	bowling = { base = 3, max = 1, label = "볼링" },
	home = { base = 5, max = 1, label = "집에 초대" },
	housewarming = { base = 10, max = 1, label = "집들이", nocap = true },
	bday = { base = 10, max = 1, label = "생일 축하", nocap = true },
	bestie = { base = 3, max = 1, label = "절친 이벤트" },
	job = { base = 1, max = 3, label = "함께 일함" },
	api = { base = 2, max = 3, label = "함께한 시간" }, -- generic joint activity (club / homes / NPC code)
	-- negative
	rude = { base = -8, label = "무례한 말" },
	bump = { base = -4, label = "어깨빵" }, -- the player shoulder-bumped this person (knockdown: amount -6)
	laughoff = { base = 3, max = 2, label = "웃어넘김" }, -- laughed off the 동네바보's bump
	give = { base = 4, max = 3, dim = { 1, 0.6, 0.3 }, label = "천원 적선" }, -- gave the 걸렁뱅이 some cash
	chatty = { base = 2, max = 2, label = "먼저 말 걸어 준 사람" }, -- answered someone who came up to talk

	dislike = { base = -3, label = "싫어하는 이야기" },
	giftbad = { base = -3, label = "싫어하는 선물" },
	broken = { base = -6, label = "약속 어김" },
	spam = { base = -2, label = "귀찮게 함" },
	errandfail = { base = -2, label = "부탁 잊음" },
}

-- Reply outcomes (see GwangalliCitizens.react): affinity for the "reply" source / negative sources.
Social.REPLY_GAIN = { love = 4, like = 2, neutral = 1, meh = 0 }
Social.REPLY_NEG = { dislike = "dislike", rude = "rude" }
-- Compliment outcomes (GwangalliCitizens.react(id, "compliment")): "compliment" amount; dislike -> the
-- "dislike" source (a persona that finds flattery fake).
Social.COMPLIMENT_GAIN = { love = 3, like = 2, neutral = 1, meh = 0 }

-- Gains are easier while strangers and slower near the top.
function Social.tierMult(a: number): number
	if a >= 90 then
		return 0.5
	elseif a >= 75 then
		return 0.7
	elseif a < 20 then
		return 1.2
	end
	return 1
end

-------------------------------------------------------------------------------------------------
-- Records. One per NPC the player has met (short keys keep the saved profile small):
--   a affinity  met meetings  first/last unix  u last change (merge key)  la last area  lx last
--   activity  lg last gift  pk highest tier reached  gd/gg/n game-day key, gain, counts per source
--   rd/rg real-day key, gain  dk decay applied for the current absence  up upset until (unix)
--   f flags {number, bdayKnown, bdayYear, bestieEvent, housewarm, secret, ...}  gk known gift
--   reactions {giftId = reaction}  pr promise {kind, dest, due, made}  er errand {id, stage, due, ...}
-------------------------------------------------------------------------------------------------
function Social.newRecord(now: number, start: number?, grudge: number?): any
	local a = Social.clampA(start or 0)
	return {
		a = a,
		gr = math.clamp(if isNum(grudge) then grudge :: number else 0, 0, Social.GRUDGE_MAX), -- below-zero affinity (see Social.award)
		met = 0,
		first = 0,
		last = 0,
		u = now,
		la = "",
		lx = "",
		lg = "",
		pk = (Social.tierOf(a)),
		gd = 0,
		gg = 0,
		n = {},
		rd = 0,
		rg = 0,
		dk = 0,
		up = 0,
		f = {},
		gk = {},
	}
end

-- starts: { [npcId] = starting affinity } (e.g. 민지 / 준호 are already friendly)
function Social.newState(now: number, starts: { [string]: number }?): any
	-- u = 0: a fresh state never wins a merge against real saved data (records carry their own u)
	local st = { v = Social.VERSION, u = 0, npcs = {}, inbox = {}, nextMsg = 1, stats = { gifts = 0, dances = 0, errands = 0, friends = 0 }, ext = nil }
	for id, a in starts or {} do
		if type(id) == "string" and isNum(a) then
			st.npcs[id] = Social.newRecord(now, a)
		end
	end
	return st
end

-- New game day / real day: reset the counters.
function Social.roll(rec: any, now: number)
	local gd = Social.gameDay(now)
	if rec.gd ~= gd then
		rec.gd = gd
		rec.gg = 0
		rec.n = {}
	end
	local rd = Social.realDay(now)
	if rec.rd ~= rd then
		rec.rd = rd
		rec.rg = 0
	end
end

Social.DECAY_GRACE_DAYS = 7
Social.DECAY_MAX = 15

-- Lazy neglect decay: after DECAY_GRACE_DAYS real days without meeting, -1 per extra day (at most
-- DECAY_MAX per absence). 친한 사이+ never falls below 50, 아는 사이 never below 20 by neglect alone.
-- Returns the affinity lost now.
function Social.decay(rec: any, now: number): number
	if (rec.last or 0) <= 0 then
		return 0
	end
	local days = math.floor((now - rec.last) / 86400)
	local due = math.clamp(days - Social.DECAY_GRACE_DAYS, 0, Social.DECAY_MAX)
	local todo = due - (rec.dk or 0)
	if todo <= 0 then
		return 0
	end
	rec.dk = due
	local floor = if rec.a >= 50 then 50 elseif rec.a >= 20 then 20 else rec.a
	local before = rec.a
	rec.a = Social.clampA(math.max(floor, rec.a - todo))
	return before - rec.a
end

-- Computes and applies one affinity change. opts = { amount?, mult?, nocap? }.
-- Returns result { delta, before, after, tierFrom, tierTo, reason? }  (reason: "limit" | "cap" | "bad")
function Social.award(rec: any, source: string, now: number, opts: any?): any
	local o = opts or {}
	local def = Social.SOURCES[source]
	local before = rec.a
	local tierFrom = Social.tierOf(before)
	local function result(delta: number, reason: string?): any
		return { delta = delta, before = before, after = rec.a, tierFrom = tierFrom, tierTo = (Social.tierOf(rec.a)), reason = reason, source = source }
	end
	if not def then
		return result(0, "bad")
	end
	Social.roll(rec, now)
	local amount = if isNum(o.amount) then o.amount else def.base
	local mult = if isNum(o.mult) then math.max(0, o.mult) else 1
	if amount < 0 then
		local d = amount * mult
		if source == "rude" and before >= Social.TIERS[Social.TIER_FRIEND].min then
			d *= Social.FRIEND_FORGIVE
		end
		-- below zero: people who can hold a grudge (opts.grudgeCap, e.g. 폭력적인 NPC) remember it
		local gcap = if isNum(o.grudgeCap) then math.clamp(o.grudgeCap, 0, Social.GRUDGE_MAX) else 0
		if gcap > 0 and before + d < 0 then
			rec.gr = math.min(gcap, (rec.gr or 0) - (before + d))
		end
		rec.a = Social.clampA(before + d)
		if source == "rude" then
			rec.up = now + Social.UPSET_SECONDS
		end
		rec.u = now
		return result(rec.a - before)
	end
	local count = rec.n[source] or 0
	if def.max and count >= def.max then
		return result(0, "limit")
	end
	local dimf = (def.dim or Social.DIM)[count + 1] or 0
	local d = amount * dimf * mult * Social.tierMult(before)
	if (rec.up or 0) > now then
		d *= 0.5
	end
	rec.n[source] = count + 1
	local nocap = o.nocap == true or def.nocap == true
	if not nocap then
		local room = math.min(Social.GAME_DAY_CAP - (rec.gg or 0), Social.REAL_DAY_CAP - (rec.rg or 0))
		if room <= 0 then
			return result(0, "cap")
		end
		d = math.min(d, room)
	end
	d = math.floor(d * 10 + 0.5) / 10
	if d <= 0 then
		return result(0, if nocap then nil else "cap")
	end
	-- a grudge (affinity below zero) is paid off first: the gain counts toward the daily caps but
	-- the visible affinity only rises once the grudge is gone
	local gr = rec.gr or 0
	if gr > 0 then
		local pay = math.min(gr, d)
		rec.gr = math.floor((gr - pay) * 10 + 0.5) / 10
		d -= pay
		if not nocap then
			rec.gg = (rec.gg or 0) + pay
			rec.rg = (rec.rg or 0) + pay
		end
		if d <= 0 then
			rec.u = now
			return result(0, "grudge")
		end
	end
	rec.a = Social.clampA(before + d)
	local applied = rec.a - before
	if not nocap then
		rec.gg = (rec.gg or 0) + applied
		rec.rg = (rec.rg or 0) + applied
	end
	if rec.a > before then
		rec.pk = math.max(rec.pk or 1, (Social.tierOf(rec.a)))
	end
	rec.u = now
	return result(applied)
end

-- Room left under the daily caps (for UI hints).
function Social.capLeft(rec: any, now: number): number
	Social.roll(rec, now)
	return math.max(0, math.min(Social.GAME_DAY_CAP - (rec.gg or 0), Social.REAL_DAY_CAP - (rec.rg or 0)))
end

-------------------------------------------------------------------------------------------------
-- Gifts (bought through the ledger when given). cat: coffee | snack | dessert | food | flower |
-- alcohol | merch | beach | pet | luxury | game | book | health | fruit | music
-------------------------------------------------------------------------------------------------
Social.GIFT_ORDER = {
	"americano", "latte", "bungeoppang", "hotteok", "tteokbokki", "saltbread", "cake", "macaron",
	"fishcake", "tangerine", "vitamin", "rose", "bouquet", "soju", "beer", "wine", "club_tee",
	"cheer_towel", "lp", "sunscreen", "surf_wax", "cat_treat", "game_card", "book", "perfume",
}
Social.GIFTS = {
	americano = { name = "아이스 아메리카노", icon = "☕", price = 4500, cat = "coffee" },
	latte = { name = "바닐라 라떼", icon = "☕", price = 5500, cat = "coffee" },
	bungeoppang = { name = "붕어빵 한 봉지", icon = "🐟", price = 3000, cat = "snack" },
	hotteok = { name = "씨앗호떡", icon = "🥞", price = 2500, cat = "snack" },
	tteokbokki = { name = "떡볶이 & 튀김", icon = "🍢", price = 6000, cat = "snack" },
	saltbread = { name = "빵천동 소금빵", icon = "🥐", price = 4000, cat = "dessert" },
	cake = { name = "조각 케이크", icon = "🍰", price = 7500, cat = "dessert" },
	macaron = { name = "마카롱 세트", icon = "🍬", price = 9000, cat = "dessert" },
	fishcake = { name = "부산 어묵 세트", icon = "🍥", price = 12000, cat = "food" },
	tangerine = { name = "귤 한 봉지", icon = "🍊", price = 5000, cat = "fruit" },
	vitamin = { name = "비타민 음료", icon = "💊", price = 2000, cat = "health" },
	rose = { name = "장미 한 송이", icon = "🌹", price = 5000, cat = "flower" },
	bouquet = { name = "꽃다발", icon = "💐", price = 25000, cat = "flower" },
	soju = { name = "사이다 한 병", icon = "🥤", price = 3000, cat = "alcohol", adult = false }, -- (all ages: the "alcohol" key stays for the roster's likes, the items are soft drinks)
	beer = { name = "수제 에이드", icon = "🧃", price = 8000, cat = "alcohol", adult = false },
	wine = { name = "전통차 선물 세트", icon = "🍵", price = 45000, cat = "alcohol", adult = false },
	club_tee = { name = "CLUB OCEAN 굿즈 티셔츠", icon = "👕", price = 35000, cat = "merch" },
	cheer_towel = { name = "부산 야구 응원 타월", icon = "⚾", price = 15000, cat = "merch" },
	lp = { name = "바이닐 LP", icon = "💿", price = 30000, cat = "music" },
	sunscreen = { name = "선크림", icon = "🧴", price = 12000, cat = "beach" },
	surf_wax = { name = "서핑 왁스", icon = "🏄", price = 8000, cat = "beach" },
	cat_treat = { name = "고양이 간식", icon = "🐱", price = 3000, cat = "pet" },
	game_card = { name = "게임 기프트카드", icon = "🎮", price = 10000, cat = "game" },
	book = { name = "에세이 책", icon = "📚", price = 15000, cat = "book" },
	perfume = { name = "향수", icon = "🌸", price = 80000, cat = "luxury" },
}
Social.GIFT_MULT = { love = 2, like = 1.4, neutral = 1 }
Social.GIFT_AGAIN = 0.7 -- the same gift as last time
Social.GIFT_SPAM_AT = 5 -- gifts to one NPC in one game day from which it becomes 부담

-- Base value by price: cheap 3, mid 5, nice 7, luxury 9.
function Social.giftValue(giftId: string): number
	local g = Social.GIFTS[giftId]
	if not g then
		return 0
	end
	if g.price <= 3000 then
		return 3
	elseif g.price <= 10000 then
		return 5
	elseif g.price <= 30000 then
		return 7
	end
	return 9
end

-- Affinity amount for a gift reaction ("love" | "like" | "neutral" | "dislike" | "refuse").
-- Returns amount, source ("gift" | "giftbad" | nil when refused).
function Social.giftGain(giftId: string, reaction: string, sameAsLast: boolean?, birthday: boolean?): (number, string?)
	if reaction == "refuse" or not Social.GIFTS[giftId] then
		return 0, nil
	end
	if reaction == "dislike" then
		return Social.SOURCES.giftbad.base, "giftbad"
	end
	local v = Social.giftValue(giftId) * (Social.GIFT_MULT[reaction] or 1)
	if sameAsLast then
		v *= Social.GIFT_AGAIN
	end
	if birthday then
		v *= 2
	end
	return math.floor(v * 10 + 0.5) / 10, "gift"
end

-------------------------------------------------------------------------------------------------
-- Invitations. dest = Destination DisplayName (nil = decided at runtime: home / companion only).
-- source = affinity source awarded when you get there together. minTier = to even ask (lower
-- tiers politely decline).
-------------------------------------------------------------------------------------------------
Social.INVITE_ORDER = { "now", "club", "beach", "cafe", "meal", "karaoke", "bowling", "home" }
Social.INVITES = {
	now = { label = "지금 같이 다니자", icon = "🚶", minTier = 3, companion = true },
	club = { label = "클럽 가자", icon = "🎶", minTier = 1, dest = "CLUB OCEAN 광안", source = "club", evening = true },
	beach = { label = "바다 산책 가자", icon = "🌊", minTier = 2, dest = "광안리해수욕장 (중앙)", source = "beach" },
	cafe = { label = "카페 가자", icon = "☕", minTier = 2, dest = "fondx 홍미당 (아쿠아펠리스 1F)", source = "cafe" },
	meal = { label = "밥 먹으러 가자", icon = "🍔", minTier = 2, dest = "브롱스 광안리 (호메르스호텔 1F)", source = "meal" },
	karaoke = { label = "코노 가자", icon = "🎤", minTier = 3, dest = "광안 코인노래연습장", source = "karaoke" },
	bowling = { label = "볼링 치자", icon = "🎳", minTier = 3, dest = "광안 락볼링클럽 (볼링장)", source = "bowling" },
	home = { label = "우리 집 놀러 와", icon = "🏠", minTier = 3, needsHome = true, source = "home" },
}
Social.ACCEPT_BASE = { 0.08, 0.4, 0.75, 0.95, 1 }
Social.INVITE_DECLINE_COOLDOWN = 240 -- seconds before asking the same NPC again after a no
Social.COMPANION_SECONDS = 900 -- a hangout lasts at most 15 real minutes
Social.COMPANION_TIER = 3 -- in person
Social.CALL_TIER = 4 -- call a friend over by phone
Social.NUMBER_TIER = 3 -- numbers are exchanged automatically at 친한 사이
Social.NUMBER_ASK_TIER = 2 -- from 아는 사이 you may ask for it (Social.numberChance)
Social.HANGOUT_TICK = 180 -- +hangout every 3 minutes together
Social.PROMISE_SECONDS = 480 -- a meet-up that is not the club must happen within 8 minutes
Social.ERRAND_SECONDS = 720
Social.TEXT_GAP = { 300, 560 } -- seconds between friend texts
Social.SPAM_WINDOW = 60
Social.SPAM_TALKS = 7

-- Chance an NPC says yes. info = { tier, social (0..1), working, sleeping, minor, clubber (0..1),
-- hasHome, bestie }.
function Social.acceptChance(kind: string, info: any): number
	local inv = Social.INVITES[kind]
	if not inv then
		return 0
	end
	local tier = math.clamp(info.tier or 1, 1, 5)
	if kind == "club" and info.minor then
		return 0
	end
	if inv.needsHome and not info.hasHome then
		return 0
	end
	if kind == "home" and tier < Social.TIER_CLOSE then
		return 0
	end
	if tier < inv.minTier then
		return if tier == 1 and kind ~= "home" then 0.03 else 0
	end
	local p = Social.ACCEPT_BASE[tier] * (0.6 + 0.8 * math.clamp(info.social or 0.5, 0, 1))
	if kind == "home" and tier == Social.TIER_CLOSE then
		p *= 0.5
	end
	if kind == "club" then
		p *= 0.4 + math.clamp(info.clubber or 0, 0, 1)
	end
	if info.working and tier < Social.TIER_BESTIE then
		p *= 0.25
	end
	if info.sleeping then
		p *= 0.2
	end
	return math.clamp(p, 0, 1)
end

-- Chance they give you their number when you ask: 친한 사이+ always, 아는 사이 about 20 % .. 75 % (more
-- the closer to 친한 사이 and the more sociable they are), strangers never.
function Social.numberChance(a: any, social: any): number
	local v = Social.clampA(a)
	local tier = Social.tierOf(v)
	if tier >= Social.NUMBER_TIER then
		return 1
	elseif tier < Social.NUMBER_ASK_TIER then
		return 0
	end
	local prog = Social.tierProgress(v)
	local s = math.clamp(if isNum(social) then social else 0.6, 0, 1)
	return math.clamp((0.25 + 0.45 * prog) * (0.6 + 0.8 * s), 0.05, 0.95)
end

-------------------------------------------------------------------------------------------------
-- Sanitising (migration-safe: never errors on garbage; unknown top-level data is kept in `ext`).
-------------------------------------------------------------------------------------------------
local function str(v: any, maxLen: number): string
	if type(v) ~= "string" then
		return ""
	end
	if #v > maxLen then
		return ""
	end
	return v
end

local function num(v: any, default: number): number
	return if isNum(v) then v else default
end

local function sanitizeRecord(r: any, now: number): any?
	if type(r) ~= "table" then
		return nil
	end
	local rec = Social.newRecord(num(r.u, 0), num(r.a, 0))
	rec.met = math.clamp(math.floor(num(r.met, 0)), 0, 1e6)
	rec.first = math.max(0, num(r.first, 0))
	rec.last = math.clamp(num(r.last, 0), 0, now + 86400)
	rec.u = math.clamp(num(r.u, rec.last), 0, now + 86400)
	rec.la = str(r.la, 40)
	rec.lx = str(r.lx, 24)
	rec.lg = if type(r.lg) == "string" and Social.GIFTS[r.lg] then r.lg else ""
	rec.pk = math.clamp(math.floor(num(r.pk, 1)), 1, #Social.TIERS)
	rec.pk = math.max(rec.pk, (Social.tierOf(rec.a)))
	rec.gd = num(r.gd, 0)
	rec.gg = math.clamp(num(r.gg, 0), 0, Social.GAME_DAY_CAP)
	rec.rd = num(r.rd, 0)
	rec.rg = math.clamp(num(r.rg, 0), 0, Social.REAL_DAY_CAP)
	rec.dk = math.clamp(math.floor(num(r.dk, 0)), 0, Social.DECAY_MAX)
	rec.up = math.clamp(num(r.up, 0), 0, now + Social.UPSET_SECONDS)
	rec.gr = math.clamp(num(r.gr, 0), 0, Social.GRUDGE_MAX)
	if type(r.n) == "table" then
		for k, c in r.n do
			if type(k) == "string" and Social.SOURCES[k] and isNum(c) and c > 0 then
				rec.n[k] = math.min(math.floor(c), 99)
			end
		end
	end
	if type(r.f) == "table" then
		for k, x in r.f do
			if type(k) == "string" and #k <= 24 and (type(x) == "boolean" or isNum(x) or (type(x) == "string" and #x <= 40)) then
				rec.f[k] = x
			end
		end
	end
	if type(r.gk) == "table" then
		for g, x in r.gk do
			if Social.GIFTS[g] and (x == "love" or x == "like" or x == "neutral" or x == "dislike" or x == "refuse") then
				rec.gk[g] = x
			end
		end
	end
	if type(r.pr) == "table" and type(r.pr.kind) == "string" and Social.INVITES[r.pr.kind] and isNum(r.pr.due) then
		rec.pr = { kind = r.pr.kind, dest = str(r.pr.dest, 80), due = r.pr.due, made = num(r.pr.made, 0) }
	end
	if type(r.er) == "table" and type(r.er.id) == "string" and #r.er.id <= 40 and isNum(r.er.due) then
		rec.er = { id = r.er.id, stage = if r.er.stage == "back" then "back" else "go", due = r.er.due, dest = str(r.er.dest, 80) }
	end
	return rec
end
Social.sanitizeRecord = sanitizeRecord

local function sanitizeMsg(m: any): any?
	if type(m) ~= "table" or type(m.from) ~= "string" or #m.from > 40 or type(m.text) ~= "string" then
		return nil
	end
	local out = {
		id = math.max(0, math.floor(num(m.id, 0))),
		from = m.from,
		text = string.sub(m.text, 1, 400),
		t = num(m.t, 0),
		kind = str(m.kind, 16),
		state = if m.state == "accepted" or m.state == "declined" or m.state == "expired" or m.state == "read" then m.state else "new",
	}
	if type(m.invite) == "table" and type(m.invite.kind) == "string" and Social.INVITES[m.invite.kind] then
		out.invite = { kind = m.invite.kind, dest = str(m.invite.dest, 80), untilT = num(m.invite.untilT, 0) }
	end
	return out
end

-- raw = whatever was saved (nil / garbage / an older or newer version). starts = seed affinities for a
-- fresh state (and for missing seeded NPCs of an old save).
function Social.sanitize(raw: any, now: number, starts: { [string]: number }?): any
	if type(raw) ~= "table" or not isNum(raw.v) then
		return Social.newState(now, starts)
	end
	local st = Social.newState(now, nil)
	st.u = math.clamp(num(raw.u, 0), 0, now + 86400)
	local count = 0
	local recs = {}
	if type(raw.npcs) == "table" then
		for id, r in raw.npcs do
			if type(id) == "string" and #id > 0 and #id <= 40 then
				local rec = sanitizeRecord(r, now)
				if rec then
					table.insert(recs, { id = id, rec = rec })
					count += 1
				end
			end
		end
	end
	if count > Social.MAX_RECORDS then
		table.sort(recs, function(x, y)
			if x.rec.a ~= y.rec.a then
				return x.rec.a > y.rec.a
			end
			return x.id < y.id
		end)
	end
	for i, e in recs do
		if i > Social.MAX_RECORDS then
			break
		end
		st.npcs[e.id] = e.rec
	end
	-- seeded NPCs an old save never met
	for id, a in starts or {} do
		if st.npcs[id] == nil and isNum(a) then
			st.npcs[id] = Social.newRecord(now, a)
		end
	end
	if type(raw.inbox) == "table" then
		for _, m in raw.inbox do
			local s = sanitizeMsg(m)
			if s then
				table.insert(st.inbox, s)
			end
		end
		table.sort(st.inbox, function(x, y)
			return x.id < y.id
		end)
		while #st.inbox > Social.INBOX_MAX do
			table.remove(st.inbox, 1)
		end
	end
	local maxId = 0
	for _, m in st.inbox do
		maxId = math.max(maxId, m.id)
	end
	st.nextMsg = math.max(math.floor(num(raw.nextMsg, 1)), maxId + 1)
	if type(raw.stats) == "table" then
		for k in st.stats do
			st.stats[k] = math.max(0, math.floor(num(raw.stats[k], 0)))
		end
	end
	-- forward compatibility: a newer server's data survives an older server
	if raw.v > Social.VERSION then
		st.v = raw.v
	end
	if type(raw.ext) == "table" then
		st.ext = raw.ext
	end
	return st
end

-- Merges two sanitized states (fallback store after a quick server hop): per NPC the record changed
-- last wins; inbox / stats from the state saved last.
function Social.merge(a: any, b: any): any
	if type(a) ~= "table" then
		return b
	end
	if type(b) ~= "table" then
		return a
	end
	local newer, older = a, b
	if (b.u or 0) > (a.u or 0) then
		newer, older = b, a
	end
	local out = {
		v = math.max(a.v or Social.VERSION, b.v or Social.VERSION),
		u = math.max(a.u or 0, b.u or 0),
		npcs = {},
		inbox = newer.inbox or {},
		nextMsg = math.max(a.nextMsg or 1, b.nextMsg or 1),
		stats = newer.stats or {},
		ext = newer.ext or older.ext,
	}
	for id, r in older.npcs or {} do
		out.npcs[id] = r
	end
	for id, r in newer.npcs or {} do
		local o = out.npcs[id]
		if not o or (r.u or 0) >= (o.u or 0) then
			out.npcs[id] = r
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- NPC TYPES (owner: npc_types). Citizens.byId[id].type: "plain" (그냥 NPC, default) | "violent"
-- (폭력적인 NPC) | "fool" (동네바보) | "beggar" (걸렁뱅이) | "drunk" (주정뱅이: stagger walk, mumbles, naps
-- on a bench; NO alcohol depiction - all ages). color = name-tag hint / speech-bubble tint, lines =
-- ambient + reaction banks (std / busan), chatty = talks to the player first by default.
-------------------------------------------------------------------------------------------------
Social.TYPE_ORDER = { "plain", "violent", "fool", "beggar", "drunk" }
-- Affinity is 0..MAX; a 폭력적인 NPC starts BELOW zero: `grudge` points (record field gr) are paid off by
-- the first goodwill before the visible affinity moves, and rudeness / 어깨빵 at 0 grow it again (up to
-- grudgeCap). Others never hold a grudge.
Social.GRUDGE_MAX = 30
Social.TYPES = {
	plain = { label = "그냥 NPC", short = "", icon = "", color = { 190, 190, 200 }, bubble = { 250, 250, 252 }, ink = { 24, 26, 36 }, chatty = false, startA = nil },
	violent = { label = "폭력적인 NPC", short = "성깔", icon = "😠", color = { 255, 90, 95 }, bubble = { 255, 214, 214 }, ink = { 70, 14, 20 }, chatty = false, startA = 0, grudge = 10, grudgeCap = 30 },
	fool = { label = "동네바보", short = "동네바보", icon = "🤪", color = { 255, 194, 71 }, bubble = { 255, 240, 196 }, ink = { 72, 48, 6 }, chatty = true, startA = 10 },
	beggar = { label = "걸렁뱅이", short = "천원만", icon = "🥤", color = { 160, 140, 110 }, bubble = { 232, 224, 206 }, ink = { 60, 48, 30 }, chatty = true, startA = 5 },
	drunk = { label = "주정뱅이", short = "비틀", icon = "😵‍💫", color = { 139, 108, 255 }, bubble = { 224, 216, 255 }, ink = { 40, 26, 90 }, chatty = false, startA = 5 },
}
-- Lines by type. kinds: ambient (said now and then near the player), glare (violent: the player is
-- close), block (violent blocks the way), insult (violent, mild), chase (violent runs after you),
-- bumped (reaction after the player's 어깨빵: stagger), down (after a knockdown), retaliate (violent
-- bumps back), giggle (fool), foolbump (fool bumped you), beg (beggar asks), thanks (got money),
-- grumble (refused), mumble (drunk), nap (drunk lies down), hiccup, opener (chatty: first line),
-- bye, shrug (you walked away), witness (someone saw the bump), puk (the comic hit word).
Social.TYPE_LINES = {
	plain = {
		std = {
			bumped = { "아 깜짝이야!", "조심 좀 하세요!", "왜 이러세요~", "앞 좀 보고 다니세요!", "헉!" },
			down = { "아야… 뭐예요 진짜…", "으으… 허리…", "이게 뭐야…", "저기요, 사과하세요!" },
			witness = { "어머, 봤어?", "저 사람 왜 저래…", "헐…", "괜찮으세요?" },
			opener = { "저기요! 혹시…", "안녕하세요~ 잠깐 시간 되세요?", "실례지만 하나만 물어볼게요!" },
			bye = { "고마워요~ 좋은 하루!", "감사합니다! 다음에 봐요~", "네네, 그럼 이만~" },
			shrug = { "어… 가버리네…", "바쁘신가 보다~", "흠, 다음에 물어보자." },
			ambient = { "오늘 바다 색 진짜 예쁘다.", "저녁에 뭐 먹지…", "광안대교 불 켜지는 거 보고 갈까?" },
		},
		busan = {
			bumped = { "아이고 깜짝아!", "마 좀 보고 댕기라~", "어데 보고 댕기노!" },
			down = { "아야… 와 이라노 진짜…", "허리 나갈라 그라네…", "니 사과해라!" },
			witness = { "어, 봤나?", "저 사람 와 저라노…", "괜찮습니꺼?" },
			opener = { "저기요! 혹시…", "아 저기, 잠깐만예~", "하나만 물어볼게예!" },
			bye = { "고맙습니데이~", "다음에 또 봅시데이!", "그럼 이만 갈게예~" },
			shrug = { "어… 가네…", "바쁜가 보다~" },
			ambient = { "오늘 바다 색 쥑이네.", "저녁에 뭐 묵지…", "광안대교 불 켜지는 거 보고 갈까?" },
		},
	},
	violent = {
		std = {
			ambient = { "뭘 봐.", "비켜, 길 막지 말고.", "오늘 기분 안 좋으니까 건들지 마.", "하… 짜증나네." },
			glare = { "…뭘 봐?", "왜 자꾸 쳐다봐?", "할 말 있어?" },
			block = { "어디 가? 잠깐 서봐.", "여기 내 자리야.", "급해? 그래서?" },
			insult = { "덜렁이 같은 게.", "너 걸음걸이 웃기다?", "오리처럼 걷네 ㅋ", "꼬맹이, 집에 가라." },
			chase = { "야! 거기 서!", "도망가냐? 서라!", "잡히면 어깨빵 두 배다!" },
			bumped = { "…뭐야. 지금 친 거야?", "하, 너 잘 걸렸다.", "제대로 걸었네." },
			retaliate = { "받아라, 어깨빵!", "이게 진짜 어깨빵이야.", "다음엔 두 배다." },
			down = { "…이걸 넘어뜨려?", "두고 보자…", "아 진짜… 다음엔 안 봐줘." },
			witness = { "저 사람 건들면 안 되는데…", "어어… 조심해요…", "저 아저씨 유명해요, 피해요." },
			shove = { "너무 가까이 오지 마.", "저리 가라고.", "떨어져." },
			giveup = { "…됐다, 귀찮아.", "다음에 보자.", "하, 숨 차." },
		},
		busan = {
			ambient = { "뭘 보노.", "마, 길 막지 마라.", "오늘 기분 더럽다. 건들지 마라.", "하… 짜증 나네." },
			glare = { "…뭘 보노?", "와 자꾸 쳐다보노?", "할 말 있나?" },
			block = { "어데 가노? 잠깐 서봐라.", "여기 내 자리다.", "급하나? 그래서?" },
			insult = { "덜렁이 같은 기.", "니 걸음걸이 웃긴다?", "오리같이 걷네 ㅋ", "꼬맹이는 집에 가라." },
			chase = { "마! 거기 서라!", "도망가나? 서라!", "잡히면 어깨빵 두 배다!" },
			bumped = { "…뭐꼬. 지금 친 기가?", "하, 니 잘 걸렸다.", "제대로 걸었네." },
			retaliate = { "받아라, 어깨빵!", "이기 진짜 어깨빵이다.", "다음엔 두 배다." },
			down = { "…이걸 넘어뜨리나?", "두고 보자…", "아 진짜… 다음엔 안 봐준다." },
			witness = { "저 사람 건들면 안 되는데…", "어어… 조심하이소…", "저 아재 유명합니다, 피하이소." },
			shove = { "너무 가까이 오지 마라.", "저리 가라.", "떨어지라." },
			giveup = { "…됐다, 귀찮다.", "다음에 보자.", "하, 숨 찬다." },
		},
	},
	fool = {
		std = {
			ambient = { "히히히~", "오늘 구름이 붕어빵 모양이야!", "나 어제 바다랑 얘기했어~", "에헤헤, 신발 끈이 또 풀렸네~" },
			giggle = { "히히~", "에헤헤~", "낄낄~", "히히, 미안~" },
			foolbump = { "어깨빵~! 히히", "에헤헤 지나갈게요~", "쿵! 히히", "아 미안, 발이 먼저 갔어~" },
			bumped = { "히히, 그게 어깨빵이야? 더 세게!", "우와 나도 해봐도 돼?", "에헤헤 재밌다~" },
			down = { "히히… 하늘이 돈다~", "우와, 별이 보여~", "에헤헤 다시 일어나야지~" },
			witness = { "히히, 쿵 했다!", "우와 넘어졌다~", "히히 재밌겠다~" },
			opener = { "저기 저기! 히히, 혹시…", "안녕! 나 동네 지도야! 뭐든 물어봐~ 히히", "에헤헤, 너 재밌어 보인다~ 얘기하자!" },
			laughed = { "히히 좋은 사람이네~ 친구 하자!", "에헤헤 다음엔 살짝 할게~", "우와 안 화내네! 최고!" },
			scolded = { "히이… 미안해…", "에헤… 안 그럴게…", "히잉…" },
			bye = { "히히 안녕~ 또 만나~", "바이바이~ 에헤헤", "히히, 어깨빵 조심해~" },
			shrug = { "어… 가버렸다 히히", "히잉, 심심해…" },
		},
		busan = {
			ambient = { "히히히~", "오늘 구름이 붕어빵이네!", "내 어제 바다랑 얘기했다~", "에헤헤, 신발끈 또 풀렸다~" },
			giggle = { "히히~", "에헤헤~", "낄낄~", "히히, 미안~" },
			foolbump = { "어깨빵~! 히히", "에헤헤 지나갈게예~", "쿵! 히히", "아 미안, 발이 먼저 갔다~" },
			bumped = { "히히, 그기 어깨빵이가? 더 세게!", "우와 나도 해봐도 되나?", "에헤헤 재밌다~" },
			down = { "히히… 하늘이 돈다~", "우와, 별 보인다~", "에헤헤 다시 일어나야지~" },
			witness = { "히히, 쿵 했다!", "우와 넘어졌다~" },
			opener = { "저기 저기! 히히, 혹시…", "안녕! 내가 동네 지도다! 뭐든 물어봐라~ 히히", "에헤헤, 니 재밌어 보인다~ 얘기하자!" },
			laughed = { "히히 좋은 사람이네~ 친구 하자!", "에헤헤 다음엔 살짝 할게~", "우와 안 화내네! 최고!" },
			scolded = { "히이… 미안하다…", "에헤… 안 그럴게…", "히잉…" },
			bye = { "히히 안녕~ 또 보자~", "바이바이~ 에헤헤" },
			shrug = { "어… 가버렸다 히히", "히잉, 심심하다…" },
		},
	},
	beggar = {
		std = {
			ambient = { "천원만…", "배고프다…", "오늘도 한 푼도 못 모았네…", "컵이 텅텅 비었어요…" },
			beg = { "천원만… 천원만 주세요…", "저기요… 천원만…", "오천원이면 밥 한 끼 먹어요…", "컵에 뭐라도 좀…" },
			thanks = { "아이고 감사합니다! 복 받으세요!", "고맙습니다… 진짜로…", "이 은혜 안 잊어요!", "덕분에 오늘 밥 먹어요!" },
			grumble = { "쩝… 알겠어요…", "쳇… 부자 되세요…", "에휴… 다음에…", "그래요, 그래요…" },
			leave = { "…다른 데 가봐야겠다.", "에휴, 저쪽으로 가보자.", "쩝…" },
			bumped = { "아이고! 컵! 내 컵!", "왜 때려요… 가난한 사람을…", "아… 동전 쏟아졌다…" },
			down = { "아이고… 허리…", "이러면 적선이라도 하세요…", "컵… 어디 갔어…" },
			witness = { "아이고, 저 양반을 왜…", "저 사람 불쌍한데…" },
			opener = { "저기요… 천원만…", "손님… 잠깐만요… 천원만…", "거기 좋은 분… 잠시만요…" },
			bye = { "복 받으세요~", "건강하세요~", "다음에 또 지나가세요…" },
			shrug = { "에휴… 그냥 가네…", "쩝… 다음 사람…" },
		},
		busan = {
			ambient = { "천원만…", "배고프다…", "오늘도 한 푼도 못 모았네…", "컵이 텅텅 비었다…" },
			beg = { "천원만… 천원만 주이소…", "저기요… 천원만…", "오천원이면 밥 한 끼 묵습니더…", "컵에 뭐라도 좀…" },
			thanks = { "아이고 고맙습니더! 복 받으소!", "고맙습니더… 진짜로…", "이 은혜 안 잊을게예!", "덕분에 오늘 밥 묵습니더!" },
			grumble = { "쩝… 알겄습니더…", "쳇… 부자 되소…", "에휴… 다음에…" },
			leave = { "…다른 데 가봐야겄다.", "에휴, 저쪽으로 가보자.", "쩝…" },
			bumped = { "아이고! 컵! 내 컵!", "와 때리노… 가난한 사람을…", "아… 동전 쏟아졌다…" },
			down = { "아이고… 허리…", "이라면 적선이라도 하이소…", "컵… 어데 갔노…" },
			witness = { "아이고, 저 양반을 와…", "저 사람 불쌍한데…" },
			opener = { "저기요… 천원만…", "손님… 잠깐만예… 천원만…", "거기 좋은 분… 잠시만예…" },
			bye = { "복 받으소~", "건강하이소~", "다음에 또 지나가이소…" },
			shrug = { "에휴… 그냥 가네…", "쩝… 다음 사람…" },
		},
	},
	drunk = {
		std = {
			ambient = { "으으… 세상이 왜 이렇게 돌지…", "집이… 어디였지…", "히끅. 광안대교가 두 개네…", "노래가… 흥얼… 흐응~" },
			mumble = { "으으… 음… 뭐라고…", "히끅… 집에 가야… 되는데…", "어… 여기가… 어디…", "흐응~ 흐흐응~ (흥얼흥얼)" },
			hiccup = { "히끅!", "히끅… 어이구…", "히끅, 히끅…" },
			nap = { "여기… 잠깐만… 눕자…", "쿨… 쿨…", "벤치가… 침대 같다…", "5분만… 쿨…" },
			bumped = { "어어어… 히끅… 누구세요…", "으으… 세상이 더 돈다…", "히끅… 미안… 내가 부딪혔나…" },
			down = { "히끅… 바닥이 편하네…", "으으… 하늘이… 돈다…", "쿨… 아 아니, 일어나야…" },
			accident = { "어이쿠… 미안해요… 히끅", "으으… 길이 좁네…", "히끅… 어깨가… 자꾸…" },
			witness = { "어어, 저 사람 괜찮나…", "졸린가… 아니, 피곤한가 보다…" },
			bye = { "히끅… 잘 가요…", "으으… 집에… 가야지…" },
			shrug = { "어… 히끅…" },
		},
		busan = {
			ambient = { "으으… 세상이 와 이래 도노…", "집이… 어데였지…", "히끅. 광안대교가 두 개네…", "노래가… 흥얼… 흐응~" },
			mumble = { "으으… 음… 뭐라꼬…", "히끅… 집에 가야… 되는데…", "어… 여기가… 어데…", "흐응~ 흐흐응~ (흥얼흥얼)" },
			hiccup = { "히끅!", "히끅… 어이구…", "히끅, 히끅…" },
			nap = { "여기… 잠깐만… 눕자…", "쿨… 쿨…", "벤치가… 침대 같다…", "5분만… 쿨…" },
			bumped = { "어어어… 히끅… 누구고…", "으으… 세상이 더 돈다…", "히끅… 미안… 내가 부딪혔나…" },
			down = { "히끅… 바닥이 편하네…", "으으… 하늘이… 돈다…", "쿨… 아 아니, 일어나야…" },
			accident = { "어이쿠… 미안합니더… 히끅", "으으… 길이 좁네…", "히끅… 어깨가… 자꾸…" },
			witness = { "어어, 저 사람 괜찮나…", "피곤한가 보다…" },
			bye = { "히끅… 잘 가소…", "으으… 집에… 가야지…" },
			shrug = { "어… 히끅…" },
		},
	},
}
Social.PUK = { "퍽!", "쿵!", "털썩!", "퍽!!", "우당탕!" }
Social.KNOCK_PUK = { "쾅!!", "퍼억!!", "우당탕!!" }

-- A random line of a type bank: Social.typeLine("fool", "giggle", "busan") (falls back to std / plain).
function Social.typeLine(typeId: any, kind: string, speech: any, rnd: (() -> number)?): string?
	local T = Social.TYPE_LINES[typeId] or Social.TYPE_LINES.plain
	local bank = (speech == "busan" and T.busan and T.busan[kind]) or (T.std and T.std[kind])
	if not bank and typeId ~= "plain" then
		local P = Social.TYPE_LINES.plain
		bank = (speech == "busan" and P.busan[kind]) or P.std[kind]
	end
	if not bank or #bank == 0 then
		return nil
	end
	local r = if rnd then rnd() else math.random()
	return bank[1 + math.floor(math.min(0.999, r) * #bank)]
end

function Social.typeDef(typeId: any): any
	return Social.TYPES[typeId] or Social.TYPES.plain
end

-------------------------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------------------------
-- Korean particle after a word: josa("민지", "와", "과") -> "민지와"; josa("태양", "와", "과") -> "태양과".
-- Non-Hangul endings (English names) take the no-batchim form.
function Social.josa(word: string, noBatchim: string, batchim: string): string
	local last = nil
	for _, c in utf8.codes(word) do
		last = c
	end
	if last and last >= 0xAC00 and last <= 0xD7A3 and (last - 0xAC00) % 28 ~= 0 then
		return word .. batchim
	end
	return word .. noBatchim
end

function Social.tierLabel(a: any): string
	local idx, t = Social.tierOf(a)
	local _ = idx
	return t.icon .. " " .. t.name
end

-- "3분 전" style (Korean), for memory lines / UI.
function Social.ago(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s < 90 then
		return "방금"
	elseif s < 3600 then
		return string.format("%d분 전", s // 60)
	elseif s < 86400 then
		return string.format("%d시간 전", s // 3600)
	end
	return string.format("%d일 전", s // 86400)
end

-- Static data checks (unit tests + once on the server).
function Social.validate(): { string }
	local problems = {}
	for i, t in Social.TIERS do
		if i > 1 and t.min <= Social.TIERS[i - 1].min then
			table.insert(problems, "tiers not increasing at " .. t.id)
		end
	end
	for _, id in Social.GIFT_ORDER do
		local g = Social.GIFTS[id]
		if not g then
			table.insert(problems, "GIFT_ORDER lists missing gift " .. id)
		elseif not isNum(g.price) or g.price <= 0 then
			table.insert(problems, "gift " .. id .. " bad price")
		end
	end
	for id in Social.GIFTS do
		if not table.find(Social.GIFT_ORDER, id) then
			table.insert(problems, "gift " .. id .. " missing from GIFT_ORDER")
		end
	end
	for _, tid in Social.TYPE_ORDER do
		local T = Social.TYPE_LINES[tid]
		if not Social.TYPES[tid] or not T or not T.std then
			table.insert(problems, "NPC type incomplete " .. tid)
		end
	end
	for _, id in Social.INVITE_ORDER do
		local inv = Social.INVITES[id]
		if not inv then
			table.insert(problems, "INVITE_ORDER lists missing invite " .. id)
		elseif inv.source and not Social.SOURCES[inv.source] then
			table.insert(problems, "invite " .. id .. " unknown source")
		end
	end
	return problems
end

return Social
