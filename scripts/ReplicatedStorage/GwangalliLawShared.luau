-- GwangalliLawShared (owner: law): the contract of 광안리 치안 — crimes, 수배 (wanted stars), the police
-- (NPC officers / patrol cars / roadblocks), arrests and the 광안지구대 유치장, the player police job
-- (경찰 직업 패스) and the crime careers (소범죄 / 조직 범죄). Pure at require time (no instances, no
-- yields): the server (ServerScriptService.GwangalliGameplay.Law) and the clients
-- (StarterPlayerScripts.GwangalliLaw) read the same numbers, and Lune / luau-web tests can load it.
--
-- WANTED is server-authoritative (Law.luau). The player attributes it writes:
--   GwangalliWanted (0..5, the stars; MindUI / People / the HUD read it), GwangalliWantedUntil (legacy),
--   Wanted (mirror, read by Housing / GwangalliTravel: no hiding at home / fast travel while wanted),
--   PoliceChase (true while an officer sees you or chases), Arrested (true from the cuffs to release),
--   LawSeen (server time an officer last saw you), LawSearch (0..1: how close the stars are to dropping),
--   LawJail (server time the sentence ends, 0 = free), LawCuffed (true while cuffed),
--   LawCop (true while on police duty), LawCopRank (rank title), LawCrimeLevel (1..), LawRecord (전과 count).
--
-- REMOTES (ReplicatedStorage.GwangalliLaw): Action (RemoteFunction, client -> server (op, payload) ->
-- result {ok, err?, ...}), Event (RemoteEvent, server -> client {kind = ...}). See Law.luau for ops.

local Law = {}

Law.VERSION = 1
Law.Folder = "GwangalliLaw"
Law.Remote = { Action = "Action", Event = "Event" }
Law.Attr = {
	Wanted = "GwangalliWanted",
	WantedUntil = "GwangalliWantedUntil",
	LegacyWanted = "Wanted",
	Chase = "PoliceChase",
	Arrested = "Arrested",
	Seen = "LawSeen",
	Search = "LawSearch",
	Jail = "LawJail",
	Cuffed = "LawCuffed",
	Cop = "LawCop",
	CopRank = "LawCopRank",
	CrimeLevel = "LawCrimeLevel",
	Record = "LawRecord",
	Active = "GwangalliLawActive", -- workspace: the Law module runs (the street-life Mind leaves the police to it)
}
Law.MAX_STARS = 5

-------------------------------------------------------------------------------------------------
-- Crimes. stars = added to the current level (capped), min = the level is at least this,
-- report = needs a witness / victim report before the police know (seconds until the call when nobody
-- reports earlier: {min, max}; nil = the police know at once, e.g. an officer was hit), sev = severity
-- points for the sentence, fine = 원 added to the episode's fine, label = 전과 text.
-------------------------------------------------------------------------------------------------
Law.CRIMES = {
	-- street (the Mind conversation / bumps)
	insult_police = { stars = 1, sev = 1, fine = 20000, label = "공무원 모욕" },
	threat = { stars = 1, sev = 1, fine = 30000, label = "협박", report = { 6, 14 } },
	shove = { stars = 1, sev = 1, fine = 20000, label = "폭행 (밀침)", report = { 8, 18 } },
	assault = { stars = 1, min = 1, sev = 2, fine = 50000, label = "폭행", report = { 4, 12 } },
	kill = { stars = 2, min = 3, sev = 6, fine = 400000, label = "폭행치사 (사람이 쓰러짐)", report = { 1, 4 } },
	assault_police = { stars = 2, min = 2, sev = 4, fine = 150000, label = "공무집행방해 (경찰 폭행)" },
	bribe = { stars = 1, sev = 2, fine = 50000, label = "뇌물 공여" },
	flee = { stars = 1, sev = 1, fine = 40000, label = "도주" },
	resist = { stars = 1, sev = 2, fine = 60000, label = "체포 불응" },
	bumps = { stars = 1, sev = 1, fine = 20000, label = "난동", report = { 6, 16 } },
	-- petty crimes (Law.SMALL)
	shoplift = { stars = 1, sev = 1, fine = 30000, label = "절도 (편의점)", report = { 3, 10 } },
	pickpocket = { stars = 1, sev = 1, fine = 40000, label = "소매치기", report = { 5, 14 } },
	bike_theft = { stars = 1, sev = 1, fine = 30000, label = "자전거 절도", report = { 10, 24 } },
	car_theft = { stars = 1, min = 1, sev = 2, fine = 80000, label = "차량 절도", report = { 12, 30 } },
	robbery = { stars = 2, min = 2, sev = 3, fine = 150000, label = "강도 (상점)", report = { 4, 9 } },
	contraband = { stars = 2, min = 2, sev = 3, fine = 120000, label = "불법 운송" },
	-- organised crime (Law.BIG)
	heist = { stars = 4, min = 4, sev = 6, fine = 500000, label = "특수절도 (금고)" },
	car_ring = { stars = 3, min = 3, sev = 5, fine = 300000, label = "고급 차량 탈취" },
	smuggling = { stars = 3, min = 3, sev = 5, fine = 300000, label = "밀수" },
	turf = { stars = 3, min = 3, sev = 4, fine = 200000, label = "조직 간 충돌" },
	-- driving
	reckless = { stars = 1, sev = 1, fine = 30000, label = "난폭 운전", report = { 6, 14 } },
	ram_police = { stars = 2, min = 2, sev = 3, fine = 150000, label = "경찰차 충돌" },
}

