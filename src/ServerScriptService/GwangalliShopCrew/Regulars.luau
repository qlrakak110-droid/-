-- GwangalliShopCrew/Regulars: 단골 (regular customers). Per player, per shop: visit days, 도장 쿠폰 stamps,
-- coupons, favourite dishes, friendship with the staff (칭찬 / 팁 / 항의) and the day's once-only perks.
--   A VISIT DAY = the first real payment (Bus "paid", total > 0, not auto-charged) of a player in a shop per KST day.
--   Levels by visit days (Config.REGULAR.levels): 첫 방문 · 아는 얼굴 · 단골 · 찐단골 · 가족 같은 손님.
--   Stamps: +1 per visit day; 10 stamps -> 1 coupon (max 3). The next paid meal there with a coupon gets up to
--   couponValue back (Bridge.earn), at most once per shop per day and dailyEarnCap per player per day.
--   Regulars.init(Shared, Bridge, Net)   Regulars.load(p) / unload(p)   Regulars.save(p)   Regulars.saveAll()
--   Regulars.view(uid, key) -> { level, title, visits, stamps, coupons, fav, friend, nextAt, first }
--   Regulars.onPaid(p, key, shopName, d) -> { visit, level, up, stamp, coupon } (what changed, for lines / receipt)
--   Regulars.friend(p, key, delta, reason) -> new value (daily gain cap)
--   Regulars.dayFlag(p, bucket, key) -> bool (already)   Regulars.setDayFlag(p, bucket, key)
--   Regulars.tipsToday(p) / addTip(p)   Regulars.card(p, key, shopName) -> card table for the client
-- DataStore Config.DATASTORE, key "u_<UserId>", UpdateAsync merge; memory only when DataStores are unavailable.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Regulars = {}

local Config: any = nil
local Bridge: any = nil
local Util: any = nil

local store: GlobalDataStore? = nil
local profiles: { [number]: any } = {}
local dirty: { [number]: boolean } = {}
local loading: { [number]: boolean } = {}

function Regulars.init(S: any, B: any, N: any)
	Config, Bridge, Util = S.Config, B, S.Util
	local _ = N
	if not Config.REGULAR.enabled then
		return
	end
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE)
	end)
	if ok then
		store = ds
	end
end

local function blank(): any
	return { v = 1, shops = {}, day = { d = Util.dayKey(), earned = 0, flags = {}, tips = 0 }, tot = { visits = 0 } }
end

local function today(prof: any): any
	local d = Util.dayKey()
	if prof.day.d ~= d then
		prof.day = { d = d, earned = 0, flags = {}, tips = 0 }
	end
	return prof.day
end

local function shopRec(prof: any, key: string): any
	local s = prof.shops[key]
	if not s then
		s = { n = 0, last = "", st = 0, cp = 0, fav = {}, nm = "", fr = 0 }
		prof.shops[key] = s
	end
	return s
end

-- keep the record small: the 120 most recent shops
local function trim(prof: any)
	local list = {}
	for k, s in prof.shops do
		table.insert(list, { k = k, last = s.last or "" })
	end
	if #list <= Config.REGULAR.maxShops then
		return
	end
	table.sort(list, function(a, b)
		return a.last > b.last
	end)
	for i = Config.REGULAR.maxShops + 1, #list do
		prof.shops[list[i].k] = nil
	end
end

local function merge(old: any, mine: any): any
	if type(old) ~= "table" or type(old.shops) ~= "table" then
		return mine
	end
	local out = old
	for k, s in mine.shops do
		local o = out.shops[k]
		if not o then
			out.shops[k] = s
		else
			local newer = (s.last or "") >= (o.last or "")
			o.n = math.max(tonumber(o.n) or 0, tonumber(s.n) or 0)
			if newer then
				o.last, o.st, o.cp, o.nm = s.last, s.st, s.cp, s.nm
				o.fav = s.fav
				o.fr = s.fr
			end
		end
	end
	if type(out.day) ~= "table" or (mine.day and (mine.day.d or "") >= (out.day.d or "")) then
		out.day = mine.day
	end
	out.tot = out.tot or { visits = 0 }
	out.tot.visits = math.max(tonumber(out.tot.visits) or 0, tonumber(mine.tot and mine.tot.visits) or 0)
	return out
end

