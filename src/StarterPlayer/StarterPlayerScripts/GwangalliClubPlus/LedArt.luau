-- GwangalliClubPlus.LedArt: the LED wall's takeover templates (client). Each template builds its
-- frames inside `host` and returns an animation object:
--   { frame, steps = { { t, fn(instant) } }, update(el, dt)?, setRank(info)?, dur }
-- Steps run in order when the item's elapsed time passes them (instant = joined late: no tween).
-- Templates: order (일반 / 프리미엄 / VIP / 레전드), donate, dj (LED text), djon (ON AIR), booking (합석 card),
-- band (tier-1 order strip). Names / messages come filtered from the server or the club's records.

local LedArt = {}

local Core: any
local S: any
local L: any

local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 194, 71)
local CYAN = Color3.fromRGB(61, 214, 245)
local MAGENTA = Color3.fromRGB(255, 79, 163)
local VIOLET = Color3.fromRGB(150, 70, 255)

function LedArt.init(core: any)
	Core = core
	S = core.S
	L = core.L.LED
end

local function lerpC(a: Color3, b: Color3, k: number): Color3
	return a:Lerp(b, math.clamp(k, 0, 1))
end
local function dark(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

-- shows `obj` with a tween (or at once when joined late)
local function to(obj: Instance, t: number, goals: { [string]: any }, instant: boolean, style: Enum.EasingStyle?)
	if instant or t <= 0 then
		for k, v in goals do
			(obj :: any)[k] = v
		end
	else
		Core.tween(obj, t, goals, style)
	end
end

local function pop(obj: GuiObject, instant: boolean, scale: number?)
	local sc = obj:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	sc.Parent = obj
	if instant then
		sc.Scale = 1
		return
	end
	sc.Scale = scale or 0.4
	Core.tween(sc, 0.32, { Scale = 1.08 }, Enum.EasingStyle.Back)
	task.delay(0.32, function()
		if sc.Parent then
			Core.tween(sc, 0.18, { Scale = 1 })
		end
	end)
end

local function money(n: number): string
	return "₩" .. S.commas(n)
end

-------------------------------------------------------------------------------------------------
-- shared pieces
-------------------------------------------------------------------------------------------------
local function base(host: Instance, c1: Color3, c2: Color3): (Frame, Frame, UIGradient)
	local frame = Core.frame(host, { Name = "Take", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true })
	local bg = Core.frame(frame, { Name = "Bg", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 1 })
	local grad = Instance.new("UIGradient")
	grad.Color = Core.seq(dark(c1, 0.16), dark(c2, 0.55), dark(c1, 0.16))
	grad.Rotation = 15
	grad.Parent = bg
	return frame, bg, grad
end

-- light rays turning behind the name
local function rays(frame: Frame, color: Color3, n: number, alpha: number): { Frame }
	local list = {}
	local holder = Core.frame(frame, { Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0, 0), BackgroundTransparency = 1, ZIndex = 2 })
	for i = 1, n do
		local r = Core.frame(holder, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromOffset(18, 900),
			BackgroundColor3 = color,
			BackgroundTransparency = alpha,
			Rotation = (i - 1) * 180 / n,
			ZIndex = 2,
		})
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = r
		table.insert(list, r)
	end
	return list
end

local function flash(frame: Frame, color: Color3?, instant: boolean)
	if instant then
		return
	end
	local f = Core.frame(frame, { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = color or WHITE, BackgroundTransparency = 0.1, ZIndex = 30 })
	Core.tween(f, 0.55, { BackgroundTransparency = 1 })
	task.delay(0.6, function()
		f:Destroy()
	end)
end

local function chip(parent: Instance, text: string, color: Color3, pos: UDim2, anchor: Vector2, w: number?): Frame
	local f = Core.frame(parent, {
		Name = "Chip",
		AnchorPoint = anchor,
		Position = pos,
		Size = UDim2.fromScale(w or 0.13, 0.11),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.15,
		corner = UDim.new(0.5, 0),
		ZIndex = 12,
	})
	Core.text(f, { Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1), Text = text, Font = Enum.Font.GothamBlack, ZIndex = 13, TextColor3 = Color3.fromRGB(12, 12, 24) })
	return f
