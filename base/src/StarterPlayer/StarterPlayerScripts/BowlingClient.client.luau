-- BowlingClient — UI and camera for 광안 락볼링클럽 (see ServerScriptService/Bowling.server).
--
-- After the server confirms a lane claim ("Claimed", from the lane's ProximityPrompt, which works
-- by tap on phones) the lane panel appears:
--   위치 (release point), 방향 (aim angle), 훅 (hook / spin), 던지기 (tap once to start the power
--   meter, tap again to release), 새 게임, 나가기 (always visible while a lane is open).
-- Keyboard: ←/→ 위치 · Q/E 방향 · Z/C 훅 · Space 던지기 · N 새 게임 · X 나가기.
-- A local aim guide (ghost ball + dots, parented to the camera) shows the predicted line.
-- The camera follows the ball for a few seconds after each throw.
--
-- Two layouts, picked from the input device:
--   * PC: the original 1280x720 layout (◀ ▶ rows, meter + round throw button at the bottom right,
--     key hints), scaled with the window.
--   * phone / tablet (touch): authored for a 740x360 phone and never shrunk (scale 1..1.35 from the
--     usable area below the top bar). Compact scoreboard top-left with 나가기 / 새 게임 beside it,
--     three big slider rows (drag or tap the track; 48 px ◀ ▶ fine steps) bottom-left where the
--     (disabled) thumbstick lives, and a 104 px throw button with the power meter left of the jump
--     button. Portrait: scoreboard and buttons on top, sliders full width above the throw button.
--     The slider panel steps aside while the ball rolls so the lane stays visible.
-- A newly opened lane turns the camera to look down the lane (no swiping round on a phone).
-- While a lane is open the character controls are disabled, the jump is blocked (JumpPower /
-- JumpHeight 0 and the Jumping state off, so Roblox hides the touch jump button) and the lane
-- ProximityPrompts are hidden locally (no accidental lane switch by a stray tap); everything is
-- restored when the lane closes.
-- Also: parts tagged "BowlingCosmic" slowly cycle hue while the camera is in the lane hall (black light).

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local sharedModule = ReplicatedStorage:WaitForChild("BowlingShared", 60)
if not sharedModule then
	warn("[BowlingClient] BowlingShared missing")
	return
end
local Shared = require(sharedModule)
local L = Shared.Limits

-- Optional shared quality module (world group): only isMobile() is used, as a tie-breaker for touch
-- devices that also report a keyboard.
local Quality: any = nil
do
	local m = ReplicatedStorage:FindFirstChild("GwangalliQuality") or ReplicatedStorage:WaitForChild("GwangalliQuality", 3)
	if m and m:IsA("ModuleScript") then
		local ok, q = pcall(require, m)
		if ok and type(q) == "table" then
			Quality = q
		end
	end
end

local requestRemote: RemoteEvent? = nil

local function request(action: string, payload: any?)
	if requestRemote then
		requestRemote:FireServer(action, payload)
	end
end

--------------------------------------------------------------------------------------------------
-- session state
--------------------------------------------------------------------------------------------------
type Session = {
	lane: number,
	laneFrame: CFrame,
	laneModel: Instance?,
	laneLength: number,
	laneWidth: number,
	ballR: number,
	offset: number,
	angle: number,
	spin: number,
	state: string,
	board: any,
	frame: number,
	roll: number,
	pinsLeft: number,
}
local session: Session? = nil
local metering = false
local meterStart = 0
local power = 0
local lastPing = 0
local follow: { ball: BasePart, t0: number, lf: CFrame, len: number, stopAt: number? }? = nil
local phone = false -- current layout (touch)

local function wantTouchLayout(): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	local ok, pref = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if ok and typeof(pref) == "EnumItem" then
		return pref.Name == "Touch"
	end
	if not UserInputService.KeyboardEnabled then
		return true
	end
	if Quality then
		local okMobile, mobile = pcall(Quality.isMobile)
		return okMobile and mobile == true
	end
	return false
end

--------------------------------------------------------------------------------------------------
-- UI (GwangalliUI kit tokens: dark glass, 1 px hairlines, cyan / magenta accents; plain fallbacks
-- when the kit is missing)
--------------------------------------------------------------------------------------------------
local UIK: any = nil
do
	local m = ReplicatedStorage:FindFirstChild("GwangalliUI") or ReplicatedStorage:WaitForChild("GwangalliUI", 3)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			UIK = res
		end
	end
end
local KC = (UIK and UIK.Color) or {}
local KF = (UIK and UIK.Font) or {}
local CYAN = KC.cyan or Color3.fromRGB(61, 214, 245)
local MAGENTA = KC.magenta or Color3.fromRGB(255, 79, 163)
local GOLD = KC.gold or Color3.fromRGB(255, 194, 71)
local ACCENT = MAGENTA
local PANEL = KC.glass or Color3.fromRGB(20, 22, 30)
local CARD = KC.card or Color3.fromRGB(30, 32, 42)
local CARD2 = KC.card2 or Color3.fromRGB(44, 47, 60)
local LINE = KC.line or Color3.new(1, 1, 1)
local TEXT = KC.text or Color3.fromRGB(246, 247, 251)
local SUB = KC.sub or Color3.fromRGB(170, 176, 192)
local FONT_BOLD = KF.bold or Enum.Font.BuilderSansBold
local FONT_HEAVY = KF.heavy or Enum.Font.BuilderSansExtraBold
local FONT_MED = KF.medium or Enum.Font.BuilderSansMedium
local MIN_TEXT = 12

