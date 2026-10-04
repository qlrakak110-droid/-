-- GwangalliUI: the shared premium UI kit (docs/UI_DESIGN_SPEC.md). Every phone app, the HUD, the NPC
-- dialog, toasts and the club / bowling widgets build their screens from this kit only.
-- Client helpers: nothing is created at require time and nothing yields. No image asset ids: icons
-- are emoji / text glyphs on gradient tiles, shadows are layered translucent frames.
--
-- Design language: dark glass (deep navy panels, 0.12-0.2 transparency) + Gwangan-bridge night
-- accents (cyan #3DD6F5, magenta #FF4FA3, gold #FFC247), 1 px white hairlines (0.85-0.9
-- transparency), radii 12-24, 8/12/16 spacing grid, type scale 22/18/15/14/12/11 (11 px floor on
-- phones), Quint Out 0.22-0.3 s motion + two-stage springs (shortened when K.reduced()), 0.96 press scale,
-- 20 ms list stagger, count-ups, click sound + haptics + a background blur (mid/high tier).
--
--   local K = require(ReplicatedStorage.GwangalliUI)
--   Tokens    K.Color  K.Grad  K.Font  K.Type  K.Radius  K.Space  K.Motion  K.Kinds  K.MIN_TAP
--   Settings  K.settings = {sound, haptics, notifications, reducedMotion}  (the phone's 설정 app)
--   Builders  K.make K.frame K.text K.corner K.stroke K.pad K.list K.gradient K.shadow K.glass
--             K.setText K.mono(label, weight?) K.tween(inst, t, goals, style?, dir?) K.tier() K.reduced()
--   Feedback  K.sound(kind) K.haptic(kind) K.feedback(kind)   kind: tap|toggle|open|close|notify|
--             success|error|money ;  K.blur(on)  (Lighting blur, mid / high tier only)
--   Motion    K.pressable(button) K.pop(gui) K.stagger(rows, veilColor?) K.pulse(stroke|gui, on)
--   Layout    K.Layout (GwangalliLayout slot contract), K.deviceClass(W, H, touch), K.scaleFor(cls, W, H)
--   Components (all return the instance or an api table; see each function's header):
--     K.Panel K.Card K.Button K.setButtonEnabled K.setButtonLoading K.IconButton K.ListRow
--     K.SectionHeader K.Tabs (underline) K.Segmented (pill) K.Toggle K.Slider K.SearchBar K.Chip
--     K.Badge K.Pill K.ProgressBar K.Ring K.MoneyLabel K.EmptyState K.Skeleton K.Modal K.confirm
--     K.BottomSheet (drag to close) K.DialogBox K.Toaster  (+ K.setToaster / K.toast global route)
--     K.iconTile K.avatar
--   Utils     K.won K.wonShort K.commas K.textSize K.korClock K.clock24 K.meters K.walkTime K.ro
--             K.countdown

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local K = {}
K.VERSION = 2

---------------------------------------------------------------------------------------------------
-- Tokens
---------------------------------------------------------------------------------------------------
local CYAN = Color3.fromRGB(61, 214, 245)
local MAGENTA = Color3.fromRGB(255, 79, 163)
local GOLD = Color3.fromRGB(255, 194, 71)
local VIOLET = Color3.fromRGB(139, 108, 255)
local GREEN = Color3.fromRGB(61, 220, 132)
local ORANGE = Color3.fromRGB(255, 176, 32)
local RED = Color3.fromRGB(255, 90, 95)

K.Color = {
	bg = Color3.fromRGB(10, 12, 20), -- app background (deep navy-black)
	navy = Color3.fromRGB(14, 18, 34),
	glass = Color3.fromRGB(15, 18, 31), -- floating panel fill, used with K.GLASS_T transparency
	glass2 = Color3.fromRGB(23, 27, 44),
	card = Color3.fromRGB(25, 29, 45), -- surface
	card2 = Color3.fromRGB(37, 42, 61), -- raised / pressed / secondary buttons
	card3 = Color3.fromRGB(54, 60, 84), -- tracks, dividers on cards
	line = Color3.fromRGB(255, 255, 255), -- hairline colour (0.85-0.9 transparency)
	text = Color3.fromRGB(245, 247, 251),
	sub = Color3.fromRGB(170, 177, 196),
	faint = Color3.fromRGB(116, 124, 146),
	cyan = CYAN,
	magenta = MAGENTA,
	gold = GOLD,
	violet = VIOLET,
	green = GREEN,
	orange = ORANGE,
	red = RED,
	blue = Color3.fromRGB(84, 140, 255),
	teal = Color3.fromRGB(40, 204, 196),
	pink = MAGENTA,
	accent = CYAN,
	accent2 = MAGENTA,
	success = GREEN,
	warn = ORANGE,
	danger = RED,
	onAccent = Color3.fromRGB(4, 22, 32), -- text on cyan / gold / green fills
	onGold = Color3.fromRGB(44, 28, 0),
	shadow = Color3.fromRGB(0, 0, 0),
}
K.GLASS_T = 0.14

-- Gradient presets (Gwangan bridge LED sweep etc.)
K.Grad = {
	bridge = { CYAN, VIOLET, MAGENTA },
	primary = { Color3.fromRGB(88, 226, 250), Color3.fromRGB(56, 170, 255) },
	gold = { Color3.fromRGB(255, 214, 110), Color3.fromRGB(255, 166, 50) },
	success = { Color3.fromRGB(86, 232, 150), Color3.fromRGB(34, 190, 120) },
	danger = { Color3.fromRGB(255, 112, 112), Color3.fromRGB(232, 64, 96) },
	night = { Color3.fromRGB(30, 36, 78), Color3.fromRGB(12, 14, 28) },
	card = { Color3.fromRGB(36, 42, 70), Color3.fromRGB(20, 23, 38) },
}

K.Font = {
	regular = Enum.Font.Gotham,
	medium = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
	heavy = Enum.Font.GothamBlack,
	gotham = Enum.Font.GothamBold,
	mono = Enum.Font.RobotoMono,
}
-- type scale (px). Phones never go below micro (11).
K.Type = { display = 28, title = 22, title2 = 18, body = 15, bodySm = 14, caption = 12, micro = 11 }
K.Radius = { sm = 12, md = 16, lg = 20, xl = 24, pill = 999 }
K.Space = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }
K.Motion = { press = 0.08, fast = 0.16, base = 0.25, slow = 0.3, stagger = 0.025, spring = 0.42 }
K.MIN_TAP = 44

-- toast / banner kinds -> accent colour + glyph
K.Kinds = {
	info = { color = CYAN, icon = "🔔" },
	money = { color = GREEN, icon = "💰" },
	pay = { color = GREEN, icon = "💵" },
	warn = { color = ORANGE, icon = "⚠️" },
	error = { color = RED, icon = "⛔" },
	job = { color = GOLD, icon = "💼" },
	home = { color = Color3.fromRGB(40, 204, 196), icon = "🏠" },
	message = { color = GOLD, icon = "💬" },
	taxi = { color = GOLD, icon = "🚕" },
	stat = { color = MAGENTA, icon = "✨" },
	club = { color = VIOLET, icon = "🎶" },
	success = { color = GREEN, icon = "✅" },
	travel = { color = CYAN, icon = "🧭" },
}

-- Player-facing feedback settings (the phone's 설정 app writes these)
K.settings = { sound = true, haptics = true, notifications = true, reducedMotion = false }

---------------------------------------------------------------------------------------------------
-- Quality tier (reduced motion on low)
---------------------------------------------------------------------------------------------------
local Quality: any = nil
local qualityTried = false
local function quality(): any
	if qualityTried then
		return Quality
	end
	qualityTried = true
	local m = ReplicatedStorage:FindFirstChild("GwangalliQuality")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			Quality = res
		end
	end
	return Quality
end

local tierCache, tierAt = "high", -1
function K.tier(): string
	if os.clock() - tierAt < 1 then
		return tierCache
	end
	tierAt = os.clock()
	tierCache = K.tierNow()
	return tierCache
end

function K.tierNow(): string
	local q = quality()
	if q and type(q.get) == "function" then
		local ok, t = pcall(q.get)
		if ok and (t == "low" or t == "mid" or t == "high") then
			return t
		end
	end
	return "high"
end

-- Reduced motion: the 설정 toggle, a player who picked "낮음" graphics by hand, or a device that is
-- actually struggling (measured frame rate below 24). The automatic "low" tier is NOT enough on its
-- own: GwangalliQuality puts every phone on "low" for the 3D world, while UI tweens cost next to
-- nothing, so phones keep the full motion design unless they are really slow.
local reducedCache, reducedAt = false, -1
function K.reduced(): boolean
	if K.settings.reducedMotion == true then
		return true
	end
	if os.clock() - reducedAt < 1 then
		return reducedCache
	end
	reducedAt = os.clock()
	local slow = false
	local q = quality()
	if q then
		if type(q.getOverride) == "function" then
			local ok, o = pcall(q.getOverride)
			if ok and o == "low" then
				slow = true
			end
		end
		if not slow and type(q.fps) == "function" then
			local ok, f = pcall(q.fps)
			if ok and type(f) == "number" and f > 0 and f < 24 then
				slow = true
			end
		end
	end
	reducedCache = slow
	return slow
end

-- Layout contract (lazy so the kit also works where the module is missing)
local layoutModule: any = nil
setmetatable(K, {
	__index = function(_, key)
		if key == "Layout" then
			if layoutModule == nil then
				local m = ReplicatedStorage:FindFirstChild("GwangalliLayout")
				if m and m:IsA("ModuleScript") then
					local ok, res = pcall(require, m)
					layoutModule = if ok and type(res) == "table" then res else false
				else
					return nil
				end
			end
			return if layoutModule then layoutModule else nil
		end
		return nil
	end,
})

---------------------------------------------------------------------------------------------------
-- Builders
---------------------------------------------------------------------------------------------------
function K.make(className: string, props: { [string]: any }?, parent: Instance?): any
	local inst = Instance.new(className)
	if props then
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local make = K.make

-- Sets the corner radius (re-uses an existing UICorner, so re-rounding a kit button never stacks two).
function K.corner(inst: Instance, r: any): UICorner
	local radius = if typeof(r) == "UDim" then r else UDim.new(0, r or K.Radius.md)
	local existing = inst:FindFirstChildOfClass("UICorner")
	if existing then
		existing.CornerRadius = radius
		return existing
	end
	return make("UICorner", { CornerRadius = radius }, inst)
end

function K.stroke(inst: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return make("UIStroke", {
		Color = color or K.Color.line,
		Thickness = thickness or 1,
		Transparency = transparency or 0.88,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
end

function K.pad(inst: Instance, l: number, r: number?, t: number?, b: number?): UIPadding
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingRight = UDim.new(0, r or l),
		PaddingTop = UDim.new(0, t or l),
		PaddingBottom = UDim.new(0, b or t or l),
	}, inst)
end

function K.list(inst: Instance, horizontal: boolean?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return make("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, padding or 0),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
	}, inst)
end

function K.gradient(inst: Instance, colors: any, rotation: number?, transparency: NumberSequence?): UIGradient
	local seq = colors
	if type(colors) == "table" then
		local kps = {}
		local n = #colors
		for i, c in colors do
			table.insert(kps, ColorSequenceKeypoint.new(if n <= 1 then 0 else (i - 1) / (n - 1), c))
		end
		if n == 1 then
			table.insert(kps, ColorSequenceKeypoint.new(1, colors[1]))
		end
		seq = ColorSequence.new(kps)
	end
	local g = make("UIGradient", { Color = seq, Rotation = rotation or 90 }, inst)
	if transparency then
		g.Transparency = transparency
	end
	return g
end

function K.frame(parent: Instance?, props: { [string]: any }?): Frame
	local f = make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0 }, nil)
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	f.Parent = parent
	return f
end

function K.text(parent: Instance?, props: { [string]: any }?): TextLabel
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextColor3 = K.Color.text,
		Font = K.Font.medium,
		TextSize = K.Type.bodySm,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, nil)
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	l.Parent = parent
	return l
end

function K.setText(l: any, s: string)
	if l and l.Text ~= s then
		l.Text = s
	end
end

-- True when `g` and every ancestor GuiObject are Visible and its ScreenGui is Enabled.
function K.shownInTree(g: Instance?): boolean
	local node = g
	for _ = 1, 24 do
		if not node then
			return false
		end
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return (node :: any).Enabled ~= false
		end
		node = node.Parent
	end
	return true
end

-- Tabular-looking digits for money / time (RobotoMono family, bold by default).
function K.mono(label: Instance, weight: Enum.FontWeight?)
	pcall(function()
		(label :: any).FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", weight or Enum.FontWeight.Bold)
	end)
end

-- Tween with Quint Out by default. Reduced motion (low tier / setting): 60 % of the duration
-- (decorative loops such as staggers, shimmers and pulses are skipped elsewhere); very short tweens
-- are applied instantly.
function K.tween(inst: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween?
	local t = seconds
	if K.reduced() then
		t *= 0.6
	end
	if t < 0.05 then
		for k, v in goals do
			pcall(function()
				(inst :: any)[k] = v
			end)
		end
		return nil
	end
	local ok, tw = pcall(function()
		local tween = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goals)
		tween:Play()
		return tween
	end)
	if ok then
		return tw
	end
	for k, v in goals do
		pcall(function()
			(inst :: any)[k] = v
		end)
	end
	return nil
end

-- Soft shadow: 3 layered, increasingly transparent rounded frames behind `target` (siblings, so the
-- target may clip its own descendants). strength: "soft" (HUD chips; layers >= 0.95 transparent so
-- they add no screen coverage) | "mid" | "strong" (sheets, the phone). Follows the target.
function K.shadow(target: GuiObject, radius: number?, depth: number?, strength: string?): Frame?
	local parent = target.Parent
	if not parent then
		return nil
	end
	local r = radius or K.Radius.md
	local d = depth or 6
	local base = if strength == "strong" then 0.8 elseif strength == "soft" then 0.95 else 0.88
	local step = if strength == "soft" then 0.015 else 0.045
	local holder = K.frame(parent, {
		Name = target.Name .. "_Shadow",
		AnchorPoint = target.AnchorPoint,
		Position = target.Position,
		Size = target.Size,
		ZIndex = math.max(1, target.ZIndex - 1),
		Visible = target.Visible,
	})
	for i = 1, 3 do
		local g = d * i / 3
		local f = K.frame(holder, {
			Name = "L" .. i,
			Position = UDim2.fromOffset(-g, -g + d * 0.45),
			Size = UDim2.new(1, 2 * g, 1, 2 * g),
			BackgroundTransparency = math.min(0.985, base + (i - 1) * step),
			BackgroundColor3 = K.Color.shadow,
			ZIndex = holder.ZIndex,
		})
		K.corner(f, r + g)
	end
	local function sync()
		holder.AnchorPoint = target.AnchorPoint
		holder.Position = target.Position
		holder.Size = target.Size
		holder.Visible = target.Visible
	end
	local conns = {
		target:GetPropertyChangedSignal("Position"):Connect(sync),
		target:GetPropertyChangedSignal("Size"):Connect(sync),
		target:GetPropertyChangedSignal("AnchorPoint"):Connect(sync),
		target:GetPropertyChangedSignal("Visible"):Connect(sync),
	}
	target.AncestryChanged:Connect(function()
		if not target.Parent then
			for _, c in conns do
				c:Disconnect()
			end
			holder:Destroy()
		elseif holder.Parent ~= target.Parent then
			holder.Parent = target.Parent
		end
	end)
	return holder
end

-- Style an existing frame as dark glass (fill + hairline + top sheen).
function K.glass(f: GuiObject, radius: number?, transparency: number?)
	f.BackgroundColor3 = K.Color.glass
	f.BackgroundTransparency = transparency or K.GLASS_T
	K.corner(f, radius or K.Radius.lg)
	K.stroke(f, nil, 1, 0.86)
	local sheen = K.frame(f, { Name = "Sheen", Size = UDim2.new(1, -24, 0, 1), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 1), BackgroundTransparency = 0.82, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = f.ZIndex })
	K.gradient(sheen, { Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(1, 1) }))
end

-- Dark glass panel.
function K.Panel(parent: Instance?, props: { [string]: any }?): Frame
	local p = K.frame(nil, { Active = true })
	local radius = K.Radius.lg
	local transparency = K.GLASS_T
	if props then
		for k, v in props do
			if k == "Radius" then
				radius = v
			elseif k == "BackgroundTransparency" then
				transparency = v
			else
				(p :: any)[k] = v
			end
		end
	end
	K.glass(p, radius, transparency)
	p.Parent = parent
	return p
end

