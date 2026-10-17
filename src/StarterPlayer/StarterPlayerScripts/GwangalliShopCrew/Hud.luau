-- GwangalliShopCrew client / Hud: the paper side of eating out.
--   * 주문서 (order ticket, "ticket"): a small card with what you ordered and where each dish is (접수 → 조리 중
--     n초 → 가져가는 중 → 서빙 완료), top-right (GwangalliLayout "topRight"), gone a few seconds after the last dish
--   * 영수증 (receipt, "receipt"): a paper slip after paying (items, total, 단골 도장, 쿠폰) — tap to close
--   * 단골 등극 banner ("regular.up") and the 단골 카드 ("card": level, visits, 10 stamp circles, coupons,
--     favourite dish, perks, my top 5 shops)
--   Hud.init(ctx)   ctx = { player, gui, K?, Layout?, Net, Shared }   Hud.toast(text, kind)

local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local Hud = {}

local ctx: any = nil
local Util: any = nil
local screen: ScreenGui? = nil

local INK = Color3.fromRGB(34, 32, 30)
local PAPER = Color3.fromRGB(252, 250, 244)
local GLASS = Color3.fromRGB(16, 20, 36)
local CYAN = Color3.fromRGB(61, 214, 245)
local GOLD = Color3.fromRGB(255, 194, 71)

local function new(cls: string, props: any, parent: Instance?): any
	local i = Instance.new(cls)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

local function corner(p: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, p)
end

local function text(parent: Instance, props: any): TextLabel
	local base = { BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

local function slot(name: string): any?
	if ctx.Layout and type(ctx.Layout.rect) == "function" then
		local ok, r = pcall(ctx.Layout.rect, name)
		if ok and type(r) == "table" and r.w then
			return r
		end
	end
	return nil
end

function Hud.toast(msg: string, kind: string?)
	local K = ctx.K
	if K and type(K.toast) == "function" then
		pcall(K.toast, { title = msg, kind = kind or "info" })
		return
	end
	if not screen then
		return
	end
	local t = text(screen, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(360, 40),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = GLASS,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		Text = msg,
		ZIndex = 40,
	})
	corner(t, 12)
	task.delay(3, function()
		t:Destroy()
	end)
end

-------------------------------------------------------------------------------------------------
-- 주문서
-------------------------------------------------------------------------------------------------
local ticket: Frame? = nil
local ticketSerial = 0
local PHASE_COLOR = {
	placed = Color3.fromRGB(150, 160, 190),
	cooking = Color3.fromRGB(255, 176, 32),
	ready = Color3.fromRGB(61, 214, 245),
	carrying = Color3.fromRGB(61, 214, 245),
	served = Color3.fromRGB(61, 220, 132),
	picked = Color3.fromRGB(61, 220, 132),
}

