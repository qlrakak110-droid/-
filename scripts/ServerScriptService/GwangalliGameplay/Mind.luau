-- GwangalliGameplay/Mind (server feature module; owner: npc_mind): the authoritative side of the NPC
-- mind. Every conversation, interaction and crime goes through here; the client (GwangalliStreetLife
-- /Mind) only shows bubbles and moves the people.
--   * FEELINGS: 신뢰도 / 분노도 / 공포도 / 친밀도 per NPC per player (GwangalliMindShared records), 호감도
--     stays Relationships' (ctx.social: tiers, numbers, promises, companions, gifts through the ledger)
--     and is moved through ctx.social.award with the new sources (mind / food / money / play / help /
--     love / insult / provoke / assault / harass).
--   * MEMORY: what you asked, gave, said, did (rec.mem), the name and the tastes you found out, the
--     phone thread, the relationship flags (연인 / 적대). Saved in DataStore "GwangalliMind_v1"
--     (key u_<UserId>; volatile bits like the no-repeat table are not saved).
--   * TALK (RemoteFunction ReplicatedStorage.GwangalliMind.MindTalk, op + payload, validated: the NPC
--     must be within reach of the player, token bucket per player):
--       open  {id, pos, kind?}         start a face-to-face conversation (kind = who started it:
--                                       talk | punk | punk_toss | fool | fool_* | beg | police | chatty | friend)
--       say   {id, pos, intent?, text?, item?}   one exchange (free text is parsed server-side)
--       act   {id, pos, act, arg?}     gift | food | money | play | meet | hit | number
--       close {id}
--       call  {id} / text {id, text?, intent?} / meet {id, kind}   the phone (needs their number)
--       police {op, copId?, pos?}     the police encounter (open | sorry | excuse | insult | caught | lost)
--       report {id, pos}              a witness phoned the police (only counts after a real crime)
--       street {id, ev, pos}          street behaviour memory (ignored | laughed | scolded | bumped_by)
--     Each answer: { ok, out = {lines, face, emote, act, ask, mood, stage}, view = npc view, wanted }
--   * EVENTS (RemoteEvent MindEvent, server -> client): crime {crime, stars, pos, victim} | wanted {stars}
--     | text {id, msg} | view {id, view} | police {op, line, fine?} | news {text}
--   * SNAPSHOT (RemoteFunction MindGet): { npcs = {id = view (met people only)}, contacts, wanted,
--     threads = {id = {...}}, appts }
--   * CRIME: 때리기 (폭행 ★★, 경찰관 ★★★), 경찰 모욕 / 협박 / 연쇄 어깨빵 (★), 뇌물 (★). Player attribute
--     GwangalliWanted (0..5) replicates; stars cool down one by one after WANTED_COOL s of calm. The
--     client dispatches police officers (street-life agents) to a wanted player; when one reaches you
--     the "police" op opens the questioning: 사과 (fine, stars cleared), 변명 (a chance), 욕 (resisting:
--     a star more and a chase), 도주 (the chase; caught = a bigger fine).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")

local MindServer = {}

local ctx: any
local G: any
local Util: any
local M: any -- GwangalliMindShared
local Lines: any
local Talk: any = nil -- child Talk: free conversation over the composer
local Brain: any = nil -- child Brain: optional Claude replies (off unless set up)
local Citizens: any
local Social: any
local Transit: any

local remotes: { Talk: RemoteFunction?, Event: RemoteEvent?, Get: RemoteFunction? } = {}
local store: DataStore? = nil

type Sess = {
	state: any,
	ready: boolean,
	dirty: boolean,
	talk: any?,
	police: any?,
	lastCrime: number,
	crimeKind: string?,
	reported: boolean,
	bumps: { number },
	nextText: number,
	nextSave: number,
	tokens: number,
	tokT: number,
}
local sessions: { [Player]: Sess } = {}
local newsFeed: { { t: number, text: string } } = {}

local TALK_REACH = 30 -- studs between the player and a reported citizen position
local AUTOSAVE = 120
local TEXT_GAP = { 240, 520 }

local function now(): number
	return os.time()
end

local function requireShared(name: string): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 20)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliMind] " .. name .. " failed to load: " .. tostring(res))
	return nil
end

local function citizen(id: any): any?
	return if type(id) == "string" and Citizens then Citizens.byId[id] else nil
end

local function push(player: Player, payload: any)
	local ev = remotes.Event
	if ev and player.Parent == Players then
		ev:FireClient(player, payload)
	end
end

local function notify(player: Player, kind: string, title: string, body: string?)
	if ctx and ctx.notify then
		pcall(ctx.notify, player, kind, title, body or "")
	end
end

local function clockNow(): number
	if ctx and ctx.env then
		local ok, e = pcall(ctx.env)
		if ok and type(e) == "table" and type(e.clock) == "number" then
			return e.clock
		end
	end
	return game:GetService("Lighting").ClockTime
end

local function weatherNow(): string
	local w = ReplicatedStorage:GetAttribute("GwWeather")
	return if type(w) == "string" then w else "clear"
end

local function tod(clock: number): string
	if clock >= 5 and clock < 11 then
		return "morning"
	elseif clock >= 11 and clock < 17 then
		return "day"
	elseif clock >= 17 and clock < 21.5 then
		return "evening"
	end
	return "night"
end

local function timeText(clock: number): string
	local h = math.floor(clock) % 24
	local m = math.floor((clock - math.floor(clock)) * 60)
	local ap = if h < 12 then "오전" else "오후"
	local hh = h % 12
	if hh == 0 then
		hh = 12
	end
	return string.format("%s %d시%s", ap, hh, if m >= 30 then " 반" else "")
end

-- destinations (tag "Destination", attribute DisplayName) for plausibility checks
local destCache: { [string]: BasePart } = {}
local function destPos(name: string?): Vector3?
	if not name then
		return nil
	end
	local p = destCache[name]
	if p and p.Parent then
		return p.Position
	end
	if ctx and ctx.dest then
		local ok, part = pcall(ctx.dest, name)
		if ok and part then
			destCache[name] = part
			return part.Position
		end
	end
	for _, inst in CollectionService:GetTagged("Destination") do
		if inst:IsA("BasePart") and inst:GetAttribute("DisplayName") == name then
			destCache[name] = inst
			return inst.Position
		end
	end
	return nil
end
local function areaPos(areaId: string): Vector3?
	local a = Citizens and Citizens.AREAS[areaId]
	return a and destPos(a.dest) or nil
end

local function vec(t: any): Vector3?
	if typeof(t) == "Vector3" then
		return t
	end
	if type(t) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(t[1] or t.x), tonumber(t[2] or t.y), tonumber(t[3] or t.z)
	if not x or not y or not z or x ~= x or y ~= y or z ~= z or math.abs(x) > 1e5 or math.abs(y) > 1e5 or math.abs(z) > 1e5 then
		return nil
	end
	return Vector3.new(x, y, z)
end

local function rootPos(player: Player): Vector3?
	if Util and Util.rootPosition then
		return Util.rootPosition(player)
	end
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return r and (r :: BasePart).Position or nil
end

-- a citizen reported by the client must stand next to the player (and be plausible for the schedule,
-- with a generous slack: client crowds keep people a little longer than the clock says)
local function nearCitizen(player: Player, id: string, posT: any, reach: number?): boolean
	local pos = vec(posT)
	local me = rootPos(player)
	if not pos or not me then
		return false
	end
	local d = Vector3.new(pos.X - me.X, 0, pos.Z - me.Z).Magnitude
	if d > (reach or TALK_REACH) or math.abs(pos.Y - me.Y) > 14 then
		return false
	end
	if Citizens and type(Citizens.plausible) == "function" then
		local ok, res = pcall(Citizens.plausible, id, pos, clockNow(), areaPos, 400)
		if ok and res == false then
			-- not where their day says: the conversation still happens, it just counts less (see award)
			return true
		end
	end
	return true
end

-------------------------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------------------------
local function newState(): any
	return { v = 1, npcs = {}, wanted = 0, crimes = 0, fines = 0, u = 0 }
end

local function sessOf(player: any): Sess?
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	local s = sessions[player]
	return if s and s.ready then s else nil
end

local function recOf(sess: Sess, id: string, create: boolean): any?
	local c = citizen(id)
	if not c then
		return nil
	end
	local r = sess.state.npcs[id]
	if not r and create then
		r = M.newRec(c, now())
		sess.state.npcs[id] = r
	elseif r and not r.said then
		M.fixRec(r, c, now())
	end
	if r then
		M.cool(r, now())
	end
	return r
end

local function social(): any
	return ctx and ctx.social
end