function K.Card(parent: Instance?, props: { [string]: any }?): Frame
	local c = K.frame(nil, { BackgroundTransparency = 0, BackgroundColor3 = K.Color.card, Size = UDim2.new(1, 0, 0, 64) })
	local radius = K.Radius.md
	if props then
		for k, v in props do
			if k == "Radius" then
				radius = v
			else
				(c :: any)[k] = v
			end
		end
	end
	K.corner(c, radius)
	K.stroke(c, nil, 1, 0.92)
	c.Parent = parent
	return c
end

---------------------------------------------------------------------------------------------------
-- Feedback: sound + haptics + blur
---------------------------------------------------------------------------------------------------
local SOUNDS = {
	tap = { id = "rbxasset://sounds/clickfast.wav", volume = 0.22, speed = 1.15 },
	toggle = { id = "rbxasset://sounds/clickfast.wav", volume = 0.26, speed = 0.9 },
	open = { id = "rbxasset://sounds/swoosh.wav", volume = 0.14, speed = 1.4 },
	close = { id = "rbxasset://sounds/swoosh.wav", volume = 0.1, speed = 1.7 },
	notify = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.38, speed = 1 },
	money = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.34, speed = 1.25 },
	success = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.3, speed = 1.45 },
	error = { id = "rbxasset://sounds/clickfast.wav", volume = 0.3, speed = 0.6 },
}
local soundCache: { [string]: Sound } = {}
local lastSound: { [string]: number } = {}

function K.sound(kind: string?)
	if not K.settings.sound or not RunService:IsClient() then
		return
	end
	local k = kind or "tap"
	local def = SOUNDS[k] or SOUNDS.tap
	local now = os.clock()
	if lastSound[k] and now - lastSound[k] < 0.05 then
		return
	end
	lastSound[k] = now
	pcall(function()
		local s = soundCache[k]
		if not (s and s.Parent) then
			s = Instance.new("Sound")
			s.Name = "GwangalliUI_" .. k
			s.SoundId = def.id
			s.Volume = def.volume
			s.PlaybackSpeed = def.speed
			s.Parent = game:GetService("SoundService")
			soundCache[k] = s
		end
		(s :: Sound):Play()
	end)
end

local hapticCache: { [string]: Instance } = {}
local HAPTIC_TYPE = { tap = "UIClick", toggle = "UIClick", open = "UIHover", close = "UIHover", notify = "UINotification", money = "UINotification", success = "UINotification", error = "UINotification" }

function K.haptic(kind: string?)
	if not K.settings.haptics or not RunService:IsClient() then
		return
	end
	local k = kind or "tap"
	-- touch devices: HapticEffect (UI click / notification); gamepads: a short motor pulse
	if UserInputService.TouchEnabled then
		pcall(function()
			local e = hapticCache[k]
			if not (e and e.Parent) then
				e = Instance.new("HapticEffect")
				e.Name = "GwangalliUIHaptic_" .. k;
				(e :: any).Type = (Enum :: any).HapticEffectType[HAPTIC_TYPE[k] or "UIClick"]
				e.Parent = game:GetService("SoundService")
				hapticCache[k] = e
			end
			(e :: any):Play()
		end)
	end
	if UserInputService.GamepadEnabled then
		pcall(function()
			local HapticService = game:GetService("HapticService")
			local pad = Enum.UserInputType.Gamepad1
			if HapticService:IsVibrationSupported(pad) and HapticService:IsMotorSupported(pad, Enum.VibrationMotor.Small) then
				HapticService:SetMotor(pad, Enum.VibrationMotor.Small, if k == "notify" or k == "error" then 0.6 else 0.3)
				task.delay(if k == "notify" then 0.12 else 0.05, function()
					pcall(HapticService.SetMotor, HapticService, pad, Enum.VibrationMotor.Small, 0)
				end)
			end
		end)
	end
end

function K.feedback(kind: string?)
	K.sound(kind)
	if kind ~= "tap" or UserInputService.TouchEnabled then
		K.haptic(kind)
	end
end

-- Background blur while a modal UI is up (mid / high tier; refcounted by key).
local blurKeys: { [string]: boolean } = {}
local blurEffect: BlurEffect? = nil
function K.blur(on: boolean, key: string?)
	local id = key or "default"
	blurKeys[id] = if on then true else nil
	local want = next(blurKeys) ~= nil and K.tier() ~= "low"
	pcall(function()
		local Lighting = game:GetService("Lighting")
		if not (blurEffect and blurEffect.Parent) then
			if not want then
				return
			end
			local b = Instance.new("BlurEffect")
			b.Name = "GwangalliUIBlur"
			b.Size = 0
			b.Parent = Lighting
			blurEffect = b
		end
		K.tween(blurEffect :: BlurEffect, if want then 0.3 else 0.22, { Size = if want then 10 else 0 })
	end)
end

