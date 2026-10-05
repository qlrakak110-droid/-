--!nocheck
-- GwangalliWorkConfig: every tunable number of the 알바 work simulation (카페 · 편의점 · 횟집 · 배달) in one place.
-- Pure data, no DataModel access (loads in plain Luau for the unit tests). Change the numbers here, not in code.
--
-- Money model (docs/WORK_SIM.md "급여"):
--   지급액 = 기본급 (근무한 분 x 분당 기본급, 숙련도 등급별) + 성과급 (전달 완료한 주문 / 업무의 작업 점수)
--          + 정확도·서비스 보너스 (성과급의 일정 비율) + 마감 수당 (마감 업무를 끝까지 한 근무)
--   * 손님이 낸 매출은 가게 몫이다. 직원 급여에 매출이 들어가지 않는다.
--   * 실수는 급여에서 깎지 않는다 (임금 공제 없음). 실수는 성과급·보너스를 못 받는 것으로만 반영된다.
--   * 중도 퇴근 / 접속 종료: 근무한 시간의 기본급 + 이미 전달 완료한 주문의 성과급만 지급 (마감 수당 없음).
-- Pacing target (tune with SHIFT / PAY / LEVELS): Lv1 기본 근무 1회 ≈ 3만원 → 중고 큐비(15만) 약 5회,
-- 원룸 보증금(30만) 약 7~8회; Lv3 이후에는 1회 5~6만원 이상.
--   * 실수 차감 (C.PAY.penaltyCap): 미성년자 판매 · 거스름돈 오류 같은 큰 실수는 그 근무의 성과급에서만
--     빠진다 (성과급 합계 아래로는 내려가지 않음 → 기본급은 항상 그대로).
--   * 팁 (단골 손님) / 우천 할증 / 단체 배달 보너스는 정산서에 따로 한 줄씩 나온다.
--
-- v2 (편의점 · 배달 · NPC 손님): C.CUSTOMERS (손님 성격), C.CVS (상품 · 진열대 · 이벤트), C.DELIVERY
-- (식당 · 콜 · 날씨 · 음식 상태), C.LEVELS.ranks (신입 → 직원 → 숙련 직원 → 매니저급), C.UNLOCKS (레벨별 새 업무).

local C = {}

C.VERSION = 2

-------------------------------------------------------------------------------------------------
-- Shift length (real seconds). A shift always has the three phases; their share is fixed.
-------------------------------------------------------------------------------------------------
C.SHIFT = {
	lengths = {
		{ id = "short", label = "짧게", seconds = 180 },
		{ id = "normal", label = "보통", seconds = 300 },
		{ id = "long", label = "길게", seconds = 480 },
	},
	defaultLength = "normal",
	-- phase shares of the shift: 오픈 준비 → 피크 → 마감
	phases = {
		{ id = "prep", label = "오픈 준비", share = 0.18, color = { 120, 190, 255 } },
		{ id = "rush", label = "피크 타임", share = 0.57, color = { 255, 150, 70 } },
		{ id = "close", label = "마감", share = 0.25, color = { 170, 140, 255 } },
	},
	lastOrderShare = 0.85, -- no new customers after this share of the shift (마감 정리 시간)
	closeGrace = 60, -- seconds after the shift time for the last orders + closing tasks, then auto 정산
	clockInRadius = 26, -- studs from the store's staff entrance to clock in
	reachDistance = 8.5, -- server check: studs between the character and a station to use it
}

-------------------------------------------------------------------------------------------------
-- Pay (won). Base pay per worked real minute by skill level; performance per completed order.
-------------------------------------------------------------------------------------------------
C.PAY = {
	baseRateByLevel = { 2400, 2800, 3300, 3900, 4600 }, -- 원 / 근무 분 (Lv1..Lv5)
	accuracyBonus = 0.3, -- 완벽한 주문: 성과급 +30 %
	serviceBonus = 0.2, -- 빨리 전달 (목표 시간 안): 성과급 +20 %
	closeBonusMinutes = 1.5, -- 마감 업무를 다 하면 기본급 1.5분치 추가
	groupBonus = 0.15, -- 단체 주문 전체를 정확히 전달: 성과급 +15 %
	taxRate = 0, -- 0 = 세전 그대로 (3.3 % 원천징수를 넣고 싶으면 0.033)
	perfMultByLevel = { 1.0, 1.06, 1.12, 1.18, 1.25 }, -- 성과급 배율 (숙련도가 오를수록 조금씩)
	penaltyCap = 1.0, -- 실수 차감은 성과급 합계의 이 비율까지만 (기본급은 깎지 않음)
	minPayout = 100, -- 이보다 적으면 지급 없음
}

