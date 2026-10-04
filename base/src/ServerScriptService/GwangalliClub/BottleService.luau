-- GwangalliClub/BottleService (server): the bottle menu, orders and table ownership for the night.
--   openMenu(player, tableId, fromPrompt) -> true when the menu was sent (ShowEvent "menu")
--   order(player, tableId, itemId)          validation -> ledger payment -> Show.start -> receipt
--   reserve(player, setId?) -> tableId?     the door's "테이블 예약 입장" (already paid there)
--   tableOf(player) -> tableId?   owns(player, tableId) -> bool
--   setTable(player, tableId, item, at)     table life (props) from `at` for Show.PropSeconds
-- Prices are the server's (GwangalliClubShowShared.Menu); the client only ever sends ids.
-- Tables (folder attribute, JSON): { [tableId] = { owner, name, tier, set, at, untilT } }.

local Players = game:GetService("Players")

local BottleService = {}

local C: any
local S: any

local tables: { [string]: any } = {} -- tableId -> { owner, name, tier, set, item, at, untilT }
local lastOrder: { [Player]: number } = {}
local lastMenu: { [Player]: number } = {}
local tableOrderAt: { [string]: number } = {}
local paying: { [Player]: boolean } = {}
local dirty = false

local function publish()
	local out = {}
	for id, t in tables do
		out[id] = { owner = t.owner, name = t.name, tier = t.tier, set = t.set, at = t.at, untilT = t.untilT }
	end
	C.publish(S.Attr.Tables, out)
	dirty = false
end

local function valid(t: any?): boolean
	return t ~= nil and C.now() < t.untilT
end

function BottleService.tableOf(plr: Player): string?
	for id, t in tables do
		if t.owner == plr.UserId and valid(t) then
			return id
		end
	end
	return nil
end

function BottleService.owns(plr: Player, tableId: any): boolean
	local t = type(tableId) == "string" and tables[tableId]
	return t and t.owner == plr.UserId and valid(t) or false
end

function BottleService.entry(tableId: string): any?
	local t = tables[tableId]
	return if valid(t) then t else nil
end

-- the table is the player's from the moment the order is paid (props wait for the staff: at = 0)
function BottleService.claim(plr: Player, tableId: string, item: any)
	local t = tables[tableId]
	local nowS = C.now()
	if not t or not valid(t) or t.owner ~= plr.UserId then
		t = { owner = plr.UserId, name = C.filteredName(plr), tier = 0, set = item.set, item = item.id, at = 0, untilT = 0 }
		tables[tableId] = t
	end
	if item.tier >= (t.tier or 0) then
		t.tier = item.tier
		t.set = item.set
		t.item = item.id
	end
	t.untilT = math.max(t.untilT or 0, nowS + 900) -- holds the table while the show waits / walks
	publish()
end

-- the set lands on the table at server time `at` (Show: when the staff arrive)
function BottleService.setTable(plr: Player, tableId: string, item: any, at: number)
	BottleService.claim(plr, tableId, item)
	local t = tables[tableId]
	t.at = at
	t.untilT = math.max(t.untilT or 0, at + (S.Show.PropSeconds or 480))
	publish()
end

-- a table someone else has for the night (nil = free or mine)
local function takenBy(tableId: string, plr: Player): any?
	local t = tables[tableId]
	if valid(t) and t.owner ~= plr.UserId then
		return t
	end
	return nil
end

local function wallet(plr: Player): (number?, number?)
	local cash, bank = C.gameplay("balance", plr)
	return if type(cash) == "number" then cash else nil, if type(bank) == "number" then bank else nil
end

