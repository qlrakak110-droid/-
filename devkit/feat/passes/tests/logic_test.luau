--!nocheck
local R = require("../t/lib/rbx")
local E = R.env
local game, workspace, Instance, Enum, CFrame, Vector3, Color3, UDim2, UDim, Vector2, task = E.game, E.workspace, E.Instance, E.Enum, E.CFrame, E.Vector3, E.Color3, E.UDim2, E.UDim, E.Vector2, E.task
local NumberSequence, NumberSequenceKeypoint, ColorSequence, ColorSequenceKeypoint, Random, typeof, warn = E.NumberSequence, E.NumberSequenceKeypoint, E.ColorSequence, E.ColorSequenceKeypoint, E.Random, E.typeof, E.warn
local _ = typeof
local RaycastParams, OverlapParams = E.RaycastParams, E.OverlapParams
local __typeof = typeof
typeof = function(v) if type(v) == "table" and rawget(v, "_p") ~= nil then return "Instance" end return E.typeof(v) end
local __defs, __cache = {}, {}
local function __req(n) if __cache[n] == nil then __cache[n] = __defs[n]() end return __cache[n] end
__defs["Config"] = function()
-- GwangalliPassesShared/Config: every tunable of the pass add-on. The owner normally edits only PASSES[*].Id
-- (the game pass numbers from the Creator Dashboard). Id = 0 means "판매 준비 중": in a live server that pass is
-- hidden and its locks are not enforced (nobody could buy it); in Studio it is shown so every screen can be tried.
--
-- Studio test switches (workspace attributes, Studio only unless noted):
--   GwPassesStudioTest = true            every pass counts as owned
--   GwPassesStudioTest = "garage,flex"   only the listed passes (aliases garage | qol | flex)
--   GwPassesAdminFree = true (live too)  admins (Player attribute GwangalliAdmin, set by GwangalliLiveOps) own all

local Config = {}

Config.PASSES = {
	PremiumGarage = {
		Id = 0, -- 대시보드 게임패스 번호
		Price = 799, -- 추천가 (R$, 안내용; 실제 가격은 대시보드에서)
		Order = 7,
		Name = "프리미엄 차고",
		Title = "프리미엄 차고",
		Short = "차고",
		Glyph = "🏎️",
		Perk = "garage",
		Store = true,
		Desc = "하이퍼카 · 슈퍼카 · VIP · 오프로더 + 어디서든 내 차 호출(원격 차고) · 출장 정비",
		Perks = {
			"🏎️ 패스 전용 프리미엄 4대 (최고 210km/h 하이퍼카)",
			"📍 원격 차고: 어디서든 내 차 · 프리미엄 차를 바로 옆으로",
			"🎨 프리미엄 도색 14종 · 언더글로우",
			"🔧 출장 정비: 정비소에 안 가도 정비소 가격으로 수리",
		},
		C1 = Color3.fromRGB(255, 194, 71),
		C2 = Color3.fromRGB(255, 120, 60),
	},
	Convenience = {
		Id = 0,
		Price = 349,
		Order = 8,
		Name = "편의 패스",
		Title = "편의 패스",
		Short = "편의",
		Glyph = "⚡",
		Perk = "qol",
		Store = true,
		Desc = "유치장 · 기절 대기 시간 절반 + 폰 블랙마켓 앱 (어디서든 총기 · 탄약 주문)",
		Perks = {
			"⏱️ 유치장 수감 시간 50% 단축",
			"🏥 기절 후 병원 이송 대기 50% 단축",
			"📱 블랙마켓 앱: 총기상까지 안 가도 같은 가격으로 주문",
		},
		C1 = Color3.fromRGB(57, 255, 136),
		C2 = Color3.fromRGB(40, 160, 255),
	},
	Flex = {
		Id = 0,
		Price = 299,
		Order = 9,
		Name = "과시 패스",
		Title = "과시 패스",
		Short = "과시",
		Glyph = "✨",
		Perk = "flex",
		Store = true,
		Desc = "KO 피니시 이펙트 6종 · 나만의 번호판 · 네온 닉네임 (머리 위 + 채팅)",
		Perks = {
			"💥 KO 피니시 이펙트 6종 + 승리 포즈",
			"🔢 나만의 번호판 (스타일 6종, 내 모든 차에 적용)",
			"🌈 네온 닉네임: 머리 위 이름 + 채팅 이름 그라데이션",
		},
		C1 = Color3.fromRGB(255, 79, 163),
		C2 = Color3.fromRGB(150, 90, 255),
	},
}

-- Studio: show / sell-test passes whose Id is still 0
Config.STUDIO_SHOW_UNCONFIGURED = true
Config.STUDIO_ATTR = "GwPassesStudioTest"
Config.ADMIN_ATTR = "GwPassesAdminFree"
-- also hand the passes into ReplicatedStorage.GamePassConfig (phone "R$" app lists them) once their Id > 0
Config.INJECT_STORE = true

-- ownership checks
Config.OWNERSHIP = { RETRIES = 3, RETRY_GAP = 4, RECHECK = 300 }

