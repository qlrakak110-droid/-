-- GwangalliGameplay/Mind/Talk (server; owner: npc_mind): the FREE CONVERSATION layer over the Mind
-- composer (GwangalliMindShared.respond). The player types anything; this turns it into a reply
-- that follows the conversation instead of one keyword -> one canned line.
--
--   * CLAUSES: a message is cut into up to 3 clauses ("안녕! 나 오늘 피곤해. 너는 뭐 해?"); each is
--     read on its own (intent, question?, topic, feeling, a fact about the player, a context word);
--     the reply answers the two that matter most, in order (a hello becomes a short opener).
--   * CONTEXT (per conversation, sess.talk.tc): the last topic, the NPC's last question (its answer
--     is read as an answer: "민수야" after "이름이 뭐예요?" is a name), the last NPC line ("뭐?" ->
--     said again, simpler), "너는?" (they answer their own side of the last thing), "왜?" (the
--     reason of what they just said), "진짜?", "ㅋㅋ", "나도!" (a bond).
--   * PLAYER FACTS (rec.pf, saved): name, job, age, home town, likes / dislikes, the last feeling and
--     what the player did; brought back later ("지난번에 피곤하다더니 좀 괜찮아요?"), the name is used
--     by friends.
--   * PERSONALITY: topics the person loves (roster c.topics) light them up, hated ones (c.hate)
--     annoy them and end in refusal when pushed; warmth, humour, pride, temper pick the kind of
--     answer; voice + Busan dialect come from the shared composer (Mind.voice / Mind.dialect).
--   * SPEECH: 존댓말 / 반말 by closeness (Mind.register); "말 놓을까?" -> rec.bm when they are close
--     enough (they may offer it themselves).
--   * PLACE / SITUATION: a clerk at work talks orders, payment, bags and the menu of their shop; off
--     duty they say so; a street person talks the time, the weather, the night, recent incidents
--     (live news), a wanted player.
--   * NOT LIKED: the same sentence again and again, swearing, a hated topic, talking to someone who
--     is angry / scared (curt answers, they leave or flee).
--   * Hostile and relationship intents (insult / 시비 / threats / confess / number / invite /
--     apologies...) stay with the shared composer, so 호감도, 신고, 반격, 번호, 약속 work as before;
--     an invite that names a place ("노래방 갈래?") becomes that appointment (out.invite).
--
-- Talk.say(c, rec, text, env, tc, rule) -> out | nil
--   rule(req) -> out runs the shared composer for one rule intent (the server's sayCommon pieces).
--   out has the shared composer's shape; extra: out.invite = Social.INVITES kind.
-- Talk.opener(c, rec, env, kind) -> out | nil  (an NPC that walks up to the player: recall / topic)
-- Pure Luau (no instances): the unit test runs it with the shared modules.

local Talk = {}

local M: any = nil
local Citizens: any = nil

function Talk.init(deps: any)
	M = deps.M
	Citizens = deps.Citizens
end

-------------------------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------------------------
local function has(s: string, w: string): boolean
	return string.find(s, w, 1, true) ~= nil
end

local function anyOf(s: string, list: { string }): string?
	for _, w in list do
		if string.find(s, w, 1, true) then
			return w
		end
	end
	return nil
end

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- "polite|casual" strings -> { p = {...}, c = {...} }
local function PC(list: { string }): any
	local out = { p = {}, c = {} }
	for _, s in list do
		local a, b = string.match(s, "^(.-)|(.*)$")
		table.insert(out.p, a or s)
		table.insert(out.c, b or s)
	end
	return out
end

local function chance(r: () -> number, p: number): boolean
	return r() < p
end

local function D(): any
	return { aff = 0, tr = 0, an = 0, fe = 0, cl = 0 }
end

local function addD(d: any, k: string, v: number)
	d[k] = (d[k] or 0) + v
end

local function utf8len(s: string): number
	return utf8.len(s) or #s
end

-- strip a trailing particle / copula from one word: "민수야" -> "민수", "김민수입니다" -> "김민수"
local NAME_TAILS = { "입니다", "이에요", "예요", "이야", "이요", "라고", "이라고", "야", "요", "씨", "님", "이" }
local function bareWord(w: string): string
	local s = trim(w)
	s = string.gsub(s, "[%p%s~]+$", "")
	for _ = 1, 2 do
		for _, t in NAME_TAILS do
			if #s > #t + 3 and string.sub(s, -#t) == t then
				s = string.sub(s, 1, #s - #t)
				break
			end
		end
	end
	return s
end

-- strip one trailing particle (whole syllables: a Lua class like "[을를]" works on bytes, not Hangul)
local JOSA_1 = { "에서", "한테", "이랑", "은", "는", "이", "가", "을", "를", "에", "도", "만", "랑", "와", "과" }
local function stripJosa(w: string, list: { string }?): string
	for _, j in list or JOSA_1 do
		if #w > #j + 3 and string.sub(w, -#j) == j then
			return string.sub(w, 1, #w - #j)
		end
	end
	return w
end

-- "민준" -> "민준이", "민수" -> "민수" (before 구나 / 면 / 잖아)
local function withI(w: string?): string?
	if not w then
		return nil
	end
	return if M and M.hasBatchim and M.hasBatchim(w) then w .. "이" else w
end

local function validName(s: string): boolean
	local n = utf8len(s)
	if n < 1 or n > 8 or has(s, " ") then
		return false
	end
	for _, bad in { "비밀", "몰라", "안 알려", "싫", "글쎄", "왜", "뭐", "누구" } do
		if has(s, bad) then
			return false
		end
	end
	return true
end

-------------------------------------------------------------------------------------------------
-- word lists
-------------------------------------------------------------------------------------------------
local SELF = { "나는", "난 ", "나 ", "내가", "내 ", "저는", "전 ", "저 ", "제가", "제 ", "나도", "저도" }
local YOU = { "너는", "넌 ", "너 ", "니가", "너도", "당신", "그쪽", "님은", "님도", "님 ", "자기", "너가" }
local WH = {
	where = { "어디", "어딨", "어딘" },
	when = { "언제", "몇 시" },
	why = { "왜", "어째서" },
	how = { "어떻게", "어때", "어땠" },
	who = { "누구", "누가" },
	what = { "뭐", "무슨", "무엇", "뭔" },
	much = { "얼마", "몇 개", "몇개" },
}
local Q_ENDS = { "니$", "냐$", "나요$", "까$", "까요$", "래$", "래요$", "어때$", "어때요$", "죠$", "지%?$", "있어요$", "없어요$" }

local POS = { "좋", "최고", "대박", "짱", "맛있", "재밌", "재미있", "예쁘", "멋있", "행복", "신나", "사랑", "당연", "그럼", "물론", "맞아", "가 봤", "가봤" }
local NEG = { "싫", "별로", "노잼", "맛없", "최악", "그닥", "글쎄", "ㄴㄴ", "아니", "안 좋", "좋지 않", "재미없", "못 가", "안 가", "안 해" }

local FEEL = {
	tired = { "피곤", "졸려", "졸리", "지쳤", "지친", "녹초", "잠 못", "잠을 못" },
	sad = { "슬퍼", "슬프", "우울", "울고 싶", "눈물", "속상", "서러" },
	lonely = { "외로", "혼자야", "혼자예요", "친구가 없" },
	happy = { "기분 좋", "기분좋", "행복", "신나", "신난", "좋은 일", "기뻐", "기쁘", "설레" },
	hungry = { "배고", "배 고", "출출", "굶었" },
	full = { "배불", "배 불", "많이 먹었" },
	bored = { "심심", "지루", "할 게 없", "할 거 없" },
	sick = { "아파", "아프", "감기", "열 나", "머리가 아", "배가 아" },
	stressed = { "스트레스", "짜증 나", "짜증나", "열받", "빡쳐", "빡치", "화나", "답답" },
	hot = { "더워", "덥다", "더워요", "덥네" },
	cold = { "추워", "춥다", "추워요", "춥네" },
}
local FEEL_ORDER = { "sad", "lonely", "sick", "stressed", "tired", "hungry", "full", "bored", "happy", "hot", "cold" }
local FEEL_LABEL = { tired = "피곤하다", sad = "속상하다", lonely = "외롭다", happy = "기분 좋다", hungry = "배고프다", full = "배부르다", bored = "심심하다", sick = "아프다", stressed = "스트레스 받는다", hot = "덥다", cold = "춥다" }

local JOBS = {
	{ "고등학생", "고딩", "고삐리" }, { "대학생", "대딩", "새내기", "휴학생" }, { "학생" }, { "직장인", "회사원", "회사 다녀", "회사다녀" },
	{ "알바", "아르바이트" }, { "백수", "취준", "취업 준비", "쉬는 중" }, { "개발자", "프로그래머" }, { "요리사", "셰프" },
	{ "배달", "라이더" }, { "사장", "자영업" }, { "유튜버", "스트리머", "인플루언서" }, { "경찰" }, { "군인", "군대" }, { "선생님", "교사" },
	{ "디자이너" }, { "간호사" }, { "운동선수", "선수" }, { "가수", "연습생" },
}

local SWEAR = { "씨발", "시발", "ㅅㅂ", "존나", "졸라", "ㅈㄴ", "개같", "젠장", "제기랄", "니미" }
local DIRECT_INSULT = { "꺼져", "닥쳐", "병신", "븅신", "개새", "새끼", "등신", "찐따", "쓰레기", "또라이", "못생" }

local BANMAL_ASK = { "말 놓", "말놓", "말 편하게", "편하게 말", "반말해도", "반말 해도", "말 까도", "말 트", "반말 할까", "반말할까" }
local POLITE_ASK = { "존댓말 해", "존댓말로", "반말하지 마", "반말 하지 마" }

local CTX = {
	you_too = { "너는?", "넌?", "너는", "넌", "당신은?", "그쪽은?", "님은?", "너도?", "님도?", "저는요?", "언니는?", "형은?", "오빠는?", "누나는?" },
	why = { "왜?", "왜요?", "왜", "왜요", "어째서?", "왜 그래?", "왜 그래요?" },
	really = { "진짜?", "정말?", "진짜요?", "정말요?", "레알?", "실화?", "헐", "대박", "와 진짜", "에이", "설마" },
	what = { "뭐?", "네?", "응?", "무슨 말", "무슨 소리", "뭐라고", "잘 못 들", "다시 말해" },
	ok = { "아하", "그렇구나", "그렇군요", "알겠어", "알겠어요", "ㅇㅋ", "오케이", "그래", "그래요", "아 그래?", "아 그래요?", "아 네", "응응" },
	me_too = { "나도", "저도", "나두", "저두" },
}

-------------------------------------------------------------------------------------------------
-- topics (the roster's c.topics / c.hate keys first, then extra street topics)
-------------------------------------------------------------------------------------------------
local TOPICS: { [string]: any } = {
	food = {
		label = "음식",
		kw = { "맛집", "음식", "먹을", "먹었", "밥", "요리", "맛있는 거", "국밥", "치킨", "회", "떡볶이", "라면" },
		ops = PC({ "광안리 왔으면 회는 꼭 먹어야죠.|광안리 왔으면 회는 꼭 먹어야지.", "요즘은 먹자골목 떡볶이에 꽂혔어요.|요즘은 먹자골목 떡볶이에 꽂혔어.", "비 오는 날엔 국밥이 최고예요.|비 오는 날엔 국밥이 최고야.", "먹는 게 남는 거예요 진짜.|먹는 게 남는 거야 진짜." }),
		ask = PC({ "뭐 좋아하는 음식 있어요?|너는 뭐 좋아해?", "오늘 뭐 먹었어요?|오늘 뭐 먹었어?" }),
		why = PC({ "맛있는 거 먹으면 기분이 확 풀리잖아요.|맛있는 거 먹으면 기분이 확 풀리잖아." }),
		where = PC({ "먹자골목 쪽 가 보세요. 거기 웬만하면 다 맛있어요.|먹자골목 가 봐. 웬만하면 다 맛있어.", "회는 민락회타운이죠!|회는 민락회타운이지!" }),
	},
	sea = {
		label = "바다",
		kw = { "바다", "해변", "파도", "수영", "서핑", "모래", "바닷", "해수욕" },
		ops = PC({ "광안리 바다는 볼 때마다 색이 달라요.|광안리 바다는 볼 때마다 색이 달라.", "파도 소리 듣고 있으면 생각이 정리돼요.|파도 소리 들으면 생각이 정리돼.", "여름엔 사람이 너무 많아서 아침에 오는 게 좋아요.|여름엔 사람 너무 많아서 아침이 좋아." }),
		ask = PC({ "바다 들어가 봤어요?|바다 들어가 봤어?", "서핑 해 본 적 있어요?|서핑 해 봤어?" }),
		why = PC({ "바다 보고 있으면 걱정이 작아지거든요.|바다 보고 있으면 걱정이 작아지거든." }),
		where = PC({ "SUP존 쪽이 물이 잔잔해요.|SUP존 쪽이 물 잔잔해.", "해변 중앙이 제일 예뻐요.|해변 중앙이 제일 예뻐." }),
	},
	music = {
		label = "음악",
		kw = { "노래", "음악", "가수", "버스킹", "아이돌", "힙합", "발라드", "케이팝", "kpop", "플레이리스트" },
		ops = PC({ "요즘 버스킹하는 분들 실력 장난 아니에요.|요즘 버스킹 실력 장난 아니야.", "밤바다엔 잔잔한 노래가 딱이에요.|밤바다엔 잔잔한 노래가 딱이야.", "코노 가면 저 목 쉴 때까지 불러요 ㅋㅋ|코노 가면 목 쉴 때까지 불러 ㅋㅋ" }),
		ask = PC({ "무슨 노래 좋아해요?|무슨 노래 좋아해?", "최애 가수 있어요?|최애 가수 있어?" }),
		why = PC({ "노래 들으면 하루가 덜 지루하잖아요.|노래 들으면 하루가 덜 지루하잖아." }),
		where = PC({ "광안 코인노래방 가 봐요. 가성비 최고예요.|광안 코노 가 봐. 가성비 최고야." }),
	},
	club = {
		label = "클럽",
		kw = { "클럽", "춤", "파티", "디제이", "dj", "오션" },
		ops = PC({ "클럽 오션은 열한 시 넘어야 사람 차요.|클럽 오션은 열한 시 넘어야 사람 차.", "춤은 못 춰도 분위기는 좋아해요.|춤은 못 춰도 분위기는 좋아해." }),
		ask = PC({ "클럽 자주 가요?|클럽 자주 가?" }),
		why = PC({ "음악 크게 틀어 놓으면 아무 생각 안 나거든요.|음악 크게 틀면 아무 생각 안 나거든." }),
		where = PC({ "클럽 오션이요, 먹자골목 쪽에 있어요.|클럽 오션, 먹자골목 쪽에 있어." }),
	},
	work = {
		label = "일",
		kw = { "회사", "출근", "퇴근", "야근", "직장", "상사", "월요일", "일하", "일 해", "일해" },
		ops = PC({ "일은… 다 그렇죠 뭐. 월급날만 기다려요.|일은 다 그렇지 뭐. 월급날만 기다려.", "퇴근하고 바다 보는 게 유일한 낙이에요.|퇴근하고 바다 보는 게 낙이야.", "오늘도 무사히 버텼어요 ㅎㅎ|오늘도 무사히 버텼다 ㅋㅋ" }),
		ask = PC({ "일은 할 만해요?|일은 할 만해?" }),
		why = PC({ "먹고살아야 하니까요 ㅎㅎ|먹고살아야 하니까 ㅋㅋ" }),
	},
	study = {
		label = "공부",
		kw = { "공부", "시험", "학교", "학원", "숙제", "과제", "수능", "대학", "성적" },
		ops = PC({ "시험 기간엔 카페가 꽉 차요.|시험 기간엔 카페 꽉 차.", "공부는 하기 싫은데 안 할 수도 없고요 ㅠ|공부 하기 싫은데 안 할 수도 없고 ㅠ" }),
		ask = PC({ "학생이에요?|너 학생이야?", "시험 끝났어요?|시험 끝났어?" }),
		why = PC({ "나중에 후회하기 싫어서요.|나중에 후회하기 싫어서." }),
		where = PC({ "홍미당 카페가 공부하기 좋아요.|홍미당이 공부하기 좋아." }),
	},
	fashion = {
		label = "패션",
		kw = { "옷", "패션", "스타일", "신발", "코디", "머리", "헤어", "가방" },
		ops = PC({ "요즘은 편한 옷이 최고더라고요.|요즘은 편한 옷이 최고더라.", "광안리는 바람 때문에 머리가 맨날 엉망이에요 ㅋㅋ|여긴 바람 때문에 머리 맨날 엉망이야 ㅋㅋ" }),
		ask = PC({ "옷 어디서 사요? 센스 있으시네.|옷 어디서 사? 센스 있네." }),
		why = PC({ "입는 거에 따라 기분이 달라지잖아요.|입는 거에 따라 기분 달라지잖아." }),
		where = PC({ "지웰 쪽 편집숍 괜찮아요.|지웰 쪽 편집숍 괜찮아." }),
	},
	games = {
		label = "게임",
		kw = { "게임", "롤", "피시방", "pc방", "랭크", "오락실", "닌텐도", "배그", "발로" },
		ops = PC({ "어제 랭크 연패해서 접을 뻔했어요 ㅋㅋ|어제 랭크 연패해서 접을 뻔했어 ㅋㅋ", "광안 PC방 의자가 진짜 편해요.|광안 PC방 의자 진짜 편해.", "오락실 펀치 기계 기록 제가 갖고 있어요 ㅎㅎ|오락실 펀치 기록 내 거야 ㅋㅋ" }),
		ask = PC({ "게임 뭐 해요?|너 게임 뭐 해?" }),
		why = PC({ "이기면 기분 좋잖아요 ㅋㅋ|이기면 기분 좋잖아 ㅋㅋ" }),
		where = PC({ "광안 PC방이나 게임랜드요!|광안 PC방이나 게임랜드!" }),
	},
	travel = {
		label = "여행",
		kw = { "여행", "관광", "서울", "제주", "해외", "비행기", "일본", "놀러 왔", "놀러왔" },
		ops = PC({ "부산 사람도 광안리는 질리지가 않아요.|부산 살아도 광안리는 안 질려.", "다음엔 제주도 가 보고 싶어요.|다음엔 제주 가고 싶다." }),
		ask = PC({ "어디서 오셨어요?|어디서 왔어?", "여행 중이에요?|여행 왔어?" }),
		why = PC({ "새로운 데 가면 내가 새로워지는 느낌이라서요.|새로운 데 가면 내가 새로워지는 느낌이라." }),
		where = PC({ "관광안내소 가면 지도 줘요.|관광안내소 가면 지도 줘." }),
	},
	fitness = {
		label = "운동",
		kw = { "운동", "헬스", "다이어트", "러닝", "조깅", "근육", "필라테스", "요가", "pt" },
		ops = PC({ "해변 따라 아침에 뛰면 진짜 상쾌해요.|해변 따라 아침에 뛰면 진짜 상쾌해.", "다이어트는 내일부터예요 ㅋㅋ|다이어트는 내일부터 ㅋㅋ" }),
		ask = PC({ "운동 해요?|운동 해?" }),
		why = PC({ "땀 흘리면 머리가 맑아져요.|땀 흘리면 머리가 맑아져." }),
		where = PC({ "광안 휘트니스 24 좋아요. 이십사 시간이에요.|광안 휘트니스 24, 이십사 시간이야." }),
	},
	baseball = {
		label = "야구",
		kw = { "야구", "롯데", "자이언츠", "사직", "홈런", "직관" },
		ops = PC({ "롯데는… 올해는 다를 거예요. 매년 그 소리지만요.|롯데는 올해는 다를 거야. 매년 그 소리지만.", "사직 직관 가면 목이 다 쉬어요.|사직 직관 가면 목 다 쉰다." }),
		ask = PC({ "야구 좋아해요? 어디 팬이에요?|야구 좋아해? 어디 팬이야?" }),
		why = PC({ "부산 사람이면 롯데죠.|부산 사람이면 롯데지." }),
	},
	family = {
		label = "가족",
		kw = { "가족", "엄마", "아빠", "부모님", "동생", "형", "언니", "누나", "오빠", "할머니", "할아버지", "자식", "애들" },
		ops = PC({ "가족이 제일 힘이 되죠.|가족이 제일 힘이 되지.", "요즘 엄마한테 전화를 잘 못 했네요.|요즘 엄마한테 전화 못 했네." }),
		ask = PC({ "가족이랑 같이 살아요?|가족이랑 같이 살아?" }),
		why = PC({ "결국 끝까지 내 편이잖아요.|결국 끝까지 내 편이잖아." }),
	},
	art = {
		label = "그림",
		kw = { "그림", "전시", "미술", "작품", "갤러리" },
		ops = PC({ "해변에서 그림 그리는 분 있던데 진짜 잘 그리더라고요.|해변에서 그림 그리는 사람 진짜 잘 그리더라." }),
		ask = PC({ "그림 그리는 거 좋아해요?|그림 좋아해?" }),
		why = PC({ "말로 못 하는 걸 보여 주니까요.|말로 못 하는 걸 보여 주니까." }),
	},
	coffee = {
		label = "커피",
		kw = { "커피", "카페", "라떼", "아메리카노", "아아", "에스프레소", "디저트", "빵" },
		ops = PC({ "아아 없으면 하루가 시작이 안 돼요.|아아 없으면 하루 시작이 안 돼.", "홍미당 소금빵 먹어 봤어요? 진짜 맛있어요.|홍미당 소금빵 먹어 봤어? 진짜 맛있어." }),
		ask = PC({ "커피 좋아해요?|커피 좋아해?" }),
		why = PC({ "카페인 없인 못 살아요 ㅎㅎ|카페인 없인 못 살아 ㅋㅋ" }),
		where = PC({ "바다 보이는 데는 스타벅스 광안리점이요.|바다 보이는 데는 스타벅스 광안리점." }),
	},
	money = {
		label = "돈",
		kw = { "돈", "월급", "부자", "용돈", "주식", "코인", "로또", "적금", "통장" },
		ops = PC({ "돈은 버는 것보다 안 쓰는 게 어려워요.|돈은 안 쓰는 게 더 어려워.", "로또 되면 광안리 뷰 아파트 살 거예요 ㅋㅋ|로또 되면 광안리 뷰 아파트 산다 ㅋㅋ" }),
		ask = PC({ "요즘 돈 모으고 있어요?|요즘 돈 모아?" }),
		why = PC({ "돈이 다는 아니지만 없으면 불편하잖아요.|돈이 다는 아니어도 없으면 불편하잖아." }),
		where = PC({ "은행은 광안동 BNK 쪽에 있어요.|은행은 광안동 BNK 쪽." }),
	},
	photo = {
		label = "사진",
		kw = { "사진", "셀카", "인스타", "릴스", "찍어", "카메라" },
		ops = PC({ "노을 질 때 대교 배경으로 찍으면 인생샷 나와요.|노을 질 때 대교 배경이면 인생샷이야.", "인스타에 올릴 사진만 백 장 찍었어요 ㅋㅋ|인스타용으로 백 장 찍었어 ㅋㅋ" }),
		ask = PC({ "사진 찍는 거 좋아해요?|사진 좋아해?" }),
		why = PC({ "지나가면 다시 안 오는 순간이잖아요.|지나가면 다시 안 오는 순간이잖아." }),
		where = PC({ "테라스타오션 쪽이 사진 잘 나와요.|테라스타오션 쪽이 사진 잘 나와." }),
	},
	-- street topics (nobody's roster topic: the archetype decides)
	bridge = {
		label = "광안대교",
		kw = { "광안대교", "대교", "다리", "야경", "불꽃", "드론쇼", "드론 쇼" },
		ops = PC({ "밤에 대교 불 들어오면 진짜 예뻐요.|밤에 대교 불 들어오면 진짜 예뻐.", "불꽃축제 날엔 여기 발 디딜 틈도 없어요.|불꽃축제 날엔 발 디딜 틈도 없어.", "주말 드론쇼 봤어요? 소름 돋아요.|주말 드론쇼 봤어? 소름 돋아." }),
		ask = PC({ "대교 야경 봤어요?|대교 야경 봤어?" }),
		why = PC({ "그거 보려고 다들 광안리 오는 거잖아요.|그거 보려고 다들 오는 거잖아." }),
		where = PC({ "해변 중앙에서 보면 대교가 한눈에 보여요.|해변 중앙에서 보면 한눈에 보여." }),
	},
	police = {
		label = "경찰",
		kw = { "경찰", "순찰", "지구대", "신고", "사건", "도둑", "범죄" },
		ops = PC({ "요즘 순찰차가 자주 다니더라고요.|요즘 순찰차 자주 다니더라.", "밤에 먹자골목은 좀 조심해야 돼요.|밤에 먹자골목은 좀 조심해." }),
		ask = PC({ "무슨 일 있었어요?|무슨 일 있었어?" }),
		why = PC({ "사람 많은 데는 사건도 많거든요.|사람 많은 데는 사건도 많거든." }),
		where = PC({ "광안지구대는 광안역 쪽에 있어요.|지구대는 광안역 쪽이야." }),
	},
	car = {
		label = "차",
		kw = { "자동차", "운전", "택시", "버스", "주차", "오토바이", "드라이브", "차 막", "면허" },
		ops = PC({ "광안리는 주말에 차 끌고 오면 고생해요.|주말에 차 끌고 오면 고생해.", "해안도로 드라이브는 밤이 최고예요.|해안도로 드라이브는 밤이 최고야." }),
		ask = PC({ "차 있어요?|차 있어?" }),
		why = PC({ "주차할 데가 없거든요 ㅠ|주차할 데가 없거든 ㅠ" }),
		where = PC({ "공영주차장은 광안동 쪽에 있어요.|공영주차장은 광안동 쪽." }),
	},
	love = {
		label = "연애",
		kw = { "연애", "썸", "소개팅", "짝사랑", "헤어졌", "차였", "커플" },
		ops = PC({ "연애는… 타이밍이더라고요.|연애는 타이밍이더라.", "광안리엔 커플이 너무 많아요 ㅋㅋ|광안리엔 커플 너무 많아 ㅋㅋ" }),
		ask = PC({ "요즘 썸 타는 사람 있어요? ㅎㅎ|요즘 썸 있어? ㅋㅋ" }),
		why = PC({ "마음대로 안 되는 게 사람 마음이잖아요.|마음대로 안 되는 게 사람 마음이잖아." }),
	},
	pet = {
		label = "반려동물",
		kw = { "강아지", "고양이", "댕댕", "냥이", "반려", "멍멍", "애완" },
		ops = PC({ "해변 산책 나온 강아지들 보면 너무 귀여워요.|해변 산책하는 강아지들 너무 귀여워.", "저 고양이 키우고 싶은데 집이 좁아요 ㅠ|고양이 키우고 싶은데 집이 좁아 ㅠ" }),
		ask = PC({ "반려동물 키워요?|너 반려동물 키워?" }),
		why = PC({ "그냥 존재 자체가 힐링이잖아요.|존재 자체가 힐링이잖아." }),
	},
	drink = {
		label = "술",
		kw = { "술", "소주", "맥주", "한잔", "치맥", "취했", "포차", "막걸리", "해장" },
		ops = PC({ "바다 보면서 마시는 맥주가 최고죠.|바다 보면서 마시는 맥주가 최고지.", "어제 마셔서 오늘은 해장국 먹어야 돼요.|어제 마셔서 오늘은 해장해야 돼." }),
		ask = PC({ "술 잘 마셔요?|술 잘 마셔?" }),
		why = PC({ "하루 끝에 한잔은 보약이잖아요 ㅎㅎ|하루 끝에 한잔은 보약이지 ㅋㅋ" }),
		where = PC({ "민락회타운 쪽 포차가 분위기 좋아요.|민락 포차 분위기 좋아." }),
	},
	movie = {
		label = "영화",
		kw = { "영화", "드라마", "넷플", "예능", "웹툰", "애니" },
		ops = PC({ "요즘 드라마 하나 정주행 중이에요.|요즘 드라마 정주행 중이야.", "부산은 영화제도 있잖아요.|부산은 영화제도 있잖아." }),
		ask = PC({ "요즘 뭐 봐요?|요즘 뭐 봐?" }),
		why = PC({ "남의 인생 구경하는 게 재밌거든요.|남 인생 구경하는 게 재밌거든." }),
	},
	busan = {
		label = "부산",
		kw = { "부산", "사투리", "광안리", "해운대", "서면", "남포동", "부산 사람" },
		ops = PC({ "광안리는 해운대보다 덜 붐비고 뷰는 더 좋아요.|광안리는 해운대보다 덜 붐비고 뷰는 더 좋아.", "부산 사람들 무뚝뚝해 보여도 정 많아요.|부산 사람 무뚝뚝해 보여도 정 많아." }),
		ask = PC({ "부산 사람이에요?|너 부산 사람이야?" }),
		why = PC({ "바다가 가까우니까 마음이 넓어지는 거죠 ㅎㅎ|바다가 가까우니까 마음이 넓어지지 ㅋㅋ" }),
	},
	sleep = {
		label = "잠",
		kw = { "잠", "자야", "꿀잠", "늦잠", "밤샜", "밤새", "새벽" },
		ops = PC({ "잠이 보약이에요 진짜.|잠이 보약이야 진짜.", "어제 새벽까지 깨 있어서 지금 눈이 감겨요.|어제 새벽까지 깨 있어서 눈이 감겨." }),
		ask = PC({ "잠은 잘 자요?|잠은 잘 자?" }),
		why = PC({ "못 자면 하루 종일 멍하거든요.|못 자면 하루 종일 멍하거든." }),
	},
}
local TOPIC_ORDER = { "bridge", "police", "drink", "love", "pet", "movie", "car", "sleep", "busan", "baseball", "games", "club", "music", "photo", "coffee", "fitness", "fashion", "travel", "study", "work", "family", "art", "money", "sea", "food" }
-- archetypes that care about a street topic either way
local ARCH_TOPIC = {
	drunk = { love = { drink = true }, hate = { police = true } },
	police = { love = { police = true }, hate = { drink = false } },
	student = { love = { games = true, music = true }, hate = { study = true } },
	office = { love = { drink = true }, hate = { work = true } },
	elder = { love = { family = true }, hate = { club = true, games = true } },
	homeless = { love = { food = true }, hate = { money = false } },
	rich = { love = { travel = true, car = true }, hate = { money = false } },
	tourist = { love = { bridge = true, travel = true, busan = true } },
	punk = { love = { car = true, club = true }, hate = { police = true, study = true } },
	thug = { hate = { police = true } },
	fool = { love = { pet = true, sea = true } },
	clerk = { love = { coffee = true } },
	parttimer = { hate = { work = true } },
}

local function stanceOf(c: any, arch: string, topic: string): string
	if type(c.hate) == "table" and table.find(c.hate, topic) then
		return "hate"
	end
	if type(c.topics) == "table" and table.find(c.topics, topic) then
		return "love"
	end
	local A = ARCH_TOPIC[arch]
	if A then
		if A.hate and A.hate[topic] then
			return "hate"
		end
		if A.love and A.love[topic] then
			return "love"
		end
	end
	return "neutral"
end

local STANCE = {
	love = PC({ "오 {label} 얘기요? 저 그거 진짜 좋아해요!|오 {label} 얘기? 나 그거 진짜 좋아해!", "{label}요? 말 잘 꺼냈다, 저 그 얘기 하면 밤새요 ㅎㅎ|{label}? 그 얘기 하면 나 밤새 ㅋㅋ", "헉 {label} 좋아하세요? 반갑다!|헉 너도 {label} 좋아해? 반갑다!" }),
	hate = PC({ "아… {label} 얘기는 좀 별로예요.|아… {label} 얘기는 좀 별로야.", "음, {label}은 제가 별로 안 좋아해서요.|음, {label}은 내가 별로라.", "{label} 얘기요? 딴 얘기 해요 우리.|{label}? 딴 얘기 하자." }),
	love_yes = PC({ "완전 좋아하죠! {label} 얘기면 하루 종일 할 수 있어요.|완전 좋아하지! {label} 얘기면 하루 종일 할 수 있어.", "좋아하는 정도가 아니에요 ㅎㅎ|좋아하는 정도가 아니야 ㅋㅋ" }),
	meh = PC({ "음… 싫진 않은데 엄청 좋아하는 것도 아니에요.|음… 싫진 않은데 엄청 좋아하진 않아.", "그냥 그래요 ㅎㅎ 가끔?|그냥 그래 ㅋㅋ 가끔?" }),
	hate_again = PC({ "그 얘기 별로라고 했잖아요.|그 얘기 별로라고 했잖아.", "또 {label} 얘기예요? 그만해요 진짜.|또 {label} 얘기야? 그만해 진짜." }),
}

-------------------------------------------------------------------------------------------------
-- reply banks of this layer
-------------------------------------------------------------------------------------------------
local B = {
	feel = {
		tired = { warm = PC({ "많이 피곤해요? 오늘은 일찍 들어가서 푹 쉬어요.|많이 피곤해? 오늘은 일찍 들어가서 푹 쉬어.", "에고, 얼굴에 피곤하다고 쓰여 있어요. 커피라도 한 잔 해요.|얼굴에 피곤하다고 쓰여 있다. 커피라도 마셔." }), cool = PC({ "피곤할 땐 그냥 자는 게 답이에요.|피곤하면 그냥 자.", "저도요. 다들 피곤하죠 뭐.|나도. 다 피곤하지 뭐." }) },
		sad = { warm = PC({ "무슨 일 있었어요? 얘기하고 싶으면 들어 줄게요.|무슨 일 있었어? 얘기하고 싶으면 들어 줄게.", "에이… 속상했겠다. 바다라도 보면서 좀 쉬어요.|에이… 속상했겠다. 바다 보면서 좀 쉬어." }), cool = PC({ "그런 날도 있죠. 지나가요.|그런 날도 있지. 지나가.", "음… 힘내요.|음… 힘내." }) },
		lonely = { warm = PC({ "외로울 땐 사람 많은 데 나와 있는 것도 방법이에요. 지금처럼요 ㅎㅎ|외로우면 이렇게 나와 있어. 나도 있잖아 ㅎㅎ" }), cool = PC({ "광안리에 사람 이렇게 많은데요?|광안리에 사람 이렇게 많은데?" }) },
		happy = { warm = PC({ "오 좋은 일 있었어요? 저까지 기분 좋아지네요!|오 좋은 일 있었어? 나까지 기분 좋다!", "얼굴이 밝아 보이더라니! 무슨 일인데요?|어쩐지 얼굴 밝더라! 무슨 일인데?" }), cool = PC({ "좋겠네요 ㅎㅎ|좋겠다 ㅋㅋ" }) },
		hungry = { warm = PC({ "배고프면 {food} 어때요? 저 그거 진짜 좋아하는데.|배고프면 {food} 어때? 나 그거 완전 좋아해.", "먹자골목 가면 먹을 거 많아요. 빈속은 안 돼요!|먹자골목 가 봐. 빈속은 안 돼!" }), cool = PC({ "저도 배고파요…|나도 배고파…" }) },
		full = { warm = PC({ "많이 먹었구나 ㅎㅎ 소화시킬 겸 해변 좀 걸어요.|많이 먹었구나 ㅋㅋ 소화시킬 겸 좀 걸어." }), cool = PC({ "부럽네요 ㅎㅎ|부럽다 ㅋㅋ" }) },
		bored = { warm = PC({ "심심하면 해변 산책 어때요? 아니면 오락실!|심심하면 산책 가자. 아니면 오락실!", "심심할 땐 사람 구경이 최고예요 ㅋㅋ|심심할 땐 사람 구경이 최고야 ㅋㅋ" }), cool = PC({ "저는 바빠서 심심할 틈도 없네요.|나는 바빠서 심심할 틈도 없다." }) },
		sick = { warm = PC({ "어디가 아파요? 약국이라도 가 봐요, 무리하지 말고요.|어디 아파? 약국 가 봐, 무리하지 말고.", "아프면 중앙병원 가 봐요. 참지 말고요.|아프면 중앙병원 가. 참지 말고." }), cool = PC({ "몸 관리 잘해요.|몸 관리 잘해." }) },
		stressed = { warm = PC({ "무슨 일인데요? 열받는 일 있었어요?|무슨 일인데? 열받는 일 있었어?", "그럴 땐 바닷바람 맞으면서 크게 한숨 쉬어요. 좀 나아요.|그럴 땐 바닷바람 맞으면서 한숨 크게 쉬어. 좀 나아." }), cool = PC({ "다들 스트레스 받죠 뭐.|다 스트레스 받지 뭐." }) },
		hot = { warm = PC({ "오늘 진짜 덥죠? 바다 한번 들어갔다 와요 ㅎㅎ|오늘 진짜 덥지? 바다 한번 들어갔다 와 ㅋㅋ" }), cool = PC({ "여름이니까요.|여름이잖아." }) },
		cold = { warm = PC({ "바닷바람이 차죠. 따뜻한 거라도 마셔요.|바닷바람 차지? 따뜻한 거 마셔." }), cool = PC({ "옷 좀 따뜻하게 입고 다녀요.|옷 좀 따뜻하게 입어." }) },
	},
	fact_name = PC({ "{pname}… 이름 좋네요! 기억할게요.|{pname}! 이름 좋다. 기억할게.", "아 {pnameI}구나! 반가워요.|아 {pnameI}구나! 반가워.", "{pname}, 외웠어요 ㅎㅎ 저는 {me}예요.|{pname}, 외웠다 ㅋㅋ 난 {me}." }),
	fact_name_old = PC({ "알아요 ㅎㅎ {pnameI}잖아요.|알지 ㅋㅋ {pnameI}잖아." }),
	fact_job = PC({ "아 {pjobI}구나! 힘들진 않아요?|아 {pjobI}구나! 안 힘들어?", "오, {pjob}! 어쩐지 그런 느낌 있었어요.|오, {pjob}! 어쩐지 그런 느낌이었어.", "{pjobI}면 바쁘겠다. 쉬는 날엔 뭐 해요?|{pjobI}면 바쁘겠다. 쉬는 날엔 뭐 해?" }),
	fact_job_same = PC({ "헐 저도 {pjob} 비슷한 거 해요! 동지네요 ㅎㅎ|헐 나도 비슷한 거 해! 동지다 ㅋㅋ" }),
	fact_like_same = PC({ "헐 저도 {plike} 좋아해요! 통했다!|헐 나도 {plike} 좋아해! 통했다!", "{plike} 좋아하는 사람 치고 나쁜 사람 없죠 ㅎㅎ|{plike} 좋아하는 사람 치고 나쁜 사람 없지 ㅋㅋ" }),
	fact_like = PC({ "{plike} 좋아하는구나. 기억해 둘게요!|{plike} 좋아하는구나. 기억해 둘게!", "오 {plike}? 저는 {mylike} 쪽이에요 ㅎㅎ|오 {plike}? 나는 {mylike} 쪽 ㅋㅋ" }),
	fact_like_hate = PC({ "{plike}요? 음… 저랑은 취향이 좀 다르네요 ㅎㅎ|{plike}? 음… 나랑은 취향이 좀 다르네 ㅋㅋ" }),
	fact_hate = PC({ "{phate} 싫어하는구나. 그럴 수 있죠.|{phate} 싫구나. 그럴 수 있지.", "ㅋㅋ {phate} 싫어하는 사람 은근 많더라고요.|ㅋㅋ {phate} 싫어하는 사람 은근 많더라." }),
	fact_age_young = PC({ "{page}살이요? 저보다 동생이네요 ㅎㅎ|{page}살? 나보다 동생이네 ㅋㅋ" }),
	fact_age_old = PC({ "{page}살이요? 저보다 언니… 아니 선배시네요 ㅎㅎ|{page}살? 나보다 형이네… 누나인가 ㅋㅋ" }),
	fact_age_same = PC({ "{page}살이요? 헐 동갑이다!|{page}살? 헐 동갑이다!" }),
	fact_from = PC({ "{pfrom}에서 왔구나! 광안리는 어때요?|{pfrom}에서 왔어? 광안리 어때?", "{pfrom} 사람이구나! 부산 오니까 좋죠?|{pfrom} 사람이구나! 부산 좋지?" }),
	fact_did = PC({ "오늘 {pdid}? 고생했네요!|오늘 {pdid}? 고생했다!", "{pdid}했구나. 대단하다 ㅎㅎ|{pdid}했구나. 대단하다 ㅋㅋ" }),
	recall_feel_bad = PC({ "지난번에 {pfeel}더니, 좀 괜찮아졌어요?|저번에 {pfeel}더니 좀 괜찮아?", "그때 {pfeel}고 했잖아요. 오늘은 어때요?|그때 {pfeel}고 했잖아. 오늘은 어때?" }),
	recall_feel_good = PC({ "저번엔 {pfeel}더니 오늘도 좋아 보여요!|저번엔 {pfeel}더니 오늘도 좋아 보인다!" }),
	recall_job = PC({ "요즘 {pjob} 일은 할 만해요?|요즘 {pjob} 일은 할 만해?" }),
	recall_like = PC({ "{plike} 좋아한다고 했죠? 저 그거 생각나더라고요 ㅎㅎ|{plike} 좋아한다 했지? 그거 보니까 너 생각나더라 ㅋㅋ" }),
	recall_did = PC({ "저번에 {pdid} 했다던 거 어떻게 됐어요?|저번에 {pdid} 했다던 거 어떻게 됐어?" }),
	name_call = PC({ "{pname}씨!|{pname}아!" }),
	you_too_feel = {
		good = PC({ "저요? 저는 오늘 꽤 괜찮아요 ㅎㅎ|나? 나는 오늘 꽤 괜찮아 ㅋㅋ", "저는 {pname2} 만나서 기분 좋아졌어요!|나는 너 만나서 기분 좋아졌어!" }),
		tired = PC({ "저도 좀 피곤해요. {tired}|나도 좀 피곤해. {tired}" }),
		meh = PC({ "저는 그냥 그래요. 평소랑 똑같죠 뭐.|나는 그냥 그래. 평소랑 똑같지 뭐." }),
	},
	tired_reason = { "오늘 할 일이 많았거든요.", "어제 늦게 잤어요.", "아침부터 계속 서 있었어요.", "날씨 때문인지 몸이 무거워요." },
	why_generic = PC({ "음… 그냥 그런 느낌이에요 ㅎㅎ|음… 그냥 그런 느낌이야 ㅋㅋ", "왜냐면… 저도 잘 모르겠어요 ㅋㅋ|왜냐면… 나도 몰라 ㅋㅋ", "살다 보니 그렇게 됐어요 ㅎㅎ|살다 보니 그렇게 됐어 ㅋㅋ" }),
	really = PC({ "진짜요! 거짓말 아니에요 ㅎㅎ|진짜지! 거짓말 아니야 ㅋㅋ", "네 진짜예요. 못 믿겠어요?|응 진짜야. 못 믿겠어?", "ㅋㅋ 놀랐죠?|ㅋㅋ 놀랐지?" }),
	laugh = PC({ "ㅋㅋㅋ 왜 웃어요?|ㅋㅋㅋ 왜 웃어?", "ㅎㅎ 웃으니까 보기 좋다.|ㅋㅋ 웃으니까 보기 좋다.", "ㅋㅋㅋ 나도 웃기다.|ㅋㅋㅋ 나도 웃기다." }),
	laugh_cold = PC({ "…뭐가 웃겨요?|…뭐가 웃겨?" }),
	what_again = PC({ "아 그러니까, {last}|아 그러니까, {last}", "다시 말하면요, {last}|다시 말하면, {last}" }),
	ok = PC({ "네 ㅎㅎ|응 ㅋㅋ", "그렇다니까요 ㅎㅎ|그렇다니까 ㅋㅋ", "ㅎㅎ 그쵸?|ㅋㅋ 그치?" }),
	me_too = PC({ "오 통했다! ㅎㅎ|오 통했다! ㅋㅋ", "헐 진짜요? 우리 잘 맞는다!|헐 진짜? 우리 잘 맞는다!" }),
	ans_often_yes = PC({ "어쩐지 낯이 익더라 ㅎㅎ|어쩐지 낯이 익더라 ㅋㅋ" }),
	ans_often_no = PC({ "처음이에요? 그럼 대교 야경은 꼭 보고 가요!|처음이야? 그럼 대교 야경은 꼭 보고 가!" }),
	ans_mood_good = PC({ "다행이다 ㅎㅎ 좋은 하루 보내요!|다행이다 ㅋㅋ" }),
	ans_mood_bad = PC({ "에고… 무슨 일 있었어요?|에고… 무슨 일 있어?" }),
	ans_secret = PC({ "에이~ 치사해요 ㅎㅎ 다음엔 알려 줘요.|에이~ 치사하다 ㅋㅋ 다음엔 알려 줘." }),
	ans_generic = PC({ "아 그렇구나 ㅎㅎ|아 그렇구나 ㅋㅋ", "오 그래요? 몰랐네요.|오 그래? 몰랐네.", "음음, 그렇군요.|음음, 그렇구나." }),
	agree = PC({ "그쵸! 역시 뭘 좀 아네요 ㅎㅎ|그치! 역시 뭘 좀 아네 ㅋㅋ", "맞아요 맞아요!|맞아 맞아!" }),
	disagree_warm = PC({ "아 그래요? 사람마다 다르죠 ㅎㅎ|아 그래? 사람마다 다르지 ㅋㅋ" }),
	disagree_proud = PC({ "에이, 한번 제대로 해 보면 생각 바뀔걸요?|에이, 제대로 해 보면 생각 바뀔걸?" }),
	echo = PC({ "{w}요? 오, 그건 처음 들어 봐요. 더 얘기해 줘요.|{w}? 처음 들어 보는데. 더 얘기해 봐.", "{w}… 음, 저는 그쪽은 잘 몰라서요 ㅎㅎ|{w}… 음, 나는 그쪽은 잘 몰라 ㅋㅋ", "{w} 얘기 재밌네요. 그래서요?|{w} 얘기 재밌다. 그래서?" }),
	echo_q = PC({ "음… {w}는 잘 모르겠어요. 미안해요 ㅎㅎ|음… {w}는 잘 모르겠어. 미안 ㅋㅋ", "{w}요? 글쎄요, 다른 사람한테 물어보는 게 나을 것 같아요.|{w}? 글쎄, 다른 사람한테 물어봐." }),
	unknown = PC({ "음… 무슨 말인지 잘 모르겠어요 ㅎㅎ|음… 무슨 말인지 잘 모르겠어 ㅋㅋ", "어… 그러니까 무슨 얘기예요?|어… 그러니까 무슨 얘기야?" }),
	topic_shift = PC({ "근데 있잖아요, {q}|근데 있잖아, {q}" }),
	same_text = PC({ "같은 말 또 하네요 ㅋㅋ|같은 말 또 하네 ㅋㅋ", "아까 그 말 했잖아요 ㅎㅎ|아까 그 말 했잖아 ㅋㅋ" }),
	same_text_stop = PC({ "자꾸 같은 말 하니까 좀 무서워요…|자꾸 같은 말 하니까 좀 무섭다…" }),
	swear_frown = PC({ "말 좀 예쁘게 해요…|말 좀 예쁘게 해…", "어머, 말이 좀 험하시네요.|말이 좀 험하다?" }),
	swear_laugh = PC({ "ㅋㅋㅋ 입 험한 거 봐|ㅋㅋㅋ 입 험한 거 봐", "ㅋㅋ 너 화났냐?|ㅋㅋ 너 화났냐?" }),
	curt_angry = PC({ "지금 얘기하고 싶지 않아요.|지금 얘기하기 싫어.", "…할 말 없어요.|…할 말 없어." }),
	curt_scared = PC({ "저, 저 가 봐야 해서요…|나, 나 가 봐야 돼…", "죄송해요, 저 바빠서…|미안, 나 바빠서…" }),
	banmal_yes = PC({ "좋아! 이제부터 편하게 하자 ㅎㅎ|좋아! 이제부터 편하게 하자 ㅎㅎ", "그래 그래, 말 놓자! 어색하다 ㅋㅋ|그래 그래, 말 놓자! 어색하다 ㅋㅋ" }),
	banmal_always = PC({ "난 원래 이렇게 말하잖아 ㅋㅋ 편하게 해.|난 원래 이렇게 말하잖아 ㅋㅋ 편하게 해." }),
	banmal_no = PC({ "음… 아직은 좀요. 조금 더 친해지면요 ㅎㅎ|음… 아직은 좀. 조금 더 친해지면 ㅋㅋ", "말 놓기엔 아직 이른 것 같아요 ㅎㅎ|말 놓기엔 아직 이른 것 같아 ㅋㅋ" }),
	banmal_offer = PC({ "근데 우리 이제 말 편하게 할까요?|근데 우리 이제 말 편하게 할까?" }),
	polite_ok = PC({ "네, 알겠어요. 존댓말 할게요.|알겠어. 존댓말 할게요." }),
	night = PC({ "근데 이 시간에 안 자고 뭐 해요?|근데 이 시간에 안 자고 뭐 해?", "밤늦게 혼자 다니면 위험해요. 조심해요.|밤늦게 혼자 다니면 위험해. 조심해." }),
	rain = PC({ "근데 비 오는데 우산 있어요?|근데 비 오는데 우산 있어?" }),
	wanted = PC({ "저… 혹시 경찰이 찾는 사람 아니에요…? 저는 아무것도 못 봤어요…|너… 경찰이 찾는 사람 아니야…? 난 아무것도 못 봤어…" }),
	news = PC({ "아 맞다, {news}|아 맞다, {news}" }),
	situation_where = PC({ "여기 {area} 근처예요.|여기 {area} 근처야." }),
	where_generic = PC({ "음… 그건 관광안내소에 물어보는 게 정확할 거예요.|음… 관광안내소에 물어보는 게 정확할걸." }),
	doing_now = PC({ "저요? 지금 {status}이에요.|나? 지금 {status}이야.", "{status}이었어요. 근데 말 걸어 줘서 반가워요 ㅎㅎ|{status}이었어. 말 걸어 줘서 반가워 ㅋㅋ" }),
	your_turn = PC({ "{you}님은요?|너는?", "{you}님도 좋아해요?|너도 좋아해?" }),
	third_who = PC({ "누구요? 아, 저도 처음 보는 사람이에요.|누구? 나도 처음 보는 사람인데.", "글쎄요, 이 동네 사람 같진 않던데요.|글쎄, 이 동네 사람 같진 않던데.", "아 그 사람이요? 저도 잘 몰라요 ㅎㅎ|아 그 사람? 나도 잘 몰라 ㅋㅋ" }),
	invite_kind_no = PC({ "{kind}요? 음… 오늘은 좀 그래요.|{kind}? 음… 오늘은 좀 그래." }),
}

-- the shop of a clerk at work (by the roster's work area)
local SHOP_OF = { gs25 = "store", gs25_beach = "store", homeplus = "store", starbucks_beach = "cafe", hongmidang = "cafe", bread = "cafe", hoetown = "hoe", bronx = "burger", salon = "salon", millak_market = "market", plaza = "stall", fishmarket = "hoe" }
local SHOP_KW = {
	order = { "주세요", "주문", "줘", "하나요", "한 잔", "한잔 주", "두 개", "하나 주", "포장" },
	price = { "얼마", "가격", "비싸", "싸요", "할인", "1+1", "원 플러스", "행사" },
	pay = { "계산", "카드", "현금", "결제", "페이", "영수증", "포인트", "적립" },
	menu = { "추천", "메뉴", "뭐가 맛있", "뭐 맛있", "잘 나가", "인기" },
	bag = { "봉투", "봉지" },
	hours = { "몇 시까지", "영업", "문 닫", "언제까지", "몇시까지" },
	toilet = { "화장실" },
}
local SHOP_ORDER = { "toilet", "hours", "bag", "pay", "price", "menu", "order" }
local SHOP = {
	store = {
		greet = PC({ "어서오세요~ 찾으시는 거 있으세요?|어서 와~ 뭐 찾아?" }),
		order = PC({ "{order} 말씀이시죠? 저쪽 진열대에 있어요. 계산대로 가져오시면 바로 해 드릴게요.|{order}? 저쪽 진열대에 있어. 계산대로 가져와." }),
		price = PC({ "요즘 1+1 행사 많이 해요! 음료 쪽 한번 보세요.|요즘 1+1 많이 해! 음료 쪽 봐 봐." }),
		pay = PC({ "카드, 현금 다 돼요. 계산대에서 도와드릴게요.|카드 현금 다 돼. 계산대로 와." }),
		menu = PC({ "삼각김밥이랑 컵라면 조합이 제일 잘 나가요 ㅎㅎ|삼김에 컵라면 조합이 제일 잘 나가 ㅋㅋ" }),
		bag = PC({ "봉투 필요하시면 백 원이에요!|봉투는 백 원!" }),
		hours = PC({ "저희는 이십사 시간이에요!|우리는 이십사 시간이야!" }),
		toilet = PC({ "화장실은 건물 뒤쪽이에요. 비밀번호는 영수증에 있어요.|화장실은 건물 뒤쪽. 비번은 영수증에." }),
	},
	cafe = {
		greet = PC({ "어서오세요! 주문 도와드릴까요?|어서 와! 뭐 마실래?" }),
		order = PC({ "{order} 한 잔이요? 네! 결제는 키오스크나 카운터에서 해 주시면 바로 만들어 드릴게요.|{order}? 오케이! 결제하면 바로 만들어 줄게." }),
		price = PC({ "아메리카노는 사천오백 원이에요. 텀블러 가져오시면 할인돼요.|아아는 사천오백 원. 텀블러 있으면 할인돼." }),
		pay = PC({ "카운터에서 결제 도와드릴게요!|카운터에서 결제해 줘!" }),
		menu = PC({ "오늘은 바닐라 라떼 추천해요. 소금빵이랑 같이 드시면 최고예요.|오늘은 바닐라 라떼 추천! 소금빵이랑 같이 먹어." }),
		bag = PC({ "포장 봉투 따로 챙겨 드릴게요!|포장 봉투 챙겨 줄게!" }),
		hours = PC({ "밤 열 시까지 해요.|밤 열 시까지 해." }),
		toilet = PC({ "화장실은 안쪽 왼편이에요.|화장실은 안쪽 왼편." }),
	},
	hoe = {
		greet = PC({ "어서오이소! 오늘 광어 물 좋습니데이.|어서 와라! 오늘 광어 물 좋다." }),
		order = PC({ "{order}요? 좋지예! 자리 잡고 앉아 계시면 바로 내드릴게예.|{order}? 좋지! 앉아 있으면 바로 내줄게." }),
		price = PC({ "모둠회 중자 오만 원부터예요. 싯가라 날마다 좀 달라요.|모둠 중자 오만 원부터. 싯가라 좀 달라." }),
		pay = PC({ "계산은 나가실 때 카운터에서요!|계산은 나갈 때 카운터에서!" }),
		menu = PC({ "오늘은 도다리 추천이에요. 제철이라 고소해요.|오늘은 도다리! 제철이라 고소해." }),
		bag = PC({ "포장도 돼요! 얼음 넉넉히 넣어 드릴게요.|포장 돼! 얼음 넉넉히 넣어 줄게." }),
		hours = PC({ "새벽 한 시까지 해요.|새벽 한 시까지 해." }),
		toilet = PC({ "화장실은 나가서 오른쪽이요.|화장실은 나가서 오른쪽." }),
	},
	burger = {
		greet = PC({ "어서오세요! 브롱스입니다~|어서 와! 브롱스야~" }),
		order = PC({ "{order} 하나요? 굽기 정도는 미디엄으로 해 드릴게요. 계산은 카운터에서요!|{order}? 미디엄으로 구워 줄게. 계산은 카운터!" }),
		price = PC({ "시그니처 버거 세트가 만 오천 원이에요.|시그니처 세트 만 오천 원." }),
		pay = PC({ "카운터에서 계산해 드릴게요!|카운터에서 계산해!" }),
		menu = PC({ "베이컨 치즈 버거가 제일 인기예요.|베이컨 치즈가 제일 인기야." }),
		bag = PC({ "포장해 드릴까요? 감자튀김은 따로 담을게요.|포장? 감튀는 따로 담아 줄게." }),
		hours = PC({ "밤 열한 시까지예요.|밤 열한 시까지." }),
		toilet = PC({ "화장실은 호텔 로비 쪽이에요.|화장실은 호텔 로비 쪽." }),
	},
	salon = {
		greet = PC({ "어서오세요~ 커트 예약하셨어요?|어서 와~ 예약했어?" }),
		order = PC({ "{order}요? 네, 자리 안내해 드릴게요. 결제는 끝나고 해요.|{order}? 앉아. 결제는 끝나고!" }),
		price = PC({ "커트는 이만 원부터예요.|커트 이만 원부터." }),
		pay = PC({ "끝나고 카운터에서 결제하시면 돼요.|끝나고 카운터에서 결제해." }),
		menu = PC({ "요즘은 레이어드 컷이 인기예요.|요즘 레이어드 컷이 인기야." }),
		bag = PC({ "쇼핑백에 넣어 드릴게요!|쇼핑백에 넣어 줄게!" }),
		hours = PC({ "저녁 여덟 시까지예요.|저녁 여덟 시까지." }),
		toilet = PC({ "화장실은 복도 끝이에요.|화장실은 복도 끝." }),
	},
	market = {
		greet = PC({ "어서오이소~ 과일 싱싱합니데이!|어서 와~ 과일 싱싱하다!" }),
		order = PC({ "{order}요? 좋은 걸로 골라 드릴게요. 덤도 하나 넣어 드릴게예.|{order}? 좋은 걸로 골라 줄게. 덤도 하나!" }),
		price = PC({ "한 바구니 만 원이에요. 많이 사면 깎아 드리지예.|한 바구니 만 원. 많이 사면 깎아 줄게." }),
		pay = PC({ "현금이면 더 좋고, 카드도 돼요.|현금이면 좋고 카드도 돼." }),
		menu = PC({ "오늘은 귤이 달아요!|오늘은 귤이 달다!" }),
		bag = PC({ "봉지 하나 더 드릴게예.|봉지 하나 더 줄게." }),
		hours = PC({ "해 지면 닫아요.|해 지면 닫아." }),
		toilet = PC({ "시장 공중화장실은 입구 쪽이에요.|화장실은 입구 쪽." }),
	},
	stall = {
		greet = PC({ "어서 와요~ 따끈한 거 있어요!|어서 와~ 따끈한 거 있다!" }),
		order = PC({ "{order}요? 금방 해 줄게요. 뜨거우니까 조심해요!|{order}? 금방 해 줄게. 뜨거우니까 조심!" }),
		price = PC({ "세 개 이천 원이에요.|세 개 이천 원." }),
		pay = PC({ "계좌이체도 돼요!|이체도 돼!" }),
		menu = PC({ "팥이 제일 잘 나가요.|팥이 제일 잘 나가." }),
		bag = PC({ "봉지에 담아 줄게요.|봉지에 담아 줄게." }),
		hours = PC({ "재료 떨어지면 끝이에요 ㅎㅎ|재료 떨어지면 끝 ㅋㅋ" }),
		toilet = PC({ "화장실은 광장 건너편이요.|화장실은 광장 건너편." }),
	},
	off = PC({ "저 지금 퇴근했어요 ㅋㅋ 가게는 {work}에 있어요. 거기로 오세요!|나 지금 퇴근했어 ㅋㅋ 가게는 {work}. 거기로 와!", "아 그건 가게에서요 ㅎㅎ 지금은 쉬는 중이라.|그건 가게에서 ㅋㅋ 지금은 쉬는 중이야." }),
}

-- invites by words
local INVITE_KW = {
	{ "karaoke", { "노래방", "코노", "코인노래" } }, { "bowling", { "볼링" } }, { "billiards", { "당구", "포켓볼" } },
	{ "club", { "클럽" } }, { "pocha", { "포차", "한잔", "술 마시", "술마시", "소주", "치맥" } }, { "cafe", { "카페", "커피" } },
	{ "meal", { "밥", "식사", "먹으러", "맛집", "저녁 먹", "점심 먹" } }, { "beach", { "바다", "산책", "해변" } },
	{ "now", { "같이 다니", "같이 걷", "같이 걸" } },
}
local INVITE_VERB = { "가자", "갈래", "갈까", "가요", "할래", "할까", "하자", "먹자", "먹을래", "먹을까", "마시자", "마실래", "치자", "칠래", "놀자", "놀래", "다니자", "걷자", "콜?" }

-------------------------------------------------------------------------------------------------
-- reading one clause
-------------------------------------------------------------------------------------------------
local function isQuestion(s: string, qmark: boolean): boolean
	if qmark then
		return true
	end
	local t = string.gsub(s, "[%s%p~]+$", "")
	for _, e in Q_ENDS do
		if string.find(t, e) then
			return true
		end
	end
	for _, list in WH do
		if anyOf(s, list) then
			return true
		end
	end
	return false
end

local function whOf(s: string): string?
	for _, k in { "why", "where", "when", "who", "much", "how", "what" } do
		if anyOf(s, WH[k]) then
			return k
		end
	end
	return nil
end

local function topicOf(s: string): string?
	for _, k in TOPIC_ORDER do
		local T = TOPICS[k]
		if anyOf(s, T.kw) then
			return k
		end
	end
	return nil
end

local function feelOf(s: string): string?
	for _, k in FEEL_ORDER do
		local w = anyOf(s, FEEL[k])
		if w then
			-- "안 피곤해" / "안 배고파" = not
			local i = string.find(s, w, 1, true) or 1
			local before = string.sub(s, math.max(1, i - 4), i - 1)
			if not has(before, "안 ") and not has(before, "안") then
				return k
			end
		end
	end
	return nil
end

local function sentiment(s: string): number
	local n = 0
	for _, w in NEG do
		if has(s, w) then
			n -= 1
		end
	end
	if n == 0 then
		for _, w in POS do
			if has(s, w) then
				n += 1
			end
		end
	end
	return n
end

local function selfMarked(s: string): boolean
	local p = " " .. s
	for _, w in SELF do
		if has(p, " " .. w) or string.sub(s, 1, #w) == w then
			return true
		end
	end
	return false
end

local function youMarked(s: string): boolean
	local p = " " .. s
	for _, w in YOU do
		if has(p, " " .. w) or string.sub(s, 1, #w) == w then
			return true
		end
	end
	return false
end

local function ctxOf(s: string): string?
	local t = trim(s)
	local short = utf8len(t) <= 8
	if not short then
		return nil
	end
	-- only ㅋ / ㅎ = laughing
	if string.find(t, "^[ㅋㅎ%s~!]+$") or t == "ㅋㅋ" then
		return "laugh"
	end
	t = string.gsub(t, "%?", "")
	for _, k in { "you_too", "why", "really", "what", "me_too", "ok" } do
		for _, w0 in CTX[k] do
			local w = string.gsub(w0, "%?", "")
			if t == w or (k ~= "ok" and k ~= "me_too" and string.sub(t, 1, #w) == w and utf8len(t) <= utf8len(w) + 2) then
				return k
			end
		end
	end
	if string.sub(t, 1, #"나도") == "나도" or string.sub(t, 1, #"저도") == "저도" then
		return "me_too"
	end
	return nil
end

-- a fact the player tells about themselves: { k = "name"|"job"|"like"|"hate"|"age"|"from"|"did", v }
local function factOf(s: string, q: boolean): any?
	if q then
		return nil
	end
	local nm = string.match(s, "내 이름은%s*(%S+)") or string.match(s, "제 이름은%s*(%S+)") or string.match(s, "(%S+)%s*라고 불러") or string.match(s, "(%S+)%s*이라고 불러") or string.match(s, "^나는%s*(%S+)%s*라고 해") or string.match(s, "^저는%s*(%S+)%s*라고 해") or string.match(s, "^저는%s*(%S+)%s*이라고 합니다") or string.match(s, "^저는%s*(%S+)%s*입니다")
	if nm then
		local b = bareWord(nm)
		if validName(b) then
			return { k = "name", v = b }
		end
	end
	local age = string.match(s, "(%d+)%s*살")
	if age and (selfMarked(s) or string.find(s, "^%d")) then
		local n = tonumber(age)
		if n and n >= 8 and n <= 99 then
			return { k = "age", v = n }
		end
	end
	local from = string.match(s, "(%S+)에서 왔") or string.match(s, "(%S+)에서 놀러") or string.match(s, "(%S+) 사람이야") or string.match(s, "(%S+) 사람이에요")
	if from and utf8len(from) <= 6 and not has(from, "어디") then
		return { k = "from", v = from }
	end
	local like = string.match(s, "(%S+)%s*좋아해") or string.match(s, "(%S+)%s*좋아함") or string.match(s, "(%S+)%s*좋아합니다") or string.match(s, "(%S+)%s*좋아해요") or string.match(s, "(%S+)%s*완전 좋아")
	if like and (selfMarked(s) or not youMarked(s)) then
		local b = stripJosa(string.gsub(like, "[%p~]+$", ""), { "을", "를", "은", "는" })
		if utf8len(b) >= 1 and b ~= "나" and b ~= "너" and b ~= "널" and b ~= "너를" and b ~= "당신" and b ~= "진짜" and b ~= "엄청" and b ~= "완전" then
			return { k = "like", v = b }
		end
	end
	local hate = string.match(s, "(%S+)%s*싫어해") or string.match(s, "(%S+)%s*싫어") or string.match(s, "(%S+)%s*별로야") or string.match(s, "(%S+)%s*별로예요")
	if hate and selfMarked(s) then
		local b = stripJosa(string.gsub(hate, "[%p~]+$", ""), { "을", "를", "은", "는" })
		if utf8len(b) >= 1 and b ~= "나" and b ~= "너" and b ~= "진짜" and b ~= "너무" then
			return { k = "hate", v = b }
		end
	end
	local did = string.match(s, "오늘%s+(%S+)%s*했") or string.match(s, "방금%s+(%S+)%s*했") or string.match(s, "(%S+)%s*하고 왔")
	if did and utf8len(did) <= 6 then
		return { k = "did", v = bareWord(stripJosa(did, { "을", "를" })) }
	end
	if selfMarked(s) then
		for _, group in JOBS do
			local w = anyOf(s, group)
			if w then
				return { k = "job", v = group[1] }
			end
		end
	end
	return nil
end

local function inviteKindOf(s: string): string?
	if not anyOf(s, INVITE_VERB) then
		return nil
	end
	for _, pair in INVITE_KW do
		if anyOf(s, pair[2]) then
			return pair[1]
		end
	end
	return nil
end

local function shopOf(s: string): string?
	for _, k in SHOP_ORDER do
		if anyOf(s, SHOP_KW[k]) then
			return k
		end
	end
	return nil
end

local QTY = { ["하나"] = true, ["한"] = true, ["두"] = true, ["세"] = true, ["잔"] = true, ["개"] = true, ["한잔"] = true, ["두개"] = true, ["이거"] = true, ["그거"] = true, ["저거"] = true, ["좀"] = true }
local function orderItem(s: string): string?
	local w = nil
	for _, pat in { "(%S+)%s+하나", "(%S+)%s+한 잔", "(%S+)%s+두 개", "(%S+)%s+한잔", "(%S+)%s+주세요", "(%S+)%s+줘" } do
		local x = string.match(s, pat)
		if x and not QTY[x] then
			w = x
			break
		end
	end
	if w then
		w = stripJosa(w, { "을", "를", "이", "가" })
		if utf8len(w) >= 1 and utf8len(w) <= 10 then
			return w
		end
	end
	return nil
end

-- the main noun of a clause (for an echo): the longest Hangul word that is not a function word
local STOP = { ["근데"] = true, ["그냥"] = true, ["진짜"] = true, ["너무"] = true, ["오늘"] = true, ["지금"] = true, ["그거"] = true, ["이거"] = true, ["저거"] = true, ["뭐야"] = true, ["있어"] = true, ["없어"] = true, ["그래서"] = true, ["그리고"] = true, ["혹시"] = true, ["완전"] = true, ["약간"] = true, ["아니"] = true, ["있잖아"] = true }
local function nounOf(s: string): string?
	local best, bestN = nil, 0
	for w in string.gmatch(s, "%S+") do
		local b = bareWord(string.gsub(w, "[%p~]+", ""))
		b = stripJosa(b)
		local n = utf8len(b)
		local cp = utf8.codepoint(b, 1, 1)
		if n >= 2 and n <= 6 and not STOP[b] and cp and cp >= 0xAC00 and cp <= 0xD7A3 and n > bestN then
			best, bestN = b, n
		end
	end
	return best
end

function Talk.clauses(text: string): { any }
	local out = {}
	local s = string.gsub(text, "\r", "")
	local i = 1
	local n = #s
	while i <= n do
		local a, b = string.find(s, "[%.%!%?\n~]+", i)
		local part, punct
		if a then
			part, punct = string.sub(s, i, a - 1), string.sub(s, a, b)
			i = b + 1
		else
			part, punct = string.sub(s, i), ""
			i = n + 1
		end
		part = trim(part)
		if part ~= "" then
			-- "A 근데 B" / "A 그리고 B": two clauses
			local cut = nil
			for _, conn in { " 근데 ", " 그리고 ", " 그런데 ", " 아 그리고 " } do
				local x = string.find(part, conn, 1, true)
				if x and x > 4 then
					cut = { x, #conn }
					break
				end
			end
			if cut then
				table.insert(out, { t = trim(string.sub(part, 1, cut[1] - 1)), q = false })
				table.insert(out, { t = trim(string.sub(part, cut[1] + cut[2])), q = has(punct, "?") })
			else
				table.insert(out, { t = part, q = has(punct, "?") })
			end
		elseif has(punct, "?") and #out > 0 then
			out[#out].q = true
		end
	end
	if #out == 0 and has(text, "?") then
		table.insert(out, { t = "?", q = true })
	end
	while #out > 3 do
		local last = table.remove(out)
		out[#out].t ..= " " .. last.t
		out[#out].q = out[#out].q or last.q
	end
	return out
end

-- one clause -> signals
local RULE_STRONG = { insult = 10, provoke = 10, threaten = 10, confess = 9, apologize = 8, number = 8, flirt = 7, invite = 7, request = 6, bye = 6, thank = 5, compliment = 5, name = 5, age = 5, job = 5, food_q = 5, like_q = 5, hobby_q = 5, news_q = 5, place_q = 4, joke = 4, comfort = 4, how = 4, doing = 4, about = 4, food_talk = 3, weather = 3, brag = 3, gift_talk = 3, greet = 2, yes = 1, no = 1, small = 0 }

function Talk.read(cl: any, names: { any }?): any
	local s = string.lower(cl.t)
	local q = isQuestion(s, cl.q)
	local intent, slots = M.parse(cl.t, names)
	local sig = { t = cl.t, s = s, q = q, intent = intent, slots = slots, polite = slots.polite }
	sig.wh = if q then whOf(s) else nil
	sig.topic = topicOf(s)
	sig.feel = feelOf(s)
	sig.ctx = ctxOf(s)
	sig.fact = factOf(s, q)
	sig.self = selfMarked(s)
	sig.you = youMarked(s)
	sig.sent = sentiment(s)
	sig.shop = shopOf(s)
	sig.invite = inviteKindOf(s)
	sig.banmal = anyOf(s, BANMAL_ASK) ~= nil
	sig.politeAsk = anyOf(s, POLITE_ASK) ~= nil
	-- swearing / an insult that is not aimed at the NPC is not an insult
	local swear = anyOf(s, SWEAR) ~= nil
	if intent == "insult" then
		local direct = anyOf(s, DIRECT_INSULT) ~= nil or sig.you
		if not direct then
			if sig.feel then
				sig.intent = "small" -- "나 오늘 짜증나" = a feeling
			elseif has(s, "미친") and (has(s, "맛") or has(s, "뷰") or has(s, "경치") or has(s, "야경") or has(s, "듯")) then
				sig.intent = "small"
				sig.wow = true
			elseif swear then
				sig.intent = "small"
				sig.swear = true
			elseif sig.self then
				sig.intent = "small" -- "나 바보인가 봐"
			end
		end
	elseif swear then
		sig.swear = true
	end
	-- "좋아해" with a thing = a taste, not "yes"; "X 좋아해?" = asking their taste of X
	if sig.fact and (sig.intent == "yes" or sig.intent == "no" or sig.intent == "small" or sig.intent == "like_q" or sig.intent == "food_talk") then
		sig.intent = "small"
	end
	-- a feeling beats a stray weak keyword ("피곤해서 그냥 걷는 중" is not "doing")
	if sig.feel and (RULE_STRONG[sig.intent] or 0) <= 4 and sig.intent ~= "greet" then
		if not (q and (sig.intent == "how" or sig.intent == "doing")) then
			sig.intent = "small"
		end
	end
	if sig.feel == "hot" or sig.feel == "cold" then
		if sig.intent == "weather" then
			sig.feel = nil -- the weather talk of the composer handles it
		end
	end
	-- a fact about yourself ("나 대학생이야") is not a question about them
	if sig.fact and not q and (RULE_STRONG[sig.intent] or 0) <= 5 then
		sig.intent = "small"
	end
	-- a topic asked about ("야구 좋아해?", "게임 뭐 해?", "어디서 커피 마셔?") is this layer's
	local TOPIC_WEAK = { yes = true, no = true, small = true, like_q = true, hobby_q = true, doing = true, how = true, food_talk = true, gift_talk = true, place_q = true }
	if sig.topic and TOPIC_WEAK[sig.intent] and not (sig.intent == "food_talk" and not q and not sig.wh) then
		sig.intent = "small"
		sig.likeQ = q and has(s, "좋아")
	end
	-- shop words at someone's shop
	if sig.shop and (RULE_STRONG[sig.intent] or 0) <= 5 then
		sig.intent = "small"
	end
	-- someone else ("그 사람 누구야?") is not their name
	if anyOf(s, { "그 사람", "저 사람", "그사람", "저사람", "걔", "쟤", "그분", "저분", "그 여자", "그 남자", "아까 그" }) and (sig.intent == "name" or sig.intent == "small") then
		sig.intent = "small"
		sig.third = true
	end
	-- laughing alone is not a joke
	if sig.ctx == "laugh" then
		sig.intent = "small"
	end
	-- a context word alone (진짜? / 왜? / 너는?) is never a rule intent
	if sig.ctx and (RULE_STRONG[sig.intent] or 0) <= 1 then
		sig.intent = "small"
	end
	if sig.invite and sig.intent ~= "confess" then
		sig.intent = "invite"
	end
	if sig.banmal or sig.politeAsk then
		sig.intent = "small"
	end
	return sig
end

-------------------------------------------------------------------------------------------------
-- the reply
-------------------------------------------------------------------------------------------------
local FRIENDLY = { good = true, neutral = true, lover = true }

local function isWorking(c: any, env: any): (boolean, string?)
	if not Citizens or not c or not c.work then
		return false, nil
	end
	local area, act = nil, nil
	pcall(function()
		area, act = Citizens.whereNow(c.id, env.clock or 12)
	end)
	local shop = SHOP_OF[c.work]
	if not shop then
		return false, nil
	end
	return (act == "work" and area == c.work), shop
end

local function statusText(c: any, env: any): string?
	if not Citizens then
		return nil
	end
	local ok, what = pcall(Citizens.status, c.id, env.clock or 12)
	if ok and type(what) == "string" and what ~= "" then
		local w = string.match(what, "·%s*(.+)$") or what
		w = string.gsub(w, "%s*중$", " 중")
		return w
	end
	return nil
end

local function myLikeLabel(c: any): string
	local k = type(c.topics) == "table" and c.topics[1]
	local T = k and TOPICS[k]
	return T and T.label or "산책"
end

-- the pf record (player facts) of this NPC's record
local function pfOf(rec: any): any
	if type(rec.pf) ~= "table" then
		rec.pf = {}
	end
	local pf = rec.pf
	pf.likes = if type(pf.likes) == "table" then pf.likes else {}
	pf.hates = if type(pf.hates) == "table" then pf.hates else {}
	return pf
end

local function remember(list: { string }, v: string, cap: number)
	local i = table.find(list, v)
	if i then
		table.remove(list, i)
	end
	table.insert(list, v)
	while #list > cap do
		table.remove(list, 1)
	end
end

-- hated topic brought up earlier (rec.cd["hate:<topic>"] within 10 minutes)
local function hateRecent(rec: any, key: string, now: number): boolean
	local t0 = rec.cd and rec.cd["hate:" .. key]
	return type(t0) == "number" and now - t0 < 600
end

-- a part = { lines = {...}, d, face?, emote?, act?, ask?, invite?, mem?, intent, rule = out? }
local function part(lines: { string }?, intent: string): any
	return { lines = lines or {}, d = D(), intent = intent }
end

-- their own topic (a question from the roster's TOPICS, or this layer's ask)
local function shiftLine(c: any, rec: any, env: any, reg: string, tc: any, r: () -> number): string?
	local keys = type(c.topics) == "table" and c.topics or {}
	if #keys == 0 then
		return nil
	end
	local key = keys[1 + math.floor(r() * #keys)]
	if tc.topic == key then
		return nil
	end
	local q = nil
	local CT = Citizens and Citizens.TOPICS and Citizens.TOPICS[key]
	if CT and CT.qs and #CT.qs > 0 then
		local e = CT.qs[1 + math.floor(r() * #CT.qs)]
		q = e[reg] or e.p
	end
	if not q and TOPICS[key] and TOPICS[key].ask then
		local list = TOPICS[key].ask[reg] or TOPICS[key].ask.p
		q = list[1 + math.floor(r() * #list)]
	end
	if not q then
		return nil
	end
	tc.ask = "topic:" .. key
	tc.askN = tc.n
	tc.topic = key
	local frame = if reg == "c" then "근데 있잖아, " else "근데 있잖아요, "
	return frame .. q
end

-- the first line of a meeting: what they remember about the player
local function recallLine(rec: any, env: any, reg: string, vars: any, r: () -> number): string?
	local pf = rec.pf
	if type(pf) ~= "table" then
		return nil
	end
	local now = env.now or os.time()
	local function pk(entry: any): string?
		local s = M.pick(entry[reg] or entry.p, rec, now, r)
		return s and M.fill(s, vars) or nil
	end
	local opts = {}
	if type(pf.feel) == "table" and now - (pf.feel.t or 0) < 3 * 86400 and now - (pf.feel.t or 0) > 120 then
		vars.pfeel = FEEL_LABEL[pf.feel.x] or "힘들다"
		table.insert(opts, if pf.feel.x == "happy" then B.recall_feel_good else B.recall_feel_bad)
	end
	if type(pf.did) == "table" and now - (pf.did.t or 0) < 2 * 86400 and now - (pf.did.t or 0) > 120 then
		vars.pdid = pf.did.x
		table.insert(opts, B.recall_did)
	end
	if pf.job then
		vars.pjob = pf.job
		table.insert(opts, B.recall_job)
	end
	if type(pf.likes) == "table" and #pf.likes > 0 then
		vars.plike = pf.likes[#pf.likes]
		table.insert(opts, B.recall_like)
	end
	if #opts == 0 then
		return nil
	end
	return pk(opts[1 + math.floor(r() * #opts)])
end

-- the situation (time, weather, live news, a wanted player) as one extra remark
local function situationLine(c: any, rec: any, env: any, reg: string, vars: any, r: () -> number): string?
	local now = env.now or os.time()
	local function pk(entry: any): string?
		local s = M.pick(entry[reg] or entry.p, rec, now, r)
		return s and M.fill(s, vars) or nil
	end
	local opts = {}
	if (env.wanted or 0) >= 2 and not M.traits(c).authority and not M.traits(c).hostile then
		return pk(B.wanted)
	end
	if env.liveNews and #env.liveNews > 0 then
		vars.news = env.liveNews[1]
		table.insert(opts, B.news)
	end
	local clock = env.clock or 12
	if clock >= 0 and clock < 4.5 then
		table.insert(opts, B.night)
	end
	if env.weather == "rain" then
		table.insert(opts, B.rain)
	end
	if #opts == 0 then
		return nil
	end
	return pk(opts[1 + math.floor(r() * #opts)])
end

function Talk.say(c: any, rec: any, text: string, env: any, tc: any, rule: (any) -> any, names: { any }?): any?
	if not M or type(text) ~= "string" or trim(text) == "" then
		return nil
	end
	local r = env.rnd or math.random
	local now = env.now or os.time()
	local t = M.traits(c)
	local arch = t.arch
	local aff = env.aff or 0
	local mood = M.mood(c, rec, aff, env)
	local reg = M.register(c, rec, aff)
	local st = M.stage(rec, aff)
	local pf = pfOf(rec)
	local P = M.prefs(c)
	tc = tc or {}
	tc.n = (tc.n or 0) + 1
	local vars = {
		you = pf.nm or env.you or "친구",
		me = c.name or "저",
		pname = pf.nm or env.you or "친구",
		pname2 = pf.nm or "당신",
		pjob = pf.job,
		pnameI = withI(pf.nm or env.you or "친구"),
		pjobI = withI(pf.job),
		page = pf.age,
		pfrom = pf.from,
		food = M.FOODS[P.foods[1] or "tteokbokki"].name,
		mylike = myLikeLabel(c),
		area = env.area or "해변",
		work = c.work and Citizens and Citizens.areaLabel and Citizens.areaLabel(c.work) or "가게",
		tired = B.tired_reason[1 + math.floor(r() * #B.tired_reason)],
	}
	local function pk(entry: any): string?
		if type(entry) ~= "table" then
			return nil
		end
		local s = M.pick(entry[reg] or entry.p, rec, now, r)
		return s and M.fill(s, vars) or nil
	end

	-- what they remember from before this message (facts said now must not come back as memories)
	tc.recall = if env.first then recallLine(rec, env, reg, table.clone(vars), r) else nil
	local clauses = Talk.clauses(text)
	if #clauses == 0 then
		return nil
	end
	local sigs = {}
	for _, cl in clauses do
		table.insert(sigs, Talk.read(cl, names))
	end

	-- the same message again and again
	local norm = string.gsub(string.lower(text), "[%s%p~]", "")
	if tc.lastText == norm and now - (tc.lastTextT or 0) < 120 then
		tc.same = (tc.same or 0) + 1
	else
		tc.same = 0
	end
	tc.lastText, tc.lastTextT = norm, now
	if tc.same >= 1 and #sigs == 1 and (RULE_STRONG[sigs[1].intent] or 0) < 8 then
		local p = part({ pk(if tc.same >= 3 then B.same_text_stop else B.same_text) or "…" }, "small")
		p.d.an = 2 + tc.same * 2
		p.face = if tc.same >= 3 then "wary" else "smug"
		if tc.same >= 3 then
			p.act = "leave"
		end
		return Talk.finish(c, rec, env, tc, { p }, mood, reg, st, r)
	end

	local parts = {}
	local used = 0
	local greetOnly = nil

	-- which clauses go to the composer (a rule intent), which this layer answers
	local function rulePart(sig: any): any
		local req = { text = sig.t, intent = sig.intent, polite = sig.polite, item = sig.slots.item, other = sig.slots.other }
		if sig.intent == "invite" and sig.invite then
			req.intent = "invite"
		end
		local out = rule(req)
		local p = part(out.lines, out.intent or sig.intent)
		p.rule = out
		p.d = out.d or D()
		p.face, p.emote, p.act, p.ask, p.mem, p.reveal = out.face, out.emote, out.act, out.ask, out.mem, out.reveal
		if sig.intent == "invite" and sig.invite and (out.act == "meet_menu" or FRIENDLY[mood]) then
			p.act = nil
			p.invite = sig.invite
		end
		return p
	end

	-- this layer's answer for one clause (nil = nothing to say about it)
	local function ownPart(sig: any): any?
		local s = sig.s
		-- angry / scared people don't chat
		if mood == "angry" or mood == "enemy" then
			local p = part({ pk(B.curt_angry) or "…" }, "small")
			p.face = "annoyed"
			p.emote = "turn"
			p.d.an = 1
			if rec.an >= 75 and chance(r, 0.5) then
				p.act = "leave"
			end
			return p
		elseif mood == "scared" then
			local p = part({ pk(B.curt_scared) or "…" }, "small")
			p.face = "scared"
			p.emote = "startle"
			if rec.fe >= 65 then
				p.act = "flee"
			end
			return p
		end
		-- speech level
		if sig.banmal then
			local okBm = (aff >= 30 or rec.cl >= 22 or t.banmal) and not ((arch == "rich" or arch == "police") and aff < 60)
			local p
			if rec.bm or reg == "c" then
				p = part({ pk(if t.banmal then B.banmal_always else B.ok) or "응 ㅋㅋ" }, "small")
				rec.bm = true
			elseif okBm then
				rec.bm = true
				reg = "c"
				p = part({ pk(B.banmal_yes) or "좋아!" }, "small")
				p.d.cl = 2
				p.d.aff = 1
				p.face = "laugh"
				p.emote = "cheer"
			else
				p = part({ pk(B.banmal_no) or "…" }, "small")
				p.face = "shy"
			end
			return p
		end
		if sig.politeAsk then
			rec.bm = false
			return part({ pk(B.polite_ok) or "네." }, "small")
		end
		-- an answer to what they just asked
		local ask = tc.ask
		if ask and tc.askN == tc.n - 1 then
			tc.ask = nil
			if ask == "banmal" then
				if sig.sent > 0 or sig.intent == "yes" then
					rec.bm = true
					reg = "c"
					local p = part({ pk(B.banmal_yes) or "좋아!" }, "small")
					p.d.cl, p.d.aff, p.face = 2, 1, "laugh"
					return p
				end
				return part({ pk(B.ok) or "네 ㅎㅎ" }, "small")
			elseif ask == "yourname" and not sig.q then
				local nm = (sig.fact and sig.fact.k == "name" and sig.fact.v) or bareWord(sig.t)
				if has(s, "비밀") or has(s, "안 알려") or has(s, "몰라") then
					return part({ pk(B.ans_secret) or "치사해요 ㅎㅎ" }, "small")
				elseif validName(nm) then
					sig.fact = { k = "name", v = nm }
				end
			elseif ask == "job" and not sig.q and not sig.fact then
				for _, group in JOBS do
					if anyOf(s, group) then
						sig.fact = { k = "job", v = group[1] }
						break
					end
				end
				if not sig.fact and (has(s, "비밀") or has(s, "몰라")) then
					return part({ pk(B.ans_secret) or "치사해요 ㅎㅎ" }, "small")
				end
			elseif ask == "food" and not sig.q and not sig.fact then
				local item = sig.slots.item
				local w = item and M.FOODS[item] and M.FOODS[item].name or nounOf(s)
				if w then
					sig.fact = { k = "like", v = w }
				end
			elseif ask == "mood" and not sig.q and not sig.feel then
				if sig.sent > 0 then
					local p = part({ pk(B.ans_mood_good) or "다행이다" }, "small")
					p.d.cl = 0.6
					return p
				elseif sig.sent < 0 or has(s, "힘들") then
					sig.feel = "stressed"
				end
			elseif ask == "often" then
				if has(s, "처음") or sig.intent == "no" then
					return part({ pk(B.ans_often_no) or "처음이구나" }, "small")
				elseif has(s, "자주") or has(s, "가끔") or sig.intent == "yes" then
					local p = part({ pk(B.ans_often_yes) or "어쩐지" }, "small")
					p.d.cl = 0.6
					return p
				end
			elseif ask == "date" then
				if sig.sent > 0 or sig.intent == "yes" then
					local p = part({}, "small")
					p.invite = "meal"
					return p
				end
			elseif string.sub(ask, 1, 6) == "topic:" then
				local key = string.sub(ask, 7)
				local T = TOPICS[key]
				if T and not sig.q then
					local p
					if sig.sent > 0 or sig.intent == "yes" then
						p = part({ pk(B.agree) or "그쵸!" }, "small")
						p.d.aff, p.d.cl = 1, 1
						p.face = "laugh"
					elseif sig.sent < 0 or sig.intent == "no" then
						p = part({ pk(if t.pride > 0.65 then B.disagree_proud else B.disagree_warm) or "그래요?" }, "small")
						p.d.cl = 0.4
					else
						p = part({ pk(B.ans_generic) or "그렇구나" }, "small")
						p.d.cl = 0.6
					end
					tc.topic = key
					return p
				end
			end
		end
		-- context words
		if sig.ctx == "you_too" then
			local last = tc.lastKind
			if last == "feel" then
				local key = if mood == "good" or mood == "lover" then "good" elseif (env.tod == "night" or env.tod == "late") then "tired" else "meh"
				return part({ pk(B.you_too_feel[key]) or "저는 괜찮아요" }, "small")
			elseif last == "fact:name" then
				return rulePart({ t = "이름이 뭐예요?", intent = "name", slots = {}, polite = sig.polite })
			elseif last == "fact:job" then
				return rulePart({ t = "무슨 일 해요?", intent = "job", slots = {}, polite = sig.polite })
			elseif last == "fact:age" then
				return rulePart({ t = "몇 살이에요?", intent = "age", slots = {}, polite = sig.polite })
			elseif last == "fact:like" then
				return rulePart({ t = "뭐 좋아해요?", intent = "like_q", slots = {}, polite = sig.polite })
			elseif tc.topic and TOPICS[tc.topic] then
				sig.topic = tc.topic
				sig.q = true
			else
				return rulePart({ t = "요즘 어때요?", intent = "how", slots = {}, polite = sig.polite })
			end
		elseif sig.ctx == "why" then
			local p = part({ tc.why or pk(B.why_generic) or "그냥요 ㅎㅎ" }, "small")
			tc.why = nil
			p.face = "think"
			p.emote = "think"
			return p
		elseif sig.ctx == "really" then
			local p = part({ pk(B.really) or "진짜요!" }, "small")
			p.face = "laugh"
			return p
		elseif sig.ctx == "what" and tc.lastLine then
			vars.last = tc.lastLine
			return part({ pk(B.what_again) or tc.lastLine }, "small")
		elseif sig.ctx == "laugh" then
			local warm = t.humor > 0.4 or mood == "good" or mood == "lover"
			local p = part({ pk(if warm then B.laugh else B.laugh_cold) or "ㅋㅋ" }, "small")
			p.face = if warm then "laugh" else "wary"
			if warm then
				p.d.cl = 0.4
			end
			return p
		elseif sig.ctx == "me_too" and not sig.fact and not sig.feel then
			if tc.lastKind == "topic" or tc.lastKind == "npc" then
				local p = part({ pk(B.me_too) or "통했다!" }, "small")
				p.d.aff, p.d.cl = 1, 1.2
				p.face = "laugh"
				p.emote = "cheer"
				return p
			end
		elseif sig.ctx == "ok" and not sig.topic and not sig.fact then
			local p = part({ pk(B.ok) or "네 ㅎㅎ" }, "small")
			-- they keep it going with their own topic now and then
			if t.chatty > 0.45 and chance(r, 0.6) then
				p.shift = true
			end
			return p
		end
		-- a fact about the player
		local f = sig.fact
		if f then
			local p = part({}, "small")
			if f.k == "name" then
				local old = pf.nm
				pf.nm = f.v
				vars.pname = f.v
				vars.pnameI = withI(f.v)
				vars.pname2 = f.v
				table.insert(p.lines, pk(if old == f.v then B.fact_name_old else B.fact_name) or (f.v .. "!"))
				if old ~= f.v then
					p.d.cl, p.d.tr = 1.5, 1
				end
				p.face = "smile"
				tc.lastKind = "fact:name"
			elseif f.k == "job" then
				pf.job = f.v
				vars.pjob = f.v
				vars.pjobI = withI(f.v)
				local same = c.job and has(c.job, f.v)
				table.insert(p.lines, pk(if same then B.fact_job_same else B.fact_job) or "그렇구나")
				p.d.cl = if same then 2 else 1
				tc.lastKind = "fact:job"
			elseif f.k == "age" then
				pf.age = f.v
				vars.page = f.v
				local my = c.age or 25
				table.insert(p.lines, pk(if f.v == my then B.fact_age_same elseif f.v < my then B.fact_age_young else B.fact_age_old) or "그렇구나")
				p.d.cl = 0.8
				tc.lastKind = "fact:age"
			elseif f.k == "from" then
				pf.from = f.v
				vars.pfrom = f.v
				table.insert(p.lines, pk(B.fact_from) or "그렇구나")
				p.d.cl = 0.8
				tc.lastKind = "fact:from"
			elseif f.k == "like" then
				remember(pf.likes, f.v, 6)
				vars.plike = f.v
				local tp = topicOf(string.lower(f.v))
				local item = sig.slots.item
				local fp = item and M.foodPref(c, item)
				local same = (tp and stanceOf(c, arch, tp) == "love") or fp == "love" or fp == "like"
				local hate = (tp and stanceOf(c, arch, tp) == "hate") or fp == "dislike"
				table.insert(p.lines, pk(if same then B.fact_like_same elseif hate then B.fact_like_hate else B.fact_like) or "그렇구나")
				if same then
					p.d.aff, p.d.cl = 1.5, 1.5
					p.face = "laugh"
					p.emote = "cheer"
				else
					p.d.cl = 0.8
				end
				tc.lastKind = "fact:like"
				if tp then
					tc.topic = tp
				end
			elseif f.k == "hate" then
				remember(pf.hates, f.v, 4)
				vars.phate = f.v
				table.insert(p.lines, pk(B.fact_hate) or "그렇구나")
				p.d.cl = 0.5
				tc.lastKind = "fact:hate"
			elseif f.k == "did" then
				pf.did = { x = f.v, t = now }
				vars.pdid = f.v
				table.insert(p.lines, pk(B.fact_did) or "고생했네요")
				p.d.cl = 0.8
				tc.lastKind = "fact:did"
			end
			return p
		end
		-- the player's feeling
		if sig.feel then
			local k = sig.feel
			pf.feel = { x = k, t = now }
			local warm = (t.warm >= 0.5 or mood == "good" or mood == "lover") and not t.hostile
			local bank = B.feel[k]
			local p = part({ pk(if warm then bank.warm else bank.cool) or "그렇구나" }, "small")
			if warm then
				p.d.aff, p.d.tr, p.d.cl = 1, 1, 1.2
				p.face = if k == "happy" then "laugh" elseif k == "hot" or k == "cold" or k == "hungry" or k == "full" or k == "bored" then "smile" else "sad"
				p.emote = if k == "happy" then "cheer" else "nod"
			else
				p.d.cl = 0.3
				p.face = "neutral"
			end
			-- bored + close: "then let's hang out"
			if k == "bored" and warm and aff >= 20 then
				p.act = "meet_menu"
			end
			tc.lastKind = "feel"
			return p
		end
		-- shop talk (a clerk at work, or one off duty)
		if sig.shop or (sig.intent == "small" and orderItem(s) and (arch == "clerk" or arch == "parttimer")) then
			local working, shop = isWorking(c, env)
			if shop then
				local key = sig.shop or "order"
				if working then
					vars.order = orderItem(s) or "그거"
					local S = SHOP[shop]
					local p = part({ pk(S[key]) or pk(S.greet) or "네~" }, "small")
					p.face = "smile"
					p.emote = "nod"
					p.d.cl = 0.4
					tc.lastKind = "shop"
					return p
				end
				local p = part({ pk(SHOP.off) or "지금은 퇴근했어요" }, "small")
				p.face = "smile"
				return p
			end
		end
		if sig.third then
			local p = part({ pk(B.third_who) or "누구요?" }, "small")
			p.emote = "think"
			return p
		end
		-- a topic
		if sig.topic then
			local key = sig.topic
			local T = TOPICS[key]
			local stance = stanceOf(c, arch, key)
			vars.label = T.label
			local p = part({}, "small")
			tc.lastKind = "topic"
			if stance == "hate" then
				local again = tc.hated == key or hateRecent(rec, key, now)
				table.insert(p.lines, pk(if again then STANCE.hate_again else STANCE.hate) or "…")
				p.d.an = if again then 6 else 2
				p.d.aff = if again then -1 else 0
				p.face = if again then "annoyed" else "wary"
				p.emote = "shrug"
				tc.hated = key
				rec.cd["hate:" .. key] = now
				tc.topic = nil
				if again and rec.an + 6 >= 45 then
					p.act = "leave"
				end
				return p
			end
			tc.topic = key
			if sig.q and sig.wh == "where" and T.where then
				table.insert(p.lines, pk(T.where) or "")
				p.emote = "point"
			elseif sig.q and sig.wh == "why" and T.why then
				table.insert(p.lines, pk(T.why) or "")
			elseif sig.likeQ and stance ~= "love" then
				table.insert(p.lines, pk(STANCE.meh) or "")
				local op = pk(T.ops)
				if op and chance(r, 0.6) then
					table.insert(p.lines, op)
				end
				p.d.cl = 0.5
			else
				if stance == "love" then
					table.insert(p.lines, pk(if sig.likeQ then STANCE.love_yes else STANCE.love) or "")
					p.d.aff, p.d.cl = 1.5, 1.2
					p.face = "laugh"
					p.emote = "cheer"
				else
					p.d.cl = 0.6
					p.face = "smile"
				end
				local op = pk(T.ops)
				if op then
					if #p.lines > 0 and chance(r, 0.5) then
						p.lines[#p.lines] ..= " " .. op
					else
						table.insert(p.lines, op)
					end
				end
				tc.why = pk(T.why)
				-- ask it back (keeps them talking)
				if sig.likeQ then
					local a = pk(B.your_turn)
					if a then
						table.insert(p.lines, a)
						p.askTopic = key
					end
				elseif (stance == "love" or chance(r, t.chatty * 0.5)) and T.ask and tc.ask == nil then
					local a = pk(T.ask)
					if a then
						table.insert(p.lines, a)
						p.askTopic = key
					end
				end
			end
			return p
		end
		-- "where" about places in general
		if sig.q and sig.wh == "where" and sig.intent == "small" then
			if has(s, "여기") then
				return part({ pk(B.situation_where) or vars.area }, "small")
			end
			local p = part({ pk(B.where_generic) or "음…" }, "small")
			p.emote = "think"
			return p
		end
		if sig.wow then
			local p = part({ pk(B.agree) or "그쵸!" }, "small")
			p.d.cl = 0.6
			p.face = "laugh"
			return p
		end
		if sig.swear then
			local rough = arch == "punk" or arch == "thug" or arch == "drunk" or arch == "fool" or arch == "hothead"
			local p = part({ pk(if rough then B.swear_laugh else B.swear_frown) or "…" }, "small")
			if not rough then
				p.d.an, p.d.aff = 3, -0.5
				p.face = "wary"
			else
				p.face = "smug"
			end
			return p
		end
		return nil
	end

	-- choose: the strongest rule clause, the own answers, a greeting kept short
	local ruleSig, ruleScore = nil, 0
	for _, sig in sigs do
		local sc = RULE_STRONG[sig.intent] or 0
		if sig.intent ~= "small" and sig.intent ~= "greet" and sc > ruleScore then
			ruleSig, ruleScore = sig, sc
		end
		if sig.intent == "greet" then
			greetOnly = sig
		end
	end
	-- hostile: only that (the composer decides the fight / flight / report)
	if ruleSig and ruleScore >= 10 then
		local p = rulePart(ruleSig)
		return Talk.finish(c, rec, env, tc, { p }, mood, reg, st, r)
	end
	local greeted = false
	for _, sig in sigs do
		if used >= 2 then
			break
		end
		if sig == ruleSig then
			table.insert(parts, rulePart(sig))
			used += 1
		elseif sig.intent == "greet" and #sigs > 1 then
			-- a short hello in front of the rest
			if not greeted then
				greeted = true
				local g = M.pick(M.bank(arch, "greet", mood, reg), rec, now, r)
				if g then
					local p = part({ M.fill(g, vars) }, "greet")
					p.d.aff = if FRIENDLY[mood] then 0.6 else 0
					p.voice = true
					table.insert(parts, p)
				end
			end
		elseif sig.intent == "small" or (RULE_STRONG[sig.intent] or 0) <= 1 or sig.feel or sig.fact or sig.topic or sig.ctx then
			local p = ownPart(sig)
			if p then
				table.insert(parts, p)
				used += 1
				if p.act == "leave" or p.act == "flee" then
					break
				end
			end
		elseif sig.intent == "doing" and FRIENDLY[mood] and statusText(c, env) and chance(r, 0.6) then
			vars.status = statusText(c, env)
			local p = part({ pk(B.doing_now) or "" }, "doing")
			p.face = "smile"
			p.d.cl = 0.6
			table.insert(parts, p)
			used += 1
		elseif sig.intent ~= "greet" then
			table.insert(parts, rulePart(sig))
			used += 1
		end
	end
	if #parts == 0 or (#parts == 1 and parts[1].intent == "greet" and #sigs > 1) then
		-- nothing understood: an echo of the main word, a question back, or their own topic
		local sig = sigs[#sigs]
		local p = nil
		if FRIENDLY[mood] then
			local w = nounOf(sig.s)
			if w and chance(r, 0.65) then
				vars.w = w
				p = part({ pk(if sig.q then B.echo_q else B.echo) or w }, "small")
				p.face = "think"
				p.emote = "think"
				p.d.cl = 0.3
				if not sig.q and chance(r, 0.5) then
					p.shift = true
				end
			end
		end
		if not p then
			-- the composer's small talk (archetype lines) as before
			p = rulePart({ t = sig.t, intent = if greetOnly and #sigs == 1 then "greet" else "small", slots = sig.slots, polite = sig.polite })
			if FRIENDLY[mood] and chance(r, 0.35) then
				p.shift = true
			end
		end
		table.insert(parts, p)
	end
	return Talk.finish(c, rec, env, tc, parts, mood, reg, st, r)
end

-- parts -> one out (the composer's shape)
function Talk.finish(c: any, rec: any, env: any, tc: any, parts: { any }, mood: string, reg: string, st: string, r: () -> number): any
	local now = env.now or os.time()
	local t = M.traits(c)
	local arch = t.arch
	local pf = pfOf(rec)
	local vars = { you = env.you or "친구", pname = pf.nm or env.you or "친구", me = c.name or "저" }
	reg = M.register(c, rec, env.aff or 0)
	local out = { lines = {}, d = D(), mood = mood, stage = st, reg = reg }
	local main = nil
	for _, p in parts do
		for k, v in p.d do
			if type(v) == "number" then
				addD(out.d, k, v)
			end
		end
		if p.rule then
			-- the composer already voiced its lines
			for _, l in p.lines do
				table.insert(out.lines, l)
			end
		else
			for _, l in p.lines do
				if l and l ~= "" then
					local v = M.voice(l, arch, r, p.face == "sad" or p.face == "angry" or p.face == "scared" or p.face == "annoyed")
					if c.speech == "busan" then
						v = M.dialect(v, reg, r)
					end
					table.insert(out.lines, v)
				end
			end
		end
		if not main or (p.intent ~= "greet" and main.intent == "greet") or (p.act and not main.act) then
			main = p
		end
		out.act = out.act or p.act
		out.ask = p.ask or out.ask
		out.invite = out.invite or p.invite
		if p.reveal then
			out.reveal = out.reveal or {}
			for k, v in p.reveal do
				out.reveal[k] = v
			end
		end
		if p.mem and (not out.mem or p.mem.k ~= "talk") then
			out.mem = p.mem
		end
	end
	main = main or parts[1]
	out.face = main.face or (if mood == "good" then "smile" else "neutral")
	out.emote = main.emote
	out.intent = main.intent or "small"
	out.mem = out.mem or { k = "talk", x = out.intent }
	-- caps (one message never swings feelings like a gift does)
	out.d.aff = math.clamp(out.d.aff or 0, -10, 4)
	out.d.cl = math.clamp(out.d.cl or 0, -20, 3)

	local friendly = FRIENDLY[mood] == true and not out.act and (out.d.an or 0) <= 1
	local extra = nil
	-- the first exchange: what they remember about you
	if env.first and friendly and #out.lines < 3 and r() < 0.75 then
		extra = tc.recall
		if extra then
			local v = M.voice(extra, arch, r, false)
			if c.speech == "busan" then
				v = M.dialect(v, reg, r)
			end
			table.insert(out.lines, 1, v)
		end
	end
	-- friends call you by name (once in a while)
	if friendly and pf.nm and (st == "friend" or st == "bestie" or st == "lover" or st == "close") and r() < 0.3 and #out.lines > 0 then
		local nmEntry = B.name_call
		local call = M.fill((nmEntry[reg] or nmEntry.p)[1], vars)
		if not has(out.lines[1], pf.nm) then
			out.lines[1] = call .. " " .. out.lines[1]
		end
	end
	-- their own turn: a topic of theirs, the situation, the 반말 offer
	local turn = nil
	local wantShift = false
	for _, p in parts do
		if p.shift then
			wantShift = true
		end
		if p.askTopic then
			tc.ask = "topic:" .. p.askTopic
			tc.askN = tc.n
		end
	end
	if friendly and #out.lines < 3 and not out.ask then
		if not rec.bm and reg == "p" and (env.aff or 0) >= 40 and rec.cl >= 25 and not ((arch == "rich" or arch == "police") and (env.aff or 0) < 60) and now - (rec.cd.bmOffer or 0) > 3600 and r() < 0.5 then
			rec.cd.bmOffer = now
			turn = M.fill((B.banmal_offer.p)[1], vars)
			tc.ask = "banmal"
			tc.askN = tc.n
		elseif wantShift then
			turn = shiftLine(c, rec, env, reg, tc, r)
		elseif r() < 0.22 then
			turn = situationLine(c, rec, env, reg, vars, r)
		end
	end
	if turn then
		local v = M.voice(turn, arch, r, false)
		if c.speech == "busan" then
			v = M.dialect(v, reg, r)
		end
		table.insert(out.lines, v)
	end
	-- the composer's question back (its chips) is an ask too
	if out.ask and out.ask.kind then
		tc.ask = out.ask.kind
		tc.askN = tc.n
	end
	while #out.lines > 3 do
		table.remove(out.lines, 1)
	end
	if #out.lines == 0 then
		out.lines = { "…" }
	end
	tc.lastLine = out.lines[#out.lines]
	if tc.lastKind == nil or (out.intent ~= "small") then
		tc.lastKind = "npc"
	end
	return out
end

-- an NPC that walks up to the player: what they remember first, else their own topic
function Talk.opener(c: any, rec: any, env: any, tc: any): any?
	if not M then
		return nil
	end
	local r = env.rnd or math.random
	local aff = env.aff or 0
	local mood = M.mood(c, rec, aff, env)
	if not FRIENDLY[mood] or (rec.tk or 0) == 0 then
		return nil
	end
	local reg = M.register(c, rec, aff)
	local pf = pfOf(rec)
	local vars = { you = env.you or "친구", pname = pf.nm or env.you or "친구", me = c.name or "저" }
	tc = tc or {}
	tc.n = tc.n or 0
	local line = recallLine(rec, env, reg, vars, r)
	if not line then
		line = shiftLine(c, rec, env, reg, tc, r)
	end
	if not line then
		return nil
	end
	local arch = M.traits(c).arch
	local hello = if pf.nm then M.fill(((B.name_call[reg] or B.name_call.p))[1], vars) else (if reg == "c" then "어! 왔어?" else "어! 안녕하세요!")
	local lines = { hello, line }
	for i, l in lines do
		local v = M.voice(l, arch, r, false)
		if c.speech == "busan" then
			v = M.dialect(v, reg, r)
		end
		lines[i] = v
	end
	tc.lastLine = lines[#lines]
	return { lines = lines, d = { aff = 0, tr = 0, an = 0, fe = 0, cl = 0.5 }, face = "smile", emote = "wave", intent = "greet", mood = mood, stage = M.stage(rec, aff), reg = reg, mem = { k = "talk", x = "greet" } }
end

Talk.TOPICS = TOPICS
Talk.B = B

return Talk
