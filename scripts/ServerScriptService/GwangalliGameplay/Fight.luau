-- GwangalliGameplay/Fight (server feature module; owner: npc): 길거리 싸움 — the player's 👊 주먹 on
-- NPCs, NPC HP / 쓰러짐 (KO), how the person hit reacts (fight back / flee / report / arrest) and the
-- swings of an NPC that fights back. Contract: ReplicatedStorage.GwangalliFightShared.
--
--   * The server owns every number: HP per (player, pedestrian) — street pedestrians exist on one
--     client only — and per key NPC (shared); damage, crits, knockdowns, the KO; the reaction (by type /
--     personality, GwangalliMindShared.traits); the crime (Law: 폭행 once per victim and minute, 폭행치사
--     for a KO, a phone report makes the police know at once); 호감도 (ctx.social.award "assault").
--   * Clients only ask and play: the punch lunge, the fall / KO, the HP bar, the brawl.
--   * Key NPCs (shops, quests) never go below FightShared.KEY_MIN_HP and never stay down. The Law units
--     on foot (police_ / swat_ / ems_) can: at 0 HP they go down and stay down (Law/Police.knocked,
--     NpcDown) until the ambulance takes them / the time runs out.
--   * Every hit gets a visible reaction: street pedestrians on this player's client, NPC.luau key NPCs
--     (NPC.knock), a module's own NPC (Fight.hitHooks), any other rig in GwangalliNPCs / tagged
--     GwShopStaff (NpcKnock stagger here). An NPC.luau key NPC that fights back swings at the player
--     from the server once he is back on his feet (a few swings, each only within reach and facing the
--     player: keyFight); a rig another brain keeps walking warns instead. 알바 / minigame rigs
--     (FightShared.foreign) are not hit at all.
--   * A named citizen who went down is off the street for HOSPITAL_S ("down" event: clients skip them).
--   * NPC swings ("npcHit") count only from an NPC this server put in a brawl with that player, close
--     enough, not too often; they never take the player below PLAYER_MIN_HP.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fight = {}
Fight.hitHooks = {} :: { [string]: (Player, string, any) -> (string?, string?) } -- [NpcId prefix] = hook
local Rob: any = nil -- GwangalliRobShared (강탈 rules, read by the crime systems)

