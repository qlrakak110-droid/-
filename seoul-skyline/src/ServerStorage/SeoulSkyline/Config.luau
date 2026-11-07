--!strict
-- SeoulSkyline / Config
-- 한강 잠실 야경 맵(롯데월드타워 모티브) 공용 설정: 좌표계, 레이아웃, 팔레트, 품질 옵션.
--
-- ── 좌표계 (studs) ───────────────────────────────────────────────────────────────────────────────
--   * 수면(Terrain Water 윗면) = Y 0.  강은 X 축을 따라 흐르고 강 중심선 = Z 0.
--   * 먼 쪽 강변(잠실, 도시/타워 쪽) = -Z.  가까운 쪽 강변(전망대·공원, 플레이어 스폰) = +Z.
--   * 대표 구도(히어로 카메라)는 +Z 강변에서 -Z 를 바라봄 → 화면 오른쪽 = +X, 왼쪽 = -X.
--   * 해는 -X 쪽으로 진다(Roblox 태양 모델): 화면 왼쪽 지평선이 노을빛.
--   * 실제 스케일: 1 stud = 0.3 m (Roblox 아바타 키 ≈ 5.5 stud ≈ 1.7 m 기준). 건물 높이·층고·도로 폭은 실측 기준.
--     롯데월드타워 555 m = 1850 stud, 오피스 층고 4.0 m, 아파트 층고 2.9 m(15~35층), 차로 폭 3.5 m.
--     강폭만 실제(≈1 km)보다 좁은 420 m(1400 stud)로 압축 — 사진 구도(망원 압축감)와 걸어서 건너는 플레이를 위해.
--
-- 모듈은 숫자를 하드코딩하지 말고 여기 값을 읽어 주세요(레이아웃이 바뀌어도 전체가 맞물리도록).

local Config = {}

Config.VERSION = "1.1.0"

-- 실제 스케일 환산 (모듈은 실측 m 값을 Config.m(미터) 로 stud 로 바꿔 쓰세요)
Config.METERS_PER_STUD = 0.3
function Config.m(meters: number): number
	return meters / 0.3
end
-- 실측 기준 (stud)
Config.Real = {
	OfficeFloor = 4.0 / 0.3, -- 오피스 층고 4.0 m  = 13.3
	HomeFloor = 2.9 / 0.3, -- 아파트 층고 2.9 m  = 9.7
	Lane = 3.5 / 0.3, -- 차로 폭 3.5 m     = 11.7
	StreetLamp = 10 / 0.3, -- 도로 가로등 10 m  = 33
	ParkLamp = 4.5 / 0.3, -- 공원 보안등 4.5 m = 15
	Railing = 1.1 / 0.3, -- 난간 1.1 m        = 3.7
	Tree = 11 / 0.3, -- 가로수/공원 나무 8~14 m (평균 11 m = 37)
}
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
	ShadowMinSize = 20,
	-- 빌드 중 task.wait() 간격(파트 수). 서버/커맨드 바 타임아웃 방지.
	YieldEvery = 600,
}

------------------------------------------------------------------------------------------------------
-- 레벨(높이) — 모든 모듈 공통
------------------------------------------------------------------------------------------------------
Config.Level = {
	Water = 0, -- 수면
	RiverBed = -40, -- 강바닥 12 m (지형 복셀 4 stud 격자에 맞춤)
	Promenade = 5, -- 한강공원 둔치(산책로·잔디) 높이 1.5 m
	Levee = 24, -- 제방 위 도로(강변북로/올림픽대로)와 도시 지면 7 m
	City = 24, -- 도시 블록 지면
}

------------------------------------------------------------------------------------------------------
-- 강 / 강변 띠 (Z 범위, 작은 값 → 큰 값)
------------------------------------------------------------------------------------------------------
Config.River = {
	HalfWidth = 700, -- 수면: Z -700 ~ +700 (강폭 420 m)
	XMin = -11600, -- 강물이 이어지는 X 범위(지평선까지 보이도록 넉넉히)
	XMax = 11600,
}

-- 먼 쪽(잠실) 강변: 수면 끝 → 둔치 공원 → 제방 사면 → 올림픽대로 → 도시
Config.FarBank = {
	WaterEdge = -700, -- 수면 경계 (계단식 호안)
	ParkFrom = -700, -- 둔치 공원 Z (Promenade 높이)
	ParkTo = -867,
	SlopeTo = -910, -- 제방 사면 끝(Levee 높이)
	RoadFrom = -910, -- 올림픽대로(왕복 8차로)
	RoadTo = -1000,
	CityFrom = -1035, -- 도시 시작
	CityTo = -11300, -- 지평선 도시 끝
}