end

-- twinkling sparkles (small rotated squares)
local function sparkles(frame: Frame, n: number, color: Color3): { any }
	local list = {}
	for i = 1, n do
		local s = Core.frame(frame, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(S.hash(i, 3), S.hash(i, 7)),
			Size = UDim2.fromOffset(5, 5),
			BackgroundColor3 = if i % 3 == 0 then color else WHITE,
			BackgroundTransparency = 1,
			Rotation = 45,
			ZIndex = 9,
		})
		table.insert(list, { f = s, ph = S.hash(i, 11) * 6.28, sp = 2 + S.hash(i, 13) * 4 })
	end
	return list
end

-- falling confetti
local CONF = { GOLD, MAGENTA, CYAN, VIOLET, WHITE, Color3.fromRGB(61, 220, 132) }
local function confetti(frame: Frame, n: number): { any }
	local list = {}
	for i = 1, n do
		local f = Core.frame(frame, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(S.hash(i, 21), -0.1),
			Size = UDim2.fromOffset(4 + math.floor(S.hash(i, 23) * 5), 7 + math.floor(S.hash(i, 29) * 6)),
			BackgroundColor3 = CONF[(i % #CONF) + 1],
			Visible = false,
			ZIndex = 20,
		})
		table.insert(list, { f = f, x = S.hash(i, 21), d = S.hash(i, 31) * 1.6, v = 0.18 + S.hash(i, 37) * 0.22, w = (S.hash(i, 41) - 0.5) * 0.08, r = S.hash(i, 43) * 360 })
	end
	return list
end
local function confettiStep(list: { any }, el: number, from: number)
	for _, c in list do
		local t = el - from - c.d
		if t > 0 then
			local y = -0.1 + t * c.v
			if y < 1.15 then
				c.f.Visible = true
				c.f.Position = UDim2.fromScale(c.x + math.sin(t * 3 + c.r) * 0.02 + c.w * t, y)
				c.f.Rotation = c.r + t * 220
			else
				c.f.Visible = false
			end
		end
	end
end

local function eq(frame: Frame, n: number, color: Color3, z: number): { Frame }
	local bars = {}
	for i = 1, n do
		local b = Core.frame(frame, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale((i - 1) / n + 0.002, 1),
			Size = UDim2.fromScale(1 / n - 0.004, 0.1),
			BackgroundColor3 = lerpC(color, WHITE, i / n * 0.5),
			BackgroundTransparency = 0.25,
			ZIndex = z,
		})
		table.insert(bars, b)
	end
	return bars
end
local function eqStep(bars: { Frame }, el: number, amp: number)
	local phase = Core.beat()
	local kick = (1 - phase) ^ 2
	for i, b in bars do
		local h = 0.05 + amp * (0.35 + 0.65 * math.abs(math.sin(el * 2.6 + i * 0.63))) * (0.55 + 0.45 * kick)
		b.Size = UDim2.new(b.Size.X.Scale, 0, math.clamp(h, 0.03, 0.95), 0)
	end
end

-- name with a moving shimmer gradient
local function bigName(frame: Frame, text: string, color: Color3, accent: Color3, y: number, h: number): (TextLabel, UIGradient)
	local t = Core.text(frame, {
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, y),
		Size = UDim2.fromScale(0.86, h),
		Text = text,
		TextTransparency = 1,
		ZIndex = 15,
		stroke = dark(color, 0.6),
	})
	local g = Instance.new("UIGradient")
	g.Color = Core.seq(accent, WHITE, accent, WHITE)
	g.Offset = Vector2.new(-1, 0)
	g.Parent = t
	return t, g
end

