-- GwangalliGameplay/Crime (server, feature module: init(ctx) / onLoaded / onCharacter / onLeave).
-- 전투 · 범죄 · 경찰: punches, HP / KO, 수배 (wanted stars), the police (child module Police), arrests,
-- fines and the 🚑 hospital. Contract (remotes, payloads, attributes, numbers):
-- ReplicatedStorage.GwangalliCombatShared.
--
-- Server-authoritative:
--   * PUNCHES (CombatAction "punch"): token bucket + cooldown, the attacker's state (alive, on foot, not
--     KO / cuffed / working / in a taxi), reach (+ slack), facing and |dy| against the target's position
--     as the SERVER knows it: key NPCs NPC.state(id).pos, officers our own officer table, players their
--     HumanoidRootPart; street pedestrians only exist on the attacker's client, so their reported
--     position is checked like 어깨빵 does (near the attacker, Citizens.plausible for named citizens).
--     Damage lands after the clip's contact time (CONFIG.PUNCH.hitDelay). NPC HP is per target
--     (pedestrians per attacker), officers have their own HP. Accepted swings are mirrored to the other
--     clients through the character attribute GwCombatMove ("jab#seq#serverTime").
--   * HP: Humanoid.MaxHealth = 100, damage never takes Health below 1 (clamp -> KO), regen after a
--     quiet spell. KO = GwKO + GwCombatPose "ko" + PlatformStand; never a real Roblox death. KO while
--     wanted (or by the police) -> arrest; otherwise the 🚑 ambulance to the ward (fee, bank first).
--   * WANTED: crimes add stars (CRIMES); a civilian assault needs a report (a witness on a client, a key
--     NPC, or automatically after REPORT_DELAY); officers that see the player keep the chase alive; out
--     of sight for SEARCH_TIME[stars] -> one star less; 0 -> escaped.
--   * ARREST: cuffs, fade, the 광안지구대, fine (bank first, then cash, the rest -> FineDebt, collected
--     later from money that comes in), 전과 (CrimeRecord), wanted cleared.
-- Client-only state is never trusted for anything that costs another player: a reported pedestrian
-- can only make the reporting player a criminal / hurt that player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crime = {}

local ctx: any
local G: any
local Util: any
local Profiles: any
local Combat: any -- GwangalliCombatShared
local CFG: any -- Combat.CONFIG
local BumpShared: any -- GwangalliBumpShared (optional: 어깨빵 on officers, knock encoding)
local Social: any -- GwangalliSocialShared (optional: key NPC lines)
local Citizens: any -- GwangalliCitizens (optional: pedestrian validation)
local NPC: any -- GwangalliGameplay.NPC (optional: key NPC positions / reactions)
local Police: any -- child module Police
local PoliceCar: any -- child module PoliceCar (optional; owned by the vehicles work)
local Live: any -- GwangalliLiveConfig (optional kill switch features.crime)

local remotes: { Action: RemoteEvent?, Event: RemoteEvent?, BumpEvent: RemoteEvent? } = {}

local BASE_WALK = 16
local TICK = 0.25 -- police brain + wanted bookkeeping
local REGEN_TICK = 0.5
local DEBT_TICK = 20
local DEBT_CASH_RESERVE = 10000 -- auto-collection leaves this much cash in the pocket
local DOWN_GRACE = 1.2
local ALARM_RADIUS = 22
local KEY_WITNESS_R = 22
local REPORT_RANGE = 90 -- a pedestrian report must come from near the player

type PState = {
	stars: number,
	episode: { any },
	pending: { any },
	victims: { [string]: number },
	lastSeen: number,
	seen: boolean,
	searchShown: number,
	lastKnown: Vector3?,
	fled: boolean,
	order: any?,
	orderAt: number,
	surrender: boolean,
	surrenderAt: number,
	fightUntil: number,
	arresting: boolean,
	ko: boolean,
	koMode: string?,
	lastDamage: number,
	downUntil: number,
	lastPunch: number,
	moveSeq: number,
	npcHp: { [string]: any },
	lastAlarm: number,
	frozen: any?,
	lastStreetHit: number,
	tokens: number,
	tokenT: number,
	spawned: boolean,
	charSerial: number,
	lastReport: number,
	lastCrimeToast: number,
	tackleAt: number,
}

local states: { [Player]: PState } = {}
local keyHp: { [string]: any } = {} -- key NPC id -> { hp, t, koUntil } (shared: everybody sees the same NPC)
local stats = { tickN = 0, tickT = 0, tickMax = 0, punches = 0, hits = 0, misses = 0 }

-------------------------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------------------------
local function requireShared(name: string, timeout: number?): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, timeout or 10)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliCrime] " .. name .. " failed to load: " .. tostring(res))
	return nil
end

local function requireSibling(parent: Instance?, name: string): any
	local m = parent and parent:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
		warn("[GwangalliCrime] module " .. name .. " failed to load: " .. tostring(res))
	end
	return nil
end

local function serverNow(): number
	local ok, t = pcall(workspace.GetServerTimeNow, workspace)
	return if ok and type(t) == "number" then t else os.clock()
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function won(n: number): string
	if G and G.format and G.format.won then
		return G.format.won(n)
	end
	return Combat.won(n)
end

local function send(player: Player, payload: any)
	local ev = remotes.Event
	if ev and player.Parent == Players then
		ev:FireClient(player, payload)
	end
end

local function sendAll(payload: any)
	local ev = remotes.Event
	if ev then
		ev:FireAllClients(payload)
	end
end

local function notify(player: Player, kind: string, title: string, body: string?)
	-- always through ctx (Progress wraps ctx.notify after init)
	if ctx and type(ctx.notify) == "function" then
		pcall(ctx.notify, player, kind, title, body or "")
	end
end

local function track(player: Player, key: string, n: number?)
	local pr = ctx and ctx.progress
	if pr and type(pr.track) == "function" then
		pcall(pr.track, player, key, n or 1)
	end
end

local liveCache, liveT = true, -1
local function enabled(): boolean
	local now = os.clock()
	if now - liveT > 2 then
		liveT = now
		liveCache = true
		if Live and type(Live.enabled) == "function" then
			local ok, res = pcall(Live.enabled, "crime")
			liveCache = not (ok and res == false)
		end
	end
	return liveCache
end

local function state(player: Player): PState?
	local s = states[player]
	if not s and player.Parent == Players then
		s = {
			stars = 0,
			episode = {},
			pending = {},
			victims = {},
			lastSeen = 0,
			seen = false,
			searchShown = -1,
			lastKnown = nil,
			fled = false,
			order = nil,
			orderAt = -1e9,
			surrender = false,
			surrenderAt = 0,
			fightUntil = 0,
			arresting = false,
			ko = false,
			koMode = nil,
			lastDamage = -1e9,
			downUntil = 0,
			lastPunch = -1e9,
			moveSeq = 0,
			npcHp = {},
			lastAlarm = -1e9,
			frozen = nil,
			lastStreetHit = -1e9,
			tokens = 8,
			tokenT = os.clock(),
			spawned = false,
			charSerial = 0,
			lastReport = -1e9,
			lastCrimeToast = -1e9,
			tackleAt = -1e9,
		}
		states[player] = s
	end
	return s
end

-- own token bucket (Util.bucket shares one bucket per player with PhoneAction / 어깨빵)
local function takeToken(s: PState): boolean
	local now = os.clock()
	s.tokens = math.min(8, s.tokens + (now - s.tokenT) * 5)
	s.tokenT = now
	if s.tokens < 1 then
		return false
	end
	s.tokens -= 1
	return true
end

local function crimeData(player: Player): any?
	local d = Profiles and Profiles.get(player)
	if not d then
		return nil
	end
	if type(d.crime) ~= "table" then
		d.crime = { record = 0, debt = 0, arrests = {} }
	end
	local c = d.crime
	c.record = math.max(0, math.floor(tonumber(c.record) or 0))
	c.debt = math.max(0, math.floor(tonumber(c.debt) or 0))
	if type(c.arrests) ~= "table" then
		c.arrests = {}
	end
	return c
end

local function pushRecordAttrs(player: Player)
	local c = crimeData(player)
	if c and player.Parent == Players then
		player:SetAttribute(Combat.Attr.CrimeRecord, c.record)
		player:SetAttribute(Combat.Attr.FineDebt, c.debt)
	end
end

