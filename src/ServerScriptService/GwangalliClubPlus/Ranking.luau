-- GwangalliClubPlus.Ranking: the side LED boards' data (server).
--   spend   오늘의 큰손 TOP 5  (orders tonight; ClubRanking's own Top is reused when it runs, so the
--           numbers match its board; otherwise ODS "GwClubPlus_Spend_<night>")
--   donate  후원 랭킹 TOP 5   (ODS "GwClubPlus_Donate_<night>")
--   best    최고가 주문 TOP 5  (single orders tonight; DataStore "GwClubPlus_Best_v1" key "n<night>")
--   weekly  이번 주 랭킹 TOP 5 (orders + 후원 this week; ODS "GwClubPlus_Week_<week>")
-- Nights run 06:00 KST -> 06:00 KST, weeks start Monday 06:00 KST (Shared.nightOf / weekOf).
-- Pending deltas are flushed every Config.Ranking.FlushEvery s with UpdateAsync(old + delta) (retried;
-- failed deltas are kept), top lists are read every SyncEvery s. Studio without API access / DataStore
-- errors -> memory only (the boards still work for this server).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Ranking = {}

local C: any
local S: any
local R: any

type Cat = {
	prefix: string,
	period: number,
	known: { [number]: number }, -- last value read from / written to the store (current period)
	mine: { [number]: number }, -- this server's own contributions (current period)
	pending: { [number]: { [number]: number } }, -- period -> uid -> delta not saved yet
	top: { number }, -- uids in the store's top list (current period)
}

local cats: { [string]: Cat } = {}
local names: { [number]: string } = {}
local best: { any } = {} -- { u, n, v, x, at } tonight (merged with the store)
local bestDirty = false
local bestNight = 0
local storeOff = false
local lastFlush, lastSync = 0, 0
local boardsDirty = true
local lastBoards = 0
local flushing = false

local function newCat(prefix: string, period: number): Cat
	return { prefix = prefix, period = period, known = {}, mine = {}, pending = {}, top = {} }
end

local function denied(err: any): boolean
	local s = tostring(err)
	return string.find(s, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(s, "403", 1, true) ~= nil
		or string.find(s, "not allowed", 1, true) ~= nil
		or string.find(s, "Place has to be opened", 1, true) ~= nil
end

-- pcall with retries; turns the store off for good when the place has no DataStore access
local function try(fn: () -> any): (boolean, any)
	if storeOff then
		return false, nil
	end
	for i = 1, R.Retries do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		if denied(res) then
			storeOff = true
			warn("[GwangalliClubPlus] DataStores unavailable; rankings stay in memory:", res)
			return false, nil
		end
		if i < R.Retries then
			task.wait(i * 1.5)
		end
	end
	return false, nil
end

local odsCache: { [string]: any } = {}
local function ods(name: string): any?
	if storeOff then
		return nil
	end
	if odsCache[name] then
		return odsCache[name]
	end
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
	if not ok then
		if denied(store) then
			storeOff = true
		end
		return nil
	end
	odsCache[name] = store
	return store
end
local bestStore: any = nil
local function bestDS(): any?
	if storeOff then
		return nil
	end
	if bestStore then
		return bestStore
	end
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, "GwClubPlus_Best_v1")
	if not ok then
		if denied(store) then
			storeOff = true
		end
		return nil
	end
	bestStore = store
	return store
end

local function periodsNow(): (number, number)
	local night = S.nightOf(os.time())
	return night, S.weekOf(night)
end

local function value(cat: Cat, uid: number): number
	local p = cat.pending[cat.period]
	local est = (cat.known[uid] or 0) + (p and p[uid] or 0)
	return math.max(cat.mine[uid] or 0, est)
end

local function add(cat: Cat, uid: number, amount: number)
	cat.mine[uid] = (cat.mine[uid] or 0) + amount
	local p = cat.pending[cat.period]
	if not p then
		p = {}
		cat.pending[cat.period] = p
	end
	p[uid] = (p[uid] or 0) + amount
	boardsDirty = true
end

