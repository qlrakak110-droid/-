-- GwangalliFight (LocalScript, StarterPlayerScripts; owner: npc): the player's side of 길거리 싸움
-- (contract: ReplicatedStorage.GwangalliFightShared; server: GwangalliGameplay/Fight).
--   * 👊 주먹 button (left of 어깨빵) / key F: appears when an NPC (street pedestrian or key NPC) stands
--     within FightShared.RANGE in front; a punch plays the lunge and asks the server.
--   * the server's answer plays here: the fall (stagger / knockdown) or the KO (down for good, then
--     taken away) through LocalPlayer.GwangalliStreetAPI, the HP bar + damage number over the head,
--     the line, and the reaction (fight back = a brawl, flee, phone report, an officer's arrest).
--   * "hurt" (a brawling NPC's swing landed): a red flash; "down": citizens in hospital are not spawned.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FS = require(ReplicatedStorage:WaitForChild("GwangalliFightShared"))
local Bump: any = nil
do
	local m = ReplicatedStorage:FindFirstChild("GwangalliBumpShared")
	if m then
		local ok, res = pcall(require, m)
		Bump = if ok then res else nil
	end
end

local action: RemoteEvent? = nil
local streetApi: BindableFunction? = nil

local function street(method: string, ...: any): any
	local api = streetApi
	if not api or not api.Parent then
		local a = player:FindFirstChild("GwangalliStreetAPI")
		if a and a:IsA("BindableFunction") then
			streetApi = a
			api = a
		else
			return nil
		end
	end
	local ok, res = pcall(function(...)
		return (api :: BindableFunction):Invoke(method, ...)
	end, ...)
	return if ok then res else nil
end

local function character(): (Model?, Humanoid?, BasePart?)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if hum and root and root:IsA("BasePart") and hum.Health > 0 then
		return ch, hum, root
	end
	return nil, nil, nil
end

local function keyModel(id: string): Model?
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if not f then
		return nil
	end
	for _, m in f:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("NpcId") == id then
			return m
		end
	end
	return nil
end

local function bubble(adornee: Instance?, text: string?, dur: number?)
	if not adornee or not text then
		return
	end
	local ev = player:FindFirstChild((Bump and Bump.BUBBLE_EVENT) or "GwangalliBubble")
	if ev and ev:IsA("BindableEvent") then
		ev:Fire(adornee, text, "plain", dur or 3, 3.2)
	end
end

-------------------------------------------------------------------------------------------------
-- UI: the 👊 button
-------------------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "GwangalliFight"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 30
gui.Parent = playerGui

local BTN = if UserInputService.TouchEnabled then 64 else 56
local button = Instance.new("TextButton")
button.Name = "PunchButton"
button.AnchorPoint = Vector2.new(1, 1)
button.Size = UDim2.fromOffset(BTN, BTN)
button.Position = UDim2.new(1, -240, 1, -24)
button.BackgroundColor3 = Color3.fromRGB(15, 18, 31)
button.BackgroundTransparency = 0.14
button.AutoButtonColor = false
button.Text = ""
button.Visible = false
button.Parent = gui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 18)
	c.Parent = button
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(255, 120, 60)
	st.Thickness = 1.5
	st.Transparency = 0.2
	st.Parent = button
	local g = Instance.new("TextLabel")
	g.BackgroundTransparency = 1
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromScale(0.5, 0.38)
	g.Size = UDim2.fromScale(0.6, 0.42)
	g.Font = Enum.Font.GothamBold
	g.TextScaled = true
	g.Text = "👊"
	g.TextColor3 = Color3.new(1, 1, 1)
	g.Parent = button
	local cap = Instance.new("TextLabel")
	cap.BackgroundTransparency = 1
	cap.AnchorPoint = Vector2.new(0.5, 1)
	cap.Position = UDim2.new(0.5, 0, 1, -5)
	cap.Size = UDim2.new(1, -4, 0, 14)
	cap.Font = Enum.Font.GothamBold
	cap.TextSize = 12
	cap.Text = if UserInputService.KeyboardEnabled then "주먹 (F)" else "주먹"
	cap.TextColor3 = Color3.new(1, 1, 1)
	cap.Parent = button
end

-- red flash when a swing lands on us
local flash = Instance.new("Frame")
flash.Name = "Hurt"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(200, 20, 30)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 0
flash.Parent = gui

-- left of the 어깨빵 button (GwangalliBump), or bottom right
local function layout()
	local bg = playerGui:FindFirstChild("GwangalliBump")
	local bb = bg and bg:FindFirstChild("BumpButton")
	if bb and bb:IsA("GuiObject") then
		button.AnchorPoint = bb.AnchorPoint
		button.Position = bb.Position - UDim2.fromOffset(BTN + 12, 0)
	end
end
task.spawn(function()
	for _ = 1, 20 do
		layout()
		task.wait(1)
	end
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		task.delay(0.1, layout)
	end)
end

-------------------------------------------------------------------------------------------------
-- HP bars over heads
-------------------------------------------------------------------------------------------------
type Bar = { gui: BillboardGui, fill: Frame, num: TextLabel, untilT: number }
local bars: { [string]: Bar } = {}

local function showBar(id: string, adornee: BasePart?, hp: number, max: number, dmg: number, crit: boolean)
	if not adornee then
		return
	end
	local b = bars[id]
	if not b or not b.gui.Parent then
		local bg = Instance.new("BillboardGui")
		bg.Name = "FightHP_" .. id
		bg.Size = UDim2.fromOffset(84, 30)
		bg.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
		bg.AlwaysOnTop = true
		bg.MaxDistance = 80
		bg.LightInfluence = 0
		local back = Instance.new("Frame")
		back.AnchorPoint = Vector2.new(0.5, 1)
		back.Position = UDim2.new(0.5, 0, 1, 0)
		back.Size = UDim2.new(1, 0, 0, 8)
		back.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
		back.BorderSizePixel = 0
		back.Parent = bg
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = back
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(80, 220, 110)
		fill.BorderSizePixel = 0
		fill.Parent = back
		local c2 = Instance.new("UICorner")
		c2.CornerRadius = UDim.new(0, 4)
		c2.Parent = fill
		local num = Instance.new("TextLabel")
		num.BackgroundTransparency = 1
		num.Size = UDim2.new(1, 0, 0, 20)
		num.Font = Enum.Font.GothamBlack
		num.TextSize = 18
		num.TextStrokeTransparency = 0.3
		num.TextColor3 = Color3.fromRGB(255, 230, 90)
		num.Parent = bg
		bg.Parent = playerGui
		b = { gui = bg, fill = fill, num = num, untilT = 0 }
		bars[id] = b
	end
	b.gui.Adornee = adornee
	local k = math.clamp(hp / math.max(1, max), 0, 1)
	b.fill.Size = UDim2.fromScale(k, 1)
	b.fill.BackgroundColor3 = if k > 0.5 then Color3.fromRGB(80, 220, 110) elseif k > 0.25 then Color3.fromRGB(255, 190, 60) else Color3.fromRGB(240, 70, 60)
	b.num.Text = (if crit then "치명타! " else "") .. "-" .. tostring(dmg)
	b.num.TextColor3 = if crit then Color3.fromRGB(255, 90, 60) else Color3.fromRGB(255, 230, 90)
	b.untilT = os.clock() + 3.5
end

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for id, b in bars do
		if t > b.untilT or not b.gui.Adornee or not b.gui.Adornee.Parent then
			b.gui:Destroy()
			bars[id] = nil
		end
	end
end)

