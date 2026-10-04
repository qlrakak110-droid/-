-- GwangalliInteractClient/Hud: the street HUD. 👊 주먹 button (F) above the 어깨빵 button,
-- 🗨 상호작용 (G) when somebody is in front of you -> the interaction wheel: the 15 verbs ordered for
-- that person (사과 / 도망 first while they are angry at you, 돈 주기 first for 김씨, 신고 first for a cop
-- ...), 7 per page + ▶ 더보기 (keys 1-8), ⇄ 대상 바꾸기 (Tab) when several people stand in front of
-- you, 📞 112 when you just saw something happen. Also the target chip (name, role, mood / quarrel,
-- HP), the wanted stars (★ under the clock, blinking while the police search for you), your HP bar,
-- red hit flashes, floating damage numbers, the crime / ticket banners, police radio lines, 🙌 항복
-- near the police, and the full-screen 기절 WASTED / 체포 BUSTED cards. Placed with GwangalliLayout
-- (no overlap with the 어깨빵 / sprint / phone buttons); GwangalliUI kit tokens; 64 px buttons on touch.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local H = {}

local C: any
local K: any
local Layout: any
local player = Players.LocalPlayer

local COL = {
	glass = Color3.fromRGB(15, 18, 31),
	text = Color3.fromRGB(245, 247, 251),
	sub = Color3.fromRGB(170, 177, 196),
	red = Color3.fromRGB(255, 90, 95),
	gold = Color3.fromRGB(255, 194, 71),
	blue = Color3.fromRGB(84, 140, 255),
	green = Color3.fromRGB(61, 220, 132),
	orange = Color3.fromRGB(255, 176, 32),
	magenta = Color3.fromRGB(255, 79, 163),
}
local FONT = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold
local FONT_HEAVY = Enum.Font.GothamBlack

local gui: ScreenGui
local fx: ScreenGui
local playerGui: PlayerGui
local BTN = 56
local touch = false

local punchBtn: TextButton
local interactBtn: TextButton
local surrenderBtn: TextButton
local switchBtn: TextButton
local callBtn: TextButton
local targetName: TextLabel
local starsFrame: Frame
local starLabels: { TextLabel } = {}
local hpFrame: Frame
local hpFill: Frame
local hpText: TextLabel
local wheel: Frame
local wheelButtons: { TextButton } = {}
local wheelTitle: TextLabel
local chip: BillboardGui
local chipName: TextLabel
local chipSub: TextLabel
local chipHp: Frame
local chipHpFill: Frame
local flashFrames: { Frame } = {}
local banner: Frame
local bannerText: TextLabel
local bannerSub: TextLabel
local overlay: Frame
local overlayTitle: TextLabel
local overlaySub: TextLabel
local overlayBody: TextLabel

local cb: any = {}
local state = { stars = 0, seen = false, hp = 100, max = 100, hpShownUntil = 0, wheelTarget = nil :: any, cdUntil = 0, flashT = 0, verbs = {} :: { string }, page = 1, slots = {} :: { string }, callUntil = 0, multi = false }
local WHEEL_SLOTS = 8

local function tween(inst: Instance, t: number, goals: any, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local ok, tw = pcall(function()
		return TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goals)
	end)
	if ok and tw then
		tw:Play()
	end
	return tw
