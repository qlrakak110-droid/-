--!nocheck
local R = require("./lib/rbx")
local G = R.G
local E = table.clone(R.env)
E.task = R.task
E.Font, E.Rect, E.NumberRange = G.Font, G.Rect, G.NumberRange
E.Instance = R.Instance
local baseTypeof = E.typeof
E.typeof = function(v) if type(v) == "table" and getmetatable(v) and rawget(v, "_p") then return "Instance" end return baseTypeof(v) end
local B = require("./b_srv")(E)
local req, tok = B.req, B.tok
local S = req(tok("Shared"))
local GS = req(tok("GwangalliGarageShared"))
local VS = req(tok("GwangalliVehiclesShared"))
S.GS = function() return GS end
S.VS = function() return VS end
S.P = function() return nil end
local player = R.player
local hrp = R.hrp
-- fake garage
local bank, cash = 1000000, 50000
local cars = { { id = "a1", kind = "compact", grade = "used", label = "큐비", sell = 90000, bought = 150000, plate = "부산11가 1111" } }
local garageCalls = {}
local Bridge = { fail = function(code, msg) return { ok = false, code = code, message = msg } end }
function Bridge.request(p, op, payload)
	table.insert(garageCalls, op)
	if op == "buy" then
		local price = payload.model and GS.modelPrice(payload.model) or GS.price(payload.kind, payload.grade)
		local due = payload.loan and GS.loanQuote(price).down or price
		if #cars >= 3 then return { ok = false, code = "max", message = "차는 최대 3대" } end
		if bank >= due then bank -= due elseif cash >= due then cash -= due else return { ok = false, code = "insufficient", message = "잔액 부족" } end
		local c = { id = "n" .. #cars, kind = payload.kind, grade = payload.grade, label = "새차", plate = "부산99허 9999", sell = math.floor(price * 0.6), bought = price }
		table.insert(cars, c)
		return { ok = true, code = "ok", car = c, receipt = { plate = c.plate, paid = due, price = price, account = "bank" } }
	elseif op == "sell" then
		for i, c in cars do if c.id == payload.id then table.remove(cars, i) bank += c.sell return { ok = true, payout = c.sell, value = c.sell } end end
		return { ok = false, code = "bad", message = "없는 차" }
	elseif op == "testdrive" then
		return { ok = true, seconds = 60, car = nil }
	end
	return { ok = true, code = "ok" }
end
function Bridge.status(p) return { cars = cars, owned = #cars, max = 3, bank = bank, cash = cash, testCooldown = 0, testing = false, loaded = true } end
function Bridge.balance(p) return bank, cash end
local credits = {}
function Bridge.credit(p, amt, label) table.insert(credits, label .. " " .. amt) bank += amt return true end
function Bridge.level(p) return 5 end
function Bridge.root(p) return hrp end
function Bridge.blocked(p) return nil end
function Bridge.availableModels() return {} end
function Bridge.vehicles() return nil end
local Npc = { list = function() return { { id = "consult", pos = hrp.Position + G.Vector3.new(5, 0, 0) } } end, info = function(id) return { id = id, name = "한서윤" } end, nearest = function() return nil end }
local TestDrive = { active = function() return nil end, cooldownLeft = function() return 0 end, watch = function() end, start = function() return { ok = true } end, stop = function() end }
local Store = req(tok("Store"))
Store.init(S)
Store.load(player)
S.Config.RATE = { perSecond = 1000, burst = 1000 }
for _, op in { "hello", "catalog", "buy", "sell", "testdrive", "endtest", "rent", "deliver", "wish", "waypoint" } do S.Config.COOLDOWN[op] = 0 end
local Service = req(tok("Service"))
Service.init(S, Bridge, Store, Npc, TestDrive)
S.usedRate = function() return 0.05 end
local function J(t)
	local parts = {}
	for k, v in t do if type(v) ~= "table" then table.insert(parts, k .. "=" .. tostring(v)) end end
	table.sort(parts)
	return table.concat(parts, " ")
end
local function call(op, p) local r = Service.handle(player, op, p) R.advance(2.5) return r end
print("bad op", J(call("hack", {})))
print("bad payload", J(call("buy", { entry = "kit:sedan:new", x = { 1 } })))
print("nan", J(call("buy", { entry = "kit:sedan:new", nonce = "n1", color = 0/0 })))
print("long", J(call("buy", { entry = string.rep("a", 70), nonce = "n1" })))
print("no nonce", J(call("buy", { entry = "kit:sedan:new" })))
print("bad entry", J(call("buy", { entry = "kit:sedan:gold", nonce = "n2" })))
print("rent via buy", J(call("buy", { entry = "rent", nonce = "n3" })))
local sp = {}
for _, id in J(call("catalog", {})) and Service.snapshot(player).specials do table.insert(sp, id) end
print("specials", table.concat(sp, ","))
local r = call("buy", { entry = "kit:compact:used", nonce = "n4", color = "mint" })
print("buy used", J(r), "lines", #(r.cashbackLines or {}), "bank", bank)
local r2 = call("buy", { entry = "kit:compact:used", nonce = "n4", color = "mint" })
print("same nonce", r2 == r, "cars", #cars)
local r3 = call("buy", { entry = "kit:sedan:new", nonce = "n5", loan = true })
print("buy loan", J(r3), "bank", bank, "cars", #cars)
local r4 = call("buy", { entry = "kit:suv:new", nonce = "n6" })
print("full", J(r4))
local r5 = call("buy", { entry = "kit:suv:new", nonce = "n7", trade = "a1" })
print("trade", J(r5), r5.trade and J(r5.trade), "cars", #cars, "bank", bank)
print("credits", table.concat(credits, " | "))
local far = hrp.Position
hrp.CFrame = G.CFrame.new(far + G.Vector3.new(500, 0, 0))
print("far", J(call("buy", { entry = "kit:truck:new", nonce = "n8" })))
print("far test", J(call("testdrive", { entry = "kit:truck:new" })))
print("wish", J(call("wish", { entry = "kit:luxury:new", on = true })))
print("rate", J(Service.handle(player, "wish", { entry = "kit:luxury:new", on = true })))
print("garage calls", table.concat(garageCalls, ","))
