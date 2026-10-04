-- GwangalliCombatShared — 전투 · 범죄 · 경찰 (combat / crime / police) contract shared by the server feature module
-- (ServerScriptService.GwangalliGameplay.Crime) and the client (StarterPlayerScripts.GwangalliCombat).
-- Pure data + pure helpers: requiring it creates nothing and never yields (like GwangalliHealthShared).
--
-- Remotes (server creates them; the folder is parented last):
--   ReplicatedStorage.GwangalliCombat.CombatAction  (RemoteEvent, client -> server)  FireServer(kind, payload)
--     "punch"     { combo = 1|2|3, target = { kind = "street"|"npc"|"police"|"player"|"none", id = string|number?, pos = {x,y,z}? } }
--     "streetHit" { id = string, pos = {x,y,z}, combo = 1|2|3 }   a violent pedestrian (client crowd) punched the local player
--     "report"    { id = string, pos = {x,y,z} }                  a pedestrian witness on this client phoned the police
--     "surrender" {}                                              answer to a stop order
--     "flee"      {}                                              the player pressed 도주 on the stop order
--   ReplicatedStorage.GwangalliCombat.CombatEvent   (RemoteEvent, server -> client)  payload.kind:
--     "hit"     (attacker)  { target, id, dmg, hp, maxHp, outcome = "hit"|"stagger"|"knockdown"|"ko", dx, dz, combo }
--     "miss"    (attacker)  { reason }
--     "hurt"    (victim)    { by, byKind, dmg, hp, maxHp, dx, dz, outcome }
--     "crime"   (criminal)  { crime, label, stars, reported }
--     "alarm"   (all)       { pos = {x,y,z}, radius, severity = 1..3, victim, attacker = userId }
--     "stop"    (suspect)   { officer = npcId, timeout }      "stopEnd" {}
--     "arrest"  (suspect)   { phase = "start" } | { phase = "done", fine, paid, debt, crimes = {{label, fine}}, record, forced }
--     "ko"      (victim)    { mode = "hospital"|"arrest" }    "wake" {}
--     "say"     (all)       { id = npcId, text, typeId, dur }
--     "search"  (suspect)   { left = seconds }
--     "escaped" (suspect)   {}
-- Attributes (server writes): Player Wanted / PoliceChase / Arrested / WantedSearch / CrimeRecord / FineDebt;
-- Character GwKO / GwCombatPose / GwCombatMove; police models: the GwangalliNPCs contract + PoliceTarget / PoliceState.
-- Names Wanted / Arrested / PoliceChase / GwKO are also read by GwangalliGameplay.Housing (no hiding from the police).

local Combat = {}

Combat.VERSION = 1
Combat.Folder = "GwangalliCombat"
Combat.Remote = { Action = "CombatAction", Event = "CombatEvent" }

Combat.Attr = {
	-- Player
	Wanted = "Wanted", -- int 0..5
	PoliceChase = "PoliceChase", -- bool: an officer currently sees the player
	Arrested = "Arrested", -- bool: during the arrest sequence
	WantedSearch = "WantedSearch", -- number: seconds left before one star drops (0 while seen)
	CrimeRecord = "CrimeRecord", -- int: arrests so far
	FineDebt = "FineDebt", -- int won: unpaid fines
	-- Character
	KO = "GwKO", -- bool
	Pose = "GwCombatPose", -- "" | "handsup" | "cuffed" | "ko"
	Move = "GwCombatMove", -- "jab#seq#serverTime" (other clients play it)
	-- Police model (plus the GwangalliNPCs NpcId / NpcKind / NpcAct / NpcLeg / NpcYaw / NpcEmote / NpcGround / NpcKnock)
	PoliceTarget = "PoliceTarget", -- UserId
	PoliceState = "PoliceState", -- "dispatch"|"chase"|"order"|"fight"|"cuff"|"search"|"leave"
	EmuFK = "GwEmuFK", -- emulator only: render this rig's Motor6D pose (real Roblox ignores it)
	-- existing contracts this system honours
	BumpEnabled = "BumpEnabled", -- false = this player opted out of PvP contact (어깨빵 and punches)
	Knocked = "GwangalliKnocked", -- BumpShared: the character is in a knockdown
}

