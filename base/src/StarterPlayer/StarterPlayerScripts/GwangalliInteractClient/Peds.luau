-- GwangalliInteractClient/Peds: the street pedestrians' side of a fight. Pedestrians live only on this
-- client (GwangalliStreetLife), so their reactions play here once the server decided them:
--   * hit: stagger / knockdown / KO (held on the ground KO_TIME, then up and off at a run)
--   * flee (a run away, then they despawn), cower (hands up, begging), talk / thanks lines
--   * fight: the existing chase (Agent:startChase), re-aimed to stop at arm's length, plus punches every
--     ~1 s that the server validates ("pedHit": only a pedestrian the player provoked can land one)
--   * 동네바보 만복이 (a server NPC) shoulder-bumps the pedestrians he runs through
--   * when the police are after you, nearby people turn, point and get out of the way
-- Uses the street life's own modules (same require cache): Crowd.byId -> agent objects.

local Players = game:GetService("Players")

local P = {}

local C: any
local R: any -- Render (pose tracks)
local BUMP: any
local player = Players.LocalPlayer
local Crowd: any = nil
local streetAPI: BindableFunction? = nil
local fire: (string, any) -> () = function() end

local fights: { [any]: any } = {} -- agent -> { untilT, nextHit, restartAt }
local kos: { [any]: number } = {} -- agent -> KO until (os.clock)
local fleeing: { [any]: number } = {}

local rnd = Random.new()
local function range(t: { number }): number
	return t[1] + (t[2] - t[1]) * rnd:NextNumber()
end

local function api(method: string, ...: any): any
	local f = streetAPI
	if not f or not f.Parent then
		f = player:FindFirstChild("GwangalliStreetAPI") :: BindableFunction?
		streetAPI = f
	end
	if not f then
		return nil
	end
	local ok, r = pcall(f.Invoke, f, method, ...)
	return if ok then r else nil
end
P.api = api

local function findCrowd(): any
	if Crowd then
		return Crowd
	end
	local ps = player:FindFirstChildOfClass("PlayerScripts")
	if not ps then
		return nil
	end
	for _, c in ps:GetChildren() do
		if c.Name == "GwangalliStreetLife" and c:IsA("Folder") then
			local m = c:FindFirstChild("Crowd")
			if m and m:IsA("ModuleScript") then
				local ok, res = pcall(require, m)
				if ok and type(res) == "table" and res.byId then
					Crowd = res
				end
			end
		end
	end
	return Crowd
end

local function agentOf(id: string): any?
	local cr = findCrowd()
	local a = cr and cr.byId and cr.byId[id]
	if a and not a.gone then
		return a
	end
	return nil
end
P.agentOf = agentOf

function P.say(id: string, text: string?, dur: number?)
	if text and text ~= "" then
		api("say", id, text, nil, dur or 3)
	end
end

local function playerFeet(): Vector3?
	local cr = findCrowd()
	if cr and cr.playerPos then
		local ok, p = pcall(cr.playerPos)
		if ok and p then
			return p
		end
	end
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return r and (r.Position - Vector3.new(0, 3, 0)) or nil
end

local function yawTo(a: any, p: Vector3): number
	return math.atan2(-(p.X - a.pos.X), -(p.Z - a.pos.Z))
end

---------------------------------------------------------------------------------------------------
-- reactions
---------------------------------------------------------------------------------------------------
local function endFight(a: any, quiet: boolean?)
	local f = fights[a]
	fights[a] = nil
	if not f then
		return
	end
	a.giFight = nil
	a.chaseStep = nil -- back to the Agent method
	a.typeLine = nil
	if a.chase then
		pcall(a.endChase, a, os.clock(), true)
	end
	if a.rig and a.rig.model then
		R.holdPose(a.rig.model, nil)
	end
	if not quiet then
		fire("fightOver", { id = a.id })
	end
end

local function flee(a: any, line: string?)
	if a.gone then
		return
	end
	endFight(a, true)
	fleeing[a] = os.clock() + 12
	a.walkSpeed = math.max(a.walkSpeed or 6, 15)
	if line then
		P.say(a.id, line, 2.5)
	end
	pcall(function()
		local cr = findCrowd()
		local pp = playerFeet()
		if a.mode == "talk" then
			a:endTalk(os.clock())
		end
		a:setPlan({ kind = "leave", act = "walk" }, os.clock())
		local _ = cr
		local __ = pp
	end)
end

local function cower(a: any, line: string?)
	if a.gone then
		return
	end
	local now = os.clock()
	local pp = playerFeet()
	pcall(function()
		a:idleFor("idle", 3.5, now, if pp then yawTo(a, pp) else nil)
	end)
	if a.rig and a.rig.model then
		R.holdPose(a.rig.model, "cower")
		task.delay(3.4, function()
			if not a.gone and a.rig and a.rig.model and not fights[a] then
				R.holdPose(a.rig.model, nil)
			end
		end)
	end
	if line then
		P.say(a.id, line, 2.8)
	end
