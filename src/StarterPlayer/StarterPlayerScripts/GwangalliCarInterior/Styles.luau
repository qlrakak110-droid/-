--!strict
-- GwangalliCarInterior/Styles: 차종별 실제 실내 사양 (현대·기아·제네시스 공식 자료 + 시승기 기준, 2019~2023 국내형).
-- 고르는 순서: 차 모델의 InteriorStyle 속성 (키 직접 지정) > CarModel 속성 / 모델 이름 > VehicleKind.
-- 새 차종을 넣을 때: 외부 모델에 CarModel = "Hyundai Sonata (DN8)" 처럼 이름만 있으면 같은 실내가 붙습니다.
--
--   wheel   핸들 스포크 (vee4: 쏘나타 4스포크 역V · u4: 투싼/카니발 아래 두 스포크가 가깝게 · two: G80 2스포크 ·
--           three: 레이 3스포크 · bus2: 포터 2스포크 버스형), hub 에어백 크기, paddles 패들시프트
--   cluster 계기판 (digital / analog 실물 바늘), hood 차양 (slim · short · none · deep · brow)
--   center  가운데 화면 (float 대시 위 태블릿 · flush G80 낮고 넓게 · stack 투싼 세로 스택 맨 위 ·
--           pod 레이 돌출 스택 · fascia 포터/쏠라티 센터페시아 · joined 카니발 한 장 유리)
--   vents · climate · shifter · console · garnish · speaker · seat · extras (차마다 다른 부분)

local Styles = {}

local function hex(s: string): Color3
	local h = string.gsub(s, "#", "")
	return Color3.fromRGB(tonumber(string.sub(h, 1, 2), 16) or 0, tonumber(string.sub(h, 3, 4), 16) or 0, tonumber(string.sub(h, 5, 6), 16) or 0)
end

local LIST: { [string]: any } = {}

-- 현대 쏘나타 DN8 (2019~2023): 스텔스 날개형 낮은 대시 + 문에서 문까지 새틴 크롬 라인, 12.3" 계기판 차양이
-- S자로 흘러 10.25" 플로팅 화면으로 이어짐, 화면 바로 아래 가로 송풍구 2개 + 비상등, 버튼식 P/R/N/D 세로 배열,
-- 다이아몬드 널링 온도 다이얼 2개, 4스포크(아래 두 스포크 역V) 핸들, 보스 스피커.
LIST.sonata = {
	key = "sonata",
	label = "Hyundai Sonata (DN8)",
	brand = "hyundai",
	wheel = { spokes = "vee4", hub = Vector3.new(0.5, 0.4, 0.18), sideTrim = true, lowerTrim = "satin", paddles = false },
	cluster = { kind = "digital", hood = "slim", w = 1.22, h = 0.44, speedMax = 260, rpmMax = 8 },
	center = { kind = "float", w = 1.02, h = 0.4 },
	sCurve = true,
	vents = "twin_h",
	sideVent = "slim",
	climate = "knurl",
	shifter = "buttons_col",
	console = "full",
	garnish = "line",
	speaker = "bose",
	seat = { insert = "perf", bolster = 1 },
	hud = true,
	startButton = true,
	ambient = true,
	trimMat = "alu",
	colors = {
		dash = hex("#1d1e20"),
		seat = hex("#232325"),
		stitch = hex("#4a4a4c"),
		trim = hex("#a9adb2"),
		liner = hex("#c8c4bc"),
		ambient = hex("#4aa3ff"),
		wheel = hex("#1a1a1a"),
	},
}

