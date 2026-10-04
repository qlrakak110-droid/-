-- GwangalliProgress/Payday: the "오늘의 정산" phone-style card at the end of each in-game day (번 돈 /
-- 쓴 돈 / 남은 돈 with count-ups + a 7-day bar chart), shown in the top-right slot for a few seconds
-- (tap -> the sheet's 정산 tab), and the chart builder the sheet reuses. Waits while the HUD is hidden
-- or a shift is running.

local Payday = {}

local C: any = nil
local K: any = nil
local P: any = nil

local card: TextButton? = nil
local cardScale: UIScale
local queued: any = nil
local showing = false
local serial = 0

local CARD_W, CARD_H = 260, 126

-------------------------------------------------------------------------------------------------
-- Chart: bars for the last days (earned up, spent down from a centre line). history = {dayView...}
-- opts {height, highlight (day number), compact}. Returns the holder frame.
-------------------------------------------------------------------------------------------------
function Payday.chart(parent: Instance, history: { any }, opts: { [string]: any }?): Frame
	local o = opts or {}
	local h = o.height or 70
	local holder = K.frame(parent, { Name = "PayChart", Size = UDim2.new(1, 0, 0, h), LayoutOrder = o.order or 0, ZIndex = o.zIndex or 2 })
	local z = holder.ZIndex
	local list = {}
	for _, x in history or {} do
		if type(x) == "table" then
			table.insert(list, x)
		end
	end
	while #list > P.HISTORY_DAYS do
		table.remove(list, 1)
	end
	local maxV = 1
	for _, x in list do
		maxV = math.max(maxV, tonumber(x.e) or 0, tonumber(x.s) or 0)
	end
	local labelH = if o.compact then 0 else 13
	local mid = math.floor((h - labelH) * 0.62)
	local upH = mid - 2
	local downH = (h - labelH) - mid - 2
	K.frame(holder, { Name = "Axis", Position = UDim2.fromOffset(0, mid), Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0.82, BackgroundColor3 = K.Color.text, ZIndex = z })
	local n = math.max(#list, 1)
	local slotW = 1 / P.HISTORY_DAYS
	local offset = P.HISTORY_DAYS - n
	for i, x in list do
		local col = K.frame(holder, { Name = "Day" .. i, Position = UDim2.new((offset + i - 1) * slotW, 0, 0, 0), Size = UDim2.new(slotW, 0, 1, 0), ZIndex = z })
		local isHi = o.highlight ~= nil and x.d == o.highlight
		local e = tonumber(x.e) or 0
		local s = tonumber(x.s) or 0
		local eh = math.max(if e > 0 then 3 else 0, math.floor(upH * e / maxV))
		local sh = math.max(if s > 0 then 2 else 0, math.floor(downH * s / maxV))
		local bw = UDim2.new(0.56, 0, 0, eh)
		local up = K.frame(col, { Name = "Earn", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, mid), Size = UDim2.new(0.56, 0, 0, 0), BackgroundTransparency = if isHi then 0 else 0.25, BackgroundColor3 = K.Color.green, ZIndex = z + 1 })
		K.corner(up, 3)
		local down = K.frame(col, { Name = "Spend", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, mid + 1), Size = UDim2.new(0.56, 0, 0, 0), BackgroundTransparency = if isHi then 0.05 else 0.35, BackgroundColor3 = K.Color.red, ZIndex = z + 1 })
		K.corner(down, 3)
		local delay = (i - 1) * 0.03
		K.tweenD(up, 0.42, { Size = bw }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, delay)
		K.tweenD(down, 0.42, { Size = UDim2.new(0.56, 0, 0, sh) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, delay + 0.05)
		if not o.compact then
			K.text(col, { Name = "Label", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0, 12), Text = if isHi then "오늘" else (tostring(x.d) .. "일"), TextSize = 11, TextColor3 = if isHi then K.Color.text else K.Color.faint, Font = if isHi then K.Font.bold else K.Font.medium, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 1 })
		end
	end
	if #list == 0 then
		K.text(holder, { Name = "Empty", Size = UDim2.fromScale(1, 1), Text = "아직 기록이 없어요", TextSize = 12, TextColor3 = K.Color.faint, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 1 })
	end
	return holder