end

-- the fight: the Agent's own chase, aimed to stop at arm's length, never ending on its own
local function chaseStepClose(self: any, now: number, pp: Vector3)
	local d = Vector3.new(self.pos.X - pp.X, 0, self.pos.Z - pp.Z)
	local stop = C.NPC_FIGHT.reach - 0.9
	local target
	if d.Magnitude <= stop + 0.3 then
		target = self.pos
	else
		local u = d.Unit
		target = Vector3.new(pp.X + u.X * stop, self.pos.Y, pp.Z + u.Z * stop)
	end
	self.nav = { mode = "points", pts = { target }, i = 1 }
	self.mode = "walk"
	self.faceYaw = nil
	self.pauseUntil = 0
	self.want = if d.Magnitude <= stop + 0.3 then 0 else C.NPC_FIGHT.speed
	self:segTo(target, nil, nil)
	self.node = nil
	if self.chase then
		self.chase.retarget = now + 0.3
	end
end

local function quietLine(self: any, kind: string): string?
	if kind == "chase" or kind == "giveup" then
		return nil
	end
	local m = getmetatable(self)
	local f = m and m.__index and (m.__index :: any).typeLine
	if type(f) == "function" then
		return f(self, kind)
	end
	return nil
end

local function startFight(a: any, line: string?)
	if a.gone or a.clubGuest or a.riding then
		return
	end
	fleeing[a] = nil
	fights[a] = { untilT = os.clock() + C.NPC_FIGHT.timeout, nextHit = os.clock() + 0.7, restartAt = 0 }
	a.giFight = true
	a.chaseStep = chaseStepClose
	a.typeLine = quietLine
	if line then
		P.say(a.id, line, 2.5)
	end
	if a.rig and a.rig.model then
		R.holdPose(a.rig.model, "fight")
	end
end

-- the server's verdict on one of our actions (hit / pedReact payloads)
function P.react(id: string, react: string?, line: string?, payload: any?)
	local a = agentOf(id)
	if not a then
		return
	end
	if react == "fight" then
		if not fights[a] then
			startFight(a, line)
		elseif line then
			P.say(id, line, 2.5)
		end
	elseif react == "flee" then
		flee(a, line)
	elseif react == "cower" or react == "robbed" then
		cower(a, line)
		if react == "robbed" then
			task.delay(2.6, function()
				flee(a, nil)
			end)
		end
	elseif react == "calm" then
		endFight(a)
		P.say(id, line, 3)
	elseif react == "given" or react == "talk" or react == "provoked" or react == "laugh" or react == "sad" then
		local pp = playerFeet()
		pcall(function()
			if not a.chase and not a.knock and a.mode ~= "talk" then
				a:idleFor("idle", 2.5, os.clock(), if pp then yawTo(a, pp) else nil)
			end
		end)
		if react == "given" and a.rig and a.rig.model then
			R.move(a.rig.model, "cheer")
		elseif react == "laugh" and a.rig and a.rig.model then
			R.move(a.rig.model, "laugh")
		elseif react == "provoked" and a.rig and a.rig.model then
			R.move(a.rig.model, "point")
		end
		P.say(id, line, 3)
	elseif react == "ko" then
		-- handled by the knock (P.hit)
	else
		P.say(id, line, 3)
	end
	local _ = payload
end

