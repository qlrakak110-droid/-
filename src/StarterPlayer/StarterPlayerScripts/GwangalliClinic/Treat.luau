-- GwangalliClinic/Treat (client): 처치.
--   진찰대 주사 (Health's own treat / vitamin op runs the seated nurse choreography, the fee and the cure on
--   the server): our overlay adds the patient's side — 힘 빼기 timing bar → "따끔!" (tiny camera shake) →
--   5초 꾹 누르기. 예방접종 uses the same overlay.
--   주사실 수액: lying on the bed (server), progress ring with the drip, "😴 눈 붙이기" (faster, screen dims) /
--   "그만 맞기", drip particles at the bed's IV bag (local prop).
--   혈압 커프: Treat.cuff(on) / Treat.cuffInflate(frac) — a local cuff on the upper arm (진료실 혈압 측정).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Treat = {}

local ctx: any
local S: any
local C: any
local Ui: any
local Col: any
local F: any
local player = Players.LocalPlayer

local overlay: Frame
local ivCard: Frame
local ivBar: any
local ivText: TextLabel
local ivBtns: Frame
local dim: Frame
local drip: Part? = nil
local injectToken = 0
local ivLocal = { progress = 0, seconds = 1, speed = 1, last = 0 }
local napping = false

local function shake()
	local cam = workspace.CurrentCamera
	if not cam or cam.CameraType == Enum.CameraType.Scriptable then
		return
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	task.spawn(function()
		for i = 1, 6 do
			hum.CameraOffset = Vector3.new((math.random() - 0.5) * 0.25, (math.random() - 0.5) * 0.2, 0)
			task.wait(0.03)
			local _ = i
		end
		hum.CameraOffset = Vector3.zero
	end)
end

local function clearOverlay()
	for _, c in overlay:GetChildren() do
		if not c:IsA("UICorner") and not c:IsA("UIStroke") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

