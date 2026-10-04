-- GwangalliPhone/Phone: the smartphone shell, built with the GwangalliUI kit and placed with the
-- GwangalliLayout slot contract.
--   * GwangalliPhoneHUD (ScreenGui, always on, DisplayOrder 6): the 폰 button ("rightColumn.phone"
--     slot, directly above GwangalliHUD's 이동 / 달리기), the money chip ("topLeftChips", Overlay),
--     the shift / tracker card ("topRight", Overlay + Tracker) and the objective arrow.
--   * GwangalliToasts (ScreenGui, DisplayOrder 40): the one toast stack of the game ("toasts" slot);
--     every client script pushes through GwangalliUI.toast(). While the phone is out, notifications
--     drop down inside the phone screen instead.
--   * GwangalliPhone (ScreenGui, Enabled only while the phone is out, DisplayOrder 30,
--     HideGwangalliHUD = true): a modern full-screen phone (punch hole, thin bezel, status bar with
--     the game clock / LTE / battery, Gwangan Bridge night wallpaper made of frames), a home screen
--     (widget row: clock / next shift / rent, app grid + dock with badges) and the apps.
--
-- Layout ("sheetRight" slot, re-done on every Layout.changed):
--   phone landscape : right ~42 % x full usable height, "⌂ 홈" / "✕ 닫기" pills left of it
--   phone portrait  : centred, "닫기" pill below it
--   tablet / PC     : fixed 360 x 740 logical device (UIScale) on the right
--   Touch devices treat the phone as modal (dim backdrop + blur on mid / high tier; the character
--   controls are disabled while it is out and always restored on close or when another full-screen
--   UI takes over and later closes). On PC the character keeps moving; P toggles the phone.
-- Performance: everything is built once (apps lazily on first open); updates are event driven; the
-- only loops are the 1 Hz status clock while the phone is out and the Tracker's 10 Hz marker.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))
local Data = require(script.Parent:WaitForChild("Data"))
local Dest = require(script.Parent:WaitForChild("Dest"))
local Net = require(script.Parent:WaitForChild("Net"))
local Tracker = require(script.Parent:WaitForChild("Tracker"))
local Life = require(script.Parent:WaitForChild("Life"))
local Overlay = require(script.Parent:WaitForChild("Overlay"))
local AppKit = require(script.Parent:WaitForChild("AppKit"))

local player = Players.LocalPlayer

local Phone = {}

local K: any = nil
local Layout: any = nil

-- Optional shared modules -------------------------------------------------------------------------------
local function optionalModule(name: string, wait: number): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, wait)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
	end
	return nil
end
local Quality: any = nil
local WorldShared: any = nil

