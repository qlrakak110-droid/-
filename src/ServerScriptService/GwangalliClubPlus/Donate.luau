-- GwangalliClubPlus.Donate: 전광판 후원 (server).
--   request(p, { rid, amount, msg?, target? })   in-game money: presets or a custom amount (validated),
--       optional message (TextService broadcast filter), target "all" | "dj" | a table id with an owner.
--       Order of checks: gate -> rid dedupe -> one in flight -> cooldown -> queue room -> amount /
--       target / text -> filter (yields) -> gate again -> balance -> charge (8 s timeout, a late
--       success is honoured) -> LED cue + rankings + receipt.
--   robuxIntent(p, { rid, product, msg?, target? })  prepares the message for a developer product
--       purchase (Config.Robux.Products); Receipts calls Donate.grantRobux when the receipt arrives.
-- Every LED cue carries only server-made text: filtered names / message, the amount, the target.

local Players = game:GetService("Players")

local Donate = {}

local C: any
local S: any
local D: any
local L: any

local inFlight: { [Player]: boolean } = {}
local lastAt: { [Player]: number } = {}
local rids: { [Player]: { string } } = {}
local intents: { [number]: { [number]: any } } = {} -- uid -> productId -> { msg, target, untilT }
local djShare: { [number]: number } = {} -- night total paid to DJs (uid -> 원), reset per night
local djShareNight = 0

local function receipt(p: Player, op: string, status: string, extra: { [string]: any }?)
	local payload: { [string]: any } = { op = op, status = status }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	C.send(p, "receipt", payload)
end

local function seenRid(p: Player, rid: any): boolean
	if type(rid) ~= "string" or #rid == 0 or #rid > 24 then
		return true -- no / bad rid: treat as a duplicate (ignored)
	end
	local list = rids[p]
	if not list then
		list = {}
		rids[p] = list
	end
	if table.find(list, rid) then
		return true
	end
	table.insert(list, rid)
	if #list > 12 then
		table.remove(list, 1)
	end
	return false
end

-- target -> cue data { k = "all" } | { k = "table", id, n } | { k = "dj", n, u }; nil = invalid
local function resolveTarget(target: any): any?
	if target == nil or target == "all" then
		return { k = "all" }
	end
	if target == "dj" then
		local dj = C.Dj.current()
		if dj then
			return { k = "dj", n = dj.n, u = dj.u }
		end
		return nil
	end
	if type(target) == "string" and #target <= 8 and target:match("^%w+$") then
		local e = C.Bridge.tables()[target]
		if e then
			return { k = "table", id = target, n = if type(e.name) == "string" then e.name else "손님", u = e.owner }
		end
	end
	return nil
end

local function cleanMessage(p: Player, msg: any): (boolean, string?)
	if msg == nil or msg == "" then
		return true, nil
	end
	local clean = S.cleanText(msg, D.MessageMax)
	if not clean then
		return false, nil
	end
	local filtered = C.filterText(p, clean)
	if not filtered then
		return false, nil
	end
	return true, filtered
end

local function cueData(p: Player, amount: number, msg: string?, target: any, robux: boolean): any
	return {
		u = p.UserId,
		n = C.filteredName(p),
		un = p.Name,
		w = amount,
		m = msg,
		to = target,
		rb = robux or nil,
	}
end