local function onTicket(d: any)
	if not screen then
		return
	end
	ticketSerial += 1
	local mine = ticketSerial
	local items = if type(d.items) == "table" then d.items else {}
	if #items == 0 then
		if ticket then
			ticket.Visible = false
		end
		return
	end
	if not ticket then
		ticket = new("Frame", { Name = "CrewTicket", BackgroundColor3 = GLASS, BackgroundTransparency = 0.12, Size = UDim2.fromOffset(250, 60), ZIndex = 20 }, screen)
		corner(ticket :: Frame, 14)
		new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.86 }, ticket)
	end
	local tk = ticket :: Frame
	for _, ch in tk:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	local head = string.format("🧾 주문서 · %s", tostring(d.shopName or ""))
	if d.table then
		head ..= string.format(" · %s번 테이블", tostring(d.table))
	elseif d.number then
		head ..= string.format(" · %03d번", tonumber(d.number) or 0)
	end
	text(tk, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18), Font = Enum.Font.GothamBold, TextSize = 13, Text = head, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = CYAN, ZIndex = 21 })
	local y = 30
	for i, it in items do
		if i > 5 then
			break
		end
		local col = PHASE_COLOR[it.phase] or PHASE_COLOR.placed
		text(tk, { Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -110, 0, 20), TextSize = 13, Text = string.format("%s %s ×%d", tostring(it.icon or "•"), tostring(it.name), tonumber(it.qty) or 1), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 21 })
		local label = tostring(it.label or "")
		if it.left and it.phase == "cooking" then
			label = string.format("조리 중 %d초", tonumber(it.left) or 0)
		end
		local chip = text(tk, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, y + 1), Size = UDim2.fromOffset(92, 18), TextSize = 11, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center, Text = label, BackgroundTransparency = 0.75, BackgroundColor3 = col, TextColor3 = col:Lerp(Color3.new(1, 1, 1), 0.55), ZIndex = 21 })
		corner(chip, 9)
		y += 24
	end
	tk.Size = UDim2.fromOffset(250, y + 8)
	local r = slot("topRight")
	if r then
		tk.Position = UDim2.fromOffset(r.x + r.w - 250, r.y)
	else
		tk.AnchorPoint = Vector2.new(1, 0)
		tk.Position = UDim2.new(1, -12, 0, 64)
	end
	tk.Visible = true
	if (tonumber(d.open) or 0) == 0 then
		task.delay(6, function()
			if mine == ticketSerial and ticket then
				ticket.Visible = false
			end
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- 영수증
-------------------------------------------------------------------------------------------------
local function kstNow(): string
	local t = os.time() + 9 * 3600
	return os.date("!%Y.%m.%d %H:%M", t) :: string
end

local receipt: Frame? = nil
local receiptSerial = 0
local function onReceipt(d: any)
	if not screen then
		return
	end
	receiptSerial += 1
	local mine = receiptSerial
	if receipt then
		receipt:Destroy()
	end
	local W = 240
	local slip = new("TextButton", { Name = "CrewReceipt", AutoButtonColor = false, Text = "", BackgroundColor3 = PAPER, Size = UDim2.fromOffset(W, 100), ZIndex = 30 }, screen)
	receipt = slip
	corner(slip, 6)
	local y = 10
	local function line(t: string, opts: any?)
		local o = opts or {}
		local l = text(slip, {
			Position = UDim2.fromOffset(14, y),
			Size = UDim2.new(1, -28, 0, o.h or 18),
			TextColor3 = o.color or INK,
			Font = o.font or Enum.Font.Code,
			TextSize = o.size or 13,
			TextXAlignment = o.align or Enum.TextXAlignment.Left,
			Text = t,
			ZIndex = 31,
		})
		y += (o.h or 18) + (o.gap or 2)
		return l
	end
	line(if d.preview then "가 계 산 서" else "영 수 증", { font = Enum.Font.GothamBold, size = 16, align = Enum.TextXAlignment.Center, h = 22 })
	line(tostring(d.shopName or ""), { font = Enum.Font.GothamBold, align = Enum.TextXAlignment.Center })
	line(kstNow(), { size = 11, align = Enum.TextXAlignment.Center, color = Color3.fromRGB(120, 116, 110) })
	line(string.rep("-", 30), { color = Color3.fromRGB(160, 156, 150), gap = 0 })
	for i, it in (if type(d.items) == "table" then d.items else {}) do
		if i > 8 then
			line(string.format("… 외 %d개", #d.items - 8))
			break
		end
		local qty = tonumber(it.qty) or 1
		local price = (tonumber(it.price) or 0) * qty
		local l = line(string.format("%s ×%d", tostring(it.name), qty))
		local p = text(slip, { Position = l.Position, Size = l.Size, TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.Code, TextSize = 13, TextColor3 = INK, Text = Util.won(price), ZIndex = 31 })
		local _ = p
	end
	line(string.rep("-", 30), { color = Color3.fromRGB(160, 156, 150), gap = 0 })
	local tl = line("합계", { font = Enum.Font.GothamBold, size = 15, h = 20 })
	text(slip, { Position = tl.Position, Size = tl.Size, TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = INK, Text = Util.won(tonumber(d.total) or 0), ZIndex = 31 })
	if d.auto then
		line("나갈 때 자동 결제", { size = 11, color = Color3.fromRGB(150, 90, 60) })
	end
	if d.coupon then
		line(string.format("🎟️ 단골 쿠폰 -%s (환급)", Util.won(d.coupon)), { size = 12, color = Color3.fromRGB(200, 70, 60), font = Enum.Font.GothamBold })
	end
	-- stamp row
	if d.stamp and d.stampsMax then
		y += 4
		line("단골 도장", { size = 11, color = Color3.fromRGB(120, 116, 110), font = Enum.Font.GothamBold })
		local n = tonumber(d.stampsMax) or 10
		local size = math.floor((W - 28 - (n - 1) * 4) / n)
		for i = 1, n do
			local filled = i <= (tonumber(d.stamp) or 0)
			local c = new("TextLabel", { Position = UDim2.fromOffset(14 + (i - 1) * (size + 4), y), Size = UDim2.fromOffset(size, size), BackgroundColor3 = if filled then Color3.fromRGB(214, 60, 52) else Color3.fromRGB(232, 228, 220), Text = if filled then "印" else "", TextColor3 = PAPER, Font = Enum.Font.GothamBold, TextSize = math.floor(size * 0.6), ZIndex = 31 }, slip)
			corner(c, size)
			if filled and i == (tonumber(d.stamp) or 0) then
				c.Size = UDim2.fromOffset(size * 1.8, size * 1.8)
				TweenService:Create(c, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(size, size) }):Play()
			end
		end
		y += size + 6
		if d.newCoupon then
			line("🎉 도장 완성! 쿠폰 1장 적립", { size = 12, color = Color3.fromRGB(200, 70, 60), font = Enum.Font.GothamBold })
		end
	end
	if d.title and (tonumber(d.level) or 0) > 0 then
		line(string.format("🏅 %s · %s", tostring(d.title), tostring(d.shopName or "")), { size = 11, color = Color3.fromRGB(120, 100, 40), font = Enum.Font.GothamBold })
	end
	line(if d.preview then "계산은 나가실 때 해 주세요" else "감사합니다 · 또 오세요!", { size = 12, align = Enum.TextXAlignment.Center, font = Enum.Font.GothamBold, color = Color3.fromRGB(90, 86, 80) })
	slip.Size = UDim2.fromOffset(W, y + 8)
	-- PC / tablet: the right side, vertically centred (clear of the dialog slot at the bottom). Phones: under
	-- the money chip on the left (the right edge is the 폰 / 이동 / 달리기 column and the jump button there)
	local scr = screen.AbsoluteSize
	local x = scr.X - W - 16
	local yy = math.max(70, scr.Y * 0.5 - (y + 8) / 2 - 40)
	local cls = nil
	if ctx.Layout and type(ctx.Layout.deviceClass) == "function" then
		local ok, c = pcall(ctx.Layout.deviceClass)
		cls = if ok then c else nil
	end
	if cls == "phoneL" or cls == "phoneP" then
		local r = slot("topLeftChips")
		x = if r then r.x else 12
		yy = (if r then r.y + r.h else 52) + 8
		local maxH = scr.Y - yy - 8
		if y + 8 > maxH then
			slip.Size = UDim2.fromOffset(W, maxH)
		end
	end
	slip.Position = UDim2.fromOffset(scr.X + 10, yy)
	TweenService:Create(slip, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(x, yy) }):Play()
	if ctx.K and type(ctx.K.feedback) == "function" then
		pcall(ctx.K.feedback, if d.preview then "open" else "money")
	end
	local function gone()
		if receipt == slip then
			receipt = nil
		end
		TweenService:Create(slip, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = UDim2.fromOffset(scr.X + 10, yy) }):Play()
		task.delay(0.3, function()
			slip:Destroy()
		end)
	end
	slip.Activated:Connect(gone)
	task.delay(if d.preview then 9 else 8, function()
		if mine == receiptSerial and slip.Parent then
			gone()
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- 단골
-------------------------------------------------------------------------------------------------
local function onRegularUp(d: any)
	if not screen then
		return
	end
	local b = text(screen, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -60),
		Size = UDim2.fromOffset(420, 52),
		BackgroundColor3 = Color3.fromRGB(46, 34, 10),
		BackgroundTransparency = 0.05,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		TextColor3 = GOLD,
		Text = string.format("🏅 '%s' %s 등극! 직원이 얼굴을 기억해요", tostring(d.shopName or ""), tostring(d.title or "단골")),
		ZIndex = 45,
	})
	corner(b, 16)
	new("UIStroke", { Color = GOLD, Transparency = 0.4, Thickness = 1.5 }, b)
	if ctx.K and type(ctx.K.feedback) == "function" then
		pcall(ctx.K.feedback, "success")
	end
	TweenService:Create(b, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 72) }):Play()
	task.delay(4.2, function()
		TweenService:Create(b, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -60) }):Play()
		task.delay(0.35, function()
			b:Destroy()
		end)
	end)
