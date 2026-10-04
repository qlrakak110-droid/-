-- GwangalliInteractClient/Render: draws the city NPCs (workspace.GwangalliInteractNPCs) from their
-- attributes (GwangalliStreetCombatShared header). The server is the brain; this is the body:
--   GiLeg   walk the polyline (positions smoothed: no snaps on stop / re-route, a soft start and stop)
--   GiYaw   turn (smoothly; faster while walking)
--   GiPose  hold a state: sit (on the seat top) / sleep (lying) / phone / camera / talk / fight /
--           cower / cuffed / handsup / beg (on the ground)
--   GiGait  how they walk: normal brisk stroll elderly swagger bouncy drunk alert limp run
--           (step style + body sway / lean / bounce)
--   GiLook  who they look at ("p:<userId>" / "n:<npcId>"): head turn (Roblox) / body turn when idle
--   GiMood  a small icon over the head (angry / scared / embarrassed / drunk / happy / sad / hurt)
--   GiEmote one-shot gestures (bow nod shake shrug give receive stop_hand point wave cheer laugh
--           look_around punch shove hurt ...)
--   GiDown  stagger / fall / KO / get up
-- Idle people stand differently too (a thug crosses his arms, a cop keeps his hands behind his back,
-- the clerk folds hers in front).
-- In Roblox the limbs move with GwangalliAnim (walk / run tracks + procedural acts / poses /
-- gestures / emotes + head look). In the studio (Workspace.GwSimulator) explicitly named tracks
-- ("GwPose_sit", "GwEmote_bow", "GwGait_drunk") drive its NPC limb renderer instead.

local Players = game:GetService("Players")

local R = {}

local C: any
local Anim: any
local BUMP: any
local SIM = false

local recs: { [Model]: any } = {}
R.recs = recs

---------------------------------------------------------------------------------------------------
-- what each state looks like
---------------------------------------------------------------------------------------------------
-- sim = studio limb pose; act = GwangalliAnim act (Roblox); pose = GwangalliAnim / C.POSES pose (Roblox)
-- lift = root height change in studs (scaled) in the studio / rbx = in Roblox (the act's own Root offset
-- already lowers the hips there); lie = lying on the back
local STATE: { [string]: any } = {
	sit = { sim = "sit", act = "sit", lift = -1.7, rbx = -0.45 },
	sleep = { sim = "sleep", pose = "nap", lie = true },
	phone = { sim = "phone", act = "call", walk = true },
	camera = { sim = "camera", act = "photo", walk = true },
	talk = { sim = "talk", act = "talk" },
	listen = { sim = "listen", act = "listen" },
	fight = { sim = "fight", combat = true },
	cower = { sim = "cower", combat = true },
	cuffed = { sim = "cuffed", combat = true, walk = true },
	handsup = { sim = "handsup", combat = true },
	beg = { sim = "beg", combat = true, lift = -1.75, rbx = -1.75 },
	ko = { sim = "ko", combat = true },
	-- idle styles (picked here, not sent by the server)
	crossed = { sim = "crossed", act = "arms_crossed" },
	behind = { sim = "behind", act = "behind" },
	front = { sim = "front", act = "teller" },
	pockets = { sim = "behind", act = "pockets" },
}
R.STATE = STATE

-- one-shot gestures: name -> { studio pose, Roblox emote, seconds }
local EMOTE: { [string]: { any } } = {
	bow = { "bow", "bow", 1.4 },
	nod = { "nod", "nod", 0.9 },
	shake = { "shake", "shake", 1.1 },
	shrug = { "shrug", "shrug", 1.2 },
	give = { "give", "give", 1.8 },
	receive = { "receive", "receive", 1.8 },
	stop_hand = { "stop_hand", "stop_hand", 1.2 },
	think = { "think", "think", 2.2 },
	facepalm = { "facepalm", "facepalm", 1.6 },
	clap = { "clap", "clap", 1.6 },
	beckon = { "beckon", "beckon", 1.5 },
	beg = { "beckon", "beckon", 1.5 },
	point = { "point", "point", 1.4 },
	wave = { "wave", "wave", 1.6 },
	cheer = { "cheer", "cheer", 1.6 },
	laugh = { "laugh", "laugh", 1.6 },
	dance = { "dance", "dance", 3.0 },
	fool = { "flail", "cheer", 2.0 },
	look_around = { "look_around", "~look_around", 2.6 },
	startle = { "startle", "gi_hurt", 0.7 },
}