-- Settings (per session; the kit's feedback settings live in K.settings) --------------------------------
local settings = { sound = true, banners = true, marker = true, haptics = true, quality = "auto" }

-- App registry --------------------------------------------------------------------------------------------
local APP_META = {
	call = { title = "전화", glyph = "📞", c1 = Color3.fromRGB(96, 236, 150), c2 = Color3.fromRGB(22, 168, 106), module = "Call", server = true },
	messages = { title = "메시지", glyph = "💬", c1 = Color3.fromRGB(255, 222, 96), c2 = Color3.fromRGB(255, 164, 36), module = "Messages", server = true },
	map = { title = "지도", glyph = "📍", c1 = Color3.fromRGB(96, 226, 250), c2 = Color3.fromRGB(28, 140, 200), module = "Map", server = false },
	bank = { title = "통장", glyph = "🏦", c1 = Color3.fromRGB(150, 124, 255), c2 = Color3.fromRGB(70, 96, 240), module = "Bank", server = true },
	jobs = { title = "알바", glyph = "💼", c1 = Color3.fromRGB(255, 208, 96), c2 = Color3.fromRGB(255, 128, 48), module = "Jobs", server = true },
	realty = { title = "부동산", glyph = "🏠", c1 = Color3.fromRGB(70, 222, 206), c2 = Color3.fromRGB(28, 112, 172), module = "Realty", server = true },
	profile = { title = "내 정보", glyph = "👤", c1 = Color3.fromRGB(255, 104, 176), c2 = Color3.fromRGB(150, 96, 250), module = "Profile", server = true },
	shop = { title = "쇼핑", glyph = "🛍️", c1 = Color3.fromRGB(255, 150, 90), c2 = Color3.fromRGB(240, 70, 140), module = "Shop", server = true },
	settings = { title = "설정", glyph = "⚙️", c1 = Color3.fromRGB(134, 140, 160), c2 = Color3.fromRGB(58, 62, 78), module = "Settings", server = false },
	-- taxi: on the home screen and opened from 전화 (광안 콜택시); camera: photo mode
	taxi = { title = "택시", glyph = "🚕", c1 = Color3.fromRGB(255, 214, 70), c2 = Color3.fromRGB(230, 150, 20), module = "Taxi", server = true },
	people = { title = "인맥", glyph = "💞", c1 = Color3.fromRGB(255, 120, 190), c2 = Color3.fromRGB(200, 60, 140), module = "People", server = false },
	camera = { title = "카메라", glyph = "📷", c1 = Color3.fromRGB(150, 156, 176), c2 = Color3.fromRGB(62, 66, 82), module = "Camera", server = false },
}
local GRID_APPS = { "people", "jobs", "realty", "taxi", "shop", "profile", "camera", "settings" }
local DOCK_APPS = { "call", "messages", "map", "bank" }
local KIND_APP = { message = "messages", taxi = "taxi", money = "bank", pay = "bank", stat = "profile", job = "jobs", home = "realty", quest = "messages" }

local apps: { [string]: any } = {}
local roots: { [string]: Frame } = {}
local bodies: { [string]: Frame } = {}
local built: { [string]: boolean } = {}
local iconBadges: { [string]: { any } } = {}
local badgeCounts: { [string]: number } = {}

-- State ---------------------------------------------------------------------------------------------------
local isOpen = false
local openSerial = 0
local current: string? = nil
local hiddenByOther = false
local photoMode = false
local controlsDisabledByUs = false
local restoreControlsLater = false
local isTouch = false
local startClock = os.clock()

local L = {
	mode = "phoneL",
	W = 740,
	H = 302,
	s = 1,
	fw = 300,
	fh = 290,
	statusH = 24,
	bottom = 14,
	headerH = 44,
	bezel = 4,
	radius = 24,
	screenW = 292,
	screenH = 282,
	btn = 56,
	hudScale = 1,
}
local layoutListeners: { () -> () } = {}

-- GUI references (built in build())
local playerGui: PlayerGui
local hudGui: ScreenGui
local hudProbe: Frame
local phoneBtn: TextButton
local phoneBtnBadge: any
local phoneGlow: UIStroke? = nil
local phoneBtnScale: UIScale
local toastGui: ScreenGui
local toaster: any
local phoneGui: ScreenGui
local phoneProbe: Frame
local backdrop: Frame
local closeBig: TextButton
local homeBig: TextButton
local device: Frame
local deviceScale: UIScale
local deviceCorner: UICorner
local screen: Frame
local screenCorner: UICorner
local wallpaper: Frame
local homeFrame: Frame
local widgetRow: Frame
local widgets: { [string]: any } = {}
local grid: Frame
local gridLayout: UIGridLayout
local dock: Frame
local dockLayout: UIGridLayout
local appHost: Frame
local connBar: TextLabel
local headsUp: any
local statusBar: Frame
local statusTime: TextLabel
local statusBattery: TextLabel
local batteryFill: Frame
local punch: Frame
local homeBar: TextButton
local homePill: Frame
local iconCells: { any } = {}
local covers: { [string]: Frame } = {}
local launchSerial = 0
local photoGui: ScreenGui

---------------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------------
local function clockNow(): number
	if WorldShared and type(WorldShared.clockNow) == "function" then
		local ok, c = pcall(WorldShared.clockNow)
		if ok and type(c) == "number" then
			return c
		end
	end
	return Lighting.ClockTime
end

local function getControls(): any
	local ps = player:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if not (pm and pm:IsA("ModuleScript")) then
		return nil
	end
	local ok, mod = pcall(require, pm)
	if not ok or type(mod) ~= "table" or type(mod.GetControls) ~= "function" then
		return nil
	end
	local ok2, controls = pcall(mod.GetControls, mod)
	return if ok2 then controls else nil
end

local function setControls(enabled: boolean)
	local controls = getControls()
	if not controls then
		return
	end
	pcall(function()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

local function sumBadges(): number
	return (badgeCounts.messages or 0) + (badgeCounts.taxi or 0) + (badgeCounts.jobs or 0) + (badgeCounts.realty or 0)
end

local function setBadge(appId: string, n: any)
	local count = if type(n) == "number" then math.max(0, math.floor(n)) elseif n then 1 else 0
	badgeCounts[appId] = count
	for _, b in iconBadges[appId] or {} do
		b.set(if appId == "realty" and count > 0 then "!" else count)
	end
	if phoneBtnBadge then
		phoneBtnBadge.set(sumBadges())
	end
	local glow = phoneGlow
	if glow then
		local unread = sumBadges() > 0
		K.breathe(glow, unread, 0.3, 0.85)
		if not unread then
			K.tween(glow, 0.3, { Transparency = 1 })
		end
	end
end

---------------------------------------------------------------------------------------------------------
-- Wallpaper: Gwangan Bridge at night (frames + gradients only; every element uses Scale so it fits any
-- screen). Sky, drifting glows, skyline, LED bridge with its reflections, shore, legibility scrims.
---------------------------------------------------------------------------------------------------------
local wallFx = { glows = {} :: { any }, stars = {} :: { Frame }, streaks = {} :: { Frame }, serial = 0, scene = nil :: Frame? }

-- Layers are ordered with explicit sibling ZIndex (never by creation order).
local function buildWallpaper(parent: Instance): Frame
	local frame, make = K.frame, K.make
	local WHITE = Color3.new(1, 1, 1)
	local function kp(t: number, c: Color3): ColorSequenceKeypoint
		return ColorSequenceKeypoint.new(t, c)
	end
	local function ns(list: { { number } }): NumberSequence
		local k = {}
		for _, p in list do
			table.insert(k, NumberSequenceKeypoint.new(p[1], p[2]))
		end
		return NumberSequence.new(k)
	end
	local wp = frame(parent, { Name = "0Wallpaper", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(4, 6, 20), ZIndex = 1, ClipsDescendants = true })
	local HORIZON = 0.66
	local DECK = HORIZON - 0.03
	local TOP = 0.43
	local T1, T2 = 0.29, 0.71

	-- 1 sky: ink blue -> violet -> a warm magenta glow on the horizon
	local sky = frame(wp, { Name = "Sky", Size = UDim2.fromScale(1, HORIZON + 0.005), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 1 })
	K.gradient(sky, ColorSequence.new({
		kp(0, Color3.fromRGB(3, 5, 18)),
		kp(0.38, Color3.fromRGB(10, 14, 46)),
		kp(0.66, Color3.fromRGB(34, 24, 84)),
		kp(0.86, Color3.fromRGB(96, 40, 118)),
		kp(1, Color3.fromRGB(206, 82, 136)),
	}), 90)

	-- 2 soft glows (three stacked ellipses fake a radial falloff); they drift slowly (parallax)
	local function glow(name: string, cx: number, cy: number, w: number, h: number, color: Color3, strength: number, z: number): Frame
		local g = frame(wp, { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx, cy), Size = UDim2.fromScale(w, h), ZIndex = z })
		-- five nested ellipses, each faded towards its left / right edge: a smooth falloff with no
		-- visible rims
		local fadeX = ns({ { 0, 1 }, { 0.3, 0.35 }, { 0.5, 0 }, { 0.7, 0.35 }, { 1, 1 } })
		for i = 1, 5 do
			local k = 1 - (i - 1) * 0.19
			local e = frame(g, { Name = "L" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(k, k), BackgroundTransparency = 1 - strength * 0.055, BackgroundColor3 = WHITE, ZIndex = z })
			K.corner(e, UDim.new(0.5, 0))
			K.gradient(e, { color, color }, 0, fadeX)
		end
		table.insert(wallFx.glows, { frame = g, cx = cx, cy = cy })
		return g
	end
	glow("GlowBridge", 0.5, DECK - 0.02, 1.25, 0.36, Color3.fromRGB(255, 84, 170), 1.0, 2)
	glow("GlowCyan", 0.12, 0.3, 0.8, 0.3, Color3.fromRGB(61, 214, 245), 0.55, 2)
	glow("GlowViolet", 0.88, 0.16, 0.7, 0.26, Color3.fromRGB(139, 108, 255), 0.6, 2)

	-- 3 stars (a few twinkle)
	local seed = 23
	local function rnd(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	for i = 1, 22 do
		local big = rnd() > 0.82
		local st = frame(wp, { Name = "Star", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.03 + rnd() * 0.94, 0.03 + rnd() * 0.36), Size = UDim2.fromOffset(if big then 3 else 2, if big then 3 else 2), BackgroundTransparency = 0.1 + rnd() * 0.55, BackgroundColor3 = Color3.fromRGB(255, 248, 232), ZIndex = 3 })
		K.corner(st, UDim.new(0.5, 0))
		if i % 4 == 0 then
			table.insert(wallFx.stars, st)
		end
	end

	-- 4 skyline: Marine City / Haeundae towers on the left, Hwangnyeong hills on the right
	local hillA = frame(wp, { Name = "Hill", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.9, HORIZON + 0.03), Size = UDim2.fromScale(0.62, 0.13), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(16, 14, 40), ZIndex = 4 })
	K.corner(hillA, UDim.new(0.5, 0))
	local hillB = frame(wp, { Name = "Hill2", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.66, HORIZON + 0.02), Size = UDim2.fromScale(0.36, 0.07), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(20, 16, 46), ZIndex = 4 })
	K.corner(hillB, UDim.new(0.5, 0))
	local towers = {
		{ 0.015, 0.036, 0.15 }, { 0.05, 0.03, 0.22 }, { 0.083, 0.04, 0.27 }, { 0.126, 0.03, 0.19 },
		{ 0.16, 0.034, 0.24 }, { 0.198, 0.028, 0.13 }, { 0.23, 0.026, 0.09 }, { 0.54, 0.03, 0.05 },
		{ 0.575, 0.024, 0.07 }, { 0.61, 0.03, 0.045 },
	}
	for i, t in towers do
		local tw = frame(wp, { Name = "Tower", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(t[1], HORIZON), Size = UDim2.fromScale(t[2], t[3]), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 4 })
		K.gradient(tw, { Color3.fromRGB(44, 36, 92), Color3.fromRGB(12, 12, 32) }, 90)
		-- lit window columns (warm, fading down)
		local win = frame(tw, { Name = "Windows", Position = UDim2.fromScale(0.22, 0.06), Size = UDim2.fromScale(0.16, 0.86), BackgroundTransparency = 0.5, BackgroundColor3 = Color3.fromRGB(255, 212, 150), ZIndex = 4 })
		K.gradient(win, { WHITE, WHITE }, 90, ns({ { 0, 0 }, { 0.6, 0.5 }, { 1, 1 } }))
		if t[3] > 0.2 then
			local win2 = frame(tw, { Name = "Windows2", Position = UDim2.fromScale(0.6, 0.12), Size = UDim2.fromScale(0.14, 0.7), BackgroundTransparency = 0.62, BackgroundColor3 = Color3.fromRGB(160, 210, 255), ZIndex = 4 })
			K.gradient(win2, { WHITE, WHITE }, 90, ns({ { 0, 0 }, { 1, 1 } }))
			local air = frame(tw, { Name = "AirLight", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(255, 70, 70), ZIndex = 4 })
			if i == 3 then
				table.insert(wallFx.stars, air)
			end
		end
	end

	-- 5 sea
	local sea = frame(wp, { Name = "Sea", Position = UDim2.fromScale(0, HORIZON), Size = UDim2.fromScale(1, 1 - HORIZON), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 5 })
	K.gradient(sea, ColorSequence.new({ kp(0, Color3.fromRGB(40, 22, 74)), kp(0.35, Color3.fromRGB(16, 12, 44)), kp(1, Color3.fromRGB(3, 4, 14)) }), 90)
	local seaGlow = frame(wp, { Name = "SeaGlow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, HORIZON), Size = UDim2.fromScale(0.9, 0.14), BackgroundTransparency = 0.84, BackgroundColor3 = Color3.fromRGB(255, 84, 170), ZIndex = 6 })
	K.corner(seaGlow, UDim.new(0.5, 0))
	K.gradient(seaGlow, { WHITE, WHITE }, 90, ns({ { 0, 0 }, { 1, 1 } }))

	-- 6 the bridge: LED spectrum along the span (cyan -> violet -> magenta -> violet -> cyan)
	local led = ColorSequence.new({
		kp(0, K.Color.cyan),
		kp(0.28, K.Color.violet),
		kp(0.5, K.Color.magenta),
		kp(0.72, K.Color.violet),
		kp(1, K.Color.cyan),
	})
	local function ledAt(x: number): Color3
		local a = math.abs(x - 0.5) * 2 -- 0 centre .. 1 ends
		if a < 0.44 then
			return K.Color.magenta:Lerp(K.Color.violet, a / 0.44)
		end
		return K.Color.violet:Lerp(K.Color.cyan, math.clamp((a - 0.44) / 0.56, 0, 1))
	end
	-- reflections first (below the deck, fading down), a few breathe
	for i = 0, 15 do
		local x = 0.03 + i * 0.0627
		local streak = frame(wp, { Name = "Reflection", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(x, HORIZON + 0.006), Size = UDim2.new(0, if i % 3 == 1 then 3 else 2, 0.1 + (i % 4) * 0.035, 0), BackgroundTransparency = 0.25, BackgroundColor3 = ledAt(x), ZIndex = 6 })
		K.gradient(streak, { WHITE, WHITE }, 90, ns({ { 0, 0.1 }, { 1, 1 } }))
		if i % 3 == 0 then
			table.insert(wallFx.streaks, streak)
		end
	end
	-- deck glow band + LED deck + lower chord
	local deckGlow = frame(wp, { Name = "DeckGlow", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(-0.02, DECK), Size = UDim2.new(1.04, 0, 0, 12), BackgroundTransparency = 0.8, BackgroundColor3 = WHITE, ZIndex = 7 })
	K.gradient(deckGlow, led, 0)
	K.corner(deckGlow, UDim.new(0.5, 0))
	local deck = frame(wp, { Name = "Deck", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(-0.02, DECK), Size = UDim2.new(1.04, 0, 0, 3), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 8 })
	K.gradient(deck, led, 0)
	local chord = frame(wp, { Name = "LowerDeck", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(-0.02, 0, DECK, 5), Size = UDim2.new(1.04, 0, 0, 1), BackgroundTransparency = 0.35, BackgroundColor3 = WHITE, ZIndex = 8 })
	K.gradient(chord, led, 0)
	-- pylons (twin legs + two cross beams + a red beacon)
	for _, tx in { T1, T2 } do
		for _, dx in { -0.011, 0.011 } do
			local leg = frame(wp, { Name = "Pylon", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(tx + dx, TOP), Size = UDim2.new(0, 2, DECK - TOP + 0.035, 0), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 8 })
			K.gradient(leg, { Color3.fromRGB(236, 240, 255), Color3.fromRGB(150, 140, 220) }, 90)
		end
		for _, by in { TOP + 0.025, TOP + 0.1 } do
			frame(wp, { Name = "Beam", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(tx, by), Size = UDim2.new(0.022, 2, 0, 2), BackgroundTransparency = 0.05, BackgroundColor3 = Color3.fromRGB(214, 220, 255), ZIndex = 8 })
		end
		frame(wp, { Name = "Beacon", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(tx, TOP), Size = UDim2.fromOffset(3, 3), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(255, 70, 80), ZIndex = 8 })
	end
	-- main cable (LED dots) + hangers; side spans down to the anchorages
	local function dot(x: number, y: number, color: Color3, big: boolean?)
		local d = frame(wp, { Name = "CableLight", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(if big then 4 else 3, if big then 4 else 3), BackgroundTransparency = if big then 0 else 0.15, BackgroundColor3 = color, ZIndex = 9 })
		K.corner(d, UDim.new(0.5, 0))
	end
	local sag = DECK - TOP - 0.012
	for i = 0, 24 do
		local u = i / 24
		local x = T1 + (T2 - T1) * u
		local y = TOP + sag * (1 - (2 * u - 1) ^ 2)
		dot(x, y, ledAt(x), i % 2 == 0)
		if i > 0 and i < 24 and i % 3 == 0 then
			frame(wp, { Name = "Hanger", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(x, y), Size = UDim2.new(0, 1, DECK - y, 0), BackgroundTransparency = 0.72, BackgroundColor3 = ledAt(x), ZIndex = 8 })
		end
	end
	for i = 1, 7 do
		local u = i / 8
		local xl = T1 - T1 * u
		local xr = T2 + (1 - T2) * u
		local y = TOP + (sag + 0.012) * (u * u)
		dot(xl, y, ledAt(xl), i % 2 == 1)
		dot(xr, y, ledAt(xr), i % 2 == 1)
	end

	-- 7 shore + foam line
	local shore = frame(wp, { Name = "Shore", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.07), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 10 })
	K.gradient(shore, { Color3.fromRGB(44, 30, 50), Color3.fromRGB(14, 10, 20) }, 90)
	local foam = frame(wp, { Name = "Foam", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 0.93), Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0.8, BackgroundColor3 = WHITE, ZIndex = 10 })
	K.gradient(foam, { WHITE, WHITE }, 0, ns({ { 0, 1 }, { 0.3, 0.3 }, { 0.7, 0.3 }, { 1, 1 } }))

	-- 8 legibility scrims (status bar on top, dock at the bottom)
	local top = frame(wp, { Name = "ScrimTop", Size = UDim2.fromScale(1, 0.2), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 11 })
	K.gradient(top, { WHITE, WHITE }, 90, ns({ { 0, 0.55 }, { 1, 1 } }))
	local bottom = frame(wp, { Name = "ScrimBottom", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.3), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 11 })
	K.gradient(bottom, { WHITE, WHITE }, 90, ns({ { 0, 1 }, { 1, 0.45 } }))
	-- the horizon scene (sky gradient, skyline, sea, bridge, shore) lives in one frame that
	-- applyHomeLayout slides / stretches so the bridge always sits in the free band between the app
	-- grid and the dock; stars and the two sky glows stay in screen space above it
	local scene = frame(wp, { Name = "Scene", Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	local keep = { Star = true, GlowCyan = true, GlowViolet = true, ScrimTop = true, ScrimBottom = true, Scene = true }
	for _, c in wp:GetChildren() do
		if not keep[c.Name] then
			c.Parent = scene
		end
	end
	for _, c in wp:GetChildren() do
		if c.Name == "Star" or c.Name == "GlowCyan" or c.Name == "GlowViolet" then
			(c :: Frame).ZIndex = 3
		end
	end
	wallFx.scene = scene
	local _ = make
	return wp
end

-- Slow ambient motion on the home wallpaper (glows drift, a few stars / reflections breathe) while
-- the phone is out and the home screen shows. Nothing on the low tier / reduced motion.
local function startWallpaperFx()
	wallFx.serial += 1
	local mine = wallFx.serial
	if K.reduced() then
		return
	end
	task.spawn(function()
		local phase = 0
		while wallFx.serial == mine and isOpen do
			if homeFrame and homeFrame.Visible then
				phase += 1
				for i, g in wallFx.glows do
					local dx = math.sin(phase * 0.9 + i * 1.7) * 0.035
					local dy = math.cos(phase * 0.7 + i) * 0.012
					K.tween(g.frame, 3.6, { Position = UDim2.fromScale(g.cx + dx, g.cy + dy) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				end
				for i, s in wallFx.stars do
					K.tween(s, 1.6, { BackgroundTransparency = if (phase + i) % 2 == 0 then 0.05 else 0.7 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				end
				for i, s in wallFx.streaks do
					K.tween(s, 1.8, { BackgroundTransparency = if (phase + i) % 2 == 0 then 0.15 else 0.55 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				end
			end
			task.wait(3.6)
		end
	end)
end

---------------------------------------------------------------------------------------------------------
-- App icon: glyph on a gradient squircle with an inner top highlight, a soft drop shadow and a label.
-- ref.center / ref.size (logical px in the screen) are filled by applyHomeLayout (launch zoom origin).
---------------------------------------------------------------------------------------------------------
local function appIcon(parent: Instance, id: string, order: number, withLabel: boolean): any
	local meta = APP_META[id]
	local WHITE = Color3.new(1, 1, 1)
	local cell = K.make("TextButton", { Name = "App_" .. id, BackgroundTransparency = 1, AutoButtonColor = false, Text = "", LayoutOrder = order }, parent)
	local shadow = K.frame(cell, { Name = "IconShadow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.fromOffset(48, 48), BackgroundTransparency = 0.7, BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 1 })
	K.corner(shadow, UDim.new(0.3, 0))
	local icon = K.frame(cell, { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(48, 48), BackgroundTransparency = 0, BackgroundColor3 = WHITE, ZIndex = 2 })
	K.corner(icon, UDim.new(0.27, 0))
	K.gradient(icon, { meta.c1, meta.c2 }, 120)
	local rim = K.stroke(icon, WHITE, 1, 0.35)
	K.gradient(rim, { WHITE, WHITE }, 90, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.45, 0.8), NumberSequenceKeypoint.new(1, 1) }))
	local gloss = K.frame(icon, { Name = "Gloss", Size = UDim2.fromScale(1, 0.55), BackgroundTransparency = 0.8, BackgroundColor3 = WHITE, ZIndex = 2 })
	K.corner(gloss, UDim.new(0.27, 0))
	K.gradient(gloss, { WHITE, WHITE }, 90, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }))
	-- vector glyph (one consistent white silhouette set); emoji only as a fallback
	local glyph: GuiObject = K.Glyph(icon, id, { cut = meta.c1:Lerp(meta.c2, 0.5), zIndex = 3 }) or K.text(icon, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = meta.glyph, TextSize = 24, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	local name = K.text(cell, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 4, 0, 14),
		Text = meta.title,
		TextSize = K.Type.micro,
		Font = K.Font.medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.72,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		Visible = withLabel,
		ZIndex = 2,
	})
	local badge = K.Badge(icon, { size = 18, position = UDim2.new(1, -2, 0, 2) })
	iconBadges[id] = iconBadges[id] or {}
	table.insert(iconBadges[id], badge)
	K.pressable(cell, { veil = false, scale = 0.9 })
	cell.Activated:Connect(function()
		Phone.launch(id)
	end)
	local ref = { id = id, cell = cell, icon = icon, shadow = shadow, glyph = glyph, name = name, dock = not withLabel, center = nil :: Vector2?, size = 48 }
	table.insert(iconCells, ref)
	return ref
end

---------------------------------------------------------------------------------------------------------
-- Home widgets (clock / next shift / rent) + the big lock-screen style clock on tall screens
---------------------------------------------------------------------------------------------------------
local hero: any = nil
local pageDots: Frame
local homeScale: UIScale

local function widget(id: string, order: number, onTap: (() -> ())?): any
	local WHITE = Color3.new(1, 1, 1)
	local b = K.make("TextButton", { Name = "Widget_" .. id, BackgroundTransparency = 0.3, BackgroundColor3 = Color3.fromRGB(12, 14, 32), AutoButtonColor = false, Text = "", LayoutOrder = order }, widgetRow)
	K.corner(b, K.Radius.md)
	local rim = K.stroke(b, WHITE, 1, 0.5)
	K.gradient(rim, { WHITE, WHITE }, 90, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.93) }))
	local icon = K.text(b, { Name = "Icon", Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(16, 16), Text = "", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left })
	local cap = K.text(b, { Name = "Caption", Position = UDim2.fromOffset(28, 8), Size = UDim2.new(1, -36, 0, 16), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.micro, Font = K.Font.bold, TextTruncate = Enum.TextTruncate.AtEnd })
	local value = K.text(b, { Name = "Value", Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -18, 0, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd })
	local sub = K.text(b, { Name = "Sub", Position = UDim2.fromOffset(10, 46), Size = UDim2.new(1, -18, 0, 14), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
	K.pressable(b, { scale = 0.96 })
	if onTap then
		b.Activated:Connect(onTap)
	end
	local ref = { button = b, icon = icon, caption = cap, value = value, sub = sub }
	widgets[id] = ref
	return ref
end

local KOR_DAYS = { "일", "월", "화", "수", "목", "금", "토" }
local function updateWidgets()
	local clock = clockNow()
	local night = clock >= 19 or clock < 6
	local c = widgets.clock
	if c then
		K.setText(c.value, K.clock24(clock))
		local t = os.date("*t")
		K.setText(c.caption, string.format("%d.%d (%s)", t.month, t.day, KOR_DAYS[t.wday] or ""))
		K.setText(c.icon, if night then "🌙" else "☀️")
		K.setText(c.sub, if night then "맑은 밤 · 22°" else "맑음 · 26°")
	end
	if hero then
		K.setText(hero.time, K.clock24(clock))
		local t = os.date("*t")
		K.setText(hero.date, string.format("%d월 %d일 %s요일", t.month, t.day, KOR_DAYS[t.wday] or ""))
		K.setText(hero.weather, if night then "🌙  맑은 밤 · 22°" else "☀️  맑음 · 26°")
	end
	local p = Net.profile
	local j = widgets.job
	if j then
		local job = p.job
		if not Net.hasProfile then
			K.setText(j.caption, "알바")
			K.setText(j.value, "연결 중…")
			K.setText(j.sub, "")
		elseif type(job) == "table" and job.id then
			local w = Net.work
			local on = job.onShift == true or (type(w) == "table" and w.onShift == true)
			K.setText(j.caption, "알바")
			if on then
				local prog = type(w) == "table" and type(w.progress) == "table" and w.progress or nil
				K.setText(j.value, "근무 중")
				j.value.TextColor3 = K.Color.green
				local step = if prog and tonumber(prog.total) then string.format("%d/%d · ", (tonumber(prog.done) or 0), tonumber(prog.total) or 0) else ""
				K.setText(j.sub, step .. K.wonShort(type(w) == "table" and tonumber(w.earnedToday) or 0))
			else
				K.setText(j.value, "출근 가능")
				j.value.TextColor3 = K.Color.text
				K.setText(j.sub, "시급 " .. K.wonShort(tonumber(job.wage) or 0))
			end
		else
			K.setText(j.caption, "알바")
			K.setText(j.value, "구직 중")
			j.value.TextColor3 = K.Color.gold
			local offers = if type(p.offers) == "table" then #p.offers else 0
			K.setText(j.sub, if offers > 0 then string.format("제안 %d건", offers) else "지원하기 ›")
		end
	end
	local r = widgets.rent
	if r then
		local h = p.home
		if not Net.hasProfile then
			K.setText(r.caption, "내 집")
			K.setText(r.value, "연결 중…")
			K.setText(r.sub, "")
		elseif type(h) == "table" and (h.listingId or h.name) then
			local missed = tonumber(h.missed) or 0
			if h.owned then
				K.setText(r.caption, "내 집")
				K.setText(r.value, "자가")
				r.value.TextColor3 = K.Color.teal
				K.setText(r.sub, "관리비 자동")
			elseif missed > 0 then
				K.setText(r.caption, "월세")
				K.setText(r.value, string.format("연체 %d일", missed))
				r.value.TextColor3 = K.Color.red
				K.setText(r.sub, "지금 납부 ›")
			else
				local due = math.max(0, math.floor(tonumber(h.dueIn) or 0))
				K.setText(r.caption, "월세 이체")
				K.setText(r.value, if due >= 3600 then string.format("%d시간 후", due // 3600) elseif due >= 60 then string.format("%d분 후", due // 60) else string.format("%d초 후", due))
				r.value.TextColor3 = K.Color.text
				K.setText(r.sub, K.wonShort(tonumber(h.rentPerDay) or 0) .. "/일")
			end
		else
			K.setText(r.caption, "내 집")
			K.setText(r.value, "집 구하기")
			r.value.TextColor3 = K.Color.teal
			K.setText(r.sub, "고시원부터 ›")
		end
	end
end

local function refreshLifeBadges()
	local p = Net.profile
	local offers = 0
	if type(p.offers) == "table" then
		for _, o in p.offers do
			if type(o) == "table" and (o.kind == "applyJob" or o.kind == "job") then
				offers += 1
			end
		end
	end
	setBadge("jobs", offers)
	local h = p.home
	setBadge("realty", type(h) == "table" and (tonumber(h.missed) or 0) > 0)
end

---------------------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------------------
local function screenGui(name: string, order: number, enabled: boolean): ScreenGui
	return K.make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order,
		Enabled = enabled,
	})
end

local function build()
	local frame, text, make = K.frame, K.text, K.make
	for _, n in { "GwangalliPhoneHUD", "GwangalliPhone", "GwangalliPhotoMode", "GwangalliToasts" } do
		local old = playerGui:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end

	-- HUD layer -----------------------------------------------------------------------------------------
	hudGui = screenGui("GwangalliPhoneHUD", 6, true)
	hudProbe = frame(hudGui, { Name = "AreaProbe", Size = UDim2.fromScale(1, 1), ZIndex = 0 })

	phoneBtn = make("TextButton", { Name = "PhoneButton", Size = UDim2.fromOffset(56, 56), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = K.Color.glass, BackgroundTransparency = K.GLASS_T, AutoButtonColor = false, Text = "", ZIndex = 3 }, hudGui)
	K.corner(phoneBtn, UDim.new(0.5, 0))
	K.stroke(phoneBtn, Color3.new(1, 1, 1), 1, 0.8)
	phoneBtnScale = make("UIScale", { Name = "Scale", Scale = 1 }, phoneBtn)
	-- drawn phone glyph with a bridge-gradient screen
	local body = frame(phoneBtn, { Name = "PhoneGlyph", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 9), Size = UDim2.fromOffset(18, 28), BackgroundTransparency = 0, BackgroundColor3 = K.Color.text, ZIndex = 4 })
	K.corner(body, 5)
	local scr = frame(body, { Name = "Screen", Position = UDim2.fromOffset(2, 3), Size = UDim2.new(1, -4, 1, -6), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 4 })
	K.corner(scr, 3)
	K.gradient(scr, K.Grad.bridge, 125)
	local camDot = frame(body, { Name = "Camera", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(3, 3), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 5 })
	K.corner(camDot, UDim.new(0.5, 0))
	text(phoneBtn, { Name = "Caption", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -5), Size = UDim2.new(1, 0, 0, 13), Text = "폰", TextSize = K.Type.micro, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	phoneBtnBadge = K.Badge(phoneBtn, { size = 18, position = UDim2.new(1, -6, 0, 6) })
	-- unread: a soft cyan ring breathes around the button
	do
		local ring = frame(phoneBtn, { Name = "UnreadGlow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 6, 1, 6), ZIndex = 2 })
		K.corner(ring, UDim.new(0.5, 0))
		phoneGlow = K.stroke(ring, K.Color.cyan, 2, 1)
	end
	K.pressable(phoneBtn, { scale = 0.92, sound = "open" })

	-- Toast layer ----------------------------------------------------------------------------------------
	toastGui = screenGui("GwangalliToasts", 40, true)
	toaster = K.Toaster(toastGui)

	-- Phone layer ---------------------------------------------------------------------------------------
	phoneGui = screenGui("GwangalliPhone", 30, false)
	phoneGui:SetAttribute("HideGwangalliHUD", true) -- GwangalliHUD hides its clock / buttons while we are out
	phoneProbe = frame(phoneGui, { Name = "AreaProbe", Size = UDim2.fromScale(1, 1), ZIndex = 0 })
	backdrop = K.dim(phoneGui, "Backdrop", 1, function()
		Phone.close()
	end)
	backdrop.BackgroundColor3 = Color3.fromRGB(2, 4, 12)
	local function pill(name: string, label: string): TextButton
		local b = K.Button(phoneGui, { name = name, text = label, style = "glass", size = UDim2.fromOffset(104, 48), zIndex = 4, textSize = K.Type.body, radius = 24 })
		K.corner(b, UDim.new(0.5, 0))
		return b
	end
	closeBig = pill("CloseButton", "✕  닫기")
	homeBig = pill("HomeButton", "⌂  홈")
	homeBig.Visible = false

	device = frame(phoneGui, { Name = "Device", Size = UDim2.fromOffset(300, 290), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(7, 8, 12), Active = true, ZIndex = 2 })
	deviceScale = make("UIScale", { Scale = 1 }, device)
	deviceCorner = K.corner(device, 28)
	-- thin brushed-titanium rim: a mid grey stroke shaded by a diagonal gradient (catch lights on
	-- two corners)
	local rim = K.stroke(device, Color3.fromRGB(120, 126, 142), 1.5, 0)
	K.gradient(rim, { Color3.fromRGB(235, 238, 245), Color3.fromRGB(70, 72, 82), Color3.fromRGB(210, 214, 226), Color3.fromRGB(80, 82, 92) }, 35)
	frame(device, { Name = "PowerKey", Position = UDim2.new(1, 1, 0.3, 0), Size = UDim2.new(0, 3, 0.08, 0), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(70, 72, 84) })
	frame(device, { Name = "VolumeKey", Position = UDim2.new(1, 1, 0.14, 0), Size = UDim2.new(0, 3, 0.12, 0), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(70, 72, 84) })
	K.shadow(device, 30, 8, "strong")

	screen = frame(device, { Name = "Screen", Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), BackgroundTransparency = 0, BackgroundColor3 = K.Color.bg, ClipsDescendants = true, ZIndex = 2 })
	screenCorner = K.corner(screen, 24)
	wallpaper = buildWallpaper(screen)
	K.corner(wallpaper, 24)

	-- Home ---------------------------------------------------------------------------------------------
	homeFrame = frame(screen, { Name = "Home", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	homeScale = make("UIScale", { Scale = 1 }, homeFrame)
	-- big clock (tall screens only)
	do
		local h = frame(homeFrame, { Name = "Hero", Size = UDim2.new(1, 0, 0, 100), Visible = false })
		local date = text(h, { Name = "Date", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 18), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextColor3 = Color3.fromRGB(225, 230, 245), TextXAlignment = Enum.TextXAlignment.Center })
		local time = text(h, { Name = "Time", Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 62), Text = "--:--", Font = K.Font.bold, TextSize = 60, TextXAlignment = Enum.TextXAlignment.Center })
		K.mono(time, Enum.FontWeight.SemiBold)
		local weather = text(h, { Name = "Weather", Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 18), Text = "", TextSize = K.Type.caption, TextColor3 = K.Color.sub, TextXAlignment = Enum.TextXAlignment.Center })
		hero = { frame = h, date = date, time = time, weather = weather }
	end
	widgetRow = frame(homeFrame, { Name = "Widgets", Position = UDim2.fromOffset(8, 28), Size = UDim2.new(1, -16, 0, 64) })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, widgetRow)
	widget("clock", 1, nil)
	widget("job", 2, function()
		Phone.launch("jobs")
	end)
	widget("rent", 3, function()
		Phone.launch("realty")
	end)
	K.mono(widgets.clock.value)
	widgets.clock.value.TextSize = K.Type.title
	widgets.job.icon.Text = "💼"
	widgets.rent.icon.Text = "🏠"

	grid = frame(homeFrame, { Name = "Grid", Position = UDim2.fromOffset(8, 96), Size = UDim2.new(1, -16, 0, 80) })
	gridLayout = make("UIGridLayout", {
		CellSize = UDim2.fromOffset(70, 74),
		CellPadding = UDim2.fromOffset(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		FillDirectionMaxCells = 4,
	}, grid)
	for i, id in GRID_APPS do
		appIcon(grid, id, i, true)
	end
	pageDots = frame(homeFrame, { Name = "PageDots", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(26, 6), Visible = false })
	for i = 1, 2 do
		local d = frame(pageDots, { Name = "Dot" .. i, Position = UDim2.fromOffset((i - 1) * 14, 0), Size = UDim2.fromOffset(6, 6), BackgroundTransparency = if i == 1 then 0.05 else 0.65, BackgroundColor3 = Color3.new(1, 1, 1) })
		K.corner(d, UDim.new(0.5, 0))
	end
	dock = frame(homeFrame, { Name = "Dock", Position = UDim2.fromOffset(8, 200), Size = UDim2.new(1, -16, 0, 70), BackgroundTransparency = 0.45, BackgroundColor3 = Color3.fromRGB(26, 28, 52) })
	K.corner(dock, K.Radius.xl)
	do
		local rim = K.stroke(dock, Color3.new(1, 1, 1), 1, 0.5)
		K.gradient(rim, { Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, 90, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.95) }))
	end
	dockLayout = make("UIGridLayout", {
		CellSize = UDim2.fromOffset(70, 60),
		CellPadding = UDim2.fromOffset(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		FillDirectionMaxCells = 4,
	}, dock)
	for i, id in DOCK_APPS do
		appIcon(dock, id, i, false)
	end

	-- Apps host ------------------------------------------------------------------------------------------
	appHost = frame(screen, { Name = "Apps", Size = UDim2.fromScale(1, 1), ZIndex = 3 })

	connBar = text(screen, {
		Name = "Connection",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 28),
		Size = UDim2.fromOffset(140, 22),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = K.Color.card2,
		Text = "연결 중…",
		TextSize = K.Type.micro,
		Font = K.Font.bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 6,
	})
	K.corner(connBar, UDim.new(0.5, 0))

	-- in-phone notifications: a "dynamic island" pill that grows out of the punch hole inside the
	-- status bar (never over an app's header buttons); the content fades in once it has grown, a tap
	-- opens the source app, a swipe up dismisses it
	do
		-- a Frame (Active) rather than a button: the pill is only status-bar tall, so taps and swipes are
		-- read from its input events instead of making it a (too small) tap target
		local island = frame(screen, { Name = "Island", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(12, 20), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(0, 0, 0), Active = true, Visible = false, ZIndex = 10 })
		K.corner(island, UDim.new(0.5, 0))
		local st = K.stroke(island, K.Color.cyan, 1, 0.55)
		local dotBg = frame(island, { Name = "IconDot", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, BackgroundColor3 = K.Color.cyan, ZIndex = 11 })
		K.corner(dotBg, UDim.new(0.5, 0))
		local glyph = text(dotBg, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "", TextSize = 11, TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 })
		local label = text(island, { Name = "Text", Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -32, 1, 0), Text = "", Font = K.Font.bold, TextSize = K.Type.micro, TextTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11 })
		local queue: { any } = {}
		local busy = false
		local currentData: any = nil
		local dismissAt = 0
		local function contentFade(show: boolean)
			local t = if show then 0 else 1
			K.tween(label, if show then 0.18 else 0.1, { TextTransparency = t })
			K.tween(glyph, if show then 0.18 else 0.1, { TextTransparency = t })
			K.tween(dotBg, if show then 0.18 else 0.1, { BackgroundTransparency = if show then 0.75 else 1 })
		end
		local function run()
			if busy then
				return
			end
			busy = true
			task.spawn(function()
				while #queue > 0 and isOpen do
					local d = table.remove(queue, 1)
					currentData = d
					local kind = K.Kinds[d.kind or "info"] or K.Kinds.info
					local col = d.color or kind.color
					st.Color = col
					dotBg.BackgroundColor3 = col
					glyph.Text = d.icon or kind.icon
					label.Text = if d.body and d.body ~= "" then (tostring(d.title) .. " · " .. tostring(d.body)) else tostring(d.title)
					local h = math.max(18, L.statusH - 4)
					island.Size = UDim2.fromOffset(h, h)
					island.Visible = true
					statusTime.Visible = false
					statusBar.Right.Visible = false
					K.spring(island, { Size = UDim2.fromOffset(math.min(L.screenW - 20, 300), h) }, { duration = 0.42, amount = 0.04 })
					task.delay(if K.reduced() then 0 else 0.14, function()
						if currentData == d then
							contentFade(true)
						end
					end)
					dismissAt = os.clock() + (d.duration or 3)
					while os.clock() < dismissAt and isOpen do
						task.wait(0.1)
					end
					contentFade(false)
					K.cancel(island)
					K.tween(island, 0.22, { Size = UDim2.fromOffset(h, h) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
					task.wait(0.24)
					island.Visible = false
					statusTime.Visible = true
					statusBar.Right.Visible = true
				end
				currentData = nil
				busy = false
				island.Visible = false
				statusTime.Visible = true
				statusBar.Right.Visible = true
			end)
		end
		local startY: number? = nil
		island.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				startY = input.Position.Y
			end
		end)
		island.InputEnded:Connect(function(input: InputObject)
			if not startY then
				return
			end
			local dy = input.Position.Y - startY
			startY = nil
			if dy < -10 then
				dismissAt = 0 -- swipe up: dismiss
			elseif math.abs(dy) < 12 then
				local d = currentData
				if d and d.onClick then
					K.feedback("tap")
					task.spawn(d.onClick)
				end
				dismissAt = 0
			end
		end)
		headsUp = {
			push = function(d: any)
				table.insert(queue, d)
				while #queue > 3 do
					table.remove(queue, 1)
				end
				if not d.silent then
					K.feedback(if d.kind == "money" or d.kind == "pay" then "money" else "notify")
				end
				run()
			end,
			clear = function()
				table.clear(queue)
				dismissAt = 0
			end,
		}
	end

	-- Status bar -------------------------------------------------------------------------------------------
	statusBar = frame(screen, { Name = "StatusBar", Size = UDim2.new(1, 0, 0, 24), ZIndex = 8 })
	K.pad(statusBar, 18, 18, 0, 0)
	statusTime = text(statusBar, { Name = "Time", Size = UDim2.new(0.4, 0, 1, 0), Text = "--:--", Font = K.Font.bold, TextSize = K.Type.caption, ZIndex = 8 })
	K.mono(statusTime)
	local right = frame(statusBar, { Name = "Right", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, 0, 1, 0), ZIndex = 8 })
	K.list(right, true, 5, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	text(right, { Name = "Network", Size = UDim2.fromOffset(24, 14), Text = "LTE", Font = K.Font.bold, TextSize = K.Type.micro, LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 8 })
	local bars = frame(right, { Name = "Signal", Size = UDim2.fromOffset(15, 11), LayoutOrder = 2, ZIndex = 8 })
	for i = 1, 4 do
		frame(bars, { Name = "Bar" .. i, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, (i - 1) * 4, 1, 0), Size = UDim2.new(0, 3, i / 4, 0), BackgroundTransparency = if i == 4 then 0.55 else 0, BackgroundColor3 = K.Color.text, ZIndex = 8 })
	end
	statusBattery = text(right, { Name = "BatteryText", Size = UDim2.fromOffset(30, 14), Text = "100%", Font = K.Font.bold, TextSize = K.Type.micro, LayoutOrder = 3, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 8 })
	local batt = frame(right, { Name = "Battery", Size = UDim2.fromOffset(21, 11), LayoutOrder = 4, ZIndex = 8 })
	local shell = frame(batt, { Name = "Shell", Size = UDim2.new(1, -2, 1, 0), ZIndex = 8 })
	K.corner(shell, 3)
	K.stroke(shell, K.Color.text, 1, 0.1)
	batteryFill = frame(shell, { Name = "Fill", Position = UDim2.fromOffset(2, 2), Size = UDim2.new(0.8, -4, 1, -4), BackgroundTransparency = 0, BackgroundColor3 = K.Color.text, ZIndex = 8 })
	K.corner(batteryFill, 1)
	frame(batt, { Name = "Tip", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(2, 5), BackgroundTransparency = 0, BackgroundColor3 = K.Color.text, ZIndex = 8 })

	punch = frame(screen, { Name = "PunchHole", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(11, 11), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 9 })
	K.corner(punch, UDim.new(0.5, 0))
	K.stroke(punch, Color3.fromRGB(40, 40, 50), 1.5, 0)
	local lens = frame(punch, { Name = "Lens", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.35, 0.35), Size = UDim2.fromOffset(3, 3), BackgroundTransparency = 0.4, BackgroundColor3 = Color3.fromRGB(80, 90, 160), ZIndex = 9 })
	K.corner(lens, UDim.new(0.5, 0))

	homeBar = make("TextButton", { Name = "HomeBar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0.6, 0, 0, 44), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", ZIndex = 9 }, screen)
	homePill = frame(screen, { Name = "HomePill", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(0.3, 0, 0, 5), BackgroundTransparency = 0.1, BackgroundColor3 = K.Color.text, ZIndex = 9 })
	K.corner(homePill, UDim.new(0.5, 0))

	-- Photo mode layer ---------------------------------------------------------------------------------------
	photoGui = screenGui("GwangalliPhotoMode", 31, false)
	photoGui:SetAttribute("HideGwangalliHUD", true)
	local exit = K.Button(photoGui, { name = "ExitPhoto", text = "✕  사진 모드 끝내기", style = "glass", position = UDim2.fromOffset(8, 8), size = UDim2.fromOffset(170, 44), textSize = K.Type.bodySm })
	K.corner(exit, UDim.new(0.5, 0))
	exit.Activated:Connect(function()
		Phone.setPhotoMode(false)
	end)
