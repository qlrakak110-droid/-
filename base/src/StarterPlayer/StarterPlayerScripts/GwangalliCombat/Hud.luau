-- GwangalliCombat/Hud (client): the combat HUD, built with the shared kit (ReplicatedStorage.GwangalliUI) and placed
-- through the screen slot contract (ReplicatedStorage.GwangalliLayout).
--   * "주먹" button (ScreenGui "GwangalliCombatHUD", order 9): the same round glass button as 이동 / 달리기 with a
--     drawn fist (Frames only) and the key hint F on PC. Touch: left of the jump button on its row (right of the
--     thumbstick zone); PC: left of the 폰 cell. Re-laid out on Layout.onChanged; glides out like the HUD column.
--   * status card under the clock / toast row: ❤ HP bar with a damage trail (label "HP", never 체력 = stamina) and
--     5 ★ wanted stars that flash red / blue while PoliceChase, "수배 해제까지 N초" while WantedSearch > 0. Calm by
--     default: shown only while hurt, below full HP or wanted. Non-interactive (it may overlap anything).
--   * police stop order: "🚔 경찰: 멈춰!" card with [🙌 항복] [🏃 도주] and a countdown ring -> FireServer
--     ("surrender" / "flee").
--   * KO / 연행 overlay (ScreenGui "GwangalliCombatOverlay", order 42) and the arrest result modal (K.Modal in
--     ScreenGui "GwangalliCombatModal", order 48: 죄목 / 벌금 / 납부 / 미납 / 전과). Both carry HideGwangalliHUD while
--     shown, so the other HUD layers (and the phone) step aside.
--   * toasts (K.toast, force = true): a crime / the stars / escaping the police.
-- Every other enabled ScreenGui with HideGwangalliHUD = true hides the button and the card (same contract as
-- GwangalliHUD). Roblox's own health bar is turned off (the card replaces it).

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Hud = {}

local ctx: any
local K: any
local Layout: any
local Combat: any
local C: any
local F: any
local player: Player

local gui: ScreenGui
local overlayGui: ScreenGui
local modalGui: ScreenGui

-- state ------------------------------------------------------------------------------------------
local hidden = false -- another full-screen UI is up
local hp, maxHp = 100, 100
local hurtAt = -1e9
local wanted = 0
local chasing = false
local searchLeft = 0
local cardShown = false
local punchShown: boolean? = nil

-------------------------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------------------------
local function metrics(): any
	if Layout and type(Layout.metrics) == "function" then
		local ok, m = pcall(Layout.metrics)
		if ok and type(m) == "table" then
			return m
		end
	end
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	return { class = if UserInputService.TouchEnabled then "phoneL" else "pc", W = vp.X, H = vp.Y - 58, s = 1, gap = 10, margin = 16, btn = 56, btnW = 84, btnH = 60 }
end

local function slotRect(name: string): any?
	if Layout and type(Layout.rect) == "function" then
		local ok, r = pcall(Layout.rect, name)
		if ok and type(r) == "table" and r.w and r.w > 0 then
			return r
		end
	end
	return nil
end

-- glide out to the right / spring back (the HUD column's motion), instant on reduced motion
local layerState: { [Instance]: string } = {}
local layerSerial: { [Instance]: number } = {}
local function setLayer(inst: GuiObject, shown: boolean, rest: UDim2, away: UDim2)
	local st = layerState[inst]
	local want = if shown then "shown" else "hidden"
	if st == want or (st == "leaving" and not shown) then
		if shown then
			inst.Position = rest
		end
		return
	end
	layerSerial[inst] = (layerSerial[inst] or 0) + 1
	local mine = layerSerial[inst]
	if st == nil or K.reduced() then
		layerState[inst] = want
		inst.Visible = shown
		inst.Position = rest
		return
	end
	if shown then
		layerState[inst] = "shown"
		inst.Visible = true
		inst.Position = rest + away
		K.spring(inst, { Position = rest }, { duration = 0.42, amount = 0.05 })
	else
		layerState[inst] = "leaving"
		K.cancel(inst)
		K.tween(inst, 0.2, { Position = rest + away }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.21, function()
			if layerSerial[inst] == mine then
				layerState[inst] = "hidden"
				inst.Visible = false
				inst.Position = rest
			end
		end)
	end
end

local function makeGui(name: string, order: number, ignoreInset: boolean): ScreenGui
	local old = ctx.playerGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = ignoreInset
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.DisplayOrder = order
	if not ignoreInset then
		pcall(function()
			g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		end)
	end
	return g
end

-------------------------------------------------------------------------------------------------
-- the 주먹 button
-------------------------------------------------------------------------------------------------
type PunchUi = { button: TextButton, glyph: Frame, caption: TextLabel, key: TextLabel, corner: UICorner, stroke: UIStroke, fill: UIGradient }
local P: PunchUi
local punchRest = UDim2.fromOffset(0, 0)
local punchRect = { x = 0, y = 0, w = 56, h = 56 }

-- a fist from frames (scale units of the Icon box, so it follows the button size): four knuckles, the back of
-- the hand, the thumb folded across it (outlined in the glass colour so it reads on the white hand)
local function drawFist(box: Frame, ink: Color3)
	for i = 1, 4 do
		local kn = K.frame(box, { Name = "Knuckle" .. i, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.17 + (i - 1) * 0.22, 0.02), Size = UDim2.fromScale(0.21, 0.5), BackgroundTransparency = 0, BackgroundColor3 = ink, ZIndex = 4 })
		K.corner(kn, UDim.new(0.5, 0))
		K.stroke(kn, C.glass, 1, 0.1)
	end
	local palm = K.frame(box, { Name = "Hand", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.9, 0.62), BackgroundTransparency = 0, BackgroundColor3 = ink, ZIndex = 5 })
	K.corner(palm, UDim.new(0.3, 0))
	local thumb = K.frame(box, { Name = "Thumb", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.42, 0.6), Size = UDim2.fromScale(0.62, 0.22), Rotation = -12, BackgroundTransparency = 0, BackgroundColor3 = ink, ZIndex = 6 })
	K.corner(thumb, UDim.new(0.5, 0))
	K.stroke(thumb, C.glass, 1.5, 0)
