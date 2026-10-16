-- GwangalliKaraokePlus/Store: persistence of the karaoke add-on (its own DataStores; the game's
-- profile drops unknown keys, so nothing of ours lives there).
--   GwangalliKaraokePlus_v1        key u_<UserId>: 애창곡 (fav), 최근 부른 곡 (recent), 곡별 최고 점수 (best),
--                                  노래방 수첩 (stats), settings, daily prize counter (coins)
--   GwangalliKaraokePlus_Chart_v1  key w_<year>_<week>: { [songId] = plays } -> 주간 인기차트
-- Merge on save with UpdateAsync (fav / settings newest, best = max, stats = max, recent = union).
-- Memory-only when DataStores are unavailable (Studio without API access, PlaceId 0).
-- Money-like values never persist here: credits live only in the room session.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Store = {}

local K: any
local S: any
local C: any
local Net: any

local ds: any = nil
local chartDs: any = nil
local data: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}
local loaded: { [Player]: boolean } = {}
local plays: { [string]: number } = {} -- this server's unflushed plays
local weekly: { [string]: number } = {} -- last known weekly totals (+ local)
local chartKey = ""

local MAX_FAV, MAX_RECENT = 30, 20

local function default(): any
	return {
		v = 1,
		fav = {},
		recent = {},
		best = {},
		stats = { songs = 0, hundred = 0, duets = 0, tamb = 0, rooms = 0, top = 0, firstT = 0 },
		settings = { lyricSize = "M", guideVol = 0.6, bandVol = 0.8, sync = 0.2, fx = true, mode = "auto" },
		coins = { day = 0, n = 0, last = 0 },
	}
end

local function sanitize(d: any): any
	local out = default()
	if type(d) ~= "table" then
		return out
	end
	if type(d.fav) == "table" then
		for _, id in d.fav do
			if type(id) == "string" and S.Songs.byId[id] and not table.find(out.fav, id) and #out.fav < MAX_FAV then
				table.insert(out.fav, id)
			end
		end
	end
	if type(d.recent) == "table" then
		for _, e in d.recent do
			if type(e) == "table" and type(e.s) == "string" and S.Songs.byId[e.s] and #out.recent < MAX_RECENT then
				table.insert(out.recent, { s = e.s, t = tonumber(e.t) or 0, sc = tonumber(e.sc) or -1 })
			end
		end
	end
	if type(d.best) == "table" then
		for id, v in d.best do
			if type(id) == "string" and S.Songs.byId[id] and type(v) == "number" then
				out.best[id] = math.clamp(math.floor(v), 0, 100)
			end
		end
	end
	if type(d.stats) == "table" then
		for k in out.stats do
			local v = d.stats[k]
			if type(v) == "number" and v == v then
				out.stats[k] = math.max(0, math.floor(v))
			end
		end
	end
	if type(d.settings) == "table" then
		local st = d.settings
		if st.lyricSize == "S" or st.lyricSize == "M" or st.lyricSize == "L" then
			out.settings.lyricSize = st.lyricSize
		end
		out.settings.guideVol = S.num(st.guideVol, 0, 1) or out.settings.guideVol
		out.settings.bandVol = S.num(st.bandVol, 0, 1) or out.settings.bandVol
		out.settings.sync = S.num(st.sync, 0, 0.8) or out.settings.sync
		if type(st.fx) == "boolean" then
			out.settings.fx = st.fx
		end
		if st.mode == "auto" or st.mode == "tap" then
			out.settings.mode = st.mode
		end
	end
	if type(d.coins) == "table" then
		out.coins.day = tonumber(d.coins.day) or 0
		out.coins.n = tonumber(d.coins.n) or 0
		out.coins.last = tonumber(d.coins.last) or 0
	end
	return out
end