-- Motion policy (docs/ui_kit_requests.md #1): phones default to the "low" graphics tier, but UI
-- tweens are cheap; motion is reduced only for the player's setting, a low graphics slider or low fps.
local TweenService = game:GetService("TweenService")
local motionCache, motionAt = false, -math.huge
local function motionReduced(): boolean
	local now = os.clock()
	if now - motionAt < 1 then
		return motionCache
	end
	motionAt = now
	local r = false
	-- the kit's own policy once it has the fixed K.reduced (it ships with K.spring): one rule for
	-- every screen in the game
	if UIK and type(UIK.spring) == "function" and type(UIK.reduced) == "function" then
		local okK, red = pcall(UIK.reduced)
		if okK then
			motionCache = red == true
			return motionCache
		end
	end
	if UIK and type(UIK.settings) == "table" and UIK.settings.reducedMotion == true then
		r = true
	elseif Quality and type(Quality.isLow) == "function" and Quality.isLow() == true then
		local why = if type(Quality.reason) == "function" then string.lower(tostring(Quality.reason())) else ""
		r = string.find(why, "frame", 1, true) ~= nil or string.find(why, "slider", 1, true) ~= nil or string.find(why, "chosen", 1, true) ~= nil
	end
	motionCache = r
	return r
end
local function kitTween(inst: Instance, t: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween?
	if motionReduced() or t <= 0 then
		for k, v in goals do
			pcall(function()
				(inst :: any)[k] = v
			end)
		end
		return nil
	end
	local ok, x = pcall(function()
		local tt = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goals)
		tt:Play()
		return tt
	end)
	return if ok then x else nil
end
-- two-stage spring (Quint Out past the goal, then Sine back), serial-guarded per instance
local springSerial: { [Instance]: number } = {}
local function spring(inst: Instance, t: number, past: { [string]: any }, goals: { [string]: any })
	local n = (springSerial[inst] or 0) + 1
	springSerial[inst] = n
	local first = kitTween(inst, t * 0.7, past)
	if not first then
		kitTween(inst, 0, goals)
		return
	end
	first.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and springSerial[inst] == n then
			kitTween(inst, t * 0.45, goals, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	end)
end
local function feedback()
	if UIK and type(UIK.click) == "function" then
		pcall(UIK.click)
	end
	if UIK and type(UIK.haptic) == "function" then
		pcall(UIK.haptic, "light")
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "BowlingUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- below the top bar, inside the notch insets
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 20
gui.Enabled = false
-- GwangalliHUD / the phone HUD / Now Playing hide while an enabled ScreenGui carries
-- HideGwangalliHUD = true (the lane scoreboard sits where the clock chip is on phones). It is set
-- only while a lane session is open, not for the short notice toasts.
gui:SetAttribute("HideGwangalliHUD", false)

-- Invisible full-area frame (unscaled, directly under the ScreenGui): its AbsolutePosition /
-- AbsoluteSize give the gui's origin and usable area in the same space as Roblox's jump button.
local probe = Instance.new("Frame")
probe.Name = "AreaProbe"
probe.Size = UDim2.fromScale(1, 1)
probe.BackgroundTransparency = 1
probe.Active = false
probe.Parent = gui

-- Everything visible lives in Root, scaled by uiScale. Root is sized 1/scale of the area, so after
-- scaling it covers the area exactly and its children lay out in "authored" px (area / scale).
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Active = false
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function setScale(k: number)
	uiScale.Scale = k
	root.Size = UDim2.fromScale(1 / k, 1 / k)
end

local function corner(parent: Instance, r: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function gradient(parent: Instance, a: Color3, b: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation or 20
	g.Parent = parent
	return g
end

local function textLimit(parent: Instance, maxSize: number): UITextSizeConstraint
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = MIN_TEXT
	c.MaxTextSize = maxSize
	c.Parent = parent
	return c
end

local function makeLabel(parent: Instance, name: string, text: string, size: UDim2, pos: UDim2, color: Color3?, font: Enum.Font?, maxText: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Text = text
	t.TextScaled = true
	t.Font = font or FONT_BOLD
	t.TextColor3 = color or TEXT
	t.Parent = parent
	textLimit(t, maxText or 40)
	return t
end

-- kit-style button: rounded card with a hairline (or a gradient fill), press scale + click / haptic
local function makeButton(parent: Instance, name: string, text: string, size: UDim2, pos: UDim2, color: Color3?, maxText: number?, grad: { Color3 }?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = pos
	b.Text = text
	b.TextScaled = true
	b.Font = FONT_HEAVY
	b.TextColor3 = TEXT
	b.BackgroundColor3 = color or CARD2
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 12)
	if grad then
		-- the fill is the first colour; the gradient only darkens towards the second (so the button
		-- keeps its colour wherever gradients are not drawn)
		b.BackgroundColor3 = grad[1]
		local a, z = grad[1], grad[2]
		local function ratio(x: number, y: number): number
			return if x <= 0 then 1 else math.clamp(y / x, 0, 1)
		end
		gradient(b, Color3.new(1, 1, 1), Color3.new(ratio(a.R, z.R), ratio(a.G, z.G), ratio(a.B, z.B)), 20)
	else
		-- neutral: a raised card lit from the top (card2 -> card) with a hairline
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		gradient(b, color or CARD2, (color or CARD2):Lerp(Color3.new(0, 0, 0), 0.22), 90)
		stroke(b, LINE, 1, 0.86)
	end
	b.AutoButtonColor = false
	textLimit(b, maxText or 28)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.14, 0)
	pad.PaddingBottom = UDim.new(0.14, 0)
	pad.PaddingLeft = UDim.new(0.1, 0)
	pad.PaddingRight = UDim.new(0.1, 0)
	pad.Parent = b
	local sc = Instance.new("UIScale")
	sc.Parent = b
	sc.Name = "Press"
	b.MouseButton1Down:Connect(function()
		kitTween(sc, 0.08, { Scale = 0.94 }, Enum.EasingStyle.Quad)
	end)
	local function up()
		spring(sc, 0.3, { Scale = 1.03 }, { Scale = 1 })
	end
	b.MouseButton1Up:Connect(up)
	b.MouseLeave:Connect(up)
	b.Activated:Connect(feedback)
	return b
end

-- top: lane / frame / scoreboard (glass card)
local top = Instance.new("Frame")
top.Name = "Top"
top.BackgroundColor3 = PANEL
top.BackgroundTransparency = 0.08
top.BorderSizePixel = 0
top.Parent = root
local topCorner = corner(top, 16)
stroke(top, LINE, 1, 0.86)
local titleLabel = makeLabel(top, "Title", "", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 4), TEXT, FONT_BOLD, 16)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
local frameCells: { { marks: TextLabel, score: TextLabel, box: Frame, stroke: UIStroke } } = {}
for f = 1, 11 do
	local box = Instance.new("Frame")
	box.Name = "Cell" .. f
	box.BackgroundColor3 = CARD
	box.BackgroundTransparency = 0
	box.BorderSizePixel = 0
	box.Parent = top
	corner(box, 7)
	local st = stroke(box, CYAN, 1, 1)
	local marks = makeLabel(box, "Marks", "", UDim2.new(1, -4, 0.45, 0), UDim2.fromOffset(2, 2), TEXT, FONT_HEAVY, 20)
	local score = makeLabel(box, "Score", f == 11 and "0" or "", UDim2.new(1, -4, 0.45, 0), UDim2.new(0, 2, 0.52, 0), f == 11 and CYAN or Color3.fromRGB(255, 232, 170), FONT_BOLD, 20)
	frameCells[f] = { marks = marks, score = score, box = box, stroke = st }
end
frameCells[11].box.BackgroundColor3 = Color3.fromRGB(20, 44, 58)

-- new game / leave (나가기 is always visible while a lane is open)
local DANGER = KC.danger or Color3.fromRGB(255, 90, 95)
local leaveBtn = makeButton(root, "Leave", "나가기", UDim2.fromOffset(110, 48), UDim2.new(1, -122, 0, 12), nil, 16)
leaveBtn.TextColor3 = DANGER:Lerp(Color3.new(1, 1, 1), 0.18)
local newBtn = makeButton(root, "NewGame", "새 게임", UDim2.fromOffset(110, 48), UDim2.new(1, -122, 0, 66), nil, 16)
newBtn.TextColor3 = CYAN
newBtn.Visible = false

-- centre: mark flash + toast pill
local flash = makeLabel(root, "Flash", "", UDim2.fromOffset(520, 110), UDim2.new(0.5, -260, 0.22, 0), Color3.new(1, 1, 1), FONT_HEAVY, 96)
flash.TextStrokeTransparency = 0.25
flash.TextStrokeColor3 = Color3.fromRGB(60, 0, 50)
flash.Visible = false
local flashScale = Instance.new("UIScale")
flashScale.Parent = flash
local toast = Instance.new("Frame")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Size = UDim2.fromOffset(460, 34)
toast.Position = UDim2.new(0.5, 0, 0.36, 0)
toast.BackgroundColor3 = PANEL
toast.BackgroundTransparency = 0.06
toast.BorderSizePixel = 0
toast.Visible = false
toast.Parent = root
corner(toast, 17)
stroke(toast, CYAN, 1, 0.55)
local toastText = makeLabel(toast, "Text", "", UDim2.new(1, -24, 1, -10), UDim2.fromOffset(12, 5), TEXT, FONT_BOLD, 16)
local toastScale = Instance.new("UIScale")
toastScale.Parent = toast
local toastMaxW = 460

-- controls panel: one row per setting
local ctrl = Instance.new("Frame")
ctrl.Name = "Controls"
ctrl.BackgroundColor3 = PANEL
ctrl.BackgroundTransparency = 0.08
ctrl.BorderSizePixel = 0
ctrl.Active = true -- taps between the buttons do not turn the camera
ctrl.Parent = root
corner(ctrl, 16)
stroke(ctrl, LINE, 1, 0.86)

type Row = {
	key: string,
	min: number,
	max: number,
	step: number,
	title: TextLabel,
	value: TextLabel,
	left: TextButton,
	right: TextButton,
	track: TextButton, -- phone slider (tap / drag); hidden on PC
	rail: Frame,
	knob: Frame,
	fill: Frame,
}
-- drawn chevron (two rounded 2.5 px bars) so the fine-step buttons match the HUD's drawn icons
local function drawChevron(btn: TextButton, dir: number)
	btn.Text = ""
	local holder = Instance.new("Frame")
	holder.Name = "Chevron"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(18, 18)
	holder.Parent = btn
	for i, sgn in { -1, 1 } do
		local bar = Instance.new("Frame")
		bar.Name = "Arm" .. i
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Size = UDim2.fromOffset(10, 2.5)
		bar.Position = UDim2.new(0.5, dir * (2.5 - 3.3), 0.5, sgn * 3.3)
		bar.Rotation = -45 * sgn * dir
		bar.BackgroundColor3 = TEXT
		bar.BorderSizePixel = 0
		bar.Parent = holder
		corner(bar, 2)
	end
end
local ROW_DEFS = {
	{ key = "offset", title = "위치", left = "<", right = ">", max = L.MaxOffset, step = Shared.OffsetStep },
	{ key = "angle", title = "방향", left = "↺", right = "↻", max = L.MaxAngle, step = Shared.AngleStep },
	{ key = "spin", title = "훅", left = "<", right = ">", max = L.MaxSpin, step = Shared.SpinStep },
}
local KNOB = 26 -- slider knob diameter (authored px)
local rows: { Row } = {}
local rowByKey: { [string]: Row } = {}
for _, d in ROW_DEFS do
	local title = makeLabel(ctrl, d.key .. "Title", d.title, UDim2.fromOffset(70, 40), UDim2.fromOffset(0, 0), CYAN, nil, 26)
	local value = makeLabel(ctrl, d.key .. "Value", "", UDim2.fromOffset(150, 40), UDim2.fromOffset(0, 0), TEXT, FONT_HEAVY, 26)
	local lb = makeButton(ctrl, d.key .. "Left", d.left, UDim2.fromOffset(72, 54), UDim2.fromOffset(0, 0), nil, 22)
	local rb = makeButton(ctrl, d.key .. "Right", d.right, UDim2.fromOffset(72, 54), UDim2.fromOffset(0, 0), nil, 22)
	for _, bb in { lb, rb } do
		local cc = bb:FindFirstChildOfClass("UICorner")
		if cc then
			cc.CornerRadius = UDim.new(0.5, 0)
		end
	end
	if d.left == "<" then
		drawChevron(lb, -1)
		drawChevron(rb, 1)
	end
	title.TextScaled = false
	title.TextSize = 12
	title.Font = FONT_BOLD
	title.TextColor3 = SUB
	title.TextXAlignment = Enum.TextXAlignment.Left
	value.TextXAlignment = Enum.TextXAlignment.Left
	do
		local vc = value:FindFirstChildOfClass("UITextSizeConstraint")
		if vc then
			vc.MaxTextSize = 18
		end
	end
	local track = Instance.new("TextButton")
	track.Name = d.key .. "Slider"
	track.Text = ""
	track.AutoButtonColor = false
	track.BackgroundTransparency = 1
	track.Visible = false
	track.Parent = ctrl
	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.BackgroundTransparency = 1
	rail.Position = UDim2.fromOffset(KNOB / 2, 0)
	rail.Size = UDim2.new(1, -KNOB, 1, 0)
	rail.Parent = track
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.fromScale(0, 0.5)
	bar.Size = UDim2.new(1, 0, 0, 6)
	bar.BackgroundColor3 = CARD2
	bar.BorderSizePixel = 0
	bar.Parent = rail
	corner(bar, 3)
	-- accent fill from the centre (0) to the knob
	local fillBar = Instance.new("Frame")
	fillBar.Name = "Fill"
	fillBar.AnchorPoint = Vector2.new(0, 0.5)
	fillBar.Position = UDim2.fromScale(0.5, 0.5)
	fillBar.Size = UDim2.new(0, 0, 0, 6)
	fillBar.BackgroundColor3 = CYAN
	fillBar.BorderSizePixel = 0
	fillBar.Parent = rail
	corner(fillBar, 3)
	local tick = Instance.new("Frame")
	tick.Name = "Centre"
	tick.AnchorPoint = Vector2.new(0.5, 0.5)
	tick.Position = UDim2.fromScale(0.5, 0.5)
	tick.Size = UDim2.fromOffset(2, 14)
	tick.BackgroundColor3 = SUB
	tick.BackgroundTransparency = 0.5
	tick.BorderSizePixel = 0
	tick.Parent = rail
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB, KNOB)
	knob.BackgroundColor3 = TEXT
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = rail
	local kc = corner(knob, KNOB / 2)
	kc.CornerRadius = UDim.new(0.5, 0)
	stroke(knob, CYAN, 3, 0)
	local row: Row = {
		key = d.key,
		min = -d.max,
		max = d.max,
		step = d.step,
		title = title,
		value = value,
		left = lb,
		right = rb,
		track = track,
		rail = rail,
		knob = knob,
		fill = fillBar,
	}
	table.insert(rows, row)
	rowByKey[d.key] = row
end

-- power meter + throw button
local meter = Instance.new("Frame")
meter.Name = "PowerMeter"
meter.BackgroundColor3 = PANEL
meter.BackgroundTransparency = 0.08
meter.BorderSizePixel = 0
meter.Parent = root
corner(meter, 999)
stroke(meter, LINE, 1, 0.8)
local sweet = Instance.new("Frame")
sweet.Name = "SweetSpot"
sweet.BackgroundColor3 = GOLD
sweet.BackgroundTransparency = 0.84
sweet.BorderSizePixel = 0
sweet.Position = UDim2.fromScale(0, 1 - 0.82)
sweet.Size = UDim2.fromScale(1, 0.14)
sweet.ZIndex = 3
sweet.Parent = meter
for _, edge in { 0, 1 } do
	local e = Instance.new("Frame")
	e.Name = if edge == 0 then "EdgeTop" else "EdgeBottom"
	e.AnchorPoint = Vector2.new(0.5, edge)
	e.Position = UDim2.fromScale(0.5, edge)
	e.Size = UDim2.new(1, -6, 0, 1)
	e.BackgroundColor3 = GOLD
	e.BackgroundTransparency = 0.15
	e.BorderSizePixel = 0
	e.ZIndex = 3
	e.Parent = sweet
end
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.AnchorPoint = Vector2.new(0, 1)
fill.Position = UDim2.fromScale(0, 1)
fill.Size = UDim2.fromScale(1, 0)
fill.BackgroundColor3 = Color3.new(1, 1, 1)
fill.BorderSizePixel = 0
fill.Parent = meter
corner(fill, 999)
-- the fill shows the colour of its own height: green at the bottom, gold at the sweet spot, magenta
-- at the top (a vertical gradient on the fill, re-scaled so it spans the whole meter)
local fillGrad = Instance.new("UIGradient")
fillGrad.Rotation = -90
fillGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 230, 140)),
	ColorSequenceKeypoint.new(0.7, GOLD),
	ColorSequenceKeypoint.new(1, MAGENTA),
})
fillGrad.Parent = fill
local fillCap = Instance.new("Frame")
fillCap.Name = "Sheen"
fillCap.AnchorPoint = Vector2.new(0.5, 0)
fillCap.Position = UDim2.new(0.5, 0, 0, 2)
fillCap.Size = UDim2.new(1, -6, 0, 3)
fillCap.BackgroundColor3 = Color3.new(1, 1, 1)
fillCap.BackgroundTransparency = 0.35
fillCap.BorderSizePixel = 0
fillCap.Visible = false
fillCap.Parent = fill
corner(fillCap, 2)
local meterCaption = makeLabel(meter, "Caption", "파워", UDim2.new(1, 16, 0, 22), UDim2.new(0, -8, 1, 4), SUB, FONT_BOLD, 16)

