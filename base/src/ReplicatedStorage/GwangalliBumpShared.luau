-- GwangalliBumpShared: the 어깨빵 (shoulder bump) contract + the shared knockdown motion + the pooled
-- speech-bubble system (owner: npc_types). Pure data / pure functions at require time; the client-only
-- helpers (bubbles, character knockdown) are only ever called from LocalScripts.
--
-- REMOTES (ReplicatedStorage.GwangalliBump, created by ServerScriptService.GwangalliGameplay.Bump):
--   Action (RemoteEvent, client -> server): FireServer(kind, payload)
--     "bump"    { target = "npc" | "player", id = citizenId | userId, pos = {x,y,z} (npc pedestrians) }
--     "fell"    { id = citizenId, outcome = "stagger" | "knockdown", pos = {x,y,z} }  a client-side
--               pedestrian knocked the LOCAL player over (fool / violent / drunk); only affects that player
--     "chat"    { id = citizenId, pos = {x,y,z} }  a chatty pedestrian walked up to the player (client
--               side approach done): the server opens the dialog card
--     "beg"     { id = citizenId, pos = {x,y,z} }  a 걸렁뱅이 asks (same, beggar node)
--     "setting" { enabled = boolean }  player-vs-player 어깨빵 on / off (attribute BumpEnabled)
--   Event (RemoteEvent, server -> client): FireClient(payload) with payload.kind:
--     "hit"  { target, id, outcome, dx, dz, puk }   your bump landed (play the target's motion locally
--            for pedestrians; key NPCs / players are moved by the server / their own client)
--     "fall" { outcome, dx, dz, by (citizenId?), byUser (userId?), delay? }  you get knocked down /
--            staggered: play your own motion (PlatformStand + impulse + pose)
--     "say"  { id, text, typeId, dur }  a bubble over that NPC (key NPC reactions)
--     "hint" { app = "jobs" | "map", dest? }  the phone should open an app (phone owner integrates)
--     "miss" { reason }  the bump was refused (too far / cooldown / target protected)
-- ATTRIBUTES: Player.BumpEnabled (bool, default true: others may 어깨빵 you and you them),
--   Player.BumpStreak (number: successive bumps within 6 s), NPC model.NpcKnock = "t0|dx|dz|outcome"
--   (key NPCs: every client plays the knockdown from this attribute, GwangalliNPCClient).

local Bump = {}
Bump.VERSION = 1

Bump.Folder = "GwangalliBump"
Bump.Remote = { Action = "BumpAction", Event = "BumpEvent" }
Bump.Attr = { Enabled = "BumpEnabled", Streak = "BumpStreak", Knock = "NpcKnock", Knocked = "GwangalliKnocked" }
Bump.BUBBLE_EVENT = "GwangalliBubble" -- BindableEvent under LocalPlayer: Fire(adornee, text, typeId, dur, offsetY)

-- rules --------------------------------------------------------------------------------------------
Bump.RANGE = 5.5 -- studs in front of the player: the 어깨빵 button appears / the server accepts
Bump.RANGE_SLACK = 2.5 -- server tolerance (client positions lag a little)
Bump.FACING = 0.2 -- dot(player look, direction to the target) must be at least this
Bump.COOLDOWN = 1.2 -- s between bumps on NPCs
Bump.COOLDOWN_PVP = 3 -- s between bumps on players
Bump.STREAK_WINDOW = 6 -- s: bumps closer than this build a streak (knockdowns get likelier)
Bump.KNOCK_DUR = 1.4 -- s on the ground
Bump.FALL_DUR = 0.42 -- s of the fall itself
Bump.GETUP_DUR = 0.7
Bump.STAGGER_DUR = 0.9
Bump.STAGGER_STEP = 2 -- studs sideways
Bump.SLOW_DUR = 2 -- s of slow walk after getting up
Bump.SLOW_MULT = 0.55
Bump.STAMINA_HIT = -3 -- 체력 of a knocked-down player
Bump.IMPULSE = 22 -- studs/s along the bump direction (player knockdown): ~2 studs in the air + a
-- short slide on the ground (friction ~0.4 at gravity 196.2) = about 5 studs, a comic tumble, not a launch
Bump.IMPULSE_UP = 9
Bump.TOPPLE = 5 -- rad/s angular kick about (up x bump direction): the body tips over AWAY from the hitter
Bump.SHAKE = 0.35 -- camera shake amplitude (studs) / seconds
Bump.AFFINITY = { stagger = -3, knockdown = -6 } -- Social source "bump" amounts
Bump.CHAT_RANGE = 25 -- chatty NPCs approach from this far
Bump.CHAT_STOP = 3.2 -- and stop this close
Bump.CHAT_COOLDOWN = 150 -- s before the same NPC talks to you first again
Bump.CHAT_GLOBAL_GAP = 40 -- s between two approaches (one at a time)
Bump.BEG_RANGE = 20
Bump.GIVE = { 1000, 5000 }
Bump.VIOLENT = { glare = 10, block = 6, shoveClose = 3.2, shoveAfter = 3.5, chase = { 6, 8 }, chaseSpeed = 11.5 }
Bump.FOOL = { bumpReach = 2.6, bumpCooldown = 14, wobble = 0.9 }
Bump.DRUNK = { speed = 0.62, sway = 1.1, swayHz = 0.55, napChance = 0.4, napTime = { 25, 60 } }