-------------------------------------------------------------------------------------------------
-- Skill tracks (숙련도). XP per finished job unit; each level changes REAL things (menu, options,
-- tools, base pay, workplaces). Track ids = job kinds.
-------------------------------------------------------------------------------------------------
C.LEVELS = {
	xp = { 0, 120, 320, 650, 1100 }, -- XP needed for Lv1..Lv5
	titles = {
		cafe = { "견습 바리스타", "바리스타", "시니어 바리스타", "바 리더", "수석 바리스타" },
		cvs = { "신입 알바", "알바생", "베테랑 알바", "매니저", "점장 대행" },
		kitchen = { "주방 보조", "홀·주방 서버", "라인 쿡", "부주방장", "주방장" },
		delivery = { "신입 라이더", "라이더", "베테랑 라이더", "에이스 라이더", "전설의 라이더" },
	},
	-- 직급 (every track): Lv1 신입 → Lv2 직원 → Lv3-4 숙련 직원 → Lv5 매니저급
	ranks = { "신입", "직원", "숙련 직원", "숙련 직원", "매니저급" },
	-- hint level by skill level: 2 = step-by-step, 1 = short reminders, 0 = off (player can override)
	hintsByLevel = { 2, 2, 1, 1, 0 },
}

-- New duties per level (shown on level-up / the job board; the store kinds check C.UNLOCKS[track][duty]).
C.UNLOCKS = {
	cvs = {
		parcel = { level = 2, label = "택배 접수 (무게 · 요금 · 20kg 거절)" },
		cigarettes = { level = 2, label = "담배 판매 (번호 · 신분증)" },
		refund = { level = 3, label = "진상 응대 · 환불 처리" },
		reorder = { level = 3, label = "재고 발주 (창고 박스 관리)" },
		count_till = { level = 4, label = "마감 시재 정산 (금고 세기)" },
		trainee = { level = 5, label = "신입 교육 (후배 질문 답하기)" },
	},
	delivery = {
		quick = { level = 2, label = "퀵 배달 (장거리 · 높은 단가)" },
		group = { level = 3, label = "단체 주문 (여러 곳 연속 배달)" },
		premium = { level = 4, label = "프리미엄 주문 (차량 필수 · 단가 1.6배)" },
		night = { level = 5, label = "야간 할증 · VIP 단골 콜" },
	},
	cafe = {},
	kitchen = {},
}

-- XP per unit of work (a perfect unit gives the full amount, a fixed or late one less)
C.XP = { order = 14, perfectExtra = 6, task = 6, closeTask = 4, shiftComplete = 20, event = 10, delivery = 24 }

