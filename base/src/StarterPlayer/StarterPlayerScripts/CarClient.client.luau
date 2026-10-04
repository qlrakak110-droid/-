-- Integrated Gwangalli mode: one driver controller and one ownership UI.
do
 local rs = game:GetService("ReplicatedStorage")
 if rs:FindFirstChild("GwangalliVehiclesShared") then
  local player = game:GetService("Players").LocalPlayer
  local gui = Instance.new("ScreenGui")
  gui.Name = "GWIntegratedCarShortcut"; gui.ResetOnSpawn = false; gui.DisplayOrder = 21
  gui.Parent = player:WaitForChild("PlayerGui")
  local btn = Instance.new("TextButton")
  btn.Name = "MyCar"; btn.Text = "🚗 내 차"; btn.Size = UDim2.fromOffset(92, 44)
  btn.AnchorPoint = Vector2.new(1, 0); btn.Position = UDim2.new(1, -12, 0, 104)
  btn.BackgroundColor3 = Color3.fromRGB(22, 35, 52); btn.TextColor3 = Color3.new(1, 1, 1)
  btn.TextSize = 16; btn.Font = Enum.Font.GothamBold; btn.Parent = gui
  local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 14); corner.Parent = btn
  btn.Activated:Connect(function()
   for _, folder in player.PlayerScripts:GetChildren() do
    if folder:IsA("Folder") and folder.Name == "GwangalliDrive" then
     local api = folder:FindFirstChild("Api")
     if api then
      local drive = require(api)
      drive.open("callcar")
      return
     end
    end
   end
  end)
  return
 end
