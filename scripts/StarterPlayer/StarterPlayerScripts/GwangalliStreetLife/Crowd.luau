-- GwangalliStreetLife/Crowd: the pedestrian manager (client-side; every client simulates its own
-- surroundings).
--   * SPAWNER (TickHz): keeps `cap` pedestrians around the player - GwangalliQuality low 12 / mid 18 /
--     high 25 (saver 6), shrinking away from the club at night (GwangalliNight.streetCap: cap * (1 -
--     0.3 * hype), blended by the distance to the club door) and 0 outside while the player is inside
--     CLUB OCEAN (the street is behind the walls; the club crowd is ClubCrowd's). Named citizens come
--     first (GwangalliCitizens.candidates), anonymous passers-by fill up. Spawns go where a GTA crowd
--     appears: ahead of the player's direction of travel, off-screen or at least SpawnViewMin studs
--     away when on screen, never on top of somebody else. Activity people START at their spot (a
--     bench, a towel, a photo spot, a shop window, a bus stop) instead of walking there, and when too
--     many of the people around are walking the next one is an activity person; by day a few people
--     always lie on the towels when there is sand nearby. Some people walk out of the metro / a shop.
--     People behind the player go first; nobody disappears on screen (on-screen agents fade out or
--     walk away).
--   * NIGHT FLOW: club-goers follow Nav.ped.toClub to CLUB OCEAN, line up in the queue (Nav.club.queue
--     after the club's own static queue rigs while those are shown), shuffle forward and go in
--     through the door one by one; smokers stand at the hang-out ring.
--   * EVENTS: the drone show (GwangalliDroneShowStart) turns the beach crowd toward the bay; a ring of
--     listeners gathers at the busker (key NPC "busker", NpcAct guitar) and claps between songs; a
--     customer or two buys at the 붕어빵 cart (key NPC "bungeoppang"); people nearby film the player
--     dancing.
--   * REACTIONS that need the whole crowd: fast cars (the player's own - Humanoid.SeatPart - or any
--     driven GwangalliDrivable car) make the people in their path jump aside; a horn turns heads; the
--     player walking into somebody (per-frame contact check); pedestrians keep apart (separation).
--   * COMPANIONS: a player's GwangalliCompanion attribute (Relationships "hangout") makes that
--     citizen follow the player (every client draws every nearby companion); a key-NPC companion's
--     server model is hidden locally meanwhile. In a car the friend rides along (Agent.stepFollow).
--   * UPDATE (Heartbeat): close agents move every frame, farther ones at MidHz / FarHz, off-screen ones
--     at OffHz; all root CFrames go out in one workspace:BulkMoveTo. Animation tracks stop only for
--     agents that are off-screen and away from the player (re-checked every frame).
--   * DEBUG: Workspace attribute GwangalliStreetLifeDebug = true prints counts / cost every DebugEvery s.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Crowd = {}

local ctx: any
local W: any
local Agent: any
local Pool: any
local Anim: any
local Config: any
local Citizens: any
local Night: any
local Looks: any
local Quality: any
local SocialUI: any
local player: Player

local agents: { any } = {}
local byId: { [string]: any } = {}
local companions: { [Player]: any } = {}
local hiddenKey: { [string]: { BasePart } } = {}
local recent: { [string]: number } = {} -- id -> time it left (cooldown before it can come back)
local extraFree: { string } = {}
local spawnSn = 0 -- spawn serial: a reused anonymous id ("x12") is a new person (GwangalliFight "sn")
local rng = Random.new()
local function rnd(): number
	return rng:NextNumber()
end

Crowd.agents = agents
Crowd.byId = byId

local function tierVal(t: any): any
	if Quality then
		if t.saver ~= nil and Quality.isSaver and Quality.isSaver() then
			return t.saver
		end
		return t[Quality.get()] or t.low
	end
	return t.low
end
Crowd.tierVal = tierVal

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function segDist(p: Vector3, a: Vector3, b: Vector3): number
	local abx, abz = b.X - a.X, b.Z - a.Z
	local len2 = abx * abx + abz * abz
	local t = 0
	if len2 > 1e-6 then
		t = math.clamp(((p.X - a.X) * abx + (p.Z - a.Z) * abz) / len2, 0, 1)
	end
	local cx, cz = a.X + abx * t, a.Z + abz * t
	return math.sqrt((p.X - cx) ^ 2 + (p.Z - cz) ^ 2)
end

local function yawOf(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

-------------------------------------------------------------------------------------------------
-- player state
-------------------------------------------------------------------------------------------------
local Delivery: any = nil -- GwangalliStreetLife/Delivery (배달 라이더 + rob state of street people)
local P = { pos = nil :: Vector3?, vel = Vector3.zero, speed = 0, lastPos = nil :: Vector3?, lastT = 0, seat = nil :: BasePart?, look = Vector3.new(0, 0, -1), drive = false, manual = nil :: BasePart?, manualW = nil :: Instance?, manualNext = 0, body = nil :: BasePart? }
-- the car this player drives (its DriveDriver is our UserId: watchCar), for a manual seating
local ownCar: Model? = nil

-- a manual seating (base Cars.manualSit when Seat:Sit is refused - the phone emulator: a "SeatWeld"
-- from the seat to the root, Humanoid.Sit, no SeatPart), else the driver's seat of our own car while
-- the root is at it. Kept while the weld holds; looked for again at most every 0.5 s (no per-frame work)
local function manualSeat(root: BasePart, hum: Humanoid, now: number): BasePart?
	local s, w = P.manual, P.manualW
	if s and s.Parent then
		if w then
			if w.Parent == s and (w :: any).Part1 == root then
				return s
			end
		elseif now < P.manualNext then
			return s -- (our own car's seat by its driver attribute: checked again every 0.5 s)
		end
	end
	P.manual, P.manualW = nil, nil
	if now < P.manualNext then
		return nil
	end
	P.manualNext = now + 0.5
	if hum.Sit then
		local okJ, j = pcall(function()
			for _, x in root:GetJoints() do
				if x.Name == "SeatWeld" and x:IsA("Weld") and x.Part1 == root and x.Part0 and (x.Part0:IsA("Seat") or x.Part0:IsA("VehicleSeat")) then
					return x
				end
			end
			return nil
		end)
		if okJ and j then
			P.manual, P.manualW = (j :: Weld).Part0, j
			return P.manual
		end
	end
	local car = ownCar
	local ds = car and car.Parent and car:FindFirstChild("DriveSeat", true)
	if ds and ds:IsA("BasePart") and (ds.Position - root.Position).Magnitude < 8 then
		local w2 = ds:FindFirstChild("SeatWeld")
		P.manual, P.manualW = ds, if w2 and (w2 :: any).Part1 == root then w2 else nil
		return ds
	end
	return nil
end

local function samplePlayer(now: number)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local p: Vector3? = nil
	if root and root:IsA("BasePart") then
		local hum = ch:FindFirstChildOfClass("Humanoid")
		local off = 3
		if hum then
			if hum.RigType == Enum.HumanoidRigType.R15 then
				off = hum.HipHeight + root.Size.Y / 2
			end
			P.seat = hum.SeatPart or Crowd.debugSeat
			if not P.seat then
				P.seat = manualSeat(root, hum, now)
			end
		else
			P.seat = Crowd.debugSeat
		end
		if not P.seat and player:GetAttribute("InTaxi") == true then
			-- riding a GwangalliTaxi (welded in, no Seat): the taxi counts as the player's car
			local f = workspace:FindFirstChild("GwangalliTaxis")
			local m = f and f:FindFirstChild("GwangalliTaxi_" .. tostring(player.UserId))
			P.seat = m and (m :: Model).PrimaryPart or nil
		end
		p = root.Position - Vector3.new(0, off, 0)
		local lv = root.CFrame.LookVector
		local m = math.sqrt(lv.X * lv.X + lv.Z * lv.Z)
		if m > 0.1 then
			P.look = Vector3.new(lv.X / m, 0, lv.Z / m)
		end
	else
		P.seat = nil
		local cam = workspace.CurrentCamera
		if cam then
			p = cam.Focus.Position
		end
	end
	if p then
		if P.lastPos and now > P.lastT then
			local dt = now - P.lastT
			if dt > 0.02 then
				local v = (p - P.lastPos) / dt
				if v.Magnitude > 200 then
					v = Vector3.zero -- teleport
				end
				P.vel = P.vel:Lerp(v, math.min(1, dt * 8))
				P.speed = Vector3.new(P.vel.X, 0, P.vel.Z).Magnitude
				P.lastPos = p
				P.lastT = now
			end
		else
			P.lastPos = p
			P.lastT = now
		end
		P.pos = p
	end
end

function Crowd.playerPos(): Vector3?
	return P.pos
end

function Crowd.playerVel(): Vector3
	return P.vel
end

function Crowd.playerLook(): Vector3
	return P.look
end

-- the local player sits in something (a car, a taxi ...)
function Crowd.playerSeated(): boolean
	return P.seat ~= nil
end

-- the seat a player sits on (Crowd.debugSeat: test drivers stand in for Humanoid.SeatPart, which
-- the simulator cannot set)
function Crowd.seatOf(plr: Player): BasePart?
	local ch = plr.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local s = hum and hum.SeatPart
	if not s and plr == player then
		s = Crowd.debugSeat or (if P.manual and P.manual.Parent then P.manual else nil)
		if not s and P.seat and ownCar and P.seat:IsDescendantOf(ownCar) then
			s = P.seat -- (our own car by its driver attribute)
		end
	end
	return s
end

function Crowd.playerSpeed(plr: Player?): number
	if plr == nil or plr == player then
		return P.speed
	end
	local ch = plr.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local ok, v = pcall(function()
			return root.AssemblyLinearVelocity
		end)
		if ok and v then
			return Vector3.new(v.X, 0, v.Z).Magnitude
		end
	end
	return 0
end

-- inside CLUB OCEAN (ClubZone boxes other than "Near")
local zones: { BasePart } = {}
local zonesAt = -1e9
function Crowd.inClub(p: Vector3): boolean
	if Night.clubDistance(p) > 320 then
		return false
	end
	local now = os.clock()
	if now - zonesAt > 10 then
		zonesAt = now
		table.clear(zones)
		for _, z in CollectionService:GetTagged("ClubZone") do
			if z:IsA("BasePart") and z:GetAttribute("Zone") ~= "Near" then
				table.insert(zones, z)
			end
		end
	end
	for _, z in zones do
		if z.Parent then
			local lp = z.CFrame:PointToObjectSpace(p + Vector3.new(0, 2, 0))
			local h = z.Size * 0.5
			if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y + 2 and math.abs(lp.Z) <= h.Z then
				return true
			end
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- crowd-wide limits: glances, reaction lines, the club pitch
-------------------------------------------------------------------------------------------------
local glanceEnds: { number } = {}
function Crowd.takeGlance(now: number): boolean
	local n = 0
	for i = #glanceEnds, 1, -1 do
		if glanceEnds[i] <= now then
			table.remove(glanceEnds, i)
		else
			n += 1
		end
	end
	if n >= Config.GlanceMax then
		return false
	end
	table.insert(glanceEnds, now + 2)
	return true
end

local lastSay = -1e9
function Crowd.canSay(now: number): boolean
	if now - lastSay < 2.5 then
		return false
	end
	lastSay = now
	return true
end

local lure = { last = -1e9, snubUntil = -1e9, ids = {} :: { [string]: number }, open = nil :: any, openAt = 0 }
function Crowd.canLure(a: any, now: number): boolean
	if now < lure.snubUntil or now - lure.last < Config.LureCooldown then
		return false
	end
	local t = lure.ids[a.id]
	if t and now - t < Config.LureSameId then
		return false
	end
	-- named people who love the club and people the player knows pitch first
	if not a.named then
		return now - lure.last > 90
	end
	local c = a.c
	if (c and c.club or 0) < 0.5 and SocialUI.tier(a.id) < 2 then
		return now - lure.last > 70
	end
	return true
end

function Crowd.noteLure(a: any, now: number)
	lure.last = now
	lure.ids[a.id] = now
	lure.open = a
	lure.openAt = now
end

-- somebody may walk up to talk (chatty / 걸렁뱅이): one at a time, a global gap, never while the
-- player is seated, talking already, or another approach is on
local lastChat = -1e9
local chatting: any = nil
local debugOnly: any = nil -- test harness (api "debug"): only the retyped agent may walk up

-- the NPC dialog card (GwangalliPhone/Overlay: PlayerGui.GwangalliDialog.NpcDialog) is open: nobody
-- walks up, bumps or shoves the player meanwhile. The panel is looked up again at most every 2 s.
local dialogPanel: GuiObject? = nil
local dialogLookAt = -1e9
function Crowd.playerInDialog(): boolean
	local p = dialogPanel
	if not p or not p.Parent then
		dialogPanel = nil
		local now = os.clock()
		if now - dialogLookAt < 2 then
			return false
		end
		dialogLookAt = now
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local g = pg and pg:FindFirstChild("GwangalliDialog")
		local found = g and g:FindFirstChild("NpcDialog", true)
		if not found or not found:IsA("GuiObject") then
			return false
		end
		dialogPanel = found
		p = found
	end
	local g = (p :: GuiObject):FindFirstAncestorOfClass("ScreenGui")
	return (p :: GuiObject).Visible and (g == nil or g.Enabled)
end

function Crowd.canChat(now: number, a: any?): boolean
	if debugOnly and a ~= nil and a ~= debugOnly then
		return false
	end
	if chatting and not chatting.gone and chatting.chatState then
		return false
	end
	chatting = nil
	if now - lastChat < ((ctx.BumpShared and ctx.BumpShared.CHAT_GLOBAL_GAP) or 40) then
		return false
	end
	if SocialUI.talkingNow and SocialUI.talkingNow() then
		return false
	end
	if ctx.Mind and ctx.Mind.busy() then
		return false -- npc_mind: in a bubble conversation already
	end
	if P.seat ~= nil then
		return false
	end
	-- never while the player works a shift, trains at the gym, rides a taxi or is inside the club
	if player:GetAttribute("OnShift") or player:GetAttribute("GymBusy") or player:GetAttribute("InTaxi") then
		return false
	end
	local cc = ctx.ClubCrowd and ctx.ClubCrowd.stats
	if cc and cc.atClub then
		return false
	end
	local ch = player.Character
	if ch and ch:GetAttribute("GwangalliKnocked") then
		return false
	end
	if Crowd.playerInDialog() then
		return false
	end
	return true
end
function Crowd.noteChat(a: any, now: number)
	lastChat = now
	chatting = a
end

-- a passer-by turned drunk for a 생활콘텐츠 incident (취객 시비 / 포장마차 싸움): the sway and the slow
-- drunk walk too, the same as a drunk spawned as one (Agent.new)
function Crowd.makeDrunk(a: any)
	if a.gone then
		return
	end
	a.type = "drunk"
	a.wobble = nil
	a.walkPose = "sway"
	a.walkSpeed = (a.baseWalkSpeed or a.walkSpeed) * ((ctx.BumpShared and ctx.BumpShared.DRUNK and ctx.BumpShared.DRUNK.speed) or 0.62)
end

-- LocalPlayer.GwangalliStreetAPI (BindableFunction, published by the boot script): other client
-- scripts (GwangalliBump) reach the pedestrians through it.
function Crowd.api(method: any, ...: any): any
	if method == "near" then
		local r = tonumber((...)) or 8
		local pp = P.pos
		local out = {}
		if not pp then
			return out
		end
		for _, a in agents do
			if not a.gone and not a.clubGuest and a.rig.model.Parent then
				local dx, dz = a.pos.X - pp.X, a.pos.Z - pp.Z
				if dx * dx + dz * dz <= r * r then
					-- down: already falling, or sitting / lying / napping (nobody shoulder-bumps a person on a bench or a towel)
					local down = a.knock ~= nil or a.sitting == true or a.lying == true or a.sitGround == true or a.napping == true
					-- x / y / z too: an Instance inside a returned table does not survive every Bindable bridge
					table.insert(out, { id = a.id, name = (a.c and a.c.name) or a.id, typeId = a.type, root = a.rig.root, down = down, named = a.named, x = a.pos.X, y = a.pos.Y + (a.rig.ground or 3), z = a.pos.Z, sn = a.sn })
				end
			end
		end
		return out
	elseif method == "knock" then
		-- a hit that landed: "stagger" | "knockdown" | "thrown", also mid-fall (a combo: Crowd.fightKnock)
		local id, dx, dz, outcome, puk = ...
		local a = byId[id]
		if not a or a.gone then
			return false
		end
		local ok = Crowd.fightKnock(a, tonumber(dx) or 0, tonumber(dz) or -1, if outcome == "knockdown" or outcome == "thrown" then outcome else "stagger", puk)
		local pp = P.pos
		if ok and a.knock and pp and (a.pos - pp).Magnitude < 12 and os.clock() - (a.giFoolBump or -1e9) > 0.5 then
			-- the player's 어깨빵 / punch (not a car, an NPC fight: those call knockDown directly; not 만복이
			-- running through people, GwangalliInteractClient/Peds): back on their feet, who they are
			-- decides what they do (Characters.bumped, when no punch reaction is pending)
			a.knock.byPlayer = true
		end
		return ok
	elseif method == "say" then
		local id, text, _typeId, dur = ...
		local a = byId[id]
		if not a or a.gone or type(text) ~= "string" then
			return false
		end
		a.lastSayAt = os.clock() -- (the server's line after a car hit: the get-up line stays quiet)
		SocialUI.say(a, text, tonumber(dur) or 3.5)
		return true
	elseif method == "leave" then
		local a = byId[(...)]
		if not a or a.gone then
			return false
		end
		local now = os.clock()
		if a.chatState then
			a:endChat(now, false)
		end
		if a.mode == "talk" then
			a:endTalk(now)
		end
		a:setPlan({ kind = "leave", act = "walk" }, now)
		return true
	elseif method == "ko" then
		-- 길거리 싸움: they went down and stay down (GwangalliFight); then they are taken away
		local id, dx, dz, secs = ...
		local a = byId[id]
		if not a or a.gone then
			return false
		end
		local now = os.clock()
		a.brawl, a.pendingReact, a.quarrel = nil, nil, nil
		if a.chase then
			a.chase = nil
		end
		if a.knock and (a.knock.outcome ~= "knockdown" or a.knock.phase == "getup") then
			-- staggering from the last punch / getting up: this one puts them (back) on the ground
			Crowd.fightKnock(a, tonumber(dx) or 0, tonumber(dz) or -1, "knockdown", "퍽!!")
		end
		if not a.knock then
			a:knockDown(tonumber(dx) or 0, tonumber(dz) or -1, "knockdown", "퍽!!")
		end
		a.ko = { untilT = now + (tonumber(secs) or 25), t0 = now }
		a.lying = true -- a body on the ground: no 말 걸기 / 인사하기 prompt (SocialUI), no emotes
		-- at most 6 people down at once: the one down longest is taken away first (performance)
		local down = {}
		for _, o in agents do
			if o.ko and not o.gone and not o.fadeAt then
				table.insert(down, o)
			end
		end
		if #down > 6 then
			table.sort(down, function(x, y)
				return x.ko.t0 < y.ko.t0
			end)
			for i = 1, #down - 6 do
				Crowd.fadeOut(down[i], now)
			end
		end
		if not a.knock then
			Crowd.fadeOut(a, now) -- (could not fall where they stood: taken away at once)
		end
		-- the people around see it: a scream, someone calls for help
		local called = false
		for _, o in agents do
			if o ~= a and not o.gone and not o.knock and not o.ko then
				local ox, oz = o.pos.X - a.pos.X, o.pos.Z - a.pos.Z
				if ox * ox + oz * oz < 20 * 20 then
					o:lookAtPoint(a.pos, 6, now)
					if not called and ctx.Mind and ctx.Mind.report and not o.companion and not o.clubGuest then
						called = true
						pcall(ctx.Mind.report, o)
					elseif ctx.Mind and ctx.Mind.flee and rnd() < 0.4 then
						pcall(ctx.Mind.flee, o, a.pos, 4 + rnd() * 3)
					end
				end
			end
		end
		return true
	elseif method == "brawl" then
		-- they fight back for a while (several swings, GwangalliFight "npcHit" for each that lands).
		-- secs = the server's window (0 = called off); hpFrac = how hurt they are (0..1: slower, swaying)
		local id, secs, hpFrac = ...
		local a = byId[id]
		if not a or a.gone or a.ko then
			return false
		end
		local now = os.clock()
		local s = tonumber(secs) or 10
		if s <= 0 then
			if a.brawl then
				a.brawl.untilT = now -- (the next chase tick ends it: the brawl_end line)
			end
			return true
		end
		a.brawl = { untilT = now + s, hp = math.clamp(tonumber(hpFrac) or 1, 0, 1) }
		a.pendingReact = nil
		a.quarrel = nil
		if not a.knock then
			local pp = P.pos
			if pp then
				a:startChase(now, pp)
			end
		end
		return true
	elseif method == "react" then
		-- after the hit: "flee" | "report" | "arrest" (played when they are back on their feet)
		local id, kind = ...
		local a = byId[id]
		if not a or a.gone or a.ko then
			return false
		end
		a.pendingReact = kind
		a.quarrel = nil
		if not a.knock then
			Crowd.playReact(a)
		end
		return true
	elseif method == "remember" then
		-- a short memory of what the player did to them (2 min): "anger" | "fear", weight adds up
		local id, kind, w = ...
		local a = byId[id]
		if not a or a.gone then
			return false
		end
		local now = os.clock()
		local m = a.memory
		if not m or now > m.untilT then
			m = { anger = 0, fear = 0, untilT = 0 }
			a.memory = m
		end
		if kind == "anger" then
			m.anger += tonumber(w) or 1
		else
			m.fear += tonumber(w) or 1
		end
		m.untilT = now + 120
		return true
	elseif method == "gunfire" then
		local x, y, z = ...
		if Crowd.Characters and tonumber(x) then
			Crowd.Characters.gunfire(Vector3.new(tonumber(x) :: number, tonumber(y) or 0, tonumber(z) or 0))
		end
		return true
	elseif method == "witness" then
		-- attack = how the player hit them ("car": a traffic accident - nobody squares up to a car),
		-- outcome = the server's (they went down: worth going over to a key NPC)
		local id, attack, outcome = ...
		if Crowd.Characters and type(id) == "string" then
			Crowd.Characters.witness(id, { car = attack == "car", down = outcome == "knockdown" or outcome == "thrown" or outcome == "ko" })
		end
		return true
	elseif method == "commotion" then
		-- a scuffle among server rigs (Law/City's 취객 싸움 and its endings): the people around notice
		local x, y, z = ...
		if Crowd.Characters and Crowd.Characters.commotion and tonumber(x) then
			Crowd.Characters.commotion(Vector3.new(tonumber(x) :: number, tonumber(y) or 0, tonumber(z) or 0))
		end
		return true
	elseif method == "emshold" then
		-- an ambulance is coming: the casualty stays down until it is picked up (or the time is up)
		local id, secs = ...
		local a = byId[id]
		if a and a.ko and not a.gone then
			a.ko.untilT = math.max(a.ko.untilT, os.clock() + (tonumber(secs) or 150))
			a.ko.ems = true
			return true
		end
		return false
	elseif method == "emspickup" then
		local id = ...
		local a = byId[id]
		if a and not a.gone then
			Crowd.fadeOut(a, os.clock())
			return true
		end
		return false
	elseif method == "hospital" then
		Crowd.setHospital((...))
		return true
	elseif method == "stats" then
		return stats
	elseif method == "info" and workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		-- test harness only: one agent's state (why an approach / chase did or did not happen)
		local a = byId[(...)]
		if not a or a.gone then
			return nil
		end
		local rp = a.rig.root and a.rig.root.Position
		return {
			id = a.id, name = (a.c and a.c.name) or a.id, type = a.type, chatty = a.chatty, mode = a.mode, idleKind = a.idleKind, hasHead = a.rig.head ~= nil,
			sitting = a.sitting == true, lying = a.lying == true, sitGround = a.sitGround == true, napping = a.napping == true,
			knock = a.knock ~= nil, chase = a.chase ~= nil, ko = a.ko ~= nil, brawl = a.brawl ~= nil, quarrel = a.quarrel ~= nil, chatState = a.chatState, near = a.near == true, onScreen = a.onScreen == true,
			companion = a.companion ~= nil, leader = a.leader ~= nil, clubGuest = a.clubGuest == true, speed = a.speed, want = a.want,
			wobble = a.wobble, walkPose = a.walkPose, walkSpeed = a.walkSpeed, baseWalkSpeed = a.baseWalkSpeed, x = a.pos.X, y = a.pos.Y, z = a.pos.Z,
			rootX = rp and rp.X, rootY = rp and rp.Y, rootZ = rp and rp.Z,
			canChat = Crowd.canChat(os.clock()), talkingNow = SocialUI.talkingNow and SocialUI.talkingNow() or false,
		}
	elseif method == "spawnnamed" and workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		-- test harness only: put a named citizen out near the player (it then follows its own day)
		local id = ...
		local pp = P.pos
		local a = if type(id) == "string" and pp then (byId[id] or Crowd.spawnResponder(id, pp, os.clock())) else nil
		return if a then { id = a.id, x = a.pos.X, y = a.pos.Y, z = a.pos.Z, delivery = a.delivery, mounted = a.mounted == true } else nil
	elseif method == "chartest" and workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		local kind, id = ...
		return if Crowd.Characters then Crowd.Characters.test(kind, id) else nil
	elseif method == "friends" and workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		return if Crowd.Friends then Crowd.Friends.stats() else nil
	elseif method == "delivery" and workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		return if Delivery then Delivery.stats() else nil
	elseif method == "debug" and workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		-- test harness only (tools/sim scenarios): retype the closest agent / a given id
		local id, spec = ...
		local a = if type(id) == "string" then byId[id] else nil
		if not a then
			local pp = P.pos
			local bd = math.huge
			for _, o in agents do
				if not o.gone and not o.clubGuest and not o.companion and pp then
					local d = flatDist(o.pos, pp)
					if d < bd then
						a, bd = o, d
					end
				end
			end
		end
		if not a or type(spec) ~= "table" then
			return nil
		end
		if type(spec.type) == "string" then
			a.chase = nil
			local base = a.baseWalkSpeed or a.walkSpeed
			if spec.type == "drunk" then
				Crowd.makeDrunk(a)
			else
				a.type = spec.type
				a.wobble = nil
				a.walkSpeed = base
				if a.walkPose == "sway" then
					a.walkPose = nil
				end
			end
		end
		if spec.chatty ~= nil then
			a.chatty = spec.chatty == true
		end
		a.chatAt = -1e9
		a.lastFoolBump = -1e9
		a.nextTypeLine = 0
		lastChat = -1e9
		chatting = nil
		debugOnly = a
		if a.rig.chip then
			a.rig.chipDirty = true
		end
		return { id = a.id, type = a.type, chatty = a.chatty, root = a.rig.root, mode = a.mode, x = a.pos.X, y = a.pos.Y, z = a.pos.Z }
	end
	return nil
end

function Crowd.noteTalk(a: any)
	if lure.open == a then
		lure.open = nil
	end
end

local function lureTick(now: number)
	local a = lure.open
	if not a then
		return
	end
	if a.gone or now - lure.openAt > 20 then
		lure.open = nil
	elseif now - lure.openAt > 3 and (a.dist or 0) > 18 then
		-- walked away from the pitch: no more pitches for a while
		lure.open = nil
		lure.snubUntil = now + Config.LureAfterWalkAway
	end
end

-------------------------------------------------------------------------------------------------
-- vehicles: the player's own car (Humanoid.SeatPart) and other driven GwangalliDrivable cars
-------------------------------------------------------------------------------------------------
local driven: { [Model]: boolean } = {}
local carLast: { [Model]: { p: Vector3, t: number, v: Vector3 } } = setmetatable({}, { __mode = "k" }) :: any
local cars: { { pos: Vector3, vel: Vector3, speed: number, horn: boolean, key: any, drive: boolean? } } = {}
local carOfSeat: { [Instance]: Model? } = setmetatable({}, { __mode = "k" }) :: any
local HORN_BIT = 64

local function vehicleModel(seat: Instance): Model?
	local c = carOfSeat[seat]
	if c ~= nil then
		return c
	end
	local m = seat.Parent
	local first: Model? = nil
	while m and m ~= workspace do
		if m:IsA("Model") then
			first = first or m
			if CollectionService:HasTag(m, "GwangalliDrivable") or m:GetAttribute("VehicleKind") ~= nil then
				first = m
				break
			end
		end
		m = m.Parent
	end
	carOfSeat[seat] = first
	return first
end

-- the local player is at the wheel of the car he sits in (not a passenger, not a taxi / police car
-- ride): only the driver's car rolls who fails to get out of the way (the server only takes the
-- driver's hits: Fight.onCarHit)
local function drivesNow(seat: BasePart?): boolean
	if not seat then
		return false
	end
	if Crowd.debugSeat ~= nil and seat == Crowd.debugSeat then
		return true
	end
	if player:GetAttribute("InTaxi") == true or player:GetAttribute("LawCuffed") then
		return false
	end
	if not seat:IsA("VehicleSeat") then
		return false
	end
	local m = vehicleModel(seat)
	local d = m and m:GetAttribute("DriveDriver")
	return d == nil or d == player.UserId -- (a VehicleSeat outside the drive system: a test seat)
end

local function watchCar(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local m = inst :: Model
	local function upd()
		local d = m:GetAttribute("DriveDriver")
		if type(d) == "number" and d ~= 0 and d ~= player.UserId then
			driven[m] = true
		else
			driven[m] = nil
		end
		if d == player.UserId then
			ownCar = m
		elseif ownCar == m then
			ownCar = nil
		end
	end
	m:GetAttributeChangedSignal("DriveDriver"):Connect(upd)
	upd()
end

local function hornOn(m: Instance?): boolean
	if not m then
		return false
	end
	local s = m:GetAttribute("DriveState")
	return type(s) == "number" and bit32.btest(s, HORN_BIT)
end

local function refreshCars()
	table.clear(cars)
	P.drive = drivesNow(P.seat)
	P.body = nil
	local pp = P.pos
	if not pp then
		return
	end
	if P.seat then
		local m = vehicleModel(P.seat)
		-- the rigged car's body box (base GwangalliVehicles/Rig: DriveCollider, x across / z along):
		-- the per-frame contact is wherever the body is, not only around the driver's seat
		local body = m and m:FindFirstChild("DriveCollider")
		P.body = if body and body:IsA("BasePart") then body else nil
		table.insert(cars, { pos = pp, vel = P.vel, speed = P.speed, horn = hornOn(m), key = "local", drive = P.drive })
	end
	-- taxis on their way (other players' rides, the local player's before boarding)
	local tf = workspace:FindFirstChild("GwangalliTaxis")
	if tf then
		for _, m in tf:GetChildren() do
			if m:IsA("Model") and not (P.seat and P.seat:IsDescendantOf(m)) then
				driven[m] = true
			end
		end
	end
	for m in driven do
		if not m.Parent then
			driven[m] = nil
		elseif P.seat and P.seat:IsDescendantOf(m) then
			-- the player's own ride: already the "local" car above
		else
			local base = m:FindFirstChild("DriveBase") or m.PrimaryPart
			if base and base:IsA("BasePart") and flatDist(base.Position, pp) < 260 then
				local ok, v = pcall(function()
					return base.AssemblyLinearVelocity
				end)
				local vel = if ok and v then Vector3.new(v.X, 0, v.Z) else Vector3.zero
				-- a car moved by CFrame (anchored / scripted) has no physics velocity: use its motion
				local now = os.clock()
				local bp = base.Position
				local last = carLast[m]
				if last and now - last.t > 0.05 then
					local dv = (bp - last.p) / (now - last.t)
					dv = Vector3.new(dv.X, 0, dv.Z)
					if dv.Magnitude > 200 then
						dv = Vector3.zero
					end
					last.v = last.v:Lerp(dv, 0.7)
					last.p, last.t = bp, now
				elseif not last then
					last = { p = bp, t = now, v = Vector3.zero }
					carLast[m] = last
				end
				if vel.Magnitude < 1 and last then
					vel = last.v
				end
				table.insert(cars, { pos = bp, vel = vel, speed = vel.Magnitude, horn = hornOn(m), key = m })
			end
		end
	end
end

-- a car faster than ~12 studs/s is about to pass within ~8 studs of p
function Crowd.carComing(p: Vector3, r: number): boolean
	for _, c in cars do
		if c.speed > 12 then
			local rx, rz = p.X - c.pos.X, p.Z - c.pos.Z
			local d = math.sqrt(rx * rx + rz * rz)
			if d < r + c.speed * 1.5 then
				local v2 = c.speed * c.speed
				local ttc = (rx * c.vel.X + rz * c.vel.Z) / v2
				if ttc > -0.2 and ttc < 2.5 then
					local cx, cz = rx - c.vel.X * ttc, rz - c.vel.Z * ttc
					if cx * cx + cz * cz < 64 then
						return true
					end
				end
			end
		end
	end
	return false
end

-- who has to get out of the way (tick rate; the per-frame contact check backs it up)
local function carReactions(now: number)
	if #cars == 0 then
		return
	end
	for _, c in cars do
		local sp = c.speed
		local reach = math.max(Config.CarReach, sp * Config.CarTTC * 1.15)
		for _, a in agents do
			if not a.gone and not a.clubGuest and not a.companion and a.mode ~= "dodge" and not a.riding then
				local rx, rz = a.pos.X - c.pos.X, a.pos.Z - c.pos.Z
				local d = math.sqrt(rx * rx + rz * rz)
				if d < reach and math.abs(a.pos.Y - c.pos.Y) < 10 then
					if sp > 8 then
						local v2 = sp * sp
						local ttc = (rx * c.vel.X + rz * c.vel.Z) / v2
						if ttc > 0 and ttc < Config.CarTTC then
							local cx, cz = rx - c.vel.X * ttc, rz - c.vel.Z * ttc
							local miss = math.sqrt(cx * cx + cz * cz)
							local px, pz = -c.vel.Z / sp, c.vel.X / sp -- perpendicular to the car's path
							local side = cx * px + cz * pz
							local s = if math.abs(side) < 0.3 then (if rnd() < 0.5 then 1 else -1) elseif side > 0 then 1 else -1
							if sp > Config.CarFast and miss < 5.5 then
								-- not everybody makes it out of the way of YOUR car: faster cars, drunks, people
								-- on their phone / sitting / asleep are hit (GwangalliFight "carHit")
								-- (only the driver's car: a passenger / taxi ride is nobody's hit, they all dive)
								if c.key == "local" and c.drive and now - (a.dodgeRollT or -1e9) > 4 then
									a.dodgeRollT = now -- (one roll per close call)
									local fail = math.clamp((sp - 12) / 70, 0, 0.45)
									if a.type == "drunk" or a.sitting or a.napping or a.sitGround or (a.plan and a.plan.act == "phone") then
										fail += 0.3
									end
									a.willBeHit = rnd() < fail
									a.willBeHitT = now
								end
								-- (a failed roll only holds for the driver's own car and only a while: any
								-- other car - a taxi, another player's, our ride as a passenger - they dodge)
								if not (c.key == "local" and c.drive and a.willBeHit and now - (a.willBeHitT or -1e9) < 4) then
									a.dodgeLocal = c.key == "local" and c.drive == true -- (the player's own driving: Agent.afterDodge)
									a:dive(now, px * s, pz * s, c.pos)
								end
							elseif miss < 4 then
								-- a slow car of the player's: most step aside, a few do not see it coming (a light
								-- hit at the contact: a stagger; 15+ studs/s they go down)
								if c.key == "local" and c.drive and now - (a.dodgeRollT or -1e9) > 4 then
									a.dodgeRollT = now
									local fail = Config.CarSlowFail or 0.06
									if a.type == "drunk" or a.sitting or a.napping or a.sitGround or (a.plan and a.plan.act == "phone") then
										fail += Config.CarSlowDistracted or 0.25
									end
									a.willBeHit = rnd() < fail
									a.willBeHitT = now
								end
								if not (c.key == "local" and c.drive and a.willBeHit and now - (a.willBeHitT or -1e9) < 4) and not (a.sitting or a.lying or a.sitGround) then
									-- step aside and look
									a:nudge(px * s * 2.6, pz * s * 2.6, ttc + 1.2, 7)
									a:lookAtPoint(c.pos, 1.5, now)
								end
							end
						end
					end
					if c.horn and d < Config.HornReach and now - (a.hornAt or -1e9) > 3 then
						local ahead = if sp > 2 then (rx * c.vel.X + rz * c.vel.Z) / sp else 1
						if ahead > -4 then
							a.hornAt = now
							a:hornReact(now, c.pos)
						end
					end
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- club queue + hang-out ring
-------------------------------------------------------------------------------------------------
local Q = { spots = {} :: { Vector3 }, first = 1, occ = {} :: { [number]: any }, nextStep = 0, hang = {} :: { Vector3 }, hangOcc = {} :: { [number]: any }, hangCenter = nil :: Vector3?, door = nil :: Vector3?, rope = nil :: Vector3?, face = Vector3.new(0, 0, 1), ready = false }
Crowd.queue = Q

-- the club's own queue rigs (ClubCrowd shows them from OUTSIDE_HYPE on) stand in the first
-- staticQueue spots; before that the street queue starts at the rope
Q.OUTSIDE_HYPE = 0.15
function Q.firstNow(): number
	if Night.hype(ctx.clock()) >= Q.OUTSIDE_HYPE then
		return Q.staticFirst or 1
	end
	return 1
end

function Q.init()
	local e = Night.clubEntrance()
	if not e then
		return
	end
	-- a little sideways jitter per spot so the line does not look drawn with a ruler
	local spots = {}
	local fx, fz = e.queueFace and e.queueFace.X or 0, e.queueFace and e.queueFace.Z or 1
	local rx, rz = -fz, fx
	for i, p in e.queue or {} do
		local j = ((i * 7919) % 9 - 4) / 10 -- -0.4 .. 0.4, stable per spot
		spots[i] = Vector3.new(p.X + rx * j, p.Y, p.Z + rz * j)
	end
	Q.spots = spots
	Q.staticFirst = math.clamp((e.staticQueue or 0) + 1, 1, math.max(1, #Q.spots))
	Q.first = Q.staticFirst
	Q.hang = e.hang or {}
	Q.hangCenter = e.hangCenter
	Q.door = e.door
	Q.rope = e.rope
	Q.face = e.queueFace or Q.face
	Q.ready = #Q.spots > 0
end

function Q.spot(i: number): Vector3
	return Q.spots[i] or Q.spots[#Q.spots] or Vector3.zero
end

function Q.nearTail(a: any): boolean
	if not Q.ready then
		return false
	end
	local tail = Q.spots[#Q.spots]
	return tail ~= nil and flatDist(a.pos, tail) < 14
end

function Q.join(a: any): number?
	if not Q.ready then
		return nil
	end
	Q.first = Q.firstNow()
	local last = Q.first - 1
	for i = Q.first, #Q.spots do
		local o = Q.occ[i]
		if o and not o.gone then
			last = i
		end
	end
	local idx = last + 1
	if idx > #Q.spots then
		return nil
	end
	Q.occ[idx] = a
	return idx
end

function Q.leave(a: any)
	local i = a.queueIdx
	if i and Q.occ[i] == a then
		Q.occ[i] = nil
	end
	a.queueIdx = nil
	local h = a.hangIdx
	if h and Q.hangOcc[h] == a then
		Q.hangOcc[h] = nil
	end
	a.hangIdx = nil
end

-- the smokers' ring: the nav hang spots (a tight circle), then two wider rings around it (only
-- points next to the pedestrian graph); a spot per person, so groups never stand inside each other
function Q.hangSpot(a: any): (Vector3?, Vector3?)
	if #Q.hang == 0 then
		return nil, nil
	end
	if not Q.hangAll then
		local all = table.clone(Q.hang)
		local c = Q.hangCenter or Q.hang[1]
		for _, ring in { { 6, 8, 0.2 }, { 9.5, 12, 0 } } do
			for k = 0, ring[2] - 1 do
				local ang = ring[3] + k * (2 * math.pi / ring[2])
				local p = Vector3.new(c.X + math.cos(ang) * ring[1], c.Y, c.Z + math.sin(ang) * ring[1])
				local node = W.nearest(p, 8)
				if node and math.abs(W.pos[node].Y - c.Y) < 2 then
					table.insert(all, p)
				end
			end
		end
		Q.hangAll = all
	end
	for i, p in Q.hangAll do
		local o = Q.hangOcc[i]
		if not o or o.gone then
			Q.hangOcc[i] = a
			a.hangIdx = i
			return p, Q.hangCenter
		end
	end
	return nil, nil
end

function Q.count(): number
	local n = 0
	for _, a in Q.occ do
		if not a.gone then
			n += 1
		end
	end
	return n
end

function Q.tick(now: number, hype: number)
	if not Q.ready then
		return
	end
	for i, a in Q.occ do
		if a.gone then
			Q.occ[i] = nil
		end
	end
	if hype < 0.12 then
		-- dawn: the line breaks up
		for i, a in Q.occ do
			Q.occ[i] = nil
			a.queueIdx = nil
			a:setPlan({ kind = "leave", act = "walk" }, now)
		end
		return
	end
	if now < Q.nextStep then
		return
	end
	Q.first = Q.firstNow()
	local qs = Config.QueueStep
	Q.nextStep = now + (qs[1] + (qs[2] - qs[1]) * rnd()) * (if hype < 0.6 then 1.6 else 1)
	local head = nil
	for i = 1, #Q.spots do
		if Q.occ[i] then
			head = i
			break
		end
	end
	if head then
		local a = Q.occ[head]
		if a and not a.queueWalk then
			Q.occ[head] = nil
			a.queueIdx = nil
			local pts = {}
			for k = head - 1, 1, -3 do
				table.insert(pts, Q.spots[k])
			end
			if Q.rope then
				table.insert(pts, Q.rope)
			end
			if Q.door then
				table.insert(pts, Q.door)
			end
			a:setPlan({ kind = "enter", act = "queue", pts = pts }, now)
		end
	end
	for i = Q.first + 1, #Q.spots do
		local a = Q.occ[i]
		if a and not a.gone and not Q.occ[i - 1] then
			Q.occ[i - 1] = a
			Q.occ[i] = nil
			a:queueMove(i - 1, now)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- plans from the schedule
-------------------------------------------------------------------------------------------------
function Crowd.makeAreaPlan(area: string, act: string): any
	local style = Agent.styleOf(act)
	local _, anchorPos = W.anchor(area)
	local def = Citizens and Citizens.AREAS and Citizens.AREAS[area]
	local move = style.move
	if def and def.indoor and act ~= "hangout" then
		-- stepped outside for a break: stand near the door with the phone
		move = "post"
		style = { move = "post", idle = "phone", speed = 1, label = style.label }
	end
	local kind = if move == "spot" then "spot" elseif move == "loop" then "loop" elseif move == "post" then "post" elseif move == "queue" then "queue" else "wander"
	return {
		kind = kind,
		area = area,
		act = act,
		style = style,
		center = anchorPos,
		radius = W.areaRadius(area),
		allow = W.areaNav(area),
	}
end

function Crowd.planInArea(a: any, area: string, act: string, now: number)
	a:setPlan(Crowd.makeAreaPlan(area, act), now)
end

local BUSY_PLANS = { enter = true, queueing = true, leave = true, watch = true, audience = true, customer = true, film = true }

-- named citizen: follow the schedule. Returns true when it set a new plan.
function Crowd.scheduleCheck(a: any, now: number, atEnd: boolean): boolean
	if not Citizens or a.ctl or a.mode == "talk" or a.mode == "follow" or a.mode == "dodge" or a.companion or a.clubGuest then
		return false
	end
	local plan = a.plan or {}
	if BUSY_PLANS[plan.kind] and not atEnd then
		return false
	end
	if plan.kind == "enter" or plan.kind == "queueing" or plan.kind == "leave" then
		return false
	end
	local clock = ctx.clock()
	local ok, area, act, info = pcall(Citizens.whereNow, a.id, clock)
	if not ok or not area then
		return false
	end
	local street = Citizens.onStreet(a.id, clock)
	if not street then
		-- going home / inside: walk away (or into the club)
		if info and info.club == "inside" then
			if plan.kind ~= "queue" then
				a:setPlan({ kind = "queue", act = "queue" }, now)
				return true
			end
			return false
		end
		a:setPlan({ kind = "leave", act = "walk" }, now)
		return true
	end
	if act == "queue" then
		if plan.kind ~= "queue" then
			a:setPlan({ kind = "queue", act = "queue" }, now)
			return true
		end
		return false
	end
	if info and info.club == "outside" and area == "club" then
		if plan.kind ~= "hang" then
			a:setPlan({ kind = "hang", act = "hangout", area = "club" }, now)
			return true
		end
		return false
	end
	if plan.area ~= area or plan.act ~= act then
		local _, ap = W.anchor(area)
		if ap and flatDist(a.pos, ap) > W.areaRadius(area) * 0.6 + 20 then
			a:setPlan({ kind = "transit", area = area, act = act, style = Agent.styleOf("walk") }, now)
		else
			Crowd.planInArea(a, area, act, now)
		end
		return true
	end
	local _ = atEnd
	return false
end

-- anonymous passer-by: night flow / time-of-day changes
function Crowd.extraCheck(a: any, now: number)
	local plan = a.plan or {}
	local k = plan.kind
	if BUSY_PLANS[k] or k == "queue" or k == "member" then
		return
	end
	local clock = ctx.clock()
	local hype = Night.hype(clock)
	if a.def.clubber and hype > 0.25 and Night.clubDistance(a.pos) < 700 and k ~= "hang" then
		a:setPlan({ kind = "queue", act = "queue" }, now)
		return
	end
	if plan.act == "sunbathe" and (clock < 9 or clock > 18) then
		a:setPlan({ kind = "wander", act = "walk", center = a.pos, radius = 150, allow = plan.allow }, now)
	end
end

function Crowd.dissolve(leader: any)
	if #leader.members == 0 then
		return
	end
	local now = os.clock()
	local members = leader.members
	leader.members = {}
	leader.handWith = nil
	for _, m in members do
		if not m.gone then
			m.leader = nil
			m.mode = "walk"
			local plan = leader.plan
			if plan and (plan.kind == "queue" or plan.kind == "queueing") then
				m:setPlan({ kind = "queue", act = "queue" }, now)
			elseif plan and plan.kind == "hang" then
				m:setPlan({ kind = "hang", act = "hangout", area = plan.area }, now)
			else
				m:setPlan({ kind = "wander", act = "walk", center = m.pos, radius = 150 }, now)
			end
		end
	end
end

-- a group member goes its own way (a car made it jump / it became a companion)
function Crowd.detachMember(m: any)
	local L = m.leader
	if not L then
		return
	end
	for i, x in L.members do
		if x == m then
			table.remove(L.members, i)
			break
		end
	end
	if L.handWith == m then
		L.handWith = nil
	end
	m.leader = nil
	m.slot = nil
end

-------------------------------------------------------------------------------------------------
-- spawning
-------------------------------------------------------------------------------------------------
local function camera(): (Vector3, Vector3)
	local cam = workspace.CurrentCamera
	if cam then
		local cf = cam.CFrame
		return cf.Position, cf.LookVector
	end
	return P.pos or Vector3.zero, Vector3.new(0, 0, -1)
end

local function onScreenPoint(p: Vector3, camPos: Vector3, look: Vector3, cosMin: number): boolean
	local d = p - camPos
	local m = d.Magnitude
	if m < 20 then
		return true
	end
	return d:Dot(look) / m > cosMin
end
Crowd.onScreenPoint = function(p: Vector3): boolean
	local cp, lk = camera()
	return onScreenPoint(p, cp, lk, 0.25)
end

-- a new person may appear at p (steady state: never in the close view)
local function spawnOK(p: Vector3, pp: Vector3, fill: boolean): boolean
	if fill then
		return true
	end
	local camPos, look = camera()
	return not (onScreenPoint(p, camPos, look, 0.2) and flatDist(p, pp) < Config.SpawnViewMin)
end

local function occupied(p: Vector3, r: number): boolean
	local r2 = r * r
	for _, a in agents do
		local dx, dz = a.pos.X - p.X, a.pos.Z - p.Z
		if dx * dx + dz * dz < r2 then
			return true
		end
	end
	return false
end

local candNodes: { number } = {}
local candW: { number } = {}
-- pick a node from the ring around pp: accept(i) -> weight (0 = no). GTA-style: ahead of the
-- player's direction of travel, off-screen or beyond SpawnViewMin when on screen, inner ring first
local function pickNode(pp: Vector3, minR: number, maxR: number, fill: boolean, accept: (number) -> number): number?
	local list = W.nearNodes(pp, maxR)
	local n = #list
	if n == 0 then
		return nil
	end
	local camPos, look = camera()
	local mvx, mvz, moving = 0, 0, false
	if P.speed > 3 then
		mvx, mvz, moving = P.vel.X / P.speed, P.vel.Z / P.speed, true
	end
	local total = 0
	local k = 0
	-- sample at most 90 nodes (random offset) to bound the cost
	local stride = math.max(1, n // 90)
	local start = 1 + math.floor(rnd() * stride)
	for j = start, n, stride do
		local i = list[j]
		local p = W.pos[i]
		local d = flatDist(p, pp)
		if d >= minR and d <= maxR and math.abs(p.Y - pp.Y) < 30 then
			local wt = accept(i)
			if wt > 0 then
				if not fill and d < Config.SpawnViewMin and onScreenPoint(p, camPos, look, 0.2) then
					wt = 0
				end
				if wt > 0 and moving then
					local dot = ((p.X - pp.X) * mvx + (p.Z - pp.Z) * mvz) / math.max(d, 1)
					wt *= 1 + 0.9 * dot -- ahead x1.9, behind x0.1
				end
				if wt > 0 then
					wt *= math.clamp(1.5 - d / maxR, 0.45, 1.15)
					if occupied(p, 3) then
						wt = 0
					end
				end
				if wt > 0 then
					k += 1
					candNodes[k] = i
					candW[k] = wt
					total += wt
				end
			end
		end
	end
	if k == 0 or total <= 0 then
		return nil
	end
	local x = rnd() * total
	for j = 1, k do
		x -= candW[j]
		if x <= 0 then
			return candNodes[j]
		end
	end
	return candNodes[k]
end

local function register(a: any)
	table.insert(agents, a)
	byId[a.id] = a
	SocialUI.attach(a)
	spawnSn += 1
	a.sn = spawnSn
	pcall(a.rig.model.SetAttribute, a.rig.model, "StreetId", a.id) -- 어깨빵 targeting (GwangalliBump)
	pcall(a.rig.model.SetAttribute, a.rig.model, "StreetSn", a.sn) -- (GwangalliFight: which person)
end

local function newAgent(def: any, spec: any, key: string, node: number?, pos: Vector3, yaw: number): any
	local cf = CFrame.new(pos.X, pos.Y + 3 * (spec.scale or 1), pos.Z) * CFrame.Angles(0, yaw, 0)
	local rig = Pool.acquire(key, spec, def.name or def.id, cf)
	local a = Agent.new(def, rig, node, pos, yaw)
	register(a)
	if Delivery then
		pcall(Delivery.attach, a)
	end
	return a
end

local function speedFor(c: any?, act: string?): number
	local base = 5.2 + rnd() * 1.4
	local age = c and c.look and c.look.age
	if age == "senior" then
		base = 3.9 + rnd() * 0.7
	elseif age == "teen" then
		base += 0.4
	end
	return base
end

-- a free POI of `style` inside the ring around pp where a person may appear now: next to the
-- chosen node first (the area fits), then anywhere in the ring (inner ring first). within(p) =
-- an extra area test (a named citizen stays inside the scheduled area)
local function ringPoi(pp: Vector3, minR: number, maxR: number, style: any, night: boolean, fill: boolean, near: Vector3?, nearR: number?, within: ((Vector3) -> boolean)?): number?
	local filter = W.poiFilter(style)
	for k = 1, 4 do
		local poi
		if near and k <= 2 then
			poi = W.findPoi(near, nearR or 30, filter, night, rnd)
		else
			poi = W.findPoi(pp, maxR, filter, night, rnd, pp, minR * 0.85)
		end
		if poi then
			local p = W.poiPos[poi]
			local d = flatDist(p, pp)
			if d >= minR * 0.85 and d <= maxR and spawnOK(p, pp, fill) and not occupied(p, 2.2) and (not within or within(p)) then
				return poi
			end
		elseif not near or k > 2 then
			return nil
		end
	end
	return nil
end

-- start the agent at an activity spot (already there a while: frac of the usual stay left)
local function settleAt(a: any, poi: number, plan: any, now: number)
	a.plan = plan
	a:takePoi(poi, plan.style)
	a.pos = a.poiSpot
	a.node = W.poiNode[poi]
	a.moved = true
	a:settleAtPoi(now, 0.3 + rnd() * 0.7)
end

-- a named citizen near the player (or nil when no spot fits)
-- 길거리 싸움 (GwangalliFight): citizens who went down are in hospital (server "down" list, unix end)
local hospital: { [string]: number } = {}
function Crowd.setHospital(ids: any)
	hospital = if type(ids) == "table" then ids else {}
end

local function spawnNamed(id: string, pp: Vector3, fill: boolean, now: number): any?
	local c = Citizens.get(id)
	if not c then
		return nil
	end
	if (hospital[id] or 0) > os.time() then
		return nil
	end
	local clock = ctx.clock()
	local ok, area, act, info = pcall(Citizens.whereNow, id, clock)
	if not ok or not area then
		return nil
	end
	local _, anchorPos = W.anchor(area)
	if not anchorPos then
		return nil
	end
	local minR = if fill then Config.FillMin else tierVal(Config.SpawnMin)
	local maxR = tierVal(Config.SpawnMax)
	local transit = info and info.transit and info.from
	local p0 = transit and W.areaPos(info.from)
	local allow = W.areaNav(area)
	local r = W.areaRadius(area)
	local node = pickNode(pp, minR, maxR, fill, function(i)
		local p = W.pos[i]
		if p0 then
			return if segDist(p, p0, anchorPos) < 70 then 1 else 0
		end
		if allow and not allow[W.area[i]] then
			return 0
		end
		return if flatDist(p, anchorPos) <= r + 25 then 1 else 0
	end)
	if not node then
		return nil
	end
	local hype = Night.hype(clock)
	local night = (info and info.club ~= nil) or (hype > 0.45 and (c.club or 0) > 0.3 and act ~= "work")
	local spec = Looks.forCitizen(c, night)
	local key = id .. (if spec.night then "#n" else "#d")
	local p = W.pos[node]
	local yaw = rnd() * math.pi * 2
	-- an activity at a spot: start right there when a free one is next to the chosen node
	local plan = nil
	local poi = nil
	if act ~= "queue" and not (info and info.club == "outside" and area == "club") and not p0 then
		plan = Crowd.makeAreaPlan(area, act)
		if plan.kind == "spot" then
			local ctr, rad = plan.center or p, (plan.radius or 140) + 25
			poi = ringPoi(pp, minR, maxR, plan.style, hype > 0.35, fill, p, 28, function(q)
				return flatDist(q, ctr) <= rad
			end)
		end
	end
	local a = newAgent({ id = id, name = c.name, named = true, citizen = c, speed = speedFor(c, act), lure = (c.club or 0) >= 0.35 }, spec, key, node, if poi then W.poiPos[poi] else p, yaw)
	if poi then
		settleAt(a, poi, plan, now)
	elseif act == "queue" then
		a:setPlan({ kind = "queue", act = "queue" }, now)
	elseif info and info.club == "outside" and area == "club" then
		a:setPlan({ kind = "hang", act = "hangout", area = "club" }, now)
	elseif p0 then
		a:setPlan({ kind = "transit", area = area, act = act, style = Agent.styleOf("walk") }, now)
	elseif plan and plan.kind == "post" and flatDist(p, plan.center or p) < 40 then
		a.plan = plan
		a:idleFor(plan.style.idle or "idle", 8 + rnd() * 20, now)
	else
		a:setPlan(plan or Crowd.makeAreaPlan(area, act), now)
	end
	return a
end

-- npc_mind: a police officer dispatched to the player (GwangalliStreetLife/Mind.dispatch): spawned
-- out of sight in a ring around the player whatever the roster says (they come from the 지구대)
function Crowd.spawnResponder(id: string, pp: Vector3, now: number): any?
	local c = Citizens and Citizens.get(id)
	if not c or byId[id] or (hospital[id] or 0) > os.time() then
		return nil
	end
	local node = pickNode(pp, 40, 80, true, function(_i)
		return 1
	end)
	if not node then
		return nil
	end
	local spec = Looks.forCitizen(c, false)
	local a = newAgent({ id = id, name = c.name, named = true, citizen = c, speed = speedFor(c, "patrol"), lure = false }, spec, id .. "#d", node, W.pos[node], rnd() * math.pi * 2)
	a:idleFor("idle", 1, now)
	return a
end

-- anonymous passers-by -------------------------------------------------------------------------
local AREA_BUSY = { promenade = 1.7, beach = 1.3, plaza_meeting = 1.8, plaza_festival = 1.5, plaza_sunrise = 1.3, haebyeon = 1.4, club = 1.2, backlane = 1.1, gwangnam = 1, suyeong = 1, side = 0.8, metro = 1.2, uptown = 0.5, millak_park = 1, millak_port = 0.9, namcheon_park = 1, samik = 0.6 }
local EXTRA_ALLOW = {
	promenade = { "promenade", "plaza_meeting", "plaza_festival", "plaza_sunrise", "beach" },
	beach = { "beach", "promenade" },
	plaza_meeting = { "plaza_meeting", "promenade", "haebyeon" },
	plaza_festival = { "plaza_festival", "promenade" },
	plaza_sunrise = { "plaza_sunrise", "promenade" },
	haebyeon = { "haebyeon", "promenade", "plaza_meeting", "side" },
	backlane = { "backlane", "side", "gwangnam" },
	gwangnam = { "gwangnam", "side", "backlane", "suyeong" },
	suyeong = { "suyeong", "side", "metro" },
	side = { "side", "gwangnam", "backlane", "haebyeon", "club" },
	club = { "club", "side" },
	metro = { "metro", "suyeong", "side" },
	uptown = { "uptown", "side" },
	millak_park = { "millak_park", "millak_port" },
	millak_port = { "millak_port", "millak_park" },
	namcheon_park = { "namcheon_park", "promenade" },
	samik = { "samik", "side" },
}

local DOG_AREAS = { promenade = true, plaza_meeting = true, plaza_festival = true, plaza_sunrise = true, millak_park = true, namcheon_park = true, samik = true, haebyeon = true, side = true }
local BEACH_AREAS = { beach = true, promenade = true, plaza_meeting = true, plaza_festival = true, plaza_sunrise = true, haebyeon = true, namcheon_park = true, millak_park = true, millak_port = true }
local STREET_AREAS = { side = true, suyeong = true, metro = true, gwangnam = true, backlane = true, uptown = true }
local SUN_STYLE = { move = "spot", kinds = { "towel" }, tags = { "sunbathe" }, idle = "sunbathe", speed = 0.8 }
local STATIONARY_ACTS = { "sit", "photo", "shop", "eat", "cafe", "sunbathe", "wait" }
local EXIT_STYLE = { move = "spot", kinds = { "metro", "shop", "cafe" }, idle = "idle", speed = 1 }

local function weighted(list: { any }): any
	local total = 0
	for i = 2, #list, 2 do
		total += list[i]
	end
	local x = rnd() * total
	for i = 1, #list, 2 do
		x -= list[i + 1]
		if x <= 0 then
			return list[i]
		end
	end
	return list[1]
end

-- stationary = the next person should be doing something at a spot (the walk share is high)
local function extraAct(navArea: string, clock: number, hype: number, clubD: number, stationary: boolean): string
	local night = hype > 0.2
	local sunny = clock >= 9 and clock < 18
	local w = if stationary then 0.06 else 1 -- walking / jogging weight factor
	if night and clubD < 380 then
		return weighted({ "queue", 0.55, "hangout", 0.2, "walk", 0.25 * w })
	end
	if navArea == "beach" then
		if night then
			return weighted({ "walk", 0.5 * w, "photo", 0.22, "sit", 0.18, "hangout", 0.1 })
		end
		return weighted({ "walk", 0.26 * w, "photo", 0.2, "sunbathe", if sunny then 0.3 else 0, "sit", 0.12, "jog", 0.05 * w, "play", 0.07 * w })
	elseif navArea == "promenade" or navArea == "plaza_meeting" or navArea == "plaza_festival" or navArea == "plaza_sunrise" then
		return weighted({ "walk", 0.34 * w, "sit", 0.22, "photo", 0.15, "jog", (if night then 0.03 else 0.09) * w, "hangout", 0.14, "eat", 0.05 })
	elseif navArea == "haebyeon" then
		return weighted({ "walk", 0.32 * w, "cafe", 0.26, "shop", 0.24, "eat", 0.16, "wait", 0.05 })
	elseif navArea == "millak_park" or navArea == "namcheon_park" or navArea == "samik" then
		return weighted({ "walk", 0.42 * w, "sit", 0.27, "jog", (if night then 0.05 else 0.14) * w, "photo", 0.1, "fish", 0.05 })
	elseif navArea == "millak_port" then
		return weighted({ "walk", 0.45 * w, "eat", 0.27, "fish", 0.16, "sit", 0.12 })
	elseif navArea == "club" then
		return weighted({ "walk", 0.6 * w, "hangout", 0.4 })
	end
	if night then
		return weighted({ "walk", 0.55 * w, "drink", 0.25, "shop", 0.12, "wait", 0.08 })
	end
	-- the city's day (owner: law / NPC life): 출근 + 카페 + 편의점 in the morning, 점심, 퇴근 + 저녁 식당 / 술집
	if clock >= 7 and clock < 10 then
		return weighted({ "walk", 0.55 * w, "cafe", 0.2, "shop", 0.15, "wait", 0.1 })
	elseif clock >= 11.5 and clock < 14 then
		return weighted({ "walk", 0.4 * w, "eat", 0.3, "cafe", 0.12, "shop", 0.12, "sit", 0.06 })
	elseif clock >= 17.5 and clock < 22 then
		return weighted({ "walk", 0.44 * w, "eat", 0.24, "drink", 0.16, "shop", 0.1, "wait", 0.06 })
	elseif clock >= 22 or clock < 5 then
		return weighted({ "walk", 0.5 * w, "drink", 0.32, "shop", 0.1, "wait", 0.08 })
	end
	return weighted({ "walk", 0.5 * w, "shop", 0.18, "eat", 0.13, "cafe", 0.08, "sit", 0.04, "wait", 0.1 })
end

-- a free passer-by id; ids whose rig for this outfit variant is still pooled come first (no rebuild)
local function takeExtraId(suffix: string): string?
	if #extraFree == 0 then
		return nil
	end
	local pick = nil
	local start = 1 + math.floor(rnd() * #extraFree)
	for k = 0, #extraFree - 1 do
		local i = (start + k - 1) % #extraFree + 1
		if Pool.has(extraFree[i] .. suffix) then
			pick = i
			break
		end
	end
	local i = pick or start
	local id = extraFree[i]
	extraFree[i] = extraFree[#extraFree]
	extraFree[#extraFree] = nil
	return id
end

local function spawnMember(leader: any, side: number, back: number, night: boolean, now: number, hand: boolean?): any?
	local suffix = if night then "#n" else "#d"
	local id = takeExtraId(suffix)
	if not id then
		return nil
	end
	local spec = Looks.random(id, { night = night or nil })
	local key = id .. suffix
	local rx, rz = math.cos(leader.yaw), -math.sin(leader.yaw)
	local sw = Config.GroupSide
	local p = leader.pos + Vector3.new(rx * side * sw, 0, rz * side * sw)
	if leader.sitting or leader.sitGround then
		local fx, fz = -math.sin(leader.yaw), -math.cos(leader.yaw)
		p = leader.pos + Vector3.new(fx * 2.8 + rx * side * 1.6, 0, fz * 2.8 + rz * side * 1.6)
	end
	local m = newAgent({ id = id, named = false, speed = leader.walkSpeed }, spec, key, nil, p, leader.yaw)
	m.leader = leader
	m.slot = { side = side, back = back, phone = rnd() < 0.3, hand = hand == true }
	m.mode = "member"
	m.plan = { kind = "member" }
	table.insert(leader.members, m)
	if hand then
		leader.handWith = m
		leader.handSide = if side > 0 then "handR" else "handL"
		if leader.mode == "walk" then
			leader:applyWalkPose()
		end
	end
	return m
end

-- opts: { stationary = bool (prefer an activity at a spot), sun = bool (a sunbather on a towel),
--         busker = { spot, face, untilT } (a listener for the busker) }
local function spawnExtra(pp: Vector3, fill: boolean, now: number, room: number, opts: any?): any?
	if #extraFree == 0 then
		return nil
	end
	local o = opts or {}
	local clock = ctx.clock()
	local hype = Night.hype(clock)
	local minR = if fill then Config.FillMin else tierVal(Config.SpawnMin)
	local maxR = tierVal(Config.SpawnMax)
	local night = hype > 0.2
	local node, poi, act, exitPoi = nil, nil, nil, nil
	-- a sunbather on a free towel inside the ring
	if o.sun then
		poi = ringPoi(pp, minR, maxR, SUN_STYLE, false, fill)
		if poi then
			node = W.poiNode[poi]
			act = "sunbathe"
		end
	end
	if not node and o.atNode then
		node = o.atNode
		act = "walk"
	end
	if not node then
		node = pickNode(pp, minR, maxR, fill, function(i)
			local name = ctx.Nav.AREA[W.area[i]]
			local wt = AREA_BUSY[name] or 0.8
			if night then
				if name == "club" then
					wt *= 2.5
				elseif name == "beach" then
					wt *= 0.5
				end
			end
			return wt
		end)
	end
	if not node then
		return nil
	end
	local navArea = ctx.Nav.AREA[W.area[node]] or "side"
	local clubD = Night.clubDistance(W.pos[node])
	local droneLeft = Crowd.droneLeft(now)
	if not act then
		if droneLeft and BEACH_AREAS[navArea] and rnd() < 0.75 then
			act = "watch"
		else
			act = extraAct(navArea, clock, hype, clubD, o.stationary == true)
		end
	end
	local style = if act == "watch" then nil else Agent.styleOf(act)
	-- activity at a spot: most start right there (a free spot next to the chosen node)
	local spotAct = style ~= nil and style.move == "spot" and not (act == "hangout" and clubD < 380 and night)
	if not poi and spotAct and (o.stationary or fill or rnd() < Config.InPlaceChance) then
		poi = ringPoi(pp, minR, maxR, style, hype > 0.35, fill, W.pos[node], 30)
	end
	if not poi and o.stationary and not (night and clubD < 380) then
		-- the street needs people doing something: any activity spot that is free in the ring
		for _, alt in STATIONARY_ACTS do
			if alt ~= act and (alt ~= "sunbathe" or (clock >= 9 and clock < 18 and not night)) then
				local st = Agent.styleOf(alt)
				poi = ringPoi(pp, minR, maxR, st, hype > 0.35, fill)
				if poi then
					act, style, spotAct = alt, st, true
					node = W.poiNode[poi]
					navArea = ctx.Nav.AREA[W.area[node]] or navArea
					break
				end
			end
		end
	end
	-- somebody coming out of the metro / a shop
	if not poi and act == "walk" and rnd() < 0.15 then
		exitPoi = ringPoi(pp, minR, maxR, EXIT_STYLE, hype > 0.35, fill)
	end
	local clubby = act == "queue" or (act == "hangout" and clubD < 380 and night)
	local nightOutfit = clubby or (night and rnd() < 0.35)
	-- somebody walking the dog (promenade, plazas, parks; daytime and early evening)
	local dog = act == "walk" and not nightOutfit and DOG_AREAS[navArea] == true and clock >= 7 and clock < 21 and rnd() < Config.DogChance
	-- one look per passer-by id and variant: day, night (club outfit), jogging or with a dog
	local suffix = if nightOutfit then "#n" elseif act == "jog" then "#j" elseif dog then "#g" else "#d"
	local id = takeExtraId(suffix)
	if not id then
		return nil
	end
	local hint = { style = if act == "jog" then "sporty" else nil, night = if nightOutfit then true else nil, dog = if dog then true else nil }
	local spec = Looks.random(id, hint)
	local key = id .. suffix
	local p = W.pos[node]
	if exitPoi then
		p = W.poiPos[exitPoi]
		node = W.poiNode[exitPoi]
	elseif poi then
		p = W.poiPos[poi] -- appears right at the spot (settleAt puts it on its seat)
	end
	local yaw = rnd() * math.pi * 2
	local speed = speedFor(nil, act) * (if dog then 0.85 else 1)
	-- late at night some passers-by have had a few too many (취객: the sway walk, the bumps, the lines)
	local lateNight = clock >= 22 or clock < 4
	local drunkNow = lateNight and not dog and not fill and rnd() < (if clubD < 380 then 0.14 else 0.2)
	local a = newAgent({ id = id, named = false, speed = speed, clubber = not dog and (clubby or (night and rnd() < hype * 0.5)), lure = clubby or (night and rnd() < 0.3), dog = dog, type = if drunkNow then "drunk" else nil }, spec, key, node, p, yaw)
	local allow = W.areaSet(EXTRA_ALLOW[navArea])
	if act == "queue" then
		-- first fill near the club: stand straight in the line
		if fill and Q.ready then
			local idx = Q.join(a)
			if idx then
				a.pos = Q.spot(idx)
				a.queueIdx = idx
				a.plan = { kind = "queueing", act = "queue", style = Agent.styleOf("queue") }
				a:idleFor(if rnd() < 0.5 then "phone" else "idle", 1e6, now, math.atan2(-Q.face.X, -Q.face.Z))
				return a
			end
		end
		a:setPlan({ kind = "queue", act = "queue" }, now)
	elseif act == "hangout" and clubD < 380 and night then
		a:setPlan({ kind = "hang", act = "hangout" }, now)
	elseif act == "watch" and droneLeft then
		a:setPlan({ kind = "watch", act = "photo", untilT = now + droneLeft - rnd() * 8, faceYaw = Crowd.droneYaw(p), stay = rnd() < 0.8, resume = { kind = "wander", act = "walk", center = p, radius = 220, allow = allow } }, now)
	else
		local move = style.move
		local kind = if move == "spot" then "spot" elseif move == "loop" then "loop" elseif move == "post" then "post" else "wander"
		local plan = { kind = kind, act = act, style = style, center = p, radius = if act == "walk" then 220 else 140, allow = allow, area = nil }
		if poi then
			settleAt(a, poi, plan, now)
		else
			a:setPlan(plan, now)
		end
	end
	-- friends walking / hanging out together
	local hangRing = a.plan and a.plan.kind == "hang" -- the smokers' ring: one spot each, no circles
	if room >= 2 and not dog and not hangRing and act ~= "jog" and act ~= "sunbathe" and act ~= "fish" and act ~= "wait" and rnd() < (if act == "hangout" then 0.6 else Config.GroupChance) then
		local couple = room < 3 or rnd() < 0.65
		spawnMember(a, 1, 0, spec.night, now, couple and rnd() < Config.HoldHands)
		if not couple then
			spawnMember(a, -1, 0.3, spec.night, now)
		end
	end
	return a
end

-- a named citizen dancing inside CLUB OCEAN in the place of a club crowd rig (ClubCrowd):
-- floorPos = the rig's feet, yaw = its facing, dance = "dance" | "dance2" | "dance3"
function Crowd.spawnClubGuest(id: string, floorPos: Vector3, yaw: number, dance: string): any?
	local c = Citizens and Citizens.get(id)
	if not c or byId[id] then
		return nil
	end
	local spec = Looks.forCitizen(c, true)
	local key = id .. (if spec.night then "#n" else "#d")
	local a = newAgent({ id = id, name = c.name, named = true, citizen = c, speed = speedFor(c, "club"), lure = false }, spec, key, nil, floorPos, yaw)
	a.clubGuest = true
	a.clubDance = dance
	a.clubYaw = yaw
	a.plan = { kind = "clubdance", act = "club", style = Agent.styleOf("club") }
	a.nextSchedule = math.huge
	a:idleFor(dance, 1e9, os.clock(), yaw)
	a.moved = true
	return a
end

-------------------------------------------------------------------------------------------------
-- removal
-------------------------------------------------------------------------------------------------
local function setFade(a: any, k: number)
	-- 8 steps over the half-second fade (not every frame): the eye cannot tell, ~half the writes
	local step = math.clamp(math.floor(k * 8 + 0.5), 0, 8)
	if a.fadeStep == step then
		return
	end
	a.fadeStep = step
	k = step / 8
	local rig = a.rig
	for _, p in rig.parts do
		p.LocalTransparencyModifier = k
	end
	for _, p in rig.extras do
		if p:IsA("BasePart") then
			p.LocalTransparencyModifier = k
		end
	end
end

function Crowd.remove(a: any)
	if a.gone then
		return
	end
	a.gone = true
	if Delivery then
		pcall(Delivery.detach, a)
	end
	if a.fadeAt then
		a.fadeAt = nil
		setFade(a, 0)
	end
	a:releasePoi()
	Q.leave(a)
	SocialUI.detach(a)
	a.knock = nil
	a.chase = nil
	a.chatState = nil
	a.napping = false
	pcall(a.rig.model.SetAttribute, a.rig.model, "StreetId", nil)
	pcall(a.rig.model.SetAttribute, a.rig.model, "StreetSn", nil)
	Pool.release(a.rig)
	if byId[a.id] == a then
		byId[a.id] = nil
	end
	for i = #agents, 1, -1 do
		if agents[i] == a then
			table.remove(agents, i)
			break
		end
	end
	recent[a.id] = os.clock()
	if not a.named then
		table.insert(extraFree, a.id)
	end
	for _, m in a.members do
		Crowd.remove(m)
	end
	if a.leader then
		Crowd.detachMember(a)
	end
end

-- fade out over 0.5 s, then remove (somebody the player can see)
function Crowd.fadeOut(a: any, now: number)
	if a.gone or a.fadeAt then
		return
	end
	a.fadeAt = now
	for _, m in a.members do
		Crowd.fadeOut(m, now)
	end
end

-- graceful: vanish when unseen, else walk away (close) or fade (far)
function Crowd.retire(a: any, now: number)
	if a.gone then
		return
	end
	if not a.onScreen then
		Crowd.remove(a)
	elseif a.dist > 70 then
		Crowd.fadeOut(a, now)
	elseif not (a.plan and a.plan.kind == "leave") then
		if a.leader then
			return -- members leave with their leader
		end
		a:setPlan({ kind = "leave", act = "walk" }, now)
	end
end

-------------------------------------------------------------------------------------------------
-- companions (Relationships "hangout": the friend follows the player)
-------------------------------------------------------------------------------------------------
local function setKeyHidden(id: string, hide: boolean)
	local folder = workspace:FindFirstChild("GwangalliNPCs")
	if hide then
		if hiddenKey[id] or not folder then
			return
		end
		local m = folder:FindFirstChild("NPC_" .. id)
		if not m then
			for _, ch in folder:GetChildren() do
				if ch:GetAttribute("NpcId") == id then
					m = ch
					break
				end
			end
		end
		if m then
			local list = {}
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 1
					table.insert(list, d)
				end
			end
			hiddenKey[id] = list
		end
	else
		local list = hiddenKey[id]
		hiddenKey[id] = nil
		if list then
			for _, d in list do
				if d.Parent then
					d.LocalTransparencyModifier = 0
				end
			end
		end
	end
end

local function syncCompanions(now: number)
	if not Citizens then
		return
	end
	local want: { [Player]: string } = {}
	for _, plr in Players:GetPlayers() do
		local id = plr:GetAttribute("GwangalliCompanion")
		if type(id) == "string" and id ~= "" and Citizens.get(id) then
			local ch = plr.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (plr == player or (P.pos and flatDist(root.Position, P.pos) < 320)) then
				want[plr] = id
			end
		end
	end
	for plr, a in companions do
		if want[plr] ~= a.id or a.gone then
			companions[plr] = nil
			if not a.gone then
				a.companion = nil
				a.followPlayer = nil
				a.waitCar = nil
				a.riding, a.rideCF = nil, nil
				a.sitting = false
				if plr == player then
					pcall(function()
						player:SetAttribute("GwangalliCompanionState", nil)
					end)
				end
				if Citizens.isKey(a.id) then
					Crowd.remove(a)
				else
					a:setPlan({ kind = "leave", act = "walk" }, now)
				end
			end
			if Citizens.isKey(a.id) then
				setKeyHidden(a.id, false)
			end
		end
	end
	for plr, id in want do
		if not companions[plr] then
			local a = byId[id]
			if a and not a.gone then
				Crowd.dissolve(a)
				if a.leader then
					Crowd.detachMember(a)
				end
				a:releasePoi()
				Q.leave(a)
			else
				local c = Citizens.get(id)
				local ch = plr.Character
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				if c and root and root:IsA("BasePart") then
					local cf = root.CFrame
					local back = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
					back = if back.Magnitude > 0.1 then back.Unit else Vector3.new(0, 0, -1)
					local p = cf.Position - back * 5 - Vector3.new(0, 3, 0)
					local night = Night.hype(ctx.clock()) > 0.45 and (c.club or 0) > 0.2
					local spec = Looks.forCitizen(c, night)
					a = newAgent({ id = id, name = c.name, named = true, citizen = c, speed = 6.2 }, spec, id .. (if spec.night then "#n" else "#d"), nil, p, math.atan2(-back.X, -back.Z))
				end
			end
			if a then
				a.companion = plr
				a.followPlayer = plr
				a.nextSchedule = os.clock() + 8
				a:setPlan({ kind = "follow", act = "hangout" }, now)
				a:setCompanionState("follow")
				companions[plr] = a
				if Citizens.isKey(id) then
					setKeyHidden(id, true)
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- events: the drone show, the busker's audience, street food customers, filming the player
-------------------------------------------------------------------------------------------------
local DRONE_CENTER = Vector3.new(0, 310, -1400)
do
	local m = ReplicatedStorage:FindFirstChild("GwangalliConfig")
	if m and m:IsA("ModuleScript") then
		local ok, cfg = pcall(require, m)
		if ok and type(cfg) == "table" and type(cfg.DroneShow) == "table" and typeof(cfg.DroneShow.Center) == "Vector3" then
			DRONE_CENTER = cfg.DroneShow.Center
		end
	end
end

-- seconds of the drone show left (nil when none is running)
function Crowd.droneLeft(_now: number?): number?
	local start = workspace:GetAttribute("GwangalliDroneShowStart")
	if type(start) ~= "number" then
		return nil
	end
	local dur = workspace:GetAttribute("GwangalliDroneShowDuration")
	dur = if type(dur) == "number" then dur else 180
	local t = workspace:GetServerTimeNow() - start
	if t >= 0 and t < dur - 5 then
		return dur - t
	end
	return nil
end

function Crowd.droneYaw(p: Vector3): number
	return yawOf(DRONE_CENTER.X - p.X, DRONE_CENTER.Z - p.Z)
end

local keyNpcs: { [string]: Model } = {}
local keyScan = -1e9
local function keyNpc(id: string): Model?
	return Crowd.keyNpc(id)
end
function Crowd.keyNpc(id: string): Model?
	local m = keyNpcs[id]
	if m and m.Parent then
		return m
	end
	local now = os.clock()
	if now - keyScan < 5 then
		return nil
	end
	keyScan = now
	local folder = workspace:FindFirstChild("GwangalliNPCs")
	if not folder then
		return nil
	end
	for _, ch in folder:GetChildren() do
		local nid = ch:GetAttribute("NpcId")
		if type(nid) == "string" and ch:IsA("Model") then
			keyNpcs[nid] = ch
		end
	end
	return keyNpcs[id]
end

local function npcFrame(m: Model): (Vector3?, Vector3)
	local root = m:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil, Vector3.new(0, 0, -1)
	end
	local yaw = m:GetAttribute("NpcYaw")
	local look
	if type(yaw) == "number" then
		local r = math.rad(yaw)
		look = Vector3.new(-math.sin(r), 0, -math.cos(r))
	else
		look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	end
	local g = m:GetAttribute("NpcGround")
	local feet = root.Position - Vector3.new(0, if type(g) == "number" then g else 3, 0)
	return feet, look
end

-- people who can drop what they are doing for an event
local FREE_PLANS = { wander = true, spot = true, loop = false, post = false, transit = true }
local function available(a: any): boolean
	if a.gone or a.clubGuest or a.companion or a.leader or a.fadeAt then
		return false
	end
	if a.mode == "talk" or a.mode == "dodge" or a.mode == "follow" or a.mode == "member" then
		return false
	end
	local k = a.plan and a.plan.kind
	if not FREE_PLANS[k] then
		return false
	end
	if a.named and a.plan.act == "work" then
		return false
	end
	return true
end

local ev = { busker = nil :: string?, nextCustomer = 0, lastDance = -1e9, danceCheck = 0, droneOn = false }
local DANCE_IDS: { [string]: boolean } = {}
local function streetCount(): number
	local n = 0
	for _, a in agents do
		if not a.companion and not a.clubGuest then
			n += 1
		end
	end
	return n
end

-- one passer-by for an incident (GwangalliStreetLife/Mind.incident) on a path minR..maxR studs from at,
-- when nobody fitting is there: the usual extra spawn (no friend group), never popping up in the
-- player's close view, within the street cap (+1, like the busker's listener)
function Crowd.spawnExtraNear(at: Vector3, now: number, minR: number?, maxR: number?): any?
	local pp = P.pos
	if not pp or streetCount() >= (Crowd.cap or tierVal(Config.Cap)) + 1 then
		return nil
	end
	local node = pickNode(at, minR or 25, maxR or 60, true, function(i)
		local p = W.pos[i]
		if flatDist(p, pp) < 14 or flatDist(p, pp) > 130 or not spawnOK(p, pp, false) then
			return 0
		end
		return 1
	end)
	local a = if node then spawnExtra(pp, false, now, 1, { atNode = node }) else nil
	if a and flatDist(a.pos, at) > (maxR or 60) + 15 then
		return nil -- (came out of a shop / the metro elsewhere: just another passer-by)
	end
	return a
end

local function eventsTick(now: number, pp: Vector3, cap: number)
	-- the drone show: the beach crowd turns to the bay (a few at a time)
	local left = Crowd.droneLeft(now)
	if left then
		for _, a in agents do
			if available(a) and a.plan.kind ~= "transit" and rnd() < 0.45 and now >= (a.droneAt or 0) then
				local node = a.node or W.nearest(a.pos, 40)
				local area = node and ctx.Nav.AREA[W.area[node]]
				if area and BEACH_AREAS[area] then
					if a.sitting or a.sitGround or a.lying then
						-- stay seated: look up at the show, film it now and then
						a.droneAt = now + 8 + rnd() * 6
						a:lookAtPoint(DRONE_CENTER, 8, now)
						if not a.lying and rnd() < 0.5 then
							Anim.flash(a.rig, "photo", 5)
						end
					else
						a:setPlan({ kind = "watch", act = "photo", untilT = now + left - rnd() * 8, faceYaw = Crowd.droneYaw(a.pos), resume = a.plan, stay = rnd() < 0.7 }, now)
					end
				end
			end
		end
	end
	-- the busker's audience
	local busker = keyNpc("busker")
	if busker then
		local bp, look = npcFrame(busker)
		local act = busker:GetAttribute("NpcAct")
		if bp and flatDist(bp, pp) < 150 then
			local audience = {}
			for _, a in agents do
				if not a.gone and a.plan and a.plan.kind == "audience" then
					table.insert(audience, a)
				end
			end
			if act == "guitar" then
				local want = tierVal(Config.AudienceMax)
				if #audience < want then
					-- a free spot on the walkable ground 7-10 studs in front of (or beside) the busker
					local k = #audience
					local rx, rz = -look.Z, look.X
					local spot = nil
					for _, ang in { 0, -0.7, 0.7, -1.25, 1.25, -0.35, 0.35, -1.7, 1.7, 3.14 } do
						local r = 7 + ((k + math.floor(ang * 10)) % 3) + rnd()
						local c, sn = math.cos(ang), math.sin(ang)
						local dx, dz = look.X * c + rx * sn, look.Z * c + rz * sn
						local p = Vector3.new(bp.X + dx * r, bp.Y, bp.Z + dz * r)
						-- open ground on the busker's level (the pedestrian graph is sparse on the sand / plazas)
						local node = W.nearest(p, 40)
						if node and math.abs(W.pos[node].Y - bp.Y) < 2.5 and not occupied(p, 2.4) then
							spot = Vector3.new(p.X, bp.Y, p.Z)
							break
						end
					end
					local plan = { kind = "audience", act = "watch", spot = spot, face = bp, untilT = now + 40 + rnd() * 50 }
					-- somebody close by stops to listen (walkers first), else a new passer-by comes over
					local best, bd = nil, 60
					for _, a in agents do
						if spot and available(a) and (not a.named or a.plan.kind == "wander") then
							local d = flatDist(a.pos, bp) + (if a.mode == "walk" then 0 else 15)
							if d < bd then
								best, bd = a, d
							end
						end
					end
					if workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
						print(string.format("[StreetLifeEv] busker audience=%d/%d best=%s spot=%s", #audience, want, if best then best.id else "-", tostring(spot)))
					end
					if best then
						-- somebody on the other level (the promenade above the busker on the sand)
						-- watches from the nearest edge of their own path instead of taking the stairs
						if math.abs(best.pos.Y - bp.Y) > 2 then
							local alt = W.closestWalkable(bp, best.pos.Y, 45, 5)
							if alt and flatDist(alt, bp) < 28 and not occupied(alt, 2.4) then
								plan.spot = alt
							end
						end
						plan.resume = best.plan
						best:setPlan(plan, now)
					elseif spot and streetCount() < cap + 1 then
						-- a new listener arrives from a path 25-45 studs away (out of the close view)
						for _ = 1, 3 do
							local ang2 = rnd() * math.pi * 2
							local rr = 25 + rnd() * 20
							local node = W.nearest(Vector3.new(bp.X + math.cos(ang2) * rr, bp.Y, bp.Z + math.sin(ang2) * rr), 20)
							local np = node and W.pos[node]
							local camPos, look = camera()
							local dp = np and flatDist(np, pp) or 0
							if np and dp > 22 and (not onScreenPoint(np, camPos, look, 0.25) or dp > 40) and not occupied(np, 3) then
								local a = spawnExtra(pp, false, now, 1, { atNode = node })
								if a then
									if math.abs(np.Y - bp.Y) > 2 then
										local alt = W.closestWalkable(bp, np.Y, 45, 5)
										if alt and flatDist(alt, bp) < 28 and not occupied(alt, 2.4) then
											plan.spot = alt
										end
									end
									plan.resume = { kind = "wander", act = "walk", center = np, radius = 200 }
									a:setPlan(plan, now)
								end
								break
							end
						end
					end
				end
			elseif ev.busker == "guitar" then
				-- the song ended: applause
				for _, a in audience do
					if a.mode == "idle" then
						Anim.flash(a.rig, "clap", 2.4)
						if rnd() < 0.3 then
							Anim.gesture(a.rig, "cheer")
						end
					end
				end
			end
		end
		ev.busker = act
	end
	-- street food: a customer or two at the 붕어빵 cart
	local vendor = keyNpc("bungeoppang")
	if vendor and now >= ev.nextCustomer then
		ev.nextCustomer = now + 10 + rnd() * 14
		local vp, look = npcFrame(vendor)
		local act = vendor:GetAttribute("NpcAct")
		if vp and act == "flip" and flatDist(vp, pp) < 120 then
			local n = 0
			for _, a in agents do
				if not a.gone and a.plan and a.plan.kind == "customer" then
					n += 1
				end
			end
			if n < Config.CustomersMax then
				local best, bd = nil, 60
				for _, a in agents do
					if available(a) and a.mode == "walk" then
						local d = flatDist(a.pos, vp)
						if d < bd then
							best, bd = a, d
						end
					end
				end
				if best then
					local rx, rz = -look.Z, look.X
					local j = (rnd() - 0.5) * 1.6
					local back = 4.4 + n * 2.3
					local spot = Vector3.new(vp.X + look.X * back + rx * j, vp.Y, vp.Z + look.Z * back + rz * j)
					best:setPlan({ kind = "customer", act = "eat", spot = spot, face = vp, resume = best.plan }, now)
				end
			end
		end
	end
end

-- the player dancing on the street: one or two people nearby stop and film / cheer
local function danceTick(now: number, pp: Vector3)
	if now < ev.danceCheck then
		return
	end
	ev.danceCheck = now + 1
	if P.seat or now - ev.lastDance < 20 or P.speed > 1 then
		return
	end
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local ok, tracks = pcall(animator.GetPlayingAnimationTracks, animator)
	if not ok or type(tracks) ~= "table" then
		return
	end
	local dancing = false
	for _, tr in tracks do
		local okA, id = pcall(function()
			return tr.Animation and tr.Animation.AnimationId
		end)
		local name = tr.Name and string.lower(tr.Name) or ""
		if (okA and id and DANCE_IDS[id]) or string.find(name, "dance", 1, true) then
			dancing = true
			break
		end
	end
	if not dancing or Crowd.inClub(pp) then
		return
	end
	ev.lastDance = now
	local n = 0
	for _, a in agents do
		if n < 2 and not a.gone and a.dist < 15 and not a.clubGuest and not a.companion and a.mode ~= "talk" and a.mode ~= "dodge" and a.mode ~= "member" and not (a.plan and a.plan.kind == "queueing") then
			n += 1
			local yaw = yawOf(pp.X - a.pos.X, pp.Z - a.pos.Z)
			if a.sitting or a.sitGround then
				a:lookAtPoint(pp, 5, now)
				Anim.flash(a.rig, "clap", 2.5)
			else
				a:setPlan({ kind = "film", act = "photo", dur = 6 + rnd() * 4, faceYaw = yaw, resume = a.plan }, now)
				if rnd() < 0.4 then
					Anim.flash(a.rig, "clap", 1.8)
				end
			end
		end
	end
end

local stats = { frames = 0, cost = 0, worst = 0, moved = 0, spawned = 0, removed = 0, contacts = 0, dives = 0, sep = 0 }
Crowd.stats = stats
-------------------------------------------------------------------------------------------------
-- separation: nobody stands in / walks through somebody else (tick rate, close agents only)
-------------------------------------------------------------------------------------------------
local function separate(now: number)
	local n = #agents
	for i = 1, n do
		local a = agents[i]
		if a and a.dist < 60 and not a.gone then
			for j = i + 1, n do
				local b = agents[j]
				if b and b.dist < 60 and not b.gone and a.leader ~= b and b.leader ~= a and (a.leader == nil or a.leader ~= b.leader) then
					local dx, dz = (b.pos.X + b.nudgeX) - (a.pos.X + a.nudgeX), (b.pos.Z + b.nudgeZ) - (a.pos.Z + a.nudgeZ)
					local d2 = dx * dx + dz * dz
					if d2 < 2.9 then -- 1.7 studs
						stats.sep += 1
						local d = math.sqrt(d2)
						if d < 0.05 then
							dx, dz, d = rnd() - 0.5, rnd() - 0.5, 0.5
						end
						local ux, uz = dx / d, dz / d
						local push = 1.9 - d
						local aFixed = a.sitting or a.lying or a.sitGround or a.clubGuest or a.mode == "dodge" or (a.plan and a.plan.kind == "queueing")
						local bFixed = b.sitting or b.lying or b.sitGround or b.clubGuest or b.mode == "dodge" or (b.plan and b.plan.kind == "queueing")
						-- offsets add to the current one (a person keeps stepping until there is room)
						if a.mode == "walk" and not aFixed and (bFixed or b.mode ~= "walk") then
							a:nudge(a.nudgeX - ux * (push + 0.6), a.nudgeZ - uz * (push + 0.6), 1.4, 4)
						elseif b.mode == "walk" and not bFixed then
							b:nudge(b.nudgeX + ux * (push + 0.6), b.nudgeZ + uz * (push + 0.6), 1.4, 4)
						elseif not bFixed then
							b:nudge(b.nudgeX + ux * push, b.nudgeZ + uz * push, 0.6, 3)
						elseif not aFixed then
							a:nudge(a.nudgeX - ux * push, a.nudgeZ - uz * push, 0.6, 3)
						end
					end
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- tick: LOD, despawn, spawn, queue, companions
-------------------------------------------------------------------------------------------------
local candidates: { string } = {}
local candAt = -1e9
local lastTickPos: Vector3? = nil
local fillUntil = 0
local wasInside = false
local lastDebug = 0
local lastEvents = 0

local function updateLOD()
	local pp = P.pos
	if not pp then
		return
	end
	local camPos, look = camera()
	local near = tierVal(Config.Near)
	local mid = tierVal(Config.Mid)
	local offFreeze = tierVal(Config.OffFreeze)
	local gest = tierVal(Config.GestureDist)
	local farHz = tierVal(Config.FarHz)
	for _, a in agents do
		local d = flatDist(a.pos, pp)
		a.dist = d
		local on = onScreenPoint(a.pos, camPos, look, 0.3)
		a.onScreen = on
		local interval
		if d < near then
			interval = 0
		elseif d < mid then
			interval = 1 / Config.MidHz
		else
			interval = 1 / farHz
		end
		if not on and d > 25 then
			interval = math.max(interval, 1 / Config.OffHz)
		end
		if a.mode == "follow" or a.mode == "member" or a.mode == "dodge" then
			interval = if d < near then 0 else interval
		end
		if a.knock or a.chatState or a.chase then
			interval = 0 -- a fall / a walk-up / a chase must stay smooth
		end
		a.interval = interval
		a.near = d < gest and on
		-- tracks stop only for people nobody can see (off-screen and away from the player)
		Anim.freeze(a.rig, not on and d > offFreeze)
	end
end

local function tick()
	local now = os.clock()
	samplePlayer(now)
	local pp = P.pos
	if not pp then
		return
	end
	-- quick travel / respawn: refill around the new spot
	if lastTickPos and flatDist(lastTickPos, pp) > Config.TeleportJump then
		fillUntil = now + 3
		for i = #agents, 1, -1 do
			local a = agents[i]
			if a and not a.companion and not a.clubGuest and flatDist(a.pos, pp) > tierVal(Config.Despawn) * 0.8 then
				Crowd.remove(a)
			end
		end
	end
	lastTickPos = pp
	updateLOD()
	SocialUI.update(now)
	refreshCars()
	carReactions(now)
	lureTick(now)
	local clock = ctx.clock()
	local hype = Night.hype(clock)
	local clubD = Night.clubDistance(pp)
	-- the cap: the night shrink blends in with the distance from the club door; nobody outside
	-- while the player is inside CLUB OCEAN
	local base = tierVal(Config.Cap)
	local nightCap = Night.streetCap(base, hype, false)
	local nb = Config.NightBlend
	local k = math.clamp((clubD - nb[1]) / (nb[2] - nb[1]), 0, 1)
	local cap = math.floor(base + (nightCap - base) * k + 0.5)
	-- the drone show: the beach is full while it runs (the club crowd is hidden there anyway)
	if Crowd.droneLeft(now) and cap < base then
		local node = W.nearest(pp, 60)
		local area = node and ctx.Nav.AREA[W.area[node]]
		if area and BEACH_AREAS[area] then
			cap = base
		end
	end
	local inside = clubD < 320 and Crowd.inClub(pp)
	if inside then
		cap = 0
		for i = #agents, 1, -1 do
			local a = agents[i]
			if a and not a.companion and not a.clubGuest and not Crowd.inClub(a.pos) then
				Crowd.remove(a) -- behind the club's walls: nobody sees them go
			end
		end
	elseif wasInside then
		fillUntil = now + 3 -- back out on the street: the queue / forecourt fills at once
	end
	wasInside = inside
	Crowd.cap = cap
	-- despawn (on-screen people stay a little longer, then fade)
	local despawn = tierVal(Config.Despawn)
	for i = #agents, 1, -1 do
		local a = agents[i]
		if a then
			if a.done then
				if a.onScreen and a.dist < 70 and not a.fadeAt and a.plan and a.plan.kind == "leave" and not a.plan.door then
					Crowd.fadeOut(a, now)
				elseif not a.fadeAt then
					Crowd.remove(a)
				end
			elseif not a.companion and not a.leader and not a.clubGuest and not (a.ctl and a.ctl.keep and a.dist < despawn * 1.6) then
				if a.dist > despawn then
					if not a.onScreen then
						Crowd.remove(a)
					elseif a.dist > despawn * 1.3 then
						Crowd.fadeOut(a, now)
					end
				elseif a.plan and a.plan.kind == "leave" and (a.dist > despawn * 0.75 or (not a.onScreen and a.dist > 35)) then
					if a.onScreen then
						Crowd.fadeOut(a, now)
					else
						Crowd.remove(a)
					end
				end
			end
		end
	end
	-- companions
	syncCompanions(now)
	-- queue
	Q.tick(now, hype)
	-- pedestrians keep apart
	separate(now)
	-- events (drone show, busker, vendors) every 2 s; the dancing player every 1 s
	if not inside then
		if now - lastEvents >= 2 then
			lastEvents = now
			eventsTick(now, pp, cap)
		end
		danceTick(now, pp)
	end
	-- spawn / trim
	local count = streetCount()
	local fill = now < fillUntil
	if count < cap then
		local budget = if fill then Config.FillPerTick else Config.SpawnPerTick
		if Citizens and now - candAt > Config.CandidateEvery then
			candAt = now
			local exclude = {}
			for id in byId do
				exclude[id] = true
			end
			for id, t in recent do
				if now - t < 25 then
					exclude[id] = true
				else
					recent[id] = nil
				end
			end
			local ok, list = pcall(Citizens.candidates, pp, clock, W.areaPos, 14, tierVal(Config.SpawnMax) + 40, exclude)
			candidates = if ok and type(list) == "table" then list else {}
		end
		-- the mix around the player: too many walkers -> the next one does something at a spot;
		-- a few sunbathers on the towels by day
		local nearN, walkN, sunN = 0, 0, 0
		for _, a in agents do
			if not a.companion and not a.clubGuest and a.dist < 70 then
				nearN += 1
				if a.mode == "walk" or a.mode == "wait" or (a.mode == "member" and a.speed > 0.5) then
					walkN += 1
				end
			end
			if a.idleKind == "sunbathe" or (a.plan and a.plan.act == "sunbathe") then
				sunN += 1
			end
		end
		local stationary = (nearN >= 3 and walkN / nearN > Config.WalkShareMax) or (nearN < 3 and rnd() < 0.5)
		local sun = clock >= 9 and clock < 18 and sunN < Config.SunbathersMin and hype < 0.2
		local tries = 0
		while budget > 0 and count < cap and tries < 6 do
			tries += 1
			local a = nil
			-- named people first (keep ~1/3 of the crowd for passers-by so groups / queues still happen)
			local namedN = 0
			for _, x in agents do
				if x.named and not x.clubGuest then
					namedN += 1
				end
			end
			if not sun and #candidates > 0 and namedN < math.max(3, math.ceil(cap * 0.55)) and not (stationary and rnd() < 0.6) then
				local id = table.remove(candidates, 1)
				if id and not byId[id] then
					a = spawnNamed(id, pp, fill, now)
				end
			end
			if not a then
				a = spawnExtra(pp, fill, now, cap - count, { stationary = stationary, sun = sun })
				if a and sun and a.idleKind == "sunbathe" then
					sun = false
				end
			end
			if a then
				budget -= 1 + #a.members
				stats.spawned += 1 + #a.members
				count = streetCount()
				if a.mode ~= "walk" then
					stationary = false
				end
			end
		end
	else
		-- too many (night falls away from the club / tier dropped): people behind the player and
		-- off-screen go first; a group goes as a whole (scored by its leader). People already
		-- walking away / fading out do not count.
		local going = 0
		for _, a in agents do
			if not a.companion and not a.clubGuest and (a.fadeAt or (a.plan and a.plan.kind == "leave")) then
				going += 1 + #a.members
			end
		end
		local mvx, mvz = 0, 0
		if P.speed > 3 then
			mvx, mvz = P.vel.X / P.speed, P.vel.Z / P.speed
		end
		local over = count - going - cap
		for _ = 1, math.clamp(over, 0, 3) do
			local worst, wd = nil, -math.huge
			for _, a in agents do
				if not a.companion and not a.leader and not a.gone and not a.clubGuest and not a.fadeAt and not (a.plan and a.plan.kind == "leave" and a.onScreen) then
					local behind = ((a.pos.X - pp.X) * mvx + (a.pos.Z - pp.Z) * mvz) < 0
					local score = a.dist + (if a.named then -40 else 0) + (if a.onScreen then 0 else 60) + (if behind then 40 else 0)
					if score > wd then
						worst, wd = a, score
					end
				end
			end
			if not worst then
				break
			end
			Crowd.retire(worst, now)
		end
	end
	-- debug
	if workspace:GetAttribute("GwangalliStreetLifeDebug") == true and now - lastDebug >= Config.DebugEvery then
		lastDebug = now
		local modes = {}
		local moving, named = 0, 0
		for _, a in agents do
			modes[a.mode] = (modes[a.mode] or 0) + 1
			if a.speed > 0.5 then
				moving += 1
			end
			if a.named then
				named += 1
			end
		end
		local ms = {}
		for kk, v in modes do
			table.insert(ms, kk .. "=" .. v)
		end
		table.sort(ms)
		local built, reused, spare, restyled = Pool.stats()
		print(string.format("[StreetLife] clock=%.2f hype=%.2f cap=%d n=%d named=%d moving=%d queue=%d %s | frame avg %.3f ms worst %.3f ms | moved/frame %.1f | pool built %d reused %d restyled %d spare %d | flows pending %d | cars %d contacts %d dives %d sep %d inside %s", clock, hype, cap, #agents, named, moving, Q.count(), table.concat(ms, " "), if stats.frames > 0 then stats.cost / stats.frames * 1000 else 0, stats.worst * 1000, if stats.frames > 0 then stats.moved / stats.frames else 0, built, reused, restyled or 0, spare, W.flowsPending(), #cars, stats.contacts, stats.dives, stats.sep, tostring(inside)))
		local cc = ctx.ClubCrowd and ctx.ClubCrowd.stats
		if cc then
			print(string.format("[StreetLifeClub] hype=%.2f target=%d visible=%d hidden=%d guests=%d named=%d atClub=%s staffHidden=%d", hype, cc.target, cc.visible, cc.hidden, cc.guests, cc.named or 0, tostring(cc.atClub), cc.staffHidden or 0))
		end
		-- id:x:z:mode:speed:y:yaw:pose:rigKey:plan (pose = idle kind / sit / lie / walk)
		local pos = {}
		for _, a in agents do
			local pose = if a.lying then "lie" elseif a.sitGround then "gsit" elseif a.sitting then "sit" elseif a.mode == "idle" then (a.idleKind or "idle") else a.mode
			local st = a.rig.anim
			if st and st.pose and pose ~= "lie" then
				pose = pose .. "+" .. st.pose
			end
			table.insert(pos, string.format("%s:%.1f:%.1f:%s:%.1f:%.2f:%.2f:%s:%s:%s:%s:%.1f,%.1f", a.id, a.pos.X + a.nudgeX, a.pos.Z + a.nudgeZ, a.mode, a.speed, a.pos.Y, a.yaw, pose, a.rig.key or "?", a.plan and a.plan.kind or "-", a.leader and a.leader.id or "", a.nudgeX, a.nudgeZ))
		end
		print("[StreetLifePos] " .. table.concat(pos, ";"))
		stats.frames, stats.cost, stats.worst, stats.moved = 0, 0, 0, 0
	end
end

-------------------------------------------------------------------------------------------------
-- per-frame update
-------------------------------------------------------------------------------------------------
local moveParts: { BasePart } = {}
local moveCFs: { CFrame } = {}
local lastN = 0

local function update(dt: number)
	local t0 = os.clock()
	local now = t0
	W.stepFlows(if Quality and Quality.get() == "low" then 180 else 350)
	samplePlayer(now)
	local pp = P.pos
	local camPos, look = camera()
	local offFreeze = tierVal(Config.OffFreeze)
	local seated = P.seat ~= nil
	local carFast = seated and P.speed > 10
	local contact = Config.ContactDist
	-- the car's body this frame (refreshCars: P.body); lz below is measured toward its leading end
	-- (-Z is its front; reversing: the back)
	local body = P.body
	local bodyCF: CFrame? = nil
	local bodyHX, bodyHZ, bodyFZ, bodyReach = 0, 0, -1, 0
	if seated and pp and body and body.Parent and P.speed > (Config.CarCrawl or 3) then
		local cf = body.CFrame
		local sz = body.Size
		bodyCF = cf
		bodyHX, bodyHZ = sz.X / 2, sz.Z / 2
		bodyFZ = if cf:VectorToObjectSpace(P.vel).Z > 0 then 1 else -1
		local ox, oz = cf.Position.X - pp.X, cf.Position.Z - pp.Z
		bodyReach = math.sqrt(ox * ox + oz * oz) + math.sqrt(bodyHX * bodyHX + bodyHZ * bodyHZ) + 3.5
	end
	local n = 0
	local i = 1
	while i <= #agents do
		local a = agents[i]
		i += 1
		if a and not a.gone then
			a.acc += dt
			if a.acc >= a.interval then
				local sdt = math.min(a.acc, 0.5)
				a.acc = 0
				a:step(sdt, now)
				if a.moved then
					a.moved = false
					n += 1
					moveParts[n] = a.root
					moveCFs[n] = a:computeCFrame()
				end
			end
			local st = a.rig.anim
			-- a frozen (off-screen) agent that came into view starts its loop at once
			if st and st.frozen and onScreenPoint(a.pos, camPos, look, 0.3) then
				a.onScreen = true
				Anim.freeze(a.rig, false)
			elseif st and not st.frozen and not a.onScreen and a.dist > offFreeze then
				-- (updateLOD freezes it at the next tick)
			end
			if a.near then
				if st and not st.frozen then
					Anim.step(a.rig, dt)
					if a.rig.dogLegs then
						Anim.dogStep(a.rig, dt, a.speed)
					end
				end
			end
			-- contact: the player (or the player's car) is right here
			if pp and a.dist < (if carFast then 45 else 30) and not a.clubGuest and not a.companion then
				local dx, dz = a.pos.X - pp.X, a.pos.Z - pp.Z
				local d = math.sqrt(dx * dx + dz * dz)
				a.dist = d
				-- against the body box: touching = in it, at its side or just ahead of the leading end;
				-- close = a step more (the last-moment dive)
				local touch, close = false, false
				if bodyCF and d < bodyReach then
					local lp = bodyCF:PointToObjectSpace(Vector3.new(a.pos.X, bodyCF.Position.Y, a.pos.Z))
					local lx, lz = math.abs(lp.X), lp.Z * bodyFZ
					touch = lx <= bodyHX + 0.5 and lz >= -bodyHZ and lz <= bodyHZ + 0.8
					close = lx <= bodyHX + 1.5 and lz >= -bodyHZ and lz <= bodyHZ + 3
				end
				if carFast then
					if (d < 4.5 or close) and a.mode ~= "dodge" and not a.knock and math.abs(a.pos.Y - pp.Y) < 8 then
						local sp = P.speed
						local ux, uz = P.vel.X / sp, P.vel.Z / sp
						-- (the contact is the car's body; with no body box: its front, a little ahead of the
						-- driver's seat)
						local bx, bz = dx - ux * 2.5, dz - uz * 2.5
						local hitNow = if bodyCF then touch else math.min(d, math.sqrt(bx * bx + bz * bz)) < 3.8
						-- (one who failed to get out of the way does not dive at the last moment either)
						local doomed = P.drive and a.willBeHit and now - (a.willBeHitT or -1e9) < 4
						if doomed and hitNow and now - (a.carHitAt or -1e9) > 3 then
							-- hit by the player's car: the fall right here (the server decides the rest)
							a.carHitAt = now
							a.carHitSp = sp
							a.willBeHit = false
							if Crowd.fightKnock(a, ux, uz, if sp < 15 then "stagger" elseif sp < 35 then "knockdown" else "thrown", if sp > 35 then "쾅!!" else "퍽!", sp) then
								a.carKnock = true
								Crowd.carHit(a, sp)
							end
						elseif not doomed then
							local px, pz = -P.vel.Z / sp, P.vel.X / sp
							local s = if (dx * px + dz * pz) >= 0 then 1 else -1
							a.dodgeLocal = P.drive == true
							a:dive(now, px * s, pz * s, pp)
						end
					end
				elseif seated and P.drive and P.speed > (Config.CarCrawl or 3) then
					-- crawling at the wheel (3-10 studs/s): a touch staggers them (the server: a light
					-- hit from 5 studs/s on)
					if (touch or d < 3.4) and a.mode ~= "dodge" and not a.knock and math.abs(a.pos.Y - pp.Y) < 6 and now - (a.carHitAt or -1e9) > 3 then
						local sp = P.speed
						local ux, uz = P.vel.X / sp, P.vel.Z / sp
						if (if bodyCF then touch else dx * ux + dz * uz > -0.5) then
							a.carHitAt = now
							a.carHitSp = sp
							a.willBeHit = false
							if Crowd.fightKnock(a, ux, uz, "stagger", "툭!") then
								a.carKnock = true
								Crowd.carHit(a, sp)
							end
						end
					end
				elseif not seated and d < contact and math.abs(a.pos.Y - pp.Y) < 6 then
					if now - a.bumpAt >= Config.BumpCooldown then
						stats.contacts += 1
					end
					a:bump(now, pp)
				end
			end
			-- fading out (somebody the player could see leaving)
			if a.fadeAt then
				local kf = (now - a.fadeAt) / 0.5
				if kf >= 1 then
					Crowd.remove(a)
					i -= 1
				else
					setFade(a, kf)
				end
			elseif now >= a.nextThink then
				a.nextThink = now + (if a.near or a.chase then 0.2 else 0.9) + rnd() * 0.1
				a:think(now)
			end
		end
	end
	for k = n + 1, lastN do
		moveParts[k] = nil
		moveCFs[k] = nil
	end
	lastN = n
	if n > 0 then
		workspace:BulkMoveTo(moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local cost = os.clock() - t0
	stats.frames += 1
	stats.cost += cost
	stats.moved += n
	if cost > stats.worst then
		stats.worst = cost
	end
end

-------------------------------------------------------------------------------------------------
-- 길거리 싸움 (GwangalliFight): KO (down for good, then taken away), the brawl (an NPC that fights
-- back swings several times; every swing that lands goes to the server as "npcHit"), and the
-- reaction after the hit (flee / report / arrest) once they are back on their feet
-------------------------------------------------------------------------------------------------
local FS: any = nil
local fightRemote: RemoteEvent? = nil
local function fightAction(): RemoteEvent?
	if fightRemote and fightRemote.Parent then
		return fightRemote
	end
	local f = ReplicatedStorage:FindFirstChild("GwangalliFight")
	local a = f and f:FindFirstChild("Action")
	fightRemote = if a and a:IsA("RemoteEvent") then a else nil
	return fightRemote
end

-- a short pose TRACK ("GwPose_<name>": punch / shove / fight ...): renderers that only show tracks
-- (not procedural joint poses) still see the swing; real Roblox plays nothing for an empty id
local poseAnims: { [string]: Animation } = {}
local function playPose(a: any, name: string, dur: number)
	local model = a.rig and a.rig.model
	local animator = model and model:FindFirstChildWhichIsA("Animator", true)
	if not animator then
		return
	end
	local anim = poseAnims[name]
	if not anim then
		anim = Instance.new("Animation")
		anim.Name = "GwPose_" .. name
		poseAnims[name] = anim
	end
	pcall(function()
		local tr = (animator :: Animator):LoadAnimation(anim)
		tr.Name = "GwPose_" .. name
		tr:Play(0.08)
		task.delay(dur, function()
			pcall(function()
				tr:Stop(0.15)
				tr:Destroy()
			end)
		end)
	end)
end

Crowd.playPose = playPose -- (GwangalliStreetLife/Mind: the shove / punch of an NPC-vs-NPC scuffle)

local function fpick(list: { string }?): string?
	if not list or #list == 0 then
		return nil
	end
	return list[1 + math.floor(rnd() * #list)]
end

-- a hit pushes the body back: one ray at chest height, the slide stops a stud short of a wall / a car /
-- a pole (no physics: a.pos slides during the fall, Agent.stepKnock below)
local slideParams: RaycastParams? = nil
local function slideRoom(a: any, dx: number, dz: number, dist: number): number
	local okR, room = pcall(function()
		local prm = slideParams or RaycastParams.new()
		slideParams = prm
		prm.FilterType = Enum.RaycastFilterType.Exclude
		local ex = {}
		local f = workspace:FindFirstChild("GwangalliStreetLife")
		if f then
			table.insert(ex, f)
		end
		local ch = player.Character
		if ch then
			table.insert(ex, ch)
		end
		prm.FilterDescendantsInstances = ex
		local hit = workspace:Raycast(Vector3.new(a.pos.X, a.pos.Y + 2.2, a.pos.Z), Vector3.new(dx, 0, dz) * (dist + 1.2), prm)
		return if hit then math.max(0, hit.Distance - 1.2) else dist
	end)
	return if okR and type(room) == "number" then room else 0
end

-- hop = studs the body leaves the ground mid-slide (a car throws them: an arc, back down at the end)
local function startSlide(a: any, dx: number, dz: number, dist: number, dur: number, hop: number?)
	local kn = a.knock
	local m = math.sqrt(dx * dx + dz * dz)
	if not kn or dist <= 0 or m < 1e-3 then
		return
	end
	dx, dz = dx / m, dz / m
	local room = slideRoom(a, dx, dz, dist)
	if room > 0.1 then
		-- (a new slide mid-arc keeps the ground they were thrown from)
		local y0 = if kn.slide and kn.slide.y0 then kn.slide.y0 else a.pos.Y
		kn.slide = { dx = dx, dz = dz, dist = room, done = 0, t0 = os.clock(), dur = dur, hop = hop, y0 = y0 }
	end
end

-- the fall's u (0..1 of FALL_DUR) at which BumpShared.knockPhase's fall reaches tilt k
local function fallU(k: number): number
	local want = math.sqrt(math.clamp(k, 0, 1))
	local lo, hi = 0, 1
	for _ = 1, 12 do
		local u = (lo + hi) * 0.5
		if u * u * (3 - 2 * u) < want then
			lo = u
		else
			hi = u
		end
	end
	return (lo + hi) * 0.5
end

-- a hit that landed on this pedestrian (GwangalliFight "knock", the talk card, a car): "stagger" (a jolt
-- and a step back), "knockdown" (falls, gets up), "thrown" (falls and slides a few studs, held down a
-- moment longer). A hit while the last one still plays is not lost (a fast combo): a fresh jolt from the
-- lean they are at, a stagger becomes a fall, somebody getting up goes down again, a body on the ground
-- stays down a little longer
-- carSp = a car's speed (thrown: farther the faster, through the air a moment, longer on the ground)
function Crowd.fightKnock(a: any, dx: number, dz: number, outcome: string, puk: string?, carSp: number?): boolean
	local B = ctx.BumpShared
	if not B or a.gone then
		return false
	end
	local want = if outcome == "knockdown" or outcome == "thrown" then "knockdown" else "stagger"
	local kn = a.knock
	local now = os.clock()
	if kn and not a.ko then
		local function pukSay()
			if puk and a.rig.root and B.bubbles then
				local pool = B.bubbles({ types = ctx.Social and ctx.Social.TYPES })
				if pool then
					pool:say(a.rig.root, puk, "plain", 1.2, 2.1 * (a.scale or 1) + 1.6)
				end
			end
		end
		if want == "knockdown" and kn.outcome == "stagger" then
			a.knock = nil -- staggering from the last hit: this one puts them down (below)
		elseif kn.outcome == "stagger" then
			-- hit again mid-stagger: the jolt starts over from the lean they are at (no snap upright)
			local k = math.clamp(kn.k or 0, 0, 1)
			kn.t0 = now - (math.asin(k) / math.pi) * B.STAGGER_DUR
			if k < 0.3 then
				kn.dx, kn.dz = dx, dz
			end
			kn.phase = ""
			Anim.setRestPose(a.rig, "stagger")
			pukSay()
			startSlide(a, dx, dz, 0.6, 0.3)
			return true
		elseif kn.phase == "getup" then
			-- hit while getting up: down again, from the tilt they are at
			kn.t0 = now - fallU(kn.k or 0) * B.FALL_DUR
			kn.phase = ""
			Anim.setRestPose(a.rig, "knock")
			pukSay()
			return true
		else
			-- on the ground: kept down a little longer
			kn.t0 = math.max(kn.t0, now - B.FALL_DUR - 0.05)
			return true
		end
	end
	if a:knockDown(dx, dz, want, puk) == false or not a.knock then
		return false
	end
	if outcome == "thrown" and carSp and carSp > 35 then
		-- hit by a fast car: thrown along the car (an arc through the air, a scripted slide - no physics),
		-- then a while on the ground
		local over = carSp - 35
		startSlide(a, dx, dz, math.clamp(5 + over * 0.15, 5, 11) + rnd() * 1.5, 0.6 + math.min(0.25, over * 0.01), math.min(1.6, 0.8 + over * 0.03) * (a.scale or 1))
		a.knock.extra = 1.2 + math.min(1.8, over / 20)
	elseif outcome == "thrown" then
		-- knocked off the feet: a slide along the hit while falling, then a second longer on the ground
		startSlide(a, dx, dz, 5 + rnd() * 3, 0.55)
		a.knock.extra = 1.0
	else
		startSlide(a, dx, dz, if want == "knockdown" then 1.2 else 0.8, if want == "knockdown" then 0.4 else 0.3)
	end
	return true
end

-- the player's car hit this pedestrian (Agent already fell): the server weighs it (speed, the car)
function Crowd.carHit(a: any, speed: number)
	local fr = fightAction()
	if fr then
		fr:FireServer("carHit", { id = a.id, speed = speed, pos = { a.pos.X, a.pos.Y, a.pos.Z }, ptype = a.type, sn = a.sn })
	end
end

function Crowd.playReact(a: any)
	local kind = a.pendingReact
	a.pendingReact = nil
	local M = ctx.Mind
	local pp = P.pos
	if not M or not kind or a.gone then
		return
	end
	if kind == "warn" and pp then
		-- squares up: looks at you, points, stays put a moment (the line came with the hit)
		a:lookAtPoint(pp + Vector3.new(0, 1.6, 0), 4, os.clock())
		Anim.flash(a.rig, "point", 1.2)
		a.want, a.speed = 0, 0
		a.pauseUntil = os.clock() + 2.5
	elseif kind == "cower" and pp then
		-- gives up: hands up / crouched a few seconds, then gets away
		playPose(a, "cower", 3)
		a.want, a.speed = 0, 0
		a.pauseUntil = os.clock() + 3
		task.delay(3, function()
			if not a.gone and not a.knock and not a.ko and M.flee then
				local p2 = P.pos
				if p2 then
					pcall(M.flee, a, p2, 7)
				end
			end
		end)
	elseif kind == "flee" and pp and M.flee then
		pcall(M.flee, a, pp, 6 + rnd() * 3)
	elseif kind == "report" and M.report then
		pcall(M.report, a)
	elseif kind == "arrest" and M.policeEncounter then
		pcall(M.policeEncounter, a, true)
	end
end

local function installFightHooks()
	local okF, fsm = pcall(function()
		return require(ReplicatedStorage:FindFirstChild("GwangalliFightShared") :: any)
	end)
	FS = if okF then fsm else nil
	local Bump = ctx.BumpShared
	local knockedAttr = (Bump and Bump.Attr and Bump.Attr.Knocked) or "GwangalliKnocked"
	-- a kick (brawl swing): the right leg up, the arms out for balance (a procedural flash pose)
	if Anim.POSES and Anim.POSES.kick == nil then
		local R = math.rad
		Anim.POSES.kick = {
			RightHip = CFrame.Angles(R(80), 0, 0),
			RightKnee = CFrame.Angles(R(-18), 0, 0),
			LeftHip = CFrame.Angles(R(-8), 0, 0),
			Waist = CFrame.Angles(R(-10), 0, 0),
			RightShoulder = CFrame.Angles(R(30), 0, R(40)),
			LeftShoulder = CFrame.Angles(R(30), 0, R(-40)),
		}
	end
	local baseStepKnock = Agent.stepKnock
	Agent.stepKnock = function(self: any, dt: number, now: number)
		local ko = self.ko
		local kn = self.knock
		if kn then
			-- pushed back by the hit (a step; thrown: a few studs while falling), eased out
			local sl = kn.slide
			if sl then
				local u = math.clamp((now - sl.t0) / math.max(0.05, sl.dur), 0, 1)
				local d = sl.dist * (1 - (1 - u) * (1 - u))
				local step = d - sl.done
				-- (thrown: up and back down on the ground it left)
				local y = if sl.hop then sl.y0 + math.sin(u * math.pi) * sl.hop else (sl.y0 or self.pos.Y)
				if step > 0 or y ~= self.pos.Y then
					self.pos = Vector3.new(self.pos.X + sl.dx * math.max(0, step), y, self.pos.Z + sl.dz * math.max(0, step))
					sl.done = math.max(sl.done, d)
				end
				if u >= 1 then
					kn.slide = nil
				end
			end
			-- thrown: held on the ground a moment longer before the get-up
			local extra = kn.extra
			if extra and extra > 0 and not ko then
				local over = now - kn.t0 - (((Bump and Bump.KNOCK_DUR) or 1.4) - 0.2)
				if over > 0 then
					local e = math.min(extra, over)
					kn.t0 += e
					kn.extra = extra - e
				end
			end
		end
		if ko and kn then
			-- KO: the timeline is held lying down (never the get-up) until they are taken away
			local hold = ((Bump and Bump.KNOCK_DUR) or 2.4) - 0.15
			if now - kn.t0 > hold then
				kn.t0 = now - hold
			end
			if now >= ko.untilT and not self.fadeAt then
				Crowd.fadeOut(self, now)
			end
		end
		return baseStepKnock(self, dt, now)
	end
	-- a KO'd body stays "lying" (Agent:endIdle resets the flag while it is down): no talk prompt
	-- (SocialUI filters a.lying), no emotes, the 어깨빵 / car passes skip it
	local baseThink = Agent.think
	Agent.think = function(self: any, now: number)
		baseThink(self, now)
		if self.ko and not self.gone then
			self.lying = true
		end
	end
	-- walking into someone (the contact pass): who they are decides the line and what follows
	-- (Characters.bumped); the base nudge / startle stay, its quip is swapped
	local baseBump = Agent.bump
	local baseQuip = Agent.quip
	Agent.quip = function(self: any, kind: string, chance: number)
		if kind == "bump" and self.quietBump then
			return
		end
		return baseQuip(self, kind, chance)
	end
	Agent.bump = function(self: any, now: number, pp: Vector3)
		local CH = Crowd.Characters
		local bk = nil
		if CH and CH.bumpKind and not self.knock and now - self.bumpAt >= Config.BumpCooldown and self.mode ~= "dodge" and self.mode ~= "talk" then
			local okK, k = pcall(CH.bumpKind, self)
			bk = if okK then k else nil
		end
		if bk == "drunk" and self.type ~= "drunk" and CH.drunkBump then
			-- a named citizen in the DRUNK mood: sways into you like a drunk (then may pick a quarrel)
			local prevAt = self.bumpAt
			self.bumpAt = now
			local okD, did = pcall(CH.drunkBump, self, pp)
			if okD and did then
				return
			end
			self.bumpAt = prevAt
		end
		local before = self.bumpAt
		self.quietBump = bk ~= nil and bk ~= "violent" and bk ~= "drunk" and bk ~= "normal"
		local okB, errB = pcall(baseBump, self, now, pp)
		self.quietBump = nil
		if not okB then
			error(errB, 0)
		end
		if self.bumpAt == now and before ~= now and not self.gone then
			if self.type == "drunk" then
				self.playerBumpAt = now -- (the base drunk branch: a stagger for both; the get-up decides)
			elseif bk and bk ~= "drunk" and bk ~= "normal" and not self.knock then
				pcall(CH.bumped, self, "walk", bk, now)
			end
		end
	end
	local baseAfter = Agent.afterKnock
	Agent.afterKnock = function(self: any, now: number)
		if self.ko then
			return
		end
		local kn = self.knock -- (the base clears it)
		local by = kn and kn.byNpc
		if by and not kn.byPlayer and not self.brawl and not self.pendingReact then
			-- another pedestrian put them off balance (a scuffle round, the 동네바보 / a drunk walking into
			-- them, a shove): back up facing THAT one - not the base reaction (it turns to the player, says
			-- a line at the player, and a violent one runs after the player who did nothing)
			self.knock = nil
			self.chase = nil
			self.carKnock, self.playerBumpAt = nil, nil
			Anim.setRestPose(self.rig, nil)
			local face = if not by.gone then yawOf(by.pos.X - self.pos.X, by.pos.Z - self.pos.Z) else self.yaw
			if self.ctl and ctx.Mind and ctx.Mind.hold then
				-- (in a scene / held by the mind: stays put, facing the other one)
				ctx.Mind.hold(self, by.pos, "")
				return
			end
			self.node = W.nearest(self.pos, 40)
			self.prev = nil
			self.lookUntil = math.max(self.lookUntil or 0, now + 2.5)
			local CH = Crowd.Characters
			if kn.bump and not by.gone and CH and CH.npcBumped then
				-- walked into: who they are decides it (a word, a glare, an argument that may turn into a fight)
				local okB, started = pcall(CH.npcBumped, self, by, now)
				if okB and started then
					return
				end
			end
			self:idleFor("idle", 1.4 + rnd(), now, face)
			return
		end
		local hitT = self.carHitAt
		local byCar = self.carKnock == true and hitT ~= nil and now - hitT < 8
		self.carKnock = nil
		-- the player's 어깨빵 (no punch reaction waiting): the personality reaction
		local CH = Crowd.Characters
		local bk = nil
		if not byCar and CH and CH.bumpKind and not self.brawl and not self.pendingReact and ((kn and kn.byPlayer) or now - (self.playerBumpAt or -1e9) < 5) then
			local okK, k = pcall(CH.bumpKind, self)
			bk = if okK then k else nil
		end
		self.playerBumpAt = nil
		if bk and not byCar then
			local okL, line = pcall(CH.bumpLine, self, bk, kn ~= nil and kn.outcome == "knockdown")
			if okL and line ~= nil then
				local prevTL = rawget(self, "typeLine")
				self.typeLine = function(s2: any, kind: string): string?
					if kind == "bumped" or kind == "down" or kind == "mumble" then
						return if line == "" then nil else line
					end
					return if prevTL then prevTL(s2, kind) else Agent.typeLine(s2, kind)
				end
				local okA, errA = pcall(baseAfter, self, now)
				self.typeLine = prevTL
				if not okA then
					error(errA, 0)
				end
			else
				baseAfter(self, now)
			end
		elseif byCar then
			-- back up after the player's car hit them: a car line, not a 어깨빵 one ("조심 좀 하세요!" /
			-- the fool's "더 세게!"), and none when the server's line (GwangalliFight) was said already
			local said = (self.lastSayAt or -1e9) > hitT
			local bank = if kn and kn.outcome == "knockdown" then "car_hurt" else "car_warn"
			local prevTL = rawget(self, "typeLine")
			self.typeLine = function(s2: any, kind: string): string?
				if kind == "bumped" or kind == "down" or kind == "beg" or kind == "mumble" then
					return if said then nil else fpick(FS and FS.LINES and FS.LINES[bank])
				end
				return if prevTL then prevTL(s2, kind) else Agent.typeLine(s2, kind)
			end
			local okA, errA = pcall(baseAfter, self, now)
			self.typeLine = prevTL
			if not okA then
				error(errA, 0)
			end
		else
			baseAfter(self, now)
		end
		if self.gone then
			return
		end
		if byCar and not self.brawl then
			if kn and kn.outcome == "knockdown" and not self.hurt then
				-- hurt (a car put them on the ground): they limp on slower a while, sit on the kerb a moment
				local mult = (Bump and Bump.SLOW_MULT) or 0.55
				local h = { walk = self.walkSpeed, wob = self.wobble == nil }
				self.hurt = h
				self.walkSpeed = self.walkSpeed * mult
				if h.wob then
					self.wobble = 0.18 -- (a limp: the Agent's sideways drift while walking)
				end
				if not self.pendingReact and not self.chase then
					self:idleFor("groundsit", 3 + rnd() * 2, now, self.faceYaw)
				end
				task.delay(if (self.carHitSp or 0) > 35 then 30 else 20, function()
					if self.hurt == h and not self.gone then
						self.hurt = nil
						if math.abs(self.walkSpeed - h.walk * mult) < 0.01 then
							self.walkSpeed = h.walk -- (a type change since keeps its own speed)
						end
						if h.wob and self.wobble == 0.18 then
							self.wobble = nil
						end
					end
				end)
			elseif not self.pendingReact and not self.chase then
				-- only bumped: startled (the base flash), then angry at the driver (look, point, a beat)
				self.pendingReact = "warn"
			end
		end
		local b = self.brawl
		if b and now < b.untilT then
			local pp = P.pos
			if pp and not self.chase then
				self:startChase(now, pp)
			end
		else
			if b then
				self.brawl = nil -- (over while they were down)
				if self.type ~= "drunk" and self.type ~= "fool" then
					self.wobble = nil
				end
			end
			if self.pendingReact then
				Crowd.playReact(self)
			elseif bk and not self.gone then
				pcall(CH.bumped, self, "knock", bk, now)
			end
		end
	end
	-- jumped out of the way of the player's car (a near miss, Agent:dive): the base glare + startle + the
	-- angry car line stay; then who they are decides what follows - a hothead points and remembers the
	-- driver (and may have words once the player is out of the car), a timid one cowers, others only
	-- remember it now and then (the street memory: the glare / "또 너냐?" when the player walks up later)
	local baseAfterDodge = Agent.afterDodge
	Agent.afterDodge = function(self: any, now: number)
		local mine = self.dodgeLocal
		self.dodgeLocal = nil
		baseAfterDodge(self, now)
		if not mine or self.gone or self.ctl or not self.id or self.knock then
			return
		end
		local M = ctx.Mind
		local CH = Crowd.Characters
		local okP, p = false, nil
		if CH and CH.persOf then
			okP, p = pcall(CH.persOf, self)
		end
		if not okP or type(p) ~= "table" then
			return
		end
		local c = self.dodgeFrom or self.pos
		if p.violent or self.type == "punk" or self.type == "thug" then
			self:lookAtPoint(c + Vector3.new(0, 1.6, 0), 3, now)
			Anim.flash(self.rig, "point", 1.2)
			if M and M.face then
				M.face(self, "angry", 3)
			end
			Crowd.api("remember", self.id, "anger", 2)
			if M and M.startQuarrel and rnd() < 0.35 then
				-- (has words with the driver once he is out of the car close by; drives on = it is over)
				local tries = 0
				local function tryQuarrel()
					tries += 1
					local pp = P.pos
					if self.gone or self.ctl or self.knock or self.chase or self.quarrel or not pp or flatDist(pp, self.pos) > 30 then
						return
					end
					if Crowd.playerSeated() then
						if tries < 8 then
							task.delay(1.5, tryQuarrel)
						end
						return
					end
					if flatDist(pp, self.pos) < 18 then
						M.startQuarrel(self, { start = { "야! 아까 그 차 너지?!", "운전 그따위로 할 거야?" }, follow = { "사람 죽일 뻔했잖아!", "운전 좀 똑바로 해!" }, calm = { "에휴… 조심 좀 해라." } }, { secs = 9, noShove = true })
					end
				end
				task.delay(2.5, tryQuarrel)
			end
		elseif p.isTimid or p.fearful then
			if M and M.face then
				M.face(self, "scared", 3)
			end
			playPose(self, "cower", 1.4)
			Crowd.api("remember", self.id, "fear", 1)
		elseif rnd() < 0.4 then
			Crowd.api("remember", self.id, "anger", 1)
		end
	end
	local baseChase = Agent.chaseTick
	Agent.chaseTick = function(self: any, now: number)
		local q = self.quarrel
		if q and not self.brawl then
			-- 취객 시비: slow, swaying, a line every few seconds, a shove when he catches you
			local chs = self.chase
			local pp = P.pos
			if not chs or not pp or now > q.untilT or Crowd.playerSeated() then
				self.quarrel = nil
				local l = fpick(q.lines and q.lines.calm)
				if l then
					SocialUI.say(self, l, 3)
				end
				if chs then
					self:endChase(now, true)
				end
				return
			end
			chs.untilT = math.max(chs.untilT, q.untilT)
			local dx, dz = pp.X - self.pos.X, pp.Z - self.pos.Z
			local d = math.sqrt(dx * dx + dz * dz)
			-- you walked off (farther than when it started, by a margin): he gives up
			q.giveUp = q.giveUp or math.max(24, d + 10)
			if d < q.giveUp - 10 then
				q.giveUp = math.max(24, d + 10)
			end
			if d > q.giveUp or math.abs(pp.Y - self.pos.Y) > 6 then
				q.untilT = now
				return
			end
			if now >= q.nextLine then
				q.nextLine = now + 3 + rnd() * 1.5
				local l = fpick(q.lines and q.lines.follow)
				if l then
					SocialUI.say(self, l, 2.8)
				end
			end
			if d < (q.keep or 2.8) then
				self.want, self.speed = 0, 0
				if now >= q.nextShove then
					q.nextShove = now + 5 + rnd() * 2
					Anim.flash(self.rig, "pointp", 0.5)
					playPose(self, "shove", 0.6)
					self:hitPlayer(dx / math.max(d, 0.05), dz / math.max(d, 0.05), "stagger", fpick(q.lines and q.lines.shove))
				end
				return
			end
			if now >= chs.retarget or self.mode ~= "walk" then
				self:chaseStep(now, pp)
			end
			self.want = math.min(self.want or 0, 6.5) -- a drunk does not sprint
			self:updateWalkAnim()
			return
		end
		local b = self.brawl
		if not b then
			return baseChase(self, now)
		end
		local chs = self.chase
		if not chs then
			return
		end
		local pp = P.pos
		local function done()
			self.brawl = nil
			if self.type ~= "drunk" and self.type ~= "fool" then
				self.wobble = nil -- (the hurt sway; drunks / fools sway anyway: think sets it again)
			end
		end
		if not pp or now > b.untilT or Crowd.playerSeated() then
			done()
			local l = FS and fpick(FS.LINES.brawl_end)
			if l then
				SocialUI.say(self, l, 3)
			end
			self:endChase(now, false)
			return
		end
		chs.untilT = math.max(chs.untilT, b.untilT)
		local dx, dz = pp.X - self.pos.X, pp.Z - self.pos.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 30 or math.abs(pp.Y - self.pos.Y) > 6 then
			done()
			self:endChase(now, false)
			return
		end
		-- hurt (under 60 % HP, GwangalliFight hp / max): slower swings, a sway, catching the balance
		local hf = b.hp or 1
		local hurt = hf < 0.6
		local drunk = self.type == "drunk"
		if d < ((FS and FS.NPC_REACH) or 3.4) then
			-- squared up: turn to the player (Agent.step turns toward faceYaw while not walking), then a
			-- swing every second or so, only once facing them (a player behind him is not hit)
			local ty = yawOf(dx, dz)
			if self.mode == "walk" then
				self.nav = nil
				self:idleFor("idle", 1, now, ty)
			else
				self.faceYaw = ty
				self.idleUntil = math.max(self.idleUntil or 0, now + 1)
			end
			self.nextSub = now + 5 -- (no phone / crossed arms while squared up)
			self.want, self.speed = 0, 0
			if hurt and chs.wobAt and now >= chs.wobAt then
				chs.wobAt = nil
				Anim.flash(self.rig, "stagger", 0.5)
			end
			local fdot = (-math.sin(self.yaw) * dx - math.cos(self.yaw) * dz) / math.max(d, 0.05)
			if fdot >= 0.5 and now >= chs.nextHit then
				-- (never faster than FS.NPC_SWING_GAP 0.9: the server drops those) a drunk swings at odd,
				-- uneven gaps; hurt = up to about twice as slow
				local gap = if drunk then 0.95 + rnd() * 1.65 else 1.05 + rnd() * 0.6
				if hurt then
					gap *= 1 + (0.6 - hf) * 2
					chs.wobAt = now + 0.6
				end
				chs.nextHit = now + gap
				local ux, uz = dx / math.max(d, 0.05), dz / math.max(d, 0.05)
				if drunk and rnd() < 0.35 then
					-- a drunk's wild swing that misses, or a lurch off balance: no hit at all
					if rnd() < 0.5 then
						Anim.flash(self.rig, "pointp", 0.5)
						playPose(self, "punch", 0.55)
					else
						Anim.flash(self.rig, "stagger", 0.6)
						chs.nextHit += 0.5
					end
					if rnd() < 0.5 and FS then
						local l = fpick(FS.DRUNK_LINES.follow)
						if l then
							SocialUI.say(self, l, 1.8)
						end
					end
				else
					-- a punch, a shove (weaker, a stagger) or a kick (harder, more often a fall)
					local k = rnd()
					local atk = if k < 0.6 then "punch" elseif k < 0.85 then "shove" else "kick"
					local outcome
					if atk == "kick" then
						Anim.flash(self.rig, "kick", 0.45)
						playPose(self, "kick", 0.6)
						outcome = if rnd() < 0.45 then "knockdown" else "stagger"
					elseif atk == "shove" then
						Anim.flash(self.rig, "pointp", 0.5)
						playPose(self, "shove", 0.6)
						outcome = "stagger"
					else
						Anim.flash(self.rig, "pointp", 0.5)
						playPose(self, "punch", 0.55)
						outcome = if rnd() < 0.22 then "knockdown" else "stagger"
					end
					local ch = player.Character
					if not (ch and ch:GetAttribute(knockedAttr)) then
						local line = nil
						if rnd() < 0.5 and FS then
							line = fpick(if atk == "shove" and drunk then FS.DRUNK_LINES.shove else FS.LINES.swing)
						end
						self:hitPlayer(ux, uz, outcome, line)
						local fr = fightAction()
						if fr then
							fr:FireServer("npcHit", { id = self.id, pos = { self.pos.X, self.pos.Y, self.pos.Z }, attack = atk })
						end
					end
				end
			end
			return
		end
		if now >= chs.retarget or self.mode ~= "walk" then
			self:chaseStep(now, pp)
		end
		if hurt then
			-- closing in hurt: slower, swaying (the Agent wobble drift while walking)
			self.want = math.min(self.want or 0, ((Bump and Bump.VIOLENT and Bump.VIOLENT.chaseSpeed) or 11.5) * (0.55 + hf * 0.75))
			self.wobble = (Bump and Bump.DRUNK and Bump.DRUNK.sway) or 0.3
		end
		self:updateWalkAnim()
	end
end

function Crowd.start(context: any)
	ctx = context
	W = ctx.World
	Agent = ctx.Agent
	Pool = ctx.Pool
	Anim = ctx.Anim
	Config = ctx.Config
	Citizens = ctx.Citizens
	Night = ctx.Night
	Looks = ctx.Looks
	Quality = ctx.Quality
	SocialUI = ctx.SocialUI
	player = ctx.player
	for i = 1, Config.Extras do
		table.insert(extraFree, "x" .. i)
	end
	pcall(installFightHooks)
	local cm = script.Parent:FindFirstChild("Characters")
	if cm then
		local okC, mod = pcall(require, cm)
		if okC and type(mod) == "table" then
			Crowd.Characters = mod
			task.spawn(function()
				local t0 = os.clock()
				while not ctx.Mind and os.clock() - t0 < 60 do
					task.wait(0.5)
				end
				local okI, err = pcall(mod.init, {
					Mind = ctx.Mind,
					api = Crowd.api,
					agents = function(): { any }
						return agents
					end,
					playerPos = function(): Vector3?
						return P.pos
					end,
					playerSpeed = function(): number
						return P.speed or 0
					end,
					seated = function(): boolean
						return Crowd.playerSeated()
					end,
					-- out of a group walk (a friend acting on their own: helping, running, fighting)
					detach = function(m: any)
						if m.leader then
							Crowd.detachMember(m)
						end
						if m.mode == "member" or (m.plan and m.plan.kind == "member") then
							-- (like a dissolved group: their own walk from here, Crowd.dissolve)
							m.mode = "walk"
							m.node = W.nearest(m.pos, 40)
							m.prev = nil
							m:setPlan({ kind = "wander", act = "walk", center = m.pos, radius = 150 }, os.clock())
						end
					end,
					canSay = function(t: number): boolean
						return Crowd.canSay(t)
					end,
					fire = function(kind: string, payload: any)
						local fr = fightAction()
						if fr then
							fr:FireServer(kind, payload)
						end
					end,
				})
				if not okI then
					warn("[GwangalliStreetLife] Characters: " .. tostring(err))
				end
			end)
		end
	end
	local fm = script.Parent:FindFirstChild("Friends")
	if fm then
		local okF, mod = pcall(require, fm)
		if okF and type(mod) == "table" then
			Crowd.Friends = mod
			local okI, err = pcall(mod.init, ctx)
			if not okI then
				warn("[GwangalliStreetLife] Friends: " .. tostring(err))
			end
		end
	end
	local dm = script.Parent:FindFirstChild("Delivery")
	if dm then
		local okD, mod = pcall(require, dm)
		if okD and type(mod) == "table" then
			Delivery = mod
			Crowd.Delivery = mod
			task.spawn(function()
				local t0 = os.clock()
				while not ctx.Mind and os.clock() - t0 < 60 do
					task.wait(0.5)
				end
				local okI, err = pcall(Delivery.init, ctx, {
					Agent = Agent,
					Mind = ctx.Mind,
					playPose = playPose,
					playerPos = function(): Vector3?
						return P.pos
					end,
					playerLook = function(): Vector3
						return P.look
					end,
					byId = function(): any
						return byId
					end,
				})
				if not okI then
					warn("[GwangalliStreetLife] Delivery: " .. tostring(err))
				end
			end)
		else
			warn("[GwangalliStreetLife] Delivery failed to load: " .. tostring(mod))
		end
	end
	-- dance clips the player may play (the player's own dances are "dance" emotes of any id; the
	-- default R15 ones are matched by id, others by track name)
	local AL = ctx.AnimLib
	if AL and type(AL.id) == "function" then
		for _, nm in { "dance1", "dance2", "dance3" } do
			local ok, id = pcall(AL.id, nm, "R15", 1)
			if ok and type(id) == "string" then
				DANCE_IDS[id] = true
			end
		end
	end
	Q.init()
	fillUntil = os.clock() + 4
	-- driven cars (other players): tracked through their DriveDriver attribute
	CollectionService:GetInstanceAddedSignal("GwangalliDrivable"):Connect(watchCar)
	CollectionService:GetInstanceRemovedSignal("GwangalliDrivable"):Connect(function(inst)
		driven[inst :: any] = nil
	end)
	for _, m in CollectionService:GetTagged("GwangalliDrivable") do
		watchCar(m)
	end
	local lastWarn = -1e9
	local function report(where: string, err: any)
		local t = os.clock()
		if t - lastWarn > 10 then
			lastWarn = t
			warn("[GwangalliStreetLife] " .. where .. ": " .. tostring(err))
		end
	end
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(update, dt)
		if not ok then
			report("update", err)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1 / Config.TickHz)
			local ok, err = pcall(tick)
			if not ok then
				report("tick", err)
			end
		end
	end)
	if Quality and Quality.changed then
		Quality.changed:Connect(function()
			updateLOD()
		end)
	end
	if Quality and Quality.saverChanged then
		Quality.saverChanged:Connect(function()
			updateLOD()
		end)
	end
end

return Crowd