Combat.POLICE_KIND = "police"
Combat.POLICE_PREFIX = "police_"
Combat.STATION = "광안지구대" -- Destination DisplayName (GwangalliNav.places too)
Combat.HOSPITAL = "광안 중앙병원"

Combat.CONFIG = {
	MAX_HP = 100,
	REGEN_DELAY = 6, -- seconds without damage before HP regenerates
	REGEN_PER_SEC = 4,
	PUNCH = {
		cooldown = 0.32, -- server: minimum time between two accepted punches
		comboWindow = 0.9, -- client: the combo resets after this idle time
		range = 4.6, -- flat reach from the attacker's root to the target root
		rangeSlack = 2.2, -- server tolerance (latency)
		facing = 0.25, -- min dot(look, toTarget) (server); the client uses 0.35
		dyMax = 5.5,
		dmg = { 8, 10, 16 }, -- vs players
		npcDmg = { 10, 12, 18 }, -- vs pedestrians / key NPCs / police
		hitDelay = { 0.12, 0.16, 0.24 }, -- contact time of the clip (server applies the hit after this delay)
		clip = { "jab", "cross", "hook" },
	},
	NPC_HP = 34,
	POLICE_HP = 70,
	NPC_HP_RESET = 20, -- seconds without hits before an NPC's HP is full again
	NPC_KO_TIME = 5, -- seconds a KO'd NPC stays down
	STREET_HIT = { maxDmg = 9, rate = 0.9, reach = 7 }, -- violent pedestrian punches (client-reported)
	REPORT_DELAY = 3, -- an unreported civilian assault becomes a star after this (someone always calls)
	SAME_VICTIM_WINDOW = 8, -- re-hitting the same victim within this doesn't stack another assault star
	MAX_STARS = 5,
	SEARCH_TIME = { 14, 18, 24, 30, 36 }, -- out of sight this long (by current stars) -> one star less
	SIGHT = 70, -- studs an officer can see the suspect (plus a line-of-sight ray)
	ORDER_RANGE = 9, -- officer gives the stop order inside this
	GRAB_RANGE = 3.2, -- officer tackles / cuffs inside this
	ORDER_TIMEOUT = 6,
	OFFICERS = { 1, 2, 2, 3, 4 }, -- officers on foot by stars
	CAR_AT = 3, -- stars >= this also dispatch a patrol car
	SPAWN_MIN = 45,
	SPAWN_MAX = 70,
	POLICE_SPEED = { walk = 9, run = { 17, 17.5, 19.5, 20.5, 21.5 } }, -- player: walk 16, sprint 26 (stamina)
	POLICE_PUNCH = { dmg = 10, cadence = 1.1, range = 4.2 },
	FINE_SURRENDER = 0.8,
	FINE_FORCED = 1.5,
	FINE_CAP = 1000000,
	HOSPITAL_FEE = 15000,
	HOSPITAL_LABEL = "광안메디컬 응급 진료 (폭행)", -- "메디컬/진료" -> Progress classifies it as med
	FINE_LABEL = "광안지구대 범칙금", -- paid with bank.post kind "fee" -> Progress classifies it as fee
}

Combat.CRIMES = {
	assault = { label = "폭행", stars = 1, fine = 30000, needsReport = true },
	ko = { label = "상해", stars = 1, fine = 50000 },
	assault_player = { label = "폭행 (시민)", stars = 1, fine = 40000 },
	assault_police = { label = "공무집행방해", stars = 2, fine = 100000 },
	flee = { label = "도주", stars = 1, fine = 50000 },
}