-- our punch / shove landed on a pedestrian
function P.hit(e: any)
	local a = agentOf(e.id)
	if not a then
		return
	end
	local outcome = if e.outcome == "stagger" then "stagger" else "knockdown"
	local puk = if e.crit then "빡!" elseif e.verb == "shove" then "툭!" else "퍽!"
	-- a punch interrupts their own chase / talk; fighters keep fighting once back up
	if a.knock then
		a.knock = nil -- hit again on the way down: restart the fall
	end
	local ok = api("knock", e.id, e.dx or 0, e.dz or 0, outcome, puk)
	if ok and a.rig and a.rig.model then
		R.move(a.rig.model, "hurt")
	end
	if e.ko then
		kos[a] = os.clock() + range(C.KO_TIME)
		endFight(a, true)
		task.delay(0.8, function()
			if not a.gone then
				P.say(a.id, C.typeLine(a.type, "ko"), 2)
			end
		end)
		return
	end
	if e.line then
		task.delay(0.35, function()
			P.say(e.id, e.line, 2.5)
		end)
	end
	if e.react == "fight" then
		if not fights[a] then
			startFight(a, nil)
		end
		local f = fights[a]
		if f then
			f.restartAt = os.clock() + (if outcome == "knockdown" then 2.4 else 1.0)
			f.untilT = math.max(f.untilT, os.clock() + 12)
		end
	elseif e.react == "flee" then
		task.delay(if outcome == "knockdown" then 2.3 else 0.9, function()
			flee(a, C.typeLine(a.type, "flee"))
		end)
	elseif e.react == "cower" then
		task.delay(if outcome == "knockdown" then 2.3 else 0.9, function()
			cower(a, C.typeLine(a.type, "cower"))
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- per frame
---------------------------------------------------------------------------------------------------
local lastWitness = 0
function P.step(_dt: number, ctx: any)
	local now = os.clock()
	-- KOs: keep them on the ground, then up and away
	for a, untilT in kos do
		if a.gone then
			kos[a] = nil
		elseif a.knock and a.knock.outcome == "knockdown" then
			if now < untilT then
				if now - a.knock.t0 > 1.0 then
					a.knock.t0 = now - 1.0 -- hold the "down" phase
				end
			else
				kos[a] = nil
				task.delay(2.2, function()
					if not a.gone then
						flee(a, C.typeLine(a.type, "flee"))
					end
				end)
			end
		elseif not a.knock then
			kos[a] = nil
		end
	end
	for a, t in fleeing do
		if a.gone or now > t then
			fleeing[a] = nil
		end
	end
	-- fights
	local pp = playerFeet()
	local busy = ctx.busy()
	for a, f in fights do
		if a.gone or not a.rig or not a.rig.model or not a.rig.model.Parent then
			fights[a] = nil
			fire("fightOver", { id = a.id })
			continue
		end
		if not pp or busy or now > f.untilT then
			endFight(a)
			continue
		end
		local d = math.sqrt((pp.X - a.pos.X) ^ 2 + (pp.Z - a.pos.Z) ^ 2)
		if d > C.NPC_FIGHT.give_up or math.abs(pp.Y - a.pos.Y) > 8 then
			P.say(a.id, C.typeLine(a.type, "win"), 2.5)
			endFight(a)
			continue
		end
		if a.knock then
			continue
		end
		if not a.chase then
			if now >= f.restartAt then
				pcall(a.startChase, a, now, pp)
				if a.chase then
					a.chase.untilT = f.untilT
					a.chase.nextHit = math.huge
				end
				R.holdPose(a.rig.model, "fight")
			end
			continue
		end
		a.chase.nextHit = math.huge
		a.chase.untilT = f.untilT
		if d <= C.NPC_FIGHT.reach and now >= f.nextHit and not ctx.playerDown() then
			f.nextHit = now + range(C.NPC_FIGHT.every)
			R.move(a.rig.model, "punch")
			fire("pedHit", { id = a.id, pos = C.packV(a.pos) })
		end
	end
	-- 만복이 runs through pedestrians
	local cr = findCrowd()
	local foolRec = ctx.foolRec()
	if cr and foolRec and foolRec.path then
		local fp = R.feetOf(foolRec.model)
		if fp then
			for _, a in cr.agents do
				if not a.gone and not a.knock and not a.clubGuest and not a.riding and a.pos then
					local dx, dz = a.pos.X - fp.X, a.pos.Z - fp.Z
					local d2 = dx * dx + dz * dz
					if d2 < 2.2 * 2.2 and math.abs(a.pos.Y - fp.Y) < 3 and now - (a.giFoolBump or -1e9) > 10 then
						a.giFoolBump = now
						local m = math.max(0.05, math.sqrt(d2))
						api("knock", a.id, dx / m, dz / m, if rnd:NextNumber() < 0.3 then "knockdown" else "stagger", "툭!")
						task.delay(1, function()
							if not a.gone then
								P.say(a.id, C.pick({ "아 저 바보 또!", "만복아!!", "야 인마!", "아이고 깜짝이야" }), 2.5)
							end
						end)
					end
				end
			end
		end
	end
	-- wanted: bystanders near you react (now and then)
	if ctx.wanted() > 0 and cr and pp and now - lastWitness > 4 then
		lastWitness = now
		local n = 0
		for _, a in cr.agents do
			if n >= 2 then
				break
			end
			if not a.gone and not a.knock and not fights[a] and not fleeing[a] and a.pos then
				local d = math.sqrt((pp.X - a.pos.X) ^ 2 + (pp.Z - a.pos.Z) ^ 2)
				if d < 16 and rnd:NextNumber() < 0.5 then
					n += 1
					if a.type == "violent" then
						pcall(a.lookAtPoint, a, pp, 2.5, now)
					else
						flee(a, C.line("witness"))
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- incidents (server broadcast): the passers-by who can SEE it (or hear a loud one) react by type
---------------------------------------------------------------------------------------------------
local WATCH_LINES = { "뭐야, 싸움 났나?", "어머 저기 봐…", "와 대박…", "저거 경찰 불러야 되는 거 아냐?", "헐…" }
local SMALL_LINES = { "뭐야?", "왜 저래…", "시끄럽네", "에이 참…" }
local THUG_LINES = { "오~ 붙었네?", "구경 났다 구경 났어", "한 대 더 쳐라!" }
local DRUNK_LINES = { "어이~ 싸우지 마라~ 딸꾹", "좋다~ 한 판 붙어라~" }
local FLEE_LINES = { "꺄악!", "싸움 났어요!", "경찰! 경찰 불러요!", "저쪽으로 가요, 빨리!" }

local seenRay: RaycastParams? = nil
local function losParams(): RaycastParams
	local rp = seenRay or RaycastParams.new()
	seenRay = rp
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	for _, name in { "GwangalliInteractNPCs", "GwangalliNPCs", "GwangalliStreetLife" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	rp.FilterDescendantsInstances = ignore
	return rp
end

function P.onIncident(e: any, pos: Vector3)
	local cr = findCrowd()
	if not cr or not cr.agents then
		return
	end
	local sev = tonumber(e.sev) or 1
	local reach = if e.loud then 44 elseif sev >= 3 then 34 else 22
	local now = os.clock()
	local rp = losParams()
	local n = 0
	for _, a in cr.agents do
		if n >= 5 then
			break
		end
		if a.gone or a.knock or fights[a] or fleeing[a] or not a.pos or a.clubGuest or a.riding then
			continue
		end
		local d = (a.pos - pos).Magnitude
		if d > reach or d < 1.5 then
			continue
		end
		-- eyes to the scene: walls / buildings block it (a loud one is still heard nearby)
		local eye = a.pos + Vector3.new(0, 4.6, 0)
		local to = pos + Vector3.new(0, 3, 0) - eye
		local ok, hit = pcall(workspace.Raycast, workspace, eye, to, rp)
		local sees = ok and hit == nil
		if not sees and not (e.loud and d < reach * 0.55) then
			continue
		end
		n += 1
		local t = a.type or "plain"
		local roll = rnd:NextNumber()
		local delay = 0.2 + d / 30 + rnd:NextNumber() * 0.4
		task.delay(delay, function()
			if a.gone or a.knock or fights[a] then
				return
			end
			if sev >= 3 then
				if t == "violent" then
					pcall(a.lookAtPoint, a, pos, 4, os.clock())
					P.say(a.id, C.pick(THUG_LINES), 2.5)
				elseif t == "drunk" then
					pcall(a.lookAtPoint, a, pos, 4, os.clock())
					P.say(a.id, C.pick(DRUNK_LINES), 2.5)
					if a.rig and a.rig.model then
						R.move(a.rig.model, "cheer")
					end
				elseif roll < 0.5 then
					flee(a, C.pick(FLEE_LINES))
				elseif roll < 0.8 then
					-- stays at a distance, phone out (filming / calling)
					pcall(a.lookAtPoint, a, pos, 5, os.clock())
					P.say(a.id, C.pick(WATCH_LINES), 2.5)
					if a.rig and a.rig.model then
						R.holdPose(a.rig.model, "phone")
						task.delay(5, function()
							if not a.gone and a.rig and a.rig.model and not fights[a] then
								R.holdPose(a.rig.model, nil)
							end
						end)
					end
				else
					cower(a, C.pick({ "어떡해…", "무서워…" }))
				end
			elseif sev == 2 then
				pcall(a.lookAtPoint, a, pos, 2.5, os.clock())
				if roll < 0.5 then
					P.say(a.id, C.pick(SMALL_LINES), 2)
				end
				if roll < 0.25 and a.rig and a.rig.model then
					R.move(a.rig.model, "point")
				end
			elseif roll < 0.4 then
				pcall(a.lookAtPoint, a, pos, 1.6, os.clock())
			end
		end)
	end
	local _ = now
end

function P.onIncidentEnd(_e: any)
	-- (the watchers' looks and phones time out by themselves)
end

-- nearest pedestrians in front of the player (for targeting): { id, name, typeId, root, down }
function P.near(r: number): { any }
	local list = api("near", r)
	return if type(list) == "table" then list else {}
end

function P.isFighting(id: string): boolean
	local a = agentOf(id)
	return a ~= nil and fights[a] ~= nil
end

function P.isKO(id: string): boolean
	local a = agentOf(id)
	return a ~= nil and kos[a] ~= nil
end

function P.init(deps: any)
	C = deps.C
	R = deps.R
	BUMP = deps.BUMP
	fire = deps.fire
	task.spawn(function()
		for _ = 1, 40 do
			if findCrowd() then
				break
			end
			task.wait(0.5)
		end
	end)
end

return P
