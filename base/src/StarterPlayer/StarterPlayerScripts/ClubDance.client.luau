-- ClubDance (client): the player's side of CLUB OCEAN 광안 - dance buttons, the hands-up button on
-- drops, the LED-wall photo moment, the bottle-service menu and the club toasts.
--
-- * Shown only while the player is inside a room that sees the show (ClubShared.Bus, written by
--   ClubLights.client: state / showRoom) and no full-screen UI carries HideGwangalliHUD.
-- * Dance bar (touch-friendly 52 px buttons): 댄스 1-3 and 📸. Dances are Roblox's public emote
--   animations (ClubShared.PlayerDances: the same R6 dances the NPC crowd uses; the R15 emotes of the
--   default Animate script for R15 avatars), loaded on the character's Humanoid Animator so they
--   replicate to everyone (the character is the player's own). A dance stops when the player moves,
--   jumps, sits or leaves; tapping the active dance stops it. Starting a dance tells the server once
--   ("dance": a little Happiness through the life-game, rate limited there) and makes the guests
--   around the player cheer (Bus.playerDanceAt -> ClubLights).
-- * Hands up: a gold 🙌 button pops up above the bar for 6 s after every drop (Bus.dropSerial) and
--   during the build-up countdown; it plays the cheer emote for 2.5 s.
-- * Photo moment: 📸 sets Bus.photoAt (the LED wall counts 3-2-1, flashes and frames the logo), hides
--   the club UI for a clean screenshot, flashes the screen once and shows a caption card; the avatar
--   raises its hands.
-- * Bottle menu: the server answers the table prompt with ClubRemote ("menu", payload); the sheet
--   lists ClubShared.Menu with prices (or "이벤트 무료" when the server has no life-game money API);
--   a tap sends ("order", TableId, itemId). Wallet line from the Money / Bank player attributes.
-- * Toasts: ClubOrder replies and the door wristband, through GwangalliUI.toast when the phone's
--   toaster is up, else a small toast of our own in the GwangalliLayout "toasts" slot.
-- * Placement: GwangalliLayout (pcall): the bar sits right above the "bottomCenter" slot (the Now
--   Playing widget), clear of the thumbstick zone and the jump button; the menu uses the "dialog"
--   slot. Fallback geometry when the module is missing. Styling: GwangalliUI tokens (pcall).
-- * Cost: a 10 Hz state check (4 Hz outside the club), no per-frame work; nothing built until the
--   player first enters the club.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Shared: any
do
	local mod = ReplicatedStorage:WaitForChild("ClubShared", 60)
	if not mod then
		warn("[ClubDance] ReplicatedStorage.ClubShared missing; club UI disabled")
		return
	end
	local ok, res = pcall(require, mod)
	if not ok or type(res) ~= "table" then
		warn("[ClubDance] ClubShared failed to load:", res)
		return
	end
	Shared = res
end
local Bus: any = Shared.Bus
if type(Bus) ~= "table" then
	Bus = {}
	Shared.Bus = Bus
end
local ATTR = Shared.Attr or {}
local NAMES = Shared.Names or {}

local function optional(name: string): any
	local m = ReplicatedStorage:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
	end
	return nil
end
local UIK: any = nil -- GwangalliUI (loaded on first UI build)
local Layout: any = nil -- GwangalliLayout
local GP: any = nil -- GwangalliGameplayShared (entry rule numbers for the toast)

-- design tokens (GwangalliUI when available)
local C = {
	glass = Color3.fromRGB(15, 18, 31),
	card = Color3.fromRGB(25, 29, 45),
	card2 = Color3.fromRGB(37, 42, 61),
	line = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(245, 247, 251),
	sub = Color3.fromRGB(170, 177, 196),
	cyan = Color3.fromRGB(61, 214, 245),
	magenta = Color3.fromRGB(255, 79, 163),
	gold = Color3.fromRGB(255, 194, 71),
	red = Color3.fromRGB(255, 90, 95),
	green = Color3.fromRGB(61, 220, 132),
}
local FONT = { bold = Enum.Font.GothamBold, medium = Enum.Font.GothamMedium, heavy = Enum.Font.GothamBlack }

local function loadKit()
	if UIK == nil then
		UIK = optional("GwangalliUI") or false
		if UIK then
			pcall(function()
				local c = UIK.Color or {}
				C.glass = c.glass or C.glass
				C.card = c.card or C.card
				C.card2 = c.card2 or C.card2
				C.line = c.line or C.line
				C.text = c.text or C.text
				C.sub = c.sub or C.sub
				C.cyan = c.cyan or c.teal or C.cyan
				C.magenta = c.magenta or c.pink or C.magenta
				C.gold = c.gold or C.gold
				C.red = c.red or C.red
				C.green = c.green or C.green
				local f = UIK.Font or {}
				FONT.bold = f.bold or FONT.bold
				FONT.medium = f.medium or FONT.medium
				FONT.heavy = f.heavy or FONT.heavy
			end)
		end
	end
	if Layout == nil then
		Layout = optional("GwangalliLayout") or false
	end
	if GP == nil then
		GP = optional("GwangalliGameplayShared") or false
	end
end

local function feedback(kind: string)
	if UIK and type(UIK.feedback) == "function" then
		pcall(UIK.feedback, kind)
	end
end

local function won(n: number): string
	if UIK and type(UIK.won) == "function" then
		local ok, s = pcall(UIK.won, n)
		if ok and type(s) == "string" then
			return s
		end
	end
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", "")) .. "원"
end

---------------------------------------------------------------------------------------------------
-- Small UI helpers (plain instances; no dependency on the kit's component API)
---------------------------------------------------------------------------------------------------
local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local function corner(inst: Instance, r: number | UDim)
	make("UICorner", { CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, r :: number) }, inst)
end
local function stroke(inst: Instance, color: Color3, thickness: number, transparency: number): UIStroke
	return make("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inst)
end
local function tween(inst: Instance, t: number, goals: { [string]: any })
	local ok = pcall(function()
		TweenService:Create(inst, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goals):Play()
	end)
	if not ok then
		for k, v in goals do
			pcall(function()
				(inst :: any)[k] = v
			end)
		end
	end
end

-- Motion policy (same as GwangalliHUD, docs/ui_kit_requests.md #1): phones sit in the "low" graphics
-- tier by default, but UI tweens are cheap, so motion is reduced only for the player's reduced-motion
-- setting, a low graphics slider or a frame-rate demotion.
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
	else
		local q = optional("GwangalliQuality")
		if q and type(q.isLow) == "function" and q.isLow() == true then
			local why = if type(q.reason) == "function" then string.lower(tostring(q.reason())) else ""
			r = string.find(why, "frame", 1, true) ~= nil or string.find(why, "slider", 1, true) ~= nil or string.find(why, "chosen", 1, true) ~= nil
		end
	end
	motionCache = r
	return r
end
local function tw(inst: Instance, t: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween?
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
-- two-stage spring: Quint Out past the goal, then Sine back (serial-guarded per instance)
local springSerial: { [Instance]: number } = {}
local function spring(inst: Instance, t: number, past: { [string]: any }, goals: { [string]: any })
	local n = (springSerial[inst] or 0) + 1
	springSerial[inst] = n
	local first = tw(inst, t * 0.7, past)
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
local function gradient(inst: Instance, a: Color3, b: Color3, rot: number): UIGradient
	return make("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rot }, inst)
end
local function lighter(c: Color3, dv: number): Color3
	local h, sat, v = c:ToHSV()
	return Color3.fromHSV(h, math.clamp(sat - dv * 0.4, 0, 1), math.clamp(v + dv, 0, 1))
end
-- press feedback: scale (own UIScale "Press") with a small release overshoot + a light veil
local function pressable(b: GuiButton, scaleTo: number?)
	local sc = make("UIScale", { Name = "Press", Scale = 1 }, b)
	local held = false
	b.MouseButton1Down:Connect(function()
		held = true
		tw(sc, 0.08, { Scale = scaleTo or 0.92 }, Enum.EasingStyle.Quad)
	end)
	local function up()
		if held then
			held = false
			spring(sc, 0.3, { Scale = 1.04 }, { Scale = 1 })
		end
	end
	b.MouseButton1Up:Connect(up)
	b.MouseLeave:Connect(up)
	b.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			up()
		end
	end)
end

local function playerGui(): PlayerGui?
	return player:FindFirstChildOfClass("PlayerGui")
end

local function newScreenGui(name: string, order: number): ScreenGui
	local g = make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = order,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	return g
end

-- usable gui area (px) of a ScreenGui
local function areaOf(g: ScreenGui): Vector2
	local a = g.AbsoluteSize
	if a.X < 100 or a.Y < 100 then
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		a = Vector2.new(vp.X, vp.Y - 58)
	end
	return a
end

local function layoutRect(name: string): { x: number, y: number, w: number, h: number }?
	if not Layout or type(Layout.rect) ~= "function" then
		return nil
	end
	local ok, r = pcall(Layout.rect, name)
	if ok and type(r) == "table" and type(r.x) == "number" and type(r.y) == "number" and type(r.w) == "number" and type(r.h) == "number" and r.w > 40 then
		return r
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Toasts
---------------------------------------------------------------------------------------------------
local ownToast = { gui = nil :: ScreenGui?, label = nil :: TextLabel?, serial = 0 }
local function toast(text: string, icon: string?, title: string?)
	loadKit()
	local pg = playerGui()
	if not pg then
		return
	end
	-- the phone's toaster (GwangalliUI.toast route) when it is up
	if UIK and type(UIK.toast) == "function" and pg:FindFirstChild("Toasts", true) then
		local ok = pcall(UIK.toast, { kind = "club", title = title or "CLUB OCEAN 광안", body = text, icon = icon or "🎶", duration = if title then 5 else 3.5 })
		if ok then
			return
		end
	end
	if not ownToast.gui or ownToast.gui.Parent ~= pg then
		local g = newScreenGui("ClubOceanToast", 30)
		local l = make("TextLabel", {
			Name = "Toast",
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = C.glass,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			TextColor3 = C.text,
			Font = FONT.bold,
			TextSize = 14,
			TextWrapped = true,
			Text = "",
		}, g)
		corner(l, 14)
		stroke(l, C.magenta, 1.5, 0.35)
		make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, l)
		g.Parent = pg
		ownToast.gui, ownToast.label = g, l
	end
	local g, l = ownToast.gui :: ScreenGui, ownToast.label :: TextLabel
	local r = layoutRect("toasts")
	local area = areaOf(g)
	if r then
		l.Position = UDim2.fromOffset(r.x + r.w / 2, r.y)
		l.Size = UDim2.fromOffset(r.w, 46)
	else
		local w = math.min(420, area.X * 0.9)
		l.Position = UDim2.new(0.5, 0, 0, 8)
		l.Size = UDim2.fromOffset(w, 46)
	end
	l.Text = (icon or "🎶") .. "  " .. text
	g.Enabled = true
	ownToast.serial += 1
	local mine = ownToast.serial
	task.delay(3.5, function()
		if ownToast.serial == mine and g.Parent then
			g.Enabled = false
		end
	end)
end

local ORDER_TEXT = {
	ok = "%s · 샴페인이 테이블로 나가요 🍾",
	parade = "%s · 보틀 퍼레이드 출발! LED 월을 봐요 ✨",
	queued = "%s · 주문 완료! 다음 퍼레이드가 이 테이블로 와요",
	wait = "주문은 잠시 후에 다시 할 수 있어요",
	busy = "%s · 이 테이블은 벌써 보틀 서비스 중이에요",
	full = "%s · 테이블에 빈 자리가 없어요",
	nofunds = "%s · 잔액이 부족해요 (현금 + 통장)",
	error = "주문을 처리하지 못했어요. 잠시 후 다시 해 주세요",
	paying = "결제 처리 중이에요…",
	far = "%s · 테이블 가까이에서 주문해 주세요",
}

player:GetAttributeChangedSignal(ATTR.Order or "ClubOrder"):Connect(function()
	local v = player:GetAttribute(ATTR.Order or "ClubOrder")
	if type(v) ~= "string" then
		return
	end
	local status, id = string.match(v, "^(%a+)|([^|]*)|")
	if status == "entry" then
		loadKit()
		local club = GP and GP.CLUB
		local need = if type(club) == "table" and type(club.entryAppearance) == "number" then club.entryAppearance else 30
		local cover = if type(club) == "table" and type(club.cover) == "number" then club.cover else 20000
		-- one line in the kit toast card (the long form wrapped and clipped on phones)
		toast(string.format("MD에게 말 걸기 · 외모 %d↑ 무료, 아니면 %s", need, won(cover)), "🪪", "입장 안내 · CLUB OCEAN")
		return
	end
	local fmt = status and ORDER_TEXT[status]
	if fmt then
		local text = if string.find(fmt, "%s", 1, true) then string.format(fmt, id or "") else fmt
		toast(text, if status == "parade" or status == "ok" or status == "queued" then "🍾" else "ℹ️")
	end
end)
player:GetAttributeChangedSignal(ATTR.Wristband or "ClubOceanWristband"):Connect(function()
	local v = player:GetAttribute(ATTR.Wristband or "ClubOceanWristband")
	if v == true or type(v) == "number" then
		toast("팔찌 확인 완료 · 즐거운 밤 보내세요", "🎟️", "입장 완료 · CLUB OCEAN")
	end
end)

---------------------------------------------------------------------------------------------------
-- Character animations (dances, hands up)
---------------------------------------------------------------------------------------------------
local anim = {
	tracks = {} :: { [string]: AnimationTrack },
	animator = nil :: Animator?,
	current = nil :: string?, -- dance id playing
	track = nil :: AnimationTrack?,
	cheerUntil = 0,
	cheerTrack = nil :: AnimationTrack?,
	objects = {} :: { [string]: Animation },
	humanoid = nil :: Humanoid?,
	lastServerDance = -1e9,
}

local function humanoidOf(): Humanoid?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum
	end
	return nil
end

local function animatorOf(hum: Humanoid): Animator?
	if anim.humanoid ~= hum then
		anim.humanoid = hum
		anim.animator = nil
		table.clear(anim.tracks)
		anim.track, anim.current, anim.cheerTrack = nil, nil, nil
	end
	local a = anim.animator
	if a and a.Parent == hum then
		return a
	end
	-- the Humanoid's own Animator (created by the engine / server): tracks played on it replicate
	local found = hum:FindFirstChildOfClass("Animator")
	anim.animator = found
	return found
end

local function trackFor(hum: Humanoid, key: string, ids: { [string]: string }): AnimationTrack?
	local t = anim.tracks[key]
	if t then
		return t
	end
	local animator = animatorOf(hum)
	if not animator then
		return nil
	end
	local r15 = hum.RigType == Enum.HumanoidRigType.R15
	local id = if r15 then ids.r15 else ids.r6
	if type(id) ~= "string" then
		return nil
	end
	local obj = anim.objects[id]
	if not obj then
		obj = Instance.new("Animation")
		obj.AnimationId = id
		anim.objects[id] = obj
	end
	local ok, res = pcall(function()
		return (animator :: Animator):LoadAnimation(obj)
	end)
	if not ok or not res then
		return nil
	end
	local tr = res :: AnimationTrack
	tr.Priority = Enum.AnimationPriority.Action
	tr.Looped = true
	anim.tracks[key] = tr
	return tr
end

local refreshButtons: () -> () = function() end

local function stopDance()
	local tr = anim.track
	if tr then
		pcall(function()
			tr:Stop(0.3)
		end)
	end
	anim.track, anim.current = nil, nil
	refreshButtons()
end

local function stopCheer()
	local tr = anim.cheerTrack
	if tr then
		pcall(function()
			tr:Stop(0.3)
		end)
	end
	anim.cheerTrack = nil
	anim.cheerUntil = 0
end

local function playDance(entry: { [string]: any })
	local hum = humanoidOf()
	if not hum then
		return
	end
	if hum.Sit then
		toast("앉아 있을 땐 춤 대신 손을 들어 봐요 🙌", "💺")
		return
	end
	if anim.current == entry.id then
		stopDance()
		return
	end
	stopCheer()
	local tr = trackFor(hum, entry.id, entry)
	if not tr then
		toast("춤 애니메이션을 불러오지 못했어요", "⚠️")
		return
	end
	local old = anim.track
	if old and old ~= tr then
		pcall(function()
			old:Stop(0.25)
		end)
	end
	local speed = math.clamp((tonumber(Bus.bpm) or 126) / 126, 0.85, 1.25)
	pcall(function()
		tr:Play(0.25, 1, speed)
	end)
	anim.track, anim.current = tr, entry.id
	Bus.playerDanceAt = os.clock()
	feedback("tap")
	refreshButtons()
	local now = os.clock()
	if now - anim.lastServerDance > 60 then
		anim.lastServerDance = now
		local remote = ReplicatedStorage:FindFirstChild(NAMES.Remote or "ClubRemote")
		if remote and remote:IsA("RemoteEvent") then
			pcall(function()
				remote:FireServer("dance")
			end)
		end
	end
end

local function cheer(seconds: number)
	local hum = humanoidOf()
	if not hum then
		return
	end
	local tr = trackFor(hum, "cheer", Shared.PlayerCheer or {})
	if not tr then
		return
	end
	if anim.track then
		stopDance()
	end
	pcall(function()
		tr:Play(0.2, 1, 1)
	end)
	anim.cheerTrack = tr
	anim.cheerUntil = os.clock() + seconds
	Bus.playerDanceAt = os.clock()
	feedback("success")
end

---------------------------------------------------------------------------------------------------
-- Dance bar, hands-up button, photo caption
---------------------------------------------------------------------------------------------------
local BTN = 52
local GAP = 6
local ui: any = nil -- { gui, bar, buttons = {id -> TextButton}, hands, handsLabel, flash, caption, captionLabel }
local photoHideUntil = 0
local handsUntil = 0
local lastDropSerial = -1

local function danceButton(parent: Instance, icon: string, caption: string, order: number): TextButton
	local b = make("TextButton", {
		Name = "Btn_" .. caption,
		Size = UDim2.fromOffset(BTN, BTN),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, parent)
	corner(b, UDim.new(0.5, 0))
	-- idle: a raised glass disc (card2 -> card, lit from the top); active: the magenta gradient
	local g = gradient(b, lighter(C.card2, 0.04), C.card, 90)
	b:SetAttribute("GradIdleA", lighter(C.card2, 0.04))
	local st = stroke(b, C.line, 1, 0.86)
	st.Name = "Hairline"
	-- breathing ring while this dance plays (a looping stroke-transparency tween, started on demand)
	local ring = make("Frame", { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 8, 1, 8), BackgroundTransparency = 1, Visible = false }, b)
	corner(ring, UDim.new(0.5, 0))
	stroke(ring, C.magenta, 2, 0.2).Name = "RingStroke"
	make("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, 0, 0, 24),
		Text = icon,
		TextSize = 21,
		Font = FONT.bold,
		TextColor3 = C.text,
	}, b)
	make("TextLabel", {
		Name = "Caption",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -4, 0, 13),
		Text = caption,
		TextSize = 11,
		Font = FONT.bold,
		TextColor3 = C.sub,
	}, b)
	pressable(b, 0.9)
	local _ = g
	return b
end

local function buildUI(): any
	loadKit()
	local pg = playerGui()
	if not pg then
		return nil
	end
	local g = newScreenGui("ClubDanceUI", 8)
	local dances = Shared.PlayerDances or {}
	local count = #dances + 1
	local barW = count * BTN + (count - 1) * GAP + 2 * GAP
	local bar = make("Frame", {
		Name = "DanceBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(barW, BTN + 2 * GAP),
		BackgroundColor3 = C.glass,
		BackgroundTransparency = 0.14,
		BorderSizePixel = 0,
	}, g)
	corner(bar, UDim.new(0.5, 0))
	stroke(bar, C.line, 1, 0.84)
	local barScale = make("UIScale", { Name = "Enter", Scale = 1 }, bar)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, GAP),
	}, bar)
	local buttons: { [string]: TextButton } = {}
	for i, entry in dances do
		local b = danceButton(bar, entry.icon or "💃", entry.label or ("댄스 " .. i), i)
		buttons[entry.id] = b
		b.Activated:Connect(function()
			playDance(entry)
		end)
	end
	local photo = danceButton(bar, "📸", "포토", count)
	buttons.photo = photo

	-- hands-up button (drops / countdown)
	local hands = make("TextButton", {
		Name = "HandsUp",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(156, 48),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "🙌  손 들어!",
		TextSize = 17,
		Font = FONT.heavy,
		TextColor3 = Color3.fromRGB(44, 28, 0),
		Visible = false,
		ClipsDescendants = true,
	}, g)
	corner(hands, UDim.new(0.5, 0))
	gradient(hands, Color3.fromRGB(255, 218, 120), Color3.fromRGB(255, 164, 48), 90)
	local handsStroke = stroke(hands, Color3.new(1, 1, 1), 1.5, 0.35)
	local handsScale = make("UIScale", { Scale = 1 }, hands)
	-- a light sheen sweeps across the gold pill while it is up (one looping tween)
	local handsSheen = make("Frame", { Name = "Sheen", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 2 }, hands)
	corner(handsSheen, UDim.new(0.5, 0))
	local sheenGrad = make("UIGradient", { Rotation = 20, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1) }) }, handsSheen)
	hands.Activated:Connect(function()
		cheer(2.5)
		handsUntil = 0
	end)

	-- photo: full-screen flash + caption card
	local flash = make("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
	}, g)
	local caption = make("Frame", {
		Name = "PhotoCaption",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(280, 54),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 21,
	}, g)
	corner(caption, 8)
	local captionLabel = make("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = 15,
		Font = FONT.bold,
		TextColor3 = Color3.fromRGB(20, 22, 30),
		ZIndex = 22,
	}, caption)
	photo.Activated:Connect(function()
		local now = os.clock()
		if now - (Bus.photoAt or -1e9) < 5 then
			return
		end
		Bus.photoAt = now
		photoHideUntil = now + 5.2
		feedback("tap")
		-- the LED wall counts 3-2-1 (ClubLights); the avatar poses on "1"
		task.delay(1.8, function()
			cheer(3)
		end)
		task.delay(2.7, function()
			if not flash.Parent then
				return
			end
			flash.Visible = true
			flash.BackgroundTransparency = 0.15
			tween(flash, 0.5, { BackgroundTransparency = 1 })
			local t = os.date("*t")
			captionLabel.Text = string.format("📸 CLUB OCEAN 광안 · %04d.%02d.%02d", t.year, t.month, t.day)
			caption.Visible = true
			task.delay(0.6, function()
				flash.Visible = false
			end)
			task.delay(2.4, function()
				caption.Visible = false
			end)
		end)
	end)
	g.Parent = pg
	return {
		gui = g,
		bar = bar,
		buttons = buttons,
		hands = hands,
		handsStroke = handsStroke,
		handsScale = handsScale,
		sheenGrad = sheenGrad,
		sheenTween = nil :: Tween?,
		barScale = barScale,
		ringTweens = {} :: { [TextButton]: Tween },
		flash = flash,
		caption = caption,
		captionLabel = captionLabel,
		barW = barW,
	}
