-- GwangalliBump (LocalScript, StarterPlayerScripts): the player's side of 어깨빵 (shoulder bumps) and
-- the pooled speech bubbles.
--   * HUD button "어깨빵" (own ScreenGui, kit colours) that appears when an NPC (street pedestrian /
--     key NPC) or another player stands within ~5 studs in front; also a double tap on an NPC.
--     Pressing it plays a shoulder lunge (GwangalliBumpShared.lungeCharacter) and fires the server.
--   * The server decides who falls (BumpEvent "hit" / "fall"): our own knockdown motion runs here
--     (PlatformStand + impulse + pose tweens + camera shake + a comic "퍽" bubble, then a get-up and
--     2 s of slow); pedestrians' motions are forwarded to GwangalliStreetLife through the
--     LocalPlayer.GwangalliStreetAPI BindableFunction it publishes; key NPCs fall from their NpcKnock
--     attribute (GwangalliNPCClient).
--   * Speech bubbles: GwangalliBumpShared.bubbles() (one pool per client, <= 10 visible, 40 studs);
--     other scripts call the same pool, or fire LocalPlayer.GwangalliBubble(adornee, text, typeId, dur).
-- Cost: one 6 Hz target scan (BindableFunction + <= 20 models), no per-frame work outside a bump.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local function optional(name: string, timeout: number?): any
	local m = ReplicatedStorage:FindFirstChild(name)
	if not m and timeout then
		m = ReplicatedStorage:WaitForChild(name, timeout)
	end
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
		warn("[GwangalliBump] " .. name .. " failed to load: " .. tostring(res))
	end
	return nil
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Shared = optional("GwangalliBumpShared", 30)
if not Shared then
	warn("[GwangalliBump] GwangalliBumpShared missing: 어깨빵 disabled")
	return
end
local Social = optional("GwangalliSocialShared", 10)
local Citizens = optional("GwangalliCitizens", 10)
local AnimLib = optional("GwangalliAnim", 5)
local K = optional("GwangalliUI", 5)
local Layout = optional("GwangalliLayout", 5)

local playerGui = player:WaitForChild("PlayerGui")

-------------------------------------------------------------------------------------------------
-- bubbles (shared pool) + the BindableEvent other scripts may fire
-------------------------------------------------------------------------------------------------
local bubbles = Shared.bubbles({ font = if K and K.Font and typeof(K.Font.medium) == "EnumItem" then K.Font.medium else Enum.Font.GothamMedium, types = Social and Social.TYPES })
do
	local ev = player:FindFirstChild(Shared.BUBBLE_EVENT)
	if not ev then
		ev = Instance.new("BindableEvent")
		ev.Name = Shared.BUBBLE_EVENT
		ev.Parent = player
	end
	(ev :: BindableEvent).Event:Connect(function(adornee, text, typeId, dur, offsetY)
		if bubbles then
			pcall(bubbles.say, bubbles, adornee, text, typeId, dur, offsetY)
		end
	end)
end

local function say(adornee: any, text: any, typeId: any, dur: any, offsetY: any)
	if bubbles and adornee then
		pcall(bubbles.say, bubbles, adornee, text, typeId, dur, offsetY)
	end
end

-------------------------------------------------------------------------------------------------
-- remotes + street life API
-------------------------------------------------------------------------------------------------
local action: RemoteEvent? = nil
local event: RemoteEvent? = nil
local streetApi: BindableFunction? = nil

local function street(method: string, ...: any): any
	local api = streetApi
	if not api or not api.Parent then
		api = player:FindFirstChild("GwangalliStreetAPI") :: any
		if api and api:IsA("BindableFunction") then
			streetApi = api
		else
			return nil
		end
	end
	local ok, res = pcall(function(...)
		return (api :: BindableFunction):Invoke(method, ...)
	end, ...)
	if ok then
		return res
	end
	return nil
end

local function character(): (Model?, Humanoid?, BasePart?)
	local c = player.Character
	if not c then
		return nil, nil, nil
	end
	local h = c:FindFirstChildOfClass("Humanoid")
	local r = c:FindFirstChild("HumanoidRootPart")
	if not h or not r or not r:IsA("BasePart") or h.Health <= 0 then
		return c, nil, nil
	end
	return c, h, r :: BasePart