-------------------------------------------------------------------------------------------------
-- Jobs handled by the work simulation (G.JOBS ids). `work` = the station system to run.
-- requires = { track = level } to apply (better workplaces need experience).
-------------------------------------------------------------------------------------------------
C.JOB_ORDER = { "starbucks", "gs25", "delivery_food", "delivery_quick", "hoe" }
C.JOBS = {
	starbucks = {
		track = "cafe",
		work = "cafe",
		title = "카페 바리스타",
		place = "스타벅스 광안리점",
		icon = "☕",
		duty = "POS 주문 확인 → 음료 제조 (컵·샷·얼음·우유·뚜껑) → 픽업대 호출 · 마감 청소",
		perf = "주문 1건 1,000~2,200원 (메뉴·옵션 난이도) · 정확 +30% · 빠른 전달 +20%",
		requires = nil,
		uniform = { color = { 0, 98, 65 }, text = "☕ BARISTA" },
	},
	gs25 = {
		track = "cvs",
		work = "cvs",
		title = "편의점 알바",
		place = "GS25 광안리점",
		icon = "🏪",
		duty = "바코드 스캔 · 카드/현금 결제 · 봉투 담기 · 상자 진열 · 냉장고 보충 · 청소",
		perf = "계산 1건 600~1,400원 · 진열/보충 400원 · 정확 +30%",
		requires = nil,
		uniform = { color = { 28, 118, 214 }, text = "GS25 STAFF" },
	},
	hoe = {
		track = "kitchen",
		work = "kitchen",
		title = "횟집 주방·홀",
		place = "민락회타운",
		icon = "🐟",
		duty = "주문 확인 → 재료 손질 → 조리 (회 썰기 · 매운탕 끓이기 · 전 굽기) → 플레이팅 → 서빙 → 식기 회수",
		perf = "요리 1접시 1,600~3,200원 · 정확·익힘 +30% · 빠른 서빙 +20%",
		requires = { cafe = 3, cvs = 3 }, -- either track at Lv3 (any = true)
		requiresAny = true,
		uniform = { color = { 235, 235, 235 }, text = "🐟 민락회타운" },
	},
	-- 배달: both clock in at the 광안 딜리버리 office. `gjob` = the G.JOBS id the employment is filed
	-- under (Jobs.apply); delivery_food has no G.JOBS entry of its own.
	delivery_food = {
		track = "delivery",
		work = "delivery",
		mode = "food",
		gjob = "delivery_quick",
		title = "음식 배달",
		place = "광안 딜리버리",
		icon = "🛵",
		duty = "배달 콜 수락 → 식당에서 포장 (용기·뚜껑·봉투·영수증·봉인) → 이동 (도보·자전거·오토바이·차) → 전달 → 정산",
		perf = "배달 1건 거리 비례 1,800~6,000원 · 음식 상태 · 시간 준수 · 비 오는 날 할증",
		requires = nil,
		uniform = { color = { 42, 193, 188 }, text = "광안 딜리버리" },
	},
	delivery_quick = {
		track = "delivery",
		work = "delivery",
		mode = "quick",
		gjob = "delivery_quick",
		fallback = "delivery_food", -- not qualified yet (legacy dispatch table): start this instead
		title = "퀵 배달",
		place = "광안 딜리버리",
		icon = "📦",
		duty = "사무실에서 퀵 물건 수령 (서명·포장 확인) → 장거리 이동 → 수령인 확인 → 전달",
		perf = "퀵 1건 3,000~9,000원 · 장거리 · 짧은 제한 시간 · 정시 보너스",
		requires = { delivery = 2, cvs = 2 },
		requiresAny = true,
		uniform = { color = { 255, 196, 40 }, text = "광안 퀵서비스" },
	},
}

-------------------------------------------------------------------------------------------------
-- CAFE (스타벅스 광안리점): menu, options and tools by skill level
-------------------------------------------------------------------------------------------------
C.CAFE = {
	-- menu unlocks: level -> menu ids
	menuByLevel = {
		{ "americano", "latte" },
		{ "vanilla_latte" },
		{ "cappuccino" },
		{ "caramel_macchiato" },
		{},
	},
	-- options unlocked at a level: size (톨/그란데), temp (HOT/ICE choice on lattes), shot (샷 추가)
	optionsByLevel = { size = 2, temp = 3, shot = 3 },
	-- tools (real station changes)
	tools = {
		steam2 = { level = 2, label = "스팀 피처 2개", desc = "우유 두 잔을 동시에 스팀" },
		machine2 = { level = 3, label = "2번 에스프레소 머신", desc = "샷 4잔 동시 추출" },
		tray = { level = 4, label = "서빙 트레이", desc = "컵 2개를 한 번에 운반" },
		grinder = { level = 5, label = "고속 그라인더", desc = "추출 시간 -25%" },
	},
	extractSeconds = 5.0, -- per shot (both shots of a double come out together)
	steamSeconds = 4.0,
	warmupSeconds = 3.5, -- 머신 예열 (오픈 준비)
	cleanAfterShots = 14, -- 머신 청소 표시등이 켜지는 추출 횟수 (청소 전까지 추출 1.5배 느림)
	stock = { -- start / max per shift (오픈 준비 때 채워야 함)
		cup_ice = { start = 5, max = 12, refill = 12, label = "아이스 컵" },
		cup_hot = { start = 5, max = 12, refill = 12, label = "핫 컵" },
		lid = { start = 8, max = 20, refill = 20, label = "뚜껑" },
		ice = { start = 4, max = 12, refill = 12, label = "얼음" },
		milk = { start = 3, max = 10, refill = 10, label = "우유" },
		beans = { start = 10, max = 24, refill = 24, label = "원두 (샷)" },
		vanilla = { start = 6, max = 12, refill = 12, label = "바닐라 시럽" },
		caramel = { start = 6, max = 12, refill = 12, label = "카라멜 시럽" },
	},
	lowStockShare = 0.25, -- warn at or below this share of max
	spillSpeed = 21, -- studs/s: running with an open cup with liquid in it spills it
	spillSeconds = 0.8, -- this long above spillSpeed
	-- customers (test customers / NPC orders): per phase, seconds between new customers
	arrival = { prep = { 22, 30 }, rush = { 8, 13 }, close = { 18, 26 } },
	maxOpenOrders = 5,
	patience = { base = 80, perItem = 25 }, -- seconds a customer waits for the whole order
	targetSeconds = { base = 30, perItem = 14 }, -- 빠른 전달 보너스 기준
	pickupSlots = 4,
	groupChance = 0.12, -- 단체 주문 (3~4잔) chance per new order in 피크
	changeChance = 0.10, -- 주문 변경 chance per open order (once) while 준비 중
	perfByMenu = { americano = 1000, latte = 1300, vanilla_latte = 1600, cappuccino = 1600, caramel_macchiato = 2000 },
	perfPerOption = 200,
	closeTasks = { "clean_machine", "wipe_counter", "empty_trash", "restock_cups" },
}

