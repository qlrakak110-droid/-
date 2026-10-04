--!strict
-- BowlingFX/Rig: procedural bowling body motion for any character (own or other players'),
-- layered over the default Animate script through Motor6D.Transform.
--   * hold(char, color)    the house ball in the right hand + a "ball at the chest" idle pose
--   * pickup(char)         bend down to the ball return, the ball appears in the hand
--   * approach(char)       pushaway -> downswing -> backswing; backswing height follows setPower()
--   * release(char, power) forward swing, slide (left knee bent, right leg back), follow-through
--   * emote(char, kind)    "cheer" (both arms up, hop), "pump" (fist pump), "clap", "sad" (hands
--                          on the head, head down)
--   * drop(char) / stop(char) / clear()
-- Poses are pitch / yaw / roll in degrees in the joint's PARENT part frame and are converted to
-- the joint's C0 space, so R15 and R6 rigs share one pose table (R6 only has shoulders / hips /
-- neck / root). Writes happen in RunService.PreSimulation (after the Animator stepped, before
-- physics + render); the connection exists only while some character is animating. Characters
-- without Motor6Ds (or out of streaming range) are skipped silently.

local RunService = game:GetService("RunService")

local Rig = {}

type JointRec = { motor: Motor6D, c0: CFrame, touched: boolean }
type Act = {
	char: Model,
	kind: string,
	t0: number,
	dur: number, -- 0 = until stopped / replaced
	power: number,
	fadeIn: number,
	fadeOut: number,
	stopAt: number?,
	seed: number,
	from: number, -- release: backswing angle at the release moment
}

local R15 = {
	waist = { "UpperTorso", "Waist" },
	root = { "LowerTorso", "Root" },
	neck = { "Head", "Neck" },
	rs = { "RightUpperArm", "RightShoulder" },
	re = { "RightLowerArm", "RightElbow" },
	ls = { "LeftUpperArm", "LeftShoulder" },
	le = { "LeftLowerArm", "LeftElbow" },
	rh = { "RightUpperLeg", "RightHip" },
	rk = { "RightLowerLeg", "RightKnee" },
	lh = { "LeftUpperLeg", "LeftHip" },
	lk = { "LeftLowerLeg", "LeftKnee" },
}
local R6 = {
	rs = { "Torso", "Right Shoulder" },
	ls = { "Torso", "Left Shoulder" },
	rh = { "Torso", "Right Hip" },
	lh = { "Torso", "Left Hip" },
	neck = { "Torso", "Neck" },
	root = { "HumanoidRootPart", "RootJoint" },
}

local jointCache: { [Model]: { [string]: JointRec } } = {}
local acts: { [Model]: Act } = {}
local balls: { [Model]: BasePart } = {}
local conn: RBXScriptConnection? = nil
local rad = math.rad

local function findJoints(char: Model): { [string]: JointRec }
	local cached = jointCache[char]
	if cached then
		local any = next(cached)
		if any == nil or (cached[any].motor.Parent ~= nil) then
			return cached
		end
	end
	local out: { [string]: JointRec } = {}
	local hum = char:FindFirstChildOfClass("Humanoid")
	local map = if hum and hum.RigType == Enum.HumanoidRigType.R6 then R6 else R15
	for key, def in map do
		local part = char:FindFirstChild(def[1])
		local m = part and part:FindFirstChild(def[2])
		if m and m:IsA("Motor6D") then
			out[key] = { motor = m, c0 = m.C0.Rotation, touched = false }
		end
	end
	jointCache[char] = out
	return out
end

-- pose: { [joint] = { pitch, yaw, roll, dy? } } in the parent frame
local function toTransform(rec: JointRec, p: { number }): CFrame
	local r = CFrame.fromEulerAnglesXYZ(rad(p[1] or 0), rad(p[2] or 0), rad(p[3] or 0))
	local t = rec.c0:Inverse() * r * rec.c0
	local dy = p[4]
	if dy and dy ~= 0 then
		t = rec.c0:Inverse() * CFrame.new(0, dy, 0) * rec.c0 * t
	end
	return t
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(t: number): number
	local u = math.clamp(t, 0, 1)
	return u * u * (3 - 2 * u)
end

-- Backswing / pushaway shoulder angle for an approach that started t seconds ago at power p.
local function approachArm(t: number, p: number): number
	if t < 0.22 then
		return lerp(45, 55, smooth(t / 0.22)) -- pushaway: ball out in front
	end
	local back = -(30 + 75 * p)
	return lerp(55, back, smooth((t - 0.22) / 0.45))
end

local POSE: { [string]: (a: Act, t: number) -> { [string]: { number } } } = {}

POSE.hold = function(_a, t)
	local breathe = math.sin(t * 2.2) * 2
	return {
		rs = { 48 + breathe, 0, 8 },
		re = { 80, 0, 0 },
		ls = { 40 + breathe, 0, -14 },
		le = { 75, 0, 0 },
		waist = { -4, 0, 0 },
	}