end

-------------------------------------------------------------------------------------------------
-- The card
-------------------------------------------------------------------------------------------------
local function stat(parent: Instance, x: number, title: string, color: Color3, name: string): TextLabel
	local f = K.frame(parent, { Name = name, Position = UDim2.new(x, 0, 0, 0), Size = UDim2.new(1 / 3, -4, 1, 0), ZIndex = 52 })
	K.text(f, { Name = "Title", Size = UDim2.new(1, 0, 0, 13), Text = title, TextSize = 11, TextColor3 = K.Color.sub, ZIndex = 52 })
	local v = K.text(f, { Name = "Value", Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 18), Text = "0", TextSize = 15, Font = K.Font.bold, TextColor3 = color, ZIndex = 52, TextTruncate = Enum.TextTruncate.AtEnd })
	K.mono(v, Enum.FontWeight.Bold)
	return v
end

local function build()
	local b = K.make("TextButton", { Name = "PaydayCard", AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = K.Color.glass2, BackgroundTransparency = 0.04, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 50 }, C.hud)
	cardScale = K.make("UIScale", { Scale = 1 }, b)
	K.corner(b, K.Radius.lg)
	K.stroke(b, K.Color.gold, 1.5, 0.45)
	-- phone-style status strip
	local top = K.frame(b, { Name = "Top", Size = UDim2.new(1, 0, 0, 26), ZIndex = 51 })
	K.pad(top, 12, 12, 6, 0)
	K.text(top, { Name = "Title", Size = UDim2.new(1, -60, 0, 18), Text = "📱 오늘의 정산", Font = K.Font.bold, TextSize = 14, ZIndex = 52 })
	K.text(top, { Name = "Day", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 70, 0, 18), Text = "", TextSize = 11, TextColor3 = K.Color.faint, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 52 })
	local nums = K.frame(b, { Name = "Numbers", Position = UDim2.fromOffset(12, 27), Size = UDim2.new(1, -24, 0, 33), ZIndex = 51 })
	stat(nums, 0, "번 돈", K.Color.green, "Earned")
	stat(nums, 1 / 3, "쓴 돈", Color3.fromRGB(255, 130, 130), "Spent")
	stat(nums, 2 / 3, "남은 돈", K.Color.gold, "Net")
	K.frame(b, { Name = "ChartHost", Position = UDim2.fromOffset(12, 62), Size = UDim2.new(1, -24, 0, 42), ZIndex = 51 })
	K.text(b, { Name = "Foot", Position = UDim2.fromOffset(12, CARD_H - 19), Size = UDim2.new(1, -24, 0, 14), Text = "", TextSize = 11, TextColor3 = K.Color.sub, ZIndex = 52, TextTruncate = Enum.TextTruncate.AtEnd })
	K.pressable(b, { scale = 0.97 })
	b.Activated:Connect(function()
		Payday.hide()
		if C.Panel then
			C.Panel.open("pay")
		end
	end)
	card = b
end

local function place()
	if not card then
		return
	end
	local s = C.Layout.metrics().s
	local r = C.Layout.rect("topRight")
	cardScale.Scale = s
	card.Position = UDim2.fromOffset(r.x + r.w, r.y)
	-- the slot may be short on landscape phones: shrink the card to fit
	local maxH = math.max(r.h, 120)
	if CARD_H * s > maxH then
		cardScale.Scale = maxH / CARD_H
	end
end

local function biggestCat(cats: any, names: any): string?
	local best, bestV = nil, 0
	for k, v in cats or {} do
		if type(v) == "number" and v > bestV then
			best, bestV = k, v
		end
	end
	if not best then
		return nil
	end
	return string.format("%s %s", names[best] or best, P.wonShort(bestV))
end