-------------------------------------------------------------------------------------------------
-- injection overlay
-------------------------------------------------------------------------------------------------
local function injection(vaccine: boolean)
	injectToken += 1
	local token = injectToken
	clearOverlay()
	overlay.Visible = true
	local function alive(): boolean
		local v = ctx.visit
		return token == injectToken and v ~= nil and v.step == "treat"
	end
	Ui.text(overlay, { Text = if vaccine then "💉 예방접종 · 간호사 박선생" else "💉 주사 · 간호사 박선생", Font = F.black, TextSize = 16, TextColor3 = Col.tealDD, Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	local tip = Ui.text(overlay, { Text = "초록색에 바늘이 오면 '힘 빼기'!", Font = F.med, TextSize = 13, TextColor3 = Col.sub, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
	local track = Ui.new("Frame", { BackgroundColor3 = Color3.fromRGB(232, 238, 239), Position = UDim2.new(0.08, 0, 0, 52), Size = UDim2.new(0.84, 0, 0, 18) }, overlay)
	Ui.corner(track, 9)
	local zone = Ui.new("Frame", { BackgroundColor3 = Col.green, Position = UDim2.fromScale(0.58, 0), Size = UDim2.fromScale(0.2, 1) }, track)
	Ui.corner(zone, 9)
	local needle = Ui.new("Frame", { BackgroundColor3 = Col.ink, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(6, 28) }, track)
	Ui.corner(needle, 3)
	local pressed = false
	local btn = Ui.btn(overlay, { text = "😮‍💨 힘 빼기" .. Ui.actionHint(), style = "primary", size = UDim2.new(0.84, 0, 0, 52), pos = UDim2.new(0.5, 0, 1, -4), anchor = Vector2.new(0.5, 1), textSize = 17, onClick = function()
		pressed = true
	end })
	local keyConn = UserInputService.InputBegan:Connect(function(io, gp)
		if not Ui.typing() and Ui.isActionKey(io.KeyCode) then
			pressed = true
		end
	end)
	Ui.select(btn)
	task.spawn(function()
		local t0 = os.clock()
		local hit = false
		while alive() and not pressed do
			local x = (math.sin((os.clock() - t0) * 2.6 - math.pi / 2) + 1) / 2
			needle.Position = UDim2.fromScale(x, 0.5)
			task.wait()
		end
		keyConn:Disconnect()
		if not alive() then
			return
		end
		local x = needle.Position.X.Scale
		hit = x >= 0.56 and x <= 0.8
		Ui.sound("tap", 0.6)
		shake()
		tip.Text = if hit then "따끔! … 생각보다 안 아파요 👍" else "따끔!! 아앗… 다음엔 힘을 더 빼 봐요"
		btn.Text = "꾹 누르는 중…"
		Ui.restyle(btn, "secondary")
		task.wait(1.4)
		if not alive() then
			return
		end
		tip.Text = S.Medical.line("nurse_press")
		local bar = Ui.bar(overlay, { h = 10 })
		bar.frame.Position = UDim2.new(0.08, 0, 0, 80)
		bar.frame.Size = UDim2.new(0.84, 0, 0, 10)
		local t1 = os.clock()
		while alive() and os.clock() - t1 < 2.4 do
			bar.set((os.clock() - t1) / 2.4)
			task.wait()
		end
		if token == injectToken then
			btn.Text = "잘 참으셨어요!"
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- 혈압 커프 (진료실 혈압 측정: a local cuff on the patient's upper arm that inflates with the pump)
-------------------------------------------------------------------------------------------------
local cuffPart: Part? = nil
local cuffBase: Vector3 = Vector3.one

function Treat.cuff(on: boolean)
	if cuffPart then
		cuffPart:Destroy()
		cuffPart = nil
	end
	if not on then
		return
	end
	local ch = player.Character
	local arm = ch and (ch:FindFirstChild("LeftUpperArm") or ch:FindFirstChild("Left Arm"))
	if not arm or not arm:IsA("BasePart") then
		return
	end
	local p = Instance.new("Part")
	p.Name = "BPCuff"
	cuffBase = Vector3.new(arm.Size.X + 0.12, math.min(0.7, arm.Size.Y * 0.55), arm.Size.Z + 0.12)
	p.Size = cuffBase
	p.Color = Color3.fromRGB(28, 44, 82)
	p.Material = Enum.Material.Fabric
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = arm.CFrame * CFrame.new(0, arm.Size.Y * 0.18, 0)
	local strip = Instance.new("Part")
	strip.Name = "Velcro"
	strip.Size = Vector3.new(0.06, cuffBase.Y * 0.9, 0.3)
	strip.Color = Color3.fromRGB(210, 214, 220)
	strip.Material = Enum.Material.SmoothPlastic
	strip.CanCollide = false
	strip.CanTouch = false
	strip.CanQuery = false
	strip.Massless = true
	strip.CFrame = p.CFrame * CFrame.new(-cuffBase.X / 2 - 0.02, 0, 0)
	local w = Instance.new("WeldConstraint")
	w.Part0 = arm
	w.Part1 = p
	w.Parent = p
	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = p
	w2.Part1 = strip
	w2.Parent = strip
	strip.Parent = p
	p.Parent = ctx.Tracker.localFolder()
	cuffPart = p
end

-- frac 0..1 = how far the cuff is pumped up
function Treat.cuffInflate(frac: number)
	local p = cuffPart
	if not p then
		return
	end
	local a = math.clamp(frac, 0, 1)
	Ui.tween(p, 0.15, { Size = cuffBase + Vector3.new(0.22 * a, 0.04 * a, 0.22 * a) })
end

-------------------------------------------------------------------------------------------------
-- IV
-------------------------------------------------------------------------------------------------
local function setDrip(v: any?)
	if drip then
		drip:Destroy()
		drip = nil
	end
	if not v or not v.iv or not v.iv.bag then
		return
	end
	local spec = S.Sites.PARTS[v.iv.bag]
	if not spec then
		return
	end
	local p = Instance.new("Part")
	p.Name = "IVDrip"
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	-- the real bag when it is streamed in (the drip falls from its bottom), else the surveyed position
	local bag = ctx.mapPart(spec.path)
	local top = if bag then bag.Position - Vector3.new(0, bag.Size.Y / 2 + 0.05, 0) else spec.fallback + Vector3.new(0, -0.55, 0)
	p.CFrame = CFrame.new(top)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(200, 240, 255))
	pe.Size = NumberSequence.new(0.07)
	pe.Lifetime = NumberRange.new(0.5, 0.6)
	pe.Speed = NumberRange.new(2.2)
	pe.SpreadAngle = Vector2.new(0, 0)
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.Acceleration = Vector3.new(0, -6, 0)
	pe.Rate = 2.5
	pe.LightEmission = 0.4
	pe.Parent = p
	p.Parent = ctx.Tracker.localFolder()
	drip = p
end

local function setNap(on: boolean)
	napping = on
	Ui.tween(dim, 0.8, { BackgroundTransparency = if on then 0.25 else 1 })
	dim.Visible = true
	if not on then
		task.delay(0.85, function()
			if not napping then
				dim.Visible = false
			end
		end)
	end
end

local function showIV(v: any)
	ivCard.Visible = true
	for _, c in ivBtns:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	Ui.btn(ivBtns, { text = "😴 눈 붙이기", style = "secondary", size = UDim2.new(0.5, -4, 1, 0), textSize = 14, onClick = function()
		local res = ctx.call("treat", { action = "nap" })
		if res.ok then
			setNap(true)
			Ui.say("nurse2", "주무셔도 돼요. 다 들어가면 깨워 드릴게요~", { name = C.Staff.nurse2.name })
		end
	end })
	Ui.btn(ivBtns, { text = "그만 맞기", style = "ghost", size = UDim2.new(0.5, -4, 1, 0), pos = UDim2.new(0.5, 4, 0, 0), textSize = 14, onClick = function()
		local pick = Ui.ask("nurse2", "아직 수액이 남았는데 그만 맞으실래요? 들어간 만큼만 효과가 있어요.", { "계속 맞을게요", "그만할게요" }, { name = C.Staff.nurse2.name })
		if pick == 2 then
			ctx.call("treat", { action = "stop" })
		else
			Ui.hideDialog()
		end
	end })
	ivLocal.progress = v.iv.progress or 0
	ivLocal.seconds = v.iv.seconds or 30
	ivLocal.speed = v.iv.speed or 1
	setDrip(v)
end

local function hideIV()
	ivCard.Visible = false
	setDrip(nil)
	if napping then
		setNap(false)
	end
end

function Treat.start()
	local v = ctx.visit
	if not v then
		return
	end
	if v.step == "iv_go" then
		Treat.startIV()
		return
	end
	local res = ctx.call("treat", { action = "start" })
	if res.ok and res.fee then
		Ui.toast(string.format("진료비 %s 결제됐어요", S.won(res.fee)), "처치비는 Health 진료비로 바로 결제돼요 (통장 → 현금)", "info")
	end
end

function Treat.startIV()
	ctx.call("treat", { action = "start" })
end

function Treat.onVisit(v: any, prev: any)
	local step = v and v.step
	local prevStep = prev and prev.step
	if step == "treat" and prevStep ~= "treat" then
		injection(v.plan and v.plan.vaccine == true)
	elseif step ~= "treat" then
		injectToken += 1
		overlay.Visible = false
	end
	if step == "iv" and v.iv then
		if prevStep ~= "iv" then
			showIV(v)
		else
			ivLocal.progress = v.iv.progress or ivLocal.progress
			ivLocal.speed = v.iv.speed or ivLocal.speed
		end
	elseif prevStep == "iv" or ivCard.Visible then
		hideIV()
	end
end

function Treat.init(c: any)
	ctx = c
	S = c.S
	C = c.C
	Ui = c.Ui
	Col = Ui.C
	F = Ui.F
	overlay = Ui.new("Frame", { Name = "Inject", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -196), Size = UDim2.fromOffset(420, 160), BackgroundColor3 = Col.white, Visible = false, ZIndex = 30, Active = true }, Ui.gui)
	Ui.corner(overlay, 16)
	Ui.stroke(overlay, Col.teal, 1.5, 0.2)
	Ui.pad(overlay, 12, 10, 12, 10)
	dim = Ui.new("Frame", { Name = "NapDim", BackgroundColor3 = Color3.fromRGB(4, 10, 16), BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 80), Position = UDim2.fromOffset(0, -60), Visible = false, ZIndex = 5 }, Ui.gui)
	Ui.text(dim, { Text = "Zzz…", Font = F.black, TextSize = 40, TextColor3 = Color3.fromRGB(180, 220, 230), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(200, 60), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	ivCard = Ui.card(Ui.gui, { Name = "IV", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(420, 0), Visible = false, ZIndex = 31 })
	Ui.pad(ivCard, 14, 10, 14, 12)
	Ui.list(ivCard, "v", 8)
	Ui.text(ivCard, { Text = "💧 수액 맞는 중 · 간호사 최선생", Font = F.black, TextSize = 15, TextColor3 = Col.tealDD, LayoutOrder = 1, ZIndex = 32 })
	ivBar = Ui.bar(ivCard, { h = 14, order = 2 })
	ivText = Ui.text(ivCard, { Text = "", Font = F.med, TextSize = 13, TextColor3 = Col.sub, LayoutOrder = 3, ZIndex = 32 })
	ivBtns = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 4 }, ivCard)
	Ui.onLayout(function()
		local W = Ui.size()
		overlay.Size = UDim2.fromOffset(math.min(420, W - 24), 160)
		Ui.placeBottom(overlay, 420, 196)
		ivCard.Size = UDim2.fromOffset(math.min(420, W - 24), 0)
		Ui.placeBottom(ivCard, 420, 24)
	end)
	RunService.Heartbeat:Connect(function(dt)
		if not ivCard.Visible then
			return
		end
		ivLocal.progress = math.min(ivLocal.seconds, ivLocal.progress + dt * ivLocal.speed)
		local a = ivLocal.progress / math.max(1, ivLocal.seconds)
		ivBar.set(a)
		local left = math.max(0, (ivLocal.seconds - ivLocal.progress) / math.max(0.1, ivLocal.speed))
		ivText.Text = string.format("%d%% · 남은 시간 약 %d초%s", math.floor(a * 100), math.ceil(left), if ivLocal.speed > 1 then " · 😴 자는 중" else "")
	end)
	local _ = player
end

return Treat