end
--[[
	📁 위치: StarterPlayer  >  StarterPlayerScripts  >  LocalScript  (이름: CarClient)
	클라이언트 담당:
	  - 운전 물리 (레이캐스트 서스펜션, 가속/브레이크/후진, 사이드브레이크 드리프트, 차체 롤/피치)
	  - PC 키보드 / 모바일 버튼(핸들 ◀▶, 가속, 브레이크, 사이드) / 게임패드
	  - 카메라: 추적 시점 / 실내 시점(계기판 보임) / 자유 시점
	  - 운전 중 손 핸들 잡는 자세, 핸들 회전, 바퀴 회전·조향, 브레이크등/후진등
	  - HUD, 계기판, 연료 소모, 충돌 감지, 주차 감지, 주유/수리 버튼, 📱 폰(택시/내 차), 택시 목적지
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local plr = Players.LocalPlayer
local cam = workspace.CurrentCamera
local Config = require(RS:WaitForChild("CarConfig"))
local remotes = RS:WaitForChild("CarRemotes")
local ActionRE = remotes:WaitForChild("Action")
local NotifyRE = remotes:WaitForChild("Notify")
local StateRE = remotes:WaitForChild("State")
local CarsFolder = workspace:WaitForChild("Cars")

local controls
pcall(function()
	controls = require(plr:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
end)

local IS_TOUCH = UIS.TouchEnabled
local WHEELS = { "FL", "FR", "RL", "RR" }

local S = {
	car = nil, seat = nil, kind = nil, role = nil,
	camMode = "free", steer = 0, spin = { FL = 0, FR = 0, RL = 0, RR = 0 },
	fuel = 100, lastV = Vector3.zero, handbrake = false, gas = false, brake = false,
	left = false, right = false, yawOff = 0, pitchOff = 0, camPos = nil, gear = "P",
	fuelSyncT = 0, parkT = 0, parkedIdx = nil, shake = 0, speed = 0, outOfFuelWarned = false,
	taxiCar = nil, taxiState = nil, taxiDest = nil, taxiOdo = 0, taxiLast = nil,
}
local D = nil -- 운전 데이터

---------------------------------------------------------------- UI
local gui = Instance.new("ScreenGui")
gui.Name = "CarUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = plr:WaitForChild("PlayerGui")

local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 14)
	c.Parent = o
	return c
end
local function stroke(o, col, th)
	local s = Instance.new("UIStroke")
	s.Color = col or Color3.new(1, 1, 1)
	s.Thickness = th or 2
	s.Transparency = 0.4
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
	return s
end
local function label(parent, text, size, pos, ts, col)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Text = text
	t.TextColor3 = col or Color3.new(1, 1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextSize = ts or 18
	t.TextScaled = ts == nil
	t.Parent = parent
	return t
end
local function button(text, size, pos, color, parent)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = color or Color3.fromRGB(25, 28, 36)
	b.BackgroundTransparency = 0.15
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.AutoButtonColor = true
	b.Parent = parent or gui
	corner(b, 16)
	stroke(b)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = b
	return b
end
local function holdButton(b, onDown, onUp)
	b.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
			onDown()
		end
	end)
	b.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
			onUp()
		end
	end)
end

-- 알림
local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 12)
toast.Size = UDim2.new(0, 520, 0, 46)
toast.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
toast.BackgroundTransparency = 1
toast.TextTransparency = 1
toast.TextColor3 = Color3.new(1, 1, 1)
toast.Font = Enum.Font.GothamBold
toast.TextScaled = true
toast.Parent = gui
corner(toast, 14)
local toastPad = Instance.new("UIPadding")
toastPad.PaddingLeft = UDim.new(0, 14)
toastPad.PaddingRight = UDim.new(0, 14)
toastPad.PaddingTop = UDim.new(0, 8)
toastPad.PaddingBottom = UDim.new(0, 8)
toastPad.Parent = toast
local toastId = 0
local function showToast(text)
	toastId += 1
	local my = toastId
	toast.Text = text
	toast.BackgroundTransparency = 0.15
	toast.TextTransparency = 0
	task.delay(3.2, function()
		if toastId == my then
			TweenService:Create(toast, TweenInfo.new(0.5), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		end
	end)
end
NotifyRE.OnClientEvent:Connect(showToast)

-- 돈
local moneyLabel = Instance.new("TextLabel")
moneyLabel.AnchorPoint = Vector2.new(1, 0)
moneyLabel.Position = UDim2.new(1, -12, 0, 12)
moneyLabel.Size = UDim2.new(0, 200, 0, 44)
moneyLabel.BackgroundColor3 = Color3.fromRGB(20, 120, 70)
moneyLabel.BackgroundTransparency = 0.1
moneyLabel.TextColor3 = Color3.new(1, 1, 1)
moneyLabel.Font = Enum.Font.GothamBlack
moneyLabel.TextScaled = true
moneyLabel.Text = "₩0"
moneyLabel.Parent = gui
corner(moneyLabel, 12)
task.spawn(function()
	local ls = plr:WaitForChild("leaderstats")
	local m = ls:WaitForChild("Money")
	local function upd()
		moneyLabel.Text = "💰 ₩" .. tostring(m.Value)
	end
	m.Changed:Connect(upd)
	upd()
end)

-- 택시 상태
local taxiLabel = Instance.new("TextLabel")
taxiLabel.Position = UDim2.new(0, 12, 0, 12)
taxiLabel.Size = UDim2.new(0, 330, 0, 44)
taxiLabel.BackgroundColor3 = Color3.fromRGB(230, 140, 30)
taxiLabel.BackgroundTransparency = 0.1
taxiLabel.TextColor3 = Color3.new(1, 1, 1)
taxiLabel.Font = Enum.Font.GothamBold
taxiLabel.TextScaled = true
taxiLabel.Visible = false
taxiLabel.Parent = gui
corner(taxiLabel, 12)

-- HUD (운전석)
local hud = Instance.new("Frame")
hud.AnchorPoint = Vector2.new(0.5, 1)
hud.Position = UDim2.new(0.5, 0, 1, -14)
hud.Size = UDim2.new(0, 330, 0, 92)
hud.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
hud.BackgroundTransparency = 0.2
hud.Visible = false
hud.Parent = gui
corner(hud, 18)
stroke(hud, Color3.fromRGB(90, 170, 255), 2)
local speedLabel = label(hud, "0", UDim2.new(0, 120, 0, 60), UDim2.new(0, 10, 0, 4), nil, Color3.fromRGB(130, 210, 255))
speedLabel.Font = Enum.Font.GothamBlack
label(hud, "km/h", UDim2.new(0, 120, 0, 20), UDim2.new(0, 10, 0, 64), 14, Color3.fromRGB(160, 170, 185))
local gearLabel = label(hud, "P", UDim2.new(0, 46, 0, 46), UDim2.new(0, 130, 0, 22), nil)
gearLabel.Font = Enum.Font.GothamBlack
local function bar(y, col, icon)
	label(hud, icon, UDim2.new(0, 24, 0, 24), UDim2.new(0, 186, 0, y - 4), 18)
	local bg = Instance.new("Frame")
	bg.Position = UDim2.new(0, 214, 0, y)
	bg.Size = UDim2.new(0, 104, 0, 16)
	bg.BackgroundColor3 = Color3.fromRGB(45, 48, 56)
	bg.Parent = hud
	corner(bg, 8)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = col
	f.Parent = bg
	corner(f, 8)
	return f
end
local fuelBar = bar(22, Color3.fromRGB(255, 190, 40), "⛽")
local hpBar = bar(56, Color3.fromRGB(80, 220, 120), "🔧")

-- 버튼들
local phoneBtn = button("📱", UDim2.new(0, 60, 0, 60), UDim2.new(1, -72, 0, 66), Color3.fromRGB(40, 60, 110))
local col = UDim2.new(1, -72, 0.28, 0)
local function colPos(i)
	return col + UDim2.new(0, 0, 0, (i - 1) * 68)
end
local exitBtn = button("🚪 내리기", UDim2.new(0, 60, 0, 60), colPos(1), Color3.fromRGB(150, 40, 40))
local camBtn = button("🎥", UDim2.new(0, 60, 0, 60), colPos(2))
local lightBtn = button("💡", UDim2.new(0, 60, 0, 60), colPos(3))
local hornBtn = button("📯", UDim2.new(0, 60, 0, 60), colPos(4))
local flipBtn = button("🔄", UDim2.new(0, 60, 0, 60), colPos(5))
local ctxBtn = button("", UDim2.new(0, 240, 0, 52), UDim2.new(0.5, -120, 1, -170), Color3.fromRGB(30, 140, 80))
ctxBtn.Visible = false
local parkBanner = label(gui, "✅ 주차 완료!", UDim2.new(0, 300, 0, 50), UDim2.new(0.5, -150, 0.22, 0), nil, Color3.fromRGB(120, 255, 150))
parkBanner.Visible = false
parkBanner.Font = Enum.Font.GothamBlack

-- 모바일 운전 버튼
local touchDrive = Instance.new("Frame")
touchDrive.Size = UDim2.fromScale(1, 1)
touchDrive.BackgroundTransparency = 1
touchDrive.Visible = false
touchDrive.Parent = gui
local leftBtn = button("◀", UDim2.new(0, 110, 0, 110), UDim2.new(0, 18, 1, -128), nil, touchDrive)
local rightBtn = button("▶", UDim2.new(0, 110, 0, 110), UDim2.new(0, 140, 1, -128), nil, touchDrive)
local gasBtn = button("▲\n가속", UDim2.new(0, 100, 0, 130), UDim2.new(1, -118, 1, -148), Color3.fromRGB(30, 130, 70), touchDrive)
local brakeBtn = button("▼\n브레이크", UDim2.new(0, 100, 0, 100), UDim2.new(1, -230, 1, -118), Color3.fromRGB(150, 40, 40), touchDrive)
local hbBtn = button("사이드", UDim2.new(0, 100, 0, 56), UDim2.new(1, -230, 1, -184), Color3.fromRGB(110, 80, 20), touchDrive)
holdButton(leftBtn, function() S.left = true end, function() S.left = false end)
holdButton(rightBtn, function() S.right = true end, function() S.right = false end)
holdButton(gasBtn, function() S.gas = true end, function() S.gas = false end)
holdButton(brakeBtn, function() S.brake = true end, function() S.brake = false end)
holdButton(hbBtn, function() S.handbrake = true end, function() S.handbrake = false end)

-- 패널 공통
local function panel(title)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.new(0, 320, 0, 420)
	f.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	f.BackgroundTransparency = 0.05
	f.Visible = false
	f.Parent = gui
	corner(f, 26)
	stroke(f, Color3.fromRGB(120, 140, 170), 3)
	local t = label(f, title, UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 0, 12), nil)
	t.Font = Enum.Font.GothamBlack
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 14, 0, 62)
	list.Size = UDim2.new(1, -28, 1, -76)
	list.BackgroundTransparency = 1
	list.ScrollBarThickness = 4
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = f
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 8)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = list
	return f, list