-- 쏘나타 LPi 택시 / 순찰차: 같은 대시에 아날로그 2눈 계기판(속도·RPM 바늘 + 4.2" LCD), 8" 화면,
-- 일반 6단 기어 레버 (버튼식 아님), 천/인조가죽 시트, 앰비언트 없음.
LIST.sonata_taxi = {
	key = "sonata_taxi",
	label = "Hyundai Sonata (DN8) LPi Taxi",
	brand = "hyundai",
	wheel = { spokes = "vee4", hub = Vector3.new(0.5, 0.4, 0.18), sideTrim = true, lowerTrim = "satin", paddles = false },
	cluster = { kind = "analog", hood = "slim", w = 1.22, h = 0.44, speedMax = 260, rpmMax = 8 },
	center = { kind = "float", w = 0.86, h = 0.36 },
	sCurve = true,
	vents = "twin_h",
	sideVent = "slim",
	climate = "knurl",
	shifter = "lever",
	console = "full",
	garnish = "line",
	speaker = "plain",
	seat = { insert = "fabric", bolster = 0.8 },
	hud = false,
	startButton = true,
	ambient = false,
	trimMat = "alu",
	colors = {
		dash = hex("#1d1e20"),
		seat = hex("#2a2b2e"),
		stitch = hex("#4a4a4c"),
		trim = hex("#9fa3a8"),
		liner = hex("#c8c4bc"),
		ambient = hex("#4aa3ff"),
		wheel = hex("#1c1c1d"),
	},
}

-- 제네시스 G80 RG3 (2020~2023): "여백의 미" 낮고 넓은 수평 대시, 전폭 한 줄 헤어라인 송풍구 + 크롬 립,
-- 오픈 포어 애쉬 우드 띠(문까지), 우드 아래 매달린 공조 패널 + 널링 금속 다이얼, 대시에 낮게 박힌 14.5" 초광폭 화면,
-- 짧은 가죽 차양의 12.3" 3D 계기판, 우드 콘솔 위 크롬 변속 다이얼 + 그 뒤 조그 다이얼, 2스포크 핸들 + 날개 엠블럼,
-- 다이아몬드 퀼팅 나파 시트 (블랙 대시 + 베이지 시트 투톤), 렉시콘 메탈 메쉬 스피커.
LIST.g80 = {
	key = "g80",
	label = "Genesis G80 (RG3)",
	brand = "genesis",
	wheel = { spokes = "two", hub = Vector3.new(0.62, 0.4, 0.2), sideTrim = false, paddles = true },
	cluster = { kind = "digital", hood = "short", w = 1.2, h = 0.42, speedMax = 260, rpmMax = 8 },
	center = { kind = "flush", w = 1.42, h = 0.5 },
	vents = "hairline",
	sideVent = "hairline",
	climate = "hang",
	shifter = "dial_wood",
	console = "full",
	garnish = "wood",
	speaker = "lexicon",
	seat = { insert = "quilt", bolster = 0.9 },
	hud = true,
	startButton = true,
	ambient = true,
	trimMat = "wood",
	colors = {
		dash = hex("#1b1a19"),
		lower = hex("#2a2826"),
		seat = hex("#cbb89a"),
		insert = hex("#d6c5a8"),
		stitch = hex("#a8916f"),
		trim = hex("#6b5440"),
		door = hex("#cbb89a"),
		liner = hex("#cfc7ba"),
		ambient = hex("#ffd7a0"),
		wheel = hex("#1c1b1a"),
	},
}

-- 현대 투싼 NX4 (2021~2023): 인터스페이스 대시, 차양 없는 10.25" 플로팅 계기판(유리판), 피아노 블랙 세로
-- 센터 스택 맨 위 10.25" 화면 + 양옆 세로 송풍구, 버튼 없는 터치 공조, 문에서 대시를 지나 스택 양옆으로 흘러내리는
-- 새틴 두 줄(워터폴), 숨은 슬롯 송풍구, 버튼식 P/R/N/D 가로 배열, 4스포크(아래 두 스포크가 가깝게 + 새틴).
LIST.tucson = {
	key = "tucson",
	label = "Hyundai Tucson (NX4)",
	brand = "hyundai",
	wheel = { spokes = "u4", hub = Vector3.new(0.6, 0.38, 0.18), sideTrim = false, lowerTrim = "satin", paddles = true },
	cluster = { kind = "digital", hood = "none", w = 1.12, h = 0.4, speedMax = 260, rpmMax = 8 },
	center = { kind = "stack", w = 1.0, h = 0.4 },
	vents = "stack_v",
	sideVent = "slot",
	climate = "touch",
	shifter = "buttons_row",
	console = "full",
	garnish = "waterfall",
	speaker = "bose",
	seat = { insert = "hstitch", bolster = 1 },
	hud = false,
	startButton = true,
	ambient = true,
	trimMat = "alu",
	colors = {
		dash = hex("#1c1c1e"),
		lower = hex("#34353a"),
		seat = hex("#232325"),
		stitch = hex("#6b6b70"),
		trim = hex("#b8bbc0"),
		liner = hex("#cfcbc4"),
		ambient = hex("#5aa8ff"),
		wheel = hex("#1a1a1a"),
	},
}

-- 기아 레이 TAM (2022 더 뉴 기아 레이): 박스형 서 있는 대시, 메탈 베젤 돌출 센터 스택(맨 위 8" 화면 + 양옆
-- 세로 송풍구 → 비상등 → 대시 기어 레버 → 3다이얼 공조), 콘솔 없는 워크스루 바닥, 작은 차양 아날로그 2눈 + 4.2" LCD,
-- 3스포크(아래 스포크 하이글로시) + 새 기아 로고, 둥근 사각 끝 송풍구.
LIST.ray = {
	key = "ray",
	label = "Kia Ray (TAM)",
	brand = "kia",
	wheel = { spokes = "three", hub = Vector3.new(0.44, 0.36, 0.17), sideTrim = false, lowerTrim = "gloss", paddles = false },
	cluster = { kind = "analog", hood = "deep", w = 1.06, h = 0.42, speedMax = 200, rpmMax = 8 },
	center = { kind = "pod", w = 0.84, h = 0.36 },
	vents = "pod_v",
	sideVent = "round",
	climate = "dials3",
	shifter = "dash_lever",
	console = "none",
	garnish = "none",
	speaker = "plain",
	seat = { insert = "plain", bolster = 0.6 },
	hud = false,
	startButton = true,
	ambient = false,
	trimMat = "black",
	colors = {
		dash = hex("#1a1a1b"),
		lower = hex("#232325"),
		seat = hex("#2b2b2d"),
		stitch = hex("#3a3a3c"),
		trim = hex("#0e0e10"),
		liner = hex("#c9c5bc"),
		ambient = hex("#4aa3ff"),
		wheel = hex("#1a1a1a"),
	},
}

-- 기아 카니발 KA4 (2021~2023): 12.3" 계기판 + 12.3" 내비가 한 장 유리(파노라믹), 계기판 쪽만 짧은 차양,
-- 화면 아래 금속 가니시 띠에 슬롯 송풍구 2 + 비상등, 그 아래 우드그레인 띠, 터치 인포테인먼트 · 공조 띠,
-- 높고 넓은 콘솔의 널링 변속 다이얼, 2열 VIP 캡틴 시트(윙 헤드레스트 · 레그레스트), 크렐 스피커.
LIST.carnival = {
	key = "carnival",
	label = "Kia Carnival (KA4)",
	brand = "kia",
	wheel = { spokes = "u4", hub = Vector3.new(0.6, 0.38, 0.18), sideTrim = false, lowerTrim = "gloss", paddles = true },
	cluster = { kind = "digital", hood = "brow", w = 1.22, h = 0.44, speedMax = 260, rpmMax = 8 },
	center = { kind = "joined", w = 1.22, h = 0.44 },
	vents = "garnish",
	sideVent = "slot",
	climate = "touch_knobs",
	shifter = "dial",
	console = "full",
	garnish = "metal_wood",
	speaker = "krell",
	seat = { insert = "hstitch", bolster = 0.9, captains = true },
	hud = false,
	startButton = true,
	ambient = true,
	trimMat = "alu",
	colors = {
		dash = hex("#1c1c1e"),
		seat = hex("#2a2a2c"),
		stitch = hex("#5c5c60"),
		trim = hex("#a7abb0"),
		wood = hex("#4a3a2e"),
		liner = hex("#c9c4ba"),
		ambient = hex("#9ec5ff"),
		wheel = hex("#1c1c1e"),
	},
}

-- 현대 포터 II (1톤 트럭): 캡오버의 서 있는 대시 + 전폭 평평한 수납 트레이, 차콜/회색 투톤 하드 플라스틱,
-- 둥근 차양 세미 아날로그 2눈 + 3.5" LCD, 센터페시아(위 송풍구 2 → 8" 화면 → 3다이얼 공조),
-- 버스처럼 눕힌 2스포크 큰 허브 핸들, 바닥에서 올라온 긴 수동 기어 + 고무 부츠, 3인 벤치 캡.
LIST.porter = {
	key = "porter",
	label = "Hyundai Porter II",
	brand = "hyundai",
	wheel = { spokes = "bus2", hub = Vector3.new(0.56, 0.48, 0.2), sideTrim = false, paddles = false },
	cluster = { kind = "analog", hood = "deep", w = 1.1, h = 0.44, speedMax = 180, rpmMax = 6 },
	center = { kind = "fascia", w = 0.84, h = 0.36 },
	vents = "top_rect",
	sideVent = "round",
	climate = "dials3",
	shifter = "manual",
	console = "none",
	garnish = "none",
	speaker = "plain",
	seat = { insert = "fabric", bolster = 0.5 },
	hud = false,
	startButton = false,
	ambient = false,
	trimMat = "plastic",
	extras = { tray = true },
	colors = {
		dash = hex("#3a3c40"),
		lower = hex("#6a6d72"),
		seat = hex("#45474b"),
		stitch = hex("#5a5c60"),
		trim = hex("#8a8d92"),
		door = hex("#6a6d72"),
		liner = hex("#c4c2bc"),
		ambient = hex("#4aa3ff"),
		wheel = hex("#2a2b2d"),
	},
}