-------------------------------------------------------------------------------------------------
-- order takeover (ledTier 2..4)
-------------------------------------------------------------------------------------------------
function LedArt.order(host: Instance, d: any, tier: number, dur: number): any
	local T = S.tier(tier)
	local q = Core.q()
	local frame, bg, grad = base(host, T.color, T.accent)
	local rayList = rays(frame, T.accent, if tier >= 3 then 12 else 6, if tier >= 4 then 0.55 else 0.75)
	local spark = sparkles(frame, math.floor((if tier >= 4 then 30 elseif tier >= 3 then 20 else 10) * (if q.name == "high" then 1 elseif q.name == "mid" then 0.7 else 0.4)), T.accent)
	local conf = if tier >= 3 then confetti(frame, math.floor((if tier >= 4 then 34 else 18) * (if q.name == "high" then 1 elseif q.name == "mid" then 0.7 else 0.4))) else {}

	local head = Core.text(frame, {
		Name = "Head",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.5, 0.13),
		Size = UDim2.fromScale(0.7, 0.12),
		Text = L.orderHead[tier] or "ORDER",
		TextColor3 = T.accent,
		ZIndex = 14,
		stroke = dark(T.color, 0.5),
	})
	local crown: TextLabel? = nil
	if tier >= 4 then
		crown = Core.text(frame, { Name = "Crown", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, -0.3), Size = UDim2.fromScale(0.2, 0.3), Text = "👑", ZIndex = 16 })
	end
	local name, shimmer = bigName(frame, string.format("%s님", d.n or "손님"), T.color, T.accent, 0.42, 0.3)
	local user = Core.text(frame, {
		Name = "User",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromScale(0.4, 0.07),
		Text = if d.un then "@" .. d.un else "",
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(200, 215, 240),
		TextTransparency = 1,
		ZIndex = 14,
	})
	local info = Core.text(frame, {
		Name = "Info",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromScale(0.8, 0.1),
		Text = string.format("%s %s", d.icon or "✨", d.label or "음료 세트"),
		Font = Enum.Font.GothamBold,
		TextTransparency = 1,
		ZIndex = 14,
	})
	local amount = Core.text(frame, {
		Name = "Amount",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.88),
		Size = UDim2.fromScale(0.5, 0.13),
		Text = money(0),
		TextColor3 = GOLD,
		TextTransparency = 1,
		ZIndex = 14,
		stroke = Color3.fromRGB(60, 30, 0),
	})
	local tableChip = chip(frame, string.format("%s 테이블", d.table or "?"), T.accent, UDim2.fromScale(0.03, 0.06), Vector2.new(0, 0), 0.15)
	tableChip.Visible = false
	local tierChip = chip(frame, T.label, T.color, UDim2.fromScale(0.97, 0.06), Vector2.new(1, 0), 0.12)
	tierChip.Visible = false
	local rankChip: Frame? = nil

	local countFrom, countDur = 1.9, 1.3
	local api: any = { frame = frame, dur = dur }
	api.steps = {
		{ t = 0, fn = function(instant: boolean)
			to(bg, 0.25, { BackgroundTransparency = 0.04 }, instant)
			flash(frame, T.accent, instant)
		end },
		{ t = 0.12, fn = function(instant: boolean)
			to(head, 0.45, { Position = UDim2.fromScale(0.5, 0.13) }, instant, Enum.EasingStyle.Back)
		end },
		{ t = if tier >= 4 then 0.2 else 99, fn = function(instant: boolean)
			if crown then
				to(crown, 0.55, { Position = UDim2.fromScale(0.5, 0.3) }, instant, Enum.EasingStyle.Bounce)
			end
		end },
		{ t = if tier >= 4 then 1.1 else 0.55, fn = function(instant: boolean)
			if crown and not instant then
				Core.tween(crown, 0.4, { Position = UDim2.fromScale(0.5, 0.2), Size = UDim2.fromScale(0.1, 0.16) })
			elseif crown then
				crown.Position = UDim2.fromScale(0.5, 0.2)
				crown.Size = UDim2.fromScale(0.1, 0.16)
			end
			to(name, 0.2, { TextTransparency = 0 }, instant)
			pop(name, instant, 0.3)
			flash(frame, WHITE, instant or tier < 3)
		end },
		{ t = if tier >= 4 then 1.6 else 1.0, fn = function(instant: boolean)
			to(user, 0.3, { TextTransparency = 0.1 }, instant)
			tableChip.Visible = true
			tierChip.Visible = true
			pop(tableChip, instant)
			pop(tierChip, instant)
		end },
		{ t = if tier >= 4 then 1.9 else 1.35, fn = function(instant: boolean)
			to(info, 0.3, { TextTransparency = 0 }, instant)
		end },
		{ t = countFrom, fn = function(instant: boolean)
			to(amount, 0.2, { TextTransparency = 0 }, instant)
		end },
		{ t = dur - 0.55, fn = function(instant: boolean)
			for _, g in frame:GetDescendants() do
				if g:IsA("TextLabel") then
					to(g, 0.45, { TextTransparency = 1 }, instant)
				end
			end
			to(bg, 0.5, { BackgroundTransparency = 1 }, instant)
		end },
	}
	function api.update(el: number, _dt: number)
		grad.Rotation = 15 + el * 18
		shimmer.Offset = Vector2.new(((el * 0.6) % 2) - 1, 0)
		for i, r in rayList do
			r.Rotation = (i - 1) * 180 / #rayList + el * (if tier >= 4 then 24 else 12)
		end
		for _, s in spark do
			local a = 0.5 + 0.5 * math.sin(el * s.sp + s.ph)
			s.f.BackgroundTransparency = 1 - a * 0.95
			s.f.Size = UDim2.fromOffset(3 + a * 6, 3 + a * 6)
		end
		if #conf > 0 and el > 0.5 then
			confettiStep(conf, el, 0.5)
		end
		if el >= countFrom then
			local k = math.clamp((el - countFrom) / countDur, 0, 1)
			local e = 1 - (1 - k) ^ 3
			amount.Text = money(math.floor((d.price or 0) * e / 1000) * 1000)
			if k >= 1 then
				amount.Text = money(d.price or 0)
			end
		end
	end
	function api.setRank(info: any)
		if rankChip or type(info) ~= "table" or type(info.rank) ~= "number" then
			return
		end
		local text = if info.rank == 1 then L.rankKing else string.format(L.rankUp, info.rank)
		rankChip = chip(frame, text, if info.rank == 1 then GOLD else CYAN, UDim2.fromScale(0.97, 0.94), Vector2.new(1, 1), if info.rank == 1 then 0.22 else 0.17)
		pop(rankChip :: Frame, false)
		if info.rank > 1 and type(info.gap) == "number" and info.gap > 0 then
			local sub = chip(frame, string.format(L.rankChase, S.wonShort(info.gap)), Color3.fromRGB(200, 210, 230), UDim2.fromScale(0.03, 0.94), Vector2.new(0, 1), 0.2)
			pop(sub, false)
		end
	end
	return api
