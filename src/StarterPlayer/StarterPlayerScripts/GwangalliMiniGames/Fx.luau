--!strict
-- GwangalliMiniGames/Fx: what the minigames look and sound like in the world (client only).
--   * sounds: built-in rbxasset samples only (no uploads), pitched per use (the 딱 of a stone, ticks,
--     buzzers, cheers), positional when a part is given.
--   * hand emotes on any character (yours, other players', NPC rigs) through GwangalliAnim's rig
--     controller: the minigame emotes are registered into Anim.EMOTES (mg_place = reach to the board
--     and put a stone down, mg_rps_pump = fist pumps on "가위바위보", mg_rps_show = the hand held out,
--     mg_press = a quick button press, mg_fist = a small victory fist), stepped every frame while
--     they play.
--   * speech bubbles over heads (accepted words, NPC lines) and the hand glyph (✊ ✋ ✌️) over a hand.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Fx = {}

local Anim: any = nil
local active: { [Model]: number } = {} -- model -> os.clock() until which its controller is stepped

local SOUNDS = {
	stone = { id = "rbxasset://sounds/clickfast.wav", vol = 0.9, speed = 0.62 },
	tick = { id = "rbxasset://sounds/clickfast.wav", vol = 0.35, speed = 1.5 },
	go = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.6, speed = 1.0 },
	buzz = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.55, speed = 0.55 },
	win = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.6, speed = 1.35 },
	lose = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.45, speed = 0.7 },
	whoosh = { id = "rbxasset://sounds/swoosh.wav", vol = 0.35, speed = 1.2 },
	pop = { id = "rbxasset://sounds/clickfast.wav", vol = 0.5, speed = 1.0 },
}

local function setJ(out: any, j: string, p: number, y: number, r: number)
	local e = out[j]
	if not e then
		e = { 0, 0, 0, 0, 0, 0 }
		out[j] = e
	end
	e[1] += p
	e[2] += y
	e[3] += r
end

local function env(u: number): number
	if u < 0.15 then
		return u / 0.15
	elseif u > 0.8 then
		return math.max(0, (1 - u) / 0.2)
	end
	return 1
end

local function registerEmotes()
	if not Anim or not Anim.EMOTES then
		return
	end
	-- reach over the table, put the stone down with a little wrist snap, bring the hand back
	Anim.EMOTES.mg_place = { 1.0, function(u: number, out: any)
		local reach = math.clamp(u / 0.35, 0, 1) * math.clamp((1 - u) / 0.35, 0, 1)
		local snap = if u > 0.32 and u < 0.48 then math.sin((u - 0.32) / 0.16 * math.pi) else 0
		setJ(out, "RightShoulder", 62 * reach, 0, -10 * reach)
		setJ(out, "RightElbow", 18 * reach, 0, 0)
		setJ(out, "RightWrist", -25 * snap, 0, 0)
		setJ(out, "Waist", -10 * reach, 0, 0)
		setJ(out, "Neck", -14 * reach, 0, 0)
	end }
	-- 가위, 바위, 보! three pumps of the fist
	Anim.EMOTES.mg_rps_pump = { 3.0, function(u: number, out: any)
		local e = env(u)
		local pump = math.abs(math.sin(u * math.pi * 3))
		setJ(out, "RightShoulder", (40 + 40 * pump) * e, 0, -8 * e)
		setJ(out, "RightElbow", (90 - 30 * pump) * e, 0, 0)
		setJ(out, "Neck", -6 * e, 0, 0)
	end }
	Anim.EMOTES.mg_rps_show = { 1.8, function(u: number, out: any)
		local e = env(u)
		setJ(out, "RightShoulder", 82 * e, 0, -4 * e)
		setJ(out, "RightElbow", 10 * e, 0, 0)
		setJ(out, "Waist", -6 * e, 0, 0)
	end }
	Anim.EMOTES.mg_press = { 0.6, function(u: number, out: any)
		local down = math.sin(math.clamp(u, 0, 1) * math.pi)
		setJ(out, "RightShoulder", (40 + 20 * down), 0, -6)
		setJ(out, "RightElbow", (50 - 30 * down), 0, 0)
		setJ(out, "RightWrist", -20 * down, 0, 0)
	end }
	Anim.EMOTES.mg_fist = { 1.2, function(u: number, out: any)
		local e = env(u)
		setJ(out, "RightShoulder", 150 * e, 0, 10 * e)
		setJ(out, "RightElbow", 40 * e, 0, 0)
		setJ(out, "Neck", 10 * e, 0, 0)
	end }