-- round throw button: magenta gradient (disabled: flat card) with a white hairline ring
local THROW_GRAD = { Color3.fromRGB(255, 96, 176), Color3.fromRGB(200, 40, 150) }
local throwBtn = makeButton(root, "Throw", "던지기", UDim2.fromOffset(150, 150), UDim2.new(1, -170, 1, -176), nil, 36, THROW_GRAD)
local throwCorner = throwBtn:FindFirstChildOfClass("UICorner")
if throwCorner then
	throwCorner.CornerRadius = UDim.new(0.5, 0)
end
local throwGrad = throwBtn:FindFirstChildOfClass("UIGradient")
local throwRing = stroke(throwBtn, Color3.new(1, 1, 1), 2, 0.55)

local hint = makeLabel(root, "Hint", "←/→ 위치 · Q/E 방향 · Z/C 훅 · Space 던지기 · N 새 게임 · X 나가기", UDim2.fromOffset(620, 20), UDim2.new(0.5, -310, 1, -236), SUB, FONT_MED, 18)
hint.Visible = false
do
	-- PC-only key hint: may shrink below the phone floor in small windows rather than overflow
	local c = hint:FindFirstChildOfClass("UITextSizeConstraint")
	if c then
		c.MinTextSize = 8
	end
end

if UIK and type(UIK.shadow) == "function" then
	for _, t in { top, ctrl, meter, leaveBtn, newBtn, throwBtn } do
		t.ZIndex = 2 -- above its shadow holder (ZIndex 1, a later sibling)
	end
	for _, t in { top, ctrl, meter, leaveBtn, newBtn } do
		pcall(UIK.shadow, t, 16, 8, "mid")
	end
end