local function standFeet(player: Player): (Vector3?, BasePart?, Humanoid?)
	local _, hum, root = Util.alive(player)
	if not hum or not root then
		return nil, nil, nil
	end
	local h = Util.standHeight(hum, root)
	return root.Position - Vector3.new(0, h, 0), root, hum
end

local function setPose(player: Player, pose: string)
	local character = player.Character
	if character and character.Parent then
		character:SetAttribute(Combat.Attr.Pose, pose)
	end
end

-- WalkSpeed / jump to 0 while cuffed / KO / hands up (the HUD sprint only rewrites its own speeds)
local function freeze(player: Player)
	local s = states[player]
	local _, hum = Util.alive(player)
	if not s or not hum then
		return
	end
	if not s.frozen then
		s.frozen = { walk = hum.WalkSpeed, jumpH = hum.JumpHeight, jumpP = hum.JumpPower }
	end
	hum.WalkSpeed = 0
	pcall(function()
		hum.JumpHeight = 0
		hum.JumpPower = 0
	end)
end

local function unfreeze(player: Player)
	local s = states[player]
	if not s then
		return
	end
	local f = s.frozen
	s.frozen = nil
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	-- only undo our own 0: another system that set its own speed in between keeps it
	if hum.WalkSpeed == 0 then
		local w = if f and type(f.walk) == "number" and f.walk > 0 and f.walk <= 32 then f.walk else BASE_WALK
		hum.WalkSpeed = w
	end
	pcall(function()
		if hum.JumpHeight == 0 then
			hum.JumpHeight = if f and type(f.jumpH) == "number" and f.jumpH > 0 then f.jumpH else 7.2
		end
		if hum.JumpPower == 0 then
			hum.JumpPower = if f and type(f.jumpP) == "number" and f.jumpP > 0 then f.jumpP else 50
		end
	end)
end