end

local function headOf(model: Instance?): BasePart?
	if not model then
		return nil
	end
	local h = model:FindFirstChild("Head")
	if h and h:IsA("BasePart") then
		return h
	end
	local r = model:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local npcFolder: Folder? = nil
local function keyNpcModel(id: string): Model?
	if not npcFolder or not npcFolder.Parent then
		local f = workspace:FindFirstChild("GwangalliNPCs")
		npcFolder = if f and f:IsA("Folder") then f else nil
	end
	if not npcFolder then
		return nil
	end
	for _, m in npcFolder:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("NpcId") == id then
			return m
		end
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- UI: the 어깨빵 button
-------------------------------------------------------------------------------------------------
local C = {
	glass = Color3.fromRGB(15, 18, 31),
	text = Color3.fromRGB(245, 247, 251),
	sub = Color3.fromRGB(170, 177, 196),
	magenta = Color3.fromRGB(255, 79, 163),
	gold = Color3.fromRGB(255, 194, 71),
	line = Color3.new(1, 1, 1),
}
local FONT_BOLD, FONT_MED = Enum.Font.GothamBold, Enum.Font.GothamMedium
if K then
	pcall(function()
		local c = K.Color or {}
		C.glass = c.glass or C.glass
		C.text = c.text or C.text
		C.sub = c.sub or C.sub
		C.magenta = c.magenta or C.magenta
		C.gold = c.gold or C.gold
		local f = K.Font or {}
		if typeof(f.bold) == "EnumItem" then
			FONT_BOLD = f.bold
		end
		if typeof(f.medium) == "EnumItem" then
			FONT_MED = f.medium
		end
	end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "GwangalliBump"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 30
gui.Enabled = true
gui.Parent = playerGui

local BTN = if UserInputService.TouchEnabled then 64 else 56
local button = Instance.new("TextButton")
button.Name = "BumpButton"
button.AnchorPoint = Vector2.new(1, 1)
button.Size = UDim2.fromOffset(BTN, BTN)
button.Position = UDim2.new(1, -170, 1, -24)
button.BackgroundColor3 = C.glass
button.BackgroundTransparency = 0.14
button.AutoButtonColor = false
button.Text = ""
button.Visible = false
button.Active = true
button.Parent = gui
do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.magenta
	stroke.Transparency = 0.25
	stroke.Thickness = 1.5
	stroke.Parent = button
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.38)
	glyph.Size = UDim2.fromScale(0.6, 0.42)
	glyph.Font = FONT_BOLD
	glyph.TextScaled = true
	glyph.Text = "💥"
	glyph.TextColor3 = C.text
	glyph.Parent = button
	local cap = Instance.new("TextLabel")
	cap.Name = "Caption"
	cap.BackgroundTransparency = 1
	cap.AnchorPoint = Vector2.new(0.5, 1)
	cap.Position = UDim2.new(0.5, 0, 1, -5)
	cap.Size = UDim2.new(1, -4, 0, 14)
	cap.Font = FONT_BOLD
	cap.TextSize = 12
	cap.Text = "어깨빵"
	cap.TextColor3 = C.text
	cap.Parent = button
end
local targetLabel = Instance.new("TextLabel")
targetLabel.Name = "Target"
targetLabel.AnchorPoint = Vector2.new(1, 1)
targetLabel.Size = UDim2.fromOffset(BTN + 36, 16)
targetLabel.BackgroundTransparency = 1
targetLabel.Font = FONT_MED
targetLabel.TextSize = 11
targetLabel.TextColor3 = C.sub
targetLabel.TextXAlignment = Enum.TextXAlignment.Center
targetLabel.Text = ""
targetLabel.Visible = false
targetLabel.Parent = gui
if K and type(K.pressable) == "function" then
	pcall(K.pressable, button)
end