Bump.OUTCOMES = { stagger = true, knockdown = true }
Bump.REACTION = { plain = "complain", violent = "retaliate", fool = "laugh", beggar = "beg", drunk = "mumble" }

-- Who falls? Pure, deterministic given rnd. strength = the player's 근력 (0..100), build = "slim" |
-- "avg" | "broad", targetType = NPC type, streak = successive bumps so far. Returns "stagger" |
-- "knockdown" and the chance that was rolled against.
function Bump.outcome(strength: number?, targetType: string?, build: string?, streak: number?, rnd: number?): (string, number)
	local s = math.clamp(tonumber(strength) or 10, 0, 100)
	local p = 0.28 + s / 170 -- 0.28 .. 0.87
	if build == "slim" then
		p += 0.14
	elseif build == "broad" then
		p -= 0.18
	end
	local t = targetType or "plain"
	if t == "violent" then
		p -= 0.22 -- tough; they mostly stagger and bump back
	elseif t == "drunk" then
		p += 0.22 -- already wobbly
	elseif t == "fool" then
		p += 0.12
	elseif t == "beggar" then
		p += 0.08
	end
	p += math.min(3, math.max(0, (streak or 0) - 1)) * 0.1
	p = math.clamp(p, 0.08, 0.95)
	local r = rnd or math.random()
	return if r < p then "knockdown" else "stagger", p
end

-- A player bumping another player: the victim's strength resists.
function Bump.outcomePvp(strength: number?, victimStrength: number?, rnd: number?): (string, number)
	local a = math.clamp(tonumber(strength) or 10, 0, 100)
	local b = math.clamp(tonumber(victimStrength) or 10, 0, 100)
	local p = math.clamp(0.4 + (a - b) / 160, 0.1, 0.8)
	local r = rnd or math.random()
	return if r < p then "knockdown" else "stagger", p
end

-- The knockdown timeline: phase + rotation fraction k (0 standing .. 1 lying) at `t` seconds after
-- the hit. "fall" (ease-in with a small bounce) -> "down" -> "getup" (ease-in-out) -> "done".
function Bump.knockPhase(t: number, outcome: string?): (string, number)
	if outcome == "stagger" then
		if t >= Bump.STAGGER_DUR then
			return "done", 0
		end
		local u = t / Bump.STAGGER_DUR
		return "stagger", math.sin(u * math.pi) -- lean out and back
	end
	if t < Bump.FALL_DUR then
		local u = t / Bump.FALL_DUR
		local k = u * u * (3 - 2 * u) -- smoothstep
		k = k * k -- accelerating
		return "fall", k
	end
	local down = Bump.KNOCK_DUR - Bump.FALL_DUR
	if t < Bump.KNOCK_DUR then
		local u = (t - Bump.FALL_DUR) / down
		local bounce = if u < 0.3 then math.sin(u / 0.3 * math.pi) * 0.08 else 0
		return "down", 1 - bounce
	end
	if t < Bump.KNOCK_DUR + Bump.GETUP_DUR then
		local u = (t - Bump.KNOCK_DUR) / Bump.GETUP_DUR
		return "getup", 1 - (u * u * (3 - 2 * u))
	end
	return "done", 0
