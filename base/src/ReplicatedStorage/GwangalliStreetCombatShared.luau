-- GwangalliStreetCombatShared: the street-life contract of 광안리 GTA — free NPC interaction (말 걸기 / 시비 /
-- 밀치기 / 주먹 / 돈 주기 / 삥 뜯기 / 사과 / 항복), fist fights, the 걸렁뱅이 and 동네바보 street
-- characters, crime + 수배 (wanted stars) and the 광안지구대 police. Pure data / pure functions at
-- require time (server and client).
--
-- SCRIPTS
--   ServerScriptService.GwangalliGameplay.Interact (feature module: init(ctx) / onLoaded / onCharacter /
--     onLeave; the "Interact" slot of GwangalliGameplay's FEATURE_MODULES) + its children Actors,
--     Street, Police: server-authoritative hits, HP, crimes, wanted level, police, arrests, KOs.
--   StarterPlayerScripts.GwangalliInteractClient (LocalScript) + children: target pick, the interaction
--     wheel, the 주먹 button (F), punches / hit effects, street pedestrian reactions (flee / fight back /
--     cower), the wanted stars, the HP bar, BUSTED / WASTED screens, sirens + light bars.
--
-- REMOTES (ReplicatedStorage.GwangalliInteract):
--   Action (RemoteEvent, client -> server): FireServer(kind, payload)
--     "act"     { verb, target = "ped" | "npc" | "actor", id, pos = {x,y,z}?, ptype? }   an interaction
--               verb = talk | provoke | shove | punch | give | rob | apologize
--               ped = client-side street pedestrian (GwangalliStreetLife; id = citizen id or "x12",
--               pos = its feet as the client sees it, ptype = its NPC type), npc = key NPC
--               (workspace.GwangalliNPCs, id = NpcId), actor = an Interact NPC (beggar / fool / police)
--     "air"     {}                         a punch at nothing (the swing is still seen / heard)
--     "pedHit"  { id, pos }                a provoked street pedestrian landed a punch on you
--     "surrender" {}                       hands up for the police (arrest with half the fine)
--   Event (RemoteEvent, server -> client): FireClient(payload) with payload.kind:
--     "hit"     { target, id, verb, dmg, hp, max, outcome, dx, dz, react?, line?, crit? }  your action
--               landed: play the target's reaction (pedestrians: the client owns them)
--     "miss"    { reason }                 refused (too far / cooldown / busy)
--     "hurt"    { dmg, hp, by, dx, dz, outcome, line? }   you got hit (shake, red flash, stagger / fall)
--     "say"     { actor?, id?, target?, text, dur, typeId? }  a speech bubble (actor = Interact NPC id)
--     "crime"   { crime, label, stars, witnessed }        a crime was recorded / reported
--     "radio"   { text }                   police radio line (toast)
--     "busted"  { fine, paid, stars }      arrested (BUSTED screen)
--     "wasted"  { fee, by }                knocked out (WASTED screen)
--     "cleared" { reason }                 wanted level lost ("evaded" | "arrested" | "hospital")
--     "pedReact" { id, react, line? }      the server decided a pedestrian's reaction (talk / give / rob)
--
-- ATTRIBUTES (Housing already honours Wanted / Arrested / PoliceChase / GwKO):
--   Player: Wanted (number 0..5, stars), WantedSeen (bool: a cop sees you now), PoliceChase (bool),
--           Arrested (bool), CombatHP (number 0..100), CombatMax (100)
--   Character: GwKO (bool: knocked out), GwHandsUp (bool)
--   Interact NPC models (workspace.GwangalliInteractNPCs, rendered by GwangalliInteractClient):
--     GiId, GiKind ("beggar" | "fool" | "police" | "patrol"), GiName, GiGround (root height above feet),
--     GiLeg "x0,y0,z0,x1,y1,z1,t0,dur" (feet; t0 = workspace:GetServerTimeNow()), GiYaw (degrees),
--     GiPose (pose name, "" = none), GiEmote "name#seq#serverTime" (one-shot), GiDown "t0|dx|dz|outcome|dur"
--     (stagger / knockdown / ko on the ground for dur s), GiHP, GiMax, GiAngry (UserId fighting, 0),
--     GiFace (UserId to face, 0)
--   Patrol car models: GiCar = true, GiSiren (bool: light bar + siren on)

local C = {}
C.VERSION = 1

C.Folder = "GwangalliInteract"
C.Remote = { Action = "Action", Event = "Event" }
C.NpcFolder = "GwangalliInteractNPCs"
C.Attr = {
	Wanted = "Wanted",
	Seen = "WantedSeen",
	Chase = "PoliceChase",
	Arrested = "Arrested",
	HP = "CombatHP",
	Max = "CombatMax",
	KO = "GwKO",
	HandsUp = "GwHandsUp",
}

---------------------------------------------------------------------------------------------------
-- Tuning
---------------------------------------------------------------------------------------------------
C.PLAYER_HP = 100
C.REGEN_DELAY = 6 -- s after the last hit
C.REGEN_RATE = 5 -- HP / s
C.REACH = 5.2 -- studs: interaction / punch range (feet to feet, flat)
C.REACH_SLACK = 2.6 -- server tolerance (positions lag)
C.FACING = 0.15 -- dot(look, to target) the server accepts
C.PICK_RANGE = 9 -- the client shows the target chip this far
C.PUNCH_CD = 0.34 -- s between punches (server floor 0.26)
C.COMBO_WINDOW = 1.0 -- s: punches closer than this chain (1, 2, 3 = hook)
C.PUNCH_DMG = 14 -- + strength * 0.12, the hook x1.6
C.SHOVE_STAGGER = true
C.ROB_RANGE = { 3000, 15000 } -- won taken from a plain pedestrian

-- NPC types (Citizens / Social types) + the Interact kinds. hp: punches to KO; fight: chance to fight
-- back when hit or insulted; flee: chance to run; dmg: their punch; rob: chance a 삥 뜯기 works.
C.TYPES = {
	plain = { hp = 55, fight = 0.28, flee = 0.6, dmg = { 6, 10 }, rob = 0.65, robWon = { 3000, 15000 } },
	violent = { hp = 95, fight = 1, flee = 0, dmg = { 10, 15 }, rob = 0.12, robWon = { 8000, 30000 } },
	drunk = { hp = 50, fight = 0.5, flee = 0.2, dmg = { 6, 11 }, rob = 0.7, robWon = { 2000, 9000 } },
	fool = { hp = 65, fight = 0, flee = 1, dmg = { 3, 5 }, rob = 0.85, robWon = { 500, 500 } },
	beggar = { hp = 42, fight = 0, flee = 0.4, dmg = { 3, 5 }, rob = 0.95, robWon = { 1200, 1200 } },
	key = { hp = 70, fight = 0, flee = 0, dmg = { 6, 9 }, rob = 0.4, robWon = { 5000, 20000 } },
	police = { hp = 140, fight = 1, flee = 0, dmg = { 11, 14 }, rob = 0, robWon = { 0, 0 } },
}
C.KO_TIME = { 7, 11 } -- s an NPC stays down after a KO
C.NPC_FIGHT = {
	speed = 14, -- studs/s while closing in
	reach = 3.3, -- studs: an NPC punch lands
	every = { 0.95, 1.4 }, -- s between NPC punches
	give_up = 32, -- studs: the player got away
	timeout = 28, -- s of fighting at most
	knock_every = 3, -- every 3rd NPC hit knocks the player down
}

-- crimes: heat added (stars, fractional) and the floor it raises the level to
C.CRIMES = {
	assault = { label = "폭행", add = 0.5, min = 1 },
	shove = { label = "폭행", add = 0.25, min = 1, onlyCop = true }, -- only when a cop sees it
	ko = { label = "폭행 (기절시킴)", add = 1, min = 2 },
	weak = { label = "약자 폭행", add = 0.75, min = 2 }, -- the 걸렁뱅이 / 동네바보
	robbery = { label = "강도 (삥 뜯기)", add = 1, min = 2 },
	rob_try = { label = "강도 미수", add = 0.5, min = 1 },
	cop = { label = "공무집행방해", add = 1, min = 3 },
	cop_ko = { label = "경찰관 폭행", add = 1, min = 4 },
	resist = { label = "체포 불응", add = 0.5, min = 1 },
	insult_cop = { label = "경찰 모욕", add = 0.5, min = 1, onlyCop = true },
	brawl = { label = "쌍방 폭행", add = 0.25, min = 1 },
	vehicle = { label = "교통사고 (인명)", add = 1, min = 2 },
	reckless = { label = "난폭 운전", add = 0.25, min = 1, onlyCop = true },
}
C.MAX_STARS = 5
C.REPORT_DELAY = { 3.5, 6 } -- s until a witness calls 112 (immediate when a cop sees it)
C.COP_SIGHT = 55 -- studs: a cop sees a crime / the suspect (line of sight)
C.EVADE = { 12, 16, 22, 28, 34 } -- s out of every cop's sight to lose 1..5 stars
C.EVADE_NEAR = 22 -- studs: a cop this close keeps the chase alive even without sight
C.DISPATCH_DELAY = { 5, 4, 3, 2.5, 2 }
C.COPS = { 1, 2, 3, 4, 4 } -- officers on foot per star level
C.CARS = { 1, 1, 2, 2, 3 }
C.COP_SPEED = { 15, 16, 17, 18, 19 } -- run speed per level (the player walks 16, runs ~22+)
C.COP_HIT_FROM = 3 -- stars: from here the police use the baton before cuffing
C.CUFF_HP = 38 -- (>= COP_HIT_FROM) cuff once the suspect is at or below this HP
C.FINES = { 30000, 70000, 150000, 300000, 500000 }
C.HOSPITAL_FEE = 25000
C.ARREST_PLACE = "광안지구대"
C.HOSPITAL_PLACES = { "광안 365 의원", "광안리 병원", "병원" } -- first Destination that exists (else home)
C.SPAWN_DIST = { 55, 85 } -- studs from the suspect where a patrol car pulls up

-- the two street characters + the beach patrol (server NPCs, Interact.Street / Interact.Police)
C.BEGGAR = {
	id = "gi_beggar",
	name = "광안리 김씨",
	role = "걸렁뱅이 · 천원만",
	callRange = 16, -- calls out to a passer-by
	callEvery = { 9, 16 },
	followRefused = 2, -- refuses before he gives up following you
	look = { body = "m", age = "senior", hair = "bald", hc = "gray", skin = 4, build = "slim", height = 0.94, style = "grandpa" },
}
C.FOOL = {
	id = "gi_fool",
	name = "만복이",
	role = "동네바보",
	walk = 8.5,
	run = 13,
	roam = 70, -- studs around his home spot
	seekEvery = { 7, 13 }, -- s between two 어깨빵 runs
	bumpReach = 2.8,
	bumpCd = 9,
	look = { body = "m", age = "adult", hair = "short", hc = "black", skin = 2, build = "avg", height = 1.0, style = "casual", acc = "bucket_hat" },
}
C.POLICE_LOOK = { body = "m", age = "adult", style = "uniform", acc = "cap", hair = "short", hc = "black", build = "broad", height = 1.04 }
C.POLICE_NAMES = { "순경 박태수", "순경 이민재", "경장 정우성", "순경 최지훈", "경사 강동원", "순경 김하늘", "경장 윤도현", "순경 한지민" }
C.PATROL = { name = "순경 오해변", role = "광안리 해변 순찰", speed = 6.5, sight = 45 }

-- interaction verbs (the wheel; order = clockwise from the top)
-- the interaction wheel: two pages (the client orders them by the situation; max 8 per page)
C.VERBS = {
	{ id = "greet", label = "인사하기", icon = "👋", page = 1 },
	{ id = "talk", label = "대화하기", icon = "💬", page = 1 },
	{ id = "ask", label = "질문하기", icon = "❓", page = 1 },
	{ id = "joke", label = "농담하기", icon = "😆", page = 1 },
	{ id = "tease", label = "놀리기", icon = "😜", page = 1 },
	{ id = "apologize", label = "사과하기", icon = "🙏", page = 1 },
	{ id = "give", label = "돈 주기", icon = "💸", page = 1 },
	{ id = "food", label = "음식 주기", icon = "🍙", page = 1 },
	{ id = "help", label = "도움 요청", icon = "🆘", page = 2 },
	{ id = "report", label = "신고하기", icon = "📞", page = 2 },
	{ id = "shove", label = "밀치기", icon = "✋", page = 2 },
	{ id = "punch", label = "때리기", icon = "👊", page = 2 },
	{ id = "rob", label = "삥 뜯기", icon = "💰", page = 2 },
	{ id = "flee", label = "도망가기", icon = "🏃", page = 2 },
	{ id = "provoke", label = "시비 걸기", icon = "😤", page = 2 },
}
C.VERB = {}
for _, v in C.VERBS do
	C.VERB[v.id] = v
end
C.GIVE_AMOUNT = 1000

-- animation names: pose-named tracks the studio maps to limb poses (Workspace.GwSimulator); in Roblox
-- fill ANIM_IDS with your own uploaded animations (rbxassetid://…) to play them as tracks too — the
-- procedural GwangalliAnim poses / emotes below always play in Roblox.
C.ANIM_IDS = { punch = "", shove = "", kick = "", fight = "", hurt = "", handsup = "", cuffed = "", cower = "", beg = "", ko = "" }
-- sound ids for Roblox (the studio synthesises sounds named GwSiren / GwPunch / GwWhistle / GwCuff)
C.SOUND_IDS = { siren = "", punch = "", whistle = "", cuff = "" }

-- procedural poses (GwangalliAnim.POSES format: motor -> {pitch, yaw, roll} degrees) for Roblox
C.POSES = {
	fight = { RightShoulder = { 72, 0, -12 }, RightElbow = { 105, 0, 0 }, LeftShoulder = { 84, 0, 14 }, LeftElbow = { 112, 0, 0 }, Waist = { 0, -14, 0 }, Neck = { -6, 10, 0 } },
	handsup = { RightShoulder = { 168, 0, 12 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 168, 0, -12 }, LeftElbow = { 10, 0, 0 } },
	cuffed = { RightShoulder = { -32, 0, -14 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { -32, 0, 14 }, LeftElbow = { 40, 0, 0 }, Neck = { -14, 0, 0 } },
	cower = { RightShoulder = { 140, 0, -30 }, RightElbow = { 120, 0, 0 }, LeftShoulder = { 140, 0, 30 }, LeftElbow = { 120, 0, 0 }, Waist = { 18, 0, 0 }, Neck = { -20, 0, 0 } },
	beg = { RightShoulder = { 62, 0, -6 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 20, 0, 6 }, RightHip = { 90, 0, 6 }, LeftHip = { 90, 0, -6 }, RightKnee = { -10, 0, 0 }, LeftKnee = { -10, 0, 0 }, Neck = { -8, 0, 0 } },
	ko = { RightShoulder = { 28, 0, 78 }, LeftShoulder = { 36, 0, -70 }, RightHip = { 22, 0, 14 }, RightKnee = { -32, 0, 0 }, Neck = { -16, 0, 0 } },
}
-- one-shot procedural moves: {duration, keyframe(u 0..1) -> motor -> {p, y, r}}
C.MOVES = {
	punch = { 0.36, function(u)
		local k = if u < 0.25 then u / 0.25 elseif u < 0.45 then 1 else math.max(0, 1 - (u - 0.45) / 0.55)
		return { RightShoulder = { 70 + 22 * k, 0, -12 + 10 * k }, RightElbow = { 105 * (1 - k), 0, 0 }, LeftShoulder = { 84, 0, 14 }, LeftElbow = { 112, 0, 0 }, Waist = { 0, -14 + 34 * k, 0 } }
	end },
	shove = { 0.5, function(u)
		local k = math.sin(math.min(1, u * 1.6) * math.pi)
		return { RightShoulder = { 30 + 60 * k, 0, 0 }, LeftShoulder = { 30 + 60 * k, 0, 0 }, RightElbow = { 60 * (1 - k), 0, 0 }, LeftElbow = { 60 * (1 - k), 0, 0 }, Waist = { 8 * k, 0, 0 } }
	end },
	hurt = { 0.5, function(u)
		local k = math.sin(u * math.pi)
		return { Waist = { -18 * k, 0, 6 * k }, Neck = { -22 * k, 0, 0 }, RightShoulder = { 40 * k, 0, 30 * k }, LeftShoulder = { 40 * k, 0, -30 * k } }
	end },
}

-- the studio pose name of each move / state (bridge poseOfTrack keywords)
C.TRACK = { punch = "GwPunch", shove = "GwShove", kick = "GwKick", fight = "GwFight", hurt = "GwHurt", handsup = "GwHandsUp", cuffed = "GwCuffed", cower = "GwCower", beg = "GwBeg", ko = "GwKnockout" }

---------------------------------------------------------------------------------------------------
-- Lines (부산 사투리 섞어서). kind -> { lines }
---------------------------------------------------------------------------------------------------
C.LINES = {
	player_provoke = { "뭘 봐?", "어깨 좀 펴고 다니네?", "한 판 붙을래?", "야, 니 내 아나?", "눈 깔아라~", "어디서 째려보노?" },
	player_shove = { "비켜라!", "저리 가라!", "길막하지 마라" },
	player_rob = { "가진 거 다 내놔라", "지갑 좀 보자", "있는 거 다 털어봐라" },
	player_give = { "이거 받으세요~", "옛다, 맛있는 거 사 드세요", "천원 드릴게요" },
	player_sorry = { "아 죄송합니다…", "미안합니다, 제가 잘못했어요", "실수였어요 진짜로!" },
	player_talk = { "안녕하세요~", "날씨 좋네요!", "광안리 자주 오세요?" },
	player_surrender = { "알겠어요 알겠어! 항복!", "손 들었어요!" },

	plain_talk = { "안녕하세요~", "광안리 좋지예?", "오늘 바다 예쁘네요", "저 지금 바빠서요…", "네? 저요?" },
	plain_provoked = { "뭐라 했노?", "아 왜요…", "참자, 참아…", "이상한 사람이네", "미친 거 아이가" },
	plain_fight = { "어디서 손을 대노!", "니 오늘 제대로 걸렸다", "한 판 붙자 이거제?", "가만 안 둔다!" },
	plain_hurt = { "아악!", "왜 때려요?!", "사람 살려!", "아야!", "미쳤나 이 사람이!" },
	plain_flee = { "도망쳐!", "꺄악!", "살려주세요!", "경찰! 경찰!" },
	plain_cower = { "때리지 마세요…", "제발요…", "돈 드릴게요…" },
	plain_robbed = { "가, 가져가세요…", "이거면 되죠…?", "제발 그냥 가세요" },
	plain_rob_fail = { "뭐? 장난하나?", "꿈 깨라", "경찰 부른다!" },
	plain_given = { "어… 감사합니다?", "이걸 왜 저한테…?", "오 진짜요? 고마워예!" },
	plain_calm = { "…조심하이소", "됐습니다, 가세요", "다음엔 국물도 없다" },
	plain_stay_mad = { "사과로 될 일이가?", "늦었다!" },
	plain_win = { "까불지 마라", "다음부턴 조심해라", "에이, 별것도 아이네" },
	plain_ko = { "으으…", "…" },
	plain_shoved = { "아 왜 밀어요!", "어어?", "조심 좀 하소!" },

	violent_provoked = { "뭐? 다시 말해봐라", "따라 나온나", "오늘 임자 만났네", "니 몇 살이고?" },
	violent_fight = { "니 오늘 죽었다", "덤벼라!", "어디 한번 해보자", "광안리 짱이 누군지 보여주까?" },
	violent_given = { "…뭐고 이거", "이걸로 퉁치자고?", "고맙다 마" },
	violent_rob_fail = { "뭐? 삥? 니가 나를?", "웃기고 있네", "죽고 싶나?" },

	fool_talk = { "니 이름 뭐고? 나는 만복이!", "바다에 고래 있다 진짜다!", "헤헤 나 잡아봐라~", "갈매기 봤나? 갈매기!", "나 오늘 붕어빵 세 개 묵었다!" },
	fool_roam = { "헤헤헤~", "부릉부릉~", "룰루랄라~", "어깨빵 간다~!", "갈매기다 갈매기!" },
	fool_bump = { "어깨빵! 헤헤헤", "쿵! 미안미안~ 헤헤", "아이쿠 내가 이겼다!", "히히 또 부딪혔다~" },
	fool_hurt = { "으아앙 엄마아!", "왜 때려 왜 때려!", "아파… 흐엉", "만복이 안 놀아!" },
	fool_provoked = { "히히 화났나?", "메롱~", "니가 더 바보다~" },
	fool_given = { "우와 돈이다! 과자 사묵어야지!", "니 착하다! 친구 하자!", "헤헤 부자 됐다!" },
	fool_robbed = { "이거 과자 사묵을 돈인데…", "흐앙 내 오백원!" },
	fool_calm = { "괜찮다! 헤헤", "용서해 줄게~" },

	beggar_call = { "총각, 천원만 주이소…", "한 푼만 도와주이소…", "배가 너무 고파예…", "어이 거기 멋쟁이, 천원만~", "국밥 한 그릇만…" },
	beggar_follow = { "한 번만요… 진짜 한 번만…", "천원이 없으면 오백원이라도…", "아이고 인심 야박하네…" },
	beggar_thanks = { "아이고 고맙심더! 복 받으이소!", "천사가 따로 없네예…", "오늘 국밥 한 그릇 묵겠네!", "평생 안 잊겠심더!" },
	beggar_refused = { "치… 인심 한번 야박하네", "다음엔 꼭 주이소~", "에휴…" },
	beggar_hurt = { "아이고 사람 살려!", "와 때리노!", "경찰 아저씨!!", "늙은이 때려서 뭐 할라꼬…" },
	beggar_provoked = { "내가 뭘 어쨌다고…", "사람 무시하지 마소", "나도 왕년엔 잘 나갔다…" },
	beggar_robbed = { "이거 내 전 재산인데…!", "천하의 나쁜 놈…", "벌 받는데이…" },
	beggar_talk = { "내가 왕년에 광안대교 공사도 했다 아이가", "요새 장사가 안 돼…", "젊은 양반 인상 좋네" },
	beggar_sleep = { "드르렁… 쿨…", "음냐… 국밥…" },

	cop_spot = { "거기 서! 경찰이다!", "멈춰! 손 들어!", "용의자 발견!", "꼼짝 마!" },
	cop_chase = { "도망가지 마!", "서라고!", "거기 서라!", "지원 바람!" },
	cop_arrest = { "현행범으로 체포합니다.", "묵비권을 행사할 수 있으며…", "가자, 지구대로." },
	cop_hit = { "공무집행방해까지?!", "지원 요청! 지원 요청!", "이 자식이…!" },
	cop_lost = { "놓쳤다…", "용의자 놓쳤습니다.", "어디 갔지…" },
	cop_patrol = { "오늘도 광안리 이상 무!", "안전한 해변 되세요~", "쓰레기는 쓰레기통에~" },
	cop_surrender = { "좋아, 천천히 손 들고!", "그대로 있어!" },
	cop_warn = { "경고합니다. 한 번만 더 그러면 연행합니다.", "지금 뭐 하시는 겁니까?" },
	cop_given = { "뇌물은 안 받습니다!", "이거 공무원 뇌물공여예요. 넣어두세요." },
	cop_talk = { "광안리 해변은 안전합니다!", "무슨 일 있으면 112!", "음주 수영은 안 됩니다~" },
	cop_baton = { "엎드려!", "저항하지 마!", "제압합니다!" },

	key_hurt = { "아야! 왜 이래요!", "경찰 부를 거예요!", "미쳤어요?!" },
	witness = { "어머 저기 싸움 났다!", "112! 112에 신고해!", "경찰 불러!", "와 미쳤다…" },
}

C.RADIO = {
	report = "📻 [무전] %s 신고 접수. 인근 순찰차 출동 바람.",
	dispatch = "📻 [무전] 광안지구대 %d호차 출동합니다.",
	backup = "📻 [무전] 지원 요청! 용의자 저항 중.",
	lost = "📻 [무전] 용의자 놓쳤습니다. 수색 종료.",
}

local rnd = Random.new()
function C.pick(list: { string }?): string
	if type(list) ~= "table" or #list == 0 then
		return ""
	end
	return list[rnd:NextInteger(1, #list)]
end
function C.line(kind: string): string
	return C.pick(C.LINES[kind])
end
-- a type-flavoured line: "<type>_<kind>", falling back to "plain_<kind>"
function C.typeLine(t: string?, kind: string): string
	local l = C.LINES[(t or "plain") .. "_" .. kind]
	if not l then
		l = C.LINES["plain_" .. kind]
	end
	return C.pick(l)
end
function C.typeOf(t: any): any
	return C.TYPES[t] or C.TYPES.plain
end

-- leg attribute "x0,y0,z0,x1,y1,z1,t0,dur" (feet)
function C.encodeLeg(a: Vector3, b: Vector3, t0: number, dur: number): string
	return string.format("%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.3f,%.3f", a.X, a.Y, a.Z, b.X, b.Y, b.Z, t0, math.max(dur, 0.01))
end
function C.decodeLeg(s: any): (Vector3?, Vector3?, number, number)
	if type(s) ~= "string" then
		return nil, nil, 0, 0
	end
	local v = string.split(s, ",")
	local n = {}
	for i = 1, 8 do
		n[i] = tonumber(v[i])
		if not n[i] then
			return nil, nil, 0, 0
		end
	end
	return Vector3.new(n[1], n[2], n[3]), Vector3.new(n[4], n[5], n[6]), n[7], n[8]
end
-- position along a leg at server time `now`
function C.legAt(a: Vector3, b: Vector3, t0: number, dur: number, now: number): (Vector3, number)
	local u = if dur <= 0.01 then 1 else math.clamp((now - t0) / dur, 0, 1)
	return a:Lerp(b, u), u
end

-- down attribute "t0|dx|dz|outcome|dur"
function C.encodeDown(t0: number, dx: number, dz: number, outcome: string, dur: number): string
	return string.format("%.3f|%.3f|%.3f|%s|%.2f", t0, dx, dz, outcome, dur)
end
function C.decodeDown(s: any): (number?, number, number, string, number)
	if type(s) ~= "string" or s == "" then
		return nil, 0, 0, "", 0
	end
	local p = string.split(s, "|")
	return tonumber(p[1]), tonumber(p[2]) or 0, tonumber(p[3]) or 0, p[4] or "stagger", tonumber(p[5]) or 1
end

-- 0 standing .. 1 lying: fall 0.4 s, hold, get up 0.8 s (outcome "ko" / "knockdown"); stagger = lean
function C.downPhase(t: number, outcome: string, dur: number): (string, number)
	if outcome == "stagger" then
		if t >= 0.8 then
			return "done", 0
		end
		return "stagger", math.sin(t / 0.8 * math.pi)
	end
	if t < 0.4 then
		local u = t / 0.4
		return "fall", u * u * (3 - 2 * u)
	end
	if t < dur then
		return "down", 1
	end
	if t < dur + 0.8 then
		local u = (t - dur) / 0.8
		return "getup", 1 - u * u * (3 - 2 * u)
	end
	return "done", 0
end

function C.packV(v: Vector3): { number }
	return { math.floor(v.X * 10 + 0.5) / 10, math.floor(v.Y * 10 + 0.5) / 10, math.floor(v.Z * 10 + 0.5) / 10 }
end
function C.unpackV(t: any): Vector3?
	if type(t) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(t[1]), tonumber(t[2]), tonumber(t[3])
	if not x or not y or not z or x ~= x or y ~= y or z ~= z or math.abs(x) > 1e5 or math.abs(y) > 1e5 or math.abs(z) > 1e5 then
		return nil
	end
	return Vector3.new(x, y, z)
end

function C.starsText(n: number): string
	n = math.clamp(math.floor(n + 0.5), 0, C.MAX_STARS)
	return string.rep("★", n) .. string.rep("☆", C.MAX_STARS - n)
end

function C.won(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out .. "원"
end

return C