---------------------------------------------------------------------------------------------------
-- #1 프리미엄 차고
---------------------------------------------------------------------------------------------------
Config.GARAGE = {
	-- 원격 차고: without the pass, OWNED / rented cars are called only inside the 정비소 zone (server enforced)
	REMOTE_LOCK = true,
	ZONE_RADIUS = 130, -- studs (horizontal) from the 정비소 venue pivot (tag GarageShop); Garage's own "at 정비소" is 150-170
	ZONE_FALLBACK = Vector3.new(-528, 7, 452), -- venue centre when the tag is missing
	STATION_RADIUS = 40, -- the kiosk itself also counts as the zone
	-- the 차량 호출 kiosk on the forecourt between the two planters (offset from the GarageReturn spot)
	STATION = { ENABLED = true, FROM_TAG = "GarageReturn", OFFSET = Vector3.new(18, 0, -1.4), FALLBACK = Vector3.new(-542, 6.7, 477.2), FACING = Vector3.new(0, 0, 1) },
	SUMMON_COOLDOWN = 4, -- s between premium summons (VS's own 8 s cooldown is skipped with force)
	SUMMON_SIDE = 9, -- studs to the player's side for "바로 내 옆"
	SUMMON_RADIUS = 400, -- road-lane search radius when the side spot is blocked
	REPAIR_FEE_MULT = 1.0, -- 출장 정비 = the 정비소 price x this
	PREVIEWS = true, -- ReplicatedStorage preview copies for the phone (3D cards)
	-- other add-ons may pass opts.gwAnywhere = true to spawnOwned (e.g. a dealership delivery) to skip the lock
}

---------------------------------------------------------------------------------------------------
-- #3 편의 패스
---------------------------------------------------------------------------------------------------
Config.QOL = {
	JAIL_MULT = 0.5,
	JAIL_MIN = 15, -- s
	KO_MULT = 0.5, -- SELF_HELP_AFTER (병원으로 이송 button), EMS_WAIT (no crew coming), EMS_TOTAL (crew never arrived)
	RESPAWN_MULT = 0.5, -- a real Roblox death / reset (Players.RespawnTime)
	-- "+ 50%" bail is untouched: GwangalliLawShared.bailFor scales with left / total, both halved
}

Config.MARKET = {
	SHOP_NAME = "📱 블랙마켓",
	RADIUS = 8, -- shop radius around the owner's own character (tradeCheck distance)
	OPEN_FEE = 0, -- 원 charged per opened session (접속료; 0 = same prices as the 총기상)
	OPEN_GAP = 1.5, -- s between open requests
}

---------------------------------------------------------------------------------------------------
-- #4 과시 패스
---------------------------------------------------------------------------------------------------
Config.PLATE = {
	MIN = 2, -- characters (not counting spaces)
	MAX = 8, -- characters (not counting spaces); "123가 4567" style plates fit
	MAX_TOTAL = 10, -- characters including spaces
	COOLDOWN = 20, -- s between changes
	UNIQUE = true, -- one plate text per player across servers (DataStore claim; falls back to this server)
	DEFAULT_STYLE = "classic",
}

Config.NEON = { DEFAULT = "bridge", TAG_DISTANCE = 90, TAG_OFFSET = 2.35, CHAT = true }

Config.KOFX = {
	DEFAULT = "lightning",
	PER_ATTACKER_GAP = 1.0, -- s
	SERVER_PER_SEC = 12,
	RANGE = 220, -- studs: who sees it
	MAX_LIVE = 3, -- client: concurrent effects
	PREVIEW_GAP = 3, -- s
	EMOTE = true, -- the attacker's short 승리 포즈 (Roblox default cheer / point animations)
}

---------------------------------------------------------------------------------------------------
-- data / net
---------------------------------------------------------------------------------------------------
Config.DATA = { STORE = "GwangalliPasses_v1", PLATES = "GwangalliPlates_v1", SAVE_DEBOUNCE = 8, RETRIES = 3 }
Config.NET = { BURST = 8, RATE = 4 } -- token bucket per player

-- client HUD shortcut (패스 상점 button under the "🚗 내 차" button)
Config.HUD = { ENABLED = true, SIZE = Vector2.new(92, 40), FALLBACK_POS = UDim2.new(1, -12, 0, 154) }

return Config

end
__defs["Lines"] = function()
-- GwangalliPassesShared/Lines: every Korean UI / notice string of the pass add-on (string.format templates).
--   Lines.t(key, ...) -> string      unknown keys return the key itself

local Lines = {}

local L = {
	-- passes / store
	app_title = "VIP 패스",
	app_sub = "광안리 프리미엄 혜택",
	not_ready = "판매 준비 중이에요",
	not_ready_studio = "판매 준비 중 · Studio에서는 workspace 속성 GwPassesStudioTest 로 시험해 보세요",
	buy = "R$ %d 로 열기",
	buy_plain = "구매하기",
	owned = "보유 중",
	bought = "패스 구매 완료! 바로 적용됐어요 ✦",
	bought_body = "%s 혜택이 지금부터 적용돼요",
	locked = "🔒 %s 전용",
	locked_tab = "%s 패스가 있으면 쓸 수 있어요",
	loading = "불러오는 중…",
	offline = "서버와 연결이 끊겼어요. 잠시 후 다시 시도해 주세요",
	busy = "잠시 후 다시 시도해 주세요",
	feature_off = "이 기능은 지금 준비 중이에요",

	-- remote garage lock (no pass)
	gate_refuse = "🔒 내 차는 광안 오토 정비소에서만 부를 수 있어요 · 원격 차고 패스가 있으면 어디서든 OK",
	gate_banner = "🔒 원격 차고 잠김",
	gate_banner_body = "내 차는 광안 오토 정비소의 '차량 호출' 키오스크 근처에서만 부를 수 있어요",
	gate_open = "📍 정비소 차량 호출 구역 · 여기서는 바로 부를 수 있어요",
	gate_owner = "👑 원격 차고 · 어디서든 내 차를 부를 수 있어요",
	gate_route = "정비소 길찾기",
	gate_buy = "원격 차고 패스",
	station_title = "차량 호출",
	station_object = "광안 오토 정비소",
	station_sign = "🚗 차량 호출",
	station_sub = "내 차 · 렌트 차 바로 부르기",

	-- premium garage
	summon_here = "📍 바로 내 옆으로",
	summon_road = "🛣️ 도로로",
	summon_back = "↩️ 돌려보내기",
	summon_arrived = "%s 도착!",
	summon_side = "%dm 옆에 세워 뒀어요",
	summon_lane = "옆에 세울 자리가 없어서 %dm 떨어진 도로에 세워 뒀어요",
	summon_driving = "운전 중에는 차를 부를 수 없어요",
	summon_cooldown = "잠시 후 다시 불러 주세요 (%d초)",
	summon_state = "지금은 차를 부를 수 없어요",
	summon_fail = "차를 부르지 못했어요",
	summon_none = "부른 프리미엄 차가 없어요",
	summon_dismissed = "차를 차고로 돌려보냈어요",
	paint_saved = "도색을 바꿨어요",
	repair_title = "🔧 출장 정비",
	repair_done = "🔧 출장 정비 완료! %s 상태 100%% · %s",
	repair_money = "돈이 부족해요 (%s 필요)",
	repair_full = "이미 상태가 좋아요",
	repair_none = "정비할 수 있는 내 차가 없어요",
	repair_rental = "렌트 차는 정비소에서 관리해요",
	repair_confirm = "%s 를 %s 에 출장 정비할까요?",
	garage_mine = "내 차 출장 정비",
	garage_premium = "패스 전용 프리미엄",

	-- 편의 패스
	jail_cut = "⚡ 편의 패스 · 유치장 %s → %s",
	jail_next = "편의 패스 혜택은 다음 체포부터 적용돼요",
	ko_chip = "⚡ 편의 패스 · %d초 후 병원으로 이송돼요",
	ko_chip_ems = "⚡ 편의 패스 · 119가 오고 있어요 (최대 %d초)",
	ko_forced = "⚡ 편의 패스 · 대기 시간이 절반으로 줄어 병원으로 이송해요",

	-- black market
	market_title = "블랙마켓",
	market_ok = "🟢 보안 연결됨 · 거래 가능",
	market_police = "🚓 근처에 경찰이 있어 접속이 차단됐어요",
	market_swat = "🚨 특임대가 근처에 있어요",
	market_gunfire = "🔫 총소리가 나서 거래가 잠시 멈췄어요",
	market_chased = "🚔 경찰에 쫓기는 중엔 접속할 수 없어요",
	market_seated = "🚗 차에서 내려야 거래할 수 있어요",
	market_busy = "😵 지금은 앱을 쓸 수 없어요",
	market_inactive = "📵 블랙마켓 서버가 응답하지 않아요",
	market_grudge = "🚫 거래처가 당신과 거래를 끊었어요",
	market_fee = "📱 블랙마켓 접속료",
	market_money = "접속료가 부족해요 (%s)",
	market_footer = "총기상과 같은 물건 · 같은 가격 · 경찰/특임대 근처에선 접속이 막혀요",
	market_basic = "기본 총기",
	market_basic_sub = "권총 · 기관단총 · 산탄총",
	market_upper = "조직 물건",
	market_upper_sub = "상위 등급 · 마피아 전용 물건 포함",
	market_ammo = "탄약",
	market_ammo_sub = "가진 총에 맞는 탄약 상자",

	-- flex: plate
	plate_title = "나만의 번호판",
	plate_rule = "번호판은 %d~%d글자, 한글 · 숫자 · 영어만 쓸 수 있어요",
	plate_bad = "사용할 수 없는 번호판이에요",
	plate_taken = "이미 누가 쓰는 번호판이에요",
	plate_saved = "번호판을 바꿨어요! 다음에 부르는 차부터 달려요",
	plate_cleared = "번호판을 기본으로 되돌렸어요",
	plate_cooldown = "번호판은 %d초 뒤에 다시 바꿀 수 있어요",
	plate_filter = "확인 서버가 응답하지 않아요. 잠시 후 다시 시도해 주세요",
	plate_hint = "예: 12가 3456 · 광안 1004 · GW 7777",
	-- flex: neon / kofx
	neon_title = "네온 닉네임",
	neon_off = "끄기",
	neon_saved = "네온 닉네임을 바꿨어요",
	kofx_title = "KO 피니시 이펙트",
	kofx_saved = "피니시 이펙트를 바꿨어요",
	kofx_preview = "▶ 미리보기",
	kofx_banner = "K.O.!",
}

Lines.L = L

function Lines.t(key: string, ...: any): string
	local s = L[key]
	if s == nil then
		return key
	end
	if select("#", ...) > 0 then
		local ok, out = pcall(string.format, s, ...)
		return if ok then out else s
	end
	return s
end

-- "2분 30초" / "45초"
function Lines.dur(sec: number): string
	local s = math.max(0, math.floor(sec + 0.5))
	local m = s // 60
	local r = s % 60
	if m > 0 and r > 0 then
		return string.format("%d분 %d초", m, r)
	elseif m > 0 then
		return string.format("%d분", m)
	end
	return string.format("%d초", r)
end

return Lines

end
__defs["Plates"] = function()
-- GwangalliPassesShared/Plates: custom plate rules (pure) + plate styles.
--   Plates.normalize(text) -> string            trim, collapse spaces, ASCII upper-case
--   Plates.validate(text) -> ok, code, clean     code: "len" | "chars" | "empty" | "digits"
--   Plates.korean(text) -> string                "12가3456" -> "12가 3456" (Korean plate spacing helper)
--   Plates.random(rng) -> string                 a random "123가 4567" plate (the editor's 🎲)
--   Plates.claimKey(clean) -> string             DataStore key (fixed-width base36 per codepoint)
--   Plates.STYLES / Plates.style(id)

local Config = __req("Config")

local Plates = {}

local function isHangul(cp: number): boolean
	return cp >= 0xAC00 and cp <= 0xD7A3
end

local function isDigit(cp: number): boolean
	return cp >= 48 and cp <= 57
end

local function isUpper(cp: number): boolean
	return cp >= 65 and cp <= 90
end

function Plates.normalize(text: any): string
	if type(text) ~= "string" then
		return ""
	end
	local s = string.gsub(text, "[%c]", " ")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	s = string.gsub(s, "%s+", " ")
	return string.upper(s)
end

-- -> ok, code, clean
function Plates.validate(text: any): (boolean, string?, string)
	local clean = Plates.normalize(text)
	if clean == "" then
		return false, "empty", clean
	end
	if not utf8.len(clean) then
		return false, "chars", clean
	end
	local total, solid, digits = 0, 0, 0
	for _, cp in utf8.codes(clean) do
		total += 1
		if cp == 32 then
			continue
		end
		solid += 1
		if isDigit(cp) then
			digits += 1
		elseif not (isHangul(cp) or isUpper(cp) or cp == 45) then
			return false, "chars", clean
		end
	end
	local P = Config.PLATE
	if solid < P.MIN or solid > P.MAX or total > P.MAX_TOTAL then
		return false, "len", clean
	end
	if digits == solid and solid > 7 then
		return false, "digits", clean -- a bare long number reads like a phone number
	end
	return true, nil, clean
end

-- Korean plate spacing: "<2-3 digits><hangul><4 digits>" gets the space before the last 4 digits
function Plates.korean(text: any): string
	local s = Plates.normalize(text)
	local compact = string.gsub(s, " ", "")
	local head, h, tail = string.match(compact, "^(%d%d%d?)([\234-\237][\128-\191][\128-\191])(%d%d%d%d)$")
	if head and h and tail then
		local cp = utf8.codepoint(h)
		if cp and isHangul(cp) then
			return head .. h .. " " .. tail
		end
	end
	return s
end

local SYL = { "가", "나", "다", "라", "마", "거", "너", "더", "러", "머", "버", "서", "어", "저", "고", "노", "도", "로", "모", "보", "소", "오", "조", "구", "누", "두", "루", "무", "부", "수", "우", "주" }
function Plates.random(rng: Random?): string
	local r = rng or Random.new()
	return string.format("%d%s %04d", r:NextInteger(100, 699), SYL[r:NextInteger(1, #SYL)], r:NextInteger(1000, 9999))
end

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n: number, width: number): string
	local out = ""
	for _ = 1, width do
		local d = n % 36
		out = string.sub(B36, d + 1, d + 1) .. out
		n = n // 36
	end
	return out
end

-- one key per plate regardless of spacing; 4 base36 chars per codepoint (max 8 * 4 + 2 = 34 < 50)
function Plates.claimKey(clean: string): string
	local compact = string.gsub(Plates.normalize(clean), " ", "")
	local parts = { "p_" }
	for _, cp in utf8.codes(compact) do
		table.insert(parts, b36(cp, 4))
	end
	return table.concat(parts)
end

---------------------------------------------------------------------------------------------------
-- styles: plate part colour / material, text colour / font, optional frame (thin bars around the plate)
---------------------------------------------------------------------------------------------------
Plates.STYLES = {
	{ id = "classic", name = "기본", bg = { 244, 244, 240 }, fg = { 18, 18, 20 }, font = "GothamBold" },
	{ id = "ev", name = "전기차", bg = { 60, 130, 220 }, bg2 = { 236, 242, 252 }, fg = { 14, 20, 40 }, font = "GothamBold", note = "파란 전기차 번호판" },
	{ id = "retro", name = "옛날 녹색", bg = { 36, 104, 64 }, fg = { 240, 236, 210 }, font = "Arcade", note = "2006년 이전 녹색 번호판" },
	{ id = "gold", name = "골드 VIP", bg = { 16, 16, 18 }, fg = { 236, 196, 110 }, font = "GothamBlack", frame = { 214, 176, 96 }, frameMat = "Metal" },
	{ id = "carbon", name = "카본", bg = { 34, 35, 38 }, fg = { 236, 238, 242 }, font = "GothamBold", frame = { 60, 62, 66 } },
	{ id = "neon", name = "네온", bg = { 10, 12, 20 }, fg = { 80, 230, 255 }, font = "GothamBlack", frame = { 80, 230, 255 }, frameMat = "Neon", glow = true },
}
Plates.BY_ID = {}
for _, s in Plates.STYLES do
	Plates.BY_ID[s.id] = s
end

function Plates.style(id: any): any
	return Plates.BY_ID[id or ""] or Plates.BY_ID[Config.PLATE.DEFAULT_STYLE] or Plates.STYLES[1]
end

function Plates.rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

function Plates.font(name: string): Enum.Font
	local ok, f = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	return if ok and f then f else Enum.Font.GothamBold
end

return Plates

end
__defs["Neon"] = function()
-- GwangalliPassesShared/Neon: neon nickname palettes (pure).
--   Neon.LIST / Neon.get(id)
--   Neon.sequence(p) -> ColorSequence          for a UIGradient (rainbow: a fixed hue wheel)
--   Neon.sample(p, t) -> Color3                 t in [0, 1]
--   Neon.rich(text, p, bold?) -> string         one <font color> per character (TextChatService PrefixText)

local Neon = {}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Neon.LIST = {
	{ id = "bridge", name = "광안대교", colors = { c(61, 214, 245), c(150, 110, 255), c(255, 79, 163) }, stroke = c(40, 20, 90), speed = 0.35 },
	{ id = "sunset", name = "해운대 노을", colors = { c(255, 170, 60), c(255, 96, 110), c(255, 70, 170) }, stroke = c(90, 20, 40), speed = 0.3 },
	{ id = "gold", name = "황금", colors = { c(255, 236, 150), c(255, 194, 71), c(220, 140, 30) }, stroke = c(70, 40, 0), speed = 0.25 },
	{ id = "aurora", name = "오로라", colors = { c(140, 255, 120), c(60, 230, 230), c(150, 100, 255) }, stroke = c(10, 50, 60), speed = 0.3 },
	{ id = "ice", name = "아이스", colors = { c(255, 255, 255), c(170, 230, 255), c(90, 170, 255) }, stroke = c(20, 50, 90), speed = 0.2 },
	{ id = "rainbow", name = "레인보우", rainbow = true, colors = { c(255, 60, 60), c(255, 200, 40), c(60, 230, 90), c(50, 170, 255), c(190, 80, 255) }, stroke = c(30, 30, 40), speed = 0.5 },
}
Neon.BY_ID = {}
for _, p in Neon.LIST do
	Neon.BY_ID[p.id] = p
end

function Neon.get(id: any): any
	return if type(id) == "string" then Neon.BY_ID[id] else nil
end

function Neon.sequence(p: any): ColorSequence
	local cols = p.colors
	if p.rainbow then
		local kps = {}
		for i = 0, 6 do
			table.insert(kps, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 0.75, 1)))
		end
		return ColorSequence.new(kps)
	end
	local kps = {}
	local n = #cols
	-- mirror the palette so an offset sweep loops without a seam: a b c b a
	local seq = table.clone(cols)
	for i = n - 1, 1, -1 do
		table.insert(seq, cols[i])
	end
	for i, col in seq do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#seq - 1), col))
	end
	return ColorSequence.new(kps)
end

function Neon.sample(p: any, t: number): Color3
	local cols = p.colors
	if p.rainbow then
		return Color3.fromHSV(t % 1, 0.7, 1)
	end
	local x = math.clamp(t, 0, 1) * (#cols - 1)
	local i = math.floor(x)
	local f = x - i
	local a = cols[math.clamp(i + 1, 1, #cols)]
	local b = cols[math.clamp(i + 2, 1, #cols)]
	return a:Lerp(b, f)
end

local function hex(col: Color3): string
	return string.format("#%02X%02X%02X", math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5))
end

local function escape(s: string): string
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	s = string.gsub(s, "\"", "&quot;")
	s = string.gsub(s, "'", "&apos;")
	return s
end

function Neon.rich(text: string, p: any, bold: boolean?): string
	local chars = {}
	for _, cp in utf8.codes(text) do
		table.insert(chars, utf8.char(cp))
	end
	local n = #chars
	local out = {}
	for i, ch in chars do
		local t = if n <= 1 then 0 else (i - 1) / (n - 1)
		table.insert(out, string.format("<font color=\"%s\">%s</font>", hex(Neon.sample(p, t)), escape(ch)))
	end
	local body = table.concat(out)
	return if bold then "<b>" .. body .. "</b>" else body
end

Neon.escape = escape
Neon.hex = hex

return Neon

end
__defs["KoFx"] = function()
-- GwangalliPassesShared/KoFx: KO 피니시 이펙트 definitions (pure data). Stylised only: no blood / gore.
-- Built-in content only (rbxasset:// particles and sounds, plus sound ids the place already uses).
--   KoFx.LIST / KoFx.get(id)

local KoFx = {}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

KoFx.TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
}

-- sounds: { id, fb (fallback when the id fails), vol, speed }
KoFx.SND = {
	boom = { id = "rbxassetid://82235785832022", fb = "rbxasset://sounds/action_jump_land.mp3", vol = 0.9, speed = 0.7 },
	ping = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.6, speed = 0.8 },
	pingHi = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.55, speed = 1.5 },
	swoosh = { id = "rbxasset://sounds/swoosh.wav", vol = 0.6, speed = 0.8 },
	crack = { id = "rbxasset://sounds/clickfast.wav", vol = 0.9, speed = 0.4 },
	coins = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.5, speed = 1.4 },
	thud = { id = "rbxassetid://132504023010884", fb = "rbxasset://sounds/action_jump_land.mp3", vol = 0.7, speed = 0.8 },
}

KoFx.LIST = {
	{ id = "lightning", name = "번개", glyph = "⚡", desc = "하늘에서 번개가 내리꽂히고 푸른 충격파", color = c(120, 210, 255), color2 = c(255, 255, 255), dur = 1.4, sounds = { "crack", "boom" } },
	{ id = "fireworks", name = "불꽃놀이", glyph = "🎆", desc = "광안리 불꽃축제처럼 머리 위로 폭죽 세 발", color = c(255, 200, 70), color2 = c(255, 80, 170), dur = 2.2, sounds = { "swoosh", "pingHi", "boom" } },
	{ id = "skull", name = "해골 마크", glyph = "💀", desc = "만화풍 해골 마크가 떠올랐다 사라져요", color = c(235, 235, 245), color2 = c(150, 90, 255), dur = 1.8, sounds = { "thud", "ping" } },
	{ id = "stars", name = "별 폭발", glyph = "🌟", desc = "노란 별이 사방으로 터지고 머리 위를 빙글빙글", color = c(255, 226, 90), color2 = c(255, 255, 255), dur = 1.8, sounds = { "pingHi", "swoosh" } },
	{ id = "money", name = "돈다발 비", glyph = "💸", desc = "만원짜리가 비처럼 쏟아져요", color = c(110, 200, 120), color2 = c(255, 214, 110), dur = 2.2, sounds = { "coins", "swoosh" } },
	{ id = "stamp", name = "K.O. 스탬프", glyph = "🥊", desc = "큼직한 K.O.! 도장과 먼지 링", color = c(255, 79, 163), color2 = c(255, 194, 71), dur = 1.6, sounds = { "thud", "crack" } },
}
KoFx.BY_ID = {}
for _, d in KoFx.LIST do
	KoFx.BY_ID[d.id] = d
end

function KoFx.get(id: any): any
	return if type(id) == "string" then KoFx.BY_ID[id] else nil
end

-- the attacker's short 승리 포즈: Roblox's own default emotes (owned by Roblox, playable in any experience;
-- the same ids ReplicatedStorage.GwangalliAnim / the default Animate script use)
KoFx.EMOTES = {
	R15 = { cheer = "rbxassetid://507770677", point = "rbxassetid://507770453" },
	R6 = { cheer = "rbxassetid://129423030", point = "rbxassetid://128853357" },
}
KoFx.EMOTE_FOR = { lightning = "point", fireworks = "cheer", skull = "point", stars = "cheer", money = "cheer", stamp = "point" }

return KoFx

end
__defs["Cars"] = function()
-- GwangalliPassesShared/Cars: the 프리미엄 차고 catalog (pure data) + handling specs + paints.
-- Each car is its own VehicleKind ("gw_*"), so the rig, the driver's controller and the server speed check all
-- read the same VS.Specs entry (both peers add it at start: Cars.install(VS)). Never police / taxi / ambulance.
--   body = "hyper" | "super"   our own part-built body (CarBodies)
--   base = "luxury" | "suv"    a clone of that kind's drive template (the map's G80 / Tucson) + a body kit

local Cars = {}

Cars.LIST = {
	{
		key = "hyper",
		kind = "gw_hyper",
		label = "광안 GT-X",
		class = "하이퍼카",
		glyph = "🏎️",
		body = "hyper",
		paint = "purple",
		glow = Color3.fromRGB(170, 90, 255),
		blurb = "미드십 하이퍼카 · 카본 리어윙 · 네온 라이트 블레이드",
		spec = { base = "luxury", topKmh = 210, reverseKmh = 30, accel = 34, brake = 58, drive = "AWD", mass = 168, gripF = 0.36, gripR = 0.37, steerLow = 33, steerHigh = 8, E = 0.26, U = 0.45, z = 0.66, hbGrip = 0.14, roll = 0.72 },
		seats = 2,
	},
	{
		key = "super",
		kind = "gw_super",
		label = "광안 GT",
		class = "슈퍼카",
		glyph = "🏁",
		body = "super",
		paint = "candy_red",
		glow = Color3.fromRGB(255, 70, 70),
		blurb = "프런트 엔진 GT 쿠페 · 덕테일 · 쿼드 머플러",
		spec = { base = "luxury", topKmh = 195, reverseKmh = 30, accel = 31, brake = 55, drive = "RWD", mass = 170, gripF = 0.35, gripR = 0.35, steerLow = 34, steerHigh = 8.5, E = 0.27, U = 0.48, z = 0.64, hbGrip = 0.13, roll = 0.68 },
		seats = 2,
	},
	{
		key = "vip",
		kind = "gw_vip",
		label = "VIP 블랙 에디션",
		class = "VIP 세단",
		glyph = "🖤",
		base = "luxury",
		paint = "matte_black",
		glow = Color3.fromRGB(255, 236, 200),
		blurb = "플래그십 세단 VIP 사양 · 짙은 썬팅 · 골드 번호판 프레임",
		spec = { base = "luxury", topKmh = 178, accel = 29, brake = 52, drive = "RWD", gripF = 0.32, gripR = 0.33, steerHigh = 9.5, z = 0.7 },
		interior = "g80",
		seats = 5,
	},
	{
		key = "offroad",
		kind = "gw_offroad",
		label = "몬스터 오프로더",
		class = "오프로더",
		glyph = "🛻",
		base = "suv",
		paint = "sand",
		glow = Color3.fromRGB(255, 190, 90),
		blurb = "리프트업 SUV · 루프 라이트바 · 불바 · 스노클",
		spec = { base = "suv", topKmh = 145, accel = 22, brake = 46, drive = "AWD", gripF = 0.34, gripR = 0.35, E = 0.42, U = 0.85, z = 0.5, roll = 0.66 },
		interior = "tucson",
		lift = 0.9,
		tyreGrow = 0.55,
		seats = 5,
	},
}

Cars.BY_KEY = {}
Cars.BY_KIND = {}
for i, c in Cars.LIST do
	c.order = i
	Cars.BY_KEY[c.key] = c
	Cars.BY_KIND[c.kind] = c
end

function Cars.get(key: any): any
	return if type(key) == "string" then Cars.BY_KEY[key] else nil
end

function Cars.carId(key: string): string
	return "gwp_" .. key
end

-- "gwp_hyper" -> "hyper"
function Cars.keyOfId(id: any): string?
	if type(id) ~= "string" or string.sub(id, 1, 4) ~= "gwp_" then
		return nil
	end
	local k = string.sub(id, 5)
	return if Cars.BY_KEY[k] then k else nil
end

-- the VS spec of a premium car (a clone of its base kind with our overrides)
function Cars.specFor(VS: any, car: any): any
	local base = VS.Specs[car.spec.base] or VS.Specs.luxury or VS.Specs.sedan
	local s = table.clone(base)
	for k, v in car.spec do
		if k ~= "base" then
			s[k] = v
		end
	end
	s.label = car.label
	s.model = car.label .. " (" .. car.class .. ")"
	return s
end

-- adds the four kinds to a VehicleShared table (server: also drivable / callable)
function Cars.install(VS: any, drivable: boolean)
	if type(VS) ~= "table" or type(VS.Specs) ~= "table" then
		return false
	end
	for _, car in Cars.LIST do
		if VS.Specs[car.kind] == nil then
			VS.Specs[car.kind] = Cars.specFor(VS, car)
		end
		if drivable and type(VS.Drivable) == "table" then
			VS.Drivable[car.kind] = true
		end
	end
	return true
end

---------------------------------------------------------------------------------------------------
-- paints: the 8 GS colours + 6 premium finishes. gs = the GwangalliGarageShared colour id used by other UIs.
---------------------------------------------------------------------------------------------------
Cars.PAINTS = {
	{ id = "white", name = "화이트", rgb = { 238, 239, 238 }, gs = "white" },
	{ id = "black", name = "블랙", rgb = { 18, 19, 21 }, gs = "black", refl = 0.12 },
	{ id = "silver", name = "실버", rgb = { 178, 182, 186 }, gs = "silver", refl = 0.1 },
	{ id = "grey", name = "그레이", rgb = { 96, 100, 104 }, gs = "grey" },
	{ id = "navy", name = "네이비", rgb = { 30, 48, 88 }, gs = "navy", refl = 0.08 },
	{ id = "red", name = "레드", rgb = { 150, 30, 34 }, gs = "red" },
	{ id = "beige", name = "베이지", rgb = { 192, 182, 162 }, gs = "beige" },
	{ id = "mint", name = "민트", rgb = { 142, 170, 160 }, gs = "mint" },
	{ id = "matte_black", name = "매트 블랙", rgb = { 28, 29, 32 }, gs = "black", mat = "SmoothPlastic", refl = 0, premium = true },
	{ id = "pearl", name = "펄 화이트", rgb = { 246, 244, 238 }, gs = "white", refl = 0.22, premium = true },
	{ id = "candy_red", name = "캔디 레드", rgb = { 196, 18, 36 }, gs = "red", refl = 0.18, premium = true },
	{ id = "lime", name = "네온 라임", rgb = { 170, 240, 40 }, gs = "mint", refl = 0.12, premium = true },
	{ id = "purple", name = "미드나잇 퍼플", rgb = { 74, 32, 140 }, gs = "navy", refl = 0.18, premium = true },
	{ id = "gold", name = "샴페인 골드", rgb = { 214, 176, 104 }, gs = "beige", refl = 0.2, premium = true },
	{ id = "sand", name = "샌드 카키", rgb = { 176, 154, 112 }, gs = "beige", premium = true },
}
Cars.PAINT_BY_ID = {}
for _, p in Cars.PAINTS do
	Cars.PAINT_BY_ID[p.id] = p
end

function Cars.paint(id: any): any
	return Cars.PAINT_BY_ID[id or ""] or Cars.PAINT_BY_ID.black
end

function Cars.paintColor(p: any): Color3
	return Color3.fromRGB(p.rgb[1], p.rgb[2], p.rgb[3])
end

-- a stable default plate per player and car ("부산12가 3456" style; VIP: "VIP 1234")
local HANGUL = { "가", "나", "다", "라", "마", "거", "너", "더", "러", "머", "버", "서", "어", "저", "고", "노", "도", "로", "모", "보", "소", "오", "조" }
function Cars.defaultPlate(userId: number, key: string): string
	local seed = (math.abs(math.floor(tonumber(userId) or 0)) % 1000003) * 31 + #key * 7 + string.byte(key, 1)
	local rng = Random.new(seed)
	if key == "vip" then
		return string.format("VIP %04d", rng:NextInteger(1000, 9999))
	end
	return string.format("부산%02d%s %04d", rng:NextInteger(10, 99), HANGUL[rng:NextInteger(1, #HANGUL)], rng:NextInteger(1000, 9999))
end

return Cars

end
__defs["P"] = function()
-- GwangalliPassesShared (ModuleScript, ReplicatedStorage): the shared half of GwangalliPasses, three Robux
-- game passes for 광안리:
--   #1 프리미엄 차고 (PremiumGarage)  premium cars (하이퍼카 · 슈퍼카 · VIP · 오프로더) + 원격 차고 (call your car
--                                    anywhere; without it owned cars are called only at 광안 오토 정비소)
--   #3 편의 패스 (Convenience)         jail / KO wait x0.5 + the phone 블랙마켓 app (the 총기상's own shop, remote)
--   #4 과시 패스 (Flex)                KO 피니시 이펙트, custom plate, neon nickname (overhead + chat)
--   Server: ServerScriptService.GwangalliPasses (Script)   Client: StarterPlayerScripts.GwangalliPasses
--
--   local P = require(ReplicatedStorage.GwangalliPassesShared)
--   P.has(player, "garage" | "qol" | "flex" | "PremiumGarage" | ...) -> boolean   (server-written attribute)
--   P.changed(player, fn(key, owned)) -> RBXScriptConnection
--   P.available(key) -> boolean   (pass Id configured, or Studio)
--   P.Config / P.Lines and lazily P.mod("Cars" | "CarBodies" | "Plates" | "Neon" | "KoFx")
-- Pure: nothing is created at require time and nothing yields except the child WaitForChild calls.

local RunService = game:GetService("RunService")

local P = {}
P.VERSION = 1

P.Config = __req("Config")
P.Lines = __req("Lines")

local mods: { [string]: any } = {}
function P.mod(name: string): any
	local m = mods[name]
	if m == nil then
		m = __req(name)
		mods[name] = m
	end
	return m
end

-- instance names -------------------------------------------------------------------------------------
P.REMOTES = "GwangalliPassesRemotes" -- Folder in ReplicatedStorage (server-made)
P.REQUEST = "Request" -- RemoteFunction client -> server (op, payload) -> result table
P.EVENT = "Event" -- RemoteEvent server -> client (payload table with `kind`)
P.API = "GwangalliPassesAPI" -- ServerStorage BindableFunction for other add-ons
P.CHANGED = "GwangalliPassesChanged" -- ServerStorage BindableEvent (player, key, owned)
P.TEMPLATES = "GwangalliPassesTemplates" -- ServerStorage: premium car templates (server only)
P.PREVIEWS = "GwangalliPassesPreviews" -- ReplicatedStorage: light copies for the phone's 3D previews
P.WORLD = "GwangalliPassesWorld" -- Workspace: the 정비소 차량 호출 kiosk
P.FX = "GwPassesFxLocal" -- Workspace (client only): KO finish effects

-- pass keys --------------------------------------------------------------------------------------------
P.KEYS = { garage = "PremiumGarage", qol = "Convenience", flex = "Flex" }
P.ORDER = { "PremiumGarage", "Convenience", "Flex" }
P.ALIAS = { PremiumGarage = "garage", Convenience = "qol", Flex = "flex" }

P.Attr = {
	Owned = "GwPass_", -- Player: GwPass_<key> = true (same convention as GwangalliPassPerks / GwangalliStore)
	Neon = "GwNeonName", -- Player: neon palette id ("" / nil = off)
	KoFx = "GwKoFx", -- Player: KO finish effect id ("" / nil = off)
	Plate = "GwVanityPlate", -- Player: custom plate text (nil = none)
	PlateStyle = "GwPlateStyle", -- Player / car model: plate style id
	AtGarage = "GwPassAtGarage", -- Player: true while inside the 정비소 call zone (server computed)
	KOEnd = "GwPassQoLKOEnd", -- Player: server time the 편의 패스 sends a downed owner to hospital
	Premium = "GwPremiumCar", -- car Model: premium car key
	Ready = "GwPassesReady", -- ReplicatedStorage folder attribute: features that hooked fine (JSON)
	Station = "GwPassesStation", -- the kiosk part (client finds the prompt by this attribute)
}

-- canonical pass key from an alias / key (case-insensitive), or nil
function P.key(k: any): string?
	if type(k) ~= "string" then
		return nil
	end
	local low = string.lower(k)
	for alias, key in P.KEYS do
		if low == alias or low == string.lower(key) then
			return key
		end
	end
	return nil
end

function P.def(key: string): any
	return P.Config.PASSES[key]
end

function P.idOf(key: string): number
	local d = P.Config.PASSES[key]
	local id = d and tonumber(d.Id) or 0
	return if id and id > 0 then math.floor(id) else 0
end

-- A pass is "available" (shown, sold, its locks enforced) once its Id is set; in Studio always, so the owner
-- can try every screen before uploading the passes.
function P.available(k: any): boolean
	local key = P.key(k)
	if not key then
		return false
	end
	if P.idOf(key) > 0 then
		return true
	end
	return RunService:IsStudio() and P.Config.STUDIO_SHOW_UNCONFIGURED == true
end

function P.anyAvailable(): boolean
	for _, key in P.ORDER do
		if P.available(key) then
			return true
		end
	end
	return false
end

-- ownership as the server published it (Player attribute). Works on both peers.
function P.has(player: any, k: any): boolean
	local key = P.key(k)
	if not key or typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	return player:GetAttribute(P.Attr.Owned .. key) == true
end

function P.ownedMap(player: Player): { [string]: boolean }
	local out = {}
	for _, key in P.ORDER do
		out[key] = P.has(player, key)
	end
	return out
end

function P.changed(player: Player, fn: (string, boolean) -> ()): RBXScriptConnection
	return player.AttributeChanged:Connect(function(name: string)
		local prefix = P.Attr.Owned
		if string.sub(name, 1, #prefix) == prefix then
			local key = string.sub(name, #prefix + 1)
			if P.Config.PASSES[key] then
				fn(key, player:GetAttribute(name) == true)
			end
		end
	end)
end

function P.serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok then t else os.time()
end

-- "12,345원"
function P.won(n: any): string
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(v))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if v < 0 then "-" else "") .. out .. "원"
end

return P

end
__defs["Util"] = function()
-- GwangalliPasses/Util (server): small helpers shared by the pass modules (lookups with timeouts, guarded
-- requires, token buckets, player state checks). Nothing here yields unless its name says wait*.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Util = {}

local warned: { [string]: boolean } = {}
function Util.warnOnce(key: string, msg: any)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[GwangalliPasses] " .. key .. ": " .. tostring(msg))
end

function Util.log(...: any)
	print("[GwangalliPasses]", ...)
end

-- parent:WaitForChild(name) with a timeout and an optional class check (the place has a Script and a Folder
-- of the same name side by side, e.g. ServerScriptService.GwangalliVehicles)
function Util.waitChild(parent: Instance, name: string, className: string?, timeout: number?): Instance?
	local deadline = os.clock() + (timeout or 60)
	while true do
		for _, c in parent:GetChildren() do
			if c.Name == name and (className == nil or c:IsA(className)) then
				return c
			end
		end
		if os.clock() >= deadline then
			return nil
		end
		task.wait(0.25)
	end
end

function Util.findChild(parent: Instance?, name: string, className: string?): Instance?
	if not parent then
		return nil
	end
	for _, c in parent:GetChildren() do
		if c.Name == name and (className == nil or c:IsA(className)) then
			return c
		end
	end
	return nil
end

-- ServerScriptService.<folder>(Folder) / a / b ... -> ModuleScript, required (pcall)
function Util.requirePath(folderName: string, path: { string }, timeout: number?): any
	local folder = Util.waitChild(ServerScriptService, folderName, "Folder", timeout or 60)
	if not folder then
		return nil, "no folder " .. folderName
	end
	local node: Instance = folder
	for _, name in path do
		local nxt = Util.waitChild(node, name, nil, 20)
		if not nxt then
			return nil, "missing " .. name
		end
		node = nxt
	end
	if not node:IsA("ModuleScript") then
		return nil, node.Name .. " is not a ModuleScript"
	end
	local ok, res = pcall(require, node)
	if not ok or type(res) ~= "table" then
		return nil, tostring(res)
	end
	return res, nil
end

function Util.requireShared(parent: Instance, name: string, timeout: number?): any
	local m = Util.waitChild(parent, name, "ModuleScript", timeout or 30)
	if not m then
		return nil
	end
	local ok, res = pcall(require, m)
	return if ok then res else nil
end

-- wraps tbl[name] once: tbl[name] = make(original). Returns the original (or nil when missing).
local wrappedFns = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
function Util.wrap(tbl: any, name: string, make: (any) -> any): any
	if type(tbl) ~= "table" or type(tbl[name]) ~= "function" then
		return nil
	end
	local cur = tbl[name]
	if wrappedFns[cur] then
		return nil -- already ours
	end
	local wrapper = make(cur)
	wrappedFns[wrapper] = true
	tbl[name] = wrapper
	return cur
end

---------------------------------------------------------------------------------------------------
-- token bucket
---------------------------------------------------------------------------------------------------
local Bucket = {}
Bucket.__index = Bucket
function Util.bucket(burst: number, rate: number): any
	return setmetatable({ burst = burst, rate = rate, per = {} }, Bucket)
end
function Bucket:take(key: any, cost: number?): boolean
	local now = os.clock()
	local b = self.per[key]
	if not b then
		b = { tokens = self.burst, t = now }
		self.per[key] = b
	end
	b.tokens = math.min(self.burst, b.tokens + (now - b.t) * self.rate)
	b.t = now
	local c = cost or 1
	if b.tokens < c then
		return false
	end
	b.tokens -= c
	return true
end
function Bucket:forget(key: any)
	self.per[key] = nil
end

---------------------------------------------------------------------------------------------------
-- player state
---------------------------------------------------------------------------------------------------
function Util.isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

function Util.root(player: Player): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

function Util.humanoid(player: Player): Humanoid?
	local ch = player.Character
	return ch and ch:FindFirstChildOfClass("Humanoid") or nil
end

-- why this player cannot do a "street" action right now (nil = fine)
function Util.blockedState(player: Player): string?
	local ch = player.Character
	local hum = Util.humanoid(player)
	if not ch or not hum or hum.Health <= 0 or not Util.root(player) then
		return "dead"
	end
	if ch:GetAttribute("GwKO") == true then
		return "ko"
	end
	local jail = player:GetAttribute("LawJail")
	if type(jail) == "number" and jail > workspace:GetServerTimeNow() then
		return "jail"
	end
	if player:GetAttribute("LawCuffed") == true or ch:GetAttribute("LawCuffed") == true then
		return "cuffed"
	end
	if hum.SeatPart then
		return "seated"
	end
	return nil
end

function Util.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Util.shortString(v: any, max: number): string?
	return if type(v) == "string" and #v > 0 and #v <= max then v else nil
end

return Util

end
__defs["Net"] = function()
-- GwangalliPasses/Net (server): ReplicatedStorage.GwangalliPassesRemotes
--   Request (RemoteFunction)  client -> server  (op: string, payload: table?) -> { ok, code?, message?, ... }
--   Event   (RemoteEvent)     server -> client  payload { kind = ..., ... }   (client -> server is ignored)
-- Every request passes a per-player token bucket (Config.NET) and the op's own cooldown; handlers get a
-- shallow-copied payload table (or {}) and must type-check every field they read.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local P: any, Config: any, Util: any
local folder: Folder? = nil
local requestFn: RemoteFunction? = nil
local eventRe: RemoteEvent? = nil
local handlers: { [string]: { fn: (Player, any) -> any, cooldown: number } } = {}
local last: { [Player]: { [string]: number } } = {}
local bucket: any = nil

function Net.on(op: string, cooldown: number, fn: (Player, any) -> any)
	handlers[op] = { fn = fn, cooldown = cooldown }
end

function Net.send(player: Player, payload: any)
	if eventRe and Util.isPlayer(player) then
		pcall(eventRe.FireClient, eventRe, player, payload)
	end
end

function Net.sendNear(pos: Vector3, range: number, payload: any, extra: ((Player) -> any)?)
	if not eventRe then
		return
	end
	for _, p in Players:GetPlayers() do
		local r = Util.root(p)
		local cam = r and r.Position
		if cam and (cam - pos).Magnitude <= range then
			local data = payload
			if extra then
				data = table.clone(payload)
				local add = extra(p)
				if type(add) == "table" then
					for k, v in add do
						data[k] = v
					end
				end
			end
			pcall((eventRe :: RemoteEvent).FireClient, eventRe, p, data)
		end
	end
end

local function copy(payload: any): { [string]: any }
	local out = {}
	if type(payload) == "table" then
		local n = 0
		for k, v in payload do
			n += 1
			if n > 16 then
				break
			end
			if type(k) == "string" and #k <= 24 then
				local t = type(v)
				if t == "string" then
					if #v <= 200 then
						out[k] = v
					end
				elseif t == "number" then
					if v == v and math.abs(v) < 1e12 then
						out[k] = v
					end
				elseif t == "boolean" then
					out[k] = v
				end
			end
		end
	end
	return out
end

local function invoke(player: Player, op: any, payload: any): any
	if type(op) ~= "string" or #op > 24 then
		return { ok = false, code = "bad" }
	end
	local h = handlers[op]
	if not h then
		return { ok = false, code = "bad" }
	end
	if not bucket:take(player) then
		return { ok = false, code = "rate", message = P.Lines.t("busy") }
	end
	local per = last[player]
	if not per then
		per = {}
		last[player] = per
	end
	local t = os.clock()
	if t - (per[op] or -1e9) < h.cooldown then
		return { ok = false, code = "cooldown", message = P.Lines.t("busy") }
	end
	per[op] = t
	local ok, res = pcall(h.fn, player, copy(payload))
	if not ok then
		Util.warnOnce("op " .. op, res)
		return { ok = false, code = "error", message = P.Lines.t("busy") }
	end
	if type(res) ~= "table" then
		return { ok = res == true }
	end
	return res
end

function Net.start(ctx: any)
	P, Config, Util = ctx.P, ctx.Config, ctx.Util
	bucket = Util.bucket(Config.NET.BURST, Config.NET.RATE)
	local old = ReplicatedStorage:FindFirstChild(P.REMOTES)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = P.REMOTES
	local rf = Instance.new("RemoteFunction")
	rf.Name = P.REQUEST
	rf.Parent = f
	local re = Instance.new("RemoteEvent")
	re.Name = P.EVENT
	re.Parent = f
	folder, requestFn, eventRe = f, rf, re
	rf.OnServerInvoke = function(player: Player, op: any, payload: any)
		return invoke(player, op, payload)
	end
	re.OnServerEvent:Connect(function() end) -- server -> client only
	Players.PlayerRemoving:Connect(function(p: Player)
		last[p] = nil
		bucket:forget(p)
	end)
end

-- parent the folder once every handler is bound (clients WaitForChild it)
function Net.publish(ready: { [string]: boolean })
	if folder then
		local okJ, json = pcall(function()
			return game:GetService("HttpService"):JSONEncode(ready)
		end)
		folder:SetAttribute(P.Attr.Ready, if okJ then json else "{}")
		folder.Parent = ReplicatedStorage
	end
end

function Net.setReady(ready: { [string]: boolean })
	if folder then
		local okJ, json = pcall(function()
			return game:GetService("HttpService"):JSONEncode(ready)
		end)
		folder:SetAttribute(P.Attr.Ready, if okJ then json else "{}")
	end
end

return Net

end
__defs["Waits"] = function()
-- GwangalliPasses/Waits (server): pass #3 편의 패스, the "50 % shorter waits" half.
--   * jail: Law calls Law.children.Jail.begin(player, s, episode, info) through the module table; the wrapper
--     halves episode.seconds (min Config.QOL.JAIL_MIN) for owners. Bail (LawShared.bailFor: left / total) and the
--     rejoin remainder follow on their own. A sentence already running keeps its length (Jail keeps it private).
--   * KO (nobody dies in 광안리: 0 HP = 기절 until 119 / transport):
--       - KO.koHelp (the "병원으로 이송" button) is wrapped: an owner may press it after SELF_HELP_AFTER x 0.5
--         (the client's own copy of A.KO.SELF_HELP_AFTER is halved by QoLClient so the button shows up on time)
--       - a watcher sends an owner to hospital (the same koHelp transport, same 119 fee as the fallback) at
--         EMS_WAIT x 0.5 when no ambulance was dispatched, or at EMS_TOTAL x 0.5 while still "waiting";
--         never during first aid / transport / staging (a 119 player at the scene keeps the patient), never
--         in "arrest" mode
--   * a real Roblox death / reset: the character comes back after Players.RespawnTime x 0.5.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Waits = {}

local ctx: any
local P: any, Config: any, Util: any, Lines: any
local A: any = nil
local KO: any = nil
local origKoHelp: any = nil
local ko: { [Player]: { t0: number, ems: boolean, forced: boolean, charConn: any? } } = {}

Waits.jailReady = false
Waits.koReady = false

local function owns(player: Player): boolean
	return ctx.Ownership.owns(player, "Convenience")
end

---------------------------------------------------------------------------------------------------
-- jail
---------------------------------------------------------------------------------------------------
-- the Jail.begin(player, s, episode, info) wrapper: an owner's sentence (episode.seconds) x JAIL_MULT, never
-- below JAIL_MIN; the episode table is copied (Law keeps its own)
function Waits.jailWrapper(o: any): any
	return function(player: any, s: any, episode: any, info: any)
		if Util.isPlayer(player) and type(episode) == "table" and type(episode.seconds) == "number" and owns(player) then
			local before = episode.seconds
			local after = math.max(Config.QOL.JAIL_MIN, math.ceil(before * Config.QOL.JAIL_MULT))
			if after < before then
				local e = table.clone(episode)
				e.seconds = after
				episode = e
				ctx.Net.send(player, { kind = "qol", what = "jail", before = before, after = after, text = Lines.t("jail_cut", Lines.dur(before), Lines.dur(after)) })
			end
		end
		return o(player, s, episode, info)
	end
end

local function hookJail(): boolean
	local api = Util.waitChild(ServerStorage, "GwangalliGameplayAPI", "BindableFunction", 150)
	if not api then
		return false
	end
	local Jail, why = Util.requirePath("GwangalliGameplay", { "Law", "Jail" }, 60)
	if not Jail then
		Util.warnOnce("jail", why)
		return false
	end
	local orig = Util.wrap(Jail, "begin", Waits.jailWrapper)
	return orig ~= nil or Jail.begin ~= nil
end

---------------------------------------------------------------------------------------------------
-- KO
---------------------------------------------------------------------------------------------------
local function koConst(name: string, default: number): number
	local v = A and A.KO and A.KO[name]
	return if type(v) == "number" then v else default
end

-- calls the original koHelp with SELF_HELP_AFTER lifted for exactly this synchronous call
local function forceHelp(player: Player): boolean
	if not origKoHelp or not A or not A.KO then
		return false
	end
	local old = A.KO.SELF_HELP_AFTER
	A.KO.SELF_HELP_AFTER = 0
	local ok, res = pcall(origKoHelp, player)
	A.KO.SELF_HELP_AFTER = old
	return ok and res == true
end

local function koState(player: Player): string?
	local ch = player.Character
	if not ch or ch:GetAttribute("GwKO") ~= true then
		return nil
	end
	local st = ch:GetAttribute("ArmsKO")
	return if type(st) == "string" then st else "down"
end

local function setKOEnd(player: Player, rec: any)
	if not owns(player) then
		player:SetAttribute(P.Attr.KOEnd, nil)
		return
	end
	local mult = Config.QOL.KO_MULT
	local wait = if rec.ems then koConst("EMS_TOTAL", 150) * mult else koConst("EMS_WAIT", 95) * mult
	local remaining = math.max(0, wait - (os.clock() - rec.t0))
	player:SetAttribute(P.Attr.KOEnd, P.serverNow() + remaining)
	player:SetAttribute("GwPassQoLKOEms", rec.ems == true)
end

local function watchCharacter(player: Player, ch: Model)
	local function update()
		if ch:GetAttribute("GwKO") == true then
			if not ko[player] then
				local rec = { t0 = os.clock(), ems = false, forced = false }
				ko[player] = rec
				setKOEnd(player, rec)
			end
		else
			ko[player] = nil
			player:SetAttribute(P.Attr.KOEnd, nil)
		end
	end
	ch:GetAttributeChangedSignal("GwKO"):Connect(update)
	update()
end

local function tick()
	local mult = Config.QOL.KO_MULT
	for player, rec in ko do
		if player.Parent ~= Players then
			ko[player] = nil
			continue
		end
		if rec.forced or not owns(player) then
			continue
		end
		local st = koState(player)
		if not st then
			continue
		end
		local el = os.clock() - rec.t0
		local wait = koConst("EMS_WAIT", 95) * mult
		local total = koConst("EMS_TOTAL", 150) * mult
		local okState = st == "waiting" or st == "down"
		local due = (not rec.ems and el >= wait) or (el >= total and st == "waiting")
		if okState and due then
			rec.forced = true
			if forceHelp(player) then
				ctx.Net.send(player, { kind = "toast", icon = "⚡", title = Lines.t("ko_forced"), tone = "info" })
			else
				rec.forced = false
				rec.t0 += 3 -- arrest mode / busy: look again in a moment
			end
		end
	end
end

-- the KO.koHelp(victim) wrapper: an owner may ask for the hospital after SELF_HELP_AFTER x KO_MULT. The global
-- A.KO.SELF_HELP_AFTER is lifted only around this one synchronous call and always restored (pcall).
function Waits.koHelpWrapper(o: any): any
	return function(victim: any): boolean
		if Util.isPlayer(victim) and owns(victim) and A and type(A.KO) == "table" then
			local rec = ko[victim]
			local need = koConst("SELF_HELP_AFTER", 20) * Config.QOL.KO_MULT
			if rec and os.clock() - rec.t0 >= need then
				local old = A.KO.SELF_HELP_AFTER
				A.KO.SELF_HELP_AFTER = 0
				local ok, res = pcall(o, victim)
				A.KO.SELF_HELP_AFTER = old
				return ok and res == true
			end
		end
		return o(victim)
	end
end

local function hookKO(): boolean
	local api = Util.waitChild(ServerStorage, "GwangalliArmsAPI", "BindableFunction", 150)
	if not api then
		return false
	end
	A = Util.requireShared(ReplicatedStorage, "GwangalliArmsShared", 30)
	local K, why = Util.requirePath("GwangalliGameplay", { "Arms", "KOSystem" }, 60)
	if not K or not A then
		Util.warnOnce("ko", why or "GwangalliArmsShared missing")
		return false
	end
	KO = K
	origKoHelp = Util.wrap(KO, "koHelp", Waits.koHelpWrapper)
	if not origKoHelp then
		return false
	end
	-- ambulance dispatched for an owner: the shorter "no crew" timer no longer applies
	local bus = ServerStorage:FindFirstChild("GwangalliCrimeBus")
	if bus and bus:IsA("BindableEvent") then
		bus.Event:Connect(function(name: any, payload: any)
			if name == "EmsDispatched" and type(payload) == "table" then
				local p = payload.player
				if typeof(p) == "Instance" and p:IsA("Player") and ko[p] then
					ko[p].ems = true
					setKOEnd(p, ko[p])
				end
			end
		end)
	end
	local function join(player: Player)
		if player.Character then
			watchCharacter(player, player.Character)
		end
		player.CharacterAdded:Connect(function(ch: Model)
			watchCharacter(player, ch)
		end)
	end
	for _, p in Players:GetPlayers() do
		join(p)
	end
	Players.PlayerAdded:Connect(join)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(tick)
			if not ok then
				Util.warnOnce("ko tick", err)
			end
		end
	end)
	return true
end

---------------------------------------------------------------------------------------------------
-- Roblox respawn
---------------------------------------------------------------------------------------------------
local function hookRespawn()
	local function onChar(player: Player, ch: Model)
		local hum = ch:WaitForChild("Humanoid", 10)
		if not hum or not hum:IsA("Humanoid") then
			return
		end
		hum.Died:Connect(function()
			if not owns(player) or not Players.CharacterAutoLoads then
				return
			end
			local delay = math.max(0.5, Players.RespawnTime * Config.QOL.RESPAWN_MULT)
			task.delay(delay, function()
				if player.Parent == Players and player.Character == ch then
					pcall(player.LoadCharacter, player)
				end
			end)
		end)
	end
	local function join(player: Player)
		if player.Character then
			task.spawn(onChar, player, player.Character)
		end
		player.CharacterAdded:Connect(function(ch: Model)
			onChar(player, ch)
		end)
	end
	for _, p in Players:GetPlayers() do
		join(p)
	end
	Players.PlayerAdded:Connect(join)
end

-- module state only (no hooks): used by start and by the offline tests
function Waits.bind(c: any, armsShared: any?)
	ctx = c
	P, Config, Util, Lines = c.P, c.Config, c.Util, c.P.Lines
	if armsShared ~= nil then
		A = armsShared
	end
end

-- the KO record of a downed player (offline tests / other modules)
function Waits.koRecord(player: Player): any
	return ko[player]
end

-- a downed player's KO watch starts now (normally the character's GwKO attribute does this)
function Waits.markDown(player: Player)
	if not ko[player] then
		ko[player] = { t0 = os.clock(), ems = false, forced = false }
	end
end

function Waits.start(c: any)
	Waits.bind(c)
	hookRespawn()
	Players.PlayerRemoving:Connect(function(p: Player)
		ko[p] = nil
	end)
	task.spawn(function()
		local ok, res = pcall(hookJail)
		Waits.jailReady = ok and res == true
		if not Waits.jailReady then
			Util.warnOnce("jail", "Law/Jail hook unavailable: 유치장 단축 off (" .. tostring(res) .. ")")
		end
		c.refreshReady()
	end)
	task.spawn(function()
		local ok, res = pcall(hookKO)
		Waits.koReady = ok and res == true
		if not Waits.koReady then
			Util.warnOnce("ko", "Arms/KOSystem hook unavailable: 기절 단축 off (" .. tostring(res) .. ")")
		end
		c.refreshReady()
	end)
	-- buying while in a cell: tell them it applies from the next arrest
	c.Ownership.onChanged(function(player: Player, key: string, owned: boolean)
		if key == "Convenience" and owned then
			local j = player:GetAttribute("LawJail")
			if type(j) == "number" and j > P.serverNow() then
				c.Net.send(player, { kind = "toast", icon = "⚡", title = Lines.t("jail_next"), tone = "info" })
			end
			local rec = ko[player]
			if rec then
				setKOEnd(player, rec)
			end
		end
	end)
end

return Waits

end
__defs["Plate"] = function()
-- GwangalliPasses/Plate (server): pass #4 과시 패스, 차량 커스텀 번호판.
--   setPlate: Shared/Plates.validate (length / charset) -> TextService FilterStringAsync ->
--   GetNonChatStringForBroadcastAsync (must come back unchanged; a failed filter call refuses) -> unique claim
--   (Data.claimPlate) -> saved + Player attributes GwVanityPlate / GwPlateStyle.
--   applyTo(model, owner): GS.applyPlate (both plates' TextLabels + DrivePlate, so the cop plate lookup reads it)
--   + the style (plate colour / text colour / font / optional frame bars welded to the plate).
--   Every owned car (DriveOwnedCar, DriveOwner = owner, not rental / 시승) that appears in
--   workspace.GwangalliPlayerCars gets it, premium cars included.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Plate = {}

local ctx: any
local P: any, Config: any, Util: any, Lines: any, Plates: any
local GS: any = nil
local lastSet: { [Player]: number } = {}

local function owns(player: Player): boolean
	return ctx.Ownership.owns(player, "Flex")
end

-- the text an owner's cars should carry (nil = keep the car's own plate)
function Plate.textFor(player: Player): string?
	if not owns(player) then
		return nil
	end
	local prof = ctx.Data.get(player)
	local t = prof.plate and prof.plate.text
	return if type(t) == "string" and t ~= "" then t else nil
end

function Plate.styleFor(player: Player): string?
	if not owns(player) then
		return nil
	end
	local prof = ctx.Data.get(player)
	return prof.plate and prof.plate.style or nil
end

local function clearFrames(plate: BasePart)
	for _, c in plate:GetChildren() do
		if c.Name == "GwPlateFrame" then
			c:Destroy()
		end
	end
	local model = plate:FindFirstAncestorOfClass("Model")
	if model then
		for _, d in model:GetDescendants() do
			if d.Name == "GwPlateFrame" and d:GetAttribute("GwFor") == plate.Name then
				d:Destroy()
			end
		end
	end
end

local function frameBars(plate: BasePart, style: any)
	local col = Plates.rgb(style.frame)
	local mat = if style.frameMat then (Enum.Material :: any)[style.frameMat] else Enum.Material.Metal
	local s = plate.Size
	local th, depth = 0.06, s.Z + 0.04
	local bars = {
		{ Vector3.new(s.X + th * 2, th, depth), Vector3.new(0, s.Y / 2 + th / 2, 0) },
		{ Vector3.new(s.X + th * 2, th, depth), Vector3.new(0, -s.Y / 2 - th / 2, 0) },
		{ Vector3.new(th, s.Y, depth), Vector3.new(s.X / 2 + th / 2, 0, 0) },
		{ Vector3.new(th, s.Y, depth), Vector3.new(-s.X / 2 - th / 2, 0, 0) },
	}
	for _, b in bars do
		local p = Instance.new("Part")
		p.Name = "GwPlateFrame"
		p:SetAttribute("GwFor", plate.Name)
		p.Size = b[1]
		p.CFrame = plate.CFrame * CFrame.new(b[2])
		p.Color = col
		p.Material = mat
		p.Reflectance = if mat == Enum.Material.Metal then 0.25 else 0
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Anchored = plate.Anchored
		local w = Instance.new("WeldConstraint")
		w.Part0 = plate
		w.Part1 = p
		w.Parent = p
		p.Parent = plate.Parent
	end
end

local function styleParts(model: Model, style: any)
	for _, name in { "PlateFront", "PlateRear" } do
		local part = model:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			clearFrames(part)
			part.Color = Plates.rgb(style.bg)
			part.Material = Enum.Material.SmoothPlastic
			for _, d in part:GetDescendants() do
				if d:IsA("TextLabel") then
					d.TextColor3 = Plates.rgb(style.fg)
					d.Font = Plates.font(style.font)
					local grad = d.Parent and d.Parent:FindFirstChild("GwPlateBg")
					if grad then
						grad:Destroy()
					end
					if style.bg2 and d.Parent and d.Parent:IsA("SurfaceGui") then
						local bg = Instance.new("Frame")
						bg.Name = "GwPlateBg"
						bg.Size = UDim2.fromScale(1, 1)
						bg.BorderSizePixel = 0
						bg.BackgroundColor3 = Color3.new(1, 1, 1)
						bg.ZIndex = 0
						local g = Instance.new("UIGradient")
						g.Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Plates.rgb(style.bg)),
							ColorSequenceKeypoint.new(0.16, Plates.rgb(style.bg)),
							ColorSequenceKeypoint.new(0.17, Plates.rgb(style.bg2)),
							ColorSequenceKeypoint.new(1, Plates.rgb(style.bg2)),
						})
						g.Parent = bg
						bg.Parent = d.Parent
						d.ZIndex = 2
					end
					local stroke = d:FindFirstChild("GwPlateGlow")
					if style.glow then
						if not stroke then
							stroke = Instance.new("UIStroke")
							stroke.Name = "GwPlateGlow"
							stroke.Parent = d
						end
						(stroke :: UIStroke).Color = Plates.rgb(style.fg);
						(stroke :: UIStroke).Transparency = 0.45;
						(stroke :: UIStroke).Thickness = 1.5
					elseif stroke then
						stroke:Destroy()
					end
				end
			end
			if style.frame then
				frameBars(part, style)
			end
		end
	end
	model:SetAttribute(P.Attr.PlateStyle, style.id)
