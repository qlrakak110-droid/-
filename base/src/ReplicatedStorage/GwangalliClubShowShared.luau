-- GwangalliClubShowShared: data + pure helpers for the CLUB OCEAN 광안 show layer (paid door, bottle
-- menu, bottle-service parade show, 합석 이벤트, table life). Used by Club.server (door), the
-- GwangalliClub server modules (BottleService / Booking / Show) and GwangalliClubShow.client.
-- No instances, no yields at require time (Lune can load it: the Roblox lookups are lazy + pcall).
--
-- CONTRACT (see docs/CLUB_SHOW.md):
--   ReplicatedStorage.GwangalliClubShow (Folder, GwangalliClub.server)
--     RemoteEvent ShowEvent    server -> client: (kind, payload)  kinds: "menu", "order", "booking",
--                              "toast"
--     RemoteEvent ShowRequest  client -> server: (op, a, b)       ops: "order" (tableId, itemId),
--                              "booking" (tableId), "act" (action), "menu" (tableId)
--     attributes (JSON strings, written by the server only; clients decode with HttpService):
--       Show     the current / last bottle-service show  { id, tier, item, table, owner, name, at,
--                staff, path = "x,z;...", y, dj, confetti, booking, aa }
--       Tables   { [tableId] = { owner, name, tier, set, at, untilT } }  table life (props) per table
--       Booking  the current 합석 event { id, table, owner, name, at, path, y, seats, guests = {
--                { id, name, g, seat, lines } }, act = { kind, at, n }, endAt }
--   ServerStorage.GwangalliClubAPI (BindableFunction, GwangalliClub.server):
--     Invoke("openMenu", player, tableId) -> true when it opened its menu
--     Invoke("reserve", player, setId?) -> tableId? (door "테이블 예약 입장": a free table + basic set)
--     Invoke("hasTable", player) -> tableId?      Invoke("ownsTable", player, tableId) -> bool
--   ServerStorage.ClubShowHook (BindableFunction, Club.server):
--     Invoke("hold", seconds)            the house parade waits (no second parade during a show)
--     Invoke("tableInfo", tableId)       -> { id, kind, label, serve = Vector3, centre = Vector3,
--                                           seats = { { cf = CFrame, free = bool } } }?
--     Invoke("tables")                   -> { tableId... }
--     Invoke("reach", player, tableId, radius?) -> bool
--     Invoke("stamp", tableId, at, userId)  ClubLights' sparkler bottles land on the table at `at`
--     Invoke("route")                    -> { Vector3 } ParadeRoute WP1..n
--   Player attributes: ClubOceanWristband (server time it was put on), ClubOceanWristbandUntil
--   (server time it stops being valid; the door and the server's walk-out check read this one).

local ShowShared = {}
ShowShared.VERSION = 1

ShowShared.Folder = "GwangalliClubShow"
ShowShared.Remote = { Event = "ShowEvent", Request = "ShowRequest" }
ShowShared.API_NAME = "GwangalliClubAPI"
ShowShared.HOOK_NAME = "ClubShowHook"
ShowShared.Tags = { Door = "ClubDoor", Anchor = "ClubShowAnchor" }
ShowShared.Attr = {
	Show = "Show",
	Tables = "Tables",
	Booking = "Booking",
	Wristband = "ClubOceanWristband",
	WristbandUntil = "ClubOceanWristbandUntil",
	GuestSeat = "ClubGuestSeat", -- Seat attribute: server time until which a 합석 guest sits there
	DoorFee = "ClubDoorFee", -- player attribute: today's walk-in fee (for the door chip)
}

---------------------------------------------------------------------------------------------------
-- All-ages build switch (Roblox content maturity: see docs/CLUB_SHOW.md)
---------------------------------------------------------------------------------------------------
-- false = club labels (샴페인 / 보드카 ...): answer the maturity questionnaire's alcohol question
--         (presence / depiction of alcohol -> Restricted 17+).
-- true  = non-alcoholic labels everywhere this layer prints ("무알콜 스파클링", "음료 세트", 🧃 / ✨
--         instead of 🍾 / 🥂). Also switchable without editing this file: GwangalliConfig.ClubShow =
--         { AllAges = true } or the workspace attribute GwangalliClubAllAges = true / false.
ShowShared.ALL_AGES = false

local configTried, configAA = false, nil :: boolean?
function ShowShared.allAges(): boolean
	local ok, ws = pcall(function()
		local g: any = game
		return g:GetService("Workspace"):GetAttribute("GwangalliClubAllAges")
	end)
	if ok and type(ws) == "boolean" then
		return ws
	end
	if not configTried then
		configTried = true
		pcall(function()
			local g: any = game
			local m = g:GetService("ReplicatedStorage"):FindFirstChild("GwangalliConfig")
			if m and m:IsA("ModuleScript") then
				local cfg: any = require(m)
				local cs = type(cfg) == "table" and cfg.ClubShow
				if type(cs) == "table" and type(cs.AllAges) == "boolean" then
					configAA = cs.AllAges
				end
			end
		end)
	end
	if configAA ~= nil then
		return configAA
	end
	return ShowShared.ALL_AGES
end

---------------------------------------------------------------------------------------------------
-- Paid door
---------------------------------------------------------------------------------------------------
-- Prices next to the jobs (docs/JOBS.md): one convenience-store shift pays ~28,000-33,000원, so a
-- weekday walk-in costs about one shift and a weekend night a little under two.
ShowShared.Door = {
	Enabled = true, -- false (or workspace attribute GwangalliClubFreeEntry = true): free entry, no walk-out
	Weekday = 30000,
	Weekend = 50000, -- Friday / Saturday nights (KST, 06:00 -> 06:00)
	WristbandSeconds = 1440, -- one in-game day (24 real minutes): leave and come back for free meanwhile
	EjectEvery = 2, -- server: seconds between "inside without a wristband?" sweeps
	PayDistance = 26, -- server: studs from the door / bouncer a payment is accepted
	OpenRadius = 8.5, -- client: the door slides open for a wristband holder this close
	CloseDelay = 1.4, -- client: seconds the door stays open after the last person passed
	SlideTime = 0.75,
	StopRadius = 4.2, -- client: an unpaid player this close to the closed door gets the bouncer's hand
	BouncerRadius = 140, -- client: the bouncer rig exists while the camera is this close
	TableOption = "basic", -- the door's "테이블 예약 입장" sells this set (entry included)
}

-- Korean time parts of a unix time: weekday (1 = Sunday .. 7 = Saturday), hour.
function ShowShared.kst(unix: number): (number, number)
	local t = math.floor(unix) + 9 * 3600
	local days = math.floor(t / 86400)
	local wday = ((days + 4) % 7) + 1 -- 1970-01-01 was a Thursday (wday 5)
	local hour = math.floor((t % 86400) / 3600)
	return wday, hour
end

-- Friday / Saturday NIGHT: the night belongs to the evening it started (until 06:00 KST).
function ShowShared.isWeekendNight(unix: number): boolean
	local wday = ShowShared.kst(unix - 6 * 3600)
	return wday == 6 or wday == 7
end

function ShowShared.doorFee(unix: number): (number, boolean)
	local weekend = ShowShared.isWeekendNight(unix)
	return if weekend then ShowShared.Door.Weekend else ShowShared.Door.Weekday, weekend
end

function ShowShared.wristbandValid(untilT: any, now: number): boolean
	return type(untilT) == "number" and untilT == untilT and untilT > now
end

---------------------------------------------------------------------------------------------------
-- Bottle menu (server-authoritative prices; the client only shows them)
---------------------------------------------------------------------------------------------------
-- tier 1: one server brings the set (table life only). tier 2+: the bottle-service show (staff line
-- with sparkler fountains, LED wall thanks, spotlight); tier 3+: DJ shout-out + crowd cheer and the
-- 합석 이벤트 can be asked for; tier 4+: the 합석 이벤트 starts by itself; tier 5: confetti + CO2.
-- Names are made up (no real brands).
ShowShared.Menu = {
	{ id = "basic", tier = 1, price = 90000, icon = "🧊", iconAA = "🧊", label = "기본 세트", labelAA = "기본 세트 · 음료 버킷", desc = "얼음 버킷 · 과일 안주 · 잔 세팅 (테이블 잡기)", staff = 1, set = "basic" },
	{ id = "champagne", tier = 2, price = 200000, icon = "🍾", iconAA = "🧃", label = "샴페인 · 루미에르 브뤼", labelAA = "무알콜 스파클링 · 루미에르", desc = "스파클러 서빙 2명 · LED 월 감사 인사", staff = 2, set = "champagne", parade = true },
	{ id = "vodka", tier = 3, price = 350000, icon = "🥃", iconAA = "🥤", label = "보드카 세트 · 블랙 스완", labelAA = "프리미엄 음료 세트 · 블랙 스완", desc = "퍼레이드 3명 · DJ 샤라웃 · 합석 이벤트 신청 가능", staff = 3, set = "vodka", parade = true, dj = true },
	{ id = "gold", tier = 4, price = 600000, icon = "🥂", iconAA = "✨", label = "프리미엄 샴페인 · 골드 레전드", labelAA = "골드 스파클링 · 레전드 (무알콜)", desc = "퍼레이드 4명 · 스포트라이트 · 합석 이벤트", staff = 4, set = "gold", parade = true, dj = true, booking = true },
	{ id = "royal", tier = 5, price = 1200000, icon = "👑", iconAA = "👑", label = "오션 로얄 세트", labelAA = "오션 로얄 세트 (무알콜)", desc = "퍼레이드 5명 · 컨페티 · CO2 · 전광판 · 합석 이벤트", staff = 5, set = "royal", parade = true, dj = true, booking = true, confetti = true },
}
local byId: { [string]: any } = {}
for i, item in ShowShared.Menu do
	item.order = i
	byId[item.id] = item
end
function ShowShared.item(id: any): any?
	return if type(id) == "string" then byId[id] else nil
end
function ShowShared.label(item: any, aa: boolean?): string
	if aa == nil then
		aa = ShowShared.allAges()
	end
	return (if aa then item.labelAA else item.label) or item.label or "?"
end
function ShowShared.icon(item: any, aa: boolean?): string
	if aa == nil then
		aa = ShowShared.allAges()
	end
	return (if aa then item.iconAA else item.icon) or "🍾"
end

-- the LED wall / DJ / toast lines (the name must already be filtered by the server)
function ShowShared.thanksTitle(tableId: string, aa: boolean): string
	return string.format("%s 테이블 감사합니다 %s", tableId, if aa then "✨" else "🥂")
end
function ShowShared.djLine(tableId: string, name: string): string
	return string.format("🎤 %s 테이블 %s님 감사합니다! 다 같이 소리 질러~!", tableId, name)
end
function ShowShared.bookingTitle(tableId: string): string
	return string.format("✨ 합석 이벤트 · %s 테이블 ✨", tableId)
end
function ShowShared.cheersWord(aa: boolean): string
	return if aa then "짠~! ✨" else "짠~! 🥂"
end

---------------------------------------------------------------------------------------------------
-- Show timing (client choreography; the server only needs the totals)
---------------------------------------------------------------------------------------------------
ShowShared.Show = {
	LeadIn = 2.2, -- dim + LED + spotlight first, then the first staff member steps out
	Speed = 4.6, -- staff walking speed (studs / s), bottles held high
	BasicSpeed = 6.2, -- tier 1: one server, brisk
	Gap = 3.0, -- spacing in the line (studs)
	Hold = 11, -- seconds lined up at the table with the sparklers burning
	Spread = 2.5, -- sideways spacing at the table
	Stand = 3.1, -- staff stop this far before the ServePoint
	Outro = 2.5, -- after the walk back
	PropSeconds = 480, -- the table keeps its bottles / glasses / bucket glow this long
	OrderCooldownPlayer = 20,
	OrderCooldownTable = 25,
	MaxDistance = 18, -- server: character within this of the table's ServePoint to order
	MaxQueue = 3, -- shows waiting behind the current one
}

ShowShared.Booking = {
	MinTier = 3, -- an order of at least this tier lets the player ask for the 합석 이벤트
	AutoTier = 4, -- from this tier it starts by itself after the parade
	Min = 2,
	Max = 4,
	Speed = 5.4, -- strut (studs / s); the client matches the walk clip to the music's BPM
	Gap = 2.6,
	Intro = 2.4, -- LED announcement + spotlight sweep before the walk-in
	Present = 4.5, -- group pose + wave at the table
	Duration = 150, -- the hangout ends by itself (guests wave and leave)
	Cooldown = 240, -- per player
	DanceSeconds = 45,
	MD = "MD 태양",
}

-- Quality caps per GwangalliQuality tier (client)
ShowShared.Q = {
	high = { spark = 36, confetti = 140, trails = true, feet = 10, spotLight = true, bubbles = 3 },
	mid = { spark = 24, confetti = 90, trails = true, feet = 6, spotLight = true, bubbles = 2 },
	low = { spark = 12, confetti = 45, trails = false, feet = 3, spotLight = false, bubbles = 2 },
	saver = { spark = 6, confetti = 20, trails = false, feet = 0, spotLight = false, bubbles = 1 },
}

---------------------------------------------------------------------------------------------------
-- Paths (pure)
---------------------------------------------------------------------------------------------------
-- cumulative flat distances of a polyline
function ShowShared.polyline(pts: { Vector3 }): ({ number }, number)
	local cum = { 0 }
	local total = 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		total += Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
		cum[i] = total
	end
	return cum, total
end

-- point + flat direction at distance d along the polyline
function ShowShared.sample(pts: { Vector3 }, cum: { number }, d: number): (Vector3, Vector3)
	local n = #pts
	if n == 0 then
		return Vector3.zero, Vector3.new(0, 0, 1)
	elseif n == 1 then
		return pts[1], Vector3.new(0, 0, 1)
	end
	if d <= 0 then
		local dir = Vector3.new(pts[2].X - pts[1].X, 0, pts[2].Z - pts[1].Z)
		return pts[1], if dir.Magnitude > 1e-4 then dir.Unit else Vector3.new(0, 0, 1)
	end
	for i = 2, n do
		if d <= cum[i] or i == n then
			local a, b = pts[i - 1], pts[i]
			local seg = cum[i] - cum[i - 1]
			local t = if seg > 1e-4 then math.clamp((d - cum[i - 1]) / seg, 0, 1) else 1
			local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			return a:Lerp(b, t), if dir.Magnitude > 1e-4 then dir.Unit else Vector3.new(0, 0, 1)
		end
	end
	return pts[n], Vector3.new(0, 0, 1)
end

-- n standing spots in front of a target: centred on `front` (the point the line arrives at),
-- spread sideways across `dir` (the arrival direction), the middle one a little closer.
function ShowShared.lineup(front: Vector3, dir: Vector3, n: number, spread: number): { Vector3 }
	local f = Vector3.new(dir.X, 0, dir.Z)
	f = if f.Magnitude > 1e-4 then f.Unit else Vector3.new(0, 0, 1)
	local side = Vector3.new(-f.Z, 0, f.X)
	local out = {}
	for i = 1, n do
		local k = (i - (n + 1) / 2)
		local arc = math.abs(k) * 0.35
		out[i] = front + side * (k * spread) - f * arc
	end
	return out
end

-- seconds a parade-style walk takes (path length / speed)
function ShowShared.travel(total: number, speed: number): number
	return total / math.max(0.1, speed)
end

-- the whole bottle-service show length (server housekeeping + client cleanup)
function ShowShared.showLength(total: number, staff: number, tier: number): number
	local C = ShowShared.Show
	local speed = if tier <= 1 then C.BasicSpeed else C.Speed
	local walk = ShowShared.travel(total, speed) + (staff - 1) * C.Gap / speed
	local hold = if tier <= 1 then 3 else C.Hold
	return C.LeadIn + walk * 2 + hold + C.Outro
end

---------------------------------------------------------------------------------------------------
-- 합석 이벤트: guests + friendly lines (all-ages social framing: friends hanging out, no romance)
---------------------------------------------------------------------------------------------------
local EXCLUDED_TYPES = { violent = true, drunk = true, beggar = true }

-- Up to n roster ids for the event: adults (20+), not key NPCs, not the troublemaker types, people
-- who like clubbing; mixed (at least one of each when n >= 2). Deterministic for a seed.
function ShowShared.pickGuests(Citizens: any, n: number, seed: number, exclude: { [string]: boolean }?): { string }
	local pool: { any } = {}
	for _, id in Citizens.ORDER or {} do
		local c = Citizens.byId and Citizens.byId[id]
		if c and not c.key and not c.minor and (c.age or 0) >= 20 and (c.club or 0) >= 0.45 and not EXCLUDED_TYPES[c.type or ""] and not (exclude and exclude[id]) then
			table.insert(pool, c)
		end
	end
	local function h(s: string): number
		local x = 0
		for i = 1, #s do
			x = (x * 31 + string.byte(s, i)) % 1000003
		end
		return ((x * 7919 + seed * 104729) % 1000003) / 1000003
	end
	table.sort(pool, function(a, b)
		local ha, hb = h(a.id), h(b.id)
		if ha == hb then
			return a.id < b.id
		end
		return ha < hb
	end)
	local out: { string } = {}
	local count = { f = 0, m = 0 }
	for _, c in pool do
		if #out >= n then
			break
		end
		local g = if c.g == "f" then "f" else "m"
		local other = if g == "f" then "m" else "f"
		-- keep it mixed: nobody past half the group of one gender while the other is missing
		if n >= 2 and count[g] >= math.ceil(n / 2) and count[other] == 0 then
			continue
		end
		table.insert(out, c.id)
		count[g] += 1
	end
	return out
end

-- Club lines by register (p = polite, tiers 1-2; c = casual, 친한 사이+). {name} = the player.
ShowShared.Lines = {
	arrive = {
		p = { "안녕하세요! MD님이 여기가 오늘 제일 핫한 테이블이래요 😆", "와 이 테이블 분위기 최고네요! 같이 놀아도 돼요?", "{name}님 테이블 맞죠? 반가워요! 👋", "오늘 음악 완전 좋죠? 같이 즐겨요! 🎶" },
		c = { "{name}! 여기서 보니까 더 반갑다 ㅋㅋ", "오 {name} 테이블이었어? 대박 👋", "{name}~ 오늘 분위기 미쳤다!", "역시 {name} 테이블이 제일 신나 보여 😆" },
	},
	talk = {
		p = { "DJ 선곡 진짜 미쳤어요 ㅋㅋ", "광안대교 불빛 보고 왔는데 오늘 완전 예뻐요", "LED 월 볼 때마다 소름 돋아요!", "이 노래 나오면 다들 손 올리더라고요 🙌", "아까 퍼레이드 완전 멋있었어요!" },
		c = { "야 이 노래 완전 내 스타일이야 ㅋㅋ", "아까 퍼레이드 봤어? 소름!", "LED 월 진짜 미쳤다 ㅋㅋ", "오늘 광안리 사람 진짜 많더라", "다음 곡 터질 것 같지 않아? 🔥" },
	},
	laugh = { p = { "ㅋㅋㅋ 진짜요?", "아 웃겨요 ㅋㅋ", "ㅎㅎ 맞아요!" }, c = { "ㅋㅋㅋㅋ 미쳤다", "아 진짜 웃겨 ㅋㅋ", "인정 ㅋㅋ" } },
	dance = { p = { "좋아요! 이 노래 완전 신나요 💃", "가요 가요! 플로어로~ 🕺" }, c = { "콜! 가자 가자 💃", "오 좋아 플로어 가자 🕺" } },
	bye = { p = { "오늘 진짜 재밌었어요! 다음에 또 봐요 👋", "덕분에 즐거웠어요! 좋은 밤 보내세요 ✨" }, c = { "오늘 완전 재밌었다! 또 보자 👋", "고마워 {name}! 다음에 또 놀자 ✨" } },
}

function ShowShared.register(tier: number): string
	return if tier >= 3 then "c" else "p"
end

function ShowShared.line(kind: string, tier: number, rnd: number, name: string): string
	local bank = ShowShared.Lines[kind]
	if not bank then
		return ""
	end
	local list = bank[ShowShared.register(tier)] or bank.p
	local s = list[math.clamp(math.floor(rnd * #list) + 1, 1, #list)] or ""
	return (string.gsub(s, "{name}", function()
		return name
	end))
end

return ShowShared