-- queue the LED cue + rankings + side effects of a paid 후원; -> pos, at (nil when the stage is full)
local function deliver(p: Player, amount: number, msg: string?, target: any, robux: boolean): (number?, number)
	local tier = S.donateTier(amount)
	local data = cueData(p, amount, msg, target, robux)
	local pos, at = C.Stage.push("donate", S.donateLength(tier), tier, data, p.UserId, true)
	C.Ranking.addDonate(p.UserId, data.n, amount)
	C.Stage.ticker("donate", data.n, string.format(L.Ticker.donate, data.n, S.wonShort(amount)), amount)
	if D.Stats then
		C.addStats(p, { happiness = 2 + tier, popularity = tier }, "CLUB OCEAN 전광판 후원 💸")
	end
	-- the DJ's share of a 후원 sent to them
	if target.k == "dj" and type(target.u) == "number" and target.u ~= p.UserId then
		local night = S.nightOf(os.time())
		if night ~= djShareNight then
			djShareNight = night
			djShare = {}
		end
		local djPlayer = Players:GetPlayerByUserId(target.u)
		local cfg = S.Config.DJ
		local share = math.floor(amount * cfg.ShareRate / 100) * 100
		local room = cfg.ShareCapPerNight - (djShare[target.u] or 0)
		share = math.min(share, room)
		if djPlayer and share > 0 then
			djShare[target.u] = (djShare[target.u] or 0) + share
			task.spawn(function()
				if C.payout(djPlayer, share, "CLUB OCEAN DJ 후원 정산") then
					C.toast(djPlayer, { "🎧 DJ 후원 정산", "%s님의 후원 중 %s이 입금됐어요" }, "money", "💰", data.n, S.won(share))
				end
			end)
		end
	end
	-- the target table's owner hears about it
	if target.k == "table" and type(target.u) == "number" and target.u ~= p.UserId then
		local tp = Players:GetPlayerByUserId(target.u)
		if tp then
			C.toast(tp, { "💸 전광판 후원 도착!", "%s님이 %s 테이블에 %s 후원을 보냈어요" }, "club", "📺", data.n, target.id, S.wonShort(amount))
		end
	end
	return pos, at
end

function Donate.init(ctx: any)
	C = ctx
	S = ctx.S
	D = S.Config.Donate
	L = S.Lines
end

function Donate.menu(p: Player): any
	local now = os.clock()
	local cash, bank = C.balance(p)
	local tables = {}
	for id, e in C.Bridge.tables() do
		table.insert(tables, { id = id, n = if type(e.name) == "string" then e.name else "손님", u = e.owner, tier = e.tier })
	end
	table.sort(tables, function(a, b)
		return a.id < b.id
	end)
	local products = {}
	for _, pr in S.Config.Robux.Products do
		if type(pr) == "table" and S.isInt(pr.id) and pr.id > 0 then
			table.insert(products, { id = pr.id, won = pr.won, label = pr.label })
		end
	end
	local dj = C.Dj.current()
	return {
		priced = C.hasWallet(),
		wallet = { cash = cash, bank = bank },
		presets = D.Presets,
		min = D.Min,
		max = D.Max,
		step = D.Step,
		msgMax = D.MessageMax,
		templates = D.Templates,
		tables = tables,
		djOn = dj and { u = dj.u, n = dj.n } or nil,
		products = products,
		cooldown = math.max(0, D.Cooldown - (now - (lastAt[p] or -1e9))),
		queue = C.Stage.count(),
		gate = (C.gate(p)),
	}
end

function Donate.request(p: Player, payload: { [string]: any })
	local op = "donate"
	local ok = C.gate(p)
	if not ok then
		receipt(p, op, "gate")
		return
	end
	if seenRid(p, payload.rid) then
		return
	end
	if inFlight[p] then
		receipt(p, op, "busy")
		return
	end
	local wait = D.Cooldown - (os.clock() - (lastAt[p] or -1e9))
	if wait > 0 then
		receipt(p, op, "wait", { wait = math.ceil(wait) })
		return
	end
	if C.Stage.count() >= D.MaxQueue then
		receipt(p, op, "full")
		return
	end
	if C.Stage.pendingFor(p.UserId) >= D.MaxPerPlayer then
		receipt(p, op, "mine")
		return
	end
	local amount = payload.amount
	if not S.amountOk(amount) then
		receipt(p, op, "amount")
		return
	end
	local target = resolveTarget(payload.target)
	if not target then
		receipt(p, op, "target")
		return
	end
	if not C.hasWallet() then
		receipt(p, op, "noapi")
		return
	end
	inFlight[p] = true
	local okMsg, msg = cleanMessage(p, payload.msg)
	if not okMsg then
		inFlight[p] = nil
		receipt(p, op, "filter")
		return
	end
	-- (the filter yielded: check again)
	if not C.isPlayer(p) or not (C.gate(p)) then
		inFlight[p] = nil
		receipt(p, op, "gate")
		return
	end
	local cash, bank = C.balance(p)
	if cash ~= nil and (cash or 0) + (bank or 0) < amount then
		inFlight[p] = nil
		receipt(p, op, "nofunds", { price = amount })
		return
	end
	local label = string.format("CLUB OCEAN 전광판 후원 (%s)", S.wonShort(amount))
	local done = false
	C.charge(p, amount, label, function(status: string)
		if status == "paid" or status == "paid-late" then
			local late = status == "paid-late" or done
			done = true
			inFlight[p] = nil
			lastAt[p] = os.clock()
			if not C.isPlayer(p) then
				-- left while paying: the cue still plays with the stored name
				deliver(p, amount, msg, target, false)
				return
			end
			local pos, at = deliver(p, amount, msg, target, false)
			if late then
				C.toast(p, L.Receipt.late, "club", "📺")
				receipt(p, op, "ok", { price = amount, pos = pos, at = at, late = true })
			else
				receipt(p, op, "ok", { price = amount, pos = pos, at = at, rid = payload.rid })
			end
		elseif not done then
			done = true
			inFlight[p] = nil
			if status == "declined" then
				receipt(p, op, "nofunds", { price = amount })
			elseif status == "timeout" then
				receipt(p, op, "slow")
			elseif status == "noapi" then
				receipt(p, op, "noapi")
			else
				receipt(p, op, "error")
			end
		end
	end)
