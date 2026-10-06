-- GwangalliStreetLife/Delivery (client; owner: npc_mind): 배달 라이더 street life on top of the crowd.
-- Not a delivery job: riders make the street feel busy, they are people (talk, feelings, fights go
-- through the usual Mind / Fight paths) and they are the special 강탈 case of GwangalliRobShared.
--
--   * WHO: roster citizens with c.delivery = "scooter" | "walk" (GwangalliCitizens). Their day is the
--     rider schedules (act "deliver": shop / food / cafe fronts one after another).
--   * LOOK: GwangalliNPCLooks gear (the scooter + rear delivery box, or the 도보 배달 bag on the back).
--   * MOVE: scooter riders sit on the scooter (the sit loop instead of walk / idle) and ride faster;
--     at a shop front they stop briefly (STOP_S: the app / the hand-over), then go on.
--   * THREAT (a gun pointed at them): the player holds a gun Tool (attribute GwWeapon = "gun" /
--     IsGun / WeaponType = "gun", or a gun-like name) within THREAT_R and faces them, or a weapon
--     system calls the API ("threat"). By nerve (c.nerve / Mind traits): surrender (off the
--     scooter, hands up, stays put), freeze (cower, trembling), flee (the brave ride off fast, the
--     timid drop the scooter and run) or try to call 112 (phone, a line; the attempt is an EVENT for
--     other systems: no wanted level / police here). Lines rotate per rider (no repeats in a row).
--     A surrendered rider who sees the player look away may still bolt or call (the brave ones).
--   * HIT: the Fight server picks flee / report for riders (cower when beaten); on a scooter the
--     flight is fast; a knocked-down rider leaves the scooter parked where they fell.
--   * ROB STATE on every street pedestrian's model (GwangalliRobShared.Attr) + the client API
--     LocalPlayer.GwangalliNPCRobAPI and the event LocalPlayer.GwangalliNPCRobEvents
--     ("threat" / "surrender" / "report" / "flee" / "robbed", info). KO / dead -> reward 0.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Delivery = {}

local player = Players.LocalPlayer
local ctx: any
local deps: any
local Rob: any = nil
local MindShared: any = nil
local tracked: { [any]: boolean } = {}
local robbedUntil: { [string]: number } = {}
local events: BindableEvent? = nil

Delivery.SCOOTER_SPEED = { 13, 17 }
Delivery.STOP_S = { 3.5, 8 }
Delivery.THREAT_R = 16 -- studs
Delivery.THREAT_CLOSE = 6 -- this close any direction counts
Delivery.THREAT_FACE = 0.86 -- cos of the aim cone
Delivery.CALM_S = 4 -- s without a threat before they recover

local GUN_WORDS = { "gun", "pistol", "rifle", "glock", "revolver", "shotgun", "smg", "uzi", "ak47", "ak-47", "m4", "deagle", "총", "권총", "소총", "엽총", "기관총" }

local LINES = {
	surrender = { "쏘, 쏘지 마세요! 가방 드릴게요!", "잠깐만요! 저 그냥 배달하는 사람이에요!", "알겠어요, 알겠어요! 손 들었어요!", "제발… 가져가세요, 다 가져가세요!", "저 애가 있어요… 제발요…", "움직이지 않을게요, 진짜로요!" },
	surrender_brave = { "…원하는 게 뭔데요.", "알았어요. 진정하고 말로 해요.", "하… 오늘 일진 진짜 최악이네.", "쏘지 마. 가방 줄 테니까." },
	freeze = { "어, 어어…", "히익…!", "…제, 제발…", "(덜덜 떤다)", "아무것도 안 했어요…" },
	flee_ride = { "으아아 비켜요!!", "미쳤어 진짜!", "콜이고 뭐고 튀자!", "꽉 잡아라 내 오토바이야!" },
	flee_run = { "살려주세요!!", "누가 좀 도와줘요!!", "총이야, 총!!", "꺄아악!" },
	report = { "여, 여보세요 112죠?! 여기 총 든 사람이…!", "경찰 부를 거예요! 진짜로!", "신고할게요! 거기 그대로 있어요!", "112… 112 빨리…!" },
	calm = { "휴… 살았다…", "심장 떨어지는 줄 알았네…", "오늘 배달 그만할까 진짜…", "아 다리 풀려…" },
	robbed = { "다… 다 가져가세요…", "그거 오늘 번 거 전부인데…", "제발 이제 가 주세요…" },
	gone = { "…", "으…" },
}

