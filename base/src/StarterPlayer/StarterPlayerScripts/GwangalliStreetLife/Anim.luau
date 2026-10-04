-- GwangalliStreetLife/Anim: animation of the pedestrian rigs (GwangalliNPCLooks block R15 rigs).
--   * base loops (idle / walk / run / sit / dance) and one-shot gestures (wave / point / cheer /
--     laugh) are Roblox's own default R15 avatar animations, ids from ReplicatedStorage.GwangalliAnim
--     (the one animation table of the game). Tracks are loaded once per rig and kept with the pooled rig.
--   * procedural poses on top (Motor6D.C0 offsets, so they add to whatever animation plays): phone in
--     hand, taking a photo, chatting hands, eating, stretching, hands behind the back at a shop window,
--     thinking, guitar / painting / fishing, lying on a towel (the root is tilted by the agent).
--   * head look-at (Neck C0, clamped, smoothed) toward the player or a partner.
-- Cost: gestures / head turns are only stepped for close agents (Agent decides); C0 writes happen
-- only when a value changed.

local Anim = {}

local ctx: any
local AnimLib: any = nil
local animCache: { [string]: Animation } = {}

-- Asset ids come only from ReplicatedStorage.GwangalliAnim (Anim.IDS.R15, the game's one table of
-- Roblox's default R15 Animate animations); without that module the rigs simply do not animate.
-- our name -> { GwangalliAnim name, variant }
local NAMES = {
	idle = { "idle", 1 },
	idle2 = { "idle", 2 },
	walk = { "walk", 1 },
	run = { "run", 1 },
	sit = { "sit", 1 },
	wave = { "wave", 1 },
	point = { "point", 1 },
	cheer = { "cheer", 1 },
	laugh = { "laugh", 1 },
	dance = { "dance1", 1 },
	dance2 = { "dance2", 1 },
	dance3 = { "dance3", 1 },
}
local LOOPED = { idle = true, idle2 = true, walk = true, run = true, sit = true, dance = true, dance2 = true, dance3 = true }

local idCache: { [string]: string | false } = {}
local function idFor(name: string): string?
	local c = idCache[name]
	if c ~= nil then
		return if c then c else nil
	end
	local found: string? = nil
	if AnimLib and type(AnimLib.id) == "function" then
		local n = NAMES[name] or { name, 1 }
		local ok, v = pcall(AnimLib.id, n[1], "R15", n[2])
		if ok and type(v) == "string" and v ~= "" then
			found = v
		end
	end
	idCache[name] = found or false
	return found
end
Anim.idFor = idFor

local function animation(name: string): Animation?
	local a = animCache[name]
	if a then
		return a
	end
	local id = idFor(name)
	if not id then
		return nil
	end
	a = Instance.new("Animation")
	a.Name = "StreetLife_" .. name
	a.AnimationId = id
	animCache[name] = a
	return a
end

function Anim.init(context: any)
	ctx = context
	AnimLib = ctx.AnimLib
	-- 어깨빵 poses (knocked down / staggering / asleep on a bench) come from GwangalliBumpShared
	local B = ctx.BumpShared
	if B and type(B.POSE_CF) == "table" then
		for name, pose in B.POSE_CF do
			if Anim.POSES[name] == nil then
				Anim.POSES[name] = pose
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- per rig state
-------------------------------------------------------------------------------------------------
function Anim.setup(rig: any)
	if rig.anim then
		return rig.anim
	end
	local host = rig.model:FindFirstChildOfClass("AnimationController") or rig.model:FindFirstChildOfClass("Humanoid")
	local animator = host and host:FindFirstChildOfClass("Animator")
	rig.anim = {
		animator = animator,
		tracks = {},
		failed = {},
		base = nil :: string?,
		baseTrack = nil :: AnimationTrack?,
		baseSpeed = 1,
		gesture = nil :: AnimationTrack?,
		frozen = false,
		pose = nil :: string?,
		poseT = 0,
		neckYaw = 0,
		neckPitch = 0,
		wantYaw = 0,
		wantPitch = 0,
		c0 = {} :: { [string]: CFrame }, -- last written C0 per motor
	}
	return rig.anim
end

local function track(rig: any, name: string): AnimationTrack?
	local st = rig.anim
	local t = st.tracks[name]
	if t then
		return t
	end
	if st.failed[name] or not st.animator then
		return nil
	end
	if not rig.model:IsDescendantOf(workspace) then
		return nil -- Animator:LoadAnimation needs the rig in the DataModel
	end
	local a = animation(name)
	if not a then
		st.failed[name] = true
		return nil
	end
	local ok, res = pcall(function()
		return st.animator:LoadAnimation(a)
	end)
	if not ok or not res then
		st.failed[name] = true
		return nil
	end
	local tr = res :: AnimationTrack
	pcall(function()
		tr.Looped = LOOPED[name] == true
		if LOOPED[name] then
			tr.Priority = if name == "walk" or name == "run" then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Idle
		else
			tr.Priority = Enum.AnimationPriority.Action
		end
	end)
	st.tracks[name] = tr
	return tr
end

-- base loop: "idle" | "idle2" | "walk" | "run" | "sit" | "dance" | "dance2" | "dance3" | "none"
-- (fade: cross-fade seconds, default 0.25; randomPhase: start walk / run at a random point too)
function Anim.base(rig: any, name: string, speed: number?, fade: number?, randomPhase: boolean?)
	local st = rig.anim or Anim.setup(rig)
	local sp = speed or 1
	if st.frozen then
		st.base = name
		st.baseSpeed = sp
		return
	end
	if st.base == name and st.baseTrack then
		if math.abs(st.baseSpeed - sp) > 0.06 then
			st.baseSpeed = sp
			pcall(st.baseTrack.AdjustSpeed, st.baseTrack, sp)
		end
		return
	end
	local fd = fade or 0.25
	if st.baseTrack then
		pcall(st.baseTrack.Stop, st.baseTrack, fd)
		st.baseTrack = nil
	end
	st.base = name
	st.baseSpeed = sp
	if name == "none" then
		return
	end
	local tr = track(rig, name)
	if tr then
		st.baseTrack = tr
		pcall(function()
			tr:Play(fd, 1, sp)
			if randomPhase or (name ~= "walk" and name ~= "run") then
				local k = if randomPhase then math.random() else (rig.seed or 0) % 1
				tr.TimePosition = k * math.max(0.1, tr.Length)
			end
		end)
	end
end

-- one-shot gesture over the base loop: "wave" | "point" | "cheer" | "laugh"
function Anim.gesture(rig: any, name: string, speed: number?)
	local st = rig.anim or Anim.setup(rig)
	if st.frozen then
		return
	end
	local tr = track(rig, name)
	if not tr then
		return
	end
	if st.gesture and st.gesture ~= tr then
		pcall(st.gesture.Stop, st.gesture, 0.2)
	end
	st.gesture = tr
	pcall(tr.Play, tr, 0.2, 1, speed or 1)
end

function Anim.stopGesture(rig: any)
	local st = rig.anim
	if st and st.gesture then
		pcall(st.gesture.Stop, st.gesture, 0.2)
		st.gesture = nil
	end
end

-- off-screen and away from the player: stop every track (nobody sees the pose), start the base loop
-- again when the agent comes into view (0.2 s fade, a random phase so walkers never step in sync)
function Anim.freeze(rig: any, on: boolean)
	local st = rig.anim or Anim.setup(rig)
	if st.frozen == on then
		return
	end
	st.frozen = on
	if on then
		for _, tr in st.tracks do
			pcall(tr.Stop, tr, 0)
		end
		st.baseTrack = nil
		st.gesture = nil
	else
		local name, sp = st.base or "idle", st.baseSpeed or 1
		st.base = nil
		Anim.base(rig, name, sp, 0.2, true)
	end
end

function Anim.stopAll(rig: any)
	local st = rig.anim
	if not st then
		return
	end
	for _, tr in st.tracks do
		pcall(tr.Stop, tr, 0)
	end
	st.baseTrack = nil
	st.gesture = nil
	st.base = nil
end

-------------------------------------------------------------------------------------------------
-- procedural poses (C0 offsets on top of the animation)
-------------------------------------------------------------------------------------------------
local rad = math.rad
local ANG = CFrame.Angles
local IDENT = CFrame.identity

local function setC0(rig: any, motor: string, off: CFrame)
	local m = rig.motors[motor]
	if not m then
		return
	end
	local st = rig.anim
	local last = st.c0[motor]
	if last == off then
		return
	end
	if last and off ~= IDENT then
		-- skip tiny changes (angle between the two offsets)
		local d = last:ToObjectSpace(off)
		local _, ang = d:ToAxisAngle()
		if math.abs(ang) < 0.012 then
			return
		end
	end
	st.c0[motor] = off
	m.C0 = rig.rest[motor] * off
end

local POSE_MOTORS = { "RightShoulder", "RightElbow", "LeftShoulder", "LeftElbow", "Waist", "RightHip", "RightKnee", "LeftHip", "LeftKnee" }

local function clearPose(rig: any)
	for _, n in POSE_MOTORS do
		if rig.anim.c0[n] and rig.anim.c0[n] ~= IDENT then
			rig.anim.c0[n] = IDENT
			local m = rig.motors[n]
			if m then
				m.C0 = rig.rest[n]
			end
		end
	end
end

-- static part of each pose (animated poses add motion in Anim.step)
local POSES: { [string]: { [string]: CFrame } } = {
	phone = { RightShoulder = ANG(rad(52), 0, rad(-16)), RightElbow = ANG(rad(78), 0, 0) },
	photo = { RightShoulder = ANG(rad(96), 0, rad(-24)), RightElbow = ANG(rad(38), 0, 0), LeftShoulder = ANG(rad(96), 0, rad(24)), LeftElbow = ANG(rad(38), 0, 0) },
	chat = { RightShoulder = ANG(rad(22), 0, rad(-8)), RightElbow = ANG(rad(52), 0, 0) },
	eat = { RightShoulder = ANG(rad(24), 0, rad(-6)), RightElbow = ANG(rad(64), 0, 0) },
	stretch = { RightShoulder = ANG(rad(168), 0, rad(8)), LeftShoulder = ANG(rad(168), 0, rad(-8)) },
	think = { RightShoulder = ANG(rad(40), 0, rad(-28)), RightElbow = ANG(rad(128), 0, 0), LeftShoulder = ANG(rad(22), 0, rad(30)), LeftElbow = ANG(rad(70), 0, 0) },
	look = { RightShoulder = ANG(rad(-14), 0, rad(6)), RightElbow = ANG(rad(55), 0, 0), LeftShoulder = ANG(rad(-14), 0, rad(-6)), LeftElbow = ANG(rad(55), 0, 0) },
	guitar = { LeftShoulder = ANG(rad(48), 0, rad(34)), LeftElbow = ANG(rad(36), 0, 0), RightShoulder = ANG(rad(28), 0, rad(-18)), RightElbow = ANG(rad(62), 0, 0) },
	paint = { RightShoulder = ANG(rad(72), 0, rad(-6)), RightElbow = ANG(rad(24), 0, 0), LeftShoulder = ANG(rad(30), 0, rad(22)), LeftElbow = ANG(rad(60), 0, 0) },
	fish = { RightShoulder = ANG(rad(58), 0, rad(-12)), RightElbow = ANG(rad(30), 0, 0), LeftShoulder = ANG(rad(52), 0, rad(18)), LeftElbow = ANG(rad(40), 0, 0) },
	cheer = { RightShoulder = ANG(rad(160), 0, rad(14)), LeftShoulder = ANG(rad(160), 0, rad(-14)) },
	wait = { RightShoulder = ANG(rad(8), 0, rad(-4)), LeftShoulder = ANG(rad(8), 0, rad(4)) },
	lie = { RightShoulder = ANG(0, 0, rad(28)), LeftShoulder = ANG(0, 0, rad(-28)) },
	-- startled (a car / somebody walked into them): hands up in front of the chest
	startle = { RightShoulder = ANG(rad(118), 0, rad(-22)), RightElbow = ANG(rad(64), 0, 0), LeftShoulder = ANG(rad(118), 0, rad(22)), LeftElbow = ANG(rad(64), 0, 0), Waist = ANG(rad(-8), 0, 0) },
	-- selfie: phone held up and out in front
	selfie = { RightShoulder = ANG(rad(100), rad(-25), rad(-18)), RightElbow = ANG(rad(12), 0, 0) },
	-- hand in hand with the friend on that side (arms slightly out toward each other)
	handR = { RightShoulder = ANG(rad(10), 0, rad(14)) },
	handL = { LeftShoulder = ANG(rad(10), 0, rad(-14)) },
	-- hands in the pockets-ish / arms crossed while waiting in line
	cross = { RightShoulder = ANG(rad(38), rad(-30), rad(-12)), RightElbow = ANG(rad(96), 0, 0), LeftShoulder = ANG(rad(38), rad(30), rad(12)), LeftElbow = ANG(rad(96), 0, 0) },
	-- sitting on the sand: leaning back on the hands
	lean = { RightShoulder = ANG(rad(-30), 0, rad(-14)), RightElbow = ANG(rad(8), 0, 0), LeftShoulder = ANG(rad(-30), 0, rad(14)), LeftElbow = ANG(rad(8), 0, 0), Waist = ANG(rad(-10), 0, 0) },
	-- animated in Anim.step
	sway = {},
	clap = { RightShoulder = ANG(rad(52), 0, rad(-26)), RightElbow = ANG(rad(70), 0, 0), LeftShoulder = ANG(rad(52), 0, rad(26)), LeftElbow = ANG(rad(70), 0, 0) },
	wavep = { RightShoulder = ANG(rad(160), 0, rad(-18)), RightElbow = ANG(rad(24), 0, 0) },
	pointp = { RightShoulder = ANG(rad(88), rad(-8), rad(-6)), RightElbow = ANG(rad(4), 0, 0) },
	-- sit without the sit animation (fallback only): thighs forward, knees down
	sitfallback = { RightShoulder = ANG(rad(18), 0, 0), LeftShoulder = ANG(rad(18), 0, 0) },
}
Anim.POSES = POSES
local PHONE_POSES = { phone = true, photo = true, selfie = true }
local ANIMATED = { chat = true, eat = true, stretch = true, guitar = true, paint = true, think = false, sway = true, clap = true, wavep = true }
Anim.ANIMATED = ANIMATED

function Anim.pose(rig: any, name: string?)
	local st = rig.anim or Anim.setup(rig)
	if st.pose == name then
		return
	end
	st.pose = name
	st.poseT = 0
	clearPose(rig)
	if rig.phone then
		local show = name ~= nil and PHONE_POSES[name] == true
		rig.phone.Transparency = if show then 0 else 1
	end
	local p = name and POSES[name]
	if p then
		for motor, off in p do
			setC0(rig, motor, off)
		end
	end
	local neckBase = if name == "phone" then -0.32 elseif name == "look" then -0.08 else 0
	setC0(rig, "Neck", ANG(neckBase + st.neckPitch, st.neckYaw, 0))
end

-- leg poses (hip / knee C0 offsets, independent of the arm pose):
--   "ground" = sitting on the sand / a towel: thighs forward, legs almost straight (the chair sit
--   animation would push the shins through the ground); "chair" = sitting without a sit animation.
local LEGS = {
	ground = { hip = rad(86), knee = rad(-10), spread = rad(7) },
	chair = { hip = rad(90), knee = rad(-90), spread = 0 },
}
function Anim.legs(rig: any, name: string?)
	local st = rig.anim or Anim.setup(rig)
	if st.legs == name then
		return
	end
	st.legs = name
	local L = name and LEGS[name]
	for _, side in { "Left", "Right" } do
		local hip, knee = rig.motors[side .. "Hip"], rig.motors[side .. "Knee"]
		if hip and knee then
			if L then
				local sp = if side == "Left" then L.spread else -L.spread
				hip.C0 = rig.rest[side .. "Hip"] * ANG(L.hip, 0, sp)
				knee.C0 = rig.rest[side .. "Knee"] * ANG(L.knee, 0, 0)
			else
				hip.C0 = rig.rest[side .. "Hip"]
				knee.C0 = rig.rest[side .. "Knee"]
			end
		end
	end
end

-- a short procedural arm gesture (works while walking, unlike the full-body emote clips):
-- "wavep" | "pointp" | "clap" | "startle" | "selfie"; the previous pose comes back after dur s
function Anim.flash(rig: any, name: string, dur: number)
	local st = rig.anim or Anim.setup(rig)
	if st.flashUntil == nil then
		st.flashPrev = st.pose
	end
	st.flashUntil = os.clock() + dur
	Anim.pose(rig, name)
	st.poseFlash = name
end

-- restore after Anim.flash (called from Anim.step for close agents and from Agent.think for all)
function Anim.tick(rig: any, now: number)
	local st = rig.anim
	if st and st.flashUntil and now >= st.flashUntil then
		st.flashUntil = nil
		local prev = st.flashPrev
		st.flashPrev = nil
		if st.pose == st.poseFlash then
			Anim.pose(rig, prev)
		end
		st.poseFlash = nil
	end
end

-- drop a running flash (the agent starts something else: walking off a bench mid-stretch)
function Anim.cancelFlash(rig: any)
	local st = rig.anim
	if st and st.flashUntil then
		st.flashUntil, st.flashPrev, st.poseFlash = nil, nil, nil
	end
end

-- the pose to come back to (what Anim.flash will restore, else the current one)
function Anim.restPose(rig: any): string?
	local st = rig.anim
	if not st then
		return nil
	end
	if st.flashUntil then
		return st.flashPrev
	end
	return st.pose
end

-- set the pose that stays after a running flash (or now when none runs)
function Anim.setRestPose(rig: any, name: string?)
	local st = rig.anim or Anim.setup(rig)
	if st.flashUntil then
		st.flashPrev = name
		return
	end
	Anim.pose(rig, name)
end

-- head look target: yaw / pitch relative to the torso (radians), nil = straight ahead
function Anim.look(rig: any, yaw: number?, pitch: number?)
	local st = rig.anim or Anim.setup(rig)
	st.wantYaw = math.clamp(yaw or 0, -1.15, 1.15)
	st.wantPitch = math.clamp(pitch or 0, -0.5, 0.45)
end

-- per-frame procedural motion for close agents: animated poses + smoothed head turn
function Anim.step(rig: any, dt: number)
	local st = rig.anim
	if not st then
		return
	end
	st.poseT += dt
	local t = st.poseT + (rig.seed or 0) * 10
	local pose = st.pose
	if pose == "chat" then
		local s1, s2 = math.sin(t * 3.1), math.sin(t * 2.3 + 1)
		setC0(rig, "RightShoulder", ANG(rad(24 + 16 * s1), rad(8 * s2), rad(-10)))
		setC0(rig, "RightElbow", ANG(rad(56 + 22 * s2), 0, 0))
		if math.sin(t * 0.37) > 0.4 then
			setC0(rig, "LeftShoulder", ANG(rad(18 + 12 * s2), 0, rad(8)))
			setC0(rig, "LeftElbow", ANG(rad(48 + 18 * s1), 0, 0))
		else
			setC0(rig, "LeftShoulder", IDENT)
			setC0(rig, "LeftElbow", IDENT)
		end
	elseif pose == "eat" then
		local ph = (t % 3.6) / 3.6
		local up = if ph < 0.35 then math.sin(ph / 0.35 * math.pi) else 0
		setC0(rig, "RightShoulder", ANG(rad(24 + 50 * up), 0, rad(-6 - 16 * up)))
		setC0(rig, "RightElbow", ANG(rad(64 + 60 * up), 0, 0))
	elseif pose == "stretch" then
		local ph = (t % 7) / 7
		local k = if ph < 0.45 then 1 else math.max(0, 1 - (ph - 0.45) * 4)
		local sway = math.sin(t * 1.3) * 10 * k
		setC0(rig, "RightShoulder", ANG(rad(168 * k), 0, rad(8 + sway)))
		setC0(rig, "LeftShoulder", ANG(rad(168 * k), 0, rad(-8 + sway)))
		setC0(rig, "Waist", ANG(0, 0, rad(sway * 0.6)))
	elseif pose == "guitar" then
		setC0(rig, "RightElbow", ANG(rad(62 + 12 * math.sin(t * 9)), 0, 0))
	elseif pose == "paint" then
		setC0(rig, "RightShoulder", ANG(rad(72 + 6 * math.sin(t * 1.7)), rad(10 * math.sin(t * 1.1)), rad(-6)))
	elseif pose == "sway" then
		-- moving to the music in the queue
		local s1 = math.sin(t * 4.2)
		setC0(rig, "Waist", ANG(0, rad(7 * s1), rad(4 * math.sin(t * 2.1))))
		setC0(rig, "RightShoulder", ANG(rad(14 + 10 * s1), 0, rad(-6)))
		setC0(rig, "LeftShoulder", ANG(rad(14 - 10 * s1), 0, rad(6)))
	elseif pose == "clap" then
		local k = math.abs(math.sin(t * 7))
		setC0(rig, "RightShoulder", ANG(rad(52), 0, rad(-26 + 20 * k)))
		setC0(rig, "LeftShoulder", ANG(rad(52), 0, rad(26 - 20 * k)))
	elseif pose == "wavep" then
		setC0(rig, "RightElbow", ANG(rad(24), 0, rad(24 * math.sin(t * 9))))
	end
	if st.flashUntil and os.clock() >= st.flashUntil then
		Anim.tick(rig, os.clock())
	end
	-- head turn
	local ky = math.min(1, dt * 6)
	local ny = st.neckYaw + (st.wantYaw - st.neckYaw) * ky
	local np = st.neckPitch + (st.wantPitch - st.neckPitch) * ky
	if math.abs(ny - st.neckYaw) > 0.004 or math.abs(np - st.neckPitch) > 0.004 or (ny == 0 and st.neckYaw ~= 0) then
		st.neckYaw, st.neckPitch = ny, np
		local base = if pose == "phone" then -0.32 elseif pose == "look" then -0.08 else 0
		setC0(rig, "Neck", ANG(base + np, ny, 0))
	elseif pose == "phone" and not st.c0.Neck then
		setC0(rig, "Neck", ANG(-0.32, 0, 0))
	end
end

-- a walked dog's legs (GwangalliNPCLooks "dog"): a trot matching the owner's speed, legs back to rest
-- when the owner stops. Close agents only (Crowd), 4 C0 writes per frame while walking.
function Anim.dogStep(rig: any, dt: number, speed: number)
	local legs = rig.dogLegs
	if not legs then
		return
	end
	if speed > 0.3 then
		local t = (rig.dogT or 0) + dt * (4 + speed * 1.1)
		rig.dogT = t
		local amp = math.min(0.6, 0.18 + speed * 0.07)
		local rest, phase = rig.dogRest, rig.dogPhase
		for i, m in legs do
			m.C0 = rest[i] * ANG(math.sin(t + phase[i]) * amp, 0, 0)
		end
		rig.dogMoving = true
	elseif rig.dogMoving then
		rig.dogMoving = false
		for i, m in legs do
			m.C0 = rig.dogRest[i]
		end
	end
end

-- back to the rest pose (rig released to the pool)
function Anim.reset(rig: any)
	local st = rig.anim
	if rig.dogLegs and rig.dogMoving then
		rig.dogMoving = false
		for i, m in rig.dogLegs do
			m.C0 = rig.dogRest[i]
		end
	end
	if not st then
		return
	end
	Anim.stopAll(rig)
	for motor, off in st.c0 do
		if off ~= IDENT then
			local m = rig.motors[motor]
			if m then
				m.C0 = rig.rest[motor]
			end
		end
	end
	for _, side in { "Left", "Right" } do
		local hip, knee = rig.motors[side .. "Hip"], rig.motors[side .. "Knee"]
		if hip and knee then
			hip.C0 = rig.rest[side .. "Hip"]
			knee.C0 = rig.rest[side .. "Knee"]
		end
	end
	table.clear(st.c0)
	st.pose = nil
	st.legs = nil
	st.flashUntil, st.flashPrev, st.poseFlash = nil, nil, nil
	st.neckYaw, st.neckPitch, st.wantYaw, st.wantPitch = 0, 0, 0, 0
	st.frozen = false
	if rig.phone then
		rig.phone.Transparency = 1
	end
end

return Anim