end

local function buildPunch()
	local b = K.make("TextButton", {
		Name = "PunchButton",
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = C.glass,
		BackgroundTransparency = K.GLASS_T or 0.14,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
	}, gui)
	local corner = K.corner(b, UDim.new(0.5, 0))
	local st = K.stroke(b, Color3.new(1, 1, 1), 1, 0.8)
	local fill = K.gradient(b, K.Grad.danger, 90)
	fill.Enabled = false
	local box = K.frame(b, { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(0.4, 0.4), ZIndex = 4 })
	K.make("UIAspectRatioConstraint", { AspectRatio = 1 }, box)
	drawFist(box, C.text)
	local cap = K.text(b, { Name = "Caption", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -5), Size = UDim2.new(1, -4, 0, 13), Text = "주먹", TextSize = K.Type and K.Type.micro or 11, Font = F.bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	local key = K.text(b, { Name = "Key", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 4), Size = UDim2.fromOffset(34, 14), Text = "F", TextSize = 11, Font = F.bold, TextColor3 = C.faint, TextXAlignment = Enum.TextXAlignment.Right, Visible = false, ZIndex = 4 })
	K.pressable(b, { scale = 0.92, sound = false }) -- the swing has its own whoosh
	-- instant on press (Activated only fires on release); GUI presses never reach the world handlers
	b.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			if ctx.Moves then
				ctx.Moves.tryPunch("button")
			end
		end
	end)
	P = { button = b, glyph = box, caption = cap, key = key, corner = corner, stroke = st, fill = fill }
end

-- same proportions as GwangalliHUD's styleActionButton
local function stylePunch(w: number, h: number, pc: boolean)
	P.button.Size = UDim2.fromOffset(w, h)
	local round = math.abs(w - h) < 2
	P.corner.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0, math.floor(math.min(w, h) * 0.36))
	local k = math.min(w, h) / 56
	P.glyph.Size = UDim2.fromOffset(math.floor(22 * k), math.floor(22 * k))
	P.glyph.Position = UDim2.new(0.5, 0, 0, math.floor(8 * k + 11 * k))
	P.caption.TextSize = math.max(11, math.floor(11 * k))
	P.caption.Size = UDim2.new(1, -4, 0, math.floor(13 * k))
	P.caption.Position = UDim2.new(0.5, 0, 1, -math.floor(5 * k))
	P.key.Visible = pc and UserInputService.KeyboardEnabled
end