end

-- Robux: the message / target are prepared (and filtered) before the purchase prompt
function Donate.robuxIntent(p: Player, payload: { [string]: any })
	local op = "robux"
	local product = S.product(payload.product)
	if not product then
		receipt(p, op, "error")
		return
	end
	if not (C.gate(p)) then
		receipt(p, op, "gate")
		return
	end
	if seenRid(p, payload.rid) then
		return
	end
	local target = resolveTarget(payload.target)
	if not target then
		receipt(p, op, "target")
		return
	end
	local okMsg, msg = cleanMessage(p, payload.msg)
	if not okMsg then
		receipt(p, op, "filter")
		return
	end
	local mine = intents[p.UserId]
	if not mine then
		mine = {}
		intents[p.UserId] = mine
	end
	mine[product.id] = { msg = msg, target = target, untilT = os.clock() + S.Config.Robux.IntentSeconds }
	receipt(p, op, "robuxOk", { product = product.id })
end

-- called by Receipts for a purchase of one of our products; -> true when delivered
function Donate.grantRobux(p: Player, productId: number): boolean
	local product = S.product(productId)
	if not product or not C.isPlayer(p) then
		return false
	end
	local intent = intents[p.UserId] and intents[p.UserId][productId]
	local msg, target = nil, { k = "all" }
	if intent and intent.untilT > os.clock() then
		msg, target = intent.msg, intent.target
		intents[p.UserId][productId] = nil
	end
	-- a DJ / table target that is gone by now becomes the whole club
	if target.k ~= "all" then
		local again = resolveTarget(if target.k == "dj" then "dj" else target.id)
		target = again or { k = "all" }
	end
	local amount = math.max(0, math.floor(tonumber(product.won) or 0))
	local tier = S.donateTier(amount)
	local data = cueData(p, amount, msg, target, true)
	-- Robux 후원 always get a slot (the queue limit protects only in-game money spam)
	local pos, at = C.Stage.push("donate", S.donateLength(tier), tier, data, p.UserId, true)
	if not pos then
		return false
	end
	C.Ranking.addDonate(p.UserId, data.n, amount)
	C.Stage.ticker("donate", data.n, string.format(L.Ticker.donate, data.n, S.wonShort(amount)), amount)
	C.toast(p, L.Receipt.robuxDone, "club", "💎")
	receipt(p, "robux", "ok", { price = amount, pos = pos, at = at })
	return true
end

function Donate.playerLeft(p: Player)
	inFlight[p] = nil
	lastAt[p] = nil
	rids[p] = nil
	intents[p.UserId] = nil
end

function Donate.tick(_now: number)
	local t = os.clock()
	for uid, list in intents do
		for pid, it in list do
			if it.untilT < t then
				list[pid] = nil
			end
		end
		if next(list) == nil then
			intents[uid] = nil
		end
	end
end

return Donate