end

POSE.pickup = function(_a, t)
	local u = if t < 0.3 then smooth(t / 0.3) else 1 - smooth((t - 0.3) / 0.35)
	return {
		waist = { -38 * u, 0, 0 },
		neck = { -12 * u, 0, 0 },
		rs = { lerp(48, 30, u), 0, 6 },
		re = { lerp(80, 12, u), 0, 0 },
		ls = { 25, 0, -18 * u },
		root = { 0, 0, 0, -0.45 * u },
		rh = { 30 * u, 0, 0 },
		rk = { -45 * u, 0, 0 },
		lh = { 30 * u, 0, 0 },
		lk = { -45 * u, 0, 0 },
	}
end

POSE.approach = function(a, t)
	local p = a.power
	local arm = approachArm(t, p)
	local lean = -10 - 12 * p
	return {
		rs = { arm, 0, 6 },
		re = { if t < 0.22 then 40 else 8, 0, 0 },
		ls = { 22, 0, -50 - 10 * p },
		le = { 18, 0, 0 },
		waist = { lean, -6, 0 },
		neck = { -lean * 0.6, 4, 0 },
	}
end

POSE.release = function(a, t)
	-- 0 .. 0.32: forward swing + slide down; 0.32 .. dur: follow-through hold
	local u = smooth(t / 0.32)
	local arm = if t < 0.32 then lerp(a.from, 85, u) else lerp(85, 118, smooth((t - 0.32) / 0.35))
	local slide = smooth(t / 0.25)
	return {
		rs = { arm, 0, 4 },
		re = { lerp(8, 22, u), 0, 0 },
		ls = { 30, 0, -72 },
		le = { 12, 0, 0 },
		waist = { -26 * slide, -10, 0 },
		neck = { 18 * slide, 6, 0 },
		root = { 0, 0, 0, -0.55 * slide },
		lh = { 55 * slide, 0, 0 },
		lk = { -72 * slide, 0, 0 },
		rh = { -38 * slide, 0, 10 * slide },
		rk = { -28 * slide, 0, 0 },
	}
end

POSE.cheer = function(a, t)
	local hop = math.abs(math.sin(t * 7 + a.seed)) * 0.28
	local wave = math.sin(t * 9 + a.seed) * 8
	return {
		rs = { 168, 0, 18 + wave },
		ls = { 168, 0, -18 - wave },
		re = { 12, 0, 0 },
		le = { 12, 0, 0 },
		neck = { 14, 0, 0 },
		waist = { 6, 0, 0 },
		root = { 0, 0, 0, hop },
	}
end

POSE.pump = function(a, t)
	local pump = math.max(0, math.sin(t * 10 + a.seed)) * 28
	return {
		rs = { 70 + pump * 0.4, 0, 12 },
		re = { 115 - pump, 0, 0 },
		ls = { 10, 0, -22 },
		waist = { 9, 0, 0 },
		neck = { 12, 0, 0 },
		lh = { 8, 0, 0 },
	}
end

POSE.clap = function(a, t)
	local c = math.sin(t * 14 + a.seed) * 11
	return {
		rs = { 62, 0, -28 + c },
		ls = { 62, 0, 28 - c },
		re = { 58, 0, 0 },
		le = { 58, 0, 0 },
		neck = { 6, 0, 0 },
	}
end

POSE.sad = function(_a, t)
	local shake = math.sin(t * 6) * 8
	return {
		rs = { 150, 0, 34 },
		ls = { 150, 0, -34 },
		re = { 125, 0, 0 },
		le = { 125, 0, 0 },
		neck = { -22, shake, 0 },
		waist = { -12, 0, 0 },
	}
end

local DUR = { pickup = 0.65, release = 1.15, cheer = 1.7, pump = 1.4, clap = 1.6, sad = 1.7 }

local function resetJoints(char: Model)
	local joints = jointCache[char]
	if not joints then
		return
	end
	for _, rec in joints do
		if rec.touched and rec.motor.Parent then
			rec.motor.Transform = CFrame.identity
		end
		rec.touched = false
	end
end

