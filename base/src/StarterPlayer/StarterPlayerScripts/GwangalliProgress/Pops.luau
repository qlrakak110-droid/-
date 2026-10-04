-- GwangalliProgress/Pops: the "돈 버는 맛" feedback under the money chip.
--   * money pops: glass pill "+12,300원" (count-up, coin sound, category glyph, "급여 · GS25 광안리점 ·
--     오늘 5.8만원"), gold pill + rings + coins for big pays (P.POP.big / jackpot)
--   * goal cards ("일일 목표 달성!") and badge cards ("업적 달성 · 골드") in the same column
-- Newest on top, at most 3 on screen, all non-interactive (the column may overlap the thumbstick zone
-- on landscape phones, so nothing here is a tap target). Frames are pooled; while the HUD is hidden
-- (phone open, job round, a feature flow) incoming items wait and money pops merge into one.

local Pops = {}

local C: any = nil
local K: any = nil
local P: any = nil

type Item = { kind: string, data: any, frame: Frame?, h: number, born: number, ttl: number, gone: boolean }

local active: { Item } = {}
local pending: { Item } = {}
local pendingMoney: any = nil -- merged money while hidden
local popPool: { Frame } = {}
local cardPool: { Frame } = {}
local MAX_ON_SCREEN = 3
local GAP = 6

local POP_W, POP_H = 210, 42
local CARD_W, CARD_H = 248, 58

local function scaleOf(f: Frame): UIScale
	return f:FindFirstChildOfClass("UIScale") :: UIScale
end

-------------------------------------------------------------------------------------------------
-- Frames
-------------------------------------------------------------------------------------------------
local function newPop(): Frame
	local f = K.frame(C.hud, { Name = "MoneyPop", Size = UDim2.fromOffset(POP_W, POP_H), BackgroundTransparency = 0.08, BackgroundColor3 = K.Color.glass, Visible = false, ZIndex = 20 })
	K.make("UIScale", { Scale = 1 }, f)
	K.corner(f, 14)
	K.stroke(f, K.Color.green, 1.5, 0.35)
	local icon = K.iconTile(f, 28, "💼", K.Color.green, true)
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 7, 0.5, 0)
	icon.ZIndex = 21
	for _, d in icon:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 21
		end
	end
	local amt = K.text(f, { Name = "Amount", Position = UDim2.fromOffset(42, 4), Size = UDim2.new(1, -50, 0, 20), Text = "+0원", Font = K.Font.bold, TextSize = 17, TextColor3 = K.Color.green, ZIndex = 21 })
	K.mono(amt, Enum.FontWeight.Bold)
	K.text(f, { Name = "Sub", Position = UDim2.fromOffset(42, 23), Size = UDim2.new(1, -50, 0, 14), Text = "", TextSize = 11, TextColor3 = K.Color.sub, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 21 })
	table.insert(popPool, f)
	return f
end

