-- GwangalliNPCClient (LocalScript, StarterPlayerScripts; owner: npc_key): client-side choreography
-- of the key NPCs. Camera and animation only (no GUI).
--   * KEY NPC MOTION: workspace.GwangalliNPCs models with attribute NpcId (server NPC.luau). The
--     server only writes attributes (contract in NPC.luau's header): this script interpolates the
--     walk (NpcLeg: a straight leg or a polyline walk between posts, server clock), turns the body
--     smoothly (NpcYaw), plays the GwangalliAnim act (NpcAct: base track + pose + gesture, prop
--     visibility), one-shot emotes (NpcEmote), head look-at (NpcLook / NpcTalk / the local
--     conversation) and talk gestures.
--   * LOD (GwangalliQuality tier, the saver tier included): within `near` everything (every frame
--     within 9 studs / in a conversation, 15 Hz beyond);
--     up to `anim` pose + emotes (no gestures / head turns) at 10 Hz; up to `far` only the base
--     track (the walk while walking); walkers are moved every frame out to `far` (one CFrame write
--     each), standing NPCs at a low rate; beyond `far` only the position, twice a second.
--   * HAND-OVERS (SocialState): a gift / drink bought for someone (affinity source gift, giftbad,
--     bday, drink): your right arm reaches out, a small gift box (or cup) travels from your hand
--     into theirs and a key NPC takes it with both hands; a number swap (contact added): both
--     phones come out together for a moment. Local only (animation + a client-side prop).
--   * CONVERSATIONS (GwangalliRemotes.Dialog): the NPC faces you and talks with its hands; the
--     camera eases into an over-the-shoulder shot that keeps the NPC clear of the dialog sheet and
--     eases back when the dialog ends (no framing for phone calls, while driving / seated, or when
--     another script owns the camera; workspace or player attribute GwangalliDialogCam = false
--     disables it); your character turns toward the NPC, waves hello and mirrors big reactions
--     (cheer, laugh, dance). SocialState "line" emote hints animate street key NPCs too.
--   * SEATED (NpcSeat = "<car model in workspace.GwangalliLawCars>|x,y,z", Law/Police crews): the rig
--     rides on that car's seat every frame (root = car root * offset, act "sit"), animated at any
--     distance so it never stands up through the roof; NpcSeat cleared = back to the NpcLeg walk
--     (the server starts the exit leg at the seat, so getting out is seen, never a jump).
--   * STREAMING: a model whose root arrives after the model (non-atomic streaming) is picked up
--     when its root streams in.
--   * Pedestrian citizens are GwangalliStreetLife's (it animates their conversations); the camera
--     still frames them when their rig model carries attribute CitizenId = <id>.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local function optional(name: string, timeout: number?): any
	local m = ReplicatedStorage:WaitForChild(name, timeout or 20)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliNPCClient] " .. name .. " failed to load: " .. tostring(res))
	return nil
end

local Anim = optional("GwangalliAnim", 30)
if not Anim then
	warn("[GwangalliNPCClient] ReplicatedStorage.GwangalliAnim missing; key NPCs stay still")
	return
end
local Quality = optional("GwangalliQuality", 10)

local LOD = {
	saver = { near = 22, anim = 45, far = 110, farHz = 2 },
	low = { near = 30, anim = 70, far = 150, farHz = 3 },
	mid = { near = 45, anim = 100, far = 200, farHz = 4 },
	high = { near = 70, anim = 140, far = 260, farHz = 6 },
}
local lod = LOD.high
local function applyTier()
	local t = "high"
	if Quality then
		local ok, v = pcall(Quality.get)
		if ok and type(v) == "string" then
			t = v
		end
		local okS, saver = pcall(function()
			return Quality.isSaver and Quality.isSaver()
		end)
		if okS and saver then
			t = "saver"
		end
	end
	lod = LOD[t] or LOD.high
end
applyTier()
if Quality and Quality.changed then
	Quality.changed:Connect(applyTier)
end
if Quality and Quality.saverChanged then
	Quality.saverChanged:Connect(applyTier)
end

local TURN_RATE = math.rad(300) -- body turn speed (rad / s)
local MID_HZ = 10 -- pose + emotes past `near`
local NEAR_HZ = 15 -- the full procedural layers within `near` but beyond CLOSE
local CLOSE = 9 -- conversation distance: every frame

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

local function angleDiff(a: number, b: number): number
	return (b - a + math.pi) % (2 * math.pi) - math.pi
end

-------------------------------------------------------------------------------------------------
-- Records
-------------------------------------------------------------------------------------------------
type Rec = {
	model: Model,
	root: BasePart,
	id: string,
	street: boolean,
	ctl: any,
	ground: number,
	leg: any?,
	basePos: Vector3,
	pos: Vector3,
	yaw: number,
	attrYaw: number,
	act: string,
	lookUser: number,
	talkUser: number,
	emoteKey: string,
	props: { [BasePart]: string },
	lastWrite: CFrame?,
	nextUpdate: number,
	lastT: number,
	animated: boolean,
	dist: number,
	conns: { RBXScriptConnection },
	localTalk: boolean,
	moving: boolean,
	level: number, -- LOD detail: 2 near, 1 mid, 0 far (tracks only), -1 beyond
	nextStep: number,
	forceProp: string?, -- a prop shown for a moment (the phone in a number swap)
	forcePropUntil: number,
	verifyAt: number,
	seatCar: string?, -- NpcSeat: the patrol car this rig sits in
	seatOff: Vector3?,
}
local recs: { [Model]: Rec } = {}
local byId: { [string]: Rec } = {}

