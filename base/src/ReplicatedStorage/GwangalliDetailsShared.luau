-- GwangalliDetailsShared: data + pure helpers for the "이것도 만들었다고?" Korean-life details
-- (owner: korean_details; docs/DETAILS.md). Server: ServerScriptService.GwangalliGameplay.Details
-- (feature module). Client: StarterPlayerScripts.GwangalliDetails (+ folder) and the phone app
-- GwangalliPhone/Apps/Delivery ("배달").
--
--   (1) 네컷사진관      self photo booth on the promenade: frame colour, props, 3-2-1 countdown, four
--                       poses -> a polaroid strip rendered from ViewportFrames (no images), album of 10
--   (2) 갈매기 새우과자  buy a snack at the beach stall, hold it up -> gulls swoop in and snatch it
--   (3) 모래 발자국      client footprints on the beach sand, fade after 20 s, washed away by the swash
--   (4) 수조            live fish swim in the tanks of the 횟집 streets, bubbles, a vendor calling out
--   (5) 배달 앱         order food (6 shops), paid from the bank, a rider rides to your home and rings
--   (6) 횡단보도        walk melody / countdown beeps near crossings, green countdown digits
--   (7) 불꽃축제        weekly fireworks festival over 광안대교 (in-game Saturday 17:00 + admin trigger)
--   (8) 소소한 발견      coins glinting on sidewalks, a lost wallet to return, cats asleep on car hoods
--   (9) 버스킹          perform on 3 street stages: instrument + original song + rhythm game, tips
--
-- Nothing here creates instances or yields; safe to require from the server, clients and Lune.
-- Every tunable lives in this file (prices, rates, caps per quality tier, schedule, texts).

local D = {}
D.VERSION = 1

---------------------------------------------------------------------------------------------------
-- Contract: remotes, tags, attributes
---------------------------------------------------------------------------------------------------
D.FOLDER = "GwangalliDetails" -- ReplicatedStorage folder created by the server (remotes + live data)
D.Remote = {
	Request = "DetailsRequest", -- RemoteFunction client -> server (op, payload) -> {ok, code, msg, ...}
	Event = "DetailsEvent", -- RemoteEvent server -> client {kind = ..., ...}
}
D.RIDES = "Rides" -- Folder inside D.FOLDER: one Configuration per delivery ride (attributes below)
D.DATASTORE = "GwangalliDetails_v1"
D.KEY = "u_"

D.Tags = {
	Booth = "GwPhotoBooth", -- the runtime booth Model (attributes: BoothId, State, ...)
	Stall = "GwSnackStall", -- 새우과자 stall counter part
	Coin = "GwCoin", -- a coin part on a sidewalk (attributes CoinId, Amount)
	Wallet = "GwWallet", -- a lost wallet part (attribute WalletId)
	Counter = "GwLostFound", -- 관광안내소 분실물 counter part
	Stage = "GwBuskStage", -- busking stage anchor part (attributes StageId, Performer, ...)
	FishTank = "GwFishTank", -- 수족관 models found in the map (tagged by the server once at start)
	Mat = "GwFestivalMat", -- picnic mats on the beach for the festival (Seat parts)
	Vendor = "GwFishVendor", -- vendor anchor part (client builds the 이모 rig here)
}

-- Workspace attributes (server writes, everyone reads)
D.WS = {
	Weekday = "GwWeekday", -- 0 = 월 .. 6 = 일 (in-game day of the week)
	DayIndex = "GwDayIndex", -- in-game days since the server started
	FestivalStart = "GwFestivalStart", -- server time the current / last show started (nil = none yet)
	FestivalSeed = "GwFestivalSeed",
	FestivalNext = "GwFestivalNext", -- server time of the next scheduled show start
	FestivalDay = "GwFestivalDay", -- true on the festival day (mats, banner)
	StartFestival = "GwStartFestival", -- admin / Studio: set true to start a show now
}

-- Character attributes (server writes)
D.Char = {
	Snack = "GwSnack", -- 새우과자 pieces left in the bag (0 / nil = none)
	FeedAt = "GwFeedAt", -- server time of the last "hold it up"
	FeedSeed = "GwFeedSeed",
	Busk = "GwBusk", -- instrument id while performing
	BuskStage = "GwBuskStage",
	Food = "GwFoodBag", -- delivery menu id while carrying the bag
	Wallet = "GwHasWallet", -- true while carrying a found wallet
	Booth = "GwInBooth", -- booth id while inside a booth session
}

D.WEEKDAYS = { "월", "화", "수", "목", "금", "토", "일" }