-- touch: left of the jump button (its row), clear of the thumbstick zone; PC: left of the 폰 cell (the row below
-- is where GwangalliBump's 어깨빵 button and its target label appear)
local function punchPlacement(): (any, boolean)
	local m = metrics()
	local gap = m.gap or 8
	if m.class == "pc" or not m.jump then
		local tr = slotRect("rightColumn.phone") or slotRect("rightColumn.travel")
		if tr then
			return { x = tr.x - gap - tr.w, y = tr.y, w = tr.w, h = tr.h }, true
		end
		local W, H = m.W or 1280, m.H or 662
		local bw, bh = m.btnW or 84, m.btnH or 60
		return { x = W - 16 - 2 * bw - gap, y = H - 16 - 2 * bh - gap, w = bw, h = bh }, true
	end
	local j, b = m.jump, m.btn or 56
	local cx = j.cx - j.r - gap - b / 2
	if m.thumb then
		cx = math.max(cx, m.thumb.x + m.thumb.w + gap + b / 2)
	end
	return { x = math.floor(cx - b / 2), y = math.floor(j.cy - b / 2), w = b, h = b }, false
end

-------------------------------------------------------------------------------------------------
-- the status card (❤ HP + ★ wanted)
-------------------------------------------------------------------------------------------------
local CARD_W = 212
local ROW1 = 36
local holder: Frame
local card: Frame
local cardScale: UIScale
local cardStroke: UIStroke
local hpText: TextLabel
local hpBar: any
local trail: Frame
local dmgLabel: TextLabel
local stars: { TextLabel } = {}
local line2: TextLabel
local trailP = 1
local flashSerial = 0
local starLevel = 0

local function buildCard()
	holder = K.frame(gui, { Name = "CombatStatus", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(CARD_W, ROW1), ZIndex = 3, Visible = false })
	cardScale = K.make("UIScale", { Name = "Fit", Scale = 1 }, holder)
	card = K.frame(holder, { Name = "Card", Size = UDim2.fromScale(1, 1), BackgroundTransparency = K.GLASS_T, BackgroundColor3 = C.glass, ZIndex = 3 })
	K.make("UIScale", { Name = "Pop", Scale = 1 }, card)
	K.corner(card, K.Radius.sm)
	cardStroke = K.stroke(card, Color3.new(1, 1, 1), 1, 0.86)
	local heart = K.iconTile(card, 24, "❤", C.red, true)
	heart.AnchorPoint = Vector2.new(0, 0.5)
	heart.Position = UDim2.new(0, 7, 0, ROW1 / 2)
	heart.ZIndex = 4
	for _, d in heart:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 5
		end
	end
	hpText = K.text(card, { Name = "HP", Position = UDim2.fromOffset(38, 4), Size = UDim2.fromOffset(84, 14), Text = "HP 100", Font = F.bold, TextSize = K.Type.micro, ZIndex = 4 })
	K.mono(hpText)
	hpBar = K.ProgressBar(card, { height = 6, color = C.green, value = 1 })
	hpBar.frame.Position = UDim2.fromOffset(38, 21)
	hpBar.frame.Size = UDim2.fromOffset(86, 6)
	hpBar.frame.ZIndex = 4
	trail = K.frame(hpBar.frame, { Name = "Trail", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.15, BackgroundColor3 = Color3.fromRGB(255, 236, 236), ZIndex = 4 })
	K.corner(trail, UDim.new(0.5, 0))
	hpBar.fill.ZIndex = 5 -- the trail shows the lost part under the fill
	dmgLabel = K.text(card, { Name = "Damage", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(128, 24), Size = UDim2.fromOffset(40, 14), Text = "", Font = F.heavy, TextSize = 12, TextColor3 = C.red, TextTransparency = 1, ZIndex = 6 })
	K.mono(dmgLabel)
	local row = K.frame(card, { Name = "Wanted", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -7, 0, ROW1 / 2), Size = UDim2.fromOffset(74, 18), ZIndex = 4 })
	K.list(row, true, 0, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	for i = 1, Combat.CONFIG.MAX_STARS do
		stars[i] = K.text(row, { Name = "Star" .. i, Size = UDim2.fromOffset(14, 18), Text = "★", Font = F.bold, TextSize = 15, TextColor3 = C.card3, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = i, ZIndex = 4 })
	end
	line2 = K.text(card, { Name = "Line", Position = UDim2.fromOffset(10, ROW1 - 2), Size = UDim2.new(1, -20, 0, 14), Text = "", Font = F.bold, TextSize = K.Type.micro, TextColor3 = C.sub, Visible = false, ZIndex = 4, TextTruncate = Enum.TextTruncate.AtEnd })
end

local function setHP(cur: number, mx: number, animate: boolean)
	local m = math.max(mx, 1)
	local p = math.clamp(cur / m, 0, 1)
	hpBar.set(p, not animate)
	hpBar.setColor(if p <= 0.25 then C.red elseif p <= 0.5 then C.orange else C.green)
	K.setText(hpText, "HP " .. tostring(math.max(0, math.ceil(cur - 1e-6))))
	if animate and p < trailP then
		K.cancel(trail)
		K.tweenD(trail, 0.45, { Size = UDim2.fromScale(p, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.35)
	else
		trail.Size = UDim2.fromScale(p, 1)
	end
	trailP = p
	if ctx.Fx then
		ctx.Fx.setLowHp(p <= 0.3 and cur > 0)
	end
end

local function showDamage(dmg: number)
	if dmg <= 0 then
		return
	end
	K.cancel(dmgLabel)
	dmgLabel.Text = "-" .. tostring(math.floor(dmg + 0.5))
	dmgLabel.TextTransparency = 0
	dmgLabel.Position = UDim2.fromOffset(128, 18)
	K.tweenD(dmgLabel, 1.2, { Position = UDim2.fromOffset(128, 30) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	K.tweenD(dmgLabel, 0.5, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.8)
end

local function setWanted(n: number, chase: boolean)
	local grew = n > starLevel
	for i, s in stars do
		s.TextColor3 = if i <= n then C.gold else C.card3
		if grew and i > starLevel and i <= n then
			pcall(K.springIn, s, 0.3, { amount = 0.6, duration = 0.45, delay = (i - starLevel - 1) * 0.06 })
		end
	end
	starLevel = n
	flashSerial += 1
	local mine = flashSerial
	cardStroke.Color = if n > 0 then C.red else Color3.new(1, 1, 1)
	cardStroke.Transparency = if n > 0 then 0.35 else 0.86
	if not (chase and n > 0) then
		return
	end
	if K.reduced() then
		cardStroke.Transparency = 0.1 -- a calm, static highlight
		return
	end
	-- police lights: red / blue stroke, the stars blink white
	task.spawn(function()
		local red = false
		while flashSerial == mine and card.Parent do
			red = not red
			cardStroke.Color = if red then C.red else C.blue
			cardStroke.Transparency = 0.1
			for i = 1, starLevel do
				stars[i].TextColor3 = if red then C.gold else Color3.new(1, 1, 1)
			end
			task.wait(0.35)
		end
	end)
end

local function setLine()
	local text, color = "", C.sub
	if wanted > 0 then
		if chasing then
			text, color = "🚨 경찰이 쫓고 있어요", C.red
		elseif searchLeft > 0 then
			text = "🔍 수배 해제까지 " .. tostring(math.ceil(searchLeft)) .. "초"
		end
	end
	K.setText(line2, text)
	line2.TextColor3 = color
	local two = text ~= ""
	line2.Visible = two
	holder.Size = UDim2.fromOffset(CARD_W, if two then ROW1 + 14 else ROW1)
end

local function cardPlacement()
	local m = metrics()
	local s = m.s or 1
	cardScale.Scale = s
	local tc = slotRect("topCenter")
	local to = slotRect("toasts")
	local gap = m.gap or 8
	local x, y
	if tc then
		x = tc.x + tc.w / 2
		y = tc.y + tc.h + 4
		if to and to.x < tc.x + tc.w and to.x + to.w > tc.x then
			y = math.max(y, to.y + to.h + 4)
		end
	else
		x, y = (m.W or 800) / 2, 70
	end
	-- landscape phones: stay between the money chip and the tracker / right column
	local half = CARD_W * s / 2
	local left = slotRect("topLeftChips")
	local lo = if left then left.x + left.w + gap + half else half + 8
	local hi = (m.W or 800) - half - 8
	local tr = slotRect("topRight")
	if tr and m.class == "phoneL" then
		hi = math.min(hi, tr.x - gap - half)
	end
	if hi >= lo then
		x = math.clamp(x, lo, hi)
	end
	-- a visible tracker / shift card right below the toast row (portrait): go below it
	local phoneHud = ctx.playerGui:FindFirstChild("GwangalliPhoneHUD")
	if phoneHud and phoneHud:IsA("ScreenGui") and phoneHud.Enabled then
		for _, name in { "QuestTracker", "ShiftCard" } do
			local f = phoneHud:FindFirstChild(name, true)
			if f and f:IsA("GuiObject") and K.shownInTree(f) then
				local ap, as = f.AbsolutePosition, f.AbsoluteSize
				local ox = ap.X < x + half and ap.X + as.X > x - half
				local oy = ap.Y < y + ROW1 * s + 14 * s and ap.Y + as.Y > y
				if ox and oy and as.Y < 200 then
					y = ap.Y + as.Y + 6
				end
			end
		end
	end
	holder.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

local function setCardShown(on: boolean)
	if on == cardShown then
		return
	end
	cardShown = on
	local sc = card:FindFirstChildOfClass("UIScale") :: UIScale
	if on then
		cardPlacement()
		holder.Visible = true
		if not K.reduced() then
			sc.Scale = 0.86
			K.spring(sc, { Scale = 1 }, { duration = 0.42, amount = 0.3 })
		else
			sc.Scale = 1
		end
	else
		K.cancel(sc)
		K.tween(sc, 0.16, { Scale = 0.86 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.17, function()
			if not cardShown then
				holder.Visible = false
				sc.Scale = 1
			end
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- the police stop order
-------------------------------------------------------------------------------------------------
local stopHolder: Frame
local stopScale: UIScale
local stopRing: any
local stopSerial = 0
local stopOpen = false
local STOP_W, STOP_H = 304, 118

local function stopPlacement()
	local m = metrics()
	local s = m.s or 1
	stopScale.Scale = s
	local w, h = STOP_W * s, STOP_H * s
	local bc = slotRect("bottomCenter")
	local x, bottom
	if bc then
		x, bottom = bc.x + bc.w / 2, bc.y + bc.h
		-- never over the 주먹 button (landscape phones: it sits at the right end of this band)
		local right = punchRect.x - (m.gap or 8)
		if punchRect.y < bottom and punchRect.y + punchRect.h > bottom - h and x + w / 2 > right then
			x = math.max(w / 2 + 8, right - w / 2)
		end
	else
		x, bottom = (m.W or 800) / 2, (m.H or 600) - 90
	end
	stopHolder.Position = UDim2.fromOffset(math.floor(x), math.floor(bottom))
end

local function closeStop()
	stopSerial += 1
	if not stopOpen then
		return
	end
	stopOpen = false
	local sc = stopHolder:FindFirstChild("Card") and (stopHolder :: any).Card:FindFirstChildOfClass("UIScale")
	if sc then
		K.tween(sc, 0.16, { Scale = 0.9 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end
	local mine = stopSerial
	task.delay(0.17, function()
		if stopSerial == mine then
			stopHolder.Visible = false
		end
	end)
end

local function buildStop()
	stopHolder = K.frame(gui, { Name = "StopOrder", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(STOP_W, STOP_H), ZIndex = 6, Visible = false })
	stopScale = K.make("UIScale", { Name = "Fit", Scale = 1 }, stopHolder)
	local c = K.frame(stopHolder, { Name = "Card", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.06, BackgroundColor3 = C.glass, Active = true, ZIndex = 6 })
	K.make("UIScale", { Name = "Pop", Scale = 1 }, c)
	K.corner(c, K.Radius.lg)
	local st = K.stroke(c, C.blue, 1.5, 0.2)
	local icon = K.iconTile(c, 36, "🚔", C.blue, true)
	icon.Position = UDim2.fromOffset(12, 12)
	icon.ZIndex = 7
	for _, d in icon:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 8
		end
	end
	K.text(c, { Name = "Title", Position = UDim2.fromOffset(58, 11), Size = UDim2.new(1, -110, 0, 20), Text = "경찰: 멈춰!", Font = F.heavy, TextSize = K.Type.title2 - 1, ZIndex = 7 })
	K.text(c, { Name = "Body", Position = UDim2.fromOffset(58, 32), Size = UDim2.new(1, -110, 0, 18), Text = "항복하면 벌금이 줄어요", TextColor3 = C.sub, TextSize = K.Type.caption, ZIndex = 7, TextTruncate = Enum.TextTruncate.AtEnd })
	stopRing = K.Ring(c, { size = 38, thickness = 3, color = C.blue, value = 1, text = "6", name = "Timer" })
	stopRing.frame.AnchorPoint = Vector2.new(1, 0)
	stopRing.frame.Position = UDim2.new(1, -12, 0, 11)
	for _, d in stopRing.frame:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 8
		end
	end
	stopRing.label.TextSize = 14
	local row = K.frame(c, { Name = "Buttons", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -24, 0, 44), ZIndex = 7 })
	K.Button(row, {
		name = "Surrender",
		text = "🙌 항복",
		style = "primary",
		size = UDim2.new(0.5, -4, 1, 0),
		zIndex = 8,
		sound = "tap",
		onClick = function()
			ctx.fire("surrender", {})
			closeStop()
		end,
	})
	K.Button(row, {
		name = "Flee",
		text = "🏃 도주",
		style = "danger",
		size = UDim2.new(0.5, -4, 1, 0),
		position = UDim2.new(0.5, 4, 0, 0),
		zIndex = 8,
		sound = "tap",
		onClick = function()
			ctx.fire("flee", {})
			closeStop()
		end,
	})
	local _ = st
end

function Hud.onStop(p: any)
	local timeout = math.clamp(tonumber(p and p.timeout) or Combat.CONFIG.ORDER_TIMEOUT or 6, 1, 20)
	stopSerial += 1
	local mine = stopSerial
	stopOpen = true
	stopPlacement()
	stopHolder.Visible = not hidden
	local c = (stopHolder :: any).Card
	local sc = c:FindFirstChildOfClass("UIScale")
	if sc then
		K.cancel(sc)
		if K.reduced() then
			sc.Scale = 1
		else
			sc.Scale = 0.86
			K.spring(sc, { Scale = 1 }, { duration = 0.42, amount = 0.35 })
		end
	end
	K.pulse(c:FindFirstChildOfClass("UIStroke"), true, 0.05, 0.6)
	pcall(K.feedback, "notify")
	local t0 = os.clock()
	task.spawn(function()
		while stopSerial == mine and stopOpen do
			local left = timeout - (os.clock() - t0)
			if left <= 0 then
				closeStop()
				break
			end
			stopRing.set(left / timeout)
			K.setText(stopRing.label, tostring(math.ceil(left)))
			stopRing.setColor(if left <= 2 then C.red else C.blue)
			stopHolder.Visible = not hidden
			task.wait(0.1)
		end
		K.pulse(c:FindFirstChildOfClass("UIStroke"), false)
	end)
end

function Hud.onStopEnd()
	closeStop()
end

-------------------------------------------------------------------------------------------------
-- KO / transport overlay
-------------------------------------------------------------------------------------------------
local overlayDim: Frame
local overlayTitle: TextLabel
local overlaySub: TextLabel
local overlaySerial = 0

local function buildOverlay()
	overlayGui = makeGui("GwangalliCombatOverlay", 42, true)
	overlayGui.Enabled = false
	overlayGui:SetAttribute("HideGwangalliHUD", true)
	overlayDim = K.frame(overlayGui, { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(4, 6, 12), BackgroundTransparency = 1, Active = false, ZIndex = 1 })
	overlayTitle = K.text(overlayGui, { Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.new(1, -40, 0, 34), Text = "", Font = F.heavy, TextSize = K.Type.title, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1, TextStrokeTransparency = 1, TextStrokeColor3 = Color3.new(0, 0, 0), ZIndex = 2 })
	overlaySub = K.text(overlayGui, { Name = "Sub", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.44, 22), Size = UDim2.new(1, -40, 0, 40), Text = "", TextColor3 = C.sub, TextSize = K.Type.bodySm, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1, ZIndex = 2 })
	overlayGui.Parent = ctx.playerGui
end

local function showOverlay(title: string, sub: string, dim: number, holdFor: number)
	overlaySerial += 1
	local mine = overlaySerial
	overlayGui.Enabled = true
	overlayTitle.Text = title
	overlaySub.Text = sub
	K.tween(overlayDim, 0.6, { BackgroundTransparency = dim })
	K.tween(overlayTitle, 0.5, { TextTransparency = 0, TextStrokeTransparency = 0.6 })
	K.tweenD(overlaySub, 0.5, { TextTransparency = 0 }, nil, nil, 0.15)
	task.delay(holdFor, function()
		if overlaySerial == mine then
			Hud.hideOverlay()
		end
	end)
end

function Hud.hideOverlay()
	overlaySerial += 1
	local mine = overlaySerial
	if not overlayGui.Enabled then
		return
	end
	K.tween(overlayDim, 0.5, { BackgroundTransparency = 1 })
	K.tween(overlayTitle, 0.35, { TextTransparency = 1, TextStrokeTransparency = 1 })
	K.tween(overlaySub, 0.35, { TextTransparency = 1 })
	task.delay(0.55, function()
		if overlaySerial == mine then
			overlayGui.Enabled = false
		end
	end)
end

function Hud.onKO(p: any)
	closeStop()
	if p and p.mode == "arrest" then
		showOverlay("💫 정신을 잃었어요…", "🚓 경찰이 당신을 연행합니다", 0.35, 20)
	else
		showOverlay("💫 정신을 잃었어요…", "🚑 구급차가 병원으로 옮기고 있어요 · 진료비 " .. K.won(Combat.CONFIG.HOSPITAL_FEE or 15000), 0.35, 20)
	end
	pcall(K.feedback, "error")
end

function Hud.onWake()
	Hud.hideOverlay()
end

-------------------------------------------------------------------------------------------------
-- arrest
-------------------------------------------------------------------------------------------------
local modal: any = nil

local function showArrestResult(p: any)
	if modal and not modal.closed then
		pcall(modal.close)
	end
	local details = {}
	local crimes = if type(p.crimes) == "table" then p.crimes else {}
	local shown = 0
	for _, c in crimes do
		if type(c) == "table" then
			shown += 1
			if shown > 4 then
				break
			end
			local label = tostring(c.label or c[1] or "죄목")
			local fine = tonumber(c.fine or c[2])
			table.insert(details, { "· " .. label, if fine then K.won(fine) else "" })
		end
	end
	if #crimes > 4 then
		table.insert(details, { "· 외 " .. tostring(#crimes - 4) .. "건", "" })
	end
	local fine = tonumber(p.fine) or 0
	local paid = tonumber(p.paid) or 0
	local debt = tonumber(p.debt) or math.max(0, fine - paid)
	table.insert(details, { "벌금", K.won(fine), C.red })
	table.insert(details, { "납부", K.won(paid), C.green })
	if debt > 0 then
		table.insert(details, { "미납", K.won(debt), C.orange })
	end
	local record = tonumber(p.record) or tonumber(player:GetAttribute(Combat.Attr.CrimeRecord)) or 0
	table.insert(details, { "전과", tostring(math.max(0, math.floor(record))) .. "회" })
	local body = if p.forced then "도주하거나 저항해서 벌금이 1.5배로 늘었어요." else "벌금을 내고 풀려났어요. 앞으로는 조심하세요!"
	if debt > 0 then
		body ..= "\n미납 벌금은 다음 수입에서 자동으로 빠져나가요."
	end
	modalGui.Enabled = true
	modal = K.Modal(modalGui, {
		title = "체포되었어요",
		body = body,
		icon = "🚔",
		iconColor = C.blue,
		details = details,
		dismissible = false,
		width = 340,
		buttons = { { text = "확인", style = "primary" } },
	})
	local m = modal
	task.spawn(function()
		while m and not m.closed do
			task.wait(0.2)
		end
		task.wait(0.2)
		if modal == m or modal == nil or modal.closed then
			modalGui.Enabled = false
		end
	end)
end

function Hud.onArrest(p: any)
	closeStop()
	if p.phase == "start" then
		showOverlay("🚓 광안지구대로 연행 중…", "수갑이 채워졌어요. 잠시만 기다려 주세요", 0.3, 15)
	elseif p.phase == "done" then
		Hud.hideOverlay()
		showArrestResult(p)
	end
end

-------------------------------------------------------------------------------------------------
-- toasts
-------------------------------------------------------------------------------------------------
function Hud.onCrime(p: any)
	local label = tostring(p.label or (Combat.CRIMES[p.crime or ""] or {}).label or "범죄")
	local n = Combat.clampStars(tonumber(p.stars) or tonumber(player:GetAttribute(Combat.Attr.Wanted)) or 1)
	K.toast({
		kind = "warn",
		icon = "🚨",
		color = C.red,
		title = label .. " · 수배 " .. Combat.starsText(n),
		body = if p.reported then "목격자가 112에 신고했어요. 경찰이 출동합니다!" else "경찰이 출동합니다!",
		duration = 3.5,
		force = true,
	})
end

function Hud.onEscaped(_p: any)
	K.toast({ kind = "success", icon = "🏃", title = "경찰을 따돌렸어요", body = "수배가 해제됐어요", duration = 3.5, force = true })
end

function Hud.onSearch(p: any)
	local left = tonumber(p and p.left)
	if left then
		searchLeft = math.max(0, left)
		setLine()
	end
end

-------------------------------------------------------------------------------------------------
-- hurt / swing / miss
-------------------------------------------------------------------------------------------------
function Hud.onHurt(p: any)
	hurtAt = os.clock()
	local dmg = tonumber(p.dmg) or 0
	local h, m = tonumber(p.hp), tonumber(p.maxHp)
	if h and m then
		hp, maxHp = h, m
		setHP(h, m, true)
	end
	showDamage(dmg)
	Hud.refresh()
end

function Hud.onSwing(_combo: number, _hasTarget: boolean)
	if not P then
		return
	end
	P.fill.Enabled = true
	P.button.BackgroundColor3 = Color3.new(1, 1, 1)
	P.button.BackgroundTransparency = 0
	task.delay(0.12, function()
		P.fill.Enabled = false
		P.button.BackgroundColor3 = C.glass
		P.button.BackgroundTransparency = K.GLASS_T or 0.14
	end)
end

function Hud.onMiss(_reason: any)
	if not P then
		return
	end
	-- a small shake of the button (too far / not facing / too fast)
	local b = P.button
	K.cancel(b)
	b.Rotation = 7
	K.tweenD(b, 0.25, { Rotation = 0 }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
end

-------------------------------------------------------------------------------------------------
-- layout + visibility
-------------------------------------------------------------------------------------------------
local function layout()
	local r, pc = punchPlacement()
	punchRect = r
	local bw, bh = math.floor(math.max(44, r.w)), math.floor(math.max(44, r.h))
	stylePunch(bw, bh, pc)
	punchRest = UDim2.fromOffset(math.floor(r.x + (r.w - bw) / 2), math.floor(r.y + (r.h - bh) / 2))
	if layerState[P.button] ~= "leaving" then
		P.button.Position = punchRest
	end
	cardPlacement()
	stopPlacement()
end

function Hud.hidden(): boolean
	return hidden
end

local BLOCK_HIDE = { dead = true, seated = true, busy = true, arrested = true, ko = true, pose = true }
function Hud.refresh()
	if not P then
		return
	end
	local reason = ctx.blockReason()
	local showPunch = ctx.ready and not hidden and not (reason and BLOCK_HIDE[reason])
	if showPunch ~= punchShown then
		punchShown = showPunch
		setLayer(P.button, showPunch, punchRest, UDim2.fromOffset(96, 0))
	end
	local calm = hp >= maxHp - 0.5 and wanted <= 0 and not chasing and os.clock() - hurtAt > 5
	setCardShown(not hidden and not calm and ctx.ready)
	if stopOpen then
		stopHolder.Visible = not hidden
	end
end

-- other full-screen UIs: HideGwangalliHUD on an enabled ScreenGui (ours included, except this layer)
local watchedGuis: { [Instance]: { RBXScriptConnection } } = {}
local function updateHidden()
	local hide = false
	for other in watchedGuis do
		if other.Parent and (other :: ScreenGui).Enabled and other:GetAttribute("HideGwangalliHUD") == true then
			hide = true
			break
		end
	end
	if hide ~= hidden then
		hidden = hide
		Hud.refresh()
	end
end
local function watchGui(inst: Instance)
	if inst == gui or not inst:IsA("ScreenGui") or watchedGuis[inst] then
		return
	end
	watchedGuis[inst] = {
		inst:GetPropertyChangedSignal("Enabled"):Connect(updateHidden),
		inst:GetAttributeChangedSignal("HideGwangalliHUD"):Connect(updateHidden),
	}
	updateHidden()
end

-------------------------------------------------------------------------------------------------
-- attributes / humanoid
-------------------------------------------------------------------------------------------------
local humConns: { RBXScriptConnection } = {}
local function watchHumanoid(ch: Model)
	for _, c in humConns do
		c:Disconnect()
	end
	table.clear(humConns)
	local hum = ch:FindFirstChildOfClass("Humanoid") or ch:WaitForChild("Humanoid", 10)
	if not hum or not hum:IsA("Humanoid") then
		return
	end
	local h = hum :: Humanoid
	hp, maxHp = h.Health, h.MaxHealth
	trailP = math.clamp(hp / math.max(maxHp, 1), 0, 1)
	setHP(hp, maxHp, false)
	local function changed()
		local was = hp
		hp, maxHp = h.Health, h.MaxHealth
		setHP(hp, maxHp, true)
		if hp < was - 0.5 then
			hurtAt = os.clock()
		end
		Hud.refresh()
	end
	table.insert(humConns, h.HealthChanged:Connect(changed))
	table.insert(humConns, h:GetPropertyChangedSignal("MaxHealth"):Connect(changed))
	Hud.refresh()
end

local function readPlayer()
	local A = Combat.Attr
	local w = tonumber(player:GetAttribute(A.Wanted)) or 0
	local ch = player:GetAttribute(A.PoliceChase) == true
	local sl = tonumber(player:GetAttribute(A.WantedSearch)) or 0
	local changedStars = w ~= wanted or ch ~= chasing
	wanted, chasing, searchLeft = Combat.clampStars(w), ch, math.max(0, sl)
	if changedStars then
		setWanted(wanted, chasing)
	end
	if ctx.Fx then
		ctx.Fx.setChase(chasing and wanted > 0)
	end
	setLine()
	Hud.refresh()
end

-------------------------------------------------------------------------------------------------
-- init
-------------------------------------------------------------------------------------------------
function Hud.init(c: any)
	ctx = c
	K = ctx.K
	Layout = ctx.Layout
	Combat = ctx.Combat
	C = K.Color
	F = K.Font
	player = Players.LocalPlayer
	gui = makeGui("GwangalliCombatHUD", 9, false)
	gui:SetAttribute("HideGwangalliHUD", false)
	buildPunch()
	buildCard()
	buildStop()
	gui.Parent = ctx.playerGui
	buildOverlay()
	modalGui = makeGui("GwangalliCombatModal", 48, false)
	modalGui.Enabled = false
	modalGui:SetAttribute("HideGwangalliHUD", true)
	modalGui.Parent = ctx.playerGui
	-- Roblox's own health bar: our card replaces it
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	-- layout
	if Layout and type(Layout.onChanged) == "function" then
		Layout.onChanged(layout)
	else
		layout()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				task.defer(layout)
			end)
		end
	end
	-- other UIs
	ctx.playerGui.ChildAdded:Connect(watchGui)
	ctx.playerGui.ChildRemoved:Connect(function(inst)
		local conns = watchedGuis[inst]
		if conns then
			for _, cn in conns do
				cn:Disconnect()
			end
			watchedGuis[inst] = nil
			updateHidden()
		end
	end)
	for _, child in ctx.playerGui:GetChildren() do
		watchGui(child)
	end
	-- state sources
	local A = Combat.Attr
	for _, name in { A.Wanted, A.PoliceChase, A.WantedSearch, A.Arrested } do
		player:GetAttributeChangedSignal(name):Connect(readPlayer)
	end
	readPlayer()
	if player.Character then
		task.spawn(watchHumanoid, player.Character)
	end
	player.CharacterAdded:Connect(function(ch)
		closeStop()
		watchHumanoid(ch)
	end)
	-- the button follows seats / shifts / poses; the card times out after a hit; the card re-checks the tracker
	task.spawn(function()
		local n = 0
		while gui.Parent do
			task.wait(0.25)
			n += 1
			local ok, err = pcall(Hud.refresh)
			if not ok then
				ctx.warnOnce("hud-refresh", "[GwangalliCombat] hud: " .. tostring(err))
			end
			if cardShown and n % 4 == 0 then
				pcall(cardPlacement)
			end
		end
	end)
end

-- test / debug snapshot
function Hud.state(): any
	return {
		hidden = hidden,
		punch = punchShown == true,
		punchPos = { punchRect.x, punchRect.y, punchRect.w, punchRect.h },
		card = cardShown,
		stop = stopOpen,
		overlay = overlayGui and overlayGui.Enabled or false,
		modal = modalGui and modalGui.Enabled or false,
		hp = hp,
		wanted = wanted,
	}
end

return Hud