end

-- applies the owner's custom plate / style to one car model. defaultStyle: used when the owner has no Flex style.
function Plate.applyTo(model: Model, owner: Player, defaultStyle: string?)
	if not model or not model.Parent or not GS then
		return
	end
	local text = Plate.textFor(owner)
	if text then
		pcall(GS.applyPlate, model, text)
	end
	local sid = Plate.styleFor(owner)
	if not sid and not defaultStyle then
		return
	end
	pcall(styleParts, model, Plates.style(sid or defaultStyle))
end

local function eligible(model: Instance): Player?
	if not model:IsA("Model") then
		return nil
	end
	if model:GetAttribute("DriveOwnedCar") ~= true or model:GetAttribute("DriveRental") == true or model:GetAttribute("DriveTestDrive") ~= nil then
		return nil
	end
	local uid = model:GetAttribute("DriveOwner")
	if type(uid) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(uid)
end

local function filter(text: string, userId: number): (string?, string?)
	local ok, res = pcall(function()
		local r = TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(res) ~= "string" then
		return nil, "filter"
	end
	return res, nil
end

local function pushAttrs(player: Player)
	if owns(player) then
		player:SetAttribute(P.Attr.Plate, Plate.textFor(player))
		player:SetAttribute(P.Attr.PlateStyle, Plate.styleFor(player))
	else
		player:SetAttribute(P.Attr.Plate, nil)
		player:SetAttribute(P.Attr.PlateStyle, nil)
	end
end

-- -> { ok, code, message, plate }
function Plate.set(player: Player, text: any, styleId: any): { [string]: any }
	if not owns(player) then
		return { ok = false, code = "locked", message = Lines.t("locked_tab", Config.PASSES.Flex.Title) }
	end
	local sid = if type(styleId) == "string" and Plates.BY_ID[styleId] then styleId else nil
	local prof = ctx.Data.get(player)
	local current = prof.plate and prof.plate.text
	local ok, code, clean = Plates.validate(text)
	-- style only (same text, or no text yet with an empty box)
	if (not ok and code == "empty") or (ok and clean == current) then
		if sid then
			ctx.Data.update(player, function(pr)
				pr.plate.style = sid
			end)
			pushAttrs(player)
			return { ok = true, message = Lines.t("plate_saved"), plate = current, style = sid }
		end
		if not ok then
			return { ok = false, code = "empty", message = Lines.t("plate_rule", Config.PLATE.MIN, Config.PLATE.MAX) }
		end
	end
	if not ok then
		return { ok = false, code = code, message = Lines.t("plate_rule", Config.PLATE.MIN, Config.PLATE.MAX) }
	end
	local t = os.clock()
	local cd = Config.PLATE.COOLDOWN - (t - (lastSet[player] or -1e9))
	if cd > 0 then
		return { ok = false, code = "cooldown", message = Lines.t("plate_cooldown", math.ceil(cd)) }
	end
	local filtered, ferr = filter(clean, player.UserId)
	if not filtered then
		return { ok = false, code = ferr or "filter", message = Lines.t("plate_filter") }
	end
	if filtered ~= clean then
		return { ok = false, code = "bad", message = Lines.t("plate_bad") }
	end
	local okC, why = ctx.Data.claimPlate(player, clean)
	if not okC then
		return { ok = false, code = why or "taken", message = Lines.t("plate_taken") }
	end
	lastSet[player] = t
	if type(current) == "string" and current ~= clean then
		ctx.Data.releasePlate(player, current)
	end
	ctx.Data.update(player, function(pr)
		pr.plate.text = clean
		if sid then
			pr.plate.style = sid
		end
	end)
	pushAttrs(player)
	return { ok = true, message = Lines.t("plate_saved"), plate = clean, style = sid or Plate.styleFor(player) }
end

function Plate.clear(player: Player): { [string]: any }
	if not owns(player) then
		return { ok = false, code = "locked" }
	end
	local prof = ctx.Data.get(player)
	local current = prof.plate and prof.plate.text
	if current then
		ctx.Data.releasePlate(player, current)
	end
	ctx.Data.update(player, function(pr)
		pr.plate.text = nil
		pr.plate.style = Config.PLATE.DEFAULT_STYLE
	end)
	pushAttrs(player)
	return { ok = true, message = Lines.t("plate_cleared") }
end

function Plate.start(c: any)
	ctx = c
	P, Config, Util, Lines = c.P, c.Config, c.Util, c.P.Lines
	Plates = P.mod("Plates")
	GS = Util.requireShared(ReplicatedStorage, "GwangalliGarageShared", 90)
	c.Data.onLoaded(function(player: Player)
		pushAttrs(player)
		-- the saved plate is claimed again for this server (another player may not take it meanwhile)
		local text = c.Data.get(player).plate.text
		if type(text) == "string" and text ~= "" then
			task.spawn(c.Data.claimPlate, player, text)
		end
	end)
	c.Ownership.onChanged(function(player: Player, key: string)
		if key == "Flex" then
			pushAttrs(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		lastSet[p] = nil
	end)
	task.spawn(function()
		local f = Util.waitChild(workspace, "GwangalliPlayerCars", "Folder", 600)
		if not f then
			return
		end
		f.ChildAdded:Connect(function(m: Instance)
			task.defer(function()
				local owner = eligible(m)
				if owner and owns(owner) and m:GetAttribute(P.Attr.Premium) == nil then
					Plate.applyTo(m :: Model, owner)
				end
			end)
		end)
	end)
end

return Plate

end
-- offline logic tests for GwangalliPasses (mock runtime)
local fails, passes = 0, 0
local function check(name, cond, extra)
	if cond then
		passes += 1
	else
		fails += 1
		print("FAIL", name, extra ~= nil and tostring(extra) or "")
	end
end

local P = __req("P")
local Plates = P.mod("Plates")
local Neon = P.mod("Neon")
local Cars = P.mod("Cars")
local KoFx = P.mod("KoFx")
local Lines = P.Lines
local player = R.player

-- shared ------------------------------------------------------------------------------------------
check("key alias garage", P.key("garage") == "PremiumGarage")
check("key alias QOL", P.key("QOL") == "Convenience")
check("key full", P.key("Flex") == "Flex")
check("key bad", P.key("vip") == nil and P.key(5) == nil)
check("available Id0 live", P.available("garage") == false)
check("won", P.won(1234567) == "1,234,567원" and P.won(0) == "0원" and P.won(-5000) == "-5,000원", P.won(1234567))
check("dur", Lines.dur(150) == "2분 30초" and Lines.dur(60) == "1분" and Lines.dur(45) == "45초")
check("lines fmt", Lines.t("summon_cooldown", 3) == "잠시 후 다시 불러 주세요 (3초)")
check("lines unknown", Lines.t("nope") == "nope")
check("lines repair %%", string.find(Lines.t("repair_done", "12가 3456", "1,000원"), "100%", 1, true) ~= nil)

-- plates ------------------------------------------------------------------------------------------
local function v(t)
	local ok, code, clean = Plates.validate(t)
	return ok, code, clean
end
check("plate korean ok", (v("12가 3456")))
check("plate 3-digit", (v("123가 4567")))
check("plate free", (v("광안 1004")))
check("plate ascii upper", select(3, v("gw 7777")) == "GW 7777")
check("plate spaces collapse", select(3, v("  부산   VIP  ")) == "부산 VIP")
check("plate too short", select(2, v("가")) == "len")
check("plate too long", select(2, v("123456789가")) == "len")
check("plate emoji", select(2, v("광안😀1")) == "chars")
check("plate markup", select(2, v("<b>x</b>")) == "chars")
check("plate empty", select(2, v("   ")) == "empty")
check("plate digits", select(2, v("12345678")) == "digits")
check("plate dash", (v("GW-777")))
check("plate jamo refused", select(2, v("ㅋㅋㅋ")) == "chars")
check("plate korean helper", Plates.korean("12가3456") == "12가 3456" and Plates.korean("123가4567") == "123가 4567")
check("plate korean helper free", Plates.korean("광안1004") == "광안1004")
check("plate claim spacing", Plates.claimKey("12가 3456") == Plates.claimKey("12가3456"))
check("plate claim case", Plates.claimKey("gw 7") == Plates.claimKey("GW7"))
check("plate claim distinct", Plates.claimKey("12가 3456") ~= Plates.claimKey("12나 3456"))
check("plate claim len", #Plates.claimKey("가나다라마바사아") <= 50)
for i = 1, 30 do
	local r = Plates.random(Random.new(i))
	check("plate random valid " .. r, (v(r)))
end
check("plate style fallback", Plates.style("nope").id == P.Config.PLATE.DEFAULT_STYLE)

-- neon --------------------------------------------------------------------------------------------
local pal = Neon.get("bridge")
local rich = Neon.rich("A&B", pal, true)
check("neon rich escape", string.find(rich, "&amp;", 1, true) ~= nil and string.sub(rich, 1, 3) == "<b>", rich)
local n = 0
for _ in string.gmatch(Neon.rich("철수야", pal), "<font") do
	n += 1
end
check("neon rich per char", n == 3)
check("neon sample ends", Neon.sample(pal, 0) == pal.colors[1] and Neon.sample(pal, 1) == pal.colors[#pal.colors])
for _, p in Neon.LIST do
	local ok = pcall(Neon.sequence, p)
	check("neon sequence " .. p.id, ok)
end

-- cars / fx ---------------------------------------------------------------------------------------
check("car id round trip", Cars.keyOfId(Cars.carId("hyper")) == "hyper" and Cars.keyOfId("gwp_x") == nil and Cars.keyOfId("abc") == nil)
for _, car in Cars.LIST do
	check("car kind not job " .. car.key, car.kind ~= "police" and car.kind ~= "taxi" and car.kind ~= "ambulance")
	local plate = Cars.defaultPlate(123456789, car.key)
	check("car plate bytes " .. car.key, #plate <= 24, plate)
	check("car plate stable " .. car.key, plate == Cars.defaultPlate(123456789, car.key))
	check("car paint " .. car.key, Cars.PAINT_BY_ID[car.paint] ~= nil)
	check("car speed sane " .. car.key, car.spec.topKmh <= 220)
end
local VS = { Specs = { luxury = { label = "L", topKmh = 165, mass = 160, accel = 25 }, suv = { label = "S", topKmh = 128, E = 0.3 }, sedan = { topKmh = 135 } }, Drivable = { sedan = true } }
Cars.install(VS, true)
check("install specs", VS.Specs.gw_hyper and VS.Specs.gw_hyper.topKmh == 210 and VS.Specs.gw_hyper.mass == 168)
check("install keeps base", VS.Specs.gw_vip.mass == 160 and VS.Specs.gw_vip.topKmh == 178)
check("install drivable", VS.Drivable.gw_offroad == true and VS.Drivable.sedan == true)
check("install base untouched", VS.Specs.luxury.topKmh == 165)
local VS2 = { Specs = { luxury = { topKmh = 165 } }, Drivable = {} }
Cars.install(VS2, false)
check("install client not drivable", VS2.Drivable.gw_hyper == nil and VS2.Specs.gw_hyper ~= nil)
for _, d in KoFx.LIST do
	check("fx emote " .. d.id, KoFx.EMOTE_FOR[d.id] ~= nil)
	for _, s in d.sounds do
		check("fx sound " .. d.id .. "." .. s, KoFx.SND[s] ~= nil)
	end
	check("fx no gore word " .. d.id, not string.find(d.name .. d.desc, "처형", 1, true) and not string.find(d.name .. d.desc, "피", 1, true))
end

-- server Util ---------------------------------------------------------------------------------------
local Util = __req("Util")
local b = Util.bucket(3, 1)
check("bucket burst", b:take("x") and b:take("x") and b:take("x") and not b:take("x"))
check("bucket other key", b:take("y"))
local T = { f = function(a)
	return a + 1
end }
local orig1 = Util.wrap(T, "f", function(o)
	return function(a)
		return o(a) * 10
	end
end)
check("wrap returns orig", type(orig1) == "function")
check("wrap calls through", T.f(1) == 20)
local orig2 = Util.wrap(T, "f", function(o)
	return function(a)
		return o(a) * 100
	end
end)
check("wrap idempotent", orig2 == nil and T.f(1) == 20)
check("wrap missing", Util.wrap(T, "nope", function(o)
	return o
end) == nil)
check("isPlayer", Util.isPlayer(player) and not Util.isPlayer({}) and not Util.isPlayer(workspace))
check("shortString", Util.shortString("abc", 5) == "abc" and Util.shortString("abcdef", 5) == nil and Util.shortString(5, 5) == nil)

-- Waits: jail / koHelp wrappers ------------------------------------------------------------------------
local sent = {}
local owns = { [player] = true }
local ctx = {
	P = P,
	Config = P.Config,
	Util = Util,
	Net = { send = function(_p, payload)
		table.insert(sent, payload)
	end },
	Ownership = { owns = function(p, k)
		return owns[p] == true and k == "Convenience"
	end },
}
local A = { KO = { SELF_HELP_AFTER = 20, EMS_WAIT = 95, EMS_TOTAL = 150 } }
local Waits = __req("Waits")
Waits.bind(ctx, A)
local seen = nil
local jw = Waits.jailWrapper(function(_p, _s, ep, _i)
	seen = ep.seconds
	return "began"
end)
local ep = { seconds = 120, fine = 1 }
check("jail returns orig result", jw(player, {}, ep, {}) == "began")
check("jail halved", seen == 60, seen)
check("jail original episode untouched", ep.seconds == 120)
check("jail toast", #sent == 1 and sent[1].kind == "qol" and sent[1].after == 60, sent[1] and sent[1].text)
jw(player, {}, { seconds = 20 }, {})
check("jail min 15", seen == 15, seen)
jw(player, {}, { seconds = 12 }, {})
check("jail never longer", seen == 12, seen)
jw(player, {}, { seconds = 31 }, {})
check("jail rounds up", seen == 16, seen)
owns[player] = false
jw(player, {}, { seconds = 120 }, {})
check("jail non-owner", seen == 120)
jw({}, {}, { seconds = 120 }, {})
check("jail bad player passthrough", seen == 120)
owns[player] = true

local calls = 0
local function origHelp(victim)
	calls += 1
	-- KOSystem: refuses before SELF_HELP_AFTER (rec.t0 = down time)
	local rec = Waits.koRecord(victim)
	return os.clock() - rec.t0 >= A.KO.SELF_HELP_AFTER
end
local kw = Waits.koHelpWrapper(origHelp)
Waits.markDown(player)
check("ko early refused", kw(player) == false and A.KO.SELF_HELP_AFTER == 20)
Waits.koRecord(player).t0 = os.clock() - 11
check("ko owner after half", kw(player) == true)
check("ko constant restored", A.KO.SELF_HELP_AFTER == 20)
owns[player] = false
check("ko non-owner at 11s refused", kw(player) == false)
owns[player] = true
local kwErr = Waits.koHelpWrapper(function()
	error("boom")
end)
check("ko error safe", kwErr(player) == false and A.KO.SELF_HELP_AFTER == 20)

-- Net: payload copy + rate limits -----------------------------------------------------------------------
local Net = __req("Net")
Net.start(ctx)
local got = nil
Net.on("echo", 0, function(_p, payload)
	got = payload
	return { ok = true }
end)
Net.on("slow", 5, function()
	return { ok = true }
end)
Net.publish({ garage = true })
local folder = game:GetService("ReplicatedStorage"):FindFirstChild(P.REMOTES)
check("net folder", folder ~= nil and folder:FindFirstChild(P.REQUEST) ~= nil and folder:FindFirstChild(P.EVENT) ~= nil)
local rf = folder:FindFirstChild(P.REQUEST)
local invoke = rf.OnServerInvoke
local r1 = invoke(player, "echo", { a = "x", nested = { 1 }, long = string.rep("z", 300), num = 5, bad = 0 / 0, [1] = "arr", fn = print })
check("net ok", r1.ok == true)
check("net copy fields", got.a == "x" and got.num == 5 and got.nested == nil and got.long == nil and got.bad == nil and got[1] == nil and got.fn == nil)
check("net unknown op", invoke(player, "nope", nil).code == "bad")
check("net bad op type", invoke(player, 5, nil).code == "bad")
check("net cooldown", invoke(player, "slow", nil).ok == true and invoke(player, "slow", nil).code == "cooldown")
local limited = false
for _ = 1, 20 do
	if invoke(player, "echo", nil).code == "rate" then
		limited = true
	end
end
check("net rate limit", limited)

-- Plate.set: validation -> filter -> claim -----------------------------------------------------------
local TextService = game:GetService("TextService")
local filterMode = "same"
TextService.FilterStringAsync = function(_self, text, _uid, _ctx)
	if filterMode == "error" then
		error("filter down")
	end
	return { GetNonChatStringForBroadcastAsync = function()
		return if filterMode == "hash" then string.rep("#", utf8.len(text) or 1) else text
	end }
end
local prof = { plate = { text = nil, style = "classic" } }
local claimed = {}
local pctx = {
	P = P,
	Config = P.Config,
	Util = Util,
	Ownership = { owns = function(_p, k)
		return k == "Flex"
	end, onChanged = function() end },
	Data = {
		get = function()
			return prof
		end,
		update = function(_p, fn)
			fn(prof)
		end,
		onLoaded = function() end,
		claimPlate = function(_p, clean)
			if claimed[Plates.claimKey(clean)] == "other" then
				return false, "taken"
			end
			claimed[Plates.claimKey(clean)] = "me"
			return true
		end,
		releasePlate = function(_p, clean)
			claimed[Plates.claimKey(clean)] = nil
		end,
	},
	Net = ctx.Net,
}
-- the lookups Plate.start waits for (the mock task.wait does not yield)
local carsF = Instance.new("Folder")
carsF.Name = "GwangalliPlayerCars"
carsF.Parent = workspace
local gsM = Instance.new("ModuleScript")
gsM.Name = "GwangalliGarageShared"
gsM.Parent = game:GetService("ReplicatedStorage")
local Plate = __req("Plate")
Plate.start(pctx)
local res = Plate.set(player, "12가3456", "gold")
check("plate set ok", res.ok == true and res.plate == "12가3456" and prof.plate.style == "gold", res.message)
check("plate attr", player:GetAttribute(P.Attr.Plate) == "12가3456")
local res2 = Plate.set(player, "광안 1004", nil)
check("plate cooldown", res2.ok == false and res2.code == "cooldown", res2.code)
res2 = Plate.set(player, "12가3456", "neon")
check("plate style only", res2.ok == true and prof.plate.style == "neon", res2.code)
res2 = Plate.set(player, "<script>", nil)
check("plate bad chars", res2.ok == false and res2.code == "chars", res2.code)
check("plate textFor", Plate.textFor(player) == "12가3456")
res2 = Plate.clear(player)
check("plate clear", res2.ok == true and prof.plate.text == nil and Plate.textFor(player) == nil)

print(string.format("logic tests: %d passed, %d failed", passes, fails))