end

refreshButtons = function()
	if not ui then
		return
	end
	for id, b in ui.buttons do
		local on = anim.current == id
		local g = b:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = if on then ColorSequence.new(lighter(C.magenta, 0.08), Color3.fromRGB(196, 40, 150)) else ColorSequence.new(lighter(C.card2, 0.04), C.card)
		end
		local cap = b:FindFirstChild("Caption")
		if cap and cap:IsA("TextLabel") then
			cap.TextColor3 = if on then Color3.new(1, 1, 1) else C.sub
		end
		local hair = b:FindFirstChild("Hairline")
		if hair and hair:IsA("UIStroke") then
			hair.Transparency = if on then 0.6 else 0.86
		end
		local ring = b:FindFirstChild("Ring")
		local rs = ring and ring:FindFirstChild("RingStroke")
		local running = ui.ringTweens[b]
		if on and ring and rs then
			ring.Visible = true
			if not running and not motionReduced() then
				(rs :: UIStroke).Transparency = 0.15
				local t = TweenService:Create(rs, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.75 })
				t:Play()
				ui.ringTweens[b] = t
			end
		elseif ring then
			ring.Visible = false
			if running then
				running:Cancel()
				ui.ringTweens[b] = nil
			end
		end
	end
end

-- bar right above the "bottomCenter" slot (Now Playing), hands-up above the bar, caption at the
-- slot itself (the Now Playing card hides during the photo? no: it stays; the caption sits over it)
local function layoutUI()
	if not ui then
		return
	end
	loadKit()
	local g: ScreenGui = ui.gui
	local area = areaOf(g)
	local W, H = area.X, area.Y
	local barH = BTN + 2 * GAP
	local cx, bottom
	local bc = layoutRect("bottomCenter")
	if bc then
		cx = bc.x + bc.w / 2
		bottom = bc.y - 8
	else
		local touch = UserInputService.TouchEnabled
		if touch and W > H then
			local left = W * 0.4 + 8
			local right = W - 190
			cx = (left + right) / 2
			bottom = H - 8 - 60 - 8
		elseif touch then
			cx = W / 2
			bottom = H * 0.4 - 8
		else
			cx = W / 2
			bottom = H - 12 - 60 - 8
		end
	end
	-- keep the bar on screen
	local half = ui.barW / 2
	cx = math.clamp(cx, half + 8, math.max(half + 8, W - half - 8))
	bottom = math.clamp(bottom, barH + 8, H - 8)
	ui.bar.Position = UDim2.fromOffset(cx, bottom)
	ui.hands.Position = UDim2.fromOffset(cx, bottom - barH - 8)
	ui.caption.Position = UDim2.fromOffset(cx, bottom)