-- how each archetype stands around when nothing else is going on
local IDLE_STYLE: { [string]: string } = { thug = "crossed", police = "behind", clerk = "front" }

---------------------------------------------------------------------------------------------------
-- tracks (studio poses / your own uploaded animations in Roblox)
---------------------------------------------------------------------------------------------------
local animCache: { [string]: Animation } = {}
local function animObj(trackName: string, idKey: string?): Animation
	local a = animCache[trackName]
	if not a then
		a = Instance.new("Animation")
		a.Name = trackName
		local id = idKey and C.ANIM_IDS[idKey]
		a.AnimationId = if type(id) == "string" then id else ""
		animCache[trackName] = a
	end
	return a
end

local function animatorOf(model: Model): Animator?
	if Anim and Anim.animator then
		local ok, a = pcall(Anim.animator, model)
		if ok and a then
			return a
		end
	end
	local ctlr = model:FindFirstChildOfClass("AnimationController") or model:FindFirstChildOfClass("Humanoid")
	return ctlr and ctlr:FindFirstChildOfClass("Animator") or nil
end

local trackCache: { [Model]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any
-- a named track on a rig: studio always (the name is the pose), Roblox only with an uploaded id
local function track(model: Model, trackName: string, idKey: string?): AnimationTrack?
	if not SIM then
		local id = idKey and C.ANIM_IDS[idKey]
		if type(id) ~= "string" or id == "" then
			return nil
		end
	end
	local per = trackCache[model]
	if not per then
		per = {}
		trackCache[model] = per
	end
	local t = per[trackName]
	if t then
		return t
	end
	local animator = animatorOf(model)
	if not animator then
		return nil
	end
	local ok, tr = pcall(function()
		return animator:LoadAnimation(animObj(trackName, idKey))
	end)
	if ok and tr then
		per[trackName] = tr
		return tr
	end
	return nil
end

-- studio track name of a held key ("sit", "gait:drunk", a combat pose ...)
local function heldTrackName(key: string): (string, string?)
	if string.sub(key, 1, 5) == "gait:" then
		return "GwGait_" .. string.sub(key, 6), nil
	end
	local st = STATE[key]
	local simName = (st and st.sim) or key
	if C.TRACK[key] then
		return C.TRACK[key], key
	end
	return "GwPose_" .. simName, key
end

local function ctlOf(model: Model, rec: any?): any?
	if SIM or not Anim or not Anim.rig then
		return nil
	end
	if rec and rec.ctl then
		return rec.ctl
	end
	local ok, ctl = pcall(Anim.rig, model)
	if ok and ctl then
		if rec then
			rec.ctl = ctl
		end
		return ctl
	end
	return nil
end

-- Roblox: show a held key with GwangalliAnim (act / pose / combat pose)
local function rbxHold(model: Model, key: string, rec: any?)
	local ctl = ctlOf(model, rec)
	if not ctl then
		return
	end
	local st = STATE[key]
	pcall(function()
		if st and st.act then
			ctl:pose(nil, 0.2)
			ctl:setAct(st.act)
		elseif st and st.pose then
			ctl:setAct(nil)
			ctl:pose(st.pose, 0.3)
		elseif st and st.combat then
			ctl:setAct(nil)
			ctl:pose(C.POSES[key], 0.2)
		elseif C.POSES[key] then
			ctl:setAct(nil)
			ctl:pose(C.POSES[key], 0.2)
		else
			ctl:setAct(nil)
			ctl:pose(nil, 0.25)
		end
	end)
end

-- held-pose state of rigs that are not city NPCs (street pedestrians)
local other: { [Model]: any } = setmetatable({}, { __mode = "k" }) :: any

-- hold a pose / state key (nil = none) on a rig (city NPCs and street pedestrians)
function R.holdPose(model: Model, name: string?, rec: any?)
	local key = name or ""
	local st = rec or recs[model]
	if not st then
		st = other[model]
		if not st then
			st = {}
			other[model] = st
		end
	end
	if st and st.heldPose == key then
		return
	end
	if st then
		local prev = st.heldPose
		if prev and prev ~= "" then
			local tn, idKey = heldTrackName(prev)
			local t = track(model, tn, idKey)
			if t and t.IsPlaying then
				pcall(t.Stop, t, 0.15)
			end
		end
		st.heldPose = key
		st.heldTrack = nil
	end
	if key ~= "" then
		local tn, idKey = heldTrackName(key)
		local t = track(model, tn, idKey)
		if t then
			pcall(function()
				t.Looped = true
				t:Play(0.12)
			end)
			if st then
				st.heldTrack = t
			end
		end
	end
	-- gaits are the walk itself in Roblox (setMoving + the root sway below)
	if string.sub(key, 1, 5) ~= "gait:" then
		rbxHold(model, key, st)
	elseif st and st.rbxKey ~= "" then
		rbxHold(model, "", st)
	end
	if st then
		st.rbxKey = if string.sub(key, 1, 5) == "gait:" then "" else key
	end
end

-- a one-shot move: punch / shove / kick / hurt (combat) or a gesture (EMOTE) or a default emote
function R.move(model: Model, name: string)
	local rec = recs[model]
	if C.TRACK[name] then
		local t = track(model, C.TRACK[name], name)
		if t then
			pcall(function()
				t.Looped = false
				t:Play(0.05)
			end)
			local dur = (C.MOVES[name] and C.MOVES[name][1]) or 0.5
			if rec then
				rec.emoteTrack, rec.emoteEnd = t, os.clock() + dur
			else
				task.delay(dur, function()
					if t.IsPlaying then
						pcall(t.Stop, t, 0.1)
					end
				end)
			end
		end
		local ctl = ctlOf(model, rec)
		if ctl and C.MOVES[name] then
			pcall(ctl.emote, ctl, "gi_" .. name)
		end
		return
	end
	local e = EMOTE[name]
	if SIM then
		local simName = if e then e[1] else name
		local t = track(model, "GwEmote_" .. simName, nil)
		if t then
			pcall(function()
				t.Looped = true
				t:Play(0.08)
			end)
			local dur = if e then e[3] else 1.4
			if rec then
				if rec.emoteTrack and rec.emoteTrack ~= t and rec.emoteTrack.IsPlaying then
					pcall(rec.emoteTrack.Stop, rec.emoteTrack, 0.05)
				end
				rec.emoteTrack, rec.emoteEnd, rec.emoteName, rec.emoteT0 = t, os.clock() + dur, name, os.clock()
			else
				task.delay(dur, function()
					if t.IsPlaying then
						pcall(t.Stop, t, 0.1)
					end
				end)
			end
		end
		return
	end
	-- Roblox
	local rname = if e then e[2] else name
	local ctl = ctlOf(model, rec)
	if string.sub(rname, 1, 1) == "~" then
		-- a gesture for a while (look around)
		if ctl then
			pcall(ctl.gesture, ctl, string.sub(rname, 2))
			if rec then
				rec.gestureEnd = os.clock() + (if e then e[3] else 2)
			end
		end
		return
	end
	if ctl then
		pcall(ctl.emote, ctl, rname)
	elseif Anim and Anim.emote then
		pcall(Anim.emote, model, rname)
	end
	if rec then
		rec.emoteName, rec.emoteT0, rec.emoteEnd = name, os.clock(), os.clock() + (if e then e[3] else 1.4)
	end
end

-- the procedural combat moves as GwangalliAnim emotes (Roblox; the module table is shared per client)
local function injectEmotes()
	if not Anim or type(Anim.EMOTES) ~= "table" then
		return
	end
	for name, mv in C.MOVES do
		local key = "gi_" .. name
		if not Anim.EMOTES[key] then
			local fn = mv[2]
			Anim.EMOTES[key] = { mv[1], function(u, out)
				local ok, t = pcall(fn, u)
				if not ok or type(t) ~= "table" then
					return
				end
				for j, v in t do
					local e = out[j]
					if not e then
						e = { 0, 0, 0, 0, 0, 0 }
						out[j] = e
					end
					e[1] += v[1] or 0
					e[2] += v[2] or 0
					e[3] += v[3] or 0
				end
			end }
		end
	end
end

---------------------------------------------------------------------------------------------------
-- paths
---------------------------------------------------------------------------------------------------
local function parsePath(s: any): any?
	if type(s) ~= "string" then
		return nil
	end
	local parts = string.split(s, ";")
	if parts[1] ~= "P" or #parts < 4 then
		return nil
	end
	local t0, speed = tonumber(parts[2]), tonumber(parts[3])
	if not t0 or not speed then
		return nil
	end
	local pts = {}
	for i = 4, #parts do
		local v = string.split(parts[i], ",")
		local x, y, z = tonumber(v[1]), tonumber(v[2]), tonumber(v[3])
		if x and y and z then
			table.insert(pts, Vector3.new(x, y, z))
		end
	end
	if #pts == 0 then
		return nil
	end
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	return { pts = pts, cum = cum, len = cum[#cum], t0 = t0, speed = math.max(0.5, speed) }
end

-- feet position + movement direction (nil = standing) at server time `now`
local function pathAt(path: any, now: number): (Vector3, Vector3?)
	local dist = (now - path.t0) * path.speed
	if dist <= 0 or #path.pts == 1 then
		return path.pts[1], nil
	end
	if dist >= path.len then
		return path.pts[#path.pts], nil
	end
	for i = 2, #path.pts do
		if path.cum[i] >= dist then
			local seg = path.cum[i] - path.cum[i - 1]
			local u = if seg > 1e-4 then (dist - path.cum[i - 1]) / seg else 1
			local d = path.pts[i] - path.pts[i - 1]
			return path.pts[i - 1]:Lerp(path.pts[i], u), Vector3.new(d.X, 0, d.Z)
		end
	end
	return path.pts[#path.pts], nil
end
R.pathAt = pathAt

-- where the body is drawn (smoothed) — gameplay code uses this for targeting
function R.feetOf(model: Model): Vector3?
	local rec = recs[model]
	if not rec or not rec.path then
		return nil
	end
	if rec.drawn then
		return rec.drawn
	end
	local p = pathAt(rec.path, workspace:GetServerTimeNow())
	return p
end

---------------------------------------------------------------------------------------------------
-- look targets / mood icons
---------------------------------------------------------------------------------------------------
local function lookPos(key: string?): Vector3?
	if type(key) ~= "string" or key == "" then
		return nil
	end
	local kind, id = string.match(key, "^(%a):(.+)$")
	if kind == "p" then
		local p = Players:GetPlayerByUserId(tonumber(id) or 0)
		local h = p and p.Character and p.Character:FindFirstChild("Head")
		return h and (h :: BasePart).Position or nil
	elseif kind == "n" then
		local other = R.byId(id)
		if other and other.drawn then
			return other.drawn + Vector3.new(0, 4.5 * other.scale, 0)
		end
	end
	return nil
end

local MOOD_ICON: { [string]: { any } } = {
	angry = { "💢", Color3.fromRGB(255, 80, 70) },
	scared = { "💦", Color3.fromRGB(120, 190, 255) },
	embarrassed = { "😳", Color3.fromRGB(255, 160, 170) },
	drunk = { "🍺", Color3.fromRGB(255, 200, 90) },
	happy = { "♪", Color3.fromRGB(120, 230, 140) },
	sad = { "💧", Color3.fromRGB(140, 170, 255) },
	hurt = { "✚", Color3.fromRGB(255, 110, 110) },
	surprised = { "❗", Color3.fromRGB(255, 230, 90) },
}

local function setMoodIcon(rec: any, mood: string?, near: boolean)
	local want = if near and mood then MOOD_ICON[mood] else nil
	local gui = rec.moodGui
	if not want then
		if gui then
			gui.Enabled = false
		end
		return
	end
	if not gui then
		local head = rec.model:FindFirstChild("Head")
		if not head then
			return
		end
		gui = Instance.new("BillboardGui")
		gui.Name = "GiMoodTag"
		gui.Size = UDim2.fromOffset(34, 34)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 4.1, 0)
		gui.MaxDistance = 45
		gui.LightInfluence = 0
		gui.Adornee = head
		local l = Instance.new("TextLabel")
		l.Name = "Icon"
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.TextStrokeTransparency = 0.5
		l.Parent = gui
		gui.Parent = head
		rec.moodGui = gui
	end
	local l = gui:FindFirstChild("Icon") :: TextLabel?
	if l and l.Text ~= want[1] then
		l.Text = want[1]
		l.TextColor3 = want[2]
	end
	gui.Enabled = true
end

---------------------------------------------------------------------------------------------------
-- records
---------------------------------------------------------------------------------------------------
local function readAttrs(rec: any)
	local m = rec.model
	local np = parsePath(m:GetAttribute("GiLeg"))
	if np then
		rec.path = np
	end
	rec.yawT = math.rad(tonumber(m:GetAttribute("GiYaw")) or 0)
	rec.pose = m:GetAttribute("GiPose") or ""
	rec.gait = m:GetAttribute("GiGait") or "normal"
	rec.look = m:GetAttribute("GiLook") or ""
	rec.mood = m:GetAttribute("GiMood") or "neutral"
	rec.mode = m:GetAttribute("GiMode") or "routine"
	rec.arch = m:GetAttribute("GiArch") or rec.kind
	local t0, dx, dz, outcome, dur = C.decodeDown(m:GetAttribute("GiDown"))
	rec.down = if t0 then { t0 = t0, dx = dx, dz = dz, outcome = outcome, dur = dur } else nil
end

local function onEmote(rec: any)
	local s = rec.model:GetAttribute("GiEmote")
	if type(s) ~= "string" or s == "" or s == rec.emoteKey then
		return
	end
	rec.emoteKey = s
	local p = string.split(s, "#")
	local name, t = p[1], tonumber(p[3])
	if not name or not t or math.abs(workspace:GetServerTimeNow() - t) > 3 then
		return
	end
	R.move(rec.model, name)
end

local function hash(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 100003
	end
	return h
end

local function addModel(m: Instance)
	if not m:IsA("Model") or recs[m] then
		return
	end
	local id = m:GetAttribute("GiId")
	local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
	if type(id) ~= "string" or not root or not root:IsA("BasePart") then
		return
	end
	local rec = {
		model = m,
		root = root,
		id = id,
		kind = m:GetAttribute("GiKind"),
		ground = tonumber(m:GetAttribute("GiGround")) or 3,
		scale = tonumber(m:GetAttribute("GiScale")) or 1,
		yaw = 0,
		heldPose = nil,
		conns = {},
		lift = 0,
		lie = 0,
		stepPhase = 0,
		seed = (hash(id) % 1000) / 1000 * math.pi * 2,
	}
	readAttrs(rec)
	rec.yaw = rec.yawT
	rec.emoteKey = m:GetAttribute("GiEmote")
	recs[m] = rec
	table.insert(rec.conns, m.AttributeChanged:Connect(function(attr)
		if attr == "GiEmote" then
			onEmote(rec)
		elseif string.sub(attr, 1, 2) == "Gi" then
			readAttrs(rec)
		end
	end))
	ctlOf(m, rec)
end

local function removeModel(m: Instance)
	local rec = recs[m :: Model]
	if not rec then
		return
	end
	for _, c in rec.conns do
		c:Disconnect()
	end
	recs[m :: Model] = nil
end

local function angDiff(a: number, b: number): number
	local d = (b - a) % (2 * math.pi)
	if d > math.pi then
		d -= 2 * math.pi
	end
	return d
end

-- body sway / lean / bounce of a gait (radians / studs): side, up, lean (forward +), roll, yaw wobble
local function gaitMotion(rec: any, moving: boolean, t: number): (number, number, number, number, number)
	local g = rec.gait
	local ph = rec.stepPhase
	local s = rec.scale
	if g == "drunk" then
		local w = t * 1.7 + rec.seed
		local amt = if moving then 1 else 0.45
		return 0.32 * math.sin(w) * amt * s, 0, 0.04, 0.08 * math.sin(w) * amt, if moving then 0.12 * math.sin(t * 0.9 + rec.seed) else 0
	elseif g == "swagger" then
		return 0, 0, -0.03, if moving then 0.06 * math.sin(ph) else 0, if moving then 0.06 * math.sin(ph) else 0
	elseif g == "bouncy" then
		if moving then
			return 0, 0.32 * math.abs(math.sin(ph)) * s, 0.02, 0.05 * math.sin(ph), 0
		end
		return 0, 0.14 * math.max(0, math.sin(t * 2.6 + rec.seed)) ^ 6 * s, 0, 0, 0
	elseif g == "elderly" then
		return 0, if moving then 0.05 * math.abs(math.sin(ph)) * s else 0, 0.14, 0, 0
	elseif g == "limp" then
		return 0, if moving then -0.16 * math.max(0, math.sin(ph)) * s else 0, 0.05, if moving then 0.06 * math.sin(ph) else 0, 0
	elseif g == "run" then
		return 0, 0, if moving then 0.14 else 0, 0, 0
	elseif g == "brisk" then
		return 0, 0, if moving then 0.05 else 0, 0, 0
	elseif g == "alert" then
		return 0, 0, 0, 0, 0
	end
	return 0, 0, 0, 0, 0
end

local function stepRec(rec: any, dt: number, now: number, cam: Vector3)
	local path = rec.path
	if not path then
		return
	end
	local t = os.clock()
	local target, dir = pathAt(path, now)
	-- smoothed position: no snap when a walk is cut short / re-routed; a soft start and stop
	local drawn = rec.drawn
	if not drawn or (target - drawn).Magnitude > 7 then
		drawn = target
	else
		local k = 1 - math.exp(-dt * 11)
		drawn = drawn:Lerp(target, k)
	end
	local moved = if rec.drawn then Vector3.new(drawn.X - rec.drawn.X, 0, drawn.Z - rec.drawn.Z).Magnitude else 0
	rec.drawn = drawn
	local speedNow = if dt > 0 then moved / dt else 0
	local moving = dir ~= nil or speedNow > 1.2
	rec.stepPhase += moved / (2.6 * rec.scale) * math.pi
	local dist = (drawn - cam).Magnitude
	local far = dist > 220
	local near = dist < 60
	-- facing: the walking direction, else a look target when idle, else the server's yaw
	local want = rec.yawT
	local lp = lookPos(rec.look)
	local st = STATE[rec.pose]
	local seated = st and (st.lift or st.lie) and true or false
	if dir and dir.Magnitude > 0.05 then
		want = math.atan2(-dir.X, -dir.Z)
	elseif lp and not seated and not rec.down then
		local d = lp - drawn
		if d.X * d.X + d.Z * d.Z > 0.25 then
			if SIM then
				want = math.atan2(-d.X, -d.Z) -- the studio has no head turn: the body turns
			else
				-- Roblox: the head does most of it; the body follows past ~70 degrees
				local full = math.atan2(-d.X, -d.Z)
				local diff = angDiff(rec.yawT, full)
				if math.abs(diff) > math.rad(70) then
					want = full
				end
			end
		end
	end
	local diff = angDiff(rec.yaw, want)
	local turn = math.rad(if dir then 480 else 260) * dt
	rec.yaw += math.clamp(diff, -turn, turn)
	-- one-shot gestures that move the whole body in the studio (it has no waist / neck)
	local extraYaw, extraPitch = 0, 0
	if rec.emoteEnd and t >= rec.emoteEnd then
		local et = rec.emoteTrack
		rec.emoteEnd, rec.emoteTrack = nil, nil
		if et and et.IsPlaying then
			pcall(et.Stop, et, 0.1)
		end
		-- the studio keeps one pose per rig: put the held one back
		if SIM and rec.heldTrack then
			pcall(rec.heldTrack.Play, rec.heldTrack, 0.1)
		end
	end
	if SIM and rec.emoteEnd and rec.emoteT0 then
		local u = t - rec.emoteT0
		if rec.emoteName == "bow" then
			extraPitch = 0.42 * math.sin(math.clamp(u / 1.4, 0, 1) * math.pi)
		elseif rec.emoteName == "nod" then
			extraPitch = 0.12 * math.max(0, math.sin(u * math.pi * 2.2))
		elseif rec.emoteName == "look_around" then
			extraYaw = 0.55 * math.sin(u / 2.6 * math.pi * 2)
		elseif rec.emoteName == "shake" then
			extraYaw = 0.12 * math.sin(u * 18)
		end
	end
	if not SIM and rec.gestureEnd and t >= rec.gestureEnd then
		rec.gestureEnd = nil
		local ctl = rec.ctl
		if ctl then
			pcall(ctl.gesture, ctl, nil)
			rbxHold(rec.model, rec.rbxKey or "", rec)
		end
	end
	-- the body
	local down = rec.down
	local cf
	local pose = rec.pose
	local lying = false
	if down then
		local phase, k = C.downPhase(now - down.t0, down.outcome, down.dur)
		if phase == "done" then
			rec.down = nil
			down = nil
		elseif down.outcome == "stagger" then
			local off, lean = Vector3.zero, 0
			if BUMP and BUMP.staggerOffset then
				off, lean = BUMP.staggerOffset(down.dx, down.dz, k, rec.scale)
			end
			cf = CFrame.new(drawn + off + Vector3.new(0, rec.ground, 0)) * CFrame.Angles(0, rec.yaw, 0) * CFrame.Angles(0, 0, lean)
			pose = "hurt"
		else
			lying = phase == "down" or phase == "fall"
			if BUMP and BUMP.fallRootCFrame then
				cf = BUMP.fallRootCFrame(drawn, rec.yaw, down.dx, down.dz, k, rec.ground, rec.scale)
			else
				cf = CFrame.new(drawn + Vector3.new(0, rec.ground * (1 - 0.7 * k), 0)) * CFrame.Angles(0, rec.yaw, 0) * CFrame.Angles(k * math.pi * 0.5, 0, 0)
			end
			pose = if lying then "ko" else ""
		end
	end
	if not cf then
		-- seated / lying heights blend in (sitting down and getting up take a moment)
		local liftT = 0
		local lieT = 0
		if st and not moving then
			liftT = ((if SIM then st.lift else st.rbx) or 0) * rec.scale
			lieT = if st.lie then 1 else 0
		end
		rec.lift += (liftT - rec.lift) * (1 - math.exp(-dt * 7))
		rec.lie += (lieT - rec.lie) * (1 - math.exp(-dt * 5))
		local side, up, lean, roll, wob = gaitMotion(rec, moving, t)
		if seated or rec.down then
			side, up, lean, roll, wob = 0, 0, 0, 0, 0
		end
		local base = CFrame.new(drawn) * CFrame.Angles(0, rec.yaw + wob + extraYaw, 0) * CFrame.new(side, up, 0)
		if rec.lie > 0.01 then
			-- lying on the back along the facing (the head where they came from)
			local h = rec.ground + (0.55 * rec.scale - rec.ground) * rec.lie
			cf = base * CFrame.new(0, h, 0) * CFrame.Angles(rec.lie * math.pi / 2, 0, 0)
		else
			cf = base * CFrame.Angles(-(lean + extraPitch), 0, roll) * CFrame.new(0, rec.ground + rec.lift, 0)
		end
	end
	if not far then
		rec.root.CFrame = cf
	elseif not rec.farT or now - rec.farT > 0.5 then
		rec.farT = now
		rec.root.CFrame = cf
	end
	-- limbs: the held state (or the gait while walking, or the idle style)
	local key = pose
	if key == "beg" and moving then
		key = ""
	end
	if key ~= "" and moving and st and not st.walk and not st.combat then
		key = "" -- people stand up to walk
	end
	if key == "" and not lying then
		if moving then
			key = if SIM and rec.gait ~= "normal" then "gait:" .. rec.gait else ""
		elseif not rec.emoteEnd and near then
			key = IDLE_STYLE[rec.arch or ""] or (if rec.gait == "elderly" then "behind" else "")
		end
	end
	R.holdPose(rec.model, if key ~= "" then key else nil, rec)
	setMoodIcon(rec, rec.mood, near)
	local ctl = rec.ctl
	if ctl and not far then
		local speed = 0
		if moving then
			speed = if dir then path.speed else speedNow
		end
		local sp = math.floor(speed * 2 + 0.5) / 2
		if sp ~= (rec.lastSpeed or -1) then
			rec.lastSpeed = sp
			pcall(ctl.setMoving, ctl, if sp > 0.3 and not lying then sp else nil)
		end
		-- head turn toward whoever they are dealing with
		local lookAt = if lp and not lying then lp else nil
		if lookAt ~= rec.lastLook then
			rec.lastLook = lookAt
			pcall(ctl.look, ctl, lookAt)
		end
		-- drunk sway gesture while standing
		local g = if rec.gait == "drunk" and not moving and key == "" then "sway" else nil
		if g ~= rec.gesture and not rec.gestureEnd then
			rec.gesture = g
			pcall(ctl.gesture, ctl, g)
		end
		if ctl.setDetail then
			local detail = if dist < 50 then 2 elseif dist < 120 then 1 else 0
			if detail ~= rec.detail then
				rec.detail = detail
				pcall(ctl.setDetail, ctl, detail)
			end
		end
		if dist < 120 or (now - (rec.ctlT or 0)) > 0.2 then
			rec.ctlT = now
			pcall(ctl.step, ctl)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- patrol car light bars
---------------------------------------------------------------------------------------------------
local cars: { [Model]: { r: BasePart?, b: BasePart? } } = {}
local function addCar(m: Instance)
	if not m:IsA("Model") or not m:GetAttribute("GiCar") then
		return
	end
	task.defer(function()
		cars[m :: Model] = { r = m:FindFirstChild("GiLightR", true) :: BasePart?, b = m:FindFirstChild("GiLightB", true) :: BasePart? }
	end)
end

local flashT = 0
local function stepCars(dt: number)
	flashT += dt
	local phase = math.floor(flashT * 6) % 2 == 0
	for m, c in cars do
		if not m.Parent then
			cars[m] = nil
			continue
		end
		if not c.r or not c.b then
			c.r = m:FindFirstChild("GiLightR", true) :: BasePart?
			c.b = m:FindFirstChild("GiLightB", true) :: BasePart?
			continue
		end
		local on = m:GetAttribute("GiSiren") == true
		local rOn, bOn = on and phase, on and not phase
		local rl = (c.r :: BasePart):FindFirstChildOfClass("PointLight")
		local bl = (c.b :: BasePart):FindFirstChildOfClass("PointLight")
		local rt = if rOn then 0 else 0.65
		local bt = if bOn then 0 else 0.65
		if (c.r :: BasePart).Transparency ~= rt then
			(c.r :: BasePart).Transparency = rt
		end
		if (c.b :: BasePart).Transparency ~= bt then
			(c.b :: BasePart).Transparency = bt
		end
		if rl and rl.Enabled ~= rOn then
			rl.Enabled = rOn
		end
		if bl and bl.Enabled ~= bOn then
			bl.Enabled = bOn
		end
	end
end

function R.step(dt: number)
	local now = workspace:GetServerTimeNow()
	local cam = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or Vector3.zero
	for _, rec in recs do
		if rec.model.Parent then
			local ok, err = pcall(stepRec, rec, dt, now, cam)
			if not ok and not rec.warned then
				rec.warned = true
				warn("[GwangalliInteract] render " .. tostring(rec.id) .. ": " .. tostring(err))
			end
		end
	end
	stepCars(dt)
end

-- the record of a city NPC by id
function R.byId(id: string): any?
	for _, rec in recs do
		if rec.id == id then
			return rec
		end
	end
	return nil
end

function R.init(deps: any)
	C = deps.C
	Anim = deps.Anim
	BUMP = deps.BUMP
	SIM = deps.SIM
	injectEmotes()
	task.spawn(function()
		local folder = workspace:WaitForChild(C.NpcFolder, 60)
		if not folder then
			return
		end
		folder.ChildAdded:Connect(function(m)
			task.defer(addModel, m)
		end)
		folder.ChildRemoved:Connect(removeModel)
		for _, m in folder:GetChildren() do
			addModel(m)
		end
	end)
	task.spawn(function()
		local f = workspace:WaitForChild("GwangalliInteractCars", 60)
		if not f then
			return
		end
		f.ChildAdded:Connect(addCar)
		for _, m in f:GetChildren() do
			addCar(m)
		end
	end)
end

return R