-- 현대 쏠라티 H350 119 구급차 운전석: 깊고 서 있는 밴 대시 + 위에 뚜껑 달린 수납함, 은색 프레임 센터 스택(8" 화면 +
-- 양옆 세로 사다리꼴 송풍구 → 3다이얼), 깊은 차양 2눈 + LCD, 대시에 붙은 기어 포드(운전자 오른쪽 무릎 옆),
-- 4스포크 밴 핸들, 사이렌 · 경광등 조작 박스 + 무전기.
LIST.solati = {
	key = "solati",
	label = "Hyundai Solati H350 119",
	brand = "hyundai",
	wheel = { spokes = "u4", hub = Vector3.new(0.52, 0.4, 0.18), sideTrim = false, lowerTrim = nil, paddles = false },
	cluster = { kind = "analog", hood = "deep", w = 1.14, h = 0.46, speedMax = 180, rpmMax = 6 },
	center = { kind = "fascia", w = 0.84, h = 0.36 },
	vents = "trap_v",
	sideVent = "rect",
	climate = "dials3",
	shifter = "dash_pod",
	console = "none",
	garnish = "none",
	speaker = "plain",
	seat = { insert = "fabric", bolster = 0.5, armrest = true },
	hud = false,
	startButton = false,
	ambient = false,
	trimMat = "plastic",
	extras = { bins = true, siren = true },
	colors = {
		dash = hex("#2e2f31"),
		lower = hex("#5d6064"),
		seat = hex("#2b2b2d"),
		stitch = hex("#4a4a4c"),
		trim = hex("#8e9196"),
		door = hex("#5d6064"),
		liner = hex("#b8b8b2"),
		ambient = hex("#4aa3ff"),
		wheel = hex("#232325"),
	},
}

