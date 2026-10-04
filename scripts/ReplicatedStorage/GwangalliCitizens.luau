-- GwangalliCitizens: the ROSTER of every named NPC in 광안리 GTA (owner: npc_social).
-- About 80 people form the WHOLE population: the key / interactive server NPCs (ids shared with
-- ServerScriptService.GwangalliGameplay.NPC and GwangalliGameplayShared.NPCS) plus the citizens who
-- roam the streets as client-side pedestrians and go to CLUB OCEAN at night. Pure data + pure
-- functions: no instances, no Roblox globals at require time (Lune unit tests load it directly).
--
-- CITIZEN FIELDS (Citizens.byId[id]):
--   id, name (Korean), age, g ("f"|"m"), persona (Citizens.PERSONAS key), speech ("std"|"busan"),
--   job (Korean label), key (true = a server NPC: never spawn it as a pedestrian), post (area of a key
--   NPC), postAct (what a key NPC does at the post: "work" by default, "hangout" for 민지 / 준호), hours
--   ({from, to} clock window a key street NPC is out, e.g. promoters at night),
--   home / work / eat / cafe / fun / walk (area ids, see Citizens.AREAS), schedule (resolved:
--   { {hour, areaId, act, t = effective start (jitter applied), crew = crewId?}, ... } sorted by t, crew
--   windows included; baseSchedule = the personal template only; see whereNow), club (0..1 how much
--   they go clubbing; 0 = never), crews / friends (= crew) / partner (see CREWS below),
--   social (0..1 how easily they say yes), topics / hate (conversation topics), tones ({like, dislike}),
--   love / like / dislike / refuse (gift ids or "cat:<category>", see GwangalliSocialShared.GIFTS),
--   bday ({month, day}), sig (their own casual lines, used from 친한 사이), errands (errand ids),
--   secret (Destination DisplayName of their 절친 spot), start (starting affinity), minor (age < 20),
--   accent ({r, g, b} name tag / heart chip colour),
--   look = { seed, body ("f"|"m"), age ("teen"|"young"|"adult"|"middle"|"senior"), skin (1..5 light ->
--     tan), hair ("short"|"side"|"twoblock"|"perm"|"buzz"|"long"|"bob"|"ponytail"|"bun"|"wave"|"bald"|
--     "granny_perm"|"curly"), hc (hair colour: "black"|"darkbrown"|"brown"|"ash"|"blonde"|"pink"|"gray"|
--     "white"|"blue"|"red"), style (day outfit: "school"|"office"|"casual"|"street"|"hoodie"|"sporty"|
--     "surf"|"apron"|"suit"|"fisher"|"granny"|"grandpa"|"tourist"|"rider"|"taxi"|"artsy"|"trendy"|
--     "chef"|"black"|"uniform"|"lifeguard"|"merch"), night (club outfit or nil: "dress"|"sparkle"|
--     "jacket"|"streetnight"|"black"|"suit"), acc (nil|"glasses"|"sunglasses"|"cap"|"bucket_hat"|
--     "headphones"|"camera"|"backpack"|"tote"|"surfboard"|"stroller"|"cane"|"helmet"|"visor"|"guitar"|
--     "earpiece"|"apron"|"flyers"|"laptop"|"sketchbook"), height (0.9..1.1), build ("slim"|"avg"|"broad") }
--   GwangalliNPCLooks builds the avatar deterministically from `look` (seed = FNV hash of the id).
--
-- AREAS: id -> { dest (Destination DisplayName: resolve with CollectionService tag "Destination",
--   attribute DisplayName), r (studs: how far from the Destination part the person may be), label
--   (Korean, for "아까 {area}에서 봤잖아요"), indoor? }. Pedestrian spawners place a citizen within r
--   of the area's Destination (on sidewalks / POIs), or along the line between two areas while in transit.
--
-- SCHEDULES (by the in-game clock, 0..24): Citizens.whereNow(id, clock) -> areaId, act, info
--   act: sleep | home | walk | sit | shop | eat | cafe | drink | photo | surf | sunbathe | jog | busk |
--        paint | fish | play | study | gym | work | queue | club | hangout
--   info: { transit (walking from info.from to the area, first 0.5 h of a slot), progress (0..1 along
--   that walk: place far pedestrians on the line from -> area, then snap to the nav graph), from, club
--   ("queue" | "inside" | "outside"), crew (the crew they are out with, see CREWS), fixed (key NPC),
--   off (key NPC outside its hours) }.   Citizens.onStreet(id, clock) -> may appear as a
--   pedestrian now.  NIGHT: club > 0 citizens go to CLUB OCEAN when the club hype (GwangalliNight.hype,
--   same curve as Citizens.hype) passes their threshold (1 - 0.95 * club): first they queue outside,
--   then they are inside (the club's own crowd shows them), ~30 % of them step outside each hour
--   (smoking area / GS25 / the beach), and they go home when the hype falls again.
--   Citizens.candidates(pos, clock, areaPos, maxN, reach?) -> ids of street-visible citizens near pos
--   (areaPos = function(areaId) -> Vector3? that resolves an area's Destination position).
--   Citizens.plausible(id, pos, clock, areaPos, slack?) -> the server's check of a client-reported
--   position of a roaming citizen.
--
-- STREET LOOK: Citizens.AREA_NAV[areaId] = GwangalliNav AREA ids to wander in; Citizens.ACT_STYLE[act] =
--   { move = wander | spot | loop | post | queue, kinds / tags (Nav POI kinds / tags), idle, speed,
--   label }. Citizens.hourly(id) -> 24 x {area, act}; Citizens.status(id, clock) -> "해변 · 산책 중",
--   area, act, visible (for contacts: where a friend is right now).
--
-- CREWS (friends among the citizens): Citizens.CREWS = { {id, name, kind (friends | couple | coworkers
--   | neighbors), members, slots = { {from, to, areaId, act}, ... } (shared schedule windows: the
--   members meet there and are shown together), club (true = they queue / party / step outside the
--   club together at night)}, lines? }. Per citizen: c.crews (crew ids), c.friends (2-4 citizen ids,
--   symmetric), c.partner (couple). whereNow's info.crew = the crew the person is with right now.
--   Citizens.companions(id, clock) -> the crew-mates with them now; Citizens.group(id, clock) ->
--   leader, members, crewId; Citizens.groupsNow(clock); Citizens.candidateGroups(...) (candidates as
--   leader + members); Citizens.areFriends(a, b); Citizens.meetLines(a, b, clock) (two friends meet
--   on the street); Citizens.crewChat(id, clock) (banter inside a group); Citizens.chipText(id,
--   withIds) -> "서연 · 도현이랑"; Citizens.shortName / callName / withText.
--
-- LINES: Citizens.linesFor(id, tier, clock) -> 3..n small-talk lines for that affinity tier (1..5)
--   and time of day (persona x register (polite for tiers 1-2, casual from 친한 사이) + tier lines +
--   Busan dialect extras + their own lines + evening club lures). Placeholders: {name} = the player's
--   display name (Citizens.fill). Citizens.smallTalk / greeting / question / react / reactLine /
--   giftPref / giftLine / complimentLine / numberLine / textFor / errandFor.

local Citizens = {}

Citizens.VERSION = 1

-------------------------------------------------------------------------------------------------
-- Hash (32-bit FNV-1a, identical to GwangalliShared.hashString) -> deterministic looks / jitter
-------------------------------------------------------------------------------------------------
local function mul32(a: number, b: number): number
	local aLo, aHi = a % 65536, a // 65536
	local bLo, bHi = b % 65536, b // 65536
	return ((aHi * bLo + aLo * bHi) % 65536 * 65536 + aLo * bLo) % 4294967296
end

local function hashString(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = mul32(h, 16777619)
	end
	return h
end
Citizens.hash = hashString

-- Deterministic 0..1 from a string and an integer (e.g. id + in-game hour).
local function hash01(s: string, n: number): number
	local h = hashString(s)
	h = bit32.bxor(h, (math.floor(n) * 2654435761) % 4294967296)
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	return h / 4294967296
end
Citizens.hash01 = hash01

-------------------------------------------------------------------------------------------------
-- Areas (Destination DisplayNames from the built world)
-------------------------------------------------------------------------------------------------
Citizens.AREAS = {
	-- beach / coast
	plaza = { dest = "광안리 만남의 광장", r = 110, label = "만남의 광장" },
	beach_c = { dest = "광안리해수욕장 (중앙)", r = 520, label = "해변" },
	beach_w = { dest = "스타벅스 광안리점", r = 480, label = "해변 서쪽" },
	beach_e = { dest = "호텔 센트럴베이", r = 560, label = "해변 동쪽" },
	sup = { dest = "광안리 SUP존", r = 320, label = "SUP존" },
	leports = { dest = "해양레포츠센터", r = 220, label = "레포츠센터" },
	-- nightlife street (CLUB OCEAN and around)
	club = { dest = "CLUB OCEAN 광안", r = 150, label = "클럽 앞" },
	gwangan_st = { dest = "광안 게임랜드", r = 320, label = "광안동 먹자골목" },
	gs25 = { dest = "GS25 광안리점", r = 70, label = "GS25 앞" },
	arcade = { dest = "광안 게임랜드", r = 70, label = "게임랜드", indoor = true },
	-- beachfront shops / hotels
	gs25_beach = { dest = "GS25 광안해변점 (켄트호텔 1F)", r = 70, label = "해변 편의점" },
	starbucks_beach = { dest = "스타벅스 광안리점", r = 80, label = "스타벅스", indoor = true },
	hongmidang = { dest = "fondx 홍미당 (아쿠아펠리스 1F)", r = 70, label = "홍미당 카페", indoor = true },
	bronx = { dest = "브롱스 광안리 (호메르스호텔 1F)", r = 70, label = "브롱스", indoor = true },
	kent = { dest = "켄트호텔 광안리", r = 90, label = "켄트호텔 앞" },
	homers = { dest = "호메르스호텔", r = 90, label = "호메르스호텔 앞" },
	aqua = { dest = "아쿠아펠리스 워터파크 · 찜질방", r = 110, label = "아쿠아펠리스" },
	info = { dest = "광안리 관광안내소", r = 80, label = "관광안내소" },
	central_bay = { dest = "호텔 센트럴베이", r = 110, label = "센트럴베이 앞" },
	terrace = { dest = "테라스타오션", r = 160, label = "테라스타오션" },
	jwell = { dest = "광안지웰에스테이트", r = 220, label = "지웰 앞" },
	-- 광안동 (station side)
	station = { dest = "지하철 광안역 3번 출구", r = 220, label = "광안역" },
	station6 = { dest = "지하철 광안역 6번 출구", r = 160, label = "광안역 6번 출구" },
	realty = { dest = "스타벅스 광안역점", r = 90, label = "광안역 부동산 앞" },
	bank = { dest = "BNK부산은행 광안동지점", r = 90, label = "은행 앞", indoor = true },
	police = { dest = "광안지구대", r = 90, label = "지구대 앞" },
	post = { dest = "광안동우체국", r = 90, label = "우체국", indoor = true },
	pcbang = { dest = "광안 PC방", r = 70, label = "PC방", indoor = true },
	karaoke = { dest = "광안 코인노래연습장", r = 70, label = "코인노래방", indoor = true },
	bowling = { dest = "광안 락볼링클럽 (볼링장)", r = 90, label = "볼링장", indoor = true },
	gym = { dest = "광안 휘트니스 24 (헬스장)", r = 90, label = "헬스장", indoor = true },
	salon = { dest = "헤어살롱 & 편집숍", r = 80, label = "헤어살롱", indoor = true },
	xi = { dest = "광안자이 (정문)", r = 260, label = "광안자이" },
	hospital = { dest = "광안 중앙병원", r = 110, label = "중앙병원" },
	school = { dest = "광안초등학교", r = 170, label = "학교 앞", indoor = true },
	church = { dest = "광안교회", r = 110, label = "교회 앞" },
	homeplus = { dest = "홈플러스 익스프레스 광안점", r = 140, label = "홈플러스" },
	suyeong_stn = { dest = "지하철 수영역 7번 출구", r = 220, label = "수영역" },
	parking = { dest = "광안 공영주차장", r = 160, label = "공영주차장" },
	-- 민락 (west)
	millak_market = { dest = "밀락더마켓", r = 170, label = "밀락더마켓" },
	hoetown = { dest = "민락회타운", r = 220, label = "민락회타운" },
	fishmarket = { dest = "민락어민활어직판장", r = 170, label = "활어직판장" },
	millak_park = { dest = "민락수변공원", r = 420, label = "민락수변공원" },
	-- 남천 (east)
	namcheon_park = { dest = "남천해변공원", r = 320, label = "남천해변공원" },
	bread = { dest = "빵천동 빵집골목", r = 220, label = "빵천동" },
	samik = { dest = "삼익비치타운", r = 360, label = "삼익비치" },
	kbs = { dest = "KBS 부산방송총국", r = 160, label = "KBS 앞", indoor = true },
	namcheon_stn = { dest = "지하철 남천역 3번 출구", r = 220, label = "남천역" },
	geumnyeon_stn = { dest = "지하철 금련산역 1번 출구", r = 220, label = "금련산역" },
}

-- Acts that never show on the street (the person is asleep / at home / inside the club).
Citizens.HIDDEN_ACTS = { sleep = true, home = true, club = true }

-- GwangalliNav AREA ids (mirror of Nav.AREA, for validation) and, per citizen area, the nav areas that
-- cover most pedestrian nodes within `r` of its Destination (measured on the built nav graph): where a
-- pedestrian of that area wanders (sidewalk / promenade / sand / plaza nodes) instead of standing on the
-- Destination marker. Nav.places[AREAS[id].dest] is the anchor node (missing for gym / salon / leports:
-- use Nav.nearest(destination part position)).
Citizens.NAV_AREAS = { "promenade", "beach", "plaza_meeting", "plaza_festival", "plaza_sunrise", "haebyeon", "backlane", "gwangnam", "suyeong", "side", "uptown", "club", "millak_park", "millak_port", "namcheon_park", "samik", "metro" }
Citizens.AREA_NAV = {
	plaza = { "plaza_meeting", "promenade" },
	beach_c = { "beach", "promenade", "plaza_meeting" },
	beach_w = { "promenade", "beach", "plaza_festival" },
	beach_e = { "promenade", "beach", "plaza_sunrise" },
	sup = { "promenade", "beach" },
	leports = { "namcheon_park", "beach", "promenade" },
	club = { "club", "side" },
	gwangan_st = { "side", "gwangnam", "backlane" },
	gs25 = { "side" },
	arcade = { "side", "gwangnam" },
	gs25_beach = { "haebyeon", "plaza_meeting" },
	starbucks_beach = { "promenade", "haebyeon" },
	hongmidang = { "haebyeon", "promenade" },
	bronx = { "haebyeon", "promenade" },
	kent = { "plaza_meeting", "promenade", "haebyeon" },
	homers = { "promenade", "haebyeon" },
	aqua = { "promenade", "haebyeon" },
	info = { "haebyeon", "promenade" },
	central_bay = { "promenade", "plaza_sunrise" },
	terrace = { "promenade", "side" },
	jwell = { "promenade", "side", "beach" },
	station = { "suyeong", "side", "metro" },
	station6 = { "suyeong", "side", "metro" },
	realty = { "suyeong", "side" },
	bank = { "suyeong", "side" },
	police = { "side", "gwangnam" },
	post = { "gwangnam" },
	pcbang = { "backlane" },
	karaoke = { "backlane" },
	bowling = { "gwangnam" },
	gym = { "side", "gwangnam" },
	salon = { "gwangnam", "side" },
	xi = { "suyeong", "side" },
	hospital = { "suyeong", "side" },
	school = { "gwangnam", "side" },
	church = { "gwangnam", "side" },
	homeplus = { "gwangnam" },
	suyeong_stn = { "suyeong", "metro" },
	parking = { "gwangnam" },
	millak_market = { "millak_port", "millak_park" },
	hoetown = { "millak_port", "side" },
	fishmarket = { "millak_port" },
	millak_park = { "millak_park" },
	namcheon_park = { "namcheon_park", "promenade", "side" },
	bread = { "gwangnam" },
	samik = { "samik", "side" },
	kbs = { "suyeong" },
	namcheon_stn = { "suyeong", "metro" },
	geumnyeon_stn = { "suyeong", "side" },
}

-- How an act looks on the street (for the pedestrian client):
--   move: "wander" (walk nav edges inside the area, pause now and then), "spot" (walk to a POI of
--   `kinds` / `tags` in the area and idle there with `idle`, then pick another spot after 1-4 in-game
--   minutes), "loop" (keep moving along the promenade / park edges: jog, patrol), "post" (stand near the
--   area anchor: work, busking, fishing), "queue" (the CLUB OCEAN queue: Nav.club.queue spots).
--   kinds = GwangalliNav POI_KIND names, tags = Nav.TAG names (either matches), idle = the idle
--   animation hint (GwangalliAnim names / procedural gestures), speed = walk speed multiplier.
Citizens.ACT_STYLE = {
	walk = { move = "wander", idle = "phone", speed = 1, label = "산책 중" },
	sit = { move = "spot", kinds = { "bench", "step", "view" }, tags = { "sit" }, idle = "sit", speed = 0.9, label = "쉬는 중" },
	shop = { move = "spot", kinds = { "shop", "window" }, tags = { "window" }, idle = "look", speed = 0.9, label = "쇼핑 중" },
	eat = { move = "spot", kinds = { "food", "stool", "cafe" }, tags = { "eat" }, idle = "eat", speed = 1, label = "밥 먹는 중" },
	cafe = { move = "spot", kinds = { "cafe", "stool" }, tags = { "eat", "sit" }, idle = "sit", speed = 0.9, label = "카페에서 쉬는 중" },
	drink = { move = "spot", kinds = { "food", "stool", "cafe" }, tags = { "eat", "chat" }, idle = "chat", speed = 1, label = "음료 마시는 중" },
	photo = { move = "spot", kinds = { "photo", "view" }, tags = { "photo" }, idle = "photo", speed = 0.9, label = "사진 찍는 중" },
	surf = { move = "wander", idle = "look", speed = 1, label = "서핑하는 중" },
	sunbathe = { move = "spot", kinds = { "towel" }, tags = { "sunbathe" }, idle = "sunbathe", speed = 0.8, label = "일광욕 중" },
	jog = { move = "loop", idle = "stretch", speed = 1.9, label = "조깅 중" },
	busk = { move = "post", kinds = { "busk" }, idle = "guitar", speed = 1, label = "버스킹 중" },
	dance = { move = "post", kinds = { "busk" }, tags = { "watch" }, idle = "dance", speed = 1, label = "춤 연습 중" },
	paint = { move = "spot", kinds = { "view", "bench" }, tags = { "watch", "sit" }, idle = "paint", speed = 0.9, label = "그림 그리는 중" },
	fish = { move = "post", kinds = { "view" }, tags = { "watch" }, idle = "fish", speed = 0.8, label = "낚시 중" },
	play = { move = "wander", idle = "phone", speed = 1.15, label = "노는 중" },
	study = { move = "spot", kinds = { "cafe", "bench" }, tags = { "sit", "phone" }, idle = "phone", speed = 1, label = "공부하는 중" },
	gym = { move = "loop", idle = "stretch", speed = 1.3, label = "운동하는 중" },
	work = { move = "post", idle = "work", speed = 1.1, label = "일하는 중" },
	hangout = { move = "spot", kinds = { "club", "bench", "step" }, tags = { "chat", "smoke" }, idle = "chat", speed = 1, label = "친구들이랑 노는 중" },
	queue = { move = "queue", kinds = { "club" }, tags = { "queue" }, idle = "phone", speed = 1, label = "클럽 줄 서는 중" },
	club = { move = "post", idle = "dance", speed = 1, label = "클럽에서 노는 중" },
	home = { move = "post", idle = "idle", speed = 1, label = "집에 있는 중" },
	sleep = { move = "post", idle = "idle", speed = 1, label = "자는 중" },
	patrol = { move = "wander", idle = "look", speed = 0.95, label = "순찰 중" },
}

-------------------------------------------------------------------------------------------------
-- Conversation tones (the player's reply styles). Each persona likes / dislikes some.
-------------------------------------------------------------------------------------------------
Citizens.TONES = {
	agree = "공감",
	joke = "농담",
	curious = "관심",
	compliment = "칭찬",
	deep = "진지",
	brag = "자랑",
	tease = "놀림",
	honest = "솔직",
	rude = "무례",
}

-------------------------------------------------------------------------------------------------
-- Personas. lines[timeOfDay] = { p = polite lines (모르는 사이 / 아는 사이), c = casual lines (친한 사이+) }.
-- Busan personas speak in dialect in both registers.
-------------------------------------------------------------------------------------------------
Citizens.PERSONAS = {
	hs = {
		label = "고등학생",
		tones = { like = { "joke", "agree" }, dislike = { "deep", "brag" } },
		topics = { "games", "food", "music", "study" },
		errands = { "gs25", "game" },
		secret = "광안 PC방",
		style = "school",
		sched = "school",
		lines = {
			morning = {
				p = { "아 1교시 지각할 것 같아요… 😭", "아침엔 편의점 삼각김밥이 최고예요.", "오늘 수행평가 있는데 하나도 안 했어요 ㅋㅋ" },
				c = { "아 진짜 학교 가기 싫다…", "야 나 어제 밤새 게임해서 눈이 안 떠져 ㅋㅋ", "아침 바다 보니까 좀 살 것 같다" },
			},
			day = {
				p = { "학원 가기 전에 떡볶이 먹으러 가는 중이에요!", "시험 끝나면 광안리 불꽃축제 보고 싶어요.", "요즘 반에서 다들 이 노래만 들어요 🎧" },
				c = { "학원 째고 바다 갈까 ㅋㅋ 농담이야", "떡볶이 먹을래? 내가 쏠 순 없지만 ㅋㅋ", "요즘 PC방에서 랭크 올리는 중이다" },
			},
			evening = {
				p = { "야자 끝나고 바다 보면 스트레스가 풀려요.", "광안대교 불 켜지는 거 진짜 예쁘죠?", "엄마가 일찍 들어오래요… 곧 가야 해요." },
				c = { "드론쇼 보러 갈래? 오늘 한대!", "숙제 좀 도와줄 수 있어? ㅋㅋ", "편의점 들렀다 가자, 배고파" },
			},
			night = {
				p = { "이 시간에 돌아다니면 혼나는데… 쉿!", "독서실 끝나고 집 가는 길이에요.", "밤바다 소리 좋아서 조금만 있다 가려고요." },
				c = { "나 몰래 나온 거야 ㅋㅋ 비밀!", "클럽은 아직 못 가지만… 스무 살 되면 꼭 간다", "밤에 보는 광안대교는 반칙이야" },
			},
		},
	},
	uni = {
		label = "대학생",
		tones = { like = { "joke", "curious" }, dislike = { "brag" } },
		topics = { "study", "coffee", "travel", "club" },
		errands = { "bread", "coffee" },
		secret = "남천해변공원",
		style = "casual",
		sched = "uni",
		lines = {
			morning = {
				p = { "1교시 전에 아아 한 잔 필수예요 ☕", "과제 마감이 오늘이라 멘붕이에요…", "아침 바다 러닝하는 사람들 부러워요." },
				c = { "나 오늘 공강이라 하루 종일 놀 수 있어!", "어제 과제하느라 밤샜어… 좀비 모드", "커피 없으면 오늘 못 버틴다" },
			},
			day = {
				p = { "여기 카페 뷰 진짜 미쳤죠?", "알바 끝나고 해변 산책하는 게 낙이에요.", "학교 축제 라인업 보셨어요?" },
				c = { "시험 끝나면 무조건 여행 간다", "빵천동 소금빵 맛집 알아? 같이 가자", "요즘 교양 수업 너무 빡세…" },
			},
			evening = {
				p = { "노을 질 때 광안리가 제일 예쁜 것 같아요.", "동기들이랑 치맥 하기로 했어요 🍗", "오늘 밤에 뭐 하세요?" },
				c = { "오늘 밤 뭐 해? 심심하면 연락해!", "노을 사진 건졌다! 봐봐", "과제 버리고 놀러 갈까…" },
			},
			night = {
				p = { "밤바다 보면서 사이다 한 캔… 이게 청춘이죠.", "막차 끊기기 전에 가야 하는데 아쉽네요.", "밤에 오니까 분위기 완전 다르네요." },
				c = { "아직 집 가기엔 너무 이르지 않아?", "밤바다 앞에서 이런 얘기 하니까 좋다", "내일 1교시… 몰라 오늘은 논다!" },
			},
		},
	},
	office = {
		label = "직장인",
		tones = { like = { "agree", "deep" }, dislike = { "brag", "tease" } },
		topics = { "work", "food", "money", "coffee" },
		errands = { "coffee", "post" },
		secret = "민락수변공원",
		style = "office",
		sched = "office",
		lines = {
			morning = {
				p = { "출근길 지하철이 지옥이었어요…", "아침 회의만 없으면 좋겠어요.", "오늘도 커피로 버텨 봅니다 ☕" },
				c = { "월요병 아니고 매일병이야 ㅋㅋ", "팀장님 오늘 기분 좋아야 할 텐데", "출근하기 싫다… 바다 보고 싶다" },
			},
			day = {
				p = { "점심은 역시 돼지국밥이죠.", "점심시간에 바다 잠깐 보는 게 힐링이에요.", "요즘 야근이 너무 많아서요…" },
				c = { "점심 뭐 먹지? 이게 인생 최대 고민이다", "회사 앞에 새 카페 생겼더라", "오늘 칼퇴 각이다 ㅋㅋ" },
			},
			evening = {
				p = { "퇴근했어요! 드디어 자유예요.", "퇴근하고 광안리 산책이 제 낙이에요.", "회식 빠질 핑계 좀 같이 생각해 주세요 ㅋㅋ" },
				c = { "퇴근했다!! 치킨 콜?", "오늘 부장님이 또… 아 말을 말자", "금요일 느낌 난다, 오늘 좀 놀자" },
			},
			night = {
				p = { "이 시간에 바다 보면 하루 피로가 풀려요.", "내일 출근인데… 조금만 더 있다 갈래요.", "야경 보면서 핫초코 한 잔이 최고죠." },
				c = { "스트레스 풀러 클럽이라도 갈까?", "내일 반차 쓸까 진지하게 고민 중", "오늘은 일찍 가려고 했는데… 망했다 ㅋㅋ" },
			},
		},
	},
	surfer = {
		label = "서퍼",
		tones = { like = { "curious", "joke" }, dislike = { "brag" } },
		topics = { "sea", "fitness", "travel" },
		errands = { "sup", "burger" },
		secret = "해양레포츠센터",
		style = "surf",
		sched = "surf",
		lines = {
			morning = {
				p = { "오늘 새벽 파도 괜찮았어요! 🏄", "아침 바다 물 온도 딱 좋아요.", "서핑 한번 해 보실래요? 알려 드릴게요." },
				c = { "파도 좋다! 오늘 같은 날은 무조건 바다지", "새벽 바다 진짜 최고야, 너도 한번 와", "보드 왁스칠 하다가 나왔어" },
			},
			day = {
				p = { "송정만큼은 아니어도 광안리 파도도 재밌어요.", "선크림 꼭 바르세요, 여기 햇볕 세요.", "SUP도 재밌어요, 해 보셨어요?" },
				c = { "바람 방향 봐, 오후에 파도 올라온다", "까맣게 탄 건 훈장이야 ㅋㅋ", "같이 SUP 탈래? 내가 잡아 줄게" },
			},
			evening = {
				p = { "노을 보면서 타는 파도가 최고예요.", "서핑 끝나고 먹는 라면은 진리죠.", "내일 파도 예보 좋대요!" },
				c = { "오늘 파도 몇 개 잡았는지 알아? 무려 열 개!", "바다 들어갔다 나오면 세상이 다 좋아 보여", "해 지기 전에 한 번 더 들어갈까" },
			},
			night = {
				p = { "밤바다 소리 들으면서 쉬는 중이에요.", "내일 새벽 서핑 때문에 일찍 자야 해요.", "밤에도 바다 냄새가 좋네요." },
				c = { "밤바다도 좋지만 난 아침형 인간이야", "클럽? 가끔 가지. 파도 없는 날에 ㅋㅋ", "별 보이네, 내일 날씨 좋겠다" },
			},
		},
	},
	grandma = {
		label = "할머니",
		tones = { like = { "agree", "deep", "curious" }, dislike = { "brag", "honest" } },
		topics = { "family", "food", "sea" },
		errands = { "market", "church", "pharmacy" },
		secret = "민락수변공원",
		style = "granny",
		sched = "granny",
		lines = {
			morning = {
				p = { "아이고, 일찍 나왔네예. 아침은 뭇나?", "새벽시장 갔다 오는 길이다. 오늘 고기 좋더라.", "아침 바닷바람이 몸에 좋다 카더라." },
				c = { "밥은 뭇나? 굶고 댕기지 마래이.", "요새 젊은 사람들은 와 이리 바쁘노.", "할매가 사탕 하나 주까?" },
			},
			day = {
				p = { "우리 손주도 딱 니만 하다 아이가.", "여 앉아서 바다 보는 기 제일 좋다.", "날이 억수로 덥네, 물 많이 마시래이." },
				c = { "니 얼굴이 좀 핼쑥하다. 밥 잘 챙기 무라.", "옛날에 광안리는 다리도 없었데이.", "이따 우리 집 가서 식혜 한 잔 하고 가라." },
			},
			evening = {
				p = { "해 지니까 인자 쪼매 시원하네.", "저녁 무러 들어갈 시간이다.", "요새 저 다리에 불 켜지는 거 보는 재미로 산다." },
				c = { "밤늦게 돌아댕기지 말고 일찍 들어가래이.", "니 요새 연애는 하나? 호호", "할매가 오늘 김치 담갔다, 쫌 주까?" },
			},
			night = {
				p = { "이 시간에 뭐하노? 얼른 들어가래이.", "잠이 안 와가 바람 쫌 쐬러 나왔다.", "밤바다가 옛날 생각나게 하네." },
				c = { "클럽? 할매도 젊을 때는 춤 좀 췄다 아이가!", "늦었다, 조심해서 들어가래이.", "니 보니까 기분이 좋네." },
			},
		},
	},
	grandpa = {
		label = "할아버지",
		tones = { like = { "curious", "agree" }, dislike = { "brag", "tease" } },
		topics = { "baseball", "family", "sea" },
		errands = { "pharmacy", "fish" },
		secret = "민락어민활어직판장",
		style = "grandpa",
		sched = "grandpa",
		lines = {
			morning = {
				p = { "새벽 낚시 갔다 왔지. 오늘은 입질이 없네.", "아침 운동은 하나? 건강이 최고다.", "요새 아침 공기가 참 좋다." },
				c = { "젊은 사람이 벌써 나왔나, 부지런하네.", "어제 야구 봤나? 아이고 속 터져 죽겠다.", "이 동네 토박이가 내다. 모르는 거 있음 물어봐라." },
			},
			day = {
				p = { "옛날엔 여기가 전부 모래사장이었제.", "장기 한 판 둘 줄 아나?", "광안대교 생길 때 내가 다 봤다 아이가." },
				c = { "요새 젊은 것들은 핸드폰만 보고 댕기드라.", "니 야구 어데 응원하노? 부산이면 당연히…", "바다는 변해도 사람 인심은 그대로다." },
			},
			evening = {
				p = { "저녁에는 식혜 한 사발이 최고지.", "해 넘어가는 거 보는 기 내 취미다.", "요새 저녁 되면 사람들 억수로 많데이." },
				c = { "오늘 야구 이기면 내가 한턱 쏘꾸마.", "젊을 때 나도 여서 연애했다 아이가, 허허.", "일찍 드가라, 밤바람 차다." },
			},
			night = {
				p = { "잠이 없어서 산책 나왔다.", "밤바다는 옛날이나 지금이나 똑같다.", "시끄러운 노래 소리가 클럽이라 카드나?" },
				c = { "나도 젊을 땐 밤새 놀았다 아이가.", "니는 뭐 하는 사람이고? 궁금하네.", "조심해서 댕기래이, 요새 차 많다." },
			},
		},
	},
	tourist = {
		label = "여행객",
		tones = { like = { "curious", "compliment" }, dislike = { "honest" } },
		topics = { "travel", "food", "photo" },
		errands = { "map", "burger" },
		secret = "광안리 SUP존",
		style = "tourist",
		sched = "tourist",
		lines = {
			morning = {
				p = { "부산 여행 이틀째예요! 아침부터 설레요.", "혹시 돼지국밥 맛집 아세요?", "해 뜨는 광안리 보려고 일찍 나왔어요." },
				c = { "여기 진짜 서울이랑 공기부터 달라!", "사진 좀 찍어 줄래? 대교 나오게!", "오늘 일정 너무 빡빡해 ㅋㅋ" },
			},
			day = {
				p = { "광안대교 실물 영접했어요! 🌉", "밀면이랑 냉면 차이가 뭐예요?", "여기 SUP 타 보려고 하는데 어때요?" },
				c = { "부산 사투리 좀 가르쳐 줘! 뭐라카노?", "회 먹으러 민락 가 볼까?", "사진 백 장은 찍은 듯 ㅋㅋ" },
			},
			evening = {
				p = { "드론쇼 몇 시에 해요? 꼭 보고 가고 싶어요!", "노을 지는 광안리 진짜 그림 같아요.", "밤에는 뭐 하면 재밌어요?" },
				c = { "오늘 밤 드론쇼 같이 볼래?", "클럽 오션 유명하다던데 가 봤어?", "여행 마지막 밤이야, 제대로 놀아야지!" },
			},
			night = {
				p = { "야경이 사진보다 훨씬 예뻐요!", "숙소 가기 아쉬워서 조금만 더 걸으려고요.", "부산 사람들 정 많다더니 진짜네요." },
				c = { "여기 살고 싶다 진심으로", "내일 서울 가기 싫어…", "클럽 가 볼까? 여행 왔는데!" },
			},
		},
	},
	foreigner = {
		label = "외국인 관광객",
		tones = { like = { "agree", "joke" }, dislike = { "deep" } },
		topics = { "travel", "food", "music" },
		errands = { "map", "coffee" },
		secret = "빵천동 빵집골목",
		style = "tourist",
		sched = "tourist",
		lines = {
			morning = {
				p = { "Good morning! 안녕하세요! 아침 바다 너무 예뻐요!", "커피… where is 커피? ㅎㅎ", "I love Busan! 부산 최고!" },
				c = { "Hey! 오늘 날씨 amazing!", "Korean breakfast 추천해 줘!", "나 한국어 연습 중이야 ㅎㅎ 잘해?" },
			},
			day = {
				p = { "이 다리 이름 뭐예요? Gwangan Bridge?", "Can you take a photo? 사진 부탁해요!", "Korean BBQ 먹고 싶어요!" },
				c = { "떡볶이 too spicy! 근데 맛있어 ㅋㅋ", "K-pop 좋아해! 너도?", "여기 beach 진짜 clean하다" },
			},
			evening = {
				p = { "Sunset… 와, 너무 예뻐요.", "Drone show 오늘 해요?", "Club Ocean, 거기 good?" },
				c = { "오늘 밤 party 하는 곳 알아?", "밀면 처음 먹어 봐! So good!", "Busan night view is crazy!" },
			},
			night = {
				p = { "The bridge lights… 정말 beautiful.", "호텔 가야 하는데 아쉬워요.", "한국 사람들 very kind!" },
				c = { "Let's go to the club! 클럽 가자!", "Best trip ever, seriously", "나 내년에 또 올 거야!" },
			},
		},
	},
	barista = {
		label = "바리스타",
		tones = { like = { "curious", "compliment" }, dislike = { "brag" } },
		topics = { "coffee", "music", "food" },
		errands = { "bread", "fish" },
		secret = "빵천동 빵집골목",
		style = "casual",
		sched = "dayjob",
		lines = {
			morning = {
				p = { "오픈 준비하러 가는 길이에요. 오늘 원두 향 좋아요.", "아침 첫 샷 뽑을 때가 제일 좋아요.", "커피 좋아하세요? 산미 있는 거요?" },
				c = { "나 오늘 라떼아트 하트 백 개 성공함 ㅋㅋ", "아침 손님들은 다 아아만 시켜", "원두 새로 들어왔어, 맛보러 와" },
			},
			day = {
				p = { "쉬는 날엔 다른 카페 탐방 다녀요.", "빵천동 빵이랑 커피 조합 최고예요.", "핸드드립 배우고 싶으면 말씀하세요!" },
				c = { "카페 투어 갈래? 내가 코스 짜 놨어", "오늘 손님이 커피에 설탕 다섯 개 넣더라…", "커피 없는 세상은 상상이 안 돼" },
			},
			evening = {
				p = { "마감하고 나니까 다리가 후들거려요.", "저녁엔 디카페인만 마셔요.", "퇴근하면 바다 보면서 쉬어요." },
				c = { "마감 청소가 제일 힘들어 ㅠ", "저녁엔 커피 말고 밀크티지!", "이따 클럽 갈 사람? 오늘 쉬는 날이야" },
			},
			night = {
				p = { "밤에는 저도 손님이 되고 싶어요 ㅎㅎ", "내일 오픈이라 일찍 자야 하는데…", "밤바다 보면서 멍 때리는 중이에요." },
				c = { "클럽 가서 스트레스 좀 풀자!", "커피 냄새가 몸에 배서 안 빠져 ㅋㅋ", "밤바다엔 역시 하이볼이지" },
			},
		},
	},
	djfan = {
		label = "EDM 팬",
		tones = { like = { "agree", "joke" }, dislike = { "honest", "deep" } },
		topics = { "club", "music", "fashion" },
		errands = { "ticket", "gs25" },
		secret = "CLUB OCEAN 광안",
		style = "street",
		sched = "party",
		lines = {
			morning = {
				p = { "어제 클럽에서 새벽까지 놀았어요… 🥱", "아침엔 로파이 들으면서 걸어요.", "귀가 아직 멍해요 ㅋㅋ" },
				c = { "어제 드롭 미쳤었어!!", "나 아직 어제 텐션 안 빠졌어 ㅋㅋ", "아침은 해장국이지" },
			},
			day = {
				p = { "이번 주말 라인업 보셨어요? 🔥", "요즘 테크하우스에 빠졌어요.", "헤드폰 없으면 못 살아요 🎧" },
				c = { "이 트랙 들어봐, 소름 돋아", "DJ 셋 영상 봤어? 미쳤더라", "오늘 밤 뭐 입고 갈지 고민 중" },
			},
			evening = {
				p = { "오늘 밤 클럽 오션 가세요? 라인업 미쳤어요!", "해 지면 슬슬 심장이 뛰어요 ㅋㅋ", "클럽 가기 전에 밥 든든히 먹어야죠." },
				c = { "오늘 밤 오션 ㄱ? 나 벌써 신났어!", "프리파티 할래? 편의점 앞에서 ㅋㅋ", "오늘 입장 줄 길 거야, 일찍 가자" },
			},
			night = {
				p = { "지금 클럽 가는 길이에요! 같이 가실래요?", "베이스 소리 여기까지 들리죠?", "오늘 DJ 진짜 대박이래요." },
				c = { "지금이 피크타임이야, 들어가자!", "플로어에서 보자! 🕺", "오늘은 해 뜰 때까지 달린다" },
			},
		},
	},
	influencer = {
		label = "인플루언서",
		tones = { like = { "compliment", "agree" }, dislike = { "honest" } },
		topics = { "photo", "fashion", "food" },
		errands = { "salon", "bread" },
		secret = "테라스타오션",
		style = "trendy",
		sched = "influencer",
		lines = {
			morning = {
				p = { "아침 햇살 받을 때 사진이 제일 잘 나와요 📸", "오늘 콘텐츠 뭐 찍을지 고민 중이에요.", "팔로워분들이 광안리 브이로그 좋아하더라고요." },
				c = { "나 오늘 릴스 조회수 터졌어!!", "이 필터 어때? 괜찮지?", "아침 카페 사진 건지러 가는 중" },
			},
			day = {
				p = { "여기 포토스팟 알려 드릴까요?", "협찬 받은 옷인데 어때요?", "오늘 해변 브이로그 찍고 있어요!" },
				c = { "같이 사진 찍자! 태그해 줄게", "여기 신상 카페 벌써 가 봤어?", "좋아요 눌러 줘 ㅋㅋ 부탁해" },
			},
			evening = {
				p = { "노을 타임이 골든아워예요! 서둘러야 해요.", "광안대교 불 들어오는 순간을 찍어야 해요.", "오늘 라이브 방송 할 건데 잠깐 나와 주실래요?" },
				c = { "노을 진짜 미쳤다, 빨리 찍어!", "오늘 밤 클럽 브이로그 찍을 거야", "나 오늘 코디 어때? 솔직하게!" },
			},
			night = {
				p = { "야경 사진은 삼각대가 필수예요.", "클럽 오션 입구가 요즘 제일 핫해요.", "오늘 찍은 사진 보정하느라 밤새겠어요." },
				c = { "클럽 가서 인증샷 찍자!", "우리 같이 찍은 거 올려도 돼?", "오늘 콘텐츠 대박이다 진짜" },
			},
		},
	},
	fisher = {
		label = "어부",
		tones = { like = { "agree", "curious" }, dislike = { "brag" } },
		topics = { "sea", "food", "money" },
		errands = { "post", "pharmacy" },
		secret = "민락어민활어직판장",
		style = "fisher",
		sched = "fisher",
		lines = {
			morning = {
				p = { "새벽에 배 타고 나갔다 왔심더. 오늘 고기 좋심더.", "민락 활어시장 가 보이소, 싱싱합니데이.", "바다 날씨는 내가 제일 잘 안다 아입니꺼." },
				c = { "오늘 새벽에 광어 봤나, 팔뚝만 하더라!", "바다 사람은 해 뜨기 전에 일어난다 아이가.", "배 기름값이 또 올랐다 카이." },
			},
			day = {
				p = { "회는 민락에서 무야 제맛이지예.", "그물 손질하다 잠깐 나왔심더.", "오늘은 파도가 좀 높네예." },
				c = { "니 회 좋아하나? 내가 싸게 해 주께.", "요새 젊은 아들은 바다 일 안 할라 칸다.", "바다는 정직하다. 땀 흘린 만큼 준다 아이가." },
			},
			evening = {
				p = { "일 끝나고 회 한 접시 묵는 기 낙이지예.", "해 지면 바다가 조용해지지예.", "내일 새벽에 또 나가야 되니까 일찍 잘랍니더." },
				c = { "회 한 접시 할래? 내가 가 오꾸마.", "오늘 잡은 거 다 팔았다, 기분 좋다 아이가!", "바다 냄새 안 나면 잠이 안 온다." },
			},
			night = {
				p = { "이 시간엔 다 자야지예, 새벽 일이 있으니까.", "밤바다 보면 걱정이 싹 없어집니더.", "옛날엔 저 다리 대신 고깃배 불빛만 있었지예." },
				c = { "클럽? 내는 배 위가 클럽이다 ㅋㅋ", "늦게 댕기지 말고 들어가래이.", "파도 소리 들으면 마음이 편하다." },
			},
		},
	},
	taxi = {
		label = "택시기사",
		tones = { like = { "joke", "agree" }, dislike = { "deep" } },
		topics = { "baseball", "money", "travel" },
		errands = { "coffee", "gs25" },
		secret = "남천해변공원",
		style = "taxi",
		sched = "taxi",
		lines = {
			morning = {
				p = { "첫 손님 태우러 가는 길입니더.", "아침엔 수영교차로가 억수로 막힙니더.", "어데 가십니꺼? 태워 드릴까예?" },
				c = { "아침부터 손님이 없네, 오늘 장사 우짜노.", "부산 길은 내 손바닥 안이다 아이가.", "커피 한 잔 하고 달려야지." },
			},
			day = {
				p = { "광안리는 주차가 헬입니더, 택시 타이소.", "요새 관광객이 많아가 장사가 좀 됩니더.", "해운대보다 광안리가 더 정감 있지예." },
				c = { "어제 손님이 서울에서 택시로 왔다 카더라, 대박이제?", "야구 표 구했나? 사직 가야지!", "라디오에서 좋은 노래 나오네." },
			},
			evening = {
				p = { "퇴근 시간이라 콜이 쏟아집니더.", "저녁엔 회타운 가는 손님이 많아예.", "밤에는 클럽 앞에서 손님 기다립니더." },
				c = { "오늘 밤 클럽 오션 앞에 택시 줄 선다, 두고 봐라.", "밥 먹을 시간도 없다 카이.", "밤 장사가 진짜 장사다." },
			},
			night = {
				p = { "심야 할증 붙는 시간입니더, 조심히 타이소.", "클럽 끝나는 시간에 맞춰서 기다리는 중입니더.", "밤에 광안대교 달리면 기분 좋지예." },
				c = { "꾸벅꾸벅 조는 손님도 내가 다 집까지 모셔 드린다.", "새벽 두 시가 제일 바쁘다 아이가.", "피곤하다… 그래도 한 탕만 더 뛰자." },
			},
		},
	},
	rider = {
		label = "배달 라이더",
		tones = { like = { "agree", "joke" }, dislike = { "brag" } },
		topics = { "work", "food", "money" },
		errands = { "burger", "gs25" },
		secret = "밀락더마켓",
		style = "rider",
		sched = "rider",
		lines = {
			morning = {
				p = { "아침 배달은 커피가 제일 많아요.", "오늘 콜 많았으면 좋겠어요.", "헬멧 쓰면 머리가 눌려서 큰일이에요 ㅋㅋ" },
				c = { "오늘 목표 오십 건이다!", "아침부터 언덕 배달 세 번 했어…", "배달하다 보면 동네 맛집 다 알게 돼" },
			},
			day = {
				p = { "점심 피크라 정신이 없어요!", "밀락더마켓 콜이 제일 많아요.", "잠깐 쉬는 중이에요, 물 한 모금만…" },
				c = { "이 동네 엘리베이터 없는 빌라 진짜 무서워", "리뷰에 친절 기사님 달리면 그날 기분 최고", "배고파… 남의 음식만 나르니까 ㅋㅋ" },
			},
			evening = {
				p = { "저녁 피크 시작이에요, 달려야죠!", "치킨 배달이 제일 많은 시간이에요 🍗", "비 오는 날엔 배달료가 올라요." },
				c = { "오늘 수입 괜찮다! 이따 치맥 쏜다", "퇴근 콜 잡으면 오늘 끝!", "광안리 배달은 뷰 보는 맛에 한다" },
			},
			night = {
				p = { "야식 배달 시간이에요. 족발이 제일 많아요.", "새벽까지 달리면 몸이 남아나질 않아요.", "밤바다 보면서 잠깐 쉬어 가요." },
				c = { "클럽 앞으로 배달 가면 사람 진짜 많더라", "오늘 백 건 채웠다!! 칭찬해 줘", "내일은 쉬는 날, 나도 좀 놀아야지" },
			},
		},
	},
	chef = {
		label = "요리사",
		tones = { like = { "compliment", "curious" }, dislike = { "honest" } },
		topics = { "food", "sea", "work" },
		errands = { "fish", "market" },
		secret = "민락회타운",
		style = "chef",
		sched = "latejob",
		lines = {
			morning = {
				p = { "새벽시장에서 재료 보고 오는 길이에요.", "오늘 생선 상태가 아주 좋아요.", "아침부터 육수 끓이고 있어요." },
				c = { "오늘 메뉴 뭐 할지 고민이야", "시장 사장님들이랑 흥정하는 게 재밌어", "칼질 하다가 잠깐 바람 쐬러 나왔어" },
			},
			day = {
				p = { "점심 장사 끝나고 한숨 돌리는 중이에요.", "맛있게 드시는 거 보면 힘이 나요.", "부산 음식은 역시 국밥이죠." },
				c = { "새 메뉴 개발 중인데 시식해 볼래?", "오늘 손님이 두 그릇 먹고 갔어 ㅋㅋ", "맛은 정성이야, 진짜로" },
			},
			evening = {
				p = { "저녁 장사 준비로 바빠요!", "요즘 전어가 제철이에요.", "퇴근하면 저도 남이 해 준 밥 먹고 싶어요 ㅎㅎ" },
				c = { "오늘 저녁 예약 꽉 찼다!", "이따 마감하고 야식 먹을래?", "요리하는 사람은 정작 밥을 못 먹어 ㅋㅋ" },
			},
			night = {
				p = { "마감하고 나오니 이 시간이네요.", "밤바다 보면서 쉬는 게 유일한 휴식이에요.", "내일 재료 손질할 생각에 벌써 피곤해요." },
				c = { "야식은 내가 끓인 라면이 최고야", "클럽? 가면 나 제일 먼저 뻗어 ㅋㅋ", "오늘도 무사히 끝났다" },
			},
		},
	},
	artist = {
		label = "아티스트",
		tones = { like = { "deep", "compliment" }, dislike = { "brag" } },
		topics = { "art", "music", "sea" },
		errands = { "coffee", "bread" },
		secret = "남천해변공원",
		style = "artsy",
		sched = "artist",
		lines = {
			morning = {
				p = { "아침 바다 색이 오늘따라 특별해요.", "스케치하러 나왔어요.", "영감은 아침 산책에서 와요." },
				c = { "오늘 바다 색 봤어? 그려야겠다", "밤새 곡 쓰다가 나왔어", "기타 줄 갈아야 하는데…" },
			},
			day = {
				p = { "오후에 해변에서 공연할 거예요. 보러 오세요!", "여기 풍경은 몇 번을 그려도 질리지 않아요.", "요즘 새 노래 작업 중이에요." },
				c = { "내 신곡 들어 볼래? 솔직하게 말해 줘", "그림 사 가는 사람이 있으면 좋겠다 ㅋㅋ", "예술은 배고파… 진짜로" },
			},
			evening = {
				p = { "노을 질 때 버스킹 하면 사람들이 제일 많아요.", "오늘 신청곡 받아요!", "해 질 무렵 빛이 그림에 제일 좋아요." },
				c = { "오늘 버스킹 관객 기록 깼어!", "노래 한 곡 불러 줄까?", "이 순간을 그림으로 남기고 싶다" },
			},
			night = {
				p = { "밤에는 조용히 곡을 써요.", "광안대교 불빛이 영감을 줘요.", "오늘 공연 들어 주셔서 감사해요!" },
				c = { "클럽에서 디제잉도 해 보고 싶어", "밤바다 보면서 가사 쓰는 중", "언젠가 저 무대에 설 거야" },
			},
		},
	},
	athlete = {
		label = "운동러",
		tones = { like = { "agree", "brag" }, dislike = { "honest" } },
		topics = { "fitness", "sea", "food" },
		errands = { "gs25", "sup" },
		secret = "광안리 SUP존",
		style = "sporty",
		sched = "athlete",
		lines = {
			morning = {
				p = { "아침 러닝 10km 끝! 상쾌해요.", "운동은 아침에 해야 제맛이죠.", "스트레칭은 하고 다니세요?" },
				c = { "같이 뛸래? 해변 한 바퀴!", "오늘 컨디션 최상이야", "단백질 챙겨 먹었어?" },
			},
			day = {
				p = { "점심은 닭가슴살 샐러드예요 ㅎㅎ", "해변 비치발리볼 하실래요?", "오후 PT 수업 있어서 가는 길이에요." },
				c = { "하체 운동 한 다음 날은 계단이 무서워", "오늘 벤치 신기록 찍었다!", "운동은 꾸준함이 전부야" },
			},
			evening = {
				p = { "퇴근 러닝 하는 사람들 많죠?", "운동 끝나고 먹는 한 끼가 최고예요.", "헬스장 사람 많은 시간이라 피해서 나왔어요." },
				c = { "오늘 저녁은 치팅데이다!", "운동 같이 하면 덜 힘들어, 같이 하자", "몸 좋아졌다는 소리 들으면 기분 최고" },
			},
			night = {
				p = { "밤 러닝은 선선해서 좋아요.", "일찍 자야 근육이 자라요.", "밤에 먹으면 안 되는데… 치킨 냄새가." },
				c = { "클럽에서 춤추는 것도 유산소야 ㅋㅋ", "오늘 운동 못 했어… 내일 두 배로 한다", "이 시간에 라면은 반칙이야" },
			},
		},
	},
	parent = {
		label = "육아 부모",
		tones = { like = { "deep", "agree" }, dislike = { "brag" } },
		topics = { "family", "food", "money" },
		errands = { "market", "pharmacy" },
		secret = "광안리해수욕장 (중앙)",
		style = "casual",
		sched = "parent",
		lines = {
			morning = {
				p = { "애들 학교 보내고 이제야 한숨 돌려요.", "아침부터 전쟁이었어요 ㅎㅎ", "커피 한 잔이 유일한 자유예요." },
				c = { "애들 등교시키고 나니까 진이 빠진다", "아침에 도시락 싸느라 정신없었어", "오늘은 나도 좀 쉬고 싶다" },
			},
			day = {
				p = { "유모차 끌고 해변 산책 나왔어요.", "애들이 모래놀이를 너무 좋아해요.", "요즘 육아 정보 좋은 거 있으세요?" },
				c = { "우리 애가 오늘 처음으로 걸었어!!", "애들 낮잠 잘 때가 천국이야", "마트 장보기가 제일 큰 일이야" },
			},
			evening = {
				p = { "저녁 준비하러 들어가야 해요.", "애들이랑 노을 보러 나왔어요.", "오늘 저녁 메뉴 추천 좀 해 주세요." },
				c = { "오늘 저녁은 배달이다, 결심했어", "애들 재우고 드라마 보는 게 낙이야", "오늘은 일찍 들어온대, 다행이다" },
			},
			night = {
				p = { "애들 재우고 잠깐 바람 쐬러 나왔어요.", "밤바다 보는 게 얼마 만인지 몰라요.", "결혼 전엔 저도 클럽 다녔는데 ㅎㅎ" },
				c = { "나도 가끔은 놀고 싶다… 클럽 가 본 게 언제더라", "애들 자는 모습 보면 또 힘이 나", "내일 또 전쟁이다 ㅋㅋ" },
			},
		},
	},
	nightlife = {
		label = "클럽 스태프",
		tones = { like = { "joke", "agree" }, dislike = { "honest" } },
		topics = { "club", "music", "fashion" },
		errands = { "ticket", "coffee" },
		secret = "CLUB OCEAN 광안",
		style = "black",
		sched = "night",
		lines = {
			morning = {
				p = { "이 시간이 저한텐 한밤중이에요 ㅋㅋ", "퇴근하고 해장국 먹으러 가는 길이에요.", "밤새 음료 백 잔은 만든 것 같아요." },
				c = { "나 이제 퇴근이야, 자러 간다", "어젯밤 손님들 진짜 텐션 미쳤어", "해 뜨는 거 보면서 퇴근하는 기분 알아?" },
			},
			day = {
				p = { "낮에는 좀비예요 ㅎㅎ 커피 필수.", "새 음료 레시피 연구 중이에요.", "헬스장 갔다가 출근할 거예요." },
				c = { "오늘 밤 스페셜 음료 만들 거야, 와서 마셔 봐", "낮에 보는 광안리는 또 다르네", "저녁까지 푹 자야 하는데…" },
			},
			evening = {
				p = { "출근 준비 중이에요. 오늘 밤 오실 거죠?", "오늘 클럽 게스트 DJ 대박이에요.", "해 지면 제 시간이 시작돼요." },
				c = { "오늘 밤 오션으로 와, 내가 한 잔 서비스할게", "입장 줄 길어지기 전에 와!", "오늘 VIP 예약 꽉 찼대" },
			},
			night = {
				p = { "지금 한창 바쁠 시간이에요!", "플로어 분위기 최고예요, 들어오세요.", "오늘의 칵테일 드셔 보셨어요?" },
				c = { "오늘 피크 미쳤어, 빨리 들어와!", "바 앞으로 와, 내가 챙겨 줄게", "오늘 밤은 길다!" },
			},
		},
	},
	merchant = {
		label = "상인",
		tones = { like = { "agree", "joke" }, dislike = { "honest" } },
		topics = { "food", "money", "family" },
		errands = { "post", "market" },
		secret = "민락회타운",
		style = "apron",
		sched = "merchant",
		lines = {
			morning = {
				p = { "어서 오이소! 아침부터 손님이네예.", "오늘 물건 좋심더, 구경하고 가이소.", "장사는 아침이 반이라예." },
				c = { "오늘 개시 좀 해 도, 첫 손님이다 아이가!", "요새 경기가 영 아이다.", "아침 뭇나? 이거 하나 무 봐라." },
			},
			day = {
				p = { "하나 더 드릴게예, 맛있게 무이소.", "관광객들이 많아가 좋네예.", "여 광안리에서 장사한 지 삼십 년이라예." },
				c = { "니는 단골이니까 싸게 해 주께.", "오늘은 날이 좋아가 장사가 잘 된다.", "부산 인심 이런 기다 아이가!" },
			},
			evening = {
				p = { "저녁엔 퇴근 손님들이 많아예.", "오늘 다 팔면 일찍 들어갈 낍니더.", "해 지면 불 켜고 또 장사 시작이지예." },
				c = { "떨이다 떨이! 싸게 가 가라.", "오늘 장사 잘 됐다, 기분 좋다!", "저녁은 뭇나? 이거 서비스다." },
			},
			night = {
				p = { "인자 문 닫을 시간입니더.", "밤에는 클럽 가는 젊은이들이 많이 사 가예.", "오늘도 고생했다, 내 자신!" },
				c = { "늦었다, 남은 거 다 가 가라.", "클럽 가기 전에 든든하게 무래이.", "내일 또 온나!" },
			},
		},
	},
	dev = {
		label = "개발자",
		tones = { like = { "curious", "honest" }, dislike = { "brag" } },
		topics = { "games", "coffee", "work" },
		errands = { "coffee", "game" },
		secret = "광안 락볼링클럽 (볼링장)",
		style = "hoodie",
		sched = "dev",
		lines = {
			morning = {
				p = { "카페에서 원격 근무하는 중이에요 💻", "오늘 배포가 있어서 긴장돼요.", "아침에 코딩이 제일 잘 돼요." },
				c = { "어제 버그 잡느라 새벽 세 시에 잤어", "스탠드업 미팅만 없으면 완벽한 아침", "커피 세 잔째… 정상이야" },
			},
			day = {
				p = { "바다 보면서 일하는 게 부산 사는 이유예요.", "요즘 게임 하나 만들고 있어요.", "노트북 배터리가 간당간당해요." },
				c = { "내가 만든 앱 써 볼래? 피드백 줘", "코드가 돌아가는데 왜 돌아가는지 모르겠어 ㅋㅋ", "점심 먹고 PC방 한 판 어때?" },
			},
			evening = {
				p = { "퇴근하고 헬스 가려고요, 거북목이 됐어요.", "오늘 배포 성공! 축하해 주세요.", "저녁엔 게임 한 판이죠." },
				c = { "오늘 야근 없다!! 놀자", "새로 나온 게임 해 봤어?", "클럽은 잘 모르는데… 가 볼까?" },
			},
			night = {
				p = { "밤에 코딩하면 집중이 잘 돼요.", "사이드 프로젝트 하느라 잠을 못 자요.", "밤바다 보면서 머리 식히는 중이에요." },
				c = { "PC방 갈래? 오늘 랭크 올리자", "버그 없는 세상에서 살고 싶다", "오늘 클럽 한번 가 볼까… 인생 경험으로" },
			},
		},
	},
	-- npc_mind: the archetypes the life sim needed (police, the street people, the rich, the shop staff)
	police = {
		label = "경찰",
		tones = { like = { "honest", "agree" }, dislike = { "rude", "tease" } },
		topics = { "work", "family", "fitness" },
		errands = { "post", "map" },
		secret = "광안지구대",
		style = "police",
		sched = "police_day",
		lines = {
			morning = {
				p = { "좋은 아침입니다. 오늘도 안전하게 다니세요.", "아침 순찰 중입니다. 별일 없으시죠?", "출근길 무단횡단은 안 됩니다, 아시죠?" },
				c = { "아침부터 민원 세 건이다… 커피가 필요해.", "오늘 해변 쪽은 조용하네, 다행이다.", "야간조한테 인수인계 받는데 별일 없었대." },
			},
			day = {
				p = { "관광객이 많아서 소매치기 조심하셔야 해요.", "해변에서 분실물 생기면 지구대로 오세요.", "더운데 수분 보충 잘 하세요." },
				c = { "오늘 길 잃은 애 둘이나 찾아 줬다 ㅎㅎ", "점심 먹을 시간도 없네.", "순찰차 에어컨이 또 고장이야." },
			},
			evening = {
				p = { "저녁엔 취객이 많아요. 시비 붙지 마세요.", "해 지면 해변 쪽 사람 많아집니다. 조심하세요.", "드론쇼 날엔 질서 유지가 제일 힘들어요." },
				c = { "오늘 밤 근무만 버티면 비번이다.", "포차 골목 또 시끄럽겠네…", "너도 늦게 다니지 마라, 걱정된다." },
			},
			night = {
				p = { "늦은 시간인데 귀가 안 하세요?", "밤엔 혼자 골목 다니지 마세요.", "야간 순찰 중입니다. 수상한 사람 보면 112." },
				c = { "새벽 세 시가 제일 졸려…", "오늘은 큰 사건 없이 넘어가자, 제발.", "야식으로 국밥 어때? 근무 끝나고." },
			},
		},
	},
	street = {
		label = "노숙자",
		tones = { like = { "agree", "deep" }, dislike = { "brag", "rude" } },
		topics = { "food", "sea", "family" },
		errands = { "gs25", "pharmacy" },
		secret = "민락수변공원",
		style = "shabby",
		sched = "homeless",
		lines = {
			morning = {
				p = { "아침 해가 따뜻해서 살 것 같네요…", "벤치가 차가워서 밤새 못 잤어요.", "편의점 폐기 도시락이라도 있으면…" },
				c = { "오늘은 왠지 좋은 일이 있을 것 같아.", "니가 지나가니까 아침이 덜 춥네.", "갈매기들이 내 아침밥을 노린다 ㅎㅎ" },
			},
			day = {
				p = { "사람들이 다 바빠 보이네요…", "옛날엔 저도 저 빌딩에서 일했어요.", "더울 땐 그늘 찾는 게 일이에요." },
				c = { "오늘 바다가 참 곱다. 돈 없어도 이건 공짜지.", "너 밥은 먹고 다니냐?", "예전 얘기 해 줄까? 나도 왕년엔 말이야…" },
			},
			evening = {
				p = { "해 지면 금방 쌀쌀해져요…", "포장마차 냄새가 너무 좋네요.", "오늘은 어디서 자야 하나…" },
				c = { "노을 볼 때만큼은 부자가 된 기분이야.", "너는 집에 가는 길이냐? 부럽다.", "광안대교 불 켜지면 마음이 좀 놓여." },
			},
			night = {
				p = { "밤엔 바람이 매서워요…", "여긴 제 자리예요. 조용히 좀 쉴게요.", "잠이 안 와서 바다만 보고 있어요." },
				c = { "밤바다 소리 들으면서 자면 꿈이 좋아.", "니도 잠 안 오냐? 같이 바다나 보자.", "추워도 별은 잘 보인다." },
			},
		},
	},
	punk = {
		label = "걸렁뱅이",
		tones = { like = { "joke", "tease" }, dislike = { "deep", "honest", "compliment" } },
		topics = { "games", "money", "club" },
		errands = { "gs25", "game" },
		secret = "광안 PC방",
		style = "punk",
		sched = "punk",
		lines = {
			morning = {
				p = { "아 뭐… 아침부터 왜요.", "아침에 사람 보는 거 별로인데.", "편의점 앞이 내 출근지다 ㅋ" },
				c = { "야 너 아침 먹었냐? 나 좀 사 주라 ㅋㅋ", "어제 밤새 놀았더니 해가 따갑네.", "오늘 뭐 재밌는 거 없냐?" },
			},
			day = {
				p = { "뭘 그렇게 쳐다봐요?", "할 말 있으면 하고.", "여기 우리 구역인 거 알지?" },
				c = { "야 심심한데 뭐 하냐 ㅋㅋ", "니 요즘 좀 컸다? ㅋ", "PC방 갈래? 니가 쏘면 ㅋㅋ" },
			},
			evening = {
				p = { "저녁엔 이 골목 우리가 접수한다.", "어이, 길 막지 말고.", "포차 가는 길이야? 부럽네." },
				c = { "오늘 밤은 좀 놀아 보자고!", "야 너 의리 있는 놈인 거 안다.", "누가 너 건들면 말해라, 내가 해결한다 ㅋ" },
			},
			night = {
				p = { "이 시간에 뭐 하고 다녀?", "밤엔 여기 조용히 지나가는 게 좋을걸.", "아 졸려… 근데 집엔 가기 싫고." },
				c = { "새벽 감성 오지지 않냐 ㅋㅋ", "야 라면 먹으러 갈래?", "너 말고는 다 재미없다." },
			},
		},
	},
	thug = {
		label = "불량배",
		tones = { like = { "brag", "agree" }, dislike = { "tease", "deep", "rude" } },
		topics = { "money", "fitness", "club" },
		errands = { "gs25", "ticket" },
		secret = "광안 공영주차장",
		style = "thug",
		sched = "thug",
		lines = {
			morning = {
				p = { "…아침부터 귀찮게 하지 마.", "어디서 많이 본 얼굴인데.", "볼일 없으면 지나가." },
				c = { "아침부터 형님한테 인사하러 왔냐 ㅋ", "어제 주차장에서 한판 붙을 뻔했다.", "운동 끝나고 국밥 콜?" },
			},
			day = {
				p = { "니 여기 처음 보는 놈이네.", "우리 형님들 지나가신다. 비켜.", "돈 좀 있어 보이네?" },
				c = { "요즘 이 동네 시끄러워. 몸 조심해라.", "니는 우리 편이니까 건들 놈 없다.", "헬스 몇 키로 치냐? ㅋ" },
			},
			evening = {
				p = { "해 졌다. 이제 우리 시간이다.", "어이, 거기. 잠깐 얘기 좀 하자.", "여기서 얼쩡대지 마라." },
				c = { "오늘 밤 클럽 앞에서 보자.", "니 의리 하나는 인정한다.", "형이 오늘 기분 좋다, 뭐 먹을래?" },
			},
			night = {
				p = { "밤길 조심해라. 여긴 무서운 동네다.", "경찰 짭새 없나 망 좀 봐라… 아, 니가 아니지.", "볼일 없으면 꺼져." },
				c = { "새벽엔 우리 형님들 다 모인다.", "니는 내가 지켜 준다. 걱정 마라.", "오늘 일 잘 끝났다. 한잔 콜?" },
			},
		},
	},
	rich = {
		label = "부자",
		tones = { like = { "compliment", "deep" }, dislike = { "joke", "rude", "tease" } },
		topics = { "money", "travel", "fashion" },
		errands = { "coffee", "fish" },
		secret = "테라스타오션",
		style = "luxe",
		sched = "rich",
		lines = {
			morning = {
				p = { "아침엔 요트 정박장에서 커피 한 잔이 루틴이에요.", "오늘 미팅이 세 개나 있네요.", "바다 뷰 펜트하우스는 아침이 제일 예뻐요." },
				c = { "아침 골프 치고 왔더니 피곤하네 ㅎㅎ", "너도 아침에 주식 창 봤어?", "오늘 브런치는 내가 살게." },
			},
			day = {
				p = { "이 근처 건물 몇 개가 제 거예요. 호호.", "명품 매장은 서울보다 부산이 덜 붐벼서 좋아요.", "요즘 부동산이 영 시원찮네요." },
				c = { "돈이 다는 아니더라… 근데 많으면 좋아 ㅋㅋ", "새 차 뽑았는데 주차할 데가 없네.", "너 투자 같은 거 관심 있어?" },
			},
			evening = {
				p = { "저녁은 늘 오마카세로 하는 편이에요.", "광안대교 야경은 우리 집 거실에서 보는 게 최고죠.", "와인 한 잔 하기 좋은 저녁이네요." },
				c = { "오늘 저녁 회 먹으러 갈래? 제일 비싼 걸로.", "요트에서 보는 불꽃축제가 진짜야.", "가끔은 포장마차가 더 맛있더라 ㅎㅎ" },
			},
			night = {
				p = { "밤엔 운전기사가 데리러 와요.", "늦게까지 일하는 사람들 보면 대단해요.", "잠이 안 와서 바다 산책 중이에요." },
				c = { "부자도 잠 안 오는 밤이 있다 ㅋㅋ", "너랑 얘기하면 돈 얘기 안 해도 돼서 좋아.", "다음 주에 요트 파티 할 건데 올래?" },
			},
		},
	},
	clerk = {
		label = "점원 · 알바생",
		tones = { like = { "agree", "joke" }, dislike = { "rude", "brag" } },
		topics = { "work", "food", "money" },
		errands = { "gs25", "coffee" },
		secret = "GS25 광안리점",
		style = "apron",
		sched = "clerk_day",
		lines = {
			morning = {
				p = { "어서 오세요~ 아침 일찍 나오셨네요!", "오픈 준비 중이라 조금만 기다려 주세요.", "아침엔 삼각김밥이 제일 잘 나가요." },
				c = { "아 출근하기 싫었다 ㅠㅠ", "점장님 오늘 기분 좋으셔서 다행이야.", "아침 손님들은 다 조용해서 좋아." },
			},
			day = {
				p = { "점심시간엔 줄이 길어서 정신없어요.", "포인트 적립하시겠어요? ㅎㅎ", "1+1 행사 중인 거 보셨어요?" },
				c = { "진상 손님 왔다 갔어… 멘탈 나감", "알바비 들어오면 뭐 살지 고민 중이야.", "시급 좀 올려 줬으면 ㅠ" },
			},
			evening = {
				p = { "저녁엔 맥주랑 안주가 많이 나가요.", "퇴근 시간 다가오니까 힘이 나네요!", "오늘 신상 디저트 들어왔어요~" },
				c = { "교대하는 애가 또 늦는대… 하", "끝나고 뭐 먹을래? 배고파 죽겠어.", "오늘 손님한테 칭찬받았다 ㅎㅎ" },
			},
			night = {
				p = { "야간에는 손님이 별로 없어서 조용해요.", "심야엔 컵라면이 효자 상품이에요.", "새벽에 취하신 분들 오면 좀 무서워요…" },
				c = { "야간 알바 3주째… 낮밤이 바뀌었어.", "새벽 감성에 폐기 도시락 먹는 중 ㅋㅋ", "너도 이 시간까지 안 자? 같이 버티자." },
			},
		},
	},
}

-------------------------------------------------------------------------------------------------
-- Lines shared by everyone: per tier (std / busan), Busan extras, evening club lures
-------------------------------------------------------------------------------------------------
Citizens.TIER_LINES = {
	[1] = {
		std = { "안녕하세요? 처음 뵙는 것 같네요.", "어… 저요? 무슨 일이세요?", "여기 자주 오세요?" },
		busan = { "누구십니꺼? 처음 보는 얼굴이네예.", "와예? 뭐 물어볼 거 있십니꺼?", "여 자주 오는 사람인교?" },
	},
	[2] = {
		std = { "아, {name}님! 또 뵙네요 😊", "{name}님 안녕하세요! 오늘도 광안리 오셨네요.", "어? {name}님이다! 반가워요." },
		busan = { "아이고 {name}님 아입니꺼! 또 보네예.", "{name}님 왔는교? 반갑심더.", "어, {name}님! 오늘도 나왔네예." },
	},
	[3] = {
		std = { "{name}! 왔어? 😄", "오 {name}, 딱 너 생각하고 있었는데!", "{name} 오늘 좋아 보인다?" },
		busan = { "{name}! 왔나? 😄", "마, {name}! 니 생각하고 있었다 아이가.", "{name} 오늘 얼굴 좋네!" },
	},
	[4] = {
		std = { "{name}~ 보고 싶었어! 💖", "내 친구 {name} 왔다! 오늘 뭐 할까?", "{name}, 너만 보면 기분이 좋아져 ㅋㅋ" },
		busan = { "{name}! 보고 싶었다 아이가~ 💖", "내 친구 {name} 왔네! 오늘 뭐 할끼고?", "{name} 니만 보면 기분 좋다 카이!" },
	},
	[5] = {
		std = { "{name}!!! 내 절친 💞 오늘도 같이 놀자!", "역시 {name}밖에 없어. 알지?", "{name}, 우리 평생 친구 하는 거다!" },
		busan = { "{name}!!! 내 절친 💞 오늘도 같이 놀재이!", "역시 {name}밖에 없다 아이가.", "{name}, 우리 평생 친구 하는 기다!" },
	},
}

-- Tier 1 again (you already met, but they barely know you): replaces the "first time?" lines.
Citizens.TIER_LINES_MET = {
	std = { "아, 아까 그분이시죠? 또 뵙네요.", "또 오셨네요 ㅎㅎ", "어, 또 만났네요?" },
	busan = { "아, 아까 그 사람 아이가? 또 보네예.", "또 왔네예 ㅎㅎ", "어, 또 만났네예?" },
}

Citizens.BUSAN_LINES = {
	morning = { p = { "아침부터 날씨 억수로 좋네예.", "아침은 무셨습니꺼?" }, c = { "오늘 날씨 쥑이네!", "밥은 뭇나?" } },
	day = { p = { "오늘 햇살 장난 아이네예.", "광안리가 부산에서 제일 좋지예." }, c = { "마, 오늘 억수로 덥다 아이가.", "머하노? 심심하나?" } },
	evening = { p = { "노을 보이소, 억수로 예쁘지예?", "저녁은 무셨습니꺼?" }, c = { "노을 봐라, 쥑인다 아이가!", "저녁 뭐 물래?" } },
	night = { p = { "밤바다 바람 좋지예?", "늦었는데 조심해서 들어가이소." }, c = { "오늘 밤 뭐 하노? 놀러 가자!", "늦게까지 머하노 ㅋㅋ" } },
}

Citizens.CLUB_LINES = {
	p = {
		std = { "오늘 밤 클럽 오션 가세요? 라인업 미쳤대요!", "해 지면 다들 클럽 쪽으로 가더라고요 🎶", "클럽 오션 오늘 게스트 DJ 온대요!", "같이 클럽 가실래요? 입구에서 만나요!" },
		busan = { "오늘 밤 클럽 오션 갑니꺼? 라인업 쥑인다 카던데예!", "밤 되면 다들 클럽 쪽으로 가데예 🎶", "같이 클럽 가실랍니꺼? 입구에서 봐예!" },
	},
	c = {
		std = { "오늘 클럽 오션 ㄱ? 라인업 미쳤대!", "이따 클럽 입구에서 보자 🎶", "오늘 밤은 무조건 오션이지!", "클럽 줄 길어지기 전에 가자!" },
		busan = { "오늘 클럽 오션 가나? 라인업 쥑인다 카더라!", "이따 클럽 앞에서 보재이 🎶", "오늘 밤은 무조건 오션이다 아이가!" },
	},
}

-------------------------------------------------------------------------------------------------
-- Conversation topics: questions (p polite / c casual) and three reply options (the player's words)
-- with a tone; effect = "club" turns a yes into a club invitation (evening lure).
-------------------------------------------------------------------------------------------------
Citizens.TOPIC_ORDER = { "food", "sea", "music", "club", "work", "study", "fashion", "games", "travel", "fitness", "baseball", "family", "art", "coffee", "money", "photo" }
Citizens.TOPICS = {
	food = {
		label = "맛집",
		qs = {
			{ p = "광안리 오면 뭐 먹어요? 저는 무조건 돼지국밥이에요!", c = "광안리 오면 뭐 먹어? 난 무조건 돼지국밥!", r = { { tone = "agree", t = "돼지국밥 최고죠! 부산 왔으면 필수!" }, { tone = "curious", t = "숨은 맛집 있으면 알려 주세요!" }, { tone = "brag", t = "저는 미슐랭 식당만 가요." } } },
			{ p = "민락 회타운 가 봤어요? 회가 진짜 싱싱해요.", c = "민락 회타운 가 봤어? 회 진짜 싱싱해.", r = { { tone = "agree", t = "가 봤어요! 광어가 입에서 녹던데요." }, { tone = "joke", t = "회 먹으면 저도 싱싱해질까요? ㅋㅋ" }, { tone = "rude", t = "회는 비린내 나서 별로던데요." } } },
		},
	},
	sea = {
		label = "바다",
		qs = {
			{ p = "오늘 바다 색 좀 봐요. 진짜 예쁘지 않아요?", c = "오늘 바다 색 봐, 진짜 예쁘지?", r = { { tone = "agree", t = "완전 에메랄드색이에요!" }, { tone = "deep", t = "바다 보면 마음이 차분해져요." }, { tone = "rude", t = "그냥 물이잖아요." } } },
			{ p = "서핑이나 SUP 해 봤어요?", c = "서핑이나 SUP 해 봤어?", r = { { tone = "curious", t = "아직요! 알려 주실래요?" }, { tone = "brag", t = "저 서핑 대회 나갔었어요." }, { tone = "joke", t = "저는 물에 뜨는 것만 잘해요 ㅋㅋ" } } },
		},
	},
	music = {
		label = "음악",
		qs = {
			{ p = "요즘 무슨 노래 들어요?", c = "요즘 무슨 노래 들어?", r = { { tone = "curious", t = "추천해 주세요! 뭐 들으세요?" }, { tone = "agree", t = "요즘 EDM에 빠졌어요!" }, { tone = "honest", t = "음악은 잘 안 들어요." } } },
			{ p = "해변에서 버스킹 하는 거 봤어요? 실력 좋던데요.", c = "해변 버스킹 봤어? 실력 좋던데.", r = { { tone = "compliment", t = "봤어요! 목소리 소름이었어요." }, { tone = "joke", t = "저도 노래방에선 가수예요 ㅋㅋ" }, { tone = "rude", t = "시끄럽기만 하던데요." } } },
		},
	},
	club = {
		label = "클럽",
		qs = {
			{ p = "오늘 밤 클럽 오션 갈 거예요?", c = "오늘 밤 클럽 오션 갈 거야?", r = { { tone = "agree", t = "가요! 같이 가요 🎶", effect = "club" }, { tone = "curious", t = "거기 분위기 어때요?" }, { tone = "honest", t = "클럽은 좀 시끄러워서요…" } } },
			{ p = "클럽에서 춤추는 거 좋아해요?", c = "클럽에서 춤추는 거 좋아해?", r = { { tone = "joke", t = "제 춤 보면 다들 놀라요 ㅋㅋ", effect = "club" }, { tone = "agree", t = "좋아요! 오늘 같이 춰요!", effect = "club" }, { tone = "rude", t = "춤추는 사람들 좀 유치하지 않아요?" } } },
		},
	},
	work = {
		label = "일",
		qs = {
			{ p = "요즘 일은 할 만해요?", c = "요즘 일은 할 만해?", r = { { tone = "agree", t = "힘들지만 보람 있어요!" }, { tone = "deep", t = "사실 요즘 진로 고민이 많아요." }, { tone = "brag", t = "저는 곧 사장님 될 거예요." } } },
			{ p = "광안리에서 알바 구하기 쉬워요?", c = "광안리에서 알바 구하기 쉬워?", r = { { tone = "curious", t = "좋은 자리 있으면 알려 주세요!" }, { tone = "agree", t = "편의점이랑 카페 자리 많던데요." }, { tone = "rude", t = "일은 딱 질색이에요." } } },
		},
	},
	study = {
		label = "공부",
		qs = {
			{ p = "공부는 잘 돼요? 저는 시험이라 죽겠어요.", c = "공부 잘 돼? 나 시험이라 죽겠어.", r = { { tone = "agree", t = "저도요! 같이 힘내요." }, { tone = "joke", t = "공부는 내일의 제가 할 거예요 ㅋㅋ" }, { tone = "brag", t = "저는 공부 안 해도 백 점이에요." } } },
			{ p = "나중에 뭐 하고 싶어요?", c = "나중에 뭐 하고 싶어?", r = { { tone = "deep", t = "바다 보이는 집에서 사는 게 꿈이에요." }, { tone = "joke", t = "건물주요! ㅋㅋ" }, { tone = "curious", t = "그쪽은 꿈이 뭐예요?" } } },
		},
	},
	fashion = {
		label = "패션",
		qs = {
			{ p = "오늘 제 옷 어때요? 솔직하게요.", c = "오늘 내 옷 어때? 솔직하게.", r = { { tone = "compliment", t = "완전 잘 어울려요!" }, { tone = "honest", t = "음… 색 조합이 조금 아쉬워요." }, { tone = "rude", t = "좀 촌스러운데요?" } } },
			{ p = "요즘 유행하는 스타일 알아요?", c = "요즘 유행하는 스타일 알아?", r = { { tone = "curious", t = "잘 모르겠어요, 알려 주세요!" }, { tone = "brag", t = "제가 유행을 만들죠." }, { tone = "agree", t = "와이드 팬츠가 대세더라고요." } } },
		},
	},
	games = {
		label = "게임",
		qs = {
			{ p = "게임 좋아해요? 저는 요즘 랭크 올리는 중이에요.", c = "게임 좋아해? 나 요즘 랭크 올리는 중.", r = { { tone = "agree", t = "좋아요! 같이 한 판 해요!" }, { tone = "brag", t = "저 그 게임 최고 티어예요." }, { tone = "honest", t = "게임은 잘 안 해요." } } },
			{ p = "광안 PC방 가 봤어요? 사양 좋던데요.", c = "광안 PC방 가 봤어? 사양 좋던데.", r = { { tone = "curious", t = "거기 라면 맛있어요?" }, { tone = "joke", t = "저는 PC방 가면 라면만 먹어요 ㅋㅋ" }, { tone = "rude", t = "게임은 시간 낭비 아니에요?" } } },
		},
	},
	travel = {
		label = "여행",
		qs = {
			{ p = "부산 말고 가 보고 싶은 데 있어요?", c = "부산 말고 가 보고 싶은 데 있어?", r = { { tone = "deep", t = "제주도요. 바다 보면서 한 달 살아 보고 싶어요." }, { tone = "agree", t = "해외여행 가고 싶어요!" }, { tone = "honest", t = "저는 광안리가 제일 좋아요." } } },
			{ p = "광안대교 드론쇼 봤어요?", c = "광안대교 드론쇼 봤어?", r = { { tone = "compliment", t = "봤어요! 진짜 감동이었어요." }, { tone = "curious", t = "몇 시에 해요? 같이 봐요!" }, { tone = "rude", t = "그거 그냥 불빛 쇼잖아요." } } },
		},
	},
	fitness = {
		label = "운동",
		qs = {
			{ p = "운동 뭐 해요? 저는 해변 러닝해요.", c = "운동 뭐 해? 난 해변 러닝.", r = { { tone = "agree", t = "저도 헬스 다녀요!" }, { tone = "joke", t = "숨쉬기 운동이요 ㅋㅋ" }, { tone = "brag", t = "저 3대 500이에요." } } },
			{ p = "같이 운동하면 덜 힘들대요. 해 볼래요?", c = "같이 운동하면 덜 힘들대. 해 볼래?", r = { { tone = "agree", t = "좋아요! 내일 아침 어때요?" }, { tone = "honest", t = "운동은 혼자가 편해요." }, { tone = "rude", t = "귀찮게 왜 그래요." } } },
		},
	},
	baseball = {
		label = "야구",
		qs = {
			{ p = "어제 야구 봤어요? 아 속 터져요!", c = "어제 야구 봤어? 아 속 터져!", r = { { tone = "agree", t = "봤어요! 9회에 진짜…" }, { tone = "joke", t = "그래도 부산은 야구죠 ㅋㅋ" }, { tone = "rude", t = "야구 재미없던데요." } } },
			{ p = "사직구장 가 봤어요? 응원 열기가 대단해요.", c = "사직 가 봤어? 응원 열기 대박이야.", r = { { tone = "curious", t = "다음에 같이 가요!" }, { tone = "agree", t = "봉다리 응원 해 봤어요!" }, { tone = "honest", t = "사람 많은 데는 좀…" } } },
		},
	},
	family = {
		label = "가족",
		qs = {
			{ p = "가족들이랑은 자주 연락해요?", c = "가족들이랑 자주 연락해?", r = { { tone = "deep", t = "사실 요즘 연락을 잘 못 했어요." }, { tone = "agree", t = "매일 통화해요!" }, { tone = "rude", t = "그런 건 왜 물어요?" } } },
			{ p = "어릴 때 광안리 자주 왔어요?", c = "어릴 때 광안리 자주 왔어?", r = { { tone = "deep", t = "부모님이랑 불꽃축제 보러 왔었어요." }, { tone = "curious", t = "옛날 광안리는 어땠어요?" }, { tone = "honest", t = "여긴 처음이에요." } } },
		},
	},
	art = {
		label = "예술",
		qs = {
			{ p = "그림이나 음악 같은 거 좋아해요?", c = "그림이나 음악 같은 거 좋아해?", r = { { tone = "compliment", t = "예술 하는 사람들 멋있어요." }, { tone = "curious", t = "요즘 뭐 만드세요?" }, { tone = "rude", t = "그걸로 밥 먹고 살 수 있어요?" } } },
			{ p = "광안리 풍경을 한 단어로 하면 뭐예요?", c = "광안리 풍경을 한 단어로 하면 뭐야?", r = { { tone = "deep", t = "위로요." }, { tone = "joke", t = "사진 맛집! ㅋㅋ" }, { tone = "agree", t = "낭만이요." } } },
		},
	},
	coffee = {
		label = "커피",
		qs = {
			{ p = "커피 좋아해요? 아아파예요, 뜨아파예요?", c = "커피 좋아해? 아아파야 뜨아파야?", r = { { tone = "agree", t = "얼죽아요!" }, { tone = "joke", t = "저는 커피 우유파예요 ㅋㅋ" }, { tone = "honest", t = "커피는 잠이 안 와서요." } } },
			{ p = "근처 카페 중에 어디가 제일 좋아요?", c = "근처 카페 중에 어디가 제일 좋아?", r = { { tone = "curious", t = "추천해 주세요!" }, { tone = "compliment", t = "추천해 주는 데면 다 좋을 것 같아요." }, { tone = "brag", t = "저는 카페 투어 백 군데 넘게 다녔어요." } } },
		},
	},
	money = {
		label = "돈",
		qs = {
			{ p = "요즘 물가 너무 비싸지 않아요?", c = "요즘 물가 너무 비싸지 않아?", r = { { tone = "agree", t = "진짜요, 커피값도 무서워요." }, { tone = "deep", t = "그래서 요즘 저축하고 있어요." }, { tone = "brag", t = "저는 별로 상관없던데요?" } } },
			{ p = "광안리에 집 사면 좋겠죠? 바다 뷰로요.", c = "광안리에 집 사면 좋겠지? 바다 뷰로.", r = { { tone = "deep", t = "그게 제 목표예요. 열심히 모으는 중!" }, { tone = "joke", t = "로또 되면 펜트하우스 가요 ㅋㅋ" }, { tone = "curious", t = "부동산 잘 아세요?" } } },
		},
	},
	photo = {
		label = "사진",
		qs = {
			{ p = "사진 찍는 거 좋아해요? 여기 포토스팟 많아요.", c = "사진 찍는 거 좋아해? 여기 포토스팟 많아.", r = { { tone = "agree", t = "좋아요! 같이 찍어요 📸" }, { tone = "compliment", t = "찍어 준 사진은 다 멋있을 것 같아요." }, { tone = "honest", t = "사진은 잘 안 찍어요." } } },
			{ p = "광안대교 야경 사진 잘 찍는 법 알아요?", c = "광안대교 야경 잘 찍는 법 알아?", r = { { tone = "curious", t = "알려 주세요!" }, { tone = "brag", t = "제 사진 전시회도 했어요." }, { tone = "joke", t = "폰 흔들면 예술 사진 돼요 ㅋㅋ" } } },
		},
	},
}

-------------------------------------------------------------------------------------------------
-- Reactions (p polite / c casual / b Busan casual)
-------------------------------------------------------------------------------------------------
Citizens.REACT = {
	love = {
		p = { "와, 저랑 완전 통하시네요! 😆", "맞아요 맞아요! 역시 {name}님 뭘 좀 아시네요.", "헐 대박, 저도 그렇게 생각했어요!" },
		c = { "야 완전 통한다 ㅋㅋㅋ 😆", "역시 너밖에 없다!", "헐 나도 그 생각 했는데!" },
		b = { "마 니 완전 내 스타일이다 아이가! 😆", "맞다 맞다! 역시 니밖에 없다." },
	},
	like = { p = { "오, 좋네요! ㅎㅎ", "그쵸? 저도 그래요." }, c = { "오 좋다 ㅎㅎ", "그치? 나도!" }, b = { "오 좋네! ㅎㅎ", "맞제? 내도 그렇다." } },
	neutral = { p = { "아~ 그렇구나.", "음, 그럴 수도 있겠네요." }, c = { "아~ 그렇구나.", "음 그럴 수도 있지." }, b = { "아~ 그렇나.", "음, 그럴 수도 있제." } },
	meh = { p = { "아… 네에.", "음… 그렇군요 ㅎㅎ;" }, c = { "아… 응.", "음… 그래? ㅎㅎ;" }, b = { "아… 그렇나.", "음… 그래 뭐." } },
	dislike = { p = { "음… 그런 말은 좀 별로네요.", "아, 저랑은 좀 안 맞네요 😅" }, c = { "음… 그건 좀 별로다.", "아 그건 좀 아니지 않나 😅" }, b = { "음… 그건 쫌 아이다.", "아 그건 좀 별로다 😅" } },
	rude = { p = { "…말씀이 좀 심하시네요. 😠", "아, 네. 저 갈게요." }, c = { "야, 말이 좀 심하다? 😠", "…그런 식으로 말하지 마." }, b = { "마, 말 좀 가려서 해라! 😠", "…그라믄 안 되지." } },
	upset = { p = { "…아직 좀 서운해요.", "지금은 별로 얘기하고 싶지 않아요." }, c = { "…아직 좀 서운하다.", "지금은 말하기 싫어." }, b = { "…아직 쫌 서운하다.", "지금은 말하기 싫다." } },
	spam = { p = { "저기요… 너무 자주 말 거시는 거 아니에요? 😑" }, c = { "야… 좀 쉬었다 말 걸어 😑" }, b = { "마, 쫌 쉬었다 말 걸어라 😑" } },
}

Citizens.GIFT_REACT = {
	love = { p = { "헐 {gift}!! 제가 제일 좋아하는 거예요! 😍", "어떻게 알았어요? 진짜 감동이에요 🥹" }, c = { "헐 {gift}!! 나 이거 제일 좋아하는데! 😍", "어떻게 알았어? 완전 감동 🥹" } },
	like = { p = { "와, {gift} 고마워요! 😊", "센스 있으시네요, 잘 쓸게요!" }, c = { "오 {gift}! 고마워 😊", "센스 있다 너 ㅎㅎ" } },
	neutral = { p = { "아, {gift}… 고마워요 ㅎㅎ", "마음만으로도 고마워요." }, c = { "오 {gift}? 고마워 ㅎㅎ", "챙겨 줘서 고마워!" } },
	dislike = { p = { "아… {gift}는 제가 좀… 😅", "마음은 고마운데 이건 좀 별로예요." }, c = { "아… {gift}는 좀… 😅", "고마운데 이건 내 취향 아니야 ㅠ" } },
	refuse = { p = { "마음만 받을게요! 이건 못 받아요 🙏", "어… 이건 제가 받으면 안 될 것 같아요." }, c = { "마음만 받을게! 이건 좀 🙏", "이건 못 받아, 진짜 괜찮아!" } },
	again = { p = { "또 {gift}네요 ㅎㅎ 제가 좋아하는 거 기억하셨구나.", "{gift} 또 주셨네요! 고마워요." }, c = { "또 {gift}다 ㅋㅋ 고마워!", "나 {gift}로 배 터지겠다 ㅋㅋ" } },
	much = { p = { "이렇게 많이 안 주셔도 돼요… 좀 부담스러워요 😅" }, c = { "야, 오늘 너무 많이 줬어… 부담스럽다 😅" } },
	bday = { p = { "제 생일인 거 어떻게 아셨어요?! 너무 감동이에요 🎂" }, c = { "내 생일 기억해 준 거야?! 진짜 감동 🎂" } },
}

-- Compliment reactions (칭찬하기; outcome from Citizens.react(id, "compliment")). again = already
-- complimented today.
Citizens.COMPLIMENT = {
	love = {
		p = { "헉, 진짜요? 그런 말 들으니까 오늘 하루가 다 좋네요 😳", "에이~ 부끄럽게… 근데 기분은 너무 좋아요! ☺️" },
		c = { "야 뭐야~ 부끄럽게 ㅋㅋ 근데 너무 좋다 😳", "헐 진짜? 너 오늘 말 너무 예쁘게 한다 ☺️" },
		b = { "마, 부끄럽구로 와 그라노 ㅋㅋ 근데 기분 억수로 좋다 😳", "진짜가? 니 오늘 말 이쁘게 하네 ☺️" },
	},
	like = {
		p = { "어머, 고마워요 ㅎㅎ", "그렇게 봐 주시니 감사해요 😊" },
		c = { "오 고마워 ㅎㅎ", "그치? 나도 오늘 좀 괜찮은 것 같았어 😎" },
		b = { "오 고맙데이 ㅎㅎ", "맞제? 내도 오늘 좀 괜찮다 싶었다 😎" },
	},
	neutral = { p = { "아, 네… 감사합니다 ㅎㅎ", "하하, 그런가요?" }, c = { "아 그래? 고마워 ㅎㅎ", "ㅋㅋ 갑자기?" }, b = { "아 그렇나? 고맙다 ㅎㅎ", "ㅋㅋ 갑자기 와?" } },
	meh = { p = { "아… 네에 ㅎㅎ;", "음… 갑자기요?" }, c = { "음… 뭐야 갑자기 ㅋㅋ;", "어… 고마워…?" }, b = { "음… 갑자기 와 그라노 ㅋㅋ;", "어… 고맙다…?" } },
	dislike = {
		p = { "음… 입에 발린 말은 좀 별로예요.", "저 그런 말 잘 안 믿어요 😅" },
		c = { "야… 영혼이 없잖아 ㅋㅋ", "그런 말 막 하는 거 별로야 😅" },
		b = { "마, 입에 발린 소리 하지 마라 ㅋㅋ", "그런 말 막 하는 거 별로다 😅" },
	},
	again = { p = { "오늘 벌써 칭찬 들었어요 ㅎㅎ 고마워요!" }, c = { "오늘 칭찬 벌써 들었다니까 ㅋㅋ 고마워!" }, b = { "오늘 칭찬 벌써 들었다 카이 ㅋㅋ 고맙데이!" } },
}

-- Phone number exchange (번호 물어보기).
Citizens.NUMBER = {
	yes = {
		p = { "좋아요! 제 번호 찍어 드릴게요 📱 연락 주세요!", "그래요, 번호 교환해요! 심심할 때 연락해요 😊" },
		c = { "당연하지! 내 번호 저장해 📱", "그래, 번호 교환하자! 연락해 😆" },
		b = { "당연하지! 내 번호 저장해라 📱", "그래, 번호 주께! 연락해래이 😆" },
	},
	no = {
		p = { "음… 번호는 조금 더 친해지면 드릴게요 ㅎㅎ", "아직은 좀… 다음에 또 만나면요!" },
		c = { "번호는 좀 더 친해지고 ㅋㅋ", "다음에 또 보면 줄게!" },
		b = { "번호는 쫌 더 친해지고 주께 ㅋㅋ", "다음에 또 보면 주께!" },
	},
	stranger = { p = { "네? 처음 보는 분한테 번호는 좀… 😅", "저희 오늘 처음 봤잖아요 ㅎㅎ" }, b = { "처음 보는 사람한테 번호는 쫌… 😅" } },
	later = { p = { "아까 물어보셨잖아요 ㅎㅎ 다음에 또 만나면요!" }, c = { "아까 물어봤잖아 ㅋㅋ 다음에!" }, b = { "아까 물어봤다 아이가 ㅋㅋ 다음에!" } },
	already = { p = { "제 번호 이미 있으시잖아요 ㅎㅎ 연락 주세요!" }, c = { "내 번호 벌써 있잖아 ㅋㅋ 연락해!" }, b = { "내 번호 벌써 있다 아이가 ㅋㅋ 연락해라!" } },
}

-------------------------------------------------------------------------------------------------
-- Memory lines ({name} player, {area} where you last met, {gift} last gift)
-------------------------------------------------------------------------------------------------
Citizens.MEMORY = {
	again = { p = "또 만났네요, {name}님 ㅎㅎ", c = "또 보네, {name} ㅎㅎ", b = "또 보네, {name}! ㅎㅎ" },
	today = { p = "아까 {area}에서 봤죠? {name}님!", c = "아까 {area}에서 봤잖아! {name}!", b = "아까 {area}에서 봤제? {name}!" },
	yesterday = { p = "{name}님, 어제 봤던 거 기억나요!", c = "{name}! 어제도 봤지? ㅋㅋ", b = "{name}! 어제도 봤제? ㅋㅋ" },
	days = { p = "{name}님 며칠 만이에요! 잘 지내셨어요?", c = "{name}! 며칠 만이야, 잘 지냈어?", b = "{name}! 며칠 만이고, 잘 지냈나?" },
	long = { p = "{name}님! 진짜 오랜만이에요. 어디 갔었어요?", c = "{name}!! 진짜 오랜만이다. 어디 갔었어?", b = "{name}! 억수로 오랜만이네. 어데 갔더노?" },
	gift = { p = "지난번에 주신 {gift} 진짜 좋았어요!", c = "지난번에 준 {gift} 진짜 좋았어!" },
	dance = { p = "지난번에 같이 춤춘 거 아직도 생각나요 ㅋㅋ", c = "지난번에 같이 춤춘 거 아직도 웃겨 ㅋㅋ" },
	drink = { p = "저번에 음료 사 주신 거 고마웠어요 🧋", c = "저번에 음료 사 준 거 고마웠어 🧋" },
	errand = { p = "저번에 부탁 들어주셔서 진짜 고마웠어요.", c = "저번에 부탁 들어줘서 진짜 고마웠어." },
	home = { p = "{name}님 집 진짜 예쁘더라고요!", c = "너네 집 진짜 예쁘더라!" },
	club = { p = "클럽에서 봤던 거 기억나요? 그날 재밌었죠!", c = "클럽에서 놀았던 거 기억나? 그날 미쳤지!" },
	hangout = { p = "지난번에 같이 다닌 거 즐거웠어요.", c = "저번에 같이 논 거 진짜 재밌었어." },
	broken = { p = "…지난번엔 왜 안 오셨어요? 기다렸는데.", c = "…저번에 왜 안 왔어? 기다렸잖아.", b = "…저번에 와 안 왔노? 기다렸다 아이가." },
	kept = { p = "지난번에 약속 지켜 줘서 고마웠어요!", c = "저번에 약속 지켜 줘서 고마웠어!" },
}
-- last activity (record.lx) -> MEMORY key
Citizens.ACT_MEMORY = { gift = "gift", dance = "dance", drink = "drink", errand = "errand", home = "home", housewarming = "home", club = "club", table = "club", hangout = "hangout", beach = "hangout", meal = "hangout", cafe = "hangout", karaoke = "hangout", bowling = "hangout", promise = "kept" }

-------------------------------------------------------------------------------------------------
-- Texts from friends (casual; b = Busan). {place} = the meeting place label.
-------------------------------------------------------------------------------------------------
Citizens.TEXTS = {
	club = {
		c = { "오늘 밤 클럽 오션 ㄱ? 🎶 입구에서 보자!", "야 오늘 오션 라인업 미쳤대!! 같이 가자 🕺", "이따 클럽 앞에서 만날래? 내가 줄 서 있을게 😎" },
		b = { "오늘 밤 클럽 오션 가자! 입구에서 보재이 🎶", "마, 오늘 오션 라인업 쥑인다 카더라! 같이 가자 🕺" },
	},
	beach = { c = { "바다 산책 갈래? 🌊 해변 가운데서 보자", "날씨 미쳤다, 바다 가자!" }, b = { "바다 보러 가자! 해변에서 보재이 🌊" } },
	meal = { c = { "배고파… 같이 밥 먹을래? 🍔 {place} 어때?", "밥 먹었어? 안 먹었으면 {place}에서 같이 먹자!" }, b = { "밥 뭇나? 안 뭇으면 {place}에서 같이 묵자 🍔" } },
	cafe = { c = { "카페 갈래? {place} 커피 땡긴다 ☕", "커피 수혈하러 가자 ☕ {place}에서 봐!" }, b = { "커피 한잔 하러 가자 ☕ {place}에서 보재이" } },
	karaoke = { c = { "코노 가자!! 목 풀어야 돼 🎤" }, b = { "노래방 가자! 목 좀 풀자 🎤" } },
	bowling = { c = { "볼링 한 게임 콜? 🎳 진 사람이 밥 사기!" }, b = { "볼링 한 게임 하자 🎳 진 사람이 밥 사는 기다!" } },
	help = { c = { "혹시 시간 있어? 부탁 하나만 해도 돼? 🙏 만나서 얘기해 줄게" }, b = { "시간 있나? 부탁 하나만 하자 🙏 만나서 얘기하께" } },
	miss = { c = { "요즘 왜 이렇게 연락이 없어 ㅠㅠ 보고 싶다", "잘 지내? 광안리 오면 연락해!" }, b = { "요새 와 이리 연락이 없노 ㅠ 보고 싶다" } },
	friend = { c = { "우리 이제 진짜 친구다 ㅋㅋ 💖 번호 저장해 놨어!" }, b = { "우리 인자 진짜 친구다 아이가 💖 번호 저장해 놨데이!" } },
	bestie = { c = { "너한테만 알려 주는 비밀 장소가 있어… {place}로 와 줄래? 💞" }, b = { "니한테만 알려 주는 비밀 장소 있다… {place}로 온나 💞" } },
	kept = { c = { "와 줬구나!! 역시 믿고 있었어 🥰" }, b = { "왔나! 역시 니는 올 줄 알았다 🥰" } },
	broken = { c = { "…왜 안 왔어? 한참 기다렸는데 😢" }, b = { "…와 안 왔노? 한참 기다렸다 😢" } },
	bday = { c = { "오늘 내 생일이다!! 🎂 축하해 줄 거지?" }, b = { "오늘 내 생일이다! 🎂 축하해 도!" } },
	secret = { c = { "여기가 내 비밀 장소야. 힘들 때마다 와서 바다 봐. 너한테만 보여 주는 거다 💞" }, b = { "여가 내 비밀 장소다. 힘들 때마다 와서 바다 본다 아이가. 니한테만 보여 주는 기다 💞" } },
}

-------------------------------------------------------------------------------------------------
-- Errands (go to dest, then come back to where they asked). tip = cash thanks (원).
-------------------------------------------------------------------------------------------------
Citizens.ERRANDS = {
	bread = { dest = "빵천동 빵집골목", item = "소금빵", tip = 5000, p = "혹시 빵천동 가면 소금빵 하나만 사다 줄 수 있어요? 🥐", c = "빵천동 가면 소금빵 하나만 사다 줄래? 🥐" },
	gs25 = { dest = "GS25 광안리점", item = "삼각김밥", tip = 3000, p = "GS25에서 삼각김밥 하나만 사다 주실 수 있어요? 배고파서요…", c = "GS25에서 삼각김밥 하나만 사다 줘 ㅠ 배고파" },
	coffee = { dest = "스타벅스 광안리점", item = "아메리카노", tip = 5000, p = "스타벅스 광안리점에서 아아 한 잔만 부탁해도 될까요? ☕", c = "스타벅스 가서 아아 한 잔만 사다 줘 ☕" },
	fish = { dest = "민락어민활어직판장", item = "주문한 회", tip = 8000, p = "민락 활어직판장에 주문해 둔 회 좀 받아다 주실래요?", c = "활어직판장에 주문한 회 좀 받아다 줄래?" },
	post = { dest = "광안동우체국", item = "택배 영수증", tip = 5000, p = "우체국에 택배 좀 부쳐 주실 수 있어요? 📦", c = "우체국에 택배 좀 부쳐 줄래? 📦" },
	pharmacy = { dest = "광안 중앙병원", item = "약 봉투", tip = 4000, p = "중앙병원 앞 약국에서 약 좀 받아다 주실래요? 💊", c = "중앙병원 앞 약국에서 약 좀 받아다 줘 💊" },
	map = { dest = "광안리 관광안내소", item = "관광 지도", tip = 3000, p = "관광안내소에서 지도 한 장만 받아다 주실래요? 🗺️", c = "관광안내소에서 지도 좀 받아다 줘 🗺️" },
	market = { dest = "홈플러스 익스프레스 광안점", item = "장본 것", tip = 6000, p = "홈플러스에서 두부랑 파 좀 사다 주실 수 있어요?", c = "홈플러스에서 두부랑 파 좀 사다 줄래?" },
	burger = { dest = "밀락더마켓", item = "수제버거", tip = 8000, p = "밀락더마켓 수제버거가 너무 먹고 싶은데… 사다 주실래요? 🍔", c = "밀락더마켓 버거 먹고 싶다… 사다 줄래? 🍔" },
	sup = { dest = "해양레포츠센터", item = "보드 대여증", tip = 6000, p = "해양레포츠센터에서 보드 대여증 좀 받아다 주실래요? 🏄", c = "레포츠센터에서 보드 대여증 좀 받아다 줘 🏄" },
	ticket = { dest = "CLUB OCEAN 광안", item = "게스트 팔찌", tip = 5000, p = "클럽 오션 입구에서 게스트 팔찌 좀 받아다 주실래요? 🎟️", c = "클럽 앞에서 게스트 팔찌 좀 받아다 줄래? 🎟️" },
	game = { dest = "광안 PC방", item = "PC방 충전 카드", tip = 3000, p = "PC방 가서 충전 카드 하나만 사다 주실래요? 🎮", c = "PC방 충전 카드 하나만 사다 줘 🎮" },
	salon = { dest = "헤어살롱 & 편집숍", item = "예약권", tip = 4000, p = "헤어살롱에 예약 좀 대신 해 주실래요? 💇", c = "헤어살롱 예약 좀 대신 해 줄래? 💇" },
	church = { dest = "광안교회", item = "주보", tip = 5000, p = "교회 가서 주보 한 장만 받아다 주겠나? 할매가 다리가 아파서…", c = "교회 가서 주보 한 장만 받아 온나. 할매가 다리가 아프다…" },
}

-------------------------------------------------------------------------------------------------
-- Daily schedule templates: { startHour, areaToken, act }. Tokens home / work / eat / cafe / fun /
-- walk resolve to the citizen's own areas; anything else is an area id.
-------------------------------------------------------------------------------------------------
Citizens.SCHEDULES = {
	school = { { 0, "home", "sleep" }, { 7, "walk", "walk" }, { 7.75, "work", "study" }, { 16, "fun", "play" }, { 18, "eat", "eat" }, { 19.5, "walk", "walk" }, { 21.5, "home", "home" } },
	uni = { { 0, "home", "sleep" }, { 9, "cafe", "cafe" }, { 11, "walk", "walk" }, { 13, "eat", "eat" }, { 14, "fun", "walk" }, { 17, "beach_c", "photo" }, { 19, "eat", "eat" }, { 21, "walk", "walk" }, { 23.5, "home", "home" } },
	office = { { 0, "home", "sleep" }, { 7, "station", "walk" }, { 8, "work", "work" }, { 12, "eat", "eat" }, { 13, "work", "work" }, { 18.5, "walk", "walk" }, { 19.5, "eat", "drink" }, { 22, "home", "home" } },
	surf = { { 0, "home", "sleep" }, { 5.5, "sup", "surf" }, { 9, "work", "surf" }, { 12, "eat", "eat" }, { 13, "beach_e", "sunbathe" }, { 16, "sup", "surf" }, { 18.5, "beach_c", "walk" }, { 20, "eat", "drink" }, { 23, "home", "home" } },
	granny = { { 0, "home", "sleep" }, { 5.5, "millak_park", "walk" }, { 7, "work", "shop" }, { 10, "plaza", "sit" }, { 12, "home", "home" }, { 15, "beach_c", "sit" }, { 18, "home", "home" } },
	grandpa = { { 0, "home", "sleep" }, { 5, "millak_park", "fish" }, { 9, "plaza", "sit" }, { 12, "eat", "eat" }, { 14, "beach_w", "walk" }, { 17, "plaza", "sit" }, { 19.5, "home", "home" } },
	tourist = { { 0, "home", "sleep" }, { 8, "eat", "eat" }, { 10, "beach_c", "photo" }, { 12.5, "eat", "eat" }, { 14, "fun", "walk" }, { 17, "beach_c", "photo" }, { 19, "eat", "eat" }, { 20.5, "beach_c", "photo" }, { 23, "home", "home" } },
	dayjob = { { 0, "home", "sleep" }, { 6, "walk", "walk" }, { 7, "work", "work" }, { 15, "cafe", "cafe" }, { 16.5, "walk", "walk" }, { 18, "eat", "eat" }, { 20, "fun", "walk" }, { 23, "home", "home" } },
	latejob = { { 0, "home", "sleep" }, { 10, "cafe", "cafe" }, { 11, "walk", "walk" }, { 12, "work", "work" }, { 17, "eat", "eat" }, { 18, "work", "work" }, { 22, "fun", "walk" }, { 23.5, "home", "home" } },
	night = { { 0, "work", "work" }, { 4, "home", "sleep" }, { 13, "cafe", "cafe" }, { 15, "gym", "gym" }, { 17, "walk", "walk" }, { 19, "work", "work" } },
	fisher = { { 0, "home", "sleep" }, { 3.5, "work", "work" }, { 10, "hoetown", "work" }, { 13, "home", "home" }, { 16, "millak_park", "walk" }, { 18, "hoetown", "drink" }, { 21, "home", "sleep" } },
	taxi = { { 0, "club", "work" }, { 3, "station", "work" }, { 6, "home", "sleep" }, { 13, "plaza", "work" }, { 16, "station", "work" }, { 19, "gwangan_st", "work" }, { 21.5, "club", "work" } },
	rider = { { 0, "home", "sleep" }, { 10, "millak_market", "work" }, { 12, "gwangan_st", "work" }, { 14, "beach_c", "work" }, { 16, "station", "work" }, { 18, "gwangan_st", "work" }, { 20, "beach_c", "work" }, { 22, "club", "work" }, { 23.5, "home", "home" } },
	artist = { { 0, "home", "sleep" }, { 9, "cafe", "cafe" }, { 11, "fun", "paint" }, { 14, "beach_c", "busk" }, { 17, "plaza", "busk" }, { 20, "beach_c", "busk" }, { 22, "gwangan_st", "walk" }, { 23.5, "home", "home" } },
	athlete = { { 0, "home", "sleep" }, { 5.5, "beach_c", "jog" }, { 8, "work", "work" }, { 12, "eat", "eat" }, { 13, "work", "work" }, { 18, "beach_c", "jog" }, { 20, "eat", "eat" }, { 22, "home", "home" } },
	parent = { { 0, "home", "sleep" }, { 8, "school", "walk" }, { 9, "cafe", "cafe" }, { 11, "homeplus", "shop" }, { 13, "home", "home" }, { 15, "beach_c", "walk" }, { 17, "fun", "walk" }, { 19, "home", "home" } },
	merchant = { { 0, "home", "sleep" }, { 6, "work", "work" }, { 13, "eat", "eat" }, { 14, "work", "work" }, { 23, "home", "home" } },
	dev = { { 0, "home", "sleep" }, { 9, "cafe", "work" }, { 12, "eat", "eat" }, { 13, "cafe", "work" }, { 17, "gym", "gym" }, { 19, "eat", "eat" }, { 20, "fun", "play" }, { 23.5, "home", "home" } },
	party = { { 0, "home", "sleep" }, { 12, "cafe", "cafe" }, { 14, "fun", "walk" }, { 17, "beach_c", "walk" }, { 19, "eat", "eat" }, { 20.5, "gwangan_st", "walk" }, { 23, "home", "home" } },
	influencer = { { 0, "home", "sleep" }, { 10, "cafe", "photo" }, { 12, "eat", "eat" }, { 14, "beach_c", "photo" }, { 16, "fun", "shop" }, { 18, "terrace", "photo" }, { 20, "eat", "eat" }, { 22, "gwangan_st", "walk" }, { 23.5, "home", "home" } },
	-- npc_types: the typed citizens' own days, so every type (violent / fool / beggar / drunk) is out on
	-- the street at every hour (the union of each type's 3-4 people covers 24 h; docs/NPC_TYPES.md)
	dawn_jog = { { 0, "home", "sleep" }, { 4.25, "beach_c", "jog" }, { 7.5, "work", "work" }, { 12, "eat", "eat" }, { 13, "work", "work" }, { 18, "beach_c", "jog" }, { 20, "eat", "eat" }, { 22, "home", "home" } },
	sunrise_tour = { { 0, "home", "sleep" }, { 4.25, "beach_c", "photo" }, { 8, "eat", "eat" }, { 10, "beach_c", "photo" }, { 12.5, "eat", "eat" }, { 14, "fun", "walk" }, { 17, "beach_c", "photo" }, { 19, "eat", "eat" }, { 20.5, "beach_c", "photo" }, { 22.5, "home", "home" } },
	night_busk = { { 0, "beach_c", "walk" }, { 2.25, "home", "sleep" }, { 11, "fun", "walk" }, { 14, "beach_c", "busk" }, { 17, "plaza", "busk" }, { 20, "beach_c", "busk" }, { 22.5, "plaza", "walk" } },
	street_night = { { 0, "beach_c", "sit" }, { 2.5, "plaza", "sit" }, { 5.5, "home", "sleep" }, { 13, "beach_w", "sit" }, { 16, "sup", "surf" }, { 19, "eat", "eat" }, { 20.5, "beach_c", "sit" } },
	fisher_nap = { { 0, "home", "sleep" }, { 3.5, "work", "work" }, { 10, "hoetown", "work" }, { 12.5, "millak_park", "sit" }, { 15.5, "beach_w", "walk" }, { 18, "hoetown", "drink" }, { 20.5, "home", "sleep" } },
	sunrise_paint = { { 0, "home", "sleep" }, { 4.5, "beach_c", "paint" }, { 8.5, "eat", "eat" }, { 9.5, "plaza", "sit" }, { 11, "fun", "paint" }, { 14, "beach_c", "paint" }, { 17, "plaza", "sit" }, { 20, "beach_c", "paint" }, { 22, "gwangan_st", "walk" }, { 23.5, "home", "home" } },
	late_office = { { 0, "gwangan_st", "walk" }, { 3, "home", "sleep" }, { 9.5, "work", "work" }, { 12, "eat", "eat" }, { 13, "work", "work" }, { 19, "walk", "walk" }, { 20, "eat", "drink" }, { 21.5, "beach_c", "walk" } },
	-- npc_mind archetypes: police shifts (day + night crews cover 24 h), the street people (always
	-- outside: benches by night), 걸렁뱅이 / 불량배 hanging around the night streets, the rich, shop staff
	police_day = { { 0, "home", "sleep" }, { 7, "work", "work" }, { 9, "plaza", "patrol" }, { 12, "eat", "eat" }, { 13, "beach_c", "patrol" }, { 16, "gwangan_st", "patrol" }, { 18.5, "home", "home" } },
	police_night = { { 0, "club", "patrol" }, { 3, "gwangan_st", "patrol" }, { 6, "home", "sleep" }, { 15, "work", "work" }, { 18, "plaza", "patrol" }, { 21, "beach_c", "patrol" } },
	homeless = { { 0, "plaza", "sit" }, { 6, "millak_park", "sit" }, { 10, "beach_w", "walk" }, { 13, "plaza", "sit" }, { 17, "gs25", "sit" }, { 20, "beach_c", "sit" } },
	homeless_b = { { 0, "beach_c", "sit" }, { 5, "plaza", "sit" }, { 9, "gs25_beach", "walk" }, { 12, "millak_park", "sit" }, { 16, "beach_w", "walk" }, { 19, "plaza", "sit" } },
	punk = { { 0, "gwangan_st", "hangout" }, { 3, "home", "sleep" }, { 11.5, "gs25", "hangout" }, { 14.5, "plaza", "walk" }, { 17.5, "beach_c", "hangout" }, { 20.5, "gwangan_st", "hangout" } },
	punk_late = { { 0, "club", "hangout" }, { 4, "home", "sleep" }, { 13, "gs25", "hangout" }, { 16, "beach_w", "walk" }, { 19, "plaza", "hangout" }, { 22, "gwangan_st", "hangout" } },
	thug = { { 0, "club", "hangout" }, { 3.5, "home", "sleep" }, { 13, "pcbang", "play" }, { 16, "gwangan_st", "walk" }, { 19, "plaza", "hangout" }, { 22, "gwangan_st", "hangout" } },
	rich = { { 0, "home", "sleep" }, { 9, "terrace", "walk" }, { 11, "starbucks_beach", "cafe" }, { 13, "eat", "eat" }, { 15, "beach_e", "walk" }, { 18, "hoetown", "eat" }, { 20.5, "terrace", "walk" }, { 22.5, "home", "home" } },
	clerk_day = { { 0, "home", "sleep" }, { 7.5, "work", "work" }, { 12.5, "eat", "eat" }, { 13.5, "work", "work" }, { 19, "walk", "walk" }, { 21, "home", "home" } },
	alba_night = { { 0, "work", "work" }, { 6, "home", "sleep" }, { 14, "cafe", "cafe" }, { 16, "walk", "walk" }, { 18, "eat", "eat" }, { 20, "work", "work" } },
	drunk_night = { { 0, "gwangan_st", "walk" }, { 2.5, "home", "sleep" }, { 11, "work", "work" }, { 17.5, "eat", "drink" }, { 20, "beach_c", "walk" }, { 22, "gwangan_st", "drink" } },
	fool_day = { { 0, "home", "sleep" }, { 7, "plaza", "walk" }, { 10, "beach_c", "walk" }, { 12, "gs25", "walk" }, { 14, "millak_park", "walk" }, { 17, "plaza", "walk" }, { 20, "gwangan_st", "walk" }, { 23, "home", "home" } },
}

-------------------------------------------------------------------------------------------------
-- THE ROSTER
-- Key NPCs (key = true): server NPCs spawned by GwangalliGameplay/NPC.luau at `post`. The first 11
-- ids are G.NPC_ORDER; the street key NPCs below them are the ids NPC.luau should use for the new
-- 붕어빵 노점 / 버스커 / 사진 관광객 / 안전요원 / 클럽 홍보 / 클럽 가드 figures.
-------------------------------------------------------------------------------------------------
Citizens.LIST = {
	-- key NPCs ------------------------------------------------------------------------------------
	{ id = "gs25_owner", key = true, name = "김사장님", fullName = "김대식", age = 54, g = "m", persona = "merchant", speech = "busan", job = "GS25 광안리점 사장", post = "gs25", accent = { 30, 160, 230 },
		topics = { "money", "work", "baseball" }, love = { "vitamin", "cheer_towel" }, like = { "cat:snack", "tangerine" }, dislike = { "cat:luxury" }, bday = { 4, 3 },
		look = { hair = "short", hc = "gray", style = "apron", skin = 3, build = "broad" },
		sig = { "우리 가게 알바생들은 다 내 자식 같다 아이가.", "삼각김밥 신상 나오면 니한테 제일 먼저 알려 주꾸마." } },
	{ id = "starbucks_mgr", key = true, name = "이점장", fullName = "이수정", age = 34, g = "f", persona = "barista", speech = "std", job = "스타벅스 광안리점 점장", post = "starbucks_beach", accent = { 0, 112, 74 },
		topics = { "coffee", "music", "work" }, love = { "lp", "macaron" }, like = { "cat:dessert", "cat:flower" }, dislike = { "soju" }, bday = { 9, 21 },
		look = { hair = "bun", hc = "darkbrown", style = "apron", skin = 2 },
		sig = { "점장 되고 나서 커피 마실 시간이 없어 ㅋㅋ", "우리 매장 창가 자리가 광안리에서 제일 명당이야." } },
	{ id = "rider_mgr", key = true, name = "박매니저", fullName = "박준혁", age = 36, g = "m", persona = "rider", speech = "std", job = "배달의광안 라이더 허브 매니저", post = "millak_market", accent = { 42, 193, 188 },
		topics = { "work", "food", "money" }, love = { "fishcake", "beer" }, like = { "cat:food" }, dislike = { "cat:flower" }, bday = { 1, 28 },
		look = { hair = "twoblock", hc = "black", style = "rider", skin = 3 },
		sig = { "라이더들 안전이 제일 중요해. 너도 조심히 다녀.", "배달 앱 알림 소리가 꿈에서도 들려 ㅋㅋ" } },
	{ id = "hoe_boss", key = true, name = "최사장님", fullName = "최판석", age = 58, g = "m", persona = "fisher", speech = "busan", job = "민락회타운 횟집 사장", post = "hoetown", accent = { 230, 90, 60 },
		topics = { "food", "sea", "baseball" }, love = { "soju", "cheer_towel" }, like = { "cat:alcohol", "tangerine" }, dislike = { "cat:dessert" }, bday = { 11, 11 },
		look = { hair = "buzz", hc = "gray", style = "chef", skin = 4, build = "broad" },
		sig = { "회는 칼맛이다. 내 칼질 삼십 년이다 아이가.", "니 오면 서비스로 매운탕 끓여 주께." } },
	{ id = "lifeguard_chief", key = true, name = "강팀장", fullName = "강동석", age = 45, g = "m", persona = "athlete", speech = "busan", job = "광안리 수상구조대 팀장", post = "beach_c", accent = { 240, 70, 60 },
		topics = { "sea", "fitness", "family" }, love = { "sunscreen", "vitamin" }, like = { "cat:beach", "americano" }, dislike = { "cat:alcohol" }, bday = { 7, 15 },
		look = { hair = "buzz", hc = "black", style = "lifeguard", acc = "visor", skin = 5, build = "broad" },
		sig = { "바다는 절대 얕보면 안 된다. 명심해래이.", "여름엔 잠잘 시간도 없다 카이." } },
	{ id = "taxi_dispatcher", key = true, name = "윤기사", fullName = "윤성호", age = 57, g = "m", persona = "taxi", speech = "busan", job = "광안운수 택시 배차 담당", post = "plaza", accent = { 250, 180, 20 },
		topics = { "baseball", "money", "travel" }, love = { "americano", "cheer_towel" }, like = { "cat:coffee", "fishcake" }, dislike = { "cat:luxury" }, bday = { 5, 5 },
		look = { hair = "short", hc = "gray", style = "taxi", acc = "cap", skin = 4 },
		sig = { "광안운수 기사님들 실력은 부산 최고다.", "밤에는 클럽 손님 태우느라 정신없다 카이." } },
	{ id = "realtor", key = true, name = "정실장", fullName = "정미경", age = 44, g = "f", persona = "office", speech = "std", job = "광안역 부동산 공인중개사", post = "realty", accent = { 120, 90, 200 },
		topics = { "money", "fashion", "work" }, love = { "bouquet", "wine" }, like = { "cat:flower", "cat:dessert" }, dislike = { "cat:snack" }, bday = { 10, 2 },
		look = { hair = "wave", hc = "darkbrown", style = "suit", skin = 2 },
		sig = { "요즘 광안자이 시세 알아? 나만 믿어.", "펜트하우스 파티 열면 나도 불러 줘 ㅋㅋ" } },
	{ id = "banker", key = true, name = "한주임", fullName = "한지우", age = 29, g = "f", persona = "office", speech = "std", job = "BNK부산은행 광안동지점 주임", post = "bank", accent = { 214, 30, 60 },
		topics = { "money", "coffee", "travel" }, love = { "macaron", "book" }, like = { "cat:dessert", "cat:coffee" }, dislike = { "soju" }, refuse = { "cat:luxury" }, bday = { 2, 14 },
		look = { hair = "bob", hc = "black", style = "suit", skin = 1 },
		sig = { "적금은 꼭 들어 둬. 미래의 너한테 고마워할 거야.", "은행 마감하면 나도 그냥 광안리 좋아하는 사람이야 ㅎㅎ" } },
	{ id = "club_md", key = true, name = "MD 태양", fullName = "이태양", age = 31, g = "m", persona = "nightlife", speech = "std", job = "CLUB OCEAN 광안 MD", post = "club", accent = { 170, 96, 255 },
		topics = { "club", "fashion", "music" }, love = { "club_tee", "perfume" }, like = { "cat:alcohol", "cat:luxury" }, dislike = { "cat:snack" }, bday = { 8, 8 },
		look = { hair = "side", hc = "black", style = "suit", acc = "earpiece", skin = 2, build = "broad" },
		sig = { "오늘 입구 분위기는 내가 다 만든다.", "넌 이제 우리 VIP야. 언제든 말만 해." } },
	{ id = "minji", key = true, name = "민지", fullName = "김민지", age = 24, g = "f", persona = "uni", speech = "std", job = "친구 · 대학원생", post = "plaza", postAct = "hangout", accent = { 255, 122, 162 }, start = 52, club = 0.9, social = 0.9,
		topics = { "club", "photo", "food" }, love = { "latte", "bouquet" }, like = { "cat:dessert", "cat:flower", "club_tee" }, dislike = { "cheer_towel" }, bday = { 6, 12 },
		look = { hair = "long", hc = "brown", style = "casual", night = "dress", acc = "tote", skin = 2 },
		sig = { "광안리 온 거 진짜 잘한 거야. 내가 다 알려 줄게!", "나중에 우리 오션뷰 집에서 파티하자 ㅋㅋ" } },
	{ id = "junho", key = true, name = "준호", fullName = "박준호", age = 25, g = "m", persona = "office", speech = "busan", job = "친구 · 신입사원", post = "plaza", postAct = "hangout", accent = { 88, 160, 255 }, start = 50, club = 0.7, social = 0.85,
		topics = { "fitness", "money", "baseball" }, love = { "beer", "cheer_towel" }, like = { "cat:food", "fishcake" }, dislike = { "cat:flower" }, bday = { 12, 3 },
		look = { hair = "twoblock", hc = "black", style = "casual", night = "streetnight", acc = "cap", skin = 3, build = "broad" },
		sig = { "돈 모아서 광안자이 사는 게 내 꿈이다 아이가.", "치맥은 광안리 모래사장에서 무야 제맛이다!" } },
	{ id = "bungeoppang", key = true, name = "붕어빵 아저씨", fullName = "오만복", age = 63, g = "m", persona = "merchant", speech = "busan", job = "만남의 광장 붕어빵 노점", post = "plaza", accent = { 214, 150, 60 },
		topics = { "food", "family", "baseball" }, love = { "tangerine", "vitamin" }, like = { "cat:health", "cat:coffee" }, dislike = { "cat:luxury" }, bday = { 1, 15 },
		look = { hair = "short", hc = "gray", style = "apron", acc = "cap", skin = 4 },
		sig = { "붕어빵은 꼬리부터 무야 된다 아이가.", "추운 날엔 내 붕어빵이 난로다!" } },
	{ id = "busker", key = true, name = "버스커 하루", fullName = "서하루", age = 24, g = "f", persona = "artist", speech = "std", job = "해변 버스커", post = "beach_c", accent = { 255, 170, 90 },
		topics = { "music", "art", "sea" }, love = { "lp", "bouquet" }, like = { "cat:music", "cat:coffee" }, dislike = { "cat:alcohol" }, bday = { 3, 3 },
		look = { hair = "wave", hc = "brown", style = "artsy", acc = "guitar", skin = 1 },
		sig = { "언젠가 광안리 불꽃축제 무대에 서고 싶어.", "네가 신청한 노래는 내가 제일 좋아하는 곡이야." } },
	{ id = "photo_tourist", key = true, name = "관광객 지수", fullName = "이지수", age = 26, g = "f", persona = "tourist", speech = "std", job = "사진 찍어 주는 서울 관광객", post = "beach_c", accent = { 120, 200, 255 },
		topics = { "photo", "travel", "food" }, love = { "cake", "sunscreen" }, like = { "cat:dessert", "cat:coffee" }, dislike = { "cat:pet" }, bday = { 9, 9 },
		look = { hair = "bob", hc = "brown", style = "tourist", acc = "camera", skin = 1 },
		sig = { "사진 찍어 드릴까요? 제가 인생샷 장인이에요!", "서울 가기 전에 부산 맛집 다 털고 갈 거야." } },
	{ id = "beach_guard", key = true, name = "안전요원 도윤", fullName = "최도윤", age = 23, g = "m", persona = "athlete", speech = "busan", job = "광안리 해변 안전요원", post = "beach_c", accent = { 255, 90, 70 },
		topics = { "sea", "fitness", "games" }, love = { "sunscreen", "vitamin" }, like = { "cat:beach", "americano" }, dislike = { "cat:alcohol" }, bday = { 8, 20 },
		look = { hair = "buzz", hc = "black", style = "lifeguard", acc = "visor", skin = 5 },
		sig = { "수영 금지 구역엔 들어가지 마래이!", "휘슬 부는 거 은근 재밌다 ㅋㅋ" } },
	{ id = "promoter_ray", chatty = true, key = true, name = "홍보 레이", fullName = "정레이", age = 22, g = "m", persona = "djfan", speech = "std", job = "CLUB OCEAN 홍보 크루", post = "plaza", hours = { 18, 2 }, accent = { 190, 110, 255 },
		topics = { "club", "music", "fashion" }, love = { "club_tee", "lp" }, like = { "cat:music", "cat:merch" }, dislike = { "book" }, bday = { 11, 27 },
		look = { hair = "twoblock", hc = "blonde", style = "merch", night = "streetnight", acc = "flyers", skin = 2 },
		sig = { "오늘 밤 오션 안 오면 후회한다니까?", "쿠폰 하나 더 챙겨 줄게, 비밀이야 😎" } },
	{ id = "promoter_nana", chatty = true, key = true, name = "홍보 나나", fullName = "윤나나", age = 23, g = "f", persona = "djfan", speech = "busan", job = "CLUB OCEAN 홍보 크루", post = "beach_c", hours = { 18, 2 }, accent = { 255, 100, 200 },
		topics = { "club", "fashion", "photo" }, love = { "perfume", "club_tee" }, like = { "cat:luxury", "cat:dessert" }, dislike = { "cat:food" }, bday = { 4, 22 },
		look = { hair = "ponytail", hc = "pink", style = "merch", night = "sparkle", acc = "flyers", skin = 2 },
		sig = { "오늘 밤 오션 라인업 쥑인다, 진짜로!", "니는 내가 입구에서 바로 넣어 주께 😎" } },
	{ id = "club_guard", key = true, name = "가드 철민", fullName = "강철민", age = 35, g = "m", persona = "nightlife", speech = "busan", job = "CLUB OCEAN 입구 가드", post = "club", hours = { 19, 4 }, accent = { 90, 90, 110 },
		topics = { "fitness", "club", "family" }, love = { "vitamin", "americano" }, like = { "cat:health", "cat:coffee" }, dislike = { "cat:alcohol" }, bday = { 2, 2 },
		look = { hair = "buzz", hc = "black", style = "black", acc = "earpiece", skin = 3, build = "broad", height = 1.08 },
		sig = { "줄 서세요. 새치기는 안 됩니데이.", "니는 착하니까 특별히 봐준다 ㅋㅋ" } },

	-- citizens: students -----------------------------------------------------------------------------
	{ id = "jiho", name = "김지호", age = 17, g = "m", persona = "hs", speech = "std", job = "고등학교 2학년", home = "station", work = "school", fun = "pcbang", eat = "gs25", club = 0, social = 0.6,
		topics = { "games", "food", "music" }, hate = { "study" }, love = { "game_card", "tteokbokki" }, like = { "cat:snack" }, dislike = { "book" }, bday = { 5, 19 },
		look = { hair = "twoblock", hc = "black", style = "school", acc = "headphones", skin = 2, build = "slim" },
		sig = { "야 오늘 PC방 가서 한 판만 하자, 진짜 한 판만 ㅋㅋ", "시험 망하면 너네 집에 숨겨 줘 ㅋㅋ" } },
	{ id = "yuna", name = "박유나", age = 18, g = "f", persona = "hs", speech = "busan", job = "고3 수험생", home = "samik", work = "school", fun = "bread", eat = "bread", club = 0, social = 0.5,
		topics = { "music", "study", "fashion" }, hate = { "baseball" }, love = { "macaron", "saltbread" }, like = { "cat:dessert" }, dislike = { "fishcake" }, bday = { 10, 27 },
		look = { hair = "long", hc = "black", style = "school", acc = "tote", skin = 1 },
		sig = { "수능 끝나면 서울 콘서트 갈 끼다!", "니랑 얘기하면 공부 스트레스가 쫌 풀린다." } },
	{ id = "minjae", name = "이민재", age = 17, g = "m", persona = "hs", speech = "busan", job = "고등학교 축구부", home = "suyeong_stn", work = "school", fun = "beach_c", eat = "gwangan_st", club = 0, social = 0.7,
		topics = { "fitness", "games", "baseball" }, hate = { "art" }, love = { "tteokbokki", "cheer_towel" }, like = { "cat:snack", "vitamin" }, dislike = { "cat:flower" }, bday = { 7, 2 },
		look = { hair = "buzz", hc = "black", style = "sporty", skin = 4 },
		sig = { "오늘 연습 끝나고 해변에서 공 차자!", "내 꿈은 국가대표다, 두고 봐라." } },
	{ id = "chaewon", chatty = true, name = "정채원", age = 18, g = "f", persona = "hs", speech = "std", job = "고등학교 댄스부", home = "xi", work = "school", fun = "karaoke", eat = "gs25", club = 0, social = 0.8,
		topics = { "music", "fashion", "club" }, hate = { "money" }, love = { "macaron", "lp" }, like = { "cat:dessert", "club_tee" }, dislike = { "cat:food" }, bday = { 12, 24 },
		look = { hair = "ponytail", hc = "darkbrown", style = "school", acc = "headphones", skin = 2 },
		sig = { "스무 살 되면 클럽 오션 무대에서 춤출 거야!", "새 안무 연습 중인데 봐 줄래?" } },
	-- university -------------------------------------------------------------------------------------
	{ id = "seoyeon", name = "이서연", age = 22, g = "f", persona = "uni", speech = "std", job = "대학생 (광고홍보학과)", home = "station", eat = "bronx", fun = "beach_c", club = 0.8, social = 0.75,
		topics = { "photo", "fashion", "club" }, hate = { "baseball" }, love = { "latte", "macaron" }, like = { "cat:flower", "cat:dessert" }, dislike = { "soju" }, bday = { 3, 14 },
		look = { hair = "long", hc = "brown", style = "street", night = "dress", acc = "tote", skin = 2 },
		sig = { "우리 과제 핑계로 카페 투어 하자 ㅋㅋ", "너랑 찍은 사진이 제일 잘 나와." } },
	{ id = "dohyun", name = "최도현", age = 24, g = "m", persona = "uni", speech = "busan", job = "복학생 (기계공학과)", home = "suyeong_stn", eat = "gwangan_st", cafe = "starbucks_beach", fun = "pcbang", club = 0.7, social = 0.65,
		topics = { "games", "fitness", "baseball" }, hate = { "fashion" }, love = { "beer", "game_card" }, like = { "cat:food", "cheer_towel" }, dislike = { "cat:flower" }, bday = { 9, 2 },
		look = { hair = "short", hc = "black", style = "hoodie", night = "streetnight", skin = 3 },
		sig = { "군대 다녀오니까 광안리가 더 좋아 보인다 아이가.", "복학하니까 동기들이 다 선배다 ㅋㅋ" } },
	{ id = "haeun", name = "강하은", age = 21, g = "f", persona = "uni", speech = "std", job = "미대생", home = "jwell", eat = "bread", fun = "namcheon_park", club = 0.6, social = 0.6,
		topics = { "art", "photo", "coffee" }, hate = { "money" }, love = { "book", "lp" }, like = { "cat:flower", "cat:coffee" }, dislike = { "cat:alcohol" }, bday = { 1, 9 },
		look = { hair = "bob", hc = "ash", style = "artsy", night = "jacket", acc = "sketchbook", skin = 1 },
		sig = { "언젠가 너를 그려 줄게. 모델료는 커피로 ㅋㅋ", "광안리 노을 색은 물감으로 못 만들어." } },
	{ id = "jimin_u", chatty = true, type = "fool", name = "윤지민", age = 23, g = "m", persona = "uni", speech = "std", job = "대학 댄스동아리 회장", home = "station", eat = "gwangan_st", fun = "plaza", club = 0.95, social = 0.85,
		topics = { "club", "music", "fitness" }, hate = { "study" }, love = { "club_tee", "beer" }, like = { "cat:music", "cat:merch" }, dislike = { "book" }, bday = { 6, 30 },
		look = { hair = "perm", hc = "brown", style = "street", night = "streetnight", acc = "cap", skin = 2 },
		sig = { "오늘 플로어 찢으러 가자! 🕺", "우리 동아리 공연 보러 와, 맨 앞자리 맡아 줄게." } },
	{ id = "sua", name = "한수아", age = 20, g = "f", persona = "uni", speech = "busan", job = "대학 신입생", home = "samik", eat = "bread", fun = "beach_e", club = 0.5, social = 0.7,
		topics = { "food", "travel", "music" }, hate = { "work" }, love = { "saltbread", "cake" }, like = { "cat:dessert", "rose" }, dislike = { "soju" }, bday = { 4, 7 },
		look = { hair = "long", hc = "darkbrown", style = "casual", night = "dress", skin = 2 },
		sig = { "대학 오니까 신기한 게 억수로 많다!", "첫 클럽은 니랑 가고 싶다 ㅋㅋ" } },
	{ id = "hyunwoo", chatty = true, name = "오현우", age = 25, g = "m", persona = "uni", speech = "std", job = "취업 준비생", home = "station6", eat = "gs25", cafe = "starbucks_beach", fun = "beach_w", club = 0.4, social = 0.5,
		topics = { "work", "money", "study" }, hate = { "fashion" }, love = { "americano", "book" }, like = { "cat:coffee" }, dislike = { "cat:luxury" }, bday = { 11, 5 },
		look = { hair = "side", hc = "black", style = "casual", night = "jacket", acc = "backpack", skin = 2 },
		sig = { "면접 붙으면 내가 제일 먼저 너한테 말할게.", "요즘 자소서만 백 장 쓴 것 같아…" } },
	{ id = "yerin", name = "서예린", age = 22, g = "f", persona = "uni", speech = "std", job = "교환학생 준비생", home = "xi", eat = "bronx", fun = "info", club = 0.7, social = 0.75,
		topics = { "travel", "music", "coffee" }, hate = { "baseball" }, love = { "bouquet", "latte" }, like = { "cat:flower", "book" }, dislike = { "cat:pet" }, bday = { 8, 15 },
		look = { hair = "wave", hc = "brown", style = "casual", night = "sparkle", acc = "tote", skin = 2 },
		sig = { "교환학생 가면 광안리가 제일 그리울 것 같아.", "외국 친구들한테 부산 자랑 엄청 할 거야!" } },
	-- office workers --------------------------------------------------------------------------------
	{ id = "taehoon", type = "drunk", name = "정태훈", age = 31, g = "m", persona = "office", speech = "busan", job = "증권사 대리", home = "xi", work = "bank", eat = "gwangan_st", cafe = "starbucks_beach", club = 0.5, social = 0.55,
		topics = { "money", "baseball", "work" }, hate = { "art" }, love = { "wine", "cheer_towel" }, like = { "cat:alcohol", "americano" }, dislike = { "cat:pet" }, bday = { 2, 20 },
		look = { hair = "side", hc = "black", style = "office", night = "suit", skin = 3 },
		sig = { "주식은 광안리 파도 같다 아이가. 오르고 내리고.", "월급날엔 내가 쏜다, 회 먹으러 가자!" } },
	{ id = "soyoung", name = "김소영", age = 29, g = "f", persona = "office", speech = "std", job = "방송 작가", home = "jwell", work = "kbs", eat = "bread", fun = "namcheon_park", club = 0.6, social = 0.7,
		topics = { "art", "travel", "coffee" }, hate = { "games" }, love = { "book", "latte" }, like = { "cat:coffee", "cat:flower" }, dislike = { "game_card" }, bday = { 5, 27 },
		look = { hair = "bob", hc = "darkbrown", style = "office", night = "black", acc = "glasses", skin = 1 },
		sig = { "너 얘기로 방송 대본 하나 쓸 수 있을 것 같아 ㅋㅋ", "마감 끝나면 무조건 바다 보러 와." } },
	{ id = "jaewon", type = "drunk", sched = "late_office", name = "박재원", age = 34, g = "m", persona = "office", speech = "std", job = "IT 회사 과장", home = "terrace", work = "kbs", eat = "gwangan_st", cafe = "starbucks_beach", fun = "bowling", club = 0, social = 0.5,
		topics = { "work", "games", "money" }, hate = { "fashion" }, love = { "game_card", "americano" }, like = { "cat:coffee", "cat:game" }, dislike = { "cat:flower" }, bday = { 10, 10 },
		look = { hair = "short", hc = "black", style = "office", night = "jacket", acc = "glasses", skin = 2, build = "broad" },
		sig = { "회의가 회의를 낳는 회사야 ㅋㅋ", "주말엔 볼링이 내 힐링이야." } },
	{ id = "eunji", name = "이은지", age = 27, g = "f", persona = "office", speech = "busan", job = "켄트호텔 프런트 직원", home = "station", work = "kent", eat = "bronx", club = 0.8, social = 0.8,
		topics = { "travel", "fashion", "food" }, hate = { "money" }, love = { "perfume", "macaron" }, like = { "cat:luxury", "cat:dessert" }, dislike = { "cheer_towel" }, bday = { 7, 28 },
		look = { hair = "bun", hc = "brown", style = "uniform", night = "dress", skin = 2 },
		sig = { "호텔 손님들 광안리 오면 다 반한다 아이가.", "퇴근하면 바로 클럽 가는 기 내 루틴이다 ㅋㅋ" } },
	{ id = "sungmin", name = "최성민", age = 38, g = "m", persona = "office", speech = "busan", job = "보험 설계사", home = "xi", work = "realty", eat = "gwangan_st", cafe = "starbucks_beach", fun = "plaza", club = 0.2, social = 0.6,
		topics = { "money", "family", "baseball" }, hate = { "games" }, love = { "fishcake", "soju" }, like = { "cat:food", "cat:alcohol" }, dislike = { "cat:dessert" }, bday = { 3, 30 },
		look = { hair = "side", hc = "black", style = "suit", night = "suit", skin = 3 },
		sig = { "보험 하나 들어라~ 농담이다 ㅋㅋ", "딸내미 사진 볼래? 억수로 예쁘다." } },
	{ id = "nari", name = "조나리", age = 26, g = "f", persona = "office", speech = "std", job = "마케터", home = "terrace", work = "kbs", eat = "bronx", fun = "terrace", club = 0.9, social = 0.85,
		topics = { "fashion", "club", "photo" }, hate = { "baseball" }, love = { "club_tee", "perfume" }, like = { "cat:luxury", "cat:flower" }, dislike = { "fishcake" }, bday = { 12, 12 },
		look = { hair = "long", hc = "ash", style = "trendy", night = "sparkle", acc = "sunglasses", skin = 2 },
		sig = { "우리 회사 캠페인 광안리에서 찍을 거야!", "오늘 밤 오션에서 불태우자 🔥" } },
	{ id = "kyungsoo", type = "violent", name = "문경수", age = 45, g = "m", persona = "office", speech = "busan", job = "우체국 공무원", home = "xi", work = "post", eat = "gwangan_st", cafe = "starbucks_beach", fun = "millak_park", club = 0, social = 0.4,
		topics = { "family", "baseball", "sea" }, hate = { "club" }, love = { "tangerine", "cheer_towel" }, like = { "cat:fruit", "cat:health" }, dislike = { "cat:alcohol" }, refuse = { "cat:luxury" }, bday = { 6, 6 },
		look = { hair = "side", hc = "gray", style = "office", acc = "glasses", skin = 3 },
		sig = { "택배 보낼 때는 주소 꼭 두 번 확인해래이.", "주말엔 딸이랑 민락 공원 산책한다." } },
	-- surfers ---------------------------------------------------------------------------------------
	{ id = "wave_jun", name = "송준", age = 28, g = "m", persona = "surfer", speech = "busan", job = "서핑 강사", home = "samik", work = "leports", eat = "bronx", fun = "sup", club = 0.5, social = 0.7,
		topics = { "sea", "fitness", "travel" }, hate = { "work" }, love = { "surf_wax", "beer" }, like = { "cat:beach", "cat:alcohol" }, dislike = { "cat:luxury" }, bday = { 8, 1 },
		look = { hair = "wave", hc = "brown", style = "surf", night = "streetnight", acc = "surfboard", skin = 5 },
		sig = { "다음에 새벽 파도 같이 타자. 내가 제대로 가르쳐 주께.", "파도 없는 날은 인생이 심심하다 아이가." } },
	{ id = "dahee", name = "임다희", age = 26, g = "f", persona = "surfer", speech = "std", job = "간호사 · 서핑 동호회", home = "jwell", work = "hospital", eat = "bronx", fun = "sup", club = 0.6, social = 0.7,
		topics = { "sea", "fitness", "photo" }, hate = { "money" }, love = { "sunscreen", "surf_wax" }, like = { "cat:beach", "latte" }, dislike = { "cat:alcohol" }, bday = { 5, 3 },
		look = { hair = "ponytail", hc = "brown", style = "surf", night = "dress", acc = "surfboard", skin = 4 },
		sig = { "야간 근무 끝나고 타는 파도가 최고야.", "병원에선 진지한데 바다에선 완전 딴 사람이야 ㅋㅋ" } },
	{ id = "hyuk", type = "violent", name = "배혁", age = 32, g = "m", persona = "surfer", speech = "busan", job = "서핑숍 사장", home = "samik", work = "sup", eat = "bronx", fun = "leports", club = 0.3, social = 0.6,
		topics = { "sea", "money", "travel" }, hate = { "games" }, love = { "surf_wax", "soju" }, like = { "cat:beach", "fishcake" }, dislike = { "cat:dessert" }, bday = { 9, 17 },
		look = { hair = "long", hc = "blonde", style = "surf", night = "streetnight", acc = "bucket_hat", skin = 5, build = "broad" },
		sig = { "우리 숍 보드 빌리러 오면 할인해 주꾸마.", "발리에서 서핑하던 시절이 그립다." } },
	-- grandparents ----------------------------------------------------------------------------------
	{ id = "grandma_bok", name = "박복순", age = 72, g = "f", persona = "grandma", speech = "busan", job = "민락 토박이 할매", home = "hoetown", work = "fishmarket", fun = "plaza", club = 0, social = 0.8,
		topics = { "family", "food", "sea" }, hate = { "games" }, love = { "tangerine", "vitamin" }, like = { "cat:fruit", "cat:health", "rose" }, dislike = { "cat:alcohol", "game_card" }, bday = { 2, 8 },
		look = { hair = "granny_perm", hc = "gray", style = "granny", acc = "cane", skin = 3, height = 0.92 },
		sig = { "니 오면 할매가 부침개 부쳐 주꾸마.", "우리 영감 살아 있을 때 여서 매일 산책했다." } },
	{ id = "grandma_mal", chatty = true, name = "김말순", age = 68, g = "f", persona = "grandma", speech = "busan", job = "시니어 댄스 교실 회원", home = "xi", work = "homeplus", fun = "plaza", club = 0.15, social = 0.9,
		topics = { "music", "family", "fitness" }, hate = { "money" }, love = { "lp", "rose" }, like = { "cat:music", "cat:flower", "vitamin" }, dislike = { "game_card" }, bday = { 11, 20 },
		look = { hair = "granny_perm", hc = "red", style = "granny", night = "sparkle", acc = "visor", skin = 2, height = 0.93 },
		sig = { "할매도 클럽 간다! 흥은 나이 안 먹는다 아이가!", "시니어 댄스 대회 우승이 내 목표다." } },
	{ id = "grandma_ok", name = "이옥자", age = 75, g = "f", persona = "grandma", speech = "busan", job = "손주 자랑이 취미인 할매", home = "samik", work = "church", fun = "beach_c", club = 0, social = 0.7,
		topics = { "family", "food", "travel" }, hate = { "club" }, love = { "tangerine", "cake" }, like = { "cat:fruit", "cat:dessert" }, dislike = { "cat:alcohol" }, bday = { 4, 30 },
		look = { hair = "granny_perm", hc = "white", style = "granny", acc = "cane", skin = 2, height = 0.9 },
		sig = { "우리 손주가 서울대 갔다 아이가, 들었나?", "니도 우리 손주 같아서 자꾸 챙겨 주고 싶다." } },
	{ id = "grandpa_man", name = "최만수", age = 74, g = "m", persona = "grandpa", speech = "busan", job = "낚시 30년 할배", home = "hoetown", eat = "hoetown", fun = "millak_park", club = 0, social = 0.6,
		topics = { "sea", "family", "baseball" }, hate = { "fashion" }, love = { "soju", "fishcake" }, like = { "cat:alcohol", "cat:food" }, dislike = { "cat:dessert" }, bday = { 10, 15 },
		look = { hair = "bald", hc = "white", style = "grandpa", acc = "bucket_hat", skin = 4 },
		sig = { "다음에 방파제 낚시 같이 가자. 내가 포인트 알려 주꾸마.", "고기는 기다리는 사람한테 온다." } },
	{ id = "grandpa_duk", name = "정덕배", age = 70, g = "m", persona = "grandpa", speech = "busan", job = "야구광 할배", home = "suyeong_stn", eat = "gwangan_st", fun = "plaza", club = 0, social = 0.7,
		topics = { "baseball", "family", "money" }, hate = { "music" }, love = { "cheer_towel", "soju" }, like = { "cat:merch", "cat:alcohol" }, dislike = { "lp" }, bday = { 3, 28 },
		look = { hair = "short", hc = "gray", style = "grandpa", acc = "cap", skin = 3 },
		sig = { "올해는 우승한다! 내 말 믿어라!", "사직 가면 내가 치킨 쏘꾸마." } },
	-- tourists --------------------------------------------------------------------------------------
	{ id = "tour_hana", chatty = true, name = "김하나", age = 27, g = "f", persona = "tourist", speech = "std", job = "서울에서 온 직장인 여행객", home = "kent", eat = "bronx", fun = "info", club = 0.7, social = 0.8,
		topics = { "travel", "food", "photo" }, hate = { "money" }, love = { "fishcake", "saltbread" }, like = { "cat:food", "cat:dessert" }, dislike = { "cat:pet" }, bday = { 1, 21 },
		look = { hair = "long", hc = "brown", style = "tourist", night = "dress", acc = "camera", skin = 1 },
		sig = { "부산 오면 무조건 너한테 연락할게!", "서울 친구들한테 너 자랑했어 ㅋㅋ" } },
	{ id = "tour_minho", chatty = true, type = "fool", sched = "sunrise_tour", name = "이민호", age = 30, g = "m", persona = "tourist", speech = "std", job = "대구에서 온 여행객", home = "homers", eat = "hoetown", fun = "millak_market", club = 0.4, social = 0.6,
		topics = { "food", "baseball", "travel" }, hate = { "fashion" }, love = { "fishcake", "beer" }, like = { "cat:food", "cat:alcohol" }, dislike = { "cat:flower" }, bday = { 7, 7 },
		look = { hair = "short", hc = "black", style = "tourist", night = "jacket", acc = "backpack", skin = 3 },
		sig = { "대구는 바다가 없어서 광안리가 더 좋다!", "다음엔 대구 막창 사 올게." } },
	{ id = "tour_sujin", name = "박수진", age = 24, g = "f", persona = "tourist", speech = "std", job = "광주에서 온 대학생 여행객", home = "aqua", eat = "bronx", fun = "beach_e", club = 0.8, social = 0.8,
		topics = { "photo", "club", "food" }, hate = { "work" }, love = { "cake", "club_tee" }, like = { "cat:dessert", "cat:merch" }, dislike = { "soju" }, bday = { 9, 30 },
		look = { hair = "bob", hc = "pink", style = "tourist", night = "sparkle", acc = "camera", skin = 2 },
		sig = { "친구들이랑 부산 왔는데 네가 제일 재밌어 ㅋㅋ", "오늘 밤 클럽 오션 같이 가자!" } },
	{ id = "tour_dad", name = "윤상철", age = 42, g = "m", persona = "tourist", speech = "std", job = "가족 여행 온 아빠", home = "central_bay", eat = "hoetown", fun = "aqua", club = 0, social = 0.5,
		topics = { "family", "food", "travel" }, hate = { "club" }, love = { "americano", "tangerine" }, like = { "cat:coffee", "cat:fruit" }, dislike = { "cat:alcohol" }, bday = { 12, 1 },
		look = { hair = "side", hc = "black", style = "tourist", acc = "backpack", skin = 3, build = "broad" },
		sig = { "애들이 광안리 또 오자고 난리야.", "아빠 노릇 하느라 휴가가 더 피곤해 ㅋㅋ" } },
	{ id = "emma", chatty = true, name = "엠마", age = 25, g = "f", persona = "foreigner", speech = "std", job = "영국에서 온 여행객", home = "kent", eat = "bronx", club = 0.8, social = 0.85,
		topics = { "travel", "music", "food" }, hate = { "money" }, love = { "tteokbokki", "soju" }, like = { "cat:snack", "cat:alcohol" }, dislike = { "fishcake" }, bday = { 5, 11 },
		look = { hair = "wave", hc = "blonde", style = "tourist", night = "dress", acc = "sunglasses", skin = 1 },
		sig = { "Busan is my second home now! 진짜야!", "영국 가면 너 보고 싶을 거야 ㅠㅠ" } },
	{ id = "kenji", name = "켄지", age = 29, g = "m", persona = "foreigner", speech = "std", job = "일본에서 온 사진작가", home = "homers", eat = "hoetown", fun = "beach_w", club = 0.6, social = 0.65,
		topics = { "photo", "travel", "food" }, hate = { "games" }, love = { "fishcake", "book" }, like = { "cat:food", "cat:book" }, dislike = { "cat:pet" }, bday = { 8, 25 },
		look = { hair = "side", hc = "black", style = "tourist", night = "jacket", acc = "camera", skin = 2 },
		sig = { "광안대교 사진으로 전시회 할 거예요. 너도 초대할게!", "부산 사투리 어려워요… '머하노'는 알아요 ㅋㅋ" } },
	{ id = "lucas", chatty = true, sched = "street_night", name = "루카스", age = 27, g = "m", persona = "foreigner", speech = "std", job = "브라질에서 온 서퍼", home = "aqua", eat = "bronx", fun = "sup", club = 0, social = 0.95,
		topics = { "sea", "club", "music" }, hate = { "work" }, love = { "beer", "surf_wax" }, like = { "cat:alcohol", "cat:beach" }, dislike = { "book" }, bday = { 2, 27 },
		look = { hair = "curly", hc = "darkbrown", style = "surf", night = "streetnight", acc = "surfboard", skin = 5, build = "broad" },
		sig = { "Party tonight? 브라질 스타일로 놀자!", "광안리 파도, 리우만큼 좋아!" } },
	-- baristas / cafe -----------------------------------------------------------------------------------
	{ id = "yujin", name = "한유진", age = 26, g = "f", persona = "barista", speech = "std", job = "홍미당 바리스타", home = "station6", work = "hongmidang", eat = "bread", cafe = "starbucks_beach", club = 0.6, social = 0.7,
		topics = { "coffee", "music", "food" }, hate = { "money" }, love = { "lp", "saltbread" }, like = { "cat:music", "cat:dessert" }, dislike = { "americano" }, bday = { 10, 19 },
		look = { hair = "bun", hc = "brown", style = "apron", night = "jacket", skin = 2 },
		sig = { "너 오면 라떼에 하트 두 개 그려 줄게 ㅋㅋ", "내 꿈은 광안리에 내 카페 차리는 거야." } },
	{ id = "seungho", name = "권승호", age = 29, g = "m", persona = "barista", speech = "busan", job = "스타벅스 바리스타", home = "suyeong_stn", work = "starbucks_beach", eat = "gwangan_st", fun = "beach_w", club = 0.4, social = 0.6,
		topics = { "coffee", "games", "sea" }, hate = { "fashion" }, love = { "game_card", "saltbread" }, like = { "cat:game", "cat:dessert" }, dislike = { "latte" }, bday = { 6, 18 },
		look = { hair = "twoblock", hc = "black", style = "apron", night = "streetnight", skin = 3 },
		sig = { "오늘 사이렌 오더 이백 개 쳐냈다 아이가.", "쉬는 날엔 PC방에서 산다 ㅋㅋ" } },
	-- club people --------------------------------------------------------------------------------------
	{ id = "bora", chatty = true, name = "신보라", age = 24, g = "f", persona = "djfan", speech = "std", job = "EDM 페스티벌 덕후", home = "station", eat = "gwangan_st", fun = "gwangan_st", club = 1, social = 0.9,
		topics = { "club", "music", "fashion" }, hate = { "study" }, love = { "club_tee", "lp" }, like = { "cat:music", "cat:merch" }, dislike = { "book" }, bday = { 7, 19 },
		look = { hair = "long", hc = "pink", style = "street", night = "sparkle", acc = "headphones", skin = 2 },
		sig = { "오늘 드롭 나오면 같이 점프하자!!", "우리 플로어 메이트 하자, 매주!" } },
	{ id = "jay", name = "제이", fullName = "장재혁", age = 26, g = "m", persona = "djfan", speech = "busan", job = "클럽 오션 단골", home = "station6", eat = "gwangan_st", cafe = "starbucks_beach", fun = "gwangan_st", club = 1, social = 0.85,
		topics = { "club", "music", "fitness" }, hate = { "family" }, love = { "club_tee", "beer" }, like = { "cat:alcohol", "cat:music" }, dislike = { "cat:flower" }, bday = { 1, 1 },
		look = { hair = "twoblock", hc = "blonde", style = "street", night = "streetnight", acc = "cap", skin = 3 },
		sig = { "MD 태양 형이랑 친하다 아이가, 내 이름 대라!", "오늘은 해 뜰 때까지 달린다!" } },
	{ id = "mina", name = "백미나", age = 23, g = "f", persona = "djfan", speech = "std", job = "DJ 지망생", home = "jwell", eat = "bronx", fun = "karaoke", club = 0.95, social = 0.8,
		topics = { "music", "club", "art" }, hate = { "money" }, love = { "lp", "macaron" }, like = { "cat:music", "cat:dessert" }, dislike = { "cheer_towel" }, bday = { 11, 14 },
		look = { hair = "bob", hc = "blue", style = "street", night = "black", acc = "headphones", skin = 1 },
		sig = { "언젠가 오션 메인 무대에서 내 셋 틀 거야.", "내 믹스셋 들어 봐, 너한테 제일 먼저 들려주는 거야." } },
	{ id = "luna", chatty = true, name = "루나", fullName = "채루나", age = 25, g = "f", persona = "influencer", speech = "std", job = "팔로워 20만 인플루언서", home = "terrace", eat = "bronx", fun = "salon", club = 0.9, social = 0.7,
		topics = { "photo", "fashion", "food" }, hate = { "baseball" }, love = { "perfume", "bouquet" }, like = { "cat:luxury", "cat:flower" }, dislike = { "fishcake" }, bday = { 3, 8 },
		look = { hair = "long", hc = "ash", style = "trendy", night = "sparkle", acc = "sunglasses", skin = 1 },
		sig = { "너 오늘 내 스토리에 나왔어 ㅋㅋ 반응 좋아!", "진짜 친구는 너뿐이야. 여기선 필터 없는 나야." } },
	{ id = "chanwoo", chatty = true, name = "류찬우", age = 27, g = "m", persona = "influencer", speech = "busan", job = "먹방 유튜버", home = "suyeong_stn", eat = "millak_market", fun = "hoetown", club = 0.8, social = 0.8,
		topics = { "food", "photo", "travel" }, hate = { "fitness" }, love = { "fishcake", "tteokbokki" }, like = { "cat:food", "cat:snack" }, dislike = { "vitamin" }, bday = { 12, 20 },
		look = { hair = "perm", hc = "brown", style = "trendy", night = "jacket", acc = "camera", skin = 3, build = "broad" },
		sig = { "오늘 먹방 조회수 터지면 니 덕이다!", "부산 맛집은 내가 다 꿰고 있다 아이가." } },
	-- sea people -------------------------------------------------------------------------------------
	{ id = "captain_park", type = "drunk", sched = "fisher_nap", name = "박선장", fullName = "박용팔", age = 58, g = "m", persona = "fisher", speech = "busan", job = "고깃배 선장", home = "hoetown", work = "fishmarket", fun = "millak_park", club = 0, social = 0.6,
		topics = { "sea", "food", "money" }, hate = { "fashion" }, love = { "soju", "fishcake" }, like = { "cat:alcohol", "vitamin" }, dislike = { "perfume" }, bday = { 6, 25 },
		look = { hair = "short", hc = "gray", style = "fisher", acc = "bucket_hat", skin = 5, build = "broad" },
		sig = { "다음에 내 배 타고 새벽 바다 나가 보자.", "바다가 내 인생이다 아이가." } },
	{ id = "haenyeo", name = "고순자", age = 64, g = "f", persona = "fisher", speech = "busan", job = "해녀", home = "hoetown", work = "fishmarket", fun = "millak_park", club = 0, social = 0.7,
		topics = { "sea", "family", "food" }, hate = { "games" }, love = { "tangerine", "vitamin" }, like = { "cat:fruit", "cat:health" }, dislike = { "cat:alcohol" }, bday = { 9, 5 },
		look = { hair = "granny_perm", hc = "gray", style = "fisher", skin = 5, height = 0.93 },
		sig = { "물질 사십 년이다. 바다 속은 내가 다 안다.", "오늘 딴 전복 쫌 주까? 니만 준다." } },
	-- drivers / riders ---------------------------------------------------------------------------------
	{ id = "taxi_kim", name = "김기사", fullName = "김동철", age = 55, g = "m", persona = "taxi", speech = "busan", job = "개인택시 기사", home = "suyeong_stn", club = 0, social = 0.6,
		topics = { "baseball", "money", "travel" }, hate = { "art" }, love = { "americano", "cheer_towel" }, like = { "cat:coffee", "vitamin" }, dislike = { "cat:alcohol" }, bday = { 4, 14 },
		look = { hair = "short", hc = "gray", style = "taxi", acc = "cap", skin = 4 },
		sig = { "급할 때 전화해라. 부산 어데든 모셔다 주꾸마.", "택시 운전 이십 년에 안 가 본 골목이 없다." } },
	{ id = "taxi_lee", name = "이기사님", fullName = "이순영", age = 49, g = "f", persona = "taxi", speech = "busan", job = "광안운수 택시 기사", home = "station6", club = 0, social = 0.7,
		topics = { "family", "food", "money" }, hate = { "games" }, love = { "tangerine", "americano" }, like = { "cat:fruit", "cat:coffee" }, dislike = { "cat:alcohol" }, bday = { 8, 11 },
		look = { hair = "bob", hc = "black", style = "taxi", acc = "sunglasses", skin = 3 },
		sig = { "여자 기사라고 얕보면 안 된다, 내가 제일 빠르다 아이가!", "우리 딸도 니 또래다. 밥은 잘 챙기 무라." } },
	{ id = "rider_hoon", name = "조성훈", age = 23, g = "m", persona = "rider", speech = "std", job = "배달 라이더 · 휴학생", home = "station", club = 0.5, social = 0.7,
		topics = { "work", "games", "money" }, hate = { "art" }, love = { "vitamin", "game_card" }, like = { "cat:snack", "cat:game" }, dislike = { "cat:flower" }, bday = { 3, 19 },
		look = { hair = "short", hc = "black", style = "rider", night = "streetnight", acc = "helmet", skin = 3 },
		sig = { "돈 모아서 복학하는 게 목표야.", "배달 가다 너 보이면 손 흔들게!" } },
	{ id = "rider_min", type = "violent", name = "남민석", age = 31, g = "m", persona = "rider", speech = "busan", job = "배달 라이더 5년 차", home = "suyeong_stn", club = 0.3, social = 0.55,
		topics = { "money", "food", "baseball" }, hate = { "fashion" }, love = { "fishcake", "beer" }, like = { "cat:food", "cat:alcohol" }, dislike = { "cat:dessert" }, bday = { 10, 31 },
		look = { hair = "twoblock", hc = "black", style = "rider", night = "jacket", acc = "helmet", skin = 4 },
		sig = { "이 동네 지름길은 내가 다 안다 아이가.", "비 오는 날 배달은 전쟁이다." } },
	-- cooks -----------------------------------------------------------------------------------------
	{ id = "chef_jung", name = "정실장님", fullName = "정민호", age = 36, g = "m", persona = "chef", speech = "busan", job = "민락회타운 횟집 실장", home = "hoetown", work = "hoetown", club = 0.2, social = 0.6,
		topics = { "food", "sea", "work" }, hate = { "games" }, love = { "soju", "fishcake" }, like = { "cat:alcohol", "cat:food" }, dislike = { "cat:dessert" }, bday = { 1, 5 },
		look = { hair = "buzz", hc = "black", style = "chef", skin = 3, build = "broad" },
		sig = { "오늘 들어온 광어는 내가 인정한다.", "니 오면 제일 좋은 부위로 썰어 주꾸마." } },
	{ id = "chef_sera", name = "오세라", age = 30, g = "f", persona = "chef", speech = "std", job = "브롱스 버거 셰프", home = "terrace", work = "bronx", club = 0.5, social = 0.7,
		topics = { "food", "music", "travel" }, hate = { "money" }, love = { "wine", "macaron" }, like = { "cat:alcohol", "cat:dessert" }, dislike = { "cat:snack" }, bday = { 7, 24 },
		look = { hair = "ponytail", hc = "red", style = "chef", night = "black", skin = 2 },
		sig = { "신메뉴 시식단 1호는 너야!", "버거는 빵이 반이야, 진짜로." } },
	-- artists ---------------------------------------------------------------------------------------
	{ id = "painter_woo", chatty = true, sched = "sunrise_paint", name = "우지안", age = 33, g = "m", persona = "artist", speech = "std", job = "해변 화가", home = "jwell", fun = "bread", club = 0.3, social = 0.5,
		topics = { "art", "sea", "coffee" }, hate = { "money" }, love = { "book", "latte" }, like = { "cat:book", "cat:coffee" }, dislike = { "cat:merch" }, bday = { 4, 18 },
		look = { hair = "long", hc = "black", style = "artsy", night = "jacket", acc = "sketchbook", skin = 2 },
		sig = { "너 표정 좋다. 오늘 그림 모델 해 줄래?", "광안리 바다는 매일 색이 달라." } },
	{ id = "singer_yeon", name = "연소희", age = 24, g = "f", persona = "artist", speech = "std", job = "싱어송라이터", home = "station6", fun = "plaza", club = 0.6, social = 0.75,
		topics = { "music", "art", "travel" }, hate = { "baseball" }, love = { "lp", "bouquet" }, like = { "cat:music", "cat:flower" }, dislike = { "cat:alcohol" }, bday = { 12, 8 },
		look = { hair = "wave", hc = "darkbrown", style = "artsy", night = "dress", acc = "guitar", skin = 1 },
		sig = { "너한테 바치는 노래 하나 쓰고 있어 ㅎㅎ", "오늘 버스킹 첫 곡은 네 신청곡으로 할게." } },
	{ id = "dancer_kai", chatty = true, type = "fool", sched = "night_busk", name = "카이", fullName = "김카이", age = 22, g = "m", persona = "artist", speech = "busan", job = "스트릿 댄서", home = "suyeong_stn", fun = "plaza", club = 0, social = 0.85,
		topics = { "music", "club", "fitness" }, hate = { "study" }, love = { "club_tee", "lp" }, like = { "cat:music", "cat:merch" }, dislike = { "book" }, bday = { 5, 25 },
		look = { hair = "twoblock", hc = "blue", style = "street", night = "streetnight", acc = "cap", skin = 4 },
		sig = { "오늘 플로어에서 배틀 한 판 하자!", "춤은 머리로 추는 기 아이다, 심장으로 추는 기다!" } },
	-- sporty ----------------------------------------------------------------------------------------
	{ id = "trainer_gun", type = "violent", sched = "dawn_jog", name = "마건우", age = 30, g = "m", persona = "athlete", speech = "busan", job = "광안 휘트니스 트레이너", home = "station", work = "gym", club = 0.4, social = 0.7,
		topics = { "fitness", "food", "sea" }, hate = { "games" }, love = { "vitamin", "americano" }, like = { "cat:health", "cat:coffee" }, dislike = { "cat:dessert", "cat:alcohol" }, bday = { 11, 2 },
		look = { hair = "buzz", hc = "black", style = "sporty", night = "jacket", skin = 4, build = "broad" },
		sig = { "오늘 하체 하는 날이다, 도망가지 마래이!", "니 자세 많이 좋아졌다, 인정!" } },
	{ id = "runner_hye", name = "윤혜진", age = 28, g = "f", persona = "athlete", speech = "std", job = "물리치료사 · 러닝크루 리더", home = "samik", work = "hospital", club = 0.5, social = 0.8,
		topics = { "fitness", "sea", "travel" }, hate = { "games" }, love = { "vitamin", "sunscreen" }, like = { "cat:health", "cat:beach" }, dislike = { "cat:snack" }, bday = { 6, 2 },
		look = { hair = "ponytail", hc = "black", style = "sporty", night = "dress", acc = "visor", skin = 3 },
		sig = { "토요일 아침 러닝크루 나와! 내가 페이스 맞춰 줄게.", "달리고 나서 보는 바다는 진짜 달라." } },
	{ id = "yoga_sol", name = "한솔", age = 35, g = "f", persona = "athlete", speech = "std", job = "요가 강사", home = "jwell", work = "gym", club = 0.2, social = 0.6,
		topics = { "fitness", "art", "family" }, hate = { "money" }, love = { "bouquet", "book" }, like = { "cat:flower", "cat:book" }, dislike = { "cat:alcohol" }, bday = { 9, 12 },
		look = { hair = "bun", hc = "darkbrown", style = "sporty", night = "dress", skin = 2 },
		sig = { "숨 크게 쉬어 봐. 바다 냄새 좋지?", "해변 선셋 요가 수업 한번 와." } },
	-- parents ---------------------------------------------------------------------------------------
	{ id = "mom_jiyeon", name = "김지연", age = 37, g = "f", persona = "parent", speech = "std", job = "초등학생 둘 엄마", home = "xi", club = 0.1, social = 0.65,
		topics = { "family", "food", "money" }, hate = { "games" }, love = { "cake", "americano" }, like = { "cat:dessert", "cat:coffee" }, dislike = { "cat:alcohol" }, bday = { 3, 2 },
		look = { hair = "bob", hc = "darkbrown", style = "casual", night = "dress", acc = "tote", skin = 2 },
		sig = { "애들 크면 나도 클럽 다시 갈 거야 ㅋㅋ", "너랑 얘기하면 육아 스트레스가 날아가." } },
	{ id = "dad_sangwoo", name = "박상우", age = 40, g = "m", persona = "parent", speech = "busan", job = "육아휴직 중인 아빠", home = "samik", club = 0.1, social = 0.6,
		topics = { "family", "baseball", "food" }, hate = { "fashion" }, love = { "beer", "cheer_towel" }, like = { "cat:alcohol", "cat:food" }, dislike = { "perfume" }, bday = { 8, 30 },
		look = { hair = "short", hc = "black", style = "casual", night = "jacket", acc = "stroller", skin = 3, build = "broad" },
		sig = { "육아휴직 해 보니까 회사가 천국이더라 ㅋㅋ", "우리 딸 첫 마디가 '아빠'였다 아이가!" } },
	{ id = "mom_hyesun", name = "이혜선", age = 34, g = "f", persona = "parent", speech = "busan", job = "워킹맘", home = "station6", club = 0.2, social = 0.7,
		topics = { "family", "food", "travel" }, hate = { "games" }, love = { "macaron", "rose" }, like = { "cat:dessert", "cat:flower" }, dislike = { "cat:alcohol" }, bday = { 10, 24 },
		look = { hair = "ponytail", hc = "brown", style = "casual", night = "dress", acc = "stroller", skin = 2 },
		sig = { "오늘은 남편이 애 본다, 자유다!", "니 보면 내 이십 대 생각난다." } },
	-- night workers -----------------------------------------------------------------------------------
	{ id = "bartender_rio", name = "리오", fullName = "최리오", age = 29, g = "m", persona = "nightlife", speech = "std", job = "CLUB OCEAN 바텐더", home = "station", work = "club", club = 1, social = 0.85,
		topics = { "club", "music", "fashion" }, hate = { "study" }, love = { "wine", "perfume" }, like = { "cat:alcohol", "cat:luxury" }, dislike = { "vitamin" }, bday = { 2, 11 },
		look = { hair = "side", hc = "black", style = "black", night = "black", skin = 2 },
		sig = { "오늘 너만을 위한 시그니처 음료 만들어 줄게.", "바 앞에서 내 이름 부르면 줄 안 서도 돼 ㅋㅋ" } },
	{ id = "staff_yuri", name = "김유리", age = 25, g = "f", persona = "nightlife", speech = "busan", job = "CLUB OCEAN 스태프", home = "station6", work = "club", club = 1, social = 0.8,
		topics = { "club", "fashion", "music" }, hate = { "money" }, love = { "perfume", "macaron" }, like = { "cat:luxury", "cat:dessert" }, dislike = { "fishcake" }, bday = { 6, 9 },
		look = { hair = "long", hc = "red", style = "black", night = "black", acc = "earpiece", skin = 2 },
		sig = { "VIP 테이블 비면 니한테 제일 먼저 연락하꾸마.", "클럽 일은 힘들어도 음악 들으면 다 잊는다." } },
	-- merchants ---------------------------------------------------------------------------------------
	{ id = "vendor_hotteok", chatty = true, name = "호떡 아지매", fullName = "정분이", age = 61, g = "f", persona = "merchant", speech = "busan", job = "씨앗호떡 노점", home = "suyeong_stn", work = "plaza", club = 0, social = 0.8,
		topics = { "food", "family", "money" }, hate = { "club" }, love = { "tangerine", "vitamin" }, like = { "cat:fruit", "cat:health" }, dislike = { "cat:alcohol" }, bday = { 1, 24 },
		look = { hair = "granny_perm", hc = "black", style = "apron", skin = 3 },
		sig = { "호떡은 설탕 흘리지 말고 조심해서 무래이!", "니는 단골이니까 하나 더 넣어 주께." } },
	{ id = "market_ahn", name = "안경숙", age = 55, g = "f", persona = "merchant", speech = "busan", job = "밀락더마켓 과일가게 사장", home = "hoetown", work = "millak_market", club = 0, social = 0.7,
		topics = { "food", "money", "family" }, hate = { "games" }, love = { "vitamin", "rose" }, like = { "cat:health", "cat:flower" }, dislike = { "cat:fruit" }, bday = { 7, 10 },
		look = { hair = "perm", hc = "brown", style = "apron", acc = "visor", skin = 4 },
		sig = { "제철 과일은 내가 제일 잘 안다 아이가.", "니 오면 제일 단 거 골라 주꾸마." } },
	-- tech ------------------------------------------------------------------------------------------
	{ id = "dev_joon", name = "한준영", age = 32, g = "m", persona = "dev", speech = "std", job = "게임 개발자", home = "terrace", eat = "gwangan_st", cafe = "starbucks_beach", fun = "pcbang", club = 0.4, social = 0.6,
		topics = { "games", "coffee", "work" }, hate = { "fashion" }, love = { "game_card", "americano" }, like = { "cat:game", "cat:coffee" }, dislike = { "cat:flower" }, bday = { 4, 1 },
		look = { hair = "side", hc = "black", style = "hoodie", night = "jacket", acc = "laptop", skin = 2 },
		sig = { "내가 만드는 게임에 너를 NPC로 넣을까? ㅋㅋ", "버그 하나 잡을 때마다 광안리 한 바퀴 뛴다." } },
	{ id = "design_ara", name = "설아라", age = 28, g = "f", persona = "dev", speech = "std", job = "UX 디자이너", home = "jwell", eat = "bread", fun = "bowling", club = 0.6, social = 0.75,
		topics = { "art", "coffee", "fashion" }, hate = { "baseball" }, love = { "book", "latte" }, like = { "cat:book", "cat:coffee", "lp" }, dislike = { "fishcake" }, bday = { 11, 29 },
		look = { hair = "bob", hc = "ash", style = "hoodie", night = "jacket", acc = "glasses", skin = 1 },
		sig = { "네 폰 UI 불편한 거 있으면 말해, 내가 고쳐 줄게 ㅋㅋ", "노을 색 조합은 최고의 디자인 레퍼런스야." } },
	-- npc_mind archetypes ---------------------------------------------------------------------------
	-- police (광안지구대): day crew 박종호 / 이수빈, night crew 김민혁 / 최다은. type police: they patrol,
	-- answer reports (GwangalliMind dispatch) and question people about trouble.
	{ id = "cop_park", type = "police", name = "박종호", age = 46, g = "m", persona = "police", speech = "busan", job = "광안지구대 경사", home = "xi", work = "police", eat = "gwangan_st", walk = "beach_c", club = 0, social = 0.55, start = 8,
		topics = { "work", "family", "baseball" }, love = { "fishcake", "vitamin" }, like = { "cat:food", "americano" }, dislike = { "cat:luxury" }, bday = { 3, 14 },
		look = { hair = "buzz", hc = "gray", style = "police", skin = 3, build = "broad" },
		sig = { "이 동네 25년째 지키고 있다 아이가.", "니는 사고 치지 마래이. 내가 다 안다." } },
	{ id = "cop_lee", type = "police", name = "이수빈", age = 31, g = "f", persona = "police", speech = "std", job = "광안지구대 경장", home = "jwell", work = "police", eat = "bronx", walk = "plaza", club = 0, social = 0.65, start = 8,
		topics = { "work", "fitness", "coffee" }, love = { "americano", "saltbread" }, like = { "cat:coffee", "cat:dessert" }, dislike = { "soju" }, bday = { 7, 7 },
		look = { hair = "ponytail", hc = "black", style = "police", skin = 2 },
		sig = { "비번 날엔 해변 러닝해요. 같이 뛸래요?", "제 동기들은 다 서울 갔는데 저는 부산이 좋아요." } },
	{ id = "cop_kim", type = "police", sched = "police_night", name = "김민혁", age = 27, g = "m", persona = "police", speech = "busan", job = "광안지구대 순경 (야간조)", home = "suyeong_stn", work = "police", eat = "gs25", walk = "club", club = 0, social = 0.6, start = 8,
		topics = { "games", "fitness", "food" }, love = { "game_card", "tteokbokki" }, like = { "cat:snack", "cat:game" }, dislike = { "cat:flower" }, bday = { 12, 2 },
		look = { hair = "short", hc = "black", style = "police", skin = 2 },
		sig = { "야간조 하면 컵라면 맛을 알게 된다.", "순경 1년 차라 아직 다 신기하다 아이가." } },
	{ id = "cop_choi", type = "police", sched = "police_night", name = "최다은", age = 29, g = "f", persona = "police", speech = "std", job = "광안지구대 순경 (야간조)", home = "samik", work = "police", eat = "gwangan_st", walk = "beach_c", club = 0, social = 0.6, start = 8,
		topics = { "work", "music", "sea" }, love = { "latte", "lp" }, like = { "cat:music", "cat:coffee" }, dislike = { "cat:alcohol" }, bday = { 10, 21 },
		look = { hair = "bun", hc = "darkbrown", style = "police", skin = 1 },
		sig = { "밤바다 순찰할 때가 제일 좋아요. 조용해서.", "취객 상대하는 법은 학교에서 안 가르쳐 줘요 ㅎㅎ" } },
	-- 노숙자 (type beggar: the 천원만 street people; always outside, naps on the benches at night)
	{ id = "street_kim", chatty = true, type = "beggar", sched = "homeless", name = "김영감", fullName = "김덕수", age = 67, g = "m", persona = "street", speech = "busan", job = "광안리 벤치 터줏대감", home = "plaza", club = 0, social = 0.5, start = 5,
		topics = { "sea", "food", "family" }, love = { "fishcake", "bungeoppang" }, like = { "cat:food", "cat:snack" }, dislike = { "cat:luxury" }, bday = { 2, 9 },
		look = { hair = "bald", hc = "gray", style = "shabby", skin = 4, build = "slim" },
		sig = { "왕년엔 내도 저 빌딩 짓던 사람이다.", "니 같은 놈 만나면 살맛 난다." } },
	{ id = "street_park", chatty = true, type = "beggar", sched = "homeless_b", name = "박씨 아저씨", fullName = "박만석", age = 54, g = "m", persona = "street", speech = "std", job = "해변 떠돌이 · 전직 요리사", home = "beach_c", club = 0, social = 0.55, start = 5,
		topics = { "food", "work", "sea" }, love = { "tteokbokki", "hotteok" }, like = { "cat:snack", "tangerine" }, dislike = { "perfume" }, bday = { 8, 30 },
		look = { hair = "curly", hc = "darkbrown", style = "shabby", skin = 3 },
		sig = { "내가 예전에 호텔 주방에 있었어. 진짜야.", "언젠가 너한테 김치찌개 끓여 줄게." } },
	{ id = "street_oh", chatty = true, type = "beggar", sched = "homeless", name = "오할매", fullName = "오말순", age = 72, g = "f", persona = "street", speech = "busan", job = "폐지 줍는 할매", home = "millak_park", club = 0, social = 0.6, start = 8,
		topics = { "family", "food", "sea" }, love = { "tangerine", "hotteok" }, like = { "cat:fruit", "cat:snack" }, dislike = { "cat:alcohol" }, bday = { 5, 8 },
		look = { hair = "granny_perm", hc = "white", style = "shabby", skin = 3, build = "slim", height = 0.92 },
		sig = { "우리 손주가 니만 하다.", "폐지값이 또 떨어졌다 아이가…" } },
	-- 걸렁뱅이 (type punk: picks on passers-by first: 뭘 봐? / 야 너 잠깐 와봐, backs off or keeps at it)
	{ id = "punk_dongsu", chatty = true, type = "punk", name = "황동수", age = 24, g = "m", persona = "punk", speech = "busan", job = "백수 · 동네 걸렁뱅이", home = "station6", eat = "gs25", fun = "gwangan_st", club = 0.6, social = 0.5, start = 3,
		topics = { "games", "money", "club" }, hate = { "study" }, love = { "game_card", "tteokbokki" }, like = { "cat:snack", "cat:game" }, dislike = { "book", "cat:flower" }, bday = { 1, 17 },
		look = { hair = "twoblock", hc = "blonde", style = "punk", night = "streetnight", skin = 3, build = "slim" },
		sig = { "니는 내가 인정한 몇 안 되는 놈이다.", "다음에 누가 니 건들면 이름만 대라." } },
	{ id = "punk_jjang", chatty = true, type = "punk", sched = "punk_late", name = "짱구", fullName = "장현구", age = 21, g = "m", persona = "punk", speech = "busan", job = "편의점 앞 죽돌이", home = "suyeong_stn", eat = "gs25", fun = "plaza", club = 0.5, social = 0.45, start = 3,
		topics = { "games", "fashion", "money" }, hate = { "work" }, love = { "club_tee", "beer" }, like = { "cat:merch", "cat:snack" }, dislike = { "book" }, bday = { 6, 6 },
		look = { hair = "perm", hc = "red", style = "punk", night = "streetnight", acc = "headphones", skin = 2 },
		sig = { "야 니 진짜 웃긴다 ㅋㅋ 친구 하자.", "내가 이래 보여도 의리는 있다." } },
	{ id = "punk_mira", chatty = true, type = "punk", name = "도미라", age = 23, g = "f", persona = "punk", speech = "std", job = "알바 그만둔 지 3일째", home = "station", eat = "gwangan_st", fun = "beach_w", club = 0.7, social = 0.5, start = 3,
		topics = { "fashion", "music", "club" }, hate = { "study" }, love = { "perfume", "lp" }, like = { "cat:music", "cat:luxury" }, dislike = { "cat:pet" }, bday = { 9, 9 },
		look = { hair = "long", hc = "pink", style = "punk", night = "streetnight", acc = "sunglasses", skin = 1 },
		sig = { "너 생각보다 괜찮은 애네.", "솔직히 시비 거는 것도 심심해서 그래." } },
	-- 불량배 (type thug: groups, intimidation, a shove when you stand up to them)
	{ id = "thug_gang", type = "thug", name = "강태식", age = 28, g = "m", persona = "thug", speech = "busan", job = "광남로 불량배 형님", home = "parking", eat = "gwangan_st", fun = "pcbang", club = 0.7, social = 0.4, start = 0,
		topics = { "money", "fitness", "club" }, hate = { "art" }, love = { "cheer_towel", "fishcake" }, like = { "cat:food", "cat:merch" }, dislike = { "cat:flower", "book" }, bday = { 4, 22 },
		look = { hair = "buzz", hc = "black", style = "thug", night = "black", skin = 4, build = "broad", height = 1.06 },
		sig = { "니는 내 동생이다. 누가 뭐라 하면 말해라.", "이 바닥도 의리가 전부다." } },
	{ id = "thug_seok", type = "thug", name = "윤석구", age = 25, g = "m", persona = "thug", speech = "busan", job = "강태식 똘마니", home = "station6", eat = "gs25", fun = "pcbang", club = 0.6, social = 0.45, start = 0,
		topics = { "games", "money", "fitness" }, hate = { "study" }, love = { "game_card", "beer" }, like = { "cat:game", "cat:snack" }, dislike = { "cat:flower" }, bday = { 11, 23 },
		look = { hair = "short", hc = "black", style = "thug", night = "black", acc = "cap", skin = 3, build = "broad" },
		sig = { "형님이 니 괜찮다 카더라.", "내도 사실 이 짓 오래 할 생각 없다." } },
	{ id = "thug_jun", type = "thug", name = "변준기", age = 22, g = "m", persona = "thug", speech = "std", job = "동네 일진 출신", home = "suyeong_stn", eat = "gwangan_st", fun = "plaza", club = 0.6, social = 0.45, start = 0,
		topics = { "fashion", "money", "club" }, hate = { "family" }, love = { "club_tee", "perfume" }, like = { "cat:merch", "cat:luxury" }, dislike = { "book" }, bday = { 3, 3 },
		look = { hair = "side", hc = "ash", style = "thug", night = "streetnight", acc = "sunglasses", skin = 2 },
		sig = { "너랑 있으면 싸울 일이 없네.", "형들 몰래 공부 다시 해볼까 생각 중이야." } },
	-- 동네바보 (type fool) + 취객 (type drunk): one more of each, always around the plaza / the 먹자골목
	{ id = "fool_mansik", chatty = true, type = "fool", sched = "fool_day", name = "만식이", fullName = "최만식", age = 34, g = "m", persona = "street", speech = "busan", job = "동네 바보 형 · 광장 지킴이", home = "station", club = 0, social = 0.95, start = 12,
		topics = { "sea", "food", "baseball" }, love = { "bungeoppang", "cheer_towel" }, like = { "cat:snack", "cat:merch" }, dislike = { "book" }, bday = { 7, 21 },
		look = { hair = "perm", hc = "black", style = "casual", acc = "cap", skin = 3, build = "broad" },
		sig = { "니는 내 베프다! 히히", "내가 광안대교 불 켜는 사람이다~ 비밀이다!" } },
	{ id = "drunk_bae", type = "drunk", sched = "drunk_night", name = "배부장", fullName = "배상만", age = 52, g = "m", persona = "office", speech = "busan", job = "회식 3차 중인 부장님", home = "xi", work = "kbs", eat = "hoetown", club = 0, social = 0.7, start = 6,
		topics = { "work", "baseball", "family" }, hate = { "games" }, love = { "soju", "fishcake" }, like = { "cat:alcohol", "cat:food" }, dislike = { "cat:game" }, bday = { 9, 30 },
		look = { hair = "side", hc = "gray", style = "office", night = "suit", skin = 4, build = "broad" },
		sig = { "내가 니만 할 때는 말이야… 히끅", "부장 되면 행복할 줄 알았다…" } },
	-- 부자 (type rich: big spenders, polite to the polite, cold to the rude)
	{ id = "rich_madam", type = "rich", name = "한사모님", fullName = "한정숙", age = 55, g = "f", persona = "rich", speech = "busan", job = "광안리 건물주 사모님", home = "terrace", eat = "hoetown", cafe = "starbucks_beach", club = 0, social = 0.55, start = 4,
		topics = { "money", "family", "fashion" }, hate = { "games" }, love = { "perfume", "bouquet" }, like = { "cat:flower", "cat:luxury" }, dislike = { "cat:snack", "soju" }, bday = { 12, 24 },
		look = { hair = "wave", hc = "brown", style = "luxe", skin = 1, acc = "sunglasses" },
		sig = { "우리 건물 1층에 카페 하나 차려 볼래?", "돈 많아도 외로운 건 똑같다." } },
	{ id = "rich_yoon", type = "rich", name = "윤대표", fullName = "윤성재", age = 38, g = "m", persona = "rich", speech = "std", job = "요트 클럽 대표 · 스타트업 엑싯", home = "central_bay", eat = "bronx", cafe = "hongmidang", club = 0.6, social = 0.6, start = 4,
		topics = { "money", "travel", "sea" }, hate = { "baseball" }, love = { "wine", "lp" }, like = { "cat:luxury", "cat:music" }, dislike = { "cat:snack" }, bday = { 2, 2 },
		look = { hair = "side", hc = "black", style = "luxe", night = "suit", acc = "sunglasses", skin = 2 },
		sig = { "엑싯하고 나니까 할 게 요트밖에 없더라 ㅋㅋ", "너 같은 사람한테 투자하고 싶다." } },
	{ id = "rich_heir", type = "rich", name = "정재희", age = 26, g = "f", persona = "rich", speech = "std", job = "재벌 3세 인플루언서", home = "terrace", eat = "bronx", cafe = "starbucks_beach", club = 0.9, social = 0.65, start = 4,
		topics = { "fashion", "travel", "club" }, hate = { "work" }, love = { "perfume", "macaron" }, like = { "cat:luxury", "cat:dessert" }, dislike = { "fishcake", "cat:snack" }, bday = { 5, 1 },
		look = { hair = "long", hc = "blonde", style = "luxe", night = "sparkle", acc = "sunglasses", skin = 1 },
		sig = { "아빠 카드 말고 내 돈으로 살게, 오늘은.", "너랑 있으면 진짜 나로 있을 수 있어." } },
	-- 점원 · 알바생 (persona clerk)
	{ id = "clerk_gs", name = "임하늘", age = 20, g = "f", persona = "clerk", speech = "busan", job = "GS25 광안리점 알바생", home = "station6", work = "gs25", eat = "gs25", cafe = "starbucks_beach", walk = "beach_c", club = 0.3, social = 0.75,
		topics = { "food", "music", "money" }, hate = { "baseball" }, love = { "cake", "macaron" }, like = { "cat:dessert", "cat:coffee" }, dislike = { "soju" }, bday = { 4, 16 },
		look = { hair = "ponytail", hc = "brown", style = "apron", skin = 2 },
		sig = { "폐기 나오면 니 몫 챙겨 둘게 ㅋㅋ", "사장님 몰래 1+1 하나 더 줄까?" } },
	{ id = "alba_night", sched = "alba_night", name = "권태양", age = 23, g = "m", persona = "clerk", speech = "std", job = "편의점 야간 알바 · 휴학생", home = "suyeong_stn", work = "gs25_beach", eat = "gwangan_st", cafe = "hongmidang", walk = "beach_w", club = 0.2, social = 0.6,
		topics = { "games", "study", "food" }, hate = { "fashion" }, love = { "game_card", "americano" }, like = { "cat:coffee", "cat:game" }, dislike = { "perfume" }, bday = { 8, 8 },
		look = { hair = "side", hc = "black", style = "apron", acc = "glasses", skin = 2 },
		sig = { "새벽 세 시에 오는 손님은 다 사연이 있어.", "알바 끝나면 해 뜨는 거 같이 볼래?" } },
	{ id = "clerk_shop", name = "남예슬", age = 27, g = "f", persona = "clerk", speech = "std", job = "헤어살롱 편집숍 점원", home = "jwell", work = "salon", eat = "bread", cafe = "hongmidang", walk = "beach_e", club = 0.6, social = 0.7,
		topics = { "fashion", "music", "coffee" }, hate = { "games" }, love = { "perfume", "rose" }, like = { "cat:flower", "cat:luxury" }, dislike = { "fishcake" }, bday = { 10, 3 },
		look = { hair = "bob", hc = "ash", style = "trendy", night = "dress", skin = 1 },
		sig = { "너한테 어울리는 옷 내가 골라 줄게!", "손님한테 웃는 거 말고 진짜 웃는 건 오랜만이다." } },
}

-------------------------------------------------------------------------------------------------
-- Index + defaults (runs once at require time; pure)
-------------------------------------------------------------------------------------------------
local ACCENTS = {
	{ 255, 122, 162 }, { 88, 160, 255 }, { 255, 196, 0 }, { 120, 220, 160 }, { 255, 150, 90 }, { 190, 120, 255 },
	{ 80, 200, 230 }, { 240, 90, 110 }, { 150, 210, 90 }, { 255, 170, 210 }, { 110, 140, 255 }, { 230, 200, 120 },
}
local TOKENS = { home = true, work = true, eat = true, cafe = true, fun = true, walk = true }
local DEFAULT_AREAS = { home = "station", eat = "gwangan_st", cafe = "hongmidang", fun = "beach_c", walk = "beach_c" }

local byId: { [string]: any } = {}
Citizens.byId = byId
Citizens.ORDER = {} -- every id, roster order
Citizens.KEY_IDS = {} -- server NPCs
Citizens.CITIZEN_IDS = {} -- roaming pedestrians
Citizens.PLAIN_IDS = {} -- type "plain"
Citizens.TYPED_IDS = {} -- violent / fool / beggar / drunk
-- NPC TYPES (npc_types): c.type. Street behaviour lives in GwangalliStreetLife/Agent, lines in
-- GwangalliSocialShared.TYPE_LINES, the 어깨빵 rules in GwangalliBumpShared.
Citizens.TYPES = {
	plain = { label = "그냥 NPC", chatty = false },
	violent = { label = "폭력적인 NPC", chatty = false, bumpBack = true },
	fool = { label = "동네바보", chatty = true, bumps = true },
	beggar = { label = "노숙자", chatty = true, begs = true },
	drunk = { label = "취객", chatty = false, stagger = true },
	police = { label = "경찰", chatty = false, police = true },
	punk = { label = "걸렁뱅이", chatty = true, provokes = true },
	thug = { label = "불량배", chatty = false, bumpBack = true, threatens = true },
	rich = { label = "부자", chatty = false },
}
function Citizens.typeOf(id: any): string
	local c = Citizens.byId[id]
	return (c and c.type) or "plain"
end
function Citizens.isChatty(id: any): boolean
	local c = Citizens.byId[id]
	return c ~= nil and c.chatty == true
end
function Citizens.ofType(typeId: string): { string }
	local out = {}
	for _, id in Citizens.ORDER do
		if Citizens.byId[id].type == typeId then
			table.insert(out, id)
		end
	end
	return out
end
-- the ids GwangalliGameplayShared.NPC_ORDER already uses (kept stable)
Citizens.LEGACY_NPC_IDS = { "gs25_owner", "starbucks_mgr", "rider_mgr", "hoe_boss", "lifeguard_chief", "taxi_dispatcher", "realtor", "banker", "club_md", "minji", "junho" }

local function ageGroup(age: number): string
	if age < 20 then
		return "teen"
	elseif age < 30 then
		return "young"
	elseif age < 45 then
		return "adult"
	elseif age < 60 then
		return "middle"
	end
	return "senior"
end

local function resolveToken(c: any, token: string): string
	if TOKENS[token] then
		local v = c[token]
		if token == "work" and v == nil then
			v = c.fun
		end
		return v or DEFAULT_AREAS[token] or "beach_c"
	end
	return token
end

for _, c in Citizens.LIST do
	local P = Citizens.PERSONAS[c.persona]
	local h = hashString(c.id)
	c.speech = c.speech or "std"
	c.minor = c.age < 20
	c.club = c.club or 0
	c.social = c.social or 0.6
	c.tones = c.tones or (P and P.tones) or { like = {}, dislike = {} }
	c.topics = c.topics or (P and P.topics) or {}
	c.hate = c.hate or {}
	c.love = c.love or {}
	c.like = c.like or {}
	c.dislike = c.dislike or {}
	c.refuse = c.refuse or {}
	c.errands = c.errands or (P and P.errands) or {}
	c.secret = c.secret or (P and P.secret) or "광안리해수욕장 (중앙)"
	c.sig = c.sig or {}
	c.start = c.start or 0
	c.fullName = c.fullName or c.name
	c.jit = ((h % 9) - 4) * 0.125 -- +-0.5 h so people do not all move on the same minute
	local look = c.look or {}
	look.seed = h
	look.body = look.body or c.g
	look.age = look.age or ageGroup(c.age)
	look.style = look.style or (P and P.style) or "casual"
	look.skin = look.skin or (h % 5) + 1
	look.height = look.height or (0.95 + ((h // 7) % 11) * 0.01)
	look.build = look.build or "avg"
	look.hair = look.hair or (if c.g == "f" then "long" else "short")
	look.hc = look.hc or "black"
	c.look = look
	c.accent = c.accent or ACCENTS[(h % #ACCENTS) + 1]
	if not c.key then
		local tpl = Citizens.SCHEDULES[c.sched or (P and P.sched) or "dayjob"] or Citizens.SCHEDULES.dayjob
		local out = {}
		for _, s in tpl do
			table.insert(out, { s[1], resolveToken(c, s[2]), s[3] })
		end
		table.sort(out, function(a, b)
			return a[1] < b[1]
		end)
		c.baseSchedule = out -- personal template (nominal hours); c.schedule adds the crew windows below
	end
	-- NPC type (npc_types): plain (default) | violent | fool | beggar | drunk; chatty = talks first
	if type(c.type) ~= "string" or not Citizens.TYPES[c.type] then
		c.type = "plain"
	end
	if c.chatty == nil then
		c.chatty = Citizens.TYPES[c.type].chatty == true
	end
	if c.type == "violent" and c.start == nil then
		c.start = 0 -- affinity starts at the floor: they do not like anybody
	end
	byId[c.id] = c
	table.insert(Citizens.ORDER, c.id)
	table.insert(if c.type == "plain" then Citizens.PLAIN_IDS else Citizens.TYPED_IDS, c.id)
	table.insert(if c.key then Citizens.KEY_IDS else Citizens.CITIZEN_IDS, c.id)
end

-------------------------------------------------------------------------------------------------
-- CREWS: who hangs out with whom. Every citizen belongs to 1-2 crews (2-4 friend links). slots are
-- shared schedule windows { fromHour, toHour, areaId, act } (nominal hours, like SCHEDULES): the
-- members meet up there and are shown as one group. A crew window replaces the members' own
-- schedule for those hours; afterwards each goes back to their own day. club = true: the crew goes
-- clubbing together (one shared hype threshold: they queue, dance and step outside together).
-- A citizen's windows are at least half an hour apart and they are in at most one club crew.
-------------------------------------------------------------------------------------------------
Citizens.CREW_KINDS = {
	friends = { label = "친구", rel = "친구" },
	couple = { label = "커플", rel = "애인" },
	coworkers = { label = "동료", rel = "동료" },
	neighbors = { label = "이웃", rel = "이웃" },
}
Citizens.CREWS = {
	{ id = "hs", name = "광남고 친구들", kind = "friends", members = { "jiho", "minjae", "chaewon", "yuna" },
		slots = { { 7, 7.75, "beach_c", "walk" }, { 16, 17.5, "gwangan_st", "eat" } },
		lines = { "떡볶이 먹으러 가자!", "야 숙제 했나?", "시험 끝나면 코노 가자 ㅋㅋ" } },
	{ id = "uni_ad", name = "광고홍보 동기들", kind = "friends", members = { "seoyeon", "dohyun", "yerin" }, club = true,
		slots = { { 13, 14, "bronx", "eat" }, { 17, 19, "beach_c", "photo" } },
		lines = { "과제 발표 누가 할래?", "오늘 밤 오션 콜?", "노을 질 때 한 장 더!" } },
	{ id = "pc", name = "PC방 멤버들", kind = "friends", members = { "dohyun", "hyunwoo", "dev_joon" },
		slots = { { 20, 22, "pcbang", "play" } },
		lines = { "한 판만 더 하고 가자", "야 힐 좀 줘!", "오늘 랭겜 몇 연승?" } },
	{ id = "dance", name = "댄스동아리", kind = "friends", members = { "jimin_u", "sua", "kenji" }, club = true,
		slots = { { 14, 16.5, "plaza", "dance" } },
		lines = { "하나 둘 셋 넷!", "거기서 턴 맞추자!", "오늘 밤엔 오션 무대에서 연습이다 ㅋㅋ" } },
	{ id = "office_m", name = "퇴근 후 저녁 멤버들", kind = "coworkers", members = { "taehoon", "sungmin", "jaewon", "kyungsoo" },
		slots = { { 12, 13, "gwangan_st", "eat" }, { 19.5, 22, "gwangan_st", "drink" } },
		lines = { "오늘 부장님 기분 어땠어요?", "딱 한 잔만 하고 갑시다", "주식 얘기는 그만!" } },
	{ id = "office_f", name = "켄트·KBS 동기들", kind = "friends", members = { "soyoung", "eunji", "nari" }, club = true,
		slots = { { 12, 13, "bronx", "eat" }, { 18.5, 19.5, "bronx", "drink" } },
		lines = { "오늘 진짜 퇴근하고 싶었어", "한 잔 하고 오션 가자!", "주말에 호캉스 어때?" } },
	{ id = "surf", name = "서핑 동호회", kind = "friends", members = { "wave_jun", "dahee", "hyuk", "lucas" },
		slots = { { 6, 8.5, "sup", "surf" }, { 16, 18.5, "sup", "surf" } },
		lines = { "오늘 파도 좋다!", "한 번만 더 타자", "보드 왁스 챙겼어?" } },
	{ id = "surf_couple", name = "서핑 커플", kind = "couple", members = { "wave_jun", "dahee" }, club = true,
		slots = { { 19, 20, "beach_c", "walk" } } },
	{ id = "grannies", name = "민락 할매들", kind = "friends", members = { "grandma_bok", "grandma_mal", "grandma_ok" },
		slots = { { 10, 12, "plaza", "sit" }, { 15, 17, "beach_c", "sit" } },
		lines = { "아이고 다리야", "우리 손주가 이번에 상 받았다 아이가", "바람 시원하네" } },
	{ id = "grandpas", name = "할배 낚시회", kind = "friends", members = { "grandpa_man", "grandpa_duk", "captain_park" },
		slots = { { 16, 18, "millak_park", "fish" } },
		lines = { "오늘은 입질이 없네", "어제는 고등어 열 마리 잡았다", "쉿, 조용히 해 봐라" } },
	{ id = "millak", name = "민락 이웃들", kind = "neighbors", members = { "haenyeo", "grandma_bok", "captain_park" },
		slots = { { 18.5, 20.5, "hoetown", "eat" } },
		lines = { "오늘 물질은 우째 됐노?", "이 회 좀 무 봐라", "내일은 바람 분다 카더라" } },
	{ id = "tour", name = "게스트하우스 동행", kind = "friends", members = { "tour_hana", "emma", "tour_sujin" }, club = true,
		slots = { { 10, 12.5, "beach_c", "photo" }, { 17.5, 19, "bronx", "eat" } },
		lines = { "광안대교 나오게 찍어 줘!", "다음 코스 어디야?", "오늘 밤 클럽 가 볼래?" } },
	{ id = "hoe_ajae", name = "회타운 아재들", kind = "friends", members = { "tour_minho", "tour_dad", "kenji" },
		slots = { { 19, 20.5, "hoetown", "eat" } },
		lines = { "이 집 광어 진짜 두껍네", "사진 좀 찍어 주세요 켄지 씨!", "한 접시 더 시킵시다" } },
	{ id = "cafe_alba", name = "카페 알바 동기들", kind = "friends", members = { "yujin", "seungho", "hyunwoo" },
		slots = { { 15, 16.5, "starbucks_beach", "cafe" } },
		lines = { "오늘 손님 진짜 많았다", "라떼 아트 이번엔 성공!", "취업 준비 잘 돼 가?" } },
	{ id = "barista_couple", name = "바리스타 커플", kind = "couple", members = { "yujin", "seungho" }, club = true,
		slots = { { 17.5, 19.5, "beach_c", "walk" } } },
	{ id = "regulars", name = "오션 단골들", kind = "friends", members = { "bora", "jay", "mina" }, club = true,
		slots = { { 12, 14, "hongmidang", "cafe" }, { 16.5, 18, "beach_c", "walk" } },
		lines = { "오늘 라인업 봤어?", "입구에서 태양 MD 보이면 인사하자", "우리 오늘 끝까지 논다" } },
	{ id = "club_staff", name = "오션 스태프", kind = "coworkers", members = { "bartender_rio", "staff_yuri", "jay" },
		slots = { { 15, 16, "gym", "gym" } },
		lines = { "오늘 밤도 풀 부킹이래", "신메뉴 음료 맛볼래?", "출근 전에 몸 좀 풀자" } },
	{ id = "collab", name = "콘텐츠 콜라보 팀", kind = "coworkers", members = { "luna", "chanwoo", "nari" },
		slots = { { 14, 16, "beach_c", "photo" } },
		lines = { "여기서 릴스 하나 찍자", "조회수 10만 가자!", "조명 좋을 때 빨리!" } },
	{ id = "road", name = "도로 위 동료들", kind = "coworkers", members = { "rider_hoon", "rider_min", "taxi_kim", "taxi_lee" },
		slots = { { 15, 16, "gs25", "eat" } },
		lines = { "오늘 콜 많네", "광안대교 또 막히더라", "잠깐 쉬었다 하자" } },
	{ id = "market", name = "밀락 상인회", kind = "neighbors", members = { "market_ahn", "vendor_hotteok", "chef_jung" },
		slots = { { 13, 14, "gwangan_st", "eat" } },
		lines = { "요새 장사는 좀 되나?", "오늘 귤이 달다 아이가", "호떡 하나 더 무라" } },
	{ id = "chefs", name = "맛집 친구들", kind = "friends", members = { "chef_sera", "chef_jung", "chanwoo" },
		slots = { { 17, 18, "gwangan_st", "eat" } },
		lines = { "이 집 소스 비법이 뭘까", "다음 영상엔 우리 가게 나와요?", "간이 딱 좋네" } },
	{ id = "runners", name = "광안 러닝크루", kind = "friends", members = { "runner_hye", "trainer_gun", "yoga_sol" },
		slots = { { 5.5, 7.5, "beach_c", "jog" }, { 18, 19.5, "beach_c", "jog" } },
		lines = { "페이스 좀 올려!", "5km만 더!", "물 마시고 가자" } },
	{ id = "lunch_gym", name = "빵천동 점심 멤버들", kind = "friends", members = { "dev_joon", "design_ara", "trainer_gun" },
		slots = { { 12, 13, "bread", "eat" } },
		lines = { "소금빵 하나 더?", "오늘 PT 몇 시예요?", "이 빵집 줄 미쳤다" } },
	{ id = "parents", name = "학부모 모임", kind = "neighbors", members = { "mom_jiyeon", "dad_sangwoo", "mom_hyesun" },
		slots = { { 9, 11, "hongmidang", "cafe" }, { 15, 17, "beach_c", "walk" } },
		lines = { "학원 어디 보내세요?", "애들 방학 숙제 끝났어요?", "오늘은 커피 제가 살게요" } },
	{ id = "artists", name = "해변 예술가들", kind = "friends", members = { "painter_woo", "singer_yeon", "haeun", "dancer_kai" },
		slots = { { 11, 13, "bread", "paint" } },
		lines = { "여기 색감 좋다", "노을 질 때 다시 그리자", "새 노래 가사 들어 볼래?" } },
	{ id = "cops", name = "광안지구대", kind = "coworkers", members = { "cop_park", "cop_lee", "cop_kim", "cop_choi" },
		slots = { { 15, 16, "police", "work" } },
		lines = { "오늘 신고 몇 건이고?", "교대 전에 순찰 한 바퀴 더 돌자.", "국밥 먹고 가자, 내가 쏜다." } },
	{ id = "bench", name = "벤치 이웃들", kind = "neighbors", members = { "street_kim", "street_park", "street_oh" },
		slots = { { 13, 14.5, "plaza", "sit" } },
		lines = { "오늘은 좀 따뜻하네.", "편의점 폐기 나왔다더라.", "할매, 이거 같이 잡수소." } },
	{ id = "plaza_bros", name = "광장 형님들", kind = "friends", members = { "street_kim", "fool_mansik", "drunk_bae" },
		slots = { { 17.5, 18.5, "plaza", "sit" } },
		lines = { "히히 형님 오늘도 취했다~", "만식아, 니 밥은 묵었나?", "히끅… 내가 오늘 쏜다…" } },
	{ id = "punks", name = "동네 걸렁뱅이들", kind = "friends", members = { "punk_dongsu", "punk_jjang", "punk_mira" },
		slots = { { 21, 23, "gwangan_st", "hangout" } },
		lines = { "야 저기 지나가는 애 봐라 ㅋㅋ", "오늘 누구한테 얻어먹지?", "심심하다… 시비나 걸까 ㅋ" } },
	{ id = "thugs", name = "광남로 불량배", kind = "friends", members = { "thug_gang", "thug_seok", "thug_jun" },
		slots = { { 19, 21.5, "plaza", "hangout" } },
		lines = { "형님, 오늘 분위기 어떻습니까?", "짭새 뜨면 바로 흩어진다.", "저기 저놈 눈빛 봐라." } },
	{ id = "rich", name = "광안 부자 모임", kind = "friends", members = { "rich_madam", "rich_yoon", "rich_heir" },
		slots = { { 15, 16.5, "terrace", "cafe" } },
		lines = { "요즘 요트 계류비가 또 올랐어요.", "다음 달에 파리 가는데 같이 가요.", "이 동네 땅값이 미쳤어요 호호." } },
	{ id = "alba", name = "알바생 동기들", kind = "coworkers", members = { "clerk_gs", "alba_night", "clerk_shop" },
		slots = { { 19.5, 20, "gs25", "eat" } },
		lines = { "오늘 진상 손님 몇 명?", "시급 언제 오르냐…", "끝나고 떡볶이 콜?" } },
}
-- Short names for the chips and how friends call them: nick (replaces the 3-syllable rule), title
-- (what clearly younger people call them), formal (no 아/야 after the nick).
Citizens.NICKS = {
	captain_park = { nick = "박선장", title = "선장님", formal = true },
	taxi_kim = { nick = "김기사", title = "기사님", formal = true },
	taxi_lee = { nick = "이기사", title = "기사님", formal = true },
	chef_jung = { nick = "정실장", title = "실장님", formal = true },
	vendor_hotteok = { nick = "호떡 아지매", title = "아지매", formal = true },
	market_ahn = { title = "사장님" },
	haenyeo = { title = "이모님" },
	cop_park = { nick = "박경사", title = "경사님", formal = true },
	cop_lee = { title = "경장님" },
	cop_kim = { title = "순경님" },
	cop_choi = { title = "순경님" },
	street_kim = { nick = "김영감", title = "영감님", formal = true },
	street_park = { nick = "박씨 아저씨", title = "아저씨", formal = true },
	street_oh = { nick = "오할매", title = "할매", formal = true },
	fool_mansik = { nick = "만식이", title = "만식이 형" },
	drunk_bae = { nick = "배부장", title = "부장님", formal = true },
	rich_madam = { nick = "한사모님", title = "사모님", formal = true },
	rich_yoon = { nick = "윤대표", title = "대표님", formal = true },
	thug_gang = { nick = "태식", title = "형님" },
	punk_jjang = { nick = "짱구" },
}
Citizens.CREW_MIN_GAP = 0.5 -- hours between two windows of one citizen (crew jitter is +-0.25 h)
local SCHED_MIN_SLOT = 0.3 -- a schedule entry shorter than this (in-game hours) is dropped

local crewById: { [string]: any } = {}
Citizens.crewById = crewById
for _, cr in Citizens.CREWS do
	crewById[cr.id] = cr
	cr.jit = ((hashString(cr.id) % 5) - 2) * 0.125 -- -0.25 .. +0.25 h, shared by every member
end

-- circular [s, e) on the 24 h clock
local function inWindow(t: number, s: number, e: number): boolean
	return (t - s) % 24 < (e - s) % 24
end
Citizens.inWindow = inWindow

-- the personal (template) entry active at nominal hour h
local function baseAt(base: { any }, h: number): any
	local pick = base[#base]
	local hh = h % 24
	for _, e in base do
		if e[1] <= hh then
			pick = e
		else
			break
		end
	end
	return pick
end

-- c.schedule = { {nominalHour, areaId, act, t = effective start (jitter applied), crew = crewId?,
-- from = shared meeting origin?, resume = true? (back to their own day after a crew window)} } sorted
-- by t. Personal entries use the citizen's own jitter, crew windows the crew's (so members move
-- together).
local function buildSchedule(c: any)
	local base = c.baseSchedule
	local wins = c.crewWindows or {}
	local eff = {}
	for i, w in wins do
		eff[i] = { s = (w.from + w.jit) % 24, e = (w.to + w.jit) % 24 }
	end
	local function covered(t: number): boolean
		for _, x in eff do
			if inWindow(t, x.s, x.e) then
				return true
			end
		end
		return false
	end
	local entries = {}
	for _, e in base do
		local t = (e[1] + c.jit) % 24
		if not covered(t) then
			table.insert(entries, { e[1], e[2], e[3], t = t })
		end
	end
	for i, w in wins do
		local x = eff[i]
		table.insert(entries, { w.from, w.area, w.act, t = x.s, crew = w.crew, from = w.origin })
		if not covered(x.e) then
			local r = baseAt(base, w.to)
			table.insert(entries, { w.to, r[2], r[3], t = x.e, resume = true })
		end
	end
	table.sort(entries, function(a, b)
		return a.t < b.t
	end)
	-- drop personal entries that would last only minutes (a crew window starts right after) and
	-- repeats of the same place + act
	local changed = true
	while changed and #entries > 1 do
		changed = false
		local n = #entries
		for i = 1, n do
			local cur = entries[i]
			local nxt = entries[i % n + 1]
			local prev = entries[(i - 2) % n + 1]
			if not cur.crew then
				local dur = (nxt.t - cur.t) % 24
				if dur < SCHED_MIN_SLOT or (not prev.crew and prev[2] == cur[2] and prev[3] == cur[3]) then
					table.remove(entries, i)
					changed = true
					break
				end
			end
		end
	end
	c.schedule = entries
end

-- links + windows
for _, c in Citizens.LIST do
	c.crews = {}
	c.friends = {}
	c.crew = c.friends -- alias: "crew links" = the friend ids
	c.crewWindows = {}
end
for _, cr in Citizens.CREWS do
	for _, m in cr.members do
		local c = byId[m]
		if c then
			table.insert(c.crews, cr.id)
			if cr.club then
				c.clubCrew = c.clubCrew or cr.id
			end
			for _, o in cr.members do
				if o ~= m and byId[o] and not table.find(c.friends, o) then
					table.insert(c.friends, o)
				end
			end
			if cr.kind == "couple" then
				for _, o in cr.members do
					if o ~= m then
						c.partner = o
					end
				end
			end
		end
	end
	-- the shared origin of each window: where the first member comes from (all members walk in
	-- together from there, so a group spawned mid-way is plausible for every member)
	local lead = byId[cr.members[1]]
	for _, s in cr.slots do
		local origin = nil
		if lead and lead.baseSchedule then
			local prevEntry = baseAt(lead.baseSchedule, s[1] - 0.01)
			origin = prevEntry[2]
		end
		for _, m in cr.members do
			local c = byId[m]
			if c and not c.key then
				table.insert(c.crewWindows, { from = s[1], to = s[2], area = s[3], act = s[4], crew = cr.id, jit = cr.jit, origin = origin })
			end
		end
	end
end
for _, c in Citizens.LIST do
	if not c.key then
		table.sort(c.crewWindows, function(a, b)
			return a.from < b.from
		end)
		buildSchedule(c)
		-- one hype threshold per clubbing crew (average of the members' club habit)
		local thrId, clubVal = c.id, c.club or 0
		local cc = c.clubCrew and crewById[c.clubCrew]
		if cc then
			local sum, n = 0, 0
			for _, m in cc.members do
				local o = byId[m]
				if o then
					sum += o.club or 0
					n += 1
				end
			end
			thrId, clubVal = cc.id, sum / math.max(1, n)
		end
		c.clubThr = if (c.club or 0) <= 0 then math.huge else math.clamp(1 - 0.95 * clubVal + (hash01(thrId, 7) - 0.5) * 0.08, 0.05, 0.98)
	end
end

function Citizens.get(id: any): any?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

function Citizens.isKey(id: any): boolean
	local c = Citizens.get(id)
	return c ~= nil and c.key == true
end

-- Starting affinities (GwangalliSocialShared.newState / sanitize seeds).
function Citizens.starts(): { [string]: number }
	local out = {}
	for _, c in Citizens.LIST do
		if c.start and c.start > 0 then
			out[c.id] = c.start
		end
	end
	return out
end

function Citizens.areaLabel(areaId: any): string
	local a = type(areaId) == "string" and Citizens.AREAS[areaId]
	return if a then a.label else ""
end

-------------------------------------------------------------------------------------------------
-- Clock: time of day + the club hype curve (GwangalliNight when it exists, same curve otherwise)
-------------------------------------------------------------------------------------------------
function Citizens.timeOfDay(clock: number): string
	local c = clock % 24
	if c >= 5 and c < 11 then
		return "morning"
	elseif c >= 11 and c < 17 then
		return "day"
	elseif c >= 17 and c < 21 then
		return "evening"
	end
	return "night"
end

-- ~0 by day, rising from 18:00, 0.6 at 21:00, 1 from 22:30 to 02:00, 0 again at 05:00.
function Citizens.hypeCurve(clock: number): number
	local c = clock % 24
	if c >= 5 and c < 18 then
		return 0
	elseif c >= 18 and c < 21 then
		return 0.6 * (c - 18) / 3
	elseif c >= 21 and c < 22.5 then
		return 0.6 + 0.4 * (c - 21) / 1.5
	elseif c >= 22.5 or c < 2 then
		return 1
	end
	return math.max(0, 1 - (c - 2) / 3)
end

local nightMod: any = nil
local nightNext = 0
local function night(): any
	if nightMod then
		return nightMod
	end
	local now = os.clock()
	if now < nightNext then
		return nil
	end
	nightNext = now + 10
	local ok, res = pcall(function()
		local s: any = script
		local m = s and s.Parent and s.Parent:FindFirstChild("GwangalliNight")
		if m and m:IsA("ModuleScript") then
			return require(m)
		end
		return nil
	end)
	if ok and type(res) == "table" then
		nightMod = res
	end
	return nightMod
end

function Citizens.hype(clock: number): number
	local N = night()
	if N and type(N.hype) == "function" then
		local ok, v = pcall(N.hype, clock)
		if ok and type(v) == "number" and v == v then
			return math.clamp(v, 0, 1)
		end
	end
	return Citizens.hypeCurve(clock)
end

-- Evening / night: small talk turns to the club (17:00 - 05:00).
function Citizens.isEvening(clock: number): boolean
	local c = clock % 24
	return c >= 17 or c < 5
end

-------------------------------------------------------------------------------------------------
-- Schedules
-------------------------------------------------------------------------------------------------
-- The schedule entry active at `clock` (entries carry their effective start `t`, jitter applied),
-- the one before it and the hours since the entry started.
local function slotAt(c: any, clock: number): (any, any, number)
	local t = clock % 24
	local sch = c.schedule
	local n = #sch
	local idx = n
	for i = 1, n do
		if sch[i].t <= t then
			idx = i
		else
			break
		end
	end
	local prevIdx = if idx > 1 then idx - 1 else n
	return sch[idx], sch[prevIdx], (t - sch[idx].t) % 24
end
Citizens.slotAt = slotAt

-- Hype level from which the person goes clubbing (math.huge = never). Members of a clubbing crew share
-- one threshold (so they queue and party together).
function Citizens.clubThreshold(id: string): number
	local c = byId[id]
	if not c or c.key or (c.club or 0) <= 0 then
		return math.huge
	end
	return c.clubThr or math.huge
end

-- nil (not clubbing) | "queue" | "inside" | "outside" (key NPCs never club)
function Citizens.clubState(id: string, clock: number): string?
	local c = byId[id]
	if not c or c.key or (c.club or 0) <= 0 then
		return nil
	end
	local h = Citizens.hype(clock)
	local thr = Citizens.clubThreshold(id)
	if h < thr then
		return nil
	end
	local cc = clock % 24
	if cc >= 17 and cc < 22.5 and h - thr < 0.12 then
		return "queue"
	end
	if hash01(c.clubCrew or id, math.floor(cc) + 100) < 0.3 then
		return "outside" -- a clubbing crew steps outside together
	end
	return "inside"
end

local OUTSIDE_SPOTS = { "club", "club", "gs25", "beach_c" }
Citizens.TRANSIT_HOURS = 0.5 -- the first half hour of a schedule slot is spent walking there

-- Where the person is at `clock`: areaId, act, info (see the header).
function Citizens.whereNow(id: string, clock: number): (string?, string?, any)
	local c = byId[id]
	if not c then
		return nil, nil, nil
	end
	local cc = clock % 24
	if c.key then
		local on = true
		if c.hours then
			local a, b = c.hours[1], c.hours[2]
			on = if a <= b then (cc >= a and cc < b) else (cc >= a or cc < b)
		end
		return c.post, (if on then (c.postAct or "work") else "home"), { fixed = true, off = not on }
	end
	local slot, prev, hoursIn = slotAt(c, cc)
	local area, act = slot[2], slot[3]
	local cs = Citizens.clubState(id, cc)
	if cs == "queue" then
		local thr = Citizens.clubThreshold(id)
		return "club", "queue", { club = cs, transit = true, from = area, progress = math.clamp((Citizens.hype(cc) - thr) / 0.12, 0, 1), crew = c.clubCrew }
	elseif cs == "outside" then
		local spot = OUTSIDE_SPOTS[1 + math.floor(hash01(c.clubCrew or id, math.floor(cc) + 200) * #OUTSIDE_SPOTS) % #OUTSIDE_SPOTS]
		return spot, "hangout", { club = cs, from = "club", crew = c.clubCrew }
	elseif cs == "inside" then
		return "club", "club", { club = cs, from = area, crew = c.clubCrew }
	end
	local from = slot.from or prev[2] -- a crew window: everyone walks in from the shared meeting origin
	local info: any = { transit = hoursIn < Citizens.TRANSIT_HOURS and from ~= area, from = from, crew = slot.crew }
	if info.transit then
		info.progress = math.clamp(hoursIn / Citizens.TRANSIT_HOURS, 0, 1) -- 0 = just left `from`, 1 = arrived
	end
	-- just left the club (the hype fell below their threshold within the last in-game hour)
	if (c.club or 0) > 0 and cc < 6 then
		local thr = Citizens.clubThreshold(id)
		if Citizens.hype((cc - 1) % 24) >= thr then
			info.transit = true
			info.from = "club"
			info.progress = 0.5
		end
	end
	return area, act, info
end

-- May this citizen be shown as a street pedestrian now? (key NPCs: never, they are server NPCs)
function Citizens.onStreet(id: string, clock: number): boolean
	local c = byId[id]
	if not c or c.key then
		return false
	end
	local area, act, info = Citizens.whereNow(id, clock)
	if not area then
		return false
	end
	if info and info.transit then
		return true
	end
	if Citizens.HIDDEN_ACTS[act :: string] then
		return false
	end
	local a = Citizens.AREAS[area]
	if a and a.indoor and act ~= "hangout" then
		-- stepped outside for a break (a crew steps out together)
		return hash01((info and info.crew) or id, math.floor(clock % 24) + 300) < 0.25
	end
	return true
end

-- Is the person at CLUB OCEAN now (queue / inside / smoking area, club staff at work, key NPCs posted there)?
function Citizens.atClub(id: string, clock: number): boolean
	local c = byId[id]
	if not c then
		return false
	end
	local area, act, info = Citizens.whereNow(id, clock)
	if c.key then
		return area == "club" and not (info and info.off)
	end
	if info and info.club then
		return info.club ~= "outside" or area == "club"
	end
	return area == "club" and act == "work" and c.work == "club"
end

-- Citizens inside the club now (the club's crowd can label its rigs with these).
function Citizens.clubCrowd(clock: number): { string }
	local out = {}
	for _, id in Citizens.CITIZEN_IDS do
		if Citizens.clubState(id, clock) == "inside" then
			table.insert(out, id)
		end
	end
	return out
end

local function dist2(p: any, q: any): number
	local dx, dz = p.X - q.X, p.Z - q.Z
	return dx * dx + dz * dz
end

-- 2D distance from p to the segment a-b.
local function segDist(p: any, a: any, b: any): number
	local abx, abz = b.X - a.X, b.Z - a.Z
	local len2 = abx * abx + abz * abz
	local t = 0
	if len2 > 1e-6 then
		t = math.clamp(((p.X - a.X) * abx + (p.Z - a.Z) * abz) / len2, 0, 1)
	end
	local cx, cz = a.X + abx * t, a.Z + abz * t
	return math.sqrt((p.X - cx) ^ 2 + (p.Z - cz) ^ 2)
end
Citizens.segDist = segDist

-- Server check of a client-reported position (Vector3 or {X, Z}) of a roaming citizen: inside the
-- scheduled area (+ slack) now or +-45 in-game minutes (clock skew / slot changes), or on the way
-- between two areas. Unresolvable areas (not built) cannot be checked and pass.
function Citizens.plausible(id: string, pos: any, clock: number, areaPos: (string) -> any, slack: number?): boolean
	local c = byId[id]
	if not c or type(pos) ~= "table" and typeof(pos) ~= "Vector3" then
		return false
	end
	local s = slack or 220
	local checked = 0
	for _, dt in { 0, -0.75, 0.75 } do
		local area, _, info = Citizens.whereNow(id, (clock + dt) % 24)
		local p = area and areaPos(area)
		if p then
			checked += 1
			local a = Citizens.AREAS[area :: string]
			local r = (if a then a.r else 120) + s
			if dist2(pos, p) <= r * r then
				return true
			end
		end
		if info and info.from then
			local p1 = areaPos(info.from)
			if p1 then
				checked += 1
				local a1 = Citizens.AREAS[info.from]
				local r1 = (if a1 then a1.r else 120) + s
				if dist2(pos, p1) <= r1 * r1 then
					return true
				end
				if p and segDist(pos, p1, p) <= s then
					return true
				end
			end
		end
	end
	return checked == 0
end

-- Street-visible citizens plausibly within `reach` studs of pos (nearest first), for pedestrian
-- spawners. exclude = { [id] = true } (already spawned).
function Citizens.candidates(pos: any, clock: number, areaPos: (string) -> any, maxN: number?, reach: number?, exclude: { [string]: boolean }?): { string }
	local lim = reach or 320
	local list = {}
	for _, id in Citizens.CITIZEN_IDS do
		if not (exclude and exclude[id]) and Citizens.onStreet(id, clock) then
			local area, _, info = Citizens.whereNow(id, clock)
			local p = area and areaPos(area)
			if p then
				local a = Citizens.AREAS[area :: string]
				local d = math.sqrt(dist2(pos, p)) - (if a then a.r else 100)
				if info and info.transit and info.from then
					local p1 = areaPos(info.from)
					if p1 then
						d = math.min(d, segDist(pos, p1, p))
					end
				end
				if d <= lim then
					table.insert(list, { id = id, d = math.max(0, d) + hash01(id, 1) * 20 })
				end
			end
		end
	end
	table.sort(list, function(x, y)
		return x.d < y.d
	end)
	local out = {}
	for i, e in list do
		if maxN and i > maxN then
			break
		end
		out[i] = e.id
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Crews: who is with whom right now
-------------------------------------------------------------------------------------------------
local EMPTY: { string } = table.freeze({})

function Citizens.friendsOf(id: any): { string }
	local c = Citizens.get(id)
	return if c and c.friends then c.friends else EMPTY
end

Citizens.crewOf = Citizens.friendsOf -- alias

function Citizens.crewsOf(id: any): { string }
	local c = Citizens.get(id)
	return if c and c.crews then c.crews else EMPTY
end

-- a and b are friends (share a crew): true, the crew id (a couple crew first)
function Citizens.areFriends(a: any, b: any): (boolean, string?)
	local ca, cb = Citizens.get(a), Citizens.get(b)
	if not ca or not cb or a == b or not ca.crews then
		return false, nil
	end
	local found = nil
	for _, crewId in ca.crews do
		local cr = crewById[crewId]
		if cr and table.find(cr.members, b) then
			if cr.kind == "couple" then
				return true, crewId
			end
			found = found or crewId
		end
	end
	return found ~= nil, found
end

function Citizens.isCouple(a: any, b: any): boolean
	local ca = Citizens.get(a)
	return ca ~= nil and ca.partner ~= nil and ca.partner == b
end

-- The crew-mates who are with this citizen right now (same crew window or the same clubbing-crew
-- state, same area and act; not including id), the crew id. Street visibility matches id's.
function Citizens.companions(id: string, clock: number): ({ string }, string?)
	local c = byId[id]
	if not c or c.key then
		return EMPTY, nil
	end
	local area, act, info = Citizens.whereNow(id, clock)
	local crewId = info and info.crew
	local cr = crewId and crewById[crewId]
	if not cr then
		return EMPTY, nil
	end
	local out = {}
	for _, m in cr.members do
		if m ~= id then
			local a2, x2, i2 = Citizens.whereNow(m, clock)
			if i2 and i2.crew == crewId and a2 == area and x2 == act then
				table.insert(out, m)
			end
		end
	end
	if #out == 0 then
		return EMPTY, nil
	end
	return out, crewId
end

-- The group this citizen is in right now: leader (first present member in crew order), members (all
-- present, leader first), crew id. Alone: id, {id}, nil.
function Citizens.group(id: string, clock: number): (string, { string }, string?)
	local others, crewId = Citizens.companions(id, clock)
	if not crewId then
		return id, { id }, nil
	end
	local out = {}
	for _, m in crewById[crewId].members do
		if m == id or table.find(others, m) then
			table.insert(out, m)
		end
	end
	return out[1], out, crewId
end

-- Every group of 2+ crew-mates out together now (street-visible, or in the club queue / outside):
-- { {crew, leader, members, area, act, couple} }.
function Citizens.groupsNow(clock: number): { any }
	local out = {}
	for _, cr in Citizens.CREWS do
		local buckets = {}
		for _, m in cr.members do
			local c = byId[m]
			if c and not c.key then
				local area, act, info = Citizens.whereNow(m, clock)
				if info and info.crew == cr.id and area and info.club ~= "inside" and Citizens.onStreet(m, clock) then
					local k = area .. "|" .. tostring(act)
					local b = buckets[k]
					if not b then
						b = { crew = cr.id, leader = m, members = {}, area = area, act = act, couple = cr.kind == "couple" }
						buckets[k] = b
						table.insert(out, b)
					end
					table.insert(b.members, m)
				end
			end
		end
	end
	for i = #out, 1, -1 do
		if #out[i].members < 2 then
			table.remove(out, i)
		end
	end
	return out
end

-- Citizens.candidates as groups: { {id = leader, members = {other ids}} } (nearest first); maxN counts
-- people. A member that comes up first brings its group under its leader. Members already spawned
-- (exclude) are left out of `members`.
function Citizens.candidateGroups(pos: any, clock: number, areaPos: (string) -> any, maxN: number?, reach: number?, exclude: { [string]: boolean }?): { any }
	local list = Citizens.candidates(pos, clock, areaPos, nil, reach, exclude)
	local taken: { [string]: boolean } = {}
	local out = {}
	local people = 0
	for _, id in list do
		if maxN and people >= maxN then
			break
		end
		if not taken[id] then
			local leader, members = Citizens.group(id, clock)
			if exclude and exclude[leader] then
				leader = id -- the leader is already out there: this one joins on its own
				members = { id }
			end
			local rest = {}
			for _, m in members do
				if m ~= leader and not taken[m] and not (exclude and exclude[m]) and Citizens.onStreet(m, clock) then
					if not maxN or people + 1 + #rest < maxN then
						table.insert(rest, m)
					end
				end
			end
			taken[leader] = true
			for _, m in rest do
				taken[m] = true
			end
			table.insert(out, { id = leader, members = rest })
			people += 1 + #rest
		end
	end
	return out
end

-- Citizens inside the club now, crew-mates next to each other (ClubCrowd can seat friends together).
function Citizens.clubGroups(clock: number): { { string } }
	local out = {}
	local byCrew = {}
	for _, id in Citizens.clubCrowd(clock) do
		local cc = byId[id].clubCrew
		if cc then
			local g = byCrew[cc]
			if not g then
				g = {}
				byCrew[cc] = g
				table.insert(out, g)
			end
			table.insert(g, id)
		else
			table.insert(out, { id })
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Lines
-------------------------------------------------------------------------------------------------
local function register(tier: number): string
	return if tier >= 3 then "c" else "p"
end
Citizens.register = register

local function pick(list: { any }?, rnd: (() -> number)?): any
	if not list or #list == 0 then
		return nil
	end
	local r = (rnd or math.random)()
	return list[math.clamp(math.floor(r * #list) + 1, 1, #list)]
end
Citizens.pick = pick

local function addAll(out: { string }, list: { string }?)
	if list then
		for _, s in list do
			table.insert(out, s)
		end
	end
end

function Citizens.fill(s: string, vars: { [string]: any }?): string
	return (string.gsub(s, "{(%w+)}", function(k)
		local v = vars and vars[k]
		if v == nil then
			return if k == "name" then "친구" else ""
		end
		return tostring(v)
	end))
end

local function clampTier(t: any): number
	return math.clamp(math.floor(tonumber(t) or 1), 1, 5)
end

-------------------------------------------------------------------------------------------------
-- Names between friends (Korean particles, nicknames, how people call each other)
-------------------------------------------------------------------------------------------------
local function lastCode(word: string): number?
	local ok, last = pcall(function()
		local l = nil
		for _, cp in utf8.codes(word) do
			l = cp
		end
		return l
	end)
	return if ok then last else nil
end

-- the last syllable has a final consonant (받침): 도현 -> true, 수아 -> false
function Citizens.hasBatchim(word: string): boolean
	local last = lastCode(word)
	return last ~= nil and last >= 0xAC00 and last <= 0xD7A3 and (last - 0xAC00) % 28 ~= 0
end

-- josa("도현", "랑", "이랑") -> "도현이랑"; josa("수아", "랑", "이랑") -> "수아랑"
function Citizens.josa(word: string, noBatchim: string, batchim: string): string
	return word .. (if Citizens.hasBatchim(word) then batchim else noBatchim)
end
local josa = Citizens.josa

local SURNAMES = {}
for _, cp in utf8.codes("김이박최정강조윤장임한오서신권황안송류전홍고문양손배백허유남심노하곽성차주우구민진지엄채원천방공현함변염여추도소석선설마길연위표명기반왕금옥육인맹제모탁국어은편용예경봉사부가복태목형피두감음빈동온호범좌") do
	SURNAMES[utf8.char(cp)] = true
end

-- The name friends and name chips use: 이서연 -> 서연 (3 Hangul syllables drop the family name),
-- 엠마 / 한솔 / 카이 stay, NICKS override (박선장, 김기사, 호떡 아지매).
function Citizens.shortName(id: any): string
	local c = Citizens.get(id)
	if not c then
		return ""
	end
	local N = Citizens.NICKS[c.id]
	if N and N.nick then
		return N.nick
	end
	local name = c.name
	if not c.key and c.persona ~= "foreigner" and not string.find(name, " ", 1, true) and utf8.len(name) == 3 then
		local cps = {}
		for _, cp in utf8.codes(name) do
			table.insert(cps, cp)
		end
		if SURNAMES[utf8.char(cps[1])] and cps[3] >= 0xAC00 and cps[3] <= 0xD7A3 then
			return utf8.char(cps[2], cps[3])
		end
	end
	return name
end

-- The friendly form used before particles: 도현 -> 도현이 (도현이한테, 도현이 알아요?), 수아 -> 수아.
local function nameI(id: string): string
	local n = Citizens.shortName(id)
	local N = Citizens.NICKS[id]
	if Citizens.hasBatchim(n) and not (N and N.formal) and not (byId[id] and byId[id].key) then
		return n .. "이"
	end
	return n
end
Citizens.nameI = nameI

-- How `id` refers to their friend `friendId` when talking to the player: 도현이 (same age / younger),
-- 민석 형 / 복순 언니 (older), 김기사님 / 안 사장님 (a title).
function Citizens.refName(id: string, friendId: string): string
	local c, f = byId[id], byId[friendId]
	if not c or not f then
		return ""
	end
	if f.age - c.age < 8 then
		return nameI(friendId)
	end
	local N = Citizens.NICKS[friendId]
	if N and N.formal and N.nick then
		return if N.title and string.sub(N.title, -3) == "님" then N.nick .. "님" else N.nick
	end
	local term, _ = Citizens.callName(id, friendId)
	if N and N.title and term == N.title then
		local first = utf8.char(utf8.codepoint(f.name, 1))
		return first .. " " .. N.title -- 안 사장님
	end
	return Citizens.shortName(friendId) .. " " .. term -- 민석 형, 복순 언니, 만수 형님
end

-- How `fromId` calls `toId` out loud, and whether they speak politely (존댓말) to them:
-- same age -> "도현아" / "수아야"; a few years older -> 형 / 오빠 / 언니 / 누나; much older -> their
-- title (기사님, 사장님) or 이모 / 삼촌 / 할머니 / 할아버지.
function Citizens.callName(fromId: string, toId: string): (string, boolean)
	local a, b = byId[fromId], byId[toId]
	if not a or not b then
		return "", false
	end
	local N = Citizens.NICKS[toId]
	local diff = b.age - a.age
	if diff >= 3 then
		if N and N.title and diff >= 8 then
			return N.title, true
		end
		if diff >= 25 then
			if b.age >= 60 and a.age < 45 then
				return (if b.g == "f" then "할머니" else "할아버지"), true
			end
			return (if b.g == "f" then "이모" else "삼촌"), true
		end
		local term
		if b.g == "m" then
			term = if a.g == "m" then "형" else "오빠"
		else
			term = if a.g == "f" then "언니" else "누나"
		end
		if a.age >= 40 and term == "형" then
			term = "형님"
		elseif a.age >= 40 and term == "누나" then
			term = "누님"
		end
		return term, diff >= 12
	end
	local n = Citizens.shortName(toId)
	if N and N.formal then
		return n, false
	end
	return n .. (if Citizens.hasBatchim(n) then "아" else "야"), false
end

-- "도현이랑" (one friend) / "광고홍보 동기들이랑" (2+: the crew's name) / "도현이 외 2명이랑"
function Citizens.withText(ids: { string }, crewId: string?): string
	if type(ids) ~= "table" or #ids == 0 then
		return ""
	end
	if #ids == 1 then
		return josa(Citizens.shortName(ids[1]), "랑", "이랑")
	end
	local cr = crewId and crewById[crewId]
	if cr then
		return josa(cr.name, "랑", "이랑")
	end
	return string.format("%s 외 %d명이랑", nameI(ids[1]), #ids - 1)
end

-- Name chip text for a citizen out with friends: "서연 · 도현이랑". withIds = the companions (see
-- Citizens.companions); empty -> just the short name.
function Citizens.chipText(id: string, withIds: { string }?, crewId: string?): string
	local n = Citizens.shortName(id)
	if not withIds or #withIds == 0 then
		return n
	end
	if not crewId then
		local _, cr = Citizens.areFriends(id, withIds[1])
		crewId = cr
	end
	return n .. " · " .. Citizens.withText(withIds, crewId)
end

-- Two named friends run into each other on the street: what A says first, what B answers.
Citizens.MEET = {
	a = {
		c = { "어! {call}!", "{call}! 여기서 다 보네?", "오 {call}, 어디 가?", "{call}~ 안녕!" },
		cb = { "어! {call}! 니 여서 뭐 하노?", "{call}! 어데 가노?", "오 {call}, 반갑데이!" },
		p = { "어, {call}! 안녕하세요!", "{call}, 여기서 뵙네요!", "{call}! 잘 지내셨어요?" },
		pb = { "아이고 {call}! 안녕하십니꺼!", "{call}, 여서 다 보네예!" },
		s = { "아이고 {call}! 밥은 뭇나?", "{call}, 어데 가노?", "아이고 {call}, 반갑데이!" },
	},
	b = {
		c = { "{call}! 나 {doing}이었어 ㅎㅎ", "헐 {call}! 반가워!", "어 {call}, 이따 연락할게!" },
		cb = { "{call}! 내 {doing}이었다 ㅋㅋ", "오야 {call}, 이따 연락하께!", "{call}! 니도 여 있었나?" },
		p = { "{call}, 안녕하세요! 저 {doing}이었어요.", "와 {call}! 반가워요!" },
		pb = { "{call}, 안녕하십니꺼! {doing}이었어예.", "아이고 {call}, 반갑습니데이!" },
		s = { "오냐 {call}, 조심히 댕기래이.", "아이고 {call}, 니도 잘 지내제?" },
	},
}

local function meetBank(speaker: any, listener: any, polite: boolean): string
	if speaker.age >= 60 and not polite and speaker.age >= listener.age - 2 then
		return "s" -- an elder to someone younger (or the same age): "아이고 {call}! 밥은 뭇나?"
	end
	if polite then
		return if speaker.speech == "busan" then "pb" else "p"
	end
	return if speaker.speech == "busan" then "cb" else "c"
end

-- lineA, lineB (filled) or nil when they are not friends.
function Citizens.meetLines(aId: string, bId: string, clock: number, rnd: (() -> number)?): (string?, string?)
	local a, b = byId[aId], byId[bId]
	if not a or not b or not Citizens.areFriends(aId, bId) then
		return nil, nil
	end
	local callB, politeA = Citizens.callName(aId, bId)
	local callA, politeB = Citizens.callName(bId, aId)
	local _, actB, infoB = Citizens.whereNow(bId, clock)
	local st = Citizens.ACT_STYLE[actB :: string]
	local doing = if infoB and infoB.transit then "가는 중" else (if st then st.label else "산책 중")
	local la = pick(Citizens.MEET.a[meetBank(a, b, politeA)], rnd) or "{call}!"
	local lb = pick(Citizens.MEET.b[meetBank(b, a, politeB)], rnd) or "{call}!"
	return Citizens.fill(la, { call = callB }), Citizens.fill(lb, { call = callA, doing = doing })
end

-- Banter inside a group of friends (speech bubbles), by what they are doing.
Citizens.CREW_CHAT = {
	walk = { "오늘 바다 색 진짜 예쁘다", "우리 저기까지만 걷자", "아 다리 아파 ㅋㅋ", "광안대교 불 언제 켜지지?" },
	eat = { "여기 진짜 맛집이다", "하나 더 시킬까?", "내가 쏠게! …다음에 ㅋㅋ" },
	drink = { "자, 짠!", "오늘 한 잔만 하는 거다?", "2차는 어디 갈래?" },
	cafe = { "여기 뷰 미쳤다", "아아 한 잔 더?", "이 케이크 반반 하자" },
	photo = { "하나 둘 셋! 다시!", "나 눈 감은 것 같아", "광안대교 나오게 찍어 줘" },
	surf = { "오늘 파도 좋다!", "한 번만 더 타자", "와 방금 거 봤어?" },
	sit = { "바람 시원하네", "요즘 어떻게 지내?", "여기 앉아 있으니까 좋다" },
	fish = { "오늘은 입질이 없네", "쉿, 조용히 해 봐라", "찌 움직였다!" },
	jog = { "페이스 좀 올려!", "조금만 더!", "물 마시고 가자" },
	play = { "한 판만 더!", "야 나 따라와", "오늘 내가 이긴다" },
	dance = { "하나 둘 셋 넷!", "거기서 턴!", "다시 처음부터!" },
	gym = { "한 세트만 더!", "자세 좋다!", "오늘 하체 하는 날이야?" },
	hangout = { "오늘 DJ 누구야?", "들어가서 한 잔 더?", "음악 쩐다 ㅋㅋ" },
	queue = { "줄 언제 줄어들어…", "오늘 사람 진짜 많다", "들어가면 바로 스테이지 가자" },
	work = { "오늘 진짜 바쁘다", "잠깐 쉬었다 하자", "이것만 하고 밥 먹자" },
	paint = { "여기 색감 좋다", "노을 질 때 다시 그리자", "너 그림 많이 늘었다" },
	shop = { "이거 어때?", "세일한다!", "이건 좀 비싸다" },
	study = { "이거 시험에 나온대", "5분만 쉬자", "집중 집중!" },
}
Citizens.CREW_CHAT_BUSAN = {
	walk = { "오늘 바다 쥑인다 아이가", "저까지만 걷자", "아 다리 아프다 ㅋㅋ" },
	eat = { "여 진짜 맛있데이", "하나 더 시키까?", "내가 쏘께! …담에 ㅋㅋ" },
	drink = { "자, 짠 하자!", "딱 한 잔만 하는 기다?", "2차 어데 가노?" },
	sit = { "바람 시원하네", "요새 우째 지내노?", "여 앉아 있으니까 좋다" },
	fish = { "오늘은 입질이 없네", "쉿, 조용히 해 봐라", "찌 움직인다!" },
	work = { "오늘 억수로 바쁘다", "쫌 쉬었다 하자" },
}

-- A banter line for someone in a group right now (their act; the crew's own lines mixed in), or nil.
function Citizens.crewChat(id: string, clock: number, rnd: (() -> number)?): string?
	local c = byId[id]
	if not c then
		return nil
	end
	local _, act, info = Citizens.whereNow(id, clock)
	local crewId = info and info.crew
	local list = {}
	local bank = if c.speech == "busan" then Citizens.CREW_CHAT_BUSAN[act :: string] else nil
	addAll(list, bank or Citizens.CREW_CHAT[act :: string] or Citizens.CREW_CHAT.walk)
	local cr = crewId and crewById[crewId]
	if cr and cr.lines and not (c.minor and act == "queue") then
		addAll(list, cr.lines)
	end
	return pick(list, rnd)
end

-- "~해요" / "~해" / Busan "~한다" per act, for the small talk about friends
local ACT_VERB = {
	walk = { "산책해요", "산책해", "산책한다" }, eat = { "밥 먹어요", "밥 먹어", "밥 묵는다" },
	drink = { "음료 마셔요", "음료 마셔", "음료 마신다" }, cafe = { "커피 마셔요", "커피 마셔", "커피 마신다" },
	photo = { "사진 찍어요", "사진 찍어", "사진 찍는다" }, surf = { "서핑해요", "서핑해", "서핑한다" },
	sit = { "수다 떨어요", "수다 떨어", "수다 떤다" }, fish = { "낚시해요", "낚시해", "낚시한다" },
	jog = { "같이 뛰어요", "같이 뛰어", "같이 뛴다" }, play = { "놀아요", "놀아", "논다" },
	dance = { "춤 연습해요", "춤 연습해", "춤 연습한다" }, paint = { "그림 그려요", "그림 그려", "그림 그린다" },
	gym = { "운동해요", "운동해", "운동한다" }, work = { "일해요", "일해", "일한다" },
	shop = { "장 봐요", "장 봐", "장 본다" }, hangout = { "놀아요", "놀아", "논다" },
}

-- "오후 5시" / "저녁 7시 반" / "오전 6시"
function Citizens.hourText(h: number): string
	local hh = math.floor(h) % 24
	local half = h - math.floor(h) >= 0.5
	local pre = if hh < 5 then "새벽" elseif hh < 12 then "오전" elseif hh == 12 then "낮" elseif hh < 18 then "오후" else "저녁"
	local h12 = if hh == 0 then 12 elseif hh > 12 then hh - 12 else hh
	return string.format("%s %d시%s", pre, h12, if half then " 반" else "")
end

-- Small talk about their friends (tier 2: polite, 3+: casual), built once per citizen.
local function crewLinesOf(c: any): any
	if c.crewLines then
		return c.crewLines
	end
	local out = { p = {}, c = {} }
	local busan = c.speech == "busan"
	local mentioned = {}
	for _, crewId in c.crews or {} do
		local cr = crewById[crewId]
		local others = {}
		for _, m in cr.members do
			if m ~= c.id then
				table.insert(others, m)
			end
		end
		-- name someone not named yet (the partner has their own couple lines)
		local f = others[1]
		for _, m in others do
			if not mentioned[m] and (cr.kind == "couple" or m ~= c.partner) then
				f = m
				break
			end
		end
		if f then
			mentioned[f] = true
		end
		if f then
			local fI = Citizens.refName(c.id, f)
			local withP = Citizens.withText(others, cr.id)
			local K = Citizens.CREW_KINDS[cr.kind] or Citizens.CREW_KINDS.friends
			local rel = K.rel
			if cr.kind == "couple" then
				rel = if byId[f].g == "m" then "남자친구" else "여자친구"
			end
			table.insert(out.p, string.format("%s 알아요? 제 %s", fI, josa(rel, "예요.", "이에요.")))
			table.insert(out.c, if busan then string.format("%s한테 니 얘기 했데이. 담에 같이 보자!", fI) else string.format("%s한테 네 얘기 했어. 다음에 같이 보자!", fI))
			local s = cr.slots[1]
			if s and not (c.minor and s[4] == "drink") then
				local area = Citizens.areaLabel(s[3])
				local V = ACT_VERB[s[4]] or ACT_VERB.play
				local when = Citizens.hourText(s[1])
				table.insert(out.p, string.format("보통 %s쯤 %s %s에서 %s.", when, withP, area, V[1]))
				table.insert(out.c, if busan then string.format("내 %s쯤엔 거의 %s %s에 있다. 놀러 온나!", when, withP, area) else string.format("나 %s쯤엔 거의 %s %s에 있어. 놀러 와!", when, withP, area))
			end
			if cr.kind == "couple" then
				table.insert(out.c, if busan then string.format("내 %s 사귀는 거 알제? ㅎㅎ", withP) else string.format("나 %s 사귀는 거 알지? ㅎㅎ", withP))
			elseif cr.kind == "coworkers" then
				table.insert(out.c, string.format("%s 없으면 일 못 해 ㅋㅋ", cr.name))
			else
				table.insert(out.c, if busan then string.format("%s 진짜 웃기다 아이가 ㅋㅋ", cr.name) else string.format("%s 진짜 웃겨 ㅋㅋ", cr.name))
			end
		end
	end
	c.crewLines = out
	return out
end
Citizens.crewLinesOf = crewLinesOf

-- A line about the friends they are out with right now (nil when alone).
function Citizens.togetherLine(id: string, tier: number, clock: number): string?
	local c = byId[id]
	local others, crewId = Citizens.companions(id, clock)
	if not c or not crewId then
		return nil
	end
	local withP = Citizens.withText(others, crewId)
	if clampTier(tier) >= 3 then
		return if c.speech == "busan" then string.format("오늘 %s 같이 나왔다 ㅎㅎ", withP) else string.format("오늘 %s 같이 나왔어 ㅎㅎ", withP)
	end
	return string.format("오늘은 %s 같이 나왔어요 ㅎㅎ", withP)
end

-- First meeting with a friend of someone you are close to: "{friend}한테 얘기 많이 들었어요!"
function Citizens.introLine(id: string, friendId: string, vars: any?): string
	local c = byId[id]
	if not c or not byId[friendId] then
		return ""
	end
	local fI = Citizens.refName(id, friendId)
	local s = if c.speech == "busan" then "혹시 {name}님 맞지예? %s한테 얘기 마이 들었어예!" else "혹시 {name}님 맞죠? %s한테 얘기 많이 들었어요!"
	return Citizens.fill(string.format(s, fI), vars)
end

local ROUGH_TYPES = { punk = true, thug = true, beggar = true, police = true, fool = true, drunk = true }

-- All small-talk lines for a tier (1..5) and clock (unfilled; see Citizens.fill). met = you have met
-- before (tier 1 then drops its "first time?" lines).
function Citizens.linesFor(id: string, tier: number, clock: number, met: boolean?): { string }
	local c = byId[id]
	if not c then
		return {}
	end
	local t = clampTier(tier)
	local tod = Citizens.timeOfDay(clock)
	local reg = register(t)
	local P = Citizens.PERSONAS[c.persona]
	local out = {}
	if P then
		addAll(out, P.lines[tod][reg])
	end
	-- street types with their own voice (걸렁뱅이, 불량배, 노숙자, 경찰, 동네바보, 취객) keep to their persona
	-- until they are close: the friendly generic lines ("같이 클럽 가실래요?") don't fit them
	local rough = ROUGH_TYPES[c.type or ""] == true
	if not rough or t >= 3 then
		local TL = if met and t == 1 then Citizens.TIER_LINES_MET else Citizens.TIER_LINES[t]
		addAll(out, TL[c.speech] or TL.std)
		if c.speech == "busan" then
			addAll(out, Citizens.BUSAN_LINES[tod][reg])
		end
	end
	if t >= 3 then
		addAll(out, c.sig)
	end
	if t >= 2 and c.crews and #c.crews > 0 then
		addAll(out, crewLinesOf(c)[reg]) -- their friends (by name), where the crew hangs out
	end
	if (tod == "evening" or tod == "night") and (c.club or 0) > 0 and not c.minor and not rough then
		local CL = Citizens.CLUB_LINES[reg]
		addAll(out, CL[c.speech] or CL.std)
	end
	return out
end

function Citizens.smallTalk(id: string, tier: number, clock: number, rnd: (() -> number)?, vars: any?, met: boolean?): string
	local line = pick(Citizens.linesFor(id, tier, clock, met), rnd)
	return Citizens.fill(line or "…", vars)
end

-- mem = { met, since (seconds since the last meeting), area (areaId), act (last activity id),
-- gift (gift display name), broken (a promise was broken) }; vars = { name = player name }.
function Citizens.greeting(id: string, tier: number, clock: number, mem: any?, vars: any?, rnd: (() -> number)?): string
	local c = byId[id]
	if not c then
		return ""
	end
	local t = clampTier(tier)
	local reg = register(t)
	local busanCasual = c.speech == "busan" and reg == "c"
	local r = rnd or math.random
	local parts = {}
	local v = table.clone(vars or {})
	local function memLine(key: string): string?
		local m = Citizens.MEMORY[key]
		if not m then
			return nil
		end
		if busanCasual and m.b then
			return m.b
		end
		return m[reg] or m.c
	end
	if mem and (mem.met or 0) > 0 and t >= 2 then
		local since = mem.since or math.huge
		local key
		if mem.broken then
			key = "broken"
		elseif since < 900 then
			key = "again"
		elseif since < 3 * 3600 and mem.area and Citizens.AREAS[mem.area] then
			key = "today"
			v.area = Citizens.AREAS[mem.area].label
		elseif since < 36 * 3600 then
			key = "yesterday"
		elseif since < 7 * 86400 then
			key = "days"
		else
			key = "long"
		end
		table.insert(parts, memLine(key) :: string)
		local ak = mem.act and Citizens.ACT_MEMORY[mem.act]
		if ak and key ~= "broken" and (ak ~= "gift" or mem.gift) and r() < 0.6 then
			v.gift = mem.gift
			local l = memLine(ak)
			if l then
				table.insert(parts, l)
			end
		end
	else
		local TL = if mem and (mem.met or 0) > 0 then Citizens.TIER_LINES_MET else Citizens.TIER_LINES[t]
		if t > 1 then
			TL = Citizens.TIER_LINES[t]
		end
		table.insert(parts, pick(TL[c.speech] or TL.std, r))
	end
	local P = Citizens.PERSONAS[c.persona]
	if P then
		table.insert(parts, pick(P.lines[Citizens.timeOfDay(clock)][reg], r))
	end
	return Citizens.fill(table.concat(parts, " "), v)
end

-- A conversation question: { topic, qi, text, replies = { {tone, t, effect?} x3 } }
function Citizens.question(id: string, tier: number, clock: number, rnd: (() -> number)?): any?
	local c = byId[id]
	if not c then
		return nil
	end
	local r = rnd or math.random
	local topic
	if Citizens.isEvening(clock) and (c.club or 0) > 0 and not c.minor and r() < 0.5 then
		topic = "club"
	elseif #c.topics > 0 and r() < 0.7 then
		topic = pick(c.topics, r)
	else
		topic = pick(Citizens.TOPIC_ORDER, r)
	end
	if not Citizens.TOPICS[topic] or (topic == "club" and c.minor) then
		topic = "music"
	end
	local T = Citizens.TOPICS[topic]
	local qi = math.clamp(math.floor(r() * #T.qs) + 1, 1, #T.qs)
	local q = T.qs[qi]
	return { topic = topic, qi = qi, text = if register(clampTier(tier)) == "c" then q.c else q.p, replies = q.r }
end

-- Reply outcome: "love" | "like" | "neutral" | "meh" | "dislike" | "rude"
function Citizens.react(id: string, tone: string, topic: string?): string
	if tone == "rude" then
		return "rude"
	end
	local c = byId[id]
	if not c then
		return "neutral"
	end
	local s = 0
	if table.find(c.tones.like, tone) then
		s += 2
	end
	if table.find(c.tones.dislike, tone) then
		s -= 2
	end
	if topic and table.find(c.topics, topic) then
		s += 1
	end
	if topic and table.find(c.hate, topic) then
		s -= 1
	end
	if s >= 2 then
		return "love"
	elseif s == 1 then
		return "like"
	elseif s == 0 then
		return "neutral"
	elseif s == -1 then
		return "meh"
	end
	return "dislike"
end

local function reactBank(c: any, bank: any, reg: string): { string }?
	if not bank then
		return nil
	end
	if c.speech == "busan" and reg == "c" and bank.b then
		return bank.b
	end
	return bank[reg] or bank.c or bank.p
end

function Citizens.reactLine(id: string, tier: number, outcome: string, rnd: (() -> number)?, vars: any?): string
	local c = byId[id]
	if not c then
		return ""
	end
	local list = reactBank(c, Citizens.REACT[outcome], register(clampTier(tier)))
	return Citizens.fill(pick(list, rnd) or "…", vars)
end

-- Gift reaction: "love" | "like" | "neutral" | "dislike" | "refuse". cat / adult from
-- GwangalliSocialShared.GIFTS[giftId]. Explicit gift ids win over category matches.
function Citizens.giftPref(id: string, giftId: string, cat: string?, adult: boolean?): string
	local c = byId[id]
	if not c then
		return "neutral"
	end
	if adult and c.minor then
		return "refuse"
	end
	local catKey = if cat then "cat:" .. cat else nil
	local function hasCat(list: { string }): boolean
		return catKey ~= nil and table.find(list, catKey) ~= nil
	end
	if table.find(c.refuse, giftId) or hasCat(c.refuse) then
		return "refuse"
	end
	if table.find(c.love, giftId) then
		return "love"
	elseif table.find(c.dislike, giftId) then
		return "dislike"
	elseif table.find(c.like, giftId) then
		return "like"
	elseif hasCat(c.love) then
		return "love"
	elseif hasCat(c.dislike) then
		return "dislike"
	elseif hasCat(c.like) then
		return "like"
	end
	return "neutral"
end

-- kind: GIFT_REACT key (love / like / neutral / dislike / refuse / again / much / bday)
function Citizens.giftLine(id: string, tier: number, kind: string, rnd: (() -> number)?, vars: any?): string
	local c = byId[id]
	if not c then
		return ""
	end
	local list = reactBank(c, Citizens.GIFT_REACT[kind], register(clampTier(tier)))
	return Citizens.fill(pick(list, rnd) or "…", vars)
end

-- Friend text of `kind` (Citizens.TEXTS key); vars.place = meeting place label.
function Citizens.textFor(id: string, kind: string, rnd: (() -> number)?, vars: any?): string
	local c = byId[id]
	local T = Citizens.TEXTS[kind]
	if not c or not T then
		return ""
	end
	local list = if c.speech == "busan" and T.b then T.b else T.c
	return Citizens.fill(pick(list, rnd) or "", vars)
end

-- An errand this person may ask for: errandId, def
function Citizens.errandFor(id: string, rnd: (() -> number)?): (string?, any?)
	local c = byId[id]
	if not c then
		return nil, nil
	end
	local ok = {}
	for _, e in c.errands do
		if Citizens.ERRANDS[e] then
			table.insert(ok, e)
		end
	end
	local e = pick(ok, rnd)
	return e, e and Citizens.ERRANDS[e] or nil
end

-- How a compliment lands: personas that like compliments love it (their dislike list: dislike);
-- otherwise friends like it, acquaintances like it half the time, strangers find it awkward 30 %.
function Citizens.complimentOutcome(id: string, tier: number, rnd: (() -> number)?): string
	local base = Citizens.react(id, "compliment", nil)
	if base ~= "neutral" then
		return base
	end
	local t = clampTier(tier)
	local r = (rnd or math.random)()
	if t >= 3 then
		return "like"
	elseif t == 2 then
		return if r < 0.5 then "like" else "neutral"
	end
	return if r < 0.3 then "meh" else "neutral"
end

-- Compliment reaction line (COMPLIMENT key: love / like / neutral / meh / dislike / again).
function Citizens.complimentLine(id: string, tier: number, outcome: string, rnd: (() -> number)?, vars: any?): string
	local c = byId[id]
	if not c then
		return ""
	end
	local list = reactBank(c, Citizens.COMPLIMENT[outcome] or Citizens.COMPLIMENT.neutral, register(clampTier(tier)))
	return Citizens.fill(pick(list, rnd) or "…", vars)
end

-- Number exchange line (NUMBER key: yes / no / stranger / later / already).
function Citizens.numberLine(id: string, tier: number, kind: string, rnd: (() -> number)?, vars: any?): string
	local c = byId[id]
	if not c then
		return ""
	end
	local list = reactBank(c, Citizens.NUMBER[kind] or Citizens.NUMBER.no, register(clampTier(tier)))
	return Citizens.fill(pick(list, rnd) or "…", vars)
end

-- The day at a glance: hourly[h + 1] = { area, act } for h = 0..23 (sampled at h:30, club night flow
-- included). Key NPCs: their post (act "home" outside their hours).
function Citizens.hourly(id: string): { any }
	local out = {}
	if not byId[id] then
		return out
	end
	for h = 0, 23 do
		local area, act = Citizens.whereNow(id, h + 0.5)
		out[h + 1] = { area = area, act = act }
	end
	return out
end

-- "지금 {area}에서 {act}" for contacts / friend lists: text, areaId, act, visible (on the street / at
-- the club right now, i.e. worth going there to meet them).
function Citizens.status(id: string, clock: number): (string, string?, string?, boolean)
	local c = byId[id]
	if not c then
		return "", nil, nil, false
	end
	local area, act, info = Citizens.whereNow(id, clock)
	local st = Citizens.ACT_STYLE[act :: string]
	local label = Citizens.areaLabel(area)
	local what = if st then st.label else "지내는 중"
	if info and info.transit and not (info.club == "queue") then
		what = "이동 중"
	end
	local visible = if c.key then not (info and info.off) else (Citizens.onStreet(id, clock) or Citizens.atClub(id, clock))
	if act == "sleep" or act == "home" then
		return what, area, act, false
	end
	if not c.key and not (info and info.transit) and info and info.crew and info.club ~= "inside" then
		local others, crewId = Citizens.companions(id, clock)
		if crewId then
			what = Citizens.withText(others, crewId) .. " " .. what -- "도현이랑 사진 찍는 중"
		end
	end
	if label == "" then
		return what, area, act, visible
	end
	return string.format("%s · %s", label, what), area, act, visible
end

-------------------------------------------------------------------------------------------------
-- Validation (unit tests + once on the server)
-------------------------------------------------------------------------------------------------
function Citizens.validate(): { string }
	local problems = {}
	local function bad(msg: string)
		table.insert(problems, msg)
	end
	local seen = {}
	for _, c in Citizens.LIST do
		if seen[c.id] then
			bad("duplicate id " .. c.id)
		end
		seen[c.id] = true
		if type(c.name) ~= "string" or c.name == "" then
			bad(c.id .. ": no name")
		end
		if not Citizens.PERSONAS[c.persona] then
			bad(c.id .. ": unknown persona " .. tostring(c.persona))
		end
		if c.speech ~= "std" and c.speech ~= "busan" then
			bad(c.id .. ": bad speech")
		end
		if type(c.age) ~= "number" or c.age < 10 or c.age > 99 then
			bad(c.id .. ": bad age")
		end
		if c.key then
			if not Citizens.AREAS[c.post] then
				bad(c.id .. ": unknown post " .. tostring(c.post))
			end
		else
			for _, s in c.schedule do
				if not Citizens.AREAS[s[2]] then
					bad(c.id .. ": unknown schedule area " .. tostring(s[2]))
				end
				if type(s[3]) ~= "string" then
					bad(c.id .. ": schedule without act")
				end
			end
			local sch = c.schedule
			if #sch < 3 then
				bad(c.id .. ": schedule too short")
			end
			for i = 1, #sch do
				local e, nx = sch[i], sch[i % #sch + 1]
				if type(e.t) ~= "number" or (i > 1 and e.t < sch[i - 1].t) then
					bad(c.id .. ": schedule not sorted by start")
				end
				if not e.crew and (nx.t - e.t) % 24 < SCHED_MIN_SLOT - 1e-6 then
					bad(string.format("%s: schedule entry at %.2f lasts under %.1f h", c.id, e.t, SCHED_MIN_SLOT))
				end
				if e.crew and not crewById[e.crew] then
					bad(c.id .. ": unknown crew in schedule " .. tostring(e.crew))
				end
			end
		end
		for _, tp in c.topics do
			if not Citizens.TOPICS[tp] then
				bad(c.id .. ": unknown topic " .. tp)
			end
		end
		for _, tp in c.hate do
			if not Citizens.TOPICS[tp] then
				bad(c.id .. ": unknown hated topic " .. tp)
			end
		end
		for _, t in c.tones.like do
			if not Citizens.TONES[t] then
				bad(c.id .. ": unknown tone " .. t)
			end
		end
		for _, e in c.errands do
			if not Citizens.ERRANDS[e] then
				bad(c.id .. ": unknown errand " .. e)
			end
		end
		if type(c.bday) ~= "table" or c.bday[1] < 1 or c.bday[1] > 12 or c.bday[2] < 1 or c.bday[2] > 31 then
			bad(c.id .. ": bad birthday")
		end
		for tier = 1, 5 do
			for _, clock in { 8, 14, 19, 23 } do
				if #Citizens.linesFor(c.id, tier, clock) < 3 then
					bad(string.format("%s: fewer than 3 lines at tier %d clock %d", c.id, tier, clock))
				end
			end
		end
	end
	for pid, P in Citizens.PERSONAS do
		for _, tod in { "morning", "day", "evening", "night" } do
			local l = P.lines[tod]
			if not l or #l.p < 3 or #l.c < 3 then
				bad("persona " .. pid .. " needs 3+ lines for " .. tod)
			end
		end
		if not Citizens.SCHEDULES[P.sched] then
			bad("persona " .. pid .. " unknown schedule " .. tostring(P.sched))
		end
	end
	for id, a in Citizens.AREAS do
		if type(a.dest) ~= "string" or a.dest == "" or type(a.r) ~= "number" then
			bad("area " .. id .. " incomplete")
		end
	end
	for _, id in Citizens.LEGACY_NPC_IDS do
		if not byId[id] or not byId[id].key then
			bad("legacy NPC id missing from the roster: " .. id)
		end
	end
	for _, tp in Citizens.TOPIC_ORDER do
		local T = Citizens.TOPICS[tp]
		if not T then
			bad("TOPIC_ORDER lists missing topic " .. tp)
		else
			for _, q in T.qs do
				if #q.r ~= 3 then
					bad("topic " .. tp .. " question needs 3 replies")
				end
				for _, rr in q.r do
					if not Citizens.TONES[rr.tone] then
						bad("topic " .. tp .. " unknown tone " .. tostring(rr.tone))
					end
				end
			end
		end
	end
	for id in Citizens.AREAS do
		local nav = Citizens.AREA_NAV[id]
		if not nav or #nav == 0 then
			bad("area " .. id .. " has no AREA_NAV entry")
		else
			for _, n in nav do
				if not table.find(Citizens.NAV_AREAS, n) then
					bad("area " .. id .. " unknown nav area " .. tostring(n))
				end
			end
		end
	end
	for _, c in Citizens.LIST do
		if not c.key then
			for _, sl in c.schedule do
				if not Citizens.ACT_STYLE[sl[3]] then
					bad(c.id .. ": act without ACT_STYLE " .. tostring(sl[3]))
				end
			end
		end
	end
	for _, k in { "love", "like", "neutral", "meh", "dislike", "again" } do
		if not Citizens.COMPLIMENT[k] then
			bad("COMPLIMENT missing " .. k)
		end
	end
	for tid in Citizens.TYPES do
		if tid ~= "plain" and #Citizens.ofType(tid) < 3 then
			bad("fewer than 3 citizens of type " .. tid)
		end
	end
	if #Citizens.LIST < 75 then
		bad("roster too small: " .. #Citizens.LIST)
	end
	-- crews: known members (citizens only), 2-4 symmetric friend links each, windows valid and apart,
	-- at most one clubbing crew per person, no minors drinking or clubbing with a crew
	local crewSeen = {}
	for _, cr in Citizens.CREWS do
		if crewSeen[cr.id] then
			bad("duplicate crew " .. cr.id)
		end
		crewSeen[cr.id] = true
		if type(cr.name) ~= "string" or cr.name == "" or not Citizens.CREW_KINDS[cr.kind] then
			bad("crew " .. cr.id .. ": name / kind")
		end
		if #cr.members < 2 or (cr.kind == "couple" and #cr.members ~= 2) then
			bad("crew " .. cr.id .. ": member count")
		end
		for _, m in cr.members do
			local c = byId[m]
			if not c or c.key then
				bad("crew " .. cr.id .. ": not a citizen " .. tostring(m))
			elseif cr.club and ((c.club or 0) <= 0 or c.minor) then
				bad("crew " .. cr.id .. ": clubbing crew member who does not club " .. m)
			end
		end
		for _, sl in cr.slots do
			if type(sl[1]) ~= "number" or type(sl[2]) ~= "number" or sl[2] <= sl[1] or sl[2] - sl[1] > 6 then
				bad("crew " .. cr.id .. ": bad window")
			end
			if not Citizens.AREAS[sl[3]] then
				bad("crew " .. cr.id .. ": unknown area " .. tostring(sl[3]))
			end
			if not Citizens.ACT_STYLE[sl[4]] or Citizens.HIDDEN_ACTS[sl[4]] then
				bad("crew " .. cr.id .. ": bad act " .. tostring(sl[4]))
			end
			for _, m in cr.members do
				local c = byId[m]
				if c and c.minor and (sl[4] == "drink" or sl[3] == "club") then
					bad("crew " .. cr.id .. ": minor " .. m .. " drinking / at the club")
				end
			end
		end
	end
	for _, c in Citizens.LIST do
		if not c.key then
			local nf = #(c.friends or {})
			if nf < 2 or nf > 4 then
				bad(string.format("%s: %d friend links (want 2-4)", c.id, nf))
			end
			for _, f in c.friends or {} do
				if not byId[f] or not table.find(byId[f].friends, c.id) then
					bad(c.id .. ": friend link not symmetric with " .. tostring(f))
				end
			end
			local clubCrews = 0
			for _, crewId in c.crews do
				if crewById[crewId].club then
					clubCrews += 1
				end
			end
			if clubCrews > 1 then
				bad(c.id .. ": in more than one clubbing crew")
			end
			local w = c.crewWindows
			for i = 2, #w do
				if w[i].from - w[i - 1].to < Citizens.CREW_MIN_GAP - 1e-6 then
					bad(string.format("%s: crew windows %s / %s closer than %.1f h", c.id, w[i - 1].crew, w[i].crew, Citizens.CREW_MIN_GAP))
				end
			end
		elseif c.friends and #c.friends > 0 then
			bad(c.id .. ": key NPCs are not in street crews")
		end
	end
	return problems
end

return Citizens
