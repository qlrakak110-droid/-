-- Interact/Cast (server data): the people of the representative street block (광안리 만남의 광장 ->
-- 광안해변로 -> 뒷골목 -> GS25 광안리점 (the 알바 store) -> CLUB OCEAN 앞). Every entry is a PERSON, not a type: own name, look, speech style,
-- gait, traits, mood baseline, a daily schedule and the places they use. Behaviour (Mind) reads the
-- traits, so two people of the same archetype react differently to the same situation.
--
-- traits (0..1): kindness, aggression, patience, courage, humor, sociability, suspicion, pride, greed,
--   civic (calls the police / intervenes), curiosity (watches incidents), temper (anger rises fast)
-- mood: valence baseline (-1..1), anger/fear start at 0 and drift back to the baseline
-- schedule: { from, to, act, ... } in in-game hours (0-24, may wrap). Activities (Mind):
--   commute (walk portal -> portal through the block), stroll, shop (GS25: queue / order / pickup /
--   maybe eat), rest (bench), photo, hangout (thugs), roam (fool), beg (homeless spot), wander
--   (homeless / drunk), drink (drunk on a bench), patrol (police beat), work (clerk at the counter),
--   sleep (homeless), away (off the block: no body)
-- look: GwangalliNPCLooks roster look (+ acc2 = extra accessories appended after resolve)

local Cast = {}

-- places of the block (feet positions; checked against the ground at boot by Places)
Cast.PLACES = {
	plaza = Vector3.new(-262, 6.5, 22),
	stage = Vector3.new(-262, 6.5, -4),
	photo = Vector3.new(-232, 6.5, 4.3),
	truckE = Vector3.new(-226, 6.5, 18),
	truckW = Vector3.new(-298, 6.5, 17),
	taxi = Vector3.new(-178, 6.5, 44),
	promenadeE = Vector3.new(-205, 6.5, 40),
	plazaW = Vector3.new(-320, 6.5, 22),
	plazaWcorner = Vector3.new(-330, 6.5, 32),
	kentfront = Vector3.new(-186, 6.5, 100),
	backlane = Vector3.new(-241.5, 6.5, 250.7),
	backlaneW = Vector3.new(-291, 6.5, 250),
	club = Vector3.new(-236, 6.5, 300),
	clubSmoke = Vector3.new(-223.7, 6.5, 275.4),
	store = Vector3.new(-299.7, 7, 302.1), -- GS25 광안리점 (the 알바 store), door_out
	storeTerrace = Vector3.new(-296, 6.5, 284),
	portalW = Vector3.new(-350, 6.5, 26),
	portalE = Vector3.new(-140, 6.5, 66),
	portalN = Vector3.new(-292, 6.5, 330),
	beggarSpot = Vector3.new(-290, 6.5, 25),
	grumpySpot = Vector3.new(-292, 6.5, 248),
}
Cast.ARCH = {
	citizen = { hp = 55, run = 15, walk = 6.2 },
	thug = { hp = 95, run = 16, walk = 6 },
	fool = { hp = 65, run = 14, walk = 7.5 },
	homeless = { hp = 45, run = 10, walk = 4.6 },
	drunk = { hp = 55, run = 9, walk = 4.2 },
	police = { hp = 140, run = 17, walk = 6.5 },
	clerk = { hp = 50, run = 14, walk = 6 },
}

local function T(k, a, p, c, h, s, su, pr, g, ci, cu, te)
	return { kindness = k, aggression = a, patience = p, courage = c, humor = h, sociability = s, suspicion = su, pride = pr, greed = g, civic = ci, curiosity = cu, temper = te }
end

