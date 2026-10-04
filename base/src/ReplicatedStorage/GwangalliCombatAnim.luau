-- GwangalliCombatAnim — 전투 · 범죄 · 경찰 (combat / crime / police) motion data, in GwangalliAnim's procedural
-- format (owner: combat client). Pure data + pure helpers: requiring it creates nothing and never yields, and it
-- never requires GwangalliAnim (GwangalliAnim requires IT, see the install hook at the end of GwangalliAnim).
--
--   CA.POSES     degree poses (GwangalliAnim.POSES format): limbs { pitch, yaw, roll } as CFrame.Angles in the
--                parent part's space about the joint pivot (pitch > 0 raises an arm / thigh forward and bends an
--                elbow, knees bend with pitch < 0, roll > 0 swings a limb toward +X); Root / Waist / Neck
--                { pitch (up +), yaw (left +), roll [, dx, dy, dz] } as fromEulerAnglesYXZ (Root carries the
--                translation: lying / kneeling).
--                cb_guard cb_jab cb_cross cb_hookLd cb_hook cb_flinchF cb_flinchB hands_up cuffed kneel_cuff cb_ko
--                cb_cuff_officer cb_cuff_officer_b cb_cower cb_phone_call
--   CA.CLIPS     keyed poses (seconds): jab cross hook flinchF flinchB ocuff; CA.sample(clip, t, out) writes the
--                clip's offset at t (key minus clip.base) into out[joint] = { p, y, r, ... } (adds; no allocation
--                once out holds the joints).
--   CA.install(Anim)   idempotent: POSES into Anim.POSES; EMOTES cb_jab cb_cross cb_hook cb_flinchF cb_flinchB
--                cb_ocuff; GESTURES cb_cuffing; ACTS cb_guard surrender cuffed kneel cb_ko cb_cuffing cb_cower
--                cb_call.
--   CA.POSE_CF   the street-life poses as CFrame offsets (GwangalliStreetLife Anim.POSES format, motor -> CFrame
--                applied as rest * offset): cower handsup phonecall cb_flinch cb_guard cb_jab cb_cross cb_hook.
--   CA.POSE_OF   GwCombatPose attribute value -> pose name ("handsup" -> "hands_up", "cuffed", "kneel" ->
--                "kneel_cuff", "ko" -> "cb_ko").
--   CA.CLIP_OF   combo index -> emote name (1 "cb_jab", 2 "cb_cross", 3 "cb_hook").

local CA = {}
CA.VERSION = 1

