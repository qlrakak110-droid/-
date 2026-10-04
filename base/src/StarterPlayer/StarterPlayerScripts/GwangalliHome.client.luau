-- GwangalliHome (LocalScript): the player side of 자기집 마련 (server: GwangalliGameplay/Housing).
--   * building entrances (parts tagged "HomeEntrance", attribute Tier): local ProximityPrompts with
--     per-player text -- 집으로 들어가기 (you live here), 초인종 (someone who lives here is online),
--     입주 문의 (listing card -> 월세 계약 / 매매 / 대출 매매 through the existing remotes)
--   * in-home HUD bar (GwangalliLayout slot "bottomCenter"): home name + tier chip, 꾸미기, 초대하기,
--     나가기 (guests: whose home + 나가기)
--   * sheets (slot "sheetRight", modal, HideGwangalliHUD): 꾸미기 (slot-based decoration: pick a slot
--     -> choose a variant -> live preview -> buy / place / sell; 창고; 리모델링 + 대출), 초대하기
--     (players list, kick), 냉장고 (집밥 / 장보기 / 배달), 책상 (통장·제안), 우편함 (고지서), 옷장
--   * doorbell / invite popups, window photo moment (scripted camera), TV screen content, home poses
--     (ReplicatedStorage.GwangalliAnim when present, else small procedural motions)
-- Remotes (ReplicatedStorage.GwangalliRemotes): HomeAction (-> server), HomeState (<- server),
-- PhoneAction (rentHome / buyHome / equip). Contract: GwangalliGameplayShared "자기집 마련" section.
-- Phone hook: to open a phone app this script fires the BindableEvent LocalPlayer.GwangalliPhoneOpen
-- (app, args) when the phone created it; otherwise it shows a toast pointing at the app.
-- 인테리어 mode / 집 구경 / 둘러보기: GwangalliHome/Interior (the Folder next to this script). Other
-- client scripts open them through GwangalliHome/Api (or LocalPlayer.GwangalliHomeOpen:Fire("interior")
-- | :Fire("tour", listingId) | :Fire("close"); LocalPlayer.GwangalliHomeQuery:Invoke("state")).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local function optionalModule(name: string, timeout: number?): any
	local m = ReplicatedStorage:FindFirstChild(name)
	if not m and timeout then
		m = ReplicatedStorage:WaitForChild(name, timeout)
	end
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
	end
	return nil
end

local G: any = optionalModule("GwangalliGameplayShared", 30)
local K: any = optionalModule("GwangalliUI", 15)
if not G or not K then
	warn("[GwangalliHome] GwangalliGameplayShared / GwangalliUI missing; home HUD disabled")
	return
end
local Layout: any = optionalModule("GwangalliLayout")
local Anim: any = optionalModule("GwangalliAnim")
ReplicatedStorage.ChildAdded:Connect(function(c)
	if c.Name == "GwangalliAnim" and not Anim then
		task.delay(0.5, function()
			Anim = optionalModule("GwangalliAnim")
		end)
	elseif c.Name == "GwangalliLayout" and not Layout then
		task.delay(0.5, function()
			Layout = optionalModule("GwangalliLayout")
		end)
	end
end)

local playerGui = player:WaitForChild("PlayerGui", 30)
if not playerGui then
	warn("[GwangalliHome] PlayerGui missing")
	return
end

local remotesFolder = ReplicatedStorage:WaitForChild(G.RemotesFolder, 60)
if not remotesFolder then
	warn("[GwangalliHome] remotes folder missing")
	return
end
local HomeAction = remotesFolder:WaitForChild("HomeAction", 60)
local HomeState = remotesFolder:WaitForChild("HomeState", 60)
local PhoneAction = remotesFolder:WaitForChild(G.Remote.PhoneAction, 30)
if not (HomeAction and HomeAction:IsA("RemoteEvent") and HomeState and HomeState:IsA("RemoteEvent")) then
	warn("[GwangalliHome] HomeAction / HomeState remotes missing; home HUD disabled")
	return
end

local C = K.Color
local CYAN = C.cyan or C.teal or Color3.fromRGB(61, 214, 245)
local GOLD = C.gold or Color3.fromRGB(255, 204, 64)
local GREEN = C.green or C.success or Color3.fromRGB(52, 211, 120)
local RED = C.red or Color3.fromRGB(255, 84, 84)
local SUB = C.sub or Color3.fromRGB(170, 176, 192)
local TEXT = C.text or Color3.fromRGB(246, 247, 251)
local CARD = C.card or Color3.fromRGB(30, 32, 42)
local FONT_B = (K.Font and K.Font.bold) or Enum.Font.GothamBold
local FONT_M = (K.Font and K.Font.medium) or Enum.Font.GothamMedium