-------------------------------------------------------------------------------------------------
-- CONVENIENCE STORE (GS25 광안리점)
-------------------------------------------------------------------------------------------------
C.CVS = {
	arrival = { prep = { 24, 32 }, rush = { 10, 15 }, close = { 20, 28 } },
	maxOpenOrders = 3,
	patience = { base = 70, perItem = 8 },
	targetSeconds = { base = 22, perItem = 5 },
	perfBase = 600,
	perfPerItem = 120,
	perfTask = 400, -- 진열 / 냉장고 보충 / 청소 1건
	cashChance = 0.35, -- share of customers paying cash (cash = choose the change)
	bagChance = 0.55, -- share of customers who want a bag (they only say so when asked)
	bagPrice = 50, -- 비닐봉투 (유상 판매)
	idCheckLevel = 1, -- 술 (신분증 확인) from Lv1; 담배 from C.UNLOCKS.cvs
	idCheckChance = 0.12,
	minorChance = 0.45, -- a teen who brings an age-restricted item: share that are really minors
	shelfCapacity = 10, -- units per shelf category
	shelfStart = 6, -- 오픈 시 진열 수량
	boxSize = 6, -- units in a restock box
	backroomBoxes = 3, -- boxes per category in the 창고 (Lv3+: finite → 재고 발주)
	orderArriveSeconds = 40, -- 발주한 박스가 창고에 들어오기까지
	trashMax = 10, -- 쓰레기통 용량 (계산 1건 = 영수증 · 포장 쓰레기 1)
	barcodeFailChance = 0.12, -- 바코드가 안 찍히는 상품 (수동 입력)
	parcelMaxKg = 20,
	parcelRates = { -- 편의점 택배 요금표
		{ max = 1, label = "1kg 이하", price = 1800 },
		{ max = 5, label = "5kg 이하", price = 2300 },
		{ max = 10, label = "10kg 이하", price = 2800 },
		{ max = 20, label = "20kg 이하", price = 3800 },
	},
	parcelDests = { "서울", "대구", "대전", "울산", "창원", "제주", "광주", "인천" },
	tillStart = 100000, -- 시재 (오픈 시 금고 현금)
	cashNotes = { 1000, 5000, 10000, 50000 },
	eventEvery = { 55, 85 }, -- seconds between random store events (피크 타임)
	puddleChance = 0.35, -- per event roll: 손님이 음료를 흘림 (비 오는 날 2배: 젖은 발자국)
	-- products by shelf category (prices = 소비자가). adult = 신분증 확인 (술 / 담배)
	categories = {
		{ id = "food", label = "식품", shelf = "slot_food", color = { 236, 196, 120 } },
		{ id = "snack", label = "과자", shelf = "slot_snack", color = { 240, 150, 90 } },
		{ id = "drink", label = "음료·주류", shelf = "slot_drink", color = { 110, 180, 240 } },
		{ id = "life", label = "생활용품", shelf = "slot_life", color = { 170, 200, 160 } },
	},
	products = {
		{ id = "samgak", name = "삼각김밥", icon = "🍙", price = 1200, cat = "food", color = { 245, 245, 245 } },
		{ id = "dosirak", name = "도시락", icon = "🍱", price = 4500, cat = "food", color = { 220, 90, 60 }, heat = true },
		{ id = "ramen", name = "컵라면", icon = "🍜", price = 1500, cat = "food", color = { 230, 60, 40 } },
		{ id = "sandwich", name = "샌드위치", icon = "🥪", price = 2800, cat = "food", color = { 240, 220, 160 } },
		{ id = "choco", name = "초코바", icon = "🍫", price = 1000, cat = "snack", color = { 110, 60, 30 } },
		{ id = "chips", name = "감자칩", icon = "🥔", price = 1700, cat = "snack", color = { 250, 200, 40 } },
		{ id = "gum", name = "껌", icon = "🍬", price = 800, cat = "snack", color = { 120, 220, 160 } },
		{ id = "icecream", name = "아이스크림", icon = "🍦", price = 1300, cat = "snack", color = { 250, 240, 220 } },
		{ id = "water", name = "생수", icon = "💧", price = 900, cat = "drink", color = { 150, 210, 250 }, shape = "bottle" },
		{ id = "cola", name = "콜라", icon = "🥤", price = 1800, cat = "drink", color = { 200, 30, 30 }, shape = "can" },
		{ id = "milk", name = "바나나우유", icon = "🥛", price = 1700, cat = "drink", color = { 250, 230, 120 } },
		{ id = "coffee", name = "캔커피", icon = "☕", price = 1400, cat = "drink", color = { 120, 80, 50 }, shape = "can" },
		{ id = "beer", name = "캔맥주", icon = "🍺", price = 3000, cat = "drink", color = { 230, 200, 60 }, shape = "can", adult = true },
		{ id = "soju", name = "소주", icon = "🍶", price = 1950, cat = "drink", color = { 60, 170, 90 }, shape = "bottle", adult = true },
		{ id = "tissue", name = "물티슈", icon = "🧻", price = 2000, cat = "life", color = { 240, 240, 250 } },
		{ id = "battery", name = "건전지", icon = "🔋", price = 3500, cat = "life", color = { 60, 60, 60 } },
		{ id = "umbrella", name = "우산", icon = "☂️", price = 6000, cat = "life", color = { 40, 60, 120 }, rain = true },
		{ id = "hangover", name = "숙취해소제", icon = "💊", price = 3500, cat = "life", color = { 240, 180, 60 } },
	},
	-- behind the counter (not on a shelf): 담배 by number on the rack, Lv2+
	cigarettes = { { n = 1, name = "에쎄 체인지" }, { n = 2, name = "말보로 레드" }, { n = 3, name = "디스 플러스" }, { n = 4, name = "레종 블루" }, { n = 5, name = "던힐 파인컷" }, { n = 6, name = "메비우스" } },
	cigarettePrice = 4500,
	posRebootSteps = { "전원 버튼 길게 누르기", "재부팅 기다리기", "근무자 코드 로그인", "카드 단말기 연결 확인" },
	closeTasks = { "mop_floor", "face_shelves", "trash_out", "count_till" },
	closeTasksByLevel = { count_till = 4 }, -- a task listed here starts at that level
}

