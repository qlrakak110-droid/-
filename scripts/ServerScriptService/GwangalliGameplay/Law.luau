-- GwangalliGameplay/Law (server, feature module; owner: law): 광안리 치안 — the one authority for 수배
-- (wanted stars), crimes and their reports, the police (child Police), arrests and the 유치장 (child
-- Jail), the player police job (child Cop) and the crime careers (child Crimes). Contract (numbers,
-- attributes, lines): ReplicatedStorage.GwangalliLawShared.
--
--   * CRIMES come from everywhere through Law.crime(player, kind, info): the street-life mind (insults,
--     shoves, hits, bribes, bumps; GwangalliGameplay.Mind routes its own crime() here), the petty /
--     organised crimes (Crimes), the driving watch (stolen cars, ramming a patrol car). A crime the
--     police did not see waits for a REPORT (신고): a witness on a client (MindTalk "report" -> Law.report),
--     the victim, or the automatic call after LS.CRIMES[kind].report seconds. Only a reported crime adds
--     stars and dispatches the police (to where it happened — not to where the suspect is now).
--   * WANTED: stars 0..5 with the attributes in LS.Attr (GwangalliWanted for the HUDs + the legacy
--     Wanted / PoliceChase / Arrested mirrors that Housing / GwangalliTravel read). Stars only drop while
--     no officer (NPC or player cop) has seen the suspect for TIERS[stars].search seconds (faster when the
--     police have lost every trace); each drop restarts the clock; 0 = 따돌림 (progress "police_escape").
--   * EPISODE: crimes since the last arrest / escape (severity points, fines). An arrest charges the
--     fine (cash, then bank, the rest becomes 미납 벌금 collected later), seizes part of the crime money
--     made since the last arrest (압수), adds a 전과 and sends the suspect to the 유치장 for
--     LS.sentenceFor(severity, priors) seconds (Jail). A 1-star minor offence ends with a ticket (Police).
--   * WARRANT: a reported crime stays arrestable by player cops for LS.WARRANT_WINDOW after the stars
--     are gone (Law.arrestable) — the only legal targets of the police job besides active stars.
--   * PERSISTENCE (d.law, kept by Profiles): 전과 / priors / debt / crime XP / police job XP, reputation,
--     false arrests, lock / the jail time left / stars carried over a leave (capped) / heist cooldowns.
--
-- REMOTES (ReplicatedStorage.GwangalliLaw): Action RemoteFunction (op, payload) -> {ok, err?, ...};
-- Event RemoteEvent server -> client {kind = "state" | "wanted" | "reported" | "seen" | "lost" |
-- "stop" | "ticket" | "arrest" | "jail" | "release" | "toast" | "cop" | "crime" | "big" ...}.
-- Core ops: state, surrender, stopAnswer {choice = "comply" | "flee"}; the children add their own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Law = {}

local ctx: any
local G: any
local Util: any
local LS: any -- GwangalliLawShared
local Nav: any = nil
local navDecoded: any = nil

local remotes: { [string]: Instance } = {}
local sessions: { [Player]: any } = {}
Law.ops = {} :: { [string]: (Player, any, any) -> any }
Law.children = {} :: { [string]: any }

local function now(): number
	return os.clock()
end
Law.now = now

local function unix(): number
	return os.time()
end

-------------------------------------------------------------------------------------------------
-- Small helpers (shared with the children through Law.*)
-------------------------------------------------------------------------------------------------
function Law.rootOf(player: Player): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

function Law.posOf(player: Player): Vector3?
	local r = Law.rootOf(player)
	return r and r.Position or nil
end

function Law.flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function Law.nav(): (any, any)
	if not Nav then
		local m = ReplicatedStorage:FindFirstChild("GwangalliNav")
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok and type(res) == "table" then
				Nav = res
				local okD, dec = pcall(res.decode)
				navDecoded = if okD then dec else nil
			end
		end
	end
	return Nav, navDecoded
end

function Law.areaName(pos: Vector3?): string
	local N = Law.nav()
	if not N or not pos then
		return "광안리"
	end
	local ok, node = pcall(N.nearest, pos, 120)
	if ok and node then
		local a = N.ped and N.ped.area and N.ped.area[node]
		local name = a and N.AREA_NAME and N.AREA_NAME[a]
		if type(name) == "string" then
			return (string.gsub(name, " %(.*%)$", ""))
		end
	end
	return "광안리"
end

function Law.push(player: Player, payload: any)
	local ev = remotes.Event :: RemoteEvent?
	if ev and player.Parent == Players then
		ev:FireClient(player, payload)
	end
end

function Law.pushAll(payload: any)
	local ev = remotes.Event :: RemoteEvent?
	if ev then
		ev:FireAllClients(payload)
	end
end

function Law.notify(player: Player, kind: string, title: string, body: string?)
	if ctx and ctx.notify then
		pcall(ctx.notify, player, kind, title, body or "")
	end
