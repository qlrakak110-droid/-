-- GwangalliHealth/Effects: what being ill looks like on this client, plus the cure celebration.
--   * grade: ONE ColorCorrectionEffect ("GwangalliHealthGrade") in Lighting, tweened to a soft
--     desaturated / cool look while ill and disabled otherwise (DayNight keeps its own effect: it caches
--     the first ColorCorrectionEffect, created by the build, so ours never collides with it)
--   * vignette: four thin edge frames with gradient alpha in a low-DisplayOrder ScreenGui (7 % of the
--     screen per edge: cheap, never over the HUD, well under the mobile coverage budget)
--   * cough / shiver: every 14-22 s a short GwangalliAnim procedural emote on the local character
--     (facepalm = hand to the mouth, shake = shiver); RenderStepped is bound only while the emote plays
--   * sparkles + "완치!" pop on the cured / vitamin events (ParticleEmitter with the client's built-in
--     sparkle texture, Emit once; no per-frame work)
-- Driven by the character attribute GwIll (server) and the HealthEvent kinds ill / cured / vitamin / collapse.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Effects = {}

local ctx: any
local K: any
local HS: any
local Anim: any
local ill = false
local grade: ColorCorrectionEffect? = nil
local vignette: ScreenGui? = nil
local edges: { Frame } = {}
local coughSerial = 0
local stepConn: RBXScriptConnection? = nil
local charConns: { RBXScriptConnection } = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-------------------------------------------------------------------------------------------------
-- Grade + vignette
-------------------------------------------------------------------------------------------------
local function ensureGrade(): ColorCorrectionEffect
	if grade and grade.Parent then
		return grade
	end
	local g = Lighting:FindFirstChild("GwangalliHealthGrade")
	if not g or not g:IsA("ColorCorrectionEffect") then
		g = Instance.new("ColorCorrectionEffect")
		g.Name = "GwangalliHealthGrade"
		g.Enabled = false
		g.Saturation = 0
		g.Contrast = 0
		g.Brightness = 0
		g.TintColor = Color3.new(1, 1, 1)
		g.Parent = Lighting
	end
	grade = g :: ColorCorrectionEffect
	return grade :: ColorCorrectionEffect
end

local function ensureVignette(): ScreenGui
	if vignette and vignette.Parent then
		return vignette
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "GwangalliHealthVignette"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 5
	sg.Enabled = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local col = Color3.fromRGB(18, 22, 40)
	local T = 0.05 -- edge thickness (fraction of the screen; 4 edges ~19 % of a portrait phone, under the 35 % walking budget with the HUD)
	local function edge(name: string, pos: UDim2, size: UDim2, rot: number)
		local f = K.frame(sg, { Name = name, Position = pos, Size = size, BackgroundTransparency = 1, BackgroundColor3 = col, Active = false, ZIndex = 1 })
		-- alpha fades from the screen edge (0) toward the inside (1)
		K.gradient(f, { col, col }, rot, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }))
		table.insert(edges, f)
	end
	edge("Top", UDim2.fromScale(0, 0), UDim2.fromScale(1, T), 90)
	edge("Bottom", UDim2.fromScale(0, 1 - T), UDim2.fromScale(1, T), -90)
	edge("Left", UDim2.fromScale(0, 0), UDim2.fromScale(T, 1), 0)
	edge("Right", UDim2.fromScale(1 - T, 0), UDim2.fromScale(T, 1), 180)
	sg.Parent = ctx.playerGui
	vignette = sg
	return sg
end

