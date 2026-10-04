-- GwangalliVenuesShared: data + pure helpers for the venue interiors (owner: venues_detail):
-- 노래방 (광안 코인노래연습장), PC방 (광안 PC방), 헬스장 (광안 휘트니스 24), 볼링장 라운지 (광안 락볼링클럽).
-- Server: GwangalliGameplay/Venues.luau (+ VenueLife / VenueKaraoke / VenuePC). Client:
-- StarterPlayerScripts/GwangalliVenues.client.luau (+ folder GwangalliVenues). No instances are created
-- at require time, nothing yields; Lune can require it.
--
-- REMOTES (ReplicatedStorage.GwangalliRemotes, created by VenueLife.init):
--   VenueRequest  RemoteFunction client -> server (op: string, payload: table?) -> {ok, code?, message?, ...}
--     ops: "kSong" {room, song}  "kStop" {room}  "kScore" {room, serial, score, hits, notes}
--          "kLeave" {room}  "emote" {name = "tambourine"}
--          "pcScore" {score, seconds}  "pcLeave"  "pcBoard"
--          "order" {item, spot?}            (food: PC seat / counter / snack bar)
--          "gymStop"  "gymForm" {form 0..1} "routine"
--          "boards" {board}                 (leaderboard rows)
--   VenueEvent    RemoteEvent server -> client {kind = ...}:
--     "kOpen" {room}                         the song picker for that room (after renting / panel)
--     "kResult" {room, serial, name, score, mine}
--     "pcStart" {pc = Model, paidUntil, fee}  "pcEnd" {reason}  "pcRank" {rank, score, best}
--     "menu" {spot = BasePart, menu = "pcbang" | "bowling", items = {id...}}
--     "orderReady" {item}                    "ate" {item, applied}
--     "gymStart" {station = Instance, kind, style, machine, sets, reps, period}
--     "gymSet" {set, sets, gains = {stat = n}, stats = {strength, stamina, appearance}, routine?}
--     "gymEnd" {sets, summary}
--     "routine" {kinds = {kind...}, done = {kind = true}, complete = bool, labels = {kind = label}}
--     "punch" {score, best}
--
-- WORLD CONTRACT (tags / attributes written by the builders):
--   KaraokeRoom   Model Booth_NN: RoomNo, RoomName; children KaraokeScreen (TV face, SurfaceGui on
--                 GuiFace), KaraokeZone (invisible room box), KaraokePanel (prompt host), MirrorBall
--                 (+ PointLight "DiscoLight", disabled), BallSpin attribute on the ball.
--                 Runtime attributes (server): KRenter (UserId, 0 = free), KRenterName, KPaidUntil
--                 (server time), KSong (song id, "" = none), KStart (server time of beat 0), KSerial,
--                 KResultName, KResultScore, KResultSerial.
--   PCStation     Model PC_NN: PCNo, ServePos (Vector3 aisle point behind the chair), AislePos
--                 (Vector3, central aisle at the same depth), RamenCF (CFrame on the desk); children
--                 Seat, MonitorScreen (Neon, SurfaceGui face Back), Keyboard (prompt host).
--                 Runtime: PCUser (UserId, 0 = free).
--   VenueStaff    rig Model: Staff (id), Act (GwangalliAnim act), NpcName; runtime Moving (studs/s).
--                 The PC clerk also carries HomeCF (CFrame), ExitPos, EntryPos (Vector3).
--   VenueSpot     prompt host part: Spot = pc_counter | bowl_snack | bowl_shoes | bowl_punch |
--                 gym_water | gym_locker | gym_trainer; optional PickupCF (CFrame), Label.
--   VenueBoard    leaderboard part: Board = karaoke | pc | bowling | punch; SurfaceGui "BoardGui"
--                 with TextLabels Row1..Row5 (the server writes their Text).
--   GymStation    (GwangalliGameplayShared contract) + RepStyle (client motion style) + Machine (label).
--                 Runtime: InUse (UserId, 0 = free).
--   Player attribute GwVenueAct = "<act>" (tambourine | eat | drink | punch | gym:<style> | pc | sing)
--   while a venue action plays; GwVenueActT = server time it started. Every client animates the
--   characters that carry it (procedural GwangalliAnim pose layers), so everyone sees it.

local V = {}
V.VERSION = 1