function Regulars.load(p: Player)
	if not Config.REGULAR.enabled then
		return
	end
	local uid = p.UserId
	if profiles[uid] or loading[uid] then
		return
	end
	loading[uid] = true
	local prof = blank()
	if store and uid > 0 then
		local ok, data = pcall(function()
			return (store :: GlobalDataStore):GetAsync("u_" .. uid)
		end)
		if ok and type(data) == "table" and type(data.shops) == "table" then
			prof = data
			prof.day = if type(prof.day) == "table" then prof.day else blank().day
			prof.day.flags = if type(prof.day.flags) == "table" then prof.day.flags else {}
			prof.tot = if type(prof.tot) == "table" then prof.tot else { visits = 0 }
		end
	end
	loading[uid] = nil
	if p.Parent then
		profiles[uid] = prof
	end
end

function Regulars.save(p: Player | number)
	local uid = if type(p) == "number" then p else (p :: Player).UserId
	local prof = profiles[uid]
	if not prof or not dirty[uid] or not store or uid <= 0 then
		return
	end
	dirty[uid] = nil
	trim(prof)
	local ok, err = pcall(function()
		(store :: GlobalDataStore):UpdateAsync("u_" .. uid, function(old)
			return merge(old, prof)
		end)
	end)
	if not ok then
		dirty[uid] = true
		Bridge.warnOnce("save", "regulars save: " .. tostring(err))
	end
end

function Regulars.unload(p: Player)
	Regulars.save(p)
	profiles[p.UserId] = nil
	dirty[p.UserId] = nil
end

function Regulars.saveAll()
	for uid in dirty do
		Regulars.save(uid)
	end
end

local function prof(uid: number): any?
	return profiles[uid]
end

local function levelOf(n: number): number
	local lv = 0
	for i, need in Config.REGULAR.levels do
		if n >= need then
			lv = i
		end
	end
	return lv
end
Regulars.levelOf = levelOf

function Regulars.view(uid: number, key: string): any
	local P = prof(uid)
	local s = P and P.shops[key]
	local n = s and s.n or 0
	local lv = levelOf(n)
	local favName, favN = nil, 0
	if s then
		for id, c in s.fav do
			if c > favN then
				favName, favN = id, c
			end
		end
	end
	local nextAt = Config.REGULAR.levels[lv + 1]
	return {
		level = lv,
		title = Config.REGULAR.titles[lv] or "처음 오신 손님",
		visits = n,
		stamps = s and s.st or 0,
		coupons = s and s.cp or 0,
		fav = favName,
		favCount = favN,
		friend = s and s.fr or 0,
		nextAt = nextAt,
		first = n == 0,
		visitedToday = s ~= nil and s.last == Util.dayKey(),
	}
end

function Regulars.dayFlag(p: Player, bucket: string, key: string): boolean
	local P = prof(p.UserId)
	if not P then
		return false
	end
	local d = today(P)
	local b = d.flags[bucket]
	return type(b) == "table" and b[key] == true
end

function Regulars.setDayFlag(p: Player, bucket: string, key: string)
	local P = prof(p.UserId)
	if not P then
		return
	end
	local d = today(P)
	d.flags[bucket] = d.flags[bucket] or {}
	d.flags[bucket][key] = true
	dirty[p.UserId] = true
end

function Regulars.tipsToday(p: Player): number
	local P = prof(p.UserId)
	return if P then (today(P).tips or 0) else 0
end

function Regulars.addTip(p: Player)
	local P = prof(p.UserId)
	if P then
		local d = today(P)
		d.tips = (d.tips or 0) + 1
		dirty[p.UserId] = true
	end
end

-- friendship with a shop's staff, capped gain per day
function Regulars.friend(p: Player, key: string, delta: number, _reason: string?): number
	local P = prof(p.UserId)
	if not P then
		return 0
	end
	local s = shopRec(P, key)
	local d = today(P)
	d.flags.fr = d.flags.fr or {}
	local gained = tonumber(d.flags.fr[key]) or 0
	if delta > 0 then
		delta = math.min(delta, math.max(0, Config.FRIEND.perDayGain - gained))
		d.flags.fr[key] = gained + delta
	end
	s.fr = math.clamp((tonumber(s.fr) or 0) + delta, -50, Config.FRIEND.max)
	dirty[p.UserId] = true
	return s.fr
end