Styles.LIST = LIST

-- 이름 매칭 (소문자, 위에서부터: 택시·순찰차가 쏘나타보다 먼저)
local MATCH: { { string } } = {
	{ "taxi", "sonata_taxi" },
	{ "택시", "sonata_taxi" },
	{ "police", "sonata_taxi" },
	{ "경찰", "sonata_taxi" },
	{ "순찰", "sonata_taxi" },
	{ "g80", "g80" },
	{ "genesis", "g80" },
	{ "제네시스", "g80" },
	{ "rg3", "g80" },
	{ "sonata", "sonata" },
	{ "쏘나타", "sonata" },
	{ "소나타", "sonata" },
	{ "dn8", "sonata" },
	{ "tucson", "tucson" },
	{ "투싼", "tucson" },
	{ "nx4", "tucson" },
	{ "%f[%w]ray%f[%W]", "ray" },
	{ "레이", "ray" },
	{ "carnival", "carnival" },
	{ "카니발", "carnival" },
	{ "ka4", "carnival" },
	{ "porter", "porter" },
	{ "포터", "porter" },
	{ "solati", "solati" },
	{ "쏠라티", "solati" },
	{ "솔라티", "solati" },
	{ "h350", "solati" },
	{ "119", "solati" },
	{ "ambulance", "solati" },
	{ "구급", "solati" },
}

local KIND: { [string]: string } = {
	sedan = "sonata",
	taxi = "sonata_taxi",
	taxi_service = "sonata_taxi",
	police = "sonata_taxi",
	luxury = "g80",
	suv = "tucson",
	compact = "ray",
	van = "carnival",
	truck = "porter",
	ambulance = "solati",
}

local function byName(s: string?): string?
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local low = string.lower(s)
	for _, m in MATCH do
		if string.find(low, m[1]) then
			return m[2]
		end
	end
	return nil
end

-- 반환: 스타일 표 (공유 표이므로 바꾸지 말 것)
function Styles.resolve(model: Model, kind: string?): any
	local forced = model:GetAttribute("InteriorStyle")
	if type(forced) == "string" and LIST[forced] then
		return LIST[forced]
	end
	-- 택시·순찰차는 차종 이름보다 용도(VehicleKind)가 우선 (예: CarModel = "Hyundai Sonata (DN8)" + VehicleKind = "police")
	if kind == "taxi" or kind == "taxi_service" or kind == "police" then
		return LIST.sonata_taxi
	end
	local key = byName(model:GetAttribute("CarModel") :: any) or byName(model.Name) or (kind and KIND[kind]) or "sonata"
	return LIST[key] or LIST.sonata
end

return Styles