local function affOf(player: Player, id: string): (number, number)
	local s = social()
	if s and type(s.affinity) == "function" then
		local ok, a, t = pcall(s.affinity, player, id)
		if ok and type(a) == "number" then
			return a, t or 1
		end
	end
	local c = citizen(id)
	return c and c.start or 0, 1
end

local function socialRec(player: Player, id: string): any?
	local s = social()
	if s and type(s.snapshot) == "function" then
		local ok, snap = pcall(s.snapshot, player)
		if ok and type(snap) == "table" and type(snap.npcs) == "table" then
			return snap.npcs[id], snap
		end
	end
	return nil
end

local function hasNumber(player: Player, id: string): boolean
	local r = socialRec(player, id)
	return r ~= nil and r.number == true
end

local function award(player: Player, id: string, source: string, amount: number?): number
	local s = social()
	if not s or type(s.award) ~= "function" then
		return 0
	end
	local ok, d = pcall(s.award, player, id, source, amount)
	return if ok and type(d) == "number" then d else 0
end

local function markDirty(sess: Sess)
	sess.dirty = true
	sess.state.u = now()
end

local function giftName(id: string): string?
	local g = Social and Social.GIFTS and Social.GIFTS[id]
	return g and g.name or nil
end

local function shortName(id: string): string
	local ok, n = pcall(Citizens.shortName, id)
	return if ok and type(n) == "string" then n else (citizen(id) and citizen(id).name or id)
end

-- the view of one NPC for this player (what the HUD / phone may show)
local function viewOf(player: Player, sess: Sess, id: string): any
	local c = citizen(id)
	local rec = recOf(sess, id, false)
	if not c then
		return nil
	end
	local a, tier = affOf(player, id)
	local stageId = if rec then M.stage(rec, a) else "stranger"
	local S = M.STAGES[stageId] or M.STAGES.stranger
	local known = { foods = {}, gifts = {}, hobbies = {}, nofood = nil }
	if rec then
		for _, f in rec.kn.food do
			local fd = M.FOODS[f]
			table.insert(known.foods, fd and (fd.icon .. " " .. fd.name) or f)
		end
		for _, g in rec.kn.gift do
			local gd = Social and Social.GIFTS[g]
			table.insert(known.gifts, gd and (gd.icon .. " " .. gd.name) or g)
		end
		for _, h in rec.kn.hobby do
			table.insert(known.hobbies, M.HOBBY[h] or h)
		end
		if rec.kn.nofood and rec.kn.nofood[1] then
			local fd = M.FOODS[rec.kn.nofood[1]]
			known.nofood = fd and fd.name or nil
		end
	end
	local named = rec ~= nil and rec.nm == true
	local mood = if rec then M.mood(c, rec, a) else "neutral"
	local disp = "neutral"
	if rec then
		if stageId == "enemy" then
			disp = if rec.fe >= 45 then "scared" else "hostile"
		elseif rec.fe >= 45 then
			disp = "scared"
		elseif rec.an >= 45 then
			disp = "hostile"
		elseif stageId == "lover" or a >= 50 then
			disp = "friendly"
		end
	end
	local t = M.traits(c)
	return {
		id = id,
		name = if named then c.name else nil,
		label = (M.ARCH[t.arch] and M.ARCH[t.arch].label) or "",
		job = c.job,
		age = if named then c.age else nil,
		stage = stageId,
		stageLabel = S.label,
		stageIcon = S.icon,
		tier = tier,
		mood = mood,
		disp = disp,
		aff = a,
		tr = rec and rec.tr or t.tr0,
		an = rec and rec.an or 0,
		fe = rec and rec.fe or 0,
		cl = rec and rec.cl or 0,
		known = known,
		number = hasNumber(player, id),
		lover = rec ~= nil and rec.st == "lover",
		talks = rec and rec.tk or 0,
		last = rec and rec.lt or 0,
		arch = t.arch,
	}
end

local function liveNews(): { string }
	local out = {}
	local t = now()
	for i = #newsFeed, 1, -1 do
		local n = newsFeed[i]
		if t - n.t < 1800 then
			table.insert(out, n.text)
		end
		if #out >= 3 then
			break
		end
	end
	return out
end

local function addNews(text: string)
	table.insert(newsFeed, { t = now(), text = text })
	while #newsFeed > 20 do
		table.remove(newsFeed, 1)
	end
end

local AREA_KIND = { beach_c = "beach", beach_w = "beach", beach_e = "beach", sup = "beach", plaza = "beach", club = "club", gwangan_st = "street", gs25 = "street" }
local RECOMMEND = { "민락회타운", "밀락더마켓", "빵천동 빵집골목", "스타벅스 광안리점", "광안리 만남의 광장", "광안 코인노래연습장", "광안 당구클럽", "남천해변공원" }

