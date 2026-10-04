-- Progress (server feature module, docs/ECONOMY.md): 돈 버는 맛 + 인생 레벨 + 일일·주간 목표 + 업적 +
-- 마일스톤. Data / rules: ReplicatedStorage.GwangalliProgressShared (P). Client: GwangalliProgress.
--
-- DETECTION (server-side only, no client trust):
--   * the ledger: G.ledger (the one function every cash / bank change goes through, including
--     ctx.ledger / ctx.spend / ctx.bank.post / G.spend / housing) is wrapped once at init; each applied
--     entry is classified (P.classify) -> earnings / spending / internal, money pops, the day record
--     (payday card), auto keys (shift, taxi_ride, eat, gift, ...).
--   * player attributes set by other server modules: ClubOceanWristband (club entry), ClubVIPTable,
--     LastBowlingScore, GymBusy (+ d.gym.sets), HomeTier, Appearance / Strength / Popularity.
--   * a 1 Hz driver loop: driving minutes (Humanoid.SeatPart is a VehicleSeat), the player's life-day
--     rollover (payday card), the KST day / week (goal reset), owned cars / home (milestones).
--   * fallback until the owners add hooks: ctx.notify titles "배달 완료" / "승진!" / "합격!" (jobs).
--   * hooks: ctx.progress.track(player, key, n) — keys in P.KEYS (owner modules, one line each).
--
-- SERVER API
--   ctx.progress.track(player, key, n?)            count a goal / achievement event (n default 1)
--   ctx.progress.perk(player, id) -> value | false  level unlock (P.UNLOCKS: used_car_discount 0.05,
--                                                   home_loan 1, club_cover_discount 0.2, ...)
--   ctx.progress.level(player) -> level, earned
--   ctx.progress.reward(player, amount, label)     pay a reward into the bank (counts as earnings)
--   ctx.progress.celebrate(player, msId, name?)    force a milestone (first_car / first_home / ...)
--   ctx.progress.snapshot(player) -> P snapshot
--   ServerStorage.GwangalliProgressAPI (BindableFunction): Invoke(op, playerOrUserId, ...) with the
--   same ops ("track" | "perk" | "level" | "reward" | "celebrate" | "snapshot") for Scripts outside
--   GwangalliGameplay (e.g. Bowling.server.luau).
--
-- PERSISTENCE: d.progress (set in onLoaded, saved with the profile). Profiles.sanitize drops unknown
--   keys on load, so until it passes `progress` through (one line, see docs/ECONOMY.md) the record is
--   also kept in the DataStore P.DATASTORE (key u_<UserId>, merged with P.merge so a server hop never
--   loses progress). Memory only in Studio / unpublished places (same as Profiles).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Progress = {}

local ctx: any = nil
local G: any = nil
local P: any = nil
local Profiles: any = nil
local Util: any = nil

type Sess = {
	pr: any,
	d: any,
	ready: boolean,
	dirty: boolean,
	lastSave: number,
	pops: { [string]: any },
	updDirty: boolean,
	achDirty: boolean,
	driveT: number,
	lastGymSets: number,
	friends: number,
	friendsAt: number,
	clubDay: number,
	tick: number,
	conns: { RBXScriptConnection },
	paydayQueued: boolean,
	preq: { any }, -- events that arrived while the fallback copy was loading (replayed after the merge)
	rewardsAt: { number },
}

local sessions: { [Player]: Sess } = {}
local byData: { [any]: Player } = setmetatable({}, { __mode = "k" }) :: any
local serverSeen: { [string]: boolean } = {} -- hook keys reported on this server (liveness)
local hookKeys: { [string]: boolean } = {} -- keys reported by a real hook (the notify fallback steps aside)
local foodNames: { [string]: boolean } = {}
local remotes: { event: RemoteEvent?, request: RemoteFunction? } = {}
local profileHolds = false -- Profiles.sanitize keeps d.progress
local store: any = nil
local storeEnabled = false
local wrapped = false
local started = false

local AUTOSAVE = 90
local TRACK_MAX = 1e9

local function now(): number
	return os.time()
end

local function playerOf(v: any): Player?
	if typeof(v) == "Instance" and v:IsA("Player") then
		return v
	end
	if type(v) == "number" then
		return Players:GetPlayerByUserId(v)
	end
	return nil
end

local function fire(player: Player, msg: { [string]: any })
	local ev = remotes.event
	if ev and player.Parent == Players then
		ev:FireClient(player, msg)
	end
end

local function sess(player: Player): Sess?
	local s = sessions[player]
	if s and s.ready then
		return s
	end
	return nil
end

local function isLive(s: Sess?, key: string): boolean
	local k = P.KEYS[key]
	if not k then
		return false
	end
	if k.auto or k.live or serverSeen[key] then
		return true
	end
	return s ~= nil and (s.pr.c[key] or 0) > 0
end

