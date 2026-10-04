-- GwangalliShopsShared: data + world contract of the ENTERABLE STREET SHOPS (owner: interiors/shops).
-- Seven ground-floor shops on 광안해변로 that you walk into through their automatic doors (no
-- loading): 광안 치킨, 행복 돼지국밥, 광안 떡볶이 (분식), 바다옷장 (옷가게), 헤어살롱 물결 (미용실),
-- 바다약국, 광안 서프 & SUP. Builder: build/venues/shops*.luau. Server: GwangalliGameplay/Shops.luau.
-- Client: StarterPlayerScripts/GwangalliShops.client.luau (+ folder GwangalliShops). Docs: docs/SHOPS.md.
--
-- Plain module: data + pure helpers at require time (Lune-loadable: the builder reads the prices
-- for the menu boards). SH.prop / SH.carry build runtime props (Instance.new) and are only called
-- on the server / client (or offline with the Roblox globals published, like the staff rigs).
--
-- WORLD CONTRACT (built by build/venues/shops.luau; everything under Workspace.Gwangalli.shops):
--   Model <shop name>      tag GwShop, attrs ShopId, DisplayName
--     Part  ShopBounds     invisible box of the walk-in room (CFrame = room centre, Size = u, v, w)
--     Folder Points        anchor parts tag GwShopPoint, attrs ShopId, PointKind (SH.POINT_KINDS),
--                          Index, Label. The server adds ONE ProximityPrompt to each.
--                          parts tag GwShopSpot, attrs ShopId, Act, Index: ambient customer spots
--                          (CFrame = standing HumanoidRootPart CFrame, scale 1; sitting acts lower it)
--     Model Interior       zone LOD (LOD = "zone"): furniture, props, staff
--       Model Table_<n>    tag GwShopTable, attrs ShopId, Index: Seat children named "Seat"
--                          (Disabled until the server sits someone) + Part "TrayPoint" (tray centre)
--       Model <npc>        tag GwShopClerk, attrs ShopId, Role (clerk|cook|stylist|pharmacist),
--                          Act (GwangalliAnim act), NpcName. Static R15 block rig (GwangalliNPCLooks).
--       Part Curtain       tag GwShopCurtain, attrs ShopId, Index, OpenOffset (Vector3 world)
--       Part SalonChair_<n> the styling chair Seat, attrs ShopId, Index (PointKind "chair")
--
-- REMOTES (ReplicatedStorage.GwangalliRemotes, created by Shops.luau):
--   ShopRequest  RemoteFunction (op, payload) -> { ok, code, message, ... }
--     ops: menu {shop} | order {shop, item, mode = "here"|"togo"} | sit {} | eat {} | buy {shop, item}
--          | tryon {item} | fitEnd {} | hair {item} | leave {} | state {}
--   ShopEvent    RemoteEvent server -> client { kind = ..., ... } (SH.EVENTS)

local SH = {}
SH.VERSION = 1

SH.Tags = {
	Shop = "GwShop",
	Point = "GwShopPoint",
	Table = "GwShopTable",
	Clerk = "GwShopClerk",
	Spot = "GwShopSpot",
	Curtain = "GwShopCurtain",
}
SH.Remote = { Request = "ShopRequest", Event = "ShopEvent" }
-- point kinds: order (food counter), counter (retail desk), fitting (fitting room), chair (salon chair)
SH.POINT_KINDS = { order = true, counter = true, fitting = true, chair = true }
SH.EVENTS = {
	"open", -- { shop, mode = "menu"|"fitting"|"salon", chair? } open the order sheet
	"close", -- { shop } close it (left the shop / session ended)
	"order", -- { order } your order state changed (placed / cooking / served / eating / done)
	"served", -- { shop, table, userId } a tray arrived (everyone near: clerk line + bell)
	"greet", -- { shop, line } staff line for the local player
	"cut", -- { shop, chair, userId, seconds } stylist starts cutting (everyone near)
	"cutDone", -- { shop, chair, userId }
	"fit", -- { shop, booth, item? } fitting session state
	"line", -- { shop, role, text } staff speech bubble (everyone near)
}

-- tuning ------------------------------------------------------------------------------------------
SH.PROMPT_DIST = 7 -- ProximityPrompt MaxActivationDistance (studs)
SH.REACH = 8 -- server: the player must be within the ShopBounds box grown by this many studs
SH.SIT_REACH = 14 -- studs from your table to use "앉기"
SH.SERVED_TIMEOUT = 180 -- a served tray nobody eats is cleared after this many seconds
SH.LEFTOVER_SECONDS = 18 -- empty plates stay this long after eating
SH.BAG_SECONDS = 150 -- a take-out bag / drink stays in the hand this long
SH.BOARD_SECONDS = 600 -- a rented surfboard is carried this long (same as the SUP buff)
SH.CUT_SECONDS = 8 -- hair styling choreography
SH.FIT_IDLE = 150 -- a fitting session ends by itself after this long without a tap
SH.CLERK_RADIUS = 46 -- client: staff animate / customers appear within this many studs of a shop
SH.GREET_COOLDOWN = 45 -- client: seconds before the same shop greets you again