CA.POSES = {
	-- fists up at the chin, elbows in, left side a little forward (orthodox stance)
	cb_guard = {
		RightShoulder = { 58, 0, -24 },
		RightElbow = { 118, 0, 0 },
		LeftShoulder = { 66, 0, 22 },
		LeftElbow = { 112, 0, 0 },
		Waist = { 0, -12, 0 },
		Neck = { -4, 10, 0 },
	},
	-- 1: left jab, arm straight out at shoulder height, the right fist stays home
	cb_jab = {
		LeftShoulder = { 92, -6, 14 },
		LeftElbow = { 4, 0, 0 },
		RightShoulder = { 58, 0, -24 },
		RightElbow = { 118, 0, 0 },
		Waist = { 0, -22, 0 },
		Neck = { -2, 18, 0 },
	},
	-- 2: right cross, the hips and shoulders turn through, the left fist comes back to the chin
	cb_cross = {
		RightShoulder = { 92, 6, -16 },
		RightElbow = { 4, 0, 0 },
		LeftShoulder = { 62, 0, 24 },
		LeftElbow = { 118, 0, 0 },
		Waist = { -4, 30, 0 },
		Neck = { -2, -20, 0 },
	},
	-- 3: left hook, wind-up (elbow out and back, body turned left) ...
	cb_hookLd = {
		LeftShoulder = { 50, -10, -48 },
		LeftElbow = { 96, 0, 0 },
		RightShoulder = { 58, 0, -24 },
		RightElbow = { 118, 0, 0 },
		Waist = { 0, 18, 0 },
		Neck = { -2, -8, 0 },
	},
	-- ... then the arm swings round horizontally, elbow bent ~90, the whole body turning right
	cb_hook = {
		LeftShoulder = { 88, -80, -6 },
		LeftElbow = { 96, 0, 0 },
		RightShoulder = { 58, 0, -24 },
		RightElbow = { 118, 0, 0 },
		Waist = { -2, -36, 0 },
		Neck = { -2, 22, 0 },
	},
	-- hit from the front: head and chest thrown back, arms flung out
	cb_flinchF = {
		Waist = { 16, 0, 0 },
		Neck = { 20, 0, 0 },
		RightShoulder = { 26, 0, 30 },
		RightElbow = { 30, 0, 0 },
		LeftShoulder = { 26, 0, -30 },
		LeftElbow = { 30, 0, 0 },
	},
	-- hit from behind: doubled forward
	cb_flinchB = {
		Waist = { -20, 0, 0 },
		Neck = { -22, 0, 0 },
		RightShoulder = { 14, 0, 18 },
		RightElbow = { 40, 0, 0 },
		LeftShoulder = { 14, 0, -18 },
		LeftElbow = { 40, 0, 0 },
	},
	-- 항복: both hands high above the head, palms out
	hands_up = {
		RightShoulder = { 170, 0, 16 },
		RightElbow = { 16, 0, 0 },
		LeftShoulder = { 170, 0, -16 },
		LeftElbow = { 16, 0, 0 },
		Neck = { 6, 0, 0 },
	},
	-- 수갑: hands together behind the back, head down
	cuffed = {
		RightShoulder = { -24, 90, 0 },
		RightElbow = { 66, 0, 0 },
		LeftShoulder = { -24, -90, 0 },
		LeftElbow = { 66, 0, 0 },
		Waist = { -4, 0, 0 },
		Neck = { -14, 0, 0 },
	},
	-- on the knees, cuffed (police tackle)
	kneel_cuff = {
		Root = { 0, 0, 0, 0, -1.0, 0 },
		RightHip = { 4, 0, 4 },
		LeftHip = { 4, 0, -4 },
		RightKnee = { -92, 0, 0 },
		LeftKnee = { -92, 0, 0 },
		RightShoulder = { -24, 90, 0 },
		RightElbow = { 66, 0, 0 },
		LeftShoulder = { -24, -90, 0 },
		LeftElbow = { 66, 0, 0 },
		Neck = { -16, 0, 0 },
	},
	-- KO: flat on the ground (Root pitch -88 = face down, lowered onto the floor), limbs sprawled
	cb_ko = {
		Root = { -88, 0, 0, 0, -2.35, 0 },
		RightShoulder = { 150, 0, 34 },
		RightElbow = { 30, 0, 0 },
		LeftShoulder = { 120, 0, -40 },
		LeftElbow = { 50, 0, 0 },
		RightHip = { 6, 0, 12 },
		RightKnee = { -14, 0, 0 },
		LeftHip = { -2, 0, -8 },
		LeftKnee = { -36, 0, 0 },
		Neck = { 30, 34, 0 },
	},
	-- officer cuffing a suspect: arms forward and down, leaning in (two keys, the ocuff clip alternates them)
	cb_cuff_officer = {
		RightShoulder = { 52, 0, -12 },
		RightElbow = { 44, 0, 0 },
		LeftShoulder = { 52, 0, 12 },
		LeftElbow = { 44, 0, 0 },
		Waist = { -14, 0, 0 },
		Neck = { -20, 0, 0 },
	},
	cb_cuff_officer_b = {
		RightShoulder = { 44, 0, -6 },
		RightElbow = { 70, 0, 0 },
		LeftShoulder = { 46, 0, 6 },
		LeftElbow = { 64, 0, 0 },
		Waist = { -16, 0, 0 },
		Neck = { -22, 0, 0 },
	},
	-- witness cowering: hunched, forearms over the head
	cb_cower = {
		Root = { 0, 0, 0, 0, -0.35, 0 },
		RightShoulder = { 132, 0, -32 },
		RightElbow = { 118, 0, 0 },
		LeftShoulder = { 132, 0, 32 },
		LeftElbow = { 118, 0, 0 },
		Waist = { -24, 0, 0 },
		Neck = { -24, 0, 0 },
		RightHip = { 22, 0, 4 },
		RightKnee = { -38, 0, 0 },
		LeftHip = { 22, 0, -4 },
		LeftKnee = { -38, 0, 0 },
	},
	-- "여보세요, 경찰이죠?": phone at the ear, the other hand across the stomach
	cb_phone_call = {
		RightShoulder = { 30, 80, 12 },
		RightElbow = { 150, 0, 0 },
		LeftShoulder = { 20, -80, 0 },
		LeftElbow = { 70, 0, 0 },
		Neck = { -6, 0, 8 },
	},
}

