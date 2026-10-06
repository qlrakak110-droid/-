-- GwangalliGameplay/Fight (server feature module; owner: npc): 길거리 싸움 — the player's 👊 주먹 on
-- NPCs, NPC HP / 쓰러짐 (KO), how the person hit reacts (fight back / flee / report / arrest) and the
-- swings of an NPC that fights back. Contract: ReplicatedStorage.GwangalliFightShared.
--
--   * The server owns every number: HP per (player, pedestrian) — street pedestrians exist on one
--     client only — and per key NPC (shared); damage, crits, knockdowns, the KO; the reaction (by type /
--     personality, GwangalliMindShared.traits); the crime (Law: 폭행 once per victim and minute, 폭행치사
--     for a KO, a phone report makes the police know at once); 호감도 (ctx.social.award "assault").
--   * Clients only ask and play: the punch lunge, the fall / KO, the HP bar, the brawl.
--   * Key NPCs (shops, quests) never go below FightShared.KEY_MIN_HP and never stay down.
--   * A named citizen who went down is off the street for HOSPITAL_S ("down" event: clients skip them).
--   * NPC swings ("npcHit") count only from an NPC this server put in a brawl with that player, close
--     enough, not too often; they never take the player below PLAYER_MIN_HP.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fight = {}
local Rob: any = nil -- GwangalliRobShared (강탈 rules, read by the crime systems)

local ctx: any
local FS: any
local Citizens: any
local MindShared: any
local NPC: any

local remotes: { Action: RemoteEvent?, Event: RemoteEvent? } = {}

type HpRec = { hp: number, max: number, t: number }
local pedHp: { [Player]: { [string]: HpRec } } = {} -- street pedestrians (per player: client-side people)
local keyHp: { [string]: HpRec } = {} -- key NPCs (one world)
local lastPunch: { [Player]: number } = {}
local brawls: { [Player]: { [string]: { untilT: number, last: number } } } = {}
local lastCrime: { [Player]: { [string]: number } } = {}
local hospital: { [string]: number } = {} -- citizen id -> os.time() when they are back
local koUntil: { [Player]: { [string]: number } } = {}
local hitCount: { [Player]: { [string]: { n: number, t: number } } } = {} -- short memory (2 min)

local rng = Random.new()
local function r(): number
	return rng:NextNumber()
end

local function now(): number
	return os.clock()
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function pick(list: { string }?): string?
	if not list or #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

local function dbg(...)
	if workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		print("[GwangalliFight:dbg]", ...)
	end
end

local function rootOf(player: Player): BasePart?
	local ch = player.Character
	local r0 = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r0 and r0:IsA("BasePart") then r0 else nil
end

local function unpackV(t: any): Vector3?
	if type(t) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(t[1] or t.x), tonumber(t[2] or t.y), tonumber(t[3] or t.z)
	if not x or not y or not z or x ~= x or y ~= y or z ~= z then
		return nil
	end
	return Vector3.new(x, y, z)
end

local function send(player: Player, payload: any)
	local e = remotes.Event
	if e and player.Parent then
		e:FireClient(player, payload)
	end
end

local function law(): any
	return ctx and ctx.law
end

-- the player may fight: alive, not cuffed / in jail / riding / working a shift
local function canAct(player: Player): (boolean, string?)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false, "dead"
	end
	if hum.Sit or hum.SeatPart then
		return false, "seated"
	end
	if player:GetAttribute("LawCuffed") or ((player:GetAttribute("LawJail") or 0) :: number) > 0 then
		return false, "cuffed"
	end
	if player:GetAttribute("OnShift") or player:GetAttribute("InTaxi") then
		return false, "busy"
	end
	return true, nil
end

local function typeOf(id: string, claimed: any): (string, any)
	local c = Citizens and Citizens.get and Citizens.get(id)
	if c then
		return c.type or "plain", c
	end
	if type(claimed) == "string" and FS.PED_TYPES[claimed] then
		return claimed, nil
	end
	return "plain", nil
end

