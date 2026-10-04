-- BbqView: the 고깃집 table sheet. 앉기 (the table prompt) -> 주문 (meat / sides) -> 굽기 (put pieces on
-- the grill) -> 뒤집기 (flip when the bottom is golden) -> 먹기 (both sides done, not burnt) -> 계산
-- (pay at the counter on the way out). Doneness comes from the server (bbq.state, 0 raw .. 1 perfect ..
-- 1.6 burnt per side); the meat on the real grill changes colour at the same time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Util = Shared.Util
local UI = require(script.Parent:WaitForChild("UI"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local BbqView = {}

local C = UI.C
local state: any = nil -- { d = open payload, pieces = {}, bill = n, tab = "grill" | "menu" }
local sheet: any = nil

local function donenessText(v: number): (string, Color3)
	if v < 0.3 then
		return "생고기", Color3.fromRGB(240, 150, 150)
	elseif v < 0.6 then
		return "익는 중", Color3.fromRGB(240, 190, 120)
	elseif v < 0.85 then
		return "거의 다", Color3.fromRGB(230, 200, 90)
	elseif v <= 1.25 then
		return "노릇노릇 ✨", Color3.fromRGB(120, 220, 120)
	elseif v <= 1.6 then
		return "바삭", Color3.fromRGB(220, 150, 60)
	end
	return "탔어요 💀", Color3.fromRGB(150, 150, 150)
end

local function bar(parent: Instance, x: number, w: number, label: string, v: number)
	local bg = UI.frame(parent, { Position = UDim2.new(0, x, 0, 30), Size = UDim2.new(0, w, 0, 18), BackgroundColor3 = C.bg3 })
	UI.corner(bg, 9)
	local txt, col = donenessText(v)
	local fill = UI.frame(bg, { Size = UDim2.new(math.clamp(v / 1.6, 0, 1), 0, 1, 0), BackgroundColor3 = col })
	UI.corner(fill, 9)
	local l = UI.label(bg, label .. " " .. txt, { size = 11, bold = true, align = "center", color = Color3.fromRGB(20, 20, 24) })
	l.Size = UDim2.fromScale(1, 1)
	l.ZIndex = 3
end

local function act(action: string, piece: number?, extra: any?)
	local payload = { action = action, piece = piece }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	local res = Net.call("shop.bbq", payload)
	if res.ok then
		Sfx.ui(if action == "eat" then "success" else "tap")
	else
		Sfx.ui("error")
	end
	return res
end

local render: () -> ()

local function grillTab(body: Instance)
	local pieces = state.pieces or {}
	if #pieces == 0 then
		UI.label(body, "🔥 불판이 달궈졌어요. '메뉴'에서 고기를 주문하세요", { color = C.sub, size = 14, h = 44 })
	end
	for _, pc in pieces do
		local row = UI.frame(body, { Size = UDim2.new(1, 0, 0, 96), BackgroundColor3 = if pc.grill then C.bg3 else C.bg2 })
		UI.corner(row, 10)
		local name = UI.label(row, (if pc.grill then "🔥 " else "🍽️ ") .. tostring(pc.name or "고기") .. (if pc.grill then (if pc.flipped then " (뒤집음)" else " (불판 위)") else " (접시)"), { size = 14, bold = true })
		name.Position = UDim2.new(0, 10, 0, 4)
		name.Size = UDim2.new(1, -20, 0, 22)
		local w = (row.AbsoluteSize.X > 0 and row.AbsoluteSize.X or 400) - 30
		bar(row, 10, math.floor(w / 2), "앞면", tonumber(pc.a) or 0)
		bar(row, 20 + math.floor(w / 2), math.floor(w / 2), "뒷면", tonumber(pc.b) or 0)
		local btns = UI.frame(row, { BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, 54), Size = UDim2.new(1, -20, 0, 36) })
		UI.list(btns, 6, true)
		UI.button(btns, if pc.grill then "접시로" else "불판에 올리기", function()
			act("grill", pc.id)
		end, { style = "ghost", size = UDim2.new(0.32, 0, 1, 0), textSize = 13 })
		if pc.grill then
			UI.button(btns, "🔄 뒤집기", function()
				act("flip", pc.id)
			end, { style = "primary", size = UDim2.new(0.32, 0, 1, 0), textSize = 13 })
		end
		local ready = (tonumber(pc.a) or 0) >= 0.6 and (tonumber(pc.b) or 0) >= 0.6
		UI.button(btns, if ready then "😋 먹기" else "덜 익음", function()
			act("eat", pc.id)
		end, { style = if ready then "ok" else "ghost", size = UDim2.new(0.32, 0, 1, 0), textSize = 13 })
	end
end

local function menuTab(body: Instance)
	for _, it in (state.d.menu or {}) do
		UI.row(body, {
			title = it.name,
			sub = if it.meat then "주문하면 직원이 가져다 드려요 (" .. tostring(Shared.Config.BBQ_PIECES) .. "점)" else "바로 나와요",
			right = Util.won(it.price),
			onClick = function()
				local res = act("order", nil, { item = it.id, qty = 1 })
				if res.ok then
					state.tab = "grill"
					render()
				end
			end,
		})
	end
end

render = function()
	if not state then
		return
	end
	if not sheet or not sheet.isOpen() then
		sheet = UI.sheet({
			title = "🥩 " .. tostring(state.d.title or "숯불갈비") .. " · " .. tostring(state.d.tableId or "") .. "번 테이블",
			sub = "",
			h = 460,
			w = 480,
			footer = true,
			kind = "bbq",
			onClose = function()
				sheet = nil
			end,
		})
		UI.button(sheet.footer, "🔥 불판", function()
			state.tab = "grill"
			render()
		end, { style = "ghost", size = UDim2.new(0.3, 0, 0, 46) })
		UI.button(sheet.footer, "📋 메뉴", function()
			state.tab = "menu"
			render()
		end, { style = "ghost", size = UDim2.new(0.3, 0, 0, 46) })
		UI.button(sheet.footer, "다 먹었어요", function()
			UI.toast("🧾 나가는 길에 카운터에서 계산해 주세요", "info")
			sheet.close()
		end, { style = "gold", size = UDim2.new(0.34, 0, 0, 46) })
	end
	sheet.setSub(string.format("현재 주문 금액 %s · 후불 (카운터에서 계산)", Util.won(tonumber(state.bill) or 0)))
	sheet.clear()
	if state.tab == "menu" then
		menuTab(sheet.body)
	else
		grillTab(sheet.body)
	end
end

function BbqView.open(d: any)
	state = { d = d, pieces = {}, bill = d.bill or 0, tab = "menu" }
	sheet = nil
	render()
end

function BbqView.start(Screens: any)
	Screens.views.bbq = BbqView.open
	Net.on("bbq.state", function(d)
		if not state then
			return
		end
		state.pieces = d.pieces or {}
		state.bill = d.bill or state.bill
		if sheet and sheet.isOpen() and state.tab == "grill" then
			render()
		end
	end)
end

return BbqView