-------------------------------------------------------------------------------------------------
-- The police by wanted level. foot = officers on foot, cars = patrol cars (2 officers each), roadblocks
-- = road closures ahead of a fleeing car, checkpoint = officers stopping cars on the main roads.
-- Each tier also tunes how GOOD the officers are (the AI is meant to be beatable at 1-2 stars and
-- tough at 5): sight (studs), fov (degrees, full cone), react (seconds from first glimpse to "saw you"),
-- run (studs/s; the player runs 16, sprints 24), burst (extra speed when close, seconds), repath (s
-- between route refreshes), wrongTurn (chance at a junction to take a wrong branch while chasing a
-- last-seen spot), hesitate (chance to stall at an obstacle / alley step for 0.6-1.4 s), search
-- (seconds out of sight before a star drops), radio (seconds the dispatcher knows the exact position
-- after a fresh report: officers head for the reported spot, not the live position, once it expires).
-------------------------------------------------------------------------------------------------
Law.TIERS = {
	[1] = { foot = 2, cars = 0, roadblocks = 0, checkpoint = false, sight = 56, fov = 120, react = 0.9, run = 15.2, burst = 1.6, repath = 1.3, wrongTurn = 0.22, hesitate = 0.2, search = 26, radio = 3, carSpeed = 1.15, label = "근처 경찰 출동" },
	[2] = { foot = 2, cars = 1, roadblocks = 0, checkpoint = false, sight = 62, fov = 130, react = 0.7, run = 15.8, burst = 2.0, repath = 1.1, wrongTurn = 0.16, hesitate = 0.15, search = 34, radio = 4, carSpeed = 1.25, label = "순찰차 출동" },
	[3] = { foot = 2, cars = 2, roadblocks = 0, checkpoint = false, sight = 70, fov = 140, react = 0.55, run = 16.4, burst = 2.4, repath = 0.95, wrongTurn = 0.11, hesitate = 0.1, search = 42, radio = 5, carSpeed = 1.35, label = "순찰차 여러 대 · 도로 추격" },
	[4] = { foot = 3, cars = 3, roadblocks = 1, checkpoint = true, sight = 78, fov = 150, react = 0.42, run = 17.0, burst = 2.8, repath = 0.8, wrongTurn = 0.07, hesitate = 0.07, search = 52, radio = 6, carSpeed = 1.45, label = "경찰 증원 · 검문 · 도로 차단" },
	[5] = { foot = 4, cars = 4, roadblocks = 2, checkpoint = true, sight = 86, fov = 160, react = 0.32, run = 17.6, burst = 3.2, repath = 0.7, wrongTurn = 0.04, hesitate = 0.05, search = 62, radio = 8, carSpeed = 1.55, label = "특별 수사대 · 주요 도로 봉쇄" },
}
Law.MAX_OFFICERS = 22 -- server-wide NPC officers (on foot + patrol car crews)
Law.MAX_CARS = 8 -- server-wide patrol cars (incl. roadblock cars)
Law.SPAWN_RING = { 70, 130 } -- studs from the reported spot, out of the suspect's sight
Law.CAR_SPAWN = { 260, 460 } -- road distance up the lanes before the car appears
Law.ORDER_RANGE = 10 -- "거기 서!" range
Law.GRAB_RANGE = 3.4 -- subdue attempt range
Law.LOST_FAR = 160 -- an officer this far from the case and the suspect gives up and leaves
Law.STOP_GRACE = 6 -- seconds a stopped (1-star) suspect has to comply before it counts as fleeing
Law.ESCAPE_BONUS = { 1500, 3000, 6000, 12000, 25000 } -- nothing paid: only the progress metric / goals text
Law.WANTED_FLOOR_DECAY = 0.35 -- multiplier on `search` once the police lost every trace (no officer near)