end

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function stroke(inst: Instance, color: Color3, th: number, tr: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = th
	s.Transparency = tr
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function label(parent: Instance, props: any): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = props.Font or FONT_BOLD
	t.TextSize = props.TextSize or 14
	t.TextColor3 = props.TextColor3 or COL.text
	t.Text = props.Text or ""
	for k, v in props do
		if k ~= "Font" and k ~= "TextSize" and k ~= "TextColor3" and k ~= "Text" then
			(t :: any)[k] = v
		end
	end
	t.Parent = parent
	return t
end

local function feedback(kind: string)
	if K and K.feedback then
		pcall(K.feedback, kind)
	end
end

local function roundButton(name: string, glyph: string, caption: string, key: string?, accent: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(1, 1)
	b.Size = UDim2.fromOffset(BTN, BTN)
	b.BackgroundColor3 = COL.glass
	b.BackgroundTransparency = 0.14
	b.AutoButtonColor = false
	b.Text = ""
	b.Active = true
	b.Parent = gui
	corner(b, 18)
	stroke(b, accent, 1.5, 0.2)
	label(b, { Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromScale(0.6, 0.42), TextScaled = true, Text = glyph })
	label(b, { Name = "Caption", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -5), Size = UDim2.new(1, -4, 0, 14), TextSize = 12, Text = caption })
	if key and not touch then
		label(b, { Name = "Key", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 3), Size = UDim2.fromOffset(14, 12), TextSize = 11, Font = FONT, TextColor3 = COL.sub, Text = key })
	end
	if K and K.pressable then
		pcall(K.pressable, b)
	end
	return b
end

---------------------------------------------------------------------------------------------------
-- layout
---------------------------------------------------------------------------------------------------
local function layout()
	local left, bottom = nil, nil
	if Layout and Layout.slot then
		local ok, pos, size, anchor = pcall(Layout.slot, "rightColumn")
		if ok and typeof(pos) == "UDim2" and typeof(size) == "UDim2" and size.X.Offset > 0 then
			local a = if typeof(anchor) == "Vector2" then anchor else Vector2.new(0.5, 1)
			left = pos.X.Offset - size.X.Offset * a.X
			bottom = pos.Y.Offset + size.Y.Offset * (1 - a.Y)
		end
	end
	if not left then
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(844, 390)
		left = vp.X - (if touch then 186 else 96)
		bottom = vp.Y - (if touch then 28 else 24)
	end
	-- 주먹 sits right above the 어깨빵 button (GwangalliBump: bottom-right corner at (left - 14, bottom))
	punchBtn.Position = UDim2.fromOffset(left - 14, bottom - BTN - 12)
	interactBtn.Position = UDim2.fromOffset(left - 14 - BTN - 12, bottom - BTN - 12)
	surrenderBtn.Position = UDim2.fromOffset(left - 14 - BTN - 12, bottom)
	-- ⇄ above 상호작용, 📞 112 left of it (the column stays clear of the 어깨빵 / sprint buttons)
	switchBtn.Position = UDim2.fromOffset(left - 14 - BTN - 12, bottom - 2 * BTN - 24)
	callBtn.Position = UDim2.fromOffset(left - 14 - 2 * (BTN + 12), bottom - BTN - 12)
	targetName.Position = UDim2.fromOffset(left - 14 - BTN - 12 + BTN / 2 + 30, bottom - 2 * BTN - 16 - (if switchBtn.Visible then BTN + 8 else 0))
	-- stars + HP under the clock chip
	local cx, y = nil, nil
	if Layout and Layout.rect then
		local ok, r = pcall(Layout.rect, "topCenter")
		if ok and type(r) == "table" and r.w then
			cx = r.x + r.w / 2
			y = r.y + r.h + 8
		end
	end
	if not cx then
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(844, 390)
		cx = vp.X / 2
		y = 64
	end
	starsFrame.Position = UDim2.fromOffset(cx, y)
	hpFrame.Position = UDim2.fromOffset(cx, y + (if starsFrame.Visible then 34 else 0))
	-- the wheel: centred, scaled to the screen height
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(844, 390)
	local scale = math.clamp((vp.Y - 120) / 300, 0.72, 1.1)
	wheel.Size = UDim2.fromOffset(300 * scale, 300 * scale)
	local uis = wheel:FindFirstChildOfClass("UIScale")
	if uis then
		uis.Scale = 1
	end
	local shown = 0
	for _, b in wheelButtons do
		if b.Visible then
			shown += 1
		end
	end
	local k = 0
	for _, b in wheelButtons do
		if b.Visible then
			local ang = -math.pi / 2 + k * (2 * math.pi / math.max(1, shown))
			local r = 112 * scale
			b.Size = UDim2.fromOffset(74 * scale, 74 * scale)
			b.Position = UDim2.new(0.5, math.cos(ang) * r, 0.5, math.sin(ang) * r)
			k += 1
		end
	end