-- the button sits left of the HUD's right column (폰 / 이동 / 달리기), level with its bottom
local function layoutButton()
	local placed = false
	if Layout and type(Layout.slot) == "function" then
		local ok, pos, size, anchor = pcall(Layout.slot, "rightColumn")
		if ok and typeof(pos) == "UDim2" and typeof(size) == "UDim2" and size.X.Offset > 0 then
			local a = if typeof(anchor) == "Vector2" then anchor else Vector2.new(0.5, 1)
			local left = pos.X.Offset - size.X.Offset * a.X
			local bottom = pos.Y.Offset + size.Y.Offset * (1 - a.Y)
			button.Position = UDim2.fromOffset(left - 14, bottom)
			placed = true
		end
	end
	if not placed then
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(844, 390)
		local touch = UserInputService.TouchEnabled
		button.Position = UDim2.fromOffset(vp.X - (if touch then 200 else 110), vp.Y - (if touch then 28 else 24))
	end
	targetLabel.Position = button.Position - UDim2.fromOffset(-18, BTN + 2)
end
layoutButton()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		task.defer(layoutButton)
	end)
end

-- another full-screen UI (phone, bowling, dialog) asks the HUD layers to step aside
local function hudHidden(): boolean
	for _, g in playerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= gui and g.Enabled and g:GetAttribute("HideGwangalliHUD") == true then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- targeting (6 Hz)
-------------------------------------------------------------------------------------------------
type Target = { kind: string, id: any, name: string, typeId: string?, part: BasePart, pos: Vector3, d: number }
local target: Target? = nil
local lastBumpAt = -1e9

local function typeShort(typeId: string?): string
	local def = Social and Social.TYPES and Social.TYPES[typeId or "plain"]
	local s = def and def.short or ""
	return if s ~= "" then " · " .. s else ""
end

local function scan(): Target?
	local _, humanoid, root = character()
	if not humanoid or not root then
		return nil
	end
	if humanoid.Sit or humanoid.PlatformStand or (player.Character :: any):GetAttribute(Shared.Attr.Knocked) then
		return nil
	end
	-- working a shift, training at the gym or riding a taxi: no 어깨빵 (the server refuses it too)
	if player:GetAttribute("OnShift") or player:GetAttribute("GymBusy") or player:GetAttribute("InTaxi") then
		return nil
	end
	local pp = root.Position
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 1e-3 then
		return nil
	end
	look = look.Unit
	local best: Target? = nil
	local function consider(kind: string, id: any, name: string, typeId: string?, part: BasePart, pos: Vector3)
		local to = Vector3.new(pos.X - pp.X, 0, pos.Z - pp.Z)
		local d = to.Magnitude
		if d > Shared.RANGE or math.abs(pos.Y - pp.Y) > 5 then
			return
		end
		if d > 0.3 and look:Dot(to.Unit) < 0.3 then
			return
		end
		if not best or d < best.d then
			best = { kind = kind, id = id, name = name, typeId = typeId, part = part, pos = pos, d = d }
		end
	end
	-- street pedestrians (client-side; the street life script lists the close ones)
	local near = street("near", Shared.RANGE + 1)
	if type(near) == "table" then
		for _, e in near do
			if type(e) == "table" and typeof(e.root) == "Instance" and e.root:IsA("BasePart") and type(e.id) == "string" and not e.down then
				consider("npc", e.id, e.name or e.id, e.typeId, e.root, e.root.Position)
			end
		end
	end
	-- key NPCs
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if f then
		for _, m in f:GetChildren() do
			if m:IsA("Model") then
				local id = m:GetAttribute("NpcId")
				local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
				if type(id) == "string" and r and r:IsA("BasePart") and (r.Position - pp).Magnitude < Shared.RANGE + 2 then
					local c = Citizens and Citizens.byId[id]
					consider("npc", id, (c and c.name) or id, c and c.type, r, r.Position)
				end
			end
		end
	end
	-- other players (both must allow it)
	if player:GetAttribute(Shared.Attr.Enabled) ~= false then
		for _, other in Players:GetPlayers() do
			if other ~= player and other:GetAttribute(Shared.Attr.Enabled) ~= false then
				local ch = other.Character
				local r = ch and ch:FindFirstChild("HumanoidRootPart")
				if r and r:IsA("BasePart") and (r.Position - pp).Magnitude < Shared.RANGE + 2 then
					consider("player", other.UserId, other.DisplayName, nil, r, r.Position)
				end
			end
		end
	end
	return best
