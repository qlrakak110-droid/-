-- GwangalliCombat/Fx (client): the screen-space and world feedback of a fight. Everything is built from Frames,
-- gradients, text and rbxasset sounds (no images, no uploads), pooled and created once.
--   * hurt(strength)       red edge vignette flash (4 gradient edges, ScreenGui "GwangalliCombatFx", order 3)
--   * setLowHp(on)         the same edges breathe while HP <= 30 %
--   * setChase(on)         thin red / blue "siren" edges while an officer sees the player (static on reduced motion)
--   * damageNumber(part, n, color)   floating "-12" over a head (pooled BillboardGuis under PlayerGui)
--   * shake(amp, secs)     camera shake (GwangalliBumpShared.shakeCamera), hitStop(combo) a tiny punch jolt
--   * sound(kind, combo?)  swing / hit / hurt / knock / siren-free blips (Sound instances in SoundService)
-- Cost: nothing per frame; tweens only while something shows.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local Fx = {}

local ctx: any
local K: any
local player: Player

local gui: ScreenGui? = nil
local edges: { Frame } = {}
local sirenL: Frame? = nil
local sirenR: Frame? = nil
local lowHp = false
local LOW_T = 0.6 -- edge transparency while HP is low (breathing between LOW_T and LOW_HI)
local LOW_HI = 0.84
local chaseSerial = 0
local chasing = false

local RED = Color3.fromRGB(255, 52, 60)
local BLUE = Color3.fromRGB(70, 120, 255)

local function edge(parent: Instance, name: string, pos: UDim2, size: UDim2, rot: number, color: Color3): Frame
	local f = K.frame(parent, { Name = name, Position = pos, Size = size, BackgroundTransparency = 1, BackgroundColor3 = color, Active = false, ZIndex = 1 })
	-- alpha fades from the screen edge (0) toward the inside (1)
	K.gradient(f, { color, color }, rot, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }))
	return f
end

local function build()
	local pg = ctx.playerGui
	local old = pg:FindFirstChild("GwangalliCombatFx")
	if old then
		old:Destroy()
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "GwangalliCombatFx"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 3
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- hurt / low-HP edges: 11 % of the screen on each side, only visible while something happens
	local T = 0.11
	table.insert(edges, edge(sg, "Top", UDim2.fromScale(0, 0), UDim2.fromScale(1, T), 90, RED))
	table.insert(edges, edge(sg, "Bottom", UDim2.fromScale(0, 1 - T), UDim2.fromScale(1, T), -90, RED))
	table.insert(edges, edge(sg, "Left", UDim2.fromScale(0, 0), UDim2.fromScale(T, 1), 0, RED))
	table.insert(edges, edge(sg, "Right", UDim2.fromScale(1 - T, 0), UDim2.fromScale(T, 1), 180, RED))
	-- siren: thin side edges (red left, blue right), alternating
	sirenL = edge(sg, "SirenLeft", UDim2.fromScale(0, 0), UDim2.fromScale(0.045, 1), 0, RED)
	sirenR = edge(sg, "SirenRight", UDim2.fromScale(0.955, 0), UDim2.fromScale(0.045, 1), 180, BLUE)
	sg.Parent = pg
	gui = sg
end

function Fx.init(c: any)
	ctx = c
	K = ctx.K
	player = Players.LocalPlayer
	build()
end

local function restT(): number
	return if lowHp then LOW_T else 1
end

-- strength 0..1 (a jab ~0.35, a knockdown 1)
function Fx.hurt(strength: number?)
	local s = math.clamp(strength or 0.5, 0.15, 1)
	for _, f in edges do
		K.cancel(f)
		f.BackgroundTransparency = 1 - 0.78 * s
		K.tweenD(f, 0.55, { BackgroundTransparency = restT() }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.08)
	end
	pcall(K.haptic, "error")
end

function Fx.setLowHp(on: boolean)
	if on == lowHp then
		return
	end
	lowHp = on
	for _, f in edges do
		if on then
			f.BackgroundTransparency = LOW_HI
			K.breathe(f, true, LOW_T, LOW_HI)
		else
			K.breathe(f, false)
			K.tween(f, 0.6, { BackgroundTransparency = 1 })
		end
	end
end