end
local function listButton(list, text, color, order, fn)
	local b = button(text, UDim2.new(1, -6, 0, 50), UDim2.new(), color, list)
	b.LayoutOrder = order
	b.MouseButton1Click:Connect(fn)
	return b
end

-- 📱 폰
local phone, phoneList = panel("📱 내 폰")
local function closePhone()
	phone.Visible = false
end
local function rebuildPhone()
	for _, c in ipairs(phoneList:GetChildren()) do
		if c:IsA("TextButton") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	listButton(phoneList, "🚕 택시 부르기", Color3.fromRGB(230, 140, 30), 1, function()
		ActionRE:FireServer("CallTaxi")
		closePhone()
	end)
	listButton(phoneList, "❌ 택시 취소", Color3.fromRGB(120, 50, 50), 2, function()
		ActionRE:FireServer("CancelTaxi")
		closePhone()
	end)
	local h = label(phoneList, "🚗 내 차 부르기", UDim2.new(1, -6, 0, 30), UDim2.new(), nil, Color3.fromRGB(170, 190, 220))
	h.LayoutOrder = 3
	local owned = string.split(plr:GetAttribute("Owned") or "", ",")
	local order = 4
	for _, t in ipairs(owned) do
		if Config.Cars[t] then
			listButton(phoneList, "🚗 " .. Config.Cars[t].Name, Color3.fromRGB(40, 80, 150), order, function()
				ActionRE:FireServer("Summon", t)
				closePhone()
			end)
			order += 1
		end
	end
	local tip = label(phoneList, "💡 차는 자동차 매장(🚗 마커)에서 구매", UDim2.new(1, -6, 0, 40), UDim2.new(), nil, Color3.fromRGB(150, 160, 175))
	tip.LayoutOrder = 50
	listButton(phoneList, "닫기", Color3.fromRGB(60, 60, 70), 99, closePhone)
end
plr:GetAttributeChangedSignal("Owned"):Connect(rebuildPhone)
rebuildPhone()
local function togglePhone()
	rebuildPhone()
	phone.Visible = not phone.Visible
end
phoneBtn.MouseButton1Click:Connect(togglePhone)

-- 🚕 목적지
local taxiPanel, taxiList = panel("🚕 어디로 갈까요?")
local function openTaxiMenu(dests)
	for _, c in ipairs(taxiList:GetChildren()) do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	for i, name in ipairs(dests) do
		listButton(taxiList, "📍 " .. name, Color3.fromRGB(40, 90, 160), i, function()
			S.taxiDest = name
			ActionRE:FireServer("TaxiDest", i)
			taxiPanel.Visible = false
		end)
	end
	listButton(taxiList, "🚪 그냥 내리기", Color3.fromRGB(120, 50, 50), 99, function()
		taxiPanel.Visible = false
		ActionRE:FireServer("Exit")
	end)
	taxiPanel.Visible = true
end

---------------------------------------------------------------- 캐릭터 헬퍼
local function getHum()
	local c = plr.Character
	return c and c:FindFirstChildOfClass("Humanoid"), c
end

local function setHeadHidden(hidden)
	local _, c = getHum()
	if not c then
		return
	end
	for _, p in ipairs(c:GetDescendants()) do
		if p:IsA("BasePart") and (p.Name == "Head" or p.Parent:IsA("Accessory")) then
			p.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
	local head = c:FindFirstChild("Head")
	if head then
		for _, dcl in ipairs(head:GetChildren()) do
			if dcl:IsA("Decal") then
				dcl.Transparency = hidden and 1 or 0
			end
		end
	end
end

