-- GwangalliHUD (LocalScript, StarterPlayerScripts) — the walking HUD, built with the shared kit
-- (ReplicatedStorage.GwangalliUI) and placed through the screen slot contract
-- (ReplicatedStorage.GwangalliLayout, shared with the phone so nothing overlaps; a built-in fallback
-- with the same slots is used until / unless that module exists).
--
--   * "topCenter": clock / date / weather chip — game time, phase icon, Korean weekday and the game
--     date (derived from the server clock anchor, so every server agrees), a weather line, plus the
--     drone-show chip (inline when the slot is wide enough, else a small chip under it) and the
--     terrain-loading progress while the server fills terrain.
--   * "rightColumn": 이동 (quick travel) and 달리기 (sprint) — the 2nd and 3rd cells of the column
--     whose 1st cell holds the phone's 폰 button. Sprint is stamina aware: speed = RunSpeed +
--     the life game's RunSpeedBonus (Player attribute), slower when Stamina is nearly empty; the
--     button shows a stamina bar. PC: hold LeftShift (Shift Lock moves to Ctrl), gamepad L3 toggles.
--   * "sheetRight": the quick-travel sheet (key M / 이동): search, category chips
--     (전체 · 광장 · 해변 · 호텔 · 클럽 · 맛집 · 교통 · 내 직장 · 내 집) and big rows sorted by distance
--     with walking time; loading skeletons, empty and error states; drag the header to dismiss.
--     On touch the sheet is modal (character controls off, dim backdrop, the other HUD layers step
--     aside through the HideGwangalliHUD attribute); on PC it is a side panel.
--   * "toasts": HUD notifications through the kit Toaster (arrival, travel errors, stamina, drone show).
--
-- Other full-screen UIs (phone, bowling lane, photo mode) set HideGwangalliHUD = true on their enabled
-- ScreenGui: this HUD steps aside meanwhile. While the travel sheet is open this gui carries the same
-- attribute so the phone HUD / Now Playing widget step aside for it.
-- Build once, update on events: rows are created when the destination list changes; filtering only
-- toggles Visible / LayoutOrder; the clock loop writes a label only when its text changes.

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local configModule = ReplicatedStorage:WaitForChild("GwangalliConfig", 30)
local sharedModule = ReplicatedStorage:WaitForChild("GwangalliShared", 30)
local kitModule = ReplicatedStorage:WaitForChild("GwangalliUI", 30)
if not configModule or not sharedModule or not kitModule then
	warn("[GwangalliHUD] GwangalliConfig / GwangalliShared / GwangalliUI missing")
	return
end
local Config = require(configModule)
local Shared = require(sharedModule)
local okKit, K = pcall(require, kitModule)
if not okKit or type(K) ~= "table" then
	warn("[GwangalliHUD] GwangalliUI failed to load: " .. tostring(K))
	return
end
local A = Shared.Attr

local function optionalModule(name: string): any
	local m = ReplicatedStorage:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
	end
	return nil
end

-- Optional: quality tier (reduced motion on low, touch tie-breaker), the life-game data (job / home
-- places for 내 직장 / 내 집) and the slot contract (may be published after this script starts).
local Quality: any = optionalModule("GwangalliQuality")
local G: any = optionalModule("GwangalliGameplayShared")
local Layout: any = optionalModule("GwangalliLayout")

local playerGui = player:WaitForChild("PlayerGui", 30)
if not playerGui then
	warn("[GwangalliHUD] PlayerGui missing")
	return
end

local sprintCfg = Config.Sprint or {}
local hudCfg = Config.HUD or {}
local travelCfg = Config.Travel or {}
-- the server waits up to StreamTimeout for the destination to stream in before it answers
local TRAVEL_WAIT = (tonumber(travelCfg.StreamTimeout) or 8) + 3
local STUD_M = 0.3 -- true scale: 1 stud = 0.3 m

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
local isTouch = wantTouchLayout()