local function merge(old: any, mine: any): any
	local o = sanitize(old)
	local m = mine
	local out = default()
	out.fav = m.fav
	out.settings = m.settings
	for id, v in o.best do
		out.best[id] = v
	end
	for id, v in m.best do
		out.best[id] = math.max(out.best[id] or 0, v)
	end
	for k in out.stats do
		out.stats[k] = math.max(o.stats[k] or 0, m.stats[k] or 0)
	end
	if (o.stats.firstT or 0) > 0 and (m.stats.firstT or 0) > 0 then
		out.stats.firstT = math.min(o.stats.firstT, m.stats.firstT)
	end
	local seen, all = {}, {}
	for _, src in { m.recent, o.recent } do
		for _, e in src do
			local key = e.s .. ":" .. tostring(e.t)
			if not seen[key] then
				seen[key] = true
				table.insert(all, e)
			end
		end
	end
	table.sort(all, function(a, b)
		return a.t > b.t
	end)
	for i = 1, math.min(MAX_RECENT, #all) do
		out.recent[i] = all[i]
	end
	out.coins = if (m.coins.day or 0) >= (o.coins.day or 0) then m.coins else o.coins
	return out
end

local function get(p: Player): any
	local d = data[p]
	if not d then
		d = default()
		data[p] = d
	end
	return d
end
Store.get = get

local function keyOf(p: Player): string
	return "u_" .. tostring(p.UserId)
end

local function load(p: Player)
	if not ds then
		loaded[p] = true
		return
	end
	local result = nil
	for attempt = 1, 3 do
		local ok, v = pcall(ds.GetAsync, ds, keyOf(p))
		if ok then
			result = v
			break
		end
		task.wait(attempt * 1.5)
	end
	if p.Parent ~= Players then
		return
	end
	local cur = data[p]
	local d = sanitize(result)
	if cur and dirty[p] then
		d = merge(d, cur) -- changes made while loading win
	end
	data[p] = d
	loaded[p] = true
end

local function save(p: Player)
	if not ds or not dirty[p] or not loaded[p] then
		return
	end
	local mine = data[p]
	if not mine then
		return
	end
	dirty[p] = nil
	local ok, err = pcall(ds.UpdateAsync, ds, keyOf(p), function(old)
		return merge(old, mine)
	end)
	if not ok then
		dirty[p] = true
		warn("[GwangalliKaraokePlus] save failed:", err)
	end
end

local function markDirty(p: Player)
	dirty[p] = true
end

-------------------------------------------------------------------------------------------------
-- records
-------------------------------------------------------------------------------------------------
-- returns (best, isBest)
function Store.record(p: Player, songId: string, score: number, duet: boolean): (number, boolean)
	local d = get(p)
	local prev = d.best[songId] or 0
	local isBest = score > prev
	if isBest then
		d.best[songId] = score
	end
	table.insert(d.recent, 1, { s = songId, t = os.time(), sc = score })
	while #d.recent > MAX_RECENT do
		table.remove(d.recent)
	end
	d.stats.songs += 1
	if score >= 100 then
		d.stats.hundred += 1
	end
	if duet then
		d.stats.duets += 1
	end
	d.stats.top = math.max(d.stats.top, score)
	if d.stats.firstT == 0 then
		d.stats.firstT = os.time()
	end
	markDirty(p)
	Net.fire(p, { kind = "me", me = Store.view(p) })
	return math.max(prev, score), isBest
end

function Store.bump(p: Player, stat: string, n: number)
	local d = get(p)
	if d.stats[stat] ~= nil then
		d.stats[stat] += n
		markDirty(p)
	end
end

local function dayKey(): number
	return math.floor(os.time() / 86400)
end

function Store.coinAllowed(p: Player): boolean
	local SC = C.ScoreCoins
	local c = get(p).coins
	if c.day ~= dayKey() then
		c.day = dayKey()
		c.n = 0
	end
	return c.n < SC.DailyMax and os.time() - (c.last or 0) >= SC.Cooldown
end

function Store.coinUsed(p: Player)
	local c = get(p).coins
	c.n += 1
	c.last = os.time()
	markDirty(p)
end

function Store.view(p: Player): any
	local d = get(p)
	return { fav = d.fav, recent = d.recent, best = d.best, stats = d.stats, settings = d.settings }
end

-------------------------------------------------------------------------------------------------
-- weekly chart
-------------------------------------------------------------------------------------------------
local function isoWeekKey(): string
	local t = os.time()
	local d = os.date("!*t", t) :: any
	-- ISO-ish: weeks start on Monday
	local wday = (d.wday + 5) % 7 -- Monday = 0
	local monday = t - wday * 86400
	local md = os.date("!*t", monday) :: any
	return string.format("w_%04d_%02d_%02d", md.year, md.month, md.day)
end

function Store.countPlay(songId: string)
	plays[songId] = (plays[songId] or 0) + 1
	weekly[songId] = (weekly[songId] or 0) + 1
end

function Store.chartTop(n: number): { string }
	local ids = {}
	for id, c in weekly do
		if c > 0 and S.Songs.byId[id] then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		if weekly[a] ~= weekly[b] then
			return weekly[a] > weekly[b]
		end
		return S.Songs.byId[a].no < S.Songs.byId[b].no
	end)
	-- fill with the seeded chart
	for _, id in S.Songs.SEED_CHART do
		if #ids >= n then
			break
		end
		if not table.find(ids, id) then
			table.insert(ids, id)
		end
	end
	while #ids > n do
		table.remove(ids)
	end
	return ids