local ctx: any
local FS: any
local Citizens: any
local MindShared: any
local NPC: any
local BumpS: any -- GwangalliBumpShared (the fall / stagger timeline every client plays from NpcKnock)
local VehS: any -- GwangalliVehiclesShared (the drive system's tag / attribute / part names)

local remotes: { Action: RemoteEvent?, Event: RemoteEvent? } = {}

type HpRec = { hp: number, max: number, t: number, by: number? } -- t / by = the last hit, who (UserId)
local pedHp: { [Player]: { [string]: HpRec } } = {} -- street pedestrians (per player: client-side people)
local keyHp: { [string]: HpRec } = {} -- key NPCs (one world)
local lastPunch: { [Player]: number } = {}
local brawls: { [Player]: { [string]: { untilT: number, last: number } } } = {}
local lastCrime: { [Player]: { [string]: number } } = {}
local hospital: { [string]: number } = {} -- citizen id -> os.time() when they are back
local koUntil: { [Player]: { [string]: number } } = {}
local hitCount: { [Player]: { [string]: { n: number, t: number } } } = {} -- short memory (2 min)
local pedSn: { [Player]: { [string]: number } } = {} -- anonymous "x12": the spawn serial its HP belongs to
local keyFights: { [string]: number } = {} -- key NPC id -> the running swing loop (Fight.keyFight)

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

-- the player may fight: alive, not cuffed / in jail / riding / working a shift. inCar = the player's own
-- car hit somebody (onCarHit checked the driver's seat): sitting at the wheel, even on a shift, counts
local function canAct(player: Player, inCar: boolean?): (boolean, string?)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false, "dead"
	end
	if not inCar and (hum.Sit or hum.SeatPart) then
		return false, "seated"
	end
	if player:GetAttribute("LawCuffed") or ((player:GetAttribute("LawJail") or 0) :: number) > 0 then
		return false, "cuffed"
	end
	if player:GetAttribute("InTaxi") or (not inCar and player:GetAttribute("OnShift")) then
		return false, "busy"
	end
	return true, nil
end

local function typeOf(id: string, claimed: any): (string, any)
	local c = Citizens and Citizens.get and Citizens.get(id)
	if c then
		return c.type or "plain", c
	end
	-- server units (GwangalliGameplay/Law): 특임대 / police officers / 119 crews
	if string.sub(id, 1, 5) == "swat_" then
		return "swat", nil
	elseif string.sub(id, 1, 7) == "police_" then
		return "police", nil
	elseif string.sub(id, 1, 4) == "ems_" then
		return "plain", nil
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

local CollectionService = game:GetService("CollectionService")
local function keyModel(id: string): Model?
	local f = workspace:FindFirstChild("GwangalliNPCs")
	for _, m in (if f then f:GetChildren() else {}) do
		if m:IsA("Model") and m:GetAttribute("NpcId") == id then
			return m
		end
	end
	-- shop staff (GwangalliGameplay/ShopStaff: workspace.GwangalliShopStaff or a clerk inside a shop model)
	for _, m in CollectionService:GetTagged("GwShopStaff") do
		if m:IsA("Model") and m:GetAttribute("NpcId") == id and m:IsDescendantOf(workspace) then
			return m
		end
	end
	return nil
end

-- the Law units on foot (Law/Police officers, Law/Swat 특임대, Law/Rescue 119): they can go down for good
local function lawRigId(id: string): boolean
	return string.sub(id, 1, 7) == "police_" or string.sub(id, 1, 5) == "swat_" or string.sub(id, 1, 4) == "ems_"
end

local function lawPolice(): any
	local L = ctx and ctx.law
	return L and L.children and L.children.Police
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
local GUN_WORDS = { "gun", "pistol", "rifle", "glock", "revolver", "shotgun", "smg", "uzi", "ak47", "m4", "deagle", "총", "권총", "소총", "엽총" }
local function armed(player: Player?): boolean
	local char = player and player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if not tool then
		return false
	end
	local w = tool:GetAttribute("GwWeapon") or tool:GetAttribute("WeaponType")
	if w == "gun" or tool:GetAttribute("IsGun") == true then
		return true
	end
	local n = string.lower(tool.Name)
	for _, word in GUN_WORDS do
		if string.find(n, word, 1, true) then
			return true
		end
	end
	return false
end

-- the situation around a hit: the player's gun, police close by, the relation (-100..100)
local function situation(player: Player?, id: string, pos: Vector3?): any
	local sit = { armed = armed(player), police = false, rel = 0 }
	local L = law()
	local P = L and L.children and L.children.Police
	if P and pos and P.nearestOfficer then
		local ok, o = pcall(P.nearestOfficer, pos, 35)
		sit.police = ok and o ~= nil
	end
	if player and ctx.mind and type(ctx.mind.relOf) == "function" then
		local ok, r = pcall(ctx.mind.relOf, player, id)
		sit.rel = if ok and type(r) == "number" then r else 0
	end
	-- crew-mates out with them right now (friends back each other up)
	sit.allies = 0
	if Citizens and type(Citizens.companions) == "function" then
		local ok, list = pcall(Citizens.companions, id, game:GetService("Lighting").ClockTime)
		sit.allies = if ok and type(list) == "table" then #list else 0
	end
	return sit
end

local function decide(id: string, typeId: string, c: any, hpLeft: number, max: number, hits: number, sit: any?): string
	if typeId == "police" or typeId == "swat" then
		return "arrest"
	end
	local brave, temper, arch = personality(id, typeId, c)
	local s = sit or {}
	local violent = typeId == "violent" or arch == "thug" or arch == "punk" or arch == "hothead"
	-- a gun in the player's hand: even the hard ones mostly back off
	if s.armed then
		if violent and brave > 0.8 and r() < 0.25 then
			return "fight"
		end
		return if r() < 0.5 then "flee" elseif r() < 0.6 then "cower" else "report"
	end
	-- the police right there: let them handle it (the hot-headed don't care)
	if s.police and not (arch == "hothead" or arch == "thug") and r() < 0.7 then
		return if violent then "warn" else "report"
	end
	-- an old grudge: hit back at once
	if (s.rel or 0) <= -60 and (violent or temper > 0.6) and hpLeft > max * 0.3 then
		return "fight"
	end
	-- friends right beside them: braver together (the timid still only warn)
	if (s.allies or 0) >= 1 and hpLeft > max * 0.4 then
		local push = math.min(2, s.allies) * 0.2
		if brave + temper * 0.5 + push > 0.85 and r() < 0.5 + push then
			return "fight"
		end
		if brave < 0.35 and r() < 0.5 then
			return "warn"
		end
	end
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
	-- hurt (30-60 %): ordinary people back off more often
	if hpLeft <= max * 0.6 and not violent and r() < 0.35 then
		return if r() < 0.5 then "warn" else "flee"
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

-- -> true when Law noted it (the caller tells the crowd, once per hit)
local function noteCrime(player: Player, id: string, kind: string, pos: Vector3, c: any, police: boolean): boolean
	local L = law()
	if not L then
		return false
	end
	lastCrime[player] = lastCrime[player] or {}
	local key = id .. ":" .. kind
	local last = lastCrime[player][key]
	if kind ~= "kill" and last and now() - last < 60 then
		return false -- one 폭행 per victim and minute (a flurry of punches is one assault)
	end
	lastCrime[player][key] = now()
	local ok, noted = pcall(L.crime, player, kind, { pos = pos, victim = id, victimName = c and c.name or nil, source = "fight", police = police })
	return ok and noted == true
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

-- an NPC's swing landed on this player: FightShared damage by the attack kind (never below
-- PLAYER_MIN_HP). outcome = the client still has to play the fall (a server-side swing); nil = the
-- client already played it (a street brawler's own swing)
local function hurtPlayer(player: Player, byId: string, atk: string, ux: number?, uz: number?, outcome: string?): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end
	local a = FS.ATTACK[atk]
	local dmg = rng:NextInteger(FS.PLAYER_DMG[1], FS.PLAYER_DMG[2])
	dmg = math.max(1, math.floor(dmg * (if a then a.dmg else 1) + 0.5))
	local hp = math.max(FS.PLAYER_MIN_HP, hum.Health - dmg)
	if hp < hum.Health then
		hum.Health = hp
	end
	send(player, { kind = "hurt", dmg = dmg, hp = math.floor(hum.Health + 0.5), by = byId, attack = atk, dx = ux, dz = uz, outcome = outcome })
	return true
end

-- a key NPC (a server rig: NPC.luau, shop staff, ...) fights back: up to 3 swings from where he stands
-- (NPC.knock halted him and he faces the player while the player is close); each lands only within
-- reach and at about the same height, a player who walks off is not chased
local emoteSeq = 0
local function keyEmote(id: string, model: Model?, name: string)
	if NPC and type(NPC.state) == "function" and NPC.state(id) then
		pcall(NPC.react, id, name)
	elseif model then
		emoteSeq += 1
		model:SetAttribute("NpcEmote", name .. "#" .. emoteSeq .. "#" .. string.format("%.2f", workspace:GetServerTimeNow()))
	end
end

-- seconds until the rig's current fall / stagger (NpcKnock, as every client plays it) is over, with a
-- beat after it (a knockdown: NPC.luau's "shake" on getting up); 0 = he stands
local function knockLeft(model: Model): number
	local s = model:GetAttribute("NpcKnock")
	if type(s) ~= "string" then
		return 0
	end
	local parts = string.split(s, "|")
	local t0 = tonumber(parts[1])
	if not t0 then
		return 0
	end
	local B = BumpS or {}
	local dur = if parts[4] == "stagger" then (B.STAGGER_DUR or 0.9) + 0.3 else (B.KNOCK_DUR or 1.4) + (B.GETUP_DUR or 0.7) + 0.8
	return math.max(0, t0 + dur - workspace:GetServerTimeNow())
end

local function keyFight(player: Player, id: string)
	local seq = (keyFights[id] or 0) + 1
	keyFights[id] = seq
	task.spawn(function()
		for _ = 1, 3 do
			task.wait(1.1 + r() * 0.5)
			-- (still on the ground / getting up / staggering from this hit or a later one: he swings after)
			local m0 = keyModel(id)
			local left = if m0 then knockLeft(m0) else 0
			if left > 0 then
				task.wait(left)
			end
			if keyFights[id] ~= seq or not player.Parent then
				return
			end
			local model = keyModel(id)
			local mr = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
			local root = rootOf(player)
			if not model or not mr or not mr:IsA("BasePart") or not root then
				break
			end
			local st = NPC and type(NPC.state) == "function" and NPC.state(id)
			if st and st.hidden then
				break
			end
			-- (a player who sat down / got in a car is out of it)
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum and (hum.Sit or hum.SeatPart) then
				break
			end
			local sp = if st and typeof(st.pos) == "Vector3" then st.pos else mr.Position
			local here = Vector3.new(sp.X, mr.Position.Y, sp.Z)
			local d = flat(root.Position, here)
			dbg("keyFight", id, "swing at", string.format("%.1f", d))
			if d > 9 or model:GetAttribute("NpcDown") ~= nil then
				break
			end
			-- only a swing he can see: facing the player (NpcYaw degrees, CFrame.Angles(0, rad(yaw), 0))
			local yaw = if st and type(st.yaw) == "number" then st.yaw else tonumber(model:GetAttribute("NpcYaw"))
			local dl = math.max(d, 0.05)
			local ux, uz = (root.Position.X - here.X) / dl, (root.Position.Z - here.Z) / dl
			if yaw and d > 0.5 and (-math.sin(math.rad(yaw)) * ux - math.cos(math.rad(yaw)) * uz) < 0.5 then
				dbg("keyFight", id, "not facing: no swing")
				continue
			end
			keyEmote(id, model, if r() < 0.6 then "cb_jab" else "cb_hook")
			if d <= FS.NPC_REACH + 1 and math.abs(root.Position.Y - here.Y) < 4 then
				hurtPlayer(player, id, "punch", ux, uz, if r() < 0.2 then "knockdown" else "stagger")
			end
		end
		if keyFights[id] == seq then
			keyFights[id] = nil
			if player.Parent then
				send(player, { kind = "say", id = id, line = pick(FS.LINES.brawl_end) })
			end
		end
	end)
end

-- one landed hit on an NPC. p = { kind = "ped" | "npc", id, pos?, ptype?, attack?, power? };
-- trusted = called by server code that already checked the hit (어깨빵, the talk card's 때리기)
local function onPunch(player: Player, p: any, trusted: boolean?): any?
	if type(p) ~= "table" or type(p.id) ~= "string" or #p.id > 40 then
		return nil
	end
	-- (only server code may claim a car hit: onCarHit checked the seat and the speed)
	local carHit = trusted == true and p.attack == "car"
	local ok, why = canAct(player, carHit)
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
		if FS.foreign(id, model) then
			return nil -- (a 알바 / minigame rig: not this system's)
		end
		local mr = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
		pos = if mr and mr:IsA("BasePart") then mr.Position else nil
		-- the server copy of a walking key NPC can lag behind a little: the client's claim within reason
		-- (a car hit on a rig: the server's own scan, where its NpcLeg walk has it now)
		local claimed = unpackV(p.pos)
		if pos and claimed and (carHit or flat(pos, claimed) < 14) then
			pos = claimed
		end
	else
		pos = unpackV(p.pos)
	end
	if trusted and not pos and not isKey then
		pos = root.Position + root.CFrame.LookVector * 2 -- (the caller checked the reach itself)
	end
	-- (a key NPC without his rig here - hidden, gone - is nobody to hit: pos stays nil, "far")
	-- a landed hit is close: anything farther is no hit at all (reach + client lag; a car hit: the bounds
	-- onCarHit / the client check, the server copy of a moving car lags the client's contact point and
	-- the driver sits higher than a walker's feet)
	-- (p.reach: the car's own check - its speed / length - only server code passes a car hit)
	local reach = if carHit then math.clamp(tonumber(p.reach) or 14, 14, 40) else FS.RANGE + 1.5
	if not pos or flat(pos, root.Position) > reach or math.abs(pos.Y - root.Position.Y) > (if carHit then 8 else 6) then
		send(player, { kind = "miss", reason = "far" })
		return nil
	end
	-- a Law unit on foot can go down for good (not one sitting in a car: that one is only knocked about)
	local lawRig = isKey and lawRigId(id)
	if lawRig and model and model:GetAttribute("NpcDown") ~= nil then
		return nil -- (down already: a body is not hit again, it never gets up)
	end
	local lawDown = lawRig and model ~= nil and model:GetAttribute("NpcSeat") == nil
	if not isKey and not (Citizens and Citizens.get and Citizens.get(id)) and not string.match(id, "^x%d+$") then
		return
	end
	if not isKey and hospital[id] and os.time() < hospital[id] then
		return -- (a client still showing somebody who went down)
	end
	koUntil[player] = koUntil[player] or {}
	if not isKey and string.match(id, "^x%d+$") then
		-- anonymous ids are reused (the crowd's free list): a new stranger (another spawn serial) or one
		-- after the last KO is over starts fresh, not with the last one's HP / hits / KO window
		local sn = tonumber(p.sn)
		pedSn[player] = pedSn[player] or {}
		local was = pedSn[player][id]
		local ko = koUntil[player][id]
		if (sn and was and was ~= sn) or (ko and ko <= t) then
			if pedHp[player] then
				pedHp[player][id] = nil
			end
			if hitCount[player] then
				hitCount[player][id] = nil
			end
			koUntil[player][id] = nil
		end
		if sn then
			pedSn[player][id] = sn
		end
	end
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
	-- (a "car" attack only from onCarHit: a client's claim of one is a punch)
	local attack = if type(p.attack) == "string" and FS.ATTACK[p.attack] and (p.attack ~= "car" or carHit) then p.attack else "punch"
	if attack == "car" then
		-- hit by a car: the speed is the damage (light / hurt / thrown)
		local sp = math.clamp(tonumber(p.speed) or 0, 0, 120)
		dmg = if sp < 15 then 6 + sp * 0.3 elseif sp < 35 then 20 + (sp - 15) * 1.5 else 60 + (sp - 35) * 2.5
		crit = false
		outcome = if sp < 15 then "stagger" elseif sp < 35 then "knockdown" else "thrown"
	end
	local at = FS.ATTACK[attack]
	dmg = math.max(1, math.floor(dmg * at.dmg * math.clamp(tonumber(p.power) or 1, 0.3, 2) + 0.5))
	if at.noCrit then
		crit = false
	end
	if type(p.outcome) == "string" and (p.outcome == "stagger" or p.outcome == "knockdown" or p.outcome == "thrown") then
		outcome = p.outcome -- (the caller already played this fall, e.g. 어깨빵)
	elseif at.knock == "stagger" and outcome == "knockdown" and not crit then
		outcome = "stagger"
	elseif at.knock == "knockdown" then
		-- a strong blow: down; a critical one throws them (a scripted slide, no physics)
		outcome = if crit and attack == "strong" then "thrown" else "knockdown"
	end
	hitCount[player] = hitCount[player] or {}
	local hc = hitCount[player][id]
	if not hc or t - hc.t > 120 then
		hc = { n = 0, t = t }
		hitCount[player][id] = hc
	end
	hc.n += 1
	hc.t = t
	-- the relation (-100..100) of a named citizen with this player (GwangalliGameplay.Mind)
	if c and ctx.mind and type(ctx.mind.event) == "function" and attack ~= "shove" then
		pcall(ctx.mind.event, player, id, if attack == "car" then "hit" else "hit", if attack == "car" then 0.8 else 1)
	end
	rec.hp -= dmg
	rec.t = t
	rec.by = player.UserId
	local police = typeId == "police" or typeId == "swat"
	local react
	if isKey and not lawDown and rec.hp < FS.KEY_MIN_HP then
		rec.hp = FS.KEY_MIN_HP
		outcome = "knockdown"
	end
	if rec.hp <= 0 then
		rec.hp = 0
		outcome = "ko"
		react = "ko"
	else
		react = if p.noReact then "none" else decide(id, typeId, c, rec.hp, max, hc.n, situation(player, id, pos))
		if attack == "car" and react == "fight" then
			react = if r() < 0.6 then "warn" else "report" -- (nobody punches a car)
		elseif attack == "car" and outcome == "stagger" and (react == "cower" or react == "flee") and r() < 0.5 then
			react = "warn" -- (only bumped by a car: startled, then angry at the driver)
		end
		local forced = workspace:GetAttribute("GwangalliStreetLifeDebug") == true and workspace:GetAttribute("GwangalliFightTestReact")
		if type(forced) == "string" and forced ~= "" and not p.noReact then
			react = forced -- test only: this reaction
		end
	end
	local d = pos - root.Position
	local dl = math.max(0.05, Vector3.new(d.X, 0, d.Z).Magnitude)
	local dx, dz = d.X / dl, d.Z / dl
	local cdx, cdz = tonumber(p.dx), tonumber(p.dz)
	if carHit and cdx and cdz and cdx * cdx + cdz * cdz > 0.01 then
		-- (a car hit: they fall the way the car pushed them, not away from the driver's seat)
		local cl = math.sqrt(cdx * cdx + cdz * cdz)
		dx, dz = cdx / cl, cdz / cl
	end
	-- a module that owns this NPC decides the reaction itself (Fight.hitHooks[id prefix], e.g. the
	-- 총기상 of GwangalliGameplay/WeaponDealer): returns react?, line?
	local hookLine: string? = nil
	local hooked = false
	for prefix, hook in Fight.hitHooks do
		if string.sub(id, 1, #prefix) == prefix and type(hook) == "function" then
			hooked = true
			local okH, hr, hl = pcall(hook, player, id, { hp = rec.hp, max = max, hits = hc.n, attack = attack, outcome = if outcome == "thrown" then "knockdown" else outcome, react = react, dx = dx, dz = dz, pos = pos })
			if okH and type(hr) == "string" and react ~= "ko" then
				react = hr
			end
			if okH and type(hl) == "string" then
				hookLine = hl
			end
			break
		end
	end
	-- the crime and the people who care (a shove the caller handles itself: no 폭행 here)
	local crowdCrime: string? = nil
	if not p.noCrime then
		-- (a car into an officer: 경찰관 폭행 unless it only bumped him; the officer saw it either way)
		local kind = if attack == "car" then (if police and outcome ~= "stagger" then "assault_police" else "reckless") elseif police then "assault_police" else "assault"
		if noteCrime(player, id, kind, pos, c, police) then
			crowdCrime = kind
		end
	end
	if outcome == "ko" and noteCrime(player, id, "kill", pos, c, police) then
		crowdCrime = "kill"
	end
	if crowdCrime then
		-- the street crowd around saw it too, once per hit (a KO: as the kill) (GwangalliStreetLife
		-- Mind.onCrime: flee / watch / film / call 112 by personality and severity; their call is Law.report)
		-- (car = a traffic accident: nobody walks up to square up to a moving car)
		send(player, { kind = "crime", crime = crowdCrime, pos = { pos.X, pos.Y, pos.Z }, victim = id, car = if attack == "car" then true else nil })
	end
	local brawlSecs: number? = nil
	if outcome == "ko" then
		koUntil[player][id] = t + FS.KO_DOWN + 2
		if lawRig then
			-- an officer / 특임대 / 119 crew member down: he lies there (out of every brain) until the
			-- ambulance takes him or the time is up (Law/Police.knocked; Fight.tell "ems" holds / ends it)
			local Pol = lawPolice()
			local okD, downOk = false, false
			if Pol and type(Pol.knocked) == "function" then
				okD, downOk = pcall(Pol.knocked, id, dx, dz, FS.KO_DOWN + 14)
			end
			if not (okD and downOk == true) and model and model.Parent then
				-- (not one of Police's units any more: at least the fall, everybody sees it)
				model:SetAttribute("NpcKnock", string.format("%.2f|%.3f|%.3f|%s", workspace:GetServerTimeNow(), dx, dz, "knockdown"))
			end
			keyHp[id] = nil
		end
		-- 119: somebody is down here (Law/Rescue sends an ambulance; it waits until the scene is safe)
		if ctx.rescue and type(ctx.rescue.casualty) == "function" then
			pcall(ctx.rescue.casualty, { pos = pos, id = id, kind = if isKey then "npc" else "ped", player = player })
		end
		if c then
			hospital[id] = os.time() + FS.HOSPITAL_S
			broadcastDown()
		end
		-- (no call of its own: the people around who saw it call (the crowd's KO bystander, the justice
		-- witnesses, Mind.onCrime via noteCrime), else the kill's chance of an unseen caller (Law.crime))
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
		if isKey then
			-- a server rig swings from the server (a module with its own hook fights back itself); only an
			-- NPC.luau one, whom NPC.knock halts and turns to the player: a rig some other brain keeps
			-- walking (customers, shop staff, Law units / actors) only warns
			if not hooked then
				if not lawRig and NPC and type(NPC.state) == "function" and NPC.state(id) then
					keyFight(player, id)
				else
					react = "warn"
				end
			end
		else
			-- the street brawl: one window, the client gets the same seconds (res.brawl)
			brawlSecs = FS.BRAWL_S[1] + r() * (FS.BRAWL_S[2] - FS.BRAWL_S[1])
			brawls[player] = brawls[player] or {}
			brawls[player][id] = { untilT = t + (brawlSecs :: number), last = 0 }
		end
	end
	if c then
		award(player, id)
	end
	-- a key NPC falls for everybody (NpcKnock): NPC.luau's own, a hooked module's (it plays it itself),
	-- else any other rig (Law units, Law/City actors, customers, shop staff) staggers here while its
	-- brain keeps it moving (a downed Law unit: Police.knocked above)
	if isKey and type(p.outcome) ~= "string" and not (lawRig and outcome == "ko") then
		local okK, did = false, false
		if NPC and type(NPC.knock) == "function" then
			okK, did = pcall(NPC.knock, id, dx, dz, if outcome == "stagger" then "stagger" else "knockdown", player)
		end
		if not (okK and did == true) and not hooked and model and model.Parent then
			-- (a car harder than a bump into a Law unit on foot - 특임대, 119: Law/Police holds him for the
			-- fall; a rig some other brain keeps walking only staggers)
			local fell = false
			local Pol = if lawRig and attack == "car" and outcome ~= "stagger" then lawPolice() else nil
			if Pol and type(Pol.knockdown) == "function" then
				local okF, res = pcall(Pol.knockdown, id, dx, dz)
				fell = okF and res == true
			end
			if not fell then
				model:SetAttribute("NpcKnock", string.format("%.2f|%.3f|%.3f|%s", workspace:GetServerTimeNow(), dx, dz, "stagger"))
			end
		end
	end
	-- (a car hit: the car lines - 운전 똑바로 해요! / 차가 사람을 쳤어요! - not the punch ones)
	local carBank = if attack == "car" then (FS.LINES["car_" .. react] or (if react ~= "ko" then FS.LINES.car_hit else nil)) else nil
	local line = hookLine or pick(carBank or FS.LINES[react] or FS.LINES.hit)
	dbg("hit", attack, id, typeId, "dmg", dmg, "hp", rec.hp, "/", max, outcome, react, "hits", hc.n)
	local res = { kind = "hit", target = if isKey then "npc" else "ped", id = id, dmg = dmg, hp = math.floor(rec.hp + 0.5), max = max, outcome = outcome, react = react, line = line, crit = crit, dx = dx, dz = dz, ko = if outcome == "ko" then FS.KO_DOWN else nil, attack = attack, brawl = brawlSecs }
	if not (p.silent == true) then
		send(player, res)
	elseif not isKey then
		-- the caller plays the fall: only the short memory goes to the client (and a KO)
		local mood: string? = if react == "fight" or react == "warn" then "anger" else "fear"
		if react == "none" then
			-- 어깨빵 (no reaction decided here): what they remember follows how they took it - the same
			-- GwangalliMindShared.bumpStyle the client's reaction read (GwangalliStreetLife/Characters):
			-- the timid are scared of you, the kind / playful / cold shrug off the first one, everyone
			-- else is angry (the street re-approach: glare or back away)
			local st: string? = nil
			if MindShared and type(MindShared.personality) == "function" and type(MindShared.bumpStyle) == "function" then
				local drunk = false
				if c and type(MindShared.npcMood) == "function" then
					local okM, nm = pcall(MindShared.npcMood, c, nil, { now = os.time(), clock = game:GetService("Lighting").ClockTime })
					drunk = okM and nm == "DRUNK"
				end
				local okS, res = pcall(function()
					return MindShared.bumpStyle(MindShared.personality(c or { id = id, type = typeId }), typeId, hc.n >= 2, drunk)
				end)
				st = if okS and type(res) == "string" then res else nil
			end
			if st then
				mood = MindShared.BUMP_MEMORY and MindShared.BUMP_MEMORY[st]
			else
				mood = if personality(id, typeId, c) < 0.3 then "fear" else "anger"
			end
		end
		if mood then
			send(player, { kind = "remember", id = id, mood = mood })
		end
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

-- the combat side of an NPC for this player: { hp, max, down (KO now / in hospital / a Law unit lying
-- there), fighting (a brawl with this player now), hits (by this player, last 2 min), lastBy (UserId of
-- the last hit, any player for a key NPC), lastT (os.clock of it), rel (a named citizen's relation) }
function Fight.state(player: Player?, id: string): any
	if type(id) ~= "string" then
		return { down = false, fighting = false, hits = 0 }
	end
	local t = now()
	-- (a key NPC's HP is in keyHp whatever kind of key it is: citizens, dealer_, police_, mg_ ...)
	local rec = keyHp[id] or (player and pedHp[player] and pedHp[player][id])
	local down = (hospital[id] ~= nil and os.time() < hospital[id]) or (player ~= nil and koUntil[player] ~= nil and (koUntil[player][id] or 0) > t)
	if not down and lawRigId(id) then
		local m = keyModel(id)
		down = m ~= nil and m:GetAttribute("NpcDown") ~= nil
	end
	local hp = rec and rec.hp or nil
	if rec and hp and t - rec.t > FS.REGEN_DELAY then
		hp = math.min(rec.max, hp + (t - rec.t - FS.REGEN_DELAY) * FS.REGEN) -- (as the next hit will see it)
	end
	local b = player and brawls[player] and brawls[player][id]
	local hc = player and hitCount[player] and hitCount[player][id]
	local rel = nil
	if player and ctx and ctx.mind and type(ctx.mind.relOf) == "function" and Citizens and Citizens.get and Citizens.get(id) then
		local ok, v = pcall(ctx.mind.relOf, player, id)
		rel = if ok and type(v) == "number" then v else nil
	end
	return {
		hp = hp,
		max = rec and rec.max or nil,
		down = down == true,
		fighting = (b ~= nil and t < b.untilT) or keyFights[id] ~= nil,
		hits = if hc and t - hc.t <= 120 then hc.n else 0,
		lastBy = rec and rec.by or nil,
		lastT = rec and rec.t or nil,
		rel = rel,
	}
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
	-- (pos = the NPC's feet on that client: within reach + lag, and at about the player's height)
	if not root or not pos or flat(pos, root.Position) > FS.NPC_REACH + 3 or math.abs(pos.Y - root.Position.Y) > 8 then
		return
	end
	b.last = t
	-- a punch / a shove (weaker) / a kick (harder): FightShared.ATTACK; the client played the fall
	local atk = if p.attack == "shove" or p.attack == "kick" then p.attack else "punch"
	hurtPlayer(player, p.id, atk, nil, nil, nil)
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
		-- (punched on the way / joined a case meanwhile: Police owns him now, no break-up beat)
		if o.gone or o.state ~= "fightcall" then
			return
		end
		Pol.faceTo(o, pos)
		if Pol.say then
			pcall(Pol.say, o, pick(FS.BREAKUP), 3.5)
		end
		send(player, { kind = "breakup", pos = { pos.X, pos.Y, pos.Z } })
		task.wait(6)
		if not o.gone and o.state == "fightcall" then
			o.role = "patrol"
			o.state = "patrol"
			o.pauseUntil = now() + 4
		end
	end)
end

-- the driver's seat this player sits at: the engine's SeatPart (a VehicleSeat: the wheel; a
-- passenger's Seat is nobody's hit, cf. Crimes.seatedCar), else a manual seating (base Cars.manualSit
-- when Seat:Sit is refused: a SeatWeld and Humanoid.Sit, no SeatPart) = the car whose DriveDriver he is
local function driverSeat(player: Player): BasePart?
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = rootOf(player)
	if not hum or not root then
		return nil
	end
	local seat = hum.SeatPart
	if seat then
		return if seat:IsA("VehicleSeat") then seat else nil
	end
	if player:GetAttribute("InTaxi") then
		return nil
	end
	local tag = (VehS and VehS.Tag) or "GwangalliDrivable"
	local attr = (VehS and VehS.Attr and VehS.Attr.Driver) or "DriveDriver"
	local seatName = (VehS and VehS.Parts and VehS.Parts.DriverSeat) or "DriveSeat"
	for _, m in CollectionService:GetTagged(tag) do
		if m:GetAttribute(attr) == player.UserId then
			local s = m:FindFirstChild(seatName, true)
			-- (sitting there now: not a driver attribute a moment behind the exit)
			if s and s:IsA("VehicleSeat") and (s.Position - root.Position).Magnitude < 8 then
				return s
			end
		end
	end
	return nil
end

-- a street pedestrian hit by this player's car (the client saw the contact): checked against the car
-- the player really sits in and how fast it really goes
-- (per victim: a car through a couple / a group hits each of them in the same frame; at most
-- CAR_HITS_PER_S of them a second per player, so a client cannot flood it)
local CAR_HITS_PER_S = 6
local lastCarHit: { [Player]: { at: { [string]: number }, w: number, n: number } } = {}
local function onCarHit(player: Player, p: any)
	if type(p) ~= "table" or type(p.id) ~= "string" or #p.id > 40 then
		return
	end
	local seat = driverSeat(player)
	local root = rootOf(player)
	local pos = unpackV(p.pos)
	if not seat or not root or not pos then
		return
	end
	local t = now()
	local hits = lastCarHit[player]
	if not hits then
		hits = { at = {}, w = t, n = 0 }
		lastCarHit[player] = hits
	end
	if t - (hits.at[p.id] or -1e9) < 0.4 then
		return
	end
	if t - hits.w >= 1 then
		hits.w, hits.n = t, 0
		for k, at in hits.at do
			if t - at > 2 then
				hits.at[k] = nil -- (only the last moments are kept)
			end
		end
	end
	if hits.n >= CAR_HITS_PER_S then
		return
	end
	local okV, vel = pcall(function()
		return seat.AssemblyLinearVelocity
	end)
	local real = if okV and typeof(vel) == "Vector3" then Vector3.new(vel.X, 0, vel.Z).Magnitude else 0
	local claimed = tonumber(p.speed) or 0
	-- (physics speed when there is one; a client claim is never taken above it + a margin)
	local sp = if real > 1 then math.min(claimed, real + 8) else math.min(claimed, 60)
	-- the contact was at the car on that client; the server copy of a car the driver owns trails it
	-- (speed x latency): the faster, the farther it may be
	local reach = math.max(14, 6 + sp * 0.25)
	if sp < 5 or flat(pos, root.Position) > reach then
		return
	end
	hits.at[p.id] = t
	hits.n += 1
	onPunch(player, { kind = "ped", id = p.id, pos = p.pos, ptype = p.ptype, attack = "car", speed = sp, sn = p.sn, reach = reach, outcome = if sp < 15 then "stagger" elseif sp < 35 then "knockdown" else "thrown" }, true)
end

-- where every client draws a server rig now: its NpcLeg walk (GwangalliNPCClient: "x0,y0,z0,x1,y1,
-- z1,t0,dur" or "P;t0;speed;x,y,z;..." on the server clock), feet level. The server root of a walking
-- rig is only written now and then (NPC.luau: once per arrival), so it is not where the rig is.
-- (parsed once per NpcLeg string: the scan reads it a few times a second)
type Leg = { s: string, poly: boolean, t0: number, speed: number, dur: number, pts: { Vector3 } }
local legCache: { [Model]: Leg } = setmetatable({}, { __mode = "k" }) :: any
local function legFeet(m: Model, t: number): Vector3?
	local s = m:GetAttribute("NpcLeg")
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local L = legCache[m]
	if not L or L.s ~= s then
		local pts = {}
		local poly = string.sub(s, 1, 2) == "P;"
		local t0, speed, dur = 0, 0, 0
		if poly then
			local parts = string.split(s, ";")
			t0, speed = tonumber(parts[2]) or 0, tonumber(parts[3]) or 0
			for i = 4, #parts do
				local c = string.split(parts[i], ",")
				local x, y, z = tonumber(c[1]), tonumber(c[2]), tonumber(c[3])
				if x and y and z then
					table.insert(pts, Vector3.new(x, y, z))
				end
			end
		else
			local c = string.split(s, ",")
			local x0, y0, z0, x1, y1, z1 = tonumber(c[1]), tonumber(c[2]), tonumber(c[3]), tonumber(c[4]), tonumber(c[5]), tonumber(c[6])
			t0, dur = tonumber(c[7]) or 0, tonumber(c[8]) or 0
			if x0 and y0 and z0 and x1 and y1 and z1 then
				pts = { Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1) }
			end
		end
		L = { s = s, poly = poly, t0 = t0, speed = speed, dur = dur, pts = pts }
		legCache[m] = L
	end
	local pts = L.pts
	if #pts == 0 then
		return nil
	end
	if not L.poly then
		local u = if L.dur > 0 then math.clamp((t - L.t0) / L.dur, 0, 1) else 1
		return if #pts >= 2 then pts[1]:Lerp(pts[2], u) else pts[1]
	end
	local left = math.max(0, (t - L.t0) * L.speed)
	for i = 2, #pts do
		local seg = (pts[i] - pts[i - 1]).Magnitude
		if left <= seg then
			return if seg > 1e-4 then pts[i - 1]:Lerp(pts[i], left / seg) else pts[i]
		end
		left -= seg
	end
	return pts[#pts]
end

-- a player's car runs into a server rig (key NPCs, shop / City actors, officers / 119 / 특임대 on foot
-- ...): every driven GwangalliDrivable car is checked a few times a second against the rigs in the
-- part of the street its body swept since the last check (a fast car cannot skip one), each hit then
-- goes the way a pedestrian's does (onPunch "car": damage by speed, the fall everybody sees, the
-- reaction / line, the crime, 119). Rigs riding in a car (NpcSeat), bodies (NpcDown), inmates, the
-- player's own companion and 알바 / minigame rigs are never hit.
local carNpcAt: { [string]: number } = {}
local carPrev: { [Model]: { p: Vector3, t: number } } = setmetatable({}, { __mode = "k" }) :: any
local carHalf: { [Model]: Vector2 } = setmetatable({}, { __mode = "k" }) :: any
local function carScanTick()
	local folder = workspace:FindFirstChild("GwangalliNPCs")
	if not folder then
		return
	end
	local A = VehS and VehS.Attr or {}
	local tag = (VehS and VehS.Tag) or "GwangalliDrivable"
	local baseName = (VehS and VehS.Parts and VehS.Parts.Base) or "DriveBase"
	local t = now()
	local rigs: { Instance }? = nil
	local tServer = 0
	for _, m in CollectionService:GetTagged(tag) do
		local uid = m:GetAttribute(A.Driver or "DriveDriver")
		if not m:IsA("Model") or type(uid) ~= "number" or uid == 0 or m:GetAttribute(A.Sleeping or "DriveSleeping") == true then
			continue
		end
		local base = m:FindFirstChild(baseName)
		local player = Players:GetPlayerByUserId(uid)
		if not base or not base:IsA("BasePart") or not player then
			continue
		end
		local bp = base.Position
		local prev = carPrev[m]
		local travel, dv = 0, Vector3.zero
		local jumped = false
		if prev then
			local dt = t - prev.t
			if dt > 0.02 and dt < 1.5 then
				dv = Vector3.new(bp.X - prev.p.X, 0, bp.Z - prev.p.Z)
				travel = dv.Magnitude
				dv = dv / dt
				-- (faster than any car (VS.Specs top ~131 studs/s): moved there - a respawn / tow / teleport)
				jumped = travel / dt > 150
			end
			prev.p, prev.t = bp, t
		else
			carPrev[m] = { p = bp, t = t }
		end
		if jumped then
			continue
		end
		travel = math.min(travel, 40)
		local okV, vel = pcall(function()
			return base.AssemblyLinearVelocity
		end)
		local v = if okV and typeof(vel) == "Vector3" then Vector3.new(vel.X, 0, vel.Z) else Vector3.zero
		if v.Magnitude < 1 then
			v = dv -- (no physics velocity here: how far it really went)
		end
		local sp = v.Magnitude
		if sp < 8 or sp > 150 then
			continue
		end
		local dir = v / sp
		local half = carHalf[m]
		if not half then
			local okE, ext = pcall(function()
				return m:GetExtentsSize()
			end)
			local L = if okE and typeof(ext) == "Vector3" then math.max(ext.X, ext.Z) else 14
			local W = if okE and typeof(ext) == "Vector3" then math.min(ext.X, ext.Z) else 6
			half = Vector2.new(math.clamp(L / 2, 3, 12), math.clamp(W / 2, 1.5, 5))
			carHalf[m] = half
		end
		local halfL, halfW = half.X, half.Y
		local companion = player:GetAttribute("GwangalliCompanion")
		if not rigs then
			rigs = folder:GetChildren()
			tServer = workspace:GetServerTimeNow()
		end
		for _, r0 in rigs :: { Instance } do
			if not r0:IsA("Model") then
				continue
			end
			local rig = r0 :: Model
			local id = rig:GetAttribute("NpcId")
			if type(id) ~= "string" or id == "" or (carNpcAt[id] or -1e9) > t - 3 or id == companion then
				continue
			end
			local seatAttr = rig:GetAttribute("NpcSeat")
			if (seatAttr ~= nil and seatAttr ~= "") or rig:GetAttribute("NpcDown") ~= nil or rig:GetAttribute("NpcKind") == "inmate" then
				continue
			end
			local mr = rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart
			if not mr or not mr:IsA("BasePart") or flat(mr.Position, bp) > 220 then
				continue -- (far off: not even its leg is close)
			end
			local feet = legFeet(rig, tServer) or (mr.Position - Vector3.new(0, tonumber(rig:GetAttribute("NpcGround")) or 3, 0))
			local rx, rz = feet.X - bp.X, feet.Z - bp.Z
			if rx * rx + rz * rz > (halfL + travel + 4) ^ 2 or math.abs(feet.Y - bp.Y) > 6 then
				continue
			end
			local along = rx * dir.X + rz * dir.Z
			local lx, lz = rx - dir.X * along, rz - dir.Z * along
			-- (inside the body now, just ahead of the bumper, or where the body passed since the last check)
			if along <= halfL + 1.5 and along >= -halfL - travel and lx * lx + lz * lz <= (halfW + 1) ^ 2 then
				if FS.foreign(id, rig) then
					continue
				end
				carNpcAt[id] = t
				local side = lx * -dir.Z + lz * dir.X -- (thrown a little to the side they stood on)
				local sx, sz = -dir.Z * (if side >= 0 then 1 else -1), dir.X * (if side >= 0 then 1 else -1)
				dbg("carScan", id, "hit by", player.Name, string.format("%.1f studs/s", sp))
				onPunch(player, { kind = "npc", id = id, pos = { feet.X, feet.Y, feet.Z }, attack = "car", speed = math.min(sp, 120), reach = halfL + travel + 10, dx = dir.X + sx * 0.35, dz = dir.Z + sz * 0.35 }, true)
			end
		end
	end
	for id, at in carNpcAt do
		if t - at > 10 then
			carNpcAt[id] = nil
		end
	end
end

-- a street fight going on near a point (Law/Rescue keeps the ambulance back)
function Fight.fightingNear(pos: Vector3, r: number): boolean
	local t = now()
	for player, list in brawls do
		local root = rootOf(player)
		if root and flat(root.Position, pos) < r then
			for _, b in list do
				if t < b.untilT then
					return true
				end
			end
		end
	end
	return false
end

-- tell one player's client about a casualty (119 phases). The server side follows the same phases: a
-- body an ambulance is coming for stays down (no new hits, no KO again) until it is carried off; a
-- Law unit's body lies there that long, then it is gone (Law/Police.downHold)
function Fight.tell(player: Player, payload: any)
	if type(payload) == "table" and payload.kind == "ems" and type(payload.id) == "string" then
		local id = payload.id
		local hold = tonumber(payload.hold) or 150
		if payload.phase == "dispatched" then
			koUntil[player] = koUntil[player] or {}
			local ku = koUntil[player][id]
			if ku and ku > now() then
				koUntil[player][id] = math.max(ku, now() + hold)
			end
		elseif payload.phase == "pickup" and koUntil[player] then
			-- (an anonymous id is free again after this: the next one is a new stranger)
			koUntil[player][id] = nil
		end
		if lawRigId(id) then
			local Pol = lawPolice()
			if Pol and type(Pol.downHold) == "function" then
				pcall(Pol.downHold, id, if payload.phase == "pickup" then 0 else hold)
			end
		end
	end
	send(player, payload)
end

-- an NPC starts a fight with this player (a 걸렁뱅이 refused money, a drunk picked a quarrel):
-- their swings may land for a while (each still checked by onNpcHit)
-- -> the seconds it lasts (the client's brawl gets the same: one window), nil when refused
function Fight.startBrawl(player: Player, id: string, secs: number?): number?
	if type(id) ~= "string" or #id > 40 then
		return nil
	end
	local s = secs or (FS.BRAWL_S[1] + r() * (FS.BRAWL_S[2] - FS.BRAWL_S[1]))
	brawls[player] = brawls[player] or {}
	brawls[player][id] = { untilT = now() + s, last = 0 }
	return s
end

-- the client says a street NPC picked the fight: only the types that do that (or a named citizen who
-- really hates this player), close by, not too often. The client's brawl runs the seconds it sent
-- (one window); a refused one is called off on that client ("brawlEnd": no swings that do nothing)
local AGGRESSIVE = { drunk = true, punk = true, thug = true, violent = true, hothead = true }
local lastStart: { [Player]: number } = {}
local function onNpcStart(player: Player, p: any)
	if type(p) ~= "table" or type(p.id) ~= "string" or #p.id > 40 then
		return
	end
	local function refuse()
		send(player, { kind = "brawlEnd", id = p.id })
	end
	local t = now()
	if t - (lastStart[player] or 0) < 2 then
		return refuse()
	end
	local typeId, c = typeOf(p.id, p.ptype)
	local arch = c and MindShared and MindShared.archOf and MindShared.archOf(c) or typeId
	local hostile = false
	if p.why == "hostile" and c and ctx.mind and type(ctx.mind.relOf) == "function" then
		local ok, rel = pcall(ctx.mind.relOf, player, p.id)
		hostile = ok and type(rel) == "number" and rel <= -60
	end
	-- (a street personality that is violent - a hot-tempered passer-by, GwangalliMindShared - picks
	-- fights too: the same shared personality the client's bump reaction read)
	-- (a citizen out drinking tonight - the DRUNK mood, GwangalliMindShared.npcMood - can turn a
	-- quarrel into a scuffle like a drunk)
	local hot = false
	-- (only a roster citizen or a crowd id x1..x999: a made-up id is nobody, and the personality caches
	-- every id it is asked about)
	local real = c ~= nil or string.match(p.id, "^x%d%d?%d?$") ~= nil
	if real and not AGGRESSIVE[typeId] and not AGGRESSIVE[arch] and not hostile and MindShared and type(MindShared.personality) == "function" then
		local okP, pv = pcall(MindShared.personality, c or { id = p.id, type = typeId })
		hot = okP and type(pv) == "table" and pv.violent == true
		if not hot and p.why == "drunk" and c and type(MindShared.npcMood) == "function" then
			local okM, nm = pcall(MindShared.npcMood, c, nil, { now = os.time(), clock = game:GetService("Lighting").ClockTime })
			hot = okM and nm == "DRUNK"
		end
	end
	if not AGGRESSIVE[typeId] and not AGGRESSIVE[arch] and not hostile and not hot then
		return refuse()
	end
	local root = rootOf(player)
	local pos = unpackV(p.pos)
	if not root or not pos or flat(pos, root.Position) > 12 then
		return refuse()
	end
	lastStart[player] = t
	local secs = tonumber(p.secs)
	Fight.startBrawl(player, p.id, if secs then math.clamp(secs, FS.BRAWL_S[1], FS.BRAWL_S[2]) else nil)
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
	pedSn[player] = nil
	robbed[player] = nil
	lastStart[player] = nil
	lastCarHit[player] = nil
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
	BumpS = opt("GwangalliBumpShared")
	VehS = opt("GwangalliVehiclesShared")
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
	-- the server rigs a player's car runs into (carScanTick: ~5 Hz, next to nothing while nobody drives)
	task.spawn(function()
		while true do
			task.wait(0.2)
			local okS, errS = pcall(carScanTick)
			if not okS then
				warn("[GwangalliFight] carScan: " .. tostring(errS))
				task.wait(5)
			end
		end
	end)
	-- ServerStorage.GwangalliNPCHitAPI, for a server-side combat system: Invoke("hit", player, { model =
	-- <the NPC Model / a part of it the hitbox touched> | kind = "ped" | "npc", id, pos?, attack?, power? })
	-- -> the hit result (nil = no hit). Only for a hit that LANDED; the reach is checked again here.
	-- (street pedestrians exist on the player's client only: their hits come in through the client's
	-- LocalPlayer.GwangalliNPCHitAPI)
	local ServerStorage = game:GetService("ServerStorage")
	local old = ServerStorage:FindFirstChild("GwangalliNPCHitAPI")
	if old then
		old:Destroy()
	end
	local sapi = Instance.new("BindableFunction")
	sapi.Name = "GwangalliNPCHitAPI"
	sapi.OnInvoke = function(op: any, pl: any, spec: any)
		if op == "hit" and typeof(pl) == "Instance" and pl:IsA("Player") and type(spec) == "table" then
			if typeof(spec.model) == "Instance" then
				local m: Instance? = spec.model
				while m and not (m:IsA("Model") and type(m:GetAttribute("NpcId")) == "string") do
					m = m.Parent
				end
				-- (an NPC rig only: a root and a kind, not an inmate, not a 알바 / minigame rig or station)
				local kind = m and m:GetAttribute("NpcKind")
				if not m or m:GetAttribute("NpcId") == "" or type(kind) ~= "string" or kind == "inmate" or FS.foreign(m:GetAttribute("NpcId"), m) then
					return nil
				end
				local mr = m:FindFirstChild("HumanoidRootPart")
				if not mr or not mr:IsA("BasePart") then
					return nil
				end
				local s2 = table.clone(spec)
				s2.model = nil
				s2.kind, s2.id = "npc", m:GetAttribute("NpcId")
				s2.pos = { mr.Position.X, mr.Position.Y, mr.Position.Z }
				return Fight.applyHit(pl, s2)
			end
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