V.Remote = { Request = "VenueRequest", Event = "VenueEvent" }
V.Tags = {
	KaraokeRoom = "KaraokeRoom",
	PCStation = "PCStation",
	Staff = "VenueStaff",
	Spot = "VenueSpot",
	Board = "VenueBoard",
}
V.Attr = {
	Act = "GwVenueAct",
	ActT = "GwVenueActT",
	InUse = "InUse",
	PCUser = "PCUser",
}

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
V.isNum = isNum

-- Real seconds for `m` in-game minutes (GwangalliConfig.DayLengthMinutes real minutes per day).
function V.gameMinutes(m: number, dayLengthMinutes: number?): number
	local dl = if isNum(dayLengthMinutes) and (dayLengthMinutes :: number) > 0 then dayLengthMinutes :: number else 24
	return m * dl * 60 / (24 * 60)
end

-------------------------------------------------------------------------------------------------
-- 노래방
-------------------------------------------------------------------------------------------------
V.KARAOKE = {
	fee = 500, -- per 30 in-game minutes (30 real seconds at the default day length)
	periodMinutes = 30,
	emptyGrace = 20, -- seconds a rented room may stay empty before it is released
	countdown = 3, -- seconds between picking a song and beat 0
	scoreWindow = { perfect = 0.12, good = 0.24 },
	dailyRewards = 12, -- songs a day that give 행복
	reward = { happiness = 3 },
	reward90 = { popularity = 1 }, -- 90+ (3 times a day)
	daily90 = 3,
}

-- ORIGINAL songs written for this game (fictional titles / artists, original placeholder lyrics).
V.SONGS = {
	{
		id = "s01", title = "광안대교 불빛 아래", artist = "파도청년단", genre = "발라드", bpm = 84, seed = 11,
		lines = { "다리 위에 불이 켜지면", "너의 이름 불러 볼게", "파도 소리 박자 맞춰", "천천히 걸어가자", "모래 위에 적은 약속", "밀물에도 남아 있길", "광안리의 밤하늘에", "별 하나를 걸어 둘게" },
	},
	{
		id = "s02", title = "민락동 치킨송", artist = "바삭즈", genre = "댄스", bpm = 120, seed = 23,
		lines = { "퇴근길엔 치킨 한 마리", "바닷바람 맞으면서", "양념 반에 후라이드 반", "오늘 하루 수고했어", "콜라 뚜껑 탁 따고서", "다 같이 건배 하나 둘", "민락동의 밤은 길다", "바삭바삭 춤을 춰" },
	},
	{
		id = "s03", title = "2호선 막차", artist = "금련산 밴드", genre = "록", bpm = 132, seed = 37,
		lines = { "막차는 벌써 떠났고", "택시는 잡히지 않아", "그래도 웃고 있는 건", "네가 옆에 있어서야", "가로등 하나 둘 셋", "발걸음은 가벼워", "새벽 공기 마시면서", "우리 집까지 달려" },
	},
	{
		id = "s04", title = "갈매기 트로트", artist = "김부산", genre = "트로트", bpm = 104, seed = 41,
		lines = { "끼룩끼룩 갈매기야", "어디로 날아가니", "광안리 앞바다에", "내 마음도 데려가렴", "떴다 떴다 저 구름아", "소식 좀 전해 주렴", "기다리는 그 사람도", "이 노래를 듣겠지" },
	},
	{
		id = "s05", title = "썸머 모래성", artist = "오션걸즈", genre = "팝", bpm = 112, seed = 53,
		lines = { "하얀 파도 넘실넘실", "모래성을 쌓아 볼까", "선크림을 듬뿍 바르고", "너에게로 달려가", "튜브 타고 둥실둥실", "햇살이 눈부신 날", "이 여름이 끝나도", "우리 꼭 다시 만나" },
	},
	{
		id = "s06", title = "PC방 영웅", artist = "레벨업", genre = "힙합", bpm = 96, seed = 67,
		lines = { "로그인 하면 시작돼", "오늘도 랭크 올려", "라면 하나 시켜 놓고", "키보드 위 손이 춤춰", "한 판만 더 외치다가", "벌써 해가 떴네", "엄마 전화 오기 전에", "마지막 판 승리해" },
	},
	{
		id = "s07", title = "새벽 편의점", artist = "도시소년", genre = "인디", bpm = 88, seed = 71,
		lines = { "불 켜진 편의점 앞에", "삼각김밥 하나 들고", "별일 없는 하루였지만", "괜찮다고 말해 줘", "유리문에 비친 얼굴", "조금은 피곤해 보여", "내일은 더 나을 거야", "바나나우유 건배" },
	},
	{
		id = "s08", title = "득근득근", artist = "헬스보이즈", genre = "EDM", bpm = 128, seed = 83,
		lines = { "하나 둘 셋 넷 스쿼트", "땀방울이 반짝반짝", "거울 속의 나에게", "오늘도 파이팅 외쳐", "벤치 위에 누워서", "숨을 크게 들이쉬고", "포기하지 않을 거야", "득근 득근 득근해" },
	},
	{
		id = "s09", title = "해운대 말고 광안리", artist = "수영구 청년회", genre = "시티팝", bpm = 100, seed = 97,
		lines = { "주말에는 어디 갈까", "고민할 필요 없잖아", "지하철 타고 금련산역", "걸어가면 바다야", "드론 쇼가 시작되면", "하늘 가득 반짝여", "사진 한 장 남겨 두고", "다음 주에 또 오자" },
	},
	{
		id = "s10", title = "생일 축하해 친구야", artist = "노래방 오리지널", genre = "축하곡", bpm = 108, seed = 101,
		lines = { "오늘은 너의 날이야", "촛불 하나 소원 하나", "케이크 위에 별을 켜고", "다 같이 박수 짝짝", "일 년 동안 고마웠어", "앞으로도 잘 부탁해", "웃음 가득 행복 가득", "생일 축하해 친구야" },
	},
}
V.SONG_BY_ID = {}
for i, s in V.SONGS do
	s.number = 38000 + i * 131 -- 노래번호 shown on the TV / picker
	V.SONG_BY_ID[s.id] = s