end

---------------------------------------------------------------------------------------------------
-- target chip + buttons
---------------------------------------------------------------------------------------------------
function H.setTarget(t: any?, multi: boolean?)
	local m = t ~= nil and multi == true and not state.wheelTarget
	if m ~= state.multi then
		state.multi = m
		switchBtn.Visible = m
		layout()
	end
	if t then
		interactBtn.Visible = not state.wheelTarget
		targetName.Visible = true
		targetName.Text = t.name .. (if t.sub and t.sub ~= "" then " · " .. t.sub else "")
		chip.Adornee = t.part
		chip.Enabled = true
		chipName.Text = t.name
		chipSub.Text = t.sub or ""
		chipSub.TextColor3 = t.color or COL.sub
		local k = if t.hp and t.max and t.max > 0 then math.clamp(t.hp / t.max, 0, 1) else 1
		chipHp.Visible = k < 0.999
		chipHpFill.Size = UDim2.fromScale(k, 1)
		chipHpFill.BackgroundColor3 = if k > 0.5 then COL.green elseif k > 0.25 then COL.orange else COL.red
	else
		interactBtn.Visible = false
		targetName.Visible = false
		chip.Enabled = false
		chip.Adornee = nil
	end
end

function H.punchFeedback()
	state.cdUntil = os.clock() + C.PUNCH_CD
	punchBtn.BackgroundTransparency = 0.45
	local g = punchBtn:FindFirstChild("Glyph") :: TextLabel?
	if g then
		g.Rotation = -18
		tween(g, 0.18, { Rotation = 0 }, Enum.EasingStyle.Back)
	end
end

function H.miss()
	punchBtn.Rotation = 8
	tween(punchBtn, 0.25, { Rotation = 0 }, Enum.EasingStyle.Elastic)
	feedback("error")
end

function H.setSurrender(on: boolean)
	surrenderBtn.Visible = on
end

---------------------------------------------------------------------------------------------------
-- the interaction wheel
---------------------------------------------------------------------------------------------------
function H.wheelOpen(): boolean
	return state.wheelTarget ~= nil
end

local function verbDef(id: string): any
	if id == "_more" then
		return { id = "_more", label = "더보기", icon = "▶" }
	elseif id == "_back" then
		return { id = "_back", label = "이전", icon = "◀" }
	end
	return C.VERB[id]
end

local ACCENT = { punch = "red", rob = "red", shove = "red", provoke = "red", tease = "orange", give = "green", food = "green", talk = "green", greet = "green", apologize = "green", help = "blue", report = "blue", ask = "blue", flee = "gold", joke = "gold" }