local function rows(cat: Cat): { any }
	local set: { [number]: boolean } = {}
	for _, u in cat.top do
		set[u] = true
	end
	for u in cat.mine do
		set[u] = true
	end
	local list = {}
	for u in set do
		local v = value(cat, u)
		if v > 0 then
			table.insert(list, { u = u, v = v })
		end
	end
	table.sort(list, function(a, b)
		if a.v == b.v then
			return a.u < b.u
		end
		return a.v > b.v
	end)
	local out = {}
	for i = 1, math.min(R.Top, #list) do
		local e = list[i]
		table.insert(out, { u = e.u, n = names[e.u] or C.cachedName(e.u) or "손님", v = e.v })
	end
	return out
end

local function spendRows(): ({ any }, string)
	local top = C.Bridge.rankingTop()
	if top then
		local out = {}
		for i, e in top.list do
			if i > R.Top then
				break
			end
			if type(e) == "table" and type(e.u) == "number" and type(e.t) == "number" then
				table.insert(out, { u = e.u, n = if type(e.n) == "string" then e.n else (names[e.u] or "손님"), v = e.t })
			end
		end
		return out, "ranking"
	end
	return rows(cats.spend), "plus"
end

local function setPlayerAttrs(uid: number)
	local p = Players:GetPlayerByUserId(uid)
	if p then
		p:SetAttribute(S.Attr.Tonight, value(cats.donate, uid))
		p:SetAttribute(S.Attr.Week, value(cats.weekly, uid))
	end
end

-- night / week rollover: the old period's pending deltas stay keyed to it and are flushed there
local function rollover()
	local night, week = periodsNow()
	for key, cat in cats do
		local want = if key == "weekly" then week else night
		if cat.period ~= want then
			cat.period = want
			cat.known = {}
			cat.mine = {}
			cat.top = {}
			boardsDirty = true
		end
	end
	if bestNight ~= night then
		if bestDirty then
			task.spawn(Ranking.flushBest, bestNight, table.clone(best))
		end
		bestNight = night
		best = {}
		bestDirty = false
		boardsDirty = true
	end
end

-------------------------------------------------------------------------------------------------
-- public
-------------------------------------------------------------------------------------------------
function Ranking.init(ctx: any)
	C = ctx
	S = ctx.S
	R = S.Config.Ranking
	local night, week = periodsNow()
	cats.spend = newCat("GwClubPlus_Spend_", night)
	cats.donate = newCat("GwClubPlus_Donate_", night)
	cats.weekly = newCat("GwClubPlus_Week_", week)
	bestNight = night
	C.Bridge.onRankingTop(function()
		boardsDirty = true
	end)
	Players.PlayerAdded:Connect(function(p)
		setPlayerAttrs(p.UserId)
	end)
	task.spawn(Ranking.sync)
end

function Ranking.addOrder(evt: any)
	rollover()
	local uid, price = evt.u, evt.price
	if type(uid) ~= "number" or type(price) ~= "number" or price <= 0 then
		return
	end
	names[uid] = evt.n
	if not C.Bridge.hasRanking() then
		add(cats.spend, uid, price)
	end
	add(cats.weekly, uid, price)
	table.insert(best, { u = uid, n = evt.n, v = price, x = evt.label, at = math.floor(evt.at) })
	table.sort(best, function(a, b)
		if a.v == b.v then
			return a.at < b.at
		end
		return a.v > b.v
	end)
	while #best > R.BestOrders do
		table.remove(best)
	end
	bestDirty = true
	setPlayerAttrs(uid)
end

function Ranking.addDonate(uid: number, name: string, amount: number)
	rollover()
	names[uid] = name
	add(cats.donate, uid, amount)
	add(cats.weekly, uid, amount)
	setPlayerAttrs(uid)
end

-- rank of `uid` among tonight's spenders: rank?, total, gap to #1
function Ranking.spendRank(uid: number): (number?, number, number)
	local list = spendRows()
	local first = list[1] and list[1].v or 0
	for i, e in list do
		if e.u == uid then
			return i, e.v, math.max(0, first - e.v)
		end
	end
	return nil, 0, first
end

function Ranking.donateRank(uid: number): number?
	for i, e in rows(cats.donate) do
		if e.u == uid then
			return i
		end
	end
	return nil
end

function Ranking.flushBest(night: number, list: { any })
	local ds = bestDS()
	if not ds then
		return
	end
	local ok = try(function()
		return ds:UpdateAsync("n" .. night, function(old: any)
			local merged: { any } = {}
			local seenKey: { [string]: boolean } = {}
			local function put(e: any)
				if type(e) == "table" and type(e.u) == "number" and type(e.v) == "number" then
					local k = e.u .. "@" .. tostring(e.at)
					if not seenKey[k] then
						seenKey[k] = true
						table.insert(merged, { u = e.u, n = tostring(e.n or "손님"):sub(1, 60), v = e.v, x = tostring(e.x or ""):sub(1, 80), at = tonumber(e.at) or 0 })
					end
				end
			end
			if type(old) == "table" then
				for _, e in old do
					put(e)
				end
			end
			for _, e in list do
				put(e)
			end
			table.sort(merged, function(a, b)
				if a.v == b.v then
					return a.at < b.at
				end
				return a.v > b.v
			end)
			while #merged > R.BestOrders do
				table.remove(merged)
			end
			return merged
		end)
	end)
	if ok and night == bestNight then
		bestDirty = false
	end
end

function Ranking.flush(final: boolean?)
	if flushing and not final then
		return
	end
	flushing = true
	for _, cat in cats do
		-- take the pending deltas out (new adds during the yields go to a fresh table)
		local work = cat.pending
		cat.pending = {}
		for period, p in work do
			local store = ods(cat.prefix .. period)
			for uid, delta in p do
				local ok, newValue = false, nil
				if store then
					ok, newValue = try(function()
						return store:UpdateAsync(tostring(uid), function(old: any)
							return math.floor((tonumber(old) or 0) + delta)
						end)
					end)
				end
				if ok and type(newValue) == "number" then
					if period == cat.period then
						cat.known[uid] = math.max(cat.known[uid] or 0, newValue)
					end
				elseif not storeOff then
					local q = cat.pending[period]
					if not q then
						q = {}
						cat.pending[period] = q
					end
					q[uid] = (q[uid] or 0) + delta
				end
			end
		end
	end
	if storeOff then
		-- memory only: pending is the same as `mine`
		for _, cat in cats do
			cat.pending = {}
		end
	end
	if bestDirty then
		Ranking.flushBest(bestNight, table.clone(best))
	end
	flushing = false
end

function Ranking.sync()
	if storeOff then
		return
	end
	local missing: { number } = {}
	for key, cat in cats do
		if not (key == "spend" and C.Bridge.hasRanking()) then
			local store = ods(cat.prefix .. cat.period)
			if store then
				local ok, page = try(function()
					return store:GetSortedAsync(false, R.Top * 2):GetCurrentPage()
				end)
				if ok and type(page) == "table" then
					cat.top = {}
					for _, e in page do
						local uid = tonumber(e.key)
						if uid and type(e.value) == "number" then
							cat.known[uid] = math.max(cat.known[uid] or 0, e.value)
							table.insert(cat.top, uid)
							if not names[uid] and not C.cachedName(uid) then
								table.insert(missing, uid)
							end
						end
					end
					boardsDirty = true
				end
			end
		end
	end
	local ds = bestDS()
	if ds then
		local night = bestNight
		local ok, list = try(function()
			return ds:GetAsync("n" .. night)
		end)
		if ok and type(list) == "table" and night == bestNight then
			local seenKey: { [string]: boolean } = {}
			local merged: { any } = {}
			for _, e in best do
				seenKey[e.u .. "@" .. tostring(e.at)] = true
				table.insert(merged, e)
			end
			for _, e in list do
				if type(e) == "table" and type(e.u) == "number" and type(e.v) == "number" then
					local k = e.u .. "@" .. tostring(e.at)
					if not seenKey[k] then
						seenKey[k] = true
						table.insert(merged, { u = e.u, n = tostring(e.n or "손님"), v = e.v, x = tostring(e.x or ""), at = tonumber(e.at) or 0 })
					end
				end
			end
			table.sort(merged, function(a, b)
				if a.v == b.v then
					return a.at < b.at
				end
				return a.v > b.v
			end)
			while #merged > R.BestOrders do
				table.remove(merged)
			end
			best = merged
			boardsDirty = true
		end
	end
	-- names of other servers' players: Roblox usernames (a few per sync)
	for i, uid in missing do
		if i > 6 then
			break
		end
		local n = C.userName(uid)
		if n then
			names[uid] = n
			boardsDirty = true
		end
	end
end

local function publishBoards(now: number)
	local spend, src = spendRows()
	local night, week = cats.donate.period, cats.weekly.period
	local donate = rows(cats.donate)
	local bestRows = {}
	for i, e in best do
		if i > R.BestOrders then
			break
		end
		table.insert(bestRows, { u = e.u, n = e.n, v = e.v, x = e.x })
	end
	C.publish(S.Attr.Boards, {
		v = 1,
		night = night,
		week = week,
		nl = S.nightLabel(night),
		wl = S.weekLabel(week),
		src = src,
		spend = spend,
		donate = donate,
		best = bestRows,
		weekly = rows(cats.weekly),
		kings = { spend = spend[1] and spend[1].u or 0, donate = donate[1] and donate[1].u or 0 },
		at = math.floor(now),
	})
end

function Ranking.tick(now: number)
	rollover()
	local t = os.clock()
	if t - lastFlush >= R.FlushEvery then
		lastFlush = t
		task.spawn(Ranking.flush)
	end
	if t - lastSync >= R.SyncEvery then
		lastSync = t
		task.spawn(Ranking.sync)
	end
	if boardsDirty and t - lastBoards >= 1 then
		boardsDirty = false
		lastBoards = t
		publishBoards(now)
	end
end

return Ranking
