-- GwangalliGameplayShared: data + pure helpers for the 광안리 GTA LIFE GAME (docs/LIFE_GAME_DESIGN.md):
-- bank + cash ledger, jobs / shifts / promotions, housing (rent / buy), NPC dialog, phone
-- messages / offers, taxi, gym, salon, shops. Owned by the server gameplay core
-- (src/ServerScriptService/GwangalliGameplay*); the phone UI only requires it. No instances are
-- created here and no Roblox globals are touched at require time (Lune unit tests require it).
--
-- REMOTES (ReplicatedStorage.GwangalliRemotes, created by the server at start; clients should
-- WaitForChild with a timeout and retry):
--   GetProfile     RemoteFunction client -> server () -> profile view (below) or nil while loading
--   ProfileChanged RemoteEvent    server -> client (partial profile view). Every top-level key that is
--                                 present REPLACES that key wholesale.
--   PhoneAction    RemoteEvent    client -> server (action: string, payload: table?). Actions:
--     "applyJob" {jobId}            "quitJob"                "startShift"       "endShift"
--     "workTask" {taskId, choice?, ok?}  (choice = 1-based index of task.choices for "choice" tasks;
--                                   "hold" / "goto" tasks complete on the server, "tap" tasks accept ok)
--     "callTaxi" {name?}  "taxiDestination" {name}  "cancelTaxi"
--     "callContact" {contactId}     (taxi -> dispatch; an NPC contact -> that NPC's dialog by phone)
--     "readThread" {contactId}      "reply" {contactId, choice}  (choice = choice id e.g. "accept" /
--                                   "decline", or a 1-based index into thread.choices)
--     "dialogChoice" {npcId, choiceId}
--     "rentHome" {listingId}  "buyHome" {listingId}  "enterHome"  "leaveHome"  "sleep"
--     "setWaypoint" {destination}  (Destination DisplayName; false / "" clears)
--     "buy" {itemId}                "equip" {itemId}
--     "bankTransfer" {direction = "deposit"|"withdraw", amount}   (cash <-> bank, anywhere: phone banking)
--   (legacy payload keys are accepted: contact = contactId, id = jobId / listingId)
--   Notify     RemoteEvent server -> client {kind = "message"|"job"|"money"|"stat"|"taxi"|"home"|"info"|"warn",
--                          title, body, contact?, sound?}
--   TaxiState  RemoteEvent server -> client {state = "coming"|"arrived"|"riding"|"done"|"cancelled", eta?,
--                          fare?, destination?, boarded?, reason?}
--   Dialog     RemoteEvent server -> client {npcId, name, role, portraitColor = Color3, text,
--                          choices = { {id, label} }, remote = bool? (a phone call)} or {close = true}
--   WorkState  RemoteEvent server -> client {jobId, jobTitle, place, onShift, level, levelTitle, wage,
--                          task = {id, kind = "goto"|"hold"|"choice"|"tap", prompt, target? (Destination
--                          DisplayName for the marker), position? (Vector3 of the work point),
--                          choices? = {label, ...}, timeLimit? (s)} | nil,
--                          progress = {done, total}, earnedShift, earnedToday}   ({jobId = nil} = no job)
--   BankRequest / BankEvent: 송금 / 송금 요청 / 현금 주기 / ATM -- see the "Bank" section at the end.
--   TaxiCall: 광안콜택시 phone call / ride / payment -- see the "Taxi call" section at the end.
--
-- PROFILE VIEW (GetProfile / ProfileChanged):
--   cash, bank: number (원)      money: = cash (legacy)     netWorth: cash + bank + owned home value
--   transactions: { {t = unix, amount (+/-), label, balance (after, of that account), account = "cash"|"bank"} }
--                  newest LAST, at most G.LEDGER_MAX
--   stats: { appearance, stamina, happiness, popularity, strength } (0..100, one decimal)
--   job: { id, title, place, level, levelTitle, xp, nextXp?, wage, onShift } | nil
--   careers: { [jobId] = level }
--   home: { listingId, tier, name, place, rentPerDay, owned, dueIn (s until the next daily charge),
--           missed (unpaid days), value? } | nil
--   housing: G.housingView(d) = { slots = {[slotId] = variantId} (current home), storage = {[variantId] = n},
--           storageCount, fridge, upgrades = {id...}, bills = {{t, day, kind, label, amount, paid}} (newest
--           first), loan = {listingId, remaining, daily, missed} | false, decor, comfort, value,
--           furnitureValue, utilityPerDay, housewarming = {done, count} }
--   threads: { [contactId] = { contact, name, role, icon, list = { {from = "them"|"me"|"system", text, t,
--              clock} }, msgs = (same), unread, choices = { {id, label} }?, offerId? } }
--   threadOrder: { contactId, ... } (most recent first)   unread: total unread messages
--   contacts: { {id, name, role, icon, color = {r,g,b}, kind = "friend"|"npc"|"service"} } (dial list)
--   offers: { {id, contact, title, body, kind} } (pending offers, newest first)
--   waypoint: Destination DisplayName | nil     inventory: { [itemId] = count }
--   outfit, hair, owned = {outfits, hair}, buffs = { [buffId] = {name, seconds?, sets?} }
--   clock: in-game day counter info { day = n (the player's own day count) }
--
-- PLAYER ATTRIBUTES (server-set, read-only elsewhere): Appearance, Happiness, Stamina, Popularity,
--   Strength (0..100 ints), Money (cash), Bank, Job (job id or ""), OnShift (bool), RunSpeedBonus
--   (studs/s, also on the Humanoid), ClubVIP, ClubGuestList, ClubVIPTable, InTaxi, GymBusy,
--   GwangalliProfileReady, HomeTier (0 = none).
--
-- WORLD TAGS: GymStation, SalonChair, ShopCounter, ElevatorButton, Destination (DisplayName).
-- HOMES (자기집 마련): per-player interior instances cloned from ServerStorage.GwangalliHomes
-- "HomeUnit_<tierKey>", furniture, visiting, remodelling, 주택담보대출 -- see the contract at the
-- "자기집 마련" section below (extra remotes HomeAction / HomeState / HomeQuery, profile view key
-- "housing" = G.housingView, player attributes InHome / HomeRole).

local G = {}

G.VERSION = 2
G.DATASTORE = "GwangalliProfile_v1"
G.KEY_PREFIX = "u_"

G.RemotesFolder = "GwangalliRemotes"
G.Remote = {
	GetProfile = "GetProfile",
	ProfileChanged = "ProfileChanged",
	PhoneAction = "PhoneAction",
	Notify = "Notify",
	TaxiState = "TaxiState",
	Dialog = "Dialog",
	WorkState = "WorkState",
}
G.Actions = {
	applyJob = true,
	quitJob = true,
	startShift = true,
	endShift = true,
	workTask = true,
	callTaxi = true,
	taxiDestination = true,
	cancelTaxi = true,
	callContact = true,
	readThread = true,
	reply = true,
	dialogChoice = true,
	rentHome = true,
	buyHome = true,
	enterHome = true,
	leaveHome = true,
	sleep = true,
	setWaypoint = true,
	buy = true,
	equip = true,
	bankTransfer = true,
}

G.Tags = {
	GymStation = "GymStation",
	SalonChair = "SalonChair",
	ShopCounter = "ShopCounter",
	ElevatorButton = "ElevatorButton",
	Destination = "Destination",
	ClubIDCheck = "ClubIDCheck",
}

G.Attr = {
	Appearance = "Appearance",
	Strength = "Strength",
	Stamina = "Stamina",
	Popularity = "Popularity",
	Happiness = "Happiness",
	Money = "Money",
	Bank = "Bank",
	Job = "Job",
	OnShift = "OnShift",
	HomeTier = "HomeTier",
	RunSpeedBonus = "RunSpeedBonus",
	ClubVIP = "ClubVIP",
	InTaxi = "InTaxi",
	GymBusy = "GymBusy",
	ProfileReady = "GwangalliProfileReady",
	LastBowlingScore = "LastBowlingScore",
	StationType = "StationType",
	ShopId = "ShopId",
	Floor = "Floor",
	Target = "Target",
	DisplayName = "DisplayName",
}

-------------------------------------------------------------------------------------------------
-- Stats and money
-------------------------------------------------------------------------------------------------
G.STAT_ORDER = { "appearance", "stamina", "happiness", "popularity", "strength", "fatigue" }
G.STATS = {
	appearance = { name = "외모지수", short = "외모", start = 20, icon = "✨", desc = "헤어·옷·운동으로 올라요. 클럽 입장과 사람들 반응이 달라져요." },
	stamina = { name = "체력", short = "체력", start = 80, icon = "🔋", desc = "일하면 줄고, 집에서 자거나 먹으면 회복돼요. 높을수록 빨리 달려요." },
	happiness = { name = "행복", short = "행복", start = 60, icon = "😊", desc = "클럽·카페·친구·좋은 집이 올려 줘요. 시간이 지나면 조금씩 줄어요." },
	popularity = { name = "인기도", short = "인기", start = 10, icon = "⭐", desc = "클럽, 친구, 맛집 인증으로 올라요." },
	strength = { name = "근력", short = "근력", start = 10, icon = "💪", desc = "헬스장 기구로 올라요. 높을수록 운동 효과가 커져요." },
	-- health (owner: health; server GwangalliGameplay/Health.luau, data G.HEALTH below): LOWER IS BETTER
	fatigue = { name = "피로도", short = "피로", start = 0, icon = "😮‍💨", desc = "일을 오래 하면 쌓여요. 50부터 급여가 줄고, 80을 넘긴 채 계속 일하면 병에 걸려요. 집에서 자면 확 내려가요.", inverted = true },
}
G.STAT_MIN = 0
G.STAT_MAX = 100
G.START_CASH = 30000
G.START_BANK = 100000
G.START_MONEY = G.START_CASH -- legacy name
G.MAX_MONEY = 999999999999
G.RUN_BONUS_MAX = 3 -- studs/s added to the sprint speed at stamina 100 (stamina is now daily energy, so keep it small)
G.ENERGY_RUN_BONUS = 3 -- extra studs/s while the "energy" buff is active

-- Club (CLUB OCEAN 광안): the MD lets you in for free at appearance >= entryAppearance, otherwise for
-- the cover charge. VIP table: popularity / happiness boost.
G.CLUB = {
	entryAppearance = 30,
	vipAppearance = 60,
	cover = 20000,
	vipTable = 300000,
	vipTableGain = { popularity = 6, happiness = 15 },
	entryGain = { happiness = 5, popularity = 1 },
	passSeconds = 1440, -- an entry lasts one in-game day
	visitPopularity = 1,
	vipBonus = 1,
}

-- Appearance thresholds at which friends notice (one compliment message each, once).
G.APPEARANCE_MILESTONES = { 30, 40, 50, 60, 75, 90 }

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
G.isFiniteNumber = isFiniteNumber

function G.clampStat(v: any): number
	if not isFiniteNumber(v) then
		return G.STAT_MIN
	end
	return math.clamp(math.floor(v * 10 + 0.5) / 10, G.STAT_MIN, G.STAT_MAX)
end

function G.clampMoney(v: any): number
	if not isFiniteNumber(v) then
		return 0
	end
	return math.clamp(math.floor(v), 0, G.MAX_MONEY)
end

-- Run speed bonus (studs/s) for a stamina value, rounded to 0.1.
function G.runSpeedBonus(stamina: number, energyBuff: boolean?): number
	local s = G.clampStat(stamina)
	local bonus = s / G.STAT_MAX * G.RUN_BONUS_MAX
	if energyBuff then
		bonus += G.ENERGY_RUN_BONUS
	end
	return math.floor(bonus * 10 + 0.5) / 10
end

-------------------------------------------------------------------------------------------------
-- Formatting
-------------------------------------------------------------------------------------------------
G.format = {}

-- 12300 -> "12,300원" ; -4800 -> "-4,800원"
function G.format.won(n: any): string
	local v = if isFiniteNumber(n) then math.floor(math.abs(n :: number) + 0.5) else 0
	local s = tostring(v)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	local neg = isFiniteNumber(n) and (n :: number) < 0 and v > 0
	return (if neg then "-" else "") .. out .. "원"
end

-- 12.345 -> "12.3" ; 12 -> "12"
function G.format.stat(v: any): string
	local x = G.clampStat(v)
	if x == math.floor(x) then
		return tostring(math.floor(x))
	end
	return string.format("%.1f", x)
end

-- In-game clock (0-24) -> "오후 9:30"
function G.format.clock(clock: any): string
	if not isFiniteNumber(clock) then
		return ""
	end
	local minutes = math.floor(((clock :: number) % 24) * 60 + 1e-6)
	local h, m = minutes // 60, minutes % 60
	local ampm = if h < 12 then "오전" else "오후"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%s %d:%02d", ampm, h12, m)
end

function G.format.seconds(s: any): string
	local v = if isFiniteNumber(s) then math.max(0, math.floor(s :: number)) else 0
	if v >= 60 then
		return string.format("%d분 %d초", v // 60, v % 60)
	end
	return string.format("%d초", v)
end

-------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------
-- Contacts (phone: 전화 / 메시지). kind: "friend" | "npc" (linked to G.NPCS[npc]) | "service".
-------------------------------------------------------------------------------------------------
G.CONTACT_ORDER = { "minji", "junho", "taxi", "boss", "cafe", "rider", "hoe", "lifeguard", "taxico", "realtor", "banker", "md", "landlord", "coach" }
G.CONTACTS = {
	minji = { name = "민지", role = "친구", icon = "🌸", color = { 255, 122, 162 }, kind = "friend", npc = "minji" },
	junho = { name = "준호", role = "친구", icon = "🧢", color = { 88, 160, 255 }, kind = "friend", npc = "junho" },
	taxi = { name = "광안 콜택시", role = "24시간 배차", icon = "🚕", color = { 255, 196, 0 }, kind = "service" },
	boss = { name = "김사장님", role = "GS25 광안리점", icon = "🏪", color = { 30, 160, 230 }, kind = "npc", npc = "gs25_owner" },
	cafe = { name = "이점장", role = "스타벅스 광안리점", icon = "☕", color = { 0, 112, 74 }, kind = "npc", npc = "starbucks_mgr" },
	rider = { name = "박매니저", role = "배달의광안 라이더 허브", icon = "🛵", color = { 42, 193, 188 }, kind = "npc", npc = "rider_mgr" },
	hoe = { name = "최사장님", role = "민락회타운 횟집", icon = "🐟", color = { 230, 90, 60 }, kind = "npc", npc = "hoe_boss" },
	lifeguard = { name = "강팀장", role = "광안리 수상구조대", icon = "🛟", color = { 240, 70, 60 }, kind = "npc", npc = "lifeguard_chief" },
	taxico = { name = "광안운수 배차실", role = "택시 회사", icon = "🚖", color = { 250, 180, 20 }, kind = "npc", npc = "taxi_dispatcher" },
	realtor = { name = "정실장", role = "광안역 부동산 공인중개사", icon = "🏠", color = { 120, 90, 200 }, kind = "npc", npc = "realtor" },
	banker = { name = "한주임", role = "BNK부산은행 광안동지점", icon = "🏦", color = { 214, 30, 60 }, kind = "npc", npc = "banker" },
	md = { name = "MD 태양", role = "CLUB OCEAN 광안", icon = "🕶️", color = { 170, 96, 255 }, kind = "npc", npc = "club_md" },
	landlord = { name = "집주인", role = "임대인", icon = "🔑", color = { 140, 140, 150 }, kind = "service" },
	coach = { name = "김코치", role = "광안 휘트니스 24 트레이너", icon = "💪", color = { 255, 168, 40 }, kind = "friend" },
}
G.CONTACT_ALIASES = { driver = "taxi", taeyang = "md" }

-- Accepts a contact id ("minji"), an alias, or its Korean name ("민지").
function G.resolveContact(v: any): string?
	if type(v) ~= "string" or #v == 0 or #v > 40 then
		return nil
	end
	if G.CONTACTS[v] then
		return v
	end
	if G.CONTACT_ALIASES[v] then
		return G.CONTACT_ALIASES[v]
	end
	for id, c in G.CONTACTS do
		if c.name == v then
			return id
		end
	end
	return nil
end

-- Taxi
-------------------------------------------------------------------------------------------------
-- Busan taxi: 4,800원 flag fall; distance charge per stud (game-scaled so a cross-map ride
-- costs about 10,000원); 20 % late-night surcharge 22:00-04:00; regulars (인기도 >= 50) get 10 %.
G.TAXI = {
	baseFare = 4800,
	perStud = 1.2,
	baseStuds = 400, -- distance included in the flag fall
	maxFare = 30000,
	nightSurcharge = 0.2,
	nightFrom = 22,
	nightTo = 4,
	regularPopularity = 50,
	regularDiscount = 0.1,
	maxConcurrent = 6, -- taxis in the world at once (server)
	callCooldown = 8, -- seconds between calls per player
	searchRadius = 320, -- studs: nearest road point to the player
	approachStuds = 110, -- the taxi drives this far along the road to the kerb
	approachSpeed = 30, -- studs/s
	waitSeconds = 120, -- the taxi waits this long at the kerb, then leaves
	destWaitSeconds = 60, -- seated without a destination this long -> the ride is cancelled
	boardDistance = 22, -- studs from the taxi to board (prompt / phone)
	walkAwayDistance = 400, -- caller further than this from the waiting taxi -> cancelled
	rideDriveSeconds = 3, -- visible drive-off before the fade
	arriveDriveSeconds = 2.5,
}

function G.inClockWindow(clock: number, from: number, to: number): boolean
	if from <= to then
		return clock >= from and clock < to
	end
	return clock >= from or clock < to
end

-- Fare in won (rounded to 100) for a ride of `studs`. `clock` (0-24) adds the night surcharge.
function G.taxiFare(studs: any, clock: number?, popularity: number?): number
	local T = G.TAXI
	local d = if isFiniteNumber(studs) then math.max(0, studs :: number) else 0
	local fare = T.baseFare + math.max(0, d - T.baseStuds) * T.perStud
	if clock and isFiniteNumber(clock) and G.inClockWindow(clock % 24, T.nightFrom, T.nightTo) then
		fare *= 1 + T.nightSurcharge
	end
	if popularity and isFiniteNumber(popularity) and popularity >= T.regularPopularity then
		fare *= 1 - T.regularDiscount
	end
	fare = math.min(fare, T.maxFare)
	return math.max(T.baseFare, math.floor(fare / 100 + 0.5) * 100)
end

-------------------------------------------------------------------------------------------------
-- Gym
-------------------------------------------------------------------------------------------------
-- gains: stat -> points per set before multipliers. duration: seconds held at the station.
-- cooldown: seconds before the same player can use this station type again.
G.GYM = {
	treadmill = { name = "러닝머신", action = "달리기", duration = 6, cooldown = 3, gains = { stamina = 1.2 }, pose = "run" },
	bike = { name = "실내 사이클", action = "페달 밟기", duration = 6, cooldown = 3, gains = { stamina = 1.0, strength = 0.2 }, pose = "sit" },
	bench = { name = "벤치프레스", action = "벤치프레스", duration = 5, cooldown = 4, gains = { strength = 1.2 }, pose = "lie" },
	squat = { name = "스쿼트 랙", action = "스쿼트", duration = 5, cooldown = 4, gains = { strength = 0.8, stamina = 0.4 }, pose = "squat" },
	dumbbell = { name = "덤벨", action = "덤벨 컬", duration = 4, cooldown = 3, gains = { strength = 0.8, appearance = 0.1 }, pose = "stand" },
	pullup = { name = "턱걸이", action = "턱걸이", duration = 4, cooldown = 4, gains = { strength = 1.0 }, pose = "hang" },
	inbody = { name = "인바디", action = "인바디 측정", duration = 3, cooldown = 5, gains = {}, pose = "stand", info = true },
}
G.GYM_ORDER = { "treadmill", "bike", "bench", "squat", "dumbbell", "pullup", "inbody" }
G.GYM_MOVING_PARTS = { "Bar", "Barbell", "Weight", "Weights", "WeightStack", "Plate", "Plates", "Handle", "Dumbbell" }
G.GYM_DAILY_FULL_SETS = 25 -- after this many sets in a (real) day, gains drop to 30 %
G.GYM_APPEARANCE_PER_SET = 0.3 -- "consistent training" bonus, first G.GYM_APPEARANCE_SETS sets a day
G.GYM_APPEARANCE_SETS = 12
G.GYM_HOLD_DURATION = 1 -- ProximityPrompt hold (seconds)

-- Stat gains for one set. stats = current stats; opts = { protein = bool, athleisure = bool,
-- setsToday = number }. Strength makes every set more effective (up to x1.5 at 100); gains shrink
-- as a stat approaches the cap.
function G.gymGain(stationType: string, stats: { [string]: number }, opts: { [string]: any }?): { [string]: number }
	local st = G.GYM[stationType]
	local out: { [string]: number } = {}
	if not st then
		return out
	end
	local o = opts or {}
	local strength = G.clampStat(stats.strength or 0)
	local mult = 1 + strength / 200
	if o.protein then
		mult *= 1.5
	end
	if o.athleisure then
		mult *= 1.1
	end
	local setsToday = if isFiniteNumber(o.setsToday) then o.setsToday else 0
	if setsToday >= G.GYM_DAILY_FULL_SETS then
		mult *= 0.3
	end
	for stat, base in st.gains do
		local cur = G.clampStat(stats[stat] or 0)
		local falloff = math.max(0.25, 1 - cur / 125)
		local g = base * mult * falloff
		out[stat] = math.floor(g * 10 + 0.5) / 10
	end
	if not st.info and setsToday < G.GYM_APPEARANCE_SETS then
		out.appearance = math.floor(((out.appearance or 0) + G.GYM_APPEARANCE_PER_SET) * 10 + 0.5) / 10
	end
	return out
end

-- Korean body-composition read-out for the InBody station.
function G.inbodyReport(stats: { [string]: number }): string
	local s = G.clampStat(stats.strength or 0)
	local st = G.clampStat(stats.stamina or 0)
	local muscle = 28 + s * 0.12
	local fat = math.max(9, 24 - st * 0.1 - s * 0.04)
	local grade = if s + st >= 140 then "A (운동 마니아)" elseif s + st >= 80 then "B (탄탄함)" elseif s + st >= 40 then "C (보통)" else "D (운동 시작!)"
	return string.format(
		"골격근량 %.1fkg · 체지방률 %.1f%%\n근력 %s · 체력 %s · 외모지수 %s · 인기도 %s\n등급 %s",
		muscle,
		fat,
		G.format.stat(s),
		G.format.stat(st),
		G.format.stat(stats.appearance or 0),
		G.format.stat(stats.popularity or 0),
		grade
	)
end

-------------------------------------------------------------------------------------------------
-- Salon (hair) and clothing (outfits). Colours are {r, g, b} (0-255). Hair shapes are ellipsoids
-- (SpecialMesh Sphere) or blocks in head units (1 = head height), offsets from the head centre
-- (+Y up, -Z = face direction).
-------------------------------------------------------------------------------------------------
type HairPiece = { shape: string, size: { number }, offset: { number }, tilt: number? }
local HAIR_SHAPES: { [string]: { HairPiece } } = {
	crop = {
		{ shape = "sphere", size = { 1.1, 0.62, 1.14 }, offset = { 0, 0.3, 0.05 } },
		{ shape = "block", size = { 0.92, 0.16, 0.22 }, offset = { 0, 0.36, -0.46 }, tilt = -15 },
	},
	twoblock = {
		{ shape = "sphere", size = { 1.04, 0.58, 1.1 }, offset = { 0, 0.38, 0.03 } },
		{ shape = "block", size = { 0.88, 0.2, 0.24 }, offset = { 0, 0.4, -0.46 }, tilt = -25 },
		{ shape = "sphere", size = { 1.07, 0.5, 1.08 }, offset = { 0, 0.16, 0.08 } },
	},
	regent = {
		{ shape = "sphere", size = { 1.08, 0.62, 1.14 }, offset = { 0, 0.36, 0.05 } },
		{ shape = "sphere", size = { 0.78, 0.5, 0.56 }, offset = { 0, 0.6, -0.34 }, tilt = 20 },
	},
	long = {
		{ shape = "sphere", size = { 1.12, 0.64, 1.16 }, offset = { 0, 0.32, 0.04 } },
		{ shape = "sphere", size = { 1.12, 1.15, 0.5 }, offset = { 0, -0.1, 0.36 } },
		{ shape = "block", size = { 0.94, 0.18, 0.22 }, offset = { 0, 0.34, -0.47 }, tilt = -10 },
	},
	bob = {
		{ shape = "sphere", size = { 1.16, 0.66, 1.18 }, offset = { 0, 0.3, 0.03 } },
		{ shape = "sphere", size = { 1.2, 0.72, 1.04 }, offset = { 0, -0.02, 0.12 } },
	},
}
G.HAIR_SHAPES = HAIR_SHAPES

-- gain = appearance points the first time a style is bought (a repeat visit only restyles).
G.SALON = {
	default = { name = "원래 헤어", price = 0, gain = 0, shape = nil, color = nil, hidden = true },
	dandy = { name = "댄디컷", price = 15000, gain = 3, shape = "crop", color = { 34, 26, 22 } },
	twoblock = { name = "투블럭", price = 18000, gain = 3, shape = "twoblock", color = { 24, 20, 18 } },
	regent = { name = "리젠트펌", price = 35000, gain = 5, shape = "regent", color = { 40, 30, 24 } },
	ash = { name = "애쉬브라운 염색", price = 45000, gain = 5, shape = "crop", color = { 118, 104, 92 } },
	wave = { name = "장발 웨이브펌", price = 40000, gain = 5, shape = "long", color = { 58, 40, 30 } },
	bob = { name = "단발 C컬펌", price = 38000, gain = 5, shape = "bob", color = { 70, 44, 30 } },
	pink = { name = "핑크 탈색", price = 60000, gain = 6, shape = "twoblock", color = { 236, 132, 170 } },
}
G.SALON_ORDER = { "dandy", "twoblock", "regent", "ash", "wave", "bob", "pink" }

-- sleeves: "long" colours the arms with the top, "short" keeps skin-coloured arms.
-- jacket: a welded jacket shell over the torso. gymBonus: gym gains x1.1 while worn.
G.CLOTHES = {
	default = { name = "원래 옷", price = 0, gain = 0, hidden = true },
	tee = { name = "화이트 티 & 청바지", price = 19000, gain = 2, top = { 238, 238, 234 }, bottom = { 52, 78, 124 }, sleeves = "short" },
	resort = { name = "광안리 리조트룩", price = 39000, gain = 3, top = { 34, 160, 170 }, bottom = { 226, 214, 186 }, sleeves = "short" },
	athleisure = { name = "애슬레저 운동복", price = 35000, gain = 3, top = { 30, 38, 64 }, bottom = { 20, 20, 24 }, sleeves = "short", gymBonus = true },
	street = { name = "스트릿 후드 & 조거", price = 45000, gain = 4, top = { 26, 26, 30 }, bottom = { 120, 122, 126 }, sleeves = "long" },
	dandy = { name = "댄디 셔츠 & 슬랙스", price = 69000, gain = 6, top = { 176, 204, 232 }, bottom = { 196, 176, 146 }, sleeves = "long" },
	clubblack = { name = "클럽 올블랙 셋업", price = 120000, gain = 8, top = { 22, 22, 24 }, bottom = { 16, 16, 18 }, sleeves = "long", jacket = { 12, 12, 14 } },
	suit = { name = "네이비 수트", price = 150000, gain = 9, top = { 236, 238, 240 }, bottom = { 28, 36, 64 }, sleeves = "long", jacket = { 28, 36, 64 } },
}
G.CLOTHES_ORDER = { "tee", "resort", "athleisure", "street", "dandy", "clubblack", "suit" }

-------------------------------------------------------------------------------------------------
-- Items. shop = ShopId (bought at a ShopCounter with that ShopId, or a SalonChair for "salon");
-- nearDest = Destination DisplayName (bought within G.NEAR_DEST_RADIUS studs of it; the server
-- puts a ProximityPrompt there); phone = true: can be bought anywhere through the phone.
-- kind: "consumable" (effect applies at once), "outfit" (owned + worn), "hair" (restyle).
-- effect: { stats = {stat = delta}, buff = id, buffSeconds = n, buffSets = n }
-- dailyStatLimit: stat effects apply at most this many times per real day (buying still works).
-------------------------------------------------------------------------------------------------
G.NEAR_DEST_RADIUS = 45
G.SHOP_REACH = 14 -- studs from a ShopCounter / SalonChair to buy there
G.SHOPS = {
	clothing = { name = "편집숍", title = "헤어살롱 & 편집숍 · 의류" },
	salon = { name = "헤어살롱", title = "헤어살롱 & 편집숍 · 헤어" },
	gym_store = { name = "휘트니스 매점", title = "광안 휘트니스 24 · 매점" },
}

G.BUFFS = {
	protein = { name = "프로틴 효과", desc = "다음 운동 3세트 효과 1.5배" },
	energy = { name = "에너지 부스트", desc = "달리기 속도 +3" },
	sup = { name = "SUP 보드 대여 중", desc = "광안리 SUP존에서 패들보드를 탈 수 있어요" },
}

G.ITEMS = {
	-- 광안 휘트니스 24 매점
	protein = { name = "프로틴 쉐이크", price = 4500, shop = "gym_store", kind = "consumable", desc = "다음 운동 3세트 효과 1.5배", effect = { buff = "protein", buffSets = 3 } },
	energy_drink = { name = "에너지 드링크", price = 2500, shop = "gym_store", kind = "consumable", desc = "3분 동안 달리기 속도 +3", effect = { buff = "energy", buffSeconds = 180 } },
	chicken_box = { name = "닭가슴살 도시락", price = 6500, shop = "gym_store", kind = "consumable", desc = "근력 +0.3 · 체력 +0.3 (하루 3번)", effect = { stats = { strength = 0.3, stamina = 0.3 } }, dailyStatLimit = 3 },
	water = { name = "생수", price = 1000, shop = "gym_store", kind = "consumable", desc = "운동 쿨타임 초기화", effect = { resetGymCooldown = true } },
	-- places around the beach (prompt at the Destination + phone within reach)
	millac_burger = { name = "밀락 수제버거 세트", price = 12000, nearDest = "밀락더마켓", kind = "consumable", desc = "체력 +0.5 · 인기도 +0.5 (먹방 인증)", effect = { stats = { stamina = 0.5, popularity = 0.5 } }, dailyStatLimit = 2 },
	sup_rental = { name = "SUP 패들보드 대여 (10분)", price = 20000, nearDest = "해양레포츠센터", kind = "consumable", desc = "광안리 SUP존에서 탈 수 있어요", effect = { buff = "sup", buffSeconds = 600 } },
	bread_set = { name = "빵천동 빵 세트", price = 9000, nearDest = "빵천동 빵집골목", kind = "consumable", desc = "인기도 +0.5 (빵지순례 인증)", effect = { stats = { popularity = 0.5 } }, dailyStatLimit = 2 },
	gs25_snack = { name = "삼각김밥 & 바나나우유", price = 2800, nearDest = "GS25 광안리점", kind = "consumable", desc = "체력 +0.2", effect = { stats = { stamina = 0.2 } }, dailyStatLimit = 3 },
	americano = { name = "아이스 아메리카노", price = 4500, nearDest = "스타벅스 광안리점", kind = "consumable", desc = "2분 동안 달리기 속도 +3", effect = { buff = "energy", buffSeconds = 120 } },
	hoe_platter = { name = "광어·우럭 모둠회", price = 30000, nearDest = "민락회타운", kind = "consumable", desc = "인기도 +1 (회타운 인증샷)", effect = { stats = { popularity = 1 } }, dailyStatLimit = 1 },
	-- phone delivery app (anywhere)
	delivery_chicken = { name = "배달 치킨 (광안리 치맥)", price = 21000, phone = true, kind = "consumable", desc = "체력 +0.4 · 인기도 +0.3", effect = { stats = { stamina = 0.4, popularity = 0.3 } }, dailyStatLimit = 1 },
}

-- Outfit / hair items are generated from CLOTHES / SALON: "outfit_<id>" and "hair_<id>".
for _, id in G.CLOTHES_ORDER do
	local c = G.CLOTHES[id]
	G.ITEMS["outfit_" .. id] = { name = c.name, price = c.price, shop = "clothing", kind = "outfit", ref = id, desc = string.format("외모지수 +%d (처음 살 때)", c.gain) }
end
for _, id in G.SALON_ORDER do
	local s = G.SALON[id]
	G.ITEMS["hair_" .. id] = { name = s.name, price = s.price, shop = "salon", kind = "hair", ref = id, desc = string.format("외모지수 +%d (처음 할 때)", s.gain) }
end

G.ITEM_ORDER = {
	"protein", "energy_drink", "chicken_box", "water",
	"millac_burger", "sup_rental", "bread_set", "gs25_snack", "americano", "hoe_platter", "delivery_chicken",
}
for _, id in G.CLOTHES_ORDER do
	table.insert(G.ITEM_ORDER, "outfit_" .. id)
end
for _, id in G.SALON_ORDER do
	table.insert(G.ITEM_ORDER, "hair_" .. id)
end

-- Items sold by a ShopId, in display order: { {id = itemId, item = def}, ... }
function G.shopItems(shopId: string): { { id: string, item: any } }
	local out = {}
	for _, id in G.ITEM_ORDER do
		local it = G.ITEMS[id]
		if it and it.shop == shopId then
			table.insert(out, { id = id, item = it })
		end
	end
	return out
end

-- Items sold at a Destination (nearDest), in display order.
function G.destItems(destName: string): { { id: string, item: any } }
	local out = {}
	for _, id in G.ITEM_ORDER do
		local it = G.ITEMS[id]
		if it and it.nearDest == destName then
			table.insert(out, { id = id, item = it })
		end
	end
	return out
end

function G.itemCategory(itemId: string): string?
	local it = G.ITEMS[itemId]
	if not it then
		return nil
	end
	return it.kind
end


-- Stats after applying `delta` (clamped). Returns the new table and the actually applied deltas.
function G.addStats(stats: { [string]: number }, delta: { [string]: number }?): ({ [string]: number }, { [string]: number })
	local out: { [string]: number } = {}
	local applied: { [string]: number } = {}
	for _, k in G.STAT_ORDER do
		out[k] = G.clampStat(stats[k] or G.STATS[k].start)
	end
	for k, d in delta or {} do
		if G.STATS[k] and isFiniteNumber(d) then
			local before = out[k]
			out[k] = G.clampStat(before + d)
			local diff = math.floor((out[k] - before) * 10 + 0.5) / 10
			if diff ~= 0 then
				applied[k] = diff
			end
		end
	end
	return out, applied
end

-- "외모지수 +3 · 인기도 +1"
function G.describeStats(delta: { [string]: number }?): string
	local parts = {}
	for _, k in G.STAT_ORDER do
		local d = delta and delta[k]
		if d and d ~= 0 then
			table.insert(parts, string.format("%s %s%s", G.STATS[k].name, if d > 0 then "+" else "", G.format.stat(math.abs(d)) :: string))
		end
	end
	return table.concat(parts, " · ")
end

function G.describeReward(reward: any): string
	if not reward then
		return ""
	end
	local parts = {}
	if reward.money and reward.money > 0 then
		table.insert(parts, G.format.won(reward.money))
	end
	local s = G.describeStats(reward.stats)
	if s ~= "" then
		table.insert(parts, s)
	end
	return table.concat(parts, " · ")
end

-- Real-day key (UTC) for daily limits.
function G.dayKey(unix: number): number
	return math.floor(unix / 86400)
end

-- Life-game tweaks to the shop items: food / cafe restore 체력 and 행복.
do
	local function addStat(id: string, stat: string, v: number)
		local it = G.ITEMS[id]
		if it then
			it.effect = it.effect or {}
			it.effect.stats = it.effect.stats or {}
			it.effect.stats[stat] = (it.effect.stats[stat] or 0) + v
		end
	end
	addStat("gs25_snack", "stamina", 8)
	addStat("americano", "happiness", 2)
	addStat("americano", "stamina", 5)
	addStat("millac_burger", "stamina", 15)
	addStat("millac_burger", "happiness", 4)
	addStat("hoe_platter", "happiness", 8)
	addStat("hoe_platter", "stamina", 15)
	addStat("bread_set", "happiness", 4)
	addStat("delivery_chicken", "stamina", 12)
	addStat("delivery_chicken", "happiness", 5)
	addStat("chicken_box", "stamina", 10)
	G.ITEMS.gs25_snack.desc = "체력 +8"
	G.ITEMS.americano.desc = "체력 +5 · 행복 +2 · 2분 달리기 속도 +3"
	G.ITEMS.millac_burger.desc = "체력 +15 · 행복 +4 · 인기도 +0.5"
	G.ITEMS.hoe_platter.desc = "체력 +15 · 행복 +8 · 인기도 +1"
	G.ITEMS.bread_set.desc = "행복 +4 · 인기도 +0.5"
	G.ITEMS.delivery_chicken.desc = "체력 +12 · 행복 +5 (어디서나 주문)"
	for _, id in { "gs25_snack", "americano", "millac_burger", "hoe_platter", "bread_set", "delivery_chicken", "chicken_box" } do
		local it = G.ITEMS[id]
		if it and it.dailyStatLimit then
			it.dailyStatLimit = math.max(it.dailyStatLimit, 4)
		end
	end
	G.ITEMS.cup_ramen = { name = "컵라면 & 김밥", price = 4500, phone = true, kind = "consumable", desc = "체력 +10 (편의점 배달)", effect = { stats = { stamina = 10 } }, dailyStatLimit = 6 }
	table.insert(G.ITEM_ORDER, "cup_ramen")
end

-------------------------------------------------------------------------------------------------
-- Time. The world clock runs 1 in-game hour per real minute (GwangalliConfig.DayLengthMinutes = 24).
-- Each player has their OWN day counter for rent (advanced while online and by sleeping), so the
-- global clock is never changed.
-------------------------------------------------------------------------------------------------
G.DAY_SECONDS = 1440 -- real seconds per in-game day
G.HOUR_SECONDS = 60
G.SLEEP_ADVANCE = 480 -- sleeping skips 8 in-game hours of the rent clock
G.SLEEP_COOLDOWN = 300
G.HAPPINESS_DECAY = 1 -- happiness lost per in-game 2 hours online
G.HAPPINESS_DECAY_EVERY = 120

-------------------------------------------------------------------------------------------------
-- Ledger. Every change of cash / bank goes through G.ledger (the server wraps it).
-------------------------------------------------------------------------------------------------
G.LEDGER_MAX = 50

-- Truncates to at most `maxBytes` bytes without cutting a UTF-8 (Korean) character in half.
function G.clipText(s: string, maxBytes: number): string
	if #s <= maxBytes then
		return s
	end
	local cut = maxBytes
	while cut > 0 do
		local b = string.byte(s, cut + 1)
		if not b or b < 0x80 or b >= 0xC0 then
			break
		end
		cut -= 1
	end
	return string.sub(s, 1, cut)
end

function G.round100(v: number): number
	return math.floor(v / 100 + 0.5) * 100
end

-- Applies `delta` to d[account] ("cash" | "bank") and records it. d = { cash, bank, transactions }.
-- Returns ok, reason ("insufficient" | "bad" | "full").
-- meta (optional, bank features): { kind, peer, peerId, memo, fee, ref, place } copied onto the entry
-- after G.ledgerMeta cleans it (see the "Bank" section at the end of this file).
function G.ledger(d: any, account: string, delta: any, label: string?, now: number?, meta: any?): (boolean, string?)
	if account ~= "cash" and account ~= "bank" then
		return false, "bad"
	end
	if not isFiniteNumber(delta) then
		return false, "bad"
	end
	local amount = if delta >= 0 then math.floor(delta) else -math.floor(-delta)
	if amount == 0 then
		return true, nil
	end
	local before = G.clampMoney(d[account])
	if before + amount < 0 then
		return false, "insufficient"
	end
	if meta ~= nil and before + amount > G.MAX_MONEY then
		return false, "full" -- bank paths never silently clamp (money would vanish)
	end
	d[account] = G.clampMoney(before + amount)
	d.transactions = d.transactions or {}
	local entry: { [string]: any } = {
		t = now or 0,
		amount = amount,
		label = G.clipText(label or (if amount > 0 then "입금" else "출금"), 120),
		balance = d[account],
		account = account,
	}
	if meta ~= nil and G.ledgerMeta then
		for k, v in G.ledgerMeta(meta) do
			entry[k] = v
		end
	end
	table.insert(d.transactions, entry)
	while #d.transactions > G.LEDGER_MAX do
		table.remove(d.transactions, 1)
	end
	return true, nil
end

function G.canAfford(d: any, amount: number): boolean
	return (d.cash or 0) >= amount or (d.bank or 0) >= amount
end

-- Pays `amount` from cash, or (when cash is short) by check card from the bank. Returns ok, account.
function G.spend(d: any, amount: any, label: string?, now: number?, prefer: string?): (boolean, string?)
	if not isFiniteNumber(amount) or amount < 0 then
		return false, nil
	end
	if amount == 0 then
		return true, "cash"
	end
	local first = if prefer == "bank" then "bank" else "cash"
	local second = if first == "bank" then "cash" else "bank"
	if (d[first] or 0) >= amount then
		G.ledger(d, first, -amount, label, now)
		return true, first
	end
	if (d[second] or 0) >= amount then
		G.ledger(d, second, -amount, (label or "결제") .. (if second == "bank" then " (체크카드)" else ""), now)
		return true, second
	end
	return false, nil
end

-- cash <-> bank. direction "deposit" (cash -> bank) | "withdraw". Returns ok, reason.
function G.transfer(d: any, direction: string, amount: any, now: number?): (boolean, string?)
	if not isFiniteNumber(amount) or amount <= 0 or amount % 1 ~= 0 then
		return false, "bad"
	end
	local from, to = "cash", "bank"
	if direction == "withdraw" then
		from, to = "bank", "cash"
	elseif direction ~= "deposit" then
		return false, "bad"
	end
	if (d[from] or 0) < amount then
		return false, "insufficient"
	end
	G.ledger(d, from, -amount, if direction == "deposit" then "입금 (현금 → 통장)" else "출금 (통장 → 현금)", now)
	G.ledger(d, to, amount, if direction == "deposit" then "현금 입금" else "ATM 출금", now)
	return true, nil
end

-------------------------------------------------------------------------------------------------
-- Jobs. Task kinds:
--   goto   { point? (work point id) | dest? (Destination) | pool? (random Destination from a list),
--            radius?, timeLimit? (seconds for the speed bonus) } -- completes when the player arrives
--   hold   { point, action, hold } -- a ProximityPrompt at the job's work point
--   choice { prompt, choices = {..}, answer } -- answered on the phone; wrong = no pay for that task
--   game   { game, point?, action?, hold?, timeLimit? } -- a mini-game round (GwangalliJobsShared /
--          JobGames); with `point` it opens when that anchor's prompt is held (docs/JOBS.md)
--   goto   { pickup = true } -- delivery pickup (dest set by the "order" round; bag prop attached)
--   deliver { radius } -- delivery drop-off: "배달 완료" prompt at the order's Destination
-- Work points are anchors created at runtime relative to the job's Destination part:
--   points[id] = { x, z } studs in the part's local frame (snapped to the floor).
-- A shift: "출근" (goto the job place) + `perShift` tasks drawn from `tasks` (or the fixed `cycle`
-- repeated), then a bonus. Pay per task = wage * G.TASK_HOURS; bonus = wage * G.SHIFT_BONUS_HOURS.
-------------------------------------------------------------------------------------------------
G.TASK_HOURS = 0.3
G.SHIFT_BONUS_HOURS = 1
G.TASK_XP = 10
G.SHIFT_XP = 20
G.TASK_MIN_SECONDS = 1.2 -- a task cannot be finished faster than this (anti-spam)
G.TASK_STAMINA = 2 -- 체력 per task
G.MIN_SHIFT_STAMINA = 10
G.CLOCK_IN_RADIUS = 45
G.WORK_POINT_RADIUS = 14
G.MAX_SHIFT_SECONDS = 900

G.DELIVERY_DESTS = {
	"삼익비치타운", "광안자이 (정문)", "켄트호텔 광안리", "호텔 아쿠아펠리스", "광안 휘트니스 24 (헬스장)",
	"KBS 부산방송총국", "광안지웰에스테이트", "테라스타오션", "광안 중앙병원", "호텔 센트럴베이",
}
G.TAXI_JOB_DESTS = {
	"지하철 광안역 3번 출구", "지하철 수영역 7번 출구", "지하철 남천역 3번 출구", "삼익비치타운",
	"켄트호텔 광안리", "민락회타운", "밀락더마켓", "광안 중앙병원", "빵천동 빵집골목",
}

-- Job ids other systems may use (docs/careers_contract.md GwJob values, the old rider job) -> G.JOBS id.
G.JOB_ALIASES = { convenience = "gs25", cafe = "starbucks", rider = "delivery_quick", delivery = "delivery_quick" }
function G.resolveJob(jobId: any): string?
	if type(jobId) ~= "string" then
		return nil
	end
	local id = G.JOB_ALIASES[jobId] or jobId
	if G.JOBS[id] and G.JOBS[id].alias then
		id = G.JOBS[id].alias
	end
	return if G.JOBS[id] then id else nil
end

-- The phone 알바 app lists these. 배달 has two entries (퀵 / 택배); the office's dispatch table switches.
G.JOB_ORDER = { "gs25", "starbucks", "delivery_quick", "delivery_parcel", "hoe", "lifeguard", "taxi_driver" }

-- Store / cafe world tasks: kind "game" with world = "customer" waits for an NPC customer at the
-- counter (GwangalliGameplay/JobWorld spawns them), world = "restock" / "expiry" / "cup" rounds are
-- played on the shelves / showcase / machine (GwangalliJobs/World.luau). `pick` = one of several.
-- Work points: build-time anchors (tag GwJobStation, attrs Job + Station) win over the offsets.
local CVS_SALE = { kind = "game", game = "sale", point = "counter", world = "customer", prompt = "카운터 손님 계산하기", action = "계산하기", hold = 0.25, timeLimit = 30 }
local CAFE_DRINK = { kind = "game", game = "drink", point = "bar", world = "customer", prompt = "주문 음료 만들기", action = "음료 만들기", hold = 0.3, timeLimit = 22 }

G.JOBS = {
	gs25 = {
		title = "편의점 알바",
		place = "GS25 광안리점",
		career = "convenience", -- GwJob (docs/careers_contract.md)
		icon = "🏪",
		npc = "gs25_owner",
		contact = "boss",
		desc = "카운터에서 손님 계산, 창고 박스 진열, 쇼케이스 유통기한 체크. 사장님이 카운터에서 기다려요!",
		levels = {
			{ title = "알바생", wage = 10320, xp = 0 },
			{ title = "매니저", wage = 13000, xp = 120 },
			{ title = "점장", wage = 17000, xp = 360 },
		},
		-- work points (offsets from the Destination at the door: +x = along the facade, -z = deeper
		-- into the shop); the store build places exact GwJobStation anchors for the same ids
		points = { counter = { -3, -24.4 }, backroom = { 10, -69 }, chiller = { -0.4, -42 } },
		cycle = {
			CVS_SALE,
			{ kind = "game", game = "shelf", point = "backroom", world = "restock", prompt = "창고 박스 들고 빈 진열칸 채우기", action = "박스 들기", hold = 0.6, timeLimit = 60 },
			CVS_SALE,
			{ kind = "game", game = "expiry", point = "chiller", world = "expiry", prompt = "쇼케이스 유통기한 체크하기", action = "유통기한 체크", hold = 0.4, timeLimit = 20 },
			{ pick = {
				{ kind = "game", game = "parcel", point = "counter", world = "customer", customer = "parcel", prompt = "손님 택배 접수하기", action = "택배 접수", hold = 0.25, timeLimit = 20 },
				{ kind = "game", game = "ask", point = "counter", world = "customer", customer = "ask", prompt = "카운터 손님 응대하기", action = "응대하기", hold = 0.25, timeLimit = 15,
					question = "손님: \"담배 한 갑 주세요.\" 어려 보이는데… 어떻게 할까요?", choices = { "신분증을 확인한다", "그냥 판다", "모른 척한다" }, answer = 1 },
				{ kind = "game", game = "ask", point = "counter", world = "customer", customer = "ask", prompt = "카운터 손님 응대하기", action = "응대하기", hold = 0.25, timeLimit = 15,
					question = "손님: \"2+1 우유 3개요!\" 몇 개 값을 받을까요?", choices = { "2개", "1개", "3개" }, answer = 1 },
				{ kind = "game", game = "ask", point = "counter", world = "customer", customer = "ask", prompt = "카운터 손님 응대하기", action = "응대하기", hold = 0.25, timeLimit = 15,
					question = "손님: \"종량제 봉투 20L 하나요.\" 얼마일까요?", choices = { "490원", "무료", "5,000원" }, answer = 1 },
			} },
			CVS_SALE,
		},
		cycles = 1,
	},
	starbucks = {
		title = "카페 바리스타",
		place = "스타벅스 광안리점",
		career = "cafe",
		icon = "☕",
		npc = "starbucks_mgr",
		contact = "cafe",
		desc = "카운터에서 주문 받고 에스프레소 머신에서 음료 만들기, 라떼 아트 보너스. 바다 뷰 카페에서 일해요.",
		levels = {
			{ title = "바리스타", wage = 10320, xp = 0 },
			{ title = "슈퍼바이저", wage = 14000, xp = 150 },
			{ title = "점장", wage = 18500, xp = 420 },
		},
		points = { pos = { -5, -5 }, bar = { 5, -6 }, table = { 0, -9 } },
		cycle = {
			CAFE_DRINK,
			CAFE_DRINK,
			{ kind = "game", game = "latte", point = "bar", world = "cup", prompt = "라떼 아트 올리기", action = "라떼 아트", hold = 0.3, timeLimit = 9 },
			{ pick = {
				{ kind = "hold", point = "table", prompt = "테라스 테이블 정리하기", action = "정리하기", hold = 1.5 },
				{ kind = "game", game = "ask", point = "pos", world = "customer", customer = "ask", prompt = "카운터 손님 응대하기", action = "응대하기", hold = 0.25, timeLimit = 15,
					question = "손님: \"시원하고 상큼한 거요, 커피는 빼고요.\"", choices = { "복숭아 아이스티", "에스프레소", "카푸치노" }, answer = 1 },
				{ kind = "game", game = "ask", point = "pos", world = "customer", customer = "ask", prompt = "카운터 손님 응대하기", action = "응대하기", hold = 0.25, timeLimit = 15,
					question = "손님: \"따뜻한 라떼 톨 사이즈요.\" 무엇을 만들까요?", choices = { "카페 라떼 (HOT)", "아이스 아메리카노", "밀크티" }, answer = 1 },
			} },
			CAFE_DRINK,
			CAFE_DRINK,
		},
		cycles = 1,
	},
	-- 광안 딜리버리 (build/venues/delivery.luau): 퀵 = pick the parcel from the office shelf, walk it to
	-- a downtown building and hand it to the NPC waiting at the entrance; 택배 = load the 탑차 at the
	-- dock, drive into the ring in front of each building (red lights cost money), bring the truck back.
	-- Drop pay comes from GwangalliJobsShared.DELIVERY_MODES (distance + tip), x wage / Lv.1 wage.
	delivery_quick = {
		title = "퀵 배달",
		place = "광안 딜리버리",
		career = "delivery_quick",
		mode = "quick",
		icon = "🛵",
		npc = "rider_mgr",
		contact = "rider",
		desc = "사무실 선반에서 물건을 챙겨 번화가 건물 앞에서 기다리는 손님에게 직접 전달! 운전 적음, 택배보다 조금 덜 벌어요.",
		levels = {
			{ title = "신입 퀵 기사", wage = 11000, xp = 0 },
			{ title = "베테랑 퀵 기사", wage = 15000, xp = 150 },
			{ title = "전설의 라이더", wage = 20000, xp = 450 },
		},
		points = { dispatch = { 1.5, -7.9 }, shelf = { -18.6, -21 }, dock = { -2, -78.5 } },
		cycle = {
			{ kind = "pickup", point = "shelf", mode = "quick", prompt = "선반에서 퀵 물건 챙기기", action = "물건 챙기기", hold = 0.6 },
			{ kind = "handover", mode = "quick", prompt = "배달지로 이동하기", radius = 9 },
		},
		cycles = 4,
	},
	delivery_parcel = {
		title = "택배 배달",
		place = "광안 딜리버리",
		career = "delivery_parcel",
		mode = "parcel",
		icon = "🚚",
		npc = "rider_mgr",
		contact = "rider",
		desc = "차고의 탑차에 상차하고 맵 전체를 돌며 건물 앞 원 안에 차를 대면 자동 배달! 신호 위반은 배달비에서 차감. 퀵보다 조금 더 벌어요.",
		levels = {
			{ title = "택배 기사", wage = 12000, xp = 0 },
			{ title = "베테랑 택배 기사", wage = 16000, xp = 150 },
			{ title = "물류 팀장", wage = 21000, xp = 450 },
		},
		points = { dispatch = { 1.5, -7.9 }, shelf = { -18.6, -21 }, dock = { -2, -78.5 }, pad = { -2, -99 } },
		cycle = {
			{ kind = "load", point = "dock", mode = "parcel", prompt = "상차하고 탑차 받기", action = "상차하기", hold = 1.0 },
			{ kind = "ring", mode = "parcel", prompt = "배달지 원 안으로 탑차 대기", radius = 13 },
			{ kind = "ring", mode = "parcel", prompt = "배달지 원 안으로 탑차 대기", radius = 13 },
			{ kind = "ring", mode = "parcel", prompt = "배달지 원 안으로 탑차 대기", radius = 13 },
			{ kind = "ring", mode = "parcel", prompt = "배달지 원 안으로 탑차 대기", radius = 13 },
			{ kind = "goto", point = "pad", mode = "parcel", returnTruck = true, prompt = "사무실 차고에 탑차 반납하기", radius = 26 },
		},
		cycles = 1,
	},
	hoe = {
		title = "횟집 서빙",
		place = "민락회타운",
		icon = "🐟",
		npc = "hoe_boss",
		contact = "hoe",
		desc = "주문 받기, 서빙, 정리. 광안대교 야경 보며 일하는 활기찬 횟집!",
		levels = {
			{ title = "서버", wage = 10320, xp = 0 },
			{ title = "실장", wage = 14500, xp = 150 },
			{ title = "매니저", wage = 18000, xp = 420 },
		},
		perShift = 5,
		points = { order = { -6, -5 }, serve = { 6, -5 }, clean = { 0, -9 } },
		tasks = {
			{ kind = "hold", point = "order", prompt = "손님 테이블 주문 받기", action = "주문 받기", hold = 1.2 },
			{ kind = "hold", point = "serve", prompt = "모둠회 서빙하기", action = "서빙하기", hold = 1.6 },
			{ kind = "hold", point = "clean", prompt = "테이블 정리하기", action = "정리하기", hold = 1.5 },
			{ kind = "choice", prompt = "손님: \"회에는 뭐가 제일 잘 어울려요?\"", choices = { "초장이랑 쌈채소", "케첩", "딸기잼" }, answer = 1 },
			{ kind = "choice", prompt = "손님: \"매운탕 추가요!\" 어디에 전달할까요?", choices = { "주방", "카운터 금고", "주차장" }, answer = 1 },
		},
	},
	lifeguard = {
		title = "해수욕장 안전요원",
		place = "광안리해수욕장 (중앙)",
		icon = "🛟",
		npc = "lifeguard_chief",
		contact = "lifeguard",
		desc = "망루와 해변 순찰, 위험한 수영객 구조. 체력이 중요해요!",
		levels = {
			{ title = "안전요원", wage = 11500, xp = 0 },
			{ title = "수상구조 팀장", wage = 16000, xp = 200 },
		},
		perShift = 5,
		points = { west = { -30, 0 }, east = { 30, 0 }, tower = { 0, -6 }, rescue = { 12, 10 } },
		tasks = {
			{ kind = "goto", point = "west", prompt = "서쪽 해변 순찰 지점 확인하기", radius = 14 },
			{ kind = "goto", point = "east", prompt = "동쪽 해변 순찰 지점 확인하기", radius = 14 },
			{ kind = "hold", point = "tower", prompt = "망루에서 바다 살피기", action = "관찰하기", hold = 2 },
			{ kind = "hold", point = "rescue", prompt = "허우적대는 수영객 구조하기!", action = "구조하기", hold = 2.5 },
			{ kind = "choice", prompt = "이안류(역파도)에 휩쓸렸을 때 올바른 행동은?", choices = { "해안과 평행하게 헤엄친다", "해안 쪽으로 전력으로 헤엄친다", "잠수한다" }, answer = 1 },
		},
	},
	taxi_driver = {
		title = "택시 기사",
		place = "광안리 만남의 광장",
		icon = "🚖",
		npc = "taxi_dispatcher",
		contact = "taxico",
		desc = "만남의 광장 택시승강장에서 손님을 태우고 목적지까지 모셔다 드려요.",
		levels = {
			{ title = "택시 기사", wage = 12000, xp = 0 },
			{ title = "모범택시 기사", wage = 17000, xp = 200 },
		},
		points = { stand = { 6, -4 } },
		cycle = {
			{ kind = "hold", point = "stand", prompt = "택시승강장에서 손님 태우기", action = "손님 태우기", hold = 1.2 },
			{ kind = "goto", pool = "TAXI_JOB_DESTS", prompt = "손님을 %s까지 모셔다 드리기", radius = 30, timeLimit = 150 },
			{ kind = "goto", point = "stand", prompt = "택시승강장으로 돌아가기", radius = 20 },
		},
		cycles = 2,
	},
}
-- the old 배달 라이더 job id: same data as 퀵 배달 (saved jobs / offers / the 밀락 manager's dialog
-- keep working; Jobs.luau resolves the alias on apply and when a profile loads)
G.JOBS.rider = table.clone(G.JOBS.delivery_quick)
G.JOBS.rider.alias = "delivery_quick"

-- GwJob / GwJobBase values (docs/careers_contract.md)
function G.jobCareer(jobId: string): string
	local job = G.JOBS[jobId]
	return (job and job.career) or jobId
end
function G.jobBase(jobId: string): string?
	local job = G.JOBS[jobId]
	return job and (job.base or job.place) or nil
end

-- every task table a job can produce (validation / work point prompts)
function G.jobTaskList(jobId: string): { any }
	local job = G.JOBS[jobId]
	local out = {}
	if not job then
		return out
	end
	for _, t in (job.tasks or job.cycle or {}) do
		if t.pick then
			for _, p in t.pick do
				table.insert(out, p)
			end
		else
			table.insert(out, t)
		end
	end
	return out
end

function G.jobLevel(jobId: string, xp: any): number
	local job = G.JOBS[jobId]
	if not job then
		return 1
	end
	local x = if isFiniteNumber(xp) then xp else 0
	local lv = 1
	for i, l in job.levels do
		if x >= l.xp then
			lv = i
		end
	end
	return lv
end

function G.jobWage(jobId: string, level: number): number
	local job = G.JOBS[jobId]
	if not job then
		return 0
	end
	local l = job.levels[math.clamp(level, 1, #job.levels)]
	return l.wage
end

function G.taskPay(jobId: string, level: number): number
	return G.round100(G.jobWage(jobId, level) * G.TASK_HOURS)
end

function G.shiftBonus(jobId: string, level: number): number
	return G.round100(G.jobWage(jobId, level) * G.SHIFT_BONUS_HOURS)
end

-- Adds xp; returns newXp, newLevel, promoted (bool).
function G.addJobXp(jobId: string, xp: any, gained: number): (number, number, boolean)
	local before = if isFiniteNumber(xp) then xp else 0
	local lv0 = G.jobLevel(jobId, before)
	local after = math.max(0, before + gained)
	local lv1 = G.jobLevel(jobId, after)
	return after, lv1, lv1 > lv0
end

function G.nextLevelXp(jobId: string, level: number): number?
	local job = G.JOBS[jobId]
	local nxt = job and job.levels[level + 1]
	return nxt and nxt.xp or nil
end

-- The task list for one shift (without the clock-in). `rand(n)` returns 1..n.
function G.buildShift(jobId: string, rand: (number) -> number): { any }
	local job = G.JOBS[jobId]
	local out = {}
	if not job then
		return out
	end
	local function resolve(t: any): any
		if t.pick then
			t = t.pick[rand(#t.pick)]
		end
		local c = table.clone(t)
		if c.pool then
			local list = if type(c.pool) == "string" then G[c.pool] else c.pool
			c.dest = list[rand(#list)]
			c.pool = nil
			c.prompt = string.format(c.prompt, c.dest)
		end
		return c
	end
	if job.cycle then
		for _ = 1, job.cycles or 1 do
			for _, t in job.cycle do
				table.insert(out, resolve(t))
			end
		end
	else
		local last = 0
		for _ = 1, job.perShift or 5 do
			local i = rand(#job.tasks)
			if i == last and #job.tasks > 1 then
				i = i % #job.tasks + 1
			end
			last = i
			table.insert(out, resolve(job.tasks[i]))
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Housing. kind "rent": deposit (refunded when you move to another home, lost on eviction) +
-- rentPerDay (auto-debit each of the player's in-game days: bank first, then cash). kind "buy":
-- price once (or 주택담보대출: G.MORTGAGE) + upkeepPerDay (관리비; unpaid upkeep only warns).
-- tier = 1..5 (player attribute HomeTier), tierKey = interior template "HomeUnit_<tierKey>".
-- comfort: extra 행복 when sleeping there (+ upgrades + furniture decor: G.homeComfort).
-------------------------------------------------------------------------------------------------
G.EVICT_AFTER = 3 -- missed daily payments before eviction
G.RENT_WARN_SECONDS = 120 -- warn this long before a charge the player cannot afford

G.LISTING_ORDER = { "goshiwon", "oneroom", "officetel", "xi_apt", "aqua_ph" }
G.LISTINGS = {
	goshiwon = { name = "광안 고시원 1인실", kind = "rent", tier = 1, tierKey = "goshiwon", place = "지하철 광안역 6번 출구", deposit = 0, rentPerDay = 6000, comfort = 0, icon = "🛏️", desc = "침대 하나, 책상 하나. 보증금 없이 바로 입주!" },
	oneroom = { name = "광안동 풀옵션 원룸", kind = "rent", tier = 2, tierKey = "oneroom", place = "광안동우체국", deposit = 300000, rentPerDay = 14000, comfort = 3, icon = "🏠", desc = "세탁기·에어컨 풀옵션, 광안역 도보 5분." },
	officetel = { name = "테라스타오션 오피스텔", kind = "rent", tier = 3, tierKey = "officetel", place = "테라스타오션", deposit = 1000000, rentPerDay = 30000, comfort = 6, icon = "🏢", desc = "복층 구조, 창밖으로 광안대교가 살짝 보여요." },
	xi_apt = { name = "광안자이 아파트 84㎡", kind = "buy", tier = 4, tierKey = "apartment", place = "광안자이 (정문)", price = 12000000, upkeepPerDay = 15000, comfort = 10, icon = "🏙️", desc = "광안동 대단지 신축 아파트. 내 집 마련의 꿈!" },
	aqua_ph = { name = "아쿠아펠리스 오션뷰 펜트하우스", kind = "buy", tier = 5, tierKey = "penthouse", place = "호텔 아쿠아펠리스", price = 48000000, upkeepPerDay = 40000, comfort = 15, icon = "🌊", desc = "광안리 해변 정면, 통창 가득 광안대교 야경." },
}

-- Daily charge of a listing: rent (scaled by the unit's floor price multiplier when the home record
-- `home` is given: 층·호수마다 시세가 달라요) or the 관리비 (per listing).
function G.homeDaily(listingId: string, home: any?): number
	local l = G.LISTINGS[listingId]
	if not l then
		return 0
	end
	if l.kind == "rent" then
		local m = if type(home) == "table" and isFiniteNumber(home.priceMult) then math.clamp(home.priceMult, 0.5, 3) else 1
		return if m == 1 then l.rentPerDay else G.round100(l.rentPerDay * m)
	end
	return l.upkeepPerDay or 0
end

-- Prices of a listing for a unit choice ({floor, unit, layoutId, priceMult, view} from
-- GwangalliHomesShared.choiceFor; nil = the listing's base prices): { deposit, rentPerDay, price,
-- upkeep, mult }. Rounded to 100원. Server and client use the same function.
function G.homePrices(listingId: string, choice: any?): any
	local l = G.LISTINGS[listingId]
	if not l then
		return { deposit = 0, rentPerDay = 0, price = 0, upkeep = 0, mult = 1 }
	end
	local m = if type(choice) == "table" and isFiniteNumber(choice.priceMult) then math.clamp(choice.priceMult, 0.5, 3) else 1
	local function sc(v: number?): number
		local b = v or 0
		return if m == 1 then b else G.round100(b * m)
	end
	return { deposit = sc(l.deposit), rentPerDay = if l.kind == "rent" then sc(l.rentPerDay) else 0, price = sc(l.price), upkeep = l.upkeepPerDay or 0, mult = m }
end

-- Market value of an owned home (price + remodelling value when the profile `d` is given).
function G.homeValue(home: any, d: any?): number
	if not home or not home.owned then
		return 0
	end
	local l = G.LISTINGS[home.listingId]
	if not l then
		return 0
	end
	local v = G.homePrices(home.listingId, home).price
	if d then
		v += G.upgradesValue(d, home.listingId)
	end
	return v
end

-- 총자산: cash + bank + home value (with upgrades) + rent deposit + furniture (resale) - mortgage left.
function G.netWorth(d: any): number
	local v = (d.cash or 0) + (d.bank or 0) + G.homeValue(d.home, d)
	if d.home and not d.home.owned then
		v += d.home.deposit or 0
	end
	v += G.furnitureValue(d)
	local loan = type(d.housing) == "table" and d.housing.loan or nil
	if type(loan) == "table" and isFiniteNumber(loan.remaining) then
		v -= loan.remaining
	end
	return v
end

-- choice = the unit ({floor, unit, layoutId, priceMult, view}; nil = the listing's default unit via
-- GwangalliHomesShared). The address is mirrored into d.housing.address by G.setHomeAddress (the
-- profile sanitiser keeps only the classic home fields; G.reconcileHousing re-attaches it on load).
local function resolveChoice(id: string, choice: any?): any?
	if type(choice) == "table" then
		return choice
	end
	local HSm = G.HOMES
	if HSm and type(HSm.defaultChoice) == "function" then
		local ok, c = pcall(HSm.defaultChoice, id)
		if ok and type(c) == "table" then
			return c
		end
	end
	return nil
end

local function newHome(id: string, l: any, choice: any?): any
	local c = resolveChoice(id, choice)
	local prices = G.homePrices(id, c)
	local h: any = { listingId = id, tier = l.tier, owned = l.kind == "buy", dueIn = G.DAY_SECONDS, missed = 0, arrears = 0, deposit = if l.kind == "rent" then prices.deposit else 0 }
	if c then
		h.floor, h.unit, h.layoutId, h.priceMult, h.view = c.floor, c.unit, c.layoutId, prices.mult, c.view
	end
	return h
end

-- Mirrors the unit fields of d.home into d.housing.address (persisted by G.sanitizeHousing).
function G.setHomeAddress(d: any)
	local h = d.home
	if type(d.housing) ~= "table" then
		d.housing = G.defaultHousing()
	end
	if not h then
		d.housing.address = nil
		return
	end
	d.housing.address = { listingId = h.listingId, floor = h.floor, unit = h.unit, layoutId = h.layoutId, priceMult = h.priceMult, view = h.view }
end

-- Clears what belongs to the home being left: placed furniture goes to storage (짐은 챙겨요),
-- remodelling of a sold home is sold with it, a mortgage is settled by the caller.
local function leaveListing(d: any, listingId: string?)
	if not listingId or type(d.housing) ~= "table" then
		return
	end
	G.moveOutFurniture(d, listingId)
	d.housing.upgrades[listingId] = nil
end

-- Moving out of the current home: refunds a rent deposit (not when evicted). Records into d.
local function moveOut(d: any, now: number?)
	local h = d.home
	if h and not h.owned and (h.deposit or 0) > 0 then
		G.ledger(d, "bank", h.deposit, "보증금 반환", now)
	end
	leaveListing(d, h and h.listingId)
	d.home = nil
end

-- Signs a rent contract: pays the deposit + the first day's rent (bank first, then cash).
-- Returns ok, reason ("unknown" | "notRent" | "same" | "owned" | "insufficient").
function G.rentHome(d: any, listingId: string, now: number?, choice: any?): (boolean, string?)
	local l = G.LISTINGS[listingId]
	if not l then
		return false, "unknown"
	end
	if l.kind ~= "rent" then
		return false, "notRent"
	end
	if d.home and d.home.listingId == listingId then
		return false, "same"
	end
	if d.home and d.home.owned then
		return false, "owned"
	end
	local refund = if d.home and not d.home.owned then (d.home.deposit or 0) else 0
	local c = resolveChoice(listingId, choice)
	local prices = G.homePrices(listingId, c)
	local cost = prices.deposit + prices.rentPerDay
	if (d.bank or 0) + refund < cost and (d.cash or 0) < cost then
		return false, "insufficient"
	end
	moveOut(d, now)
	if (d.bank or 0) >= cost then
		G.ledger(d, "bank", -cost, l.name .. " 계약 (보증금+첫날 월세)", now)
	else
		G.ledger(d, "cash", -cost, l.name .. " 계약 (보증금+첫날 월세)", now)
	end
	d.home = newHome(listingId, l, c)
	G.setHomeAddress(d)
	return true, nil
end

-- What selling the current home brings (90 % of value incl. upgrades, minus a mortgage left) or
-- the rent deposit coming back.
local function currentCredit(d: any): number
	if not d.home then
		return 0
	end
	if d.home.owned then
		local loan = type(d.housing) == "table" and d.housing.loan or nil
		local left = if type(loan) == "table" then (loan.remaining or 0) else 0
		return math.floor(G.homeValue(d.home, d) * 0.9) - left
	end
	return d.home.deposit or 0
end

local function sellCurrent(d: any, now: number?)
	local old = G.LISTINGS[d.home.listingId]
	local gross = math.floor(G.homeValue(d.home, d) * 0.9)
	G.ledger(d, "bank", gross, (old and old.name or "집") .. " 매도", now)
	local loan = type(d.housing) == "table" and d.housing.loan or nil
	if type(loan) == "table" and (loan.remaining or 0) > 0 then
		local pay = math.min(loan.remaining, d.bank or 0)
		G.ledger(d, "bank", -pay, "주택담보대출 상환 (매도)", now)
		d.housing.loan = nil
	elseif type(d.housing) == "table" then
		d.housing.loan = nil
	end
	leaveListing(d, d.home.listingId)
	d.home = nil
end

-- Buys a listing (bank first, then cash; a previous owned home is sold back at 90 %).
function G.buyHome(d: any, listingId: string, now: number?, choice: any?): (boolean, string?)
	local l = G.LISTINGS[listingId]
	if not l then
		return false, "unknown"
	end
	if l.kind ~= "buy" then
		return false, "notBuy"
	end
	if d.home and d.home.listingId == listingId then
		return false, "same"
	end
	local c = resolveChoice(listingId, choice)
	local price = G.homePrices(listingId, c).price
	local credit = currentCredit(d)
	if (d.bank or 0) + credit < price and (d.cash or 0) < price then
		return false, "insufficient"
	end
	if d.home and d.home.owned then
		sellCurrent(d, now)
	else
		moveOut(d, now)
	end
	if (d.bank or 0) >= price then
		G.ledger(d, "bank", -price, l.name .. " 매매", now)
	else
		G.ledger(d, "cash", -price, l.name .. " 매매", now)
	end
	d.home = newHome(listingId, l, c)
	G.setHomeAddress(d)
	return true, nil
end

-- Advances the home clock by `elapsed` seconds. Returns events:
--   { kind = "charged", amount, account, loan? } | { kind = "missed", amount, missed }
--   | { kind = "evicted" } | { kind = "warn", amount, seconds } | { kind = "loanPaid" }
--   | { kind = "foreclosed", refund }
-- `warned` (bool) suppresses repeated warnings within one day; returned second value = new warned.
function G.homeTick(d: any, elapsed: number, now: number?, warned: boolean?): ({ any }, boolean)
	local events = {}
	local h = d.home
	if not h or not isFiniteNumber(elapsed) or elapsed <= 0 then
		return events, warned == true
	end
	local l = G.LISTINGS[h.listingId]
	if not l then
		d.home = nil
		return events, false
	end
	local w = warned == true
	h.dueIn = (if isFiniteNumber(h.dueIn) then h.dueIn else G.DAY_SECONDS) - elapsed
	local guard = 0
	while h.dueIn <= 0 and guard < 10 do
		guard += 1
		h.dueIn += G.DAY_SECONDS
		w = false
		local loan = G.activeLoan(d)
		local loanDaily = if loan then math.min(loan.daily, loan.remaining) else 0
		local daily = G.homeDaily(h.listingId, h)
		local due = daily + loanDaily + (h.arrears or 0)
		local label = if l.kind == "rent" then l.name .. " 월세 자동이체" elseif loanDaily > 0 then l.name .. " 관리비 + 대출 상환" else l.name .. " 관리비"
		local ok, account = false, nil
		if due <= 0 then
			ok = true
		elseif (d.bank or 0) >= due then
			ok, account = G.ledger(d, "bank", -due, label, now), "bank"
		elseif (d.cash or 0) >= due then
			ok, account = G.ledger(d, "cash", -due, label, now), "cash"
		end
		if ok then
			local paidLoan = if loan then math.min(loan.remaining, loanDaily + (loan.arrears or 0)) else 0
			h.arrears = 0
			h.missed = 0
			table.insert(events, { kind = "charged", amount = due, account = account, loan = if loan then paidLoan else nil })
			if loan then
				loan.remaining = math.max(0, loan.remaining - paidLoan)
				loan.arrears = 0
				loan.missed = 0
				if loan.remaining <= 0 then
					d.housing.loan = nil
					table.insert(events, { kind = "loanPaid" })
				end
			end
		else
			h.missed = (h.missed or 0) + 1
			h.arrears = due
			if l.kind == "rent" and h.missed >= G.EVICT_AFTER then
				leaveListing(d, h.listingId)
				d.home = nil -- deposit is kept by the landlord
				table.insert(events, { kind = "evicted", amount = due })
				return events, false
			end
			if loan then
				loan.missed = (loan.missed or 0) + 1
				loan.arrears = math.min((loan.arrears or 0) + loanDaily, loan.remaining)
				if loan.missed >= G.MORTGAGE.forecloseAfter then
					-- 경매: the bank sells the home, the player gets what is left after the loan
					local refund = math.max(0, math.floor(G.homeValue(h, d) * G.MORTGAGE.auctionRate) - loan.remaining)
					if refund > 0 then
						G.ledger(d, "bank", refund, l.name .. " 경매 정산금", now)
					end
					d.housing.loan = nil
					leaveListing(d, h.listingId)
					d.home = nil
					table.insert(events, { kind = "foreclosed", amount = due, refund = refund })
					return events, false
				end
			end
			if l.kind ~= "rent" then
				-- owners never lose the home for upkeep; unpaid upkeep just accumulates up to 3 days
				-- (a mortgage accumulates until foreclosure)
				local capDays = if loan then G.MORTGAGE.forecloseAfter else G.EVICT_AFTER
				h.arrears = math.min(due, (daily + loanDaily) * capDays)
			end
			table.insert(events, { kind = "missed", amount = due, missed = h.missed, loan = loan ~= nil })
		end
	end
	if d.home and not w and h.dueIn <= G.RENT_WARN_SECONDS then
		local loan = G.activeLoan(d)
		local due = G.homeDaily(h.listingId, h) + (if loan then math.min(loan.daily, loan.remaining) else 0) + (h.arrears or 0)
		if due > 0 and (d.bank or 0) < due and (d.cash or 0) < due then
			w = true
			table.insert(events, { kind = "warn", amount = due, seconds = h.dueIn })
		end
	end
	return events, w
end

-- Pays arrears now (from the rent reminder message). Returns ok, amount.
function G.payArrears(d: any, now: number?): (boolean, number)
	local h = d.home
	if not h or (h.arrears or 0) <= 0 then
		return false, 0
	end
	local amt = h.arrears
	local l = G.LISTINGS[h.listingId]
	local ok = G.spend(d, amt, (l and l.name or "집") .. " 연체금 납부", now, "bank")
	if ok then
		h.arrears = 0
		h.missed = 0
		local loan = G.activeLoan(d)
		if loan then
			loan.remaining = math.max(0, loan.remaining - (loan.arrears or 0))
			loan.arrears = 0
			loan.missed = 0
			if loan.remaining <= 0 then
				d.housing.loan = nil
			end
		end
		return true, amt
	end
	return false, amt
end

-------------------------------------------------------------------------------------------------
-- 자기집 마련 (home ownership): per-player interior instances, home interactions, furniture and
-- decoration, remodelling, 주택담보대출, bills, visiting / 집들이. Server:
-- ServerScriptService.GwangalliGameplay.Housing; in-home HUD: StarterPlayerScripts.GwangalliHome.
--
-- TEMPLATES: ServerStorage.GwangalliHomes has Models "HomeUnit_<tierKey>" (G.HOME_TIER_ORDER), each:
--   PrimaryPart "UnitRoot" (floor centre), part "Spawn" (the player appears here, facing its
--   LookVector), part "ExitDoor" (inside door), parts tagged "HomeInteract" (attribute Kind = one of
--   G.HOME_KIND_ORDER), parts tagged "FurnitureSlot" (attributes SlotId (unique per unit), Category
--   (G.FURNITURE_CATEGORY_ORDER); Size = the furniture envelope W x H x D, the part's bottom face
--   is the floor, the front faces its LookVector, i.e. -Z; the slot's default furniture Model is a
--   child), and a window-view backdrop. A HomeInteract part inside a slot's default furniture keeps
--   working when the furniture is swapped (the server leaves an invisible proxy in its place).
-- MAP: parts tagged "HomeEntrance" (attribute Tier = tierKey, optional DisplayName = building name)
--   at each building; missing ones fall back to the listing's Destination (G.LISTINGS[id].place).
-- INSTANCES: the server clones the owner's template into Workspace.GwangalliHomeInstances at
--   G.homeSlotPosition(i) (high above the map: FallenPartsDestroyHeight is -120), one per online
--   owner, reused while online, destroyed on leave / move / after G.HOME_IDLE_DESTROY unused.
--   Player attributes: InHome (owner UserId, 0 outside), HomeRole ("owner" | "guest" | "").
--
-- REMOTES (in ReplicatedStorage.GwangalliRemotes, created by Housing):
--   HomeAction RemoteEvent client -> server (action, payload?). Actions (G.HOME_ACTIONS):
--     "enter" {via = "entrance"|"phone"}   "leave"   "ring" {ownerId}   "answerDoor" {visitorId, accept}
--     "invite" {userId}   "acceptInvite" {ownerId}   "declineInvite" {ownerId}   "kick" {userId}
--     "standUp"   "tv" (toggle)   "eat" {source = "home"}   "groceries"   "delivery" {menuId}
--     "windowPhoto"   "openPanel" {panel = "fridge"|"desk"|"mailbox"|"wardrobe"|"guests"}
--     "placeFurniture" {slotId, variantId}   "resetSlot" {slotId}   "sellSlot" {slotId}
--     "sellStored" {variantId}   "upgrade" {upgradeId}   "buyWithLoan" {listingId}   "repayLoan"
--   HomeState  RemoteEvent server -> client {kind = ...}:
--     "enter"   {role = "owner"|"guest", ownerId, ownerName, listingId, tierKey, tierName, homeName,
--                icon, maxGuests, guests = {{userId, name}}, slots = {{slotId, category, variantId?}},
--                housing = G.housingView(owner profile) (owner only), tvOn}
--     "exit"    {}          "guests" {guests}        "furniture" {slots, housing}
--     "invite"  {ownerId, ownerName, homeName, tierName, expiresIn}
--     "doorbell" {visitorId, visitorName}           "tv" {on}
--     "panel"   {panel, data}   (fridge / desk / mailbox / wardrobe / guests)
--     "pose"    {pose = "sleep"|"eat"|"shower"|"none", seconds?}
--     "openApp" {app, args?}    (desk: ask the phone to open an app, see GwangalliHome.client)
--   HomeQuery  RemoteFunction client -> server ("summary") -> {home = profile home view or false,
--              housing = G.housingView(d), inHome = bool, role, mortgage = {[listingId] = quote}}
-------------------------------------------------------------------------------------------------
G.HOME_TIER_ORDER = { "goshiwon", "oneroom", "officetel", "apartment", "penthouse" }
G.HOME_TIERS = {
	goshiwon = { tier = 1, name = "고시원", icon = "🛏️", view = "alley", maxGuests = 1, color = { 150, 150, 160 } },
	oneroom = { tier = 2, name = "원룸", icon = "🏠", view = "alley", maxGuests = 2, color = { 90, 170, 230 } },
	officetel = { tier = 3, name = "오피스텔", icon = "🏢", view = "sea", maxGuests = 4, color = { 40, 196, 210 } },
	apartment = { tier = 4, name = "아파트", icon = "🏙️", view = "sea", maxGuests = 6, color = { 255, 196, 64 } },
	penthouse = { tier = 5, name = "펜트하우스", icon = "🌊", view = "sea", maxGuests = 10, color = { 176, 110, 255 } },
}
G.HomeTags = { Entrance = "HomeEntrance", Interact = "HomeInteract", Slot = "FurnitureSlot" }
G.HOME_TEMPLATE_FOLDER = "GwangalliHomes"
G.HOME_INSTANCE_FOLDER = "GwangalliHomeInstances"
G.HOME_ORIGIN = { 0, 4000, 0 } -- above everything in the map (max ~2340) and far above the kill plane
G.HOME_SPACING = 400
G.HOME_GRID_COLS = 8
G.HOME_IDLE_DESTROY = 900 -- s an empty instance of an online owner is kept before it is destroyed
G.HOME_ENTRANCE_REACH = 18 -- studs from a HomeEntrance to use its prompts
G.HOME_INVITE_TTL = 60
G.HOME_RING_TTL = 45
G.HOME_KICK_BAN = 180 -- s a kicked visitor cannot ring / be invited to that home again
G.HOME_SHOWER_COOLDOWN = 240
G.HOME_EAT_COOLDOWN = 20
G.HOME_PHOTO_COOLDOWN = 90
G.HOME_TV_EVERY = 15 -- s on the sofa with the TV on per +1 행복
G.HOME_TV_DAILY_MAX = 12
G.HOME_BILLS_MAX = 20
G.HOME_FRIDGE_MAX = 20
G.HOME_STORAGE_MAX = 60 -- stored furniture pieces in total
G.UTILITY_PER_DAY = { 0, 1500, 3000, 5000, 9000 } -- 공과금 (전기·가스·수도) by tier, charged with rent / upkeep

G.HOME_ACTIONS = {
	enter = 2, leave = 2, ring = 3, answerDoor = 0.5, invite = 2, acceptInvite = 1, declineInvite = 0.5, kick = 1,
	standUp = 0.5, tv = 0.6, eat = 1, groceries = 1, delivery = 2, windowPhoto = 1, openPanel = 0.4,
	placeFurniture = 0.6, resetSlot = 0.6, sellSlot = 0.8, sellStored = 0.5, upgrade = 1, buyWithLoan = 1.5, repayLoan = 1.5,
}

-- Home interaction kinds (HomeInteract parts). guest = visitors may use it.
G.HOME_KIND_ORDER = { "bed", "sofa", "tv", "fridge", "table", "shower", "wardrobe", "desk", "window", "mailbox", "door" }
G.HOME_KINDS = {
	bed = { action = "잠자기", object = "침대", hold = 0.35 },
	sofa = { action = "앉기", object = "소파", guest = true },
	tv = { action = "TV 켜기/끄기", object = "TV", guest = true },
	fridge = { action = "냉장고 열기", object = "냉장고" },
	table = { action = "식사하기", object = "식탁" },
	shower = { action = "샤워하기", object = "욕실", hold = 0.3 },
	wardrobe = { action = "옷 갈아입기", object = "옷장" },
	desk = { action = "통장·제안 확인", object = "책상" },
	window = { action = "창밖 보기", object = "창문", guest = true },
	mailbox = { action = "고지서 확인", object = "우편함" },
	door = { action = "나가기", object = "현관", guest = true },
}

function G.homeTierKey(t: any): string?
	if type(t) == "number" then
		return G.HOME_TIER_ORDER[t]
	elseif type(t) == "string" then
		if G.HOME_TIERS[t] then
			return t
		end
		local n = tonumber(t)
		if n then
			return G.HOME_TIER_ORDER[n]
		end
	end
	return nil
end

function G.homeTierNumber(t: any): number
	local key = G.homeTierKey(t)
	return key and G.HOME_TIERS[key].tier or 0
end

-- The listing that uses a tier's interior: listingId, listing.
function G.listingForTier(t: any): (string?, any)
	local key = G.homeTierKey(t)
	if not key then
		return nil, nil
	end
	for _, id in G.LISTING_ORDER do
		local l = G.LISTINGS[id]
		if l and l.tierKey == key then
			return id, l
		end
	end
	return nil, nil
end

function G.homeGuestLimit(t: any): number
	local key = G.homeTierKey(t)
	return key and G.HOME_TIERS[key].maxGuests or 1
end

-- World position (x, y, z) of instance slot `index` (1-based). Columns run along Z and rows stack
-- upwards, so units never share an X column with another unit's window view (the sea-view
-- backdrops reach thousands of studs sideways). spacing = { y, z } (default G.HOME_SPACING); the
-- server derives it from the templates' ViewExtent so no two units' views overlap.
function G.homeSlotPosition(index: number, spacing: { number }?): (number, number, number)
	local i = math.max(1, math.floor(index)) - 1
	local col = i % G.HOME_GRID_COLS
	local row = i // G.HOME_GRID_COLS
	local o = G.HOME_ORIGIN
	local sy = spacing and spacing[1] or G.HOME_SPACING
	local sz = spacing and spacing[2] or G.HOME_SPACING
	return o[1], o[2] + row * sy, o[3] + (col - (G.HOME_GRID_COLS - 1) / 2) * sz
end

-- Grid spacing { y, z } for units whose half-extents (ViewExtent) are at most `ext` = { x, y, z }.
function G.homeSpacingFor(ext: { number }?): { number }
	local ey = if ext and isFiniteNumber(ext[2]) then ext[2] else 0
	local ez = if ext and isFiniteNumber(ext[3]) then ext[3] else 0
	return { math.max(G.HOME_SPACING, math.ceil(2 * ey + 200)), math.max(G.HOME_SPACING, math.ceil(2 * ez + 200)) }
end

-- Geometry of a FurnitureSlot (a BasePart envelope, or the builder's Model with PrimaryPart
-- "SlotBase" + attribute Footprint (W, H, D) + optional MountY, default furniture in the child
-- Model "Furniture"). Returns { container, base, frame (CFrame: bottom centre, front = -Z), w, h,
-- d, default } or nil. Uses Roblox datatypes, so only call it with instances.
function G.slotGeometry(inst: any): any?
	local base, w, h, d, default
	if inst:IsA("BasePart") then
		base = inst
		w, h, d = inst.Size.X, inst.Size.Y, inst.Size.Z
		default = inst:FindFirstChildWhichIsA("Model")
	elseif inst:IsA("Model") then
		base = inst.PrimaryPart or inst:FindFirstChild("SlotBase")
		if not (base and base:IsA("BasePart")) then
			base = inst:FindFirstChildWhichIsA("BasePart")
		end
		if not base then
			return nil
		end
		local fp = inst:GetAttribute("Footprint")
		if typeof(fp) == "Vector3" then
			w, h, d = math.abs(fp.X), math.max(0.05, math.abs(fp.Y)), math.abs(fp.Z)
		else
			w, h, d = base.Size.X, math.max(base.Size.Y, 3), base.Size.Z
		end
		local f = inst:FindFirstChild("Furniture")
		default = if f and f:IsA("Model") then f else nil
		if not default then
			for _, c in inst:GetChildren() do
				if c:IsA("Model") then
					default = c
					break
				end
			end
		end
	else
		return nil
	end
	local frame = base.CFrame * CFrame.new(0, -base.Size.Y / 2, 0)
	if inst:IsA("Model") then
		local cat = inst:GetAttribute("Category")
		local mountY = inst:GetAttribute("MountY")
		if type(mountY) == "number" then
			frame = frame * CFrame.new(0, mountY, 0)
		elseif cat == "art" then
			frame = frame * CFrame.new(0, math.max(0, 5 - h / 2), 0)
		end
		if cat == "art" then
			-- the builder's art slots sit on the wall surface: hang the frame in front of it
			frame = frame * CFrame.new(0, 0, -d / 2)
		end
	end
	return { container = inst, base = base, frame = frame, w = w, h = h, d = d, default = default }
end

-------------------------------------------------------------------------------------------------
-- Furniture catalog. Slot-based decoration: a FurnitureSlot of Category c accepts any variant of c.
-- Buying goes through the ledger (bank first for big items); a replaced piece goes to storage (창고)
-- and can be placed again for free or sold back at G.FURNITURE_RESALE. decor = 인테리어 점수.
-------------------------------------------------------------------------------------------------
G.FURNITURE_RESALE = 0.5
G.FURNITURE_CATEGORY_ORDER = { "sofa", "bed", "tv", "table", "desk", "chair", "shelf", "lamp", "plant", "rug", "art" }
-- size = default envelope W x H x D (studs, 1 stud = 0.3 m) when a slot gives none
G.FURNITURE_CATEGORIES = {
	sofa = { name = "소파", icon = "🛋️", size = { 7, 3, 3.2 } },
	bed = { name = "침대", icon = "🛏️", size = { 5.4, 3.6, 7 } },
	tv = { name = "TV", icon = "📺", size = { 6, 5, 1.6 } },
	table = { name = "테이블", icon = "🍽️", size = { 5, 2.6, 3.2 } },
	desk = { name = "책상", icon = "🖥️", size = { 4.4, 4, 2.2 } },
	chair = { name = "의자", icon = "🪑", size = { 2, 3.2, 2 } },
	shelf = { name = "수납·선반", icon = "📚", size = { 3.2, 6, 1.3 } },
	lamp = { name = "조명", icon = "💡", size = { 1.4, 5.4, 1.4 } },
	plant = { name = "식물", icon = "🪴", size = { 1.6, 4, 1.6 } },
	rug = { name = "러그", icon = "🧶", size = { 8, 0.1, 6 } },
	art = { name = "액자·아트", icon = "🖼️", size = { 3.6, 2.6, 0.3 } },
}
G.FURNITURE_STYLE_ORDER = { "ikea", "modern", "luxury" }
G.FURNITURE_STYLES = {
	ikea = { name = "이케아풍", color = { 70, 150, 230 } },
	modern = { name = "모던", color = { 120, 124, 136 } },
	luxury = { name = "럭셔리", color = { 212, 175, 55 } },
}

G.FURNITURE_ORDER = {}
G.FURNITURE = {}
do
	local function F(id: string, category: string, style: string, name: string, price: number, decor: number, main: { number }, accent: { number }, detail: { number }?)
		G.FURNITURE[id] = { name = name, category = category, style = style, price = price, decor = decor, main = main, accent = accent, detail = detail or accent }
		table.insert(G.FURNITURE_ORDER, id)
	end
	local WOOD, OAK, WALNUT, GOLD, BLACK, WHITE = { 200, 168, 120 }, { 214, 184, 140 }, { 96, 62, 40 }, { 212, 175, 55 }, { 32, 32, 36 }, { 238, 238, 240 }
	F("sofa_ikea", "sofa", "ikea", "패브릭 2인 소파 (그레이)", 190000, 3, { 150, 152, 158 }, WOOD)
	F("sofa_ikea_blue", "sofa", "ikea", "패브릭 소파 (데님 블루)", 210000, 3, { 74, 98, 140 }, WOOD)
	F("sofa_modern", "sofa", "modern", "모던 카우치 (카멜 가죽)", 890000, 6, { 168, 110, 62 }, BLACK, { 236, 226, 206 })
	F("sofa_luxury", "sofa", "luxury", "벨벳 체스터필드 소파", 3800000, 12, { 22, 84, 76 }, GOLD, { 14, 60, 54 })
	F("bed_ikea", "bed", "ikea", "원목 침대 + 체크 이불", 150000, 2, { 120, 160, 200 }, OAK, WHITE)
	F("bed_modern", "bed", "modern", "호텔식 퀸 침대", 1200000, 6, { 244, 244, 246 }, { 60, 60, 66 }, { 178, 156, 124 })
	F("bed_luxury", "bed", "luxury", "킹사이즈 럭셔리 침대", 4500000, 12, { 238, 228, 212 }, { 112, 30, 52 }, GOLD)
	F("tv_ikea", "tv", "ikea", "32인치 TV + 원목 장식장", 250000, 2, OAK, BLACK)
	F("tv_modern", "tv", "modern", "65인치 OLED TV", 2200000, 6, { 44, 44, 48 }, BLACK, WHITE)
	F("tv_luxury", "tv", "luxury", "85인치 월 TV + 대리석 콘솔", 6500000, 11, { 236, 232, 226 }, BLACK, GOLD)
	F("table_ikea", "table", "ikea", "원목 식탁", 120000, 2, OAK, OAK, { 240, 240, 236 })
	F("table_modern", "table", "modern", "세라믹 원형 테이블", 650000, 5, { 228, 226, 222 }, BLACK, { 255, 170, 60 })
	F("table_luxury", "table", "luxury", "대리석 다이닝 테이블", 2800000, 10, { 240, 238, 236 }, GOLD, { 40, 120, 90 })
	F("desk_ikea", "desk", "ikea", "화이트 책상 + 노트북", 110000, 2, WHITE, { 180, 184, 192 }, { 90, 140, 220 })
	F("desk_modern", "desk", "modern", "스탠딩 데스크 + 듀얼 모니터", 780000, 5, { 60, 60, 64 }, BLACK, { 80, 170, 255 })
	F("desk_luxury", "desk", "luxury", "월넛 서재 책상", 2400000, 10, WALNUT, GOLD, { 40, 140, 80 })
	F("chair_ikea", "chair", "ikea", "원목 의자", 45000, 1, OAK, OAK)
	F("chair_modern", "chair", "modern", "디자이너 체어", 420000, 4, WHITE, BLACK, { 90, 90, 96 })
	F("chair_luxury", "chair", "luxury", "벨벳 라운지 체어", 1600000, 8, { 150, 40, 70 }, GOLD)
	F("shelf_ikea", "shelf", "ikea", "5단 책장", 70000, 2, WHITE, { 90, 140, 200 }, { 230, 120, 90 })
	F("shelf_modern", "shelf", "modern", "오픈 선반 + 소품", 380000, 4, { 176, 140, 100 }, BLACK, { 90, 150, 110 })
	F("shelf_luxury", "shelf", "luxury", "월넛 장식장 (와인 수납)", 2100000, 9, WALNUT, GOLD, { 110, 20, 40 })
	F("lamp_ikea", "lamp", "ikea", "종이 갓 스탠드", 35000, 1, { 246, 240, 226 }, OAK)
	F("lamp_modern", "lamp", "modern", "아크 플로어 램프", 290000, 4, WHITE, BLACK)
	F("lamp_luxury", "lamp", "luxury", "골드 크리스털 스탠드", 1200000, 8, { 250, 246, 236 }, GOLD)
	F("plant_ikea", "plant", "ikea", "몬스테라 화분", 30000, 1, { 60, 140, 70 }, { 236, 232, 222 })
	F("plant_ikea2", "plant", "ikea", "스투키 화분", 25000, 1, { 50, 110, 70 }, { 196, 110, 70 })
	F("plant_modern", "plant", "modern", "극락조 대형 화분", 180000, 3, { 40, 128, 70 }, { 40, 40, 44 })
	F("plant_luxury", "plant", "luxury", "올리브 나무 (대리석 화분)", 950000, 7, { 118, 136, 76 }, { 236, 234, 230 }, { 110, 84, 60 })
	F("rug_ikea", "rug", "ikea", "베이지 러그", 40000, 1, { 222, 206, 176 }, { 190, 170, 140 })
	F("rug_modern", "rug", "modern", "기하학 패턴 러그", 260000, 3, { 70, 74, 84 }, { 236, 236, 236 }, { 230, 150, 60 })
	F("rug_luxury", "rug", "luxury", "페르시안 실크 카펫", 2000000, 9, { 128, 30, 40 }, GOLD, { 30, 40, 90 })
	F("art_ikea", "art", "ikea", "광안대교 포스터", 20000, 1, { 24, 36, 74 }, WHITE, { 90, 200, 255 })
	F("art_modern", "art", "modern", "추상화 캔버스", 350000, 4, { 236, 232, 222 }, { 230, 90, 60 }, { 40, 90, 170 })
	F("art_luxury", "art", "luxury", "광안리 야경 유화 (작가 원화)", 3000000, 10, { 14, 20, 48 }, GOLD, { 255, 214, 120 })
	G.FURNITURE.plant_ikea2.form = "spikes"
end

-- Variants of a category, in catalog order: { {id, def}, ... }
function G.furnitureFor(category: string): { { id: string, def: any } }
	local out = {}
	for _, id in G.FURNITURE_ORDER do
		local f = G.FURNITURE[id]
		if f.category == category then
			table.insert(out, { id = id, def = f })
		end
	end
	return out
end

function G.furnitureResale(variantId: string): number
	local f = G.FURNITURE[variantId]
	return f and math.floor(f.price * G.FURNITURE_RESALE) or 0
end

-------------------------------------------------------------------------------------------------
-- Furniture variant generator: G.furnitureSpec(variantId, W, H, D) -> spec (pure data, no instances)
--   spec = { parts = { {name, shape = "Block"|"Cylinder"|"Ball", size = {x,y,z}, pos = {x,y,z},
--            rot = {rx,ry,rz}? (degrees), color = {r,g,b}, material, transparency?, collide?} },
--            seat = {pos, facing = "front"}?, bed = {pos}?, screen = part index?, lights = {{part, range,
--            brightness, color}}? }
-- Frame: origin at the slot's bottom centre (floor), X right, Y up, front = -Z (the slot part's
-- LookVector). Everything fits the W x H x D envelope. Vertical cylinders use rot {0, 0, 90}.
-------------------------------------------------------------------------------------------------
local GEN: { [string]: (any, number, number, number, any, string) -> () } = {}

local function part(spec: any, name: string, shape: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: { number }, material: string, opts: { [string]: any }?): number
	local p = {
		name = name,
		shape = shape,
		size = { math.max(0.05, sx), math.max(0.05, sy), math.max(0.05, sz) },
		pos = { x, y, z },
		color = color,
		material = material,
	}
	if opts then
		for k, v in opts do
			p[k] = v
		end
	end
	table.insert(spec.parts, p)
	return #spec.parts
end
local function box(spec: any, name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: { number }, material: string, opts: { [string]: any }?): number
	return part(spec, name, "Block", sx, sy, sz, x, y, z, color, material, opts)
end
-- vertical cylinder of height h and diameter dia centred at (x, y, z)
local function vcyl(spec: any, name: string, h: number, dia: number, x: number, y: number, z: number, color: { number }, material: string, opts: { [string]: any }?): number
	local o = opts or {}
	o.rot = { 0, 0, 90 }
	return part(spec, name, "Cylinder", h, dia, dia, x, y, z, color, material, o)
end
local function ball(spec: any, name: string, dia: number, x: number, y: number, z: number, color: { number }, material: string, opts: { [string]: any }?): number
	return part(spec, name, "Ball", dia, dia, dia, x, y, z, color, material, opts)
end
local function shade(c: { number }, k: number): { number }
	return { math.clamp(math.floor(c[1] * k), 0, 255), math.clamp(math.floor(c[2] * k), 0, 255), math.clamp(math.floor(c[3] * k), 0, 255) }
end
local function legs4(spec: any, W: number, D: number, h: number, inset: number, thick: number, color: { number }, material: string, round: boolean)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (W / 2 - inset), sz * (D / 2 - inset)
			if round then
				vcyl(spec, "Leg", h, thick, x, h / 2, z, color, material)
			else
				box(spec, "Leg", thick, h, thick, x, h / 2, z, color, material)
			end
		end
	end
end

local FABRIC = { ikea = "Fabric", modern = "Leather", luxury = "Fabric" }
local LEGMAT = { ikea = "Wood", modern = "Metal", luxury = "Foil" }

GEN.sofa = function(s, W, H, D, v, st)
	local legH = if st == "modern" then 0.45 elseif st == "luxury" then 0.3 else 0.5
	local seatTop = math.min(1.6, H * 0.55)
	local baseTop = seatTop - 0.45
	local armW = math.min(0.9, W * 0.13)
	local armH = math.min(H, if st == "luxury" then 2.4 else 2.05)
	local backD = math.min(0.9, D * 0.26)
	local backH = math.min(H, if st == "luxury" then 3.0 else 2.9)
	local mat = FABRIC[st]
	legs4(s, W, D, legH, 0.35, 0.22, v.accent, LEGMAT[st], st ~= "modern")
	box(s, "Base", W, baseTop - legH, D, 0, (legH + baseTop) / 2, 0, v.main, mat, { collide = true })
	box(s, "Back", W - 2 * armW, backH - baseTop, backD, 0, (baseTop + backH) / 2, D / 2 - backD / 2, v.main, mat, { collide = true })
	for _, sx in { -1, 1 } do
		box(s, "Arm", armW, armH - legH, D, sx * (W / 2 - armW / 2), (legH + armH) / 2, 0, shade(v.main, 0.94), mat, { collide = true })
	end
	local n = if W > 6.2 then 3 else 2
	local cw = (W - 2 * armW) / n
	local cd = D - backD - 0.1
	for i = 1, n do
		box(s, "Cushion", cw - 0.08, 0.45, cd, -W / 2 + armW + cw * (i - 0.5), baseTop + 0.225, -D / 2 + cd / 2 + 0.05, shade(v.main, 1.06), mat)
	end
	if st ~= "ikea" then
		for _, sx in { -1, 1 } do
			box(s, "Pillow", 1.1, 1.0, 0.35, sx * (W / 2 - armW - 0.8), baseTop + 0.95, D / 2 - backD - 0.2, v.detail, "Fabric")
		end
	end
	if st == "luxury" then
		for i = 1, 5 do
			ball(s, "Tuft", 0.14, -W / 2 + armW + (W - 2 * armW) * (i - 0.5) / 5, (baseTop + backH) / 2 + 0.3, D / 2 - backD - 0.01, v.detail, "Fabric")
		end
		box(s, "Trim", W, 0.08, D, 0, legH + 0.04, 0, v.accent, "Foil")
	end
	s.seat = { pos = { 0, seatTop, -backD / 2 } }
end

GEN.bed = function(s, W, H, D, v, st)
	local legH = if st == "ikea" then 0.45 else 0
	local frameTop = math.min(H * 0.35, if st == "modern" then 0.95 else 1.05)
	local hbD = 0.35
	local hbH = math.min(H, if st == "luxury" then 4.4 else 3.2)
	local frameColor = v.accent
	if legH > 0 then
		legs4(s, W, D, legH, 0.3, 0.3, frameColor, "Wood", false)
	end
	box(s, "Frame", W, frameTop - legH, D - hbD, 0, (legH + frameTop) / 2, -hbD / 2, frameColor, if st == "ikea" then "Wood" else "Fabric", { collide = true })
	box(s, "Headboard", W + (if st == "luxury" then 0.3 else 0), hbH, hbD, 0, hbH / 2, D / 2 - hbD / 2, frameColor, if st == "luxury" then "Fabric" else (if st == "ikea" then "Wood" else "Fabric"), { collide = true })
	local mW, mD, mH = W - 0.3, D - hbD - 0.3, 0.75
	local mTop = frameTop + mH
	box(s, "Mattress", mW, mH, mD, 0, frameTop + mH / 2, -hbD / 2, { 246, 246, 248 }, "Fabric", { collide = true })
	local bl = mD * 0.64
	box(s, "Blanket", mW + 0.1, 0.2, bl, 0, mTop + 0.05, -D / 2 + 0.15 + bl / 2, v.main, "Fabric")
	box(s, "BlanketFold", mW + 0.1, 0.24, 0.5, 0, mTop + 0.08, -D / 2 + 0.15 + bl - 0.25, v.detail, "Fabric")
	local np = if W >= 4.6 then 2 else 1
	for i = 1, np do
		local pw = (mW - 0.4) / np - 0.2
		box(s, "Pillow", pw, 0.4, 1.1, -mW / 2 + 0.2 + (mW - 0.4) * (i - 0.5) / np, mTop + 0.2, D / 2 - hbD - 0.85, { 250, 250, 252 }, "Fabric")
	end
	if st == "luxury" then
		for r = 1, 2 do
			for c = 1, 4 do
				ball(s, "Tuft", 0.16, -W / 2 + W * (c - 0.5) / 4, math.min(hbH - 0.3 * r, frameTop + 1.2 + r * 0.9), D / 2 - hbD - 0.02, shade(frameColor, 0.7), "Fabric")
			end
		end
		box(s, "Trim", W + 0.3, 0.12, hbD + 0.04, 0, hbH - 0.06, D / 2 - hbD / 2, v.detail, "Foil")
	elseif st == "modern" then
		box(s, "Runner", mW + 0.12, 0.08, 1.2, 0, mTop + 0.2, -D / 2 + 0.15 + bl * 0.55, v.detail, "Fabric")
	end
	s.bed = { pos = { 0, mTop, -hbD / 2 } }
end

GEN.tv = function(s, W, H, D, v, st)
	local ch = math.min(H * 0.4, if st == "luxury" then 1.5 else 1.7)
	local cMat = if st == "ikea" then "Wood" elseif st == "luxury" then "Marble" else "SmoothPlastic"
	if st == "luxury" then
		for _, sx in { -1, 1 } do
			box(s, "Leg", 0.12, ch - 0.25, D - 0.3, sx * (W / 2 - 0.3), (ch - 0.25) / 2, 0, v.detail, "Foil")
		end
		box(s, "Console", W, 0.25, D, 0, ch - 0.125, 0, v.main, cMat, { collide = true })
	else
		box(s, "Console", W, ch, D, 0, ch / 2, 0, v.main, cMat, { collide = true })
		if st == "ikea" then
			for _, sx in { -1, 1 } do
				box(s, "Door", W / 2 - 0.2, ch - 0.35, 0.05, sx * W / 4, ch / 2, -D / 2 - 0.02, shade(v.main, 0.9), "Wood")
			end
		else
			box(s, "Strip", W - 0.3, 0.08, 0.05, 0, ch - 0.25, -D / 2 - 0.02, { 80, 170, 255 }, "Neon")
		end
	end
	local sw = if st == "ikea" then math.min(W * 0.6, 3.4) elseif st == "modern" then math.min(W * 0.86, 5.2) else math.min(W * 0.96, 6.4)
	local sh = sw * 9 / 16
	local room = H - ch - 0.35
	if sh > room then
		sh = math.max(0.6, room)
		sw = sh * 16 / 9
	end
	local sy = ch + 0.3 + sh / 2
	local sz = math.min(D / 2 - 0.1, 0.25)
	if st ~= "luxury" then
		box(s, "Neck", 0.3, 0.3, 0.3, 0, ch + 0.15, sz + 0.05, v.accent, "Metal")
	end
	box(s, "Bezel", sw + 0.12, sh + 0.12, 0.12, 0, sy, sz + 0.1, v.accent, "SmoothPlastic")
	s.screen = box(s, "Screen", sw, sh, 0.06, 0, sy, sz, { 12, 12, 16 }, "Glass")
	if st ~= "ikea" then
		box(s, "Soundbar", math.min(sw * 0.7, W - 0.4), 0.28, 0.4, 0, ch + 0.14, -D / 2 + 0.35, v.accent, "Metal")
	end
end

GEN.table = function(s, W, H, D, v, st)
	local th = math.min(H, 2.5)
	local top = 0.16
	if st == "modern" then
		local dia = math.min(W, D)
		vcyl(s, "Top", top, dia, 0, th - top / 2, 0, v.main, "Marble", { collide = true })
		vcyl(s, "Pedestal", th - top - 0.2, 0.5, 0, (th - top) / 2 + 0.1, 0, v.accent, "Metal")
		vcyl(s, "Foot", 0.2, dia * 0.45, 0, 0.1, 0, v.accent, "Metal")
		vcyl(s, "Vase", 0.8, 0.45, 0, th + 0.4, 0, v.detail, "Glass", { transparency = 0.2 })
	elseif st == "luxury" then
		box(s, "Top", W, top + 0.06, D, 0, th - (top + 0.06) / 2, 0, v.main, "Marble", { collide = true })
		for _, sx in { -1, 1 } do
			box(s, "Trestle", 0.35, th - top - 0.06, D * 0.7, sx * (W / 2 - 0.9), (th - top - 0.06) / 2, 0, v.accent, "Foil")
		end
		vcyl(s, "Bowl", 0.35, 1.0, 0, th + 0.17, 0, v.accent, "Foil")
		ball(s, "Fruit", 0.4, 0.15, th + 0.4, 0.05, v.detail, "SmoothPlastic")
		ball(s, "Fruit", 0.38, -0.2, th + 0.4, -0.1, { 230, 170, 40 }, "SmoothPlastic")
	else
		box(s, "Top", W, top, D, 0, th - top / 2, 0, v.main, "Wood", { collide = true })
		legs4(s, W, D, th - top, 0.3, 0.25, v.accent, "Wood", false)
		box(s, "Runner", W * 0.7, 0.03, 0.9, 0, th + 0.015, 0, v.detail, "Fabric")
	end
end

GEN.desk = function(s, W, H, D, v, st)
	local th = math.min(H * 0.62, 2.45)
	local mat = if st == "luxury" then "Wood" elseif st == "modern" then "SmoothPlastic" else "SmoothPlastic"
	box(s, "Top", W, 0.12, D, 0, th - 0.06, 0, v.main, mat, { collide = true })
	if st == "luxury" then
		for _, sx in { -1, 1 } do
			box(s, "Pedestal", W * 0.28, th - 0.12, D - 0.2, sx * (W / 2 - W * 0.14 - 0.05), (th - 0.12) / 2, 0, v.main, "Wood", { collide = true })
			box(s, "Handle", 0.5, 0.06, 0.06, sx * (W / 2 - W * 0.14 - 0.05), th - 0.5, -D / 2 + 0.07, v.accent, "Foil")
		end
		vcyl(s, "LampBase", 0.1, 0.5, W / 2 - 0.6, th + 0.05, D / 2 - 0.5, v.accent, "Foil")
		local shadeIdx = box(s, "LampShade", 0.9, 0.3, 0.35, W / 2 - 0.6, th + 0.85, D / 2 - 0.5, v.detail, "Glass")
		box(s, "LampPole", 0.08, 0.7, 0.08, W / 2 - 0.6, th + 0.4, D / 2 - 0.5, v.accent, "Foil")
		s.lights = { { part = shadeIdx, range = 8, brightness = 0.8, color = { 255, 220, 160 } } }
		box(s, "Book", 1.0, 0.25, 0.7, -0.6, th + 0.13, 0, { 120, 30, 40 }, "Fabric")
	elseif st == "modern" then
		for _, sx in { -1, 1 } do
			box(s, "Leg", 0.25, th - 0.12, D - 0.3, sx * (W / 2 - 0.3), (th - 0.12) / 2, 0, v.accent, "Metal")
		end
		for _, sx in { -1, 1 } do
			box(s, "Monitor", 1.7, 1.0, 0.08, sx * 0.9, th + 1.05, D / 2 - 0.45, v.accent, "SmoothPlastic")
			box(s, "MonitorGlow", 1.6, 0.9, 0.02, sx * 0.9, th + 1.05, D / 2 - 0.5, v.detail, "Neon", { transparency = 0.35 })
		end
		box(s, "Stand", 0.2, 0.5, 0.2, 0, th + 0.25, D / 2 - 0.4, v.accent, "Metal")
		box(s, "Keyboard", 1.4, 0.06, 0.45, 0, th + 0.03, -D / 2 + 0.6, v.accent, "SmoothPlastic")
	else
		legs4(s, W, D, th - 0.12, 0.2, 0.16, v.accent, "Metal", true)
		box(s, "Laptop", 1.2, 0.06, 0.85, 0, th + 0.03, -0.1, { 190, 194, 200 }, "Metal")
		box(s, "LaptopScreen", 1.2, 0.8, 0.05, 0, th + 0.43, 0.33, { 30, 32, 40 }, "SmoothPlastic")
		box(s, "LaptopGlow", 1.1, 0.7, 0.02, 0, th + 0.43, 0.3, v.detail, "Neon", { transparency = 0.4 })
		vcyl(s, "Mug", 0.35, 0.3, W / 2 - 0.5, th + 0.17, -0.2, { 250, 250, 250 }, "SmoothPlastic")
	end
end

GEN.chair = function(s, W, H, D, v, st)
	local seatY = math.min(1.5, H * 0.47)
	local backH = math.min(H, if st == "luxury" then 3.1 else 3.0)
	local sw, sd = math.min(W, 1.8), math.min(D, 1.8)
	if st == "luxury" then
		box(s, "Base", sw, seatY - 0.3, sd, 0, 0.3 + (seatY - 0.3) / 2, 0, v.main, "Fabric", { collide = true })
		legs4(s, sw, sd, 0.3, 0.2, 0.14, v.accent, "Foil", true)
		box(s, "Back", sw, backH - seatY, 0.4, 0, (seatY + backH) / 2, sd / 2 - 0.2, v.main, "Fabric", { collide = true })
		for _, sx in { -1, 1 } do
			box(s, "Arm", 0.3, 0.8, sd, sx * (sw / 2 - 0.15), seatY + 0.4, 0, shade(v.main, 0.9), "Fabric")
		end
	elseif st == "modern" then
		box(s, "Seat", sw, 0.2, sd, 0, seatY - 0.1, 0, v.main, "SmoothPlastic", { collide = true })
		box(s, "Cushion", sw - 0.2, 0.12, sd - 0.3, 0, seatY + 0.06, -0.05, v.detail, "Fabric")
		box(s, "Back", sw, backH - seatY - 0.2, 0.18, 0, (seatY + backH) / 2 + 0.1, sd / 2 - 0.1, v.main, "SmoothPlastic", { collide = true })
		for _, sx in { -1, 1 } do
			box(s, "Sled", 0.1, seatY - 0.2, 0.1, sx * (sw / 2 - 0.15), (seatY - 0.2) / 2, -sd / 2 + 0.2, v.accent, "Metal")
			box(s, "Sled", 0.1, seatY - 0.2, 0.1, sx * (sw / 2 - 0.15), (seatY - 0.2) / 2, sd / 2 - 0.2, v.accent, "Metal")
			box(s, "Runner", 0.1, 0.08, sd - 0.3, sx * (sw / 2 - 0.15), 0.04, 0, v.accent, "Metal")
		end
	else
		box(s, "Seat", sw, 0.16, sd, 0, seatY - 0.08, 0, v.main, "Wood", { collide = true })
		legs4(s, sw, sd, seatY - 0.16, 0.15, 0.16, v.accent, "Wood", false)
		for i = 1, 3 do
			box(s, "Slat", 0.14, backH - seatY - 0.3, 0.1, -sw / 2 + sw * i / 4, seatY + (backH - seatY - 0.3) / 2, sd / 2 - 0.08, v.accent, "Wood")
		end
		box(s, "BackRail", sw, 0.3, 0.12, 0, backH - 0.15, sd / 2 - 0.08, v.main, "Wood")
	end
	s.seat = { pos = { 0, seatY, 0 } }
end

local BOOKS = { { 180, 60, 60 }, { 60, 110, 180 }, { 230, 190, 80 }, { 70, 140, 90 }, { 240, 240, 236 }, { 120, 80, 160 }, { 40, 40, 44 } }
GEN.shelf = function(s, W, H, D, v, st)
	local mat = if st == "ikea" then "SmoothPlastic" else "Wood"
	local t = 0.14
	local n = math.clamp(math.floor(H / 1.35), 2, 5)
	if st == "modern" then
		for _, sx in { -1, 1 } do
			box(s, "Frame", 0.1, H, 0.1, sx * (W / 2 - 0.05), H / 2, -D / 2 + 0.05, v.accent, "Metal")
			box(s, "Frame", 0.1, H, 0.1, sx * (W / 2 - 0.05), H / 2, D / 2 - 0.05, v.accent, "Metal")
		end
	else
		for _, sx in { -1, 1 } do
			box(s, "Side", t, H, D, sx * (W / 2 - t / 2), H / 2, 0, v.main, mat, { collide = true })
		end
		box(s, "BackPanel", W, H, 0.06, 0, H / 2, D / 2 - 0.03, shade(v.main, 0.92), mat)
	end
	for i = 0, n do
		local y = math.min(H - t / 2, t / 2 + i * (H - t) / n)
		box(s, "Board", W - (if st == "modern" then 0 else 2 * t), t, D - 0.06, 0, y, -0.03, v.main, mat, { collide = i == 0 })
	end
	local idx = 0
	for i = 0, n - 1 do
		local y0 = t + i * (H - t) / n
		local gap = (H - t) / n - t
		if st == "luxury" and i >= n - 1 then
			for b = 1, 3 do
				vcyl(s, "Bottle", math.min(gap - 0.1, 1.0), 0.3, -W / 2 + W * b / 4, y0 + math.min(gap - 0.1, 1.0) / 2, 0, v.detail, "Glass")
			end
		elseif st == "modern" and i % 2 == 1 then
			vcyl(s, "Pot", math.min(gap * 0.5, 0.6), 0.6, -W / 4, y0 + math.min(gap * 0.5, 0.6) / 2, 0, v.accent, "SmoothPlastic")
			ball(s, "Leaves", 0.8, -W / 4, y0 + math.min(gap * 0.5, 0.6) + 0.3, 0, v.detail, "Grass")
			box(s, "Frame", 0.7, math.min(gap * 0.7, 0.9), 0.08, W / 4, y0 + math.min(gap * 0.7, 0.9) / 2, 0.1, { 240, 240, 240 }, "SmoothPlastic")
		else
			-- a row of books (pairs share one block) and a storage box
			local x = -W / 2 + t + 0.1
			local maxX = W / 2 - t - 0.1 - math.min(0.9, W * 0.25)
			local k = 0
			while x < maxX - 0.3 and k < 6 do
				idx += 1
				k += 1
				local bw = 0.34 + (idx % 3) * 0.08
				local bh = math.min(gap - 0.08, 0.8 + (idx % 4) * 0.1)
				box(s, "Book", bw, bh, D * 0.7, x + bw / 2, y0 + bh / 2, -0.05, BOOKS[idx % #BOOKS + 1], "SmoothPlastic")
				x += bw + 0.03
			end
			local bxw = math.min(0.9, W * 0.25)
			box(s, "Box", bxw, math.min(gap - 0.1, 0.6), D * 0.75, W / 2 - t - 0.1 - bxw / 2, y0 + math.min(gap - 0.1, 0.6) / 2, 0, if st == "ikea" then v.accent else v.detail, "Fabric")
		end
	end
	if st == "luxury" then
		box(s, "GlassDoor", W - 0.1, H - 0.2, 0.05, 0, H / 2, -D / 2 + 0.03, { 200, 220, 230 }, "Glass", { transparency = 0.7 })
		box(s, "Handle", 0.06, 0.8, 0.06, 0.2, H / 2, -D / 2 - 0.02, v.accent, "Foil")
	end
end

GEN.lamp = function(s, W, H, D, v, st)
	local top = math.min(H, 5.4)
	local baseD = math.min(W, D, 1.2)
	if st == "modern" then
		vcyl(s, "Base", 0.18, baseD, 0, 0.09, 0, v.accent, "Marble")
		box(s, "Pole", 0.12, top - 0.6, 0.12, 0, (top - 0.6) / 2, 0, v.accent, "Metal")
		box(s, "Arm", math.min(W, 2.2) * 0.5, 0.1, 0.1, math.min(W, 2.2) * 0.25 - 0.05, top - 0.6, 0, v.accent, "Metal")
		local sx = math.min(W, 2.2) * 0.5 - 0.1
		ball(s, "Dome", 0.9, math.min(sx, W / 2 - 0.45), top - 0.75, 0, v.main, "SmoothPlastic")
		s.lights = { { part = ball(s, "Bulb", 0.35, math.min(sx, W / 2 - 0.45), top - 1.05, 0, { 255, 236, 200 }, "Neon"), range = 16, brightness = 1.1, color = { 255, 226, 180 } } }
	elseif st == "luxury" then
		vcyl(s, "Base", 0.25, baseD, 0, 0.125, 0, v.accent, "Foil")
		vcyl(s, "Pole", top - 1.6, 0.16, 0, 0.25 + (top - 1.6) / 2, 0, v.accent, "Foil")
		for i = 1, 3 do
			ball(s, "Crystal", 0.28, 0, 0.6 + i * (top - 2.2) / 4, 0, { 230, 240, 250 }, "Glass", { transparency = 0.3 })
		end
		vcyl(s, "Shade", 1.1, math.min(W, 1.4), 0, top - 0.55, 0, v.main, "Fabric", { transparency = 0.1 })
		s.lights = { { part = ball(s, "Bulb", 0.4, 0, top - 0.7, 0, { 255, 232, 190 }, "Neon"), range = 18, brightness = 1.2, color = { 255, 214, 160 } } }
	else
		vcyl(s, "Base", 0.15, baseD * 0.9, 0, 0.075, 0, v.accent, "Wood")
		for _, a in { 0, 120, 240 } do
			local r = math.rad(a)
			box(s, "Leg", 0.1, top - 1.2, 0.1, math.cos(r) * 0.25, (top - 1.2) / 2, math.sin(r) * 0.25, v.accent, "Wood")
		end
		vcyl(s, "Shade", 1.1, math.min(W, 1.3), 0, top - 0.6, 0, v.main, "Fabric", { transparency = 0.15 })
		s.lights = { { part = ball(s, "Bulb", 0.35, 0, top - 0.7, 0, { 255, 240, 210 }, "Neon"), range = 14, brightness = 0.9, color = { 255, 230, 190 } } }
	end
end

GEN.plant = function(s, W, H, D, v, st)
	local dia = math.min(W, D) * (if st == "luxury" then 0.85 else 0.7)
	local potH = math.min(H * 0.3, if st == "luxury" then 1.6 else 1.1)
	local potMat = if st == "luxury" then "Marble" elseif st == "modern" then "SmoothPlastic" else "Plastic"
	vcyl(s, "Pot", potH, dia, 0, potH / 2, 0, v.accent, potMat, { collide = true })
	vcyl(s, "Soil", 0.06, dia * 0.9, 0, potH + 0.02, 0, { 70, 50, 36 }, "Ground")
	local top = math.min(H, 4.4)
	if st == "luxury" then
		box(s, "Trunk", 0.25, top * 0.5, 0.25, 0, potH + top * 0.25 - potH * 0.5, 0, v.detail, "Wood")
		local cy = potH + (top - potH) * 0.65
		for i, o in { { 0, 0.3, 0 }, { 0.45, 0, 0.2 }, { -0.45, 0.05, -0.15 }, { 0.15, -0.1, -0.45 }, { -0.1, 0.1, 0.45 } } do
			local r = math.min(W, D) * (if i == 1 then 0.55 else 0.42)
			ball(s, "Canopy", r, o[1] * math.min(W, 1.6) / 1.6, math.min(top - r / 2, cy + o[2]), o[3] * math.min(D, 1.6) / 1.6, shade(v.main, 0.9 + i * 0.03), "Grass")
		end
	elseif st == "modern" then
		for i = 1, 5 do
			local a = math.rad(i * 72)
			local h = (top - potH) * (0.6 + (i % 3) * 0.15)
			box(s, "Stalk", 0.08, h, 0.08, math.cos(a) * 0.15, potH + h / 2, math.sin(a) * 0.15, v.main, "Grass")
			box(s, "Leaf", 0.12, math.min(1.4, h * 0.45), 0.55, math.cos(a) * 0.35, math.min(top - 0.7, potH + h - 0.3), math.sin(a) * 0.35, shade(v.main, 1.1), "Grass", { rot = { 0, i * 72, 18 } })
		end
	elseif v.form == "spikes" then -- 스투키: upright spikes
		for i = 1, 6 do
			local a = math.rad(i * 60)
			local h = (top - potH) * (0.55 + (i % 3) * 0.12)
			vcyl(s, "Spike", h, 0.16, math.cos(a) * dia * 0.2, potH + h / 2, math.sin(a) * dia * 0.2, v.main, "Grass")
		end
	else
		for i, o in { { 0, 0.9 }, { 0.35, 0.6 }, { -0.35, 0.55 }, { 0.1, 0.35 }, { -0.1, 0.75 } } do
			local r = math.min(W, D) * 0.45
			ball(s, "Leaf", r, o[1] * math.min(W, 1.6) / 1.6, math.min(top - r / 2, potH + (top - potH) * o[2]), (i % 2 - 0.5) * 0.3, shade(v.main, 0.9 + i * 0.04), "Grass")
		end
	end
end

GEN.rug = function(s, W, H, D, v, st)
	local t = math.min(H, 0.06)
	box(s, "Rug", W, t, D, 0, t / 2, 0, v.main, if st == "ikea" then "Carpet" else "Fabric")
	if st == "modern" then
		box(s, "Band", W * 0.8, t + 0.01, D * 0.12, 0, t / 2 + 0.005, -D * 0.2, v.accent, "Fabric")
		box(s, "Band", W * 0.8, t + 0.01, D * 0.12, 0, t / 2 + 0.005, D * 0.2, v.detail, "Fabric")
		box(s, "Block", W * 0.25, t + 0.012, D * 0.25, W * 0.25, t / 2 + 0.006, 0, v.accent, "Fabric")
	elseif st == "luxury" then
		for _, e in { { W, 0.25, 0, D / 2 - 0.3 }, { W, 0.25, 0, -D / 2 + 0.3 } } do
			box(s, "Border", e[1] - 0.4, t + 0.01, e[2], e[3], t / 2 + 0.005, e[4], v.accent, "Fabric")
		end
		for _, sx in { -1, 1 } do
			box(s, "Border", 0.25, t + 0.01, D - 0.4, sx * (W / 2 - 0.3), t / 2 + 0.005, 0, v.accent, "Fabric")
		end
		box(s, "Field", W - 1.4, t + 0.008, D - 1.4, 0, t / 2 + 0.004, 0, shade(v.main, 0.85), "Fabric")
		vcyl(s, "Medallion", t + 0.014, math.min(W, D) * 0.4, 0, t / 2 + 0.007, 0, v.detail, "Fabric")
	else
		box(s, "Inner", W - 0.8, t + 0.01, D - 0.8, 0, t / 2 + 0.005, 0, v.accent, "Carpet")
		box(s, "Center", W - 1.2, t + 0.02, D - 1.2, 0, t / 2 + 0.01, 0, v.main, "Carpet")
	end
end

GEN.art = function(s, W, H, D, v, st)
	local fd = math.min(D, 0.14)
	local z = D / 2 - fd / 2
	local frameColor = if st == "luxury" then v.accent elseif st == "modern" then { 30, 30, 32 } else { 250, 250, 250 }
	box(s, "Frame", W, H, fd, 0, H / 2, z, frameColor, if st == "luxury" then "Foil" else "SmoothPlastic")
	local cw, ch = W - (if st == "luxury" then 0.5 else 0.3), H - (if st == "luxury" then 0.5 else 0.3)
	local cz = z - fd / 2 - 0.01
	box(s, "Canvas", cw, ch, 0.02, 0, H / 2, cz, v.main, if st == "ikea" then "SmoothPlastic" else "Fabric")
	if st == "modern" then
		box(s, "Shape", cw * 0.45, ch * 0.5, 0.02, -cw * 0.18, H / 2 + ch * 0.1, cz - 0.01, v.accent, "Fabric")
		local dia = math.min(cw, ch) * 0.4
		part(s, "Circle", "Cylinder", 0.02, dia, dia, cw * 0.22, H / 2 - ch * 0.12, cz - 0.015, v.detail, "Fabric", { rot = { 0, 90, 0 } })
		box(s, "Line", cw * 0.8, 0.06, 0.02, 0, H / 2 - ch * 0.3, cz - 0.012, { 30, 30, 32 }, "Fabric")
	else
		-- 광안대교 at night: sea strip, deck, two towers, light dots
		box(s, "Sea", cw, ch * 0.28, 0.02, 0, H / 2 - ch * 0.36, cz - 0.005, shade(v.main, 1.6), "Fabric")
		box(s, "Deck", cw * 0.92, 0.07, 0.02, 0, H / 2 - ch * 0.18, cz - 0.012, v.detail, "Neon")
		for _, sx in { -1, 1 } do
			box(s, "Tower", 0.08, ch * 0.45, 0.02, sx * cw * 0.22, H / 2 + ch * 0.02, cz - 0.012, v.detail, "Neon")
		end
		if st == "luxury" then
			for i = 1, 5 do
				ball(s, "Light", 0.1, -cw * 0.4 + cw * 0.8 * (i - 1) / 4, H / 2 + ch * 0.28, cz - 0.02, { 255, 240, 200 }, "Neon")
			end
		end
	end
end

-- Pure spec for a variant in a W x H x D envelope (nil for unknown ids).
function G.furnitureSpec(variantId: string, W: number?, H: number?, D: number?): any?
	local v = G.FURNITURE[variantId]
	if not v then
		return nil
	end
	local c = G.FURNITURE_CATEGORIES[v.category]
	local w = if isFiniteNumber(W) and (W :: number) > 0.2 then W :: number else c.size[1]
	local h = if isFiniteNumber(H) and (H :: number) > 0.05 then H :: number else c.size[2]
	local d = if isFiniteNumber(D) and (D :: number) > 0.05 then D :: number else c.size[3]
	local spec = { parts = {}, variant = variantId, category = v.category, size = { w, h, d } }
	GEN[v.category](spec, w, h, d, v, v.style)
	return spec
end
-- The generator table, so the homes extension (GwangalliHomesShared) can register categories.
G.FURNITURE_GEN = GEN

-------------------------------------------------------------------------------------------------
-- Remodelling (리모델링, owned homes): raises the home's value (net worth) and comfort.
-------------------------------------------------------------------------------------------------
G.HOME_UPGRADE_ORDER = { "wallpaper", "aircon", "smarthome", "kitchen", "terrace" }
G.HOME_UPGRADES = {
	wallpaper = { name = "도배·장판 새로 하기", icon = "🎨", price = 1500000, value = 1200000, comfort = 2, desc = "화사한 벽지와 원목 장판" },
	aircon = { name = "시스템 에어컨", icon = "❄️", price = 2500000, value = 2000000, comfort = 2, desc = "여름에도 쾌적하게" },
	smarthome = { name = "스마트홈 IoT", icon = "📱", price = 3000000, value = 2400000, comfort = 2, desc = "조명·보일러·도어락을 폰으로" },
	kitchen = { name = "주방 리모델링", icon = "🍳", price = 5000000, value = 4500000, comfort = 3, desc = "아일랜드 식탁과 빌트인 가전" },
	terrace = { name = "테라스 조경", icon = "🌿", price = 8000000, value = 7000000, comfort = 4, minTier = 5, desc = "펜트하우스 루프탑 정원" },
}

-------------------------------------------------------------------------------------------------
-- 주택담보대출: down payment + a daily installment for `days` of the player's days, taken with the
-- 관리비. forecloseAfter missed installments -> 경매 (auction at auctionRate of the value).
-------------------------------------------------------------------------------------------------
G.MORTGAGE = { downPayment = 0.2, rate = 0.1, days = 90, forecloseAfter = 5, auctionRate = 0.7 }

-- price = the unit's price (G.homePrices(...).price; nil = the listing's base price)
function G.mortgageQuote(listingId: string, price: number?): any?
	local l = G.LISTINGS[listingId]
	if not l or l.kind ~= "buy" then
		return nil
	end
	local p = if isFiniteNumber(price) and (price :: number) > 0 then price :: number else l.price
	local m = G.MORTGAGE
	local down = G.round100(p * m.downPayment)
	local principal = p - down
	local total = G.round100(principal * (1 + m.rate))
	local daily = math.ceil(total / m.days / 100) * 100
	return { price = p, down = down, principal = principal, total = total, daily = daily, days = m.days, upkeep = l.upkeepPerDay or 0 }
end

function G.activeLoan(d: any): any?
	local h = d.housing
	local loan = type(h) == "table" and h.loan or nil
	if type(loan) ~= "table" or not d.home or loan.listingId ~= d.home.listingId or not isFiniteNumber(loan.remaining) or loan.remaining <= 0 then
		return nil
	end
	return loan
end

function G.loanDaily(d: any): number
	local loan = G.activeLoan(d)
	return if loan then math.min(loan.daily, loan.remaining) else 0
end

-- Buys with a mortgage: pays the down payment (bank, then cash). Returns ok, reason ("unknown" |
-- "notBuy" | "same" | "loan" (already has one) | "insufficient").
function G.buyHomeWithLoan(d: any, listingId: string, now: number?, choice: any?): (boolean, string?)
	local l = G.LISTINGS[listingId]
	local c = resolveChoice(listingId, choice)
	local q = G.mortgageQuote(listingId, G.homePrices(listingId, c).price)
	if not l or not q then
		return false, if l then "notBuy" else "unknown"
	end
	if d.home and d.home.listingId == listingId then
		return false, "same"
	end
	G.ensureHousing(d)
	local credit = currentCredit(d)
	local hasOtherLoan = type(d.housing.loan) == "table" and not (d.home and d.home.owned and d.housing.loan.listingId == d.home.listingId)
	if hasOtherLoan then
		return false, "loan"
	end
	if (d.bank or 0) + credit < q.down and (d.cash or 0) < q.down then
		return false, "insufficient"
	end
	if d.home and d.home.owned then
		sellCurrent(d, now)
	else
		moveOut(d, now)
	end
	if (d.bank or 0) >= q.down then
		G.ledger(d, "bank", -q.down, l.name .. " 계약금 (대출 매매)", now)
	else
		G.ledger(d, "cash", -q.down, l.name .. " 계약금 (대출 매매)", now)
	end
	d.home = newHome(listingId, l, c)
	G.setHomeAddress(d)
	d.housing.loan = { listingId = listingId, principal = q.principal, remaining = q.total, daily = q.daily, missed = 0, arrears = 0, t = now or 0 }
	return true, nil
end

-- Pays the whole remaining mortgage from the bank (then cash). Returns ok, amount | reason.
function G.repayLoan(d: any, now: number?): (boolean, any)
	local loan = G.activeLoan(d)
	if not loan then
		return false, "noLoan"
	end
	local amt = loan.remaining
	local ok = G.spend(d, amt, "주택담보대출 완납", now, "bank")
	if not ok then
		return false, "insufficient"
	end
	d.housing.loan = nil
	if d.home then
		d.home.arrears = 0
		d.home.missed = 0
	end
	return true, amt
end

-------------------------------------------------------------------------------------------------
-- Housing profile data (d.housing), persisted with the profile:
--   units = { [listingId] = { slots = { [slotId] = variantId } } }   placed furniture per listing
--   storage = { [variantId] = count }   fridge = meals of groceries   upgrades = { [listingId] = { [id] = true } }
--   bills = { {t, day, kind, label, amount, paid} } (newest last)   loan = {...} | nil
--   housewarming = { [listingId] = { done, count, guests = { [userId string] = true } } }
--   daily = { day, tv, photos, showers }   lastShower = unix
-------------------------------------------------------------------------------------------------
G.HOME_FOOD = {
	groceries = { name = "장보기 (집밥 재료 5끼)", price = 18000, meals = 5 },
	meal = { name = "집밥", stats = { stamina = 18, happiness = 3 } },
	DELIVERY_ORDER = { "tteok", "jjajang", "chicken", "pizza", "jokbal" },
	delivery = {
		tteok = { name = "떡볶이 세트", icon = "🌶️", price = 13000, wait = 10, stats = { stamina = 15, happiness = 6 } },
		jjajang = { name = "짜장면 + 탕수육", icon = "🍜", price = 16000, wait = 12, stats = { stamina = 20, happiness = 5 } },
		chicken = { name = "후라이드 치킨", icon = "🍗", price = 21000, wait = 14, stats = { stamina = 22, happiness = 7 } },
		pizza = { name = "피자 라지", icon = "🍕", price = 25000, wait = 14, stats = { stamina = 24, happiness = 7 } },
		jokbal = { name = "족발·보쌈", icon = "🍖", price = 32000, wait = 16, stats = { stamina = 28, happiness = 9, popularity = 0.5 } },
	},
}

function G.defaultHousing(): any
	return { units = {}, storage = {}, fridge = 0, upgrades = {}, bills = {}, housewarming = {}, loan = nil, daily = { day = 0, tv = 0, photos = 0, showers = 0 }, lastShower = 0 }
end

function G.ensureHousing(d: any): any
	if type(d.housing) ~= "table" then
		d.housing = G.defaultHousing()
	end
	return d.housing
end

local function cleanKey(k: any, maxLen: number): string?
	if type(k) ~= "string" or #k == 0 or #k > maxLen then
		return nil
	end
	return k
end

local function num0(v: any, lo: number, hi: number): number
	if not isFiniteNumber(v) then
		return lo
	end
	return math.clamp(math.floor(v), lo, hi)
end

-- Sanitises saved housing data (never errors on garbage).
function G.sanitizeHousing(raw: any): any
	local h = G.defaultHousing()
	if type(raw) ~= "table" then
		return h
	end
	if type(raw.units) == "table" then
		for lid, u in raw.units do
			if G.LISTINGS[lid] and type(u) == "table" and type(u.slots) == "table" then
				local slots = {}
				local n = 0
				for sid, vid in u.slots do
					local s = cleanKey(sid, 40)
					if s and type(vid) == "string" and G.FURNITURE[vid] and n < 40 then
						slots[s] = vid
						n += 1
					end
				end
				h.units[lid] = { slots = slots }
			end
		end
	end
	local total = 0
	if type(raw.storage) == "table" then
		for vid, c in raw.storage do
			if G.FURNITURE[vid] and isFiniteNumber(c) and c >= 1 and total < G.HOME_STORAGE_MAX then
				local n = math.min(math.floor(c), G.HOME_STORAGE_MAX - total)
				h.storage[vid] = n
				total += n
			end
		end
	end
	h.fridge = num0(raw.fridge, 0, G.HOME_FRIDGE_MAX)
	if type(raw.upgrades) == "table" then
		for lid, u in raw.upgrades do
			if G.LISTINGS[lid] and type(u) == "table" then
				local set = {}
				for id, x in u do
					if G.HOME_UPGRADES[id] and x then
						set[id] = true
					end
				end
				h.upgrades[lid] = set
			end
		end
	end
	if type(raw.bills) == "table" then
		for _, b in raw.bills do
			if type(b) == "table" and type(b.label) == "string" and isFiniteNumber(b.amount) then
				table.insert(h.bills, {
					t = num0(b.t, 0, 2 ^ 40),
					day = num0(b.day, 0, 1e7),
					kind = cleanKey(b.kind, 16) or "bill",
					label = G.clipText(b.label, 120),
					amount = math.floor(b.amount),
					paid = b.paid == true,
				})
			end
		end
		while #h.bills > G.HOME_BILLS_MAX do
			table.remove(h.bills, 1)
		end
	end
	if type(raw.housewarming) == "table" then
		for lid, hw in raw.housewarming do
			if G.LISTINGS[lid] and type(hw) == "table" then
				local guests = {}
				local n = 0
				if type(hw.guests) == "table" then
					for k, x in hw.guests do
						if cleanKey(k, 20) and x and n < 20 then
							guests[k] = true
							n += 1
						end
					end
				end
				h.housewarming[lid] = { done = hw.done == true, count = n, guests = guests }
			end
		end
	end
	local loan = raw.loan
	if type(loan) == "table" and type(loan.listingId) == "string" and G.LISTINGS[loan.listingId] and G.LISTINGS[loan.listingId].kind == "buy" and isFiniteNumber(loan.remaining) and loan.remaining > 0 then
		local q = G.mortgageQuote(loan.listingId, G.LISTINGS[loan.listingId].price * 3) -- a unit costs up to 3x the base (floor price multiplier)
		h.loan = {
			listingId = loan.listingId,
			principal = num0(loan.principal, 0, q.price),
			remaining = num0(loan.remaining, 1, q.total),
			daily = num0(loan.daily, 100, q.total),
			missed = num0(loan.missed, 0, G.MORTGAGE.forecloseAfter),
			arrears = num0(loan.arrears, 0, q.total),
			t = num0(loan.t, 0, 2 ^ 40),
		}
	end
	if type(raw.daily) == "table" then
		h.daily = { day = num0(raw.daily.day, 0, 1e7), tv = num0(raw.daily.tv, 0, 1000), photos = num0(raw.daily.photos, 0, 1000), showers = num0(raw.daily.showers, 0, 1000) }
	end
	h.lastShower = num0(raw.lastShower, 0, 2 ^ 40)
	return h
end

-- Aligns housing with the home after load: a loan for a home no longer owned is dropped.
function G.reconcileHousing(d: any)
	local h = G.ensureHousing(d)
	if h.loan and not (d.home and d.home.owned and d.home.listingId == h.loan.listingId) then
		h.loan = nil
	end
end

local function storageCount(h: any): number
	local n = 0
	for _, c in h.storage do
		n += c
	end
	return n
end

local function unitOf(h: any, listingId: string): any
	local u = h.units[listingId]
	if not u then
		u = { slots = {} }
		h.units[listingId] = u
	end
	return u
end

-- Places `variantId` into a slot of the current home. From storage when there is one, else buys
-- it (bank first). The replaced piece goes to storage. Returns ok, reason | info:
--   reason: "noHome" | "unknown" | "category" | "same" | "insufficient" | "storageFull"
--   info: { bought = bool, price, displaced = variantId? }
function G.placeFurniture(d: any, slotId: string, slotCategory: string, variantId: string, now: number?): (boolean, any)
	local h = G.ensureHousing(d)
	if not d.home then
		return false, "noHome"
	end
	local f = G.FURNITURE[variantId]
	if not f or type(slotId) ~= "string" or #slotId == 0 or #slotId > 40 then
		return false, "unknown"
	end
	if f.category ~= slotCategory then
		return false, "category"
	end
	local u = unitOf(h, d.home.listingId)
	local current = u.slots[slotId]
	if current == variantId then
		return false, "same"
	end
	local fromStorage = (h.storage[variantId] or 0) > 0
	if current and not fromStorage and storageCount(h) >= G.HOME_STORAGE_MAX then
		return false, "storageFull"
	end
	local info = { bought = false, price = 0, displaced = current }
	if fromStorage then
		h.storage[variantId] -= 1
		if h.storage[variantId] <= 0 then
			h.storage[variantId] = nil
		end
	else
		local ok = G.spend(d, f.price, "가구 구매 · " .. f.name, now, "bank")
		if not ok then
			return false, "insufficient"
		end
		info.bought = true
		info.price = f.price
	end
	if current then
		h.storage[current] = (h.storage[current] or 0) + 1
	end
	u.slots[slotId] = variantId
	return true, info
end

-- Puts the slot back to the template's default furniture (the piece goes to storage).
function G.resetSlot(d: any, slotId: string): (boolean, any)
	local h = G.ensureHousing(d)
	if not d.home then
		return false, "noHome"
	end
	local u = h.units[d.home.listingId]
	local current = u and u.slots[slotId]
	if not current then
		return false, "empty"
	end
	if storageCount(h) >= G.HOME_STORAGE_MAX then
		return false, "storageFull"
	end
	u.slots[slotId] = nil
	h.storage[current] = (h.storage[current] or 0) + 1
	return true, current
end

-- Sells the piece placed in a slot at the resale rate. Returns ok, amount | reason.
function G.sellSlot(d: any, slotId: string, now: number?): (boolean, any)
	local h = G.ensureHousing(d)
	if not d.home then
		return false, "noHome"
	end
	local u = h.units[d.home.listingId]
	local current = u and u.slots[slotId]
	if not current then
		return false, "empty"
	end
	u.slots[slotId] = nil
	local amt = G.furnitureResale(current)
	G.ledger(d, "bank", amt, "가구 판매 · " .. G.FURNITURE[current].name, now)
	return true, amt
end

function G.sellStored(d: any, variantId: string, now: number?): (boolean, any)
	local h = G.ensureHousing(d)
	if not G.FURNITURE[variantId] or (h.storage[variantId] or 0) <= 0 then
		return false, "empty"
	end
	h.storage[variantId] -= 1
	if h.storage[variantId] <= 0 then
		h.storage[variantId] = nil
	end
	local amt = G.furnitureResale(variantId)
	G.ledger(d, "bank", amt, "가구 판매 · " .. G.FURNITURE[variantId].name, now)
	return true, amt
end

-- Moving out: the furniture placed in `listingId` goes to storage (over the cap it is sold).
-- Returns moved count, sold amount.
function G.moveOutFurniture(d: any, listingId: string, now: number?): (number, number)
	local h = G.ensureHousing(d)
	local u = h.units[listingId]
	if not u then
		return 0, 0
	end
	local moved, sold = 0, 0
	local ids = {}
	for sid in u.slots do
		table.insert(ids, sid)
	end
	table.sort(ids)
	for _, sid in ids do
		local vid = u.slots[sid]
		if storageCount(h) < G.HOME_STORAGE_MAX then
			h.storage[vid] = (h.storage[vid] or 0) + 1
			moved += 1
		else
			local amt = G.furnitureResale(vid)
			G.ledger(d, "bank", amt, "가구 판매 (이사) · " .. G.FURNITURE[vid].name, now)
			sold += amt
		end
	end
	h.units[listingId] = nil
	return moved, sold
end

-- Resale value of all furniture owned (placed in the current home + storage).
function G.furnitureValue(d: any): number
	local h = d.housing
	if type(h) ~= "table" then
		return 0
	end
	local v = 0
	for vid, c in h.storage or {} do
		v += G.furnitureResale(vid) * c
	end
	if d.home and h.units then
		local u = h.units[d.home.listingId]
		if u then
			for _, vid in u.slots do
				v += G.furnitureResale(vid)
			end
		end
	end
	return v
end

-- 인테리어 점수 of the furniture placed in the current home.
function G.homeDecor(d: any): number
	local h = d.housing
	if type(h) ~= "table" or not d.home then
		return 0
	end
	local u = h.units and h.units[d.home.listingId]
	local s = 0
	if u then
		for _, vid in u.slots do
			local f = G.FURNITURE[vid]
			if f then
				s += f.decor
			end
		end
	end
	return s
end

function G.upgradesValue(d: any, listingId: string): number
	local h = d.housing
	local set = type(h) == "table" and h.upgrades and h.upgrades[listingId]
	local v = 0
	if set then
		for id in set do
			local u = G.HOME_UPGRADES[id]
			if u then
				v += u.value
			end
		end
	end
	return v
end

local function upgradesComfort(d: any, listingId: string): number
	local h = d.housing
	local set = type(h) == "table" and h.upgrades and h.upgrades[listingId]
	local v = 0
	if set then
		for id in set do
			local u = G.HOME_UPGRADES[id]
			if u then
				v += u.comfort
			end
		end
	end
	return v
end

-- Extra 행복 when sleeping at home: listing comfort + remodelling + furniture decor (max +10).
function G.homeComfort(d: any): number
	if not d.home then
		return 0
	end
	local l = G.LISTINGS[d.home.listingId]
	local base = l and l.comfort or 0
	return base + upgradesComfort(d, d.home.listingId) + math.min(10, math.floor(G.homeDecor(d) / 6))
end

-- Buys a remodelling upgrade for the current (owned) home. Returns ok, reason.
function G.buyUpgrade(d: any, upgradeId: string, now: number?): (boolean, string?)
	local h = G.ensureHousing(d)
	local u = G.HOME_UPGRADES[upgradeId]
	if not u then
		return false, "unknown"
	end
	if not d.home then
		return false, "noHome"
	end
	if not d.home.owned then
		return false, "notOwned"
	end
	if u.minTier and (d.home.tier or 0) < u.minTier then
		return false, "tier"
	end
	local set = h.upgrades[d.home.listingId]
	if not set then
		set = {}
		h.upgrades[d.home.listingId] = set
	end
	if set[upgradeId] then
		return false, "owned"
	end
	if not G.spend(d, u.price, "리모델링 · " .. u.name, now, "bank") then
		return false, "insufficient"
	end
	set[upgradeId] = true
	return true, nil
end

-- Mailbox: a bill / notice. kind = "rent" | "upkeep" | "loan" | "utility" | "missed" | "evicted" |
-- "foreclosed" | "loanPaid" | "info".
function G.addBill(d: any, kind: string, label: string, amount: number, paid: boolean, now: number?)
	local h = G.ensureHousing(d)
	table.insert(h.bills, { t = now or 0, day = d.lifeDay or 1, kind = kind, label = G.clipText(label, 120), amount = math.floor(amount or 0), paid = paid == true })
	while #h.bills > G.HOME_BILLS_MAX do
		table.remove(h.bills, 1)
	end
end

-- 공과금 for the day (charged by the server with the daily rent / upkeep). Returns amount, paid.
function G.chargeUtilities(d: any, now: number?): (number, boolean)
	if not d.home then
		return 0, true
	end
	local amt = G.UTILITY_PER_DAY[d.home.tier or 1] or 0
	if amt <= 0 then
		return 0, true
	end
	local ok = G.spend(d, amt, "공과금 (전기·가스·수도)", now, "bank")
	G.addBill(d, "utility", "공과금 (전기·가스·수도)", amt, ok, now)
	return amt, ok
end

-- The player's own-day counters (tv happiness, photos, showers) reset on a new life day.
function G.housingDaily(d: any): any
	local h = G.ensureHousing(d)
	local day = d.lifeDay or 1
	if h.daily.day ~= day then
		h.daily = { day = day, tv = 0, photos = 0, showers = 0 }
	end
	return h.daily
end

-- A guest entered the owner's home. Returns { party = bool (first 집들이 for this listing),
-- newGuest = bool, count }.
function G.housewarmingVisit(d: any, guestKey: string): any
	local h = G.ensureHousing(d)
	if not d.home then
		return { party = false, newGuest = false, count = 0 }
	end
	local lid = d.home.listingId
	local hw = h.housewarming[lid]
	if not hw then
		hw = { done = false, count = 0, guests = {} }
		h.housewarming[lid] = hw
	end
	local key = string.sub(tostring(guestKey), 1, 20)
	local newGuest = false
	if not hw.guests[key] and hw.count < 20 then
		hw.guests[key] = true
		hw.count += 1
		newGuest = true
	end
	local party = false
	if not hw.done then
		hw.done = true
		party = true
	end
	return { party = party, newGuest = newGuest, count = hw.count }
end

function G.buyGroceries(d: any, now: number?): (boolean, string?)
	local h = G.ensureHousing(d)
	local g = G.HOME_FOOD.groceries
	if h.fridge + g.meals > G.HOME_FRIDGE_MAX then
		return false, "full"
	end
	if not G.spend(d, g.price, g.name, now) then
		return false, "insufficient"
	end
	h.fridge += g.meals
	return true, nil
end

function G.eatHomeMeal(d: any): (boolean, any)
	local h = G.ensureHousing(d)
	if h.fridge <= 0 then
		return false, "empty"
	end
	h.fridge -= 1
	return true, G.HOME_FOOD.meal.stats
end

-- Client view of d.housing (profile view key "housing", HomeState payloads).
function G.housingView(d: any): any
	local h = G.ensureHousing(d)
	local lid = d.home and d.home.listingId
	local slots = {}
	if lid and h.units[lid] then
		for sid, vid in h.units[lid].slots do
			slots[sid] = vid
		end
	end
	local storage = {}
	for vid, c in h.storage do
		storage[vid] = c
	end
	local ups = {}
	if lid and h.upgrades[lid] then
		for id in h.upgrades[lid] do
			table.insert(ups, id)
		end
		table.sort(ups)
	end
	local bills = {}
	for i = #h.bills, math.max(1, #h.bills - 11), -1 do
		local b = h.bills[i]
		table.insert(bills, { t = b.t, day = b.day, kind = b.kind, label = b.label, amount = b.amount, paid = b.paid })
	end
	local loan = G.activeLoan(d)
	local hw = lid and h.housewarming[lid]
	return {
		slots = slots,
		storage = storage,
		storageCount = storageCount(h),
		fridge = h.fridge,
		upgrades = ups,
		bills = bills,
		loan = if loan then { listingId = loan.listingId, remaining = loan.remaining, daily = loan.daily, missed = loan.missed or 0 } else false,
		decor = G.homeDecor(d),
		comfort = G.homeComfort(d),
		value = G.homeValue(d.home, d),
		furnitureValue = G.furnitureValue(d),
		utilityPerDay = if d.home then (G.UTILITY_PER_DAY[d.home.tier or 1] or 0) else 0,
		housewarming = if hw then { done = hw.done, count = hw.count } else { done = false, count = 0 },
	}
end

-- Static-data checks for the housing tables (called from G.validate).
function G.validateHousing(bad: (string) -> ())
	for _, id in G.LISTING_ORDER do
		local l = G.LISTINGS[id]
		if l and not G.HOME_TIERS[l.tierKey or ""] then
			bad("listing " .. id .. " unknown tierKey")
		end
		if l and G.HOME_TIERS[l.tierKey or ""] and G.HOME_TIERS[l.tierKey].tier ~= l.tier then
			bad("listing " .. id .. " tier / tierKey mismatch")
		end
	end
	for _, id in G.FURNITURE_ORDER do
		local f = G.FURNITURE[id]
		if not G.FURNITURE_CATEGORIES[f.category] then
			bad("furniture " .. id .. " unknown category")
		elseif not GEN[f.category] then
			bad("furniture " .. id .. " no generator")
		end
		if not G.FURNITURE_STYLES[f.style] then
			bad("furniture " .. id .. " unknown style")
		end
		if not isFiniteNumber(f.price) or f.price <= 0 then
			bad("furniture " .. id .. " bad price")
		end
	end
	for _, c in G.FURNITURE_CATEGORY_ORDER do
		if #G.furnitureFor(c) == 0 then
			bad("furniture category " .. c .. " has no variants")
		end
	end
	for _, id in G.HOME_UPGRADE_ORDER do
		if not G.HOME_UPGRADES[id] then
			bad("HOME_UPGRADE_ORDER lists missing upgrade " .. id)
		end
	end
	for _, k in G.HOME_KIND_ORDER do
		if not G.HOME_KINDS[k] then
			bad("HOME_KIND_ORDER lists missing kind " .. k)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- NPCs (spawned at runtime next to their Destination part). kind: employer (job) | realtor |
-- banker | clubmd | friend. offset = { x, z } studs in the Destination part's local frame.
-------------------------------------------------------------------------------------------------
G.NPC_TALK_RADIUS = 16
G.NPC_ORDER = { "gs25_owner", "starbucks_mgr", "rider_mgr", "hoe_boss", "lifeguard_chief", "taxi_dispatcher", "realtor", "banker", "club_md", "minji", "junho" }
G.NPCS = {
	gs25_owner = { name = "김사장님", role = "GS25 광안리점 사장", kind = "employer", job = "gs25", dest = "GS25 광안리점", offset = { 1.4, -24.6 }, color = { 30, 160, 230 }, shirt = { 40, 150, 220 }, pants = { 40, 40, 50 } }, -- behind the counter (store build: register 2), faces the door
	starbucks_mgr = { name = "이점장", role = "스타벅스 광안리점 점장", kind = "employer", job = "starbucks", dest = "스타벅스 광안리점", offset = { 4, -3 }, color = { 0, 112, 74 }, shirt = { 20, 110, 70 }, pants = { 30, 30, 34 } },
	rider_mgr = { name = "박매니저", role = "배달 앱 매니저", kind = "employer", job = "rider", dest = "밀락더마켓", offset = { -5, -3 }, color = { 42, 193, 188 }, shirt = { 42, 193, 188 }, pants = { 50, 50, 60 } },
	hoe_boss = { name = "최사장님", role = "민락회타운 횟집 사장", kind = "employer", job = "hoe", dest = "민락회타운", offset = { 5, -3 }, color = { 230, 90, 60 }, shirt = { 235, 235, 235 }, pants = { 40, 50, 80 } },
	lifeguard_chief = { name = "강팀장", role = "광안리 수상구조대 팀장", kind = "employer", job = "lifeguard", dest = "광안리해수욕장 (중앙)", offset = { -6, -4 }, color = { 240, 70, 60 }, shirt = { 230, 50, 40 }, pants = { 240, 200, 40 } },
	taxi_dispatcher = { name = "배차 담당 윤기사", role = "광안운수 택시 배차", kind = "employer", job = "taxi_driver", dest = "광안리 만남의 광장", offset = { 8, -6 }, color = { 250, 180, 20 }, shirt = { 250, 190, 40 }, pants = { 40, 40, 40 } },
	realtor = { name = "정실장", role = "광안역 부동산 공인중개사", kind = "realtor", dest = "스타벅스 광안역점", offset = { -5, -3 }, color = { 120, 90, 200 }, shirt = { 110, 80, 190 }, pants = { 40, 40, 50 } },
	banker = { name = "한주임", role = "BNK부산은행 은행원", kind = "banker", dest = "BNK부산은행 광안동지점", offset = { 4, -3 }, color = { 214, 30, 60 }, shirt = { 210, 40, 60 }, pants = { 30, 30, 40 } },
	club_md = { name = "MD 태양", role = "CLUB OCEAN 광안 MD", kind = "clubmd", dest = "CLUB OCEAN 광안", offset = { 5, -3 }, color = { 170, 96, 255 }, shirt = { 20, 20, 24 }, pants = { 16, 16, 20 } },
	minji = { name = "민지", role = "친구", kind = "friend", contact = "minji", dest = "광안리 만남의 광장", offset = { -6, -3 }, color = { 255, 122, 162 }, shirt = { 255, 150, 180 }, pants = { 70, 90, 140 } },
	junho = { name = "준호", role = "친구", kind = "friend", contact = "junho", dest = "광안리 만남의 광장", offset = { -9, -1 }, color = { 88, 160, 255 }, shirt = { 70, 130, 230 }, pants = { 50, 50, 55 } },
}
G.FRIEND_CHAT_COOLDOWN = 600 -- seconds between happiness boosts from chatting with the same friend

-------------------------------------------------------------------------------------------------
-- Offers: texts that arrive over time. trigger = { after (seconds online this session),
-- noJob?, noHome?, hasJob?, minShifts?, night?, repeatEvery? (seconds; else once) }.
-- action (on "accept"): { type = "applyJob", job } | { type = "clubPass" } | { type = "waypoint",
-- dest } | { type = "meet", contact, dest }
-------------------------------------------------------------------------------------------------
G.OFFER_ORDER = { "welcome", "job_gs25", "home_hint", "job_cafe", "club_invite", "chimaek", "job_rider" }
G.OFFERS = {
	welcome = { contact = "minji", title = "광안리 도착!", text = "광안리 온 거 환영해 🌊 폰에 알바 앱이랑 부동산 앱 있지? 일해서 돈 모으고 집부터 구해 보자! 급여는 통장으로 들어와 🏦", trigger = { after = 8 } },
	job_gs25 = {
		contact = "boss",
		title = "알바 제안",
		text = "안녕하세요, GS25 광안리점 사장이에요. 알바 해볼래요? 시급 10,320원부터, 열심히 하면 매니저도 시켜 줄게요 😊",
		trigger = { after = 35, noJob = true },
		action = { type = "applyJob", job = "gs25" },
		acceptReply = "좋아요! 가게로 오면 알바 앱에서 '근무 시작'을 누르세요. 지도에 표시해 둘게요 📍",
		declineReply = "알겠어요. 생각 바뀌면 연락 줘요!",
	},
	home_hint = {
		contact = "realtor",
		title = "매물 안내",
		text = "안녕하세요, 광안역 부동산 정실장입니다. 아직 집이 없으시죠? 보증금 없는 고시원부터 오션뷰 펜트하우스까지 있어요. 사무실(스타벅스 광안역점 옆)로 오세요!",
		trigger = { after = 90, noHome = true },
		action = { type = "waypoint", dest = "스타벅스 광안역점" },
		acceptReply = "지도에 사무실 위치 찍어 드렸어요. 부동산 앱으로 바로 계약도 돼요 🏠",
		declineReply = "필요하실 때 연락 주세요!",
	},
	job_cafe = {
		contact = "cafe",
		title = "바리스타 모집",
		text = "스타벅스 광안리점 이점장입니다. 성실하다는 소문 들었어요! 바리스타 해 보실래요? 바다 보면서 일할 수 있어요 ☕",
		trigger = { after = 300, minShifts = 1 },
		action = { type = "applyJob", job = "starbucks" },
		acceptReply = "환영해요! 매장으로 와서 근무 시작하면 돼요.",
		declineReply = "아쉽네요. 언제든 연락 주세요!",
	},
	club_invite = {
		contact = "minji",
		title = "클럽 초대",
		text = "오늘 밤 CLUB OCEAN 갈래? 🎶 내가 MD 태양 오빠한테 말해 둘게, 입장료 없이 들어갈 수 있어!",
		trigger = { after = 420, night = true, repeatEvery = 2880 },
		action = { type = "clubPass" },
		acceptReply = "오케이! 게스트 리스트에 올려 놨어 😎 클럽 앞에서 태양 오빠한테 말 걸어!",
		declineReply = "ㅠㅠ 다음엔 꼭 가자!",
	},
	chimaek = {
		contact = "junho",
		title = "치맥 약속",
		text = "야 광안리 만남의 광장에서 치맥 콜? 🍗🍺 나 거기 있을게!",
		trigger = { after = 600, repeatEvery = 2400 },
		action = { type = "meet", contact = "junho", dest = "광안리 만남의 광장" },
		acceptReply = "ㄱㄱ 광장 오면 말 걸어!",
		declineReply = "ㅇㅋ 다음에~",
	},
	job_rider = {
		contact = "rider",
		title = "라이더 모집",
		text = "배달의광안 박매니저예요. 라이더 하실래요? 빨리 배달하면 팁도 있어요 🛵 (밀락더마켓 허브)",
		trigger = { after = 900, hasJob = true },
		action = { type = "applyJob", job = "rider" },
		acceptReply = "등록 완료! 밀락더마켓 허브로 오세요.",
		declineReply = "넵, 필요하면 연락 주세요!",
	},
}

-- Is the offer's trigger satisfied? state = { online, hasJob, hasHome, shifts, night, lastSent }
function G.offerDue(offerId: string, state: any, now: number): boolean
	local o = G.OFFERS[offerId]
	if not o then
		return false
	end
	local t = o.trigger or {}
	if (state.online or 0) < (t.after or 0) then
		return false
	end
	if t.noJob and state.hasJob then
		return false
	end
	if t.hasJob and not state.hasJob then
		return false
	end
	if t.noHome and state.hasHome then
		return false
	end
	if t.minShifts and (state.shifts or 0) < t.minShifts then
		return false
	end
	if t.night and not state.night then
		return false
	end
	local last = state.lastSent
	if last then
		if not t.repeatEvery then
			return false
		end
		if now - last < t.repeatEvery then
			return false
		end
	end
	return true
end

-- Legacy quest data (the quest system was folded into jobs / offers); kept empty for old clients.
G.QUESTS = {}
G.QUEST_ORDER = {}
G.MESSAGES = {}
G.DEST = {
	plaza = "광안리 만남의 광장",
	beach = "광안리해수욕장 (중앙)",
	gym = "광안 휘트니스 24 (헬스장)",
	salon = "헤어살롱 & 편집숍",
	hoetown = "민락회타운",
	gs25 = "GS25 광안리점",
	club = "CLUB OCEAN 광안",
	millac = "밀락더마켓",
	realtor = "스타벅스 광안역점",
	bank = "BNK부산은행 광안동지점",
}

-------------------------------------------------------------------------------------------------
-- Validation of the static data (unit tests + once by the server at start).
-------------------------------------------------------------------------------------------------
function G.validate(): { string }
	local problems = {}
	local function bad(msg: string)
		table.insert(problems, msg)
	end
	for _, id in G.JOB_ORDER do
		local j = G.JOBS[id]
		if not j then
			bad("JOB_ORDER lists missing job " .. id)
			continue
		end
		if j.npc and not G.NPCS[j.npc] then
			bad("job " .. id .. " unknown npc")
		end
		if j.contact and not G.CONTACTS[j.contact] then
			bad("job " .. id .. " unknown contact")
		end
		for i, l in j.levels do
			if i > 1 and l.xp <= j.levels[i - 1].xp then
				bad("job " .. id .. " levels xp not increasing")
			end
		end
		for _, t in (j.tasks or j.cycle or {}) do
			if t.point and not (j.points and j.points[t.point]) then
				bad("job " .. id .. " unknown point " .. t.point)
			end
			if t.kind == "choice" and (not t.choices or not t.choices[t.answer or 0]) then
				bad("job " .. id .. " choice without answer")
			end
			if type(t.pool) == "string" and type(G[t.pool]) ~= "table" then
				bad("job " .. id .. " unknown pool " .. t.pool)
			end
		end
	end
	for _, id in G.LISTING_ORDER do
		if not G.LISTINGS[id] then
			bad("LISTING_ORDER lists missing listing " .. id)
		end
	end
	G.validateHousing(bad)
	for _, id in G.NPC_ORDER do
		local n = G.NPCS[id]
		if not n then
			bad("NPC_ORDER lists missing npc " .. id)
		elseif n.job and not G.JOBS[n.job] then
			bad("npc " .. id .. " unknown job")
		end
	end
	for cid, c in G.CONTACTS do
		if c.npc and not G.NPCS[c.npc] then
			bad("contact " .. cid .. " unknown npc")
		end
	end
	for _, id in G.OFFER_ORDER do
		local o = G.OFFERS[id]
		if not o then
			bad("OFFER_ORDER lists missing offer " .. id)
		elseif not G.CONTACTS[o.contact] then
			bad("offer " .. id .. " unknown contact")
		elseif o.action and o.action.type == "applyJob" and not G.JOBS[o.action.job] then
			bad("offer " .. id .. " unknown job")
		end
	end
	for id, it in G.ITEMS do
		if not isFiniteNumber(it.price) or it.price < 0 then
			bad("item " .. id .. " bad price")
		end
		if it.shop and not G.SHOPS[it.shop] then
			bad("item " .. id .. " unknown shop")
		end
		if not it.shop and not it.nearDest and not it.phone then
			bad("item " .. id .. " cannot be bought anywhere")
		end
		if it.effect and it.effect.buff and not G.BUFFS[it.effect.buff] then
			bad("item " .. id .. " unknown buff")
		end
	end
	for id, s in G.SALON do
		if s.shape and not G.HAIR_SHAPES[s.shape] then
			bad("salon " .. id .. " unknown shape")
		end
	end
	if G.validateBank then
		G.validateBank(bad)
	end
	return problems
end

-------------------------------------------------------------------------------------------------
-- Bank (owner: money): 송금 (player -> player, 계좌이체), 송금 요청, 현금 주기 (in person), ATM /
-- 은행 창구 (withdraw / deposit with fees), day-grouped statements. Server: GwangalliGameplay/Bank.luau;
-- client: StarterPlayerScripts/GwangalliFeatures/*; contract: docs/features_contract.md §3.
--
-- EXTRA REMOTES (created by Bank.luau inside GwangalliRemotes):
--   BankRequest RemoteFunction client -> server (op, payload?) -> {ok, code, message, ...}
--     summary | recipients | quote {to, amount} | transfer {to, amount, memo?, preset?, rid, requestId?}
--     request {to, amount, memo?, preset?, rid} | requests | offers | requestAnswer {requestId, accept = false}
--     statement {account?} | atmOpen {atmId} | atm {atmId, direction = "withdraw"|"deposit", amount, rid}
--     cashOffer {to, amount, rid} | cashAnswer {offerId, accept} | cashCancel {offerId} | block {userId, on}
--   BankEvent   RemoteEvent server -> client {kind = "received"|"sent"|"request"|"requestAnswered"|
--               "cashOffer"|"cashResolved"|"atm", ...}
-- Amounts are integer won; every limit / fee is decided on the server from the tables below.
-- Ledger entries written by the bank carry meta fields: kind (BANK_KINDS), peer (display name),
-- peerId (UserId), memo, fee, ref (transaction id, the same on both sides), place (ATM name).
-------------------------------------------------------------------------------------------------
G.Remote.BankRequest = "BankRequest"
G.Remote.BankEvent = "BankEvent"
G.Tags.ATM = "GwangalliATM"
G.Attr.AtmKind = "AtmKind"
G.Attr.AtmId = "GwangalliAtmId"

-- 입출금 알림 thread (messages) -- a service contact that is not in the dial list
G.CONTACTS.bnk = { name = "BNK부산은행", role = "입출금 알림", icon = "🏦", color = { 214, 30, 60 }, kind = "service" }
-- 전투·범죄·경찰: 광안지구대 texts (fines, escapes); a service thread, not in the dial list
G.CONTACTS.police = { name = "광안지구대", role = "경찰", icon = "🚓", color = { 70, 120, 255 }, kind = "service" }

G.BANK = {
	bankName = "BNK부산은행",
	account = "110-***-4567",
	minTransfer = 1000,
	maxTransfer = 1000000, -- per transfer
	dailyLimit = 3000000, -- 1일 이체한도 (송금 + 현금 주기)
	limitedDaily = 50000, -- 한도제한계좌: a new account (under limitedSeconds of play) sends at most this a day
	limitedSeconds = 1800,
	fee = 0, -- 송금 수수료 면제
	nearbyRadius = 60, -- studs: "근처 사람"
	giveRadius = 12, -- studs: 현금 주기 (offer); acceptance allows giveRadius * giveSlack
	giveSlack = 1.6,
	giveMin = 1000,
	giveMax = 500000,
	offerTTL = 20, -- s a cash offer waits for an answer
	requestTTL = 300, -- s a money request stays open
	maxPendingOut = 3, -- open money requests a player may have sent
	maxPendingIn = 5, -- open money requests a player may receive
	maxOffersIn = 3,
	requestTargetCooldown = 20, -- s between two requests to the same player
	memoMaxChars = 20,
	recentMax = 8,
	atmReach = 14, -- studs from the ATM part for every ATM operation (the prompt is 8)
	atmPromptDistance = 8,
	atmDailyWithdraw = 3000000,
	nightFrom = 18, -- ATM night fees 18:00-09:00 (game clock)
	nightTo = 9,
	counterOpen = 9, -- 은행 창구 09:00-16:00 (game clock)
	counterClose = 16,
	kstOffset = 9 * 3600,
}

-- ATM kinds. fee = {day, night} per operation; units = the notes the machine takes / gives;
-- min = smallest withdrawal, minDeposit = smallest deposit.
G.ATM_KINDS = {
	bnk = { name = "BNK부산은행 ATM", short = "자행 ATM", own = true, fee = { 0, 0 }, withdrawUnit = 10000, depositUnit = 1000, maxWithdraw = 1000000, maxDeposit = 1000000, min = 10000, minDeposit = 1000 },
	cvs = { name = "편의점 ATM", short = "편의점 ATM", fee = { 900, 1300 }, withdrawUnit = 10000, depositUnit = 1000, maxWithdraw = 700000, maxDeposit = 1000000, min = 10000, minDeposit = 1000 },
	other = { name = "타행 ATM", short = "타행 ATM", fee = { 500, 1000 }, withdrawUnit = 10000, depositUnit = 1000, maxWithdraw = 700000, maxDeposit = 1000000, min = 10000, minDeposit = 1000 },
	counter = { name = "BNK부산은행 창구", short = "은행 창구", own = true, counter = true, fee = { 0, 0 }, withdrawUnit = 1, depositUnit = 1, maxWithdraw = 10000000, maxDeposit = 10000000, min = 1, minDeposit = 1 },
}

G.BANK_KINDS = { p2p_out = true, p2p_in = true, cash_out = true, cash_in = true, atm_wd = true, atm_dep = true, fee = true, refund = true }

-- memo presets (sent as ids: no text filtering needed)
G.BANK_PRESET_ORDER = { "rice", "coffee", "taxi", "club", "split", "thanks", "allowance", "rent" }
G.BANK_PRESETS = {
	rice = "밥값 🍚",
	coffee = "커피값 ☕",
	taxi = "택시비 🚕",
	club = "클럽 🎶",
	split = "N빵 🧾",
	thanks = "고마워 💛",
	allowance = "용돈 💸",
	rent = "월세 🏠",
}

G.BANK_MESSAGES = {
	ok = "완료됐어요",
	bad = "잘못된 요청이에요",
	amount = "금액을 확인해 주세요",
	min = "최소 1,000원부터 보낼 수 있어요",
	max = "한 번에 최대 100만원까지 보낼 수 있어요",
	unit = "이 기기에서는 그 단위로 거래할 수 없어요",
	insufficient = "통장 잔액이 부족해요",
	cash = "현금이 부족해요",
	daily = "오늘 이체 한도(300만원)를 넘어요",
	limited = "신규 계좌(한도제한계좌)는 하루 5만원까지 보낼 수 있어요",
	self = "나에게는 보낼 수 없어요",
	offline = "받는 분이 지금 이 서버에 없어요",
	loading = "정보를 불러오는 중이에요. 잠시 후 다시 시도해 주세요",
	busy = "처리 중이에요. 잠시만요",
	rate = "너무 빨라요. 잠시 후 다시 시도해 주세요",
	far = "너무 멀어요. 가까이 가서 다시 시도해 주세요",
	nosave = "저장 서버 연결이 불안정해서 지금은 돈을 주고받을 수 없어요",
	full = "받는 분 계좌에 더 넣을 수 없어요",
	closed = "은행 창구 영업시간(오전 9시~오후 4시)이 아니에요",
	expired = "이미 끝난 요청이에요",
	blocked = "상대방이 지금은 받지 않고 있어요",
	pending = "이미 보낸 요청이 있어요. 답을 기다려 주세요",
	tooMany = "대기 중인 요청이 너무 많아요",
	atmLimit = "오늘 ATM 출금 한도(300만원)를 넘어요",
	noatm = "ATM을 찾을 수 없어요",
	feeTooHigh = "수수료보다 큰 금액만 입금할 수 있어요",
	mismatch = "요청받은 금액과 달라요",
	dead = "지금은 할 수 없어요",
}

function G.bankMessage(code: string?): string
	return G.BANK_MESSAGES[code or "bad"] or G.BANK_MESSAGES.bad
end

-- Strict integer won from an untrusted value: a number (not NaN / inf), whole, lo <= v <= hi.
function G.bankInt(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	if v % 1 ~= 0 or v < lo or v > hi then
		return nil
	end
	return v
end

-- Real-world day in Korea (limits reset at KST midnight).
function G.bankKstDay(unix: number): number
	return math.floor((unix + G.BANK.kstOffset) / 86400)
end

function G.atmNight(clock: number?): boolean
	local c = if isFiniteNumber(clock) then (clock :: number) % 24 else 12
	return G.inClockWindow(c, G.BANK.nightFrom, G.BANK.nightTo)
end

function G.counterOpen(clock: number?): boolean
	local c = if isFiniteNumber(clock) then (clock :: number) % 24 else 12
	return c >= G.BANK.counterOpen and c < G.BANK.counterClose
end

-- Fee (won) for one ATM operation of `kind` at the game `clock`.
function G.atmFee(kind: string, clock: number?): number
	local k = G.ATM_KINDS[kind]
	if not k then
		return 0
	end
	return if G.atmNight(clock) then k.fee[2] else k.fee[1]
end

-- Checks one ATM / counter operation against the machine rules. Returns ok, code.
function G.atmCheck(kind: string, direction: string, amount: any, clock: number?): (boolean, string?)
	local k = G.ATM_KINDS[kind]
	if not k then
		return false, "noatm"
	end
	if direction ~= "withdraw" and direction ~= "deposit" then
		return false, "bad"
	end
	if k.counter and not G.counterOpen(clock) then
		return false, "closed"
	end
	local maxV = if direction == "withdraw" then k.maxWithdraw else k.maxDeposit
	local v = G.bankInt(amount, 1, G.MAX_MONEY)
	if not v then
		return false, "amount"
	end
	if v < (if direction == "withdraw" then k.min else (k.minDeposit or k.min)) then
		return false, "min"
	end
	if v > maxV then
		return false, "max"
	end
	local unit = if direction == "withdraw" then k.withdrawUnit else k.depositUnit
	if v % unit ~= 0 then
		return false, "unit"
	end
	if direction == "deposit" and v <= G.atmFee(kind, clock) then
		return false, "feeTooHigh"
	end
	return true, nil
end

-- Daily send limit for an account with `playSeconds` of play: limit, limited (한도제한계좌).
function G.bankDailyLimit(playSeconds: any): (number, boolean)
	local s = if isFiniteNumber(playSeconds) then playSeconds :: number else 0
	if s < G.BANK.limitedSeconds then
		return G.BANK.limitedDaily, true
	end
	return G.BANK.dailyLimit, false
end

-- Cleans ledger meta (whitelisted keys, clipped strings, integer numbers). Used by G.ledger and the
-- profile sanitizer.
function G.ledgerMeta(m: any): { [string]: any }
	local out: { [string]: any } = {}
	if type(m) ~= "table" then
		return out
	end
	if type(m.kind) == "string" and G.BANK_KINDS[m.kind] then
		out.kind = m.kind
	end
	if type(m.peer) == "string" and #m.peer > 0 and utf8.len(m.peer) then
		out.peer = G.clipText(m.peer, 40)
	end
	if isFiniteNumber(m.peerId) and m.peerId > 0 and m.peerId % 1 == 0 then
		out.peerId = m.peerId
	end
	if type(m.memo) == "string" and #m.memo > 0 and utf8.len(m.memo) then
		out.memo = G.clipText(m.memo, 80)
	end
	if isFiniteNumber(m.fee) and m.fee > 0 then
		out.fee = math.floor(m.fee)
	end
	if type(m.ref) == "string" and #m.ref > 0 and #m.ref <= 40 and string.match(m.ref, "^[%w%-_]+$") then
		out.ref = m.ref
	end
	if type(m.place) == "string" and #m.place > 0 and utf8.len(m.place) then
		out.place = G.clipText(m.place, 60)
	end
	return out
end

-- Cleans a user memo: trims, drops control characters, at most BANK.memoMaxChars characters.
-- Returns nil for an empty / invalid memo. (The server still text-filters it before anyone sees it.)
function G.bankCleanMemo(s: any): string?
	if type(s) ~= "string" or #s == 0 or #s > 200 or not utf8.len(s) then
		return nil
	end
	local chars = {}
	for _, cp in utf8.codes(s) do
		if cp >= 32 and cp ~= 127 and not (cp >= 0x200B and cp <= 0x200F) and not (cp >= 0x202A and cp <= 0x202E) then
			table.insert(chars, utf8.char(cp))
		end
		if #chars >= G.BANK.memoMaxChars then
			break
		end
	end
	local out = table.concat(chars)
	out = string.gsub(out, "^%s+", "")
	out = string.gsub(out, "%s+$", "")
	if out == "" then
		return nil
	end
	return out
end

-- The profile's banking record (daily counters, recent recipients). Rolls the day over.
function G.bankingOf(d: any, now: number): any
	local b = d.banking
	if type(b) ~= "table" then
		b = { day = 0, sent = 0, count = 0, atmDay = 0, atmOut = 0, recent = {} }
		d.banking = b
	end
	local day = G.bankKstDay(now)
	if b.day ~= day then
		b.day = day
		b.sent = 0
		b.count = 0
	end
	if b.atmDay ~= day then
		b.atmDay = day
		b.atmOut = 0
	end
	b.recent = if type(b.recent) == "table" then b.recent else {}
	return b
end

function G.sanitizeBanking(raw: any): any
	local b = { day = 0, sent = 0, count = 0, atmDay = 0, atmOut = 0, recent = {} }
	if type(raw) ~= "table" then
		return b
	end
	local function int0(v: any): number
		return if isFiniteNumber(v) and v >= 0 then math.floor(v) else 0
	end
	b.day = int0(raw.day)
	b.sent = math.min(int0(raw.sent), G.MAX_MONEY)
	b.count = math.min(int0(raw.count), 100000)
	b.atmDay = int0(raw.atmDay)
	b.atmOut = math.min(int0(raw.atmOut), G.MAX_MONEY)
	if type(raw.recent) == "table" then
		for _, r in raw.recent do
			if type(r) == "table" and isFiniteNumber(r.u) and r.u > 0 and r.u % 1 == 0 and type(r.n) == "string" and utf8.len(r.n) then
				table.insert(b.recent, { u = r.u, n = G.clipText(r.n, 40), t = int0(r.t), a = int0(r.a) })
				if #b.recent >= G.BANK.recentMax then
					break
				end
			end
		end
	end
	return b
end

function G.validateBank(bad: (string) -> ())
	for id, k in G.ATM_KINDS do
		if type(k.fee) ~= "table" or not isFiniteNumber(k.fee[1]) or not isFiniteNumber(k.fee[2]) then
			bad("atm kind " .. id .. " bad fee")
		end
		if k.maxWithdraw % k.withdrawUnit ~= 0 or k.maxDeposit % k.depositUnit ~= 0 then
			bad("atm kind " .. id .. " max not a multiple of its unit")
		end
	end
	for _, id in G.BANK_PRESET_ORDER do
		if not G.BANK_PRESETS[id] then
			bad("bank preset " .. id .. " missing")
		end
	end
	if G.BANK.minTransfer > G.BANK.maxTransfer or G.BANK.maxTransfer > G.BANK.dailyLimit then
		bad("bank limits out of order")
	end
end


-------------------------------------------------------------------------------------------------
-- Taxi call (owner: taxi_call): 광안콜택시 by phone call, a real drive along the traffic lanes,
-- card / cash payment, receipt, rating. Server: GwangalliGameplay/Taxi.luau (+ TaxiDispatch.luau);
-- client: StarterPlayerScripts/GwangalliFeatures/TaxiCall.luau (call screen) + TaxiRide.luau (card,
-- meter, payment, receipt, smooth car motion); contract: docs/features_contract.md §4.
--
-- EXTRA REMOTE (created by Taxi.luau inside GwangalliRemotes):
--   TaxiCall RemoteFunction client -> server (op, payload?) -> {ok, code?, message?, ...}
--     hello | quote {dest | x, z | nearby = true} | book {same} | setDest {dest} | cancel | board |
--     skip | pay {method = "card"|"cash"} | rate {rideId, stars 1..5} | state
--   TaxiState (existing RemoteEvent) gains state "paying" and the field job = {id, state, driver,
--   driverTitle, rating, car, color, plate, phone, destination, fare, lines, boarded, needDest,
--   pickup, dropoff, arriveAt, waitUntil, rideStart, rideEnd, skipAt, payUntil, freeCancelUntil,
--   cancelFee, model, serial, now} (times = workspace:GetServerTimeNow()); "done" carries receipt.
-- Taxi models (Workspace.GwangalliTaxis) carry TaxiPath ("x,y,z,t;..."), TaxiT0, TaxiSerial,
-- TaxiState, TaxiHazard, TaxiHonk / TaxiWave (counters), TaxiOwner, TaxiPlate, TaxiSpawnFade.
-------------------------------------------------------------------------------------------------
G.Remote.TaxiCall = "TaxiCall"

-------------------------------------------------------------------------------------------------
-- Health (owner: health): 피로도 (stat `fatigue`, lower is better) -> pay debuff -> 질병 -> 병원.
-- Server: GwangalliGameplay/Health.luau (ctx.health API for the other modules); pure helpers:
-- ReplicatedStorage.GwangalliHealthShared; client: StarterPlayerScripts/GwangalliHealth.client.luau;
-- venue: build/venues/hospital.luau (Destination "광안메디컬"); tuning guide: docs/HEALTH.md.
--
-- EXTRA REMOTES (created by Health.luau inside GwangalliRemotes):
--   HealthRequest RemoteFunction client -> server (op, payload?) -> {ok, code?, message?, ...}
--     status | treat | vitamin | checkup   (fees charged bank first, cash fallback; distance checked)
--   HealthEvent   RemoteEvent server -> client {kind = "clinic" (open the hospital UI, carries status)
--                 | "cured" | "vitamin" | "checkup" | "collapse" | "ill" | "status"}
-- ATTRIBUTES: Player.Fatigue (0..100), Player.Illness ("" | kind), Character.GwIll (bool: other
--   scripts scale WalkSpeed / sprint by G.HEALTH.illWalkSpeed), Character.GwTreating (bool),
--   Player.GwCollapse (bool while the ambulance sequence runs).
-- WORLD TAGS (CollectionService, built by venues/hospital.luau):
--   HospitalStaff   Model (static rig)  attributes Role = "doctor" | "nurse", Hospital = "gwangan"
--   HospitalPrompt  BasePart anchor with the ProximityPrompt  attribute Kind = "doctor" | "desk"
--   HospitalBed     Seat  attribute BedKind = "exam" (treatment bed) | "ward" (입원실, ambulance drop)
-------------------------------------------------------------------------------------------------
G.Remote.HealthRequest = "HealthRequest"
G.Remote.HealthEvent = "HealthEvent"
G.Attr.Fatigue = "Fatigue"
G.Attr.Illness = "Illness"
G.Attr.Ill = "GwIll"
G.Attr.Treating = "GwTreating"
G.Attr.Collapse = "GwCollapse"
G.Tags.HospitalStaff = "HospitalStaff"
G.Tags.HospitalPrompt = "HospitalPrompt"
G.Tags.HospitalBed = "HospitalBed"

G.HEALTH = {
	place = "광안메디컬", -- Destination DisplayName of the clinic
	name = "광안 메디컬 의원",
	reach = 14, -- studs from a HospitalPrompt anchor to use it / from the exam bed for the treatment
	-- 피로도 curve (seconds of real time per +1 / -1)
	fatigue = {
		workSecondsDay = 32, -- on shift: +1 per this many seconds (06:00-22:00 game time)
		workSecondsNight = 22, -- on shift at night (22:00-06:00): faster
		taskBonus = 1.5, -- Health.onWork(player, "task") from the jobs module: extra per finished task
		taskBonusNight = 0.5, -- added to taskBonus at night
		restSeconds = 90, -- off shift: -1 per this many seconds
		sleep = 70, -- Life.sleep at home: fatigue -70 (never below 0)
		meal = 6, -- a meal / 카페 interaction (Life hooks: 치맥, home meals via ctx.health.rest)
		vitamin = 40, -- 영양주사
		cured = 50, -- after a treatment
		collapse = 50, -- after the ambulance ride
	},
	-- pay multiplier tiers by fatigue (checked top down; `ill` wins over everything)
	tiers = {
		{ min = 90, mult = 0.2, label = "탈진", color = { 255, 90, 95 } },
		{ min = 75, mult = 0.4, label = "과로", color = { 255, 120, 70 } },
		{ min = 50, mult = 0.7, label = "피로", color = { 255, 176, 32 } },
		{ min = 0, mult = 1.0, label = "", color = { 61, 220, 132 } },
	},
	illMult = 0.2,
	illWalkSpeed = 0.7, -- WalkSpeed factor while ill (server sets the base, HUD sprint x this too)
	illHappinessEvery = 60, -- seconds per -1 행복 while ill
	coughEvery = { 14, 22 }, -- client: seconds between cough / shiver emotes while ill
	friendMessageAfter = 45, -- s after falling ill: a friend texts "병원 가 봐…"
	collapseAfter = 600, -- s of being ill (online) before 쓰러짐 + ambulance
	ambulanceFee = 20000, -- added to the illness fee x ambulanceFeeMult
	ambulanceFeeMult = 1.5,
	-- 질병 risk: accumulates only while WORKING with fatigue >= riskFrom; ill when >= riskThreshold
	risk = {
		from = 80, -- fatigue needed before any risk accrues
		perSecond = 1 / 30, -- base: +1 risk per 30 s of work at fatigue 80 ...
		slopePer5 = 1, -- ... +1 more per 30 s for every 5 fatigue above 80 (90 -> 3/30 s, 100 -> 5/30 s)
		taskBonus = 2, -- Health.onWork adds this much risk per task while fatigue >= from
		decayPerSecond = 1 / 60, -- off the danger zone: -1 risk per 60 s
		threshold = 25,
	},
	-- illness kinds (fee = 진료비, paid bank first then cash)
	KIND_ORDER = { "cold", "ache", "gastritis", "burnout" },
	KINDS = {
		cold = { name = "감기", icon = "🤧", fee = 15000, desc = "콧물에 기침까지… 밤샘 근무가 문제였어요.", cure = "주사 한 방 + 감기약 3일분", emote = "cough" },
		ache = { name = "몸살", icon = "🥵", fee = 25000, desc = "온몸이 쑤시고 열이 나요. 너무 무리했어요.", cure = "해열 주사 + 근육이완제", emote = "shiver" },
		gastritis = { name = "위염", icon = "🤢", fee = 35000, desc = "식사를 거르고 일만 했죠? 속이 쓰려요.", cure = "위장약 처방 + 수액", emote = "cough" },
		burnout = { name = "번아웃", icon = "😵‍💫", fee = 45000, desc = "몸도 마음도 다 타버렸어요. 쉬어야 해요.", cure = "영양 수액 + 휴식 처방", emote = "shiver" },
	},
	services = {
		vitamin = { name = "영양주사", icon = "💉", fee = 30000, desc = "피로도 -40 · 지금 바로 개운하게" },
		checkup = { name = "건강검진", icon = "🩺", fee = 10000, desc = "피로도·질병 위험도·능력치 리포트" },
	},
	-- 쓰러짐 / 병원 copy
	messages = {
		friend = "야 너 목소리 왜 그래… 아프면 광안메디컬 가 봐. 뒷골목 GS25 옆에 있어 🏥",
		ambulance = "쓰러졌어요… 🚑 구급차가 광안메디컬로 옮겼어요",
	},
}

-------------------------------------------------------------------------------------------------
-- Extension: GwangalliHomesShared (내집마련 인테리어: room themes, extra furniture, rotation). It
-- receives G and never requires this module (no cycle); a missing / failing module leaves G as is.
-------------------------------------------------------------------------------------------------
do
	local scr: any = script
	local ext = if typeof(scr) == "Instance" and scr.Parent then scr.Parent:FindFirstChild("GwangalliHomesShared") else nil
	if ext and ext:IsA("ModuleScript") then
		local ok, m = pcall(require, ext)
		if ok and type(m) == "table" and type(m.extend) == "function" then
			local ok2, err = pcall(m.extend, G)
			if not ok2 then
				warn("[GwangalliGameplayShared] GwangalliHomesShared.extend failed: " .. tostring(err))
			end
		elseif not ok then
			warn("[GwangalliGameplayShared] GwangalliHomesShared failed to load: " .. tostring(m))
		end
	end
end

return G