end

-- another full-screen UI (phone, bowling, dialog sheet) asks the HUD layers to step aside
local function hiddenByOther(): boolean
	local pg = playerGui()
	if not pg then
		return false
	end
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and g.Enabled and g:GetAttribute("HideGwangalliHUD") == true and g.Name ~= "ClubMenuUI" then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------
-- Bottle-service menu
---------------------------------------------------------------------------------------------------
-- Built once (first table prompt) and refilled per payload: a right-hand sheet in the same language
-- as the travel sheet ("sheetRight" slot, dim backdrop, spring in). Rows show the price against the
-- wallet (Money + Bank attributes): unaffordable rows are dimmed with "잔액 부족"; a tap selects a row
-- and raises a confirm bar ("주문하기 · 150,000원" + the balance after), a second tap orders. Nothing
-- is charged here: the server's ClubOrder flow pays and replies.
local menu = { gui = nil :: ScreenGui?, panel = nil :: Frame?, openedAt = 0, tableId = "", ui = nil :: any, payload = nil :: any, selected = nil :: string?, serial = 0 }

-- the sheet is modal on touch (like the travel sheet): character controls pause while it is open so
-- its rows can use the jump-button corner
local controlsOff = false
local function setControls(enabled: boolean)
	if enabled == not controlsOff then
		return
	end
	controlsOff = not enabled
	pcall(function()
		local ps = player:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if pm and pm:IsA("ModuleScript") then
			local controls = (require(pm) :: any):GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end)