local function step()
	local now = os.clock()
	for char, a in acts do
		if not char.Parent then
			acts[char] = nil
			jointCache[char] = nil
			continue
		end
		local t = now - a.t0
		if a.dur > 0 and t >= a.dur then
			acts[char] = nil
			resetJoints(char)
			-- a finished pickup / emote returns to the hold pose while the ball is in the hand
			local b = balls[char]
			if b and b.Parent and (a.kind == "pickup" or a.kind == "cheer" or a.kind == "pump" or a.kind == "clap" or a.kind == "sad") then
				Rig.play(char, "hold")
			end
			continue
		end
		local w = 1
		if a.fadeIn > 0 then
			w = math.min(w, smooth(t / a.fadeIn))
		end
		if a.dur > 0 and a.fadeOut > 0 then
			w = math.min(w, smooth((a.dur - t) / a.fadeOut))
		end
		if a.stopAt then
			local k = 1 - smooth((now - a.stopAt) / 0.22)
			w = math.min(w, k)
			if k <= 0 then
				acts[char] = nil
				resetJoints(char)
				continue
			end
		end
		local joints = findJoints(char)
		local pose = POSE[a.kind](a, t)
		for key, p in pose do
			local rec = joints[key]
			if rec then
				local target = toTransform(rec, p)
				local cur = rec.motor.Transform
				rec.motor.Transform = if w >= 0.999 then target else cur:Lerp(target, w)
				rec.touched = true
			end
		end
	end
	if next(acts) == nil and conn then
		conn:Disconnect()
		conn = nil
	end
end

local function ensureLoop()
	if not conn then
		conn = RunService.PreSimulation:Connect(step)
	end
end

function Rig.play(char: Model?, kind: string, power: number?)
	if not char or not POSE[kind] then
		return
	end
	local prev = acts[char]
	local from = 0
	if kind == "release" then
		from = if prev and prev.kind == "approach" then approachArm(os.clock() - prev.t0, prev.power) else -60
	end
	if prev then
		resetJoints(char)
	end
	acts[char] = {
		char = char,
		kind = kind,
		t0 = os.clock(),
		dur = DUR[kind] or 0,
		power = power or (prev and prev.power) or 0.5,
		fadeIn = if kind == "release" then 0 else 0.14,
		fadeOut = if kind == "release" then 0.3 else 0.22,
		stopAt = nil,
		seed = math.random() * 6,
		from = from,
	}
	ensureLoop()
end

function Rig.setPower(char: Model?, p: number)
	local a = char and acts[char]
	if a and a.kind == "approach" then
		a.power = math.clamp(p, 0, 1)
	end
end

function Rig.kind(char: Model?): string?
	local a = char and acts[char]
	return a and a.kind or nil
end

-- Fades the current motion out (0.22 s).
function Rig.stop(char: Model?)
	local a = char and acts[char]
	if a and not a.stopAt then
		a.stopAt = os.clock()
	end
end

-- The house ball in the right hand (client-local part, welded; Massless so it never affects the
-- owner's movement). Same colour for everyone watching.
function Rig.hold(char: Model?, color: Color3, diameter: number?)
	if not char then
		return
	end
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm") or char:FindFirstChild("HumanoidRootPart")
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local b = balls[char]
	if not (b and b.Parent ~= nil and b:FindFirstChild("HoldWeld")) then
		if b then
			b:Destroy()
		end
		local d = diameter or 0.72
		local p = Instance.new("Part")
		p.Name = "BowlingHeldBall"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(d, d, d)
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.3
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Anchored = false
		local off = if hand.Name == "RightHand" then CFrame.new(0, -0.38, -0.12) elseif hand.Name == "Right Arm" then CFrame.new(0, -1.25, -0.1) else CFrame.new(0.95, -0.6, -0.7)
		p.CFrame = hand.CFrame * off
		local w = Instance.new("Weld")
		w.Name = "HoldWeld"
		w.Part0 = hand
		w.Part1 = p
		w.C0 = off
		w.Parent = p
		p.Parent = char
		b = p
		balls[char] = p
	end
	(b :: BasePart).Color = color
	;(b :: BasePart).Transparency = 0
end

function Rig.drop(char: Model?)
	local b = char and balls[char]
	if b then
		b.Transparency = 1
	end
end

function Rig.holding(char: Model?): boolean
	local b = char and balls[char]
	return b ~= nil and b.Parent ~= nil and b.Transparency < 1
end

function Rig.release(char: Model?, power: number)
	Rig.play(char, "release", power)
end

function Rig.emote(char: Model?, kind: string)
	if char and (kind == "cheer" or kind == "pump" or kind == "clap" or kind == "sad") then
		-- never interrupt the bowler's own swing
		local a = acts[char]
		if a and (a.kind == "release" and os.clock() - a.t0 < 0.7) then
			return
		end
		Rig.play(char, kind)
	end
end

function Rig.forget(char: Model?)
	if not char then
		return
	end
	acts[char] = nil
	resetJoints(char)
	local b = balls[char]
	if b then
		b:Destroy()
	end
	balls[char] = nil
	jointCache[char] = nil
end

function Rig.clear()
	for char in acts do
		resetJoints(char)
	end
	table.clear(acts)
	for _, b in balls do
		b:Destroy()
	end
	table.clear(balls)
	table.clear(jointCache)
	if conn then
		conn:Disconnect()
		conn = nil
	end
end

function Rig.active(): boolean
	return next(acts) ~= nil
end

return Rig