-- Motion policy. The quality tier is about 3D cost: every phone starts in "low" (reason "mobile"),
-- but UI tweens run in the engine and cost next to nothing, and the player asked for animation. So
-- motion is reduced only when the player asked for it (kit setting), chose a low graphics level, or
-- the frame rate itself demoted the tier. (docs/ui_kit_requests.md #1)
local motionCache, motionAt = false, -math.huge
local function reducedMotion(): boolean
	local now = os.clock()
	if now - motionAt < 1 then
		return motionCache
	end
	motionAt = now
	local r = false
	-- the kit's own policy once it has the fixed K.reduced (it ships with K.spring): one rule for
	-- every screen in the game
	if K and type(K.spring) == "function" and type(K.reduced) == "function" then
		local okK, red = pcall(K.reduced)
		if okK then
			motionCache = red == true
			return motionCache
		end
	end
	if type(K.settings) == "table" and K.settings.reducedMotion == true then
		r = true
	elseif Quality and type(Quality.isLow) == "function" then
		local okL, low = pcall(Quality.isLow)
		if okL and low == true then
			local why = ""
			if type(Quality.reason) == "function" then
				local okR, res = pcall(Quality.reason)
				why = if okR and type(res) == "string" then string.lower(res) else ""
			end
			r = string.find(why, "frame", 1, true) ~= nil or string.find(why, "slider", 1, true) ~= nil or string.find(why, "chosen", 1, true) ~= nil
		end
	end
	motionCache = r
	return r
end

---------------------------------------------------------------------------------------------------
-- Tokens / feedback
---------------------------------------------------------------------------------------------------
local C = K.Color
local CYAN = C.cyan or Color3.fromRGB(61, 214, 245)
local MAGENTA = C.magenta or Color3.fromRGB(255, 79, 163)
local GOLD = C.gold or Color3.fromRGB(255, 194, 71)
local GREEN = C.success or C.green or Color3.fromRGB(61, 220, 132)
local WARN = C.warning or C.orange or Color3.fromRGB(255, 176, 32)
local DANGER = C.danger or C.red or Color3.fromRGB(255, 90, 95)
local LIVE = Color3.fromRGB(255, 70, 90)
local F = K.Font
local FONT_NUM = F.mono or F.heavy or Enum.Font.BuilderSansExtraBold
local make = K.make
-- UI element handles live in one table (keeps the chunk under Luau's 200-local limit)
local U: { [string]: any } = {}

-- Tweens: TweenService directly (the kit's K.tween snaps on the "low" tier, see above); instant when
-- motion is reduced. Returns the Tween (or nil when applied instantly).
local function tw(inst: Instance, t: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween?
	if reducedMotion() or t <= 0 then
		for k, v in goals do
			pcall(function()
				(inst :: any)[k] = v
			end)
		end
		return nil
	end
	local ok, tween = pcall(function()
		local x = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goals)
		x:Play()
		return x
	end)
	if ok then
		return tween
	end
	for k, v in goals do
		pcall(function()
			(inst :: any)[k] = v
		end)
	end
	return nil
end

-- Two-stage "spring" (no real spring solver): Quint Out slightly past the target, then Sine back.
-- goalsPast / goals share keys. Cancels itself when a newer spring starts on the same instance.
local springSerial: { [Instance]: number } = {}
local function spring(inst: Instance, t: number, goalsPast: { [string]: any }, goals: { [string]: any })
	local n = (springSerial[inst] or 0) + 1
	springSerial[inst] = n
	if reducedMotion() then
		tw(inst, 0, goals)
		return
	end
	local first = tw(inst, t * 0.72, goalsPast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	if not first then
		tw(inst, 0, goals)
		return
	end
	first.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and springSerial[inst] == n then
			tw(inst, t * 0.45, goals, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	end)
end

-- click sound + haptic through the kit (K.feedback / K.sound / K.haptic) when it has them, else a
-- quiet built-in click
local clickSound: Sound? = nil
local function click()
	if type(K.feedback) == "function" then
		pcall(K.feedback, "tap")
		return
	end
	if type(K.sound) == "function" then
		pcall(K.sound, "tap")
		return
	end
	pcall(function()
		if not clickSound then
			local snd = Instance.new("Sound")
			snd.Name = "GwangalliHUDClick"
			snd.SoundId = "rbxasset://sounds/clickfast.wav"
			snd.Volume = 0.25
			snd.Parent = SoundService
			clickSound = snd
		end
		SoundService:PlayLocalSound(clickSound :: Sound)
	end)
end
local function haptic(kind: string?)
	if type(K.haptic) == "function" then
		pcall(K.haptic, kind or "tap")
	end
end
local function feedback(kind: string)
	if type(K.feedback) == "function" then
		pcall(K.feedback, kind)
	else
		haptic(kind)
	end
end

-- rendered width estimate (Hangul ~0.95 em, emoji ~1.25 em, ASCII ~0.56 em): used to size chips
local function textWidth(s: string, size: number): number
	local w = 0
	for _, cp in utf8.codes(s) do
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

-- press feedback for custom buttons: the kit's K.pressable (scale + veil + tap sound) when present,
-- else a 0.94 press scale + click (the kit's Button has its own)
local function pressable(b: GuiButton, scaleTo: number?, target: GuiObject?)
	local host: GuiObject = target or b
	local sc = host:FindFirstChild("Press") or make("UIScale", { Name = "Press", Scale = 1 }, host)
	local veil = K.frame(host, { Name = "PressVeil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = host.ZIndex + 6 })
	local bc = host:FindFirstChildOfClass("UICorner")
	local vc = K.corner(veil, if bc then bc.CornerRadius else UDim.new(0, 12))
	if bc then
		bc:GetPropertyChangedSignal("CornerRadius"):Connect(function()
			vc.CornerRadius = bc.CornerRadius
		end)
	end
	local held = false
	b.MouseButton1Down:Connect(function()
		held = true
		tw(sc, 0.08, { Scale = scaleTo or 0.94 }, Enum.EasingStyle.Quad)
		veil.BackgroundTransparency = 0.9
	end)
	local function up()
		if not held then
			return
		end
		held = false
		-- release with a little overshoot
		spring(sc, 0.3, { Scale = 1.03 }, { Scale = 1 })
		tw(veil, 0.22, { BackgroundTransparency = 1 })
	end
	b.MouseButton1Up:Connect(up)
	b.MouseLeave:Connect(up)
	b.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			up()
		end
	end)
	b.Activated:Connect(click)
end
local KIT_BUTTON_SOUNDS = type(K.pressable) == "function" -- the new kit's Button plays its own tap

---------------------------------------------------------------------------------------------------
-- ScreenGui
---------------------------------------------------------------------------------------------------
local old = playerGui:FindFirstChild("GwangalliHUD")
if old then
	old:Destroy()
end
local BASE_ORDER = tonumber(hudCfg.DisplayOrder) or 5
-- the open travel sheet draws above the small HUD layers (phone HUD 6, Now Playing 7); full-screen
-- UIs (bowling 20, phone 30, dialog 35) stay above it and hide it anyway
local SHEET_ORDER = BASE_ORDER + 4
local gui = make("ScreenGui", {
	Name = "GwangalliHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, -- below the top bar, inside the notch insets
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = BASE_ORDER,
})
gui:SetAttribute("HideGwangalliHUD", false)

-- invisible full-area frame: origin / usable area in the same space as Roblox's jump button
local probe = K.frame(gui, { Name = "AreaProbe", Size = UDim2.fromScale(1, 1), Active = false })

---------------------------------------------------------------------------------------------------
-- Geometry: area, device class, Roblox's touch controls, slots
---------------------------------------------------------------------------------------------------
type Rect = { x: number, y: number, w: number, h: number }
type Info = { W: number, H: number, ox: number, top: number, sw: number, sh: number, class: string, s: number }

local function area(): Vector2
	local size = probe.AbsoluteSize
	if size.X >= 50 and size.Y >= 50 then
		return size
	end
	local camera = workspace.CurrentCamera
	local vp = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = Vector2.new(0, 58)
	pcall(function()
		inset = GuiService:GetGuiInset()
	end)
	return Vector2.new(vp.X, math.max(vp.Y - inset.Y, 1))
end

local function screenInfo(): Info
	local a = area()
	local insetTop = 58
	pcall(function()
		insetTop = GuiService:GetGuiInset().Y
	end)
	local ox = math.max(probe.AbsolutePosition.X, 0)
	local sw, sh = a.X + 2 * ox, a.Y + insetTop
	local class
	if not isTouch then
		class = "pc"
	elseif math.min(sw, sh) <= 500 then
		class = if a.X < a.Y then "phoneP" else "phone"
	else
		class = "tablet"
	end
	if Layout and type(Layout.deviceClass) == "function" then
		local ok, c = pcall(Layout.deviceClass)
		if ok and type(c) == "string" then
			local l = string.lower(c)
			if string.find(l, "pc", 1, true) or string.find(l, "desktop", 1, true) then
				class = "pc"
			elseif string.find(l, "tablet", 1, true) then
				class = "tablet"
			elseif string.find(l, "portrait", 1, true) then
				class = "phoneP"
			elseif string.find(l, "phone", 1, true) then
				class = "phone"
			end
		end
	end
	local s
	if class == "pc" then
		s = math.clamp(math.min(a.X / 1280, a.Y / 662), 0.85, 1.3)
	elseif a.X >= a.Y then
		s = math.clamp(math.min(a.X / 740, a.Y / 302), 1, 1.25)
	else
		s = math.clamp(math.min(a.X / 360, a.Y / 600), 1, 1.25)
	end
	return { W = a.X, H = a.Y, ox = ox, top = insetTop, sw = sw, sh = sh, class = class, s = s }
end

-- Roblox's jump button in this gui's px. The live TouchGui button when present; else the union of
-- the PlayerModule TouchJump geometry measured from the safe area and from the whole screen (70 px
-- at (1,-95,1,-90) when the short side is <= 500 px, else 120 px at (1,-170,1,-210)).
local function jumpRect(info: Info): Rect
	local tg = playerGui:FindFirstChild("TouchGui")
	local frame = tg and tg:FindFirstChild("TouchControlFrame")
	local jb = frame and frame:FindFirstChild("JumpButton")
	if jb and jb:IsA("GuiObject") then
		local s = jb.AbsoluteSize
		local p = jb.AbsolutePosition - probe.AbsolutePosition
		if s.X >= 30 and s.Y >= 30 and p.X > info.W * 0.5 and p.Y > info.H * 0.3 and p.X + s.X <= info.W + 80 and p.Y + s.Y <= info.H + 80 then
			return { x = p.X, y = p.Y, w = s.X, h = s.Y }
		end
	end
	local small = math.min(info.sw, info.sh) <= 500
	local size = if small then 70 else 120
	local dx, dy = if small then 95 else 170, if small then 90 else 210
	local xSafe = info.W - dx
	local xScreen = info.sw - dx - info.ox
	local x = math.min(xSafe, xScreen)
	local right = math.max(xSafe, xScreen) + size
	local y = info.H - dy
	return { x = x, y = y, w = right - x, h = size }
end

local function jumpKey(): string
	local tg = playerGui:FindFirstChild("TouchGui")
	local frame = tg and tg:FindFirstChild("TouchControlFrame")
	local jb = frame and frame:FindFirstChild("JumpButton")
	if jb and jb:IsA("GuiObject") then
		local p, s = jb.AbsolutePosition, jb.AbsoluteSize
		return string.format("%.0f,%.0f,%.0f,%.0f", p.X, p.Y, s.X, s.Y)
	end
	return "none"
end

-- Built-in slots (same contract as GwangalliLayout) in this gui's px.
local function fallbackSlot(name: string, info: Info): Rect
	local W, H, s, class = info.W, info.H, info.s, info.class
	local item = (if class == "pc" or class == "tablet" then 64 else 56) * s
	local gap = 8 * s
	local col: Rect
	if class == "pc" then
		local colH = 3 * item + 2 * gap
		col = { x = W - 16 - item, y = H - 16 - colH, w = item, h = colH }
	else
		local j = jumpRect(info)
		local cx = math.clamp(j.x + math.min(j.w, j.h) / 2, item / 2 + 8, W - item / 2 - 8)
		local bottom = j.y - 12
		local g = gap
		local colH = 3 * item + 2 * g
		if bottom - colH < 6 then
			g = math.max(4, (bottom - 6 - 3 * item) / 2)
			colH = 3 * item + 2 * g
		end
		col = { x = cx - item / 2, y = bottom - colH, w = item, h = colH }
	end
	if name == "rightColumn" then
		return col
	end
	local thumbRight = info.sw * 0.4 - info.ox
	local thumbTop = info.sh * 0.4 - info.top
	if name == "topLeftChips" then
		return { x = 8, y = 8, w = 170 * s, h = 44 * s }
	elseif name == "topRight" then
		local w = 230 * s
		return { x = (if class == "pc" then W - 16 else col.x - 8) - w, y = 8, w = w, h = 50 * s }
	elseif name == "topCenter" then
		local left = 8 + 170 * s + 8
		local right = (if class == "pc" then W - 16 else col.x - 8) - 230 * s - 8
		local w = math.min(300 * s, 2 * math.min(W / 2 - left, right - W / 2))
		if class == "phoneP" then
			w = math.min(300 * s, W - left - 8)
			return { x = left, y = 8, w = w, h = 44 * s }
		end
		w = math.max(w, 180 * s)
		return { x = W / 2 - w / 2, y = 8, w = w, h = 44 * s }
	elseif name == "bottomCenter" then
		local h = 56 * s
		if class == "pc" then
			local w = 360 * s
			return { x = W / 2 - w / 2, y = H - 16 - h, w = w, h = h }
		elseif class == "phoneP" then
			local w = math.min(340 * s, W - 16)
			return { x = W / 2 - w / 2, y = thumbTop - 8 - h, w = w, h = h }
		end
		local j = jumpRect(info)
		local left, right = thumbRight + 8, j.x - 12
		local w = math.min(340 * s, right - left)
		return { x = left + (right - left - w) / 2, y = H - 8 - h, w = w, h = h }
	elseif name == "sheetRight" then
		if class == "pc" then
			local w = 400 * s
			local h = math.min(700 * s, H - 32)
			return { x = col.x - 16 - w, y = (H - h) / 2, w = w, h = h }
		elseif class == "tablet" then
			local w = 400 * s
			return { x = W - 16 - w, y = 16, w = w, h = H - 32 }
		elseif class == "phoneP" then
			local y = math.floor(H * 0.3)
			return { x = 0, y = y, w = W, h = H - y }
		end
		local w = math.max(280, math.floor(W * 0.44))
		return { x = W - 8 - w, y = 8, w = w, h = H - 16 }
	elseif name == "toasts" then
		local w = math.min(380 * s, W - 16)
		return { x = W / 2 - w / 2, y = 8, w = w, h = 200 }
	end
	return { x = 8, y = 8, w = 100, h = 44 }
end

local function udimRect(pos: UDim2, size: UDim2, anchor: Vector2, W: number, H: number): Rect
	local w = size.X.Scale * W + size.X.Offset
	local h = size.Y.Scale * H + size.Y.Offset
	return { x = pos.X.Scale * W + pos.X.Offset - anchor.X * w, y = pos.Y.Scale * H + pos.Y.Offset - anchor.Y * h, w = w, h = h }
end

-- GwangalliLayout.rect(name) -> {x, y, w, h}; else GwangalliLayout.slot(name) -> position, size,
-- anchor (or a table with those fields); else the built-in fallback.
local function slot(name: string, info: Info): Rect
	if Layout then
		if type(Layout.rect) == "function" then
			local ok, r = pcall(Layout.rect, name)
			if ok and type(r) == "table" and type(r.x) == "number" and type(r.w) == "number" and r.w > 1 and (r.h or 0) > 1 then
				return { x = r.x, y = r.y, w = r.w, h = r.h }
			end
		end
		if type(Layout.slot) == "function" then
			local ok, a, b, c = pcall(Layout.slot, name)
			if ok then
				local pos, size, anchor = a, b, c
				if type(a) == "table" then
					pos = a.position or a.Position or a.pos
					size = a.size or a.Size
					anchor = a.anchor or a.anchorPoint or a.AnchorPoint
				end
				if typeof(pos) == "UDim2" and typeof(size) == "UDim2" then
					local r = udimRect(pos, size, if typeof(anchor) == "Vector2" then anchor else Vector2.zero, info.W, info.H)
					if r.w > 1 and r.h > 1 then
						return r
					end
				end
			end
		end
	end
	local item = string.match(name, "^rightColumn%.(%a+)$")
	if item then
		local col = slot("rightColumn", info)
		local size = math.max(44, math.min(col.w, (col.h - 8) / 3))
		local gap = math.max(4, (col.h - 3 * size) / 2)
		local index = if item == "phone" then 0 elseif item == "travel" then 1 else 2
		return { x = col.x + (col.w - size) / 2, y = col.y + index * (size + gap), w = size, h = size }
	end
	return fallbackSlot(name, info)
end

---------------------------------------------------------------------------------------------------
-- Clock / date / weather chip (topCenter). Line 2 alternates between the weather and a small
-- drone-show pill (next show time; a red LIVE pill while a show runs; terrain progress at start-up).
---------------------------------------------------------------------------------------------------
local clockChip = K.frame(gui, {
	Name = "ClockChip",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(200, 44),
	BackgroundTransparency = 0.14,
	BackgroundColor3 = C.glass,
	ZIndex = 2,
})
U.clockScale = make("UIScale", { Scale = 1 }, clockChip)
K.corner(clockChip, 16)
U.clockStroke = K.stroke(clockChip, C.line, 1, 0.86)
-- top sheen: a 1 px highlight that fades out towards the ends (lit glass edge)
do
	local sheen = K.frame(clockChip, { Name = "Sheen", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 1), Size = UDim2.new(1, -28, 0, 1), BackgroundTransparency = 0.78, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2 })
	K.gradient(sheen, { Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }))
end
U.clockShadow = K.shadow(clockChip, 16, 6, "soft")
U.phaseTile = K.iconTile(clockChip, 30, "🌅", GOLD, true)
U.phaseTile.AnchorPoint = Vector2.new(0, 0.5)
U.phaseTile.Position = UDim2.new(0, 7, 0.5, 0)
U.phaseGlyph = U.phaseTile:FindFirstChild("Glyph") :: TextLabel
local CLOCK_X, CLOCK_W = 43, 58
local TEXT_X = CLOCK_X + CLOCK_W + 11
U.clockLabel = K.text(clockChip, {
	Name = "Clock",
	Position = UDim2.fromOffset(CLOCK_X, 0),
	Size = UDim2.new(0, CLOCK_W, 1, 0),
	Text = "--:--",
	Font = FONT_NUM,
	TextSize = 20,
})
-- tabular digits in a firmer weight (Roboto Mono SemiBold) so the minutes never jiggle
if type(K.mono) == "function" then
	pcall(K.mono, U.clockLabel, Enum.FontWeight.SemiBold)
end
K.frame(clockChip, { Name = "Divider", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, CLOCK_X + CLOCK_W + 4, 0.5, 0), Size = UDim2.fromOffset(1, 22), BackgroundTransparency = 0.82, BackgroundColor3 = C.line })
U.dayLabel = K.text(clockChip, {
	Name = "Day",
	Position = UDim2.fromOffset(TEXT_X, 5),
	Size = UDim2.new(1, -TEXT_X - 8, 0, 18),
	Text = "",
	Font = F.bold,
	TextSize = 13,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
-- line 2 is a clipped strip: weather and the drone pill roll through it like a ticker
U.line2 = K.frame(clockChip, { Name = "Line2", Position = UDim2.fromOffset(TEXT_X - 2, 22), Size = UDim2.new(1, -TEXT_X - 4, 0, 19), ClipsDescendants = true })
U.weatherLabel = K.text(U.line2, {
	Name = "Weather",
	Position = UDim2.fromOffset(2, 1),
	Size = UDim2.new(1, -4, 0, 16),
	Text = "",
	TextColor3 = C.sub,
	Font = F.medium,
	TextSize = 12,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
U.dronePill = K.frame(U.line2, { Name = "DronePill", Position = UDim2.fromOffset(0, 1), Size = UDim2.fromOffset(80, 17), BackgroundTransparency = 0, BackgroundColor3 = C.card2, Visible = false })
K.corner(U.dronePill, 8)
U.droneDot = K.frame(U.dronePill, { Name = "Dot", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.fromOffset(6, 6), BackgroundTransparency = 0, BackgroundColor3 = LIVE })
K.corner(U.droneDot, UDim.new(0.5, 0))
U.droneLabel = K.text(U.dronePill, { Name = "Label", Position = UDim2.fromOffset(15, 0), Size = UDim2.new(1, -19, 1, 0), Text = "", Font = F.bold, TextSize = 11 })

---------------------------------------------------------------------------------------------------
-- Right column: 이동 / 달리기 (cells 2 and 3; the phone's 폰 button owns cell 1)
---------------------------------------------------------------------------------------------------
local actions = K.frame(gui, { Name = "Actions", Size = UDim2.fromOffset(56, 184), ZIndex = 2 })

type HudButton = { button: TextButton, glyph: Frame, caption: TextLabel, key: TextLabel, corner: UICorner, stroke: UIStroke, bars: { Frame }, fill: UIGradient }
-- Drawn icons (frames only, no emoji) so the column reads as one icon family with the phone's drawn
-- 폰 glyph: everything is in scale units of the Icon box, so it follows the button size.
local function bar(parent: Instance, name: string, x: number, y: number, w: number, h: number, rot: number, color: Color3?): Frame
	local f = K.frame(parent, { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h), Rotation = rot, BackgroundTransparency = 0, BackgroundColor3 = color or C.text, ZIndex = 4 })
	K.corner(f, UDim.new(0.5, 0))
	return f
end
local function drawIcon(kind: string, box: Frame, ink: Color3?, core: Color3?): { Frame }
	local bars = {}
	if kind == "travel" then
		-- map pin: round head + a 45-degree square tail (a teardrop), cyan core
		local tail = K.frame(box, { Name = "PinTail", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.48, 0.48), Rotation = 45, BackgroundTransparency = 0, BackgroundColor3 = ink or C.text, ZIndex = 4 })
		K.corner(tail, UDim.new(0.18, 0))
		local head = K.frame(box, { Name = "PinHead", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, -0.04), Size = UDim2.fromScale(0.76, 0.76), BackgroundTransparency = 0, BackgroundColor3 = ink or C.text, ZIndex = 5 })
		K.corner(head, UDim.new(0.5, 0))
		local core = K.frame(head, { Name = "Core", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.42, 0.42), BackgroundTransparency = 0, BackgroundColor3 = core or CYAN, ZIndex = 6 })
		K.corner(core, UDim.new(0.5, 0))
		table.insert(bars, head)
		table.insert(bars, tail)
	else
		-- run: double chevron (>>)
		for i, cx in { 0.3, 0.64 } do
			table.insert(bars, bar(box, "Chevron" .. i .. "A", cx, 0.5 - 0.17, 0.15, 0.5, -45, ink))
			table.insert(bars, bar(box, "Chevron" .. i .. "B", cx, 0.5 + 0.17, 0.15, 0.5, 45, ink))
		end
	end
	return bars
end
local function hudButton(name: string, icon: string, caption: string, keyHint: string?): HudButton
	local b = make("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = C.glass,
		BackgroundTransparency = K.GLASS_T or 0.14,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
	}, actions)
	-- round glass, same fill / hairline as the phone's 폰 button above it
	local corner = K.corner(b, UDim.new(0.5, 0))
	local st = K.stroke(b, Color3.new(1, 1, 1), 1, 0.8)
	local fill = K.gradient(b, K.Grad.primary, 90)
	fill.Enabled = false
	local box = K.frame(b, { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(0.4, 0.4), ZIndex = 4 })
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, box)
	local bars = drawIcon(icon, box)
	local cap = K.text(b, { Name = "Caption", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -5), Size = UDim2.new(1, -4, 0, 13), Text = caption, TextSize = K.Type and K.Type.micro or 11, Font = F.bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	local key = K.text(b, { Name = "Key", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 4), Size = UDim2.fromOffset(34, 14), Text = keyHint or "", TextSize = 11, Font = F.bold, TextColor3 = C.faint, TextXAlignment = Enum.TextXAlignment.Right, Visible = false, ZIndex = 4 })
	pressable(b, 0.92)
	return { button = b, glyph = box, caption = cap, key = key, corner = corner, stroke = st, bars = bars, fill = fill }
end
U.travelAction = hudButton("TravelButton", "travel", "이동", "M")
U.sprintAction = hudButton("SprintButton", "run", "달리기", "Shift")
local travelButton = U.travelAction.button
local sprintButton = U.sprintAction.button
-- stamina ring hugging the sprint button's edge (shown while running or when not full)
U.staminaBar = K.Ring(sprintButton, { size = 56, thickness = 2.5, color = GREEN, value = 1, name = "Stamina" })
U.staminaBar.frame.Size = UDim2.fromScale(1, 1)
U.staminaBar.frame.ZIndex = 5
do
	local track = U.staminaBar.frame:FindFirstChild("Track")
	local tst = track and track:FindFirstChildOfClass("UIStroke")
	if tst then
		tst.Transparency = 1 -- the button's own hairline is the track
	end
	if U.staminaBar.label then
		U.staminaBar.label.Visible = false
	end
end
U.staminaBar.frame.Visible = false

---------------------------------------------------------------------------------------------------
-- Quick-travel sheet
---------------------------------------------------------------------------------------------------
-- dim backdrop behind the touch sheet: an Active frame (taps on it close the sheet and never reach
-- the camera) rather than a button, so it is not a second tap target under the sheet
U.backdrop = K.frame(gui, {
	Name = "SheetBackdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	Active = true,
	Visible = false,
	ZIndex = 10,
})

local sheet = K.Panel(gui, {
	Name = "TravelPanel",
	Size = UDim2.fromOffset(320, 300),
	BackgroundTransparency = 0.04,
	Visible = false,
	ZIndex = 12,
	ClipsDescendants = true,
})
-- soft shadow only where the sheet floats (tablet / PC); on phones it touches the screen edges
U.sheetShadow = K.shadow(sheet, 20, 10)
U.sheetScale = make("UIScale", { Scale = 1 }, sheet)
local PAD = 12

-- header (drag to dismiss) ------------------------------------------------------------------------
U.header = K.frame(sheet, { Name = "Header", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 56), Active = true })
U.grabber = K.frame(U.header, { Name = "Grabber", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(36, 4), BackgroundTransparency = 0.7, BackgroundColor3 = C.line, Visible = false })
K.corner(U.grabber, 2)
U.headIcon = K.iconTile(U.header, 36, "", CYAN, false)
U.headIcon.AnchorPoint = Vector2.new(0, 0.5)
U.headIcon.Position = UDim2.new(0, PAD, 0.5, 0)
do
	local pinBox = K.frame(U.headIcon, { Name = "Pin", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromScale(0.5, 0.5), ZIndex = 4 })
	drawIcon("travel", pinBox, Color3.new(1, 1, 1), Color3.fromRGB(22, 120, 170))
end
U.sheetTitle = K.text(U.header, {
	Name = "Title",
	Position = UDim2.fromOffset(PAD + 46, 9),
	Size = UDim2.new(1, -(PAD + 46 + 56), 0, 22),
	Text = "빠른 이동",
	Font = F.heavy,
	TextSize = 19,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
local SUBTITLE_DEFAULT = "누르면 바로 이동해요"
U.sheetSub = K.text(U.header, {
	Name = "Subtitle",
	Position = UDim2.fromOffset(PAD + 46, 31),
	Size = UDim2.new(1, -(PAD + 46 + 56), 0, 16),
	Text = SUBTITLE_DEFAULT,
	TextColor3 = C.sub,
	TextSize = 12,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
U.closeButton = K.Button(U.header, { name = "Close", style = "icon", icon = "✕", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -8, 0.5, 0), textSize = 17 })
if not KIT_BUTTON_SOUNDS then
	U.closeButton.Activated:Connect(click)
end

-- search row ------------------------------------------------------------------------------------------
U.searchRow = nil
U.searchBox = nil
U.clearSearch = nil
U.searchStroke = nil
if type(K.SearchBar) == "function" then
	local ok, api = pcall(K.SearchBar, sheet, { name = "Search", placeholder = "장소 이름 검색" })
	if ok and type(api) == "table" and api.frame and api.box then
		U.searchRow = api.frame
		U.searchBox = api.box
	end
end
if not U.searchBox then
	U.searchRow = K.frame(sheet, { Name = "Search", Position = UDim2.fromOffset(PAD, 60), Size = UDim2.new(1, -2 * PAD, 0, 44), BackgroundTransparency = 0, BackgroundColor3 = C.card })
	K.corner(U.searchRow, 12)
	U.searchStroke = K.stroke(U.searchRow, nil, 1, 0.9)
	K.text(U.searchRow, { Name = "Glyph", Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 22, 1, 0), Text = "🔍", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center })
	U.searchBox = make("TextBox", {
		Name = "Query",
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -38 - 44, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "장소 이름 검색",
		PlaceholderColor3 = C.faint,
		TextColor3 = C.text,
		Font = F.medium,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, U.searchRow)
	local cs = make("TextButton", { Name = "ClearSearch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 1, Text = "✕", TextColor3 = C.sub, Font = F.bold, TextSize = 15, Visible = false }, U.searchRow)
	pressable(cs)
	U.clearSearch = cs
end
U.searchCancel = K.Button(sheet, { name = "SearchCancel", text = "취소", style = "ghost", size = UDim2.fromOffset(56, 44), textSize = 14 })
U.searchCancel.Visible = false

-- category chips ------------------------------------------------------------------------------------
local CATS = {
	{ id = "all", label = "전체", icon = "✨", color = CYAN },
	{ id = "plaza", label = "광장", icon = "🏛️", color = Color3.fromRGB(120, 150, 255) },
	{ id = "beach", label = "해변", icon = "🏖️", color = Color3.fromRGB(40, 196, 230) },
	{ id = "hotel", label = "호텔", icon = "🏨", color = Color3.fromRGB(180, 120, 255) },
	{ id = "club", label = "클럽", icon = "🎧", color = MAGENTA },
	{ id = "food", label = "맛집", icon = "🍜", color = Color3.fromRGB(255, 150, 60) },
	{ id = "transit", label = "교통", icon = "🚇", color = Color3.fromRGB(80, 200, 140) },
	{ id = "work", label = "내 직장", icon = "💼", color = GOLD },
	{ id = "home", label = "내 집", icon = "🏠", color = Color3.fromRGB(40, 200, 190) },
}
local CAT_BY_ID: { [string]: any } = {}
for _, c in CATS do
	CAT_BY_ID[c.id] = c
end
U.chipBar = make("ScrollingFrame", {
	Name = "Chips",
	Position = UDim2.fromOffset(PAD, 108),
	Size = UDim2.new(1, -2 * PAD, 0, 44),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollBarThickness = 0,
	ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
}, sheet)
K.list(U.chipBar, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
U.chipFade = K.frame(sheet, { Name = "ChipFade", AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(28, 44), BackgroundTransparency = 0, BackgroundColor3 = C.glass, ZIndex = 14 })
K.gradient(U.chipFade, { Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.05) }))
U.searchToggle = make("TextButton", { Name = "SearchButton", Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 1, Text = "", LayoutOrder = 0 }, U.chipBar)
do
	local pill = K.frame(U.searchToggle, { Name = "Pill", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 34), BackgroundTransparency = 0, BackgroundColor3 = C.card2 })
	K.corner(pill, 17)
	K.stroke(pill, nil, 1, 0.9)
	K.text(pill, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "🔍", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center })
	pressable(U.searchToggle)
end
type Chip = { button: GuiButton, set: (on: boolean) -> () }
local chips: { [string]: Chip } = {}
for i, c in CATS do
	local chip: Chip? = nil
	if type(K.Chip) == "function" then
		local ok, api = pcall(K.Chip, U.chipBar, { text = c.label, color = CYAN, order = i, name = "Chip_" .. c.id, minWidth = 52 })
		if ok and type(api) == "table" and api.button and type(api.set) == "function" then
			chip = { button = api.button, set = api.set }
		end
	end
	if not chip then
		local text = c.label
		local w = textWidth(text, 14) + 28
		local b = make("TextButton", { Name = "Chip_" .. c.id, Size = UDim2.fromOffset(w, 44), BackgroundTransparency = 1, Text = "", LayoutOrder = i }, U.chipBar)
		local pill = K.frame(b, { Name = "Pill", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 0, BackgroundColor3 = C.card2 })
		K.corner(pill, 17)
		local st = K.stroke(pill, nil, 1, 0.9)
		local l = K.text(pill, { Name = "Label", Size = UDim2.fromScale(1, 1), Text = text, Font = F.bold, TextSize = 14, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Center })
		pressable(b)
		local color = CYAN
		chip = {
			button = b,
			set = function(on: boolean)
				pill.BackgroundColor3 = if on then color else C.card2
				l.TextColor3 = if on then Color3.fromRGB(10, 14, 22) else C.sub
				st.Transparency = if on then 1 else 0.9
			end,
		}
	end
	chips[c.id] = chip :: Chip
end

-- list + states ---------------------------------------------------------------------------------------
local list = make("ScrollingFrame", {
	Name = "List",
	Position = UDim2.fromOffset(PAD, 160),
	Size = UDim2.new(1, -2 * PAD + 6, 1, -172),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = C.sub,
	ScrollBarImageTransparency = 0.5,
}, sheet)
K.list(list, false, 6)
make("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }, list)

-- empty / error state + loading skeleton: the kit's EmptyState / Skeleton when present
U.emptyApi = nil
if type(K.EmptyState) == "function" then
	local ok, api = pcall(K.EmptyState, list, { icon = "🧭", title = "", body = "", order = -1000, compact = true })
	if ok and type(api) == "table" and api.frame and type(api.set) == "function" then
		U.emptyApi = api
		api.frame.Visible = false
	end
end
U.stateBox = K.frame(list, { Name = "State", Size = UDim2.new(1, 0, 0, 140), LayoutOrder = -1000, Visible = false })
U.stateIcon = K.iconTile(U.stateBox, 44, "🧭", CYAN, true)
U.stateIcon.AnchorPoint = Vector2.new(0.5, 0)
U.stateIcon.Position = UDim2.new(0.5, 0, 0, 12)
U.stateTitle = K.text(U.stateBox, { Name = "Title", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 22), Text = "", Font = F.bold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
U.stateBody = K.text(U.stateBox, { Name = "Body", Position = UDim2.fromOffset(8, 88), Size = UDim2.new(1, -16, 0, 36), Text = "", TextColor3 = C.sub, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top })

U.skeletonKit = nil
if type(K.Skeleton) == "function" then
	local ok, f = pcall(K.Skeleton, list, { rows = 4, rowHeight = 58, gap = 6, avatar = true, order = -900 })
	if ok and typeof(f) == "Instance" then
		U.skeletonKit = f
		f.Visible = false
	end
end
U.skeletons = {}
if not U.skeletonKit then
	for i = 1, 4 do
		local sk = K.frame(list, { Name = "Skeleton" .. i, Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 0, BackgroundColor3 = C.card, LayoutOrder = -900 + i, Visible = false })
		K.corner(sk, 12)
		local a1 = K.frame(sk, { Name = "A", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 0, BackgroundColor3 = C.card2 })
		K.corner(a1, 10)
		local b1 = K.frame(sk, { Name = "B", Position = UDim2.fromOffset(56, 14), Size = UDim2.new(0.5, 0, 0, 12), BackgroundTransparency = 0, BackgroundColor3 = C.card2 })
		K.corner(b1, 6)
		local c1 = K.frame(sk, { Name = "C", Position = UDim2.fromOffset(56, 32), Size = UDim2.new(0.3, 0, 0, 10), BackgroundTransparency = 0.3, BackgroundColor3 = C.card2 })
		K.corner(c1, 5)
		U.skeletons[i] = sk
	end
end
U.skeletonPulse = nil

local toaster: any = nil
local toastCount = 0

---------------------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------------------
local sheetOpen = false
local hudHidden = false
local searchMode = false -- compact layouts: the chip row turns into the search field
local compact = false -- short screens: search toggles with the chip row instead of its own row
local category = "all"
local query = ""
local sheetRect: Rect = { x = 0, y = 0, w = 320, h = 300 }
local sheetFrom: UDim2 = UDim2.new()
local slideAxis = "x" -- the sheet slides in along this axis ("y" for the portrait bottom sheet)
local lastInfo: Info? = nil
local lastJump = ""
local toastsOverClock = true
local lineWidth = 80 -- clock chip: px available for the day / weather lines

local refreshVisibility: () -> ()
local sheetClosing = false
local setLayer: (inst: GuiObject, shown: boolean, rest: UDim2?, away: UDim2) -> ()
local layerState: { [Instance]: string } = {}
local layerSerial: { [Instance]: number } = {}

---------------------------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------------------------
local function styleActionButton(a: HudButton, w: number, h: number, pc: boolean)
	a.button.Size = UDim2.fromOffset(w, h)
	local round = math.abs(w - h) < 2
	a.corner.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0, math.floor(math.min(w, h) * 0.36))
	local k = math.min(w, h) / 56
	a.glyph.Size = UDim2.fromOffset(math.floor(22 * k), math.floor(22 * k))
	a.glyph.Position = UDim2.new(0.5, 0, 0, math.floor(8 * k + 11 * k))
	a.caption.TextSize = math.max(11, math.floor(11 * k))
	a.caption.Size = UDim2.new(1, -4, 0, math.floor(13 * k))
	a.caption.Position = UDim2.new(0.5, 0, 1, -math.floor(5 * k))
	a.key.Visible = pc and UserInputService.KeyboardEnabled
end

local function layoutSheet(info: Info)
	local r = slot("sheetRight", info)
	-- a readable minimum; never wider / taller than the gui
	r.w = math.min(math.max(r.w, 260), info.W)
	r.h = math.min(math.max(r.h, 200), info.H)
	sheetRect = r
	local portrait = info.class == "phoneP"
	slideAxis = if portrait then "y" else "x"
	sheet.AnchorPoint = Vector2.zero
	sheet.Size = UDim2.fromOffset(r.w, r.h)
	U.sheetScale.Scale = 1
	if not sheetOpen then
		sheet.Position = UDim2.fromOffset(r.x, r.y)
	else
		sheet.Position = UDim2.fromOffset(r.x, r.y)
	end
	sheetFrom = if slideAxis == "y" then UDim2.fromOffset(r.x, info.H + 12) else UDim2.fromOffset(info.W + 12, r.y)
	U.grabber.Visible = portrait
	-- compact (short) layouts: search lives in the chip row
	compact = r.h < 420
	local y = if portrait then 14 else 4
	U.header.Position = UDim2.fromOffset(0, y - 4)
	U.header.Size = UDim2.new(1, 0, 0, 56)
	y += 52
	if compact then
		U.searchRow.Position = UDim2.fromOffset(PAD, y)
		U.searchRow.Size = UDim2.new(1, -2 * PAD - 62, 0, 44)
		U.searchCancel.AnchorPoint = Vector2.new(1, 0)
		U.searchCancel.Position = UDim2.new(1, -PAD + 2, 0, y)
		U.chipBar.Position = UDim2.fromOffset(PAD, y)
		U.searchRow.Visible = searchMode
		U.searchCancel.Visible = searchMode
		U.chipBar.Visible = not searchMode
		U.searchToggle.Visible = true
		y += 44 + 6
	else
		U.searchRow.Position = UDim2.fromOffset(PAD, y)
		U.searchRow.Size = UDim2.new(1, -2 * PAD, 0, 44)
		U.searchRow.Visible = true
		U.searchCancel.Visible = false
		U.searchToggle.Visible = false
		y += 44 + 6
		U.chipBar.Position = UDim2.fromOffset(PAD, y)
		U.chipBar.Visible = true
		y += 44 + 6
	end
	list.Position = UDim2.fromOffset(PAD, y)
	list.Size = UDim2.new(1, -2 * PAD + 6, 1, -y - 4)
	U.chipFade.Position = UDim2.new(1, -PAD, 0, U.chipBar.Position.Y.Offset)
	U.chipFade.Visible = U.chipBar.Visible
	local rh = if info.class == "pc" then 54 else 58
	for _, sk in U.skeletons do
		sk.Size = UDim2.new(1, 0, 0, rh)
	end
end

local function applyLayout()
	isTouch = wantTouchLayout()
	if Layout and type(Layout.refresh) == "function" then
		pcall(Layout.refresh) -- re-measure now: its own change signal may arrive after ours
	end
	local info = screenInfo()
	if info.W < 50 or info.H < 50 then
		return
	end
	lastInfo = info
	lastJump = jumpKey()

	-- clock chip: fills the topCenter slot's width (content scales with the slot height) ---------------
	local cr = slot("topCenter", info)
	local h = math.clamp(cr.h, 40, 56)
	local k = h / 44
	U.clockScale.Scale = k
	local wUnscaled = math.clamp(cr.w / k, 150, 300)
	clockChip.AnchorPoint = Vector2.new(0.5, 0)
	U.clockRest = UDim2.fromOffset(math.floor(cr.x + cr.w / 2), math.floor(cr.y))
	if layerState[clockChip] ~= "leaving" then
		clockChip.Position = U.clockRest
	end
	clockChip.Size = UDim2.fromOffset(math.floor(wUnscaled), 44)
	lineWidth = math.floor(wUnscaled - TEXT_X - 8)

	-- right column: cells 2 (이동) and 3 (달리기) --------------------------------------------------------
	local col = slot("rightColumn", info)
	local tr0 = slot("rightColumn.travel", info)
	local sr0 = slot("rightColumn.sprint", info)
	-- cells are square on touch screens, 84 x 60 pills on PC (the slot decides)
	local bw = math.floor(math.max(44, tr0.w))
	local bh = math.floor(math.max(44, tr0.h))
	U.actionsRest = UDim2.fromOffset(math.floor(col.x), math.floor(col.y))
	if layerState[actions] ~= "leaving" then
		actions.Position = U.actionsRest
	end
	actions.Size = UDim2.fromOffset(math.floor(col.w), math.floor(col.h))
	styleActionButton(U.travelAction, bw, bh, info.class == "pc")
	styleActionButton(U.sprintAction, bw, bh, info.class == "pc")
	travelButton.Position = UDim2.fromOffset(math.floor(tr0.x - col.x + (tr0.w - bw) / 2), math.floor(tr0.y - col.y + (tr0.h - bh) / 2))
	sprintButton.Position = UDim2.fromOffset(math.floor(sr0.x - col.x + (sr0.w - bw) / 2), math.floor(sr0.y - col.y + (sr0.h - bh) / 2))

	-- toasts (own toaster only when the kit has no shared one) -----------------------------------------
	local tr = slot("toasts", info)
	if toaster and type(toaster.place) == "function" then
		pcall(toaster.place, math.floor(tr.x + tr.w / 2), math.floor(tr.y), math.floor(tr.w))
	end
	toastsOverClock = tr.y < cr.y + h and tr.y + tr.h > cr.y and tr.x < cr.x + cr.w and tr.x + tr.w > cr.x

	-- the sheet's shadow only where it floats
	if U.sheetShadow then
		U.sheetShadow.Parent = if info.class == "pc" or info.class == "tablet" then gui else nil
	end
	layoutSheet(info)
	refreshVisibility()
end

---------------------------------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------------------------------
local droneText = ""
function setLayer(inst: GuiObject, shown: boolean, rest: UDim2?, away: UDim2)
	local st = layerState[inst]
	local want = if shown then "shown" else "hidden"
	if st == want or (st == "leaving" and not shown) then
		return
	end
	local home = rest or inst.Position
	layerSerial[inst] = (layerSerial[inst] or 0) + 1
	local mine = layerSerial[inst]
	if st == nil or reducedMotion() then
		-- first layout: no animation
		layerState[inst] = want
		inst.Visible = shown
		inst.Position = home
		return
	end
	if shown then
		layerState[inst] = "shown"
		inst.Visible = true
		inst.Position = home + away
		spring(inst, 0.42, { Position = home - UDim2.fromOffset(away.X.Offset * 0.05, away.Y.Offset * 0.05) }, { Position = home })
	else
		layerState[inst] = "leaving"
		springSerial[inst] = (springSerial[inst] or 0) + 1
		tw(inst, 0.2, { Position = home + away }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.21, function()
			if layerSerial[inst] == mine then
				layerState[inst] = "hidden"
				inst.Visible = false
				inst.Position = if inst == clockChip then (U.clockRest or home) else (U.actionsRest or home)
			end
		end)
	end
end
function refreshVisibility()
	local touchSheet = (sheetOpen or sheetClosing) and isTouch
	local toastUp = toastCount > 0 and toastsOverClock
	-- layers glide out towards their edge and spring back in (the clock up, the column right)
	setLayer(clockChip, not hudHidden and not touchSheet and not toastUp, U.clockRest, UDim2.fromOffset(0, -64))
	setLayer(actions, not hudHidden and not touchSheet, U.actionsRest, UDim2.fromOffset(96, 0))
	if toaster and toaster.holder then
		toaster.holder.Visible = not hudHidden
	end
end

-- Toasts: the kit's shared stack (GwangalliUI.toast) when it exists, else an own Toaster in the
-- "toasts" slot (created lazily).
local function ensureToaster()
	if toaster or type(K.toast) == "function" then
		return
	end
	local ok = pcall(function()
		toaster = K.Toaster(gui)
	end)
	if ok and toaster and toaster.holder then
		local function recount()
			local n = 0
			for _, c in toaster.holder:GetChildren() do
				if c:IsA("GuiButton") and c.Parent then
					n += 1
				end
			end
			if n ~= toastCount then
				toastCount = n
				refreshVisibility()
			end
		end
		toaster.holder.ChildAdded:Connect(recount)
		toaster.holder.ChildRemoved:Connect(recount)
		applyLayout()
	end
end

-- The shared stack (the phone's GwangalliToasts gui) slides over the clock chip: the chip steps aside
-- while a card is up so the two never stack on top of each other.
local globalHolderConns: { RBXScriptConnection } = {}
local function watchGlobalToasts(g: Instance)
	if g.Name ~= "GwangalliToasts" or not g:IsA("ScreenGui") then
		return
	end
	task.spawn(function()
		local holder = g:WaitForChild("Toasts", 10)
		if not holder then
			return
		end
		for _, c in globalHolderConns do
			c:Disconnect()
		end
		table.clear(globalHolderConns)
		local function recount()
			local n = 0
			for _, c in holder:GetChildren() do
				if c.Name == "Toast" and c:IsA("GuiObject") then
					n += 1
				end
			end
			if n ~= toastCount then
				toastCount = n
				refreshVisibility()
			end
		end
		table.insert(globalHolderConns, holder.ChildAdded:Connect(recount))
		table.insert(globalHolderConns, holder.ChildRemoved:Connect(recount))
		recount()
	end)
end
playerGui.ChildAdded:Connect(watchGlobalToasts)
do
	local g = playerGui:FindFirstChild("GwangalliToasts")
	if g then
		watchGlobalToasts(g)
	end
end

-- Toast dodge (docs/ui_kit_requests.md #3, local until the kit's toaster does it): while a right-hand
-- sheet is open (an enabled ScreenGui with SheetOpenRight = true and its left edge in screen px in
-- SheetLeft: the travel sheet, the bottle sheet, the home sheet) the shared toast stack glides into the
-- free area left of the sheet, so a notice never covers the sheet's header; an enabled ScreenGui with
-- ToastBelow = y (AbsolutePosition space) pushes it below y, and ToastsHidden = true (a bowling lane:
-- focus mode, the lane has its own notice pill) hides the stack; cards still time out and the phone
-- keeps them. Everything glides back when nothing asks any more.
do
	local dodged: any = nil
	local watched: { [Instance]: boolean } = {}
	local hiddenHolder: GuiObject? = nil
	local function asks(): (number?, number?, boolean)
		local left: number?, below: number? = nil, nil
		local hide = false
		for g in watched do
			if g.Parent == playerGui and (g :: ScreenGui).Enabled then
				if g:GetAttribute("ToastsHidden") == true then
					hide = true
				end
				local x = g:GetAttribute("SheetLeft")
				if g:GetAttribute("SheetOpenRight") == true and type(x) == "number" and (left == nil or x < left) then
					left = x
				end
				local y = g:GetAttribute("ToastBelow")
				if type(y) == "number" and (below == nil or y > below) then
					below = y
				end
			end
		end
		return left, below, hide
	end
	local function update()
		local tg = playerGui:FindFirstChild("GwangalliToasts")
		local holder = tg and tg:FindFirstChild("Toasts")
		if not (tg and tg:IsA("ScreenGui") and holder and holder:IsA("GuiObject")) then
			return
		end
		local left, below, hide = asks()
		if hide and not hiddenHolder then
			hiddenHolder = holder
			holder.Visible = false
		elseif not hide and hiddenHolder then
			if hiddenHolder.Parent then
				hiddenHolder.Visible = true
			end
			hiddenHolder = nil
		end
		if left or below then
			if not dodged or dodged.holder ~= holder then
				dodged = {
					holder = holder,
					pos = holder.Position,
					size = holder.Size,
					anchor = holder.AnchorPoint,
					ax = holder.AbsolutePosition.X,
					ay = holder.AbsolutePosition.Y,
					aw = holder.AbsoluteSize.X,
				}
			end
			local d = dodged
			local origin = tg.AbsolutePosition
			local x, y, w = d.ax, d.ay, d.aw
			if left and d.ax + d.aw > left - 8 then
				local free = left - 8 - (origin.X + 8)
				if free >= 160 then
					w = math.min(d.aw, free)
					x = origin.X + 8 + (free - w) / 2
				end
			end
			if below and below + 6 > y then
				y = below + 6
			end
			holder.AnchorPoint = Vector2.new(0, 0)
			tw(holder, 0.26, { Position = UDim2.fromOffset(math.floor(x - origin.X), math.floor(y - origin.Y)), Size = UDim2.new(0, w, d.size.Y.Scale, d.size.Y.Offset) })
		elseif dodged then
			local d = dodged
			dodged = nil
			if d.holder.Parent then
				d.holder.AnchorPoint = d.anchor
				tw(d.holder, 0.26, { Position = d.pos, Size = d.size })
			end
		end
	end
	local function watch(g: Instance)
		if not g:IsA("ScreenGui") or watched[g] then
			return
		end
		watched[g] = true
		g:GetAttributeChangedSignal("SheetOpenRight"):Connect(update)
		g:GetAttributeChangedSignal("SheetLeft"):Connect(update)
		g:GetAttributeChangedSignal("ToastBelow"):Connect(update)
		g:GetAttributeChangedSignal("ToastsHidden"):Connect(update)
		g:GetPropertyChangedSignal("Enabled"):Connect(update)
		g.AncestryChanged:Connect(function()
			if g.Parent ~= playerGui then
				watched[g] = nil
				update()
			end
		end)
	end
	for _, g in playerGui:GetChildren() do
		watch(g)
	end
	playerGui.ChildAdded:Connect(function(g)
		watch(g)
		if g.Name == "GwangalliToasts" then
			task.defer(update)
		end
	end)
end

local function toast(kind: string, title: string, body: string?, icon: string?, duration: number?)
	if hudHidden then
		return
	end
	local t = { kind = kind, title = title, body = body or "", icon = icon, duration = duration or 3.2 }
	if type(K.toast) == "function" then
		pcall(K.toast, t)
	else
		ensureToaster()
		if toaster then
			pcall(toaster.push, t)
		end
	end
	if kind == "error" or kind == "warn" then
		haptic("warning")
	end
end

gui.Parent = playerGui

local viewportConn: RBXScriptConnection? = nil
local function bindCamera()
	if viewportConn then
		viewportConn:Disconnect()
		viewportConn = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
	applyLayout()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
pcall(function()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(applyLayout)
end)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "TouchGui" then
		task.delay(0.5, applyLayout) -- the PlayerModule builds its buttons right after parenting
	end
end)
-- the slot contract: re-apply on its change signal; the module may be published after we start
local layoutConn: RBXScriptConnection? = nil
local function hookLayout()
	if layoutConn or not Layout then
		return
	end
	local ev = Layout.changed
	if typeof(ev) == "RBXScriptSignal" then
		layoutConn = ev:Connect(applyLayout)
	end
end
hookLayout()
ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "GwangalliLayout" and child:IsA("ModuleScript") then
		task.defer(function()
			Layout = optionalModule("GwangalliLayout")
			hookLayout()
			applyLayout()
		end)
	elseif child.Name == "GwangalliGameplayShared" and not G then
		task.defer(function()
			G = optionalModule("GwangalliGameplayShared")
		end)
	end
end)
bindCamera()

local function checkLayoutDrift()
	if wantTouchLayout() ~= isTouch then
		applyLayout()
	elseif isTouch and jumpKey() ~= lastJump then
		applyLayout()
	end
end

---------------------------------------------------------------------------------------------------
-- Character controls (touch sheet is modal)
---------------------------------------------------------------------------------------------------
local controlsDisabledByUs = false
local function getControls(): any
	local ok, controls = pcall(function()
		local ps = player:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if pm and pm:IsA("ModuleScript") then
			return (require(pm) :: any):GetControls()
		end
		return nil
	end)
	return if ok then controls else nil
end
local function setControls(enabled: boolean)
	local controls = getControls()
	if controls then
		pcall(function()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- Sprint (stamina aware)
---------------------------------------------------------------------------------------------------
local sprintHeld = false -- keyboard hold
local sprintToggled = false -- touch button / gamepad / toggle key mode
local sprintKeys: { [Enum.KeyCode]: boolean } = {}
for _, key in sprintCfg.Keys or { Enum.KeyCode.LeftShift } do
	sprintKeys[key] = true
end
local WALK, RUN = tonumber(sprintCfg.WalkSpeed) or 16, tonumber(sprintCfg.RunSpeed) or 26
local TIRED = 10 -- stamina below this: a slower run
local lastRun = RUN
local tiredWarned = false

local function humanoidOf(character: Model?): Humanoid?
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function staminaValue(): number?
	local v = player:GetAttribute("Stamina")
	return if type(v) == "number" and v == v then math.clamp(v, 0, 100) else nil
end

local function runSpeed(): number
	local bonus = player:GetAttribute("RunSpeedBonus")
	if type(bonus) ~= "number" then
		local hum = humanoidOf(player.Character)
		bonus = hum and hum:GetAttribute("RunSpeedBonus")
	end
	local b = if type(bonus) == "number" and bonus == bonus then math.clamp(bonus, 0, 10) else 0
	local st = staminaValue()
	if st and st < TIRED then
		return WALK + (RUN - WALK) * 0.6
	end
	return RUN + b
end

local function isOurSpeed(v: number): boolean
	return math.abs(v - WALK) < 0.05 or math.abs(v - RUN) < 0.05 or math.abs(v - lastRun) < 0.05
end

local function refreshStamina()
	local st = staminaValue()
	local on = sprintHeld or sprintToggled
	-- calm by default: the ring only shows while running or once stamina is getting low
	U.staminaBar.frame.Visible = st ~= nil and (on or st < 50)
	if st then
		U.staminaBar.set(st / 100)
		U.staminaBar.setColor(if st < TIRED then DANGER elseif st < 35 then WARN elseif on then Color3.new(1, 1, 1) else GREEN)
	end
end

-- chevrons drift forward while running (one looping tween each, no per-frame work)
local runTweens: { Tween } = {}
local function setRunMotion(on: boolean)
	for _, t in runTweens do
		t:Cancel()
	end
	table.clear(runTweens)
	for _, f in U.sprintAction.bars do
		local base = f:GetAttribute("BaseX")
		if base == nil then
			base = f.Position.X.Scale
			f:SetAttribute("BaseX", base)
		end
		f.Position = UDim2.fromScale(base, f.Position.Y.Scale)
		if on and not reducedMotion() then
			local t = TweenService:Create(f, TweenInfo.new(0.42, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromScale(base + 0.08, f.Position.Y.Scale) })
			t:Play()
			table.insert(runTweens, t)
		end
	end
end

local sprintVisualOn: boolean? = nil
local function applySprint()
	local on = sprintHeld or sprintToggled
	if on ~= sprintVisualOn then
		sprintVisualOn = on
		local ink = if on then (C.onAccent or Color3.fromRGB(4, 22, 32)) else C.text
		U.sprintAction.fill.Enabled = on
		sprintButton.BackgroundColor3 = if on then Color3.new(1, 1, 1) else C.glass
		sprintButton.BackgroundTransparency = if on then 0 else (K.GLASS_T or 0.14)
		U.sprintAction.stroke.Transparency = if on then 0.55 else 0.8
		U.sprintAction.caption.TextColor3 = ink
		for _, f in U.sprintAction.bars do
			f.BackgroundColor3 = ink
		end
		setRunMotion(on)
		refreshStamina()
	end
	local humanoid = humanoidOf(player.Character)
	if humanoid and humanoid.Health > 0 and isOurSpeed(humanoid.WalkSpeed) then
		-- only take over from our own values: a seat / minigame may have set a custom speed
		local run = runSpeed()
		lastRun = run
		humanoid.WalkSpeed = if on then run else WALK
	end
end

local function setSprintToggled(v: boolean)
	sprintToggled = v
	if v then
		local st = staminaValue()
		if st and st < TIRED and not tiredWarned then
			tiredWarned = true
			toast("warn", "체력이 거의 없어요", "천천히 달려요 · 집에서 자거나 먹으면 회복돼요", "🔋")
		end
	end
	applySprint()
end

sprintButton.Activated:Connect(function()
	setSprintToggled(not sprintToggled)
	haptic("light")
end)

player:GetAttributeChangedSignal("RunSpeedBonus"):Connect(applySprint)
player:GetAttributeChangedSignal("Stamina"):Connect(function()
	refreshStamina()
	local st = staminaValue()
	if st and st >= TIRED + 5 then
		tiredWarned = false
	end
	applySprint()
end)
refreshStamina()

player.CharacterAdded:Connect(function(character)
	sprintHeld = false
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		applySprint()
	end
end)
if player.Character then
	task.defer(applySprint)
end

-- Shift Lock is bound to LeftShift by default; move it so LeftShift can sprint.
if sprintCfg.RebindShiftLock then
	task.spawn(function()
		local ok, err = pcall(function()
			local ps = player:WaitForChild("PlayerScripts", 20)
			local pm = ps and ps:WaitForChild("PlayerModule", 20)
			local cm = pm and pm:WaitForChild("CameraModule", 20)
			local mlc = cm and cm:WaitForChild("MouseLockController", 20)
			if not mlc then
				return -- custom camera scripts: nothing to rebind
			end
			local bound = mlc:FindFirstChild("BoundKeys") or mlc:WaitForChild("BoundKeys", 5)
			if not bound then
				bound = Instance.new("StringValue")
				bound.Name = "BoundKeys"
				bound.Parent = mlc
			end
			if bound:IsA("StringValue") then
				bound.Value = sprintCfg.ShiftLockKeys or "LeftControl,RightShift"
			end
		end)
		if not ok then
			warn("[GwangalliHUD] Shift Lock rebind failed: " .. tostring(err))
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Travel data
---------------------------------------------------------------------------------------------------
type Entry = {
	id: string,
	name: string,
	main: string,
	detail: string,
	order: number,
	x: number?,
	z: number?,
	cat: string,
	norm: string,
	row: any,
	dist: number?,
}
local entries: { Entry } = {}
local travelRemote: RemoteEvent? = nil
local remoteState = "loading" -- "loading" | "ready" | "error"
local pendingUntil = 0
local pendingId: string? = nil
local lastSent = -math.huge

local function norm(s: string): string
	return (string.gsub(string.lower(s), "[%s·%-%(%)]", ""))
end

-- "GS25 광안해변점 (켄트호텔 1F)" -> "GS25 광안해변점", "켄트호텔 1F"
local function splitName(name: string): (string, string)
	local main, detail = string.match(name, "^(.-)%s*%((.-)%)%s*$")
	if main and main ~= "" then
		return main, detail or ""
	end
	return name, ""
end

-- category from keywords (the server may publish an explicit one through the part's Category attr)
local CAT_RULES = {
	{ "transit", { "지하철", "출구", "주차장", "주유소", "정류장", "터미널", "역 " } },
	{ "club", { "club", "클럽", "볼링", "노래", "pc방", "게임", "당구", "라운지", "bar" } },
	{ "food", { "회타운", "활어", "빵", "마켓", "스타벅스", "카페", "홍미당", "브롱스", "gs25", "홈플러스", "식당", "맛집", "치킨", "버거", "횟집", "편의점" } },
	{ "hotel", { "호텔", "hotel", "리조트", "워터파크", "찜질방", "스테이" } },
	{ "beach", { "해수욕장", "해변", "sup", "레포츠", "비치", "수변공원", "beach" } },
}
local CAT_ALIASES = { ["광장"] = "plaza", ["해변"] = "beach", ["호텔"] = "hotel", ["클럽"] = "club", ["맛집"] = "food", ["교통"] = "transit" }
local function categoryOf(main: string, explicit: any): string
	if type(explicit) == "string" and explicit ~= "" then
		if CAT_BY_ID[explicit] then
			return explicit
		end
		local alias = CAT_ALIASES[explicit]
		if alias then
			return alias
		end
	end
	local l = string.lower(main) .. " "
	for _, rule in CAT_RULES do
		for _, word in rule[2] do
			if string.find(l, word, 1, true) then
				return rule[1]
			end
		end
	end
	return "plaza"
end

-- the player's job / home places (life game): player attributes Job / HomeTier + shared tables
local function placeMatches(e: Entry, place: string): boolean
	if place == "" then
		return false
	end
	if e.name == place or e.main == place then
		return true
	end
	local p = norm(place)
	return #p >= 4 and (string.find(e.norm, p, 1, true) ~= nil or string.find(p, norm(e.main), 1, true) ~= nil)
end
local function workPlace(): string
	local job = player:GetAttribute("Job")
	if type(job) == "string" and job ~= "" and G and type(G.JOBS) == "table" then
		local j = G.JOBS[job]
		if type(j) == "table" and type(j.place) == "string" then
			return j.place
		end
	end
	return ""
end
local function homePlace(): string
	local tier = player:GetAttribute("HomeTier")
	if type(tier) == "number" and tier > 0 and G and type(G.LISTINGS) == "table" then
		for _, l in G.LISTINGS do
			if type(l) == "table" and l.tier == tier and type(l.place) == "string" then
				return l.place
			end
		end
	end
	return ""
end

local function myPosition(): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position
end

local function distText(m: number): string
	if m < 950 then
		return string.format("%d m", math.max(10, math.floor(m / 10 + 0.5) * 10))
	end
	return string.format("%.1f km", m / 1000)
end
local function walkText(studs: number): string
	local minutes = studs / math.max(WALK, 1) / 60
	if minutes < 1 then
		return "도보 1분"
	end
	return string.format("도보 %d분", math.floor(minutes + 0.5))
end

---------------------------------------------------------------------------------------------------
-- Travel sheet: rows, filtering, states
---------------------------------------------------------------------------------------------------
local requestTravel: (e: Entry) -> ()
local rowH = function(): number
	return if lastInfo and lastInfo.class == "pc" then 54 else 58
end

local function subtitleFor(e: Entry, work: boolean, home: boolean): string
	local cat = CAT_BY_ID[e.cat]
	local tag = if work then "💼 내 직장" elseif home then "🏠 내 집" else nil
	local rest = if e.detail ~= "" then e.detail elseif cat then cat.label else ""
	if tag then
		return if rest ~= "" then tag .. " · " .. rest else tag
	end
	return rest
end

-- One destination row: a layout-managed transparent button holding a Card (the visual) so the card
-- can slide / scale without re-flowing the list, plus a veil in the sheet colour for the staggered
-- reveal. Built once per destination list; filtering only toggles Visible / LayoutOrder.
local SHEET_FILL = C.glass
local function destRow(i: number, e: Entry, h: number): any
	local cat = CAT_BY_ID[e.cat] or CATS[1]
	local row = make("TextButton", { Name = "Dest_" .. i, Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = i }, nil)
	local card = K.frame(row, { Name = "Card", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2 })
	K.corner(card, 14)
	-- a whisper of vertical light: a touch brighter at the top edge, like a lit glass card
	K.gradient(card, { K.shade(C.card, 0, 0.035), C.card }, 90)
	K.stroke(card, C.line, 1, 0.93)
	local icon = K.iconTile(card, math.min(h - 18, 40), cat.icon, cat.color, false)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	icon.ZIndex = 3
	for _, d in icon:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 3
		end
	end
	local x = 10 + math.min(h - 18, 40) + 12
	local title = K.text(card, { Name = "Title", Position = UDim2.new(0, x, 0.5, -19), Size = UDim2.new(1, -(x + 84), 0, 20), Text = e.main, Font = F.bold, TextSize = K.Type.bodySm or 14, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	local sub = K.text(card, { Name = "Subtitle", Position = UDim2.new(0, x, 0.5, 1), Size = UDim2.new(1, -(x + 84), 0, 17), Text = cat.label, TextColor3 = C.sub, TextSize = K.Type.caption or 12, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	local trailing = K.text(card, { Name = "Trailing", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, -9), Size = UDim2.fromOffset(72, 18), Text = "", Font = FONT_NUM, TextSize = K.Type.bodySm or 14, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	if type(K.mono) == "function" then
		pcall(K.mono, trailing, Enum.FontWeight.Bold)
	end
	local walk = K.text(card, { Name = "Walk", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 10), Size = UDim2.fromOffset(72, 16), Text = "", TextColor3 = C.faint, TextSize = K.Type.caption or 12, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	-- pending sweep (a cyan sheen crossing the card while this trip is in flight)
	local sweep = K.frame(card, { Name = "Sweep", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.82, BackgroundColor3 = CYAN, Visible = false, ZIndex = 3 })
	K.corner(sweep, 14)
	local sweepGrad = K.gradient(sweep, { Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }))
	local veil = K.frame(card, { Name = "Veil", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BackgroundColor3 = SHEET_FILL, ZIndex = 6 })
	K.corner(veil, 14)
	pressable(row, 0.97, card)
	row.Activated:Connect(function()
		requestTravel(e)
	end)
	row.Parent = list
	return { row = row, card = card, veil = veil, title = title, subtitle = sub, trailing = trailing, walk = walk, icon = icon, sweep = sweep, sweepGrad = sweepGrad, sweepTween = nil :: Tween?, pin = 0 }
end

local function buildRows()
	for _, e in entries do
		if e.row and e.row.row then
			e.row.row:Destroy()
		end
	end
	local h = rowH()
	for i, e in entries do
		e.row = destRow(i, e, h)
	end
end

-- pending sweep on / off (one looping gradient-offset tween, only while a trip is in flight)
local function setPendingSweep(r: any, on: boolean)
	if r.sweepTween then
		r.sweepTween:Cancel()
		r.sweepTween = nil
	end
	r.sweep.Visible = on
	if on and not reducedMotion() then
		r.sweepGrad.Offset = Vector2.new(-1, 0)
		local t = TweenService:Create(r.sweepGrad, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1), { Offset = Vector2.new(1, 0) })
		t:Play()
		r.sweepTween = t
	end
end

local function setState(kind: string?)
	-- kind: nil (rows) | "loading" | "error" | "empty" | "work" | "home" | "search"
	local loading = kind == "loading"
	if U.skeletonKit then
		U.skeletonKit.Visible = loading
	else
		for _, sk in U.skeletons do
			sk.Visible = loading
		end
		if loading and not U.skeletonPulse and U.skeletons[1] then
			local ok, t = pcall(function()
				return TweenService:Create(U.skeletons[1], TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.35 })
			end)
			if ok then
				U.skeletonPulse = t
				t:Play()
			end
		elseif not loading and U.skeletonPulse then
			U.skeletonPulse:Cancel()
			U.skeletonPulse = nil
			U.skeletons[1].BackgroundTransparency = 0
		end
	end
	local glyph, color, title, body = "🧭", CYAN, "", ""
	if loading then
		title, body = "목적지를 불러오는 중…", "서버와 연결하고 있어요"
	elseif kind == "error" then
		glyph, color, title, body = "⚠️", WARN, "빠른 이동을 사용할 수 없어요", "잠시 후 다시 열어 주세요"
	elseif kind == "work" then
		glyph, color, title, body = "💼", GOLD, "아직 직장이 없어요", "폰의 알바 앱에서 일자리를 구해 보세요"
	elseif kind == "home" then
		glyph, color, title, body = "🏠", Color3.fromRGB(40, 200, 190), "아직 내 집이 없어요", "폰의 부동산 앱에서 집을 구해 보세요"
	elseif kind == "search" then
		glyph, color, title, body = "🔍", CYAN, string.format("'%s' 검색 결과가 없어요", query), "다른 이름이나 카테고리로 찾아보세요"
	elseif kind then
		glyph, color, title, body = "📍", CYAN, "이 카테고리에 장소가 없어요", "전체에서 찾아보세요"
	end
	-- the loading skeleton speaks for itself when the kit draws it; the caption stays for the fallback
	local showBox = kind ~= nil and not (loading and U.skeletonKit ~= nil)
	if U.emptyApi then
		U.emptyApi.frame.Visible = showBox
		U.stateBox.Visible = false
		if showBox then
			pcall(U.emptyApi.set, { icon = glyph, title = title, body = body, color = color })
		end
		return
	end
	U.stateBox.Visible = showBox
	if not showBox then
		return
	end
	local g = U.stateIcon:FindFirstChild("Glyph")
	if g and g:IsA("TextLabel") then
		g.Text = glyph
	end
	local grad = U.stateIcon:FindFirstChildOfClass("UIGradient")
	if grad then
		local hh, ss, vv = color:ToHSV()
		grad.Color = ColorSequence.new(Color3.fromHSV(hh, math.max(0, ss - 0.1), math.min(1, vv + 0.1)), Color3.fromHSV(hh, math.min(1, ss + 0.1), vv * 0.75))
	end
	U.stateTitle.Text = title
	U.stateBody.Text = body
end

local function refreshChips()
	for id, chip in chips do
		pcall(chip.set, id == category)
	end
end

local visibleRows: { Entry } = {}
-- Staggered reveal of the first rows (25 ms apart): each card slides in from the right edge of the
-- sheet (open) or rises a few px (filter change) while its veil fades. Serial-guarded against taps.
local revealSerial = 0
local function revealRows(fromSide: boolean)
	revealSerial += 1
	local mine = revealSerial
	local n = #visibleRows
	for i, e in visibleRows do
		local r = e.row
		if r and r.card then
			r.card.Position = UDim2.new()
			r.veil.BackgroundTransparency = 1
		end
		local _ = i
	end
	if reducedMotion() then
		return
	end
	for i = 1, math.min(n, 9) do
		local r = visibleRows[i].row
		if r and r.card then
			r.card.Position = if fromSide then UDim2.fromOffset(28 + i * 4, 0) else UDim2.fromOffset(0, 10)
			r.veil.BackgroundTransparency = 0
			task.delay((i - 1) * 0.025 + (if fromSide then 0.06 else 0), function()
				if revealSerial ~= mine then
					return
				end
				tw(r.card, 0.34, { Position = UDim2.new() }, Enum.EasingStyle.Quint)
				tw(r.veil, 0.26, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			end)
		end
	end
end
local function applyFilter(animate: any)
	refreshChips()
	table.clear(visibleRows)
	if remoteState ~= "ready" then
		for _, e in entries do
			if e.row then
				e.row.row.Visible = false
			end
		end
		setState(remoteState)
		return
	end
	local q = norm(query)
	local wp, hp = workPlace(), homePlace()
	local pos = myPosition()
	for _, e in entries do
		if pos and e.x and e.z then
			e.dist = Vector2.new(pos.X - e.x, pos.Z - e.z).Magnitude
		else
			e.dist = nil
		end
		local isWork = placeMatches(e, wp)
		local isHome = placeMatches(e, hp)
		local catOk = category == "all" or e.cat == category or (category == "work" and isWork) or (category == "home" and isHome)
		local qOk = q == "" or string.find(e.norm, q, 1, true) ~= nil or string.find(norm((CAT_BY_ID[e.cat] or CATS[1]).label), q, 1, true) ~= nil
		local show = catOk and qOk
		local r = e.row
		if r then
			r.row.Visible = show
			if show then
				K.setText(r.subtitle, subtitleFor(e, isWork, isHome))
				local pending = e.id == pendingId
				K.setText(r.trailing, if pending then "이동 중…" elseif e.dist then distText(e.dist * STUD_M) else "")
				r.trailing.TextColor3 = if pending then CYAN else C.text
				if (r.pendingOn == true) ~= pending then
					r.pendingOn = pending
					setPendingSweep(r, pending)
				end
				K.setText(r.walk, if e.dist and not pending then walkText(e.dist) else "")
				-- pin work / home at the top of 전체
				local pin = if isWork then -2 elseif isHome then -1 else 0
				e.row.pin = pin
				table.insert(visibleRows, e)
			end
		end
	end
	table.sort(visibleRows, function(a, b)
		local pa, pb = a.row.pin or 0, b.row.pin or 0
		if pa ~= pb then
			return pa < pb
		end
		if a.dist and b.dist and a.dist ~= b.dist then
			return a.dist < b.dist
		end
		if (a.dist ~= nil) ~= (b.dist ~= nil) then
			return a.dist ~= nil
		end
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.name < b.name
	end)
	for i, e in visibleRows do
		e.row.row.LayoutOrder = i
	end
	if #visibleRows == 0 then
		if category == "work" and wp == "" and q == "" then
			setState("work")
		elseif category == "home" and hp == "" and q == "" then
			setState("home")
		elseif q ~= "" then
			setState("search")
		else
			setState("empty")
		end
	else
		setState(nil)
	end
	local n = #visibleRows
	if pendingId == nil then
		K.setText(U.sheetSub, if n > 0 then string.format("%d곳 · %s", n, if myPosition() then "가까운 순" else "추천 순") else SUBTITLE_DEFAULT)
	end
	if animate then
		revealRows(animate == "open")
	end
end

local function parseEntries()
	local raw = travelRemote and travelRemote:GetAttribute("Destinations")
	local decoded: any = nil
	if type(raw) == "string" and raw ~= "" then
		local ok, d = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(d) == "table" then
			decoded = d
		end
	end
	local out: { Entry } = {}
	if decoded then
		for i, e in decoded do
			if type(e) == "table" and type(e.id) == "string" then
				local name = if type(e.name) == "string" then e.name else e.id
				local main, detail = splitName(name)
				table.insert(out, {
					id = e.id,
					name = name,
					main = main,
					detail = detail,
					order = if type(e.order) == "number" then e.order else 1000 + i,
					x = if type(e.x) == "number" then e.x else nil,
					z = if type(e.z) == "number" then e.z else nil,
					cat = categoryOf(main, e.cat),
					norm = norm(name),
					row = nil,
				})
			end
		end
	end
	entries = out
	buildRows()
	applyFilter(false)
end

---------------------------------------------------------------------------------------------------
-- Travel sheet: open / close / drag
---------------------------------------------------------------------------------------------------
local openSerial = 0
local statusSerial = 0
local function sheetStatus(message: string?, color: Color3?, seconds: number?)
	statusSerial += 1
	local mine = statusSerial
	if message then
		U.sheetSub.Text = message
		U.sheetSub.TextColor3 = color or C.sub
		task.delay(seconds or 3, function()
			if statusSerial == mine and pendingId == nil then
				U.sheetSub.TextColor3 = C.sub
				applyFilter(false)
			end
		end)
	else
		U.sheetSub.TextColor3 = C.sub
		applyFilter(false)
	end
end

local function setSearchMode(on: boolean)
	searchMode = on
	if lastInfo then
		layoutSheet(lastInfo)
	end
	if on then
		pcall(function()
			U.searchBox:CaptureFocus()
		end)
	else
		pcall(function()
			U.searchBox:ReleaseFocus()
		end)
		if query ~= "" then
			U.searchBox.Text = ""
		end
	end
end

local function setSheet(open: boolean, reason: string?)
	if open == sheetOpen then
		return
	end
	sheetOpen = open
	openSerial += 1
	local mine = openSerial
	-- closing: the sheet keeps its draw order and the other HUD layers stay aside until it has slid
	-- out, then everything glides back (see the delayed block below)
	sheetClosing = not open
	if open then
		gui:SetAttribute("HideGwangalliHUD", true)
		gui.DisplayOrder = SHEET_ORDER
	end
	gui:SetAttribute("SheetOpenRight", open and slideAxis == "x")
	gui:SetAttribute("SheetLeft", math.floor(sheetRect.x + probe.AbsolutePosition.X))
	-- the 이동 button lights up while its sheet is open (visible on PC, where the sheet is a panel)
	U.travelAction.fill.Enabled = open
	travelButton.BackgroundColor3 = if open then Color3.new(1, 1, 1) else C.glass
	travelButton.BackgroundTransparency = if open then 0 else (K.GLASS_T or 0.14)
	U.travelAction.caption.TextColor3 = if open then (C.onAccent or Color3.fromRGB(4, 22, 32)) else C.text
	local info = lastInfo
	if open then
		if info then
			layoutSheet(info)
		end
		local target = UDim2.fromOffset(sheetRect.x, sheetRect.y)
		-- slide in with a small overshoot past the resting edge, then settle (two-stage spring)
		local past = if slideAxis == "y" then UDim2.fromOffset(sheetRect.x, sheetRect.y - 10) else UDim2.fromOffset(sheetRect.x - 12, sheetRect.y)
		-- a re-open while the sheet is still sliding out continues from where it is
		if not sheet.Visible then
			sheet.Position = sheetFrom
		end
		sheet.Visible = true
		spring(sheet, 0.42, { Position = past }, { Position = target })
		pcall(K.blur, true, "GwangalliTravel")
		if isTouch then
			U.backdrop.Visible = true
			U.backdrop.BackgroundTransparency = 1
			tw(U.backdrop, 0.26, { BackgroundTransparency = 0.5 }, Enum.EasingStyle.Quad)
			if not controlsDisabledByUs then
				controlsDisabledByUs = true
				setControls(false)
			end
		end
		applyFilter("open")
		haptic("light")
	else
		pcall(function()
			U.searchBox:ReleaseFocus()
		end)
		if searchMode then
			searchMode = false
			if info then
				layoutSheet(info)
			end
		end
		springSerial[sheet] = (springSerial[sheet] or 0) + 1 -- stop a running open spring
		tw(sheet, 0.22, { Position = sheetFrom }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		tw(U.backdrop, 0.2, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
		pcall(K.blur, false, "GwangalliTravel")
		task.delay(0.23, function()
			if openSerial == mine then
				sheet.Visible = false
				U.backdrop.Visible = false
				sheet.Position = UDim2.fromOffset(sheetRect.x, sheetRect.y)
				sheetClosing = false
				gui:SetAttribute("HideGwangalliHUD", false)
				gui.DisplayOrder = BASE_ORDER
				refreshVisibility()
			end
		end)
		if controlsDisabledByUs then
			controlsDisabledByUs = false
			-- "other": a full-screen UI took over and owns the character controls now
			if reason ~= "other" then
				setControls(true)
			end
		end
		statusSerial += 1
		U.sheetSub.TextColor3 = C.sub
	end
	refreshVisibility()
end

-- Drag the header (or the grabber) to move the sheet with the finger: towards the edge it follows 1:1,
-- inwards it rubber-bands; release past 30 % of the sheet or with a flick dismisses, else it springs back.
do
	local drag: { input: InputObject, start: Vector3, base: UDim2, last: number, lastT: number, vel: number }? = nil
	local function along(v: Vector3): number
		return if slideAxis == "y" then v.Y else v.X
	end
	U.header.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if not sheetOpen or (t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1) then
			return
		end
		springSerial[sheet] = (springSerial[sheet] or 0) + 1
		drag = { input = input, start = input.Position, base = UDim2.fromOffset(sheetRect.x, sheetRect.y), last = 0, lastT = os.clock(), vel = 0 }
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local d = drag
		if not d then
			return
		end
		if input == d.input or (d.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
			local raw = along(input.Position - d.start)
			local off = if raw >= 0 then raw else -math.sqrt(-raw) * 2.2 -- rubber band inwards
			local now = os.clock()
			local dt = now - d.lastT
			if dt > 0.004 then
				d.vel = d.vel * 0.4 + (raw - d.last) / dt * 0.6
				d.last, d.lastT = raw, now
			end
			sheet.Position = d.base + (if slideAxis == "y" then UDim2.fromOffset(0, off) else UDim2.fromOffset(off, 0))
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local d = drag
		if not d then
			return
		end
		if input == d.input or (d.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
			drag = nil
			local off = along(input.Position - d.start)
			local extent = if slideAxis == "y" then sheetRect.h else sheetRect.w
			if off > extent * 0.3 or (off > 24 and d.vel > 700) then
				setSheet(false)
			elseif sheetOpen then
				local past = if slideAxis == "y" then d.base - UDim2.fromOffset(0, 4) else d.base - UDim2.fromOffset(5, 0)
				spring(sheet, 0.34, { Position = past }, { Position = d.base })
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Travel requests
---------------------------------------------------------------------------------------------------
function requestTravel(e: Entry)
	if not travelRemote then
		sheetStatus("이동 서비스를 준비하는 중이에요", WARN)
		return
	end
	local now = os.clock()
	-- one request in flight, and never faster than the server's spam interval
	if now < pendingUntil or now - lastSent < (travelCfg.SpamInterval or 0.4) + 0.1 then
		haptic("light")
		return
	end
	lastSent = now
	pendingUntil = now + TRAVEL_WAIT
	pendingId = e.id
	statusSerial += 1
	U.sheetSub.Text = e.main .. "(으)로 이동 중…"
	U.sheetSub.TextColor3 = CYAN
	if e.row then
		K.setText(e.row.trailing, "이동 중…")
		e.row.trailing.TextColor3 = CYAN
	end
	haptic("medium")
	travelRemote:FireServer("travel", e.id)
	local mine = e.id
	task.delay(TRAVEL_WAIT, function()
		if pendingId == mine and os.clock() >= pendingUntil - 0.05 then
			pendingId = nil
			pendingUntil = 0
			if sheetOpen then
				sheetStatus("응답이 없어요 · 다시 시도해 주세요", WARN)
			end
		end
	end)
end

local function onTravelResult(ok: boolean, message: string)
	local name = pendingId
	pendingUntil = 0
	pendingId = nil
	if ok then
		setSheet(false)
		local main = if name then (splitName(name)) else ""
		toast("info", "도착했어요", if message ~= "" then message else main, "📍", 3)
		haptic("success")
	else
		local msg = if message ~= "" then message else "이동할 수 없어요"
		if sheetOpen then
			sheetStatus(msg, DANGER, 3)
			haptic("warning")
		else
			toast("warn", "이동할 수 없어요", msg, "🧭")
		end
	end
	applyFilter(false)
end

---------------------------------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------------------------------
for id, chip in chips do
	chip.button.Activated:Connect(function()
		if category ~= id then
			category = id
			list.CanvasPosition = Vector2.zero
			applyFilter("filter")
		end
	end)
end
U.searchToggle.Activated:Connect(function()
	setSearchMode(true)
end)
U.searchCancel.Activated:Connect(function()
	setSearchMode(false)
end)
if U.clearSearch then
	U.clearSearch.Activated:Connect(function()
		U.searchBox.Text = ""
	end)
end
U.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	local t = U.searchBox.Text
	if #t > 40 then
		U.searchBox.Text = string.sub(t, 1, 40)
		return
	end
	query = t
	if U.clearSearch then
		U.clearSearch.Visible = t ~= ""
	end
	list.CanvasPosition = Vector2.zero
	applyFilter(false)
end)
if U.searchStroke then
	local st = U.searchStroke
	U.searchBox.Focused:Connect(function()
		st.Color = CYAN
		st.Transparency = 0.3
	end)
	U.searchBox.FocusLost:Connect(function()
		st.Color = C.line
		st.Transparency = 0.9
	end)
end
travelButton.Activated:Connect(function()
	if not hudHidden then
		setSheet(not sheetOpen)
	end
end)
U.closeButton.Activated:Connect(function()
	setSheet(false)
end)
U.backdrop.InputBegan:Connect(function(input: InputObject)
	local t = input.UserInputType
	if sheetOpen and (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) then
		setSheet(false)
	end
end)
player:GetAttributeChangedSignal("Job"):Connect(function()
	if sheetOpen then
		applyFilter(false)
	end
end)
player:GetAttributeChangedSignal("HomeTier"):Connect(function()
	if sheetOpen then
		applyFilter(false)
	end
end)
player.CharacterAdded:Connect(function()
	if sheetOpen then
		setSheet(false)
	end
end)

-- Other full-screen UIs carry HideGwangalliHUD = true on their enabled ScreenGui ---------------------
local watchedGuis: { [Instance]: { RBXScriptConnection } } = {}
local function updateHidden()
	local hide = false
	for other in watchedGuis do
		if other.Parent and (other :: ScreenGui).Enabled and other:GetAttribute("HideGwangalliHUD") == true then
			hide = true
			break
		end
	end
	if hide ~= hudHidden then
		hudHidden = hide
		if hide then
			setSheet(false, "other")
		end
		refreshVisibility()
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
playerGui.ChildAdded:Connect(watchGui)
playerGui.ChildRemoved:Connect(function(inst)
	local conns = watchedGuis[inst]
	if conns then
		for _, c in conns do
			c:Disconnect()
		end
		watchedGuis[inst] = nil
		updateHidden()
	end
end)
for _, child in playerGui:GetChildren() do
	watchGui(child)
end

setState("loading")
task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("GwangalliTravel", 60)
	if not remote or not remote:IsA("RemoteEvent") then
		remoteState = "error"
		applyFilter(false)
		warn("[GwangalliHUD] ReplicatedStorage.GwangalliTravel missing")
		return
	end
	travelRemote = remote
	remoteState = "ready"
	remote:GetAttributeChangedSignal("Destinations"):Connect(parseEntries)
	remote.OnClientEvent:Connect(function(kind: any, ok: any, message: any)
		if kind == "result" then
			onTravelResult(ok == true, if type(message) == "string" then message else "")
		end
	end)
	parseEntries()
	if #entries == 0 then
		-- the server publishes the list a moment after it creates the remote
		task.delay(10, function()
			if #entries == 0 and sheetOpen then
				applyFilter(false)
			end
		end)
	end
end)
if not G then
	task.spawn(function()
		local m = ReplicatedStorage:WaitForChild("GwangalliGameplayShared", 20)
		if m and not G then
			G = optionalModule("GwangalliGameplayShared")
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Keyboard / gamepad
---------------------------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	local key = input.KeyCode
	if sprintKeys[key] then
		-- sprint keys are honoured even when another binding saw them, but never while typing
		if UserInputService:GetFocusedTextBox() then
			return
		end
		if sprintCfg.KeyMode == "toggle" then
			setSprintToggled(not sprintToggled)
		else
			sprintHeld = true
			applySprint()
		end
		return
	end
	if processed then
		return
	end
	if key == sprintCfg.GamepadToggle then
		setSprintToggled(not sprintToggled)
	elseif key == hudCfg.TravelKey and not hudHidden then
		setSheet(not sheetOpen)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if sprintKeys[input.KeyCode] and sprintCfg.KeyMode ~= "toggle" and sprintHeld then
		sprintHeld = false
		applySprint()
	end
end)

-- losing focus (alt-tab) never delivers InputEnded: drop a held sprint
UserInputService.WindowFocusReleased:Connect(function()
	if sprintHeld then
		sprintHeld = false
		applySprint()
	end
end)

---------------------------------------------------------------------------------------------------
-- Clock / date / weather + drone chip (2 Hz; labels are written only when their text changes)
---------------------------------------------------------------------------------------------------
local PHASE = {
	Dawn = { name = "새벽", icon = "🌄", color = Color3.fromRGB(255, 150, 120), weather = "맑음 19°" },
	Day = { name = "낮", icon = "☀️", color = GOLD, weather = "맑음 26°" },
	Sunset = { name = "해질녘", icon = "🌅", color = Color3.fromRGB(255, 120, 90), weather = "맑음 24°" },
	Night = { name = "밤", icon = "🌙", color = Color3.fromRGB(110, 120, 255), weather = "맑은 밤 22°" },
}
local KOR_DAYS = { "일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일" }
local lastPhase = ""

-- Game date: absolute in-game hours = serverTime * rate + base, with base chosen so the hours match
-- the server clock (continuous, identical on every server while the rate stays the same).
local function gameDate(): { month: number, day: number, wday: number }?
	local ws = workspace
	local t0 = ws:GetAttribute(A.ClockAnchorTime)
	local c0 = ws:GetAttribute(A.ClockAnchorClock)
	local rate = ws:GetAttribute(A.ClockRate)
	local t: any = nil
	if type(t0) == "number" and type(c0) == "number" and type(rate) == "number" and rate > 0 then
		local now = ws:GetServerTimeNow()
		local hours = now * rate + c0 - (t0 * rate) % 24
		local dayIndex = math.floor(hours / 24)
		local ok, d = pcall(os.date, "!*t", (dayIndex % 146097) * 86400) -- 400-year cycle keeps the year small
		if ok then
			t = d
		end
	end
	if type(t) ~= "table" then
		local ok, d = pcall(os.date, "*t")
		t = if ok then d else nil
	end
	if type(t) == "table" and type(t.month) == "number" then
		return { month = t.month, day = t.day, wday = t.wday }
	end
	return nil
end

local pulse = TweenService:Create(U.droneDot, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.75 })
local pulsing = false
local liveToasted = false

-- the richest text variant that fits `width` px at `size`
local function fit(variants: { string }, size: number, width: number): string
	for _, v in variants do
		if textWidth(v, size) <= width then
			return v
		end
	end
	return variants[#variants]
end

local line2Pill: boolean? = nil
local line2Serial = 0
local function refreshClock()
	local clock = Shared.clockNow()
	K.setText(U.clockLabel, Shared.formatClock(clock))
	local phaseId = Shared.phaseForClock(clock)
	local ph = PHASE[phaseId] or PHASE.Day
	if phaseId ~= lastPhase then
		lastPhase = phaseId
		U.phaseGlyph.Text = ph.icon
		local grad = U.phaseTile:FindFirstChildOfClass("UIGradient")
		if grad then
			local hh, ss, vv = ph.color:ToHSV()
			grad.Color = ColorSequence.new(Color3.fromHSV(hh, math.max(0, ss - 0.1), math.min(1, vv + 0.1)), Color3.fromHSV(hh, math.min(1, ss + 0.1), vv * 0.75))
		end
	end
	local d = gameDate()
	local day = if d then KOR_DAYS[d.wday] or "" else ""
	K.setText(U.dayLabel, if d then fit({ string.format("%d월 %d일 %s", d.month, d.day, day), string.format("%d.%d %s", d.month, d.day, day), day }, 13, lineWidth) else "광안리")
	K.setText(U.weatherLabel, fit({ ph.name .. " · " .. ph.weather, ph.name .. " · " .. string.match(ph.weather, "%-?%d+°") or ph.name, ph.name }, 12, lineWidth))

	-- drone show / terrain pill (line 2): always while live / loading, else 3 s out of every 8
	local ready = workspace:GetAttribute(A.TerrainReady) == true
	local live = false
	local label = ""
	if not ready then
		local progress = workspace:GetAttribute("GwangalliTerrainProgress")
		label = if type(progress) == "number" then string.format("지형 %d%%", math.floor(math.clamp(progress, 0, 1) * 100)) else "지형 준비 중"
	else
		local active = Shared.droneShowState()
		if active then
			live = true
			label = "드론쇼 LIVE"
		else
			local nextClock = Shared.nextShowClock(clock)
			if nextClock then
				local t = Shared.formatClock(nextClock)
				label = fit({ "🚁 드론쇼 " .. t, "🚁 " .. t }, 11, lineWidth - 10)
			end
		end
	end
	if live and not liveToasted then
		liveToasted = true
		toast("info", "광안리 M 드론라이트쇼 시작!", "해변에서 바다 쪽 하늘을 보세요", "🚁", 4)
	elseif not live then
		liveToasted = false
	end
	droneText = label
	local urgent = live or not ready
	local showPill = label ~= "" and (urgent or (os.clock() % 8) >= 5)
	K.setText(U.droneLabel, label)
	U.droneDot.Visible = urgent
	U.droneLabel.Position = UDim2.fromOffset(if urgent then 15 else 7, 0)
	U.droneLabel.Size = UDim2.new(1, if urgent then -19 else -11, 1, 0)
	U.dronePill.Size = UDim2.fromOffset(math.min(lineWidth + 2, textWidth(label, 11) + (if urgent then 22 else 14)), 17)
	-- kit status-pill look: the state colour as a translucent tint, text in a light shade of it
	local tint = if live then LIVE elseif not ready then CYAN else GOLD
	U.dronePill.BackgroundColor3 = tint
	U.dronePill.BackgroundTransparency = if live then 0.55 else 0.8
	U.droneLabel.TextColor3 = if live then Color3.new(1, 1, 1) else tint:Lerp(Color3.new(1, 1, 1), 0.35)
	U.droneDot.BackgroundColor3 = if live then Color3.new(1, 1, 1) else tint
	if showPill ~= line2Pill then
		line2Pill = showPill
		local inc: GuiObject = if showPill then U.dronePill else U.weatherLabel
		local out: GuiObject = if showPill then U.weatherLabel else U.dronePill
		local incRest = if showPill then UDim2.fromOffset(0, 1) else UDim2.fromOffset(2, 1)
		local outRest = if showPill then UDim2.fromOffset(2, 1) else UDim2.fromOffset(0, 1)
		line2Serial += 1
		local mine = line2Serial
		if reducedMotion() or not clockChip.Visible then
			inc.Position, inc.Visible = incRest, true
			out.Position, out.Visible = outRest, false
		else
			inc.Visible = true
			inc.Position = incRest + UDim2.fromOffset(0, 19)
			tw(inc, 0.42, { Position = incRest }, Enum.EasingStyle.Quint)
			tw(out, 0.3, { Position = outRest - UDim2.fromOffset(0, 19) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.31, function()
				if line2Serial == mine then
					out.Visible = false
					out.Position = outRest
				end
			end)
		end
	end
	U.clockStroke.Color = if live then LIVE else C.line
	U.clockStroke.Transparency = if live then 0.45 else 0.88
	if urgent ~= pulsing then
		pulsing = urgent
		if pulsing and not reducedMotion() then
			pulse:Play()
		else
			pulse:Cancel()
			U.droneDot.BackgroundTransparency = 0
		end
	end
end

local ticks = 0
while true do
	local ok, err = pcall(refreshClock)
	if not ok then
		warn("[GwangalliHUD] " .. tostring(err))
		task.wait(2)
	end
	ticks += 1
	if ticks % 2 == 0 then
		local okJump, errJump = pcall(checkLayoutDrift)
		if not okJump then
			warn("[GwangalliHUD] layout: " .. tostring(errJump))
		end
		if sheetOpen and pendingId == nil then
			-- PC players may walk with the sheet open: keep distances / order fresh (1 Hz)
			pcall(applyFilter, false)
		end
	end
	task.wait(0.5)
end
