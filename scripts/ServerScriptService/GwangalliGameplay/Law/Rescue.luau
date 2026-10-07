-- GwangalliGameplay/Law/Rescue (server; owner: npc_mind): 119 구급대 NPC. Not a combat unit and not
-- the 119 job (no UI, no pay): ambient rescue AI another session can build on. Numbers: LS.RESCUE.
--
--   출동 -> 구급차 운전 -> 현장 도착 -> 하차 -> 부상자 접근 -> 응급처치 -> 환자 이송 -> 병원 이동
--   * CALLS: Rescue.casualty({ pos, id, kind = "ped" | "npc", player }) — GwangalliGameplay/Fight calls
--     it on every KO (fights, car hits); other systems use ServerStorage.GwangalliRescueAPI
--     ("casualty", spec) / ("status"). Casualties close together are one call (MERGE_R).
--   * THE AMBULANCE: the hospital's Car_Ambulance (Police.newCar, car kind "ambulance", 2 crew),
--     spawned far away out of sight and driven in on the roads (the Police car path / client sampler).
--   * SAFETY FIRST: while a fight, gunfire (Law/Swat shots) or a wanted suspect is within SAFE_R the
--     ambulance stops STAGE_BACK studs short and the crew waits ("현장 위험, 대기"); only after SAFE_HOLD
--     seconds of calm (the police / 특임대 secured it) do they drive up and go in. If it turns unsafe
--     again while treating, they fall back to the ambulance.
--   * CARE: each paramedic kneels at the casualty (act "squat"), lines, TREAT_S seconds; then the
--     patient is carried off (the casualty's client fades the body: Fight "ems" pickup), the crew
--     boards and drives to the 광안 메디컬 의원 ambulance bay, walks in through the entrance and
--     Law/Hospital gets a new emergency patient (nurses / doctor meet them at the door).
--   * A street casualty is a client-side body: the client keeps it down while the ambulance comes
--     (Fight "ems" dispatched -> HOLD_KO_S).

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Rescue = {}

local Law: any
local ctx: any
local LS: any
local RS: any
local P: any

local incidents: { any } = {}
local seqN = 0
local UNIT: any = nil

local BAY = Vector3.new(-442, 7.2, 290) -- 광안 메디컬 의원 ambulance bay (map)
local ENTRANCE = Vector3.new(-496, 7.2, 262) -- in front of the automatic door

local function now(): number
	return os.clock()
end

local function rnd(): number
	return math.random()
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function pick(list: { string }): string
	return list[1 + math.floor(rnd() * #list)]
end

local function tell(inc: any, phase: string)
	local F = ctx.fight
	if not F or type(F.tell) ~= "function" or not inc.player or not inc.player.Parent then
		return
	end
	for _, id in inc.ids do
		pcall(F.tell, inc.player, { kind = "ems", id = id, phase = phase, hold = RS.HOLD_KO_S })
	end
end

-- is the scene safe? (no street fight, no gunfire, no engaged 특임대, no wanted suspect around)
local function safe(pos: Vector3): (boolean, string?)
	local F = ctx.fight
	if F and type(F.fightingNear) == "function" and F.fightingNear(pos, RS.SAFE_R) then
		return false, "fight"
	end
	local S = ctx.swat
	if S then
		if S.gunfireNear(pos, RS.SAFE_R + 15, 8) then
			return false, "gunfire"
		end
		if S.activeNear(pos, RS.SAFE_R + 20) then
			return false, "swat"
		end
	end
	for _, p in Players:GetPlayers() do
		local s = Law.sess(p)
		local pp = Law.posOf(p)
		if s and pp and (s.stars or 0) > 0 and not s.cuffed and not s.jail and flat(pp, pos) < RS.SAFE_R then
			return false, "suspect"
		end
	end
	return true, nil
end
Rescue.safe = safe

local function ambulances(): number
	local n = 0
	for _, inc in incidents do
		if inc.car and not inc.car.gone then
			n += 1
		end
	end
	return n
end

function Rescue.casualty(spec: any): any?
	if type(spec) ~= "table" or typeof(spec.pos) ~= "Vector3" then
		return nil
	end
	for _, inc in incidents do
		if not inc.closed and inc.phase ~= "transport" and inc.phase ~= "arrived" and flat(inc.pos, spec.pos) < RS.MERGE_R then
			if spec.id and not table.find(inc.ids, spec.id) then
				table.insert(inc.ids, spec.id)
			end
			return inc
		end
	end
	seqN += 1
	local inc = { n = seqN, pos = spec.pos, ids = { spec.id }, kind = spec.kind, player = spec.player, t = now(), phase = "call", safeSince = nil }
	if not spec.id then
		inc.ids = {}
	end
	table.insert(incidents, inc)
	return inc
end

-------------------------------------------------------------------------------------------------
-- the ambulance (Police.unitCarThink.ems: fully driven here)
-------------------------------------------------------------------------------------------------
local function pathDone(c: any): boolean
	return c.path == nil or now() - c.t0 >= (c.path.total or 0)
end

local function route(c: any, to: Vector3, stopBack: number, cruise: number?): boolean
	local path = P.carRoute(c, to, { cruise = cruise or 40, v1 = 0, stopBack = stopBack })
	if path then
		P.setCarPath(c, path)
		c.model:SetAttribute("LawCarMoving", true)
		return true
	end
	return false
end

local function crewLine(c: any, list: { string })
	for _, o in c.crew do
		if not o.gone then
			P.say(o, pick(list), 3)
			return
		end
	end
end

local function carThink(c: any): boolean
	local inc = c.inc
	if not inc or inc.closed then
		if not c.leaving then
			c.leaving = true
			if P.seatedCount(c) > 0 then
				P.driveAway(c)
			else
				P.removeCar(c)
			end
		end
		return false -- the police car brain handles leave / abandoned
	end
	if c.state == "leave" or c.state == "abandoned" then
		return false
	end
	local t = now()
	if t < (c.nextThink or 0) then
		return true
	end
	c.nextThink = t + 0.5
	local ok, why = safe(inc.pos)
	if ok then
		inc.safeSince = inc.safeSince or t
	else
		inc.safeSince = nil
		inc.unsafeWhy = why
	end
	local calm = inc.safeSince ~= nil and t - inc.safeSince >= RS.SAFE_HOLD
	if c.state == "respond" then
		-- on the way: not safe -> stop short of it
		if not calm and not c.staged then
			c.staged = true
			route(c, inc.pos, RS.STAGE_BACK, 40)
		end
		if pathDone(c) then
			if calm then
				if c.staged and flat(P.carPos(c), inc.pos) > 20 then
					c.staged = false
					crewLine(c, RS.LINES.go)
					route(c, inc.pos, 9, 22)
					return true
				end
				inc.phase = "scene"
				P.startExits(c, inc.pos)
			elseif not c.waitLine or t - c.waitLine > 12 then
				c.waitLine = t
				crewLine(c, RS.LINES.wait)
				inc.phase = "staging"
			end
		end
		return true
	end
	if c.state == "parked" then
		-- everybody back in after the patient is loaded: to the hospital
		if inc.loaded and P.seatedCount(c) >= c.crewN and P.boardingCount(c) == 0 then
			c.state = "transport_ems"
			inc.phase = "transport"
			c.model:SetAttribute("LawSiren", true)
			route(c, BAY, 2, 44)
		end
		return true
	end
	if c.state == "transport_ems" then
		if pathDone(c) then
			inc.phase = "arrived"
			c.arrivedT = t
			P.startExits(c, ENTRANCE)
			c.state = "hospital" -- (not "parked": the patient is already delivered)
			c.model:SetAttribute("LawSiren", false)
		end
		return true
	end
	return true
end

-------------------------------------------------------------------------------------------------
-- the paramedics on foot (Police.unitThink.ems)
-------------------------------------------------------------------------------------------------
local function think(o: any)
	local c = o.car
	local inc = c and c.inc
	if not inc or inc.closed then
		o.state = "leave"
		o.leaveAt = now() + 30
		return
	end
	local t = now()
	if t < (o.pauseUntil or 0) then
		return
	end
	-- at the hospital: walk in through the entrance, then they are inside
	if inc.phase == "arrived" then
		if o.state ~= "in" then
			o.state = "in"
			P.assignGoal(o, ENTRANCE + Vector3.new((o.k or 1) * 1.5 - 2, 0, 1), 7, nil)
			if o.k == 1 then
				P.say(o, pick(RS.LINES.arrive), 3)
				local H = ctx.hospital
				if H and type(H.emergency) == "function" then
					pcall(H.emergency, { ids = inc.ids })
				end
			end
		elseif P.arrived(o) then
			P.removeOfficer(o)
			local left = 0
			for _, m in c.crew do
				if not m.gone then
					left += 1
				end
			end
			if left == 0 then
				inc.closed = true
			end
		end
		return
	end
	local ok = safe(inc.pos)
	if o.state == "deploy" or o.state == "wait" then
		if ok and inc.safeSince and t - inc.safeSince >= RS.SAFE_HOLD then
			local off = Vector3.new(if (o.k or 1) == 1 then 1.6 else -1.6, 0, 1.2)
			P.assignGoal(o, inc.pos + off, 9, nil)
			o.state = "approach"
		elseif o.state ~= "wait" then
			o.state = "wait"
			P.standAt(o, P.legPos(o, t))
			P.setAct(o, "lookout")
		end
		return
	end
	if not ok and (o.state == "approach" or o.state == "treat") then
		-- it turned dangerous: back to the ambulance and wait
		o.state = "wait"
		local _, _, door = P.doorWorld(c, o.k or 1)
		P.assignGoal(o, door, 11, nil)
		if o.k == 1 then
			P.say(o, pick(RS.LINES.wait), 3)
		end
		return
	end
	if o.state == "approach" then
		if P.arrived(o) then
			o.state = "treat"
			o.treatUntil = t + RS.TREAT_S[1] + rnd() * (RS.TREAT_S[2] - RS.TREAT_S[1])
			P.faceTo(o, inc.pos)
			P.setAct(o, "squat")
			P.say(o, pick(RS.LINES.treat), 3)
			o.nextLine = t + 3
			inc.phase = "treat"
		end
		return
	end
	if o.state == "treat" then
		if t >= (o.nextLine or 0) then
			o.nextLine = t + 3.5
			if rnd() < 0.6 then
				P.say(o, pick(RS.LINES.treat), 3)
			end
		end
		if t >= o.treatUntil then
			if not inc.loaded then
				inc.loaded = true
				P.say(o, pick(RS.LINES.load), 3)
				tell(inc, "pickup")
			end
			P.setAct(o, "idle")
			P.boardOfficer(o, c)
		end
		return
	end
end

-------------------------------------------------------------------------------------------------
-- dispatch
-------------------------------------------------------------------------------------------------
local acc = 0
function Rescue.tick(dt: number)
	acc += dt
	if acc < 1 then
		return
	end
	acc = 0
	for i = #incidents, 1, -1 do
		local inc = incidents[i]
		if inc.closed then
			table.remove(incidents, i)
		elseif not inc.car then
			if ambulances() < RS.MAX_AMBULANCES then
				local c = P.newCar(nil, inc.pos, "ems", UNIT)
				if c then
					inc.car = c
					c.inc = inc
					c.crewN = #c.crew
					c.state = "respond"
					for k, o in c.crew do
						o.k = k
					end
					inc.phase = "inbound"
					tell(inc, "dispatched")
					crewLine(c, RS.LINES.dispatch)
				end
			end
			if not inc.car and now() - inc.t > 120 then
				inc.closed = true
			end
		elseif inc.car.gone then
			inc.closed = true
		elseif now() - inc.t > 600 then
			inc.closed = true -- (stuck somewhere: give up)
		end
	end
end

function Rescue.status(): any
	local out = {}
	for _, inc in incidents do
		table.insert(out, { n = inc.n, phase = inc.phase, ids = #inc.ids, safe = (safe(inc.pos)), why = inc.unsafeWhy, car = inc.car and inc.car.state or nil, x = inc.pos.X, z = inc.pos.Z })
	end
	return out
end

function Rescue.init(law: any, context: any)
	Law = law
	ctx = context
	LS = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliLawShared")) :: any
	RS = LS.RESCUE
	P = Law.children.Police
	assert(P and RS, "Law/Rescue needs Law/Police and LS.RESCUE")
	UNIT = {
		kind = "ems",
		car = "ambulance",
		crew = 2,
		civil = true,
		label = "119 구급",
		prefix = "ems_",
		names = RS.NAMES,
		look = { style = "paramedic", age = "adult", acc = { "kitbag" } },
		extraCap = 2 * RS.MAX_AMBULANCES,
		extraCars = RS.MAX_AMBULANCES,
	}
	P.unitThink.ems = think
	P.unitCarThink.ems = carThink
	ctx.rescue = Rescue
	local old = ServerStorage:FindFirstChild("GwangalliRescueAPI")
	if old then
		old:Destroy()
	end
	local api = Instance.new("BindableFunction")
	api.Name = "GwangalliRescueAPI"
	api.OnInvoke = function(op: any, spec: any): any
		if op == "casualty" and type(spec) == "table" then
			local pos = spec.pos
			if type(pos) == "table" then
				pos = Vector3.new(pos[1] or pos.x or 0, pos[2] or pos.y or 0, pos[3] or pos.z or 0)
			end
			local inc = Rescue.casualty({ pos = pos, id = spec.id, kind = spec.kind, player = spec.player })
			return inc ~= nil
		elseif op == "status" then
			return Rescue.status()
		end
		return nil
	end
	api.Parent = ServerStorage
end

return Rescue