end

function Fx.init()
	local m = ReplicatedStorage:FindFirstChild("GwangalliAnim")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok then
			Anim = res
		end
	end
	registerEmotes()
	RunService.RenderStepped:Connect(function()
		if not Anim then
			return
		end
		local now = os.clock()
		for model, untilT in active do
			if now > untilT or not model.Parent then
				active[model] = nil
			else
				pcall(function()
					Anim.rig(model):step()
				end)
			end
		end
	end)
end

function Fx.sound(kind: string, at: BasePart?, volume: number?)
	local s = SOUNDS[kind]
	if not s then
		return
	end
	local snd = Instance.new("Sound")
	snd.SoundId = s.id
	snd.Volume = (volume or 1) * s.vol
	snd.PlaybackSpeed = s.speed
	if at then
		snd.RollOffMaxDistance = 60
		snd.RollOffMinDistance = 6
		snd.Parent = at
	else
		snd.Parent = Workspace.CurrentCamera or Workspace
	end
	snd:Play()
	task.delay(3, function()
		snd:Destroy()
	end)
end

-- One-shot emote on a character / rig (players are animated by this client; NPC rigs by
-- GwangalliNPCClient through their NpcEmote attribute, so they never come through here).
function Fx.emote(model: Model?, name: string)
	if not Anim or not model or not model.Parent then
		return
	end
	local ok, dur = pcall(function()
		return Anim.rig(model):emote(name)
	end)
	if ok and type(dur) == "number" and dur > 0 then
		active[model] = math.max(active[model] or 0, os.clock() + dur + 0.3)
	end
end

function Fx.characterOf(userId: number): Model?
	local p = Players:GetPlayerByUserId(userId)
	return p and p.Character
end

-------------------------------------------------------------------------------------------------
-- bubbles
-------------------------------------------------------------------------------------------------
local bubbles: { [Instance]: BillboardGui } = {}

function Fx.bubble(head: BasePart?, text: string, dur: number?)
	if not head or not head.Parent then
		return
	end
	local old = bubbles[head]
	if old then
		old:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "MiniGameBubble"
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(220, 56)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.1, 0)
	bb.MaxDistance = 70
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	local box = Instance.new("TextLabel")
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.fromScale(0.5, 1)
	box.AutomaticSize = Enum.AutomaticSize.X
	box.Size = UDim2.fromOffset(0, 40)
	box.BackgroundColor3 = Color3.fromRGB(250, 250, 252)
	box.BackgroundTransparency = 0.04
	box.TextColor3 = Color3.fromRGB(20, 24, 36)
	box.Font = Enum.Font.GothamBold
	box.TextSize = 20
	box.Text = text
	box.Parent = bb
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = box
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = box
	local sc = Instance.new("UIScale")
	sc.Scale = 0.6
	sc.Parent = box
	bb.Parent = head
	bubbles[head] = bb
	TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(dur or 3, function()
		if bubbles[head] == bb then
			bubbles[head] = nil
			local t = TweenService:Create(box, TweenInfo.new(0.25), { BackgroundTransparency = 1, TextTransparency = 1 })
			t:Play()
			t.Completed:Wait()
			bb:Destroy()
		end
	end)
end

-- ✊ ✋ ✌️ over a character's right hand for a moment
local HANDS = { "✊", "✋", "✌️" }
function Fx.hand(model: Model?, hand: number, dur: number?)
	if not model then
		return
	end
	local part = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm") or model:FindFirstChild("Head")
	if not part or not part:IsA("BasePart") then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "MiniGameHand"
	bb.Adornee = part
	bb.Size = UDim2.fromOffset(90, 90)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 1.2, 0)
	bb.MaxDistance = 80
	bb.LightInfluence = 0
	bb.AlwaysOnTop = true
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.TextScaled = true
	l.Text = HANDS[hand] or "?"
	l.Parent = bb
	local sc = Instance.new("UIScale")
	sc.Scale = 0.2
	sc.Parent = l
	bb.Parent = part
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(dur or 2.2, function()
		bb:Destroy()
	end)
end

return Fx
