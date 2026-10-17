-- GwangalliClubPlusShared: contract + config + pure helpers for the CLUB OCEAN 광안 AAA show add-on
-- (ServerScriptService.GwangalliClubPlus + StarterPlayerScripts.GwangalliClubPlus).
-- Nothing is created and nothing yields at require time (safe on both peers).
--
-- Contract (created by the server, parented last):
--   ReplicatedStorage.GwangalliClubPlus (Folder)
--     RemoteEvent Request   client -> server (op: string, payload: table)
--         ops: "menu" {}, "donate" {rid, amount, msg?, target?}, "robux" {rid, product, msg?, target?},
--              "dj" {op = "join"|"leave"|"goto"|"pad"|"admin", pad?, text?, admin?}
--     RemoteEvent Event     server -> client (kind: string, payload: table)
--         kinds: "menu", "receipt", "toast", "order" (rank enrichment), "fx" (world cue), "dj" (private DJ state)
--     attributes (JSON, server-written only):
--       Stage   { v, serial, cues = { cue }, ticker = { {k, n, t, w, at} } }
--               cue = { id, kind = "donate"|"dj"|"djon", at, dur, tier, holds = { {from, to} }, data }
--       Boards  { v, night, week, nl, wl, src, spend, donate, best, weekly = { {u, n, v, x?} }, kings = {spend, donate} }
--       DJ      { on, u, n, at, untilT, queue = { {u, n} } }
--       Active  (bool) the add-on is running
--   ServerStorage.GwangalliReceiptHandlers (Folder) / BindableFunction "GwangalliClubPlus"
--       Invoke(receiptInfo) -> Enum.ProductPurchaseDecision? (nil = not one of our products)
--   Player attributes: GwClubPlusTonight (원 후원 tonight), GwClubPlusWeek (원 this week, orders + 후원)
--
-- Everything listens to the existing club contract (GwangalliClubShowShared: Show / Tables / Booking
-- attributes, ClubShowHook, GwangalliGameplayAPI, ClubShared.Bus, GwangalliClubRanking). The club's
-- own scripts are never edited.

local Shared = {}

Shared.VERSION = 1

Shared.Names = {
	Folder = "GwangalliClubPlus",
	Request = "Request",
	Event = "Event",
	LocalFolder = "GwangalliClubPlusLocal", -- Workspace (client-only world props)
	ReceiptFolder = "GwangalliReceiptHandlers", -- ServerStorage: one BindableFunction per add-on
	ReceiptHandler = "GwangalliClubPlus",
	ReceiptOwnerAttr = "GwProcessReceiptOwner", -- ServerStorage attribute: who assigned ProcessReceipt
	-- the existing club (read only)
	ClubFolder = "GwangalliClubShow",
	ClubShared = "ClubShared",
	ShowShared = "GwangalliClubShowShared",
	ClubHook = "ClubShowHook",
	GameplayAPI = "GwangalliGameplayAPI",
	Ranking = "GwangalliClubRanking",
	ShowLocal = "GwangalliClubShowLocal", -- the club show's client folder (staff / MD / guest rigs)
}

Shared.Attr = {
	Stage = "Stage",
	Boards = "Boards",
	DJ = "DJ",
	Active = "Active",
	Tonight = "GwClubPlusTonight",
	Week = "GwClubPlusWeek",
}