---------------------------------------------------------------- 운전 설정
local function setupDrive(car)
	local root = car.PrimaryPart
	local d = { car = car, root = root, forces = {}, atts = {}, motors = {}, lamps = {} }
	for _, n in ipairs(WHEELS) do
		d.forces[n] = root:FindFirstChild("Force" .. n)
		d.atts[n] = root:FindFirstChild("Sus" .. n)
		d.motors[n] = root:FindFirstChild("Wheel" .. n)
	end
	d.upright = root:FindFirstChild("Upright")
	d.steerMotor = root:FindFirstChild("SteerMotor")
	d.R = car:GetAttribute("WheelR") or 1.25
	d.rideH = car:GetAttribute("RideH") or 2.6
	d.wheelY = -(d.rideH - d.R)
	d.xeq = 0.45
	d.rest = -d.wheelY + d.xeq
	d.maxSpeed = car:GetAttribute("MaxSpeed") or 120
	d.accel = car:GetAttribute("Accel") or 28
	d.grip = car:GetAttribute("Grip") or 10
	d.fuelUse = car:GetAttribute("FuelUse") or 1
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local _, c = getHum()
	params.FilterDescendantsInstances = { car, c }
	params.IgnoreWater = true
	d.params = params
	for _, p in ipairs(car:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("Light") then
			table.insert(d.lamps, { part = p, kind = p:GetAttribute("Light"), base = p.Transparency })
		end
	end
	S.fuel = car:GetAttribute("Fuel") or 100
	d.fuelConn = car:GetAttributeChangedSignal("Fuel"):Connect(function()
		local f = car:GetAttribute("Fuel")
		if f > S.fuel + 0.5 then
			S.fuel = f
			S.outOfFuelWarned = false
		end
	end)
	if Config.ENGINE_SOUND_ID ~= "" then
		local snd = Instance.new("Sound")
		snd.SoundId = Config.ENGINE_SOUND_ID
		snd.Looped = true
		snd.Volume = 0.5
		snd.Parent = root
		snd:Play()
		d.engine = snd
	end
	S.lastV = root.AssemblyLinearVelocity
	S.steer = 0
	D = d
end

local function stopDrive()
	if not D then
		return
	end
	for _, n in ipairs(WHEELS) do
		if D.forces[n] then
			D.forces[n].Force = Vector3.zero
		end
	end
	if D.upright then
		D.upright.Torque = Vector3.zero
	end
	if D.fuelConn then
		D.fuelConn:Disconnect()
	end
	if D.engine then
		D.engine:Destroy()
	end
	for _, l in ipairs(D.lamps) do
		if l.part.Parent and not l.part:GetAttribute("Broken") then
			l.part.Transparency = l.base
		end
	end
	ActionRE:FireServer("FuelSync", S.fuel)
	D = nil
end

---------------------------------------------------------------- 입력
local function readInput()
	local thr, str = 0, 0
	if UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.Up) then
		thr += 1
	end
	if UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.Down) then
		thr -= 1
	end
	if UIS:IsKeyDown(Enum.KeyCode.D) or UIS:IsKeyDown(Enum.KeyCode.Right) then
		str += 1
	end
	if UIS:IsKeyDown(Enum.KeyCode.A) or UIS:IsKeyDown(Enum.KeyCode.Left) then
		str -= 1
	end
	if S.gas then
		thr = 1
	end
	if S.brake then
		thr = -1
	end
	if S.left then
		str -= 1
	end
	if S.right then
		str += 1
	end
	pcall(function()
		for _, st in ipairs(UIS:GetGamepadState(Enum.UserInputType.Gamepad1)) do
			if st.KeyCode == Enum.KeyCode.Thumbstick1 and math.abs(st.Position.X) > 0.15 then
				str += st.Position.X
			elseif st.KeyCode == Enum.KeyCode.ButtonR2 and st.Position.Z > 0.1 then
				thr += st.Position.Z
			elseif st.KeyCode == Enum.KeyCode.ButtonL2 and st.Position.Z > 0.1 then
				thr -= st.Position.Z
			end
		end
	end)
	return math.clamp(thr, -1, 1), math.clamp(str, -1, 1)
end