end

local function wallet(): (number?, number?)
	local m, b = player:GetAttribute("Money"), player:GetAttribute("Bank")
	return if type(m) == "number" then m else nil, if type(b) == "number" then b else nil
end

local function closeMenu()
	local g = menu.gui
	menu.tableId = ""
	menu.selected = nil
	if not g or not g.Enabled then
		return
	end
	menu.serial += 1
	local mine = menu.serial
	local mu = menu.ui
	g:SetAttribute("HideGwangalliHUD", false)
	setControls(true)
	g:SetAttribute("SheetOpenRight", false)
	if mu then
		springSerial[mu.panel] = (springSerial[mu.panel] or 0) + 1
		tw(mu.panel, 0.2, { Position = mu.rest + UDim2.fromOffset(mu.slideX, mu.slideY) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		tw(mu.backdrop, 0.18, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	end
	task.delay(0.21, function()
		if menu.serial == mine then
			g.Enabled = false
		end
	end)
end

local function buildMenu(pg: PlayerGui): any
	local g = newScreenGui("ClubMenuUI", 40)
	local backdrop = make("Frame", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Active = true }, g)
	backdrop.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			closeMenu()
		end
	end)
	local panel = make("Frame", { Name = "BottleMenu", BackgroundColor3 = C.glass, BackgroundTransparency = 0.04, BorderSizePixel = 0, Size = UDim2.fromOffset(360, 300), Active = true, ClipsDescendants = true, ZIndex = 2 }, g)
	corner(panel, 22)
	stroke(panel, C.line, 1, 0.84)
	-- header: gold tile, title, table label, close
	local tile = make("Frame", { Name = "Icon", Position = UDim2.fromOffset(14, 12), Size = UDim2.fromOffset(38, 38), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3 }, panel)
	corner(tile, UDim.new(0.28, 0))
	gradient(tile, Color3.fromRGB(255, 214, 110), Color3.fromRGB(230, 140, 40), 125)
	make("TextLabel", { Name = "Glyph", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "🍾", TextSize = 20, Font = FONT.bold, TextColor3 = C.text, ZIndex = 4 }, tile)
	make("TextLabel", { Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(62, 11), Size = UDim2.new(1, -124, 0, 22), Text = "보틀 서비스", TextSize = 18, Font = FONT.heavy, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, panel)
	local sub = make("TextLabel", { Name = "Sub", BackgroundTransparency = 1, Position = UDim2.fromOffset(62, 33), Size = UDim2.new(1, -124, 0, 16), Text = "", TextSize = 12, Font = FONT.medium, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 }, panel)
	local close = make("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 9), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = C.card2, BorderSizePixel = 0, AutoButtonColor = false, Text = "✕", TextSize = 17, Font = FONT.bold, TextColor3 = C.text, ZIndex = 3 }, panel)
	corner(close, UDim.new(0.5, 0))
	stroke(close, C.line, 1, 0.88)
	pressable(close, 0.9)
	close.Activated:Connect(function()
		feedback("tap")
		closeMenu()
	end)
	-- wallet pills (cash / bank), or the free-event pill
	local walletRow = make("Frame", { Name = "Wallet", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 60), Size = UDim2.new(1, -28, 0, 24), ZIndex = 3 }, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, walletRow)
	local function pill(name: string, order: number): TextLabel
		local l = make("TextLabel", { Name = name, BackgroundColor3 = C.card2, BackgroundTransparency = 0, Size = UDim2.fromOffset(120, 24), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 12, Font = FONT.bold, TextColor3 = C.text, LayoutOrder = order, ZIndex = 3 }, walletRow)
		corner(l, UDim.new(0.5, 0))
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, l)
		l.Size = UDim2.fromOffset(0, 24)
		return l
	end
	local cashPill, bankPill = pill("Cash", 1), pill("Bank", 2)
	local list = make("ScrollingFrame", { Name = "Items", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 92), Size = UDim2.new(1, -24, 1, -100), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, ScrollBarImageTransparency = 0.5, ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 3 }, panel)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, list)
	make("UIPadding", { PaddingBottom = UDim.new(0, 8) }, list)
	local note = make("TextLabel", { Name = "Note", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -10), Size = UDim2.new(1, -32, 0, 18), Text = "", TextSize = 12, Font = FONT.medium, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 }, panel)
	-- confirm bar (slides up from the bottom edge when a row is selected)
	local confirm = make("Frame", { Name = "Confirm", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 76), Size = UDim2.new(1, 0, 0, 74), BackgroundColor3 = C.glass, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 6 }, panel)
	make("Frame", { Name = "Hairline", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.line, BackgroundTransparency = 0.88, BorderSizePixel = 0, ZIndex = 6 }, confirm)
	local orderBtn = make("TextButton", { Name = "Order", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 9), Size = UDim2.new(1, -24, 0, 44), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AutoButtonColor = false, Text = "주문하기", TextSize = 15, Font = FONT.heavy, TextColor3 = Color3.fromRGB(44, 28, 0), ZIndex = 7 }, confirm)
	corner(orderBtn, UDim.new(0.5, 0))
	gradient(orderBtn, Color3.fromRGB(255, 218, 120), Color3.fromRGB(255, 164, 48), 90)
	pressable(orderBtn, 0.96)
	local after = make("TextLabel", { Name = "After", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, -24, 0, 14), Text = "", TextSize = 11, Font = FONT.medium, TextColor3 = C.sub, ZIndex = 7 }, confirm)
	g.Parent = pg
	return { gui = g, backdrop = backdrop, panel = panel, sub = sub, cashPill = cashPill, bankPill = bankPill, walletRow = walletRow, list = list, note = note, confirm = confirm, orderBtn = orderBtn, after = after, rows = {} :: { [string]: any }, rest = UDim2.new(), slideX = 0, slideY = 0, rowH = 56 }
