--!strict
-- GwangalliDecorPlus/Actions: every Request (RemoteFunction) of the 자유 배치 editor and the visitor overlay.
-- Server-authoritative: prices come from the catalog, positions are re-validated by Rules on the
-- server's own Unit index, every number is type / range checked, uids must be the player's own.
-- Token bucket + per-action cooldowns, a rid cache (a repeated request returns the first answer, so a
-- double tap never charges twice) and a per-player lock around mutations.
--   Actions.init(deps) / Actions.handle(p, action, payload) -> result { ok, code?, msg?, ... }

local Players = game:GetService("Players")

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliDecorShared"))
local Config, Catalog, Rules, Codec, Finish, Text, Geometry, Unit =
	Shared.Config, Shared.Catalog, Shared.Rules, Shared.Codec, Shared.Finish, Shared.Text, Shared.Geometry, Shared.Unit

local Actions = {}

local Host: any, Store: any, Homes: any, Social: any, push: any = nil, nil, nil, nil, nil

type Session = {
	bucket: { tokens: number, t: number },
	cool: { [string]: number },
	rids: { order: { string }, res: { [string]: any } },
	fresh: { [number]: { t: number, price: number } },
	trash: { [number]: { rec: any, how: string, amount: number, t: number } },
	busy: boolean,
}
local sessions: { [Player]: Session } = {}

function Actions.init(deps: any)
	Host, Store, Homes, Social, push = deps.Host, deps.Store, deps.Homes, deps.Social, deps.push
end

local function session(p: Player): Session
	local s = sessions[p]
	if not s then
		s = {
			bucket = { tokens = Config.RATE.burst, t = os.clock() },
			cool = {},
			rids = { order = {}, res = {} },
			fresh = {},
			trash = {},
			busy = false,
		}
		sessions[p] = s
	end
	return s
end

function Actions.drop(p: Player)
	sessions[p] = nil
end

local function fail(code: string, ...: any): any
	local msg = if select("#", ...) > 0 then Text.reason(code, ...) else Text.reason(code)
	return { ok = false, code = code, msg = msg }
end

local function finite(v: any): boolean
	return Geometry.finite(v)
end

