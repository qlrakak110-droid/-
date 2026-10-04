-- GwangalliGameplay/Bank: money between players and at the bank (owner: money;
-- docs/features_contract.md §3, data + pure rules in GwangalliGameplayShared "Bank" section).
--   * 송금 (계좌이체, bank -> bank) to a player in this server: min / max per transfer, 1일 이체한도,
--     한도제한계좌 for brand-new accounts, fee 0, memo (preset id or text-filtered free text), the
--     receiver gets a toast + a "BNK부산은행 입출금 알림" message + a BankEvent; both statements get an
--     entry with the same ref. Irreversible (no cancel), said clearly on the client.
--   * 송금 요청: ask a player for money; the payer answers with 송금 (exact amount) or 거절.
--   * 현금 주기: hand cash to a player standing next to you; they accept or decline (20 s).
--   * ATM / 은행 창구: withdraw / deposit with server-side fees by machine kind and game time, note units,
--     per-operation and daily limits, distance checks. ATMs are parts tagged GwangalliATM plus the map's
--     parts named "ATM" / "PostATM" (discovered at start); the server adds the ProximityPrompts.
--
-- SECURITY: every amount is decided / checked here (integers only; NaN, inf, negatives, fractions and
-- strings are refused), per-player token bucket + per-op cooldowns, one mutating op in flight per player,
-- request ids (rid) make a repeated request (double tap, replay) return the first result instead of
-- running twice, every balance change goes through G.ledger with no yield between the checks and the
-- writes (re-checked after the only yield: the memo text filter), the payer's profile is saved first
-- (a crash can lose a credit but never duplicate money), no transfers between a saved and a memory-only
-- profile, audit records (ring buffer + DataStore "GwangalliBankAudit_v1" when available).
--
-- Unit tests inject everything Roblox-specific through ctx.bankEnv (see the scratch tests); in the game
-- the environment below is built from the real services.

local Bank = {}

local G: any
local Util: any
local Profiles: any
local ctx: any
local E: any = nil -- environment (services / clock / filter / persistence)

local AUDIT_STORE = "GwangalliBankAudit_v1"
local AUDIT_RING = 500
local RID_TTL = 120

type Req = { id: string, fromId: number, toId: number, fromName: string, toName: string, amount: number, memo: string?, t: number, exp: number }
type Offer = { id: string, fromId: number, toId: number, fromName: string, toName: string, amount: number, t: number, exp: number }
type Atm = { id: string, part: any, kind: string, name: string, prompt: any? }

local inflight: { [any]: boolean } = {}
local rids: { [any]: { [string]: { t: number, res: any } } } = {}
local buckets: { [any]: { tokens: number, t: number } } = {}
local cooldowns: { [any]: { [string]: number } } = {}
local lastRequestTo: { [any]: { [number]: number } } = {}
local blocks: { [any]: { [number]: boolean } } = {}
local requests: { [string]: Req } = {}
local offers: { [string]: Offer } = {}
local atms: { [string]: Atm } = {}
local atmOfPart: { [any]: string } = {}
local atmCount = 0
local auditRing: { any } = {}
local auditQueue: { any } = {}
local refSeq = 0
local remotes: { request: any?, event: any? } = {}

-------------------------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------------------------
local function won(n: number): string
	return G.format.won(n)
end