-- grabbing a running suspect: the chance one grab works (a stopped / slow suspect is always caught)
function Law.grabChance(stars: number, suspectSpeed: number, inCar: boolean): number
	if inCar then
		return if suspectSpeed < 4 then 0.85 else 0
	end
	if suspectSpeed < 3 then
		return 1
	end
	local t = Law.TIERS[math.clamp(stars, 1, 5)]
	local base = 0.28 + 0.07 * (stars - 1)
	if suspectSpeed > 20 then
		base *= 0.55 -- sprinting
	end
	return math.clamp(base * (t.run / 16), 0.1, 0.75)
end

-------------------------------------------------------------------------------------------------
-- Sentences (유치장). The episode's severity points pick the band; repeat offenders sit a bit longer;
-- bail (보석금) lets you out early. Seconds are real time and deliberately short (the game should not
-- lock anyone out for long).
-------------------------------------------------------------------------------------------------
Law.SENTENCE = {
	{ upTo = 2, seconds = 45, label = "가벼운 범죄", bail = 20000 },
	{ upTo = 5, seconds = 90, label = "중간 범죄", bail = 60000 },
	{ upTo = 9, seconds = 150, label = "무거운 범죄", bail = 180000 },
	{ upTo = math.huge, seconds = 240, label = "대형 범죄", bail = 450000 },
}
Law.REPEAT_PER = 0.12 -- +12% per prior arrest in the last game week (max +60%)
Law.JAIL_MIN = 30
Law.JAIL_MAX = 300
Law.JAIL_GAME_CUT = 6 -- seconds off per won cell mini-game (max 3 a stay)
Law.JAIL_WORKOUT_CUT = 3 -- seconds off per push-up set (max 4 a stay)
Law.FINE_CAP = 1000000
Law.SURRENDER_MULT = 0.7 -- hands up / gave yourself in
Law.FORCED_MULT = 1.25 -- tackled while running / in a car chase

