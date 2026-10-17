-- GwangalliCarDealerShared/Lines: what the dealers say (Korean). Two voices: "consult" (한서윤 대리 · polite,
-- warm showroom consultant) and "boss" (박사장 · 광안 오토 대표, friendly with a light 부산 사투리).
--   Lines.get(voice, key, vars?, seed?) -> string     {name} style placeholders, variants picked by seed

local U = require(script.Parent:WaitForChild("Util"))

local Lines = {}

local L: { [string]: { [string]: { string } } } = {}

L.consult = {
	greet_first = {
		"안녕하세요, 광안 오토에 오신 걸 환영해요! 영업 컨설턴트 한서윤입니다. 어떤 차 찾고 계세요?",
		"어서 오세요! 광안 오토 한서윤 대리예요. 첫 차 보러 오셨어요? 편하게 둘러보시고 궁금한 건 다 물어보세요 😊",
	},
	greet_back = {
		"{player}님, 또 오셨네요! 오늘은 어떤 차 보러 오셨어요?",
		"다시 뵈니 반가워요, {player}님! 그사이 새로 들어온 차도 있어요.",
	},
	greet_tested = {
		"{player}님! 지난번에 시승하신 {car}, 아직 고민 중이세요? 오늘 조건 좋아요 😉",
	},
	greet_owner = {
		"{car} 잘 타고 계세요? 정비는 옆 정비 베이 김기사님께 맡기시면 돼요. 오늘은 뭐 도와드릴까요?",
		"{player}님, {car} 오너시죠! 한 대 더 들이시게요? 😄",
	},
	greet_full = {
		"차고가 꽉 찼네요 ({owned}/{max}대)! 타던 차를 보상판매로 넘기시면 바로 새 차로 바꿔 드릴 수 있어요.",
	},
	menu = { "어떤 걸 도와드릴까요?" },
	special_intro = {
		"{month}월 특가 차량은 {list:이에요}! 계약하시면 출고 즉시 차값의 {pct}를 통장으로 환급해 드려요. 이번 달 {days}일 남았어요.",
	},
	special_none = { "이번 달 특가는 모두 마감됐어요. 대신 레벨 혜택이랑 할부 조건은 그대로예요!" },
	budget_ask = { "예산은 어느 정도 생각하세요? 지금 잔액 기준으로 딱 맞는 차를 골라 드릴게요." },
	budget_full = {
		"그 예산이면 {car:이} 제일 좋아요. {price}이고, 지금 바로 일시불로 출고돼요!",
	},
	budget_loan = {
		"{car} 어떠세요? 할부로 하시면 계약금 {down}만 내시고, 하루 {daily}씩 {days}일이면 끝나요.",
	},
	budget_save = {
		"지금 잔액으로는 {car}까지 {short}이 모자라요. 알바 몇 번 더 하시면 금방이에요! 찜해 두시면 제가 기억해 둘게요.",
	},
	budget_none = { "조건에 맞는 차가 아직 없어요. 전체 차량부터 같이 보실까요?" },
	trade_intro = {
		"타던 차를 넘기시면 매입가에 {bonus} 추가 정산금을 얹어 드려요. 남은 할부는 매입가에서 정리돼요.",
	},
	trade_none = { "아직 팔 수 있는 차가 없으세요. 렌트한 차는 반납만 가능해요!" },
	test_ask = { "어떤 차로 시승해 보시겠어요? 정비소 앞 출고 라인에서 바로 빼 드릴게요." },
	test_go = { "{car} 시승차 준비됐어요! 안전벨트 매시고, 코스 따라 한 바퀴 돌고 오세요 🏁" },
	test_shift = { "근무 중이시네요! 근무 끝나고 오시면 바로 시승 잡아 드릴게요." },
	test_taxi = { "지금은 택시 운행 중이세요. 운행 끝나고 오세요!" },
	test_cuffed = { "지금은 시승을 도와드릴 수가 없어요…" },
	test_cooldown = { "시승차 정비 중이에요. {sec}초만 기다려 주세요!" },
	test_busy = { "이미 시승 중이세요! 코스부터 다녀오세요 😄" },
	rent_ask = {
		"{car:을} 게임 시간 하루({minutes}분) 동안 {fee}에 빌려 드려요. 차고 대수에는 안 들어가요. 바로 빼 드릴까요?",
	},
	rent_have = { "이미 렌트하신 차가 있어요. '내 차'에서 부르시면 돼요!" },
	rent_done = { "렌트 완료! 정비소 앞으로 차 가져다 놨어요. 즐거운 드라이브 되세요 🔑" },
	mine = { "내 차 관리 화면 열어 드릴게요. 부르기 · 정비 · 판매 다 거기서 돼요." },
	bye = {
		"천천히 둘러보세요! 궁금한 건 언제든 불러 주세요 😊",
		"네, 편하게 구경하세요. 저는 여기 있을게요!",
	},
	after_test = {
		"시승 어떠셨어요? {car}, 승차감 괜찮죠? 😄 마음에 드시면 바로 계약 도와드릴게요.",
		"최고 {kmh}km/h까지 밟아 보셨네요! {car} 잘 나가죠?",
	},
	delivered = {
		"축하드려요! {car} 출고 완료예요 🎉 번호판은 {plate:이에요}. 안전 운전하세요!",
	},
	offline = { "죄송해요, 지금 전산 점검 중이라 계약이 잠시 어려워요. 차는 마음껏 구경하세요!" },
	loading = { "잠시만요, 고객님 정보 불러오는 중이에요…" },
	far = { "계약이랑 시승은 광안 오토 매장에서 저한테 말씀해 주세요. 길 안내 해 드릴까요?" },
	full = { "차는 최대 {max}대까지 가질 수 있어요. 보상판매로 한 대 넘기시고 바꾸시는 건 어떠세요?" },
	sold = { "매각 완료! {car} 매입가 정산해서 통장으로 넣어 드렸어요." },
}

