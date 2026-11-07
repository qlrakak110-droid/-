--!strict
-- SeoulSkyline / Config
-- 한강 잠실 야경 맵(롯데월드타워 모티브) 공용 설정: 좌표계, 레이아웃, 팔레트, 품질 옵션.
--
-- ── 좌표계 (studs) ───────────────────────────────────────────────────────────────────────────────
--   * 수면(Terrain Water 윗면) = Y 0.  강은 X 축을 따라 흐르고 강 중심선 = Z 0.
--   * 먼 쪽 강변(잠실, 도시/타워 쪽) = -Z.  가까운 쪽 강변(전망대·공원, 플레이어 스폰) = +Z.
--   * 대표 구도(히어로 카메라)는 +Z 강변에서 -Z 를 바라봄 → 화면 오른쪽 = +X, 왼쪽 = -X.
--   * 해는 -X 쪽으로 진다(Roblox 태양 모델): 화면 왼쪽 지평선이 노을빛.
--   * 1 stud ≈ 0.5 m 정도의 "압축 스케일": 강폭 840, 타워 높이 ~1000(+첨탑).
--
-- 모듈은 숫자를 하드코딩하지 말고 여기 값을 읽어 주세요(레이아웃이 바뀌어도 전체가 맞물리도록).

local Config = {}

Config.VERSION = "1.0.0"
Config.ROOT_NAME = "SeoulSkyline" -- Workspace 아래 맵 모델 이름
Config.SEED = 20260507 -- 결정적 생성: 같은 시드 → 항상 같은 맵

------------------------------------------------------------------------------------------------------
-- 품질 / 성능
------------------------------------------------------------------------------------------------------
Config.Quality = {
	-- 0.5 ~ 1.5 : 아파트·도시 카펫 밀도 배율 (모바일 대상이면 0.7 권장)
	Density = 1.0,
	-- 실제 광원(PointLight/SpotLight/SurfaceLight) 상한. 나머지 조명은 Neon 발광으로만 표현.
	MaxLights = 140,
	-- 작은 장식 파트는 그림자를 끔(이 크기 미만의 최대 변 길이)
	ShadowMinSize = 12,
	-- 빌드 중 task.wait() 간격(파트 수). 서버/커맨드 바 타임아웃 방지.
	YieldEvery = 600,
}

------------------------------------------------------------------------------------------------------
-- 레벨(높이) — 모든 모듈 공통
------------------------------------------------------------------------------------------------------
Config.Level = {
	Water = 0, -- 수면
	RiverBed = -24, -- 강바닥 (지형 복셀 4 stud 격자에 맞춤)
	Promenade = 3, -- 한강공원 둔치(산책로·잔디) 높이
	Levee = 14, -- 제방 위 도로(강변북로/올림픽대로)와 도시 지면
	City = 14, -- 도시 블록 지면
}

------------------------------------------------------------------------------------------------------
-- 강 / 강변 띠 (Z 범위, 작은 값 → 큰 값)
------------------------------------------------------------------------------------------------------
Config.River = {
	HalfWidth = 420, -- 수면: Z -420 ~ +420
	XMin = -7000, -- 강물이 이어지는 X 범위(지평선까지 보이도록 넉넉히)
	XMax = 7000,
}

-- 먼 쪽(잠실) 강변: 수면 끝 → 둔치 공원 → 제방 사면 → 올림픽대로 → 도시
Config.FarBank = {
	WaterEdge = -420, -- 수면 경계 (계단식 호안)
	ParkFrom = -420, -- 둔치 공원 Z (Promenade 높이)
	ParkTo = -520,
	SlopeTo = -545, -- 제방 사면 끝(Levee 높이)
	RoadFrom = -545, -- 올림픽대로(왕복 8차로)
	RoadTo = -600,
	CityFrom = -620, -- 도시 시작
	CityTo = -6800, -- 지평선 도시 끝
}

