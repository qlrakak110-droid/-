--!strict
-- GwangalliDecorShared/Text: every Korean string of the 자유 배치 add-on + small text helpers
-- (원 표기, 초성 검색, 조사). Reason codes from Rules / the server map to Text.REASON.

local Text = {}

-------------------------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------------------------
function Text.commas(n: number): string
	local neg = n < 0
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if neg then "-" else "") .. out
end

function Text.won(n: number?): string
	return Text.commas(n or 0) .. "원"
end

-- 1,250,000원 -> "125만원", 18,500 -> "1.8만원", 9,000 -> "9,000원"
function Text.wonShort(n: number?): string
	local v = math.floor(n or 0)
	if math.abs(v) >= 100000000 then
		local e = v / 100000000
		return (if e == math.floor(e) then string.format("%d", e) else string.format("%.1f", e)) .. "억원"
	elseif math.abs(v) >= 10000 then
		local m = v / 10000
		if math.abs(m) >= 100 or m == math.floor(m) then
			return Text.commas(math.floor(m)) .. "만원"
		end
		return string.format("%.1f", m) .. "만원"
	end
	return Text.won(v)
end

local CHO = { "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ" }
local CHO_SET: { [string]: boolean } = {}
for _, c in CHO do
	CHO_SET[c] = true
end

-- "체스터필드 소파" -> "ㅊㅅㅌㅍㄷ ㅅㅍ" (non-Hangul characters are kept, lower-cased)
function Text.chosung(s: string): string
	local out = {}
	for _, cp in utf8.codes(s) do
		if cp >= 0xAC00 and cp <= 0xD7A3 then
			table.insert(out, CHO[math.floor((cp - 0xAC00) / 588) + 1])
		else
			table.insert(out, string.lower(utf8.char(cp)))
		end
	end
	return table.concat(out)
end

-- true when the query is made of 초성 jamo (and spaces) only
function Text.isChosungQuery(q: string): boolean
	local any = false
	for _, cp in utf8.codes(q) do
		local ch = utf8.char(cp)
		if CHO_SET[ch] then
			any = true
		elseif ch ~= " " then
			return false
		end
	end
	return any
end

-- does the last syllable have a final consonant (받침)?
local function hasBatchim(word: string): boolean
	local last = nil
	for _, cp in utf8.codes(word) do
		last = cp
	end
	if not last or last < 0xAC00 or last > 0xD7A3 then
		return false
	end
	return (last - 0xAC00) % 28 ~= 0
end

-- 조사: Text.josa("소파", "이", "가") -> "소파가"
function Text.josa(word: string, withB: string, without: string): string
	return word .. (if hasBatchim(word) then withB else without)
end

-- (으)로
function Text.ro(word: string): string
	local last = nil
	for _, cp in utf8.codes(word) do
		last = cp
	end
	if last and last >= 0xAC00 and last <= 0xD7A3 then
		local jong = (last - 0xAC00) % 28
		if jong ~= 0 and jong ~= 8 then -- ㄹ 받침은 "로"
			return word .. "으로"
		end
	end
	return word .. "로"
end

-- trims, collapses whitespace, cuts to n characters (UTF-8 aware)
function Text.clip(s: any, n: number): string
	if type(s) ~= "string" then
		return ""
	end
	local t = string.gsub(string.gsub(s, "[%c]", " "), "%s+", " ")
	t = string.match(t, "^%s*(.-)%s*$") or ""
	if utf8.len(t) == nil then
		return ""
	end
	if (utf8.len(t) :: number) <= n then
		return t
	end
	local cut = utf8.offset(t, n + 1)
	return if cut then string.sub(t, 1, cut - 1) else t
end

function Text.fmt(s: string, ...: any): string
	local ok, r = pcall(string.format, s, ...)
	return if ok then r else s
end