end

-- Root CFrame of a CFrame-driven (anchored) R15 rig lying down k of the way (0..1) along the fall
-- direction (dx, dz: unit, world). feet = ground point, yaw = facing, ground = root centre height,
-- scale = rig scale. The body pivots around the feet; lying, the torso rests 0.62 * scale above the
-- ground, a little past the feet so the head lands ~ground + 3 studs away.
function Bump.fallRootCFrame(feet: Vector3, yaw: number, dx: number, dz: number, k: number, ground: number, scale: number): CFrame
	local d = Vector3.new(dx, 0, dz)
	if d.Magnitude < 1e-3 then
		d = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	end
	d = d.Unit
	local axis = Vector3.yAxis:Cross(d)
	if axis.Magnitude < 1e-3 then
		axis = Vector3.xAxis
	end
	local ang = k * math.pi * 0.5
	local rot = CFrame.fromAxisAngle(axis.Unit, ang)
	local up = rot:VectorToWorldSpace(Vector3.new(0, ground, 0))
	local lift = math.sin(ang) * 0.62 * scale
	local pos = feet + up + Vector3.new(0, lift, 0)
	return CFrame.new(pos) * rot * CFrame.Angles(0, yaw, 0)
end

-- Stagger root offset (relative to the standing CFrame): a sideways step and a lean.
function Bump.staggerOffset(dx: number, dz: number, k: number, scale: number): (Vector3, number)
	local step = Bump.STAGGER_STEP * k
	return Vector3.new(dx * step, -0.08 * k * scale, dz * step), math.rad(14) * k
end

-- Joint poses (degrees, GwangalliAnim.POSES format: motor -> { pitch, yaw, roll }; CFrame.Angles applies
-- roll first: + roll swings the RIGHT arm / leg outward, - roll the LEFT one). knock = a comic
-- "starfish" flail (arms thrown out, one knee up) that reads at a glance whether the body ends up on
-- its back or its front; stagger = arms out for balance; both kept in sync with GwangalliAnim.POSES.
Bump.POSES = {
	knock = { RightShoulder = { 28, 0, 78 }, RightElbow = { 24, 0, 0 }, LeftShoulder = { 36, 0, -70 }, LeftElbow = { 30, 0, 0 }, Waist = { -8, 0, 0 }, Neck = { -16, 0, 0 }, RightHip = { 22, 0, 14 }, RightKnee = { -32, 0, 0 }, LeftHip = { -6, 0, -12 }, LeftKnee = { -14, 0, 0 } },
	stagger = { RightShoulder = { 18, 0, 58 }, RightElbow = { 22, 0, 0 }, LeftShoulder = { 34, 0, -42 }, LeftElbow = { 34, 0, 0 }, Waist = { 0, 0, 12 }, Neck = { 6, 0, -8 } },
	lunge = { RightShoulder = { -20, 0, -10 }, LeftShoulder = { 30, 0, 24 }, Waist = { 6, 0, -22 }, Neck = { 0, 0, 10 } },
	nap = { RightShoulder = { 20, 0, 70 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 10, 0, -20 }, LeftElbow = { 40, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -60, 0, 0 }, LeftHip = { 10, 0, 0 }, LeftKnee = { -20, 0, 0 }, Neck = { 10, 0, 20 } },
}

local DEG = math.pi / 180
local function anglesOf(t: { number }): CFrame
	return CFrame.Angles(t[1] * DEG, t[2] * DEG, t[3] * DEG)
end
-- The same poses as CFrame offsets (GwangalliStreetLife/Anim.POSES format).
Bump.POSE_CF = {}
for name, pose in Bump.POSES do
	local out = {}
	for motor, a in pose do
		out[motor] = anglesOf(a)
	end
	Bump.POSE_CF[name] = out
end

