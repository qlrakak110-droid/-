--!nocheck
-- t_serve.luau: Serve tracking + guard + flush against a fake ShopLife bus
local B = require("./mods")
local req = B.req
local Shared = req("CS_init")
local Serve = req("SV_Serve")
local Q = {} -- orderId -> {orderId, item, phase, table, seat, dest}
local calls = {}
local Bridge = {
	req = function(op, d)
		table.insert(calls, op .. ":" .. tostring(d.orderId or d.shop))
		if op == "queue" then
			local l = {}
			for _, o in Q do table.insert(l, o) end
			return { ok = true, orders = l }
		elseif op == "serve" then
			local o = Q[d.orderId]
			if not o or o.phase ~= "ready" then return { ok = false, code = "bad_phase" } end
			o.phase = "served"
			return { ok = true }
		end
		return { ok = true }
	end,
	playerById = function() return nil end,
	SS = nil,
}
local sent = {}
Serve.init(Shared, Bridge, { fire = function(_, k, d) table.insert(sent, k) end })
local function busy(sec) local t = os.clock() while os.clock() - t < sec do end end
-- npc order
Serve.onOrder({ shop = "S", npc = "shop_diner_1", orderId = "o1", items = { { id = "dwaeji", name = "돼지국밥", qty = 1 } }, table = 2, seat = 1 })
Q.o1 = { orderId = "o1", item = "dwaeji", phase = "placed", table = 2, seat = 1, dest = "table" }
-- player order (no orderId): adopted from the queue by table
Q.o2 = { orderId = "o2", item = "sundae", name = "순대국밥", phase = "placed", table = 3, seat = 2, dest = "table" }
local got = Serve.onOrder({ shop = "S", userId = 7, items = { { id = "sundae", name = "순대국밥", qty = 1 } }, table = 3, seat = 2 })
assert(#got == 1 and got[1].owner == 7, "player order adopted")
Q.o1.phase = "ready"; Serve.onReady({ shop = "S", orderId = "o1", where = "table" })
Q.o2.phase = "ready"; Serve.onReady({ shop = "S", orderId = "o2", where = "table" })
assert(#Serve.readyFor("S") == 2)
Serve.claim(Serve.byId("o1"), "waiter")
assert(#Serve.readyFor("S") == 1, "claimed is not offered again")
-- the waiter is up: the guard leaves young orders alone
Serve.guard(function() return true, true end)
assert(not Serve.byId("o2").served)
-- the waiter is gone: served after 1 s
busy(1.15)
Serve.guard(function() return true, false end)
assert(Serve.byId("o1").served and Serve.byId("o2").served, "guard served")
assert(Q.o1.phase == "served" and Q.o2.phase == "served")
-- double serve never happens
local n = 0
for _, c in calls do if c == "serve:o1" then n += 1 end end
Serve.serveNow(Serve.byId("o1"), "waiter")
local n2 = 0
for _, c in calls do if c == "serve:o1" then n2 += 1 end end
assert(n == 1 and n2 == 1, "no double serve " .. n .. " " .. n2)
-- shops we never owned are untouched
Q.o3 = { orderId = "o3", item = "x", phase = "ready", table = 1, seat = 1, dest = "table" }
Serve.onReady({ shop = "T", orderId = "o3", where = "table" })
busy(1.15)
Serve.guard(function(k) if k == "T" then return false, false end return true, true end)
assert(Q.o3.phase == "ready", "not ours: ShopLife serves it")
-- flush
local f = Serve.flush("T")
assert(f == 1 and Q.o3.phase == "served", "flush")
Serve.flushTickets(function() return "가게" end)
print("SERVE OK", #sent)