-- "P;t0;speed;x,y,z;x,y,z;...": a polyline walk at a constant speed (walks between posts).
local function parsePath(s: string): any?
	local v = string.split(s, ";")
	local t0, speed = tonumber(v[2]), tonumber(v[3])
	if not t0 or not speed or speed <= 0 or #v < 5 then
		return nil
	end
	local pts: { Vector3 } = {}
	local cum = { 0 }
	for i = 4, #v do
		local c = string.split(v[i], ",")
		local x, y, z = tonumber(c[1]), tonumber(c[2]), tonumber(c[3])
		if not x or not y or not z then
			return nil
		end
		local p = Vector3.new(x, y, z)
		if #pts > 0 then
			cum[#pts + 1] = cum[#pts] + (p - pts[#pts]).Magnitude
		end
		table.insert(pts, p)
	end
	local total = cum[#pts]
	return { from = pts[1], to = pts[#pts], t0 = t0, dur = math.max(total / speed, 0.01), speed = speed, yaw = nil, poly = { pts = pts, cum = cum, total = total }, seg = 2 }
end

-- Position and heading along a polyline leg at progress a (0..1); remembers the segment it was on.
local function polyAt(leg: any, a: number): (Vector3, number?)
	local poly = leg.poly
	local pts, cum = poly.pts, poly.cum
	local dist = a * poly.total
	local i = leg.seg or 2
	if i > #pts or cum[i - 1] > dist then
		i = 2
	end
	while i < #pts and cum[i] < dist do
		i += 1
	end
	leg.seg = i
	local seg = cum[i] - cum[i - 1]
	local u = if seg > 1e-4 then math.clamp((dist - cum[i - 1]) / seg, 0, 1) else 1
	local d = pts[i] - pts[i - 1]
	local yaw = if Vector3.new(d.X, 0, d.Z).Magnitude > 0.05 then yawOf(d) else nil
	return pts[i - 1]:Lerp(pts[i], u), yaw
end

local function parseLeg(s: any): any?
	if type(s) ~= "string" or s == "" then
		return nil
	end
	if string.sub(s, 1, 2) == "P;" then
		return parsePath(s)
	end
	local v = string.split(s, ",")
	if #v < 8 then
		return nil
	end
	local n = {}
	for i = 1, 8 do
		n[i] = tonumber(v[i])
		if not n[i] then
			return nil
		end
	end
	local from = Vector3.new(n[1], n[2], n[3])
	local to = Vector3.new(n[4], n[5], n[6])
	local d = to - from
	return { from = from, to = to, t0 = n[7], dur = math.max(n[8], 0.01), speed = Vector3.new(d.X, 0, d.Z).Magnitude / math.max(n[8], 0.01), yaw = if Vector3.new(d.X, 0, d.Z).Magnitude > 0.05 then yawOf(d) else nil }
end

local function wantedProp(act: string, model: Model): string?
	local a = Anim.ACTS[act]
	local p = a and a.prop
	if p == "camera" and not model:FindFirstChild("Camera") then
		p = "phone" -- a selfie with the phone
	end
	return p
end

local function applyProps(rec: Rec)
	local want = wantedProp(rec.act, rec.model)
	if rec.forceProp and os.clock() < rec.forcePropUntil then
		want = rec.forceProp
	elseif rec.moving then
		local a = Anim.ACTS[rec.act]
		if not (a and a.walkPose) then
			want = nil
		end
	end
	for part, prop in rec.props do
		if part.Parent then
			local t = if prop == want then 0 else 1
			if part.Transparency ~= t then
				part.Transparency = t
			end
		end
	end
end

local function readAttrs(rec: Rec)
	local m = rec.model
	local legStr = m:GetAttribute("NpcLeg")
	local leg = parseLeg(legStr)
	if leg == nil and rec.leg ~= nil then
		rec.basePos = rec.root.Position - Vector3.new(0, rec.ground, 0) -- the server placed it
	end
	rec.leg = leg
	local y = m:GetAttribute("NpcYaw")
	if type(y) == "number" then
		rec.attrYaw = math.rad(y)
	end
	local act = m:GetAttribute("NpcAct")
	if type(act) == "string" and act ~= rec.act then
		rec.act = act
		applyProps(rec)
	end
	local lu = m:GetAttribute("NpcLook")
	rec.lookUser = if type(lu) == "number" then lu else 0
	local tu = m:GetAttribute("NpcTalk")
	rec.talkUser = if type(tu) == "number" then tu else 0
	local seat = m:GetAttribute("NpcSeat")
	rec.seatCar, rec.seatOff = nil, nil
	if type(seat) == "string" and seat ~= "" then
		local carName, xyz = string.match(seat, "^(.-)|(.+)$")
		local n = xyz and string.split(xyz, ",")
		if carName and n and #n == 3 and tonumber(n[1]) and tonumber(n[2]) and tonumber(n[3]) then
			rec.seatCar = carName
			rec.seatOff = Vector3.new(tonumber(n[1]) :: number, tonumber(n[2]) :: number, tonumber(n[3]) :: number)
		end
	end
	rec.nextUpdate = 0
end

local lawCars: Instance? = nil
local function seatRoot(rec: Rec): BasePart?
	if not rec.seatCar then
		return nil
	end
	lawCars = if lawCars and lawCars.Parent then lawCars else workspace:FindFirstChild("GwangalliLawCars")
	local car = lawCars and lawCars:FindFirstChild(rec.seatCar)
	local root = car and ((car :: any).PrimaryPart or car:FindFirstChild("CarRoot"))
	return if root and root:IsA("BasePart") then root else nil
end

local function playEmote(rec: Rec, name: string)
	if rec.animated and rec.dist <= lod.anim then
		rec.ctl:emote(name)
	end
end

local function onEmoteAttr(rec: Rec)
	local s = rec.model:GetAttribute("NpcEmote")
	if type(s) ~= "string" or s == "" or s == rec.emoteKey then
		return
	end
	rec.emoteKey = s
	local parts = string.split(s, "#")
	local name, t = parts[1], tonumber(parts[3])
	if name and name ~= "" and t and math.abs(serverNow() - t) < 3 then
		playEmote(rec, name)
	end
end

-- 어깨빵 knockdown (server attribute "t0|dx|dz|outcome", GwangalliBumpShared): the fall timeline runs
-- in update() from the server clock so every client shows the same moment
local BumpShared: any = optional("GwangalliBumpShared")
local function onKnockAttr(rec: Rec)
	if not BumpShared then
		return
	end
	local t0, dx, dz, outcome = BumpShared.decodeKnock(rec.model:GetAttribute("NpcKnock"))
	if not t0 or math.abs(serverNow() - t0) > 6 then
		return
	end
	(rec :: any).knock = { t0 = t0, dx = dx, dz = dz, outcome = outcome, phase = "" }
	rec.nextUpdate = 0
	if rec.animated then
		pcall(function()
			rec.ctl:pose(if outcome == "knockdown" then "knock" else "stagger", 0.15)
		end)
	end
end

local function removeRec(model: Model)
	local rec = recs[model]
	if not rec then
		return
	end
	recs[model] = nil
	if byId[rec.id] == rec then
		byId[rec.id] = nil
	end
	for _, c in rec.conns do
		c:Disconnect()
	end
	pcall(function()
		rec.ctl:destroy()
	end)
end

local function addModel(model: Instance)
	if not model:IsA("Model") or recs[model] then
		return
	end
	local id = model:GetAttribute("NpcId")
	if type(id) ~= "string" then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root or not root:IsA("BasePart") then
		return
	end
	local ground = model:GetAttribute("NpcGround")
	ground = if type(ground) == "number" then ground else 3
	local cf = root.CFrame
	local rec: Rec = {
		model = model,
		root = root,
		id = id,
		street = model:GetAttribute("NpcKind") == "street",
		ctl = Anim.rig(model),
		ground = ground,
		leg = nil,
		basePos = cf.Position - Vector3.new(0, ground, 0),
		pos = cf.Position - Vector3.new(0, ground, 0),
		yaw = yawOf(cf.LookVector),
		attrYaw = yawOf(cf.LookVector),
		act = "",
		lookUser = 0,
		talkUser = 0,
		emoteKey = "",
		props = {},
		lastWrite = nil,
		nextUpdate = 0,
		lastT = os.clock(),
		animated = true,
		dist = math.huge,
		conns = {},
		localTalk = false,
		moving = false,
		level = -1,
		nextStep = 0,
		forceProp = nil,
		forcePropUntil = 0,
		verifyAt = 0,
	}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d:GetAttribute("Prop")
			if type(p) == "string" then
				rec.props[d] = p
			end
		end
	end
	-- the current emote is history: only new ones play
	local e = model:GetAttribute("NpcEmote")
	rec.emoteKey = if type(e) == "string" then e else ""
	recs[model] = rec
	byId[id] = rec
	readAttrs(rec)
	rec.ctl:setAnimated(false) -- LOD turns it on when close
	rec.animated = false
	table.insert(rec.conns, model.AttributeChanged:Connect(function(name: string)
		if name == "NpcEmote" then
			onEmoteAttr(rec)
		elseif name == "NpcKnock" then
			onKnockAttr(rec)
		elseif name == "NpcLeg" or name == "NpcYaw" or name == "NpcAct" or name == "NpcLook" or name == "NpcTalk" or name == "NpcSeat" then
			readAttrs(rec)
		end
	end))
	table.insert(rec.conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			removeRec(model)
		end
	end))
end

-------------------------------------------------------------------------------------------------
-- Conversation state (Dialog remote)
-------------------------------------------------------------------------------------------------
local talk = {
	id = nil :: string?,
	remote = false,
	lastPayload = 0,
	openedAt = 0,
	greeted = {} :: { [string]: number },
	spotDirty = false, -- the sheet changed: measure where it leaves room for the NPC (camera)
	nx = nil :: number?,
	ny = nil :: number?,
}

local function characterParts(): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if hum and root and root:IsA("BasePart") and hum.Health > 0 then
		return char, hum, root
	end
	return nil, nil, nil
end

local function headOf(model: Model?): Vector3?
	if not model then
		return nil
	end
	local h = model:FindFirstChild("Head")
	if h and h:IsA("BasePart") then
		return h.Position
	end
	local r = model:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r.Position + Vector3.new(0, 1.6, 0)
	end
	return nil
end

local function playerHead(userId: number): Vector3?
	if userId == 0 then
		return nil
	end
	local p = if userId == player.UserId then player else Players:GetPlayerByUserId(userId)
	return p and headOf(p.Character) or nil
end

-------------------------------------------------------------------------------------------------
-- Per-NPC update
-------------------------------------------------------------------------------------------------
local function update(rec: Rec, now: number, sNow: number)
	local dt = math.min(now - rec.lastT, 0.5)
	rec.lastT = now
	if rec.seatOff then
		local carRoot = seatRoot(rec)
		if carRoot then
			local cf = carRoot.CFrame * CFrame.new(rec.seatOff)
			rec.root.CFrame = cf
			rec.lastWrite = cf
			rec.pos = cf.Position - Vector3.new(0, rec.ground, 0)
			rec.basePos = rec.pos
			rec.yaw = yawOf(cf.LookVector)
			if rec.moving then
				rec.moving = false
				applyProps(rec)
			end
			if rec.animated then
				rec.ctl:setMoving(nil)
				rec.ctl:setAct("idle")
				rec.ctl:look(nil)
			end
			-- the sitting itself is the R15 sit TRACK (a procedural pose would not lower the body on
			-- every renderer; the track does, and it keeps the head under the roof)
			if not (rec :: any).sitTrack then
				local okT, tr = pcall(Anim.play, rec.model, "sit", { fade = 0.15, looped = true })
				;(rec :: any).sitTrack = if okT and tr then tr else false
			end
			return
		end
	end
	if (rec :: any).sitTrack then
		local tr = (rec :: any).sitTrack
		;(rec :: any).sitTrack = nil
		pcall(function()
			tr:Stop(0.2)
		end)
	end
	local leg = rec.leg
	local pos = rec.basePos
	local moving = false
	local speed = 0
	local walkYaw: number? = nil
	if leg then
		local a = (sNow - leg.t0) / leg.dur
		if a >= 1 then
			pos = leg.to
		elseif a <= 0 then
			pos = leg.from
		elseif leg.poly then
			pos, walkYaw = polyAt(leg, a)
			moving = leg.speed > 0.2
			speed = leg.speed
		else
			pos = leg.from:Lerp(leg.to, a)
			moving = leg.speed > 0.2
			speed = leg.speed
			walkYaw = leg.yaw
		end
	end
	rec.pos = pos
	-- facing: walking direction, else the server's yaw; in a conversation with us: toward us
	local target = walkYaw or rec.attrYaw
	local talkingToMe = rec.localTalk or rec.talkUser == player.UserId
	if talkingToMe and not moving then
		local _, _, myRoot = characterParts()
		if myRoot then
			local d = myRoot.Position - pos
			if Vector3.new(d.X, 0, d.Z).Magnitude > 0.8 then
				target = yawOf(d)
			end
		end
	end
	local diff = angleDiff(rec.yaw, target)
	local maxTurn = TURN_RATE * math.max(dt, 1 / 60)
	if math.abs(diff) <= maxTurn then
		rec.yaw = target
	else
		rec.yaw += math.sign(diff) * maxTurn
	end
	local kn = (rec :: any).knock
	if kn and BumpShared then
		local phase, k = BumpShared.knockPhase(sNow - kn.t0, kn.outcome)
		if phase == "done" then
			(rec :: any).knock = nil
			pcall(function()
				rec.ctl:pose(nil, 0.3)
			end)
		else
			if phase ~= kn.phase then
				kn.phase = phase
				if phase == "getup" and rec.animated then
					pcall(function()
						rec.ctl:pose("stagger", 0.2)
					end)
				end
			end
			local cfk
			if kn.outcome == "knockdown" then
				cfk = BumpShared.fallRootCFrame(pos, rec.yaw, kn.dx, kn.dz, k, rec.ground, rec.ground / 3)
			else
				local off, lean = BumpShared.staggerOffset(kn.dx, kn.dz, k, rec.ground / 3)
				cfk = CFrame.new(pos + Vector3.new(0, rec.ground, 0) + off) * CFrame.Angles(0, rec.yaw, 0) * CFrame.Angles(0, 0, lean)
			end
			rec.root.CFrame = cfk
			rec.lastWrite = nil
			rec.nextUpdate = 0
			return
		end
	end
	local cf = CFrame.new(pos + Vector3.new(0, rec.ground, 0)) * CFrame.Angles(0, rec.yaw, 0)
	local last = rec.lastWrite
	local write = not last or (last.Position - cf.Position).Magnitude > 0.005 or math.abs(angleDiff(yawOf(last.LookVector), rec.yaw)) > 0.002
	if not write and now >= rec.verifyAt then
		-- now and then: did the server's copy of the root replicate over ours?
		rec.verifyAt = now + 0.5
		write = (rec.root.CFrame.Position - cf.Position).Magnitude > 0.01
	end
	if write then
		rec.root.CFrame = cf
		rec.lastWrite = cf
	end
	if moving ~= rec.moving then
		rec.moving = moving
		applyProps(rec)
	end
	-- animation layers
	if rec.animated then
		local ctl = rec.ctl
		ctl:setMoving(if moving then speed else nil)
		local act = rec.act
		if talkingToMe and not moving and rec.street and act ~= "talk" and act ~= "listen" then
			act = "listen"
		end
		ctl:setAct(if act ~= "" then act else "idle")
		local lookAt: Vector3? = nil
		if rec.level >= 2 or rec.localTalk then
			if talkingToMe then
				lookAt = playerHead(player.UserId)
			elseif rec.talkUser ~= 0 then
				lookAt = playerHead(rec.talkUser)
			elseif rec.lookUser ~= 0 and not moving then
				lookAt = playerHead(rec.lookUser)
			end
		end
		ctl:look(lookAt)
	end
end

-------------------------------------------------------------------------------------------------
-- Camera framing
-------------------------------------------------------------------------------------------------
local frame: any = nil

local function camAllowed(): boolean
	if workspace:GetAttribute("GwangalliDialogCam") == false or player:GetAttribute("GwangalliDialogCam") == false then
		return false
	end
	local cam = workspace.CurrentCamera
	if not cam or cam.CameraType ~= Enum.CameraType.Custom then
		return false
	end
	local _, hum = characterParts()
	if not hum or hum.SeatPart ~= nil or hum.Sit then
		return false
	end
	if cam.CameraSubject ~= hum then
		return false
	end
	return true
end

-- Where the dialog sheet sits (read-only look at the overlay): returns the NPC's screen target
-- in normalised device coordinates (x right +, y up +).
local function freeSpot(): (number, number)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local gui = pg and pg:FindFirstChild("GwangalliDialog")
	local panel = gui and gui:FindFirstChild("NpcDialog")
	local cam = workspace.CurrentCamera
	if panel and panel:IsA("GuiObject") and cam then
		local vs = cam.ViewportSize
		local ok, ap, as = pcall(function()
			return panel.AbsolutePosition, panel.AbsoluteSize
		end)
		if ok and vs.X > 0 and vs.Y > 0 and as.X > 0 then
			local cx = (ap.X + as.X / 2) / vs.X
			local cy = (ap.Y + as.Y / 2) / vs.Y
			if as.X / vs.X < 0.62 and cx > 0.55 then
				return -math.clamp(as.X / vs.X, 0.2, 0.5), 0.1 -- sheet on the right: NPC on the left
			elseif as.X / vs.X < 0.62 and cx < 0.45 then
				return math.clamp(as.X / vs.X, 0.2, 0.5), 0.1
			elseif cy > 0.5 then
				return 0.12, math.clamp(as.Y / vs.Y, 0.15, 0.45) -- bottom sheet: NPC higher up
			end
		end
	end
	return 0.15, 0.25
end

local function dialogVisible(): boolean?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local gui = pg and pg:FindFirstChild("GwangalliDialog")
	local panel = gui and gui:FindFirstChild("NpcDialog")
	if panel and panel:IsA("GuiObject") then
		return panel.Visible and (gui :: any).Enabled ~= false
	end
	return nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
pcall(function()
	(rayParams :: any).RespectCanCollide = true -- people (rigs: CanCollide / CanQuery false) never block
end)
local CLIP_EVERY = 0.2 -- the wall check runs at 5 Hz (the shot eases in, so nobody sees the steps)

local function shot(model: Model, f: any): CFrame?
	local cam = workspace.CurrentCamera
	local _, _, myRoot = characterParts()
	local head = headOf(model)
	if not cam or not myRoot or not head then
		return nil
	end
	local me = myRoot.Position
	local d = head - me
	local flatD = Vector3.new(d.X, 0, d.Z)
	if flatD.Magnitude < 0.5 then
		return nil
	end
	local dir = flatD.Unit
	local right = dir:Cross(Vector3.yAxis)
	local dist = flatD.Magnitude
	local back = math.clamp(3.2 + dist * 0.25, 3.6, 6)
	local camPos = me + Vector3.new(0, 2.2, 0) - dir * back + right * 2.1
	local aim = head - Vector3.new(0, 0.3, 0)
	-- keep the lens out of walls (throttled: the clip fraction is reused between checks)
	local toCam = camPos - aim
	local now = os.clock()
	if now >= (f.clipAt or 0) then
		f.clipAt = now + CLIP_EVERY
		local filter: { Instance } = { model }
		if player.Character then
			table.insert(filter, player.Character)
		end
		rayParams.FilterDescendantsInstances = filter
		local ok, hit = pcall(workspace.Raycast, workspace, aim, toCam, rayParams)
		local len = toCam.Magnitude
		f.clip = if ok and hit and len > 0.01 then math.max(0.15, ((hit.Position - aim).Magnitude - 0.6) / len) else 1
	end
	camPos = aim + toCam * (f.clip or 1)
	local cf = CFrame.lookAt(camPos, aim)
	-- where the sheet leaves room: measured once per dialog node, a moment after it appears
	-- (layout reads are not free everywhere; the sheet does not move while a node is shown)
	if talk.spotDirty and now - talk.lastPayload > 0.3 then
		talk.spotDirty = false
		talk.nx, talk.ny = freeSpot()
	end
	local nx, ny = talk.nx or 0.15, talk.ny or 0.25
	local vfov = math.rad(cam.FieldOfView)
	local vs = cam.ViewportSize
	local aspect = if vs.Y > 0 then vs.X / vs.Y else 16 / 9
	local hfovHalf = math.atan(math.tan(vfov / 2) * aspect)
	local yaw = math.atan(nx * math.tan(hfovHalf))
	local pitch = math.atan(-ny * math.tan(vfov / 2))
	return cf * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

-- The model a conversation is with: a key NPC record, else a pedestrian rig of GwangalliStreetLife
-- (direct children of its folder; matched by attribute CitizenId / NpcId or by the display name the
-- dialog carries, the nearest one within 30 studs).
local function findTalkModel(id: string, name: string?): Model?
	local rec = byId[id]
	if rec and rec.model.Parent then
		return rec.model
	end
	local sl = workspace:FindFirstChild("GwangalliStreetLife")
	local _, _, myRoot = characterParts()
	if not sl or not myRoot then
		return nil
	end
	local best: Model? = nil
	local bestD = 30
	for _, m in sl:GetChildren() do
		if m:IsA("Model") and (m:GetAttribute("CitizenId") == id or m:GetAttribute("NpcId") == id or (name ~= nil and m.Name == name)) then
			local h = headOf(m)
			local d = if h then (h - myRoot.Position).Magnitude else math.huge
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best
end

local function endFrame(restore: boolean)
	local f = frame
	if not f or f.restoring then
		return
	end
	local cam = workspace.CurrentCamera
	if not restore or not cam or cam.CameraType ~= Enum.CameraType.Scriptable then
		frame = nil
		return
	end
	f.restoring = true
	f.restoreT0 = os.clock()
	f.restoreFrom = cam.CFrame
end

local function startFrame(id: string, model: Model)
	if frame then
		if frame.id == id and not frame.restoring then
			frame.model = model
			return
		end
		if frame.restoring then
			local cam = workspace.CurrentCamera
			if cam and cam.CameraType == Enum.CameraType.Scriptable then
				cam.CameraType = frame.prevType
			end
			frame = nil
		else
			frame.id = id
			frame.model = model
			return
		end
	end
	if not camAllowed() then
		return
	end
	local cam = workspace.CurrentCamera
	local _, _, myRoot = characterParts()
	if not cam or not myRoot then
		return
	end
	local h = headOf(model)
	if not h or (h - myRoot.Position).Magnitude > 30 then
		return
	end
	frame = {
		id = id,
		model = model,
		t0 = os.clock(),
		startCF = cam.CFrame,
		prevType = cam.CameraType,
		origin = myRoot.Position,
		restoring = false,
	}
	cam.CameraType = Enum.CameraType.Scriptable
end

local function stepFrame(dt: number)
	local f = frame
	if not f then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		frame = nil
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		frame = nil -- someone else took the camera: leave it alone
		return
	end
	local now = os.clock()
	if f.restoring then
		local u = math.clamp((now - f.restoreT0) / 0.35, 0, 1)
		local e = 1 - (1 - u) * (1 - u)
		cam.CFrame = f.restoreFrom:Lerp(f.startCF, e)
		if u >= 1 then
			cam.CameraType = f.prevType
			frame = nil
		end
		return
	end
	local _, hum, myRoot = characterParts()
	local vis = dialogVisible()
	local over = not myRoot
		or not hum
		or hum.SeatPart ~= nil
		or (myRoot.Position - f.origin).Magnitude > 7
		or now - f.t0 > 150
		or talk.id ~= f.id
		or (vis == false and now - talk.lastPayload > 0.6)
		or (vis == nil and now - talk.lastPayload > 40)
		or not f.model.Parent
	if over then
		endFrame(myRoot ~= nil)
		return
	end
	local target = shot(f.model, f)
	if target then
		local k = 1 - math.exp(-dt * 5)
		cam.CFrame = cam.CFrame:Lerp(target, k)
	end
end

-------------------------------------------------------------------------------------------------
-- Local character reactions
-------------------------------------------------------------------------------------------------
local turn: any = nil -- { root, from, to, t0 }

local function faceNpc(model: Model)
	local _, hum, myRoot = characterParts()
	local h = headOf(model)
	if not hum or not myRoot or not h or hum.SeatPart then
		return
	end
	if hum.MoveDirection.Magnitude > 0.1 or hum.FloorMaterial == Enum.Material.Air then
		return
	end
	local d = h - myRoot.Position
	if Vector3.new(d.X, 0, d.Z).Magnitude < 1 then
		return
	end
	turn = { root = myRoot, hum = hum, fromYaw = yawOf(myRoot.CFrame.LookVector), toYaw = yawOf(d), t0 = os.clock() }
end

local function stepTurn()
	local t = turn
	if not t then
		return
	end
	if not t.root.Parent or t.hum.MoveDirection.Magnitude > 0.1 then
		turn = nil
		return
	end
	local u = math.clamp((os.clock() - t.t0) / 0.3, 0, 1)
	local yaw = t.fromYaw + angleDiff(t.fromYaw, t.toYaw) * (1 - (1 - u) * (1 - u))
	local p = t.root.Position
	t.root.CFrame = CFrame.new(p) * CFrame.Angles(0, yaw, 0)
	if u >= 1 then
		turn = nil
	end
end

local reactT = 0
local function react(name: string)
	local _, hum = characterParts()
	if not hum or hum.SeatPart or hum.MoveDirection.Magnitude > 0.1 then
		return
	end
	local now = os.clock()
	if now - reactT < 2.5 then
		return
	end
	reactT = now
	local track = Anim.play(hum, name, { fade = 0.15, looped = false })
	if track then
		local dur = if string.sub(name, 1, 5) == "dance" then 3.5 else 2.2
		task.delay(dur, function()
			if track.IsPlaying then
				pcall(track.Stop, track, 0.3)
			end
		end)
	end
end

local HINT = { greet = "wave", think = "think", refuse = "shake", dance = "dance1", cheer = "cheer", shy = "shy", laugh = "laugh", nod = "nod" }
local MIRROR = { cheer = "cheer", dance = "dance1", laugh = "laugh" }

local function setLocalTalk(id: string?)
	for _, rec in recs do
		local on = rec.id == id
		if rec.localTalk ~= on then
			rec.localTalk = on
			rec.nextUpdate = 0
		end
	end
end

local function onDialog(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local now = os.clock()
	if payload.close == true then
		talk.id = nil
		setLocalTalk(nil)
		if frame then
			endFrame(true)
		end
		return
	end
	local id = payload.npcId
	if type(id) ~= "string" then
		return
	end
	local fresh = talk.id ~= id or now - talk.lastPayload > 60
	talk.id = id
	talk.remote = payload.remote == true
	talk.lastPayload = now
	if talk.remote then
		setLocalTalk(nil)
		return
	end
	if fresh then
		talk.openedAt = now
	end
	talk.spotDirty = true
	setLocalTalk(id)
	local model = if fresh or not frame or frame.id ~= id then findTalkModel(id, if type(payload.name) == "string" then payload.name else nil) else frame.model
	local rec = byId[id]
	-- emote hints: server NPCs of G.NPCS emote through NpcEmote already; street ones react here
	local hint = payload.emote
	if type(hint) == "string" and rec and rec.street and HINT[hint] then
		playEmote(rec, HINT[hint])
	end
	if model then
		if fresh then
			faceNpc(model)
			local last = talk.greeted[id]
			if not last or now - last > 45 then
				talk.greeted[id] = now
				task.delay(0.35, react, "wave")
			end
		end
		startFrame(id, model)
	end
	if type(hint) == "string" and MIRROR[hint] then
		task.delay(0.4, react, MIRROR[hint])
	end
end

local function onSocialLine(msg: any)
	if type(msg) ~= "table" or msg.kind ~= "line" or type(msg.id) ~= "string" then
		return
	end
	local rec = byId[msg.id]
	if rec and type(msg.emote) == "string" and HINT[msg.emote] then
		playEmote(rec, HINT[msg.emote])
		local _, _, myRoot = characterParts()
		if myRoot and (myRoot.Position - rec.pos).Magnitude < 16 then
			rec.localTalk = true
			task.delay(4, function()
				if talk.id ~= rec.id then
					rec.localTalk = false
				end
			end)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Hand-overs: a gift / drink changes hands, phones out for a number swap (local animation + prop)
-------------------------------------------------------------------------------------------------
local beats: { any } = {}
local mine: any = nil -- { ctl, untilT }: the one-shot on the local character

local function fxPart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function hand(model: Instance?, name: string): BasePart?
	if not model then
		return nil
	end
	local h = model:FindFirstChild(name) or model:FindFirstChild(if name == "RightHand" then "Right Arm" else "Left Arm")
	return if h and h:IsA("BasePart") then h else nil
end

local function endMine()
	local m = mine
	mine = nil
	if m then
		pcall(function()
			m.ctl:relax()
			m.ctl:destroy()
		end)
	end
end

-- A procedural one-shot on the local character (C0 offsets on top of the Animate tracks; the
-- controller is made for the beat and dropped after it, so avatar scaling never goes stale).
local function playMine(name: string): boolean
	local char, hum = characterParts()
	if not char or not hum or hum.SeatPart or hum.Sit then
		return false
	end
	endMine()
	local ok, ctl = pcall(Anim.rig, char)
	if not ok or not ctl then
		return false
	end
	local dur = ctl:emote(name)
	if dur <= 0 then
		pcall(function()
			ctl:destroy()
		end)
		return false
	end
	mine = { ctl = ctl, untilT = os.clock() + dur + 0.1 }
	return true
end

local function nearModel(id: string): (Model?, Rec?)
	local model = findTalkModel(id, nil)
	local _, _, myRoot = characterParts()
	local h = headOf(model)
	if not model or not myRoot or not h or (h - myRoot.Position).Magnitude > 14 then
		return nil, nil
	end
	local rec = byId[id]
	return model, if rec and rec.model == model then rec else nil
end

-- Where the gift goes: between a key NPC's hands (they reach for it), else in front of the chest.
local function receivePoint(model: Model, rec: Rec?): Vector3?
	if rec then
		local r, l = hand(model, "RightHand"), hand(model, "LeftHand")
		if r and l then
			return (r.Position + l.Position) / 2 + Vector3.new(0, 0.15, 0)
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if root and root:IsA("BasePart") then
		return (root.CFrame * CFrame.new(0, 0.5, -1.1)).Position
	end
	return nil
end

local function handover(id: string, kind: string)
	local model, rec = nearModel(id)
	local char = player.Character
	if not model or not char then
		return
	end
	faceNpc(model)
	if not playMine("give") then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local parts: { Part } = {}
	if kind == "cup" then
		local cup = fxPart("HandoverCup", Vector3.new(0.34, 0.5, 0.34), Color3.fromRGB(245, 240, 232), cam)
		local drink = fxPart("HandoverDrink", Vector3.new(0.3, 0.12, 0.3), Color3.fromRGB(230, 70, 120), cam)
		table.insert(parts, cup)
		table.insert(parts, drink)
	else
		local box = fxPart("HandoverGift", Vector3.new(0.62, 0.5, 0.62), Color3.fromRGB(226, 52, 78), cam)
		local ribbon = fxPart("HandoverRibbon", Vector3.new(0.66, 0.54, 0.16), Color3.fromRGB(255, 214, 90), cam)
		table.insert(parts, box)
		table.insert(parts, ribbon)
	end
	if rec then
		task.delay(0.3, function()
			if rec.model.Parent and rec.animated then
				rec.ctl:emote("receive")
			end
		end)
	end
	table.insert(beats, { kind = kind, t0 = os.clock(), dur = 2.2, parts = parts, model = model, rec = rec })
end

local function numberSwap(id: string)
	local model, rec = nearModel(id)
	if not model then
		return
	end
	faceNpc(model)
	if not playMine("phone_show") then
		return
	end
	local cam = workspace.CurrentCamera
	local parts: { Part } = {}
	if cam then
		table.insert(parts, fxPart("SwapPhone", Vector3.new(0.34, 0.62, 0.08), Color3.fromRGB(18, 18, 22), cam))
		table.insert(parts, fxPart("SwapScreen", Vector3.new(0.28, 0.5, 0.02), Color3.fromRGB(120, 200, 255), cam))
		parts[2].Material = Enum.Material.Neon
	end
	if rec then
		rec.forceProp = "phone"
		rec.forcePropUntil = os.clock() + 2.4
		applyProps(rec)
		if rec.animated then
			rec.ctl:emote("phone_show")
		end
		task.delay(2.5, function()
			if rec.model.Parent then
				applyProps(rec)
			end
		end)
	end
	table.insert(beats, { kind = "phone", t0 = os.clock(), dur = 2.4, parts = parts, model = model, rec = rec })
end

local function stepBeats(now: number)
	local m = mine
	if m then
		if now >= m.untilT or not m.ctl.model.Parent then
			endMine()
		else
			m.ctl:step()
		end
	end
	if #beats == 0 then
		return
	end
	local char = player.Character
	local myHand = hand(char, "RightHand")
	for i = #beats, 1, -1 do
		local b = beats[i]
		local t = now - b.t0
		if t >= b.dur or not b.model.Parent then
			for _, p in b.parts do
				p:Destroy()
			end
			table.remove(beats, i)
		elseif #b.parts > 0 then
			local cf: CFrame? = nil
			if b.kind == "phone" then
				if myHand then
					cf = myHand.CFrame * CFrame.new(0, -0.15, -0.42)
				end
			else
				local from = if myHand then (myHand.CFrame * CFrame.new(0, -0.35, -0.2)).Position else nil
				local to = receivePoint(b.model, b.rec)
				local pos: Vector3? = nil
				if from and (t < 0.55 or not to) then
					pos = from
				elseif from and to and t < 1.05 then
					local u = (t - 0.55) / 0.5
					u = u * u * (3 - 2 * u)
					pos = from:Lerp(to, u) + Vector3.new(0, 0.35 * math.sin(u * math.pi), 0)
				else
					pos = to
				end
				if pos then
					local root = b.model:FindFirstChild("HumanoidRootPart")
					local yaw = if root and root:IsA("BasePart") then CFrame.Angles(0, yawOf(root.CFrame.LookVector), 0) else CFrame.identity
					cf = CFrame.new(pos) * yaw
				end
			end
			local fade = math.clamp((t - (b.dur - 0.3)) / 0.3, 0, 1)
			for k, p in b.parts do
				if cf then
					if b.kind == "phone" and k == 2 then
						p.CFrame = cf * CFrame.new(0, 0.02, -0.05)
					elseif b.kind == "cup" and k == 2 then
						p.CFrame = cf * CFrame.new(0, 0.2, 0)
					else
						p.CFrame = cf
					end
				end
				p.Transparency = fade
			end
		end
	end
end

-- a gift / drink bought for someone, a number given: the hand-over moment
local GIVE_SOURCES = { gift = "gift", giftbad = "gift", bday = "gift", drink = "cup" }
local function onSocial(msg: any)
	if type(msg) ~= "table" or type(msg.id) ~= "string" then
		return
	end
	if msg.kind == "line" then
		onSocialLine(msg)
	elseif msg.kind == "affinity" and GIVE_SOURCES[msg.source] then
		handover(msg.id, GIVE_SOURCES[msg.source])
	elseif msg.kind == "contact" and msg.added == true then
		numberSwap(msg.id)
	end
end

-------------------------------------------------------------------------------------------------
-- Frame loop
-------------------------------------------------------------------------------------------------
local function focusPos(): Vector3?
	local _, _, myRoot = characterParts()
	if myRoot then
		return myRoot.Position
	end
	local cam = workspace.CurrentCamera
	return cam and cam.Focus.Position or nil
end

local function step(dt: number)
	local now = os.clock()
	local sNow = serverNow()
	local focus = focusPos()
	-- the sheet can close on its own (walked away, phone opened): the conversation is over
	if talk.id and not frame and now - talk.lastPayload > 1 then
		local vis = dialogVisible()
		if vis == false or (vis == nil and now - talk.lastPayload > 40) then
			talk.id = nil
			setLocalTalk(nil)
		end
	end
	for _, rec in recs do
		if rec.root.Parent then
			local d = if focus then (rec.pos - focus).Magnitude else 0
			rec.dist = d
			-- walking right now? (walkers glide every frame out to `far`)
			local leg = rec.leg
			local walking = leg ~= nil and sNow > leg.t0 and sNow < leg.t0 + leg.dur and leg.speed > 0.2
			local level = if d <= lod.near or rec.localTalk then 2 elseif d <= lod.anim then 1 elseif d <= lod.far then 0 else -1
			if rec.seatOff and level < 1 then
				level = 1 -- a seated rig keeps its sitting pose at any distance (never through the roof)
			end
			local wantAnim = level >= 1 or (level == 0 and walking)
			if level ~= rec.level then
				rec.level = level
				if level >= 0 then
					rec.ctl:setDetail(level)
				end
				rec.nextUpdate = 0
			end
			if wantAnim ~= rec.animated then
				rec.animated = wantAnim
				rec.ctl:setAnimated(wantAnim)
				rec.nextUpdate = 0
			end
			local due = false
			if (rec :: any).knock or rec.seatOff then
				due = true
			elseif level == 2 or (level >= 0 and (walking or rec.moving)) then
				due = true
			elseif now >= rec.nextUpdate then
				if level == 1 then
					due = true
					rec.nextUpdate = now + 1 / MID_HZ
				elseif level == 0 then
					due = true
					rec.nextUpdate = now + 1 / lod.farHz
				else
					due = true -- beyond `far`: only keeps its place current (someone walking in from afar)
					rec.nextUpdate = now + 0.5
				end
			end
			if due then
				local ok, err = pcall(update, rec, now, sNow)
				if not ok then
					warn("[GwangalliNPCClient] " .. rec.id .. ": " .. tostring(err))
					rec.nextUpdate = now + 2
				end
			end
			-- procedural layers: every frame close by, 15 Hz within `near`, 10 Hz pose + emotes to `anim`
			if rec.animated then
				if level == 2 and (d <= CLOSE or rec.localTalk) then
					rec.ctl:step()
				elseif level >= 1 and now >= rec.nextStep then
					rec.nextStep = now + (if level == 2 then 1 / NEAR_HZ else 1 / MID_HZ)
					rec.ctl:step()
				end
			end
		end
	end
	stepBeats(now)
	stepTurn()
	stepFrame(dt)
end

RunService:BindToRenderStep("GwangalliNPCClient", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	local ok, err = pcall(step, dt)
	if not ok then
		warn("[GwangalliNPCClient] step: " .. tostring(err))
	end
end)

-- if this script stops (character reset keeps it: StarterPlayerScripts), never leave the camera stuck
player.CharacterRemoving:Connect(function()
	mine = nil
	if frame then
		local cam = workspace.CurrentCamera
		if cam and cam.CameraType == Enum.CameraType.Scriptable then
			cam.CameraType = frame.prevType or Enum.CameraType.Custom
		end
		frame = nil
	end
	turn = nil
end)

-------------------------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------------------------
task.spawn(function()
	local f = workspace:WaitForChild("GwangalliNPCs", 120)
	while not f do
		f = workspace:WaitForChild("GwangalliNPCs", 120)
	end
	f.ChildAdded:Connect(function(ch)
		-- attributes are set before the server parents a model; wait a frame for streamed parts
		task.defer(addModel, ch)
	end)
	-- non-atomic streaming: the model can arrive before its root; register it when the root does
	f.DescendantAdded:Connect(function(d)
		if d.Name == "HumanoidRootPart" and d:IsA("BasePart") then
			local m = d.Parent
			if m and m.Parent == f and not recs[m :: any] then
				task.defer(addModel, m)
			end
		end
	end)
	f.ChildRemoved:Connect(function(ch)
		if ch:IsA("Model") then
			removeRec(ch)
		end
	end)
	for _, ch in f:GetChildren() do
		addModel(ch)
	end
end)

task.spawn(function()
	local rf = ReplicatedStorage:WaitForChild("GwangalliRemotes", 60)
	local d = rf and rf:WaitForChild("Dialog", 60)
	if d and d:IsA("RemoteEvent") then
		d.OnClientEvent:Connect(function(payload)
			local ok, err = pcall(onDialog, payload)
			if not ok then
				warn("[GwangalliNPCClient] dialog: " .. tostring(err))
			end
		end)
	end
end)

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("GwangalliSocial", 60)
	local st = folder and folder:WaitForChild("SocialState", 60)
	if st and st:IsA("RemoteEvent") then
		st.OnClientEvent:Connect(function(msg)
			local ok, err = pcall(onSocial, msg)
			if not ok then
				warn("[GwangalliNPCClient] social: " .. tostring(err))
			end
		end)
	end
end)
