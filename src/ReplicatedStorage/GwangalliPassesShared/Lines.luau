-- GwangalliPassesShared/Lines: every Korean UI / notice string of the pass add-on (string.format templates).
--   Lines.t(key, ...) -> string      unknown keys return the key itself

local Lines = {}

local L = {
	-- passes / store
	app_title = "VIP 패스",
	app_sub = "광안리 프리미엄 혜택",
	not_ready = "판매 준비 중이에요",
	not_ready_studio = "판매 준비 중 · Studio에서는 workspace 속성 GwPassesStudioTest 로 시험해 보세요",
	buy = "R$ %d 로 열기",
	buy_plain = "구매하기",
	owned = "보유 중",
	bought = "패스 구매 완료! 바로 적용됐어요 ✦",
	bought_body = "%s 혜택이 지금부터 적용돼요",
	locked = "🔒 %s 전용",
	locked_tab = "%s 패스가 있으면 쓸 수 있어요",
	loading = "불러오는 중…",
	offline = "서버와 연결이 끊겼어요. 잠시 후 다시 시도해 주세요",
	busy = "잠시 후 다시 시도해 주세요",
	feature_off = "이 기능은 지금 준비 중이에요",

	-- remote garage lock (no pass)
	gate_refuse = "🔒 내 차는 광안 오토 정비소에서만 부를 수 있어요 · 원격 차고 패스가 있으면 어디서든 OK",
	gate_banner = "🔒 원격 차고 잠김",
	gate_banner_body = "내 차는 광안 오토 정비소의 '차량 호출' 키오스크 근처에서만 부를 수 있어요",
	gate_open = "📍 정비소 차량 호출 구역 · 여기서는 바로 부를 수 있어요",
	gate_owner = "👑 원격 차고 · 어디서든 내 차를 부를 수 있어요",
	gate_route = "정비소 길찾기",
	gate_buy = "원격 차고 패스",
	station_title = "차량 호출",
	station_object = "광안 오토 정비소",
	station_sign = "🚗 차량 호출",
	station_sub = "내 차 · 렌트 차 바로 부르기",

	-- premium garage
	summon_here = "📍 바로 내 옆으로",
	summon_road = "🛣️ 도로로",
	summon_back = "↩️ 돌려보내기",
	summon_arrived = "%s 도착!",
	summon_side = "%dm 옆에 세워 뒀어요",
	summon_lane = "옆에 세울 자리가 없어서 %dm 떨어진 도로에 세워 뒀어요",
	summon_driving = "운전 중에는 차를 부를 수 없어요",
	summon_cooldown = "잠시 후 다시 불러 주세요 (%d초)",
	summon_state = "지금은 차를 부를 수 없어요",
	summon_fail = "차를 부르지 못했어요",
	summon_none = "부른 프리미엄 차가 없어요",
	summon_dismissed = "차를 차고로 돌려보냈어요",
	paint_saved = "도색을 바꿨어요",
	repair_title = "🔧 출장 정비",
	repair_done = "🔧 출장 정비 완료! %s 상태 100%% · %s",
	repair_money = "돈이 부족해요 (%s 필요)",
	repair_full = "이미 상태가 좋아요",
	repair_none = "정비할 수 있는 내 차가 없어요",
	repair_rental = "렌트 차는 정비소에서 관리해요",
	repair_confirm = "%s 를 %s 에 출장 정비할까요?",
	garage_mine = "내 차 출장 정비",
	garage_premium = "패스 전용 프리미엄",

	-- 편의 패스
	jail_cut = "⚡ 편의 패스 · 유치장 %s → %s",
	jail_next = "편의 패스 혜택은 다음 체포부터 적용돼요",
	ko_chip = "⚡ 편의 패스 · %d초 후 병원으로 이송돼요",
	ko_chip_ems = "⚡ 편의 패스 · 119가 오고 있어요 (최대 %d초)",
	ko_forced = "⚡ 편의 패스 · 대기 시간이 절반으로 줄어 병원으로 이송해요",

	-- black market
	market_title = "블랙마켓",
	market_ok = "🟢 보안 연결됨 · 거래 가능",
	market_police = "🚓 근처에 경찰이 있어 접속이 차단됐어요",
	market_swat = "🚨 특임대가 근처에 있어요",
	market_gunfire = "🔫 총소리가 나서 거래가 잠시 멈췄어요",
	market_chased = "🚔 경찰에 쫓기는 중엔 접속할 수 없어요",
	market_seated = "🚗 차에서 내려야 거래할 수 있어요",
	market_busy = "😵 지금은 앱을 쓸 수 없어요",
	market_inactive = "📵 블랙마켓 서버가 응답하지 않아요",
	market_grudge = "🚫 거래처가 당신과 거래를 끊었어요",
	market_fee = "📱 블랙마켓 접속료",
	market_money = "접속료가 부족해요 (%s)",
	market_footer = "총기상과 같은 물건 · 같은 가격 · 경찰/특임대 근처에선 접속이 막혀요",
	market_basic = "기본 총기",
	market_basic_sub = "권총 · 기관단총 · 산탄총",
	market_upper = "조직 물건",
	market_upper_sub = "상위 등급 · 마피아 전용 물건 포함",
	market_ammo = "탄약",
	market_ammo_sub = "가진 총에 맞는 탄약 상자",

	-- flex: plate
	plate_title = "나만의 번호판",
	plate_rule = "번호판은 %d~%d글자, 한글 · 숫자 · 영어만 쓸 수 있어요",
	plate_bad = "사용할 수 없는 번호판이에요",
	plate_taken = "이미 누가 쓰는 번호판이에요",
	plate_saved = "번호판을 바꿨어요! 다음에 부르는 차부터 달려요",
	plate_cleared = "번호판을 기본으로 되돌렸어요",
	plate_cooldown = "번호판은 %d초 뒤에 다시 바꿀 수 있어요",
	plate_filter = "확인 서버가 응답하지 않아요. 잠시 후 다시 시도해 주세요",
	plate_hint = "예: 12가 3456 · 광안 1004 · GW 7777",
	-- flex: neon / kofx
	neon_title = "네온 닉네임",
	neon_off = "끄기",
	neon_saved = "네온 닉네임을 바꿨어요",
	kofx_title = "KO 피니시 이펙트",
	kofx_saved = "피니시 이펙트를 바꿨어요",
	kofx_preview = "▶ 미리보기",
	kofx_banner = "K.O.!",
}

Lines.L = L

function Lines.t(key: string, ...: any): string
	local s = L[key]
	if s == nil then
		return key
	end
	if select("#", ...) > 0 then
		local ok, out = pcall(string.format, s, ...)
		return if ok then out else s
	end
	return s
end

-- "2분 30초" / "45초"
function Lines.dur(sec: number): string
	local s = math.max(0, math.floor(sec + 0.5))
	local m = s // 60
	local r = s % 60
	if m > 0 and r > 0 then
		return string.format("%d분 %d초", m, r)
	elseif m > 0 then
		return string.format("%d분", m)
	end
	return string.format("%d초", r)
end

return Lines
