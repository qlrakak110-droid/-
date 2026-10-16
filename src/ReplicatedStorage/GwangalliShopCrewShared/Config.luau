-- GwangalliShopCrewShared/Config: every tunable of the shop crew add-on.
-- Overrides without code changes (read once at server start):
--   Script ServerScriptService.GwangalliShopCrew attributes: TakeOverShopService (bool), Diners (bool),
--     MaxShops (number), Debug (bool), Help (bool: 일손 돕기), Augment (bool: talk to ShopStaff / clerks)
--   Workspace attributes: GwShopCrew = false (everything off), GwShopCrewDebug = true (logs + status prints)
--   Shop model attribute ShopCrew = false: that shop never gets a crew.
-- Pure data (strings for enums: the server converts them).

local C = {}

C.ENABLED = true
C.DEBUG = false

-- GwangalliShopService (the add-on pack's simple waiter): taken over (disabled at runtime, its waiters removed)
-- when true; false = coexist (we never spawn waiters / call staffMode in table shops then)
C.TAKE_OVER_SHOP_SERVICE = true
-- ShopStaff counter rigs, GwShopClerk figures and venue staff (PC방 · 노래방 ...) get our "말 걸기" dialog
C.AUGMENT_STAFF = true

-- where crews exist ----------------------------------------------------------------------------------
C.MAX_SHOPS = 6 -- crewed shops at once (nearest players first; the shop a player is in always wins)
C.MAX_CREW_RIGS = 18
C.SPAWN_R = 45 -- a player this close (3D, to the shop centre) brings the crew in
C.DESPAWN_R = 90 -- nobody within this for DESPAWN_AFTER seconds: the crew goes home
C.DESPAWN_AFTER = 20
C.JOB_SITES = { "스타벅스 광안리점", "GS25 광안리점", "민락회타운" } -- Destination names: the player works there
C.JOB_SITE_R = 45
C.SKIP_SHOPS = { "민락 포장마차" } -- shop names never crewed (Play.Pocha runs that venue)
C.SKIP_TYPES = {} -- ShopLife types never crewed ({ cafe = true } ...)
-- player attributes that mean "working here now": the crew stands down while such a player is inside
C.WORK_ATTRS = { "GwWorkShift", "GwWorkPlaced", "GwMgrDuty" }
C.WORK_ACTIVITIES = { gukbap = true, pocha = true } -- GwPlayActivity values that are a job

-- motion -----------------------------------------------------------------------------------------------
C.WALK = { waiter = 7.0, tray = 5.8, cook = 5.5, cashier = 6.0, barista = 5.8, floor = 6.2, stocker = 5.6, diner = 5.0 }
C.AGENT_R = 0.6 -- clearance kept from furniture (studs); a tighter 0.35 is tried when a table is unreachable
C.AGENT_R_TIGHT = 0.35
C.CELL = 0.5 -- grid cell (studs)
C.DOOR_STRIP = 4.5 -- walkable strip outside the door (diners come in from the sidewalk)
C.TICK = 0.25 -- brain tick (s)

-- serving ----------------------------------------------------------------------------------------------
C.SERVE_TIMEOUT = 18 -- a ready table order nobody brought in this many seconds is served by ShopLife directly
C.QUEUE_POLL = 3 -- seconds between "queue" polls per crewed shop (adopts orders we missed)
C.BATCH_WINDOW = 3 -- ready orders of the same table within this many seconds go on one tray
C.MAX_BATCH = 3
C.BRAIN_DEAD = 5 -- a crew whose brain has not ticked for this long loses staffMode
C.CALL_STAY = 20 -- the waiter waits this long at a table that rang the bell before going back

-- talking ----------------------------------------------------------------------------------------------
C.TALK_KEY = "T" -- KeyboardKeyCode of the 말 걸기 prompt (E is taken by most shop prompts)
C.TALK_PAD = "ButtonY"
C.TALK_DIST = 7 -- prompt activation distance
C.TALK_R = 10 -- server: max distance to the staff when a dialog opens
C.TALK_CLOSE_R = 14 -- the dialog closes beyond this
C.DIALOG_TTL = 60
C.RATE = 5 -- requests per second (token bucket)
C.BURST = 10
C.GREET_GAP = 60 -- seconds between two greetings of the same player in a shop
C.BANTER_GAP = 90
C.LINE_GAP_PER_PLAYER = 6
C.SAY_R = 45 -- bubbles go to players this close to the speaker
C.CHOICE_CD = { water = 25, recommend = 4, banchan = 20, taste = 5, smalltalk = 3, directions = 4 }

-- mood · friendliness (칭찬 / 항의 / 팁) --------------------------------------------------------------------
C.MOOD = { base = 70, min = 10, max = 100, compliment = 6, complaint = -9, tip = 5, recoverPerMin = 1.5 }
C.FRIEND = { compliment = 3, tip = 2, complaint = -4, max = 100, perDayGain = 8 }
C.TIP = { amounts = { 1000, 3000, 5000 }, perDay = 3 }

-- 단골 (regulars) -------------------------------------------------------------------------------------------
C.REGULAR = {
	enabled = true,
	levels = { 1, 3, 7, 15, 30 }, -- visit days for level 1..5
	titles = { "첫 방문", "아는 얼굴", "단골", "찐단골", "가족 같은 손님" },
	stampsPerCoupon = 10,
	maxCoupons = 3,
	couponValue = 10000,
	dailyEarnCap = 20000,
	serviceLevel = 3, -- 서비스 (a free small item once per visit day) from this level
	nameLevel = 2, -- greeted by name from this level
	maxShops = 120,
	saveEvery = 180,
}
C.DATASTORE = "GwangalliShopCrew_v1"

-- NPC diners -------------------------------------------------------------------------------------------
C.DINERS = {
	enabled = true,
	max = 14, -- whole server
	perShop = 6,
	keepFree = 2, -- tables always left free (+1 per 2 players in the shop)
	maxShare = 0.4, -- at most this share of a shop's tables
	occBase = 0.25,
	occPeak = 0.5, -- 11:30-13:30, 18:00-20:30
	occNight = 0.6, -- 포차 / 구이 / 펍 19:00-02:00
	occLate = 0.1, -- 03:00-07:00
	gap = { 15, 40 }, -- seconds between arrivals
	eat = { 25, 50 },
	avatarCap = 10, -- with this many live diners, new ones use block rigs (shared avatar budget)
}

-- counter sales (staff counters ShopLife does not run: 홈플러스 POS, 빵집, 펍 바 ...) ----------------------------
C.COUNTER = { enabled = true, perMinute = 6 }

-- 일손 돕기 (P3, off by default) ----------------------------------------------------------------------------
C.HELP = { enabled = false, perDay = 3, seconds = 180, maxDeliveries = 6, pay = 1200, bonus = 600, cap = 15000, leaveR = 25, reach = 5 }

-- client -----------------------------------------------------------------------------------------------
C.CLIENT = {
	tagDistance = 28,
	maxTags = 12,
	propDistance = 40,
	maxProps = 8,
	footstepDistance = 26,
	keeps = true, -- register our spots as keep zones with the building interior (GwangalliBuildingInterior)
}

-- ids / names
C.NPC_PREFIX = "shop_crew_"
C.DINER_PREFIX = "shop_diner_"

return C