-- visibility helper (only Root's children: the probe and Root itself always stay visible; shadow
-- holders follow their targets' Visible)
local function showOnly(keep: { [Instance]: boolean })
	for _, c in root:GetChildren() do
		if c:IsA("GuiObject") and string.sub(c.Name, -7) ~= "_Shadow" then
			c.Visible = keep[c] == true
		end
	end
end

-- Phone: the slider panel covers the lower-left of the screen; while the ball rolls (camera follow)
-- and the pins settle it steps aside so the lane and pins stay visible. PC keeps it.
local function updateControlsVisible()
	local s = session
	if not s then
		return
	end
	local busy = s.state == "Rolling" or s.state == "Settling"
	ctrl.Visible = not (phone and busy)
end

--------------------------------------------------------------------------------------------------
-- layout
--------------------------------------------------------------------------------------------------
local function guiArea(): Vector2
	local size = probe.AbsoluteSize
	if size.X >= 50 and size.Y >= 50 then
		return size
	end
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local inset = Vector2.new(0, 58)
	pcall(function()
		inset = GuiService:GetGuiInset()
	end)
	return Vector2.new(vp.X, math.max(vp.Y - inset.Y, 1))
end

-- Roblox's jump button in this gui's local px (x, y, w, h): the live TouchGui button when it exists
-- (it is hidden during a session, but keeps its geometry), else the PlayerModule TouchJump geometry
-- (70 px at (1,-95,1,-90) when the short side is <= 500 px, else 120 px at (1,-170,1,-210)).
local function jumpRect(area: Vector2): (number, number, number, number)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local tg = pg and pg:FindFirstChild("TouchGui")
	local frame = tg and tg:FindFirstChild("TouchControlFrame")
	local jb = frame and frame:FindFirstChild("JumpButton")
	if jb and jb:IsA("GuiObject") then
		local bs = jb.AbsoluteSize
		local bp = jb.AbsolutePosition - probe.AbsolutePosition
		if bs.X >= 30 and bs.Y >= 30 and bp.X > area.X * 0.5 and bp.Y > area.Y * 0.3 and bp.X + bs.X <= area.X + 60 and bp.Y + bs.Y <= area.Y + 60 then
			return bp.X, bp.Y, bs.X, bs.Y
		end
	end
	local small = math.min(area.X, area.Y) <= 500
	local size = if small then 70 else 120
	local x = area.X - (size * 1.5 - 10)
	local y = if small then area.Y - size - 20 else area.Y - size * 1.75
	return x, y, size, size
end

-- Scoreboard cells: 9 frames, a wider 10th, then the total.
local function layoutBoard(width: number, titleH: number, cellY: number, cellH: number, gap: number, compact: boolean)
	titleLabel.Position = UDim2.fromOffset(if compact then 8 else 10, if compact then 3 else 4)
	titleLabel.Size = UDim2.new(1, if compact then -16 else -20, 0, titleH)
	if compact then
		local inner = width - 16
		local unit = (inner - 10 * gap - 4) / 11.7
		local x = 8
		for f = 1, 11 do
			local w = if f == 10 then unit * 1.3 elseif f == 11 then unit * 1.4 else unit
			if f == 11 then
				x += 4
			end
			local cell = frameCells[f]
			cell.box.Position = UDim2.fromOffset(x, cellY)
			cell.box.Size = UDim2.fromOffset(w, cellH)
			x += w + gap
		end
	else
		for f = 1, 11 do
			local w = (f == 10 or f == 11) and 58 or 46
			local x = 10 + (f - 1) * 48 + ((f == 11) and 12 or 0)
			local cell = frameCells[f]
			cell.box.Position = UDim2.fromOffset(x, cellY)
			cell.box.Size = UDim2.fromOffset(w - 2, cellH)
		end
	end
	for f = 1, 11 do
		local cell = frameCells[f]
		cell.marks.Position = UDim2.fromOffset(2, 1)
		cell.marks.Size = UDim2.new(1, -4, 0.47, 0)
		cell.score.Position = UDim2.new(0, 2, 0.52, 0)
		cell.score.Size = UDim2.new(1, -4, 0.46, 0)
	end
end

local function layoutRowsPC()
	for i, r in rows do
		local y = 10 + (i - 1) * 62
		r.title.Position = UDim2.fromOffset(14, y + 8)
		r.title.Size = UDim2.fromOffset(66, 40)
		r.title.TextSize = 14
		r.value.TextXAlignment = Enum.TextXAlignment.Center
		r.left.Position = UDim2.fromOffset(86, y)
		r.left.Size = UDim2.fromOffset(72, 54)
		r.value.Position = UDim2.fromOffset(163, y + 8)
		r.value.Size = UDim2.fromOffset(150, 40)
		r.right.Position = UDim2.fromOffset(318, y)
		r.right.Size = UDim2.fromOffset(72, 54)
		r.track.Visible = false
	end
end

-- Phone rows (authored px): [title / value 52] [◀ 48] [slider track] [▶ 48], 50 px tall, 6 px apart.
local PHONE_ROW_H = 50
local PHONE_ROW_GAP = 6
local PHONE_PANEL_H = 3 * PHONE_ROW_H + 2 * PHONE_ROW_GAP + 16
local PHONE_PANEL_MIN_W = 8 + 52 + 4 + 48 + 4 + 120 + 4 + 48 + 8
local function layoutRowsPhone(panelW: number)
	local trackW = panelW - (8 + 52 + 4 + 48 + 4) - (4 + 48 + 8)
	for i, r in rows do
		local y = 8 + (i - 1) * (PHONE_ROW_H + PHONE_ROW_GAP)
		r.title.Position = UDim2.fromOffset(12, y + 5)
		r.title.Size = UDim2.fromOffset(48, 16)
		r.title.TextSize = 12
		r.value.TextXAlignment = Enum.TextXAlignment.Left
		r.value.Position = UDim2.fromOffset(12, y + 21)
		r.value.Size = UDim2.fromOffset(50, 24)
		r.left.Position = UDim2.fromOffset(64, y + 3)
		r.left.Size = UDim2.fromOffset(44, 44)
		r.track.Position = UDim2.fromOffset(116, y)
		r.track.Size = UDim2.fromOffset(trackW, PHONE_ROW_H)
		r.track.Visible = true
		r.right.Position = UDim2.fromOffset(116 + trackW + 6, y + 3)
		r.right.Size = UDim2.fromOffset(44, 44)
	end
end

local function layoutPC(W: number, H: number)
	-- the layout is authored for ~1280x720 (1280x662 below the top bar); shrink on small windows
	setScale(math.clamp(math.min(W / 1280, H / 662), 0.55, 1.2))
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 10)
	top.Size = UDim2.fromOffset(560, 96)
	topCorner.CornerRadius = UDim.new(0, 14)
	layoutBoard(560, 26, 34, 56, 2, false)
	leaveBtn.AnchorPoint = Vector2.new(0, 0)
	leaveBtn.Position = UDim2.new(1, -122, 0, 12)
	leaveBtn.Size = UDim2.fromOffset(110, 48)
	newBtn.AnchorPoint = Vector2.new(0, 0)
	newBtn.Position = UDim2.new(1, -122, 0, 66)
	newBtn.Size = UDim2.fromOffset(110, 48)
	flash.AnchorPoint = Vector2.new(0, 0)
	flash.Position = UDim2.new(0.5, -260, 0.22, 0)
	flash.Size = UDim2.fromOffset(520, 110)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0.36, 0)
	toast.Size = UDim2.fromOffset(560, 36)
	toastMaxW = 560
	ctrl.AnchorPoint = Vector2.new(0.5, 1)
	ctrl.Position = UDim2.new(0.5, -80, 1, -14)
	ctrl.Size = UDim2.fromOffset(400, 196)
	layoutRowsPC()
	meter.AnchorPoint = Vector2.new(1, 1)
	meter.Position = UDim2.new(1, -196, 1, -30)
	meter.Size = UDim2.fromOffset(34, 200)
	meterCaption.Position = UDim2.new(0, -8, 1, 4)
	meterCaption.Size = UDim2.new(1, 16, 0, 22)
	throwBtn.AnchorPoint = Vector2.new(0, 0)
	throwBtn.Position = UDim2.new(1, -170, 1, -176)
	throwBtn.Size = UDim2.fromOffset(150, 150)
end

local function layoutPhone(W: number, H: number)
	local area = Vector2.new(W, H)
	local portrait = W < H
	local k = if portrait then math.clamp(math.min(W / 360, H / 600), 1, 1.35) else math.clamp(math.min(W / 740, H / 302), 1, 1.35)
	setScale(k)
	local Wa, Ha = W / k, H / k -- authored coordinate space (Root's local size)
	local jx, jy, jw, jh = jumpRect(area)
	jx, jy, jw, jh = jx / k, jy / k, jw / k, jh / k
	local m = 8
	local BTN_W, BTN_H = 96, 48
	local THROW = 104
	local METER_W = 26
	topCorner.CornerRadius = UDim.new(0, 10)

	local boardH = 70
	local panelW, panelX, panelBottom
	local throwRight, throwBottom
	local meterH = 150
	if not portrait then
		-- top row: scoreboard (left) | 새 게임 | 나가기 (top-right corner)
		leaveBtn.AnchorPoint = Vector2.new(1, 0)
		leaveBtn.Position = UDim2.fromOffset(Wa - m, 6)
		newBtn.AnchorPoint = Vector2.new(1, 0)
		newBtn.Position = UDim2.fromOffset(Wa - m - BTN_W - 8, 6)
		local boardW = math.clamp(Wa - 2 * m - 2 * BTN_W - 16, 300, 640)
		top.AnchorPoint = Vector2.new(0, 0)
		top.Position = UDim2.fromOffset(m, 6)
		top.Size = UDim2.fromOffset(boardW, boardH)
		layoutBoard(boardW, 18, 24, boardH - 29, 2, true)
		toast.AnchorPoint = Vector2.new(0.5, 0)
		toast.Position = UDim2.new(0.5, 0, 0, 6 + boardH + 6)
		toast.Size = UDim2.fromOffset(math.min(460, Wa - 2 * m), 32)
		toastMaxW = math.min(460, Wa - 2 * m)
		-- sliders bottom-left (the thumbstick is disabled during a session)
		panelW = math.clamp(Wa * 0.44, PHONE_PANEL_MIN_W, 360)
		panelX = m
		panelBottom = Ha - m
		-- throw button left of the jump button (16 px clear of it), meter left of it
		throwRight = jx - 16
		throwBottom = Ha - m
		if throwRight - THROW - 8 - METER_W < panelX + panelW + 8 then
			-- narrow screen: stack the throw button above the jump button instead
			throwRight = Wa - m
			throwBottom = jy - 12
			meterH = math.clamp(throwBottom - (6 + BTN_H + 12), 60, 150)
		end
		flash.AnchorPoint = Vector2.new(0.5, 0.5)
		flash.Position = UDim2.new(0.5, 0, 0, math.max(6 + boardH + 70, Ha * 0.46))
		flash.Size = UDim2.fromOffset(math.min(340, Wa - 2 * m), 64)
	else
		-- portrait: scoreboard across the top, buttons under it, sliders above the throw button
		top.AnchorPoint = Vector2.new(0, 0)
		top.Position = UDim2.fromOffset(m, 6)
		local boardW = math.min(Wa - 2 * m, 640)
		top.Size = UDim2.fromOffset(boardW, boardH)
		layoutBoard(boardW, 18, 24, boardH - 29, 2, true)
		local rowY = 6 + boardH + 6
		leaveBtn.AnchorPoint = Vector2.new(1, 0)
		leaveBtn.Position = UDim2.fromOffset(Wa - m, rowY)
		newBtn.AnchorPoint = Vector2.new(1, 0)
		newBtn.Position = UDim2.fromOffset(Wa - m - BTN_W - 8, rowY)
		toast.AnchorPoint = Vector2.new(0.5, 0)
		toast.Position = UDim2.new(0.5, 0, 0, rowY + BTN_H + 6)
		toast.Size = UDim2.fromOffset(Wa - 2 * m, 32)
		toastMaxW = Wa - 2 * m
		throwRight = jx - 16
		throwBottom = Ha - m
		meterH = THROW
		panelW = Wa - 2 * m
		panelX = m
		panelBottom = math.min(jy, throwBottom - THROW - 24) - 12 -- 24: the meter caption
		flash.AnchorPoint = Vector2.new(0.5, 0.5)
		flash.Position = UDim2.new(0.5, 0, 0, (rowY + BTN_H + 40 + panelBottom - PHONE_PANEL_H) / 2)
		flash.Size = UDim2.fromOffset(Wa - 2 * m, 64)
	end
	leaveBtn.Size = UDim2.fromOffset(BTN_W, BTN_H)
	newBtn.Size = UDim2.fromOffset(BTN_W, BTN_H)
	ctrl.AnchorPoint = Vector2.new(0, 1)
	ctrl.Position = UDim2.fromOffset(panelX, panelBottom)
	ctrl.Size = UDim2.fromOffset(panelW, PHONE_PANEL_H)
	layoutRowsPhone(panelW)
	throwBtn.AnchorPoint = Vector2.new(1, 1)
	throwBtn.Position = UDim2.fromOffset(throwRight, throwBottom)
	throwBtn.Size = UDim2.fromOffset(THROW, THROW)
	meter.AnchorPoint = Vector2.new(1, 1)
	meter.Position = UDim2.fromOffset(throwRight - THROW - 8, throwBottom)
	meter.Size = UDim2.fromOffset(METER_W, meterH)
	-- caption above the meter (below it would leave the screen)
	meterCaption.Position = UDim2.new(0, -10, 0, -22)
	meterCaption.Size = UDim2.new(1, 20, 0, 20)
end

local function applyLayout()
	phone = wantTouchLayout()
	local area = guiArea()
	if area.X < 50 or area.Y < 50 then
		return
	end
	if phone then
		layoutPhone(area.X, area.Y)
	else
		layoutPC(area.X, area.Y)
	end
	if session then
		-- focus mode: the shared toast stack would sit on the scoreboard / sliders (no free band on a
		-- landscape phone), so it hides while a lane is open; lane notices use the pill below the board
		gui:SetAttribute("ToastsHidden", true)
		hint.Visible = not phone and UserInputService.KeyboardEnabled
		hint.Position = UDim2.new(0.5, -310, 1, -236)
		updateControlsVisible()
	end
end
applyLayout()

local function parentGui()
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 30)
	if pg then
		gui.Parent = pg
	end