function Fx.setChase(on: boolean)
	if on == chasing then
		return
	end
	chasing = on
	chaseSerial += 1
	local mine = chaseSerial
	local l, r = sirenL, sirenR
	if not l or not r then
		return
	end
	if not on then
		K.tween(l, 0.4, { BackgroundTransparency = 1 })
		K.tween(r, 0.4, { BackgroundTransparency = 1 })
		return
	end
	if K.reduced() then
		-- reduced motion: a calm, static tint instead of flashing
		l.BackgroundTransparency = 0.8
		r.BackgroundTransparency = 0.8
		return
	end
	task.spawn(function()
		local red = false
		while chaseSerial == mine and chasing and l.Parent do
			red = not red
			K.tween(l, 0.22, { BackgroundTransparency = if red then 0.55 else 0.92 }, Enum.EasingStyle.Sine)
			K.tween(r, 0.22, { BackgroundTransparency = if red then 0.92 else 0.55 }, Enum.EasingStyle.Sine)
			task.wait(0.5)
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- camera
-------------------------------------------------------------------------------------------------
function Fx.shake(amp: number?, secs: number?)
	local Bump = ctx.Bump
	if K.reduced() then
		amp = (amp or 0.2) * 0.5
	end
	if Bump and type(Bump.shakeCamera) == "function" then
		pcall(Bump.shakeCamera, amp, secs)
	end
end

-- the landed punch: a short jolt, a little stronger for the hook
function Fx.hitStop(combo: number?)
	local c = combo or 1
	Fx.shake(0.05 + 0.035 * c, 0.1 + 0.03 * c)
end

-------------------------------------------------------------------------------------------------
-- damage numbers (pooled BillboardGuis under PlayerGui, adorned to a head / root)
-------------------------------------------------------------------------------------------------
type Num = { bb: BillboardGui, label: TextLabel, busyUntil: number, seq: number }
local pool: { Num } = {}
local POOL_MAX = 6

local function newNum(): Num
	local bb = Instance.new("BillboardGui")
	bb.Name = "GwangalliCombatDamage"
	bb.Size = UDim2.fromOffset(120, 80)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 90
	bb.ResetOnSpawn = false
	bb.Enabled = false
	local l = K.text(bb, {
		Name = "Amount",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 46),
		Size = UDim2.new(1, 0, 0, 34),
		Text = "",
		Font = K.Font.heavy,
		TextSize = 26,
		TextColor3 = K.Color.gold,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = K.Color.bg,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	bb.Parent = ctx.playerGui
	return { bb = bb, label = l, busyUntil = 0, seq = 0 }
end

local function takeNum(): Num
	local now = os.clock()
	local oldest: Num? = nil
	for _, n in pool do
		if n.busyUntil <= now then
			return n
		end
		if not oldest or n.busyUntil < oldest.busyUntil then
			oldest = n
		end
	end
	if #pool < POOL_MAX then
		local n = newNum()
		table.insert(pool, n)
		return n
	end
	return oldest :: Num
end

function Fx.damageNumber(part: BasePart?, amount: number?, color: Color3?, big: boolean?)
	if typeof(part) ~= "Instance" or not (part :: Instance):IsA("BasePart") or not (part :: BasePart):IsDescendantOf(workspace) then
		return
	end
	local n = takeNum()
	if not n.bb.Parent then
		n.bb.Parent = ctx.playerGui
	end
	n.seq += 1
	local seq = n.seq
	local now = os.clock()
	n.busyUntil = now + 0.95
	local l = n.label
	K.cancel(l)
	local a = math.max(1, math.floor((tonumber(amount) or 0) + 0.5))
	l.Text = "-" .. tostring(a)
	l.TextColor3 = color or K.Color.gold
	l.TextSize = if big then 32 else 26
	l.TextTransparency = 0
	l.TextStrokeTransparency = 0.3
	l.Position = UDim2.new(0.5, 0, 0, 46)
	n.bb.Adornee = part
	n.bb.StudsOffsetWorldSpace = Vector3.new((math.random() - 0.5) * 1.4, 1.6, (math.random() - 0.5) * 0.6)
	n.bb.Enabled = true
	pcall(K.springIn, l, 0.55, { amount = 0.45, duration = 0.35 })
	K.tweenD(l, 0.8, { Position = UDim2.new(0.5, 0, 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	K.tweenD(l, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.55)
	task.delay(0.92, function()
		if n.seq == seq then
			n.bb.Enabled = false
			n.bb.Adornee = nil
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- sounds (rbxasset ids only; the emulator synthesizes a blip for them)
-------------------------------------------------------------------------------------------------
local SOUNDS = {
	swing = { id = "rbxasset://sounds/swoosh.wav", volume = 0.32, speed = 1.35 },
	hit = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.55, speed = 1.3 },
	knock = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.7, speed = 0.9 },
	hurt = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.5, speed = 1.05 },
}
local soundCache: { [string]: Sound } = {}
local lastPlay: { [string]: number } = {}

function Fx.sound(kind: string, combo: number?)
	if K.settings and K.settings.sound == false then
		return
	end
	local def = SOUNDS[kind]
	if not def then
		return
	end
	local now = os.clock()
	if lastPlay[kind] and now - lastPlay[kind] < 0.05 then
		return
	end
	lastPlay[kind] = now
	pcall(function()
		local s = soundCache[kind]
		if not (s and s.Parent) then
			s = Instance.new("Sound")
			s.Name = "GwangalliCombat_" .. kind
			s.SoundId = def.id
			s.Volume = def.volume
			s.Parent = SoundService
			soundCache[kind] = s
		end
		local snd = s :: Sound
		-- a little pitch variety: the combo climbs, every swing differs slightly
		snd.PlaybackSpeed = def.speed * (1 + ((combo or 1) - 1) * 0.06) * (0.96 + math.random() * 0.08)
		snd.TimePosition = 0
		snd:Play()
	end)
end

return Fx