-- Clips: { dur, base = pose the clip is relative to (nil = relaxed), hit = contact time, keys = { { t, pose } } }.
-- Hold keys of >= 0.08 s keep the contact frame visible at the 20 Hz phone step rate.
CA.CLIPS = {
	jab = { dur = 0.36, hit = 0.12, base = "cb_guard", keys = { { 0, "cb_guard" }, { 0.09, "cb_jab" }, { 0.18, "cb_jab" }, { 0.36, "cb_guard" } } },
	cross = { dur = 0.42, hit = 0.16, base = "cb_guard", keys = { { 0, "cb_guard" }, { 0.12, "cb_cross" }, { 0.22, "cb_cross" }, { 0.42, "cb_guard" } } },
	hook = { dur = 0.58, hit = 0.24, base = "cb_guard", keys = { { 0, "cb_guard" }, { 0.12, "cb_hookLd" }, { 0.22, "cb_hook" }, { 0.34, "cb_hook" }, { 0.58, "cb_guard" } } },
	flinchF = { dur = 0.45, keys = { { 0, false }, { 0.07, "cb_flinchF" }, { 0.16, "cb_flinchF" }, { 0.45, false } } },
	flinchB = { dur = 0.45, keys = { { 0, false }, { 0.07, "cb_flinchB" }, { 0.16, "cb_flinchB" }, { 0.45, false } } },
	ocuff = { dur = 1.2, base = "cb_cuff_officer", keys = { { 0, "cb_cuff_officer" }, { 0.3, "cb_cuff_officer_b" }, { 0.6, "cb_cuff_officer" }, { 0.9, "cb_cuff_officer_b" }, { 1.2, "cb_cuff_officer" } } },
}

CA.CLIP_OF = { "cb_jab", "cb_cross", "cb_hook" }
CA.POSE_OF = { handsup = "hands_up", cuffed = "cuffed", kneel = "kneel_cuff", ko = "cb_ko" }

local EMPTY = {}
local ZERO = { 0, 0, 0 }

-- joints touched by each clip (union of its keys and base), computed once: sample() never allocates
for _, clip in CA.CLIPS do
	local seen, list = {}, {}
	local function addPose(name)
		local p = name and CA.POSES[name]
		if p then
			for j in p do
				if not seen[j] then
					seen[j] = true
					table.insert(list, j)
				end
			end
		end
	end
	addPose(clip.base)
	for _, k in clip.keys do
		addPose(k[2])
	end
	clip.joints = list
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function add(out: any, j: string, p: number, y: number, r: number)
	local e = out[j]
	if not e then
		e = { 0, 0, 0, 0, 0, 0 }
		out[j] = e
	end
	e[1] += p
	e[2] += y
	e[3] += r
end