-- 가까운 쪽(관람자) 강변: 수면 끝 → 산책로/잔디/숲 → 제방 사면 → 강변북로 → 도시(배경)
Config.NearBank = {
	WaterEdge = 700,
	ParkFrom = 700,
	ParkTo = 1267, -- 넓은 한강공원(숲·잔디·전망대)
	SlopeTo = 1317,
	RoadFrom = 1317, -- 강변북로
	RoadTo = 1408,
	CityFrom = 1450,
	CityTo = 8700,
}

------------------------------------------------------------------------------------------------------
-- 주요 랜드마크 배치
------------------------------------------------------------------------------------------------------
Config.Landmark = {
	-- 롯데월드타워 모티브 초고층 (정사각 평면, 위로 갈수록 곡선으로 가늘어짐)
	Tower = {
		Center = Vector3.new(-717, 24, -1967),
		BaseWidth = 290, -- 지상부 한 변 87 m
		TopWidth = 107, -- 크라운 시작부 한 변 32 m
		Height = 1500, -- 본체(크라운 시작) 높이 450 m, 지면 기준
		CrownHeight = 260, -- 랜턴 크라운 78 m
		SpireHeight = 90, -- 첨탑 → 총 1850 stud = 555 m (실제 롯데월드타워)
		Yaw = 34, -- 평면 회전(도) — 모서리가 카메라 쪽을 향하는 다이아몬드 실루엣 (45 이면 노을 해가 면에 정반사되어 번짐)
	},
	-- 저층부 몰(타워 앞 오른쪽): 곡면 지붕 파란 조명 건물 포함
	Mall = {
		Min = Vector2.new(-600, -1767), -- (X, Z)
		Max = Vector2.new(100, -1367),
	},
}

-- 다리(잠실대교 모티브): 강을 수직(Z 방향)으로 가로지름
Config.Bridge = {
	X = 417, -- 중심선 X (대표 구도에서 다리가 오른쪽 아래 → 타워 발치 쪽으로 대각선으로 보이도록)
	ZFrom = -1067, -- 먼 쪽 도시 도로와 연결
	ZTo = 1500, -- 가까운 쪽 도시 도로와 연결
	DeckTop = 57, -- 상판 윗면 높이 17 m (수면 위)
	Width = 120, -- 36 m: 차도 8차로(3.5 m) + 중앙분리대 + 보도
	PierSpacing = 160, -- 경간 48 m
}

-- 관람 전망대(스폰) — 사진 구도를 재현하는 위치
Config.Viewpoint = {
	-- 전망대 바닥(플레이어가 서는 곳)
	DeckCenter = Vector3.new(-67, 0, 1167), -- Y 는 Park 모듈이 DeckHeight 로 결정
	DeckHeight = 200, -- 60 m 전망대
	-- 히어로 카메라(사진 구도). 포토 스팟/인트로에서 사용.
	HeroCamPos = Vector3.new(133, 342, 1433),
	HeroCamLook = Vector3.new(-200, 383, -1667),
	HeroFov = 62,
}

------------------------------------------------------------------------------------------------------
-- 구역 분할 (도시 생성기들이 겹치지 않도록 Kit.reserve 로 발자국을 예약)
--   Landmark → Skyline → Bridge/Riverside/Park → Apartments → CityCarpet 순서로 빌드됨.
------------------------------------------------------------------------------------------------------
Config.Zones = {
	-- 먼 쪽 강변의 "히어로" 고층 클러스터 (Skyline 모듈)
	SkylineLeft = { XMin = -2833, XMax = -1267, ZMin = -2500, ZMax = -1267 },
	SkylineMid = { XMin = -417, XMax = 233, ZMin = -2917, ZMax = -1967 },
	SkylineRight = { XMin = 300, XMax = 1750, ZMin = -2250, ZMax = -1200 },
	-- 아파트 단지 띠 (Apartments 모듈) — 먼 쪽 / 가까운 쪽
	ApartmentsFar = { XMin = -7000, XMax = 7000, ZMin = -3833, ZMax = -1067 },
	ApartmentsNear = { XMin = -5333, XMax = 5333, ZMin = 1467, ZMax = 3167 },
	-- LOD 도시 카펫 (CityCarpet 모듈)
	CarpetFarMid = { XMin = -10833, XMax = 10833, ZMin = -6667, ZMax = -3833 },
	CarpetFarFar = { XMin = -15000, XMax = 15000, ZMin = -11333, ZMax = -6667 },
	CarpetNear = { XMin = -10000, XMax = 10000, ZMin = 3167, ZMax = 8667 },
	-- 원경 산 능선
	MountainsFar = { XMin = -18333, XMax = 18333, Z = -13667 },
	MountainsNear = { XMin = -15000, XMax = 15000, Z = 10667 },
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
