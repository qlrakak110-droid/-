--!nocheck
require("./stubs")
local which = ...
local B = require(if which == "old" then "./b_old" else "./b_new")
local req, tok = B.req, B.tok
-- inject globals into module envs: modules see _G via getfenv? luau CLI: globals are shared
Vector3, Color3, Enum, game = _G.Vector3, _G.Color3, _G.Enum, _G.game
local U = req(tok("Util"))
local Cat = req(tok("Catalog"))
local Lines = req(tok("Lines"))
local GS = req(tok("GS"))
local VS = req(tok("VS"))
print("MODELS", GS.MODELS and #GS.MODELS or "nil")
local list, byId = Cat.build(GS, VS, { avail = {}, showAll = false, rent = true })
print("entries", #list)
for _, e in list do
  print(string.format("%-16s %-14s %-8s %9d %s loan=%s cats=%s prev=%s brand=%s fuel=%s", e.id, e.name, e.grade, e.price, U.man(e.price), e.loan and U.won(e.loan.down) or "-", table.concat(e.cats, ","), e.preview, e.brand, e.fuel))
end
local all = Cat.build(GS, VS, { avail = { k5 = true }, showAll = true })
print("showAll entries", #all)
for _, e in all do if e.model then print(" ", e.id, e.name, table.concat(e.cats, ","), e.available, e.deliverAs or "") end end
local sp = Cat.pickSpecials(list, "2026-10", 2, 140000)
for id in sp do print("special", id) end
local sp2 = Cat.pickSpecials(list, "2026-11", 2, 140000)
for id in sp2 do print("special nov", id) end
for _, c in Cat.catsIn(list) do io = nil; print("cat", c.id, c.label) end
local money = { bank = 200000, cash = 50000 }
local f = Cat.filter(list, { cat = "all", affordableOnly = true, money = money })
print("affordable", #f)
for _, e in Cat.sort(f, "rec", money) do print("  rec", e.id, e.price) end
for _, b in { 300000, 1500000, 5000000 } do
  local e, how = Cat.recommend(list, b, money)
  print("budget", b, e and e.id, how)
end
local e = byId["kit:compact:used"]
local ben = Cat.benefits(e, { usedRate = 0.05, special = true })
print("benefits", ben.total, ben.rate, #ben.lines)
print(U.man(780000), U.man(23700), U.man(125000000), U.man(9500), U.manShort(780000), U.manShort(23700))
print(Lines.get("consult", "budget_full", { car = "미드 세단", price = "78만원" }, 1))
print(Lines.get("consult", "budget_full", { car = "트레일 SUV", price = "98만원" }, 1))
print(Lines.get("boss", "special_intro", { month = 10, list = "큐비 박스카 · 든든 1톤 트럭", pct = "7%", days = 15 }, 1))
print(Lines.get("consult", "rent_ask", { car = "큐비", minutes = 40, fee = "2만원" }, 1))
print(Lines.get("consult", "delivered", { car = "큐비", plate = "부산12가 3456" }, 1))
print(U.josa("1톤 트럭", "이"), U.josa("SUV", "을"), U.josa("부산 3", "으로"), U.josa("서울", "으로"))
print("parse", Cat.parse("kit:sedan:new") ~= nil, Cat.parse("kit:sedan:mint") == nil, Cat.parse("model:k5").model, Cat.parse("model:../x") == nil, Cat.parse(string.rep("a", 50)) == nil)
local q = Cat.filter(list, { cat = "all", query = "트럭" })
print("search 트럭", #q)
local q2 = Cat.filter(list, { cat = "all", query = "중고" })
print("search 중고", #q2)
