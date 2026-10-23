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
rawget(player, "_p").DisplayName = "테스터"
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

local function choose(pat)
	local dg = gui("GwangalliCarDealerDialog")
	for i = 1, 400 do
		for _, b in dg:GetDescendants() do
			if b.ClassName == "TextButton" and string.find(b.Name, "^Choice_") then
				local lbl = b:FindFirstChild("Label")
				if lbl and string.find(lbl.Text, pat, 1, true) then
					print("  choose", lbl.Text)
					b.Activated:Fire()
					step(3)
					return true
				end
			end
		end
		step(1)
	end
	print("  choose FAILED", pat)
	return false
end
local function said()
	local dg = gui("GwangalliCarDealerDialog")
	for _, d in dg:GetDescendants() do
		if d.ClassName == "TextLabel" and d.TextWrapped and #d.Text > 20 then
			return d.Text
		end
	end
	return ""
end
ctx.Net.call = function(op, payload)
	if op == "catalog" then return snap end
	if op == "hello" then return { ok = true, npc = { id = "consult" }, ctx = { visits = 3, first = false, owned = 1, max = 3, full = false, ownedName = "큐비", testedName = "미드 세단", garageReady = true, near = true, canSell = true } } end
	if op == "testdrive" then return { ok = false, code = "cooldown", message = "12초 뒤에 다시 시승할 수 있어요" } end
	if op == "rent" then return { ok = true } end
	return { ok = true, code = "ok" }
end
S.Config.UI.typeSpeed = 1e7
ctx.Dialog.open({ id = "consult", name = "한서윤 대리", role = "영업 컨설턴트", voice = "consult", icon = "👩‍💼" })
step(20)
choose("이달의 특가")
print("  >", said())
choose("다른 것도")
choose("예산에 맞는")
choose("150만 원")
print("  >", said())
choose("다른 질문")
choose("시승 예약")
choose("미드 세단")
step(30)
print("  >", said())
choose("하루 렌트")
print("  >", said())
choose("괜찮아요")
choose("내 차 팔기")
print("  >", said())
choose("다음에 할게요")
choose("전체 차량 보기")
step(5)
print("dialog open", ctx.Dialog.isOpen(), "catalog open", ctx.CatalogUI.isOpen())
ctx.CatalogUI.close()
ctx.Dialog.open({ id = "boss", name = "박사장", role = "광안 오토 대표", voice = "boss", icon = "👨‍💼" })
step(20)
print("  boss >", said())
choose("그냥 둘러볼게요")
step(30)
print("dialog open", ctx.Dialog.isOpen())
print("DONE")
