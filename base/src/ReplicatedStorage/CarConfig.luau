--[[
	📁 위치: ReplicatedStorage  >  ModuleScript  (이름: CarConfig)
	게임 전체 설정값. 숫자만 바꿔서 밸런스 조절하면 됩니다.
]]

local Config = {}

-- 💰 경제
Config.START_MONEY = 15000        -- 처음 시작 돈
Config.STARTER_CAR = "Hatch"      -- 처음에 주는 차
Config.SALARY = 200               -- 월급
Config.SALARY_INTERVAL = 120      -- 월급 주기(초)
Config.FUEL_PRICE = 30            -- 연료 1% 당 가격
Config.REPAIR_PRICE = 40          -- 내구도 1 당 수리비
Config.PARK_REWARD = 300          -- 주차 성공 보상
Config.PARK_COOLDOWN = 60         -- 주차 보상 쿨타임(초)
Config.TAXI_BASE = 3000           -- 택시 기본요금
Config.TAXI_PER_STUD = 4          -- 택시 거리당 요금
Config.SUMMON_COOLDOWN = 8        -- 내 차 부르기 쿨타임

-- 🏙️ 도시 (자동 생성)
Config.CITY_N = 4                 -- 블록 개수 (4 x 4)
Config.CITY_S = 160               -- 블록 간격(스터드)
Config.ROAD_W = 32                -- 도로 폭
Config.LANE = 7                   -- 차선 중심 오프셋 (우측통행)

-- 🚗 교통 NPC
Config.TRAFFIC_COUNT = 10         -- NPC 차량 수 (폰 렉 걸리면 줄이세요)
Config.TRAFFIC_DRIVERS = true     -- NPC 차 안에 운전자 표시
Config.TRAFFIC_SPEED = 55         -- NPC 최고속도 (스터드/초 ≈ km/h)

-- 🔊 소리 (원하는 오디오 ID 넣기, 비우면 소리 없음)
Config.ENGINE_SOUND_ID = ""       -- 예: "rbxassetid://123456"
Config.HORN_SOUND_ID = ""

-- 🚙 차량 목록
-- Style: sedan / hatch / suv / sports  (외형 모양)
-- MaxSpeed: 스터드/초 (≈ km/h),  Accel: 가속력,  Grip: 접지력
Config.Cars = {
	Hatch = {
		Name = "해치백", Price = 12000, Style = "hatch",
		Color = Color3.fromRGB(70, 130, 200), Interior = Color3.fromRGB(45, 45, 50),
		MaxSpeed = 115, Accel = 26, Grip = 9, FuelUse = 0.8,
	},
	Sedan = {
		Name = "세단", Price = 20000, Style = "sedan",
		Color = Color3.fromRGB(30, 32, 38), Interior = Color3.fromRGB(150, 120, 90),
		MaxSpeed = 135, Accel = 30, Grip = 10, FuelUse = 1.0,
	},
	SUV = {
		Name = "SUV", Price = 32000, Style = "suv",
		Color = Color3.fromRGB(235, 235, 235), Interior = Color3.fromRGB(40, 40, 44),
		MaxSpeed = 125, Accel = 28, Grip = 9, FuelUse = 1.3,
	},
	Sports = {
		Name = "스포츠카", Price = 60000, Style = "sports",
		Color = Color3.fromRGB(200, 25, 30), Interior = Color3.fromRGB(25, 25, 28),
		MaxSpeed = 175, Accel = 42, Grip = 12, FuelUse = 1.6,
	},
	Taxi = {
		Name = "택시", Price = nil, Style = "sedan", Taxi = true,
		Color = Color3.fromRGB(235, 140, 40), Interior = Color3.fromRGB(60, 60, 65),
		MaxSpeed = 110, Accel = 24, Grip = 9, FuelUse = 1.0,
	},
}

-- 매장에 진열되는 순서
Config.SHOP_ORDER = { "Hatch", "Sedan", "SUV", "Sports" }

-- NPC 차량 색상 랜덤
Config.TRAFFIC_COLORS = {
	Color3.fromRGB(240, 240, 240), Color3.fromRGB(25, 25, 30), Color3.fromRGB(120, 125, 130),
	Color3.fromRGB(160, 30, 35), Color3.fromRGB(40, 70, 140), Color3.fromRGB(190, 190, 195),
	Color3.fromRGB(60, 90, 70), Color3.fromRGB(110, 80, 60),
}

Config.GW_INTEGRATED = true
return Config