-- a bubble over a police officer (CombatEvent "say") or a key NPC (GwangalliBump.BumpEvent "say":
-- every existing client already renders it over the NPC's head)
local function say(id: string, text: string?, typeId: string?, dur: number?)
	if not text or text == "" then
		return
	end
	if Combat.isPoliceId(id) then
		sendAll({ kind = "say", id = id, text = text, typeId = "police", dur = dur or 2.6 })
	elseif remotes.BumpEvent then
		remotes.BumpEvent:FireAllClients({ kind = "say", id = id, text = text, typeId = typeId or "plain", dur = dur or 3 })
	else
		sendAll({ kind = "say", id = id, text = text, typeId = typeId or "plain", dur = dur or 3 })
	end
end
Crime.say = say

local function citizen(id: any): any?
	return if type(id) == "string" and Citizens and Citizens.byId then Citizens.byId[id] else nil
end

local function speechOf(id: string): string
	local c = citizen(id)
	return (c and c.speech) or "std"
end

local function clockNow(): number
	local ok, env = pcall(ctx.env)
	return if ok and env and type(env.clock) == "number" then env.clock % 24 else 12
end

local function areaPos(areaId: string): Vector3?
	local a = Citizens and Citizens.AREAS and Citizens.AREAS[areaId]
	local part = a and ctx.dest(a.dest)
	return part and part.Position or nil
end

local function keyNpcPos(id: string): Vector3?
	if NPC and type(NPC.state) == "function" then
		local ok, st = pcall(NPC.state, id)
		if ok and st and not st.hidden and st.pos then
			return st.pos
		end
	end
	return nil
end

local function award(player: Player, id: string)
	local social = ctx.social
	if not social or type(social.award) ~= "function" or not citizen(id) then
		return
	end
	local okSrc = Social and Social.SOURCES and Social.SOURCES.punch ~= nil
	if okSrc then
		pcall(social.award, player, id, "punch", -10)
	else
		pcall(social.award, player, id, "rude", -8)
	end
end

local function alarm(player: Player, pos: Vector3, severity: number, victim: string?)
	local s = states[player]
	local now = os.clock()
	if s then
		if now - s.lastAlarm < 0.6 and severity < 3 then
			return
		end
		s.lastAlarm = now
	end
	sendAll({ kind = "alarm", pos = Combat.packV(pos), radius = ALARM_RADIUS, severity = math.clamp(severity, 1, 3), victim = victim, attacker = player.UserId })
end

-------------------------------------------------------------------------------------------------
-- Wanted
-------------------------------------------------------------------------------------------------
local function setWantedAttrs(player: Player, s: PState)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(Combat.Attr.Wanted, s.stars)
	if s.stars <= 0 then
		player:SetAttribute(Combat.Attr.PoliceChase, false)
		player:SetAttribute(Combat.Attr.WantedSearch, 0)
		s.searchShown = 0
	end
end

local function carDispatch(player: Player, s: PState)
	if not PoliceCar or type(PoliceCar.dispatch) ~= "function" then
		return
	end
	local ok, err = pcall(PoliceCar.dispatch, player, ctx, {
		stars = s.stars,
		pos = s.lastKnown,
		-- the car can unload officers where it stops: spawnOfficers(feet, n)
		spawnOfficers = function(at: Vector3, n: number)
			if Police and type(Police.spawnAt) == "function" then
				return Police.spawnAt(player, at, n)
			end
			return 0
		end,
	})
	if not ok then
		warn("[GwangalliCrime] PoliceCar.dispatch failed: " .. tostring(err))
	end
end

local function carRelease(player: Player)
	if PoliceCar and type(PoliceCar.release) == "function" then
		local ok, err = pcall(PoliceCar.release, player)
		if not ok then
			warn("[GwangalliCrime] PoliceCar.release failed: " .. tostring(err))
		end
	end
end

local function endCompanion(player: Player)
	local social = ctx.social
	if not social or type(social.companion) ~= "function" or type(social.handleChoice) ~= "function" then
		return
	end
	local ok, compId = pcall(social.companion, player)
	if ok and type(compId) == "string" then
		pcall(social.handleChoice, player, compId, "soc:dismiss")
	end
end

local function crimeToast(player: Player, s: PState, label: string)
	local stars = Combat.starsText(s.stars)
	local body = if s.stars >= 3 then label .. " · 순찰차까지 출동했어요!" else label .. " · 경찰이 출동했어요"
	notify(player, if s.stars >= 3 then "error" else "warn", "🚨 수배 " .. stars, body)
end

-- the star(s) of a crime land now
local function confirm(player: Player, s: PState, crimeId: string, pos: Vector3?)
	local def = Combat.CRIMES[crimeId]
	if not def or s.arresting then
		return
	end
	if #s.episode < 24 then
		table.insert(s.episode, { crime = crimeId, label = def.label, fine = def.fine, t = os.time() })
	end
	local before = s.stars
	s.stars = math.min(CFG.MAX_STARS, s.stars + def.stars)
	s.lastSeen = os.clock() -- the police know where it happened: the search clock starts now
	s.lastKnown = pos or standFeet(player) or s.lastKnown
	setWantedAttrs(player, s)
	send(player, { kind = "crime", crime = crimeId, label = def.label, stars = s.stars, reported = true })
	if not s.seen then
		-- nobody sees the suspect yet: the search clock runs from now
		send(player, { kind = "search", left = math.ceil(Combat.searchTime(s.stars)) })
	end
	local now = os.clock()
	if s.stars ~= before or now - s.lastCrimeToast > 6 then
		s.lastCrimeToast = now
		crimeToast(player, s, def.label)
	end
	if before == 0 then
		endCompanion(player)
	end
	if Police then
		pcall(Police.alert, player, s.lastKnown)
		pcall(Police.ensure, player, s.stars)
	end
	if s.stars >= CFG.CAR_AT and before < CFG.CAR_AT then
		carDispatch(player, s)
	end
end

local function confirmPending(player: Player, s: PState)
	if #s.pending == 0 then
		return
	end
	local list = s.pending
	s.pending = {}
	for _, p in list do
		confirm(player, s, p.crime, p.pos)
	end
end

-- A crime by `player`. opts = { victim = key (same-victim window), pos = Vector3, reported = bool }.
-- Returns true when stars were added now (false: pending a report / suppressed).
function Crime.addCrime(player: Player, crimeId: string, opts: any?): boolean
	local def = Combat.CRIMES[crimeId]
	local s = state(player)
	if not def or not s or s.arresting or not enabled() then
		return false
	end
	local o = opts or {}
	local now = os.clock()
	if o.victim and crimeId ~= "ko" then
		local key = crimeId .. "|" .. tostring(o.victim)
		local last = s.victims[key]
		s.victims[key] = now
		if last and now - last < CFG.SAME_VICTIM_WINDOW then
			return false
		end
	end
	if crimeId == "flee" then
		if s.fled then
			return false
		end
		s.fled = true
	end
	if def.needsReport and not o.reported and not s.seen then
		table.insert(s.pending, { crime = crimeId, at = now + CFG.REPORT_DELAY, pos = o.pos })
		send(player, { kind = "crime", crime = crimeId, label = def.label, stars = s.stars, reported = false })
		return false
	end
	confirm(player, s, crimeId, o.pos)
	return true
end

-- a witness phoned the police (key NPC / pedestrian report): every pending crime counts now
function Crime.report(player: Player)
	local s = states[player]
	if s then
		confirmPending(player, s)
	end
end

local function clearWanted(player: Player, s: PState, why: string)
	s.stars = 0
	s.episode = {}
	s.pending = {}
	s.victims = {}
	s.fled = false
	s.order = nil
	s.surrender = false
	s.fightUntil = 0
	s.seen = false
	s.lastKnown = nil
	setWantedAttrs(player, s)
	if Police then
		pcall(Police.release, player, why)
	end
	carRelease(player)
end

local function escaped(player: Player, s: PState)
	clearWanted(player, s, "escaped")
	send(player, { kind = "escaped" })
	notify(player, "success", "🚨 경찰을 따돌렸어요", "수배가 해제됐어요. 당분간은 얌전히 지내요 😅")
	track(player, "police_escape")
	if G and G.CONTACTS and G.CONTACTS.police then
		task.delay(4, function()
			if player.Parent == Players then
				pcall(ctx.sendMessage, player, "police", "[광안지구대] 오늘은 운이 좋으셨네요. 광안리에서는 질서를 꼭 지켜 주세요 🚓")
			end
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- HP / damage / KO
-------------------------------------------------------------------------------------------------
local function hpView(hum: Humanoid): (number, number)
	return math.floor(hum.Health + 0.5), math.floor(hum.MaxHealth + 0.5)
end

local knockOut: (Player, any) -> ()

-- Damage to a player. info = { by = id/name, byKind = "police"|"street"|"player"|..., dx, dz,
-- outcome = "hit"|"stagger"|"knockdown", attacker = Player? }. Never kills: at 0 the player is KO.
-- Returns applied, ko.
function Crime.damage(victim: Player, dmg: number, info: any?): (boolean, boolean)
	local s = state(victim)
	local i = info or {}
	if not s or s.ko or s.arresting then
		return false, false
	end
	local character, hum = Util.alive(victim)
	if not character or not hum then
		return false, false
	end
	if character:FindFirstChildOfClass("ForceField") then
		return false, false -- spawn protection (like Humanoid:TakeDamage)
	end
	local amount = math.clamp(math.floor((tonumber(dmg) or 0) + 0.5), 0, CFG.MAX_HP)
	if amount <= 0 then
		return false, false
	end
	local now = os.clock()
	s.lastDamage = now
	local hp = hum.Health - amount
	local ko = hp < 1
	hum.Health = math.max(1, hp)
	local outcome = if ko then "knockdown" else (i.outcome or "hit")
	if outcome == "knockdown" then
		s.downUntil = math.max(s.downUntil, now + 2.1 + DOWN_GRACE)
	elseif outcome == "stagger" then
		s.downUntil = math.max(s.downUntil, now + 0.9)
	end
	local h, m = hpView(hum)
	send(victim, { kind = "hurt", by = i.by, byKind = i.byKind, dmg = amount, hp = h, maxHp = m, dx = i.dx or 0, dz = i.dz or -1, outcome = outcome })
	if ko then
		knockOut(victim, i) -- sets s.ko at once: nothing else can hit / arrest-race this player meanwhile
	end
	return true, ko
end

local function hospitalPart(): BasePart?
	local health = ctx.health
	if health and type(health.findBed) == "function" then
		local ok, bed = pcall(health.findBed, "ward", nil)
		if ok and bed then
			return bed
		end
	end
	return ctx.dest("광안메디컬") or ctx.dest(Combat.HOSPITAL)
end

-- bank first (check card), then cash; what neither covers -> hospital debt (Health charges it at
-- the next clinic visit)
local function chargeHospital(player: Player, fee: number): (number, number)
	local d = Profiles.get(player)
	if not d then
		return 0, 0
	end
	local label = CFG.HOSPITAL_LABEL
	if ctx.spend(player, fee, label, true, "bank") then
		return fee, 0
	end
	local remaining = fee
	local takeBank = math.min(remaining, math.max(0, math.floor(d.bank or 0)))
	if takeBank > 0 and ctx.ledger(player, "bank", -takeBank, label .. " (일부)", true) then
		remaining -= takeBank
	end
	local takeCash = math.min(remaining, math.max(0, math.floor(d.cash or 0)))
	if takeCash > 0 and ctx.ledger(player, "cash", -takeCash, label .. " (일부)", true) then
		remaining -= takeCash
	end
	if remaining > 0 then
		local health = ctx.health
		if health and type(health.status) == "function" then
			pcall(health.status, player) -- creates d.health lazily
		end
		if type(d.health) == "table" then
			d.health.debt = math.max(0, math.floor(tonumber(d.health.debt) or 0)) + remaining
			pcall(ctx.changed, player, "stats")
		end
	end
	return fee - remaining, remaining
end

local function wake(player: Player, s: PState)
	s.ko = false
	s.koMode = nil
	local character = player.Character
	if character then
		character:SetAttribute(Combat.Attr.KO, false)
	end
	setPose(player, "")
	local _, hum = Util.alive(player)
	if hum then
		pcall(function()
			hum.PlatformStand = false
		end)
	end
	unfreeze(player)
end

local function hospital(player: Player, s: PState, serial: number)
	task.wait(3)
	if player.Parent ~= Players or s.charSerial ~= serial or not s.ko then
		return
	end
	Util.fade(player, true, 0.8, "🚑 구급차 이동 중…")
	if player.Parent ~= Players or s.charSerial ~= serial then
		return
	end
	if ctx.onShift(player) then
		pcall(ctx.endShift, player)
	end
	local paid, debt = chargeHospital(player, CFG.HOSPITAL_FEE)
	local bed = hospitalPart()
	local _, hum = Util.alive(player)
	if hum then
		pcall(function()
			hum.PlatformStand = false
		end)
		hum.Health = hum.MaxHealth
	end
	if bed then
		ctx.allowTeleport(player, 10)
		pcall(ctx.jobsResetPosition, player)
		local ok = pcall(Util.teleportTo, player, bed, 6)
		local _, hum2 = Util.alive(player)
		if ok and hum2 and bed:IsA("Seat") then
			pcall(function()
				(bed :: any):Sit(hum2)
			end)
		end
	end
	wake(player, s)
	task.wait(0.6)
	Util.fade(player, false, 0.8)
	send(player, { kind = "wake" })
	local body = string.format("응급 진료비 %s%s · HP 회복", won(paid), if debt > 0 then string.format(" (미납 %s)", won(debt)) else "")
	notify(player, "info", "광안메디컬 응급실에서 눈을 떴어요 🏥", body)
end

local arrest: (Player, string, string?) -> ()

knockOut = function(victim: Player, info: any)
	local s = state(victim)
	if not s or s.ko or s.arresting then
		return
	end
	local character, hum = Util.alive(victim)
	if not character or not hum then
		return
	end
	s.ko = true
	local mode = if s.stars > 0 or info.byKind == "police" then "arrest" else "hospital"
	s.koMode = mode
	character:SetAttribute(Combat.Attr.KO, true)
	setPose(victim, "ko")
	freeze(victim)
	pcall(function()
		hum.PlatformStand = true
	end)
	s.order = nil
	s.surrender = false
	send(victim, { kind = "stopEnd" })
	send(victim, { kind = "ko", mode = mode })
	if mode == "hospital" then
		notify(victim, "warn", "쓰러졌어요… 😵", "119 구급차가 오고 있어요")
	else
		notify(victim, "error", "쓰러졌어요… 😵", "경찰이 다가와요 🚓")
	end
	local serial = s.charSerial
	task.spawn(function()
		if mode == "hospital" then
			local ok, err = pcall(hospital, victim, s, serial)
			if not ok then
				warn("[GwangalliCrime] hospital failed: " .. tostring(err))
				if s.charSerial == serial then
					Util.clearFade(victim)
					wake(victim, s)
				end
			end
		else
			task.wait(2.6)
			if victim.Parent == Players and s.charSerial == serial and s.ko and not s.arresting then
				arrest(victim, "forced", nil)
			end
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Arrest / fines
-------------------------------------------------------------------------------------------------
local function post(player: Player, account: string, delta: number, label: string): boolean
	local bank = ctx.bank
	if bank and type(bank.post) == "function" then
		local ok, res = pcall(bank.post, player, account, delta, label, { kind = "fee" })
		return ok and res == true
	end
	return ctx.ledger(player, account, delta, label, true) == true
end

-- bank first, then cash; returns paid, unpaid
local function payFine(player: Player, amount: number, label: string, cashReserve: number?): (number, number)
	local d = Profiles.get(player)
	if not d or amount <= 0 then
		return 0, math.max(0, amount)
	end
	local remaining = amount
	local takeBank = math.min(remaining, math.max(0, math.floor(d.bank or 0)))
	if takeBank > 0 and post(player, "bank", -takeBank, label) then
		remaining -= takeBank
	end
	local cashFree = math.max(0, math.floor(d.cash or 0) - (cashReserve or 0))
	local takeCash = math.min(remaining, cashFree)
	if takeCash > 0 and post(player, "cash", -takeCash, label .. " (현금)") then
		remaining -= takeCash
	end
	return amount - remaining, remaining
end

local function stationPart(): (BasePart?, CFrame?)
	local part = ctx.dest(Combat.STATION)
	if part then
		return part, nil
	end
	local navMod = ReplicatedStorage:FindFirstChild("GwangalliNav")
	if navMod and navMod:IsA("ModuleScript") then
		local ok, Nav = pcall(require, navMod)
		local p = ok and Nav and Nav.places and Nav.places[Combat.STATION]
		if p and type(p.x) == "number" then
			return nil, CFrame.new(p.x, p.y + 3.5, p.z)
		end
	end
	return nil, nil
end

local function crimesSummary(episode: { any }): ({ any }, string)
	local byId: { [string]: any } = {}
	local list = {}
	for _, e in episode do
		local b = byId[e.crime]
		if b then
			b.n += 1
			b.fine += e.fine
		else
			b = { crime = e.crime, label = e.label, fine = e.fine, n = 1 }
			byId[e.crime] = b
			table.insert(list, b)
		end
	end
	local out, names = {}, {}
	for _, b in list do
		local label = if b.n > 1 then string.format("%s ×%d", b.label, b.n) else b.label
		table.insert(out, { label = label, fine = b.fine })
		table.insert(names, b.label)
	end
	return out, table.concat(names, ", ")
end

arrest = function(player: Player, mode: string, officerId: string?)
	local s = state(player)
	if not s or s.arresting or player.Parent ~= Players then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	s.arresting = true
	s.order = nil
	local surrendered = s.surrender or mode == "surrender"
	s.surrender = false
	local serial = s.charSerial
	player:SetAttribute(Combat.Attr.Arrested, true)
	player:SetAttribute(Combat.Attr.PoliceChase, false)
	player:SetAttribute(Combat.Attr.WantedSearch, 0)
	send(player, { kind = "stopEnd" })
	send(player, { kind = "arrest", phase = "start" })
	freeze(player)
	if not s.ko then
		setPose(player, "cuffed")
	end
	if ctx.onShift(player) then
		pcall(ctx.endShift, player)
	end
	if Police then
		pcall(Police.cuffing, player, officerId)
	end
	task.spawn(function()
		local ok, err = pcall(function()
			task.wait(2.4)
			if player.Parent ~= Players then
				return
			end
			Util.fade(player, true, 0.8, "🚓 광안지구대로 연행 중…")
			if player.Parent ~= Players then
				return
			end
			local fineMode = if surrendered then "surrender" elseif mode == "forced" then "forced" else nil
			local fine = Combat.fineFor(s.episode, fineMode)
			local crimes, names = crimesSummary(s.episode)
			local label = CFG.FINE_LABEL .. (if names ~= "" then " · " .. names else "")
			local paid, unpaid = payFine(player, fine, label, 0)
			local c = crimeData(player)
			local record, debt = 0, unpaid
			if c then
				c.record += 1
				c.debt = math.min(c.debt + unpaid, 100000000)
				table.insert(c.arrests, { t = os.time(), fine = fine, paid = paid, crimes = string.sub(names, 1, 80) })
				while #c.arrests > 8 do
					table.remove(c.arrests, 1)
				end
				record, debt = c.record, c.debt
				pcall(Profiles.markDirty, player)
			end
			pushRecordAttrs(player)
			track(player, "arrested")
			if fine > 0 and unpaid == 0 then
				track(player, "fine_paid")
			end
			-- officers stay behind (they walk off); the suspect goes to the station
			if Police then
				pcall(Police.release, player, "arrested")
			end
			carRelease(player)
			local stillHere = s.charSerial == serial
			if stillHere then
				local _, hum = Util.alive(player)
				if hum then
					pcall(function()
						hum.PlatformStand = false
					end)
					hum.Health = math.max(hum.Health, math.floor(hum.MaxHealth * 0.4))
				end
				s.ko = false
				s.koMode = nil
				if player.Character then
					player.Character:SetAttribute(Combat.Attr.KO, false)
				end
				setPose(player, "")
				ctx.allowTeleport(player, 10)
				pcall(ctx.jobsResetPosition, player)
				local part, cf = stationPart()
				if part then
					pcall(Util.teleportTo, player, part, 6)
				elseif cf then
					pcall(Util.placeCharacter, player, cf)
				end
			end
			clearWanted(player, s, "arrested")
			task.wait(0.5)
			Util.fade(player, false, 0.8)
			unfreeze(player)
			send(player, {
				kind = "arrest",
				phase = "done",
				fine = fine,
				paid = paid,
				debt = debt,
				crimes = crimes,
				record = record,
				forced = mode == "forced",
				surrendered = surrendered,
			})
			local body = string.format("벌금 %s · 납부 %s%s", won(fine), won(paid), if unpaid > 0 then " · 미납 " .. won(unpaid) else "")
			notify(player, "error", "🚓 체포되었어요", body)
			if G and G.CONTACTS and G.CONTACTS.police then
				local text = if unpaid > 0
					then string.format("[광안지구대] %s 건으로 범칙금 %s이 부과되었습니다. 미납 %s은 입금되는 대로 자동 납부됩니다.", names ~= "" and names or "질서위반", won(fine), won(debt))
					else string.format("[광안지구대] %s 건 범칙금 %s 납부가 확인되었습니다. 다음엔 이런 일 없도록 해 주세요.", names ~= "" and names or "질서위반", won(fine))
				task.delay(3, function()
					if player.Parent == Players then
						pcall(ctx.sendMessage, player, "police", text)
					end
				end)
			end
		end)
		s.arresting = false
		if player.Parent == Players then
			player:SetAttribute(Combat.Attr.Arrested, false)
		end
		if not ok then
			warn("[GwangalliCrime] arrest failed: " .. tostring(err))
			if player.Parent == Players then
				Util.clearFade(player)
				if s.charSerial == serial then
					wake(player, s)
				end
				clearWanted(player, s, "arrested")
			end
		end
	end)
end

function Crime.arrest(player: Player, mode: string?, officerId: string?)
	arrest(player, mode or "forced", officerId)
end

-------------------------------------------------------------------------------------------------
-- Punch validation and resolution
-------------------------------------------------------------------------------------------------
-- the attacker can throw a punch now
local function canAct(player: Player, s: PState): (boolean, string?)
	local character, hum, root = Util.alive(player)
	if not character or not hum or not root then
		return false, "dead"
	end
	if s.ko or s.arresting or s.surrender then
		return false, "busy"
	end
	if hum.Sit or hum.PlatformStand then
		return false, "seated"
	end
	if os.clock() < s.downUntil or character:GetAttribute(Combat.Attr.Knocked) == true then
		return false, "down"
	end
	if ctx.isRiding and ctx.isRiding(player) then
		return false, "taxi"
	end
	if ctx.onShift and ctx.onShift(player) then
		return false, "shift"
	end
	if G and player:GetAttribute(G.Attr.GymBusy) then
		return false, "gym"
	end
	return true
end

-- HP bookkeeping of an NPC target (pedestrians: per attacker; key NPCs: shared)
local function npcHpEntry(map: { [string]: any }, key: string, maxHp: number, now: number): any
	local e = map[key]
	if not e or (now - e.t > CFG.NPC_HP_RESET and now >= (e.koUntil or 0)) then
		e = { hp = maxHp, t = now, koUntil = 0 }
		map[key] = e
	end
	if e.koUntil > 0 and now >= e.koUntil then
		e.hp = maxHp
		e.koUntil = 0
	end
	return e
end

-- key NPCs within reach of the crime that saw it: they react and phone the police
local function keyWitnesses(player: Player, pos: Vector3, except: string?): number
	local folder = workspace:FindFirstChild("GwangalliNPCs")
	if not folder then
		return 0
	end
	local n = 0
	for _, m in folder:GetChildren() do
		local id = m:IsA("Model") and m:GetAttribute("NpcId")
		if type(id) == "string" and id ~= except and not Combat.isPoliceId(id) then
			local p = keyNpcPos(id)
			if p and (p - pos).Magnitude <= KEY_WITNESS_R then
				n += 1
				if n <= 2 then
					local delay = 0.4 + n * 0.5
					task.delay(delay, function()
						if NPC and type(NPC.react) == "function" then
							pcall(NPC.react, id, if n == 1 then "facepalm" else "shake")
						end
						local text = Combat.line("witness", nil, speechOf(id))
						say(id, text, "plain", 2.6)
					end)
				end
			end
		end
	end
	return n
end

local function moveAttr(player: Player, s: PState, combo: number)
	local character = player.Character
	if not character then
		return
	end
	s.moveSeq = (s.moveSeq % 9999) + 1
	character:SetAttribute(Combat.Attr.Move, Combat.encodeMove(Combat.clipOf(combo), s.moveSeq, serverNow()))
end

-- target resolution: returns pos (feet / root position the server trusts), key, extra
local function resolveTarget(player: Player, s: PState, kind: string, id: any, payload: any, myPos: Vector3): (Vector3?, string?, any)
	local reach = CFG.PUNCH.range + CFG.PUNCH.rangeSlack
	if kind == "police" or (type(id) == "string" and Combat.isPoliceId(id)) then
		local o = Police and Police.get(id)
		if not o then
			return nil, "gone", nil
		end
		local p = Police.position(o)
		if not p then
			return nil, "gone", nil
		end
		return p + Vector3.new(0, o.ground, 0), nil, { kind = "police", officer = o, id = o.id }
	elseif kind == "npc" then
		local sid = Util.str(id, 40)
		local c = sid and citizen(sid)
		if not sid or not c or c.key ~= true then
			return nil, "bad", nil
		end
		local p = keyNpcPos(sid)
		if not p then
			return nil, "gone", nil
		end
		return p + Vector3.new(0, 3, 0), nil, { kind = "npc", id = sid, c = c }
	elseif kind == "street" then
		local sid = Util.str(id, 40)
		if not sid then
			return nil, "bad", nil
		end
		local c = citizen(sid)
		local anon = string.match(sid, "^x%d+$") ~= nil
		if not anon and (not c or c.key == true) then
			return nil, "bad", nil
		end
		local pos = Combat.unpackV(payload.target and payload.target.pos)
		if not pos then
			return nil, "nopos", nil
		end
		if flatDist(pos, myPos) > reach + 0.5 or math.abs(pos.Y - myPos.Y) > CFG.PUNCH.dyMax + 2 then
			return nil, "far", nil
		end
		local plausible = true
		if c and Citizens and type(Citizens.plausible) == "function" then
			local ok, res = pcall(Citizens.plausible, sid, pos, clockNow(), areaPos, 160)
			plausible = not (ok and res == false)
		end
		return pos, nil, { kind = "street", id = sid, c = c, plausible = plausible }
	elseif kind == "player" then
		local uid = tonumber(id)
		local victim = uid and Players:GetPlayerByUserId(uid)
		if not victim or victim == player then
			return nil, "bad", nil
		end
		local bumpOff = Combat.Attr.BumpEnabled
		if player:GetAttribute(bumpOff) == false or victim:GetAttribute(bumpOff) == false then
			return nil, "protected", nil
		end
		local vs = state(victim)
		if not vs or vs.ko or vs.arresting then
			return nil, "victim", nil
		end
		local _, _, vroot = Util.alive(victim)
		if not vroot then
			return nil, "victim", nil
		end
		return vroot.Position, nil, { kind = "player", victim = victim, id = victim.UserId }
	end
	return nil, "bad", nil
end

local function applyHit(player: Player, s: PState, combo: number, t: any, targetPos: Vector3)
	local now = os.clock()
	local myPos = Util.rootPosition(player)
	if not myPos then
		return
	end
	local dx, dz = Combat.flatDir(myPos, targetPos)
	local feet = targetPos
	if t.kind == "player" then
		local victim = t.victim :: Player
		local dmg = CFG.PUNCH.dmg[combo] or 8
		local outcome = if combo >= 3 then "knockdown" elseif combo == 2 then "stagger" else "hit"
		local vs = state(victim)
		if vs and now < vs.downUntil then
			send(player, { kind = "miss", reason = "down" })
			return
		end
		local applied, ko = Crime.damage(victim, dmg, { by = player.DisplayName, byKind = "player", dx = dx, dz = dz, outcome = outcome, attacker = player })
		if not applied then
			send(player, { kind = "miss", reason = "victim" })
			return
		end
		local _, vhum = Util.alive(victim)
		local hp, maxHp = 0, CFG.MAX_HP
		if vhum then
			hp, maxHp = hpView(vhum)
		end
		local out = if ko then "ko" else outcome
		send(player, { kind = "hit", target = "player", id = victim.UserId, dmg = dmg, hp = hp, maxHp = maxHp, outcome = out, dx = dx, dz = dz, combo = combo })
		stats.hits += 1
		track(player, "punch_hit")
		Crime.addCrime(player, "assault_player", { victim = "p" .. victim.UserId, pos = feet })
		if ko then
			track(player, "crime_ko")
			Crime.addCrime(player, "ko", { victim = "p" .. victim.UserId, pos = feet })
		end
		alarm(player, feet, if ko then 3 elseif outcome == "hit" then 1 else 2, nil)
		return
	end
	if t.kind == "police" then
		local o = t.officer
		local dmg = CFG.PUNCH.npcDmg[combo] or 10
		local hp, outcome = Police.hit(o, dmg, combo, dx, dz, player)
		if not hp then
			send(player, { kind = "miss", reason = "down" })
			return
		end
		send(player, { kind = "hit", target = "police", id = o.id, dmg = dmg, hp = hp, maxHp = CFG.POLICE_HP, outcome = outcome, dx = dx, dz = dz, combo = combo })
		stats.hits += 1
		track(player, "punch_hit")
		s.fightUntil = os.clock() + 12
		if s.order then
			-- fists instead of hands up: the stop order is over (the assault is the crime, not a flight)
			s.order = nil
			send(player, { kind = "stopEnd" })
		end
		Crime.addCrime(player, "assault_police", { victim = "police", pos = feet })
		if outcome == "ko" then
			track(player, "crime_ko")
			Crime.addCrime(player, "ko", { victim = o.id, pos = feet })
		end
		alarm(player, feet, if outcome == "ko" or outcome == "knockdown" then 3 else 2, o.id)
		return
	end
	-- civilians: key NPCs (shared HP) / pedestrians (HP per attacker)
	local dmg = CFG.PUNCH.npcDmg[combo] or 10
	local isKey = t.kind == "npc"
	local key = if isKey then t.id else "s:" .. t.id
	local entry = npcHpEntry(if isKey then keyHp else s.npcHp, key, CFG.NPC_HP, now)
	if entry.koUntil > now then
		send(player, { kind = "miss", reason = "down" })
		return
	end
	entry.hp = math.max(0, entry.hp - dmg)
	entry.t = now
	local outcome = Combat.outcome(combo, entry.hp)
	if outcome == "ko" then
		entry.koUntil = now + CFG.NPC_KO_TIME
	end
	send(player, { kind = "hit", target = t.kind, id = t.id, dmg = dmg, hp = entry.hp, maxHp = CFG.NPC_HP, outcome = outcome, dx = dx, dz = dz, combo = combo, typeId = t.c and t.c.type or "plain" })
	stats.hits += 1
	track(player, "punch_hit")
	local victimKey = if isKey then t.id else "s:" .. t.id
	local firstHit = (s.victims["assault|" .. victimKey] or -1e9) < now - CFG.SAME_VICTIM_WINDOW
	if isKey then
		-- everyone sees it: the NPC staggers / falls (NpcKnock) and is angry; it also calls the police
		local id = t.id
		if NPC then
			if outcome == "hit" then
				pcall(NPC.react, id, "cb_flinchF")
			else
				pcall(NPC.knock, id, dx, dz, if outcome == "stagger" then "stagger" else "knockdown", player)
			end
		end
		if firstHit then
			award(player, id)
		end
		local sp = speechOf(id)
		local text = if outcome == "ko" then (if sp == "busan" then "으윽… 니 진짜…" else "으윽… 경찰… 불러 주세요…") else Combat.line("victim", nil, sp)
		task.delay(if outcome == "knockdown" or outcome == "ko" then 1.6 else 0.35, function()
			say(id, text, t.c and t.c.type or "plain", 2.8)
		end)
		if firstHit then
			task.delay(2.2, function()
				local call = Combat.line("call", nil, sp)
				say(id, call, t.c and t.c.type or "plain", 3.2)
			end)
		end
	elseif t.plausible and t.c and firstHit then
		award(player, t.id)
	end
	local witnesses = keyWitnesses(player, feet, if isKey then t.id else nil)
	local reported = isKey or witnesses > 0
	Crime.addCrime(player, "assault", { victim = victimKey, pos = feet, reported = reported })
	if reported then
		Crime.report(player)
	end
	if outcome == "ko" then
		track(player, "crime_ko")
		Crime.addCrime(player, "ko", { victim = victimKey, pos = feet })
	end
	alarm(player, feet, if outcome == "ko" then 3 elseif outcome == "hit" then 1 else 2, t.id)
end

local function onPunch(player: Player, s: PState, payload: any)
	stats.punches += 1
	local combo = Util.int(payload.combo, 1, 3) or 1
	local ok, why = canAct(player, s)
	if not ok then
		send(player, { kind = "miss", reason = why })
		return
	end
	local now = os.clock()
	-- latency jitter: two swings may arrive a little closer than the client's own cooldown
	if now - s.lastPunch < CFG.PUNCH.cooldown * 0.75 then
		return
	end
	s.lastPunch = now
	if not enabled() then
		send(player, { kind = "miss", reason = "off" })
		return
	end
	moveAttr(player, s, combo)
	local target = if type(payload.target) == "table" then payload.target else nil
	local kind = target and Util.str(target.kind, 12) or "none"
	if kind == "none" or not target then
		return
	end
	local _, _, root = Util.alive(player)
	if not root then
		return
	end
	local myPos = root.Position
	local targetPos, why2, t = resolveTarget(player, s, kind, target.id, payload, myPos)
	if not targetPos or not t then
		stats.misses += 1
		send(player, { kind = "miss", reason = why2 or "bad" })
		return
	end
	local reach = CFG.PUNCH.range + CFG.PUNCH.rangeSlack
	local d = flatDist(targetPos, myPos)
	if d > reach then
		stats.misses += 1
		send(player, { kind = "miss", reason = "far" })
		return
	end
	if math.abs(targetPos.Y - myPos.Y) > CFG.PUNCH.dyMax then
		stats.misses += 1
		send(player, { kind = "miss", reason = "height" })
		return
	end
	if d > 1.2 and Combat.facingDot(root.CFrame, targetPos) < CFG.PUNCH.facing then
		stats.misses += 1
		send(player, { kind = "miss", reason = "facing" })
		return
	end
	local serial = s.charSerial
	task.delay(CFG.PUNCH.hitDelay[combo] or 0.15, function()
		if player.Parent ~= Players or s.charSerial ~= serial or s.ko or s.arresting then
			return
		end
		local okH, err = pcall(applyHit, player, s, combo, t, targetPos)
		if not okH then
			warn("[GwangalliCrime] punch failed: " .. tostring(err))
		end
	end)
end

-- a violent pedestrian (client crowd) punched this player: limited damage to the reporter only
local function onStreetHit(player: Player, s: PState, payload: any)
	local now = os.clock()
	if now - s.lastStreetHit < CFG.STREET_HIT.rate then
		return
	end
	local id = Util.str(payload.id, 40)
	if not id then
		return
	end
	local c = citizen(id)
	local anon = string.match(id, "^x%d+$") ~= nil
	if not anon and not (c and c.type == "violent" and c.key ~= true) then
		return
	end
	local pos = Combat.unpackV(payload.pos)
	local myPos = Util.rootPosition(player)
	if not pos or not myPos or flatDist(pos, myPos) > CFG.STREET_HIT.reach or math.abs(pos.Y - myPos.Y) > 6 then
		return
	end
	if now < s.downUntil then
		return
	end
	s.lastStreetHit = now
	local combo = Util.int(payload.combo, 1, 3) or 1
	local dmg = math.min(CFG.STREET_HIT.maxDmg, ({ 6, 7, 9 })[combo] or 6)
	local dx, dz = Combat.flatDir(pos, myPos)
	Crime.damage(player, dmg, { by = id, byKind = "street", dx = dx, dz = dz, outcome = if combo >= 3 then "knockdown" elseif combo == 2 then "stagger" else "hit" })
end

local function onReport(player: Player, s: PState, payload: any)
	local now = os.clock()
	if now - s.lastReport < 1.5 or #s.pending == 0 then
		return
	end
	local id = Util.str(payload.id, 40)
	local pos = Combat.unpackV(payload.pos)
	local myPos = Util.rootPosition(player)
	if not id or not pos or not myPos or flatDist(pos, myPos) > REPORT_RANGE then
		return
	end
	if not string.match(id, "^x%d+$") then
		local c = citizen(id)
		if not c then
			return
		end
		if Citizens and type(Citizens.plausible) == "function" then
			local ok, res = pcall(Citizens.plausible, id, pos, clockNow(), areaPos, 160)
			if ok and res == false then
				return
			end
		end
	end
	s.lastReport = now
	Crime.report(player)
end

local function onSurrender(player: Player, s: PState)
	if s.stars <= 0 or s.arresting or s.ko or s.surrender then
		return
	end
	local _, hum = Util.alive(player)
	if not hum or hum.Sit then
		return
	end
	-- an officer must be around to surrender to
	local o, d = nil, math.huge
	if Police then
		o, d = Police.nearest(player)
	end
	if not o or d > 30 then
		send(player, { kind = "miss", reason = "nopolice" })
		return
	end
	s.surrender = true
	s.surrenderAt = os.clock()
	s.order = nil
	send(player, { kind = "stopEnd" })
	setPose(player, "handsup")
	freeze(player)
	pcall(Police.surrendered, player)
end

local function onFlee(player: Player, s: PState)
	if not s.order or s.arresting or s.surrender then
		return
	end
	Crime.fled(player, s.order.officer, "button")
end

local handlers: { [string]: (Player, PState, any) -> () } = {
	punch = onPunch,
	streetHit = onStreetHit,
	report = onReport,
	surrender = function(player, s, _p)
		onSurrender(player, s)
	end,
	flee = function(player, s, _p)
		onFlee(player, s)
	end,
}

local function onAction(player: Player, kind: any, payload: any)
	if type(kind) ~= "string" or not handlers[kind] then
		return
	end
	if payload ~= nil and type(payload) ~= "table" then
		return
	end
	local s = state(player)
	if not s or not takeToken(s) then
		return
	end
	if not Profiles.get(player) then
		send(player, { kind = "miss", reason = "loading" })
		return
	end
	local ok, err = pcall(handlers[kind], player, s, payload or {})
	if not ok then
		warn(string.format("[GwangalliCrime] %s from %s failed: %s", kind, player.Name, tostring(err)))
	end
end

-------------------------------------------------------------------------------------------------
-- 어깨빵 on an officer (GwangalliBump ignores ids it does not know): 공무집행방해
-------------------------------------------------------------------------------------------------
local function onBumpAction(player: Player, kind: any, payload: any)
	if kind ~= "bump" or type(payload) ~= "table" or payload.target ~= "npc" then
		return
	end
	local id = payload.id
	if not Combat.isPoliceId(id) or not Police or not BumpShared then
		return
	end
	local s = state(player)
	if not s or not takeToken(s) or not Profiles.get(player) then
		return
	end
	local okAct = canAct(player, s)
	if not okAct or not Util.cooldown(player, "crime:bumpPolice", BumpShared.COOLDOWN or 1.2) then
		return
	end
	local o = Police.get(id)
	local p = o and Police.position(o)
	local _, _, root = Util.alive(player)
	if not o or not p or not root then
		return
	end
	local reach = (BumpShared.RANGE or 5.5) + (BumpShared.RANGE_SLACK or 2.5)
	if flatDist(p, root.Position) > reach or Combat.facingDot(root.CFrame, p) < (BumpShared.FACING or 0.2) then
		return
	end
	local dx, dz = Combat.flatDir(root.Position, p)
	local hp, outcome = Police.hit(o, 4, 2, dx, dz, player)
	if not hp then
		return
	end
	local puk = if Social and Social.PUK then Social.PUK[math.random(#Social.PUK)] else "퍽!"
	if remotes.BumpEvent then
		remotes.BumpEvent:FireClient(player, { kind = "hit", target = "npc", id = id, outcome = if outcome == "knockdown" or outcome == "ko" then "knockdown" else "stagger", dx = dx, dz = dz, puk = puk, typeId = "police" })
	end
	s.fightUntil = os.clock() + 12
	if s.order then
		s.order = nil
		send(player, { kind = "stopEnd" })
	end
	Crime.addCrime(player, "assault_police", { victim = "police", pos = p })
	alarm(player, p, 2, id)
end

-------------------------------------------------------------------------------------------------
-- Police hooks (the officers' brain lives in the child module Police)
-------------------------------------------------------------------------------------------------
-- the officer `officerId` gave the stop order
function Crime.ordered(player: Player, officerId: string)
	local s = states[player]
	if not s or s.arresting or s.ko or s.surrender then
		return
	end
	s.order = { officer = officerId, untilT = os.clock() + CFG.ORDER_TIMEOUT }
	s.orderAt = os.clock()
	send(player, { kind = "stop", officer = officerId, timeout = CFG.ORDER_TIMEOUT })
end

-- the suspect ran from / ignored the stop order
function Crime.fled(player: Player, officerId: string?, how: string?)
	local s = states[player]
	if not s or not s.order then
		return
	end
	s.order = nil
	send(player, { kind = "stopEnd" })
	Crime.addCrime(player, "flee", { pos = standFeet(player) })
	if officerId then
		say(officerId, Combat.line("police", "chase"), "police", 2.2)
	end
	local _ = how
end

-- an officer reached the suspect: a tackle (not surrendering) or the cuffs (surrendered / KO)
function Crime.grab(player: Player, officerId: string, tackle: boolean, dx: number?, dz: number?)
	local s = states[player]
	local now = os.clock()
	if not s or s.arresting or now - s.tackleAt < 2.5 then
		return
	end
	if tackle and not s.ko then
		s.tackleAt = now
		local _, hum = Util.alive(player)
		if hum then
			s.downUntil = math.max(s.downUntil, os.clock() + 2.1 + DOWN_GRACE)
			local h, m = hpView(hum)
			send(player, { kind = "hurt", by = officerId, byKind = "police", dmg = 0, hp = h, maxHp = m, dx = dx or 0, dz = dz or -1, outcome = "knockdown" })
		end
		say(officerId, "꼼짝 마! 경찰이다!", "police", 2.2)
		task.delay(1.4, function()
			if player.Parent == Players and not s.arresting then
				arrest(player, "forced", officerId)
			end
		end)
		return
	end
	arrest(player, if s.surrender then "surrender" else "forced", officerId)
end

-- an officer's punch landed (POLICE_PUNCH)
function Crime.policePunch(player: Player, officerId: string, combo: number, dx: number, dz: number)
	local outcome = if combo >= 3 then "stagger" else "hit"
	Crime.damage(player, CFG.POLICE_PUNCH.dmg, { by = officerId, byKind = "police", dx = dx, dz = dz, outcome = outcome })
end

-- an officer saw / lost the suspect this tick (aggregated over the squad)
function Crime.sighted(player: Player, seen: boolean, pos: Vector3?)
	local s = states[player]
	if not s or s.stars <= 0 then
		return
	end
	if seen then
		s.lastSeen = os.clock()
		if pos then
			s.lastKnown = pos
		end
		-- an officer saw it: crimes waiting for a report are witnessed now
		if #s.pending > 0 then
			confirmPending(player, s)
		end
	end
	if s.seen ~= seen then
		s.seen = seen
		if player.Parent == Players then
			player:SetAttribute(Combat.Attr.PoliceChase, seen and not s.arresting)
		end
		if not seen and not s.arresting then
			send(player, { kind = "search", left = math.max(0, math.ceil(Combat.searchTime(s.stars) - (os.clock() - s.lastSeen))) })
		end
	end
end

function Crime.stateOf(player: Player): PState?
	return states[player]
end

-------------------------------------------------------------------------------------------------
-- Loops
-------------------------------------------------------------------------------------------------
local function wantedTick(now: number)
	for player, s in states do
		if player.Parent ~= Players then
			continue
		end
		-- reports that nobody made: someone always calls after REPORT_DELAY
		if #s.pending > 0 then
			local keep = {}
			for _, p in s.pending do
				if now >= p.at then
					confirm(player, s, p.crime, p.pos)
				else
					table.insert(keep, p)
				end
			end
			s.pending = keep
		end
		if s.stars > 0 and not s.arresting and not s.ko then
			if s.order and Police and not Police.active(s.order.officer) then
				-- the officer who gave the order is down / gone: no order to break any more
				s.order = nil
				send(player, { kind = "stopEnd" })
			elseif s.order and now > s.order.untilT then
				Crime.fled(player, s.order.officer, "ignored")
			end
			if s.surrender and now - s.surrenderAt > 9 then
				-- nobody could reach the suspect (blocked path): the arrest happens anyway
				arrest(player, "surrender", nil)
			elseif not s.seen and not s.surrender then
				local limit = Combat.searchTime(s.stars)
				local left = limit - (now - s.lastSeen)
				if left <= 0 then
					s.stars -= 1
					s.lastSeen = now
					if s.stars <= 0 then
						escaped(player, s)
					else
						setWantedAttrs(player, s)
						notify(player, "warn", "🚨 수배 " .. Combat.starsText(s.stars), "경찰이 당신을 놓치고 있어요. 계속 숨어 있어요!")
						if Police then
							pcall(Police.ensure, player, s.stars)
						end
						send(player, { kind = "search", left = math.ceil(Combat.searchTime(s.stars)) })
					end
				else
					local shown = math.ceil(left)
					if shown ~= s.searchShown then
						s.searchShown = shown
						player:SetAttribute(Combat.Attr.WantedSearch, shown)
					end
				end
			elseif s.searchShown ~= 0 then
				s.searchShown = 0
				player:SetAttribute(Combat.Attr.WantedSearch, 0)
			end
		end
	end
end

local function regenTick(dt: number)
	local now = os.clock()
	for player, s in states do
		if player.Parent ~= Players or s.ko or s.arresting then
			continue
		end
		if now - s.lastDamage < CFG.REGEN_DELAY then
			continue
		end
		local character = player.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
			hum.Health = math.min(hum.MaxHealth, hum.Health + CFG.REGEN_PER_SEC * dt)
		end
	end
	-- forget NPC HP nobody touched for a while (memory)
	for id, e in keyHp do
		if now - e.t > CFG.NPC_HP_RESET * 3 and now > (e.koUntil or 0) then
			keyHp[id] = nil
		end
	end
end

local function debtTick()
	for player, s in states do
		if player.Parent ~= Players or s.arresting or s.stars > 0 then
			continue
		end
		local c = crimeData(player)
		if not c or c.debt <= 0 then
			continue
		end
		local paid, left = payFine(player, c.debt, CFG.FINE_LABEL .. " (미납분 자동 납부)", DEBT_CASH_RESERVE)
		if paid > 0 then
			c.debt = left
			pcall(Profiles.markDirty, player)
			pushRecordAttrs(player)
			if left <= 0 then
				track(player, "fine_paid")
				notify(player, "info", "🚓 미납 범칙금 완납", string.format("-%s · 이제 미납금이 없어요", won(paid)))
			elseif paid >= 1000 then
				notify(player, "warn", "🚓 미납 범칙금 자동 납부", string.format("-%s · 남은 미납 %s", won(paid), won(left)))
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Feature hooks
-------------------------------------------------------------------------------------------------
function Crime.onLoaded(player: Player)
	local s = state(player)
	pushRecordAttrs(player)
	if s and player.Parent == Players then
		player:SetAttribute(Combat.Attr.Wanted, s.stars)
		player:SetAttribute(Combat.Attr.PoliceChase, false)
		player:SetAttribute(Combat.Attr.Arrested, s.arresting)
		player:SetAttribute(Combat.Attr.WantedSearch, 0)
	end
end

local function setupCharacter(player: Player, character: Model, serial: number)
	local hum = character:WaitForChild("Humanoid", 10)
	if not hum or not hum:IsA("Humanoid") or player.Character ~= character then
		return
	end
	local s = states[player]
	if not s or s.charSerial ~= serial then
		return
	end
	hum.MaxHealth = CFG.MAX_HP
	hum.Health = CFG.MAX_HP
	-- Roblox's default "Health" script regenerates 1%/s from the first hit: our regen owns HP
	local hs = character:WaitForChild("Health", 3)
	if hs and hs:IsA("Script") and player.Character == character then
		(hs :: any).Disabled = true
	end
end

function Crime.onCharacter(player: Player, character: Model)
	local s = state(player)
	if not s then
		return
	end
	s.charSerial += 1
	local serial = s.charSerial
	local respawn = s.spawned
	s.spawned = true
	s.ko = false
	s.koMode = nil
	s.frozen = nil
	s.surrender = false
	s.order = nil
	s.downUntil = 0
	s.lastDamage = -1e9
	character:SetAttribute(Combat.Attr.KO, false)
	character:SetAttribute(Combat.Attr.Pose, "")
	character:SetAttribute(Combat.Attr.Move, "")
	task.spawn(setupCharacter, player, character, serial)
	if s.arresting then
		-- mid-arrest respawn: the arrest thread finishes with the new character
		return
	end
	if respawn and s.stars > 0 then
		-- a wanted player who respawned (reset / void) is not let off: taken to the station
		player:SetAttribute(Combat.Attr.Arrested, true) -- also keeps Housing's respawn-home teleport out
		task.delay(2, function()
			if player.Parent == Players and s.charSerial == serial and s.stars > 0 and not s.arresting then
				arrest(player, "forced", nil)
			elseif player.Parent == Players and not s.arresting then
				player:SetAttribute(Combat.Attr.Arrested, false)
			end
		end)
	end
end

function Crime.onLeave(player: Player)
	if Police then
		pcall(Police.clear, player)
	end
	carRelease(player)
	states[player] = nil
end

function Crime.debugStats(): any
	local out = table.clone(stats)
	out.avgTickMs = if stats.tickN > 0 then stats.tickT / stats.tickN * 1000 else 0
	out.maxTickMs = stats.tickMax * 1000
	if Police and Police.stats then
		out.police = Police.stats()
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------------------------
local function makeRemotes()
	local folder = ReplicatedStorage:FindFirstChild(Combat.Folder)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	local fresh = folder == nil
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Combat.Folder
	end
	local function remote(name: string): RemoteEvent
		local r = (folder :: Instance):FindFirstChild(name)
		if r and not r:IsA("RemoteEvent") then
			r:Destroy()
			r = nil
		end
		if not r then
			r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
		return r :: RemoteEvent
	end
	remotes.Action = remote(Combat.Remote.Action)
	remotes.Event = remote(Combat.Remote.Event)
	-- parent the folder last so clients that find it also find both remotes
	if fresh then
		(folder :: Instance).Parent = ReplicatedStorage
	end
end

function Crime.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	Combat = requireShared("GwangalliCombatShared", 20)
	if not Combat then
		warn("[GwangalliCrime] ReplicatedStorage.GwangalliCombatShared missing; 전투·범죄·경찰 disabled")
		return
	end
	CFG = Combat.CONFIG
	BumpShared = requireShared("GwangalliBumpShared", 5)
	Social = requireShared("GwangalliSocialShared", 5)
	Citizens = requireShared("GwangalliCitizens", 5)
	Live = requireShared("GwangalliLiveConfig", 2)
	local cfgMod = ReplicatedStorage:FindFirstChild("GwangalliConfig")
	if cfgMod and cfgMod:IsA("ModuleScript") then
		local ok, res = pcall(require, cfgMod)
		if ok and type(res) == "table" and type(res.Sprint) == "table" and tonumber(res.Sprint.WalkSpeed) then
			BASE_WALK = tonumber(res.Sprint.WalkSpeed) :: number
		end
	end
	local folder = script.Parent
	NPC = requireSibling(folder, "NPC")
	makeRemotes()
	-- GwangalliBump remotes (bubbles over key NPCs, 어깨빵 on officers)
	local bumpFolder = BumpShared and (ReplicatedStorage:FindFirstChild(BumpShared.Folder) or ReplicatedStorage:WaitForChild(BumpShared.Folder, 5))
	if bumpFolder then
		local be = bumpFolder:FindFirstChild(BumpShared.Remote.Event)
		if be and be:IsA("RemoteEvent") then
			remotes.BumpEvent = be
		end
		local ba = bumpFolder:FindFirstChild(BumpShared.Remote.Action)
		if ba and ba:IsA("RemoteEvent") then
			ba.OnServerEvent:Connect(function(player: Player, kind: any, payload: any)
				local ok, err = pcall(onBumpAction, player, kind, payload)
				if not ok then
					warn("[GwangalliCrime] bump on officer failed: " .. tostring(err))
				end
			end)
		end
	end
	-- the officers (child module) and the optional patrol car
	Police = requireSibling(script, "Police")
	PoliceCar = requireSibling(script, "PoliceCar")
	if Police then
		local okP, errP = pcall(Police.init, {
			ctx = ctx,
			Util = Util,
			Combat = Combat,
			BumpShared = BumpShared,
			crime = Crime,
			send = send,
			sendAll = sendAll,
		})
		if not okP then
			warn("[GwangalliCrime] police init failed: " .. tostring(errP))
			Police = nil
		end
	else
		warn("[GwangalliCrime] child module Police missing: no officers")
	end
	if PoliceCar and type(PoliceCar.init) == "function" then
		local okC, errC = pcall(PoliceCar.init, ctx, Crime)
		if not okC then
			warn("[GwangalliCrime] PoliceCar init failed: " .. tostring(errC))
		end
	end
	if Profiles and type(Profiles.sanitize) == "function" then
		-- record / unpaid fines persist only when Profiles keeps d.crime (the server.luau patch)
		local okProbe, probe = pcall(Profiles.sanitize, { v = G.VERSION, crime = { record = 1, debt = 1000 } })
		if not (okProbe and type(probe) == "table" and type(probe.crime) == "table") then
			warn("[GwangalliCrime] Profiles does not keep d.crime: 전과 / 미납 범칙금 stay in memory this session")
		end
	end
	(remotes.Action :: RemoteEvent).OnServerEvent:Connect(onAction)
	for _, player in Players:GetPlayers() do
		state(player)
	end
	-- the brain: police (4 Hz) + wanted bookkeeping
	task.spawn(function()
		while true do
			task.wait(TICK)
			local t0 = os.clock()
			if Police then
				local ok, err = pcall(Police.tick)
				if not ok then
					warn("[GwangalliCrime] police tick failed: " .. tostring(err))
				end
			end
			local ok2, err2 = pcall(wantedTick, os.clock())
			if not ok2 then
				warn("[GwangalliCrime] wanted tick failed: " .. tostring(err2))
			end
			local dt = os.clock() - t0
			stats.tickN += 1
			stats.tickT += dt
			stats.tickMax = math.max(stats.tickMax, dt)
		end
	end)
	task.spawn(function()
		local last = os.clock()
		local debtAt = os.clock() + DEBT_TICK
		while true do
			task.wait(REGEN_TICK)
			local now = os.clock()
			local ok, err = pcall(regenTick, math.min(2, now - last))
			last = now
			if not ok then
				warn("[GwangalliCrime] regen failed: " .. tostring(err))
			end
			if now >= debtAt then
				debtAt = now + DEBT_TICK
				local okD, errD = pcall(debtTick)
				if not okD then
					warn("[GwangalliCrime] fine collection failed: " .. tostring(errD))
				end
			end
		end
	end)
	ctx.crime = Crime
	print("[GwangalliCrime] ready (전투 · 수배 · 경찰)")
end

return Crime