-- colours (r, g, b) used by the UI accents
SH.SHOPS = {
	chicken = {
		awning = "#D9480F",
		name = "광안 치킨",
		short = "치킨집",
		icon = "🍗",
		kind = "food",
		accent = { 255, 176, 32 },
		menu = { "chicken_fried", "chicken_yangnyeom", "chicken_banban", "chicken_half" },
		modes = { "here", "togo" },
		sheetTitle = "광안 치킨 · 주문",
		sheetSub = "주문하면 자리로 가져다 드려요",
		lines = {
			greet = { "어서오세요~ 광안 치킨입니다!", "어서오세요! 오늘 닭 아주 잘 튀겨졌어요", "편한 자리 앉으세요~ 주문은 카운터에서!" },
			order = { "네~ 바로 튀겨 드릴게요! 자리에 앉아 계세요", "후라이드 하나요~ 15분… 아니 15초만 기다리세요!" },
			served = { "주문하신 치킨 나왔습니다~ 뜨거우니까 조심하세요!", "치킨 나왔어요~ 무는 더 드릴 수 있어요!" },
			togo = { "포장 나왔습니다~ 식기 전에 드세요!" },
			bye = { "감사합니다~ 또 오세요!", "맛있게 드셨어요? 또 오세요~" },
		},
	},
	gukbap = {
		awning = "#7A1F1F",
		name = "행복 돼지국밥",
		short = "국밥집",
		icon = "🍲",
		kind = "food",
		accent = { 236, 120, 72 },
		menu = { "gukbap_pork", "gukbap_sundae", "gukbap_mixed", "gukbap_suyuk" },
		modes = { "here" },
		sheetTitle = "행복 돼지국밥 · 주문",
		sheetSub = "앉아 계시면 바로 가져다 드립니더",
		lines = {
			greet = { "어서오이소~ 행복 돼지국밥입니더!", "앉으이소, 국물 펄펄 끓고 있습니더", "혼자 오셨어예? 편한 데 앉으이소~" },
			order = { "국밥 하나요~ 금방 나갑니더!", "네~ 정구지 많이 드릴게예" },
			served = { "국밥 나왔습니더~ 부추랑 새우젓 넣어 드이소!", "뜨끈할 때 드이소~ 밥은 말아 드셔도 돼요" },
			bye = { "마이 무따? 또 오이소~", "든든하게 드셨지예? 조심히 가이소~" },
		},
	},
	snack = {
		awning = "#C0392B",
		name = "광안 떡볶이",
		short = "분식집",
		icon = "🍢",
		kind = "food",
		accent = { 232, 64, 52 },
		menu = { "snack_tteok", "snack_gimbap", "snack_eomuk", "snack_twigim", "snack_set" },
		modes = { "here", "togo" },
		sheetTitle = "광안 떡볶이 · 주문",
		sheetSub = "매장에서 먹거나 포장해 가세요",
		lines = {
			greet = { "어서오세요~ 떡볶이 방금 나왔어요!", "어묵 국물은 셀프예요~ 마음껏 드세요", "튀김 갓 튀겼어요~ 구경하세요!" },
			order = { "네~ 금방 담아 드릴게요!", "떡볶이 맵기 보통이죠? 바로 나가요~" },
			served = { "주문하신 거 나왔어요~ 맛있게 드세요!" },
			togo = { "포장이요~ 봉투에 담아 드렸어요!", "포장 완료~ 국물 안 새게 묶었어요" },
			bye = { "감사합니다~ 또 오세요!", "학생 또 와~" },
		},
	},
	clothing = {
		awning = "#1D3557",
		name = "바다옷장",
		short = "옷가게",
		icon = "👕",
		kind = "clothes",
		accent = { 61, 214, 245 },
		source = "clothes", -- items = G.CLOTHES (bought through Venues.buy "outfit_<id>")
		sheetTitle = "바다옷장 · 옷 고르기",
		sheetSub = "피팅룸에서 입어 보고 사세요",
		lines = {
			greet = { "어서오세요~ 편하게 구경하세요!", "신상 들어왔어요~ 피팅룸 써 보셔도 돼요", "찾으시는 스타일 있으세요?" },
			fit = { "와~ 잘 어울리세요!", "그 색 진짜 찰떡이에요", "사이즈 딱이네요~" },
			bought = { "감사합니다~ 예쁘게 입으세요!", "오늘 룩 완성이에요~" },
			bye = { "또 오세요~ 다음 주에 신상 들어와요!" },
		},
	},
	salon = {
		awning = "#B85C7A",
		name = "헤어살롱 물결",
		short = "미용실",
		icon = "💇",
		kind = "salon",
		accent = { 255, 79, 163 },
		source = "salon", -- items = G.SALON (bought through Venues.buy "hair_<id>", the SalonChair path)
		sheetTitle = "헤어살롱 물결 · 스타일",
		sheetSub = "의자에 앉아 원하는 스타일을 고르세요",
		lines = {
			greet = { "어서오세요~ 헤어살롱 물결입니다!", "앉으세요~ 오늘 어떤 스타일 해 드릴까요?" },
			cut = { "자 그럼 시작할게요~ 앞머리는 이 정도?", "이 스타일 요즘 진짜 인기 많아요~", "조금만 고개 숙여 주세요~" },
			done = { "짜잔~ 완전 잘 어울리세요!", "거울 보세요~ 분위기 확 살았죠?" },
			bye = { "감사합니다~ 다음에 또 다듬으러 오세요!" },
		},
	},
	pharmacy = {
		awning = "#0B8A3A",
		name = "바다약국",
		short = "약국",
		icon = "💊",
		kind = "goods",
		accent = { 61, 220, 132 },
		menu = { "pharm_drink", "pharm_vitamin", "pharm_patch", "pharm_digest" },
		sheetTitle = "바다약국",
		sheetSub = "피곤할 땐 피로회복제 한 병",
		lines = {
			greet = { "어서오세요~ 어디 불편하세요?", "어서오세요~ 피곤해 보이시네요" },
			sold = { "하루 한 병이면 충분해요~", "식후 30분에 드세요~", "푹 쉬는 게 제일 좋아요~" },
			bye = { "몸조리 잘하세요~" },
		},
	},
	surf = {
		awning = "#0077B6",
		name = "광안 서프 & SUP",
		short = "서핑숍",
		icon = "🏄",
		kind = "goods",
		accent = { 40, 204, 196 },
		menu = { "surf_sup", "surf_board", "surf_sunscreen", "surf_towel" },
		sheetTitle = "광안 서프 & SUP · 렌탈",
		sheetSub = "보드 빌려서 광안리 바다로!",
		lines = {
			greet = { "어서오세요~ 오늘 파도 괜찮아요!", "서핑 처음이세요? SUP부터 추천해요", "보드 렌탈하러 오셨어요?" },
			sold = { "안전하게 타세요~ 해변 안전요원 근처에서!", "선크림 꼭 바르시고요~", "즐거운 서핑 되세요!" },
			bye = { "파도 좋은 날 또 오세요~" },
		},
	},
}
SH.ORDER = { "chicken", "gukbap", "snack", "clothing", "salon", "pharmacy", "surf" }