local function int(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v or v ~= math.floor(v) or v < lo or v > hi then
		return nil
	end
	return v
end

local function balance(p: Player): any
	local c, b = Host.balance(p)
	return { cash = c, bank = b }
end

local function recView(rec: any): any
	return { u = rec.u, i = rec.i, x = rec.x, y = rec.y, z = rec.z, r = rec.r, c = rec.c, m = rec.m, on = rec.on }
end

local function copyRec(rec: any): any
	return {
		u = rec.u,
		i = rec.i,
		x = rec.x,
		y = rec.y,
		z = rec.z,
		r = rec.r,
		c = if rec.c then table.clone(rec.c) else nil,
		m = if rec.m then table.clone(rec.m) else nil,
		on = rec.on,
	}
end

-- the owner's attached home + checks
local function ownHome(p: Player): (any?, string?)
	local inst, code = Host.ownInside(p)
	if not inst then
		return nil, code
	end
	local H = Homes.ofModel(inst.model)
	if not H then
		Homes.ensure(p)
		return nil, "noData"
	end
	return H, nil
end

-- the home a visitor stands in (owner given by id)
local function visitedHome(p: Player, ownerId: any): (any?, string?)
	local inst = Host.inside(p)
	if not inst then
		return nil, "notGuest"
	end
	local H = Homes.ofModel(inst.model)
	if not H or (ownerId ~= nil and H.ownerId ~= ownerId) then
		return nil, "notGuest"
	end
	return H, nil
end

local function insufficient(p: Player, price: number): any
	local c, b = Host.balance(p)
	return fail("insufficient", Text.won(price), Text.won(b), Text.won(c))
end

local function after(p: Player, H: any, money: boolean)
	if money then
		Host.changed(p)
	end
	Store.saveSoon(p)
	Social.after(H)
end

local function freshLeft(s: Session, uid: number): number
	local f = s.fresh[uid]
	if not f then
		return 0
	end
	return math.max(0, Config.FRESH_SECONDS - (os.clock() - f.t))
end

-- pieces standing on uid (recursively, max 3 levels / 24 pieces)
local function dependents(H: any, uid: number): { number }
	local out, seen = {}, { [uid] = true }
	local frontier = { uid }
	for _ = 1, 3 do
		local nextF = {}
		for _, u in frontier do
			for _, d in Rules.standingOn(H.idx, u) do
				if not seen[d] and #out < 24 then
					seen[d] = true
					table.insert(out, d)
					table.insert(nextF, d)
				end
			end
		end
		frontier = nextF
	end
	return out
end

local function caps(H: any): any
	return Config.caps(H.tierKey)
end

local function cleanCand(raw: any): any?
	if type(raw) ~= "table" then
		return nil
	end
	if not (finite(raw.x) and finite(raw.y) and finite(raw.z)) then
		return nil
	end
	local r = if finite(raw.r) then raw.r else 0
	return { x = raw.x, y = raw.y, z = raw.z, r = Geometry.wrapYaw(r) }
end

-------------------------------------------------------------------------------------------------
-- Snapshot
-------------------------------------------------------------------------------------------------
local function presetsView(H: any): { any }
	local list = H.data.presets[H.tierKey] or {}
	local out = {}
	for i = 1, Config.PRESET_SLOTS do
		local pr = list[i]
		out[i] = if pr then { n = pr.n, t = pr.t, count = #pr.items } else false
	end
	return out
end

local function snapshot(p: Player, H: any): any
	local s = session(p)
	local items = {}
	local fresh = {}
	for _, rec in H.home.items do
		table.insert(items, recView(rec))
		local left = freshLeft(s, rec.u)
		if left > 0 then
			fresh[tostring(rec.u)] = left
		end
	end
	local r = Homes.score(H)
	local rooms = {}
	for id, th in H.U.themes do
		if #th.wall > 0 or #th.floor > 0 then
			local name, icon = Unit.roomName(id)
			table.insert(rooms, { id = id, name = name, icon = icon, wall = #th.wall > 0, floor = #th.floor > 0 })
		end
	end
	table.sort(rooms, function(a, b)
		return a.name < b.name
	end)
	local hostThemes = nil
	local HS = Host.G() and Host.G().HOMES
	if HS and HS.WALLPAPER_ORDER then
		hostThemes = { wall = {}, floor = {} }
		for _, id in HS.WALLPAPER_ORDER do
			local d = HS.WALLPAPERS[id]
			table.insert(hostThemes.wall, { id = id, name = d.name, color = d.color, material = d.material, price = HS.themePrice("wall", id, H.tierKey, nil) })
		end
		for _, id in HS.FLOOR_ORDER do
			local d = HS.FLOORS[id]
			table.insert(hostThemes.floor, { id = id, name = d.name, color = d.color, material = d.material, price = HS.themePrice("floor", id, H.tierKey, nil) })
		end
	end
	return {
		ok = true,
		ownerId = H.ownerId,
		listingId = H.listingId,
		tierKey = H.tierKey,
		homeName = Host.listingName(H.listingId),
		modelName = H.model.Name,
		caps = caps(H),
		counts = Homes.counts(H),
		items = items,
		nextUid = H.home.n,
		storage = H.data.storage,
		storageMax = Config.STORAGE_MAX,
		fin = H.home.fin,
		rooms = rooms,
		hostThemes = hostThemes,
		presets = presetsView(H),
		balance = balance(p),
		score = Social.summary(r),
		goals = Social.goalsView(H.data, r),
		badges = Social.badgesView(H.data),
		likes = H.data.likes,
		gb = H.data.gb,
		persistent = Store.persistent(p),
		fresh = fresh,
		canPay = Host.canPay(),
		config = { fresh = Config.FRESH_SECONDS, trash = Config.TRASH_SECONDS, sell = Config.SELL_RATE },
	}
end

-------------------------------------------------------------------------------------------------
-- Handlers
-------------------------------------------------------------------------------------------------
local H_: { [string]: (Player, any, Session) -> any } = {}

H_.open = function(p, _pl, _s)
	local H, code = ownHome(p)
	if not H then
		return fail(code or "notHome")
	end
	return snapshot(p, H)
end

H_.state = function(p, pl, _s)
	local H = nil
	if type(pl) == "table" and pl.ownerId == p.UserId then
		H = Homes.ofOwner(p)
	else
		H = visitedHome(p, if type(pl) == "table" then pl.ownerId else nil)
	end
	if not H then
		return fail("notGuest")
	end
	local st = Social.state(p, H)
	st.ok = true
	return st
end

H_.place = function(p, pl, s)
	local H, code = ownHome(p)
	if not H then
		return fail(code or "notHome")
	end
	if type(pl) ~= "table" then
		return fail("bad")
	end
	local def = Catalog.get(pl.i)
	if not def then
		return fail("unknown")
	end
	local cand = cleanCand(pl)
	if not cand then
		return fail("bad")
	end
	cand.i = pl.i
	local c, m = Codec.cleanLook(def, pl.c, pl.m)
	local fromStorage = pl.src == "storage" and (H.data.storage[pl.i] or 0) > 0
	local cp = caps(H)
	local ok, rcode, arg, fx = Rules.check(H.U, H.idx, cand, {
		isNew = true,
		caps = cp,
		counts = Homes.counts(H),
		overlap = pl.ov == true,
		people = Homes.people(H),
	})
	if not ok then
		if rcode == "cap" then
			return fail("cap", Host.listingName(H.listingId), arg)
		end
		return fail(rcode :: string, arg)
	end
	local price = 0
	if fromStorage then
		H.data.storage[pl.i] -= 1
		if H.data.storage[pl.i] <= 0 then
			H.data.storage[pl.i] = nil
		end
	else
		if not Host.canPay() then
			return fail("noMoney")
		end
		price = def.price
		if not Host.spend(p, price, "가구 구매 · " .. def.name) then
			return insufficient(p, price)
		end
	end
	local rec = { u = H.home.n, i = pl.i, x = fx.x, y = fx.y, z = fx.z, r = fx.r, c = c, m = m }
	H.home.n += 1
	Homes.add(H, rec)
	if price > 0 then
		s.fresh[rec.u] = { t = os.clock(), price = price }
	end
	local st = H.data.stats
	st.placed = (st.placed or 0) + 1
	if price > 0 then
		st.bought = (st.bought or 0) + 1
		st.spent = (st.spent or 0) + price
	end
	after(p, H, price > 0)
	local counts = Homes.counts(H)
	local warnMsg = nil
	if Catalog.lightCount(rec.i) > 0 and counts.realLights >= cp.lights and (H.built[rec.u] and not H.built[rec.u].extra.lights[1].Enabled) then
		warnMsg = Text.fmt(Text.UI.lightCap, cp.lights)
	end
	return { ok = true, rec = recView(rec), price = price, src = if fromStorage then "storage" else "buy", balance = balance(p), counts = counts, storage = H.data.storage, warn = warnMsg, fresh = if price > 0 then Config.FRESH_SECONDS else 0 }
end

-- one piece (+ whatever stands on it) to a new pose
H_.move = function(p, pl, _s)
	local H, code = ownHome(p)
	if not H then
		return fail(code or "notHome")
	end
	if type(pl) ~= "table" then
		return fail("bad")
	end
	local uid = int(pl.u, 1, 1e7)
	local rec = uid and H.recs[uid]
	if not rec then
		return fail("bad")
	end
	local cand = cleanCand(pl)
	if not cand then
		return fail("bad")
	end
	cand.i, cand.u = rec.i, rec.u
	local deps = if pl.carry == false then {} else dependents(H, rec.u)
	local list = { cand }
	if #deps > 0 then
		local oldPose = Geometry.pose(rec.x, rec.y, rec.z, rec.r)
		-- the base's snapped pose decides where the carried pieces go: check the base alone first
		local ok0, c0, a0, fx0 = Rules.check(H.U, H.idx, cand, { ignore = { [rec.u] = true }, overlap = pl.ov == true, people = Homes.people(H), noPath = true })
		if not ok0 then
			return fail(c0 :: string, a0)
		end
		local newPose = Geometry.pose(fx0.x, fx0.y, fx0.z, fx0.r)
		local delta = newPose * oldPose:Inverse()
		cand.x, cand.y, cand.z, cand.r = fx0.x, fx0.y, fx0.z, fx0.r
		for _, d in deps do
			local dr = H.recs[d]
			local np = delta * Geometry.pose(dr.x, dr.y, dr.z, dr.r)
			table.insert(list, { u = dr.u, i = dr.i, x = np.X, y = np.Y, z = np.Z, r = Geometry.yawOf(np) })
		end
	end
	local ok, rcode, arg, fixed = Rules.checkGroup(H.U, H.idx, list, { overlap = pl.ov == true, people = Homes.people(H) })
	if not ok then
		return fail(rcode :: string, arg)
	end
	local out = {}
	for i, c in list do
		Homes.move(H, c.u, (fixed :: any)[i])
		table.insert(out, recView(H.recs[c.u]))
	end
	after(p, H, false)
	return { ok = true, recs = out }
end

H_.moveMany = function(p, pl, _s)
	local H, code = ownHome(p)
	if not H then
		return fail(code or "notHome")
	end
	if type(pl) ~= "table" or type(pl.list) ~= "table" or #pl.list == 0 or #pl.list > Config.BATCH_MAX then
		return fail("bad")
	end
	local list = {}
	local seen = {}
	for _, e in pl.list do
		local uid = int(type(e) == "table" and e.u or nil, 1, 1e7)
		local rec = uid and H.recs[uid]
		local cand = cleanCand(e)
		if not rec or not cand or seen[uid] then
			return fail("bad")
		end
		seen[uid] = true
		cand.i, cand.u = rec.i, rec.u
		table.insert(list, cand)
	end
	local ok, rcode, arg, fixed = Rules.checkGroup(H.U, H.idx, list, { overlap = pl.ov == true, people = Homes.people(H) })
	if not ok then
		return fail(rcode :: string, arg)
	end
	local out = {}
	for i, c in list do
		Homes.move(H, c.u, (fixed :: any)[i])
		table.insert(out, recView(H.recs[c.u]))
	end
	after(p, H, false)
	return { ok = true, recs = out }
end

H_.color = function(p, pl, _s)
	local H, code = ownHome(p)
	if not H then
		return fail(code or "notHome")
	end
	if type(pl) ~= "table" then
		return fail("bad")
	end
	local uid = int(pl.u, 1, 1e7)
	local rec = uid and H.recs[uid]
	if not rec then
		return fail("bad")
	end
	local def = Catalog.get(rec.i)
	local c, m = Codec.cleanLook(def, pl.c, pl.m)
	local function same(a: any, b: any): boolean
		if a == nil or b == nil then
			return a == b
		end
		for i = 1, #def.slots do
			if a[i] ~= b[i] then
				return false
			end
		end
		return true
	end
	if same(c, rec.c) and same(m, rec.m) then
		return fail("same")
	end
	rec.c, rec.m = c, m
	Homes.restyle(H, rec.u)
	after(p, H, false)
	return { ok = true, rec = recView(rec) }
end

H_.remove = function(p, pl, s)
	local H, code = ownHome(p)
	if not H then
		return fail(code or "notHome")
	end
	if type(pl) ~= "table" or type(pl.uids) ~= "table" or #pl.uids == 0 or #pl.uids > Config.BATCH_MAX then
		return fail("bad")
	end
	local how = if pl.how == "sell" then "sell" else "store"
	local uids = {}
	local seen = {}
	for _, u in pl.uids do
		local uid = int(u, 1, 1e7)
		if not uid or not H.recs[uid] then
			return fail("bad")
		end
		if not seen[uid] then
			seen[uid] = true
			table.insert(uids, uid)
		end
	end
	-- whatever stands on a removed piece comes off with it
	for _, u in table.clone(uids) do
		for _, d in dependents(H, u) do
			if not seen[d] and #uids < Config.BATCH_MAX then
				seen[d] = true
				table.insert(uids, d)
			end
		end
	end
	if how == "store" then
		local need = 0
		for _, u in uids do
			if freshLeft(s, u) <= 0 then
				need += 1
			end
		end
		if Codec.storageCount(H.data) + need > Config.STORAGE_MAX then
			return fail("storageFull", Config.STORAGE_MAX)
		end
	end
	local removed = {}
	local money = false
	for _, u in uids do
		local rec = H.recs[u]
		local fresh = freshLeft(s, u) > 0
		local entryHow, amount = how, 0
		if fresh then
			entryHow = "refund"
			amount = s.fresh[u].price
			Host.refund(p, amount, "구매 취소 · " .. Catalog.get(rec.i).name)
			money = true
			s.fresh[u] = nil
		elseif how == "sell" then
			amount = Catalog.resale(rec.i, Config.SELL_RATE)
			Host.refund(p, amount, "가구 판매 · " .. Catalog.get(rec.i).name)
			H.data.stats.sold = (H.data.stats.sold or 0) + 1
			money = true
		else
			H.data.storage[rec.i] = math.min(99, (H.data.storage[rec.i] or 0) + 1)
		end
		s.trash[u] = { rec = copyRec(rec), how = entryHow, amount = amount, t = os.clock() }
		Homes.removeItem(H, u)
		table.insert(removed, { u = u, how = entryHow, amount = amount })
	end
	after(p, H, money)
	return { ok = true, removed = removed, balance = balance(p), counts = Homes.counts(H), storage = H.data.storage }
end

-- undo of a removal (same uids come back, at the same place)
H_.restore = function(p, pl, s)
	local H, code = ownHome(p)
	if not H then
		return fail(code or "notHome")
	end
	if type(pl) ~= "table" or type(pl.uids) ~= "table" or #pl.uids == 0 or #pl.uids > Config.BATCH_MAX then
		return fail("bad")
	end
	local list, entries = {}, {}
	local cost = 0
	local needStock: { [string]: number } = {}
	for _, u in pl.uids do
		local uid = int(u, 1, 1e7)
		local e = uid and s.trash[uid]
		if not e or os.clock() - e.t > Config.TRASH_SECONDS or H.recs[uid] then
			return fail("expired")
		end
		table.insert(entries, e)
		local r = e.rec
		table.insert(list, { u = r.u, i = r.i, x = r.x, y = r.y, z = r.z, r = r.r })
		if e.how == "store" then
			needStock[r.i] = (needStock[r.i] or 0) + 1
		elseif e.how == "sell" then
			cost += e.amount
		else
			cost += e.amount
		end
	end
	-- pieces taken from 창고 that are no longer there are bought again
	local buyAgain: { [any]: boolean } = {}
	for _, e in entries do
		if e.how == "store" then
			local have = H.data.storage[e.rec.i] or 0
			if (needStock[e.rec.i] or 0) > have then
				needStock[e.rec.i] -= 1
				buyAgain[e] = true
				cost += Catalog.price(e.rec.i)
			end
		end
	end
	local cp = caps(H)
	local counts = Homes.counts(H)
	if counts.items + #list > cp.items then
		return fail("cap", Host.listingName(H.listingId), cp.items)
	end
	local ok, rcode, arg, fixed = Rules.checkGroup(H.U, H.idx, list, { people = Homes.people(H), overlap = pl.ov == true })
	if not ok then
		return fail(rcode :: string, arg)
	end
	if cost > 0 then
		if not Host.canPay() then
			return fail("noMoney")
		end
		if not Host.spend(p, cost, "되돌리기 · 가구") then
			return insufficient(p, cost)
		end
	end
	local out = {}
	for i, e in entries do
		local rec = copyRec(e.rec)
		local fx = (fixed :: any)[i]
		rec.x, rec.y, rec.z, rec.r = fx.x, fx.y, fx.z, fx.r
		if e.how == "store" and not buyAgain[e] then
			H.data.storage[rec.i] -= 1
			if H.data.storage[rec.i] <= 0 then
				H.data.storage[rec.i] = nil
			end
		end
		if e.how == "refund" or buyAgain[e] then
			s.fresh[rec.u] = { t = os.clock(), price = Catalog.price(rec.i) }
		end
		s.trash[rec.u] = nil
		Homes.add(H, rec)
		table.insert(out, recView(rec))
	end
	after(p, H, cost > 0)
	return { ok = true, recs = out, cost = cost, balance = balance(p), counts = Homes.counts(H), storage = H.data.storage }
end

H_.sellStored = function(p, pl, _s)
	local H, code = ownHome(p)
	if not H then
		return fail(code or "notHome")
	end
	if type(pl) ~= "table" or not Catalog.get(pl.i) then
		return fail("bad")
	end
	local n = int(pl.n, 1, 99) or 1
	local have = H.data.storage[pl.i] or 0
	if have < n then
		return fail("noStock")
	end
	H.data.storage[pl.i] = if have - n > 0 then have - n else nil
	local amount = Catalog.resale(pl.i, Config.SELL_RATE) * n
	Host.refund(p, amount, "창고 가구 판매 · " .. Catalog.get(pl.i).name)
	H.data.stats.sold = (H.data.stats.sold or 0) + n
	after(p, H, true)
	return { ok = true, amount = amount, storage = H.data.storage, balance = balance(p) }
end

H_.interact = function(p, pl, _s)
	if type(pl) ~= "table" then
		return fail("bad")
	end
	local H = visitedHome(p, nil)
	if not H then
		return fail("notHome")
	end
	local uid = int(pl.u, 1, 1e7)
	local what = pl.what
	if not uid or not H.built[uid] or type(what) ~= "string" then
		return fail("bad")
	end
	local b = H.built[uid]
	if not b.prompts[what] then
		return fail("bad")
	end
	local ch = p.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if what == "sit" then
		if not hrp or ((hrp :: BasePart).Position - b.pivot.Position).Magnitude > 14 then
			return fail("bad")
		end
	end
	Homes.interact(H, uid, what, p)
	return { ok = true }
end

H_.finish = function(p, pl, _s)
	local H, code = ownHome(p)
	if not H then
		return fail(code or "notHome")
	end
	if type(pl) ~= "table" or type(pl.kind) ~= "string" or type(pl.id) ~= "string" then
		return fail("bad")
	end
	local fin = H.home.fin
	local kind = pl.kind
	local price = 0
	if kind == "light" then
		if not Finish.LIGHTS[pl.id] then
			return fail("bad")
		end
		local cur = fin.light or "default"
		if cur == pl.id then
			return fail("same")
		end
		price = Finish.price("light", pl.id, H.tierKey, nil)
		if price > 0 and not Host.spend(p, price, "조명 연출 · " .. Finish.LIGHTS[pl.id].name) then
			return insufficient(p, price)
		end
		fin.light = if pl.id == "default" then nil else pl.id
	elseif kind == "wall" or kind == "floor" then
		local room = pl.room
		local th = type(room) == "string" and H.U.themes[room] or nil
		if not th or #th[kind] == 0 then
			return fail("finishRoom")
		end
		local key = if kind == "wall" then "w" else "f"
		local cur = fin.rooms[room]
		if pl.id == "default" then
			if not (cur and cur[key]) then
				return fail("same")
			end
			cur[key] = nil
			if not cur.w and not cur.f then
				fin.rooms[room] = nil
			end
		else
			local def = Finish.def(kind, pl.id)
			if not def then
				return fail("bad")
			end
			local a = if Finish.hexOk(pl.a) then string.lower(pl.a) else nil
			local b = if Finish.hexOk(pl.b) then string.lower(pl.b) else nil
			local e = { p = pl.id, a = a, b = b }
			if cur and cur[key] and cur[key].p == e.p and cur[key].a == e.a and cur[key].b == e.b then
				return fail("same")
			end
			-- recolouring the same finish costs a quarter of it
			local full = Finish.price(kind, pl.id, H.tierKey, room)
			price = if cur and cur[key] and cur[key].p == e.p then math.floor(full / 4000 + 0.5) * 1000 else full
			if price > 0 and not Host.spend(p, price, (if kind == "wall" then "벽 마감 · " else "바닥 마감 · ") .. def.name) then
				return insufficient(p, price)
			end
			if not cur then
				cur = {}
				fin.rooms[room] = cur
			end
			cur[key] = e
		end
	else
		return fail("bad")
	end
	H.data.stats.finishes = (H.data.stats.finishes or 0) + 1
	Homes.applyFinish(H)
	Homes.refreshBonus(H)
	after(p, H, price > 0)
	return { ok = true, fin = fin, price = price, balance = balance(p) }
end

-------------------------------------------------------------------------------------------------
-- Presets (배치 저장 3칸 per home layout)
-------------------------------------------------------------------------------------------------
local function planPreset(H: any, pr: any): any
	local pool: { [string]: { any } } = {}
	for _, rec in H.home.items do
		pool[rec.i] = pool[rec.i] or {}
		table.insert(pool[rec.i], rec)
	end
	local stock = table.clone(H.data.storage)
	local plan = { move = 0, fromStorage = 0, buy = 0, cost = 0, steps = {} }
	for _, item in pr.items do
		local def = Catalog.get(item.i)
		if def then
			local src
			if pool[item.i] and #pool[item.i] > 0 then
				src = { kind = "move", rec = table.remove(pool[item.i]) }
				plan.move += 1
			elseif (stock[item.i] or 0) > 0 then
				stock[item.i] -= 1
				src = { kind = "storage" }
				plan.fromStorage += 1
			else
				src = { kind = "buy", price = def.price }
				plan.buy += 1
				plan.cost += def.price
			end
			table.insert(plan.steps, { item = item, src = src })
		end
	end
	local leftover = 0
	for _, l in pool do
		leftover += #l
	end
	plan.leftover = leftover
	plan.pool = pool
	-- finishes that differ from now are charged at their price
	local finCost = 0
	local cur = H.home.fin
	for room, e in pr.fin.rooms do
		if H.U.themes[room] then
			local c = cur.rooms[room]
			for key, kind in { w = "wall", f = "floor" } do
				local want = e[key]
				local have = c and c[key]
				if want and not (have and have.p == want.p and have.a == want.a and have.b == want.b) then
					finCost += Finish.price(kind, want.p, H.tierKey, room)
				end
			end
		end
	end
	if pr.fin.light and pr.fin.light ~= cur.light then
		finCost += Finish.price("light", pr.fin.light, H.tierKey, nil)
	end
	plan.finCost = finCost
	return plan
end

H_.preset = function(p, pl, s)
	local H, code = ownHome(p)
	if not H then
		return fail(code or "notHome")
	end
	if type(pl) ~= "table" or type(pl.op) ~= "string" then
		return fail("bad")
	end
	local slot = int(pl.slot, 1, Config.PRESET_SLOTS)
	if not slot then
		return fail("bad")
	end
	local tier = H.tierKey or "default"
	H.data.presets[tier] = H.data.presets[tier] or {}
	local list = H.data.presets[tier]
	local op = pl.op
	if op == "save" then
		if #H.home.items == 0 then
			return fail("presetEmpty")
		end
		local name = Text.clip(pl.name, Config.PRESET_NAME_LEN)
		if name ~= "" then
			name = Social.filterForUser(name, p) or Text.fmt(Text.UI.presetDefaultName, slot)
		else
			name = Text.fmt(Text.UI.presetDefaultName, slot)
		end
		local items = {}
		for _, rec in H.home.items do
			table.insert(items, copyRec(rec))
		end
		list[slot] = { n = name, t = os.time(), items = items, fin = Finish.sanitize(H.home.fin) }
		H.data.stats.presets = (H.data.stats.presets or 0) + 1
		after(p, H, false)
		return { ok = true, presets = presetsView(H), name = name }
	elseif op == "delete" then
		list[slot] = nil
		Store.saveSoon(p)
		return { ok = true, presets = presetsView(H) }
	elseif op == "plan" or op == "load" then
		local pr = list[slot]
		if not pr then
			return fail("noPreset")
		end
		local plan = planPreset(H, pr)
		if op == "plan" then
			return { ok = true, move = plan.move, fromStorage = plan.fromStorage, buy = plan.buy, cost = plan.cost, finCost = plan.finCost, leftover = plan.leftover, name = pr.n }
		end
		local buy = pl.buy == true
		local total = plan.finCost + (if buy then plan.cost else 0)
		if total > 0 and not Host.canPay() then
			return fail("noMoney")
		end
		local cash, bank = Host.balance(p)
		if total > cash + bank then
			return insufficient(p, total)
		end
		-- 창고 room for what is left over (+ what is not bought)
		local storageAfter = Codec.storageCount(H.data) - plan.fromStorage + plan.leftover
		if storageAfter > Config.STORAGE_MAX then
			return fail("storageFull", Config.STORAGE_MAX)
		end
		-- 1. lift every current piece off (kept in the pool by uid)
		for _, rec in table.clone(H.home.items) do
			Homes.removeItem(H, rec.u)
			s.fresh[rec.u] = nil
		end
		-- 2. place the preset in height order
		table.sort(plan.steps, function(a, b)
			return a.item.y < b.item.y
		end)
		local cp = caps(H)
		local placed, skipped, spent = 0, 0, 0
		local returnPool: { any } = {}
		for _, st in plan.steps do
			local it = st.item
			local src = st.src
			local cand = { u = if src.kind == "move" then src.rec.u else -1, i = it.i, x = it.x, y = it.y, z = it.z, r = it.r }
			local ok, _, _, fx = Rules.check(H.U, H.idx, cand, { isNew = true, caps = cp, counts = Homes.counts(H), people = Homes.people(H), noPath = true })
			local paid = true
			if ok and src.kind == "buy" then
				if not buy then
					paid = false
				elseif Host.spend(p, src.price, "프리셋 가구 구매 · " .. Catalog.get(it.i).name) then
					spent += src.price
				else
					paid = false
				end
			end
			if ok and paid then
				local u
				if src.kind == "move" then
					u = src.rec.u
				else
					u = H.home.n
					H.home.n += 1
				end
				if src.kind == "storage" then
					H.data.storage[it.i] = (H.data.storage[it.i] or 1) - 1
					if H.data.storage[it.i] <= 0 then
						H.data.storage[it.i] = nil
					end
				end
				local rec = { u = u, i = it.i, x = fx.x, y = fx.y, z = fx.z, r = fx.r, c = if it.c then table.clone(it.c) else nil, m = if it.m then table.clone(it.m) else nil, on = it.on }
				Homes.add(H, rec)
				if src.kind == "buy" then
					s.fresh[u] = { t = os.clock(), price = src.price }
				end
				placed += 1
			else
				skipped += 1
				if src.kind == "move" then
					table.insert(returnPool, src.rec)
				end
			end
		end
		-- 3. pieces not used by the preset go to 창고
		for _, l in plan.pool do
			for _, rec in l do
				table.insert(returnPool, rec)
			end
		end
		for _, rec in returnPool do
			H.data.storage[rec.i] = math.min(99, (H.data.storage[rec.i] or 0) + 1)
		end
		-- 4. finishes
		if plan.finCost > 0 then
			if Host.spend(p, plan.finCost, "프리셋 벽지 · 바닥 · 조명") then
				spent += plan.finCost
				H.home.fin = Finish.sanitize(pr.fin)
			end
		else
			H.home.fin = Finish.sanitize(pr.fin)
		end
		Homes.applyFinish(H)
		Homes.refreshBonus(H)
		after(p, H, spent > 0)
		local snap = snapshot(p, H)
		snap.placed, snap.skipped, snap.spent, snap.name = placed, skipped, spent, pr.n
		return snap
	end
	return fail("bad")
end

H_.like = function(p, pl, _s)
	local H, code = visitedHome(p, if type(pl) == "table" then pl.ownerId else nil)
	if not H then
		return fail(code or "notGuest")
	end
	local ok, c, res = Social.like(p, H)
	if not ok then
		return fail(c :: string)
	end
	res.ok = true
	return res
end

H_.guestbook = function(p, pl, _s)
	local H, code = visitedHome(p, if type(pl) == "table" then pl.ownerId else nil)
	if not H then
		return fail(code or "notGuest")
	end
	local ok, c, res = Social.write(p, H, type(pl) == "table" and pl.text or nil)
	if not ok then
		return fail(c :: string)
	end
	res.ok = true
	return res
end

H_.gbDelete = function(p, pl, _s)
	local H = Homes.ofOwner(p)
	if not H or type(pl) ~= "table" then
		return fail("notOwner")
	end
	local ok, c, res = Social.erase(p, H, pl.t, pl.u)
	if not ok then
		return fail(c :: string)
	end
	res.ok = true
	return res
end

H_.photo = function(p, _pl, _s)
	local H = visitedHome(p, nil)
	if not H then
		return fail("notHome")
	end
	local ok, c, res = Social.photo(p, H)
	if not ok then
		return fail(c :: string)
	end
	res.ok = true
	return res
end

H_.set = function(p, pl, _s)
	-- 세트 완성 (the client finished a 스타일 세트 cart): verified against the placed pieces
	local H = Homes.ofOwner(p)
	if not H or type(pl) ~= "table" or type(pl.id) ~= "string" then
		return fail("bad")
	end
	for _, set in Catalog.SETS do
		if set.id == pl.id then
			local have: { [string]: number } = {}
			for _, rec in H.home.items do
				have[rec.i] = (have[rec.i] or 0) + 1
			end
			for _, id in set.items do
				if not have[id] then
					return fail("bad")
				end
			end
			H.data.stats.sets = (H.data.stats.sets or 0) + 1
			after(p, H, false)
			return { ok = true }
		end
	end
	return fail("bad")
end

-------------------------------------------------------------------------------------------------
-- Dispatch
-------------------------------------------------------------------------------------------------
local MUTATING = { place = true, move = true, moveMany = true, color = true, remove = true, restore = true, sellStored = true, finish = true, preset = true, like = true, guestbook = true, gbDelete = true, photo = true, set = true }
local COST = { move = 0.5, moveMany = 1, state = 0.5, interact = 0.5 }

local function allow(s: Session, action: string): boolean
	local now = os.clock()
	local b = s.bucket
	b.tokens = math.min(Config.RATE.burst, b.tokens + (now - b.t) * Config.RATE.tokens)
	b.t = now
	local cost = COST[action] or 1
	if b.tokens < cost then
		return false
	end
	local cd = (Config.COOLDOWN :: any)[action] or 0.1
	local last = s.cool[action]
	if last and now - last < cd then
		return false
	end
	b.tokens -= cost
	s.cool[action] = now
	return true
end

function Actions.handle(p: Player, action: any, payload: any): any
	if type(action) ~= "string" or #action > 24 or not H_[action] then
		return fail("bad")
	end
	if p.Parent ~= Players then
		return fail("bad")
	end
	if not Host.ready() then
		return fail("booting")
	end
	local s = session(p)
	local rid = type(payload) == "table" and payload.rid or nil
	if rid ~= nil and (type(rid) ~= "string" or #rid > 24) then
		return fail("bad")
	end
	if rid and s.rids.res[rid] then
		return s.rids.res[rid]
	end
	if not allow(s, action) then
		return fail("rate")
	end
	if MUTATING[action] then
		local t0 = os.clock()
		while s.busy and os.clock() - t0 < 4 do
			task.wait(0.05)
		end
		if s.busy then
			return fail("busy")
		end
		s.busy = true
	end
	local ok, res = pcall(H_[action], p, payload, s)
	if MUTATING[action] then
		s.busy = false
	end
	if not ok then
		warn("[GwangalliDecorPlus] " .. action .. " failed: " .. tostring(res))
		res = fail("bad")
	end
	if rid and MUTATING[action] then
		s.rids.res[rid] = res
		table.insert(s.rids.order, rid)
		while #s.rids.order > Config.RID_CACHE do
			s.rids.res[table.remove(s.rids.order, 1) :: string] = nil
		end
	end
	return res
end

return Actions