-- Korean lines. std / busan follow the citizen's `speech` field like GwangalliSocialShared.TYPE_LINES.
Combat.LINES = {
	police = {
		dispatch = { "본부, 현장으로 이동합니다!", "신고 들어왔습니다, 출동!", "용의자 확인하러 갑니다." },
		chase = { "거기 서!", "도망가지 마!", "멈춰!", "놓치지 마!", "저기다!" },
		order = { "멈춰! 경찰이다! 손 들어!", "경찰입니다! 그 자리에 멈추세요!", "손 들고 엎드려!" },
		fight = { "공무집행방해야!", "저항하지 마!", "제압합니다!" },
		cuff = { "체포합니다. 순순히 따라오세요.", "수갑 채웁니다.", "변호사를 선임할 권리가 있습니다." },
		search = { "어디 갔지…?", "이 근처에 있을 텐데…", "본부, 용의자 수색 중." },
		lost = { "놓쳤다… 본부, 용의자 놓쳤습니다.", "에이, 오늘은 운 좋네.", "철수합니다." },
		hit = { "윽!", "이게 감히!", "크윽…" },
		station = { "다음엔 이런 일 없도록 하세요.", "벌금 내셨으면 가셔도 됩니다.", "조심히 다니세요." },
	},
	victim = {
		std = { "아야!", "왜 때려요?!", "악!", "살려주세요!", "뭐 하는 거예요!" },
		busan = { "아야!", "와 때리노?!", "아이고!", "살려주이소!", "니 미쳤나!" },
	},
	witness = {
		std = { "꺄악!", "싸움 났어요!", "경찰 불러요!", "어머, 어떡해!", "저 사람 좀 말려요!" },
		busan = { "꺄악!", "싸움 났다!", "경찰 불러라!", "아이고 우짜노!", "저 사람 좀 말리라!" },
	},
	call = {
		std = { "여보세요, 경찰이죠? 여기 사람이 맞고 있어요!", "112죠? 광안리에서 싸움 났어요!" },
		busan = { "여보세요, 경찰이지예? 여기 사람 맞고 있어예!", "112지예? 광안리에서 싸움 났어예!" },
	},
	film = { "이거 찍어야 돼…", "와 대박…", "실화냐…" },
	fightback = {
		std = { "한번 해보자는 거야?", "너 오늘 큰일 났다!", "덤벼!" },
		busan = { "니 지금 뭐하노?!", "한판 붙어볼래?", "니 오늘 죽었다!" },
	},
}