-- Menu items. kind: meal (eat in / take out), goods (instant), rental (carry prop for a while),
-- venues (delegated to Venues.buy with `venuesItem`, price from G.ITEMS).
-- effect: stats deltas (G.STATS keys: stamina = 체력, happiness = 행복, popularity = 인기도,
-- appearance = 외모지수) + rest = fatigue points removed through the health module (ctx.health.rest);
-- without the health module rest becomes happiness (restFallback). daily = how many times a real
-- day the stat effect applies (buying always works).
SH.MENU = {
	-- 광안 치킨 (prices: Busan 2026)
	chicken_fried = { shop = "chicken", kind = "meal", name = "후라이드 치킨", sub = "치킨무 · 콜라 포함", price = 20000, cook = 15, eat = 9, effect = { stamina = 7, happiness = 5 }, daily = 2, icon = "🍗", prop = "tray_chicken", tint = "fried" },
	chicken_yangnyeom = { shop = "chicken", kind = "meal", name = "양념 치킨", sub = "달콤매콤 · 치킨무 · 콜라", price = 21000, cook = 15, eat = 9, effect = { stamina = 7, happiness = 6 }, daily = 2, icon = "🌶️", prop = "tray_chicken", tint = "yangnyeom" },
	chicken_banban = { shop = "chicken", kind = "meal", name = "반반 치킨", sub = "후라이드 반 + 양념 반", price = 21000, cook = 15, eat = 9, effect = { stamina = 7, happiness = 6, popularity = 0.3 }, daily = 2, icon = "🍗", prop = "tray_chicken", tint = "banban" },
	chicken_half = { shop = "chicken", kind = "meal", name = "1인 순살 세트", sub = "순살 반 마리 · 콜라", price = 12000, cook = 15, eat = 7, effect = { stamina = 4, happiness = 3 }, daily = 3, icon = "🥤", prop = "tray_chicken", tint = "boneless" },
	-- 행복 돼지국밥
	gukbap_pork = { shop = "gukbap", kind = "meal", name = "돼지국밥", sub = "뽀얀 사골 육수 · 공깃밥", price = 9500, cook = 15, eat = 10, effect = { stamina = 8, happiness = 3 }, daily = 2, icon = "🍲", prop = "set_gukbap", tint = "pork" },
	gukbap_sundae = { shop = "gukbap", kind = "meal", name = "순대국밥", sub = "찹쌀순대 듬뿍", price = 10000, cook = 15, eat = 10, effect = { stamina = 8, happiness = 3 }, daily = 2, icon = "🍲", prop = "set_gukbap", tint = "sundae" },
	gukbap_mixed = { shop = "gukbap", kind = "meal", name = "섞어국밥", sub = "고기 + 순대 + 내장", price = 10500, cook = 15, eat = 10, effect = { stamina = 9, happiness = 3 }, daily = 2, icon = "🍲", prop = "set_gukbap", tint = "mixed" },
	gukbap_suyuk = { shop = "gukbap", kind = "meal", name = "수육백반", sub = "수육 한 접시 + 국 + 밥", price = 14000, cook = 15, eat = 11, effect = { stamina = 10, happiness = 4, popularity = 0.3 }, daily = 1, icon = "🥩", prop = "set_gukbap", tint = "suyuk" },
	-- 광안 떡볶이 (분식)
	snack_tteok = { shop = "snack", kind = "meal", name = "떡볶이", sub = "쫄깃한 밀떡 · 보통맛", price = 4500, cook = 8, eat = 7, effect = { stamina = 3, happiness = 3 }, daily = 3, icon = "🌶️", prop = "plate_snack", tint = "tteok" },
	snack_gimbap = { shop = "snack", kind = "meal", name = "광안 김밥", sub = "참기름 듬뿍 한 줄", price = 3500, cook = 8, eat = 6, effect = { stamina = 3, happiness = 1 }, daily = 3, icon = "🍙", prop = "plate_snack", tint = "gimbap" },
	snack_eomuk = { shop = "snack", kind = "meal", name = "부산 어묵 2꼬치", sub = "뜨끈한 국물 셀프", price = 2000, cook = 8, eat = 5, effect = { stamina = 2, happiness = 1 }, daily = 4, icon = "🍢", prop = "plate_snack", tint = "eomuk" },
	snack_twigim = { shop = "snack", kind = "meal", name = "모둠 튀김", sub = "오징어 · 고구마 · 김말이", price = 5000, cook = 8, eat = 6, effect = { stamina = 3, happiness = 2 }, daily = 3, icon = "🍤", prop = "plate_snack", tint = "twigim" },
	snack_set = { shop = "snack", kind = "meal", name = "떡튀순 세트", sub = "떡볶이 + 튀김 + 순대", price = 9000, cook = 10, eat = 8, effect = { stamina = 6, happiness = 4, popularity = 0.2 }, daily = 2, icon = "🥢", prop = "plate_snack", tint = "set" },
	-- 바다약국
	pharm_drink = { shop = "pharmacy", kind = "goods", name = "피로회복제", sub = "갈색 병 드링크 한 병", price = 1000, effect = { rest = 10 }, restFallback = 2, daily = 3, icon = "🧃", prop = "bottle_drink" },
	pharm_vitamin = { shop = "pharmacy", kind = "goods", name = "종합비타민 (30일)", sub = "하루 한 알 · 피로 확 풀림", price = 15000, effect = { rest = 25, happiness = 1 }, restFallback = 4, daily = 1, icon = "💊", prop = "bottle_pills" },
	pharm_patch = { shop = "pharmacy", kind = "goods", name = "근육 파스", sub = "어깨 · 다리 뭉쳤을 때", price = 4000, effect = { stamina = 4 }, daily = 2, icon = "🩹" },
	pharm_digest = { shop = "pharmacy", kind = "goods", name = "소화제 드링크", sub = "국밥 · 치킨 먹고 한 병", price = 2500, effect = { stamina = 1, happiness = 1, rest = 3 }, restFallback = 1, daily = 2, icon = "🥤", prop = "bottle_drink" },
	-- 광안 서프 & SUP
	surf_sup = { shop = "surf", kind = "venues", venuesItem = "sup_rental", name = "SUP 패들보드 대여 (10분)", sub = "광안리 SUP존에서 탈 수 있어요", icon = "🛶" },
	surf_board = { shop = "surf", kind = "rental", name = "서프보드 대여 (10분)", sub = "보드 들고 해변으로! 행복 +3", price = 15000, effect = { happiness = 3 }, daily = 2, icon = "🏄", prop = "board_surf", seconds = 600 },
	surf_sunscreen = { shop = "surf", kind = "goods", name = "워터프루프 선크림", sub = "SPF50+ · 바다 필수템", price = 6000, effect = { happiness = 1, appearance = 0.3 }, daily = 1, icon = "🧴" },
	surf_towel = { shop = "surf", kind = "goods", name = "광안리 비치타월", sub = "광안대교 프린트 한정판", price = 9000, effect = { happiness = 2, popularity = 0.2 }, daily = 1, icon = "🏖️", prop = "towel" },
}