-------------------------------------------------------------------------------------------------
-- NPC CUSTOMERS (WorkCustomers): personalities. weight = spawn share; patience / walk = multipliers.
-- lines live in GwangalliWorkLines (several per situation, never the same twice in a row).
-------------------------------------------------------------------------------------------------
C.CUSTOMERS = {
	maxPerStore = 4,
	walkSpeed = 5.2, -- studs / s
	spawnGap = { prep = { 16, 24 }, rush = { 7, 12 }, close = { 16, 24 } },
	nagEvery = 14, -- s between impatient lines (급한 손님 more often)
	pickupWait = 50, -- s a called cafe customer waits at the pick-up counter
	personas = {
		normal = { label = "평범한 손님", weight = 40, patience = 1.0, walk = 1.0, icon = "🙂" },
		hurry = { label = "급한 손님", weight = 14, patience = 0.6, walk = 1.3, icon = "⏱️", nag = 0.5 },
		drunk = { label = "취객", weight = 8, patience = 1.3, walk = 0.55, icon = "🥴", night = 2.5, wander = true },
		karen = { label = "진상 손님", weight = 9, patience = 0.85, walk = 1.0, icon = "😤", strict = true, level = 1 },
		student = { label = "학생", weight = 14, patience = 0.9, walk = 1.15, icon = "🎒", group = { 2, 3 } },
		regular = { label = "단골", weight = 15, patience = 1.4, walk = 1.0, icon = "😊", tip = { 300, 1000 } },
	},
	reaction = { thanks = "😊", ok = "🙂", complain = "😕", angry = "😠", left = "💢" },
}