local function envFor(player: Player, id: string, sess: Sess): any
	local c = citizen(id)
	local clock = clockNow()
	local a, tier = affOf(player, id)
	local area, _ = nil, nil
	pcall(function()
		area = Citizens.whereNow(id, clock)
	end)
	local friendName = nil
	if c and c.friends and #c.friends > 0 then
		friendName = shortName(c.friends[1 + (math.floor(clock) % #c.friends)])
	end
	local news = liveNews()
	for _, l in Lines and Lines.NEWS or {} do
		if #news >= 6 then
			break
		end
		if math.random() < 0.35 then
			table.insert(news, l)
		end
	end
	return {
		now = now(),
		clock = clock,
		tod = tod(clock),
		timeText = timeText(clock),
		weather = weatherNow(),
		area = area and Citizens.AREAS[area] and Citizens.AREAS[area].label or "해변",
		areaKind = area and AREA_KIND[area] or nil,
		you = player.DisplayName,
		aff = a,
		tier = tier,
		news = news,
		rnd = math.random,
		friend = friendName,
		partner = c ~= nil and c.partner ~= nil,
		giftName = giftName,
		recommend = RECOMMEND[math.random(#RECOMMEND)],
	}
end

-------------------------------------------------------------------------------------------------
-- Wanted / crime
-------------------------------------------------------------------------------------------------
local function setWanted(player: Player, sess: Sess, stars: number, why: string?)
	if ctx and ctx.law then
		-- GwangalliGameplay.Law owns the stars (server police, sight-based decay, arrests)
		ctx.law.setStars(player, stars, why)
		sess.state.wanted = ctx.law.stars(player)
		return
	end
	stars = math.clamp(math.floor(stars), 0, M.WANTED_MAX)
	local before = sess.state.wanted or 0
	sess.state.wanted = stars
	player:SetAttribute(M.Attr.Wanted, stars)
	player:SetAttribute(M.Attr.WantedUntil, workspace:GetServerTimeNow() + M.WANTED_COOL)
	markDirty(sess)
	if stars ~= before then
		push(player, { kind = "wanted", stars = stars, why = why })
		if stars > before then
			notify(player, "warn", "🚨 수배 " .. string.rep("★", stars), why or "경찰이 당신을 찾고 있어요")
		elseif stars == 0 then
			notify(player, "info", "✅ 수배 해제", why or "이제 경찰이 당신을 쫓지 않아요")
		end
	end
end

local function crime(player: Player, sess: Sess, key: string, victimId: string?, pos: Vector3?)
	local def = M.CRIMES[key]
	if not def then
		return
	end
	sess.lastCrime = os.clock()
	sess.crimeKind = key
	sess.reported = false
	sess.state.crimes = (sess.state.crimes or 0) + 1
	local victim = victimId and citizen(victimId)
	local where = pos or rootPos(player)
	if ctx and ctx.law then
		-- the Law module decides the stars (reports, witnesses) and sends the police
		ctx.law.crime(player, key, { pos = where, victim = victimId, victimName = victim and shortName(victimId) or nil, source = "mind", police = victim ~= nil and victim.type == "police" })
		sess.state.wanted = ctx.law.stars(player)
	else
		setWanted(player, sess, (sess.state.wanted or 0) + def.stars, def.label)
	end
	push(player, { kind = "crime", crime = key, label = def.label, stars = sess.state.wanted, pos = where and { where.X, where.Y, where.Z } or nil, victim = victimId })
	if victim then
		addNews(string.format("아까 누가 %s한테 %s했대요! 무섭다…", shortName(victimId), def.label))
	else
		addNews(string.format("방금 근처에서 %s 사건이 있었대요.", def.label))
	end
end

-- fines come out of cash first, then the bank (what is there; never below zero)
local function chargeFine(player: Player, amount: number, label: string): number
	if amount <= 0 or not ctx then
		return 0
	end
	local d = ctx.Profiles and ctx.Profiles.get and ctx.Profiles.get(player)
	local cash = d and d.cash or 0
	local bank = d and d.bank or 0
	local paid = 0
	local fromCash = math.min(cash, amount)
	if fromCash > 0 and ctx.ledger(player, "cash", -fromCash, label, true) then
		paid += fromCash
	end
	local rest = amount - paid
	if rest > 0 then
		local fromBank = math.min(bank, rest)
		if fromBank > 0 and ctx.ledger(player, "bank", -fromBank, label, true) then
			paid += fromBank
		end
	end
	if paid > 0 then
		notify(player, "money", "-" .. M.won(paid), label)
	end
	return paid
end

-------------------------------------------------------------------------------------------------
-- Applying a composed reply
-------------------------------------------------------------------------------------------------
local NEG_SOURCE = { insult = "insult", provoke = "provoke", threaten = "provoke", hit_r = "assault" }

local function splitLines(s: string?): { string }
	local out = {}
	if type(s) ~= "string" then
		return out
	end
	for part in string.gmatch(s, "[^\n]+") do
		table.insert(out, part)
	end
	return out
end

local function applyOut(player: Player, sess: Sess, id: string, rec: any, out: any, opts: any?)
	local o = opts or {}
	local t = now()
	local c = citizen(id)
	M.apply(rec, out.d, t)
	-- 호감도 through Relationships
	local da = out.d and out.d.aff or 0
	if da > 0 and not o.noAff then
		award(player, id, o.source or "mind", da)
	elseif da < 0 then
		award(player, id, NEG_SOURCE[out.intent or ""] or "harass", da)
	end
	if out.mem then
		M.remember(rec, out.mem.k, out.mem.x, t)
		if out.mem.k == "insult" then
			rec.ins = (rec.ins or 0) + 1
		end
	end
	if out.reveal then
		if out.reveal.name then
			rec.nm = true
		end
		for _, key in { "food", "gift", "hobby" } do
			local list = out.reveal[key]
			if type(list) == "table" then
				for _, v in list do
					if not table.find(rec.kn[key], v) then
						table.insert(rec.kn[key], v)
					end
				end
			end
		end
	end
	if out.act == "lover" and c then
		rec.st = "lover"
		award(player, id, "love")
		notify(player, "info", "💘 " .. c.name .. "와(과) 연인이 됐어요!", "문자 · 전화로 데이트 약속을 잡아 보세요")
		addNews(string.format("%s가(이) 누구랑 사귄대요! 부럽다~", shortName(id)))
	elseif out.act == "breakup" and c then
		rec.st = ""
		notify(player, "warn", "💔 " .. c.name .. "와(과) 헤어졌어요", "말 한마디가 이렇게 무서워요…")
	elseif out.act == "warn" and c and Citizens.typeOf(id) == "police" and (out.intent == "insult" or out.intent == "threaten") then
		crime(player, sess, if out.intent == "insult" then "insult_police" else "threat", id, nil)
	elseif out.act == "report" and not o.noCrime then
		crime(player, sess, "threat", id, nil)
		sess.reported = true
	end
	-- 적대: two hits or a run of insults make an enemy; real amends (calm + trust) heal it
	if rec.st ~= "lover" and ((rec.hit or 0) >= 2 or ((rec.ins or 0) >= 4 and rec.an >= 50)) then
		rec.st = "enemy"
	elseif rec.st == "enemy" and rec.an < 8 and rec.tr >= 35 then
		rec.st = ""
	end
	-- they start a real scuffle (their swings may land: GwangalliGameplay.Fight checks every one)
	if out.act == "fight" and ctx.fight and type(ctx.fight.startBrawl) == "function" then
		pcall(ctx.fight.startBrawl, player, id)
	end
	if o.talk ~= false then
		rec.tk = (rec.tk or 0) + 1
		if (rec.fm or 0) == 0 then
			rec.fm = t
		end
		rec.lt = t
	end
	markDirty(sess)
end

local function answer(player: Player, sess: Sess, id: string, out: any): any
	return { ok = true, out = { lines = out.lines, face = out.face, emote = out.emote, act = out.act, ask = out.ask, mood = out.mood, stage = out.stage, intent = out.intent }, view = viewOf(player, sess, id), wanted = sess.state.wanted or 0 }
end

-------------------------------------------------------------------------------------------------
-- Ops
-------------------------------------------------------------------------------------------------
local ops: { [string]: (Player, Sess, any) -> any } = {}

local function bucket(sess: Sess): boolean
	local t = os.clock()
	sess.tokens = math.min(10, sess.tokens + (t - sess.tokT) * 3)
	sess.tokT = t
	if sess.tokens < 1 then
		return false
	end
	sess.tokens -= 1
	return true
end

ops.open = function(player, sess, p)
	local id = Util.str(p.id, 40)
	local c = citizen(id)
	if not c or c.key then
		return { ok = false, err = "nobody" }
	end
	if not nearCitizen(player, id, p.pos) then
		return { ok = false, err = "far" }
	end
	local rec = recOf(sess, id, true)
	local kind = Util.str(p.kind, 20) or "talk"
	sess.talk = { id = id, since = os.clock(), first = true, kind = kind, chan = "talk" }
	player:SetAttribute(M.Attr.Busy, id)
	local env = envFor(player, id, sess)
	if kind ~= "talk" then
		local out = nil
		if Talk and (kind == "chatty" or kind == "friend") then
			sess.talk.tc = {}
			local ok, res = pcall(Talk.opener, c, rec, env, sess.talk.tc)
			out = if ok then res else nil
		end
		out = out or M.opener(c, rec, kind, env)
		-- 걸렁뱅이: the walk-up is a money demand (no money / no -> a fight)
		if kind == "punk" and M.DEMAND and M.mood(c, rec, env.aff) ~= "good" then
			local amount = M.DEMAND_AMOUNTS[math.random(#M.DEMAND_AMOUNTS)]
			sess.talk.demand = { amount = amount, n = 1 }
			local l = M.DEMAND.ask[math.random(#M.DEMAND.ask)]
			table.insert(out.lines, M.voice(M.fill(l, { money = M.won(amount) }), "punk", math.random))
			while #out.lines > 2 do
				table.remove(out.lines, 1)
			end
			local chips = {}
			for _, ch in M.DEMAND.chips do
				table.insert(chips, ch)
			end
			out.ask = { kind = "demand", chips = chips }
		end
		applyOut(player, sess, id, rec, out, { noAff = true })
		sess.talk.first = false
		return answer(player, sess, id, out)
	end
	-- the player started it: nothing said yet (the client sends the first "say")
	return { ok = true, view = viewOf(player, sess, id), wanted = sess.state.wanted or 0 }
end

-- one composer reply (no state applied yet): the "about" person, the number through Relationships
local function ruleOut(player: Player, sess: Sess, id: string, req: any, chan: string, env: any): any
	local c = citizen(id)
	local rec = recOf(sess, id, true)
	if req.intent == "about" and type(req.other) == "string" and citizen(req.other) then
		local oc = citizen(req.other)
		local oa = nil
		pcall(function()
			oa = Citizens.whereNow(req.other, env.clock)
		end)
		env.other = { id = req.other, name = shortName(req.other), area = oa and Citizens.AREAS[oa] and Citizens.AREAS[oa].label or nil, friend = Citizens.areFriends(id, req.other) }
		local _ = oc
	end
	req.chan = chan
	local out = M.respond(c, rec, req, env)
	-- the number goes through Relationships (its contact list / texts / phone)
	if out.act == "number" and social() then
		if hasNumber(player, id) then
			out.lines = { M.fill(Lines.G.number.already[out.reg or "p"][1], env.vars) }
		else
			local ok, res = pcall(social().handleChoice, player, id, "soc:number", false)
			if ok and type(res) == "table" and type(res.line) == "string" and res.line ~= "" then
				if not hasNumber(player, id) then
					out.lines = splitLines(res.line)
					out.face = "shy"
				end
			end
		end
	end
	return out
end

-- an appointment asked in words ("노래방 갈래?"): the same path as the meet menu
local function inviteOut(player: Player, sess: Sess, id: string, rec: any, out: any, kind: string, env: any)
	local c = citizen(id)
	local inv = Social and Social.INVITES[kind]
	if not c or not inv or not social() then
		return
	end
	local mood = M.mood(c, rec, env.aff)
	local reg = M.register(c, rec, env.aff)
	local arch = M.archOf(c)
	local key
	if inv.adult and c.minor then
		key = "minor"
	elseif mood == "bad" or mood == "angry" or mood == "enemy" or mood == "scared" or rec.tr < 12 then
		key = "no"
	end
	if key then
		local l = M.pick(M.sub("meet_r", key, arch, reg), rec, now())
		if l then
			out.lines = { M.fill(l, { placeName = inv.dest or "광안리", kind = inv.label }) }
		end
		out.face = "wary"
		return
	end
	local ok, res = pcall(social().handleChoice, player, id, "soc:inv:" .. kind, false)
	if ok and type(res) == "table" and type(res.line) == "string" and res.line ~= "" then
		out.lines = splitLines(res.line)
		M.remember(rec, "meet", kind, now())
		out.d.cl = (out.d.cl or 0) + 2
		out.face = "smile"
		out.emote = "nod"
	end
end

local function sayCommon(player: Player, sess: Sess, id: string, req: any, chan: string): any
	local rec = recOf(sess, id, true)
	local env = envFor(player, id, sess)
	local talk = sess.talk
	req.first = talk ~= nil and talk.first == true
	local out = ruleOut(player, sess, id, req, chan, env)
	if talk then
		talk.first = false
	end
	applyOut(player, sess, id, rec, out, nil)
	if out.act == "end" or out.act == "leave" then
		sess.talk = nil
		player:SetAttribute(M.Attr.Busy, "")
	end
	return answer(player, sess, id, out)
end

-- the reply to a 걸렁뱅이's money demand (nil = not about it)
local function demandReply(player: Player, sess: Sess, id: string, text: string): any?
	local talk = sess.talk
	local dm = talk and talk.id == id and talk.demand
	if not dm then
		return nil
	end
	local c = citizen(id)
	local rec = recOf(sess, id, true)
	local env = envFor(player, id, sess)
	local vars = { money = M.won(dm.amount) }
	local s = string.lower(text)
	local function has(w: string): boolean
		return string.find(s, w, 1, true) ~= nil
	end
	local it = M.parse(text, nil)
	local out = { lines = {}, d = { aff = 0, tr = 0, an = 0, fe = 0, cl = 0 }, mood = M.mood(c, rec, env.aff), stage = M.stage(rec, env.aff), reg = "c", intent = "small", mem = { k = "demand" } }
	local function say(key: string)
		local list = M.DEMAND[key]
		table.insert(out.lines, M.voice(M.fill(list[math.random(#list)], vars), "punk", math.random))
	end
	local function fight(key: string)
		say(key)
		out.act = "fight"
		out.face = "angry"
		out.d.an = 30
		talk.demand = nil
	end
	local pay = has("드릴") or has("줄게") or has("드려") or has("가져가") or has("여기") or has("옜다") or has("ㅇㅋ") or has("알겠") or has("💵") or it == "yes"
	local no = has("없") or has("싫") or has("안 줘") or has("못 줘") or has("안줘") or has("꺼져") or it == "no"
	if it == "insult" or it == "provoke" or it == "threaten" then
		fight("insult")
	elseif pay then
		local d = ctx.Profiles and ctx.Profiles.get and ctx.Profiles.get(player)
		if d and (d.cash or 0) >= dm.amount and ctx.ledger(player, "cash", -dm.amount, string.format("💸 %s에게 뜯김 (%s)", c.name, M.won(dm.amount)), false) then
			say("paid")
			out.act = "backoff"
			out.face = "smug"
			out.d.an = -15
			talk.demand = nil
			M.remember(rec, "money", dm.amount, now())
		else
			fight("nomoney")
		end
	elseif no then
		fight("refuse")
	elseif it == "apologize" and dm.n < 2 then
		dm.n += 1
		say("sorry")
		out.ask = { kind = "demand", chips = M.DEMAND.chips }
	else
		dm.n += 1
		if dm.n >= 3 then
			fight("refuse")
		else
			say("again")
			out.ask = { kind = "demand", chips = M.DEMAND.chips }
		end
	end
	applyOut(player, sess, id, rec, out, { noAff = true, noCrime = true })
	if out.act == "fight" or out.act == "backoff" then
		sess.talk = nil
		player:SetAttribute(M.Attr.Busy, "")
	end
	return answer(player, sess, id, out)
end

local function namesFor(id: string): { any }
	local names = {}
	for _, oid in Citizens.ORDER do
		local oc = Citizens.byId[oid]
		if oid ~= id and oc and not oc.key then
			table.insert(names, { id = oid, name = oc.name, short = shortName(oid) })
		end
	end
	return names
end

-- free text: GwangalliGameplay.Mind.Talk (context, facts, topics, places) over the composer;
-- the optional Brain (Claude) answers first when it is set up and quick enough
local function sayFree(player: Player, sess: Sess, id: string, text: string, chan: string): any
	local c = citizen(id)
	local rec = recOf(sess, id, true)
	local env = envFor(player, id, sess)
	local talk = if chan == "text" then nil else sess.talk
	env.first = (talk ~= nil and talk.first == true) or (chan == "text" and (now() - (rec.lt or 0)) > 3600)
	env.wanted = sess.state.wanted or 0
	env.liveNews = liveNews()
	local tc = if talk then talk.tc else sess.textCtx and sess.textCtx[id]
	if not tc then
		tc = {}
		if talk then
			talk.tc = tc
		else
			sess.textCtx = sess.textCtx or {}
			sess.textCtx[id] = tc
		end
	end
	local function rule(req: any): any
		req.first = false
		local e2 = table.clone(env)
		e2.vars = {}
		return ruleOut(player, sess, id, req, chan, e2)
	end
	local out = nil
	if Brain and Brain.ready() then
		out = Brain.reply(player, c, rec, text, env, tc, chan)
	end
	if not out then
		local ok, res = pcall(Talk.say, c, rec, text, env, tc, rule, namesFor(id))
		if ok and type(res) == "table" then
			out = res
		else
			if not ok then
				warn("[GwangalliMind] Talk.say: " .. tostring(res))
			end
			local it, slots = M.parse(text, namesFor(id))
			out = rule({ text = text, intent = it, polite = slots.polite, item = slots.item, other = slots.other })
		end
	end
	if talk then
		talk.first = false
	end
	if out.invite then
		inviteOut(player, sess, id, rec, out, out.invite, env)
	end
	-- the conversation as text (the Brain's context; the last turns are saved with the record)
	rec.cv = if type(rec.cv) == "table" then rec.cv else {}
	table.insert(rec.cv, { p = string.sub(text, 1, 140), n = string.sub(table.concat(out.lines, " "), 1, 200), t = now() })
	while #rec.cv > 8 do
		table.remove(rec.cv, 1)
	end
	applyOut(player, sess, id, rec, out, nil)
	if out.act == "end" or out.act == "leave" or out.act == "flee" then
		if talk then
			sess.talk = nil
			player:SetAttribute(M.Attr.Busy, "")
		end
	end
	return answer(player, sess, id, out), out
end

ops.say = function(player, sess, p)
	local id = Util.str(p.id, 40)
	local c = citizen(id)
	if not c then
		return { ok = false, err = "nobody" }
	end
	local talk = sess.talk
	local remote = talk ~= nil and talk.id == id and talk.chan == "call"
	if not remote and not nearCitizen(player, id, p.pos) then
		return { ok = false, err = "far" }
	end
	if not talk or talk.id ~= id then
		sess.talk = { id = id, since = os.clock(), first = true, kind = "talk", chan = "talk" }
		player:SetAttribute(M.Attr.Busy, id)
	end
	local text = Util.str(p.text, 140)
	local intent = Util.str(p.intent, 20)
	if text and not intent then
		local dr = demandReply(player, sess, id, text)
		if dr then
			return dr
		end
	end
	if text and not intent and Talk then
		return sayFree(player, sess, id, text, if remote then "call" else "talk")
	end
	local req = { text = text }
	if text then
		local names = {}
		for _, oid in Citizens.ORDER do
			local oc = Citizens.byId[oid]
			if oid ~= id and oc then
				table.insert(names, { id = oid, name = oc.name, short = shortName(oid) })
			end
		end
		local it, slots = M.parse(text, names)
		req.intent = it
		req.polite = slots.polite
		req.item = slots.item
		req.other = slots.other
	end
	if intent and M.INTENT_LABEL[intent] then
		req.intent = intent
		req.polite = p.polite ~= false
		req.item = Util.str(p.item, 20) or req.item
	end
	req.intent = req.intent or "small"
	return sayCommon(player, sess, id, req, if remote then "call" else "talk")
end

local GIVE_GAIN = { [1000] = 2, [5000] = 3.5, [10000] = 5, [50000] = 8 }

ops.act = function(player, sess, p)
	local id = Util.str(p.id, 40)
	local c = citizen(id)
	if not c then
		return { ok = false, err = "nobody" }
	end
	if not nearCitizen(player, id, p.pos) then
		return { ok = false, err = "far" }
	end
	local act = Util.str(p.act, 16)
	local rec = recOf(sess, id, true)
	local env = envFor(player, id, sess)
	local t = M.traits(c)
	local arch = t.arch
	local req = { intent = "small", first = false, chan = "talk" }
	local extra = nil
	local lines: { string }? = nil

	if act == "gift" then
		local gid = Util.str(p.arg, 24)
		local g = gid and Social.GIFTS[gid]
		if not g then
			return { ok = false }
		end
		req.intent = "gift_r"
		req.itemName = g.name
		if ctx.canAfford and not ctx.canAfford(player, g.price) then
			req.outcome = "nomoney"
		else
			local pref = Citizens.giftPref(id, gid, g.cat, g.adult)
			local ok, res = pcall(social().handleChoice, player, id, "soc:g:" .. gid, false)
			lines = if ok and type(res) == "table" then splitLines(res.line) else nil
			req.outcome = pref
			if pref ~= "refuse" then
				rec.gifts = (rec.gifts or 0) + 1
				M.remember(rec, "gift", g.name, now())
				extra = { tr = if pref == "love" then 5 elseif pref == "like" then 3 elseif pref == "dislike" then -1 else 1, cl = if pref == "love" then 4 else 2 }
				if pref == "love" and not table.find(rec.kn.gift, gid) then
					table.insert(rec.kn.gift, gid)
				end
			end
		end
	elseif act == "food" then
		local fid = Util.str(p.arg, 20)
		local f = fid and M.FOODS[fid]
		if not f then
			return { ok = false }
		end
		req.intent = "food_r"
		req.itemName = f.name
		local last = rec.cd.food or 0
		if f.adult and c.minor then
			req.outcome = "dislike"
		elseif now() - last < 600 then
			req.outcome = "full"
		elseif not (ctx.spend and ctx.spend(player, f.price, string.format("%s %s → %s", f.icon, f.name, c.name))) then
			req.outcome = "nomoney"
		else
			rec.cd.food = now()
			local pref = M.foodPref(c, fid)
			req.outcome = pref
			local gain = if pref == "love" then 5 elseif pref == "like" then 3 elseif pref == "neutral" then 1.5 else 0
			if arch == "homeless" then
				gain += 2
			end
			if gain > 0 then
				award(player, id, "food", gain)
			else
				award(player, id, "giftbad")
			end
			M.remember(rec, "food", fid, now())
			extra = { tr = if arch == "homeless" then 6 else (if pref == "dislike" then 0 else 2), cl = if pref == "love" then 4 else 2 }
			if pref == "love" and not table.find(rec.kn.food, fid) then
				table.insert(rec.kn.food, fid)
			end
			pcall(ctx.addStats, player, { happiness = 1 }, nil, true)
		end
	elseif act == "money" then
		local amount = tonumber(p.arg)
		if not amount or not table.find(M.MONEY, amount) then
			return { ok = false }
		end
		req.intent = "money_r"
		req.moneyText = M.won(amount)
		local d = ctx.Profiles and ctx.Profiles.get and ctx.Profiles.get(player)
		if not d or (d.cash or 0) < amount then
			req.outcome = "nomoney"
		elseif arch == "police" then
			req.outcome = "bribe"
			extra = { tr = -12, an = 10 }
			if amount >= 10000 then
				crime(player, sess, "bribe", id, nil)
			end
		elseif arch == "rich" then
			req.outcome = "insulted"
			extra = { an = 6, tr = -2 }
		elseif arch == "homeless" or arch == "punk" or arch == "thug" or arch == "fool" or arch == "drunk" or arch == "student" or arch == "parttimer" or t.greed > 0.65 then
			if ctx.ledger(player, "cash", -amount, string.format("💵 %s에게 %s", c.name, M.won(amount)), false) then
				req.outcome = if arch == "punk" or arch == "thug" then "greedy" else "happy"
				award(player, id, if Citizens.typeOf(id) == "beggar" then "give" else "money", GIVE_GAIN[amount] or 2)
				extra = { tr = if arch == "homeless" then 6 else 2, cl = 1.5, an = -10 }
				M.remember(rec, "money", amount, now())
				if arch == "homeless" then
					rec.help = (rec.help or 0) + 1
					M.remember(rec, "help", "money", now())
				end
				pcall(ctx.addStats, player, { happiness = 1, popularity = if amount >= 5000 then 1 else 0 }, nil, true)
			else
				req.outcome = "nomoney"
			end
		else
			req.outcome = "awkward"
			extra = { tr = 1 }
		end
	elseif act == "play" then
		local kind = Util.str(p.arg, 12) or "rps"
		req.intent = "play_r"
		local mood = M.mood(c, rec, env.aff)
		if (mood == "bad" or mood == "angry" or mood == "enemy" or mood == "scared") and kind ~= "prank" then
			req.outcome = "refuse"
		elseif kind == "rps" then
			local x = math.random()
			req.outcome = if x < 0.38 then "rps_win" elseif x < 0.76 then "rps_lose" else "rps_tie"
			award(player, id, "play", 1.5)
			extra = { cl = 1.5 }
		elseif kind == "selfie" then
			req.outcome = "selfie"
			award(player, id, "play", 2)
			extra = { cl = 2 }
			pcall(ctx.addStats, player, { happiness = 1, popularity = 1 }, nil, true)
		elseif kind == "prank" then
			local likes = arch == "fool" or arch == "student" or arch == "punk" or arch == "drunk" or (env.aff >= 50 and t.humor > 0.4)
			req.outcome = if likes then "prank" else "prank_bad"
			if likes then
				award(player, id, "play", 1.5)
				extra = { cl = 1.5 }
			else
				extra = { an = 10, tr = -2 }
				award(player, id, "harass", -2)
			end
		elseif kind == "walk" then
			local ok, res = pcall(social().handleChoice, player, id, "soc:inv:now", false)
			lines = if ok and type(res) == "table" then splitLines(res.line) else nil
			req.outcome = "walk"
			extra = { cl = 1 }
		end
	elseif act == "meet" then
		local kind = Util.str(p.arg, 12)
		local inv = kind and Social.INVITES[kind]
		if not inv then
			return { ok = false }
		end
		req.intent = "meet_r"
		req.kindName = inv.label
		req.placeName = inv.dest or "광안리"
		local mood = M.mood(c, rec, env.aff)
		if inv.adult and c.minor then
			req.outcome = "minor"
		elseif mood == "bad" or mood == "angry" or mood == "enemy" or mood == "scared" or rec.tr < 12 then
			req.outcome = "no"
		else
			local ok, res = pcall(social().handleChoice, player, id, "soc:inv:" .. kind, false)
			lines = if ok and type(res) == "table" then splitLines(res.line) else nil
			req.outcome = "yes"
			extra = { cl = 2 }
			M.remember(rec, "meet", kind, now())
		end
	elseif act == "hit" then
		req.intent = "hit_r"
		rec.hit = (rec.hit or 0) + 1
		M.remember(rec, "hit", 1, now())
		local fight = (arch == "thug" or arch == "hothead" or arch == "punk" or (t.brave > 0.7 and t.temper > 0.6)) and rec.fe < 50
		if rec.st == "lover" then
			req.outcome = "lover"
			rec.st = ""
		elseif arch == "police" then
			req.outcome = "angry"
		elseif fight then
			req.outcome = "fight"
		elseif t.brave < 0.45 then
			req.outcome = "scared"
		else
			req.outcome = "angry"
		end
		extra = { an = 40, fe = 20 + (1 - t.brave) * 40, tr = -30, cl = -5 }
		-- the hit itself (HP, KO, the reaction by personality, 폭행 with Law, 호감도) is the street
		-- fight module's; this card only words it
		local fr = ctx.fight and type(ctx.fight.applyHit) == "function" and ctx.fight.applyHit(player, { kind = if c.key then "npc" else "ped", id = id, pos = p.pos, attack = "punch", silent = true })
		if type(fr) == "table" then
			req.fightReact = fr.react
			if fr.react == "fight" then
				req.outcome = "fight"
			elseif fr.react == "flee" or fr.react == "cower" or fr.react == "ko" then
				req.outcome = "scared"
			elseif fr.react == "warn" then
				req.outcome = "angry"
			end
		else
			award(player, id, "assault")
			crime(player, sess, if arch == "police" then "assault_police" else "assault", id, vec(p.pos))
		end
	elseif act == "number" then
		return sayCommon(player, sess, id, { intent = "number" }, "talk")
	else
		return { ok = false }
	end

	local out = M.respond(c, rec, req, env)
	if lines and #lines > 0 then
		out.lines = lines
	end
	if extra then
		for k, v in extra do
			out.d[k] = (out.d[k] or 0) + v
		end
	end
	-- reactions the client plays (fight back / flee / report)
	if act == "hit" then
		local fr = req.fightReact
		if fr == "ko" then
			out.act = "ko"
		elseif fr == "fight" or fr == "flee" or fr == "report" or fr == "arrest" or fr == "cower" then
			out.act = fr
		elseif fr == "warn" then
			out.act = "escalate"
		else
			out.act = if req.outcome == "fight" then "fight" elseif req.outcome == "scared" then (if math.random() < 0.5 then "report" else "flee") elseif arch == "police" then "arrest" else "report"
		end
	end
	-- (a hit's report is already a 폭행 report: no extra 협박 for it)
	applyOut(player, sess, id, rec, out, { noAff = true, noCrime = act == "hit" })
	if act == "hit" and out.act == "report" then
		sess.reported = true
	end
	return answer(player, sess, id, out)
end

ops.close = function(player, sess, p)
	local id = Util.str(p.id, 40)
	if sess.talk and (not id or sess.talk.id == id) then
		sess.talk = nil
	end
	player:SetAttribute(M.Attr.Busy, "")
	return { ok = true }
end

-- the phone ---------------------------------------------------------------------------------------
ops.call = function(player, sess, p)
	local id = Util.str(p.id, 40)
	local c = citizen(id)
	if not c or not hasNumber(player, id) then
		return { ok = false, err = "nonumber" }
	end
	local rec = recOf(sess, id, true)
	local env = envFor(player, id, sess)
	local a = env.aff
	local mood = M.mood(c, rec, a)
	if mood == "angry" or mood == "enemy" or (math.random() < 0.12 and mood ~= "lover") then
		return { ok = true, noAnswer = true, view = viewOf(player, sess, id) }
	end
	sess.talk = { id = id, since = os.clock(), first = true, kind = "call", chan = "call" }
	local out = M.respond(c, rec, { intent = "greet", first = true, chan = "call" }, env)
	table.insert(out.lines, 1, if out.reg == "c" then "여보세요? 오 " .. player.DisplayName .. "!" else "여보세요? 아, " .. player.DisplayName .. "님!")
	award(player, id, "call")
	out.d.cl = (out.d.cl or 0) + 1.5
	M.remember(rec, "called", 1, now())
	applyOut(player, sess, id, rec, out, { noAff = true })
	sess.talk.first = false
	return answer(player, sess, id, out)
end

local function textReply(player: Player, sess: Sess, id: string, req: any): any
	local c = citizen(id)
	local rec = recOf(sess, id, true)
	local env = envFor(player, id, sess)
	req.chan = "text"
	req.first = (now() - (rec.lt or 0)) > 3600
	local out = M.respond(c, rec, req, env)
	applyOut(player, sess, id, rec, out, nil)
	local msg = table.concat(out.lines, " ")
	table.insert(rec.txt, { f = "npc", m = msg, t = now() })
	while #rec.txt > M.TXT_MAX do
		table.remove(rec.txt, 1)
	end
	return out, msg
end

ops.text = function(player, sess, p)
	local id = Util.str(p.id, 40)
	local c = citizen(id)
	if not c or not hasNumber(player, id) then
		return { ok = false, err = "nonumber" }
	end
	local rec = recOf(sess, id, true)
	local text = Util.str(p.text, 140)
	local intent = Util.str(p.intent, 20)
	local req = { text = text }
	if text then
		local it, slots = M.parse(text, nil)
		req.intent, req.polite, req.item = it, slots.polite, slots.item
	end
	if intent and M.INTENT_LABEL[intent] then
		req.intent = intent
		req.polite = true
		text = text or M.playerLine(intent, M.register(c, rec, (affOf(player, id))) == "c", { you = player.DisplayName })
	end
	req.intent = req.intent or "small"
	table.insert(rec.txt, { f = "me", m = text or "…", t = now() })
	local out, msg
	if text and not (intent and M.INTENT_LABEL[intent]) and Talk then
		local _, o = sayFree(player, sess, id, text, "text")
		out = o
		msg = table.concat(o.lines, " ")
		table.insert(rec.txt, { f = "npc", m = msg, t = now() })
		while #rec.txt > M.TXT_MAX do
			table.remove(rec.txt, 1)
		end
	else
		out, msg = textReply(player, sess, id, req)
	end
	return { ok = true, reply = msg, delay = 1.2 + math.random() * 2.2, out = { face = out.face, ask = out.ask, act = out.act }, view = viewOf(player, sess, id), thread = rec.txt }
end

ops.meet = function(player, sess, p)
	local id = Util.str(p.id, 40)
	local c = citizen(id)
	local kind = Util.str(p.kind, 12)
	local inv = kind and Social.INVITES[kind]
	if not c or not inv or not hasNumber(player, id) then
		return { ok = false }
	end
	local rec = recOf(sess, id, true)
	local a = affOf(player, id)
	local mood = M.mood(c, rec, a)
	local msg
	if inv.adult and c.minor then
		msg = M.pick(M.sub("meet_r", "minor", M.archOf(c), M.register(c, rec, a)), rec, now())
	elseif mood == "bad" or mood == "angry" or mood == "enemy" or mood == "scared" then
		msg = M.pick(M.sub("meet_r", "no", M.archOf(c), M.register(c, rec, a)), rec, now())
	else
		local ok, res = pcall(social().handleChoice, player, id, "soc:inv:" .. kind, true)
		msg = if ok and type(res) == "table" and type(res.line) == "string" then string.gsub(res.line, "\n", " ") else "음… 다음에!"
		M.remember(rec, "meet", kind, now())
		M.apply(rec, { cl = 1 }, now())
	end
	msg = M.fill(msg or "…", { you = player.DisplayName, place = inv.dest or "", kind = inv.label })
	table.insert(rec.txt, { f = "me", m = inv.icon .. " " .. inv.label, t = now() })
	table.insert(rec.txt, { f = "npc", m = msg, t = now() })
	markDirty(sess)
	return { ok = true, reply = msg, delay = 1.5 + math.random() * 2, view = viewOf(player, sess, id), thread = rec.txt }
end

ops.thread = function(player, sess, p)
	local id = Util.str(p.id, 40)
	local rec = id and recOf(sess, id, false)
	return { ok = true, thread = rec and rec.txt or {}, view = id and viewOf(player, sess, id) }
end

-- test harness only (workspace.GwangalliStreetLifeDebug): fast-forward a friendship
ops.debug = function(player, sess, p)
	if workspace:GetAttribute("GwangalliStreetLifeDebug") ~= true then
		return { ok = false, err = "off" }
	end
	local id = Util.str(p.id, 40)
	local s = social()
	if not citizen(id) or not s or type(s.debugSet) ~= "function" then
		return { ok = false }
	end
	local rec = recOf(sess, id, true)
	rec.tk = math.max(rec.tk or 0, 1)
	rec.nm = true
	local ok, tier = s.debugSet(player, id, tonumber(p.aff) or 55)
	markDirty(sess)
	return { ok = ok, tier = tier, view = viewOf(player, sess, id) }
end

-- the police -----------------------------------------------------------------------------------------
ops.police = function(player, sess, p)
	local op = Util.str(p.op, 12)
	if ctx and ctx.law then
		-- the server police (Law) run encounters; only an insult said to a street officer still counts
		if op == "insult" then
			crime(player, sess, "insult_police", Util.str(p.copId, 40), nil)
		end
		return { ok = false, err = "law" }
	end
	local stars = sess.state.wanted or 0
	local copId = Util.str(p.copId, 40)
	local fine = M.fineFor(math.max(1, stars))
	local vars = { money = M.won(fine), you = player.DisplayName }
	if op == "open" then
		sess.police = { copId = copId, since = os.clock() }
		if stars <= 0 then
			return { ok = true, line = M.policeLine("calm", vars), done = true }
		end
		return { ok = true, line = M.policeLine("arrive", vars) .. " " .. M.policeLine("ask", vars), chips = { { id = "sorry", label = "🙏 잘못했어요 (벌금 " .. M.won(fine) .. ")" }, { id = "excuse", label = "🤥 변명하기" }, { id = "insult", label = "🤬 욕하기" }, { id = "flee", label = "🏃 도망가기" } }, stars = stars }
	elseif op == "sorry" then
		local first = (sess.state.fines or 0) == 0
		local amount = if first then math.floor(fine * 0.6 / 1000) * 1000 else fine
		vars.money = M.won(amount)
		local paid = chargeFine(player, amount, "🚓 벌금 · 광안지구대")
		sess.state.fines = (sess.state.fines or 0) + 1
		setWanted(player, sess, 0, "벌금 " .. M.won(paid) .. " 납부")
		sess.police = nil
		addNews("경찰이 해변에서 누구한테 벌금 딱지를 끊었대요.")
		return { ok = true, line = M.policeLine("sorry", vars), done = true, fine = paid }
	elseif op == "excuse" then
		if math.random() < (if stars <= 1 then 0.45 else 0.2) then
			setWanted(player, sess, stars - 1, "경찰이 이번엔 봐줬어요")
			sess.police = nil
			return { ok = true, line = M.policeLine("excuse_ok", vars), done = true }
		end
		local paid = chargeFine(player, fine, "🚓 벌금 · 광안지구대")
		sess.state.fines = (sess.state.fines or 0) + 1
		setWanted(player, sess, 0, "벌금 " .. M.won(paid) .. " 납부")
		sess.police = nil
		vars.money = M.won(paid)
		return { ok = true, line = M.policeLine("excuse_no", vars), done = true, fine = paid }
	elseif op == "insult" or op == "flee" then
		if op == "insult" then
			crime(player, sess, "insult_police", copId, nil)
		else
			crime(player, sess, "flee", copId, nil)
		end
		return { ok = true, line = M.policeLine(if op == "insult" then "resist" else "chase", vars), chase = true, stars = sess.state.wanted }
	elseif op == "caught" then
		local amount = math.floor(M.fineFor(math.max(2, stars)) * 1.5 / 1000) * 1000
		vars.money = M.won(amount)
		local paid = chargeFine(player, amount, "🚓 벌금 · 도주 / 공무집행방해")
		sess.state.fines = (sess.state.fines or 0) + 1
		setWanted(player, sess, 0, "체포 · 벌금 " .. M.won(paid))
		sess.police = nil
		addNews("경찰이 도망가던 사람을 잡았대요!")
		return { ok = true, line = M.policeLine("caught", vars), done = true, fine = paid }
	elseif op == "lost" then
		sess.police = nil
		return { ok = true, line = M.policeLine("lost", vars), done = true }
	end
	return { ok = false }
end

-- a witness phoned 112: only counts right after a real crime by this player
ops.report = function(player, sess, p)
	if ctx and ctx.law then
		local pos = p and Util.vec and Util.vec(p.pos) or nil
		return { ok = ctx.law.report(player, "witness", pos) == true }
	end
	if os.clock() - (sess.lastCrime or -1e9) > 45 then
		return { ok = false }
	end
	if not sess.reported then
		sess.reported = true
		if (sess.state.wanted or 0) < 1 then
			setWanted(player, sess, 1, "목격자가 신고했어요")
		end
		push(player, { kind = "dispatch", stars = sess.state.wanted })
	end
	return { ok = true }
end

-- street behaviour memory (rate limited by the bucket; tiny effects only)
ops.street = function(player, sess, p)
	local id = Util.str(p.id, 40)
	local ev = Util.str(p.ev, 16)
	local c = citizen(id)
	if not c or not ev then
		return { ok = false }
	end
	if not nearCitizen(player, id, p.pos, 60) then
		return { ok = false }
	end
	local rec = recOf(sess, id, true)
	local t = now()
	if ev == "ignored" then
		M.apply(rec, { an = 4 }, t)
		M.remember(rec, "ignored", 1, t)
	elseif ev == "laughed" then
		M.apply(rec, { cl = 1.5, an = -5 }, t)
		award(player, id, "laughoff", 2)
		M.remember(rec, "laughed", 1, t)
	elseif ev == "scolded" then
		M.apply(rec, { an = 5, fe = 4 }, t)
		award(player, id, "harass", -1)
		M.remember(rec, "scolded", 1, t)
	elseif ev == "bumped_by" then
		M.remember(rec, "bumped_by", 1, t)
	elseif ev == "helped" then
		rec.help = (rec.help or 0) + 1
		M.apply(rec, { tr = 4, cl = 2 }, t)
		M.remember(rec, "help", 1, t)
	else
		return { ok = false }
	end
	markDirty(sess)
	return { ok = true, view = viewOf(player, sess, id) }
end

-------------------------------------------------------------------------------------------------
-- Hooks for the other modules (Bump: the player knocked somebody down)
-------------------------------------------------------------------------------------------------
function MindServer.note(player: Player, id: string, kind: string, x: any)
	local sess = sessOf(player)
	local c = citizen(id)
	if not sess or not c then
		return
	end
	local rec = recOf(sess, id, true)
	local t = now()
	if kind == "bump" then
		M.remember(rec, "bump", x, t)
		-- the shove counts against their HP and they remember it a while (GwangalliGameplay/Fight);
		-- 어깨빵 plays its own fall and reaction, so no second reaction / no 폭행 here
		if ctx.fight and type(ctx.fight.applyHit) == "function" then
			pcall(ctx.fight.applyHit, player, { kind = if c.key then "npc" else "ped", id = id, attack = "shove", outcome = x, silent = true, noCrime = true, noReact = true })
		end
		local tr = M.traits(c)
		M.apply(rec, { an = (if x == "knockdown" then 18 else 8) + tr.temper * 10, fe = (if x == "knockdown" then 10 else 3) * (1 - tr.brave), tr = -3 }, t)
		-- a run of knockdowns on people is trouble with the police
		if x == "knockdown" then
			table.insert(sess.bumps, os.clock())
			local n = 0
			for i = #sess.bumps, 1, -1 do
				if os.clock() - sess.bumps[i] < 60 then
					n += 1
				end
			end
			while #sess.bumps > 6 do
				table.remove(sess.bumps, 1)
			end
			if n >= 3 and Citizens.typeOf(id) ~= "fool" then
				crime(player, sess, "bumps", id, nil)
				table.clear(sess.bumps)
			end
		end
	end
	markDirty(sess)
end

-------------------------------------------------------------------------------------------------
-- Snapshot
-------------------------------------------------------------------------------------------------
function MindServer.snapshot(player: Player): any?
	local sess = sessOf(player)
	if not sess then
		return nil
	end
	local npcs = {}
	for id, rec in sess.state.npcs do
		if citizen(id) and ((rec.tk or 0) > 0 or (rec.mem and #rec.mem > 0)) then
			npcs[id] = viewOf(player, sess, id)
		end
	end
	local contacts = {}
	local soc = socialRec(player, "__") -- (the whole snapshot is the second return)
	local _, snap = socialRec(player, "__")
	local _ = soc
	if type(snap) == "table" and type(snap.contacts) == "table" then
		for _, ct in snap.contacts do
			local v = viewOf(player, sess, ct.id)
			if v then
				v.where = ct.where
				v.here = ct.here
				v.whereDest = ct.whereDest
				v.name = v.name or ct.name -- with their number you know their name
				table.insert(contacts, v)
				local rec = recOf(sess, ct.id, true)
				if rec and not rec.nm then
					rec.nm = true
				end
			end
		end
	end
	local threads = {}
	for id, rec in sess.state.npcs do
		if rec.txt and #rec.txt > 0 then
			threads[id] = rec.txt
		end
	end
	return { kind = "snapshot", npcs = npcs, contacts = contacts, wanted = sess.state.wanted or 0, threads = threads, companion = type(snap) == "table" and snap.companion or false }
end

-------------------------------------------------------------------------------------------------
-- NPC-initiated texts (friends, lovers, people who owe you) + wanted cooling
-------------------------------------------------------------------------------------------------
local TEXT_OPENERS = {
	p = { "{you}님, 뭐 하세요? ㅎㅎ", "오늘 날씨 좋네요! 광안리 나올래요?", "아까 생각나서 문자 해요 ㅎㅎ", "혹시 오늘 시간 있어요?", "요즘 잘 지내요?" },
	c = { "뭐 해? ㅋㅋ", "심심하다~ 나와!", "오늘 저녁 뭐 먹을래?", "야 광안대교 불 켜졌다 보러 와!", "갑자기 니 생각나서 ㅎㅎ", "오늘 당구 한 게임 어때?", "포차 갈래? 오늘 내가 쏜다 ㅋㅋ" },
	lover = { "자기야 뭐 해? 💕", "보고 싶어… 오늘 볼 수 있어?", "오늘 데이트 하자 💕 광안리에서 만날래?", "자기 생각하다가 문자 해 ㅎㅎ", "잘 자 💕 꿈에서 봐" },
}
local function textTick(player: Player, sess: Sess)
	if os.clock() < sess.nextText then
		return
	end
	sess.nextText = os.clock() + TEXT_GAP[1] + math.random() * (TEXT_GAP[2] - TEXT_GAP[1])
	local _, snap = socialRec(player, "__")
	if type(snap) ~= "table" or type(snap.contacts) ~= "table" or #snap.contacts == 0 then
		return
	end
	-- the warmer the relationship, the likelier they write
	local best, bestW = nil, 0
	for _, ct in snap.contacts do
		local rec = recOf(sess, ct.id, true)
		if rec and M.stage(rec, ct.a) ~= "enemy" and rec.an < 30 then
			local w = (ct.a + rec.cl) * (if rec.st == "lover" then 2.5 else 1) * math.random()
			if now() - (rec.lt or 0) < 120 then
				w *= 0.2 -- just talked
			end
			if w > bestW then
				best, bestW = ct, w
			end
		end
	end
	if not best or bestW < 25 then
		return
	end
	local c = citizen(best.id)
	local rec = recOf(sess, best.id, true)
	local reg = if rec.st == "lover" then "lover" else M.register(c, rec, best.a)
	local list = TEXT_OPENERS[reg] or TEXT_OPENERS.p
	local msg = M.fill(list[math.random(#list)], { you = player.DisplayName })
	msg = M.voice(msg, M.archOf(c), math.random)
	if c.speech == "busan" then
		msg = M.dialect(msg, if reg == "p" then "p" else "c", math.random)
	end
	table.insert(rec.txt, { f = "npc", m = msg, t = now() })
	while #rec.txt > M.TXT_MAX do
		table.remove(rec.txt, 1)
	end
	markDirty(sess)
	push(player, { kind = "text", id = best.id, name = c.name, msg = msg })
	notify(player, "message", "💬 " .. c.name, msg)
end

local function wantedTick(player: Player, sess: Sess)
	if ctx and ctx.law then
		sess.state.wanted = ctx.law.stars(player)
		return -- decay is the Law module's (only while the police lose sight of you)
	end
	local stars = sess.state.wanted or 0
	if stars <= 0 then
		return
	end
	if sess.police then
		return -- questioning / chase in progress
	end
	if os.clock() - (sess.lastCrime or -1e9) > M.WANTED_COOL then
		sess.lastCrime = os.clock() - M.WANTED_COOL * 0.4 -- next star a little faster
		setWanted(player, sess, stars - 1, if stars - 1 <= 0 then "경찰이 수색을 멈췄어요" else nil)
	end
end

-------------------------------------------------------------------------------------------------
-- Persistence
-------------------------------------------------------------------------------------------------
local function keyOf(player: Player): string
	return "u_" .. tostring(player.UserId)
end

local function packState(st: any): any
	local npcs = {}
	for id, r in st.npcs do
		local mem = {}
		for i = math.max(1, #r.mem - 19), #r.mem do
			table.insert(mem, r.mem[i])
		end
		local txt = {}
		for i = math.max(1, #r.txt - 19), #r.txt do
			table.insert(txt, r.txt[i])
		end
		npcs[id] = {
			v = r.v, tr = r.tr, an = r.an, fe = r.fe, cl = r.cl, clPeak = r.clPeak, nm = r.nm, kn = r.kn, st = r.st,
			tk = r.tk, lt = r.lt, fm = r.fm, mem = mem, gd = r.gd, gcl = r.gcl, hit = r.hit, ins = r.ins, help = r.help,
			gifts = r.gifts, txt = txt, u = r.u, at = r.at, cd = { food = r.cd and r.cd.food or nil, bmOffer = r.cd and r.cd.bmOffer or nil },
			pf = r.pf, bm = r.bm, cv = r.cv,
		}
	end
	return { v = st.v, npcs = npcs, wanted = st.wanted, crimes = st.crimes, fines = st.fines, u = st.u }
end

local function load(player: Player): any
	local st = newState()
	if store then
		local ok, data = pcall(function()
			return (store :: DataStore):GetAsync(keyOf(player))
		end)
		if ok and type(data) == "table" and type(data.npcs) == "table" then
			st.wanted = if type(data.wanted) == "number" then data.wanted else 0
			st.crimes = tonumber(data.crimes) or 0
			st.fines = tonumber(data.fines) or 0
			for id, r in data.npcs do
				local c = citizen(id)
				if c then
					st.npcs[id] = M.fixRec(r, c, now())
				end
			end
		end
	end
	return st
end

local function save(player: Player, sess: Sess)
	if not store or not sess.dirty then
		return
	end
	sess.dirty = false
	local packed = packState(sess.state)
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(keyOf(player), packed)
	end)
	if not ok then
		sess.dirty = true
		warn("[GwangalliMind] save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

local function attach(player: Player)
	if sessions[player] then
		return
	end
	local sess: Sess = { state = newState(), ready = false, dirty = false, talk = nil, police = nil, lastCrime = -1e9, crimeKind = nil, reported = false, bumps = {}, nextText = os.clock() + 150 + math.random() * 120, nextSave = os.clock() + AUTOSAVE, tokens = 10, tokT = os.clock() }
	sessions[player] = sess
	local st = load(player)
	if sessions[player] ~= sess then
		return
	end
	sess.state = st
	sess.ready = true
	if not (ctx and ctx.law) then
		player:SetAttribute(M.Attr.Wanted, st.wanted or 0)
	end
	player:SetAttribute(M.Attr.Busy, "")
	player:SetAttribute(M.Attr.Ready, true)
end

local function detach(player: Player)
	local sess = sessions[player]
	if not sess then
		return
	end
	if sess.ready then
		save(player, sess)
	end
	sessions[player] = nil
end

-------------------------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------------------------
local function makeRemotes()
	local folder = ReplicatedStorage:FindFirstChild(M.Folder)
	local fresh = folder == nil
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = M.Folder
	end
	local function remote(name: string, cls: string): any
		local r = (folder :: Instance):FindFirstChild(name)
		if r and r.ClassName ~= cls then
			r:Destroy()
			r = nil
		end
		if not r then
			r = Instance.new(cls)
			r.Name = name
			r.Parent = folder
		end
		return r
	end
	remotes.Talk = remote(M.Remote.Talk, "RemoteFunction")
	remotes.Event = remote(M.Remote.Event, "RemoteEvent")
	remotes.Get = remote(M.Remote.Get, "RemoteFunction")
	if fresh then
		(folder :: Instance).Parent = ReplicatedStorage
	end
end

function MindServer.init(context: any)
	ctx = context
	G = ctx.G
	Util = ctx.Util
	M = requireShared("GwangalliMindShared")
	Lines = requireShared("GwangalliMindLines")
	for _, name in { "Talk", "Brain" } do
		local m = script:FindFirstChild(name)
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok and type(res) == "table" then
				if name == "Talk" then
					Talk = res
				else
					Brain = res
				end
			else
				warn("[GwangalliMind] " .. name .. " failed to load: " .. tostring(res))
			end
		end
	end
	Citizens = requireShared("GwangalliCitizens")
	Social = requireShared("GwangalliSocialShared")
	if Talk then
		Talk.init({ M = M, Citizens = Citizens })
	end
	if Brain then
		Brain.init({ M = M, Citizens = Citizens, Talk = Talk, ctx = context })
	end
	Transit = requireShared("GwangalliTransitShared")
	if not M or not Citizens or not Social or not Util then
		warn("[GwangalliMind] shared modules missing; the NPC mind is off")
		return
	end
	-- saved exactly when Relationships saves 호감도 (a live place with profiles on), so feelings and
	-- 호감도 never disagree after a rejoin
	local okEnabled, en = pcall(function()
		return ctx.Profiles and ctx.Profiles.enabled and ctx.Profiles.enabled()
	end)
	if game.PlaceId ~= 0 and okEnabled and en then
		local okS, res = pcall(DataStoreService.GetDataStore, DataStoreService, M.DATASTORE)
		if okS and res then
			store = res
		end
	end
	makeRemotes()
	ctx.mind = MindServer
	;(remotes.Talk :: RemoteFunction).OnServerInvoke = function(player: Player, op: any, payload: any)
		local sess = sessOf(player)
		if not sess then
			return { ok = false, err = "loading" }
		end
		if type(op) ~= "string" or not ops[op] or (payload ~= nil and type(payload) ~= "table") then
			return { ok = false, err = "bad" }
		end
		if op ~= "close" and op ~= "thread" and not bucket(sess) then
			return { ok = false, err = "slow" }
		end
		local ok, r = pcall(ops[op], player, sess, payload or {})
		if not ok then
			warn("[GwangalliMind] " .. op .. " failed: " .. tostring(r))
			return { ok = false, err = "error" }
		end
		return r
	end
	;(remotes.Get :: RemoteFunction).OnServerInvoke = function(player: Player)
		local ok, snap = pcall(MindServer.snapshot, player)
		return if ok then snap else nil
	end
	for _, p in Players:GetPlayers() do
		task.spawn(attach, p)
	end
	Players.PlayerAdded:Connect(attach)
	Players.PlayerRemoving:Connect(detach)
	game:BindToClose(function()
		for p, sess in sessions do
			if sess.ready then
				save(p, sess)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			for p, sess in sessions do
				if sess.ready and p.Parent == Players then
					pcall(wantedTick, p, sess)
					pcall(textTick, p, sess)
					if os.clock() >= sess.nextSave then
						sess.nextSave = os.clock() + AUTOSAVE
						task.spawn(save, p, sess)
					end
				end
			end
		end
	end)
	print("[GwangalliMind] ready (" .. #Citizens.ORDER .. " people, " .. (if store then "saved" else "not saved") .. ")")
end

return MindServer