---------------------------------------------------------------- 운전 물리 (매 프레임)
local function physicsStep(dt)
	if not D then
		return
	end
	local root = D.root
	local car = D.car
	if not root.Parent or not car.Parent then
		return
	end
	local thr, str = readInput()
	local cf = root.CFrame
	local up, fwd, right = cf.UpVector, cf.LookVector, cf.RightVector
	local vel = root.AssemblyLinearVelocity
	local vF = vel:Dot(fwd)
	S.speed = vF

	local dead = (car:GetAttribute("Health") or 100) <= 0 or S.fuel <= 0
	local steerMax = math.rad(34) - math.rad(24) * math.clamp(math.abs(vF) / D.maxSpeed, 0, 1)
	S.steer += (str * steerMax - S.steer) * math.clamp(dt * 7, 0, 1)

	local drive, brake = 0, 0
	if thr > 0.05 then
		if vF < -3 then
			brake = thr
		else
			drive = thr
		end
	elseif thr < -0.05 then
		if vF > 3 then
			brake = -thr
		else
			drive = thr * 0.6
		end
	end
	if dead then
		drive = 0
	end
	if vF < -1 and thr < 0 then
		S.gear = "R"
	elseif math.abs(vF) < 1 and math.abs(thr) < 0.05 then
		S.gear = "N"
	else
		S.gear = "D"
	end

	if root.Anchored then
		for _, n in ipairs(WHEELS) do
			D.forces[n].Force = Vector3.zero
		end
		D.upright.Torque = Vector3.zero
		return
	end

	local M = root.AssemblyMass
	local g = workspace.Gravity
	local k = (M * g / 4) / D.xeq
	local c = 2 * 0.55 * math.sqrt(k * M / 4)
	local len = D.rest + D.R
	local hits = {}
	local grounded = 0
	for _, n in ipairs(WHEELS) do
		local r = workspace:Raycast(D.atts[n].WorldPosition, -up * len, D.params)
		hits[n] = r
		if r then
			grounded += 1
		end
	end
	local gN = math.max(grounded, 1)
	local cap = (drive < 0) and D.maxSpeed * 0.3 or D.maxSpeed
	local engineF = drive * M * D.accel * math.max(0, 1 - (math.abs(vF) / cap) ^ 2)

	for _, n in ipairs(WHEELS) do
		local isFront = (n == "FL" or n == "FR")
		local origin = D.atts[n].WorldPosition
		local r = hits[n]
		local f = Vector3.zero
		local off
		if r then
			local dist = (r.Position - origin).Magnitude
			local comp = len - dist
			local pv = root:GetVelocityAtPosition(origin)
			local Fs = math.clamp(k * comp - c * pv:Dot(up), 0, M * g * 3)
			local wf, wr = fwd, right
			if isFront then
				local rot = CFrame.fromAxisAngle(up, -S.steer)
				wf = rot * fwd
				wr = rot * right
			end
			local nrm = r.Normal
			wf = (wf - nrm * wf:Dot(nrm)).Unit
			wr = (wr - nrm * wr:Dot(nrm)).Unit
			local vLong = pv:Dot(wf)
			local vLat = pv:Dot(wr)
			local Fl = engineF / gN
			if brake > 0 then
				Fl -= math.clamp(vLong * 6, -1, 1) * brake * M * 75 / gN
			end
			Fl -= vLong * M * 0.1 / gN
			if drive == 0 and brake == 0 then
				Fl -= math.clamp(vLong * 1.5, -1, 1) * M * 7 / gN
			end
			local latGrip = D.grip
			if S.handbrake and not isFront then
				latGrip = D.grip * 0.15
				Fl -= math.clamp(vLong * 4, -1, 1) * M * 40 / 4
			end
			local Flat = -vLat * (M / 4) * latGrip
			local maxF = Fs * 1.6
			Flat = math.clamp(Flat, -maxF, maxF)
			f = up * Fs + wf * Fl + wr * Flat
			off = -(dist - D.R) - D.wheelY
			S.spin[n] -= vLong / D.R * dt
		else
			off = -D.xeq
			S.spin[n] -= vF / D.R * dt * 0.98
		end
		D.forces[n].Force = f
		local m = D.motors[n]
		if m then
			m.Transform = CFrame.new(0, off, 0) * CFrame.Angles(0, isFront and -S.steer or 0, 0) * CFrame.Angles(S.spin[n] % (2 * math.pi), 0, 0)
		end
	end

	-- 전복 방지 / 자세 유지
	local av = root.AssemblyAngularVelocity
	local avH = Vector3.new(av.X, 0, av.Z)
	local axis = up:Cross(Vector3.yAxis)
	local tq = axis * M * 60 - avH * M * 10
	if grounded == 0 then
		tq *= 0.4
	end
	D.upright.Torque = tq

	-- 핸들 회전
	if D.steerMotor then
		D.steerMotor.Transform = CFrame.Angles(0, 0, -S.steer * 6)
	end

	-- 충돌 감지
	local dv = vel - S.lastV
	local dvH = Vector3.new(dv.X, dv.Y * 0.3, dv.Z)
	if dvH.Magnitude > 30 and S.lastV.Magnitude > 22 then
		local ld = cf:VectorToObjectSpace(-dvH.Unit)
		ActionRE:FireServer("Impact", dvH.Magnitude, Vector3.new(ld.X, 0, ld.Z))
		S.shake = math.min(1.5, dvH.Magnitude / 40)
	end
	S.lastV = vel

	-- 연료
	local use = (0.012 + math.abs(drive) * 0.22 * (0.4 + math.abs(vF) / D.maxSpeed)) * D.fuelUse * dt
	S.fuel = math.max(0, S.fuel - use)
	S.fuelSyncT += dt
	if S.fuelSyncT > 2 then
		S.fuelSyncT = 0
		ActionRE:FireServer("FuelSync", S.fuel)
	end
	if S.fuel <= 0 and not S.outOfFuelWarned then
		S.outOfFuelWarned = true
		showToast("⛽ 연료가 떨어졌어요! 주유소로 가거나 📱로 차를 다시 부르세요")
	end

	-- 브레이크등 / 후진등
	local braking = brake > 0 or (S.handbrake)
	for _, l in ipairs(D.lamps) do
		local p = l.part
		if p.Parent and not p:GetAttribute("Broken") then
			if l.kind == "Brake" then
				p.Transparency = braking and 0 or 0.8
			elseif l.kind == "Tail" then
				p.Transparency = braking and 0 or 0.35
			elseif l.kind == "Reverse" then
				p.Transparency = (S.gear == "R") and 0 or 0.7
			end
		end
	end

	if D.engine then
		D.engine.PlaybackSpeed = 0.7 + math.abs(vF) / D.maxSpeed * 1.4 + math.abs(drive) * 0.15
	end
end

---------------------------------------------------------------- 운전 자세 (손으로 핸들 잡기)
local function armPose()
	if S.role ~= "driver" then
		return
	end
	local _, c = getHum()
	if not c then
		return
	end
	local ru = c:FindFirstChild("RightUpperArm")
	local lu = c:FindFirstChild("LeftUpperArm")
	local rl = c:FindFirstChild("RightLowerArm")
	local ll = c:FindFirstChild("LeftLowerArm")
	local rs = ru and ru:FindFirstChild("RightShoulder")
	local ls = lu and lu:FindFirstChild("LeftShoulder")
	local re = rl and rl:FindFirstChild("RightElbow")
	local le = ll and ll:FindFirstChild("LeftElbow")
	local st = S.steer * 1.6
	if rs then
		rs.Transform = CFrame.Angles(math.rad(62) - st * 0.5, 0, math.rad(-8))
	end
	if ls then
		ls.Transform = CFrame.Angles(math.rad(62) + st * 0.5, 0, math.rad(8))
	end
	if re then
		re.Transform = CFrame.Angles(math.rad(25), 0, 0)
	end
	if le then
		le.Transform = CFrame.Angles(math.rad(25), 0, 0)
	end
end