end
task.spawn(parentGui)

local function textWidth(str: string, size: number): number
	local w = 0
	for _, cp in utf8.codes(str) do
		if cp >= 0x1F000 or (cp >= 0x2600 and cp < 0x2800) then
			w += 1.25
		elseif cp >= 0x1100 then
			w += 0.95
		elseif cp == 32 then
			w += 0.3
		else
			w += 0.58
		end
	end
	return math.ceil(w * size)
end

local setThrowBreathing: (on: boolean) -> ()
local countTotal: (n: number) -> ()
local toastId = 0
local function showToast(text: string, seconds: number?)
	toastId += 1
	local id = toastId
	toastText.Text = text
	-- pill hugs the text (up to the layout's width)
	local h = toast.Size.Y.Offset
	toast.Size = UDim2.fromOffset(math.clamp(textWidth(text, 15) + 40, 160, toastMaxW), h)
	toast.Visible = true
	local sc = toast:FindFirstChildOfClass("UIScale")
	if sc then
		sc.Scale = 0.86
		spring(sc, 0.36, { Scale = 1.03 }, { Scale = 1 })
	end
	task.delay(seconds or 3, function()
		if toastId == id then
			toast.Visible = false
		end
	end)
end

local flashId = 0
local FLASH = {
	STRIKE = { "STRIKE!", Color3.fromRGB(255, 80, 200) },
	SPARE = { "SPARE!", Color3.fromRGB(80, 200, 255) },
	GUTTER = { "GUTTER", Color3.fromRGB(200, 200, 210) },
}
local function showFlash(mark: string, knocked: number)
	local f = FLASH[mark]
	flashId += 1
	local id = flashId
	if f then
		flash.Text = f[1]
		flash.TextColor3 = f[2]
	else
		flash.Text = knocked == 1 and "1 PIN" or (tostring(knocked) .. " PINS")
		flash.TextColor3 = Color3.new(1, 1, 1)
	end
	flash.Visible = true
	flash.TextTransparency = 0
	flash.TextStrokeTransparency = 0.25
	flashScale.Scale = 0.5
	spring(flashScale, 0.42, { Scale = if mark == "STRIKE" then 1.18 else 1.1 }, { Scale = 1 })
	task.delay(1.35, function()
		if flashId == id then
			kitTween(flash, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad)
			kitTween(flashScale, 0.4, { Scale = 1.08 }, Enum.EasingStyle.Quad)
		end
	end)
	task.delay(1.8, function()
		if flashId == id then
			flash.Visible = false
		end
	end)
end

--------------------------------------------------------------------------------------------------
-- aim guide (client-only parts under the camera)
--------------------------------------------------------------------------------------------------
local guideFolder: Folder? = nil
local ghost: BasePart? = nil
local dots: { BasePart } = {}

local function ensureGuide()
	local cam = workspace.CurrentCamera
	if not cam then
		return false
	end
	if guideFolder and guideFolder.Parent == cam and ghost then
		return true
	end
	if guideFolder then
		guideFolder:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "BowlingAimGuide"
	local g = Instance.new("Part")
	g.Name = "Ghost"
	g.Shape = Enum.PartType.Ball
	g.Size = Vector3.new(0.72, 0.72, 0.72)
	g.Anchored = true
	g.CanCollide = false
	g.CanQuery = false
	g.CanTouch = false
	g.CastShadow = false
	g.Material = Enum.Material.Neon
	g.Color = CYAN
	g.Transparency = 0.45
	g.Parent = f
	dots = {}
	for i = 1, 16 do
		local d = Instance.new("Part")
		d.Name = "Dot"
		d.Shape = Enum.PartType.Cylinder
		d.Size = Vector3.new(0.04, 0.22, 0.22)
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
		d.Material = Enum.Material.Neon
		d.Color = i > 11 and Color3.fromRGB(255, 90, 200) or CYAN
		d.Transparency = 0.25
		d.Parent = f
		dots[i] = d
	end
	f.Parent = cam
	guideFolder = f
	ghost = g
	return true
end

local function clearGuide()
	if guideFolder then
		guideFolder:Destroy()
	end
	guideFolder = nil
	ghost = nil
	dots = {}
end

local function updateGuide()
	local s = session
	if not s or s.state ~= "Ready" then
		if guideFolder then
			guideFolder.Parent = nil
		end
		return
	end
	if not ensureGuide() then
		return
	end
	local lf = s.laneFrame
	local g = ghost
	if g then
		g.CFrame = lf * CFrame.new(s.offset, s.ballR + 0.02, 0.9)
	end
	local a = math.rad(s.angle)
	local speed = Shared.speedFor(0.7)
	local hookStart = Shared.HookStart or 36
	local hookAccel = Shared.HookAccel or 3.5
	for i, d in dots do
		local dist = 2 + (i - 1) * (s.laneLength - 4) / (#dots - 1)
		local x = s.offset + math.tan(a) * dist
		if dist > hookStart then
			local t = (dist - hookStart) / speed
			x += 0.5 * s.spin * hookAccel * t * t * math.clamp((dist - hookStart) / 10, 0.3, 1)
		end
		x = math.clamp(x, -(s.laneWidth / 2 + 0.4), s.laneWidth / 2 + 0.4)
		d.CFrame = lf * CFrame.new(x, 0.03, -dist) * CFrame.Angles(0, 0, math.pi / 2)
	end
end

--------------------------------------------------------------------------------------------------
-- display
--------------------------------------------------------------------------------------------------
local function valueOf(s: Session, key: string): number
	if key == "offset" then
		return s.offset
	elseif key == "angle" then
		return s.angle
	end
	return s.spin
end

local function refreshValues()
	local s = session
	if not s then
		return
	end
	rowByKey.offset.value.Text = string.format("%+.1f", s.offset)
	rowByKey.angle.value.Text = string.format("%+.1f°", s.angle)
	local spinText = "없음"
	local pct = math.floor(math.abs(s.spin) * 100 + 0.5)
	if s.spin > 0.001 then
		spinText = if phone then string.format("우 %d%%", pct) else string.format("오른쪽 %d%%", pct)
	elseif s.spin < -0.001 then
		spinText = if phone then string.format("좌 %d%%", pct) else string.format("왼쪽 %d%%", pct)
	end
	rowByKey.spin.value.Text = spinText
	for _, r in rows do
		local frac = (valueOf(s, r.key) - r.min) / math.max(r.max - r.min, 1e-6)
		local f = math.clamp(frac, 0, 1)
		r.knob.Position = UDim2.fromScale(f, 0.5)
		r.fill.Position = UDim2.fromScale(math.min(f, 0.5), 0.5)
		r.fill.Size = UDim2.new(math.abs(f - 0.5), 0, 0, 6)
	end
	updateGuide()
end

local STATE_TEXT = {
	Ready = "던질 준비 완료",
	Resetting = "핀 정리 중...",
	Rolling = "굴러가는 중!",
	Settling = "핀 확인 중...",
	GameOver = "게임 종료",
	Idle = "",
}
local STATE_SHORT = {
	Ready = "던지세요!",
	Resetting = "핀 정리 중",
	Rolling = "굴러가는 중",
	Settling = "핀 확인 중",
	GameOver = "게임 종료",
	Idle = "",
}

-- "your turn" idle motion: the throw button's ring breathes while the lane is Ready (one looping tween)
local breathTween: Tween? = nil
function setThrowBreathing(on: boolean)
	if on and not breathTween and not motionReduced() then
		throwRing.Transparency = 0.2
		local t = TweenService:Create(throwRing, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.75 })
		t:Play()
		breathTween = t
	elseif not on and breathTween then
		breathTween:Cancel()
		breathTween = nil
	end
end

-- total: counts up over 0.5 s with a gold flash when it grows
local shownTotal = 0
local countSerial = 0
function countTotal(n: number)
	local label = frameCells[11].score
	if n == shownTotal then
		label.Text = tostring(n)
		return
	end
	local from = shownTotal
	shownTotal = n
	countSerial += 1
	local mine = countSerial
	if n < from or motionReduced() then
		label.Text = tostring(n)
		return
	end
	label.TextColor3 = GOLD
	task.spawn(function()
		local t0 = os.clock()
		while countSerial == mine do
			local a = math.clamp((os.clock() - t0) / 0.5, 0, 1)
			local e = 1 - (1 - a) ^ 3
			label.Text = tostring(math.floor(from + (n - from) * e + 0.5))
			if a >= 1 then
				break
			end
			task.wait(1 / 30)
		end
		if countSerial == mine then
			label.TextColor3 = CYAN
		end
	end)
end

local function refreshBoard()
	local s = session
	if not s then
		return
	end
	updateControlsVisible()
	local b = s.board
	local over = b and b.over
	if over then
		titleLabel.Text = if phone
			then string.format("%d번 레인 · GAME OVER · %d점", s.lane, b.total or 0)
			else string.format("LANE %02d · GAME OVER · %d점", s.lane, b.total or 0)
	elseif phone then
		titleLabel.Text = string.format("%d번 레인 · %dF %d구 · 핀 %d · %s", s.lane, s.frame, s.roll, s.pinsLeft, STATE_SHORT[s.state] or "")
	else
		titleLabel.Text = string.format("LANE %02d · %d프레임 %d구 · 남은 핀 %d · %s", s.lane, s.frame, s.roll, s.pinsLeft, STATE_TEXT[s.state] or "")
	end
	for f = 1, 10 do
		local cell = frameCells[f]
		local fi = b and b.frames and b.frames[f]
		if fi then
			local marks = fi.marks or {}
			cell.marks.Text = table.concat(marks, " ")
			cell.score.Text = fi.score and tostring(fi.score) or ""
		else
			cell.marks.Text = ""
			cell.score.Text = ""
		end
		local current = not over and f == s.frame
		cell.box.BackgroundColor3 = if current then CARD2 else CARD
		cell.stroke.Transparency = if current then 0.1 else 1
	end
	frameCells[11].marks.Text = "합계"
	countTotal(b and b.total or 0)
	local ready = s.state == "Ready"
	throwBtn.AutoButtonColor = ready
	if throwGrad then
		throwGrad.Enabled = ready
	end
	throwBtn.BackgroundColor3 = if ready then THROW_GRAD[1] else CARD2
	throwBtn.TextColor3 = if ready then Color3.new(1, 1, 1) else SUB
	throwRing.Transparency = if ready then 0.55 else 0.85
	setThrowBreathing(ready and not metering)
	throwBtn.Text = metering and "놓기!" or "던지기"
	newBtn.Visible = s.state == "GameOver" or s.state == "Ready"
	newBtn.Text = s.state == "GameOver" and "새 게임" or "다시 시작"
	updateGuide()
end

--------------------------------------------------------------------------------------------------
-- camera follow
--------------------------------------------------------------------------------------------------
local function stopFollow()
	if not follow then
		return
	end
	follow = nil
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
	end
end

-- Turn the player's (Custom) camera to look down the lane once when a lane opens. The default camera
-- keeps whatever look direction it finds and re-places itself behind the character, so only the
-- orientation is set here; phone players do not have to swipe the view round before aiming.
local function faceLane(lf: CFrame)
	local cam = workspace.CurrentCamera
	if not cam or cam.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local dir = lf.LookVector - Vector3.new(0, 0.3, 0) -- a little downward, so the approach shows
	if dir.Magnitude < 1e-3 then
		return
	end
	local p = cam.CFrame.Position
	cam.CFrame = CFrame.lookAt(p, p + dir.Unit)
end

local function startFollow(ball: BasePart)
	local s = session
	local cam = workspace.CurrentCamera
	if not s or not cam then
		return
	end
	follow = { ball = ball, t0 = os.clock(), lf = s.laneFrame, len = s.laneLength, stopAt = nil }
	cam.CameraType = Enum.CameraType.Scriptable
end

--------------------------------------------------------------------------------------------------
-- character controls, jump and lane prompts while a lane is open
--------------------------------------------------------------------------------------------------
local controlsModule: any = nil
local controlsRetryAt = 0
local function setCharacterControls(enabled: boolean)
	-- a missing PlayerModule (custom control scripts, or not replicated yet) is retried later
	-- instead of being cached as "no controls" for the whole session
	if not controlsModule and os.clock() >= controlsRetryAt then
		controlsRetryAt = os.clock() + 5
		local ok, result = pcall(function()
			local ps = player:FindFirstChild("PlayerScripts")
			local pm = ps and ps:FindFirstChild("PlayerModule")
			if pm and pm:IsA("ModuleScript") then
				return (require(pm) :: any):GetControls()
			end
			return nil
		end)
		if ok and result then
			controlsModule = result
		end
	end
	if controlsModule then
		pcall(function()
			if enabled then
				controlsModule:Enable()
			else
				controlsModule:Disable()
			end
		end)
	end
end

-- ControlModule:Disable() does not reliably hide the touch jump button, and a jump would pull the
-- player off the approach anyway. JumpPower / JumpHeight 0 (both, whichever UseJumpPower picks) and
-- the Jumping state off make Roblox hide TouchJump; the old values come back on close.
type JumpSave = { hum: Humanoid, power: number, height: number, stateOn: boolean }
local jumpSave: JumpSave? = nil
local function restoreJump()
	local saved = jumpSave
	jumpSave = nil
	if not saved then
		return
	end
	local hum = saved.hum
	if not hum.Parent then
		return -- the character is gone (respawn); the new humanoid has its own defaults
	end
	pcall(function()
		-- only undo our own zeroes (another system may have changed the values meanwhile)
		if hum.JumpPower == 0 then
			hum.JumpPower = saved.power
		end
		if hum.JumpHeight == 0 then
			hum.JumpHeight = saved.height
		end
		if saved.stateOn then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end)
end

local function blockJump()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if jumpSave and jumpSave.hum == hum then
		return
	end
	restoreJump()
	local ok = pcall(function()
		local save: JumpSave = {
			hum = hum,
			power = hum.JumpPower,
			height = hum.JumpHeight,
			stateOn = hum:GetStateEnabled(Enum.HumanoidStateType.Jumping),
		}
		jumpSave = save
		hum.JumpPower = 0
		hum.JumpHeight = 0
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)
	if not ok then
		warn("[BowlingClient] could not block the jump for the lane session")
	end
end

-- Lane prompts are hidden locally while a lane is open: on a phone a stray tap on a neighbour
-- lane's prompt would switch lanes. The server never writes Enabled, so the local change sticks.
local hiddenPrompts: { ProximityPrompt } = {}
local function setLanePromptsHidden(hidden: boolean)
	if hidden then
		for _, model in CollectionService:GetTagged("BowlingLane") do
			local anchor = model:FindFirstChild("PromptAnchor")
			local prompt = anchor and anchor:FindFirstChildOfClass("ProximityPrompt")
			if prompt and prompt.Enabled then
				prompt.Enabled = false
				table.insert(hiddenPrompts, prompt)
			end
		end
	else
		for _, prompt in hiddenPrompts do
			if prompt.Parent then
				prompt.Enabled = true
			end
		end
		table.clear(hiddenPrompts)
	end
end

local function ping()
	local now = os.clock()
	if now - lastPing > 8 then
		lastPing = now
		request("Ping")
	end
end

local function setValue(key: string, v: number)
	local s = session
	local r = rowByKey[key]
	if not s or not r or metering then
		return
	end
	-- snap to the step grid (0 stays reachable), then clamp
	v = math.floor(v / r.step + 0.5) * r.step
	v = math.clamp(v, r.min, r.max)
	if math.abs(v) < 1e-4 then
		v = 0
	end
	if key == "offset" then
		s.offset = v
	elseif key == "angle" then
		s.angle = v
	else
		s.spin = v
	end
	refreshValues()
	ping()
end

local function adjust(key: string, dir: number)
	local s = session
	local r = rowByKey[key]
	if not s or not r or metering then
		return
	end
	setValue(key, valueOf(s, key) + dir * r.step)
end

-- press-and-hold repeat for touch and mouse
local function holdRepeat(btn: TextButton, step: () -> ())
	local holding: InputObject? = nil
	btn.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if holding then
			return
		end
		holding = input
		step()
		local conn: RBXScriptConnection? = nil
		conn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
				if holding == input then
					holding = nil
				end
				if conn then
					conn:Disconnect()
				end
			end
		end)
		task.spawn(function()
			task.wait(0.35)
			while holding == input and gui.Enabled do
				step()
				task.wait(0.07)
			end
		end)
	end)
	btn.InputEnded:Connect(function(input: InputObject)
		if holding == input then
			holding = nil
		end
	end)