end

---------------------------------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------------------------------
local slideOffset = 400

local function applyHomeLayout()
	local sw, sh = L.screenW, L.screenH
	local short = sh < 420
	local cols = 4
	local side = if short then 8 else 14
	local innerW = sw - side * 2
	local cellW = math.floor(innerW / cols)
	local rows = math.ceil(#GRID_APPS / cols)
	local avail = sh - L.statusH - L.bottom
	local icon, wH, rowGap
	if short then
		icon = math.clamp(math.floor((avail - 40) / 5.3), 40, 48)
		wH = math.clamp(math.floor(avail * 0.215), 50, 62)
		rowGap = 2
	else
		icon = math.clamp(math.floor(cellW * 0.66), 48, 60)
		wH = 74
		rowGap = 10
	end
	local labelH = 14
	local cellH = icon + 7 + labelH
	local dockIcon = icon
	local dockH = dockIcon + (if short then 14 else 22)
	local gridH = rows * cellH + (rows - 1) * rowGap
	-- vertical rhythm: short screens share the spare height between the three blocks; tall screens
	-- stack hero clock / widgets / grid from the top and park the dock at the bottom (iOS style)
	local wy, gy, dy
	if short then
		local spare = math.max(0, avail - wH - gridH - dockH)
		local g1 = math.floor(spare * 0.22)
		local g2 = math.floor(spare * 0.4)
		wy = L.statusH + g1
		gy = wy + wH + g2
		dy = sh - L.bottom - dockH - math.max(2, spare - g1 - g2 - 2)
		hero.frame.Visible = false
		pageDots.Visible = false
	else
		local heroY = L.statusH + 20
		hero.frame.Position = UDim2.fromOffset(0, heroY)
		hero.frame.Size = UDim2.new(1, 0, 0, 100)
		hero.frame.Visible = true
		wy = heroY + 100 + 16
		gy = wy + wH + 22
		dy = sh - L.bottom - dockH - 6
		pageDots.Visible = true
		pageDots.Position = UDim2.new(0.5, 0, 0, dy - 10)
	end
	for _, ref in iconCells do
		local sz = if ref.dock then dockIcon else icon
		ref.size = sz
		ref.icon.Size = UDim2.fromOffset(sz, sz)
		ref.shadow.Size = UDim2.fromOffset(sz - 4, sz - 4)
		ref.shadow.Position = UDim2.new(0.5, 0, 0, if ref.dock then 7 else 6)
		if ref.glyph:IsA("TextLabel") then
			(ref.glyph :: TextLabel).TextSize = math.floor(sz * 0.5)
		end
		ref.icon.Position = UDim2.new(0.5, 0, 0, if ref.dock then math.floor((dockH - 6 - sz) / 2) else 2)
	end
	gridLayout.CellSize = UDim2.fromOffset(cellW, cellH)
	gridLayout.CellPadding = UDim2.fromOffset(0, rowGap)
	gridLayout.FillDirectionMaxCells = cols
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	dockLayout.CellSize = UDim2.fromOffset(math.floor((innerW - 8) / 4), dockH - 6)

	-- widget row: clock + job + rent (short); job + rent under the hero clock (tall)
	widgetRow.Position = UDim2.fromOffset(side, wy)
	widgetRow.Size = UDim2.new(1, -2 * side, 0, wH)
	local avW = innerW - (if short then 16 else 8)
	local clockW = if short then math.floor(avW * 0.36) else 0
	local otherW = math.floor((avW - clockW) / 2)
	widgets.clock.button.Visible = short
	widgets.clock.button.Size = UDim2.fromOffset(clockW, wH)
	widgets.job.button.Size = UDim2.fromOffset(otherW, wH)
	widgets.rent.button.Size = UDim2.fromOffset(otherW, wH)
	for id, w in widgets do
		local tall = wH >= 70
		w.icon.Position = UDim2.fromOffset(10, if tall then 10 else 7)
		w.caption.Position = UDim2.fromOffset(28, if tall then 10 else 7)
		w.value.Position = UDim2.fromOffset(10, if tall then 30 else 24)
		w.sub.Position = UDim2.fromOffset(10, if tall then 52 else 43)
		w.sub.Visible = wH >= 56
		if id == "clock" then
			w.value.TextSize = if tall then K.Type.title else K.Type.title2 + 2
			w.value.Size = UDim2.new(1, -18, 0, if tall then 24 else 20)
		else
			w.value.TextSize = if tall then K.Type.body + 1 else K.Type.caption + 2
		end
	end
	grid.Position = UDim2.fromOffset(side, gy)
	grid.Size = UDim2.new(1, -2 * side, 0, gridH)
	dock.Position = UDim2.fromOffset(side, dy)
	dock.Size = UDim2.new(1, -2 * side, 0, dockH)

	-- wallpaper: scene y 0.43 (pylon tops) lands just under the grid, the horizon (0.66) behind the
	-- dock, so the bridge fills the free band instead of running through the icons
	if wallFx.scene then
		-- short screens: a small bridge glowing through the dock glass keeps the labels clean
		local a = gy + gridH + (if short then -2 else 4)
		local b = dy + math.floor(dockH * (if short then 0.6 else 0.42))
		local h = math.clamp((b - a) / 0.23, sh * 0.45, sh * 1.3)
		local y0 = b - 0.66 * h
		wallFx.scene.Position = UDim2.fromOffset(0, math.floor(y0))
		wallFx.scene.Size = UDim2.new(1, 0, 0, math.ceil(h))
	end

	-- icon centres in screen px (the launch zoom starts / ends there)
	local gi, di = 0, 0
	local dockCellW = math.floor((innerW - 8) / 4)
	local dockX0 = side + (innerW - dockCellW * 4) / 2
	for _, ref in iconCells do
		if ref.dock then
			ref.center = Vector2.new(dockX0 + di * dockCellW + dockCellW / 2, dy + 3 + math.floor((dockH - 6 - dockIcon) / 2) + dockIcon / 2)
			di += 1
		else
			local c, r = gi % cols, gi // cols
			ref.center = Vector2.new(side + c * cellW + cellW / 2, gy + r * (cellH + rowGap) + 2 + icon / 2)
			gi += 1
		end
	end
end

local function areaOf(probe: Frame): Vector2
	local size = probe.AbsoluteSize
	if size.X >= 50 and size.Y >= 50 then
		return size
	end
	local m = Layout.metrics()
	return Vector2.new(m.W, m.H)
end

local function placeToasts()
	if not toaster then
		return
	end
	local r = Layout.rect("toasts")
	local m = Layout.metrics()
	toaster.placeRect(r, m.toastH)
end

local function applyLayout()
	if not phoneGui or not hudGui then
		return
	end
	local m = Layout.metrics()
	local mode = m.class
	isTouch = m.touch
	local phoneArea = areaOf(phoneProbe)
	local W, H = phoneArea.X, phoneArea.Y
	L.mode, L.W, L.H = mode, W, H

	local sheet = Layout.rect("sheetRight")
	local fw, fh, s
	if mode == "phoneL" then
		s = 1
		fw, fh = sheet.w, sheet.h
		L.statusH, L.bottom, L.headerH, L.bezel, L.radius = 24, 12, 44, 4, 24
	elseif mode == "phoneP" then
		s = 1
		fw = sheet.w
		fh = math.min(sheet.h - 60, math.floor(fw * 2.1))
		L.statusH, L.bottom, L.headerH, L.bezel, L.radius = 28, 40, 48, 6, 34
	else
		s = math.max(0.5, sheet.w / 360)
		fw = 360
		fh = math.floor(sheet.h / s)
		L.statusH, L.bottom, L.headerH, L.bezel, L.radius = 30, 40, 48, 7, 40
	end
	L.s, L.fw, L.fh = s, fw, fh
	L.screenW, L.screenH = fw - 2 * L.bezel, fh - 2 * L.bezel

	deviceScale.Scale = s
	device.Size = UDim2.fromOffset(fw, fh)
	deviceCorner.CornerRadius = UDim.new(0, L.radius + L.bezel)
	screen.Position = UDim2.fromOffset(L.bezel, L.bezel)
	screen.Size = UDim2.new(1, -2 * L.bezel, 1, -2 * L.bezel)
	screenCorner.CornerRadius = UDim.new(0, L.radius)
	for _, ch in wallpaper:GetChildren() do
		if ch:IsA("UICorner") then
			ch.CornerRadius = UDim.new(0, L.radius)
		end
	end
	for id, root in roots do
		local rc = root:FindFirstChildOfClass("UICorner")
		if rc then
			rc.CornerRadius = UDim.new(0, L.radius)
		end
		local cv = covers[id]
		local cc = cv and cv:FindFirstChildOfClass("UICorner")
		if cc then
			cc.CornerRadius = UDim.new(0, L.radius)
		end
		local b = bodies[id]
		if b then
			b.Position = UDim2.fromOffset(0, L.statusH)
			b.Size = UDim2.new(1, 0, 1, -(L.statusH + L.bottom))
		end
	end
	statusBar.Size = UDim2.new(1, 0, 0, L.statusH)
	statusTime.TextSize = if L.statusH >= 28 then 13 else 12
	punch.Position = UDim2.new(0.5, 0, 0, math.floor(L.statusH / 2))
	punch.Size = UDim2.fromOffset(if L.statusH >= 28 then 12 else 10, if L.statusH >= 28 then 12 else 10)
	connBar.Position = UDim2.new(0.5, 0, 0, L.statusH + 4)
	homeBar.Size = UDim2.new(0.6, 0, 0, L.bottom)
	homeBar.Visible = mode ~= "phoneL"
	homePill.Position = UDim2.new(0.5, 0, 1, if mode == "phoneL" then -4 else -8)
	homePill.Size = UDim2.new(if mode == "phoneL" then 0.22 else 0.32, 0, 0, if mode == "phoneL" then 4 else 5)
	applyHomeLayout()

	-- device + close button placement (px in the phone gui)
	local pw, ph = fw * s, fh * s
	local closeW, closeH = 104, 48
	if mode == "phoneL" then
		device.AnchorPoint = Vector2.new(0, 0)
		device.Position = UDim2.fromOffset(sheet.x, sheet.y)
		closeBig.AnchorPoint = Vector2.new(1, 0)
		closeBig.Position = UDim2.fromOffset(sheet.x - 12, sheet.y)
		homeBig.AnchorPoint = Vector2.new(1, 0)
		homeBig.Position = UDim2.fromOffset(sheet.x - 12, sheet.y + closeH + 10)
	elseif mode == "phoneP" then
		device.AnchorPoint = Vector2.new(0.5, 0)
		device.Position = UDim2.fromOffset(math.floor(W / 2), sheet.y)
		closeW = 160
		closeBig.AnchorPoint = Vector2.new(0.5, 0)
		closeBig.Position = UDim2.fromOffset(math.floor(W / 2), sheet.y + ph + 8)
	else
		device.AnchorPoint = Vector2.new(0, 0)
		device.Position = UDim2.fromOffset(sheet.x, sheet.y)
		closeBig.AnchorPoint = Vector2.new(1, 0)
		closeBig.Position = UDim2.fromOffset(sheet.x - 14, sheet.y)
		if mode == "pc" then
			closeW, closeH = 100, 44
		end
	end
	closeBig.Size = UDim2.fromOffset(closeW, closeH)
	homeBig.Size = UDim2.fromOffset(closeW, closeH)
	homeBig.Visible = mode == "phoneL"
	slideOffset = if mode == "phoneL" then math.floor(pw + 40) else math.floor(ph + 40)
	backdrop.Visible = isTouch
	-- the dim covers the whole screen (top bar + notch strips included), not just the safe area
	backdrop.Position = UDim2.fromOffset(-m.ox, -m.oy)
	backdrop.Size = UDim2.fromOffset(m.screenW, m.screenH)
	local shadow = phoneGui:FindFirstChild("Device_Shadow")
	if shadow and shadow:IsA("GuiObject") then
		-- phones: the device spans the full height, a drop shadow would spill off screen
		shadow.Visible = mode == "tablet" or mode == "pc"
		for _, l in shadow:GetChildren() do
			if l:IsA("GuiObject") then
				l.Visible = mode == "tablet" or mode == "pc"
			end
		end
	end

	-- HUD layer: phone button in the right column (above 이동 / 달리기)
	local hs = m.s
	L.hudScale = hs
	local slot = Layout.rect("rightColumn.phone")
	L.btn = slot.w
	phoneBtnScale.Scale = slot.w / 56
	phoneBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	phoneBtn.Position = UDim2.fromOffset(slot.x + slot.w / 2, slot.y + slot.h / 2)
	phoneBtn.Size = UDim2.fromOffset(56, 56)
	local caption = phoneBtn:FindFirstChild("Caption") :: TextLabel?
	if caption then
		caption.Text = if mode == "pc" then "폰 P" else "폰"
	end
	local okT, errT = pcall(Tracker.layout, mode, hs)
	if not okT then
		warn("[GwangalliPhone] tracker layout: " .. tostring(errT))
	end
	local okO, errO = pcall(Overlay.layout, mode, hs)
	if not okO then
		warn("[GwangalliPhone] overlay layout: " .. tostring(errO))
	end
	placeToasts()

	for _, fn in layoutListeners do
		task.spawn(fn)
	end
end

---------------------------------------------------------------------------------------------------------
-- Visibility of the HUD layer
---------------------------------------------------------------------------------------------------------
local function refreshHud()
	local show = not hiddenByOther and not photoMode
	phoneBtn.Visible = show and not isOpen and not Overlay.dialogOpen()
	hudGui.Enabled = show
	toastGui.Enabled = not photoMode
	Tracker.setHidden(not show or isOpen, not show or (isOpen and isTouch))
	Overlay.setShown(show, isOpen)
	Overlay.setOtherShown(not hiddenByOther and not photoMode)
end

---------------------------------------------------------------------------------------------------------
-- Status bar / widgets (1 Hz while the phone is out)
---------------------------------------------------------------------------------------------------------
local function updateClock()
	local clock = clockNow()
	UI.setText(statusTime, K.clock24(clock))
	local minutes = (os.clock() - startClock) / 60
	local level = math.clamp(math.floor(100 - minutes * 0.6), 15, 100)
	UI.setText(statusBattery, level .. "%")
	batteryFill.Size = UDim2.new(level / 100, -4 + math.floor(4 * (1 - level / 100)), 1, -4)
	batteryFill.BackgroundColor3 = if level <= 20 then K.Color.red else K.Color.text
	if homeFrame.Visible then
		updateWidgets()
	end
end

local function startClockLoop()
	local mine = openSerial
	task.spawn(function()
		while isOpen and openSerial == mine do
			local ok, err = pcall(updateClock)
			if not ok then
				warn("[GwangalliPhone] clock: " .. tostring(err))
			end
			task.wait(1)
		end
	end)
end

---------------------------------------------------------------------------------------------------------
-- Connection pill inside apps that need the server
---------------------------------------------------------------------------------------------------------
local function refreshConn()
	local need = current ~= nil and APP_META[current] ~= nil and APP_META[current].server == true
	local ready = Net.status == "ready"
	connBar.Visible = isOpen and need and not ready and Net.hasProfile
	connBar.Text = if Net.status == "offline" then "서버 준비 중…" else "연결 중…"
end

---------------------------------------------------------------------------------------------------------
-- Apps
---------------------------------------------------------------------------------------------------------
local ctx: any = nil

-- App header: back chevron (44 px), title (+ subtitle), optional right action.
-- opts {onBack? -> handled, right? (glyph), onRight?, subtitle?}
local function header(body: Instance, title: string, opts: { [string]: any }?): any
	local o = opts or {}
	local h = K.frame(body, { Name = "Header", Size = UDim2.new(1, 0, 0, L.headerH), ZIndex = 4 })
	local back = K.make("TextButton", {
		Name = "Back",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "‹",
		TextSize = 30,
		Font = K.Font.bold,
		TextColor3 = K.Color.cyan,
		ZIndex = 4,
	}, h)
	K.pressable(back, { veil = false, scale = 0.9, sound = "close" })
	local hasSub = o.subtitle ~= nil
	local t = K.text(h, { Name = "Title", Position = UDim2.fromOffset(46, if hasSub then 4 else 0), Size = UDim2.new(1, -100, if hasSub then 0 else 1, if hasSub then 22 else 0), Text = title, Font = K.Font.bold, TextSize = K.Type.title2, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
	local sub = K.text(h, { Name = "Subtitle", Position = UDim2.fromOffset(46, 25), Size = UDim2.new(1, -100, 0, 15), Text = o.subtitle or "", TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4, Visible = hasSub })
	back.Activated:Connect(function()
		if o.onBack and o.onBack() then
			return
		end
		Phone.home()
	end)
	local r: TextButton? = nil
	if o.right then
		r = K.make("TextButton", {
			Name = "Action",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(44, 44),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = o.right,
			TextSize = 18,
			Font = K.Font.bold,
			TextColor3 = K.Color.text,
			ZIndex = 4,
		}, h)
		K.pressable(r :: TextButton, { veil = false, scale = 0.9 })
		if o.onRight then
			(r :: TextButton).Activated:Connect(o.onRight)
		end
	end
	local api = { frame = h, title = t, back = back, right = r, subtitle = sub }
	function api.setSubtitle(s: string?, color: Color3?)
		local has = s ~= nil and s ~= ""
		sub.Visible = has
		sub.Text = s or ""
		sub.TextColor3 = color or K.Color.sub
		t.Position = UDim2.fromOffset(46, if has then 4 else 0)
		t.Size = UDim2.new(1, -100, if has then 0 else 1, if has then 22 else 0)
	end
	return api
end

local function ensureBuilt(id: string): boolean
	if built[id] then
		return apps[id] ~= nil
	end
	built[id] = true
	local meta = APP_META[id]
	local appsFolder = script.Parent:FindFirstChild("Apps")
	local m = appsFolder and appsFolder:FindFirstChild(meta.module)
	if not (m and m:IsA("ModuleScript")) then
		warn("[GwangalliPhone] app module missing: " .. meta.module)
		return false
	end
	local okReq, ctor = pcall(require, m)
	if not okReq or type(ctor) ~= "function" then
		warn("[GwangalliPhone] app " .. id .. " failed to load: " .. tostring(ctor))
		return false
	end
	local root = K.frame(appHost, { Name = "App_" .. id, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = K.Color.bg, Visible = false, ZIndex = 3 })
	K.corner(root, L.radius)
	local body = K.frame(root, { Name = "Body", Position = UDim2.fromOffset(0, L.statusH), Size = UDim2.new(1, 0, 1, -(L.statusH + L.bottom)), ZIndex = 3 })
	roots[id] = root
	bodies[id] = body
	-- launch cover: the app icon blown up to the full screen; it fades out while the app zooms in from
	-- its home-screen icon (and back in when the app shrinks into the icon again)
	do
		local cover = K.frame(root, { Name = "LaunchCover", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 90, Visible = false })
		K.corner(cover, L.radius)
		K.gradient(cover, { meta.c1, meta.c2 }, 120)
		local gs = math.floor(math.min(L.screenW, L.screenH) * 0.3)
		local vg = K.Glyph(cover, id, { cut = meta.c1:Lerp(meta.c2, 0.5), zIndex = 91, size = UDim2.fromOffset(gs, gs) })
		if vg then
			for _, d in vg:GetDescendants() do
				if d:IsA("Frame") then
					d.BackgroundTransparency = 1
				end
			end
		else
			local g = K.text(cover, { Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.5, 0.5), Text = meta.glyph, TextScaled = true, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1, ZIndex = 91 })
			K.make("UIAspectRatioConstraint", { AspectRatio = 1 }, g)
		end
		covers[id] = cover
	end
	local okNew, app = pcall(ctor, ctx)
	if not okNew or type(app) ~= "table" then
		warn("[GwangalliPhone] app " .. id .. " failed: " .. tostring(app))
		return false
	end
	apps[id] = app
	if type(app.build) == "function" then
		local okBuild, err = pcall(app.build, body, root)
		if not okBuild then
			warn("[GwangalliPhone] app " .. id .. " build failed: " .. tostring(err))
		end
	end
	return true
end

local function callApp(id: string, fn: string, ...: any): any
	local app = apps[id]
	if app and type(app[fn]) == "function" then
		local ok, res = pcall(app[fn], ...)
		if not ok then
			warn(string.format("[GwangalliPhone] %s.%s: %s", id, fn, tostring(res)))
			return nil
		end
		return res
	end
	return nil
end

local function iconOf(id: string): any
	for _, ref in iconCells do
		if ref.id == id and ref.center then
			return ref
		end
	end
	return nil
end

local function resetRoot(root: GuiObject)
	root.AnchorPoint = Vector2.zero
	root.Position = UDim2.fromScale(0, 0)
	K.scaleOf(root).Scale = 1
end

-- Back to the home screen: the app shrinks into its icon (or scales away) while the home screen
-- settles back from a slight zoom.
function Phone.home()
	if current then
		local id = current
		current = nil
		launchSerial += 1
		local mine = launchSerial
		callApp(id, "hide")
		local root = roots[id]
		homeFrame.Visible = true
		if not K.reduced() then
			homeScale.Scale = 1.07
			K.spring(homeScale, { Scale = 1 }, { duration = 0.42, amount = 0.25 })
		else
			homeScale.Scale = 1
		end
		if root then
			local ref = iconOf(id)
			local cover = covers[id]
			local function done()
				if launchSerial == mine and current ~= id then
					root.Visible = false
					resetRoot(root)
					if cover then
						cover.Visible = false
						cover.BackgroundTransparency = 1
					end
				end
			end
			if ref then
				K.zoomFrom(root, Vector2.new(L.screenW, L.screenH), ref.center, ref.size / math.max(1, L.screenW), { reverse = true, cover = cover, duration = 0.34, onDone = done })
			else
				root.AnchorPoint = Vector2.new(0.5, 0.5)
				root.Position = UDim2.fromScale(0.5, 0.5)
				K.tweenD(K.scaleOf(root), 0.22, { Scale = 0.86 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
				if cover then
					cover.Visible = true
					K.tweenD(cover, 0.2, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				end
				task.delay(if K.reduced() then 0.14 else 0.22, done)
			end
		end
	end
	homeFrame.Visible = true
	refreshConn()
	pcall(updateClock)
end

function Phone.launch(id: string, args: any?)
	if not APP_META[id] then
		return
	end
	if not ensureBuilt(id) then
		Phone.toast({ app = id, title = APP_META[id].title, body = "앱을 열 수 없어요", kind = "error" })
		return
	end
	local prev = current
	local root = roots[id]
	launchSerial += 1
	local mine = launchSerial
	current = id
	if prev and prev ~= id then
		-- app -> app (e.g. 전화 -> 택시): push with parallax
		callApp(prev, "hide")
		local proot = roots[prev]
		resetRoot(root)
		if covers[id] then
			covers[id].Visible = false
		end
		homeFrame.Visible = false
		K.pushPage(root, proot)
	elseif prev ~= id then
		-- from the home screen: zoom out of the tapped icon
		root.Visible = true
		local ref = iconOf(id)
		local fresh = homeFrame.Visible
		if ref and fresh and isOpen then
			K.zoomFrom(root, Vector2.new(L.screenW, L.screenH), ref.center, ref.size / math.max(1, L.screenW), { cover = covers[id], duration = 0.38 })
			K.tweenD(homeScale, 0.38, { Scale = 1.07 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			task.delay(if K.reduced() then 0.24 else 0.38, function()
				if launchSerial == mine and current == id then
					homeFrame.Visible = false
					homeScale.Scale = 1
				end
			end)
		else
			resetRoot(root)
			homeFrame.Visible = false
			if isOpen then
				root.AnchorPoint = Vector2.new(0.5, 0.5)
				root.Position = UDim2.fromScale(0.5, 0.5)
				K.springIn(root, 0.94, { amount = 0.3, duration = 0.36 })
				task.delay(0.4, function()
					if launchSerial == mine and current == id then
						resetRoot(root)
					end
				end)
			end
		end
	end
	callApp(id, "show", args)
	refreshConn()
end

-- Opens the phone (optionally straight into an app).
function Phone.open(appId: string?, args: any?)
	if hiddenByOther or photoMode then
		return
	end
	if not isOpen then
		isOpen = true
		openSerial += 1
		pcall(Overlay.onPhoneOpened)
		phoneGui.Enabled = true
		applyLayout()
		local target = device.Position
		device.Position = if L.mode == "phoneL" then target + UDim2.fromOffset(slideOffset, 0) else target + UDim2.fromOffset(0, slideOffset)
		K.spring(device, { Position = target }, { duration = 0.5, amount = 0.035 })
		if not current and not K.reduced() then
			-- the home screen settles in from a slight zoom while the phone slides up
			homeScale.Scale = 0.92
			K.spring(homeScale, { Scale = 1 }, { duration = 0.5, amount = 0.3, delay = 0.06 })
		end
		startWallpaperFx()
		closeBig.Visible = true
		if isTouch then
			backdrop.BackgroundTransparency = 1
			K.tween(backdrop, 0.25, { BackgroundTransparency = 0.5 })
			if not controlsDisabledByUs then
				controlsDisabledByUs = true
				setControls(false)
			end
		end
		K.blur(true, "phone")
		refreshHud()
		startClockLoop()
		Net.refresh()
		pcall(updateClock)
		if current then
			callApp(current, "show", nil)
		end
	end
	if appId then
		Phone.launch(appId, args)
	end
	refreshConn()
end

-- reason "other": another full-screen UI took over (it may own the character controls now; ours are
-- restored as soon as that UI closes again, so nothing ever stays locked).
function Phone.close(reason: string?)
	if not isOpen then
		return
	end
	isOpen = false
	openSerial += 1
	local mine = openSerial
	if current then
		callApp(current, "hide")
	end
	headsUp.clear()
	local target = device.Position
	local away = if L.mode == "phoneL" then target + UDim2.fromOffset(slideOffset, 0) else target + UDim2.fromOffset(0, slideOffset)
	K.cancel(device)
	K.tween(device, 0.24, { Position = away }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	if isTouch then
		K.tween(backdrop, 0.2, { BackgroundTransparency = 1 })
	end
	K.blur(false, "phone")
	K.sound("close")
	task.delay(0.24, function()
		if openSerial == mine then
			phoneGui.Enabled = false
			device.Position = target
		end
	end)
	if controlsDisabledByUs then
		controlsDisabledByUs = false
		if reason == "other" then
			restoreControlsLater = true
		else
			setControls(true)
		end
	end
	refreshHud()
end

function Phone.toggle()
	if isOpen then
		Phone.close()
	else
		Phone.open()
	end
end

function Phone.isOpen(): boolean
	return isOpen
end

---------------------------------------------------------------------------------------------------------
-- Notifications: the HUD toast stack while the phone is away, heads-up cards inside the phone while it
-- is out. Other client scripts use GwangalliUI.toast() (routed here).
---------------------------------------------------------------------------------------------------------
-- t = { app?, args?, title, body, glyph?, kind?, silent?, onClick? }
function Phone.toast(t: any)
	if type(t) ~= "table" then
		return
	end
	local meta = t.app and APP_META[t.app]
	local kind = t.kind or "info"
	local data = {
		kind = kind,
		title = if t.title and t.title ~= "" then t.title else ((meta and meta.title) or "알림"),
		body = t.body,
		icon = t.glyph or t.icon or (meta and meta.glyph) or nil,
		color = t.color or (meta and meta.c1) or nil,
		silent = t.silent or not settings.sound,
		duration = t.duration,
		onClick = t.onClick or function()
			if t.app then
				Phone.open(t.app, t.args)
			else
				Phone.open()
			end
		end,
	}
	if not settings.banners and not t.force then
		if not data.silent then
			K.sound("notify")
		end
		return
	end
	if isOpen then
		headsUp.push(data)
	elseif not photoMode then
		toaster.push(data)
	end
end

---------------------------------------------------------------------------------------------------------
-- Photo mode (카메라 app): hide every overlay for a clean screenshot
---------------------------------------------------------------------------------------------------------
function Phone.setPhotoMode(on: boolean)
	if on == photoMode then
		return
	end
	if on then
		Phone.close()
	end
	photoMode = on
	photoGui.Enabled = on
	refreshHud()
end

---------------------------------------------------------------------------------------------------------
-- Other full-screen UIs (e.g. the bowling lane UI) set HideGwangalliHUD = true on their ScreenGui
---------------------------------------------------------------------------------------------------------
local watched: { [Instance]: { RBXScriptConnection } } = {}
local ownGuis: { [Instance]: boolean } = {}
local function updateOther()
	local hide = false
	for g in watched do
		if g.Parent and (g :: ScreenGui).Enabled and g:GetAttribute("HideGwangalliHUD") == true then
			hide = true
			break
		end
	end
	if hide ~= hiddenByOther then
		hiddenByOther = hide
		if hide then
			Phone.close("other")
		elseif restoreControlsLater then
			-- the other UI is gone: make sure the controls we once disabled are back
			restoreControlsLater = false
			setControls(true)
		end
		refreshHud()
	end
end
local function watchGui(g: Instance)
	if not g:IsA("ScreenGui") or ownGuis[g] or watched[g] then
		return
	end
	watched[g] = {
		g:GetPropertyChangedSignal("Enabled"):Connect(updateOther),
		g:GetAttributeChangedSignal("HideGwangalliHUD"):Connect(updateOther),
	}
	updateOther()
end

---------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------
function Phone.start()
	playerGui = player:WaitForChild("PlayerGui", 30) :: PlayerGui
	if not playerGui then
		warn("[GwangalliPhone] PlayerGui missing")
		return
	end
	local kitModule = ReplicatedStorage:FindFirstChild("GwangalliUI") or ReplicatedStorage:WaitForChild("GwangalliUI", 10)
	local okKit, Kit = pcall(require, kitModule)
	if not okKit or type(Kit) ~= "table" then
		warn("[GwangalliPhone] GwangalliUI kit missing: " .. tostring(Kit))
		return
	end
	K = Kit
	Layout = K.Layout
	if not Layout then
		local lm = ReplicatedStorage:WaitForChild("GwangalliLayout", 10)
		local okL, res = pcall(require, lm)
		Layout = if okL then res else nil
	end
	if not Layout then
		warn("[GwangalliPhone] GwangalliLayout missing")
		return
	end
	Quality = optionalModule("GwangalliQuality", 3)
	WorldShared = optionalModule("GwangalliShared", 5)
	Data.start()
	Dest.start()
	Net.start()

	build()
	ownGuis[hudGui] = true
	ownGuis[phoneGui] = true
	ownGuis[photoGui] = true
	ownGuis[toastGui] = true

	ctx = {
		K = K,
		Layout = Layout,
		AppKit = AppKit,
		Life = Life,
		UI = UI,
		Data = Data,
		Dest = Dest,
		Net = Net,
		Tracker = Tracker,
		Quality = Quality,
		player = player,
		settings = settings,
		phone = {
			open = Phone.open,
			close = Phone.close,
			home = Phone.home,
			launch = Phone.launch,
			toast = Phone.toast,
			setBadge = setBadge,
			header = header,
			setPhotoMode = Phone.setPhotoMode,
			setControls = setControls,
			current = function(): string?
				return if isOpen then current else nil
			end,
			isOpen = function(): boolean
				return isOpen
			end,
			layout = function(): any
				return L
			end,
			onLayout = function(fn: () -> ())
				table.insert(layoutListeners, fn)
				-- apps register while being built, after the first layout: run once for the current one
				task.defer(function()
					local ok, err = pcall(fn)
					if not ok then
						warn("[GwangalliPhone] layout listener: " .. tostring(err))
					end
				end)
			end,
			clock = clockNow,
			screen = function(): Frame
				return screen
			end,
			-- modal / confirm inside the phone screen
			modal = function(o: any): any
				return K.Modal(screen, o)
			end,
			confirm = function(o: any): any
				return K.confirm(screen, o)
			end,
		},
	}
	-- one toast route for every client script (GwangalliUI.toast)
	K.setToaster({
		push = function(d: any)
			if isOpen then
				headsUp.push(d)
			elseif not photoMode then
				toaster.push(d)
			end
		end,
	})
	Tracker.init(ctx, hudGui, hudProbe)
	local okOv, errOv = pcall(Overlay.init, ctx, hudGui, playerGui)
	if not okOv then
		warn("[GwangalliPhone] overlay: " .. tostring(errOv))
	end
	Overlay.onDialogChanged = function()
		refreshHud()
	end
	local dlg = playerGui:FindFirstChild("GwangalliDialog")
	if dlg then
		ownGuis[dlg] = true
	end

	hudGui.Parent = playerGui
	toastGui.Parent = playerGui
	phoneGui.Parent = playerGui
	photoGui.Parent = playerGui

	-- input -------------------------------------------------------------------------------------------------
	phoneBtn.Activated:Connect(function()
		Phone.toggle()
	end)
	closeBig.Activated:Connect(function()
		Phone.close()
	end)
	homeBig.Activated:Connect(function()
		if current then
			Phone.home()
		else
			Phone.close()
		end
	end)
	homeBar.Activated:Connect(function()
		if current then
			Phone.home()
		else
			Phone.close()
		end
	end)
	-- long-press the home bar: close
	do
		local downAt = 0
		homeBar.MouseButton1Down:Connect(function()
			downAt = os.clock()
			local mine = downAt
			task.delay(0.55, function()
				if downAt == mine and isOpen then
					downAt = 0
					Phone.close()
				end
			end)
		end)
		homeBar.MouseButton1Up:Connect(function()
			downAt = 0
		end)
	end
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		if not processed and (key == Enum.KeyCode.P or key == Enum.KeyCode.DPadUp) then
			if not hiddenByOther and not photoMode then
				Phone.toggle()
			end
			return
		end
		if isOpen and not processed and key == Enum.KeyCode.Escape then
			Phone.close()
			return
		end
		-- PC: a click into the world (not on any GUI) closes the phone
		if isOpen and not isTouch and not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			local p = input.Position
			local ap, as = device.AbsolutePosition, device.AbsoluteSize
			local inside = p.X >= ap.X and p.X <= ap.X + as.X and p.Y >= ap.Y and p.Y <= ap.Y + as.Y
			if not inside then
				Phone.close()
			end
		end
	end)

	-- layout triggers ---------------------------------------------------------------------------------------
	Layout.onChanged(applyLayout)
	phoneProbe:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if isOpen then
			applyLayout()
		end
	end)

	-- other full-screen UIs ---------------------------------------------------------------------------------
	playerGui.ChildAdded:Connect(function(g)
		if g.Name == "GwangalliDialog" then
			ownGuis[g] = true
		end
		watchGui(g)
	end)
	playerGui.ChildRemoved:Connect(function(g)
		local conns = watched[g]
		if conns then
			for _, c in conns do
				c:Disconnect()
			end
			watched[g] = nil
			updateOther()
		end
	end)
	for _, g in playerGui:GetChildren() do
		watchGui(g)
	end

	-- data events ---------------------------------------------------------------------------------------------
	local lastTaxiNotify = -math.huge
	local lastTaxiToast = -math.huge
	Net.on("notify", function(n: any)
		local appId = KIND_APP[n.kind]
		local args: any = nil
		local title = n.title
		local glyph = nil
		if n.kind == "message" then
			local c = Data.contact(n.contact or n.title)
			title = c.name
			glyph = c.glyph
			args = { contact = n.contact or c.id }
		elseif n.kind == "taxi" then
			lastTaxiNotify = os.clock()
			if os.clock() - lastTaxiToast < 1.5 then
				return -- the TaxiState toast already said it
			end
		end
		local raw = n.raw
		if type(raw) == "table" and type(raw.shop) == "string" and raw.shop ~= "" then
			-- a shop counter prompt: the list is in the 쇼핑 app
			appId = "shop"
			args = { shop = raw.shop }
			if isOpen and current == "shop" then
				callApp("shop", "show", args)
			end
		end
		Phone.toast({ app = appId, args = args, title = title, body = n.body, kind = n.kind, glyph = glyph })
	end)
	Net.on("profile", function(changed: any)
		if changed.messages or changed.unread then
			setBadge("messages", Data.unreadTotal(Net.profile.messages))
		end
		if changed.offers or changed.home or changed.job then
			refreshLifeBadges()
		end
		if isOpen and homeFrame.Visible then
			pcall(updateWidgets)
		end
	end)
	Net.on("work", function()
		if isOpen and homeFrame.Visible then
			pcall(updateWidgets)
		end
	end)
	Net.on("status", function()
		refreshConn()
	end)
	local TAXI_TEXT = {
		arrived = "택시가 도착했어요 · 탭해서 목적지를 골라요",
		done = "목적지에 도착했어요",
		cancelled = "택시 호출이 취소됐어요",
	}
	Net.on("taxi", function(t: any)
		setBadge("taxi", if t.state == "arrived" then 1 else 0)
		local body = TAXI_TEXT[t.state]
		if body and not (isOpen and current == "taxi") and os.clock() - lastTaxiNotify > 1.5 then
			lastTaxiToast = os.clock()
			if t.state == "done" and t.fare then
				body = string.format("요금 %s 결제 완료 · 영수증 보기", K.won(t.fare))
			end
			Phone.toast({ app = "taxi", title = "광안 콜택시", body = body, kind = "taxi" })
		end
	end)
	-- feedback settings mirror
	K.settings.sound = settings.sound
	K.settings.haptics = settings.haptics

	refreshHud()
	refreshLifeBadges()
	print("[GwangalliPhone] ready (" .. L.mode .. ")")
end

return Phone