end

local function sendOrder(itemId: string)
	local p = menu.payload
	if not p then
		return
	end
	local remote = ReplicatedStorage:FindFirstChild(NAMES.Remote or "ClubRemote")
	if remote and remote:IsA("RemoteEvent") then
		pcall(function()
			remote:FireServer("order", p.table, itemId)
		end)
		feedback("success")
	end
	closeMenu()
end

local function selectItem(id: string?)
	local mu = menu.ui
	if not mu then
		return
	end
	menu.selected = id
	for rid, r in mu.rows do
		local on = rid == id
		r.stroke.Color = if on then C.gold elseif r.parade then C.gold else C.line
		r.stroke.Transparency = if on then 0.1 elseif r.parade then 0.6 else 0.9
		r.check.Visible = on
	end
	local it = nil
	for _, x in (menu.payload and menu.payload.items) or {} do
		if type(x) == "table" and x.id == id then
			it = x
		end
	end
	if it then
		local priced = menu.payload.priced == true and type(it.price) == "number"
		mu.orderBtn.Text = if priced then string.format("%s · %s 주문하기", tostring(it.label or it.id), won(it.price)) else string.format("%s · 무료로 주문하기", tostring(it.label or it.id))
		local m, b = wallet()
		if priced and m and b then
			local rest = math.max(0, m + b - it.price)
			mu.after.Text = string.format("현금·통장에서 결제 · 결제 후 %s", won(rest))
		else
			mu.after.Text = "이벤트 무료 · 결제 없음"
		end
		spring(mu.confirm, 0.34, { Position = UDim2.new(0, 0, 1, -2) }, { Position = UDim2.new(0, 0, 1, 0) })
		-- the list ends above the bar; keep the selected row in view
		mu.list.Size = UDim2.new(1, -24, 1, -(92 + 78))
		local rr = mu.rows[id :: string]
		if rr then
			local top = rr.row.AbsolutePosition.Y - mu.list.AbsolutePosition.Y + mu.list.CanvasPosition.Y
			local viewH = mu.list.AbsoluteSize.Y
			if top + rr.row.AbsoluteSize.Y > mu.list.CanvasPosition.Y + viewH then
				mu.list.CanvasPosition = Vector2.new(0, math.max(0, top + rr.row.AbsoluteSize.Y - viewH + 4))
			end
		end
	else
		tw(mu.confirm, 0.18, { Position = UDim2.new(0, 0, 1, 76) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		mu.list.Size = UDim2.new(1, -24, 1, -(92 + 30))
	end
end

local function menuRow(mu: any, it: any, i: number, blocked: boolean, priced: boolean, total: number?)
	local rowH = mu.rowH
	local row = make("TextButton", { Name = "Item_" .. it.id, Size = UDim2.new(1, 0, 0, rowH), BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = i, ZIndex = 3 }, mu.list)
	local card = make("Frame", { Name = "Card", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3 }, row)
	corner(card, 14)
	gradient(card, lighter(C.card, 0.035), C.card, 90)
	local st = stroke(card, if it.parade then C.gold else C.line, 1, if it.parade then 0.6 else 0.9)
	local iconS = rowH - 16
	local tile = make("Frame", { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(iconS, iconS), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 4 }, card)
	corner(tile, UDim.new(0.28, 0))
	if it.parade then
		gradient(tile, Color3.fromRGB(255, 120, 190), Color3.fromRGB(150, 70, 255), 125)
	else
		gradient(tile, Color3.fromRGB(86, 226, 250), Color3.fromRGB(40, 150, 220), 125)
	end
	make("TextLabel", { Name = "Glyph", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = tostring(it.icon or "🍾"), TextSize = math.floor(iconS * 0.52), Font = FONT.bold, TextColor3 = C.text, ZIndex = 5 }, tile)
	local tx = iconS + 18
	local affordable = not priced or total == nil or type(it.price) ~= "number" or total >= it.price
	local ink = if affordable and not blocked then C.text else C.sub
	make("TextLabel", { Name = "Label", BackgroundTransparency = 1, Position = UDim2.new(0, tx, 0.5, -18), Size = UDim2.new(1, -(tx + 88), 0, 19), Text = tostring(it.label or it.id), TextSize = 14, Font = FONT.bold, TextColor3 = ink, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 }, card)
	make("TextLabel", { Name = "Desc", BackgroundTransparency = 1, Position = UDim2.new(0, tx, 0.5, 2), Size = UDim2.new(1, -(tx + 88), 0, 16), Text = tostring(it.desc or ""), TextSize = 12, Font = FONT.medium, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 }, card)
	local priceText = if priced and type(it.price) == "number" then won(it.price) else "무료"
	make("TextLabel", { Name = "Price", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, if affordable then 0 else -8), Size = UDim2.fromOffset(76, 20), Text = priceText, TextSize = 14, Font = FONT.heavy, TextColor3 = if not affordable then C.sub elseif it.parade then C.gold else C.text, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 }, card)
	if not affordable then
		make("TextLabel", { Name = "Short", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 10), Size = UDim2.fromOffset(76, 14), Text = "잔액 부족", TextSize = 11, Font = FONT.bold, TextColor3 = C.red, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 }, card)
	end
	-- selection badge on the icon's corner
	local check = make("TextLabel", { Name = "Check", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -2, 1, -2), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = C.gold, Text = "✓", TextSize = 12, Font = FONT.heavy, TextColor3 = Color3.fromRGB(44, 28, 0), Visible = false, ZIndex = 6 }, tile)
	corner(check, UDim.new(0.5, 0))
	stroke(check, C.card, 2, 0)
	local veil = make("Frame", { Name = "Veil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.glass, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 8 }, card)
	corner(veil, 14)
	local sc = make("UIScale", { Name = "Press", Scale = 1 }, card)
	row.MouseButton1Down:Connect(function()
		tw(sc, 0.08, { Scale = 0.97 }, Enum.EasingStyle.Quad)
	end)
	local function up()
		spring(sc, 0.28, { Scale = 1.01 }, { Scale = 1 })
	end
	row.MouseButton1Up:Connect(up)
	row.MouseLeave:Connect(up)
	local itemId = it.id
	row.Activated:Connect(function()
		if blocked then
			toast(if menu.payload and menu.payload.busy then "이 테이블은 지금 보틀 서비스 중이에요" else "다음 주문까지 잠시만 기다려 주세요", "⏳")
			return
		end
		if not affordable then
			-- inline "no": the card shakes and the note line says why (no toast over the sheet)
			feedback("error")
			local seq = { 7, -6, 4, -2, 0 }
			task.spawn(function()
				for _, dx in seq do
					tw(card, 0.05, { Position = UDim2.fromOffset(dx, 0) }, Enum.EasingStyle.Sine)
					task.wait(0.05)
				end
				card.Position = UDim2.new()
			end)
			local mu2 = menu.ui
			if mu2 then
				mu2.note.Text = "잔액이 부족해요 · 알바로 돈을 모으거나 통장을 확인해 보세요"
				mu2.note.TextColor3 = C.red
				local mine = menu.serial
				task.delay(3, function()
					if menu.serial == mine and mu2.note.Parent then
						mu2.note.Text = "퍼레이드: 스태프가 스파클러를 들고 테이블까지 와요 ✨"
						mu2.note.TextColor3 = C.sub
					end
				end)
			end
			return
		end
		feedback("tap")
		if menu.selected == itemId then
			sendOrder(itemId)
		else
			selectItem(itemId)
		end
	end)
	mu.rows[itemId] = { row = row, card = card, veil = veil, stroke = st, check = check, parade = it.parade == true }
end

local function openMenu(payload: any)
	if type(payload) ~= "table" or type(payload.table) ~= "string" or type(payload.items) ~= "table" then
		return
	end
	loadKit()
	local pg = playerGui()
	if not pg then
		return
	end
	if not menu.ui or not menu.ui.gui.Parent then
		menu.ui = buildMenu(pg)
		menu.gui = menu.ui.gui
	end
	local mu = menu.ui
	local g: ScreenGui = mu.gui
	menu.payload = payload
	menu.selected = nil
	menu.serial += 1
	-- geometry: the sheetRight slot (the travel sheet's place) or a centred card
	local area = areaOf(g)
	local r = layoutRect("sheetRight")
	local w, h, x, y
	if r then
		w, h, x, y = math.min(r.w, 400), r.h, r.x + r.w - math.min(r.w, 400), r.y
	else
		w = math.min(400, area.X - 16)
		h = math.min(420, area.Y - 16)
		x, y = (area.X - w) / 2, (area.Y - h) / 2
	end
	local items = payload.items
	mu.rowH = if h < 330 then 50 else 58
	-- never taller than the content (+ room for the confirm bar): short menus stay compact on
	-- tablets / PC instead of a mostly empty full-height sheet
	local contentH = 92 + #items * (mu.rowH + 6) + 30 + 80
	h = math.min(h, contentH)
	mu.panel.Size = UDim2.fromOffset(math.floor(w), math.floor(h))
	mu.rest = UDim2.fromOffset(math.floor(x), math.floor(y))
	local portrait = area.X < area.Y
	mu.slideX, mu.slideY = if portrait then 0 else w + 24, if portrait then h + 24 else 0
	-- header / wallet
	local m, b = wallet()
	local priced = payload.priced == true
	mu.sub.Text = tostring(payload.label or payload.table)
	if priced and m and b then
		mu.cashPill.Visible, mu.bankPill.Visible = true, true
		mu.cashPill.Text = "현금  " .. won(m)
		mu.bankPill.Text = "통장  " .. won(b)
		mu.cashPill.TextColor3, mu.bankPill.TextColor3 = C.text, C.text
		mu.cashPill.BackgroundColor3 = C.card2
	elseif not priced then
		mu.cashPill.Visible, mu.bankPill.Visible = true, false
		mu.cashPill.Text = "오늘은 이벤트로 무료!"
		mu.cashPill.TextColor3 = C.gold
	else
		mu.cashPill.Visible, mu.bankPill.Visible = false, false
	end
	-- rows (rebuilt only when the menu contents change; the menu is 3 static items)
	local blocked = payload.busy == true or (type(payload.cooldown) == "number" and payload.cooldown > 0)
	for _, rr in mu.rows do
		rr.row:Destroy()
	end
	table.clear(mu.rows)
	local total = if m and b then m + b else nil
	for i, it in items do
		if type(it) == "table" and type(it.id) == "string" then
			menuRow(mu, it, i, blocked, priced, total)
		end
	end
	mu.note.Text = if payload.busy then "이 테이블은 지금 보틀 서비스 중이에요"
		elseif type(payload.cooldown) == "number" and payload.cooldown > 0 then string.format("다음 주문까지 %d초", payload.cooldown)
		else "퍼레이드: 스태프가 스파클러를 들고 테이블까지 와요 ✨"
	mu.note.TextColor3 = if blocked then C.gold else C.sub
	mu.list.Size = UDim2.new(1, -24, 1, -(92 + 30))
	mu.confirm.Position = UDim2.new(0, 0, 1, 76)
	-- open: backdrop fade, sheet springs in, rows reveal 25 ms apart
	g:SetAttribute("HideGwangalliHUD", true) -- the sheet covers the right column (Layout contract)
	g.Enabled = true
	if UserInputService.TouchEnabled then
		setControls(false)
	end
	-- where the sheet is, for the shared toast stack (docs/ui_kit_requests.md #3)
	g:SetAttribute("SheetOpenRight", not portrait)
	g:SetAttribute("SheetLeft", math.floor(x + g.AbsolutePosition.X))
	mu.backdrop.BackgroundTransparency = 1
	tw(mu.backdrop, 0.24, { BackgroundTransparency = 0.5 }, Enum.EasingStyle.Quad)
	mu.panel.Position = mu.rest + UDim2.fromOffset(mu.slideX, mu.slideY)
	local past = mu.rest - UDim2.fromOffset(if portrait then 0 else 12, if portrait then 10 else 0)
	spring(mu.panel, 0.42, { Position = past }, { Position = mu.rest })
	local i = 0
	for _, it in items do
		local rr = type(it) == "table" and mu.rows[it.id]
		if rr and not motionReduced() then
			i += 1
			rr.veil.BackgroundTransparency = 0
			rr.card.Position = UDim2.fromOffset(30 + i * 4, 0)
			task.delay(0.06 + (i - 1) * 0.025, function()
				tw(rr.card, 0.34, { Position = UDim2.new() })
				tw(rr.veil, 0.26, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			end)
		end
	end
	menu.panel, menu.openedAt, menu.tableId = mu.panel, os.clock(), payload.table
	feedback("open")
end

task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild(NAMES.Remote or "ClubRemote", 120)
	if not remote or not remote:IsA("RemoteEvent") then
		return
	end
	(remote :: RemoteEvent).OnClientEvent:Connect(function(kind: any, payload: any)
		if kind == "menu" then
			local ok, err = pcall(openMenu, payload)
			if not ok then
				warn("[ClubDance] menu:", err)
			end
		end
	end)
end)

---------------------------------------------------------------------------------------------------
-- State loop (10 Hz inside, 4 Hz outside; no per-frame work)
---------------------------------------------------------------------------------------------------
local visible = false
local acc = 0
local lastCountdown = 0

local function tick()
	local inside = Bus.state == "Inside" and Bus.showRoom == true
	local now = os.clock()
	local hum = humanoidOf()
	-- the menu closes when the player leaves the club or after a minute
	if menu.tableId ~= "" and (Bus.state ~= "Inside" or now - menu.openedAt > 60) then
		closeMenu()
	end
	-- dances stop on movement / jump / sit / leaving
	if anim.track or anim.cheerTrack then
		local moving = false
		if hum then
			moving = hum.MoveDirection.Magnitude > 0.1 or hum.Jump or hum.Sit
		end
		if not hum or not inside or moving then
			if anim.track then
				stopDance()
			end
			if anim.cheerTrack and (not hum or not inside) then
				stopCheer()
			end
		end
		if anim.cheerTrack and now >= anim.cheerUntil then
			stopCheer()
		end
	end
	local show = inside and hum ~= nil and now >= photoHideUntil and menu.tableId == "" and not hiddenByOther()
	if show and not ui then
		ui = buildUI()
		if ui then
			layoutUI()
			if Layout and typeof(Layout.changed) == "RBXScriptSignal" then
				Layout.changed:Connect(layoutUI)
			end
			local cam = workspace.CurrentCamera
			if cam then
				cam:GetPropertyChangedSignal("ViewportSize"):Connect(layoutUI)
			end
			refreshButtons()
		end
	end
	if not ui then
		return
	end
	if show ~= visible then
		visible = show
		if show then
			layoutUI()
		end
	end
	-- the gui stays enabled during the photo so the flash / caption show; the bar hides
	local photoing = now < photoHideUntil
	local want = show or photoing
	if ui.gui.Enabled ~= want then
		ui.gui.Enabled = want
	end
	if ui.bar.Visible ~= show then
		ui.bar.Visible = show
		if show then
			-- rise in: bar lifts 14 px with a small overshoot, buttons pop in one after another
			local rest = ui.bar.Position
			ui.bar.Position = rest + UDim2.fromOffset(0, 14)
			spring(ui.bar, 0.4, { Position = rest - UDim2.fromOffset(0, 3) }, { Position = rest })
			local i = 0
			for _, b in ui.buttons do
				i += 1
				local sc = b:FindFirstChild("Press")
				if sc and sc:IsA("UIScale") and not motionReduced() then
					sc.Scale = 0.6
					task.delay(0.04 + i * 0.03, function()
						spring(sc, 0.36, { Scale = 1.06 }, { Scale = 1 })
					end)
				end
			end
		end
	end
	-- hands up: 6 s after every drop, and while the LED wall counts down
	local serial = Bus.dropSerial or 0
	if serial ~= lastDropSerial then
		if lastDropSerial >= 0 and inside then
			handsUntil = now + 6
		end
		lastDropSerial = serial
	end
	local countdown = tonumber(Bus.countdown) or 0
	local handsOn = show and (now < handsUntil or countdown > 0)
	if ui.hands.Visible ~= handsOn then
		ui.hands.Visible = handsOn
		if ui.sheenTween then
			ui.sheenTween:Cancel()
			ui.sheenTween = nil
		end
		if handsOn then
			ui.handsPopAt = now
			ui.handsScale.Scale = 0.5
			spring(ui.handsScale, 0.4, { Scale = 1.08 }, { Scale = 1 })
			if not motionReduced() then
				ui.sheenGrad.Offset = Vector2.new(-1, 0)
				local t = TweenService:Create(ui.sheenGrad, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0.4), { Offset = Vector2.new(1, 0) })
				t:Play()
				ui.sheenTween = t
			end
		end
	end
	if handsOn then
		local label = if countdown > 0 then string.format("🙌  READY %d", countdown) else "🙌  손 들어!"
		if ui.hands.Text ~= label then
			ui.hands.Text = label
		end
		if countdown ~= lastCountdown or countdown == 0 then
			-- pulse on the beat
			local since = now - (Bus.beatAt or 0)
			local s = 1 + 0.08 * math.exp(-since * 6)
			if now - (ui.handsPopAt or 0) > 0.45 and math.abs(ui.handsScale.Scale - s) > 0.01 then
				ui.handsScale.Scale = s
			end
		end
	end
	lastCountdown = countdown
end

RunService.Heartbeat:Connect(function(dt)
	acc += dt
	local inside = Bus.state == "Inside"
	local period = if inside or visible then 0.1 else 0.25
	if acc < period then
		return
	end
	acc = 0
	local ok, err = pcall(tick)
	if not ok then
		warn("[ClubDance] tick:", err)
	end
end)

player.CharacterAdded:Connect(function()
	anim.track, anim.current, anim.cheerTrack = nil, nil, nil
	anim.humanoid, anim.animator = nil, nil
	table.clear(anim.tracks)
	refreshButtons()
end)