end

for _, r in rows do
	local key = r.key
	holdRepeat(r.left, function()
		adjust(key, -1)
	end)
	holdRepeat(r.right, function()
		adjust(key, 1)
	end)
end

-- slider tracks (phone layout): tap to jump, drag to slide
local drag: { row: Row, input: InputObject }? = nil
local function slideTo(r: Row, pos: Vector3)
	local absX, absW = r.rail.AbsolutePosition.X, r.rail.AbsoluteSize.X
	if absW < 4 then
		return
	end
	local frac = math.clamp((pos.X - absX) / absW, 0, 1)
	setValue(r.key, r.min + (r.max - r.min) * frac)
end
for _, r in rows do
	r.track.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
			return
		end
		if not session or metering then
			return
		end
		drag = { row = r, input = input }
		slideTo(r, input.Position)
	end)
	r.track.InputEnded:Connect(function(input: InputObject)
		local d = drag
		if d and d.input == input then
			drag = nil
		end
	end)
end
UserInputService.InputChanged:Connect(function(input: InputObject)
	local d = drag
	if not d then
		return
	end
	if input == d.input or (d.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
		slideTo(d.row, input.Position)
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	local d = drag
	if d and (input == d.input or (d.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
		drag = nil
	end
end)

local function pressThrow()
	local s = session
	if not s then
		return
	end
	if s.state ~= "Ready" then
		metering = false
		showToast(STATE_TEXT[s.state] ~= "" and STATE_TEXT[s.state] or "잠시만 기다려 주세요", 1.5)
		return
	end
	if not metering then
		metering = true
		drag = nil
		meterStart = os.clock()
		power = 0
		throwBtn.Text = "놓기!"
		return
	end
	metering = false
	throwBtn.Text = "던지기"
	fill.Size = UDim2.fromScale(1, power)
	request("Throw", { offset = s.offset, angle = s.angle, spin = s.spin, power = power })
	lastPing = os.clock()
end

throwBtn.Activated:Connect(pressThrow)
leaveBtn.Activated:Connect(function()
	request("Leave")
end)
newBtn.Activated:Connect(function()
	request("NewGame")
end)

local held: { [string]: number } = {}
local ACTION = "BowlingControls"
local KEYMAP: { [Enum.KeyCode]: { any } } = {
	[Enum.KeyCode.Left] = { "offset", -1 },
	[Enum.KeyCode.Right] = { "offset", 1 },
	[Enum.KeyCode.Q] = { "angle", -1 },
	[Enum.KeyCode.E] = { "angle", 1 },
	[Enum.KeyCode.Z] = { "spin", -1 },
	[Enum.KeyCode.C] = { "spin", 1 },
}
local heldTimer = 0

local function onAction(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if not session then
		return Enum.ContextActionResult.Pass
	end
	local kc = input.KeyCode
	local map = KEYMAP[kc]
	if map then
		if state == Enum.UserInputState.Begin then
			adjust(map[1], map[2])
			held[map[1]] = map[2]
			heldTimer = -0.3
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			if held[map[1]] == map[2] then
				held[map[1]] = nil
			end
		end
		return Enum.ContextActionResult.Sink
	end
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if kc == Enum.KeyCode.Space then
		pressThrow()
	elseif kc == Enum.KeyCode.X then
		request("Leave")
	elseif kc == Enum.KeyCode.N then
		request("NewGame")
	end
	return Enum.ContextActionResult.Sink
end

local function bindKeys()
	ContextActionService:BindActionAtPriority(ACTION, onAction, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.Z, Enum.KeyCode.C, Enum.KeyCode.Space, Enum.KeyCode.X, Enum.KeyCode.N)
end

local function unbindKeys()
	ContextActionService:UnbindAction(ACTION)
	table.clear(held)
end

--------------------------------------------------------------------------------------------------
-- session open / close
--------------------------------------------------------------------------------------------------
local noticeUntil = 0
local function showNoticeOnly(text: string, seconds: number)
	-- no lane open: the shared kit toast stack when it exists (same place as every other notice)
	if UIK and type(UIK.toast) == "function" then
		local ok = pcall(UIK.toast, { kind = "info", title = "광안 락볼링클럽", body = text, icon = "🎳", duration = seconds })
		if ok then
			return
		end
	end
	gui.Enabled = true
	showOnly({ [toast] = true })
	-- the HUD clock chip stays on screen: the notice sits right below it
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, 62)
	showToast(text, seconds)
	noticeUntil = os.clock() + seconds
	task.delay(seconds + 0.1, function()
		if not session and os.clock() >= noticeUntil then
			gui.Enabled = false
		end
	end)
end

local function closeSession(reason: string?)
	session = nil
	setThrowBreathing(false)
	metering = false
	drag = nil
	gui:SetAttribute("HideGwangalliHUD", false)
	gui:SetAttribute("ToastsHidden", nil)
	gui.Enabled = false
	unbindKeys()
	clearGuide()
	stopFollow()
	setCharacterControls(true)
	restoreJump()
	setLanePromptsHidden(false)
	local text = ({
		idle = "90초 동안 움직임이 없어 레인이 반납되었습니다.",
		far = "레인에서 멀어져 게임이 종료되었습니다.",
		died = "게임이 종료되었습니다.",
		leave = "이용해 주셔서 감사합니다! 또 오세요 :)",
	})[reason or ""]
	if text then
		showNoticeOnly(text, 3)
	end
end

local function openSession(msg: any)
	if typeof(msg.laneFrame) ~= "CFrame" then
		return
	end
	local keep = session ~= nil and session.lane == msg.lane
	local old = session
	local s: Session = {
		lane = tonumber(msg.lane) or 0,
		laneFrame = msg.laneFrame,
		laneModel = msg.laneModel,
		laneLength = tonumber(msg.laneLength) or 60.96,
		laneWidth = tonumber(msg.laneWidth) or 3.5,
		ballR = (tonumber(msg.ballDiameter) or 0.72) / 2,
		offset = keep and old and old.offset or 0,
		angle = keep and old and old.angle or 0,
		spin = keep and old and old.spin or 0,
		state = "Resetting",
		board = Shared.board({}),
		frame = 1,
		roll = 1,
		pinsLeft = 10,
	}
	session = s
	showOnly({ [top] = true, [leaveBtn] = true, [ctrl] = true, [meter] = true, [throwBtn] = true })
	gui:SetAttribute("HideGwangalliHUD", true)
	gui.Enabled = true -- before the layout: a disabled gui may report a stale area
	applyLayout() -- also sets the key hint (PC with a keyboard only)
	bindKeys()
	setCharacterControls(false)
	blockJump()
	setLanePromptsHidden(true)
	if not keep then
		faceLane(s.laneFrame)
	end
	refreshValues()
	refreshBoard()
	if not keep then
		-- panels arrive from their own edges, 40 ms apart (scoreboard from above, controls from the left,
		-- the throw button pops)
		local moves = { { top, 0, -18 }, { leaveBtn, 0, -18 }, { ctrl, -26, 0 }, { meter, 18, 0 } }
		for i, m in moves do
			local inst, dx, dy = m[1], m[2], m[3]
			local rest = inst.Position
			if not motionReduced() then
				inst.Position = rest + UDim2.fromOffset(dx, dy)
				task.delay((i - 1) * 0.04, function()
					spring(inst, 0.42, { Position = rest - UDim2.fromOffset(dx * 0.12, dy * 0.12) }, { Position = rest })
				end)
			end
		end
		local ps = throwBtn:FindFirstChild("Press")
		if ps and ps:IsA("UIScale") and not motionReduced() then
			ps.Scale = 0.6
			task.delay(0.14, function()
				spring(ps, 0.42, { Scale = 1.06 }, { Scale = 1 })
			end)
		end
	end
	showToast(string.format("%d번 레인 · 즐거운 게임 되세요!", s.lane), 2.5)
end

--------------------------------------------------------------------------------------------------
-- messages from the server
--------------------------------------------------------------------------------------------------
local function onMessage(msg: any)
	if type(msg) ~= "table" then
		return
	end
	local kind = msg.type
	if kind == "Notice" then
		if type(msg.text) == "string" then
			if session then
				showToast(msg.text, 3)
			else
				showNoticeOnly(msg.text, 3)
			end
		end
		return
	elseif kind == "Claimed" then
		openSession(msg)
		return
	elseif kind == "Released" then
		if session and (msg.lane == 0 or msg.lane == session.lane) then
			closeSession(msg.reason)
		end
		return
	end
	local s = session
	if not s or msg.lane ~= s.lane then
		return
	end
	if kind == "State" then
		s.state = tostring(msg.state)
		if type(msg.board) == "table" then
			s.board = msg.board
		end
		s.frame = tonumber(msg.frame) or s.frame
		s.roll = tonumber(msg.roll) or s.roll
		s.pinsLeft = tonumber(msg.pinsLeft) or s.pinsLeft
		if s.state ~= "Ready" then
			metering = false
		end
		refreshBoard()
	elseif kind == "Thrown" then
		s.state = "Rolling"
		metering = false
		refreshBoard()
		local ball = msg.ball
		if typeof(ball) == "Instance" and ball:IsA("BasePart") then
			startFollow(ball)
		end
	elseif kind == "Result" then
		if type(msg.board) == "table" then
			s.board = msg.board
		end
		s.frame = tonumber(msg.frame) or s.frame
		s.roll = tonumber(msg.roll) or s.roll
		showFlash(tostring(msg.mark or ""), tonumber(msg.knocked) or 0)
		refreshBoard()
		if follow then
			follow.stopAt = os.clock() + 1.4
		end
	end
end

task.spawn(function()
	-- created at runtime by Bowling.server; bounded waits so a place without the bowling server
	-- (e.g. a partial build) does not print infinite-yield warnings
	local folder = ReplicatedStorage:WaitForChild(Shared.FolderName, 120)
	local req = folder and folder:WaitForChild(Shared.RequestName, 30)
	local upd = folder and folder:WaitForChild(Shared.UpdateName, 30)
	if not (req and upd) then
		warn("[BowlingClient] ReplicatedStorage." .. Shared.FolderName .. " remotes missing; bowling UI disabled")
		return
	end
	if req:IsA("RemoteEvent") and upd:IsA("RemoteEvent") then
		requestRemote = req
		upd.OnClientEvent:Connect(onMessage)
	else
		warn("[BowlingClient] unexpected remote types")
	end
end)

player.CharacterAdded:Connect(function()
	stopFollow()
	jumpSave = nil -- the old humanoid is gone; the server releases the lane on respawn
end)

--------------------------------------------------------------------------------------------------
-- layout triggers
--------------------------------------------------------------------------------------------------
local viewportConn: RBXScriptConnection? = nil
local function bindCamera()
	if viewportConn then
		viewportConn:Disconnect()
		viewportConn = nil
	end
	local cam = workspace.CurrentCamera
	if cam then
		viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
	applyLayout()
end
bindCamera()
probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
pcall(function()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		applyLayout()
		if session then
			refreshValues()
			refreshBoard()
		end
	end)
end)

--------------------------------------------------------------------------------------------------
-- per-frame: power meter, held keys, camera follow
--------------------------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt: number)
	local s = session
	local f = follow
	if not s and not f then
		return
	end
	if s and metering then
		local t = os.clock() - meterStart
		power = (1 - math.cos(t * math.pi * 2 / 1.6)) / 2
		fill.Size = UDim2.fromScale(1, power)
		fillCap.Visible = power > 0.05
		-- keep the gradient anchored to the meter: scale its offset so the fill shows its own band
		fillGrad.Offset = Vector2.new(0, 0)
		fillGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 230, 140)),
			ColorSequenceKeypoint.new(math.clamp(0.7 / math.max(power, 0.05), 0.001, 0.999), if power >= 0.7 then GOLD else Color3.fromRGB(70, 230, 140):Lerp(GOLD, power / 0.7)),
			ColorSequenceKeypoint.new(1, if power >= 0.7 then GOLD:Lerp(MAGENTA, (power - 0.7) / 0.3) else Color3.fromRGB(70, 230, 140):Lerp(GOLD, power / 0.7)),
		})
		if t > 8 then
			metering = false
			throwBtn.Text = "던지기"
		end
	end
	if s and next(held) then
		heldTimer += dt
		if heldTimer > 0.07 then
			heldTimer = 0
			for key, dir in held do
				adjust(key, dir)
			end
		end
	end
	if f then
		local cam = workspace.CurrentCamera
		local ball = f.ball
		local now = os.clock()
		if not cam or not ball.Parent or now - f.t0 > 7 or (f.stopAt and now > f.stopAt) then
			stopFollow()
		else
			local lf = f.lf
			local p = ball.Position
			local rel = lf:PointToObjectSpace(p)
			local d = math.clamp(-rel.Z, 0, f.len - 4)
			local focus = lf * CFrame.new(rel.X * 0.6, 0.4, -d)
			local look = lf.LookVector
			local eye = focus.Position - look * 8 + Vector3.new(0, 3, 0)
			local target = CFrame.lookAt(eye, focus.Position + look * 6)
			cam.CFrame = cam.CFrame:Lerp(target, math.clamp(dt * 5, 0, 1))
		end
	end
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindCamera()
	clearGuide()
	updateGuide()
