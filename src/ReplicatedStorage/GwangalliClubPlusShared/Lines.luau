-- GwangalliClubPlusShared.Lines: Korean text for the LED wall, boards, receipts and errors.
-- All-ages wording only: drinks are 음료 / 세트, the 합석 이벤트 is a friends' mixer (no dating words).

local Lines = {}

Lines.Receipt = {
	ok = { "📺 전광판 송출 예약 완료", "%d번째 순서 · 약 %d초 뒤 전광판에 떠요" },
	okNow = { "📺 전광판 송출 시작!", "가운데 전광판을 봐 주세요 ✨" },
	nofunds = { "잔액이 부족해요", "현금이나 체크카드 잔액을 확인해 주세요" },
	wait = { "잠시 후 다시 해 주세요", "%d초 뒤에 다시 후원할 수 있어요" },
	full = { "전광판 대기열이 꽉 찼어요", "조금 뒤에 다시 신청해 주세요" },
	mine = { "이미 대기 중인 후원이 있어요", "앞선 후원이 송출된 뒤 다시 신청해 주세요" },
	filter = { "쓸 수 없는 표현이 있어요", "메시지를 바꿔서 다시 보내 주세요" },
	gate = { "클럽 안에서만 할 수 있어요", "CLUB OCEAN 입장 팔찌가 필요해요" },
	amount = { "금액을 다시 확인해 주세요", "5,000원 ~ 10,000,000원 (1,000원 단위)" },
	target = { "대상을 찾을 수 없어요", "테이블이나 DJ가 바뀌었어요. 다시 골라 주세요" },
	busy = { "결제 처리 중이에요", "잠시만 기다려 주세요" },
	slow = { "결제가 지연되고 있어요", "완료되면 자동으로 전광판에 올라가요" },
	error = { "결제에 실패했어요", "잠시 후 다시 시도해 주세요" },
	noapi = { "지금은 후원을 받을 수 없어요", "지갑 시스템을 불러오지 못했어요" },
	off = { "지금은 쉬는 중이에요", "잠시 후 다시 이용해 주세요" },
	robuxOk = { "로벅스 후원 준비 완료", "결제 창에서 구매하면 전광판에 바로 올라가요" },
	robuxDone = { "💎 로벅스 후원 감사합니다!", "전광판 송출 순서에 올렸어요" },
	late = { "📺 결제가 확인됐어요", "전광판 송출 순서에 올렸어요" },
}

Lines.DJ = {
	joined = { "🎧 DJ 대기열에 올랐어요", "%d번째 · 차례가 오면 알려 드릴게요" },
	left = { "DJ 대기열에서 나왔어요", "" },
	turn = { "🎧 지금부터 DJ 타임!", "DJ 부스로 가서 패드를 눌러 보세요 (%d분)" },
	soon = { "곧 DJ 차례예요", "DJ 부스 근처로 와 주세요" },
	ended = { "오늘 밤 디제잉 수고했어요! 🎧", "다음 DJ에게 바통을 넘겼어요" },
	skipped = { "DJ 차례를 놓쳤어요", "클럽 안에 없어서 다음 순서로 넘어갔어요" },
	again = { "조금 쉬었다가 다시 신청해 주세요", "%d초 뒤에 다시 DJ 신청을 할 수 있어요" },
	full = { "DJ 대기열이 꽉 찼어요", "조금 뒤에 다시 신청해 주세요" },
	already = { "이미 DJ 대기열에 있어요", "" },
	far = { "DJ 부스에서 너무 멀어요", "부스로 이동한 뒤 눌러 주세요" },
	cool = { "패드 충전 중이에요", "%d초 뒤에 다시 쓸 수 있어요" },
	notDj = { "지금은 DJ 차례가 아니에요", "" },
	admin = { "관리자 명령 완료", "%s" },
	noAdmin = { "관리자만 쓸 수 있어요", "" },
	refund = { "DJ 신청비를 돌려드렸어요", "%s" },
	paid = { "DJ 신청비 결제 완료", "%s" },
}

-- LED wall / board text
Lines.LED = {
	thanks = "감사합니다",
	orderHead = { "ORDER", "PREMIUM ORDER", "VIP ORDER", "OCEAN LEGEND" },
	donateHead = { "후원 감사합니다", "PREMIUM 후원", "VIP 후원", "LEGEND 후원" },
	toAll = "클럽 전체에",
	toTable = "%s 테이블에",
	toDj = "DJ %s에게",
	cheers = "짠~! ✨",
	booking = "TABLE %s · 합석 이벤트!",
	bookingSub = "%s님 테이블에 새 친구 %d명 등장 ✨",
	bookingMD = "%s의 오늘의 합석",
	onAir = "DJ %s ON AIR",
	djTime = "GUEST DJ TIME",
	idleHint = "📺 전광판 후원 받아요 · 화면 왼쪽 💸 버튼",
	brand = "CLUB OCEAN",
	brandKo = "광안",
	rankUp = "오늘의 큰손 %d위",
	rankKing = "👑 오늘의 큰손 1위!",
	rankChase = "1위까지 %s",
	newKing = "👑 1위 탈환!",
	dethroned = "%s님을 제쳤어요",
}