local function pick(list: { string }?, rnd: number?): string?
	if type(list) ~= "table" or #list == 0 then
		return nil
	end
	local r = rnd or math.random()
	return list[math.clamp(math.floor(r * #list) + 1, 1, #list)]
end
Combat.pick = pick

-- a line from Combat.LINES: line("police", "order") or line("victim", nil, "busan")
function Combat.line(group: string, kind: string?, speech: string?, rnd: number?): string?
	local g = Combat.LINES[group]
	if type(g) ~= "table" then
		return nil
	end
	local bank = if kind then g[kind] else g
	if type(bank) == "table" and bank.std ~= nil then
		bank = if speech == "busan" and bank.busan then bank.busan else bank.std
	end
	return pick(bank :: any, rnd)
end

-- stars --------------------------------------------------------------------------------------------------------------
function Combat.clampStars(n: number): number
	return math.clamp(math.floor(n + 0.5), 0, Combat.CONFIG.MAX_STARS)
end
function Combat.starsText(n: number): string
	n = Combat.clampStars(n)
	return string.rep("★", n) .. string.rep("☆", Combat.CONFIG.MAX_STARS - n)
end
function Combat.searchTime(stars: number): number
	local t = Combat.CONFIG.SEARCH_TIME
	return t[math.clamp(stars, 1, #t)] or 20
end
function Combat.officersFor(stars: number): number
	local t = Combat.CONFIG.OFFICERS
	return if stars <= 0 then 0 else (t[math.clamp(stars, 1, #t)] or 1)
end
function Combat.policeRunSpeed(stars: number): number
	local t = Combat.CONFIG.POLICE_SPEED.run
	return t[math.clamp(stars, 1, #t)] or 17
end

-- fines --------------------------------------------------------------------------------------------------------------
-- crimes: { {crime = id, ...}, ... } (the episode's record); mode: "surrender" | "forced" | nil
function Combat.fineFor(crimes: { any }, mode: string?): number
	local sum = 0
	for _, c in crimes do
		local def = Combat.CRIMES[c.crime or c]
		if def then
			sum += def.fine
		end
	end
	if mode == "surrender" then
		sum *= Combat.CONFIG.FINE_SURRENDER
	elseif mode == "forced" then
		sum *= Combat.CONFIG.FINE_FORCED
	end
	sum = math.floor(sum / 1000 + 0.5) * 1000
	return math.clamp(sum, 0, Combat.CONFIG.FINE_CAP)
end

function Combat.won(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-" else "") .. out .. "원"
end

-- punches -----------------------------------------------------------------------------------------------------------
function Combat.outcome(combo: number, hpAfter: number): string
	if hpAfter <= 0 then
		return "ko"
	elseif combo >= 3 then
		return "knockdown"
	elseif combo == 2 then
		return "stagger"
	end
	return "hit"
end
function Combat.clipOf(combo: number): string
	local c = Combat.CONFIG.PUNCH.clip
	return c[math.clamp(combo, 1, #c)]
end

-- "name#seq#serverTime" (same shape as GwangalliNPCs NpcEmote)
function Combat.encodeMove(name: string, seq: number, t: number): string
	return string.format("%s#%d#%.2f", name, seq, t)
end
function Combat.decodeMove(s: any): (string?, number, number)
	if type(s) ~= "string" then
		return nil, 0, 0
	end
	local name, seq, t = string.match(s, "^([%w_]+)#(%d+)#([%d%.%-]+)$")
	return name, tonumber(seq) or 0, tonumber(t) or 0
end

function Combat.isPoliceId(id: any): boolean
	return type(id) == "string" and string.sub(id, 1, #Combat.POLICE_PREFIX) == Combat.POLICE_PREFIX
end

-- geometry (flat) ---------------------------------------------------------------------------------------------------
function Combat.packV(v: Vector3): { number }
	return { math.floor(v.X * 100 + 0.5) / 100, math.floor(v.Y * 100 + 0.5) / 100, math.floor(v.Z * 100 + 0.5) / 100 }
end
function Combat.unpackV(t: any): Vector3?
	if type(t) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(t[1]), tonumber(t[2]), tonumber(t[3])
	if not x or not y or not z or x ~= x or y ~= y or z ~= z then
		return nil
	end
	if math.abs(x) > 1e5 or math.abs(y) > 1e5 or math.abs(z) > 1e5 then
		return nil
	end
	return Vector3.new(x, y, z)
end
function Combat.flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end
-- dot of the attacker's flat look vector with the flat direction to the target (1 = straight ahead)
function Combat.facingDot(attackerCF: CFrame, target: Vector3): number
	local look = attackerCF.LookVector
	local fx, fz = look.X, look.Z
	local fl = math.sqrt(fx * fx + fz * fz)
	local dx, dz = target.X - attackerCF.Position.X, target.Z - attackerCF.Position.Z
	local dl = math.sqrt(dx * dx + dz * dz)
	if fl < 1e-4 or dl < 1e-4 then
		return 1
	end
	return (fx * dx + fz * dz) / (fl * dl)
end
-- unit flat direction from a to b (fall / knockback direction)
function Combat.flatDir(a: Vector3, b: Vector3): (number, number)
	local dx, dz = b.X - a.X, b.Z - a.Z
	local l = math.sqrt(dx * dx + dz * dz)
	if l < 1e-4 then
		return 0, -1
	end
	return dx / l, dz / l
end

return Combat