-- "t0|dx|dz|outcome" attribute for key NPC knockdowns.
function Bump.encodeKnock(t0: number, dx: number, dz: number, outcome: string): string
	return string.format("%.2f|%.3f|%.3f|%s", t0, dx, dz, outcome)
end
function Bump.decodeKnock(s: any): (number?, number, number, string)
	if type(s) ~= "string" then
		return nil, 0, 0, "stagger"
	end
	local parts = string.split(s, "|")
	local t0 = tonumber(parts[1])
	return t0, tonumber(parts[2]) or 0, tonumber(parts[3]) or 0, parts[4] or "stagger"
end

-- vector helpers for remote payloads ({x, y, z} tables)
function Bump.packV(v: Vector3): { number }
	return { math.floor(v.X * 10 + 0.5) / 10, math.floor(v.Y * 10 + 0.5) / 10, math.floor(v.Z * 10 + 0.5) / 10 }
end
function Bump.unpackV(t: any): Vector3?
	if type(t) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(t[1] or t.x or t.X), tonumber(t[2] or t.y or t.Y), tonumber(t[3] or t.z or t.Z)
	if not x or not y or not z or x ~= x or y ~= y or z ~= z or math.abs(x) > 1e5 or math.abs(y) > 1e5 or math.abs(z) > 1e5 then
		return nil
	end
	return Vector3.new(x, y, z)
end

-------------------------------------------------------------------------------------------------
-- CLIENT: the pooled speech bubbles (one pool per client; every script that requires this module
-- shares it). <= MAX visible, nearest-first (a new one steals the farthest), fade in / out, 40-stud
-- range (BillboardGui.MaxDistance), per-type colours, a tail, AlwaysOnTop = false.
-------------------------------------------------------------------------------------------------
local Bubbles = {}
Bubbles.__index = Bubbles
Bump.BUBBLE_MAX = 10
Bump.BUBBLE_RANGE = 40

local bubblePool: any = nil

local function c3(t: any, fallback: Color3): Color3
	if type(t) == "table" and #t >= 3 then
		return Color3.fromRGB(t[1], t[2], t[3])
	end
	return fallback
end

local function newBubbleGui(parent: Instance, font: Enum.Font): any
	local bb = Instance.new("BillboardGui")
	bb.Name = "Bubble"
	bb.Size = UDim2.fromOffset(210, 90)
	bb.SizeOffset = Vector2.new(0, 0.5)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.3, 0)
	bb.MaxDistance = Bump.BUBBLE_RANGE
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.ResetOnSpawn = false
	bb.Enabled = false
	bb.ClipsDescendants = false
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -10)
	box.Size = UDim2.new(1, 0, 0, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundColor3 = Color3.fromRGB(250, 250, 252)
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = box
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 9)
	pad.PaddingRight = UDim.new(0, 9)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = box
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = font
	label.TextSize = 14
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(24, 26, 36)
	label.TextTransparency = 1
	label.Text = ""
	label.Parent = box
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 1, -10)
	tail.Size = UDim2.fromOffset(12, 12)
	tail.Rotation = 45
	tail.BackgroundColor3 = box.BackgroundColor3
	tail.BackgroundTransparency = 1
	tail.BorderSizePixel = 0
	tail.ZIndex = 0
	tail.Parent = bb
	bb.Parent = parent
	return { gui = bb, box = box, label = label, tail = tail, adornee = nil, untilT = 0, seq = 0 }
end

-- Bump.bubbles(): the client's pool (created on first use; parent = a ScreenGui in PlayerGui so the
-- bubbles survive respawns and never replicate). opts.font (Enum.Font), opts.types (Social.TYPES).
function Bump.bubbles(opts: any?): any
	if bubblePool then
		return bubblePool
	end
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	if not player then
		return nil -- server
	end
	local o = opts or {}
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	local gui = pg and pg:FindFirstChild("GwangalliBubbles")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "GwangalliBubbles"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 5
		gui.Parent = pg
	end
	local self = setmetatable({}, Bubbles)
	self.gui = gui
	-- each bubble is its own BillboardGui root directly in PlayerGui (Adornee = the head / root): the
	-- usual Roblox pattern, and the one the 광안리 임시 스튜디오 player places in the world (npc_mind)
	self.parent = pg
	self.items = {}
	self.byAdornee = {}
	self.font = if typeof(o.font) == "EnumItem" then o.font else Enum.Font.GothamMedium
	self.types = o.types
	self.tween = game:GetService("TweenService")
	self.fadeIn = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	self.fadeOut = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	bubblePool = self
	return self
