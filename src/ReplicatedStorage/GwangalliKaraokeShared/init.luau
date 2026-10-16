-- GwangalliKaraokeShared: the contract of GwangalliKaraokePlus (팡팡노래방-style 코인노래방 for the 8
-- booths of Workspace.Gwangalli.karaoke["광안 코인노래연습장"]). Required by the server Script
-- ServerScriptService.GwangalliKaraokePlus and the client LocalScript of the same name.
-- Pure data + helpers: nothing is created at require time and nothing yields.
--
--   local S = require(ReplicatedStorage.GwangalliKaraokeShared)
--   S.Config                      owner-tunable settings (see the Korean comments below)
--   S.Songs / S.Chart / S.Score / S.Search      child modules (catalog, timeline, scoring, 노래책 search)
--   S.NAMES                       instance / remote / attribute names
--   S.now()                       workspace:GetServerTimeNow()
--   S.won(n) S.mmss(s) S.commas(n) S.roomName(no)
--   S.int(v, lo, hi) S.num(v, lo, hi) S.str(v, maxLen) S.bool(v)      remote input validation
--   S.encode(t) S.decode(s)       JSON (HttpService, pcall-guarded)
--   S.tempoRate(step) S.keyRatio(semi)
--   S.parseClock(s) / S.formatClock(serial, anchorT, anchorS, rate) / S.songTime(clock, now)
--   S.pack(id) S.FX S.FX_BY_ID S.GENRES S.ERR S.ECHO_LABELS S.PRIVACY
--
-- TIME MODEL: a playing song is described by ONE string attribute "Clock" on the room state
-- (Configuration ReplicatedStorage.GwangalliKaraokeShared.State.Room_NN):
--     "serial|anchorT|anchorS|rate"   song time st(now) = anchorS + (now - anchorT) * rate
-- (seconds of the chart at the song's base tempo; rate = the 템포 factor, 0 while paused). A tempo
-- change mid-song re-anchors (anchorT = now, anchorS = st(now)), so lyrics, notes, the band and the
-- server's judge always agree. One attribute = an atomic update on every client.

local HttpService = game:GetService("HttpService")

local Shared = {}
Shared.VERSION = 1

-------------------------------------------------------------------------------------------------
-- 설정 (오너가 바꿀 수 있는 값). Everything here is read on both the server and the clients.
-------------------------------------------------------------------------------------------------
Shared.Config = {
	Enabled = true, -- false: 애드온 전체를 끕니다 (기존 노래방 그대로)
	TakeOverLegacy = true, -- 기존 VenueKaraoke 의 "방 잡기" 프롬프트를 끄고 이 애드온이 방을 운영합니다
	-- 요금: "credits" = 동전 곡 수 (1곡 500원 · 4곡 1,000원, 건물 안내판과 같음)
	--       "free"    = 방 잡기 무료 · 곡 무제한 (이벤트용)
	Billing = "credits",
	FreeWhenNoEconomy = true, -- 돈 시스템(GwangalliGameplayAPI)이 없으면 무료 체험으로 운영
	VenueModelNames = { "광안 코인노래연습장" }, -- KaraokeRoom 부스를 찾을 매장 모델 이름
	Packs = {
		{ id = "p1", songs = 1, price = 500, label = "1곡", sub = "동전 1개" },
		{ id = "p4", songs = 4, price = 1000, label = "4곡", sub = "지폐 1장", badge = "이득" },
		{ id = "p8", songs = 8, price = 2000, label = "8곡", sub = "지폐 2장", badge = "인기" },
	},
	MaxCredits = 30, -- 방에 쌓일 수 있는 남은 곡 수
	RefundWindow = 5, -- 곡 시작 후 이 시간(초) 안에 취소하면 1곡 돌려받음
	BonusScore = 100, -- 이 점수면 서비스 1곡
	BonusSongsMax = 2, -- 한 번 대여에 받을 수 있는 서비스 곡 수
	RestartMax = 2, -- 한 곡에서 "처음부터" 를 누를 수 있는 횟수
	PauseMax = 60, -- 일시정지 최대 시간(초), 지나면 자동 재생
	EmptyGrace = 40, -- 방이 비어 있으면 이 시간(초) 뒤 퇴실 처리 (남은 곡은 사라짐)
	IdleRelease = 150, -- 남은 곡도 예약도 없이 이 시간(초) 지나면 퇴실
	IdleWarn = 120,
	LeadIn = 1.2, -- 시작 버튼 후 반주가 시작되기까지(초)
	SettleTime = 1.5, -- 곡이 끝난 뒤 채점까지(초)
	ScoreHold = 7.5, -- 점수 화면 후 다음 예약곡까지(초)
	StopGap = 2.5, -- 취소 후 다음 예약곡까지(초)
	QueueMax = 20, -- 방 하나의 예약 곡 수
	QueuePerPlayer = 6, -- 한 사람이 예약할 수 있는 곡 수
	AllowedMax = 12, -- 방에 들어올 수 있는 인원 (방장 포함)
	DefaultPrivacy = "friends", -- "lock" 잠금(노크) · "friends" 로블록스 친구만 · "open" 누구나
	PushOutIntruders = true, -- 잠긴 방에 들어온 다른 손님을 문 밖으로 안내
	IntruderGrace = 1.5, -- 허락 없이 들어온 손님을 안내하기까지(초)
	KnockCooldown = 8, -- 노크 간격(초)
	MicReturnGrace = 3, -- 마이크를 들고 방 밖에 이만큼 있으면 제자리로
	MicOfferTTL = 10, -- 마이크 건네기 제안 유효 시간(초)
	AutoStartDelay = 1.2, -- 예약 후 (재생 중인 곡이 없으면) 자동 시작까지(초)
	PanelReach = 12, -- 방 밖에서 결제 · 노크할 수 있는 패널과의 거리
	TempoMin = -4, TempoMax = 4, TempoStep = 0.05, -- 템포 단계 (1단계 = 5%)
	KeyMin = -6, KeyMax = 6, -- 키 (반음)
	EchoMax = 5, EchoDefault = 3, -- 마이크 에코 단계 0..5
	Voice = "auto", -- "auto" = 음성 채팅(오디오 API)이 켜진 손님은 에코 마이크 + 목소리 채점, "off" = 끄기
	Soundproof = true, -- 방음: 방 안 사람의 목소리는 같은 방 사람에게만 들림 (오디오 API 필요)
	EchoAllMembers = false, -- true = 마이크를 안 잡아도 방 안 모든 사람 목소리에 에코
	-- 점수 보상 (VenueLife 의 일일 한도를 기존 노래방과 함께 씀)
	Rewards = {
		song = { happiness = 3 }, daily = 12, -- 곡을 끝까지 부르면 행복 +3 (하루 12번)
		high = { popularity = 1 }, highMin = 90, highDaily = 3, -- 90점 이상 인기도 +1 (하루 3번)
		cheer = { happiness = 1 }, cheerDaily = 5, cheerNeed = 8, -- 박자 맞춘 탬버린 8번이면 행복 +1
		minParticipation = 0.3, -- 채점에 필요한 참여율 (음표 또는 가사 줄 기준)
		minProgress = 0.6, -- 곡을 이만큼 이상 들어야 보상
	},
	-- 점수 코인 (선택): 높은 점수면 소액 상금. Amount = 0 이면 끔
	ScoreCoins = { MinScore = 95, Amount = 300, Cooldown = 300, DailyMax = 5, Label = "노래방 고득점 상금" },
	WriteBoard = true, -- 로비 "👑 오늘의 노래왕" 보드 갱신
	WriteLED = true, -- 로비 LED 전광판 (TOP 인기차트) 갱신
	DataStoreName = "GwangalliKaraokePlus_v1", -- 애창곡 · 최근 곡 · 최고 점수 · 설정 저장
	ChartStoreName = "GwangalliKaraokePlus_Chart_v1", -- 주간 인기차트 집계
	-- 반주 악기 소리 (rbxasset 기본 소리, 바꾸려면 rbxassetid://번호). midi = PlaybackSpeed 1 일 때의 음높이
	Samples = {
		tone = { id = "rbxasset://sounds/electronicpingshort.wav", midi = 76, gain = 1 },
		click = { id = "rbxasset://sounds/clickfast.wav", gain = 1 },
		noise = { id = "rbxasset://sounds/swoosh.wav", gain = 1 },
		thud = { id = "rbxasset://sounds/action_jump_land.mp3", gain = 1 },
		splash = { id = "rbxasset://sounds/impact_water.mp3", gain = 1 },
	},
	-- 선택: 직접 올린 드럼 / 효과음 asset id (비우면 위 기본 소리로 만듦)
	Instruments = { kick = "", snare = "", hat = "", clap = "", crash = "", tamb = "", cheer = "", firework = "" },
	-- 선택: 곡별 반주 음원 (라이선스가 있는 반주만!). Songs.luau 의 soundId 와 같음
	-- [곡 id] = { id = "rbxassetid://…", offset = 0 (음원의 0초 = 곡 시간 몇 초), gain = 0.5 }
	SongAudio = {},
	-- 효과 버튼 쿨다운 (초) · 서버도 같은 값으로 제한
	EffectCooldown = { tamb = 0.25, clap = 0.5, cheer = 2, fire = 3, petal = 3, dance = 4 },
	PromptKey = Enum.KeyCode.E,
	PromptGamepad = Enum.KeyCode.ButtonX,
	Debug = false,
}

-------------------------------------------------------------------------------------------------
-- names
-------------------------------------------------------------------------------------------------
Shared.NAMES = {
	Remotes = "Remotes",
	Request = "KPRequest", -- RemoteFunction (op, payload) -> { ok, code?, message?, ... }
	Event = "KPEvent", -- RemoteEvent server -> one client
	Live = "KPLive", -- UnreliableRemoteEvent (RemoteEvent fallback) server -> room members
	State = "State",
	RoomPrefix = "Room_",
	ServerFolder = "GwangalliKaraokePlus", -- Workspace folder of the server (voice nodes)
	ClientFolder = "GwKaraokePlusLocal", -- Workspace folder of each client (prompts, fx)
	Gui = "GwangalliKaraokePlus", -- PlayerGui ScreenGui
	TV = "GwKP_TV", -- PlayerGui SurfaceGui (Adornee = KaraokeScreen)
	SoundFolder = "GwKP_Band", -- SoundService folder of each client
	Tag = "KaraokeRoom",
	-- player attributes (server)
	PlayerRoom = "GwKPRoom", -- room no the player stands in (0 = none)
	PlayerMic = "GwKPMic", -- mic slot held (0 = none)
	PlayerAct = "GwKPAct", -- "clap:<n>" / "cheer:<n>" / "dance:<n>" (every client plays the emote)
	-- booth Model attributes written for the other teams (legacy names kept)
	KRenter = "KRenter",
	KRenterName = "KRenterName",
	KPaidUntil = "KPaidUntil",
	KPState = "KPState",
	KPCredits = "KPCredits",
	KPSongNo = "KPSongNo",
	KPMicsOut = "KPMicsOut",
	KPTambOut = "KPTambOut",
}

-------------------------------------------------------------------------------------------------
-- children
-------------------------------------------------------------------------------------------------
Shared.Songs = require(script:WaitForChild("Songs"))
Shared.Chart = require(script:WaitForChild("Chart"))
Shared.Score = require(script:WaitForChild("Score"))
Shared.Search = require(script:WaitForChild("Search"))

-------------------------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------------------------
function Shared.now(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(t) == "number" then t else os.clock()
end

function Shared.commas(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-" else "") .. out
end

function Shared.won(n: number): string
	return Shared.commas(tonumber(n) or 0) .. "원"
end

function Shared.mmss(sec: number): string
	local s = math.max(0, math.floor((tonumber(sec) or 0) + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

function Shared.roomName(no: number): string
	return string.format("%02d", tonumber(no) or 0)
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
Shared.finite = finite

-- integer in [lo, hi] or nil
function Shared.int(v: any, lo: number, hi: number): number?
	if not finite(v) then
		return nil
	end
	local n = math.floor(v)
	if n ~= v or n < lo or n > hi then
		return nil
	end
	return n
end

-- number clamped to [lo, hi] or nil when not a finite number
function Shared.num(v: any, lo: number, hi: number): number?
	if not finite(v) then
		return nil
	end
	return math.clamp(v, lo, hi)
end

-- non-empty string of at most maxLen bytes without control characters, or nil
function Shared.str(v: any, maxLen: number): string?
	if type(v) ~= "string" or #v == 0 or #v > maxLen then
		return nil
	end
	if string.find(v, "%c") then
		return nil
	end
	if not utf8.len(v) then
		return nil
	end
	return v
end

function Shared.bool(v: any): boolean?
	if type(v) == "boolean" then
		return v
	end
	return nil
end

function Shared.encode(t: any): string
	local ok, s = pcall(HttpService.JSONEncode, HttpService, t)
	return if ok and type(s) == "string" then s else "[]"
end

function Shared.decode(s: any): any
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, s)
	return if ok then t else nil
end

function Shared.tempoRate(step: number): number
	local C = Shared.Config
	local st = math.clamp(math.floor(tonumber(step) or 0), C.TempoMin, C.TempoMax)
	return 1 + st * C.TempoStep
end

function Shared.keyRatio(semi: number): number
	return 2 ^ ((tonumber(semi) or 0) / 12)
end

-- Clock = "serial|anchorT|anchorS|rate"
function Shared.formatClock(serial: number, anchorT: number, anchorS: number, rate: number): string
	return string.format("%d|%.4f|%.4f|%.4f", serial, anchorT, anchorS, rate)
end

export type Clock = { serial: number, anchorT: number, anchorS: number, rate: number }

function Shared.parseClock(s: any): Clock?
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local a, b, c, d = string.match(s, "^(%-?%d+)|(%-?[%d%.]+)|(%-?[%d%.]+)|(%-?[%d%.]+)$")
	if not a then
		return nil
	end
	return { serial = tonumber(a) :: number, anchorT = tonumber(b) :: number, anchorS = tonumber(c) :: number, rate = tonumber(d) :: number }
end

function Shared.songTime(clock: Clock?, now: number): number
	if not clock then
		return -math.huge
	end
	return clock.anchorS + (now - clock.anchorT) * clock.rate
end

-- server time at which song time `st` is reached (math.huge while paused and st is ahead)
function Shared.realTimeOf(clock: Clock, st: number): number
	if clock.rate <= 0 then
		return if st <= clock.anchorS then clock.anchorT else math.huge
	end
	return clock.anchorT + (st - clock.anchorS) / clock.rate
end

function Shared.pack(id: any): any?
	for _, p in Shared.Config.Packs do
		if p.id == id then
			return p
		end
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- UI vocabulary (Korean)
-------------------------------------------------------------------------------------------------
Shared.ECHO_LABELS = { [0] = "끄기", "약하게", "조금", "기본", "많이", "동굴" }
Shared.PRIVACY = {
	lock = { label = "🔒 잠금", sub = "노크한 손님만 들어와요" },
	friends = { label = "👥 친구만", sub = "로블록스 친구는 바로 들어와요" },
	open = { label = "🌐 누구나", sub = "누구나 들어와서 함께 불러요" },
}
Shared.PRIVACY_ORDER = { "lock", "friends", "open" }

-- effect buttons (탬버린 · 박수 · 환호 · 폭죽 · 꽃가루 · 춤)
Shared.FX = {
	{ id = "tamb", label = "탬버린", emoji = "🪇", color = { 255, 206, 70 } },
	{ id = "clap", label = "박수", emoji = "👏", color = { 120, 220, 255 } },
	{ id = "cheer", label = "환호", emoji = "🙌", color = { 255, 120, 200 } },
	{ id = "fire", label = "폭죽", emoji = "🎆", color = { 255, 150, 60 } },
	{ id = "petal", label = "꽃가루", emoji = "🌸", color = { 255, 170, 210 } },
	{ id = "dance", label = "춤", emoji = "💃", color = { 170, 130, 255 } },
}
Shared.FX_BY_ID = {}
for _, f in Shared.FX do
	Shared.FX_BY_ID[f.id] = f
end

-- 장르 (노래책 탭 · TV 배경 · 반주 스타일)
Shared.GENRES = {
	{ id = "발라드", emoji = "🌙", color = { 120, 170, 255 } },
	{ id = "댄스", emoji = "🪩", color = { 255, 92, 200 } },
	{ id = "트로트", emoji = "🎺", color = { 255, 196, 70 } },
	{ id = "힙합", emoji = "🎧", color = { 160, 120, 255 } },
	{ id = "락", emoji = "🎸", color = { 255, 90, 80 } },
	{ id = "동요", emoji = "🎈", color = { 120, 230, 160 } },
	{ id = "민요", emoji = "🪘", color = { 230, 170, 110 } },
	{ id = "OST", emoji = "🎬", color = { 90, 220, 230 } },
}

-- error codes -> Korean messages (the server sends both)
Shared.ERR = {
	room = "방을 찾을 수 없어요",
	notInside = "방 안에서만 할 수 있어요",
	near = "방 문 앞이나 안에서만 할 수 있어요",
	locked = "다른 손님이 이용 중인 방이에요 🔒 노크해 보세요",
	free = "먼저 방을 잡아 주세요 (문 옆 패널)",
	money = "잔액이 부족해요",
	busy = "처리 중이에요… 잠시만요",
	full = "남은 곡은 최대 %d곡까지 넣을 수 있어요",
	credits = "남은 곡이 없어요 · 동전을 넣어 주세요 🪙",
	queueFull = "예약은 %d곡까지예요",
	mine = "한 사람당 %d곡까지 예약할 수 있어요",
	nosong = "없는 곡 번호예요",
	rate = "잠시 후에 다시 시도해 주세요",
	renter = "방장만 할 수 있어요",
	role = "지금 부르는 사람이나 방장만 할 수 있어요",
	playing = "노래가 끝난 뒤에 할 수 있어요",
	notPlaying = "지금 재생 중인 곡이 없어요",
	another = "이미 다른 방을 이용 중이에요",
	mic = "마이크를 쓸 수 없어요",
	micBusy = "그 마이크는 다른 사람이 쓰고 있어요",
	cooldown = "조금 천천히! 잠시 후에 다시 눌러 주세요",
	target = "그 손님을 찾을 수 없어요",
	disabled = "지금은 쓸 수 없어요",
	bad = "잘못된 요청이에요",
	error = "잠시 후에 다시 시도해 주세요",
	legacy = "문 옆 패널에서 방을 잡아 주세요",
}

function Shared.err(code: string, ...: any): string
	local m = Shared.ERR[code] or Shared.ERR.error
	if select("#", ...) > 0 then
		local ok, s = pcall(string.format, m, ...)
		if ok then
			return s
		end
	end
	return m
end

-- remote op names (client <-> server contract; payloads are validated on the server)
Shared.OPS = {
	"hello", "buy", "reserve", "reserveNo", "cancel", "first", "start", "stop", "restart", "pause",
	"set", "privacy", "invite", "kick", "knock", "leave", "mic", "micAnswer", "hits", "voice",
	"voiceStatus", "cheer", "fav", "settings", "rank", "nearby",
}

return Shared