end

local cardFrame: Frame? = nil
local function closeCard()
	if cardFrame then
		cardFrame:Destroy()
		cardFrame = nil
	end
	ContextActionService:UnbindAction("GwShopCrewCardClose")
end

local function onCard(d: any)
	if not screen then
		return
	end
	closeCard()
	local scr = screen.AbsoluteSize
	local W = math.min(360, scr.X - 24)
	local dim = new("TextButton", { Name = "CrewCard", AutoButtonColor = false, Text = "", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 50 }, screen)
	cardFrame = dim
	local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, 420), BackgroundColor3 = Color3.fromRGB(20, 24, 44), ZIndex = 51 }, dim)
	corner(card, 20)
	new("UIStroke", { Color = GOLD, Transparency = 0.55, Thickness = 1.5 }, card)
	local y = 16
	text(card, { Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -72, 0, 24), Font = Enum.Font.GothamBold, TextSize = 18, Text = string.format("%s %s", tostring(d.icon or "🏅"), tostring(d.shopName or "")), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 52 })
	local x = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 1, Text = "✕", TextSize = 20, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(200, 206, 222), ZIndex = 52 }, card)
	x.Activated:Connect(closeCard)
	y += 28
	local lv = tonumber(d.level) or 0
	text(card, { Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, 22), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = GOLD, Text = string.rep("★", lv) .. string.rep("☆", math.max(0, 5 - lv)) .. "  " .. tostring(d.title or ""), ZIndex = 52 })
	y += 26
	local visits = tonumber(d.visits) or 0
	local nextTxt = if d.nextAt then string.format(" · %s까지 %d일", tostring(d.nextTitle or "다음 등급"), math.max(0, (tonumber(d.nextAt) or 0) - visits)) else ""
	text(card, { Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, 18), TextSize = 13, TextColor3 = Color3.fromRGB(190, 198, 220), Text = string.format("방문 %d일째%s", visits, nextTxt), ZIndex = 52 })
	y += 26
	-- stamps
	local n = tonumber(d.stampsMax) or 10
	local cols = 5
	local size = math.floor((W - 32 - (cols - 1) * 8) / cols)
	size = math.min(size, 52)
	for i = 1, n do
		local cx = (i - 1) % cols
		local cy = (i - 1) // cols
		local filled = i <= (tonumber(d.stamps) or 0)
		local c = new("TextLabel", { Position = UDim2.fromOffset(16 + cx * (size + 8), y + cy * (size + 8)), Size = UDim2.fromOffset(size, size), BackgroundColor3 = if filled then Color3.fromRGB(214, 60, 52) else Color3.fromRGB(44, 50, 78), Text = if filled then "印" else tostring(i), TextColor3 = if filled then PAPER else Color3.fromRGB(110, 118, 150), Font = Enum.Font.GothamBold, TextSize = math.floor(size * 0.45), ZIndex = 52 }, card)
		corner(c, size)
	end
	y += math.ceil(n / cols) * (size + 8) + 6
	text(card, { Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, 18), TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 132, 120), Text = string.format("🎟️ 쿠폰 %d장", tonumber(d.coupons) or 0), ZIndex = 52 })
	y += 22
	if d.fav then
		text(card, { Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, 18), TextSize = 13, TextColor3 = Color3.new(1, 1, 1), Text = string.format("😋 자주 먹는 메뉴: %s (%d번)", tostring(d.fav), tonumber(d.favCount) or 0), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 52 })
		y += 22
	end
	for _, perk in (if type(d.perks) == "table" then d.perks else {}) do
		text(card, { Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, 16), TextSize = 12, TextColor3 = Color3.fromRGB(170, 230, 190), Text = "✓ " .. tostring(perk), ZIndex = 52 })
		y += 18
	end
	if type(d.top) == "table" and #d.top > 0 then
		y += 6
		text(card, { Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, 16), TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = CYAN, Text = "내 단골 가게 TOP 5", ZIndex = 52 })
		y += 18
		for i, s in d.top do
			text(card, { Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, 16), TextSize = 12, TextColor3 = Color3.fromRGB(210, 214, 230), Text = string.format("%d. %s · %d일", i, tostring(s.shopName), tonumber(s.visits) or 0), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 52 })
			y += 17
		end
	end
	card.Size = UDim2.fromOffset(W, y + 14)
	dim.Activated:Connect(closeCard)
	ContextActionService:BindActionAtPriority("GwShopCrewCardClose", function(_, state)
		if state == Enum.UserInputState.Begin then
			closeCard()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	if ctx.K and type(ctx.K.feedback) == "function" then
		pcall(ctx.K.feedback, "open")
	end
end

function Hud.init(c: any)
	ctx = c
	Util = c.Shared.Util
	local g = Instance.new("ScreenGui")
	g.Name = "GwangalliShopCrewHud"
	g.ResetOnSpawn = false
	g.DisplayOrder = 31
	g.IgnoreGuiInset = false
	pcall(function()
		(g :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = c.gui
	screen = g
	c.Net.on("ticket", onTicket)
	c.Net.on("receipt", onReceipt)
	c.Net.on("regular.up", onRegularUp)
	c.Net.on("card", onCard)
	c.Net.on("toast", function(d)
		if type(d.text) == "string" then
			Hud.toast(d.text, d.kind)
		end
	end)
end

return Hud