-------------------------------------------------------------------------------------------------
-- Day records (payday card): one per player life-day (G.DAY_SECONDS of play)
-------------------------------------------------------------------------------------------------
local function dayRecord(s: Sess): any
	local pr = s.pr
	local day = math.max(1, math.floor(tonumber(s.d.lifeDay) or 1))
	local last = pr.days[#pr.days]
	if last and last.d == day then
		return last
	end
	local rec = { d = day, e = 0, s = 0, cats = {}, ecats = {}, best = 0 }
	table.insert(pr.days, rec)
	while #pr.days > P.HISTORY_DAYS + 1 do
		table.remove(pr.days, 1)
	end
	return rec
end

local function history(pr: any): { any }
	local out = {}
	for _, x in pr.days do
		table.insert(out, P.dayView(x))
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Attributes / views
-------------------------------------------------------------------------------------------------
local function applyAttributes(player: Player, s: Sess)
	local pr = s.pr
	local lv, lp = P.levelFor(pr.earned)
	player:SetAttribute(P.Attr.Level, lv)
	player:SetAttribute(P.Attr.LevelProgress, math.floor(lp * 1000) / 1000)
	player:SetAttribute(P.Attr.Title, P.titleFor(lv))
	local done = 0
	for _, g in pr.daily.goals do
		if g.done then
			done += 1
		end
	end
	player:SetAttribute(P.Attr.GoalsDone, done)
	player:SetAttribute(P.Attr.GoalsTotal, #pr.daily.goals)
end

local function goalsView(s: Sess): ({ any }, any?)
	local pr = s.pr
	local lv = pr.level
	local list = {}
	for _, g in pr.daily.goals do
		local def = P.GOAL_BY_ID[g.id]
		local v = P.goalView(g, false, lv, def and isLive(s, def.key))
		if v then
			table.insert(list, v)
		end
	end
	local w = pr.weekly.goal and P.goalView(pr.weekly.goal, true, lv, true) or nil
	return list, w
end

-------------------------------------------------------------------------------------------------
-- Metrics (achievements)
-------------------------------------------------------------------------------------------------
local function carsOwned(d: any): number
	local n = 0
	if type(d.cars) == "table" then
		for _, c in d.cars do
			if type(c) == "table" and not c.rental and not c.test then
				n += 1
			end
		end
	end
	return n
end

local function friendsCount(player: Player, s: Sess): number
	if os.clock() - s.friendsAt < 30 then
		return s.friends
	end
	s.friendsAt = os.clock()
	local social = ctx.social
	if type(social) == "table" and type(social.friends) == "function" then
		local ok, list = pcall(social.friends, player)
		if ok and type(list) == "table" then
			s.friends = #list
		end
	end
	return s.friends
end

local function metric(player: Player, s: Sess, m: string): number
	local d, pr = s.d, s.pr
	if m == "earned" then
		return pr.earned
	elseif string.sub(m, 1, 2) == "c:" then
		local key = string.sub(m, 3)
		local v = pr.c[key] or 0
		if key == "shift" then
			v = math.max(v, tonumber(d.shifts) or 0)
		end
		return v
	elseif string.sub(m, 1, 3) == "ms:" then
		return if pr.ms[string.sub(m, 4)] then 1 else 0
	elseif string.sub(m, 1, 5) == "stat:" then
		return tonumber(d.stats and d.stats[string.sub(m, 6)]) or 0
	elseif m == "bank" then
		return tonumber(d.bank) or 0
	elseif m == "net" then
		local ok, v = pcall(G.netWorth, d)
		return if ok and type(v) == "number" then v else 0
	elseif m == "level" then
		return pr.level
	elseif m == "bestPay" then
		return pr.best.pay
	elseif m == "bestDay" then
		local today = pr.days[#pr.days]
		return math.max(pr.best.day, today and today.e or 0)
	elseif m == "goals" then
		return pr.goalsDone
	elseif m == "weekly" then
		return pr.weeklyDone
	elseif m == "cars" then
		return math.max(carsOwned(d), if pr.ms.first_car then 1 else 0)
	elseif m == "homeTier" then
		return if d.home then (tonumber(d.home.tier) or 0) else 0
	elseif m == "homeOwned" then
		return if d.home and d.home.owned then 1 else 0
	elseif m == "jobs" then
		local n = 0
		if type(d.careerXp) == "table" then
			for _, x in d.careerXp do
				if type(x) == "number" and x > 0 then
					n += 1
				end
			end
		end
		return n
	elseif m == "promo" or m == "topRank" then
		local best = 0
		if type(d.careers) == "table" then
			for id, lv in d.careers do
				local job = G.JOBS and G.JOBS[id]
				if job and type(lv) == "number" then
					if m == "promo" and lv >= 2 then
						best = 1
					elseif m == "topRank" and lv >= #job.levels and #job.levels > 1 then
						best = 1
					end
				end
			end
		end
		return math.max(best, if m == "promo" and (pr.c.promotion or 0) > 0 then 1 else 0)
	elseif m == "friends" then
		return friendsCount(player, s)
	elseif m == "outfits" then
		local n = 0
		if type(d.owned) == "table" then
			for _, t in { d.owned.outfits, d.owned.hair } do
				if type(t) == "table" then
					for _ in t do
						n += 1
					end
				end
			end
		end
		return n
	elseif m == "gymSets" then
		return if type(d.gym) == "table" then (tonumber(d.gym.sets) or 0) else 0
	elseif m == "shifts" then
		return math.max(tonumber(d.shifts) or 0, pr.c.shift or 0)
	end
	return 0
end

-------------------------------------------------------------------------------------------------
-- Rewards (deferred: never re-enter G.ledger from inside the ledger hook)
-------------------------------------------------------------------------------------------------
local function payReward(player: Player, cash: number, label: string, pop: number?, extraStats: { [string]: number }?)
	task.defer(function()
		if player.Parent ~= Players or not Profiles.get(player) then
			return
		end
		if cash > 0 then
			ctx.ledger(player, "bank", math.floor(cash), label, true)
		end
		local stats: { [string]: number } = {}
		if pop and pop > 0 then
			stats.popularity = pop
		end
		if extraStats then
			for k, v in extraStats do
				stats[k] = (stats[k] or 0) + v
			end
		end
		if next(stats) then
			ctx.addStats(player, stats, nil, true)
		end
	end)
end

local evaluate: (Player, Sess, boolean?) -> ()
local checkLevel: (Player, Sess) -> ()

-------------------------------------------------------------------------------------------------
-- Goals
-------------------------------------------------------------------------------------------------
local function completeGoal(player: Player, s: Sess, g: any, weekly: boolean)
	local pr = s.pr
	g.done = true
	g.have = g.n
	local def = if weekly then P.WEEKLY_BY_ID[g.id] else P.GOAL_BY_ID[g.id]
	if not def then
		return
	end
	local cash = P.goalCash(def, pr.level, weekly)
	local pop = def.pop or 0
	local view = P.goalView(g, weekly, pr.level, true)
	local allDone = false
	if weekly then
		pr.weeklyDone += 1
		payReward(player, cash, "주간 목표 보상 · " .. view.text, pop)
	else
		pr.goalsDone += 1
		payReward(player, cash, "일일 목표 보상 · " .. view.text, pop)
		allDone = #pr.daily.goals >= P.DAILY_COUNT
		for _, x in pr.daily.goals do
			if not x.done then
				allDone = false
			end
		end
	end
	local bonus = nil
	if allDone and not pr.daily.allDone then
		pr.daily.allDone = true
		local mult = P.BAND_CASH[P.band(pr.level)] or 1
		bonus = math.floor(P.ALL_DONE.cash * mult / 100 + 0.5) * 100
		payReward(player, bonus, "일일 목표 올클리어 보너스", P.ALL_DONE.pop, { happiness = P.ALL_DONE.happiness })
	end
	fire(player, { k = "goal", goal = view, cash = cash, pop = pop, allDone = allDone, bonus = bonus })
	s.dirty = true
	s.updDirty = true
	s.achDirty = true
	applyAttributes(player, s)
	if not weekly then
		-- counts toward the weekly "일일 목표 n개" goal
		task.defer(function()
			if sessions[player] == s then
				Progress.track(player, "goal_done", 1, "internal")
			end
		end)
	end
end

local function bumpGoals(player: Player, s: Sess, key: string, n: number)
	local pr = s.pr
	for _, g in pr.daily.goals do
		local def = P.GOAL_BY_ID[g.id]
		if def and def.key == key and not g.done then
			g.have = math.min(g.n, g.have + n)
			s.updDirty = true
			if g.have >= g.n then
				completeGoal(player, s, g, false)
			end
		end
	end
	local w = pr.weekly.goal
	if w then
		local def = P.WEEKLY_BY_ID[w.id]
		if def and def.key == key and not w.done then
			w.have = math.min(w.n, w.have + n)
			s.updDirty = true
			if w.have >= w.n then
				completeGoal(player, s, w, true)
			end
		end
	end
end

local function owns(s: Sess): { [string]: boolean }
	return { car = carsOwned(s.d) > 0 or s.pr.ms.first_car ~= nil, home = s.d.home ~= nil }
end

local function ensureGoals(player: Player, s: Sess, silent: boolean?)
	local pr = s.pr
	local t = now()
	local day = P.kstDay(t)
	local changed = false
	if pr.daily.day ~= day or #pr.daily.goals == 0 then
		pr.daily = {
			day = day,
			goals = P.rollDaily(player.UserId * 7 + day * 131, pr.level, function(k)
				return isLive(s, k)
			end, owns(s)),
			rerolls = 0,
			allDone = false,
		}
		changed = true
	end
	local week = P.kstWeek(t)
	if pr.weekly.week ~= week or not pr.weekly.goal then
		pr.weekly = { week = week, goal = P.rollWeekly(player.UserId * 3 + week * 17, pr.level) }
		changed = true
	end
	if changed then
		s.dirty = true
		s.updDirty = true
		applyAttributes(player, s)
		if not silent then
			fire(player, { k = "newday" })
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Track (the hook entry point)
-------------------------------------------------------------------------------------------------
function Progress.track(player: any, key: any, n: any, source: string?): boolean
	local p = playerOf(player)
	if not p or type(key) ~= "string" or #key > 32 then
		return false
	end
	local amount = if type(n) == "number" and n == n then n else 1
	if amount <= 0 then
		return false
	end
	amount = math.min(math.floor(amount * 100 + 0.5) / 100, TRACK_MAX)
	if source == nil then
		hookKeys[key] = true
	end
	if source ~= "sniff" and source ~= "auto" then
		serverSeen[key] = true
	end
	local s = sessions[p]
	if not s then
		return false
	end
	if not s.ready then
		table.insert(s.preq, { "track", key, amount, source })
		return true
	end
	local pr = s.pr
	pr.c[key] = math.min((pr.c[key] or 0) + amount, P.MAX_COUNTER)
	s.dirty = true
	s.achDirty = true
	bumpGoals(p, s, key, amount)
	return true
end

-------------------------------------------------------------------------------------------------
-- Money pops (coalesced per player)
-------------------------------------------------------------------------------------------------
local function flushPop(player: Player, group: string)
	local s = sessions[player]
	if not s then
		return
	end
	local q = s.pops[group]
	s.pops[group] = nil
	if not q then
		return
	end
	local big = if q.max >= P.POP.jackpot then 2 elseif q.max >= P.POP.big then 1 else 0
	local today = s.pr.days[#s.pr.days]
	fire(player, { k = "pop", amt = q.amt, cat = q.cat, label = q.label, big = big, acct = q.acct, n = q.n, today = today and today.e or 0, count = q.count })
end

local function queuePop(player: Player, s: Sess, group: string, amount: number, cat: string, label: string, account: string, counts: boolean)
	if amount < P.POP.min then
		return
	end
	local q = s.pops[group]
	if q then
		q.amt += amount
		q.n += 1
		if amount > q.max then
			q.max = amount
			q.cat = cat
			q.label = label
			q.acct = account
		end
		return
	end
	s.pops[group] = { amt = amount, n = 1, max = amount, cat = cat, label = label, acct = account, count = counts }
	task.delay(P.POP.coalesce, flushPop, player, group)
end

-------------------------------------------------------------------------------------------------
-- Milestones
-------------------------------------------------------------------------------------------------
local function celebrate(player: Player, s: Sess, id: string, name: string?, silent: boolean?)
	local pr = s.pr
	local def = P.MILESTONES[id]
	if not def or pr.ms[id] then
		return
	end
	pr.ms[id] = now()
	s.dirty = true
	s.achDirty = true
	if silent then
		return
	end
	local body = def.body
	if string.find(body, "%%s") then
		body = string.format(body, name or "")
	end
	fire(player, { k = "ms", id = id, title = def.title, body = body, icon = def.icon, camera = def.camera == true })
	if def.friend and def.msg and type(ctx.sendMessage) == "function" then
		task.delay(4.5, function()
			if player.Parent == Players then
				pcall(ctx.sendMessage, player, def.friend, def.msg)
			end
		end)
	end
end

local function homeName(d: any): string?
	local l = d.home and G.LISTINGS and G.LISTINGS[d.home.listingId]
	return l and l.name or nil
end

local function carName(d: any): string?
	if type(d.cars) ~= "table" then
		return nil
	end
	local last: any = nil
	for _, c in d.cars do
		if type(c) == "table" and not c.rental and not c.test then
			if not last or (tonumber(c.t) or 0) >= (tonumber(last.t) or 0) then
				last = c
			end
		end
	end
	if not last then
		return nil
	end
	local okGS, GS = pcall(function()
		local m = ReplicatedStorage:FindFirstChild("GwangalliGarageShared")
		return if m and m:IsA("ModuleScript") then require(m) :: any else nil
	end)
	local info = okGS and GS and GS.CATALOG and GS.CATALOG[last.kind]
	return info and (info.full or info.label) or "내 차"
end

local function checkAssets(player: Player, s: Sess, silent: boolean?)
	local d, pr = s.d, s.pr
	-- home
	local tier = if d.home then (tonumber(d.home.tier) or 0) else 0
	if tier > 0 then
		if not pr.ms.first_home then
			celebrate(player, s, "first_home", homeName(d), silent)
		end
		if d.home.owned and not pr.ms.own_home then
			celebrate(player, s, "own_home", homeName(d), silent)
		end
		if tier >= 5 and not pr.ms.penthouse then
			celebrate(player, s, "penthouse", homeName(d), silent)
		end
	end
	if tier ~= pr.seen.tier then
		pr.seen.tier = tier
		s.dirty = true
		s.achDirty = true
	end
	-- cars
	local cars = carsOwned(d)
	if cars > pr.seen.cars then
		if not pr.ms.first_car then
			celebrate(player, s, "first_car", carName(d), silent)
		end
		if not silent then
			Progress.track(player, "car_buy", cars - pr.seen.cars, "auto")
		end
	end
	if cars ~= pr.seen.cars then
		pr.seen.cars = cars
		s.dirty = true
		s.achDirty = true
	end
end

-------------------------------------------------------------------------------------------------
-- Level
-------------------------------------------------------------------------------------------------
checkLevel = function(player: Player, s: Sess)
	local pr = s.pr
	local lv = P.levelFor(pr.earned)
	if lv <= pr.level then
		return
	end
	local from = pr.level
	pr.level = lv
	s.dirty = true
	s.achDirty = true
	s.updDirty = true
	local unlocks = {}
	for l = from + 1, lv do
		for _, u in P.unlocksAt(l) do
			table.insert(unlocks, { id = u.id, name = u.name, desc = u.desc, icon = u.icon, level = u.level })
		end
	end
	applyAttributes(player, s)
	fire(player, { k = "level", level = lv, from = from, title = P.titleFor(lv), unlocks = unlocks })
	for l = from + 1, lv do
		local t = P.LEVEL_TEXTS[l]
		if t and type(ctx.sendMessage) == "function" then
			task.delay(6, function()
				if player.Parent == Players then
					pcall(ctx.sendMessage, player, t[1], t[2])
				end
			end)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Achievements
-------------------------------------------------------------------------------------------------
evaluate = function(player: Player, s: Sess, silent: boolean?)
	s.achDirty = false
	local pr = s.pr
	for _, a in P.ACHIEVEMENTS do
		if not pr.ach[a.id] then
			local v = metric(player, s, a.metric)
			if v >= a.n then
				pr.ach[a.id] = now()
				s.dirty = true
				s.updDirty = true
				if not silent then
					local tier = P.TIERS[a.tier]
					payReward(player, tier.cash, "업적 보상 · " .. a.name, tier.pop)
					fire(player, { k = "ach", id = a.id, name = a.name, desc = a.desc, icon = a.icon, tier = a.tier, cash = tier.cash, pop = tier.pop })
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- The ledger hook
-------------------------------------------------------------------------------------------------
local function onLedger(player: Player, account: string, amount: number, label: string?, meta: any)
	local s = sessions[player]
	if not s then
		return
	end
	if not s.ready then
		if #s.preq < 200 then
			table.insert(s.preq, { "ledger", account, amount, label, meta })
		end
		return
	end
	local pr = s.pr
	local cat, group = P.classify(amount, account, label, meta)
	local lbl = if type(label) == "string" then label else ""
	if group == "skip" then
		if amount > 0 and cat ~= "internal" then
			queuePop(player, s, "other", amount, cat, lbl, account, false)
		end
		return
	end
	local amt = math.abs(amount)
	local rec = dayRecord(s)
	if group == "earn" then
		pr.earned = math.min(pr.earned + amt, P.MAX_COUNTER)
		rec.e += amt
		rec.ecats[cat] = (rec.ecats[cat] or 0) + amt
		if amt > rec.best then
			rec.best = amt
		end
		if amt > pr.best.pay then
			pr.best.pay = amt
		end
		if rec.e > pr.best.day then
			pr.best.day = rec.e
		end
		queuePop(player, s, "earn", amt, cat, lbl, account, true)
		if cat == "wage" and not pr.ms.first_pay then
			celebrate(player, s, "first_pay", nil, false)
		end
		checkLevel(player, s)
	else
		pr.spent = math.min(pr.spent + amt, P.MAX_COUNTER)
		rec.s += amt
		rec.cats[cat] = (rec.cats[cat] or 0) + amt
		-- a purchase may have been a car / home: look shortly after (the owner writes d.cars / d.home
		-- right after the payment)
		task.delay(0.6, function()
			local s2 = sessions[player]
			if s2 == s and s.ready then
				checkAssets(player, s, false)
			end
		end)
	end
	for _, kv in P.ledgerKeys(amount, cat, group, lbl, foodNames) do
		Progress.track(player, kv[1], kv[2], "auto")
	end
	if group == "spend" and lbl ~= "" and string.find(lbl, "VIP", 1, true) and string.find(lbl, "테이블", 1, true) then
		celebrate(player, s, "first_vip", nil, false)
	end
	s.dirty = true
	s.updDirty = true
	s.achDirty = true
end

local function wrapLedger()
	if wrapped then
		return
	end
	wrapped = true
	local orig = G.ledger
	G.ledger = function(d: any, account: string, delta: any, label: string?, t: number?, meta: any?): (boolean, string?)
		local ok, why = orig(d, account, delta, label, t, meta)
		if ok then
			local player = byData[d]
			if player and type(delta) == "number" and delta == delta and delta ~= 0 then
				local amount = if delta >= 0 then math.floor(delta) else -math.floor(-delta)
				if amount ~= 0 then
					local okH, err = pcall(onLedger, player, account, amount, label, meta)
					if not okH then
						Util.warnOnce("progressLedger", "[GwangalliProgress] ledger hook failed: " .. tostring(err))
					end
				end
			end
		end
		return ok, why
	end
end

-- Fallback detection from notification titles (jobs): steps aside per key once a real hook reports it.
local SNIFF = {
	{ prefix = "배달 완료", key = "delivery" },
	{ prefix = "승진!", key = "promotion" },
	{ prefix = "합격!", key = "hired" },
}
local function wrapNotify()
	local orig = ctx.notify
	if type(orig) ~= "function" then
		return
	end
	ctx.notify = function(player: Player, kind: string, title: string, body: string?, extra: any?)
		orig(player, kind, title, body, extra)
		if kind == "job" and type(title) == "string" and sessions[player] then
			for _, sn in SNIFF do
				if not hookKeys[sn.key] and string.sub(title, 1, #sn.prefix) == sn.prefix then
					pcall(Progress.track, player, sn.key, 1, "sniff")
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Snapshot
-------------------------------------------------------------------------------------------------
function Progress.snapshot(player: Player): any?
	local s = sess(player)
	if not s then
		return nil
	end
	local pr = s.pr
	local lv, lp, at, nxt = P.levelFor(pr.earned)
	local goals, weekly = goalsView(s)
	local achs = {}
	local achDone = 0
	for _, a in P.ACHIEVEMENTS do
		local v = metric(player, s, a.metric)
		local done = pr.ach[a.id] ~= nil
		if done then
			achDone += 1
		end
		table.insert(achs, {
			id = a.id,
			name = a.name,
			desc = a.desc,
			icon = a.icon,
			tier = a.tier,
			cat = a.cat,
			n = a.n,
			have = math.min(v, a.n),
			done = done,
			t = pr.ach[a.id],
			live = a.key == nil or isLive(s, a.key),
		})
	end
	local unlocks = {}
	for _, u in P.UNLOCKS do
		table.insert(unlocks, { level = u.level, id = u.id, name = u.name, desc = u.desc, icon = u.icon, have = lv >= u.level, owner = u.owner })
	end
	local maxRe = P.perk(lv, "goal_reroll") or 0
	local today = P.dayView(dayRecord(s))
	return {
		level = lv,
		title = P.titleFor(lv),
		lp = lp,
		earned = pr.earned,
		levelAt = at,
		nextAt = nxt,
		goals = goals,
		weekly = weekly,
		allDone = pr.daily.allDone,
		rerolls = { used = pr.daily.rerolls, max = maxRe },
		achievements = achs,
		unlocks = unlocks,
		history = history(pr),
		today = today,
		lifeDay = s.d.lifeDay or 1,
		stats = { goalsDone = pr.goalsDone, weeklyDone = pr.weeklyDone, bestPay = pr.best.pay, bestDay = pr.best.day, achDone = achDone, achTotal = #P.ACHIEVEMENTS, spent = pr.spent },
	}
end

local function pushUpd(player: Player, s: Sess)
	s.updDirty = false
	local goals, weekly = goalsView(s)
	local lv, lp = P.levelFor(s.pr.earned)
	fire(player, { k = "upd", goals = goals, weekly = weekly, level = lv, lp = lp, earned = s.pr.earned, allDone = s.pr.daily.allDone })
end

-------------------------------------------------------------------------------------------------
-- Reroll (Lv2 perk)
-------------------------------------------------------------------------------------------------
local function reroll(player: Player, s: Sess, index: any): any
	local pr = s.pr
	local i = if type(index) == "number" then math.floor(index) else 0
	local g = pr.daily.goals[i]
	if not g then
		return { ok = false, message = "바꿀 목표를 골라 주세요" }
	end
	if g.done then
		return { ok = false, message = "이미 달성한 목표예요" }
	end
	local max = P.perk(pr.level, "goal_reroll") or 0
	if max <= 0 then
		return { ok = false, message = "인생 레벨 2부터 목표를 바꿀 수 있어요" }
	end
	if pr.daily.rerolls >= max then
		return { ok = false, message = "오늘은 더 바꿀 수 없어요" }
	end
	local def = P.GOAL_BY_ID[g.id]
	local used: { [string]: boolean } = {}
	for _, x in pr.daily.goals do
		local dx = P.GOAL_BY_ID[x.id]
		if dx then
			used[x.id] = true
			used["key:" .. dx.key] = true
		end
	end
	local o = owns(s)
	local candidates = {}
	for _, cand in P.GOALS do
		if not used[cand.id] and not used["key:" .. cand.key] and isLive(s, cand.key) and (not cand.needs or o[cand.needs]) and (not cand.minLevel or pr.level >= cand.minLevel) then
			if def and cand.group == def.group then
				table.insert(candidates, cand)
			end
		end
	end
	if #candidates == 0 then
		for _, cand in P.GOALS do
			if not used[cand.id] and not used["key:" .. cand.key] and isLive(s, cand.key) and (not cand.needs or o[cand.needs]) and (not cand.minLevel or pr.level >= cand.minLevel) then
				table.insert(candidates, cand)
			end
		end
	end
	if #candidates == 0 then
		return { ok = false, message = "지금은 바꿀 수 있는 목표가 없어요" }
	end
	local rand = P.rng(player.UserId * 11 + pr.daily.day * 37 + pr.daily.rerolls * 101 + i)
	local pick = candidates[rand(#candidates)]
	local band = P.band(pr.level)
	pr.daily.goals[i] = { id = pick.id, n = pick.n[band] or pick.n[#pick.n], have = 0, done = false }
	pr.daily.rerolls += 1
	s.dirty = true
	applyAttributes(player, s)
	local goals, weekly = goalsView(s)
	return { ok = true, goals = goals, weekly = weekly, rerolls = { used = pr.daily.rerolls, max = max } }
end

-------------------------------------------------------------------------------------------------
-- Persistence (fallback store)
-------------------------------------------------------------------------------------------------
local function waitBudget(kind: Enum.DataStoreRequestType)
	for _ = 1, 20 do
		local ok, budget = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, kind)
		if not ok or budget > 0 then
			return
		end
		task.wait(0.5)
	end
end

local function keyOf(player: Player): string
	return P.KEY_PREFIX .. tostring(player.UserId)
end

local function loadSide(player: Player): any?
	if not storeEnabled or not store then
		return nil
	end
	for attempt = 1, 3 do
		waitBudget(Enum.DataStoreRequestType.GetAsync)
		local ok, res = pcall(function()
			return store:GetAsync(keyOf(player))
		end)
		if ok then
			return if type(res) == "table" then res else nil
		end
		warn(string.format("[GwangalliProgress] load %s failed (try %d): %s", player.Name, attempt, tostring(res)))
		task.wait(attempt * 2)
	end
	return nil
end

local function saveSide(player: Player, s: Sess)
	if not storeEnabled or not store or profileHolds then
		s.dirty = false
		return
	end
	if not s.ready then
		return
	end
	s.dirty = false
	s.lastSave = os.clock()
	local snapshot = Util.deepCopy(s.pr)
	snapshot.t = now()
	waitBudget(Enum.DataStoreRequestType.UpdateAsync)
	local ok, err = pcall(function()
		store:UpdateAsync(keyOf(player), function(old: any)
			return P.merge(old, snapshot)
		end)
	end)
	if not ok then
		s.dirty = true
		warn("[GwangalliProgress] save " .. player.Name .. " failed: " .. tostring(err))
	end
end

-------------------------------------------------------------------------------------------------
-- Seeding (players who played before this system existed): progress from what the profile already
-- shows, unlocked silently (no rewards, no celebrations).
-------------------------------------------------------------------------------------------------
local function seed(player: Player, s: Sess, queuedEarn: number)
	local pr, d = s.pr, s.d
	if pr.seeded then
		return
	end
	pr.seeded = true
	local start = (tonumber(G.START_CASH) or 0) + (tonumber(G.START_BANK) or 0)
	local okN, net = pcall(G.netWorth, d)
	if okN and type(net) == "number" then
		-- queued earnings are replayed right after this (not counted twice)
		pr.earned = math.max(pr.earned, math.floor(net - start - queuedEarn))
	end
	local shifts = tonumber(d.shifts) or 0
	if shifts > 0 then
		pr.c.shift = math.max(pr.c.shift or 0, shifts)
		pr.c.payday = math.max(pr.c.payday or 0, 1)
		pr.ms.first_pay = pr.ms.first_pay or now()
	end
	pr.level = (P.levelFor(pr.earned))
	pr.seen.lifeDay = math.max(pr.seen.lifeDay, tonumber(d.lifeDay) or 1)
	checkAssets(player, s, true)
	evaluate(player, s, true)
	s.dirty = true
end

-------------------------------------------------------------------------------------------------
-- Player lifecycle
-------------------------------------------------------------------------------------------------
local function attrHooks(player: Player, s: Sess)
	local function on(name: string, fn: () -> ())
		table.insert(s.conns, player:GetAttributeChangedSignal(name):Connect(function()
			if sessions[player] ~= s or not s.ready then
				return
			end
			local ok, err = pcall(fn)
			if not ok then
				Util.warnOnce("progressAttr" .. name, "[GwangalliProgress] " .. name .. ": " .. tostring(err))
			end
		end))
	end
	on("ClubOceanWristband", function()
		if player:GetAttribute("ClubOceanWristband") then
			local day = tonumber(s.d.lifeDay) or 0
			if s.clubDay ~= day then
				s.clubDay = day
				Progress.track(player, "club_enter", 1, "auto")
			end
		end
	end)
	on("ClubVIPTable", function()
		if player:GetAttribute("ClubVIPTable") == true then
			celebrate(player, s, "first_vip", nil, false)
		end
	end)
	on(G.Attr.LastBowlingScore or "LastBowlingScore", function()
		local score = tonumber(player:GetAttribute(G.Attr.LastBowlingScore or "LastBowlingScore")) or 0
		if Util.cooldown(player, "prog:bowl", 20) then
			Progress.track(player, "bowl_game", 1, "auto")
		end
		if score >= 200 then
			Progress.track(player, "bowl_200", 1, "auto")
		end
	end)
	on(G.Attr.GymBusy or "GymBusy", function()
		if not player:GetAttribute(G.Attr.GymBusy or "GymBusy") then
			local sets = if type(s.d.gym) == "table" then (tonumber(s.d.gym.sets) or 0) else 0
			if sets > s.lastGymSets then
				local diff = math.min(sets - s.lastGymSets, 5)
				s.lastGymSets = sets
				Progress.track(player, "gym_set", diff, "auto")
			end
		end
	end)
	on(G.Attr.HomeTier or "HomeTier", function()
		task.delay(0.3, function()
			if sessions[player] == s then
				checkAssets(player, s, false)
			end
		end)
	end)
	for _, a in { G.Attr.Appearance, G.Attr.Strength, G.Attr.Popularity } do
		if type(a) == "string" then
			on(a, function()
				s.achDirty = true
			end)
		end
	end
end

function Progress.onLoaded(player: Player)
	if not started then
		return
	end
	local d = Profiles.get(player)
	if not d or sessions[player] then
		return
	end
	local fromProfile = type(d.progress) == "table"
	local pr = P.sanitize(d.progress, now())
	d.progress = pr
	byData[d] = player
	local s: Sess = {
		pr = pr,
		d = d,
		ready = false,
		dirty = false,
		lastSave = os.clock(),
		pops = {},
		updDirty = false,
		achDirty = true,
		driveT = 0,
		lastGymSets = if type(d.gym) == "table" then (tonumber(d.gym.sets) or 0) else 0,
		friends = 0,
		friendsAt = -math.huge,
		clubDay = -1,
		tick = 0,
		conns = {},
		paydayQueued = false,
		preq = {},
		rewardsAt = {},
	}
	sessions[player] = s
	attrHooks(player, s)
	task.spawn(function()
		-- the fallback copy (until Profiles keeps d.progress; read once after the switch to migrate)
		if storeEnabled and (not profileHolds or not fromProfile) then
			local side = loadSide(player)
			if sessions[player] ~= s then
				return
			end
			if side then
				local merged = P.merge(side, s.pr)
				-- keep the same table identity for d.progress (other code holds s.pr)
				for k in s.pr do
					s.pr[k] = nil
				end
				for k, v in merged do
					s.pr[k] = v
				end
			end
		end
		s.ready = true
		local queued = s.preq
		s.preq = {}
		local queuedEarn = 0
		for _, e in queued do
			if e[1] == "ledger" and e[3] > 0 then
				local _, grp = P.classify(e[3], e[2], e[4], e[5])
				if grp == "earn" then
					queuedEarn += e[3]
				end
			end
		end
		seed(player, s, queuedEarn)
		for _, e in queued do
			if e[1] == "ledger" then
				pcall(onLedger, player, e[2], e[3], e[4], e[5])
			else
				pcall(Progress.track, player, e[2], e[3], e[4])
			end
		end
		if pr.seen.lifeDay <= 0 then
			pr.seen.lifeDay = tonumber(d.lifeDay) or 1
		end
		ensureGoals(player, s, true)
		applyAttributes(player, s)
		checkAssets(player, s, false)
		evaluate(player, s, false)
		pushUpd(player, s)
	end)
end

function Progress.onLeave(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	for _, c in s.conns do
		c:Disconnect()
	end
	table.clear(s.conns)
	sessions[player] = nil
	byData[s.d] = nil
	if s.ready and storeEnabled and not profileHolds then
		task.spawn(saveSide, player, s)
	end
end

function Progress.onCharacter(_player: Player, _character: Model) end

-------------------------------------------------------------------------------------------------
-- Driver loop (1 Hz, all players)
-------------------------------------------------------------------------------------------------
local function rollDay(player: Player, s: Sess)
	local pr = s.pr
	local newDay = tonumber(s.d.lifeDay) or 1
	local prevDay = pr.seen.lifeDay
	pr.seen.lifeDay = newDay
	s.dirty = true
	local rec: any = nil
	for _, x in pr.days do
		if x.d == prevDay then
			rec = x
		end
	end
	if not rec or (rec.e <= 0 and rec.s <= 0) then
		return
	end
	if rec.e > pr.best.day then
		pr.best.day = rec.e
	end
	fire(player, { k = "payday", scope = "day", day = P.dayView(rec), history = history(pr) })
end

local function step(player: Player, s: Sess)
	s.tick += 1
	local d = s.d
	-- driving minutes (driver's seat of a car; taxi passengers excluded)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat and seat:IsA("VehicleSeat") and not player:GetAttribute(G.Attr.InTaxi or "InTaxi") then
		s.driveT += 1
		if s.driveT >= 60 then
			s.driveT -= 60
			Progress.track(player, "drive_min", 1, "auto")
		end
	end
	-- the player's own day (rent clock) rolled over -> payday card
	if (tonumber(d.lifeDay) or 1) ~= s.pr.seen.lifeDay then
		rollDay(player, s)
	end
	if s.tick % 5 == 0 then
		ensureGoals(player, s, false)
		checkAssets(player, s, false)
	end
	if s.achDirty and s.tick % 2 == 0 then
		evaluate(player, s, false)
	end
	if s.updDirty then
		pushUpd(player, s)
	end
	if s.dirty and storeEnabled and not profileHolds and os.clock() - s.lastSave > AUTOSAVE then
		task.spawn(saveSide, player, s)
	end
end

-------------------------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------------------------
local function requireShared(): any
	local m = ReplicatedStorage:FindFirstChild("GwangalliProgressShared")
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	return if ok and type(res) == "table" then res else nil
end

local function makeRemotes()
	local rf = ReplicatedStorage:FindFirstChild(G.RemotesFolder)
	if not rf then
		rf = Instance.new("Folder")
		rf.Name = G.RemotesFolder
		rf.Parent = ReplicatedStorage
	end
	local function remote(name: string, className: string): any
		local r = rf:FindFirstChild(name)
		if r and r.ClassName ~= className then
			r:Destroy()
			r = nil
		end
		if not r then
			r = Instance.new(className)
			r.Name = name
			r.Parent = rf
		end
		return r
	end
	remotes.event = remote(P.Remotes.Event, "RemoteEvent")
	remotes.request = remote(P.Remotes.Request, "RemoteFunction")
	;(remotes.request :: RemoteFunction).OnServerInvoke = function(player: Player, op: any, payload: any)
		if type(op) ~= "string" or not Util.cooldown(player, "prog:" .. op, 0.25) then
			return nil
		end
		local t0 = os.clock()
		while player.Parent == Players and not sess(player) and os.clock() - t0 < 10 do
			task.wait(0.25)
		end
		local s = sess(player)
		if not s then
			return nil
		end
		if op == "snapshot" then
			local ok, snap = pcall(Progress.snapshot, player)
			return if ok then snap else nil
		elseif op == "reroll" then
			local idx = if type(payload) == "table" then payload.index else nil
			local ok, res = pcall(reroll, player, s, idx)
			return if ok then res else { ok = false, message = "잠시 후 다시 해 주세요" }
		elseif op == "payday" then
			return { day = P.dayView(dayRecord(s)), history = history(s.pr) }
		end
		return nil
	end
end

local function api(): any
	return {
		track = function(player: any, key: any, n: any): boolean
			return Progress.track(player, key, n)
		end,
		perk = function(player: any, id: any): any
			local p = playerOf(player)
			local s = p and sessions[p]
			if not s or type(id) ~= "string" then
				return false
			end
			return P.perk(s.pr.level, id)
		end,
		level = function(player: any): (number, number)
			local p = playerOf(player)
			local s = p and sessions[p]
			if not s then
				return 1, 0
			end
			return s.pr.level, s.pr.earned
		end,
		reward = function(player: any, amount: any, label: any): boolean
			local p = playerOf(player)
			if not p or type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount > 5000000 then
				return false
			end
			local s = sessions[p]
			if not s then
				return false
			end
			-- at most 30 rewards a minute per player (a runaway caller cannot print money)
			local t = os.clock()
			while #s.rewardsAt > 0 and t - s.rewardsAt[1] > 60 do
				table.remove(s.rewardsAt, 1)
			end
			if #s.rewardsAt >= 30 then
				return false
			end
			table.insert(s.rewardsAt, t)
			local text = if type(label) == "string" and #label > 0 then string.sub(label, 1, 80) else "보상"
			return ctx.ledger(p, "bank", math.floor(amount), text, true) == true
		end,
		celebrate = function(player: any, id: any, name: any): boolean
			local p = playerOf(player)
			local s = p and sess(p)
			if not s or type(id) ~= "string" or not P.MILESTONES[id] then
				return false
			end
			celebrate(p :: Player, s, id, if type(name) == "string" then name else nil, false)
			return true
		end,
		snapshot = function(player: any): any
			local p = playerOf(player)
			return p and Progress.snapshot(p) or nil
		end,
	}
end

local function makeApi(a: any)
	local bf = ServerStorage:FindFirstChild(P.API)
	if bf and not bf:IsA("BindableFunction") then
		bf:Destroy()
		bf = nil
	end
	if not bf then
		bf = Instance.new("BindableFunction")
		bf.Name = P.API
		bf.Parent = ServerStorage
	end
	(bf :: BindableFunction).OnInvoke = function(op: any, player: any, ...: any)
		local fn = a[op]
		if type(fn) ~= "function" then
			return nil
		end
		local res = table.pack(pcall(fn, player, ...))
		if not res[1] then
			warn("[GwangalliProgress] API " .. tostring(op) .. " failed: " .. tostring(res[2]))
			return nil
		end
		return table.unpack(res, 2, res.n)
	end
end

function Progress.init(context: any)
	if started then
		return
	end
	ctx = context
	G = context.G
	Profiles = context.Profiles
	Util = context.Util
	P = requireShared()
	if not P or not G or not Profiles or not Util then
		warn("[GwangalliProgress] shared modules missing; progression disabled")
		return
	end
	for _, p in P.validate() do
		warn("[GwangalliProgress] data: " .. p)
	end
	started = true
	Progress._ctx = context
	Progress._P = P

	-- food names (eat goal): consumable items that restore 체력 + the home delivery menu
	for _, it in G.ITEMS or {} do
		if type(it) == "table" and it.kind == "consumable" and type(it.name) == "string" then
			local st = it.effect and it.effect.stats
			if type(st) == "table" and (st.stamina or 0) > 0 then
				foodNames[it.name] = true
			end
		end
	end
	local hf = G.HOME_FOOD
	if type(hf) == "table" and type(hf.delivery) == "table" then
		for _, m in hf.delivery do
			if type(m) == "table" and type(m.name) == "string" then
				foodNames[m.name] = true
			end
		end
	end

	-- does Profiles keep d.progress itself?
	local okProbe, probe = pcall(Profiles.sanitize, { v = G.VERSION, progress = { v = P.VERSION, earned = 1 } })
	profileHolds = okProbe and type(probe) == "table" and type(probe.progress) == "table"
	local okEnabled, en = pcall(Profiles.enabled)
	if game.PlaceId ~= 0 and okEnabled and en then
		local ok, res = pcall(DataStoreService.GetDataStore, DataStoreService, P.DATASTORE)
		if ok and res then
			store = res
			storeEnabled = true
		end
	end

	wrapLedger()
	wrapNotify()
	makeRemotes()
	local a = api()
	ctx.progress = a
	makeApi(a)

	task.spawn(function()
		while true do
			task.wait(1)
			for player, s in sessions do
				if s.ready and player.Parent == Players then
					local ok, err = pcall(step, player, s)
					if not ok then
						Util.warnOnce("progressStep", "[GwangalliProgress] step failed: " .. tostring(err))
					end
				end
			end
		end
	end)
	game:BindToClose(function()
		if not storeEnabled or profileHolds then
			return
		end
		local pending = 0
		for player, s in sessions do
			if s.ready then
				pending += 1
				task.spawn(function()
					pcall(saveSide, player, s)
					pending -= 1
				end)
			end
		end
		local t0 = os.clock()
		local limit = if RunService:IsStudio() then 5 else 20
		while pending > 0 and os.clock() - t0 < limit do
			task.wait(0.1)
		end
	end)
	-- players whose profile loaded before this module started (the bootstrap calls onLoaded later
	-- for everyone else)
	for _, player in Players:GetPlayers() do
		if Profiles.get(player) then
			task.spawn(Progress.onLoaded, player)
		end
	end
	print(string.format("[GwangalliProgress] ready: %d achievements, %d goals, persistence = %s", #P.ACHIEVEMENTS, #P.GOALS, if profileHolds then "profile" elseif storeEnabled then P.DATASTORE else "memory"))
end

return Progress