---------------------------------------------------------------------------------------------------
-- Motion helpers
---------------------------------------------------------------------------------------------------
-- Press feedback for any GuiButton: 0.96 scale + a light veil while held; tap sound on Activated.
function K.pressable(b: GuiButton, opts: { [string]: any }?)
	local o = opts or {}
	local scale = b:FindFirstChildOfClass("UIScale") or make("UIScale", { Scale = 1 }, b)
	local veil: Frame? = nil
	if o.veil ~= false then
		veil = K.frame(b, { Name = "PressVeil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = b.ZIndex + 3 })
		local c = b:FindFirstChildOfClass("UICorner")
		if c then
			K.corner(veil :: Frame, c.CornerRadius)
		end
	end
	local held = false
	-- the button may size itself with this UIScale (e.g. the 폰 button): press relative to that
	-- base instead of forcing 1. The base follows outside writes (not our own press animation);
	-- an explicit "BaseScale" attribute on the UIScale wins.
	local base = scale.Scale
	local oursUntil = 0
	scale:GetPropertyChangedSignal("Scale"):Connect(function()
		if not held and os.clock() > oursUntil then
			base = scale.Scale
		end
	end)
	local function baseScale(): number
		local attr = scale:GetAttribute("BaseScale")
		return if type(attr) == "number" then attr else base
	end
	local function down()
		if b:GetAttribute("Disabled") then
			return
		end
		held = true
		oursUntil = math.huge
		K.cancel(scale)
		K.tween(scale, K.Motion.press, { Scale = baseScale() * (o.scale or 0.96) })
		if veil then
			veil.BackgroundTransparency = 0.9
		end
	end
	local function up()
		if not held then
			return
		end
		held = false
		oursUntil = os.clock() + 0.4
		-- release with a tiny overshoot, like a physical key popping back
		if K.reduced() then
			K.tween(scale, 0.12, { Scale = baseScale() })
		else
			K.spring(scale, { Scale = baseScale() }, { duration = 0.3, amount = 0.25 })
		end
		if veil then
			K.tween(veil, 0.2, { BackgroundTransparency = 1 })
		end
	end
	b.MouseButton1Down:Connect(down)
	b.MouseButton1Up:Connect(up)
	b.MouseLeave:Connect(up)
	b.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			up()
		end
	end)
	if o.sound ~= false then
		b.Activated:Connect(function()
			if not b:GetAttribute("Disabled") then
				K.feedback(o.sound or "tap")
			end
		end)
	end
end

-- Scale pop-in (0.92 -> 1) for cards / modals.
function K.pop(g: GuiObject, from: number?)
	local s = g:FindFirstChildOfClass("UIScale") or make("UIScale", { Scale = 1 }, g)
	s.Scale = from or 0.92
	K.tween(s, K.Motion.base, { Scale = 1 })
end

-- Sequential reveal of list rows (25 ms apart): each row rises from 97 % scale while a veil in the
-- colour behind it fades away (the veil is removed afterwards). veilColor defaults to the first
-- opaque ancestor's colour, so rows inside cards do not flash dark. Skipped on reduced motion.
local function surfaceColor(g: Instance): Color3
	local node = g.Parent
	for _ = 1, 12 do
		if not node or not node:IsA("GuiObject") then
			break
		end
		local go = node :: GuiObject
		if go.BackgroundTransparency < 0.5 and not go:FindFirstChildOfClass("UIGradient") then
			return go.BackgroundColor3
		end
		node = node.Parent
	end
	return K.Color.bg
end

function K.stagger(rows: { GuiObject }, veilColor: Color3?)
	if K.reduced() then
		return
	end
	for i, row in rows do
		if i > 14 then
			break
		end
		local col = veilColor or surfaceColor(row)
		local veil = K.frame(row, { Name = "FadeVeil", Size = UDim2.new(1, 2, 1, 2), Position = UDim2.fromOffset(-1, -1), BackgroundTransparency = 0, BackgroundColor3 = col, ZIndex = row.ZIndex + 6 })
		local c = row:FindFirstChildOfClass("UICorner")
		if c then
			K.corner(veil, c.CornerRadius)
		end
		local delay = (i - 1) * K.Motion.stagger
		local sc = K.scaleOf(row)
		sc.Scale = 0.97
		K.spring(sc, { Scale = 1 }, { duration = 0.4, amount = 0.2, delay = delay })
		K.tweenD(veil, 0.26, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, delay)
		task.delay(delay + 0.28, function()
			veil:Destroy()
		end)
	end
end

-- Gentle attention pulse on a UIStroke (transparency) or a GuiObject (background). Stops when
-- turned off, destroyed or hidden. Static highlight on the low tier.
local pulses: { [Instance]: number } = {}
function K.pulse(target: Instance, on: boolean, a: number?, b: number?)
	local lo, hi = a or 0.05, b or 0.7
	local prop = if target:IsA("UIStroke") then "Transparency" else "BackgroundTransparency"
	if not on then
		pulses[target] = nil
		return
	end
	if pulses[target] then
		return
	end
	local serial = os.clock()
	pulses[target] = serial
	if K.reduced() then
		(target :: any)[prop] = lo
		return
	end
	task.spawn(function()
		local flip = false
		while pulses[target] == serial and target.Parent do
			flip = not flip
			K.tween(target, 0.6, { [prop] = if flip then lo else hi }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.wait(0.65)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Motion system (v3): physical-feeling helpers. Every tween targets Position / Size / Transparency /
-- Rotation / UIScale (or a UIGradient offset); instances are reused; only count-ups step per frame.
-- On the low tier / reduced-motion setting durations shrink and decorative motion is skipped.
---------------------------------------------------------------------------------------------------
local motionSerial: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

local function applyNow(inst: Instance, goals: { [string]: any })
	for k, v in goals do
		pcall(function()
			(inst :: any)[k] = v
		end)
	end
end

-- Tween with an optional start delay (seconds). Returns the Tween, or nil when applied instantly.
function K.tweenD(inst: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, delay: number?): Tween?
	local t, d = seconds, delay or 0
	if K.reduced() then
		t *= 0.6
		d *= 0.5
	end
	if t < 0.05 and d <= 0 then
		applyNow(inst, goals)
		return nil
	end
	local ok, tw = pcall(function()
		local tween = TweenService:Create(inst, TweenInfo.new(math.max(t, 0.01), style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out, 0, false, d), goals)
		tween:Play()
		return tween
	end)
	if ok then
		return tw
	end
	applyNow(inst, goals)
	return nil
end

-- Stops pending second stages of K.spring on `inst` (call before re-targeting on rapid taps).
function K.cancel(inst: Instance)
	motionSerial[inst] = (motionSerial[inst] or 0) + 1
end

local function overshoot(a: any, b: any, amt: number): any
	local ta = typeof(b)
	if ta == "number" and type(a) == "number" then
		return b + (b - a) * amt
	elseif ta == "UDim2" and typeof(a) == "UDim2" then
		return UDim2.new(
			b.X.Scale + (b.X.Scale - a.X.Scale) * amt,
			math.floor(b.X.Offset + (b.X.Offset - a.X.Offset) * amt + 0.5),
			b.Y.Scale + (b.Y.Scale - a.Y.Scale) * amt,
			math.floor(b.Y.Offset + (b.Y.Offset - a.Y.Offset) * amt + 0.5)
		)
	elseif ta == "Vector2" and typeof(a) == "Vector2" then
		return b + (b - a) * amt
	end
	return b
end

-- Two-stage spring: a fast Quint Out past the target (overshoot `amount` of the travel), then a soft
-- Sine settle. opts {duration = 0.42, amount = 0.08, delay = 0}. Reduced motion: one short tween.
function K.spring(inst: Instance, goals: { [string]: any }, opts: { [string]: any }?)
	local o = opts or {}
	local dur = o.duration or 0.42
	local delay = o.delay or 0
	K.cancel(inst)
	local mine = motionSerial[inst]
	if K.reduced() then
		K.tweenD(inst, dur * 0.5, goals, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, delay)
		return
	end
	local amt = o.amount or 0.08
	local over = {}
	for k, v in goals do
		local cur = nil
		pcall(function()
			cur = (inst :: any)[k]
		end)
		over[k] = overshoot(cur, v, amt)
	end
	local d1 = dur * 0.56
	K.tweenD(inst, d1, over, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, delay)
	task.delay(delay + d1, function()
		if motionSerial[inst] == mine and inst.Parent then
			K.tweenD(inst, dur - d1, goals, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	end)
end

local function scaleOf(g: Instance): UIScale
	local s = g:FindFirstChildOfClass("UIScale")
	if not s then
		s = make("UIScale", { Scale = 1 }, g)
	end
	return s :: UIScale
end
K.scaleOf = scaleOf

-- Spring pop-in of a panel / card: UIScale from -> 1 with a small overshoot.
function K.springIn(g: GuiObject, from: number?, opts: { [string]: any }?)
	local s = scaleOf(g)
	s.Scale = from or 0.9
	local o = opts or {}
	K.spring(s, { Scale = 1 }, { duration = o.duration or 0.42, amount = o.amount or 0.35, delay = o.delay })
end

-- App launch / close zoom. `root` is a full-size page inside a parent `parentSize` px big; it grows
-- from `fromCenter` (px in the parent) at `fromScale`. opts {duration?, reverse?, cover? (a frame
-- drawn over the page, e.g. the icon colour + glyph, faded out on open / in on close), onDone?}
function K.zoomFrom(root: GuiObject, parentSize: Vector2, fromCenter: Vector2, fromScale: number, opts: { [string]: any }?)
	local o = opts or {}
	local s = scaleOf(root)
	local d = o.duration or 0.34
	K.cancel(s)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	local full = UDim2.fromScale(0.5, 0.5)
	local at = UDim2.fromOffset(fromCenter.X, fromCenter.Y)
	local cover: GuiObject? = o.cover
	local reduced = K.reduced()
	if o.reverse then
		if cover then
			cover.Visible = true
			K.tweenD(cover, d * 0.5, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			-- the vector glyph fades back in so the page lands in its icon as the icon
			for _, c in cover:GetDescendants() do
				local gt = c:GetAttribute("GlyphT")
				if gt ~= nil and c:IsA("Frame") then
					K.tweenD(c, d * 0.4, { BackgroundTransparency = gt }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, d * 0.2)
				end
			end
		end
		K.tweenD(root, d * 0.85, { Position = at }, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		K.tweenD(s, d * 0.85, { Scale = fromScale }, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		task.delay(if reduced then d * 0.55 else d * 0.85, function()
			if o.onDone then
				o.onDone()
			end
		end)
		return
	end
	root.Position = at
	s.Scale = fromScale
	if cover then
		cover.Visible = true
		cover.BackgroundTransparency = 0
		K.tweenD(cover, d * 0.55, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, d * 0.25)
		for _, c in cover:GetDescendants() do
			if c:IsA("TextLabel") then
				c.TextTransparency = 0
				K.tweenD(c, d * 0.4, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, d * 0.1)
			elseif c:IsA("Frame") and c:GetAttribute("GlyphT") ~= nil then
				c.BackgroundTransparency = c:GetAttribute("GlyphT")
				K.tweenD(c, d * 0.4, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, d * 0.1)
			end
		end
		task.delay(d * 0.85, function()
			if cover.BackgroundTransparency > 0.95 then
				cover.Visible = false
			end
		end)
	end
	K.tweenD(root, d, { Position = full }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	K.spring(s, { Scale = 1 }, { duration = d + 0.1, amount = 0.02 })
	if o.onDone then
		task.delay(d, o.onDone)
	end
end

-- Page transitions (iOS-style push / pop with parallax). Pages are full-size frames in the same
-- container that stay alive (Visible toggled). The page underneath drifts 28 % and darkens.
local function navVeil(page: GuiObject): Frame
	local v = page:FindFirstChild("NavVeil") :: Frame?
	if not v then
		v = K.frame(page, { Name = "NavVeil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 60, Visible = false })
		local c = page:FindFirstChildOfClass("UICorner")
		if c then
			K.corner(v :: Frame, c.CornerRadius)
		end
	end
	return v :: Frame
end

-- opts {duration?, rest? (UDim2 the pages rest at; default the container's top-left)}
function K.pushPage(newPage: GuiObject, oldPage: GuiObject?, opts: { [string]: any }?)
	local o = opts or {}
	local d = o.duration or 0.34
	local rest: UDim2 = o.rest or UDim2.fromScale(0, 0)
	newPage.AnchorPoint = Vector2.zero
	newPage:SetAttribute("NavSerial", (newPage:GetAttribute("NavSerial") or 0) + 1)
	newPage.Visible = true
	newPage.Position = rest + UDim2.fromScale(1, 0)
	K.tweenD(newPage, d, { Position = rest }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	if oldPage and oldPage ~= newPage then
		oldPage.AnchorPoint = Vector2.zero
		local veil = navVeil(oldPage)
		veil.Visible = true
		veil.BackgroundTransparency = 1
		K.tweenD(veil, d, { BackgroundTransparency = 0.55 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		K.tweenD(oldPage, d, { Position = rest + UDim2.fromScale(-0.28, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local serial = (oldPage:GetAttribute("NavSerial") or 0) + 1
		oldPage:SetAttribute("NavSerial", serial)
		task.delay(if K.reduced() then d * 0.6 else d, function()
			if oldPage:GetAttribute("NavSerial") == serial then
				oldPage.Visible = false
				oldPage.Position = rest
				veil.Visible = false
			end
		end)
	end
end

function K.popPage(topPage: GuiObject, underPage: GuiObject?, opts: { [string]: any }?)
	local o = opts or {}
	local d = o.duration or 0.3
	local rest: UDim2 = o.rest or UDim2.fromScale(0, 0)
	local serial = (topPage:GetAttribute("NavSerial") or 0) + 1
	topPage:SetAttribute("NavSerial", serial)
	K.tweenD(topPage, d, { Position = rest + UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	task.delay(if K.reduced() then d * 0.6 else d, function()
		if topPage:GetAttribute("NavSerial") == serial then
			topPage.Visible = false
			topPage.Position = rest
		end
	end)
	if underPage and underPage ~= topPage then
		underPage:SetAttribute("NavSerial", (underPage:GetAttribute("NavSerial") or 0) + 1)
		underPage.AnchorPoint = Vector2.zero
		underPage.Visible = true
		underPage.Position = rest + UDim2.fromScale(-0.28, 0)
		local veil = navVeil(underPage)
		veil.Visible = true
		veil.BackgroundTransparency = 0.55
		K.tweenD(underPage, d, { Position = rest }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		K.tweenD(veil, d, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		task.delay(d, function()
			if veil.BackgroundTransparency > 0.95 then
				veil.Visible = false
			end
		end)
	end
end

-- Expanding "radar" rings around a point (searching / calling states). Returns stop().
-- opts {color?, size? (px, final diameter), period? (s), count? (rings)}
function K.radar(parent: GuiObject, center: UDim2, opts: { [string]: any }?): () -> ()
	local o = opts or {}
	local color = o.color or CYAN
	local size = o.size or 120
	local period = o.period or 1.6
	local count = o.count or 2
	local rings: { Frame } = {}
	for i = 1, count do
		local r = K.frame(parent, { Name = "Radar" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = center, Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, BackgroundColor3 = color, ZIndex = parent.ZIndex + 1 })
		K.corner(r, UDim.new(0.5, 0))
		local st = K.stroke(r, color, 1.5, 1)
		st.Name = "RadarStroke"
		table.insert(rings, r)
	end
	local running = true
	if K.reduced() then
		rings[1].Size = UDim2.fromOffset(size * 0.6, size * 0.6)
		rings[1].BackgroundTransparency = 0.88
		return function()
			running = false
			for _, r in rings do
				r:Destroy()
			end
		end
	end
	for i, r in rings do
		task.spawn(function()
			task.wait((i - 1) * period / count)
			while running and r.Parent do
				if K.shownInTree(r) then
					local st = r:FindFirstChild("RadarStroke") :: UIStroke
					r.Size = UDim2.fromOffset(10, 10)
					r.BackgroundTransparency = 0.8
					st.Transparency = 0.2
					K.tweenD(r, period, { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
					K.tweenD(st, period, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
				task.wait(period)
			end
		end)
	end
	return function()
		running = false
		for _, r in rings do
			r:Destroy()
		end
	end
end

-- Generic count-up for a number label. opts {from?, duration = 0.6, format = K.commas, prefix?,
-- suffix?} -> the serial (a newer call on the same label supersedes an older one).
local countSerial: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
function K.countUp(label: TextLabel, to: number, opts: { [string]: any }?): number
	local o = opts or {}
	local fmt = o.format or K.commas
	local pre, suf = o.prefix or "", o.suffix or ""
	local from = tonumber(o.from) or 0
	countSerial[label] = (countSerial[label] or 0) + 1
	local mine = countSerial[label]
	if K.reduced() or from == to then
		K.setText(label, pre .. fmt(to) .. suf)
		return mine
	end
	local dur = o.duration or 0.6
	local t0 = os.clock()
	task.spawn(function()
		while countSerial[label] == mine and label.Parent do
			local u = math.min(1, (os.clock() - t0) / dur)
			local e = 1 - (1 - u) ^ 4
			K.setText(label, pre .. fmt(from + (to - from) * e) .. suf)
			if u >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
	return mine
end

-- A soft light band that sweeps across `frame` once (progress fills, success cards, buttons).
-- Reuses one "Sheen" child. opts {duration = 0.8, delay = 0, strength = 0.55}
function K.sheen(frame: GuiObject, opts: { [string]: any }?)
	if K.reduced() then
		return
	end
	local o = opts or {}
	local band = frame:FindFirstChild("SheenBand") :: Frame?
	local g: UIGradient
	if not band then
		band = K.frame(frame, { Name = "SheenBand", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = o.strength or 0.55, ZIndex = frame.ZIndex + 1 })
		local c = frame:FindFirstChildOfClass("UICorner")
		if c then
			K.corner(band :: Frame, c.CornerRadius)
		end
		g = K.gradient(band :: Frame, { Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, 20, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }))
	else
		g = (band :: Frame):FindFirstChildOfClass("UIGradient") :: UIGradient
	end
	(band :: Frame).Visible = true
	g.Offset = Vector2.new(-1, 0)
	K.tweenD(g, o.duration or 0.8, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, o.delay)
end

-- Looping shimmer while `frame` is shown (skeletons, "searching" states). Returns stop().
function K.shimmer(frame: GuiObject, opts: { [string]: any }?): () -> ()
	local o = opts or {}
	local running = true
	if K.reduced() then
		return function() end
	end
	task.spawn(function()
		while running and frame.Parent do
			if K.shownInTree(frame) then
				K.sheen(frame, { duration = o.duration or 1.1, strength = o.strength or 0.9 })
			end
			task.wait(o.period or 1.5)
		end
	end)
	return function()
		running = false
	end
end

-- Idle "breathing" glow (slow sine on a UIStroke / frame transparency) while `on`; static on low tier.
function K.breathe(target: Instance, on: boolean, lo: number?, hi: number?)
	local prop = if target:IsA("UIStroke") then "Transparency" else "BackgroundTransparency"
	local key = "__breathe"
	if not on then
		pulses[target] = nil
		return
	end
	if pulses[target] then
		return
	end
	local serial = os.clock()
	pulses[target] = serial
	local a, b = lo or 0.15, hi or 0.75
	if K.reduced() then
		(target :: any)[prop] = a
		return
	end
	local _ = key
	task.spawn(function()
		local flip = false
		while pulses[target] == serial and target.Parent do
			flip = not flip
			K.tween(target, 1.4, { [prop] = if flip then a else b }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.wait(1.45)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Text utilities
---------------------------------------------------------------------------------------------------
function K.textSize(text: string, size: number, font: Enum.Font?, width: number?): Vector2
	local w = width or 10000
	local ok, v = pcall(TextService.GetTextSize, TextService, text, size, font or K.Font.medium, Vector2.new(w, 10000))
	if ok and typeof(v) == "Vector2" and v.Y > 0 then
		if width and v.X > w + 1 then
			-- a measurer that ignored the wrap width: derive the wrapped line count
			local lines = math.ceil(v.X / math.max(1, w))
			return Vector2.new(w, math.max(v.Y, lines * size * 1.25))
		end
		return v
	end
	local units = 0
	for _, cp in utf8.codes(text) do
		units += if cp >= 0x1100 then 0.95 elseif cp == 32 then 0.3 elseif cp >= 0x2000 then 1.1 else 0.6
	end
	local tw = units * size
	local lines = math.max(1, math.ceil(tw / math.max(1, w)))
	for _ in string.gmatch(text, "\n") do
		lines += 1
	end
	return Vector2.new(math.min(tw, w), lines * size * 1.25)
end

-- Conservative width model (Hangul / CJK 1.0 em, emoji 1.2 em, Latin ~0.6 em): used to size wrapped
-- text boxes explicitly so they fit whatever fallback font renders Korean.
local function cpWidth(cp: number): number
	if cp == 32 then
		return 0.3
	elseif cp >= 0x1100 and cp <= 0x11FF or cp >= 0x3130 and cp <= 0x318F or cp >= 0xAC00 and cp <= 0xD7A3 or cp >= 0x4E00 and cp <= 0x9FFF then
		return 1.0
	elseif cp >= 0x1F000 or cp >= 0x2600 and cp <= 0x27BF then
		return 1.2
	elseif cp >= 48 and cp <= 57 then
		return 0.62
	elseif cp >= 65 and cp <= 90 then
		return 0.7
	elseif cp >= 97 and cp <= 122 then
		return 0.58
	elseif cp < 128 then
		return 0.42
	end
	return 0.8
end

function K.textWidth(text: string, size: number): number
	local w = 0
	for _, cp in utf8.codes(text) do
		w += cpWidth(cp)
	end
	return w * size
end

-- Greedy word wrap with the conservative model -> number of lines.
function K.lineCount(text: string, size: number, width: number): number
	local count = 0
	local space = 0.3 * size
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local lineW, n = 0, 0
		local any = false
		for word in string.gmatch(line, "%S+") do
			any = true
			local ww = K.textWidth(word, size)
			if n > 0 and lineW + space + ww > width then
				count += 1
				lineW, n = ww, 1
			else
				lineW = if n > 0 then lineW + space + ww else ww
				n += 1
			end
			-- a single word longer than the line wraps by characters
			while lineW > width and width > size do
				count += 1
				lineW -= width
			end
		end
		count += 1
		local _ = any
	end
	return math.max(1, count)
end

-- Height (px) of wrapped text at `size` in a box `width` wide (line height 1.3).
function K.textHeight(text: string, size: number, width: number): number
	return math.ceil(K.lineCount(text, size, width) * size * 1.3)
end

function K.commas(n: number): string
	n = tonumber(n) or 0
	if n ~= n or n == math.huge or n == -math.huge then
		n = 0
	end
	local neg = n < 0
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if neg and out ~= "0" then "-" else "") .. out
end

function K.won(n: any): string
	return K.commas(tonumber(n) or 0) .. "원"
end

-- Short form for tight chips: 1.2만 / 3.4억
function K.wonShort(n: any): string
	local v = tonumber(n) or 0
	local a = math.abs(v)
	local sign = if v < 0 then "-" else ""
	if a >= 1e8 then
		local s = string.format("%.1f", a / 1e8)
		s = string.gsub(s, "%.0$", "")
		return sign .. s .. "억원"
	elseif a >= 1e5 then
		return sign .. K.commas(math.floor(a / 1e4)) .. "만원"
	elseif a >= 1e4 then
		local s = string.format("%.1f", a / 1e4)
		s = string.gsub(s, "%.0$", "")
		return sign .. s .. "만원"
	end
	return K.won(v)
end

function K.korClock(clock: number): string
	local minutes = math.floor(((tonumber(clock) or 0) % 24) * 60 + 1e-6)
	local h, m = minutes // 60, minutes % 60
	local ampm = if h < 12 then "오전" else "오후"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%s %d:%02d", ampm, h12, m)
end

function K.clock24(clock: number): string
	local minutes = math.floor(((tonumber(clock) or 0) % 24) * 60 + 1e-6)
	return string.format("%02d:%02d", minutes // 60, minutes % 60)
end

-- 1 stud = 0.3 m (true-scale map)
function K.meters(studs: number): string
	local m = (tonumber(studs) or 0) * 0.3
	if m < 1000 then
		return string.format("%dm", math.floor(m / 5 + 0.5) * 5)
	end
	return string.format("%.1fkm", m / 1000)
end

-- walking at 16 studs/s (Humanoid default)
function K.walkTime(studs: number): string
	local s = (tonumber(studs) or 0) / 16
	if s < 60 then
		return "도보 1분 미만"
	end
	return string.format("도보 %d분", math.floor(s / 60 + 0.5))
end

function K.countdown(sec: any): string
	local s = math.max(0, math.floor(tonumber(sec) or 0))
	if s >= 3600 then
		return string.format("%d시간 %d분", s // 3600, (s % 3600) // 60)
	elseif s >= 60 then
		return string.format("%d분 %02d초", s // 60, s % 60)
	end
	return string.format("%d초", s)
end

-- Korean particle (으)로
function K.ro(word: string): string
	local last = 0
	for _, cp in utf8.codes(word) do
		last = cp
	end
	if last >= 0xAC00 and last <= 0xD7A3 then
		local jong = (last - 0xAC00) % 28
		if jong == 0 or jong == 8 then
			return word .. "로"
		end
		return word .. "으로"
	end
	return word .. "(으)로"
end

---------------------------------------------------------------------------------------------------
-- Icon tiles / avatars
---------------------------------------------------------------------------------------------------
local function shade(c: Color3, ds: number, dv: number): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, math.clamp(s + ds, 0, 1), math.clamp(v + dv, 0, 1))
end
K.shade = shade

-- Rounded-square (or round) gradient tile with a glyph: the kit's icon style.
function K.iconTile(parent: Instance, size: number, glyph: string, color: Color3?, round: boolean?): Frame
	local c = color or K.Color.accent
	local f = K.frame(parent, { Name = "Icon", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
	K.corner(f, if round then UDim.new(0.5, 0) else UDim.new(0.28, 0))
	K.gradient(f, { shade(c, -0.08, 0.12), shade(c, 0.1, -0.22) }, 125)
	local gloss = K.frame(f, { Name = "Gloss", Size = UDim2.fromScale(1, 0.5), BackgroundTransparency = 0.88, BackgroundColor3 = Color3.new(1, 1, 1) })
	K.corner(gloss, if round then UDim.new(0.5, 0) else UDim.new(0.28, 0))
	K.text(f, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = glyph, TextSize = math.max(11, math.floor(size * 0.5)), Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center })
	return f
end

-- Vector app glyphs: one consistent white silhouette set drawn from Frames in unit (Scale)
-- coordinates, so they scale with their box and never depend on the platform's emoji style.
-- K.Glyph(parent, name, {cut = Color3 (the tile colour behind, for the few negative shapes), color?})
-- -> Frame (fills its parent; square). Names: call, messages, map, bank, jobs, realty, profile, shop,
-- settings, taxi, camera. Parts carry attribute GlyphT (their resting transparency) so launch
-- covers can fade them. Returns nil for an unknown name (callers fall back to an emoji).
local GLYPHS: { [string]: (add: any, cut: any, clip: any) -> () } = {
	call = function(add, _cut, _clip)
		-- a classic receiver: handle bar on top, ear / mouth cups below, tilted like the Material icon
		-- (grot turns each part about the glyph centre: no rotated container, so clipping and the
		-- layout tools stay exact)
		add(0.5, 0.4, 0.74, 0.2, { r = 0.5, grot = -135 })
		add(0.19, 0.55, 0.28, 0.34, { r = 0.42, grot = -135 })
		add(0.81, 0.55, 0.28, 0.34, { r = 0.42, grot = -135 })
	end,
	messages = function(add, _cut, _clip)
		add(0.5, 0.45, 0.88, 0.66, { r = 0.5 })
		add(0.27, 0.73, 0.2, 0.2, { rot = 30, r = 0.12 })
	end,
	map = function(add, cut, _clip)
		add(0.5, 0.58, 0.44, 0.44, { rot = 45, r = 0.1 })
		add(0.5, 0.4, 0.64, 0.64, { r = 0.5 })
		cut(0.5, 0.4, 0.26, 0.26, { r = 0.5 })
	end,
	bank = function(add, _cut, clip)
		local roof = clip(0.5, 0.21, 0.92, 0.3)
		-- a 0.46-unit square (sizes are relative to the 0.92 x 0.3 clip box) turned 45 degrees
		add(0.5, 1.02, 0.5, 1.533, { rot = 45, parent = roof, r = 0.06 })
		for i = 0, 3 do
			add(0.2 + i * 0.2, 0.6, 0.11, 0.34, { r = 0.3 })
		end
		add(0.5, 0.41, 0.84, 0.06, { r = 0.5 })
		add(0.5, 0.82, 0.9, 0.09, { r = 0.5 })
	end,
	jobs = function(add, cut, _clip)
		add(0.5, 0.23, 0.38, 0.08, { r = 0.5 })
		add(0.33, 0.29, 0.08, 0.16, { r = 0.5 })
		add(0.67, 0.29, 0.08, 0.16, { r = 0.5 })
		add(0.5, 0.6, 0.9, 0.58, { r = 0.2 })
		cut(0.5, 0.56, 0.9, 0.05, { t = 0.35 })
		add(0.5, 0.56, 0.16, 0.12, { r = 0.3 })
	end,
	realty = function(add, cut, clip)
		local roof = clip(0.5, 0.29, 0.96, 0.42)
		-- a 0.52-unit square (relative to the 0.96 x 0.42 clip box) turned 45 degrees
		add(0.5, 1.0, 0.542, 1.238, { rot = 45, parent = roof, r = 0.08 })
		add(0.5, 0.67, 0.64, 0.46, { r = 0.1 })
		cut(0.5, 0.77, 0.18, 0.26, { r = 0.3 })
	end,
	profile = function(add, _cut, clip)
		add(0.5, 0.3, 0.36, 0.36, { r = 0.5 })
		local body = clip(0.5, 0.74, 0.8, 0.36)
		add(0.5, 0.95, 1, 1.9, { r = 0.5, parent = body })
	end,
	shop = function(add, cut, _clip)
		add(0.5, 0.36, 0.42, 0.42, { r = 0.5 })
		cut(0.5, 0.36, 0.26, 0.26, { r = 0.5 })
		add(0.5, 0.64, 0.74, 0.56, { r = 0.18 })
		cut(0.36, 0.5, 0.07, 0.07, { r = 0.5 })
		cut(0.64, 0.5, 0.07, 0.07, { r = 0.5 })
	end,
	settings = function(add, cut, _clip)
		for i = 0, 3 do
			add(0.5, 0.5, 0.17, 0.92, { rot = i * 45, r = 0.3 })
		end
		add(0.5, 0.5, 0.7, 0.7, { r = 0.5 })
		cut(0.5, 0.5, 0.3, 0.3, { r = 0.5 })
	end,
	taxi = function(add, cut, _clip)
		add(0.5, 0.2, 0.24, 0.09, { r = 0.3 })
		add(0.5, 0.39, 0.62, 0.3, { r = 0.3 })
		cut(0.5, 0.42, 0.48, 0.14, { r = 0.25 })
		add(0.5, 0.62, 0.9, 0.3, { r = 0.3 })
		add(0.24, 0.8, 0.16, 0.14, { r = 0.3 })
		add(0.76, 0.8, 0.16, 0.14, { r = 0.3 })
		cut(0.24, 0.62, 0.13, 0.11, { r = 0.5 })
		cut(0.76, 0.62, 0.13, 0.11, { r = 0.5 })
	end,
	camera = function(add, cut, _clip)
		add(0.38, 0.27, 0.3, 0.14, { r = 0.3 })
		add(0.5, 0.58, 0.9, 0.6, { r = 0.22 })
		cut(0.5, 0.58, 0.38, 0.38, { r = 0.5 })
		add(0.5, 0.58, 0.24, 0.24, { r = 0.5 })
		cut(0.78, 0.4, 0.08, 0.08, { r = 0.5, t = 0.2 })
	end,
}

function K.Glyph(parent: Instance, name: string, opts: { [string]: any }?): Frame?
	local draw = GLYPHS[name]
	if not draw then
		return nil
	end
	local o = opts or {}
	local col = o.color or Color3.new(1, 1, 1)
	local cutCol = o.cut or Color3.fromRGB(40, 40, 60)
	local z = o.zIndex or ((parent :: any).ZIndex and (parent :: any).ZIndex + 1) or 2
	local root = K.frame(parent, { Name = "Glyph_" .. name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = o.size or UDim2.fromScale(0.56, 0.56), ZIndex = z })
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, root)
	local order = 0
	local function part(cx: number, cy: number, w: number, h: number, p: { [string]: any }?, color: Color3): Frame
		local q = p or {}
		order += 1
		local rot = q.rot or 0
		if q.grot then
			-- clockwise about (0.5, 0.5), like Roblox's Rotation (y points down)
			local a = math.rad(q.grot)
			local dx, dy = cx - 0.5, cy - 0.5
			cx, cy = 0.5 + dx * math.cos(a) - dy * math.sin(a), 0.5 + dx * math.sin(a) + dy * math.cos(a)
			rot += q.grot
		end
		local f = K.frame(q.parent or root, {
			Name = q.name or ("P" .. order),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(cx, cy),
			Size = UDim2.fromScale(w, h),
			BackgroundTransparency = q.t or 0,
			BackgroundColor3 = color,
			Rotation = rot,
			ZIndex = z,
		})
		if q.r then
			K.corner(f, UDim.new(q.r, 0))
		end
		f:SetAttribute("GlyphT", f.BackgroundTransparency)
		return f
	end
	local function add(cx: number, cy: number, w: number, h: number, p: { [string]: any }?): Frame
		return part(cx, cy, w, h, p, col)
	end
	local function cut(cx: number, cy: number, w: number, h: number, p: { [string]: any }?): Frame
		return part(cx, cy, w, h, p, cutCol)
	end
	-- a non-rotated clipping box (rotated children inside it are clipped to its rectangle)
	local function clip(cx: number, cy: number, w: number, h: number): Frame
		order += 1
		return K.frame(root, { Name = "Clip" .. order, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx, cy), Size = UDim2.fromScale(w, h), ClipsDescendants = true, ZIndex = z })
	end
	draw(add, cut, clip)
	return root
end

function K.avatar(parent: Instance, size: number, glyph: string, color: Color3?, props: { [string]: any }?): Frame
	local f = K.iconTile(parent, size, glyph, color or K.Color.violet, true)
	f.Name = "Avatar"
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	return f
end

---------------------------------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------------------------------
local BUTTON_STYLES = {
	primary = { fg = K.Color.onAccent, grad = K.Grad.primary },
	secondary = { bg = K.Color.card2, fg = K.Color.text, stroke = 0.88 },
	tonal = { bg = Color3.fromRGB(22, 58, 76), fg = CYAN, stroke = 0.9 },
	ghost = { bg = K.Color.card, fg = CYAN, transparent = 1 },
	danger = { bg = Color3.fromRGB(64, 24, 30), fg = Color3.fromRGB(255, 132, 136), stroke = 0.9 },
	destructive = { fg = Color3.new(1, 1, 1), grad = K.Grad.danger },
	success = { fg = K.Color.onAccent, grad = K.Grad.success },
	gold = { fg = K.Color.onGold, grad = K.Grad.gold },
	bridge = { fg = Color3.new(1, 1, 1), grad = K.Grad.bridge },
	icon = { bg = K.Color.card2, fg = K.Color.text, stroke = 0.88 },
	glass = { bg = K.Color.glass, fg = K.Color.text, stroke = 0.84, transparent = K.GLASS_T },
}
K.ButtonStyles = BUTTON_STYLES

-- opts {text, icon?, style = primary|secondary|tonal|ghost|danger|destructive|success|gold|bridge|
--       icon|glass, size?, position?, anchor?, order?, zIndex?, textSize?, name?, onClick?, sound?}
function K.Button(parent: Instance?, opts: { [string]: any }): TextButton
	local styleName = opts.style or "primary"
	local style = BUTTON_STYLES[styleName] or BUTTON_STYLES.primary
	local isIcon = styleName == "icon"
	local b = make("TextButton", {
		Name = opts.name or "Button",
		BackgroundColor3 = if style.grad then Color3.new(1, 1, 1) else style.bg,
		BackgroundTransparency = style.transparent or 0,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = if opts.icon and opts.text then opts.icon .. "  " .. opts.text else (opts.text or opts.icon or ""),
		TextColor3 = style.fg,
		Font = K.Font.bold,
		TextSize = opts.textSize or (if isIcon then 18 else K.Type.bodySm),
		Size = opts.size or (if isIcon then UDim2.fromOffset(44, 44) else UDim2.new(1, 0, 0, 44)),
		Position = opts.position or UDim2.new(),
		AnchorPoint = opts.anchor or Vector2.zero,
		LayoutOrder = opts.order or 0,
		ZIndex = opts.zIndex or 1,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, nil)
	b:SetAttribute("KitStyle", styleName)
	K.corner(b, if isIcon then UDim.new(0.5, 0) else UDim.new(0, opts.radius or K.Radius.sm))
	if style.grad then
		K.gradient(b, style.grad, 15)
		-- top sheen for a glossy, lit-from-above look
		local sheen = K.frame(b, { Name = "Sheen", Size = UDim2.new(1, 0, 0.5, 0), BackgroundTransparency = 0.9, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = b.ZIndex })
		K.corner(sheen, if isIcon then UDim.new(0.5, 0) else UDim.new(0, opts.radius or K.Radius.sm))
	elseif style.stroke then
		K.stroke(b, nil, 1, style.stroke)
	end
	K.pressable(b, { sound = opts.sound })
	if opts.onClick then
		b.Activated:Connect(function()
			if b:GetAttribute("Disabled") then
				return
			end
			local ok, err = pcall(opts.onClick)
			if not ok then
				warn("[GwangalliUI] button: " .. tostring(err))
			end
		end)
	end
	b.Parent = parent
	return b
end

function K.IconButton(parent: Instance?, opts: { [string]: any }): TextButton
	local o = table.clone(opts)
	o.style = o.style or "icon"
	if o.style ~= "icon" and not o.size then
		o.size = UDim2.fromOffset(44, 44)
	end
	return K.Button(parent, o)
end

function K.setButtonEnabled(b: TextButton, enabled: boolean)
	b:SetAttribute("Disabled", if enabled then nil else true)
	b.TextTransparency = if enabled then 0 else 0.5
	local g = b:FindFirstChildOfClass("UIGradient")
	if g then
		g.Enabled = enabled
		b.BackgroundColor3 = if enabled then Color3.new(1, 1, 1) else K.Color.card2
	end
	if not g then
		local st = BUTTON_STYLES[b:GetAttribute("KitStyle") or ""]
		b.BackgroundTransparency = if enabled then ((st and st.transparent) or 0) else 0.35
	end
end

-- Busy state: keeps the label, dims it and adds "…" (restored with loading = false).
function K.setButtonLoading(b: TextButton, loading: boolean, text: string?)
	if loading then
		if b:GetAttribute("IdleText") == nil then
			b:SetAttribute("IdleText", b.Text)
		end
		b.Text = text or "처리 중…"
		b:SetAttribute("Disabled", true)
		b.TextTransparency = 0.3
	else
		local idle = b:GetAttribute("IdleText")
		if idle ~= nil then
			b.Text = idle
			b:SetAttribute("IdleText", nil)
		end
		b:SetAttribute("Disabled", nil)
		b.TextTransparency = 0
	end
end

---------------------------------------------------------------------------------------------------
-- List row / section header
---------------------------------------------------------------------------------------------------
-- opts {icon, iconColor, round?, title, subtitle?, trailing?, trailingColor?, trailingWidth?,
--       chevron?, badge? (number), height?, order?, name?, onClick?, grouped? (transparent, hairline)}
function K.ListRow(parent: Instance?, opts: { [string]: any }): any
	local h = opts.height or 56
	local clickable = opts.onClick ~= nil
	local row = make(if clickable then "TextButton" else "Frame", {
		Name = opts.name or "Row",
		Size = UDim2.new(1, 0, 0, h),
		BackgroundColor3 = K.Color.card,
		BackgroundTransparency = if opts.grouped then 1 else 0,
		BorderSizePixel = 0,
		LayoutOrder = opts.order or 0,
	}, nil)
	if clickable then
		local rb: any = row
		rb.Text = ""
		rb.AutoButtonColor = false
	end
	if not opts.grouped then
		K.corner(row, K.Radius.sm)
	else
		K.frame(row, { Name = "Hairline", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 60, 1, 0), Size = UDim2.new(1, -60, 0, 1), BackgroundTransparency = 0.93, BackgroundColor3 = K.Color.line })
	end
	local x = 12
	local icon
	if opts.icon then
		local s = math.min(h - 16, 38)
		icon = K.iconTile(row, s, opts.icon, opts.iconColor, opts.round)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 10, 0.5, 0)
		x = 10 + s + 12
	end
	local trailW = opts.trailingWidth or (if opts.trailing then 96 else 0)
	local chevW = if opts.chevron then 18 else 0
	local hasSub = opts.subtitle ~= nil and opts.subtitle ~= ""
	local title = K.text(row, {
		Name = "Title",
		Position = UDim2.new(0, x, 0, if hasSub then h / 2 - 19 else 0),
		Size = UDim2.new(1, -(x + trailW + chevW + 12), 0, if hasSub then 20 else h),
		Text = opts.title or "",
		Font = K.Font.bold,
		TextSize = K.Type.bodySm,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local subtitle = K.text(row, {
		Name = "Subtitle",
		Position = UDim2.new(0, x, 0, h / 2 + 1),
		Size = UDim2.new(1, -(x + trailW + chevW + 12), 0, 17),
		Text = opts.subtitle or "",
		TextColor3 = K.Color.sub,
		TextSize = K.Type.caption,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = hasSub,
	})
	local trailing = K.text(row, {
		Name = "Trailing",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(12 + chevW), 0.5, 0),
		Size = UDim2.fromOffset(math.max(0, trailW - 4), 20),
		Text = opts.trailing or "",
		TextColor3 = opts.trailingColor or K.Color.text,
		Font = K.Font.bold,
		TextSize = K.Type.bodySm,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if opts.chevron then
		K.text(row, { Name = "Chevron", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(16, 20), Text = "›", TextColor3 = K.Color.faint, TextSize = 20, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center })
	end
	-- callers often fill the subtitle later (distance, fare…): keep the two-line layout in sync
	local function relayoutTitle()
		local two = subtitle.Visible and subtitle.Text ~= ""
		title.Position = UDim2.new(0, x, 0, if two then h / 2 - 19 else 0)
		title.Size = UDim2.new(1, -(x + trailW + chevW + 12), 0, if two then 20 else h)
	end
	subtitle:GetPropertyChangedSignal("Text"):Connect(relayoutTitle)
	subtitle:GetPropertyChangedSignal("Visible"):Connect(relayoutTitle)
	local badge = nil
	if opts.badge ~= nil then
		badge = K.Badge(row, { position = UDim2.new(1, -(16 + chevW), 0.5, 0), anchor = Vector2.new(1, 0.5) })
		badge.set(opts.badge)
	end
	if clickable then
		local rowButton: any = row
		K.pressable(rowButton, { scale = 0.98 })
		rowButton.Activated:Connect(function()
			local ok, err = pcall(opts.onClick)
			if not ok then
				warn("[GwangalliUI] row: " .. tostring(err))
			end
		end)
	end
	row.Parent = parent
	return { row = row, title = title, subtitle = subtitle, trailing = trailing, icon = icon, badge = badge }
end

-- opts {title, action?, onAction?, order?, caption?}
function K.SectionHeader(parent: Instance?, opts: { [string]: any }): any
	local h = K.frame(nil, { Name = "Section_" .. tostring(opts.title), Size = UDim2.new(1, 0, 0, if opts.caption then 40 else 30), LayoutOrder = opts.order or 0 })
	local t = K.text(h, { Name = "Title", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 2, 0, 26), Size = UDim2.new(1, -90, 0, 22), Text = opts.title or "", Font = K.Font.bold, TextSize = K.Type.body, TextTruncate = Enum.TextTruncate.AtEnd })
	local cap = nil
	if opts.caption then
		cap = K.text(h, { Name = "Caption", Position = UDim2.fromOffset(2, 26), Size = UDim2.new(1, -4, 0, 14), Text = opts.caption, TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	local action = nil
	if opts.action then
		action = make("TextButton", { Name = "Action", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -8), Size = UDim2.fromOffset(84, 44), BackgroundTransparency = 1, Text = opts.action, TextColor3 = CYAN, Font = K.Font.bold, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Right }, h)
		K.pressable(action, { veil = false })
		if opts.onAction then
			action.Activated:Connect(function()
				pcall(opts.onAction)
			end)
		end
	end
	h.Parent = parent
	return { frame = h, title = t, caption = cap, action = action }
end

---------------------------------------------------------------------------------------------------
-- Tabs (underline) / Segmented (pill) / Toggle
---------------------------------------------------------------------------------------------------
-- opts {tabs = {{id, label, badge?}}, value?, onChange, size?, order?}
function K.Tabs(parent: Instance?, opts: { [string]: any }): any
	local holder = K.frame(nil, { Name = "Tabs", Size = opts.size or UDim2.new(1, 0, 0, 44), LayoutOrder = opts.order or 0 })
	K.frame(holder, { Name = "Hairline", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0.9, BackgroundColor3 = K.Color.line })
	local n = math.max(1, #opts.tabs)
	local bar = K.frame(holder, { Name = "Underline", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5 / n, 0, 1, 0), Size = UDim2.new(0.5 / n, 0, 0, 3), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
	K.corner(bar, UDim.new(0.5, 0))
	K.gradient(bar, { CYAN, VIOLET }, 0)
	local buttons = {}
	local badges = {}
	local api = { frame = holder, value = opts.value or (opts.tabs[1] and opts.tabs[1].id) }
	function api.set(id: string, silent: boolean?)
		for i, t in opts.tabs do
			local on = t.id == id
			local b = buttons[t.id]
			if b then
				b.TextColor3 = if on then K.Color.text else K.Color.faint
			end
			if on then
				K.spring(bar, { Position = UDim2.new((i - 0.5) / n, 0, 1, 0) }, { duration = 0.36, amount = 0.08 })
			end
		end
		local changed = api.value ~= id
		api.value = id
		if not silent and opts.onChange and changed then
			task.spawn(opts.onChange, id)
		end
	end
	function api.setBadge(id: string, count: any)
		local bd = badges[id]
		if bd then
			bd.set(count)
		end
	end
	for i, t in opts.tabs do
		local b = make("TextButton", {
			Name = "Tab_" .. t.id,
			Position = UDim2.new((i - 1) / n, 0, 0, 0),
			Size = UDim2.new(1 / n, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = t.label,
			Font = K.Font.bold,
			TextSize = K.Type.bodySm,
			TextColor3 = K.Color.faint,
			ZIndex = 2,
		}, holder)
		buttons[t.id] = b
		badges[t.id] = K.Badge(b, { position = UDim2.new(1, -8, 0, 6), anchor = Vector2.new(1, 0), size = 16 })
		if t.badge then
			badges[t.id].set(t.badge)
		end
		K.pressable(b, { veil = false, scale = 0.97 })
		b.Activated:Connect(function()
			api.set(t.id)
		end)
	end
	holder.Parent = parent
	api.set(api.value, true)
	return api
end

-- Pill segmented control. opts {items = {{id, label}}, value?, onChange, order?, height?}
function K.Segmented(parent: Instance?, opts: { [string]: any }): any
	local h = (opts.height or 44) + 6 -- 3 px inset around 44 px segments
	local holder = K.frame(nil, { Name = "Segmented", Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card, LayoutOrder = opts.order or 0 })
	K.corner(holder, K.Radius.sm)
	K.stroke(holder, nil, 1, 0.92)
	K.pad(holder, 3)
	local n = math.max(1, #opts.items)
	local pill = K.frame(holder, { Name = "Pill", Size = UDim2.new(1 / n, 0, 1, 0), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
	K.corner(pill, K.Radius.sm - 3)
	K.gradient(pill, K.Grad.primary, 15)
	local buttons = {}
	local api = { frame = holder, value = opts.value or (opts.items[1] and opts.items[1].id) }
	function api.set(id: string, silent: boolean?)
		for i, t in opts.items do
			local on = t.id == id
			if buttons[t.id] then
				buttons[t.id].TextColor3 = if on then K.Color.onAccent else K.Color.sub
			end
			if on then
				K.spring(pill, { Position = UDim2.new((i - 1) / n, 0, 0, 0) }, { duration = 0.34, amount = 0.06 })
			end
		end
		local changed = api.value ~= id
		api.value = id
		if not silent and opts.onChange and changed then
			task.spawn(opts.onChange, id)
		end
	end
	for i, t in opts.items do
		local b = make("TextButton", { Name = "Seg_" .. t.id, Position = UDim2.new((i - 1) / n, 0, 0, 0), Size = UDim2.new(1 / n, 0, 1, 0), BackgroundTransparency = 1, Text = t.label, Font = K.Font.bold, TextSize = K.Type.caption + 1, TextColor3 = K.Color.sub, ZIndex = 2 }, holder)
		buttons[t.id] = b
		K.pressable(b, { veil = false, scale = 0.97, sound = "toggle" })
		b.Activated:Connect(function()
			api.set(t.id)
		end)
	end
	holder.Parent = parent
	api.set(api.value, true)
	return api
end

-- opts {value, onChange, color?}. The button is a 60x44 hit area around the 52x32 switch.
function K.Toggle(parent: Instance?, opts: { [string]: any }): any
	local b = make("TextButton", { Name = "Toggle", Size = UDim2.fromOffset(60, 44), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, BorderSizePixel = 0 }, nil)
	local track = K.frame(b, { Name = "Track", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(52, 32), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card3 })
	K.corner(track, UDim.new(0.5, 0))
	local onColor = opts.color or CYAN
	local onFill = K.frame(track, { Name = "OnFill", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 1 })
	K.corner(onFill, UDim.new(0.5, 0))
	K.gradient(onFill, { shade(onColor, -0.05, 0.1), shade(onColor, 0.05, -0.08) }, 0)
	local knobShadow = K.frame(track, { Name = "KnobShadow", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 2), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 0.75, BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 2 })
	K.corner(knobShadow, UDim.new(0.5, 0))
	local knob = K.frame(track, { Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
	K.corner(knob, UDim.new(0.5, 0))
	local api = { button = b, track = track, value = opts.value == true }
	function api.set(v: boolean, silent: boolean?)
		api.value = v
		local at = if v then UDim2.new(1, -29, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
		if silent then
			knob.Position = at
			knobShadow.Position = at + UDim2.fromOffset(0, 2)
			onFill.BackgroundTransparency = if v then 0 else 1
		else
			K.spring(knob, { Position = at }, { duration = 0.34, amount = 0.12 })
			K.tween(knobShadow, 0.22, { Position = at + UDim2.fromOffset(0, 2) })
			K.tween(onFill, 0.2, { BackgroundTransparency = if v then 0 else 1 })
		end
		if not silent and opts.onChange then
			task.spawn(opts.onChange, v)
		end
	end
	function api.get(): boolean
		return api.value
	end
	b.Activated:Connect(function()
		K.feedback("toggle")
		api.set(not api.value)
	end)
	b.Parent = parent
	api.set(api.value, true)
	return api
end

---------------------------------------------------------------------------------------------------
-- Slider
---------------------------------------------------------------------------------------------------
-- opts {min=0, max=1, step?, value?, color?, onChange(v), onRelease(v), order?, size?}
-- -> {frame, set(v, silent?), get()}. The whole 44 px tall row is the hit area.
function K.Slider(parent: Instance?, opts: { [string]: any }): any
	local lo, hi = tonumber(opts.min) or 0, tonumber(opts.max) or 1
	if hi <= lo then
		hi = lo + 1
	end
	local step = tonumber(opts.step)
	local holder = make("TextButton", { Name = "Slider", Size = opts.size or UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = opts.order or 0 }, nil)
	local track = K.frame(holder, { Name = "Track", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 11, 0.5, 0), Size = UDim2.new(1, -22, 0, 6), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card3 })
	K.corner(track, UDim.new(0.5, 0))
	local fill = K.frame(track, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
	K.corner(fill, UDim.new(0.5, 0))
	K.gradient(fill, if opts.color then { shade(opts.color, 0, 0.1), opts.color } else { CYAN, VIOLET }, 0)
	local knob = K.frame(track, { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
	K.corner(knob, UDim.new(0.5, 0))
	K.stroke(knob, K.Color.shadow, 2, 0.75)
	local api = { frame = holder, value = lo }
	local function norm(v: number): number
		return (v - lo) / (hi - lo)
	end
	function api.set(v: number, silent: boolean?)
		local x = math.clamp(tonumber(v) or lo, lo, hi)
		if step and step > 0 then
			x = math.clamp(lo + math.floor((x - lo) / step + 0.5) * step, lo, hi)
		end
		local changed = x ~= api.value
		api.value = x
		local u = norm(x)
		fill.Size = UDim2.fromScale(u, 1)
		knob.Position = UDim2.fromScale(u, 0.5)
		if changed and not silent and opts.onChange then
			task.spawn(opts.onChange, x)
		end
	end
	function api.get(): number
		return api.value
	end
	function api.setRange(minV: number, maxV: number, stepV: number?)
		lo, hi = tonumber(minV) or 0, tonumber(maxV) or 1
		if hi <= lo then
			hi = lo + 1
		end
		step = tonumber(stepV)
		api.set(api.value, true)
	end
	local dragging: InputObject? = nil
	local lastTick = 0
	local function fromX(px: number)
		local ax, aw = track.AbsolutePosition.X, math.max(1, track.AbsoluteSize.X)
		local before = api.value
		api.set(lo + math.clamp((px - ax) / aw, 0, 1) * (hi - lo))
		if api.value ~= before and os.clock() - lastTick > 0.06 then
			lastTick = os.clock()
			K.haptic("tap")
		end
	end
	holder.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = input
			K.tween(knob, 0.1, { Size = UDim2.fromOffset(28, 28) })
			fromX(input.Position.X)
		end
	end)
	local c1 = UserInputService.InputChanged:Connect(function(input: InputObject)
		local d = dragging
		if not d or not holder.Parent then
			return
		end
		if input == d or (input.UserInputType == Enum.UserInputType.MouseMovement and d.UserInputType == Enum.UserInputType.MouseButton1) then
			fromX(input.Position.X)
		end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input: InputObject)
		local d = dragging
		if d and (input == d or input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = nil
			K.tween(knob, 0.14, { Size = UDim2.fromOffset(24, 24) })
			if opts.onRelease then
				task.spawn(opts.onRelease, api.value)
			end
		end
	end)
	holder.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
	end)
	holder.Parent = parent
	api.set(tonumber(opts.value) or lo, true)
	return api
end

---------------------------------------------------------------------------------------------------
-- Search bar
---------------------------------------------------------------------------------------------------
-- opts {placeholder, onChange(text), onSubmit(text), order?, size?, name?}
-- -> {frame, box, set(text), get(), clear(), release()}
function K.SearchBar(parent: Instance?, opts: { [string]: any }): any
	local f = K.frame(nil, { Name = opts.name or "SearchBar", Size = opts.size or UDim2.new(1, 0, 0, 44), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card, LayoutOrder = opts.order or 0 })
	K.corner(f, K.Radius.sm)
	local st = K.stroke(f, nil, 1, 0.9)
	K.text(f, { Name = "Glass", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 20, 1, 0), Text = "🔍", TextSize = 14, TextColor3 = K.Color.faint, TextXAlignment = Enum.TextXAlignment.Center })
	local box = make("TextBox", {
		Name = "Query",
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -84, 1, 0),
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		PlaceholderText = opts.placeholder or "검색",
		PlaceholderColor3 = K.Color.faint,
		Text = "",
		TextColor3 = K.Color.text,
		TextSize = K.Type.bodySm,
		Font = K.Font.medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, f)
	local clear = make("TextButton", { Name = "Clear", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 1, Text = "✕", TextColor3 = K.Color.sub, TextSize = 13, Font = K.Font.bold, Visible = false }, f)
	local api = { frame = f, box = box }
	local serial = 0
	box:GetPropertyChangedSignal("Text"):Connect(function()
		clear.Visible = box.Text ~= ""
		serial += 1
		local mine = serial
		task.delay(0.12, function()
			if mine == serial and opts.onChange then
				pcall(opts.onChange, box.Text)
			end
		end)
	end)
	box.Focused:Connect(function()
		K.tween(st, 0.15, { Color = CYAN, Transparency = 0.35 })
	end)
	box.FocusLost:Connect(function(enter: boolean)
		K.tween(st, 0.15, { Color = K.Color.line, Transparency = 0.9 })
		if enter and opts.onSubmit then
			pcall(opts.onSubmit, box.Text)
		end
	end)
	clear.Activated:Connect(function()
		K.feedback("tap")
		box.Text = ""
	end)
	function api.set(t: string)
		box.Text = t
	end
	function api.get(): string
		return box.Text
	end
	function api.clear()
		box.Text = ""
	end
	function api.release()
		pcall(function()
			box:ReleaseFocus()
		end)
	end
	f.Parent = parent
	return api
end

---------------------------------------------------------------------------------------------------
-- Chip / Badge / Pill
---------------------------------------------------------------------------------------------------
-- Selectable filter chip: 44 px tall hit area around a 34 px pill.
-- opts {text, icon?, selected?, color?, onClick?, order?, name?, minWidth?}
function K.Chip(parent: Instance?, opts: { [string]: any }): any
	local label = if opts.icon then opts.icon .. " " .. (opts.text or "") else (opts.text or "")
	local tw = K.textSize(label, K.Type.caption + 1, K.Font.bold).X
	local w = math.max(opts.minWidth or 44, math.ceil(tw) + 28)
	local b = make("TextButton", { Name = opts.name or ("Chip_" .. tostring(opts.text)), Size = UDim2.fromOffset(w, 44), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = opts.order or 0 }, nil)
	local pill = K.frame(b, { Name = "Pill", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card })
	K.corner(pill, UDim.new(0.5, 0))
	local st = K.stroke(pill, nil, 1, 0.88)
	local txt = K.text(pill, { Name = "Label", Size = UDim2.fromScale(1, 1), Text = label, Font = K.Font.bold, TextSize = K.Type.caption + 1, TextColor3 = K.Color.sub, TextXAlignment = Enum.TextXAlignment.Center })
	local color = opts.color or CYAN
	local api = { button = b, selected = opts.selected == true }
	function api.set(sel: boolean)
		api.selected = sel
		pill.BackgroundColor3 = if sel then color else K.Color.card
		txt.TextColor3 = if sel then (if color == GOLD or color == CYAN or color == GREEN then K.Color.onAccent else Color3.new(1, 1, 1)) else K.Color.sub
		st.Transparency = if sel then 1 else 0.88
	end
	function api.setText(t: string)
		txt.Text = t
	end
	K.pressable(b, { veil = false, scale = 0.95, sound = "toggle" })
	if opts.onClick then
		b.Activated:Connect(function()
			pcall(opts.onClick)
		end)
	end
	b.Parent = parent
	api.set(api.selected)
	return api
end

-- Count badge (hidden at 0 / nil). opts {size?, color?, position?, anchor?}
function K.Badge(parent: Instance, opts: { [string]: any }?): any
	local o = opts or {}
	local s = o.size or 18
	local b = K.text(parent, {
		Name = "Badge",
		AnchorPoint = o.anchor or Vector2.new(0.5, 0.5),
		Position = o.position or UDim2.new(1, -3, 0, 3),
		Size = UDim2.fromOffset(s, s),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = o.color or RED,
		Text = "",
		Font = K.Font.bold,
		TextSize = math.max(11, math.floor(s * 0.66)),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 8,
		Visible = false,
	})
	K.corner(b, UDim.new(0.5, 0))
	K.pad(b, math.floor(s * 0.3), math.floor(s * 0.3), 0, 0)
	K.stroke(b, K.Color.bg, 1.5, 0)
	local api = { label = b }
	function api.set(n: any)
		if type(n) == "string" and n ~= "" then
			b.Visible = true
			K.setText(b, n)
		elseif type(n) == "number" and n > 0 then
			local was = b.Visible
			b.Visible = true
			K.setText(b, if n > 99 then "99+" else tostring(math.floor(n)))
			if not was then
				K.springIn(b, 0.4, { amount = 0.5, duration = 0.4 })
			end
		else
			b.Visible = false
		end
	end
	return api
end

-- Non-interactive status pill. opts {text, icon?, color?, height?, order?, name?}
function K.Pill(parent: Instance?, opts: { [string]: any }): TextLabel
	local label = if opts.icon then opts.icon .. " " .. (opts.text or "") else (opts.text or "")
	local h = opts.height or 22
	local color = opts.color or CYAN
	local tw = K.textSize(label, K.Type.micro, K.Font.bold).X
	local p = K.text(nil, {
		Name = opts.name or "Pill",
		Size = UDim2.fromOffset(math.ceil(tw) + 16, h),
		BackgroundTransparency = 0.82,
		BackgroundColor3 = color,
		Text = label,
		TextColor3 = shade(color, -0.25, 0.15),
		Font = K.Font.bold,
		TextSize = K.Type.micro,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = opts.order or 0,
	})
	K.corner(p, UDim.new(0.5, 0))
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------------------------------
-- Progress bar / ring
---------------------------------------------------------------------------------------------------
function K.ProgressBar(parent: Instance?, opts: { [string]: any }?): any
	local o = opts or {}
	local track = K.frame(nil, { Name = "Progress", Size = UDim2.new(1, 0, 0, o.height or 8), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card3, LayoutOrder = o.order or 0 })
	K.corner(track, UDim.new(0.5, 0))
	local fill = K.frame(track, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
	K.corner(fill, UDim.new(0.5, 0))
	local c = o.color or CYAN
	local grad = K.gradient(fill, { shade(c, -0.05, 0.12), shade(c, 0.05, -0.08) }, 0)
	local api = { frame = track, fill = fill }
	local lastX = 0
	function api.set(value: number, instant: boolean?)
		local x = math.clamp(tonumber(value) or 0, 0, 1)
		if instant then
			fill.Size = UDim2.fromScale(x, 1)
		else
			K.tween(fill, 0.6, { Size = UDim2.fromScale(x, 1) })
			if x > lastX + 0.001 and x > 0.02 then
				K.sheen(fill, { duration = 0.9, delay = 0.15, strength = 0.45 })
			end
		end
		lastX = x
	end
	function api.setColor(col: Color3)
		grad.Color = ColorSequence.new(shade(col, -0.05, 0.12), shade(col, 0.05, -0.08))
	end
	track.Parent = parent
	api.set(o.value or 0, true)
	return api
end

-- Circular progress / timer ring without images: two clipped halves of a stroked circle whose
-- UIGradient transparency sweeps clockwise from 12 o'clock. opts {size, thickness?, color?,
-- track?, text?} -> {frame, set(p 0..1), label}
function K.Ring(parent: Instance?, opts: { [string]: any }): any
	local s = opts.size or 36
	local th = opts.thickness or 3
	local color = opts.color or GOLD
	local holder = K.frame(nil, { Name = opts.name or "Ring", Size = UDim2.fromOffset(s, s), LayoutOrder = opts.order or 0 })
	local base = K.frame(holder, { Name = "Track", Size = UDim2.fromScale(1, 1) })
	K.corner(base, UDim.new(0.5, 0))
	K.stroke(base, opts.track or Color3.new(1, 1, 1), th, 0.82)
	local grads: { UIGradient } = {}
	local seq = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.499, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1) })
	for i = 1, 2 do
		local half = K.frame(holder, { Name = if i == 1 then "Right" else "Left", Position = UDim2.fromScale(if i == 1 then 0.5 else 0, 0), Size = UDim2.fromScale(0.5, 1), ClipsDescendants = true })
		local circle = K.frame(half, { Name = "Arc", Position = UDim2.fromScale(if i == 1 then -1 else 0, 0), Size = UDim2.fromScale(2, 1) })
		K.corner(circle, UDim.new(0.5, 0))
		local st = K.stroke(circle, color, th, 0)
		local g = K.gradient(st, { Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, 0, seq)
		grads[i] = g
	end
	local label = K.text(holder, { Name = "Value", Size = UDim2.fromScale(1, 1), Text = opts.text or "", Font = K.Font.bold, TextSize = math.max(11, math.floor(s * 0.36)), TextXAlignment = Enum.TextXAlignment.Center })
	local api = { frame = holder, label = label, value = 0 }
	function api.set(p: number)
		local x = math.clamp(tonumber(p) or 0, 0, 1)
		api.value = x
		grads[1].Rotation = math.clamp(x, 0, 0.5) / 0.5 * 180
		grads[2].Rotation = 180 + math.clamp(x - 0.5, 0, 0.5) / 0.5 * 180
	end
	function api.setColor(c: Color3)
		for _, g in grads do
			local st = g.Parent :: UIStroke
			st.Color = c
		end
	end
	holder.Parent = parent
	api.set(opts.value or 0)
	return api
end

---------------------------------------------------------------------------------------------------
-- Money
---------------------------------------------------------------------------------------------------
-- '12,300원' label with a count-up; set(n, animate) flashes green / red while counting (a coloured
-- twin label fades out over the digits: transparency only) and gives the number a small bump.
-- props: TextLabel props + Mono (default true) + Bump (default true)
function K.MoneyLabel(parent: Instance?, props: { [string]: any }?): any
	local p = props or {}
	local mono = p.Mono
	local bump = p.Bump ~= false
	local clean = {}
	for k, v in p do
		if k ~= "Mono" and k ~= "Bump" then
			clean[k] = v
		end
	end
	local l = K.text(parent, clean)
	if mono ~= false then
		K.mono(l)
	end
	local flashL = K.text(l, {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		Text = l.Text,
		TextSize = l.TextSize,
		Font = l.Font,
		TextXAlignment = l.TextXAlignment,
		TextYAlignment = l.TextYAlignment,
		TextTruncate = l.TextTruncate,
		TextColor3 = GREEN,
		TextTransparency = 1,
		ZIndex = l.ZIndex,
	})
	pcall(function()
		flashL.FontFace = l.FontFace
	end)
	local api = { label = l, value = 0, serial = 0, prefix = "", format = K.won, flash = true }
	local function show(text: string)
		K.setText(l, text)
		K.setText(flashL, text)
	end
	function api.setBaseColor(c: Color3)
		l.TextColor3 = c
	end
	function api.set(n: number, animate: boolean?)
		n = tonumber(n) or 0
		api.serial += 1
		local mine = api.serial
		local from = api.value
		api.value = n
		flashL.TextSize = l.TextSize
		if not animate or from == n or K.reduced() then
			show(api.prefix .. api.format(n))
			flashL.TextTransparency = 1
			return
		end
		if api.flash then
			flashL.TextColor3 = if n > from then GREEN else Color3.fromRGB(255, 120, 124)
			flashL.TextTransparency = 0
			K.tweenD(flashL, 0.55, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.65)
		end
		if bump then
			local sc = scaleOf(l)
			sc.Scale = 1.08
			K.spring(sc, { Scale = 1 }, { duration = 0.4, amount = 0.3 })
		end
		local t0 = os.clock()
		local dur = 0.6
		task.spawn(function()
			while api.serial == mine do
				local u = math.min(1, (os.clock() - t0) / dur)
				local e = 1 - (1 - u) ^ 4
				show(api.prefix .. api.format(from + (n - from) * e))
				if u >= 1 then
					break
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end
	return api
end

---------------------------------------------------------------------------------------------------
-- Empty state / skeleton
---------------------------------------------------------------------------------------------------
-- opts {icon, title, body?, actionText?, onAction?, order?, height?, color?, compact?}
-- -> {frame, set(opts)}
function K.EmptyState(parent: Instance?, opts: { [string]: any }): any
	local compact = opts.compact == true
	local f = K.frame(nil, { Name = opts.name or "EmptyState", Size = UDim2.new(1, 0, 0, opts.height or (if compact then 120 else 180)), LayoutOrder = opts.order or 0 })
	local holder = K.frame(f, { Name = "Stack", Size = UDim2.fromScale(1, 1) })
	K.list(holder, false, if compact then 4 else 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local circle = K.frame(holder, { Name = "IconCircle", Size = UDim2.fromOffset(if compact then 44 else 60, if compact then 44 else 60), BackgroundTransparency = 0.82, BackgroundColor3 = opts.color or CYAN, LayoutOrder = 1 })
	K.corner(circle, UDim.new(0.5, 0))
	local icon = K.text(circle, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = opts.icon or "✨", TextSize = if compact then 20 else 26, TextXAlignment = Enum.TextXAlignment.Center })
	local title = K.text(holder, { Name = "Title", Size = UDim2.new(1, -24, 0, 20), Text = opts.title or "", Font = K.Font.bold, TextSize = K.Type.body, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 2 })
	local body = K.text(holder, { Name = "Body", Size = UDim2.new(1, -32, 0, if compact then 16 else 34), Text = opts.body or "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 3 })
	local action: TextButton? = nil
	local api = { frame = f }
	local onAction = opts.onAction
	local function ensureAction(text: string?)
		if text and not action then
			action = K.Button(holder, { name = "Action", text = text, style = "tonal", size = UDim2.fromOffset(math.max(120, math.ceil(K.textSize(text, K.Type.bodySm, K.Font.bold).X) + 36), 44), order = 4, onClick = function()
				if onAction then
					onAction()
				end
			end })
		end
		if action then
			action.Visible = text ~= nil
			if text then
				action.Text = text
			end
		end
	end
	function api.set(o: { [string]: any })
		if o.icon then
			icon.Text = o.icon
		end
		if o.title then
			title.Text = o.title
		end
		if o.body ~= nil then
			body.Text = o.body
		end
		if o.color then
			circle.BackgroundColor3 = o.color
		end
		if o.onAction then
			onAction = o.onAction
		end
		ensureAction(o.actionText)
	end
	ensureAction(opts.actionText)
	f.Parent = parent
	return api
end

-- Loading placeholder rows with a moving shimmer (static on the low tier).
-- opts {rows=3, rowHeight=56, gap=8, avatar=true, order?} -> frame
function K.Skeleton(parent: Instance?, opts: { [string]: any }?): Frame
	local o = opts or {}
	local rows = o.rows or 3
	local rh = o.rowHeight or 56
	local gap = o.gap or 8
	local f = K.frame(nil, { Name = o.name or "Skeleton", Size = UDim2.new(1, 0, 0, rows * rh + (rows - 1) * gap), LayoutOrder = o.order or 0 })
	local grads: { UIGradient } = {}
	for i = 1, rows do
		local row = K.frame(f, { Name = "Row" .. i, Position = UDim2.fromOffset(0, (i - 1) * (rh + gap)), Size = UDim2.new(1, 0, 0, rh), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card })
		K.corner(row, K.Radius.sm)
		local x = 12
		if o.avatar ~= false then
			local a = K.frame(row, { Name = "Dot", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(math.min(36, rh - 20), math.min(36, rh - 20)), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card2 })
			K.corner(a, UDim.new(0.5, 0))
			x = 12 + math.min(36, rh - 20) + 12
		end
		local l1 = K.frame(row, { Name = "Line1", Position = UDim2.new(0, x, 0.5, -11), Size = UDim2.new(0.55, -x, 0, 9), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card2 })
		K.corner(l1, UDim.new(0.5, 0))
		local l2 = K.frame(row, { Name = "Line2", Position = UDim2.new(0, x, 0.5, 4), Size = UDim2.new(0.35, -x * 0.5, 0, 8), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card2 })
		K.corner(l2, UDim.new(0.5, 0))
		local shimmer = K.frame(row, { Name = "Shimmer", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.92, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2 })
		K.corner(shimmer, K.Radius.sm)
		local g = K.gradient(shimmer, { Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }))
		g.Offset = Vector2.new(-1, 0)
		table.insert(grads, g)
	end
	if not K.reduced() then
		task.spawn(function()
			while f.Parent do
				if K.shownInTree(f) then
					for _, g in grads do
						g.Offset = Vector2.new(-1, 0)
						K.tween(g, 1.1, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
					end
				end
				task.wait(1.4)
			end
		end)
	end
	f.Parent = parent
	return f
end

---------------------------------------------------------------------------------------------------
-- Overlay helpers
---------------------------------------------------------------------------------------------------
-- Disables every button / text box under `root` (except under `keep`) while an overlay covers it;
-- returns a restore function. (The overlay's input-sinking dim blocks them anyway; this also keeps
-- keyboard / gamepad selection off hidden controls.)
function K.shield(root: Instance?, keep: Instance?): () -> ()
	local changed: { GuiObject } = {}
	local conn: RBXScriptConnection? = nil
	local function consider(d: Instance)
		if (d:IsA("GuiButton") or d:IsA("TextBox")) and d.Active and not (keep and d:IsDescendantOf(keep)) then
			d.Active = false
			table.insert(changed, d)
		end
	end
	if root then
		for _, d in root:GetDescendants() do
			consider(d)
		end
		-- a screen that re-renders under the overlay (new rows arriving) stays shielded too; the
		-- overlay's own controls are created before the shield or live under `keep`
		conn = root.DescendantAdded:Connect(function(d: Instance)
			task.defer(function()
				if conn and d.Parent then
					consider(d)
				end
			end)
		end)
	end
	return function()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		for _, d in changed do
			if d.Parent then
				d.Active = true
			end
		end
		table.clear(changed)
	end
end

-- A full-cover, input-sinking dim (a Frame, not a button, so it is not a tap target itself);
-- onTap fires on a tap / click on the dim.
function K.dim(host: Instance, name: string, z: number, onTap: (() -> ())?): Frame
	local d = K.frame(host, { Name = name, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Active = true, ZIndex = z })
	if onTap then
		d.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				onTap()
			end
		end)
	end
	return d
end

---------------------------------------------------------------------------------------------------
-- Modal / confirm
---------------------------------------------------------------------------------------------------
-- host: ScreenGui or any GuiObject (the dim covers it). opts {title, body?, icon?, iconColor?,
-- details? = {{label, value, color?}}, buttons = {{text, style, onClick}}, dismissible?, width?}
function K.Modal(host: Instance, opts: { [string]: any }): any
	local z = opts.zIndex or 60
	local api = { panel = nil :: any, closed = false }
	local dim = K.dim(host, "ModalDim", z, function()
		if opts.dismissible ~= false then
			api.close()
			if opts.onDismiss then
				task.spawn(opts.onDismiss)
			end
		end
	end)
	local restore = K.shield(opts.shield or host, dim)
	local hostW = 320
	if host:IsA("GuiObject") and host.AbsoluteSize.X > 0 then
		hostW = host.AbsoluteSize.X
	elseif host:IsA("LayerCollector") and (host :: any).AbsoluteSize.X > 0 then
		hostW = (host :: any).AbsoluteSize.X
	end
	local hostH = 600
	if host:IsA("GuiObject") and host.AbsoluteSize.Y > 0 then
		hostH = host.AbsoluteSize.Y
	elseif host:IsA("LayerCollector") and (host :: any).AbsoluteSize.Y > 0 then
		hostH = (host :: any).AbsoluteSize.Y
	end
	local compact = hostH < 380
	local width = math.min(opts.width or 320, hostW - 24)
	local panel = K.Panel(dim, { Name = "Modal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(width, 10), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = z + 1, BackgroundTransparency = 0, Radius = K.Radius.xl })
	K.pad(panel, 16, 16, if compact then 14 else 16, if compact then 12 else 14)
	K.list(panel, false, if compact then 8 else 10, Enum.HorizontalAlignment.Center)
	if opts.icon and not compact then
		local ic = K.iconTile(panel, 44, opts.icon, opts.iconColor or CYAN, true)
		ic.LayoutOrder = 0
		for _, d in ic:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = z + 3
			end
		end
		ic.ZIndex = z + 2
	end
	K.text(panel, { Name = "Title", Size = UDim2.new(1, 0, 0, K.textHeight(opts.title or "", K.Type.title2, width - 32) + 2), Text = opts.title or "", Font = K.Font.bold, TextSize = K.Type.title2, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 2, LayoutOrder = 1 })
	if opts.body then
		K.text(panel, { Name = "Body", Size = UDim2.new(1, 0, 0, K.textHeight(opts.body, K.Type.bodySm - 1, width - 32) + 2), Text = opts.body, TextColor3 = K.Color.sub, TextWrapped = true, TextSize = K.Type.bodySm - 1, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 2, LayoutOrder = 2 })
	end
	if opts.details and #opts.details > 0 then
		local box = K.frame(panel, { Name = "Details", Size = UDim2.new(1, 0, 0, #opts.details * (if compact then 21 else 24) + (if compact then 8 else 12)), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card, LayoutOrder = 3, ZIndex = z + 2 })
		K.corner(box, K.Radius.sm)
		K.pad(box, 12, 12, if compact then 4 else 6, if compact then 4 else 6)
		K.list(box, false, 0)
		for i, d in opts.details do
			local r = K.frame(box, { Name = "Detail" .. i, Size = UDim2.new(1, 0, 0, if compact then 21 else 24), LayoutOrder = i, ZIndex = z + 2 })
			K.text(r, { Name = "Label", Size = UDim2.new(0.45, 0, 1, 0), Text = tostring(d[1] or d.label or ""), TextColor3 = K.Color.sub, TextSize = K.Type.caption, ZIndex = z + 3 })
			local v = K.text(r, { Name = "Value", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.55, 0, 1, 0), Text = tostring(d[2] or d.value or ""), TextColor3 = d[3] or d.color or K.Color.text, Font = K.Font.bold, TextSize = K.Type.caption + 1, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = z + 3 })
			K.mono(v)
		end
	end
	local row = K.frame(panel, { Name = "Buttons", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 4, ZIndex = z + 2 })
	api.panel = panel
	function api.close()
		if api.closed then
			return
		end
		api.closed = true
		restore()
		K.tween(dim, 0.16, { BackgroundTransparency = 1 })
		-- exit: the card sinks back while the dim fades (it stays visible for those 0.16 s; the
		-- api.closed guard keeps its buttons from firing twice)
		local sc = scaleOf(panel)
		K.cancel(sc)
		if K.reduced() then
			panel.Visible = false
		else
			K.tween(sc, 0.16, { Scale = 0.92 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		end
		task.delay(0.17, function()
			if dim.Parent then
				dim:Destroy()
			end
		end)
	end
	local btns = opts.buttons or { { text = "확인", style = "primary" } }
	local n = #btns
	for i, bd in btns do
		local b = K.Button(row, {
			name = "Button" .. i,
			text = bd.text,
			style = bd.style or (if i == n then "primary" else "secondary"),
			size = UDim2.new(1 / n, if n > 1 then -4 else 0, 1, 0),
			position = UDim2.new((i - 1) / n, if i > 1 then 4 else 0, 0, 0),
			zIndex = z + 3,
		})
		b.Activated:Connect(function()
			if api.closed then
				return
			end
			api.close()
			if bd.onClick then
				task.spawn(bd.onClick)
			end
		end)
	end
	K.tween(dim, 0.22, { BackgroundTransparency = 0.45 })
	K.springIn(panel, 0.88, { amount = 0.3, duration = 0.42 })
	K.feedback("open")
	return api
end

-- Confirm dialog. opts {title, body?, icon?, iconColor?, details?, confirmText?, cancelText?,
-- destructive?, style?, onConfirm, onCancel?}
function K.confirm(host: Instance, opts: { [string]: any }): any
	return K.Modal(host, {
		title = opts.title,
		body = opts.body,
		icon = opts.icon,
		iconColor = opts.iconColor,
		details = opts.details,
		width = opts.width,
		zIndex = opts.zIndex,
		shield = opts.shield,
		onDismiss = opts.onCancel,
		buttons = {
			{ text = opts.cancelText or "취소", style = "secondary", onClick = opts.onCancel },
			{ text = opts.confirmText or "확인", style = opts.style or (if opts.destructive then "destructive" else "primary"), onClick = opts.onConfirm },
		},
	})
end

---------------------------------------------------------------------------------------------------
-- Bottom sheet (drag to close)
---------------------------------------------------------------------------------------------------
-- host: GuiObject / ScreenGui the sheet lives in. opts {title, subtitle?, height? (px, default 60 %
-- of the host), side = "bottom"|"right", width? (right side), dim? (default true), onClose?, zIndex?}
-- -> {frame, content, open(), close(), isOpen(), setTitle(title, subtitle?)}
function K.BottomSheet(host: Instance, opts: { [string]: any }): any
	local z = opts.zIndex or 40
	local side = opts.side or "bottom"
	local closeFn: () -> () = function() end
	local dim = K.dim(host, (opts.name or "Sheet") .. "Dim", z, function()
		closeFn()
	end)
	dim.Visible = false
	if opts.dim == false then
		dim.Size = UDim2.fromScale(0, 0)
	end
	local restore: (() -> ())? = nil
	-- opaque: GUI behind a GUI is never blurred, so a see-through sheet would show the app through it
	local panel = K.Panel(host, { Name = opts.name or "Sheet", ZIndex = z + 1, Visible = false, BackgroundTransparency = 0, Radius = K.Radius.xl })
	panel.BackgroundColor3 = K.Color.glass2
	-- a Frame (Active, receives InputBegan) rather than a button: it is a drag surface, not a tap target
	local handle = make("Frame", { Name = "Grabber", BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, ZIndex = z + 3 }, panel)
	local grip = K.frame(handle, { Name = "Grip", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 0.55, BackgroundColor3 = K.Color.text, ZIndex = z + 3 })
	K.corner(grip, UDim.new(0.5, 0))
	local title = K.text(panel, { Name = "Title", Text = opts.title or "", Font = K.Font.bold, TextSize = K.Type.title2, ZIndex = z + 2, TextTruncate = Enum.TextTruncate.AtEnd })
	local subtitle = K.text(panel, { Name = "Subtitle", Text = opts.subtitle or "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, ZIndex = z + 2, TextTruncate = Enum.TextTruncate.AtEnd })
	local close = K.Button(panel, { name = "Close", style = "icon", icon = "✕", zIndex = z + 3, textSize = 14 })
	close.AnchorPoint = Vector2.new(1, 0)
	local content = K.frame(panel, { Name = "Content", ZIndex = z + 2 })
	local api = { frame = panel, content = content, open_ = false, dim = dim }
	local restPos = UDim2.new()

	local function layout()
		local hasSub = subtitle.Text ~= ""
		local headH = if hasSub then 64 else 52
		if side == "right" then
			local w = opts.width or 0.42
			panel.AnchorPoint = Vector2.new(1, 0)
			restPos = UDim2.new(1, -6, 0, 6)
			panel.Size = if type(w) == "number" and w <= 1 then UDim2.new(w, 0, 1, -12) else UDim2.new(0, w, 1, -12)
			handle.Position = UDim2.fromOffset(0, 0)
			handle.Size = UDim2.new(0, 18, 1, 0)
			grip.Size = UDim2.fromOffset(4, 36)
			title.Position = UDim2.fromOffset(20, 12)
		else
			local h = opts.height or 0.6
			panel.AnchorPoint = Vector2.new(0.5, 1)
			restPos = UDim2.new(0.5, 0, 1, 0)
			panel.Size = if type(h) == "number" and h <= 1 then UDim2.new(1, 0, h, 0) else UDim2.new(1, 0, 0, h)
			handle.Position = UDim2.fromOffset(0, 0)
			handle.Size = UDim2.new(1, 0, 0, 22)
			grip.Size = UDim2.fromOffset(36, 4)
			title.Position = UDim2.fromOffset(16, 18)
		end
		title.Size = UDim2.new(1, -76, 0, 24)
		subtitle.Position = UDim2.fromOffset(title.Position.X.Offset, title.Position.Y.Offset + 24)
		subtitle.Size = UDim2.new(1, -76, 0, 16)
		subtitle.Visible = hasSub
		close.Position = UDim2.new(1, -8, 0, 8)
		local left = if side == "right" then 18 else 12
		content.Position = UDim2.fromOffset(left, headH)
		content.Size = UDim2.new(1, -(left + 12), 1, -(headH + 10))
		if not api.open_ then
			panel.Position = restPos
		end
	end
	local function offscreen(): UDim2
		if side == "right" then
			return restPos + UDim2.new(0, math.max(200, panel.AbsoluteSize.X + 20), 0, 0)
		end
		return restPos + UDim2.new(0, 0, 0, math.max(200, panel.AbsoluteSize.Y + 20))
	end
	function api.setTitle(t: string, sub: string?)
		title.Text = t
		subtitle.Text = sub or ""
		layout()
	end
	function api.isOpen(): boolean
		return api.open_
	end
	function api.open()
		layout()
		if api.open_ then
			return
		end
		api.open_ = true
		dim.Visible = opts.dim ~= false
		if opts.shield then
			restore = K.shield(opts.shield, panel)
		end
		panel.Visible = true
		panel.Position = offscreen()
		K.spring(panel, { Position = restPos }, { duration = 0.46, amount = 0.035 })
		K.tween(dim, 0.25, { BackgroundTransparency = 0.5 })
		K.feedback("open")
	end
	function api.close(silent: boolean?)
		if not api.open_ then
			return
		end
		api.open_ = false
		if restore then
			restore()
			restore = nil
		end
		K.cancel(panel)
		K.tween(panel, 0.22, { Position = offscreen() }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		K.tween(dim, 0.2, { BackgroundTransparency = 1 })
		task.delay(0.23, function()
			if not api.open_ then
				panel.Visible = false
				dim.Visible = false
				panel.Position = restPos
			end
		end)
		if not silent then
			K.sound("close")
		end
		if opts.onClose then
			task.spawn(opts.onClose)
		end
	end
	function api.relayout()
		layout()
	end
	close.Activated:Connect(function()
		api.close()
	end)
	closeFn = function()
		api.close()
	end
	-- drag to close (handle / title area): past 30 % of the sheet or a fast flick
	local dragging: InputObject? = nil
	local startP = Vector2.zero
	local startT = 0
	local function delta(p: Vector3): number
		if side == "right" then
			return math.max(0, p.X - startP.X)
		end
		return math.max(0, p.Y - startP.Y)
	end
	handle.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) and api.open_ then
			dragging = input
			K.cancel(panel)
			startP = Vector2.new(input.Position.X, input.Position.Y)
			startT = os.clock()
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local d = dragging
		if not d or not api.open_ then
			return
		end
		if input == d or (input.UserInputType == Enum.UserInputType.MouseMovement and d.UserInputType == Enum.UserInputType.MouseButton1) then
			local dd = delta(input.Position)
			panel.Position = if side == "right" then restPos + UDim2.fromOffset(dd, 0) else restPos + UDim2.fromOffset(0, dd)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local d = dragging
		if d and (input == d or input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = nil
			local dd = delta(input.Position)
			local size = if side == "right" then panel.AbsoluteSize.X else panel.AbsoluteSize.Y
			local speed = dd / math.max(0.05, os.clock() - startT)
			if dd > size * 0.3 or (dd > 24 and speed > 900) then
				api.close()
			else
				-- snap back with a little bounce
				K.spring(panel, { Position = restPos }, { duration = 0.34, amount = 0.08 })
			end
		end
	end)
	layout()
	return api
end

---------------------------------------------------------------------------------------------------
-- Toaster: iOS-style stack under the top bar (newest in front, up to 2 older cards peeking behind),
-- slides in from the top, tap -> onClick, swipe up -> dismiss. Place it in the Layout "toasts" slot.
---------------------------------------------------------------------------------------------------
function K.Toaster(gui: Instance): any
	local holder = K.frame(gui, { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(340, 64), ZIndex = 40 })
	local api = { holder = holder, count = 0, cardH = 52, gap = 5, active = {} :: { any } }
	local peek = 5
	local drag: any = nil
	local remove: (t: any) -> ()

	function api.place(x: number, y: number, w: number, h: number?)
		holder.AnchorPoint = Vector2.new(0, 0)
		holder.Position = UDim2.fromOffset(x, y)
		holder.Size = UDim2.fromOffset(w, h or (api.cardH + 2 * peek))
	end
	-- rect = {x, y, w, h} (e.g. Layout.rect("toasts")), cardH optional
	function api.placeRect(r: { [string]: number }, cardH: number?)
		api.cardH = cardH or api.cardH
		api.place(r.x, r.y, r.w, r.h)
	end
	function api.setTop(y: number)
		holder.Position = UDim2.new(holder.Position.X.Scale, holder.Position.X.Offset, 0, y)
	end

	local function reflow()
		for i, t in api.active do
			local depth = i - 1
			local visible = depth <= 2
			t.card.Visible = visible
			if visible then
				t.card.ZIndex = 50 - depth * 3
				for _, d in t.card:GetDescendants() do
					if d:IsA("GuiObject") then
						d.ZIndex = t.card.ZIndex + (d:GetAttribute("Zo") or 1)
					end
				end
				local goal = { Position = UDim2.new(0.5, 0, 0, depth * peek), Size = UDim2.new(1 - depth * 0.06, 0, 0, api.cardH), BackgroundTransparency = if depth == 0 then 0.04 else 0.02 }
				if t.fresh then
					-- a new banner drops in from above with a soft overshoot
					t.fresh = false
					K.spring(t.card, goal, { duration = 0.5, amount = 0.14 })
				elseif not t.dragging then
					K.cancel(t.card)
					K.tween(t.card, 0.26, goal)
				end
				t.content.Visible = depth == 0
				t.hit.Visible = depth == 0
			end
		end
	end

	UserInputService.InputChanged:Connect(function(input: InputObject)
		local d = drag
		if not d or d.entry.dead then
			return
		end
		if input == d.input or (input.UserInputType == Enum.UserInputType.MouseMovement and d.input.UserInputType == Enum.UserInputType.MouseButton1) then
			local dy = input.Position.Y - d.startY
			d.moved = dy
			local y = if dy < 0 then dy else dy * 0.25
			d.entry.card.Position = UDim2.new(0.5, 0, 0, math.floor(y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local d = drag
		if not d or not (input == d.input or input.UserInputType == Enum.UserInputType.MouseButton1) then
			return
		end
		drag = nil
		local e = d.entry
		e.dragging = false
		if e.dead then
			return
		end
		if d.moved < -18 then
			e.swiped = true
			remove(e)
		else
			K.spring(e.card, { Position = UDim2.new(0.5, 0, 0, 0) }, { duration = 0.34, amount = if math.abs(d.moved) > 2 then 0.1 else 0 })
		end
	end)

	function remove(t: any)
		local idx = table.find(api.active, t)
		if not idx then
			return
		end
		table.remove(api.active, idx)
		t.dead = true
		K.cancel(t.card)
		K.tween(t.card, 0.2, { Position = UDim2.new(0.5, 0, 0, -api.cardH - 12) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.21, function()
			t.card:Destroy()
		end)
		reflow()
	end

	-- t = {kind, title, body, icon?, onClick?, duration?, silent?}
	function api.push(t: { [string]: any })
		api.count += 1
		local kind = K.Kinds[t.kind or "info"] or K.Kinds.info
		local color = t.color or kind.color
		local card = K.frame(holder, { Name = "Toast", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -api.cardH - 12), Size = UDim2.new(1, 0, 0, api.cardH), BackgroundTransparency = 0.04, BackgroundColor3 = K.Color.glass2, ZIndex = 50 })
		K.corner(card, K.Radius.md)
		K.stroke(card, color, 1, 0.55)
		local content = K.frame(card, { Name = "Content", Size = UDim2.fromScale(1, 1) })
		content:SetAttribute("Zo", 1)
		local iconS = math.min(34, api.cardH - 16)
		local icon = K.iconTile(content, iconS, t.icon or kind.icon, color, true)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 10, 0.5, 0)
		local tx = 10 + iconS + 10
		local hasBody = t.body ~= nil and t.body ~= ""
		K.text(content, { Name = "Title", Position = UDim2.new(0, tx, 0.5, if hasBody then -17 else -10), Size = UDim2.new(1, -(tx + 10), 0, 18), Text = t.title or "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd })
		if hasBody then
			K.text(content, { Name = "Body", Position = UDim2.new(0, tx, 0.5, 2), Size = UDim2.new(1, -(tx + 10), 0, 16), Text = t.body, TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextTruncate = Enum.TextTruncate.AtEnd })
		end
		local hit = make("TextButton", { Name = "Hit", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 55 }, card)
		hit:SetAttribute("Zo", 5)
		local entry = { card = card, content = content, hit = hit, dead = false, fresh = true, dragging = false }
		table.insert(api.active, 1, entry)
		while #api.active > 3 do
			remove(api.active[#api.active])
		end
		reflow()
		if not t.silent then
			K.feedback(if t.kind == "money" or t.kind == "pay" then "money" else "notify")
		end
		-- the banner follows the finger (up freely, down with rubber-band resistance); released past
		-- 18 px up it flies away, otherwise it springs back. Tap opens.
		hit.InputBegan:Connect(function(input: InputObject)
			if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) and not entry.dead then
				drag = { entry = entry, input = input, startY = input.Position.Y, moved = 0 }
				entry.dragging = true
				K.cancel(card)
			end
		end)
		hit.Activated:Connect(function()
			if entry.dead or entry.swiped then
				return
			end
			K.feedback("tap")
			if t.onClick then
				task.spawn(t.onClick)
			end
			remove(entry)
		end)
		task.delay(t.duration or 4, function()
			remove(entry)
		end)
		return entry
	end
	function api.clear()
		for i = #api.active, 1, -1 do
			remove(api.active[i])
		end
	end
	return api
end

-- Global toast route: one Toaster (the phone's HUD layer) serves every client script.
local globalToaster: any = nil
local toastQueue: { any } = {}
function K.setToaster(t: any)
	globalToaster = t
	for _, q in toastQueue do
		pcall(t.push, q)
	end
	table.clear(toastQueue)
end
function K.toast(data: { [string]: any })
	if type(data) ~= "table" then
		return
	end
	if K.settings.notifications == false and not data.force then
		if not data.silent then
			K.sound("notify")
		end
		return
	end
	if globalToaster then
		pcall(globalToaster.push, data)
	else
		table.insert(toastQueue, data)
		while #toastQueue > 3 do
			table.remove(toastQueue, 1)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- NPC dialog: portrait circle + name / role + typewriter text (tap to skip) + choice buttons +
-- optional timer ring. Place it with dialog.place(rect) (Layout "dialog" slot).
---------------------------------------------------------------------------------------------------
function K.DialogBox(gui: Instance): any
	local WHITE = Color3.new(1, 1, 1)
	local panel = K.Panel(gui, { Name = "NpcDialog", AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(420, 180), Visible = false, ZIndex = 20, BackgroundTransparency = 0.04, Radius = K.Radius.xl })
	panel.BackgroundColor3 = K.Color.glass2
	local panelScale = scaleOf(panel)
	local shadowHolder = K.shadow(panel, K.Radius.xl, 10, "strong")
	-- a faint vertical wash so the glass reads lit from above
	local wash = K.frame(panel, { Name = "Wash", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.94, BackgroundColor3 = WHITE, ZIndex = 20 })
	K.corner(wash, K.Radius.xl)
	K.gradient(wash, { WHITE, WHITE }, 90, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1) }))
	-- Gwangan-bridge accent line along the top edge; its light sweeps across on every new line
	local accentBar = K.frame(panel, { Name = "Accent", Position = UDim2.new(0, 18, 0, 0), Size = UDim2.new(1, -36, 0, 2), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 21 })
	K.corner(accentBar, UDim.new(0.5, 0))
	local accentGrad = K.gradient(accentBar, K.Grad.bridge, 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.05), NumberSequenceKeypoint.new(0.8, 0.05), NumberSequenceKeypoint.new(1, 1) }))
	-- portrait: gradient disc + glyph, circled by a slowly turning light ring while the NPC talks
	local ringHolder = K.frame(panel, { Name = "PortraitRing", Position = UDim2.fromOffset(12, 11), Size = UDim2.fromOffset(46, 46), ZIndex = 21 })
	K.corner(ringHolder, UDim.new(0.5, 0))
	local ringStroke = K.stroke(ringHolder, WHITE, 2, 0)
	local ringGrad = K.gradient(ringStroke, { CYAN, MAGENTA, GOLD }, 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0.15), NumberSequenceKeypoint.new(0.75, 0.9), NumberSequenceKeypoint.new(1, 0) }))
	local portrait = K.frame(panel, { Name = "Portrait", Position = UDim2.fromOffset(16, 15), Size = UDim2.fromOffset(38, 38), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 21 })
	K.corner(portrait, UDim.new(0.5, 0))
	local pGrad = K.gradient(portrait, { CYAN, VIOLET }, 125)
	local glyph = K.text(portrait, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "🙂", TextSize = 20, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
	local name = K.text(panel, { Name = "Name", Position = UDim2.fromOffset(68, 13), Size = UDim2.new(1, -176, 0, 22), Text = "", Font = K.Font.bold, TextSize = K.Type.body + 1, ZIndex = 21, TextTruncate = Enum.TextTruncate.AtEnd })
	local role = K.text(panel, { Name = "Role", Position = UDim2.fromOffset(68, 35), Size = UDim2.new(1, -176, 0, 16), Text = "", TextColor3 = GOLD, Font = K.Font.bold, TextSize = K.Type.caption, ZIndex = 21, TextTruncate = Enum.TextTruncate.AtEnd })
	local textScroll = make("ScrollingFrame", { Name = "TextScroll", Position = UDim2.fromOffset(16, 64), Size = UDim2.new(1, -32, 0, 44), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 2, ScrollBarImageColor3 = K.Color.sub, ZIndex = 21 }, panel)
	local body = K.text(textScroll, { Name = "Text", Size = UDim2.new(1, -4, 0, 0), Text = "", TextColor3 = K.Color.text, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextSize = K.Type.bodySm, LineHeight = 1.1, ZIndex = 21 })
	local skipHint = K.text(panel, { Name = "SkipHint", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 0, 62), Size = UDim2.fromOffset(96, 14), Text = "", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 21 })
	local close = K.Button(panel, { name = "Close", style = "icon", icon = "✕", anchor = Vector2.new(1, 0), position = UDim2.new(1, -10, 0, 10), zIndex = 22, textSize = 14 })
	local ring = K.Ring(panel, { name = "Timer", size = 36, thickness = 3, color = GOLD })
	ring.frame.AnchorPoint = Vector2.new(1, 0)
	ring.frame.Position = UDim2.new(1, -62, 0, 14)
	ring.frame.ZIndex = 21
	for _, d in ring.frame:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 22
		end
	end
	ring.frame.Visible = false
	local choices = K.frame(panel, { Name = "Choices", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.new(1, -28, 0, 44), ZIndex = 21 })

	local api = { panel = panel, visible = false, serial = 0, onChoice = nil :: any, onClose = nil :: any, onHidden = nil :: any, cols = 3 }
	local rect = { x = 8, y = 8, w = 420, h = 180 }
	local anchorBottom = false
	local fullText = ""
	local lastChoices: { any } = {}
	local active: { TextButton } = {} -- buttons showing the current choices, in order
	local pool: { [string]: { TextButton } } = {} -- style -> reusable buttons
	local choiceOf: { [TextButton]: any } = {}
	local skipTyping = false
	local typing = false
	local timerSerial = 0
	local ringSerial = 0
	local restPos = panel.Position

	-- Content layout inside the current rect: header (portrait / name / role, 58), text (scrolls when
	-- long), choice grid at the bottom. Columns: as many as fit the longest label (max 3).
	local function arrange()
		local w = rect.w
		local n = #lastChoices
		local gap = 8
		local longest = 0
		for _, ch in lastChoices do
			longest = math.max(longest, K.textWidth(tostring(ch.label or ch.text or ""), K.Type.bodySm - 1))
		end
		local cols = 1
		for c = math.min(n, 3), 1, -1 do
			local cw = (w - 28 - gap * (c - 1)) / c
			if longest + 22 <= cw then
				cols = c
				break
			end
		end
		if n == 4 and cols == 3 then
			cols = 2
		end
		local rows = math.max(1, math.ceil(n / cols))
		local cw = math.floor((w - 28 - gap * (cols - 1)) / cols)
		local gridH = rows * 44 + (rows - 1) * gap
		local textW = w - 32
		local want = math.clamp(K.textHeight(fullText, K.Type.bodySm, textW - 6) + 4, 20, 100)
		local fixed = 64 + 10 + gridH + 14
		local h = math.min(fixed + want, math.max(rect.h, fixed + 36))
		local th = math.max(18, h - fixed)
		panel.Size = UDim2.fromOffset(w, h)
		if anchorBottom then
			panel.AnchorPoint = Vector2.new(0, 1)
			restPos = UDim2.fromOffset(rect.x, rect.y + rect.h)
		else
			panel.AnchorPoint = Vector2.new(0, 0)
			restPos = UDim2.fromOffset(rect.x, rect.y)
		end
		panel.Position = restPos
		textScroll.Size = UDim2.new(1, -32, 0, th)
		body.Size = UDim2.new(1, -4, 0, math.max(th, K.textHeight(fullText, K.Type.bodySm, textW - 6) + 4))
		choices.Size = UDim2.new(1, -28, 0, gridH)
		for i, b in active do
			local idx = i - 1
			local cx, cy = idx % cols, idx // cols
			b.Position = UDim2.fromOffset(cx * (cw + gap) + cw / 2, cy * (44 + gap) + 22)
			b.Size = UDim2.fromOffset(cw, 44)
		end
	end

	-- rect {x, y, w, h} in the gui's px; bottom = true anchors the panel to the rect's bottom edge
	function api.place(r: { [string]: number }, bottom: boolean?)
		rect = { x = r.x, y = r.y, w = r.w, h = r.h }
		anchorBottom = bottom == true
		api.cols = if r.w >= 420 then 3 elseif r.w >= 300 then 2 else 1
		arrange()
	end

	-- legacy: mode "phone" | "tablet" | "pc"; W,H gui area; jump = {x,y,w,h}
	function api.layout(mode: string, W: number, H: number, jump: { number }?)
		if mode == "pc" or mode == "tablet" then
			local w = math.min(620, W - 32)
			api.place({ x = (W - w) / 2, y = H - 24 - 200, w = w, h = 200 }, true)
		else
			local right = W - 8
			if jump then
				right = math.min(right, jump[1] - 10)
			end
			local w = math.min(640, math.max(280, right - 8))
			api.place({ x = 8, y = 8, w = w, h = H - 16 }, true)
		end
	end

	local function takeButton(styleName: string): TextButton
		local list = pool[styleName]
		if list then
			for _, b in list do
				if not b.Visible then
					return b
				end
			end
		else
			list = {}
			pool[styleName] = list
		end
		local b = K.Button(choices, {
			name = "Choice",
			text = "",
			style = styleName,
			anchor = Vector2.new(0.5, 0.5),
			size = UDim2.fromOffset(120, 44),
			zIndex = 22,
			textSize = K.Type.bodySm - 1,
		})
		b.Visible = false
		b.Activated:Connect(function()
			local ch = choiceOf[b]
			if ch and b.Visible and api.onChoice then
				task.spawn(api.onChoice, ch.id, ch)
			end
		end)
		table.insert(list :: { TextButton }, b)
		return b
	end

	local function setChoices(list: { any })
		lastChoices = list
		for _, b in active do
			b.Visible = false
			choiceOf[b] = nil
		end
		table.clear(active)
		for i, ch in list do
			local b = takeButton(ch.style or (if i == 1 then "primary" else "secondary"))
			b.Name = "Choice" .. i
			b.Text = tostring(ch.label or ch.text or "…")
			b:SetAttribute("Index", i)
			choiceOf[b] = ch
			table.insert(active, b)
		end
		arrange()
	end

	-- choices pop in one after another (45 ms apart) once the line has been read
	local function revealChoices(animate: boolean)
		for i, b in active do
			b.Visible = true
			local s = scaleOf(b)
			if animate and not K.reduced() then
				s.Scale = 0.72
				K.spring(s, { Scale = 1 }, { duration = 0.38, amount = 0.3, delay = (i - 1) * 0.045 })
			else
				K.cancel(s)
				s.Scale = 1
			end
		end
	end

	local function colorOf(pc: any): Color3
		if typeof(pc) == "Color3" then
			return pc
		elseif type(pc) == "table" and tonumber(pc[1]) then
			return Color3.fromRGB(tonumber(pc[1]) or 88, tonumber(pc[2]) or 130, tonumber(pc[3]) or 255)
		end
		return CYAN
	end

	-- the portrait ring turns while the NPC is talking (one tween per turn; none on reduced motion)
	local function spinRing(on: boolean)
		ringSerial += 1
		local mine = ringSerial
		if not on or K.reduced() then
			ringStroke.Transparency = if on then 0.2 else 0.55
			return
		end
		ringStroke.Transparency = 0
		task.spawn(function()
			while ringSerial == mine and api.visible do
				ringGrad.Rotation = 0
				K.tweenD(ringGrad, 1.6, { Rotation = 360 }, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
				task.wait(1.6)
			end
		end)
	end

	-- timer {total, left?} seconds: the ring counts down (gold -> red in the last 25 %)
	function api.setTimer(timer: any)
		timerSerial += 1
		local mine = timerSerial
		local total = type(timer) == "table" and tonumber(timer.total) or nil
		if not total or total <= 0 then
			ring.frame.Visible = false
			return
		end
		local left0 = tonumber(timer.left) or total
		local t0 = os.clock()
		ring.frame.Visible = true
		task.spawn(function()
			while timerSerial == mine and api.visible do
				local left = math.max(0, left0 - (os.clock() - t0))
				ring.set(left / total)
				ring.label.Text = tostring(math.ceil(left))
				ring.setColor(if left / total < 0.25 then RED else GOLD)
				if left <= 0 then
					break
				end
				task.wait(0.1)
			end
		end)
	end

	-- data = {npcId, name, role, portraitColor ({r,g,b} | Color3), portrait/icon?, text, choices,
	--         timer? = {total, left?}}
	function api.show(data: { [string]: any })
		api.serial += 1
		local mine = api.serial
		local wasVisible = api.visible
		api.visible = true
		name.Text = tostring(data.name or "")
		role.Text = tostring(data.role or "")
		local col = colorOf(data.portraitColor)
		pGrad.Color = ColorSequence.new(shade(col, -0.08, 0.14), shade(col, 0.1, -0.25))
		local g = data.icon or data.portrait
		glyph.Text = if type(g) == "string" and g ~= "" then g else utf8.char(utf8.codepoint(tostring(data.name or "?") .. " ", 1))
		fullText = tostring(data.text or "")
		local list = if type(data.choices) == "table" then data.choices else {}
		if #list == 0 then
			list = { { id = "close", label = "닫기", style = "secondary" } }
		end
		ring.frame.Position = UDim2.new(1, -62, 0, 14)
		skipTyping = false
		body.Text = fullText
		textScroll.CanvasPosition = Vector2.zero
		setChoices(list) -- also arranges the panel for the new text
		api.setTimer(data.timer)
		local reduced = K.reduced()
		if not panel.Visible or not wasVisible then
			-- entrance: glide in from the side (phones) / from below (tablet, PC) with a spring settle
			panel.Visible = true
			local side = rect.w < 480
			panel.Position = restPos + UDim2.fromOffset(if side then 48 else 0, if side then 0 else 36)
			K.spring(panel, { Position = restPos }, { duration = 0.46, amount = 0.06 })
			panelScale.Scale = if reduced then 1 else 0.94
			if not reduced then
				K.spring(panelScale, { Scale = 1 }, { duration = 0.46, amount = 0.25 })
			end
			K.feedback("open")
		end
		-- name / role slide in, the accent light sweeps
		if not reduced then
			name.TextTransparency, role.TextTransparency = 1, 1
			K.tweenD(name, 0.28, { TextTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.06)
			K.tweenD(role, 0.28, { TextTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.12)
			accentGrad.Offset = Vector2.new(-0.6, 0)
			K.tweenD(accentGrad, 0.7, { Offset = Vector2.new(0, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		else
			name.TextTransparency, role.TextTransparency = 0, 0
		end
		-- typewriter by grapheme; tap anywhere on the panel to show everything
		for _, b in active do
			b.Visible = false
		end
		local total = utf8.len(fullText) or #fullText
		if reduced or total == 0 then
			body.MaxVisibleGraphemes = -1
			skipHint.Text = ""
			revealChoices(false)
			spinRing(false)
			return
		end
		body.MaxVisibleGraphemes = 0
		skipHint.Text = "탭하면 건너뛰기"
		typing = true
		spinRing(true)
		task.spawn(function()
			local shown = 0
			while api.serial == mine and shown < total and not skipTyping do
				shown += 2
				body.MaxVisibleGraphemes = shown
				task.wait(0.028)
			end
			if api.serial == mine then
				body.MaxVisibleGraphemes = -1
				skipHint.Text = ""
				typing = false
				spinRing(false)
				revealChoices(true)
			end
		end)
	end

	function api.hide()
		api.serial += 1
		timerSerial += 1
		ringSerial += 1
		local mine = api.serial
		local was = api.visible
		api.visible = false
		typing = false
		if was and panel.Visible and not K.reduced() then
			-- exit: a quick dip + fade of the scale (no rebuild; the same instances come back next time)
			K.cancel(panel)
			K.cancel(panelScale)
			local side = rect.w < 480
			K.tweenD(panel, 0.18, { Position = restPos + UDim2.fromOffset(if side then 36 else 0, if side then 0 else 24) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			K.tweenD(panelScale, 0.18, { Scale = 0.96 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.18, function()
				if api.serial == mine then
					panel.Visible = false
					panel.Position = restPos
					panelScale.Scale = 1
				end
			end)
		else
			panel.Visible = false
		end
		if was and api.onHidden then
			task.spawn(api.onHidden)
		end
	end

	panel.InputBegan:Connect(function(input: InputObject)
		if typing and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			skipTyping = true
		end
	end)
	close.Activated:Connect(function()
		if api.onClose then
			task.spawn(api.onClose)
		end
		api.hide()
	end)
	local _ = shadowHolder
	return api
end

---------------------------------------------------------------------------------------------------
-- Responsive helpers (legacy; new code uses K.Layout)
---------------------------------------------------------------------------------------------------
function K.deviceClass(W: number, H: number, touch: boolean): string
	if not touch then
		return "pc"
	end
	if math.min(W, H + 58) <= 500 then
		return "phone"
	end
	return "tablet"
end

function K.scaleFor(class: string, W: number, H: number): number
	if class == "pc" then
		return math.clamp(math.min(W / 1280, H / 662), 0.85, 1.3)
	elseif W >= H then
		return math.clamp(math.min(W / 740, H / 302), 1, 1.25)
	end
	return math.clamp(math.min(W / 360, H / 600), 1, 1.25)
end

return K
