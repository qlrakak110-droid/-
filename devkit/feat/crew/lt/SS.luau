-- ModuleScript @ ReplicatedStorage.GwangalliBuildingsShared.StreetShops
-- StreetShops: data of the SHOP LIFE layer — every walk-in shop of the 광안리 map used like a real one.
--
-- The map (Workspace.Gwangalli) already has ~120 ground-floor shops with automatic doors and fitted
-- interiors (tables, chairs, counters, POS, kiosks, espresso machines, fish tanks, grill tables, beer
-- taps, fridges, gondolas, restroom doors ...), plus the seven GwShop shops (행복 돼지국밥 · 광안 치킨 ·
-- 광안 떡볶이 · 바다약국 · 바다옷장 · 헤어살롱 물결 · 광안 서프 & SUP) and the GS25 venue. Their outside
-- and their inside stay exactly as built; the shop-life server only ADDS invisible anchors with
-- proximity prompts, small props (dishes, cups, trays, a water purifier, a trash bin) and the flows.
--
-- This module: shop TYPES (how a visit goes), RULES (shop name / sign keywords -> type + menu),
-- MENUS (items, prices = 부산 2026, dish model, how it is eaten, how it is cooked, effects), staff
-- LINES (shown as the shop's voice; NPC behaviour belongs to the NPC system), helpers.
-- Pure data + pure functions (no instances, no services) — safe on server and client.

local SS = {}
SS.VERSION = 1

-------------------------------------------------------------------------------------------------
-- Shop types
--   flow   table   sit -> order at the table (paper menu / menu board) -> served to the table -> eat
--                  -> 추가 주문 -> pay at the counter on the way out (후불)
--          kiosk   kiosk / counter order (선불, 매장 / 포장) -> made at the machine -> 진동벨 / number
--                  -> pick up -> table or take out
--          counter order at the counter (선불) -> served on a plate / in the hand
--          pick    take goods from shelves into a basket -> POS checkout -> bag
--          service a desk service (약국 상담, 세탁 맡기기, 부동산, 호텔 프런트, 우편함)
--   ui     board (메뉴판) | paper (테이블 메뉴지) | kiosk | tank (수조) | tap (탭 음료) | window (디저트 쇼케이스)
--          | pick (진열대) | consult | desk
--   water  self water purifier (물 셀프) · trash: a bin is added when the shop has none
-------------------------------------------------------------------------------------------------
SS.TYPES = {
	soup = { label = "국밥 · 탕", icon = "🍲", flow = "table", ui = "board", pay = "post", water = true, banchan = "korean", accent = { 236, 120, 72 } },
	noodle = { label = "면 요리", icon = "🍜", flow = "table", ui = "board", pay = "post", water = true, banchan = "noodle", accent = { 240, 190, 90 } },
	katsu = { label = "돈카츠", icon = "🍛", flow = "table", ui = "board", pay = "post", water = true, banchan = "katsu", accent = { 230, 160, 70 } },
	grill = { label = "구이", icon = "🔥", flow = "table", ui = "paper", pay = "post", water = true, banchan = "grill", grill = true, accent = { 255, 120, 60 } },
	rawfish = { label = "횟집", icon = "🐟", flow = "table", ui = "tank", pay = "post", water = true, banchan = "hoe", accent = { 80, 180, 230 } },
	seafood = { label = "해산물", icon = "🦀", flow = "table", ui = "paper", pay = "post", water = true, banchan = "hoe", accent = { 230, 90, 70 } },
	pocha = { label = "포차", icon = "🏮", flow = "table", ui = "paper", pay = "post", water = true, banchan = "pocha", accent = { 255, 90, 70 } },
	pub = { label = "펍 · 바", icon = "🍹", flow = "table", ui = "tap", pay = "post", accent = { 255, 190, 60 } },
	chicken = { label = "치킨", icon = "🍗", flow = "table", ui = "board", pay = "post", water = true, banchan = "chicken", accent = { 255, 176, 32 } },
	snack = { label = "분식", icon = "🍢", flow = "counter", ui = "board", pay = "pre", water = true, accent = { 232, 64, 52 } },
	cafe = { label = "카페", icon = "☕", flow = "kiosk", ui = "kiosk", pay = "pre", accent = { 150, 100, 70 } },
	burger = { label = "버거 · 샌드위치", icon = "🍔", flow = "kiosk", ui = "kiosk", pay = "pre", accent = { 250, 160, 40 } },
	dessert = { label = "디저트", icon = "🍨", flow = "counter", ui = "window", pay = "pre", accent = { 255, 140, 190 } },
	bakery = { label = "베이커리", icon = "🥐", flow = "pick", ui = "pick", pay = "pre", accent = { 220, 160, 90 } },
	cvs = { label = "편의점", icon = "🏪", flow = "pick", ui = "pick", pay = "pre", accent = { 60, 170, 230 } },
	retail = { label = "상점", icon = "🛍️", flow = "pick", ui = "pick", pay = "pre", accent = { 120, 200, 140 } },
	pharmacy = { label = "약국", icon = "💊", flow = "service", ui = "consult", pay = "pre", accent = { 61, 220, 132 } },
	laundry = { label = "세탁소", icon = "👔", flow = "service", ui = "desk", pay = "pre", accent = { 120, 170, 240 } },
	realty = { label = "부동산", icon = "🏠", flow = "service", ui = "desk", pay = "pre", accent = { 90, 160, 255 } },
	lobby = { label = "호텔 로비", icon = "🛎️", flow = "service", ui = "desk", pay = "pre", accent = { 200, 170, 100 } },
	residence = { label = "건물 로비", icon = "🏢", flow = "service", ui = "desk", pay = "pre", accent = { 150, 160, 180 } },
	salon = { label = "미용실", icon = "💇", flow = "service", ui = "desk", pay = "pre", accent = { 255, 79, 163 } },
	-- add new types BELOW (append only; ids are saved / used by other systems)
	-- (Annex: the shops behind facade-only storefronts)
	chinese = { label = "중식", icon = "🥢", flow = "table", ui = "board", pay = "post", water = true, banchan = "chinese", accent = { 220, 40, 40 } },
	clinic = { label = "병원 · 의원", icon = "🏥", flow = "service", ui = "consult", pay = "pre", accent = { 70, 170, 230 }, staff = "의사 선생님" },
	academy = { label = "학원 · 교실", icon = "📚", flow = "service", ui = "desk", pay = "pre", accent = { 250, 180, 60 }, staff = "선생님" },
	gym = { label = "운동", icon = "💪", flow = "service", ui = "desk", pay = "pre", accent = { 250, 90, 60 }, staff = "코치" },
	bank = { label = "은행", icon = "🏦", flow = "service", ui = "desk", pay = "pre", accent = { 40, 110, 200 }, staff = "창구 직원" },
	office = { label = "사무실 · 공공기관", icon = "🏢", flow = "service", ui = "desk", pay = "pre", accent = { 150, 160, 180 }, staff = "담당자" },
	play = { label = "놀거리", icon = "🎲", flow = "service", ui = "desk", pay = "pre", accent = { 180, 100, 250 }, staff = "직원" },
}

-- default menu of a type (when a shop forces ShopLifeType without ShopLifeMenu)
SS.TYPE_MENU = {
	soup = "gukbap",
	noodle = "milmyeon",
	katsu = "katsu",
	grill = "bbq",
	rawfish = "hoe",
	seafood = "jjim",
	pocha = "pocha",
	pub = "pub",
	chicken = "chicken",
	snack = "snack",
	cafe = "cafe",
	burger = "burger",
	dessert = "gelato",
	bakery = "bakery",
	cvs = "cvs",
	retail = "souvenir",
	pharmacy = "pharmacy",
	laundry = "laundry",
	realty = "realty",
	lobby = "lobby",
	residence = "residence",
	salon = "salon",
	chinese = "chinese",
	clinic = "clinic",
	academy = "math",
	gym = "gym",
	bank = "bank",
	office = "office",
	play = "boardgame",
}

-- 셀프 반찬 / 기본 상차림 per type (shown on the table the moment you order)
SS.BANCHAN = {
	korean = { { "김치", { 196, 46, 30 } }, { "깍두기", { 214, 120, 60 } }, { "부추무침", { 90, 160, 70 } }, { "새우젓", { 236, 200, 190 } } },
	noodle = { { "김치", { 196, 46, 30 } }, { "단무지", { 250, 220, 80 } } },
	katsu = { { "양배추 샐러드", { 200, 230, 160 } }, { "단무지", { 250, 220, 80 } } },
	grill = { { "쌈채소", { 70, 150, 60 } }, { "쌈장", { 150, 90, 50 } }, { "파절이", { 120, 170, 80 } }, { "콘치즈", { 250, 210, 90 } } },
	hoe = { { "초장", { 200, 40, 30 } }, { "상추 · 깻잎", { 70, 150, 60 } }, { "마늘 · 고추", { 230, 230, 210 } }, { "미역국", { 70, 90, 50 } } },
	pocha = { { "뻥튀기", { 240, 230, 200 } }, { "콘치즈", { 250, 210, 90 } } },
	chicken = { { "치킨무", { 250, 250, 236 } }, { "양배추 샐러드", { 200, 230, 160 } } },
	chinese = { { "단무지", { 250, 220, 80 } }, { "양파 · 춘장", { 60, 40, 30 } } },
}

-------------------------------------------------------------------------------------------------
-- Rules: shop model name / sign text -> type + menu (first match wins). exact = the whole name.
-- When nothing matches, the contents decide (SS.CONTENT_RULES on the scanned prop counts).
-------------------------------------------------------------------------------------------------
SS.RULES = {
	{ "해장국", "soup", "haejang" },
	{ "돼지국밥", "soup", "gukbap" },
	{ "국밥", "soup", "gukbap" },
	{ "복국", "soup", "bok" },
	{ "밀면", "noodle", "milmyeon" },
	{ "칼국수", "noodle", "kalguksu" },
	{ "라멘", "noodle", "ramen" },
	{ "돈카츠", "katsu", "katsu" },
	{ "조개구이", "grill", "clam" },
	{ "곱창", "grill", "gopchang" },
	{ "조개찜", "seafood", "jjim" },
	{ "대게", "seafood", "crab" },
	{ "오징어", "seafood", "ojingeo" },
	{ "횟집", "rawfish", "hoe" },
	{ "수산", "rawfish", "hoe" },
	{ "초장집", "rawfish", "hoe" },
	{ "회 한", "rawfish", "hoe" },
	{ "스시", "rawfish", "sushi" },
	{ "포장마차", "pocha", "pocha" },
	{ "포차", "pocha", "pocha" },
	{ "새벽집", "pocha", "pocha" },
	{ "탭하우스", "pub", "craft" },
	{ "TAPROOM", "pub", "craft" },
	{ "WILD WAVE", "pub", "craft" },
	{ "HAPPY MONK", "pub", "craft" },
	{ "크래프트 비어", "pub", "craft" },
	{ "FUZZY NAVEL", "pub", "cocktail" },
	{ "THURSDAY PARTY", "pub", "party" },
	{ "SUNSET", "pub", "pub" },
	{ "PUB", "pub", "pub" },
	{ "BEER", "pub", "pub" },
	{ "비어", "pub", "pub" },
	{ "MAD DOGS", "pub", "pub" },
	{ "WORKING HOLIDAY", "pub", "pub" },
	{ "치킨", "chicken", "chicken" },
	{ "통닭", "chicken", "tongdak" },
	{ "떡볶이", "snack", "snack" },
	{ "분식", "snack", "snack" },
	{ "어묵", "snack", "odeng" },
	{ "오뎅", "snack", "odeng" },
	{ "SUBWAY", "burger", "sub" },
	{ "SUB OF THE", "burger", "sub" },
	{ "타코", "burger", "taco" },
	{ "버거", "burger", "burger" },
	{ "BINGBING", "dessert", "bingsu" },
	{ "탕후루", "dessert", "tanghulu" },
	{ "츄러스", "dessert", "churros" },
	{ "와플", "dessert", "waffle" },
	{ "젤라또", "dessert", "gelato" },
	{ "GELATO", "dessert", "gelato" },
	{ "호떡", "dessert", "hotteok" },
	{ "베이커리", "bakery", "bakery" },
	{ "BAKERY", "bakery", "bakery" },
	{ "로스터리", "cafe", "roastery" },
	{ "TWOSOME", "cafe", "dessertcafe" },
	{ "STARBUCKS", "cafe", "cafe" },
	{ "PASCUCCI", "cafe", "cafe" },
	{ "COFFEE", "cafe", "cafe" },
	{ "커피", "cafe", "cafe" },
	{ "CAFE", "cafe", "cafe" },
	{ "카페", "cafe", "cafe" },
	{ "라운지", "cafe", "cafe" },
	{ "ESPRESSO", "cafe", "cafe" },
	{ "GS25", "cvs", "cvs" },
	{ "CU", "cvs", "cvs", exact = true },
	{ "7-ELEVEn", "cvs", "cvs" },
	{ "emart24", "cvs", "cvs" },
	{ "슈퍼", "cvs", "cvs" },
	{ "편의점", "cvs", "cvs" },
	{ "OLIVE YOUNG", "retail", "cosmetics" },
	{ "기념품", "retail", "souvenir" },
	{ "I AM BUSAN", "retail", "souvenir" },
	{ "GOODS", "retail", "souvenir" },
	{ "POP-UP", "retail", "souvenir" },
	{ "비치용품", "retail", "beach" },
	{ "튜브", "retail", "beach" },
	{ "돗자리", "retail", "beach" },
	{ "플라워", "retail", "flower" },
	{ "오션북스", "retail", "books" },
	{ "보틀샵", "retail", "bottle" },
	{ "VINTAGE", "retail", "vintage" },
	{ "약국", "pharmacy", "pharmacy" },
	{ "세탁", "laundry", "laundry" },
	{ "공인중개사", "realty", "realty" },
	{ "부동산", "realty", "realty" },
	{ "HOTEL", "lobby", "lobby" },
	{ "호텔", "lobby", "lobby" },
	{ "MOTEL", "lobby", "lobby" },
	{ "OCEAN STAY", "lobby", "lobby" },
	{ "맨션", "residence", "residence" },
	{ "RESIDENCE", "residence", "residence" },
	{ "TOWER", "residence", "residence" },
	{ "A-PARK", "residence", "residence" },
	{ "JIWELL", "residence", "residence" },
	{ "CITY NINE", "residence", "residence" },
	{ "TERRASTAR", "residence", "residence" },
	{ "BEACH STUDIO", "residence", "residence" },
}

-- contents -> type (scanned prop names; first rule whose prop is present wins)
SS.CONTENT_RULES = {
	{ "TapPost", "pub", "pub" },
	{ "TankWater", "rawfish", "hoe" },
	{ "GrillTable", "grill", "clam" },
	{ "CharcoalPot", "grill", "bbq" },
	{ "EspressoBody", "cafe", "cafe" },
	{ "Gondola", "cvs", "cvs" },
	{ "IceCreamChest", "cvs", "cvs" },
	{ "PastryCase", "bakery", "bakery" },
	{ "BreadShelf", "bakery", "bakery" },
	{ "BreadCabinet", "bakery", "bakery" },
	{ "GelatoTub", "dessert", "gelato" },
	{ "WaffleIron", "dessert", "waffle" },
	{ "OrderKiosk", "burger", "burger" },
	{ "Tester", "retail", "cosmetics" },
	{ "WallRack", "retail", "souvenir" },
	{ "DisplayTable", "retail", "souvenir" },
	{ "FrontDesk", "lobby", "lobby" },
	{ "Mailboxes", "residence", "residence" },
	{ "WorkDesk", "realty", "realty" },
	{ "KitchenPass", "soup", "gukbap" },
	{ "Noren", "noodle", "ramen" },
}

-- the GwShop shops of the map (ShopId attribute) -> type + menu
SS.GWSHOP = {
	gukbap = { "soup", "gw_gukbap" },
	chicken = { "chicken", "gw_chicken" },
	snack = { "snack", "gw_snack" },
	pharmacy = { "pharmacy", "gw_pharmacy" },
	surf = { "retail", "gw_surf" },
	clothing = { "retail", "gw_clothing" },
	salon = { "salon", "salon" },
}

-------------------------------------------------------------------------------------------------
-- Menus. Item fields:
--   id, name, price (원), desc, icon
--   dish   FoodKit builder id (+ tint)        cat  main | side | drink | alcohol | dessert | goods
--   eat    spoon | chop | slurp | fork | hand | sip | gulp | shot | lick | stick | none
--   bites  how many bites / sips              cook seconds in the kitchen (0 = instant)
--   fx     how it is made: boil | fry | grill | espresso | pour | tap | chop | scoop | steam | blend
--          | microwave | bake | press | shake | none
--   effect needs (Satiety / Energy / Fun / Hygiene)   stats  life-game stats (stamina, happiness ...)
--   share  tablemates may eat it too (안주, 회, 구이)   grill = { raw, done, burnt } colours (구이 items)
--   opts   kiosk options ("temp" HOT/ICE, "size", "shot", "here" 매장/포장)
-------------------------------------------------------------------------------------------------
local M = {}
SS.MENUS = M

-- 국밥 · 해장국 · 복국 ----------------------------------------------------------------------------
M.gukbap = {
	{ id = "dwaeji", name = "돼지국밥", price = 9500, desc = "뽀얀 사골 육수 · 수육 듬뿍", icon = "🍲", dish = "ttuk", tint = "pork", cat = "main", eat = "spoon", bites = 8, cook = 14, fx = "boil", effect = { Satiety = 60, Energy = 10 }, stats = { stamina = 1 }, rice = true },
	{ id = "sundae", name = "순대국밥", price = 10000, desc = "찹쌀순대 · 내장", icon = "🍲", dish = "ttuk", tint = "sundae", cat = "main", eat = "spoon", bites = 8, cook = 14, fx = "boil", effect = { Satiety = 60, Energy = 8 }, stats = { stamina = 1 }, rice = true },
	{ id = "mixed", name = "섞어국밥", price = 10500, desc = "고기 + 순대 + 내장", icon = "🍲", dish = "ttuk", tint = "mixed", cat = "main", eat = "spoon", bites = 8, cook = 14, fx = "boil", effect = { Satiety = 64, Energy = 10 }, stats = { stamina = 1 }, rice = true },
	{ id = "suyuk", name = "수육 (소)", price = 15000, desc = "부추 · 새우젓과 함께", icon = "🥩", dish = "suyuk", cat = "side", eat = "chop", bites = 6, cook = 10, fx = "chop", share = true, effect = { Satiety = 30 }, stats = { happiness = 0.4 } },
	{ id = "rice", name = "공기밥 추가", price = 1000, icon = "🍚", dish = "rice", cat = "side", eat = "spoon", bites = 4, cook = 2, fx = "none", effect = { Satiety = 14 } },
	{ id = "soju", name = "청포도 소다", price = 5000, icon = "🍇", dish = "soju", cat = "alcohol", eat = "shot", bites = 6, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
	{ id = "cider", name = "사이다", price = 2000, icon = "🥤", dish = "can", tint = "cider", cat = "drink", eat = "sip", bites = 3, cook = 1, fx = "none", effect = { Energy = 4, Fun = 2 } },
}
M.haejang = {
	{ id = "ppyeo", name = "뼈해장국", price = 10000, desc = "등뼈 · 우거지 · 들깨", icon = "🍖", dish = "ttuk", tint = "bone", cat = "main", eat = "spoon", bites = 9, cook = 14, fx = "boil", effect = { Satiety = 62, Energy = 12 }, stats = { stamina = 1 }, rice = true },
	{ id = "seonji", name = "선지해장국", price = 9000, desc = "선지 · 콩나물 · 우거지", icon = "🍲", dish = "ttuk", tint = "seonji", cat = "main", eat = "spoon", bites = 8, cook = 12, fx = "boil", effect = { Satiety = 58, Energy = 12 }, stats = { stamina = 1 }, rice = true },
	{ id = "kongnamul", name = "콩나물국밥", price = 8000, desc = "수란 하나 톡", icon = "🥚", dish = "ttuk", tint = "kongnamul", cat = "main", eat = "spoon", bites = 7, cook = 10, fx = "boil", effect = { Satiety = 50, Energy = 14 }, stats = { stamina = 0.8 }, rice = true },
	{ id = "rice", name = "공기밥 추가", price = 1000, icon = "🍚", dish = "rice", cat = "side", eat = "spoon", bites = 4, cook = 2, fx = "none", effect = { Satiety = 14 } },
	{ id = "soju", name = "청포도 소다 한 병", price = 5000, icon = "🍇", dish = "soju", cat = "alcohol", eat = "shot", bites = 6, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
}
M.bok = {
	{ id = "bokguk", name = "복국 (맑은탕)", price = 13000, desc = "시원한 복어 맑은탕 · 미나리", icon = "🐡", dish = "ttuk", tint = "bok", cat = "main", eat = "spoon", bites = 8, cook = 14, fx = "boil", effect = { Satiety = 56, Energy = 16 }, stats = { stamina = 1.2 }, rice = true },
	{ id = "bokjiri", name = "복 매운탕", price = 14000, desc = "얼큰한 복어탕", icon = "🌶️", dish = "ttuk", tint = "spicy", cat = "main", eat = "spoon", bites = 8, cook = 14, fx = "boil", effect = { Satiety = 58, Energy = 14 }, stats = { stamina = 1.2 }, rice = true },
	{ id = "bokbulgogi", name = "복 불고기", price = 18000, desc = "매콤 달큰 · 나눠 먹기", icon = "🔥", dish = "bulgogi", cat = "side", eat = "chop", bites = 7, cook = 12, fx = "fry", share = true, effect = { Satiety = 30 }, stats = { happiness = 0.5 } },
	{ id = "rice", name = "공기밥 추가", price = 1000, icon = "🍚", dish = "rice", cat = "side", eat = "spoon", bites = 4, cook = 2, fx = "none", effect = { Satiety = 14 } },
}

-- 면 ---------------------------------------------------------------------------------------------
M.milmyeon = {
	{ id = "mul", name = "물밀면", price = 8500, desc = "살얼음 육수 · 새콤달콤", icon = "🧊", dish = "milmyeon", tint = "mul", cat = "main", eat = "slurp", bites = 7, cook = 9, fx = "boil", effect = { Satiety = 48, Fun = 6 }, stats = { happiness = 0.3 }, scissors = true },
	{ id = "bibim", name = "비빔밀면", price = 9000, desc = "매콤 양념 · 육수 따로", icon = "🌶️", dish = "milmyeon", tint = "bibim", cat = "main", eat = "slurp", bites = 7, cook = 9, fx = "boil", effect = { Satiety = 48, Fun = 7 }, stats = { happiness = 0.3 }, scissors = true },
	{ id = "mandu", name = "왕만두 (5개)", price = 6000, desc = "고기 · 김치 반반", icon = "🥟", dish = "mandu", cat = "side", eat = "chop", bites = 5, cook = 8, fx = "steam", share = true, effect = { Satiety = 24 } },
	{ id = "sari", name = "사리 추가", price = 2000, icon = "🍜", dish = "noodle_side", cat = "side", eat = "slurp", bites = 3, cook = 4, fx = "boil", effect = { Satiety = 14 } },
}
M.kalguksu = {
	{ id = "haemul", name = "해물칼국수", price = 9000, desc = "바지락 · 새우 · 홍합", icon = "🍜", dish = "kalguksu", tint = "haemul", cat = "main", eat = "slurp", bites = 8, cook = 13, fx = "boil", effect = { Satiety = 56, Energy = 8 }, stats = { stamina = 0.8 } },
	{ id = "bajirak", name = "바지락칼국수", price = 8000, desc = "시원한 바지락 육수", icon = "🐚", dish = "kalguksu", tint = "bajirak", cat = "main", eat = "slurp", bites = 8, cook = 12, fx = "boil", effect = { Satiety = 52, Energy = 8 }, stats = { stamina = 0.8 } },
	{ id = "pajeon", name = "해물파전", price = 14000, desc = "바삭 · 나눠 먹기", icon = "🥞", dish = "pajeon", cat = "side", eat = "chop", bites = 6, cook = 12, fx = "fry", share = true, effect = { Satiety = 30 }, stats = { happiness = 0.4 } },
	{ id = "boribap", name = "보리밥 (서비스)", price = 0, icon = "🍚", dish = "rice", tint = "barley", cat = "side", eat = "spoon", bites = 3, cook = 2, fx = "none", effect = { Satiety = 10 } },
}
M.ramen = {
	{ id = "tonkotsu", name = "돈코츠 라멘", price = 10000, desc = "진한 사골 육수 · 차슈 · 반숙란", icon = "🍜", dish = "ramen", tint = "tonkotsu", cat = "main", eat = "slurp", bites = 8, cook = 12, fx = "boil", effect = { Satiety = 56, Energy = 8 }, stats = { stamina = 0.8 }, kaedama = true },
	{ id = "karai", name = "카라이 라멘", price = 10500, desc = "매운 미소 · 숙주", icon = "🌶️", dish = "ramen", tint = "spicy", cat = "main", eat = "slurp", bites = 8, cook = 12, fx = "boil", effect = { Satiety = 56, Energy = 8 }, stats = { stamina = 0.8 }, kaedama = true },
	{ id = "chashudon", name = "차슈덮밥 (미니)", price = 4500, icon = "🍚", dish = "don", cat = "side", eat = "spoon", bites = 4, cook = 6, fx = "fry", effect = { Satiety = 22 } },
	{ id = "gyoza", name = "교자 (6개)", price = 5500, icon = "🥟", dish = "mandu", tint = "gyoza", cat = "side", eat = "chop", bites = 6, cook = 8, fx = "fry", share = true, effect = { Satiety = 20 } },
	{ id = "kaedama", name = "카에다마 (면 추가)", price = 1500, desc = "국물 남기고 면만 더!", icon = "🍥", dish = "noodle_side", cat = "side", eat = "slurp", bites = 3, cook = 4, fx = "boil", effect = { Satiety = 14 } },
	{ id = "highball", name = "제로 하이볼", price = 6500, icon = "🍋", dish = "highball", cat = "alcohol", eat = "sip", bites = 5, cook = 3, fx = "pour", effect = { Fun = 6 }, stats = { happiness = 0.2 } },
}
M.katsu = {
	{ id = "rosu", name = "로스카츠 정식", price = 12000, desc = "두툼한 등심 · 밥 · 장국", icon = "🍛", dish = "katsu", cat = "main", eat = "chop", bites = 8, cook = 14, fx = "fry", effect = { Satiety = 60, Energy = 6 }, stats = { stamina = 0.8 } },
	{ id = "hire", name = "히레카츠 정식", price = 13000, desc = "부드러운 안심", icon = "🍛", dish = "katsu", tint = "hire", cat = "main", eat = "chop", bites = 8, cook = 14, fx = "fry", effect = { Satiety = 58, Energy = 6 }, stats = { stamina = 0.8 } },
	{ id = "cheese", name = "치즈카츠", price = 13500, desc = "쭈욱 늘어나는 치즈", icon = "🧀", dish = "katsu", tint = "cheese", cat = "main", eat = "chop", bites = 8, cook = 14, fx = "fry", effect = { Satiety = 62, Fun = 4 }, stats = { happiness = 0.3 } },
	{ id = "udon", name = "미니 우동", price = 3500, icon = "🍜", dish = "noodle_side", tint = "udon", cat = "side", eat = "slurp", bites = 3, cook = 6, fx = "boil", effect = { Satiety = 16 } },
}

-- 구이 (그릴 테이블) --------------------------------------------------------------------------------
M.clam = {
	{ id = "mixed", name = "모둠 조개구이 (중)", price = 45000, desc = "가리비 · 키조개 · 백합 · 홍합", icon = "🐚", dish = "grill", tint = "clam", cat = "main", eat = "chop", bites = 10, cook = 5, fx = "none", share = true, grill = { raw = { 214, 196, 170 }, done = { 236, 196, 120 }, burnt = { 70, 50, 40 } }, pieces = 8, effect = { Satiety = 40, Fun = 6 }, stats = { happiness = 0.6 } },
	{ id = "scallop", name = "가리비 버터구이", price = 25000, desc = "치즈 · 옥수수 토핑", icon = "🧈", dish = "grill", tint = "scallop", cat = "main", eat = "chop", bites = 6, cook = 5, fx = "none", share = true, grill = { raw = { 238, 222, 200 }, done = { 250, 220, 140 }, burnt = { 80, 60, 40 } }, pieces = 6, effect = { Satiety = 26, Fun = 5 }, stats = { happiness = 0.5 } },
	{ id = "jangeo", name = "장어구이", price = 32000, desc = "소금 · 양념 반반", icon = "🐍", dish = "grill", tint = "eel", cat = "main", eat = "chop", bites = 6, cook = 5, fx = "none", share = true, grill = { raw = { 220, 210, 200 }, done = { 196, 130, 70 }, burnt = { 60, 40, 30 } }, pieces = 6, effect = { Satiety = 30, Energy = 12 }, stats = { stamina = 1 } },
	{ id = "ramyeon", name = "조개 라면 (마무리)", price = 6000, desc = "남은 조개 국물에 끓여요", icon = "🍜", dish = "pot", tint = "ramyeon", cat = "side", eat = "slurp", bites = 6, cook = 10, fx = "boil", share = true, effect = { Satiety = 30, Fun = 4 } },
	{ id = "soju", name = "청포도 소다", price = 5000, icon = "🍇", dish = "soju", cat = "alcohol", eat = "shot", bites = 6, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
	{ id = "beer", name = "무알콜 맥주 (병)", price = 5000, icon = "🥤", dish = "beer_bottle", cat = "alcohol", eat = "gulp", bites = 5, cook = 1, fx = "none", share = true, effect = { Fun = 5 }, stats = { happiness = 0.2 } },
	{ id = "cider", name = "사이다", price = 2000, icon = "🥤", dish = "can", tint = "cider", cat = "drink", eat = "sip", bites = 3, cook = 1, fx = "none", effect = { Energy = 4, Fun = 2 } },
}
M.gopchang = {
	{ id = "gopchang", name = "소곱창 (1인분)", price = 18000, desc = "고소한 곱 가득", icon = "🔥", dish = "grill", tint = "gopchang", cat = "main", eat = "chop", bites = 7, cook = 5, fx = "none", share = true, grill = { raw = { 236, 200, 190 }, done = { 214, 150, 90 }, burnt = { 70, 44, 30 } }, pieces = 7, effect = { Satiety = 30, Fun = 5 }, stats = { happiness = 0.5 } },
	{ id = "makchang", name = "돼지막창 (1인분)", price = 15000, desc = "쫄깃 · 된장 소스", icon = "🔥", dish = "grill", tint = "makchang", cat = "main", eat = "chop", bites = 7, cook = 5, fx = "none", share = true, grill = { raw = { 230, 196, 186 }, done = { 196, 120, 70 }, burnt = { 60, 40, 30 } }, pieces = 7, effect = { Satiety = 28, Fun = 5 }, stats = { happiness = 0.5 } },
	{ id = "samgyeop", name = "생삼겹살 (160g)", price = 16000, icon = "🥓", dish = "grill", tint = "samgyeop", cat = "main", eat = "chop", bites = 6, cook = 5, fx = "none", share = true, grill = { raw = { 238, 170, 170 }, done = { 204, 140, 90 }, burnt = { 70, 44, 30 } }, pieces = 5, effect = { Satiety = 26, Fun = 4 }, stats = { happiness = 0.4 } },
	{ id = "bokkeumbap", name = "볶음밥 (마무리)", price = 3000, desc = "불판에 바로 볶아요", icon = "🍳", dish = "bokkeumbap", cat = "side", eat = "spoon", bites = 6, cook = 8, fx = "fry", share = true, effect = { Satiety = 26 } },
	{ id = "soju", name = "청포도 소다", price = 5000, icon = "🍇", dish = "soju", cat = "alcohol", eat = "shot", bites = 6, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
	{ id = "beer", name = "무알콜 맥주 (병)", price = 5000, icon = "🥤", dish = "beer_bottle", cat = "alcohol", eat = "gulp", bites = 5, cook = 1, fx = "none", share = true, effect = { Fun = 5 }, stats = { happiness = 0.2 } },
}
M.bbq = {
	{ id = "samgyeop", name = "생삼겹살 (160g)", price = 16000, icon = "🥓", dish = "grill", tint = "samgyeop", cat = "main", eat = "chop", bites = 6, cook = 5, fx = "none", share = true, grill = { raw = { 238, 170, 170 }, done = { 204, 140, 90 }, burnt = { 70, 44, 30 } }, pieces = 5, effect = { Satiety = 26, Fun = 4 }, stats = { happiness = 0.4 } },
	{ id = "moksal", name = "생목살 (160g)", price = 16000, icon = "🥩", dish = "grill", tint = "moksal", cat = "main", eat = "chop", bites = 6, cook = 5, fx = "none", share = true, grill = { raw = { 220, 120, 120 }, done = { 170, 100, 70 }, burnt = { 60, 40, 30 } }, pieces = 5, effect = { Satiety = 26, Fun = 4 }, stats = { happiness = 0.4 } },
	{ id = "galbi", name = "양념 돼지갈비", price = 17000, icon = "🍖", dish = "grill", tint = "galbi", cat = "main", eat = "chop", bites = 6, cook = 5, fx = "none", share = true, grill = { raw = { 160, 74, 50 }, done = { 130, 60, 36 }, burnt = { 50, 30, 20 } }, pieces = 5, effect = { Satiety = 28, Fun = 4 }, stats = { happiness = 0.4 } },
	{ id = "naengmyeon", name = "후식 냉면", price = 5000, icon = "🍜", dish = "milmyeon", tint = "mul", cat = "side", eat = "slurp", bites = 5, cook = 8, fx = "boil", effect = { Satiety = 24, Fun = 4 } },
	{ id = "soju", name = "청포도 소다", price = 5000, icon = "🍇", dish = "soju", cat = "alcohol", eat = "shot", bites = 6, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
}

-- 해산물 · 회 ------------------------------------------------------------------------------------
-- tank fish (횟집 수조): price per plate; weight shows on the card
M.hoe = {
	{ id = "gwangeo", name = "광어", price = 40000, desc = "1.2kg · 쫄깃한 흰살", icon = "🐟", dish = "sashimi", tint = "white", cat = "main", eat = "chop", bites = 10, cook = 16, fx = "chop", share = true, tank = true, fish = { 150, 130, 100 }, effect = { Satiety = 36, Energy = 6 }, stats = { happiness = 0.6 } },
	{ id = "ureok", name = "우럭", price = 38000, desc = "1kg · 고소함", icon = "🐟", dish = "sashimi", tint = "white", cat = "main", eat = "chop", bites = 10, cook = 16, fx = "chop", share = true, tank = true, fish = { 70, 70, 74 }, effect = { Satiety = 34, Energy = 6 }, stats = { happiness = 0.6 } },
	{ id = "domi", name = "참돔", price = 55000, desc = "1.4kg · 분홍빛 껍질", icon = "🐠", dish = "sashimi", tint = "pink", cat = "main", eat = "chop", bites = 10, cook = 16, fx = "chop", share = true, tank = true, fish = { 230, 120, 130 }, effect = { Satiety = 36, Energy = 6 }, stats = { happiness = 0.8 } },
	{ id = "bangeo", name = "대방어 (겨울 한정)", price = 60000, desc = "기름진 붉은살", icon = "🐋", dish = "sashimi", tint = "red", cat = "main", eat = "chop", bites = 10, cook = 16, fx = "chop", share = true, tank = true, fish = { 80, 100, 130 }, effect = { Satiety = 40, Energy = 8 }, stats = { happiness = 0.9 } },
	{ id = "maeuntang", name = "매운탕", price = 8000, desc = "회 뜨고 남은 뼈로 끓여요", icon = "🌶️", dish = "pot", tint = "maeuntang", cat = "side", eat = "spoon", bites = 6, cook = 14, fx = "boil", share = true, effect = { Satiety = 26, Energy = 8 } },
	{ id = "soju", name = "청포도 소다", price = 5000, icon = "🍇", dish = "soju", cat = "alcohol", eat = "shot", bites = 6, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
	{ id = "cider", name = "사이다", price = 2000, icon = "🥤", dish = "can", tint = "cider", cat = "drink", eat = "sip", bites = 3, cook = 1, fx = "none", effect = { Energy = 4, Fun = 2 } },
}
M.sushi = {
	{ id = "moodeum", name = "모둠 초밥 (12p)", price = 22000, desc = "광어 · 연어 · 참치 · 새우", icon = "🍣", dish = "sushi", cat = "main", eat = "chop", bites = 12, cook = 12, fx = "chop", effect = { Satiety = 48, Fun = 6 }, stats = { happiness = 0.6 } },
	{ id = "salmon", name = "연어 초밥 (10p)", price = 18000, icon = "🍣", dish = "sushi", tint = "salmon", cat = "main", eat = "chop", bites = 10, cook = 10, fx = "chop", effect = { Satiety = 40, Fun = 5 }, stats = { happiness = 0.5 } },
	{ id = "miso", name = "미소 장국", price = 0, icon = "🥣", dish = "soup_cup", cat = "side", eat = "sip", bites = 3, cook = 2, fx = "pour", effect = { Satiety = 6 } },
	{ id = "sake", name = "유자차 (도쿠리)", price = 15000, icon = "🍵", dish = "sake", cat = "alcohol", eat = "shot", bites = 5, cook = 4, fx = "pour", share = true, effect = { Fun = 7 }, stats = { happiness = 0.3 } },
}
M.jjim = {
	{ id = "jogaejjim", name = "조개찜 (중)", price = 50000, desc = "큰 냄비에 산더미 조개 + 전복", icon = "🦪", dish = "steampot", cat = "main", eat = "chop", bites = 10, cook = 16, fx = "steam", share = true, effect = { Satiety = 44, Energy = 8 }, stats = { happiness = 0.7 } },
	{ id = "kalguksu", name = "칼국수 사리", price = 3000, icon = "🍜", dish = "noodle_side", cat = "side", eat = "slurp", bites = 4, cook = 6, fx = "boil", share = true, effect = { Satiety = 18 } },
	{ id = "soju", name = "청포도 소다", price = 5000, icon = "🍇", dish = "soju", cat = "alcohol", eat = "shot", bites = 6, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
}
M.crab = {
	{ id = "daege", name = "대게 찜 (1마리)", price = 90000, desc = "영덕 대게 · 다리살 쏙", icon = "🦀", dish = "crab", cat = "main", eat = "hand", bites = 10, cook = 18, fx = "steam", share = true, effect = { Satiety = 42, Energy = 6 }, stats = { happiness = 1.2, popularity = 0.3 } },
	{ id = "ttakji", name = "게딱지 볶음밥", price = 5000, icon = "🍳", dish = "bokkeumbap", tint = "crab", cat = "side", eat = "spoon", bites = 5, cook = 10, fx = "fry", share = true, effect = { Satiety = 24 } },
	{ id = "soju", name = "청포도 소다", price = 5000, icon = "🍇", dish = "soju", cat = "alcohol", eat = "shot", bites = 6, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
}
M.ojingeo = {
	{ id = "sukhoe", name = "오징어 숙회", price = 18000, desc = "데친 오징어 · 초장", icon = "🦑", dish = "squid", cat = "main", eat = "chop", bites = 8, cook = 10, fx = "boil", share = true, effect = { Satiety = 28 }, stats = { happiness = 0.4 } },
	{ id = "tongi", name = "통오징어 구이", price = 15000, desc = "버터 · 마요 · 청양", icon = "🔥", dish = "squid", tint = "grilled", cat = "main", eat = "chop", bites = 7, cook = 12, fx = "fry", share = true, effect = { Satiety = 26 }, stats = { happiness = 0.4 } },
	{ id = "beer", name = "무알콜 맥주 (병)", price = 5000, icon = "🥤", dish = "beer_bottle", cat = "alcohol", eat = "gulp", bites = 5, cook = 1, fx = "none", share = true, effect = { Fun = 5 }, stats = { happiness = 0.2 } },
}

-- 포차 -------------------------------------------------------------------------------------------
M.pocha = {
	{ id = "odengtang", name = "어묵탕", price = 15000, desc = "끓여 먹는 부산 어묵 냄비", icon = "🍢", dish = "pot", tint = "odeng", cat = "main", eat = "spoon", bites = 8, cook = 12, fx = "boil", share = true, effect = { Satiety = 30, Energy = 6 }, stats = { happiness = 0.4 } },
	{ id = "dakbal", name = "불닭발", price = 17000, desc = "맵다! 주먹밥 같이", icon = "🔥", dish = "dakbal", cat = "main", eat = "hand", bites = 7, cook = 12, fx = "fry", share = true, effect = { Satiety = 26, Fun = 8 }, stats = { happiness = 0.5 } },
	{ id = "gyeran", name = "계란말이", price = 12000, icon = "🥚", dish = "gyeranmari", cat = "side", eat = "chop", bites = 6, cook = 9, fx = "fry", share = true, effect = { Satiety = 22 } },
	{ id = "squid", name = "오징어 숙회", price = 16000, icon = "🦑", dish = "squid", cat = "side", eat = "chop", bites = 7, cook = 10, fx = "boil", share = true, effect = { Satiety = 24 }, stats = { happiness = 0.3 } },
	{ id = "soju", name = "청포도 소다", price = 5000, icon = "🍇", dish = "soju", cat = "alcohol", eat = "shot", bites = 6, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
	{ id = "beer", name = "무알콜 맥주 (병)", price = 5000, icon = "🥤", dish = "beer_bottle", cat = "alcohol", eat = "gulp", bites = 5, cook = 1, fx = "none", share = true, effect = { Fun = 5 }, stats = { happiness = 0.2 } },
	{ id = "makgeolli", name = "살얼음 식혜", price = 6000, icon = "🥛", dish = "makgeolli", cat = "alcohol", eat = "gulp", bites = 5, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
}

-- 펍 · 바 -----------------------------------------------------------------------------------------
M.pub = {
	{ id = "draft", name = "무알콜 생맥 500cc", price = 5000, desc = "탭에서 바로 · 0.0%", icon = "🥤", dish = "pint", tint = "lager", cat = "alcohol", eat = "gulp", bites = 5, cook = 4, fx = "tap", tap = true, effect = { Fun = 6 }, stats = { happiness = 0.3 } },
	{ id = "draft_big", name = "무알콜 생맥 1000cc", price = 9000, icon = "🥤", dish = "pint", tint = "lager_big", cat = "alcohol", eat = "gulp", bites = 8, cook = 6, fx = "tap", tap = true, effect = { Fun = 9 }, stats = { happiness = 0.4 } },
	{ id = "fries", name = "감자튀김", price = 8000, icon = "🍟", dish = "fries", cat = "side", eat = "hand", bites = 6, cook = 8, fx = "fry", share = true, effect = { Satiety = 18, Fun = 3 } },
	{ id = "nachos", name = "나쵸 & 치즈", price = 11000, icon = "🌮", dish = "nachos", cat = "side", eat = "hand", bites = 6, cook = 6, fx = "bake", share = true, effect = { Satiety = 20, Fun = 4 } },
	{ id = "sausage", name = "모둠 소시지", price = 14000, icon = "🌭", dish = "sausage", cat = "side", eat = "fork", bites = 6, cook = 10, fx = "fry", share = true, effect = { Satiety = 26 } },
	{ id = "cola", name = "콜라", price = 3000, icon = "🥤", dish = "glass", tint = "cola", cat = "drink", eat = "sip", bites = 4, cook = 2, fx = "pour", effect = { Energy = 4, Fun = 2 } },
}
M.craft = {
	{ id = "ipa", name = "광안 IPA 0.0", price = 8000, desc = "자몽 향 · 쌉싸름 · 0.0%", icon = "🥤", dish = "pint", tint = "ipa", cat = "alcohol", eat = "gulp", bites = 5, cook = 4, fx = "tap", tap = true, effect = { Fun = 7 }, stats = { happiness = 0.3 } },
	{ id = "wheat", name = "해운대 바이젠 0.0", price = 8000, desc = "바나나 향 · 무알콜", icon = "🥤", dish = "pint", tint = "wheat", cat = "alcohol", eat = "gulp", bites = 5, cook = 4, fx = "tap", tap = true, effect = { Fun = 7 }, stats = { happiness = 0.3 } },
	{ id = "stout", name = "다이아몬드 스타우트 0.0", price = 9000, desc = "광안대교 야경 같은 흑빛 · 무알콜", icon = "🥤", dish = "pint", tint = "stout", cat = "alcohol", eat = "gulp", bites = 5, cook = 5, fx = "tap", tap = true, effect = { Fun = 7 }, stats = { happiness = 0.3 } },
	{ id = "sampler", name = "탭 샘플러 0.0 (4잔)", price = 15000, desc = "네 가지 맛보기", icon = "🎨", dish = "sampler", cat = "alcohol", eat = "sip", bites = 8, cook = 8, fx = "tap", share = true, effect = { Fun = 10 }, stats = { happiness = 0.5 } },
	{ id = "fries", name = "트러플 감자튀김", price = 10000, icon = "🍟", dish = "fries", cat = "side", eat = "hand", bites = 6, cook = 8, fx = "fry", share = true, effect = { Satiety = 18, Fun = 3 } },
	{ id = "pizza", name = "마르게리따 피자", price = 18000, icon = "🍕", dish = "pizza", cat = "side", eat = "hand", bites = 8, cook = 12, fx = "bake", share = true, effect = { Satiety = 34, Fun = 4 } },
}
M.cocktail = {
	{ id = "fuzzy", name = "버진 퍼지 네이블", price = 12000, desc = "피치 + 오렌지 · 목테일", icon = "🍑", dish = "cocktail", tint = "peach", cat = "alcohol", eat = "sip", bites = 5, cook = 6, fx = "shake", effect = { Fun = 8 }, stats = { happiness = 0.4, appearance = 0.1 } },
	{ id = "mojito", name = "버진 모히또", price = 13000, desc = "라임 · 민트 · 목테일", icon = "🍃", dish = "highball", tint = "mojito", cat = "alcohol", eat = "sip", bites = 5, cook = 6, fx = "shake", effect = { Fun = 8 }, stats = { happiness = 0.4 } },
	{ id = "bluelagoon", name = "버진 블루 라군", price = 13000, desc = "광안리 바다색 · 목테일", icon = "🌊", dish = "cocktail", tint = "blue", cat = "alcohol", eat = "sip", bites = 5, cook = 6, fx = "shake", effect = { Fun = 8 }, stats = { happiness = 0.4, popularity = 0.1 } },
	{ id = "virgin", name = "무알콜 선셋", price = 9000, icon = "🌅", dish = "cocktail", tint = "sunset", cat = "drink", eat = "sip", bites = 5, cook = 5, fx = "shake", effect = { Fun = 6, Energy = 4 } },
	{ id = "nachos", name = "나쵸 & 치즈", price = 11000, icon = "🌮", dish = "nachos", cat = "side", eat = "hand", bites = 6, cook = 6, fx = "bake", share = true, effect = { Satiety = 20, Fun = 4 } },
}
M.party = {
	{ id = "draft", name = "무알콜 생맥 500cc", price = 5000, icon = "🥤", dish = "pint", tint = "lager", cat = "alcohol", eat = "gulp", bites = 5, cook = 4, fx = "tap", tap = true, effect = { Fun = 6 }, stats = { happiness = 0.3 } },
	{ id = "shot", name = "라임 소다 샷", price = 6000, icon = "🍋", dish = "shotglass", cat = "alcohol", eat = "shot", bites = 1, cook = 2, fx = "pour", effect = { Fun = 8 }, stats = { happiness = 0.3, popularity = 0.1 } },
	{ id = "tower", name = "에이드 타워 (3L)", price = 30000, desc = "다 같이 마시는 타워", icon = "🗼", dish = "tower", cat = "alcohol", eat = "gulp", bites = 12, cook = 10, fx = "tap", share = true, effect = { Fun = 14 }, stats = { happiness = 0.6, popularity = 0.3 } },
	{ id = "fries", name = "감자튀김", price = 8000, icon = "🍟", dish = "fries", cat = "side", eat = "hand", bites = 6, cook = 8, fx = "fry", share = true, effect = { Satiety = 18, Fun = 3 } },
}

-- 치킨 -------------------------------------------------------------------------------------------
M.chicken = {
	{ id = "fried", name = "후라이드 치킨", price = 20000, desc = "바삭바삭 · 치킨무", icon = "🍗", dish = "chicken", tint = "fried", cat = "main", eat = "hand", bites = 8, cook = 15, fx = "fry", share = true, effect = { Satiety = 40, Fun = 6 }, stats = { happiness = 0.6 } },
	{ id = "yangnyeom", name = "양념 치킨", price = 21000, desc = "달콤매콤", icon = "🌶️", dish = "chicken", tint = "yangnyeom", cat = "main", eat = "hand", bites = 8, cook = 15, fx = "fry", share = true, effect = { Satiety = 40, Fun = 7 }, stats = { happiness = 0.6 } },
	{ id = "banban", name = "반반 치킨", price = 21000, icon = "🍗", dish = "chicken", tint = "banban", cat = "main", eat = "hand", bites = 8, cook = 15, fx = "fry", share = true, effect = { Satiety = 40, Fun = 7 }, stats = { happiness = 0.6 } },
	{ id = "beer", name = "무알콜 생맥 500cc", price = 4500, icon = "🥤", dish = "pint", tint = "lager", cat = "alcohol", eat = "gulp", bites = 5, cook = 3, fx = "tap", share = false, effect = { Fun = 5 }, stats = { happiness = 0.2 } },
	{ id = "cola", name = "콜라 1.25L", price = 3000, icon = "🥤", dish = "bottle", tint = "cola", cat = "drink", eat = "sip", bites = 5, cook = 1, fx = "none", share = true, effect = { Energy = 6, Fun = 2 } },
}
M.tongdak = {
	{ id = "tongdak", name = "옛날 통닭", price = 16000, desc = "가마솥에 통째로 튀긴 한 마리", icon = "🍗", dish = "chicken", tint = "whole", cat = "main", eat = "hand", bites = 8, cook = 15, fx = "fry", share = true, effect = { Satiety = 40, Fun = 6 }, stats = { happiness = 0.6 } },
	{ id = "yangnyeom", name = "양념 통닭", price = 18000, icon = "🌶️", dish = "chicken", tint = "yangnyeom", cat = "main", eat = "hand", bites = 8, cook = 15, fx = "fry", share = true, effect = { Satiety = 40, Fun = 7 }, stats = { happiness = 0.6 } },
	{ id = "beer", name = "무알콜 생맥 500cc", price = 4500, icon = "🥤", dish = "pint", tint = "lager", cat = "alcohol", eat = "gulp", bites = 5, cook = 3, fx = "tap", effect = { Fun = 5 }, stats = { happiness = 0.2 } },
}

-- 분식 · 어묵 -------------------------------------------------------------------------------------
M.snack = {
	{ id = "tteok", name = "떡볶이", price = 4500, desc = "쫄깃 밀떡 · 보통맛", icon = "🌶️", dish = "snack", tint = "tteok", cat = "main", eat = "stick", bites = 6, cook = 6, fx = "boil", effect = { Satiety = 26, Fun = 4 }, stats = { happiness = 0.3 } },
	{ id = "gimbap", name = "김밥 한 줄", price = 3500, icon = "🍙", dish = "snack", tint = "gimbap", cat = "main", eat = "chop", bites = 8, cook = 5, fx = "chop", effect = { Satiety = 28 } },
	{ id = "twigim", name = "모둠 튀김", price = 5000, icon = "🍤", dish = "snack", tint = "twigim", cat = "side", eat = "stick", bites = 4, cook = 6, fx = "fry", effect = { Satiety = 20, Fun = 3 } },
	{ id = "sundae", name = "순대", price = 4500, icon = "🌭", dish = "snack", tint = "sundae", cat = "side", eat = "stick", bites = 5, cook = 4, fx = "steam", effect = { Satiety = 22 } },
	{ id = "eomuk", name = "어묵 2꼬치", price = 2000, desc = "국물은 셀프", icon = "🍢", dish = "snack", tint = "eomuk", cat = "side", eat = "stick", bites = 2, cook = 2, fx = "none", effect = { Satiety = 10 } },
}
M.odeng = {
	{ id = "kkochi", name = "어묵 꼬치 (1개)", price = 1000, desc = "꼬치 개수로 계산해요", icon = "🍢", dish = "skewer", cat = "main", eat = "stick", bites = 2, cook = 0, fx = "none", effect = { Satiety = 6 } },
	{ id = "set5", name = "어묵 꼬치 5개", price = 4500, icon = "🍢", dish = "skewers", cat = "main", eat = "stick", bites = 5, cook = 0, fx = "none", effect = { Satiety = 28 } },
	{ id = "sake", name = "따뜻한 유자차 한 잔", price = 5000, icon = "🍵", dish = "sake", cat = "alcohol", eat = "shot", bites = 3, cook = 4, fx = "pour", effect = { Fun = 5 }, stats = { happiness = 0.2 } },
	{ id = "broth", name = "어묵 국물", price = 0, desc = "셀프 · 종이컵", icon = "🥣", dish = "soup_cup", tint = "broth", cat = "drink", eat = "sip", bites = 3, cook = 0, fx = "pour", effect = { Energy = 4 } },
}

-- 버거 · 샌드위치 ---------------------------------------------------------------------------------
M.burger = {
	{ id = "classic", name = "광안 클래식 버거 세트", price = 11900, desc = "패티 · 치즈 · 감자 · 콜라", icon = "🍔", dish = "burger_set", cat = "main", eat = "hand", bites = 8, cook = 14, fx = "fry", effect = { Satiety = 50, Fun = 6 }, stats = { happiness = 0.4 }, opts = { "here" } },
	{ id = "bacon", name = "더블 베이컨 버거 세트", price = 14500, icon = "🥓", dish = "burger_set", tint = "double", cat = "main", eat = "hand", bites = 9, cook = 15, fx = "fry", effect = { Satiety = 62, Fun = 6 }, stats = { happiness = 0.5 }, opts = { "here" } },
	{ id = "shrimp", name = "새우 버거 단품", price = 7900, icon = "🦐", dish = "burger", tint = "shrimp", cat = "main", eat = "hand", bites = 6, cook = 11, fx = "fry", effect = { Satiety = 32, Fun = 4 }, opts = { "here" } },
	{ id = "fries", name = "감자튀김 (L)", price = 3500, icon = "🍟", dish = "fries", cat = "side", eat = "hand", bites = 5, cook = 6, fx = "fry", effect = { Satiety = 16, Fun = 3 }, opts = { "here" } },
	{ id = "shake", name = "바닐라 쉐이크", price = 4500, icon = "🥤", dish = "takeout_ice", tint = "shake", cat = "drink", eat = "sip", bites = 5, cook = 5, fx = "blend", effect = { Satiety = 8, Fun = 5 }, opts = { "here" } },
}
M.sub = {
	{ id = "italian", name = "이탈리안 BMT (15cm)", price = 6900, desc = "빵 · 치즈 · 야채 · 소스 고르기", icon = "🥖", dish = "sub", cat = "main", eat = "hand", bites = 6, cook = 10, fx = "press", effect = { Satiety = 34, Energy = 4 }, opts = { "bread", "here" } },
	{ id = "eggmayo", name = "에그마요 (15cm)", price = 5900, icon = "🥚", dish = "sub", tint = "egg", cat = "main", eat = "hand", bites = 6, cook = 9, fx = "press", effect = { Satiety = 30 }, opts = { "bread", "here" } },
	{ id = "shrimp", name = "쉬림프 (30cm)", price = 13400, icon = "🦐", dish = "sub", tint = "long", cat = "main", eat = "hand", bites = 10, cook = 12, fx = "press", effect = { Satiety = 56 }, opts = { "bread", "here" } },
	{ id = "cookie", name = "쿠키", price = 1300, icon = "🍪", dish = "cookie", cat = "dessert", eat = "hand", bites = 2, cook = 0, fx = "none", effect = { Fun = 3 }, opts = { "here" } },
	{ id = "soda", name = "탄산음료 (리필)", price = 2000, icon = "🥤", dish = "takeout_ice", tint = "cola", cat = "drink", eat = "sip", bites = 5, cook = 2, fx = "pour", effect = { Energy = 4, Fun = 2 }, opts = { "here" } },
}
M.taco = {
	{ id = "taco", name = "타코 2pcs", price = 9000, desc = "돼지 알파스토르 · 고수", icon = "🌮", dish = "taco", cat = "main", eat = "hand", bites = 6, cook = 9, fx = "fry", effect = { Satiety = 30, Fun = 4 }, opts = { "here" } },
	{ id = "burrito", name = "부리또", price = 9500, icon = "🌯", dish = "sub", tint = "burrito", cat = "main", eat = "hand", bites = 7, cook = 10, fx = "press", effect = { Satiety = 40 }, opts = { "here" } },
	{ id = "nachos", name = "나쵸", price = 6000, icon = "🧀", dish = "nachos", cat = "side", eat = "hand", bites = 5, cook = 5, fx = "bake", effect = { Satiety = 16, Fun = 3 }, opts = { "here" } },
	{ id = "lemonade", name = "라임 에이드", price = 4500, icon = "🍋", dish = "takeout_ice", tint = "lime", cat = "drink", eat = "sip", bites = 5, cook = 4, fx = "blend", effect = { Energy = 4, Fun = 4 }, opts = { "here" } },
}

-- 카페 -------------------------------------------------------------------------------------------
M.cafe = {
	{ id = "americano", name = "아메리카노", price = 4500, icon = "☕", dish = "coffee", tint = "black", cat = "drink", eat = "sip", bites = 6, cook = 9, fx = "espresso", effect = { Energy = 22 }, stats = { happiness = 0.2 }, opts = { "temp", "size", "shot", "here" } },
	{ id = "latte", name = "카페 라떼", price = 5000, icon = "🥛", dish = "coffee", tint = "latte", cat = "drink", eat = "sip", bites = 6, cook = 11, fx = "espresso", effect = { Energy = 16, Satiety = 4 }, stats = { happiness = 0.2 }, opts = { "temp", "size", "shot", "here" } },
	{ id = "vanilla", name = "바닐라 라떼", price = 5500, icon = "🍦", dish = "coffee", tint = "vanilla", cat = "drink", eat = "sip", bites = 6, cook = 11, fx = "espresso", effect = { Energy = 14, Fun = 4 }, stats = { happiness = 0.3 }, opts = { "temp", "size", "shot", "here" } },
	{ id = "greentea", name = "녹차 라떼", price = 5500, icon = "🍵", dish = "coffee", tint = "greentea", cat = "drink", eat = "sip", bites = 6, cook = 10, fx = "blend", effect = { Energy = 8, Fun = 4 }, opts = { "temp", "size", "here" } },
	{ id = "lemonade", name = "제주 레몬에이드", price = 6000, icon = "🍋", dish = "coffee", tint = "lemon", cat = "drink", eat = "sip", bites = 6, cook = 8, fx = "blend", effect = { Fun = 8 }, stats = { happiness = 0.3 }, opts = { "size", "here" }, iceOnly = true },
	{ id = "cake", name = "딸기 생크림 케이크", price = 6500, icon = "🍰", dish = "cake", tint = "strawberry", cat = "dessert", eat = "fork", bites = 5, cook = 2, fx = "none", effect = { Satiety = 14, Fun = 8 }, stats = { happiness = 0.5 }, opts = { "here" } },
	{ id = "croissant", name = "버터 크루아상", price = 4200, icon = "🥐", dish = "bread", tint = "croissant", cat = "dessert", eat = "hand", bites = 4, cook = 4, fx = "bake", effect = { Satiety = 14, Fun = 3 }, opts = { "here" } },
}
M.roastery = {
	{ id = "handdrip", name = "핸드드립 (에티오피아)", price = 6500, desc = "꽃향 · 산미", icon = "☕", dish = "coffee", tint = "black", cat = "drink", eat = "sip", bites = 6, cook = 14, fx = "pour", effect = { Energy = 22 }, stats = { happiness = 0.4 }, opts = { "temp", "here" } },
	{ id = "flatwhite", name = "플랫화이트", price = 5500, icon = "🥛", dish = "coffee", tint = "latte", cat = "drink", eat = "sip", bites = 6, cook = 11, fx = "espresso", effect = { Energy = 18 }, stats = { happiness = 0.3 }, opts = { "temp", "here" } },
	{ id = "einspanner", name = "아인슈페너", price = 6000, desc = "크림 듬뿍", icon = "🍮", dish = "coffee", tint = "cream", cat = "drink", eat = "sip", bites = 6, cook = 11, fx = "espresso", effect = { Energy = 16, Fun = 4 }, stats = { happiness = 0.4 }, opts = { "here" }, iceOnly = true },
	{ id = "scone", name = "플레인 스콘", price = 3800, icon = "🥯", dish = "bread", tint = "scone", cat = "dessert", eat = "hand", bites = 3, cook = 3, fx = "bake", effect = { Satiety = 12, Fun = 2 }, opts = { "here" } },
}
M.dessertcafe = {
	{ id = "americano", name = "아메리카노", price = 4700, icon = "☕", dish = "coffee", tint = "black", cat = "drink", eat = "sip", bites = 6, cook = 9, fx = "espresso", effect = { Energy = 22 }, opts = { "temp", "size", "shot", "here" } },
	{ id = "latte", name = "카페 라떼", price = 5200, icon = "🥛", dish = "coffee", tint = "latte", cat = "drink", eat = "sip", bites = 6, cook = 11, fx = "espresso", effect = { Energy = 16, Satiety = 4 }, opts = { "temp", "size", "shot", "here" } },
	{ id = "cheesecake", name = "뉴욕 치즈케이크", price = 7000, icon = "🍰", dish = "cake", tint = "cheese", cat = "dessert", eat = "fork", bites = 5, cook = 2, fx = "none", effect = { Satiety = 14, Fun = 8 }, stats = { happiness = 0.5 }, opts = { "here" } },
	{ id = "tiramisu", name = "티라미수", price = 7500, icon = "🍫", dish = "cake", tint = "tiramisu", cat = "dessert", eat = "fork", bites = 5, cook = 2, fx = "none", effect = { Satiety = 14, Fun = 8 }, stats = { happiness = 0.5 }, opts = { "here" } },
	{ id = "macaron", name = "마카롱 3구", price = 7500, icon = "🎨", dish = "macaron", cat = "dessert", eat = "hand", bites = 3, cook = 1, fx = "none", effect = { Fun = 8 }, stats = { happiness = 0.4, appearance = 0.05 }, opts = { "here" } },
}

-- 디저트 -----------------------------------------------------------------------------------------
M.gelato = {
	{ id = "pistachio", name = "피스타치오 젤라또", price = 5500, icon = "🟢", dish = "gelato", tint = "pistachio", cat = "dessert", eat = "lick", bites = 6, cook = 4, fx = "scoop", effect = { Fun = 10 }, stats = { happiness = 0.5 }, opts = { "cone" } },
	{ id = "strawberry", name = "딸기 젤라또", price = 5000, icon = "🍓", dish = "gelato", tint = "strawberry", cat = "dessert", eat = "lick", bites = 6, cook = 4, fx = "scoop", effect = { Fun = 10 }, stats = { happiness = 0.5 }, opts = { "cone" } },
	{ id = "choco", name = "다크 초코 젤라또", price = 5000, icon = "🍫", dish = "gelato", tint = "choco", cat = "dessert", eat = "lick", bites = 6, cook = 4, fx = "scoop", effect = { Fun = 10 }, stats = { happiness = 0.5 }, opts = { "cone" } },
	{ id = "double", name = "두 가지 맛 (더블)", price = 7500, icon = "🍨", dish = "gelato", tint = "double", cat = "dessert", eat = "lick", bites = 9, cook = 6, fx = "scoop", effect = { Fun = 14, Satiety = 6 }, stats = { happiness = 0.6 }, opts = { "cone" } },
}
M.churros = {
	{ id = "churros", name = "시나몬 츄러스", price = 4000, icon = "🥖", dish = "churros", cat = "dessert", eat = "stick", bites = 4, cook = 7, fx = "fry", effect = { Satiety = 10, Fun = 6 }, stats = { happiness = 0.3 } },
	{ id = "choco", name = "초코 딥 츄러스", price = 5000, icon = "🍫", dish = "churros", tint = "choco", cat = "dessert", eat = "stick", bites = 4, cook = 8, fx = "fry", effect = { Satiety = 10, Fun = 8 }, stats = { happiness = 0.4 } },
	{ id = "gelato", name = "젤라또 한 스쿱", price = 4500, icon = "🍨", dish = "gelato", tint = "vanilla", cat = "dessert", eat = "lick", bites = 5, cook = 3, fx = "scoop", effect = { Fun = 8 }, stats = { happiness = 0.4 }, opts = { "cone" } },
}
M.waffle = {
	{ id = "plain", name = "생크림 와플", price = 4500, icon = "🧇", dish = "waffle", cat = "dessert", eat = "hand", bites = 4, cook = 9, fx = "press", effect = { Satiety = 12, Fun = 6 }, stats = { happiness = 0.3 } },
	{ id = "icecream", name = "아이스크림 와플", price = 6000, icon = "🍦", dish = "waffle", tint = "icecream", cat = "dessert", eat = "hand", bites = 5, cook = 9, fx = "press", effect = { Satiety = 14, Fun = 8 }, stats = { happiness = 0.4 } },
	{ id = "gelato", name = "젤라또 컵", price = 5000, icon = "🍨", dish = "gelato", tint = "strawberry", cat = "dessert", eat = "lick", bites = 5, cook = 3, fx = "scoop", effect = { Fun = 8 }, stats = { happiness = 0.4 }, opts = { "cone" } },
}
M.tanghulu = {
	{ id = "strawberry", name = "딸기 탕후루", price = 4000, icon = "🍓", dish = "tanghulu", tint = "strawberry", cat = "dessert", eat = "stick", bites = 4, cook = 6, fx = "dip", effect = { Fun = 8 }, stats = { happiness = 0.3 } },
	{ id = "grape", name = "샤인머스캣 탕후루", price = 5000, icon = "🍇", dish = "tanghulu", tint = "grape", cat = "dessert", eat = "stick", bites = 5, cook = 6, fx = "dip", effect = { Fun = 9 }, stats = { happiness = 0.4 } },
	{ id = "mix", name = "모둠 탕후루", price = 5500, icon = "🍡", dish = "tanghulu", tint = "mix", cat = "dessert", eat = "stick", bites = 5, cook = 6, fx = "dip", effect = { Fun = 9 }, stats = { happiness = 0.4 } },
}
M.hotteok = {
	{ id = "ssiat", name = "씨앗호떡", price = 2000, desc = "부산 원조 · 견과류 가득", icon = "🥞", dish = "hotteok", cat = "dessert", eat = "hand", bites = 4, cook = 8, fx = "press", effect = { Satiety = 12, Fun = 6 }, stats = { happiness = 0.3 } },
	{ id = "cheese", name = "치즈 씨앗호떡", price = 2500, icon = "🧀", dish = "hotteok", tint = "cheese", cat = "dessert", eat = "hand", bites = 4, cook = 8, fx = "press", effect = { Satiety = 12, Fun = 7 }, stats = { happiness = 0.3 } },
	{ id = "sikhye", name = "식혜", price = 2000, icon = "🥤", dish = "takeout_ice", tint = "sikhye", cat = "drink", eat = "sip", bites = 4, cook = 1, fx = "pour", effect = { Energy = 4, Fun = 2 } },
}
M.bingsu = {
	{ id = "injeolmi", name = "인절미 빙수", price = 11000, desc = "콩고물 · 떡 · 아이스크림", icon = "🍧", dish = "bingsu", tint = "injeolmi", cat = "dessert", eat = "spoon", bites = 8, cook = 9, fx = "blend", share = true, effect = { Fun = 14, Satiety = 10 }, stats = { happiness = 0.6 } },
	{ id = "mango", name = "애플망고 빙수", price = 15000, icon = "🥭", dish = "bingsu", tint = "mango", cat = "dessert", eat = "spoon", bites = 8, cook = 9, fx = "blend", share = true, effect = { Fun = 16, Satiety = 10 }, stats = { happiness = 0.7 } },
	{ id = "patbingsu", name = "옛날 팥빙수", price = 9000, icon = "🫘", dish = "bingsu", tint = "pat", cat = "dessert", eat = "spoon", bites = 8, cook = 8, fx = "blend", share = true, effect = { Fun = 12, Satiety = 10 }, stats = { happiness = 0.5 } },
	{ id = "americano", name = "아메리카노", price = 4000, icon = "☕", dish = "coffee", tint = "black", cat = "drink", eat = "sip", bites = 6, cook = 8, fx = "espresso", effect = { Energy = 20 }, opts = { "temp", "here" } },
}

-- 셀프 진열 (bakery / cvs / retail): shelf -> items ------------------------------------------------
M.bakery = {
	{ id = "salt", name = "소금빵", price = 3200, icon = "🥐", dish = "bread", tint = "saltbread", cat = "bread", eat = "hand", bites = 3, effect = { Satiety = 14, Fun = 4 }, shelf = "bread" },
	{ id = "danpat", name = "단팥빵", price = 2800, icon = "🍞", dish = "bread", tint = "danpat", cat = "bread", eat = "hand", bites = 3, effect = { Satiety = 16, Fun = 3 }, shelf = "bread" },
	{ id = "croissant", name = "크루아상", price = 3800, icon = "🥐", dish = "bread", tint = "croissant", cat = "bread", eat = "hand", bites = 4, effect = { Satiety = 14, Fun = 3 }, shelf = "bread" },
	{ id = "eggtart", name = "에그타르트", price = 2500, icon = "🥧", dish = "bread", tint = "eggtart", cat = "bread", eat = "hand", bites = 2, effect = { Satiety = 8, Fun = 5 }, shelf = "case" },
	{ id = "cake", name = "조각 케이크", price = 5500, icon = "🍰", dish = "cake", tint = "strawberry", cat = "bread", eat = "fork", bites = 5, effect = { Satiety = 12, Fun = 8 }, stats = { happiness = 0.4 }, shelf = "case" },
	{ id = "milk", name = "흰 우유", price = 1500, icon = "🥛", dish = "milk", tint = "white", cat = "drink", eat = "sip", bites = 3, effect = { Satiety = 6 }, shelf = "fridge" },
	{ id = "coffee", name = "아메리카노 (테이크아웃)", price = 3000, icon = "☕", dish = "takeout_hot", tint = "black", cat = "drink", eat = "sip", bites = 5, effect = { Energy = 18 }, shelf = "counter" },
}
M.cvs = {
	{ id = "samgak", name = "참치마요 삼각김밥", price = 1400, icon = "🍙", dish = "samgak", cat = "food", eat = "hand", bites = 3, effect = { Satiety = 14 }, shelf = "food", unwrap = true },
	{ id = "dosirak", name = "제육 도시락", price = 5900, icon = "🍱", dish = "dosirak", cat = "food", eat = "chop", bites = 6, effect = { Satiety = 38, Energy = 4 }, stats = { stamina = 0.3 }, shelf = "food", heat = true },
	{ id = "cupramen", name = "컵라면 (큰사발)", price = 1700, icon = "🍜", dish = "cupramen", cat = "food", eat = "slurp", bites = 5, effect = { Satiety = 26, Fun = 3 }, shelf = "food", noodle = true },
	{ id = "kimbap", name = "참치 김밥", price = 3300, icon = "🍙", dish = "kimbap_roll", cat = "food", eat = "hand", bites = 4, effect = { Satiety = 22 }, shelf = "food" },
	{ id = "hotbar", name = "핫바", price = 2500, icon = "🌭", dish = "hotbar", cat = "food", eat = "stick", bites = 3, effect = { Satiety = 12 }, shelf = "steamer" },
	{ id = "jjinppang", name = "찐빵", price = 1800, icon = "🥟", dish = "jjinppang", cat = "food", eat = "hand", bites = 3, effect = { Satiety = 12 }, shelf = "steamer" },
	{ id = "banana", name = "바나나맛 우유", price = 1800, icon = "🍌", dish = "milk", tint = "banana", cat = "drink", eat = "sip", bites = 3, effect = { Satiety = 6, Fun = 4 }, stats = { happiness = 0.2 }, shelf = "fridge" },
	{ id = "cola", name = "콜라 500ml", price = 2400, icon = "🥤", dish = "bottle", tint = "cola", cat = "drink", eat = "sip", bites = 4, effect = { Energy = 6, Fun = 2 }, shelf = "fridge" },
	{ id = "water", name = "생수 500ml", price = 950, icon = "💧", dish = "bottle", tint = "water", cat = "drink", eat = "sip", bites = 3, effect = { Energy = 2 }, shelf = "fridge" },
	{ id = "canbeer", name = "무알콜 캔맥주 4캔", price = 12000, icon = "🥤", dish = "can", tint = "beer", cat = "drink", eat = "gulp", bites = 4, effect = { Fun = 6 }, stats = { happiness = 0.2 }, shelf = "fridge" },
	{ id = "icecream", name = "메로나", price = 1200, icon = "🍦", dish = "icebar", tint = "melon", cat = "snack", eat = "lick", bites = 3, effect = { Fun = 8 }, stats = { happiness = 0.2 }, shelf = "freezer" },
	{ id = "bbangbbare", name = "빵빠레", price = 1800, icon = "🍦", dish = "gelato", tint = "vanilla", cat = "snack", eat = "lick", bites = 4, effect = { Fun = 9 }, stats = { happiness = 0.2 }, shelf = "freezer" },
	{ id = "chips", name = "새우깡", price = 1600, icon = "🦐", dish = "chips", cat = "snack", eat = "hand", bites = 4, effect = { Satiety = 8, Fun = 4 }, shelf = "snack" },
	{ id = "choco", name = "초코파이", price = 700, icon = "🍫", dish = "chocopie", cat = "snack", eat = "hand", bites = 2, effect = { Satiety = 6, Fun = 3 }, shelf = "snack" },
	{ id = "toothbrush", name = "칫솔 세트", price = 2500, icon = "🪥", dish = "goods", tint = "toothbrush", cat = "goods", eat = "none", effect = { Hygiene = 10 }, shelf = "goods" },
	{ id = "sunscreen", name = "선크림", price = 9800, icon = "🧴", dish = "goods", tint = "sunscreen", cat = "goods", eat = "none", effect = { Hygiene = 4 }, stats = { appearance = 0.2 }, shelf = "goods" },
}
M.cosmetics = {
	{ id = "lip", name = "틴트 (코랄)", price = 11000, icon = "💄", dish = "goods", tint = "lip", cat = "goods", eat = "none", stats = { appearance = 0.4 }, shelf = "makeup", tester = true },
	{ id = "cushion", name = "쿠션 팩트", price = 26000, icon = "🪞", dish = "goods", tint = "cushion", cat = "goods", eat = "none", stats = { appearance = 0.6 }, shelf = "makeup", tester = true },
	{ id = "perfume", name = "바다 향수 (30ml)", price = 39000, icon = "🌊", dish = "goods", tint = "perfume", cat = "goods", eat = "none", stats = { appearance = 0.6, popularity = 0.2 }, shelf = "makeup", tester = true },
	{ id = "mask", name = "마스크팩 10매", price = 15000, icon = "🧖", dish = "goods", tint = "mask", cat = "goods", eat = "none", effect = { Hygiene = 12 }, stats = { appearance = 0.3 }, shelf = "skin" },
	{ id = "sunscreen", name = "선크림 SPF50+", price = 18000, icon = "🧴", dish = "goods", tint = "sunscreen", cat = "goods", eat = "none", effect = { Hygiene = 4 }, stats = { appearance = 0.3 }, shelf = "skin" },
	{ id = "vitamin", name = "비타민 젤리", price = 8000, icon = "🍬", dish = "goods", tint = "vitamin", cat = "goods", eat = "none", effect = { Energy = 6 }, shelf = "health" },
}
M.souvenir = {
	{ id = "magnet", name = "광안대교 자석", price = 6000, icon = "🌉", dish = "goods", tint = "magnet", cat = "goods", eat = "none", stats = { happiness = 0.3 }, shelf = "goods" },
	{ id = "tshirt", name = "I ♥ BUSAN 티셔츠", price = 22000, icon = "👕", dish = "goods", tint = "shirt", cat = "goods", eat = "none", stats = { happiness = 0.4, popularity = 0.1 }, shelf = "goods" },
	{ id = "keyring", name = "갈매기 키링", price = 8000, icon = "🕊️", dish = "goods", tint = "keyring", cat = "goods", eat = "none", stats = { happiness = 0.3 }, shelf = "goods" },
	{ id = "postcard", name = "야경 엽서 세트", price = 5000, icon = "🖼️", dish = "goods", tint = "postcard", cat = "goods", eat = "none", stats = { happiness = 0.2 }, shelf = "goods" },
	{ id = "eomukbox", name = "부산 어묵 선물세트", price = 25000, icon = "🎁", dish = "goods", tint = "gift", cat = "goods", eat = "none", stats = { happiness = 0.3, popularity = 0.2 }, shelf = "goods" },
}
M.beach = {
	{ id = "tube", name = "튜브 대여 (1시간)", price = 10000, icon = "🛟", dish = "goods", tint = "tube", cat = "goods", eat = "none", stats = { happiness = 0.4 }, shelf = "goods" },
	{ id = "mat", name = "돗자리", price = 8000, icon = "🟦", dish = "goods", tint = "mat", cat = "goods", eat = "none", stats = { happiness = 0.2 }, shelf = "goods" },
	{ id = "firework", name = "불꽃놀이 막대", price = 5000, icon = "🎇", dish = "goods", tint = "firework", cat = "goods", eat = "none", effect = { Fun = 10 }, stats = { happiness = 0.3 }, shelf = "goods" },
	{ id = "sunglass", name = "선글라스", price = 15000, icon = "🕶️", dish = "goods", tint = "sunglass", cat = "goods", eat = "none", stats = { appearance = 0.4 }, shelf = "goods" },
	{ id = "sunscreen", name = "선크림", price = 12000, icon = "🧴", dish = "goods", tint = "sunscreen", cat = "goods", eat = "none", effect = { Hygiene = 4 }, stats = { appearance = 0.2 }, shelf = "goods" },
}
M.flower = {
	{ id = "bouquet", name = "미니 꽃다발", price = 15000, icon = "💐", dish = "goods", tint = "bouquet", cat = "goods", eat = "none", stats = { happiness = 0.5, popularity = 0.2 }, shelf = "goods" },
	{ id = "candle", name = "바다 향 캔들", price = 18000, icon = "🕯️", dish = "goods", tint = "candle", cat = "goods", eat = "none", stats = { happiness = 0.4 }, shelf = "goods" },
	{ id = "rose", name = "장미 한 송이", price = 4000, icon = "🌹", dish = "goods", tint = "rose", cat = "goods", eat = "none", stats = { popularity = 0.2 }, shelf = "goods" },
}
M.books = {
	{ id = "novel", name = "바다 소설", price = 14000, icon = "📘", dish = "goods", tint = "book", cat = "goods", eat = "none", effect = { Fun = 10 }, stats = { happiness = 0.4 }, shelf = "goods" },
	{ id = "photo", name = "광안리 사진집", price = 28000, icon = "📷", dish = "goods", tint = "book", cat = "goods", eat = "none", effect = { Fun = 8 }, stats = { happiness = 0.5 }, shelf = "goods" },
	{ id = "diary", name = "여행 다이어리", price = 9000, icon = "📓", dish = "goods", tint = "book", cat = "goods", eat = "none", effect = { Fun = 4 }, shelf = "goods" },
}
M.bottle = {
	{ id = "wine", name = "스파클링 포도주스 (선물용)", price = 19000, icon = "🧃", dish = "goods", tint = "wine", cat = "goods", eat = "none", stats = { happiness = 0.4 }, shelf = "goods" },
	{ id = "craftcan", name = "수제 무알콜 맥주 캔", price = 6500, icon = "🥤", dish = "can", tint = "beer", cat = "drink", eat = "gulp", bites = 4, effect = { Fun = 6 }, stats = { happiness = 0.2 }, shelf = "goods" },
	{ id = "makgeolli", name = "부산 전통 식혜 (병)", price = 2500, icon = "🥛", dish = "bottle", tint = "makgeolli", cat = "drink", eat = "gulp", bites = 4, effect = { Fun = 5 }, shelf = "goods" },
}
M.vintage = {
	{ id = "jacket", name = "빈티지 데님 재킷", price = 45000, icon = "🧥", dish = "goods", tint = "shirt", cat = "goods", eat = "none", stats = { appearance = 0.8, popularity = 0.2 }, shelf = "goods" },
	{ id = "cap", name = "볼캡", price = 18000, icon = "🧢", dish = "goods", tint = "cap", cat = "goods", eat = "none", stats = { appearance = 0.4 }, shelf = "goods" },
	{ id = "lp", name = "중고 LP", price = 25000, icon = "💿", dish = "goods", tint = "lp", cat = "goods", eat = "none", effect = { Fun = 8 }, shelf = "goods" },
}

-- service shops -----------------------------------------------------------------------------------
M.pharmacy = {
	{ id = "fatigue", name = "피로회복제", price = 1000, desc = "피곤할 때 · 갈색 병 한 병", icon = "🧃", dish = "medicine", tint = "drink", cat = "goods", eat = "shot", bites = 1, effect = { Energy = 14 }, symptom = "tired" },
	{ id = "headache", name = "두통약", price = 3000, desc = "머리 아플 때", icon = "💊", dish = "medicine", tint = "pill", cat = "goods", eat = "shot", bites = 1, effect = { Fun = 4, Energy = 4 }, symptom = "head" },
	{ id = "digest", name = "소화제 드링크", price = 2500, desc = "국밥 · 치킨 먹고 한 병", icon = "🥤", dish = "medicine", tint = "drink", cat = "goods", eat = "shot", bites = 1, effect = { Satiety = -10, Energy = 4 }, symptom = "stomach" },
	{ id = "patch", name = "근육 파스", price = 4000, desc = "어깨 · 다리 뭉쳤을 때", icon = "🩹", dish = "goods", tint = "patch", cat = "goods", eat = "none", effect = { Energy = 8 }, stats = { stamina = 0.3 }, symptom = "muscle" },
	{ id = "cold", name = "종합 감기약", price = 5000, desc = "콧물 · 기침", icon = "🤧", dish = "medicine", tint = "pill", cat = "goods", eat = "shot", bites = 1, effect = { Energy = 6 }, symptom = "cold" },
	{ id = "hangover", name = "밤샘 회복 드링크", price = 4500, desc = "어젯밤 늦게까지 놀았다면", icon = "🍋", dish = "medicine", tint = "drink", cat = "goods", eat = "shot", bites = 1, effect = { Energy = 12, Fun = 2 }, symptom = "hangover" },
}
SS.SYMPTOMS = {
	{ id = "tired", label = "피곤해요", icon = "😪", line = "요즘 많이 피곤하시죠? 피로회복제 한 병 드세요~" },
	{ id = "head", label = "머리가 아파요", icon = "🤕", line = "물이랑 같이 한 알 드시고 좀 쉬세요" },
	{ id = "stomach", label = "속이 더부룩해요", icon = "🤢", line = "과식하셨구나~ 소화제 드링크 드릴게요" },
	{ id = "muscle", label = "근육이 뭉쳤어요", icon = "💪", line = "운동 많이 하셨나 봐요. 파스 붙이세요~" },
	{ id = "cold", label = "감기 기운이 있어요", icon = "🤧", line = "바닷바람 조심하세요~ 따뜻하게 주무시고요" },
	{ id = "hangover", label = "밤새 놀아서 피곤해요", icon = "😪", line = "어제 늦게까지 노셨구나~ 이거 드시고 국밥 한 그릇 하세요!" },
}
M.laundry = {
	{ id = "shirt", name = "셔츠 드라이", price = 4000, desc = "다음 방문 때 찾아가요 (2분)", icon = "👔", dish = "goods", tint = "shirt", cat = "goods", eat = "none", effect = { Hygiene = 8 }, stats = { appearance = 0.3 }, wait = 120 },
	{ id = "suit", name = "정장 한 벌", price = 12000, desc = "빳빳하게 (3분)", icon = "🤵", dish = "goods", tint = "suit", cat = "goods", eat = "none", effect = { Hygiene = 10 }, stats = { appearance = 0.6, popularity = 0.1 }, wait = 180 },
	{ id = "padding", name = "패딩 세탁", price = 15000, desc = "뽀송하게 (3분)", icon = "🧥", dish = "goods", tint = "padding", cat = "goods", eat = "none", effect = { Hygiene = 12 }, stats = { appearance = 0.4 }, wait = 180 },
}

M.salon = {
	{ id = "cut", name = "커트", price = 15000, desc = "다듬기 · 샴푸 포함", icon = "✂️", dish = "goods", tint = "cap", cat = "service", eat = "none", seconds = 8, stats = { appearance = 0.8 }, effect = { Hygiene = 6 } },
	{ id = "perm", name = "볼륨 펌", price = 45000, desc = "자연스러운 웨이브", icon = "🌀", dish = "goods", tint = "cap", cat = "service", eat = "none", seconds = 12, stats = { appearance = 1.5, popularity = 0.2 }, effect = { Hygiene = 6 } },
	{ id = "dye", name = "염색 (애쉬 브라운)", price = 50000, desc = "광안리 햇살에 빛나는 색", icon = "🎨", dish = "goods", tint = "cap", cat = "service", eat = "none", seconds = 12, stats = { appearance = 1.6, popularity = 0.3 }, effect = { Hygiene = 6 } },
	{ id = "care", name = "두피 케어", price = 20000, desc = "시원한 스파", icon = "💆", dish = "goods", tint = "mask", cat = "service", eat = "none", seconds = 10, stats = { happiness = 0.6 }, effect = { Hygiene = 14, Energy = 6 } },
}
M.clothing = {
	{ id = "tee", name = "오버핏 반팔티", price = 29000, icon = "👕", dish = "goods", tint = "shirt", cat = "goods", eat = "none", stats = { appearance = 0.5 }, shelf = "goods", fitting = true },
	{ id = "shirt", name = "린넨 셔츠", price = 49000, icon = "👔", dish = "goods", tint = "shirt", cat = "goods", eat = "none", stats = { appearance = 0.8 }, shelf = "goods", fitting = true },
	{ id = "dress", name = "썸머 원피스", price = 59000, icon = "👗", dish = "goods", tint = "bouquet", cat = "goods", eat = "none", stats = { appearance = 1.0, popularity = 0.2 }, shelf = "goods", fitting = true },
	{ id = "shorts", name = "보드 숏츠", price = 35000, icon = "🩳", dish = "goods", tint = "mat", cat = "goods", eat = "none", stats = { appearance = 0.4, happiness = 0.2 }, shelf = "goods", fitting = true },
	{ id = "cap", name = "버킷햇", price = 25000, icon = "👒", dish = "goods", tint = "cap", cat = "goods", eat = "none", stats = { appearance = 0.4 }, shelf = "goods", fitting = true },
}

-- the GwShop shops (prices from the map's own GwangalliShopsShared where present) -----------------
M.gw_gukbap = M.gukbap
M.gw_chicken = M.chicken
M.gw_snack = M.snack
M.gw_pharmacy = M.pharmacy
M.gw_surf = M.beach
M.gw_clothing = M.clothing
M.gw_salon = M.salon

-- add new menus BELOW; never rename an item id (bills, NPC orders and saved tickets use them)

-- Annex shops (the storefronts that were only a facade) ------------------------------------------
-- service items: eat = "none"; seconds = a timed service (act = the animation, skill = a practice
-- counter shown to the player); symptom = the consult answer (병원 · 약국)
M.chinese = {
	{ id = "jjajang", name = "짜장면", price = 6000, desc = "춘장 듬뿍 · 단무지", icon = "🍜", dish = "jjajang", cat = "main", eat = "slurp", bites = 6, cook = 8, fx = "boil", effect = { Satiety = 34, Fun = 4 }, stats = { happiness = 0.3 } },
	{ id = "ganjjajang", name = "간짜장", price = 7000, desc = "센 불에 볶은 소스 · 계란 프라이", icon = "🍳", dish = "jjajang", tint = "gan", cat = "main", eat = "slurp", bites = 6, cook = 9, fx = "fry", effect = { Satiety = 36, Fun = 5 }, stats = { happiness = 0.3 } },
	{ id = "jjamppong", name = "짬뽕", price = 7500, desc = "얼큰한 해물 국물", icon = "🌶️", dish = "jjamppong", cat = "main", eat = "slurp", bites = 6, cook = 9, fx = "boil", effect = { Satiety = 34, Energy = 6, Fun = 4 }, stats = { happiness = 0.3 } },
	{ id = "whitejjamppong", name = "백짬뽕", price = 8500, desc = "맑고 시원한 해물 국물", icon = "🦐", dish = "jjamppong", tint = "white", cat = "main", eat = "slurp", bites = 6, cook = 9, fx = "boil", effect = { Satiety = 34, Energy = 6 }, stats = { happiness = 0.3 } },
	{ id = "tangsuyuk", name = "탕수육 (소)", price = 16000, desc = "부먹? 찍먹? 같이 먹어요", icon = "🍖", dish = "tangsuyuk", cat = "side", eat = "chop", bites = 8, cook = 12, fx = "fry", share = true, effect = { Satiety = 30, Fun = 8 }, stats = { happiness = 0.5 } },
	{ id = "bokkeumbap", name = "볶음밥", price = 7500, desc = "불맛 · 짜장 소스 조금", icon = "🍚", dish = "bokkeumbap", cat = "main", eat = "spoon", bites = 6, cook = 8, fx = "fry", effect = { Satiety = 36 } },
	{ id = "gunmandu", name = "군만두", price = 5000, icon = "🥟", dish = "mandu", tint = "gyoza", cat = "side", eat = "chop", bites = 5, cook = 7, fx = "fry", share = true, effect = { Satiety = 18, Fun = 3 } },
	{ id = "kaoliang", name = "매실 에이드 (작은 병)", price = 9000, icon = "🧃", dish = "shotglass", cat = "alcohol", eat = "shot", bites = 3, cook = 1, fx = "pour", share = true, effect = { Fun = 7 }, stats = { happiness = 0.2 } },
}
M.mara = {
	{ id = "mara", name = "마라탕 (1인)", price = 12000, desc = "맵기 2단계 · 넓적당면 · 소고기", icon = "🌶️", dish = "mara", cat = "main", eat = "slurp", bites = 7, cook = 10, fx = "boil", effect = { Satiety = 36, Energy = 6, Fun = 6 }, stats = { happiness = 0.4 } },
	{ id = "xiangguo", name = "마라샹궈", price = 18000, desc = "볶음 마라 · 둘이 먹어요", icon = "🔥", dish = "mara", tint = "xiang", cat = "main", eat = "chop", bites = 8, cook = 12, fx = "fry", share = true, effect = { Satiety = 38, Fun = 8 }, stats = { happiness = 0.5 } },
	{ id = "guobaorou", name = "꿔바로우", price = 14000, desc = "찹쌀 탕수육 · 새콤달콤", icon = "🍖", dish = "tangsuyuk", tint = "dip", cat = "side", eat = "chop", bites = 7, cook = 10, fx = "fry", share = true, effect = { Satiety = 26, Fun = 7 }, stats = { happiness = 0.4 } },
	{ id = "rice", name = "공기밥", price = 1000, icon = "🍚", dish = "rice", cat = "side", eat = "spoon", bites = 4, cook = 1, fx = "none", effect = { Satiety = 14 } },
}
M.pho = {
	{ id = "pho", name = "소고기 쌀국수", price = 9500, desc = "진한 육수 · 숙주 · 고수", icon = "🍜", dish = "pho", cat = "main", eat = "slurp", bites = 6, cook = 8, fx = "boil", effect = { Satiety = 32, Energy = 6 }, stats = { happiness = 0.3 } },
	{ id = "friedrice", name = "파인애플 볶음밥", price = 10000, icon = "🍍", dish = "bokkeumbap", cat = "main", eat = "spoon", bites = 6, cook = 8, fx = "fry", effect = { Satiety = 34 } },
	{ id = "springroll", name = "짜조 (튀김 만두)", price = 6000, icon = "🥟", dish = "mandu", tint = "gyoza", cat = "side", eat = "chop", bites = 4, cook = 6, fx = "fry", share = true, effect = { Satiety = 16, Fun = 3 } },
	{ id = "icetea", name = "연유 커피 (아이스)", price = 4500, icon = "🧋", dish = "takeout_ice", tint = "latte", cat = "drink", eat = "sip", bites = 5, cook = 2, fx = "pour", effect = { Energy = 14 } },
}
M.jokbal = {
	{ id = "jokbal", name = "족발 (중)", price = 35000, desc = "쫀득한 앞다리 · 쌈 채소", icon = "🍖", dish = "jokbal", cat = "main", eat = "chop", bites = 10, cook = 10, fx = "chop", share = true, effect = { Satiety = 44, Fun = 6 }, stats = { stamina = 0.4, happiness = 0.4 } },
	{ id = "bossam", name = "보쌈 (중)", price = 33000, desc = "야들야들 수육 · 김장 김치", icon = "🥬", dish = "jokbal", tint = "bossam", cat = "main", eat = "chop", bites = 10, cook = 10, fx = "chop", share = true, effect = { Satiety = 42, Fun = 6 }, stats = { stamina = 0.4, happiness = 0.4 } },
	{ id = "makguksu", name = "막국수", price = 8000, icon = "🍜", dish = "milmyeon", tint = "bibim", cat = "side", eat = "slurp", bites = 6, cook = 6, fx = "boil", effect = { Satiety = 24, Energy = 4 } },
	{ id = "soju", name = "청포도 소다", price = 5000, icon = "🍇", dish = "soju", cat = "alcohol", eat = "shot", bites = 6, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
}
M.juk = {
	{ id = "jeonbok", name = "전복죽", price = 14000, desc = "고소하고 든든하게", icon = "🥣", dish = "ttuk", tint = "kongnamul", cat = "main", eat = "spoon", bites = 6, cook = 8, fx = "boil", effect = { Satiety = 30, Energy = 10 }, stats = { stamina = 0.3 } },
	{ id = "hobak", name = "단호박죽", price = 9000, icon = "🎃", dish = "ttuk", tint = "kongnamul", cat = "main", eat = "spoon", bites = 6, cook = 6, fx = "boil", effect = { Satiety = 26, Energy = 6 } },
	{ id = "bibim", name = "돌솥 비빔밥", price = 10000, icon = "🍚", dish = "don", cat = "main", eat = "spoon", bites = 6, cook = 8, fx = "fry", effect = { Satiety = 36 } },
}
M.izakaya = {
	{ id = "sake", name = "따뜻한 유자차", price = 9000, icon = "🍵", dish = "sake", cat = "alcohol", eat = "shot", bites = 4, cook = 4, fx = "pour", share = true, effect = { Fun = 7 }, stats = { happiness = 0.3 } },
	{ id = "highball", name = "제로 하이볼", price = 8000, desc = "레몬 · 탄산 가득", icon = "🍋", dish = "highball", cat = "alcohol", eat = "sip", bites = 5, cook = 3, fx = "pour", effect = { Fun = 7 }, stats = { happiness = 0.3 } },
	{ id = "yakitori", name = "꼬치 모둠 (5개)", price = 15000, icon = "🍢", dish = "skewers", cat = "side", eat = "stick", bites = 5, cook = 10, fx = "fry", share = true, effect = { Satiety = 26, Fun = 5 } },
	{ id = "karaage", name = "가라아게", price = 13000, icon = "🍗", dish = "chicken", tint = "fried", cat = "side", eat = "hand", bites = 6, cook = 9, fx = "fry", share = true, effect = { Satiety = 24, Fun = 5 } },
	{ id = "ramen", name = "돈코츠 라멘", price = 10000, icon = "🍜", dish = "ramen", cat = "main", eat = "slurp", bites = 6, cook = 9, fx = "boil", effect = { Satiety = 34 } },
}
M.hof = {
	{ id = "draft", name = "무알콜 생맥 500cc", price = 4500, desc = "살얼음 잔", icon = "🥤", dish = "pint", tint = "lager", cat = "alcohol", eat = "gulp", bites = 5, cook = 3, fx = "tap", tap = true, effect = { Fun = 6 }, stats = { happiness = 0.3 } },
	{ id = "nogari", name = "노가리 (5마리)", price = 6000, desc = "마요 + 청양고추", icon = "🐟", dish = "squid", tint = "grilled", cat = "side", eat = "hand", bites = 5, cook = 6, fx = "fry", share = true, effect = { Satiety = 12, Fun = 4 } },
	{ id = "fried", name = "옛날 통닭 반 마리", price = 10000, icon = "🍗", dish = "chicken", tint = "whole", cat = "side", eat = "hand", bites = 6, cook = 12, fx = "fry", share = true, effect = { Satiety = 26, Fun = 5 }, stats = { happiness = 0.3 } },
	{ id = "fries", name = "감자튀김", price = 7000, icon = "🍟", dish = "fries", cat = "side", eat = "hand", bites = 6, cook = 7, fx = "fry", share = true, effect = { Satiety = 16, Fun = 3 } },
	{ id = "soju", name = "청포도 소다", price = 5000, icon = "🍇", dish = "soju", cat = "alcohol", eat = "shot", bites = 6, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
}
M.wine = {
	{ id = "red", name = "스파클링 포도주스 (레드)", price = 11000, icon = "🧃", dish = "glass", tint = "wine", cat = "alcohol", eat = "sip", bites = 5, cook = 2, fx = "pour", effect = { Fun = 7 }, stats = { happiness = 0.3, appearance = 0.1 } },
	{ id = "white", name = "스파클링 포도주스 (화이트)", price = 11000, icon = "🥂", dish = "glass", tint = "white_wine", cat = "alcohol", eat = "sip", bites = 5, cook = 2, fx = "pour", effect = { Fun = 7 }, stats = { happiness = 0.3 } },
	{ id = "cheese", name = "치즈 플래터", price = 18000, icon = "🧀", dish = "cake", tint = "cheese", cat = "side", eat = "fork", bites = 6, cook = 5, fx = "chop", share = true, effect = { Satiety = 16, Fun = 5 } },
	{ id = "pasta", name = "알리오 올리오", price = 16000, icon = "🍝", dish = "kalguksu", cat = "main", eat = "fork", bites = 6, cook = 9, fx = "boil", effect = { Satiety = 30 } },
}
M.pizza = {
	{ id = "pepperoni", name = "페퍼로니 피자", price = 19000, desc = "화덕에서 90초", icon = "🍕", dish = "pizza", cat = "main", eat = "hand", bites = 8, cook = 12, fx = "bake", share = true, effect = { Satiety = 40, Fun = 6 }, stats = { happiness = 0.4 } },
	{ id = "margherita", name = "마르게리따", price = 17000, icon = "🍕", dish = "pizza", cat = "main", eat = "hand", bites = 8, cook = 12, fx = "bake", share = true, effect = { Satiety = 38, Fun = 5 }, stats = { happiness = 0.4 } },
	{ id = "fries", name = "웨지 감자", price = 6000, icon = "🍟", dish = "fries", cat = "side", eat = "hand", bites = 5, cook = 6, fx = "fry", effect = { Satiety = 16 } },
	{ id = "cola", name = "콜라", price = 2500, icon = "🥤", dish = "glass", tint = "cola", cat = "drink", eat = "sip", bites = 4, cook = 1, fx = "pour", effect = { Energy = 4, Fun = 2 } },
}
M.toast = {
	{ id = "hamcheese", name = "햄치즈 토스트", price = 4500, desc = "달달한 철판 토스트", icon = "🥪", dish = "sub", tint = "egg", cat = "main", eat = "hand", bites = 4, cook = 5, fx = "fry", effect = { Satiety = 24, Fun = 3 } },
	{ id = "bulgogi", name = "불고기 토스트", price = 5500, icon = "🥪", dish = "sub", cat = "main", eat = "hand", bites = 4, cook = 5, fx = "fry", effect = { Satiety = 28 } },
	{ id = "icecoffee", name = "아이스 아메리카노", price = 2500, icon = "🧊", dish = "takeout_ice", tint = "black", cat = "drink", eat = "sip", bites = 5, cook = 2, fx = "pour", effect = { Energy = 16 } },
}
M.dosirak = {
	{ id = "chicken_mayo", name = "치킨마요", price = 4300, desc = "한솥 스테디셀러", icon = "🍱", dish = "don", cat = "main", eat = "spoon", bites = 6, cook = 5, fx = "fry", effect = { Satiety = 34 } },
	{ id = "jeyuk", name = "제육 도시락", price = 5900, icon = "🍱", dish = "dosirak", cat = "main", eat = "chop", bites = 6, cook = 5, fx = "fry", effect = { Satiety = 38, Energy = 4 }, stats = { stamina = 0.2 } },
	{ id = "miso", name = "미소된장국", price = 1000, icon = "🥣", dish = "soup_cup", cat = "side", eat = "sip", bites = 3, cook = 1, fx = "pour", effect = { Energy = 4 } },
}
M.gangjeong = {
	{ id = "cup", name = "닭강정 컵 (중)", price = 7000, desc = "달콤 바삭 · 들고 다니며", icon = "🍗", dish = "chicken", tint = "yangnyeom", cat = "main", eat = "hand", bites = 6, cook = 8, fx = "fry", effect = { Satiety = 26, Fun = 6 }, stats = { happiness = 0.3 } },
	{ id = "box", name = "닭강정 한 박스", price = 18000, icon = "📦", dish = "chicken", tint = "yangnyeom", cat = "main", eat = "hand", bites = 10, cook = 12, fx = "fry", share = true, effect = { Satiety = 40, Fun = 8 }, stats = { happiness = 0.5 } },
	{ id = "cola", name = "캔 콜라", price = 1500, icon = "🥤", dish = "can", cat = "drink", eat = "sip", bites = 3, cook = 1, fx = "none", effect = { Energy = 4, Fun = 2 } },
}
M.nakgopsae = {
	{ id = "nakgopsae", name = "낙곱새 (2인)", price = 26000, desc = "낙지 · 곱창 · 새우 전골", icon = "🦑", dish = "pot", tint = "spicy", cat = "main", eat = "spoon", bites = 10, cook = 12, fx = "boil", share = true, effect = { Satiety = 40, Energy = 8, Fun = 6 }, stats = { stamina = 0.4, happiness = 0.4 } },
	{ id = "rice", name = "볶음밥 추가", price = 3000, icon = "🍚", dish = "bokkeumbap", cat = "side", eat = "spoon", bites = 5, cook = 6, fx = "fry", share = true, effect = { Satiety = 20 } },
	{ id = "soju", name = "청포도 소다", price = 5000, icon = "🍇", dish = "soju", cat = "alcohol", eat = "shot", bites = 6, cook = 1, fx = "none", share = true, effect = { Fun = 6 }, stats = { happiness = 0.2 } },
}
-- 상점 (pick: 진열대에서 고르고 계산대)
M.daiso = {
	{ id = "basket", name = "수납 바구니", price = 2000, icon = "🧺", dish = "goods", tint = "daiso", cat = "goods", eat = "none", stats = { happiness = 0.1 }, shelf = "goods" },
	{ id = "tumbler", name = "텀블러", price = 5000, icon = "🥤", dish = "goods", tint = "mug", cat = "goods", eat = "none", stats = { happiness = 0.2 }, shelf = "goods" },
	{ id = "towel", name = "비치 타월", price = 3000, icon = "🏖️", dish = "goods", tint = "towel", cat = "goods", eat = "none", effect = { Hygiene = 6 }, shelf = "goods" },
	{ id = "fan", name = "휴대용 선풍기", price = 5000, icon = "🌀", dish = "goods", tint = "phone", cat = "goods", eat = "none", effect = { Energy = 4 }, stats = { happiness = 0.2 }, shelf = "goods" },
}
M.fruit = {
	{ id = "strawberry", name = "딸기 한 팩", price = 9000, icon = "🍓", dish = "goods", tint = "fruit", cat = "goods", eat = "none", effect = { Satiety = 10, Fun = 6 }, stats = { happiness = 0.2 }, shelf = "goods" },
	{ id = "watermelon", name = "수박 반 통", price = 12000, icon = "🍉", dish = "goods", tint = "fruit", cat = "goods", eat = "none", effect = { Satiety = 16, Energy = 6, Fun = 6 }, shelf = "goods" },
	{ id = "peach", name = "복숭아 4개", price = 10000, icon = "🍑", dish = "goods", tint = "fruit", cat = "goods", eat = "none", effect = { Satiety = 10, Fun = 4 }, shelf = "goods" },
}
M.butcher = {
	{ id = "samgyeop", name = "삼겹살 600g", price = 16000, icon = "🥓", dish = "goods", tint = "meat", cat = "goods", eat = "none", effect = { Satiety = 20 }, stats = { stamina = 0.3 }, shelf = "goods" },
	{ id = "hanwoo", name = "한우 등심 300g", price = 38000, icon = "🥩", dish = "goods", tint = "meat", cat = "goods", eat = "none", effect = { Satiety = 22 }, stats = { stamina = 0.6, happiness = 0.3 }, shelf = "goods" },
}
M.banchan = {
	{ id = "set3", name = "반찬 3종 세트", price = 10000, icon = "🥗", dish = "goods", tint = "banchan", cat = "goods", eat = "none", effect = { Satiety = 14 }, stats = { stamina = 0.2 }, shelf = "goods" },
	{ id = "kimchi", name = "포기김치 1kg", price = 12000, icon = "🥬", dish = "goods", tint = "banchan", cat = "goods", eat = "none", effect = { Satiety = 10 }, shelf = "goods" },
}
M.stationery = {
	{ id = "pen", name = "볼펜 세트", price = 3000, icon = "🖊️", dish = "goods", tint = "pencil", cat = "goods", eat = "none", stats = { happiness = 0.1 }, shelf = "goods" },
	{ id = "note", name = "스프링 노트", price = 2000, icon = "📓", dish = "goods", tint = "book", cat = "goods", eat = "none", stats = { happiness = 0.1 }, shelf = "goods" },
	{ id = "sticker", name = "캐릭터 스티커", price = 1500, icon = "⭐", dish = "goods", tint = "nail", cat = "goods", eat = "none", effect = { Fun = 4 }, shelf = "goods" },
}
M.hardware = {
	{ id = "tools", name = "공구 세트", price = 25000, icon = "🧰", dish = "goods", tint = "tool", cat = "goods", eat = "none", stats = { stamina = 0.1 }, shelf = "goods" },
	{ id = "bulb", name = "LED 전구", price = 4000, icon = "💡", dish = "goods", tint = "tool", cat = "goods", eat = "none", stats = { happiness = 0.1 }, shelf = "goods" },
}
M.optical = {
	{ id = "glasses", name = "뿔테 안경 맞추기", price = 69000, icon = "👓", dish = "goods", tint = "glasses", cat = "goods", eat = "none", stats = { appearance = 0.6 }, shelf = "goods" },
	{ id = "sunglass", name = "편광 선글라스", price = 49000, icon = "🕶️", dish = "goods", tint = "sunglass", cat = "goods", eat = "none", stats = { appearance = 0.5 }, shelf = "goods" },
	{ id = "lens", name = "원데이 렌즈 30P", price = 28000, icon = "👁️", dish = "goods", tint = "glasses", cat = "goods", eat = "none", stats = { appearance = 0.3 }, shelf = "goods" },
}
M.phone = {
	{ id = "case", name = "광안대교 폰 케이스", price = 15000, icon = "📱", dish = "goods", tint = "phone", cat = "goods", eat = "none", stats = { appearance = 0.2, happiness = 0.1 }, shelf = "goods" },
	{ id = "charger", name = "고속 충전기", price = 19000, icon = "🔌", dish = "goods", tint = "phone", cat = "goods", eat = "none", effect = { Energy = 2 }, shelf = "goods" },
	{ id = "earbuds", name = "무선 이어폰", price = 89000, icon = "🎧", dish = "goods", tint = "phone", cat = "goods", eat = "none", effect = { Fun = 10 }, stats = { happiness = 0.4 }, shelf = "goods" },
}
-- 미용 (네일 · 왁싱)
M.nail = {
	{ id = "gel", name = "젤네일 (원컬러)", price = 35000, desc = "광안리 바다색", icon = "💅", dish = "goods", tint = "nail", cat = "service", eat = "none", seconds = 10, stats = { appearance = 0.8 }, effect = { Hygiene = 4 } },
	{ id = "lash", name = "속눈썹 펌", price = 40000, icon = "👁️", dish = "goods", tint = "nail", cat = "service", eat = "none", seconds = 10, stats = { appearance = 1.0 }, effect = { Hygiene = 4 } },
	{ id = "care", name = "피부 관리 (60분)", price = 60000, icon = "🧖", dish = "goods", tint = "mask", cat = "service", eat = "none", seconds = 14, stats = { appearance = 1.2, happiness = 0.3 }, effect = { Hygiene = 16, Energy = 8 } },
}
-- 병원 · 의원 (상담: 증상 -> 진료)
M.clinic = {
	{ id = "cold", name = "감기 진료", price = 5000, desc = "진찰 · 처방전", icon = "🤧", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 8, act = "treat", symptom = "cold", effect = { Energy = 12 }, stats = { stamina = 0.2 } },
	{ id = "drip", name = "영양 수액", price = 30000, desc = "피로 싹 · 20분 누워 있기", icon = "💧", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 14, act = "treat", symptom = "tired", effect = { Energy = 34 }, stats = { stamina = 0.6 } },
	{ id = "head", name = "두통 진료", price = 5000, icon = "🤕", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 8, act = "treat", symptom = "head", effect = { Energy = 8, Fun = 4 } },
	{ id = "stomach", name = "소화기 진료", price = 5000, icon = "🤢", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 8, act = "treat", symptom = "stomach", effect = { Satiety = -16, Energy = 6 } },
	{ id = "physio", name = "물리 치료", price = 8000, desc = "핫팩 · 전기 자극", icon = "💪", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 12, act = "treat", symptom = "muscle", effect = { Energy = 16 }, stats = { stamina = 0.4 } },
	{ id = "hangover", name = "밤샘 회복 수액", price = 25000, icon = "💧", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 12, act = "treat", symptom = "hangover", effect = { Energy = 26, Fun = 4 } },
	{ id = "checkup", name = "건강 검진", price = 50000, desc = "1년에 한 번", icon = "🩺", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 16, act = "treat", effect = { Energy = 6 }, stats = { stamina = 1.0, happiness = 0.2 } },
}
M.dental = {
	{ id = "scaling", name = "스케일링", price = 15000, desc = "개운한 잇몸", icon = "🦷", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 12, act = "treat", effect = { Hygiene = 24 }, stats = { appearance = 0.3 } },
	{ id = "cavity", name = "충치 치료", price = 30000, icon = "🪥", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 14, act = "treat", symptom = "head", effect = { Hygiene = 10, Fun = -4 }, stats = { stamina = 0.2 } },
	{ id = "whitening", name = "치아 미백", price = 80000, icon = "✨", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 14, act = "treat", effect = { Hygiene = 12 }, stats = { appearance = 1.0, popularity = 0.2 } },
}
M.oriental = {
	{ id = "acupuncture", name = "침 치료", price = 6000, desc = "뭉친 어깨에 콕콕", icon = "📍", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 12, act = "treat", symptom = "muscle", effect = { Energy = 18 }, stats = { stamina = 0.4 } },
	{ id = "boyak", name = "공진단 한 알", price = 20000, desc = "피곤할 때 기운 펄펄", icon = "🟤", dish = "medicine", tint = "pill", cat = "goods", eat = "shot", bites = 1, symptom = "tired", effect = { Energy = 30 }, stats = { stamina = 0.6 } },
	{ id = "chuna", name = "추나 요법", price = 15000, icon = "🙆", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 12, act = "treat", effect = { Energy = 14 }, stats = { stamina = 0.3, appearance = 0.1 } },
}
M.eye = {
	{ id = "test", name = "시력 검사", price = 3000, icon = "👁️", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 8, act = "treat", effect = { Energy = 2 } },
	{ id = "dry", name = "안구 건조 치료", price = 12000, icon = "💧", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 10, act = "treat", symptom = "tired", effect = { Energy = 12 } },
	{ id = "drops", name = "인공 눈물", price = 6000, icon = "💧", dish = "medicine", tint = "drink", cat = "goods", eat = "shot", bites = 1, effect = { Energy = 6 } },
}
M.skin = {
	{ id = "acne", name = "여드름 관리", price = 30000, icon = "🧴", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 12, act = "treat", effect = { Hygiene = 16 }, stats = { appearance = 0.7 } },
	{ id = "toning", name = "레이저 토닝", price = 70000, icon = "✨", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 14, act = "treat", effect = { Hygiene = 10 }, stats = { appearance = 1.4, popularity = 0.2 } },
	{ id = "sun", name = "진정 팩 (선번)", price = 20000, desc = "해수욕 후 화끈할 때", icon = "🧊", dish = "goods", tint = "mask", cat = "service", eat = "none", seconds = 10, act = "treat", symptom = "head", effect = { Hygiene = 12, Energy = 4 } },
}
M.vet = {
	{ id = "treat", name = "강아지 간식", price = 5000, icon = "🦴", dish = "goods", tint = "gift", cat = "goods", eat = "none", effect = { Fun = 6 }, stats = { happiness = 0.3 } },
	{ id = "consult", name = "반려동물 건강 상담", price = 0, icon = "🐶", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 8, act = "treat", effect = { Fun = 4 }, stats = { happiness = 0.2 } },
}
-- 학원 · 교실 (수업: 실력이 1씩 올라요)
M.math = {
	{ id = "class", name = "수학 특강 (1시간)", price = 20000, desc = "오늘은 미적분", icon = "📐", dish = "goods", tint = "book", cat = "service", eat = "none", seconds = 14, act = "study", skill = "수학", effect = { Energy = -8 }, stats = { happiness = 0.1 } },
	{ id = "test", name = "모의고사 풀기", price = 5000, icon = "📝", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 12, act = "study", skill = "수학", effect = { Energy = -6, Fun = -2 } },
	{ id = "consult", name = "입시 상담", price = 0, icon = "🎓", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 6, act = "think", effect = { Fun = 2 } },
}
M.english = {
	{ id = "class", name = "영어 회화 (1시간)", price = 25000, desc = "원어민 쌤과 프리토킹", icon = "🗣️", dish = "goods", tint = "book", cat = "service", eat = "none", seconds = 14, act = "study", skill = "영어", effect = { Energy = -6, Fun = 4 }, stats = { popularity = 0.2 } },
	{ id = "toeic", name = "토익 특강", price = 30000, icon = "📘", dish = "goods", tint = "book", cat = "service", eat = "none", seconds = 14, act = "study", skill = "영어", effect = { Energy = -8 } },
}
M.taekwondo = {
	{ id = "class", name = "태권도 수련 (1시간)", price = 15000, desc = "품새 · 발차기", icon = "🥋", dish = "goods", tint = "towel", cat = "service", eat = "none", seconds = 14, act = "kick", skill = "태권도", effect = { Energy = -12, Fun = 6 }, stats = { stamina = 0.8 } },
	{ id = "belt", name = "승급 심사", price = 30000, icon = "🎖️", dish = "goods", tint = "card", cat = "service", eat = "none", seconds = 12, act = "kick", skill = "태권도", effect = { Energy = -10, Fun = 10 }, stats = { stamina = 0.5, popularity = 0.2 } },
}
M.piano = {
	{ id = "lesson", name = "피아노 레슨 (30분)", price = 20000, desc = "엘리제를 위하여", icon = "🎹", dish = "goods", tint = "book", cat = "service", eat = "none", seconds = 12, act = "piano", skill = "피아노", effect = { Fun = 8 }, stats = { happiness = 0.5 } },
	{ id = "practice", name = "연습실 (1시간)", price = 5000, icon = "🎼", dish = "goods", tint = "book", cat = "service", eat = "none", seconds = 12, act = "piano", skill = "피아노", effect = { Fun = 6 }, stats = { happiness = 0.3 } },
}
M.art = {
	{ id = "drawing", name = "수채화 클래스", price = 25000, desc = "광안대교 그리기", icon = "🎨", dish = "goods", tint = "postcard", cat = "service", eat = "none", seconds = 14, act = "study", skill = "미술", effect = { Fun = 10 }, stats = { happiness = 0.6 } },
	{ id = "sketch", name = "크로키 1시간", price = 15000, icon = "✏️", dish = "goods", tint = "pencil", cat = "service", eat = "none", seconds = 12, act = "study", skill = "미술", effect = { Fun = 6 }, stats = { happiness = 0.4 } },
}
M.coding = {
	{ id = "class", name = "코딩 수업 (로블록스 만들기)", price = 30000, icon = "💻", dish = "goods", tint = "phone", cat = "service", eat = "none", seconds = 14, act = "study", skill = "코딩", effect = { Fun = 8, Energy = -6 }, stats = { happiness = 0.3 } },
	{ id = "robot", name = "로봇 만들기", price = 20000, icon = "🤖", dish = "goods", tint = "tool", cat = "service", eat = "none", seconds = 12, act = "study", skill = "코딩", effect = { Fun = 10 } },
}
M.school = {
	{ id = "afterschool", name = "방과후 교실", price = 0, desc = "축구 · 독서 · 로봇", icon = "🏫", dish = "goods", tint = "book", cat = "service", eat = "none", seconds = 12, act = "study", skill = "공부", effect = { Fun = 6 }, stats = { happiness = 0.3 } },
	{ id = "library", name = "도서실에서 책 읽기", price = 0, icon = "📚", dish = "goods", tint = "book", cat = "service", eat = "none", seconds = 10, act = "study", skill = "독서", effect = { Fun = 4, Energy = 4 } },
}
-- 운동
M.gym = {
	{ id = "day", name = "헬스 1일권", price = 10000, desc = "러닝머신 · 벤치프레스", icon = "🏋️", dish = "goods", tint = "towel", cat = "service", eat = "none", seconds = 16, act = "workout", skill = "근력", effect = { Energy = -14, Hygiene = -6, Fun = 6 }, stats = { stamina = 1.0, appearance = 0.3 } },
	{ id = "pt", name = "PT 1회 (트레이너)", price = 50000, desc = "자세 교정 · 식단 상담", icon = "💪", dish = "goods", tint = "towel", cat = "service", eat = "none", seconds = 18, act = "workout", skill = "근력", effect = { Energy = -18, Hygiene = -8, Fun = 8 }, stats = { stamina = 1.6, appearance = 0.6 } },
	{ id = "shake", name = "프로틴 쉐이크", price = 4500, icon = "🥤", dish = "takeout_ice", tint = "latte", cat = "drink", eat = "sip", bites = 4, effect = { Satiety = 12, Energy = 8 }, stats = { stamina = 0.2 } },
	{ id = "shower", name = "샤워실 이용", price = 0, icon = "🚿", dish = "goods", tint = "towel", cat = "service", eat = "none", seconds = 8, act = "treat", effect = { Hygiene = 30 } },
}
M.pilates = {
	{ id = "group", name = "필라테스 그룹 레슨", price = 30000, desc = "리포머 · 코어", icon = "🧘", dish = "goods", tint = "towel", cat = "service", eat = "none", seconds = 16, act = "stretch", skill = "유연성", effect = { Energy = -8, Fun = 6 }, stats = { stamina = 0.6, appearance = 0.6 } },
	{ id = "yoga", name = "요가 · 명상", price = 20000, icon = "🕉️", dish = "goods", tint = "towel", cat = "service", eat = "none", seconds = 14, act = "stretch", skill = "유연성", effect = { Energy = 10, Fun = 6 }, stats = { happiness = 0.5 } },
}
-- 은행 · 사무실 · 공공기관
M.bank = {
	{ id = "ticket", name = "번호표 뽑기 · 창구 업무", price = 0, desc = "통장 정리 · 카드 발급", icon = "🎫", dish = "goods", tint = "ticket", cat = "service", eat = "none", seconds = 10, act = "wait", effect = { Fun = 1 } },
	{ id = "savings", name = "적금 상담", price = 0, desc = "내집마련의 첫걸음", icon = "🐷", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 8, act = "think", effect = { Fun = 2 }, stats = { happiness = 0.1 } },
	{ id = "exchange", name = "환전 (여행 준비)", price = 1000, desc = "수수료 1,000원", icon = "💱", dish = "goods", tint = "card", cat = "service", eat = "none", seconds = 8, act = "wait", effect = { Fun = 2 } },
}
M.office = {
	{ id = "consult", name = "상담 받기", price = 0, icon = "🗂️", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 8, act = "think", effect = { Fun = 1 } },
	{ id = "paper", name = "서류 발급", price = 1000, icon = "📄", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 6, act = "wait" },
	{ id = "coffee", name = "믹스커피 한 잔", price = 0, desc = "대기실 셀프", icon = "☕", dish = "takeout_hot", tint = "latte", cat = "drink", eat = "sip", bites = 3, effect = { Energy = 8 } },
}
M.post = {
	{ id = "parcel", name = "택배 보내기", price = 4000, desc = "부산 → 서울 내일 도착", icon = "📦", dish = "goods", tint = "parcel", cat = "service", eat = "none", seconds = 8, act = "wait", effect = { Fun = 2 }, stats = { happiness = 0.1 } },
	{ id = "postcard", name = "광안리 엽서 부치기", price = 500, icon = "✉️", dish = "goods", tint = "postcard", cat = "service", eat = "none", seconds = 6, act = "study", effect = { Fun = 4 }, stats = { happiness = 0.2 } },
	{ id = "stamp", name = "기념 우표", price = 3000, icon = "🖼️", dish = "goods", tint = "postcard", cat = "goods", eat = "none", stats = { happiness = 0.2 } },
}
M.civic = {
	{ id = "paper", name = "민원 서류 발급", price = 1000, desc = "주민등록등본 · 무인 발급기", icon = "📄", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 6, act = "wait" },
	{ id = "map", name = "관광 지도 받기", price = 0, icon = "🗺️", dish = "goods", tint = "postcard", cat = "goods", eat = "none", effect = { Fun = 2 } },
	{ id = "class", name = "문화 강좌 (1시간)", price = 5000, desc = "캘리그라피 · 우쿨렐레", icon = "🎸", dish = "goods", tint = "book", cat = "service", eat = "none", seconds = 12, act = "study", skill = "취미", effect = { Fun = 10 }, stats = { happiness = 0.5 } },
}
M.broadcast = {
	{ id = "tour", name = "방송국 견학", price = 0, desc = "스튜디오 · 뉴스 세트", icon = "📺", dish = "goods", tint = "ticket", cat = "service", eat = "none", seconds = 12, act = "think", effect = { Fun = 12 }, stats = { happiness = 0.4 } },
	{ id = "ticket", name = "공개방송 방청권", price = 0, icon = "🎟️", dish = "goods", tint = "ticket", cat = "goods", eat = "none", effect = { Fun = 8 }, stats = { popularity = 0.2 } },
}
M.church = {
	{ id = "pray", name = "기도하기", price = 0, icon = "🙏", dish = "goods", tint = "candle", cat = "service", eat = "none", seconds = 10, act = "pray", effect = { Fun = 6, Energy = 4 }, stats = { happiness = 0.5 } },
	{ id = "choir", name = "성가대 연습", price = 0, icon = "🎶", dish = "goods", tint = "book", cat = "service", eat = "none", seconds = 12, act = "pray", skill = "노래", effect = { Fun = 8 }, stats = { happiness = 0.4, popularity = 0.1 } },
}
M.travel = {
	{ id = "citytour", name = "부산 시티투어 버스", price = 15000, icon = "🚌", dish = "goods", tint = "ticket", cat = "goods", eat = "none", effect = { Fun = 10 }, stats = { happiness = 0.5 } },
	{ id = "yacht", name = "광안리 요트 투어", price = 35000, desc = "광안대교 야경", icon = "⛵", dish = "goods", tint = "ticket", cat = "goods", eat = "none", effect = { Fun = 20 }, stats = { happiness = 0.8, popularity = 0.2 } },
}
M.insurance = {
	{ id = "consult", name = "보험 상담", price = 0, icon = "📑", dish = "goods", tint = "doc", cat = "service", eat = "none", seconds = 8, act = "think", effect = { Fun = 1 } },
	{ id = "travel", name = "여행자 보험 가입", price = 8000, icon = "🛡️", dish = "goods", tint = "doc", cat = "goods", eat = "none", stats = { happiness = 0.1 } },
}
-- 놀거리
M.escape = {
	{ id = "theme", name = "방탈출 테마 1회 (60분)", price = 22000, desc = "공포 · 추리 · 감성", icon = "🔐", dish = "goods", tint = "game", cat = "service", eat = "none", seconds = 20, act = "think", skill = "추리", effect = { Fun = 30, Energy = -6 }, stats = { happiness = 0.7 } },
	{ id = "hint", name = "힌트 없이 도전", price = 22000, icon = "🧠", dish = "goods", tint = "game", cat = "service", eat = "none", seconds = 24, act = "think", skill = "추리", effect = { Fun = 36, Energy = -8 }, stats = { happiness = 0.8, popularity = 0.2 } },
}
M.boardgame = {
	{ id = "hour", name = "보드게임 1시간", price = 4000, desc = "할리갈리 · 루미큐브", icon = "🎲", dish = "goods", tint = "game", cat = "service", eat = "none", seconds = 14, act = "play", effect = { Fun = 20 }, stats = { happiness = 0.5, popularity = 0.1 } },
	{ id = "drink", name = "아이스티", price = 3000, icon = "🧃", dish = "glass", tint = "peach", cat = "drink", eat = "sip", bites = 4, effect = { Energy = 6 } },
}
M.comic = {
	{ id = "hour", name = "만화카페 1시간", price = 3000, desc = "다락방 자리 · 담요", icon = "📚", dish = "goods", tint = "book", cat = "service", eat = "none", seconds = 14, act = "read", effect = { Fun = 16, Energy = 8 }, stats = { happiness = 0.4 } },
	{ id = "ramen", name = "라면 (끓여 줘요)", price = 4500, icon = "🍜", dish = "cupramen", cat = "main", eat = "slurp", bites = 5, effect = { Satiety = 26, Fun = 3 } },
}
M.study = {
	{ id = "seat", name = "스터디카페 2시간", price = 3500, desc = "조용한 1인석", icon = "📖", dish = "goods", tint = "book", cat = "service", eat = "none", seconds = 14, act = "study", skill = "공부", effect = { Energy = -6 } },
	{ id = "coffee", name = "아메리카노", price = 2000, icon = "☕", dish = "takeout_hot", tint = "black", cat = "drink", eat = "sip", bites = 4, effect = { Energy = 14 } },
}
M.tarot = {
	{ id = "one", name = "오늘의 타로 한 장", price = 5000, icon = "🔮", dish = "goods", tint = "tarot", cat = "service", eat = "none", seconds = 8, act = "think", effect = { Fun = 10 }, stats = { happiness = 0.3 }, fortunes = { "☀️ 태양 카드! 오늘 광안리에서 좋은 일이 생겨요", "💘 연인 카드… 바닷가 산책에 설레는 인연이?", "💰 펜타클 에이스 — 내집마련 운이 들어와요", "🌙 달 카드 — 오늘은 포차보다 일찍 자요", "⭐ 별 카드 — 광안대교 불꽃처럼 반짝일 거예요" } },
	{ id = "saju", name = "사주 풀이", price = 20000, icon = "📜", dish = "goods", tint = "tarot", cat = "service", eat = "none", seconds = 14, act = "think", effect = { Fun = 14 }, stats = { happiness = 0.4 }, fortunes = { "올해는 물(水) 기운이 좋아요. 바다 근처에 살면 대길!", "귀인이 동쪽에서 와요. 민락 쪽을 자주 가 보세요", "재물운이 상승 중… 무리한 투자만 피하면 돼요" } },
}
M.massage = {
	{ id = "foot", name = "발 마사지 (30분)", price = 25000, icon = "🦶", dish = "goods", tint = "towel", cat = "service", eat = "none", seconds = 12, act = "treat", effect = { Energy = 22, Hygiene = 6 }, stats = { happiness = 0.4 } },
	{ id = "thai", name = "타이 마사지 (60분)", price = 50000, icon = "💆", dish = "goods", tint = "towel", cat = "service", eat = "none", seconds = 16, act = "treat", effect = { Energy = 36 }, stats = { stamina = 0.3, happiness = 0.5 } },
}
M.golf = {
	{ id = "round", name = "스크린골프 9홀", price = 25000, desc = "해운대 CC", icon = "⛳", dish = "goods", tint = "game", cat = "service", eat = "none", seconds = 18, act = "swing", skill = "골프", effect = { Fun = 24, Energy = -6 }, stats = { stamina = 0.3, popularity = 0.2 } },
	{ id = "practice", name = "연습 타석 30분", price = 10000, icon = "🏌️", dish = "goods", tint = "game", cat = "service", eat = "none", seconds = 14, act = "swing", skill = "골프", effect = { Fun = 12, Energy = -6 }, stats = { stamina = 0.3 } },
}
M.photo = {
	{ id = "fourcut", name = "인생네컷 (4컷)", price = 4000, desc = "머리띠 · 소품 무료", icon = "📸", dish = "goods", tint = "photo", cat = "service", eat = "none", seconds = 8, act = "pose", effect = { Fun = 12 }, stats = { happiness = 0.3, popularity = 0.2 } },
	{ id = "profile", name = "프로필 촬영", price = 50000, icon = "🖼️", dish = "goods", tint = "photo", cat = "service", eat = "none", seconds = 14, act = "pose", effect = { Fun = 10 }, stats = { appearance = 0.6, popularity = 0.4 } },
}
M.partyroom = {
	{ id = "hour", name = "파티룸 1시간", price = 30000, desc = "풍선 · 조명 · 블루투스 스피커", icon = "🎉", dish = "goods", tint = "gift", cat = "service", eat = "none", seconds = 16, act = "dance", effect = { Fun = 30 }, stats = { happiness = 0.7, popularity = 0.4 } },
	{ id = "cake", name = "레터링 케이크", price = 28000, icon = "🎂", dish = "cake", tint = "strawberry", cat = "dessert", eat = "fork", bites = 6, effect = { Satiety = 12, Fun = 12 }, stats = { happiness = 0.5 } },
}
M.laser = {
	{ id = "game", name = "레이저 태그 1게임", price = 15000, icon = "🔫", dish = "goods", tint = "game", cat = "service", eat = "none", seconds = 16, act = "workout", effect = { Fun = 26, Energy = -10 }, stats = { stamina = 0.4, popularity = 0.2 } },
}

-- generic fallbacks
M.restaurant = M.gukbap
M.store = M.souvenir
M.lobby = {}
M.residence = {}
M.realty = {}

-------------------------------------------------------------------------------------------------
-- Kiosk options
-------------------------------------------------------------------------------------------------
SS.OPTIONS = {
	temp = { label = "온도", choices = { { "ice", "ICE 🧊", 0 }, { "hot", "HOT ☕", 0 } } },
	size = { label = "사이즈", choices = { { "r", "레귤러", 0 }, { "l", "라지 +500", 500 } } },
	shot = { label = "샷", choices = { { "1", "기본", 0 }, { "2", "샷 추가 +500", 500 } } },
	here = { label = "드시고 가세요?", choices = { { "here", "매장 🪑", 0 }, { "togo", "포장 🥡", 0 } } },
	bread = { label = "빵", choices = { { "white", "화이트", 0 }, { "wheat", "위트", 0 }, { "honey", "허니오트", 0 } } },
	cone = { label = "용기", choices = { { "cone", "콘 🍦", 0 }, { "cup", "컵 🥄", 0 } } },
}

-------------------------------------------------------------------------------------------------
-- The shop's voice (shown as a line from the counter / kitchen; staff NPCs are the NPC system's)
-------------------------------------------------------------------------------------------------
SS.LINES = {
	soup = { greet = { "어서오이소~ 편한 데 앉으이소!", "어서오세요~ 국물 펄펄 끓고 있습니더" }, order = { "네~ 금방 나갑니더!", "국밥 하나요~ 정구지 많이 드릴게예" }, served = { "나왔습니더~ 뜨거우니 조심하이소!", "새우젓 넣어서 드이소~" }, bye = { "마이 무따? 또 오이소~", "든든하게 드셨지예? 조심히 가이소~" } },
	noodle = { greet = { "어서오세요~ 몇 분이세요?", "어서오세요! 편하신 자리 앉으세요" }, order = { "네~ 면 삶을게요!", "주문 들어갑니다~" }, served = { "나왔습니다~ 면 불기 전에 드세요!", "가위 필요하시면 말씀하세요~" }, bye = { "감사합니다~ 또 오세요!" } },
	katsu = { greet = { "이랏샤이마세~ 어서오세요!" }, order = { "네~ 바로 튀겨 드릴게요" }, served = { "로스카츠 나왔습니다~ 소스는 직접 갈아 드세요" }, bye = { "감사합니다~" } },
	grill = { greet = { "어서오세요~ 불 넣어 드릴게요!", "어서오세요! 오늘 조개 싱싱해요~" }, order = { "네~ 바로 올려 드릴게요", "주문 들어갑니다~ 집게 여기 있어요" }, served = { "올려 드렸어요~ 자주 뒤집어 주세요!", "익으면 입 벌려요~ 그때 드세요!" }, bye = { "맛있게 드셨어요? 또 오세요~" } },
	rawfish = { greet = { "어서오세요~ 수조에서 직접 골라 보세요!", "오늘 광어 물 좋아요~" }, order = { "네~ 바로 떠 드릴게요!", "좋은 놈 고르셨네~ 손질 들어갑니다" }, served = { "회 나왔습니다~ 초장 찍어 드세요!", "매운탕은 회 다 드시면 끓여 드려요~" }, bye = { "감사합니다~ 또 오이소!" } },
	seafood = { greet = { "어서오세요~ 해산물 싱싱합니다!" }, order = { "네~ 쪄 드릴게요!" }, served = { "나왔습니다~ 뜨거우니 조심하세요" }, bye = { "또 오세요~" } },
	pocha = { greet = { "어서와요~ 앉아요 앉아!", "오늘 바닷바람 좋제? 앉아요~" }, order = { "네~ 금방 해 줄게요!", "청포도 소다 하나 추가요~" }, served = { "나왔어요~ 맛있게 먹어요!", "어묵탕 뜨거우니까 조심!" }, bye = { "잘 가요~ 조심히 들어가요!" } },
	pub = { greet = { "Welcome~ 어서오세요!", "바 자리도 비어 있어요~" }, order = { "무알콜 생맥 하나요~ 거품 예쁘게!", "주문 들어갑니다!" }, served = { "Cheers~ 맛있게 드세요!" }, bye = { "Thank you~ 또 오세요!" } },
	chicken = { greet = { "어서오세요~ 치킨 방금 튀겼어요!" }, order = { "네~ 바로 튀겨 드릴게요! 15초만~", "후라이드 하나요~" }, served = { "치킨 나왔습니다~ 뜨거우니 조심하세요!" }, bye = { "감사합니다~ 또 오세요!" } },
	snack = { greet = { "어서오세요~ 떡볶이 방금 나왔어요!", "어묵 국물은 셀프예요~" }, order = { "네~ 금방 담아 드릴게요!" }, served = { "나왔어요~ 맛있게 드세요!" }, bye = { "또 와요~" } },
	cafe = { greet = { "어서오세요~ 주문은 키오스크에서 도와드릴게요", "안녕하세요~" }, order = { "주문 확인했습니다~ 진동벨 드릴게요!" }, served = { "주문하신 음료 나왔습니다~" }, bye = { "감사합니다~ 좋은 하루 되세요!" } },
	burger = { greet = { "어서오세요~ 키오스크로 주문해 주세요!" }, order = { "주문 들어갔습니다~ 번호 불러 드릴게요" }, served = { "주문하신 버거 나왔습니다~" }, bye = { "감사합니다~" } },
	dessert = { greet = { "어서오세요~ 맛보기 드려요?", "오늘의 맛 추천드릴게요~" }, order = { "네~ 예쁘게 담아 드릴게요!" }, served = { "여기 있습니다~ 녹기 전에 드세요!" }, bye = { "감사합니다~" } },
	bakery = { greet = { "어서오세요~ 방금 나온 빵이에요!", "소금빵 지금 막 구웠어요~" }, order = { "봉투 필요하세요?" }, served = { "맛있게 드세요~" }, bye = { "감사합니다~" } },
	cvs = { greet = { "어서오세요~ GS… 아니 편의점입니다~", "어서오세요~" }, order = { "봉투 필요하세요?", "포인트 적립하세요?" }, served = { "감사합니다~" }, bye = { "안녕히 가세요~" } },
	retail = { greet = { "어서오세요~ 편하게 구경하세요!", "테스터 써 보셔도 돼요~" }, order = { "포장해 드릴까요?" }, served = { "예쁘게 쓰세요~" }, bye = { "또 오세요~" } },
	pharmacy = { greet = { "어서오세요~ 어디가 불편하세요?" }, order = { "하루 세 번, 식후에 드세요~" }, served = { "몸조리 잘하세요~" }, bye = { "몸조리 잘하세요~" } },
	laundry = { greet = { "어서오세요~ 맡기실 거 있으세요?" }, order = { "네~ 깨끗하게 해 놓을게요" }, served = { "다 됐어요~ 빳빳하죠?" }, bye = { "또 오세요~" } },
	realty = { greet = { "어서오세요~ 집 보러 오셨어요?" }, order = {}, served = {}, bye = { "좋은 집 찾으시길 바래요~" } },
	lobby = { greet = { "어서오세요, 프런트입니다~" }, order = {}, served = {}, bye = { "좋은 여행 되세요~" } },
	residence = { greet = {}, order = {}, served = {}, bye = {} },
	salon = { greet = { "어서오세요~ 헤어살롱입니다! 앉으세요~" }, order = { "자 그럼 시작할게요~", "이 스타일 요즘 진짜 인기 많아요~" }, served = { "짜잔~ 완전 잘 어울리세요!" }, bye = { "다음에 또 다듬으러 오세요~" } },
	chinese = { greet = { "어서오세요~ 몇 분이세요?", "어서오세요! 짜장 짬뽕 다 됩니다~" }, order = { "짜장 하나 짬뽕 하나~ 금방 나가요!", "네~ 웍 불 올립니다!" }, served = { "나왔습니다~ 잘 비벼 드세요!", "탕수육은 소스 따로 드렸어요~" }, bye = { "감사합니다~ 또 오세요!" } },
	clinic = { greet = { "어서오세요~ 접수 도와드릴게요", "성함이랑 생년월일 말씀해 주세요~" }, order = { "잠시만 누워 계세요~", "금방 끝나요, 긴장 푸세요~" }, served = { "다 됐습니다~ 물 많이 드세요", "몸조리 잘하세요~" }, bye = { "안녕히 가세요~ 무리하지 마세요!" } },
	academy = { greet = { "어서와요~ 오늘도 열심히 해 볼까요?", "안녕하세요~ 수업 들으러 왔어요?" }, order = { "자, 교재 펴세요~", "오늘 진도 나갑니다!" }, served = { "수고했어요~ 실력 늘었네요!", "오늘 잘했어요~ 다음 시간에 봐요!" }, bye = { "조심히 가요~" } },
	gym = { greet = { "어서오세요~ 운동하러 오셨어요?", "오늘 하체 하는 날이죠? 😤" }, order = { "자 시작합니다! 하나, 둘!", "호흡 잊지 마세요~" }, served = { "수고하셨습니다! 단백질 챙겨 드세요 💪", "오늘 운동 끝! 개운하죠?" }, bye = { "내일 또 봬요~" } },
	bank = { greet = { "어서오세요~ 번호표 뽑아 주세요", "무엇을 도와드릴까요?" }, order = { "잠시만 기다려 주세요~", "확인해 드릴게요~" }, served = { "처리됐습니다~ 좋은 하루 되세요", "다른 업무 있으시면 말씀해 주세요~" }, bye = { "안녕히 가세요~" } },
	office = { greet = { "어서오세요~ 무슨 일로 오셨어요?", "안녕하세요~ 이쪽으로 앉으세요" }, order = { "네~ 확인해 볼게요", "잠시만 기다려 주세요~" }, served = { "다 됐습니다~", "도움이 되셨길 바래요~" }, bye = { "안녕히 가세요~" } },
	play = { greet = { "어서오세요~ 재밌게 놀다 가세요!", "몇 분이세요? 바로 안내해 드릴게요~" }, order = { "시작합니다! 즐거운 시간 되세요~", "자~ 준비됐죠?" }, served = { "재밌었어요? 또 놀러 와요!", "수고하셨어요~ 기록 대박인데요?" }, bye = { "또 오세요~" } },
}

-------------------------------------------------------------------------------------------------
-- Annex: the shops of facade-only storefronts are classified by their sign text. These rules never
-- change how the map's own walk-in shops are read (those use SS.RULES above):
--   ANNEX_PRE   checked FIRST (specific words that the general rules would misread, e.g. "방탈출 카페")
--   then SS.RULES, then ANNEX_RULES (words the map's shops never needed)
-------------------------------------------------------------------------------------------------
SS.ANNEX_PRE = {
	{ "방탈출", "play", "escape" },
	{ "보드게임", "play", "boardgame" },
	{ "만화카페", "play", "comic" },
	{ "룸카페", "play", "comic" },
	{ "스터디", "play", "study" },
	{ "독서실", "play", "study" },
	{ "타로", "play", "tarot" },
	{ "사주", "play", "tarot" },
	{ "파티룸", "play", "partyroom" },
	{ "LASER TAG", "play", "laser" },
	{ "스크린골프", "play", "golf" },
	{ "골프존", "play", "golf" },
	{ "GOLFZON", "play", "golf" },
	{ "골프", "play", "golf" },
	{ "인생네컷", "play", "photo" },
	{ "LIFE4CUTS", "play", "photo" },
	{ "사진", "play", "photo" },
	{ "마사지", "play", "massage" },
	{ "피부관리", "salon", "nail" },
	{ "왁싱", "salon", "nail" },
	{ "네일", "salon", "nail" },
	{ "속눈썹", "salon", "nail" },
	{ "아이스크림 할인", "cvs", "cvs" },
	{ "무인 아", "cvs", "cvs" },
	{ "아이스크림 천국", "cvs", "cvs" },
	{ "무인할인", "cvs", "cvs" },
	{ "와인", "pub", "wine" },
	{ "WINE", "pub", "wine" },
	{ "이자카야", "pub", "izakaya" },
	{ "黒松", "pub", "izakaya" },
	{ "홀덤", "pub", "pub" },
	{ "마라", "chinese", "mara" },
	{ "짬뽕", "chinese", "chinese" },
	{ "반점", "chinese", "chinese" },
	{ "중화", "chinese", "chinese" },
	{ "쌀국수", "noodle", "pho" },
	{ "족발", "soup", "jokbal" },
	{ "보쌈", "soup", "jokbal" },
	{ "본죽", "soup", "juk" },
	{ "닭강정", "chicken", "gangjeong" },
	{ "피자", "burger", "pizza" },
	{ "DOUGH", "burger", "pizza" },
	{ "토스트", "burger", "toast" },
	{ "도시락", "snack", "dosirak" },
	{ "낙곱새", "seafood", "nakgopsae" },
	{ "막창", "grill", "gopchang" },
	{ "피부과", "clinic", "skin" },
	{ "동물병원", "clinic", "vet" },
	{ "BAKERY", "bakery", "bakery" },
}
SS.ANNEX_RULES = {
	{ "순대국", "soup", "gukbap" },
	{ "국밥", "soup", "gukbap" },
	{ "곰장어", "grill", "clam" },
	{ "장어", "grill", "clam" },
	{ "물회", "rawfish", "hoe" },
	{ "회센터", "rawfish", "hoe" },
	{ "회타운", "rawfish", "hoe" },
	{ "활어", "rawfish", "hoe" },
	{ "다찌", "rawfish", "hoe" },
	{ "오마카세", "rawfish", "sushi" },
	{ "호프", "pub", "hof" },
	{ "생맥주", "pub", "hof" },
	{ "맥주창고", "pub", "hof" },
	{ "술집", "pub", "hof" },
	{ "주점", "pub", "hof" },
	{ "BAR", "pub", "cocktail" },
	{ "bar", "pub", "cocktail" },
	{ "야장", "pocha", "pocha" },
	{ "경양식", "katsu", "katsu" },
	{ "스테이크", "grill", "bbq" },
	{ "한우", "grill", "bbq" },
	{ "고기", "grill", "bbq" },
	{ "삼겹", "grill", "bbq" },
	{ "갈비", "grill", "bbq" },
	{ "흑돼지", "grill", "bbq" },
	{ "화로", "grill", "bbq" },
	{ "숯불", "grill", "bbq" },
	{ "숙성", "grill", "bbq" },
	{ "명륜", "grill", "bbq" },
	{ "냉면", "noodle", "milmyeon" },
	{ "김밥", "snack", "snack" },
	{ "맥도날드", "burger", "burger" },
	{ "롯데리아", "burger", "burger" },
	{ "LOTTERIA", "burger", "burger" },
	{ "맘스터치", "burger", "burger" },
	{ "MOM'S TOUCH", "burger", "burger" },
	{ "PARIS BAGUETTE", "bakery", "bakery" },
	{ "파리바게뜨", "bakery", "bakery" },
	{ "뚜레쥬르", "bakery", "bakery" },
	{ "제과", "bakery", "bakery" },
	{ "빵", "bakery", "bakery" },
	{ "BAGEL", "bakery", "bakery" },
	{ "베이글", "bakery", "bakery" },
	{ "크루아상", "bakery", "bakery" },
	{ "배스킨", "dessert", "gelato" },
	{ "빽다방", "cafe", "cafe" },
	{ "EDIYA", "cafe", "cafe" },
	{ "이디야", "cafe", "cafe" },
	{ "할리스", "cafe", "cafe" },
	{ "메가", "cafe", "cafe" },
	{ "컴포즈", "cafe", "cafe" },
	{ "투썸", "cafe", "dessertcafe" },
	{ "ROASTERS", "cafe", "roastery" },
	{ "브런치", "cafe", "dessertcafe" },
	{ "BRUNCH", "cafe", "dessertcafe" },
	{ "치과", "clinic", "dental" },
	{ "한의원", "clinic", "oriental" },
	{ "한방", "clinic", "oriental" },
	{ "안과", "clinic", "eye" },
	{ "병원", "clinic", "clinic" },
	{ "의원", "clinic", "clinic" },
	{ "메디컬", "clinic", "clinic" },
	{ "소아", "clinic", "clinic" },
	{ "내과", "clinic", "clinic" },
	{ "정형외과", "clinic", "clinic" },
	{ "이비인후", "clinic", "clinic" },
	{ "통증", "clinic", "clinic" },
	{ "태권도", "academy", "taekwondo" },
	{ "합기도", "academy", "taekwondo" },
	{ "피아노", "academy", "piano" },
	{ "음악", "academy", "piano" },
	{ "미술", "academy", "art" },
	{ "코딩", "academy", "coding" },
	{ "영어", "academy", "english" },
	{ "어학", "academy", "english" },
	{ "수학", "academy", "math" },
	{ "학원", "academy", "math" },
	{ "교습소", "academy", "piano" },
	{ "교실", "academy", "math" },
	{ "눈높이", "academy", "math" },
	{ "학교", "academy", "school" },
	{ "필라테스", "gym", "pilates" },
	{ "요가", "gym", "pilates" },
	{ "크로스핏", "gym", "gym" },
	{ "헬스", "gym", "gym" },
	{ "GYM", "gym", "gym" },
	{ "피트니스", "gym", "gym" },
	{ "휘트니스", "gym", "gym" },
	{ "은행", "bank", "bank" },
	{ "금고", "bank", "bank" },
	{ "BNK", "bank", "bank" },
	{ "ATM", "bank", "bank" },
	{ "우체국", "office", "post" },
	{ "구청", "office", "civic" },
	{ "주민센터", "office", "civic" },
	{ "관리사무소", "office", "civic" },
	{ "경로당", "office", "civic" },
	{ "문화센터", "office", "civic" },
	{ "관광안내", "office", "civic" },
	{ "KBS", "office", "broadcast" },
	{ "방송", "office", "broadcast" },
	{ "교회", "office", "church" },
	{ "성당", "office", "church" },
	{ "여행사", "office", "travel" },
	{ "보험", "office", "insurance" },
	{ "삼성화재", "office", "insurance" },
	{ "세무", "office", "office" },
	{ "법무사", "office", "office" },
	{ "건축사", "office", "office" },
	{ "사무소", "office", "office" },
	{ "사무실", "office", "office" },
	{ "비즈니스", "office", "office" },
	{ "인테리어", "office", "office" },
	{ "타이어", "office", "office" },
	{ "정비", "office", "office" },
	{ "텔레콤", "retail", "phone" },
	{ "T world", "retail", "phone" },
	{ "KT", "retail", "phone" },
	{ "LG U+", "retail", "phone" },
	{ "휴대폰", "retail", "phone" },
	{ "하이마트", "retail", "phone" },
	{ "다이소", "retail", "daiso" },
	{ "DAISO", "retail", "daiso" },
	{ "홈플러스", "cvs", "cvs" },
	{ "올리브영", "retail", "cosmetics" },
	{ "마트", "cvs", "cvs" },
	{ "MART", "cvs", "cvs" },
	{ "할인점", "cvs", "cvs" },
	{ "미니스톱", "cvs", "cvs" },
	{ "청과", "retail", "fruit" },
	{ "과일", "retail", "fruit" },
	{ "정육", "retail", "butcher" },
	{ "반찬", "retail", "banchan" },
	{ "문구", "retail", "stationery" },
	{ "철물", "retail", "hardware" },
	{ "꽃", "retail", "flower" },
	{ "안경", "retail", "optical" },
	{ "크린토피아", "laundry", "laundry" },
	{ "빨래방", "laundry", "laundry" },
	{ "수선", "laundry", "laundry" },
	{ "헤어", "salon", "salon" },
	{ "HAIR", "salon", "salon" },
	{ "미용", "salon", "salon" },
	{ "메이크업", "salon", "salon" },
}

local function matchList(list: { any }, n: string): (string?, string?)
	for _, rule in list do
		if string.find(n, rule[1], 1, true) then
			return rule[2], rule[3]
		end
	end
	return nil, nil
end

-- a storefront sign / building name -> type, menu (or nil: not a shop, e.g. "공동현관", "101동")
function SS.classifyAnnex(name: string): (string?, string?)
	local t, m = matchList(SS.ANNEX_PRE, name)
	if t then
		return t, m
	end
	t, m = SS.classify({ name })
	-- the map's rules know 호텔 / 맨션 / TOWER as lobbies of whole buildings: not a storefront
	if t and t ~= "lobby" and t ~= "residence" then
		return t, m
	end
	return matchList(SS.ANNEX_RULES, name)
end

-------------------------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------------------------
-- classify a shop by its names (model name, sign texts): -> type, menu | nil
function SS.classify(names: { string }): (string?, string?)
	for _, rule in SS.RULES do
		local key = rule[1]
		for _, n in names do
			if rule.exact then
				local bare = string.gsub(n, "^%s+", "")
				bare = string.gsub(bare, "%s+$", "")
				if bare == key then
					return rule[2], rule[3]
				end
			elseif string.find(n, key, 1, true) then
				return rule[2], rule[3]
			end
		end
	end
	return nil, nil
end

-- classify by contents (prop name -> count): -> type, menu | nil
function SS.classifyContents(props: { [string]: number }): (string?, string?)
	for _, rule in SS.CONTENT_RULES do
		if (props[rule[1]] or 0) > 0 then
			return rule[2], rule[3]
		end
	end
	return nil, nil
end

function SS.menu(key: string?): { any }
	return (key and M[key]) or {}
end

function SS.item(menuKey: string?, id: any): any?
	for _, it in SS.menu(menuKey) do
		if it.id == id then
			return it
		end
	end
	return nil
end

-- deterministic line pick
function SS.line(shopType: string, key: string, seed: number?): string?
	local t = SS.LINES[shopType]
	local list = t and t[key]
	if not list or #list == 0 then
		return nil
	end
	return list[(math.floor(math.abs(seed or 0)) % #list) + 1]
end

-- "9,500원"
function SS.won(n: any): string
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(v))
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return (if v < 0 then "-" else "") .. s .. out .. "원"
end

-- option price add-ons
function SS.optionPrice(opts: any?): number
	if type(opts) ~= "table" then
		return 0
	end
	local add = 0
	for key, choice in opts do
		local def = SS.OPTIONS[key]
		if def then
			for _, c in def.choices do
				if c[1] == choice then
					add += c[3]
				end
			end
		end
	end
	return add
end

-- eat style -> what you hold while eating
SS.UTENSIL = {
	spoon = "spoon",
	chop = "chopsticks",
	slurp = "chopsticks",
	fork = "fork",
	stick = "none",
	hand = "none",
	sip = "none",
	gulp = "none",
	shot = "none",
	lick = "none",
	none = "none",
}

-- eat style -> the verb on the button
SS.EAT_VERB = {
	spoon = "한 숟갈",
	chop = "한 젓가락",
	slurp = "후루룩",
	fork = "한 입",
	stick = "한 입",
	hand = "한 입",
	sip = "한 모금",
	gulp = "벌컥",
	shot = "짠 · 원샷",
	lick = "냠",
	none = "사용",
}

-- practice counters (item.skill) -> the player attribute "GwB_Skill_<id>" (attribute names must be
-- ASCII letters / digits / _). A new skill name needs a line here (validate() checks it).
SS.SKILLS = {
	["수학"] = "Math",
	["영어"] = "English",
	["태권도"] = "Taekwondo",
	["피아노"] = "Piano",
	["미술"] = "Art",
	["코딩"] = "Coding",
	["공부"] = "Study",
	["독서"] = "Reading",
	["근력"] = "Strength",
	["유연성"] = "Flexibility",
	["취미"] = "Hobby",
	["노래"] = "Singing",
	["추리"] = "Puzzle",
	["골프"] = "Golf",
}

function SS.validate(): { string }
	local out = {}
	for key, list in M do
		for _, it in list do
			if it.skill ~= nil and not SS.SKILLS[it.skill] then
				table.insert(out, key .. "." .. tostring(it.id) .. ": skill " .. tostring(it.skill) .. " not in SKILLS")
			end
			if type(it.id) ~= "string" or type(it.name) ~= "string" then
				table.insert(out, key .. ": bad id/name")
			end
			if type(it.price) ~= "number" or it.price < 0 then
				table.insert(out, key .. "." .. tostring(it.id) .. ": bad price")
			end
			if type(it.dish) ~= "string" then
				table.insert(out, key .. "." .. tostring(it.id) .. ": no dish")
			end
		end
	end
	local all = table.clone(SS.RULES)
	for _, list in { SS.ANNEX_PRE, SS.ANNEX_RULES } do
		for _, rule in list do
			table.insert(all, rule)
		end
	end
	for _, rule in all do
		if not SS.TYPES[rule[2]] then
			table.insert(out, "rule " .. rule[1] .. ": unknown type " .. rule[2])
		end
		if not M[rule[3]] then
			table.insert(out, "rule " .. rule[1] .. ": unknown menu " .. rule[3])
		end
	end
	return out
end

return SS