end

local function setTarget(t: Target?)
	target = t
	local show = t ~= nil and not hudHidden()
	if button.Visible ~= show then
		button.Visible = show
		targetLabel.Visible = show
		if show and K and type(K.pop) == "function" then
			pcall(K.pop, button)
		end
	end
	if t then
		targetLabel.Text = t.name .. typeShort(t.typeId)
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if t.kind == "player" then C.gold else C.magenta
		end
	end
end

-------------------------------------------------------------------------------------------------
-- bumping
-------------------------------------------------------------------------------------------------
local function cooldownLeft(): number
	return math.max(0, lastBumpAt + Shared.COOLDOWN - os.clock())
end

local function doBump(t: Target)
	if cooldownLeft() > 0 or not action then
		return
	end
	local ch, humanoid, root = character()
	if not ch or not humanoid or not root then
		return
	end
	lastBumpAt = os.clock()
	-- which shoulder: the target's side
	local rel = root.CFrame:PointToObjectSpace(t.pos)
	Shared.lungeCharacter(ch, rel.X >= 0)
	if K and type(K.feedback) == "function" then
		pcall(K.feedback, "tap")
	end
	local payload: any = { target = t.kind, id = t.id }
	if t.kind == "npc" then
		payload.pos = Shared.packV(t.pos)
	end
	if workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		print(string.format("[GwangalliBump:dbg] bump %s %s d=%.1f", t.kind, tostring(t.id), t.d))
	end
	action:FireServer("bump", payload)
	-- the button cools down visibly
	button.BackgroundTransparency = 0.55
	task.delay(Shared.COOLDOWN, function()
		button.BackgroundTransparency = 0.14
	end)
end

button.Activated:Connect(function()
	if target then
		doBump(target)
	end
end)

-- double tap on an NPC (touch)
local lastTapModel: Instance? = nil
local lastTapAt = -1e9
local function modelFromRay(pos: Vector2): Instance?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: any }
	local res = workspace:Raycast(ray.Origin, ray.Direction * 60, params)
	if not res or not res.Instance then
		return nil
	end
	local m: Instance? = res.Instance
	while m and m ~= workspace do
		if m:IsA("Model") and (m:GetAttribute("NpcId") ~= nil or m:GetAttribute("StreetId") ~= nil) then
			return m
		end
		m = m.Parent
	end
	return nil
end
UserInputService.TouchTap:Connect(function(positions, processed)
	if processed or type(positions) ~= "table" or #positions == 0 then
		return
	end
	local pos = positions[1]
	if typeof(pos) ~= "Vector2" then
		return
	end
	local m = modelFromRay(pos)
	local now = os.clock()
	if m and m == lastTapModel and now - lastTapAt < 0.45 then
		lastTapModel = nil
		local id = m:GetAttribute("NpcId") or m:GetAttribute("StreetId")
		local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
		local _, _, myRoot = character()
		if not myRoot or not r or not r:IsA("BasePart") or (r.Position - myRoot.Position).Magnitude > Shared.RANGE + 1.5 then
			return -- too far for a shoulder (the server would refuse it anyway)
		end
		if m:GetAttribute("StreetId") ~= nil then
			-- a pedestrian sitting / lying / already falling is no target
			for _, e in street("near", Shared.RANGE + 2) or {} do
				if type(e) == "table" and e.id == id and e.down then
					return
				end
			end
		end
		if type(id) == "string" and r and r:IsA("BasePart") then
			local c = Citizens and Citizens.byId[id]
			doBump({ kind = "npc", id = id, name = (c and c.name) or id, typeId = c and c.type, part = r, pos = r.Position, d = 0 })
		end
		return
	end
	lastTapModel = m
	lastTapAt = now
end)

-------------------------------------------------------------------------------------------------
-- server events
-------------------------------------------------------------------------------------------------
local function myHead(): BasePart?
	return headOf(player.Character)
end