-- fill the slots with the current page (7 verbs + ▶/◀ when there are more than 8)
local function showPage()
	local verbs = state.verbs
	local slots = {}
	if #verbs <= WHEEL_SLOTS then
		slots = table.clone(verbs)
	else
		local per = WHEEL_SLOTS - 1
		local pages = math.ceil(#verbs / per)
		state.page = math.clamp(state.page, 1, pages)
		for i = (state.page - 1) * per + 1, math.min(#verbs, state.page * per) do
			table.insert(slots, verbs[i])
		end
		table.insert(slots, if state.page < pages then "_more" else "_back")
	end
	state.slots = slots
	for i, b in wheelButtons do
		local id = slots[i]
		local v = id and verbDef(id)
		if v then
			b.Visible = true
			b:SetAttribute("Verb", id)
			local icon = b:FindFirstChild("Icon") :: TextLabel?
			local lab = b:FindFirstChild("Label") :: TextLabel?
			if icon then
				icon.Text = v.icon
			end
			if lab then
				lab.Text = v.label
			end
			local st = b:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = COL[ACCENT[id] or "orange"] or COL.orange
			end
		else
			b.Visible = false
			b:SetAttribute("Verb", nil)
		end
	end
	layout()
end

function H.openWheel(t: any, verbs: { string }?)
	state.wheelTarget = t
	state.verbs = verbs or {}
	state.page = 1
	wheelTitle.Text = t.name .. (if t.sub and t.sub ~= "" then "\n" .. t.sub else "")
	wheel.Visible = true
	interactBtn.Visible = false
	switchBtn.Visible = false
	wheel.Size = UDim2.fromOffset(10, 10)
	showPage()
	local target = wheel.Size
	wheel.Size = UDim2.fromOffset(target.X.Offset * 0.6, target.Y.Offset * 0.6)
	tween(wheel, 0.22, { Size = target }, Enum.EasingStyle.Back)
	feedback("open")
end

-- slot i (keys 1-8 / a tap): a verb id, or nil after turning the page
function H.pick(i: number): string?
	local id = state.slots[i]
	if id == "_more" then
		state.page += 1
		showPage()
		feedback("tap")
		return nil
	elseif id == "_back" then
		state.page = 1
		showPage()
		feedback("tap")
		return nil
	end
	return id
end

function H.closeWheel()
	if not state.wheelTarget then
		return
	end
	state.wheelTarget = nil
	wheel.Visible = false
	state.multi = false
	feedback("close")
end

-- 📞 112 for a while after something happened near you
function H.showCall(secs: number)
	state.callUntil = math.max(state.callUntil, os.clock() + secs)
end

function H.wheelTarget(): any
	return state.wheelTarget
end

---------------------------------------------------------------------------------------------------
-- wanted stars + HP
---------------------------------------------------------------------------------------------------
function H.setWanted(stars: number, seen: boolean)
	local prev = state.stars
	state.stars = stars
	state.seen = seen
	starsFrame.Visible = stars > 0
	for i, l in starLabels do
		l.Text = if i <= stars then "★" else "☆"
		l.TextColor3 = if i <= stars then Color3.new(1, 1, 1) else Color3.fromRGB(150, 156, 176)
		l.TextTransparency = if i <= stars then 0 else 0.35
	end
	if stars > prev then
		for i = prev + 1, stars do
			local l = starLabels[i]
			if l then
				l.TextSize = 40
				tween(l, 0.35, { TextSize = 24 }, Enum.EasingStyle.Back)
			end
		end
	end
	layout()
end

function H.setHP(hp: number, max: number)
	local was = state.hp
	state.hp = hp
	state.max = max
	local k = math.clamp(hp / math.max(1, max), 0, 1)
	hpFill.Size = UDim2.fromScale(k, 1)
	hpFill.BackgroundColor3 = if k > 0.5 then COL.green elseif k > 0.25 then COL.orange else COL.red
	hpText.Text = "❤ " .. math.floor(hp + 0.5)
	if hp < max or hp < was then
		state.hpShownUntil = os.clock() + 4
	end
end

---------------------------------------------------------------------------------------------------
-- effects
---------------------------------------------------------------------------------------------------
function H.hurtFlash(strength: number)
	state.flashT = os.clock()
	for _, f in flashFrames do
		f.BackgroundTransparency = 1 - math.clamp(strength, 0.25, 0.85)
		tween(f, 0.45, { BackgroundTransparency = 1 })
	end
end

-- a floating number / word over a part
function H.pop(part: BasePart?, text: string, color: Color3?, big: boolean?)
	if not part then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "GiPop"
	bb.Size = UDim2.fromOffset(120, 40)
	bb.StudsOffsetWorldSpace = Vector3.new((math.random() - 0.5) * 1.2, 2.6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 80
	bb.Adornee = part
	local t = label(bb, { Size = UDim2.fromScale(1, 1), Font = FONT_HEAVY, TextSize = if big then 30 else 22, TextColor3 = color or COL.text, Text = text, TextStrokeTransparency = 0.2, TextStrokeColor3 = Color3.new(0, 0, 0) })
	bb.Parent = playerGui
	tween(bb, 0.9, { StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(0, 2.2, 0) })
	task.delay(0.45, function()
		tween(t, 0.45, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	task.delay(1, function()
		bb:Destroy()
	end)
end

function H.banner(text: string, sub: string?, color: Color3?)
	bannerText.Text = text
	bannerText.TextColor3 = color or COL.text
	bannerSub.Text = sub or ""
	banner.Visible = true
	bannerText.TextTransparency = 0
	bannerText.TextStrokeTransparency = 0.3
	bannerSub.TextTransparency = 0
	bannerSub.TextStrokeTransparency = 0.4
	bannerText.TextSize = 40
	tween(bannerText, 0.3, { TextSize = 30 }, Enum.EasingStyle.Back)
	local seq = (banner:GetAttribute("Seq") or 0) + 1
	banner:SetAttribute("Seq", seq)
	task.delay(2.2, function()
		if banner:GetAttribute("Seq") == seq then
			tween(bannerText, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
			tween(bannerSub, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
			task.delay(0.42, function()
				if banner:GetAttribute("Seq") == seq then
					banner.Visible = false
				end
			end)
		end
	end)
end

function H.toast(title: string, body: string?, icon: string?, kind: string?)
	if K and K.toast then
		pcall(K.toast, { kind = kind or "warn", title = title, body = body, icon = icon, duration = 3.5, color = COL.blue })
	end
end

-- 기절 WASTED / 체포 BUSTED
function H.overlay(kind: string, body: string?)
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	if kind == "wasted" then
		overlayTitle.Text = "기절"
		overlaySub.Text = "W A S T E D"
		overlayTitle.TextColor3 = Color3.fromRGB(235, 60, 60)
		overlay.BackgroundColor3 = Color3.fromRGB(60, 8, 8)
	else
		overlayTitle.Text = "체포"
		overlaySub.Text = "B U S T E D"
		overlayTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
		overlay.BackgroundColor3 = Color3.fromRGB(8, 14, 40)
	end
	overlayBody.Text = body or ""
	overlayTitle.TextTransparency = 1
	overlaySub.TextTransparency = 1
	overlayBody.TextTransparency = 1
	overlayTitle.TextSize = 96
	tween(overlay, 1.2, { BackgroundTransparency = 0.38 })
	task.delay(0.6, function()
		tween(overlayTitle, 0.5, { TextTransparency = 0, TextSize = 72 }, Enum.EasingStyle.Back)
		tween(overlaySub, 0.8, { TextTransparency = 0.1 })
		tween(overlayBody, 0.8, { TextTransparency = 0.15 })
	end)
end

function H.clearOverlay()
	if not overlay.Visible then
		return
	end
	tween(overlay, 0.5, { BackgroundTransparency = 1 })
	tween(overlayTitle, 0.4, { TextTransparency = 1 })
	tween(overlaySub, 0.4, { TextTransparency = 1 })
	tween(overlayBody, 0.4, { TextTransparency = 1 })
	task.delay(0.55, function()
		overlay.Visible = false
	end)
end

local function hudHidden(): boolean
	for _, g in playerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= gui and g ~= fx and g.Enabled and g:GetAttribute("HideGwangalliHUD") == true then
			return true
		end
	end
	return false
end

function H.step(_dt: number, canFight: boolean)
	local now = os.clock()
	local hidden = hudHidden()
	gui.Enabled = not hidden
	punchBtn.Visible = canFight
	if not canFight then
		interactBtn.Visible = false
		if state.wheelTarget then
			H.closeWheel()
		end
	end
	if now >= state.cdUntil and punchBtn.BackgroundTransparency ~= 0.14 then
		punchBtn.BackgroundTransparency = 0.14
	end
	-- stars: steady while a cop sees you, blinking while they search
	if state.stars > 0 then
		local blink = not state.seen and math.floor(now * 3) % 2 == 0
		for i = 1, state.stars do
			local l = starLabels[i]
			if l then
				l.TextTransparency = if blink then 0.75 else 0
			end
		end
	end
	local showHp = state.hp < state.max - 0.5 or now < state.hpShownUntil
	hpFrame.Visible = showHp
	callBtn.Visible = canFight and now < state.callUntil and not state.wheelTarget
end

---------------------------------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------------------------------
function H.init(deps: any)
	C = deps.C
	K = deps.K
	Layout = deps.Layout
	cb = deps.callbacks
	touch = UserInputService.TouchEnabled
	BTN = if touch then 64 else 56
	if K and K.Color then
		COL.glass = K.Color.glass or COL.glass
		COL.text = K.Color.text or COL.text
		COL.sub = K.Color.sub or COL.sub
		COL.red = K.Color.red or COL.red
		COL.gold = K.Color.gold or COL.gold
		COL.blue = K.Color.blue or COL.blue
		COL.green = K.Color.green or COL.green
		COL.orange = K.Color.orange or COL.orange
		COL.magenta = K.Color.magenta or COL.magenta
	end
	if K and K.Font then
		FONT = K.Font.regular or FONT
		FONT_BOLD = K.Font.bold or FONT_BOLD
		FONT_HEAVY = K.Font.heavy or FONT_HEAVY
	end
	playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	gui = Instance.new("ScreenGui")
	gui.Name = "GwangalliInteract"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 31
	gui.Parent = playerGui
	fx = Instance.new("ScreenGui")
	fx.Name = "GwangalliInteractFX"
	fx.ResetOnSpawn = false
	fx.IgnoreGuiInset = true
	fx.DisplayOrder = 61
	fx.Parent = playerGui

	-- buttons
	punchBtn = roundButton("PunchButton", "👊", "주먹", "F", COL.red)
	interactBtn = roundButton("InteractButton", "🗨️", "상호작용", "G", COL.gold)
	interactBtn.Visible = false
	surrenderBtn = roundButton("SurrenderButton", "🙌", "항복", "H", COL.blue)
	surrenderBtn.Visible = false
	switchBtn = roundButton("SwitchTargetButton", "⇄", "대상 바꾸기", "Tab", COL.sub)
	switchBtn.Size = UDim2.fromOffset(BTN, math.floor(BTN * 0.78))
	switchBtn.Visible = false
	callBtn = roundButton("Call112Button", "📞", "112 신고", "J", COL.blue)
	callBtn.Visible = false
	switchBtn.Activated:Connect(function()
		if cb.switch then
			cb.switch()
		end
	end)
	callBtn.Activated:Connect(function()
		state.callUntil = 0
		if cb.call112 then
			cb.call112()
		end
	end)
	targetName = label(gui, { Name = "TargetName", AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(220, 16), TextSize = 11, Font = FONT, TextColor3 = COL.sub, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, Visible = false })
	punchBtn.Activated:Connect(function()
		if cb.punch then
			cb.punch()
		end
	end)
	interactBtn.Activated:Connect(function()
		if cb.interact then
			cb.interact()
		end
	end)
	surrenderBtn.Activated:Connect(function()
		if cb.surrender then
			cb.surrender()
		end
	end)

	-- wanted stars
	starsFrame = Instance.new("Frame")
	starsFrame.Name = "Wanted"
	starsFrame.AnchorPoint = Vector2.new(0.5, 0)
	starsFrame.Size = UDim2.fromOffset(170, 30)
	starsFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
	starsFrame.BackgroundTransparency = 0.35
	starsFrame.Visible = false
	starsFrame.Parent = gui
	corner(starsFrame, 15)
	stroke(starsFrame, COL.red, 1.2, 0.3)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 2)
	list.Parent = starsFrame
	label(starsFrame, { Name = "Siren", Size = UDim2.fromOffset(24, 26), TextSize = 16, Text = "🚨", LayoutOrder = 0 })
	for i = 1, C.MAX_STARS do
		starLabels[i] = label(starsFrame, { Name = "Star" .. i, Size = UDim2.fromOffset(26, 28), TextSize = 24, Text = "☆", LayoutOrder = i, Font = FONT_HEAVY })
	end

	-- HP
	hpFrame = Instance.new("Frame")
	hpFrame.Name = "HP"
	hpFrame.AnchorPoint = Vector2.new(0.5, 0)
	hpFrame.Size = UDim2.fromOffset(170, 20)
	hpFrame.BackgroundTransparency = 1
	hpFrame.Visible = false
	hpFrame.Parent = gui
	hpText = label(hpFrame, { Name = "Label", Size = UDim2.fromOffset(44, 20), TextSize = 13, Text = "❤ 100", TextXAlignment = Enum.TextXAlignment.Left })
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromOffset(46, 6)
	bar.Size = UDim2.new(1, -46, 0, 8)
	bar.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
	bar.BackgroundTransparency = 0.2
	bar.BorderSizePixel = 0
	bar.Parent = hpFrame
	corner(bar, 4)
	hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.BackgroundColor3 = COL.green
	hpFill.BorderSizePixel = 0
	hpFill.Parent = bar
	corner(hpFill, 4)

	-- the wheel
	wheel = Instance.new("Frame")
	wheel.Name = "Wheel"
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Position = UDim2.fromScale(0.5, 0.5)
	wheel.Size = UDim2.fromOffset(300, 300)
	wheel.BackgroundTransparency = 1
	wheel.Visible = false
	wheel.Parent = gui
	local center = Instance.new("TextButton")
	center.Name = "Close"
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.fromScale(0.34, 0.34)
	center.BackgroundColor3 = COL.glass
	center.BackgroundTransparency = 0.1
	center.AutoButtonColor = false
	center.Text = ""
	center.Parent = wheel
	corner(center, 999)
	stroke(center, COL.gold, 1.5, 0.3)
	wheelTitle = label(center, { Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 0), Size = UDim2.new(0.92, 0, 0.5, 0), TextScaled = true, Text = "" })
	label(center, { Name = "X", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, 0, 0, 14), TextSize = 12, Font = FONT, TextColor3 = COL.sub, Text = "✕ 닫기" })
	center.Activated:Connect(function()
		H.closeWheel()
	end)
	for i = 1, WHEEL_SLOTS do
		local b = Instance.new("TextButton")
		b.Name = "Slot" .. i
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Size = UDim2.fromOffset(74, 74)
		b.BackgroundColor3 = COL.glass
		b.BackgroundTransparency = 0.08
		b.AutoButtonColor = false
		b.Text = ""
		b.Visible = false
		b.Parent = wheel
		corner(b, 999)
		stroke(b, COL.orange, 1.5, 0.15)
		label(b, { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(0.5, 0.36), TextScaled = true, Text = "" })
		label(b, { Name = "Label", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromScale(0.9, 0.2), TextScaled = true, Text = "" })
		if not touch then
			label(b, { Name = "Key", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.04), Size = UDim2.fromScale(0.3, 0.16), TextScaled = true, Font = FONT, TextColor3 = COL.sub, Text = tostring(i) })
		end
		if K and K.pressable then
			pcall(K.pressable, b)
		end
		b.Activated:Connect(function()
			local id = H.pick(i)
			if id and cb.verb then
				cb.verb(id)
			end
		end)
		wheelButtons[i] = b
	end

	-- target chip (over the target's head)
	chip = Instance.new("BillboardGui")
	chip.Name = "GiTargetChip"
	chip.Size = UDim2.fromOffset(150, 46)
	chip.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	chip.AlwaysOnTop = true
	chip.LightInfluence = 0
	chip.MaxDistance = 40
	chip.Enabled = false
	chip.Parent = playerGui
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.fromScale(0.5, 0)
	box.Size = UDim2.new(1, 0, 0, 40)
	box.BackgroundColor3 = COL.glass
	box.BackgroundTransparency = 0.2
	box.Parent = chip
	corner(box, 10)
	stroke(box, COL.gold, 1.2, 0.35)
	chipName = label(box, { Name = "Name", Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 18), TextSize = 14, Text = "" })
	chipSub = label(box, { Name = "Sub", Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 14), TextSize = 11, Font = FONT, TextColor3 = COL.sub, Text = "" })
	chipHp = Instance.new("Frame")
	chipHp.Name = "HP"
	chipHp.AnchorPoint = Vector2.new(0.5, 0)
	chipHp.Position = UDim2.new(0.5, 0, 0, 33)
	chipHp.Size = UDim2.new(0.7, 0, 0, 4)
	chipHp.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
	chipHp.BorderSizePixel = 0
	chipHp.Visible = false
	chipHp.Parent = box
	chipHpFill = Instance.new("Frame")
	chipHpFill.Size = UDim2.fromScale(1, 1)
	chipHpFill.BorderSizePixel = 0
	chipHpFill.BackgroundColor3 = COL.green
	chipHpFill.Parent = chipHp

	-- red edge flash
	for i, spec in { { UDim2.new(1, 0, 0, 70), UDim2.fromScale(0, 0) }, { UDim2.new(1, 0, 0, 70), UDim2.new(0, 0, 1, -70) }, { UDim2.new(0, 70, 1, 0), UDim2.fromScale(0, 0) }, { UDim2.new(0, 70, 1, 0), UDim2.new(1, -70, 0, 0) } } do
		local f = Instance.new("Frame")
		f.Name = "Flash" .. i
		f.Size = spec[1]
		f.Position = spec[2]
		f.BackgroundColor3 = Color3.fromRGB(220, 20, 30)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = fx
		local g = Instance.new("UIGradient")
		local rot = ({ 90, 270, 0, 180 })[i]
		g.Rotation = rot
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
		flashFrames[i] = f
	end

	-- crime banner
	banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.3)
	banner.Size = UDim2.fromOffset(420, 80)
	banner.BackgroundTransparency = 1
	banner.Visible = false
	banner.Parent = fx
	bannerText = label(banner, { Name = "Text", Size = UDim2.new(1, 0, 0, 44), TextSize = 30, Font = FONT_HEAVY, Text = "", TextStrokeTransparency = 0.3 })
	bannerSub = label(banner, { Name = "Sub", Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 26), TextSize = 18, Font = FONT_BOLD, TextColor3 = COL.gold, Text = "", TextStrokeTransparency = 0.4 })

	-- WASTED / BUSTED
	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.ZIndex = 5
	overlay.Parent = fx
	overlayTitle = label(overlay, { Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.new(1, 0, 0, 90), TextSize = 72, Font = FONT_HEAVY, Text = "", ZIndex = 6, TextStrokeTransparency = 0.2 })
	overlaySub = label(overlay, { Name = "Sub", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53), Size = UDim2.new(1, 0, 0, 30), TextSize = 24, Font = FONT_BOLD, TextColor3 = Color3.fromRGB(230, 230, 230), Text = "", ZIndex = 6 })
	overlayBody = label(overlay, { Name = "Body", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.new(0.9, 0, 0, 24), TextSize = 16, Font = FONT, TextColor3 = Color3.fromRGB(220, 222, 230), Text = "", ZIndex = 6 })

	layout()
	if Layout and Layout.onChanged then
		pcall(Layout.onChanged, layout)
	end
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(layout)
		end)
	end
end

return H