-- 가까운 쪽(관람자) 강변: 수면 끝 → 산책로/잔디/숲 → 제방 사면 → 강변북로 → 도시(배경)
Config.NearBank = {
	WaterEdge = 420,
	ParkFrom = 420,
	ParkTo = 760, -- 넓은 한강공원(숲·잔디·전망대)
	SlopeTo = 790,
	RoadFrom = 790, -- 강변북로
	RoadTo = 845,
	CityFrom = 870,
	CityTo = 5200,
}

------------------------------------------------------------------------------------------------------
-- 주요 랜드마크 배치
------------------------------------------------------------------------------------------------------
Config.Landmark = {
	-- 롯데월드타워 모티브 초고층 (정사각 평면, 위로 갈수록 곡선으로 가늘어짐)
	Tower = {
		Center = Vector3.new(-430, 14, -1180),
		BaseWidth = 190, -- 지상부 한 변
		TopWidth = 64, -- 크라운 시작부 한 변
		Height = 980, -- 본체(크라운 시작) 높이, 지면 기준
		CrownHeight = 120, -- 랜턴 크라운
		SpireHeight = 60, -- 첨탑
		Yaw = 34, -- 평면 회전(도) — 모서리가 카메라 쪽을 향하는 다이아몬드 실루엣 (45 이면 노을 해가 면에 정반사되어 번짐)
	},
	-- 저층부 몰(타워 앞 오른쪽): 곡면 지붕 파란 조명 건물 포함
	Mall = {
		Min = Vector2.new(-360, -1060), -- (X, Z)
		Max = Vector2.new(60, -820),
	},
}

-- 다리(잠실대교 모티브): 강을 수직(Z 방향)으로 가로지름
Config.Bridge = {
	X = 250, -- 중심선 X (대표 구도에서 다리가 오른쪽 아래 → 타워 발치 쪽으로 대각선으로 보이도록)
	ZFrom = -640, -- 먼 쪽 도시 도로와 연결
	ZTo = 900, -- 가까운 쪽 도시 도로와 연결
	DeckTop = 34, -- 상판 윗면 높이 (수면 위)
	Width = 72, -- 차도 8차로 + 보도
	PierSpacing = 96,
}

-- 관람 전망대(스폰) — 사진 구도를 재현하는 위치
Config.Viewpoint = {
	-- 전망대 바닥(플레이어가 서는 곳)
	DeckCenter = Vector3.new(-40, 0, 700), -- Y 는 Park 모듈이 DeckHeight 로 결정
	DeckHeight = 120,
	-- 히어로 카메라(사진 구도). 포토 스팟/인트로에서 사용.
	HeroCamPos = Vector3.new(80, 205, 860),
	HeroCamLook = Vector3.new(-120, 230, -1000),
	HeroFov = 62,
}

------------------------------------------------------------------------------------------------------
-- 구역 분할 (도시 생성기들이 겹치지 않도록 Kit.reserve 로 발자국을 예약)
--   Landmark → Skyline → Bridge/Riverside/Park → Apartments → CityCarpet 순서로 빌드됨.
------------------------------------------------------------------------------------------------------
Config.Zones = {
	-- 먼 쪽 강변의 "히어로" 고층 클러스터 (Skyline 모듈)
	SkylineLeft = { XMin = -1700, XMax = -760, ZMin = -1500, ZMax = -760 },
	SkylineMid = { XMin = -250, XMax = 140, ZMin = -1750, ZMax = -1180 },
	SkylineRight = { XMin = 180, XMax = 1050, ZMin = -1350, ZMax = -720 },
	-- 아파트 단지 띠 (Apartments 모듈) — 먼 쪽 / 가까운 쪽
	ApartmentsFar = { XMin = -4200, XMax = 4200, ZMin = -2300, ZMax = -640 },
	ApartmentsNear = { XMin = -3200, XMax = 3200, ZMin = 880, ZMax = 1900 },
	-- LOD 도시 카펫 (CityCarpet 모듈)
	CarpetFarMid = { XMin = -6500, XMax = 6500, ZMin = -4000, ZMax = -2300 },
	CarpetFarFar = { XMin = -9000, XMax = 9000, ZMin = -6800, ZMax = -4000 },
	CarpetNear = { XMin = -6000, XMax = 6000, ZMin = 1900, ZMax = 5200 },
	-- 원경 산 능선
	MountainsFar = { XMin = -11000, XMax = 11000, Z = -8200 },
	MountainsNear = { XMin = -9000, XMax = 9000, Z = 6400 },
}