-- Motion policy (docs/ui_kit_requests.md #1): phones default to the "low" graphics tier, but UI
-- tweens are cheap; motion is reduced only for the player's setting, a low graphics slider or low fps.
local Quality: any = optionalModule("GwangalliQuality")
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
	if K and type(K.spring) == "function" and type(K.reduced) == "function" then
		local okK, red = pcall(K.reduced)
		if okK then
			motionCache = red == true
			return motionCache
		end
	end
	if type(K.settings) == "table" and K.settings.reducedMotion == true then
		r = true
	elseif Quality and type(Quality.isLow) == "function" and Quality.isLow() == true then
		local why = if type(Quality.reason) == "function" then string.lower(tostring(Quality.reason())) else ""
		r = string.find(why, "frame", 1, true) ~= nil or string.find(why, "slider", 1, true) ~= nil or string.find(why, "chosen", 1, true) ~= nil
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
local springSerial: { [Instance]: number } = {}
local function spring(inst: Instance, t: number, past: { [string]: any }, goals: { [string]: any })
	local n = (springSerial[inst] or 0) + 1
	springSerial[inst] = n
	local first = tw(inst, t * 0.7, past)
	if not first then
		tw(inst, 0, goals)
		return
	end
	first.Completed:Connect(function(st)
		if st == Enum.PlaybackState.Completed and springSerial[inst] == n then
			tw(inst, t * 0.45, goals, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	end)
end

local function won(n: number): string
	local ok, s = pcall(K.won, n)
	return if ok then s else G.format.won(n)
end

local function toast(kind: string, title: string, body: string?)
	local ok = pcall(K.toast, { kind = kind, title = title, body = body or "" })
	if not ok then
		print("[GwangalliHome] " .. title .. " " .. (body or ""))
	end
end

local function act(action: string, payload: any?)
	HomeAction:FireServer(action, payload or {})
end

local function phoneAct(action: string, payload: any?)
	if PhoneAction and PhoneAction:IsA("RemoteEvent") then
		PhoneAction:FireServer(action, payload or {})
	end
end

local function rgb(t: { number }?, fallback: Color3?): Color3
	if type(t) == "table" and t[1] then
		return Color3.fromRGB(t[1], t[2], t[3])
	end
	return fallback or Color3.new(1, 1, 1)
end

-- Opens a phone app through the phone's BindableEvent (see the header), else a hint toast.
local APP_NAMES = { bank = "통장", messages = "메시지", realty = "부동산", shop = "쇼핑", profile = "내 정보" }
local function openPhoneApp(app: string, args: any?)
	local ev = player:FindFirstChild("GwangalliPhoneOpen")
	if ev and ev:IsA("BindableEvent") then
		ev:Fire(app, args)
		return
	end
	toast("info", "📱 폰 → " .. (APP_NAMES[app] or app), "폰을 열어 '" .. (APP_NAMES[app] or app) .. "' 앱을 확인해요")
end

-------------------------------------------------------------------------------------------------
-- GUI roots
-------------------------------------------------------------------------------------------------
local function newGui(name: string, order: number): ScreenGui
	local old = playerGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = false
	pcall(function()
		(g :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	g.DisplayOrder = order
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = playerGui
	return g
end

local hudGui = newGui("GwangalliHome", 12)
local sheetGui = newGui("GwangalliHomeSheet", 15)
sheetGui.Enabled = false
sheetGui:SetAttribute("HideGwangalliHUD", true)
local popGui = newGui("GwangalliHomePopup", 31)

type Rect = { x: number, y: number, w: number, h: number }
local function guiSize(g: ScreenGui): Vector2
	local s = g.AbsoluteSize
	if s.X < 10 then
		local cam = workspace.CurrentCamera
		s = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	end
	return s
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function fallbackRect(name: string): Rect
	local s = guiSize(hudGui)
	local W, H = s.X, s.Y
	local phone = isTouch() and math.min(W, H) <= 500
	if name == "bottomCenter" then
		local w = math.min(420, W - 16)
		if phone and W > H then
			local left = W * 0.4
			local right = W - 150
			w = math.min(380, right - left)
			return { x = left + (right - left - w) / 2, y = H - 8 - 60, w = w, h = 60 }
		end
		return { x = (W - w) / 2, y = H - 16 - 60 - (if phone then H * 0.3 else 0), w = w, h = 60 }
	elseif name == "sheetRight" then
		if phone and W > H then
			local w = math.max(280, math.floor(W * 0.44))
			return { x = W - 8 - w, y = 8, w = w, h = H - 16 }
		elseif phone then
			local y = math.floor(H * 0.3)
			return { x = 0, y = y, w = W, h = H - y }
		end
		local w = 400
		local h = math.min(640, H - 32)
		return { x = W - 16 - w - 90, y = (H - h) / 2, w = w, h = h }
	end
	return { x = 8, y = 8, w = 200, h = 50 }
end

local function rectOf(name: string): Rect
	if Layout and type(Layout.rect) == "function" then
		local ok, r = pcall(Layout.rect, name)
		if ok and type(r) == "table" and (r.w or 0) > 40 and (r.h or 0) > 30 then
			return r
		end
	end
	return fallbackRect(name)
end

-------------------------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------------------------
local state: any = {
	inside = false,
	role = nil,
	ownerId = 0,
	ownerName = "",
	homeName = "",
	tierKey = "",
	tierName = "",
	icon = "🏠",
	maxGuests = 1,
	guests = {},
	slots = {},
	housing = nil,
	owned = false,
	tvOn = false,
	model = nil,
	modelName = "",
}
local sheet: any = nil -- { kind, frame, close }
local barHiddenByInterior = false -- the 인테리어 mode is up (GwangalliHome/Interior hides the bar)
local refreshSheet: () -> () = function() end
local closeSheet: () -> ()
local exitDecor: () -> ()

-------------------------------------------------------------------------------------------------
-- Controls / camera helpers
-------------------------------------------------------------------------------------------------
local controlsOff = false
local function setControls(on: boolean)
	if on == not controlsOff then
		return
	end
	controlsOff = not on
	local ok, pm = pcall(function()
		local ps = player:FindFirstChild("PlayerScripts")
		local m = ps and ps:FindFirstChild("PlayerModule")
		return m and require(m :: ModuleScript)
	end)
	if ok and pm and type(pm.GetControls) == "function" then
		pcall(function()
			local c = pm:GetControls()
			if on then
				c:Enable()
			else
				c:Disable()
			end
		end)
	end
end

local camSaved: any = nil
local function scriptCamera(cf: CFrame, fov: number?, seconds: number?)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if not camSaved then
		camSaved = { type = cam.CameraType, fov = cam.FieldOfView, subject = cam.CameraSubject }
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local goal: any = { CFrame = cf }
	if fov then
		goal.FieldOfView = fov
	end
	local ok = pcall(function()
		TweenService:Create(cam, TweenInfo.new(seconds or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	end)
	if not ok then
		cam.CFrame = cf
	end
end

local function restoreCamera()
	local cam = workspace.CurrentCamera
	if not cam or not camSaved then
		return
	end
	local saved = camSaved
	camSaved = nil
	cam.CameraType = if saved.type == Enum.CameraType.Scriptable then Enum.CameraType.Custom else saved.type
	cam.FieldOfView = saved.fov or 70
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	cam.CameraSubject = hum or saved.subject
end

-------------------------------------------------------------------------------------------------
-- Poses (GwangalliAnim when available; else small procedural motions on the Motor6Ds)
-------------------------------------------------------------------------------------------------
local poseConn: RBXScriptConnection? = nil
local poseHandle: any = nil
local function stopPose()
	if poseConn then
		poseConn:Disconnect()
		poseConn = nil
	end
	if poseHandle then
		local h = poseHandle
		poseHandle = nil
		pcall(function()
			if type(h) == "table" and type(h.stop) == "function" then
				h.stop()
			elseif type(h) == "table" and type(h.Stop) == "function" then
				h:Stop()
			elseif typeof(h) == "Instance" and h:IsA("AnimationTrack") then
				h:Stop(0.2)
			elseif type(h) == "function" then
				h()
			end
		end)
	end
	local char = player.Character
	if char then
		for _, m in char:GetDescendants() do
			if m:IsA("Motor6D") and m:GetAttribute("HomePose") then
				m:SetAttribute("HomePose", nil)
			end
		end
	end
end

local ANIM_NAMES = { eat = { "eat", "drink", "give" }, shower = { "wash", "wipe", "shrug" }, sleep = { "sleep", "lie", "idle" } }
local function animLibrary(name: string, seconds: number): any
	if not Anim then
		return nil
	end
	local char = player.Character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	for _, gname in ANIM_NAMES[name] or { name } do
		for _, fname in { "playGesture", "gesture", "play", "playEmote" } do
			local f = Anim[fname]
			if type(f) == "function" then
				for _, target in { char, hum } do
					if target then
						local ok, h = pcall(f, target, gname, { duration = seconds, loop = false })
						if ok and h ~= nil and h ~= false then
							return h
						end
					end
				end
			end
		end
	end
	return nil
end

local function motor(char: Model, names: { string }): Motor6D?
	for _, n in names do
		local m = char:FindFirstChild(n, true)
		if m and m:IsA("Motor6D") then
			return m
		end
	end
	return nil
end

local function playPose(name: string, seconds: number?)
	stopPose()
	if name == "none" then
		return
	end
	local dur = seconds or 3
	poseHandle = animLibrary(name, dur)
	if poseHandle or name == "sleep" then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	local arm = motor(char, { "RightShoulder", "Right Shoulder" })
	local neck = motor(char, { "Neck" })
	if not arm then
		return
	end
	local t0 = os.clock()
	poseConn = RunService.Stepped:Connect(function()
		local t = os.clock() - t0
		if t > dur or not arm.Parent then
			stopPose()
			return
		end
		local k = math.min(1, t / 0.3, (dur - t) / 0.3)
		if name == "eat" then
			local bob = (math.sin(t * 5) + 1) / 2
			arm.Transform = CFrame.Angles(math.rad(-(70 + 25 * bob) * k), 0, math.rad(-15 * k))
			if neck then
				neck.Transform = CFrame.Angles(math.rad(8 * k * bob), 0, 0)
			end
		elseif name == "shower" then
			arm.Transform = CFrame.Angles(math.rad(-150 * k), math.rad(20 * math.sin(t * 6) * k), 0)
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- HUD bar (bottomCenter)
-------------------------------------------------------------------------------------------------
local bar = K.frame(hudGui, { Name = "HomeBar", Visible = false, BackgroundTransparency = 0.12, BackgroundColor3 = C.glass or Color3.fromRGB(20, 22, 30) })
K.corner(bar, 16)
K.stroke(bar, nil, 1, 0.84)
local chip = K.frame(bar, { Name = "Chip", Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.46, -10, 1, 0) })
local chipTitle = K.text(chip, { Name = "Title", Position = UDim2.fromScale(0, 0.1), Size = UDim2.new(1, 0, 0.46, 0), Font = FONT_B, TextSize = 15, TextColor3 = TEXT, TextTruncate = Enum.TextTruncate.AtEnd, Text = "" })
local chipSub = K.text(chip, { Name = "Sub", Position = UDim2.fromScale(0, 0.54), Size = UDim2.new(1, 0, 0.36, 0), Font = FONT_M, TextSize = 12, TextColor3 = SUB, TextTruncate = Enum.TextTruncate.AtEnd, Text = "" })
local btnRow = K.frame(bar, { Name = "Buttons", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0.54, -8, 0, 44) })
K.list(btnRow, true, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)

local function barButton(name: string, text: string, style: string, order: number, onClick: () -> ()): TextButton
	local ok, b = pcall(K.Button, btnRow, { name = name, text = text, style = style, size = UDim2.fromOffset(64, 44), order = order, textSize = 13, onClick = onClick })
	if ok and b then
		return b
	end
	local fb = Instance.new("TextButton")
	fb.Name = name
	fb.Size = UDim2.fromOffset(64, 44)
	fb.Text = text
	fb.LayoutOrder = order
	fb.Font = FONT_B
	fb.TextSize = 13
	fb.TextColor3 = TEXT
	fb.BackgroundColor3 = CARD
	fb.Parent = btnRow
	fb.Activated:Connect(onClick)
	return fb
end

local openDecor: () -> ()
local openGuests: () -> ()
local openInterior: () -> ()
local decorBtn = barButton("Decor", "🛠️ 인테리어", "tonal", 1, function()
	openInterior()
end)
local inviteBtn = barButton("Invite", "💌 초대", "secondary", 2, function()
	openGuests()
end)
local leaveBtn = barButton("Leave", "🚪 나가기", "secondary", 3, function()
	act("leave")
end)

local function layoutBar()
	local r = rectOf("bottomCenter")
	local h = math.max(56, math.min(r.h, 64))
	local w = math.max(260, r.w)
	bar.Position = UDim2.fromOffset(r.x + (r.w - w) / 2, r.y + r.h - h)
	bar.Size = UDim2.fromOffset(w, h)
	local owner = state.role == "owner"
	local nb = if owner then 3 else 2
	local bw = math.clamp(math.floor((w * 0.56 - 8 - 6 * (nb - 1)) / nb), 48, 84)
	for _, b in { decorBtn, inviteBtn, leaveBtn } do
		b.Size = UDim2.fromOffset(bw, 44)
		b.TextSize = if bw < 62 then 11 else 13
	end
	decorBtn.Text = if owner then "🛠️ 인테리어" elseif state.role == "viewer" then "📝 계약" else "👀 구경"
	decorBtn.Visible = true
	inviteBtn.Visible = owner
	chip.Size = UDim2.new(1, -(nb * bw + 6 * (nb - 1)) - 26, 1, 0)
	btnRow.Size = UDim2.new(0, nb * bw + 6 * (nb - 1), 0, 44)
end

local function refreshBar()
	if not state.inside then
		bar.Visible = false
		return
	end
	if state.role == "owner" then
		chipTitle.Text = string.format("%s %s", state.icon, state.homeName)
		local guests = #state.guests
		chipSub.Text = string.format("%s · %s%s", state.tierName, if state.owned then "자가" else "월세", if guests > 0 then string.format(" · 손님 %d/%d", guests, state.maxGuests) else "")
	elseif state.role == "viewer" then
		chipTitle.Text = "🔑 " .. state.homeName
		chipSub.Text = string.format("%s · 빈 집 둘러보기", state.tierName)
	else
		chipTitle.Text = string.format("🏠 %s님의 집", state.ownerName)
		chipSub.Text = string.format("%s · %s · 방문 중", state.homeName, state.tierName)
	end
	local want = sheet == nil and not barHiddenByInterior
	local was = bar.Visible
	bar.Visible = want
	layoutBar()
	if want and not was then
		local rest = bar.Position
		bar.Position = rest + UDim2.fromOffset(0, 22)
		spring(bar, 0.42, { Position = rest - UDim2.fromOffset(0, 3) }, { Position = rest })
	end
end

-------------------------------------------------------------------------------------------------
-- Sheet (sheetRight): a modal side sheet
-------------------------------------------------------------------------------------------------
-- dim backdrop behind the modal sheet (a tap on it closes the sheet)
local sheetBackdrop = K.frame(sheetGui, { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BackgroundColor3 = Color3.new(0, 0, 0), Active = true })
local sheetFrame = K.frame(sheetGui, { Name = "Sheet", BackgroundTransparency = 0.06, BackgroundColor3 = C.glass or Color3.fromRGB(20, 22, 30), ClipsDescendants = true, ZIndex = 2 })
K.corner(sheetFrame, 20)
K.stroke(sheetFrame, nil, 1, 0.84)
local sheetHeader = K.frame(sheetFrame, { Name = "Header", Size = UDim2.new(1, 0, 0, 52) })
local sheetTitle = K.text(sheetHeader, { Name = "Title", Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -72, 1, 0), Font = FONT_B, TextSize = 18, TextColor3 = TEXT, Text = "", TextTruncate = Enum.TextTruncate.AtEnd })
local closeBtn: TextButton
do
	local ok, b = pcall(K.Button, sheetHeader, { name = "Close", text = "✕", style = "icon", size = UDim2.fromOffset(44, 44), onClick = function()
		closeSheet()
	end })
	if ok and b then
		closeBtn = b
	else
		closeBtn = Instance.new("TextButton")
		closeBtn.Text = "✕"
		closeBtn.Size = UDim2.fromOffset(44, 44)
		closeBtn.Parent = sheetHeader
		closeBtn.Activated:Connect(function()
			closeSheet()
		end)
	end
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -8, 0.5, 0)
end
local sheetBody = Instance.new("ScrollingFrame")
sheetBody.Name = "Body"
sheetBody.Position = UDim2.fromOffset(0, 52)
sheetBody.Size = UDim2.new(1, 0, 1, -52)
sheetBody.BackgroundTransparency = 1
sheetBody.BorderSizePixel = 0
sheetBody.ScrollBarThickness = 4
sheetBody.CanvasSize = UDim2.new()
sheetBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
sheetBody.ScrollingDirection = Enum.ScrollingDirection.Y
sheetBody.Parent = sheetFrame
K.pad(sheetBody, 12, 12, 4, 16)
K.list(sheetBody, false, 8)
-- content veil: the body fades in just after the shell lands (one frame, no per-row work)
local bodyVeil = K.frame(sheetFrame, { Name = "BodyVeil", Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52), BackgroundTransparency = 1, BackgroundColor3 = C.glass or Color3.fromRGB(20, 22, 30), ZIndex = 20 })
local sheetRest = UDim2.new()
local sheetAway = UDim2.new()
local sheetSerial = 0

local function layoutSheet()
	local r = rectOf("sheetRight")
	sheetRest = UDim2.fromOffset(r.x, r.y)
	local s0 = guiSize(sheetGui)
	sheetAway = if s0.X < s0.Y then UDim2.fromOffset(0, r.h + 24) else UDim2.fromOffset(r.w + 24, 0)
	sheetFrame.Position = sheetRest
	sheetFrame.Size = UDim2.fromOffset(r.w, r.h)
end

local function clearBody()
	for _, c in sheetBody:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function label(text: string, opts: any?): TextLabel
	local o = opts or {}
	-- explicit wrapped height (conservative Hangul width model) as the minimum; AutomaticSize may grow it
	local bodyW = math.max(120, sheetFrame.Size.X.Offset - 24)
	local minH = 0
	pcall(function()
		minH = K.textHeight(text, o.size or 14, bodyW)
	end)
	local l = K.text(sheetBody, {
		Size = UDim2.new(1, 0, 0, minH),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextWrapped = true,
		Font = if o.bold then FONT_B else FONT_M,
		TextSize = o.size or 14,
		TextColor3 = o.color or TEXT,
		LayoutOrder = nextOrder(),
		RichText = o.rich == true,
	})
	return l
end

local function card(height: number?): Frame
	local f = K.frame(sheetBody, { Size = UDim2.new(1, 0, 0, height or 0), AutomaticSize = if height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y, BackgroundTransparency = 0, BackgroundColor3 = CARD, LayoutOrder = nextOrder() })
	K.corner(f, 14)
	K.pad(f, 12, 12, 10, 10)
	return f
end

local function button(parent: Instance, text: string, style: string, onClick: () -> (), size: UDim2?, enabled: boolean?): TextButton
	local ok, b = pcall(K.Button, parent, { text = text, style = style, size = size or UDim2.new(1, 0, 0, 44), order = nextOrder(), textSize = 14, onClick = onClick })
	local btn: TextButton
	if ok and b then
		btn = b
	else
		btn = Instance.new("TextButton")
		btn.Text = text
		btn.Size = size or UDim2.new(1, 0, 0, 44)
		btn.LayoutOrder = order
		btn.Font = FONT_B
		btn.TextSize = 14
		btn.TextColor3 = TEXT
		btn.BackgroundColor3 = CARD
		btn.Parent = parent
		btn.Activated:Connect(onClick)
	end
	if enabled == false then
		pcall(K.setButtonEnabled, btn, false)
		btn.Active = false
	end
	return btn
end

local function row(parent: Instance, left: string, right: string?, rightColor: Color3?, sub: string?): Frame
	local r = K.frame(parent, { Size = UDim2.new(1, 0, 0, if sub then 40 else 26), LayoutOrder = nextOrder() })
	K.text(r, { Size = UDim2.new(0.62, 0, 0, 22), Text = left, Font = FONT_M, TextSize = 14, TextColor3 = TEXT, TextTruncate = Enum.TextTruncate.AtEnd })
	if sub then
		K.text(r, { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 18), Text = sub, Font = FONT_M, TextSize = 12, TextColor3 = SUB, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	if right then
		K.text(r, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.38, 0, 0, 22), Text = right, Font = FONT_B, TextSize = 14, TextColor3 = rightColor or TEXT, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	return r
end

local function hstack(parent: Instance, height: number?): Frame
	local f = K.frame(parent, { Size = UDim2.new(1, 0, 0, height or 44), LayoutOrder = nextOrder() })
	K.list(f, true, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	return f
end

local function openSheet(kind: string, title: string, build: () -> ())
	if sheet and sheet.kind ~= kind and sheet.kind == "decor" then
		exitDecor()
	end
	sheet = { kind = kind }
	sheetTitle.Text = title
	clearBody()
	order = 0
	layoutSheet()
	local ok, err = pcall(build)
	if not ok then
		warn("[GwangalliHome] sheet " .. kind .. ": " .. tostring(err))
	end
	refreshSheet = function()
		if sheet and sheet.kind == kind then
			local keep = sheetBody.CanvasPosition
			clearBody()
			order = 0
			local ok2, err2 = pcall(build)
			if not ok2 then
				warn("[GwangalliHome] sheet " .. kind .. ": " .. tostring(err2))
			end
			sheetBody.CanvasPosition = keep
		end
	end
	local wasOpen = sheetGui.Enabled and sheetSerial > 0 and sheetFrame:GetAttribute("Open") == true
	sheetSerial += 1
	sheetGui.Enabled = true
	sheetFrame:SetAttribute("Open", true)
	sheetGui:SetAttribute("SheetOpenRight", sheetAway.X.Offset > 0)
	sheetGui:SetAttribute("SheetLeft", math.floor(sheetRest.X.Offset + sheetGui.AbsolutePosition.X))
	setControls(false)
	bar.Visible = false
	if not wasOpen then
		-- shell springs in from its edge over a dimming backdrop; the content fades in after it
		sheetBackdrop.BackgroundTransparency = 1
		tw(sheetBackdrop, 0.24, { BackgroundTransparency = 0.5 }, Enum.EasingStyle.Quad)
		sheetFrame.Position = sheetRest + sheetAway
		local past = sheetRest - UDim2.fromOffset(if sheetAway.X.Offset > 0 then 12 else 0, if sheetAway.Y.Offset > 0 then 10 else 0)
		spring(sheetFrame, 0.42, { Position = past }, { Position = sheetRest })
		if not motionReduced() then
			bodyVeil.BackgroundTransparency = 0
			task.delay(0.12, function()
				tw(bodyVeil, 0.24, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			end)
		end
	end
end

sheetBackdrop.InputBegan:Connect(function(input: InputObject)
	local t = input.UserInputType
	if sheet and (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) then
		closeSheet()
	end
end)

closeSheet = function()
	if sheet and sheet.kind == "decor" then
		exitDecor()
	end
	sheet = nil
	refreshSheet = function() end
	sheetFrame:SetAttribute("Open", false)
	sheetGui:SetAttribute("SheetOpenRight", false)
	sheetSerial += 1
	local mine = sheetSerial
	springSerial[sheetFrame] = (springSerial[sheetFrame] or 0) + 1
	tw(sheetFrame, 0.2, { Position = sheetRest + sheetAway }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	tw(sheetBackdrop, 0.18, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	task.delay(if motionReduced() then 0 else 0.21, function()
		if sheetSerial == mine then
			sheetGui.Enabled = false
			clearBody()
		end
	end)
	setControls(true)
	refreshBar()
end

-------------------------------------------------------------------------------------------------
-- Furniture preview / slot highlights / camera (decoration mode)
-------------------------------------------------------------------------------------------------
local decor: any = nil -- { slotIndex, variantIndex, preview, hidden = {parts}, boxes = {} }

-- FurnitureSlot containers (BasePart envelopes or the builder's slot Models) in the current home.
local function slotParts(): { Instance }
	local out = {}
	local m = state.model
	if not m then
		return out
	end
	for _, d in m:GetDescendants() do
		if (d:IsA("BasePart") or d:IsA("Model")) and d:HasTag(G.HomeTags.Slot) then
			table.insert(out, d)
		end
	end
	return out
end

local function slotPartById(id: string): Instance?
	for _, p in slotParts() do
		if p:GetAttribute("SlotId") == id then
			return p
		end
	end
	return nil
end

local function geometry(container: Instance): any?
	local ok, geo = pcall(G.slotGeometry, container)
	return if ok then geo else nil
end

local function currentSlots(): { any }
	return state.slots or {}
end

local function clearPreview()
	if not decor then
		return
	end
	if decor.preview then
		decor.preview:Destroy()
		decor.preview = nil
	end
	for _, p in decor.hidden do
		if p.Parent then
			p.LocalTransparencyModifier = 0
		end
	end
	decor.hidden = {}
end

-- Builds the variant locally at the slot (hiding what the server shows there).
local function buildPreview(slotPart: Instance, variantId: string?)
	clearPreview()
	if not decor or not variantId then
		return
	end
	local geo = geometry(slotPart)
	if not geo then
		return
	end
	local spec = G.furnitureSpec(variantId, geo.w, geo.h, geo.d)
	if not spec then
		return
	end
	for _, d in slotPart:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			table.insert(decor.hidden, d)
		end
	end
	local frame = geo.frame
	local m = Instance.new("Model")
	m.Name = "HomePreview"
	for _, p in spec.parts do
		local part = Instance.new("Part")
		part.Name = p.name
		if p.shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		elseif p.shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		end
		part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		local cf = frame * CFrame.new(p.pos[1], p.pos[2], p.pos[3])
		if p.rot then
			cf = cf * CFrame.Angles(math.rad(p.rot[1]), math.rad(p.rot[2]), math.rad(p.rot[3]))
		end
		part.CFrame = cf
		part.Color = rgb(p.color)
		local okM, mat = pcall(function()
			return (Enum.Material :: any)[p.material]
		end)
		part.Material = if okM and mat then mat else Enum.Material.SmoothPlastic
		part.Transparency = p.transparency or 0
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Parent = m
	end
	m.Parent = workspace
	decor.preview = m
end

local function clearBoxes()
	if not decor then
		return
	end
	for _, b in decor.boxes do
		b:Destroy()
	end
	decor.boxes = {}
end

local function drawBoxes(selectedId: string?)
	clearBoxes()
	if not decor then
		return
	end
	for _, p in slotParts() do
		local sel = p:GetAttribute("SlotId") == selectedId
		local box = Instance.new("SelectionBox")
		box.Name = "HomeSlotBox"
		box.Adornee = p
		box.LineThickness = if sel then 0.08 else 0.03
		box.Color3 = if sel then GOLD else CYAN
		box.SurfaceColor3 = if sel then GOLD else CYAN
		box.SurfaceTransparency = if sel then 0.88 else 0.96
		box.Transparency = if sel then 0 else 0.4
		box.Parent = hudGui
		table.insert(decor.boxes, box)
	end
end

local function focusSlot(p: Instance)
	local geo = geometry(p)
	if not geo then
		return
	end
	local frame = geo.frame
	local size = Vector3.new(geo.w, geo.h, geo.d)
	local center = (frame * CFrame.new(0, math.max(1, size.Y / 2), 0)).Position
	local look = frame.LookVector
	local dist = math.max(size.X, size.Y, size.Z) * 1.1 + 7
	local camPos = center + look * dist + Vector3.new(0, math.max(3, size.Y * 0.6 + 2), 0)
	-- keep the camera inside the unit when possible
	local m = state.model
	if m then
		local ok, cf, bs = pcall(m.GetBoundingBox, m)
		if ok then
			local rel = cf:PointToObjectSpace(camPos)
			local hx, hy, hz = bs.X / 2 - 2, bs.Y / 2 - 1, bs.Z / 2 - 2
			rel = Vector3.new(math.clamp(rel.X, -hx, hx), math.clamp(rel.Y, -hy, hy), math.clamp(rel.Z, -hz, hz))
			camPos = cf:PointToWorldSpace(rel)
		end
	end
	-- the sheet covers the right side of the screen: aim right of the slot so it shows on the left
	local s = guiSize(hudGui)
	local r = rectOf("sheetRight")
	local coverFrac = if r.x > s.X * 0.3 then (s.X - r.x) / s.X else 0
	local toCenter = (center - camPos)
	local right = toCenter.Unit:Cross(Vector3.yAxis)
	local aim = center + right * (toCenter.Magnitude * math.tan(math.rad(35)) * coverFrac)
	scriptCamera(CFrame.lookAt(camPos, aim), 60, 0.45)
end

-------------------------------------------------------------------------------------------------
-- 꾸미기 sheet
-------------------------------------------------------------------------------------------------
local decorTab = "place"

local function housingView(): any
	return state.housing or {}
end

local function variantsFor(category: string): { any }
	local list = { { id = false, def = nil } }
	for _, v in G.furnitureFor(category) do
		table.insert(list, v)
	end
	return list
end

local function slotInfo(index: number): any?
	local slots = currentSlots()
	return slots[index]
end

local function buildDecor()
	local hv = housingView()
	local tabs = hstack(sheetBody, 40)
	for _, t in { { "place", "🛋️ 배치" }, { "storage", "📦 창고" }, { "remodel", "🏗️ 리모델링" } } do
		button(tabs, t[2], if decorTab == t[1] then "primary" else "secondary", function()
			decorTab = t[1]
			if decorTab ~= "place" then
				clearPreview()
			end
			refreshSheet()
		end, UDim2.new(0.31, 0, 0, 40))
	end
	local summary = card()
	K.list(summary, false, 2)
	row(summary, "인테리어 점수", tostring(hv.decor or 0), GOLD)
	row(summary, "편안함 (잘 때 행복 +)", "+" .. tostring(hv.comfort or 0), GREEN)
	if (hv.value or 0) > 0 then
		row(summary, "집 가치", won(hv.value), TEXT)
	end
	row(summary, "가구 가치 (되팔 때)", won(hv.furnitureValue or 0), SUB)

	if decorTab == "storage" then
		local any = false
		local ids = {}
		for vid in hv.storage or {} do
			table.insert(ids, vid)
		end
		table.sort(ids)
		for _, vid in ids do
			local f = G.FURNITURE[vid]
			local n = hv.storage[vid]
			if f and n and n > 0 then
				any = true
				local c = card()
				K.list(c, false, 6)
				local cat = G.FURNITURE_CATEGORIES[f.category]
				row(c, string.format("%s %s ×%d", cat and cat.icon or "📦", f.name, n), G.FURNITURE_STYLES[f.style].name, rgb(G.FURNITURE_STYLES[f.style].color))
				button(c, "팔기 +" .. won(G.furnitureResale(vid)), "danger", function()
					act("sellStored", { variantId = vid })
				end, UDim2.new(1, 0, 0, 40))
			end
		end
		if not any then
			label("창고가 비어 있어요. 가구를 바꾸면 원래 가구가 여기에 보관돼요. 창고 가구는 배치 탭에서 무료로 다시 놓을 수 있어요.", { color = SUB, size = 13 })
		else
			label(string.format("창고 %d/%d · 되팔면 구매가의 50%%", hv.storageCount or 0, G.HOME_STORAGE_MAX), { color = SUB, size = 12 })
		end
		return
	end

	if decorTab == "remodel" then
		if not state.owned then
			label("리모델링은 매매한 내 집(광안자이·아쿠아펠리스)에서 할 수 있어요. 공사할수록 집값과 편안함이 올라요.", { color = SUB, size = 13 })
		end
		local done: { [string]: boolean } = {}
		for _, id in hv.upgrades or {} do
			done[id] = true
		end
		for _, id in G.HOME_UPGRADE_ORDER do
			local u = G.HOME_UPGRADES[id]
			local c = card()
			K.list(c, false, 6)
			row(c, u.icon .. " " .. u.name, if done[id] then "완료 ✓" else won(u.price), if done[id] then GREEN else GOLD, string.format("%s · 집값 +%s · 편안함 +%d%s", u.desc, won(u.value), u.comfort, if u.minTier then " · 펜트하우스 전용" else ""))
			if not done[id] then
				button(c, "공사하기 · " .. won(u.price), "primary", function()
					act("upgrade", { upgradeId = id })
				end, UDim2.new(1, 0, 0, 40), state.owned and (not u.minTier or (G.HOME_TIERS[state.tierKey] and G.HOME_TIERS[state.tierKey].tier >= u.minTier)))
			end
		end
		local loan = hv.loan
		if type(loan) == "table" then
			local c = card()
			K.list(c, false, 6)
			row(c, "🏦 주택담보대출 남은 금액", won(loan.remaining), RED)
			row(c, "하루 상환금 (관리비와 함께)", won(loan.daily), SUB)
			button(c, "대출 완납하기 · " .. won(loan.remaining), "gold", function()
				act("repayLoan")
			end, UDim2.new(1, 0, 0, 40))
		end
		return
	end

	-- 배치
	local slots = currentSlots()
	if #slots == 0 then
		label("이 집에는 가구 자리가 없어요.", { color = SUB })
		return
	end
	decor.slotIndex = math.clamp(decor.slotIndex, 1, #slots)
	local s = slotInfo(decor.slotIndex)
	local cat = G.FURNITURE_CATEGORIES[s.category]
	local variants = variantsFor(s.category)
	if decor.variantIndex == nil then
		decor.variantIndex = 1
		for i, v in variants do
			if v.id and v.id == s.variantId then
				decor.variantIndex = i
			end
		end
	end
	decor.variantIndex = ((decor.variantIndex - 1) % #variants) + 1
	local v = variants[decor.variantIndex]
	local nav = hstack(sheetBody, 44)
	button(nav, "◀", "secondary", function()
		decor.slotIndex = (decor.slotIndex - 2) % #slots + 1
		decor.variantIndex = nil
		refreshSheet()
	end, UDim2.fromOffset(44, 44))
	local mid = K.frame(nav, { Size = UDim2.new(1, -104, 1, 0), LayoutOrder = nextOrder() })
	K.text(mid, { Size = UDim2.new(1, 0, 0.6, 0), Text = string.format("%s %s", cat and cat.icon or "🪑", cat and cat.name or s.category), Font = FONT_B, TextSize = 16, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Center })
	K.text(mid, { Position = UDim2.fromScale(0, 0.6), Size = UDim2.new(1, 0, 0.4, 0), Text = string.format("자리 %d / %d · 화면의 네모를 눌러도 돼요", decor.slotIndex, #slots), Font = FONT_M, TextSize = 11, TextColor3 = SUB, TextXAlignment = Enum.TextXAlignment.Center })
	button(nav, "▶", "secondary", function()
		decor.slotIndex = decor.slotIndex % #slots + 1
		decor.variantIndex = nil
		refreshSheet()
	end, UDim2.fromOffset(44, 44))

	local c = card()
	K.list(c, false, 6)
	local placed = (v.id == false and not s.variantId) or (v.id and v.id == s.variantId)
	local owned = v.id and (hv.storage or {})[v.id] or 0
	if v.id then
		local f = v.def
		local st = G.FURNITURE_STYLES[f.style]
		K.text(c, { Size = UDim2.new(1, 0, 0, 24), Text = f.name, Font = FONT_B, TextSize = 17, TextColor3 = TEXT, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = nextOrder() })
		local chipRow = K.frame(c, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = nextOrder() })
		K.list(chipRow, true, 6)
		local function pill(text: string, color: Color3)
			local p = K.frame(chipRow, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0.75, BackgroundColor3 = color, LayoutOrder = nextOrder() })
			K.corner(p, 12)
			K.pad(p, 10, 10, 0, 0)
			K.text(p, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Text = text, Font = FONT_B, TextSize = 12, TextColor3 = TEXT })
		end
		pill(st.name, rgb(st.color))
		pill("인테리어 +" .. f.decor, GOLD)
		if owned > 0 then
			pill("창고 " .. owned .. "개", GREEN)
		end
		row(c, "가격", won(f.price), GOLD)
	else
		K.text(c, { Size = UDim2.new(1, 0, 0, 24), Text = "기본 가구 (집에 딸린 옵션)", Font = FONT_B, TextSize = 17, TextColor3 = TEXT, LayoutOrder = nextOrder() })
		label("처음부터 있던 가구예요. 지금 가구는 창고로 옮겨져요.", { color = SUB, size = 12 })
	end
	local vnav = hstack(c, 40)
	button(vnav, "◀ 이전", "secondary", function()
		decor.variantIndex = (decor.variantIndex - 2) % #variants + 1
		refreshSheet()
	end, UDim2.new(0.3, 0, 0, 40))
	K.text(vnav, { Size = UDim2.new(0.3, 0, 0, 40), Text = string.format("%d / %d", decor.variantIndex, #variants), Font = FONT_B, TextSize = 14, TextColor3 = SUB, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = nextOrder() })
	button(vnav, "다음 ▶", "secondary", function()
		decor.variantIndex = decor.variantIndex % #variants + 1
		refreshSheet()
	end, UDim2.new(0.3, 0, 0, 40))
	if placed then
		button(c, "지금 놓여 있어요 ✓", "secondary", function() end, UDim2.new(1, 0, 0, 44), false)
	elseif v.id == false then
		button(c, "기본 가구로 되돌리기", "primary", function()
			act("resetSlot", { slotId = s.slotId })
		end)
	elseif owned > 0 then
		button(c, "창고에서 꺼내 배치하기", "success", function()
			act("placeFurniture", { slotId = s.slotId, variantId = v.id })
		end)
	else
		button(c, "구매하고 배치 · " .. won(v.def.price), "primary", function()
			act("placeFurniture", { slotId = s.slotId, variantId = v.id })
		end)
	end
	if s.variantId then
		button(c, "지금 가구 팔기 +" .. won(G.furnitureResale(s.variantId)), "danger", function()
			act("sellSlot", { slotId = s.slotId })
		end, UDim2.new(1, 0, 0, 40))
	end
	-- preview + camera
	local sp = slotPartById(s.slotId)
	if sp then
		if v.id and not placed then
			buildPreview(sp, v.id)
		elseif v.id == false and s.variantId then
			-- preview of the default: show the server model hidden state is not needed; just clear
			clearPreview()
		else
			clearPreview()
		end
		drawBoxes(s.slotId)
		if decor.focused ~= s.slotId then
			decor.focused = s.slotId
			focusSlot(sp)
		end
	end
end

exitDecor = function()
	if not decor then
		return
	end
	clearPreview()
	clearBoxes()
	if decor.tapConn then
		decor.tapConn:Disconnect()
	end
	decor = nil
	restoreCamera()
end

openDecor = function()
	if not state.inside or state.role ~= "owner" then
		return
	end
	if decor then
		exitDecor()
	end
	decor = { slotIndex = 1, variantIndex = nil, preview = nil, hidden = {}, boxes = {}, focused = nil, tapConn = nil }
	decorTab = "place"
	-- tap a slot box in the world to select it
	decor.tapConn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not decor or decorTab ~= "place" then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local best, bestD = nil, 70
		for i, s in currentSlots() do
			local p = slotPartById(s.slotId)
			local geo = p and geometry(p)
			if geo then
				local sp, onScreen = cam:WorldToViewportPoint((geo.frame * CFrame.new(0, geo.h / 2, 0)).Position)
				if onScreen then
					local dd = (Vector2.new(sp.X, sp.Y) - pos).Magnitude
					if dd < bestD then
						best, bestD = i, dd
					end
				end
			end
		end
		if best and best ~= decor.slotIndex then
			decor.slotIndex = best
			decor.variantIndex = nil
			refreshSheet()
		end
	end)
	openSheet("decor", "🛠️ 꾸미기 · " .. state.homeName, buildDecor)
end

-------------------------------------------------------------------------------------------------
-- 초대하기 sheet
-------------------------------------------------------------------------------------------------
local function buildGuests()
	local inside: { [number]: boolean } = {}
	for _, g in state.guests do
		inside[g.userId] = true
	end
	label(string.format("우리 집 손님 %d / %d명 · %s", #state.guests, state.maxGuests, state.tierName), { bold = true })
	if #state.guests > 0 then
		for _, g in state.guests do
			local c = card()
			K.list(c, false, 6)
			row(c, "🙋 " .. g.name, "방문 중", GREEN)
			button(c, "내보내기", "danger", function()
				act("kick", { userId = g.userId })
			end, UDim2.new(1, 0, 0, 40))
		end
	end
	label("친구 초대하기", { bold = true, color = SUB, size = 13 })
	local others = 0
	for _, p in Players:GetPlayers() do
		if p ~= player and not inside[p.UserId] then
			others += 1
			local c = card()
			K.list(c, false, 6)
			local tier = p:GetAttribute("HomeTier")
			local tk = type(tier) == "number" and tier > 0 and G.homeTierKey(tier)
			row(c, "👤 " .. p.DisplayName, if tk then (G.HOME_TIERS[tk].icon .. " " .. G.HOME_TIERS[tk].name) else "집 없음", SUB)
			button(c, "초대 보내기 💌", "primary", function()
				act("invite", { userId = p.UserId })
			end, UDim2.new(1, 0, 0, 40), #state.guests < state.maxGuests)
		end
	end
	if others == 0 then
		label("지금 서버에 초대할 친구가 없어요. 친구가 들어오면 여기서 초대할 수 있어요.", { color = SUB, size = 13 })
	end
	label("첫 손님이 오면 집들이 성공! 행복·인기도가 올라요 🎉", { color = SUB, size = 12 })
end

openGuests = function()
	if not state.inside or state.role ~= "owner" then
		return
	end
	openSheet("guests", "💌 초대하기", buildGuests)
end

-------------------------------------------------------------------------------------------------
-- Panels from the server (fridge / desk / mailbox / wardrobe / guests / window)
-------------------------------------------------------------------------------------------------
local panelData: any = {}

local function buildFridge()
	local d = panelData.fridge or {}
	local c = card()
	K.list(c, false, 6)
	row(c, "🧊 집밥 재료", string.format("%d / %d끼", d.fridge or 0, d.max or 20), if (d.fridge or 0) > 0 then GREEN else RED)
	if d.meal then
		label(d.meal.name .. " · " .. (d.meal.desc or ""), { color = SUB, size = 12 })
	end
	button(c, "🍚 집밥 먹기", "success", function()
		act("eat", { source = "home" })
	end, UDim2.new(1, 0, 0, 44), (d.fridge or 0) > 0)
	if d.groceries then
		button(c, string.format("🛒 장보기 · %s (+%d끼)", won(d.groceries.price), d.groceries.meals), "secondary", function()
			act("groceries")
		end, UDim2.new(1, 0, 0, 40))
	end
	label("🛵 배달 주문", { bold = true })
	if type(d.delivery) == "table" then
		label(string.format("배달 중… 약 %d초 후 도착", d.delivery.eta or 0), { color = GOLD, size = 13 })
	end
	for _, m in d.menu or {} do
		local mc = card()
		K.list(mc, false, 6)
		row(mc, m.icon .. " " .. m.name, won(m.price), GOLD, m.desc)
		button(mc, "주문하기", "primary", function()
			act("delivery", { menuId = m.id })
		end, UDim2.new(1, 0, 0, 40), type(d.delivery) ~= "table")
	end
end

local KIND_ICON = { rent = "🏠", upkeep = "🏢", loan = "🏦", utility = "💡", missed = "⚠️", evicted = "📦", foreclosed = "🔨", loanPaid = "🎉", info = "🧾" }
local function buildMailbox()
	local d = panelData.mailbox or {}
	local c = card()
	K.list(c, false, 2)
	row(c, d.homeName ~= "" and d.homeName or "내 집", if d.owned then "자가" else "월세", SUB)
	row(c, if d.owned then "관리비 (하루)" else "월세 (하루)", won(d.daily or 0))
	if (d.utility or 0) > 0 then
		row(c, "공과금 (하루)", won(d.utility))
	end
	if type(d.loan) == "table" then
		row(c, "대출 상환 (하루)", won(d.loan.daily), GOLD)
		row(c, "남은 대출", won(d.loan.remaining), RED)
	end
	row(c, "다음 자동이체까지", G.format.seconds(d.dueIn or 0), SUB)
	if (d.arrears or 0) > 0 then
		row(c, string.format("연체 %d일", d.missed or 0), won(d.arrears), RED)
	end
	label("📬 고지서", { bold = true })
	local bills = d.bills or {}
	if #bills == 0 then
		label("아직 고지서가 없어요.", { color = SUB, size = 13 })
	end
	for _, b in bills do
		local bc = card()
		K.list(bc, false, 2)
		row(bc, (KIND_ICON[b.kind] or "🧾") .. " " .. b.label, if (b.amount or 0) ~= 0 then won(b.amount) else "", if b.paid then TEXT else RED, string.format("%d일째 · %s", b.day or 1, if b.paid then "납부 완료" else "미납"))
	end
end

local function buildDesk()
	local d = panelData.desk or {}
	local c = card()
	K.list(c, false, 2)
	row(c, "🏦 통장", won(d.bank or 0), TEXT)
	row(c, "💵 현금", won(d.cash or 0), TEXT)
	row(c, "📈 총자산", won(d.netWorth or 0), GOLD)
	if (d.homeValue or 0) > 0 then
		row(c, "🏠 집 가치", won(d.homeValue), SUB)
	end
	if (d.furnitureValue or 0) > 0 then
		row(c, "🛋️ 가구 가치", won(d.furnitureValue), SUB)
	end
	if type(d.loan) == "table" then
		row(c, "🏦 남은 대출", won(d.loan.remaining), RED)
	end
	if d.job then
		row(c, "💼 직업", tostring(d.job), SUB)
	end
	button(sheetBody, "📱 폰으로 통장 열기", "primary", function()
		openPhoneApp("bank")
	end)
	label("최근 거래", { bold = true, color = SUB, size = 13 })
	for _, tx in d.lastTx or {} do
		local tc = card()
		row(tc, tx.label, (if tx.amount > 0 then "+" else "") .. won(tx.amount), if tx.amount > 0 then GREEN else TEXT, if tx.account == "cash" then "현금" else "통장")
	end
	label(string.format("받은 제안 %d개 · 안 읽은 메시지 %d개", #(d.offers or {}), d.unread or 0), { bold = true, color = SUB, size = 13 })
	for _, o in d.offers or {} do
		local oc = card()
		row(oc, "💌 " .. o.title, "", nil)
	end
	button(sheetBody, "💬 메시지 열기", "secondary", function()
		openPhoneApp("messages")
	end, UDim2.new(1, 0, 0, 40))
end

local function buildWardrobe()
	local d = panelData.wardrobe or {}
	for _, o in d.outfits or {} do
		local c = card()
		K.list(c, false, 6)
		row(c, "👕 " .. o.name, if o.worn then "입는 중 ✓" else "", GREEN)
		if not o.worn then
			button(c, "갈아입기", "primary", function()
				phoneAct("equip", { itemId = o.id })
				playPose("shower", 0.8)
				toast("stat", "옷 갈아입기 👕", o.name)
				task.delay(0.6, function()
					act("openPanel", { panel = "wardrobe" })
				end)
			end, UDim2.new(1, 0, 0, 40))
		end
	end
	if d.shopHint then
		label("옷은 헤어살롱 & 편집숍에서 살 수 있어요.", { color = SUB, size = 13 })
	end
end

local function buildGuestPanel()
	local d = panelData.guests or {}
	state.guests = d.guests or state.guests
	buildGuests()
end

-------------------------------------------------------------------------------------------------
-- Window photo moment
-------------------------------------------------------------------------------------------------
local photo: any = nil
local function closePhoto()
	if not photo then
		return
	end
	photo.frame:Destroy()
	photo = nil
	restoreCamera()
	if sheet == nil then
		sheetGui.Enabled = false
		setControls(true)
	end
	refreshBar()
end

local function openPhoto(data: any)
	if photo or not state.inside then
		return
	end
	if sheet then
		closeSheet()
	end
	local cf: CFrame = if typeof(data.cf) == "CFrame" then data.cf else nil
	if not cf then
		return
	end
	local center = state.model and state.model:GetPivot().Position or cf.Position
	local dir = Vector3.new(cf.Position.X - center.X, 0, cf.Position.Z - center.Z)
	if dir.Magnitude < 0.5 then
		dir = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	end
	dir = dir.Unit
	local camPos = cf.Position - dir * 3 + Vector3.new(0, 1.2, 0)
	scriptCamera(CFrame.lookAt(camPos, camPos + dir * 60 + Vector3.new(0, -4, 0)), 55, 0.8)
	bar.Visible = false
	sheetGui.Enabled = true
	setControls(false)
	local frame = K.frame(sheetGui, { Name = "Photo", Size = UDim2.fromScale(1, 1) })
	local caption = if data.view == "sea" then (if data.night then "광안대교 야경 🌉" else "광안리 오션뷰 🌊") else "골목길 창밖 풍경 🏙️"
	K.text(frame, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.new(0.8, 0, 0, 36), Text = caption, Font = FONT_B, TextSize = 22, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5 })
	local row2 = K.frame(frame, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(300, 52) })
	K.list(row2, true, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local flash = K.frame(frame, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 5 })
	local function mk(text: string, style: string, fn: () -> ())
		local ok, b = pcall(K.Button, row2, { text = text, style = style, size = UDim2.fromOffset(140, 48), textSize = 15, onClick = fn })
		if not ok then
			local fb = Instance.new("TextButton")
			fb.Text = text
			fb.Size = UDim2.fromOffset(140, 48)
			fb.Parent = row2
			fb.Activated:Connect(fn)
		end
		local _ = b
	end
	mk("📸 찰칵", "primary", function()
		flash.BackgroundTransparency = 0.1
		pcall(function()
			TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		end)
		pcall(K.sound, "shutter")
		act("windowPhoto")
	end)
	mk("닫기", "secondary", closePhoto)
	photo = { frame = frame }
end

-------------------------------------------------------------------------------------------------
-- TV screens (local content while TvOn)
-------------------------------------------------------------------------------------------------
local CHANNELS = {
	{ "KNN 뉴스", "광안리 불꽃축제 D-7, 해변 준비 한창", Color3.fromRGB(30, 60, 140) },
	{ "드라마", "〈광안리 연가〉 12화 — 다시 만난 두 사람", Color3.fromRGB(140, 60, 100) },
	{ "야구 중계", "롯데 자이언츠 vs 두산 · 7회말 3:2", Color3.fromRGB(20, 110, 60) },
	{ "예능", "〈부산 맛집 로드〉 민락회타운 편", Color3.fromRGB(200, 120, 30) },
	{ "음악 방송", "이번 주 1위 후보 무대", Color3.fromRGB(120, 40, 170) },
}
local tvGuis: { SurfaceGui } = {}
local tvLoop = 0
local function clearTv()
	for _, g in tvGuis do
		g:Destroy()
	end
	tvGuis = {}
	tvLoop += 1
end

local function refreshTv()
	clearTv()
	local m = state.model
	if not m or not state.tvOn then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Screen" or d.Name == "TVScreen") then
			local sg = Instance.new("SurfaceGui")
			sg.Name = "HomeTV"
			sg.Face = Enum.NormalId.Front
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 40
			sg.LightInfluence = 0
			sg.Adornee = d
			local bg = Instance.new("Frame")
			bg.Name = "BG"
			bg.Size = UDim2.fromScale(1, 1)
			bg.BorderSizePixel = 0
			bg.BackgroundColor3 = CHANNELS[1][3]
			bg.Parent = sg
			local t1 = Instance.new("TextLabel")
			t1.Name = "Channel"
			t1.BackgroundTransparency = 1
			t1.Position = UDim2.fromScale(0.05, 0.06)
			t1.Size = UDim2.fromScale(0.9, 0.22)
			t1.Font = Enum.Font.GothamBold
			t1.TextScaled = true
			t1.TextColor3 = Color3.new(1, 1, 1)
			t1.TextXAlignment = Enum.TextXAlignment.Left
			t1.Parent = bg
			local t2 = Instance.new("TextLabel")
			t2.Name = "Show"
			t2.BackgroundTransparency = 1
			t2.Position = UDim2.fromScale(0.05, 0.62)
			t2.Size = UDim2.fromScale(0.9, 0.3)
			t2.Font = Enum.Font.GothamMedium
			t2.TextScaled = true
			t2.TextWrapped = true
			t2.TextColor3 = Color3.fromRGB(240, 240, 240)
			t2.TextXAlignment = Enum.TextXAlignment.Left
			t2.Parent = bg
			sg.Parent = hudGui
			table.insert(tvGuis, sg)
		end
	end
	local token = tvLoop
	task.spawn(function()
		local i = 0
		while token == tvLoop and #tvGuis > 0 do
			i = i % #CHANNELS + 1
			local ch = CHANNELS[i]
			for _, sg in tvGuis do
				local bg = sg:FindFirstChild("BG")
				if bg and bg:IsA("Frame") then
					bg.BackgroundColor3 = ch[3]
					local c1 = bg:FindFirstChild("Channel")
					local c2 = bg:FindFirstChild("Show")
					if c1 and c1:IsA("TextLabel") then
						c1.Text = "📺 " .. ch[1]
					end
					if c2 and c2:IsA("TextLabel") then
						c2.Text = ch[2]
					end
				end
			end
			task.wait(9)
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Popups: doorbell / invite / entrance listing card / resident picker
-------------------------------------------------------------------------------------------------
local function modal(opts: any): any
	local ok, api = pcall(K.Modal, popGui, opts)
	if ok and api then
		return api
	end
	-- minimal fallback
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(300, 180)
	f.BackgroundColor3 = CARD
	f.Parent = popGui
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 0, 90)
	t.TextWrapped = true
	t.Text = (opts.title or "") .. "\n" .. (opts.body or "")
	t.TextColor3 = TEXT
	t.BackgroundTransparency = 1
	t.Parent = f
	local fallbackApi = {}
	function fallbackApi.close()
		f:Destroy()
	end
	for i, b in opts.buttons or {} do
		local bb = Instance.new("TextButton")
		bb.Position = UDim2.new((i - 1) / #opts.buttons, 4, 1, -48)
		bb.Size = UDim2.new(1 / #opts.buttons, -8, 0, 44)
		bb.Text = b.text
		bb.Parent = f
		bb.Activated:Connect(function()
			fallbackApi.close()
			if b.onClick then
				b.onClick()
			end
		end)
	end
	return fallbackApi
end

-- One popup at a time; it closes on its buttons, after `ttl` seconds, or when the player walks
-- away from `anchor` (a building entrance).
local activePopup: any = nil
local popupWatch: RBXScriptConnection? = nil
local function closePopup()
	if popupWatch then
		popupWatch:Disconnect()
		popupWatch = nil
	end
	local a = activePopup
	activePopup = nil
	if a then
		pcall(a.close)
	end
end

local function popup(opts: any, ttl: number?, anchor: BasePart?): any
	closePopup()
	local api = modal(opts)
	activePopup = api
	local t0 = os.clock()
	popupWatch = RunService.Heartbeat:Connect(function()
		if activePopup ~= api then
			return
		end
		if api.closed then
			closePopup()
			return
		end
		if ttl and os.clock() - t0 > ttl then
			closePopup()
			return
		end
		if anchor then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not anchor.Parent or (root and root:IsA("BasePart") and (root.Position - anchor.Position).Magnitude > G.HOME_ENTRANCE_REACH + 12) then
				closePopup()
			end
		end
	end)
	return api
end

local function showDoorbell(data: any)
	pcall(K.sound, "notify")
	if data.delivery then
		toast("home", "딩동 🔔 배달 왔어요!", "식탁 위 음식에서 '먹기'")
		return
	end
	popup({
		icon = "🔔",
		title = "딩동! 초인종이 울렸어요",
		body = string.format("%s님이 문 앞에 있어요. 들어오게 할까요?", data.visitorName or "누군가"),
		buttons = {
			{ text = "거절", style = "secondary", onClick = function()
				act("answerDoor", { visitorId = data.visitorId, accept = false })
			end },
			{ text = "문 열어주기", style = "primary", onClick = function()
				act("answerDoor", { visitorId = data.visitorId, accept = true })
			end },
		},
	}, G.HOME_RING_TTL)
end

local function showInvite(data: any)
	pcall(K.sound, "notify")
	popup({
		icon = "💌",
		title = "집들이 초대 🏠",
		body = string.format("%s님이 %s(%s)에 초대했어요. 놀러 갈까요?", data.ownerName or "친구", data.homeName or "집", data.tierName or ""),
		buttons = {
			{ text = "다음에", style = "secondary", onClick = function()
				act("declineInvite", { ownerId = data.ownerId })
			end },
			{ text = "놀러 가기", style = "primary", onClick = function()
				act("acceptInvite", { ownerId = data.ownerId })
			end },
		},
	}, data.expiresIn or G.HOME_INVITE_TTL)
end

-------------------------------------------------------------------------------------------------
-- Building entrances (client prompts)
-------------------------------------------------------------------------------------------------
type Entrance = { part: BasePart, tierKey: string, enter: ProximityPrompt, bell: ProximityPrompt, info: ProximityPrompt }
local entrancesByPart: { [BasePart]: Entrance } = {}

local function myTier(): number
	local t = player:GetAttribute("HomeTier")
	return if type(t) == "number" then t else 0
end

local function residents(tierKey: string): { Player }
	local n = G.homeTierNumber(tierKey)
	local out = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("HomeTier") == n then
			table.insert(out, p)
		end
	end
	table.sort(out, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	return out
end

local function buildingName(e: Entrance): string
	for _, key in { "DisplayName", "Destination" } do
		local n = e.part:GetAttribute(key)
		if type(n) == "string" and n ~= "" then
			return n
		end
	end
	local _, l = G.listingForTier(e.tierKey)
	return l and l.place or G.HOME_TIERS[e.tierKey].name
end

local function refreshEntrance(e: Entrance)
	local mine = myTier() == G.homeTierNumber(e.tierKey)
	local _, l = G.listingForTier(e.tierKey)
	e.enter.Enabled = mine
	e.enter.ObjectText = l and l.name or buildingName(e)
	local res = residents(e.tierKey)
	e.bell.Enabled = #res > 0
	e.bell.ObjectText = string.format("%s · 입주민 %d명", buildingName(e), #res)
	e.info.Enabled = not mine and l ~= nil
	if l then
		e.info.ObjectText = string.format("%s · %s", l.name, if l.kind == "rent" then ("월세 " .. won(l.rentPerDay) .. "/일") else ("매매 " .. won(l.price)))
	end
end

local function refreshEntrances()
	for _, e in entrancesByPart do
		refreshEntrance(e)
	end
end

-- The listing card (입주 문의 at a building entrance, 계약 문의 while touring a staged unit):
-- 🔑 둘러보기 (an empty staged unit), 월세 계약 / 매매 / 대출로 매매 through the existing remotes.
local function listingCardFor(id: string, anchor: BasePart?)
	local l = G.LISTINGS[id]
	if not l then
		return
	end
	local touring = state.inside and state.role == "viewer"
	local buttons = {}
	local body
	local tourBtn = { text = "🔑 둘러보기", style = "secondary", onClick = function()
		act("tour", { listingId = id })
	end }
	if l.kind == "rent" then
		body = string.format("%s\n보증금 %s · 월세 하루 %s\n편안함 +%d · 손님 최대 %d명", l.desc, won(l.deposit or 0), won(l.rentPerDay), l.comfort or 0, G.homeGuestLimit(l.tierKey))
		table.insert(buttons, if touring then { text = "닫기", style = "secondary" } else tourBtn)
		table.insert(buttons, { text = "월세 계약하기", style = "primary", onClick = function()
			phoneAct("rentHome", { listingId = id })
		end })
	else
		local q = G.mortgageQuote(id)
		body = string.format("%s\n매매가 %s · 관리비 하루 %s%s", l.desc, won(l.price), won(l.upkeepPerDay or 0), if q then string.format("\n🏦 대출: 계약금 %s + 하루 %s × %d일", won(q.down), won(q.daily), q.days) else "")
		table.insert(buttons, if touring then { text = "닫기", style = "secondary" } else tourBtn)
		table.insert(buttons, { text = "매매", style = "secondary", onClick = function()
			phoneAct("buyHome", { listingId = id })
		end })
		if q then
			table.insert(buttons, { text = "대출로 매매", style = "primary", onClick = function()
				act("buyWithLoan", { listingId = id })
			end })
		end
	end
	popup({ icon = l.icon, title = l.name, body = body, buttons = buttons, width = 360 }, 30, anchor)
end

local function listingCard(e: Entrance)
	local id = G.listingForTier(e.tierKey)
	if id then
		listingCardFor(id, e.part)
	end
end

local function ringFlow(e: Entrance)
	local res = residents(e.tierKey)
	if #res == 0 then
		toast("home", "초인종", "지금 이 건물에 있는 입주민이 없어요")
		return
	end
	if #res == 1 then
		act("ring", { ownerId = res[1].UserId })
		return
	end
	local buttons = {}
	for i, p in res do
		if i > 4 then
			break
		end
		table.insert(buttons, { text = p.DisplayName, style = if i == 1 then "primary" else "secondary", onClick = function()
			act("ring", { ownerId = p.UserId })
		end })
	end
	popup({ icon = "🔔", title = "누구네 초인종을 누를까요?", body = buildingName(e), buttons = buttons, width = 360 }, 20, e.part)
end

local function makeEntrancePrompt(part: BasePart, name: string, action: string, key: Enum.KeyCode, gp: Enum.KeyCode): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = action
	pp.KeyboardKeyCode = key
	pp.GamepadKeyCode = gp
	pp.HoldDuration = 0
	pp.MaxActivationDistance = G.HOME_ENTRANCE_REACH - 4
	pp.RequiresLineOfSight = false
	pp.Enabled = false
	pp.Parent = part
	return pp
end

local function entranceAdded(inst: Instance)
	if not inst:IsA("BasePart") or entrancesByPart[inst] then
		return
	end
	local key = G.homeTierKey(inst:GetAttribute("Tier"))
	if not key then
		return
	end
	local e: Entrance = {
		part = inst,
		tierKey = key,
		enter = makeEntrancePrompt(inst, "HomeEnterPrompt", "집으로 들어가기", Enum.KeyCode.E, Enum.KeyCode.ButtonX),
		bell = makeEntrancePrompt(inst, "HomeBellPrompt", "초인종", Enum.KeyCode.F, Enum.KeyCode.ButtonY),
		info = makeEntrancePrompt(inst, "HomeInfoPrompt", "입주 문의", Enum.KeyCode.R, Enum.KeyCode.ButtonB),
	}
	entrancesByPart[inst] = e
	e.enter.Triggered:Connect(function()
		act("enter", { via = "entrance" })
	end)
	e.bell.Triggered:Connect(function()
		ringFlow(e)
	end)
	e.info.Triggered:Connect(function()
		listingCard(e)
	end)
	refreshEntrance(e)
end

local function entranceRemoved(inst: Instance)
	local e = entrancesByPart[inst :: any]
	if e then
		entrancesByPart[inst :: any] = nil
		for _, pp in { e.enter, e.bell, e.info } do
			pp:Destroy()
		end
	end
end

CollectionService:GetInstanceAddedSignal(G.HomeTags.Entrance):Connect(entranceAdded)
CollectionService:GetInstanceRemovedSignal(G.HomeTags.Entrance):Connect(entranceRemoved)
for _, inst in CollectionService:GetTagged(G.HomeTags.Entrance) do
	task.spawn(entranceAdded, inst)
end
local watched: { [Player]: RBXScriptConnection } = {}
local function watchPlayer(p: Player)
	if watched[p] then
		return
	end
	watched[p] = p:GetAttributeChangedSignal("HomeTier"):Connect(refreshEntrances)
	refreshEntrances()
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(p)
	if watched[p] then
		watched[p]:Disconnect()
		watched[p] = nil
	end
	task.defer(refreshEntrances)
end)
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end

-------------------------------------------------------------------------------------------------
-- 인테리어 mode (GwangalliHome/Interior) + the client API (GwangalliHome/Api, bindables)
-------------------------------------------------------------------------------------------------
local Interior: any = nil
do
	local folder: Instance? = nil
	local here = script.Parent
	if here then
		for _, c in here:GetChildren() do
			if c:IsA("Folder") and c.Name == "GwangalliHome" then
				folder = c
				break
			end
		end
	end
	local mod = folder and folder:FindFirstChild("Interior")
	if mod and mod:IsA("ModuleScript") then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			Interior = res
		else
			warn("[GwangalliHome] Interior failed to load: " .. tostring(res))
		end
	end
end
if Interior and G.HOMES then
	local okI, errI = pcall(Interior.init, {
		K = K,
		G = G,
		player = player,
		playerGui = playerGui,
		state = state,
		act = act,
		toast = toast,
		setControls = setControls,
		motionReduced = motionReduced,
		hideBar = function(hidden: boolean)
			barHiddenByInterior = hidden
			refreshBar()
		end,
		openLegacy = function(tabName: string?)
			openDecor()
			if tabName and decor then
				decorTab = tabName
				refreshSheet()
			end
		end,
		listingCard = function(listingId: string)
			listingCardFor(listingId, nil)
		end,
	})
	if not okI then
		warn("[GwangalliHome] Interior.init failed: " .. tostring(errI))
		Interior = nil
	end
else
	Interior = nil
end

-- 🛠️ 인테리어 (owner) / 👀 구경 (guest) / 📝 계약 (둘러보기 viewer)
openInterior = function()
	if state.inside and state.role == "viewer" then
		listingCardFor(state.listingId or "", nil)
		return
	end
	if Interior then
		if sheet then
			closeSheet()
		end
		act("openInterior")
	elseif state.role == "owner" then
		openDecor()
	end
end

do
	local old = player:FindFirstChild("GwangalliHomeOpen")
	if old then
		old:Destroy()
	end
	local oldQ = player:FindFirstChild("GwangalliHomeQuery")
	if oldQ then
		oldQ:Destroy()
	end
	local ev = Instance.new("BindableEvent")
	ev.Name = "GwangalliHomeOpen"
	ev.Parent = player
	ev.Event:Connect(function(what: any, arg: any)
		if what == "interior" then
			if Interior then
				act("openInterior")
			else
				toast("home", "인테리어", "집 안에서 🛠️ 인테리어를 눌러요")
			end
		elseif what == "tour" and type(arg) == "string" and G.LISTINGS[arg] then
			act("tour", { listingId = arg })
		elseif what == "close" then
			if Interior then
				Interior.close()
			end
		end
	end)
	local q = Instance.new("BindableFunction")
	q.Name = "GwangalliHomeQuery"
	q.Parent = player
	q.OnInvoke = function(what: any): any
		if what == "state" then
			return {
				inside = state.inside,
				role = state.role,
				homeName = state.homeName,
				listingId = state.listingId,
				tierKey = state.tierKey,
				interior = if Interior then Interior.mode() else nil,
			}
		end
		return nil
	end
end

-------------------------------------------------------------------------------------------------
-- HomeState
-------------------------------------------------------------------------------------------------
local function findModel(name: string): Model?
	local folder = workspace:FindFirstChild(G.HOME_INSTANCE_FOLDER) or workspace:WaitForChild(G.HOME_INSTANCE_FOLDER, 10)
	if not folder then
		return nil
	end
	local m = folder:FindFirstChild(name) or folder:WaitForChild(name, 10)
	return if m and m:IsA("Model") then m else nil
end

local firstEnter = true
local function onEnter(data: any)
	if activePopup and state.inside == false then
		closePopup()
	end
	state.inside = true
	state.role = data.role
	state.ownerId = data.ownerId or 0
	state.ownerName = data.ownerName or ""
	state.homeName = data.homeName or "집"
	state.tierKey = data.tierKey or ""
	state.tierName = data.tierName or ""
	state.icon = data.icon or "🏠"
	state.maxGuests = data.maxGuests or 1
	state.guests = data.guests or {}
	state.slots = data.slots or {}
	state.tvOn = data.tvOn == true
	state.owned = data.owned == true
	if data.housing then
		state.housing = data.housing
	end
	state.modelName = data.modelName or ""
	state.listingId = data.listingId
	state.model = nil
	refreshBar()
	task.spawn(function()
		local m = findModel(state.modelName)
		if m and state.inside and state.modelName == m.Name then
			state.model = m
			refreshTv()
		end
	end)
	if firstEnter and state.role == "owner" then
		firstEnter = false
		toast("home", "🏠 집 사용법", "침대=잠자기 · 소파+TV=행복 · 냉장고=식사 · 욕실=샤워 · 창문=인증샷 · 현관 패널/🛠️ 인테리어로 가구·벽지 바꾸기")
	end
end

local function onExit()
	if Interior then
		Interior.close()
	end
	if sheet then
		closeSheet()
	end
	closePhoto()
	exitDecor()
	stopPose()
	clearTv()
	state.inside = false
	state.role = nil
	state.model = nil
	refreshBar()
end

HomeState.OnClientEvent:Connect(function(data: any)
	if type(data) ~= "table" then
		return
	end
	local kind = data.kind
	local ok, err = pcall(function()
		if kind == "enter" then
			onEnter(data)
		elseif kind == "exit" then
			onExit()
		elseif kind == "guests" then
			state.guests = data.guests or {}
			if data.maxGuests then
				state.maxGuests = data.maxGuests
			end
			refreshBar()
			if sheet and sheet.kind == "guests" then
				refreshSheet()
			end
		elseif kind == "interior" then
			if Interior then
				if sheet then
					closeSheet()
				end
				Interior.open(data)
			end
		elseif kind == "themes" then
			if Interior then
				Interior.onThemes(data)
			end
		elseif kind == "interiorResult" then
			if Interior then
				Interior.onResult(data)
			end
		elseif kind == "furniture" then
			if Interior then
				Interior.onFurniture(data)
			end
			state.slots = data.slots or state.slots
			if data.housing then
				state.housing = data.housing
			end
			if decor then
				decor.variantIndex = nil
				decor.focused = decor.focused
			end
			if sheet and sheet.kind == "decor" then
				refreshSheet()
			end
			task.delay(0.2, refreshTv)
		elseif kind == "invite" then
			showInvite(data)
		elseif kind == "doorbell" then
			showDoorbell(data)
		elseif kind == "tv" then
			state.tvOn = data.on == true
			refreshTv()
		elseif kind == "panel" then
			local name = data.panel
			panelData[name] = data.data
			if name == "window" then
				openPhoto(data.data or {})
			elseif name == "fridge" then
				openSheet("fridge", "🧊 냉장고 · 식사", buildFridge)
			elseif name == "mailbox" then
				openSheet("mailbox", "📬 우편함 · 고지서", buildMailbox)
			elseif name == "desk" then
				openSheet("desk", "🖥️ 책상 · 통장과 제안", buildDesk)
			elseif name == "wardrobe" then
				openSheet("wardrobe", "👕 옷장", buildWardrobe)
			elseif name == "guests" then
				openSheet("guests", "💌 초대하기", buildGuestPanel)
			end
		elseif kind == "pose" then
			playPose(data.pose or "none", data.seconds)
		elseif kind == "openApp" then
			openPhoneApp(data.app or "bank", data.args)
		end
	end)
	if not ok then
		warn("[GwangalliHome] HomeState " .. tostring(kind) .. ": " .. tostring(err))
	end
end)

-------------------------------------------------------------------------------------------------
-- Layout / lifecycle
-------------------------------------------------------------------------------------------------
local function relayout()
	if state.inside then
		layoutBar()
	end
	if sheet then
		layoutSheet()
	end
end
if Layout and type(Layout.onChanged) == "function" then
	pcall(Layout.onChanged, relayout)
end
hudGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

player.CharacterAdded:Connect(function()
	stopPose()
	closePopup()
	if photo then
		closePhoto()
	end
	if controlsOff and not sheet then
		setControls(true)
	end
end)

-- keyboard shortcuts on PC while at home: B = 꾸미기, I = 초대, Esc closes a sheet
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		if photo then
			closePhoto()
		elseif sheet then
			closeSheet()
		end
	elseif state.inside and state.role == "owner" and not sheet then
		if input.KeyCode == Enum.KeyCode.B then
			openInterior()
		elseif input.KeyCode == Enum.KeyCode.I then
			openGuests()
		end
	end
end)