function Payday.hide()
	if not card or not showing then
		return
	end
	showing = false
	serial += 1
	local c = card
	K.tween(cardScale, 0.18, { Scale = cardScale.Scale * 0.92 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	K.tween(c, 0.18, { BackgroundTransparency = 1 })
	task.delay(0.19, function()
		if not showing then
			c.Visible = false
			c.BackgroundTransparency = 0.04
		end
	end)
end

local function canShow(): boolean
	if not C.visible() then
		return false
	end
	if C.player:GetAttribute("OnShift") == true then
		return false
	end
	if C.Panel and C.Panel.isOpen() then
		return false
	end
	return true
end

local function present(msg: any)
	if not card then
		build()
	end
	local c = card :: TextButton
	local day = msg.day or {}
	local hist = msg.history or {}
	place()
	local top = c:FindFirstChild("Top") :: Frame
	;(top:FindFirstChild("Day") :: TextLabel).Text = string.format("%d일차", tonumber(day.d) or 1)
	;(top:FindFirstChild("Title") :: TextLabel).Text = if msg.scope == "shift" then "📱 근무 정산" else "📱 오늘의 정산"
	local nums = c:FindFirstChild("Numbers") :: Frame
	local e = tonumber(day.e) or 0
	local s = tonumber(day.s) or 0
	local net = e - s
	K.countUp((nums:FindFirstChild("Earned") :: Frame):FindFirstChild("Value") :: TextLabel, e, { from = 0, prefix = "+", format = K.wonShort, duration = 0.7 })
	K.countUp((nums:FindFirstChild("Spent") :: Frame):FindFirstChild("Value") :: TextLabel, s, { from = 0, prefix = "-", format = K.wonShort, duration = 0.7 })
	local netLabel = (nums:FindFirstChild("Net") :: Frame):FindFirstChild("Value") :: TextLabel
	netLabel.TextColor3 = if net >= 0 then K.Color.gold else Color3.fromRGB(255, 130, 130)
	K.countUp(netLabel, math.abs(net), { from = 0, prefix = if net >= 0 then "+" else "-", format = K.wonShort, duration = 0.8 })
	local host = c:FindFirstChild("ChartHost") :: Frame
	for _, ch in host:GetChildren() do
		ch:Destroy()
	end
	Payday.chart(host, hist, { height = 42, highlight = day.d, compact = false, zIndex = 52 })
	local foot = c:FindFirstChild("Foot") :: TextLabel
	local parts = {}
	local topSpend = biggestCat(day.cats, P.SPEND_NAMES)
	if topSpend then
		table.insert(parts, "지출 1위 " .. topSpend)
	end
	local best = 0
	for _, x in hist do
		if type(x) == "table" and x.d ~= day.d then
			best = math.max(best, tonumber(x.e) or 0)
		end
	end
	if e > 0 and e > best and #hist > 1 then
		table.insert(parts, 1, "🔥 최고 기록!")
	end
	foot.Text = if #parts > 0 then table.concat(parts, " · ") else "탭해서 자세히 보기"
	-- enter
	local target = cardScale.Scale
	cardScale.Scale = target * 0.9
	c.BackgroundTransparency = 1
	c.Visible = true
	showing = true
	K.tween(cardScale, 0.24, { Scale = target }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	K.tween(c, 0.2, { BackgroundTransparency = 0.04 })
	K.sheen(c, { duration = 0.9, delay = 0.25, strength = 0.6 })
	C.Sfx.card()
	if net > 0 then
		task.delay(0.3, function()
			C.Sfx.coin(0.3)
		end)
	end
	serial += 1
	local mine = serial
	task.delay(9, function()
		if serial == mine then
			Payday.hide()
		end
	end)
end

local function tryQueued()
	if queued and canShow() then
		local m = queued
		queued = nil
		present(m)
	end
end

function Payday.show(msg: any)
	if canShow() then
		present(msg)
	else
		queued = msg
	end
end

function Payday.init(c: any)
	C = c
	K = c.K
	P = c.P
	c.on("payday", Payday.show)
	c.on("visible", function(v)
		if v then
			task.delay(1, tryQueued)
		else
			Payday.hide()
		end
	end)
	c.player:GetAttributeChangedSignal("OnShift"):Connect(function()
		task.delay(2.5, tryQueued)
	end)
	c.on("layout", place)
end

return Payday