SH.MODE_LABEL = { here = "매장에서 먹기", togo = "포장하기" }

SH.STAT_LABEL = {
	stamina = "체력",
	happiness = "행복",
	popularity = "인기도",
	appearance = "외모지수",
	strength = "근력",
	rest = "피로",
}
SH.STAT_ORDER = { "rest", "stamina", "happiness", "popularity", "appearance", "strength" }

local function fmtNum(v: number): string
	if math.abs(v - math.floor(v)) < 0.05 then
		return tostring(math.floor(v + 0.5))
	end
	return string.format("%.1f", v)
end

-- "체력 +7 · 행복 +5" (rest shows as "피로 -10")
function SH.effectText(effect: any?): string
	if type(effect) ~= "table" then
		return ""
	end
	local parts = {}
	for _, k in SH.STAT_ORDER do
		local v = effect[k]
		if type(v) == "number" and v ~= 0 then
			if k == "rest" then
				table.insert(parts, "피로 -" .. fmtNum(v))
			else
				table.insert(parts, string.format("%s %s%s", SH.STAT_LABEL[k] or k, if v > 0 then "+" else "-", fmtNum(math.abs(v))))
			end
		end
	end
	return table.concat(parts, " · ")
end

-- "20,000원"
function SH.won(n: any): string
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(v))
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return (if v < 0 then "-" else "") .. s .. out .. "원"
end