L.boss = {
	greet_first = {
		"어서 오이소! 광안 오토 박사장입니더. 차 보러 왔능교? 편하게 보이소~",
		"아이고 손님 오셨네! 광안 오토 대표 박사장이라예. 뭐 찾는 차 있습니꺼?",
	},
	greet_back = {
		"{player} 씨 또 왔네! 반갑데이. 오늘은 뭐 보러 왔노?",
	},
	greet_tested = {
		"{player} 씨, 저번에 {car} 몰아 봤제? 그거 물건이다 아이가. 오늘 계약할라꼬?",
	},
	greet_owner = {
		"{car} 잘 굴러가제? 손볼 데 있으면 김기사한테 맡기래이. 오늘은 뭐 도와주꼬?",
	},
	greet_full = {
		"차고가 꽉 찼네 ({owned}/{max}대)! 타던 거 보상판매로 넘기면 내가 잘 쳐 주께.",
	},
	menu = { "뭐 도와주꼬?" },
	special_intro = {
		"{month}월 특가는 {list:이다}! 계약하믄 차값 {pct} 바로 통장에 돌려준다. 이번 달 {days}일 남았데이.",
	},
	special_none = { "이번 달 특가는 다 나갔다. 대신 할부는 언제든 된데이!" },
	budget_ask = { "예산은 얼마나 생각하노? 딱 맞는 놈으로 골라 주께." },
	budget_full = { "그 돈이면 {car:이} 딱이다. {price}, 지금 바로 끌고 가도 된다!" },
	budget_loan = { "{car} 함 보래이. 할부로 하믄 계약금 {down}에 하루 {daily}씩 {days}일이면 끝이다." },
	budget_save = { "{car}까지 {short} 모자라네. 알바 쪼매만 더 하고 온나, 내가 빼 두께!" },
	budget_none = { "딱 맞는 기 없네. 전체 차부터 함 보자!" },
	trade_intro = { "타던 차 넘기믄 매입가에 {bonus} 더 얹어 주께. 남은 할부는 매입가에서 정리한데이." },
	trade_none = { "팔 차가 아직 없네! 렌트한 거는 반납만 된데이." },
	test_ask = { "뭘로 몰아 볼래? 정비소 앞 출고 라인에 바로 빼 주께." },
	test_go = { "{car} 시승차 나왔데이! 코스 따라 한 바퀴 돌고 온나 🏁" },
	test_shift = { "일하는 중이네! 일 끝나고 온나, 시승은 그때 하자." },
	test_taxi = { "택시 운행 중이제? 끝나고 온나!" },
	test_cuffed = { "지금은 좀 곤란하데이…" },
	test_cooldown = { "시승차 손보는 중이다. {sec}초만 기다리래이!" },
	test_busy = { "벌써 시승 중이다 아이가! 코스부터 다녀온나." },
	rent_ask = { "{car} 하루({minutes}분) 빌리는 데 {fee}다. 차고에는 안 친다. 빼 주까?" },
	rent_have = { "렌트한 차 벌써 있다 아이가! '내 차'에서 부르믄 된다." },
	rent_done = { "렌트 끝! 정비소 앞에 갖다 놨데이. 살살 몰아래이 🔑" },
	mine = { "내 차 관리 화면 열어 주께. 부르기 · 정비 · 판매 다 거서 된다." },
	bye = { "천천히 구경하이소~ 볼일 있으면 부르래이!" },
	after_test = { "어떻노, {car} 잘 나가제? 최고 {kmh}km/h 찍었네! 마음에 들믄 바로 계약하자." },
	delivered = { "축하한데이! {car} 출고다 🎉 번호판 {plate}. 안전 운전하래이!" },
	offline = { "미안하데이, 지금 전산이 먹통이라 계약은 쪼매 있다 하자. 구경은 맘껏 하고!" },
	loading = { "잠깐만, 장부 좀 보고…" },
	far = { "계약이랑 시승은 매장 와서 내한테 말해래이. 길 알려 주까?" },
	full = { "차는 {max}대까지다. 하나 보상판매로 넘기고 바꾸자!" },
	sold = { "매각 끝! {car} 값 통장에 넣어 놨데이." },
}

function Lines.get(voice: string?, key: string, vars: { [string]: any }?, seed: number?): string
	local bank = L[voice or "consult"] or L.consult
	local list = bank[key] or L.consult[key]
	if not list or #list == 0 then
		return ""
	end
	local i = if seed then (math.floor(math.abs(seed)) % #list) + 1 else math.random(1, #list)
	return U.fmt(list[i], vars)
end

function Lines.has(voice: string?, key: string): boolean
	local bank = L[voice or "consult"] or L.consult
	return bank[key] ~= nil or L.consult[key] ~= nil
end

return Lines
