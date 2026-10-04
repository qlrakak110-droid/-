--!nocheck
-- GwangalliJobs/Delivery: the compact DELIVERY CHIP (광안 딜리버리 퀵 / 택배, and the legacy rider
-- orders): "<건물> <호수> - 배달요망", live distance, the tip timer, pay (+ tip), 택배 drop n/N and red
-- lights. Sits in the Layout "bottomCenter" band (clear of the thumbstick and jump zones); the phone's
-- tracker arrow points at WorkState.task.position. The legacy "차 부르기" button only for old rider
-- orders (퀵 is on foot, 택배 has its 탑차). One 0.5 s loop while the chip is visible.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Delivery = {}

local J: any
local K: any
local gui: ScreenGui

local card: Frame? = nil
local tile: Frame
local line1: TextLabel
local line2: TextLabel
local payLabel: TextLabel
local timerLabel: TextLabel
local carBtn: TextButton? = nil
local state: any = nil -- { phase, order, deadline }
local serial = 0
local layoutConn: RBXScriptConnection? = nil

function Delivery.init(ctx: any)
	J = ctx
	K = ctx.K
	gui = ctx.gui
end

local function callCarRemote(): RemoteFunction?
	local f = ReplicatedStorage:FindFirstChild("GwangalliVehiclesRemotes")
	local r = f and f:FindFirstChild("CallCar")
	return if r and r:IsA("RemoteFunction") then r else nil
end

local function place()
	if not card then
		return
	end
	local W, H = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	local w = math.min(math.max(260, W - 32), 420)
	local ok, r = pcall(function()
		return J.Layout and J.Layout.rect("bottomCenter")
	end)
	if ok and type(r) == "table" and r.w and r.w > 100 then
		w = math.min(w, r.w)
		card.AnchorPoint = Vector2.new(0.5, 1)
		card.Position = UDim2.fromOffset(r.x + r.w / 2, r.y + r.h)
	else
		card.AnchorPoint = Vector2.new(0.5, 1)
		card.Position = UDim2.new(0.5, 0, 1, -(if H > W then 130 else 16))
	end
	card.Size = UDim2.fromOffset(w, 60)
end