end

-- UTF-8 code points of a string (Hangul syllables are 3 bytes each).
local function codepoints(s: string): { string }
	local out = {}
	for _, c in utf8.codes(s) do
		table.insert(out, utf8.char(c))
	end
	return out
end
V.codepoints = codepoints

local function syllables(s: string): number
	local n = 0
	for _, ch in codepoints(s) do
		if ch ~= " " then
			n += 1
		end
	end
	return n
end

-- small deterministic generator (song seed -> melody)
local function lcg(seed: number): () -> number
	local st = (seed * 7919 + 13) % 2147483647
	return function(): number
		st = (st * 48271) % 2147483647
		return st / 2147483647
	end
end

local SCALE = { 0, 2, 4, 7, 9, 12, 14, 16, 19, 21 } -- major pentatonic, two octaves (semitones)
V.PITCH_MAX = 21

-- Chart of a song (pure; server and every client compute the same):
--   { bpm, beat (s), bar (s), intro (s), duration (s), lines = { {text, t0, t1, chars = {..}} },
--     notes = { {t, p (semitones 0..21), line, frac (0..1 position inside the line)} } }
-- Each lyric line spans 2 bars (8 beats): the words are sung over the first 6 beats, 3-5 tap notes
-- per line (one tap per ~2 syllables, never faster than every 1.2 beats).
function V.chart(song: any): any
	local beat = 60 / song.bpm
	local bar = beat * 4
	local intro = bar * 2
	local rnd = lcg(song.seed or 1)
	local lines, notes = {}, {}
	local deg = 4
	for i, text in song.lines do
		local t0 = intro + (i - 1) * bar * 2
		local t1 = t0 + beat * 6
		table.insert(lines, { text = text, t0 = t0, t1 = t1, chars = codepoints(text) })
		local m = math.clamp(math.ceil(syllables(text) / 2), 3, 5)
		local step = 6 / m
		for j = 0, m - 1 do
			local b = math.floor(j * step * 2 + 0.5) / 2
			deg = math.clamp(deg + math.floor(rnd() * 5) - 2, 1, #SCALE)
			if j == m - 1 and i % 2 == 0 then
				deg = math.clamp(deg - 1, 1, #SCALE) -- phrase endings fall
			end
			table.insert(notes, { t = t0 + b * beat, p = SCALE[deg], line = i, frac = b / 6 })
		end
	end
	local duration = intro + #song.lines * bar * 2 + bar
	return { bpm = song.bpm, beat = beat, bar = bar, intro = intro, duration = duration, lines = lines, notes = notes }
end

-- Score 0..100 from per-note judgements (perfect = 1, good = 0.6). A small floor keeps a
-- singer who joined late from a humiliating 0 (Korean 노래방 machines rarely go below 40).
function V.karaokeScore(perfect: number, good: number, total: number): number
	if not isNum(total) or total <= 0 then
		return 0
	end
	local raw = (math.max(0, perfect) + 0.6 * math.max(0, good)) / total
	return math.clamp(math.floor(40 + raw * 60 + 0.5), 0, 100)
end

function V.scoreComment(score: number): (string, string)
	if score >= 100 then
		return "축하합니다! 100점!", "전국 노래자랑 나가도 되겠어요 🎉"
	elseif score >= 90 then
		return "와우! 가수 데뷔?", "노래 실력이 프로급이에요 🎤"
	elseif score >= 80 then
		return "노래 실력 수준급!", "박자 감각이 좋아요 👏"
	elseif score >= 70 then
		return "흥이 넘쳐요!", "조금만 더 박자를 맞춰 봐요"
	end
	return "다음엔 더 잘할 수 있어요", "탬버린이라도 열심히 🪇"
end

-------------------------------------------------------------------------------------------------
-- PC방
-------------------------------------------------------------------------------------------------
V.PC = {
	feePerHour = 1000, -- per in-game hour (60 real seconds at the default day length)
	hourMinutes = 60,
	boardSize = 10,
	maxScoreRate = 90, -- points / second the racer can possibly earn (anti-cheat clamp)
	minSeconds = 3,
}

-- 광안대교 나이트 레이서 (client SurfaceGui game) tuning, shared so the server knows the limits.
V.RACER = {
	lanes = 3,
	startSpeed = 0.55, -- road lengths / second
	maxSpeed = 1.6,
	accel = 0.035, -- per second
	spawnEvery = { 1.15, 0.45 }, -- seconds between traffic cars (start, at max speed)
	pointsPerRoad = 50,
}

-------------------------------------------------------------------------------------------------
-- Food (PC방 counter / seat order, 볼링장 분식 코너)
-------------------------------------------------------------------------------------------------
-- prep: seconds until the order is ready; effect: stats applied when eaten (once per real day
-- `daily` times; buying always works); pose: the eat act ("eat" bowl + chopsticks, "drink" cup).
V.FOOD = {
	ramen = { name = "컵라면", icon = "🍜", price = 3500, prep = 20, menu = "pcbang", effect = { stamina = 4, happiness = 2 }, daily = 4, pose = "eat", prop = "ramen", eat = 7 },
	jjapa = { name = "짜파게티", icon = "🍝", price = 4000, prep = 20, menu = "pcbang", effect = { stamina = 4, happiness = 3 }, daily = 3, pose = "eat", prop = "ramen", eat = 7 },
	hotdog = { name = "핫도그", icon = "🌭", price = 2500, prep = 12, menu = "pcbang", effect = { stamina = 2, happiness = 1 }, daily = 4, pose = "eat_hand", prop = "hotdog", eat = 5 },
	pc_soda = { name = "탄산음료", icon = "🥤", price = 1500, prep = 6, menu = "pcbang", effect = { stamina = 1, happiness = 1 }, daily = 6, pose = "drink", prop = "cup", eat = 4 },
	tteokbokki = { name = "떡볶이", icon = "🌶️", price = 4000, prep = 10, menu = "bowling", effect = { stamina = 3, happiness = 3 }, daily = 3, pose = "eat", prop = "tteok", eat = 7 },
	eomuk = { name = "어묵꼬치", icon = "🍢", price = 2000, prep = 6, menu = "bowling", effect = { stamina = 2, happiness = 1 }, daily = 4, pose = "eat_hand", prop = "skewer", eat = 5 },
	fries = { name = "감자튀김", icon = "🍟", price = 4000, prep = 10, menu = "bowling", effect = { stamina = 2, happiness = 2 }, daily = 3, pose = "eat_hand", prop = "fries", eat = 6 },
	bowl_cola = { name = "콜라", icon = "🥤", price = 1500, prep = 4, menu = "bowling", effect = { stamina = 1, happiness = 1 }, daily = 6, pose = "drink", prop = "cup", eat = 4 },
}
V.MENUS = {
	pcbang = { "ramen", "jjapa", "hotdog", "pc_soda" },
	bowling = { "tteokbokki", "eomuk", "fries", "bowl_cola" },
}

-------------------------------------------------------------------------------------------------
-- 헬스장
-------------------------------------------------------------------------------------------------
V.GYM = {
	reps = 8, -- reps per set (client animation count; the server times the set)
	maxSets = 5, -- sets per session, then the session ends with a summary
	rest = 1.5, -- seconds between sets
	formBonus = 0.15, -- max extra gain for perfect form (rhythm taps)
	water = { stamina = 3, daily = 10, cooldown = 25 },
	routineCount = 3,
	routineReward = { strength = 1, stamina = 1, happiness = 4, appearance = 0.5, popularity = 0.5 },
}
-- Station kind -> rep period (seconds per rep) per motion style; the set length is
-- G.GYM[kind].duration, so reps = duration / period.
V.STYLE = {
	run = { period = 0.42, label = "러닝머신" },
	cycle = { period = 0.55, label = "실내 사이클" },
	row = { period = 1.5, label = "로잉머신" },
	bench = { period = 1.25, label = "벤치프레스" },
	squat = { period = 1.25, label = "스쿼트" },
	curl = { period = 1.0, label = "덤벨 컬" },
	pullup = { period = 1.0, label = "턱걸이" },
	cable = { period = 1.25, label = "케이블 크로스오버" },
	legpress = { period = 1.25, label = "레그프레스" },
	lat = { period = 1.25, label = "랫풀다운" },
	scan = { period = 3, label = "인바디" },
}
V.KIND_STYLE = { treadmill = "run", bike = "cycle", bench = "bench", squat = "squat", dumbbell = "curl", pullup = "pullup", inbody = "scan" }

-------------------------------------------------------------------------------------------------
-- 볼링장 라운지
-------------------------------------------------------------------------------------------------
V.SHOES = {
	price = 1500,
	returnDistance = 220, -- studs from the counter: leaving the venue returns the shoes
	colors = {
		{ name = "레드", main = { 200, 36, 44 }, trim = { 246, 246, 244 }, sole = { 40, 34, 34 } },
		{ name = "블루", main = { 30, 90, 200 }, trim = { 246, 246, 244 }, sole = { 40, 34, 34 } },
		{ name = "블랙", main = { 28, 28, 32 }, trim = { 220, 40, 50 }, sole = { 240, 240, 236 } },
		{ name = "그린", main = { 30, 150, 90 }, trim = { 246, 246, 244 }, sole = { 40, 34, 34 } },
		{ name = "퍼플", main = { 120, 50, 180 }, trim = { 255, 214, 60 }, sole = { 40, 34, 34 } },
	},
}
V.PUNCH = { price = 500, max = 999 }

-- Punch score: strength makes it bigger, the swing timing (0..1) adds up to 180.
function V.punchScore(strength: number, timing: number, roll: number): number
	local s = math.clamp(if isNum(strength) then strength else 0, 0, 100)
	local t = math.clamp(if isNum(timing) then timing else 0, 0, 1)
	local r = math.clamp(if isNum(roll) then roll else 0, 0, 1)
	return math.clamp(math.floor(280 + s * 4.2 + t * 180 + r * 140), 0, V.PUNCH.max)
end

-------------------------------------------------------------------------------------------------
-- Formatting
-------------------------------------------------------------------------------------------------
function V.won(n: any): string
	local v = if isNum(n) then math.floor(math.abs(n) + 0.5) else 0
	local s = tostring(v):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if s:sub(1, 1) == "," then
		s = s:sub(2)
	end
	return s .. "원"
end

function V.commas(n: any): string
	local v = if isNum(n) then math.floor(math.abs(n) + 0.5) else 0
	local s = tostring(v):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if s:sub(1, 1) == "," then
		s = s:sub(2)
	end
	return s
end

function V.mmss(sec: number): string
	local s = math.max(0, math.floor(if isNum(sec) then sec else 0))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Self-check used by the Lune tests / build: every song charts, every food item has a menu.
function V.validate(): { string }
	local problems = {}
	for _, s in V.SONGS do
		local c = V.chart(s)
		if #c.notes < #s.lines * 3 then
			table.insert(problems, "song " .. s.id .. " has too few notes")
		end
		if c.duration < 20 or c.duration > 120 then
			table.insert(problems, string.format("song %s duration %.1f", s.id, c.duration))
		end
	end
	for menu, list in V.MENUS do
		for _, id in list do
			if not V.FOOD[id] or V.FOOD[id].menu ~= menu then
				table.insert(problems, "menu " .. menu .. " item " .. id)
			end
		end
	end
	return problems
end

return V
