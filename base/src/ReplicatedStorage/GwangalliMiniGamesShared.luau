--!strict
-- GwangalliMiniGamesShared (MS): data + pure helpers of the 광안리 해변 미니게임 거리 (docs/MINIGAMES.md).
-- Shared by the server feature module (ServerScriptService.GwangalliGameplay.MiniGames) and the client
-- (StarterPlayerScripts.GwangalliMiniGames). Nothing is created at require time and nothing yields.
--
-- MONEY: every stake / prize is the life game's in-game 원 (profile cash / bank, ctx.ledger on the
-- server). There is NO Robux, developer product or real-money path anywhere in this system and the
-- money can never be exchanged for anything outside the game (MS.VIRTUAL_CURRENCY_ONLY).
--
-- WORLD CONTRACT (server StationBuilder -> every client):
--   workspace.GwangalliMiniGames (Folder) / <stationId> (Model, tag MS.Tags.Station) with attributes
--     StationId, GameId, Label, NpcId ("" = no NPC host), and the live public state
--     State ("idle" | "waiting" | "playing" | "result"), P1 / P2 (display names), P1Id / P2Id (UserId,
--     negative = NPC), Stake, Pot, Score ("2 : 1" style, game defined), Turn (1 | 2 | 0), MatchId,
--     WaitStake (open table: the stake the seated player waits with), Spectators (count).
--   Game-specific broadcast attributes (passers-by see the game live), e.g. Omok: OmokBoard (225 chars
--   "0" empty / "1" black / "2" white), OmokLast (cell index, 0 = none), OmokSeq, OmokWin ("i,j,k,l,m").
--   Parts inside the model: Table (top centre = the play surface), SeatA / SeatB (Seat), PadA / PadB
--   (standing spots for stand games), CamA / CamB / CamSpec (camera hint parts, invisible), Board (Omok).
-- REMOTES: ReplicatedStorage.GwangalliMiniGames (Folder): Request (RemoteEvent, client -> server
--   (action, payload)), Update (RemoteEvent, server -> client (kind, payload)), Query (RemoteFunction:
--   records / leaderboard). Actions and kinds: see MS.Actions / MS.Kinds.

local MS = {}
MS.VERSION = 1
MS.VIRTUAL_CURRENCY_ONLY = true

MS.FolderName = "GwangalliMiniGames" -- ReplicatedStorage remotes + workspace stations share the name
MS.Remote = { Request = "Request", Update = "Update", Query = "Query" }
MS.Tags = { Station = "GwangalliMiniGameStation" }
MS.NpcFolder = "GwangalliNPCs" -- GwangalliNPCClient animates every rig in here (NPC.luau contract)
MS.DATASTORE = "GwangalliMiniGames_v1"
MS.KEY_PREFIX = "u_"

-- client -> server actions (payload is always a table)
MS.Actions = {
	sit = true, -- {station}                       게임 참가: sit at the open table and wait (stake picked)
	open = true, -- {station, stake}                 상대 찾기: sit + broadcast an open challenge server-wide
	challenge = true, -- {station, target, stake}    친구에게 신청
	respond = true, -- {id, accept}                   answer a challenge / open call
	join = true, -- {station}                         도전하기: take the free seat of a waiting table
	practice = true, -- {station, stake}             NPC와 연습
	spectate = true, -- {station}
	unspectate = true, -- {}
	leave = true, -- {}                               stand up (before play: refund) / close the result
	forfeit = true, -- {}                             기권 (playing: the opponent wins)
	rematch = true, -- {}                             재대결 vote (result screen)
	draw = true, -- {offer = bool}                   무승부 제안 / 수락 (turn games)
	move = true, -- {...}                              game input (game module validates)
	ping = true, -- {t}                                latency probe answer
}
-- server -> client kinds
MS.Kinds = {
	match = "match", -- full match view (participants + spectators)
	game = "game", -- game-only delta {id, g}
	event = "event", -- one-shot game event {id, e, ...} (sounds / emotes / reveals)
	invite = "invite", -- incoming challenge {id, from, fromId, game, stake, station, ttl, open?}
	inviteClosed = "inviteClosed", -- {id, reason}
	closed = "closed", -- the match is over for this client {id}
	toast = "toast", -- {kind, title, body}
	say = "say", -- speech bubble {model | head, text, dur}
	waypoint = "waypoint", -- walk to a table {station, pos, untilT} (accepted far away)
	ping = "ping", -- {t}
	record = "record", -- my record snapshot (after a match)
}