end

-------------------------------------------------------------------------------------------------
-- 후원 takeover
-------------------------------------------------------------------------------------------------
local DONATE_COL = {
	{ CYAN, Color3.fromRGB(180, 240, 255) },
	{ MAGENTA, Color3.fromRGB(255, 200, 230) },
	{ VIOLET, GOLD },
	{ GOLD, Color3.fromRGB(255, 250, 220) },
}
function LedArt.donate(host: Instance, d: any, tier: number, dur: number): any
	local col = DONATE_COL[math.clamp(tier, 1, 4)]
	local q = Core.q()
	local frame, bg, grad = base(host, col[1], col[2])
	local rayList = rays(frame, col[2], if tier >= 3 then 12 else 6, if tier >= 4 then 0.5 else 0.78)
	local spark = sparkles(frame, math.floor((8 + tier * 6) * (if q.name == "high" then 1 elseif q.name == "mid" then 0.7 else 0.4)), col[2])
	local conf = if tier >= 2 then confetti(frame, math.floor((tier * 9) * (if q.name == "high" then 1 elseif q.name == "mid" then 0.7 else 0.4))) else {}
	local headText = L.donateHead[tier] or "후원 감사합니다"
	if d.rb then
		headText = "💎 " .. headText
	end
	local head = Core.text(frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, -0.2),
		Size = UDim2.fromScale(0.7, 0.12),
		Text = "💸 " .. headText,
		TextColor3 = col[2],
		ZIndex = 14,
		stroke = dark(col[1], 0.5),
	})
	local name, shimmer = bigName(frame, string.format("%s님", d.n or "손님"), col[1], col[2], 0.38, 0.26)
	local user = Core.text(frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromScale(0.4, 0.065),
		Text = if d.un then "@" .. d.un else "",
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(205, 215, 240),
		TextTransparency = 1,
		ZIndex = 14,
	})
	local msgText = if type(d.m) == "string" and d.m ~= "" then "“" .. d.m .. "”" else ""
	local msg = Core.text(frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.69),
		Size = UDim2.fromScale(0.86, 0.13),
		Text = msgText,
		Font = Enum.Font.GothamBold,
		TextTransparency = 1,
		ZIndex = 14,
		stroke = Color3.fromRGB(20, 10, 40),
	})
	local amount = Core.text(frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.87),
		Size = UDim2.fromScale(0.5, 0.13),
		Text = money(0),
		TextColor3 = GOLD,
		TextTransparency = 1,
		ZIndex = 14,
		stroke = Color3.fromRGB(60, 30, 0),
	})
	local to_ = d.to or { k = "all" }
	local targetText = if to_.k == "table" then string.format(L.toTable, tostring(to_.id or "?"))
		elseif to_.k == "dj" then string.format(L.toDj, tostring(to_.n or ""))
		else L.toAll
	local targetChip = chip(frame, "→ " .. targetText, col[2], UDim2.fromScale(0.03, 0.06), Vector2.new(0, 0), 0.22)
	targetChip.Visible = false
	local tierChip = chip(frame, S.tier(tier).label, col[1], UDim2.fromScale(0.97, 0.06), Vector2.new(1, 0), 0.12)
	tierChip.Visible = false

	local countFrom = 1.5
	local api: any = { frame = frame, dur = dur }
	api.steps = {
		{ t = 0, fn = function(instant: boolean)
			to(bg, 0.25, { BackgroundTransparency = 0.04 }, instant)
			flash(frame, col[2], instant)
		end },
		{ t = 0.1, fn = function(instant: boolean)
			to(head, 0.5, { Position = UDim2.fromScale(0.5, 0.12) }, instant, Enum.EasingStyle.Back)
		end },
		{ t = 0.5, fn = function(instant: boolean)
			to(name, 0.2, { TextTransparency = 0 }, instant)
			pop(name, instant, 0.35)
		end },
		{ t = 0.9, fn = function(instant: boolean)
			to(user, 0.3, { TextTransparency = 0.1 }, instant)
			targetChip.Visible = true
			tierChip.Visible = true
			pop(targetChip, instant)
			pop(tierChip, instant)
		end },
		{ t = countFrom, fn = function(instant: boolean)
			to(amount, 0.2, { TextTransparency = 0 }, instant)
		end },
		{ t = 2.6, fn = function(instant: boolean)
			if msgText ~= "" then
				to(msg, 0.35, { TextTransparency = 0 }, instant)
				pop(msg, instant, 0.7)
			end
		end },
		{ t = dur - 0.55, fn = function(instant: boolean)
			for _, g in frame:GetDescendants() do
				if g:IsA("TextLabel") then
					to(g, 0.45, { TextTransparency = 1 }, instant)
				end
			end
			to(bg, 0.5, { BackgroundTransparency = 1 }, instant)
		end },
	}
	function api.update(el: number, _dt: number)
		grad.Rotation = 15 + el * 16
		shimmer.Offset = Vector2.new(((el * 0.55) % 2) - 1, 0)
		for i, r in rayList do
			r.Rotation = (i - 1) * 180 / #rayList - el * (if tier >= 4 then 22 else 10)
		end
		for _, s in spark do
			local a = 0.5 + 0.5 * math.sin(el * s.sp + s.ph)
			s.f.BackgroundTransparency = 1 - a * 0.95
			s.f.Size = UDim2.fromOffset(3 + a * 6, 3 + a * 6)
		end
		if #conf > 0 and el > 0.4 then
			confettiStep(conf, el, 0.4)
		end
		if el >= countFrom then
			local k = math.clamp((el - countFrom) / 1.2, 0, 1)
			local e = 1 - (1 - k) ^ 3
			amount.Text = money(if k >= 1 then (d.w or 0) else math.floor((d.w or 0) * e / 1000) * 1000)
		end
	end
	return api