---------------------------------------------------------------------------------------------------
-- Config (server-authoritative; the client only displays it)
---------------------------------------------------------------------------------------------------
Shared.Config = {
	Enabled = true,
	RequireWristband = true, -- 후원 / DJ only with a valid ClubOcean wristband (when the door system exists)

	-- order tiers (일반 / 프리미엄 / VIP / 레전드) by the order's price (원)
	OrderTier = { premium = 150000, vip = 300000, legend = 1000000 },
	-- 후원 tiers by amount
	DonateTier = { premium = 50000, vip = 200000, legend = 1000000 },

	Donate = {
		Presets = { 10000, 30000, 50000, 100000, 300000, 1000000 },
		Min = 5000,
		Max = 10000000,
		Step = 1000,
		Cooldown = 20, -- seconds between two 후원 of one player
		MaxQueue = 10, -- LED cues waiting (all players)
		MaxPerPlayer = 2, -- LED cues waiting per player
		MessageMax = 30, -- characters (after filtering)
		Templates = { "생일 축하해! 🎂", "오늘 밤 최고! 🔥", "DJ 선곡 대박 🎧", "광안리 사랑해 🌊", "다들 반가워요 🙌", "우리 테이블 파이팅! 💪" },
		Stats = true, -- small happiness / popularity gain like the club's orders
	},

	-- Optional Robux 후원 (developer products). Empty = the Robux section is hidden and
	-- ProcessReceipt is never touched. Example:
	--   { id = 1234567890, won = 1000000, label = "레전드 후원 (로벅스)" }
	-- `won` is what the 후원 counts as on the LED / rankings.
	Robux = {
		Products = {} :: { { id: number, won: number, label: string } },
		InstallProcessReceipt = true, -- assign MarketplaceService.ProcessReceipt only when nobody claimed it
		ClaimWait = 6, -- seconds to let a central receipt handler claim ProcessReceipt first
		IntentSeconds = 240, -- a prepared message waits this long for its purchase
	},

	DJ = {
		Enabled = true,
		TurnSeconds = 180, -- one turn
		MaxQueue = 6,
		Price = 0, -- 원 per turn (0 = free); charged when joining, refunded when skipped
		AgainCooldown = 300, -- seconds after a turn ends before the same player can join again
		BoothRadius = 13, -- studs from the booth (Show_DJ anchor) to use the pad
		ArriveSeconds = 45, -- a DJ who is not in the club when the turn starts is skipped after this
		Admins = {} :: { number }, -- UserIds (the place owner is always an admin)
		AdminGroupId = 0, -- optional group: members with rank >= AdminMinRank are admins
		AdminMinRank = 254,
		TextMax = 24,
		ShareRate = 0.3, -- share of 후원 that targets the DJ paid to the DJ (bank, label with 정산)
		ShareCapPerNight = 300000,
		Pads = {
			{ id = "laser", label = "레이저 쇼", icon = "🟣", cooldown = 10 },
			{ id = "co2", label = "CO2", icon = "💨", cooldown = 12 },
			{ id = "fireworks", label = "폭죽", icon = "🎆", cooldown = 15 },
			{ id = "strobe", label = "스트로브", icon = "⚡", cooldown = 8 },
			{ id = "hands", label = "손 머리 위로", icon = "🙌", cooldown = 10 },
			{ id = "text", label = "LED 문구", icon = "💬", cooldown = 20 },
		},
		PadGap = 1.2, -- seconds between any two pads
	},

	Ranking = {
		Top = 5,
		FlushEvery = 30, -- seconds between DataStore writes of pending totals
		SyncEvery = 60, -- seconds between reads of the shared top lists
		Retries = 3,
		BestOrders = 5, -- 최고가 주문 list length
	},

	Stage = {
		Lead = 0.8, -- a new cue starts at least this long after it was accepted
		Gap = 0.5, -- seconds between two cues
		MaxCues = 10, -- cues kept in the Stage attribute (running + waiting)
		Ticker = 10,
	},

	Rate = { Burst = 8, PerSecond = 2 }, -- remote token bucket per player

	-- client show budgets per quality tier (GwangalliQuality: high | mid | low, saver)
	Quality = {
		high = { lasers = 4, heads = 8, headLights = 4, strobes = 4, haze = true, mirror = 140, confetti = 160, co2 = 6, ripple = true, signs = true, trails = true },
		mid = { lasers = 2, heads = 6, headLights = 2, strobes = 2, haze = true, mirror = 90, confetti = 100, co2 = 4, ripple = true, signs = true, trails = true },
		low = { lasers = 1, heads = 4, headLights = 0, strobes = 2, haze = false, mirror = 40, confetti = 50, co2 = 2, ripple = true, signs = true, trails = false },
		saver = { lasers = 0, heads = 0, headLights = 0, strobes = 0, haze = false, mirror = 0, confetti = 24, co2 = 2, ripple = false, signs = true, trails = false },
	},

	-- fallbacks when the map lookups fail (world space, CLUB OCEAN 광안 v7)
	Fallback = {
		LEDWall = { pos = Vector3.new(-72.88, 23.82, 373.99), size = Vector3.new(56, 17.05, 0.1) },
		DJ = Vector3.new(-98.78, 17.5, 373.70),
		Floor = Vector3.new(-106.83, 10, 373.48),
		SideLED = { pos = Vector3.new(-118.8, 23.3, 411.76), size = Vector3.new(0.5, 15.6, 58.4) },
		DJSpotOffset = Vector3.new(1.4, -4.2, 4.1), -- guest DJ spot relative to the Show_DJ anchor
	},
}

---------------------------------------------------------------------------------------------------
-- Tiers
---------------------------------------------------------------------------------------------------
Shared.Tiers = {
	{ id = "normal", label = "일반", en = "ORDER", color = Color3.fromRGB(61, 214, 245), accent = Color3.fromRGB(150, 235, 255) },
	{ id = "premium", label = "프리미엄", en = "PREMIUM", color = Color3.fromRGB(255, 79, 163), accent = Color3.fromRGB(255, 190, 225) },
	{ id = "vip", label = "VIP", en = "VIP", color = Color3.fromRGB(150, 70, 255), accent = Color3.fromRGB(255, 194, 71) },
	{ id = "legend", label = "레전드", en = "LEGEND", color = Color3.fromRGB(255, 194, 71), accent = Color3.fromRGB(255, 250, 220) },
}

local function tierBy(amount: number, t: { premium: number, vip: number, legend: number }): number
	if amount >= t.legend then
		return 4
	elseif amount >= t.vip then
		return 3
	elseif amount >= t.premium then
		return 2
	end
	return 1
end
function Shared.orderTier(price: number): number
	return tierBy(price, Shared.Config.OrderTier)
end
function Shared.donateTier(amount: number): number
	return tierBy(amount, Shared.Config.DonateTier)
end
function Shared.tier(i: any): any
	return Shared.Tiers[math.clamp(math.floor(tonumber(i) or 1), 1, 4)]
