-- GwangalliCarDealer/Service (server): the Request RemoteFunction. Every input is validated (op whitelist,
-- payload shape, strict entry ids, colour ids), rate limited (our bucket + per-op cooldowns, on top of the
-- garage's own), and mutating ops run one at a time per player. Contracts / test drives / rentals need the
-- player near a dealer NPC; browsing works anywhere. Money and cars always move through the garage API.
--
--   hello {npc}                       -> { npc, ctx }           visit count, greeting context
--   catalog                           -> snapshot for the catalog UI (see Service.snapshot)
--   buy {entry, color, loan, nonce, trade?}  -> garage buy result + { cashback, cashbackLines, trade? }
--   sell {id}                         -> garage sell result
--   testdrive {entry, color}          -> { ok, mode = "garage" | "dealer", seconds }
--   endtest                           -> { ok }
--   rent                              -> garage rent result
--   deliver {id}                      -> { ok, meters, seated }  (call the bought car + driver's seat)
--   wish {entry, on}                  -> { ok, wish }
--   waypoint                          -> { ok }
-- Buys are idempotent per nonce (a retried request returns the first answer).

local Players = game:GetService("Players")

local Service = {}

local S: any
local C: any
local U: any
local Catalog: any
local Bridge: any
local Store: any
local Npc: any
local TestDrive: any

local bucket: any
local cools: any
local busy: { [Player]: boolean } = {}
local nonces: { [Player]: { [string]: { t: number, res: any } } } = {}
local availCache: { t: number, v: { [string]: boolean } }? = nil

local MUTATING = { buy = true, sell = true, testdrive = true, rent = true, deliver = true, endtest = true }

function Service.init(shared: any, bridge: any, store: any, npc: any, testDrive: any)
	S = shared
	C = shared.Config
	U = shared.Util
	Catalog = shared.Catalog
	Bridge = bridge
	Store = store
	Npc = npc
	TestDrive = testDrive
	bucket = U.bucket(C.RATE.perSecond, C.RATE.burst)
	cools = U.cooldowns()
end

local function fail(code: string, message: string, extra: { [string]: any }?): { [string]: any }
	local r = { ok = false, code = code, message = message }
	if extra then
		for k, v in extra do
			r[k] = v
		end
	end
	return r
end

local function avail(): { [string]: boolean }
	local c = availCache
	if c and os.clock() - c.t < 10 then
		return c.v
	end
	local v = Bridge.availableModels()
	availCache = { t = os.clock(), v = v }
	return v
end

local function entries(): ({ any }, { [string]: any }, { [string]: boolean })
	local GS = S.GS(0)
	local VS = S.VS(0)
	local list, byId = Catalog.build(GS, VS, { avail = avail(), showAll = C.SHOW_MODELS_WITHOUT_TEMPLATE, rent = true })
	local specials = {}
	if C.SPECIALS.enabled then
		specials = Catalog.pickSpecials(list, S.monthKey(), C.SPECIALS.count, C.SPECIALS.minPrice)
		for id in specials do
			if byId[id] then
				byId[id].special = true
			end
		end
	end
	return list, byId, specials
end

-- Within C.CONTRACT_RANGE of a dealer NPC (or, with no NPC placed at all, the garage's own check decides).
local function nearDealer(player: Player): boolean
	local root = Bridge.root(player)
	if not root then
		return false
	end
	local list = Npc.list()
	if #list == 0 then
		return true
	end
	for _, n in list do
		if (n.pos - root.Position).Magnitude <= C.CONTRACT_RANGE then
			return true
		end
	end
	return false
end

local BLOCK_MSG = {
	shift = "근무 중에는 시승할 수 없어요 · 근무가 끝난 뒤 다시 와 주세요",
	taxi = "택시 운행 중에는 시승할 수 없어요",
	cuffed = "지금은 이용할 수 없어요",
	dead = "지금은 이용할 수 없어요",
}

local function validColor(GS: any, id: any): string
	if type(id) == "string" and type(GS.COLORS) == "table" then
		for _, c in GS.COLORS do
			if c.id == id then
				return id
			end
		end
	end
	return GS.DEFAULT_COLOR or "white"
end

-- entry id -> entry (validated against the live data), or a fail result
local function resolve(id: any, byId: { [string]: any }): (any?, { [string]: any }?)
	local p = Catalog.parse(id)
	if not p then
		return nil, fail("bad", "없는 차예요")
	end
	local e = byId[id]
	if not e then
		return nil, fail("bad", "지금은 팔지 않는 차예요")
	end
	return e, nil
end

local function carsOf(st: any): { any }
	return if type(st.cars) == "table" then st.cars else {}
end

-------------------------------------------------------------------------------------------------
-- ops
-------------------------------------------------------------------------------------------------
local OPS: { [string]: (Player, { [string]: any }) -> { [string]: any } } = {}

function OPS.hello(player, p)
	local GS = S.GS(0)
	local info = Npc.info(p.npc)
	if not info then
		local root = Bridge.root(player)
		info = root and Npc.nearest(root.Position) or nil
	end
	local rec, fresh = Store.visit(player)
	local st = Bridge.status(player)
	local _, byId = entries()
	local testedId = Store.lastTested(player)
	local tested = testedId and byId[testedId]
	local cars = carsOf(st or {})
	local ownedName = nil
	for _, c in cars do
		if type(c) == "table" and not c.rental then
			ownedName = c.label or (GS and GS.carName(c)) or "내 차"
			break
		end
	end
	local owned = if st and type(st.owned) == "number" then st.owned else 0
	local max = if st and type(st.max) == "number" then st.max else (GS and GS.MAX_CARS or 3)
	return {
		ok = true,
		code = "ok",
		npc = info,
		ctx = {
			visits = rec.visits,
			first = rec.visits <= 1 and fresh,
			fresh = fresh,
			owned = owned,
			max = max,
			full = owned >= max,
			ownedName = ownedName,
			tested = if tested then tested.id else nil,
			testedName = if tested then tested.name else nil,
			level = Bridge.level(player),
			garageReady = st ~= nil,
			near = nearDealer(player),
			canSell = st ~= nil and owned > 0,
		},
	}
end

function Service.snapshot(player: Player): { [string]: any }
	local GS = S.GS(0)
	local st = Bridge.status(player)
	local _, _, specials = entries()
	local bank, cash
	if st and type(st.bank) == "number" then
		bank, cash = st.bank, st.cash or 0
	else
		bank, cash = Bridge.balance(player)
	end
	local level = Bridge.level(player)
	local cars = carsOf(st or {})
	local loanBlocked, rentActive = false, false
	for _, c in cars do
		if type(c) == "table" then
			if type(c.loan) == "table" and (c.loan.missed or 0) > 0 then
				loanBlocked = true
			end
			if c.rental then
				rentActive = true
			end
		end
	end
	local rec = Store.get(player)
	local specialList = {}
	for id in specials do
		table.insert(specialList, id)
	end
	table.sort(specialList)
	local av = avail()
	local avList = {}
	for id in av do
		table.insert(avList, id)
	end
	local tCool = math.max(if st and type(st.testCooldown) == "number" then st.testCooldown else 0, TestDrive.cooldownLeft(player))
	return {
		ok = true,
		code = "ok",
		garageReady = st ~= nil,
		loaded = st ~= nil and st.loaded ~= false,
		avail = avList,
		showAll = C.SHOW_MODELS_WITHOUT_TEMPLATE,
		month = S.monthKey(),
		daysLeft = S.daysLeft(),
		specials = specialList,
		cars = cars,
		owned = if st and type(st.owned) == "number" then st.owned else 0,
		max = if st and type(st.max) == "number" then st.max else (GS and GS.MAX_CARS or 3),
		outId = st and st.outId or nil,
		bank = bank,
		cash = cash,
		level = level,
		usedRate = if C.USED_DISCOUNT_CASHBACK then S.usedRate(level) else 0,
		gates = {
			enforce = C.ENFORCE_LEVEL_GATES,
			loanLevel = S.perkLevel("car_loan"),
			luxuryLevel = S.perkLevel("luxury_new"),
			hasLoan = S.hasPerk(level, "car_loan"),
			hasLuxury = S.hasPerk(level, "luxury_new"),
		},
		loanBlocked = loanBlocked,
		rentActive = rentActive,
		testCooldown = tCool,
		testing = (st and st.testing == true) or TestDrive.active(player) ~= nil,
		near = nearDealer(player),
		wish = table.clone(rec.wish),
		tested = table.clone(rec.tested),
		best = table.clone(rec.best),
		tradeBonus = if C.TRADEIN.enabled then C.TRADEIN.bonusRate else 0,
		free = st and st.free == true or false,
	}
end

function OPS.catalog(player, _p)
	return Service.snapshot(player)
end

local function levelGate(player: Player, e: any, loan: boolean): { [string]: any }?
	if not C.ENFORCE_LEVEL_GATES then
		return nil
	end
	local level = Bridge.level(player)
	if loan and not S.hasPerk(level, "car_loan") then
		return fail("level", string.format("할부는 레벨 %d부터 이용할 수 있어요", S.perkLevel("car_loan") or 8))
	end
	if e.kind == "luxury" and e.grade == "new" and not e.model and not S.hasPerk(level, "luxury_new") then
		return fail("level", string.format("플래그십 신차는 레벨 %d부터 출고돼요", S.perkLevel("luxury_new") or 18))
	end
	return nil
end

local function pctLabel(fmtStr: string, rate: number): string
	return string.format(fmtStr, math.floor(rate * 100 + 0.5))
end

function OPS.buy(player, p)
	local GS = S.GS(0)
	if not GS then
		return fail("offline", "정비소 전산이 아직 준비되지 않았어요")
	end
	local nonce = U.str(p.nonce, 24, "^[%w%-_]+$")
	if not nonce then
		return fail("bad", "잘못된 요청이에요")
	end
	local seen = nonces[player]
	if seen and seen[nonce] then
		return seen[nonce].res
	end
	local _, byId, specials = entries()
	local e, bad = resolve(p.entry, byId)
	if not e then
		return bad :: any
	end
	if e.grade == "rent" then
		return fail("bad", "렌트는 '하루 렌트'로 신청해 주세요")
	end
	if not nearDealer(player) then
		return fail("far", "계약은 광안 오토 매장에서 상담원과 할 수 있어요")
	end
	local why = Bridge.blocked(player)
	if why == "cuffed" or why == "dead" then
		return fail(why, BLOCK_MSG[why])
	end
	local loan = U.bool(p.loan) and e.canLoan == true
	local gate = levelGate(player, e, loan)
	if gate then
		return gate
	end
	local colorId = validColor(GS, p.color)
	-- 보상판매: sell the old car first (frees the slot, money to the bank), after checking the new contract fits
	local trade = nil
	local tradeId = if p.trade ~= nil then U.str(p.trade, 16, "^[%w_%-]+$") else nil
	if p.trade ~= nil and not tradeId then
		return fail("bad", "잘못된 요청이에요")
	end
	if tradeId then
		if not C.TRADEIN.enabled then
			return fail("bad", "보상판매를 지금은 받지 않아요")
		end
		local st = Bridge.status(player)
		if not st then
			return fail("loading", "차 정보를 불러오는 중이에요")
		end
		local car = nil
		for _, c in carsOf(st) do
			if type(c) == "table" and c.id == tradeId then
				car = c
			end
		end
		if not car or car.rental then
			return fail("bad", "보상판매할 차를 다시 골라 주세요")
		end
		local remaining = if type(car.loan) == "table" then (car.loan.remaining or 0) else 0
		local value = tonumber(car.sell) or 0
		local payout = value - remaining
		if payout < 0 then
			return fail("loan", string.format("남은 할부(%s)가 매입가(%s)보다 많아서 보상판매할 수 없어요", U.won(remaining), U.won(value)))
		end
		local due = if loan and e.loan then e.loan.down else e.price
		local bank, cash = st.bank or 0, st.cash or 0
		if bank + payout < due and cash < due then
			return fail("insufficient", string.format("보상판매 후에도 %s이 부족해요 (매각 %s 포함 통장 %s)", U.won(due), U.won(payout), U.won(bank + payout)))
		end
		if e.model then
			for _, c in carsOf(st) do
				if type(c) == "table" and c.model == e.model and c.id ~= tradeId and not c.rental then
					return fail("owned", "이미 가진 차예요 · '내 차'에서 부를 수 있어요")
				end
			end
		end
		if loan then
			for _, c in carsOf(st) do
				if type(c) == "table" and c.id ~= tradeId and type(c.loan) == "table" and (c.loan.missed or 0) > 0 then
					return fail("loanMissed", "밀린 할부가 있어서 새 할부를 할 수 없어요")
				end
			end
		end
		local sold = Bridge.request(player, "sell", { id = tradeId })
		if not sold.ok then
			return sold
		end
		local bonus = U.round100((tonumber(sold.value) or value) * C.TRADEIN.bonusRate)
		local bonusPaid = bonus > 0 and Bridge.credit(player, bonus, C.CASHBACK_LABELS.trade)
		trade = { name = car.label or "내 차", value = sold.value or value, payout = sold.payout or payout, bonus = if bonusPaid then bonus else 0 }
	end
	local beforeBank, beforeCash = Bridge.balance(player)
	local payload: { [string]: any } = if e.model then { model = e.model, color = colorId, loan = loan } else { kind = e.kind, grade = e.grade, color = colorId, loan = loan }
	local r = Bridge.request(player, "buy", payload)
	if not r.ok then
		if trade then
			local out = table.clone(r)
			out.message = string.format("보상판매는 완료됐어요 (+%s) · %s", U.won(trade.payout + trade.bonus), tostring(r.message or "계약은 진행되지 않았어요"))
			out.trade = trade
			out.sold = true
			return out
		end
		return r
	end
	-- benefits: only up to what really left the accounts (admin free cars pay nothing back)
	local afterBank, afterCash = Bridge.balance(player)
	local paid = math.max(0, (beforeBank + beforeCash) - (afterBank + afterCash))
	local receipt = type(r.receipt) == "table" and r.receipt or {}
	if type(receipt.paid) == "number" then
		paid = math.min(paid, receipt.paid)
	end
	local level = Bridge.level(player)
	local ben = Catalog.benefits(e, { usedRate = if C.USED_DISCOUNT_CASHBACK then S.usedRate(level) else 0, special = specials[e.id] == true })
	local lines = {}
	local total = 0
	local budget = paid
	for _, l in ben.lines do
		local amt = math.min(l.amount or 0, budget)
		if amt > 0 then
			local label = pctLabel(if l.key == "special" then C.CASHBACK_LABELS.special else C.CASHBACK_LABELS.used, l.rate)
			if Bridge.credit(player, amt, label) then
				table.insert(lines, { key = l.key, label = l.label, rate = l.rate, amount = amt })
				total += amt
				budget -= amt
			end
		end
	end
	Store.bought(player, total)
	local out = table.clone(r)
	out.entry = e.id
	out.cashback = total
	out.cashbackLines = lines
	out.trade = trade
	nonces[player] = nonces[player] or {}
	local map = nonces[player]
	map[nonce] = { t = os.clock(), res = out }
	for k, v in map do
		if os.clock() - v.t > 180 then
			map[k] = nil
		end
	end
	return out
end

function OPS.sell(player, p)
	local id = U.str(p.id, 16, "^[%w_%-]+$")
	if not id then
		return fail("bad", "잘못된 요청이에요")
	end
	if not nearDealer(player) then
		return fail("far", "매각은 광안 오토 매장에서 할 수 있어요")
	end
	return Bridge.request(player, "sell", { id = id })
end

function OPS.testdrive(player, p)
	local GS = S.GS(0)
	if not GS then
		return fail("offline", "정비소 전산이 아직 준비되지 않았어요")
	end
	local _, byId = entries()
	local e, bad = resolve(p.entry, byId)
	if not e then
		return bad :: any
	end
	if e.grade == "rent" then
		return fail("bad", "렌트 차량은 시승 없이 바로 빌릴 수 있어요")
	end
	if not nearDealer(player) then
		return fail("far", "시승은 광안 오토 매장에서 신청할 수 있어요")
	end
	local why = Bridge.blocked(player)
	if why then
		return fail(why, BLOCK_MSG[why])
	end
	if TestDrive.active(player) then
		return fail("busy", "이미 시승 중이에요")
	end
	local st = Bridge.status(player)
	if st and st.testing == true then
		return fail("busy", "이미 시승 중이에요")
	end
	local colorId = validColor(GS, p.color)
	if e.model and avail()[e.model] then
		return TestDrive.start(player, e, colorId)
	end
	local r = Bridge.request(player, "testdrive", { kind = e.kind, color = colorId })
	if not r.ok then
		return r
	end
	local seconds = tonumber(r.seconds) or 60
	local car = r.car
	if typeof(car) == "Instance" and car:IsA("Model") then
		TestDrive.watch(player, car, e.id, e.name, "garage", seconds)
	else
		Store.tested(player, e.id)
	end
	return { ok = true, code = "ok", message = "시승 시작", mode = "garage", seconds = seconds, entry = e.id }
end

function OPS.endtest(player, _p)
	if TestDrive.active(player) == "dealer" then
		TestDrive.stop(player, "player")
		return { ok = true, code = "ok" }
	end
	return Bridge.request(player, "endtest", {})
end

function OPS.rent(player, _p)
	if not nearDealer(player) then
		return fail("far", "렌트는 광안 오토 매장에서 할 수 있어요")
	end
	local why = Bridge.blocked(player)
	if why == "cuffed" or why == "dead" then
		return fail(why, BLOCK_MSG[why])
	end
	return Bridge.request(player, "rent", {})
end

function OPS.deliver(player, p)
	local id = U.str(p.id, 16, "^[%w_%-]+$")
	if not id then
		return fail("bad", "잘못된 요청이에요")
	end
	if TestDrive.active(player) then
		return fail("test", "시승 중에는 차를 부를 수 없어요")
	end
	local r = Bridge.request(player, "call", { id = id })
	if not r.ok then
		return r
	end
	local seated = false
	local car = r.car
	if typeof(car) == "Instance" and car:IsA("Model") and Bridge.blocked(player) == nil then
		local ok = Bridge.vehicles("seat", player, car)
		seated = ok == true
	end
	return { ok = true, code = "ok", meters = r.meters, seated = seated, label = r.label }
end

function OPS.wish(player, p)
	local p2 = Catalog.parse(p.entry)
	if not p2 then
		return fail("bad", "없는 차예요")
	end
	local list = Store.setWish(player, p.entry, U.bool(p.on))
	return { ok = true, code = "ok", wish = table.clone(list) }
end

function OPS.waypoint(player, _p)
	return Bridge.request(player, "waypoint", {})
end

-------------------------------------------------------------------------------------------------
-- entry point
-------------------------------------------------------------------------------------------------
function Service.handle(player: Player, op: any, payload: any): { [string]: any }
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return fail("bad", "잘못된 요청이에요")
	end
	if type(op) ~= "string" or #op > 16 or not OPS[op] then
		return fail("bad", "잘못된 요청이에요")
	end
	local p = U.payload(payload, 8)
	if not p then
		return fail("bad", "잘못된 요청이에요")
	end
	if not bucket:take(player) then
		return fail("rate", "잠시 후 다시 시도해 주세요")
	end
	if not cools:ready(player, op, C.COOLDOWN[op] or 0.5) then
		return fail("rate", "잠시 후 다시 시도해 주세요")
	end
	if not Store.ready(player) and op ~= "catalog" then
		return fail("loading", "고객 정보를 불러오는 중이에요")
	end
	if MUTATING[op] then
		if busy[player] then
			return fail("busy", "처리 중이에요")
		end
		busy[player] = true
	end
	local ok, res = pcall(OPS[op], player, p)
	if MUTATING[op] then
		busy[player] = nil
	end
	if not ok then
		warn(string.format("[GwangalliCarDealer] %s from %s failed: %s", op, player.Name, tostring(res)))
		return fail("error", "처리하지 못했어요 · 잠시 후 다시 시도해 주세요")
	end
	if type(res) ~= "table" then
		return fail("error", "처리하지 못했어요")
	end
	return res
end

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
	nonces[player] = nil
	if bucket then
		bucket:drop(player)
	end
	if cools then
		cools:drop(player)
	end
end)

return Service