end

-------------------------------------------------------------------------------------------------
-- DJ: LED text / ON AIR
-------------------------------------------------------------------------------------------------
function LedArt.dj(host: Instance, d: any, _tier: number, dur: number): any
	local frame, bg, grad = base(host, VIOLET, CYAN)
	local bars = eq(frame, 28, VIOLET, 3)
	local head = Core.text(frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.15),
		Size = UDim2.fromScale(0.5, 0.11),
		Text = string.format("🎧 DJ %s", d.n or ""),
		TextColor3 = CYAN,
		TextTransparency = 1,
		ZIndex = 14,
	})
	local body = Core.text(frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.36),
		Text = tostring(d.t or ""),
		TextTransparency = 1,
		ZIndex = 15,
		stroke = Color3.fromRGB(70, 20, 140),
	})
	local scale = Instance.new("UIScale")
	scale.Parent = body
	local api: any = { frame = frame, dur = dur }
	api.steps = {
		{ t = 0, fn = function(instant: boolean)
			to(bg, 0.2, { BackgroundTransparency = 0.05 }, instant)
			to(head, 0.3, { TextTransparency = 0 }, instant)
			flash(frame, CYAN, instant)
		end },
		{ t = 0.3, fn = function(instant: boolean)
			to(body, 0.2, { TextTransparency = 0 }, instant)
		end },
		{ t = dur - 0.5, fn = function(instant: boolean)
			to(body, 0.4, { TextTransparency = 1 }, instant)
			to(head, 0.4, { TextTransparency = 1 }, instant)
			to(bg, 0.45, { BackgroundTransparency = 1 }, instant)
		end },
	}
	function api.update(el: number, _dt: number)
		grad.Rotation = el * 30
		local phase = Core.beat()
		scale.Scale = 1 + 0.07 * (1 - phase) ^ 3
		eqStep(bars, el, 0.55)
	end
	return api