-------------------------------------------------------------------------------------------------
-- Reason codes -> messages
-------------------------------------------------------------------------------------------------
Text.REASON = {
	booting = "인테리어 기능을 준비하고 있어요. 잠시 후 다시 해 주세요",
	notHome = "내 집 안에서만 꾸밀 수 있어요",
	notOwner = "집주인만 할 수 있어요",
	coopOnly = "함께 꾸미기에서는 창고 가구로만 꾸밀 수 있어요",
	staged = "둘러보기 중에는 꾸밀 수 없어요",
	noProfile = "프로필을 불러오는 중이에요",
	noData = "인테리어 기록을 불러오는 중이에요",
	unknown = "없는 가구예요",
	bad = "잘못된 요청이에요",
	cap = "%s에는 가구를 최대 %d개까지 놓을 수 있어요 · 더 넓은 집으로 이사하면 늘어요",
	parts = "집이 너무 복잡해졌어요 (모바일 최적화) · 작은 소품을 조금 정리해 주세요",
	outside = "집 밖으로 나가요",
	floating = "바닥이나 받침 위에 놓아 주세요",
	tooHigh = "너무 높이 띄웠어요",
	stair = "계단에는 놓을 수 없어요",
	noSurface = "테이블·선반 같은 받침 위에 올려요",
	floorOnly = "이 가구는 바닥에 놓아요",
	noWall = "벽에 딱 붙여서 걸어요",
	noCeiling = "천장에 달아요",
	ceiling = "천장에 닿아요",
	lowCeiling = "너무 낮게 달면 머리에 부딪혀요",
	wall = "벽을 뚫을 수 없어요",
	fixture = "붙박이 가구·설비와 겹쳐요",
	overlap = "다른 가구와 겹쳐요",
	slot = "기본 가구 자리예요 · 🛠️ 인테리어에서 바꿀 수 있어요",
	group = "같이 옮기는 가구 중 놓을 수 없는 게 있어요",
	noMoney = "돈 기능이 아직 준비되지 않았어요",
	presetEmpty = "배치할 가구가 없어요",
	door = "문이 열리는 자리예요",
	entry = "현관 통로는 비워 둬야 해요",
	interact = "%s 앞은 비워 둬야 써요",
	path = "이렇게 두면 %s 가는 길이 막혀요",
	person = "사람이 서 있는 자리예요",
	insufficient = "잔액이 부족해요 (필요 %s · 통장 %s · 현금 %s)",
	noStock = "창고에 없는 가구예요",
	storageFull = "창고가 꽉 찼어요 (최대 %d개) · 안 쓰는 가구를 팔아 주세요",
	expired = "되돌릴 수 있는 시간이 지났어요",
	same = "이미 그 모습이에요",
	rate = "잠시 후 다시 해 주세요",
	liked = "오늘은 이미 좋아요를 눌렀어요",
	notGuest = "놀러 간 집에서만 할 수 있어요",
	filtered = "지금은 방명록을 쓸 수 없어요",
	empty = "내용을 적어 주세요",
	noChat = "채팅이 제한된 계정은 방명록을 쓸 수 없어요",
	photoLimit = "오늘 집 사진 보상은 다 받았어요",
	noPreset = "저장된 프리셋이 없어요",
	busy = "처리 중이에요",
	saveFail = "저장하지 못했어요. 잠시 후 다시 해 주세요",
	stacked = "위에 다른 가구가 올려져 있어요",
	finishRoom = "꾸밀 수 없는 방이에요",
	noLight = "이 가구에는 불빛이 없어요",
	timeout = "서버 응답이 늦어요. 잠시 후 다시 해 주세요",
}

function Text.reason(code: string?, ...: any): string
	local s = Text.REASON[code or ""] or Text.REASON.bad
	if select("#", ...) > 0 then
		return Text.fmt(s, ...)
	end
	return (string.gsub(s, "%%[sd]", ""))
end

