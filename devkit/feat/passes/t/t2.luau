--!nocheck
local R = require("./lib/rbx")
local E = R.env
local game, workspace, Instance, Enum, CFrame, Vector3, Color3, UDim2, UDim, Vector2 = E.game, E.workspace, E.Instance, E.Enum, E.CFrame, E.Vector3, E.Color3, E.UDim2, E.UDim, E.Vector2
local NumberSequence, NumberSequenceKeypoint, ColorSequence, ColorSequenceKeypoint, Random, typeof = E.NumberSequence, E.NumberSequenceKeypoint, E.ColorSequence, E.ColorSequenceKeypoint, E.Random, E.typeof
local CONFIG = (function()
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

end)()
local Plates = (function()
-- GwangalliPassesShared/Plates: custom plate rules (pure) + plate styles.
--   Plates.normalize(text) -> string            trim, collapse spaces, ASCII upper-case
--   Plates.validate(text) -> ok, code, clean     code: "len" | "chars" | "empty" | "digits"
--   Plates.korean(text) -> string                "12가3456" -> "12가 3456" (Korean plate spacing helper)
--   Plates.random(rng) -> string                 a random "123가 4567" plate (the editor's 🎲)
--   Plates.claimKey(clean) -> string             DataStore key (fixed-width base36 per codepoint)
--   Plates.STYLES / Plates.style(id)

local Config = CONFIG

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

end)()
local Neon = (function()
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

end)()
local Lines = (function()
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

end)()

local cases = { "12가 3456", "123가4567", " 광안 1004 ", "gw 7777", "부산VIP", "a", "12345678", "1234567", "광안리광안리광안리", "😀GW", "AB<CD", "가-나 12", "123가 4567", "abcdefghi" }
for _, c in cases do
	local ok, code, clean = Plates.validate(c)
	print(string.format("%-22s ok=%-5s code=%-6s clean=[%s] korean=[%s] key=%s", "[" .. c .. "]", tostring(ok), tostring(code), clean, Plates.korean(c), ok and Plates.claimKey(clean) or "-"))
end
print("claim same", Plates.claimKey("12가 3456") == Plates.claimKey("12가3456"), #Plates.claimKey("광안리광안리광안"))
print("random", Plates.random(Random.new(4)), Plates.random(Random.new(5)))
local pal = Neon.get("bridge")
print("rich", Neon.rich("Kim<3", pal, true))
print("seq ok", Neon.sequence(pal) ~= nil, Neon.sequence(Neon.get("rainbow")) ~= nil)
print(Lines.t("jail_cut", Lines.dur(120), Lines.dur(60)), Lines.t("repair_done", "부산12가 3456", "31,200원"), Lines.t("plate_rule", 2, 8), Lines.t("buy", 799))
