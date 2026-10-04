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

local C = {}

C.VERSION = 1

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
	-- hint level by skill level: 2 = step-by-step, 1 = short reminders, 0 = off (player can override)
	hintsByLevel = { 2, 2, 1, 1, 0 },
}

-- XP per unit of work (a perfect unit gives the full amount, a fixed or late one less)
C.XP = { order = 14, perfectExtra = 6, task = 6, closeTask = 4, shiftComplete = 20 }

-------------------------------------------------------------------------------------------------
-- Jobs handled by the work simulation (G.JOBS ids). `work` = the station system to run.
-- requires = { track = level } to apply (better workplaces need experience).
-------------------------------------------------------------------------------------------------
C.JOB_ORDER = { "starbucks", "gs25", "hoe", "delivery_quick" }
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
	delivery_quick = {
		track = "delivery",
		work = "delivery",
		title = "음식 배달",
		place = "광안 딜리버리",
		icon = "🛵",
		duty = "주문 수령 → 내용 확인 → 포장 → 이동 (도보·내 차) → 수령 위치 확인 → 전달 → 정산",
		perf = "배달 1건 거리 비례 1,800~5,000원 · 음식 상태 · 시간 준수 보너스",
		requires = { cvs = 2 },
		uniform = { color = { 42, 193, 188 }, text = "광안 딜리버리" },
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
	arrival = { prep = { 26, 34 }, rush = { 10, 15 }, close = { 20, 28 } },
	maxOpenOrders = 3,
	patience = { base = 70, perItem = 8 },
	targetSeconds = { base = 18, perItem = 4 },
	perfBase = 600,
	perfPerItem = 120,
	perfTask = 400, -- 진열 / 냉장고 보충 / 청소 1건
	cashChance = 0.35, -- share of customers paying cash (cash = choose the change)
	bagChance = 0.6,
	-- items unlocked by level (cigarettes need an ID check from Lv2, age-check event)
	idCheckLevel = 2,
	idCheckChance = 0.12,
	shelfCapacity = 6, -- per product facing
	shelfStart = 3, -- 오픈 시 진열 수량
	boxSize = 6, -- units in a restock box
	closeTasks = { "mop_floor", "face_shelves", "count_till" },
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
	speedByMode = { walk = 13, car = 38 },
	conditionBumpSpeed = 35, -- studs/s velocity change in one tick that shakes the food
	conditionBumpLoss = 8,
	conditionLatePerSecond = 0.6,
	handoverRadius = 10,
	packSteps = { "container", "lid", "bag", "receipt", "seal" },
	maxActive = 1,
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
