--!strict
-- GwangalliBuildingInterior/Hosp_UI: HospitalPlus 화면 UI (PlayerGui/GwHospitalUI).
--   fade(toBlack, t, caption)  화면 어둡게/밝게 (yield)
--   toast(text, t)             아래 가운데 안내 한 줄
--   lift(show, handlers)       엘리베이터 조작반 (1 · 2 · R · 열림 · 닫힘 · 비상), PC 숫자키 · 패드 · 터치
--   scope(show, onClose)       망원경 원형 시야
-- 서버 GwangalliFade(DisplayOrder 60) 아래(55)에 둠. 아무것도 안 보일 때는 Enabled = false.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local UI = {}

local C3 = Color3.fromRGB
local TEAL = C3(0, 128, 118)
local INK = C3(24, 28, 32)
local FONT_B, FONT_M = Enum.Font.GothamBold, Enum.Font.GothamMedium

local gui: ScreenGui? = nil
local fadeF: Frame? = nil
local fadeCap: TextLabel? = nil
local toastF: Frame? = nil
local toastL: TextLabel? = nil
local toastSeq = 0
local liftF: Frame? = nil
local liftApi: any = nil
local scopeF: Frame? = nil
local showing = { fade = false, toast = false, lift = false, scope = false }

local function refresh()
	if gui then
		gui.Enabled = showing.fade or showing.toast or showing.lift or showing.scope
	end