end

function LedArt.djon(host: Instance, d: any, _tier: number, dur: number): any
	local frame, bg, grad = base(host, MAGENTA, VIOLET)
	local bars = eq(frame, 36, MAGENTA, 3)
	local rayList = rays(frame, MAGENTA, 10, 0.7)
	local head = Core.text(frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, -0.2),
		Size = UDim2.fromScale(0.6, 0.13),
		Text = L.djTime,
		TextColor3 = Color3.fromRGB(255, 200, 235),
		ZIndex = 14,
	})
	local name, shimmer = bigName(frame, string.format("DJ %s", d.n or ""), MAGENTA, Color3.fromRGB(255, 210, 240), 0.47, 0.3)
	local onair = Core.frame(frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.76),
		Size = UDim2.fromScale(0.2, 0.13),
		BackgroundColor3 = Color3.fromRGB(255, 50, 70),
		BackgroundTransparency = 1,
		corner = UDim.new(0.5, 0),
		ZIndex = 14,
	})
	local onairText = Core.text(onair, { Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1), Text = "● ON AIR", TextTransparency = 1, ZIndex = 15 })
	local api: any = { frame = frame, dur = dur }
	api.steps = {
		{ t = 0, fn = function(instant: boolean)
			to(bg, 0.2, { BackgroundTransparency = 0.04 }, instant)
			flash(frame, MAGENTA, instant)
			to(head, 0.45, { Position = UDim2.fromScale(0.5, 0.14) }, instant, Enum.EasingStyle.Back)
		end },
		{ t = 0.5, fn = function(instant: boolean)
			to(name, 0.2, { TextTransparency = 0 }, instant)
			pop(name, instant, 0.3)
		end },
		{ t = 1.0, fn = function(instant: boolean)
			to(onair, 0.25, { BackgroundTransparency = 0.05 }, instant)
			to(onairText, 0.25, { TextTransparency = 0 }, instant)
			pop(onair, instant)
		end },
		{ t = dur - 0.5, fn = function(instant: boolean)
			for _, g in frame:GetDescendants() do
				if g:IsA("TextLabel") then
					to(g, 0.4, { TextTransparency = 1 }, instant)
				end
			end
			to(onair, 0.4, { BackgroundTransparency = 1 }, instant)
			to(bg, 0.45, { BackgroundTransparency = 1 }, instant)
		end },
	}
	function api.update(el: number, _dt: number)
		grad.Rotation = el * 25
		shimmer.Offset = Vector2.new(((el * 0.7) % 2) - 1, 0)
		for i, r in rayList do
			r.Rotation = (i - 1) * 18 + el * 20
		end
		eqStep(bars, el, 0.7)
		if el > 1.2 then
			onair.BackgroundTransparency = 0.05 + 0.35 * (0.5 + 0.5 * math.sin(el * 6))
		end
	end
	return api