-------------------------------------------------------------------------------------------------
-- UI copy
-------------------------------------------------------------------------------------------------
Text.UI = {
	entry = "✨ 자유 배치",
	entryKey = "가구를 원하는 곳에 직접 놓아요 (K)",
	coach = "가구를 원하는 곳에 직접 놓아 보세요! (K)",
	title = "자유 배치",
	done = "완료",
	close = "닫기",
	all = "전체",
	search = "가구 이름으로 찾기 (예: 소파, ㅅㅍ)",
	storage = "창고",
	sets = "추천 세트",
	place = "놓기",
	placeFree = "창고에서 꺼내기",
	cancel = "취소",
	rotate = "돌리기",
	up = "올리기",
	down = "내리기",
	color = "색·재질",
	move = "옮기기",
	dup = "하나 더",
	toStorage = "창고에 넣기",
	sell = "팔기",
	refund = "구매 취소",
	multi = "다중 선택",
	groupMove = "같이 옮기기",
	selected = "%d개 선택",
	okHere = "여기에 놓을 수 있어요",
	overlapOn = "겹치기 허용",
	grid = "격자",
	gridOff = "격자 끔",
	rot = "회전",
	fine = "미세",
	cut = "벽 가리기",
	undo = "되돌리기",
	redo = "다시 하기",
	finish = "벽지·바닥·조명",
	presets = "프리셋",
	goals = "목표·뱃지",
	photo = "집 사진",
	settings = "설정",
	help = "① 카탈로그에서 가구를 골라요 → ② 놓을 곳을 눌러요 → ③ ✓ 놓기!\n놓은 가구를 누르면 옮기거나 색·재질을 바꿀 수 있어요",
	keysPC = "R/T 회전 · Q/E 높이 · G 격자 · Ctrl+Z/Y 되돌리기 · Del 창고 · Ctrl+D 복제 · Shift+클릭 다중 선택",
	confirmSell = "정말 팔까요? 산 값의 %d%%를 돌려받아요",
	notSaved = "⚠️ 지금은 저장이 안 되는 세션이에요 (테스트 서버)",
	exitHome = "집 밖으로 나와서 꾸미기를 마쳤어요",
	lightCap = "조명이 많아서 빛은 %d개까지만 켜져요",
	setProgress = "세트 %d/%d · 남은 금액 %s",
	setDone = "🎉 세트를 다 놓았어요!",
	insufficientTitle = "잔액이 부족해요",
	openBank = "💳 통장 보기",
	free = "무료",
	stock = "창고 %d개",
	priceFresh = "↩ 구매 취소 +%s",
	priceSell = "💰 팔기 +%s",
	room = "방",
	level = "층",
	stats = "⭐ %d · 🛋️ %d/%d",
	coopOn = "🤝 함께 꾸미기 중 · %s님의 집",
	coopGrant = "함께 꾸미기 허락",
	coopRevoke = "함께 꾸미기 해제",
	slotInfo = "기본 옵션 가구는 🛠️ 인테리어에서 바꿔요",
	like = "❤️ 좋아요",
	liked = "❤️ 좋아요를 보냈어요!",
	guestbook = "📝 방명록",
	gbWrite = "한 줄 남기기 (최대 60자)",
	gbSend = "남기기",
	gbEmpty = "아직 방명록이 없어요. 첫 글을 남겨 주세요!",
	inspect = "🔍 구경",
	visitors = "놀러 온 사람",
	photoTitle = "📸 집 사진",
	shutter = "찰칵",
	photoSaved = "📸 집 사진을 저장했어요 · SNS 업로드!",
	filters = { "기본", "따뜻하게", "필름", "야경", "흑백" },
	presetSave = "현재 배치 저장",
	presetLoad = "불러오기",
	presetEmpty = "빈 칸",
	presetDelete = "지우기",
	presetPlan = "창고 %d개 · 옮기기 %d개 · 새로 구매 %d개 (%s)",
	presetDefaultName = "프리셋 %d",
}

Text.TOAST = {
	placed = "%s 놓았어요",
	placedPaid = "%s 놓았어요 · -%s",
	stored = "📦 창고에 넣었어요",
	sold = "💰 팔았어요 · +%s",
	refunded = "↩ 구매를 취소했어요 · +%s",
	restored = "↶ 되돌렸어요",
	colored = "🎨 색을 바꿨어요",
	finished = "🎨 %s · %s",
	presetSaved = "💾 '%s' 저장했어요",
	presetLoaded = "✨ '%s' 배치를 불러왔어요%s",
	likedOwner = "❤️ %s님이 우리 집에 좋아요를 눌렀어요 (총 %d개)",
	gbOwner = "📝 %s님이 방명록을 남겼어요: %s",
	coopGranted = "🤝 %s님이 함께 꾸미기를 허락했어요",
	coopRevoked = "🤝 함께 꾸미기가 끝났어요",
}

-------------------------------------------------------------------------------------------------
-- Place kinds / categories copy
-------------------------------------------------------------------------------------------------
Text.PLACE = {
	floor = { name = "바닥", icon = "⬛" },
	surface = { name = "받침 위", icon = "🔲" },
	wall = { name = "벽걸이", icon = "🖼️" },
	ceiling = { name = "천장", icon = "💡" },
	rug = { name = "러그", icon = "🧶" },
}

Text.INTERACT = {
	sit = "앉기",
	lie = "눕기",
	lampOn = "불 켜기",
	lampOff = "불 끄기",
	lampColor = "빛 색 바꾸기",
	tvOn = "TV 켜기",
	tvOff = "TV 끄기",
	channel = "채널 바꾸기",
	musicOn = "음악 켜기",
	musicOff = "음악 끄기",
	nextTrack = "다음 곡",
	fireOn = "불 피우기",
	fireOff = "불 끄기",
	open = "열기",
	close = "닫기",
	feed = "먹이 주기",
	stand = "일어나기",
}

return Text