local function res(ok: boolean, code: string, extra: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = { ok = ok, code = code, message = G.bankMessage(code) }
	if extra then
		for k, v in extra do
			out[k] = v
		end
	end
	return out
end

local function fail(code: string, extra: { [string]: any }?): { [string]: any }
	return res(false, code, extra)
end

local function okr(extra: { [string]: any }?): { [string]: any }
	return res(true, "ok", extra)
end

local function nameOf(p: any): string
	local n = p.DisplayName
	if type(n) ~= "string" or n == "" then
		n = p.Name
	end
	return G.clipText(tostring(n), 40)
end

local function online(p: any): boolean
	return p ~= nil and p.Parent == E.Players
end

local function newRef(): string
	refSeq += 1
	local g = tostring(E.guid())
	g = string.gsub(g, "[^%w]", "")
	return string.sub(g, 1, 14) .. string.format("%x", refSeq % 4096)
end

local function cleanId(v: any): string?
	if type(v) ~= "string" or #v == 0 or #v > 40 or not string.match(v, "^[%w%-_]+$") then
		return nil
	end
	return v
end

local function bucket(player: any): boolean
	local now = E.tick()
	local b = buckets[player]
	if not b then
		b = { tokens = 8, t = now }
		buckets[player] = b
	end
	b.tokens = math.min(8, b.tokens + (now - b.t) * 3)
	b.t = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function cooldown(player: any, key: string, interval: number): boolean
	if interval <= 0 then
		return true
	end
	local now = E.tick()
	local m = cooldowns[player]
	if not m then
		m = {}
		cooldowns[player] = m
	end
	local last = m[key]
	if last and now - last < interval then
		return false
	end
	m[key] = now
	return true
end

local function ridGet(player: any, rid: string): any?
	local m = rids[player]
	local e = m and m[rid]
	if e and E.tick() - e.t < RID_TTL then
		return e.res
	end
	return nil
end

local function ridPut(player: any, rid: string, r: any)
	local m = rids[player]
	if not m then
		m = {}
		rids[player] = m
	end
	local now = E.tick()
	m[rid] = { t = now, res = r }
	local n = 0
	for k, e in m do
		n += 1
		if now - e.t >= RID_TTL then
			m[k] = nil
		end
	end
	if n > 64 then
		-- keep the table small: drop the oldest half
		local list = {}
		for k, e in m do
			table.insert(list, { k = k, t = e.t })
		end
		table.sort(list, function(a, b)
			return a.t < b.t
		end)
		for i = 1, math.floor(#list / 2) do
			m[list[i].k] = nil
		end
	end
end

local function touch(player: any, ...: string)
	ctx.changed(player, ...)
	local d = Profiles.get(player)
	if d and online(player) then
		pcall(function()
			player:SetAttribute(G.Attr.Money, d.cash)
			player:SetAttribute(G.Attr.Bank, d.bank)
		end)
	end
end

local function fire(player: any, payload: any)
	if online(player) then
		pcall(E.fire, player, payload)
	end
end

local function notify(player: any, kind: string, title: string, body: string?)
	if online(player) then
		pcall(ctx.notify, player, kind, title, body or "")
	end
end

-- "BNK부산은행 입출금 알림" message (the Messages app thread "bnk").
local function pushAlert(player: any, text: string, unread: boolean)
	local d = Profiles.get(player)
	if not d or type(d.messages) ~= "table" or type(d.messages.threads) ~= "table" then
		return
	end
	local t = d.messages.threads.bnk
	if not t then
		t = { list = {}, unread = 0 }
		d.messages.threads.bnk = t
	end
	local clock = 12
	pcall(function()
		clock = ctx.env().clock
	end)
	table.insert(t.list, { from = "them", text = G.clipText(text, 400), t = E.now(), clock = clock })
	while #t.list > (Profiles.MAX_THREAD or 30) do
		table.remove(t.list, 1)
	end
	if unread then
		t.unread = math.min(99, (t.unread or 0) + 1)
	end
	ctx.changed(player, "messages")
end

local function audit(rec: { [string]: any })
	table.insert(auditRing, rec)
	while #auditRing > AUDIT_RING do
		table.remove(auditRing, 1)
	end
	if E.auditWrite then
		table.insert(auditQueue, rec)
		while #auditQueue > 300 do
			table.remove(auditQueue, 1)
			Util.warnOnce("bankAuditQueue", "[GwangalliGameplay] bank audit queue full; oldest records kept in memory only")
		end
	end
end

local function playSeconds(player: any, d: any): number
	local ok, s = pcall(E.playSeconds, player, d)
	return if ok and G.isFiniteNumber(s) then s else 0
end

local function limitOf(player: any, d: any): (number, boolean)
	return G.bankDailyLimit(playSeconds(player, d))
end

local function dist(a: any, b: any): number
	if a == nil or b == nil then
		return math.huge
	end
	local ok, m = pcall(function()
		return (a - b).Magnitude
	end)
	return if ok and G.isFiniteNumber(m) then m else math.huge
end

local function isBlocked(target: any, fromId: number): boolean
	local b = blocks[target]
	return b ~= nil and b[fromId] == true
end

-- Resolves a recipient UserId from an untrusted value: target, or nil + code.
local function resolveTarget(player: any, to: any): (any?, string?)
	local id = G.bankInt(to, 1, 1e15)
	if not id then
		return nil, "bad"
	end
	if id == player.UserId then
		return nil, "self"
	end
	local target = E.Players:GetPlayerByUserId(id)
	if not target or not online(target) then
		return nil, "offline"
	end
	if not Profiles.get(target) then
		return nil, "loading"
	end
	if isBlocked(target, player.UserId) then
		return nil, "blocked"
	end
	return target, nil
end

-- A saved profile and a memory-only one never exchange money (the memory-only one could be re-made).
local function persistCode(a: any, b: any?): string?
	local ok, enabled = pcall(E.storeEnabled)
	if not ok or not enabled then
		return nil -- the whole server runs without a DataStore: everything is memory only
	end
	if not E.persistent(a) or (b ~= nil and not E.persistent(b)) then
		return "nosave"
	end
	return nil
end

local function memoOf(player: any, target: any?, p: any): (string?, boolean)
	if p.preset ~= nil then
		local id = cleanId(p.preset)
		local text = id and G.BANK_PRESETS[id]
		if text then
			return text, false
		end
	end
	if p.memo == nil then
		return nil, false
	end
	local clean = G.bankCleanMemo(p.memo)
	if not clean then
		return nil, false
	end
	local ok, filtered = pcall(E.filter, clean, player.UserId, if target then target.UserId else nil)
	if ok and type(filtered) == "string" and filtered ~= "" then
		return G.clipText(filtered, 80), false
	end
	return nil, true -- the filter failed: the memo is dropped (never shown unfiltered)
end

local function addRecent(b: any, userId: number, name: string, now: number, amount: number)
	for i = #b.recent, 1, -1 do
		if b.recent[i].u == userId then
			table.remove(b.recent, i)
		end
	end
	table.insert(b.recent, 1, { u = userId, n = name, t = now, a = amount })
	while #b.recent > G.BANK.recentMax do
		table.remove(b.recent)
	end
end

-- Checks a transfer / hand-over of `amount` from `player`'s `account` to `target` (no yield).
local function checkSend(player: any, target: any, amount: number, account: string): string?
	local d, dt = Profiles.get(player), Profiles.get(target)
	if not d then
		return "loading"
	end
	if not dt then
		return "offline"
	end
	local b = G.bankingOf(d, E.now())
	local limit, limited = limitOf(player, d)
	if b.sent + amount > limit then
		return if limited then "limited" else "daily"
	end
	if (d[account] or 0) < amount then
		return if account == "cash" then "cash" else "insufficient"
	end
	if (dt[account] or 0) + amount > G.MAX_MONEY then
		return "full"
	end
	return nil
end

local function reqView(r: Req, now: number): any
	return { id = r.id, fromId = r.fromId, fromName = r.fromName, toId = r.toId, toName = r.toName, amount = r.amount, memo = r.memo, expiresIn = math.max(0, r.exp - now), t = r.t }
end

local function offerView(o: Offer, now: number): any
	return { id = o.id, fromId = o.fromId, fromName = o.fromName, toId = o.toId, toName = o.toName, amount = o.amount, expiresIn = math.max(0, o.exp - now) }
end

local function summaryOf(player: any): any
	local d = Profiles.get(player)
	local now = E.now()
	local b = G.bankingOf(d, now)
	local limit, limited = limitOf(player, d)
	local incoming = 0
	for _, r in requests do
		if r.toId == player.UserId then
			incoming += 1
		end
	end
	return {
		cash = d.cash,
		bank = d.bank,
		sentToday = b.sent,
		dailyLimit = limit,
		remaining = math.max(0, limit - b.sent),
		limited = limited,
		min = G.BANK.minTransfer,
		max = G.BANK.maxTransfer,
		fee = G.BANK.fee,
		giveMin = G.BANK.giveMin,
		giveMax = G.BANK.giveMax,
		atmLeft = math.max(0, G.BANK.atmDailyWithdraw - b.atmOut),
		pendingIn = incoming,
		bankName = G.BANK.bankName,
		account = G.BANK.account,
		holder = nameOf(player),
	}
end

-------------------------------------------------------------------------------------------------
-- 송금
-------------------------------------------------------------------------------------------------
-- The one place a P2P transfer is applied. No yields. Returns a result table.
local function applyTransfer(player: any, target: any, amount: number, memo: string?, via: string?): { [string]: any }
	local code = checkSend(player, target, amount, "bank")
	if code then
		return fail(code)
	end
	local d, dt = Profiles.get(player), Profiles.get(target)
	local now = E.now()
	local ref = newRef()
	local toName, fromName = nameOf(target), nameOf(player)
	local memoPart = if memo then " · " .. memo else ""
	local okA, whyA = G.ledger(d, "bank", -amount, "송금 · " .. toName .. memoPart, now, { kind = "p2p_out", peer = toName, peerId = target.UserId, memo = memo, ref = ref })
	if not okA then
		return fail(if whyA == "insufficient" then "insufficient" else "bad")
	end
	local okB, whyB = G.ledger(dt, "bank", amount, "입금 · " .. fromName .. memoPart, now, { kind = "p2p_in", peer = fromName, peerId = player.UserId, memo = memo, ref = ref })
	if not okB then
		-- cannot normally happen (checked above): put the money back on the payer
		G.ledger(d, "bank", amount, "송금 취소 · " .. toName, now, { kind = "refund", peer = toName, peerId = target.UserId, ref = ref })
		touch(player, "bank")
		return fail(if whyB == "full" then "full" else "bad")
	end
	local b = G.bankingOf(d, now)
	b.sent += amount
	b.count += 1
	addRecent(b, target.UserId, toName, now, amount)
	-- persistence: the payer first (a crash in between loses the credit, never duplicates money)
	pcall(E.saveSoon, player)
	pcall(E.saveSoon, target)
	touch(player, "bank")
	touch(target, "bank")
	audit({ ref = ref, t = now, kind = "p2p", from = player.UserId, to = target.UserId, amount = amount, memo = memo, via = via })
	local limit = limitOf(player, d)
	notify(target, "money", string.format("%s님이 %s을 보냈어요", fromName, won(amount)), (memo or "계좌 입금") .. " · 잔액 " .. won(dt.bank))
	pushAlert(target, string.format("[입금] %s님이 %s을 보냈어요.%s\n통장 잔액 %s", fromName, won(amount), if memo then "\n메모: " .. memo else "", won(dt.bank)), true)
	pushAlert(player, string.format("[출금] %s님에게 %s을 보냈어요.%s\n통장 잔액 %s", toName, won(amount), if memo then "\n메모: " .. memo else "", won(d.bank)), false)
	fire(target, { kind = "received", ref = ref, fromId = player.UserId, fromName = fromName, amount = amount, memo = memo, bank = dt.bank, t = now })
	fire(player, { kind = "sent", ref = ref, toId = target.UserId, toName = toName, amount = amount, memo = memo, bank = d.bank, t = now })
	return okr({ ref = ref, amount = amount, toId = target.UserId, toName = toName, bank = d.bank, cash = d.cash, sentToday = b.sent, remaining = math.max(0, limit - b.sent), memo = memo, fee = 0, t = now })
end

local function opTransfer(player: any, p: any): any
	local amount = G.bankInt(p.amount, 1, math.huge) -- any finite whole number; the range is checked below
	if not amount then
		return fail("amount")
	end
	if amount < G.BANK.minTransfer then
		return fail("min")
	end
	if amount > G.BANK.maxTransfer then
		return fail("max")
	end
	local target, code = resolveTarget(player, p.to)
	if not target then
		return fail(code or "bad")
	end
	code = persistCode(player, target)
	if code then
		return fail(code)
	end
	local req: Req? = nil
	if p.requestId ~= nil then
		local id = cleanId(p.requestId)
		local r = id and requests[id]
		if not r or r.toId ~= player.UserId or r.fromId ~= target.UserId then
			return fail("expired")
		end
		if r.amount ~= amount then
			return fail("mismatch")
		end
		req = r
	end
	code = checkSend(player, target, amount, "bank")
	if code then
		return fail(code)
	end
	local memo, dropped = memoOf(player, target, p) -- may yield (text filter)
	if not memo and req then
		memo = req.memo
	end
	-- re-check after the yield
	target, code = resolveTarget(player, p.to)
	if not target then
		return fail(code or "offline")
	end
	if req and requests[req.id] ~= req then
		return fail("expired")
	end
	local r = applyTransfer(player, target, amount, memo, if req then "request" else "transfer")
	r.memoDropped = dropped or nil
	if r.ok and req then
		requests[req.id] = nil
		local requester = E.Players:GetPlayerByUserId(req.fromId)
		if requester then
			fire(requester, { kind = "requestAnswered", requestId = req.id, paid = true, amount = amount, byId = player.UserId, byName = nameOf(player) })
		end
	end
	return r
end

local function opQuote(player: any, p: any): any
	local amount = G.bankInt(p.amount, 1, math.huge) -- any finite whole number; the range is checked below
	if not amount then
		return fail("amount")
	end
	if amount < G.BANK.minTransfer then
		return fail("min")
	end
	if amount > G.BANK.maxTransfer then
		return fail("max")
	end
	local target, code = resolveTarget(player, p.to)
	if not target then
		return fail(code or "bad")
	end
	code = persistCode(player, target) or checkSend(player, target, amount, "bank")
	if code then
		return fail(code)
	end
	local d = Profiles.get(player)
	local s = summaryOf(player)
	return okr({ toId = target.UserId, toName = nameOf(target), toUser = target.Name, amount = amount, fee = 0, after = d.bank - amount, remaining = s.remaining - amount })
end

-------------------------------------------------------------------------------------------------
-- 송금 요청
-------------------------------------------------------------------------------------------------
local function countReq(pred: (Req) -> boolean): number
	local n = 0
	for _, r in requests do
		if pred(r) then
			n += 1
		end
	end
	return n
end

local function opRequest(player: any, p: any): any
	local amount = G.bankInt(p.amount, 1, math.huge) -- any finite whole number; the range is checked below
	if not amount then
		return fail("amount")
	end
	if amount < G.BANK.minTransfer then
		return fail("min")
	end
	if amount > G.BANK.maxTransfer then
		return fail("max")
	end
	local target, code = resolveTarget(player, p.to)
	if not target then
		return fail(code or "bad")
	end
	local me, them = player.UserId, target.UserId
	if countReq(function(r)
		return r.fromId == me and r.toId == them
	end) > 0 then
		return fail("pending")
	end
	if countReq(function(r)
		return r.fromId == me
	end) >= G.BANK.maxPendingOut then
		return fail("tooMany")
	end
	if countReq(function(r)
		return r.toId == them
	end) >= G.BANK.maxPendingIn then
		return fail("tooMany")
	end
	local lr = lastRequestTo[player]
	if lr and lr[them] and E.tick() - lr[them] < G.BANK.requestTargetCooldown then
		return fail("rate")
	end
	local memo, dropped = memoOf(player, target, p) -- may yield
	target, code = resolveTarget(player, p.to)
	if not target then
		return fail(code or "offline")
	end
	if countReq(function(r)
		return r.fromId == me and r.toId == them
	end) > 0 then
		return fail("pending")
	end
	if not lr then
		lr = {}
		lastRequestTo[player] = lr
	end
	lr[them] = E.tick()
	local now = E.now()
	local r: Req = { id = newRef(), fromId = me, toId = them, fromName = nameOf(player), toName = nameOf(target), amount = amount, memo = memo, t = now, exp = now + G.BANK.requestTTL }
	requests[r.id] = r
	audit({ ref = r.id, t = now, kind = "request", from = me, to = them, amount = amount, memo = memo })
	fire(target, { kind = "request", request = reqView(r, now) })
	pushAlert(target, string.format("[송금 요청] %s님이 %s을 요청했어요.%s", r.fromName, won(amount), if memo then "\n메모: " .. memo else ""), true)
	return okr({ requestId = r.id, expiresIn = G.BANK.requestTTL, toName = r.toName, amount = amount, memo = memo, memoDropped = dropped or nil })
end

local function opRequests(player: any, _p: any): any
	local now = E.now()
	local incoming, outgoing = {}, {}
	for _, r in requests do
		if r.toId == player.UserId then
			table.insert(incoming, reqView(r, now))
		elseif r.fromId == player.UserId then
			table.insert(outgoing, reqView(r, now))
		end
	end
	table.sort(incoming, function(a, b)
		return a.t > b.t
	end)
	table.sort(outgoing, function(a, b)
		return a.t > b.t
	end)
	return okr({ incoming = incoming, outgoing = outgoing })
end

-- Decline (payer) or cancel (requester). Paying is a transfer with requestId.
local function opRequestAnswer(player: any, p: any): any
	local id = cleanId(p.requestId)
	local r = id and requests[id]
	if not r then
		return fail("expired")
	end
	if p.accept == true then
		return fail("bad")
	end
	if r.toId == player.UserId then
		requests[r.id] = nil
		local requester = E.Players:GetPlayerByUserId(r.fromId)
		if requester then
			fire(requester, { kind = "requestAnswered", requestId = r.id, declined = true, amount = r.amount, byId = player.UserId, byName = nameOf(player) })
		end
		return okr({ declined = true })
	elseif r.fromId == player.UserId then
		requests[r.id] = nil
		local payer = E.Players:GetPlayerByUserId(r.toId)
		if payer then
			fire(payer, { kind = "requestAnswered", requestId = r.id, cancelled = true, amount = r.amount, byId = player.UserId, byName = nameOf(player) })
		end
		return okr({ cancelled = true })
	end
	return fail("expired")
end

-------------------------------------------------------------------------------------------------
-- 현금 주기 (in person)
-------------------------------------------------------------------------------------------------
local function opCashOffer(player: any, p: any): any
	local amount = G.bankInt(p.amount, 1, math.huge) -- any finite whole number; the range is checked below
	if not amount then
		return fail("amount")
	end
	if amount < G.BANK.giveMin then
		return fail("min")
	end
	if amount > G.BANK.giveMax then
		return fail("max")
	end
	local target, code = resolveTarget(player, p.to)
	if not target then
		return fail(code or "bad")
	end
	code = persistCode(player, target) or checkSend(player, target, amount, "cash")
	if code then
		return fail(code)
	end
	if dist(E.position(player), E.position(target)) > G.BANK.giveRadius then
		return fail("far")
	end
	for _, o in offers do
		if o.fromId == player.UserId then
			return fail("pending")
		end
	end
	local incoming = 0
	for _, o in offers do
		if o.toId == target.UserId then
			incoming += 1
		end
	end
	if incoming >= G.BANK.maxOffersIn then
		return fail("tooMany")
	end
	local now = E.now()
	local o: Offer = { id = newRef(), fromId = player.UserId, toId = target.UserId, fromName = nameOf(player), toName = nameOf(target), amount = amount, t = now, exp = now + G.BANK.offerTTL }
	offers[o.id] = o
	fire(target, { kind = "cashOffer", offer = offerView(o, now) })
	return okr({ offerId = o.id, expiresIn = G.BANK.offerTTL, toName = o.toName, toId = o.toId, amount = amount })
end

local function opCashAnswer(player: any, p: any): any
	local id = cleanId(p.offerId)
	local o = id and offers[id]
	if not o or o.toId ~= player.UserId then
		return fail("expired")
	end
	offers[o.id] = nil -- consumed now: a second answer finds nothing
	local giver = E.Players:GetPlayerByUserId(o.fromId)
	if p.accept ~= true then
		if giver then
			fire(giver, { kind = "cashResolved", offerId = o.id, accepted = false, declined = true, amount = o.amount, toId = o.toId, toName = o.toName })
		end
		return okr({ accepted = false })
	end
	local function refuse(code: string): any
		if giver then
			fire(giver, { kind = "cashResolved", offerId = o.id, accepted = false, failed = code, amount = o.amount, toId = o.toId, toName = o.toName })
		end
		return fail(code)
	end
	if not giver or not online(giver) or not Profiles.get(giver) then
		return fail("offline")
	end
	local code = persistCode(giver, player) or checkSend(giver, player, o.amount, "cash")
	if code then
		return refuse(code)
	end
	if dist(E.position(giver), E.position(player)) > G.BANK.giveRadius * G.BANK.giveSlack then
		return refuse("far")
	end
	local dg, dr = Profiles.get(giver), Profiles.get(player)
	local now = E.now()
	local ref = newRef()
	local okA = G.ledger(dg, "cash", -o.amount, "현금 전달 · " .. o.toName, now, { kind = "cash_out", peer = o.toName, peerId = o.toId, ref = ref })
	if not okA then
		return refuse("cash")
	end
	local okB = G.ledger(dr, "cash", o.amount, "현금 받음 · " .. o.fromName, now, { kind = "cash_in", peer = o.fromName, peerId = o.fromId, ref = ref })
	if not okB then
		G.ledger(dg, "cash", o.amount, "현금 전달 취소 · " .. o.toName, now, { kind = "refund", peer = o.toName, peerId = o.toId, ref = ref })
		touch(giver, "cash")
		return refuse("full")
	end
	local b = G.bankingOf(dg, now)
	b.sent += o.amount
	b.count += 1
	addRecent(b, o.toId, o.toName, now, o.amount)
	pcall(E.saveSoon, giver)
	pcall(E.saveSoon, player)
	touch(giver, "cash")
	touch(player, "cash")
	audit({ ref = ref, t = now, kind = "cash", from = o.fromId, to = o.toId, amount = o.amount })
	fire(giver, { kind = "cashResolved", offerId = o.id, accepted = true, amount = o.amount, fromId = o.fromId, fromName = o.fromName, toId = o.toId, toName = o.toName, cash = dg.cash, ref = ref })
	return okr({ accepted = true, amount = o.amount, fromId = o.fromId, fromName = o.fromName, toId = o.toId, cash = dr.cash, ref = ref })
end

local function opCashCancel(player: any, p: any): any
	local id = cleanId(p.offerId)
	local o = id and offers[id]
	if not o or o.fromId ~= player.UserId then
		return fail("expired")
	end
	offers[o.id] = nil
	local target = E.Players:GetPlayerByUserId(o.toId)
	if target then
		fire(target, { kind = "cashResolved", offerId = o.id, cancelled = true, amount = o.amount, fromId = o.fromId, fromName = o.fromName })
	end
	return okr({ cancelled = true })
end

-- Open cash offers of this player (restores the banners after a respawn / UI reload).
local function opOffers(player: any, _p: any): any
	local now = E.now()
	local incoming, outgoing = {}, {}
	for _, o in offers do
		if o.toId == player.UserId then
			table.insert(incoming, offerView(o, now))
		elseif o.fromId == player.UserId then
			table.insert(outgoing, offerView(o, now))
		end
	end
	return okr({ incoming = incoming, outgoing = outgoing })
end

-------------------------------------------------------------------------------------------------
-- ATM / 은행 창구
-------------------------------------------------------------------------------------------------
local function atmPosition(a: Atm): any
	local ok, pos = pcall(function()
		local part = a.part
		if part:IsA("Model") then
			return part:GetPivot().Position
		end
		return part.Position
	end)
	return if ok then pos else nil
end

local function atmInfo(player: any, a: Atm): any
	local d = Profiles.get(player)
	local k = G.ATM_KINDS[a.kind]
	local clock = E.clock()
	local b = G.bankingOf(d, E.now())
	return {
		id = a.id,
		kind = a.kind,
		name = a.name,
		short = k.short,
		own = k.own == true,
		counter = k.counter == true,
		open = (not k.counter) or G.counterOpen(clock),
		fee = G.atmFee(a.kind, clock),
		feeDay = k.fee[1],
		feeNight = k.fee[2],
		night = G.atmNight(clock),
		clock = clock,
		withdrawUnit = k.withdrawUnit,
		depositUnit = k.depositUnit,
		maxWithdraw = k.maxWithdraw,
		maxDeposit = k.maxDeposit,
		min = k.min,
		cash = d.cash,
		bank = d.bank,
		atmLeft = math.max(0, G.BANK.atmDailyWithdraw - b.atmOut),
		holder = nameOf(player),
		account = G.BANK.account,
		pos = atmPosition(a), -- the client closes the screen when the player walks away
		reach = G.BANK.atmReach,
	}
end

local function nearAtm(player: any, a: Atm): boolean
	return dist(E.position(player), atmPosition(a)) <= G.BANK.atmReach
end

local function opAtmOpen(player: any, p: any): any
	local id = cleanId(p.atmId)
	local a = id and atms[id]
	if not a then
		return fail("noatm")
	end
	if not nearAtm(player, a) then
		return fail("far")
	end
	return okr({ atm = atmInfo(player, a) })
end

local function opAtm(player: any, p: any): any
	local id = cleanId(p.atmId)
	local a = id and atms[id]
	if not a then
		return fail("noatm")
	end
	local direction = p.direction
	if direction ~= "withdraw" and direction ~= "deposit" then
		return fail("bad")
	end
	if not nearAtm(player, a) then
		return fail("far")
	end
	local clock = E.clock()
	local okc, code = G.atmCheck(a.kind, direction, p.amount, clock)
	if not okc then
		return fail(code or "bad")
	end
	local amount: number = p.amount
	local fee = G.atmFee(a.kind, clock)
	local d = Profiles.get(player)
	local now = E.now()
	local b = G.bankingOf(d, now)
	local k = G.ATM_KINDS[a.kind]
	local verb = if k.counter then "창구" else "ATM"
	local ref = newRef()
	if direction == "withdraw" then
		if b.atmOut + amount > G.BANK.atmDailyWithdraw and not k.counter then
			return fail("atmLimit")
		end
		if d.bank < amount + fee then
			return fail("insufficient")
		end
		if d.cash + amount > G.MAX_MONEY then
			return fail("full")
		end
		G.ledger(d, "bank", -amount, verb .. " 출금 (통장 → 현금) · " .. a.name, now, { kind = "atm_wd", place = a.name, ref = ref, fee = fee })
		if fee > 0 then
			G.ledger(d, "bank", -fee, verb .. " 수수료 · " .. a.name, now, { kind = "fee", place = a.name, ref = ref })
		end
		G.ledger(d, "cash", amount, verb .. " 출금 (통장 → 현금)", now, { kind = "atm_wd", place = a.name, ref = ref })
		if not k.counter then
			b.atmOut += amount
		end
	else
		if d.cash < amount then
			return fail("cash")
		end
		if d.bank + amount > G.MAX_MONEY then
			return fail("full")
		end
		G.ledger(d, "cash", -amount, verb .. " 입금 (현금 → 통장)", now, { kind = "atm_dep", place = a.name, ref = ref })
		G.ledger(d, "bank", amount, verb .. " 입금 (현금 → 통장) · " .. a.name, now, { kind = "atm_dep", place = a.name, ref = ref, fee = fee })
		if fee > 0 then
			G.ledger(d, "bank", -fee, verb .. " 수수료 · " .. a.name, now, { kind = "fee", place = a.name, ref = ref })
		end
	end
	touch(player, "cash", "bank")
	audit({ ref = ref, t = now, kind = "atm_" .. direction, from = player.UserId, amount = amount, fee = fee, place = a.name })
	pushAlert(player, string.format("[%s] %s %s%s\n통장 잔액 %s", if direction == "withdraw" then "출금" else "입금", a.name, won(amount), if fee > 0 then " · 수수료 " .. won(fee) else "", won(d.bank)), false)
	return okr({ direction = direction, amount = amount, fee = fee, cash = d.cash, bank = d.bank, ref = ref, atmLeft = math.max(0, G.BANK.atmDailyWithdraw - b.atmOut), t = now })
end

-------------------------------------------------------------------------------------------------
-- Queries
-------------------------------------------------------------------------------------------------
local function opSummary(player: any, _p: any): any
	return okr(summaryOf(player))
end

local function opRecipients(player: any, _p: any): any
	local list = {}
	local present: { [number]: boolean } = {}
	for _, other in E.Players:GetPlayers() do
		if other ~= player and online(other) and Profiles.get(other) then
			present[other.UserId] = true
			table.insert(list, { u = other.UserId, n = nameOf(other), un = G.clipText(tostring(other.Name), 40), blocked = blocks[player] ~= nil and blocks[player][other.UserId] == true or nil })
		end
	end
	table.sort(list, function(a, b)
		return a.n < b.n
	end)
	local d = Profiles.get(player)
	local b = G.bankingOf(d, E.now())
	local recent = {}
	for _, r in b.recent do
		table.insert(recent, { u = r.u, n = r.n, t = r.t, a = r.a, online = present[r.u] == true })
	end
	return okr({ players = list, recent = recent, me = player.UserId })
end

local function opStatement(player: any, p: any): any
	local d = Profiles.get(player)
	local account = if p.account == "cash" or p.account == "bank" then p.account else nil
	local out = {}
	for i = #d.transactions, 1, -1 do
		local tx = d.transactions[i]
		if not account or tx.account == account then
			local e: { [string]: any } = { t = tx.t, amount = tx.amount, label = tx.label, balance = tx.balance, account = tx.account }
			for k, v in G.ledgerMeta(tx) do
				e[k] = v
			end
			table.insert(out, e)
		end
	end
	return okr({ entries = out, summary = summaryOf(player) })
end

local function opBlock(player: any, p: any): any
	local id = G.bankInt(p.userId, 1, 1e15)
	if not id or id == player.UserId then
		return fail("bad")
	end
	local b = blocks[player]
	if not b then
		b = {}
		blocks[player] = b
	end
	b[id] = if p.on == false then nil else true
	if b[id] then
		-- drop what that player already sent me
		for rid, r in requests do
			if r.fromId == id and r.toId == player.UserId then
				requests[rid] = nil
			end
		end
		for oid, o in offers do
			if o.fromId == id and o.toId == player.UserId then
				offers[oid] = nil
			end
		end
	end
	return okr({ userId = id, blocked = b[id] == true })
end

-------------------------------------------------------------------------------------------------
-- Dispatcher (the RemoteFunction handler and the unit tests use this)
-------------------------------------------------------------------------------------------------
local OPS: { [string]: { fn: (any, any) -> any, cd: number, mut: boolean? } } = {
	summary = { fn = opSummary, cd = 0.25 },
	recipients = { fn = opRecipients, cd = 0.5 },
	quote = { fn = opQuote, cd = 0.2 },
	requests = { fn = opRequests, cd = 0.3 },
	offers = { fn = opOffers, cd = 0.3 },
	statement = { fn = opStatement, cd = 0.5 },
	atmOpen = { fn = opAtmOpen, cd = 0.3 },
	block = { fn = opBlock, cd = 0.5 },
	transfer = { fn = opTransfer, cd = 1.0, mut = true },
	request = { fn = opRequest, cd = 2.0, mut = true },
	requestAnswer = { fn = opRequestAnswer, cd = 0.3, mut = true },
	cashOffer = { fn = opCashOffer, cd = 1.5, mut = true },
	cashAnswer = { fn = opCashAnswer, cd = 0.3, mut = true },
	cashCancel = { fn = opCashCancel, cd = 0.3, mut = true },
	atm = { fn = opAtm, cd = 1.0, mut = true },
}
Bank.OPS = OPS

function Bank.handle(player: any, op: any, payload: any): any
	if type(op) ~= "string" then
		return fail("bad")
	end
	local spec = OPS[op]
	if not spec then
		return fail("bad")
	end
	if payload ~= nil and type(payload) ~= "table" then
		return fail("bad")
	end
	local p = payload or {}
	if not bucket(player) then
		return fail("rate")
	end
	local rid: string? = nil
	if spec.mut then
		rid = cleanId(p.rid)
		if not rid then
			return fail("bad")
		end
		local cached = ridGet(player, rid :: string)
		if cached then
			local c = table.clone(cached)
			c.dup = true
			return c
		end
		if inflight[player] then
			return fail("busy")
		end
	end
	if not cooldown(player, op, spec.cd) then
		return fail("rate")
	end
	if not Profiles.get(player) then
		return fail("loading")
	end
	if spec.mut then
		inflight[player] = true
	end
	local ok, r = pcall(spec.fn, player, p)
	if spec.mut then
		inflight[player] = nil
	end
	if not ok then
		warn(string.format("[GwangalliGameplay] bank %s from %s failed: %s", op, tostring(player.Name), tostring(r)))
		r = fail("bad")
	elseif type(r) ~= "table" then
		r = fail("bad")
	end
	if rid then
		ridPut(player, rid, r)
	end
	return r
end

-------------------------------------------------------------------------------------------------
-- Expiry, leave
-------------------------------------------------------------------------------------------------
function Bank.sweep(now: number?)
	local t = now or E.now()
	for id, r in requests do
		if t >= r.exp then
			requests[id] = nil
			for _, uid in { r.fromId, r.toId } do
				local pl = E.Players:GetPlayerByUserId(uid)
				if pl then
					fire(pl, { kind = "requestAnswered", requestId = id, expired = true, amount = r.amount })
				end
			end
		end
	end
	for id, o in offers do
		if t >= o.exp then
			offers[id] = nil
			for _, uid in { o.fromId, o.toId } do
				local pl = E.Players:GetPlayerByUserId(uid)
				if pl then
					fire(pl, { kind = "cashResolved", offerId = id, expired = true, amount = o.amount, fromName = o.fromName, toName = o.toName })
				end
			end
		end
	end
end

function Bank.onLeave(player: any)
	local uid = player.UserId
	for id, r in requests do
		if r.fromId == uid or r.toId == uid then
			requests[id] = nil
			local other = E.Players:GetPlayerByUserId(if r.fromId == uid then r.toId else r.fromId)
			if other and other ~= player then
				fire(other, { kind = "requestAnswered", requestId = id, cancelled = true, reason = "left", amount = r.amount, byName = nameOf(player) })
			end
		end
	end
	for id, o in offers do
		if o.fromId == uid or o.toId == uid then
			offers[id] = nil
			local other = E.Players:GetPlayerByUserId(if o.fromId == uid then o.toId else o.fromId)
			if other and other ~= player then
				fire(other, { kind = "cashResolved", offerId = id, cancelled = true, reason = "left", amount = o.amount, fromName = o.fromName, toName = o.toName })
			end
		end
	end
	inflight[player] = nil
	rids[player] = nil
	buckets[player] = nil
	cooldowns[player] = nil
	lastRequestTo[player] = nil
	blocks[player] = nil
end

-------------------------------------------------------------------------------------------------
-- ATM registry + prompts
-------------------------------------------------------------------------------------------------
local KIND_WORDS: { { string } } = {
	{ "BNK", "bnk" },
	{ "부산은행", "bnk" },
	{ "창구", "counter" },
	{ "GS25", "cvs" },
	{ "세븐일레븐", "cvs" },
	{ "7-ELEVEN", "cvs" },
	{ "7-Eleven", "cvs" },
	{ "이마트24", "cvs" },
	{ "emart24", "cvs" },
	{ "편의점", "cvs" },
	{ "Convenience", "cvs" },
	{ "convenience", "cvs" },
	{ "우체국", "other" },
	{ "새마을", "other" },
	{ "신한", "other" },
	{ "국민", "other" },
	{ "우리은행", "other" },
	{ "하나은행", "other" },
	{ "농협", "other" },
}
local KIND_TOKENS: { { string } } = { { "CU", "cvs" }, { "MG", "other" }, { "KB", "other" }, { "NH", "other" }, { "Post", "other" } }

-- Kind + display name of an ATM part from its own attributes or the names of its ancestors.
function Bank.classify(inst: any): (string, string)
	local attrKind = inst:GetAttribute(G.Attr.AtmKind)
	local attrName = inst:GetAttribute(G.Attr.DisplayName)
	local kind: string? = if type(attrKind) == "string" and G.ATM_KINDS[attrKind] then attrKind else nil
	local place: string? = nil
	local cur = inst.Parent
	local n = 0
	while cur and cur ~= workspace and n < 8 do
		local name = tostring(cur.Name)
		if not kind then
			for _, w in KIND_WORDS do
				if string.find(name, w[1], 1, true) then
					kind = w[2]
					place = name
					break
				end
			end
			if not kind then
				for _, w in KIND_TOKENS do
					if string.find(name, "%f[%w]" .. w[1] .. "%f[%W]") then
						kind = w[2]
						place = name
						break
					end
				end
			end
		end
		if kind then
			break
		end
		cur = cur.Parent
		n += 1
	end
	if not kind and tostring(inst.Name) == "PostATM" then
		kind = "other"
		place = "우체국"
	end
	local k = kind or "other"
	local display: string
	if type(attrName) == "string" and attrName ~= "" then
		display = attrName
	elseif place then
		local clean = string.gsub(string.gsub(place, "빌딩$", ""), "%s+$", "")
		display = G.clipText(clean, 40) .. (if k == "counter" then "" else " ATM")
	else
		display = G.ATM_KINDS[k].name
	end
	return k, G.clipText(display, 60)
end

function Bank.openAtm(player: any, id: string): any
	local a = atms[id]
	if not a then
		return fail("noatm")
	end
	if not Profiles.get(player) then
		return fail("loading")
	end
	if not cooldown(player, "prompt", 0.4) then
		return fail("rate")
	end
	if not nearAtm(player, a) then
		return fail("far")
	end
	local info = atmInfo(player, a)
	fire(player, { kind = "atm", atm = info })
	return okr({ atm = info })
end

function Bank.registerAtm(inst: any, kindOverride: string?, nameOverride: string?): string?
	if atmOfPart[inst] then
		return atmOfPart[inst]
	end
	local kind, name = Bank.classify(inst)
	if kindOverride and G.ATM_KINDS[kindOverride] then
		kind = kindOverride
	end
	if nameOverride then
		name = nameOverride
	end
	atmCount += 1
	local id = "atm" .. atmCount
	local a: Atm = { id = id, part = inst, kind = kind, name = name, prompt = nil }
	atms[id] = a
	atmOfPart[inst] = id
	pcall(function()
		inst:SetAttribute(G.Attr.AtmId, id)
	end)
	if E.makePrompt then
		local ok, prompt = pcall(E.makePrompt, a)
		if ok then
			a.prompt = prompt
		end
	end
	return id
end

function Bank.unregisterAtm(inst: any)
	local id = atmOfPart[inst]
	if not id then
		return
	end
	atmOfPart[inst] = nil
	local a = atms[id]
	atms[id] = nil
	if a and a.prompt then
		pcall(function()
			a.prompt:Destroy()
		end)
	end
end

function Bank.atms(): { [string]: any }
	return atms
end

function Bank.auditLog(): { any }
	return auditRing
end

-------------------------------------------------------------------------------------------------
-- Roblox environment
-------------------------------------------------------------------------------------------------
local function robloxEnv(): any
	local Players = game:GetService("Players")
	local HttpService = game:GetService("HttpService")
	local TextService = game:GetService("TextService")
	local env: any = {}
	env.Players = Players
	env.now = os.time
	env.tick = os.clock
	env.clock = function(): number
		local ok, e = pcall(ctx.env)
		return if ok and type(e) == "table" and G.isFiniteNumber(e.clock) then e.clock else 12
	end
	env.guid = function(): string
		return HttpService:GenerateGUID(false)
	end
	env.filter = function(text: string, fromId: number, _toId: number?): string?
		local ok, result = pcall(function()
			return TextService:FilterStringAsync(text, fromId, Enum.TextFilterContext.PublicChat)
		end)
		if not ok or not result then
			return nil
		end
		local ok2, s = pcall(function()
			return result:GetNonChatStringForBroadcastAsync()
		end)
		return if ok2 and type(s) == "string" then s else nil
	end
	env.position = function(p: any): any
		return Util.rootPosition(p)
	end
	env.playSeconds = function(p: any, d: any): number
		local joined = ctx.session(p).joinedAt or os.clock()
		return (d.playSeconds or 0) + math.max(0, os.clock() - joined)
	end
	env.persistent = function(p: any): boolean
		return Profiles.persistent(p)
	end
	env.storeEnabled = function(): boolean
		return Profiles.storeEnabled()
	end
	env.saveSoon = function(p: any)
		Profiles.saveSoon(p)
	end
	env.fire = function(p: any, payload: any)
		local ev = remotes.event
		if ev then
			ev:FireClient(p, payload)
		end
	end
	env.makePrompt = function(a: Atm): any
		local part = a.part
		if part:IsA("Model") then
			part = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart", true)
		end
		if not part then
			return nil
		end
		local old = part:FindFirstChild("GwangalliATMPrompt")
		if old then
			old:Destroy()
		end
		local k = G.ATM_KINDS[a.kind]
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "GwangalliATMPrompt"
		prompt.ActionText = if k.counter then "창구 업무" else "ATM 이용"
		prompt.ObjectText = a.name
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = G.BANK.atmPromptDistance
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = part
		prompt.Triggered:Connect(function(player: Player)
			Bank.openAtm(player, a.id)
		end)
		return prompt
	end
	-- audit records in a DataStore (published places only)
	if game.PlaceId ~= 0 then
		local ok, store = pcall(function()
			return game:GetService("DataStoreService"):GetDataStore(AUDIT_STORE)
		end)
		if ok and store then
			env.auditWrite = function(rec: any)
				store:UpdateAsync("tx_" .. tostring(rec.ref), function(old: any)
					if old ~= nil then
						return nil
					end
					return rec
				end)
			end
		end
	end
	return env
end

local function discoverAtms()
	local CollectionService = game:GetService("CollectionService")
	local tag = G.Tags.ATM
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		if inst:IsDescendantOf(workspace) then
			Bank.registerAtm(inst)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		Bank.unregisterAtm(inst)
	end)
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsDescendantOf(workspace) then
			Bank.registerAtm(inst)
		end
	end
	-- the map's own ATM kiosks (build/kit/interior.luau, uptown_civic, city_shops, beachfront, GS25)
	task.delay(5, function()
		local found = 0
		local all = workspace:GetDescendants()
		for i, inst in all do
			if inst:IsA("BasePart") and (inst.Name == "ATM" or inst.Name == "PostATM") and not atmOfPart[inst] then
				-- skip tiny decorative bits
				if inst.Size.Y >= 3 then
					Bank.registerAtm(inst)
					found += 1
				end
			end
			if i % 20000 == 0 then
				task.wait()
			end
		end
		-- a teller counter at the BNK branch when no world object provides one
		local hasCounter = false
		for _, a in atms do
			if a.kind == "counter" then
				hasCounter = true
				break
			end
		end
		if not hasCounter and ctx.dest then
			local dest = ctx.dest("BNK부산은행 광안동지점")
			if dest then
				Bank.registerAtm(dest, "counter", "BNK부산은행 광안동지점 창구")
			end
		end
		print(string.format("[GwangalliGameplay] bank: %d ATMs ready (%d found in the map)", atmCount, found))
	end)
end

-------------------------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------------------------
function Bank.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	local test = context.bankEnv ~= nil
	E = context.bankEnv or robloxEnv()
	E.tick = E.tick or os.clock
	E.now = E.now or os.time

	context.bank = {
		transfer = function(from: any, to: any, amount: number, memo: string?): any
			if not G.bankInt(amount, G.BANK.minTransfer, G.BANK.maxTransfer) then
				return fail("amount")
			end
			if not online(to) or not Profiles.get(to) then
				return fail("offline")
			end
			local code = persistCode(from, to)
			if code then
				return fail(code)
			end
			return applyTransfer(from, to, amount, memo, "server")
		end,
		post = function(player: any, account: string, delta: number, label: string, meta: any?): boolean
			local d = Profiles.get(player)
			if not d then
				return false
			end
			local m = G.ledgerMeta(meta)
			m.ref = m.ref or newRef()
			local ok = G.ledger(d, account, delta, label, E.now(), m)
			if ok then
				touch(player, account)
				audit({ ref = m.ref, t = E.now(), kind = m.kind or "post", from = player.UserId, amount = delta, label = label })
			end
			return ok
		end,
		kstDay = function(unix: number?): number
			return G.bankKstDay(unix or E.now())
		end,
		openAtm = function(player: any, id: string): any
			return Bank.openAtm(player, id)
		end,
		openCounter = function(player: any): any
			for id, a in atms do
				if a.kind == "counter" then
					local info = atmInfo(player, a)
					fire(player, { kind = "atm", atm = info, remote = true })
					return okr({ atm = info, id = id })
				end
			end
			return fail("noatm")
		end,
		registerAtm = Bank.registerAtm,
		summary = function(player: any): any
			return if Profiles.get(player) then summaryOf(player) else nil
		end,
	}

	if test then
		return
	end

	-- remotes (inside GwangalliRemotes; the core created the folder before the modules start)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	remotes.event = remote(G.Remote.BankEvent, "RemoteEvent")
	remotes.request = remote(G.Remote.BankRequest, "RemoteFunction")
	remotes.request.OnServerInvoke = function(player: Player, op: any, payload: any)
		local ok, r = pcall(Bank.handle, player, op, payload)
		if ok then
			return r
		end
		warn("[GwangalliGameplay] bank request failed: " .. tostring(r))
		return fail("bad")
	end

	local okD, errD = pcall(discoverAtms)
	if not okD then
		warn("[GwangalliGameplay] bank: ATM discovery failed: " .. tostring(errD))
	end

	-- expiry + audit writer
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(Bank.sweep)
			if not ok then
				Util.warnOnce("bankSweep", "[GwangalliGameplay] bank sweep failed: " .. tostring(err))
			end
		end
	end)
	if E.auditWrite then
		task.spawn(function()
			while true do
				task.wait(2)
				local rec = table.remove(auditQueue, 1)
				if rec then
					local ok, err = pcall(E.auditWrite, rec)
					if not ok then
						Util.warnOnce("bankAudit", "[GwangalliGameplay] bank audit write failed: " .. tostring(err))
					end
				end
			end
		end)
	end
end

function Bank.onLoaded(_player: any) end

return Bank