local function onEvent(p: any)
	if type(p) ~= "table" then
		return
	end
	local kind = p.kind
	if kind == "hit" then
		local puk = if type(p.puk) == "string" then p.puk else "퍽!"
		if p.target == "npc" and type(p.id) == "string" then
			local handled = street("knock", p.id, p.dx, p.dz, p.outcome, puk)
			if not handled then
				-- a key NPC: its NpcKnock attribute plays the motion on every client; the comic word here
				local m = keyNpcModel(p.id)
				say(headOf(m), puk, "plain", 1.2, 3.2)
			end
		elseif p.target == "player" then
			local other = Players:GetPlayerByUserId(tonumber(p.id) or 0)
			say(headOf(other and other.Character), puk, "plain", 1.2, 3.2)
		end
		Shared.shakeCamera(0.12, 0.18)
		if K and type(K.feedback) == "function" then
			pcall(K.feedback, if p.outcome == "knockdown" then "success" else "tap")
		end
	elseif kind == "fall" then
		local function fall()
			local ch = player.Character
			if not ch then
				return
			end
			local outcome = if p.outcome == "knockdown" then "knockdown" else "stagger"
			local ok = Shared.knockCharacter(ch, tonumber(p.dx) or 0, tonumber(p.dz) or -1, outcome, { anim = AnimLib })
			if ok then
				say(myHead(), if type(p.puk) == "string" then p.puk else "퍽!", "plain", 1.3, 3.4)
				Shared.shakeCamera(if outcome == "knockdown" then Shared.SHAKE else 0.15, 0.4)
				if K and type(K.feedback) == "function" then
					pcall(K.feedback, "error")
				end
			end
			if type(p.by) == "string" and type(p.text) == "string" then
				task.delay(0.3, function()
					if not street("say", p.by, p.text, p.typeId, 3.5) then
						say(headOf(keyNpcModel(p.by)), p.text, p.typeId, 3.5)
					end
				end)
			end
		end
		if type(p.delay) == "number" and p.delay > 0 then
			task.delay(p.delay, fall)
		else
			fall()
		end
	elseif kind == "say" and type(p.id) == "string" and type(p.text) == "string" then
		if not street("say", p.id, p.text, p.typeId, p.dur or 3.5) then
			say(headOf(keyNpcModel(p.id)), p.text, p.typeId, p.dur or 3.5)
		end
	elseif kind == "leave" and type(p.id) == "string" then
		street("leave", p.id)
	elseif kind == "hint" then
		-- the phone owns the apps: open one when the phone published its BindableEvent (integration_todo)
		local ev = player:FindFirstChild("GwangalliPhoneOpen")
		if ev and ev:IsA("BindableEvent") then
			pcall(ev.Fire, ev, p.app, { dest = p.dest })
		end
	elseif kind == "miss" then
		-- shake the button a little (too far / not facing / cooldown)
		local ok = pcall(function()
			local t = TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 3, true), { Rotation = 6 })
			t:Play()
			t.Completed:Connect(function()
				button.Rotation = 0
			end)
		end)
		if not ok then
			button.Rotation = 0
		end
	end
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild(Shared.Folder, 60)
	if not folder then
		warn("[GwangalliBump] remotes folder missing: server module not running")
		return
	end
	local a = folder:WaitForChild(Shared.Remote.Action, 20)
	local e = folder:WaitForChild(Shared.Remote.Event, 20)
	if a and a:IsA("RemoteEvent") then
		action = a
	end
	if e and e:IsA("RemoteEvent") then
		event = e
		e.OnClientEvent:Connect(function(p)
			local ok, err = pcall(onEvent, p)
			if not ok then
				warn("[GwangalliBump] event failed: " .. tostring(err))
			end
		end)
	end
end)

-------------------------------------------------------------------------------------------------
-- the scan loop (6 Hz)
-------------------------------------------------------------------------------------------------
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 1 / 6 then
		return
	end
	acc = 0
	if not action then
		if button.Visible then
			setTarget(nil)
		end
		return
	end
	local ok, t = pcall(scan)
	setTarget(if ok then t else nil)
end)

player.CharacterAdded:Connect(function()
	setTarget(nil)
end)

local _ = event