-------------------------------------------------------------------------------------------------
-- Money
-------------------------------------------------------------------------------------------------
MS.STAKES = { 0, 1000, 5000, 10000, 50000 } -- 0 = 친선전 (no money)
MS.MAX_STAKE = 50000
-- NPC practice: the house matches the stake, so the stakes are smaller per difficulty and the house's
-- daily payout to a player is capped (MS.NPC_DAILY_PROFIT_CAP): the NPCs are for practice, not farming.
MS.NPC_STAKES = {
	easy = { 0, 1000 },
	normal = { 0, 1000, 5000 },
	hard = { 0, 1000, 5000, 10000 },
}
MS.NPC_DAILY_PROFIT_CAP = 30000 -- net 원 a player may win from NPCs per KST day (beyond: stake back only)
MS.HOUSE_CUT = 0 -- fraction of a PvP pot kept by nobody (0 = the winner takes the whole pot)

function MS.isStake(v: any): boolean
	if type(v) ~= "number" then
		return false
	end
	for _, s in MS.STAKES do
		if s == v then
			return true
		end
	end
	return false
end

function MS.isNpcStake(difficulty: string, v: any): boolean
	local list = MS.NPC_STAKES[difficulty]
	if not list then
		return false
	end
	for _, s in list do
		if s == v then
			return true
		end
	end
	return false
end

-- Same rule as GwangalliGameplayShared.canAfford: one account (cash, or the bank by check card) covers it.
function MS.canAfford(cash: any, bank: any, amount: number): boolean
	if amount <= 0 then
		return true
	end
	local c = if type(cash) == "number" then cash else 0
	local b = if type(bank) == "number" then bank else 0
	return c >= amount or b >= amount
end

function MS.won(n: any): string
	local v = if type(n) == "number" and n == n then math.floor(math.abs(n) + 0.5) else 0
	local s = tostring(v):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if s:sub(1, 1) == "," then
		s = s:sub(2)
	end
	return "₩" .. s
end

function MS.stakeLabel(stake: number): string
	if stake <= 0 then
		return "친선전"
	end
	return MS.won(stake)
end

-------------------------------------------------------------------------------------------------
-- Games
-------------------------------------------------------------------------------------------------
-- kind: "table" (two seats facing each other across a table) | "stand" (two pads side by side at a
-- machine / face to face). turn: turn based (Turn attribute, draw offers).
export type GameInfo = { id: string, name: string, icon: string, kind: string, turn: boolean, desc: string, rounds: string }
MS.GAMES = {
	omok = { id = "omok", name = "오목", icon = "⚫", kind = "table", turn = true, desc = "다섯 알을 먼저 한 줄로!", rounds = "단판" },
	wordchain = { id = "wordchain", name = "끝말잇기", icon = "💬", kind = "table", turn = true, desc = "10초 안에 이어 말하기", rounds = "단판" },
	rps = { id = "rps", name = "가위바위보", icon = "✌️", kind = "stand", turn = false, desc = "3판 2선승", rounds = "3판 2선승" },
	reaction = { id = "reaction", name = "순발력 대결", icon = "⚡", kind = "stand", turn = false, desc = "\"지금!\" 에 먼저 누르기", rounds = "3판 2선승" },
	memory = { id = "memory", name = "기억력 대결", icon = "🧠", kind = "table", turn = false, desc = "숫자를 외워서 그대로", rounds = "끝까지" },
	numberguess = { id = "numberguess", name = "숫자 맞히기", icon = "🔢", kind = "table", turn = true, desc = "1~100 업다운", rounds = "단판" },
	timing = { id = "timing", name = "타이밍 게임", icon = "🎯", kind = "stand", turn = false, desc = "가운데에 딱 멈추기", rounds = "3라운드 합산" },
	quiz = { id = "quiz", name = "퀴즈 대결", icon = "❓", kind = "table", turn = false, desc = "먼저 맞히면 1점", rounds = "5문제" },
} :: { [string]: GameInfo }
MS.GAME_ORDER = { "omok", "wordchain", "rps", "reaction", "memory", "numberguess", "timing", "quiz" }

