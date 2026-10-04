-- GwangalliAnim: THE animation library of 광안리 GTA (owner: npc_key). Everyone animating a person
-- uses it: the key NPCs (server NPC.luau + GwangalliNPCClient), the street pedestrians, the club crowd.
--
-- ANIMATION ASSETS: only Roblox's own default avatar animations (the values of the standard
-- `Animate` character script; Roblox-owned, usable in any game, nothing uploaded). ONE table:
-- Anim.IDS.R15[name] / Anim.IDS.R6[name] = { variant ids } (Anim.WEIGHTS: pick weights);
-- Anim.ID[name] = the R15 first-variant id (flat view, plus idle2), Anim.id(name, rig?, variant?).
--   idle walk run jump fall climb sit swim swimidle toolnone (the "holding something" arm)
--   wave point cheer laugh dance1 dance2 dance3 (dance = dance1)
--
-- TRACKS (Humanoid, AnimationController, Animator or the Model that holds one; tracks are cached
-- per Animator, so calling play() every frame is cheap and never reloads):
--   Anim.play(target, name | "rbxassetid://n", opts?) -> AnimationTrack?
--        opts = { fade = 0.2, speed = 1, weight = 1, looped = <default by name>, priority =
--        Enum.AnimationPriority (default by name), variant = n (else weighted random), offset =
--        0..1 random start (desyncs crowds; true = random) }
--   Anim.stop(target, name?, fade?)   Anim.stopAll(target, fade?)   Anim.isPlaying(target, name)
--   Anim.animator(target) -> Animator?   Anim.rigType(model) -> "R15" | "R6"   Anim.id(name, rig?)
--   Anim.preload(target, { names })  (loads tracks ahead, e.g. when a pooled rig is built)
--   Loading needs the rig inside the DataModel (Roblox rule): before that play() returns nil.
--
-- RIG CONTROLLER (procedural motion on top of the tracks; Motor6D.C0 offsets compose with the
-- animation's Transform, so a pose / gesture / look-at layers over idle or walk):
--   local ctl = Anim.rig(model)        -- one per model (cached, freed when the model is destroyed)
--   ctl:setAct(actName)                -- Anim.ACTS: base track + pose + gesture + prop hint in one go
--   ctl:setMoving(speed | nil)         -- walk / run track at a matching speed (nil = stand, act back)
--   ctl:pose(name | nil, fade?)        -- Anim.POSES (phone, phone_call, text, wipe, flyer_offer,
--                                          flyers_hold, guitar, camera, arms_crossed, hands_behind,
--                                          hands_front, clipboard, cup, shade_eyes, chop, flip,
--                                          whistle, hips, pockets, sit, sit_bench, lean, cook, tray ...)
--   ctl:gesture(name | nil)            -- Anim.GESTURES, continuous: talk, listen, wipe, strum, flip,
--                                          chop, nod, scroll, look_around, sway, clap, flyer, stir, cheer_arms
--   ctl:look(worldPos | nil)           -- head (and a little waist) turn toward a point, clamped
--   ctl:emote(name, opts?) -> seconds  -- one-shot: a track (wave, point, cheer, laugh, dance*) or a
--                                          procedural Anim.EMOTES (bow, nod, shake, shrug, think, shy,
--                                          clap, thumbs, facepalm, beckon, stop_hand, wave_small,
--                                          and the hand-overs give, receive, phone_show)
--   ctl:setAnimated(on)                -- LOD: false stops tracks and relaxes every joint (no writes)
--   ctl:relax()                        -- joints back to rest, procedural layers dropped (tracks play on)
--   ctl:setDetail(2 | 1 | 0)           -- LOD: 2 everything, 1 pose + emotes (no gestures / head turns),
--                                          0 base tracks only (procedural layers cleared, step no-ops)
--   ctl:step()                         -- advance procedural motion; call every rendered frame for
--                                          near rigs (or at a lower rate for far ones). Idempotent
--                                          within one frame, so two systems may step the same rig.
--   ctl:destroy()
--   Shortcuts: Anim.lookAt(model, pos), Anim.pose(model, name), Anim.gesture(model, name),
--   Anim.emote(model, name), Anim.act(model, act) (create the controller on demand).
--
-- RIGS: Anim.buildR15(opts) -> Model: a light block R15 (standard part / Motor6D names and pivots,
--   so the default R15 animations play on it), HumanoidRootPart anchored, every part non-colliding,
--   AnimationController + Animator (opts.humanoid = true: a Humanoid with EvaluateStateMachine off
--   instead). opts = { skin, shirt, sleeves ("short" | "long" | "none"), pants, shorts?, shoes,
--   build ("slim" | "avg" | "broad"), body ("f" | "m"), height (0.85..1.15), name, face? }.
--   Anim.R15 = the layout (sizes / joint heights) for code that dresses the rig.
--   Anim.solve(model) positions the parts of an anchored-root rig from its joints (Studio edit
--   mode, offline renders); not needed at runtime (the engine solves Motor6Ds).
--
-- Plain module: no yields, no instances at require time; safe on server and client.

local Anim = {}
Anim.VERSION = 1

-------------------------------------------------------------------------------------------------
-- Asset ids (the standard Animate script values)
-------------------------------------------------------------------------------------------------
Anim.IDS = {
	R15 = {
		idle = { "rbxassetid://507766666", "rbxassetid://507766951", "rbxassetid://507766388" },
		walk = { "rbxassetid://507777826" },
		run = { "rbxassetid://507767714" },
		jump = { "rbxassetid://507765000" },
		fall = { "rbxassetid://507767968" },
		climb = { "rbxassetid://507765644" },
		sit = { "rbxassetid://2506281703" },
		swim = { "rbxassetid://507784897" },
		swimidle = { "rbxassetid://507785072" },
		toolnone = { "rbxassetid://507768375" },
		wave = { "rbxassetid://507770239" },
		point = { "rbxassetid://507770453" },
		cheer = { "rbxassetid://507770677" },
		laugh = { "rbxassetid://507770818" },
		dance1 = { "rbxassetid://507771019", "rbxassetid://507771955", "rbxassetid://507772104" },
		dance2 = { "rbxassetid://507776043", "rbxassetid://507776720", "rbxassetid://507776879" },
		dance3 = { "rbxassetid://507777268", "rbxassetid://507777451", "rbxassetid://507777623" },
	},
	R6 = {
		idle = { "rbxassetid://180435571", "rbxassetid://180435792" },
		walk = { "rbxassetid://180426354" },
		run = { "rbxassetid://180426354" },
		jump = { "rbxassetid://125750702" },
		fall = { "rbxassetid://180436148" },
		climb = { "rbxassetid://180436334" },
		sit = { "rbxassetid://178130996" },
		toolnone = { "rbxassetid://182393478" },
		wave = { "rbxassetid://128777973" },
		point = { "rbxassetid://128853357" },
		cheer = { "rbxassetid://129423030" },
		laugh = { "rbxassetid://129423131" },
		dance1 = { "rbxassetid://182435998", "rbxassetid://182491037", "rbxassetid://182491065" },
		dance2 = { "rbxassetid://182436842", "rbxassetid://182491248", "rbxassetid://182491277" },
		dance3 = { "rbxassetid://182436935", "rbxassetid://182491368", "rbxassetid://182491423" },
	},
}
-- Pick weights per variant (the Animate script's: the long breathing idle is the usual one).
Anim.WEIGHTS = {
	R15 = { idle = { 1, 1, 9 } },
	R6 = { idle = { 9, 1 } },
}
Anim.ALIASES = { dance = "dance1", swim_idle = "swimidle", hold = "toolnone", tool = "toolnone" }
-- Flat view (R15, first variant) for simple readers: Anim.ID.walk == "rbxassetid://507777826";
-- idle2 = the second idle ("look around"), dance = dance1. Derived from IDS (never edit it by hand).
Anim.ID = {} :: { [string]: string }
for name, list in Anim.IDS.R15 do
	Anim.ID[name] = list[1]
end
Anim.ID.idle2 = Anim.IDS.R15.idle[2]
Anim.ID.dance = Anim.IDS.R15.dance1[1]

local LOOPED = { idle = true, walk = true, run = true, climb = true, sit = true, swim = true, swimidle = true, toolnone = true, dance1 = true, dance2 = true, dance3 = true }
Anim.LOOPED = LOOPED
-- Speed (studs / s) at which the walk / run clip's feet match the ground at AdjustSpeed(1).
Anim.WALK_CLIP_SPEED = 7.2
Anim.RUN_CLIP_SPEED = 16

local function priorityOf(name: string): any
	local P = Enum.AnimationPriority
	if name == "idle" or name == "sit" or name == "swimidle" then
		return P.Idle
	elseif name == "walk" or name == "run" or name == "swim" or name == "climb" or string.sub(name, 1, 5) == "dance" then
		return P.Movement
	elseif name == "toolnone" or name == "jump" or name == "fall" then
		return P.Action
	end
	return P.Action2 -- emotes (wave, point, cheer, laugh, raw ids)
end

-------------------------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------------------------
local rng = Random.new()

local function isA(x: any, class: string): boolean
	return typeof(x) == "Instance" and x:IsA(class)
end

function Anim.rigType(model: Instance?): string
	if model and model:FindFirstChild("UpperTorso") then
		return "R15"
	end
	if model and model:FindFirstChild("Torso") then
		return "R6"
	end
	if model then
		local h = model:FindFirstChildOfClass("Humanoid")
		if h and h.RigType == Enum.HumanoidRigType.R6 then
			return "R6"
		end
	end
	return "R15"
end

local function modelOf(target: any): Instance?
	if typeof(target) ~= "Instance" then
		return nil
	end
	if target:IsA("Model") then
		return target
	end
	if target:IsA("Animator") then
		local p = target.Parent
		return p and p.Parent
	end
	return target.Parent
end

-- Animator of a Humanoid / AnimationController / Animator / Model (created when missing).
function Anim.animator(target: any): Animator?
	if typeof(target) ~= "Instance" then
		return nil
	end
	if target:IsA("Animator") then
		return target
	end
	local host: Instance? = nil
	if target:IsA("Humanoid") or target:IsA("AnimationController") then
		host = target
	elseif target:IsA("Model") then
		host = target:FindFirstChildOfClass("Humanoid") or target:FindFirstChildOfClass("AnimationController")
	end
	if not host then
		return nil
	end
	local a = host:FindFirstChildOfClass("Animator")
	if not a then
		a = Instance.new("Animator")
		a.Parent = host
	end
	return a
end

local function resolveName(name: string): string
	return Anim.ALIASES[name] or name
end

-- Asset id for `name` (variant n, else the first). Raw "rbxassetid://" / number ids pass through.
function Anim.id(name: any, rig: string?, variant: number?): string?
	if type(name) == "number" then
		return "rbxassetid://" .. string.format("%d", name)
	end
	if type(name) ~= "string" then
		return nil
	end
	if string.find(name, "://", 1, true) then
		return name
	end
	local set = Anim.IDS[rig or "R15"] or Anim.IDS.R15
	local list = set[resolveName(name)]
	if not list then
		return nil
	end
	return list[math.clamp(variant or 1, 1, #list)]
end

local function pickVariant(rig: string, name: string, variant: number?, seed: number?): number
	local set = Anim.IDS[rig] or Anim.IDS.R15
	local list = set[name]
	if not list or #list <= 1 then
		return 1
	end
	if variant then
		return math.clamp(variant, 1, #list)
	end
	local weights = Anim.WEIGHTS[rig] and Anim.WEIGHTS[rig][name]
	local r = if seed then (seed % 1000) / 1000 else rng:NextNumber()
	if not weights then
		return 1 + math.floor(r * #list) % #list
	end
	local total = 0
	for i = 1, #list do
		total += weights[i] or 1
	end
	local acc = 0
	for i = 1, #list do
		acc += (weights[i] or 1) / total
		if r < acc then
			return i
		end
	end
	return #list
end

local animObjects: { [string]: Animation } = {}
local function animObject(id: string): Animation
	local a = animObjects[id]
	if not a then
		a = Instance.new("Animation")
		a.Name = "GwangalliAnim"
		a.AnimationId = id
		animObjects[id] = a
	end
	return a
end

-- Track cache: animator -> key -> track (weak keys: destroyed rigs are collected).
local trackCache: { [Animator]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any

local function loadTrack(animator: Animator, key: string, id: string, name: string): AnimationTrack?
	local cache = trackCache[animator]
	if not cache then
		cache = {}
		trackCache[animator] = cache
	end
	local t = cache[key]
	if t then
		return t
	end
	if not animator:IsDescendantOf(game) then
		return nil -- LoadAnimation outside the DataModel errors in Roblox
	end
	local ok, res = pcall(animator.LoadAnimation, animator, animObject(id))
	if not ok or not res then
		return nil
	end
	local track = res :: AnimationTrack
	pcall(function()
		track.Priority = priorityOf(name)
		track.Looped = LOOPED[name] == true
	end)
	cache[key] = track
	return track
end

-- Loads (cached) the track for `name` on `target`. Returns track, resolved name, variant.
function Anim.load(target: any, name: any, variant: number?, seed: number?): (AnimationTrack?, string?)
	local animator = Anim.animator(target)
	if not animator then
		return nil, nil
	end
	local model = modelOf(animator)
	local rig = Anim.rigType(model)
	if type(name) == "number" or (type(name) == "string" and string.find(name, "://", 1, true)) then
		local id = Anim.id(name) :: string
		return loadTrack(animator, id, id, "raw"), "raw"
	end
	if type(name) ~= "string" then
		return nil, nil
	end
	local n = resolveName(name)
	local set = Anim.IDS[rig] or Anim.IDS.R15
	if not set[n] then
		return nil, nil
	end
	local v = pickVariant(rig, n, variant, seed)
	local id = set[n][v]
	return loadTrack(animator, n .. "#" .. v, id, n), n
end

function Anim.preload(target: any, names: { string })
	for _, n in names do
		Anim.load(target, n, 1)
	end
end

function Anim.play(target: any, name: any, opts: any?): AnimationTrack?
	local o = opts or {}
	local track, n = Anim.load(target, name, o.variant, o.seed)
	if not track then
		return nil
	end
	pcall(function()
		if o.priority then
			track.Priority = o.priority
		end
		if o.looped ~= nil then
			track.Looped = o.looped
		elseif n and n ~= "raw" then
			track.Looped = LOOPED[n] == true
		end
		if not track.IsPlaying then
			track:Play(o.fade or 0.2, o.weight or 1, o.speed or 1)
			if o.offset then
				local len = track.Length
				if len and len > 0 then
					local f = if type(o.offset) == "number" then o.offset else rng:NextNumber()
					track.TimePosition = (f % 1) * len
				end
			end
		else
			if o.weight then
				track:AdjustWeight(o.weight, o.fade or 0.2)
			end
		end
		if o.speed then
			track:AdjustSpeed(o.speed)
		end
	end)
	return track
end

function Anim.stop(target: any, name: any?, fade: number?)
	local animator = Anim.animator(target)
	local cache = animator and trackCache[animator]
	if not cache then
		return
	end
	local n = if type(name) == "string" and not string.find(name, "://", 1, true) then resolveName(name) else name
	for key, t in cache do
		if n == nil or key == n or string.sub(key, 1, #tostring(n) + 1) == tostring(n) .. "#" then
			if t.IsPlaying then
				pcall(t.Stop, t, fade or 0.2)
			end
		end
	end
end

function Anim.stopAll(target: any, fade: number?)
	Anim.stop(target, nil, fade)
end

function Anim.isPlaying(target: any, name: string): boolean
	local animator = Anim.animator(target)
	local cache = animator and trackCache[animator]
	if not cache then
		return false
	end
	local n = resolveName(name)
	for key, t in cache do
		if (key == n or string.sub(key, 1, #n + 1) == n .. "#") and t.IsPlaying then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- Procedural layer data. Angles in DEGREES in the parent part's space about the joint pivot.
-- Limbs: { pitch, yaw, roll } applied as CFrame.Angles (X then Y then Z): pitch > 0 raises an arm /
-- thigh forward and bends an elbow (knees bend with pitch < 0); roll > 0 swings a limb toward +X
-- (outward for RIGHT limbs, inward for left ones); yaw spins the limb about the vertical axis
-- (right arm +90 / left arm -90 turn the elbow bend inward: hands behind the back / clasped in front).
-- Neck / Waist / Root: { pitch (up +), yaw (left +), roll } as fromEulerAnglesYXZ; entries may carry a
-- translation { p, y, r, dx, dy, dz } (Root dy < 0 lowers the body onto a seat).
-------------------------------------------------------------------------------------------------
local JOINT_NAMES = { "Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }
Anim.JOINT_NAMES = JOINT_NAMES
local R6_JOINT = { Root = "RootJoint", Neck = "Neck", LeftShoulder = "Left Shoulder", RightShoulder = "Right Shoulder", LeftHip = "Left Hip", RightHip = "Right Hip" }
local YXZ_JOINT = { Root = true, Waist = true, Neck = true }

Anim.POSES = {
	none = {},
	phone = { RightShoulder = { 28, 0, -10 }, RightElbow = { 88, 0, 0 }, RightWrist = { -12, 0, 0 }, LeftShoulder = { 4, 0, 4 }, Neck = { -24, 0, 0 } },
	text = { RightShoulder = { 26, 0, -14 }, RightElbow = { 88, 0, 0 }, LeftShoulder = { 26, 0, 14 }, LeftElbow = { 88, 0, 0 }, Neck = { -26, 0, 0 } },
	phone_call = { RightShoulder = { 30, 80, 12 }, RightElbow = { 150, 0, 0 }, Neck = { 0, 0, 8 } },
	wipe = { RightShoulder = { 52, 0, -6 }, RightElbow = { 32, 0, 0 }, LeftShoulder = { 20, 0, 6 }, LeftElbow = { 30, 0, 0 }, Neck = { -18, 0, 0 }, Waist = { -8, 0, 0 } },
	cook = { RightShoulder = { 40, 0, -8 }, RightElbow = { 55, 0, 0 }, LeftShoulder = { 38, 0, 8 }, LeftElbow = { 55, 0, 0 }, Neck = { -22, 0, 0 }, Waist = { -6, 0, 0 } },
	flip = { RightShoulder = { 42, 0, -6 }, RightElbow = { 50, 0, 0 }, LeftShoulder = { 30, 0, 10 }, LeftElbow = { 60, 0, 0 }, Neck = { -20, 0, 0 } },
	chop = { RightShoulder = { 40, 0, -4 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 34, 0, 10 }, LeftElbow = { 50, 0, 0 }, Neck = { -24, 0, 0 }, Waist = { -8, 0, 0 } },
	flyer_offer = { RightShoulder = { 78, 0, -4 }, RightElbow = { 12, 0, 0 }, LeftShoulder = { 30, 0, 12 }, LeftElbow = { 84, 0, 0 }, Waist = { -4, 0, 0 } },
	flyers_hold = { LeftShoulder = { 30, 0, 12 }, LeftElbow = { 84, 0, 0 } },
	guitar = { LeftShoulder = { 52, 0, -38 }, LeftElbow = { 58, 0, 0 }, RightShoulder = { 26, 0, -24 }, RightElbow = { 78, 0, 0 }, Neck = { -14, 10, 0 } },
	camera = { RightShoulder = { 74, 0, -22 }, RightElbow = { 118, 0, 0 }, LeftShoulder = { 74, 0, 22 }, LeftElbow = { 118, 0, 0 }, Neck = { -4, 0, 0 } },
	arms_crossed = { RightShoulder = { 40, 90, 0 }, RightElbow = { 112, 0, 0 }, LeftShoulder = { 46, -90, 0 }, LeftElbow = { 108, 0, 0 } },
	hands_behind = { RightShoulder = { -38, 90, 0 }, RightElbow = { 78, 0, 0 }, LeftShoulder = { -38, -90, 0 }, LeftElbow = { 78, 0, 0 } },
	hands_front = { RightShoulder = { 30, 90, 0 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 30, -90, 0 }, LeftElbow = { 70, 0, 0 } },
	clipboard = { LeftShoulder = { 34, 0, 10 }, LeftElbow = { 86, 0, 0 }, RightShoulder = { 30, 0, -12 }, RightElbow = { 70, 0, 0 }, Neck = { -18, 0, 0 } },
	cup = { RightShoulder = { 16, 0, -6 }, RightElbow = { 86, 0, 0 } },
	tray = { LeftShoulder = { 22, 0, 8 }, LeftElbow = { 88, 0, 0 } },
	shade_eyes = { RightShoulder = { 118, 0, -8 }, RightElbow = { 96, 0, 0 }, Neck = { 4, 0, 0 } },
	whistle = { RightShoulder = { 96, 70, 0 }, RightElbow = { 120, 0, 0 } },
	hips = { RightShoulder = { 0, 0, 30 }, RightElbow = { 0, 0, -100 }, LeftShoulder = { 0, 0, -30 }, LeftElbow = { 0, 0, 100 } },
	pockets = { RightShoulder = { -8, 0, 4 }, RightElbow = { 22, 0, 0 }, LeftShoulder = { -8, 0, -4 }, LeftElbow = { 22, 0, 0 } },
	lean = { Waist = { 0, 0, 5 }, Neck = { 0, 0, -4 }, RightHip = { 4, 0, 4 }, LeftHip = { -2, 0, -2 }, LeftKnee = { -10, 0, 0 } },
	point_fwd = { RightShoulder = { 88, 10, 0 }, RightElbow = { 6, 0, 0 } },
	stop_hand = { RightShoulder = { 82, 0, -6 }, RightElbow = { 38, 0, 0 }, RightWrist = { -60, 0, 0 } },
	sit = { Root = { 0, 0, 0, 0, -1.25, 0 }, RightHip = { 90, 0, 0 }, LeftHip = { 90, 0, 0 }, RightKnee = { -88, 0, 0 }, LeftKnee = { -88, 0, 0 }, RightShoulder = { 18, 0, -4 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 18, 0, 4 }, LeftElbow = { 30, 0, 0 } },
	sit_bench = { Root = { 0, 0, 0, 0, -1.25, 0.15 }, RightHip = { 88, 0, 4 }, LeftHip = { 88, 0, -4 }, RightKnee = { -84, 0, 0 }, LeftKnee = { -84, 0, 0 }, RightShoulder = { 14, 0, -2 }, RightElbow = { 36, 0, 0 }, LeftShoulder = { 14, 0, 2 }, LeftElbow = { 36, 0, 0 }, Neck = { -4, 0, 0 } },
	sit_phone = { Root = { 0, 0, 0, 0, -1.25, 0.15 }, RightHip = { 88, 0, 4 }, LeftHip = { 88, 0, -4 }, RightKnee = { -84, 0, 0 }, LeftKnee = { -84, 0, 0 }, RightShoulder = { 30, 0, -12 }, RightElbow = { 92, 0, 0 }, LeftShoulder = { 20, 0, 8 }, LeftElbow = { 60, 0, 0 }, Neck = { -26, 0, 0 } },
	squat = { Root = { 0, 0, 0, 0, -1.1, 0 }, RightHip = { 110, 0, 6 }, LeftHip = { 110, 0, -6 }, RightKnee = { -130, 0, 0 }, LeftKnee = { -130, 0, 0 }, Waist = { -16, 0, 0 } },
	sunbathe = { Root = { -84, 0, 0, 0, -2.2, 0 }, RightShoulder = { 160, 0, 20 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 160, 0, -20 }, LeftElbow = { 110, 0, 0 } },
	fish = { RightShoulder = { 60, 0, -12 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 50, 0, 14 }, LeftElbow = { 50, 0, 0 }, Neck = { -6, 0, 0 } },
	paint = { RightShoulder = { 70, 0, -4 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 26, 0, 12 }, LeftElbow = { 80, 0, 0 }, Neck = { -6, 0, 0 } },
	stretch = { RightShoulder = { 170, 0, 8 }, LeftShoulder = { 170, 0, -8 }, Neck = { 10, 0, 0 } },
	guard = { RightShoulder = { 20, 90, 0 }, RightElbow = { 64, 0, 0 }, LeftShoulder = { 22, -90, 0 }, LeftElbow = { 64, 0, 0 }, Neck = { 2, 0, 0 } },
	bow = { Waist = { -32, 0, 0 }, Neck = { -10, 0, 0 }, RightShoulder = { 30, 90, 0 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 30, -90, 0 }, LeftElbow = { 60, 0, 0 } },
	-- 어깨빵 (GwangalliBumpShared.POSES, kept in sync): knocked down / staggering / asleep on a bench
	knock = { RightShoulder = { 28, 0, 78 }, RightElbow = { 24, 0, 0 }, LeftShoulder = { 36, 0, -70 }, LeftElbow = { 30, 0, 0 }, Waist = { -8, 0, 0 }, Neck = { -16, 0, 0 }, RightHip = { 22, 0, 14 }, RightKnee = { -32, 0, 0 }, LeftHip = { -6, 0, -12 }, LeftKnee = { -14, 0, 0 } },
	stagger = { RightShoulder = { 18, 0, 58 }, RightElbow = { 22, 0, 0 }, LeftShoulder = { 34, 0, -42 }, LeftElbow = { 34, 0, 0 }, Waist = { 0, 0, 12 }, Neck = { 6, 0, -8 } },
	nap = { RightShoulder = { 20, 0, 70 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 10, 0, -20 }, LeftElbow = { 40, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -60, 0, 0 }, LeftHip = { 10, 0, 0 }, LeftKnee = { -20, 0, 0 }, Neck = { 10, 0, 20 } },
}

-- Gestures: continuous additive motion. fn(t, phase, out) writes { p, y, r } offsets into out[joint].
local function wave(t: number, f: number, ph: number): number
	return math.sin((t * f + ph) * math.pi * 2)
end
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
Anim.GESTURES = {
	talk = function(t, ph, out)
		-- lively hands while speaking: alternate hands, rhythmic little beats, a head that bobs
		local a = wave(t, 0.55, ph)
		local b = wave(t, 0.8, ph + 0.3)
		local beat = math.max(0, wave(t, 1.7, ph)) ^ 2
		setJ(out, "RightShoulder", 18 + 14 * math.max(0, a) + 6 * beat, 0, -6 - 8 * math.max(0, a))
		setJ(out, "RightElbow", 40 + 30 * math.max(0, a) + 10 * beat, 0, 0)
		setJ(out, "RightWrist", -10 * beat, 0, 0)
		setJ(out, "LeftShoulder", 12 + 12 * math.max(0, -a), 0, 5 + 6 * math.max(0, -a))
		setJ(out, "LeftElbow", 30 + 26 * math.max(0, -a), 0, 0)
		setJ(out, "Neck", 3 * b + 2 * beat, 5 * wave(t, 0.23, ph), 2 * wave(t, 0.31, ph))
		setJ(out, "Waist", 0, 3 * wave(t, 0.2, ph), 0)
	end,
	listen = function(t, ph, out)
		setJ(out, "Neck", -3 + 4 * math.max(0, wave(t, 0.4, ph)) ^ 4, 0, 5 * wave(t, 0.09, ph))
		setJ(out, "Waist", 0, 0, 1.5 * wave(t, 0.12, ph))
	end,
	wipe = function(t, ph, out)
		local c, s = math.cos((t * 0.9 + ph) * math.pi * 2), math.sin((t * 0.9 + ph) * math.pi * 2)
		setJ(out, "RightShoulder", 8 * s, 14 * c, 0)
		setJ(out, "RightElbow", 12 * c, 0, 0)
		setJ(out, "Waist", 0, 3 * c, 0)
	end,
	stir = function(t, ph, out)
		local c, s = math.cos((t * 0.7 + ph) * math.pi * 2), math.sin((t * 0.7 + ph) * math.pi * 2)
		setJ(out, "RightShoulder", 6 * s, 8 * c, 0)
		setJ(out, "RightElbow", 8 * c, 0, 0)
	end,
	strum = function(t, ph, out)
		local s = wave(t, 3.2, ph)
		setJ(out, "RightElbow", 14 * s, 0, 0)
		setJ(out, "RightShoulder", 4 * s, 0, 0)
		setJ(out, "LeftElbow", 4 * wave(t, 0.5, ph), 0, 0)
		setJ(out, "Neck", 3 * wave(t, 1.1, ph), 4 * wave(t, 0.13, ph), 0)
		setJ(out, "Waist", 0, 0, 2.5 * wave(t, 0.55, ph))
	end,
	flip = function(t, ph, out)
		local k = ((t * 0.6 + ph) % 1)
		local flick = if k < 0.18 then math.sin(k / 0.18 * math.pi) else 0
		setJ(out, "RightElbow", 30 * flick, 0, 0)
		setJ(out, "RightWrist", -50 * flick, 0, 0)
		setJ(out, "LeftElbow", 6 * wave(t, 0.3, ph), 0, 0)
	end,
	chop = function(t, ph, out)
		local s = math.max(0, wave(t, 2.6, ph))
		setJ(out, "RightElbow", 28 * s, 0, 0)
		setJ(out, "RightShoulder", 6 * s, 0, 0)
	end,
	nod = function(t, ph, out)
		setJ(out, "Neck", 7 * wave(t, 1.6, ph), 0, 0)
	end,
	scroll = function(t, ph, out)
		local k = ((t * 0.45 + ph) % 1)
		local flick = if k < 0.12 then math.sin(k / 0.12 * math.pi) else 0
		setJ(out, "RightWrist", -14 * flick, 0, 0)
		setJ(out, "Neck", -2 * flick, 4 * wave(t, 0.07, ph), 0)
	end,
	look_around = function(t, ph, out)
		local s = math.sin((t * 0.11 + ph) * math.pi * 2)
		local hold = math.sign(s) * math.min(1, math.abs(s) * 1.8)
		setJ(out, "Neck", 3 * wave(t, 0.17, ph), 38 * hold, 0)
		setJ(out, "Waist", 0, 8 * hold, 0)
	end,
	sway = function(t, ph, out)
		local s = wave(t, 0.5, ph)
		setJ(out, "Waist", 0, 0, 5 * s)
		setJ(out, "Neck", 0, 0, -3 * s)
		setJ(out, "RightShoulder", 0, 0, 6 + 4 * s)
		setJ(out, "LeftShoulder", 0, 0, -6 + 4 * s)
	end,
	clap = function(t, ph, out)
		local s = math.max(0, wave(t, 2.4, ph))
		setJ(out, "RightShoulder", 50, 70, 0)
		setJ(out, "LeftShoulder", 50, -70, 0)
		setJ(out, "RightElbow", 40 + 26 * s, 0, 0)
		setJ(out, "LeftElbow", 40 + 26 * s, 0, 0)
	end,
	flyer = function(t, ph, out)
		-- offering the flyer: the arm reaches out and back every few seconds
		local k = ((t * 0.28 + ph) % 1)
		local reach = if k < 0.5 then math.sin(k / 0.5 * math.pi) else 0
		setJ(out, "RightShoulder", 70 * reach, 0, -4 * reach)
		setJ(out, "RightElbow", -20 * reach + 30 * (1 - reach), 0, 0)
		setJ(out, "Neck", -4 * reach, 0, 0)
		setJ(out, "Waist", -5 * reach, 0, 0)
	end,
	cheer_arms = function(t, ph, out)
		local s = wave(t, 1.8, ph)
		setJ(out, "RightShoulder", 150 + 12 * s, 0, 14)
		setJ(out, "LeftShoulder", 150 - 12 * s, 0, -14)
	end,
	breathe = function(t, ph, out)
		setJ(out, "Waist", 1.2 * wave(t, 0.25, ph), 0, 0)
	end,
	whistle = function(t, ph, out)
		local k = ((t * 0.2 + ph) % 1)
		local blow = if k < 0.25 then 1 else 0
		setJ(out, "RightShoulder", 96 * blow, 70 * blow, 0)
		setJ(out, "RightElbow", 120 * blow, 0, 0)
		setJ(out, "Neck", 6 * blow, 0, 0)
	end,
	shade = function(t, ph, out)
		local k = ((t * 0.08 + ph) % 1)
		local up = math.clamp(math.sin(k * math.pi * 2) * 2, 0, 1)
		setJ(out, "RightShoulder", 118 * up, 0, -8 * up)
		setJ(out, "RightElbow", 96 * up, 0, 0)
		setJ(out, "Neck", 4 * up, 30 * wave(t, 0.05, ph) * up, 0)
	end,
}

-- One-shot procedural emotes: { dur, fn(u 0..1, out) } (u = progress; the envelope is built in).
local function env(u: number): number
	if u < 0.15 then
		return u / 0.15
	elseif u > 0.8 then
		return math.max(0, (1 - u) / 0.2)
	end
	return 1
end
Anim.EMOTES = {
	bow = { 1.4, function(u, out)
		local e = env(u)
		setJ(out, "Waist", -34 * e, 0, 0)
		setJ(out, "Neck", -12 * e, 0, 0)
		setJ(out, "RightShoulder", 26 * e, 90 * e, 0)
		setJ(out, "RightElbow", 56 * e, 0, 0)
		setJ(out, "LeftShoulder", 26 * e, -90 * e, 0)
		setJ(out, "LeftElbow", 56 * e, 0, 0)
	end },
	nod = { 0.9, function(u, out)
		setJ(out, "Neck", -14 * math.sin(u * math.pi * 2) * env(u), 0, 0)
	end },
	shake = { 1.1, function(u, out)
		local e = env(u)
		setJ(out, "Neck", -4 * e, 24 * math.sin(u * math.pi * 6) * e, 0)
		setJ(out, "RightShoulder", 30 * e, 0, -10 * e)
		setJ(out, "RightElbow", 70 * e, 0, 0)
		setJ(out, "RightWrist", -40 * e, 0, 0)
	end },
	shrug = { 1.2, function(u, out)
		local e = env(u)
		setJ(out, "RightShoulder", 20 * e, 0, 26 * e)
		setJ(out, "LeftShoulder", 20 * e, 0, -26 * e)
		setJ(out, "RightElbow", 80 * e, 0, 0)
		setJ(out, "LeftElbow", 80 * e, 0, 0)
		setJ(out, "Neck", 0, 0, 10 * e)
	end },
	think = { 2.2, function(u, out)
		local e = env(u)
		setJ(out, "RightShoulder", 50 * e, 70 * e, 0)
		setJ(out, "RightElbow", 135 * e, 0, 0)
		setJ(out, "LeftShoulder", 20 * e, -90 * e, 0)
		setJ(out, "LeftElbow", 80 * e, 0, 0)
		setJ(out, "Neck", 10 * e, 12 * e, 8 * e)
	end },
	shy = { 2.0, function(u, out)
		local e = env(u)
		setJ(out, "Neck", -16 * e, -14 * e, 6 * e)
		setJ(out, "RightShoulder", 26 * e, 90 * e, 0)
		setJ(out, "RightElbow", 66 * e, 0, 0)
		setJ(out, "LeftShoulder", 26 * e, -90 * e, 0)
		setJ(out, "LeftElbow", 66 * e, 0, 0)
		setJ(out, "Waist", 0, 6 * math.sin(u * math.pi * 3) * e, 0)
	end },
	clap = { 1.6, function(u, out)
		local e = env(u)
		local s = math.max(0, math.sin(u * math.pi * 10))
		setJ(out, "RightShoulder", 55 * e, 70 * e, 0)
		setJ(out, "LeftShoulder", 55 * e, -70 * e, 0)
		setJ(out, "RightElbow", (40 + 28 * s) * e, 0, 0)
		setJ(out, "LeftElbow", (40 + 28 * s) * e, 0, 0)
	end },
	thumbs = { 1.4, function(u, out)
		local e = env(u)
		setJ(out, "RightShoulder", 70 * e, 0, -10 * e)
		setJ(out, "RightElbow", 80 * e, 0, 0)
		setJ(out, "Neck", 4 * e, 0, 6 * e)
	end },
	facepalm = { 1.6, function(u, out)
		local e = env(u)
		setJ(out, "RightShoulder", 70 * e, 80 * e, 0)
		setJ(out, "RightElbow", 140 * e, 0, 0)
		setJ(out, "Neck", -18 * e, 0, 0)
	end },
	beckon = { 1.5, function(u, out)
		local e = env(u)
		setJ(out, "RightShoulder", 60 * e, 0, -6 * e)
		setJ(out, "RightElbow", (50 + 40 * math.max(0, math.sin(u * math.pi * 6))) * e, 0, 0)
	end },
	stop_hand = { 1.2, function(u, out)
		local e = env(u)
		setJ(out, "RightShoulder", 82 * e, 0, -6 * e)
		setJ(out, "RightElbow", 38 * e, 0, 0)
		setJ(out, "RightWrist", -60 * e, 0, 0)
	end },
	wave_small = { 1.6, function(u, out)
		local e = env(u)
		setJ(out, "RightShoulder", 120 * e, 0, 24 * e)
		setJ(out, "RightElbow", 40 * e, 0, 22 * math.sin(u * math.pi * 8) * e)
	end },
	cheer_proc = { 1.6, function(u, out)
		local e = env(u)
		local s = math.sin(u * math.pi * 6)
		setJ(out, "RightShoulder", (150 + 10 * s) * e, 0, 16 * e)
		setJ(out, "LeftShoulder", (150 - 10 * s) * e, 0, -16 * e)
		setJ(out, "Neck", 10 * e, 0, 0)
	end },
	point_proc = { 1.4, function(u, out)
		local e = env(u)
		setJ(out, "RightShoulder", 88 * e, 10 * e, 0)
		setJ(out, "RightElbow", 6 * e, 0, 0)
	end },
	laugh_proc = { 1.6, function(u, out)
		local e = env(u)
		setJ(out, "Neck", (12 + 5 * math.sin(u * math.pi * 12)) * e, 0, 0)
		setJ(out, "Waist", (-4 + 3 * math.sin(u * math.pi * 12)) * e, 0, 0)
		setJ(out, "RightShoulder", 20 * e, 90 * e, 0)
		setJ(out, "RightElbow", 60 * e, 0, 0)
	end },
	-- hand-overs (a gift / a drink changes hands, phones out to swap numbers)
	give = { 1.8, function(u, out)
		-- reach forward with the right hand, hold it out, bring it back
		local e = env(u)
		local reach = math.clamp((u - 0.05) / 0.25, 0, 1) * math.clamp((0.95 - u) / 0.25, 0, 1)
		setJ(out, "RightShoulder", (22 + 58 * reach) * e, 0, -6 * e)
		setJ(out, "RightElbow", (70 - 55 * reach) * e, 0, 0)
		setJ(out, "RightWrist", -10 * reach * e, 0, 0)
		setJ(out, "Waist", -6 * reach * e, 0, 0)
		setJ(out, "Neck", -8 * reach * e, 0, 0)
	end },
	receive = { 1.8, function(u, out)
		-- both hands out, cupped, then the gift comes in to the chest
		local e = env(u)
		local take = math.clamp((u - 0.1) / 0.2, 0, 1)
		local hug = math.clamp((u - 0.55) / 0.2, 0, 1)
		local sh = 55 * take * (1 - hug) + 30 * hug
		local el = 45 * take * (1 - hug) + 100 * hug
		setJ(out, "RightShoulder", sh * e, 18 * take * e, -4 * e)
		setJ(out, "LeftShoulder", sh * e, -18 * take * e, 4 * e)
		setJ(out, "RightElbow", el * e, 0, 0)
		setJ(out, "LeftElbow", el * e, 0, 0)
		setJ(out, "Waist", -5 * take * (1 - hug) * e, 0, 0)
		setJ(out, "Neck", (-10 * take + 8 * hug) * e, 0, 5 * hug * e)
	end },
	phone_show = { 2.4, function(u, out)
		-- the phone held up between the two, screen out, a couple of taps
		local e = env(u)
		local tap = math.max(0, math.sin(u * math.pi * 7)) * (if u > 0.3 and u < 0.75 then 1 else 0)
		setJ(out, "RightShoulder", 52 * e, 0, -10 * e)
		setJ(out, "RightElbow", 78 * e, 0, 0)
		setJ(out, "RightWrist", -14 * e, 0, 0)
		setJ(out, "LeftShoulder", 34 * e, 0, 12 * e)
		setJ(out, "LeftElbow", (70 + 14 * tap) * e, 0, 0)
		setJ(out, "Neck", -20 * e, 0, 0)
	end },
}
-- Track emotes and the procedural stand-in used when the track cannot load.
local TRACK_EMOTES = { wave = "wave_small", point = "point_proc", cheer = "cheer_proc", laugh = "laugh_proc", dance1 = "cheer_proc", dance2 = "cheer_proc", dance3 = "cheer_proc", dance = "cheer_proc" }
Anim.TRACK_EMOTES = TRACK_EMOTES
local TRACK_EMOTE_DUR = { wave = 2.2, point = 2.0, cheer = 2.0, laugh = 2.4, dance1 = 5, dance2 = 5, dance3 = 5, dance = 5 }

-- Activities: what a person is doing when standing. base = looped track, pose / gesture = the
-- procedural layers, walkPose = pose kept while walking (carrying something), prop = a hint for
-- the rig dresser (phone, cup, flyers, guitar, camera, clipboard, rag ...). The street-life idle
-- hints of GwangalliCitizens.ACT_STYLE (phone | sit | look | eat | chat | photo | sunbathe |
-- stretch | guitar | paint | fish | work | dance | idle) are all valid act names.
Anim.ACTS = {
	idle = { base = "idle", gesture = "breathe" },
	look = { base = "idle", gesture = "look_around" },
	chat = { base = "idle", gesture = "talk" },
	talk = { base = "idle", gesture = "talk" },
	listen = { base = "idle", gesture = "listen" },
	phone = { base = "idle", pose = "phone", gesture = "scroll", prop = "phone", walkPose = "phone" },
	text = { base = "idle", pose = "text", gesture = "scroll", prop = "phone" },
	call = { base = "idle", pose = "phone_call", gesture = "listen", prop = "phone", walkPose = "phone_call" },
	eat = { base = "idle", pose = "cup", gesture = "nod", prop = "snack" },
	cup = { base = "idle", pose = "cup", gesture = "breathe", prop = "cup", walkPose = "cup" },
	photo = { base = "idle", pose = "camera", gesture = "breathe", prop = "camera" },
	sit = { base = "idle", pose = "sit_bench", gesture = "listen" },
	sit_phone = { base = "idle", pose = "sit_phone", gesture = "scroll", prop = "phone" },
	sunbathe = { base = "idle", pose = "sunbathe" },
	stretch = { base = "idle", pose = "stretch", gesture = "sway" },
	guitar = { base = "idle", pose = "guitar", gesture = "strum", prop = "guitar", walkPose = "flyers_hold" },
	paint = { base = "idle", pose = "paint", gesture = "stir", prop = "brush" },
	fish = { base = "idle", pose = "fish", gesture = "breathe", prop = "rod" },
	work = { base = "idle", pose = "hands_front", gesture = "look_around" },
	dance = { base = "dance1", gesture = "breathe" },
	dance2 = { base = "dance2" },
	dance3 = { base = "dance3" },
	cheer = { base = "idle", gesture = "cheer_arms" },
	wipe = { base = "idle", pose = "wipe", gesture = "wipe", prop = "rag" },
	cook = { base = "idle", pose = "cook", gesture = "stir" },
	flip = { base = "idle", pose = "flip", gesture = "flip" },
	chop = { base = "idle", pose = "chop", gesture = "chop" },
	flyers = { base = "idle", pose = "flyers_hold", gesture = "flyer", prop = "flyers", walkPose = "flyers_hold" },
	clipboard = { base = "idle", pose = "clipboard", gesture = "scroll", prop = "clipboard", walkPose = "clipboard" },
	guard = { base = "idle", pose = "guard", gesture = "look_around" },
	arms_crossed = { base = "idle", pose = "arms_crossed", gesture = "look_around" },
	behind = { base = "idle", pose = "hands_behind", gesture = "look_around", walkPose = "hands_behind" },
	teller = { base = "idle", pose = "hands_front", gesture = "breathe" },
	typing = { base = "idle", pose = "wipe", gesture = "scroll" },
	lookout = { base = "idle", pose = "hands_behind", gesture = "shade" },
	whistle = { base = "idle", pose = "hands_behind", gesture = "whistle", walkPose = "hands_behind" },
	pockets = { base = "idle", pose = "pockets", gesture = "look_around", walkPose = "pockets" },
	hips = { base = "idle", pose = "hips", gesture = "look_around" },
	lean = { base = "idle", pose = "lean", gesture = "listen" },
	squat = { base = "idle", pose = "squat", gesture = "breathe" },
	shop = { base = "idle", gesture = "look_around" },
	queue = { base = "idle", pose = "phone", gesture = "scroll", prop = "phone" },
	walk = { base = "idle" },
}

-------------------------------------------------------------------------------------------------
-- Rig controller
-------------------------------------------------------------------------------------------------
type JointRec = { m: Motor6D, p: CFrame, r: CFrame, yxz: boolean, wrote: boolean }

local Ctl = {}
Ctl.__index = Ctl

local controllers: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
local DEG = math.pi / 180
local ZERO6 = { 0, 0, 0, 0, 0, 0 }

local function findJoints(model: Instance, rig: string): { [string]: JointRec }
	local out: { [string]: JointRec } = {}
	local byName: { [string]: Motor6D } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and not byName[d.Name] then
			byName[d.Name] = d
		end
	end
	for _, j in JOINT_NAMES do
		local m = byName[if rig == "R6" then (R6_JOINT[j] or "") else j]
		if m then
			local c0 = m.C0
			out[j] = { m = m, p = CFrame.new(c0.Position), r = c0 - c0.Position, yxz = YXZ_JOINT[j] == true, wrote = false }
		end
	end
	return out
end

local function seedOf(model: Instance): number
	local s = model:GetAttribute("AnimSeed")
	if type(s) == "number" then
		return s
	end
	local n = 0
	local name = model.Name
	for i = 1, math.min(#name, 24) do
		n = (n * 31 + string.byte(name, i)) % 100003
	end
	return n
end

function Anim.rig(model: Instance): any
	local c = controllers[model]
	if c and not c.dead then
		return c
	end
	local rig = Anim.rigType(model)
	local seed = seedOf(model)
	c = setmetatable({
		model = model,
		rig = rig,
		seed = seed,
		phase = (seed % 997) / 997,
		joints = findJoints(model, rig),
		animated = true,
		act = nil :: string?,
		moving = nil :: number?,
		baseName = nil :: string?,
		baseTrack = nil :: AnimationTrack?,
		-- pose blend (numeric angles per joint)
		poseName = nil :: string?,
		poseCur = {} :: { [string]: { number } },
		poseTo = {} :: { [string]: { number } },
		poseRate = 6,
		gestureName = nil :: string?,
		gestureW = 0,
		gestureOut = {} :: { [string]: { number } },
		lookPos = nil :: Vector3?,
		lookYaw = 0,
		lookPitch = 0,
		oneShot = nil :: any,
		oneOut = {} :: { [string]: { number } },
		suppressUntil = 0,
		suppress = 0,
		t = 0,
		last = os.clock(),
		settled = true,
		dead = false,
		detail = 2,
		conn = nil :: RBXScriptConnection?,
	}, Ctl)
	controllers[model] = c
	c.conn = model.Destroying:Connect(function()
		c:destroy()
	end)
	return c
end

function Ctl:destroy()
	if self.dead then
		return
	end
	self.dead = true
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	controllers[self.model] = nil
end

function Ctl:_playBase(name: string?)
	if name == self.baseName and (name == nil or (self.baseTrack and self.baseTrack.IsPlaying)) then
		return
	end
	local old = self.baseTrack
	self.baseName = name
	self.baseTrack = nil
	if old and old.IsPlaying then
		pcall(old.Stop, old, 0.25)
	end
	if name and self.animated then
		local track = Anim.play(self.model, name, { fade = 0.25, seed = self.seed, offset = self.phase })
		self.baseTrack = track
		if track and self.moving and (name == "walk" or name == "run") then
			local clip = if name == "run" then Anim.RUN_CLIP_SPEED else Anim.WALK_CLIP_SPEED
			pcall(track.AdjustSpeed, track, math.clamp(self.moving / clip, 0.55, 1.6))
		end
	end
end

function Ctl:_applyAct()
	local a = Anim.ACTS[self.act or "idle"] or Anim.ACTS.idle
	if self.moving then
		local sp = self.moving
		if sp > 11 then
			self:_playBase("run")
			if self.baseTrack then
				pcall(self.baseTrack.AdjustSpeed, self.baseTrack, math.clamp(sp / Anim.RUN_CLIP_SPEED, 0.6, 1.6))
			end
		else
			self:_playBase("walk")
			if self.baseTrack then
				pcall(self.baseTrack.AdjustSpeed, self.baseTrack, math.clamp(sp / Anim.WALK_CLIP_SPEED, 0.55, 1.5))
			end
		end
		self:pose(a.walkPose, 0.3)
		self:gesture(nil)
	else
		self:_playBase(a.base or "idle")
		self:pose(a.pose, 0.35)
		self:gesture(a.gesture)
	end
end

function Ctl:setAct(name: string?)
	if name == self.act then
		return
	end
	self.act = name
	self:_applyAct()
end

function Ctl:setMoving(speed: number?)
	local was = self.moving
	if speed and speed < 0.3 then
		speed = nil
	end
	if (was == nil) == (speed == nil) then
		self.moving = speed
		if speed and self.baseTrack then
			local clip = if speed > 11 then Anim.RUN_CLIP_SPEED else Anim.WALK_CLIP_SPEED
			if (speed > 11) ~= (was ~= nil and was > 11) then
				self:_applyAct()
			else
				pcall(self.baseTrack.AdjustSpeed, self.baseTrack, math.clamp(speed / clip, 0.55, 1.6))
			end
		end
		return
	end
	self.moving = speed
	self:_applyAct()
end

-- Target pose (Anim.POSES name, a custom table, or nil = relaxed), blended over `fade` seconds.
function Ctl:pose(name: any, fade: number?)
	local def = if type(name) == "table" then name elseif type(name) == "string" then Anim.POSES[name] else nil
	local key = if type(name) == "string" then name else (if def then def else nil)
	if key == self.poseName then
		return
	end
	self.poseName = key
	local to = {}
	if def then
		for j, v in def do
			to[j] = { v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 0, v[5] or 0, v[6] or 0 }
		end
	end
	self.poseTo = to
	for j in to do
		if not self.poseCur[j] then
			self.poseCur[j] = { 0, 0, 0, 0, 0, 0 }
		end
	end
	self.poseRate = 1 / math.max(0.05, fade or 0.35)
	self.settled = false
end

function Ctl:gesture(name: string?)
	if name ~= nil and not Anim.GESTURES[name] then
		name = nil
	end
	if name == self.gestureName then
		return
	end
	self.gestureName = name
	self.settled = false
end

function Ctl:look(pos: Vector3?)
	if pos == nil and self.lookPos == nil then
		return
	end
	self.lookPos = pos
	self.settled = false
end

-- One-shot emote. Returns its duration (seconds) or 0 when unknown.
function Ctl:emote(name: string, opts: any?): number
	local o = opts or {}
	local proc = Anim.EMOTES[name]
	if proc then
		self.oneShot = { def = proc, t0 = os.clock(), dur = (o.duration or proc[1]) }
		self.settled = false
		return self.oneShot.dur
	end
	local n = resolveName(name)
	local stand = TRACK_EMOTES[n]
	if stand == nil then
		return 0
	end
	local track = if self.animated then Anim.play(self.model, n, { fade = 0.15, speed = o.speed, looped = LOOPED[n] == true }) else nil
	if track then
		local dur = o.duration or TRACK_EMOTE_DUR[n] or 2
		local len = track.Length
		if not LOOPED[n] and len and len > 0.2 then
			dur = math.min(dur, len / math.max(0.1, o.speed or 1))
		end
		self.suppressUntil = os.clock() + dur
		self.settled = false
		if LOOPED[n] then
			task.delay(dur, function()
				if track.IsPlaying then
					pcall(track.Stop, track, 0.3)
				end
			end)
		end
		return dur
	end
	-- no track (not loaded yet / blocked): the procedural stand-in
	local def = Anim.EMOTES[stand]
	self.oneShot = { def = def, t0 = os.clock(), dur = def[1] }
	self.settled = false
	return def[1]
end

function Ctl:setAnimated(on: boolean)
	if on == self.animated then
		return
	end
	self.animated = on
	if not on then
		local old = self.baseTrack
		self.baseTrack = nil
		self.baseName = nil
		if old and old.IsPlaying then
			pcall(old.Stop, old, 0.2)
		end
		Anim.stopAll(self.model, 0.2)
		for _, j in self.joints do
			if j.wrote then
				j.m.C0 = j.p * j.r
				j.wrote = false
			end
		end
		self.settled = true
	else
		self:_applyAct()
		self.settled = false
	end
end

local function approach(cur: number, target: number, maxStep: number): number
	local d = target - cur
	if d > maxStep then
		return cur + maxStep
	elseif d < -maxStep then
		return cur - maxStep
	end
	return target
end

-- Puts every joint this controller moved back to its rest C0 and drops the procedural layers
-- (tracks keep playing): for a borrowed rig such as a player's character after a one-shot.
function Ctl:relax()
	for _, j in self.joints do
		if j.wrote then
			j.m.C0 = j.p * j.r
			j.wrote = false
		end
	end
	table.clear(self.poseCur)
	self.poseTo = {}
	self.poseName = nil
	self.gestureName = nil
	self.gestureW = 0
	self.oneShot = nil
	self.lookPos = nil
	self.lookYaw, self.lookPitch = 0, 0
	self.settled = true
end

-- Detail level for distance LOD: 2 = everything, 1 = pose + one-shot emotes (no gestures, no
-- head turns), 0 = base tracks only (the procedural layers are cleared once and not stepped).
function Ctl:setDetail(level: number)
	if level == self.detail then
		return
	end
	self.detail = level
	self.settled = false
	if level <= 0 then
		for _, j in self.joints do
			if j.wrote then
				j.m.C0 = j.p * j.r
				j.wrote = false
			end
		end
		table.clear(self.poseCur)
		self.gestureW = 0
		self.oneShot = nil
		self.lookYaw, self.lookPitch = 0, 0
	else
		for j in self.poseTo do
			if not self.poseCur[j] then
				self.poseCur[j] = { 0, 0, 0, 0, 0, 0 }
			end
		end
	end
end

-- Advances blends and writes the joints. Returns true when it wrote anything.
function Ctl:step(): boolean
	if self.dead or not self.animated then
		return false
	end
	local now = os.clock()
	local dt = now - self.last
	if dt < 1e-4 then
		return false -- already stepped this frame (another system shares the rig)
	end
	self.last = now
	dt = math.min(dt, 0.25)
	self.t += dt
	-- a base track that could not load yet (rig not in the DataModel / asset still loading): retry
	if self.baseName and not self.baseTrack and now >= (self.retryAt or 0) then
		self.retryAt = now + 1
		local n = self.baseName
		self.baseName = nil
		self:_playBase(n)
	end
	local detail = self.detail or 2
	if detail <= 0 then
		return false
	end
	local gName = if detail >= 2 then self.gestureName else nil
	local lookPos = if detail >= 2 then self.lookPos else nil
	if self.settled and not gName and not lookPos and not self.oneShot and self.gestureW <= 0 then
		return false
	end
	local busy = false
	-- emote suppression of the pose (a track emote owns the arms meanwhile)
	local supTarget = if now < self.suppressUntil then 1 else 0
	self.suppress = approach(self.suppress, supTarget, dt * 6)
	if self.suppress > 0 then
		busy = true
	end
	-- pose blend
	local k = math.min(1, dt * self.poseRate * 3)
	for j, cur in self.poseCur do
		local to = self.poseTo[j] or ZERO6
		local moving = false
		for i = 1, 6 do
			local d = to[i] - cur[i]
			if math.abs(d) > 0.05 then
				cur[i] += d * k
				moving = true
			else
				cur[i] = to[i]
			end
		end
		if moving then
			busy = true
		elseif not self.poseTo[j] then
			self.poseCur[j] = nil
		end
	end
	-- gesture
	local gOut = self.gestureOut
	for _, e in gOut do
		e[1], e[2], e[3], e[4], e[5], e[6] = 0, 0, 0, 0, 0, 0
	end
	local gTarget = if gName then 1 else 0
	self.gestureW = approach(self.gestureW, gTarget, dt * 2.5)
	if self.gestureW > 0 then
		busy = true
		local fn = Anim.GESTURES[gName or ""] or self._lastGesture
		if gName then
			self._lastGesture = Anim.GESTURES[gName]
		end
		if fn then
			fn(self.t, self.phase, gOut)
		end
	end
	-- one-shot emote
	local oOut = self.oneOut
	for _, e in oOut do
		e[1], e[2], e[3], e[4], e[5], e[6] = 0, 0, 0, 0, 0, 0
	end
	local os_ = self.oneShot
	if os_ then
		local u = (now - os_.t0) / os_.dur
		if u >= 1 then
			self.oneShot = nil
		else
			busy = true
			os_.def[2](u, oOut)
		end
	end
	-- look-at (neck 75 %, waist 25 % of the yaw)
	local wantYaw, wantPitch = 0, 0
	if lookPos then
		local ut = self.model:FindFirstChild(if self.rig == "R6" then "Torso" else "UpperTorso")
		local root = self.model:FindFirstChild("HumanoidRootPart")
		local ref = (root or ut) :: BasePart?
		if ref and ref:IsA("BasePart") then
			local headY = if ut and ut:IsA("BasePart") then ut.Position.Y + ut.Size.Y * 0.5 + 0.6 else ref.Position.Y + 1.5
			local rel = ref.CFrame:PointToObjectSpace(Vector3.new(lookPos.X, lookPos.Y - (headY - ref.Position.Y), lookPos.Z))
			local flat = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
			if flat > 0.3 then
				wantYaw = math.atan2(-rel.X, -rel.Z) / DEG
				wantPitch = math.atan2(rel.Y, flat) / DEG
				if math.abs(wantYaw) > 110 then
					wantYaw, wantPitch = 0, 0 -- behind: do not break the neck, just face forward
				end
				wantYaw = math.clamp(wantYaw, -75, 75)
				wantPitch = math.clamp(wantPitch, -30, 25)
			end
		end
	end
	local lk = math.min(1, dt * 7)
	self.lookYaw += (wantYaw - self.lookYaw) * lk
	self.lookPitch += (wantPitch - self.lookPitch) * lk
	if math.abs(self.lookYaw) > 0.2 or math.abs(self.lookPitch) > 0.2 then
		busy = true
	else
		self.lookYaw, self.lookPitch = 0, 0
	end
	-- compose + write
	local wrote = false
	local poseW = 1 - self.suppress
	local gW = self.gestureW * (1 - self.suppress * 0.8)
	for name, j in self.joints do
		local pc = self.poseCur[name]
		local g = gOut[name]
		local o = oOut[name]
		local p, y, r, dx, dy, dz = 0, 0, 0, 0, 0, 0
		local any = false
		if pc then
			p, y, r, dx, dy, dz = pc[1] * poseW, pc[2] * poseW, pc[3] * poseW, pc[4] * poseW, pc[5] * poseW, pc[6] * poseW
			any = true
		end
		if g and gW > 0 then
			p += g[1] * gW
			y += g[2] * gW
			r += g[3] * gW
			any = true
		end
		if o then
			p += o[1]
			y += o[2]
			r += o[3]
			any = true
		end
		if name == "Neck" and (self.lookYaw ~= 0 or self.lookPitch ~= 0) then
			y += self.lookYaw * 0.75
			p += self.lookPitch
			any = true
		elseif name == "Waist" and self.lookYaw ~= 0 then
			y += self.lookYaw * 0.25
			any = true
		end
		if any and (p ~= 0 or y ~= 0 or r ~= 0 or dx ~= 0 or dy ~= 0 or dz ~= 0) then
			local rot = if j.yxz then CFrame.fromEulerAnglesYXZ(p * DEG, y * DEG, r * DEG) else CFrame.Angles(p * DEG, y * DEG, r * DEG)
			j.m.C0 = j.p * CFrame.new(dx, dy, dz) * rot * j.r
			j.wrote = true
			wrote = true
		elseif j.wrote then
			j.m.C0 = j.p * j.r
			j.wrote = false
			wrote = true
		end
	end
	self.settled = not busy
	return wrote
end

-- Shortcuts --------------------------------------------------------------------------------------
function Anim.lookAt(model: Instance, pos: Vector3?)
	local c = Anim.rig(model)
	c:look(pos)
	c:step()
end
function Anim.pose(model: Instance, name: any, fade: number?)
	Anim.rig(model):pose(name, fade)
end
function Anim.gesture(model: Instance, name: string?)
	Anim.rig(model):gesture(name)
end
function Anim.emote(model: Instance, name: string, opts: any?): number
	return Anim.rig(model):emote(name, opts)
end
function Anim.act(model: Instance, act: string?)
	Anim.rig(model):setAct(act)
end

-------------------------------------------------------------------------------------------------
-- Block R15 rig
-------------------------------------------------------------------------------------------------
-- Layout at height scale 1, feet at y = 0, facing -Z. Joint heights are world Y of the pivots.
Anim.R15 = {
	rootY = 3, -- HumanoidRootPart centre (2 x 2 x 1)
	hipHeight = 2,
	lowerTorso = { y0 = 2.0, y1 = 2.6 },
	upperTorso = { y0 = 2.6, y1 = 4.0 },
	head = { y = 4.62, size = 1.2 },
	shoulderY = 3.78, elbowY = 3.08, wristY = 2.3,
	upperArm = { y0 = 3.03, y1 = 4.0 }, lowerArm = { y0 = 2.3, y1 = 3.14 }, hand = { y0 = 1.98, y1 = 2.34 },
	hipY = 2.05, kneeY = 1.1, ankleY = 0.3,
	upperLeg = { y0 = 1.05, y1 = 2.1 }, lowerLeg = { y0 = 0.28, y1 = 1.14 }, foot = { y0 = 0, y1 = 0.3 },
	builds = {
		slim = { torso = 1.7, arm = 0.8, leg = 0.82, depth = 0.9 },
		avg = { torso = 1.9, arm = 0.9, leg = 0.9, depth = 1.0 },
		broad = { torso = 2.2, arm = 1.0, leg = 1.0, depth = 1.1 },
	},
}

local function mkPart(model: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function joint(name: string, p0: BasePart, p1: BasePart, pivot: Vector3)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = p0.CFrame:ToObjectSpace(CFrame.new(pivot))
	m.C1 = p1.CFrame:ToObjectSpace(CFrame.new(pivot))
	m.Parent = p1
	return m
end

local function col(v: any, fallback: Color3): Color3
	if typeof(v) == "Color3" then
		return v
	elseif type(v) == "table" and type(v[1]) == "number" then
		return Color3.fromRGB(v[1], v[2], v[3])
	end
	return fallback
end

-- Builds a bare block R15 at the origin (feet y = 0, facing -Z); returns model, parts.
function Anim.buildR15(opts: any?): (Model, { [string]: BasePart })
	local o = opts or {}
	local s = math.clamp(tonumber(o.height) or 1, 0.8, 1.2)
	local L = Anim.R15
	local B = L.builds[o.build or "avg"] or L.builds.avg
	local tw = B.torso * (if o.body == "f" then 0.94 else 1)
	local aw, lw, dp = B.arm * (if o.body == "f" then 0.92 else 1), B.leg, B.depth
	local skin = col(o.skin, Color3.fromRGB(234, 192, 160))
	local shirt = col(o.shirt, Color3.fromRGB(230, 230, 230))
	local pants = col(o.pants, Color3.fromRGB(45, 50, 64))
	local shoes = col(o.shoes, Color3.fromRGB(240, 240, 240))
	local sleeves = o.sleeves or "short"
	local model = Instance.new("Model")
	model.Name = o.name or "Rig"
	local parts: { [string]: BasePart } = {}
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x * s, y * s, z * s)
	end
	local function part(name: string, w: number, y0: number, y1: number, d: number, x: number, c: Color3, z: number?): BasePart
		local p = mkPart(model, name, Vector3.new(w * s, (y1 - y0) * s, d * s), at(x, (y0 + y1) / 2, z or 0), c)
		parts[name] = p
		return p
	end
	local hrp = mkPart(model, "HumanoidRootPart", Vector3.new(2, 2, 1) * s, at(0, L.rootY, 0), Color3.new(1, 1, 1))
	hrp.Transparency = 1
	hrp.Anchored = true
	hrp.Massless = false
	parts.HumanoidRootPart = hrp
	model.PrimaryPart = hrp
	local lt = part("LowerTorso", tw * 0.98, L.lowerTorso.y0, L.lowerTorso.y1, dp * 0.96, 0, if o.shorts == "dress" then shirt else pants)
	local ut = part("UpperTorso", tw, L.upperTorso.y0, L.upperTorso.y1, dp, 0, shirt)
	lt.CastShadow = true
	ut.CastShadow = true
	local head = mkPart(model, "Head", Vector3.new(L.head.size, L.head.size, L.head.size) * s, at(0, L.head.y, 0), skin)
	parts.Head = head
	local hm = Instance.new("SpecialMesh")
	hm.MeshType = Enum.MeshType.Head
	hm.Scale = Vector3.new(1.18, 1.1, 1.18)
	hm.Parent = head
	if o.face ~= false then
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Texture = if type(o.face) == "string" then o.face else "rbxasset://textures/face.png"
		face.Face = Enum.NormalId.Front
		face.Parent = head
	end
	local ax = tw / 2 + aw / 2
	local upperArmC = if sleeves == "none" then skin else shirt
	local lowerArmC = if sleeves == "long" then shirt else skin
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		part(side .. "UpperArm", aw, L.upperArm.y0, L.upperArm.y1, aw, sx * ax, upperArmC)
		part(side .. "LowerArm", aw * 0.96, L.lowerArm.y0, L.lowerArm.y1, aw * 0.96, sx * ax, lowerArmC)
		part(side .. "Hand", aw * 0.9, L.hand.y0, L.hand.y1, aw * 0.9, sx * ax, skin)
		local lx = sx * (tw / 4 + 0.02)
		local lowerLegC = if o.shorts == true or o.shorts == "dress" then skin else pants
		local upperLegC = if o.shorts == "dress" then shirt else pants
		part(side .. "UpperLeg", lw, L.upperLeg.y0, L.upperLeg.y1, lw, lx, upperLegC)
		part(side .. "LowerLeg", lw * 0.94, L.lowerLeg.y0, L.lowerLeg.y1, lw * 0.94, lx, lowerLegC)
		part(side .. "Foot", lw * 0.94, L.foot.y0, L.foot.y1, lw * 1.2, lx, shoes, -0.1)
	end
	joint("Root", hrp, lt, Vector3.new(0, L.lowerTorso.y0 + 0.3, 0) * s)
	joint("Waist", lt, ut, Vector3.new(0, L.lowerTorso.y1, 0) * s)
	joint("Neck", ut, head, Vector3.new(0, L.upperTorso.y1, 0) * s)
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		local P = parts
		joint(side .. "Shoulder", ut, P[side .. "UpperArm"], Vector3.new(sx * ax, L.shoulderY, 0) * s)
		joint(side .. "Elbow", P[side .. "UpperArm"], P[side .. "LowerArm"], Vector3.new(sx * ax, L.elbowY, 0) * s)
		joint(side .. "Wrist", P[side .. "LowerArm"], P[side .. "Hand"], Vector3.new(sx * ax, L.wristY, 0) * s)
		local lx = sx * (tw / 4 + 0.02)
		joint(side .. "Hip", lt, P[side .. "UpperLeg"], Vector3.new(lx, L.hipY, 0) * s)
		joint(side .. "Knee", P[side .. "UpperLeg"], P[side .. "LowerLeg"], Vector3.new(lx, L.kneeY, 0) * s)
		joint(side .. "Ankle", P[side .. "LowerLeg"], P[side .. "Foot"], Vector3.new(lx, L.ankleY, 0) * s)
	end
	if o.humanoid then
		local h = Instance.new("Humanoid")
		h.RigType = Enum.HumanoidRigType.R15
		h.HipHeight = L.hipHeight * s
		h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		h.BreakJointsOnDeath = false
		pcall(function()
			(h :: any).EvaluateStateMachine = false
			h.RequiresNeck = false
		end)
		h.Parent = model
		local a = Instance.new("Animator")
		a.Parent = h
	else
		local ac = Instance.new("AnimationController")
		ac.Parent = model
		local a = Instance.new("Animator")
		a.Parent = ac
	end
	model:SetAttribute("RigScale", s)
	return model, parts
end

-- Welds `part` to `to` where it stands now (a Weld, so Anim.solve can place it too).
function Anim.weld(to: BasePart, part: BasePart): Weld
	local w = Instance.new("Weld")
	w.Name = "Attach"
	w.Part0 = to
	w.Part1 = part
	w.C0 = to.CFrame:ToObjectSpace(part.CFrame)
	w.C1 = CFrame.new()
	w.Parent = part
	part.Anchored = false
	part.Massless = true
	return w
end

-- Places every part of an anchored-root rig from its Motor6Ds / Welds (C0 * C1^-1 chain from the root).
function Anim.solve(model: Instance)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local children: { [Instance]: { any } } = {}
	for _, d in model:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("Weld")) and d.Part0 and d.Part1 then
			local list = children[d.Part0]
			if not list then
				list = {}
				children[d.Part0] = list
			end
			table.insert(list, d)
		end
	end
	local stack = { root }
	local seen: { [Instance]: boolean } = { [root] = true }
	while #stack > 0 do
		local p0 = table.remove(stack) :: BasePart
		for _, m in children[p0] or {} do
			local p1 = m.Part1 :: BasePart
			if not seen[p1] then
				seen[p1] = true
				local tr = CFrame.new()
				if m:IsA("Motor6D") then
					local ok, t = pcall(function()
						return m.Transform
					end)
					if ok and typeof(t) == "CFrame" then
						tr = t
					end
				end
				p1.CFrame = p0.CFrame * m.C0 * tr * m.C1:Inverse()
				table.insert(stack, p1)
			end
		end
	end
end

return Anim
