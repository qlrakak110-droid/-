--!nocheck
local R = require("./lib/rbx")
local G = R.G
local E = table.clone(R.env)
E.task = R.task
E.Font, E.Rect, E.NumberRange = G.Font, G.Rect, G.NumberRange
E.Instance = R.Instance
local B = require("./b_cli")(E)
local req, tok = B.req, B.tok
local game = R.game
local UIS = game:GetService("UserInputService")
UIS.TouchEnabled = false
UIS.MouseEnabled = true
UIS.GamepadEnabled = false
UIS.TouchPinch = R.Signal.new()
function UIS:GetLastInputType() return G.Enum.UserInputType.MouseMovement end
function UIS:GetFocusedTextBox() return nil end
local player = R.player
if not player:FindFirstChild("PlayerGui") then
	local pg = R.Instance.new("Folder")
	pg.Name = "PlayerGui"
	pg.Parent = player
end
player:SetAttribute("Bank", 1500000)
player:SetAttribute("Money", 80000)
local RS = game:GetService("ReplicatedStorage")
local pv = R.Instance.new("Folder")
pv.Name = "GwangalliCarDealerPreviews"
pv:SetAttribute("Ready", true)
pv.Parent = RS
local car = R.Instance.new("Model")
car.Name = "kit_suv"
local body = R.Instance.new("Part")
body.Name = "BodySide"
body.Size = G.Vector3.new(6, 4, 14)
body.Parent = car
car:SetAttribute("Size", G.Vector3.new(6, 4, 14))
car.Parent = pv

local S = req(tok("Shared"))
local GS = req(tok("GS"))
local VS = req(tok("VS"))
local Ui = req(tok("Ui"))
local ctx = { S = S, C = S.Config, Ui = Ui, GS = GS, VS = VS }
ctx.Net = req(tok("Net"))
ctx.Viewport = req(tok("Viewport"))
ctx.NpcFx = req(tok("NpcFx"))
ctx.Dialog = req(tok("Dialog"))
ctx.Detail = req(tok("Detail"))
ctx.CatalogUI = req(tok("CatalogUI"))
ctx.Contract = req(tok("Contract"))
ctx.Ceremony = req(tok("Ceremony"))
ctx.TestHud = req(tok("TestHud"))
local snap = { ok = true, code = "ok", garageReady = true, loaded = true, avail = {}, showAll = false, month = "2026-10", daysLeft = 15,
	specials = { "kit:sedan:new", "kit:luxury:used" },
	cars = { { id = "c1", kind = "compact", grade = "used", label = "큐비", glyph = "🚙", plate = "부산12가 3456", sell = 90000, bought = 150000, color = "white" } },
	owned = 1, max = 3, bank = 1500000, cash = 80000, level = 4, usedRate = 0.05, gates = { enforce = false }, loanBlocked = false, rentActive = false,
	testCooldown = 0, testing = false, near = true, wish = { "kit:suv:new" }, tested = { ["kit:sedan:new"] = 1 }, best = { ["kit:sedan:new"] = { kmh = 121, m = 900 } }, tradeBonus = 0.05 }
local calls = {}
ctx.Net.call = function(op, payload)
	table.insert(calls, op)
	if op == "catalog" then return snap end
	if op == "wish" then return { ok = true, wish = { "kit:suv:new", "kit:luxury:new" } } end
	return { ok = true, code = "ok" }
end
Ui.init(nil)
ctx.Net.init(ctx)
ctx.Viewport.init(ctx)
ctx.Detail.init(ctx)
ctx.CatalogUI.init(ctx)
ctx.Contract.init(ctx)
ctx.Ceremony.init(ctx)
ctx.Dialog.init(ctx)
ctx.TestHud.init(ctx)
ctx.NpcFx.init(ctx)
local function step(n) for _ = 1, n or 10 do R.advance(0.1) end end
local function count(root, pat)
	local n = 0
	for _, d in root:GetDescendants() do if string.find(d.Name, pat) then n += 1 end end
	return n
end
local pg = player.PlayerGui
local function gui(name) return pg:FindFirstChild(name) end
print("== catalog open")
ctx.CatalogUI.open({ cat = "all" })
step(5)
local cg = gui("GwangalliCarDealerUI")
print("enabled", cg and cg.Enabled, "cards", count(cg, "^Card_"), "tabs", count(cg, "^Tab_"), "entries", #ctx.Net.state.entries)
ctx.CatalogUI.setCat("suv"); step(3)
print("suv cards", count(cg, "^Card_"))
ctx.CatalogUI.setCat("special"); step(3)
print("special cards", count(cg, "^Card_"))
ctx.CatalogUI.setCat("all"); step(2)
ctx.CatalogUI.toggleWish("kit:luxury:new"); step(2)
print("== detail")
ctx.CatalogUI.openDetail("kit:suv:new"); step(5)
print("detail open", ctx.Detail.isOpen(), "rows", count(cg, "^Row"))
ctx.Detail.show(ctx.Net.state.byId["kit:suv:used"]); step(3)
ctx.CatalogUI.toggleCompare("kit:suv:used"); ctx.CatalogUI.toggleCompare("kit:sedan:new"); step(2)
print("== contract")
ctx.Contract.open(ctx.Net.state.byId["kit:suv:new"], { colorId = "red", loan = true, trade = false }); step(3)
local kg = gui("GwangalliCarDealerContract")
print("contract", kg and kg.Enabled, "children", kg and #kg:GetDescendants())
ctx.Contract.close()
ctx.Contract.open(ctx.Net.state.byId["kit:luxury:new"], { colorId = "black", loan = false, trade = true }); step(3)
ctx.Contract.close()
ctx.Contract.compare("kit:suv:used", "kit:sedan:new"); step(2)
ctx.Contract.close()
ctx.Contract.rent(ctx.Net.state.byId["rent"]); step(2)
ctx.Contract.close()
print("== ceremony")
local res = { ok = true, code = "ok", car = { id = "c2", plate = "부산34나 5678", label = "트레일 SUV" }, receipt = { label = "든든 SUV 신차 (레드)", plate = "부산34나 5678", paid = 294000, account = "bank", loan = { down = 294000, daily = 72100, days = 10 }, price = 980000 }, cashback = 0, trade = { name = "큐비", payout = 90000, bonus = 4500 } }
ctx.Ceremony.play(res, ctx.Net.state.byId["kit:suv:new"], "red"); step(40)
print("ceremony open", ctx.Ceremony.isOpen())
print("== phone")
R.camera.ViewportSize = G.Vector2.new(844, 390)
step(3)
ctx.CatalogUI.close()
ctx.CatalogUI.open({ cat = "all", entry = "kit:sedan:used" }); step(5)
print("phone detail", ctx.Detail.isOpen(), "cards", count(cg, "^Card_"))
ctx.CatalogUI.closeDetail(); step(2)
ctx.CatalogUI.close()
print("calls", table.concat(calls, ","))
print("DONE")