function BottleService.openMenu(plr: Player, tableId: any, fromPrompt: boolean?): boolean
	if type(tableId) ~= "string" or #tableId > 12 then
		return false
	end
	local now = os.clock()
	if not fromPrompt and lastMenu[plr] and now - lastMenu[plr] < 0.8 then
		return true
	end
	lastMenu[plr] = now
	local info = C.hook("tableInfo", tableId)
	if type(info) ~= "table" then
		return false
	end
	if C.hook("reach", plr, tableId, (S.Show.MaxDistance or 18) + 4) ~= true then
		return fromPrompt == true -- the prompt was out of reach: swallow it (no old menu either)
	end
	local aa = C.aa()
	local items = {}
	for _, it in S.Menu do
		table.insert(items, {
			id = it.id,
			tier = it.tier,
			price = it.price,
			label = S.label(it, aa),
			icon = S.icon(it, aa),
			desc = it.desc,
			parade = it.parade == true,
			booking = it.booking == true,
		})
	end
	local cooldown = 0
	if lastOrder[plr] then
		cooldown = math.max(0, (S.Show.OrderCooldownPlayer or 20) - (now - lastOrder[plr]))
	end
	local mine = tables[tableId]
	local owned = valid(mine) and mine.owner == plr.UserId
	local other = takenBy(tableId, plr)
	local cash, bank = wallet(plr)
	local bookingState = C.Booking and C.Booking.stateFor(plr, tableId) or "none"
	C.send(plr, "menu", {
		table = tableId,
		label = info.label,
		kind = info.kind,
		items = items,
		aa = aa,
		priced = C.hasGameplay(),
		cooldown = math.floor(cooldown + 0.5),
		owned = owned,
		tier = if owned then mine.tier else 0,
		takenBy = if other then other.name else nil,
		showBusy = C.Show and C.Show.busy() or false,
		booking = bookingState, -- "none" | "available" | "running" | "cooldown" | "locked"
		cash = cash,
		bank = bank,
	})
	return true
end

local function addStats(plr: Player, item: any)
	local gain = { happiness = 3 + item.tier * 2, popularity = item.tier }
	C.gameplay("addStats", plr, gain, string.format("CLUB OCEAN %s %s", S.label(item, C.aa()), S.icon(item, C.aa())))
end

local function reply(plr: Player, payload: any)
	C.send(plr, "order", payload)
end

function BottleService.order(plr: Player, tableId: any, itemId: any)
	if type(tableId) ~= "string" or #tableId > 12 or type(itemId) ~= "string" or #itemId > 24 then
		return
	end
	local item = S.item(itemId)
	if not item then
		return
	end
	local info = C.hook("tableInfo", tableId)
	if type(info) ~= "table" then
		return
	end
	if paying[plr] then
		reply(plr, { status = "paying", table = tableId })
		return
	end
	if C.hook("reach", plr, tableId, (S.Show.MaxDistance or 18) + 10) ~= true then
		reply(plr, { status = "far", table = tableId })
		return
	end
	local now = os.clock()
	if lastOrder[plr] and now - lastOrder[plr] < (S.Show.OrderCooldownPlayer or 20) then
		reply(plr, { status = "wait", table = tableId, wait = math.ceil((S.Show.OrderCooldownPlayer or 20) - (now - lastOrder[plr])) })
		return
	end
	if tableOrderAt[tableId] and now - tableOrderAt[tableId] < (S.Show.OrderCooldownTable or 25) then
		reply(plr, { status = "busy", table = tableId })
		return
	end
	local other = takenBy(tableId, plr)
	if other then
		reply(plr, { status = "taken", table = tableId, by = other.name })
		return
	end
	local mineElsewhere = BottleService.tableOf(plr)
	if mineElsewhere and mineElsewhere ~= tableId then
		reply(plr, { status = "other", table = tableId, mine = mineElsewhere })
		return
	end
	-- shows queue up; refuse before charging when the queue is full
	if C.Show and C.Show.queueFull() then
		reply(plr, { status = "showfull", table = tableId })
		return
	end
	paying[plr] = true
	lastOrder[plr] = now
	tableOrderAt[tableId] = now
	local aa = C.aa()
	local label = string.format("CLUB OCEAN %s (%s)", S.label(item, aa), tableId)
	C.charge(plr, item.price, label, function(status)
		paying[plr] = nil
		if status == "declined" then
			lastOrder[plr] = nil
			tableOrderAt[tableId] = nil
			reply(plr, { status = "nofunds", table = tableId, item = item.id, price = item.price })
			return
		elseif status == "error" or status == "timeout" then
			lastOrder[plr] = nil
			tableOrderAt[tableId] = nil
			reply(plr, { status = "error", table = tableId })
			return
		end
		if not C.isPlayer(plr) then
			return
		end
		-- the table is the player's from now on (props start when the staff arrive)
		BottleService.claim(plr, tableId, item)
		local wantBooking = item.booking == true
		local res, wait = "error", 0
		if C.Show then
			res, wait = C.Show.start({
				player = plr,
				item = item,
				tableId = tableId,
				onArrive = function(rec)
					if wantBooking and C.Booking and C.isPlayer(plr) then
						task.delay(5, function()
							if C.isPlayer(plr) then
								C.Booking.start(plr, tableId, item.tier, true)
							end
						end)
					end
				end,
			})
		end
		if res == "full" or res == "error" then
			-- no show slot: the set goes straight onto the table (no fanfare) - still served
			BottleService.setTable(plr, tableId, item, C.now() + 2)
			C.hook("stamp", tableId, C.now() + 2, plr.UserId)
		end
		addStats(plr, item)
		reply(plr, {
			status = if res == "queued" then "queued" elseif res == "now" then "ok" else "served",
			table = tableId,
			item = item.id,
			label = S.label(item, aa),
			icon = S.icon(item, aa),
			price = item.price,
			paid = status == "paid" or status == "paid-late",
			free = status == "noapi" or status == "free",
			wait = math.floor(wait + 0.5),
			tier = item.tier,
			booking = if item.tier >= (S.Booking.MinTier or 3) and not wantBooking then "available" else (if wantBooking then "auto" else "none"),
		})
	end)