local function newCard(): Frame
	local f = K.frame(C.hud, { Name = "ProgressCard", Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundTransparency = 0.06, BackgroundColor3 = K.Color.glass2, Visible = false, ZIndex = 20 })
	K.make("UIScale", { Scale = 1 }, f)
	K.corner(f, 16)
	K.stroke(f, K.Color.gold, 1.5, 0.3)
	local medal = K.frame(f, { Name = "Medal", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 21 })
	K.corner(medal, UDim.new(0.5, 0))
	K.gradient(medal, K.Grad.gold, 125)
	K.stroke(medal, Color3.new(1, 1, 1), 1.5, 0.45)
	K.text(medal, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "🎯", TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
	K.text(f, { Name = "Title", Position = UDim2.fromOffset(58, 6), Size = UDim2.new(1, -66, 0, 15), Text = "", Font = K.Font.bold, TextSize = 12, TextColor3 = K.Color.gold, ZIndex = 21, TextTruncate = Enum.TextTruncate.AtEnd })
	K.text(f, { Name = "Body", Position = UDim2.fromOffset(58, 21), Size = UDim2.new(1, -66, 0, 17), Text = "", Font = K.Font.bold, TextSize = 14, ZIndex = 21, TextTruncate = Enum.TextTruncate.AtEnd })
	local reward = K.text(f, { Name = "Reward", Position = UDim2.fromOffset(58, 38), Size = UDim2.new(1, -66, 0, 14), Text = "", TextSize = 11, TextColor3 = K.Color.green, ZIndex = 21, TextTruncate = Enum.TextTruncate.AtEnd })
	K.mono(reward)
	table.insert(cardPool, f)
	return f
end

local function take(kind: string): Frame
	local pool = if kind == "money" then popPool else cardPool
	for _, f in pool do
		if not f.Visible and not f:GetAttribute("InUse") then
			f:SetAttribute("InUse", true)
			return f
		end
	end
	local f = if kind == "money" then newPop() else newCard()
	f:SetAttribute("InUse", true)
	return f
end

local function setAlpha(f: Frame, a: number, instant: boolean?, t: number?)
	-- a = 0 shown, 1 hidden
	local dur = t or 0.2
	local base = if f.Name == "MoneyPop" then 0.08 else 0.06
	local goals = { BackgroundTransparency = base + (1 - base) * a }
	local st = f:FindFirstChildOfClass("UIStroke")
	if instant then
		f.BackgroundTransparency = goals.BackgroundTransparency
	else
		K.tween(f, dur, goals)
	end
	if st then
		if instant then
			st.Transparency = 0.3 + 0.7 * a
		else
			K.tween(st, dur, { Transparency = 0.3 + 0.7 * a })
		end
	end
	for _, d in f:GetDescendants() do
		if d:IsA("TextLabel") then
			if instant then
				d.TextTransparency = a
			else
				K.tween(d, dur, { TextTransparency = a })
			end
		elseif d:IsA("Frame") and d.Name ~= "SheenBand" then
			local rest = d:GetAttribute("RestT")
			if rest == nil then
				rest = d.BackgroundTransparency
				d:SetAttribute("RestT", rest)
			end
			local target = rest + (1 - rest) * a
			if instant then
				d.BackgroundTransparency = target
			else
				K.tween(d, dur, { BackgroundTransparency = target })
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Stack layout
-------------------------------------------------------------------------------------------------
local function geometry(): any
	return C.geometry()
end

local function slotY(index: number): number
	local g = geometry()
	local y = g.stackY
	for i = 1, index - 1 do
		local it = active[i]
		if it then
			y += it.h * g.s + GAP
		end
	end
	return y
end

local function relayout(animate: boolean)
	local g = geometry()
	for i, it in active do
		local f = it.frame
		if f then
			scaleOf(f).Scale = g.s
			local pos = UDim2.fromOffset(g.stackX, slotY(i))
			if animate then
				K.tween(f, 0.22, { Position = pos }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			else
				f.Position = pos
			end
		end
	end
end

local function remove(it: Item)
	if it.gone then
		return
	end
	it.gone = true
	local idx = table.find(active, it)
	if idx then
		table.remove(active, idx)
	end
	local f = it.frame
	if f then
		local p = f.Position
		setAlpha(f, 1, false, 0.2)
		K.tween(f, 0.2, { Position = UDim2.new(p.X.Scale, p.X.Offset - (if it.kind == "money" then 0 else 24), p.Y.Scale, p.Y.Offset - (if it.kind == "money" then 14 else 0)) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.22, function()
			f.Visible = false
			f:SetAttribute("InUse", nil)
		end)
	end
	relayout(true)
end

-------------------------------------------------------------------------------------------------
-- Money
-------------------------------------------------------------------------------------------------
local CAT_COLOR: { [string]: Color3 } = {}
local function catColor(cat: string): Color3
	local c = CAT_COLOR[cat]
	if c then
		return c
	end
	local rgb = P.CAT_COLORS[cat]
	c = if rgb then Color3.fromRGB(rgb[1], rgb[2], rgb[3]) else K.Color.green
	CAT_COLOR[cat] = c
	return c
end

local OTHER_NAMES = { transfer = "받은 돈", refund = "돌려받은 돈", asset = "판매 대금", loan = "대출금" }

local function shortLabel(label: string?): string
	local l = if type(label) == "string" then label else ""
	-- "급여 · 광안리 GS25점 (근무 완료)" -> "급여 · 광안리 GS25점"
	l = (string.gsub(l, "%s*%b()", ""))
	return l
end

local function fillMoney(f: Frame, d: any)
	local amt = f:FindFirstChild("Amount") :: TextLabel
	local sub = f:FindFirstChild("Sub") :: TextLabel
	local icon = f:FindFirstChild("Icon") :: Frame
	local counts = d.count ~= false
	local big = tonumber(d.big) or 0
	local color = if big > 0 then K.Color.gold elseif counts then K.Color.green else K.Color.cyan
	amt.TextColor3 = color
	local st = f:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = color
		st.Thickness = if big > 0 then 2 else 1.5
	end
	local glyph = P.POP_GLYPH[d.cat] or "💰"
	local glyphLabel = icon and icon:FindFirstChild("Glyph") :: TextLabel?
	if glyphLabel then
		glyphLabel.Text = glyph
	end
	local grad = icon and icon:FindFirstChildOfClass("UIGradient")
	if grad then
		local c = if big > 0 then K.Color.gold else catColor(d.cat)
		grad.Color = ColorSequence.new(c:Lerp(Color3.new(1, 1, 1), 0.12), c:Lerp(Color3.new(0, 0, 0), 0.22))
	end
	local label = shortLabel(d.label)
	if label == "" then
		label = OTHER_NAMES[d.cat] or (P.EARN_NAMES[d.cat] or "수입")
	end
	if (tonumber(d.n) or 1) > 1 then
		label = string.format("%s 외 %d건", label, d.n - 1)
	end
	if counts and (tonumber(d.today) or 0) > (tonumber(d.amt) or 0) then
		label = string.format("%s · 오늘 %s", label, P.wonShort(d.today))
	end
	sub.Text = label
	local finalText = "+" .. K.won(d.amt or 0)
	local w = math.max(K.textSize(finalText, 17, K.Font.bold).X + 8, math.min(K.textSize(label, 11).X + 4, 190))
	f.Size = UDim2.fromOffset(math.clamp(math.ceil(w) + 52, 150, 250), POP_H)
	return amt, finalText
end

local function showMoney(it: Item)
	local d = it.data
	local f = take("money")
	it.frame = f
	it.h = POP_H
	local amtLabel = fillMoney(f, d)
	local big = tonumber(d.big) or 0
	local g = geometry()
	scaleOf(f).Scale = g.s * 0.86
	setAlpha(f, 1, true)
	f.Position = UDim2.fromOffset(g.stackX, g.stackY + 18)
	f.Visible = true
	table.insert(active, 1, it)
	while #active > MAX_ON_SCREEN do
		remove(active[#active])
	end
	relayout(true)
	setAlpha(f, 0, false, 0.2)
	K.tween(scaleOf(f), 0.24, { Scale = g.s }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local amount = tonumber(d.amt) or 0
	K.countUp(amtLabel, amount, { from = 0, prefix = "+", suffix = "원", duration = if big > 0 then 0.9 else 0.5 })
	local Sfx = C.Sfx
	Sfx.coin(math.clamp(amount / 100000, 0, 1))
	local ticks = if big > 0 then 7 else 4
	for i = 1, ticks do
		task.delay(0.06 + i * (if big > 0 then 0.11 else 0.09), Sfx.tick)
	end
	pcall(K.haptic, "money")
	-- chip landing glow (rings around the money chip's coin)
	local cx = g.chip.x + math.floor(22 * g.s)
	local cy = g.chip.y + math.floor(g.chip.h / 2)
	if big > 0 then
		task.delay(0.12, Sfx.gold)
		K.sheen(f, { duration = 0.9, delay = 0.2, strength = 0.35 })
		if C.Fx then
			C.Fx.rings(cx, cy, K.Color.gold, C.hud, math.floor(110 * g.s))
			if big >= 2 then
				C.Fx.coins(g.stackX + 60 * g.s, slotY(1) + 20 * g.s, cx, cy, 8, C.hud)
				C.Fx.confetti(g.stackX + 90 * g.s, slotY(1) + 10 * g.s, 16, 90)
			end
		end
		local sc = scaleOf(f)
		task.delay(0.3, function()
			if not it.gone then
				K.tween(sc, 0.12, { Scale = g.s * 1.1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				task.delay(0.12, function()
					K.tween(sc, 0.22, { Scale = g.s }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				end)
			end
		end)
	elseif C.Fx then
		task.delay(0.35, function()
			C.Fx.rings(cx, cy, if d.count ~= false then K.Color.green else K.Color.cyan, C.hud, math.floor(70 * g.s))
		end)
	end
	if C.Chip and C.Chip.bump then
		task.delay(0.4, C.Chip.bump)
	end
	it.ttl = if big >= 2 then 3.4 elseif big > 0 then 2.8 else 2.1
	task.delay(it.ttl, remove, it)
end

-------------------------------------------------------------------------------------------------
-- Goal / badge cards
-------------------------------------------------------------------------------------------------
local function tierColor(tier: string?): (Color3, { Color3 })
	local t = tier and P.TIERS[tier]
	if not t then
		return K.Color.gold, K.Grad.gold
	end
	local c = Color3.fromRGB(t.color[1], t.color[2], t.color[3])
	return c, { c:Lerp(Color3.new(1, 1, 1), 0.25), c:Lerp(Color3.new(0, 0, 0), 0.3) }
end

local function showCard(it: Item)
	local d = it.data
	local f = take("card")
	it.frame = f
	it.h = CARD_H
	local medal = f:FindFirstChild("Medal") :: Frame
	local title = f:FindFirstChild("Title") :: TextLabel
	local body = f:FindFirstChild("Body") :: TextLabel
	local reward = f:FindFirstChild("Reward") :: TextLabel
	local glyph = medal:FindFirstChild("Glyph") :: TextLabel
	local grad = medal:FindFirstChildOfClass("UIGradient") :: UIGradient
	local st = f:FindFirstChildOfClass("UIStroke") :: UIStroke
	local rewardText = ""
	if it.kind == "goal" then
		local goal = d.goal or {}
		local weekly = goal.weekly == true
		title.Text = if weekly then "🗓️ 주간 목표 달성!" elseif d.allDone then "🎉 오늘 목표 올클리어!" else "✅ 일일 목표 달성!"
		title.TextColor3 = if weekly then K.Color.violet else K.Color.green
		body.Text = tostring(goal.text or "")
		glyph.Text = tostring(goal.icon or "🎯")
		local c = if weekly then K.Color.violet else K.Color.green
		grad.Color = ColorSequence.new(c:Lerp(Color3.new(1, 1, 1), 0.2), c:Lerp(Color3.new(0, 0, 0), 0.3))
		st.Color = c
		rewardText = "+" .. K.won(d.cash or 0)
		if (tonumber(d.pop) or 0) > 0 then
			rewardText ..= string.format(" · 인기 +%d", d.pop)
		end
		if d.bonus then
			rewardText ..= " · 올클 보너스 +" .. K.won(d.bonus)
		end
	else
		local tier = P.TIERS[d.tier]
		local c, g = tierColor(d.tier)
		title.Text = string.format("🏅 업적 달성 · %s", tier and tier.name or "")
		title.TextColor3 = c
		body.Text = tostring(d.name or "")
		glyph.Text = tostring(d.icon or "🏅")
		grad.Color = ColorSequence.new(g[1], g[2])
		st.Color = c
		rewardText = "+" .. K.won(d.cash or 0)
		if (tonumber(d.pop) or 0) > 0 then
			rewardText ..= string.format(" · 인기 +%d", d.pop)
		end
	end
	reward.Text = rewardText
	local w = math.max(K.textSize(body.Text, 14, K.Font.bold).X, K.textSize(title.Text, 12, K.Font.bold).X, K.textSize(rewardText, 11).X) + 74
	f.Size = UDim2.fromOffset(math.clamp(math.ceil(w), 200, 280), CARD_H)
	local g = geometry()
	scaleOf(f).Scale = g.s
	setAlpha(f, 1, true)
	f.Position = UDim2.fromOffset(math.max(0, g.stackX - 10), g.stackY)
	f.Visible = true
	table.insert(active, 1, it)
	while #active > MAX_ON_SCREEN do
		remove(active[#active])
	end
	relayout(true)
	setAlpha(f, 0, false, 0.22)
	-- medal pop
	local ms = medal:FindFirstChildOfClass("UIScale") or K.make("UIScale", { Scale = 1 }, medal)
	ms.Scale = 0.6
	K.tween(ms, 0.32, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(0.25, function()
		K.sheen(f, { duration = 0.8, strength = 0.5 })
	end)
	if it.kind == "goal" then
		C.Sfx.goal()
	else
		C.Sfx.badge()
		if C.Fx then
			local my = slotY(1) + CARD_H * g.s / 2
			C.Fx.rings(g.stackX + 29 * g.s, my, (tierColor(d.tier)), C.hud, math.floor(90 * g.s))
		end
	end
	pcall(K.haptic, "success")
	it.ttl = if d.allDone then 4.2 else 3.4
	task.delay(it.ttl, remove, it)
end

-------------------------------------------------------------------------------------------------
-- Queue
-------------------------------------------------------------------------------------------------
local function show(it: Item)
	if it.kind == "money" then
		showMoney(it)
	else
		showCard(it)
	end
end

local function push(kind: string, data: any)
	local it: Item = { kind = kind, data = data, frame = nil, h = 0, born = os.clock(), ttl = 0, gone = false }
	if not C.visible() then
		if kind == "money" and data.count ~= false then
			if pendingMoney then
				pendingMoney.amt += data.amt or 0
				pendingMoney.n = (pendingMoney.n or 1) + (data.n or 1)
				if (data.big or 0) > (pendingMoney.big or 0) then
					pendingMoney.big = data.big
				end
				if (data.amt or 0) >= (pendingMoney.maxAmt or 0) then
					pendingMoney.maxAmt = data.amt
					pendingMoney.label = data.label
					pendingMoney.cat = data.cat
				end
				pendingMoney.today = math.max(pendingMoney.today or 0, data.today or 0)
			else
				pendingMoney = table.clone(data)
				pendingMoney.maxAmt = data.amt
			end
		else
			table.insert(pending, it)
			while #pending > 8 do
				table.remove(pending, 1)
			end
		end
		return
	end
	show(it)
end

local function flushPending()
	if not C.visible() then
		return
	end
	local list = pending
	pending = {}
	local money = pendingMoney
	pendingMoney = nil
	local delay = 0.35
	if money then
		task.delay(delay, function()
			show({ kind = "money", data = money, frame = nil, h = 0, born = os.clock(), ttl = 0, gone = false })
		end)
		delay += 0.5
	end
	for _, it in list do
		task.delay(delay, function()
			if C.visible() then
				show(it)
			else
				table.insert(pending, it)
			end
		end)
		delay += 0.6
	end
end

function Pops.money(data: any)
	push("money", data)
end

function Pops.init(c: any)
	C = c
	K = c.K
	P = c.P
	c.on("pop", function(msg)
		push("money", msg)
	end)
	c.on("goal", function(msg)
		push("goal", msg)
	end)
	c.on("ach", function(msg)
		push("ach", msg)
	end)
	c.on("visible", function(v)
		if v then
			flushPending()
		end
	end)
	c.on("layout", function()
		relayout(false)
	end)
	c.on("chipmoved", function()
		relayout(false)
	end)
end

return Pops