-- timings (seconds)
MS.T = {
	seatWalk = 2.2, -- sit down + camera move before the countdown
	countdown = 3, -- "3 2 1" before play starts
	result = 18, -- the result card stays (rematch window)
	inviteTTL = 25, -- a direct challenge waits this long
	openTTL = 60, -- an open call (상대 찾기) waits this long
	arriveTTL = 90, -- a player who accepted from far away has this long to walk to the table
	waitTTL = 240, -- a seated player waits this long for an opponent before standing up
	leaveGrace = 8, -- out of the seat / away from the pad during play before it counts as leaving
	nearStation = 14, -- studs: station buttons show / station actions accepted
	nearInvite = 45, -- studs: an accepted challenge seats you directly (no walk) within this range
	spectate = 60, -- studs: spectators further than this stop spectating
}

-------------------------------------------------------------------------------------------------
-- Records, rating and ranks
-------------------------------------------------------------------------------------------------
MS.RATING_START = 1000
MS.K_PVP = 24
MS.K_NPC = 10
MS.NPC_RATING = { easy = 900, normal = 1150, hard = 1450 }

export type Rank = { id: string, name: string, min: number, color: { number }, icon: string }
MS.RANKS = {
	{ id = "bronze", name = "브론즈", min = 0, color = { 205, 127, 50 }, icon = "🥉" },
	{ id = "silver", name = "실버", min = 1100, color = { 192, 200, 214 }, icon = "🥈" },
	{ id = "gold", name = "골드", min = 1250, color = { 255, 194, 71 }, icon = "🥇" },
	{ id = "platinum", name = "플래티넘", min = 1400, color = { 120, 230, 220 }, icon = "💠" },
	{ id = "diamond", name = "다이아", min = 1550, color = { 120, 170, 255 }, icon = "💎" },
} :: { Rank }
-- a rank needs this many rated games (PvP or NPC) before it shows above 브론즈
MS.RANK_MIN_GAMES = 5

function MS.rankOf(rating: number, games: number?): Rank
	local r = MS.RANKS[1]
	if (games or MS.RANK_MIN_GAMES) < MS.RANK_MIN_GAMES then
		return r
	end
	for _, rk in MS.RANKS do
		if rating >= rk.min then
			r = rk
		end
	end
	return r
end

-- Elo expectation and new rating (score 1 win / 0.5 draw / 0 loss).
function MS.expected(a: number, b: number): number
	return 1 / (1 + 10 ^ ((b - a) / 400))
end
function MS.rated(a: number, b: number, score: number, k: number): number
	local n = a + k * (score - MS.expected(a, b))
	return math.clamp(math.floor(n + 0.5), 100, 3000)
end

function MS.winRate(w: number, l: number): number
	local n = w + l
	if n <= 0 then
		return 0
	end
	return math.floor(w / n * 100 + 0.5)
end

-- Empty record (also the shape RewardService saves; sanitize keeps only these keys).
function MS.emptyRecord(): any
	local games = {}
	for _, id in MS.GAME_ORDER do
		games[id] = { w = 0, l = 0, d = 0, streak = 0, best = 0 }
	end
	return { v = 1, rating = MS.RATING_START, games = games, earned = 0, lost = 0, npcDay = { day = 0, net = 0 }, played = 0 }