function Law.sentenceFor(sev: number, priors: number): (number, any)
	local band = Law.SENTENCE[#Law.SENTENCE]
	for _, b in Law.SENTENCE do
		if sev <= b.upTo then
			band = b
			break
		end
	end
	local mult = 1 + math.min(0.6, Law.REPEAT_PER * math.max(0, priors))
	return math.clamp(math.floor(band.seconds * mult + 0.5), Law.JAIL_MIN, Law.JAIL_MAX), band
end

function Law.bailFor(sev: number, secondsLeft: number, total: number): number
	local _, band = Law.sentenceFor(sev, 0)
	local share = math.clamp(secondsLeft / math.max(1, total), 0, 1)
	return math.max(5000, math.floor(band.bail * (0.35 + 0.65 * share) / 1000 + 0.5) * 1000)
end

-------------------------------------------------------------------------------------------------
-- Player police job (경찰 직업 패스). PASS_ID = 0: no game pass in this build (anyone may join the force
-- for testing; a live game sets the pass id). Ranks by XP; pay per legit arrest / ticket / patrol.
-- Arrests are only legal against a player with active stars, or with a reported, unpunished crime
-- (Law.WARRANT_WINDOW); anything else is a FALSE ARREST: reputation down, and FALSE_LOCK false arrests
-- inside FALSE_WINDOW lock the arrest tools for LOCK_SECONDS. Reputation under REP_SUSPEND suspends duty.
-------------------------------------------------------------------------------------------------
Law.POLICE_PASS_ID = 0
Law.MAFIA_PASS_ID = 0
Law.WARRANT_WINDOW = 600 -- seconds a reported crime stays arrestable after the stars are gone
Law.FALSE_WINDOW = 1200
Law.FALSE_LOCK = 3
Law.LOCK_SECONDS = 600
Law.REP_START = 60
Law.REP_SUSPEND = 15
Law.COP_RANKS = {
	{ xp = 0, title = "순경", pay = 1.0 },
	{ xp = 150, title = "경장", pay = 1.12 },
	{ xp = 420, title = "경사", pay = 1.25 },
	{ xp = 900, title = "경위", pay = 1.4 },
	{ xp = 1700, title = "경감", pay = 1.6 },
	{ xp = 3000, title = "경정", pay = 1.85 },
}
Law.COP_PAY = {
	arrest = 9000, -- + per star
	arrestStar = 4000,
	npcArrest = 6000,
	ticket = 3000,
	patrolPoint = 900,
	handover = 2500, -- walked / drove the suspect to the 지구대 yourself (vs. 자동 이송)
	duty = 700, -- per 2 minutes on duty with at least one patrol point or call
}
Law.COP_XP = { arrest = 40, arrestStar = 12, npcArrest = 25, ticket = 10, patrolPoint = 4, handover = 10, lookup = 1, falseArrest = -30 }
Law.CUFF_RANGE = 7
Law.HANDOVER_RANGE = 32 -- studs from the 지구대 door to hand a suspect over yourself
Law.AUTO_TRANSFER_AFTER = 15 -- seconds cuffed before the "자동 이송" button works
Law.ESCORT_RANGE = 26 -- a cuffed suspect follows the cop; farther than this the escort breaks (auto transfer)

function Law.copRank(xp: number): (number, any, any?)
	local idx = 1
	for i, r in Law.COP_RANKS do
		if xp >= r.xp then
			idx = i
		end
	end
	return idx, Law.COP_RANKS[idx], Law.COP_RANKS[idx + 1]
end

-------------------------------------------------------------------------------------------------
-- Crime careers. Crime XP from successful crimes; levels unlock new crimes. The "big" crimes (조직
--범죄) need the 조직 직업 (MAFIA_PASS_ID) OR crime level ORG_LEVEL plus enough 조직 신뢰; they take
-- long preparation, fail often and pay well — never a plain money multiplier (no pay-to-win: a pass
-- only opens the door, the payout and the risk are the same for everybody).
-------------------------------------------------------------------------------------------------
Law.CRIME_LEVELS = {
	{ xp = 0, title = "동네 양아치" },
	{ xp = 120, title = "좀도둑" },
	{ xp = 320, title = "꾼" },
	{ xp = 650, title = "전문털이범" },
	{ xp = 1100, title = "조직 수습" },
	{ xp = 1800, title = "조직원" },
	{ xp = 2800, title = "행동대장" },
}
Law.ORG_LEVEL = 5

function Law.crimeLevel(xp: number): (number, any, any?)
	local idx = 1
	for i, r in Law.CRIME_LEVELS do
		if xp >= r.xp then
			idx = i
		end
	end
	return idx, Law.CRIME_LEVELS[idx], Law.CRIME_LEVELS[idx + 1]
end

-- Petty crimes: anyone. pay {min, max} 원 (cash), xp, level = crime level needed, cool = seconds before
-- the same player may try this kind again, base = success chance before the situation (watchers,
-- the target, the night), hold = seconds of the action, risk text for the UI.
Law.SMALL = {
	shoplift = { label = "편의점 슬쩍하기", icon = "🧃", pay = { 2500, 8000 }, xp = 14, level = 1, cool = 90, base = 0.72, hold = 2.2, crime = "shoplift", risk = "점원·CCTV에 걸리면 1성 수배" },
	pickpocket = { label = "소매치기", icon = "👛", pay = { 3000, 15000 }, xp = 18, level = 1, cool = 60, base = 0.62, hold = 1.6, crime = "pickpocket", risk = "들키면 신고 + 주변 시민 반응" },
	bike_theft = { label = "자전거 훔치기", icon = "🚲", pay = { 9000, 18000 }, xp = 20, level = 2, cool = 180, base = 0.7, hold = 5, crime = "bike_theft", risk = "자물쇠 따는 동안 목격되면 신고" },
	car_theft = { label = "차량 절도", icon = "🚗", pay = { 0, 0 }, xp = 30, level = 2, cool = 120, base = 0.55, hold = 6, crime = "car_theft", risk = "경보 · 신고 · 추격" },
	chop = { label = "훔친 차 폐차장 넘기기", icon = "🔧", pay = { 25000, 60000 }, xp = 25, level = 2, cool = 300, base = 1, hold = 3, crime = nil, risk = "추적 중이면 못 넘김" },
	robbery = { label = "작은 상점 털기", icon = "💰", pay = { 22000, 55000 }, xp = 45, level = 3, cool = 420, base = 0.8, hold = 8, crime = "robbery", risk = "곧바로 2성 · 신고 확실" },
	contraband = { label = "불법 배달", icon = "📦", pay = { 30000, 52000 }, xp = 40, level = 2, cool = 360, base = 1, hold = 1.2, crime = "contraband", risk = "검문에 걸리면 2성 + 압수" },
}
Law.SMALL_ORDER = { "shoplift", "pickpocket", "bike_theft", "car_theft", "chop", "contraband", "robbery" }
Law.CONFISCATE = 0.5 -- caught: this share of the crime money made since the last arrest is seized

-- Organised crime. steps = preparation (each a small mission), then the job; reward split among the crew.
Law.BIG = {
	vault = {
		label = "대형 금고 털이", icon = "🏦", crime = "heist", level = 5, cool = 3600, reward = { 320000, 620000 }, xp = 260,
		steps = {
			{ id = "scout", label = "은행 주변 정찰 (3곳)", kind = "visit", n = 3 },
			{ id = "tools", label = "드릴 · 장비 구입", kind = "buy", cost = 60000 },
			{ id = "car", label = "도주 차량 확보 (차량 절도)", kind = "steal_car" },
			{ id = "job", label = "금고 털기 (드릴 60초 버티기)", kind = "drill", seconds = 60 },
			{ id = "escape", label = "은신처까지 도주", kind = "escape" },
		},
	},
	luxury = {
		label = "고급 차량 탈취", icon = "🏎️", crime = "car_ring", level = 5, cool = 2400, reward = { 180000, 300000 }, xp = 180,
		steps = {
			{ id = "intel", label = "정보원에게 차량 위치 받기", kind = "talk" },
			{ id = "grab", label = "고급 차량 훔치기 (경보 해제 미니게임)", kind = "steal_marked" },
			{ id = "deliver", label = "민락항 컨테이너까지 운반", kind = "escape" },
		},
	},
	smuggle = {
		label = "대규모 밀수", icon = "🚢", crime = "smuggling", level = 6, cool = 3600, reward = { 260000, 480000 }, xp = 220, night = true,
		steps = {
			{ id = "boat", label = "민락항 밀수선 접선 (밤)", kind = "visit", n = 1 },
			{ id = "crates", label = "상자 4개 옮기기", kind = "carry", n = 4 },
			{ id = "drive", label = "트럭으로 창고 운반 (검문 피하기)", kind = "escape" },
		},
	},
	turf = {
		label = "조직 간 임무 (구역 다툼)", icon = "🕶️", crime = "turf", level = 6, cool = 1800, reward = { 120000, 220000 }, xp = 150,
		steps = {
			{ id = "meet", label = "행동대장 만나기", kind = "talk" },
			{ id = "take", label = "상대 조직 물건 빼앗기", kind = "steal_marked" },
			{ id = "back", label = "아지트로 복귀", kind = "escape" },
		},
	},
}
Law.BIG_ORDER = { "vault", "luxury", "smuggle", "turf" }

-------------------------------------------------------------------------------------------------
-- NPC incidents (the city has its own crime: more at night). Feed the NPC police and the player cops.
-------------------------------------------------------------------------------------------------
Law.INCIDENTS = {
	pickpocket = { label = "소매치기 신고", icon = "👛", flee = true, w = { day = 2, night = 3 } },
	fight = { label = "취객 싸움", icon = "🍺", flee = false, w = { day = 0.4, night = 4 } },
	shoplift = { label = "편의점 절도", icon = "🧃", flee = true, w = { day = 1.5, night = 2 } },
	vandal = { label = "기물 파손", icon = "🪧", flee = true, w = { day = 0.5, night = 2 } },
	noise = { label = "소음 민원", icon = "📢", flee = false, w = { day = 0.3, night = 2.5 } },
}
Law.INCIDENT_GAP = { day = { 150, 260 }, night = { 70, 150 } } -- seconds between NPC incidents
Law.PATROL = { day = { foot = 1, cars = 1 }, night = { foot = 2, cars = 2 } } -- idle patrol units

-------------------------------------------------------------------------------------------------
-- Lines (officers / dispatch / inmates). Pick with Law.pick(list, rnd, last) to avoid an immediate repeat.
-------------------------------------------------------------------------------------------------
Law.LINES = {
	dispatch = {
		"무전: {area} 일대 {crime} 신고 접수, 인근 순찰 바람.",
		"무전: {area}에서 {crime} 발생, 출동 부탁드립니다.",
		"무전: 신고 들어왔습니다. {area}, {crime}. 용의자 인상착의 확인 중.",
	},
	arrive = { "여기가 신고 장소인가…", "음, 어디 갔지?", "주변 한번 둘러보자.", "목격자 계십니까?", "흠… 이쪽인가?" },
	spot = { "거기 서!", "저 사람이다!", "경찰입니다! 움직이지 마세요!", "찾았다, 거기 너!", "용의자 발견! 쫓아간다!" },
	chase = { "서라고!", "도망가봤자야!", "멈춰!", "헉… 헉… 거기 안 서?", "지원 바람! 용의자 도주 중!" },
	lost = { "놓쳤다… 이 근처일 텐데.", "어디로 갔지?", "골목으로 빠졌나?", "무전: 용의자 시야에서 놓침.", "쳇, 빠르네…" },
	search = { "이쪽은 없는데.", "여기 숨었나?", "흔적이 이쪽으로…", "저 뒤쪽도 확인해.", "분명 이 근처야." },
	wrong = { "아 이쪽이 아닌가?", "어? 막다른 길이네.", "잠깐, 반대쪽이었나…" },
	stumble = { "어어!", "아이고, 미끄러워라.", "윽, 계단…", "아 진짜, 길 막혀있네." },
	grab_fail = { "놓쳤다!", "빠져나갔어!", "어딜!", "으악, 미끄러져…" },
	grab = { "잡았다!", "꼼짝 마!", "손 뒤로!", "체포합니다." },
	order = { "잠깐만요, 거기 서 보세요.", "신분증 좀 보여주시겠어요?", "멈추세요, 경찰입니다." },
	ticket = { "이번엔 경고와 벌금으로 끝내겠습니다.", "벌금 처리합니다. 조심하세요.", "다음엔 이렇게 안 끝나요." },
	give_up = { "이번엔 놓쳤네… 복귀한다.", "무전: 수색 종료, 복귀합니다.", "다음에 보자." },
	roadblock = { "검문 중입니다, 서행하세요!", "도로 통제 중!", "차 세워!" },
	cuffed = { "변호사 부를 권리가 있습니다.", "차에 타세요.", "지구대로 갑니다." },
	inmate = {
		"신입이네? 뭐 하다 들어왔어?",
		"여기 밥은 진짜 별로야. 국은 미지근하고.",
		"나? 편의점에서 컵라면 하나… 배고파서 그랬어.",
		"조용히 있으면 금방 나가. 소리 지르면 더 있게 돼.",
		"밖에 나가면 국밥부터 먹을 거야.",
		"저 형사 아저씨 은근 착해. 말만 무섭지.",
		"공기놀이 할래? 여기선 그거밖에 할 게 없어.",
		"광안대교 불빛 보고 싶다…",
		"너도 도망치다 잡혔지? 다리가 아직 후들거리네.",
		"보석금 있으면 그냥 내고 나가. 시간 아까워.",
		"여기서 팔굽혀펴기 하면 시간 금방 가더라.",
		"다음엔 진짜 착하게 살 거야… 아마도.",
	},
	inmate_reply = {
		"ㅋㅋ 너도 참 운 없다.",
		"그러게… 다 그렇게 들어오는 거지.",
		"에이, 금방 나가겠네.",
		"나는 벌써 세 번째야. 자랑은 아니고.",
		"쉿, 간수 온다.",
		"나가면 연락해. 아, 번호는 압수됐지.",
	},
	release = { "나가셔도 됩니다. 다시는 보지 맙시다.", "형기 끝났습니다. 소지품 챙겨 가세요.", "자, 출구는 저쪽입니다. 착하게 사세요." },
}

function Law.pick(list: { string }?, rnd: (() -> number)?, last: string?): string
	if not list or #list == 0 then
		return ""
	end
	local r = rnd or math.random
	local i = math.clamp(math.floor(r() * #list) + 1, 1, #list)
	if list[i] == last and #list > 1 then
		i = (i % #list) + 1
	end
	return list[i]
end

function Law.fill(s: string, vars: { [string]: any }?): string
	if not vars then
		return s
	end
	return (string.gsub(s, "{(%w+)}", function(k)
		local v = vars[k]
		return if v ~= nil then tostring(v) else ""
	end))
end

function Law.stars(n: number): string
	n = math.clamp(math.floor(n or 0), 0, Law.MAX_STARS)
	return string.rep("★", n) .. string.rep("☆", Law.MAX_STARS - n)
end

function Law.won(n: number): string
	local s = tostring(math.floor(math.abs(n or 0)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if (n or 0) < 0 then "-" else "") .. out .. "원"
end

function Law.fmtTime(sec: number): string
	sec = math.max(0, math.floor(sec + 0.5))
	return string.format("%02d:%02d", sec // 60, sec % 60)
end

-- Validation for tests / the server boot.
function Law.selfTest(): { string }
	local p = {}
	for i = 1, Law.MAX_STARS do
		if not Law.TIERS[i] then
			table.insert(p, "missing tier " .. i)
		end
	end
	for id, s in Law.SMALL do
		if s.crime and not Law.CRIMES[s.crime] then
			table.insert(p, "small " .. id .. " -> unknown crime " .. s.crime)
		end
	end
	for id, b in Law.BIG do
		if not Law.CRIMES[b.crime] then
			table.insert(p, "big " .. id .. " -> unknown crime " .. b.crime)
		end
	end
	local s1 = Law.sentenceFor(1, 0)
	local s9 = Law.sentenceFor(12, 5)
	if not (s1 >= Law.JAIL_MIN and s9 <= Law.JAIL_MAX and s9 > s1) then
		table.insert(p, "sentence bands")
	end
	return p
end

return Law