local function rnd(): number
	return math.random()
end

local function pickLine(a: any, key: string): string?
	local list = LINES[key]
	if not list or #list == 0 then
		return nil
	end
	a.dlvSaid = a.dlvSaid or {}
	local last = a.dlvSaid[key]
	local i = 1 + math.floor(rnd() * #list)
	if #list > 1 and list[i] == last then
		i = i % #list + 1
	end
	a.dlvSaid[key] = list[i]
	return list[i]
end

local function fire(kind: string, info: any)
	if events then
		pcall(events.Fire, events, kind, info)
	end
end

local function traitsOf(a: any): any
	if MindShared and a.c then
		local ok, t = pcall(MindShared.traits, a.c)
		if ok and type(t) == "table" then
			return t
		end
	end
	return { brave = 0.4, temper = 0.4, warm = 0.6, arch = "citizen" }
end

-------------------------------------------------------------------------------------------------
-- rob state (every street pedestrian)
-------------------------------------------------------------------------------------------------
local function robState(a: any): (string, boolean)
	local dead = a.ko ~= nil or a.gone == true
	if dead then
		return "dead", true
	end
	if (robbedUntil[a.id] or 0) > os.clock() then
		return "robbed", false
	end
	return a.robState or "ok", false
end

local function infoOf(a: any): any?
	if not Rob or not a then
		return nil
	end
	local st, dead = robState(a)
	local info = Rob.info(a.id, a.c, a.type, st, dead)
	info.delivery = a.delivery
	info.mounted = a.mounted == true
	info.name = a.c and a.c.name or nil
	if a.pos then
		info.x, info.y, info.z = a.pos.X, a.pos.Y, a.pos.Z
	end
	return info
end
Delivery.info = infoOf

local function publish(a: any)
	local model = a.rig and a.rig.model
	if not model or not Rob then
		return
	end
	local info = infoOf(a)
	if not info then
		return
	end
	local A = Rob.Attr
	local key = string.format("%s|%s|%d|%s", info.state, tostring(info.robbable), info.reward, tostring(a.delivery))
	if a.robKey == key then
		return
	end
	a.robKey = key
	pcall(function()
		model:SetAttribute(A.Robbable, info.robbable)
		model:SetAttribute(A.Kind, info.kind)
		model:SetAttribute(A.Reward, info.reward)
		model:SetAttribute(A.State, info.state)
		model:SetAttribute(A.Dead, info.dead)
		model:SetAttribute(A.Delivery, a.delivery)
	end)
end

local function setState(a: any, st: string)
	if a.robState ~= st then
		a.robState = st
		publish(a)
	end
end

-------------------------------------------------------------------------------------------------
-- the scooter
-------------------------------------------------------------------------------------------------
local function scooterVisible(a: any, on: boolean)
	local list = a.rig and a.rig.scooter
	if not list then
		return
	end
	for _, p in list do
		if p.Parent then
			p.LocalTransparencyModifier = if on then 0 else 1
		end
	end
end

local function clearParked(a: any)
	if a.parked then
		pcall(a.parked.Destroy, a.parked)
		a.parked = nil
	end
end

-- off the scooter: a parked copy stays where it was (anchored, no collisions)
local function dismount(a: any)
	if not a.mounted then
		return
	end
	a.mounted = false
	local list = a.rig and a.rig.scooter
	if list and #list > 0 then
		local m = Instance.new("Model")
		m.Name = "GwParkedScooter"
		for _, p in list do
			if p.Parent then
				local c = p:Clone()
				for _, ch in c:GetChildren() do
					if ch:IsA("WeldConstraint") or ch:IsA("Weld") then
						ch:Destroy()
					end
				end
				c.Anchored = true
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				c.LocalTransparencyModifier = 0
				c.Parent = m
			end
		end
		m:SetAttribute("Owner", a.id)
		local folder = workspace:FindFirstChild("GwangalliStreetLife")
		m.Parent = folder or workspace
		a.parked = m
		a.parkedPos = a.pos
	end
	scooterVisible(a, false)
	a.walkSpeed = a.footSpeed or 5.6
	if a.animState == "sit" then
		a.animState = nil
		a:setAnim("idle")
	end
end

local function remount(a: any)
	if a.mounted or a.delivery ~= "scooter" then
		return
	end
	clearParked(a)
	a.mounted = true
	scooterVisible(a, true)
	a.walkSpeed = a.rideSpeed or 15
	a.animState = nil
	a:setAnim("sit")
end

-------------------------------------------------------------------------------------------------
-- threat
-------------------------------------------------------------------------------------------------
local function heldGun(char: Model?): Tool?
	if not char then
		return nil
	end
	if workspace:GetAttribute("GwangalliTestGun") == true then
		return char:FindFirstChildOfClass("Tool") or (Instance.new("Tool") :: any)
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end
	local w = tool:GetAttribute("GwWeapon") or tool:GetAttribute("WeaponType")
	if w == "gun" or tool:GetAttribute("IsGun") == true or tool:GetAttribute("Gun") == true then
		return tool
	end
	local n = string.lower(tool.Name)
	for _, word in GUN_WORDS do
		if string.find(n, word, 1, true) then
			return tool
		end
	end
	return nil
end

local function choose(a: any): string
	local t = traitsOf(a)
	local nerve = t.brave or 0.4
	local x = rnd()
	if nerve < 0.3 then
		return if x < 0.45 then "surrender" elseif x < 0.85 then "freeze" else "flee"
	elseif nerve < 0.6 then
		return if x < 0.5 then "surrender" elseif x < 0.8 then "flee" else "report"
	elseif nerve < 0.8 then
		return if x < 0.35 then "surrender" elseif x < 0.7 then "flee" else "report"
	end
	return if x < 0.3 then "surrender" elseif x < 0.6 then "report" else "flee"
end

local drive: (a: any, ctl: any, now: number, pp: Vector3) -> ()

local function say(a: any, key: string, dur: number?)
	local l = pickLine(a, key)
	if l and deps.Mind and deps.Mind.sayNpc then
		deps.Mind.sayNpc(a, l, dur or 3)
	end
end

local function startReport(a: any, ctl: any, pp: Vector3)
	ctl.mode = "report"
	ctl.untilT = os.clock() + 5
	setState(a, "reporting")
	if a.mounted then
		dismount(a)
	end
	a.want, a.speed = 0, 0
	deps.playPose(a, "phonecall", 4.5)
	if deps.Mind.face then
		deps.Mind.face(a, "scared", 5)
	end
	say(a, "report", 3.5)
	fire("report", infoOf(a))
end

local function startFlee(a: any, ctl: any, pp: Vector3)
	ctl.mode = "flee"
	ctl.untilT = os.clock() + 8
	setState(a, "fleeing")
	local t = traitsOf(a)
	if a.mounted and (t.brave or 0) >= 0.45 then
		say(a, "flee_ride", 2.5)
	else
		if a.mounted then
			dismount(a)
		end
		say(a, "flee_run", 2.5)
	end
	local dx, dz = a.pos.X - pp.X, a.pos.Z - pp.Z
	local d = math.max(0.1, math.sqrt(dx * dx + dz * dz))
	local speed = if a.mounted then (a.rideSpeed or 15) * 1.5 else 12 + rnd() * 3
	deps.Mind.moveTo(a, Vector3.new(a.pos.X + dx / d * 40, a.pos.Y, a.pos.Z + dz / d * 40), speed)
	if deps.Mind.face then
		deps.Mind.face(a, "scared", 6)
	end
	fire("flee", infoOf(a))
end

-- a weapon pointed at them. kind = "gun" (default) | another weapon word
function Delivery.threaten(a: any, kind: string?): boolean
	if not a or a.gone or a.ko or a.knock then
		return false
	end
	local now = os.clock()
	local ctl = a.ctl
	if ctl and ctl.kind == "threat" then
		ctl.seen = now
		return true
	end
	local pp = deps.playerPos()
	if not pp then
		return false
	end
	local new = { kind = "threat", weapon = kind or "gun", seen = now, start = now, drive = drive }
	if not deps.Mind.take(a, new) then
		return false
	end
	a.threatCount = (a.threatCount or 0) + 1
	local how = choose(a)
	if a.lastThreatHow == how and rnd() < 0.5 then
		how = choose(a) -- the same person reacts a little differently next time
	end
	a.lastThreatHow = how
	fire("threat", infoOf(a))
	if how == "flee" then
		startFlee(a, new, pp)
	elseif how == "report" then
		startReport(a, new, pp)
	else
		new.mode = how
		if a.mounted then
			dismount(a)
		end
		a.want, a.speed = 0, 0
		deps.Mind.hold(a, pp, "")
		if how == "surrender" then
			setState(a, "surrender")
			deps.playPose(a, "handsup", 4.2)
			new.poseT = now
			local t = traitsOf(a)
			say(a, if (t.brave or 0) >= 0.7 then "surrender_brave" else "surrender", 3.2)
			fire("surrender", infoOf(a))
		else
			setState(a, "scared")
			deps.playPose(a, "cower", 4.2)
			new.poseT = now
			say(a, "freeze", 2.6)
		end
		if deps.Mind.face then
			deps.Mind.face(a, "scared", 30)
		end
	end
	return true
end

drive = function(a: any, ctl: any, now: number, pp: Vector3)
	local mode = ctl.mode
	if mode == "flee" or mode == "report" then
		if now > (ctl.untilT or 0) then
			if mode == "report" then
				-- after the call: get away
				startFlee(a, ctl, pp)
				return
			end
			setState(a, "ok")
			deps.Mind.release(a, a.delivery ~= "scooter" or not a.parked)
			a.dlvRecover = now
		end
		return
	end
	-- surrender / freeze: stay put, hands up, face the gun
	a.want, a.speed = 0, 0
	a.faceYaw = math.atan2(-(pp.X - a.pos.X), -(pp.Z - a.pos.Z))
	if now - (ctl.poseT or 0) > 4 then
		ctl.poseT = now
		deps.playPose(a, if mode == "surrender" then "handsup" else "cower", 4.2)
	end
	-- still threatened? (the step refreshes ctl.seen while the gun points at them)
	if now - (ctl.seen or now) > Delivery.CALM_S then
		setState(a, if (robbedUntil[a.id] or 0) > now then "robbed" else "ok")
		say(a, "calm", 3)
		deps.Mind.release(a, false)
		a.dlvRecover = now
		return
	end
	-- the brave watch for a chance: the player looks away / steps back
	if not ctl.chanceT and now - (ctl.start or now) > 3 then
		ctl.chanceT = now
		local t = traitsOf(a)
		local look = deps.playerLook()
		local dx, dz = a.pos.X - pp.X, a.pos.Z - pp.Z
		local d = math.max(0.1, math.sqrt(dx * dx + dz * dz))
		local facing = (look.X * dx + look.Z * dz) / d
		if (t.brave or 0) >= 0.6 and (facing < 0.5 or d > 10) and rnd() < 0.6 then
			if rnd() < 0.5 then
				startReport(a, ctl, pp)
			else
				startFlee(a, ctl, pp)
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- attach / step
-------------------------------------------------------------------------------------------------
function Delivery.attach(a: any)
	if not a then
		return
	end
	local c = a.c
	local kind = c and c.delivery
	if kind == "scooter" or kind == "walk" then
		a.delivery = kind
		a.footSpeed = a.walkSpeed
		if kind == "scooter" and a.rig and a.rig.onScooter then
			local s = Delivery.SCOOTER_SPEED
			a.rideSpeed = s[1] + (s[2] - s[1]) * rnd()
			a.mounted = true
			a.walkSpeed = a.rideSpeed
			scooterVisible(a, true)
		else
			a.walkSpeed = (a.walkSpeed or 5.6) * 1.15 -- 도보 배달: always in a hurry
		end
	end
	tracked[a] = true
	publish(a)
end

function Delivery.detach(a: any)
	tracked[a] = nil
	clearParked(a)
end

local nextStep = 0
local function step()
	local now = os.clock()
	if now < nextStep then
		return
	end
	nextStep = now + 0.2
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local gun = heldGun(char)
	local look = if root then root.CFrame.LookVector else Vector3.new(0, 0, -1)
	for a in tracked do
		if a.gone then
			tracked[a] = nil
			clearParked(a)
		else
			-- knocked off the scooter: it stays where they fell
			if a.mounted and (a.knock or a.ko) then
				dismount(a)
			end
			if a.delivery and gun and root and a.pos then
				local dx, dz = a.pos.X - root.Position.X, a.pos.Z - root.Position.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < Delivery.THREAT_R and math.abs(a.pos.Y - root.Position.Y) < 8 then
					local cosA = (look.X * dx + look.Z * dz) / math.max(d, 0.1)
					local aiming = player:GetAttribute("GwAiming") == true
					if d < Delivery.THREAT_CLOSE or cosA > Delivery.THREAT_FACE or (aiming and cosA > 0.6) then
						Delivery.threaten(a, "gun")
					end
				end
			end
			-- the threat goes on even out of the near ring (Mind.drive only runs for close people)
			local ctl = a.ctl
			if ctl and ctl.kind == "threat" and type(ctl.drive) == "function" then
				local pp = deps.playerPos()
				if pp then
					ctl.drive(a, ctl, now, pp)
				end
			end
			-- a flight that ended inside Mind (its own release): calm again
			if a.robState == "fleeing" and not a.ctl then
				setState(a, "ok")
			end
			-- back on the scooter after a scare / a fall (walk to it if it is parked away)
			if a.delivery == "scooter" and not a.mounted and not a.ctl and not a.knock and not a.ko then
				a.dlvRecover = a.dlvRecover or now
			end
			if a.delivery == "scooter" and not a.mounted and not a.ctl and not a.knock and not a.ko and a.dlvRecover and now - a.dlvRecover > 1.2 then
				local pp = a.parkedPos
				if not pp or (Vector3.new(a.pos.X - pp.X, 0, a.pos.Z - pp.Z)).Magnitude < 3.5 then
					remount(a)
					a.dlvRecover = nil
					a:beginPlan(now)
				elseif not a.dlvWalking then
					a.dlvWalking = true
					if deps.Mind.take(a, { kind = "threat", untilT = now + 12, drive = function(ag: any, ctl: any, t: number)
						local p2 = ag.parkedPos
						if not p2 or (Vector3.new(ag.pos.X - p2.X, 0, ag.pos.Z - p2.Z)).Magnitude < 3.5 or t > ctl.untilT then
							ag.dlvWalking = nil
							deps.Mind.release(ag, false)
							if ag.parked then
								ag.pos = Vector3.new(p2.X, ag.pos.Y, p2.Z)
							end
						end
					end }) then
						deps.Mind.moveTo(a, pp, 7)
					else
						a.dlvWalking = nil
					end
				end
			end
			publish(a)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- hooks on Agent (sit on the scooter, short stops) + Mind.flee on a scooter
-------------------------------------------------------------------------------------------------
local RIDE_ANIM = { walk = true, run = true, idle = true, idle2 = true }

local function installHooks(Agent: any)
	local baseSetAnim = Agent.setAnim
	Agent.setAnim = function(self: any, name: string, speed: number?)
		if self.mounted and RIDE_ANIM[name] then
			name = "sit"
			speed = nil
		end
		return baseSetAnim(self, name, speed)
	end
	local baseSettle = Agent.settleAtPoi
	Agent.settleAtPoi = function(self: any, now: number, frac: number?)
		baseSettle(self, now, frac)
		if self.delivery and self.plan and self.plan.act == "deliver" then
			-- a quick stop: the app / the hand-over at the door, then the next call
			local s = Delivery.STOP_S
			self.idleUntil = now + s[1] + (s[2] - s[1]) * rnd()
			if self.mounted then
				self:setAnim("sit")
			end
		end
	end
	local M = deps.Mind
	if M and M.flee then
		local baseFlee = M.flee
		M.flee = function(a: any, from: Vector3, dur: number)
			if a and a.delivery and a.mounted then
				setState(a, "fleeing")
			end
			baseFlee(a, from, dur)
			if a and a.mounted and a.ctl and a.ctl.kind == "flee" then
				-- on the scooter: away fast and far
				local dx, dz = a.pos.X - from.X, a.pos.Z - from.Z
				local d = math.max(0.1, math.sqrt(dx * dx + dz * dz))
				M.moveTo(a, Vector3.new(a.pos.X + dx / d * 45, a.pos.Y, a.pos.Z + dz / d * 45), (a.rideSpeed or 15) * 1.4)
			end
		end
		local baseRelease = M.release
		M.release = function(a: any, leave: boolean?)
			local wasFlee = a and a.ctl and (a.ctl.kind == "flee" or a.ctl.kind == "report")
			baseRelease(a, leave)
			if a and a.delivery and wasFlee then
				setState(a, "ok")
				if not a.mounted then
					a.dlvRecover = os.clock()
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- API
-------------------------------------------------------------------------------------------------
local function agentOf(x: any): any?
	if type(x) == "string" then
		return deps.byId()[x]
	end
	if typeof(x) == "Instance" then
		local id = x:GetAttribute("StreetId")
		if not id and x.Parent then
			id = x.Parent:GetAttribute("StreetId")
		end
		return id and deps.byId()[id] or nil
	end
	return nil
end

local function makeApi()
	local f = player:FindFirstChild("GwangalliNPCRobAPI")
	if not f then
		f = Instance.new("BindableFunction")
		f.Name = "GwangalliNPCRobAPI"
		f.Parent = player
	end
	local e = player:FindFirstChild("GwangalliNPCRobEvents")
	if not e then
		e = Instance.new("BindableEvent")
		e.Name = "GwangalliNPCRobEvents"
		e.Parent = player
	end
	events = e :: BindableEvent
	;(f :: BindableFunction).OnInvoke = function(method: any, x: any, arg: any): any
		if method == "info" then
			return infoOf(agentOf(x))
		elseif method == "list" then
			local out = {}
			for a in tracked do
				if not a.gone then
					local i = infoOf(a)
					if i and (arg ~= "delivery" or a.delivery) then
						table.insert(out, i)
					end
				end
			end
			return out
		elseif method == "threat" then
			local a = agentOf(x)
			return a ~= nil and Delivery.threaten(a, if type(arg) == "string" then arg else "gun")
		elseif method == "robbed" then
			local a = agentOf(x)
			if not a or not Rob then
				return false
			end
			local st, dead = robState(a)
			if dead or st == "robbed" then
				return false
			end
			robbedUntil[a.id] = os.clock() + Rob.ROBBED_COOLDOWN
			setState(a, "robbed")
			say(a, "robbed", 3)
			fire("robbed", infoOf(a))
			return true
		elseif method == "rules" then
			return Rob and Rob.KIND or nil
		end
		return nil
	end
end

function Delivery.init(context: any, d: any)
	ctx = context
	deps = d
	local okR, r = pcall(function()
		return require(ReplicatedStorage:WaitForChild("GwangalliRobShared", 10) :: any)
	end)
	Rob = if okR then r else nil
	local okM, m = pcall(function()
		return require(ReplicatedStorage:WaitForChild("GwangalliMindShared", 10) :: any)
	end)
	MindShared = if okM then m else nil
	installHooks(d.Agent)
	makeApi()
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(step)
		if not ok then
			warn("[GwangalliStreetLife.Delivery] " .. tostring(err))
		end
	end)
end

-- debug: the riders around
function Delivery.stats(): any
	local n, mounted, parked, states = 0, 0, 0, {}
	for a in tracked do
		if a.delivery and not a.gone then
			n += 1
			if a.mounted then
				mounted += 1
			end
			if a.parked then
				parked += 1
			end
			local st = robState(a)
			states[st] = (states[st] or 0) + 1
		end
	end
	return { riders = n, mounted = mounted, parked = parked, states = states }
end

return Delivery