end

-- LED takeover lengths (seconds)
Shared.Durations = {
	order = { 0, 5.2, 7.0, 9.5 }, -- tier 1 orders only run the lower band
	orderBand = 7,
	donate = { 6.5, 8.5, 10.5, 14 },
	dj = 6,
	djon = 5.5,
	booking = 6.5,
}
function Shared.orderIntro(tier: number): number
	return Shared.Durations.order[math.clamp(tier, 1, 4)]
end
function Shared.donateLength(tier: number): number
	return Shared.Durations.donate[math.clamp(tier, 1, 4)]
end

---------------------------------------------------------------------------------------------------
-- Time keys: the club's night runs 06:00 KST -> 06:00 KST (same as the door and ClubRanking);
-- weeks start on Monday 06:00 KST (night 0 = Thursday 1970-01-01).
---------------------------------------------------------------------------------------------------
function Shared.nightOf(unix: number): number
	return math.floor((unix + 9 * 3600 - 6 * 3600) / 86400)
end
function Shared.weekOf(night: number): number
	return math.floor((night + 3) / 7)
end
local function dateOf(night: number): (number, number)
	local t = os.date("!*t", night * 86400) :: any
	return t.month, t.day
end
function Shared.nightLabel(night: number): string
	local m, d = dateOf(night)
	return string.format("%d월 %d일", m, d)
end
function Shared.weekLabel(week: number): string
	local first = week * 7 - 3
	local m1, d1 = dateOf(first)
	local m2, d2 = dateOf(first + 6)
	return string.format("%d.%d ~ %d.%d", m1, d1, m2, d2)
end

---------------------------------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------------------------------
function Shared.commas(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-" else "") .. out
end
function Shared.won(n: number): string
	return Shared.commas(n) .. "원"
end
-- 1,234,000 -> "123만 4천원"-style short form for boards ("1.2억", "350만", "9만 5천")
function Shared.wonShort(n: number): string
	n = math.floor(n)
	if n >= 100000000 then
		local v = n / 100000000
		return (if v >= 10 then string.format("%d억", math.floor(v)) else string.format("%.1f억", math.floor(v * 10) / 10)) .. "원"
	elseif n >= 10000 then
		local man = math.floor(n / 10000)
		local rest = math.floor((n % 10000) / 1000)
		if rest > 0 and man < 100 then
			return string.format("%d만 %d천원", man, rest)
		end
		return string.format("%d만원", man)
	end
	return Shared.commas(n) .. "원"
end

---------------------------------------------------------------------------------------------------
-- Validation (server) / text helpers
---------------------------------------------------------------------------------------------------
function Shared.isInt(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and math.floor(v) == v
end

-- trims, removes control characters / newlines, collapses spaces; nil when empty, not valid
-- UTF-8 or longer than `maxChars` characters
function Shared.cleanText(s: any, maxChars: number): string?
	if type(s) ~= "string" or #s == 0 or #s > maxChars * 4 + 8 then
		return nil
	end
	if utf8.len(s) == nil then
		return nil
	end
	s = s:gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then
		return nil
	end
	local n = utf8.len(s)
	if not n or n > maxChars then
		return nil
	end
	return s
end

-- a filtered string that came back (mostly) as #### is not worth showing
function Shared.mostlyHashed(s: string): boolean
	local hashes = select(2, s:gsub("#", ""))
	local len = utf8.len(s) or #s
	return len > 0 and hashes / len > 0.5
end

function Shared.amountOk(amount: any): boolean
	local D = Shared.Config.Donate
	if not Shared.isInt(amount) then
		return false
	end
	for _, p in D.Presets do
		if amount == p then
			return true
		end
	end
	return amount >= D.Min and amount <= D.Max and amount % D.Step == 0
end

function Shared.product(id: any): any?
	if not Shared.isInt(id) then
		return nil
	end
	for _, p in Shared.Config.Robux.Products do
		if type(p) == "table" and p.id == id then
			return p
		end
	end
	return nil
end

function Shared.pad(id: any): any?
	if type(id) ~= "string" then
		return nil
	end
	for _, p in Shared.Config.DJ.Pads do
		if p.id == id then
			return p
		end
	end
	return nil
end

function Shared.quality(tierName: string?, saver: boolean?): any
	local Q = Shared.Config.Quality
	if saver then
		return Q.saver
	end
	return Q[tierName or "mid"] or Q.mid
end

-- JSON (HttpService works on both peers)
local HttpService = game:GetService("HttpService")
function Shared.encode(v: any): string?
	local ok, s = pcall(HttpService.JSONEncode, HttpService, v)
	return if ok and type(s) == "string" then s else nil
end
function Shared.decode(s: any): any
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local ok, v = pcall(HttpService.JSONDecode, HttpService, s)
	return if ok then v else nil
end

-- deterministic 0..1 hash (same on every client)
function Shared.hash(a: number, b: number?): number
	local x = math.sin(a * 12.9898 + (b or 0) * 78.233) * 43758.5453
	return x - math.floor(x)
end

Shared.Lines = require(script:WaitForChild("Lines"))

return Shared