end)

--------------------------------------------------------------------------------------------------
-- black-light hue cycling (club vibe) for parts tagged BowlingCosmic
--------------------------------------------------------------------------------------------------
-- 3 Hz, only while the camera is inside the lane hall: inside the tubes' bounding box grown by
-- COSMIC_MARGIN studs (the tubes line the lanes and the approach, ~70 x 93 studs), and never
-- farther than COSMIC_RADIUS from its centre. A sphere alone would also cover the pavement in front
-- of the building (~60 studs from the centre); the forecourt / street never pays for the loop.
-- A colour is written only when its hue moved by more than 0.01.
local COSMIC_INTERVAL = 1 / 3
local COSMIC_RADIUS = 90
local COSMIC_MARGIN = 16
local COSMIC_HUE_STEP = 0.01
local cosmic: { [BasePart]: { base: number, last: number } } = {}
local cosmicDirty = true
local cosmicCentre: Vector3? = nil
local cosmicMin, cosmicMax = Vector3.zero, Vector3.zero

local function addCosmic(inst: Instance)
	if inst:IsA("BasePart") and cosmic[inst] == nil then
		local h = inst.Color:ToHSV()
		cosmic[inst] = { base = h, last = -1 }
		cosmicDirty = true
	end
end
for _, inst in CollectionService:GetTagged("BowlingCosmic") do
	addCosmic(inst)