end

function MS.sanitizeRecord(raw: any): any
	local r = MS.emptyRecord()
	if type(raw) ~= "table" then
		return r
	end
	local function n(v: any, lo: number, hi: number, d: number): number
		if type(v) ~= "number" or v ~= v then
			return d
		end
		return math.clamp(math.floor(v), lo, hi)
	end
	r.rating = n(raw.rating, 100, 3000, MS.RATING_START)
	r.earned = n(raw.earned, 0, 1e12, 0)
	r.lost = n(raw.lost, 0, 1e12, 0)
	r.played = n(raw.played, 0, 1e9, 0)
	if type(raw.npcDay) == "table" then
		r.npcDay = { day = n(raw.npcDay.day, 0, 1e9, 0), net = n(raw.npcDay.net, -1e12, 1e12, 0) }
	end
	if type(raw.games) == "table" then
		for _, id in MS.GAME_ORDER do
			local g = raw.games[id]
			if type(g) == "table" then
				r.games[id] = {
					w = n(g.w, 0, 1e9, 0),
					l = n(g.l, 0, 1e9, 0),
					d = n(g.d, 0, 1e9, 0),
					streak = n(g.streak, 0, 1e6, 0),
					best = n(g.best, 0, 1e6, 0),
				}
			end
		end
	end
	return r
end

function MS.totals(rec: any): (number, number, number)
	local w, l, d = 0, 0, 0
	for _, id in MS.GAME_ORDER do
		local g = rec.games[id]
		if g then
			w += g.w
			l += g.l
			d += g.d
		end
	end
	return w, l, d
end

-- KST calendar day number (the NPC payout cap resets at midnight in Korea).
function MS.kstDay(unix: number): number
	return (unix + 9 * 3600) // 86400
end

-------------------------------------------------------------------------------------------------
-- NPC hosts (one per station that has one). difficulty easy | normal | hard.
-- look = GwangalliNPCLooks.random hint; act = GwangalliAnim act while idle at the station.
-------------------------------------------------------------------------------------------------
MS.DIFFICULTY = { easy = "초보", normal = "일반", hard = "고수" }