local function hpRec(tab: { [string]: HpRec }, id: string, max: number): HpRec
	local rec = tab[id]
	local t = now()
	if not rec then
		rec = { hp = max, max = max, t = t }
		tab[id] = rec
	else
		-- left alone a while: they get their breath back
		local idle = t - rec.t
		if idle > FS.REGEN_DELAY then
			rec.hp = math.min(rec.max, rec.hp + (idle - FS.REGEN_DELAY) * FS.REGEN)
		end
	end
	return rec
end

local function keyModel(id: string): Model?
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if not f then
		return nil
	end
	for _, m in f:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("NpcId") == id then
			return m
		end
	end
	return nil
end

-- who they are decides what they do
-- who they are: a named citizen's traits (GwangalliMindShared); an anonymous pedestrian gets a
-- steady personality from its id (the same "x12" is always the same kind of person)
local function personality(id: string, typeId: string, c: any): (number, number, string)
	if c and MindShared and MindShared.traits then
		local ok, t = pcall(MindShared.traits, c)
		if ok and type(t) == "table" then
			return t.brave or 0.5, t.temper or 0.5, t.arch or typeId
		end
	end
	local h = 0
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 100003
	end
	return 0.2 + (h % 71) / 100, 0.2 + ((h // 71) % 71) / 100, typeId
end

-- what they do after this hit. hits = how many times this player hit them lately
local function decide(id: string, typeId: string, c: any, hpLeft: number, max: number, hits: number): string
	if typeId == "police" then
		return "arrest"
	end
	local brave, temper, arch = personality(id, typeId, c)
	if arch == "rider" and typeId ~= "violent" then
		-- 배달 라이더: startled, they get away (on the scooter) or call; only the toughest hit back
		if hpLeft <= max * 0.3 then
			return if r() < 0.5 then "cower" else "flee"
		end
		if brave >= 0.85 and hits >= 2 and r() < 0.5 then
			return "fight"
		end
		return if r() < 0.4 + (1 - brave) * 0.3 then "flee" else "report"
	end
	if hpLeft <= max * 0.3 then
		-- beaten: give up, get away, or (the toughest) one last go
		if brave > 0.75 and r() < 0.3 then
			return "fight"
		end
		return if r() < 0.45 then "cower" else "flee"
	end
	if typeId == "violent" or arch == "thug" or arch == "punk" or arch == "hothead" then
		return "fight"
	end
	if typeId == "drunk" or arch == "drunk" then
		local x = r()
		return if x < 0.5 then "fight" elseif x < 0.75 then "warn" else "flee"
	end
	if brave < 0.35 then
		return if r() < 0.75 then "flee" else "report" -- the timid ones just get away
	end
	if hits <= 1 then
		-- the first one: a warning, a call to the police or they get away
		local x = r()
		return if x < 0.35 + temper * 0.3 then "warn" elseif x < 0.75 then "report" else "flee"
	end
	-- it keeps happening: the brave / hot-tempered hit back
	if brave + temper * 0.5 > 0.85 then
		return "fight"
	end
	return if r() < 0.5 then "report" else "flee"
end

local function noteCrime(player: Player, id: string, kind: string, pos: Vector3, c: any, police: boolean)
	local L = law()
	if not L then
		return
	end
	lastCrime[player] = lastCrime[player] or {}
	local key = id .. ":" .. kind
	local last = lastCrime[player][key]
	if kind ~= "kill" and last and now() - last < 60 then
		return -- one 폭행 per victim and minute (a flurry of punches is one assault)
	end
	lastCrime[player][key] = now()
	pcall(L.crime, player, kind, { pos = pos, victim = id, victimName = c and c.name or nil, source = "fight", police = police })
end

local function award(player: Player, id: string)
	local s = ctx and ctx.social
	if s and type(s.award) == "function" then
		pcall(s.award, player, id, "assault")
	end
end

local function broadcastDown()
	local e = remotes.Event
	if e then
		e:FireAllClients({ kind = "down", ids = hospital })
	end
end

-- one landed hit on an NPC. p = { kind = "ped" | "npc", id, pos?, ptype?, attack?, power? };
-- trusted = called by server code that already checked the hit (어깨빵, the talk card's 때리기)
local function onPunch(player: Player, p: any, trusted: boolean?): any?
	if type(p) ~= "table" or type(p.id) ~= "string" or #p.id > 40 then
		return nil
	end
	local ok, why = canAct(player)
	if not ok then
		send(player, { kind = "miss", reason = why })
		return nil
	end
	local t = now()
	if not trusted and t - (lastPunch[player] or 0) < FS.COOLDOWN * 0.5 then
		return nil
	end
	lastPunch[player] = t
	local root = rootOf(player)
	if not root then
		return
	end
	local id = p.id
	local isKey = p.kind == "npc"
	local pos: Vector3?
	local model: Model? = nil
	if isKey then
		model = keyModel(id)
		local mr = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
		pos = if mr and mr:IsA("BasePart") then mr.Position else nil
		-- the server copy of a walking key NPC can lag behind a little: the client's claim within reason
		local claimed = unpackV(p.pos)
		if pos and claimed and flat(pos, claimed) < 14 then
			pos = claimed
		end
	else
		pos = unpackV(p.pos)
	end
	if trusted and not pos then
		pos = root.Position + root.CFrame.LookVector * 2 -- (the caller checked the reach itself)
	end
	-- a landed hit is close: anything farther is no hit at all (reach + client lag)
	if not pos or flat(pos, root.Position) > FS.RANGE + 1.5 or math.abs(pos.Y - root.Position.Y) > 6 then
		send(player, { kind = "miss", reason = "far" })
		return nil
	end
	if not isKey and not (Citizens and Citizens.get and Citizens.get(id)) and not string.match(id, "^x%d+$") then
		return
	end
	if not isKey and hospital[id] and os.time() < hospital[id] then
		return -- (a client still showing somebody who went down)
	end
	koUntil[player] = koUntil[player] or {}
	if not isKey and (koUntil[player][id] or 0) > t then
		return -- already down
	end
	local typeId, c = typeOf(id, p.ptype)
	local max = FS.maxHp(typeId)
	local testHp = workspace:GetAttribute("GwangalliStreetLifeDebug") == true and tonumber(workspace:GetAttribute("GwangalliFightTestHp"))
	if testHp and testHp > 0 then
		max = testHp -- test only: a short fight to the KO
	end
	local tab = if isKey then keyHp else (function()
		pedHp[player] = pedHp[player] or {}
		return pedHp[player]
	end)()
	local rec = hpRec(tab, id, max)
	local strength = tonumber(player:GetAttribute("Strength")) or tonumber(player:GetAttribute("GwStrength")) or 0
	local dmg, crit, outcome = FS.roll(r, strength)
	local attack = if type(p.attack) == "string" and FS.ATTACK[p.attack] then p.attack else "punch"
	if attack == "car" then
		-- hit by a car: the speed is the damage (light / hurt / thrown)
		local sp = math.clamp(tonumber(p.speed) or 0, 0, 120)
		dmg = if sp < 15 then 6 + sp * 0.3 elseif sp < 35 then 20 + (sp - 15) * 1.5 else 60 + (sp - 35) * 2.5
		crit = false
		outcome = if sp < 15 then "stagger" else "knockdown"
	end
	local at = FS.ATTACK[attack]
	dmg = math.max(1, math.floor(dmg * at.dmg * math.clamp(tonumber(p.power) or 1, 0.3, 2) + 0.5))
	if at.noCrit then
		crit = false
	end
	if type(p.outcome) == "string" and (p.outcome == "stagger" or p.outcome == "knockdown") then
		outcome = p.outcome -- (the caller already played this fall, e.g. 어깨빵)
	elseif at.knock == "stagger" and outcome == "knockdown" and not crit then
		outcome = "stagger"
	elseif at.knock == "knockdown" then
		outcome = "knockdown"
	end
	hitCount[player] = hitCount[player] or {}
	local hc = hitCount[player][id]
	if not hc or t - hc.t > 120 then
		hc = { n = 0, t = t }
		hitCount[player][id] = hc
	end
	hc.n += 1
	hc.t = t
	rec.hp -= dmg
	rec.t = t
	local police = typeId == "police"
	local react
	if isKey and rec.hp < FS.KEY_MIN_HP then
		rec.hp = FS.KEY_MIN_HP
		outcome = "knockdown"
	end
	if rec.hp <= 0 then
		rec.hp = 0
		outcome = "ko"
		react = "ko"
	else
		react = if p.noReact then "none" else decide(id, typeId, c, rec.hp, max, hc.n)
		if attack == "car" and react == "fight" then
			react = if r() < 0.6 then "warn" else "report" -- (nobody punches a car)
		end
	end
	local d = pos - root.Position
	local dl = math.max(0.05, Vector3.new(d.X, 0, d.Z).Magnitude)
	local dx, dz = d.X / dl, d.Z / dl
	-- the crime and the people who care (a shove the caller handles itself: no 폭행 here)
	if not p.noCrime then
		noteCrime(player, id, if attack == "car" then "reckless" elseif police then "assault_police" else "assault", pos, c, police)
	end
	if outcome == "ko" then
		noteCrime(player, id, "kill", pos, c, police)
		koUntil[player][id] = t + FS.KO_DOWN + 2
		if c then
			hospital[id] = os.time() + FS.HOSPITAL_S
			broadcastDown()
		end
		local L = law()
		if L then
			task.delay(2.5, function()
				if player.Parent then
					pcall(L.report, player, "witness", pos)
				end
			end)
		end
	elseif react == "report" then
		local L = law()
		if L then
			task.delay(3 + r() * 2, function()
				if player.Parent then
					pcall(L.report, player, "victim", pos)
				end
			end)
		end
	elseif react == "fight" then
		brawls[player] = brawls[player] or {}
		brawls[player][id] = { untilT = t + FS.BRAWL_S[1] + r() * (FS.BRAWL_S[2] - FS.BRAWL_S[1]), last = 0 }
	end
	if c then
		award(player, id)
	end
	-- a key NPC falls for everybody (NpcKnock)
	if isKey and NPC and type(NPC.knock) == "function" and type(p.outcome) ~= "string" then
		pcall(NPC.knock, id, dx, dz, if outcome == "stagger" then "stagger" else "knockdown", player)
	end
	local line = pick(FS.LINES[react] or FS.LINES.hit)
	dbg("hit", attack, id, typeId, "dmg", dmg, "hp", rec.hp, "/", max, outcome, react, "hits", hc.n)
	local res = { kind = "hit", target = if isKey then "npc" else "ped", id = id, dmg = dmg, hp = math.floor(rec.hp + 0.5), max = max, outcome = outcome, react = react, line = line, crit = crit, dx = dx, dz = dz, ko = if outcome == "ko" then FS.KO_DOWN else nil, attack = attack }
	if not (p.silent == true) then
		send(player, res)
	elseif not isKey then
		-- the caller plays the fall: only the short memory goes to the client (and a KO)
		send(player, { kind = "remember", id = id, mood = if react == "fight" or react == "warn" or react == "none" then "anger" else "fear" })
		if outcome == "ko" then
			send(player, { kind = "hit", target = "ped", id = id, outcome = "ko", react = "ko", dx = dx, dz = dz, ko = FS.KO_DOWN })
		end
	end
	return res
end

-- for server code: a hit that already landed (another combat system, 어깨빵, the talk card)
function Fight.applyHit(player: Player, p: any): any?
	return onPunch(player, p, true)
end

-- the HP side of an NPC for this player: { hp, max, down } (down = KO now / in hospital)
function Fight.state(player: Player?, id: string): any
	local t = now()
	local c = Citizens and Citizens.get and Citizens.get(id)
	local isKey = c ~= nil and c.key == true
	local rec = if isKey then keyHp[id] else (player and pedHp[player] and pedHp[player][id])
	local down = (hospital[id] ~= nil and os.time() < hospital[id]) or (player ~= nil and koUntil[player] ~= nil and (koUntil[player][id] or 0) > t)
	return { hp = rec and rec.hp or nil, max = rec and rec.max or nil, down = down == true }
end

-- 강탈 (robbery) rules (GwangalliRobShared): who may be robbed, for how much, nothing from the down
local robbed: { [Player]: { [string]: number } } = {}
function Fight.robInfo(player: Player?, id: string): any?
	if not Rob or type(id) ~= "string" then
		return nil
	end
	local c = Citizens and Citizens.get and Citizens.get(id)
	local st = Fight.state(player, id)
	local state = "ok"
	if player and robbed[player] and (robbed[player][id] or 0) > now() then
		state = "robbed"
	end
	local info = Rob.info(id, c, nil, state, st.down)
	info.hp, info.max = st.hp, st.max
	return info
end

local function onNpcHit(player: Player, p: any)
	if type(p) ~= "table" or type(p.id) ~= "string" then
		return
	end
	local b = brawls[player] and brawls[player][p.id]
	local t = now()
	if not b or t > b.untilT + 2 then
		return -- nobody is fighting this player
	end
	if t - b.last < FS.NPC_SWING_GAP then
		return
	end
	local root = rootOf(player)
	local pos = unpackV(p.pos)
	if not root or not pos or flat(pos, root.Position) > FS.NPC_REACH + 3 then
		return
	end
	b.last = t
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	local dmg = rng:NextInteger(FS.PLAYER_DMG[1], FS.PLAYER_DMG[2])
	local hp = math.max(FS.PLAYER_MIN_HP, hum.Health - dmg)
	if hp < hum.Health then
		hum.Health = hp
	end
	send(player, { kind = "hurt", dmg = dmg, hp = math.floor(hum.Health + 0.5), by = p.id })
end

-- an NPC fight seen by a bystander: an officer walks over and breaks it up
local lastFightCall = 0
local function onNpcFight(player: Player, p: any)
	if type(p) ~= "table" then
		return
	end
	local pos = unpackV(p.pos)
	local root = rootOf(player)
	if not pos or not root or flat(pos, root.Position) > 90 or now() - lastFightCall < 40 then
		return
	end
	lastFightCall = now()
	local L = law()
	local Pol = L and L.children and L.children.Police
	if not Pol or type(Pol.newOfficer) ~= "function" then
		return
	end
	local at = Pol.hiddenSpot and Pol.hiddenSpot(pos, 40, 80)
	if not at then
		return
	end
	local o = Pol.newOfficer(at, "patrol", nil)
	if not o then
		return
	end
	o.role = "post" -- (no block: it just goes there; patrol logic resumes after the call)
	o.state = "fightcall"
	Pol.assignGoal(o, pos, 11, nil)
	task.spawn(function()
		local t0 = now()
		while not o.gone and now() - t0 < 30 do
			task.wait(0.5)
			if Pol.arrived(o) then
				break
			end
		end
		if o.gone then
			return
		end
		Pol.faceTo(o, pos)
		if Pol.say then
			pcall(Pol.say, o, pick(FS.BREAKUP), 3.5)
		end
		send(player, { kind = "breakup", pos = { pos.X, pos.Y, pos.Z } })
		task.wait(6)
		if not o.gone then
			o.role = "patrol"
			o.state = "patrol"
			o.pauseUntil = now() + 4
		end
	end)
end

-- a street pedestrian hit by this player's car (the client saw the contact): checked against the car
-- the player really sits in and how fast it really goes
local lastCarHit: { [Player]: number } = {}
local function onCarHit(player: Player, p: any)
	if type(p) ~= "table" or type(p.id) ~= "string" then
		return
	end
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local root = rootOf(player)
	local pos = unpackV(p.pos)
	if not seat or not root or not pos or flat(pos, root.Position) > 14 then
		return
	end
	if now() - (lastCarHit[player] or 0) < 0.4 then
		return
	end
	lastCarHit[player] = now()
	local okV, vel = pcall(function()
		return seat.AssemblyLinearVelocity
	end)
	local real = if okV and typeof(vel) == "Vector3" then Vector3.new(vel.X, 0, vel.Z).Magnitude else 0
	local claimed = tonumber(p.speed) or 0
	-- (physics speed when there is one; a client claim is never taken above it + a margin)
	local sp = if real > 1 then math.min(claimed, real + 8) else math.min(claimed, 60)
	if sp < 5 then
		return
	end
	onPunch(player, { kind = "ped", id = p.id, pos = p.pos, ptype = p.ptype, attack = "car", speed = sp, outcome = if sp < 15 then "stagger" else "knockdown" }, true)
end

-- an NPC starts a fight with this player (a 걸렁뱅이 refused money, a drunk picked a quarrel):
-- their swings may land for a while (each still checked by onNpcHit)
function Fight.startBrawl(player: Player, id: string, secs: number?)
	if type(id) ~= "string" or #id > 40 then
		return false
	end
	brawls[player] = brawls[player] or {}
	brawls[player][id] = { untilT = now() + (secs or (FS.BRAWL_S[1] + r() * (FS.BRAWL_S[2] - FS.BRAWL_S[1]))), last = 0 }
	return true
end

-- the client says a street NPC picked the fight: only the types that do that, close by, not too often
local AGGRESSIVE = { drunk = true, punk = true, thug = true, violent = true, hothead = true }
local lastStart: { [Player]: number } = {}
local function onNpcStart(player: Player, p: any)
	if type(p) ~= "table" or type(p.id) ~= "string" then
		return
	end
	local t = now()
	if t - (lastStart[player] or 0) < 6 then
		return
	end
	local typeId, c = typeOf(p.id, p.ptype)
	local arch = c and MindShared and MindShared.archOf and MindShared.archOf(c) or typeId
	if not AGGRESSIVE[typeId] and not AGGRESSIVE[arch] then
		return
	end
	local root = rootOf(player)
	local pos = unpackV(p.pos)
	if not root or not pos or flat(pos, root.Position) > 12 then
		return
	end
	lastStart[player] = t
	Fight.startBrawl(player, p.id)
end

local function onAction(player: Player, kind: any, p: any)
	local ok, err = pcall(function()
		if kind == "carHit" then
			onCarHit(player, p)
		elseif kind == "punch" then
			onPunch(player, p)
		elseif kind == "npcHit" then
			onNpcHit(player, p)
		elseif kind == "npcFight" then
			onNpcFight(player, p)
		elseif kind == "npcStart" then
			onNpcStart(player, p)
		end
	end)
	if not ok then
		warn("[GwangalliFight] " .. tostring(kind) .. ": " .. tostring(err))
	end
end

function Fight.onLeave(player: Player)
	pedHp[player] = nil
	lastPunch[player] = nil
	brawls[player] = nil
	lastCrime[player] = nil
	koUntil[player] = nil
	hitCount[player] = nil
	robbed[player] = nil
	lastStart[player] = nil
end

function Fight.onLoaded(player: Player)
	send(player, { kind = "down", ids = hospital })
end

function Fight.inHospital(id: string): boolean
	return (hospital[id] or 0) > os.time()
end

function Fight.init(context: any)
	ctx = context
	local function opt(name: string): any
		local m = ReplicatedStorage:FindFirstChild(name)
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok then
				return res
			end
		end
		return nil
	end
	FS = opt("GwangalliFightShared")
	Citizens = opt("GwangalliCitizens")
	MindShared = opt("GwangalliMindShared")
	Rob = opt("GwangalliRobShared")
	if not FS then
		warn("[GwangalliFight] GwangalliFightShared missing: street fights off")
		return
	end
	local npcModule = script.Parent and script.Parent:FindFirstChild("NPC")
	if npcModule and npcModule:IsA("ModuleScript") then
		local ok, res = pcall(require, npcModule)
		if ok and type(res) == "table" then
			NPC = res
		end
	end
	local folder = ReplicatedStorage:FindFirstChild(FS.Folder)
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = FS.Folder
	local a = Instance.new("RemoteEvent")
	a.Name = FS.Remote.Action
	a.Parent = folder
	local e = Instance.new("RemoteEvent")
	e.Name = FS.Remote.Event
	e.Parent = folder
	remotes.Action, remotes.Event = a, e
	a.OnServerEvent:Connect(onAction)
	folder.Parent = ReplicatedStorage
	Players.PlayerRemoving:Connect(Fight.onLeave)
	-- ServerStorage.GwangalliNPCHitAPI: Invoke("hit", player, { kind, id, pos?, attack?, power? }) -> result
	local ServerStorage = game:GetService("ServerStorage")
	local old = ServerStorage:FindFirstChild("GwangalliNPCHitAPI")
	if old then
		old:Destroy()
	end
	local sapi = Instance.new("BindableFunction")
	sapi.Name = "GwangalliNPCHitAPI"
	sapi.OnInvoke = function(op: any, pl: any, spec: any)
		if op == "hit" and typeof(pl) == "Instance" and pl:IsA("Player") then
			return Fight.applyHit(pl, spec)
		end
		return nil
	end
	sapi.Parent = ServerStorage
	-- ServerStorage.GwangalliNPCRobAPI: ("info", player, id) -> GwangalliRobShared info + hp / max;
	-- ("robbed", player, id) -> marks them robbed (the crime system calls it after its own roll);
	-- ("rules") -> Rob.KIND. No money / wanted / police here: that is the crime system's.
	local oldR = ServerStorage:FindFirstChild("GwangalliNPCRobAPI")
	if oldR then
		oldR:Destroy()
	end
	local rapi = Instance.new("BindableFunction")
	rapi.Name = "GwangalliNPCRobAPI"
	rapi.OnInvoke = function(method: any, player: any, id: any): any
		if method == "info" then
			return Fight.robInfo(if typeof(player) == "Instance" and player:IsA("Player") then player else nil, id)
		elseif method == "robbed" and typeof(player) == "Instance" and player:IsA("Player") and type(id) == "string" and Rob then
			local info = Fight.robInfo(player, id)
			if not info or not info.robbable then
				return false
			end
			robbed[player] = robbed[player] or {}
			robbed[player][id] = now() + Rob.ROBBED_COOLDOWN
			return true
		elseif method == "rules" then
			return Rob and Rob.KIND or nil
		end
		return nil
	end
	rapi.Parent = ServerStorage
	-- ServerStorage.GwangalliNPCEvents: 생활콘텐츠 (or any server system) says "an incident happened";
	-- the NPC system on that player's client casts and plays it (GwangalliStreetLife Mind.incident):
	--   Invoke("incident", player, kind, { pos = Vector3?, id = string? }) -> true when sent
	--   kind = "drunk_quarrel" | "stall_fight" | "street_fight" | "lost" | "help" | "suspicious"
	local oldE = ServerStorage:FindFirstChild("GwangalliNPCEvents")
	if oldE then
		oldE:Destroy()
	end
	local ev = Instance.new("BindableFunction")
	ev.Name = "GwangalliNPCEvents"
	ev.OnInvoke = function(op: any, pl: any, kind: any, data: any)
		if op ~= "incident" or typeof(pl) ~= "Instance" or not pl:IsA("Player") or type(kind) ~= "string" then
			return false
		end
		local d = if type(data) == "table" then data else {}
		local pos = if typeof(d.pos) == "Vector3" then { d.pos.X, d.pos.Y, d.pos.Z } else nil
		send(pl, { kind = "incident", what = kind, pos = pos, id = if type(d.id) == "string" then d.id else nil })
		return true
	end
	ev.Parent = ServerStorage
	ctx.fight = Fight
	print("[GwangalliFight] ready (punch / HP / KO / fight back)")
end

return Fight
