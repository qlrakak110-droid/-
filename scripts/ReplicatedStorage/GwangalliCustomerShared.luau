--!nocheck
-- GwangalliCustomerShared (owner: npc_mind · NPC session): the NPC CUSTOMERS of the shops and cafes —
-- who they are (personas), what they say (never the same line twice in a row), where they stand in each
-- store (sites). Pure data + helpers: no instances, no yields.
--
-- The NPC session owns only the customers' BEHAVIOUR: they come in, queue, order with a speech bubble,
-- wait (a patience bar), nag, get angry / leave, or praise / thank. Everything that is the JOB itself
-- (clock-in / out, pay, levels, skill, missions, rewards, what is on the menu, how a drink is judged) is
-- the 알바 session's (ServerScriptService.GwangalliGameplay.Work*). The two meet only at the order
-- interface ServerScriptService.GwangalliGameplay.WorkOrders (registerProvider / placeOrder / receive /
-- cancel), see ServerScriptService.GwangalliGameplay.Customers for the full contract.
--
--   CS.PERSONAS[id]   { label, icon, w (spawn weight; wNight at night), patience (x the job's patience),
--                       walk (studs/s), nagAt = { share of patience ... }, strict (a "complain" becomes
--                       "angry"), praise (an "ok" becomes "thanks"), group = {min, max}, wander (chance),
--                       hint (GwangalliNPCLooks.random hint) }
--   CS.LINES[persona][situation] = { lines }  (falls back to normal). Situations: enter browse order
--                       counter wait nag leave thanks ok complain angry remake called pickup waitPickup
--                       change card cash bagAsk bagNo idShow refused tip wander trouble calmed refund argue
--   CS.pick(memo, persona, situation, rand, vars) -> text
--   CS.SITES[siteId]  where the customers walk, in the frame of the store's Destination part
--                       (dest name; or anchors = the GwJobStation folder of the store's building)

local CS = {}
local L = {}
CS.LINES = L

L.normal = {
	enter = { "안녕하세요~", "(두리번)", "여기 문 열었죠?", "음… 뭐 사지" },
	browse = { "음… 뭐 먹지", "오, 신상 나왔네", "2+1 하는 거 있나", "이거랑… 이거", "아 이거 없네" },
	order = { "{order} 주세요", "{order} 하나 부탁드려요", "음… {order}로 할게요", "{order}요!" },
	counter = { "계산해 주세요~", "이거 계산이요", "이렇게 할게요", "이거 다 주세요" },
	wait = { "(폰 보는 중)", "음…", "(기다리는 중)" },
	nag = { "저… 아직인가요?", "오래 걸려요?", "제 거 들어갔죠?" },
	leave = { "너무 오래 걸리네… 그냥 갈게요", "다음에 올게요…", "에휴, 됐어요" },
	thanks = { "감사합니다~", "수고하세요!", "고마워요 😊", "잘 먹을게요!", "좋은 하루 되세요~" },
	ok = { "네, 수고하세요", "감사합니다", "네~" },
	complain = { "음… 좀 다른데…", "이거 맞나…?", "다음엔 신경 좀 써 주세요" },
	angry = { "이게 뭐예요, 진짜…", "주문한 거랑 완전 다르잖아요", "다시는 안 와요" },
	remake = { "저기요, 이거 제가 시킨 거 아닌데요?", "이거 잘못 나왔어요. 다시 해 주세요", "주문이랑 달라요!" },
	card = { "카드요", "카드로 할게요", "(카드를 내민다)", "삼성페이 돼요?" },
	cash = { "현금이요. {money} 드릴게요", "여기 {money}요", "현금 {money} 받으세요" },
	bagAsk = { "아 봉투요? 네 주세요", "봉투 하나 주세요", "네, 담아 주세요" },
	bagNo = { "아뇨 괜찮아요", "봉투는 됐어요", "그냥 들고 갈게요" },
	idShow = { "아 네, 여기요", "(신분증을 꺼낸다)", "민증 여기요~" },
	refused = { "아… 네", "알겠어요…", "쳇, 알겠어요" },
	called = { "아 제 거다!", "네~ 저요!", "감사합니다~" },
	pickup = { "잘 마실게요!", "감사합니다~", "오 빠르다" },
	waitPickup = { "(픽업대 앞에서 기다리는 중)", "제 음료 언제 나와요?", "(진동벨 확인)" },
	change = { "아 죄송한데, 혹시 바꿀 수 있어요?", "앗 잠깐만요, 변경할게요" },
}

L.hurry = {
	enter = { "빨리빨리…", "(시계를 본다)", "아 늦었다 늦었다" },
	browse = { "아 뭐 사지 빨리", "이거면 돼" },
	order = { "{order}요, 빨리 좀 부탁드려요!", "{order}! 급해요!", "{order} 최대한 빨리요" },
	counter = { "빨리 계산 좀요!", "저 급해서요, 이것만요", "카드 바로 꽂을게요!" },
	wait = { "(발을 동동)", "(시계를 계속 본다)", "하…" },
	nag = { "아직이에요? 저 진짜 급한데", "빨리 좀요…!", "버스 놓치겠다…", "언제 돼요?!", "저기요, 제 거부터 해 주시면 안 돼요?" },
	leave = { "됐어요, 그냥 갈게요!", "아 늦었다, 안 사요!", "시간 없어서 갈게요" },
	thanks = { "오 빠르다! 감사합니다!", "덕분에 살았어요!", "고마워요, 수고하세요!" },
	ok = { "네네 감사합니다", "됐다, 갈게요!" },
	complain = { "좀 늦었네요…", "다음엔 좀 빨리요" },
	angry = { "너무 늦잖아요!", "이렇게 오래 걸릴 줄 알았으면 안 왔죠" },
	card = { "카드! 카드요!", "(카드를 이미 내밀고 있다)" },
	cash = { "현금 {money}! 거스름돈 빨리요", "{money} 여기요, 빨리요" },
	bagNo = { "봉투 필요 없어요, 빨리요!", "그냥 주세요!" },
	bagAsk = { "네 아무거나요, 빨리요!" },
}

L.drunk = {
	enter = { "어어~ 여기가… 편의점 맞쥬?", "히끅… 안녀엉하세여~", "(비틀비틀)", "아따 시원하다~" },
	browse = { "이게… 이게 뭐더라…", "어? 이거 아까 샀나…?", "히끅… 맥주… 맥주 어딨어…", "(진열대에 기댄다)" },
	order = { "어어… {order}… 아니 그거… 그거 줘요…", "{order}… 히끅… 두 개… 아니 하나…", "사장님~ {order}이요오~" },
	counter = { "이거… 이거 계산… 해조요오~", "카드… 카드가 어딨지…", "히끅… 이거 다 얼마여…" },
	wait = { "(꾸벅꾸벅)", "흥얼흥얼~ ♪", "(카운터에 기댄다)" },
	nag = { "아직이여어…?", "사장니임~ 빨리 좀…", "나 여기 단골이여~ 히끅" },
	leave = { "에이… 안 사, 안 사…", "나 간다아~", "(비틀거리며 나간다)" },
	thanks = { "고마워잉~ 히끅", "최고여, 최고!", "학생 착하네~ 수고혀" },
	ok = { "어어… 그려…", "히끅, 고마워~" },
	complain = { "이거… 이거 아닌디…?", "어? 내가 이거 시켰나…" },
	angry = { "아 뭐여 이거!", "나 무시하는 거여 지금?" },
	card = { "카드… 여기… 아니 이건 교통카드네… 히끅", "(지갑을 뒤적인다)" },
	cash = { "옛다~ {money}! 잔돈은… 아니 잔돈 줘", "히끅… {money}… 맞지?" },
	idShow = { "민증? 나 나이 많어~ 히끅", "(신분증을 거꾸로 내민다)" },
	wander = { "어… 화장실이 어디여…", "(이상한 데로 걸어간다)", "여기가 출구여…?", "히끅… 노래 한 곡 할까?" },
	trouble = { "나 안 나가! 여기서 좀 쉬다 갈 거여~", "어이 학생, 이리 와 봐~", "(바닥에 주저앉는다)" },
	calmed = { "어어… 물 고마워…", "그려… 나 간다… 미안혀…", "학생 착하구먼… 집에 갈게" },
}

L.karen = {
	enter = { "(한숨)", "여긴 왜 이렇게 좁아", "점장 있어요?" },
	browse = { "가격이 왜 이래", "이거 유통기한 괜찮은 거 맞아요?", "진열 상태가 이게 뭐야" },
	order = { "{order}. 제대로 해 주세요", "{order}요. 지난번처럼 하면 안 돼요", "{order}. 얼음 적당히요, 적당히!" },
	counter = { "빨리 좀 해요", "아까부터 기다렸는데", "이거 할인 안 돼요?" },
	wait = { "(팔짱)", "(카운터를 톡톡 친다)", "하… 진짜" },
	nag = { "아니 몇 분째예요?", "서비스가 왜 이래요?", "본사에 전화해야 되나" },
	leave = { "됐어요! 리뷰 남길 거예요", "이런 데 다시 오나 봐라", "점장 번호 줘요!" },
	thanks = { "…뭐, 이번엔 괜찮네", "그래요, 이 정도면 됐어요", "흠. 수고했어요" },
	ok = { "다음엔 더 빨리 해요", "뭐… 그냥 그렇네" },
	complain = { "이게 최선이에요?", "맛이 왜 이래요", "제가 말한 거랑 좀 다르잖아요" },
	angry = { "이게 장난해요?", "다시 해 와요, 당장!", "책임자 불러요!" },
	remake = { "이거 다시 만들어요. 제대로", "이걸 먹으라고요? 다시요", "제가 뭐라고 했어요? 다시!" },
	refund = { "이거 환불해 줘요", "이거 어제 샀는데 이상해요. 환불이요", "돈 돌려줘요" },
	argue = { "아니 영수증이 왜 필요해요?", "제가 거짓말한다는 거예요?", "다른 지점은 해 주던데?" },
	refundOk = { "진작 그럴 것이지", "흥, 됐어요" },
	refundNo = { "이런 데가 다 있네!", "본사에 민원 넣을 거예요", "…알았어요. 기억할게요" },
	card = { "카드요. 빨리", "(카드를 던지듯 놓는다)" },
	cash = { "{money}. 잔돈 정확히 줘요", "여기 {money}. 세어 보세요" },
	bagAsk = { "당연히 봉투 줘야죠", "봉투 공짜 아니에요? 비싸네" },
	bagNo = { "됐어요" },
}

L.student = {
	enter = { "야 여기 들어가자", "편의점 ㄱㄱ", "오 시원해~", "야 너 뭐 먹을래?" },
	browse = { "야 이거 맛있대", "이거 2+1이다!", "돈 얼마 있어?", "나 이거 먹어 볼래" },
	order = { "저희 {order}요!", "{order} 주세요! 다 따로…아니 같이요", "{order}! 아 야 너 뭐였지?" },
	counter = { "이거요! 같이 계산할게요", "이거 다 계산이요~", "저희 학생 할인 돼요?" },
	wait = { "(친구랑 수다)", "ㅋㅋㅋㅋ", "야 그거 봤냐" },
	nag = { "아 학원 늦겠다", "저희 거 아직이에요?", "야 우리 늦겠다" },
	leave = { "야 그냥 가자", "학원 늦어서요… 죄송해요", "아 시간 없다, 가자" },
	thanks = { "감사합니다!!", "와 맛있겠다! 감사해요~", "감사합니당~" },
	ok = { "감사합니다~", "네!" },
	complain = { "어… 이거 맞나?", "야 이거 아닌 거 같은데" },
	angry = { "헐… 이게 뭐야", "완전 다르잖아…" },
	card = { "체크카드요!", "엄카… 아니 제 카드요" },
	cash = { "{money}요! 거스름돈 주세요", "용돈 털었다… {money}요" },
	idShow = { "아… 민증 두고 왔는데…", "(학생증을 내민다)", "아 저 성인이에요…! 진짜로요" },
	refused = { "아 네… 죄송해요", "ㅠㅠ 알겠어요", "야 안 된대, 가자" },
	bagAsk = { "네 봉투 주세요!", "봉투 하나요~" },
	bagNo = { "그냥 들고 갈게요!", "괜찮아요~" },
}

L.regular = {
	enter = { "안녕하세요~ 오늘도 왔어요", "수고 많으세요!", "오늘 바쁘죠?" },
	browse = { "늘 먹던 걸로…", "오늘은 뭐 새로 나왔나" },
	order = { "늘 먹던 {order}요!", "{order} 부탁해요~", "오늘은 {order}로 할게요" },
	counter = { "이거 계산 부탁해요~", "천천히 하셔도 돼요" },
	wait = { "(여유롭게 기다리는 중)", "천천히 하세요~" },
	nag = { "바쁘시죠? 천천히 하세요", "괜찮아요, 기다릴게요" },
	leave = { "오늘은 바쁘신가 보네… 다음에 올게요", "아이고 시간이… 이따 다시 올게요" },
	thanks = { "역시 잘하시네요! 이거 팁이에요", "오늘도 고마워요~ 수고하세요!", "여기가 제일 맛있어요!" },
	ok = { "고마워요~", "수고하세요!" },
	complain = { "오늘은 좀 다르네요? 괜찮아요", "음, 다음엔 부탁해요~" },
	angry = { "에이… 오늘은 좀 실망이네요" },
	tip = { "이거 얼마 안 되지만 받아요 😊", "음료수 값이에요, 수고해요!", "팁이에요~ 힘내세요!" },
	card = { "카드로 할게요~", "포인트 적립도 해 주세요" },
	cash = { "현금 {money} 드릴게요~", "여기 {money}요" },
	bagNo = { "에코백 있어요~", "봉투는 괜찮아요" },
	bagAsk = { "봉투 하나 부탁해요~" },
}

-- delivery recipients
L.recipient = {
	greet = { "아 배달이요? 감사합니다!", "오 빨리 왔네요!", "고생 많으세요~" },
	late = { "좀 늦었네요…", "많이 기다렸어요", "음식 식었겠다…" },
	bad = { "어? 국물이 다 샜잖아요", "포장이 다 엉망이네요…", "이거 흔들렸나 봐요" },
	thanks = { "감사합니다, 안전 운전하세요!", "잘 먹을게요~", "비 오는데 고생하셨어요" },
	absent = { "(부재중 · 문 앞에 두고 가 주세요)", "(전화 연결음…)", "죄송해요, 지금 밖이라 문 앞에 둬 주세요!" },
	rain = { "비 오는데 고생 많으셨어요!", "우산도 없이… 감사해요" },
}


CS.PERSONAS = {
	normal = { label = "손님", icon = "🙂", w = 40, wNight = 30, patience = 1, walk = 5.4, nagAt = { 0.6 }, hint = { style = "casual" } },
	hurry = { label = "급한 손님", icon = "⏱️", w = 14, wNight = 8, patience = 0.6, walk = 7.4, nagAt = { 0.3, 0.55, 0.8 }, hint = { style = "office" } },
	drunk = { label = "취객", icon = "🍺", w = 3, wNight = 18, patience = 1.3, walk = 3.6, nagAt = { 0.5 }, wander = 0.35, hint = { style = "office" } },
	karen = { label = "진상 손님", icon = "😤", w = 8, wNight = 8, patience = 0.8, walk = 5.6, nagAt = { 0.35, 0.65 }, strict = true, hint = { style = "trendy" } },
	student = { label = "학생", icon = "🎒", w = 12, wNight = 3, patience = 1, walk = 6, nagAt = { 0.7 }, group = { 2, 3 }, hint = { style = "school" } },
	regular = { label = "단골", icon = "⭐", w = 10, wNight = 6, patience = 1.6, walk = 5.2, nagAt = { 0.85 }, praise = true, named = true, hint = { style = "casual" } },
}
CS.PERSONA_ORDER = { "normal", "hurry", "drunk", "karen", "student", "regular" }

-- the job's reaction -> what the customer says / does (strict personas sour, praising ones warm up)
CS.REACT = {
	thanks = { line = "thanks", emote = "cheer_proc", mood = 1 },
	ok = { line = "ok", emote = "nod", mood = 0.5 },
	complain = { line = "complain", emote = "shake", mood = -0.5 },
	angry = { line = "angry", emote = "facepalm", mood = -1 },
	left = { line = "leave", emote = "shake", mood = -1 },
}

function CS.reaction(persona: string, reaction: string): string
	local p = CS.PERSONAS[persona]
	if p and p.strict and reaction == "complain" then
		return "angry"
	end
	if p and p.praise and reaction == "ok" then
		return "thanks"
	end
	return if CS.REACT[reaction] then reaction else "ok"
end

-- Sites (the stores the NPC customers visit). Local frame = the Destination part's CFrame (the job
-- module uses the same frame: WorkCafe.LAYOUT). door -> lobby -> queue from `order` back toward the door
-- (queueStep, along queueDir), `waits` near the pick-up counter, `pickup` where the cup is taken.
-- job = the job id whose shift (player attribute GwWorkShift) opens the store for customers.
CS.SITES = {
	starbucks = {
		label = "스타벅스 광안리점",
		dest = "스타벅스 광안리점",
		job = "starbucks",
		kind = "cafe",
		max = 4,
		gap = { 9, 18 }, -- seconds between arrivals (x0.6 in the rush)
		door = { 0, -4.2, 3 },
		lobby = { 1.5, -4.2, 15 },
		order = { 3.21, -4.2, 26.23 },
		queueDir = { 0, 0, -1 },
		queueStep = 2.6,
		waits = { { -26.5, -4.2, 23.2 }, { -29.0, -4.2, 22.4 }, { -23.8, -4.2, 22.0 }, { -31.4, -4.2, 23.6 } },
		pickup = { -30.76, -4.2, 27.76 },
	},
	-- GS25: the building places GwJobStation anchors (door_out / door_in / browse* / queue1..3 / counter).
	-- Served only when the 알바 session's Work module handles the job (ctx.work.handles("gs25")); the
	-- legacy job (JobWorld) keeps its own customers otherwise.
	gs25 = {
		label = "GS25 광안리점",
		dest = "GS25 광안리점",
		anchors = { "convenience", "GS25 광안리점", "JobStations" },
		job = "gs25",
		kind = "counter",
		max = 4,
		gap = { 8, 16 },
	},
}

local function fill(text: string, vars: any?): string
	if not vars then
		return text
	end
	return (string.gsub(text, "{(%w+)}", function(k)
		local v = vars[k]
		return if v ~= nil then tostring(v) else ""
	end))
end
CS.fill = fill

function CS.list(persona: string?, situation: string): { string }?
	local p = persona and L[persona]
	local l = p and p[situation]
	if type(l) ~= "table" or #l == 0 then
		l = L.normal[situation]
	end
	return if type(l) == "table" and #l > 0 then l else nil
end

-- never the same line twice in a row (per memo + persona + situation)
function CS.pick(memo: any, persona: string?, situation: string, rand: (number) -> number, vars: any?): string?
	local l = CS.list(persona, situation)
	if not l then
		return nil
	end
	local key = tostring(persona) .. "/" .. situation
	local last = memo and memo[key]
	local i = rand(#l)
	if #l > 1 and i == last then
		i = (i % #l) + 1
	end
	if memo then
		memo[key] = i
	end
	return fill(l[i], vars)
end

function CS.pickPersona(rand: () -> number, night: boolean): string
	local total = 0
	for _, id in CS.PERSONA_ORDER do
		local p = CS.PERSONAS[id]
		total += if night then p.wNight else p.w
	end
	local r = rand() * total
	for _, id in CS.PERSONA_ORDER do
		local p = CS.PERSONAS[id]
		r -= if night then p.wNight else p.w
		if r <= 0 then
			return id
		end
	end
	return "normal"
end

return CS