-- Menu ids of a shop (food / goods shops).
function SH.menuOf(shopId: string): { string }
	local s = SH.SHOPS[shopId]
	return (s and s.menu) or {}
end

-- Deterministic pick from a staff line list (seed: any number).
function SH.line(shopId: string, key: string, seed: number?): string?
	local s = SH.SHOPS[shopId]
	local list = s and s.lines and s.lines[key]
	if not list or #list == 0 then
		return nil
	end
	local i = (math.floor(math.abs(seed or 0)) % #list) + 1
	return list[i]
end

-- Validation (called by the server at start; returns problems).
function SH.validate(): { string }
	local out = {}
	for id, m in SH.MENU do
		if not SH.SHOPS[m.shop] then
			table.insert(out, "menu " .. id .. ": unknown shop " .. tostring(m.shop))
		end
		if m.kind ~= "venues" and (type(m.price) ~= "number" or m.price < 0) then
			table.insert(out, "menu " .. id .. ": bad price")
		end
	end
	for id, s in SH.SHOPS do
		for _, mid in s.menu or {} do
			if not SH.MENU[mid] then
				table.insert(out, "shop " .. id .. ": missing menu item " .. mid)
			end
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Runtime props (server: trays on tables, bags in hands; client: local bites, customer props).
-- Every part: Anchored (unless welded by the caller), CanCollide / CanTouch / CanQuery false,
-- CastShadow false, Massless. Parts named "Food" are eaten one by one (Shops.luau removes them).
-------------------------------------------------------------------------------------------------
local function rgb(t: { number }): any
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function part(parent: Instance, name: string, size: any, cf: any, color: { number }, mat: string?, shape: string?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = rgb(color)
	p.Material = (Enum.Material :: any)[mat or "SmoothPlastic"]
	if shape == "cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "egg" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Parent = parent
	return p
end
SH.part = part

-- vertical cylinder centred at cf (height h, diameter d)
local function vcyl(parent: Instance, name: string, h: number, d: number, cf: any, color: { number }, mat: string?): BasePart
	return part(parent, name, Vector3.new(h, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, mat, "cyl")
end

local FRY = { { 196, 128, 48 }, { 208, 142, 58 }, { 186, 116, 40 } }
local YANG = { { 168, 42, 28 }, { 150, 36, 24 }, { 182, 56, 34 } }

-- chicken pieces on a liner (6 drumsticks / wings), radish cubes, cola, sauce
local function trayChicken(m: Model, cf: any, tint: string?)
	part(m, "Tray", Vector3.new(2.6, 0.12, 1.9), cf * CFrame.new(0, 0.06, 0), { 200, 30, 36 }, "SmoothPlastic")
	part(m, "Liner", Vector3.new(1.7, 0.04, 1.5), cf * CFrame.new(-0.35, 0.14, 0), { 236, 226, 200 }, "Fabric")
	local pieces = {
		{ -0.8, -0.35, 20 }, { -0.35, -0.42, -30 }, { 0.05, -0.3, 60 }, { -0.75, 0.25, -60 }, { -0.3, 0.32, 10 }, { 0.08, 0.22, 85 },
	}
	for i, pc in pieces do
		local col: { number }
		if tint == "yangnyeom" then
			col = YANG[(i % #YANG) + 1]
		elseif tint == "banban" then
			col = if i <= 3 then FRY[(i % #FRY) + 1] else YANG[(i % #YANG) + 1]
		else
			col = FRY[(i % #FRY) + 1]
		end
		local p = part(m, "Food", Vector3.new(0.62, 0.36, 0.42), cf * CFrame.new(pc[1], 0.32, pc[2]) * CFrame.Angles(0, math.rad(pc[3]), math.rad(8)), col, "Sand", "egg")
		p:SetAttribute("Bite", i)
	end
	-- 치킨무 (pickled radish) dish + cola + sauce dish + wet wipe
	part(m, "RadishDish", Vector3.new(0.6, 0.1, 0.5), cf * CFrame.new(0.82, 0.17, -0.45), { 240, 240, 236 }, "SmoothPlastic")
	for k = 0, 3 do
		part(m, "Radish", Vector3.new(0.16, 0.16, 0.16), cf * CFrame.new(0.72 + (k % 2) * 0.2, 0.3, -0.5 + math.floor(k / 2) * 0.18), { 250, 250, 236 }, "SmoothPlastic")
	end
	vcyl(m, "Cola", 1.0, 0.36, cf * CFrame.new(0.85, 0.62, 0.35), { 40, 20, 14 }, "Glass")
	vcyl(m, "ColaLabel", 0.3, 0.38, cf * CFrame.new(0.85, 0.55, 0.35), { 210, 26, 32 }, "SmoothPlastic")
	vcyl(m, "ColaCap", 0.08, 0.2, cf * CFrame.new(0.85, 1.16, 0.35), { 210, 26, 32 }, "SmoothPlastic")
	vcyl(m, "Cup", 0.5, 0.3, cf * CFrame.new(0.42, 0.38, 0.55), { 250, 250, 250 }, "SmoothPlastic")
	part(m, "WetWipe", Vector3.new(0.4, 0.04, 0.25), cf * CFrame.new(0.95, 0.14, -0.05), { 250, 250, 250 }, "SmoothPlastic")
end

-- 뚝배기 + rice bowl + side dishes (kimchi, 깍두기, 부추, 새우젓, onion), spoon / chopsticks
local function setGukbap(m: Model, cf: any, tint: string?)
	part(m, "Tray", Vector3.new(2.8, 0.1, 1.9), cf * CFrame.new(0, 0.05, 0), { 132, 92, 56 }, "WoodPlanks")
	vcyl(m, "Ttukbaegi", 0.6, 1.0, cf * CFrame.new(-0.55, 0.4, 0.1), { 54, 38, 30 }, "Slate")
	local broth = if tint == "sundae" or tint == "mixed" then { 222, 206, 180 } else { 238, 230, 210 }
	local b = vcyl(m, "Food", 0.06, 0.86, cf * CFrame.new(-0.55, 0.69, 0.1), broth, "SmoothPlastic")
	b:SetAttribute("Bite", 6)
	for i = 1, 3 do
		local col = if tint == "sundae" and i == 2 then { 70, 40, 44 } else { 226, 182, 170 }
		local p = part(m, "Food", Vector3.new(0.36, 0.06, 0.2), cf * CFrame.new(-0.7 + (i - 1) * 0.16, 0.74, 0.0 + (i % 2) * 0.18) * CFrame.Angles(0, math.rad(i * 37), 0), col, "SmoothPlastic")
		p:SetAttribute("Bite", i)
	end
	part(m, "Food", Vector3.new(0.3, 0.04, 0.3), cf * CFrame.new(-0.45, 0.75, 0.28), { 70, 150, 60 }, "Grass"):SetAttribute("Bite", 4)
	vcyl(m, "RiceBowl", 0.34, 0.56, cf * CFrame.new(0.42, 0.27, 0.45), { 210, 212, 216 }, "Metal")
	part(m, "Food", Vector3.new(0.5, 0.16, 0.5), cf * CFrame.new(0.42, 0.48, 0.45), { 250, 250, 246 }, "SmoothPlastic", "egg"):SetAttribute("Bite", 5)
	if tint == "suyuk" then
		part(m, "SuyukPlate", Vector3.new(1.0, 0.06, 0.6), cf * CFrame.new(0.55, 0.13, -0.35), { 240, 240, 236 }, "SmoothPlastic")
		for i = 0, 4 do
			part(m, "Food", Vector3.new(0.16, 0.12, 0.42), cf * CFrame.new(0.25 + i * 0.15, 0.22, -0.35) * CFrame.Angles(0, 0, math.rad(-12)), { 214, 170, 150 }, "SmoothPlastic"):SetAttribute("Bite", 7 + i)
		end
	else
		local dishes = { { 0.15, -0.5, { 196, 46, 30 } }, { 0.55, -0.5, { 214, 120, 60 } }, { 0.95, -0.45, { 90, 160, 70 } }, { 1.0, 0.0, { 236, 200, 190 } } }
		for _, dd in dishes do
			vcyl(m, "SideDish", 0.08, 0.36, cf * CFrame.new(dd[1], 0.14, dd[2]), { 236, 236, 232 }, "SmoothPlastic")
			part(m, "Banchan", Vector3.new(0.24, 0.08, 0.22), cf * CFrame.new(dd[1], 0.22, dd[2]), dd[3], "SmoothPlastic")
		end
	end
	part(m, "Spoon", Vector3.new(0.08, 0.03, 0.9), cf * CFrame.new(1.25, 0.12, 0.4), { 206, 208, 212 }, "Metal")
	part(m, "Chopsticks", Vector3.new(0.06, 0.03, 0.95), cf * CFrame.new(1.15, 0.12, 0.4), { 206, 208, 212 }, "Metal")
end

-- 분식 plate: tteokbokki / gimbap / eomuk / twigim / set on a green melamine plate
local function plateSnack(m: Model, cf: any, tint: string?)
	part(m, "Plate", Vector3.new(1.9, 0.08, 1.3), cf * CFrame.new(0, 0.04, 0), { 60, 150, 92 }, "SmoothPlastic", "egg")
	local bite = 0
	local function food(size: any, off: any, col: { number }, shape: string?)
		bite += 1
		local p = part(m, "Food", size, cf * off, col, "SmoothPlastic", shape)
		p:SetAttribute("Bite", bite)
		return p
	end
	if tint == "tteok" or tint == "set" then
		part(m, "Sauce", Vector3.new(1.3, 0.06, 0.9), cf * CFrame.new(-0.1, 0.1, 0), { 196, 40, 26 }, "SmoothPlastic", "egg")
		for i = 0, 5 do
			food(Vector3.new(0.44, 0.15, 0.15), CFrame.new(-0.5 + (i % 3) * 0.32, 0.18, -0.2 + math.floor(i / 3) * 0.3) * CFrame.Angles(0, math.rad(i * 29), math.pi / 2), { 218, 72, 50 }, "cyl")
		end
		food(Vector3.new(0.5, 0.05, 0.3), CFrame.new(0.2, 0.17, 0.25) * CFrame.Angles(0, 0.6, 0), { 220, 170, 110 })
	end
	if tint == "gimbap" then
		for i = 0, 7 do
			local c = cf * CFrame.new(-0.7 + i * 0.2, 0.2, 0)
			local p = part(m, "Food", Vector3.new(0.16, 0.34, 0.34), c, { 30, 34, 30 }, "SmoothPlastic", "cyl")
			bite += 1
			p:SetAttribute("Bite", bite)
			-- rice ring + filling (eaten together with the roll: same Bite)
			local r = part(m, "Food", Vector3.new(0.17, 0.26, 0.26), c, { 248, 248, 244 }, "SmoothPlastic", "cyl")
			r:SetAttribute("Bite", bite)
		end
	end
	if tint == "eomuk" then
		for i = 0, 1 do
			food(Vector3.new(0.22, 0.6, 0.5), CFrame.new(-0.35 + i * 0.6, 0.24, 0) * CFrame.Angles(0, 0, 0.2), { 214, 168, 112 })
			part(m, "Skewer", Vector3.new(0.05, 1.3, 0.05), cf * CFrame.new(-0.35 + i * 0.6, 0.55, 0) * CFrame.Angles(0, 0, 0.2), { 222, 196, 150 }, "Wood")
		end
		vcyl(m, "BrothCup", 0.5, 0.42, cf * CFrame.new(0.65, 0.3, 0.35), { 250, 250, 250 }, "SmoothPlastic")
	end
	if tint == "twigim" or tint == "set" then
		for i = 0, 3 do
			food(Vector3.new(0.5, 0.22, 0.3), CFrame.new(-0.5 + i * 0.34, 0.2, if tint == "set" then -0.42 else 0) * CFrame.Angles(0, math.rad(i * 41), 0), { 214, 160, 70 }, "egg")
		end
	end
	if tint == "set" then
		for i = 0, 3 do
			food(Vector3.new(0.18, 0.2, 0.2), CFrame.new(0.5 + (i % 2) * 0.22, 0.17, 0.25 + math.floor(i / 2) * 0.2), { 60, 40, 44 }, "cyl")
		end
	end
	part(m, "Fork", Vector3.new(0.05, 0.03, 0.7), cf * CFrame.new(0.95, 0.1, 0.1), { 220, 220, 224 }, "Metal")
end

-- Build a prop model at cf (cf = the surface centre it rests on, LookVector = toward the eater).
function SH.prop(kind: string, cf: any, tint: string?, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = "ShopProp_" .. kind
	if kind == "tray_chicken" then
		trayChicken(m, cf, tint)
	elseif kind == "set_gukbap" then
		setGukbap(m, cf, tint)
	elseif kind == "plate_snack" then
		plateSnack(m, cf, tint)
	elseif kind == "bag_togo" then
		part(m, "Bag", Vector3.new(1.1, 1.2, 0.7), cf * CFrame.new(0, 0.6, 0), { 196, 160, 112 }, "Cardboard")
		part(m, "BagTop", Vector3.new(1.12, 0.1, 0.72), cf * CFrame.new(0, 1.22, 0), { 176, 140, 96 }, "Cardboard")
		part(m, "Handle", Vector3.new(0.6, 0.5, 0.06), cf * CFrame.new(0, 1.5, 0), { 160, 124, 84 }, "Fabric")
		part(m, "Sticker", Vector3.new(0.5, 0.4, 0.02), cf * CFrame.new(0, 0.7, -0.36), { 232, 64, 52 }, "SmoothPlastic")
	elseif kind == "bottle_drink" then
		vcyl(m, "Bottle", 0.55, 0.22, cf * CFrame.new(0, 0.28, 0), { 110, 56, 20 }, "Glass")
		vcyl(m, "Label", 0.22, 0.23, cf * CFrame.new(0, 0.24, 0), { 250, 210, 60 }, "SmoothPlastic")
		vcyl(m, "Cap", 0.08, 0.16, cf * CFrame.new(0, 0.59, 0), { 220, 196, 60 }, "Metal")
	elseif kind == "bottle_pills" then
		vcyl(m, "Bottle", 0.5, 0.34, cf * CFrame.new(0, 0.25, 0), { 250, 250, 250 }, "SmoothPlastic")
		vcyl(m, "Label", 0.26, 0.35, cf * CFrame.new(0, 0.24, 0), { 240, 140, 40 }, "SmoothPlastic")
		vcyl(m, "Cap", 0.12, 0.3, cf * CFrame.new(0, 0.56, 0), { 240, 140, 40 }, "SmoothPlastic")
	elseif kind == "board_surf" then
		part(m, "Board", Vector3.new(0.18, 6.4, 1.7), cf, { 250, 250, 246 }, "SmoothPlastic", "egg")
		part(m, "Stripe", Vector3.new(0.2, 5.6, 0.25), cf, { 40, 204, 196 }, "SmoothPlastic")
		part(m, "Fin", Vector3.new(0.08, 0.5, 0.35), cf * CFrame.new(0.15, -2.6, 0), { 30, 30, 34 }, "SmoothPlastic")
	elseif kind == "towel" then
		part(m, "Towel", Vector3.new(1.1, 0.5, 0.6), cf * CFrame.new(0, 0.25, 0), { 61, 160, 230 }, "Fabric")
		part(m, "Stripe", Vector3.new(1.12, 0.12, 0.62), cf * CFrame.new(0, 0.3, 0), { 250, 250, 250 }, "Fabric")
	elseif kind == "bite_chicken" then
		part(m, "Food", Vector3.new(0.5, 0.3, 0.34), cf, FRY[1], "Sand", "egg")
	elseif kind == "bite_spoon" then
		part(m, "Spoon", Vector3.new(0.06, 0.03, 0.7), cf, { 206, 208, 212 }, "Metal")
		part(m, "Food", Vector3.new(0.18, 0.08, 0.22), cf * CFrame.new(0, 0.04, -0.28), { 240, 236, 226 }, "SmoothPlastic")
	elseif kind == "bite_skewer" then
		part(m, "Skewer", Vector3.new(0.05, 0.05, 0.9), cf, { 222, 196, 150 }, "Wood")
		part(m, "Food", Vector3.new(0.2, 0.2, 0.42), cf * CFrame.new(0, 0, -0.2), { 218, 72, 50 }, "SmoothPlastic", "cyl")
	end
	if parent then
		m.Parent = parent
	end
	return m
end

-- Which hand-held bite the local eater shows for a meal prop.
SH.BITE_FOR = { tray_chicken = "bite_chicken", set_gukbap = "bite_spoon", plate_snack = "bite_skewer" }

-- Where a carried prop sits: hand = "right" (R15 RightHand / R6 Right Arm) or "back" (UpperTorso /
-- Torso). offset = CFrame relative to that part.
SH.CARRY = {
	bag_togo = { hand = "right", offset = CFrame and CFrame.new(0, -1.35, 0) or nil },
	bottle_drink = { hand = "right", offset = CFrame and CFrame.new(0, -0.45, -0.1) or nil },
	bottle_pills = { hand = "right", offset = CFrame and CFrame.new(0, -0.45, -0.1) or nil },
	towel = { hand = "right", offset = CFrame and CFrame.new(0, -0.6, 0) or nil },
	board_surf = { hand = "back", offset = CFrame and (CFrame.new(0, 0, 0.75) * CFrame.Angles(0, math.pi / 2, math.rad(10))) or nil },
}

return SH