-------------------------------------------------------------------------------------------------
-- KITCHEN (민락회타운): each dish has its own way of cooking
-------------------------------------------------------------------------------------------------
C.KITCHEN = {
	arrival = { prep = { 30, 38 }, rush = { 16, 22 }, close = { 28, 36 } },
	maxOpenOrders = 3,
	patience = { base = 140, perItem = 40 },
	targetSeconds = { base = 60, perItem = 25 },
	perfByDish = { hoe = 2600, maeuntang = 3200, pajeon = 2200, rice = 600 },
	stewBoilSeconds = 9, -- 매운탕: 끓기 시작까지
	stewWindow = { 5, 11 }, -- 끓기 시작 후 이 범위 안에 불을 끄면 딱 좋음
	pajeonFlipWindow = { 4, 7 }, -- 전: 이 시간 사이에 뒤집기, 다시 같은 시간 후 꺼내기
	sliceCount = 6, -- 회: 썰기 횟수 (일정한 두께 = 탭 간격 일정)
	closeTasks = { "wash_dishes", "clean_grill", "wipe_tables" },
}

-------------------------------------------------------------------------------------------------
-- DELIVERY (광안 딜리버리): uses the existing vehicles / walking; no driving code here
-------------------------------------------------------------------------------------------------
C.DELIVERY = {
	perStud = 3.2,
	base = 1400,
	timeBase = 45, -- seconds + distance / speed of the chosen way of travel
	speedByMode = { walk = 13, bicycle = 24, motorbike = 34, car = 38 },
	conditionBumpSpeed = 35, -- studs/s velocity change in one tick that shakes the food
	conditionBumpLoss = 8,
	hardBrakeAccel = 34, -- studs/s² while seated: 급정거 (a small loss per tick)
	conditionLatePerSecond = 0.6,
	conditionSpeedLimit = 95, -- studs/s: faster than this slowly ruins the food (soup spills)
	conditionSpeedLoss = 2.0, -- per second above the limit
	rainBumpFactor = 0.75, -- rain: a smaller jolt already shakes (slippery roads)
	rainBonus = 0.2, -- 우천 할증 +20 %
	lateMinFactor = 0.5, -- a very late delivery still pays half (never zero)
	handoverRadius = 10,
	packSteps = { "container", "lid", "bag", "receipt", "seal" },
	packLabels = { container = "용기 확인 (메뉴·수량)", lid = "뚜껑 닫기", bag = "봉투에 담기", receipt = "영수증 부착", seal = "안심 스티커 봉인" },
	quickSteps = { "check", "sign", "pack" },
	quickLabels = { check = "물건·수령인 확인", sign = "발송인 서명 받기", pack = "퀵 봉투 포장" },
	maxActive = 1,
	callsOffered = 3, -- 배달 앱에 보이는 콜 수
	callRefresh = 25, -- s
	cookSeconds = { 8, 18 }, -- the restaurant cooks after the call is accepted
	minDist = 120,
	maxDist = 1400,
	food = { base = 1800, perStud = 3.0, timeBase = 60, timeSpeed = 16 },
	quick = { base = 3000, perStud = 4.2, timeBase = 40, timeSpeed = 20, minDist = 400 },
	premiumMult = 1.6, -- Lv4 프리미엄 주문 (차로만, 음식 상태 2배 중요)
	groupBonus = 0.25, -- 단체 주문 (여러 곳 배달) 전부 성공
	tipChance = 0.25,
	tip = { 500, 2000 },
	addressChangeChance = 0.12, -- per order: 주소 변경
	absentChance = 0.15, -- per drop: 고객 부재 (전화 → 문 앞)
	-- pick-up restaurants (Destination DisplayName); the missing ones are skipped
	restaurants = {
		{ dest = "브롱스 광안리 (호메르스호텔 1F)", name = "브롱스 광안리", menu = { "수제 버거 세트", "피시앤칩스", "치킨 윙 바스켓" }, soup = false },
		{ dest = "fondx 홍미당 (아쿠아펠리스 1F)", name = "홍미당", menu = { "딸기 케이크", "마카롱 6구", "생크림 롤" }, soup = false, fragile = true },
		{ dest = "스타벅스 광안역점", name = "스타벅스 광안역점", menu = { "아메리카노 4잔", "라떼 2잔 + 샌드위치" }, soup = true },
		{ dest = "빵천동 빵집골목", name = "빵천동 베이커리", menu = { "소금빵 6개", "단팥빵 세트" }, soup = false },
		{ dest = "민락회타운", name = "민락회타운", menu = { "모둠회 (중)", "매운탕 2인" }, soup = true },
		{ dest = "밀락더마켓", name = "밀락더마켓", menu = { "타코 세트", "피자 한 판" }, soup = false },
	},
	premiumMenu = { "한우 오마카세 도시락", "랍스터 플래터", "프리미엄 초밥 세트" },
	quickItems = { "계약 서류 봉투", "노트북 충전기", "급한 열쇠 꾸러미", "인쇄물 박스", "꽃다발" },
	closeTasks = { "return_gear", "report" },
}