export type NpcHost = {
	id: string,
	name: string,
	role: string,
	difficulty: string,
	look: { [string]: any },
	seed: number,
	lines: { [string]: { string } },
}
MS.NPCS = {
	parkssi = {
		id = "parkssi",
		name = "박씨 아저씨",
		role = "동네 아저씨",
		difficulty = "normal",
		look = { body = "m", age = 52, style = "casual" },
		seed = 4101,
		lines = {
			invite = { "오목 한 판 할래?", "어이 젊은이, 오목 둘 줄 아나?", "심심한데 한 판 두고 가라~" },
			start = { "봐주는 거 없다이~", "자, 흑 백 정했으니 시작하자." },
			think = { "음... 어디 보자...", "이거 참 고민되네.", "허허, 제법인데?" },
			good = { "오, 거기를 막네?", "좋은 수다!", "아이고, 그건 생각 못 했다." },
			win = { "허허, 아직 멀었다!", "또 와라, 또 놀아줄게~", "광안리 오목왕은 아직 나다!" },
			lose = { "졌다 졌다! 대단하네!", "아이고 내가 늙었나 보다...", "한 판 더 하자, 이번엔 진짜다!" },
			draw = { "비겼네? 실력이 비슷하구먼." },
			wait = { "누가 나랑 오목 한 판 안 두나~" },
		},
	},
	kimsabeom = {
		id = "kimsabeom",
		name = "김 사범님",
		role = "오목 고수 할아버지",
		difficulty = "hard",
		look = { body = "m", age = 71, style = "classic" },
		seed = 4207,
		lines = {
			invite = { "한 수 배우러 왔는가?", "광안리에서 나를 이긴 사람은 몇 없지." },
			start = { "천천히, 신중하게 두게.", "흑은 서두르면 지는 법이야." },
			think = { "흠...", "...그렇게 나온다 이거지.", "수읽기가 제법이군." },
			good = { "호오, 날카롭구먼.", "그 수, 나쁘지 않아." },
			win = { "아직 수련이 부족하군.", "다음엔 사삼을 조심하게.", "허허, 정진하게." },
			lose = { "내가 졌네. 훌륭한 수였어.", "오랜만에 진땀 뺐구먼!" },
			draw = { "무승부라... 좋은 승부였네." },
			wait = { "바닷바람 맞으며 두는 오목이 최고지." },
		},
	},
	minjun = {
		id = "minjun",
		name = "민준",
		role = "고등학생",
		difficulty = "normal",
		look = { body = "m", age = 17, style = "street" },
		seed = 5113,
		lines = {
			invite = { "형 끝말잇기 ㄱ?", "끝말잇기 한 판 하실래요?", "저 끝말잇기 좀 하는데 ㅋㅋ" },
			start = { "제가 먼저 할게요?", "ㄱㄱ 바로 시작!" },
			think = { "어... 잠깐만요", "아 그거 뭐였지", "음..." },
			good = { "오 그런 단어도 있어요?", "와 그걸로 오네" },
			win = { "ㅋㅋ 제가 이겼다!", "끝말잇기는 제 전문이죠~", "한 판 더? ㅋㅋ" },
			lose = { "아 뭐야 ㅋㅋ 졌다", "인정합니다... 고수시네요", "다음엔 안 져요!" },
			draw = { "ㅋㅋ 비김" },
			wait = { "아 심심하다... 끝말잇기 할 사람~" },
		},
	},
	hajun = {
		id = "hajun",
		name = "하준이",
		role = "초등학생",
		difficulty = "easy",
		look = { body = "m", age = 10, style = "kid" },
		seed = 5201,
		lines = {
			invite = { "형아/누나 끝말잇기 할래요?", "나랑 끝말잇기 해요!" },
			start = { "내가 먼저 할래!", "시작~!" },
			think = { "음... 음...", "엄마한테 물어봐야 하나...", "잠깐만!!" },
			good = { "우와 어려운 단어다!", "그게 뭐예요?" },
			win = { "야호! 내가 이겼다!", "나 천재인가 봐!" },
			lose = { "으앙 졌다...", "다음엔 이길 거야!" },
			draw = { "비겼다!" },
			wait = { "끝말잇기 할 사람 손!" },
		},
	},
	haeun = {
		id = "haeun",
		name = "하은",
		role = "서울에서 온 관광객",
		difficulty = "easy",
		look = { body = "f", age = 24, style = "tourist" },
		seed = 6107,
		lines = {
			invite = { "가위바위보 한 판?", "저랑 가위바위보 해요! 지면 사진 찍어주기~", "광안리 기념으로 가위바위보 어때요?" },
			start = { "안 내면 진다~", "준비됐죠?" },
			think = { "음... 뭐 내지?", "이번엔 바위 낼까... 아닌가?" },
			good = { "헉 어떻게 알았어요?", "와 운 좋다!" },
			win = { "꺄 이겼다!", "가위바위보 여왕!", "부산 여행 운 좋다~" },
			lose = { "아 졌다ㅠㅠ", "한 판만 더 해요!" },
			draw = { "비겼네요!" },
			wait = { "광안대교 너무 예쁘다... 누구 가위바위보 할 사람?" },
		},
	},
	dongsu = {
		id = "dongsu",
		name = "동수 과장",
		role = "출장 온 회사원",
		difficulty = "normal",
		look = { body = "m", age = 38, style = "office" },
		seed = 6211,
		lines = {
			invite = { "가위바위보로 스트레스 풀 사람?", "자네, 가위바위보 한 판 어때?" },
			start = { "회사에서 점심 내기 단련된 실력이야.", "가위바위보는 심리전이지." },
			think = { "패턴이 보인다...", "흠, 다음은..." },
			good = { "오, 읽었나?", "제법인데?" },
			win = { "역시 점심 내기 10년 짬!", "하하, 내가 이겼군!" },
			lose = { "부장님한테 지는 기분이구먼...", "졌다! 한 판 더!" },
			draw = { "비겼구만. 다시!" },
			wait = { "출장 와서 바다 보니 좋구먼..." },
		},
	},
	taeho = {
		id = "taeho",
		name = "태호",
		role = "편의점 알바생",
		difficulty = "normal",
		look = { body = "m", age = 22, style = "casual" },
		seed = 7103,
		lines = {
			invite = { "순발력 대결 하실래요? 저 손 빠른데", "쉬는 시간인데 한 판 해요!" },
			start = { "바코드 찍는 손이라 빨라요.", "집중!" },
			think = { "..." },
			good = { "와 빠르시네요!", "반응속도 뭐예요?" },
			win = { "역시 알바 짬은 못 속여요~", "제가 이겼네요!" },
			lose = { "와... 졌다.", "손이 안 따라가네요 ㅋㅋ" },
			draw = { "동시에 눌렀어요!" },
			wait = { "아 손 풀린다... 순발력 대결 하실 분?" },
		},
	},
	jiho = {
		id = "jiho",
		name = "지호",
		role = "동네 꼬마",
		difficulty = "easy",
		look = { body = "f", age = 9, style = "kid" },
		seed = 7207,
		lines = {
			invite = { "타이밍 게임 할래요? 나 잘해요!", "이거 같이 해요!" },
			start = { "가운데에 딱 멈추면 돼요!", "시작!" },
			think = { "으음..." },
			good = { "우와 딱 가운데다!", "대박!" },
			win = { "내가 이겼다~!", "헤헤" },
			lose = { "아잉 졌다...", "또 해요 또!" },
			draw = { "똑같다!" },
			wait = { "타이밍 게임 할 사람~" },
		},
	},
	sunja = {
		id = "sunja",
		name = "순자 할머니",
		role = "광안리 토박이",
		difficulty = "normal",
		look = { body = "f", age = 74, style = "classic" },
		seed = 8101,
		lines = {
			invite = { "기억력 내기 한번 할래? 할미 아직 정정하다~", "젊은이, 숫자 외우기 해볼래?" },
			start = { "잘 보고 외우거래이~", "할미 따라올 수 있겠나?" },
			think = { "어디 보자...", "아이고 이게 뭐였더라..." },
			good = { "아이고 잘 외우네!", "똑똑하네~" },
			win = { "할미가 아직 안 죽었다!", "호호, 또 오너라~" },
			lose = { "아이고 졌다, 똑똑하네!", "요새 젊은이들 머리 좋다~" },
			draw = { "둘 다 잘했네~" },
			wait = { "바다 보면서 숫자 외우면 머리가 맑아진다이~" },
		},
	},
	deokbae = {
		id = "deokbae",
		name = "덕배 할아버지",
		role = "산책하는 할아버지",
		difficulty = "normal",
		look = { body = "m", age = 68, style = "classic" },
		seed = 8203,
		lines = {
			invite = { "숫자 맞히기 한 판 하겠나?", "1부터 100 중에 내가 생각한 숫자, 맞혀볼래?" },
			start = { "업, 다운만 잘 들어라~", "시작하자!" },
			think = { "음... 이쯤인가?", "반으로 딱 나누면..." },
			good = { "오, 좁혀오는구먼!", "감이 좋네!" },
			win = { "허허, 내가 맞혔다!", "숫자는 반으로 나누는 게 비결이야." },
			lose = { "아이고 맞혔네!", "대단하구먼!" },
			draw = { "허허, 무승부네." },
			wait = { "숫자 맞히기 할 사람 없나~" },
		},
	},
	seoyeon = {
		id = "seoyeon",
		name = "서연",
		role = "퀴즈 동아리 대학생",
		difficulty = "hard",
		look = { body = "f", age = 21, style = "campus" },
		seed = 9107,
		lines = {
			invite = { "퀴즈 대결 하실래요? 저 퀴즈 동아리예요!", "상식 퀴즈 한 판 어때요?" },
			start = { "버저 빨리 누르는 사람이 이겨요!", "준비되셨죠?" },
			think = { "어... 이거 아는 건데!", "잠깐만요..." },
			good = { "와, 그걸 아세요?", "빠르시다!" },
			win = { "퀴즈 동아리의 자존심!", "다음 문제도 기대하세요~" },
			lose = { "와... 졌어요. 대단하세요!", "동아리 선배한테 혼나겠다 ㅠ" },
			draw = { "동점이네요!" },
			wait = { "오늘의 퀴즈 상대 구합니다~" },
		},
	},
} :: { [string]: NpcHost }