------------------------------------------------------------------------------------------------------
-- 팔레트 (해질녘 블루아워). Neon 색은 밝기 = 발광 세기이므로 어두운 Neon 색 = 은은한 불빛.
------------------------------------------------------------------------------------------------------
local rgb = Color3.fromRGB
Config.Palette = {
	-- 실내 조명(창문) — Neon
	WindowWarm = rgb(255, 196, 120),
	WindowWarmDim = rgb(178, 128, 74),
	WindowCool = rgb(214, 228, 255),
	WindowCoolDim = rgb(128, 146, 178),
	WindowGold = rgb(255, 214, 140),
	WindowOff = rgb(28, 34, 46), -- 꺼진 창 (Glass)
	-- 유리 커튼월
	GlassDeep = rgb(38, 56, 82),
	GlassBlue = rgb(70, 104, 140),
	GlassSilver = rgb(150, 172, 196),
	GlassTeal = rgb(52, 88, 96),
	GlassBronze = rgb(92, 76, 62),
	Mullion = rgb(52, 58, 68),
	MullionLight = rgb(176, 184, 194),
	-- 콘크리트 / 아파트
	ConcreteLight = rgb(214, 208, 198),
	ConcreteWarm = rgb(196, 184, 168),
	ConcreteGrey = rgb(150, 150, 152),
	ConcreteDark = rgb(92, 94, 100),
	Asphalt = rgb(46, 48, 52),
	AsphaltLight = rgb(70, 72, 76),
	LaneWhite = rgb(214, 214, 206),
	LaneYellow = rgb(232, 184, 64),
	-- 자연
	Grass = rgb(66, 98, 52),
	GrassDark = rgb(46, 74, 40),
	Leaf1 = rgb(48, 84, 44),
	Leaf2 = rgb(64, 102, 50),
	Leaf3 = rgb(86, 116, 58),
	LeafAutumn = rgb(150, 112, 58),
	Bark = rgb(74, 58, 46),
	Soil = rgb(92, 80, 66),
	Mountain = rgb(44, 56, 66),
	MountainFar = rgb(70, 82, 102),
	-- 조명 / 포인트
	LampWarm = rgb(255, 206, 140),
	LampSodium = rgb(255, 170, 84),
	LampWhite = rgb(236, 242, 255),
	Headlight = rgb(255, 246, 226),
	Taillight = rgb(255, 46, 36),
	Beacon = rgb(255, 30, 24),
	LedBlue = rgb(70, 150, 255),
	LedCyan = rgb(80, 220, 255),
	LedMagenta = rgb(220, 90, 255),
	LedGold = rgb(255, 196, 92),
}

------------------------------------------------------------------------------------------------------
-- 조명 / 대기 (해질녘 직후). Atmosphere 모듈이 적용.
------------------------------------------------------------------------------------------------------
Config.Lighting = {
	ClockTime = 18.08,
	-- 실제 서울 위도는 37.5 이지만 Roblox 태양 모델에서 노을을 화면 왼쪽-앞(서쪽, -X/-Z)에 두기 위해 조정
	GeographicLatitude = 8,
	DayNightCycle = false, -- true: 하루가 흐름(MinutesPerDay), 밤/낮에 맞춰 창문 조명 자동 전환
	MinutesPerDay = 24,
	NightFrom = 17.6, -- 이 시각부터 창문/가로등 점등
	NightTo = 6.4,
}

Config.Client = {
	IntroCinematic = true, -- 접속 시 7초 시네마틱(스킵 가능)
	Traffic = true, -- 다리·강변도로 차량 불빛 흐름
	TrafficDensity = 1.0,
	Beacons = true, -- 고층 항공장애등 깜빡임
	Boats = true, -- 유람선
}

return Config