Lines.Board = {
	title = "CLUB OCEAN 랭킹전",
	spend = "오늘의 큰손 TOP 5",
	donate = "후원 랭킹 TOP 5",
	best = "최고가 주문",
	weekly = "이번 주 랭킹",
	empty = "첫 주인공을 기다려요",
	live = "LIVE",
	tickerIdle = "🎶 CLUB OCEAN 광안 · 음료 주문과 💸 전광판 후원이 랭킹에 올라가요",
}

-- ticker lines (server builds the text; names are filtered)
Lines.Ticker = {
	order = "%s %s님 · %s",
	donate = "💸 %s님 %s 후원",
	dj = "🎧 DJ %s ON AIR",
	king = "👑 %s님 오늘의 큰손 1위!",
}

-- DJ text pad: suggested lines (the DJ can type their own, filtered)
Lines.DJText = { "손 머리 위로! 🙌", "광안리 소리 질러~! 🔊", "다 같이 점프! 🦘", "오늘 밤 최고! 🔥", "CLUB OCEAN 사랑해요 🌊" }

Lines.UI = {
	donateTitle = "💸 전광판 후원",
	donateSub = "닉네임과 메시지가 가운데 전광판에 떠요",
	amount = "후원 금액",
	custom = "직접 입력 (원)",
	message = "메시지 (선택 · 30자)",
	messageHint = "예) 생일 축하해!",
	target = "누구에게",
	all = "클럽 전체",
	tableT = "테이블",
	djT = "DJ",
	send = "%s 후원하기",
	wallet = "잔액 %s",
	robux = "💎 로벅스 후원",
	queue = "대기 중인 전광판 %d개",
	djTitle = "🎧 게스트 DJ",
	djSub = "한 번에 한 명 · %d분씩 차례대로",
	djJoin = "DJ 신청하기",
	djJoinPrice = "DJ 신청하기 · %s",
	djLeave = "대기열 나가기",
	djEnd = "DJ 타임 끝내기",
	djGoto = "DJ 부스로 이동",
	djQueue = "대기 %d명",
	djNow = "지금 DJ",
	djNone = "지금은 레지던트 DJ가 플레이 중이에요",
	djMine = "내 차례 · 남은 시간 %s",
	djWait = "내 순서 %d번째",
	djTextHint = "전광판 문구 (24자)",
	djSendText = "전광판에 띄우기",
	admin = "관리자",
	adminSkip = "다음 DJ",
	adminClear = "대기열 비우기",
	close = "닫기",
	hudDonate = "후원",
	hudDj = "DJ",
}

-- world show / signs / 합석 production (client)
Lines.Show = {
	laserShow = "🟣 OCEAN LASER SHOW · 손 머리 위로! 🙌",
	cheers = "🎉 짠~! %s 테이블 합석 파티 ✨",
	dance = "💃 %s 테이블 다 같이 댄스 타임! 🕺",
	arrive = "✨ %s 테이블 · 새 친구 도착! 반갑게 맞아 주세요",
	djHands = "🙌 DJ %s · 손 머리 위로!",
	signBooking = "✨ 합석 중",
	signDj = "🎧 DJ",
	signGift = "💸 후원 도착",
	presenterFor = "%s · %s님",
	bartender = "🍹 %s 주문 들어갑니다!",
	bartenderLegend = "🍹 %s 레전드 세트 준비 중! ✨",
	crownSpend = "👑 오늘의 큰손",
	crownDonate = "💸 후원왕",
	onAir = "🎧 DJ %s ON AIR",
	residentDj = "🎧 RESIDENT DJ",
}

Lines.Rank = {
	title = "🏆 CLUB OCEAN 랭킹전",
	sub = "%s 밤 · 이번 주 %s",
	tabs = { "오늘의 큰손", "후원 랭킹", "최고가 주문", "이번 주" },
	keys = { "spend", "donate", "best", "weekly" },
	icons = { "👑", "💸", "💎", "📅" },
	mine = "내 기록 · 오늘 후원 %s · 이번 주 %s",
	none = "아직 기록이 없어요 · 첫 주인공이 되어 보세요!",
	newKing = "NEW 1위",
	up = "▲%d",
	new = "NEW",
	shared = "모든 서버 합산 · 1분마다 갱신",
}

Lines.Pad = {
	title = "🎧 DJ 패드",
	left = "남은 시간 %s",
	ready = "준비",
	booth = "부스로 이동",
	finish = "DJ 끝내기",
	textHint = "전광판에 띄울 문구 (24자)",
	send = "보내기",
	collapse = "접기",
	expand = "🎧 패드",
}

return Lines