end
CollectionService:GetInstanceAddedSignal("BowlingCosmic"):Connect(addCosmic)
CollectionService:GetInstanceRemovedSignal("BowlingCosmic"):Connect(function(inst)
	if cosmic[inst :: BasePart] then
		cosmic[inst :: BasePart] = nil
		cosmicDirty = true
	end
end)

local function updateCosmicBounds()
	cosmicDirty = false
	local minP, maxP = nil :: Vector3?, nil :: Vector3?
	for part in cosmic do
		if part.Parent then
			local p = part.Position
			minP = if minP then minP:Min(p) else p
			maxP = if maxP then maxP:Max(p) else p
		else
			cosmic[part] = nil
		end
	end
	if minP and maxP then
		cosmicCentre = (minP + maxP) / 2
		local margin = Vector3.one * COSMIC_MARGIN
		cosmicMin, cosmicMax = minP - margin, maxP + margin
	else
		cosmicCentre = nil
	end
end

task.spawn(function()
	while true do
		task.wait(COSMIC_INTERVAL)
		if next(cosmic) ~= nil then
			if cosmicDirty then
				updateCosmicBounds()
			end
			local cam = workspace.CurrentCamera
			local centre = cosmicCentre
			local eye = if cam then cam.CFrame.Position else nil
			if
				eye
				and centre
				and (eye - centre).Magnitude < COSMIC_RADIUS
				and eye.X >= cosmicMin.X
				and eye.X <= cosmicMax.X
				and eye.Y >= cosmicMin.Y
				and eye.Y <= cosmicMax.Y
				and eye.Z >= cosmicMin.Z
				and eye.Z <= cosmicMax.Z
			then
				-- sway each tube's hue around its own colour (purple / cyan / pink stay in family)
				local t = os.clock()
				for part, rec in cosmic do
					if part.Parent then
						local hue = (rec.base + 0.07 * math.sin(t * 0.9 + rec.base * 12)) % 1
						local moved = math.abs(hue - rec.last)
						if math.min(moved, 1 - moved) > COSMIC_HUE_STEP then
							rec.last = hue
							part.Color = Color3.fromHSV(hue, 0.8, 1)
						end
					else
						cosmic[part] = nil
						cosmicDirty = true
					end
				end
			end
		end
	end
end)