function MS.line(npc: NpcHost?, kind: string, seed: number?): string?
	if not npc then
		return nil
	end
	local list = npc.lines[kind]
	if not list or #list == 0 then
		return nil
	end
	local i = if seed then (math.floor(seed) % #list) + 1 else math.random(1, #list)
	return list[i]
end

-------------------------------------------------------------------------------------------------
-- Stations along the promenade (광안해변로 seaside band). x = position along the beach (studs, the
-- MapData coast frame: z = baseline(x) + n, the sea is -Z), n = distance from the seawall coping
-- (the seaside paving band is n 1..11; benches sit at n 7, the furniture strip at n 12..16). The
-- builder slides a station up to MS.SLIDE studs along the promenade to find a clear spot, so a
-- planter or a bench is never cut through. Stations sit in the gaps between bench groups so the
-- tables mix with the benches instead of forming one game hall.
-------------------------------------------------------------------------------------------------
export type StationSeed = { id: string, game: string, x: number, n: number, npc: string?, label: string }
MS.SLIDE = 26
MS.STATIONS = {
	{ id = "wordchain_west", game = "wordchain", x = -1590, n = 5, npc = "hajun", label = "민락 쪽 벤치" },
	{ id = "omok_west", game = "omok", x = -1290, n = 5, npc = nil, label = "민락 쪽 산책로" },
	{ id = "numberguess_west", game = "numberguess", x = -990, n = 5, npc = "deokbae", label = "축제의 광장 서쪽" },
	{ id = "timing_plaza", game = "timing", x = -420, n = 5, npc = "jiho", label = "만남의 광장 옆" },
	{ id = "omok_plaza", game = "omok", x = -330, n = 5, npc = "parkssi", label = "만남의 광장 앞" },
	{ id = "rps_center", game = "rps", x = -150, n = 5, npc = "haeun", label = "광안리 중앙" },
	{ id = "reaction_center", game = "reaction", x = -60, n = 5, npc = "taeho", label = "해변 중앙 데크 옆" },
	{ id = "wordchain_center", game = "wordchain", x = 210, n = 5, npc = "minjun", label = "관광안내소 앞" },
	{ id = "memory_east", game = "memory", x = 510, n = 5, npc = "sunja", label = "호메르스호텔 앞" },
	{ id = "omok_east", game = "omok", x = 780, n = 5, npc = "kimsabeom", label = "해변 동쪽 벤치" },
	{ id = "quiz_east", game = "quiz", x = 1200, n = 5, npc = "seoyeon", label = "해맞이광장 옆" },
	{ id = "rps_east", game = "rps", x = 1410, n = 5, npc = "dongsu", label = "남천 쪽 산책로" },
} :: { StationSeed }

-- MapData coast baseline (GwangalliPhone/MapData): the promenade's seawall coping follows this.
MS.COAST_A = 0.0000324
function MS.baseline(x: number): number
	return -MS.COAST_A * x * x
end

return MS