-------------------------------------------------------------------------------------------------
-- target + punch
-------------------------------------------------------------------------------------------------
type Target = { kind: string, id: string, root: BasePart, pos: Vector3, ptype: string?, d: number }
local target: Target? = nil
local lastPunch = 0

local function scan(): Target?
	local _, hum, root = character()
	if not hum or not root or hum.Sit or hum.PlatformStand then
		return nil
	end
	if player:GetAttribute("OnShift") or player:GetAttribute("InTaxi") or player:GetAttribute("LawCuffed") then
		return nil
	end
	local pp = root.Position
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 1e-3 then
		return nil
	end
	look = look.Unit
	local best: Target? = nil
	local function consider(kind: string, id: string, r: BasePart, ptype: string?)
		local pos = r.Position
		local to = Vector3.new(pos.X - pp.X, 0, pos.Z - pp.Z)
		local d = to.Magnitude
		if d > FS.RANGE or math.abs(pos.Y - pp.Y) > 5 then
			return
		end
		if d > 0.4 and look:Dot(to.Unit) < 0.25 then
			return
		end
		if not best or d < best.d then
			best = { kind = kind, id = id, root = r, pos = pos, ptype = ptype, d = d }
		end
	end
	local near = street("near", FS.RANGE + 1)
	if type(near) == "table" then
		for _, e in near do
			if type(e) == "table" and type(e.id) == "string" and typeof(e.root) == "Instance" and e.root:IsA("BasePart") and not e.down then
				consider("ped", e.id, e.root, e.typeId)
			end
		end
	end
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if f then
		for _, m in f:GetChildren() do
			if m:IsA("Model") then
				local id = m:GetAttribute("NpcId")
				local kind = m:GetAttribute("NpcKind")
				local r = m:FindFirstChild("HumanoidRootPart")
				-- (Law officers / actors and shop customers are not key NPCs; officers are Law's)
				if type(id) == "string" and (kind == "key" or kind == "street") and r and r:IsA("BasePart") and (r.Position - pp).Magnitude < FS.RANGE + 2 then
					consider("npc", id, r, nil)
				end
			end
		end
	end
	return best
end

local function punch()
	local t = target
	if not t or not action or os.clock() - lastPunch < FS.COOLDOWN then
		return
	end
	local ch, _, root = character()
	if not ch or not root then
		return
	end
	lastPunch = os.clock()
	if Bump and Bump.lungeCharacter then
		local rel = root.CFrame:PointToObjectSpace(t.pos)
		pcall(Bump.lungeCharacter, ch, rel.X >= 0)
	end
	local p = t.root.Position
	action:FireServer("punch", { kind = t.kind, id = t.id, pos = { p.X, p.Y, p.Z }, ptype = t.ptype })
	button.BackgroundTransparency = 0.55
	task.delay(FS.COOLDOWN, function()
		button.BackgroundTransparency = 0.14
	end)
end

button.Activated:Connect(punch)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.F then
		punch()
	end
end)