local function build()
	if card then
		return
	end
	card = K.Card(gui, { Name = "DeliveryChip", Size = UDim2.fromOffset(340, 60), Visible = false, ZIndex = 5, Radius = K.Radius.lg })
	K.stroke(card, K.Color.teal, 1, 0.5)
	tile = K.iconTile(card, 40, "🛵", K.Color.teal)
	tile.Position = UDim2.fromOffset(10, 10)
	line1 = K.text(card, { Name = "Line1", Position = UDim2.fromOffset(58, 9), Size = UDim2.new(1, -176, 0, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	line2 = K.text(card, { Name = "Line2", Position = UDim2.fromOffset(58, 31), Size = UDim2.new(1, -176, 0, 17), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	payLabel = K.text(card, { Name = "Pay", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -62, 0, 9), Size = UDim2.fromOffset(100, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextColor3 = K.Color.green, TextXAlignment = Enum.TextXAlignment.Right })
	K.mono(payLabel)
	timerLabel = K.text(card, { Name = "Timer", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -62, 0, 31), Size = UDim2.fromOffset(100, 17), Text = "", Font = K.Font.bold, TextSize = K.Type.caption, TextColor3 = K.Color.gold, TextXAlignment = Enum.TextXAlignment.Right })
	K.mono(timerLabel)
	carBtn = K.IconButton(card, {
		name = "CallCar",
		icon = "🚗",
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -8, 0.5, 0),
		size = UDim2.fromOffset(44, 44),
		onClick = function()
			local r = callCarRemote()
			if not r then
				J.toast({ kind = "info", title = "차량 시스템 준비 중", body = "지금은 걸어서 배달해요" })
				return
			end
			task.spawn(function()
				local ok, res = pcall(r.InvokeServer, r, "call", "compact")
				if ok and type(res) == "table" then
					if res.ok then
						local label, dist = tostring(res.msg or ""):match("^(.-)|(%d+)$")
						J.toast({ kind = "success", title = "🚗 차가 왔어요", body = if label then string.format("%s · %sm 앞 도로", label, dist) else tostring(res.msg or "") })
					else
						J.toast({ kind = "warn", title = "차를 부를 수 없어요", body = tostring(res.msg or "") })
					end
				elseif not ok then
					J.toast({ kind = "info", title = "차량 시스템 준비 중", body = "지금은 걸어서 배달해요" })
				end
			end)
		end,
	})
	place()
	layoutConn = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	local function bindCamera()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(place)
		end
	end
	bindCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	if J.Layout and J.Layout.changed then
		pcall(function()
			J.Layout.changed:Connect(place)
		end)
	end
end

local function mmss(sec: number): string
	local s = math.max(0, math.floor(sec + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function refresh()
	if not card or not state then
		return
	end
	local o = state.order or {}
	local glyph = tile:FindFirstChild("Glyph") :: TextLabel?
	if glyph then
		glyph.Text = tostring(o.icon or (if state.mode == "parcel" then "🚚" else "🛵"))
	end
	if state.mode == "quick" or state.mode == "parcel" then
		K.setText(line1, tostring(o.room or o.name or "배달지"))
		local where = o.ring or o.pos
		local dist = ""
		local rp = J.rootPos()
		if typeof(where) == "Vector3" and rp then
			dist = K.meters((Vector3.new(where.X, 0, where.Z) - Vector3.new(rp.X, 0, rp.Z)).Magnitude)
		end
		local parts = {}
		if dist ~= "" then
			table.insert(parts, "📍 " .. dist)
		end
		if state.mode == "parcel" and state.drops then
			table.insert(parts, string.format("택배 %d/%d", state.drop or 1, state.drops))
			table.insert(parts, if state.truck then "🚚 탑차로 원 안에 대기" else "🚶 원 안으로")
		else
			table.insert(parts, "손님께 직접 전달")
		end
		if (state.redLights or 0) > 0 then
			table.insert(parts, string.format("🚦x%d", state.redLights))
		end
		K.setText(line2, table.concat(parts, " · "))
	elseif state.phase == "pickup" then
		K.setText(line1, string.format("픽업 → %s", tostring(o.pickup or "")))
		K.setText(line2, string.format("%s · %s 손님", tostring(o.dish or ""), tostring(o.customer or "")))
		K.setText(timerLabel, "가방 비어 있음")
		timerLabel.TextColor3 = K.Color.faint
	elseif state.phase == "picked" or state.phase == "deliver" then
		K.setText(line1, string.format("배달 → %s", tostring(o.drop or "")))
		K.setText(line2, string.format("%s · 팁 +%s", tostring(o.dish or ""), K.won(tonumber(o.tip) or 0)))
	end
	K.setText(payLabel, K.won(tonumber(o.pay) or 0) .. (if (tonumber(o.tip) or 0) > 0 then "+" else ""))
	if carBtn then
		carBtn.Visible = state.mode == nil and callCarRemote() ~= nil
		local right = if carBtn.Visible then 62 else 12
		payLabel.Position = UDim2.new(1, -right, 0, 9)
		timerLabel.Position = UDim2.new(1, -right, 0, 31)
		line1.Size = UDim2.new(1, -(right + 114), 0, 20)
		line2.Size = UDim2.new(1, -(right + 114), 0, 17)
	end
end

local function startTimer()
	serial += 1
	local mine = serial
	task.spawn(function()
		while serial == mine and card and card.Visible and state do
			if state.mode then
				refresh()
			end
			if state.deadline then
				local left = state.deadline - os.clock()
				K.setText(timerLabel, if left > 0 then "⏱ " .. mmss(left) else "⏱ 팁 시간 지남")
				timerLabel.TextColor3 = if left <= 0 then K.Color.faint elseif left < 20 then K.Color.red elseif left < 45 then K.Color.orange else K.Color.gold
			end
			task.wait(0.5)
		end
	end)
end

function Delivery.update(p: any)
	build()
	if p.phase == "done" then
		Delivery.hide()
		return
	end
	if p.mode == "parcel" and p.phase == "loaded" then
		-- the route is planned; the first drop arrives with "deliver"
		J.toast({ kind = "job", title = if p.truck then "🚚 탑차 준비 완료" else "📦 상차 완료", body = string.format("택배 %d건 · %s", tonumber(p.drops) or 0, if p.truck then "차고의 탑차를 타고 출발!" else "탑차가 없어 걸어서/아무 차로 배달해요"), icon = "🚚" })
		return
	end
	if not p.order then
		Delivery.hide()
		return
	end
	local deadline = nil
	if p.mode then
		if p.phase == "deliver" and tonumber(p.timeLimit) then
			deadline = os.clock() + tonumber(p.timeLimit)
		elseif p.phase == "picked" and tonumber(p.order.timeLimit) then
			deadline = os.clock() + tonumber(p.order.timeLimit)
		end
		if state and state.mode == p.mode and p.phase == "deliver" and state.phase == "picked" and state.deadline then
			deadline = state.deadline -- 퀵: the deliver task follows the pickup at once
		end
	elseif (p.phase == "picked" or p.phase == "deliver") and tonumber(p.timeLimit) then
		if state and state.deadline and (state.phase == "picked" or state.phase == "deliver") then
			deadline = state.deadline
		else
			deadline = os.clock() + tonumber(p.timeLimit)
		end
	elseif state and state.deadline and p.phase == "deliver" then
		deadline = state.deadline
	end
	if p.phase == "picked" and not deadline and p.order and tonumber(p.order.timeLimit) then
		deadline = os.clock() + tonumber(p.order.timeLimit)
	end
	local reds = state and state.redLights or 0
	state = { phase = p.phase, order = p.order, deadline = deadline, mode = p.mode, drop = p.drop, drops = p.drops, truck = p.truck, redLights = reds }
	local wasVisible = card.Visible
	card.Visible = true
	place()
	refresh()
	if not wasVisible then
		K.springIn(card, 0.9, { amount = 0.2, duration = 0.35 })
	elseif p.phase == "picked" or p.phase == "deliver" then
		pcall(K.sheen, card, { duration = 0.7 })
	end
	startTimer()
end

-- 🚦 a red light was run (server: JobDelivery)
function Delivery.redlight(p: any)
	if state then
		state.redLights = tonumber(p.total) or ((state.redLights or 0) + 1)
		refresh()
	end
	if card and card.Visible then
		local st = card:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = K.Color.red
			st.Transparency = 0
			K.tween(st, 0.8, { Transparency = 0.5 })
			task.delay(0.9, function()
				if st.Parent then
					st.Color = K.Color.teal
				end
			end)
		end
		task.spawn(function()
			local base = card.Position
			for _, dx in { 8, -8, 5, -5, 0 } do
				card.Position = base + UDim2.fromOffset(dx, 0)
				task.wait(0.03)
			end
			card.Position = base
		end)
	end
	pcall(K.feedback, "error")
end

function Delivery.result(_p: any)
	-- the pay pills (Stage.flashResult) say it; the chip waits for the next order
end

-- WorkState: a deliver task carries its own timeLimit; keep the chip's deadline in step
function Delivery.onWork(data: any)
	if not state or not card or not card.Visible then
		return
	end
	local t = type(data) == "table" and data.task or nil
	if type(t) == "table" and t.kind == "deliver" and tonumber(t.timeLimit) and state.phase == "pickup" then
		state.phase = "deliver"
		state.deadline = os.clock() + tonumber(t.timeLimit)
		refresh()
	end
end

function Delivery.hide()
	serial += 1
	state = nil
	if card then
		card.Visible = false
	end
end

function Delivery.isVisible(): boolean
	return card ~= nil and card.Visible
end

return Delivery