end

-------------------------------------------------------------------------------------------------
-- 합석 card: "TABLE G2 · 합석 이벤트!" + new friends' name chips
-------------------------------------------------------------------------------------------------
function LedArt.booking(host: Instance, d: any, _tier: number, dur: number): any
	local frame, bg, grad = base(host, Color3.fromRGB(40, 204, 196), MAGENTA)
	local spark = sparkles(frame, 26, GOLD)
	local head = Core.text(frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, -0.2),
		Size = UDim2.fromScale(0.55, 0.1),
		Text = string.format("✨ %s ✨", string.format(L.bookingMD, d.md or "MD")),
		TextColor3 = Color3.fromRGB(180, 255, 245),
		ZIndex = 14,
	})
	local title, shimmer = bigName(frame, string.format(L.booking, d.table or "?"), Color3.fromRGB(40, 204, 196), GOLD, 0.37, 0.26)
	local sub = Core.text(frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromScale(0.8, 0.09),
		Text = string.format(L.bookingSub, d.n or "손님", #(d.guests or {})),
		Font = Enum.Font.GothamBold,
		TextTransparency = 1,
		ZIndex = 14,
	})
	local chips: { Frame } = {}
	local guests = d.guests or {}
	local n = math.min(#guests, 4)
	for i = 1, n do
		local g = guests[i]
		local x = 0.5 + (i - (n + 1) / 2) * 0.2
		local c = chip(frame, tostring(g.name or "친구"), if i % 2 == 0 then MAGENTA else Color3.fromRGB(120, 240, 230), UDim2.fromScale(x, 0.8), Vector2.new(0.5, 0.5), 0.17)
		c.Visible = false
		table.insert(chips, c)
	end
	local api: any = { frame = frame, dur = dur }
	api.steps = {
		{ t = 0, fn = function(instant: boolean)
			to(bg, 0.25, { BackgroundTransparency = 0.05 }, instant)
			flash(frame, Color3.fromRGB(180, 255, 245), instant)
			to(head, 0.45, { Position = UDim2.fromScale(0.5, 0.13) }, instant, Enum.EasingStyle.Back)
		end },
		{ t = 0.45, fn = function(instant: boolean)
			to(title, 0.2, { TextTransparency = 0 }, instant)
			pop(title, instant, 0.4)
		end },
		{ t = 1.0, fn = function(instant: boolean)
			to(sub, 0.3, { TextTransparency = 0 }, instant)
		end },
		{ t = dur - 0.55, fn = function(instant: boolean)
			for _, g in frame:GetDescendants() do
				if g:IsA("TextLabel") then
					to(g, 0.45, { TextTransparency = 1 }, instant)
				end
			end
			for _, c in chips do
				to(c, 0.45, { BackgroundTransparency = 1 }, instant)
			end
			to(bg, 0.5, { BackgroundTransparency = 1 }, instant)
		end },
	}
	-- the name chips flip in on the beats
	for i, c in chips do
		table.insert(api.steps, #api.steps, { t = 1.3 + i * 0.45, fn = function(instant: boolean)
			c.Visible = true
			pop(c, instant)
		end })
	end
	table.sort(api.steps, function(a, b)
		return a.t < b.t
	end)
	function api.update(el: number, _dt: number)
		grad.Rotation = 20 + el * 20
		shimmer.Offset = Vector2.new(((el * 0.6) % 2) - 1, 0)
		for _, s in spark do
			local a = 0.5 + 0.5 * math.sin(el * s.sp + s.ph)
			s.f.BackgroundTransparency = 1 - a * 0.95
			s.f.Size = UDim2.fromOffset(3 + a * 6, 3 + a * 6)
		end
	end
	return api
