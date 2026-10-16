-- GwangalliClinicShared/Config: 오너가 바꿀 수 있는 값 (광안 메디컬 의원 진료 보기 애드온).
-- 서버와 클라이언트가 같이 읽습니다. 가격·효과 중 "질병 치료 / 영양주사 / 건강검진" 은 기존 Health
-- 시스템(G.HEALTH)의 값을 그대로 씁니다 (여기서 바꾸지 않음). 여기 있는 돈은 이 애드온이 직접 받는
-- 추가 서비스(상담 진찰료 · 영양수액 추가 · 예방접종 · 퇴원 수속 미납금)만입니다.

local Config = {}

Config.Enabled = true -- false: 애드온 전체를 끕니다 (기존 병원 시트가 그대로 동작)
Config.Debug = false -- true: 서버/클라이언트 출력창에 진행 로그
Config.TakeOverLegacy = true -- 기존 HospitalPrompt("진료 받기"/"접수하기") 프롬프트를 끄고 이 애드온이 진료를 맡습니다
Config.PersistHealth = true -- 질병 · 미납금 · 위험도를 재접속해도 유지 (기존 프로필은 health 를 저장하지 않음)
Config.StudioMemoryOnly = false -- true: 스튜디오에서 DataStore 를 쓰지 않음

-- 병원 위치 (맵): Workspace 아래 경로. 못 찾으면 이름으로 한 번 검색합니다.
Config.Venue = {
	Path = { "Gwangalli", "hospital", "광안 메디컬 의원" },
	Name = "광안 메디컬 의원",
	Floor1 = 6.9, -- 1층 바닥 높이 (Y)
	Floor2 = 21.05, -- 2층 바닥 높이 (Y)
	-- 건물 안 판정 상자 (모델을 못 찾을 때 쓰는 값; 찾으면 모델 바운딩 박스를 씁니다)
	ZoneMin = Vector3.new(-575, 4, 264),
	ZoneMax = Vector3.new(-455, 38, 340),
	ZoneMargin = 3,
}

-- 진료과 (키오스크 버튼 순서). room = 진찰받는 곳, doctor = 진료 의사 이름
Config.Depts = {
	Order = { "im", "fm", "ped", "vac", "chk" },
	im = { name = "내과", icon = "🩺", sub = "감기 · 몸살 · 위염 · 피로", room = "c1" },
	fm = { name = "가정의학과", icon = "🌿", sub = "피로 · 영양주사 · 건강 상담", room = "c1" },
	ped = { name = "소아청소년과", icon = "🧸", sub = "학생 · 어린이 진료", room = "c1" },
	vac = { name = "예방접종", icon = "💉", sub = "인플루엔자 (독감)", room = "c1" },
	chk = { name = "건강검진", icon = "📋", sub = "2층 건강검진센터", room = "chk" },
}
Config.Doctor = { name = "김선생", title = "내과 전문의", room = "진료실 1 · 내과" }

-- 대기 (초). 실제 시간이 아니라 게임 템포에 맞춘 값입니다.
Config.Wait = {
	DeskBase = 3, -- 창구 호출까지 기본
	DeskPerAhead = 5, -- 앞 사람 1명당 (가상 환자 창구 처리 시간 평균)
	ConsultBase = 5, -- 진료 호출까지 기본
	ConsultPerAhead = 8, -- 앞 환자 1명당 (가상 환자 진료 시간 평균)
	UrgentFactor = 0.5, -- 위급 환자 (번아웃 · 쓰러지기 직전) 대기 배율
	CallTimeout = 60, -- 호출 후 이 시간 안에 안 오면 "보류" (순서 한 칸 뒤로)
	CallRepeat = 18, -- 호출 반복 간격
	MaxHolds = 2, -- 보류가 이만큼 쌓이면 접수 취소
	RegisterTimeout = 150, -- 창구에서 접수를 끝내야 하는 시간
	ConsultTimeout = 240, -- 진료실에서 아무 것도 안 하면 진료 종료
	MinConsult = 10, -- 진료실 입장 후 치료 계획을 고를 수 있기까지 최소 시간
	ExamGap = 1.0, -- 진찰 단계 사이 최소 간격 (서버 검증)
	GoTimeout = 180, -- 처치실 · 수납 · 약국으로 이동해야 하는 시간
	Dispense = 8, -- 약 조제 시간
	MoneyHold = 600, -- 잔액 부족으로 멈춘 진료를 다시 이어갈 수 있는 시간
}