end

function Bubbles:setTypes(types: any)
	self.types = types
end

local function camPos(): Vector3
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame.Position else Vector3.zero
end

function Bubbles:_free(newDist: number): any
	for _, it in self.items do
		if not it.adornee then
			return it
		end
	end
	if #self.items < Bump.BUBBLE_MAX then
		local it = newBubbleGui(self.parent or self.gui, self.font)
		table.insert(self.items, it)
		return it
	end
	-- nearest-first: steal the farthest one, but only for somebody nearer than it
	local cp = camPos()
	local best, bd = nil, -1
	for _, it in self.items do
		local a = it.adornee
		local d = if a and a.Parent then (a.Position - cp).Magnitude else 1e9
		if d > bd then
			best, bd = it, d
		end
	end
	if not best or bd <= newDist then
		return nil
	end
	self:_hide(best, true)
	return best
end

function Bubbles:_hide(it: any, now: boolean?)
	local a = it.adornee
	if a and self.byAdornee[a] == it then
		self.byAdornee[a] = nil
	end
	it.adornee = nil
	it.untilT = 0
	it.seq += 1
	if now then
		it.gui.Enabled = false -- (the old adornee stays referenced until the next say: a disabled gui draws nothing)
		return
	end
	local seq = it.seq
	pcall(function()
		self.tween:Create(it.label, self.fadeOut, { TextTransparency = 1 }):Play()
		self.tween:Create(it.box, self.fadeOut, { BackgroundTransparency = 1 }):Play()
		self.tween:Create(it.tail, self.fadeOut, { BackgroundTransparency = 1 }):Play()
	end)
	task.delay(0.3, function()
		if it.seq == seq and not it.adornee then
			it.gui.Enabled = false
		end
	end)
end

-- say(adornee: BasePart, text, typeId?, dur?, offsetY?): one bubble per adornee (the text is replaced)
function Bubbles:say(adornee: any, text: any, typeId: any, dur: any, offsetY: any)
	if typeof(adornee) ~= "Instance" or not adornee:IsA("BasePart") or type(text) ~= "string" or text == "" then
		return
	end
	-- out of range: nothing to show (keeps the pool for the people around the player)
	local dist = (adornee.Position - camPos()).Magnitude
	if dist > Bump.BUBBLE_RANGE + 6 then
		return
	end
	local it = self.byAdornee[adornee]
	local fresh = it == nil
	if not it then
		it = self:_free(dist)
		if not it then
			return
		end
		it.adornee = adornee
		self.byAdornee[adornee] = it
	end
	it.seq += 1
	local seq = it.seq
	local def = self.types and (self.types[typeId] or self.types.plain)
	local bg = c3(def and def.bubble, Color3.fromRGB(250, 250, 252))
	local ink = c3(def and def.ink, Color3.fromRGB(24, 26, 36))
	it.box.BackgroundColor3 = bg
	it.tail.BackgroundColor3 = bg
	it.label.TextColor3 = ink
	it.label.Text = text
	it.gui.Adornee = adornee
	it.gui.StudsOffsetWorldSpace = Vector3.new(0, tonumber(offsetY) or 2.3, 0)
	it.gui.Enabled = true
	if fresh then
		it.label.TextTransparency = 1
		it.box.BackgroundTransparency = 1
		it.tail.BackgroundTransparency = 1
		pcall(function()
			self.tween:Create(it.label, self.fadeIn, { TextTransparency = 0 }):Play()
			self.tween:Create(it.box, self.fadeIn, { BackgroundTransparency = 0.04 }):Play()
			self.tween:Create(it.tail, self.fadeIn, { BackgroundTransparency = 0.04 }):Play()
		end)
	else
		it.label.TextTransparency = 0
		it.box.BackgroundTransparency = 0.04
		it.tail.BackgroundTransparency = 0.04
	end
	local d = math.clamp(tonumber(dur) or 3.5, 0.8, 12)
	it.untilT = os.clock() + d
	task.delay(d, function()
		if it.seq == seq and it.adornee == adornee then
			self:_hide(it)
		end
	end)