---------------------------------------------------------------- 다른 차 바퀴 / 비상등 애니메이션
local other = {}
local blinkT = 0
local function animateOthers(dt)
	blinkT += dt
	local blinkOn = (blinkT % 0.8) < 0.4
	local camPos = cam.CFrame.Position
	for _, m in ipairs(CarsFolder:GetChildren()) do
		local root = m.PrimaryPart
		if root and (not D or D.car ~= m) then
			local dist = (root.Position - camPos).Magnitude
			if dist < 350 then
				local o = other[m]
				if not o then
					o = { last = root.CFrame, spin = 0, steer = 0, motors = {}, signals = {} }
					for _, n in ipairs(WHEELS) do
						o.motors[n] = root:FindFirstChild("Wheel" .. n)
					end
					o.steerMotor = root:FindFirstChild("SteerMotor")
					for _, p in ipairs(m:GetDescendants()) do
						if p:IsA("BasePart") and p:GetAttribute("Light") == "Signal" then
							table.insert(o.signals, { part = p, base = p.Transparency })
						end
					end
					other[m] = o
					m.Destroying:Connect(function()
						other[m] = nil
					end)
				end
				local cfNow = root.CFrame
				local dp = cfNow.Position - o.last.Position
				local v = dp:Dot(cfNow.LookVector) / math.max(dt, 1e-3)
				local _, y0 = o.last:ToOrientation()
				local _, y1 = cfNow:ToOrientation()
				local dy = (y1 - y0 + math.pi) % (2 * math.pi) - math.pi
				local wb = math.abs((m:GetAttribute("AxleR") or 6) - (m:GetAttribute("AxleF") or -6))
				local target = 0
				if math.abs(v) > 1 then
					target = math.clamp(math.atan(dy / dt * wb / v), -0.6, 0.6)
				end
				o.steer += (target - o.steer) * math.clamp(dt * 8, 0, 1)
				local R = m:GetAttribute("WheelR") or 1.25
				o.spin -= v / R * dt
				for _, n in ipairs(WHEELS) do
					local mo = o.motors[n]
					if mo then
						local front = n == "FL" or n == "FR"
						mo.Transform = CFrame.Angles(0, front and o.steer or 0, 0) * CFrame.Angles(o.spin % (2 * math.pi), 0, 0)
					end
				end
				if o.steerMotor then
					o.steerMotor.Transform = CFrame.Angles(0, 0, o.steer * 6)
				end
				local hazard = m:GetAttribute("Hazard")
				for _, sgl in ipairs(o.signals) do
					if sgl.part.Parent and not sgl.part:GetAttribute("Broken") then
						sgl.part.Transparency = (hazard and blinkOn) and 0 or sgl.base
					end
				end
				o.last = cfNow
			end
		end
	end
end

---------------------------------------------------------------- 카메라
local touchLook = {}
UIS.InputBegan:Connect(function(input, gpe)
	if input.UserInputType == Enum.UserInputType.Touch and not gpe then
		touchLook[input] = true
	end
end)
UIS.InputEnded:Connect(function(input)
	touchLook[input] = nil
end)
UIS.InputChanged:Connect(function(input, gpe)
	if S.camMode == "free" or not S.car then
		return
	end
	local delta
	if input.UserInputType == Enum.UserInputType.MouseMovement and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		delta = input.Delta
	elseif input.UserInputType == Enum.UserInputType.Touch and touchLook[input] then
		delta = input.Delta
	end
	if delta then
		S.yawOff = math.clamp(S.yawOff - delta.X * 0.006, -2.6, 2.6)
		S.pitchOff = math.clamp(S.pitchOff - delta.Y * 0.004, -0.8, 0.6)
		S.lookT = os.clock()
	end
end)

local function setCamMode(mode)
	S.camMode = mode
	setHeadHidden(mode == "interior")
	if mode == "free" then
		cam.CameraType = Enum.CameraType.Custom
		local hum = getHum()
		if hum then
			cam.CameraSubject = hum
		end
		cam.FieldOfView = 70
	else
		cam.CameraType = Enum.CameraType.Scriptable
		S.camPos = nil
		S.yawOff, S.pitchOff = 0, 0
	end
end