-------------------------------------------------------------------------------------------------
-- server answers
-------------------------------------------------------------------------------------------------
local function onEvent(p: any)
	if type(p) ~= "table" then
		return
	end
	if p.kind == "hit" and type(p.id) == "string" then
		local dx, dz = tonumber(p.dx) or 0, tonumber(p.dz) or -1
		local adornee: BasePart? = nil
		if p.target == "ped" then
			if p.outcome == "ko" then
				street("ko", p.id, dx, dz, p.ko or FS.KO_DOWN)
			else
				street("knock", p.id, dx, dz, p.outcome, if p.crit then "퍽!!" else "퍽!")
			end
			local near = street("near", 12)
			if type(near) == "table" then
				for _, e in near do
					if type(e) == "table" and e.id == p.id and typeof(e.root) == "Instance" then
						adornee = e.root
					end
				end
			end
			if type(p.line) == "string" then
				task.delay(0.35, function()
					street("say", p.id, p.line, nil, 3)
				end)
			end
			if p.react == "fight" then
				street("brawl", p.id, FS.BRAWL_S[1] + math.random() * (FS.BRAWL_S[2] - FS.BRAWL_S[1]))
			elseif p.react == "flee" or p.react == "report" or p.react == "arrest" then
				street("react", p.id, p.react)
			end
		else
			local m = keyModel(p.id)
			local head = m and m:FindFirstChild("Head")
			adornee = m and m:FindFirstChild("HumanoidRootPart") :: BasePart?
			bubble(head, p.line, 3)
		end
		showBar(p.id, adornee, tonumber(p.hp) or 0, tonumber(p.max) or 100, tonumber(p.dmg) or 0, p.crit == true)
		if Bump and Bump.shakeCamera then
			pcall(Bump.shakeCamera, if p.crit or p.outcome == "ko" then 0.3 else 0.12, 0.2)
		end
	elseif p.kind == "hurt" then
		flash.BackgroundTransparency = 0.55
		TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	elseif p.kind == "down" then
		street("hospital", p.ids)
	end
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild(FS.Folder, 60)
	if not folder then
		return
	end
	local a = folder:WaitForChild(FS.Remote.Action, 20)
	local e = folder:WaitForChild(FS.Remote.Event, 20)
	if a and a:IsA("RemoteEvent") then
		action = a
	end
	if e and e:IsA("RemoteEvent") then
		e.OnClientEvent:Connect(function(p)
			local ok, err = pcall(onEvent, p)
			if not ok then
				warn("[GwangalliFight] " .. tostring(err))
			end
		end)
	end
end)

-- 6 Hz target scan
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 1 / 6 then
		return
	end
	acc = 0
	local ok, t = pcall(scan)
	target = if ok then t else nil
	local show = target ~= nil
	if button.Visible ~= show then
		button.Visible = show
		if show then
			layout()
		end
	end
end)

-- debug hook (tests): LocalPlayer.GwangalliFightAPI:Invoke("punch") punches the current target
local api = Instance.new("BindableFunction")
api.Name = "GwangalliFightAPI"
api.OnInvoke = function(op: string)
	if workspace:GetAttribute("GwangalliStreetLifeDebug") ~= true then
		return nil
	end
	if op == "target" then
		local t = scan()
		return t and { id = t.id, kind = t.kind, d = t.d } or nil
	elseif op == "punch" then
		target = scan()
		lastPunch = 0
		punch()
		return target and target.id or nil
	end
	return nil
end
api.Parent = player

