-- GwangalliKaraokeShared/Songs: the 노래책 (song book) of GwangalliKaraokePlus. Pure data.
--
-- CONTENT RULE: every song here is either
--   * an ORIGINAL song written for this game (fictional artists, original lyrics; the melody is
--     composed by Chart.luau from the song's chords and seed), or
--   * public domain: traditional Korean folk songs (민요, author unknown / centuries old) and
--     public-domain melodies (Twinkle / Happy Birthday / Ode to Joy / Frère Jacques / London Bridge /
--     Jingle Bells) with ORIGINAL Korean words (the standard 4-line 생일 축하 text excepted).
--   No real copyrighted lyrics or melodies. The 민요 melodies are written out note by note below
--   (traditional tunes as sung today; check them by ear before a public event and fix a token if a
--   phrase sounds off).
--
-- SONG FIELDS
--   id ("s01"), title, artist, genre (발라드 / 댄스 / 트로트 / 힙합 / 락 / 동요 / 민요 / OST), style (finer
--   label + the band preset: 발라드 인디 어쿠스틱 블루스 R&B 팝 시티팝 EDM 댄스 트로트 힙합 록 응원가 동요
--   축하곡 민요 OST 애니), bpm, key ("C", "Am", "G" ...), meter (4 = 4/4, 3 = 3/4), part ("M" 남 / "F" 여 /
--   "MF" 혼성 / "D" 듀엣), credit (작사 · 작곡), origin (OST / folk source), tags ("new", "duet", "event",
--   "season", "pd"), ch (first chorus line for the default form), form (explicit order of line indices;
--   "간주" = an instrumental break), intro (bars), soundId (optional licensed backing track, "" = the
--   built-in band; Config.SongAudio[id] overrides), soundOffset (s of the track at song time 0).
--   lines: a string = an original line (melody composed; "{M}" / "{F}" / "{A}" prefix = the duet part),
--          or { t = text, m = melody tokens, p = part } = a line with a written-out melody.
--   MELODY TOKENS (one per sung syllable, spaces in the text are skipped): "G4" (1 beat), "G4:0.5",
--     "D4:1.5+E4:0.5" (one syllable over several notes), "r:2" (rest beats). Lines follow each other
--     without a gap; the first token of a line may be a pickup.
-- Numbers: TJ-style 5-digit 곡번호 = 38000 + 131 * (catalog index); s01..s10 keep the numbers of the
-- legacy GwangalliVenuesShared catalog (38131 ... 39310) and their titles / artists / lyrics verbatim.

local Songs = {}

local ORIG = "작사 · 작곡 광안 노래방 오리지널"

Songs.LIST = {
	-------------------------------------------------------------------------------------------------
	-- legacy catalog (GwangalliVenuesShared s01..s10, kept verbatim)
	-------------------------------------------------------------------------------------------------
	{
		id = "s01", title = "광안대교 불빛 아래", artist = "파도청년단", genre = "발라드", style = "발라드", bpm = 84, key = "C", part = "M", credit = ORIG, seed = 11,
		lines = { "다리 위에 불이 켜지면", "너의 이름 불러 볼게", "파도 소리 박자 맞춰", "천천히 걸어가자", "모래 위에 적은 약속", "밀물에도 남아 있길", "광안리의 밤하늘에", "별 하나를 걸어 둘게" },
	},
	{
		id = "s02", title = "민락동 치킨송", artist = "바삭즈", genre = "댄스", style = "댄스", bpm = 120, key = "C", part = "MF", credit = ORIG, seed = 23,
		lines = { "퇴근길엔 치킨 한 마리", "바닷바람 맞으면서", "양념 반에 후라이드 반", "오늘 하루 수고했어", "콜라 뚜껑 탁 따고서", "다 같이 건배 하나 둘", "민락동의 밤은 길다", "바삭바삭 춤을 춰" },
	},
	{
		id = "s03", title = "2호선 막차", artist = "금련산 밴드", genre = "락", style = "록", bpm = 132, key = "E", part = "M", credit = ORIG, seed = 37,
		lines = { "막차는 벌써 떠났고", "택시는 잡히지 않아", "그래도 웃고 있는 건", "네가 옆에 있어서야", "가로등 하나 둘 셋", "발걸음은 가벼워", "새벽 공기 마시면서", "우리 집까지 달려" },
	},
	{
		id = "s04", title = "갈매기 트로트", artist = "김부산", genre = "트로트", style = "트로트", bpm = 104, key = "Am", part = "M", credit = ORIG, seed = 41,
		lines = { "끼룩끼룩 갈매기야", "어디로 날아가니", "광안리 앞바다에", "내 마음도 데려가렴", "떴다 떴다 저 구름아", "소식 좀 전해 주렴", "기다리는 그 사람도", "이 노래를 듣겠지" },
	},
	{
		id = "s05", title = "썸머 모래성", artist = "오션걸즈", genre = "댄스", style = "팝", bpm = 112, key = "G", part = "F", credit = ORIG, seed = 53,
		lines = { "하얀 파도 넘실넘실", "모래성을 쌓아 볼까", "선크림을 듬뿍 바르고", "너에게로 달려가", "튜브 타고 둥실둥실", "햇살이 눈부신 날", "이 여름이 끝나도", "우리 꼭 다시 만나" },
	},
	{
		id = "s06", title = "PC방 영웅", artist = "레벨업", genre = "힙합", style = "힙합", bpm = 96, key = "Am", part = "M", credit = ORIG, seed = 67,
		lines = { "로그인 하면 시작돼", "오늘도 랭크 올려", "라면 하나 시켜 놓고", "키보드 위 손이 춤춰", "한 판만 더 외치다가", "벌써 해가 떴네", "엄마 전화 오기 전에", "마지막 판 승리해" },
	},
	{
		id = "s07", title = "새벽 편의점", artist = "도시소년", genre = "발라드", style = "인디", bpm = 88, key = "D", part = "M", credit = ORIG, seed = 71,
		lines = { "불 켜진 편의점 앞에", "삼각김밥 하나 들고", "별일 없는 하루였지만", "괜찮다고 말해 줘", "유리문에 비친 얼굴", "조금은 피곤해 보여", "내일은 더 나을 거야", "바나나우유 건배" },
	},
	{
		id = "s08", title = "득근득근", artist = "헬스보이즈", genre = "댄스", style = "EDM", bpm = 128, key = "Am", part = "M", credit = ORIG, seed = 83,
		lines = { "하나 둘 셋 넷 스쿼트", "땀방울이 반짝반짝", "거울 속의 나에게", "오늘도 파이팅 외쳐", "벤치 위에 누워서", "숨을 크게 들이쉬고", "포기하지 않을 거야", "득근 득근 득근해" },
	},
	{
		id = "s09", title = "해운대 말고 광안리", artist = "수영구 청년회", genre = "댄스", style = "시티팝", bpm = 100, key = "F", part = "MF", credit = ORIG, seed = 97,
		lines = { "주말에는 어디 갈까", "고민할 필요 없잖아", "지하철 타고 금련산역", "걸어가면 바다야", "드론 쇼가 시작되면", "하늘 가득 반짝여", "사진 한 장 남겨 두고", "다음 주에 또 오자" },
	},
	{
		id = "s10", title = "생일 축하해 친구야", artist = "노래방 오리지널", genre = "동요", style = "축하곡", bpm = 108, key = "C", part = "MF", credit = ORIG, seed = 101,
		lines = { "오늘은 너의 날이야", "촛불 하나 소원 하나", "케이크 위에 별을 켜고", "다 같이 박수 짝짝", "일 년 동안 고마웠어", "앞으로도 잘 부탁해", "웃음 가득 행복 가득", "생일 축하해 친구야" },
	},

	-------------------------------------------------------------------------------------------------
	-- original songs (광안 노래방 오리지널)
	-------------------------------------------------------------------------------------------------
	{
		id = "s11", title = "수변공원 노을", artist = "바닷마을 밴드", genre = "발라드", style = "발라드", bpm = 76, key = "D", part = "F", credit = ORIG, seed = 113,
		lines = { "수변공원 계단 위에", "나란히 앉은 우리 둘", "붉게 물든 바다 위로", "하루가 천천히 저물어", "노을아 조금만 더 머물러 줘", "이 순간을 기억할 수 있게", "파도가 지워도 남아 있을", "우리의 작은 약속", "바람이 차가워지면", "네 어깨를 감싸 줄게", "별이 하나 둘 켜지면", "다시 노래할게" },
	},
	{
		id = "s12", title = "드론쇼 하늘 위에", artist = "네온캣", genre = "댄스", style = "댄스", bpm = 124, key = "C", part = "F", credit = ORIG, seed = 127, tags = { "new" },
		lines = { "토요일 밤 여덟 시", "광안리로 모여 봐", "하늘 위에 불이 켜져", "수천 개의 별이 떠", "드론쇼 하늘 위에", "너의 이름 그려 줄게", "반짝반짝 춤을 춰", "오늘 밤은 우리 거야", "휴대폰을 높이 들어", "이 순간을 담아 봐", "하트 모양 불빛 아래", "너에게 고백할래" },
	},
	{
		id = "s13", title = "국밥 한 그릇의 위로", artist = "서면 블루스", genre = "발라드", style = "블루스", bpm = 82, key = "A", part = "M", credit = ORIG, seed = 131,
		lines = { "비 오는 서면 골목길", "김이 나는 국밥집", "뚝배기에 밥 말아서", "한 숟갈 크게 떠", "괜찮아 다 괜찮아", "뜨끈한 국물이 말해", "오늘 하루 고생했어", "내일은 더 웃을 거야" },
	},
	{
		id = "s14", title = "남천동 벚꽃길", artist = "봄날소녀", genre = "댄스", style = "팝", bpm = 108, key = "F", part = "F", credit = ORIG, seed = 139, tags = { "new" },
		lines = { "사월의 남천동엔", "분홍빛 눈이 내려", "너와 걷는 이 길이", "영화 같은 장면이야", "벚꽃길 따라 걸어요", "꽃잎이 춤을 춰요", "바람 불면 살랑살랑", "내 마음도 살랑살랑", "사진 한 장 찍어 줄래", "꽃잎 같은 너의 미소", "내년 봄도 이 길에서", "다시 만나자 우리" },
	},
	{
		id = "s15", title = "해운대에서 광안리까지", artist = "파도청년단", genre = "락", style = "록", bpm = 140, key = "E", part = "M", credit = ORIG, seed = 149,
		lines = { "해운대 백사장 지나", "동백섬을 돌아서", "페달 밟아 달려가", "바닷바람 가르며", "달려 달려 광안리까지", "멈추지 마 끝까지", "숨이 차도 웃음이 나", "우린 지금 청춘이야", "신호등이 바뀌면", "다시 한번 출발해", "저 다리가 보일 때까지", "소리 질러 예" },
	},
	{
		id = "s16", title = "밤바다 버스킹", artist = "기타소년", genre = "발라드", style = "어쿠스틱", bpm = 92, key = "G", part = "M", credit = ORIG, seed = 151,
		lines = { "낡은 기타 하나 메고", "모래 위에 앉았어", "지나가는 사람들", "잠시 멈춰 들어 줘", "밤바다 위에 띄운 노래", "파도에 실어 보낼게", "누군가의 마음에", "작은 불빛이 되길" },
	},
	{
		id = "s17", title = "퇴근길 막차 버스", artist = "도시소년", genre = "발라드", style = "인디", bpm = 96, key = "D", part = "M", credit = ORIG, seed = 157,
		lines = { "창밖에 흐르는 불빛", "꾸벅꾸벅 졸다가", "내릴 곳을 지나쳐", "웃음이 나와 버렸어", "퇴근길 막차 버스", "오늘도 수고했어", "이어폰 속 노래가", "나를 토닥여 주네" },
	},
	{
		id = "s18", title = "첫 월급", artist = "레벨업", genre = "힙합", style = "힙합", bpm = 94, key = "Am", part = "M", credit = ORIG, seed = 163,
		lines = { "통장에 찍힌 숫자", "눈을 몇 번 비볐어", "한 달 동안 버틴 나", "오늘만큼은 플렉스", "첫 월급 받은 날", "엄마 선물 먼저 사", "남은 돈은 치킨 한 마리", "이게 바로 행복이지", "출근길 지하철 안", "졸린 눈 비비면서", "꿈을 향해 한 걸음씩", "내일도 달려 볼게" },
	},
	{
		id = "s19", title = "광안대교 드라이브", artist = "시티라이트", genre = "댄스", style = "시티팝", bpm = 112, key = "F", part = "MF", credit = ORIG, seed = 167, tags = { "new", "duet" },
		lines = { "{M}창문을 살짝 내리고", "{M}라디오를 켜 볼까", "{F}반짝이는 다리 위를", "{F}천천히 달려가", "{A}광안대교 드라이브", "{A}밤공기가 달콤해", "{A}너와 나의 플레이리스트", "{A}끝나지 않았으면 해", "{F}신호 없는 이 길 위에", "{F}우리만 남은 것 같아", "{M}바다 위로 떠오른 달", "{M}우릴 따라오네" },
	},
	{
		id = "s20", title = "엄마의 된장찌개", artist = "김부산", genre = "트로트", style = "트로트", bpm = 100, key = "Am", part = "M", credit = ORIG, seed = 173,
		lines = { "객지 생활 십 년째", "혼자 먹는 저녁밥", "문득 생각나는 그 맛", "보글보글 그 냄새", "엄마의 된장찌개", "그 맛을 잊을 수 없네", "이번 명절 내려가면", "한 그릇만 끓여 주오" },
	},
	{
		id = "s21", title = "오늘도 출근", artist = "직장인 밴드", genre = "락", style = "록", bpm = 128, key = "D", part = "M", credit = ORIG, seed = 179,
		lines = { "알람 소리 다섯 번째", "겨우 눈을 떴어", "커피 한 잔 들이켜고", "지옥철에 몸을 실어", "오늘도 출근 출근", "월급날만 기다려", "그래도 퇴근하면", "노래방에 가자" },
	},
	{
		id = "s22", title = "썸 타는 중", artist = "오션걸즈", genre = "댄스", style = "팝", bpm = 116, key = "G", part = "F", credit = ORIG, seed = 181, tags = { "new" },
		lines = { "읽고 답이 없는 너", "일 분이 한 시간 같아", "하트 하나 보낼까", "지울까 말까 고민해", "썸 타는 중 두근두근", "너도 나랑 같은 맘일까", "오늘 밤엔 말해 줄래", "우리 무슨 사이야", "바닷가를 걷다가", "손끝이 닿았을 때", "너의 볼도 빨개진 걸", "나는 봤어" },
	},
	{
		id = "s23", title = "파도 위의 고백", artist = "윤바다", genre = "발라드", style = "발라드", bpm = 72, key = "D", part = "M", credit = ORIG, seed = 191,
		lines = { "하얀 파도 밀려와", "발끝을 적실 때", "오래 숨긴 그 말을", "이제는 꺼내 볼게", "사랑해 파도 소리에", "묻히지 않게 크게", "네가 웃어 준다면", "나는 바다가 될게" },
	},
	{
		id = "s24", title = "깡통시장 야시장", artist = "깡통 시스터즈", genre = "트로트", style = "트로트", bpm = 118, key = "Am", part = "F", credit = ORIG, seed = 193,
		lines = { "해가 지면 불이 켜져", "깡통시장 야시장", "어묵 하나 떡볶이 하나", "손님들이 북적북적", "오세요 오세요", "맛있는 야시장", "사장님 인심 좋아", "한 개 더 덤이요" },
	},
	{
		id = "s25", title = "불꽃축제", artist = "네온캣", genre = "댄스", style = "EDM", bpm = 128, key = "Am", part = "F", credit = ORIG, seed = 197, tags = { "new" },
		lines = { "십일월의 밤바다", "사람들이 모여들어", "카운트다운 시작해", "셋 둘 하나 지금이야", "펑펑 터지는 불꽃", "내 마음도 같이 터져", "하늘 가득 너의 이름", "오늘 밤은 축제야", "손을 높이 흔들어", "소리 질러 다 같이", "광안리가 빛나는 밤", "끝나지 않을 거야" },
	},
	{
		id = "s26", title = "편의점 알바", artist = "레벨업", genre = "힙합", style = "힙합", bpm = 90, key = "Am", part = "M", credit = ORIG, seed = 199,
		lines = { "새벽 두 시 카운터", "삑삑 바코드 소리", "컵라면 물 붓는 손님", "어서 오세요 안녕히", "편의점 알바 인생", "그래도 꿈은 크게", "유통기한 지난 삼각김밥", "오늘 저녁 메뉴야" },
	},
	{
		id = "s27", title = "새벽 세 시 택시", artist = "금련산 밴드", genre = "락", style = "록", bpm = 136, key = "E", part = "M", credit = ORIG, seed = 211,
		lines = { "마지막 잔을 비우고", "거리로 나왔어", "손을 흔들어도", "빈 차는 오지 않아", "새벽 세 시 택시", "제발 나를 태워 줘", "집에 가는 그 길이", "오늘따라 멀어" },
	},
	{
		id = "s28", title = "바다가 보이는 원룸", artist = "김바다", genre = "발라드", style = "발라드", bpm = 80, key = "C", part = "M", credit = ORIG, seed = 223,
		lines = { "작은 창문 너머로", "바다가 보이는 방", "월세는 좀 비싸도", "매일 아침 행복해", "바다가 보이는 원룸", "나만의 작은 우주", "언젠가 너를 데려와", "이 풍경 보여 줄게" },
	},
	{
		id = "s29", title = "우리 동네 PC방", artist = "레벨업", genre = "댄스", style = "댄스", bpm = 126, key = "Am", part = "M", credit = ORIG, seed = 227,
		lines = { "학교 끝나면 모여", "우리 동네 PC방", "자리 맡아 놨어", "빨리 와 친구야", "한 판만 더 한 판만", "이기면 끝낼게", "라면 냄새 솔솔", "오늘도 레벨업" },
	},
	{
		id = "s30", title = "황령산 별밤", artist = "기타소년", genre = "발라드", style = "어쿠스틱", bpm = 88, key = "G", part = "MF", credit = ORIG, seed = 229, tags = { "duet" },
		lines = { "{M}꼬불꼬불 산길 따라", "{M}차를 타고 올라가", "{F}발아래 펼쳐진 불빛", "{F}별보다 더 반짝여", "{A}황령산 별밤 아래", "{A}너와 나 둘이서", "{A}도시의 불빛을 보며", "{A}꿈을 이야기해" },
	},
	{
		id = "s31", title = "민락 회센터", artist = "김부산", genre = "트로트", style = "트로트", bpm = 112, key = "Am", part = "M", credit = ORIG, seed = 233,
		lines = { "싱싱한 광어 한 접시", "초장에 콕 찍어서", "소주 한 잔 곁들이면", "세상 부러울 게 없네", "민락 회센터로 오소", "바다 내음 가득한 곳", "이모님 손맛 최고", "또 오이소 또 오이소" },
	},
	{
		id = "s32", title = "시험 끝!", artist = "교복밴드", genre = "댄스", style = "팝", bpm = 132, key = "D", part = "MF", credit = ORIG, seed = 239,
		lines = { "마지막 문제 풀고", "펜을 내려놓은 순간", "교실 창밖 햇살이", "오늘따라 눈부셔", "{A}시험 끝 시험 끝", "{A}이제 놀러 가자", "{A}성적표는 나중에", "{A}오늘은 즐기자" },
	},
	{
		id = "s33", title = "너의 이름 광안리", artist = "윤바다 & 오션걸즈", genre = "발라드", style = "발라드", bpm = 84, key = "C", part = "D", credit = ORIG, seed = 241, tags = { "new", "duet" },
		lines = { "{M}처음 만난 그 바다", "{M}기억하고 있니", "{F}어색하게 웃던 너", "{F}아직도 생생해", "{A}너의 이름 광안리", "{A}부를 때마다 설레", "{M}파도처럼 밀려와", "{F}내 맘을 적시네", "{F}시간이 흘러가도", "{M}변하지 않을 거야", "{A}우리가 걷던 바닷길", "{A}영원히 함께 걸어" },
	},
	{
		id = "s34", title = "짝사랑 일기", artist = "봄날소녀", genre = "발라드", style = "발라드", bpm = 78, key = "F", part = "F", credit = ORIG, seed = 251,
		lines = { "오늘도 너를 봤어", "복도 끝에서 웃는 너", "말 한마디 못 하고", "그냥 지나쳐 버렸어", "짝사랑 일기장에", "너의 이름 또 적어", "언젠가는 용기 내서", "좋아한다 말할게" },
	},
	{
		id = "s35", title = "여름 끝 바다", artist = "파도청년단", genre = "락", style = "록", bpm = 90, key = "A", part = "M", credit = ORIG, seed = 257,
		lines = { "파라솔이 접히고", "사람들이 떠나도", "나는 아직 여기에", "여름을 붙잡고 있어", "여름 끝 바다에서", "너를 다시 불러 봐", "뜨거웠던 그 계절", "잊지 말아 줘" },
	},
	{
		id = "s36", title = "새벽 두 시의 문자", artist = "시티라이트", genre = "발라드", style = "R&B", bpm = 86, key = "A", part = "F", credit = ORIG, seed = 263,
		lines = { "잘 지내냐는 한마디", "화면 위에 떠올라", "몇 번이나 지웠다가", "다시 쓰는 답장", "새벽 두 시의 문자", "아직 나를 생각해", "보고 싶다 말하면", "다시 시작될까" },
	},
	{
		id = "s37", title = "광안리 댄스파티", artist = "민락 크루", genre = "댄스", style = "댄스", bpm = 128, key = "C", part = "MF", credit = ORIG, seed = 269, tags = { "new" },
		lines = { "볼륨을 높여 봐", "모래 위의 무대", "모두 손을 들어", "지금부터 시작이야", "{A}광안리 댄스파티", "{A}다 같이 뛰어 뛰어", "{A}오른쪽 왼쪽 빙글빙글", "{A}멈추지 마 밤새도록", "디제이 음악 바꿔 줘", "더 신나게 더 크게", "바다도 춤을 추는", "광안리의 밤" },
	},
	{
		id = "s38", title = "가자 부산", artist = "사직 응원단", genre = "락", style = "응원가", bpm = 120, key = "D", part = "MF", credit = ORIG, seed = 271,
		lines = { "주황 봉지 머리에 쓰고", "목이 터져라 외쳐", "구 회 말 투 아웃이라도", "우리는 포기 안 해", "{A}가자 부산 가자 부산", "{A}승리를 향해 가자", "{A}오늘도 이긴다", "{A}부산 최고 부산" },
	},
	{
		id = "s39", title = "할매 손칼국수", artist = "김부산", genre = "트로트", style = "트로트", bpm = 96, key = "Am", part = "M", credit = ORIG, seed = 277,
		lines = { "시장 골목 끝자락에", "사십 년 된 칼국수집", "할매가 밀어 주는", "쫄깃한 면발 하나", "할매 손칼국수", "한 그릇에 사랑 담아", "국물 한 숟갈 떠먹으면", "고향 생각이 나네" },
	},
	{
		id = "s40", title = "졸업식 날", artist = "교복밴드", genre = "발라드", style = "발라드", bpm = 74, key = "G", part = "MF", credit = ORIG, seed = 281,
		lines = { "교복 위에 꽃다발", "어색한 사진 한 장", "매일 걷던 교문 앞", "오늘은 마지막이야", "{A}고마웠어 친구야", "{A}우리 꼭 다시 만나", "{A}어디에서 무엇을 하든", "{A}오늘을 기억해" },
	},
	{
		id = "s41", title = "보름달 소원", artist = "김부산", genre = "트로트", style = "트로트", bpm = 102, key = "Am", part = "MF", credit = ORIG, seed = 283, tags = { "new", "event" },
		lines = { "둥근 보름달이 떴네", "온 가족이 모였네", "송편 빚고 전 부치고", "웃음소리 가득하네", "{A}보름달아 보름달아", "{A}내 소원 들어주렴", "{A}우리 가족 건강하고", "{A}행복하게 해 주렴" },
	},
	{
		id = "s42", title = "별빛 수영구", artist = "한여름", genre = "OST", style = "OST", bpm = 70, key = "C", part = "F", credit = ORIG, origin = "드라마 〈광안리 연가〉 OST", seed = 293, tags = { "new" },
		lines = { "수많은 별 중에서", "너를 찾은 그날 밤", "바다 위에 흩어진", "별빛을 모아 줄게", "너는 나의 별빛", "어두운 밤을 비춰", "멀리 있어도 괜찮아", "같은 하늘 아래니까" },
	},
	{
		id = "s43", title = "바람이 머문 자리", artist = "윤바다", genre = "OST", style = "OST", bpm = 76, key = "D", part = "M", credit = ORIG, origin = "드라마 〈민락동 사람들〉 OST", seed = 307, tags = { "new" },
		lines = { "오래된 골목 끝에", "바람이 머문 자리", "그곳에 서 있으면", "네 목소리 들려와", "기억해 줄래", "우리가 웃던 날들", "바람이 다시 불면", "나를 찾아와 줘" },
	},
	{
		id = "s44", title = "우리의 계절", artist = "오션걸즈", genre = "OST", style = "OST", bpm = 96, key = "D", part = "F", credit = ORIG, origin = "웹드라마 〈광안 고등학교〉 OST", seed = 311, tags = { "new" },
		lines = { "처음 교실 문을 열던", "설레던 그 아침", "낯설던 너의 얼굴", "이제는 가장 소중해", "우리의 계절은", "아직 끝나지 않았어", "함께라서 빛나는", "지금 이 순간" },
	},
	{
		id = "s45", title = "끝까지 달려", artist = "금련산 밴드", genre = "OST", style = "애니", bpm = 148, key = "E", part = "M", credit = ORIG, origin = "애니메이션 〈부산 레이서〉 OST", seed = 313, tags = { "new" },
		lines = { "출발 신호가 울리면", "심장이 뛰기 시작해", "앞만 보고 달려가", "바람보다 빠르게", "끝까지 달려 달려", "쓰러져도 일어나", "결승선 그 너머에", "꿈이 기다려" },
	},

	-------------------------------------------------------------------------------------------------
	-- 민요 (traditional Korean folk songs, public domain)
	-------------------------------------------------------------------------------------------------
	{
		id = "s46", title = "아리랑", artist = "경기 민요", genre = "민요", style = "민요", bpm = 92, key = "G", meter = 3, part = "MF", credit = "작사 · 작곡 미상 (전래 민요)", origin = "경기 민요 · 세마치장단", seed = 317, tags = { "pd" }, intro = 2,
		lines = {
			{ t = "아리랑 아리랑 아라리요", m = "D4:1.5 E4:0.5 D4:0.5+E4:0.5 G4:1.5 A4:0.5 G4:0.5+A4:0.5 B4:0.5 A4:0.5 G4:0.5+A4:0.5 G4:0.5+E4:0.5+D4:3", p = "A" },
			{ t = "아리랑 고개로 넘어간다", m = "D5:1.5 E5:0.5 D5:0.5+B4:0.5 A4:1.5 B4:0.5 A4:0.5+G4:0.5 E4:0.5 G4:0.5 A4:0.5+B4:0.5 A4:0.5+G4:3.5", p = "A" },
			{ t = "나를 버리고 가시는 님은", m = "D4:1.5 E4:0.5 D4:0.5 E4:0.5 G4:1.5 A4:0.5 G4:0.5 A4:0.5 B4:0.5+A4:0.5 G4:0.5+A4:0.5+G4:0.5+E4:0.5+D4:3" },
			{ t = "십 리도 못 가서 발병 난다", m = "D5:1.5 E5:0.5 D5:0.5+B4:0.5 A4:1.5 B4:0.5 A4:0.5+G4:0.5 E4:0.5 G4:0.5 A4:0.5+B4:0.5 A4:0.5+G4:3.5" },
			{ t = "청천 하늘엔 잔별도 많고", m = "D4:1.5 E4:0.5 D4:0.5 E4:0.5 G4:1.5 A4:0.5 G4:0.5 A4:0.5 B4:0.5+A4:0.5 G4:0.5+A4:0.5+G4:0.5+E4:0.5+D4:3" },
			{ t = "우리네 가슴엔 수심도 많다", m = "D5:1 E5:0.5 D5:0.5+B4:1 A4:1 B4:0.5 A4:0.5+G4:1 E4:0.5 G4:0.5 A4:0.5+B4:0.5 A4:1 G4:3" },
		},
		form = { 1, 2, 3, 4, "간주", 1, 2, 5, 6 },
	},
	{
		id = "s47", title = "도라지 타령", artist = "경기 민요", genre = "민요", style = "민요", bpm = 104, key = "C", meter = 3, part = "MF", credit = "작사 · 작곡 미상 (전래 민요)", origin = "경기 민요 · 세마치장단", seed = 331, tags = { "pd" }, intro = 2,
		lines = {
			{ t = "도라지 도라지 백도라지", m = "G4:1 G4:0.5 E4:1.5 G4:1 G4:0.5 E4:1.5 G4:1 A4:0.5 G4:0.5 E4:1+D4:3" },
			{ t = "심심 산천에 백도라지", m = "A4:0.5 A4:0.5 C5:1 A4:0.5 G4:0.5 G4:1 A4:0.5 G4:0.5 E4:1+C4:3" },
			{ t = "한두 뿌리만 캐어도", m = "E4:1 G4:0.5 A4:1.5 C5:0.5 A4:0.5 G4:1 E4:0.5 G4:0.5" },
			{ t = "대바구니로 반실만 되누나", m = "G4:0.5 A4:0.5 G4:0.5 E4:0.5 D4:1 E4:1 G4:0.5 E4:1.5 D4:1 E4:0.5 D4:0.5+C4:4" },
			{ t = "에헤요 에헤요 에헤야", m = "G4:1 A4:0.5 G4:1.5 C5:1 D5:0.5 C5:1.5 A4:0.5 C5:0.5 A4:0.5+G4:1.5", p = "A" },
			{ t = "어여라 난다 지화자 좋다", m = "E4:0.5 G4:0.5 A4:1 G4:0.5 E4:0.5 G4:1 A4:0.5 C5:1.5 A4:1 G4:2", p = "A" },
			{ t = "저기 저 산 밑에 도라지가 한들한들", m = "E4:0.5 G4:0.5 A4:1 C5:1 A4:0.5 G4:0.5 E4:0.5 G4:0.5 A4:0.5 G4:0.5 E4:1 D4:0.5 E4:0.5 D4:0.5+C4:3.5", p = "A" },
		},
		form = { 1, 2, 3, 4, 5, 6, 7, "간주", 1, 2, 3, 4, 5, 6, 7 },
	},
	{
		id = "s48", title = "밀양 아리랑", artist = "경상도 민요", genre = "민요", style = "민요", bpm = 116, key = "Am", meter = 3, part = "MF", credit = "작사 · 작곡 미상 (전래 민요)", origin = "경상도 민요 · 세마치장단", seed = 337, tags = { "pd" }, intro = 2,
		lines = {
			{ t = "날 좀 보소 날 좀 보소 날 좀 보소", m = "A4:1 A4:0.5 C5:1 A4:0.5 G4:1 G4:0.5 A4:1 G4:0.5 E4:1 G4:0.5 A4:1 E4:0.5+D4:3" },
			{ t = "동지섣달 꽃 본 듯이 날 좀 보소", m = "A4:0.5 A4:0.5 C5:1 A4:1 G4:1 A4:0.5 G4:0.5 E4:1 G4:1 G4:0.5 A4:1 G4:0.5+E4:3" },
			{ t = "아리 아리랑 쓰리 쓰리랑 아라리가 났네", m = "C5:0.5 D5:0.5 C5:0.5 A4:0.5 C5:1 A4:0.5 C5:0.5 A4:0.5 G4:0.5 A4:1 G4:0.5 A4:0.5 G4:0.5 E4:0.5 G4:0.5 E4:3.5", p = "A" },
			{ t = "아리랑 고개로 날 넘겨 주소", m = "A4:1 C5:0.5 A4:1.5 G4:1 A4:0.5 G4:1.5 E4:1 G4:0.5 A4:0.5 G4:0.5 E4:3.5", p = "A" },
			{ t = "정든 님이 오셨는데 인사를 못 해", m = "A4:0.5 A4:0.5 C5:1 A4:1 G4:0.5 A4:0.5 G4:1 E4:1 G4:0.5 A4:0.5 G4:0.5 E4:0.5 G4:0.5+E4:3.5" },
			{ t = "행주치마 입에 물고 입만 방긋", m = "A4:0.5 A4:0.5 C5:1 A4:1 G4:1 A4:0.5 G4:0.5 E4:1 G4:1 G4:0.5 A4:1 G4:0.5+E4:3" },
		},
		form = { 1, 2, 3, 4, "간주", 5, 6, 3, 4 },
	},
	{
		id = "s49", title = "진도 아리랑", artist = "전라도 민요", genre = "민요", style = "민요", bpm = 100, key = "Am", meter = 3, part = "MF", credit = "작사 · 작곡 미상 (전래 민요)", origin = "전라도 민요 · 세마치장단", seed = 347, tags = { "pd" }, intro = 2,
		lines = {
			{ t = "아리아리랑 스리스리랑 아라리가 났네", m = "E5:0.5 E5:0.5 E5:0.5 C5:0.5 B4:1 C5:0.5 B4:0.5 A4:0.5 B4:0.5 A4:1 E4:0.5 A4:0.5 B4:0.5 C5:0.5 B4:0.5 A4:3.5", p = "A" },
			{ t = "아리랑 응응응 아라리가 났네", m = "E5:1 C5:0.5 B4:1.5 C5:0.5 B4:0.5 A4:2 E4:0.5 A4:0.5 B4:0.5 C5:0.5 B4:0.5 A4:3.5", p = "A" },
			{ t = "문경 새재는 웬 고갠가", m = "A4:1 A4:0.5 C5:1 B4:0.5 A4:1 C5:0.5 E5:1 C5:0.5 B4:1+A4:2" },
			{ t = "구비야 구비구비가 눈물이로구나", m = "E5:0.5 E5:0.5 C5:2 B4:0.5 C5:0.5 B4:0.5 A4:0.5 B4:1 C5:0.5 B4:0.5 A4:0.5 E4:0.5 A4:0.5 A4:3.5" },
			{ t = "노다 가세 노다나 가세", m = "A4:0.5 C5:0.5 E5:1 C5:1 B4:0.5 C5:0.5 B4:0.5 A4:0.5 A4:4" },
			{ t = "저 달이 떴다 지도록 노다나 가세", m = "E4:0.5 A4:0.5 B4:1 C5:0.5 B4:0.5 A4:0.5 B4:0.5 C5:2 B4:0.5 C5:0.5 B4:0.5 A4:0.5 A4:4" },
		},
		form = { 1, 2, 3, 4, 1, 2, "간주", 5, 6, 1, 2 },
	},
	{
		id = "s50", title = "강강술래", artist = "전라도 민요", genre = "민요", style = "민요", bpm = 96, key = "Am", meter = 3, part = "MF", credit = "작사 · 작곡 미상 (전래 민요)", origin = "전라남도 해안 지방 민요 · 국가무형문화재", seed = 349, tags = { "pd" }, intro = 2,
		lines = {
			{ t = "달 떠온다 달 떠온다", m = "E5:1 E5:0.5 C5:1 B4:0.5 C5:0.5 B4:0.5 A4:0.5 A4:1.5", p = "F" },
			{ t = "강강술래", m = "A4:1 B4:0.5 C5:1 A4:3.5", p = "A" },
			{ t = "동해 동창 달 떠온다", m = "E5:1 E5:0.5 C5:1 B4:0.5 C5:0.5 B4:0.5 A4:0.5 A4:1.5", p = "F" },
			{ t = "강강술래", m = "A4:1 B4:0.5 C5:1 A4:3.5", p = "A" },
			{ t = "저 달이 뉘 달인가", m = "E5:1 E5:0.5 C5:1 B4:0.5 C5:1 B4:0.5 A4:1.5", p = "F" },
			{ t = "강강술래", m = "A4:1 B4:0.5 C5:1 A4:3.5", p = "A" },
			{ t = "우리 마을 달이로세", m = "E5:1 E5:0.5 C5:1 B4:0.5 C5:0.5 B4:0.5 A4:0.5 A4:1.5", p = "F" },
			{ t = "강강술래", m = "A4:1 B4:0.5 C5:1 A4:3.5", p = "A" },
			{ t = "뛰어 보세 뛰어 보세", m = "E5:1 E5:0.5 C5:1 B4:0.5 C5:0.5 B4:0.5 A4:0.5 A4:1.5", p = "F" },
			{ t = "강강술래", m = "A4:1 B4:0.5 C5:1 A4:3.5", p = "A" },
			{ t = "손에 손을 맞잡고서", m = "E5:1 E5:0.5 C5:1 B4:0.5 C5:0.5 B4:0.5 A4:0.5 A4:1.5", p = "F" },
			{ t = "강강술래", m = "A4:1 B4:0.5 C5:1 A4:3.5", p = "A" },
		},
	},
	{
		id = "s51", title = "새야 새야 파랑새야", artist = "전래 민요", genre = "민요", style = "민요", bpm = 76, key = "Em", meter = 3, part = "MF", credit = "작사 · 작곡 미상 (전래 민요)", origin = "전래 민요", seed = 353, tags = { "pd" }, intro = 2,
		lines = {
			{ t = "새야 새야 파랑새야", m = "E4:1 E4:0.5 G4:1 E4:0.5 A4:1 G4:0.5 A4:0.5 E4:1" },
			{ t = "녹두밭에 앉지 마라", m = "G4:1 A4:0.5 B4:1 A4:0.5 G4:1 E4:0.5 D4:0.5 E4:1" },
			{ t = "녹두꽃이 떨어지면", m = "B4:1 B4:0.5 D5:1 B4:0.5 A4:1 B4:0.5 A4:0.5 G4:1" },
			{ t = "청포 장수 울고 간다", m = "G4:1 A4:0.5 G4:1 E4:0.5 D4:1 E4:0.5 D4:0.5 E4:4" },
		},
		form = { 1, 2, 3, 4, "간주", 1, 2, 3, 4 },
	},
	{
		id = "s52", title = "옹헤야", artist = "경상도 민요", genre = "민요", style = "민요", bpm = 132, key = "Am", meter = 4, part = "MF", credit = "작사 · 작곡 미상 (전래 민요)", origin = "경상도 보리타작 노래", seed = 359, tags = { "pd" }, intro = 2,
		lines = {
			{ t = "옹헤야 옹헤야", m = "A4 C5 A4:2 G4 A4 E4:2", p = "A" },
			{ t = "어절씨구 옹헤야", m = "E5 D5 C5 A4 A4 C5 A4:2", p = "M" },
			{ t = "저절씨구 옹헤야", m = "E5 D5 C5 A4 G4 A4 E4:2", p = "M" },
			{ t = "잘도 한다 옹헤야", m = "E5 D5 C5 A4 A4 C5 A4:2", p = "M" },
			{ t = "이 보리를 옹헤야", m = "E5 D5 C5 A4 G4 A4 E4:2", p = "M" },
			{ t = "털어 보세 옹헤야", m = "E5 D5 C5 A4 A4 C5 A4:2", p = "M" },
			{ t = "에헤 에헤 옹헤야", m = "E5 D5 E5 C5 G4 A4 E4:2", p = "A" },
			{ t = "이 보리가 옹헤야", m = "E5 D5 C5 A4 A4 C5 A4:2", p = "M" },
			{ t = "누구 보리 옹헤야", m = "E5 D5 C5 A4 G4 A4 E4:2", p = "M" },
			{ t = "우리 보리 옹헤야", m = "E5 D5 C5 A4 A4 C5 A4:2", p = "M" },
			{ t = "잘도 털린다 옹헤야", m = "E5 D5 C5 A4:0.5 A4:0.5 G4 A4 E4:2", p = "M" },
			{ t = "옹헤야 옹헤야", m = "A4 C5 A4:2 G4 A4 A4:2", p = "A" },
		},
		form = { 1, 2, 3, 4, 5, 6, 7, "간주", 8, 9, 10, 11, 12 },
	},

	-------------------------------------------------------------------------------------------------
	-- public-domain melodies with original Korean words (동요 / 축하곡 / 시즌)
	-------------------------------------------------------------------------------------------------
	{
		id = "s53", title = "반짝반짝 바다 별", artist = "광안 동요단", genre = "동요", style = "동요", bpm = 100, key = "C", part = "MF", credit = "작곡 프랑스 민요 (작자 미상) · 작사 광안 노래방", origin = "프랑스 민요 〈Ah! vous dirai-je, maman〉 선율", seed = 367, tags = { "pd" },
		lines = {
			{ t = "반짝반짝 바다 별", m = "C4 C4 G4 G4 A4 A4 G4:2" },
			{ t = "광안대교 비추네", m = "F4 F4 E4 E4 D4 D4 C4:2" },
			{ t = "물결 따라 춤추고", m = "G4 G4 F4 F4 E4 E4 D4:2" },
			{ t = "모래 위에 앉았네", m = "G4 G4 F4 F4 E4 E4 D4:2" },
			{ t = "반짝반짝 바다 별", m = "C4 C4 G4 G4 A4 A4 G4:2" },
			{ t = "우리 꿈을 비추네", m = "F4 F4 E4 E4 D4 D4 C4:2" },
		},
		form = { 1, 2, 3, 4, 5, 6, "간주", 1, 2, 3, 4, 5, 6 },
	},
	{
		id = "s54", title = "생일 축하합니다", artist = "다 같이", genre = "동요", style = "축하곡", bpm = 100, key = "C", meter = 3, part = "MF", credit = "작곡 밀드레드 힐 · 패티 힐 (퍼블릭 도메인)", origin = "〈Happy Birthday to You〉 선율", seed = 373, tags = { "pd" },
		lines = {
			{ t = "생일 축하합니다", m = "r:2 G4:0.75 G4:0.25 A4 G4 C5 B4 B4", p = "A" },
			{ t = "생일 축하합니다", m = "G4:0.75 G4:0.25 A4 G4 D5 C5 C5", p = "A" },
			{ t = "사랑하는 내 친구", m = "G4:0.75 G4:0.25 G5 E5 C5 B4 A4", p = "A" },
			{ t = "생일 축하합니다", m = "F5:0.75 F5:0.25 E5 C5 D5 C5 C5:2", p = "A" },
		},
		form = { 1, 2, 3, 4, "간주", 1, 2, 3, 4 },
	},
	{
		id = "s55", title = "환희의 바다", artist = "광안 합창단", genre = "동요", style = "동요", bpm = 108, key = "C", part = "MF", credit = "작곡 베토벤 (교향곡 9번) · 작사 광안 노래방", origin = "베토벤 교향곡 9번 〈환희의 송가〉 선율", seed = 379, tags = { "pd" },
		lines = {
			{ t = "파도 소리 들리는 날", m = "E4 E4 F4 G4 G4 F4 E4 D4", p = "A" },
			{ t = "모두 함께 노래해", m = "C4 C4 D4 E4 E4:1.5 D4:0.5 D4:2", p = "A" },
			{ t = "광안대교 불빛 아래", m = "E4 E4 F4 G4 G4 F4 E4 D4", p = "A" },
			{ t = "손을 잡고 노래해", m = "C4 C4 D4 E4 D4:1.5 C4:0.5 C4:2", p = "A" },
			{ t = "맑은 날도 비 오는 날도", m = "D4 D4 E4 C4 D4 E4:0.5 F4:0.5 E4 C4", p = "A" },
			{ t = "우리 함께 걸어가요", m = "D4 E4:0.5 F4:0.5 E4 D4 C4 D4 G3:2", p = "A" },
			{ t = "환한 미소 가득 안고", m = "E4 E4 F4 G4 G4 F4 E4 D4", p = "A" },
			{ t = "기쁨의 노래 불러", m = "C4 C4 D4 E4 D4:1.5 C4:0.5 C4:2", p = "A" },
		},
		form = { 1, 2, 3, 4, 5, 6, 7, 8, "간주", 5, 6, 7, 8 },
	},
	{
		id = "s56", title = "갈매기야 갈매기야", artist = "광안 동요단", genre = "동요", style = "동요", bpm = 112, key = "C", part = "MF", credit = "작곡 프랑스 민요 (작자 미상) · 작사 광안 노래방", origin = "프랑스 민요 〈Frère Jacques〉 선율", seed = 383, tags = { "pd" },
		lines = {
			{ t = "갈매기야 갈매기야", m = "C4 D4 E4 C4 C4 D4 E4 C4" },
			{ t = "바다로 바다로", m = "E4 F4 G4:2 E4 F4 G4:2" },
			{ t = "둥실둥실 떠다니며 노래하자", m = "G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4 C4 G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4 C4" },
			{ t = "끼룩룩 끼룩룩", m = "C4 G3 C4:2 C4 G3 C4:2" },
			{ t = "파도야 파도야", m = "C4 D4 E4:2 C4 D4 E4:2", p = "A" },
			{ t = "어디 가니 어디 가니", m = "E4 F4 G4:1 G4:1 E4 F4 G4:1 G4:1", p = "A" },
			{ t = "모래성을 쌓아 놓고 놀러 가자", m = "G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4 C4 G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4 C4", p = "A" },
			{ t = "출렁출렁 출렁출렁", m = "C4:0.5 C4:0.5 G3 C4 C4:0.5 C4:0.5 G3 C4", p = "A" },
		},
		form = { 1, 2, 3, 4, "간주", 5, 6, 7, 8 },
	},
	{
		id = "s57", title = "광안대교 건너요", artist = "광안 동요단", genre = "동요", style = "동요", bpm = 112, key = "C", part = "MF", credit = "작곡 영국 전래 동요 · 작사 광안 노래방", origin = "영국 전래 동요 〈London Bridge〉 선율", seed = 389, tags = { "pd" },
		lines = {
			{ t = "광안대교 건너요", m = "G4:1.5 A4:0.5 G4 F4 E4 F4 G4:2" },
			{ t = "건너요 건너요", m = "D4 E4 F4:2 E4 F4 G4:2" },
			{ t = "불빛 따라 건너요", m = "G4:1.5 A4:0.5 G4 F4 E4 F4 G4:2" },
			{ t = "우리 함께", m = "D4:2 G4:2 E4 C4:3" },
			{ t = "갈매기도 날아요", m = "G4:1.5 A4:0.5 G4 F4 E4 F4 G4:2" },
			{ t = "날아요 날아요", m = "D4 E4 F4:2 E4 F4 G4:2" },
			{ t = "파도 위로 날아요", m = "G4:1.5 A4:0.5 G4 F4 E4 F4 G4:2" },
			{ t = "높이 높이", m = "D4:2 G4:2 E4 C4:3" },
		},
		form = { 1, 2, 3, 4, "간주", 5, 6, 7, 8 },
	},
	{
		id = "s58", title = "징글벨 광안리", artist = "광안 동요단", genre = "동요", style = "동요", bpm = 120, key = "C", part = "MF", credit = "작곡 J. 피어폰트 (1857, 퍼블릭 도메인) · 작사 광안 노래방", origin = "〈Jingle Bells〉 선율", seed = 397, tags = { "pd", "season" },
		lines = {
			{ t = "징글벨 징글벨", m = "E4 E4 E4:2 E4 E4 E4:2", p = "A" },
			{ t = "눈이 내려요", m = "E4 G4 C4:1.5 D4:0.5 E4:4", p = "A" },
			{ t = "반짝이는 광안대교 위", m = "F4 F4 F4:1.5 F4:0.5 F4 E4 E4 E4:0.5 E4:0.5", p = "A" },
			{ t = "산타가 날아요", m = "E4 D4 D4 E4 D4:2 G4:2", p = "A" },
			{ t = "징글벨 징글벨", m = "E4 E4 E4:2 E4 E4 E4:2", p = "A" },
			{ t = "종이 울려요", m = "E4 G4 C4:1.5 D4:0.5 E4:4", p = "A" },
			{ t = "썰매 대신 오리배 타고", m = "F4 F4 F4 F4 F4 E4 E4 E4:0.5 E4:0.5", p = "A" },
			{ t = "신나게 가요", m = "G4 G4 F4 D4 C4:4", p = "A" },
		},
		form = { 1, 2, 3, 4, 5, 6, 7, 8, "간주", 1, 2, 3, 4, 5, 6, 7, 8 },
	},
}

-- 인기차트 order before this server has real weekly play counts (Store fills State.Chart)
Songs.SEED_CHART = { "s01", "s02", "s04", "s09", "s33", "s05", "s25", "s46", "s37", "s12", "s22", "s54", "s20", "s03", "s19", "s08", "s18", "s14", "s41", "s42" }

-- genre -> band preset (Chart / client Band)
Songs.STYLE_PRESET = {
	["발라드"] = "ballad", ["인디"] = "ballad", ["어쿠스틱"] = "acoustic", ["블루스"] = "ballad", ["R&B"] = "rnb",
	["팝"] = "pop", ["시티팝"] = "citypop", ["EDM"] = "edm", ["댄스"] = "dance", ["트로트"] = "trot",
	["힙합"] = "hiphop", ["록"] = "rock", ["응원가"] = "rock", ["동요"] = "kids", ["축하곡"] = "kids",
	["민요"] = "folk", ["OST"] = "ost", ["애니"] = "rock",
}

-------------------------------------------------------------------------------------------------
-- normalisation (numbers, parts, lookups)
-------------------------------------------------------------------------------------------------
Songs.byId = {}
Songs.byNo = {}

local function parsePart(text: string, default: string): (string, string)
	local p, rest = string.match(text, "^{([MFA])}(.*)$")
	if p then
		return rest, p
	end
	return text, default
end

for i, s in Songs.LIST do
	s.index = i
	s.no = 38000 + i * 131
	s.meter = s.meter or 4
	s.tags = s.tags or {}
	s.soundId = s.soundId or ""
	s.soundOffset = s.soundOffset or 0
	s.preset = Songs.STYLE_PRESET[s.style] or Songs.STYLE_PRESET[s.genre] or "pop"
	s.minor = string.sub(s.key or "C", -1) == "m"
	local defPart = if s.part == "F" then "F" elseif s.part == "M" then "M" else "A"
	local lines = {}
	for li, l in s.lines do
		if type(l) == "string" then
			local text, part = parsePart(l, defPart)
			lines[li] = { t = text, p = part }
		else
			lines[li] = { t = l.t, m = l.m, p = l.p or defPart }
		end
	end
	s.lines = lines
	s.explicit = lines[1] ~= nil and lines[1].m ~= nil
	s.tagSet = {}
	for _, t in s.tags do
		s.tagSet[t] = true
	end
	if s.part == "D" then
		s.tagSet.duet = true
	end
	Songs.byId[s.id] = s
	Songs.byNo[s.no] = s
end

Songs.COUNT = #Songs.LIST

function Songs.get(id: any): any?
	if type(id) == "string" then
		return Songs.byId[id]
	elseif type(id) == "number" then
		return Songs.byNo[id]
	end
	return nil
end

-- 남 / 여 / 혼성 / 듀엣 label
function Songs.partLabel(s: any): string
	local p = s and s.part
	if p == "M" then
		return "남"
	elseif p == "F" then
		return "여"
	elseif p == "D" then
		return "듀엣"
	end
	return "혼성"
end

return Songs