end

-------------------------------------------------------------------------------------------------
-- tier-1 order strip (lower band)
-------------------------------------------------------------------------------------------------
function LedArt.band(host: Instance, d: any, _tier: number, dur: number): any
	local frame = Core.frame(host, {
		Name = "Band",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.2),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		ZIndex = 25,
		gradient = Core.seq(Color3.fromRGB(10, 40, 70), Color3.fromRGB(20, 120, 160), Color3.fromRGB(10, 40, 70)),
	})
	local label = Core.text(frame, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(1.02, 0.5),
		Size = UDim2.fromScale(0.95, 0.7),
		Text = string.format("%s %s 테이블 · %s님 · %s %s", d.icon or "🧊", d.table or "?", d.n or "손님", d.label or "기본 세트", L.thanks .. " ✨"),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 26,
	})
	local api: any = { frame = frame, dur = dur, band = true }
	api.steps = {
		{ t = 0, fn = function(instant: boolean)
			to(frame, 0.3, { BackgroundTransparency = 0.12 }, instant)
			to(label, 0.6, { Position = UDim2.fromScale(0.025, 0.5) }, instant)
		end },
		{ t = dur - 0.5, fn = function(instant: boolean)
			to(label, 0.45, { Position = UDim2.fromScale(-1, 0.5) }, instant)
			to(frame, 0.45, { BackgroundTransparency = 1 }, instant)
		end },
	}
	return api
end

-------------------------------------------------------------------------------------------------
-- generic lower-band note (짠 / laser show / DJ hands / 합석 arrivals)
-------------------------------------------------------------------------------------------------
function LedArt.note(host: Instance, d: any, _tier: number, dur: number): any
	local col: Color3 = if typeof(d.color) == "Color3" then d.color else VIOLET
	local frame = Core.frame(host, {
		Name = "Note",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.2),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		ZIndex = 25,
		gradient = Core.seq(dark(col, 0.25), dark(col, 0.75), dark(col, 0.25)),
	})
	local edge = Core.frame(frame, { Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = lerpC(col, WHITE, 0.4), BackgroundTransparency = 1, ZIndex = 26 })
	local label = Core.text(frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.94, 0.68),
		Text = tostring(d.text or ""),
		Font = Enum.Font.GothamBlack,
		TextTransparency = 1,
		ZIndex = 27,
		stroke = dark(col, 0.4),
	})
	local scale = Instance.new("UIScale")
	scale.Parent = label
	local api: any = { frame = frame, dur = dur, band = true }
	api.steps = {
		{ t = 0, fn = function(instant: boolean)
			to(frame, 0.25, { BackgroundTransparency = 0.1 }, instant)
			to(edge, 0.25, { BackgroundTransparency = 0.1 }, instant)
			to(label, 0.3, { TextTransparency = 0 }, instant)
			pop(label, instant, 0.6)
		end },
		{ t = dur - 0.45, fn = function(instant: boolean)
			to(label, 0.4, { TextTransparency = 1 }, instant)
			to(frame, 0.4, { BackgroundTransparency = 1 }, instant)
			to(edge, 0.4, { BackgroundTransparency = 1 }, instant)
		end },
	}
	function api.update(el: number, _dt: number)
		if el > 0.5 then
			local phase = Core.beat()
			scale.Scale = 1 + 0.04 * (1 - phase) ^ 3
		end
	end
	return api
end

return LedArt