-- a payment in a shop: visit day, stamp, coupon, favourite dishes
function Regulars.onPaid(p: Player, key: string, shopName: string, d: any): any
	local out: any = { visit = false, up = false }
	local P = prof(p.UserId)
	if not P or not Config.REGULAR.enabled then
		return out
	end
	local total = tonumber(d.total) or 0
	local s = shopRec(P, key)
	s.nm = shopName
	-- favourite dishes
	for _, it in (if type(d.items) == "table" then d.items else {}) do
		if type(it) == "table" then
			local name = tostring(it.name or it.id or "")
			if name ~= "" then
				s.fav[name] = math.min(9999, (s.fav[name] or 0) + (tonumber(it.qty) or 1))
			end
		end
	end
	-- at most 8 favourites
	local favs = {}
	for n, c in s.fav do
		table.insert(favs, { n = n, c = c })
	end
	if #favs > 8 then
		table.sort(favs, function(a, b)
			return a.c > b.c
		end)
		s.fav = {}
		for i = 1, 8 do
			s.fav[favs[i].n] = favs[i].c
		end
	end
	local day = today(P)
	local dk = Util.dayKey()
	if total > 0 and d.auto ~= true and s.last ~= dk then
		local before = levelOf(s.n)
		s.n += 1
		s.last = dk
		P.tot.visits = (P.tot.visits or 0) + 1
		out.visit = true
		s.st += 1
		out.stamp = s.st
		if s.st >= Config.REGULAR.stampsPerCoupon then
			s.st = 0
			if s.cp < Config.REGULAR.maxCoupons then
				s.cp += 1
				out.newCoupon = true
			end
		end
		local after = levelOf(s.n)
		if after > before then
			out.up = true
		end
		out.level = after
		out.title = Config.REGULAR.titles[after]
	end
	-- coupon: money back for this meal (only on a real payment, once per shop per day, daily cap)
	if total > 0 and d.auto ~= true and s.cp > 0 and not out.newCoupon then
		day.flags.cp = day.flags.cp or {}
		if not day.flags.cp[key] then
			local room = math.max(0, Config.REGULAR.dailyEarnCap - (day.earned or 0))
			local back = math.min(total, Config.REGULAR.couponValue, room)
			if back > 0 and Bridge.earn(p, back, "단골 쿠폰 · " .. shopName) then
				s.cp -= 1
				day.flags.cp[key] = true
				day.earned = (day.earned or 0) + back
				out.coupon = back
			end
		end
	end
	dirty[p.UserId] = true
	return out
end

-- the 단골 card the client draws
function Regulars.card(p: Player, key: string, shopName: string, icon: string?): any
	local v = Regulars.view(p.UserId, key)
	local P = prof(p.UserId)
	local top = {}
	if P then
		for k, s in P.shops do
			table.insert(top, { key = k, shopName = s.nm ~= "" and s.nm or k, visits = s.n, level = levelOf(s.n) })
		end
		table.sort(top, function(a, b)
			return a.visits > b.visits
		end)
		while #top > 5 do
			table.remove(top)
		end
	end
	local perks = {}
	if v.level >= Config.REGULAR.nameLevel then
		table.insert(perks, "직원이 이름을 불러 줘요")
	end
	if v.level >= Config.REGULAR.serviceLevel then
		table.insert(perks, "하루 한 번 서비스 메뉴")
	end
	table.insert(perks, string.format("도장 %d개 모으면 쿠폰 (최대 %s 환급)", Config.REGULAR.stampsPerCoupon, Util.won(Config.REGULAR.couponValue)))
	return {
		shop = key,
		shopName = shopName,
		icon = icon,
		level = v.level,
		title = v.title,
		visits = v.visits,
		nextAt = v.nextAt,
		nextTitle = if v.nextAt then Config.REGULAR.titles[v.level + 1] else nil,
		stamps = v.stamps,
		stampsMax = Config.REGULAR.stampsPerCoupon,
		coupons = v.coupons,
		fav = v.fav,
		favCount = v.favCount,
		friend = v.friend,
		perks = perks,
		top = top,
	}
end

function Regulars.markDirty(uid: number)
	dirty[uid] = true
end

function Regulars.start()
	if not Config.REGULAR.enabled then
		return
	end
	Players.PlayerAdded:Connect(function(p)
		task.spawn(Regulars.load, p)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(Regulars.load, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		task.spawn(Regulars.unload, p)
	end)
	task.spawn(function()
		while true do
			task.wait(Config.REGULAR.saveEvery)
			pcall(Regulars.saveAll)
		end
	end)
end

return Regulars