end

function Bubbles:clear(adornee: any)
	local it = adornee and self.byAdornee[adornee]
	if it then
		self:_hide(it)
	end
end

function Bubbles:count(): number
	local n = 0
	for _, it in self.items do
		if it.adornee then
			n += 1
		end
	end
	return n
end

-------------------------------------------------------------------------------------------------
-- CLIENT: the local player's knockdown / stagger (R15 character). Humanoid.PlatformStand + an impulse
-- along the bump direction + a procedural pose (Motor6D C0 tweens, no ragdoll constraints), then a
-- get-up and a short slow. Returns false when a knockdown is already playing. opts: onPhase(name),
-- anim (GwangalliAnim module, optional: plays the default "fall" clip during the fall), silent.
-------------------------------------------------------------------------------------------------
local knockState: any = nil

-- Our pose tweens change Motor6D.C0 and tween it back afterwards. A lunge and a knockdown can overlap
-- (you bump, the violent NPC bumps back 0.9 s later): both must return to the C0 the motor had before
-- OUR first tween, not to a value caught mid-tween. claim() remembers it until the last tween of ours
-- on that motor has finished (release with the matching token); weak keys: respawned rigs drop out.
local ownRest: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local ownToken: { [Motor6D]: number } = setmetatable({}, { __mode = "k" }) :: any
local function claim(m: Motor6D): (CFrame, number)
	local r = ownRest[m]
	if not r then
		r = m.C0
		ownRest[m] = r
	end
	local t = (ownToken[m] or 0) + 1
	ownToken[m] = t
	return r, t
end
local function release(m: Motor6D, token: number)
	if ownToken[m] == token then
		ownRest[m] = nil
	end
end

local KNOCK_MOTORS = { RightShoulder = true, RightElbow = true, LeftShoulder = true, LeftElbow = true, Waist = true, Neck = true, RightHip = true, RightKnee = true, LeftHip = true, LeftKnee = true }
local function motorsOf(character: Model): { [string]: Motor6D }
	local out = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and KNOCK_MOTORS[d.Name] and not out[d.Name] then
			out[d.Name] = d
		end
	end
	return out
end

function Bump.isDown(): boolean
	return knockState ~= nil
end