local function cycleCam()
	if not S.car then
		return
	end
	local order = S.role == "driver" and { "chase", "interior", "free" } or { "interior", "free" }
	local idx = table.find(order, S.camMode) or 0
	setCamMode(order[idx % #order + 1])
	local names = { chase = "🎥 추적 시점", interior = "🎥 실내 시점", free = "🎥 자유 시점" }
	showToast(names[S.camMode])
end

local function updateCamera(dt)
	if not S.car or S.camMode == "free" then
		return
	end
	local car = S.car
	local root = car.PrimaryPart
	if not root then
		return
	end
	if S.lookT and os.clock() - S.lookT > 2 and S.camMode == "chase" then
		S.yawOff *= math.exp(-dt * 2)
		S.pitchOff *= math.exp(-dt * 2)
	end
	local shake = Vector3.zero
	if S.shake > 0 then
		S.shake = math.max(0, S.shake - dt * 2.5)
		shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * S.shake * 0.6
	end
	if S.camMode == "interior" and S.seat then
		local base = S.seat.CFrame * CFrame.new(0, 2.65, 0.15)
		cam.CFrame = base * CFrame.Angles(0, S.yawOff, 0) * CFrame.Angles(S.pitchOff - 0.06, 0, 0) + shake * 0.3
		cam.FieldOfView = 78
	elseif S.camMode == "chase" then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.1 then
			flat = Vector3.new(0, 0, -1)
		end
		flat = flat.Unit
		local v = root.AssemblyLinearVelocity
		local spd = math.abs(S.speed)
		if S.speed < -3 then
			flat = -flat
		end
		local rot = CFrame.fromAxisAngle(Vector3.yAxis, S.yawOff)
		flat = rot * flat
		local dist = 19 + math.min(spd, 150) * 0.04
		local desired = root.Position - flat * dist + Vector3.new(0, 6.5 + S.pitchOff * 10, 0)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local _, c = getHum()
		params.FilterDescendantsInstances = { car, c, CarsFolder }
		local target = root.Position + Vector3.new(0, 2.5, 0)
		local hit = workspace:Raycast(target, desired - target, params)
		if hit then
			desired = hit.Position + (target - hit.Position).Unit * 1.5
		end
		if not S.camPos then
			S.camPos = desired
		end
		S.camPos = S.camPos:Lerp(desired, 1 - math.exp(-dt * 7))
		local lookAt = target + flat * 6 + v * 0.05
		cam.CFrame = CFrame.lookAt(S.camPos + shake, lookAt)
		cam.FieldOfView = 70 + math.min(spd, 160) * 0.09
	end
end

---------------------------------------------------------------- 상태 이벤트
local taxiHighlight
local function clearTaxiHighlight()
	if taxiHighlight then
		taxiHighlight:Destroy()
		taxiHighlight = nil
	end
end

local function enterUI()
	local isDriver = S.role == "driver"
	hud.Visible = isDriver
	exitBtn.Visible = true
	camBtn.Visible = true
	lightBtn.Visible = isDriver
	hornBtn.Visible = isDriver
	flipBtn.Visible = isDriver
	touchDrive.Visible = isDriver and IS_TOUCH
	phoneBtn.Visible = not isDriver or not IS_TOUCH
end
local function exitUI()
	hud.Visible = false
	exitBtn.Visible = false
	camBtn.Visible = false
	lightBtn.Visible = false
	hornBtn.Visible = false
	flipBtn.Visible = false
	touchDrive.Visible = false
	ctxBtn.Visible = false
	parkBanner.Visible = false
	taxiPanel.Visible = false
	phoneBtn.Visible = true
end
exitUI()

local function leaveCar()
	stopDrive()
	S.car, S.seat, S.kind, S.role = nil, nil, nil, nil
	S.gas, S.brake, S.left, S.right, S.handbrake = false, false, false, false, false
	setCamMode("free")
	exitUI()
	local hum = getHum()
	if hum then
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
	if controls then
		pcall(function()
			controls:Enable()
		end)
	end
end

StateRE.OnClientEvent:Connect(function(msg)
	if msg.type == "Entered" then
		local hum = getHum()
		S.car = msg.car
		S.seat = msg.car:FindFirstChild(msg.seat)
		S.kind = msg.kind
		S.role = (msg.seat == "DriverSeat" and msg.kind == "player") and "driver" or "passenger"
		if hum then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
		if controls then
			pcall(function()
				controls:Disable()
			end)
		end
		if S.role == "driver" then
			setupDrive(msg.car)
			setCamMode("chase")
		else
			setCamMode("interior")
		end
		enterUI()
		if msg.kind == "taxi" then
			clearTaxiHighlight()
		end
	elseif msg.type == "Exiting" then
		stopDrive()
		setCamMode("free")
	elseif msg.type == "Exited" then
		leaveCar()
	elseif msg.type == "Taxi" then
		S.taxiState = msg.state
		S.taxiCar = msg.car
		if msg.state == "waiting" and msg.car then
			clearTaxiHighlight()
			taxiHighlight = Instance.new("Highlight")
			taxiHighlight.FillTransparency = 0.85
			taxiHighlight.OutlineColor = Color3.fromRGB(255, 200, 40)
			taxiHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			taxiHighlight.Adornee = msg.car
			taxiHighlight.Parent = msg.car
		elseif msg.state == "riding" then
			S.taxiOdo = 0
			S.taxiLast = msg.car and msg.car.PrimaryPart and msg.car.PrimaryPart.Position
		elseif msg.state == "gone" or msg.state == "arrived" then
			clearTaxiHighlight()
			if msg.state == "gone" then
				S.taxiCar = nil
			end
		end
	elseif msg.type == "TaxiMenu" then
		S.taxiState = "boarded"
		openTaxiMenu(msg.dests or {})
	end
end)

---------------------------------------------------------------- 버튼 / 키
local function doExit()
	if S.car then
		ActionRE:FireServer("Exit")
	end
end
local function doLights()
	if S.role == "driver" then
		ActionRE:FireServer("Lights")
	end
end
local function doHorn()
	if S.role == "driver" then
		ActionRE:FireServer("Horn")
	end
end
local function doFlip()
	if S.role == "driver" and D then
		if D.root.CFrame.UpVector.Y < 0.5 or math.abs(S.speed) < 3 then
			ActionRE:FireServer("Flip")
		end
	end
end
exitBtn.MouseButton1Click:Connect(doExit)
camBtn.MouseButton1Click:Connect(cycleCam)
lightBtn.MouseButton1Click:Connect(doLights)
hornBtn.MouseButton1Click:Connect(doHorn)
flipBtn.MouseButton1Click:Connect(doFlip)
ctxBtn.MouseButton1Click:Connect(function()
	local act = ctxBtn:GetAttribute("Action")
	if act then
		ActionRE:FireServer(act)
	end
end)

UIS.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.E or kc == Enum.KeyCode.F then
		if S.car then
			doExit()
		end
	elseif kc == Enum.KeyCode.V then
		cycleCam()
	elseif kc == Enum.KeyCode.L then
		doLights()
	elseif kc == Enum.KeyCode.H then
		doHorn()
	elseif kc == Enum.KeyCode.R then
		doFlip()
	elseif kc == Enum.KeyCode.P then
		togglePhone()
	elseif kc == Enum.KeyCode.Space or kc == Enum.KeyCode.ButtonX then
		S.handbrake = true
	elseif kc == Enum.KeyCode.G and ctxBtn.Visible then
		local act = ctxBtn:GetAttribute("Action")
		if act then
			ActionRE:FireServer(act)
		end
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonX then
		S.handbrake = false
	end
end)

---------------------------------------------------------------- 구역 체크 (주유 / 수리 / 주차)
local function inZone(part, pos)
	local rel = part.CFrame:PointToObjectSpace(pos)
	return math.abs(rel.X) <= part.Size.X / 2 and math.abs(rel.Z) <= part.Size.Z / 2
end

local zoneT = 0
local function zoneCheck(dt)
	zoneT += dt
	if zoneT < 0.2 then
		return
	end
	local step = zoneT
	zoneT = 0
	if S.role ~= "driver" or not D then
		ctxBtn.Visible = false
		return
	end
	local zones = workspace:FindFirstChild("CityZones")
	if not zones then
		return
	end
	local pos = D.root.Position
	local slow = D.root.AssemblyLinearVelocity.Magnitude < 3
	local ctx
	local inSpace
	for _, z in ipairs(zones:GetChildren()) do
		if z.Name == "Pump" and slow and inZone(z, pos) then
			local need = math.ceil((100 - S.fuel) * Config.FUEL_PRICE)
			ctx = { "Refuel", "⛽ 주유하기 ₩" .. need .. (IS_TOUCH and "" or "  [G]") }
		elseif z.Name == "RepairPad" and slow and inZone(z, pos) then
			local hp = D.car:GetAttribute("Health") or 100
			ctx = { "Repair", "🔧 수리하기 ₩" .. math.ceil((100 - hp) * Config.REPAIR_PRICE) .. (IS_TOUCH and "" or "  [G]") }
		elseif z.Name == "ParkSpace" and inZone(z, pos) then
			local align = math.abs(D.root.CFrame.LookVector:Dot(z.CFrame.LookVector))
			if align > 0.95 then
				inSpace = z
			end
		end
	end
	if ctx then
		ctxBtn.Text = ctx[2]
		ctxBtn:SetAttribute("Action", ctx[1])
		ctxBtn.Visible = true
	else
		ctxBtn.Visible = false
	end
	-- 주차
	if inSpace and D.root.AssemblyLinearVelocity.Magnitude < 1 then
		S.parkT += step
		if S.parkT > 1.2 and S.parkedIdx ~= inSpace:GetAttribute("Index") then
			S.parkedIdx = inSpace:GetAttribute("Index")
			parkBanner.Visible = true
			ActionRE:FireServer("Parked", S.parkedIdx)
			task.delay(2.5, function()
				parkBanner.Visible = false
			end)
		end
	else
		S.parkT = 0
		if not inSpace then
			S.parkedIdx = nil
		end
	end
end

---------------------------------------------------------------- 메인 루프
local preSim = RunService.PreSimulation or RunService.Stepped
preSim:Connect(function(a, b)
	local dt = typeof(b) == "number" and b or a
	dt = math.min(dt, 0.05)
	physicsStep(dt)
	armPose()
end)

RunService.RenderStepped:Connect(function(dt)
	-- 좌석 이탈 감지 (사망 등)
	if S.car then
		local hum = getHum()
		if not hum or not hum.SeatPart or hum.SeatPart.Parent ~= S.car then
			if not hum or hum.Health <= 0 or not hum.SeatPart then
				leaveCar()
			end
		end
	end
	animateOthers(dt)
	updateCamera(dt)
	zoneCheck(dt)

	-- HUD + 계기판
	if D then
		local kmh = math.floor(math.abs(S.speed) * 1.008 + 0.5)
		speedLabel.Text = tostring(kmh)
		gearLabel.Text = S.gear
		fuelBar.Size = UDim2.fromScale(math.clamp(S.fuel / 100, 0, 1), 1)
		local hp = D.car:GetAttribute("Health") or 100
		hpBar.Size = UDim2.fromScale(math.clamp(hp / 100, 0, 1), 1)
		hpBar.BackgroundColor3 = hp > 50 and Color3.fromRGB(80, 220, 120) or (hp > 20 and Color3.fromRGB(240, 180, 40) or Color3.fromRGB(230, 60, 50))
		local cl = D.car:FindFirstChild("Cluster")
		local g = cl and cl:FindFirstChild("Gui")
		if g then
			local bg = g:FindFirstChildOfClass("Frame")
			if bg then
				bg.Speed.Text = tostring(kmh)
				bg.Gear.Text = S.gear
				bg.FuelBg.Fuel.Size = UDim2.fromScale(1, math.clamp(S.fuel / 100, 0, 1))
				bg.HpBg.Hp.Size = UDim2.fromScale(1, math.clamp(hp / 100, 0, 1))
			end
		end
	end

	-- 택시 상태 표시
	if S.taxiCar and S.taxiCar.Parent and S.taxiCar.PrimaryPart then
		local tp = S.taxiCar.PrimaryPart.Position
		taxiLabel.Visible = true
		if S.taxiState == "coming" then
			local _, c = getHum()
			local h = c and c:FindFirstChild("HumanoidRootPart")
			local d = h and math.floor((tp - h.Position).Magnitude * 0.28) or 0
			taxiLabel.Text = "🚕 택시가 오는 중 · " .. d .. "m"
		elseif S.taxiState == "waiting" then
			taxiLabel.Text = "🚕 도착! 오른쪽 뒷문에서 [E]"
		elseif S.taxiState == "riding" then
			if S.taxiLast then
				S.taxiOdo += (tp - S.taxiLast).Magnitude
			end
			S.taxiLast = tp
			local fare = math.floor(Config.TAXI_BASE + S.taxiOdo * Config.TAXI_PER_STUD)
			taxiLabel.Text = "🚕 → " .. tostring(S.taxiDest or "") .. " · ₩" .. fare
		elseif S.taxiState == "boarded" then
			taxiLabel.Text = "🚕 목적지를 선택하세요"
		else
			taxiLabel.Visible = false
		end
	else
		taxiLabel.Visible = false
	end
end)

plr.CharacterAdded:Connect(function()
	leaveCar()
end)

print("✅ CarClient 준비 완료")