end

function Law.track(player: Player, key: string, n: number?)
	if ctx and ctx.progress and ctx.progress.track then
		pcall(ctx.progress.track, player, key, n or 1)
	end
end

function Law.profile(player: Player): any?
	return ctx and ctx.Profiles and ctx.Profiles.get(player) or nil
end

function Law.dirty(player: Player)
	if ctx and ctx.Profiles and ctx.Profiles.markDirty then
		pcall(ctx.Profiles.markDirty, player)
	end
end

function Law.ctx(): any
	return ctx
end

function Law.shared(): any
	return LS
end

function Law.isNight(): boolean
	if ctx and ctx.env then
		local ok, e = pcall(ctx.env)
		if ok and type(e) == "table" then
			if e.night ~= nil then
				return e.night == true
			end
			local c = tonumber(e.clock)
			if c then
				return c >= 19 or c < 6
			end
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- Persistent record (d.law)
-------------------------------------------------------------------------------------------------
local function num(v: any, def: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else def
end

local function sanitize(raw: any): any
	local r = if type(raw) == "table" then raw else {}
	local out = {
		v = 1,
		record = math.clamp(math.floor(num(r.record, 0)), 0, 100000),
		priors = {},
		debt = math.clamp(math.floor(num(r.debt, 0)), 0, 100000000),
		crimeXp = math.clamp(math.floor(num(r.crimeXp, 0)), 0, 10000000),
		copXp = math.clamp(math.floor(num(r.copXp, 0)), 0, 10000000),
		rep = math.clamp(num(r.rep, LS.REP_START), 0, 100),
		falseT = {},
		lockUntil = num(r.lockUntil, 0),
		jail = nil,
		carry = math.clamp(math.floor(num(r.carry, 0)), 0, 3),
		bigCool = {},
		big = nil,
		history = {},
		stats = {},
		orgTrust = math.clamp(num(r.orgTrust, 0), 0, 100),
	}
	if type(r.priors) == "table" then
		for _, t in r.priors do
			if type(t) == "number" and #out.priors < 20 then
				table.insert(out.priors, t)
			end
		end
	end
	if type(r.falseT) == "table" then
		for _, t in r.falseT do
			if type(t) == "number" and #out.falseT < 10 then
				table.insert(out.falseT, t)
			end
		end
	end
	if type(r.jail) == "table" and num(r.jail.left, 0) > 0 then
		out.jail = { left = math.clamp(num(r.jail.left, 0), 1, LS.JAIL_MAX), total = math.clamp(num(r.jail.total, 60), 1, LS.JAIL_MAX), sev = math.clamp(num(r.jail.sev, 1), 0, 99), label = if type(r.jail.label) == "string" then string.sub(r.jail.label, 1, 80) else "" }
	end
	if type(r.bigCool) == "table" then
		for id, t in r.bigCool do
			if type(id) == "string" and LS.BIG[id] and type(t) == "number" then
				out.bigCool[id] = t
			end
		end
	end
	if type(r.big) == "table" and type(r.big.id) == "string" and LS.BIG[r.big.id] then
		out.big = { id = r.big.id, step = math.clamp(math.floor(num(r.big.step, 1)), 1, 10), n = math.clamp(math.floor(num(r.big.n, 0)), 0, 99), started = num(r.big.started, unix()) }
	end
	if type(r.history) == "table" then
		for _, h in r.history do
			if type(h) == "table" and #out.history < 12 then
				table.insert(out.history, { t = num(h.t, 0), label = if type(h.label) == "string" then string.sub(h.label, 1, 80) else "", fine = math.floor(num(h.fine, 0)), jail = math.floor(num(h.jail, 0)) })
			end
		end
	end
	if type(r.stats) == "table" then
		for k, v in r.stats do
			if type(k) == "string" and #k <= 24 and type(v) == "number" then
				out.stats[k] = math.max(0, math.floor(v))
			end
		end
	end
	return out
end

local cleaned: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- d.law tables sanitised this session

function Law.data(player: Player): any
	local d = Law.profile(player)
	if not d then
		local s = sessions[player]
		if not s then
			return sanitize(nil)
		end
		s.temp = s.temp or sanitize(nil)
		return s.temp
	end
	if type(d.law) ~= "table" or not cleaned[d.law] then
		d.law = sanitize(d.law)
		cleaned[d.law] = true
	end
	return d.law
end

function Law.stat(player: Player, key: string, n: number?)
	local L = Law.data(player)
	L.stats[key] = (L.stats[key] or 0) + (n or 1)
	Law.dirty(player)
end

-------------------------------------------------------------------------------------------------
-- Sessions
-------------------------------------------------------------------------------------------------
local function newSess(player: Player): any
	return {
		player = player,
		stars = 0,
		sev = 0, -- episode severity points
		fine = 0, -- episode fines
		crimes = {}, -- episode crimes {kind, t, pos}
		pending = {}, -- unreported crimes {kind, t, due, pos, info}
		lastSeen = -1e9, -- os.clock() an officer last saw the suspect
		lastSeenPos = nil,
		knownPos = nil, -- where the police believe the suspect is (report / sighting)
		knownT = -1e9,
		warrantUntil = -1e9,
		warrantLabel = nil,
		crimeMoney = 0, -- crime income since the last arrest (part of it is seized on arrest)
		cuffed = false,
		handsUp = -1e9,
		temp = nil,
		lastStarDrop = 0,
		loaded = false,
	}
end

function Law.sess(player: Player): any?
	return sessions[player]
end

function Law.sessions(): { [Player]: any }
	return sessions
end

-------------------------------------------------------------------------------------------------
-- Attributes / state view
-------------------------------------------------------------------------------------------------
local function writeAttrs(player: Player, s: any)
	local A = LS.Attr
	player:SetAttribute(A.Wanted, s.stars)
	player:SetAttribute(A.WantedUntil, if s.stars > 0 then workspace:GetServerTimeNow() + 60 else 0)
	player:SetAttribute(A.LegacyWanted, s.stars)
	local chasing = s.stars > 0 and (now() - s.lastSeen) < 3
	player:SetAttribute(A.Chase, chasing)
	player:SetAttribute(A.Arrested, s.cuffed == true or s.jail ~= nil)
	player:SetAttribute(A.Cuffed, s.cuffed == true)
end
Law.writeAttrs = writeAttrs

function Law.view(player: Player): any
	local s = sessions[player]
	if not s then
		return { stars = 0 }
	end
	local L = Law.data(player)
	local lvl, cur, nxt = LS.crimeLevel(L.crimeXp)
	local cop = Law.children.Cop and Law.children.Cop.view(player) or nil
	local t = LS.TIERS[math.max(1, s.stars)]
	return {
		stars = s.stars,
		search = if s.stars > 0 then math.clamp((now() - s.lastSeen) / math.max(1, t.search), 0, 1) else 0,
		chase = s.stars > 0 and (now() - s.lastSeen) < 3,
		tierLabel = if s.stars > 0 then t.label else nil,
		cuffed = s.cuffed,
		jail = Law.children.Jail and Law.children.Jail.view(player) or nil,
		record = L.record,
		debt = L.debt,
		crimeXp = L.crimeXp,
		crimeLevel = lvl,
		crimeTitle = cur.title,
		crimeNext = nxt and nxt.xp or nil,
		crimeNextTitle = nxt and nxt.title or nil,
		warrant = now() < s.warrantUntil,
		cop = cop,
		big = Law.children.Crimes and Law.children.Crimes.bigView(player) or nil,
		episode = { sev = s.sev, fine = s.fine, n = #s.crimes },
	}
end

function Law.sendState(player: Player)
	local v = Law.view(player)
	v.kind = "state"
	Law.push(player, v)
end

-------------------------------------------------------------------------------------------------
-- Wanted
-------------------------------------------------------------------------------------------------
function Law.stars(player: Player): number
	local s = sessions[player]
	return s and s.stars or 0
end

function Law.setStars(player: Player, stars: number, why: string?)
	local s = sessions[player]
	if not s then
		return
	end
	stars = math.clamp(math.floor(tonumber(stars) or 0), 0, LS.MAX_STARS)
	local before = s.stars
	if stars == before then
		return
	end
	s.stars = stars
	if stars > before then
		s.lastSeen = math.max(s.lastSeen, now() - 1) -- the police just heard of you: the clock restarts
	end
	writeAttrs(player, s)
	player:SetAttribute(LS.Attr.Search, 0)
	if Law.children.Police then
		Law.children.Police.retier(player, s, before, stars)
	end
	Law.push(player, { kind = "wanted", stars = stars, before = before, why = why, tier = if stars > 0 then LS.TIERS[stars].label else nil })
	if stars > before then
		Law.notify(player, "warn", "🚨 수배 " .. LS.stars(stars), why or LS.TIERS[stars].label)
	elseif stars == 0 then
		if s.sev > 0 then
			-- got away: the crimes stay arrestable by player cops for a while (warrant)
			s.warrantUntil = now() + LS.WARRANT_WINDOW
			s.warrantLabel = s.crimes[#s.crimes] and LS.CRIMES[s.crimes[#s.crimes].kind].label or nil
			Law.track(player, "police_escape", 1)
			Law.stat(player, "escapes")
			Law.push(player, { kind = "escaped", why = why })
		end
		s.sev, s.fine, s.crimes = 0, 0, {}
		Law.notify(player, "info", "✅ 수배 해제", why or "경찰을 따돌렸어요")
	else
		Law.notify(player, "info", "⬇️ 수배 " .. LS.stars(stars), why or "경찰이 흔적을 놓치고 있어요")
	end
	Law.sendState(player)
end

-- an officer / cop saw the suspect at pos
function Law.seen(player: Player, pos: Vector3?, by: string?)
	local s = sessions[player]
	if not s or s.stars <= 0 then
		return
	end
	local fresh = now() - s.lastSeen > 4
	s.lastSeen = now()
	s.lastSeenPos = pos or Law.posOf(player)
	s.knownPos = s.lastSeenPos
	s.knownT = now()
	player:SetAttribute(LS.Attr.Seen, workspace:GetServerTimeNow())
	player:SetAttribute(LS.Attr.Search, 0)
	if fresh then
		writeAttrs(player, s)
		Law.push(player, { kind = "seen", by = by })
	end
end

-------------------------------------------------------------------------------------------------
-- Crimes and reports
-------------------------------------------------------------------------------------------------
local function report(player: Player, s: any, entry: any, by: string)
	local def = LS.CRIMES[entry.kind]
	if not def then
		return
	end
	entry.reported = true
	local target = math.max(s.stars + def.stars, def.min or 0)
	s.knownPos = entry.pos or Law.posOf(player)
	s.knownT = now()
	local area = Law.areaName(s.knownPos)
	Law.setStars(player, target, def.label .. " 신고 접수")
	if Law.children.Police then
		Law.children.Police.dispatch(player, s, s.knownPos, entry.kind, by)
	end
	if Law.children.Cop then
		Law.children.Cop.onReport(player, entry.kind, s.knownPos, s.stars)
	end
	Law.push(player, { kind = "reported", crime = entry.kind, label = def.label, by = by, area = area, stars = s.stars })
end

-- info = { pos?, victim?, victimName?, police? (the victim / witness is an officer), seen? (an officer
-- watched it), source?, silent? }
function Law.crime(player: Player, kind: string, info: any?): boolean
	local s = sessions[player]
	local def = LS.CRIMES[kind]
	if not s or not def or s.jail then
		return false
	end
	info = info or {}
	local pos = info.pos or Law.posOf(player)
	local entry = { kind = kind, t = now(), pos = pos, info = info, reported = false }
	table.insert(s.crimes, entry)
	if #s.crimes > 24 then
		table.remove(s.crimes, 1)
	end
	s.sev += def.sev or 1
	s.fine = math.min(LS.FINE_CAP, s.fine + (def.fine or 0))
	Law.stat(player, "crimes")
	if Law.children.Cop then
		Law.children.Cop.onCrime(player, kind)
	end
	Law.push(player, { kind = "crime", crime = kind, label = def.label, reported = false })
	local seen = info.police == true or info.seen == true or (Law.children.Police and Law.children.Police.sees(player)) or (Law.children.Cop and Law.children.Cop.witness(player, pos))
	if seen or not def.report then
		report(player, s, entry, if seen then "officer" else "victim")
	else
		local lo, hi = def.report[1], def.report[2]
		-- at night fewer people call at once; a crowd calls sooner (the client witnesses call Law.report)
		local delay = lo + math.random() * (hi - lo)
		if Law.isNight() then
			delay *= 1.2
		end
		entry.due = now() + delay
		table.insert(s.pending, entry)
		if not info.silent then
			Law.push(player, { kind = "toast", text = "👀 누가 봤을지도 몰라요… (" .. def.label .. ")" })
		end
	end
	return true
end

-- a witness / victim called 112 (client street-life witnesses, key NPCs, Crimes)
function Law.report(player: Player, by: string?, pos: Vector3?): boolean
	local s = sessions[player]
	if not s then
		return false
	end
	local best = nil
	for _, e in s.pending do
		if not e.reported and now() - e.t < 60 then
			best = e
		end
	end
	if not best then
		return false
	end
	for i, e in s.pending do
		if e == best then
			table.remove(s.pending, i)
			break
		end
	end
	report(player, s, best, by or "witness")
	return true
end

-- crimes that are arrestable now (active stars or a recent, reported, unpunished crime)
function Law.arrestable(player: Player): (boolean, string?)
	local s = sessions[player]
	if not s or s.jail or s.cuffed then
		return false, nil
	end
	if s.stars > 0 then
		return true, "수배 " .. LS.stars(s.stars)
	end
	if now() < s.warrantUntil then
		return true, "수배 기록 (" .. tostring(s.warrantLabel or "범죄") .. ")"
	end
	return false, nil
end

-------------------------------------------------------------------------------------------------
-- Money: fines (cash -> bank -> 미납), crime income, confiscation
-------------------------------------------------------------------------------------------------
function Law.charge(player: Player, amount: number, label: string): (number, number)
	amount = math.max(0, math.floor(amount))
	if amount <= 0 or not ctx then
		return 0, 0
	end
	local d = Law.profile(player)
	local paid = 0
	local cash = d and d.cash or 0
	local fromCash = math.min(cash, amount)
	if fromCash > 0 and ctx.ledger(player, "cash", -fromCash, label, true) then
		paid += fromCash
	end
	local rest = amount - paid
	if rest > 0 then
		local bank = d and d.bank or 0
		local fromBank = math.min(bank, rest)
		if fromBank > 0 and ctx.ledger(player, "bank", -fromBank, label, true) then
			paid += fromBank
		end
	end
	local owed = amount - paid
	if owed > 0 then
		local L = Law.data(player)
		L.debt = math.min(100000000, L.debt + owed)
		Law.dirty(player)
	end
	return paid, owed
end

function Law.earnCrime(player: Player, amount: number, label: string, xp: number?)
	amount = math.max(0, math.floor(amount))
	local s = sessions[player]
	if amount > 0 and ctx then
		ctx.ledger(player, "cash", amount, label)
		if s then
			s.crimeMoney += amount
		end
	end
	if xp and xp > 0 then
		Law.addCrimeXp(player, xp)
	end
end

function Law.addCrimeXp(player: Player, xp: number)
	local L = Law.data(player)
	local before = LS.crimeLevel(L.crimeXp)
	L.crimeXp = math.max(0, L.crimeXp + math.floor(xp))
	local after, cur = LS.crimeLevel(L.crimeXp)
	player:SetAttribute(LS.Attr.CrimeLevel, after)
	Law.dirty(player)
	if after > before then
		Law.notify(player, "levelup", "🕶️ 범죄 등급 상승", "Lv." .. after .. " " .. cur.title)
		Law.push(player, { kind = "crimeLevel", level = after, title = cur.title })
	end
end

local function debtTick(player: Player)
	local L = Law.data(player)
	if L.debt <= 0 or not ctx then
		return
	end
	local d = Law.profile(player)
	local spare = (d and d.cash or 0) - 10000
	if spare >= 1000 then
		local take = math.min(spare, L.debt)
		if ctx.ledger(player, "cash", -take, "🚓 미납 벌금 자동 납부", true) then
			L.debt -= take
			Law.dirty(player)
			Law.notify(player, "money", "🚓 미납 벌금 -" .. LS.won(take), if L.debt > 0 then "남은 미납 " .. LS.won(L.debt) else "미납 벌금을 모두 냈어요")
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Arrest (any officer / cop) -> Jail; ticket (1-star minor offence)
-------------------------------------------------------------------------------------------------
-- info = { by = "npc" | "cop", cop = Player?, officer = any?, forced = bool, surrender = bool, auto = bool }
function Law.arrest(player: Player, info: any): boolean
	local s = sessions[player]
	if not s or s.jail or s.cuffed then
		return false
	end
	local ok = Law.arrestable(player)
	if not ok then
		return false
	end
	info = info or {}
	local L = Law.data(player)
	-- priors in the last 7 days
	local priors = 0
	local cutoff = unix() - 7 * 86400
	for _, t in L.priors do
		if t >= cutoff then
			priors += 1
		end
	end
	local sev = math.max(1, s.sev)
	local fine = math.max(s.fine, 20000)
	if info.surrender then
		fine *= LS.SURRENDER_MULT
	elseif info.forced then
		fine *= LS.FORCED_MULT
	end
	fine = math.min(LS.FINE_CAP, math.floor(fine / 1000 + 0.5) * 1000)
	local seconds, band = LS.sentenceFor(sev, priors)
	if info.surrender then
		seconds = math.max(LS.JAIL_MIN, math.floor(seconds * 0.8))
	end
	local labels = {}
	for _, e in s.crimes do
		local def = LS.CRIMES[e.kind]
		if def and not table.find(labels, def.label) then
			table.insert(labels, def.label)
		end
	end
	if #labels == 0 and s.warrantLabel then
		table.insert(labels, s.warrantLabel)
	end
	local crimesText = table.concat(labels, ", ")
	-- money
	local paid, owed = Law.charge(player, fine, "🚓 벌금 · " .. (if crimesText ~= "" then crimesText else "범죄"))
	local seized = 0
	if s.crimeMoney > 0 then
		local d = Law.profile(player)
		seized = math.min(math.floor(s.crimeMoney * LS.CONFISCATE), d and d.cash or 0)
		if seized > 0 and ctx.ledger(player, "cash", -seized, "🚓 범죄 수익 압수", true) then
			Law.notify(player, "money", "🚓 압수 -" .. LS.won(seized), "범죄로 번 돈 일부를 압수당했어요")
		else
			seized = 0
		end
	end
	s.crimeMoney = 0
	-- record
	L.record += 1
	table.insert(L.priors, unix())
	while #L.priors > 20 do
		table.remove(L.priors, 1)
	end
	table.insert(L.history, 1, { t = unix(), label = crimesText, fine = fine, jail = seconds })
	while #L.history > 12 do
		table.remove(L.history)
	end
	player:SetAttribute(LS.Attr.Record, L.record)
	Law.dirty(player)
	Law.track(player, "arrested", 1)
	Law.stat(player, "arrests")
	local episode = { sev = sev, fine = fine, paid = paid, owed = owed, seized = seized, crimes = crimesText, seconds = seconds, band = band.label, by = info.by, cop = info.cop, surrender = info.surrender == true }
	-- clear the case
	s.stars = 0
	s.sev, s.fine, s.crimes, s.pending = 0, 0, {}, {}
	s.warrantUntil = -1e9
	s.cuffed = true
	writeAttrs(player, s)
	if Law.children.Police then
		Law.children.Police.standDown(player, s, "arrest")
	end
	if Law.children.Jail then
		Law.children.Jail.begin(player, s, episode, info)
	end
	Law.sendState(player)
	return true
end

-- 1-star minor offence, the suspect complied: a ticket instead of the cell
function Law.ticket(player: Player, officerLabel: string?): number
	local s = sessions[player]
	if not s or s.stars <= 0 then
		return 0
	end
	local fine = math.max(15000, math.floor(math.max(s.fine, 20000) * 0.6 / 1000 + 0.5) * 1000)
	local paid, owed = Law.charge(player, fine, "🚓 범칙금 · " .. (officerLabel or "광안지구대"))
	Law.stat(player, "tickets")
	s.sev, s.fine, s.crimes, s.pending = 0, 0, {}, {}
	s.stars = 0
	s.warrantUntil = -1e9
	writeAttrs(player, s)
	if Law.children.Police then
		Law.children.Police.standDown(player, s, "ticket")
	end
	Law.push(player, { kind = "ticket", fine = fine, paid = paid, owed = owed })
	Law.notify(player, "money", "🚓 범칙금 " .. LS.won(fine), if owed > 0 then "미납 " .. LS.won(owed) .. "은 나중에 자동 납부돼요" else "이번엔 경고로 끝났어요")
	Law.sendState(player)
	return fine
end

-- the minor episode a ticket may settle: 1 star and nothing worse than severity 2
function Law.ticketable(player: Player): boolean
	local s = sessions[player]
	return s ~= nil and s.stars == 1 and s.sev <= 2
end

-------------------------------------------------------------------------------------------------
-- Core ops
-------------------------------------------------------------------------------------------------
Law.ops.state = function(player, s, _p)
	return { ok = true, state = Law.view(player) }
end

Law.ops.surrender = function(player, s, _p)
	if s.stars <= 0 or s.cuffed or s.jail then
		return { ok = false, err = "nothing" }
	end
	s.handsUp = now()
	player:SetAttribute("GwHandsUp", true)
	task.delay(6, function()
		if player.Parent and now() - s.handsUp >= 5.9 then
			player:SetAttribute("GwHandsUp", false)
		end
	end)
	if Law.children.Police then
		Law.children.Police.surrender(player, s)
	end
	return { ok = true }
end

Law.ops.stopAnswer = function(player, s, p)
	if Law.children.Police then
		return Law.children.Police.stopAnswer(player, s, p and p.choice)
	end
	return { ok = false }
end

-- test harness only (workspace.GwangalliStreetLifeDebug)
Law.ops.debug = function(player, s, p)
	if workspace:GetAttribute("GwangalliStreetLifeDebug") ~= true then
		return { ok = false, err = "off" }
	end
	if p.act == "crime" and type(p.kind) == "string" then
		local ok = Law.crime(player, p.kind, { seen = p.seen == true })
		if p.report then
			Law.report(player, "test", nil)
		end
		return { ok = ok, stars = s.stars }
	elseif p.act == "stars" then
		if (tonumber(p.n) or 0) > 0 and #s.crimes == 0 then
			table.insert(s.crimes, { kind = "assault", t = now(), pos = Law.posOf(player), reported = true })
			s.sev = math.max(s.sev, 2)
			s.fine = math.max(s.fine, 50000)
		end
		if Law.children.Police then
			-- test only: the case is worked by patrol cars alone (watch a car drive in, park, get out)
			Law.children.Police.testCarsOnly = p.carsOnly == true
			Law.children.Police.testNoGrab = p.noGrab == true
		end
		Law.setStars(player, tonumber(p.n) or 0, "test")
		if s.stars > 0 and Law.children.Police then
			Law.children.Police.dispatch(player, s, Law.posOf(player), "assault", "test")
		end
		return { ok = true, stars = s.stars }
	elseif p.act == "fakeCar" and Law.children.Police then
		Law.children.Police.testInCar = p.on == true
		return { ok = true }
	elseif p.act == "myCar" then
		-- test only: a car for the player (seated), moved along / out of it from the test harness
		local VA = game:GetService("ServerStorage"):FindFirstChild("GwangalliVehiclesAPI")
		if not VA then
			return { ok = false }
		end
		local op = tostring(p.op or "spawn")
		if op == "spawn" then
			task.spawn(function()
				local okC, a, b = pcall(function()
					return VA:Invoke("spawnOwned", player, { id = "test", kind = "sedan", color = Color3.fromRGB(40, 40, 48), colorId = "black", plate = "12가 3456", cond = 100, dirt = 0, label = "test" }, { near = Law.posOf(player), seat = true, force = true })
				end)
				workspace:SetAttribute("GwangalliTestCar", tostring(okC) .. "|" .. tostring(a) .. "|" .. tostring(b))
			end)
			return { ok = true }
		end
		local model = VA:Invoke("current", player)
		if not model then
			return { ok = false, err = "no car" }
		end
		if op == "move" then
			local pv = model:GetPivot()
			local dx, dz = tonumber(p.dx) or 0, tonumber(p.dz) or 0
			local to = pv.Position + Vector3.new(dx, 0, dz)
			local look = if math.abs(dx) + math.abs(dz) > 0.1 then Vector3.new(dx, 0, dz).Unit else pv.LookVector
			model:PivotTo(CFrame.lookAt(to, to + look))
			return { ok = true }
		elseif op == "eject" then
			VA:Invoke("eject", model)
			return { ok = true }
		end
		return { ok = false }
	elseif p.act == "carDemo" and Law.children.Police then
		local pp = Law.posOf(player)
		local off = Vector3.new(tonumber(p.dx) or 0, 0, tonumber(p.dz) or 0)
		return Law.children.Police.debugDemo(player, tostring(p.op or "spawn"), pp and (pp + off) or nil)
	elseif p.act == "arrest" then
		return { ok = Law.arrest(player, { by = "npc", forced = true }) }
	elseif p.act == "xp" then
		Law.addCrimeXp(player, tonumber(p.n) or 100)
		return { ok = true }
	elseif p.act == "units" then
		local P = Law.children.Police
		local out = {}
		if P then
			for _, o in P.officers() do
				table.insert(out, string.format("%s:%s:%s:%.0f", o.id, o.role, tostring(o.state), (Law.posOf(player) and Law.flat(o.pos, Law.posOf(player) :: Vector3)) or -1))
			end
			for _, c in P.cars() do
				table.insert(out, string.format("%s:%s:%s", c.id, c.role, tostring(c.state)))
			end
		end
		return { ok = true, units = table.concat(out, " | "), stars = s.stars, seen = now() - s.lastSeen }
	end
	return { ok = false }
end

-------------------------------------------------------------------------------------------------
-- Ticks
-------------------------------------------------------------------------------------------------
local function wantedTick(player: Player, s: any)
	-- pending reports
	if #s.pending > 0 then
		for i = #s.pending, 1, -1 do
			local e = s.pending[i]
			if e.due and now() >= e.due then
				table.remove(s.pending, i)
				report(player, s, e, "call")
			end
		end
	end
	if s.stars <= 0 or s.cuffed or s.jail then
		return
	end
	local t = LS.TIERS[s.stars]
	local hunting = Law.children.Police and Law.children.Police.hunting(player) or false
	local need = t.search * (if hunting then 1 else LS.WANTED_FLOOR_DECAY)
	local unseen = now() - s.lastSeen
	player:SetAttribute(LS.Attr.Search, math.clamp(unseen / need, 0, 1))
	local chasing = unseen < 3
	if player:GetAttribute(LS.Attr.Chase) ~= chasing then
		player:SetAttribute(LS.Attr.Chase, chasing)
	end
	if unseen >= need then
		s.lastSeen = now()
		Law.setStars(player, s.stars - 1, if s.stars - 1 <= 0 then "경찰을 완전히 따돌렸어요!" else "경찰이 당신을 놓쳤어요")
	end
end

local function attach(player: Player)
	if sessions[player] then
		return
	end
	local s = newSess(player)
	sessions[player] = s
	writeAttrs(player, s)
	player:SetAttribute(LS.Attr.Seen, 0)
	player:SetAttribute(LS.Attr.Search, 0)
	player:SetAttribute(LS.Attr.Jail, 0)
	player:SetAttribute(LS.Attr.Cop, false)
end

function Law.onLoaded(player: Player)
	attach(player)
	local s = sessions[player]
	local L = Law.data(player)
	s.loaded = true
	player:SetAttribute(LS.Attr.Record, L.record)
	player:SetAttribute(LS.Attr.CrimeLevel, (LS.crimeLevel(L.crimeXp)))
	-- the cell time left from last time (logging out does not dodge the 유치장)
	if L.jail and Law.children.Jail then
		local j = L.jail
		L.jail = nil
		task.delay(3, function()
			if player.Parent then
				s.cuffed = true
				Law.children.Jail.resume(player, s, j)
			end
		end)
	elseif L.carry > 0 then
		local carry = L.carry
		L.carry = 0
		task.delay(6, function()
			if player.Parent then
				s.sev = math.max(s.sev, carry)
				s.fine = math.max(s.fine, LS.FINE_CAP > 0 and 30000 * carry or 0)
				table.insert(s.crimes, { kind = "flee", t = now(), pos = Law.posOf(player), reported = true })
				Law.setStars(player, carry, "지난번 수배가 아직 남아 있어요")
			end
		end)
	end
	for _, c in Law.children do
		if type(c.onLoaded) == "function" then
			pcall(c.onLoaded, player, s)
		end
	end
	Law.sendState(player)
end

function Law.onCharacter(player: Player, character: Model)
	attach(player)
	local s = sessions[player]
	for _, c in Law.children do
		if type(c.onCharacter) == "function" then
			pcall(c.onCharacter, player, s, character)
		end
	end
end

function Law.onLeave(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	local L = Law.data(player)
	if s.stars > 0 and not s.jail then
		L.carry = math.min(3, s.stars)
	end
	for _, c in Law.children do
		if type(c.onLeave) == "function" then
			pcall(c.onLeave, player, s)
		end
	end
	Law.dirty(player)
	sessions[player] = nil
end

-------------------------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------------------------
local function makeRemotes()
	local folder = ReplicatedStorage:FindFirstChild(LS.Folder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = LS.Folder
		folder.Parent = ReplicatedStorage
	end
	local function remote(name: string, cls: string): Instance
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
		return r :: Instance
	end
	remotes.Action = remote(LS.Remote.Action, "RemoteFunction")
	remotes.Event = remote(LS.Remote.Event, "RemoteEvent")
end

local buckets: { [Player]: { t: number, n: number } } = {}
local function allow(player: Player): boolean
	local b = buckets[player]
	local t = now()
	if not b then
		b = { t = t, n = 12 }
		buckets[player] = b
	end
	b.n = math.min(12, b.n + (t - b.t) * 6)
	b.t = t
	if b.n < 1 then
		return false
	end
	b.n -= 1
	return true
end

local CHILDREN = { "Police", "Jail", "Cop", "Crimes", "City" }

function Law.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	local m = ReplicatedStorage:WaitForChild("GwangalliLawShared", 10)
	assert(m and m:IsA("ModuleScript"), "GwangalliLawShared missing")
	LS = require(m) :: any
	local problems = LS.selfTest()
	if #problems > 0 then
		warn("[GwangalliLaw] shared self-test: " .. table.concat(problems, "; "))
	end
	makeRemotes()
	ctx.law = Law
	workspace:SetAttribute(LS.Attr.Active, true)
	-- children (each: init(Law, ctx) and optional onLoaded / onCharacter / onLeave / tick(dt))
	for _, name in CHILDREN do
		local cm = script:FindFirstChild(name)
		if cm and cm:IsA("ModuleScript") then
			local ok, res = pcall(require, cm)
			if ok and type(res) == "table" then
				local okI, err = pcall(res.init, Law, ctx)
				if okI then
					Law.children[name] = res
				else
					warn("[GwangalliLaw] " .. name .. " init failed: " .. tostring(err))
				end
			else
				warn("[GwangalliLaw] " .. name .. " failed to load: " .. tostring(res))
			end
		end
	end
	;(remotes.Action :: RemoteFunction).OnServerInvoke = function(player: Player, op: any, payload: any)
		local s = sessions[player]
		if not s then
			return { ok = false, err = "loading" }
		end
		if type(op) ~= "string" or not Law.ops[op] or (payload ~= nil and type(payload) ~= "table") then
			return { ok = false, err = "bad" }
		end
		if op ~= "state" and not allow(player) then
			return { ok = false, err = "slow" }
		end
		local ok, r = pcall(Law.ops[op], player, s, payload or {})
		if not ok then
			warn("[GwangalliLaw] op " .. op .. " failed: " .. tostring(r))
			return { ok = false, err = "error" }
		end
		return r
	end
	for _, p in Players:GetPlayers() do
		attach(p)
	end
	Players.PlayerAdded:Connect(attach)
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
	-- 4 Hz: wanted / children; 1 Hz: debt
	task.spawn(function()
		local last = now()
		local slow = 0
		while true do
			task.wait(0.25)
			local t = now()
			local dt = math.min(1, t - last)
			last = t
			for p, s in sessions do
				if p.Parent == Players then
					local ok, err = pcall(wantedTick, p, s)
					if not ok then
						warn("[GwangalliLaw] wanted tick: " .. tostring(err))
					end
				end
			end
			for name, c in Law.children do
				if type(c.tick) == "function" then
					local ok, err = pcall(c.tick, dt)
					if not ok then
						warn("[GwangalliLaw] " .. name .. " tick: " .. tostring(err))
					end
				end
			end
			slow += dt
			if slow >= 30 then
				slow = 0
				for p in sessions do
					pcall(debtTick, p)
				end
			end
		end
	end)
	local names = {}
	for n in Law.children do
		table.insert(names, n)
	end
	table.sort(names)
	print("[GwangalliLaw] ready (" .. table.concat(names, ", ") .. ")")
end

return Law