-- The clip's offset at time t (seconds) relative to clip.base, added into out[joint][1..3] (GwangalliAnim one-shot
-- outputs only carry rotations; translations come from poses).
function CA.sample(clip: any, t: number, out: any)
	local keys = clip.keys
	local a, b = keys[#keys], keys[#keys]
	for i = 1, #keys - 1 do
		if t < keys[i + 1][1] then
			a, b = keys[i], keys[i + 1]
			break
		end
	end
	local u = if b[1] > a[1] then smooth((t - a[1]) / (b[1] - a[1])) else 1
	local pa = (a[2] and CA.POSES[a[2]]) or EMPTY
	local pb = (b[2] and CA.POSES[b[2]]) or EMPTY
	local base = (clip.base and CA.POSES[clip.base]) or EMPTY
	for _, j in clip.joints do
		local A, B, Z = pa[j] or ZERO, pb[j] or ZERO, base[j] or ZERO
		local p = A[1] + (B[1] - A[1]) * u - Z[1]
		local y = A[2] + (B[2] - A[2]) * u - Z[2]
		local r = A[3] + (B[3] - A[3]) * u - Z[3]
		if p ~= 0 or y ~= 0 or r ~= 0 or out[j] then
			add(out, j, p, y, r)
		end
	end
end

-- GwangalliAnim registration (every peer that animates people: GwangalliNPCClient's police, the local player,
-- other players). Called from GwangalliAnim's own install hook and again by the combat client (no-op then).
function CA.install(Anim: any): boolean
	if type(Anim) ~= "table" or type(Anim.POSES) ~= "table" or type(Anim.EMOTES) ~= "table" or type(Anim.ACTS) ~= "table" then
		return false
	end
	if Anim.__gwCombatAnim == CA.VERSION then
		return true
	end
	for name, pose in CA.POSES do
		if Anim.POSES[name] == nil then
			Anim.POSES[name] = pose
		end
	end
	for name, clip in CA.CLIPS do
		local key = "cb_" .. name
		if Anim.EMOTES[key] == nil then
			local dur = clip.dur
			Anim.EMOTES[key] = {
				dur,
				function(u: number, out: any)
					CA.sample(clip, u * dur, out)
				end,
			}
		end
	end
	if type(Anim.GESTURES) == "table" and Anim.GESTURES.cb_cuffing == nil then
		local clip = CA.CLIPS.ocuff
		-- continuous cuffing motion on top of the cb_cuff_officer pose (fn(t, phase, out), additive)
		Anim.GESTURES.cb_cuffing = function(t: number, phase: number, out: any)
			CA.sample(clip, (t + phase * clip.dur) % clip.dur, out)
		end
	end
	local acts = Anim.ACTS
	acts.cb_guard = acts.cb_guard or { base = "idle", pose = "cb_guard", gesture = "breathe" }
	acts.surrender = acts.surrender or { base = "idle", pose = "hands_up" }
	acts.cuffed = acts.cuffed or { base = "idle", pose = "cuffed", walkPose = "cuffed" }
	acts.kneel = acts.kneel or { base = "idle", pose = "kneel_cuff" }
	acts.cb_ko = acts.cb_ko or { base = "idle", pose = "cb_ko" }
	acts.cb_cuffing = acts.cb_cuffing or { base = "idle", pose = "cb_cuff_officer", gesture = "cb_cuffing" }
	acts.cb_cower = acts.cb_cower or { base = "idle", pose = "cb_cower" }
	acts.cb_call = acts.cb_call or { base = "idle", pose = "cb_phone_call", gesture = "listen", prop = "phone" }
	Anim.__gwCombatAnim = CA.VERSION
	return true
end

-- Street-life rigs (GwangalliStreetLife Anim.POSES: motor -> CFrame offset, applied as rest * offset; no Root /
-- Neck there: the agent owns the root CFrame and the head look). Built once from the degree poses.
local DEG = math.pi / 180
local STREET_JOINTS = { RightShoulder = true, RightElbow = true, LeftShoulder = true, LeftElbow = true, Waist = true, RightHip = true, RightKnee = true, LeftHip = true, LeftKnee = true }
local function toCF(pose: any, noLegs: boolean?): { [string]: CFrame }
	local out = {}
	for j, v in pose do
		if STREET_JOINTS[j] and not (noLegs and (string.find(j, "Hip") or string.find(j, "Knee"))) then
			out[j] = CFrame.Angles((v[1] or 0) * DEG, (v[2] or 0) * DEG, (v[3] or 0) * DEG)
		end
	end
	return out
end
CA.POSE_CF = {
	-- legs stay straight on crowd rigs (their root height is fixed: a crouch would lift the feet)
	cower = toCF(CA.POSES.cb_cower, true),
	handsup = toCF(CA.POSES.hands_up),
	phonecall = toCF(CA.POSES.cb_phone_call),
	cb_flinch = toCF(CA.POSES.cb_flinchF),
	cb_guard = toCF(CA.POSES.cb_guard),
	cb_jab = toCF(CA.POSES.cb_jab),
	cb_cross = toCF(CA.POSES.cb_cross),
	cb_hook = toCF(CA.POSES.cb_hook),
}

return CA