---------------------------------------------------------------------------------------------------
-- Small pure helpers
---------------------------------------------------------------------------------------------------
function D.won(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-" else "") .. out .. "원"
end

-- deterministic 0..1 from integers (xorshift on a 32-bit seed)
function D.rand(seed: number, i: number): number
	local x = (math.floor(seed) % 2147483647 + (math.floor(i) % 1048576) * 7919) % 4294967296
	x = bit32.bxor(x, 0x9E3779B9)
	if x == 0 then
		x = 0x2545F491
	end
	for _ = 1, 3 do
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
	end
	return x / 4294967296
end

function D.clockText(clock: number): string
	local m = math.floor((clock % 24) * 60 + 1e-6)
	return string.format("%02d:%02d", m // 60, m % 60)
end

function D.mmss(sec: number): string
	sec = math.max(0, math.floor(sec + 0.5))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

---------------------------------------------------------------------------------------------------
-- Quality tiers (client): caps per system. GwangalliQuality.get() -> low | mid | high (+ saver)
---------------------------------------------------------------------------------------------------
D.TIER = {
	footprints = { saver = 24, low = 40, mid = 80, high = 120 }, -- pooled footprint parts
	footHz = { saver = 4, low = 6, mid = 10, high = 12 }, -- character sampling rate
	gulls = { saver = 2, low = 3, mid = 5, high = 7 }, -- gulls per feeding swoop
	flock = { saver = 0, low = 4, mid = 8, high = 12 }, -- sunset flock circling the beach
	gullHz = { saver = 12, low = 20, mid = 30, high = 40 },
	fishTanks = { saver = 2, low = 4, mid = 8, high = 12 }, -- animated tanks near the camera
	fishHz = { saver = 6, low = 8, mid = 15, high = 24 },
	bubbles = { saver = 2, low = 3, mid = 6, high = 9 }, -- particles / s per tank
	burstParticles = { saver = 26, low = 40, mid = 80, high = 140 }, -- per firework burst
	shells = { saver = 4, low = 6, mid = 10, high = 16 }, -- pooled shells in flight / bursting
	cats = { saver = 1, low = 2, mid = 3, high = 5 },
	pedDigits = { saver = 2, low = 3, mid = 5, high = 8 }, -- countdown displays on ped signals
	audience = { saver = 2, low = 3, mid = 5, high = 6 }, -- busking audience rigs
	vendors = { saver = 1, low = 1, mid = 2, high = 3 }, -- fish vendor rigs
}

---------------------------------------------------------------------------------------------------
-- (1) 네컷사진관 (photo booth)
---------------------------------------------------------------------------------------------------
D.BOOTH = {
	name = "네컷사진관",
	sub = "SELF PHOTO STUDIO · 24H",
	price = 4000, -- per session (paid by the one who starts it; friends join free)
	maxMembers = 4,
	setupTimeout = 60, -- seconds the owner has to press 촬영 시작
	joinRadius = 14, -- studs from the booth centre to join / stay in a session
	countdown = 3, -- 3-2-1 per shot
	shotGap = 1.4, -- seconds after a flash before the next countdown
	cooldown = 8, -- seconds between sessions of the same player
	albumMax = 10,
	-- runtime booth placements (world CFrame of the floor centre; LookVector = out of the entrance)
	-- 광안리 해변 테마거리 (promenade) between the main walkway (z 22) and the inland walk (z 40)
	spots = {
		{ id = "prom", x = 236, z = 33.5, y = 6.5, yaw = 180, name = "네컷사진관 광안리해변점" },
	},
}

-- frame colours of the strip (id, name, bg colour, text colour, optional gradient)
D.FRAMES = {
	{ id = "white", name = "화이트", bg = { 250, 250, 248 }, fg = { 40, 40, 46 } },
	{ id = "black", name = "블랙", bg = { 22, 22, 26 }, fg = { 245, 245, 245 } },
	{ id = "pink", name = "체리 핑크", bg = { 255, 196, 214 }, fg = { 120, 40, 70 } },
	{ id = "sky", name = "스카이", bg = { 178, 222, 255 }, fg = { 30, 70, 120 } },
	{ id = "mint", name = "민트", bg = { 182, 238, 214 }, fg = { 30, 100, 80 } },
	{ id = "lavender", name = "라벤더", bg = { 214, 200, 255 }, fg = { 70, 50, 130 } },
	{ id = "night", name = "광안 나이트", bg = { 20, 24, 60 }, fg = { 255, 255, 255 }, grad = { { 61, 214, 245 }, { 139, 108, 255 }, { 255, 79, 163 } } },
	{ id = "film", name = "필름", bg = { 46, 36, 30 }, fg = { 255, 214, 150 }, film = true },
}
D.FRAME_BY_ID = {}
for i, f in D.FRAMES do
	D.FRAME_BY_ID[f.id] = f
	f.index = i
end

-- props from the props box (worn on the head / face of the posed clone and of the real character)
D.PROPS = {
	{ id = "none", name = "없음", icon = "🙂" },
	{ id = "cat", name = "고양이 머리띠", icon = "🐱", slot = "head" },
	{ id = "bunny", name = "토끼 머리띠", icon = "🐰", slot = "head" },
	{ id = "ribbon", name = "왕리본", icon = "🎀", slot = "head" },
	{ id = "crown", name = "왕관", icon = "👑", slot = "head" },
	{ id = "heartglass", name = "하트 선글라스", icon = "😍", slot = "face" },
	{ id = "round", name = "동그란 안경", icon = "🤓", slot = "face" },
	{ id = "star", name = "별 선글라스", icon = "🤩", slot = "face" },
}
D.PROP_BY_ID = {}
for _, p in D.PROPS do
	D.PROP_BY_ID[p.id] = p
end

-- poses (applied procedurally to the clone in the strip and, locally, to the real characters)
D.POSES = {
	v = { name = "브이 ✌️", glyph = "✌️" },
	heart = { name = "손하트 🫰", glyph = "🫰" },
	bigheart = { name = "머리 위 큰 하트", glyph = "💗" },
	cheek = { name = "볼콕 😊", glyph = "☺️" },
	flower = { name = "꽃받침 🌸", glyph = "🌸" },
	cheer = { name = "만세 🙌", glyph = "🙌" },
	wave = { name = "안녕 👋", glyph = "👋" },
	cool = { name = "시크하게 😎", glyph = "😎" },
}
-- four-shot sequences (one picked per session, so strips differ)
D.POSE_SEQS = {
	{ "v", "heart", "cheek", "cheer" },
	{ "wave", "flower", "bigheart", "v" },
	{ "cool", "v", "heart", "cheer" },
	{ "cheek", "bigheart", "flower", "wave" },
}

---------------------------------------------------------------------------------------------------
-- (2) 갈매기 새우과자
---------------------------------------------------------------------------------------------------
D.SNACK = {
	name = "새우과자",
	stallName = "갈매기 매점",
	price = 1500,
	pieces = 5, -- pieces per bag (one per feed)
	feedCooldown = 3.2, -- seconds between feeds
	swoop = 2.6, -- seconds from the raise until the snatch
	happiness = 1, -- per feed (max 5 per in-game day: D.SNACK.dailyJoy)
	dailyJoy = 5,
	-- stall on the sand next to the 260 stairs (광안리해수욕장, x 280)
	stall = { x = 284, z = -24, yaw = 180 },
	sunset = { from = 16.8, to = 19.3 }, -- big flock window (clock)
}

---------------------------------------------------------------------------------------------------
-- (3) 모래 발자국
---------------------------------------------------------------------------------------------------
D.FOOT = {
	life = 20, -- seconds until fully faded
	step = 2.3, -- studs per step (alternating feet)
	washLife = 0.9, -- fade when the swash reaches a print
	radius = 90, -- characters further than this from the camera leave no prints
	size = Vector3.new(0.55, 0.05, 1.05),
	color = Color3.fromRGB(150, 128, 92),
	wetColor = Color3.fromRGB(112, 96, 70),
	alpha = 0.28, -- starting transparency
}

---------------------------------------------------------------------------------------------------
-- (4) 수조 (live fish tanks) + vendor
---------------------------------------------------------------------------------------------------
D.FISH = {
	radius = 70, -- tanks animated within this distance of the camera
	species = {
		{ name = "광어", color = { 132, 112, 86 }, size = { 2.2, 0.32, 1.5 }, flat = true },
		{ name = "우럭", color = { 64, 62, 58 }, size = { 1.9, 0.85, 0.55 } },
		{ name = "도미", color = { 214, 120, 116 }, size = { 1.9, 0.95, 0.45 } },
		{ name = "방어", color = { 120, 146, 172 }, size = { 2.4, 0.75, 0.55 } },
		{ name = "도다리", color = { 150, 126, 96 }, size = { 1.8, 0.3, 1.2 }, flat = true },
		{ name = "전어", color = { 170, 182, 196 }, size = { 1.2, 0.45, 0.3 } },
	},
	vendorLines = {
		"어서 오이소~ 광어 싱싱합니데이!",
		"오늘 도다리 억수로 좋아예~",
		"회 한 접시 하고 가이소!",
		"총각~ 아가씨~ 구경만 해도 됩니데이!",
		"방금 들어온 놈들이라 펄떡펄떡해요!",
		"초장집 바로 위층이라예~ 올라가이소!",
		"우럭 매운탕 서비스로 드릴게예~",
	},
	-- vendor anchors near the 회센터 / 횟집 tanks (x, z; y from the ground); the client builds the rig
	vendors = {
		{ x = -2575, z = -96, yaw = 200, name = "민락회타운 이모" },
		{ x = -2950, z = -308, yaw = 190, name = "직판장 이모" },
		{ x = -1918, z = -4, yaw = 180, name = "횟집 사장님" },
	},
}

---------------------------------------------------------------------------------------------------
-- (5) 배달 앱
---------------------------------------------------------------------------------------------------
-- prepMin / rideMin are in-game minutes (1 in-game hour = 60 real seconds); the rider rides the
-- last `rideStuds` studs on screen. stats go through ctx.addStats (stamina = 배부름 / 에너지).
D.DELIVERY = {
	appName = "배달",
	brand = "광안 배달",
	minPrepMin = 18,
	tipFree = 20000, -- free delivery tip at or above this subtotal
	tip = 3000,
	waitAtDoor = 90, -- real seconds the rider waits at the entrance before leaving the bag at the door
	rideSpeed = 34, -- studs/s on the scooter
	rideStuds = 420, -- length of the visible ride before the entrance
	eatCooldown = 25,
	cancelBefore = "cooking", -- an order can be cancelled (full refund) until it starts cooking
	menu = {
		{ id = "chicken", cat = "치킨", shop = "광안바삭치킨", item = "후라이드 반 + 양념 반", icon = "🍗", price = 21000, rating = 4.9, reviews = 3812, prepMin = 32, stats = { stamina = 24, happiness = 8 }, color = { 255, 176, 32 } },
		{ id = "pizza", cat = "피자", shop = "바다화덕피자", item = "고구마 무스 피자 (L)", icon = "🍕", price = 24000, rating = 4.7, reviews = 1290, prepMin = 38, stats = { stamina = 26, happiness = 7 }, color = { 255, 90, 95 } },
		{ id = "jjajang", cat = "중식", shop = "민락반점", item = "짜장면 + 탕수육 (소)", icon = "🍜", price = 17000, rating = 4.8, reviews = 2204, prepMin = 22, stats = { stamina = 22, happiness = 6 }, color = { 60, 50, 46 } },
		{ id = "tteok", cat = "분식", shop = "엽기분식 광안점", item = "매운 떡볶이 + 튀김 + 순대", icon = "🌶️", price = 14000, rating = 4.8, reviews = 4021, prepMin = 18, stats = { stamina = 16, happiness = 9 }, color = { 232, 64, 70 } },
		{ id = "jokbal", cat = "족발·보쌈", shop = "남천동 할매족발", item = "앞다리 족발 (중) + 막국수", icon = "🍖", price = 33000, rating = 4.9, reviews = 980, prepMin = 40, stats = { stamina = 30, happiness = 10, popularity = 0.5 }, color = { 150, 96, 60 } },
		{ id = "burger", cat = "버거", shop = "수영로 수제버거", item = "더블 치즈버거 세트", icon = "🍔", price = 12500, rating = 4.6, reviews = 1655, prepMin = 20, stats = { stamina = 18, happiness = 6 }, color = { 255, 194, 71 } },
	},
	-- order states, in order
	STAGES = { "accepted", "cooking", "riding", "arrived", "done" },
	STAGE_NAME = { accepted = "주문 접수", cooking = "조리 중", riding = "배달 중", arrived = "도착", left = "문 앞 보관", done = "배달 완료", cancelled = "주문 취소" },
	riders = { "김민수", "박지훈", "이서준", "최도윤", "정하준", "강예준" },
}
D.MENU_BY_ID = {}
for i, m in D.DELIVERY.menu do
	D.MENU_BY_ID[m.id] = m
	m.index = i
end

function D.deliveryTip(subtotal: number): number
	return if subtotal >= D.DELIVERY.tipFree then 0 else D.DELIVERY.tip
end

-- real seconds for in-game minutes at `rate` in-game hours per real second (default 1 h / 60 s)
function D.gameMinutes(minutes: number, rate: number?): number
	local r = rate or (1 / 60)
	if r <= 0 then
		r = 1 / 60
	end
	return (minutes / 60) / r
end

---------------------------------------------------------------------------------------------------
-- (6) 횡단보도
---------------------------------------------------------------------------------------------------
-- Melody notes as playback speeds of the built-in ping (semitone steps from 1.0).
local function semis(list: { number }): { number }
	local out = {}
	for i, s in list do
		out[i] = 2 ^ (s / 12)
	end
	return out
end
D.CROSS = {
	radius = 34, -- studs from a crossing end where its sounds play
	digitRadius = 80, -- countdown displays on ped signals within this distance
	ping = "rbxasset://sounds/electronicpingshort.wav",
	tick = "rbxasset://sounds/clickfast.wav",
	-- "보행자 녹색 신호입니다" chime (the walk melody, ~1.6 s)
	melody = semis({ 0, 4, 7, 12, 7, 12, 16 }),
	melodyGap = 0.2,
	melodyVolume = 0.32,
	walkChirp = semis({ 12, 16 }), -- the soft chirp every second while walking (시각장애인 음향신호)
	flashBeep = 1.9, -- playback speed of the 뚜 뚜 뚜 countdown beep
	beepVolume = 0.28,
}

---------------------------------------------------------------------------------------------------
-- (7) 불꽃축제
---------------------------------------------------------------------------------------------------
D.FESTIVAL = {
	name = "광안리 불꽃축제",
	weekday = 5, -- 토요일 (0 = 월)
	clock = 17.0, -- in-game start: the 3-minute show (3 in-game hours) runs 17:00-20:00, then the
	-- 20:00 drone show takes over the sky (GwangalliConfig.DroneShow.Times)
	duration = 180, -- real seconds
	announceHours = 2, -- banner / mats from 2 in-game hours before the start
	matsAfter = 30, -- real seconds the mats stay after the show
	viewDistance = 7000, -- clients skip the show beyond this distance from the bay
	-- show volume: barges in front of 광안대교 (deck z -3300, y 150, towers x +-833)
	z = -3020,
	y0 = 260, -- lowest burst height
	y1 = 640,
	x0 = -1500,
	x1 = 1500,
	bridgeZ = -3300,
	deckY = 150,
	soundSpeed = 1143, -- studs/s (343 m/s): the boom arrives after the flash
	-- crowd mats on the sand (x, distance seaward of the promenade edge)
	mats = { { -160, 48 }, { -120, 64 }, { -80, 44 }, { -40, 70 }, { 0, 52 }, { 40, 66 }, { 80, 46 }, { 120, 72 }, { 160, 54 }, { 200, 68 }, { -200, 74 }, { 240, 50 } },
	-- colours (index into this table in the cues)
	colors = {
		{ 255, 214, 110 }, -- 1 gold
		{ 255, 255, 255 }, -- 2 white
		{ 61, 214, 245 }, -- 3 cyan
		{ 255, 79, 163 }, -- 4 magenta
		{ 139, 108, 255 }, -- 5 violet
		{ 255, 90, 70 }, -- 6 red
		{ 90, 240, 140 }, -- 7 green
		{ 84, 140, 255 }, -- 8 blue
		{ 255, 166, 50 }, -- 9 orange
	},
	acts = {
		{ t = 0, name = "오프닝 · 황금 버드나무" },
		{ t = 10, name = "1막 · 광안리의 밤" },
		{ t = 44, name = "2막 · 바다 (광안대교 나이아가라)" },
		{ t = 76, name = "3막 · 열정" },
		{ t = 116, name = "4막 · 별이 쏟아지는 바다" },
		{ t = 150, name = "피날레" },
	},
}

-- The choreography: a deterministic list of cues for a seed, sorted by time.
--   { t, kind = "peony" | "willow" | "ring" | "crossette" | "palm" | "niagara" | "flash" | "beat",
--     x, y, size (burst radius studs), c (colour index), c2 (second colour or nil), n (count weight) }
-- "beat" cues carry no burst: they drive the music (k = "kick" | "chime", note = playback speed).
function D.festivalCues(seed: number): { any }
	local F = D.FESTIVAL
	local cues = {}
	local i = 0
	local function r(): number
		i += 1
		return D.rand(seed, i)
	end
	local function lerp(a: number, b: number, t: number): number
		return a + (b - a) * t
	end
	local function add(t: number, kind: string, x: number, y: number, size: number, c: number, c2: number?, n: number?)
		table.insert(cues, { t = t, kind = kind, x = x, y = y, size = size, c = c, c2 = c2, n = n or 1 })
	end
	local function beat(t: number, k: string, note: number?)
		table.insert(cues, { t = t, kind = "beat", k = k, note = note or 1 })
	end
	local function rx(): number
		return lerp(F.x0, F.x1, r())
	end
	local function ry(a: number?, b: number?): number
		return lerp(a or F.y0, b or F.y1, r())
	end
	-- music: 120 BPM kick from 10 s, chimes on act changes and phrases
	local scale = { 1, 1.122, 1.26, 1.498, 1.682, 2 } -- pentatonic-ish steps of the ping
	for tb = 10, F.duration - 4, 0.5 do
		if tb < 150 then
			if (tb * 2) % 2 == 0 then
				beat(tb, "kick")
			end
		else
			beat(tb, "kick") -- finale: double-time
		end
	end
	for a = 1, #F.acts do
		local t0 = F.acts[a].t
		for k = 0, 3 do
			beat(t0 + k * 0.25, "chime", scale[((a + k) % #scale) + 1])
		end
	end
	for tp = 12, 148, 4 do
		beat(tp, "chime", scale[(math.floor(tp / 4) % #scale) + 1] * 0.5)
	end
	-- opening: three golden willows, centre then the towers
	add(1.0, "willow", 0, 520, 220, 1)
	add(4.0, "willow", -833, 470, 200, 1)
	add(4.0, "willow", 833, 470, 200, 1)
	add(7.5, "flash", 0, 560, 260, 2)
	-- act 1: left / right peonies on the beat, cyan + white
	local t = 10
	local side = 1
	while t < 44 do
		local c = if r() < 0.5 then 3 else 2
		add(t, "peony", side * lerp(200, 1300, r()), ry(300, 560), lerp(150, 210, r()), c, if r() < 0.3 then 4 else nil)
		side = -side
		t += if r() < 0.3 then 0.6 else 1.2
	end
	-- act 2: blue / green rings facing the beach + the bridge niagara (44-58)
	add(44, "niagara", 0, F.deckY, 800, 2, nil, 14)
	t = 45
	while t < 76 do
		add(t, "ring", rx(), ry(340, 600), lerp(160, 230, r()), if r() < 0.5 then 8 else 7, 3)
		if r() < 0.4 then
			add(t + 0.3, "palm", rx() * 0.6, ry(260, 380), 170, 3)
		end
		t += 1.4
	end
	-- act 3: rapid red / magenta / gold, crossettes
	t = 76
	while t < 116 do
		local kinds = { "peony", "crossette", "peony", "palm" }
		local k = kinds[math.floor(r() * #kinds) + 1]
		local cs = { 6, 4, 1, 9 }
		add(t, k, rx(), ry(), lerp(150, 230, r()), cs[math.floor(r() * #cs) + 1], if r() < 0.4 then 1 else nil)
		t += lerp(0.35, 0.7, r())
	end
	-- act 4: slow big chrysanthemums, doubles on the beat
	t = 116
	while t < 150 do
		local x = lerp(-900, 900, r())
		add(t, "peony", x, ry(420, 640), lerp(240, 300, r()), 5, 2)
		add(t + 0.5, "peony", -x, ry(420, 640), lerp(240, 300, r()), 3, 2)
		if r() < 0.5 then
			add(t + 1, "willow", lerp(-400, 400, r()), ry(500, 640), 230, 1)
		end
		t += 2
	end
	-- finale: barrage across the whole bridge + golden curtain, last flash at 176 s
	t = 150
	while t < 175 do
		local per = math.floor(lerp(2, 5, (t - 150) / 25))
		for _ = 1, per do
			local cs = { 1, 2, 3, 4, 6, 7, 9 }
			add(t + r() * 0.5, if r() < 0.25 then "crossette" else "peony", rx(), ry(), lerp(170, 260, r()), cs[math.floor(r() * #cs) + 1])
		end
		if (t * 2) % 4 == 0 then
			add(t, "willow", rx(), ry(520, 640), 240, 1)
		end
		t += 0.5
	end
	add(160, "niagara", 0, F.deckY, 800, 1, nil, 14)
	for k = 0, 6 do
		add(175 + k * 0.08, "willow", lerp(F.x0, F.x1, k / 6), 600, 260, 1)
	end
	add(176.6, "flash", 0, 520, 320, 2)
	table.sort(cues, function(a, b)
		return a.t < b.t
	end)
	return cues
end

-- Next in-game Saturday 17:00 as a server time, given the current weekday / clock / rate.
function D.nextFestival(now: number, weekday: number, clock: number, rate: number): number?
	if rate <= 0 then
		return nil
	end
	local F = D.FESTIVAL
	local days = (F.weekday - weekday) % 7
	local hours = days * 24 + (F.clock - clock)
	if hours <= 0 then
		hours += 7 * 24
	end
	return now + hours / rate
end

---------------------------------------------------------------------------------------------------
-- (8) 소소한 발견: coins, the lost wallet, cats
---------------------------------------------------------------------------------------------------
D.COIN = {
	amounts = { { 100, 0.72 }, { 500, 0.28 } }, -- amount, weight
	maxPerPlayer = 2, -- coins near one player at a time
	maxTotal = 14,
	interval = { 25, 55 }, -- seconds between spawn attempts per player
	near = { 30, 110 }, -- studs from the player
	life = 180, -- seconds before an untouched coin disappears
	reach = 4.5, -- client pick-up radius
	serverReach = 9,
	dailyMax = 30, -- coins per player per in-game day
	cooldown = 1.2,
}

D.WALLET = {
	chance = 0.55, -- per attempt
	interval = { 300, 600 }, -- seconds between attempts per player
	reward = { 5000, 20000 }, -- 사례금 (rounded to 1,000)
	stats = { happiness = 6, popularity = 1.5 },
	life = 240, -- an untouched wallet disappears
	counterName = "광안리 관광안내소 · 분실물 센터",
	counter = { x = 96, z = 101, yaw = 0 }, -- in front of the tourist information centre
	owners = { "김민지", "이도현", "박서연", "최준호", "정유나", "한지우", "윤태민", "오세아" },
	items = { "학생증", "주민등록증", "카드 3장", "가족사진", "영화표 2장", "네컷사진 한 장", "광안리 조개 키링" },
	daily = 3,
}

D.CATS = {
	radius = 120, -- cars within this distance of the camera may carry a sleeping cat at night
	share = 0.18, -- share of parked cars that have a cat (hash of the car position)
	colors = { { 236, 170, 90 }, { 60, 58, 60 }, { 238, 236, 230 }, { 150, 130, 110 } },
	night = { from = 19.5, to = 5.5 },
}

---------------------------------------------------------------------------------------------------
-- (9) 버스킹 (player performers)
---------------------------------------------------------------------------------------------------
D.BUSK = {
	length = 75, -- seconds per show
	cooldown = 45,
	radius = 26, -- audience radius
	tip = 1000, -- player tip amount (cash)
	tipCooldown = 2.5,
	tipMaxPerShow = 10, -- per tipper
	npcTipMax = 12000, -- NPC tips per show (scaled by accuracy)
	npcTipEvery = { 5, 11 }, -- seconds between NPC tips (best accuracy -> shortest)
	reportEvery = 4, -- client sends hit counts every N seconds
	lanes = 3,
	-- the 3 stages (existing builds: coast.Life "버스킹 (Busking)" + 밀락더마켓 버스킹 스퀘어)
	stages = {
		{ id = "meeting", name = "만남의 광장 무대", x = -262, z = -7, find = "버스킹 만남의 광장 무대" },
		{ id = "sunrise", name = "해맞이광장 버스킹존", x = 1121, z = -28, find = "버스킹 해맞이광장" },
		{ id = "millac", name = "밀락더마켓 버스킹 스퀘어", x = -3220, z = -557, find = "버스킹 스퀘어" },
	},
	instruments = {
		{ id = "guitar", name = "어쿠스틱 기타", icon = "🎸", pose = "guitar", gesture = "strum", tone = "rbxasset://sounds/electronicpingshort.wav", pitch = 0.75 },
		{ id = "keys", name = "키보드", icon = "🎹", pose = "hands_front", gesture = "strum", tone = "rbxasset://sounds/electronicpingshort.wav", pitch = 1.0 },
		{ id = "cajon", name = "카혼", icon = "🥁", pose = "hands_front", gesture = "clap", tone = "rbxasset://sounds/clickfast.wav", pitch = 0.6 },
		{ id = "violin", name = "바이올린", icon = "🎻", pose = "guitar", gesture = "strum", tone = "rbxasset://sounds/electronicpingshort.wav", pitch = 1.25 },
	},
	-- original song titles (no real songs)
	songs = {
		{ id = "night_sea", title = "광안리 밤바다", artist = "버스커 OST", bpm = 92, mood = "잔잔한" },
		{ id = "waves", title = "파도의 노래", artist = "버스커 OST", bpm = 104, mood = "시원한" },
		{ id = "gull_waltz", title = "갈매기 왈츠", artist = "버스커 OST", bpm = 120, mood = "경쾌한" },
		{ id = "millak_blues", title = "민락항 블루스", artist = "버스커 OST", bpm = 84, mood = "느긋한" },
		{ id = "summer_fire", title = "여름밤 불꽃", artist = "버스커 OST", bpm = 128, mood = "신나는" },
		{ id = "bridge", title = "광안대교를 건너며", artist = "버스커 OST", bpm = 98, mood = "감성" },
	},
	audienceLines = { "와 잘한다!", "한 곡 더!", "목소리 좋다~", "앵콜!", "👏👏👏", "여기 광안리 맛집이네", "인스타 올려도 돼요?" },
}
D.INSTRUMENT_BY_ID = {}
for _, it in D.BUSK.instruments do
	D.INSTRUMENT_BY_ID[it.id] = it
end
D.SONG_BY_ID = {}
for _, s in D.BUSK.songs do
	D.SONG_BY_ID[s.id] = s
end
D.STAGE_BY_ID = {}
for _, s in D.BUSK.stages do
	D.STAGE_BY_ID[s.id] = s
end

-- The note chart of a song: { {t, lane, hold} } for `length` seconds (deterministic per song id).
function D.songChart(songId: string, length: number?): { any }
	local song = D.SONG_BY_ID[songId] or D.BUSK.songs[1]
	local len = length or D.BUSK.length
	local seed = 7
	for k = 1, #song.id do
		seed = (seed * 31 + string.byte(song.id, k)) % 2147483647
	end
	local beat = 60 / song.bpm
	local notes = {}
	local i = 0
	local t = 2.0
	local lane = 2
	while t < len - 2 do
		i += 1
		local r = D.rand(seed, i)
		local step
		if r < 0.18 then
			step = beat * 0.5
		elseif r < 0.8 then
			step = beat
		else
			step = beat * 2
		end
		local lr = D.rand(seed, i + 1000)
		if lr < 0.33 then
			lane = 1
		elseif lr < 0.66 then
			lane = 2
		else
			lane = 3
		end
		local hold = 0
		if D.rand(seed, i + 2000) < 0.14 then
			hold = beat * (if D.rand(seed, i + 3000) < 0.5 then 1 else 2)
		end
		table.insert(notes, { t = t, lane = lane, hold = hold })
		t += step + hold
	end
	return notes
end

-- Accuracy (0..1) -> grade text
function D.grade(acc: number): string
	if acc >= 0.92 then
		return "S"
	elseif acc >= 0.8 then
		return "A"
	elseif acc >= 0.62 then
		return "B"
	elseif acc >= 0.4 then
		return "C"
	end
	return "D"
end

---------------------------------------------------------------------------------------------------
-- Beach geometry (same analytic profile as GwangalliAmbience/Env + ReplicatedStorage.GwangalliSeaData)
---------------------------------------------------------------------------------------------------
local SEA: any = nil
local function num(v: any, d: number): number
	return if type(v) == "number" and v == v then v else d
end
function D.setSeaData(sea: any)
	SEA = if type(sea) == "table" then sea else {}
end
local function sea(): any
	return SEA or {}
end
function D.beachRange(): (number, number)
	local s = sea()
	return num(s.beachX0, -2380), num(s.beachX1, 2380)
end
-- promenade edge z (Plan.P)
function D.promZ(x: number): number
	local A = num(sea().A, 0.0000324)
	return -A * x * x
end
local function sandWidth(x: number): number
	local s = sea()
	local W0, WK, WH = num(s.W0, 280), num(s.WK, 170), num(s.WH, 2380)
	local t = math.clamp(x / WH, -1, 1)
	return W0 - WK * t * t
end
-- 0.3 contour (where the wet sand starts)
function D.shoreZ(x: number): number
	return D.promZ(x) - sandWidth(x)
end
-- y = 0 water edge
function D.edgeZ(x: number): number
	local s = sea()
	local SY, FY, FD = num(s.SY, 0.3), num(s.FY, -5), num(s.FD, 150)
	local foreK = (SY - FY) / FD
	return D.shoreZ(x) - SY / foreK
end
function D.sandHeight(x: number, z: number): number
	local s = sea()
	local SY, TY = num(s.SY, 0.3), num(s.TY, 3.5)
	local FD, FY = num(s.FD, 150), num(s.FY, -5)
	local zs = D.shoreZ(x)
	if z >= zs then
		return SY + (TY - SY) * (z - zs) / sandWidth(x)
	end
	local d = zs - z
	if d <= FD then
		return SY + (FY - SY) * d / FD
	end
	return FY
end
-- Is (x, z) on the dry / wet beach sand (between the water edge and the sea wall)?
function D.onSand(x: number, z: number): boolean
	local x0, x1 = D.beachRange()
	if x < x0 + 4 or x > x1 - 4 then
		return false
	end
	return z <= D.promZ(x) - 6 and z >= D.edgeZ(x) - 1.5
end
-- The swash: how far inland of the water edge the current wave reaches (studs, along the normal).
-- Same swell as GwangalliAmbience (T 8.4 s, crests sweeping along the beach, every ~3rd wave bigger).
function D.swash(t: number, x: number): number
	local p = t / 8.4 - x / 950
	local idx = math.floor(p)
	p -= idx
	local set = 1 + 0.22 * math.sin(idx * 2.09 + 0.6) + 0.08 * math.sin(idx * 5.3)
	local rmax = 6 + 11 * (set - 0.7)
	local up = 0.3
	if p < up then
		local u = p / up
		return -2.5 + (rmax + 2.5) * (1 - (1 - u) ^ 2.3)
	end
	local u = (p - up) / (1 - up)
	local c = math.cos(u * math.pi) * 0.5 + 0.5
	return -2.5 + (rmax + 2.5) * c ^ 1.35
end

return D