Cast.LIST = {
	{
		id = "c_jihun", name = "박지훈", role = "회사원", arch = "citizen", style = "citizen_polite", gait = "brisk",
		bio = "광안동 사는 7년 차 회사원. 출근길 커피 없으면 사람이 아님.",
		look = { body = "m", age = "adult", style = "office", hair = "side", hc = "black", skin = 2, build = "avg", height = 1.02, acc = "glasses" },
		traits = T(0.6, 0.15, 0.55, 0.4, 0.4, 0.45, 0.4, 0.5, 0.3, 0.8, 0.5, 0.35),
		mood = { valence = 0.05 },
		schedule = {
			{ 7, 9.5, "commute", from = "portalE", to = "portalW", via = { "plaza" }, shop = 0.6 },
			{ 12, 13.5, "shop", eat = true },
			{ 18, 20, "commute", from = "portalW", to = "portalE", via = { "plaza", "photo" }, stroll = 0.5 },
			{ 0, 24, "away" },
		},
	},
	{
		id = "c_subin", name = "이수빈", role = "대학생", arch = "citizen", style = "student", gait = "normal",
		bio = "부산대 3학년. 광안리 노을 사진 찍는 게 취미.",
		look = { body = "f", age = "young", style = "trendy", hair = "bob", hc = "brown", skin = 1, build = "slim", acc = "tote" },
		traits = T(0.65, 0.2, 0.5, 0.55, 0.75, 0.8, 0.3, 0.4, 0.3, 0.6, 0.85, 0.3),
		mood = { valence = 0.3 },
		schedule = {
			{ 10, 13, "stroll", spots = { "photo", "stage", "promenadeE", "truckE" } },
			{ 13, 14, "shop" },
			{ 14, 18, "stroll", spots = { "photo", "plaza", "promenadeE" }, rest = 0.4 },
			{ 18, 21, "photo" },
			{ 0, 24, "away" },
		},
	},
	{
		id = "c_soonja", name = "김순자 할머니", role = "동네 할머니", arch = "citizen", style = "grandma", gait = "elderly",
		bio = "광안리 토박이 할머니. 젊은 사람만 보면 밥은 먹었냐고 묻는다.",
		look = { body = "f", age = "senior", style = "granny", skin = 3, build = "slim", height = 0.92, acc = "tote" },
		traits = T(0.95, 0.05, 0.9, 0.25, 0.55, 0.85, 0.2, 0.3, 0.1, 0.9, 0.6, 0.15),
		mood = { valence = 0.4 },
		schedule = {
			{ 6, 10, "stroll", spots = { "plaza", "stage", "truckW" }, rest = 0.7, slow = true },
			{ 10, 11, "shop" },
			{ 16.5, 19, "rest", spots = { "plaza" } },
			{ 0, 24, "away" },
		},
	},
	{
		id = "c_jungwoo", name = "정우", role = "배달 라이더", arch = "citizen", style = "worker", gait = "brisk",
		bio = "콜 하나라도 더 잡아야 하는 배달 라이더. 기다리는 걸 제일 싫어한다.",
		look = { body = "m", age = "young", style = "rider", hair = "twoblock", hc = "black", skin = 2, build = "avg" },
		traits = T(0.45, 0.4, 0.2, 0.6, 0.35, 0.35, 0.45, 0.6, 0.5, 0.5, 0.3, 0.65),
		mood = { valence = -0.05 },
		schedule = {
			{ 9, 23, "commute", from = "portalN", to = "portalE", via = { "backlane", "plaza" }, shop = 0.5, loop = true, rest = 0.2 },
			{ 0, 24, "away" },
		},
	},
	{
		id = "c_miyuki", name = "미유키", role = "일본인 관광객", arch = "citizen", style = "tourist", gait = "stroll",
		bio = "오사카에서 온 관광객. 광안대교 야경 보러 왔다.",
		look = { body = "f", age = "young", style = "tourist", hair = "long", hc = "darkbrown", skin = 1, build = "slim", acc = "camera" },
		traits = T(0.8, 0.05, 0.75, 0.35, 0.6, 0.7, 0.15, 0.3, 0.2, 0.55, 0.9, 0.1),
		mood = { valence = 0.5 },
		schedule = {
			{ 11, 15, "stroll", spots = { "photo", "stage", "taxi", "promenadeE" }, askDirections = true },
			{ 15, 16, "shop" },
			{ 16, 22, "photo", askDirections = true },
			{ 0, 24, "away" },
		},
	},
	{
		id = "t_cheol", name = "강철", role = "광안리 건달", arch = "thug", style = "thug_boss", gait = "swagger",
		bio = "이 동네 형님 행세하는 건달. 체면이 목숨보다 중요하다.",
		look = { body = "m", age = "adult", style = "black", hair = "buzz", hc = "black", skin = 3, build = "broad", height = 1.08, acc = "sunglasses" },
		traits = T(0.15, 0.85, 0.25, 0.85, 0.3, 0.4, 0.75, 0.95, 0.7, 0.05, 0.5, 0.85),
		mood = { valence = -0.15 },
		buddy = "t_minsu",
		schedule = {
			{ 15, 20, "hangout", spots = { "plazaWcorner", "truckW", "stage" } },
			{ 20, 4, "hangout", spots = { "backlane", "clubSmoke", "club" } },
			{ 0, 24, "away" },
		},
	},
	{
		id = "t_minsu", name = "똘마니 민수", role = "강철 따까리", arch = "thug", style = "thug_minion", gait = "swagger",
		bio = "강철 형님 따라다니며 허세 부리는 똘마니. 혼자 남으면 순한 양.",
		look = { body = "m", age = "young", style = "street", hair = "perm", hc = "blonde", skin = 2, build = "slim", acc = "cap" },
		traits = T(0.3, 0.6, 0.35, 0.3, 0.6, 0.6, 0.55, 0.75, 0.6, 0.1, 0.6, 0.6),
		mood = { valence = 0.05 },
		buddy = "t_cheol",
		schedule = {
			{ 15, 20, "hangout", spots = { "plazaWcorner", "truckW", "stage" }, follow = "t_cheol" },
			{ 20, 4, "hangout", spots = { "backlane", "clubSmoke", "club" }, follow = "t_cheol" },
			{ 0, 24, "away" },
		},
	},
	{
		id = "gi_fool", name = "만복이", role = "동네바보", arch = "fool", style = "fool", gait = "bouncy",
		bio = "광안리에서 제일 빠르고 제일 세다고 믿는 동네 형. 마음은 제일 착하다.",
		look = { body = "m", age = "adult", style = "casual", hair = "short", hc = "black", skin = 2, build = "avg", acc = "bucket_hat" },
		traits = T(0.85, 0.2, 0.5, 0.65, 1.0, 0.95, 0.05, 0.75, 0.4, 0.4, 0.95, 0.4),
		mood = { valence = 0.6 },
		type = "fool",
		schedule = {
			{ 8, 23, "roam" },
			{ 0, 24, "away" },
		},
	},
	{
		id = "gi_beggar", name = "광안리 김씨", role = "거렁뱅이", arch = "homeless", style = "homeless_kind", gait = "elderly",
		bio = "왕년에 광안대교 공사도 했다는 김씨. 동네 소문은 다 안다.",
		look = { body = "m", age = "senior", hair = "bald", hc = "gray", skin = 4, build = "slim", height = 0.94, style = "grandpa" },
		traits = T(0.8, 0.1, 0.7, 0.35, 0.8, 0.8, 0.2, 0.3, 0.6, 0.5, 0.7, 0.25),
		mood = { valence = 0.15 },
		type = "beggar",
		spot = "beggarSpot",
		schedule = {
			{ 7, 21, "beg", wander = 0.3 },
			{ 21, 7, "sleep" },
		},
	},
	{
		id = "h_chulsu", name = "철수 할배", role = "노숙자", arch = "homeless", style = "homeless_grumpy", gait = "elderly",
		bio = "자존심 하나로 버티는 할배. 낯선 사람 돈은 안 받는다, 밥은 받는다.",
		look = { body = "m", age = "senior", hair = "short", hc = "white", skin = 3, build = "slim", height = 0.97, style = "grandpa", acc = "cap" },
		traits = T(0.4, 0.35, 0.35, 0.55, 0.35, 0.25, 0.85, 0.9, 0.2, 0.3, 0.4, 0.7),
		mood = { valence = -0.25 },
		spot = "grumpySpot",
		schedule = {
			{ 6, 22, "wander", spots = { "grumpySpot", "storeTerrace", "backlaneW", "plazaW" }, rest = 0.6 },
			{ 22, 6, "sleep" },
		},
	},
	{
		id = "d_choi", name = "최만식 부장", role = "퇴근길 취객", arch = "drunk", style = "drunk_sad", gait = "drunk",
		bio = "회식 끝나고 혼자 2차 중인 부장님. 취하면 다들 자기 자식 같다.",
		look = { body = "m", age = "middle", style = "suit", hair = "side", hc = "black", skin = 2, build = "broad", height = 1.0 },
		traits = T(0.65, 0.35, 0.4, 0.5, 0.65, 0.9, 0.25, 0.65, 0.2, 0.3, 0.6, 0.55),
		mood = { valence = 0.1 },
		drunkBase = 0.75,
		schedule = {
			{ 19, 2, "drink", spots = { "plaza", "stage", "club", "backlane" } },
			{ 0, 24, "away" },
		},
	},
	{
		id = "d_hwang", name = "황씨", role = "동네 술꾼", arch = "drunk", style = "drunk_rowdy", gait = "drunk",
		bio = "낮이고 밤이고 막걸리 냄새. 시비 걸다가 자기가 뭐라 했는지 잊는다.",
		look = { body = "m", age = "middle", style = "grandpa", hair = "perm", hc = "black", skin = 4, build = "avg", height = 0.98 },
		traits = T(0.35, 0.7, 0.25, 0.6, 0.45, 0.6, 0.5, 0.7, 0.4, 0.1, 0.5, 0.85),
		mood = { valence = -0.1 },
		drunkBase = 0.85,
		schedule = {
			{ 16, 3, "drink", spots = { "truckW", "plazaW", "backlaneW", "clubSmoke" }, wander = 0.6 },
			{ 0, 24, "away" },
		},
	},
	{
		id = "gi_patrol", name = "순경 오해변", role = "광안리 해변 순찰", arch = "police", style = "cop", gait = "alert",
		bio = "여름경찰서 소속. 광안리 치안은 내가 지킨다.",
		look = { body = "m", age = "adult", style = "uniform", acc = "cap", hair = "short", hc = "black", build = "broad", height = 1.04, skin = 2 },
		traits = T(0.6, 0.3, 0.6, 0.85, 0.4, 0.5, 0.6, 0.5, 0.0, 1.0, 0.7, 0.3),
		mood = { valence = 0.1 },
		police = true,
		schedule = {
			{ 8, 20, "patrol", beat = { "promenadeE", "plaza", "photo", "backlane", "store", "plazaW" } },
			{ 0, 24, "away" },
		},
	},
	{
		id = "p_night", name = "경장 한밤", role = "광안리 야간 순찰", arch = "police", style = "cop", gait = "alert",
		bio = "야간 순찰 담당. 취객이랑 건달은 얼굴만 봐도 안다.",
		look = { body = "f", age = "adult", style = "uniform", acc = "cap", hair = "ponytail", hc = "black", build = "avg", height = 1.0, skin = 1 },
		traits = T(0.55, 0.35, 0.5, 0.9, 0.3, 0.4, 0.7, 0.5, 0.0, 1.0, 0.7, 0.35),
		mood = { valence = 0.0 },
		police = true,
		schedule = {
			{ 20, 8, "patrol", beat = { "plazaWcorner", "plaza", "backlane", "club", "store", "backlaneW" } },
			{ 0, 24, "away" },
		},
	},
	{
		id = "k_yuna", name = "알바생 윤아", role = "GS25 광안리점 알바", arch = "clerk", style = "clerk", gait = "normal",
		bio = "GS25 광안리점 주간 알바. 진상 손님도 웃으며 상대한다(겉으로는).",
		look = { body = "f", age = "young", style = "apron", hair = "ponytail", hc = "brown", skin = 1, build = "slim" },
		traits = T(0.75, 0.1, 0.65, 0.4, 0.6, 0.7, 0.3, 0.4, 0.2, 0.8, 0.4, 0.3),
		mood = { valence = 0.25 },
		schedule = {
			{ 8, 20, "work" },
			{ 0, 24, "away" },
		},
	},
	{
		id = "k_jungi", name = "알바생 준기", role = "GS25 광안리점 야간 알바", arch = "clerk", style = "clerk", gait = "normal",
		bio = "야간 알바 3개월 차. 졸음과 싸우는 중.",
		look = { body = "m", age = "young", style = "apron", hair = "twoblock", hc = "black", skin = 2, build = "slim" },
		traits = T(0.6, 0.15, 0.55, 0.45, 0.5, 0.45, 0.4, 0.4, 0.2, 0.7, 0.3, 0.35),
		mood = { valence = -0.05 },
		schedule = {
			{ 20, 8, "work" },
			{ 0, 24, "away" },
		},
	},
}

Cast.BY_ID = {}
for _, c in Cast.LIST do
	Cast.BY_ID[c.id] = c
end

-- how an NPC calls the player (by the speaker's style + the player's look is unknown: keep it neutral)
Cast.CALL = {
	citizen_polite = { "저기요", "손님" },
	citizen_busan = { "총각", "아가씨", "학생" },
	student = { "저기요" },
	grandma = { "아가", "총각", "학생" },
	tourist = { "아노…", "저기요" },
	worker = { "저기요" },
	thug_boss = { "어이", "니" },
	thug_minion = { "야", "어이 니" },
	fool = { "친구야", "니" },
	homeless_kind = { "총각", "젊은 양반" },
	homeless_grumpy = { "젊은이", "자네" },
	drunk_sad = { "자네", "어이 젊은 친구" },
	drunk_rowdy = { "야", "어이" },
	cop = { "선생님", "시민분" },
	clerk = { "손님" },
}

return Cast