end

-- door: the reserved table (a booth first) with the basic set walked over
local PREF = { "Booth", "DJ", "Standing", "Bar", "VIP" }
function BottleService.reserve(plr: Player, setId: any): string?
	local have = BottleService.tableOf(plr)
	if have then
		return have
	end
	local item = S.item(if type(setId) == "string" then setId else "basic") or S.item("basic")
	local ids = C.hook("tables")
	if type(ids) ~= "table" then
		return nil
	end
	local best, bestRank = nil, math.huge
	for _, id in ids do
		if not valid(tables[id]) then
			local info = C.hook("tableInfo", id)
			if type(info) == "table" and not info.busy then
				local rank = (table.find(PREF, info.kind) or 9) * 100 + #info.seats * -1
				if string.sub(id, 1, 1) == "G" then
					rank += 1000 -- the VIP platform stays for the bottle buyers
				end
				if rank < bestRank or (rank == bestRank and best and id < best) then
					best, bestRank = id, rank
				end
			end
		end
	end
	if not best then
		return nil
	end
	BottleService.claim(plr, best, item)
	if C.Show then
		C.Show.start({ player = plr, item = item, tableId = best })
	end
	C.toast(plr, string.format("%s 테이블 예약 완료 🧊", best), string.format("%s 이(가) 테이블로 나가요. 들어가서 앉으세요!", S.label(item, C.aa())), "🧊")
	return best
end

function BottleService.tick()
	local nowS = C.now()
	for id, t in tables do
		if nowS >= t.untilT then
			tables[id] = nil
			dirty = true
		end
	end
	if dirty then
		publish()
	end
end

function BottleService.onLeave(plr: Player)
	lastOrder[plr] = nil
	lastMenu[plr] = nil
	paying[plr] = nil
	for id, t in tables do
		if t.owner == plr.UserId then
			tables[id] = nil
			dirty = true
		end
	end
end

function BottleService.init(ctx: any)
	C = ctx
	S = ctx.Shared
	publish()
	local _ = Players
end

return BottleService