-- 가상 환자 (병원이 살아 있는 느낌; 플레이어가 병원 안에 있을 때만 생김)
Config.Virtual = {
	Enabled = true,
	MaxDesk = 2, -- 창구 대기열에 동시에 있을 수 있는 가상 환자
	MaxConsult = 2, -- 진료 대기열 가상 환자
	SpawnEvery = { 22, 45 }, -- 새 가상 환자 간격 (초)
	DeskTime = { 4, 7 }, -- 가상 환자 창구 처리 시간
	ConsultTime = { 7, 11 }, -- 가상 환자 진료 시간
	PharmChance = 0.6, -- 가상 환자가 약국까지 가는 비율
	Names = { "김*수", "이*영", "박*민", "최*희", "정*호", "강*진", "윤*아", "장*우", "임*연", "한*석", "오*지", "서*준", "신*은", "권*혁", "황*라", "안*빈" },
}

-- 진료비 (이 애드온이 직접 받는 항목만; 질병 치료비 = G.HEALTH.KINDS[kind].fee, 영양주사 =
-- G.HEALTH.services.vitamin.fee, 건강검진 = G.HEALTH.services.checkup.fee 는 Health 가 받습니다)
Config.Fees = {
	ConsultFirst = 5500, -- 진찰료 · 초진 (영수증 표시 + 상담만 받을 때 실제 청구)
	ConsultRevisit = 4000, -- 진찰료 · 재진 (RevisitDays 안에 다시 오면)
	RevisitDays = 30,
	NightAddRate = 0.3, -- 야간·공휴일 가산 (진찰료의 30%)
	NightFrom = 18, -- 게임 시각 이 시 이후 ~
	NightTo = 9, -- ~ 이 시 이전 = 야간
	-- 질병 치료비(Health 가 받는 총액)를 영수증 항목으로 나눌 때 원내 약제비 비율 (나머지 = 주사료/처치료)
	PharmShare = { cold = 0.6, ache = 0.4, gastritis = 0.35, burnout = 0.15 },
	InsurerRatio = 7 / 3, -- 영수증 표시용 공단부담금 = 본인부담금 x 이 값 (급여 항목)
	IVExtra = 12000, -- 영양수액 추가 (비급여, 수납 창구에서 결제)
	Vaccine = 35000, -- 인플루엔자 예방접종 (비급여)
	VaccineName = "인플루엔자 예방접종 (3가)",
	DefaultMethod = "card", -- 결제수단 기본값: "card" (통장 체크카드) | "cash" (현금)
}

-- 처치 효과 (Health.rest 로 피로도를 줄이는 추가분; 질병 완치 · 피로 -50 · 영양주사 -40 은 Health 몫)
Config.Treat = {
	IVSeconds = 30, -- 질병 수액 (위염 · 번아웃 처방에 포함)
	IVExtraSeconds = 45, -- 영양수액 추가
	IVIncludedRest = 8, -- 처방에 포함된 수액: 누워 있는 동안 피로도 추가 회복
	IVExtraRest = 18, -- 영양수액 추가: 피로도 추가 회복
	NapSpeed = 3, -- "눈 붙이기": 수액이 이 배속으로 들어감
	NapMinSeconds = 12,
	SliceEvery = 5, -- 이 간격(초)마다 회복분을 조금씩 적용 (중간에 일어나도 받은 만큼은 유지)
	InjectSeconds = 3.2, -- 예방접종 주사 연출 (질병/영양 주사는 Health 연출을 그대로 씀)
	CounselRiskFactor = 0.5, -- 상담만: 질병 위험도 x 이 값
	VaccineHours = 2, -- 예방접종 면역 시간 (실제 시간)
	VaccineRiskDamp = 0.5, -- 면역 동안 일하면서 쌓이는 위험도의 이 비율을 깎아 줌
	CollapseGrace = 180, -- 병원 안에서 접수한 환자는 쓰러지기까지 최소 이 시간(초)을 남겨 둠
	UnpaidGrace = 60, -- 수납 전에 병원을 떠나면 이 시간 뒤 미납금으로 처리
}

-- 복약 (약국에서 받은 약: 실제 효과)
Config.Meds = {
	Doses = 3, -- 처방 횟수
	Every = 150, -- 다음 복용까지 (실제 초)
	Window = 1800, -- 이 시간 안에 안 먹으면 그 회차는 건너뜀
	Rest = 5, -- 1회 복용: 피로도 -5 (Health.rest)
	Risk = 10, -- 1회 복용: 질병 위험도 -10 (Health API setRisk)
	FinishHappiness = 2, -- 끝까지 다 먹으면 행복 +2
}