local function setGrade(on: boolean, strong: boolean?)
	local g = ensureGrade()
	local info = TweenInfo.new(if on then 1.2 else 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if on then
		g.Enabled = true
		local goal = if strong
			then { Saturation = -0.7, Contrast = 0.12, Brightness = -0.08, TintColor = Color3.fromRGB(222, 228, 245) }
			else { Saturation = -0.35, Contrast = 0.05, Brightness = -0.02, TintColor = Color3.fromRGB(236, 240, 250) }
		pcall(function()
			TweenService:Create(g, info, goal):Play()
		end)
	else
		local ok = pcall(function()
			local t = TweenService:Create(g, info, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.new(1, 1, 1) })
			t:Play()
			t.Completed:Connect(function()
				if not ill and grade then
					(grade :: ColorCorrectionEffect).Enabled = false
				end
			end)
		end)
		if not ok then
			g.Saturation = 0
			g.Contrast = 0
			g.Brightness = 0
			g.TintColor = Color3.new(1, 1, 1)
			g.Enabled = false
		end
	end
	local sg = ensureVignette()
	if on then
		sg.Enabled = true
		for _, f in edges do
			K.tween(f, 1.0, { BackgroundTransparency = if strong then 0.25 else 0.45 })
		end
	else
		for _, f in edges do
			K.tween(f, 0.6, { BackgroundTransparency = 1 })
		end
		task.delay(0.65, function()
			if not ill and vignette then
				(vignette :: ScreenGui).Enabled = false
			end
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- Cough / shiver emotes (GwangalliAnim procedural one-shots on the local character)
-------------------------------------------------------------------------------------------------
local function stopStep()
	if stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

local function emote(name: string): number
	local character = ctx.player.Character
	if not Anim or not character or not character.Parent then
		return 0
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid.Sit or humanoid.PlatformStand then
		return 0
	end
	local ok, ctl = pcall(Anim.rig, character)
	if not ok or not ctl then
		return 0
	end
	local dur = 0
	local ok2, d = pcall(ctl.emote, ctl, name)
	if ok2 and type(d) == "number" then
		dur = d
	end
	if dur <= 0 then
		return 0
	end
	stopStep()
	local untilT = os.clock() + dur + 0.6
	stepConn = RunService.RenderStepped:Connect(function()
		local okS = pcall(ctl.step, ctl)
		if not okS or os.clock() > untilT then
			stopStep()
			pcall(ctl.relax, ctl)
		end
	end)
	return dur
end

local function coughLoop(serial: number)
	local rng = Random.new()
	local every = HS.H().coughEvery or { 14, 22 }
	task.wait(rng:NextNumber(3, 6))
	while ill and coughSerial == serial do
		local kindId = ctx.player:GetAttribute(ctx.G.Attr.Illness)
		local kind = HS.kind(kindId)
		local which = if kind and kind.emote == "shiver" then "shake" else "facepalm"
		emote(which)
		task.wait(rng:NextNumber(every[1], every[2]))
	end
end

-------------------------------------------------------------------------------------------------
-- Cure celebration
-------------------------------------------------------------------------------------------------
local function emitter(character: Model): ParticleEmitter?
	local host = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
	if not host or not host:IsA("BasePart") then
		return nil
	end
	local e = host:FindFirstChild("GwangalliHealthSparkle")
	if e and e:IsA("ParticleEmitter") then
		return e
	end
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "GwangalliHealthSparkle"
	pe.Texture = SPARKLE
	pe.Enabled = false
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(0.6, 1.1)
	pe.Speed = NumberRange.new(5, 9)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-90, 90)
	pe.Acceleration = Vector3.new(0, -6, 0)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.6, 0.35), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
	pe.Color = ColorSequence.new(Color3.fromRGB(120, 255, 200), Color3.fromRGB(255, 214, 110))
	pe.LightEmission = 0.8
	pe.Parent = host
	return pe
end

local function sparkle(count: number)
	local character = ctx.player.Character
	if not character then
		return
	end
	local pe = emitter(character)
	if pe then
		pcall(pe.Emit, pe, count)
	end
end

-- big centred label that springs in and fades (no layout slot: it sits over the world for 1.4 s)
local function pop(text: string, color: Color3)
	local gui = ctx.gui
	local l = K.text(gui, {
		Name = "CurePop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromOffset(260, 44),
		Text = text,
		Font = K.Font.heavy,
		TextSize = K.Type.display,
		TextColor3 = color,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Color3.fromRGB(10, 12, 20),
		ZIndex = 50,
	})
	K.springIn(l, 0.6, { amount = 0.25, duration = 0.45 })
	task.delay(1.1, function()
		K.tween(l, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.fromScale(0.5, 0.32) })
		task.delay(0.45, function()
			l:Destroy()
		end)
	end)
end

-------------------------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------------------------
local function setIll(on: boolean)
	if on == ill then
		return
	end
	ill = on
	setGrade(on, false)
	coughSerial += 1
	if on then
		task.spawn(coughLoop, coughSerial)
	else
		stopStep()
	end
end

local function watchCharacter(character: Model?)
	for _, c in charConns do
		c:Disconnect()
	end
	charConns = {}
	if not character then
		return
	end
	table.insert(charConns, character:GetAttributeChangedSignal(ctx.G.Attr.Ill):Connect(function()
		setIll(character:GetAttribute(ctx.G.Attr.Ill) == true)
	end))
	setIll(character:GetAttribute(ctx.G.Attr.Ill) == true)
end

function Effects.init(c: any)
	ctx = c
	K = c.K
	HS = c.HS
	Anim = c.Anim
	local player = ctx.player
	player.CharacterAdded:Connect(function(ch)
		watchCharacter(ch)
	end)
	player.CharacterRemoving:Connect(function()
		stopStep()
	end)
	if player.Character then
		watchCharacter(player.Character)
	end
	-- the Player attribute is set before the character exists (and survives respawns)
	player:GetAttributeChangedSignal(ctx.G.Attr.Illness):Connect(function()
		local v = player:GetAttribute(ctx.G.Attr.Illness)
		if type(v) == "string" and v ~= "" then
			setIll(true)
		elseif ill and not (player.Character and player.Character:GetAttribute(ctx.G.Attr.Ill) == true) then
			setIll(false)
		end
	end)
	player:GetAttributeChangedSignal(ctx.G.Attr.Collapse):Connect(function()
		if player:GetAttribute(ctx.G.Attr.Collapse) == true then
			setGrade(true, true)
			pcall(emote, "shake")
		elseif ill then
			setGrade(true, false)
		else
			setGrade(false)
		end
	end)
	ctx.on("event:cured", function(p: any)
		sparkle(32)
		pop("완치! 🎉", K.Color.green)
		pcall(K.feedback, "success")
		local _ = p
	end)
	ctx.on("event:vitamin", function()
		sparkle(20)
		pop("개운하다 💉", K.Color.cyan)
		pcall(K.feedback, "success")
	end)
	ctx.on("event:ill", function(p: any)
		setIll(true)
		pcall(K.feedback, "error")
		local _ = p
	end)
	ctx.on("event:woke", function()
		sparkle(12)
	end)
end

function Effects.isIll(): boolean
	return ill
end

return Effects