end

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function ensure(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local pl = Players.LocalPlayer
	local pg = pl and pl:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local g = Instance.new("ScreenGui")
	g.Name = "GwHospitalUI"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 55
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Enabled = false
	g.Parent = pg
	gui = g
	return g
end

-- 페이드 ---------------------------------------------------------------------------------------------

function UI.fade(toBlack: boolean, t: number, caption: string?)
	local g = ensure()
	if not g then
		return
	end
	if not fadeF or not fadeF.Parent then
		local f = Instance.new("Frame")
		f.Name = "Fade"
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.ZIndex = 50
		f.Parent = g
		local cap = Instance.new("TextLabel")
		cap.Name = "Caption"
		cap.AnchorPoint = Vector2.new(0.5, 0.5)
		cap.Position = UDim2.fromScale(0.5, 0.5)
		cap.Size = UDim2.new(0.8, 0, 0, 40)
		cap.BackgroundTransparency = 1
		cap.TextColor3 = Color3.new(1, 1, 1)
		cap.TextTransparency = 1
		cap.Font = FONT_B
		cap.TextSize = 26
		cap.Text = ""
		cap.ZIndex = 51
		cap.Parent = f
		fadeF, fadeCap = f, cap
	end
	local f = fadeF :: Frame
	local cap = fadeCap :: TextLabel
	if caption then
		cap.Text = caption
	end
	showing.fade = true
	refresh()
	local info = TweenInfo.new(t, Enum.EasingStyle.Quad, if toBlack then Enum.EasingDirection.Out else Enum.EasingDirection.In)
	TweenService:Create(f, info, { BackgroundTransparency = if toBlack then 0 else 1 }):Play()
	TweenService:Create(cap, info, { TextTransparency = if toBlack and caption then 0 else 1 }):Play()
	task.wait(t)
	if not toBlack then
		showing.fade = false
		refresh()
	end
end

-- 즉시 밝게 (비상 정리)
function UI.unfade()
	if fadeF then
		fadeF.BackgroundTransparency = 1
	end
	if fadeCap then
		fadeCap.TextTransparency = 1
	end
	showing.fade = false
	refresh()
end

-- 안내 한 줄 ---------------------------------------------------------------------------------------

function UI.toast(text: string, t: number?)
	local g = ensure()
	if not g then
		return
	end
	if not toastF or not toastF.Parent then
		local f = Instance.new("Frame")
		f.Name = "Toast"
		f.AnchorPoint = Vector2.new(0.5, 1)
		f.Position = UDim2.new(0.5, 0, 1, -110)
		f.Size = UDim2.new(0, 520, 0, 46)
		f.BackgroundColor3 = INK
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.ZIndex = 40
		f.Parent = g
		corner(f, 14)
		local c = Instance.new("UISizeConstraint")
		c.MaxSize = Vector2.new(620, 80)
		c.Parent = f
		local bar = Instance.new("Frame")
		bar.Name = "Accent"
		bar.Size = UDim2.new(0, 6, 1, -16)
		bar.Position = UDim2.new(0, 10, 0, 8)
		bar.BackgroundColor3 = TEAL
		bar.BorderSizePixel = 0
		bar.ZIndex = 41
		bar.Parent = f
		corner(bar, 3)
		local l = Instance.new("TextLabel")
		l.Name = "Text"
		l.Position = UDim2.new(0, 26, 0, 0)
		l.Size = UDim2.new(1, -40, 1, 0)
		l.BackgroundTransparency = 1
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextTransparency = 1
		l.Font = FONT_M
		l.TextSize = 18
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.ZIndex = 41
		l.Parent = f
		toastF, toastL = f, l
	end
	local f = toastF :: Frame
	local l = toastL :: TextLabel
	-- 화면 폭에 맞춤 (모바일)
	local cam = workspace.CurrentCamera
	local vw = if cam then cam.ViewportSize.X else 800
	f.Size = UDim2.new(0, math.clamp(vw - 40, 260, 620), 0, if #text > 44 then 64 else 46)
	l.Text = text
	toastSeq += 1
	local seq = toastSeq
	showing.toast = true
	refresh()
	local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(f, info, { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(l, info, { TextTransparency = 0 }):Play()
	f:FindFirstChild("Accent")
	task.delay(t or 2.6, function()
		if seq ~= toastSeq or not f.Parent then
			return
		end
		local out = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(f, out, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(l, out, { TextTransparency = 1 }):Play()
		task.delay(0.4, function()
			if seq == toastSeq then
				showing.toast = false
				refresh()
			end
		end)
	end)
end

-- 엘리베이터 조작반 -------------------------------------------------------------------------------------

local LIFT_ACTION = "GwHospLiftKeys"

local function liftButton(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Position = pos
	b.Size = size
	b.BackgroundColor3 = color or C3(58, 62, 68)
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = FONT_B
	b.TextSize = 22
	b.Selectable = true
	b.ZIndex = 31
	b.Parent = parent
	corner(b, 999)
	local s = Instance.new("UIStroke")
	s.Name = "Ring"
	s.Thickness = 2
	s.Color = C3(220, 224, 228)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	return b
end

-- handlers = { floor = fn(i), open = fn(), close = fn(), alarm = fn() }. 반환 api: display(text), lit(i, on), shown()
function UI.lift(show: boolean, handlers: any?): any
	if not show then
		if liftF then
			liftF.Visible = false
		end
		showing.lift = false
		pcall(function()
			ContextActionService:UnbindAction(LIFT_ACTION)
		end)
		if GuiService.SelectedObject and liftF and GuiService.SelectedObject:IsDescendantOf(liftF) then
			GuiService.SelectedObject = nil
		end
		refresh()
		return liftApi
	end
	local g = ensure()
	if not g then
		return nil
	end
	local h: any = handlers or {}
	if not liftF or not liftF.Parent then
		local f = Instance.new("Frame")
		f.Name = "LiftPanel"
		f.AnchorPoint = Vector2.new(1, 0.5)
		f.Position = UDim2.new(1, -18, 0.5, 0)
		f.Size = UDim2.new(0, 168, 0, 360)
		f.BackgroundColor3 = C3(196, 190, 180)
		f.BorderSizePixel = 0
		f.ZIndex = 30
		f.Parent = g
		corner(f, 16)
		local st = Instance.new("UIStroke")
		st.Thickness = 2
		st.Color = C3(150, 146, 140)
		st.Parent = f
		local sc = Instance.new("UIScale")
		sc.Name = "Scale"
		sc.Parent = f
		local disp = Instance.new("TextLabel")
		disp.Name = "Display"
		disp.Position = UDim2.new(0, 14, 0, 12)
		disp.Size = UDim2.new(1, -28, 0, 48)
		disp.BackgroundColor3 = C3(10, 10, 12)
		disp.BorderSizePixel = 0
		disp.Font = Enum.Font.Code
		disp.TextColor3 = C3(255, 70, 50)
		disp.TextSize = 32
		disp.Text = "1"
		disp.ZIndex = 31
		disp.Parent = f
		corner(disp, 6)
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Position = UDim2.new(0, 0, 0, 62)
		title.Size = UDim2.new(1, 0, 0, 18)
		title.BackgroundTransparency = 1
		title.Font = FONT_M
		title.TextColor3 = C3(60, 60, 64)
		title.TextSize = 13
		title.Text = "정원 9인 · 600kg"
		title.ZIndex = 31
		title.Parent = f
		local bs = UDim2.new(0, 58, 0, 58)
		local bR = liftButton(f, "B3", "R", UDim2.new(0.5, -29, 0, 86), bs)
		local b2 = liftButton(f, "B2", "2", UDim2.new(0.5, -29, 0, 150), bs)
		local b1 = liftButton(f, "B1", "1", UDim2.new(0.5, -29, 0, 214), bs)
		local bo = liftButton(f, "Open", "◀▶", UDim2.new(0, 14, 0, 282), UDim2.new(0, 64, 0, 30), C3(70, 74, 80))
		local bc = liftButton(f, "Close", "▶◀", UDim2.new(1, -78, 0, 282), UDim2.new(0, 64, 0, 30), C3(70, 74, 80))
		local ba = liftButton(f, "Alarm", "🔔 비상", UDim2.new(0, 14, 0, 320), UDim2.new(1, -28, 0, 30), C3(214, 170, 30))
		bo.TextSize, bc.TextSize, ba.TextSize = 16, 16, 15
		ba.TextColor3 = C3(30, 30, 30)
		local api: any = { buttons = { b1, b2, bR }, handlers = h }
		local function fire(name: string, ...)
			local fn = api.handlers and api.handlers[name]
			if fn then
				local ok, err = pcall(fn, ...)
				if not ok then
					warn("[HospitalPlus] lift ui: " .. tostring(err))
				end
			end
		end
		b1.Activated:Connect(function()
			fire("floor", 1)
		end)
		b2.Activated:Connect(function()
			fire("floor", 2)
		end)
		bR.Activated:Connect(function()
			fire("floor", 3)
		end)
		bo.Activated:Connect(function()
			fire("open")
		end)
		bc.Activated:Connect(function()
			fire("close")
		end)
		ba.Activated:Connect(function()
			fire("alarm")
		end)
		api.fire = fire
		function api.display(text: string)
			disp.Text = text
		end
		function api.lit(i: number, on: boolean)
			local b = api.buttons[i]
			if b then
				local ring = b:FindFirstChild("Ring") :: UIStroke?
				if ring then
					ring.Color = if on then C3(255, 176, 60) else C3(220, 224, 228)
					ring.Thickness = if on then 4 else 2
				end
				b.TextColor3 = if on then C3(255, 200, 110) else Color3.new(1, 1, 1)
			end
		end
		function api.shown(): boolean
			return showing.lift
		end
		liftF = f
		liftApi = api
	end
	local f = liftF :: Frame
	liftApi.handlers = h
	-- 작은 화면이면 줄임
	local cam = workspace.CurrentCamera
	local vh = if cam then cam.ViewportSize.Y else 720
	local sc = f:FindFirstChild("Scale") :: UIScale?
	if sc then
		sc.Scale = math.clamp(vh / 720, 0.7, 1.15)
	end
	if not f.Visible or not showing.lift then
		f.Visible = true
		showing.lift = true
		refresh()
		pcall(function()
			ContextActionService:BindActionAtPriority(LIFT_ACTION, function(_n, state, input)
				if state ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Pass
				end
				local k = input.KeyCode
				if k == Enum.KeyCode.One or k == Enum.KeyCode.KeypadOne then
					liftApi.fire("floor", 1)
				elseif k == Enum.KeyCode.Two or k == Enum.KeyCode.KeypadTwo then
					liftApi.fire("floor", 2)
				elseif k == Enum.KeyCode.Three or k == Enum.KeyCode.KeypadThree then
					liftApi.fire("floor", 3)
				else
					return Enum.ContextActionResult.Pass
				end
				return Enum.ContextActionResult.Sink
			end, false, 3000, Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.KeypadOne, Enum.KeyCode.KeypadTwo, Enum.KeyCode.KeypadThree)
		end)
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = liftApi.buttons[1]
		end
	end
	return liftApi
end

-- 망원경 --------------------------------------------------------------------------------------------

function UI.scope(show: boolean, onClose: (() -> ())?, caption: string?)
	if not show then
		if scopeF then
			scopeF.Visible = false
		end
		showing.scope = false
		refresh()
		return
	end
	local g = ensure()
	if not g then
		return
	end
	if not scopeF or not scopeF.Parent then
		local f = Instance.new("Frame")
		f.Name = "Scope"
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundTransparency = 1
		f.ZIndex = 20
		f.Parent = g
		local hole = Instance.new("Frame")
		hole.Name = "Hole"
		hole.AnchorPoint = Vector2.new(0.5, 0.5)
		hole.Position = UDim2.fromScale(0.5, 0.5)
		hole.Size = UDim2.fromScale(0.78, 0.78)
		hole.BackgroundTransparency = 1
		hole.ZIndex = 20
		hole.Parent = f
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = hole
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(1, 0)
		rc.Parent = hole
		local st = Instance.new("UIStroke")
		st.Thickness = 2400
		st.Color = Color3.new(0, 0, 0)
		st.Parent = hole
		for _, d in { { 0.5, 0.0, 0.002, 0.08 }, { 0.5, 0.92, 0.002, 0.08 }, { 0.0, 0.5, 0.08, 0.002 }, { 0.92, 0.5, 0.08, 0.002 } } do
			local l = Instance.new("Frame")
			l.Name = "Tick"
			l.Position = UDim2.fromScale(d[1] - (if d[3] < 0.01 then 0.001 else 0), d[2] - (if d[4] < 0.01 then 0.001 else 0))
			l.Size = UDim2.fromScale(d[3], d[4])
			l.BackgroundColor3 = Color3.new(0, 0, 0)
			l.BackgroundTransparency = 0.3
			l.BorderSizePixel = 0
			l.ZIndex = 21
			l.Parent = hole
		end
		local cap = Instance.new("TextLabel")
		cap.Name = "Caption"
		cap.AnchorPoint = Vector2.new(0.5, 0)
		cap.Position = UDim2.new(0.5, 0, 0, 24)
		cap.Size = UDim2.new(0.9, 0, 0, 30)
		cap.BackgroundTransparency = 1
		cap.TextColor3 = Color3.new(1, 1, 1)
		cap.Font = FONT_B
		cap.TextSize = 20
		cap.ZIndex = 22
		cap.Parent = f
		local close = Instance.new("TextButton")
		close.Name = "Close"
		close.AnchorPoint = Vector2.new(0.5, 1)
		close.Position = UDim2.new(0.5, 0, 1, -28)
		close.Size = UDim2.new(0, 190, 0, 48)
		close.BackgroundColor3 = C3(40, 44, 50)
		close.TextColor3 = Color3.new(1, 1, 1)
		close.Font = FONT_B
		close.TextSize = 18
		close.Text = "망원경 내려놓기"
		close.ZIndex = 22
		close.Parent = f
		corner(close, 12)
		scopeF = f
	end
	local f = scopeF :: Frame
	local cap = f:FindFirstChild("Caption") :: TextLabel
	cap.Text = caption or "광안대교"
	local close = f:FindFirstChild("Close") :: TextButton
	local old = close:FindFirstChild("Conn") :: ObjectValue?
	if old then
		old:Destroy()
	end
	local c = close.Activated:Connect(function()
		if onClose then
			onClose()
		end
	end)
	-- 연결 보관 (다음 열기 때 끊음)
	local holder = Instance.new("ObjectValue")
	holder.Name = "Conn"
	holder.Parent = close
	holder.Destroying:Connect(function()
		c:Disconnect()
	end)
	f.Visible = true
	showing.scope = true
	refresh()
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = close
	end
end

function UI.destroy()
	pcall(function()
		ContextActionService:UnbindAction(LIFT_ACTION)
	end)
	if gui then
		gui:Destroy()
	end
	gui, fadeF, fadeCap, toastF, toastL, liftF, liftApi, scopeF = nil, nil, nil, nil, nil, nil, nil, nil
	showing = { fade = false, toast = false, lift = false, scope = false }
end

return UI