-- 건강검진 코스 (2층)
Config.Checkup = {
	Stations = { "height", "bp", "eye", "ear", "ecg" },
	MinStation = 3.5, -- 각 검사 최소 시간 (서버 검증)
	StationTimeout = 60,
	CourseTimeout = 900,
	EyeRows = { 0.3, 0.5, 0.7, 0.9, 1.0, 1.2, 1.5 }, -- 시력표 줄 (작아질수록 높은 시력)
	EarTones = 6, -- 청력 검사 신호음 수 (좌/우 무작위)
	HappinessOncePerDay = 3, -- 결과 상담 후 행복 +3 (하루 한 번)
}

-- 입원실 · 병실 휴식
Config.Ward = {
	RestEnabled = true,
	RestEvery = 6, -- 이 간격(초)마다 피로도 -1 (Health.rest)
	RestMaxPerStay = 25, -- 한 번 누워서 회복할 수 있는 최대치
	RestCooldown = 600, -- 다음 병실 휴식까지 (초)
	CallCooldown = 20, -- 간호사 호출 버튼
	CallHappiness = 1, -- 누워 있을 때 간호사가 물을 가져다주면 행복 +1 (10분에 한 번)
}

-- 편의 패스 (GwangalliPasses "qol"): 대기 시간 단축
Config.Pass = { Key = "qol", WaitFactor = 0.5, Label = "⚡ 편의 패스 · 대기 50% 단축" }

-- 직원 (이 애드온이 세우는 NPC; 김선생 · 박선생은 맵에 있는 기존 리그)
Config.Staff = {
	Enabled = true,
	desk1 = { name = "원무과 김주임", role = "desk", shirt = { 40, 62, 104 }, pants = { 38, 40, 48 }, body = "f", skin = { 240, 204, 176 } },
	desk2 = { name = "원무과 이주임", role = "desk", shirt = { 40, 62, 104 }, pants = { 38, 40, 48 }, body = "m", skin = { 228, 188, 154 } },
	nurse2 = { name = "간호사 최선생", role = "nurse", shirt = { 120, 196, 196 }, pants = { 120, 196, 196 }, body = "f", skin = { 238, 200, 170 } },
	pharm = { name = "약사 정약사", role = "pharm", shirt = { 246, 246, 246 }, pants = { 60, 64, 76 }, body = "m", skin = { 232, 194, 160 } },
	check = { name = "검진센터 한선생", role = "check", shirt = { 92, 168, 172 }, pants = { 92, 168, 172 }, body = "f", skin = { 242, 206, 178 } },
}

-- 기존 실내 장식 팀(GwangalliBuildingInterior) 과 겹치는 것들
Config.Interior = {
	Folder = "GwInteriorDetailLocal",
	SuppressAlways = { "번호표 뽑기" }, -- 이 애드온이 진짜 번호표를 뽑으므로 장식 프롬프트는 끔
	SuppressDuringCheckup = { "키 · 몸무게 재기", "시력 검사", "청력 검사" }, -- 내 검진 코스 중에만 끔
	-- 장식 팀이 만든 글자판 (파트 이름 -> 우리 화면 종류). 그 SurfaceGui("Gw"..이름) 는 끄고 우리 것을 덮어 씀
	Screens = { CallBoardNo = "callno", WaitScreen = "wait", WaitMonitorText = "door", KioskScreen = "kiosk" },
	ScreenAttribute = "GwClinicScreen", -- 이 속성이 있는 파트 (값 = "call" | "wait" | "door" | "rx" | "kiosk") 를 1순위로 씀
}

-- 소리 (Roblox 기본 내장 소리만)
Config.Sounds = {
	Ding = "rbxasset://sounds/electronicpingshort.wav",
	Tap = "rbxasset://sounds/clickfast.wav",
	Swoosh = "rbxasset://sounds/swoosh.wav",
	Volume = 0.5,
}

-- 원격 요청 속도 제한 (초당 토큰, 최대 버스트)
Config.Rate = {
	ui = { rate = 5, burst = 12 },
	act = { rate = 2, burst = 5 },
	money = { rate = 0.8, burst = 2 },
}

-- 거리 (스터드): 이 안에 있어야 해당 동작이 서버에서 통과
Config.Reach = {
	Kiosk = 11,
	Window = 11,
	Seat = 14,
	Bed = 12,
	Pharmacy = 12,
	Station = 12,
	CheckDesk = 12,
	Ward = 10,
}

return Config