function Bump.knockCharacter(character: Model, dx: number, dz: number, outcome: string, opts: any?): boolean
	if knockState or not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return false
	end
	local o = opts or {}
	local TweenService = game:GetService("TweenService")
	local dir = Vector3.new(dx, 0, dz)
	if dir.Magnitude < 1e-3 then
		dir = -root.CFrame.LookVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	local motors = motorsOf(character)
	local rest: { [string]: CFrame } = {}
	local tokens: { [string]: number } = {}
	for name, m in motors do
		rest[name], tokens[name] = claim(m)
	end
	local st = { character = character, outcome = outcome, t0 = os.clock(), motors = motors, rest = rest }
	knockState = st
	character:SetAttribute(Bump.Attr.Knocked, true)
	local function pose(name: string?, secs: number)
		local ti = TweenInfo.new(secs, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local p = name and Bump.POSE_CF[name]
		for mname, m in motors do
			local target = rest[mname]
			if p and p[mname] then
				target = target * p[mname]
			end
			pcall(function()
				TweenService:Create(m, ti, { C0 = target }):Play()
			end)
		end
	end
	local function phase(name: string)
		if type(o.onPhase) == "function" then
			pcall(o.onPhase, name)
		end
	end
	task.spawn(function()
		local baseSpeed = humanoid.WalkSpeed
		if outcome == "knockdown" then
			phase("fall")
			pcall(function()
				humanoid.PlatformStand = true
			end)
			pcall(function()
				root.AssemblyLinearVelocity = dir * Bump.IMPULSE + Vector3.new(0, Bump.IMPULSE_UP, 0)
				-- tip the body over away from the hitter (the head moves along dir: omega = up x dir);
				-- without it a PlatformStanding R15 can land on its feet and just slide
				root.AssemblyAngularVelocity = Vector3.yAxis:Cross(dir) * Bump.TOPPLE
			end)
			pose("knock", Bump.FALL_DUR)
			if o.anim and type(o.anim.play) == "function" then
				pcall(o.anim.play, character, "fall", { fade = 0.1 })
			end
			task.wait(Bump.FALL_DUR)
			phase("down")
			task.wait(math.max(0.1, Bump.KNOCK_DUR - Bump.FALL_DUR))
			phase("getup")
			if o.anim and type(o.anim.stop) == "function" then
				pcall(o.anim.stop, character, "fall", 0.2)
			end
			pose(nil, Bump.GETUP_DUR * 0.6)
			pcall(function()
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end)
			task.wait(Bump.GETUP_DUR)
		else
			phase("stagger")
			pcall(function()
				root.AssemblyLinearVelocity = dir * (Bump.IMPULSE * 0.45) + Vector3.new(0, 3, 0)
			end)
			pose("stagger", 0.18)
			task.wait(Bump.STAGGER_DUR * 0.45)
			pose(nil, Bump.STAGGER_DUR * 0.55)
			task.wait(Bump.STAGGER_DUR * 0.55)
		end
		-- slow for a moment (restored only when nothing else changed the speed meanwhile)
		phase("slow")
		if humanoid.Parent and humanoid.WalkSpeed == baseSpeed and baseSpeed > 0 then
			local slow = math.floor(baseSpeed * Bump.SLOW_MULT * 10 + 0.5) / 10
			humanoid.WalkSpeed = slow
			task.delay(Bump.SLOW_DUR, function()
				if humanoid.Parent and humanoid.WalkSpeed == slow then
					humanoid.WalkSpeed = baseSpeed
				end
			end)
		end
		for name, m in motors do
			release(m, tokens[name])
		end
		if knockState == st then
			knockState = nil
		end
		if character.Parent then
			character:SetAttribute(Bump.Attr.Knocked, nil)
		end
		phase("done")
	end)
	return true
end

-- The attacker's shoulder lunge (local character): a quick waist twist toward the target + a step.
function Bump.lungeCharacter(character: Model, towardRight: boolean)
	if not character then
		return
	end
	local TweenService = game:GetService("TweenService")
	local root = character:FindFirstChild("HumanoidRootPart")
	local motors = motorsOf(character)
	local sign = if towardRight then 1 else -1
	for name, m in motors do
		local p = Bump.POSES.lunge[name]
		if p then
			local rest, token = claim(m)
			local off = CFrame.Angles(p[1] * DEG, p[2] * DEG, p[3] * DEG * sign)
			pcall(function()
				local t1 = TweenService:Create(m, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = rest * off })
				t1:Play()
				t1.Completed:Connect(function(state)
					if state ~= Enum.PlaybackState.Completed or ownToken[m] ~= token then
						return -- a knockdown took the motor over meanwhile (it tweens back to the same rest)
					end
					local t2 = TweenService:Create(m, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = rest })
					t2:Play()
					t2.Completed:Connect(function()
						release(m, token)
					end)
				end)
			end)
		end
	end
	if root and root:IsA("BasePart") then
		pcall(function()
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, v.Z) + root.CFrame.LookVector * 9
		end)
	end
end

-- A short camera shake (local). Adds an offset after the camera scripts ran (RenderPriority.Camera + 1).
function Bump.shakeCamera(strength: number?, seconds: number?)
	local RunService = game:GetService("RunService")
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local amp = strength or Bump.SHAKE
	local dur = seconds or Bump.SHAKE
	local name = "GwangalliBumpShake" .. tostring(math.floor(os.clock() * 1000))
	local t0 = os.clock()
	local ok = pcall(function()
		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
			local t = os.clock() - t0
			if t >= dur then
				RunService:UnbindFromRenderStep(name)
				return
			end
			local k = (1 - t / dur) * amp
			local off = Vector3.new(math.sin(t * 61) * k, math.cos(t * 47) * k * 0.7, 0)
			cam.CFrame = cam.CFrame * CFrame.new(off)
		end)
	end)
	if not ok then
		return
	end
end

return Bump