-------------------------------------------------------------------------------------------------
-- Satisfaction → NPC reaction (sent to the NPC session through WorkOrders)
-------------------------------------------------------------------------------------------------
C.SATISFACTION = {
	weightAccuracy = 0.7,
	weightSpeed = 0.3,
	thanks = 80, -- >= : 감사 (+팁 표시만, 팁은 직원 급여가 아닌 서비스 보너스로 이미 반영)
	ok = 55, -- >= : 보통
	complain = 30, -- >= : 불평, below: 퇴점 수준 불만
}

-------------------------------------------------------------------------------------------------
-- Goals (돈의 쓰임): ids into the existing catalogs (GwangalliGarageShared / G.LISTINGS / G.FURNITURE)
-------------------------------------------------------------------------------------------------
C.GOALS = {
	{ kind = "car", id = "compact", grade = "used", label = "첫 차 · 큐비 중고" },
	{ kind = "home", id = "oneroom", field = "deposit", label = "원룸 보증금" },
	{ kind = "furniture", id = "sofa_ikea", label = "패브릭 2인 소파" },
	{ kind = "car", id = "sedan", grade = "used", label = "미드 세단 중고" },
	{ kind = "home", id = "officetel", field = "deposit", label = "오피스텔 보증금" },
	{ kind = "furniture", id = "tv_modern", label = "65인치 OLED TV" },
	{ kind = "home", id = "xi_apt", field = "price", label = "광안자이 아파트" },
}

-------------------------------------------------------------------------------------------------
-- Sounds: built-in rbxasset sounds work in Roblox and in the studio (approximated there).
-- Replace with uploaded assets for the real 추출음 / 스팀음 (see docs/WORK_SIM.md "필요한 자산").
-------------------------------------------------------------------------------------------------
C.SOUNDS = {
	tap = "rbxasset://sounds/clickfast.wav",
	pickup = "rbxasset://sounds/swoosh.wav",
	place = "rbxasset://sounds/clickfast.wav",
	extract = "rbxasset://sounds/action_falling.mp3", -- placeholder: 에스프레소 추출음 자산 필요
	steam = "rbxasset://sounds/action_swim.mp3", -- placeholder: 스팀음 자산 필요
	ice = "rbxasset://sounds/clickfast.wav",
	pour = "rbxasset://sounds/action_swim.mp3",
	ready = "rbxasset://sounds/electronicpingshort.wav", -- 픽업 알림 / 주문 출력
	scan = "rbxasset://sounds/electronicpingshort.wav",
	error = "rbxasset://sounds/uuhhh.mp3",
	coin = "rbxasset://sounds/electronicpingshort.wav",
	sizzle = "rbxasset://sounds/action_swim.mp3",
	chop = "rbxasset://sounds/clickfast.wav",
}

-- Character work animations: empty = no asset yet (the client uses its procedural carry pose).
-- Put uploaded animation ids here; the client plays them on the local character.
C.ANIMATIONS = {
	carry = "",
	pour = "",
	scan = "",
	wipe = "",
	chop = "",
	box = "",
}

return C