end

local function flushChart()
	local key = isoWeekKey()
	if key ~= chartKey then
		chartKey = key
		table.clear(weekly)
		for id, c in plays do
			weekly[id] = c
		end
	end
	if not chartDs then
		return
	end
	local inc = plays
	plays = {}
	local ok, res = pcall(chartDs.UpdateAsync, chartDs, key, function(old)
		local t = if type(old) == "table" then old else {}
		for id, c in inc do
			if S.Songs.byId[id] then
				t[id] = (tonumber(t[id]) or 0) + c
			end
		end
		return t
	end)
	if ok and type(res) == "table" then
		table.clear(weekly)
		for id, c in res do
			if type(c) == "number" then
				weekly[id] = c
			end
		end
	elseif not ok then
		for id, c in inc do
			plays[id] = (plays[id] or 0) + c
		end
	end
end
Store.flushChart = flushChart

-------------------------------------------------------------------------------------------------
-- ops
-------------------------------------------------------------------------------------------------
local function fav(p: Player, a: any): any
	local id = S.str(a.song, 8)
	if not id or not S.Songs.byId[id] then
		return Net.fail("nosong")
	end
	local d = get(p)
	local i = table.find(d.fav, id)
	if a.on == true then
		if not i then
			if #d.fav >= MAX_FAV then
				return { ok = false, code = "full", message = string.format("애창곡은 %d곡까지 담을 수 있어요", MAX_FAV) }
			end
			table.insert(d.fav, 1, id)
		end
	elseif i then
		table.remove(d.fav, i)
	end
	markDirty(p)
	return { ok = true, fav = d.fav }
end

local function settings(p: Player, a: any): any
	local d = get(p)
	local st = d.settings
	if a.lyricSize ~= nil then
		if a.lyricSize ~= "S" and a.lyricSize ~= "M" and a.lyricSize ~= "L" then
			return Net.fail("bad")
		end
		st.lyricSize = a.lyricSize
	end
	for _, k in { "guideVol", "bandVol" } do
		if a[k] ~= nil then
			local v = S.num(a[k], 0, 1)
			if not v then
				return Net.fail("bad")
			end
			st[k] = v
		end
	end
	if a.sync ~= nil then
		local v = S.num(a.sync, 0, 0.8)
		if not v then
			return Net.fail("bad")
		end
		st.sync = v
	end
	if a.fx ~= nil then
		if type(a.fx) ~= "boolean" then
			return Net.fail("bad")
		end
		st.fx = a.fx
	end
	if a.mode ~= nil then
		if a.mode ~= "auto" and a.mode ~= "tap" then
			return Net.fail("bad")
		end
		st.mode = a.mode
	end
	markDirty(p)
	return { ok = true }
end

function Store.init(k: any)
	K = k
	S, C, Net = k.S, k.S.Config, k.Net
	if game.PlaceId ~= 0 then
		local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, C.DataStoreName)
		if ok then
			ds = store
		end
		local ok2, cstore = pcall(DataStoreService.GetDataStore, DataStoreService, C.ChartStoreName)
		if ok2 then
			chartDs = cstore
		end
	end
	chartKey = isoWeekKey()
	if chartDs then
		task.spawn(function()
			local ok, res = pcall(chartDs.GetAsync, chartDs, chartKey)
			if ok and type(res) == "table" then
				for id, c in res do
					if type(c) == "number" then
						weekly[id] = (weekly[id] or 0) + c
					end
				end
				K.refreshLED()
			end
		end)
	end
	Net.handle("fav", "ui", fav)
	Net.handle("settings", "ui", settings)
	local function added(p: Player)
		task.spawn(load, p)
	end
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerAdded:Connect(added)
	Players.PlayerRemoving:Connect(function(p)
		task.spawn(function()
			save(p)
			data[p] = nil
			dirty[p] = nil
			loaded[p] = nil
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(180)
			for _, p in Players:GetPlayers() do
				if dirty[p] then
					task.spawn(save, p)
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(300)
			flushChart()
			K.refreshLED()
		end
	end)
	game:BindToClose(function()
		local n = 0
		for _, p in Players:GetPlayers() do
			n += 1
			task.spawn(function()
				save(p)
				n -= 1
			end)
		end
		task.spawn(function()
			pcall(flushChart)
		end)
		local t0 = os.clock()
		while n > 0 and os.clock() - t0 < 20 do
			task.wait(0.2)
		end
	end)
end

return Store
